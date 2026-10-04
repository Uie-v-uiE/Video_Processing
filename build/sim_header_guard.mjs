// 用途：校验 sim/tb_*.v 的三段头注释已就位，且本次改动只增加了注释行。
// 输入输出：参数=仓库相对路径列表（省略则扫全部 tb_*.v）；stdout 每文件一行判定；无文件产物。
// 退出码：0 全部 PASS；1 存在 FAIL；2 参数/环境错误（NOT_MEASURED）。
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..');
const SEG = [
  ['功能', /^\/\/\s*功能：/],
  ['激励与检查', /^\/\/\s*激励与检查：/],
  ['预期结果', /^\/\/\s*预期结果：/],
];

function run(cmd) {
  try { return execSync(cmd, { cwd: ROOT, encoding: 'utf8', maxBuffer: 1 << 26 }); }
  catch (e) { return null; }
}
// 只留非注释、非空行，用于比较"逻辑有没有被动过"
function codeOnly(txt) {
  return txt.split(/\r?\n/).filter((l) => l.trim() !== '' && !/^\s*\/\//.test(l)).join('\n');
}

let files = process.argv.slice(2).filter((a) => !a.startsWith('-'));
if (files.length === 0) {
  const out = run('git ls-files sim');
  if (out === null) { console.log('SIM-HEADER-GUARD NOT_MEASURED git 不可用'); process.exit(2); }
  files = out.split('\n').filter((f) => /\/tb_[^/]+\.v$/.test(f));
}
if (files.length === 0) { console.log('SIM-HEADER-GUARD 判 0 项 NOT_MEASURED 名单为空'); process.exit(2); }

let cmp = 0, red = 0, me = 0;
const rows = [];
for (const f of files) {
  const abs = path.join(ROOT, f);
  if (!fs.existsSync(abs)) { rows.push(`${f} 缺文件 FAIL`); red++; cmp++; continue; }
  const now = fs.readFileSync(abs, 'utf8');
  const head = now.split(/\r?\n/).slice(0, 40);
  const miss = SEG.filter(([, re]) => !head.some((l) => re.test(l.trim()))).map(([n]) => n);
  const prev = run(`git show HEAD:${f}`);
  let drift = '无基线';
  if (prev !== null) drift = codeOnly(prev) === codeOnly(now) ? '同' : '异';
  cmp++;
  if (prev === null) me++;
  const verdict = miss.length ? 'FAIL' : drift === '异' ? 'FAIL' : 'PASS';
  if (verdict === 'FAIL') red++;
  rows.push(`${f} 缺段=${miss.join(',') || '无'} 逻辑改动=${drift} ${verdict}`);
}
rows.forEach((r) => console.log(r));
console.log(`SIM-HEADER-GUARD 判 ${cmp} 项 文件=${files.length} 红=${red} 未测=${me} ${red ? 'FAIL' : me ? 'NOT_MEASURED' : 'PASS'}`);
process.exit(red ? 1 : 0);
