// 用途：PS 裸机固件的归档位置改口——src/host/ps/** 迁到 src/ps/**（与 src/rtl、src/constraints 同级），
//      并把全仓（git 跟踪文件 + 盘上的 docs/walkthrough 学习文档）里指向旧目录的**路径字面量**同步改口；
//      含固件构建入口（build/ps_app.mjs、build/build_ps_app.py）与各把尺子里硬编码的 `src/ps/main.c`。
// 方向说明：本工具原本是**反方向**写的（r122 那一轮 src/ps → src/host/ps，已 --apply 过、提交 8e952cc），
//      本轮按用户口径把 OLD/NEW 互换复用；下面的 SELF 用例、判定列与 FROZEN 名单都跟着这一方向。
// 输入输出：读 git ls-files 射程与文件正文；--check 只打印，--apply 写盘；stdout 一行计数 + 判定词。
// 退出码：0=PASS，1=REFUSE/FAIL（不变量不成立或射程为空），2=参数或 git 不可用。
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const ROOT = process.cwd();
const APPLY = process.argv.includes('--apply');
const SELF = process.argv.includes('--self');

// 旧名/新名：只认"src/host/ps"作为一个目录段，后面不能再跟名字字符。
// 这条边界是**射程的关键**，不是装饰：`src/host/ps_hb_check.mjs`、`src/host/ps_app.mjs` 是 PC 侧工具，
// 它们的文件名恰好以 `ps` 开头 ⇒ 少了 `(?![A-Za-z0-9_\-])` 就会把工具路径改成 `src/ps_hb_check.mjs`。
const OLD_RE = /(?<![A-Za-z0-9_.\-])src\/host\/ps(?![A-Za-z0-9_\-])/g;
const NEW = 'src/ps';
const NEW_RE = /(?<![A-Za-z0-9_.\-])src\/ps(?![A-Za-z0-9_\-])/g;
const count = (s, re) => (s.match(re) || []).length;
const occurrences = (s) => count(s, OLD_RE);

// 冻结射程：过去时的记录不改（改了等于篡改证据链）。名单写在尺子里并打印命中数（rule 44）。
const FROZEN = [
  'report/log', 'build/evidence', 'build/frozen_', 'build/report', 'build/runs',
  'board/compare', 'board/logs', 'board/captures', 'data/golden', '.git',
  // 本轮加的两类（用户口径：证据件正文一个字都不改）：
  //  board/firmware/ 是三份二进制成品的**来源卡**，正文里抄的是当时那条 `git diff --stat` 的原始输出。
  'board/firmware',
];
// 凡 `.txt` / `.rpt` 都是凭据原件（工具产出或抓包原文），不论落在哪个目录都不改写正文。
const EVIDENCE_EXT = /\.(txt|rpt|log|md5)$/i;
const isFrozen = (f) => FROZEN.some(p => f === p || f.startsWith(p + '/') || f.startsWith(p))
  || EVIDENCE_EXT.test(f);
// 尺子自己点名旧名（用例字符串就在正文里），必须自斥；否则第二次跑会把用例改掉。
const SELF_FILE = 'build/r122_ps_relocate.mjs';

// 口径声明件（与 SELF_FILE 同一族，理由不同一条）：这几个文件的**职责就是把旧名说出来**——
//   build/deliver_spec_check.mjs 的 C1-2 靠"固件放回 src/host/ps ⇒ 判红"这条对照证明它不是恒绿，
//     改口器把那句话里的旧名也洗掉，判据就变成一句自相矛盾的注释（红对照的定义消失了）；
//   build/make_submission.sh 与 src/host/README.md 记的是"这一条为什么从 host/ps 改成 ps"。
// 复跑本工具时必须跳过它们，且**命中数要念出来**（藏在脚本里不打印 = 有人能悄悄扩大豁免面）。
const NAME_HOLDERS = [
  'build/deliver_spec_check.mjs',
  'build/make_submission.sh',
  'src/host/README.md',
];

function trackedFiles() {
  try {
    return execFileSync('git', ['ls-files'], { cwd: ROOT, encoding: 'utf8', maxBuffer: 64 << 20 })
      .split(/\r?\n/).filter(Boolean);
  } catch (e) { return null; }
}

// docs/walkthrough 是**盘上的学习文档、按 .gitignore 不入库**，但它和交付文档一样是活指路：
// 搬完目录不搬它，读者就照着一条不存在的路走。所以射程在 git 跟踪集之外并上这一层（只这一层；
// report/study/ 那几份本地笔记本轮用户明确不动，宁可留旧指路也不越界改它）。
const EXTRA_SCOPE = ['docs/walkthrough'];
function onDisk(prefix) {
  const out = [];
  const walk = (rel) => {
    const abs = path.join(ROOT, rel);
    let ents = [];
    try { ents = fs.readdirSync(abs, { withFileTypes: true }); } catch (e) { return; }
    for (const ent of ents) {
      const r = `${rel}/${ent.name}`;
      if (ent.isDirectory()) walk(r); else if (ent.isFile()) out.push(r);
    }
  };
  walk(prefix);
  return out;
}

function scope() {
  const files = trackedFiles();
  if (files === null) return null;
  const extra = [];
  for (const d of EXTRA_SCOPE) for (const f of onDisk(d)) if (!files.includes(f)) extra.push(f);
  return { files: files.concat(extra), tracked: files.length, extra: extra.length };
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
    ['固件在 `src/host/ps/main.c` 里', 1, '文档行内码里的路径 ⇒ 改'],
    ["main:   'src/host/ps/main.c',", 1, '尺子里硬编码的输入路径 ⇒ 改'],
    ['git ls-files src/rtl src/host/ps', 1, '命令参数 ⇒ 改'],
    ['# 改了什么（src/host/ps/sd_play.c）', 1, '中文括号里的裸路径 ⇒ 改'],
    ['src/host/ps_extra/x.c', 0, '同前缀的别的目录 ⇒ 不许改'],
    ['src/ps/main.c', 0, '已经是新名 ⇒ 不再命中（幂等）'],
    ['D:/X/VP/src/host/ps/main.c', 1, '绝对路径尾部 ⇒ 也改（前面是 / 不挡）'],
    ['src/host/ps 与 src/host/ps/main.c 两处', 2, '一处裸目录名 + 一处带斜杠 ⇒ 都改'],
    // 本轮新增的两条边界：PC 侧工具的名字恰好以 `ps` 开头，它们**留在 src/host**，一条都不许碰。
    ['node src/host/ps_hb_check.mjs --self', 0, 'PC 侧尺子 ps_hb_check ⇒ 名字里的 ps_ 被边界挡下，不许改'],
    ['bash build/board_verify.sh && node src/host/ps_app_helper.mjs', 0, '同理：ps_ 前缀的工具名不许改'],
    ['src/host/README.md 讲上位机', 0, '上位机工具的 README ⇒ 不动'],
    ['^src/(rtl|host/ps|constraints)/', 0, 'KEEP 正则里的 host/ps 不是 src/host/ps 字面量 ⇒ 本工具改不动它，由人工改'],
  ];
  let r = 0;
  for (const [s, want, why] of cases) {
    const g = rotateText(s);
    const ok = g.oldIn === want && g.oldOut === 0 && g.newOut === g.newIn + want && (want ? g.out !== s : g.out === s);
    if (!ok) r++;
    console.log(`SELF ${ok ? 'PASS' : 'FAIL'} ${why}（旧名 ${g.oldIn}→${g.oldOut}，新名 ${g.newIn}→${g.newOut}）`);
  }
  // 幂等：改口两次的结果与改一次相同
  const once = rotateText('路径 src/host/ps 与 src/host/ps/main.c').out;
  const twice = rotateText(once).out;
  const idem = once === twice && once === '路径 src/ps 与 src/ps/main.c';
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

const scopeInfo = scope();
if (!scopeInfo) { console.log('PS-RELOC git ls-files 不可用 NOT_MEASURED'); process.exit(2); }
const files = scopeInfo.files;
if (!files.length) { console.log('PS-RELOC 射程读到 0 个文件 NOT_MEASURED'); process.exit(1); }

const hits = [], frozen = [], holders = [];
let total = 0, refuse = 0, holderN = 0;
for (const f of files) {
  let raw = '';
  try { raw = fs.readFileSync(path.join(ROOT, f), 'utf8'); } catch (e) { continue; }
  const oldIn = occurrences(raw);
  if (!oldIn) continue;
  if (f === SELF_FILE) { console.log(`(自斥 ${f}：${oldIn} 处旧名是用例本身，不改)`); continue; }
  if (isFrozen(f)) { frozen.push(`${f}:${oldIn}`); continue; }
  if (NAME_HOLDERS.includes(f)) { holders.push(`${f}:${oldIn}`); holderN += oldIn; continue; }
  const { r, bad } = checkFile(f);
  if (bad.length) { refuse++; console.log(`REFUSE ${f} ${bad.join('；')}`); continue; }
  hits.push([f, r.oldIn]); total += r.oldIn;
}
if (holders.length) console.log(`(口径声明件不洗名 ${holders.length} 份 / ${holderN} 处：${holders.join(' ')} —— 它们点旧名是职责，改口器复跑会把判据的对照定义抹掉)`);
// 判定列：ISSUES #363 的教训是"这把尺子的射程只到改引用，它不会替我做 git mv"，
// 所以**目录状态必须自己念出来**，而且要两头都念：新目录在位 + 旧目录已消失。
// 只看一头会放行两种坏树：只搬目录不改引用（旧指路满仓），或只改引用不搬目录（指路指向不存在的目录）。
function dirState() {
  const nw = fs.existsSync(path.join(ROOT, 'src/ps'));
  const old = fs.existsSync(path.join(ROOT, 'src/host/ps'));
  const oldLeft = old ? fs.readdirSync(path.join(ROOT, 'src/host/ps')).length : 0;
  return { nw, old, oldLeft, label: `src/ps=${nw ? '已就位' : '缺失'} src/host/ps=${old ? `未清(剩${oldLeft}件)` : '已消失'}` };
}

if (!hits.length) {
  // 射程里没有旧名 = 改口已完成（幂等复跑走这一支）；有拒写则仍是 FAIL，不圆场。
  const st = dirState();
  const done = !refuse && st.nw && !st.old;
  console.log(`PS-RELOC 射程=${files.length}(跟踪=${scopeInfo.tracked}+盘上学习文档=${scopeInfo.extra}) 待改文件=0 旧名总数=0 冻结件不计=${frozen.length} 口径声明件不计=${holders.length}/${holderN} 拒写=${refuse} ${st.label} ${done ? 'PASS' : 'FAIL'}`);
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
// 旧写法在这里**无论目录有没有搬都打 PASS**（`src/host/ps=已就位/未迁` 只是念一下），
// 于是 #363 那种"引用改完、树是断的"会被当成绿灯放行。现在判定跟着目录走。
const st = dirState();
const ok = st.nw && !st.old;
console.log(`PS-RELOC ${APPLY ? 'WROTE' : 'CHECK'} 射程=${files.length}(跟踪=${scopeInfo.tracked}+盘上学习文档=${scopeInfo.extra}) 待改文件=${hits.length} 旧名总数=${total} 冻结件不计=${frozen.length}[${frozen.join(',')}] 口径声明件不计=${holders.length}/${holderN} 拒写=0 ${st.label} ${ok ? 'PASS' : 'FAIL'}`);
if (!ok) console.log('  ↑ FAIL 的理由：引用改口与目录搬迁是两件事，缺一样这棵树就是断的（ISSUES #363）。');
process.exit(ok ? 0 : 1);
