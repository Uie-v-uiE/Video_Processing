// 2026-10-07 队定案（方案 A）：`data/metrics.csv:25` 那个 33.34 ms 是 **PL 内的入流帧间隔**，
// 不是端到端时延，而且它原来连轮次都挂错了（写"一轮 600 帧"，凭据是 9000 帧 / 300 s 那一轮）。
// 凭据：`report/perf_report.md:195` 第①条（"只有 PL 内部…不许叫端到端时延"）+
//       `report/perf_report.md:205-208`（min/avg/max = 20/33.34/51 属于"长跑那一行"：9000 帧 / 5.02 分钟）+
//       `board/evidence_r41/metrics_r41_soak300.md` 的 gap_sum/gap_segments = 33.3434 ms（8999 段）。
// 本工具一次改三棵树里所有引用这一格的地方；端到端那一格（metrics.csv:20）保持"未报"不动。
// 作用：把"端到端时延"那一格的口径改口轮一次做完——输入是三棵树里的现文，输出是同一批文件被改写。
// 退出码：0 = 全部规则判完且无坏规则（--check 不落盘）；1 = 有坏规则、Σ 不闭合，或没给树根。
// 用法：node build/r127_latency_rename.mjs --check|--apply <树根> [<树根> …]
import fs from 'node:fs';
import path from 'node:path';

const APPLY = process.argv.includes('--apply');
const TREES = process.argv.slice(2).filter((a) => !a.startsWith('--')).map((a) => a.replace(/[\\/]+$/, ''));
if (!TREES.length) { console.log('用法：node build/r127_latency_rename.mjs --check|--apply <树根> …'); process.exit(1); }

const CSV_OLD = '端到端时延,核心,33.34,ms,从上位机发出到屏上出现；min/avg/max = 20 / 33.34 / 51 ms，同轮墙钟交付 29.79 fps（≈9.15 MB/s = 73.2 Mbps）；测量起点=上位机发送时刻，终点=示相机位录到该帧上屏,一轮 600 帧,report/perf_report.md';
const CSV_NEW = '入流帧间隔（PL 内）,核心,33.34,ms,PL 侧收包链量的相邻两帧之间隔（`gap_sum/gap_segments` 件内自报 33.3434 ms、8999 段）；min/avg/max = 20 / 33.34 / 51 ms；同轮墙钟交付 29.79 fps（≈9.15 MB/s = 73.2 Mbps）；只含 PL 内部——不含上位机编码、网线与交换机排队（口径见 `report/perf_report.md:195` 第①条）,9000 帧 / 300 s 那一轮,report/perf_report.md';

// [文件, 旧串, 新串, 说明]
const RULES = [
  ['data/metrics.csv', CSV_OLD, CSV_NEW, '指标表那一行本体'],
  ['report/measurements.md',
   '| 端到端时延（上位机发出 ↔ 屏上出现） | 核心 | 33.34 | ms | ①共用 ②min/avg/max 三位（20 / 33.34 / 51 ms）③30 fps 限速一轮 ④同一轮墙钟交付 29.79 fps ⑤`eth_rxc` 125 MHz + 显示 50 MHz ⑥无 DVFS；测量起点=上位机发送时刻，终点=示相机位录到该帧上屏（`data/metrics.csv:25`） | 一轮 600 帧 |',
   '| 入流帧间隔（PL 内，不是端到端时延） | 核心 | 33.34 | ms | ①共用 ②min/avg/max 三位（20 / 33.34 / 51 ms）③30 fps 限速 ④同一轮墙钟交付 29.79 fps ⑤计数在 `eth_rxc` 125 MHz 域 ⑥无 DVFS；量的是 PL 收包链相邻两帧之间隔（`gap_sum/gap_segments` 件内自报 33.3434 ms、8999 段），不含上位机编码、网线与交换机排队（`report/perf_report.md:195` 第①条）（`data/metrics.csv:25`） | 9000 帧 / 300 s 那一轮 |',
   '测量条件表那一行'],
  ['report/technical-document.md',
   '- 端到端时延这一格有读数出口（OSD 的 Latency lane），但只有一轮 600 帧的可信值 33.34 ms，\n  没做多次复测 ⇒ 指标表里如实标条件。',
   '- 端到端时延那一格只有出口（OSD 的 `Latency` lane）没有值，指标表里写的是 `未报`；33.34 ms 是 PL 内的**入流帧间隔**，\n  原先挂在"端到端时延"名下且轮次写成"一轮 600 帧"，本轮按凭据改名并把轮次写成 9000 帧 / 300 s（台账 #416）。',
   '技术文档 §6.4 那条限制（主树措辞）'],
  ['report/technical-document.md',
   '- 端到端时延有读数出口（OSD 的 Latency lane），但只有一轮 600 帧的可信值 33.34 ms，\n  多次复测没做，指标表里按这个条件标注。',
   '- 端到端时延只有出口（OSD 的 `Latency` lane）没有值，指标表那一格写 `未报`；33.34 ms 是 PL 内的**入流帧间隔**，\n  原先挂在"端到端时延"名下且轮次写成"一轮 600 帧"，本轮按凭据改名并把轮次写成 9000 帧 / 300 s（台账 #416）。',
   '技术文档同一条（提交分支措辞）'],
  ['report/technical-document.md',
   '| 端到端时延 | 33.34 ms（min 20 / max 51） | 上位机发出 → 示相机录到该帧上屏，一轮 600 帧 |',
   '| 入流帧间隔（PL 内） | 33.34 ms（min 20 / max 51） | PL 收包链相邻两帧之间隔；9000 帧 / 300 s 那一轮；不含编码、网线与交换机排队 |',
   '技术文档 §7 结果表那一行'],
  ['report/08-limits.md',
   '  而同一张表另一行"端到端时延,核心,33.34,ms"是旧轮的实测行 ⇒ 同名两行、状态不同。',
   '  另一行原写"端到端时延,核心,33.34,ms"，2026-10-07 按凭据改名"入流帧间隔（PL 内）"（`gap_sum/gap_segments` 自报 33.3434 ms）⇒ 同名两行的矛盾消失，端到端那一格仍是未报。',
   '限制册 §10 现象（主树措辞）'],
  ['report/08-limits.md',
   '  同一张表另一行"端到端时延,核心,33.34,ms"是旧轮的实测行：同名两行、状态不同。',
   '  另一行原写"端到端时延,核心,33.34,ms"，2026-10-07 按凭据改名"入流帧间隔（PL 内）"（`gap_sum/gap_segments` 自报 33.3434 ms）⇒ 同名两行的矛盾消失，端到端那一格仍是未报。',
   '限制册 §10 现象（提交分支措辞）'],
  ['report/50-results.md',
   '端到端时延那一行有两格——第 20 行标"未报/—/待复测"，第 25 行标 33.34 ms（一轮 600 帧）；',
   '端到端时延只剩第 20 行那一格（未报/—/待复测）；第 25 行原挂同名、标 33.34 ms 且写"一轮 600 帧"，2026-10-07 按凭据改名"入流帧间隔（PL 内）"并把轮次写成 9000 帧 / 300 s；',
   '结果册正文（只主树有这份）'],
  ['report/50-results.md',
   '| 端到端时延（一轮 600 帧） | 33.34（min/avg/max 20 / 33.34 / 51） | ms | 起点=上位机发送时刻、终点=示相机位录到上屏；同轮墙钟交付 29.79 fps；**与第 1 张表里"未报/待复测"那一格并列时不给当前这一版借用** | `data/metrics.csv` 第 20、25 行 |',
   '| 入流帧间隔（PL 内，9000 帧 / 300 s 那一轮） | 33.34（min/avg/max 20 / 33.34 / 51） | ms | `gap_sum/gap_segments` 件内自报 33.3434 ms、8999 段；同轮墙钟交付 29.79 fps；不含上位机编码、网线与交换机排队，**不是端到端时延**；端到端那一格仍是"未报/待复测" | `data/metrics.csv` 第 20、25 行、`report/perf_report.md:205` |',
   '结果册表行（只主树有这份）'],
  ['report/90-open-items.md',
   '改的是指标表口径，属敏感动作 ⇒ 需点头',
   '改的是指标表口径，属敏感动作 ⇒ 2026-10-07 队点头走前一条：第 25 行改名「入流帧间隔（PL 内）」、轮次写对（9000 帧 / 300 s，件内自报 33.3434 ms），端到端那一格仍是未报（台账 #416）',
   '未闭合项 #19 的处置格（主树）'],
  ['board/raw-vs-golden.md',
   '**不改 `data/`**（禁区） | 队伍二选一：把那行改成「帧间隔/抖动」口径，或补一次带仪器凭据的真时延轮',
   '2026-10-07 经队点头动 `data/`：那行已改名「入流帧间隔（PL 内）」并把轮次写对（9000 帧 / 300 s，件内自报 `avg_gap_ms=33.3434`）；真时延那一格仍是 `未报` | 剩下只有一件事：要对外报端到端时延，就得补一次带仪器凭据的轮（台账 #416）',
   'U7 的源头行（提交分支的 90-open-items 由 build/submit_open_items.mjs 从这行现生成，不能手改表）'],
];

let fired = 0, already = 0, bad = 0, absent = 0, na = 0, rules = 0;
for (const tree of TREES) {
  if (!fs.existsSync(tree)) { console.log(`跳过（树不在）：${tree}`); rules += 0; continue; }
  const staged = new Map();
  for (const [f, oldS, newS, why] of RULES) {
    rules++;
    const p = path.join(tree, f);
    if (!fs.existsSync(p)) { absent++; continue; }
    let t = staged.get(p) ?? fs.readFileSync(p, 'utf8');
    const nNew = t.split(newS).length - 1;
    const nOldOutside = t.split(newS).join('').split(oldS).length - 1;
    // 四态：1/0=该改口；0/1=已改口；0/0=本树没有这句（两棵树措辞不同，属正常）；其余=坏
    if (nOldOutside === 1 && nNew === 0) { staged.set(p, t.replace(oldS, newS)); fired++; }
    else if (nOldOutside === 0 && nNew === 1) { already++; }
    else if (nOldOutside === 0 && nNew === 0) { na++; }
    else { bad++; console.log(`BAD  ${p}  旧(挖掉新后)=${nOldOutside} 新=${nNew}：${why}`); }
  }
  for (const [p, t] of staged) {
    const before = fs.readFileSync(p, 'utf8');
    if (before.split('\n').length !== t.split('\n').length) { console.log(`REFUSE 行数会变：${p}`); process.exit(1); }
    if (APPLY) fs.writeFileSync(p, t, 'utf8');
    console.log(`${APPLY ? '已改' : '待改'} ${p}`);
  }
}
console.log(`入流帧间隔改口  规则×树=${rules}  命中=${fired}  已改口=${already}  本树无此句=${na}  不命中/坏=${bad}  文件不在=${absent}  ${APPLY ? '已写盘' : '（--check 未写盘）'}`);
if (fired + already + na + bad + absent !== rules) { console.log(`REFUSE 判定条数 ${fired + already + na + bad + absent} ≠ 规则×树 ${rules}`); process.exit(1); }
if (bad) { console.log('REFUSE 有坏规则，未写盘'); process.exit(1); }
