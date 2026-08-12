#!/usr/bin/env node
/**
 * Drive the jsbeeb MCP server from the command line.
 *
 * We talk to the real MCP server over stdio (the same one Claude Code uses),
 * so what we test here is exactly what the MCP tools would do.
 *
 * Usage:
 *   node tools/beeb.js --disc build/demis.ssd --secs 6 --shot shots/a.png
 *   node tools/beeb.js --disc build/demis.ssd --secs 3 \
 *        --keys 'RETURN:0.5,X:3.0,SPACE:0.2' --shot shots/b.png
 *   node tools/beeb.js --disc build/demis.ssd --secs 3 --peek 0x0070:16
 *
 * --keys is a comma separated list of  KEY:hold_seconds  played in order,
 * each preceded by a short gap. Use KEY:hold@delay to wait `delay` seconds
 * before pressing.
 */
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { writeFileSync, mkdirSync } from "fs";
import { dirname, resolve } from "path";

// Talk to the published jsbeeb MCP server by default; point JSBEEB_MCP at a
// local server.js to test against a working copy.
const MCP = process.env.JSBEEB_MCP
    ? { command: "node", args: [process.env.JSBEEB_MCP] }
    : { command: "npx", args: ["-y", "jsbeeb-mcp"] };

function arg(name, dflt) {
    const i = process.argv.indexOf(`--${name}`);
    return i >= 0 ? process.argv[i + 1] : dflt;
}
function flag(name) {
    return process.argv.includes(`--${name}`);
}

const text = (r) => r.content.find((c) => c.type === "text")?.text ?? "";
const image = (r) => r.content.find((c) => c.type === "image");

async function main() {
    const disc = resolve(arg("disc", "build/demis.ssd"));
    const secs = parseFloat(arg("secs", "6"));
    const shot = arg("shot", null);
    const keys = arg("keys", null);
    const peek = arg("peek", null);
    const model = arg("model", "B-DFS1.2");

    const transport = new StdioClientTransport(MCP);
    const client = new Client({ name: "demis-harness", version: "1.0.0" });
    await client.connect(transport);

    const call = async (name, args) => {
        const r = await client.callTool({ name, arguments: args });
        if (r.isError) throw new Error(`${name}: ${JSON.stringify(r.content)}`);
        return r;
    };

    const { session_id } = JSON.parse(text(await call("create_machine", { model })));
    await call("boot_disc", { session_id, image_path: disc });

    const CPS = 2_000_000; // 2MHz
    const runFor = (s) => call("run_for_cycles", { session_id, cycles: Math.max(1, Math.round(s * CPS)) });

    await runFor(secs);

    if (keys) {
        for (const spec of keys.split(",")) {
            const [keyPart, delayPart] = spec.split("@");
            const [key, hold] = keyPart.split(":");
            if (delayPart) await runFor(parseFloat(delayPart));
            await call("key_down", { session_id, key });
            await runFor(parseFloat(hold || "0.2"));
            await call("key_up", { session_id, key });
            await runFor(0.15);
        }
    }

    const out = text(await call("run_for_cycles", { session_id, cycles: 40000 }));
    console.log("OUTPUT:", out.slice(0, 800));

    const dump = arg("dump", null);
    if (dump) {
        // MODE 5 screen is 10K at &5800; read_memory caps at 256 bytes a go.
        const bytes = [];
        for (let a = 0x5800; a < 0x8000; a += 256) {
            const r = JSON.parse(text(await call("read_memory", { session_id, address: a, length: 256 })));
            bytes.push(...r.bytes);
        }
        mkdirSync(dirname(resolve(dump)), { recursive: true });
        writeFileSync(resolve(dump), Buffer.from(bytes));
        console.log("DUMP:", resolve(dump), bytes.length, "bytes");
    }

    if (peek) {
        for (const p of peek.split(",")) {
            const [addr, len] = p.split(":");
            const r = JSON.parse(
                text(await call("read_memory", { session_id, address: parseInt(addr), length: parseInt(len || "16") })),
            );
            console.log(r.hexDump);
        }
    }

    const regs = text(await call("read_registers", { session_id }));
    console.log("REGS:", regs);

    if (shot) {
        const img = image(await call("screenshot", { session_id, active_only: true }));
        mkdirSync(dirname(resolve(shot)), { recursive: true });
        writeFileSync(resolve(shot), Buffer.from(img.data, "base64"));
        console.log("SHOT:", resolve(shot));
    }

    await call("destroy_machine", { session_id });
    await client.close();
    process.exit(0);
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
