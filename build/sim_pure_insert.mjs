// 用途：证明 sim/tb_*.v 这一轮只做了**纯插入**——HEAD 里的每一行都按原顺序出现在工作树里。
// 输入输出：参数=可选的仓库相对路径列表（省略则扫全部 tb_*.v）；stdout 每文件一行；无文件产物。
// 退出码：0 全部为纯插入；1 存在丢行/改行；2 读不到基线（NOT_MEASURED）。
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..');
const run = (c) => { try { return execSync(c, { cwd: ROOT, encoding: 'utf8', maxBuffer: 1 << 28 }); } catch { return null; } };
const norm = (t) => t.split(/\r?\n/).map((l) => l.replace(/\r$/, ''));

let files = process.argv.slice(2);
if (files.length === 0) {
  const out = run('git ls-files sim');
  if (out === null) { console.log('PURE-INSERT 判 0 项 NOT_MEASURED git 不可用'); process.exit(2); }
  files = out.split('\n').filter((f) => /\/tb_[^/]+\.v$/.test(f));
}
let cmp = 0, red = 0, me = 0;
const rows = [];
for (const f of files) {
  const base = run(`git show HEAD:${f}`);
  const cur = fs.existsSync(path.join(ROOT, f)) ? fs.readFileSync(path.join(ROOT, f), 'utf8') : null;
  cmp++;
  if (base === null || cur === null) { red++; me++; rows.push(`${f} 基线或缺件 NOT_MEASURED`); continue; }
  const H = norm(base), C = norm(cur);
  let i = 0;
  for (const l of C) if (i < H.length && H[i] === l) i++;
  const lost = H.length - i;
  if (lost) {
    red++;
    const at = C.indexOf(H[Math.max(0, i - 1)]);
    rows.push(`${f} HEAD=${H.length} 命中=${i} 丢/改=${lost} 断点首行="${(H[i] || '').slice(0, 60)}" 位置≈${at + 1} FAIL`);
  } else {
    rows.push(`${f} HEAD=${H.length} 现=${C.length} 纯插入 PASS`);
  }
}
rows.forEach((r) => console.log(r));
console.log(`PURE-INSERT 判 ${cmp} 项 红=${red} 未测=${me} ${red ? 'FAIL' : me ? 'NOT_MEASURED' : 'PASS'}`);
process.exit(red ? 1 : 0);
