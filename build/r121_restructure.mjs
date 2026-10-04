// r121_restructure.mjs —— 按交付要求 §0.3/§0.4 重排目录与文件名，并同批改口所有引用
//
// 用途: 一次算出"旧路径 → 新路径"的搬迁表（顶层目录归并 + 全小写化），执行搬迁并重写引用。
// 输入: 命令行 --check（只报数）或 --apply（真写盘；要求 git 工作树干净）
// 输出: 终端逐层计数；写盘时同步改所有跟踪文本文件里的旧路径/旧基名引用
// 退出码: 0=成功 1=前置不满足或断言失败 2=需要人工裁决的歧义（不自动改）
//
// 规矩（本仓库记过账的地方都在这儿）：
//  · 只搬不改内容语义：每个被改写的文件必须**行数不变**，否则 REFUSE（批量改口把文件改短=截断）。
//  · 歧义不猜：同名基名出现在两个目录时**不改裸基名**，只改带目录的全路径，并把歧义数打印出来。
//  · 豁免名单随工具走：README.md / README_EN.md / LICENSE / SKILL.md 是交付要求自己点名的名字。
//  · 大小写改名在 Windows 上要过临时名，否则新旧路径在大小写不敏感的盘上是同一个文件。
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const ROOT = process.cwd();
const MODE = process.argv.includes('--apply') ? 'apply' : (process.argv.includes('--check') ? 'check' : 'check');
const EXEMPT = ['README.md', 'README_EN.md', 'LICENSE', 'SKILL.md'];
const git = (a) => execFileSync('git', a, { cwd: ROOT, encoding: 'utf8' });

// 前置：工作树必须干净（把"改口波"和别的改动混在一次提交里就没法逐刀归因）
if (MODE === 'apply') {
  const dirty = git(['status', '--porcelain']).split(/\r?\n/).filter(Boolean).filter(l => !/^\?\? /.test(l));
  if (dirty.length) { console.log(`REFUSE 工作树不干净（${dirty.length} 项改动），先提交或撤销再搬 FAIL`); process.exit(1); }
}
const tracked = git(['ls-files']).split(/\r?\n/).filter(Boolean);
if (tracked.length < 500) { console.log(`REFUSE 跟踪文件只有 ${tracked.length}，射程没扫成 FAIL`); process.exit(1); }

// ① 顶层归并规则（§0.4：只留 src sim build board data skills report + 两个 README + LICENSE）
const DIR_MOVE = [
  [/^docs\/timing\//, 'report/timing/'],
  [/^docs\//, 'report/'],
  [/^submit\/reproduce\//, 'report/reproduce/'],
  [/^submit\//, 'report/'],
  [/^scripts\//, 'build/checks/'],
  [/^sim\/probes\//, 'build/sim/probes/'],
  // sim 里除 .v 与 README.md 之外的一切辅助件 ⇒ 挪进 build/sim/，名字不变（§2.1）
  { re: /^sim\/[^/]+\.(sh|tcl|do|py|mjs|txt|log|wdb|md)$/, to: (q) => (q === 'sim/README.md' ? q : 'build/sim/' + q.split('/').pop()) },
  [/^tight_setup_hold_pins\.txt$/, 'build/report/'],
  [/^NOTICE\.md$/, 'report/'],
];
const lower = (p) => p.split('/').map(seg => (EXEMPT.includes(seg) ? seg : seg.toLowerCase())).join('/');
function newPath(p) {
  let q = p;
  for (const rule of DIR_MOVE) {
    if (typeof rule === 'object' && !Array.isArray(rule)) { if (rule.re.test(q)) { q = rule.to(q); break; } continue; }
    const [re, to] = rule;
    if (typeof to === 'function') { if (re.test(q)) { q = to(q); break; } }
    else if (re.test(q)) { q = q.replace(re, to); break; }
  }
  return lower(q);
}
const moves = [];
for (const p of tracked) { const n = newPath(p); if (n !== p) moves.push({ from: p, to: n }); }

// ② 裸基名改口的歧义检查：同名基名对应多个旧路径 ⇒ 不改裸基名，只改全路径
const byBase = new Map();
for (const m of moves) byBase.set(path.basename(m.from), [...(byBase.get(path.basename(m.from)) || []), m]);
const ambiguous = [...byBase].filter(([, v]) => v.length > 1);
const safeBase = new Map([...byBase].filter(([, v]) => v.length === 1).map(([b, v]) => [b, v[0]]));

const textExt = /\.(md|sh|tcl|mjs|py|bat|cmd|csv|tsv|txt|json|xdc|xdc\.in|ps1)$/i;
const docFiles = tracked.filter(f => textExt.test(f) && !f.startsWith('build/evidence') && !f.startsWith('report/log/'));
console.log(`射程 跟踪=${tracked.length} 搬迁=${moves.length} 改口对象=${docFiles.length} 裸基名歧义=${ambiguous.length}（歧义只改全路径）`);
if (MODE === 'check') {
  const top = {};
  for (const m of moves) { const k = m.from.split('/')[0]; top[k] = (top[k] || 0) + 1; }
  console.log('按顶层统计搬迁 ' + Object.entries(top).map(([k, v]) => `${k}=${v}`).join(' '));
  console.log(`CHECK 未写盘 ${ambiguous.length ? 'NOT_MEASURED' : 'PASS'}`);
  process.exit(0);
}

// ③ 先重写引用（行数断言），后搬文件：这样"旧路径还在盘上"时新路径已可解析
let rewritten = 0, shortHits = 0, skipped = 0;
for (const f of docFiles) {
  const abs = path.join(ROOT, f);
  if (!fs.existsSync(abs)) { skipped++; continue; }
  const before = fs.readFileSync(abs, 'utf8');
  let t = before;
  for (const m of moves) {
    if (!t.includes(m.from)) continue;
    t = t.split(m.from).join(m.to);
  }
  for (const [b, m] of safeBase) {
    if (b === m.from) continue;
    if (t.includes(b)) t = t.split(b).join(m.to.split('/').slice(-1)[0]);
  }
  if (t === before) { shortHits++; continue; }
  const lb = before.split(/\r?\n/).length, la = t.split(/\r?\n/).length;
  if (lb !== la) { console.log(`REFUSE ${f} 行数 ${lb} -> ${la}（改口把文件改动了行数，疑似截断） FAIL`); process.exit(1); }
  fs.writeFileSync(abs, t); rewritten++;
}
console.log(`改口 重写文件=${rewritten} 无需改=${shortHits} 件不在盘上=${skipped} 全路径规则=${moves.length} 裸基名规则=${safeBase.size}`);

// ④ 搬迁：深路径先走，避免父目录先没了；大小写改名过临时名
const sorted = moves.slice().sort((a, b) => b.from.split('/').length - a.from.split('/').length);
let moved = 0, collide = [];
for (const m of sorted) {
  const src = path.join(ROOT, m.from), dst = path.join(ROOT, m.to);
  if (!fs.existsSync(src)) continue;
  if (fs.existsSync(dst) && path.resolve(src) !== path.resolve(dst)) { collide.push(m.from + ' -> ' + m.to); continue; }
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  if (m.from.toLowerCase() === m.to.toLowerCase()) {
    const tmp = dst + '.case-tmp';
    fs.renameSync(src, tmp); fs.renameSync(tmp, dst);
  } else fs.renameSync(src, dst);
  moved++;
}
console.log(`搬迁 实搬=${moved}/${sorted.length} 撞名未搬=${collide.length}${collide.length ? ' 例:' + collide.slice(0, 3).join(',') : ''} ${collide.length ? 'FAIL' : 'PASS'}`);
// 空目录在所有搬迁之后统一收
const gone = [];
const prune = (d) => {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) if (e.isDirectory()) prune(path.join(d, e.name));
  if (fs.readdirSync(d).length === 0 && !/\.git$/.test(d)) { fs.rmdirSync(d); gone.push(d.replace(ROOT + path.sep, '')); }
};
prune(ROOT);
console.log(`空目录收掉=${gone.length} 例:${gone.slice(0, 4).join(',')}`);
console.log(`RESTUCTURE 搬迁=${moved} 改口=${rewritten} 撞名=${collide.length} 空目录=${gone.length} ${collide.length ? 'FAIL' : 'PASS'}`);
process.exit(collide.length ? 1 : 0);
