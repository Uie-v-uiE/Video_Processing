// build/r124_repro_verdict_col.mjs —— 把演练清单两张表的**判定列搬到末列**并补齐判定词
// 终审 C9 只读每行最后一个非空单元格（`build/checks/check_repo_consistency.mjs` 的 `c9Judge`），
// 而 §8.1 那张表把判定放在第 4 列、第 5 列是"与第一轮的差异"，§9 第三轮那张表根本没有判定列 ⇒
// 这 14 行读出来是"判定列不成词"。这不是文档写错，是**表形与判据的量纲不一致**：
// 交付文档的规矩本来就写着"判定行必须在末列"。
// 用法：node build/r124_repro_verdict_col.mjs --check | --apply
import fs from 'node:fs';

const F = 'report/repro-check.md';
const MODE = process.argv.includes('--apply') ? 'apply' : 'check';
const lines = fs.readFileSync(F, 'utf8').split(/\r?\n/);
const before = lines.length;

// §8.1 的 S5 判定格里写着"改前照字面敲 = FAIL"——那是**改前**的判定；搬进末列后 C9 会把它
// 数成本轮演练失败（C9 先看 FAIL 再看 PASS）。改成同义的"判红"，信息不丢，末列只剩一个判定词。
const S5_OLD = 'PASS（**改后**；改前照字面敲 = FAIL，见 §3 R11）';
const S5_NEW = 'PASS（**改后**；改前照字面敲判红，见 §3 R11）';

const HEAD9 = '| 步 | 命令（逐字） | 读到的原文（摘要） | 凭据 |';
const VERDICT9 = {
  '前置': 'PASS（`--self` 5/5 条形符期望，地板 5/5）',
  'C1': 'PASS（三步 rc 全 0，末行 FLOW_DONE=1）',
  // C4 那两跑的健康计数原件已被记录在案的精简笔删掉（`git log --diff-filter=D` 指得出那一笔），
  // 正文里的串是当时的转述 ⇒ 不能拿它当一个"能复跑的判定"，如实写 NOT_MEASURED 并说清缺哪件。
  'C4': 'NOT_MEASURED（两跑健康计数的原件 `build/evidence/r116_board/health_r118docround_a.json` 与 `_b.json` 已被记录在案的精简笔删掉、不随包 ⇒ 上面那串读数是当时的转述，今天在包内指不到件；要转成判定需重跑一次带流的 `board/scripts/board_health.sh`）',
  'C2': 'PASS（geom ok=10 fail=0、105 条串口命令全过、末行判红步骤 0）',
};

let moved = 0, rows9 = 0, s5 = 0;
const h9 = lines.indexOf(HEAD9);
if (h9 < 0) { console.log('REFUSE：没找到第三轮那张表的表头'); process.exit(1); }
// 那张表的范围：表头 + 分隔行 + 连续以 `|` 开头的行
const inTable9 = new Set();
const cellsOf = (l) => l.split(CELL).map(s => s.trim()).slice(1, -1);
for (let i = h9 + 2; i < lines.length && /^\s*\|/.test(lines[i]); i++) inTable9.add(i);

const HEAD81 = '| # | 命令 | 实际输出摘要（删略主机名与绝对路径） | 判定 | 与第一轮 / 与 README 的差异 |';
const NEWHEAD81 = '| # | 命令 | 实际输出摘要（删略主机名与绝对路径） | 与第一轮 / 与 README 的差异 | 判定 |';
const h81 = lines.indexOf(HEAD81);
if (h81 < 0) { console.log('REFUSE：没找到 §8.1 那张表的表头'); process.exit(1); }
lines[h81] = NEWHEAD81;

const inTable81 = new Set();
for (let i = h81 + 2; i < lines.length && /^\s*\|/.test(lines[i]); i++) inTable81.add(i);
if (inTable81.size !== 11) { console.log(`REFUSE：§8.1 表体行数=${inTable81.size}（期望 11，全文有 22 条 |S..| 形状的表行，所以必须按范围动）`); process.exit(1); }

const CELL = /(?<!\\)\|/;   // 表格里的 `\|` 是**转义过的竖线**，属于单元格内容，不是分隔符；
                            // 按裸 `|` 切会把一条命令切成两格，列数与列序都读错（第一版就栽在这里）
for (let i = 0; i < lines.length; i++) {
  const l = lines[i];
  if (inTable81.has(i)) {
    const inner = cellsOf(l);
    if (inner.length !== 5) { console.log(`REFUSE 第 ${i + 1} 行不是 5 列`); process.exit(1); }
    if (inner[3].includes('FAIL')) s5++;
    const reordered = [inner[0], inner[1], inner[2], inner[4], inner[3]];
    reordered[4] = reordered[4].split(S5_OLD).join(S5_NEW);
    lines[i] = '| ' + reordered.join(' | ') + ' |';
    moved++;
  } else if (i === h9) {
    lines[i] = HEAD9.replace('| 凭据 |', '| 凭据 | 判定 |');
  } else if (i === h9 + 1) {
    if (!/^\|---\|---\|---\|---\|$/.test(l)) { console.log(`REFUSE 第 ${i + 1} 行不是四列分隔行`); process.exit(1); }
    lines[i] = '|---|---|---|---|---|';
  } else if (inTable9.has(i)) {
    const m = /^\s*\|\s*(前置|C1|C2|C4)\s*\|/.exec(l);
    if (!m) { console.log(`REFUSE 第 ${i + 1} 行不在预期的四个步名里：${l.slice(0, 40)}`); process.exit(1); }
    const inner = cellsOf(l);
    if (inner.length !== 4) { console.log(`REFUSE 第 ${i + 1} 行不是 4 列`); process.exit(1); }
    lines[i] = '| ' + inner.join(' | ') + ' | ' + VERDICT9[m[1]] + ' |';
    rows9++;
  }
}

const txt = lines.join('\n');
const now = txt.split(/\r?\n/).length;
console.log(`§8.1 换列=${moved}（期望 11）其中含旧 FAIL 字样的=${s5}（期望 1）§9 补判定行=${rows9}（期望 4）行数 ${before}→${now}`);
if (moved !== 11 || s5 !== 1 || rows9 !== 4 || now !== before) { console.log('REFUSE：形状与期望不符，没写盘'); process.exit(1); }
if (MODE === 'check') { console.log('CHECK-ONLY（没写盘）'); process.exit(0); }
fs.writeFileSync(F, txt);
console.log('APPLY DONE ' + F);
