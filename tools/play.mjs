// Play a scripted run and grab several screenshots, through the jsbeeb MCP server.
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { writeFileSync } from "fs";
// Talk to the published jsbeeb MCP server by default; point JSBEEB_MCP at a
// local server.js to test against a working copy.
const MCP = process.env.JSBEEB_MCP
    ? { command: "node", args: [process.env.JSBEEB_MCP] }
    : { command: "npx", args: ["-y", "jsbeeb-mcp"] };
const text = (r) => r.content.find((c) => c.type === "text")?.text ?? "";
const image = (r) => r.content.find((c) => c.type === "image");
const transport = new StdioClientTransport(MCP);
const client = new Client({ name: "play", version: "1" });
await client.connect(transport);
const call = async (n, a) => { const r = await client.callTool({ name: n, arguments: a }); if (r.isError) throw new Error(JSON.stringify(r.content)); return r; };

import { resolve } from "path";
const disc = resolve(process.argv[2]);
const script = process.argv[3];          // e.g. "X:down,2.0,SPACE:tap,1.0"
const prefix = process.argv[4] || "shots/p";
const { session_id } = JSON.parse(text(await call("create_machine", { model: "B-DFS1.2" })));
await call("boot_disc", { session_id, image_path: disc });
const run = (s) => call("run_for_cycles", { session_id, cycles: Math.max(1, Math.round(s * 2e6)) });
await run(3.0);                          // DFS boot + *RUN Code

let shot = 0;
const snap = async (tag) => {
  const img = image(await call("screenshot", { session_id, active_only: true }));
  const f = `${prefix}${shot++}_${tag}.png`;
  writeFileSync(f, Buffer.from(img.data, "base64"));
  console.log("SHOT", f);
};

for (const step of script.split(",")) {
  if (step.startsWith("!")) { await snap(step.slice(1)); continue; }
  if (step.startsWith("#")) {
    const bytes = [];
    for (let a = 0x5800; a < 0x8000; a += 256)
      bytes.push(...JSON.parse(text(await call("read_memory", { session_id, address: a, length: 256 }))).bytes);
    writeFileSync(`${prefix}${step.slice(1)}.bin`, Buffer.from(bytes));
    console.log("DUMP", `${prefix}${step.slice(1)}.bin`);
    continue;
  }
  const [key, action] = step.split(":");
  if (!action) { await run(parseFloat(key)); continue; }
  if (action === "down") await call("key_down", { session_id, key });
  else if (action === "up") await call("key_up", { session_id, key });
  else { await call("key_down", { session_id, key }); await run(0.1); await call("key_up", { session_id, key }); }
}
console.log("REGS", text(await call("read_registers", { session_id })));
const mem = (a, n) => call("read_memory", { session_id, address: a, length: n }).then((r) => JSON.parse(text(r)).hexDump);
console.log(await mem(0x2636, 24));
await call("destroy_machine", { session_id });
process.exit(0);
