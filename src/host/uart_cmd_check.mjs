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
/* `--replay <捕获文件>`：不发送、直接判一份**已经存在的**捕获。
 * 存在的理由有两条：① 判据自己要能离线复验（不必每次上板、不占串口）；
 * ② 让"判据过期"与"固件坏了"分得开 —— 拿旧固件的捕获去跑新判据，必须**红**，
 *    红了才说明这条判据真的在看那个字段。 */
const REPLAY = String(get('replay', ''));

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
  [/\[ROT\] \d+ 覆盖=开/, /rot auto/],                    // V8-10 rot 44：真的执行，并念出覆盖与交还路径
  [/\[ROT\] 只认/, /!覆盖=开/],                            // rot speed 1：不认的写法要拒绝，且**不许顺手把覆盖打开**
  [/语法已收，硬件未接/, /split_ctrl/],
  [/语法已收，硬件未接/, /split_ctrl/],                     // split range 20 80（四个 token）
  // V8-3：gamma 不再是"待接"。这条判据同时钉三件事：回声里的 γ 值、曲线单调、端点 0/255 ——
  // 这三样都是 PS 侧算的（PL 只查表），所以它是 `[GAMMA]` 自检的**外部对照**。
  [/\[GAMMA\] g=1\.80 mono_bad=0 first=0 last=255/],
  [/\[GAMMA\] off/],                                        // 收尾必须关掉：电池不许留下状态改变
  [/语法已收，硬件未接/, /OSD/],
  // V8-8：`zoom <倍率>` 不再是"待接"。判据一条管一头，六条连起来把"解析 → 取最近档 → 写进硬件的三位
  //   → 收尾还原"整条链钉住：
  //   1.5  精确命中一档；0.25/2 两个**端点**（越界方向各一个）；0.9 证明取的是"最近"而不是"向下取整"；
  //   auto 交还呼吸（回声必须写"自动呼吸"，否则电池不知道硬件被留在手动档）；
  //   9    解析上限外，必须被拒并提示写法 —— 电池不许改变板上状态，所以 auto 排在 9 之前。
  [/\[ZOOM\].*最近档 1\.50x/, /zoom_step=6 1\.50x \(手动\)/],
  [/\[ZOOM\].*最近档 0\.25x/, /zoom_step=0 0\.25x \(手动\)/],
  [/\[ZOOM\].*最近档 1\.00x/, /zoom_step=4 1\.00x \(手动\)/],              // 0.9 → 1.00x，不是 0.75x
  [/\[ZOOM\].*最近档 2\.00x/, /zoom_step=7 2\.00x \(手动\)/],
  // `zoom 1.0` 是**收尾还原档**：`zoom auto` 只交还呼吸、不改存好的档号，所以要把 zsel 也放回默认的 4。
  // 两条凭据叠在一起才值钱：① r53 第一次跑电池就靠"末态必须等于初态"抓到 zsel=7 ≠ 4；
  // ② 那一版我写的是 `zoom 1`，结果它沿用 V7 的 `ZOOM1` = **开呼吸**（不是 1.0 倍）⇒ 必须写 `1.0`。
  //   这个语义重叠现在由固件的拒绝消息自己说出来（`zoom 0|1` 是开关），别再靠猜。
  [/zoom_step=4 1\.00x \(手动\)/],
  [/zoom_step=\d+ .*\(自动呼吸\)/],
  [/不认的参数/, /0\.75/],
  [/V8 语法/, /旧写法仍可用/],
  [/不认: BOGUS/],
  [/sel=0A0/i],                                              // pipe 000001010 = 二值化 + 腐蚀 ⇒ 0x0A0
  [/sel=100/i],                                              // pipe 000000001 = 膨胀           ⇒ 0x100
  [/sel=008/i],                                              // pipe 001000000 = 锐化            ⇒ 0x008
  // ---- r58：`pipe` 的长度口径（用户报"必须发 8/10 位才读得到"）----
  // 6/7/8 位过去被静默当成"9 位前面补零"⇒ 命令串与屏上五位对不上，这正是那两条抱怨的来源。
  // 反例判据 `!sel=` 是这一组的核心：拒了还写寄存器，等于没拒。
  [/长度只收/, /!sel=/],                                     // pipe 00001100（8 位）：必须拒
  [/长度只收/, /!sel=/],                                     // pipe 1（1 位）：同上
  [/\[PIPE\] sel=008 生效: sharpen/],                        // pipe show：只说名字，不动状态
  [/sel=000/i],                                           // pipe 00000：收尾恢复全旁路（电池不许改变板上状态）
  [/\[SD\] autoplay off/],                                  // AUTOPLAY0（老写法，参数粘着）
  [/\[SD\] autoplay on/],                                   // autoplay 1（V8 写法；顺序保证电池结束时仍是默认的开）
  [/src=1/],                                                // SRC2：粘着写法也要认（数下标那种写法就是从这里翻车的）
  [/\[BILIN\] 只认/, /!bilin=/],                             // bilin 2：第三态不存在，必须拒
  [/thr=80/],                                              // TH80：把阈值恢复成 80
  // ---- V8-7 温度八条（与 board/cmd_battery_v81.txt 结尾那八条一一对位）----
  // sane=1 是这一组里唯一"不许靠放松判据变绿"的一条：raw 读到 0（FIFO 没对齐 / XADC 没释放复位）
  // 会译成 -273.15 °C，读到满码会译成 230 °C，两种都被 sane 挡下；VCCINT 必须在 0.8..1.3 V。
  // 注意 raw 的十六进制是**大写**：`xil_printf` 用的字母表是 0123456789ABCDEF，`%04x` 也一样。
  // 第一次跑这八条时这行红过一回，红在判据写成 [0-9a-f] —— 改判据去配合打印约定，不是放松判据
  // （放松是指把"必须有 4 位十六进制 raw"改成"随便什么都算过"，这里没有）。
  [/\[TEMP\] degC=\d+\.\d+ raw=0x[0-9A-F]{4} vccint=\d+mv th=85C over=0 sane=1/],
  [/\[TEMP\] th=0C/],                                      // temp th 0：把告警线压到环境温度以下
  [/over=1/, /sane=1/],                                    // 于是同一块冷板子也必须报"过热"
  [/\[TEMP\] th=200C/],                                    // temp th 200：抬到物理不可能的位置
  [/over=0/, /sane=1/],                                    // 灭 —— 这两条合起来证明 over 是比出来的
  [/\[TEMP\] th [^=]/, /!th=85C/],                         // temp th 光杆：必须拒（`!` = 不许出现）
  [/\[TEMP\] th [^=]/, /!th=85C/],                         // temp th 999：越界也拒，且自己退回 85
  [/\[TEMP\] degC=.*th=85C .*sane=1/],                     // TEMP（大写）：别名有效 + 阈值已回到默认
  // ---- r58 新加的"串口钉片源模式"（V8-2 欠的那半件事）----
  // 每条都验 `mode=` 这个**回显值**，不是验"有没有回应"：钉错码与钉不住都会在这里露出来。
  // 顺序是 auto → 图卡 → SD → ETH → auto，最后一条把状态还回 AUTO，
  // 于是"末态必须等于初态"那条（下面的元组比对）同时也在管 mode。
  [/\[SRC\].*mode=0/],                                     // src auto：钉回自动（也交还按键环）
  [/\[SRC\].*mode=2/],                                     // src 0：钉图卡（码 2，与 PL 的 M_TEST 一致）
  [/\[SRC\].*mode=3/],                                     // src 2：钉 SD 回放（码 3 = M_SD）
  [/\[SRC\].*mode=1/],                                     // src 1：钉网络（码 1 = M_ETH）
  [/\[SRC\].*mode=0/],                                     // 再 auto：把板上状态还干净
  [/^\[STAT\] ctrl en=(\w\w) thr=(\d+) src=(\d) zoom=(\d) bilin=(\d) zsel=(\d) zman=(\d)/m],

  // V8-9：卡上不止一段（META.TXT 的 FILEn）。以前"想看第 3 段"只能人肉去算全局帧号
  //   （`frame 900` 这种），段表明明就在固件里。这四条钉住新加的三件事 + 一条反面：
  //   裸 `sd` 的摘要没被顺手改坏；`sd files` 真的把"每段第几帧"列出来；
  //   `sd file 1` 跳段并念出全局号；`sd file 99` 越界**明确拒绝且不改任何状态**（#67 那条规矩）。
  [/\[SD\]/, /files=|META|card=|frame/i],
  [/\[SD\] \d+ file\(s\)/, /first=\d+/],
  [/file #1 /, /first=\d+/],
  [/只认 0\./, /!file #99/],
  [/\[OSD\] off/, /一个字都不动/],                          // V8-10 osd 0：关的是画字，明说同步不动
  [/\[OSD\] on/],                                           // osd 1：开回来（末态必须与初态一致）
  [/\[ROT\] 45 -> 44/, /2 度/],                             // 奇数度**不许静默改意**：把实际生效值念回来（#67）
  [/\[ROT\] auto/],                                         // 交还按键 ⇒ 末态角度控制权回到按键那一路
];

/* `--align`：只做"判据表与命令表逐行对位"这一件事就退出（不碰串口、不需要板子）。
 * 为什么值得单独立一个模式：EXPECT 是**按下标**取的，电池里插一条命令就会让后面每一条错一位 ——
 * 症状是"一大片 FAIL"，最容易被误诊成固件坏了，真正的原因只是判据表没跟着插。
 * 每次动过 board/cmd_battery_*.txt 或这张表，先跑这个（几秒钟）。 */
if (process.argv.includes('--align')) {
  const bat = readFileSync(FILE, 'utf8').replace(/^﻿/, '').split(/\r?\n/)
    .filter((l) => l.trim() && !l.trim().startsWith('#'));
  for (let k = 0; k < bat.length; k++) {
    console.log(`${String(k + 1).padStart(2)} ${bat[k].padEnd(18)} | ` +
                (EXPECT[k] ? EXPECT[k].map(String).join(' + ').slice(0, 88) : '*** 缺判据 ***'));
  }
  const ok = bat.length === EXPECT.length;
  console.log(`ALIGN expect=${EXPECT.length} battery=${bat.length} ` +
              `${ok ? 'PASS' : 'FAIL —— 表与命令错位，整轮判据都不可信'}`);
  process.exit(ok ? 0 : 1);
}

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
if (!REPLAY) {
const out = execFileSync('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', PS1,
  '-Port', PORT, '-File', FILE.replace(/\//g, '\\'), '-DelayMs', '900', '-Out', OUT.replace(/\//g, '\\')],
  { encoding: 'utf8' });
console.log(`[TX] ${out.trim()}`);
if (!existsSync(OUT)) { console.log('FAIL 捕获文件不存在（发送器没跑成）'); process.exit(1); }
} else {
  console.log('[REPLAY] 不碰串口，直接判 ' + REPLAY);
}
// PowerShell 的 -Encoding UTF8 会写 BOM，留下它第一条正则永远对不上
const cap = readFileSync(REPLAY || OUT, 'utf8').replace(/^﻿/, '');

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
 * gm= 也在元组里：V8-3 之后"电池不许改变板上状态"必须能抓住"gamma 被留在开着"。
 * V8-8 起 zsel/zman 也进元组：手动档留在板上就是改了状态，与 gamma 同一类，不许靠"看着像 auto"放过。 */
const cap2 = cap.split(/\r?\n/);
const stats = cap2.filter(l => l.startsWith('[STAT]'))
  .map(l => { const m = l.match(/ctrl (en=\w\w) (thr=\d+) (src=\d) (zoom=\d) (bilin=\d) (zsel=\d) (zman=\d).*?(gm=\d+\.\d\d).*?(mode=\d)/); return m ? m.slice(1).join(' ') : 'NO_MATCH'; });
if (stats.length < 2) { console.log('FAIL 没有两条 STAT，初/末态无从比较'); fail++; }
/* ⚠ 先验"元组真的被抓到了"再比相等：正则一旦不匹配，两条都变成同一个 'NO_MATCH' 字符串，
 *   `stats[0] !== stats[last]` 就**永远相等** ⇒ 这条判据永远不会红（V8-8 给 STAT 加 zsel/zman 时，
 *   如果我改正则却忘了改固件，就是这个形状）。"两个都读不到"必须判红，不许判绿。 */
else if (stats.some((s) => s === 'NO_MATCH')) {
  console.log('FAIL [STAT] 元组正则没抓到东西 —— 判据本身过期了（固件行变了，正则没跟着变）'); fail++;
}
else if (stats[0] !== stats[stats.length - 1]) {
  console.log(`FAIL 电池改变了板上状态：初 ${stats[0]} ≠ 末 ${stats[stats.length - 1]}`); fail++;
} else console.log(`ok   跑完回到初态：${stats[0]}`);

console.log(`\nRESULT ${fail === 0 ? 'PASS' : 'FAIL'} uart_cmd_check  (${lines.length} 条命令, ${((Date.now() - t0) / 1000).toFixed(1)} s, 捕获 ${OUT})`);
if (fail) console.log(`     ${fail} 条不满足判据`);
process.exit(fail === 0 ? 0 : 1);
