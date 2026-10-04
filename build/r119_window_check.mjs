#!/usr/bin/env node
// build/r119_window_check.mjs —— HDMI 源端 TP1 窗（候选件 + 成品实测离散）的只读尺子
//
// 判什么（一条一行输出，判定 token 放在最后一个字段；缺输入一律 NOT_MEASURED）：
//   W1 数字可推导：XDC 里的半窗 == 0.20 × (1/像素钟)，像素钟读自 data/metrics.csv（不靠人眼抄数）
//   W2 对称成对：-max 与 -min 必须互为相反数（只判一侧=半成品，本仓库铁律）
//   W3 纯 SDC 子集：非注释行不得出现 if/foreach/puts/error/expr/while/proc（.xdc 里会被静默跳过，
//      实测 CRITICAL WARNING 见 build/evidence/r119_xdc_loads_probe2.txt）
//   W4 参考钟身份有凭据：XDC 用的时钟名必须逐字出现在只读探针件 r119_ser_clock_probe.txt 里
//   W5 射程正确：窗只挂 tmds_data_*（6 个端口名），且**不得**挂到 led/时钟道（借数字=伪造依据）
//   W6 默认不加载：build/tcl/build_system_axigpio.tcl 里该文件只能出现在 VP_R119_TMDS_WINDOW 开关块内
//   W7 互对离散（max 角）：成品上 每条数据道 vs 钟道 的 clock-to-pin 延迟差 ≤ 0.20 Tcharacter
//   W8 互对离散（min 角）：同一件事在 min 角再判一次（与 W7 成对，证明不是只看一边）
//   W9 对内离散：每对 P/N 的 clock-to-pin 延迟差 ≤ 0.15 Tbit
//   W10 计数地板：W7/W8 要 3 条数据道齐、W9 要 4 对差分齐，缺 lane 不许判通过
//
// W7–W10 的读数只来自一份**真跑过的探针件**（默认 build/evidence/r119_pin_skew_probe2.txt，
// 由 build/tcl/probe_tmds_pin_skew.tcl 的同类只读探针打在 system_top_routed.dcp 上产出）；
// 件不在就是 NOT_MEASURED，**绝不默认 0、绝不推断**。
//
// 跑法：node build/r119_window_check.mjs          （对当前工程）
//      node build/r119_window_check.mjs --self   （对临时畸形副本做对照，证明每条判据都能红）
// 退出码：0=PASS 1=FAIL 2=NOT_MEASURED 3=前置不满足
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';

const ROOT = process.cwd();
const XDC = 'src/constraints/r119_hdmi_source_window.xdc';
const METRICS = 'data/metrics.csv';
const PROBE = 'build/evidence/r119_ser_clock_probe.txt';
const BUILD_TCL = 'build/tcl/build_system_axigpio.tcl';
const SKEW = 'build/evidence/r119_pin_skew_probe2.txt';
const FORBIDDEN = /\b(if|foreach|puts|error|expr|while|proc)\b/;

let judged = 0;          // 判 N 项 = 做了多少次比较，不是通过了多少次
function read(f) {
  const p = path.isAbsolute(f) ? f : path.join(ROOT, f);   // fixture 用临时绝对路径
  if (!fs.existsSync(p)) return null;
  return fs.readFileSync(p, 'utf8');
}
function body(raw) {              // 去掉注释与空行；注释里可以随便写命令名
  return raw.split(/\r?\n/).map(s => s.replace(/##.*$/, '').replace(/(^|\s)#.*$/, ''))
    .filter(s => s.trim().length > 0);
}
// 解析探针件：`PIN| <name> | <max|min> | data_path_delay=<x>ns`
function skewTable(txt) {
  const t = { max: {}, min: {} };
  for (const l of txt.split(/\r?\n/)) {
    const m = l.match(/^PIN\|\s*(.+?)\s*\|\s*(max|min)\s*\|\s*data_path_delay=([0-9.]+)ns/);
    if (m) t[m[2]][m[1]] = Number(m[3]);
  }
  return t;
}

function run(xdcPath, metricsPath, probePath, tclPath, skewPath) {
  const out = [];
  judged = 0;
  const xdc = read(xdcPath), met = read(metricsPath), probe = read(probePath), tcl = read(tclPath), skewTxt = read(skewPath);
  if (xdc === null) { out.push(`W0 XDC缺失                判 0 项 缺 ${xdcPath} NOT_MEASURED`); return { out }; }
  if (met === null) { out.push(`W0 metrics缺失            判 0 项 缺 ${metricsPath} NOT_MEASURED`); return { out }; }

  const L = body(xdc);
  // --- W1 数字可推导 ---
  const mrow = met.split(/\r?\n/).find(l => l.includes('显示像素时钟'));
  const m = mrow ? mrow.split(',') : null;
  let tchar = null, tbit = null;
  if (m) {
    judged++;
    const pclock = Number(m[2]);
    const unit = (m[3] || '').trim();
    if (!Number.isFinite(pclock) || pclock <= 0 || unit !== 'MHz') {
      out.push(`W1 半窗可推导         判 ${judged} 项 像素钟行解析不到或单位非 MHz（读=${mrow}） NOT_MEASURED`);
    } else {
      tchar = 1000 / pclock; tbit = tchar / 10;
      const expect = +(0.20 * tchar).toFixed(3);
      const gotMax = L.filter(s => /set_output_delay/.test(s) && /-max/.test(s));
      const nums = gotMax.map(s => Number((s.match(/-max\s+(-?\d+(?:\.\d+)?)/) || [])[1]));
      const okAll = gotMax.length > 0 && nums.every(n => Number.isFinite(n) && Math.abs(n - expect) < 1e-6);
      out.push(`W1 半窗可推导         判 ${judged} 项 期望=0.20×${tchar.toFixed(3)}ns=${expect}ns 实读=[${nums.join(',')}] 行=${gotMax.length} ${okAll ? 'PASS' : 'FAIL'}`);
    }
  } else { judged++; out.push(`W1 半窗可推导         判 ${judged} 项 metrics 里没有"显示像素时钟"行 NOT_MEASURED`); }

  // --- W2 对称成对 ---
  judged++;
  const mx = L.filter(s => /set_output_delay/.test(s) && /-max/.test(s)).map(s => Number((s.match(/-max\s+(-?\d+(?:\.\d+)?)/) || [])[1]));
  const mn = L.filter(s => /set_output_delay/.test(s) && /-min/.test(s)).map(s => Number((s.match(/-min\s+(-?\d+(?:\.\d+)?)/) || [])[1]));
  const pair = mx.length === mn.length && mx.length > 0 && mx.every((v, i) => Math.abs(v + mn[i]) < 1e-9);
  out.push(`W2 max/min 成对      判 ${judged} 项 max=[${mx.join(',')}] min=[${mn.join(',')}] ${pair ? 'PASS' : 'FAIL'}`);

  // --- W3 纯 SDC 子集 ---
  judged++;
  const bad = L.filter(s => FORBIDDEN.test(s));
  out.push(`W3 纯SDC子集         判 ${judged} 项 违规行=${bad.length}${bad.length ? ' 例:' + bad[0].slice(0, 48) : ''} ${bad.length === 0 && mx.length > 0 ? 'PASS' : 'FAIL'}`);

  // --- W4 参考钟身份有凭据 ---
  const clkNames = [...new Set(L.filter(s => /set_output_delay/.test(s)).map(s => (s.match(/-clock\s+([A-Za-z0-9_\[\]]+)/) || [])[1]).filter(Boolean))];
  if (probe === null) {
    judged++; out.push(`W4 参考钟有凭据       判 ${judged} 项 缺探针件 ${probePath} NOT_MEASURED`);
  } else {
    judged++;
    const hit = clkNames.filter(n => probe.includes(n));
    const ok = clkNames.length > 0 && hit.length === clkNames.length;
    out.push(`W4 参考钟有凭据       判 ${judged} 项 用到=[${clkNames.join(',')}] 探针件逐字命中=[${hit.join(',')}] ${ok ? 'PASS' : 'FAIL'}`);
  }

  // --- W5 射程 ---
  judged++;
  const portTxt = L.filter(s => /set_output_delay/.test(s)).join(' ');
  const led = /\bled\b|tmds_clk/.test(portTxt);
  const dports = [...new Set((portTxt.match(/tmds_data_[pn]\[\*\]/g) || []))];
  const ok5 = !led && dports.length === 2;
  out.push(`W5 射程只含数据道    判 ${judged} 项 命中道=[${dports.join(',')}] 误挂led/钟道=${led ? '是' : '否'} ${ok5 ? 'PASS' : 'FAIL'}`);

  // --- W6 默认不加载 ---
  if (tcl === null) { judged++; out.push(`W6 默认不加载         判 ${judged} 项 缺 ${tclPath} NOT_MEASURED`); }
  else {
    judged++;
    const base = path.basename(xdcPath).replace('.xdc', '');
    const tclLines = tcl.split(/\r?\n/);
    const at = tclLines.map((l, i) => ({ l, i })).filter(o => o.l.includes(base));
    // 审计指出：原来 `l.includes('add_files')` 单独就满足"在开关块内"（裸 add_files 会判绿）。
    // 我第一版收紧成"同一行要有开关名"结果把真实形状误判成红（真实形状是 if 开一块、块内一行 add_files）。
    // 正确做法：从引用行往上找 6 行，看它是否落在带开关名的块里；裸 add_files 仍然不算把门。
    const inSwitchBlock = (idx) => {
      for (let k = Math.max(0, idx - 6); k <= idx; k++) if (/VP_R119_TMDS_WINDOW|env\(/.test(tclLines[k])) return true;
      return false;
    };
    const gated = at.length > 0 && at.every(o => inSwitchBlock(o.i));
    out.push(`W6 默认不加载         判 ${judged} 项 引用行=${at.length} 全在开关块内=${gated ? '是' : '否'} ${gated ? 'PASS' : 'FAIL'}`);
  }

  // --- W7–W10 成品离散（与规范同量纲的那一问）---
  if (skewTxt === null) {
    judged += 4;
    out.push(`W7 互对离散max角     判 ${judged} 项 缺读数件 ${skewPath} NOT_MEASURED`);
    out.push(`W8 互对离散min角     判 ${judged + 1} 项 同上 NOT_MEASURED`);
    out.push(`W9 对内离散          判 ${judged + 2} 项 同上 NOT_MEASURED`);
    out.push(`W10 lane 计数地板     判 ${judged + 3} 项 同上 NOT_MEASURED`);
  } else if (tchar === null) {
    judged += 4;
    out.push(`W7 互对离散max角     判 ${judged} 项 Tcharacter 没算出来（W1 未过）NOT_MEASURED`);
    out.push(`W8 互对离散min角     判 ${judged + 1} 项 同上 NOT_MEASURED`);
    out.push(`W9 对内离散          判 ${judged + 2} 项 同上 NOT_MEASURED`);
    out.push(`W10 lane 计数地板     判 ${judged + 3} 项 同上 NOT_MEASURED`);
  } else {
    const limI = +(0.20 * tchar).toFixed(3), limN = +(0.15 * tbit).toFixed(3);
    const t = skewTable(skewTxt);
    const lanes = ['tmds_data_p[0]', 'tmds_data_p[1]', 'tmds_data_p[2]'];
    const pairs = [['tmds_clk_p', 'tmds_clk_n'], ['tmds_data_p[0]', 'tmds_data_n[0]'], ['tmds_data_p[1]', 'tmds_data_n[1]'], ['tmds_data_p[2]', 'tmds_data_n[2]']];

    // W10 计数地板先算，供 W7/W8/W9 用（缺 lane 时三条一起 NOT_MEASURED，不许"少一条也算过"）
    // 第三方审计（2026-10-04）指出的两个洞，这里一起补：
    //   ① 地板原来只数"读到了没有"，**全 0 读数**也能过 ⇒ 现在要求读数 > 0（clock-to-pin 不可能为 0）。
    //   ② 打印的"钟道=两角齐"与 floorOk 用的不是同一件事（一个查 clk_p 的 min，一个查 clk_n）⇒ 统一到 clk_p 两角。
    judged++;
    const haveMax = lanes.filter(l => Number.isFinite(t.max[l]) && t.max[l] > 0).length;
    const haveMin = lanes.filter(l => Number.isFinite(t.min[l]) && t.min[l] > 0).length;
    const havePair = pairs.filter(([a, b]) => Number.isFinite(t.max[a]) && Number.isFinite(t.max[b]) && t.max[a] > 0 && t.max[b] > 0).length;
    const clkBoth = Number.isFinite(t.max['tmds_clk_p']) && t.max['tmds_clk_p'] > 0 && Number.isFinite(t.min['tmds_clk_p']) && t.min['tmds_clk_p'] > 0;
    const zeroSeen = Object.values(t.max).concat(Object.values(t.min)).filter(v => v === 0).length;
    const floorOk = haveMax === 3 && haveMin === 3 && havePair === 4 && clkBoth;
    out.push(`W10 lane 计数地板     判 ${judged} 项 数据道max=${haveMax}/3 min=${haveMin}/3 P-N对=${havePair}/4 钟道=${clkBoth ? '两角齐' : '缺'} 全零读数=${zeroSeen} ${floorOk && zeroSeen === 0 ? 'PASS' : 'FAIL'}`);

    const interOf = (corner) => {
      const c = t[corner]['tmds_clk_p'];
      if (!Number.isFinite(c)) return null;
      const d = lanes.map(l => (Number.isFinite(t[corner][l]) ? +(t[corner][l] - c).toFixed(3) : null));
      if (d.some(x => x === null)) return null;
      return { d, worst: Math.max(...d.map(Math.abs)) };
    };
    for (const [id, corner] of [['W7', 'max'], ['W8', 'min']]) {
      judged++;
      const r = interOf(corner);
      if (r === null) { out.push(`${id} 互对离散${corner}角     判 ${judged} 项 读数不齐（见 W10）NOT_MEASURED`); continue; }
      out.push(`${id} 互对离散${corner}角     判 ${judged} 项 上限=${limI}ns(0.20×${tchar.toFixed(3)}) 逐道偏差=[${r.d.join(',')}]ns 最差=${r.worst}ns ${r.worst <= limI ? 'PASS' : 'FAIL'}`);
    }
    judged++;
    const intra = pairs.map(([a, b]) => (Number.isFinite(t.max[a]) && Number.isFinite(t.max[b])) ? +(t.max[a] - t.max[b]).toFixed(3) : null);
    if (intra.some(x => x === null)) { out.push(`W9 对内离散          判 ${judged} 项 读数不齐（见 W10）NOT_MEASURED`); }
    else {
      const w = Math.max(...intra.map(Math.abs));
      out.push(`W9 对内离散          判 ${judged} 项 上限=${limN}ns(0.15×Tbit=${tbit.toFixed(3)}ns) 逐对P-N=[${intra.join(',')}]ns 最差=${w}ns ${w <= limN ? 'PASS' : 'FAIL'}`);
    }
  }

  const judgedLines = out.filter(l => / (PASS|FAIL|NOT_MEASURED)$/.test(l)).length;
  const red = out.filter(l => l.trim().endsWith('FAIL')).length;
  const nm = out.filter(l => l.trim().endsWith('NOT_MEASURED')).length;
  out.push(`GATES r119 窗件：判定 ${judgedLines} 项 红=${red} 未测=${nm} ${red > 0 ? 'FAIL' : nm > 0 ? 'NOT_MEASURED' : 'PASS'}`);
  return { out };
}

// —— 阳性对照：每条判据各造一条畸形输入，必须各自变红；缺输入必须报 NOT_MEASURED
function selftest() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'r119ctl-'));
  const xf = path.join(dir, 'bad.xdc'), mf = path.join(dir, 'metrics.csv'), pf = path.join(dir, 'probe.txt'),
        tf = path.join(dir, 'build.tcl'), sf = path.join(dir, 'skew.txt');
  fs.writeFileSync(mf, '名称,类别,值,单位\n显示像素时钟,核心,50,MHz\n');
  const OK = 'set_output_delay -clock clkout1_1 -max 4.000 [get_ports {tmds_data_p[*] tmds_data_n[*]}]\n' +
             'set_output_delay -clock clkout1_1 -min -4.000 [get_ports {tmds_data_p[*] tmds_data_n[*]}]\n';
  const GOODPROBE = 'clock=clkout1_1 period=4.000\n';
  const GOODTCL = `# 开关块\nif {$::env(VP_R119_TMDS_WINDOW) eq "1"} {\n  add_files -norecurse bad.xdc\n}\n`;
  const GOODKEW = ['tmds_clk_p', 'tmds_clk_n', 'tmds_data_p[0]', 'tmds_data_n[0]', 'tmds_data_p[1]', 'tmds_data_n[1]', 'tmds_data_p[2]', 'tmds_data_n[2]']
    .map(p => `PIN| ${p} | max | data_path_delay=2.030ns\nPIN| ${p} | min | data_path_delay=1.010ns`).join('\n') + '\n';
  const cases = [
    ['W1', { xdc: OK.replace('-max 4.000', '-max 8.000').replace('-min -4.000', '-min -8.000'), probe: GOODPROBE, tcl: GOODTCL, skew: GOODKEW }],
    ['W2', { xdc: OK.replace('-min -4.000', '-min  4.000'), probe: GOODPROBE, tcl: GOODTCL, skew: GOODKEW }],
    ['W3', { xdc: 'if {1} {\n' + OK + '}\n', probe: GOODPROBE, tcl: GOODTCL, skew: GOODKEW }],
    ['W4', { xdc: OK, probe: 'clock=clkout9_9 period=4.000\n', tcl: GOODTCL, skew: GOODKEW }],
    ['W5', { xdc: 'set_output_delay -clock clkout1_1 -max 4.000 [get_ports {led[*] tmds_clk_p}]\nset_output_delay -clock clkout1_1 -min -4.000 [get_ports {led[*] tmds_clk_p}]\n', probe: GOODPROBE, tcl: GOODTCL, skew: GOODKEW }],
    ['W6', { xdc: OK, probe: GOODPROBE, tcl: 'read_xdc bad.xdc\n', skew: GOODKEW }],
    ['W7', { xdc: OK, probe: GOODPROBE, tcl: GOODTCL, skew: GOODKEW.replace('PIN| tmds_data_p[1] | max | data_path_delay=2.030ns', 'PIN| tmds_data_p[1] | max | data_path_delay=6.300ns') }],
    ['W8', { xdc: OK, probe: GOODPROBE, tcl: GOODTCL, skew: GOODKEW.replace('PIN| tmds_data_p[2] | min | data_path_delay=1.010ns', 'PIN| tmds_data_p[2] | min | data_path_delay=5.300ns') }],
    ['W9', { xdc: OK, probe: GOODPROBE, tcl: GOODTCL, skew: GOODKEW.replace('PIN| tmds_data_n[1] | max | data_path_delay=2.030ns', 'PIN| tmds_data_n[1] | max | data_path_delay=2.900ns') }],
    ['W10', { xdc: OK, probe: GOODPROBE, tcl: GOODTCL, skew: GOODKEW.split('\n').filter(l => !l.includes('tmds_data_p[2]')).join('\n') }],
    // 审计指出的洞：地板原来只数"读到了没有"，**全 0 读数**（结构完整但数值为零）能一路判绿 ⇒ 加这一条对照。
    ['W10b', { xdc: OK, probe: GOODPROBE, tcl: GOODTCL, skew: GOODKEW.replace(/data_path_delay=[0-9.]+ns/g, 'data_path_delay=0.000ns') }],
    ['NM', { xdc: OK, probe: null, tcl: GOODTCL, skew: GOODKEW }],
    ['NMS', { xdc: OK, probe: GOODPROBE, tcl: GOODTCL, skew: null }],
  ];
  let moved = 0, nmok = 0;
  for (const [id, c] of cases) {
    fs.writeFileSync(xf, c.xdc);
    if (c.probe === null) fs.rmSync(pf, { force: true }); else fs.writeFileSync(pf, c.probe);
    fs.writeFileSync(tf, c.tcl);
    if (c.skew === null) fs.rmSync(sf, { force: true }); else fs.writeFileSync(sf, c.skew);
    const { out } = run(xf, mf, pf, tf, sf);
    const want = (id === 'NM' || id === 'NMS') ? 'NOT_MEASURED' : 'FAIL';
    const key = id === 'NM' ? 'W4' : (id === 'NMS' || id === 'W10b') ? 'W10' : id;
    const hit = out.find(l => l.startsWith(key + ' '));
    const got = hit ? hit.trim().split(/\s+/).pop() : '无该行';
    if (want === 'NOT_MEASURED') { if (got === want) nmok++; } else if (got === want) moved++;
    const reds = out.filter(l => l.trim().endsWith('FAIL')).map(l => l.split(' ')[0]);
    console.log(`CTRL ${id} 期望=${want} 实读=${got} 本轮全红=[${reds.join(',')}] ${got === want ? '对照成立' : '对照不成立：这条判据没有牙'}`);
  }
  fs.rmSync(dir, { recursive: true, force: true });
  const nRed = cases.filter(c => c[1].probe !== null && c[1].skew !== null && c[0] !== 'NM' && c[0] !== 'NMS').length;
  const nNm = 2;
  const ok = moved === nRed && nmok === nNm;
  console.log(`对照总结：造 ${nRed} 条畸形动红 ${moved} 条；缺输入 ${nNm} 条报 NOT_MEASURED ${nmok} 条 ${ok ? 'PASS' : 'FAIL'}`);
  return ok ? 0 : 1;
}

if (process.argv.includes('--self')) { process.exit(selftest()); }
const res = run(XDC, METRICS, PROBE, BUILD_TCL, SKEW);
// 旁证头：这份读数的每个数字都来自下面 5 件，md5 现算（先归一 CRLF，换行差异不得改变指纹）
const INPUTS = [XDC, METRICS, PROBE, BUILD_TCL, SKEW];
const md5 = f => {
  const p = path.isAbsolute(f) ? f : path.join(ROOT, f);
  if (!fs.existsSync(p)) return 'ABSENT';
  return crypto.createHash('md5').update(fs.readFileSync(p, 'utf8').replace(/\r\n/g, '\n')).digest('hex').slice(0, 12);
};
let absent = 0;
console.log('HEAD 输入件指纹（现算，非手抄）');
for (const f of INPUTS) { const h = md5(f); if (h === 'ABSENT') absent++; console.log(`HEAD ${f} ${h}`); }
console.log(`HEAD 读数器=node${process.version} 输入件=${INPUTS.length} 缺件=${absent} 判 ${INPUTS.length} 项`);
res.out.forEach(l => console.log(l));
const last = res.out[res.out.length - 1];
process.exit(last.endsWith('PASS') ? 0 : last.endsWith('NOT_MEASURED') ? 2 : 1);
