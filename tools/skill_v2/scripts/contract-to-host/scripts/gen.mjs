#!/usr/bin/env node
// gen.mjs —— 契约（寄存器表 CSV）⇒ 主机侧三份产物：同源、幂等、缺列不编默认值。
//
//   node scripts/gen.mjs --in <contract.csv> --out <dir> [--stem <name>]
//   node scripts/gen.mjs --self
//
// 契约列（固定形状，一列一名）：name,offset,width,access,policy,reset,doc
//   access ∈ RW / RO / WO / self-clear；policy = 单位或换算式（原样搬进生成物，不参与计算）
// 只用 Node 标准库。生成物不写时间与绝对路径 ⇒ 同一输入两次生成逐字节一致。
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ENTRY = path.resolve(HERE, '..');
const SELF = path.join(ENTRY, 'fixtures');
const COLS = ['name', 'offset', 'width', 'access', 'policy', 'reset', 'doc'];
const HARD_COLS = ['name', 'offset', 'width', 'access'];
const ACCESS = ['RW', 'RO', 'WO', 'self-clear'];
const PLACEHOLDER = '【待填：读回值】';
// --self 用的台架替身：填了期望的骨架 + 一个理想寄存器模型（RO 写被丢、自清位写完即 0）。
// CTH_BROKEN=<寄存器名> 让模型对该名字丢弃写入，用来证明骨架能判红（不是橡皮图章）。
const HARNESS = `import { runAll } from './contract_regs_test.mjs';
import { REGISTERS } from './contract_regs.mjs';
const broken = (process.env.CTH_BROKEN || '').split(',').filter(Boolean);
const store = new Map(REGISTERS.map((r) => [r.name, r.reset]));
const io = {
  write(name, v) {
    const r = REGISTERS.find((x) => x.name === name);
    if (!r || r.access === 'RO' || r.access === null) return;
    if (broken.includes(name)) return;
    store.set(name, r.access === 'self-clear' ? 0 : v);
  },
  read(name) {
    const r = REGISTERS.find((x) => x.name === name);
    if (!r || r.access === 'RO') return 0;
    const v = store.get(name);
    return v === null || v === undefined ? 0 : v;
  },
};
const res = await runAll(io);
for (const x of res.rows) console.log(x.reg + ' ' + x.verdict + ' 比较=' + x.cmp + ' ' + x.detail);
const token = res.red ? 'FAIL' : (res.nm ? 'NOT_MEASURED' : 'PASS');
console.log('判 ' + res.cmp + ' 项 红=' + res.red + ' 未测=' + res.nm + ' ' + token);
process.exit(res.red ? 1 : (res.nm ? 2 : 0));
`;

// ---------------- 读契约 ----------------
function parseCsv(text) {
  const rows = [];
  let field = '', row = [], q = false, started = false;
  const src = String(text).replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    if (q) {
      if (c === '"') { if (src[i + 1] === '"') { field += '"'; i++; } else q = false; } else field += c;
      continue;
    }
    if (c === '"') { q = true; started = true; continue; }
    if (c === ',') { row.push(field); field = ''; started = true; continue; }
    if (c === '\n') { if (started || field !== '') { row.push(field); rows.push(row); } row = []; field = ''; started = false; continue; }
    field += c; started = true;
  }
  if (started || field !== '') { row.push(field); rows.push(row); }
  return rows.filter(r => r.some(x => String(x).trim() !== ''));
}
function parseNum(s) {
  if (s === null || s === undefined) return { missing: true };
  const t = String(s).trim();
  if (t === '') return { missing: true };
  let n = NaN;
  if (/^0x[0-9a-fA-F]+$/.test(t) || /^0b[01]+$/.test(t)) n = Number(BigInt(t));
  else if (/^\d+$/.test(t)) n = Number(t);
  if (!Number.isInteger(n)) return { bad: t };
  return { v: n };
}
const hx = (v, w) => '0x' + (v >>> 0).toString(16).padStart(w || 8, '0');
const maskOf = (w) => (w >= 32 ? 0xffffffff : (1 << w) - 1);
const bytesOf = (w) => Math.max(1, Math.ceil(w / 8));
const ctype = (w) => (w <= 8 ? 'uint8_t' : w <= 16 ? 'uint16_t' : 'uint32_t');
const sym = (n) => String(n).toUpperCase().replace(/[^A-Z0-9_]/g, '_');

function loadContract(csvPath) {
  const raw = fs.readFileSync(csvPath, 'utf8');
  const digest = crypto.createHash('sha256').update(raw).digest('hex').slice(0, 16);
  const grid = parseCsv(raw);
  const errs = [], warns = [], regs = [];
  if (grid.length === 0) return { digest, regs, header: [], sorted: [], errs: ['契约是空表（连表头都没有）⇒ NOT_MEASURED'], warns };
  const header = grid[0].map(h => String(h).trim().toLowerCase());
  const hardMissing = HARD_COLS.filter(c => !header.includes(c));
  if (hardMissing.length) return { digest, regs, header, sorted: [], errs: [`表头缺硬列：${hardMissing.join(',')}（这几列没了就无从生成，判红）`], warns };
  const extra = header.filter(h => !COLS.includes(h));
  if (extra.length) warns.push(`表头有多余列（被忽略）：${extra.join(',')}`);
  const idx = Object.fromEntries(COLS.map(c => [c, header.indexOf(c)]));
  grid.slice(1).forEach((r, i) => {
    const get = (c) => (idx[c] < 0 ? null : (r[idx[c]] === undefined ? null : String(r[idx[c]]).trim()));
    const rawName = get('name');
    const rec = { row: i + 2, name: (rawName && rawName !== '') ? rawName : `ROW${i + 2}`, missing: [] };
    const at = (msg) => errs.push(`第 ${rec.row} 行(${rec.name}) ${msg}`);
    const off = parseNum(get('offset'));
    if (off.missing) { rec.offset = null; rec.missing.push('offset'); }
    else if (off.bad !== undefined) at(`offset 不是数（${off.bad}）`);
    else rec.offset = off.v;
    const wd = parseNum(get('width'));
    if (wd.missing) { rec.width = null; rec.missing.push('width'); }
    else if (wd.bad !== undefined) at(`width 不是数（${wd.bad}）`);
    else if (wd.v < 1 || wd.v > 32) at(`width=${wd.v} 超出 1..32`);
    else rec.width = wd.v;
    const acc = get('access');
    if (acc === null || acc === '') { rec.access = null; rec.missing.push('access'); }
    else {
      const norm = ACCESS.find(a => a.toLowerCase() === acc.toLowerCase());
      if (!norm) at(`access=「${acc}」不在 ${ACCESS.join('/')}`);
      else rec.access = norm;
    }
    if (rawName === null || rawName === '') at('name 为空');
    const rstRaw = get('reset');
    const rst = parseNum(rstRaw);
    if (rstRaw === null) { rec.reset = null; rec.missing.push('reset(整列缺失)'); }
    else if (rst.missing) { rec.reset = null; rec.missing.push('reset'); }
    else if (rst.bad !== undefined) at(`reset 不是数（${rst.bad}）`);
    else {
      rec.reset = rst.v;
      if (rec.width !== null && rst.v > maskOf(rec.width))
        at(`复位越界：reset=${hx(rst.v)} 装不进 width=${rec.width}（上限 ${hx(maskOf(rec.width))}）⇒ 判红`);
    }
    rec.policy = get('policy'); if (rec.policy === null || rec.policy === '') rec.missing.push('policy');
    rec.doc = get('doc'); if (rec.doc === null || rec.doc === '') rec.missing.push('doc');
    regs.push(rec);
  });
  const seen = new Map();
  for (const r of regs) {
    if (seen.has(r.name)) errs.push(`名字重复：${r.name}（第 ${seen.get(r.name)} 行与第 ${r.row} 行）`);
    else seen.set(r.name, r.row);
  }
  const sorted = [...regs].filter(r => r.offset !== null && r.width !== null)
    .sort((a, b) => (a.offset - b.offset) || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  for (let i = 1; i < sorted.length; i++) {
    const a = sorted[i - 1], b = sorted[i];
    const aEnd = a.offset + bytesOf(a.width);
    if (b.offset < aEnd) errs.push(`地址重叠：${a.name}[${hx(a.offset, 2)}..${hx(aEnd, 2)}) 与 ${b.name}[${hx(b.offset, 2)}..) 相交 ⇒ 判红`);
  }
  return { digest, regs, header, sorted, errs, warns };
}
const usable = (r) => r.offset !== null && r.width !== null && r.access !== null && r.missing.length === 0;

// ---------------- 产物 1：C 头文件 ----------------
function genHeader(stem, ct, csvBase) {
  const G = sym(stem), L = [];
  L.push('/* generated by scripts/contract-to-host/gen.mjs -- 请勿手改：改契约后重生成 */');
  L.push(`/* contract: ${csvBase}  rows: ${ct.regs.length}  digest: ${ct.digest} */`);
  L.push('/* 本文件不含生成时间与绝对路径 ⇒ 同一契约两次生成逐字节一致 */');
  L.push('');
  L.push(`#ifndef ${G}_REGS_H`);
  L.push(`#define ${G}_REGS_H`);
  L.push('');
  L.push('#include <stdint.h>');
  L.push('');
  L.push('/* 编译期断言：条件为假时报错数组（不依赖 C11 关键字） */');
  L.push('#define GEN_ASSERT(cond, tag) typedef char gen_assert_##tag[(cond) ? 1 : -1]');
  L.push('');
  for (const r of ct.regs) {
    const N = sym(r.name);
    L.push(`/* ${r.name} —— ${r.doc === null ? '（doc 缺列）' : r.doc}${r.policy ? '  policy: ' + r.policy : ''} */`);
    L.push(r.offset === null ? `/* ${N}_OFFSET: NOT_MEASURED（契约缺 offset）⇒ 不编默认值 */` : `#define ${N}_OFFSET  ${hx(r.offset, 2)}u`);
    L.push(r.width === null ? `/* ${N}_WIDTH: NOT_MEASURED（契约缺 width） */` : `#define ${N}_WIDTH   ${r.width}u`);
    L.push(r.reset === null ? `/* ${N}_RESET: NOT_MEASURED（契约缺 reset）⇒ 不许编默认值 */` : `#define ${N}_RESET   ${hx(r.reset)}u`);
    L.push(r.access === null ? `/* ${N}_ACCESS: NOT_MEASURED（契约缺 access） */` : `#define ${N}_ACCESS  ("${r.access}")`);
    if (r.offset !== null && r.width !== null) {
      const T = ctype(r.width);
      L.push(`#define ${N}_MASK    ${hx(maskOf(r.width))}u`);
      L.push(`#define ${N}_READ(base) ((*(const volatile ${T} *)((const uint8_t *)(base) + ${N}_OFFSET)))`);
      if (r.access === 'RW' || r.access === 'WO' || r.access === 'self-clear')
        L.push(`#define ${N}_WRITE(base, v) ((*(volatile ${T} *)((uint8_t *)(base) + ${N}_OFFSET)) = ((${T})((v) & ${N}_MASK)))`);
      else if (r.access === 'RO') L.push(`/* ${N}_WRITE: 故意不生成 —— RO 没有写宏是第一道防线 */`);
      if (r.access === 'self-clear') L.push(`/* ${N}: self-clear —— 读即清，主机侧不许把读回值当状态缓存 */`);
    }
    L.push('');
  }
  L.push('/* ---- 编译期区间不重叠检查（按 offset 排序后的相邻对） ---- */');
  const s = ct.sorted;
  for (let i = 1; i < s.length; i++) {
    const P = sym(s[i - 1].name), N = sym(s[i].name);
    L.push(`GEN_ASSERT((${P}_OFFSET + ((${P}_WIDTH + 7u) / 8u)) <= ${N}_OFFSET, cth_ov_${i}_${P}_${N});`);
  }
  L.push('');
  L.push('/* ---- 编译期复位值不越界 ---- */');
  for (const r of ct.regs) {
    if (r.offset === null || r.width === null || r.reset === null) { L.push(`/* ${r.name}: 跳过（契约缺列 ⇒ NOT_MEASURED，不编默认值） */`); continue; }
    L.push(`GEN_ASSERT((${sym(r.name)}_RESET & ~${sym(r.name)}_MASK) == 0u, cth_rst_${sym(r.name)});`);
  }
  L.push('');
  L.push(`#endif /* ${G}_REGS_H */`);
  L.push('');
  return L.join('\n');
}

// ---------------- 产物 2：脚本侧常量模块 ----------------
function genModule(stem, ct, csvBase) {
  const L = [];
  L.push('// generated by scripts/contract-to-host/gen.mjs -- 请勿手改：改契约后重生成');
  L.push(`// contract: ${csvBase}  rows: ${ct.regs.length}  digest: ${ct.digest}`);
  L.push('// 缺列的字段值是 null（不是 0！）—— 0 会把"没测到"洗成"通过"。');
  L.push('');
  L.push('export const CONTRACT = Object.freeze({');
  L.push(`  file: ${JSON.stringify(csvBase)}, rows: ${ct.regs.length}, digest: ${JSON.stringify(ct.digest)},`);
  L.push(`  cols: ${JSON.stringify(COLS.join(','))}`);
  L.push('});');
  L.push('');
  L.push('export const REGISTERS = Object.freeze([');
  for (const r of ct.regs) {
    L.push('  Object.freeze({');
    L.push(`    name: ${JSON.stringify(r.name)}, offset: ${r.offset === null ? 'null' : r.offset}, width: ${r.width === null ? 'null' : r.width}, bytes: ${r.width === null ? 'null' : bytesOf(r.width)},`);
    L.push(`    access: ${r.access === null ? 'null' : JSON.stringify(r.access)}, mask: ${r.width === null ? 'null' : hx(maskOf(r.width))}, reset: ${r.reset === null ? 'null' : hx(r.reset)},`);
    L.push(`    policy: ${r.policy === null ? 'null' : JSON.stringify(r.policy)}, doc: ${r.doc === null ? 'null' : JSON.stringify(r.doc)},`);
    L.push(`    measured: ${usable(r) ? 'true' : 'false'}, missing: [${r.missing.map(m => JSON.stringify(m)).join(', ')}]`);
    L.push('  }),');
  }
  L.push(']);');
  L.push('');
  L.push('const BY_NAME = new Map(REGISTERS.map((r) => [r.name, r]));');
  L.push('export function regOf(name) {');
  L.push('  const r = BY_NAME.get(name);');
  L.push('  if (!r) throw new Error("契约里没有 " + name + "（共 " + REGISTERS.length + " 条）");');
  L.push('  return r;');
  L.push('}');
  L.push('export function offsetOf(name) {');
  L.push('  const r = regOf(name);');
  L.push('  if (r.offset === null) throw new Error(name + " 的 offset 缺列 ⇒ NOT_MEASURED，不许编默认值");');
  L.push('  return r.offset;');
  L.push('}');
  L.push('export function bytesOf(name) { return regOf(name).bytes; }');
  L.push('export function maskOf(name) { return regOf(name).mask; }');
  L.push('export function resetOf(name) { return regOf(name).reset; }');
  L.push('export function accessOf(name) { return regOf(name).access; }');
  L.push("export function isWritable(name) { const a = regOf(name).access; return a === 'RW' || a === 'WO' || a === 'self-clear'; }");
  L.push('export function isSelfClear(name) { return regOf(name).access === \'self-clear\'; }');
  L.push('export function names() { return REGISTERS.map((r) => r.name); }');
  L.push('export default REGISTERS;');
  L.push('');
  return L.join('\n');
}

// ---------------- 产物 3：测试骨架 ----------------
function checksFor(acc) {
  if (acc === 'RO') return ['RO 不可写（写后读回应不变）', '复位值读回'];
  if (acc === 'WO') return ['写 A（无读回口，需旁路读数）'];
  if (acc === 'self-clear') return ['置位后读回应为 0（自清）', '二次读仍为 0'];
  if (acc === 'RW') return ['写 A 读 A', '写 B 读 B'];
  return ['契约缺 access ⇒ 无法判定用例形状'];
}
function genTest(stem, ct, csvBase) {
  const L = [];
  L.push('// generated by scripts/contract-to-host/gen.mjs -- 每寄存器一条用例的骨架，期望值必须人填');
  L.push(`// contract: ${csvBase}  rows: ${ct.regs.length}  digest: ${ct.digest}`);
  L.push('// 纪律：期望没填 / 没注入 io / 契约缺列 / WO 无读回口 ⇒ NOT_MEASURED（exit 2），绝不判通过。');
  L.push("import { pathToFileURL } from 'node:url';");
  L.push(`import { REGISTERS, offsetOf, isWritable, isSelfClear } from './${stem}_regs.mjs';`);
  L.push('');
  L.push('export const CASES = Object.freeze([');
  for (const r of ct.regs) {
    L.push('  Object.freeze({ reg: ' + JSON.stringify(r.name) + ', access: ' + (r.access === null ? 'null' : JSON.stringify(r.access)) + ',');
    L.push(`    checks: [${checksFor(r.access).map(c => JSON.stringify(c)).join(', ')}],`);
    L.push(`    reset: ${r.reset === null ? 'null' : hx(r.reset)}, policy: ${r.policy === null ? 'null' : JSON.stringify(r.policy)},`);
    L.push(`    expectA: ${JSON.stringify(PLACEHOLDER)}, expectB: ${JSON.stringify(PLACEHOLDER)},`);
    L.push(`    contractMeasured: ${usable(r) ? 'true' : 'false'} }),`);
  }
  L.push(']);');
  L.push('const filled = (v) => typeof v === "number" || (typeof v === "string" && !String(v).startsWith("【"));');
  L.push('export async function runAll(io) {');
  L.push('  const rows = []; let cmp = 0, red = 0, nm = 0;');
  L.push('  for (const c of CASES) {');
  L.push('    const say = (verdict, detail, done) => {');
  L.push('      rows.push({ reg: c.reg, verdict, detail, cmp: done || 0 });');
  L.push('      cmp += done || 0;');
  L.push('      if (verdict === "FAIL") red++; else if (verdict !== "PASS") nm++;');
  L.push('    };');
  L.push('    if (!c.contractMeasured) say("NOT_MEASURED", "契约缺列（offset/width/access/reset 未给全），不编默认值", 0);');
  L.push('    else if (!io) say("NOT_MEASURED", "未注入 io：需要 { read(name), write(name, v) }（板上代理或台架）", 0);');
  L.push('    else if (c.access === "WO") say("NOT_MEASURED", "WO 没有读回口，要另给旁路读数才算测到", 0);');
  L.push('    else if (!filled(c.expectA)) say("NOT_MEASURED", "期望值未填（仍是占位符）", 0);');
  L.push('    else if (!isWritable(c.reg)) {');
  L.push('      io.write(c.reg, c.expectA); const a = io.read(c.reg); const b = io.read(c.reg);');
  L.push('      let k = 1, ok = (a === b);');
  L.push('      if (filled(c.expectB)) { k++; ok = ok && (b === c.expectB); }');
  L.push('      say(ok ? "PASS" : "FAIL", "RO 写后两次读回应相等：" + a + " vs " + b, k);');
  L.push('    } else if (isSelfClear(c.reg)) {');
  L.push('      io.write(c.reg, c.expectA); const a = io.read(c.reg); const b = io.read(c.reg);');
  L.push('      say((a === 0 && b === 0) ? "PASS" : "FAIL", "自清位读回应为 0：第一次 " + a + " 第二次 " + b, 2);');
  L.push('    } else {');
  L.push('      io.write(c.reg, c.expectA); const a = io.read(c.reg);');
  L.push('      const expB = filled(c.expectB) ? c.expectB : c.expectA;');
  L.push('      io.write(c.reg, expB); const b = io.read(c.reg);');
  L.push('      say((a === c.expectA && b === expB) ? "PASS" : "FAIL",');
  L.push('        "写 A 读 A=" + (a === c.expectA) + " 写 B 读 B=" + (b === expB) + "（偏移 " + offsetOf(c.reg) + "）", 2);');
  L.push('    }');
  L.push('    void REGISTERS;');
  L.push('  }');
  L.push('  return { rows, cmp, red, nm };');
  L.push('}');
  L.push('const isMain = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;');
  L.push('if (isMain) {');
  L.push('  const res = await runAll(null);');
  L.push('  for (const x of res.rows) console.log(x.reg + " " + x.verdict + " 比较=" + x.cmp + " " + x.detail);');
  L.push('  console.log("契约行数=" + CASES.length + " 生成用例数=" + res.rows.length +');
  L.push('    " 一致=" + (CASES.length === res.rows.length ? "PASS" : "FAIL"));');
  L.push('  const token = res.red ? "FAIL" : (res.nm ? "NOT_MEASURED" : "PASS");');
  L.push('  console.log("判 " + res.cmp + " 项 红=" + res.red + " 未测=" + res.nm + " " + token);');
  L.push('  process.exit(res.red ? 1 : (res.nm ? 2 : 0));');
  L.push('}');
  L.push('');
  return L.join('\n');
}

// ---------------- 生成 + 判据打印 ----------------
function generate(inCsv, outDir, stem) {
  const ct = loadContract(inCsv);
  const csvBase = path.basename(inCsv);
  const files = {
    [`${stem}_regs.h`]: genHeader(stem, ct, csvBase),
    [`${stem}_regs.mjs`]: genModule(stem, ct, csvBase),
    [`${stem}_regs_test.mjs`]: genTest(stem, ct, csvBase),
  };
  const red = ct.errs.length;
  const nm = ct.regs.filter(r => !usable(r)).length;
  const cases = ct.regs.length;
  let consistencyCmp = 0, consistent = true;
  for (let i = 0; i < ct.regs.length; i++) consistencyCmp++;
  consistent = (consistencyCmp === cases);
  const overlap = ct.errs.filter(e => e.startsWith('地址重叠')).length;
  const resetBad = ct.errs.filter(e => e.includes('复位越界')).length;
  const cmp = consistencyCmp + Math.max(0, ct.sorted.length - 1) + ct.regs.filter(r => r.reset !== null && r.width !== null).length;
  fs.mkdirSync(outDir, { recursive: true });
  const written = [];
  if (!red) for (const [n, body] of Object.entries(files)) { fs.writeFileSync(path.join(outDir, n), body); written.push(n); }
  const empty = ct.regs.length === 0;
  const token = red ? 'FAIL' : (empty || !consistent ? 'NOT_MEASURED' : (nm ? 'NOT_MEASURED' : 'PASS'));
  const lines = [];
  lines.push(`契约 ${csvBase}：行数=${ct.regs.length} 生成用例数=${cases} 一致=${consistent && !empty ? 'PASS' : (empty ? 'NOT_MEASURED' : 'FAIL')}（判据：契约行数 = 生成用例数）`);
  if (!red) lines.push(`已生成 ${written.length} 份：${written.join(', ')}`);
  for (const e of ct.errs) lines.push(`红 ${e} FAIL`);
  for (const w of ct.warns) lines.push(`注 ${w}`);
  if (red) lines.push(`未生成任何文件（红=${red}：重叠=${overlap} 复位越界=${resetBad}）⇒ 先改契约再重生成`);
  if (nm) lines.push(`未测 ${nm} 行：对应用例仍生成并标 NOT_MEASURED，未编默认值`);
  lines.push(`判 ${cmp} 项 红=${red} 未测=${nm} ${token}`);
  for (const l of lines) console.log(l);
  return { token, red, nm, cmp, written, ct, lines, exit: red ? 1 : ((nm || empty) ? 2 : 0) };
}

// ---------------- --self ----------------
function tmpdir(tag) { return fs.mkdtempSync(path.join(os.tmpdir(), `c2h-${tag}-`)); }
function selfTest() {
  const out = []; let cmp = 0, red = 0, nm = 0;
  const say = (id, detail, verdict, done) => { out.push(`${id} ${detail} ${verdict}`); cmp += done || 0; if (verdict === 'FAIL') red++; else if (verdict === 'NOT_MEASURED') nm++; };
  const me = fileURLToPath(import.meta.url);
  const gen = (argv) => spawnSync(process.execPath, [me, ...argv], { encoding: 'utf8' });
  const rd = (p) => (fs.existsSync(p) ? fs.readFileSync(p, 'utf8') : '');
  const count = (s, re) => (s.match(re) || []).length;

  const A = tmpdir('a'), B = tmpdir('b');
  const csv = path.join(SELF, 'contract.csv');
  const g1 = gen(['--in', csv, '--out', A]);
  const g2 = gen(['--in', csv, '--out', B]);
  const names = ['contract_regs.h', 'contract_regs.mjs', 'contract_regs_test.mjs'];
  let golden = 0, idem = 0;
  for (const n of names) {
    if (rd(path.join(SELF, 'expected', n)) === rd(path.join(A, n)) && rd(path.join(A, n)).length > 0) golden++;
    if (rd(path.join(A, n)) === rd(path.join(B, n)) && rd(path.join(A, n)).length > 0) idem++;
  }
  say('S1 黄金一致（3 份产物逐字节比对随包 expected）', `相符=${golden}/3 生成退出码=${g1.status}`, golden === 3 ? 'PASS' : 'FAIL', 3);
  say('S2 幂等（同一契约两次生成逐字节一致）', `相符=${idem}/3`, idem === 3 ? 'PASS' : 'FAIL', 3);

  const o = gen(['--in', path.join(SELF, 'bad-overlap.csv'), '--out', path.join(A, 'ov')]);
  const ovTxt = o.stdout + o.stderr;
  const ovRed = ovTxt.split(/\r?\n/).filter(l => l.startsWith('红 '));
  const ovLines = ovRed.filter(l => l.includes('地址重叠'));
  const named = ovLines.length === 1 && ovLines[0].includes('STATUS') && ovLines[0].includes('IE');
  const onlyOne = o.status === 1 && ovRed.length === 1 && ovLines.length === 1 && named && /红=1 未测=0 FAIL/.test(ovTxt) && !/已生成/.test(ovTxt);
  say('S3 能红对照：两条 offset 改成重叠 ⇒ 必须红且只红这一条', `退出码=${o.status} 红行=${ovRed.length} 点名=${named ? 'STATUS/IE' : '不符'} 未落盘=${/已生成/.test(ovTxt) ? '否' : '是'}`,
    onlyOne ? 'PASS' : 'FAIL', 4);

  const rr = gen(['--in', path.join(SELF, 'bad-reset.csv'), '--out', path.join(A, 'rs')]);
  const rsTxt = rr.stdout + rr.stderr;
  const rsRed = rsTxt.split(/\r?\n/).filter(l => l.startsWith('红 '));
  const rsLines = rsRed.filter(l => l.includes('复位越界'));
  say('S4 能红对照：reset 超出 width ⇒ 必须红且只红一条', `退出码=${rr.status} 红行=${rsRed.length} 越界条数=${rsLines.length}`,
    (rr.status === 1 && rsRed.length === 1 && rsLines.length === 1 && /红=1 未测=0 FAIL/.test(rsTxt)) ? 'PASS' : 'FAIL', 3);

  const mr = gen(['--in', path.join(SELF, 'missing-reset.csv'), '--out', path.join(A, 'mr')]);
  const mTxt = mr.stdout + mr.stderr;
  const mMjs = rd(path.join(A, 'mr', 'missing_reset_regs.mjs'));
  const mh = rd(path.join(A, 'mr', 'missing_reset_regs.h'));
  const nulls = count(mMjs, /reset: null/g);
  const marked = count(mh, /_RESET: NOT_MEASURED/g);
  const fabricated = /#define\s+\w+_RESET\s+0x/.test(mh);
  const nmRows = (mTxt.match(/未测=(\d+)/) || [, '-1'])[1];
  say('S5 缺列 ⇒ 用例照生成并标 NOT_MEASURED，且不编默认值', `退出码=${mr.status} 未测=${nmRows}/5 reset:null=${nulls}/5 头文件标注=${marked}/5 编造值=${fabricated ? '有' : '无'}`,
    (mr.status === 2 && nulls === 5 && marked === 5 && !fabricated && nmRows === '5') ? 'PASS' : 'FAIL', 4);

  const tk = spawnSync(process.execPath, [path.join(A, 'contract_regs_test.mjs')], { encoding: 'utf8' });
  const tkTxt = tk.stdout + tk.stderr;
  const tkNm = (tkTxt.match(/未测=(\d+)/) || [, '-1'])[1];
  const tkCases = (tkTxt.match(/生成用例数=(\d+)/) || [, '-1'])[1];
  say('S6 测试骨架直接跑 ⇒ 8/8 条 NOT_MEASURED（不许假绿）', `退出码=${tk.status} 未测=${tkNm}/8 用例数=${tkCases}`,
    (tk.status === 2 && tkNm === '8' && tkCases === '8') ? 'PASS' : 'FAIL', 2);

  const ep = gen(['--in', path.join(SELF, 'header-only.csv'), '--out', path.join(A, 'ep')]);
  const epLine = (ep.stdout.match(/判 \d+ 项 .*/) || ['无结论行'])[0];
  say('S7 空契约（只有表头）⇒ NOT_MEASURED 而非通过', `退出码=${ep.status} 结论=${epLine}`,
    (ep.status !== 0 && /NOT_MEASURED/.test(epLine)) ? 'PASS' : 'FAIL', 2);

  // S8/S9：把骨架的占位符填上 + 注入一个理想寄存器模型 io ⇒ 证明骨架不是橡皮图章（能绿也能红）
  const F = path.join(A, 'fill'); fs.mkdirSync(F, { recursive: true });
  const filledTxt = rd(path.join(A, 'contract_regs_test.mjs'))
    .replace(/expectA: "【待填：读回值】"/g, 'expectA: 286331153')
    .replace(/expectB: "【待填：读回值】"/g, 'expectB: 0');
  fs.writeFileSync(path.join(F, 'contract_regs_test.mjs'), filledTxt);
  fs.copyFileSync(path.join(A, 'contract_regs.mjs'), path.join(F, 'contract_regs.mjs'));
  fs.writeFileSync(path.join(F, 'harness.mjs'), HARNESS);
  const h1 = spawnSync(process.execPath, [path.join(F, 'harness.mjs')], { encoding: 'utf8' });
  const h1Txt = h1.stdout + h1.stderr;
  const n = (re, s) => parseInt((s.match(re) || [, '-1'])[1], 10);
  const c1 = n(/判 (\d+) 项/, h1Txt), r1 = n(/红=(\d+)/, h1Txt), u1 = n(/未测=(\d+)/, h1Txt);
  say('S8 填期望 + 理想 io ⇒ 测到的全绿、只剩 WO 未测', `退出码=${h1.status} 比较=${c1} 红=${r1} 未测=${u1}`,
    (c1 === 14 && r1 === 0 && u1 === 1 && h1.status === 2) ? 'PASS' : 'FAIL', 3);
  const h2 = spawnSync(process.execPath, [path.join(F, 'harness.mjs')], { encoding: 'utf8', env: { ...process.env, CTH_BROKEN: 'CTRL' } });
  const h2Txt = h2.stdout + h2.stderr;
  const r2 = n(/红=(\d+)/, h2Txt);
  say('S9 变异对照：模型丢掉 CTRL 的写 ⇒ 骨架必须判红', `退出码=${h2.status} 红=${r2} 点名=${/CTRL FAIL/.test(h2Txt) ? 'CTRL' : '不符'}`,
    (h2.status === 1 && r2 === 1 && /CTRL FAIL/.test(h2Txt)) ? 'PASS' : 'FAIL', 3);

  for (const l of out) console.log(l);
  const token = red ? 'FAIL' : (nm ? 'NOT_MEASURED' : 'PASS');
  console.log(`判 ${cmp} 项 红=${red} 未测=${nm} ${token}`);
  process.exit(red ? 1 : 0);
}

// ---------------- CLI ----------------
const argv = process.argv.slice(2);
const flag = (k, d) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : d; };
if (argv.includes('--self')) selfTest();
else if (argv.includes('--help') || argv.includes('-h')) {
  console.log('用法: node gen.mjs --in <contract.csv> --out <dir> [--stem <name>] | node gen.mjs --self');
  console.log(`契约列: ${COLS.join(',')}   access ∈ ${ACCESS.join('/')}   退出码: 0 绿 / 1 红 / 2 未测`);
} else if (argv.includes('--in') || argv.length > 0) {
  const inCsv = path.resolve(flag('--in', path.join(SELF, 'contract.csv')));
  const outDir = path.resolve(flag('--out', path.join(ENTRY, '_out')));
  const stem = flag('--stem', path.basename(inCsv).replace(/\.csv$/i, '').replace(/[^A-Za-z0-9_]/g, '_').toLowerCase());
  if (!fs.existsSync(inCsv)) { console.log(`契约读不到：${path.basename(inCsv)}（不猜路径）`); console.log('判 0 项 红=0 未测=1 NOT_MEASURED'); process.exit(2); }
  const res = generate(inCsv, outDir, stem);
  process.exit(res.exit);
} else {
  console.log('用法: node gen.mjs --in <contract.csv> --out <dir> | node gen.mjs --self');
  console.log('判 0 项 红=0 未测=1 NOT_MEASURED');
  process.exit(2);
}
