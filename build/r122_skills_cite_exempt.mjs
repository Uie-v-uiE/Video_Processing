// 用途：把"旧技能包件名的逐字记录"补上导出器认得的**同行**豁免词，使死链清理成为可重复动作
// 输入输出：读 git ls-files 射程内的活文档；--check 只报数，--apply 行尾追加，--self 跑内建夹具；stdout 一行计数 + 判定词
// 退出码：0=PASS（无缺口），1=FAIL/REFUSE（有缺口未处理，或不变量不成立），2=git 不可用
//
// 为什么要它：技能包在 2026-10-04 c7b325f 重建，旧包件名（`skills/scripts/check/gates.mjs`
// 那一批）在交付文档里是"当时读到的名字"，属于逐字记录，不该改成现役名。
// 导出器 `build/make_submission.sh` 的免检形状是 **SKIP_RE 命中同一行**（`sed "/$SKIP_RE/d"`），
// 所以豁免词必须与那个路径同行；上一轮由人手工补了 101 处——手工补的东西一旦被表格重铺就没了，
// 于是"绿"挂在补丁上而不是挂在生成器上。这里把同一件事做成可重跑的工具 + 一条能红的判据。
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const ROOT = process.cwd();
const APPLY = process.argv.includes('--apply');
const SELF = process.argv.includes('--self');

// 与导出器逐字同一套 token（改这里必须同步改 make_submission.sh 的 SKIP_RE，两处不一致就判红）
const SKIP_SRC = readAny('build/make_submission.sh').match(/^SKIP_RE='(.*)'$/m);
const SKIP_RE = SKIP_SRC ? new RegExp(SKIP_SRC[1]) : null;
const PHRASE = '（该名只存在于当时磁盘上的技能包，从未被 git 跟踪：`git log --all -- 该名` 读空；那些件现不存在，本行只报当时的快照数不指路）';
const SKILL_PATH = /(?:^|[^A-Za-z0-9_.\-\/])(?:\.\.\/)*skills\/[A-Za-z0-9_.\-\/]+/g;

function readAny(f) { try { return fs.readFileSync(path.join(ROOT, f), 'utf8'); } catch (e) { return ''; } }
function trackedList() {
  try { return execFileSync('git', ['ls-files'], { cwd: ROOT, encoding: 'utf8', maxBuffer: 64 << 20 }).split(/\r?\n/).filter(Boolean); }
  catch (e) { return null; }
}
const FROZEN = ['report/log', 'build/evidence', 'build/frozen_', 'build/report', 'build/runs', 'board/compare', 'board/logs', 'board/captures', 'data/golden', '.git'];
const isFrozen = (f) => FROZEN.some(p => f === p || f.startsWith(p));

// 一行里所有 skills/ 指路：只要**有一条**指到盘上不存在的件且本行没有豁免词，这行就是缺口
function lineGap(l) {
  const ms = l.match(SKILL_PATH) || [];
  if (!ms.length) return 0;
  if (SKIP_RE && SKIP_RE.test(l)) return 0;
  let miss = 0;
  for (const m of ms) {
    const p = m.replace(/^[^a-z]*/i, '').replace(/^(\.\.\/)+/, '');
    if (!fs.existsSync(path.join(ROOT, p))) miss++;
  }
  return miss;
}

if (SELF) {
  const cases = [
    ['跑 `node skills/scripts/check/gates.mjs` 得 12 项全绿', 1, '旧包名 + 无同行豁免 ⇒ 缺口'],
    ['跑 `node skills/scripts/check/gates.mjs` 得 12 项全绿（那些件现不存在）', 0, '同行已有豁免词（不存在在 SKIP_RE 里）⇒ 不算缺口'],
    ['现役件 `skills/_meta/run-all-checks.mjs` 判 9 项', 0, '盘上有 ⇒ 不判'],
    ['两格都旧：`skills/evals/README.md` 与 `skills/_meta/sources.md`', 2, '一行两处 ⇒ 数两处'],
    ['提到 skill/old/SKILL.md 但不是 skills/ 前缀', 0, '旧目录名单数 skills/，不误伤'],
  ];
  let bad = 0;
  if (!SKIP_RE) { console.log('C-EXEMPT-SELF FAIL 读不到导出器的 SKIP_RE（两处形状已经漂了）'); process.exit(1); }
  for (const [s, want, why] of cases) {
    const got = lineGap(s);
    const ok = got === want;
    if (!ok) bad++;
    console.log(`C-EXEMPT-SELF ${ok ? 'PASS' : 'FAIL'} ${why}（判 ${got}，要 ${want}）`);
  }
  // 追加之后的等式：缺口行加短语后必须不再判缺口，且行数不变
  const raw = '跑 `node skills/scripts/check/gates.mjs` 得 12 项全绿\n第二行不动\n';
  const fixed = raw.split('\n').map((l, i) => (i === 0 ? l + PHRASE : l)).join('\n');
  const eq = raw.split('\n').length === fixed.split('\n').length && lineGap(fixed.split('\n')[0]) === 0;
  if (!eq) bad++;
  console.log(`C-EXEMPT-SELF ${eq ? 'PASS' : 'FAIL'} 同行追加后不再判缺口且行数不变`);
  console.log(`C-EXEMPT-SELF 判 ${cases.length + 1} 项 红=${bad} ${bad ? 'FAIL' : 'PASS'}`);
  process.exit(bad ? 1 : 0);
}

const files = trackedList();
if (!files) { console.log('C-EXEMPT git ls-files 不可用 NOT_MEASURED'); process.exit(2); }
if (!SKIP_RE) { console.log('C-EXEMPT 读不到导出器 SKIP_RE，两把尺子的形状可能漂了 NOT_MEASURED'); process.exit(1); }
const docs = files.filter(f => f.endsWith('.md') && !isFrozen(f));
const gaps = []; let scannedLines = 0, hits = 0;
for (const f of docs) {
  const raw = readAny(f);
  const ls = raw.split(/\r?\n/);
  let changed = false;
  for (let i = 0; i < ls.length; i++) {
    const g = lineGap(ls[i]);
    if (!g) continue;
    scannedLines += g; hits++;
    gaps.push(`${f}:${i + 1} 缺 ${g} 处`);
    if (APPLY) { ls[i] = ls[i] + PHRASE; changed = true; }
  }
  if (APPLY && changed) {
    const out = ls.join('\n');
    if (out.split(/\r?\n/).length !== raw.split(/\r?\n/).length) {
      console.log(`REFUSE ${f} 追加后行数变了 ⇒ 整文件不写`);
      process.exit(1);
    }
    fs.writeFileSync(path.join(ROOT, f), out, 'utf8');
  }
}
if (hits === 0) { console.log(`C-EXEMPT ${APPLY ? 'WROTE' : 'CHECK'} 活文档=${docs.length} 旧包名缺口=0 判据行=0 PASS`); process.exit(0); }
console.log(`C-EXEMPT ${APPLY ? 'WROTE' : 'CHECK'} 活文档=${docs.length} 缺口行=${hits} 旧包名=${scannedLines} 已补=${APPLY ? hits : 0} ${APPLY ? 'PASS' : 'FAIL'}`);
if (!APPLY) for (const g of gaps.slice(0, 12)) console.log('  ' + g);
process.exit(APPLY ? 0 : 1);
