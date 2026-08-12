/**
 * Capture one screenshot per emulated frame, so a sequence can be flicked
 * through or diffed.  A BBC frame is 312 scanlines x 64us = 19968us, i.e.
 * 39936 cycles at 2MHz -- NOT 40000, which drifts by 64 cycles a frame.
 *
 *   node tools/frames.mjs <disc.ssd> <settle-secs> <n-frames> <out-dir> [keys]
 *   keys: comma list of KEY:downFrame:upFrame, e.g. "X:0:999,SPACE:40:44"
 */
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { writeFileSync, mkdirSync } from "fs";
import { resolve } from "path";

const MCP = process.env.JSBEEB_MCP
    ? { command: "node", args: [process.env.JSBEEB_MCP] }
    : { command: "npx", args: ["-y", "jsbeeb-mcp"] };
const FRAME = 39936;

const text = (r) => r.content.find((c) => c.type === "text")?.text ?? "";
const image = (r) => r.content.find((c) => c.type === "image");

const client = new Client({ name: "frames", version: "1" });
await client.connect(new StdioClientTransport(MCP));
const call = async (n, a) => {
    const r = await client.callTool({ name: n, arguments: a });
    if (r.isError) throw new Error(JSON.stringify(r.content));
    return r;
};

const disc = resolve(process.argv[2]);
const settle = parseFloat(process.argv[3] ?? "4");
const count = parseInt(process.argv[4] ?? "50");
const outDir = resolve(process.argv[5] ?? "shots/frames");
const keys = (process.argv[6] ?? "").split(",").filter(Boolean).map((k) => {
    const [key, down, up] = k.split(":");
    return { key, down: parseInt(down), up: parseInt(up) };
});

mkdirSync(outDir, { recursive: true });
const { session_id } = JSON.parse(text(await call("create_machine", { model: "B-DFS1.2" })));
await call("boot_disc", { session_id, image_path: disc });
await call("run_for_cycles", { session_id, cycles: Math.round(settle * 2e6) });

for (let f = 0; f < count; f++) {
    for (const k of keys) {
        if (k.down === f) await call("key_down", { session_id, key: k.key });
        if (k.up === f) await call("key_up", { session_id, key: k.key });
    }
    await call("run_for_cycles", { session_id, cycles: FRAME });
    const img = image(await call("screenshot", { session_id, active_only: true }));
    writeFileSync(`${outDir}/f${String(f).padStart(3, "0")}.png`, Buffer.from(img.data, "base64"));
}
console.log(`captured ${count} frames to ${outDir}`);
await call("destroy_machine", { session_id });
process.exit(0);
