// W13：把 code-reading.md 里每个围栏片段与源文件逐字对照。
// 用法：node w13_diff.mjs <md 路径> [容忍偏移量，默认 2]
// 判定词放最后一个字段；任何一片段不一致 => 红。
import fs from 'node:fs';

const md = process.argv[2] || 'docs/walkthrough/code-reading.md';
const TOL = Number(process.argv[3] ?? 2);
const CITE = /`(src|build|sim|board|report|data)\/([^\s`]+?):(\d+)(?:-(\d+))?`/g;

const lines = fs.readFileSync(md, 'utf8').split(/\r?\n/);
let last = null, blocks = [], inFence = false, cur = null;
for (let i = 0; i < lines.length; i++) {
  const l = lines[i];
  CITE.lastIndex = 0;
  let m;
  while ((m = CITE.exec(l))) last = { path: m[1] + '/' + m[2], start: Number(m[3]), at: i + 1 };
  if (/^\s*```/.test(l)) {
    if (!inFence) { inFence = true; cur = { cite: last, body: [], mdAt: i + 1 }; }
    else { inFence = false; if (cur && cur.body.length) blocks.push(cur); cur = null; }
    continue;
  }
  if (inFence && cur) cur.body.push(l);
}

let red = 0, checked = 0;
for (const b of blocks) {
  if (!b.cite) { console.log(`SKIP 片段 @md:${b.mdAt} 之前没有 文件:行 引用 NOT_MEASURED`); continue; }
  let src;
  try { src = fs.readFileSync(b.cite.path, 'utf8').split(/\r?\n/); }
  catch { console.log(`MISS ${b.cite.path} 打不开 FAIL`); red++; continue; }
  // 在 ±TOL 里找一个让整段逐字相等的偏移；找不到就取最长公共前缀做诊断
  let best = null;
  for (let off = -TOL; off <= TOL; off++) {
    const s = b.cite.start - 1 + off;
    if (s < 0 || s + b.body.length > src.length) continue;
    const ok = b.body.every((ln, k) => ln.replace(/\s+$/, '') === src[s + k].replace(/\s+$/, ''));
    if (ok) { best = { off, equal: b.body.length }; break; }
  }
  checked++;
  if (best) {
    console.log(`OK   ${b.cite.path}:${b.cite.start}${best.off ? `（实际在 ${b.cite.start + best.off}）` : ''} 片段 ${b.body.length} 行逐字一致`);
    if (best.off) red++;
  } else {
    let s = b.cite.start - 1, k = 0;
    while (k < b.body.length && (src[s + k] || '').replace(/\s+$/, '') === b.body[k].replace(/\s+$/, '')) k++;
    console.log(`DIFF ${b.cite.path}:${b.cite.start} 片段 ${b.body.length} 行，前 ${k} 行一致，第 ${k + 1} 行起不一致 FAIL`);
    console.log(`     md  : ${JSON.stringify(b.body[k] ?? '')}`);
    console.log(`     src : ${JSON.stringify((src[s + k] ?? '').slice(0, 120))}`);
    red++;
  }
}
console.log(`W13 片段核对 ${checked}/${blocks.length} 个，不一致或行号要挪的 ${red} 个 ${red ? 'FAIL' : (checked ? 'PASS' : 'NOT_MEASURED')}`);
process.exit(red ? 1 : 0);
