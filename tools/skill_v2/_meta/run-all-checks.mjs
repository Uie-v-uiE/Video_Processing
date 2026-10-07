// run-all-checks.mjs —— 一条命令跑完整包的自证（元检查 + 每个校验脚本的 --self）
//
// 为什么要有：交付时"包是自洽的"这句话必须能被一条命令复跑，而不是靠人记三条命令。
// 三态纪律照本包的 `verify/three-state-verdicts`：判定词在行尾；没跑到的一律 NOT_MEASURED，不写"无异常"。
// 用法：node _meta/run-all-checks.mjs [本包根]
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const ROOT = path.resolve(process.argv[2] || path.join(path.dirname(path.resolve(process.argv[1] || '.')), '..'));
const rows = [];
function run(id, args) {
  const file = path.join(ROOT, ...args.slice(0, 1));
  if (!fs.existsSync(file)) { rows.push(`${id} ${args.join(' ')} 件不在盘上 NOT_MEASURED`); return; }
  let out = '', code = 0;
  try { out = execFileSync(process.execPath, args, { cwd: ROOT, encoding: 'utf8' }); }
  catch (e) { out = String(e.stdout || ''); code = e.status ?? 1; }
  const tail = out.trim().split(/\r?\n/).pop() || '(无输出)';
  const verdict = /FAIL/.test(tail.slice(-24)) ? 'FAIL' : code === 0 ? 'PASS' : 'FAIL';
  rows.push(`${id} ${tail.replace(/\s+/g, ' ').slice(-160)} ${verdict}`);
}
// ① 元检查两件
run('M1', ['_meta/check-selftest.mjs']);
run('M2', ['_meta/check-skill-package.mjs', ROOT]);
run('M3', ['_meta/build-index.mjs', ROOT, '--check']);
// ② 每个校验脚本条目的 --self（射程由遍历现算，不手写清单）
const selfs = [];
for (const cat of ['scripts']) {
  const base = path.join(ROOT, cat);
  if (!fs.existsSync(base)) continue;
  for (const e of fs.readdirSync(base, { withFileTypes: true })) {
    if (!e.isDirectory()) continue;
    const sd = path.join(base, e.name, 'scripts');
    if (!fs.existsSync(sd)) continue;
    for (const f of fs.readdirSync(sd)) if (/\.mjs$/.test(f)) selfs.push(`${cat}/${e.name}/scripts/${f}`);
  }
}
selfs.forEach((rel, i) => run(`S${i + 1}`, [rel, '--self']));
for (const r of rows) console.log(r);
const red = rows.filter(r => /FAIL$/.test(r)).length, nm = rows.filter(r => /NOT_MEASURED$/.test(r)).length;
console.log(`ALL-CHECKS 判 ${rows.length} 项 自测件=${selfs.length} 红=${red} 未测=${nm} ${red ? 'FAIL' : (nm ? 'NOT_MEASURED' : 'PASS')}`);
process.exit(red ? 1 : 0);
