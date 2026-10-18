#!/usr/bin/env node
// collect.mjs —— 从文本报告里抓"指标名 + 数值 + 单位"，产出一张 CSV + 一份 Markdown 表
// 依赖：只有 Node 标准库。无本机绝对路径常量、无工程/器件/板卡/工具名绑定 ——
//       被读的就是普通文本文件，抓取规则是一张可替换的指标名册（--spec 可自带）。
//
// 判定纪律：每条判据一行，最后一个字段是 PASS / FAIL / NOT_MEASURED；结论行 `判 N 项 … <token>`，
// N = 做了多少次比较；抓不到的一律 NOT_MEASURED 落进 CSV（不留空、不编）；有 FAIL ⇒ 退出码 1。
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ENTRY = path.resolve(HERE, '..');
const FIXDIR = path.join(ENTRY, 'fixtures');
const NM = 'NOT_MEASURED';
const VERDICTS = new Set(['PASS', 'FAIL', NM]);

// 指标名册：metric=显示名，cls=报告类别，probe=找候选行的锚（只用于探针，不用于取值），
// re=取值+单位（第 1 组=值，第 2 组=单位），required=是否"一次都没命中就判红"。
// 取值锚一律写成 `标签 [^=\n]* [=:] \s* 数值`：数值必须紧跟在赋值号后面。
// 不要写成 `标签[^\d\n]*?数值`（跳着找下一个数）—— 报告里常带 "(可用 N, x%)" 这种尾巴，
// 一旦主数值换了写法，宽松锚会静默抓到括号里的可用量，抓到数不降、也不报红（夹具上实测到过）。
const DEFAULT_SPEC = [
  { metric: 'LUT 占用', cls: '资源', probe: 'LUT', re: 'LUT[^=\\n]*[=:]\\s*([0-9][0-9,.]*)\\s*(cells?|个|片|)', required: true },
  { metric: '触发器占用', cls: '资源', probe: '触发器', re: '触发器[^=\\n]*[=:]\\s*([0-9][0-9,.]*)\\s*(cells?|个|片|)', required: true },
  { metric: 'BRAM 占用', cls: '资源', probe: 'BRAM', re: 'BRAM[^=\\n]*[=:]\\s*([0-9][0-9,.]*)\\s*(tiles?|块|个|)', required: true },
  { metric: 'DSP 占用', cls: '资源', probe: 'DSP', re: 'DSP[^=\\n]*[=:]\\s*([0-9][0-9,.]*)\\s*(tiles?|块|个|)', required: true },
  { metric: '时钟网络缓冲数', cls: '资源', probe: '时钟网络缓冲', re: '时钟网络缓冲[^=\\n]*[=:]\\s*([0-9][0-9,.]*)\\s*(buffers?|个|)', required: true },
  { metric: '最坏建立余量', cls: '时序', probe: 'WNS', re: 'WNS\\s*[=:]\\s*([+-]?[0-9][0-9,.]*)\\s*(ps|ns|us|ms|s)?', required: true },
  { metric: '最坏保持余量', cls: '时序', probe: 'WhS', re: 'WhS\\s*[=:]\\s*([+-]?[0-9][0-9,.]*)\\s*(ps|ns|us|ms|s)?', required: true },
  { metric: '主时钟频率', cls: '时序', probe: '频率', re: '频率\\s*[=:]\\s*([+-]?[0-9][0-9,.]*)\\s*(Hz|kHz|MHz|GHz)', required: true },
  { metric: '最深逻辑级数', cls: '时序', probe: '逻辑级', re: '逻辑级\\s*[=:]\\s*([+-]?[0-9][0-9,.]*)\\s*(levels?|级)?', required: true },
  { metric: '未约束端点数', cls: '时序', probe: '未约束端点', re: '未约束端点\\s*[=:]\\s*([+-]?[0-9][0-9,.]*)\\s*(endpoints?|pins?|个)?', required: true },
  { metric: '帧计数', cls: '台架', probe: '帧计数', re: '帧计数[^=\\n]*[=:]\\s*([0-9][0-9,.]*)\\s*(frames?|帧|)', required: true },
  { metric: '丢帧数', cls: '台架', probe: '丢帧', re: '丢帧[^=\\n]*[=:]\\s*([0-9][0-9,.]*)\\s*(frames?|帧|)', required: true },
  { metric: '校验错误数', cls: '台架', probe: '校验错误', re: '校验错误[^=\\n]*[=:]\\s*([0-9][0-9,.]*)\\s*(errors?|errs?|个|)', required: true },
  { metric: '寄存器回读数', cls: '台架', probe: '寄存器回读', re: '寄存器回读[^=\\n]*[=:]\\s*([0-9][0-9,.]*)\\s*(regs?|个|)', required: true },
  { metric: '结温读数', cls: '台架', probe: '温度', re: '温度[^=\\n]*[=:]\\s*([0-9][0-9,.]*)\\s*(C|degC|℃|K)', required: false },
];

const USAGE = [
  '用法: node collect.mjs <报告目录> [--out metrics.csv] [--report metrics.md] [--spec <file>] [--self]',
  '',
  '  <报告目录>       递归扫描其下的文本报告（跳过空文件、二进制、4 MB 以上、自己产出的 metrics.*）',
  '  --out <file>     CSV 落点，列 = 指标,值,单位,来源件,抓取时间；缺省 metrics.csv',
  '  --report <file>  Markdown 表落点；缺省 metrics.md',
  '  --spec <file>    自带指标名册（JSON 数组，字段 metric/cls/probe/re/required），替换缺省名册',
  '  --self           在临时目录跑夹具并断言读数（含"改一个数就少抓一个"的能红对照）',
  '',
  '退出码：有 FAIL ⇒ 1；其余 ⇒ 0。退出码 0 不等于通过 —— 只认每行最后一个字段的判定词。',
].join('\n');

const SKIP = /(^|[\\/])(node_modules|\.git|fixtures|_out)([\\/]|$)/;
const cell = (v) => (/[",\n]/.test(String(v)) ? `"${String(v).replace(/"/g, '""')}"` : String(v));

function listReports(dir) {
  const out = [];
  (function walk(d) {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) { if (!SKIP.test(p)) walk(p); continue; }
      if (!e.isFile()) continue;
      if (/^metrics\.(csv|md)$/.test(e.name)) continue;
      const sz = fs.statSync(p).size;
      if (sz === 0 || sz > 4 * 1024 * 1024) continue;
      const buf = fs.readFileSync(p);
      if (buf.includes(0)) continue;
      out.push({ rel: path.relative(dir, p).replace(/\\/g, '/'), text: buf.toString('utf8').replace(/\r\n/g, '\n') });
    }
  })(dir);
  return out.sort((a, b) => a.rel.localeCompare(b.rel));
}

function loadSpec(file) {
  if (!file) return { spec: DEFAULT_SPEC, src: '内置名册', err: null };
  try {
    const j = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (!Array.isArray(j) || !j.length) return { spec: [], src: file, err: '不是非空数组' };
    for (const s of j) if (!s.metric || !s.probe || !s.re) return { spec: [], src: file, err: '条目缺 metric/probe/re' };
    return { spec: j, src: file, err: null };
  } catch (e) { return { spec: [], src: file, err: e.message.split('\n')[0] }; }
}

function collect(o) {
  const st = { rows: [], probe: [], comparisons: 0, red: 0, nm: 0, found: 0, files: 0, roster: 0, unitClashes: 0, csv: '', md: '', token: NM };
  const stamp = o.stamp || new Date().toISOString().replace('T', ' ').slice(0, 19);
  const emit = (id, name, detail, verdict) => {
    if (!VERDICTS.has(verdict)) throw new Error(`非法判定词 ${verdict}`);
    st.rows.push(`${id} ${name} ${detail} ${verdict}`);
    st.comparisons += 1;
    if (verdict === 'FAIL') st.red += 1; else if (verdict === NM) st.nm += 1;
  };

  const { spec, src, err } = loadSpec(o.spec);
  o.specSrc = src;
  if (err) { emit('K0', '指标名册', `载入失败=${err}（宁可红，不许退化成内置名册悄悄跑）`, 'FAIL'); return finish(st, o); }
  const compiled = [];
  for (const s of spec) {
    try { compiled.push({ ...s, RE: new RegExp(s.re), RP: new RegExp(s.probe, 'i') }); }
    catch (e) { emit('K1', `名册正则「${s.metric}」`, `编译失败=${e.message.split('\n')[0]}`, 'FAIL'); }
  }
  st.roster = compiled.length;
  emit('K2', '名册就绪', `名册=${src} 指标=${compiled.length} 必中=${compiled.filter((s) => s.required).length}`, compiled.length ? 'PASS' : NM);

  let files = [];
  try { files = listReports(o.dir); } catch (e) { emit('P0', '扫描目录', `读不了=${e.message.split('\n')[0]}`, NM); return finish(st, o); }
  st.files = files.length;
  emit('P1', '扫描文件数', `目录=${o.dir} 文件=${files.length} 字节=${files.reduce((a, f) => a + f.text.length, 0)}`, files.length ? 'PASS' : NM);

  const recs = new Map(compiled.map((s) => [s.metric, []]));
  if (!files.length) {
    // 0 样本：整条不是"没指标"而是"没测成"，一律 NOT_MEASURED（读不到不判红，也不判绿）
    emit('P2', '抓取前提', '扫描到 0 个文件，未做任何抓取；0 样本不算通过', NM);
    compiled.forEach((s, i) => emit(`M${i + 1}`, s.metric, `值=${NM} 单位=${NM} 来源=${NM} 命中=0 前提=无文件`, NM));
    buildOutputs(st, compiled, recs, o, stamp);
    return finish(st, o);
  }

  // 阶段一：探针。先把每个锚的候选行原文打出来 —— "摘要行在第几行"不许靠猜。
  const cands = new Map(compiled.map((s) => [s.metric, []]));
  for (const f of files) {
    f.lines = f.text.split('\n');
    f.lines.forEach((ln, i) => {
      for (const s of compiled) {
        const c = cands.get(s.metric);
        if (c.length < 6 && s.RP.test(ln)) c.push(`${f.rel}:L${i + 1} 「${ln.trim().slice(0, 96)}」`);
      }
    });
  }
  for (const s of compiled) {
    const c = cands.get(s.metric);
    st.probe.push(`# 探针 [${s.cls}] ${s.metric} 锚=/${s.probe}/ 候选行=${c.length}`);
    c.slice(0, 3).forEach((r) => st.probe.push(`  ${r}`));
    if (!c.length) st.probe.push('  （无候选行：锚一次也没落到任何行，形状可能已变 —— 先看这里再谈取值）');
  }
  const probeTot = [...cands.values()].reduce((a, r) => a + r.length, 0);
  emit('P3', '探针候选行', `合计=${probeTot} 有候选的指标=${[...cands.values()].filter((r) => r.length).length}/${compiled.length}（先核对上面原文，再采信取值）`, probeTot ? 'PASS' : NM);

  // 阶段二：取值（逐行、逐指标，一次取第一个匹配）
  for (const f of files) for (const s of compiled) f.lines.forEach((ln, i) => {
    const m = s.RE.exec(ln);
    if (m) recs.get(s.metric).push({ file: f.rel, line: i + 1, value: m[1], unit: (m[2] || '无量纲').trim() });
  });

  compiled.forEach((s, i) => {
    const r = recs.get(s.metric);
    if (!r.length) { emit(`M${i + 1}`, s.metric, `值=${NM} 单位=${NM} 来源=${NM} 命中=0 名册必中=${!!s.required}`, s.required ? 'FAIL' : NM); return; }
    st.found += 1;
    const units = [...new Set(r.map((x) => x.unit))];
    const clash = units.length > 1;
    if (clash) st.unitClashes += 1;
    emit(`M${i + 1}`, s.metric,
      `值=${r[0].value} 单位=[${units.join(',')}] 来源=${r.map((x) => `${x.file}:L${x.line}`).join(',')} 命中=${r.length}` +
      (clash ? ' 同一指标多种单位：不许跨单位相减，要么分列要么先归一' : ''),
      clash ? 'FAIL' : 'PASS');
  });
  emit('U1', '单位一致性', `多单位指标=${st.unitClashes}`, st.unitClashes ? 'FAIL' : 'PASS');
  buildOutputs(st, compiled, recs, o, stamp);
  emit('Z1', '计数地板', `扫描文件=${st.files} 抓到指标=${st.found} ${NM}=${st.roster - st.found} 名册=${st.roster} 落件=${o.out}+${o.report}`, 'PASS');
  return finish(st, o);
}

function buildOutputs(st, compiled, recs, o, stamp) {
  const header = ['指标', '值', '单位', '来源件', '抓取时间'];
  const csv = [header.join(',')];
  const md = ['# 指标采集', '', `目录 \`${o.dir}\` ｜ 名册 \`${o.specSrc}\` ｜ 扫描文件 ${st.files} ｜ 抓取时间 ${stamp}`, '',
    `| ${header.join(' | ')} |`, `|${header.map(() => '---|').join('')}`];
  for (const s of compiled) {
    const r = recs.get(s.metric) || [];
    const units = [...new Set(r.map((x) => x.unit))];
    const val = r.length ? (units.length > 1 ? `${NM}` : r[0].value) : NM;
    const unit = r.length ? (units.length > 1 ? units.join('/') : r[0].unit) : NM;
    const from = r.length ? r.map((x) => `${x.file}:L${x.line}`).join(' ') : NM;
    csv.push([cell(s.metric), cell(val), cell(unit), cell(from), cell(stamp)].join(','));
    md.push(`| ${s.metric} | ${val} | ${unit} | ${from} | ${stamp} |`);
  }
  st.csv = `${csv.join('\n')}\n`;
  st.md = `${md.join('\n')}\n\n共 ${compiled.length} 行：抓到 ${st.found}，${NM} ${compiled.length - st.found}。多单位的指标分列呈现，不相减。\n`;
}

function finish(st, o) {
  st.token = st.red ? 'FAIL' : (st.nm ? NM : 'PASS');
  if (o.out && st.csv) {
    try {
      fs.mkdirSync(path.dirname(path.resolve(o.out)), { recursive: true });
      fs.writeFileSync(o.out, st.csv, 'utf8');
      if (o.report) { fs.mkdirSync(path.dirname(path.resolve(o.report)), { recursive: true }); fs.writeFileSync(o.report, st.md, 'utf8'); }
    } catch (e) { st.rows.push(`O0 落件 写不出=${e.message.split('\n')[0]} FAIL`); st.comparisons += 1; st.red += 1; st.token = 'FAIL'; }
  }
  return st;
}

function show(st) {
  for (const p of st.probe) console.log(p);
  for (const r of st.rows) console.log(r);
  console.log(`判 ${st.comparisons} 项：文件=${st.files} 抓到=${st.found} 未测=${st.roster - st.found} 单位冲突=${st.unitClashes} 红=${st.red} ${st.token}`);
}

// ---------------------------------------------------------------- self
function copyTree(src, dst) {
  fs.mkdirSync(dst, { recursive: true });
  for (const e of fs.readdirSync(src, { withFileTypes: true })) {
    const s = path.join(src, e.name), d = path.join(dst, e.name);
    if (e.isDirectory()) copyTree(s, d); else fs.copyFileSync(s, d);
  }
}

function selfTest() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'metrics-collector-self-'));
  const rows = [];
  let red = 0;
  const ck = (name, want, got) => {
    const ok = JSON.stringify(want) === JSON.stringify(got);
    rows.push(`T ${name} 期望=${JSON.stringify(want)} 实得=${JSON.stringify(got)} ${ok ? 'PASS' : 'FAIL'}`);
    if (!ok) red += 1;
  };
  const runIn = (sub, from, mutate) => {
    const d = path.join(tmp, sub);
    copyTree(from, d);
    if (mutate) mutate(d);
    return collect({ dir: d, out: path.join(d, 'metrics.csv'), report: path.join(d, 'metrics.md'), stamp: '固定时戳' });
  };

  // 只放三份核心报告的临时源（第 4 件是故意带单位冲突的，不进干净基线）
  const core = path.join(tmp, 'src-core');
  fs.mkdirSync(core, { recursive: true });
  for (const f of ['resource-report.txt', 'timing-summary.txt', 'bench-counts.txt']) fs.copyFileSync(path.join(FIXDIR, f), path.join(core, f));

  const a = runIn('caseA', core);
  ck('A 干净基线：文件/抓到/未测/冲突/红', { files: 3, found: 14, miss: 1, unitClashes: 0, red: 0 },
    { files: a.files, found: a.found, miss: a.roster - a.found, unitClashes: a.unitClashes, red: a.red });
  ck('A 整体判定（有 1 项未测 ⇒ 不许 PASS）', NM, a.token);
  ck('A CSV 行数=名册+表头', 16, a.csv.trim().split('\n').length);
  ck('A 抓不到的指标也进 CSV（值栏 NOT_MEASURED，不留空）', '结温读数,NOT_MEASURED,NOT_MEASURED,NOT_MEASURED,固定时戳',
    a.csv.trim().split('\n').find((l) => l.startsWith('结温读数')));
  ck('A 必中项不许被悄悄改名（每条正则至少命中一次）', 0, a.rows.filter((r) => r.includes('必中=true') && r.endsWith(NM)).length);

  const b = runIn('caseB', FIXDIR);
  ck('B 换单位的那件 ⇒ 多单位指标=2 且整体红', { files: 4, unitClashes: 2, token: 'FAIL' },
    { files: b.files, unitClashes: b.unitClashes, token: b.token });

  // 能红对照：只改一个数的写法，让同一形状抓不到 ⇒ 必须少抓一个
  const c = runIn('caseC', core, (d) => {
    const p = path.join(d, 'resource-report.txt');
    fs.writeFileSync(p, fs.readFileSync(p, 'utf8').replace('DSP 占用 = 12 tiles', 'DSP 占用 = 十二 tiles'), 'utf8');
  });
  ck('C 改一个数就少抓一个', { found: 13, dropped: 1, red: 1, token: 'FAIL' },
    { found: c.found, dropped: a.found - c.found, red: c.red, token: c.token });

  const e = path.join(tmp, 'empty-dir'); fs.mkdirSync(e, { recursive: true });
  const d0 = collect({ dir: e, out: path.join(e, 'metrics.csv'), report: path.join(e, 'metrics.md'), stamp: '固定时戳' });
  ck('D 扫描 0 文件 ⇒ 整体 NOT_MEASURED（不是 PASS）', { files: 0, token: NM, red: 0 }, { files: d0.files, token: d0.token, red: d0.red });
  ck('D 0 文件时 CSV 仍写满名册行', 16, d0.csv.trim().split('\n').length);

  const bad = path.join(tmp, 'bad.spec.json');
  fs.writeFileSync(bad, '{ "not": "an array" }', 'utf8');
  const f0 = collect({ dir: core, out: null, report: null, spec: bad, stamp: '固定时戳' });
  ck('E 名册坏了不许悄悄退化成内置的', { red: 1, token: 'FAIL' }, { red: f0.red, token: f0.token });

  for (const r of rows) console.log(r);
  console.log(`判 ${rows.length} 项：红=${red} 夹具=${fs.readdirSync(FIXDIR).length} 名册=${DEFAULT_SPEC.length} 临时目录=${tmp} ${red ? 'FAIL' : 'PASS'}`);
  if (red) console.log(`保留临时目录以便复跑：${tmp}`); else fs.rmSync(tmp, { recursive: true, force: true });
  return red ? 1 : 0;
}

// ---------------------------------------------------------------- main
function main(argv) {
  const pos = [];
  const o = { out: null, report: null, spec: null };
  let self = false;
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--self') self = true;
    else if (a === '--out') { i += 1; o.out = argv[i]; }
    else if (a === '--report') { i += 1; o.report = argv[i]; }
    else if (a === '--spec') { i += 1; o.spec = argv[i]; }
    else if (a === '-h' || a === '--help') { console.log(USAGE); return 0; }
    else if (a.startsWith('--')) { console.log(`判 1 项：未知选项 ${a} FAIL`); return 1; }
    else pos.push(a);
  }
  if (self) return selfTest();
  if (pos.length !== 1) { console.log(USAGE); return 1; }
  if (!fs.existsSync(pos[0]) || !fs.statSync(pos[0]).isDirectory()) { console.log(`判 1 项：报告目录不可用 ${pos[0]} FAIL`); return 1; }
  o.out = o.out || 'metrics.csv';
  o.report = o.report || 'metrics.md';
  o.dir = pos[0];
  const st = collect(o);
  show(st);
  return st.red ? 1 : 0;
}

process.exit(main(process.argv.slice(2)));
