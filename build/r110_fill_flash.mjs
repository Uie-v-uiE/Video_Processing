// build/r110_fill_flash.mjs —— 采纳笔之后把"刷板时刻 / 板读结温 / 板上证据件名"回填（第二笔）。
// 与 r110_rotate_docs.mjs 同一套纪律：每条规则必须恰好命中一次，任何一条拒 ⇒ 整批不落盘。
import { readFileSync, writeFileSync } from 'node:fs';
const APPLY = process.argv.includes('--apply');
const RULES = [
  ['README.md', '首页身份句回填刷板时刻',
     '板上这一版 r110（bit `2bf95588978f`，刷板时刻待回填）',
     '板上这一版 r110，2026-10-03 07:51 三步 JTAG 刷入，`bit 2bf95588978f`', 1],
  ['README.md', '首页证据件对回 r110', 'build/r109_gates.txt', 'build/r110_gates.txt', 1],
  ['README.md', '首页板级验收件对回 r110', 'build/r109_board_verify_console.txt', 'build/r110_board_verify_console.txt', 2],
  ['README.en.md', '首页身份句回填刷板时刻',
     'r110 \\(flash time to be filled after the three-step JTAG chain\\)',
     'r110, flashed at 07:51 on 2026-10-03 by the three-step JTAG chain', 1],
  ['README.en.md', '首页证据件对回 r110', 'build/r109_gates.txt', 'build/r110_gates.txt', 1],
  ['README.en.md', '首页板级验收件对回 r110', 'build/r109_board_verify_console.txt', 'build/r110_board_verify_console.txt', 2],
  ['data/metrics.csv', '结温行的读数', ',59\\.3 – 59\\.6,℃,板上这一版 \\*\\*r109\\*\\*（bit md5 `21227687e925`）2026-10-03 02:10 三步 JTAG 刷入后',
     ',60.6 – 60.7,℃,板上这一版 **r110**（bit md5 `2bf95588978f`）2026-10-03 07:51 三步 JTAG 刷入后', 1],
  ['data/metrics.csv', '结温行的件名', 'build/r109_flash_console.txt', 'build/r110_flash_console.txt', 1],
];
let bad = 0, hit = 0; const cache = {};
for (const [f, name, src, rep, want] of RULES) {
    if (!(f in cache)) cache[f] = readFileSync(f, 'utf8');
    const re = new RegExp(src, 'g');
    const n = (cache[f].match(re) || []).length;
    if (n !== want) { console.log(`REFUSE ${name}：${f} 命中 ${n}（期望 ${want}）`); bad++; continue; }
    if (APPLY) cache[f] = cache[f].replace(re, rep);
    hit++; console.log(`OK   ${name} ×${n}`);
}
if (APPLY && bad === 0) for (const f of Object.keys(cache)) { writeFileSync(f, cache[f]); console.log(`WROTE ${f}`); }
else if (APPLY) console.log('NO-WRITE 有规则被拒');
process.exit(bad ? 1 : 0);
