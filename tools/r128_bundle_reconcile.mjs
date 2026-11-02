// 一次性对账：交付树 HEAD 的非厂商文件 vs bundle 工程半棵
// 判据：逐件比较"去掉 \r 之后的内容摘要"，打印 判/缺/内容不同 三个数与多余件数
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const REPO = 'D:/Xilinx/Prj/pro/delivery_review_20261005';
const BUNDLE = 'D:/Xilinx/Prj/Video_Processing';
const TREE = 'D:/Xilinx/Prj/pro/tmp_main_tree';

const list = execFileSync('git', ['-C', REPO, 'ls-tree', '-r', 'HEAD', '--name-only'], { encoding: 'utf8' })
  .split('\n').filter(Boolean)
  .filter((f) => !/^vivado_system\//.test(f) && !/^vitis\//.test(f));

// 一次性导出到临时树（1124 次 `git show` 太慢；`git archive | tar` 一次完成）
fs.rmSync(TREE, { recursive: true, force: true });
fs.mkdirSync(TREE, { recursive: true });
execFileSync('bash', ['-lc', `cd "${REPO}" && git archive HEAD -- . ':(exclude)vivado_system' ':(exclude)vitis' | tar -x -C "${TREE}"`]);

const md5 = (buf) => crypto.createHash('md5').update(buf.toString('utf8').replace(/\r/g, '')).digest('hex');

let judged = 0, missing = 0, differ = 0;
const missList = [], diffList = [];
for (const f of list) {
  const t = path.join(TREE, f), b = path.join(BUNDLE, f);
  if (!fs.existsSync(t)) { console.log(`REFUSE 导出树里没有 ${f}`); process.exit(2); }
  if (!fs.existsSync(b)) { missing++; missList.push(f); continue; }
  judged++;
  if (md5(fs.readFileSync(t)) !== md5(fs.readFileSync(b))) { differ++; diffList.push(f); }
}

const HALF = ['src', 'sim', 'build', 'report', 'board', 'data', 'skills', '.gitignore', '.gitattributes', 'LICENSE', 'README.md', 'README_EN.md', 'run_test.bat', 'run_test.sh', 'send_demo.bat'];
const walk = (d, acc) => { for (const e of fs.readdirSync(d, { withFileTypes: true })) { const p = path.join(d, e.name); if (e.isDirectory()) walk(p, acc); else acc.push(path.relative(BUNDLE, p).replace(/\\/g, '/')); } return acc; };
const onDisk = [];
for (const h of HALF) { const p = path.join(BUNDLE, h); if (!fs.existsSync(p)) { console.log(`REFUSE 顶层条目不在盘上: ${h}`); process.exit(2); } if (fs.statSync(p).isDirectory()) walk(p, onDisk); else onDisk.push(h); }
const inMain = new Set(list);
const extra = onDisk.filter((f) => !inMain.has(f));

console.log(`对账 判=${judged} 缺=${missing} 内容不同=${differ} 多余(bundle 有而 main 无)=${extra.length} bundle盘上半棵=${onDisk.length} main非厂商=${list.length}`);
if (missing) console.log('缺(前10): ' + missList.slice(0, 10).join(' | '));
if (differ) console.log('不同(前10): ' + diffList.slice(0, 10).join(' | '));
const agg = new Map();
for (const f of extra) { const k = f.split('/').slice(0, 2).join('/'); agg.set(k, (agg.get(k) || 0) + 1); }
console.log('多余件归类: ' + [...agg.entries()].sort((a, b) => b[1] - a[1]).slice(0, 12).map(([k, v]) => `${k}=${v}`).join(' | '));
