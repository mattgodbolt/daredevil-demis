import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
// Talk to the published jsbeeb MCP server by default; point JSBEEB_MCP at a
// local server.js to test against a working copy.
const MCP = process.env.JSBEEB_MCP
    ? { command: "node", args: [process.env.JSBEEB_MCP] }
    : { command: "npx", args: ["-y", "jsbeeb-mcp"] };
const text = (r) => r.content.find((c) => c.type === "text")?.text ?? "";
const transport = new StdioClientTransport(MCP);
const client = new Client({ name: "keytest", version: "1" });
await client.connect(transport);
const call = async (n, a) => { const r = await client.callTool({ name: n, arguments: a }); if (r.isError) throw new Error(JSON.stringify(r.content)); return r; };
const { session_id } = JSON.parse(text(await call("create_machine", { model: "B-DFS1.2" })));
const run = (s) => call("run_for_cycles", { session_id, cycles: Math.round(s * 2e6), clear: false });
await call("load_basic", { session_id, source:
  `10 FOR J=1 TO 2\n20 FOR I%=-128 TO -1\n30 IF INKEY(I%) THEN PRINT I%\n40 NEXT\n50 NEXT\n60 PRINT "DONE"\n` });
for (const key of process.argv.slice(2)) {
  await call("type_input", { session_id, text: "RUN" });
  await run(0.4);
  await call("key_down", { session_id, key });
  const out = JSON.parse(text(await call("run_until_prompt", { session_id, timeout_secs: 60 })));
  await call("key_up", { session_id, key });
  await run(0.3);
  const nums = [...new Set(out.screenText.match(/-\d+/g) || [])].join(" ");
  console.log(key.padEnd(7), "=>", nums || "(none)");
}
await call("destroy_machine", { session_id });
process.exit(0);
