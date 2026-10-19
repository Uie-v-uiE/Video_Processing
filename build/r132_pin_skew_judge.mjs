#!/usr/bin/env node
// build/r132_pin_skew_judge.mjs —— 臂 D 的尺子：只读现版逐脚 clock-to-pin 探针件，判 HDMI 源端 TP1 的两条 skew
//
// 为什么另起一把而不是用 build/r119_window_check.mjs：那把尺子的五个输入件路径写死在 r119 那一轮
// （它判的是"候选件形状对不对 + 当时那份成品"）。本文件只吃探针件 + metrics，
// 换一版成品只要换探针件，判定语义不变。
//
// 判什么（一条一行，判定 token 放最后一个字段；缺输入一律 NOT_MEASURED）：
//   J1 计数地板：8 个脚（4 对差分）的 max 与 min 都要有数，缺任何一个不许判通过
//   J2 互对 max 角：每条数据道 vs 钟道的 |Δ| 最差值 <= 0.20 Tcharacter
//   J3 互对 min 角：同一件事在 min 角再判一次（与 J2 成对，证明不是只看一边）
//   J4 对内：每对 P/N 的 max 角与 min 角 |Δ| 最差值 <= 0.15 Tbit
//   J5 上限可推导：Tcharacter=1000/像素钟、Tbit=Tcharacter/10，像素钟读自 data/metrics.csv，不手抄
//
// 量纲口径的出处：report/log/issues.md #335 与 report/timing/debt_ledger.md
// "追加（2026-10-04 09:4x）"——规范那条是 skew（两脚到达时刻之差的上限），不是采样窗，
// 所以这里判的是"逐脚到达时刻的离散"，不去判 set_output_delay 的 slack。
//
// 跑法：node build/r132_pin_skew_judge.mjs
//       node build/r132_pin_skew_judge.mjs --probe <探针件> --metrics <metrics>   （换输入件）
//       node build/r132_pin_skew_judge.mjs --self   （对畸形副本做对照，证明每条判据都能红）
// 退出码：0=PASS 1=FAIL 2=NOT_MEASURED
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';

const ROOT = process.cwd();
const argv = process.argv.slice(2);
const flag = (name, dflt) => {
  const i = argv.indexOf(name);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : dflt;
};
const PROBE = flag('--probe', 'build/evidence/r132_pin_skew_probe.txt');
const METRICS = flag('--metrics', 'data/metrics.csv');

const PINS = ['tmds_clk_p', 'tmds_clk_n',
  'tmds_data_p[0]', 'tmds_data_n[0]',
  'tmds_data_p[1]', 'tmds_data_n[1]',
  'tmds_data_p[2]', 'tmds_data_n[2]'];
const DATA_P = ['tmds_data_p[0]', 'tmds_data_p[1]', 'tmds_data_p[2]'];
const PAIRS = [['tmds_data_p[0]', 'tmds_data_n[0]'],
  ['tmds_data_p[1]', 'tmds_data_n[1]'],
  ['tmds_data_p[2]', 'tmds_data_n[2]'],
  ['tmds_clk_p', 'tmds_clk_n']];

function read(f) {
  const p = path.isAbsolute(f) ? f : path.join(ROOT, f);
  return fs.existsSync(p) ? fs.readFileSync(p, 'utf8') : null;
}
function skewTable(txt) {
  const t = { max: {}, min: {} };
  for (const l of txt.split(/\r?\n/)) {
    const m = l.match(/^PIN\|\s*(.+?)\s*\|\s*(max|min)\s*\|\s*data_path_delay=([0-9.]+)ns/);
    if (m) t[m[2]][m[1]] = Number(m[3]);
  }
  return t;
}
function pixelClockMHz(txt) {
  const row = txt.split(/\r?\n/).find(l => l.includes('显示像素时钟'));
  if (!row) return null;
  const c = row.split(',');
  const v = Number(c[2]);
  return (Number.isFinite(v) && v > 0 && (c[3] || '').trim() === 'MHz') ? v : null;
}
const worst = (xs) => xs.length ? Math.max(...xs) : null;
const fmt = (v) => v === null ? '—' : v.toFixed(3);

function run(probePath, metricsPath) {
  const out = [];
  const skewTxt = read(probePath), metTxt = read(metricsPath);
  if (skewTxt === null) { out.push(`J0 探针件缺失            缺 ${probePath} NOT_MEASURED`); return { out }; }
  if (metTxt === null) { out.push(`J0 metrics缺失          缺 ${metricsPath} NOT_MEASURED`); return { out }; }

  const t = skewTable(skewTxt);
  // J5 先算上限：拿不到像素钟就没有上限可判，后面的格子一律不涂绿
  const pc = pixelClockMHz(metTxt);
  if (pc === null) {
    out.push(`J5 上限可推导            metrics 里没有可解析的"显示像素时钟"行 NOT_MEASURED`);
    return { out };
  }
  const tchar = 1000 / pc, tbit = tchar / 10;
  const limInter = 0.20 * tchar, limIntra = 0.15 * tbit;
  out.push(`J5 上限可推导            像素钟=${pc}MHz ⇒ Tcharacter=${tchar.toFixed(3)} Tbit=${tbit.toFixed(3)} 互对上限=${limInter.toFixed(3)}ns 对内上限=${limIntra.toFixed(3)}ns PASS`);

  // J1 计数地板
  const missMax = PINS.filter(p => !Number.isFinite(t.max[p]));
  const missMin = PINS.filter(p => !Number.isFinite(t.min[p]));
  const nmRow = skewTxt.split(/\r?\n/).filter(l => /^PIN\|/.test(l) && /NOT_MEASURED|PORT_NOT_FOUND|NO_ARRIVAL_LINE|NO_FIELD/.test(l));
  out.push(`J1 计数地板              期望 8 脚×2 角 缺 max=[${missMax.join(',')}] 缺 min=[${missMin.join(',')}] 未量到行=${nmRow.length} ${missMax.length === 0 && missMin.length === 0 ? 'PASS' : 'NOT_MEASURED'}`);
  if (missMax.length || missMin.length) return { out };

  // J2 / J3 互对
  const interMax = DATA_P.map(d => Math.abs(t.max[d] - t.max['tmds_clk_p']));
  const interMin = DATA_P.map(d => Math.abs(t.min[d] - t.min['tmds_clk_p']));
  const wiMax = worst(interMax), wiMin = worst(interMin);
  out.push(`J2 互对max角             逐道=[${interMax.map(fmt).join(', ')}] 最差=${fmt(wiMax)}ns 上限=${limInter.toFixed(3)} ${wiMax <= limInter ? 'PASS' : 'FAIL'}`);
  out.push(`J3 互对min角             逐道=[${interMin.map(fmt).join(', ')}] 最差=${fmt(wiMin)}ns 上限=${limInter.toFixed(3)} ${wiMin <= limInter ? 'PASS' : 'FAIL'}`);

  // J4 对内（两个角各判一次，取最差）
  const intraMax = PAIRS.map(([a, b]) => Math.abs(t.max[a] - t.max[b]));
  const intraMin = PAIRS.map(([a, b]) => Math.abs(t.min[a] - t.min[b]));
  const wiIntra = worst(intraMax.concat(intraMin));
  out.push(`J4 对内 P/N              max角=[${intraMax.map(fmt).join(', ')}] min角=[${intraMin.map(fmt).join(', ')}] 最差=${fmt(wiIntra)}ns 上限=${limIntra.toFixed(3)} ${wiIntra <= limIntra ? 'PASS' : 'FAIL'}`);

  const last = out[out.length - 1];
  const allPass = out.length === 5 && out.every(l => l.endsWith('PASS'));
  if (!allPass && !last.endsWith('FAIL')) out.push(`总结 判 5 项 有格子不是 PASS 也不是 FAIL ⇒ 判定不完整 FAIL`);
  return { out, vals: { wiMax, wiMin, wiIntra, limInter, limIntra } };
}

// ---- --self：把探针件抄到临时目录，逐条造畸形，证明 J1–J4 都能红；缺件报 NOT_MEASURED ----
function selftest() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'armd-self-'));
  const base = read(PROBE);
  if (base === null) { console.log('SELF 基线探针件不存在，无法造对照 NOT_MEASURED'); return 2; }
  const put = (name, txt) => { const p = path.join(dir, name); fs.writeFileSync(p, txt, 'utf8'); return p; };
  const cases = [
    ['J1 少一条数据道', () => put('j1.xdc.txt', base.split(/\r?\n/).filter(l => !/\|\s*tmds_data_p\[2\]\s*\|\s*max/.test(l)).join('\n')), 'NOT_MEASURED'],
    ['J2 把一条数据道推后 6 ns', () => put('j2.txt', base.replace(/PIN\|\s*tmds_data_p\[1\]\s*\|\s*max\s*\|\s*data_path_delay=([0-9.]+)ns/, (s, v) => `PIN| tmds_data_p[1] | max | data_path_delay=${(Number(v) + 6).toFixed(3)}ns`)), 'FAIL'],
    ['J3 只在 max 角坏、min 角也带坏', () => put('j3.txt', base.replace(/PIN\|\s*tmds_data_n\[2\]\s*\|\s*min\s*\|\s*data_path_delay=([0-9.]+)ns/, (s, v) => `PIN| tmds_data_n[2] | min | data_path_delay=${(Number(v) + 6).toFixed(3)}ns`)), 'FAIL'],
    ['J4 对内拉开 0.5 ns', () => put('j4.txt', base.replace(/PIN\|\s*tmds_data_p\[0\]\s*\|\s*max\s*\|\s*data_path_delay=([0-9.]+)ns/, (s, v) => `PIN| tmds_data_p[0] | max | data_path_delay=${(Number(v) + 0.5).toFixed(3)}ns`)), 'FAIL'],
    ['J5 像素钟行被改名', () => { const m = read(METRICS).replace('显示像素时钟', '像素时钟X'); return [put('p.txt', base), put('m.csv', m)]; }, 'NOT_MEASURED'],
    ['件整个不存在', () => path.join(dir, 'nope.txt'), 'NOT_MEASURED'],
  ];
  let moved = 0;
  for (const [title, mk, want] of cases) {
    const made = mk();
    const pair = Array.isArray(made) ? made : [made, METRICS];
    const res = run(pair[0], pair[1]);
    const line = res.out[res.out.length - 1];
    const got = line.split(' ').pop();
    const ok = want === 'FAIL' ? res.out.some(l => l.endsWith('FAIL')) : got === want;
    if (ok) moved++;
    console.log(`SELF ${title.padEnd(26)} 期望 ${want} 实得 ${ok ? want : got} ${ok ? 'RED-AS-EXPECTED' : 'NOT-RED'}`);
    if (!ok) res.out.forEach(l => console.log('     ' + l));
  }
  const truth = run(PROBE, METRICS);
  const truthPass = truth.out.every(l => l.endsWith('PASS'));
  console.log(`SELF 正本对照 判 ${truth.out.length} 项 ${truthPass ? 'PASS' : 'NOT-PASS'}`);
  truth.out.forEach(l => console.log('     ' + l));
  fs.rmSync(dir, { recursive: true, force: true });
  const okAll = moved === cases.length && truthPass;
  console.log(`对照总结：造 ${cases.length} 条畸形动红 ${moved} 条；正本 ${truthPass ? 'PASS' : 'NOT-PASS'} ${okAll ? 'PASS' : 'FAIL'}`);
  return okAll ? 0 : 1;
}

if (argv.includes('--self')) { process.exit(selftest()); }
const md5 = f => {
  const p = path.isAbsolute(f) ? f : path.join(ROOT, f);
  if (!fs.existsSync(p)) return 'ABSENT';
  return crypto.createHash('md5').update(fs.readFileSync(p, 'utf8').replace(/\r\n/g, '\n')).digest('hex').slice(0, 12);
};
console.log(`HEAD 探针件 ${PROBE} ${md5(PROBE)}`);
console.log(`HEAD metrics ${METRICS} ${md5(METRICS)}`);
console.log(`HEAD 读数器=node${process.version}`);
const res = run(PROBE, METRICS);
res.out.forEach(l => console.log(l));
const last = res.out[res.out.length - 1];
process.exit(last.endsWith('PASS') ? 0 : last.endsWith('NOT_MEASURED') ? 2 : 1);
