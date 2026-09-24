#!/usr/bin/env node
/**
 * temp_formula_check.mjs —— V8-7 温度换算的独立核对（不碰板子，几秒钟）
 *
 * 为什么要有这一条：固件里 `temp_mc_of()` 是**定点**实现（`xil_printf` 不认 %f，见 main.c 注释），
 * 而权威定义是 BSP 宏 `XAdcPs_RawToTemperature(AdcData) = (AdcData/65536)/0.00198421639 − 273.15`。
 * 一个符号写错（少一个 0、把 65536 当成 4096）在串口上只会显示"340 °C"或"3.4 °C"，
 * 而板子上没有第二支温度计能拆穿它 —— tb_v94 那次"公式差 100 倍"的红就是这么来的，
 * 所以这里**从 main.c 源码里把常数抠出来**，跟浮点参考式在全码段上比，而不是抄一份到测试里。
 *
 * 用法：node src/host/temp_formula_check.mjs [--verbose]
 */
import { readFileSync } from 'node:fs';

const SRC = 'src/ps/main.c';
const verbose = process.argv.includes('--verbose');

/* 1) 从固件源码里读出实现（只认这两个函数体里的三个常数，改了写法就必须同步改这里 —— 这是故意的）。
 *    括号嵌套数容易数错，所以先取函数体再按 `* NULL` / `>> N` / `- N` 三种形状各抽一个数。 */
const src = readFileSync(SRC, 'utf8');
const body = (fn) => { const m = src.match(new RegExp(`static s32 ${fn}\\(u16 raw\\)\\s*\\{([^}]*)\\}`)); return m ? m[1] : null; };
const num = (txt, re, what) => { const m = txt && txt.match(re); if (!m) { console.log(`FAIL 固件里读不到 ${what}`); process.exit(1); } return Number(m[1]); };
const bT = body('temp_mc_of'), bV = body('volt_mv_of');
if (!bT || !bV) {
    console.log(`FAIL 读不到固件里的定点实现（main.c 的 temp_mc_of/volt_mv_of 改了写法？` +
                `同步改本文件第 1 步，别把这条判据删掉）`);
    process.exit(1);
}
const [KM, SM, OM] = [num(bT, /\*\s*(\d+)ULL/, 'temp_mc_of 的乘数'),
                      num(bT, />>\s*(\d+)/,   'temp_mc_of 的右移位数'),
                      num(bT, /-\s*(\d+)/,    'temp_mc_of 的偏移')];
const [KV, SV]     = [num(bV, /\*\s*(\d+)ULL/, 'volt_mv_of 的乘数'),
                      num(bV, />>\s*(\d+)/,    'volt_mv_of 的右移位数')];
console.log(`SRC  ${SRC}: degC×1000 = (raw*${KM} >> ${SM}) - ${OM}   mV = (raw*${KV} >> ${SV})`);

/* 2) 权威参考式：逐字抄 BSP 的 xadcps.h 宏（float），单位也换成 ×1000 好比对 */
const REF_MC = (raw) => Math.round(((raw / 65536) / 0.00198421639 - 273.15) * 1000);
const REF_MV = (raw) => Math.round(((raw * 3.0) / 65536) * 1000);
const impl_mc = (raw) => Math.floor((raw * KM) / 2 ** SM) - OM;      // C 的整数乘除：先乘再整除
const impl_mv = (raw) => Math.floor((raw * KV) / 2 ** SV);

let worst_mc = 0, worst_mv = 0, worst_raw = 0, n = 0;
for (let raw = 0; raw <= 0xFFFF; raw++) {
    const dmc = Math.abs(impl_mc(raw) - REF_MC(raw)), dmv = Math.abs(impl_mv(raw) - REF_MV(raw));
    if (dmc > worst_mc) { worst_mc = dmc; worst_raw = raw; }
    if (dmv > worst_mv) worst_mv = dmv;
    n++;
}
/* 容差不许拍脑袋，三项各有出处，加起来就是"最大可能差多少"：
 *   ① 固件用 KM/1000 = 503.975，而参考式的常数是 1/0.00198421639 = 503.97729 —— 差 4.5e-6，
 *      乘上满量程那一端的绝对温度（≈504 K）就是它的贡献 ≈2.3 个千分位；
 *   ② 定点实现向下取整：≤1 个千分位；③ 参考式四舍五入：≤1 个千分位。
 * 这样"容差 = 5"是被算出来的，不是看到一个偏差 3 就把 2 改成 5 —— 那才是放松判据。 */
const rel = Math.abs(KM / 1000 - 1 / 0.00198421639) / (1 / 0.00198421639);
const spanK = (impl_mc(0xFFFF) + OM) / 1000;
const bound = Math.ceil(rel * spanK * 1000) + 2;
const okT = worst_mc <= bound, okV = worst_mv <= 2;
console.log(`INFO 容差依据：rel=${rel.toExponential(2)} × 满量程 ${spanK.toFixed(1)} K = ${(rel * spanK * 1000).toFixed(1)}‰，加两次取整 ⇒ 容差 ${bound}‰°C`);
console.log(`${okT ? 'PASS' : 'FAIL'} 全 65536 码段比参考式：温度最大偏差 ${worst_mc} ‰°C（最差在 raw=0x${worst_raw.toString(16)}）`);
console.log(`${okV ? 'PASS' : 'FAIL'} 电压最大偏差 ${worst_mv} µV，容差 2µV×1000（同一条截断式，3000/65536 是精确的）`);

/* 3) 三个锚点：raw 由参考式反解（只为把告警线对应的码写在纸上），
 *    但**期望的 °C 是手算的**（25 / 85 / 满码 230.8），所以抓到的是标度错而不是自证。 */
const anchors = [
    ['raw=0x0000（复位值/没转换）', 0x0000, -273150, '全 0 必须译成 −273.15 °C —— 固件靠这一条把"读不到"和"很冷"分开'],
    ['25 °C 的码 = 38771',          0x9773,  25000,  '(25+273.15)×65536/503.975 ≈ 38771 = 0x9773'],
    ['85 °C（spec 的告警线）= 46573', 0xB5ED,  85000,  '(85+273.15)×65536/503.975 ≈ 46573 = 0xB5ED'],
    ['raw=0xFFFF（满码）',          0xFFFF, 230823,  '满码 ≈ 230.8 °C：>85 ⇒ 满码一定被 sane 挡下'],
];
let okA = true;
for (const [name, raw, want, why] of anchors) {
    const got = impl_mc(raw);
    const ok = Math.abs(got - want) <= 150;                 // ±0.15 °C：锚点是手算的，允许这一档
    okA &&= ok;
    console.log(`${ok ? 'PASS' : 'FAIL'} 锚点 ${name} → ${(got / 1000).toFixed(2)} °C（期望 ${want} ±150）  依据：${why}`);
}

/* 4) 反向对照（假判据探测器）：把"最可能写错的三种变体"逐个试一遍，必须全部偏离参考式。
 *    如果这条 PASS 不了，说明第 2 步的容差松到连错公式都能过 —— 那才是真正的红。 */
const mutants = [
    ['把 65536 当成 4096（少移 4 位）', (r) => Math.floor((r * KM) / 2 ** (SM - 4)) - OM],
    ['忘了减 273.15 的偏移',            (r) => Math.floor((r * KM) / 2 ** SM)],
    ['常数 503.975 少写一个 5',         (r) => Math.floor((r * 50397) / 2 ** SM) - OM],
];
let okM = true;
for (const [name, f] of mutants) {
    const err = Math.abs(f(0x9776) - REF_MC(0x9776));       // 25 °C 那一点上比
    const ok = err > 1000;                                  // 至少差 1 °C 才算被这条判据抓到
    okM &&= ok;
    console.log(`${ok ? 'PASS' : 'FAIL'} 变异对照 ${name} → 偏 ${(err / 1000).toFixed(1)} °C，必须 > 1 °C`);
}

if (verbose)
    console.log(`  样本 ${n} 个码值；实现 degC(0x9776)=${(impl_mc(0x9776) / 1000).toFixed(3)}，` +
                `参考 ${(REF_MC(0x9776) / 1000).toFixed(3)}`);
const all = okT && okV && okA && okM;
console.log(`${all ? 'PASS' : 'FAIL'} temp_formula_check`);
process.exit(all ? 0 : 1);
