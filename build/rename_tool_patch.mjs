// 用途：给"report/ 改名成 report/"这一轮用：**按行锚点**换掉工具里写死的名字
// 输入：无字面量输入路径；参数解析见本文件
// 输出：stdout
// 退出码：1=非 0 分支（该文件 exit 1 那一行）
// build/rename_tool_patch.mjs —— 给"report/ 改名成 report/"这一轮用：**按行锚点**换掉工具里写死的名字。
// 为什么按行锚点而不是整串字面匹配：这些行里嵌的是正则字面量（反斜杠成灾），
// 整串匹配今晚已经两次因为一个转义不符就 MISS；而行锚点（`const OLD_DIR =` 之类）是稳定可寻的。
// 规矩沿用今晚那张断言式补丁表：**每条都要命中，且只命中一次，否则一条都不写盘**。
import { readFileSync, writeFileSync } from 'node:fs';
const R = process.cwd() + '/';   // 在仓库根运行；不带本机盘符（交付要求 §6.2：命令必须照字面可执行）
// [文件, 行锚点(包含即匹配), 行内要找的旧 token, 行的新内容函数, 说明]
const L = [
  ['src/host/doc_currency_check.mjs', 'const OLD_DIR =', 'report', (l) => l.replace('report', 'docs'),
    'D4b 的"废弃目录名"从 report 翻成 docs（改名之后 docs/ 才是已经不存在的旧目录）'],
  ['src/host/doc_currency_check.mjs', 'const CITE_MD =', 'docs', (l) => l.replace('docs\\/log|docs', 'report\\/log|report'),
    'D4a 的指路前缀集合换成 report'],
  ['src/host/doc_currency_check.mjs', 'skill|docs', 'skill|docs',
    (l) => l.replace('skill|docs', 'skill|report'),
    'D4c 凭据前缀集合换成 report（这行在 new RegExp 里，锚点用它的名字交替段）'],
  ['src/host/doc_currency_check.mjs', '/^docs\\/', 'docs', (l) => l.replace('docs', 'report'),
    '交付文档判定：^report/ → ^report/'],
  ['src/host/doc_currency_check.mjs', 'HAND_SKIP_PREFIX =', "'report/study/'",
    (l) => l.replace("'report/study/'", "'report/study/'"),
    '学习件排除目录换成 report/study'],
  // D4b 与 D4a/D4c 用同一套"出处决定严重度"的口径：交付文档里念旧名 ⇒ 判红；
  // 日记/注释里那句"当年那个 report/ 拆成 docs/"是历史叙述，判红等于逼我伪造记录（#172 那一族）。
  ['src/host/doc_currency_check.mjs', 'D4b 还在指已经删掉的旧目录', 'rows.push',
    (l) => l.replace('rows.push(`${at} D4b 还在指已经删掉的旧目录：${l.trim().slice(0, 70)}`);',
                     '{ const r = `${at} D4b 还在指已经删掉的旧目录：${l.trim().slice(0, 70)}`; if (hard) rows.push(r); else adv.push(r); }'),
    'D4b 改成"交付文档判红、日记与注释只报数"（与 D4a/D4c 同口径）'],
  ['src/host/doc_currency_check.mjs', "'report/perf_report.md', 'report/build.md'", 'docs',
    (l) => l.split("'report/").join("'report/"),
    'D1 盯的清单第一行（含 BUILD/CONTEST 那三项）'],
  ['src/host/doc_currency_check.mjs', "'report/demo_script.md'", 'docs', (l) => l.split("'report/").join("'report/"),
    'D1 盯的清单第二行'],
  ['src/host/doc_enc_check.mjs', 'const SCOPE =', "'docs'", 'docs',
    '手写件扫描目录：docs → report'],
  ['src/host/line_cite_check.mjs', 'const DOC_DIRS =', 'docs', (l) => l.split("'docs").join("'report"),
    'D5 扫描目录：docs → report'],
  ['src/host/line_cite_check.mjs', 'const SKIP_DOCS =', 'docs', (l) => l.split('report/').join('report/'),
    'D5 排除：report/log 与 report/study → report 同名'],
  ['src/host/demo_cmds.mjs', 'path.join(ROOT, \'docs\'', 'docs', (l) => l.replace("'docs'", "'report'"),
    '讲稿抽取器读的是 report/demo_script.md'],
];
const plans = new Map();
let bad = 0;
for (const [rel, anchor, token, fn, why] of L) {
  if (!plans.has(rel)) plans.set(rel, readFileSync(R + rel, 'utf8'));
  const lines = plans.get(rel).split('\n');
  const hits = [];
  lines.forEach((l, i) => { if (l.includes(anchor) && l.includes(token)) hits.push(i); });
  if (hits.length !== 1) {
    console.log(`MISS ${rel} 锚点 "${anchor}"：命中 ${hits.length} 行（要正好 1）—— ${why}`);
    bad++; continue;
  }
  const i = hits[0];
  const nl = typeof fn === 'function' ? fn(lines[i]) : lines[i].split(fn).join('report/');
  if (nl === lines[i]) { console.log(`NOOP ${rel}:${i + 1} 锚点对上了但内容没变 —— ${why}`); bad++; continue; }
  lines[i] = nl;
  plans.set(rel, lines.join('\n'));
  console.log(`HIT  ${rel}:${i + 1} —— ${why}`);
}
if (bad) { console.log(`ABORT：${bad} 条不符合预期，一个字节都不写`); process.exit(1); }
for (const [rel, txt] of plans) { writeFileSync(R + rel, txt); console.log(`WROTE ${rel}`); }
