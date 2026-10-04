// build/r113_fill_flash2.mjs —— 回填之后的**第二把修正**：把回填自己造成的两处形状错纠回来。
// 起因（都是今天我自己造的，逐条有凭据）：
//  ① `\|` 落进首页表格行首：r113_rotate_docs.mjs 的 WNS 那条规则把**替换文**写成了 `'\\| 全设计 setup WNS \\|'`。
//     src 是正则所以要 `\\|`，rep 是字面量所以 `\\|` 直接产出 `\|`。凭据：`git show HEAD~3:README.md | sed -n 56p`
//     行首是 `| 全设计 setup WNS`，HEAD 那份变成 `\| 全设计 setup WNS`。后果不只是难看：
//     `src/host/metric_recheck.mjs:238` 找首页行用的是 `ls[i].startsWith('|')` ⇒ 这一格从"被对账"变成"判红"
//     （门禁里那 2 条 metric 红就是这个，不是数字错）。
//  ② 点名件路径不存在：回填把 `build/r110_board_verify_console.txt` 换成 `build/r113_board_verify_console.txt`，
//     而这一轮的板级校验控制台实际写在 `build/evidence/` 下 ⇒ doc_currency D4c「点名的凭据盘上没有」×4。
//     修法选"文档对回真实路径"而不是"把证据复制一份到 build/"：同一份内容抄到两处正是 D6/#225 一直在防的漂移。
// 纪律照旧：每条规则必须恰好命中期望次数，任何一条拒 ⇒ 整批不落盘；匹配一律用字面量（原因见 r113_fill_flash.mjs 头注）。
import { readFileSync, writeFileSync } from 'node:fs';
const APPLY = process.argv.includes('--apply');
const RULES = [
  ['README.md', '① 首页 WNS 行首去掉反斜杠', '\\| 全设计 setup WNS \\| **0.445 ns**', '| 全设计 setup WNS | **0.445 ns**', 1],
  ['README.md', '② 板级校验件对回真实路径', 'build/r113_board_verify_console.txt', 'build/evidence/r113_board_verify_console.txt', 2],
  ['readme.en.md', '① 首页 WNS 行首去掉反斜杠', '\\| Design-wide setup WNS \\| **0.445 ns**', '| Design-wide setup WNS | **0.445 ns**', 1],
  ['readme.en.md', '② 板级校验件对回真实路径', 'build/r113_board_verify_console.txt', 'build/evidence/r113_board_verify_console.txt', 2],
];
let bad = 0, hit = 0;
const cache = {};
const countOf = (s, sub) => { let n = 0, i = 0; for (;;) { i = s.indexOf(sub, i); if (i < 0) break; n++; i += sub.length; } return n; };
for (const [f, name, src, rep, want] of RULES) {
  if (!(f in cache)) cache[f] = readFileSync(f, 'utf8');
  const n = countOf(cache[f], src);
  // 注意：这里**总是**把替换做进 cache，写不写由 APPLY 决定。
  // 第一版只在 APPLY 时才替换，结果下面两条复发病地板在 --check 模式下读的是**改之前**的内容，
  // 于是"全对的一版"必然报 4 条 REFUSE（尺子判不了绿 = #227 那一族：正控制必须能绿）。
  if (n !== want) { console.log(`REFUSE ${name}：${f} 命中 ${n}（期望 ${want}）`); bad++; continue; }
  cache[f] = cache[f].split(src).join(rep);
  hit++; console.log(`OK   ${name} ×${n}`);
}
// 落盘前的形状地板：首页两份都**不许**有以 `\|` 开头的行（①的复发病判据），
// 且每条点名的 build/… 路径都得在盘上（②的复发病判据，只查这次改过的名字）。
const { existsSync } = (await import('node:fs'));
for (const [f, s] of Object.entries(cache)) {
  const stray = s.split(/\r?\n/).filter((l) => l.startsWith('\\|')).length;
  if (stray) { console.log(`REFUSE 复发病①：${f} 还有 ${stray} 行行首是 \\|`); bad++; }
  const named = [...s.matchAll(/build\/evidence\/r113_[A-Za-z0-9_.]+|build\/r113_[A-Za-z0-9_.]+/g)].map((m) => m[0]);
  const missing = [...new Set(named)].filter((p) => !existsSync(p));
  if (missing.length) { console.log(`REFUSE 复发病②：${f} 点名而盘上没有：${missing.join('、')}`); bad++; }
}
if (APPLY && bad === 0) { for (const f of Object.keys(cache)) { writeFileSync(f, cache[f]); console.log(`WROTE ${f}`); } }
else if (APPLY) console.log('NO-WRITE 有规则被拒');
console.log(`判定=${bad ? 'RED' : 'GREEN'} 规则 ${hit} 条 / 拒 ${bad} 条 / apply=${APPLY ? 'yes' : 'no'}`);
process.exit(bad ? 1 : 0);
