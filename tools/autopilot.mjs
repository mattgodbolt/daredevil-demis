/**
 * Plays DAREDEVIL DEMIS by watching the game's own variables through the
 * jsbeeb MCP server: holds accelerate, and jumps when a known hazard is
 * coming up. Used to prove a whole shoot can actually be completed.
 *
 *   node tools/autopilot.mjs build/demis.ssd [frames]
 */
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { readFileSync, writeFileSync, mkdirSync } from "fs";
import { resolve, dirname } from "path";

// Talk to the published jsbeeb MCP server by default; point JSBEEB_MCP at a
// local server.js to test against a working copy.
const MCP = process.env.JSBEEB_MCP
    ? { command: "node", args: [process.env.JSBEEB_MCP] }
    : { command: "npx", args: ["-y", "jsbeeb-mcp"] };
const text = (r) => r.content.find((c) => c.type === "text")?.text ?? "";
const image = (r) => r.content.find((c) => c.type === "image");

import { parseLevels } from "./levelparse.mjs";
const LEVELS = parseLevels();
console.log("levels parsed:", LEVELS.map((sh, i) =>
    `shoot${i + 1}=[${sh.lanes.map((l) => l.objs.length).join(",")}] movers=${sh.movers.length}`).join("  "));

const sym = {};
for (const line of readFileSync("build/symbols.txt", "utf8").split("\n")) {
    const m = line.match(/^SYM (\w+)&([0-9A-F]+)/);
    if (m) sym[m[1]] = parseInt(m[2], 16);
}

const transport = new StdioClientTransport(MCP);
const client = new Client({ name: "autopilot", version: "1" });
await client.connect(transport);
const call = async (n, a) => {
    const r = await client.callTool({ name: n, arguments: a });
    if (r.isError) throw new Error(JSON.stringify(r.content));
    return r;
};

const disc = resolve(process.argv[2] || "build/demis.ssd");
const maxFrames = parseInt(process.argv[3] || "2000");
// Optional: --capture <fromFrame> <toFrame> <dir> to save one PNG per frame.
const capIdx = process.argv.indexOf("--capture");
const capFrom = capIdx > 0 ? parseInt(process.argv[capIdx + 1]) : Infinity;
const capTo = capIdx > 0 ? parseInt(process.argv[capIdx + 2]) : -1;
const capDir = capIdx > 0 ? process.argv[capIdx + 3] : "";
const capLog = [];
const { session_id } = JSON.parse(text(await call("create_machine", { model: "B-DFS1.2" })));
await call("boot_disc", { session_id, image_path: disc });
const FRAME = 40000;         // 312.5 scanlines: the BBC interlaces by default
const run = (s) => call("run_for_cycles", { session_id, cycles: Math.max(1, Math.round(s * 2e6)) });
const runFrame = () => call("run_for_cycles", { session_id, cycles: FRAME });
const peek = async (a, n = 1) =>
    JSON.parse(text(await call("read_memory", { session_id, address: a, length: n }))).bytes;
const snap = async (f) => {
    mkdirSync(dirname(resolve(f)), { recursive: true });
    const img = image(await call("screenshot", { session_id, active_only: true }));
    writeFileSync(f, Buffer.from(img.data, "base64"));
    console.log("SHOT", f);
};

await run(3.0);
// Tap SPACE until the engine has actually started a shoot (lives becomes 3).
let started = false;
for (let i = 0; i < 40 && !started; i++) {
    await call("key_down", { session_id, key: "SPACE" });
    await run(0.15);
    await call("key_up", { session_id, key: "SPACE" });
    await run(0.35);
    const [lives] = JSON.parse(text(await call("read_memory", { session_id, address: sym.lives, length: 1 }))).bytes;
    const [flag] = JSON.parse(text(await call("read_memory", { session_id, address: sym.game_flag, length: 1 }))).bytes;
    if (lives > 0 && lives <= 3 && flag === 0) started = true;
}
console.log(started ? "game started" : "NEVER STARTED");
await call("key_down", { session_id, key: "X" });          // accelerator wedged open

let braking = false, jumpHeld = false, lastLane = -1, lastShoot = -1, crashes = 0, lastLives = 3;
const seen = new Set();
for (let f = 0; f < maxFrames; f++) {
    const [shoot, , lane] = await peek(sym.shoot, 3);
    const [px] = await peek(sym.px_hi);
    const [airborne] = await peek(sym.airborne);
    const [lives] = await peek(sym.lives);
    if (f < 8 || f % 100 === 0) {
        const [flag] = await peek(sym.game_flag);
        const [py] = await peek(sym.py_hi);
        const regs = JSON.parse(text(await call("read_registers", { session_id })));
        console.log(`  f${f} shoot=${shoot} lane=${lane} px=${px} py=${py} air=${airborne} lives=${lives} flag=${flag} pc=${regs.pcHex}`);
    }
    if (lives !== lastLives) { crashes++; lastLives = lives; console.log(`  CRASH at shoot ${shoot+1} lane ${lane+1} px=${px} py=${(await peek(sym.py_hi))[0]} air=${airborne}`); }
    if (shoot !== lastShoot || lane !== lastLane) {
        console.log(`frame ${f}: shoot ${shoot + 1} lane ${lane + 1}  lives ${lives}`);
        lastShoot = shoot; lastLane = lane;
        seen.add(`${shoot}:${lane}`);
    }
    // Jump if a hazard, or the near edge of a gap, is the right distance ahead.
    const L = LEVELS[shoot]?.lanes[lane];
    const [mact, mtype, mcell, mphase] = [
        await peek(sym.mv_active, 3), await peek(sym.mv_type, 3),
        await peek(sym.mv_cell, 3), await peek(sym.mv_phase, 3),
    ];
    // A hopper is only dangerous while it is low, and jumping puts you at
    // exactly its height when it is high -- so you wait for it, you don't
    // jump it. Patrols stay on the ground, so those you jump.
    let hold = false;
    for (let i = 0; i < 3; i++) {
        if (!mact[i]) continue;
        const d = mcell[i] * 4 - px;
        if (mtype[i] === 1) {
            const HOP = [0, 0, 4, 10, 16, 20, 22, 22, 22, 22, 20, 16, 10, 4, 0, 0];
            const lift = HOP[mphase[i] & 15];
            // Only set off through the gap at the START of the hop's dwell,
            // so it is still up when we come out the far side. Once committed
            // (d < 8) keep going -- stopping underneath it is fatal.
            const goNow = lift >= 16 && mphase[i] >= 4 && mphase[i] <= 8;
            if (d >= 8 && d < 26 && !goNow) hold = true;
        }
    }
    const points = [
        ...(L?.objs ?? []).filter((o) => o.kind === 0).map((o) => o.cell * 4),
        ...(L?.gaps ?? []).map(([c, n]) => [c * 4, (c + n) * 4 - 4]).flat(),
        ...mact.map((a, i) => (a && mtype[i] === 0 ? mcell[i] * 4 : null)).filter((v) => v !== null),
    ].sort((a, b) => a - b);
    const groups = [];
    for (const t of points) {
        const g = groups[groups.length - 1];
        if (g && t - g[1] <= 24) g[1] = t; else groups.push([t, t]);
    }
    // The arc shelters roughly 33 pixels; place the take-off so the whole
    // group sits inside it.
    const want = !airborne && !hold && groups.some(([gs, ge]) => gs - px >= 14 && gs - px <= 26 - (ge - gs));
    if (hold !== braking) {
        await call(hold ? "key_up" : "key_down", { session_id, key: "X" });
        await call(hold ? "key_down" : "key_up", { session_id, key: "Z" });
        braking = hold;
    }
    if (want && !jumpHeld) { await call("key_down", { session_id, key: "SPACE" }); jumpHeld = true; }
    else if (!want && jumpHeld) { await call("key_up", { session_id, key: "SPACE" }); jumpHeld = false; }
    await runFrame();
    if (f >= capFrom && f < capTo) {
        const tag = String(f).padStart(3, "0");
        await snap(`${capDir}/f${tag}.png`);
        // Record where the game thinks everything is, so the capture can be
        // checked against what the beam actually painted.
        const [px2] = await peek(sym.px_hi);
        const [py2] = await peek(sym.py_hi);
        const [lane2] = await peek(sym.lane);
        capLog.push({ f, px: px2, py: py2, lane: lane2, air: airborne });
        if (process.env.DUMPMEM) {
            const bytes = [];
            for (let a = 0x5800; a < 0x8000; a += 256)
                bytes.push(...JSON.parse(text(await call("read_memory", { session_id, address: a, length: 256 }))).bytes);
            writeFileSync(`${capDir}/f${tag}.bin`, Buffer.from(bytes));
        }
    }
    if (lives === 0) { console.log(`frame ${f}: OUT OF RESEARCHERS`); break; }
}
const [s0, s1, s2] = await peek(sym.score, 3);
console.log("score  $" + [s2, s1, s0].map((b) => b.toString(16).padStart(2, "0")).join(""));
console.log("crashes", crashes, " lanes reached", [...seen].sort().join(" "));
if (capLog.length) writeFileSync(`${capDir}/frames.json`, JSON.stringify(capLog, null, 1));
await snap("shots/auto_final.png");
await run(4.0);                      // let the game-over screen come up
await snap("shots/auto_end.png");
await call("destroy_machine", { session_id });
process.exit(0);
