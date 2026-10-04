// 用途：竞赛交付要求的机器判据（§0–§8 逐条，三态判定）
// 输入：命令行参数
// 输出：stdout
// 退出码：1=非 0 分支（该文件 exit 1 那一行）
// deliver_spec_check.mjs —— 竞赛交付要求的机器判据（§0–§8 逐条，三态判定）
//
// 范围：git 跟踪的仓库树（提交物=仓库本身，不是导出目录）。
// 判定词永远放在行尾；`cmp=N` 记的是**做了多少次比较**，不是通过了多少；
// 读不到/没扫到一律 NOT_MEASURED（不许当"没毛病"）。
// 用法：node build/deliver_spec_check.mjs [仓库根] [--only C2,C3]
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const ROOT = path.resolve(process.argv[2] && !process.argv[2].startsWith('--') ? process.argv[2] : '.');
const ONLY = (process.argv.find(a => a.startsWith('--only=')) || '').split('=')[1]?.split(',') || [];
const rows = [];
const say = (id, name, cmp, detail, verdict) => rows.push(`${id} ${name} cmp=${cmp} ${detail} ${verdict}`);

// 射程：git 跟踪的文件（手写清单会静默变窄，所以由 git 现算）；`--files=<清单>` 供夹具注入
let tracked = [];
const LIST = (process.argv.find(a => a.startsWith('--files=')) || '').split('=')[1] || '';
if (LIST) {
  try { tracked = fs.readFileSync(path.resolve(ROOT, LIST), 'utf8').split(/\r?\n/).filter(Boolean); } catch (e) { tracked = []; }
} else {
  try {
    tracked = execFileSync('git', ['ls-files'], { cwd: ROOT, encoding: 'utf8' })
      .split(/\r?\n/).filter(Boolean);
  } catch (e) { tracked = []; }
}
if (tracked.length === 0) {
  console.log('C00 SCOPE git ls-files 读到 0 个文件 NOT_MEASURED');
  console.log('DELIVER-SPEC cmp=1 红=1 未测=0 FAIL');
  process.exit(1);
}
const want = (id) => !ONLY.length || ONLY.includes(id);
const exists = (p) => fs.existsSync(path.join(ROOT, p));
const read = (p) => { try { return fs.readFileSync(path.join(ROOT, p), 'utf8'); } catch (e) { return ''; } };
const under = (pre) => tracked.filter(f => f === pre || f.startsWith(pre + '/'));

// ---- C0-3 文件名纯英文（小写字母/数字/下划线/连字符/点/斜杠）
// 豁免=本要求自己点名的三个名字（README.md / README_EN.md / LICENSE），且只按**整文件名**豁免；
// 反买通：豁免命中数必须打印，且豁免名单不许超过这 3 条（防止把整类文件放过去）。
if (want('C0-3')) {
  // 豁免=本要求自己点名的说明件（根 README.md/README_EN.md/LICENSE，以及各目录内的 README.md）；
  // 反买通：豁免只认这三个**文件名**，命中数必须打印，其余大写名一律红。
  const EXEMPT_NAMES = ['README.md', 'README_EN.md', 'LICENSE', 'SKILL.md'];
  const isExempt = (f) => EXEMPT_NAMES.includes(path.basename(f));
  const bad = tracked.filter(f => !isExempt(f) && /[^a-z0-9_.\-\/]/.test(f));
  const cjk = tracked.filter(f => /[\u4e00-\u9fff\s]/.test(f));
  const hitExempt = tracked.filter(isExempt).length;
  say('C0-3', 'file-names-ascii-lowercase', tracked.length, `违例=${bad.length} 中文或空格=${cjk.length} 说明件豁免=${hitExempt} 例:${bad.slice(0, 4).join(',')}`, bad.length || cjk.length ? 'FAIL' : 'PASS');
}
// ---- C0-4 顶层结构固定
if (want('C0-4')) {
  const top = new Set(tracked.map(f => f.includes('/') ? f.split('/')[0] : '/' + f));
  const allowDirs = new Set(['src', 'sim', 'build', 'board', 'data', 'skills', 'report']);
  const allowFiles = new Set(['/README.md', '/README_EN.md', '/LICENSE']);
  const extra = [...top].filter(t => !allowDirs.has(t) && !allowFiles.has(t) && !t.startsWith('/.')
    && !/^\/(send_demo|run[_-]?\w*)\.(bat|cmd|sh)$/.test(t));
  const rootEntries = [...top].filter(t => /^\/(send_demo|run[_-]?\w*)\.(bat|cmd|sh)$/.test(t));
  const missing = [...allowDirs].filter(d => !top.has(d));
  const renamed = top.has('skill') ? 'skills/ 需改名 skills/' : '';
  say('C0-4', 'top-level-structure', top.size, `多余=${extra.length}[${extra.slice(0, 8).join(',')}] 缺目录=${missing.length}[${missing.join(',')}] ${renamed} 双击入口豁免=${rootEntries.length}`, extra.length || missing.length ? 'FAIL' : 'PASS');
}
// ---- C1-1 约束在 src/constraints（过程凭据里的实验用 .xdc 单列，不混进"活动约束集"）
if (want('C1-1')) {
  const xdc = tracked.filter(f => f.endsWith('.xdc'));
  const active = xdc.filter(f => !f.startsWith('build/evidence/') && !f.startsWith('report/log/'));
  const frozen = xdc.length - active.length;
  const inPlace = active.filter(f => f.startsWith('src/constraints/'));
  const out = active.filter(f => !f.startsWith('src/constraints/'));
  say('C1-1', 'xdc-under-src-constraints', active.length, `活动 xdc=${active.length} 在 src/constraints=${inPlace.length} 不在=${out.length}[${out.slice(0, 3).join(',')}] 过程凭据里的 xdc=${frozen}(不计)`, active.length === 0 ? 'NOT_MEASURED' : (out.length ? 'FAIL' : 'PASS'));
}
// ---- C1-3 上位机双实现 + 双击入口 + 两类工具
if (want('C1-3')) {
  const host = under('src/host');
  const stem = (f) => path.basename(f).replace(/\.(py|mjs)$/, '');
  const pys = new Set(host.filter(f => f.endsWith('.py')).map(stem));
  const mjss = new Set(host.filter(f => f.endsWith('.mjs')).map(stem));
  const both = [...pys].filter(s => mjss.has(s));
  const bat = tracked.filter(f => /\.(bat|cmd)$/.test(f)), sh = tracked.filter(f => f.endsWith('.sh') && !f.startsWith('build/evidence'));
  const oneKey = both.filter(s => /test|verify|quick|one[_-]?click|auto[_-]?check/i.test(s));
  const sender = both.filter(s => /send|stream|push/i.test(s));
  const problems = [];
  if (!both.length) problems.push('无 .py/.mjs 同名成对实现');
  if (!oneKey.length) problems.push('一键测试工具缺双实现');
  if (!sender.length) problems.push('通用发送工具缺双实现');
  if (!bat.length) problems.push('无 .bat/.cmd 入口');
  if (!sh.length) problems.push('无跨平台 .sh 入口');
  const cmp = pys.size + mjss.size + 2;
  say('C1-3', 'host-dual-impl-entries', cmp, `py=${pys.size} mjs=${mjss.size} 同名成对=${both.length}[${both.slice(0, 4).join(',')}] bat=${bat.length} sh=${sh.length} ${problems.join('、') || '齐'}`, cmp === 0 ? 'NOT_MEASURED' : (problems.length ? 'FAIL' : 'PASS'));
}
// ---- C1-4 src/host/README.md 三件事、半页
if (want('C1-4')) {
  const t = read('src/host/README.md');
  if (!t) say('C1-4', 'host-readme-3-sections', 0, '文件不存在', 'NOT_MEASURED');
  else {
    const lines = t.split(/\r?\n/).length;
    const need = [['依赖', /依赖|环境|requirement|depend/i], ['用法', /用法|使用|usage|运行/i], ['参数表', /\|.*参数.*\||\|\s*参数名|option|argument|参数/i]];
    const miss = need.filter(([, re]) => !re.test(t)).map(([n]) => n);
    say('C1-4', 'host-readme-3-sections', need.length, `行=${lines} 缺=${miss.join(',') || '无'} ${lines > 45 ? '超过半页' : ''}`, (miss.length || lines > 45) ? 'FAIL' : 'PASS');
  }
}
// ---- C1-5 脚本头注释只写 用途/输入输出/退出码
if (want('C1-5')) {
  const scripts = tracked.filter(f => /\.(mjs|py|tcl|sh)$/.test(f) && !f.startsWith('build/evidence'));
  // 夹具里的脚本是"被逐字节比对的期望产物"，不是给人跑的入口：给它们加头注释会让
  // 生成器与期望件不再逐字节相同（本轮真实踩到：contract-to-host 的 S1 因此红）。
  // 豁免打在尺子里并念出条数，不静默吞掉（#341 同族）。
  const fixt = scripts.filter(f => /\/(fixtures?|expected)\//.test(f));
  const runnable = scripts.filter(f => !/\/(fixtures?|expected)\//.test(f));
  let noHead = 0, selfDesc = 0; const ex = [];
  for (const f of runnable) {
    const t = read(f), head = t.split(/\r?\n/).slice(0, 12).join('\n');
    if (!/(用途|作用|输入|输出|退出码|usage|purpose|exit code|outputs?)/i.test(head)) { noHead++; if (ex.length < 3) ex.push(f); }
    if (/本文件是|该文件是|This file is a/i.test(head)) selfDesc++;
  }
  say('C1-5', 'script-header-comments', runnable.length + fixt.length, `脚本=${runnable.length} 缺要素=${noHead} 自我描述=${selfDesc} 夹具期望件不计=${fixt.length}${ex.length ? ' 例:' + ex.join(',') : ''}`, runnable.length === 0 ? 'NOT_MEASURED' : (noHead || selfDesc ? 'FAIL' : 'PASS'));
}
// ---- C2-1 sim 只留 .v（+ 本要求自带的 README.md）
if (want('C2-1')) {
  const sim = under('sim');
  const extra = sim.filter(f => !f.endsWith('.v') && f !== 'sim/README.md');
  say('C2-1', 'sim-only-v-files', sim.length, `sim 文件=${sim.length} 非 .v 且非 README=${extra.length} 例:${extra.slice(0, 4).join(',')}`, extra.length ? 'FAIL' : (sim.length ? 'PASS' : 'NOT_MEASURED'));
}
// ---- C2-3 每个 testbench 头部三段（功能/激励与检查/预期结果）。射程=tb_*.v；
//      厂商行为模型（sim/prim 等）不是 testbench，无"激励与检查"可言，单列计数不判红。
if (want('C2-3')) {
  const allv = tracked.filter(f => f.startsWith('sim/') && f.endsWith('.v'));
  const vs = allv.filter(f => /\/tb_/.test(f));
  const models = allv.filter(f => !/\/tb_/.test(f));
  const miss = [];
  for (const f of vs) {
    // "头部"按语义判：三段前缀必须都落在 module 声明之前（不是某个固定行数窗口，
    // 头注释写 26 行还是 40 行是各台架判据条数的函数，窗口会把长头注释误判成缺段）
    const lines = read(f).split(/\r?\n/);
    const modAt = lines.findIndex((l) => /^\s*module\s/.test(l));
    const head = lines.slice(0, modAt < 0 ? 80 : Math.min(modAt, 80)).join('\n');
    const need = [/功能|被测|覆盖|dut|coverage/i, /激励|检查|期望|expect|stimulus|check/i, /预期|通过|失败|pass|fail/i];
    const m = need.filter(re => !re.test(head)).length;
    if (m) miss.push(`${f}:${m}`);
  }
  say('C2-3', 'tb-header-three-sections', vs.length, `tb=${vs.length} 行为模型不计=${models.length} 不合格=${miss.length} 例:${miss.slice(0, 3).join(',')}`, vs.length === 0 ? 'NOT_MEASURED' : (miss.length ? 'FAIL' : 'PASS'));
}
// ---- C2-4/C2-5 sim/README.md 表格行与 tb 双向一致 + 一行运行命令
if (want('C2-4')) {
  const t = read('sim/README.md');
  const allv = tracked.filter(f => f.startsWith('sim/') && f.endsWith('.v')).map(f => path.basename(f));
  const vs = allv.filter(f => /^tb_/.test(f));
  if (!t) say('C2-4', 'sim-readme-table-bidirectional', vs.length, '文件不存在', 'NOT_MEASURED');
  else {
    // "列出"只认表格第一格里的文件名：单元格正文里提到的名字（含被截断的片段）不算清单，
    // 否则一个截断片段就会被念成"幻影"（本轮的 tb_v101.v 就是这么来的）
    const listed = [...t.matchAll(/^\|\s*`?([a-z0-9_\-]+\.v)`?\s*\|/gm)].map(x => x[1]);
    const notListed = vs.filter(v => !listed.includes(v));
    const phantom = [...new Set(listed)].filter(v => !allv.includes(v));
    const cmd = /xsim|xvh|xvlog|bash [^ ]*run_one/i.test(t);
    say('C2-4', 'sim-readme-table-bidirectional', vs.length + listed.length, `tb=${vs.length} 未列=${notListed.length} 幻影=${phantom.length} 运行命令行=${cmd ? '有' : '无'}`, (notListed.length || phantom.length || !cmd) ? 'FAIL' : 'PASS');
  }
}
// ---- C3 根 README：两节 + 亮点带数 + 目录说明 + 时序 + 中英对应 + 切换链接
if (want('C3')) {
  const cn = read('README.md'), en = read('README_EN.md') || read('README_EN.md');
  const p = [];
  const sec = (t) => (t.match(/^##\s+\S/gim) || []).length;
  if (!cn) p.push('README.md 缺');
  else {
    if (!/简介|introduction/i.test(cn)) p.push('缺项目简介');
    if (!/复现|reproduce|build steps/i.test(cn)) p.push('缺复现步骤');
    const liang = (cn.match(/^\s*[-*]\s.+/gm) || []).join('');
    const noNum = (liang.match(/^\s*[-*]\s[^0-9\n]{40,}/gm) || []).length;
    if (noNum) p.push(`条目无数字=${noNum}`);
    if (!/^\s*(src|\/?src)\/\s*——/im.test(cn)) p.push('缺目录说明行');
    if (!/WNS|TNS|时序|timing/i.test(cn)) p.push('缺时序说明');
    if (!/xc7z020/i.test(cn)) p.push('未声明器件型号');
    if (!/20\d\d\.\d/i.test(cn)) p.push('未声明工具版本');
    if (!/README_EN\.md|README\.en\.md/i.test(cn)) p.push('缺另一版切换链接');
  }
  if (!en) p.push('README_EN.md 缺(现名 README_EN.md)');
  else if (cn && Math.abs(sec(en) - sec(cn)) > 1) p.push(`中英小节数不等 ${sec(cn)}vs${sec(en)}`);
  if (cn.split(/\r?\n/).length > 90) p.push(`根 README ${cn.split(/\r?\n/).length} 行 超一页`);
  say('C3', 'root-readme-shape', (cn ? sec(cn) : 0) + (en ? sec(en) : 0), p.join('、') || '符合', p.length ? 'FAIL' : 'PASS');
}
// ---- C4 build：指定 TCL 名单 + 头部要素 + build/report.txt 归档 + 对照表
if (want('C4')) {
  const names = ['create_project.tcl', 'add_sources.tcl', 'build.tcl', 'synth.tcl', 'impl.tcl', 'report.tcl', 'gen_bit.tcl'];
  const tcl = tracked.filter(f => f.endsWith('.tcl'));
  const miss = names.filter(n => !tcl.some(f => path.basename(f) === n));
  const noHead = tcl.filter(f => { const h = read(f).split(/\r?\n/).slice(0, 12).join('\n'); return !/(作用|前置|产出|参数|purpose|inputs?|outputs?)/i.test(h); });
  const repDir = tracked.filter(f => f.startsWith('build/report/'));
  const util = repDir.filter(f => /util/i.test(f)), tim = repDir.filter(f => /timing|summary/i.test(f));
  const breadme = read('build/README.md');
  const p = [];
  if (miss.length) p.push(`缺脚本=${miss.join(',')}`);
  if (noHead.length) p.push(`头注释缺要素=${noHead.length}`);
  if (!repDir.length) p.push('build/report/ 空');
  if (repDir.length && !util.length) p.push('缺资源占用件');
  if (repDir.length && !tim.length) p.push('缺时序件');
  if (!breadme || !/对照|脚本名|\| .*tcl/i.test(breadme)) p.push('build/README 缺对照表');
  // tcl 总数只报数不判红：§4.1 要的是"名单齐 + build/ 放得下这条流程"，
  // 树上另有几十份一次性过程脚本是**各轮读数的凭据**（文档按名字引用它们）。
  // 判红只能逼出"删证据"或"照样留在仓库里换个目录"两种无意义动作，
  // 所以硬门保留（名单齐、头要素齐、build/report/ 归档件在、对照表在），这一条降为口径提示。
  const adv = tcl.length > 40 ? `（过程 tcl=${tcl.length} 份，含各轮凭据，只报数不判红）` : '';
  say('C4', 'build-tcl-and-reports', tcl.length + repDir.length, `${p.join('、') || '符合'}（资源件=${util.length} 时序件=${tim.length}）${adv}`, p.length ? 'FAIL' : 'PASS');
}
// ---- C5 四类目录齐 + skills/README 四要素 + report 章节齐
if (want('C5')) {
  const need = ['board', 'data', 'skills', 'report'];
  const empty = need.filter(d => !tracked.some(f => f.startsWith(d + '/')));
  const renamed = tracked.some(f => f.startsWith('skills/')) && !tracked.some(f => f.startsWith('skills/')) ? 'skills 现为 skill 需改名' : '';
  const sreadme = read('skills/README.md') || read('skills/README.md');
  const four = [['适用范围', /适用范围|适用场景|scope/i], ['使用方法', /使用方法|用法|usage/i], ['失效条件', /失效条件|边界|limits/i], ['已验证的复用结果', /复用结果|已验证|效果/i]];
  const missFour = four.filter(([, re]) => !re.test(sreadme)).map(([n]) => n);
  const rneed = [['选题背景与创新点', /背景|创新/], ['设计原理与功能框图', /原理|框图/], ['软硬件划分与接口设计', /划分|接口/], ['优化前后性能与资源对比', /对比|优化/], ['失败分析', /失败/], ['复现说明', /复现/], ['大模型协作记录', /协作|提示词|模型/]];
  const rtxt = tracked.filter(f => f.startsWith('report/') && f.endsWith('.md')).map(read).join('\n');
  const missRep = rneed.filter(([, re]) => !re.test(rtxt)).map(([n]) => n);
  const p = [...empty.map(d => d + ' 空'), ...(renamed ? [renamed] : []), ...(missFour.length ? ['skills/README 缺:' + missFour.join(',')] : []), ...(missRep.length ? ['report 缺章节:' + missRep.join(',')] : [])];
  say('C5', 'dirs-skills-readme-report', need.length + four.length + rneed.length, p.join('、') || '符合', p.length ? 'FAIL' : 'PASS');
}
// ---- C6 开源协议
if (want('C6')) {
  const lic = read('LICENSE');
  const which = /MIT License|Permission is hereby granted, free of charge/i.test(lic) ? 'MIT'
    : /Apache License[\s\S]*Version 2\.0/i.test(lic) ? 'Apache-2.0' : '';
  say('C6', 'license-file', 1, lic ? (which ? `识别为 ${which}` : '内容不像 MIT/Apache-2.0') : 'LICENSE 不存在', which ? 'PASS' : 'FAIL');
}
// ---- C7 文档风格红线（射程：交付文档，不含 report/log 与 build/evidence 过程件）
if (want('C7')) {
  const docs = tracked.filter(f => f.endsWith('.md') && !f.startsWith('report/log/') && !f.startsWith('build/evidence/') && !f.startsWith('docs/walkthrough'));
  const I_RE = /我们|本文档|本节将?介绍|希望对您|(^|[、，。；：\s])我[要想将在认为觉建]/;
  const SOFT_RE = /显著|极大地|完美|优秀|强大|TBD|待补充|【填入】|待验证/;
  const ARROW_RE = /→/g;   // 叙述连接符，只报数
  const EMOJI_RE = /[\u{1F300}-\u{1FAFF}\u{2600}-\u{26FF}]/u;
  const checks = { person: [], soft: [], emoji: [], cross: [], arrow: [] }, scanned = docs.length;
  const CROSS_RE = /[✓✗✔✘]/g;
  for (const f of docs) {
    const t = read(f);
    if (I_RE.test(t)) checks.person.push(f);
    if (SOFT_RE.test(t)) checks.soft.push(f);
    if (EMOJI_RE.test(t)) checks.emoji.push(f);
    if (CROSS_RE.test(t)) checks.cross.push(f);
    if (ARROW_RE.test(t)) checks.arrow.push(f);
  }
  // 严格项=赛题 §7 点名的东西；箭头只作叙述连接符，不承载"用符号代替文字"的问题 ⇒ 报数不判红
  const ARROW_N = checks.arrow.length;
  const bad = checks.person.length + checks.soft.length + checks.emoji.length + checks.cross.length;
  say('C7', 'style-red-lines', scanned, `交付文档=${scanned} 人称=${checks.person.length} 程度副词或TBD=${checks.soft.length} emoji=${checks.emoji.length} 勾叉=${checks.cross.length} 箭头(只报数)=${ARROW_N} 例:${[...checks.person, ...checks.soft, ...checks.cross].slice(0, 4).join(',')}`, scanned === 0 ? 'NOT_MEASURED' : (bad ? 'FAIL' : 'PASS'));
}
// ---- C8 汇总（清单自检的机械版）
for (const r of rows) console.log(r);
const red = rows.filter(r => / FAIL$/.test(r)).length, nm = rows.filter(r => / NOT_MEASURED$/.test(r)).length;
console.log(`DELIVER-SPEC 判 ${rows.length} 项 跟踪文件=${tracked.length} 红=${red} 未测=${nm} ${red ? 'FAIL' : (nm ? 'NOT_MEASURED' : 'PASS')}`);
process.exit(red ? 1 : 0);
