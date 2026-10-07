#!/usr/bin/env node
// build/checks/check_repo_consistency.mjs —— 提交前终审的机器门禁（P21 的 C1–C12）
//
// 设计约束：
//  · 只读，不改任何文件；判定 token 放每行最后一个字段；每条打印分母；缺输入一律 NOT_MEASURED（绝不判通过）。
//  · 能复用就别重造：C6 调 `skills/_meta/build-index.mjs skills --check`、C12 调 `skills/_meta/run-all-checks.mjs skills`（现役件；旧包 gates.mjs/gen_index.mjs 已随 2026-10-04 c7b325f 重建删除），C5 调用 P20 的卫生机检。
//  · 每条红项都要能指出"缺什么"，不许只说"不通过"。
// 退出码：0=无红 1=有红 2=有未测且无红 3=前置不满足
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const ROOT = process.cwd();
const SELF = process.argv.includes('--self');   // --self 只跑 C2 的对照例，不做全仓扫描（免得自检本身要读 3000+ 份文件）
const LIST = process.argv.includes('--list');    // --list 把 C3 的死引用明细打全（判定不变）
// C5 调用的卫生机检是一次全仓扫描，耗时随仓库大小走。上限用"本轮实测 × 3"而不是拍一个 60 s，
// 否则这一项永远是 NOT_MEASURED（那是把"我没等够"说成"测不了"）。实测值更新在本行注释里：
// 2026-10-04 r120：C1 改成一次 awk 之前，400 条路径就要 266 s（全仓外推 ≈ 39 min）；改后待重测。
const HYGIENE_TMO = Number(process.env.VP_HYGIENE_TMO_MS || 300000);
const P = (...a) => path.join(ROOT, ...a);
const J = [];
let judged = 0;
function row(id, label, detail, verdict) { judged++; const line = `${id} ${label} 判 ${judged} 项 ${detail.split(String.fromCharCode(92)).join('/')} ${verdict}`; J.push(line); console.log(line); }   // 逐条即打：中途卡住时还能看出卡在哪一项（第一版只在结尾打印，卡住＝零输出）；显示层把反斜杠换成正斜杠，判定不变
function read(f) { try { return fs.readFileSync(path.isAbsolute(f) ? f : P(f), 'utf8'); } catch { return null; } }
function exists(f) { try { fs.accessSync(P(f)); return true; } catch { return false; } }
function sh(cmd, args, tmo = 90000) {
  try { return { ok: true, out: execFileSync(cmd, args, { cwd: ROOT, encoding: 'utf8', maxBuffer: 64e6, timeout: tmo, killSignal: 'SIGKILL' }) }; }
  catch (e) { return { ok: false, timedOut: /ETIMEDOUT|SIGKILL/.test(String(e.code) + String(e.signal) + String(e.message)), out: (e.stdout || '') + (e.stderr || '') }; }
}

const MD_SCOPE = ['README.md', 'docs', 'report', 'submit', 'board', 'skill'];
// 交付宇宙 = 未被 .gitignore 排除的文件。学习文档（report/study/ 等）按用户指令本就不入库，
// 让它们参与"路径必须存活"的判据会把尺子的射程指向一个根本不随包的对象集（改前 C3 的 66 条里 55 条是这一类）。
let IGNORED = new Set();
try {
  // `-z` 与 core.quotePath=false 是必需的：学习文档目录名是中文，默认输出会被 git 八进制转义，
  // 那样 Set 永远查不中，被排除的对象集照样参与判据（第一版就栽在这里）。
  IGNORED = new Set(execFileSync('git', ['-c', 'core.quotePath=false', 'ls-files', '--others', '--ignored',
    '--exclude-standard', '-z'], { cwd: ROOT, encoding: 'utf8', maxBuffer: 64e6 }).split('\u0000').filter(Boolean));
} catch { IGNORED = new Set(); }
function mdFiles() {
  const out = [];
  const walk = (rel) => {
    const abs = P(rel);
    if (!fs.existsSync(abs)) return;
    const st = fs.statSync(abs);
    if (st.isFile()) { const fwd = rel.split(path.sep).join('/'); if (rel.endsWith('.md') && !IGNORED.has(fwd)) out.push(fwd); return; }
    for (const e of fs.readdirSync(abs)) { if (e === 'node_modules' || e.startsWith('.')) continue; walk(path.join(rel, e)); }
  };
  MD_SCOPE.forEach(walk);
  return out.map(f => f.split(path.sep).join('/'));   // 判定不变，只将路径统一成正斜杠，好与 git 的视图对齐
}

// C1 单一事实源：器件/版本只允许一处权威。
// 判据是"**别处出现了与权威不同的值**"才算红；同值的抄写只登记条数（改抄写为引用要动整批文档，是另一轮的事）。
// 改前这条把"任何别处提到 2025.2.1"都判红，等于禁止文档引用版本号——那是量错维度，也必然与 §3.3.3.1 冲突。
const decl = read('report/declarations.md');
const part = read('report/build.md');
if (!SELF) {
  if (decl === null) row('C1', '声明唯一权威源', '缺 report/declarations.md（P20 产出）', 'NOT_MEASURED');
  else {
    const blk = decl.split('<!-- BEGIN-AUTHORITATIVE -->')[1]?.split('<!-- END-AUTHORITATIVE -->')[0] || '';
    const auth = k => (blk.match(new RegExp('^' + k + ':[ \\t]*(.+)$', 'm')) || [])[1]?.trim() || '';
    const keys = ['part', 'vivado', 'vivado_build', 'os', 'node', 'board'];
    const missing = keys.filter(k => !auth(k));
    if (missing.length) row('C1', '声明唯一权威源', `权威块缺字段=${missing.join(',')}（缺字段则整条不可判）`, 'NOT_MEASURED');
    else {
      const want = auth('part').toUpperCase().replace(/[-_]/g, '');
      const devRe = /[Xx][Cc]7[Zz][0-9]{2}[A-Za-z]{2,3}[0-9]{2,3}[A-Za-z]*-?[0-9][A-Za-z]?/g;
      const verRe = /(?:Vivado|Vitis)[^\n]{0,8}(?:v\.|版本)?[ ]?20[0-9]{2}\.[0-9]+(?:\.[0-9]+)?/g;
      let same = 0, conflict = [], verSame = 0, verBad = [], quoted = 0;
      for (const f of mdFiles()) {
        if (f === 'report/declarations.md') continue;
        const t = read(f) || '';
        // 引文豁免：`skills/evals/records/` 存的是"陌生人演练/第三方审计的原话"，里面出现"2024.2（不是本包的 2025.2.1）"
        // 这类对照句是**被审对象说的话**，不是本仓库另立权威。豁免只开这一个目录，且把豁免条数打出来（静默跳过=没有尺子）。
        const isQuote = /^skill\/evals\/records\//.test(f);
        for (const m of t.matchAll(devRe)) {
          const n = m[0].toUpperCase().replace(/[-_]/g, '');
          if (n === want) same++; else if (isQuote) quoted++; else conflict.push(`${f}:${m[0]}`);
        }
        for (const m of t.matchAll(verRe)) {
          const num = (m[0].match(/20[0-9]{2}\.[0-9]+(?:\.[0-9]+)?/) || [])[0];
          if (num === auth('vivado')) verSame++; else if (isQuote) quoted++; else verBad.push(`${f}:${m[0]}`);
        }
      }
      const badN = conflict.length + verBad.length;
      const made = same + verSame + badN;
      row('C1', '声明唯一权威源',
          `权威=${keys.join('/')} 比过=${made} 同值抄写=${same}+${verSame} 器件冲突=${conflict.length}${conflict.length ? ' 例:' + conflict.slice(0, 2).join(',') : ''} 版本冲突=${verBad.length}${verBad.length ? ' 例:' + verBad.slice(0, 2).join(',') : ''} 引文豁免=${quoted}`,
          made === 0 ? 'NOT_MEASURED' : (badN === 0 ? 'PASS' : 'FAIL'));
    }
  }
}
// C2 的取路径逻辑单独成函数，好让 --self 能喂假象（改前正则会把 `）`、反引号吞进路径名，
// 把"指得到"的行判成红——那是尺子的维度错，不是被量对象的错）
const C2_RE = /((?:build|docs|report|board|data|src|sim|scripts)\/[^\s,;`)\]（）、。，；：]+|README\.md)/g;
function c2Judge(rows, has) {
  let ok = 0; const miss = [];
  for (const l of rows) {
    const c = (l.match(C2_RE) || []).map(x => x.replace(/[.,;:]+$/, ''));
    if (c.length) (c.every(x => has(x)) ? ok++ : miss.push(l.split(',')[0]));
    else miss.push('(无路径)' + l.split(',')[0]);
  }
  return { ok, miss };
}
// 2026-10-05 的射程洞（本轮实测到的，不是推测），两条同族：
//  ① 字符类里**没有 `/**` ⇒ `build/evidence/r116_board/board_now.txt` 这种三层路径永远匹配不上：
//     正则吃掉 `build/evidence` 后要求下一字符是分隔符，而它是 `/` ⇒ 整个 token 不成立，
//     **静默不进分母**（当时打印 `检查路径引用=631 死引用=0 PASS`，看着全绿；把 `/` 放进类里
//     同一棵树现算抓到 1179 条）。
//  ② 右边界那条 `(?=[\s)|,，。；;：:]|$)` 把**反引号或全角括号包起来的写法**整体否掉：
//     中文文档里最常见的指路形状正是 `build/x.md`（两头反引号），这一类从前一条都不判。
// 改法：字符类带 `/`，去掉右边界前瞻——字符类自己就定义了"什么算路径字符"，遇到反引号、
// 全角标点、空白自然收口；左边界改为"前面不是路径字符也不是 `/`"（避免咬进 URL 与更长串）。
// 截断上限一并去掉：一个 200 字符的上限会制造新的静默（超限的 token 匹配不上＝不算分母），
// 而那正是这条判据要消灭的东西。
const C3_RE = /(?:^|[^A-Za-z0-9_.\-\[\/])((?:build|docs|report|submit|board|data|src|sim|scripts|skill)\/[A-Za-z0-9_.\-\[\]*\/]+)/g;
// 两条射程修正（都是尺子自己的维度错，不是被量对象变好了）：
//  ① 只判"像一个文件"的串（带扩展名）或"像一个目录"的串（以 / 结尾）。改前 `board/README`、`src/dst`
//     这类行文碎片被当成路径引用，虚报死引用；
//  ② 运行期产物（*.log / *.dcp / impl_1/ / *.runs/）按仓库规矩本就不入库，要求它在盘上＝用错量纲。
const C3_HASFILE = /\.[A-Za-z][A-Za-z0-9]{1,6}$/;
const C3_RUNTIME = /(\.log|\.dcp|impl_1\/|\.runs\/|runme|vivado_system\/|__pycache__\/)/;
// 过程台账（report/log/）里的引用是"当时那一步看到的文件名"，改名轮之后必然对不上；
// 导出器的死链自检也按 #217 的同一条口径排除这一层，这里保持一致并把豁免数打出来（不是静默跳过）。
// 第三支豁免（2026-10-05）：**同一行自带"这件东西故意不入库/不随包"的声明** ⇒ 只报数不判红。
// 词表不自己另立一份：从 `src/host/doc_currency_check.mjs` 的 `NOSHIP_MARK` 现读；读不到就
// 让 C3 整项 NOT_MEASURED（fail-closed）。两把尺子各写一套话术的后果本轮实测到了：
// 同一批 7 条指路（`board/uart_script_capture.txt` 那族）一边放行一边判红（详见 AUDIT §24）。
let C3_NOSHIP = null;
try {
    const src = fs.readFileSync(new URL('../../src/host/doc_currency_check.mjs', import.meta.url), 'utf8');
    const mm = src.match(/const NOSHIP_MARK = \[([^\]]+)\]/);
    // 逐词按"单引号包起来"取，别按逗号切再剥引号 —— 词里有反引号与空格（`已被 \`.gitignore\` 挡住`），
    // 按逗号切会把带反引号的那一条留成脏串，于是同行声明明明在词表里却永不命中（第一版就栽在这里）。
    if (mm) C3_NOSHIP = [...mm[1].matchAll(/'([^']*)'/g)].map(x => x[1]).filter(Boolean);
} catch { C3_NOSHIP = null; }
const c3Ship = (line) => Array.isArray(C3_NOSHIP) && C3_NOSHIP.some(k => line.includes(k));

// 第五支豁免（2026-10-05，随 C3 射程修正一起加）：**被记录在案的精简笔删掉的凭据**。
// 目录重构那一轮把 `build/` 从 3118 支收到 592 支（笔 `02bd5c4`，另一笔 `58faa85` 删了一条），
// 交付文档里有 81 条指路点的是那一批**当时真在盘上、后来按记录删掉**的读数件。这类不是名字写错，
// 硬要求它在盘上＝用错量纲（与"运行期产物""台账"同一族）。降级为只报数（条数打成 历史精简=N），
// 但降级必须可核：只认下面这份**写死在尺子里**的删除笔名单，名单从 `git show` 现取；
// 不在名单里的缺失照旧红（对照 P2 钉住这一条）。要新增一次精简，就得同时改这份名单——
// 名单在尺子里、尺子随包，改它会和 `--self` 的对照一起被看见，这是反买通。
// 取不到 git ⇒ C3 整项 NOT_MEASURED（fail-closed，不退回"全当存在"）。
const PRUNE_COMMITS = ['02bd5c4', '58faa85'];
let C3_PRUNED = null;
let C3_PRUNED_DIRS = null;
try {
  C3_PRUNED = new Set(PRUNE_COMMITS.flatMap(c => execFileSync('git',
    ['show', '--no-renames', '--diff-filter=D', '--name-only', '--format=', c],
    { cwd: ROOT, encoding: 'utf8', maxBuffer: 64e6, timeout: 60000 }).split(/\r?\n/).filter(Boolean)));
  // 文档也常指**目录**（`build/evidence_r63b/` 这种一整族读数所在的工作目录）。git 里只有文件没有目录，
  // 所以目录形要按前缀判：它的下面曾有文件、且那些文件是被上面那两笔删掉的 ⇒ 同一族历史精简。
  C3_PRUNED_DIRS = new Set();
  for (const p of C3_PRUNED) {
    const segs = p.split('/');
    for (let i = 1; i < segs.length; i++) C3_PRUNED_DIRS.add(segs.slice(0, i).join('/') + '/');
  }
} catch { C3_PRUNED = null; C3_PRUNED_DIRS = null; }
const c3PrunedHit = (c, pruned, prunedDirs) =>
  pruned ? (pruned.has(c) || (c.endsWith('/') && prunedDirs && prunedDirs.has(c))) : false;

function c3Judge(t, relFile, has, pruned, prunedDirs) {
  let total = 0, dead = [], skipFrag = 0, skipRun = 0, skipLedger = 0, skipShip = 0, skipFence = 0, skipQuote = 0, prunedHit = 0;
  const reSrc = new RegExp(C3_RE.source, 'g');
  let inFence = false;
  for (const line of String(t).split(/\r?\n/)) {
    // 围栏里是**工具原文回显**（`RESULT PASS uart_cmd_check (… 捕获 board/uart_script_capture.txt)` 这一类）。
    // 作者不能往别人打印的那一行里塞声明，改抄件＝伪造记录 ⇒ 与 doc_currency 的 D4c 同一口径：
    // 只报数不判红，条数打出来。对照 CTRL M 钉住"同一句写在围栏外照旧必须红"。
    if (/^\s*(?:`{3,}|~{3,})/.test(line)) { inFence = !inFence; continue; }
    // 引用块（`>` 开头）与围栏同族：那是**别人打印/写下的原文**，作者不许往里塞声明词，
    // 也不许为了过尺子改别人的话。这一类同样只报数（条数打成 skipQuote），
    // 对照 Q1/Q2 钉住"同一句写在作者自己名下照旧必须红"。
    if (/^\s*>/.test(line) && !inFence) {
      const re3 = new RegExp(C3_RE.source, 'g'); let mq;
      while ((mq = re3.exec(line))) {
        const c = mq[1].replace(/[.。，;)]+$/, '');
        if (/[*\[\]]/.test(c) || /rNN|<|>|\bdemo\b/.test(c)) continue;
        if (!C3_HASFILE.test(c) && !c.endsWith('/')) continue;
        if (C3_RUNTIME.test(c)) continue;
        if (!has(c) && !c3PrunedHit(c, pruned, prunedDirs)) skipQuote++;
      }
      continue;
    }
    if (inFence) {
      const re2 = new RegExp(C3_RE.source, 'g'); let mm;
      while ((mm = re2.exec(line))) {
        const c = mm[1].replace(/[.。，;)]+$/, '');
        if (/[*\[\]]/.test(c) || /rNN|<|>|\bdemo\b/.test(c)) continue;
        if (!C3_HASFILE.test(c) && !c.endsWith('/')) continue;
        if (C3_RUNTIME.test(c)) continue;
        if (!has(c)) skipFence++;
      }
      continue;
    }
    reSrc.lastIndex = 0; let m2;
    while ((m2 = reSrc.exec(line))) {
      const c = m2[1].replace(/[.。，;)]+$/, '');
      if (/[*\[\]]/.test(c) || /rNN|<|>|\bdemo\b/.test(c)) continue;
      if (!C3_HASFILE.test(c) && !c.endsWith('/')) { skipFrag++; continue; }
      if (C3_RUNTIME.test(c)) { skipRun++; continue; }
      if (/^report\/log\//.test(relFile)) { skipLedger++; continue; }
      if (c3Ship(line)) { skipShip++; continue; }
      total++;
      if (!has(c)) {
        // 名单里那两笔精简删掉的 ⇒ 只报数；其余（从没存在过、或存在过却被别的路径删掉）⇒ 红。
        if (c3PrunedHit(c, pruned, prunedDirs)) prunedHit++;
        else dead.push(`${relFile} → ${c}`);
      }
    }
  }
  return { total, dead, skipFrag, skipRun, skipLedger, skipShip, skipFence, skipQuote, prunedHit };
}
function selftestC2() {
  const has = f => f === 'build/x.rpt';
  const cases = [
    ['A 正常行指得到', ['性能,吞吐,100MB,build/x.rpt'], { ok: 1, miss: 0 }],
    ['B 真缺件必须红', ['性能,吞吐,100MB,build/gone.rpt'], { ok: 0, miss: 1 }],
    ['C 全角括号与反引号不得算进路径（改前正是这里判错）', ['性能,吞吐,100MB,`build/x.rpt`（本轮实测）'], { ok: 1, miss: 0 }],
    ['D 没有路径的行', ['性能,吞吐,100MB,见正文'], { ok: 0, miss: 1 }],
    ['E 行尾点号不算进文件名', ['性能,吞吐,100MB,build/x.rpt.'], { ok: 1, miss: 0 }],
    ['F 全角逗号后面的正文不得吞进路径', ['性能,吞吐,100MB,build/x.rpt，见该目录'], { ok: 1, miss: 0 }]
  ];
  let bad = 0;
  for (const [name, rows, want] of cases) {
    const r = c2Judge(rows, has);
    const got = { ok: r.ok, miss: r.miss.length };
    const pass = got.ok === want.ok && got.miss === want.miss;
    if (!pass) bad++;
    console.log(`CTRL ${name} 期望=${want.ok}/${want.miss} 实读=${got.ok}/${got.miss} ${pass ? '对照成立' : '对照不成立'}`);
  }
  console.log(`C2 自检：造 ${cases.length} 例 不符=${bad} 判 ${cases.length} 项 ${bad === 0 ? 'PASS' : 'FAIL'}`);
  // C3 的对照例：碎片串必须被豁免、真缺的 .md 必须红、运行期件与台账各自只走自己那一支
  const has3 = f => f === 'docs/real.md' || f === 'build/evidence/r118_board/board_now.txt';
  const c3cases = [
    ['G 行文碎片不算路径', '见 board/README 那一节', 'docs/x.md', { total: 0, dead: 0, skipFrag: 1 }],
    ['H 真缺的文件必须红', '对照 docs/gone.md 与 docs/real.md', 'docs/x.md', { total: 2, dead: 1, skipFrag: 0 }],
    ['I 运行期产物走豁免', '日志在 sim/a.log 里', 'docs/x.md', { total: 0, dead: 0, skipRun: 1 }],
    ['J 台账只走台账', '当时读的是 docs/gone.md', 'report/log/issues.md', { total: 0, dead: 0, skipLedger: 1 }],
    // 2026-10-05 新增两支豁免的"能红/能绿"对：少任何一支，这条降级就成了"把句子塞进不随包三个字即可放行"的后门
    ['K 同行声明不随包 ⇒ 只报数', '捕获件 board/uart_script_capture.txt 是本机重写的那一份（不入库）', 'docs/x.md', { total: 0, dead: 0, skipShip: 1 }],
    ['L 同一句没写声明 ⇒ 必须红', '捕获件 board/uart_script_capture.txt 的读数见下', 'docs/x.md', { total: 1, dead: 1, skipShip: 0, skipFence: 0 }],
    ['M 围栏内原文回显只报数（同一句写在围栏外照旧红，见 L 例）',
      ['说明：', String.fromCharCode(96).repeat(3), 'RESULT PASS (捕获 board/uart_script_capture.txt)', String.fromCharCode(96).repeat(3)].join('\n'),
      'docs/x.md', { total: 0, dead: 0, skipFence: 1 }],
    // 2026-10-05 补的三支形状对照：旧正则①字符类里没有 `/`、②右边界前瞻不认反引号，
    // 于是三层路径与 `path` 这种文档里最常见的写法**根本不进分母**，"死引用=0"是看不见不是没有。
    // N1 钉"嵌套的死引用看得见"，N2 是它的正对照（同形状但件在盘上 ⇒ 不许红）——
    // 少了 N2，N1 可以靠"任何嵌套一律红"蒙过；N3/N4 钉住反引号包裹这一形状的红与绿。
    ['N1 三层嵌套的死引用必须看得见', '凭据见 build/evidence/r118_board/gone.txt 那一份', 'docs/x.md', { total: 1, dead: 1 }],
    ['N2 三层嵌套且在盘上 ⇒ 不红（N1 的正对照）', '凭据见 build/evidence/r118_board/board_now.txt', 'docs/x.md', { total: 1, dead: 0 }],
    ['N3 反引号包着的死引用必须看得见', '见 `build/evidence/r118_board/gone.txt` 那一份', 'docs/x.md', { total: 1, dead: 1 }],
    ['N4 反引号包着且在盘上 ⇒ 不红（N3 的正对照）', '见 `build/evidence/r118_board/board_now.txt` 那一份', 'docs/x.md', { total: 1, dead: 0 }],
    // 第五支豁免（历史精简）的能红/能绿对：少了 P2，"指到被删过的件"就成了新的后门——
    // 任何一条乱写的路径只要混进名单就永久免检。
    ['P1 精简名单里的件 ⇒ 只报数不判红', '读数见 build/evidence/r7_pruned/example.rpt', 'docs/x.md', { total: 1, dead: 0, prunedHit: 1 }],
    ['P2 同形状但不在名单里 ⇒ 必须红（P1 的反买通对照）', '读数见 build/evidence/r7_pruned/other.rpt', 'docs/x.md', { total: 1, dead: 1, prunedHit: 0 }],
    // 目录形指路的同一对：`build/evidence_r63b/` 这种工作目录在 git 里没有条目，只有它下面的文件，
    // 所以要按前缀判；P4 钉住"前缀下一条历史文件都没有"仍然必须红（否则任何乱写的目录都免检）。
    ['P3 目录形指路，下面曾有被删文件 ⇒ 按前缀只报数', '整族读数在 build/evidence_r63b/ 里', 'docs/x.md', { total: 1, dead: 0, prunedHit: 1 }],
    ['P4 目录形指路但前缀下空无一物 ⇒ 必须红（P3 的反买通对照）', '整族读数在 build/never_existed_dir/ 里', 'docs/x.md', { total: 1, dead: 1, prunedHit: 0 }],
    // 引用块（`>`）与 ``` 围栏同族：那是别人写下的原文，作者不许往里塞声明词。
    // Q2 钉住"同一句话挂在作者自己名下照旧必须红"，否则引用块会成为新的免检通道。
    ['Q1 引用块里的死引用只报数', '> 当时留的快照在 build/evidence/r9_eyes/gone.txt（用完就该删）', 'docs/x.md', { total: 0, dead: 0, skipQuote: 1 }],
    ['Q2 同一句写在作者名下 ⇒ 必须红（Q1 的反买通对照）', '当时留的快照在 build/evidence/r9_eyes/gone.txt（用完就该删）', 'docs/x.md', { total: 1, dead: 1, skipQuote: 0 }]
  ];
  let bad3 = 0;
  const pruned3 = new Set(['build/evidence/r7_pruned/example.rpt', 'build/evidence_r63b/roster.txt']);
  const prunedDirs3 = new Set(['build/', 'build/evidence/', 'build/evidence/r7_pruned/', 'build/evidence_r63b/']);
  for (const [name, text, rel, want] of c3cases) {
    const r = c3Judge(text, rel, has3, pruned3, prunedDirs3);
    const got = { total: r.total, dead: r.dead.length, skipFrag: r.skipFrag, skipRun: r.skipRun, skipLedger: r.skipLedger, skipShip: r.skipShip, skipFence: r.skipFence, skipQuote: r.skipQuote, prunedHit: r.prunedHit };
    const okk = Object.keys(want).every(k => got[k] === want[k]);
    if (!okk) bad3++;
    console.log(`CTRL ${name} 期望=${JSON.stringify(want)} 实读=${JSON.stringify(got)} ${okk ? '对照成立' : '对照不成立'}`);
  }
  // C9 的量纲对照（2026-10-05 随"只数判定列"这次改动一起补）：期望栏里的 FAIL 不许算成本轮失败，
  // 判定栏里的 FAIL 必须算；判定栏不成词要单独计数，不许被悄悄丢掉。
  const c9cases = [
    ['N 期望栏的 FAIL 不算红', '| B3 | `run_one.sh tb_video_pipeline_top` | 出处 | 期望 `RESULT … FAIL nfail=1` | 实跑：1 行 FAIL | **PASS** |', { rows: 1, pass: 1, fail: 0, nm: 0, noVerdict: 0 }],
    ['O 判定栏 FAIL 必须红', '| A11 | `node x.mjs` | 出处 | 期望 rc=0 | 实跑 rc=1 | **FAIL** |', { rows: 1, pass: 0, fail: 1, nm: 0, noVerdict: 0 }],
    ['P 判定栏 NOT_MEASURED 记未测', '| C2 | `board_verify` | 出处 | 期望 | 没跑 | NOT_MEASURED |', { rows: 1, pass: 0, fail: 0, nm: 1, noVerdict: 0 }],
    ['Q 判定栏不成词单独计（表形漂了要看得见）', '| S1 | `x` | 出处 | 期望 | 实跑 | 见下一节 |', { rows: 1, pass: 0, fail: 0, nm: 0, noVerdict: 1 }],
    ['R 登记行 R* 与表头不进射程', '| R16 | 内部计数不自洽 | 说明 | 备注 |\n| 集合 | 条数 | PASS | FAIL | NOT_MEASURED |', { rows: 0, pass: 0, fail: 0, nm: 0, noVerdict: 0 }]
  ];
  let bad4 = 0;
  for (const [name, text, want] of c9cases) {
    const g4 = c9Judge(text);
    const okk4 = Object.keys(want).every(k => g4[k] === want[k]);
    if (!okk4) bad4++;
    console.log(`CTRL ${name} 期望=${JSON.stringify(want)} 实读=${JSON.stringify(g4)} ${okk4 ? '对照成立' : '对照不成立'}`);
  }
  console.log(`C3 自检：造 ${c3cases.length} 例 不符=${bad3} C9 自检：造 ${c9cases.length} 例 不符=${bad4} 判 ${cases.length + c3cases.length + c9cases.length} 项 ${bad === 0 && bad3 === 0 && bad4 === 0 ? 'PASS' : 'FAIL'}`);
  return (bad === 0 && bad3 === 0 && bad4 === 0) ? 0 : 1;
}
if (process.argv.includes('--self')) { process.exit(selftestC2()); }

// C2 数字可追：metrics.csv 每行点名的证据文件必须存在（与仓库 D6 的 metric_recheck 互补：这里只查"指得到"，不查数值）
{
  const m = read('data/metrics.csv');
  if (m === null) row('C2', '指标数字指得到证据', '缺 data/metrics.csv', 'NOT_MEASURED');
  else {
    const rows = m.split(/\r?\n/).slice(1).filter(l => l.trim());
    const { ok, miss } = c2Judge(rows, exists);
    row('C2', '指标数字指得到证据', `行=${rows.length} 全指到=${ok} 缺或无路径=${miss.length}${miss.length ? ' 例:' + miss.slice(0, 3).join('|') : ''}`, rows.length === 0 ? 'NOT_MEASURED' : (miss.length === 0 ? 'PASS' : 'FAIL'));
  }
}
// C3 路径存活：文档里写的相对路径必须存在（判据定义与对照例在文件上半部，与 --self 共用）
{
  const files = mdFiles();
  const agg = { total: 0, dead: [], skipFrag: 0, skipRun: 0, skipLedger: 0, skipShip: 0, skipFence: 0, skipQuote: 0, prunedHit: 0 };
  for (const f of files) {
    const r = c3Judge(read(f) || '', f, exists, C3_PRUNED, C3_PRUNED_DIRS);
    agg.total += r.total; agg.dead.push(...r.dead);
    agg.skipFrag += r.skipFrag; agg.skipRun += r.skipRun; agg.skipLedger += r.skipLedger;
    agg.skipShip += r.skipShip; agg.skipFence += r.skipFence; agg.skipQuote += r.skipQuote; agg.prunedHit += r.prunedHit;
  }
  if (LIST) agg.dead.forEach(d => console.log('DEAD ' + d));   // --list 只把明细打全，判定与分母不变
  // 词表读不到 ⇒ 这一项**没判成**（不许把它念成"干净"，也不许念成"红"）
  if (!Array.isArray(C3_NOSHIP) || C3_NOSHIP.length === 0) {
    row('C3', '文档内路径存活', `扫=${files.length} 份 词表=读不到（doc_currency 的 NOSHIP_MARK 没解析出来）⇒ 豁免一支无法生效，本项不判`,
        'NOT_MEASURED');
  } else if (C3_PRUNED === null) {
    row('C3', '文档内路径存活', `扫=${files.length} 份 精简名单=读不到（git show 取不到 ${PRUNE_COMMITS.join('/')} 的删除清单）⇒ 历史凭据那一支豁免无法生效，本项不判`,
        'NOT_MEASURED');
  } else {
    row('C3', '文档内路径存活', `扫=${files.length} 份 检查路径引用=${agg.total} 死引用=${agg.dead.length}${agg.dead.length ? ' 例:' + agg.dead.slice(0, 3).join(' | ') : ''} 历史精简=${agg.prunedHit}（指的是被 ${PRUNE_COMMITS.join('/')} 删掉的凭据，只报数不判红） 豁免=碎片${agg.skipFrag}/运行期${agg.skipRun}/台账${agg.skipLedger}/同行声明${agg.skipShip}/围栏回显${agg.skipFence}/引用块${agg.skipQuote}（词表 ${C3_NOSHIP.length} 词，与 doc_currency 同一套）`,
        agg.total > 0 && agg.dead.length === 0 ? 'PASS' : agg.dead.length ? 'FAIL' : 'NOT_MEASURED');
  }
}
// C4 命名合规（调用技能包 G1 的等价逻辑，但范围是全仓跟踪文件）
{
  const r = sh('git', ['ls-files']);
  if (!r.ok) row('C4', '文件名纯小写 ASCII', 'git ls-files 失败', 'NOT_MEASURED');
  else {
    const list = r.out.split(/\r?\n/).filter(Boolean);
    const bad = list.filter(p => p.split('/').some(seg => !/^[A-Za-z0-9._-]+$/.test(seg) || /[A-Z\u4e00-\u9fff]/.test(seg)));
    // 豁免名单 = **条文或工具格式自己点名的名字**，不是"我们习惯这么写"：
    //   README.md / README_EN.md / LICENSE / NOTICE.md ← §0.4 与 §3.5 逐字写出的文件名
    //   SKILL.md                                      ← §5.3 交付的"技能包"条目外壳名，技能加载器只认这个拼写
    // §0.3 要禁的是中文、空格与特殊字符（本行的 ASCII 段检查照旧生效），不是这四个名字本身。
    const NAMES = ['README.md', 'README_EN.md', 'LICENSE', 'NOTICE.md', 'SKILL.md'];
    const exempt = bad.filter(p => NAMES.includes(p.split('/').pop()));
    const byName = {};
    for (const p of exempt) { const b = p.split('/').pop(); byName[b] = (byName[b] || 0) + 1; }
    // 反买通：豁免只可能来自这 5 个名字，且逐个点名计数；名单外的大写名一律留在违规里
    row('C4', '文件名纯小写 ASCII', `跟踪文件=${list.length} 违规=${bad.length - exempt.length} 点名豁免=${exempt.length}[${Object.entries(byName).map(([k, v]) => k + '=' + v).join(',')}] 名单上限=${NAMES.length} 名${bad.length - exempt.length ? ' 例:' + bad.filter(x => !exempt.includes(x)).slice(0, 3).join(' | ') : ''}`, list.length === 0 ? 'NOT_MEASURED' : (bad.length - exempt.length === 0 ? 'PASS' : 'FAIL'));
  }
}
// C5 许可合规：调用 P20 机检（带超时；超时＝NOT_MEASURED，绝不因为"没跑完"就当通过）
{
  if (!exists('build/checks/check_repo_hygiene.sh')) row('C5', '许可与卫生机检', '缺 build/checks/check_repo_hygiene.sh（P20）', 'NOT_MEASURED');
  else {
    const t0 = Date.now();
    const s = sh('bash', ['build/checks/check_repo_hygiene.sh'], HYGIENE_TMO);
    const el = Math.round((Date.now() - t0) / 1000);
    if (s.timedOut) { row('C5', '许可与卫生机检', `被调脚本 ${Math.round(HYGIENE_TMO / 1000)} s 未返回（本轮实测到 ${el} s 仍在跑）⇒ 记未测；慢在哪一行见 report/log/issues.md #339 末段`, 'NOT_MEASURED'); }
    else {
      const out = s.out || '';
      const reds = (out.match(/\bFAIL$/gm) || []).length, nm = (out.match(/\bNOT_MEASURED$/gm) || []).length;
      const olines = out.split(/\r?\n/).filter(l => / (PASS|FAIL|NOT_MEASURED)$/.test(l)).length;
      // 审计指出的洞：被调脚本"零输出 + rc=0"原来判 PASS ⇒ 加输出地板：至少要看到 6 行判定行才认为它真的跑了。
      row('C5', '许可与卫生机检', `红=${reds} 未测=${nm} 判定行=${olines}`, olines < 6 ? 'NOT_MEASURED' : (s.ok && reds === 0 ? 'PASS' : reds ? 'FAIL' : 'NOT_MEASURED'));
    }
  }
}
// C6 索引一致（调用 gen_index --check）
{
  const s = sh('node', ['skills/_meta/build-index.mjs', 'skills', '--check']);
  row('C6', '技能包索引一致', `rc=${s.ok ? 0 : 1} ${s.out.trim().split(/\r?\n/).pop() || ''}`, s.ok ? 'PASS' : 'FAIL');
}
// C7 状态一致：README 一览表的"验证状态"与条目 §7 的内容不许互相打脸
{
  const rd = read('skills/README.md');
  if (rd === null) row('C7', '验证状态三处一致', '缺 skills/README.md', 'NOT_MEASURED');
  else {
    let checked = 0, conflict = [];
    for (const l of rd.split(/\r?\n/)) {
      const m = l.match(/\|\s*`?((?:skill\/)?[a-z0-9_./-]+\/SKILL\.md)`?\s*\|.*\|\s*(待验证|已复跑[^|]*|不适用)\s*\|/);
      // 审计指出的洞：生成表每行的路径外面包着反引号，原正则的字符类里没有 ` ⇒ 一条都匹配不上，checked 恒 0，
      // 这条"README 状态 ↔ 条目 §7"的判据从未生效（现在字符类容反引号，并容 `skills/` 前缀）。
      if (!m) continue;
      let rel2 = m[1].startsWith('skills/') ? m[1] : 'skills/' + m[1];
      const sk = read(rel2);
      if (sk === null) { conflict.push(`${rel2} 文件不存在`); continue; }
      checked++;
      const s7 = (sk.split(/## 7\. 已验证的效果/)[1] || '').split(/## 8\./)[0];
      if (/已复跑/.test(m[2]) && !/【待验证】|【未实测】|NOT_MEASURED/.test(s7) === false) conflict.push(`${m[1]} 表=已复跑 但 §7 仍带未验证标记`);
      if (m[2] === '待验证' && /判 \d+ 项 (红=0|PASS)/.test(s7)) conflict.push(`${m[1]} 表=待验证 但 §7 写了实测通过读数`);
    }
    row('C7', '验证状态三处一致', `对=${checked} 冲突=${conflict.length}${conflict.length ? ' 例:' + conflict.slice(0, 3).join(' | ') : ''}`, checked > 0 && conflict.length === 0 ? 'PASS' : conflict.length ? 'FAIL' : 'NOT_MEASURED');
  }
}
// C8 未决项计数与汇总表一致
{
  const marks = ['【待验证】', '【未核实】', '【未实测】', '【队伍未确认】', '【待你补】', 'NOT_MEASURED', '【填入】'];
  const counts = {}; let total = 0;
  for (const f of mdFiles()) { const t = read(f) || ''; for (const k of marks) { const n = (t.match(new RegExp(k.replace(/[【】]/g, x => '\\' + x), 'g')) || []).length; if (n) { counts[k] = (counts[k] || 0) + n; total += n; } } }
  const open = read('report/90-open-items.md');
  // 两棵树的汇总表形状不同：主线那份是 `| 1 | 【标记】 | …`，提交分支由
  // `build/submit_open_items.mjs` 生成、首列就是标记（可有可无被反引号包住）。
  // 老正则只认前者，对这份件永远读成 0 行 ⇒ "表空就是缺认领"这条门从没看过真实的表（台账 #396）。
  // 两种形状都数，行数仍为 0 就判红。
  const ROW_RE = /^\|\s*(?:\d+\s*\|\s*)?`?(?:【[^】]*】|NOT_MEASURED)`?\s*\|/;
  const rows = open === null ? -1 : open.split(/\r?\n/).filter(l => ROW_RE.test(l)).length;
  // 审计指出的洞：原来只要 `rows > 0` 就判 PASS，正文标记与汇总表从不比对（名字叫"汇总一致"却不比）。
  // 现在要求：正文里每一类出现过的标记，汇总表里必须至少有一行认领它；缺类就 FAIL 并把类名念出来。
  const missingCls = open === null ? [] : Object.keys(counts).filter(k => !open.includes(k));
  row('C8', '未决项汇总一致', `正文标记总数=${total} ${Object.entries(counts).map(([k, v]) => k + '=' + v).join(' ')} 汇总表行=${rows < 0 ? '缺 report/90-open-items.md' : rows} 未认领的标记类=${missingCls.length}`,
    rows < 0 ? 'NOT_MEASURED' : (rows > 0 && missingCls.length === 0 ? 'PASS' : 'FAIL'));
}
// C9 复现演练
// 2026-10-05 改量纲：原来数的是**整篇文本里 ` PASS` / `FAIL` / `NOT_MEASURED` 出现次数**，
// 于是"期望输出那一栏写着 `RESULT tb_video_pipeline_top FAIL nfail=1`"这种**照抄的期望**也被算成一条红。
// 这份清单里那条是公开保留的已知缺陷（C5c），把它念成本轮的复现失败既是假话，也让这一项
// 永远绿不了——除非把期望值改掉，而那正是"改文档迁就尺子"。现在只读**每行的判定列**（末列）。
function c9Judge(text) {
  const out = { pass: 0, fail: 0, nm: 0, noVerdict: 0, rows: 0 };
  for (const line of String(text).split(/\r?\n/)) {
    if (!/^\s*\|/.test(line)) continue;
    const cells = line.split('|').map(s => s.trim()).filter(s => s.length);
    if (cells.length < 2) continue;
    if (!/^[SABCM]\d+[a-z]?$/.test(cells[0])) continue;         // 只数演练行；R*（不一致登记）与表头不进射程
    out.rows++;
    const v = cells[cells.length - 1];
    if (/NOT_MEASURED/.test(v)) out.nm++;
    else if (/FAIL/.test(v)) out.fail++;
    else if (/PASS/.test(v)) out.pass++;
    else out.noVerdict++;
  }
  return out;
}
{
  const rc = read('report/repro-check.md');
  if (rc === null) row('C9', 'A/B/C 路径复现演练', '缺 report/repro-check.md（P12）', 'NOT_MEASURED');
  else {
    const c9 = c9Judge(rc);
    row('C9', 'A/B/C 路径复现演练',
        `判定列在内=${c9.rows} 行 PASS=${c9.pass} FAIL=${c9.fail} 未测=${c9.nm} 判定列不成词=${c9.noVerdict}`,
        c9.rows < 40 ? 'NOT_MEASURED' : (c9.fail > 0 ? 'FAIL' : (c9.pass > 0 ? 'PASS' : 'NOT_MEASURED')));
  }
}
// C10 时间线自洽：本轮读数件不应早于其声称的来源件（只查 r119 一族，其余 NOT_MEASURED）
{
  const t = p => exists(p) ? fs.statSync(P(p)).mtimeMs : 0;
  const both = exists('board/output/pin_skew_probe2.txt') && exists('board/output/window_check.txt');
  const ok = both && t('board/output/pin_skew_probe2.txt') <= t('board/output/window_check.txt');
  // 审计指出的洞：t() 对缺失件返回 0，两份都不存在时 `0 <= 0` 判 PASS。现在先要求两件都在盘上。
  row('C10', '证据时间线自洽', `两件齐=${both ? '是' : '否'} 读数件→判读件 先后=${both ? (ok ? '正确' : '颠倒') : '无从判'}`,
    both ? (ok ? 'PASS' : 'FAIL') : 'NOT_MEASURED');
}
// C11 失败可见
{
  const cand = ['board/output/pin_skew_probe.txt', 'board/output/window_check.txt', 'board/acceptance.md', 'report/known_issues.md'];
  const has = cand.filter(exists).length;
  const failLines = cand.filter(exists).reduce((a, f) => a + (((read(f) || '').match(/FAIL|VIOLATED|NOT_MEASURED/g) || []).length), 0);
  row('C11', '失败与未测记录可见', `已登记候选件=${has}/${cand.length} 内含失败/未测字样=${failLines}`, has >= 3 && failLines > 0 ? 'PASS' : 'FAIL');
}
// C12 技能包四要素齐全：复用 P09 的 G1–G12
{
  const s = sh('node', ['skills/_meta/run-all-checks.mjs', 'skills']);
  const out = s.out || '';
  // 只数 `G<数字> ` 开头的判据行：原来用"整行以 PASS 结尾"来数，把 gates.mjs 自己的汇总行也算成一项 ⇒ 报出"绿=13"。
  // 条目数本身是被判的数（D1c 那一族），所以这里再加一条对账：绿+红+未测 必须 == 12，否则本项不可信。
  // 只数 `M<数字> `/`S<数字> ` 开头的判据行（现役 run-all-checks 打 M1–M3 + S1–S6 共 9 行，
  // 自己那句汇总是 `ALL-CHECKS 判 9 项`）；旧包 gates.mjs 的 12 条 G 行随 c7b325f 重建一起没了，
  // 这里的形状是**量出来的**，不是照抄旧常数——照抄会让这条永远 NOT_MEASURED。
  const gl = out.split(/\r?\n/).filter(l => /^[MS][0-9]+ /.test(l));
  const green = gl.filter(l => l.endsWith('PASS')).length, red = gl.filter(l => l.endsWith('FAIL')).length, nm = gl.filter(l => l.endsWith('NOT_MEASURED')).length;
  const recon = green + red + nm;
  row('C12', '技能包门禁（run-all-checks 的 M1–M3 与 S1–S6）', `绿=${green} 红=${red} 未测=${nm} 判据行=${gl.length} 加总对账=${recon}/9`,
      gl.length !== 9 || recon !== 9 ? 'NOT_MEASURED' : (s.ok && red === 0 && nm === 0 ? 'PASS' : red ? 'FAIL' : 'NOT_MEASURED'));
}

// 行已在 row() 里即时打印，这里不重打（重打会让分母看起来翻倍）
const reds = J.filter(l => l.trim().endsWith('FAIL')).length;
const nms = J.filter(l => l.trim().endsWith('NOT_MEASURED')).length;
console.log(`GATES 终审 C1–C12：判定 ${judged} 项 绿=${judged - reds - nms} 红=${reds} 未测=${nms} ${reds ? '有红项，不得提交' : nms ? '仍有未测项' : '全绿'} ${reds ? 'FAIL' : nms ? 'NOT_MEASURED' : 'PASS'}`);
process.exit(reds ? 1 : nms ? 2 : 0);
