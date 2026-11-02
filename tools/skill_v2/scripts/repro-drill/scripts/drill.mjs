#!/usr/bin/env node
// drill.mjs —— 复现演练：文档点名的相对路径是否真在盘上（只读检查，绝不写被检查的树）。
//
//   node scripts/drill.mjs --dir <文档根目录>
//   node scripts/drill.mjs --self
//
// 射程由遍历现算（不手写文件清单）；死引用 > 0 ⇒ exit 1；扫到 0 个文件 ⇒ NOT_MEASURED 且 exit 1。
// 代码块里的命令行只抽取、只报数，本工具不执行任何东西。只用 Node 标准库。
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ENTRY = path.resolve(HERE, '..');
const SELF = path.join(ENTRY, 'fixtures', 'docs');
const MD_EXT = ['.md', '.markdown', '.mdown'];
const SKIP_DIR = new Set(['node_modules', '.git', '.cache']);
const DECL = ['不随包', '未随包', '本地留档', '未写', '规划', '示例', '自备', '未提交'];
// 形如 dir/xxx.yyy 的相对路径（至少一段目录 + 一个扩展名）；URL 与版本号不会被吃进来
const REF_RE = /(?<![\w/.+-])(?:\.\.?\/)*(?:[\w+@.-]+\/)+[\w+@.-]*\.[A-Za-z][A-Za-z0-9]{0,7}(?![\w./-])/g;
const FENCE = /^\s*(?:```|~~~)/;
const CMD_RE = /^\s*(?:\$ )?(?:sudo\s+)?(?:node|npm|npx|pnpm|yarn|make|gmake|cmake|bash|sh|zsh|python3?|perl|git|gcc|g\+\+|cargo|dot|vivado|xvlog|xsim|openocd|st-?util|[^ ]*\.sh|[^ ]*\.mjs|[^ ]*\.py|\.\/[\w./-]+)(?:\s|$)/;
const WRITE_FLAGS = ['--fix', '--rewrite', '--delete', '--write', '--in-place'];

const digest = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
function walkMd(d, acc, skipped) {
  let ents;
  try { ents = fs.readdirSync(d, { withFileTypes: true }); } catch { return acc; }
  for (const e of ents.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0))) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) { if (SKIP_DIR.has(e.name) || e.name.startsWith('.')) { skipped.push(e.name); continue; } walkMd(p, acc, skipped); continue; }
    if (MD_EXT.includes(path.extname(e.name).toLowerCase())) acc.push(p);
  }
  return acc;
}
function resolveRef(root, fileDir, ref) {
  const cands = [path.resolve(fileDir, ref), path.resolve(root, ref)];
  for (const c of cands) { try { if (fs.statSync(c)) return { hit: c, mode: c === cands[0] ? '按文件位置' : '按扫描根' }; } catch { /* 不存在 */ } }
  return { hit: null, mode: '' };
}
function scan(root) {
  const skipped = [];
  const files = walkMd(root, [], skipped);
  const dead = [], live = [], exempt = [], cmds = [], outside = [];
  for (const f of files) {
    const rel = path.relative(root, f).replace(/\\/g, '/');
    const fileDir = path.dirname(f);
    const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
    let inCode = false;
    lines.forEach((line, i) => {
      const ln = i + 1;
      if (FENCE.test(line)) { inCode = !inCode; return; }
      const refs = [...line.matchAll(REF_RE)].map(m => m[0]);
      const decl = DECL.filter(w => line.includes(w));
      for (const ref of refs) {
        if (decl.length) { exempt.push({ rel, ln, ref, why: decl.join('/') }); continue; }
        const r = resolveRef(root, fileDir, ref);
        if (r.hit) live.push({ rel, ln, ref, via: r.mode });
        else {
          dead.push({ rel, ln, ref });
          if (ref.startsWith('..')) outside.push(ref);
        }
      }
      if (inCode && CMD_RE.test(line)) cmds.push({ rel, ln, text: line.trim() });
    });
  }
  return { root, files, dead, live, exempt, cmds, outside, skipped };
}
function report(s, quiet) {
  const out = [];
  out.push(`射程（遍历现算）根=${path.basename(s.root)} Markdown 文件=${s.files.length}${s.skipped.length ? ` 跳过目录=${s.skipped.length}` : ''}`);
  for (const f of s.files) out.push(`  计入 ${path.relative(s.root, f).replace(/\\/g, '/')}`);
  for (const d of s.dead) out.push(`死引用 ${d.rel}:${d.ln} ${d.ref}（盘上找不到）FAIL`);
  for (const e of s.exempt) out.push(`豁免 ${e.rel}:${e.ln} ${e.ref}（同行声明词：${e.why}）NOT_MEASURED`);
  for (const l of s.live) if (!quiet) out.push(`在盘 ${l.rel}:${l.ln} ${l.ref}（${l.via}）`);
  for (const c of s.cmds) out.push(`命令抽取 ${c.rel}:${c.ln} ${c.text} —— 未执行`);
  if (s.outside.length) out.push(`注：${s.outside.length} 条引用指向扫描根之外（本次只按盘上有没有判，不猜别处）`);
  out.push(`扫描文件数=${s.files.length} 抓到引用数=${s.dead.length + s.live.length + s.exempt.length} 豁免命中数=${s.exempt.length} 死引用数=${s.dead.length}`);
  out.push(`命令抽取数=${s.cmds.length}（只抽取、不执行 ⇒ 命令能否跑属于未测）`);
  const nm = s.exempt.length + s.cmds.length;
  const token = s.dead.length ? 'FAIL' : (s.files.length === 0 || nm ? 'NOT_MEASURED' : 'PASS');
  out.push(`判 ${s.dead.length + s.live.length + s.files.length} 项 红=${s.dead.length} 未测=${nm} ${token}`);
  for (const l of out) console.log(l);
  const exit = s.dead.length ? 1 : (s.files.length === 0 ? 1 : (nm ? 2 : 0));
  return { exit, token, nm };
}
function runScan(root, quiet) {
  if (!fs.existsSync(root) || !fs.statSync(root).isDirectory()) {
    console.log(`扫描根读不到：${root}（不猜路径、不退回当前目录）`);
    console.log('扫描文件数=0 抓到引用数=0 豁免命中数=0 死引用数=0');
    console.log('判 0 项 红=0 未测=1 NOT_MEASURED');
    return 1;
  }
  const s = scan(root);
  if (s.files.length === 0) {
    console.log(`扫描文件数=0 抓到引用数=0 豁免命中数=0 死引用数=0`);
    console.log(`射程为空（${path.basename(root)} 里没有 ${MD_EXT.join('/')}）⇒ NOT_MEASURED：没扫到不等于没有死引用`);
    console.log('判 0 项 红=0 未测=1 NOT_MEASURED');
    return 1;
  }
  return report(s, quiet).exit;
}

function selfTest() {
  const out = []; let cmp = 0, red = 0, nm = 0;
  const say = (id, detail, verdict, done) => { out.push(`${id} ${detail} ${verdict}`); cmp += done || 0; if (verdict === 'FAIL') red++; else if (verdict === 'NOT_MEASURED') nm++; };
  const me = fileURLToPath(import.meta.url);
  const num = (txt, re) => parseInt((txt.match(re) || [, '-1'])[1], 10);
  const guard = {};
  for (const f of walkMd(SELF, [], [])) guard[f.replace(/\\/g, '/')] = digest(f);
  const run = (args) => spawnSync(process.execPath, [me, ...args], { encoding: 'utf8' });
  const changed = () => {
    let n = 0;
    for (const [p, h] of Object.entries(guard)) { if (!fs.existsSync(p) || digest(p) !== h) n++; }
    for (const f of walkMd(SELF, [], [])) if (!Object.keys(guard).includes(f.replace(/\\/g, '/'))) n++;
    return n;
  };

  // S1 死引用必须抓到且点名，退出码 1
  const d = run(['--dir', SELF]);
  const dTxt = d.stdout + d.stderr;
  const deadN = num(dTxt, /死引用数=(\d+)/), named = /死引用 runbook\.md:\d+ tools\/flash_host\.mjs/.test(dTxt);
  say('S1 死引用必须抓到并点名（夹具含 1 条）', `退出码=${d.status} 死引用数=${deadN} 点名=${named ? 'tools/flash_host.mjs' : '不符'}`,
    (d.status === 1 && deadN === 1 && named) ? 'PASS' : 'FAIL', 3);

  // S2 同行声明词豁免：夹具 4 条，且这 4 条没被算进死引用
  const exN = num(dTxt, /豁免命中数=(\d+)/), refsN = num(dTxt, /抓到引用数=(\d+)/);
  const exNames = ['tools/bit_gen.mjs', 'notes/appendix.md', 'notes/plan.md', 'notes/readings.csv'];
  const allEx = exNames.every(n => dTxt.split('\n').some(l => l.startsWith('豁免') && l.includes(n)));
  say('S2 同行声明词豁免（不随包/未写/规划）', `豁免命中数=${exN}/4 全部命中=${allEx ? '是' : '否'} 引用总数=${refsN}`,
    (exN === 4 && allEx && refsN === 10) ? 'PASS' : 'FAIL', 3);

  // S3 表格行：只统计不改写 —— 表格里的 notes/setup.md 被判在盘，且整棵夹具字节不变
  const tableRow = dTxt.split('\n').some(l => l.startsWith('在盘 runbook.md') && l.includes('notes/setup.md'));
  say('S3 表格行按引用统计（不改写、不当路径重排）', `表格/正文引用被判在盘=${tableRow ? '是' : '否'} 夹具文件改动=${changed()}`,
    (tableRow && changed() === 0) ? 'PASS' : 'FAIL', 2);

  // S4 只读：--fix 之类写盘请求必须被拒绝
  const fx = run(['--dir', SELF, '--fix']);
  const fxTxt = fx.stdout + fx.stderr;
  say('S4 写盘请求被拒绝（本工具只做只读检查）', `退出码=${fx.status} 说明=${/只读/.test(fxTxt) ? '含"只读"' : '缺失'}`,
    (fx.status === 1 && /只读/.test(fxTxt) && changed() === 0) ? 'PASS' : 'FAIL', 2);

  // S5 空目录 / 不存在的根 ⇒ NOT_MEASURED 且 exit 1（不许空转成绿）
  const e1 = run(['--dir', path.join(SELF, 'empty')]);
  const e2 = run(['--dir', path.join(SELF, 'no-such-dir')]);
  say('S5 射程为空 ⇒ NOT_MEASURED 且退出码 1', `空目录退出码=${e1.status} 缺目录退出码=${e2.status} 结论=${/NOT_MEASURED/.test(e1.stdout) ? '未测' : '不符'}`,
    (e1.status === 1 && e2.status === 1 && /NOT_MEASURED/.test(e1.stdout) && /扫描文件数=0/.test(e1.stdout)) ? 'PASS' : 'FAIL', 3);

  // S6 命令只抽取不执行：抽取数报出来、标"未执行"，且不参与判定
  const cN = num(dTxt, /命令抽取数=(\d+)/);
  const marked = dTxt.split('\n').filter(l => l.startsWith('命令抽取 ')).every(l => l.includes('未执行'));
  const markedN = dTxt.split('\n').filter(l => l.startsWith('命令抽取 ')).length;
  const silent = run(['--dir', SELF, '--quiet']);
  const sameVerdict = num(silent.stdout, /死引用数=(\d+)/) === deadN;
  say('S6 代码块命令只抽取、只报数、不执行', `抽取数=${cN}/3 逐条标注未执行=${marked ? markedN + '/3' : '否'} 判定不受影响=${sameVerdict ? '是' : '否'}`,
    (cN === 3 && marked && markedN === 3 && sameVerdict) ? 'PASS' : 'FAIL', 3);

  // S7 射程由遍历现算：临时造一棵更深的树，文件数必须跟着涨（证明没有手写清单）
  const T = fs.mkdtempSync(path.join(os.tmpdir(), 'drill-'));
  fs.mkdirSync(path.join(T, 'a', 'b', 'c'), { recursive: true });
  ['r.md', 'a/x.md', 'a/b/y.md', 'a/b/c/z.md'].forEach(n => fs.writeFileSync(path.join(T, n), '# 占位\n'));
  const t = run(['--dir', T]);
  const tN = num(t.stdout, /扫描文件数=(\d+)/);
  say('S7 射程由遍历现算（临时塞 4 个嵌套 md 必须全进射程）', `退出码=${t.status} 扫描文件数=${tN}`,
    (tN === 4 && t.status !== 1) ? 'PASS' : 'FAIL', 2);
  fs.rmSync(T, { recursive: true, force: true });

  const touched = changed();
  say('S8 全程只读（跑完 7 项后夹具字节不变）', `比对文件=${Object.keys(guard).length} 改动=${touched}`, touched === 0 ? 'PASS' : 'FAIL', Object.keys(guard).length);

  for (const l of out) console.log(l);
  const token = red ? 'FAIL' : (nm ? 'NOT_MEASURED' : 'PASS');
  console.log(`判 ${cmp} 项 红=${red} 未测=${nm} ${token}`);
  process.exit(red ? 1 : 0);
}

const argv = process.argv.slice(2);
const get = (k, d) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : d; };
if (argv.includes('--self')) selfTest();
else if (argv.some(a => WRITE_FLAGS.includes(a))) {
  console.log(`本工具只读：${WRITE_FLAGS.join(' / ')} 一律拒绝（绝不写被检查的树，也不替死引用编目标）`);
  console.log('判 1 项 红=1 未测=0 FAIL');
  process.exit(1);
} else if (argv.includes('--help') || argv.includes('-h')) {
  console.log('用法: node drill.mjs --dir <文档根目录> [--quiet] | node drill.mjs --self');
  console.log(`声明词（同行即豁免，判 NOT_MEASURED 不判通过）：${DECL.join(' / ')}`);
  console.log('退出码：0 干净 / 1 有死引用或射程为空 / 2 只有豁免与抽取项');
} else if (!argv.includes('--dir')) {
  console.log('缺 --dir：不猜要扫哪里');
  console.log('判 0 项 红=0 未测=1 NOT_MEASURED');
  process.exit(1);
} else {
  process.exit(runScan(path.resolve(get('--dir', '.')), argv.includes('--quiet')));
}
