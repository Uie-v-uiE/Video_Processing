// build/r124_sync_c3c9_numbers.mjs —— 把 C3（射程改对）与 C9（判定列补齐）的现算读数同步回所有引用它们的交付文档
// 依赖：node（本机 v24.x）；以仓库根为当前工作目录；不联网、不调 Vivado/xsim，只读写仓库内的文本文件。
// 用法：node build/r124_sync_c3c9_numbers.mjs --check   （默认，只报每条规则的命中数，不写盘）
//       node build/r124_sync_c3c9_numbers.mjs --apply  （命中数与期望全对才写；任何一条不匹配就整批 REFUSE，不留半改状态）
// 参数：
//   | 参数 | 作用 |
//   | --- | --- |
//   | --check | 逐条打印命中数与不命中项，不写盘 |
//   | --apply | 全部命中才落盘，并打印每个文件的行数变化（行数只许增不减） |

// 规矩：字面匹配、每条命中 1 次、一个文件一次写、行数不许变少；--check 先看命中。
import fs from 'node:fs';

const MODE = process.argv.includes('--apply') ? 'apply' : 'check';
const E = [
  ['report/known-limitations.md',
    '- **现象（现算读数）**：`report/repro-check.md` 的第三轮判定分母是 **61 行**，判定列读数 **PASS=36 / FAIL=0 / 未测=11**，\n' +
    '  另有 **14 行判定列不成词**（§9 那张第三轮表末列写的是凭据路径而不是判定词）。\n' +
    '  这一层由 `node build/checks/check_repo_consistency.mjs` 的 C9 打印，同一份件现在打印的末行是\n' +
    '  `C9 A/B/C 路径复现演练 判 9 项 判定列在内=61 行 PASS=36 FAIL=0 未测=11 判定列不成词=14`，判 PASS。',
    '- **现象（现算读数）**：`report/repro-check.md` 的判定分母是 **61 行**，判定列读数 **PASS=49 / FAIL=0 / 未测=12**，\n' +
    '  判定列不成词 **0 行**（先前那 14 行是表形问题：§8.1 把判定写在第 4 列、§9 那张第三轮表根本没有判定列；\n' +
    '  两处都改成了"判定在末列"，换列件是 `build/r124_repro_verdict_col.mjs`，只动列序与一个判定词的写法）。\n' +
    '  这一层由 `node build/checks/check_repo_consistency.mjs` 的 C9 打印，同一份件现在打印的末行是\n' +
    '  `C9 A/B/C 路径复现演练 判 9 项 判定列在内=61 行 PASS=49 FAIL=0 未测=12 判定列不成词=0`，判 PASS。', 1],
  ['report/known-limitations.md',
    '- **11 行未测的构成**：路径 B 的 9 行（`B1`/`B1b`/`B2`/`B3`/`B3b`/`B4`/`B4b`/`B5`/`B6`，都要真跑一次构建或全量仿真）、\n' +
    '  结果比对的 `M4`、以及换 ELF 对照的 `C3c`（见第 2 节：重建那颗与板上那颗 md5 不同）。',
    '- **12 行未测的构成**：路径 B 的 9 行（`B1`/`B1b`/`B2`/`B3`/`B3b`/`B4`/`B4b`/`B5`/`B6`，都要真跑一次构建或全量仿真）、\n' +
    '  结果比对的 `M4`、换 ELF 对照的 `C3c`（见第 2 节：重建那颗与板上那颗 md5 不同），\n' +
    '  以及第三轮那张表的 `C4`：两跑健康计数的原件（`health_r118docround_a.json` 与 `_b.json`）已被记录在案的\n' +
    '  精简笔删掉、不随包 ⇒ 正文里那串读数是当时的转述，包内指不到件，所以它不能算成一条判定。', 1],
  ['report/final-gate.md',
    '  同一份 `report/repro-check.md` 读出 `判定列在内=61 行 PASS=36 FAIL=0 未测=11 判定列不成词=14`，判 **PASS**。',
    '  同一份 `report/repro-check.md` 在读出上面那一对数之后又收了一轮：两张表的判定列搬回末列、第三轮 `C4` 如实记未测，\n' +
    '  现跑读数是 `判定列在内=61 行 PASS=49 FAIL=0 未测=12 判定列不成词=0`，判 **PASS**。', 1],
  ['report/final-gate.md',
    '  仍然没有变成"全通过"的是那 11 行未测与 14 行判定列不成词，逐条构成见 `report/known-limitations.md` 第 4 节。',
    '  仍然没有变成"全通过"的是那 12 行未测（判定列不成词已经清零），逐条构成见 `report/known-limitations.md` 第 4 节。', 1],
  ['report/final-gate.md',
    '- **C3 的死引用清了。** 同一条命令今天打印 `死引用=0`（其余计数随交付树变：两次现跑分别读到 `扫=131 检查=616` 与\n' +
    '  `扫=120 检查=563`），判 PASS；快照里那 3 条死引用指的是改名之前的 `docs/…` 路径。',
    '- **C3 的死引用清了，但先前那个"0"是尺子看不见。** 路径正则的字符类里没有 `/`，三层以上的指路（`build/evidence/r118_board/…` 这一族）\n' +
    '  匹配不上就**静默不进分母**；右边界那条前瞻又不认反引号，`build/x.md` 这种最常见写法一条都不判。把射程改对之后\n' +
    '  同一棵树现算 `检查路径引用=5244`（改前只有 628），其中 **140 条**指的是被记录在案的精简笔（`02bd5c4`、`58faa85`）删掉的\n' +
    '  凭据 ⇒ 按"历史凭据"只报数，名单写死在尺子里并配了能红的反买通对照；剩下 13 条真缺口逐条改了口径（件：`build/r124_fix_dead_cites.mjs`），\n' +
    '  现在打印 `死引用=0`，判 PASS。快照里那 3 条死引用指的是改名之前的 `docs/…` 路径。', 1],
  ['report/submission-checklist.md',
    '**FAIL**：A/B/C 三条路径逐条跑下来的判定读数（终审 C9 现跑）是 `判定列在内=61 行 PASS=36 FAIL=0 未测=11 判定列不成词=14`。' +
    '缺的是那 11 行未测（9 行要一次真构建/全量仿真、`M4`、`C3c`）与 14 行没有判定词的表格，不是把表改绿；构成逐条写在 `report/known-limitations.md` 第 4 节。',
    '**FAIL**：A/B/C 三条路径逐条跑下来的判定读数（终审 C9 现跑）是 `判定列在内=61 行 PASS=49 FAIL=0 未测=12 判定列不成词=0`。' +
    '"判定列不成词"的 14 行已经补齐（§8.1 把判定挪回末列、§9 那张第三轮表补了判定列，换列件 `build/r124_repro_verdict_col.mjs`）；' +
    '剩下的缺口是那 12 行未测——9 行要一次真构建或全量仿真、`M4`、`C3c`，再加第三轮 `C4`（两跑健康计数的原件已被记录在案的精简笔删掉、不随包，只能转述）。这些不是把表改绿能了结的；构成逐条写在 `report/known-limitations.md` 第 4 节。', 1],
  ['report/submission-checklist.md',
    '**PASS（快照史实保留）**：C3 现判 `扫=111 份 检查路径引用=628 死引用=0`，逐类豁免随输出打印（碎片 62／台账 213／同行声明 14／围栏回显 4）。' +
    '**先前那版记的"3 条真缺口"随改名波清掉**，其中 2 条正是第 9/18 项当时未落地的文件 ⇒ 这条从 FAIL 改 PASS 的依据是"缺口没了"，不是"豁免放宽了"',
    '**PASS**：C3 现判 `扫=111 份 检查路径引用=5244 死引用=0 历史精简=140`，逐类豁免随输出打印（碎片 1154／运行期 49／台账 2807／同行声明 160／围栏回显 25／引用块 1）。' +
    '分母从六百涨到五千**不是文档变好了，是尺子改对了射程**：路径正则的字符类缺 `/`（三层以上指路根本不进分母）、右边界又不认反引号。' +
    '射程修好后现算抓到 13 条真缺口（指到从来没有过的目录或章节），逐条改了口径（件：`build/r124_fix_dead_cites.mjs`）⇒ 死引用=0；' +
    '那 140 条指的是被记录在案的精简笔删掉的凭据，只报数，名单与反买通对照都在尺子里', 1],
  ['report/90-open-items.md',
    'C3「文档内路径存活」现判 `PASS`（2026-10-05 12:55 现跑）：`扫=120 份 检查路径引用=593 死引用=0`（豁免：碎片 57 / 运行期 0 / 台账 205 / 同行声明 14 / 围栏回显 4）。',
    'C3「文档内路径存活」现判 `PASS`（2026-10-05 下午现跑）：`扫=111 份 检查路径引用=5244 死引用=0 历史精简=140`（豁免：碎片 1154 / 运行期 49 / 台账 2807 / 同行声明 160 / 围栏回显 25 / 引用块 1）。' +
    '**这一行的分母比上午那一版大了整整一个数量级，原因在尺子不在文档**：路径正则的字符类里没有 `/`，三层以上的指路根本不进分母，反引号包着的写法也不认；射程改对后抓到 13 条真缺口，逐条改了口径（`build/r124_fix_dead_cites.mjs`），台账 #391。', 1],
  ['report/90-open-items.md',
    'C9「A/B/C 路径复现演练」现判 `PASS`：判定列在内 61 行、`PASS=36`、`FAIL=0`、未测 11、判定列不成词 14。',
    'C9「A/B/C 路径复现演练」现判 `PASS`：判定列在内 61 行、`PASS=49`、`FAIL=0`、未测 12、判定列不成词 0（那 14 行的表形已改回"判定在末列"）。', 1],
  ['report/90-open-items.md',
    '② 14 条"判定列不成词"= 那 14 行的末列不是三态 token，C9 数不到它们 ⇒ 行形要改回三态。收这一格需要一次带构建窗口的复现演练',
    '② 14 条"判定列不成词"已经收掉（§8.1 换列 + §9 补判定列，件 `build/r124_repro_verdict_col.mjs`）；剩下 12 条未测里要真跑构建或全量仿真的还是 10 条，收这一格需要一次带构建窗口的复现演练', 1],
  ['report/run-queue.md',
    '第三轮的判定读数是 `判定列在内=61 行 PASS=36 FAIL=0 未测=11 判定列不成词=14`（终审 C9 现跑）；缺的是那 11 行未测与 14 行没有判定词的表格，逐条构成见 `report/known-limitations.md` 第 4 节。',
    '判定读数是 `判定列在内=61 行 PASS=49 FAIL=0 未测=12 判定列不成词=0`（终审 C9 现跑）；14 行没有判定词的表格已补齐（判定列搬回末列），缺的是那 12 行未测，逐条构成见 `report/known-limitations.md` 第 4 节。', 1],
];

let bad = 0;
const perFile = new Map();
for (const [f, old, neu, want] of E) {
  const text = perFile.get(f) ?? fs.readFileSync(f, 'utf8');
  const n = text.split(old).length - 1;
  if (n !== want) { console.log(`MISS ${f} 命中=${n} 期望=${want} :: ${old.slice(0, 56).replace(/\n/g, '\\n')}`); bad++; continue; }
  perFile.set(f, text.split(old).join(neu));
  console.log(`OK   ${f} :: ${old.slice(0, 44).replace(/\n/g, '\\n')}`);
}
console.log(`规则 ${E.length} 条 不符=${bad} 涉及文件=${perFile.size}`);
if (MODE === 'check') { console.log(bad ? '有不命中，先修规则' : '全部命中，可 --apply'); process.exit(bad ? 1 : 0); }
if (bad) { console.log('REFUSE：有不命中，整批不写'); process.exit(1); }
for (const [f, text] of perFile) {
  const before = fs.readFileSync(f, 'utf8').split(/\r?\n/).length;
  const after = text.split(/\r?\n/).length;
  if (after < before) { console.log(`REFUSE ${f} 行数变少 ${before}→${after}`); process.exit(1); }
  fs.writeFileSync(f, text);
  console.log(`WROTE ${f} 行数 ${before}→${after}`);
}
console.log('APPLY DONE');
