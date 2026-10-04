// 用途：从 sim/tb_*.v 的三段头注释生成 sim/README.md 的四列表格（文件名 → 被测模块 → 功能 → 预期结果）。
// 输入输出：读 git ls-files 里的 sim/tb_*.v 与 sim/models 侧的非 tb 文件计数；写 sim/README.md（--check 时只打印不落盘）。
// 退出码：0 一致或写出成功 1 有台架缺段/表格与文件名单不一致 2 git 或写盘失败。
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..');
const APPLY = process.argv.includes('--apply');
const run = (c) => { try { return execSync(c, { cwd: ROOT, encoding: 'utf8', maxBuffer: 1 << 28 }); } catch { return null; } };
const files = (run('git ls-files sim') || '').split('\n').filter((f) => /\/tb_[^/]+\.v$/.test(f)).sort();
if (files.length === 0) { console.log('GEN-SIM-README 判 0 项 NOT_MEASURED 名单为空'); process.exit(2); }

// 把头注释里三个前缀的行块取出来（续行 = 以 // 开头且不带新前缀）
function sections(txt) {
  const lines = txt.split(/\r?\n/);
  const out = {};
  let cur = null;
  for (const l of lines.slice(0, 80)) {
    const t = l.replace(/^\s*\/\/\s?/, '').trim();
    const m = t.match(/^(功能|激励与检查|预期结果)：(.*)$/);
    if (m) { cur = m[1]; out[cur] = m[2]; continue; }
    if (cur && /^\S/.test(t) && !/^(module|timescale)/.test(t)) out[cur] += ' ' + t;
    if (/^\s*module\s/.test(l)) break;
  }
  return out;
}
// 截断要停在标点或空格上，不留半个词（"行滞后与列平"那种尾巴就是硬切出来的）
const cell = (s, n) => {
  const t = (s || '').replace(/\|/g, '/').replace(/\s+/g, ' ').trim();
  if (t.length <= n) return t;
  const head = t.slice(0, n);
  const at = Math.max(head.lastIndexOf('、'), head.lastIndexOf('；'), head.lastIndexOf(';'), head.lastIndexOf(','), head.lastIndexOf(' '));
  return (at > 12 ? head.slice(0, at) : head).trim().replace(/[、，,；;（(]$/, '') + '…';
};
const rows = [];
let bad = 0;
for (const f of files) {
  const txt = fs.readFileSync(path.join(ROOT, f), 'utf8');
  const s = sections(txt);
  if (!s['功能'] || !s['激励与检查'] || !s['预期结果']) { bad++; console.log(`${f} 缺段=${['功能', '激励与检查', '预期结果'].filter((k) => !s[k]).join(',')} FAIL`); continue; }
  const dut = (s['功能'].match(/被测模块\s*`([^`]+)`/) || [])[1] || cell(s['功能'].split('；')[0], 28);
  const cover = (s['功能'].match(/覆盖点[：:]\s*(.+)$/) || [])[1] || s['功能'];
  const pass = (s['预期结果'].match(/通过时(.+?)；失败时/) || s['预期结果'].match(/通过时(.+)$/) || [])[1] || s['预期结果'];
  const fail = (s['预期结果'].match(/失败时(.+)$/) || [])[1] || '';
  rows.push(`| \`${path.basename(f)}\` | ${cell(dut, 40)} | ${cell(cover, 64)} | ${cell(pass, 44)}${fail ? '；失败时 ' + cell(fail, 40) : ''} |`);
}
const header = [
  '| 文件名 | 被测模块 | 功能 | 预期结果 |',
  '| --- | --- | --- | --- |',
];
const cmd = [
  '',
  '```tcl',
  'bash build/sim/run_one.sh tb_crc32        # 单支台架：xvlog → xelab → xsim，判定词在末行',
  '```',
];
const body = header.concat(rows).concat(cmd).join('\n') + '\n';
const cur = fs.existsSync(path.join(ROOT, 'sim/README.md')) ? fs.readFileSync(path.join(ROOT, 'sim/README.md'), 'utf8') : '';
const listed = [...cur.matchAll(/`?([a-z0-9_\-]+\.v)`?/g)].map((x) => x[1]);
const notListed = files.map((f) => path.basename(f)).filter((v) => !listed.includes(v));
const allV = (run('git ls-files sim') || '').split('\n').filter((f) => f.endsWith('.v')).map((f) => path.basename(f));
const phantom = [...new Set(listed)].filter((v) => !allV.includes(v));
console.log(`GEN-SIM-README 台架=${files.length} 生成行=${rows.length} 现状未列=${notListed.length} 幻影=${phantom.length}${phantom.length ? ' ' + phantom.slice(0, 5).join(',') : ''}`);
if (APPLY) {
  fs.writeFileSync(path.join(ROOT, 'sim/README.md'), body);
  const back = fs.readFileSync(path.join(ROOT, 'sim/README.md'), 'utf8');
  if (back !== body) { console.log(`写完读回与生成的正文不一致 FAIL`); process.exit(1); }
  const rl = [...back.matchAll(/\| \`([a-z0-9_\-]+\.v)\`/g)].map((x) => x[1]);
  const stillMissing = files.map((f) => path.basename(f)).filter((v) => !rl.includes(v));
  if (rl.length !== files.length || stillMissing.length) { console.log(`表格行=${rl.length} 台架=${files.length} 未列=${stillMissing.length} FAIL`); process.exit(1); }
  console.log(`WROTE sim/README.md 行=${back.split(/\r?\n/).length} 表格行=${rl.length} 未列=0 PASS`);
} else {
  console.log(`CHECK 未写；现文件行=${cur.split(/\r?\n/).length} 将写行=${body.split(/?
/).length} ${bad ? 'FAIL' : 'PASS'}`);
}
process.exit(bad ? 1 : 0);
