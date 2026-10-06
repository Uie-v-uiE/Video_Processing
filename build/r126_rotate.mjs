#!/usr/bin/env node
// 作用: 把交付文档里"板上跑的是哪一版 / 现役 ELF 是哪颗"这类活句子按字面规则改口（r126 那一轮）
// 依赖: node（本机 v24.x）；工作目录无关（仓库根从 argv[2] 取）；不联网、不调 Vivado/xsdb，只读写文本文件
// 输入: argv[2]=仓库根，argv[3]=--check（默认）或 --apply；16 条规则写死在本文件的 R 数组里
// 输出: stdout 每条规则一行 HIT/OKAY/BAD/SKIP，末行给计数；--apply 且全对时才逐文件写回
// 关键参数: 不用环境变量；带 'B' 标签的规则只适用于提交分支那棵树（另一棵树按 SKIP 计，不算不命中）
// 退出码: 0=全部命中或已改口；1=有规则不命中，或"命中+已改口"低于地板 8（那等于这一波什么都没判）
// r126 改口波：把"板上现在跑的是 r118 / 现役 ELF 是 d0b07f84 / PS 应用不会自己跑"这三类活句子
// 改成 2026-10-06 晚上量出来的那一版（位流没动，PS 应用从 OCM 0x0 重链到 DDR 0x00200000，
// QSPI 冷上电整条自启成立，门禁件写进 build/r126_gates.txt）。
//
// 用法：node r126_rotate.mjs <仓库根> --check    只数每条规则的命中数，不写盘
//       node r126_rotate.mjs <仓库根> --apply    每条必须"命中 1 次"或"新文已在（判已改口）"，否则整批不写
// 规矩（照本仓既有改口脚本的样子）：old 按字面匹配；一个文件一次写；写完断言行数不变；
//   已经在别处改口的句子不报错、但要念出来，免得看起来"全命中"其实一条没管。
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(process.argv[2] || '.');
const mode = process.argv.includes('--apply') ? 'apply' : 'check';
if (!fs.existsSync(root)) { console.log('REFUSE 根目录不存在：' + root); process.exit(2); }

const R = [
  ['README.md', '板上现在跑的是 r118，位流身份', '板上现在跑的是 r126，位流身份'],  ['README.md', 'r118_gates.txt`；逐字节', 'r126_gates.txt`；逐字节'],
  ['README_EN.md', 'The board now runs r118', 'The board now runs r126'],
  ['README_EN.md', 'r118_gates.txt`; byte-identical', 'r126_gates.txt`; byte-identical'],
  ['report/commands.md', '板上现在跑的是 r118，位流 ', '板上现在跑的是 r126，位流 '],
  ['report/host_guide.md', '入口 = `_boot`、`_vector_table` 必须在 0x0、`.text` 体积下界、七个符号必须在',
                          '入口 = `_boot`、`_vector_table` = 第一个 LOAD 的 `VirtAddr`、基址落在 `[0x00100000, 0x3FEF0000]` 且不为 0、`.text` 体积下界、七个符号必须在'],
  ['report/host_guide.md', 'md5 `d0b07f84a068…`，即板上那一版', 'md5 `57fa442a7eaf…`，即板上那一版'],
  ['report/70-reproduce.md',
   '`d0b07f84a068`（与 `build/r118_gates.txt` 身份行一致；`git log -1 --format=%ci -- build/ps_app.elf` = `2026-09-29`（原始提交时间戳以 `%ci` 打全，这里只留日期），早于 `src/ps/main.c` 的 #167 那次提交 `2026-10-02`）',
   '`57fa442a7eaf`（与 `build/r126_gates.txt` 身份行一致；这一版是 2026-10-06 把 PS 应用从 OCM 的 0x0 重链到 DDR 的 0x00200000 之后重编出来的，位流没换）'],
  ['report/repro-check.md',
   '该件写于 `2026-10-01`、`md5(12)=d0b07f84a068`（`build/provenance.md` 第 5 节，并登记它与板上这一版的位流**不同源**）',
   '该件写于 `2026-10-06`、`md5(12)=57fa442a7eaf`（重链到 DDR 之后重编的那一颗，就是板上正在跑的这颗）'],
  ['board/README.md', '实测读数分两格：上电会把 PL 配置好（串口 `FPGA Done !`），PS 应用不会自己跑；',
                      '实测：拨回 QSPI 断电重上，串口依次出 `Boot mode is QSPI` → `FPGA Done !` → `SUCCESSFUL_HANDOFF` → `[CFG] … ok`，', 'B'],
  ['board/README.md', '根因与凭据在 `report/technical-document.md` §8.3，演示照上面 4) 的 JTAG 三步走。',
                      'SD 自动播起片、ETH 那一路也出画面 ⇒ 演示可以只靠断电上电。凭据与修法见 `report/technical-document.md` §8.3；上面 4) 的 JTAG 三步仍然可用。', 'B'],
  ['report/technical-document.md', '位流那一格实测成立、应用那一格不成立，两格分开写在 §8.3',
                                  '断电自启整条成立（`Boot mode is QSPI` → `FPGA Done !` → `SUCCESSFUL_HANDOFF`），两格读数与凭据在 §8.3', 'B'],
  ['board/README.md', '| `build/ps_app.elf` | `d0b07f84a068` | 跟踪件 |', '| `build/ps_app.elf` | `57fa442a7eaf` | 跟踪件 |'],
  ['board/README.md', '上表是 2026-10-05 10:26 用', '上表是 2026-10-06 19:36 用'],
  ['board/README.md', '`board/measured/flash_20261005_1030.txt` 的 IDENTITY 段', '`board/measured/flash_20261006_1936.txt` 的 IDENTITY 段'],
  ['board/README.md', '所以板上验过的行为只绑定 `d0b07f84a068` 那颗；要用重建件，就得重刷 + 跑一次第 2 节末尾那条 `board_verify`。',
                      '2026-10-06 把 PS 应用重链到 DDR 之后重编的那颗（md5 `57fa442a7eaf`）就是现在板上跑的这颗，10-05 那颗没上过板、已被它取代；要用自己重编的件，就得重刷 + 跑一次第 2 节末尾那条 `board_verify`。'],
];

const byFile = new Map();
// 标 'B' 的规则只属于提交分支（那两句是交付树里才有的写法）；另一棵树里它们不适用，不算不命中。
const IS_BRANCH = /delivery_review/.test(root);
for (const [f, oldS, newS, tag] of R) {
  if (tag === 'B' && !IS_BRANCH) continue;
  if (!byFile.has(f)) byFile.set(f, []);
  byFile.get(f).push([oldS, newS]);
}
let bad = 0, fired = 0, already = 0, skipped = 0;
const staged = new Map();   // 先全判完再一次性写：中途发现某条不命中也不能留下半改状态
for (const [f, rules] of byFile) {
  const p = path.join(root, f);
  if (!fs.existsSync(p)) { console.log(`SKIP 这一棵树里没有：${f}（规则 ${rules.length} 条不适用）`); skipped += rules.length; continue; }
  let t = fs.readFileSync(p, 'utf8');
  const lines0 = t.split('\n').length;
  for (const [oldS, newS] of rules) {
    const hits = t.split(oldS).length - 1;
    const newHits = t.split(newS).length - 1;
    if (hits === 1) { t = t.replace(oldS, newS); fired++; console.log(`HIT  ${f} 命中 1（新文原有 ${newHits} 次）`); }
    else if (hits === 0 && newHits >= 1) { already++; console.log(`OKAY ${f} 这条已改口（新文 ${newHits} 次）`); }
    else { bad++; console.log(`BAD  ${f} 命中 ${hits} 次（期望 1；新文 ${newHits} 次）⇒ 整批不写`); }
  }
  if (t.split('\n').length !== lines0) { console.log(`BAD ${f} 行数变了 ⇒ 不写`); bad++; }
  staged.set(f, t);
}
if (mode === 'apply' && bad === 0) {
  for (const [f, t] of staged) fs.writeFileSync(path.join(root, f), t);
}
const done = fired + already;
console.log(`${mode === 'apply' ? 'APPLY' : 'CHECK-ONLY'} 改口=${fired} 已改口=${already} 不适用=${skipped} 不命中=${bad} 规则=${R.length} 文件=${byFile.size}`);
// 地板：这一波在每棵树里至少真的管到 8 句，否则等于"改口跑了一遍什么都没改"（防空转）。
if (done < 8) { console.log(`REFUSE 命中+已改口 只有 ${done} 句（地板 8）⇒ 这条改口波没在判东西`); process.exit(1); }
process.exit(bad ? 1 : 0);
