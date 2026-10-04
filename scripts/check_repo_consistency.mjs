#!/usr/bin/env node
// scripts/check_repo_consistency.mjs —— 提交前终审的机器门禁（P21 的 C1–C12）
//
// 设计约束：
//  · 只读，不改任何文件；判定 token 放每行最后一个字段；每条打印分母；缺输入一律 NOT_MEASURED（绝不判通过）。
//  · 能复用就别重造：C4/C6/C12 直接调用技能包门禁（gates.mjs / gen_index.mjs），C5 调用 P20 的卫生机检。
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
const decl = read('docs/declarations.md');
const part = read('report/BUILD.md');
if (!SELF) {
  if (decl === null) row('C1', '声明唯一权威源', '缺 docs/declarations.md（P20 产出）', 'NOT_MEASURED');
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
        if (f === 'docs/declarations.md') continue;
        const t = read(f) || '';
        // 引文豁免：`skill/evals/records/` 存的是"陌生人演练/第三方审计的原话"，里面出现"2024.2（不是本包的 2025.2.1）"
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
const C3_RE = /(?:^|[\s`(（|])((?:build|docs|report|submit|board|data|src|sim|scripts|skill)\/[A-Za-z0-9_.\-\[\]*]{2,120})(?=[\s)|,，。；;：:]|$)/g;
// 两条射程修正（都是尺子自己的维度错，不是被量对象变好了）：
//  ① 只判"像一个文件"的串（带扩展名）或"像一个目录"的串（以 / 结尾）。改前 `board/README`、`src/dst`
//     这类行文碎片被当成路径引用，虚报死引用；
//  ② 运行期产物（*.log / *.dcp / impl_1/ / *.runs/）按仓库规矩本就不入库，要求它在盘上＝用错量纲。
const C3_HASFILE = /\.[A-Za-z][A-Za-z0-9]{1,6}$/;
const C3_RUNTIME = /(\.log|\.dcp|impl_1\/|\.runs\/|runme|vivado_system\/|__pycache__\/)/;
// 过程台账（report/log/）里的引用是"当时那一步看到的文件名"，改名轮之后必然对不上；
// 导出器的死链自检也按 #217 的同一条口径排除这一层，这里保持一致并把豁免数打出来（不是静默跳过）。
function c3Judge(t, relFile, has) {
  let total = 0, dead = [], skipFrag = 0, skipRun = 0, skipLedger = 0;
  const re = new RegExp(C3_RE.source, 'g');
  let m2;
  while ((m2 = re.exec(t))) {
    const c = m2[1].replace(/[.。，;)]+$/, '');
    if (/[*\[\]]/.test(c) || /rNN|<|>|\bdemo\b/.test(c)) continue;
    if (!C3_HASFILE.test(c) && !c.endsWith('/')) { skipFrag++; continue; }
    if (C3_RUNTIME.test(c)) { skipRun++; continue; }
    if (/^report\/log\//.test(relFile)) { skipLedger++; continue; }
    total++; if (!has(c)) dead.push(`${relFile} → ${c}`);
  }
  return { total, dead, skipFrag, skipRun, skipLedger };
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
  const has3 = f => f === 'docs/real.md';
  const c3cases = [
    ['G 行文碎片不算路径', '见 board/README 那一节', 'docs/x.md', { total: 0, dead: 0, skipFrag: 1 }],
    ['H 真缺的文件必须红', '对照 docs/gone.md 与 docs/real.md', 'docs/x.md', { total: 2, dead: 1, skipFrag: 0 }],
    ['I 运行期产物走豁免', '日志在 sim/a.log 里', 'docs/x.md', { total: 0, dead: 0, skipRun: 1 }],
    ['J 台账只走台账', '当时读的是 docs/gone.md', 'report/log/ISSUES.md', { total: 0, dead: 0, skipLedger: 1 }]
  ];
  let bad3 = 0;
  for (const [name, text, rel, want] of c3cases) {
    const r = c3Judge(text, rel, has3);
    const got = { total: r.total, dead: r.dead.length, skipFrag: r.skipFrag, skipRun: r.skipRun, skipLedger: r.skipLedger };
    const okk = Object.keys(want).every(k => got[k] === want[k]);
    if (!okk) bad3++;
    console.log(`CTRL ${name} 期望=${JSON.stringify(want)} 实读=${JSON.stringify(got)} ${okk ? '对照成立' : '对照不成立'}`);
  }
  console.log(`C3 自检：造 ${c3cases.length} 例 不符=${bad3} 判 ${cases.length + c3cases.length} 项 ${bad === 0 && bad3 === 0 ? 'PASS' : 'FAIL'}`);
  return (bad === 0 && bad3 === 0) ? 0 : 1;
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
  const agg = { total: 0, dead: [], skipFrag: 0, skipRun: 0, skipLedger: 0 };
  for (const f of files) {
    const r = c3Judge(read(f) || '', f, exists);
    agg.total += r.total; agg.dead.push(...r.dead);
    agg.skipFrag += r.skipFrag; agg.skipRun += r.skipRun; agg.skipLedger += r.skipLedger;
  }
  if (LIST) agg.dead.forEach(d => console.log('DEAD ' + d));   // --list 只把明细打全，判定与分母不变
  row('C3', '文档内路径存活', `扫=${files.length} 份 检查路径引用=${agg.total} 死引用=${agg.dead.length}${agg.dead.length ? ' 例:' + agg.dead.slice(0, 3).join(' | ') : ''} 豁免=碎片${agg.skipFrag}/运行期${agg.skipRun}/台账${agg.skipLedger}`,
      agg.total > 0 && agg.dead.length === 0 ? 'PASS' : agg.dead.length ? 'FAIL' : 'NOT_MEASURED');
}
// C4 命名合规（调用技能包 G1 的等价逻辑，但范围是全仓跟踪文件）
{
  const r = sh('git', ['ls-files']);
  if (!r.ok) row('C4', '文件名纯小写 ASCII', 'git ls-files 失败', 'NOT_MEASURED');
  else {
    const list = r.out.split(/\r?\n/).filter(Boolean);
    const bad = list.filter(p => p.split('/').some(seg => !/^[A-Za-z0-9._-]+$/.test(seg) || /[A-Z\u4e00-\u9fff]/.test(seg)));
    const exempt = bad.filter(p => /(^|\/)(README|LICENSE|NOTICE)(\.md)?$/.test(p));
    row('C4', '文件名纯小写 ASCII', `跟踪文件=${list.length} 违规=${bad.length - exempt.length} 点名豁免=${exempt.length}${bad.length - exempt.length ? ' 例:' + bad.filter(x => !exempt.includes(x)).slice(0, 3).join(' | ') : ''}`, list.length === 0 ? 'NOT_MEASURED' : (bad.length - exempt.length === 0 ? 'PASS' : 'FAIL'));
  }
}
// C5 许可合规：调用 P20 机检（带超时；超时＝NOT_MEASURED，绝不因为"没跑完"就当通过）
{
  if (!exists('scripts/check_repo_hygiene.sh')) row('C5', '许可与卫生机检', '缺 scripts/check_repo_hygiene.sh（P20）', 'NOT_MEASURED');
  else {
    const t0 = Date.now();
    const s = sh('bash', ['scripts/check_repo_hygiene.sh'], HYGIENE_TMO);
    const el = Math.round((Date.now() - t0) / 1000);
    if (s.timedOut) { row('C5', '许可与卫生机检', `被调脚本 ${Math.round(HYGIENE_TMO / 1000)} s 未返回（本轮实测到 ${el} s 仍在跑）⇒ 记未测；慢在哪一行见 report/log/ISSUES.md #339 末段`, 'NOT_MEASURED'); }
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
  const s = sh('node', ['skill/scripts/check/gen_index.mjs', '--check']);
  row('C6', '技能包索引一致', `rc=${s.ok ? 0 : 1} ${s.out.trim().split(/\r?\n/).pop() || ''}`, s.ok ? 'PASS' : 'FAIL');
}
// C7 状态一致：README 一览表的"验证状态"与条目 §7 的内容不许互相打脸
{
  const rd = read('skill/README.md');
  if (rd === null) row('C7', '验证状态三处一致', '缺 skill/README.md', 'NOT_MEASURED');
  else {
    let checked = 0, conflict = [];
    for (const l of rd.split(/\r?\n/)) {
      const m = l.match(/\|\s*`?((?:skill\/)?[a-z0-9_./-]+\/SKILL\.md)`?\s*\|.*\|\s*(待验证|已复跑[^|]*|不适用)\s*\|/);
      // 审计指出的洞：生成表每行的路径外面包着反引号，原正则的字符类里没有 ` ⇒ 一条都匹配不上，checked 恒 0，
      // 这条"README 状态 ↔ 条目 §7"的判据从未生效（现在字符类容反引号，并容 `skill/` 前缀）。
      if (!m) continue;
      let rel2 = m[1].startsWith('skill/') ? m[1] : 'skill/' + m[1];
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
  const rows = open === null ? -1 : open.split(/\r?\n/).filter(l => /^\|\s*\d+\s*\|/.test(l)).length;
  // 审计指出的洞：原来只要 `rows > 0` 就判 PASS，正文标记与汇总表从不比对（名字叫"汇总一致"却不比）。
  // 现在要求：正文里每一类出现过的标记，汇总表里必须至少有一行认领它；缺类就 FAIL 并把类名念出来。
  const missingCls = open === null ? [] : Object.keys(counts).filter(k => !open.includes(k));
  row('C8', '未决项汇总一致', `正文标记总数=${total} ${Object.entries(counts).map(([k, v]) => k + '=' + v).join(' ')} 汇总表行=${rows < 0 ? '缺 report/90-open-items.md' : rows} 未认领的标记类=${missingCls.length}`,
    rows < 0 ? 'NOT_MEASURED' : (rows > 0 && missingCls.length === 0 ? 'PASS' : 'FAIL'));
}
// C9 复现演练
{
  const rc = read('docs/repro-check.md');
  if (rc === null) row('C9', 'A/B/C 路径复现演练', '缺 docs/repro-check.md（P12）', 'NOT_MEASURED');
  else {
    const nm = (rc.match(/NOT_MEASURED/g) || []).length, pass = (rc.match(/ PASS/g) || []).length, fail = (rc.match(/\bFAIL\b/g) || []).length;
    // 审计指出的洞：原来只数 " PASS" 出现次数，满篇 FAIL 只要有一处 " PASS" 就绿。
    // 现在：有 FAIL 就判不了绿；一条 PASS 都没有 ⇒ NOT_MEASURED。
    row('C9', 'A/B/C 路径复现演练', `PASS=${pass} FAIL=${fail} 未测=${nm}`, fail > 0 ? 'FAIL' : (pass > 0 ? 'PASS' : 'NOT_MEASURED'));
  }
}
// C10 时间线自洽：本轮读数件不应早于其声称的来源件（只查 r119 一族，其余 NOT_MEASURED）
{
  const t = p => exists(p) ? fs.statSync(P(p)).mtimeMs : 0;
  const both = exists('build/evidence/r119_pin_skew_probe2.txt') && exists('build/evidence/r119_window_check.txt');
  const ok = both && t('build/evidence/r119_pin_skew_probe2.txt') <= t('build/evidence/r119_window_check.txt');
  // 审计指出的洞：t() 对缺失件返回 0，两份都不存在时 `0 <= 0` 判 PASS。现在先要求两件都在盘上。
  row('C10', '证据时间线自洽', `两件齐=${both ? '是' : '否'} 读数件→判读件 先后=${both ? (ok ? '正确' : '颠倒') : '无从判'}`,
    both ? (ok ? 'PASS' : 'FAIL') : 'NOT_MEASURED');
}
// C11 失败可见
{
  const cand = ['build/evidence/r119_pin_skew_probe.txt', 'build/evidence/r119_window_check.txt', 'board/ACCEPTANCE.md', 'report/KNOWN_ISSUES.md'];
  const has = cand.filter(exists).length;
  const failLines = cand.filter(exists).reduce((a, f) => a + (((read(f) || '').match(/FAIL|VIOLATED|NOT_MEASURED/g) || []).length), 0);
  row('C11', '失败与未测记录可见', `已登记候选件=${has}/${cand.length} 内含失败/未测字样=${failLines}`, has >= 3 && failLines > 0 ? 'PASS' : 'FAIL');
}
// C12 技能包四要素齐全：复用 P09 的 G1–G12
{
  const s = sh('node', ['skill/scripts/check/gates.mjs']);
  const out = s.out || '';
  // 只数 `G<数字> ` 开头的判据行：原来用"整行以 PASS 结尾"来数，把 gates.mjs 自己的汇总行也算成一项 ⇒ 报出"绿=13"。
  // 条目数本身是被判的数（D1c 那一族），所以这里再加一条对账：绿+红+未测 必须 == 12，否则本项不可信。
  const gl = out.split(/\r?\n/).filter(l => /^G[0-9]+ /.test(l));
  const green = gl.filter(l => l.endsWith('PASS')).length, red = gl.filter(l => l.endsWith('FAIL')).length, nm = gl.filter(l => l.endsWith('NOT_MEASURED')).length;
  const recon = green + red + nm;
  row('C12', '技能包门禁（G1–G12 调用）', `绿=${green} 红=${red} 未测=${nm} 判据行=${gl.length} 加总对账=${recon}/12`,
      gl.length !== 12 || recon !== 12 ? 'NOT_MEASURED' : (s.ok && red === 0 && nm === 0 ? 'PASS' : red ? 'FAIL' : 'NOT_MEASURED'));
}

// 行已在 row() 里即时打印，这里不重打（重打会让分母看起来翻倍）
const reds = J.filter(l => l.trim().endsWith('FAIL')).length;
const nms = J.filter(l => l.trim().endsWith('NOT_MEASURED')).length;
console.log(`GATES 终审 C1–C12：判定 ${judged} 项 绿=${judged - reds - nms} 红=${reds} 未测=${nms} ${reds ? '有红项，不得提交' : nms ? '仍有未测项' : '全绿'} ${reds ? 'FAIL' : nms ? 'NOT_MEASURED' : 'PASS'}`);
process.exit(reds ? 1 : nms ? 2 : 0);
