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
  const allowDirs = new Set(['src', 'sim', 'build', 'board', 'data', 'skills', 'report', 'docs']);
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
// ---- C1-2 §1.2 源码归档位置：RTL 在 src/rtl，**PS 裸机固件在 src/ps（与 src/rtl 同级）**，
//      上位机/PC 侧工具在 src/host。顶层八目录之外的**子目录**不会被 C0-4 看到，所以这一条单独量。
// 口径换过一次：r122 那一轮按"PS 侧与上位机都在 src/host"判，固件因此被归档到 src/host/ps。
//      本轮按用户口径改回"PS 源与 rtl 同级 = src/ps"，上位机工具仍留在 src/host —— 两类源文件
//      按**扩展名**分家（固件=c/h/cpp/ld/S，PC 侧=py/mjs），不再一锅烩在"在不在 src/host"上。
// ⚠ 判据不许改成恒绿：`--c1-2-self` 那六条对照里必须有"固件放回 src/host/ps ⇒ 红"和
//      "src/ps 空了 ⇒ 红"两条，否则这一条只是把现在的成绩单抄了一遍。
const C12 = { RTL: 'src/rtl/', PS: 'src/ps/', HOST: 'src/host/', CON: 'src/constraints/' };
function c12Judge(files) {
  const srcAll = files.filter(f => f.startsWith('src/') && !f.startsWith('src/../'));
  const isRtlSrc = (f) => /\.(v|sv|vhd|vhdl)$/.test(f);
  const isFwSrc = (f) => /\.(c|cpp|cc|h|hpp|ld|S)$/.test(f);
  const isPcSrc = (f) => /\.(py|mjs)$/.test(f);
  const rtl = srcAll.filter(f => isRtlSrc(f) && f.startsWith(C12.RTL));
  const rtlOutside = srcAll.filter(f => isRtlSrc(f) && !f.startsWith(C12.RTL));
  const fw = srcAll.filter(f => isFwSrc(f) && !f.startsWith(C12.CON));
  const fwInPs = fw.filter(f => f.startsWith(C12.PS));
  const fwMisplaced = fw.filter(f => !f.startsWith(C12.PS));
  const pc = srcAll.filter(f => isPcSrc(f));
  const pcInHost = pc.filter(f => f.startsWith(C12.HOST));
  const pcMisplaced = pc.filter(f => !f.startsWith(C12.HOST));
  const p = [];
  if (rtlOutside.length) p.push(`RTL 不在 src/rtl=${rtlOutside.length}[${rtlOutside.slice(0, 3).join(',')}]`);
  if (fwMisplaced.length) p.push(`PS 固件源不在 src/ps=${fwMisplaced.length} 目录=${[...new Set(fwMisplaced.map(f => f.split('/')[1]))].join(',')} 例:${fwMisplaced.slice(0, 3).join(',')}`);
  // 这一条是"删掉了也算偏差"的那一档：不写成 `fw.length && !fwInPs.length`，因为固件源**整个被删**
  // 时 fw 也是 0，那样判据就悄悄恒绿了 —— 交付口径要求 src/ps 里必须有 PS 源，空目录就是不合格。
  if (!fwInPs.length) p.push(`src/ps 下一份固件源都没有（PS 归档缺失；src/ 里的固件源=${fw.length}，例:${fw.slice(0, 2).join(',') || '无'}）`);
  if (pcMisplaced.length) p.push(`上位机/PC 源不在 src/host=${pcMisplaced.length} 例:${pcMisplaced.slice(0, 3).join(',')}`);
  let verdict;
  if (!srcAll.length) verdict = 'NOT_MEASURED';        // 射程空 = 没量，不许当"没毛病"
  else verdict = p.length ? 'FAIL' : 'PASS';
  return {
    cmp: srcAll.length, p, verdict,
    detail: p.join('、')
      || `符合（RTL=${rtl.length} 在 src/rtl，PS 固件=${fwInPs.length} 在 src/ps 与 rtl 同级，上位机/PC=${pcInHost.length} 在 src/host）`,
  };
}
if (want('C1-2')) {
  const g = c12Judge(tracked);
  say('C1-2', 'src-placement-per-1.2', g.cmp, g.detail, g.verdict);
}
// ---- C1-2 自己的对照：判据必须**能红**，否则"换了口径"等于"改了成绩单"
//      （本轮口径从"PS 在 src/host"换成"PS 在 src/ps 与 rtl 同级"，没有这六条就分不清
//        是真的按新口径判、还是把现在的成绩抄了一遍。跑法：node build/deliver_spec_check.mjs --c1-2-self）
if (process.argv.includes('--c1-2-self')) {
  // 夹具里的假路径**由常量拼出来**，不写成 `src/host/ps/main.c` 这种字面量：
  // C-PATHS 判的就是脚本里的 `src/**` 字面量必须在盘上存在，写死会让这条判据自己红在夹具上；
  // 而把它塞进 SKIP_RE 或 CASE_LINE 去豁免，等于拿豁免通道盖住一条真指路（rule 44 反买通禁止的形状）。
  const OLD_PS = C12.HOST + 'ps/';                       // r122 那一版固件的位置 = 本轮要判红的形状
  const RTL = ['src/rtl/top/pl_video_top.v', 'src/rtl/eth/icmp_tx.v'];
  const FW = [C12.PS + 'main.c', C12.PS + 'sd_play.c', C12.PS + 'sd_play.h', C12.PS + 'lscript_ocm.ld'];
  const PC = ['src/host/video_sender.mjs', 'src/host/udp_push.py', 'src/host/README.md'];
  const cases = [
    ['正对照：本轮口径（RTL 在 src/rtl + 固件在 src/ps + PC 在 src/host）', RTL.concat(FW, PC), 'PASS'],
    ['能红①：固件放回 host/ps（r122 那一版的位置）', RTL.concat(
      [OLD_PS + 'main.c', OLD_PS + 'sd_play.c', OLD_PS + 'lscript_ocm.ld'], PC), 'FAIL'],
    ['能红②：固件整个被删（src/ps 空了）——不许滑成绿，也不许躲进 NOT_MEASURED', RTL.concat(PC), 'FAIL'],
    ['能红③：PC 侧工具漂进 ps/', RTL.concat(FW, [C12.PS + 'video_sender.mjs'])
      .filter(f => f !== 'src/host/video_sender.mjs'), 'FAIL'],
    ['能红④：RTL 漂进 ps/（证明 src/ps 不是"什么源都能放"）', [C12.PS + 'top.v'].concat(FW, PC), 'FAIL'],
    ['射程空：src/ 下一个文件都没跟踪 ⇒ NOT_MEASURED，不能当"没毛病"', ['README.md', 'build/x.sh'], 'NOT_MEASURED'],
  ];
  let r = 0;
  for (const [why, fs_, wantV] of cases) {
    const g = c12Judge(fs_);
    const ok = g.verdict === wantV;
    if (!ok) r++;
    console.log(`C12-SELF ${ok ? 'PASS' : 'FAIL'} ${why} ⇒ 判 ${g.verdict}（要 ${wantV}）${g.verdict === 'FAIL' ? ' 理由:' + g.p.join('、').slice(0, 110) : ''}`);
  }
  console.log(`C12-SELF 判 ${cases.length} 项 红=${r} ${r ? 'FAIL' : 'PASS'}`);
  process.exit(r ? 1 : 0);
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
// ---- C-PATHS §6.2「路径与仓库实际一致」的机械版：脚本里指向源码目录的输入路径必须在盘上
// 只判 `src/` 开头的字面量：build/ data/ 下大量路径是脚本**自己要产出的件**，
// 用"必须已存在"去判它们会淹死在假红里（本轮实测：全目录形状数到 258 条读不到，
// 逐条看几乎全是 `build/frozen_rNN_`、`src/dst` 这类模板串与夹具名）。
// 模板串（含 NN $ < > * % {）不计并打印条数；一条都没判到 ⇒ NOT_MEASURED，不许当"没毛病"。
if (want('C-PATHS')) {
  // 自检/探针/改口器的正文里**必须**写着不存在的假路径（那是它们的用例），按形状豁免并念出条数；
  // 豁免名单住在尺子里且打印命中数，防止被随手扩大（rule 44 的反买通同族）。
  const SKIP_RE = /selftest|probe|fix_dangling|ps_relocate|orphan_rtl|ports_dup_ce|repin_modules|rtl_fingerprint|check_repo_consistency/;
  const scripts = tracked.filter(f => /\.(py|mjs|sh|tcl|bat|cmd|ps1)$/.test(f)
    && !/^build\/(evidence|frozen_|report|runs)/.test(f) && !/\/(fixtures?|expected)\//.test(f)
    && !f.startsWith('report/log/'));
  const judged = scripts.filter(f => !SKIP_RE.test(path.basename(f)));
  const exempt = scripts.length - judged.length;
  const LIT = /(?:\.\.\/)*(?:src|sim|build|data|skills|board|report)\/[\w.\-\/]*\.(?:v|sv|md|csv|txt|py|mjs|sh|tcl|bat|cmd|ps1|xdc|xci|json|rpt|html|png|mem|ld|h|c|elf|bit|xsa|out|mm|xva)/g;
  // 行级豁免（按形状，不按名单）：注释行与"用例/断言"行里的路径是**被讨论的对象**，不是这脚本要读的文件。
  const CASE_LINE = /(^\s*(\/\/|#|\*|---|<!--))|===|!==|\bassert\b|用例|SELF|vendorBuyoff|expect/;
  const bad = []; let tpl = 0, n = 0, caseSkipped = 0;
  for (const f of judged) {
    const lines = read(f).split(/\r?\n/);
    for (const l of lines) {
      const ms = l.match(LIT) || [];
      if (!ms.length) continue;
      if (CASE_LINE.test(l)) { caseSkipped += ms.length; continue; }
      for (const m of ms) {
        if (/NN|\$|<|>|\*|%|\{/.test(m)) { tpl++; continue; }
        if (!/^(?:\.\.\/)*src\//.test(m)) continue;
        n++;
        const cands = [path.resolve(ROOT, path.dirname(f), m), path.resolve(ROOT, m)];
        if (!cands.some(p => fs.existsSync(p))) bad.push(`${m}  <- ${f}`);
      }
    }
  }
  say('C-PATHS', 'script-src-paths-resolve', n,
    `脚本=${judged.length} 判(指向 src/ 的字面量)=${n} 解析不到=${bad.length} 模板串不计=${tpl} 用例与注释行不计=${caseSkipped} 自检探针类文件不计=${exempt} 例:${bad.slice(0, 3).join(' | ')}`,
    n === 0 ? 'NOT_MEASURED' : (bad.length ? 'FAIL' : 'PASS'));
}
// ---- C-LEN §7.6 长度上限：根 README 一页（C3 里判），子 README 半页。
// "半页"落在**作者写的散文行**上：§2.4 要的是 81 行的台架表、§0.4 要的是目录表，
// 那些是被条款强制要求的表格/代码，把它们算进长度就变成"两条条款互相打架"，
// 于是判据只数表外散文行，表格行数另印出来（能看见长度是从哪儿来的）。
if (want('C-LEN')) {
  // 射程现算（手写名单会随树长大静默变窄）：除根以外所有目录级 README
  const present = tracked.filter(f => /(^|\/)README(_EN)?\.md$/.test(f) && f.includes('/'));
  const proseLines = (t) => {
    let fence = false; const out = [];
    for (const l of t.split(/\r?\n/)) {
      if (/^\s*```/.test(l)) { fence = !fence; continue; }
      if (fence) continue;
      if (/^\s*\|/.test(l)) continue;             // 表格行
      if (/^\s{4,}\S/.test(l)) continue;           // 缩进代码
      if (!l.trim()) continue;
      out.push(l);
    }
    return out;
  };
  const CAP = Number(process.env.VP_CLEN_CAP || 45);
  const DEEP = Number(process.env.VP_CLEN_DEEP || 160);
  const over = []; let tableRows = 0, cmp = 0, guides = 0, chapters = 0;
  for (const f of present) {
    const t = read(f), ls = t.split(/\r?\n/);
    const p = proseLines(t), tb = ls.filter(l => /^\s*\|/.test(l)).length;
    // 两档（自己记过的规矩：条款之间打架时按"它保护什么"拆硬门与建议，不做一次mass-edit）：
    //   `<目录>/README.md` = 目录导览，§7.6 的"半页"就是给它的 ⇒ 硬门 CAP；
    //   再往下的 README = §5.4 点名要的章节正文（复现说明、协作记录…），
    //   给一个宽得多的地板 DEEP，超了照样红，但不逼把命令逐字抄写成表格外的短句。
    const isGuide = f.split('/').length === 2;
    const cap = isGuide ? CAP : DEEP;
    cmp += 2; tableRows += tb; isGuide ? guides++ : chapters++;
    if (p.length > cap) over.push(`${f} 散文=${p.length}（${isGuide ? '导览' : '章节'}上限 ${cap}，表格 ${tb} 行不计）`);
  }
  say('C-LEN', 'sub-readme-length', cmp,
    `子 README=${present.length}（导览 ${guides} 上限 ${CAP}／章节 ${chapters} 上限 ${DEEP}）超=(${over.join(' ; ') || '无'}) 表格行合计=${tableRows}（§2.4/§0.4 强制的表不算长度）`,
    present.length === 0 ? 'NOT_MEASURED' : (over.length ? 'FAIL' : 'PASS'));
  if (process.argv.includes('--len-list')) for (const f of present) console.log(`  ${f} 散文=${proseLines(read(f)).length} 总行=${read(f).split(/\r?\n/).length}`);
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
// ---- C4b §4.4/§4.5 的**内容**判据：归档件里要真有条目，且件与脚本一一对应
// C4 只看 `build/report/` 里有没有"名字带 util/timing 的件"，那判的是文件名不是内容：
// 一份只写了"见附件"的空报告也能过。这里按工具原始输出的**行标签**逐项数（标签是从
// 盘上真件里 grep 出来的，不是照文档猜的），并要求每份报告都能在一支脚本里被重出。
if (want('C4b')) {
  const dir = 'build/report';
  const rep = tracked.filter(f => f.startsWith(dir + '/'));
  const util = read(dir + '/utilization.rpt'), tim = read(dir + '/timing_summary.rpt');
  const RES = [['LUT', /LUT as Logic/], ['FF', /Register as Flip Flop|Slice Registers/], ['BRAM', /Block RAM Tile/], ['DSP', /\| *DSPs/], ['IO', /Bonded IOB/]];
  const TIM = [['WNS', /WNS\(ns\)/], ['TNS', /TNS\(ns\)/], ['频率', /Frequency\(MHz\)/], ['未收敛路径表', /Clock +WNS\(ns\)|Path Group +From Clock/]];
  const missRes = RES.filter(([, re]) => !re.test(util)).map(([n]) => n);
  const missTim = TIM.filter(([, re]) => !re.test(tim)).map(([n]) => n);
  const raw = rep.filter(f => /Vivado v\./.test(read(f)));
  // 每份报告由谁重出：脚本正文里必须点名该文件名（§4.5「脚本与报告一一对应」）
  const emitter = read('build/report.tcl');
  const orphan = rep.filter(f => !emitter.includes(path.basename(f)));
  const p = [];
  if (!rep.length) p.push('build/report/ 空');
  if (rep.length && !util) p.push('缺 utilization.rpt');
  if (util && missRes.length) p.push(`资源行缺:${missRes.join(',')}`);
  if (rep.length && !tim) p.push('缺 timing_summary.rpt');
  if (tim && missTim.length) p.push(`时序行缺:${missTim.join(',')}`);
  if (rep.length && raw.length < 2) p.push(`带工具版本横幅的原始件只 ${raw.length} 份（要 ≥2，否则像手抄的数）`);
  if (emitter && orphan.length) p.push(`没有脚本能重出的报告=${orphan.length}[${orphan.map(f => path.basename(f)).join(',')}]`);
  if (!emitter) p.push('读不到 build/report.tcl ⇒ 对应关系判不了');
  say('C4b', 'report-contents-and-script-map', RES.length + TIM.length + 2 + rep.length,
    p.join('、') || `符合（归档件=${rep.length} 资源行 5/5 时序行 4/4 原始件横幅=${raw.length}/${rep.length} 每份都有脚本能重出）`,
    (rep.length === 0 || !util || !tim || !emitter) ? 'NOT_MEASURED' : (p.length ? 'FAIL' : 'PASS'));
}
// ---- C5 四类目录齐 + skills/README 四要素 + report 章节齐
if (want('C5')) {
  const need = ['board', 'data', 'skills', 'report'];
  const empty = need.filter(d => !tracked.some(f => f.startsWith(d + '/')));
  const renamed = tracked.some(f => f.startsWith('skills/')) && !tracked.some(f => f.startsWith('skills/')) ? 'skills 现为 skill 需改名' : '';
  const sreadme = read('skills/README.md') || read('skills/README.md');
  // §5.3 点名的四个词按**字面**判：同义词放行等于这把尺子量不到（第一版写的
  // `/适用场景|scope/`、`/效果/i` 之类让 skills/README.md 一个"适用范围"都没有也报绿）。
  const four = [['适用范围', /适用范围/], ['使用方法', /使用方法/], ['失效条件', /失效条件/], ['已验证的复用结果', /已验证的复用结果|已验证复用结果/]];
  const missFour = four.filter(([, re]) => !re.test(sreadme)).map(([n]) => n);
  const rneed = [['选题背景与创新点', /背景|创新/], ['设计原理与功能框图', /原理|框图/], ['软硬件划分与接口设计', /划分|接口/], ['优化前后性能与资源对比', /对比|优化/], ['失败分析', /失败/], ['复现说明', /复现/], ['大模型协作记录', /协作|提示词|模型/]];
  const rtxt = tracked.filter(f => f.startsWith('report/') && f.endsWith('.md')).map(read).join('\n');
  const missRep = rneed.filter(([, re]) => !re.test(rtxt)).map(([n]) => n);
  // §5.4 的四件"具体内容"按**结构**判，不按关键词：关键词只要出现过就算齐，等于没判
  // （C5 的四要素那一半刚犯过同一种错）。这里要的是：能看见的数字对比表、带读数的失败分析、
  //  三段齐的协作记录（提示词 / 模型回答 / 自我纠错）。
  const md = tracked.filter(f => f.startsWith('report/') && f.endsWith('.md'));
  let cmpTables = 0, failRows = 0;
  for (const f of md) {
    const t = read(f), ls = t.split(/\r?\n/);
    for (let i = 0; i + 1 < ls.length; i++) {
      const isRow = (s) => /^\s*\|/.test(s) && (s.match(/\|/g) || []).length >= 3;
      if (!isRow(ls[i]) || !isRow(ls[i + 1])) continue;
      const hdr = ls[i], sep = ls[i + 1];
      if (!/[前后]|基线|改前|改后/.test(hdr + ls[i + 2] + ls[i + 3] || '')) continue;
      const nums = (hdr + ls[i + 2] + ls[i + 3]).match(/\d+(\.\d+)?\s*(%|ns|ms|µs|LUT|FF|BRAM|fps|MB|Mbps|字|行|包)/g) || [];
      if (nums.length >= 2) { cmpTables++; break; }
    }
    if (/^[-*|]?\s*(否决|REFUSE|失败|FAIL)/m.test(t) && /\d/.test(t)) failRows++;
  }
  const collab = tracked.filter(f => f.startsWith('report/collaboration/'));
  const ct = collab.map(read).join('\n');
  const tri = [['提示词', /提示词|prompt/i], ['模型回答', /回答|原话|输出|response/], ['自我纠错', /纠错|更正|改口|撤回|retract/i]];
  const missTri = tri.filter(([, re]) => !re.test(ct)).map(([n]) => n);
  const p = [...empty.map(d => d + ' 空'), ...(renamed ? [renamed] : []), ...(missFour.length ? ['skills/README 缺:' + missFour.join(',')] : []),
    ...(missRep.length ? ['report 缺章节:' + missRep.join(',')] : []),
    ...(cmpTables < Number(process.env.VP_C5_TABLES || 30) ? [`带单位数字的前后对比表只数到 ${cmpTables} 张（地板 ${process.env.VP_C5_TABLES || 30}，§5.4 要求优化前后对比）`] : []),
    ...(failRows < Number(process.env.VP_C5_FAILS || 8) ? [`带读数的失败/否决条目只数到 ${failRows} 份（地板 ${process.env.VP_C5_FAILS || 8}，§5.4 要求失败分析）`] : []),
    ...(collab.length < Number(process.env.VP_C5_COLLAB || 9) ? [`协作记录文件只有 ${collab.length} 份（地板 ${process.env.VP_C5_COLLAB || 9}）`] : []),
    ...(missTri.length ? ['协作记录缺三段:' + missTri.join(',')] : [])];
  say('C5', 'dirs-skills-readme-report', need.length + four.length + rneed.length + 4,
    p.join('、') || `符合（对比表 ${cmpTables} 张／含失败读数 ${failRows} 份／协作记录 ${collab.length} 份三段齐）`,
    p.length ? 'FAIL' : 'PASS');
}
// ---- C6 开源协议
if (want('C6')) {
  const lic = read('LICENSE');
  const which = /MIT License|Permission is hereby granted, free of charge/i.test(lic) ? 'MIT'
    : /Apache License[\s\S]*Version 2\.0/i.test(lic) ? 'Apache-2.0' : '';
  say('C6', 'license-file', 1, lic ? (which ? `识别为 ${which}` : '内容不像 MIT/Apache-2.0') : 'LICENSE 不存在', which ? 'PASS' : 'FAIL');
}
// ---- C7 文档风格红线（射程：交付文档，不含 report/log 与 build/evidence 过程件）
// 拆"使用"与"提及"（#352）：§7.1/§7.2/§7.5 禁的是**把禁用词当成自己的话写出来**，
// 不是禁文档引用它。判据只看落在"作者声音"里的命中；被引用/被点名/被抄成命令的走"只报数"。
// 豁免是**形状**而不是文件名名单：围栏代码块、行内码、引号内、引用行（`>` 开头）、
// 以及"第 2 格就是那个标记本身"的清单行（那种行的主题就是那个词）。emoji 与勾叉不豁免。
const QUOTE_RE = /"[^"\n]*"|“[^”]*”|「[^」]*」|『[^』]*』/g;
const MARKER = 'TBD|待补充|【[^】]*】|待验证|未实测|未核实';
const CELL_MARKER = new RegExp('^(?:`)?(?:' + MARKER + ')');
// 跨行引号：赛题条文抄下来会换行（"…可测量的性能表现，并给出与基线的对比""合理使用…显著…"），
// 所以引号的开合必须带状态；第一版只按单行配对，把 4 处抄文判成了"作者自己的话"。
function splitVoice(t) {
  const voice = []; let mention = '', fence = false, inq = false;
  for (const l of t.split(/\r?\n/)) {
    if (/^\s*```/.test(l)) { fence = !fence; mention += l + '\n'; continue; }
    if (fence || /^\s*>/.test(l)) { mention += l + '\n'; continue; }              // 代码块/引用行=被引原文
    if (l.startsWith('|') && l.split('|').some(c => CELL_MARKER.test(c.trim()))) { mention += l + '\n'; continue; }  // 清单行
    let s = l;
    if (inq) {
      const close = s.search(/["”]/);
      if (close < 0) { mention += s + '\n'; continue; }
      mention += s.slice(0, close + 1) + '\n'; s = s.slice(close + 1); inq = false;
    }
    s = s.replace(QUOTE_RE, m => { mention += m + '\n'; return ' '; });            // 同行成对引号=引用
    if ((s.match(/["“]/g) || []).length % 2 === 1) { inq = true; mention += s + '\n'; continue; }  // 开了没关
    voice.push(s.replace(/`[^`\n]*`/g, m => { mention += m + '\n'; return ' '; }));  // 行内码=命令/路径
  }
  return { voice: voice.join('\n'), mention };
}
function c7Judge(docs, read) {
  const I_RE = /我们|本文档|本节将?介绍|希望对您|(^|[、，。；：\s])我[要想将在认为觉建]/;
  const SOFT_RE = /显著|极大地|完美|优秀|强大|TBD|待补充|【填入】|待验证/;
  const ARROW_RE = /→/g;
  const EMOJI_RE = /[\u{1F300}-\u{1FAFF}\u{2600}-\u{26FF}]/u;
  const CROSS_RE = /[✓✗✔✘]/g;
  const bad = { person: [], soft: [] }, sym = [], mentions = { person: 0, soft: 0 };
  let arrows = 0, scanned = 0;
  for (const f of docs) {
    const t = read(f); scanned++;
    const v = splitVoice(t).voice, m = splitVoice(t).mention;
    if (I_RE.test(v)) bad.person.push(f); else if (I_RE.test(m)) mentions.person++;
    if (SOFT_RE.test(v)) bad.soft.push(f); else if (SOFT_RE.test(m)) mentions.soft++;
    if (EMOJI_RE.test(t) || CROSS_RE.test(t)) sym.push(f);
    arrows += (t.match(ARROW_RE) || []).length;
  }
  return { bad, sym, mentions, arrows, scanned };
}
if (process.argv.includes('--c7-self')) {
  const cases = [
    ['正文里写 结果【待验证】', 'soft', true, '占位符当自己的话用 ⇒ 必须红'],
    ['表里写 `【待验证】` 这个标记', 'soft', false, '行内码里点名这个词 ⇒ 提及，不红'],
    ['赛题说"避免以显著的资源代价"', 'soft', false, '引号里的原文 ⇒ 提及，不红'],
    ['> 07:5x 我要往 issues.md 追加', 'person', false, '引用行里的队员原话 ⇒ 提及，不红'],
    ['| 271 | 【填入】 | `a.md` 行 1 | 我们手写的 |', 'soft', false, '清单行第 2 格就是标记 ⇒ 提及，不红'],
    ['结果还没量，见 报告', 'person', false, '正对照：无人称的一句 ⇒ 必须绿'],
    ['这一格 显著 变大了', 'soft', true, '裸写的程度副词 ⇒ 必须红'],
    ['命令 `bash ⚠ run.sh`', 'sym', true, 'emoji 不随豁免走 ⇒ 必须红'],
    ['对应赛题 3.3.4"可测量的性能表现，并给出与基线的对比""合理使用片上资源，避免以\n显著的资源代价换取有限的性能收益"与 3.3.5.3。', 'soft', false, '跨行引号：第二行的"显著"还在引用里 ⇒ 不红'],
    ['3.3.4 要求"可测量的表现"，而这一格显著变大是本轮自己的话。', 'soft', true, '正对照：引号外的"显著"照样红（豁免没把整把尺子买通）'],
    ['| 索引由目录生成 | `node x.mjs --check` | 不一致 exit 1 | 待验证（等条目到位跑一次） |', 'soft', false, '表里某一整格就是状态标记 ⇒ 只报数'],
    ['| 结论 | 这一条待验证（写在句子中间） |', 'soft', true, '标记夹在句子里当占位符 ⇒ 必须红'],
  ];
  let r = 0;
  for (const [src, kind, want, why] of cases) {
    const g = c7Judge(['x'], () => src);
    const got = kind === 'sym' ? g.sym.length > 0 : (kind === 'person' ? g.bad.person.length > 0 : g.bad.soft.length > 0);
    const ok = got === want;
    if (!ok) r++;
    console.log(`C7-SELF ${ok ? 'PASS' : 'FAIL'} ${why}（判得 ${got ? '红' : '绿'}，要 ${want ? '红' : '绿'}）`);
  }
  console.log(`C7-SELF 判 ${cases.length} 项 红=${r} ${r ? 'FAIL' : 'PASS'}`);
  process.exit(r ? 1 : 0);
}
if (want('C7')) {
  const docs = tracked.filter(f => f.endsWith('.md') && !f.startsWith('report/log/') && !f.startsWith('build/evidence/') && !f.startsWith('docs/walkthrough'));
  const g = c7Judge(docs, read);
  const n = g.bad.person.length + g.bad.soft.length + g.sym.length;
  say('C7', 'style-red-lines', docs.length,
    `交付文档=${g.scanned} 使用:人称=${g.bad.person.length} 程度副词或TBD=${g.bad.soft.length} emoji或勾叉=${g.sym.length}`
    + ` 提及(只报数):人称文件=${g.mentions.person} 标记文件=${g.mentions.soft} 箭头=${g.arrows}`
    + ` 例:${[...g.bad.person, ...g.bad.soft, ...g.sym].slice(0, 4).join(',')}`,
    g.scanned === 0 ? 'NOT_MEASURED' : (n ? 'FAIL' : 'PASS'));
}
// ---- C8 汇总（清单自检的机械版）
for (const r of rows) console.log(r);
const red = rows.filter(r => / FAIL$/.test(r)).length, nm = rows.filter(r => / NOT_MEASURED$/.test(r)).length;
console.log(`DELIVER-SPEC 判 ${rows.length} 项 跟踪文件=${tracked.length} 红=${red} 未测=${nm} ${red ? 'FAIL' : (nm ? 'NOT_MEASURED' : 'PASS')}`);
process.exit(red ? 1 : 0);
