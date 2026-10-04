#!/usr/bin/env node
/**
 * skill/scripts/report_metrics/report_metrics.mjs
 * 从真实 Vivado 报告里取 WNS/TNS/失败端点/LUT/FF/BRAM/DSP，落 CSV + Markdown（三态判定）
 *
 * 字段位置不是按记忆写的：见 skill/scripts/report_metrics/SKILL.md 第 8 节"量出来的形状"，
 * 那份形状是从 build/timing_summary.rpt 与 build/utilization.rpt 逐列打印出来的实测结果。
 * 解析规则：先按节标题定位（| Design Timing Summary），再取表头行，再跳过虚线行，
 * 值行按"右端对齐到表头字段的末列"取值（不是按空格数第几列，负数/宽数字不会串列）。
 * 取不到 / 取到两次 / 值为空或 X ⇒ 一律 NOT_MEASURED，绝不默认 0。
 *
 * 退出码：0=PASS 1=FAIL 2=NOT_MEASURED 3=环境或前置不满足
 */
import fs from 'node:fs';
import path from 'node:path';

const HELP = `用法: node report_metrics.mjs --timing F --utilization F --out-dir DIR [选项]
  --timing F             report_timing_summary 的输出文件（必需）
  --utilization F        report_utilization 的输出文件（必需）
  --out-dir DIR          产物目录（拒绝 src/ sim/ build/ 等工程目录）
  --prefix NAME          产物文件名前缀，默认 metrics
  --max-pct FIELD=NUM    占比上界（可重复或用逗号分隔多个 FIELD=NUM）
  --min-pct FIELD=NUM    占比下界（同上）；上下界都给了才算判了这一条
  --baseline CSV         上一版产出的 metrics.csv，做双向漂移比对
  --max-drift-pct NUM    与 baseline 的允许漂移百分比（绝对值，两个方向一起管）
  --help                 本帮助
退出码: 0=PASS 1=FAIL 2=NOT_MEASURED 3=前置不满足`;

const PROTECTED = ['src/', 'sim/', 'build/', 'board/', 'data/', 'report/', 'docs/'];
const argv = process.argv.slice(2);
const opt = { 'max-pct': [], 'min-pct': [] };
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--help' || a === '-h') { console.log(HELP); process.exit(0); }
  if (a === '--max-pct' || a === '--min-pct') { (a === '--max-pct' ? opt['max-pct'] : opt['min-pct']).push(...String(argv[++i]).split(',')); continue; }
  if (a.startsWith('--')) { opt[a.slice(2)] = argv[++i]; continue; }
  console.log(`METRICS 前置不满足 无法识别的参数 ${a} NOT_MEASURED`); process.exit(3);
}
function pre(msg) { console.log(`METRICS 前置不满足 ${msg} NOT_MEASURED`); console.log('METRICS 前置不满足 判 0 项 FAIL'); process.exit(3); }
function nm(msg) { console.log(`METRICS 读不到输入 ${msg} NOT_MEASURED`); console.log('METRICS 读不到输入 判 0 项 NOT_MEASURED'); process.exit(2); }
for (const k of ['timing', 'utilization']) if (!opt[k]) pre(`缺 --${k}`);
for (const k of ['timing', 'utilization']) if (!fs.existsSync(opt[k])) nm(`--${k} ${opt[k]} 不存在`);
for (const k of ['timing', 'utilization']) if (fs.statSync(opt[k]).size === 0) nm(`--${k} ${opt[k]} 是空文件`);
if (!opt['out-dir']) pre('缺 --out-dir（产物必须写独立目录，不写工程目录）');
const outDir = opt['out-dir'].split(path.sep).join('/');
if (PROTECTED.some(x => outDir === x.replace(/\/$/, '') || outDir.startsWith(x))) pre(`--out-dir 指向工程目录 ${outDir}`);

const lines = [];
let nMade = 0, nFail = 0, nNm = 0, nPass = 0;
function say(name, made, detail, verdict) {
  nMade += made;
  if (verdict === 'FAIL') nFail++; else if (verdict === 'NOT_MEASURED') nNm++; else nPass++;
  lines.push(`${name.padEnd(30)} 判 ${made} 项 ${detail} ${verdict}`);
}
const num = s => (s === undefined || s === null || s === '' || /^x/i.test(s)) ? null : (Number.isFinite(Number(s)) ? Number(s) : null);

// ---------- 表头对齐取值（实测形状：值行的每个数右端与表头字段末列同一列） ----------
function readLines(f) { return fs.readFileSync(f, 'utf8').split(/\r?\n/); }
function headerFields(line, names) {
  const out = [];
  for (const n of names) {
    const i = line.indexOf(n);
    if (i >= 0) out.push({ name: n, end: i + n.length });
  }
  return out;
}
function rightAligned(line, ends) {
  const toks = [...line.matchAll(/\S+/g)];
  const map = {};
  for (const e of ends) {
    const hit = toks.filter(t => t.index + t[0].length === e.end).pop();
    map[e.name] = hit ? hit[0] : null;
  }
  return map;
}
function designTiming(txt) {
  const L = txt.split(/\r?\n/);
  const NAMES = ['WNS(ns)', 'TNS(ns)', 'TNS Failing Endpoints', 'TNS Total Endpoints', 'WHS(ns)', 'THS(ns)',
                 'THS Failing Endpoints', 'THS Total Endpoints', 'WPWS(ns)', 'TPWS(ns)',
                 'TPWS Failing Endpoints', 'TPWS Total Endpoints'];
  for (let i = 0; i < L.length; i++) {
    if (!/^\|\s*Design Timing Summary\s*$/.test(L[i])) continue;
    for (let j = i + 1; j < Math.min(L.length, i + 40); j++) {
      if (!/\bWNS\(ns\)/.test(L[j])) continue;
      const ends = headerFields(L[j], NAMES);
      let k = j + 1;
      while (k < L.length && /^[\s-]+$/.test(L[k])) k++;
      const got = rightAligned(L[k] || '', ends.map(e => e));
      return { line: k + 1, fields: got, names: NAMES, found: ends.length };
    }
  }
  return null;
}
function intraClock(txt) {
  const L = txt.split(/\r?\n/);
  for (let i = 0; i < L.length; i++) {
    if (!/^\|\s*Intra Clock Table\s*$/.test(L[i])) continue;
    let h = i + 1;
    while (h < L.length && !/\bWNS\(ns\)/.test(L[h])) h++;
    const ends = headerFields(L[h], ['WNS(ns)', 'TNS Failing Endpoints', 'TNS Total Endpoints', 'WHS(ns)', 'THS Failing Endpoints']);
    const rows = [];
    // 实测形状：表体是"从虚线行下一行开始的连续行"，直到第一个空行结束；
    // 子时钟（clkfbout 那一类）没有 setup 列，值全空，靠 rightAligned 的全 null 判掉。
    for (let k = h + 1; k < L.length; k++) {
      if (rows.length && /^\s*$/.test(L[k])) break;
      if (/^\s*$/.test(L[k])) continue;
      const name = (L[k].match(/^\s*(\S+)/) || [, ''])[1];
      if (!name || /^-+$/.test(name)) continue;
      const got = rightAligned(L[k], ends.map(e => e));
      if (Object.values(got).every(v => v === null)) continue;
      rows.push({ clock: name, line: k + 1, ...got });
    }
    return { headerLine: h + 1, rows };
  }
  return null;
}
function utilTableRows(txt, wanted) {
  const L = txt.split(/\r?\n/);
  const out = {};
  for (const name of wanted) {
    const hits = [];
    L.forEach((l, i) => { if (new RegExp(`^\\|\\s*${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*\\|`).test(l)) hits.push({ i: i + 1, l }); });
    out[name] = hits;
  }
  return out;
}
function cells(rowLine) { return rowLine.split('|').map(s => s.trim()); }
function reportHeader(txt) {
  const g = k => { const m = txt.match(new RegExp(`^\\|\\s*${k}\\s*:\\s*(.*)$`, 'm')); return m ? m[1].trim() : null; };
  return { tool: g('Tool Version'), date: g('Date'), design: g('Design'), device: g('Device'), command: g('Command') };
}

const T = fs.readFileSync(opt.timing, 'utf8');
const U = fs.readFileSync(opt.utilization, 'utf8');
const H = reportHeader(T);
const UA = Object.entries(reportHeader(U)).filter(([k]) => k !== 'command');

// key -> {value, unit, file, line, note}
const M = {};
const put = (k, v, unit, file, line, note) => { M[k] = { value: v, unit, file, line, note: note || '' }; };

const dt = designTiming(T);
const TKEY = { 'WNS(ns)': 'setup_wns_ns', 'TNS(ns)': 'setup_tns_ns', 'TNS Failing Endpoints': 'setup_failing_endpoints',
               'TNS Total Endpoints': 'setup_total_endpoints', 'WHS(ns)': 'hold_whs_ns', 'THS(ns)': 'hold_ths_ns',
               'THS Failing Endpoints': 'hold_failing_endpoints', 'THS Total Endpoints': 'hold_total_endpoints',
               'WPWS(ns)': 'pulse_wpws_ns', 'TPWS(ns)': 'pulse_tns_ns',
               'TPWS Failing Endpoints': 'pulse_failing_endpoints', 'TPWS Total Endpoints': 'pulse_total_endpoints' };
const UNAME = ['Slice LUTs', 'LUT as Logic', 'LUT as Memory', 'Slice Registers', 'Register as Flip Flop',
               'Register as Latch', 'Block RAM Tile', 'RAMB36/FIFO*', 'RAMB18', 'DSPs'];
const UKEY = { 'Slice LUTs': 'lut_slice', 'LUT as Logic': 'lut_as_logic', 'LUT as Memory': 'lut_as_memory',
               'Slice Registers': 'reg_slice', 'Register as Flip Flop': 'reg_as_ff', 'Register as Latch': 'reg_as_latch',
               'Block RAM Tile': 'bram_tile', 'RAMB36/FIFO*': 'bram_ramb36', 'RAMB18': 'bram_ramb18', 'DSPs': 'dsp48' };

const ut = utilTableRows(U, UNAME);

// R1 形状定位：每个字段都要在报告里命中，且多处命中必须互相一致；行号一起记下来
{
  let made = 0, missing = 0, conflicting = 0;
  const miss = [], conf = [];
  if (!dt) { missing += Object.keys(TKEY).length; miss.push('timing_summary:无 Design Timing Summary 段'); }
  else for (const [hn, key] of Object.entries(TKEY)) {
    made++;
    const raw = dt.fields[hn];
    if (raw === null || raw === undefined || num(raw) === null) { missing++; miss.push(key); continue; }
    put(key, num(raw), /ns/.test(hn) ? 'ns' : 'count', opt.timing, dt.line, hn);
  }
  for (const name of UNAME) {
    made++;
    const hits = ut[name];
    if (!hits.length) { missing++; miss.push(name); continue; }
    const vals = hits.map(x => num(cells(x.l)[2]));
    if (hits.length > 1) {
      // 同一个 Site Type 在 report_utilization 里会出现两次（1. Slice Logic 与 2. Slice Logic Distribution，
      // 实测 build/utilization.rpt:36 与 :79 都是 "LUT as Logic"）。两处必须给同一个 Used，
      // 不一致就是报告自己或解析串了列 ⇒ 判红，不许"取第一条"糊过去。
      const uniq = [...new Set(vals.map(v => String(v)))];
      if (uniq.length > 1 || vals.some(v => v === null)) { conflicting++; conf.push(`${name}=[${vals.join('/')}] 行=${hits.map(x => x.i).join(',')}`); }
    }
    const c = cells(hits[0].l);
    const v = vals[0];
    if (v === null) { missing++; miss.push(`${name}:值格为空`); continue; }
    const lineTag = hits.map(x => x.i).join(',');
    put(UKEY[name], v, name === 'Block RAM Tile' ? 'tile' : 'count', opt.utilization, lineTag,
        `Used 列，行文本 ${hits[0].l.slice(0, 46)}`);
    if (c[5] !== '') put(UKEY[name] + '_avail', num(c[5]), 'count', opt.utilization, lineTag, 'Available 列');
    if (c[6] !== '') put(UKEY[name] + '_util_pct', num(c[6]), 'percent', opt.utilization, lineTag, 'Util% 列');
  }
  const detail = `请求字段=${Object.keys(TKEY).length + UNAME.length} 取到=${Object.keys(M).length} 取不到=${missing}${miss.length ? ' 例:' + miss.slice(0, 3).join(' ') : ''} 命中多次=${conflicting}${conf.length ? ' 例:' + conf.slice(0, 2).join(' ') : ''}`;
  say('R1_field_shape', made, detail, (conflicting ? 'FAIL' : (missing ? 'NOT_MEASURED' : 'PASS')));
}

// R2 符号与失败端点数同条判（两维一起出现：数值方向 + 端点归属）
{
  const pairs = [['setup_wns_ns', 'setup_failing_endpoints'], ['hold_whs_ns', 'hold_failing_endpoints']];
  let made = 0, bad = 0, undec = 0; const det = [];
  for (const [vk, fk] of pairs) {
    const v = M[vk] && M[vk].value, f = M[fk] && M[fk].value;
    if (v === undefined || f === undefined) { undec++; det.push(`${vk}:读不到`); continue; }
    made++;
    const okSign = v >= 0, okZero = f === 0;
    if (okSign !== okZero) { bad++; det.push(`${vk}=${v} 但 ${fk}=${f}（方向与端点数不自洽）`); }
    else det.push(`${vk}=${v} 配 ${fk}=${f} 同向`);
  }
  say('R2_sign_vs_failing', made, det.join(' ') + (undec ? ` 读不到=${undec}` : ''),
      made === 0 ? 'NOT_MEASURED' : (bad ? 'FAIL' : (undec ? 'NOT_MEASURED' : 'PASS')));
}

// R3 整体与部分：上界夹逼（不引入报告以外的常数），增与减两个方向都能判
{
  const checks = [];
  const g = k => (M[k] ? M[k].value : null);
  checks.push({ name: 'lut', expr: 'LUT as Logic + LUT as Memory == Slice LUTs',
                want: g('lut_as_logic') !== null && g('lut_as_memory') !== null ? g('lut_as_logic') + g('lut_as_memory') : null,
                got: g('lut_slice') });
  checks.push({ name: 'reg', expr: 'FF + Latch == Slice Registers',
                want: g('reg_as_ff') !== null && g('reg_as_latch') !== null ? g('reg_as_ff') + g('reg_as_latch') : null,
                got: g('reg_slice') });
  checks.push({ name: 'bram', expr: 'RAMB36 <= Block RAM Tile <= RAMB36 + RAMB18',
                want: null, lo: g('bram_ramb36'), hi: g('bram_ramb36') !== null && g('bram_ramb18') !== null ? g('bram_ramb36') + g('bram_ramb18') : null,
                got: g('bram_tile') });
  let made = 0, bad = 0, undec = 0; const det = [];
  for (const c of checks) {
    if (c.got === null || c.got === undefined) { undec++; det.push(`${c.name}:总数读不到`); continue; }
    if (c.want !== null) {
      if (c.want === null || Number.isNaN(c.want)) { undec++; det.push(`${c.name}:部分读不到`); continue; }
      made++;
      if (c.want !== c.got) { bad++; det.push(`${c.name} ${c.expr} 不成立(${c.got} vs ${c.want})`); }
      else det.push(`${c.name} ${c.want}==${c.got}`);
    } else {
      if (c.lo === null || c.hi === null) { undec++; det.push(`${c.name}:两侧都读不到`); continue; }
      made += 2;
      const loOk = c.lo <= c.got, hiOk = c.got <= c.hi;
      if (!loOk || !hiOk) { bad++; det.push(`${c.name} ${c.lo}<=${c.got}<=${c.hi} 破了(小侧${loOk ? 'ok' : 'bad'} 大侧${hiOk ? 'ok' : 'bad'})`); }
      else det.push(`${c.name} ${c.lo}<=${c.got}<=${c.hi}`);
    }
  }
  say('R3_whole_vs_parts', made, det.join(' ') + (undec ? ` 读不到=${undec}` : ''),
      made === 0 ? 'NOT_MEASURED' : (bad ? 'FAIL' : (undec ? 'NOT_MEASURED' : 'PASS')));
}

// R4 Util% 复算：用同一行的 Used/Available 反算，容差 = 报告只印两位小数
{
  const keys = Object.keys(M).filter(k => k.endsWith('_util_pct'));
  let made = 0, bad = 0, undec = 0; const det = [];
  for (const k of keys) {
    const base = k.replace(/_util_pct$/, '');
    const u = M[base] && M[base].value, a = M[base + '_avail'] && M[base + '_avail'].value, p = M[k].value;
    if (u === undefined || a === undefined || p === undefined || !a) { undec++; continue; }
    made++;
    const calc = u / a * 100;
    if (Math.abs(calc - p) > 0.005 + 1e-9) { bad++; det.push(`${base}:印${p} 算${calc.toFixed(4)}`); }
    else det.push(`${base}:印${p} 算${calc.toFixed(2)} 一致`);
  }
  say('R4_percent_recheck', made, det.join(' ') + (undec ? ` 读不到=${undec}` : ''),
      made === 0 ? 'NOT_MEASURED' : (bad ? 'FAIL' : (undec ? 'NOT_MEASURED' : 'PASS')));
}

// R5 归属：全局 WNS 的取值与"它属于哪一时钟族"一次判完（两维同条）
{
  const ic = intraClock(T);
  const gw = M.setup_wns_ns && M.setup_wns_ns.value;
  let made = 0, bad = 0, undec = 0; const det = [];
  if (!ic || !ic.rows.length || gw === undefined) undec++;
  else {
    const withWns = ic.rows.filter(r => num(r['WNS(ns)']) !== null);
    if (!withWns.length) undec++;
    else {
      const owner = withWns.reduce((m, r) => (num(r['WNS(ns)']) < num(m['WNS(ns)']) ? r : m), withWns[0]);
      made += 2;
      const vEq = num(owner['WNS(ns)']) === gw;
      const eEq = gw >= 0 ? num(owner['TNS Failing Endpoints']) === 0 : num(owner['TNS Failing Endpoints']) > 0;
      if (!vEq) bad++;
      if (!eEq) bad++;
      det.push(`全局 WNS=${gw} 最差族=${owner.clock}(行 ${owner.line}) 值等=${vEq ? 'yes' : 'no'} 该族失败端点=${owner['TNS Failing Endpoints']} 与符号自洽=${eEq ? 'yes' : 'no'} 参比族=${withWns.length}`);
      const blank = ic.rows.length - withWns.length;
      if (blank) det.push(`只有脉宽列没有 setup 列的族=${blank}（这些族不参与最小值）`);
    }
  }
  say('R5_wns_ownership', made, det.join(' ') + (undec ? ' 读不到 Intra Clock Table 或全局 WNS' : ''),
      made === 0 ? 'NOT_MEASURED' : (bad ? 'FAIL' : 'PASS'));
}

// R6 阈值（只从命令行取；上下界缺一侧就判 NOT_MEASURED，不默认放行）
{
  const parse = arr => { const o = {}; for (const s of arr) { const i = s.indexOf('='); if (i > 0) o[s.slice(0, i).trim()] = Number(s.slice(i + 1)); } return o; };
  const mx = parse(opt['max-pct']), mn = parse(opt['min-pct']);
  const fields = [...new Set([...Object.keys(mx), ...Object.keys(mn)])];
  let made = 0, bad = 0, undec = 0; const det = [];
  for (const f of fields) {
    const key = f.endsWith('_util_pct') ? f : (M[f + '_util_pct'] ? f + '_util_pct' : null);
    const v = key ? M[key].value : undefined;
    if (v === undefined || mx[f] === undefined || mn[f] === undefined) { undec++; det.push(`${f}:上下界不齐或值读不到`); continue; }
    made += 2;
    const hiOk = v <= mx[f], loOk = v >= mn[f];
    if (!hiOk || !loOk) bad++;
    det.push(`${f}=${v} 上界${mx[f]}${hiOk ? '' : ' 破'} 下界${mn[f]}${loOk ? '' : ' 破'}`);
  }
  if (!fields.length) say('R6_threshold_band', 0, '命令行没给 --max-pct/--min-pct ⇒ 本条不判（判过要两条都给）', 'NOT_MEASURED');
  else say('R6_threshold_band', made, det.join(' ') + (undec ? ` 判不了=${undec}` : ''),
      made === 0 ? 'NOT_MEASURED' : (bad ? 'FAIL' : (undec ? 'NOT_MEASURED' : 'PASS')));
}

// ---------- 产物 ----------
const prefix = opt.prefix || 'metrics';
fs.mkdirSync(outDir, { recursive: true });
const keys = Object.keys(M).sort();
const csv = ['key,value,unit,source_file,source_line,note'];
for (const k of keys) csv.push([k, M[k].value, M[k].unit, M[k].file.replace(/,/g, ' '), M[k].line, M[k].note.replace(/,/g, ';')].join(','));
const csvPath = path.join(outDir, `${prefix}.csv`);
fs.writeFileSync(csvPath, csv.join('\n') + '\n', 'utf8');

// R7 与 baseline 的双向漂移（给了 baseline 才判；两侧都有的键才算比较次数，单侧的就是缺失项）
{
  if (!opt.baseline) say('R7_baseline_drift', 0, '没给 --baseline ⇒ 本条不判', 'NOT_MEASURED');
  else if (!fs.existsSync(opt.baseline)) { nm(`--baseline ${opt.baseline} 不存在`); }
  else {
    const maxDrift = opt['max-drift-pct'] === undefined ? null : Number(opt['max-drift-pct']);
    if (maxDrift === null) say('R7_baseline_drift', 0, '给了 --baseline 但没给 --max-drift-pct ⇒ 不判', 'NOT_MEASURED');
    else {
      const base = {};
      for (const l of fs.readFileSync(opt.baseline, 'utf8').split(/\r?\n/)) {
        if (!l || l.startsWith('key,')) continue;
        const c = l.split(',');
        if (c.length >= 2 && Number.isFinite(Number(c[1]))) base[c[0]] = Number(c[1]);
      }
      const both = keys.filter(k => k in base);
      const onlyNew = keys.filter(k => !(k in base));
      const onlyBase = Object.keys(base).filter(k => !keys.includes(k));
      let made = both.length, bad = 0, up = 0, down = 0; const det = [];
      for (const k of both) {
        const d = (M[k].value - base[k]) / (Math.abs(base[k]) || 1) * 100;
        if (d > 0) up++; else if (d < 0) down++;
        if (Math.abs(d) > maxDrift) { bad++; det.push(`${k}:${base[k]}->${M[k].value}(Δ${d.toFixed(2)}%)`); }
      }
      say('R7_baseline_drift', made, `容许=${maxDrift}% 增=${up} 减=${down} 破限=${bad} 新增键=${onlyNew.length} 消失键=${onlyBase.length}${det.length ? ' 例:' + det.slice(0, 3).join(' ') : ''}`,
          made === 0 ? 'NOT_MEASURED' : (bad ? 'FAIL' : 'PASS'));
    }
  }
}

// R8 可追溯：每行数值的来源文件与来源行号必须同时在场（两维同条）
// 行号允许是逗号分隔的列表（同一个 Site Type 在 report_utilization 里出现两次，两处行号都要在场）。
{
  let made = 0, bad = 0; const det = [];
  for (const k of keys) {
    made++;
    const okFile = M[k].file && fs.existsSync(M[k].file);
    const nums = String(M[k].line).split(',').map(s => Number(s.trim()));
    const okLine = nums.length > 0 && nums.every(n => Number.isInteger(n) && n > 0);
    if (!okFile || !okLine) { bad++; det.push(`${k}:file=${!!okFile} line=${!!okLine}`); }
  }
  say('R8_provenance_per_row', made, `行=${keys.length} 缺出处的=${bad}${det.length ? ' 例:' + det.slice(0, 2).join(' ') : ''}`,
      made === 0 ? 'NOT_MEASURED' : (bad ? 'FAIL' : 'PASS'));
}

const md = [];
md.push(`# report_metrics 读数（${path.basename(opt.timing)} / ${path.basename(opt.utilization)}）`);
md.push('');
md.push(`- 报告头（逐字取自文件，不重新跑工具）：${UA.map(([k, v]) => `${k}=${v || '空'}`).join(' ; ')}`);
md.push(`- 取值命令：\`node skill/scripts/report_metrics/report_metrics.mjs --timing ${opt.timing} --utilization ${opt.utilization} --out-dir ${outDir}\``);
md.push('');
md.push('| key | value | unit | 来源 | 行 |');
md.push('| --- | --- | --- | --- | --- |');
for (const k of keys) md.push(`| \`${k}\` | ${M[k].value} | ${M[k].unit} | \`${M[k].file}\` | ${M[k].line} |`);
md.push('');
const verdict = nFail ? 'FAIL' : (nNm ? 'NOT_MEASURED' : (nMade === 0 ? 'NOT_MEASURED' : 'PASS'));
md.push(`判定：${verdict}（判 ${nMade} 项 / 红 ${nFail} 项 / 未判 ${nNm} 项）`);
const mdPath = path.join(outDir, `${prefix}.md`);
fs.writeFileSync(mdPath, md.join('\n') + '\n', 'utf8');

for (const l of lines) console.log(l);
console.log(`METRICS ${csvPath} ${mdPath} 取到字段=${keys.length} 判 ${nMade} 项 未判 ${nNm} 项 红 ${nFail} 项 ${verdict}`);
process.exit(verdict === 'PASS' ? 0 : verdict === 'FAIL' ? 1 : 2);
