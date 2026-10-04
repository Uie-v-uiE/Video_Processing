// 用途：把交付 §1.2 要求的源码归档位置改到位——src/ps/** 迁到 src/host/ps/**，并把
//      全仓（git 跟踪文件）里指向旧目录的**路径字面量**同步改口；含固件构建入口
//      （build/ps_app.mjs、build/build_ps_app.py）与各把尺子里硬编码的 `src/ps/main.c`。
// 输入输出：读 git ls-files 射程与文件正文；--check 只打印，--apply 写盘；stdout 一行计数 + 判定词。
// 退出码：0=PASS，1=REFUSE/FAIL（不变量不成立或射程为空），2=参数或 git 不可用。
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const ROOT = process.cwd();
const APPLY = process.argv.includes('--apply');
const SELF = process.argv.includes('--self');

// 旧名/新名：只认"src/ps"作为一个目录段，后面不能再跟名字字符（防 src/ps_extra）
const OLD_RE = /(?<![A-Za-z0-9_.\-])src\/ps(?![A-Za-z0-9_\-])/g;
const NEW = 'src/host/ps';
const NEW_RE = /(?<![A-Za-z0-9_.\-])src\/host\/ps(?![A-Za-z0-9_\-])/g;
const count = (s, re) => (s.match(re) || []).length;
const occurrences = (s) => count(s, OLD_RE);

// 冻结射程：过去时的记录不改（改了等于篡改证据链）。名单写在尺子里并打印命中数（rule 44）。
const FROZEN = [
  'report/log', 'build/evidence', 'build/frozen_', 'build/report', 'build/runs',
  'board/compare', 'board/logs', 'board/captures', 'data/golden', '.git',
];
const isFrozen = (f) => FROZEN.some(p => f === p || f.startsWith(p + '/') || f.startsWith(p));
// 尺子自己点名旧名（用例字符串就在正文里），必须自斥；否则第二次跑会把用例改掉。
const SELF_FILE = 'build/r122_ps_relocate.mjs';

function trackedFiles() {
  try {
    return execFileSync('git', ['ls-files'], { cwd: ROOT, encoding: 'utf8', maxBuffer: 64 << 20 })
      .split(/\r?\n/).filter(Boolean);
  } catch (e) { return null; }
}

function rotateText(raw) {
  const oldIn = occurrences(raw), newIn = count(raw, NEW_RE);
  const out = oldIn ? raw.replace(OLD_RE, NEW) : raw;
  return { out, oldIn, oldOut: occurrences(out), newIn, newOut: count(out, NEW_RE) };
}

// 不变量：旧名清零、新名净增数=旧名原数、行数与 CR 数不动。逐文件判，
// 一条不成立就整批 REFUSE（改口脚本历史上把 README 截断过，见 ISSUES 里的改口陷阱条目）。
function checkFile(f) {
  const raw = fs.readFileSync(path.join(ROOT, f), 'utf8');
  const r = rotateText(raw);
  const bad = [];
  if (r.oldOut !== 0) bad.push(`残留旧名 ${r.oldOut} 处`);
  if (r.newOut !== r.newIn + r.oldIn) bad.push(`旧名 ${r.oldIn}→新名净增 ${r.newOut - r.newIn} 不等`);
  if (r.out.split(/\r?\n/).length !== raw.split(/\r?\n/).length) bad.push('行数变了');
  if (count(r.out, /\r/g) !== count(raw, /\r/g)) bad.push('CR 数变了');
  return { r, bad };
}

if (SELF) {
  const cases = [
    ['固件在 `src/ps/main.c` 里', 1, '文档行内码里的路径 ⇒ 改'],
    ["main:   'src/ps/main.c',", 1, '尺子里硬编码的输入路径 ⇒ 改'],
    ['git ls-files src/rtl src/ps', 1, '命令参数 ⇒ 改'],
    ['# 改了什么（src/ps/sd_play.c）', 1, '中文括号里的裸路径 ⇒ 改'],
    ['src/ps_extra/x.v', 0, '同前缀的别的目录 ⇒ 不许改'],
    ['src/host/ps/main.c', 0, '已经是新名 ⇒ 不再命中（幂等）'],
    ['D:/X/VP/src/ps/main.c', 1, '绝对路径尾部 ⇒ 也改（前面是 / 不挡）'],
    ['src/ps 与 src/ps/main.c 两处', 2, '一处裸目录名 + 一处带斜杠 ⇒ 都改'],
  ];
  let r = 0;
  for (const [s, want, why] of cases) {
    const g = rotateText(s);
    const ok = g.oldIn === want && g.oldOut === 0 && g.newOut === g.newIn + want && (want ? g.out !== s : g.out === s);
    if (!ok) r++;
    console.log(`SELF ${ok ? 'PASS' : 'FAIL'} ${why}（旧名 ${g.oldIn}→${g.oldOut}，新名 ${g.newIn}→${g.newOut}）`);
  }
  // 幂等：改口两次的结果与改一次相同
  const once = rotateText('路径 src/ps 与 src/ps/main.c').out;
  const twice = rotateText(once).out;
  const idem = once === twice;
  if (!idem) r++;
  console.log(`SELF ${idem ? 'PASS' : 'FAIL'} 幂等（二次改口不再命中）`);
  // 反例：把新名当成旧名再"改"一次会破坏等式（证明这把尺子拦得住重复改口）
  const dbl = rotateText(once);
  const guard = dbl.oldIn === 0 && dbl.newOut === dbl.newIn;
  if (!guard) r++;
  console.log(`SELF ${guard ? 'PASS' : 'FAIL'} 重复改口不破等式（新名 ${dbl.newIn}→${dbl.newOut}）`);
  console.log(`PS-RELOC-SELF 判 ${cases.length + 2} 项 红=${r} ${r ? 'FAIL' : 'PASS'}`);
  process.exit(r ? 1 : 0);
}

const files = trackedFiles();
if (!files) { console.log('PS-RELOC git ls-files 不可用 NOT_MEASURED'); process.exit(2); }
if (!files.length) { console.log('PS-RELOC 射程读到 0 个跟踪文件 NOT_MEASURED'); process.exit(1); }

const hits = [], frozen = [];
let total = 0, refuse = 0;
for (const f of files) {
  let raw = '';
  try { raw = fs.readFileSync(path.join(ROOT, f), 'utf8'); } catch (e) { continue; }
  const oldIn = occurrences(raw);
  if (!oldIn) continue;
  if (f === SELF_FILE) { console.log(`(自斥 ${f}：${oldIn} 处旧名是用例本身，不改)`); continue; }
  if (isFrozen(f)) { frozen.push(`${f}:${oldIn}`); continue; }
  const { r, bad } = checkFile(f);
  if (bad.length) { refuse++; console.log(`REFUSE ${f} ${bad.join('；')}`); continue; }
  hits.push([f, r.oldIn]); total += r.oldIn;
}
if (!hits.length) {
  // 射程里没有旧名 = 改口已完成（幂等复跑走这一支）；有拒写则仍是 FAIL，不圆场。
  const done = !refuse && fs.existsSync(path.join(ROOT, 'src/host/ps'));
  console.log(`PS-RELOC 射程=${files.length} 待改文件=0 旧名总数=0 冻结件不计=${frozen.length} 拒写=${refuse} src/host/ps=${done ? '已就位' : '未见'} ${done ? 'PASS' : 'FAIL'}`);
  process.exit(done ? 0 : 1);
}
if (refuse) {
  console.log(`PS-RELOC 射程=${files.length} 待改=${hits.length} 旧名总数=${total} 冻结件不计=${frozen.length} 拒写=${refuse} FAIL`);
  process.exit(1);
}

if (APPLY) {
  for (const [f] of hits) {
    const raw = fs.readFileSync(path.join(ROOT, f), 'utf8');
    fs.writeFileSync(path.join(ROOT, f), rotateText(raw).out, 'utf8');
  }
}
const moved = fs.existsSync(path.join(ROOT, 'src/host/ps')) ? '已就位' : '未迁';
console.log(`PS-RELOC ${APPLY ? 'WROTE' : 'CHECK'} 射程=${files.length} 待改文件=${hits.length} 旧名总数=${total} 冻结件不计=${frozen.length}[${frozen.slice(0, 3).join(',')}] 拒写=0 src/host/ps=${moved} PASS`);
