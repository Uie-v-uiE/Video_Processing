#!/usr/bin/env node
/**
 * skill/scripts/golden_compare/golden_compare.mjs
 * 黄金参考表 ↔ 实际产出表：逐键、逐值、带容差的三态比对（只读，产物写到 --out-dir）
 *
 * 复跑（仓库根，正例基线，钉的是 CDC 基线与它自己点名的来源报告）：
 *   node skill/scripts/golden_compare/golden_compare.mjs \
 *     --golden build/CDC_BASELINE.txt --golden-format kv --golden-key '$1' --golden-values 'endpoints=@2,unsafe=@1' \
 *     --produced build/frozen_r23_srcseen/cdc.rpt --produced-format kv --produced-key '$2>$3' \
 *     --produced-values 'endpoints=@5,unsafe=@3' --produced-where '$1=Critical' --tolerance 0
 *
 * 退出码：0=PASS 1=FAIL 2=NOT_MEASURED（读不到/解析不到/空集）3=环境或前置不满足
 * 判定 token 一律放在每行最后一个字段；每判一条打印 `判 N 项`（数的是做了多少次比较）。
 */
import fs from 'node:fs';
import path from 'node:path';

const HELP = `用法: node golden_compare.mjs --golden F --produced F [选项]
  --golden-format kv|csv        默认 kv（空白分列）
  --produced-format kv|csv      默认 kv
  --golden-key '<expr>'         kv: $N=第 N 列(1 起), @N=倒数第 N 列; csv: 列名
  --golden-values 'n=expr,...'  参与比对的数值列（csv 直接写列名）
  --produced-key/--produced-values  同上
  --golden-where 'expr'         行过滤, 形如 '$1=Critical'
  --produced-where 'expr'       同上
  --tolerance <num>             允许的绝对偏差, 默认 0
  --comment <char>              行首注释符, 默认 #
  --out-dir <dir>               比对结果落盘目录(可选); 拒绝写入 src/ sim/ build/ 等工程目录
  --help                        本帮助`;

function fail3(msg) { console.log(`GOLDEN 前置不满足 ${msg} NOT_MEASURED`); console.log('GOLDEN 前置不满足 判 0 项 FAIL'); process.exit(3); }
function die2(msg) { console.log(`GOLDEN 读不到输入 ${msg} NOT_MEASURED`); console.log('GOLDEN 读不到输入 判 0 项 NOT_MEASURED'); process.exit(2); }

const argv = process.argv.slice(2);
const opt = {};
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--help' || a === '-h') { console.log(HELP); process.exit(0); }
  if (a.startsWith('--')) { opt[a.slice(2)] = argv[i + 1]; i++; }
  else fail3(`无法识别的参数 ${a}`);
}
const need = ['golden', 'produced'];
for (const k of need) if (!opt[k]) fail3(`缺 --${k}`);
for (const k of need) if (!fs.existsSync(opt[k])) die2(`--${k} ${opt[k]} 不存在`);
for (const k of need) if (fs.statSync(opt[k]).size === 0) die2(`--${k} ${opt[k]} 是空文件`);

const PROTECTED = ['src/', 'sim/', 'build/', 'board/', 'data/', 'report/', 'docs/'];
if (opt['out-dir']) {
  const p = opt['out-dir'].split(path.sep).join('/');
  if (PROTECTED.some(x => p === x.replace(/\/$/, '') || p.startsWith(x)))
    fail3(`--out-dir 指向工程目录 ${p}（技能包脚本不改工程产物）`);
}
const tol = opt.tolerance === undefined ? 0 : Number(opt.tolerance);
if (!Number.isFinite(tol)) fail3(`--tolerance 不是数 ${opt.tolerance}`);
const comment = opt.comment || '#';

const results = [];
let nFail = 0, nNm = 0, nPass = 0, nMade = 0;
function say(name, made, detail, verdict) {
  nMade += made;
  if (verdict === 'FAIL') nFail++; else if (verdict === 'NOT_MEASURED') nNm++; else nPass++;
  results.push(`${name.padEnd(30)} 判 ${made} 项 ${detail} ${verdict}`);
}

function splitCsvLine(line) {
  const out = []; let cur = '', q = false;
  for (const ch of line) {
    if (ch === '"') q = !q;
    else if (ch === ',' && !q) { out.push(cur.trim()); cur = ''; }
    else cur += ch;
  }
  out.push(cur.trim());
  return out;
}
function cell(cols, expr) {
  if (/^@/.test(expr)) { const k = Number(expr.slice(1)); return cols.length >= k ? cols[cols.length - k] : undefined; }
  if (/^\$/.test(expr)) { const k = Number(expr.slice(1)); return cols[k - 1]; }
  return undefined;
}
// 键表达式允许是模板：'$2>$3' 拼出 'clk_a>clk_b'；单列 '$1' / '@5' 也走同一条路
function evalExpr(cols, expr) {
  if (/^\$[0-9]+$/.test(expr) || /^@[0-9]+$/.test(expr)) return cell(cols, expr);
  const out = expr.replace(/[@$][0-9]+/g, m => {
    const v = cell(cols, m);
    return v === undefined ? '' : v;
  });
  return out === '' ? undefined : out;
}
function whereOk(cols, expr) {
  if (!expr) return true;
  const i = expr.indexOf('=');
  if (i < 0) throw new Error(`where 表达式少了等号: ${expr}`);
  const l = cell(cols, expr.slice(0, i).trim());
  return l !== undefined && l === expr.slice(i + 1).trim();
}

function load(file, fmt, key, values, where) {
  const txt = fs.readFileSync(file, 'utf8');
  const lines = txt.split(/\r?\n/);
  const rows = new Map();
  let header = null, empty = 0, unparsed = 0, total = 0;
  const names = (values || '').split(',').map(s => s.trim()).filter(Boolean).map(s => {
    const i = s.indexOf('=');
    return i < 0 ? { name: s, expr: s } : { name: s.slice(0, i).trim(), expr: s.slice(i + 1).trim() };
  });
  if (!names.length) throw new Error(`${file} 没给 --values`);
  for (const raw of lines) {
    const line = raw.replace(/\r$/, '');
    if (!line.trim()) continue;
    if (line.trimStart().startsWith(comment)) continue;
    const cols = fmt === 'csv' ? splitCsvLine(line) : line.trim().split(/\s+/);
    if (fmt === 'csv' && !header) { header = cols; continue; }
    if (fmt === 'csv') {
      if (!whereOkByName(cols, header, where)) continue;
      const k = cols[header.indexOf(key)];
      if (k === undefined) { unparsed++; continue; }
      total++;
      const v = {};
      for (const n of names) {
        const idx = header.indexOf(n.name);
        const s = idx < 0 ? undefined : cols[idx];
        const num = Number(s);
        if (s === undefined || s === '' || !Number.isFinite(num)) { v[n.name] = null; unparsed++; empty++; }
        else v[n.name] = num;
      }
      if (!rows.has(k)) rows.set(k, v);
      continue;
    }
    if (!whereOk(cols, where)) continue;
    const k = evalExpr(cols, key);
    if (k === undefined || k === '') { unparsed++; continue; }
    total++;
    const v = {};
    for (const n of names) {
      const s = evalExpr(cols, n.expr);
      const num = Number(s);
      if (s === undefined || s === '' || !Number.isFinite(num)) { v[n.name] = null; unparsed++; empty++; }
      else v[n.name] = num;
    }
    if (!rows.has(k)) rows.set(k, v);
  }
  return { rows, total, unparsed, empty, names: names.map(n => n.name) };
}
function whereOkByName(cols, header, expr) {
  if (!expr) return true;
  const i = expr.indexOf('=');
  const idx = header.indexOf(expr.slice(0, i).trim());
  return idx < 0 ? false : cols[idx] === expr.slice(i + 1).trim();
}

let A, B;
try {
  A = load(opt.golden, opt['golden-format'] || 'kv', opt['golden-key'], opt['golden-values'], opt['golden-where']);
  B = load(opt.produced, opt['produced-format'] || 'kv', opt['produced-key'], opt['produced-values'], opt['produced-where']);
} catch (e) {
  fail3(`表头/表达式解析失败 ${e.message}`);
}

const ka = [...A.rows.keys()], kb = [...B.rows.keys()];
const shared = ka.filter(k => B.rows.has(k));
const onlyGolden = ka.filter(k => !B.rows.has(k));
const onlyProduced = kb.filter(k => !A.rows.has(k));
const valueNames = A.names.filter(n => B.names.includes(n));

// C1 键集合双向覆盖：总数与缺失项同条出现（少一行、多一行都要判）
{
  const made = new Set([...ka, ...kb]).size;
  const detail = `黄金=${ka.length} 产出=${kb.length} 共有=${shared.length} 产出缺=${onlyGolden.length} 产出不明=${onlyProduced.length}`;
  if (made === 0) say('C1_key_coverage', 0, '两张表都没有数据行（空集合不算通过）', 'NOT_MEASURED');
  else say('C1_key_coverage', made, detail, (onlyGolden.length || onlyProduced.length) ? 'FAIL' : 'PASS');
}

// C2 逐键逐值比对：|Δ|<=容差；增大与减小分开计数（只判一侧算半成品）
let c2made = 0, c2bad = 0, up = 0, down = 0, undecidable = 0;
const diffs = [];
for (const k of shared) {
  for (const n of valueNames) {
    const g = A.rows.get(k)[n], p = B.rows.get(k)[n];
    c2made++;
    if (g === null || p === null) { undecidable++; continue; }
    const d = p - g;
    if (d > 0) up++; else if (d < 0) down++;
    if (Math.abs(d) > tol) { c2bad++; diffs.push(`${k}.${n}:${g}->${p}(Δ${d > 0 ? '+' : ''}${round(d)})`); }
  }
}
{
  if (c2made === 0) say('C2_value_vs_tolerance', 0, '没有共有的键可比（空集合不算通过）', 'NOT_MEASURED');
  else {
    const detail = `容差=${tol} 超上=${c2bad} 键值增=${up} 键值减=${down} 值不可解析=${undecidable}` +
                   (diffs.length ? ` 例:${diffs.slice(0, 3).join(' ')}` : '');
    let v = 'PASS';
    if (c2bad) v = 'FAIL';
    else if (undecidable) v = 'NOT_MEASURED';
    say('C2_value_vs_tolerance', c2made, detail, v);
  }
}

// C3 最差的值是否属于黄金参考里的键（两维同条：归属 + 取值，一次比完）
{
  let made = 0, bad = 0, nm = 0;
  const det = [];
  for (const n of valueNames) {
    const cand = kb.map(k => ({ k, v: B.rows.get(k)[n] })).filter(x => x.v !== null && Number.isFinite(x.v));
    if (!cand.length || !shared.length) { nm++; continue; }
    const worst = cand.reduce((m, x) => (x.v > m.v ? x : m), cand[0]);
    made += 2;
    const inGolden = A.rows.has(worst.k);
    const gv = inGolden ? A.rows.get(worst.k)[n] : null;
    const notWorse = gv !== null && worst.v <= gv + tol;
    if (!inGolden || !notWorse) bad++;
    det.push(`${n}:最差=${worst.k}(${worst.v}) 属于黄金=${inGolden ? 'yes' : 'no'} 不比黄金差=${notWorse ? 'yes' : 'no'}`);
  }
  if (made === 0 && nm > 0) say('C3_worst_row_membership', 0, '取不到可比的最差行（空集合不算通过）', 'NOT_MEASURED');
  else say('C3_worst_row_membership', made, det.join(' ') + (nm ? ` 未判列=${nm}` : ''), bad ? 'FAIL' : (nm ? 'NOT_MEASURED' : 'PASS'));
}

// C4 解析面：每张表读到的行数、空/坏值数（读不到一律不算通过）
{
  const made = 2;
  const bad = (A.total === 0 || B.total === 0);
  say('C4_parse_surface_nonempty', made,
      `黄金行=${A.total} 空或坏值=${A.empty} 产出行=${B.total} 空或坏值=${B.empty}`,
      bad ? 'NOT_MEASURED' : 'PASS');
}

function round(x) { return Number.isInteger(x) ? x : Number(x.toFixed(6)); }

for (const r of results) console.log(r);
const verdict = nFail ? 'FAIL' : (nNm ? 'NOT_MEASURED' : (nMade === 0 ? 'NOT_MEASURED' : 'PASS'));
console.log(`GOLDEN ${path.basename(opt.golden)} vs ${path.basename(opt.produced)} 判 ${nMade} 项 未判 ${nNm} 项 红 ${nFail} 项 ${verdict}`);

if (opt['out-dir']) {
  fs.mkdirSync(opt['out-dir'], { recursive: true });
  const outPath = path.join(opt['out-dir'], 'golden_diff.csv');
  const rows = ['key,value,golden,produced,delta,within_tolerance'];
  for (const k of [...new Set([...ka, ...kb])].sort()) {
    for (const n of valueNames) {
      const g = A.rows.has(k) ? A.rows.get(k)[n] : '';
      const p = B.rows.has(k) ? B.rows.get(k)[n] : '';
      const d = (Number.isFinite(g) && Number.isFinite(p)) ? round(p - g) : '';
      const ok = (Number.isFinite(g) && Number.isFinite(p)) ? (Math.abs(p - g) <= tol ? 'yes' : 'no') : 'not_measured';
      rows.push([k, n, g === null ? '' : g, p === null ? '' : p, d, ok].join(','));
    }
  }
  rows.push(`verdict,${verdict},judged,${nMade},not_measured,${nNm},fail,${nFail}`);
  fs.writeFileSync(outPath, rows.join('\n') + '\n', 'utf8');
  console.log(`GOLDEN 写出 ${outPath} 判 ${rows.length} 行 PASS`);
}
process.exit(verdict === 'PASS' ? 0 : verdict === 'FAIL' ? 1 : 2);
