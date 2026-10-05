#!/usr/bin/env node
// 作用：把 `report/README.md` "怎么读"那张表的**长度列**按文件实际行数改写（用途：改口轮里唯一合法的"数字自己算"）
// 输入：可选位置参数 = 目标 README 路径，默认 `report/README.md`；`--write` 才真写盘（不加只报数）
// 输出：stdout 每行 `ROW <文件> <旧> → <新>`，最后一行 RESULT；退出码 0 改写或持平、1 行数对不上（表格被改坏）、2 找不到表
// 为什么：交付文档里"这份多少行"是**关于文档自己的事实**，一旦正文被改，这一格立刻失实；
//   但它又是一个可现算的数，所以不该由人抄——由这把小工具按盘上的文件算。
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
// 位置参数只取不以 -- 开头的那一个：早先直接拿 argv[2]，于是 `--write` 被当成文件名，
// 报出来的是"REFUSE 没有 --write"——一句看起来像缺参数、实际是参数被位置参数吃掉的假话。
const rel = process.argv.slice(2).find(a => !a.startsWith('--')) || 'report/README.md';
const abs = path.join(root, rel);
if (!fs.existsSync(abs)) { console.log(`REFUSE 没有 ${rel}`); process.exit(2); }
const lines = fs.readFileSync(abs, 'utf8').split('\n');
const rows = lines.map((l, i) => [i, l]).filter(([, l]) => /^\| \d+ \| `/.test(l));
if (!rows.length) { console.log('REFUSE 找不到"怎么读"那张表（行首形如 `| 1 | \\`` 的行 0 条）'); process.exit(2); }

let changed = 0, kept = 0;
const baseDir = path.dirname(abs);
function resolve(name) {
  const cand = [path.join(baseDir, name), path.join(root, name)];
  return cand.find(p => fs.existsSync(p)) || null;
}
for (const [i, l] of rows) {
  const cells = l.split('|').map(s => s.trim());
  const filecol = cells[2] || '';       // 第 2 格 = 文件列；第 3 格是"它回答什么"，第 4 格才是长度
  const parts = [];
  for (const m of filecol.matchAll(/`([\w./\-]+\.(?:md|csv|tsv))`/g)) {
    const p = resolve(m[1]);
    if (!p) { parts.push(`${m[1]} 不在盘上`); continue; }
    parts.push(`${fs.readFileSync(p, 'utf8').split('\n').length} 行`);
  }
  for (const m of filecol.matchAll(/`([\w./\-]+\/)`/g)) {
    const p = resolve(m[1]);
    const n = p ? fs.readdirSync(p).filter(f => /\.(md|txt|csv|json)$/.test(f)).length : 0;
    parts.push(`${n} 份`);
  }
  if (!parts.length) { console.log(`ROW-未算 ${filecol}（这一格没有可现算的路径，保持原样）`); continue; }
  const next = parts.join(' + ');
  if (cells[4] === next) { kept++; continue; }
  const prev = cells[4];
  cells[4] = next;
  lines[i] = '| ' + cells.slice(1, -1).join(' | ') + ' |';
  console.log(`ROW ${filecol.replace(/\|/g, '/')} "${prev}" → "${next}"`);
  changed++;
}
const out = lines.join('\n');
if (out.split('\n').length !== fs.readFileSync(abs, 'utf8').split('\n').length) {
  console.log('RESULT=RED 行数变了（只该改一格内容，不该增删行）'); process.exit(1);
}
if (process.argv.includes('--write')) {
  fs.writeFileSync(abs, out);
  console.log(`RESULT=WRITTEN 改 ${changed} 格 已对 ${kept} 格`);
} else {
  console.log(`RESULT=CHECK 待改 ${changed} 格 已对 ${kept} 格`);
}
