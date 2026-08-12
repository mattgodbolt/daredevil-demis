import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
const t = r => r.content.find(x=>x.type==="text")?.text ?? "";
const c = new Client({name:"tim",version:"1"});
await c.connect(new StdioClientTransport({command:"npx",args:["-y","jsbeeb-mcp"]}));
const call = async (n,a) => { const r = await c.callTool({name:n,arguments:a}); if(r.isError) throw new Error(JSON.stringify(r.content)); return r; };
const {session_id} = JSON.parse(t(await call("create_machine",{model:"B-DFS1.2"})));
// TIME is the OS's 100Hz clock, driven by System VIA T1 off the CPU clock:
// 1 centisecond = 20000 cycles exactly. So counting N vsyncs and reading TIME
// converts frames straight into CPU cycles, with no code of mine involved.
// *TV's second parameter controls interlace: 0 = on (the default), 1 = off.
// It takes effect at the next MODE change.
for (const [label, tv] of [["interlace ON  (default)", "0,0"], ["interlace OFF (*TV 0,1)", "0,1"]]) {
  await call("load_basic",{session_id,source:
`10 *TV ${tv}\n20 MODE 5\n30 N%=500\n40 T%=TIME\n50 FOR I%=1 TO N%\n60 *FX19\n70 NEXT\n80 D%=TIME-T%\n90 MODE 7\n100 PRINT "RESULT ";D%;" ";(D%*20000)/N%\n`});
  await call("type_input",{session_id,text:"RUN"});
  const out = JSON.parse(t(await call("run_until_prompt",{session_id,timeout_secs:180})));
  const line = out.screenText.split("\n").find(l=>l.includes("RESULT")) || "(no result)";
  const m = line.match(/RESULT\s+(\d+)\s+([\d.]+)/);
  console.log(`${label}: ${m ? m[1]+" cs for 500 frames -> "+m[2]+" cycles/frame" : line}`);
}
await call("destroy_machine",{session_id}); process.exit(0);
