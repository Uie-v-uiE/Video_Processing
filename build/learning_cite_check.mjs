// 回读校验 LEARNING/*.md 里的每一条 `路径:行号` 与裸路径引用。
// 用法：node build/learning_cite_check.mjs [目录，默认 LEARNING]
// 判定：OK / NO_FILE / OUT_OF_RANGE / EMPTY_LINE / NOT_CODE（行存在但那行是注释，说明引用没落到实现上）
import fs from 'node:fs';
import path from 'node:path';

const ROOT = process.argv[2] && process.argv[2].includes(':') ? process.argv[2] : (process.argv[2] ? process.argv[2] : 'LEARNING');
const BASE = path.resolve('.');
const files = fs.readdirSync(ROOT).filter((f) => f.endsWith('.md')).sort();

// 只认"看起来像仓库内路径"的：必须以已知顶层目录开头，避免把 URL / 中文短语当路径
const HEADS = ['src/', 'sim/', 'build/', 'board/', 'data/', 'report/', 'skills/', 'study_docs/', 'LEARNING/'];
// 扩展名分支必须长前缀在前，且后面不能再跟字母数字——否则 `metrics.csv` 会被 `\.(?:…|c|…)` 截成 `metrics.c`
const RE = /([A-Za-z0-9_./-]*\/[A-Za-z0-9_.+-]+\.(?:md|mjs|txt|rpt|csv|xdc|bif|bin|bit|elf|xsa|tcl|sh|out|log|py|ld|v|c|h))(?![A-Za-z0-9._])(?::(\d+)(?:-(\d+))?)?/g;

let ok = 0, noFile = 0, outOfRange = 0, empty = 0, noteOnly = 0, bare = 0, declared = 0;
const bad = [];
// 同行写了"这东西不在树上"的话，那条路径就不是指路而是叙述：不判红，单独计数
const DECLARED = /不存在|不入库|不随包|没随包|未随包|仓库外|本机件|gitignore|从来没有|没留下|未留下|被 \.gitignore|挡着|捕获|写成|变成|举例|示例|这种三层路径|-Out |-log |输出目标/;
const lineCache = new Map();
const existsCache = new Map();

function linesOf(p) {
  if (!lineCache.has(p)) {
    try { lineCache.set(p, fs.readFileSync(path.join(BASE, p), 'utf8').split(/\r?\n/)); }
    catch { lineCache.set(p, null); }
  }
  return lineCache.get(p);
}
function has(p) {
  if (!existsCache.has(p)) existsCache.set(p, fs.existsSync(path.join(BASE, p)));
  return existsCache.get(p);
}

for (const f of files) {
  const txt = fs.readFileSync(path.join(ROOT, f), 'utf8').split(/\r?\n/);
  txt.forEach((line, i) => {
    let m;
    RE.lastIndex = 0;
    while ((m = RE.exec(line))) {
      const rel = m[1].replace(/^\.\//, '');
      if (!HEADS.some((h) => rel.startsWith(h))) continue;
      if (rel.includes('..')) continue;
      const a = m[2] ? Number(m[2]) : null;
      const b = m[3] ? Number(m[3]) : null;
      if (!has(rel)) {
        if (DECLARED.test(line)) { declared++; continue; }
        noFile++; bad.push(`${f}:${i + 1} NO_FILE ${rel}`); continue;
      }
      if (a === null) { bare++; ok++; continue; }
      const L = linesOf(rel);
      const hi = b && b > a ? b : a;
      if (hi > L.length) { outOfRange++; bad.push(`${f}:${i + 1} OUT_OF_RANGE ${rel}:${a}${b ? '-' + b : ''}（文件只有 ${L.length} 行）`); continue; }
      const seg = L.slice(a - 1, hi).join(' ').trim();
      if (!seg) { empty++; bad.push(`${f}:${i + 1} EMPTY_LINE ${rel}:${a}${b ? '-' + b : ''}`); continue; }
      // .v/.c/.h 且整段是注释 ⇒ 指路没落到实现上，单独计一类（不算错，只报数）
      if (/\.(v|c|h)$/.test(rel) && /^\s*(\/\/|\*|\/\*)/.test(L[a - 1].trim()) && !/\S/.test(L[a - 1].replace(/^\s*(\/\/|\*|\/\*)\s*/, ''))) noteOnly++;
      else ok++;
    }
  });
}

console.log(`LEARNING 引用回读  文件=${files.length}  判=${ok + noFile + outOfRange + empty}  OK=${ok}（其中裸路径=${bare}）  NO_FILE=${noFile}  OUT_OF_RANGE=${outOfRange}  EMPTY_LINE=${empty}  注释行=${noteOnly}`);
if (bad.length) {
  console.log('--- 明细（最多 60 条）---');
  for (const b of bad.slice(0, 60)) console.log(b);
  if (bad.length > 60) console.log(`…另有 ${bad.length - 60} 条`);
}
process.exit(noFile + outOfRange + empty > 0 ? 1 : 0);
