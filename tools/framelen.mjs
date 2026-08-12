// Measure the emulated frame length by counting the engine's own vsyncs.
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { readFileSync } from "fs";
import { resolve } from "path";
const MCP = process.env.JSBEEB_MCP
    ? { command: "node", args: [process.env.JSBEEB_MCP] }
    : { command: "npx", args: ["-y", "jsbeeb-mcp"] };
const text = (r) => r.content.find((c) => c.type === "text")?.text ?? "";
const client = new Client({ name: "framelen", version: "1" });
await client.connect(new StdioClientTransport(MCP));
const call = async (n, a) => { const r = await client.callTool({ name: n, arguments: a }); if (r.isError) throw new Error(JSON.stringify(r.content)); return r; };
const sym = {};
for (const l of readFileSync("build/symbols.txt", "utf8").split("\n")) {
    const m = l.match(/^SYM (\w+)&([0-9A-F]+)/); if (m) sym[m[1]] = parseInt(m[2], 16);
}
const { session_id } = JSON.parse(text(await call("create_machine", { model: "B-DFS1.2" })));
await call("boot_disc", { session_id, image_path: resolve("build/demis.ssd") });
await call("run_for_cycles", { session_id, cycles: 6e6 });
const peek = async () => JSON.parse(text(await call("read_memory", { session_id, address: sym.vsync_count, length: 1 }))).bytes[0];
for (const cycles of [39936 * 100, 40000 * 100, 39936 * 200]) {
    const a = await peek();
    await call("run_for_cycles", { session_id, cycles });
    const b = await peek();
    const n = (b - a + 256) % 256;
    console.log(`${cycles} cycles -> ${n} vsyncs -> ${(cycles / n).toFixed(1)} cycles/frame`);
}
await call("destroy_machine", { session_id });
process.exit(0);
