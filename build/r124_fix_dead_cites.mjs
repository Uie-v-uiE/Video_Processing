// build/r124_fix_dead_cites.mjs —— 把终审 C3 新射程下暴露的"指到从来没有过的路径"逐条改口
// 依赖：node（本机 v24.x）；以仓库根为当前工作目录；不联网、不调 Vivado/xsim，只读写仓库内的文本文件。
// 用法：node build/r124_fix_dead_cites.mjs --check   （默认，只报每条规则的命中数，不写盘）
//       node build/r124_fix_dead_cites.mjs --apply  （命中数与期望全对才写；任何一条不匹配就整批 REFUSE，不留半改状态）
// 参数：
//   | 参数 | 作用 |
//   | --- | --- |
//   | --check | 逐条打印命中数与不命中项，不写盘 |
//   | --apply | 全部命中才落盘，并打印每个文件的行数变化（行数只许增不减） |

// 规矩（都是以前踩过的坑）：
//  · old 串按**字面**匹配（不是正则），每条必须命中 want 次，否则整文件不写；
//  · 一个文件一次写，写完立刻断言行数只增不减；
//  · 不改围栏/引用块里的原文回显（那是别人打印的，改它＝伪造记录）。
import fs from 'node:fs';

const MODE = process.argv.includes('--apply') ? 'apply' : 'check';
const EDITS = [
  // —— 报"在仓库内/被跟踪"而实际那几层从未随包或被精简删掉：先把话说对 ——
  ['board/raw-vs-golden.md',
    '所有比对表都在 `board/compare/`，日志/抓图的条件卡都在 `board/conditions/`，索引在 `board/logs/index.md`、`board/captures/index.md`。',
    '比对表仍在 `board/compare/`（这一层随包）。当时放日志与抓图条件卡、以及那两份索引的另外三层目录**从未入库，也不随包**：本节表里的判定读数是那时从那些件抄进来的，抄件在此、原件不在包内。', 1],
  ['report/notice.md',
    '`build/evidence/r115_sch_p8/` 被跟踪裁图=4，逐格与上表相符。',
    '§3 那 4 张原理图裁图当时被跟踪，现已随记录在案的精简笔删掉（`git log --diff-filter=D --name-only -- build/evidence` 念出删除那一笔），不随包；其余逐格与上表相符。', 1],

  // —— 包内落点 vs 仓库路径：用 `$PKG/` 把"包根"写明白，仓库里没有这一层 ——
  ['report/submission-package.md',
    '| 凭据（构建/台架/板级报告原件） | 仓库里在 `build/` 与 `build/evidence/`；**包里的落点是 `build/reports/` 与 `board/output/`**（导出时按"被活文档点名"搬运，名字去掉轮次号） |',
    '| 凭据（构建/台架/板级报告原件） | 仓库里在 `build/` 与 `build/evidence/`；**包里的落点是 `$PKG/build/reports/` 与 `$PKG/board/output/`**（`$PKG` 是导出器写的包根，仓库里没有这一层；导出时按"被活文档点名"搬运，名字去掉轮次号） |', 1],
  ['report/submission-package.md',
    '| 复现说明 | `submit/reproduce/` | 命令 + 前置 + 期望输出，三件齐才算一条步骤 |',
    '| 复现说明 | 仓库侧在 `report/reproduce/README.md` 与 `report/70-reproduce.md`；包侧落点是 `$PKG/submit/reproduce/`（`$PKG`＝包根，仓库里没有这一层） | 命令 + 前置 + 期望输出，三件齐才算一条步骤 |', 1],
  ['report/submission-package.md',
    '| 度量表、逐时钟名册、逐轮台账 | `build/`（名册在 `build/roster/`、逐轮台账在 `build/timing/`） |',
    '| 度量表、逐时钟名册、逐轮台账 | `build/`（名册在 `build/roster/`）＋ `report/timing/`（逐轮那一半的落点；`build/` 下从来没有 `timing/` 这一层） |', 1],

  // —— 从未落地的装配页／目录：写成"没写过"，不留一个像路径的名字 ——
  ['report/run-queue.md',
    '`sim/regress/` 与 `verification-claim` 装配页未写（后者从未落盘 ⇒ 现不存在）',
    '回归清单目录与 `verification-claim` 装配页都未写（两者从未落盘 ⇒ 现不存在）', 1],
  ['report/run-queue.md',
    '进行中（`board/hardware_setup.md` 151 行、`board/firmware/` 在；`board/run/`、`bringup-checklist.md` 待核）',
    '进行中（`board/hardware_setup.md` 已落并随包；三件身份改由 `build/provenance.md` 与 `board/measured/` 的 IDENTITY 块承担——原先那层身份摘要卡已随目录精简删掉、不随包；`bringup-checklist.md` 从未落盘 ⇒ 现不存在）', 1],
  ['report/run-queue.md',
    '已交付（`board/raw-vs-golden.md` + logs/captures/compare/conditions，比对表 12 张全部脚本产出）',
    '已交付（`board/raw-vs-golden.md` 与 `board/compare/` 里 12 张比对表全部脚本产出；当时的日志／抓图条件卡那三层从未入库、不随包）', 1],
  ['report/run-queue.md',
    '| P08 验证与增益 | `skills/evals/*` | P04/P05 | 部分交付（`evals/runbook.md` + `raw/` 两跑原始件 + `records/` 陌生人演练与第三方审计各一份）；',
    '| P08 验证与增益 | `skills/_meta/`（旧包的 `skills/evals/` 那一层在 2026-10-04 c7b325f 重建后从未入库、不随包）| P04/P05 | 部分交付（协议与两跑原始件、陌生人演练与第三方审计各一份都在 `skills/_meta/` 一侧，条目级验证状态见 `skills/_meta/validation.md`）；', 1],
  ['report/run-queue.md',
    '已交付：**技能包门禁 12 项全绿、无未测**，两跑逐字节一致（`build/evidence/r120_gates_skill_a.txt` / `..._b.txt`）；索引 `gen_index --check` 条目=58 一致=yes；陌生人演练与第三方审计两份记录在 `skills/evals/records/`',
    '已交付：**技能包自检 `node skills/_meta/run-all-checks.mjs skills` 判 9 项、自测件 6、红=0、未测=0**；索引 `node skills/_meta/build-index.mjs skills --check` 条目=49、需改写=no；陌生人演练与第三方审计两份记录现落在 `skills/_meta/` 一侧。（旧包那把"12 项全绿"的读数在 `build/evidence/r120_gates_skill_a.txt`，是 2026-10-04 c7b325f 重建**前**那一版包的产物；同一次对照的第二跑 `..._b.txt` 已被记录在案的精简笔删掉、不随包 ⇒ "两跑逐字节一致"今天在盘上复跑不出来，只算历史记录。`gen_index --check 条目=58` 同属旧包读数，现役件是 `build-index.mjs`）', 1],

  // —— 本机隔离滚动目录：说清"从未入库、不随包"，别让读者去仓库里找 ——
  ['report/optimization_log.md',
    '## r90（2026-09-29 19:5x–23:0x，隔离构建 `build/isolated_0929_2036/` 与 `build/isolated_0929_2105/`）：',
    '## r90（2026-09-29 19:5x–23:0x，两次隔离构建都在本机滚动目录里跑，从未入库、不随包）：', 1],
  ['report/optimization_log.md',
    '两份报告的 WNS 与级数**完全相同**（`build/isolated_0929_2036/` 与 `build/isolated_0929_2105/`）——',
    '两份报告的 WNS 与级数**完全相同**（各自躺在上面那两个本机滚动目录里，从未入库、不随包）——', 1],
  ['report/repro-check.md',
    '| M4 | `node src/host/report_metrics/…` 那把（当时叫',
    '| M4 | 指标采集那把（当时叫', 1],
  ['report/figures/legend.md',
    '所以它们里面的引用**不被**第 20 项自动核对 ⇒ `report/20-principle.md（未写）` 与',
    '所以它们里面的引用**不被**第 20 项自动核对 ⇒ 尚未写的那一章（第 20 章·设计原理）与', 1],
  ['report/ai_collaboration.md',
    '在 `board/evidence_metrics/` 落下一份**没有计划、没有出处**的"实测"（那份产物事后删掉了，今天盘上不再有这一份，',
    '在一层的板级证据目录里落下一份**没有计划、没有出处**的"实测"（那份产物从未入库、不随包，事后删掉了，今天盘上不再有这一份，', 1],
];

let bad = 0, touched = new Set();
const perFile = new Map();
for (const [f, old, neu, want] of EDITS) {
  const text = perFile.get(f) ?? fs.readFileSync(f, 'utf8');
  const n = text.split(old).length - 1;
  if (n !== want) { console.log(`MISS ${f} 命中=${n} 期望=${want} :: ${old.slice(0, 60)}`); bad++; continue; }
  perFile.set(f, text.split(old).join(neu));
  touched.add(f);
  console.log(`OK   ${f} 命中 ${n} :: ${old.slice(0, 48)}`);
}
console.log(`规则 ${EDITS.length} 条 命中不符=${bad} 涉及文件=${touched.size}`);
if (MODE === 'check') { console.log('CHECK-ONLY（没写盘）' + (bad ? ' 有不命中，先把规则改准再 --apply' : ' 全部命中，可 --apply')); process.exit(bad ? 1 : 0); }
if (bad) { console.log('REFUSE：有不命中的规则，整批不写（不留半改状态）'); process.exit(1); }
for (const [f, text] of perFile) {
  const before = fs.readFileSync(f, 'utf8').split(/\r?\n/).length;
  const after = text.split(/\r?\n/).length;
  if (after < before) { console.log(`REFUSE ${f} 行数变少 ${before}→${after}（这批规则只该改字，不该删行）`); process.exit(1); }
  fs.writeFileSync(f, text);
  console.log(`WROTE ${f} 行数 ${before}→${after}`);
}
console.log('APPLY DONE');
