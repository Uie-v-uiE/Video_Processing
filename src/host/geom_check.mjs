#!/usr/bin/env node
// 用途：V9（ISSUES #75）几何自动化的"最后一跳"机器判据
// 输入：命令行参数
// 输出：stdout
// 退出码：0=跑完 2=非 0 分支（该文件 exit 2 那一行）
/**
 * geom_check.mjs —— V9（ISSUES #75）几何自动化的"最后一跳"机器判据。
 *
 * 为什么要有这个文件（不是"再写一个脚本"，而是补一个**证据等级**）：
 *   串口电池能证明"固件收到命令并回显了它以为的值"，证明不了"像素域真的用了它"。
 *   V8-8 为缩放补过这一跳（lane23 = 像素域真的在用的 inv / zoom_code / zman），
 *   V9 新加了三种像素域行为（自动旋转、按角度定倍率、缝搬进图像列）。
 *   只留回显，它们就是"屏上看着像、机器说不出"那一类 —— 评审问"怎么证明"答不上来。
 *
 * 六条判据（都是"命令 → 读回像素域自己吐出来的数"，不看回显文本）：
 *   G1 `zoom fit 1`      ⇒ lane23 的 bit19 = 1，inv_used 落在 [256,512]，且 zcode == 独立复算的最近档
 *   G2 `rot auto 1` 之后  ⇒ **在同一次 halt 里隔 1.2 s 读两次 lane23，两次的 inv 必须不同**
 *                          （CPU 停着 ⇒ 变的只可能是 PL 自己：角度在走、拟合跟着角度走）
 *   G5/G5b（r97 加，#175）⇒ 关掉 fit 请求、只留自动旋转 + 手动 1.00x：这一位就只剩"被旋转钳住"一个来源，
 *                          于是判不变量 `bit19 == (inv ≠ 256)`，并要求四次里至少真钳住一次（防空判据）
 *   G3 `split video`      ⇒ CFG_DATA0 的 bit24（= 打包后 gp[11]）为 1
 *   G4 收尾              ⇒ 整串跑完，CFG_DATA0 的 19 个几何位等于**演示默认档**那一束（#177 换的口径：
 *                          与起点无关；跑完不许留自动态/手动态）
 *
 * 用法：node src/host/geom_check.mjs [--com COM6] [--jtag 3121]
 * 前置：板子上电、r60 那套三件套已下载、hw_server 在跑（同 health_read.mjs）。
 * ⚠ 会动板上状态：结尾一定要还原（G4 就是钉这件事的）。
 */
import { execSync } from 'node:child_process';
import { writeFileSync, readFileSync, unlinkSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';

/* 演示默认的 19 位几何字（唯一出处：report/defaults.md 第一节 + src/host/ps/main.c 的 cur_split/rot/… 初值；
 * 位序与掩码沿用本文件上面的 GEOM_MASK）。#177：G4 判的是"跑完停在这一档"，不再是"与进来时相同"。 */
const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 && process.argv[i + 1] ? process.argv[i + 1] : d; };
if (process.argv.includes('--help') || process.argv.includes('-h')) {
  console.log('用法：node src/host/geom_check.mjs [--com COM6] [--jtag 3121] [--xsdb <xsdb.bat>]');
  console.log('四条判据 G1..G4 全是"命令 → 读回像素域/寄存器的真值"，不看回显文本。');
  console.log('⚠ 会动板上状态（结尾自己还原，G4 就是钉这件事的）。跑之前确认 hw_server 在、bit 已下载。');
  process.exit(0);
}
const XSDB = String(arg('--xsdb', process.env.VP_XSDB || 'xsdb.bat'));
const JPORT = String(arg('--jtag', '3121'));
const COM = String(arg('--com', 'COM6'));
const SENDER = 'board/uart_cmd_script.ps1';
const GPIO0 = '0x41200000', GPIO1 = '0x41210000', CFG1 = '0x41220000';

let fail = 0, okn = 0;
const line = (name, pass, note = '') => {
  if (pass) { okn++; console.log(`ok   ${name}${note ? '  ' + note : ''}`); }
  else { fail++; console.log(`FAIL ${name}${note ? '  ' + note : ''}`); }
};

/* 19 位几何控制字在 CFG_DATA0 里的掩码（唯一出处 = src/host/ps/main.c 的 GEOM_MASK，两边同序）：
 * bit31 fit ｜ bit30 marker_off ｜ bit[25:23] auto/follow/swap ｜ bit[22:13] 缝位
 * ｜ bit[12:10] rot_speed ｜ bit9 rot_auto。[8:0] 是效果九位、[29]/[28:26] 是缩放档 ⇒ 不比较。 */
const MAINC = String(arg('--main-c', 'src/host/ps/main.c'));
/* #177b（2026-09-30，r94）：上面那份掩码过去是**手抄**的 main.c `GEOM_MASK`，而且抄错了 ——
 *   缝位写成 `0x001FE000`（8 位）而不是 `(0x3FFu << 13)` = `0x007FE000`（10 位），
 *   于是 cfg 的 bit22/bit21 落在掩码外。症状很具体：`split px 0`（pos=0）与默认档（pos=512 ⇒ bit22）
 *   **恰好只差这两位** ⇒ 老的 G4 会把"缝钉在屏幕最左边缘"判成"几何位回到默认档"。
 *   这正是 #117 那一课：**判据看不见的那一位，就等于没有判据**。
 *   修法不是把手抄那串数补对 —— 只要还是"抄第二份"，位段哪天再变宽就会第二次抄错；
 *   现在**从唯一出处现算**：读 `src/host/ps/main.c` 的宏、自己求值 ⇒ PS 的位图一改这里自动跟着改。
 *   读不到文件 / 宏的形状不认识 ⇒ FATAL 退出，不退回旧常量（沉默地用一份可能过期的掩码，
 *   比没有判据更糟）。 */
function macros(path) {
  const src = readFileSync(path, 'utf8');
  const defs = {};
  for (const m of src.matchAll(/^#define\s+([A-Za-z_]\w*)\s+([^\n]*)/gm)) {
    const body = m[2].replace(/\/\*[\s\S]*?\*\//g, '').trim();
    if (body && !(m[1] in defs)) defs[m[1]] = body;
  }
  return defs;
}
/* 只认 C 位图宏里会出现的这几种形状：十/十六进制常数（可带 u 后缀）、`<<`、`&`、`|`、括号、标识符。
 * 出现别的运算（三元、`(u32)` 强转……）求值器返回 null ⇒ 调用方 FATAL，绝不猜一个数出来。 */
function evExpr(text, defs, depth) {
  const d = depth || 0;
  if (d > 24 || !String(text).trim()) return null;
  const toks = text.match(/0[xX][0-9a-fA-F]+[uU]*|\b\d+[uU]*|[A-Za-z_]\w*|<<|\||\(|\)|&/g);
  if (!toks) return null;
  let i = 0;
  const peek = () => toks[i];
  function primary() {
    if (toks[i] === '(') { i++; const v = orExpr(); if (v === null || toks[i] !== ')') return null; i++; return v; }
    const t = toks[i++];
    if (t === undefined) return null;
    if (/^0[xX]/.test(t)) return parseInt(t.replace(/[uU]+$/, ''), 16) >>> 0;
    if (/^\d/.test(t)) return parseInt(t.replace(/[uU]+$/, ''), 10) >>> 0;
    return defs[t] === undefined ? null : evExpr(defs[t], defs, d + 1);
  }
  function shift() {
    let v = primary();
    if (v === null) return null;
    while (peek() === '<<') { i++; const s = primary(); if (s === null) return null; v = (v << s) >>> 0; }
    return v;
  }
  function andExpr() {
    let v = shift();
    if (v === null) return null;
    while (peek() === '&') { i++; const s = shift(); if (s === null) return null; v = (v & s) >>> 0; }
    return v;
  }
  function orExpr() {
    let v = andExpr();
    if (v === null) return null;
    while (peek() === '|') { i++; const s = andExpr(); if (s === null) return null; v = (v | s) >>> 0; }
    return v;
  }
  const v = orExpr();
  return i < toks.length ? null : v;
}
const MAIN_DEFS = (() => {
  try { return macros(MAINC); } catch (e) {
    console.log(`FATAL 读不到几何位图唯一出处 ${MAINC}（用 --main-c 指路径）：${String(e.message).slice(0, 60)}`);
    process.exit(2);
  }
})();
const die = (why) => { console.log(`FATAL ${why}`); process.exit(2); };
const GEOM_MASK = (() => {
  if (MAIN_DEFS.GEOM_MASK === undefined) die(`${MAINC} 里没有 GEOM_MASK 宏 —— 位图被改名或删了，先对上再判`);
  const m = evExpr(MAIN_DEFS.GEOM_MASK, MAIN_DEFS, 0);
  if (m === null) die(`求值不了 GEOM_MASK = "${MAIN_DEFS.GEOM_MASK}"（这个检查器不认识的宏形状）`);
  return m;
})();
/* #177（2026-09-30，r94）：G4 判的是"跑完停在演示默认档"，不再是"与进来时那一束相同"。
 *   今天撞的形状：我为眼睛判据把板子钉在 `rot auto 1 + src SD`（几何位 0xa00），
 *   收尾还原到默认反而 diff≠0 —— 红的是"起点不是默认档"，而这句话真正要钉的是终点。
 *   默认值出处：report/defaults.md 第一节（`cur_split` 正中 + marker 画着、rot/fit/自动扫描全关），
 *   而那份文档的出处就是 main.c 的 `cur_split` 初值 ⇒ 这里**直接读那一行**，连 512 都不手抄。 */
const GEOM_DEFAULT = (() => {
  const src = (() => { try { return readFileSync(MAINC, 'utf8'); } catch (e) { return ''; } })();
  const m = src.match(/static\s+u32\s+cur_split\s*=\s*\(([^)]*)\)/);
  if (!m) die(`${MAINC} 里找不到 cur_split 的初值 —— 默认档换了写法要同时改这里`);
  const v = evExpr(m[1], MAIN_DEFS, 0);
  if (v === null) die(`求值不了 cur_split 初值 = "${m[1]}"`);
  return v;
})();
const endsAtDefault = (w) => w !== null && ((w & GEOM_MASK) >>> 0) === ((GEOM_DEFAULT & GEOM_MASK) >>> 0);
if (process.argv.includes("--self")) {
  console.log(`  掩码（从 ${MAINC} 现算）= 0x${GEOM_MASK.toString(16)}，默认档 = 0x${GEOM_DEFAULT.toString(16)}`);
  const cases = [[GEOM_DEFAULT, true, "末态正好等于默认档"],
                 [GEOM_DEFAULT | 0x3C0001FF, true, "缩放档[28:26] 与效果九位不在几何掩码里，不参与判"],
                 [0x30400A00, false, "留住 rot auto + 转速"],
                 [GEOM_DEFAULT | (1 << 23), false, "留住缝的自动扫描位"],
                 [GEOM_DEFAULT | (1 << 31), false, "留住 zoom fit"],
                 [0x00000000, false, "缝被留在 pos=0：与默认档只差 bit22 —— 掩码抄窄一位就看不见（#177b）"]];
  let bad = 0;
  for (const [w, want, why] of cases) {
    const got = endsAtDefault(w);
    console.log(`  ${got === want ? "ok  " : "BAD "}${why}: 判 ${got}（期望 ${want}）`);
    if (got !== want) bad++;
  }
  console.log(bad ? "SELF FAIL geom_check --self" : "SELF PASS geom_check --self（六条对照都按期望动）");
  process.exit(bad ? 1 : 0);
}

/* 屏上 `Zoom:` 那一格的八档分区 —— 与 zoom_ctrl.v 里那七个"相邻两档中点"**同一套数**。
 * 为什么在脚本里再算一遍：这条判据要抓的恰恰是"屏上写的与真正在用的不是一回事"，
 * 而 lane23 里 zcode 与 inv 来自 zoom_ctrl 同一个寄存器组 ⇒ 只有独立复算才咬得住。
 * 改了 RTL 的那七个中点必须同时改这里（不一致就红，红得对）。 */
const nearOf = (inv) => (inv >= 900 ? 0 : inv >= 644 ? 1 : inv >= 427 ? 2 : inv >= 299 ? 3 :
                         inv >= 224 ? 4 : inv >= 182 ? 5 : inv >= 150 ? 6 : 7);

const VAL_RE = /VAL\s*[0-9a-fA-F]{1,8}:\s*([0-9a-fA-F]{1,8})/;
const TAG = 'geom';
const dump = (n) => `${tmpdir()}/${TAG}_${n}`;

/* 一次 halt 里做完：读 GPIO0 原值 → 选 lane → 读 GPIO1 → 还原 GPIO0 →（可选）读 CFG1 → con。
 * 抄 health_read 的套路（catch {stop} + after，最后才 con）：A9 停在断点时 mrd/mwr 走
 * CoreSight 直打 GP0 从端口；不停 CPU 的话固件会随时改 GPIO0[31:27]，lane 选择会被踩掉。 */
function sample(laneN, extraDelayMs) {
  const L = [
    `catch {connect -host localhost -port ${JPORT}}`,
    'targets -set -filter {name =~ "*#0"}',
    'catch {stop}', 'after 100',
    `puts "BASE [mrd -force ${GPIO0} 1]"`,
    `mwr -force ${GPIO0} 0x00000000 32`,                       // 先把 lane 清 0，避免读到上一次的选择
    `after 20`,
  ];
  const emit = (n, tag) => {
    L.push(`mwr -force ${GPIO0} 0x${(((n & 0x1F) << 27) >>> 0).toString(16)} 32`);
    L.push('after 20');
    L.push(`puts "${tag} [mrd -force ${GPIO1} 1]"`);
  };
  emit(laneN, 'A');
  if (extraDelayMs) { L.push(`after ${extraDelayMs}`); emit(laneN, 'B'); }
  L.push('catch {con}', 'after 50');
  const tcl = dump(`${TAG}.tcl`), out = dump(`${TAG}.out`);
  writeFileSync(tcl, L.join('\n') + '\n');
  try { execSync(`"${XSDB}" "${tcl}" > "${out}" 2>&1`, { windowsVerbatimArguments: true }); } catch (e) { /* 下面按内容判 */ }
  unlinkSync(tcl);
  const text = existsSync(out) ? readFileSync(out, 'utf8').replace(/\r\n/g, '\n') : '';
  const grab = (tag) => { const m = text.match(new RegExp(tag + '\\s*[0-9a-fA-F]{1,8}:\\s*([0-9a-fA-F]{1,8})')); return m ? (parseInt(m[1], 16) >>> 0) : null; };
  const head = text.split('\n').slice(0, 6).join('\n');
  if (/^error|no targets|cannot|invalid target/im.test(head))
    console.log('[GEOM] xsdb 报错（板子有电？bit 已下载？hw_server 在跑？):\n' + head);
  const dec = (v) => v === null ? null : ({
    raw: v, alive: (v >>> 31) & 1, zoom_fit: (v >>> 19) & 1, zman: (v >>> 18) & 1,
    zsel: (v >>> 15) & 7, zcode: (v >>> 12) & 7, active: (v >>> 11) & 1, dir: (v >>> 10) & 1,
    inv: v & 0x3FF,
  });
  return { base: grab('BASE'), a: dec(grab('A')), b: extraDelayMs ? dec(grab('B')) : null };
}

function readCfg1() {
  const L = [`catch {connect -host localhost -port ${JPORT}}`, 'targets -set -filter {name =~ "*#0"}',
             'catch {stop}', 'after 100', `puts "CFG [mrd -force ${CFG1} 1]"`, 'catch {con}'];
  const tcl = dump('cfg.tcl'), out = dump('cfg.out');
  writeFileSync(tcl, L.join('\n') + '\n');
  try { execSync(`"${XSDB}" "${tcl}" > "${out}" 2>&1`, { windowsVerbatimArguments: true }); } catch (e) {}
  unlinkSync(tcl);
  const m = (existsSync(out) ? readFileSync(out, 'utf8') : '').match(/CFG\s+[0-9a-fA-F]{1,8}:\s*([0-9a-fA-F]{1,8})/);
  return m ? (parseInt(m[1], 16) >>> 0) : null;
}

/* 串口：把一批命令发给固件（发送器就是电池用的那个 ps1），只回显、不判定 ——
 * 判定全部在 lane23 / CFG1 那两侧（回显只能证明固件"说了"，证明不了硬件"用了"）。 */
function send(cmds) {
  const f = dump('cmds.txt'), echo = dump('echo.txt');
  writeFileSync(f, cmds.join('\n') + '\n');
  try {
    execSync(`powershell -NoProfile -ExecutionPolicy Bypass -File ${SENDER} -Port ${COM} ` +
             `-File "${f}" -DelayMs 250 -Out "${echo}" >nul 2>&1`, { shell: true });
  } catch (e) { console.log(`FAIL 发送器没跑成（COM=${COM} 被占？）：${String(e.message).slice(0, 90)}`); fail++; }
  return existsSync(echo) ? readFileSync(echo, 'utf8') : '';
}

console.log('# geom_check（V9 的"最后一跳"：命令 → 像素域真的用了它）');
const cfg0 = readCfg1();
if (cfg0 === null) { console.log('FATAL 读不到 CFG_DATA0（0x41220000）—— 一个字节都不写，先修 JTAG 通路'); process.exit(2); }
console.log(`  进来时 CFG_DATA0 = 0x${cfg0.toString(16)}（几何位 0x${(cfg0 & GEOM_MASK).toString(16)}）`);

// ---- G1：开拟合，看像素域真的换了来源 ----
send(['zoom fit 1']);
let s = sample(23, 0);
const z1 = s.a;
line('G1a `zoom fit 1` ⇒ lane23.bit19（zoom_fit）= 1', !!z1 && z1.zoom_fit === 1,
     z1 ? `lane23=0x${z1.raw.toString(16)} alive=${z1.alive}` : '读不到 lane23（位流没有这一口？）');
line('G1b 拟合的 inv_used 落在 [256,512]（只缩小、不放大到画外）',
     !!z1 && z1.alive === 1 && z1.inv >= 256 && z1.inv <= 512, z1 ? `inv=${z1.inv}` : '');
line('G1c 屏上档位与真值同档（zcode == 独立复算的最近档）',
     !!z1 && z1.zcode === nearOf(z1.inv), z1 ? `zcode=${z1.zcode} nearOf(${z1.inv})=${nearOf(z1.inv)}` : '');

// ---- G2：自动旋转期间，在同一次 halt 里隔 1.2 s 读两次 ⇒ PL 自己在动 ----
send(['rot speed 5', 'rot auto 1']);
const s2 = sample(23, 1200);
line('G2 开着自动旋转，CPU 停着，1.2 s 之间 inv_used 变了（缩放真的跟着角度走）',
     !!s2.a && !!s2.b && s2.a.zoom_fit === 1 && s2.b.zoom_fit === 1 && s2.a.inv !== s2.b.inv,
     s2.a && s2.b ? `${s2.a.inv} → ${s2.b.inv}（相等 = 只有后缀在动，倍率没动）` : '');
line('G2x 全程没有把 zoom 弹出量程', !!s2.b && s2.b.inv >= 256 && s2.b.inv <= 512,
     s2.b ? `inv=${s2.b.inv}` : '');

// ---- G5（#175 的机器判据；r97 那一刀把这一位接成了 `zoom_fit_en | rot_forced`）----
// 先把"请求位"关掉、只留"旋转钳"这一路：`rot auto 1` 的成对语义会顺带开 fit（report/commands.md:209-210），
// 所以顺序是 rot 在前、`zoom fit 0` 在后；再把缩放钉在手动 1.00x（`zoom 1.0` ⇒ `inv_raw` 恒 256）。
// 这样 lane23.bit19 只剩一个可能来源：`rot_forced`（zoom_snap 的第 20 位）。
// 判据写成**不变量**而不是"应该等于 1"：`bit19 == (生效倍率偏离 256)` ⇒
// 一次同时杀掉"恒 0（回读口根本没接）"与"恒 1（当成常亮旗）"两种糊法；
// G5b 再要求四次里**至少真的钳住一次**，否则上面那条是空判据（#60 那一族）。
send(['rot speed 5', 'rot auto 1', 'zoom 1.0', 'zoom fit 0']);
const s5x = sample(23, 1200);
const s5y = sample(23, 1200);
const r5 = [s5x.a, s5x.b, s5y.a, s5y.b].filter((z) => z && z.alive === 1);
const bad5 = r5.filter((z) => (z.zoom_fit === 1) !== (z.inv !== 256));
const nClamp = r5.filter((z) => z.zoom_fit === 1 && z.inv > 256).length;
line('G5 只留旋转钳（fit 请求已关、手动 1.00x）⇒ lane23.bit19 与"倍率偏离 256"同拍相等',
     r5.length >= 3 && bad5.length === 0,
     `样本=${r5.length} 违例=${bad5.length}` + (bad5.length ? `（首个 raw=0x${bad5[0].raw.toString(16)}）` : ''));
line('G5b 四次里至少真的钳住一次（bit19=1 且 inv>256）—— 不然 G5 是空判据',
     nClamp >= 1, `钳住=${nClamp}/${r5.length}`);

// ---- G3 + G4：follow 位落进那一束，然后一切还原 ----
// 收尾钉回**文档默认档**（#177：默认 = 手动 1.00x，即 `zman=1 zsel=4`）⇒ 用 `zoom 1.0` 而不是 `zoom auto`。
// 今天（r97 板级复验）这里红过一次：我原先写的是 `zoom auto`，于是几何这一段把板子留在呼吸档（zman=0），
// 后面串口电池的"初态=末态"就红在收尾上——红的是我的恢复表，不是设计。恢复表必须与 #177 的默认档同源。
send(['rot auto 0', 'rot speed 0', 'zoom fit 0', 'zoom 1.0', 'split video']);
const c1 = readCfg1();
line('G3 `split video` ⇒ CFG_DATA0 bit24 = 1（缝的分类改在图像列里做）',
     c1 !== null && ((c1 >>> 24) & 1) === 1, c1 === null ? '读不到 CFG1' : `cfg1=0x${c1.toString(16)}`);
const s3 = sample(23, 0);
// G3x 原判的是"bit19 回 0"——那是一条**到不了**的状态：`lane23.bit19 = zoom_fit_en | rot_forced`
//（pl_video_top.v 的 zoom_snap 第 20 位），而命令表里没有把角度归零的动词
//（main.c 的 `rot auto 0` 明写"停在当前角度"，±1° 只有 KEY1/KEY2），所以任何转过角度的收尾
// 都可能由旋转钳把这一位置 1。改成判**同一枚不变量**：`bit19 == (生效倍率偏离 256)`，
// 它照样能红（恒 0 = 回读口没接；恒 1 = 当成常亮旗；两者不同拍 = 接错），但不要求做不到的事。
line('G3x 收尾只留旋转钳那一路：lane23.bit19 与"倍率偏离 256"同拍相等（fit 请求已由 G4 那 19 位判关）',
     !!s3.a && (s3.a.zoom_fit === 1) === (s3.a.inv !== 256),
     s3.a ? `bit19=${s3.a.zoom_fit} inv=${s3.a.inv}（角度停在 ≠0 时 bit19=1 是对的：命令表无归零动词）` : '');
send(['split screen', 'split 50']);
const c2 = readCfg1();
const diff = (c2 === null) ? null : (((cfg0 ^ c2) & GEOM_MASK) >>> 0);
/* #177（2026-09-30，r94）：原来这条拿"进来时那一束"当基准 ⇒ 它的红绿取决于**上一次谁碰过板子**。
 *   今天撞了两次：我为了眼睛判据把板子钉在 `rot auto 1 + src SD`（geom 位 0xa00），于是收尾还原到
 *   默认那一束反而 diff≠0 —— 红的不是"留了自动态"，而是"起点不是默认档"。而这句话真正要钉的是
 *   **跑完之后板子停在演示默认档**（DEFAULTS 那一套），与起点无关。所以：判据换成对默认值，
 *   entry 差只当上下文打印（起点≠默认时它仍然有用：告诉你这一跑顺带把哪些位动了）。 */
line('G4 整串跑完，CFG_DATA0 的 19 个几何位回到演示默认档（不许留自动态；#177 改判默认值而非"与进来时相同"）',
     endsAtDefault(c2), c2 === null ? '读不到 CFG1'
     : `末 19 位=0x${(c2 & GEOM_MASK).toString(16)} 默认=0x${(GEOM_DEFAULT & GEOM_MASK).toString(16)}` +
       `（与进来时差 0x${(diff === null ? 0 : diff).toString(16)}${diff && (cfg0 & GEOM_MASK) !== (GEOM_DEFAULT & GEOM_MASK) ? '；起点本就不是默认档' : ''}）`);

console.log(`\nRESULT ${fail === 0 ? 'PASS' : 'FAIL'} geom_check（ok=${okn} fail=${fail}）`);
process.exit(fail === 0 ? 0 : 1);
