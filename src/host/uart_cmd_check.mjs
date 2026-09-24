/**
 * uart_cmd_check.mjs —— V8 命令层的验收判据（不是"看看有没有回应"，是逐条对回声 + 收尾对初态）
 *
 *   node src/host/uart_cmd_check.mjs [--file board/cmd_battery_v81.txt] [--port COM6] [--dry]
 *
 * 为什么单独有个判据器：命令层是"人敲一条、板子回一行"的东西，没有判据就只能靠人眼逐条读，
 * 而人眼读最容易漏的是**该拒的没拒**（老解析器连 `THE` 都当 `TH` 用）。所以这里每条命令
 * 都带一条"必须出现"的正判据，另有 `!` 开头的"必须不出现"反判据 —— 反例是判据的一部分。
 *
 * 还有一条电池本身给不了的：整串命令跑完之后 `STAT` 必须**等于**跑之前的 `STAT`
 * （除了 pub 位，它是每帧翻的）。不然"命令层能用"是拿"把板子调到别的状态"换来的。
 *
 * 传输走 board/uart_cmd_script.ps1（PowerShell 自带 SerialPort，本机没有 pyserial），
 * 它按行发、每条前面 echo `>> <行>`，所以捕获能按命令切片。
 */
import { execFileSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';

const PS1 = 'board/uart_cmd_script.ps1';
const get = (n, d) => { const i = process.argv.indexOf('--' + n); return i < 0 ? d : process.argv[i + 1]; };
const FILE = String(get('file', 'board/cmd_battery_v81.txt'));
const PORT = String(get('port', 'COM6'));
const OUT = String(get('out', 'board/uart_script_capture.txt'));
const DRY = process.argv.includes('--dry');

/* 每条命令的判据。`!` 前缀 = 这一段里不许出现。
 * 表必须与 battery 文件同序 —— 数量不一致直接红，避免"加了命令忘了加判据"。 */
const EXPECT = [
  [/^\[STAT\] ctrl en=\w\w thr=\d+ src=\d zoom=\d bilin=\d/m],
  [/thr=80/],                                              // th 80（spec 写法）
  [/thr=120/],                                             // TH120（老写法，参数粘着）
  [/\[TH\]/, /!thr=/],                                     // THE：必须拒，且不许写寄存器
  [/\[TH\]/, /!thr=/],                                     // th 光杆：同上
  // V8-2 起 [CTRL] 回声打的是 **sel=%03x**（九位算法字），老五位只剩成它的投影；
  // 所以这三条同时是"老五位 → 新九位"映射的判据：
  //   11000 = gray+binary            ⇒ sel 位 0 与 5 = 0x021
  //   01010 = binary+sobel           ⇒ 位 4,5       = 0x030
  //   00000 = 全关                   ⇒ 0x000
  [/sel=021/i],
  [/sel=030/i],
  [/sel=000/],
  [/src=0/, /\[SRC\]/],                                    // src 0 = 图卡
  [/src=1/],                                               // src 2 = DDR + 起播 SD
  [/src=1/],                                               // src 1 = DDR
  [/\[SRC\] 只认/, /!src=9/],                              // src 9 必须被拒
  [/zoom=0/],
  [/zoom=1/],
  [/bilin=0/],
  [/bilin=1/],
  [/!frame \d+ failed/],                                   // frame 12：不许报失败
  [/语法已收，硬件未接/, /angle_ctrl/],
  [/语法已收，硬件未接/, /angle_ctrl/],                     // rot speed 1 同一个出口
  [/语法已收，硬件未接/, /split_ctrl/],
  [/语法已收，硬件未接/, /split_ctrl/],                     // split range 20 80（四个 token）
  // V8-3：gamma 不再是"待接"。这条判据同时钉三件事：回声里的 γ 值、曲线单调、端点 0/255 ——
  // 这三样都是 PS 侧算的（PL 只查表），所以它是 `[GAMMA]` 自检的**外部对照**。
  [/\[GAMMA\] g=1\.80 mono_bad=0 first=0 last=255/],
  [/\[GAMMA\] off/],                                        // 收尾必须关掉：电池不许留下状态改变
  [/语法已收，硬件未接/, /OSD/],
  [/语法已收，硬件未接/, /缩放因子/],                        // zoom 1.5：on/off 之外都要因子寄存器
  [/V8 语法/, /旧写法仍可用/],
  [/不认: BOGUS/],
  [/sel=0A0/i],                                              // pipe 000001010 = 二值化 + 腐蚀 ⇒ 0x0A0
  [/sel=100/i],                                              // pipe 000000001 = 膨胀           ⇒ 0x100
  [/sel=008/i],                                              // pipe 001000000 = 锐化            ⇒ 0x008
  [/sel=000/i],                                           // pipe 00000：收尾恢复全旁路（电池不许改变板上状态）
  [/\[SD\] autoplay off/],                                  // AUTOPLAY0（老写法，参数粘着）
  [/\[SD\] autoplay on/],                                   // autoplay 1（V8 写法；顺序保证电池结束时仍是默认的开）
  [/src=1/],                                                // SRC2：粘着写法也要认（数下标那种写法就是从这里翻车的）
  [/\[BILIN\] 只认/, /!bilin=/],                             // bilin 2：第三态不存在，必须拒
  [/thr=80/],                                              // TH80：把阈值恢复成 80
  [/^\[STAT\] ctrl en=(\w\w) thr=(\d+) src=(\d) zoom=(\d) bilin=(\d)/m],  // 与第一条逐项比，见下
];

function seg(capture, line, i) {
  const mark = `>> ${line}`;
  const a = capture.indexOf(mark, i);
  if (a < 0) return { seg: '', at: i };
  const nl = capture.indexOf('\n', a);
  const b = capture.indexOf('>> ', nl < 0 ? capture.length : nl + 1);
  return { seg: capture.slice(nl + 1, b < 0 ? capture.length : b), at: (b < 0 ? capture.length : b) };
}

if (DRY) {
  const lines = readFileSync(FILE, 'utf8').split(/\r?\n/).filter(l => l.trim() && !l.trim().startsWith('#'));
  console.log(`[DRY] ${lines.length} 条命令 → ${PS1} -Port ${PORT}；只打印计划，绝不碰串口。`);
  lines.forEach((l, i) => console.log(`  ${String(i + 1).padStart(2)} ${l}   ${EXPECT[i] ? '' : '← 无判据'}`));
  process.exit(lines.length === EXPECT.length ? 0 : 1);
}

const t0 = Date.now();
const out = execFileSync('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', PS1,
  '-Port', PORT, '-File', FILE.replace(/\//g, '\\'), '-DelayMs', '900', '-Out', OUT.replace(/\//g, '\\')],
  { encoding: 'utf8' });
console.log(`[TX] ${out.trim()}`);
if (!existsSync(OUT)) { console.log('FAIL 捕获文件不存在（发送器没跑成）'); process.exit(1); }
// PowerShell 的 -Encoding UTF8 会写 BOM，留下它第一条正则永远对不上
const cap = readFileSync(OUT, 'utf8').replace(/^﻿/, '');

const lines = cap.split(/\r?\n/).filter(l => l.startsWith('>> ')).map(l => l.slice(3));
let fail = 0, cursor = 0;

for (let i = 0; i < lines.length; i++) {
  const { seg: s } = seg(cap, lines[i], cursor);
  cursor = cap.indexOf(`>> ${lines[i]}`, cursor) + 1;
  const exp = EXPECT[i];
  if (!exp) { console.log(`SKIP ${i + 1} ${lines[i]} —— 判据表没这一条`); fail++; continue; }
  const bad = exp.filter(re => re.source.startsWith('!')
    ? s.includes(re.source.slice(1)) : !re.test(s));
  if (bad.length) { console.log(`FAIL ${String(i + 1).padStart(2)} ${lines[i]}\n     缺/违: ${bad.map(r => r.source).join(' | ')}\n     回声: ${s.trim().split('\n').slice(0, 2).join(' ⏎ ')}`); fail++; }
  else console.log(`ok   ${String(i + 1).padStart(2)} ${lines[i]}`);
}

/* 收尾判据：最后一条 STAT 必须等于第一条（pub 位不在比较范围内，它每帧翻）
 * gm= 也在元组里：V8-3 之后"电池不许改变板上状态"必须能抓住"gamma 被留在开着"。 */
const cap2 = cap.split(/\r?\n/);
const stats = cap2.filter(l => l.startsWith('[STAT]'))
  .map(l => { const m = l.match(/ctrl (en=\w\w) (thr=\d+) (src=\d) (zoom=\d) (bilin=\d).*?(gm=\d+\.\d\d)/); return m ? m.slice(1).join(' ') : 'NO_MATCH'; });
if (stats.length < 2) { console.log('FAIL 没有两条 STAT，初/末态无从比较'); fail++; }
else if (stats[0] !== stats[stats.length - 1]) {
  console.log(`FAIL 电池改变了板上状态：初 ${stats[0]} ≠ 末 ${stats[stats.length - 1]}`); fail++;
} else console.log(`ok   跑完回到初态：${stats[0]}`);

console.log(`\nRESULT ${fail === 0 ? 'PASS' : 'FAIL'} uart_cmd_check  (${lines.length} 条命令, ${((Date.now() - t0) / 1000).toFixed(1)} s, 捕获 ${OUT})`);
if (fail) console.log(`     ${fail} 条不满足判据`);
process.exit(fail === 0 ? 0 : 1);
