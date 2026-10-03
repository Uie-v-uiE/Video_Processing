// build/r113_fill_flash.mjs —— 采纳笔之后把「刷板时刻 / 板上证据件名 / 板读结温 / E6 现状」回填（第二笔）。
// 与 r110_fill_flash.mjs 同一套纪律：每条规则必须恰好命中期望次数，任何一条拒 ⇒ 整批不落盘。
// 与 r110 那份唯一的区别（有意为之）：**这里用字面量匹配而不是正则**。首页那几句里满是从 Markdown
// 抄来的 `**` 与 `*`，正则里 `**` 直接是 "Nothing to repeat" 语法错，`*待队员判*` 这类锚点迟早炸
// （规矩：解析层要按实测定形，不要沿用没验过的形状）。字面量 indexOf 计数没有这个雷。
import { readFileSync, writeFileSync } from 'node:fs';
const APPLY = process.argv.includes('--apply');

// —— 1) 字面量规则：[文件, 名字, 原文（字面）, 新文（字面）, 期望命中次数] ——
const RULES = [
  ['README.md', '首页身份句回填刷板时刻',
    '板上这一版 r113（bit `b94f4da6cdff`，刷板时刻待回填）',
    '板上这一版 r113，2026-10-03 14:32 三步 JTAG 刷入（bit `b94f4da6cdff`，14:31 起链、program_pl 于 14:32:26 exit 0、RESUME ok）', 1],
  ['README.md', '首页门禁件对回 r113', 'build/r110_gates.txt', 'build/r113_gates.txt', 1],
  ['README.md', '首页板级验收件对回 r113', 'build/r110_board_verify_console.txt', 'build/r113_board_verify_console.txt', 2],
  ['README.en.md', '首页身份句回填刷板时刻',
    'the board now runs r113 (bit `b94f4da6cdff`, flash time to be filled)',
    'the board now runs r113, flashed at 14:32 on 2026-10-03 by the three-step JTAG chain (bit `b94f4da6cdff`, chain started 14:31, program_pl exit 0 at 14:32:26, RESUME ok)', 1],
  ['README.en.md', '首页门禁件对回 r113', 'build/r110_gates.txt', 'build/r113_gates.txt', 1],
  ['README.en.md', '首页板级验收件对回 r113', 'build/r110_board_verify_console.txt', 'build/r113_board_verify_console.txt', 2],
  ['board/ACCEPTANCE.md', 'E6 现状半句：板上已是 r113（判还没做）',
    '现状（r110 那版 bit `2bf95588978f`，**既没有**武装门**也没有**声明初值）应当读 **1**',
    '现状（板上已是 **r113**（bit `b94f4da6cdff`，2026-10-03 14:32 三步 JTAG 刷入）**既带**武装门**也带**声明初值）应当读 **0**——**但 E6 这一判还没做**（要冷上电 ≥10 s）；上一版 r110（bit `2bf95588978f`，两样都没有）读 **1** 已是历史记录', 1],
  ['board/ACCEPTANCE.md', 'E6 待判半句：读 1 不再属预期',
    '*待队员判*（板上是 r110/r112 那两版时读 1 属预期；刷上 **r113**（带声明初值，网表已实测 `INIT=1\'b1`）之后**必须读 0**；',
    '*待队员判*（板上已经是 **r113**（bit `b94f4da6cdff`，14:32 刷入，带声明初值，网表已实测 `INIT=1\'b1`）⇒ 现在读 1 **不再属预期**、必须读 0；r110/r112 那两版读 1 属预期，那是历史；', 1],
];

// —— 2) 整行替换（CSV 那一行太长，字面量锚点只认行首，落盘前验字段数）——
const ROWS = [
  ['data/metrics.csv', '片上结温（板读 XADC）,资源,',
    '片上结温（板读 XADC）,资源,61.2 – 61.7,℃,板上这一版 **r113**（bit md5 `b94f4da6cdff`）2026-10-03 14:32 三步 JTAG 刷入（`build/evidence/r113_flash_console.txt`：14:31 起链、program_pl Vivado `exit 0` 于 14:32:26、`RESUME: ok`）之后由 `board_verify --geom --battery --round=r113` 那一次（RESULT board_verify PASS、判红步骤 0、geom 10/0、串口 105 条 97.6 s）逐条 `[TEMP]` 回显的极值：`degC=61.15 raw=0xA9D1 vccint=998mv osd=61C gpio=0x61`、`degC=61.35 raw=0xA9EA vccint=998mv osd=61C gpio=0x61`、`degC=61.71 raw=0xAA19 vccint=997mv osd=62C gpio=0x62`（六条全在 `build/evidence/r113_temp_lines.txt`——由该次运行的两份产物 grep 而来、不手抄）；V9-6 三方对账（驱动读数 ↔ 屏上三字符 ↔ 写进 PL 的 gpio）判 ok（电池里 4 条 degC↔osd↔gpio 全自洽）。区间是**六次读数的极值**、不是精度声明 ⇒ 与 r110 那版（60.6–60.7 ℃）的差属工况与热身差异、别当收益或回归；第 1b 步**自己产出**并被跟踪的原始回显 `build/evidence/r113_serial_raw.txt`（[TEMP]=2、判定=绿、地板 2）⇒ 这一格不靠手抄的凭据从 r104 起续到本轮（#220/#163）,一次板级校验（同一次串口电池 + 第 1b 步原始回显）,build/evidence/r113_temp_lines.txt、build/evidence/r113_serial_raw.txt'],
];

let bad = 0, hit = 0;
const cache = {};
const load = (f) => { if (!(f in cache)) cache[f] = readFileSync(f, 'utf8'); return cache[f]; };

const countOf = (s, sub) => { let n = 0, i = 0; for (;;) { i = s.indexOf(sub, i); if (i < 0) break; n++; i += sub.length; } return n; };

for (const [f, name, src, rep, want] of RULES) {
  const s = load(f);
  const n = countOf(s, src);
  if (n !== want) { console.log(`REFUSE ${name}：${f} 命中 ${n}（期望 ${want}）`); bad++; continue; }
  if (APPLY) cache[f] = s.split(src).join(rep);
  hit++; console.log(`OK   ${name} ×${n}`);
}
for (const [f, prefix, newline] of ROWS) {
  const lines = load(f).split('\n');
  const idx = [];
  lines.forEach((l, i) => { if (l.startsWith(prefix)) idx.push(i); });
  if (idx.length !== 1) { console.log(`REFUSE 行替换 ${f} ${prefix}：命中 ${idx.length}（期望 1）`); bad++; continue; }
  const fields = newline.split(',').length;
  if (fields !== 7) { console.log(`REFUSE 行替换 ${f}：新行 ASCII 逗号 ${fields - 1} 个（CSV 要 6 个分隔 ⇒ 说明格里混进了半角逗号）`); bad++; continue; }
  console.log(`OK   行替换 ${f} ${prefix}（旧 ${lines[idx[0]].length} 字 → 新 ${newline.length} 字，字段 ${fields}）`);
  if (APPLY) { lines[idx[0]] = newline; cache[f] = lines.join('\n'); }
  hit++;
}
if (APPLY && bad === 0) { for (const f of Object.keys(cache)) { writeFileSync(f, cache[f]); console.log(`WROTE ${f}`); } }
else if (APPLY) console.log('NO-WRITE 有规则被拒');
console.log(`判定=${bad ? 'RED' : 'GREEN'} 规则 ${hit} 条 / 拒 ${bad} 条 / apply=${APPLY ? 'yes' : 'no'}`);
process.exit(bad ? 1 : 0);
