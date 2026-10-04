#!/usr/bin/env node
/**
 * skill/scripts/regmap_check/regmap_check.mjs
 * 寄存器契约一致性：单一真相源(契约表) <-> RTL <-> 主机/固件代码 <-> 块图地址 <-> 人读文档表
 *
 * 复跑（仓库根，本仓真实契约表；两个输入路径都必须显式给，脚本没有兜底默认值）：
 *   node skill/scripts/regmap_check/regmap_check.mjs \
 *     --contract skill/scripts/regmap_check/axi_gpio_contract.tsv \
 *     --bd build/tcl/build_system_axigpio.tcl
 *
 * 判据（一条一行，判定 token 在最后一列，每行打印分母 `判 N 项`；标签文字与列宽属于判据的一部分）：
 *   K1 contract_columns   22 列齐全且每格非空（空 = 这一格没人负责）
 *   K2 bits_range_overlap [h:l] 合法、同一 (base,addr_off) 内位域不重叠、RO 窗口行的 index 不重复
 *   K3 vs_rtl             每行 rtl_pattern 能在 rtl_file 里定点找到
 *   K4 vs_host_code       每行 host_pattern 能在 host_file（固件或上位机脚本）里找到
 *   K5 vs_docs            正向：每行 doc_pattern 在 doc_file 里；反向：文档点名的 0x412xxxxx 基址必须也在表里
 *   K6 vs_block_design    表里的 base 必须被 BD 钉过，BD 钉了而表里没有的同样判红（双向覆盖）
 *   K7 widest_vs_bits     widest <= 2^width-1；越界的行必须写明越界行为（装得下 / 靠声明夹住 两向都数）
 *   K8 reset_provenance   reset 是数 ⇒ reset_src 的 path:line 必须能打开且那一行含数字
 *
 * 三态：读不到文件 / 解析不到 / 空集 ⇒ NOT_MEASURED，绝不 PASS。
 * 退出码：0=PASS 1=FAIL 2=NOT_MEASURED 3=环境或前置不满足
 * stdout 只打 ASCII 加必需的 `判 N 项` 分母 token（本机控制台是 cp936，CJK 会让 grep 失真）。
 */
import fs from 'node:fs';

const COLS = ['row', 'object', 'bits', 'access', 'index', 'reset', 'reset_src', 'wse', 'rse', 'irq',
              'unit', 'widest', 'overflow', 'cdc', 'base', 'addr_off', 'rtl_file', 'rtl_pattern',
              'host_file', 'host_pattern', 'doc_file', 'doc_pattern'];

const HELP = `用法: node regmap_check.mjs --contract FILE --bd FILE [选项]
  --contract FILE   契约表（TSV，制表符分隔；# 开头是注释行）
  --bd FILE         块图脚本（钉死地址的那段 foreach），K6 用
  --only K1,K3      只跑点名的判据（其余不打印也不计数）
  --help            本帮助
必需列（${COLS.length} 个）：${COLS.join(' ')}
退出码: 0=PASS 1=FAIL 2=NOT_MEASURED 3=前置不满足`;

function pre(msg) { console.log(`REGMAP precondition ${msg} FAIL`); console.log('REGMAP precondition 判 0 项 FAIL'); process.exit(3); }
function nm(msg) { console.log(`REGMAP not_measured ${msg} NOT_MEASURED`); console.log('REGMAP not_measured 判 0 项 NOT_MEASURED'); process.exit(2); }

const argv = process.argv.slice(2);
const opt = { only: [] };
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--help' || a === '-h') { console.log(HELP); process.exit(0); }
  if (a === '--only') { opt.only = String(argv[++i]).split(',').map(s => s.trim()).filter(Boolean); continue; }
  if (a.startsWith('--')) { opt[a.slice(2)] = argv[++i]; continue; }
  pre(`unknown argument ${a}`);
}
for (const k of ['contract', 'bd']) {
  if (!opt[k]) pre(`missing --${k} (no built-in fallback path)`);
  if (!fs.existsSync(opt[k])) nm(`--${k} ${opt[k]} not found`);
  if (fs.statSync(opt[k]).size === 0) nm(`--${k} ${opt[k]} is empty`);
}

const results = [];
let nMade = 0, nFail = 0, nNm = 0;
const want = id => opt.only.length === 0 || opt.only.includes(id);
function say(id, name, made, detail, verdict) {
  if (!want(id)) return;
  nMade += made;
  if (verdict === 'FAIL') nFail++; else if (verdict === 'NOT_MEASURED') nNm++;
  results.push(`${id} ${name.padEnd(20)} 判 ${made} 项 ${detail} ${verdict}`);
}

// ---------- 读表：形状不对就退，不按记忆里的列序解析 ----------
const raw = fs.readFileSync(opt.contract, 'utf8').split(/\r?\n/).filter(l => l.trim() !== '' && !l.startsWith('#'));
const header = raw.length ? raw[0].split('\t').map(s => s.trim()) : [];
const missingCols = COLS.filter(c => !header.includes(c));
const rows = raw.slice(1).map(l => {
  const cells = l.split('\t');
  const o = {};
  header.forEach((h, i) => { o[h] = (cells[i] === undefined ? '' : cells[i]).trim(); });
  return o;
});

const fileCache = new Map();
function linesOf(f) {
  if (fileCache.has(f)) return fileCache.get(f);
  let v = null;
  try { v = fs.readFileSync(f, 'utf8').split(/\r?\n/); } catch { v = null; }
  fileCache.set(f, v); return v;
}
const contains = (f, needle) => {
  const L = linesOf(f);
  if (L === null) return 'nofile';
  if (!needle) return 'miss';
  return L.some(l => l.includes(needle)) ? 'hit' : 'miss';
};
const parseBits = s => {
  const m = String(s).match(/^\[(\d+)(?::(\d+))?\]$/);
  if (!m) return null;
  const h = Number(m[1]), l = m[2] === undefined ? h : Number(m[2]);
  return l <= h ? { h, l, w: h - l + 1 } : null;
};

// K1 表自洽：列齐全 + 每格非空
{
  if (!raw.length || missingCols.length) {
    say('K1', 'contract_columns', 0,
        missingCols.length ? `header_lacks=${missingCols.join(',')}` : 'no_data_rows', 'NOT_MEASURED');
  } else {
    const empt = [];
    rows.forEach((r, i) => { for (const c of COLS) if (!r[c]) empt.push(`${r.row || 'row' + (i + 2)}.${c}`); });
    const unknown = header.filter(h => !COLS.includes(h));
    say('K1', 'contract_columns', rows.length * COLS.length,
        `rows=${rows.length} cols=${COLS.length} empty=${empt.length}${empt.length ? ' at:' + empt.slice(0, 3).join(',') : ''} unknown_cols=${unknown.length}`,
        empt.length ? 'FAIL' : 'PASS');
  }
}

// K2 位域合法 / 不重叠 / RO 窗口 index 区间不重叠
// 窗口式读回（access=RO，先写 index 再读一个数据口）比的是 index 区间：同一地址上两条 RO 行的
// index 区间相交 = 同一次读会被两条契约行认领 ⇒ 判红；普通位域行比 bit 区间。
{
  const idxSet = s => {
    const s2 = String(s).trim();
    if (/^na$/i.test(s2)) return null;
    const set = new Set();
    for (const part of s2.split(',')) {
      const m = part.trim().match(/^(\d+)(?:-(\d+))?$/);
      if (!m) return 'bad';
      const a = Number(m[1]), b = m[2] === undefined ? a : Number(m[2]);
      if (b < a) return 'bad';
      for (let i = a; i <= b; i++) set.add(i);
    }
    return set;
  };
  const bad = []; const byAddr = new Map(); let ok = 0;
  for (const r of rows) {
    const f = parseBits(r.bits);
    if (!f || f.h > 31) { bad.push(`${r.row}:bad_bits=${r.bits}`); continue; }
    const ix = idxSet(r.index);
    if (ix === 'bad') { bad.push(`${r.row}:bad_index=${r.index}`); continue; }
    ok++;
    const key = `${r.base}${r.addr_off}`;
    for (const o of byAddr.get(key) || []) {
      const g = parseBits(o.bits), jx = idxSet(o.index);
      if (r.access === 'RO' && o.access === 'RO' && ix && jx) {
        const shared = [...ix].filter(v => jx.has(v));
        if (shared.length) bad.push(`${r.row}~index~overlaps~${o.row}@${key}[${shared.slice(0, 3).join(':')}]`);
      } else if (g && !(f.h < g.l || g.h < f.l)) {
        bad.push(`${r.row}~bits~overlaps~${o.row}@${key}`);
      }
    }
    if (!byAddr.has(key)) byAddr.set(key, []); byAddr.get(key).push(r);
  }
  say('K2', 'bits_range_overlap', rows.length + bad.length,
      `rows=${rows.length} wellformed=${ok} overlap_or_illegal=${bad.length}${bad.length ? ' at:' + bad.slice(0, 3).join(',') : ''}`,
      rows.length === 0 ? 'NOT_MEASURED' : (bad.length ? 'FAIL' : 'PASS'));
}

// K3/K4 契约 <-> RTL / 主机与固件代码
function anchorCriterion(id, name, fileKey, patKey) {
  let miss = 0, nofile = 0, hit = 0; const det = [];
  for (const r of rows) {
    const res = contains(r[fileKey], r[patKey]);
    if (res === 'nofile') { nofile++; det.push(`${r.row}:${fileKey}=${r[fileKey]} unreadable`); }
    else if (res === 'miss') { miss++; det.push(`${r.row}: anchor not found in ${r[fileKey]}`); }
    else hit++;
  }
  say(id, name, rows.length,
      `compared=${rows.length} hit=${hit} miss=${miss} unreadable_file=${nofile}${det.length ? ' at:' + det.slice(0, 3).join(' | ') : ''}`,
      rows.length === 0 ? 'NOT_MEASURED' : (miss ? 'FAIL' : (nofile ? 'NOT_MEASURED' : 'PASS')));
}
anchorCriterion('K3', 'vs_rtl', 'rtl_file', 'rtl_pattern');
anchorCriterion('K4', 'vs_host_code', 'host_file', 'host_pattern');

// K5 契约 <-> 人读文档（正向逐行 + 反向：文档里的基址必须登记）
{
  let miss = 0, nofile = 0, hit = 0; const det = [];
  for (const r of rows) {
    const res = contains(r.doc_file, r.doc_pattern);
    if (res === 'nofile') { nofile++; det.push(`${r.row}:doc=${r.doc_file} unreadable`); }
    else if (res === 'miss') { miss++; det.push(`${r.row}: "${r.doc_pattern}" not in ${r.doc_file}`); }
    else hit++;
  }
  const docAddrs = new Set();
  for (const f of [...new Set(rows.map(r => r.doc_file))]) {
    const L = linesOf(f); if (!L) continue;
    for (const l of L) for (const m of l.matchAll(/0x4[0-9a-fA-F]{7}/g)) docAddrs.add(m[0].toLowerCase());
  }
  const tableAddrs = new Set(rows.map(r => r.base.toLowerCase()));
  const notInTable = [...docAddrs].filter(a => /^0x412[0-9a-f]{5}$/.test(a) && !tableAddrs.has(a));
  say('K5', 'vs_docs', rows.length + docAddrs.size,
      `rows=${rows.length} hit=${hit} doc_missing_row=${miss} doc_unreadable=${nofile} doc_bases=${docAddrs.size} base_not_in_table=${notInTable.length}${notInTable.length ? '[' + notInTable.join(',') + ']' : ''}${det.length ? ' at:' + det.slice(0, 2).join(' | ') : ''}`,
      rows.length === 0 ? 'NOT_MEASURED' : ((miss || notInTable.length) ? 'FAIL' : (nofile ? 'NOT_MEASURED' : 'PASS')));
}

// K6 契约 <-> 块图钉址（双向）
{
  const L = linesOf(opt.bd);
  if (!L) say('K6', 'vs_block_design', 0, `--bd ${opt.bd} unreadable`, 'NOT_MEASURED');
  else {
    const pinned = new Set();
    for (const l of L) {
      const m = l.match(/^\s*[\w/]+\s+(0x[0-9a-fA-F]{8})\s*$/);
      if (m) pinned.add(m[1].toLowerCase());
    }
    const tableBases = new Set(rows.map(r => r.base.toLowerCase()));
    const onlyTable = [...tableBases].filter(b => !pinned.has(b));
    const onlyBd = [...pinned].filter(b => !tableBases.has(b));
    say('K6', 'vs_block_design', tableBases.size + pinned.size,
        `table_bases=${tableBases.size} bd_pinned=${pinned.size} in_table_not_pinned=${onlyTable.length}${onlyTable.length ? '[' + onlyTable.join(',') + ']' : ''} pinned_not_in_table=${onlyBd.length}${onlyBd.length ? '[' + onlyBd.join(',') + ']' : ''}`,
        (pinned.length === 0 || tableBases.size === 0) ? 'NOT_MEASURED' : ((onlyTable.length || onlyBd.length) ? 'FAIL' : 'PASS'));
  }
}

// K7 最宽输入 vs 位宽
{
  let made = 0, bad = 0, undec = 0, fits = 0, clamped = 0; const det = [];
  for (const r of rows) {
    const f = parseBits(r.bits); const widest = Number(r.widest);
    if (!f || r.widest === '' || !Number.isFinite(widest)) { undec++; det.push(`${r.row}: width_or_widest_unparsable`); continue; }
    made++;
    const cap = Math.pow(2, f.w) - 1;
    if (widest <= cap) { fits++; continue; }
    const ov = (r.overflow || '').trim();
    if (/^(na|none|)$/i.test(ov)) { bad++; det.push(`${r.row}: widest=${widest} > cap=${cap} overflow_col="${ov}"`); }
    else clamped++;
  }
  say('K7', 'widest_vs_bits', made,
      `judged=${made} fits=${fits} over_but_documented=${clamped} over_not_documented=${bad} undecidable=${undec}${det.length ? ' at:' + det.slice(0, 3).join(' | ') : ''}`,
      made === 0 ? 'NOT_MEASURED' : (bad ? 'FAIL' : (undec ? 'NOT_MEASURED' : 'PASS')));
}

// K8 复位值出处
{
  let made = 0, bad = 0, undec = 0; const det = [];
  for (const r of rows) {
    if (!/^(0x[0-9a-fA-F]+|\d+)$/.test(r.reset)) { undec++; det.push(`${r.row}: reset="${r.reset}" is not a plain number`); continue; }
    made++;
    const m = String(r.reset_src).match(/^([^\s:]+):(\d+)$/);
    if (!m) { bad++; det.push(`${r.row}: reset_src="${r.reset_src}" is not path:line`); continue; }
    const L = linesOf(m[1]);
    if (!L) { undec++; det.push(`${r.row}: reset_src file ${m[1]} unreadable`); continue; }
    const line = L[Number(m[2]) - 1];
    if (line === undefined) { bad++; det.push(`${r.row}: ${m[1]} has no line ${m[2]}`); continue; }
    if (!/[0-9]/.test(line)) bad++;
  }
  say('K8', 'reset_provenance', made,
      `numeric_rows=${made} bad_provenance=${bad} no_number_or_unreadable=${undec}${det.length ? ' at:' + det.slice(0, 3).join(' | ') : ''}`,
      (made === 0) ? 'NOT_MEASURED' : (bad ? 'FAIL' : (undec ? 'NOT_MEASURED' : 'PASS')));
}

if (!results.length) { console.log('REGMAP no criterion matched by --only NOT_MEASURED'); console.log('REGMAP 判 0 项 NOT_MEASURED'); process.exit(2); }
for (const l of results) console.log(l);
const verdict = nFail ? 'FAIL' : (nNm ? 'NOT_MEASURED' : (nMade === 0 ? 'NOT_MEASURED' : 'PASS'));
console.log(`REGMAP ${opt.contract} 判 ${nMade} 项 未判 ${nNm} 项 红 ${nFail} 项 ${verdict}`);
process.exit(verdict === 'PASS' ? 0 : verdict === 'FAIL' ? 1 : 2);
