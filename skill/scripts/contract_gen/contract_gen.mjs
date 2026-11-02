#!/usr/bin/env node
/**
 * skill/scripts/contract_gen/contract_gen.mjs
 * 从寄存器契约表生成主机侧调用骨架 + 测试骨架；表里没有的字段一律不臆造默认值 ⇒ 退出码 3
 *
 * 复跑（仓库根）：
 *   node skill/scripts/contract_gen/contract_gen.mjs \
 *     --contract skill/scripts/regmap_check/contract.tsv --out-dir skill/scripts/_out/gen
 *   node skill/scripts/_out/gen/regmap_host_stub.mjs        # 生成的测试骨架自己也能跑
 * 产物再用 node --check 复核（这条判据不是"看着像代码"，是真的过了一遍解析器）。
 *
 * 退出码：0=PASS 1=FAIL 2=NOT_MEASURED 3=前置不满足（含"契约缺字段"：缺就不生成）
 */
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const HELP = `用法: node contract_gen.mjs --contract FILE --out-dir DIR [--prefix NAME] [--help]
  --contract   与 regmap_check 同一张契约表（TSV）
  --out-dir    产物目录；拒绝 src/ sim/ build/ 等工程目录
  --prefix     产物文件名前缀，默认 regmap_host
  规则：10 个必填字段有一格是空 ⇒ 立刻退出 3，不生成、不补默认值。
退出码: 0=PASS 1=FAIL 2=NOT_MEASURED 3=前置不满足`;

const REQUIRED = ['offset', 'bits', 'access', 'reset', 'w_side_effect', 'r_side_effect',
                  'interrupt', 'unit_range', 'widest_input', 'clock_domain'];
const PROTECTED = ['src/', 'sim/', 'build/', 'board/', 'data/', 'report/', 'docs/'];

const argv = process.argv.slice(2);
const opt = {};
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--help' || a === '-h') { console.log(HELP); process.exit(0); }
  if (a.startsWith('--')) { opt[a.slice(2)] = argv[++i]; continue; }
  console.log('GEN 前置不满足 无法识别的参数 ' + a + ' NOT_MEASURED');
  console.log('GEN 前置不满足 判 0 项 FAIL'); process.exit(3);
}
const buf = [];
let printed = 0;
function bail(code, head, msg, verdict) {
  for (const l of buf) console.log(l);
  console.log(`GEN ${head} ${msg} 判 ${printed + nMade} 项 ${verdict}`);
  process.exit(code);
}
function pre(m) { bail(3, '前置不满足', m, 'FAIL'); }
function nm(m) { console.log(`GEN 读不到输入 ${m} NOT_MEASURED`); console.log('GEN 读不到输入 判 0 项 NOT_MEASURED'); process.exit(2); }
if (!opt.contract) nm('缺 --contract');
if (!opt['out-dir']) nm('缺 --out-dir（生成物必须写独立目录，不写工程目录）');
if (!fs.existsSync(opt.contract)) nm(`--contract ${opt.contract} 不存在`);
if (fs.statSync(opt.contract).size === 0) nm(`--contract ${opt.contract} 是空文件`);
const outDir = String(opt['out-dir']).split(path.sep).join('/');
if (PROTECTED.some(x => outDir === x.replace(/\/$/, '') || outDir.startsWith(x))) pre(`--out-dir 指向工程目录 ${outDir}`);

let nMade = 0, nFail = 0, nNm = 0, nPass = 0;
function say(name, made, detail, verdict) {
  nMade += made;
  if (verdict === 'FAIL') nFail++; else if (verdict === 'NOT_MEASURED') nNm++; else nPass++;
  buf.push(`${name.padEnd(30)} 判 ${made} 项 ${detail} ${verdict}`);
}

const raw = fs.readFileSync(opt.contract, 'utf8').split(/\r?\n/).filter(l => l && !l.startsWith('#'));
if (raw.length < 2) nm(`契约表只有 ${raw.length} 行（表头或数据行缺失 ⇒ 没东西可生成）`);
const head = raw[0].split('\t').map(s => s.trim());
for (const k of REQUIRED) if (!head.includes(k)) pre(`契约表缺列 ${k}（缺列与缺值是两回事：都不许臆造，先补表）`);
const rows = raw.slice(1).map(l => {
  const c = l.split('\t'); const o = {};
  head.forEach((h, i) => { o[h] = (c[i] || '').trim(); });
  return o;
});
if (!rows.length) nm(`契约表 ${opt.contract} 没有数据行（空表不生成）`);

function parseBits(spec) {
  const s = String(spec).replace(/[[\]]/g, '').trim();
  const m = s.match(/^(\d+)(?::(\d+))?$/);
  if (!m) return null;
  const hi = Number(m[1]), lo = m[2] === undefined ? hi : Number(m[2]);
  if (lo > hi) return null;
  return { lo, hi, width: hi - lo + 1 };
}

// C1 必填字段：缺一格就点名到哪一行哪一列并退出 3（检查过的格子数照样打印，不许静默跳过）
{
  let made = 0, bad = 0; const det = [];
  rows.forEach((r, i) => {
    for (const k of REQUIRED) { made++; if (!r[k]) { bad++; det.push(`第${i + 1}行(${r.name || '无名'})缺 ${k}`); } }
  });
  say('C1_required_fields', made, `行=${rows.length} 检查=${made} 缺=${bad}${det.length ? ' 例:' + det.slice(0, 4).join(' | ') : ''}`, 'PASS?');
  buf[buf.length - 1] = buf[buf.length - 1].replace(/PASS\?$/, bad ? 'FAIL' : 'PASS');
  if (bad) bail(3, '契约缺字段', `缺 ${bad} 处 ⇒ 不生成、不补默认值`, 'FAIL');
}

// C3 最宽输入重推：从位域与量程自己算一遍再与表对账（放不下、超出位域、与量程不符都算红）
const derived = [];
{
  let made = 0, bad = 0, undec = 0; const det = [];
  rows.forEach((r, i) => {
    const p = parseBits(r.bits);
    const rg = (r.unit_range || '').match(/(-?\d+)\s*\.\.\s*(-?\d+)/);
    if (!p || !rg) { undec++; det.push(`第${i + 1}行(${r.name}):位域或量程读不出`); derived.push(null); return; }
    made += 3;
    const fieldMax = (1 << p.width) - 1;
    const rangeMax = Math.max(Number(rg[1]), Number(rg[2]));
    const declared = Number(r.widest_input);
    derived.push({ ...p, fieldMax, rangeMax, declared });
    if (rangeMax > fieldMax) { bad++; det.push(`${r.name}:量程上限 ${rangeMax} 大于位域上限 ${fieldMax}`); }
    if (!Number.isFinite(declared)) { bad++; det.push(`${r.name}:最宽输入不是数(${r.widest_input})`); }
    else if (declared !== rangeMax) { bad++; det.push(`${r.name}:表里写 ${declared}, 从量程重推是 ${rangeMax}`); }
    else if (declared > fieldMax) { bad++; det.push(`${r.name}:表里写 ${declared} 超出位域上限 ${fieldMax}`); }
  });
  say('C3_widest_input_recheck', made, `行=${rows.length} 判=${made} 破=${bad} 判不了=${undec}${det.length ? ' 例:' + det.slice(0, 3).join(' | ') : ''}`,
      made === 0 ? 'NOT_MEASURED' : (bad ? 'FAIL' : (undec ? 'NOT_MEASURED' : 'PASS')));
}

// 生成产物（只有 C1/C3 都没红才写盘）
if (nFail) {
  for (const l of buf) console.log(l);
  console.log(`GEN 未生成 契约本身不自洽 ⇒ 不产出骨架 判 ${nMade} 项 未判 ${nNm} 项 红 ${nFail} 项 FAIL`);
  process.exit(1);
}
const prefix = opt.prefix || 'regmap_host';
fs.mkdirSync(outDir, { recursive: true });
const skPath = path.join(outDir, `${prefix}.mjs`);
const tstPath = path.join(outDir, `${prefix}_stub.mjs`);

const sk = [];
sk.push('// 由 skill/scripts/contract_gen/contract_gen.mjs 从契约表生成。',
        '// 字段值全部来自表里那一格；脚本没给任何字段补默认值（缺字段是退出码 3，不是空串）。',
        '// 主机侧写入函数由调用方注入（GPIO 整字 / AXI-Lite / 串口都行），本骨架不认识具体总线。',
        '',
        'export const REGISTERS = [');
rows.forEach((r, i) => {
  const d = derived[i];
  sk.push(`  // 名称=${r.name} 读写=${r.access} 复位值=${r.reset} 写副作用=${r.w_side_effect} 读副作用=${r.r_side_effect}`);
  sk.push(`  // 中断号=${r.interrupt} 单位与量程=${r.unit_range} 时钟域=${r.clock_domain}`);
  sk.push('  { name: ' + JSON.stringify(r.name) + ', offset: ' + JSON.stringify(r.offset) +
          ', bits: ' + JSON.stringify(r.bits) +
          ', width: ' + (d ? d.width : 0) +
          ', mask: 0x' + (d ? d.fieldMax : 0).toString(16) +
          ', widest: ' + (d ? d.declared : 'null') +
          ', lo: ' + (d ? d.lo : 0) +
          ', reset: ' + JSON.stringify(r.reset) +
          ', access: ' + JSON.stringify(r.access) +
          ', unit: ' + JSON.stringify(r.unit_range) +
          ', clockDomain: ' + JSON.stringify(r.clock_domain) +
          ', interrupt: ' + JSON.stringify(r.interrupt) +
          ', writeSideEffect: ' + JSON.stringify(r.w_side_effect) +
          ', readSideEffect: ' + JSON.stringify(r.r_side_effect) + ' },');
});
sk.push('];', '',
  'export function packWord(values) {',
  '  const word = { addr: REGISTERS[0].offset, value: 0 };',
  '  for (const r of REGISTERS) {',
  '    if (!(r.name in values)) continue;',
  '    const v = Number(values[r.name]);',
  '    if (!Number.isInteger(v) || v < 0 || v > r.widest)',
  '      throw new Error(`${r.name}: ${v} 超出契约里的最宽输入 ${r.widest}（量程 ${r.unit}）`);',
  '    word.value |= (v & r.mask) << r.lo;',
  '  }',
  '  return word;',
  '}',
  '',
  'export function unpackWord(raw) {',
  '  const out = {};',
  '  for (const r of REGISTERS) out[r.name] = (Number(raw) >>> r.lo) & r.mask;',
  '  return out;',
  '}', '');

const tst = [];
tst.push('// 测试骨架：复位值必须落在量程内；最宽输入必须塞得进位域；写最宽再解包应当回到自己。',
  '// 期望值是从表重推的，不是手抄的 —— 表若与 RTL/文档不一致，先跑 regmap_check.mjs 让它红。',
  `import { REGISTERS, packWord, unpackWord } from './${path.basename(skPath)}';`,
  '',
  'let n = 0, bad = 0;',
  'const check = (name, ok, detail) => { n++; if (!ok) { bad++; console.log(`FAIL ${name} ${detail}`); } else console.log(`PASS ${name} ${detail}`); };',
  'for (const r of REGISTERS) {',
  '  const rv = Number(r.reset);',
  '  check(`${r.name}_reset_in_range`, Number.isFinite(rv) && rv >= 0 && rv <= r.widest, `reset=${r.reset} 必须在 0..${r.widest}`);',
  '  check(`${r.name}_widest_fits_field`, r.widest <= r.mask, `widest=${r.widest} 位域上限=0x${r.mask.toString(16)}`);',
  '}',
  'for (const r of REGISTERS) {',
  '  let round = false;',
  '  try { round = unpackWord(packWord({ [r.name]: r.widest }).value)[r.name] === r.widest; } catch (e) { round = false; }',
  '  check(`${r.name}_roundtrip_widest`, round, `写最宽 ${r.widest} 再解包应当回到自己`);',
  '}',
  'console.log(`GEN_STUB 判 ${n} 项 未判 0 项 红 ${bad} 项 ${bad ? "FAIL" : "PASS"}`);',
  'process.exit(bad ? 1 : 0);', '');

fs.writeFileSync(skPath, sk.join('\n') + '\n', 'utf8');
fs.writeFileSync(tstPath, tst.join('\n') + '\n', 'utf8');

// C2 生成覆盖（成对）：应生成的行数、实际出现的行数、漏掉的行、多余的行，同一条里全出现
{
  const want = rows.length;
  const text = fs.readFileSync(skPath, 'utf8');
  const got = rows.filter(r => text.includes('name: ' + JSON.stringify(r.name))).length;
  const missing = rows.filter(r => !text.includes('name: ' + JSON.stringify(r.name))).map(r => r.name);
  say('C2_emit_coverage', want * 2,
      `应生成=${want} 实际=${got} 漏=${missing.length}${missing.length ? '(' + missing.slice(0, 3).join(',') + ')' : ''} 多余=${Math.max(0, got - want)}`,
      (got === want && missing.length === 0) ? 'PASS' : 'FAIL');
}

// C4 产物过解析器
{
  let made = 0, bad = 0; const det = [];
  for (const f of [skPath, tstPath]) {
    made++;
    try { execFileSync(process.execPath, ['--check', f], { stdio: 'pipe' }); det.push(`${path.basename(f)}:语法过`); }
    catch (e) { bad++; det.push(`${path.basename(f)}:语法不过 ` + String(e.stderr || e.message).split('\n')[0].slice(0, 60)); }
  }
  say('C4_generated_parses', made, det.join(' '), made === 0 ? 'NOT_MEASURED' : (bad ? 'FAIL' : 'PASS'));
}

// C5 单位与量程 + 时钟域 两维都进了产物（同一行两条都要在场才算通过）
{
  const text = fs.readFileSync(skPath, 'utf8');
  let made = 0, bad = 0; const det = [];
  for (const r of rows) {
    made += 2;
    const hasUnit = text.includes(JSON.stringify(r.unit_range));
    const hasDomain = text.includes(JSON.stringify(r.clock_domain));
    if (!hasUnit || !hasDomain) { bad++; det.push(`${r.name}:unit=${hasUnit ? 'y' : 'n'} domain=${hasDomain ? 'y' : 'n'}`); }
  }
  say('C5_units_and_domain_in_code', made, `行=${rows.length} 判=${made} 缺=${bad}${det.length ? ' 例:' + det.slice(0, 2).join(' ') : ''}`,
      made === 0 ? 'NOT_MEASURED' : (bad ? 'FAIL' : 'PASS'));
}

for (const l of buf) console.log(l);
const verdict = nFail ? 'FAIL' : (nNm ? 'NOT_MEASURED' : (nMade === 0 ? 'NOT_MEASURED' : 'PASS'));
console.log(`GEN ${skPath} ${tstPath} 判 ${nMade} 项 未判 ${nNm} 项 红 ${nFail} 项 ${verdict}`);
process.exit(verdict === 'PASS' ? 0 : verdict === 'FAIL' ? 1 : 2);
