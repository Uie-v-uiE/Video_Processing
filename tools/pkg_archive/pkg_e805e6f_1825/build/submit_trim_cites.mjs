// build/submit_trim_cites.mjs —— 提交分支专用：把指到"不随包的开发流水账"的路径引用改成非路径的说法
//
// 依赖：Node 22+（无第三方模块）；只在提交分支的工作树里跑（它对着的是当前目录的 *.md / *.csv / *.tsv）。
// 用法：node build/submit_trim_cites.mjs --check      （只数不改，打印每条规则命中数与残留）
//       node build/submit_trim_cites.mjs --apply     （写盘；写之前每个文件先断言行数不减少）
// 参数：
//   | 参数 | 作用 |
//   | --- | --- |
//   | `--check` / `--apply` | 只读预检 / 真正改写；两者都必须能打印每条规则的命中数 |
//   | 环境变量 `SUBMIT_TRIM_DRY_DIR` | 换一棵树跑（自测用，验证规则真的会改东西） |
//
// 为什么要它：提交分支按赛题 §3.3.5.4 只留评委要翻的文档，`report/log/`（2.2 万行流水账）、
// `report/timing/`（逐轮方案选择）、`report/io/`、`report/reproduce/` 与 30 份重复件不随包。
// 留下来的文档里有约 900 处指向它们的路径引用——**删了目标不删指路 = 一堆死链**，
// 而把信息丢掉也不行（那些编号是"这条结论从哪来"的唯一去处）。所以规则是：
// 路径形状换成中文的说法，行号/编号一并去掉或改写，一条都不留成假指路。
// 自证：跑完再数一次"还剩下多少条指向被删目标的路径"，必须为 0，否则退出码非 0。

import fs from 'node:fs';
import path from 'node:path';

const root = process.env.SUBMIT_TRIM_DRY_DIR || process.cwd();
const mode = process.argv.includes('--apply') ? 'apply' : 'check';

// 被删掉的开发件（路径形状不再允许出现在留下来的文档里）
const DROPPED_DIRS = ['report/log/', 'report/timing/', 'report/io/', 'report/reproduce/'];
const DROPPED_FILES = [
  'report/timing_global.md', 'report/known_issues.md', 'report/known-limitations.md',
  'report/90-open-items.md', 'report/optimization_log.md', 'report/50-results.md',
  'report/01-overview.md', 'report/02-architecture.md', 'report/03-algorithm.md',
  'report/04-resources.md', 'report/05-timing.md', 'report/architecture.md',
  'report/background_and_novelty.md', 'report/ps_vs_pl.md', 'report/rotation_and_effects.md',
  'report/bench_mutation.md', 'report/claims-vs-evidence.md', 'report/comparison-notes.md',
  'report/build-notes.md', 'report/final-gate.md', 'report/run-queue.md', 'report/unattended.md',
  'report/submission-checklist.md', 'report/submission-package.md', 'report/questions-for-team.md',
  'report/questions-for-team-p12.md', 'report/defaults.md', 'report/command_precedence.md',
  'report/llm_collab.md', 'report/modules.md', 'report/notice.md', 'report/acceptance-recipes.md',
];

// 具体目标 → 中文说法（顺序由长到短，避免短规则先吃掉长路径的前缀）
const NAME_MAP = [
  ['report/log/issues.md', '开发台账'],
  ['report/log/overnight_log.md', '夜轮记录'],
  ['report/log/version_lineage.md', '逐轮版本线'],
  ['report/log/changelog_v7.md', '变更志'],
  ['report/log/changelog_v6.md', '变更志'],
  ['report/log/d4c_pointers.md', '指路核对记录'],
  ['report/log/contest_checklist.md', '章程对照记录'],
  ['report/log/plan_v8_spec.md', '规格记录'],
  ['report/log/d5_soft_verdicts.md', '行号引用裁决记录'],
  ['report/log/eth_bringup.md', '网口上电记录'],
  ['report/log/v6_board_measurement.md', '板级测量记录'],
  ['report/log/v6_root_cause.md', '根因记录'],
  ['report/timing/debt_ledger.md', '时序债务账'],
  ['report/timing/rgmii_window_model.md', '收口输入窗模型'],
  ['report/timing/eth_rxc_partition_options.md', '域划分候选评估'],
  ['report/timing/eth_tx_decoupling_inventory.md', '发侧跨域清单'],
  ['report/timing/round_r116.md', '那一轮的逐轮页'],
  ['report/timing/round_r117.md', '那一轮的逐轮页'],
  ['report/timing/round_r118.md', '那一轮的逐轮页'],
  ['report/timing/cut_ledger.tsv', '刀口台账'],
  ['report/timing/loosen_ledger.tsv', '放松台账'],
  ['report/timing/twelve_questions.md', '十二问'],
  ['report/timing/limit_audit_r116.md', '极限核对'],
  ['report/timing/uncertainty_hold_ab.md', '不确定度对照'],
  ['report/timing/baseline_index.md', '基线索引'],
  ['report/timing/handoff_r118.md', '交接页'],
  ['report/timing/gates_g1_g12.md', '门禁逐条页'],
  ['report/timing/a1_sources.md', '出处核对'],
  ['report/timing/score.md', '打分页'],
  ['report/timing/README.md', '时序专章'],
  ['report/io/hdmi_cts_source_window.md', '屏侧窗口取证'],
  ['report/io/hdmi_tp1_sdc_measurement.md', '屏侧实测记录'],
  ['report/reproduce/README.md', '复现步骤'],
  ['report/timing_global.md', '时序全局记录'],
  ['report/known_issues.md', '问题清单'],
  ['report/known-limitations.md', '限制清单'],
  ['report/90-open-items.md', '未决项集中表'],
  ['report/optimization_log.md', '优化流水账'],
  ['report/50-results.md', '结果页'],
  ['report/01-overview.md', '概览章'],
  ['report/02-architecture.md', '架构章'],
  ['report/03-algorithm.md', '算法章'],
  ['report/04-resources.md', '资源章'],
  ['report/05-timing.md', '时序章'],
  ['report/architecture.md', '架构章'],
  ['report/background_and_novelty.md', '背景与创新'],
  ['report/ps_vs_pl.md', '软硬件划分'],
  ['report/rotation_and_effects.md', '旋转与效果'],
  ['report/bench_mutation.md', '台架变异对照'],
  ['report/claims-vs-evidence.md', '声明与凭据对照'],
  ['report/comparison-notes.md', '对照表说明'],
  ['report/build-notes.md', '构建流水账'],
  ['report/final-gate.md', '终审页'],
  ['report/run-queue.md', '任务队列'],
  ['report/unattended.md', '无人值守记录'],
  ['report/submission-checklist.md', '提交清单'],
  ['report/submission-package.md', '提交包说明'],
  ['report/questions-for-team-p12.md', '问队伍清单'],
  ['report/questions-for-team.md', '问队伍清单'],
  ['report/defaults.md', '默认档说明'],
  ['report/command_precedence.md', '命令优先级记录'],
  ['report/llm_collab.md', '大模型协作记录'],
  ['report/modules.md', '模块清单'],
  ['report/notice.md', '复核通知'],
  ['report/acceptance-recipes.md', '验收配方'],
];

const SKIP_DIR = new Set(['.git', 'vivado_system', 'node_modules', 'final_submission', 'local_docs']);
const isTarget = (p) => /\.(md|csv|tsv)$/.test(p);

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (SKIP_DIR.has(e.name)) continue;
    const full = path.join(dir, e.name);
    if (e.isDirectory()) walk(full, out);
    else if (isTarget(e.name)) out.push(full);
  }
  return out;
}

const files = walk(root);
const hits = new Map();      // 规则 -> 命中次数
let changedFiles = 0, changedLines = 0;

for (const f of files) {
  const rel = path.relative(root, f).replace(/\\/g, '/');
  // 被删掉的目标本身不参与改写（它们已经不在盘上；这里只兜住"仍留在盘上的开发件"）
  if (DROPPED_FILES.includes(rel)) continue;
  const before = fs.readFileSync(f, 'utf8');
  let text = before, lines = 0;
  for (const [needle, repl] of NAME_MAP) {
    // 带行号的形态先走：`report/x/y.md:12-34` 整段换掉，不留一个假锚点
    const withLines = new RegExp(needle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + ':(?:L)?\\d+(?:\\s*[-–—~]\\s*(?:L)?\\d+)?', 'g');
    // 目录形态：`report/log/` 后面跟一个文件名（映射表没列到的具体件）
    for (const d of DROPPED_DIRS) {
      if (rel.startsWith(d)) continue;
    }
    let m;
    while ((m = withLines.exec(text)) !== null) { /* 计数在下一行统一做 */ }
    const n1 = (text.match(withLines) || []).length;
    if (n1) { text = text.replace(withLines, repl); hits.set(needle + ':行号', (hits.get(needle + ':行号') || 0) + n1); lines += n1; }
    const plain = new RegExp(needle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g');
    const n2 = (text.match(plain) || []).length;
    if (n2) { text = text.replace(plain, repl); hits.set(needle, (hits.get(needle) || 0) + n2); lines += n2; }
  }
  // 兜底：任何仍指向被删目录的路径形状（映射表没覆盖到的具体文件）
  for (const d of DROPPED_DIRS) {
    const re = new RegExp(d.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '[A-Za-z0-9_.\\-/]*', 'g');
    const n = (text.match(re) || []).length;
    if (n) { text = text.replace(re, '开发流水账'); hits.set(d + '*', (hits.get(d + '*') || 0) + n); lines += n; }
  }
  for (const df of DROPPED_FILES) {
    if (rel === df) continue;
    const re = new RegExp(df.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g');
    const n = (text.match(re) || []).length;
    if (n) { text = text.replace(re, '开发流水账'); hits.set(df, (hits.get(df) || 0) + n); lines += n; }
  }
  if (text !== before) {
    changedFiles++; changedLines += lines;
    const bLines = before.split('\n').length, aLines = text.split('\n').length;
    // 行数只减不增是允许的（去掉行号形态会缩短句子），但绝不允许整段消失
    if (aLines < bLines - 2) { console.log(`REFUSE ${rel} 行数 ${bLines} -> ${aLines}`); process.exit(1); }
    if (mode === 'apply') fs.writeFileSync(f, text);
  }
}

let residual = 0;
for (const f of files) {
  const rel = path.relative(root, f).replace(/\\/g, '/');
  if (DROPPED_FILES.includes(rel) || DROPPED_DIRS.some(d => rel.startsWith(d))) continue;
  const t = fs.readFileSync(f, 'utf8');
  for (const d of DROPPED_DIRS) residual += (t.match(new RegExp(d.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '[A-Za-z0-9_.\\-/]*', 'g')) || []).length;
  for (const df of DROPPED_FILES) residual += (t.split(df).length - 1);
}

console.log(`TRIM-MODE ${mode} 扫文件=${files.length} 改写文件=${changedFiles} 改写处=${changedLines}`);
for (const [k, v] of [...hits.entries()].sort((a, b) => b[1] - a[1]).slice(0, 14)) console.log(`  规则 ${k} 命中 ${v}`);
console.log(`残留指向不随包目标的引用=${residual}`);
if (mode === 'apply' && residual > 0) { console.log('TRIM RESULT=FAIL 还有残留'); process.exit(1); }
console.log(residual === 0 ? 'TRIM RESULT=OK' : 'TRIM RESULT=PENDING（--check 只数不改）');
