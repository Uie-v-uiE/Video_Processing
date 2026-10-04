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
function mdFiles() {
  const out = [];
  const walk = (rel) => {
    const abs = P(rel);
    if (!fs.existsSync(abs)) return;
    const st = fs.statSync(abs);
    if (st.isFile()) { if (rel.endsWith('.md')) out.push(rel); return; }
    for (const e of fs.readdirSync(abs)) { if (e === 'node_modules' || e.startsWith('.')) continue; walk(path.join(rel, e)); }
  };
  MD_SCOPE.forEach(walk);
  return out;
}

// C1 单一事实源：器件/版本只允许一处权威，其余引用
const decl = read('docs/declarations.md');
const part = read('report/BUILD.md');
{
  const canon = { dev: 'xc7z020clg484-2', ver: '2025.2.1', build: '6403652' };
  const hits = {};
  for (const k in canon) hits[k] = mdFiles().filter(f => (read(f) || '').includes(canon[k])).length;
  if (decl === null) row('C1', '声明唯一权威源', `缺 docs/declarations.md（P20 产出），另出现 ${canon.ver} 的文件数=${hits.ver}`, 'NOT_MEASURED');
  else {
    const others = mdFiles().filter(f => f !== 'docs/declarations.md' && /xc7[a-z0-9]+|Vivado[^\n]{0,20}20\d\d\.\d/.test(read(f) || ''));
    row('C1', '声明唯一权威源', `权威=${path.basename(decl ? 'docs/declarations.md' : '')} 出现该型号/版本的文件数=${hits.ver} 含器件或版本的其它文件=${others.length}`, others.length === 0 ? 'PASS' : 'FAIL');
  }
}
// C2 数字可追：metrics.csv 每行点名的证据文件必须存在（与仓库 D6 的 metric_recheck 互补：这里只查"指得到"，不查数值）
{
  const m = read('data/metrics.csv');
  if (m === null) row('C2', '指标数字指得到证据', '缺 data/metrics.csv', 'NOT_MEASURED');
  else {
    const rows = m.split(/\r?\n/).slice(1).filter(l => l.trim());
    const pathRe = /((?:build|docs|report|board|data|src|sim|scripts)\/[^\s,;]+|README\.md)/g;
    let ok = 0, miss = [];
    for (const l of rows) { const c = l.match(pathRe) || []; if (c.length) (c.every(x => exists(x)) ? ok++ : miss.push(l.split(',')[0])); else miss.push('(无路径)' + l.split(',')[0]); }
    row('C2', '指标数字指得到证据', `行=${rows.length} 全指到=${ok} 缺或无路径=${miss.length}${miss.length ? ' 例:' + miss.slice(0, 3).join('|') : ''}`, rows.length === 0 ? 'NOT_MEASURED' : (miss.length === 0 ? 'PASS' : 'FAIL'));
  }
}
// C3 路径存活：文档里写的相对路径必须存在
{
  const files = mdFiles();
  const re = /(?:^|[\s`(（|])((?:build|docs|report|submit|board|data|src|sim|scripts|skill)\/[A-Za-z0-9_.\-\[\]*]{2,120})(?=[\s)|,，。；;：:]|$)/g;
  let total = 0, dead = [];
  for (const f of files) {
    const t = read(f) || ''; let m2;
    while ((m2 = re.exec(t))) {
      const c = m2[1].replace(/[.。，;)]+$/, '');
      if (/[*\[\]]/.test(c) || /rNN|<|>|\bdemo\b/.test(c)) continue;
      total++; if (!exists(c)) dead.push(`${f} → ${c}`);
    }
    re.lastIndex = 0;
  }
  row('C3', '文档内路径存活', `扫=${files.length} 份 检查路径引用=${total} 死引用=${dead.length}${dead.length ? ' 例:' + dead.slice(0, 3).join(' | ') : ''}`, total > 0 && dead.length === 0 ? 'PASS' : dead.length ? 'FAIL' : 'NOT_MEASURED');
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
    const s = sh('bash', ['scripts/check_repo_hygiene.sh'], 60000);
    if (s.timedOut) { row('C5', '许可与卫生机检', '被调脚本 60 s 未返回 ⇒ 记未测（同时说明该脚本可能扫了 vivado_system/ 等生成目录，要收紧射程）', 'NOT_MEASURED'); }
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
  const green = (out.match(/ PASS$/gm) || []).length, red = (out.match(/ FAIL$/gm) || []).length, nm = (out.match(/ NOT_MEASURED$/gm) || []).length;
  row('C12', '技能包门禁（G1–G12 调用）', `绿=${green} 红=${red} 未测=${nm}`, s.ok && red === 0 && nm === 0 ? 'PASS' : red ? 'FAIL' : 'NOT_MEASURED');
}

// 行已在 row() 里即时打印，这里不重打（重打会让分母看起来翻倍）
const reds = J.filter(l => l.trim().endsWith('FAIL')).length;
const nms = J.filter(l => l.trim().endsWith('NOT_MEASURED')).length;
console.log(`GATES 终审 C1–C12：判定 ${judged} 项 绿=${judged - reds - nms} 红=${reds} 未测=${nms} ${reds ? '有红项，不得提交' : nms ? '仍有未测项' : '全绿'} ${reds ? 'FAIL' : nms ? 'NOT_MEASURED' : 'PASS'}`);
process.exit(reds ? 1 : nms ? 2 : 0);
