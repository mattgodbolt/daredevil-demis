// Parse src/levels.asm the same way the engine walks it, so the test harness
// and the game can never drift apart.
import { readFileSync } from "fs";

function constants() {
    const c = { MV_PATROL: 0, MV_HOP: 1, KIND_HAZ: 0, KIND_BONUS: 1 };
    for (const line of readFileSync("src/defs.asm", "utf8").split("\n")) {
        const m = line.replace(/\\.*$/, "").match(/^\s*(SPR_\w+)\s*=\s*(\d+)/);
        if (m) c[m[1]] = parseInt(m[2]);
    }
    return c;
}

export function parseLevels() {
    const c = constants();
    const src = readFileSync("src/levels.asm", "utf8");
    const shoots = [];
    for (let n = 1; n <= 4; n++) {
        const start = src.indexOf(`.shoot${n}\n`);
        const end = n < 4 ? src.indexOf(`.shoot${n + 1}\n`) : src.length;
        const bytes = [];
        for (const line of src.slice(start, end).split("\n")) {
            const m = line.replace(/\\.*$/, "").match(/^\s*EQUB\s+(.*)$/);
            if (!m) continue;
            for (const tok of m[1].split(",").map((t) => t.trim()).filter(Boolean)) {
                const v = /^&/.test(tok) ? parseInt(tok.slice(1), 16)
                    : /^\d+$/.test(tok) ? parseInt(tok)
                    : c[tok];
                if (v === undefined) throw new Error(`shoot${n}: unknown token "${tok}"`);
                bytes.push(v);
            }
        }
        // Walk it exactly as setup_shoot does.
        let p = 8;
        const lanes = [];
        for (let l = 0; l < 4; l++) {
            const gaps = [];
            let count = bytes[p++];
            for (let i = 0; i < count; i++) { gaps.push([bytes[p], bytes[p + 1]]); p += 2; }
            const objs = [];
            count = bytes[p++];
            for (let i = 0; i < count; i++) { objs.push({ cell: bytes[p], spr: bytes[p + 1], kind: bytes[p + 2] }); p += 3; }
            lanes.push({ gaps, objs });
        }
        const movers = [];
        let count = bytes[p++];
        for (let i = 0; i < count; i++) {
            movers.push({ lane: bytes[p], type: bytes[p + 1], cell: bytes[p + 2] });
            p += 7;
        }
        if (p !== bytes.length) throw new Error(`shoot${n}: walked ${p} of ${bytes.length} bytes`);
        shoots.push({ lanes, movers });
    }
    return shoots;
}
