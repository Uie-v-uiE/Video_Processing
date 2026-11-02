// 用途：V8 命令层的验收判据（不是"看看有没有回应"，是逐条对回声 + 收尾对初态）
// 输入：命令行参数
// 输出：stdout
// 退出码：1=FAIL
/**
 * uart_cmd_check.mjs —— V8 命令层的验收判据（不是"看看有没有回应"，是逐条对回声 + 收尾对初态）
 *
 *   node src/host/uart_cmd_check.mjs [--file board/scripts/cmd_battery_v81.txt] [--port COM6] [--dry]
 *
 * 为什么单独有个判据器：命令层是"人敲一条、板子回一行"的东西，没有判据就只能靠人眼逐条读，
 * 而人眼读最容易漏的是**该拒的没拒**（老解析器连 `THE` 都当 `TH` 用）。所以这里每条命令
 * 都带一条"必须出现"的正判据，另有 `!` 开头的"必须不出现"反判据 —— 反例是判据的一部分。
 *
 * 还有一条电池本身给不了的：整串命令跑完之后 `STAT` 必须**等于**跑之前的 `STAT`
 * （除了 pub 位，它是每帧翻的）。不然"命令层能用"是拿"把板子调到别的状态"换来的。
 *
 * 2026-09-26（#66）跟着固件改口径：V7 那五位控制字整个退掉了，于是
 *   ① `[STAT]` 行不再打印 `en=%02x`（那个投影随五位一起没了），效果链的真相只剩 `sel=%03x`
 *      ⇒ 元组里原来由 `en=` 承担的那半件事（"电池不许把效果链留在别的选择上"）**改由 `sel=` 承担**，
 *      判据没有放松：`en` 只有五位，`sel` 是九位，看得见的是超集。
 *   ② 命令里给五位（`pipe 11000` / 裸 `01010` / `pipe 00000`）不再是"设成某个组合"，
 *      而是**一个位都不写**、只回一句"等价的九位是 pipe ……" ⇒ 这三条判据从"必须等于某个 sel"
 *      改成"必须没有 sel= 回声 + 必须回一句正好九个字符的等价串"。
 *      ⚠ 由此带出一条电池自己的过期：结尾那条 `pipe 00000` 以前是"全旁路还原"，现在它不还原任何东西，
 *      于是板上 `sel` 被留在前面那条 `pipe 000100000` 的 0x008 ⇒ 末态 ≠ 初态，本判据会红。
 *      红得对（改了状态就是改了状态），要修的是 `board/scripts/cmd_battery_v81.txt` 那一行改成 `pipe 000000000`
 *      —— 判据不许为了能绿而把 `sel` 从元组里摘出去。
 *
 * 传输走 board/scripts/uart_cmd_script.ps1（PowerShell 自带 SerialPort，本机没有 pyserial），
 * 它按行发、每条前面 echo `>> <行>`，所以捕获能按命令切片。
 */
import { execFileSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';

const PS1 = 'board/scripts/uart_cmd_script.ps1';
const get = (n, d) => { const i = process.argv.indexOf('--' + n); return i < 0 ? d : process.argv[i + 1]; };
const FILE = String(get('file', 'board/scripts/cmd_battery_v81.txt'));
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
/* 五位老写法（#66 之后）的应有回声，三条用例共用同一份，免得"改了格式忘了改另外两条"：
 *   正判据一：走的是 apply_pipe_bits 那条**翻译**出口（`[PIPE] 只收 ……等价的九位是：pipe XXXXXXXXX`），
 *             不是 `pipe` 动词那条长度拒绝出口（`[PIPE] 长度只收 …`）—— 两者不是一回事，分开钉；
 *   正判据二：回的那一串**正好九个字符**（少一个字符的提示等于没提示，多一个字符就是又学会了补零）；
 *   反判据：  一个寄存器都不许写（`sel=` 只出现在 [CTRL] 回声与 [PIPE] 生效行里）。
 * 具体等价串等于什么**不在这里写**：那是 main.c 的 legacy_to_sel 与 proc_pipeline.v 位定义表的事，
 * 由 `src/host/pipe_len_check.mjs` 的 B 组（把真函数抠出来现编跑）判，串口这边只判形状。 */
const FIVE_FORM = [/\[PIPE\] 只收/, /等价的九位是：pipe [01]{9}(?![01])/, /!sel=/];
const EXPECT = [
  // #66：`[STAT]` 打头从 `ctrl en=%02x thr=…` 变成 `ctrl thr=…` —— 老五位那个投影跟着五位一起删了。
  // 头四个字段的位置就是固件那条"字段顺序不许动"的合同；效果链的真相现在只剩 `sel=%03x`（九位），
  // 原来由 `en=` 承担的"电池不许偷偷改效果链"这一步，改由下面那条元组用 `sel=` 承担（是超集，不是放松）。
  [/^\[STAT\] ctrl thr=\d+ src=\d zoom=\d bilin=\d/m, /sel=[0-9A-Fa-f]{3}/],
  [/thr=80/],                                              // th 80（spec 写法）
  [/thr=120/],                                             // TH120（老写法，参数粘着）
  [/\[TH\]/, /!thr=/],                                     // THE：必须拒，且不许写寄存器
  [/\[TH\]/, /!thr=/],                                     // th 光杆：同上
  // 这三条是**五位老写法**（`pipe 11000` / 裸 `01010` / `pipe 00000`）。V8-2 那版它们判的是
  // "老五位翻译成九位之后落在哪几格"（sel=021 / 030 / 000）；#66 把五位那条路整个退掉以后，
  // 固件对这三条**不再写任何位**，只回一句等价串 ⇒ 判据跟着换成上面那份 FIVE_FORM。
  // 形状没放松：以前是"必须等于某个 sel"，现在是"必须一个位都不写 + 必须回正好九个字"。
  FIVE_FORM,                                            // pipe 11000
  FIVE_FORM,                                            // 01010（裸五位，走的是 dispatch 第一条）
  FIVE_FORM,                                            // pipe 00000（当时以为它是"全关"）
  [/src=0/, /\[SRC\]/],                                    // src 0 = 图卡
  [/src=1/],                                               // src 2 = DDR + 起播 SD
  [/src=1/],                                               // src 1 = DDR
  [/\[SRC\] 只认/, /!src=9/],                              // src 9 必须被拒
  [/zoom=0/],
  [/zoom=1/],
  [/bilin=0/],
  [/bilin=1/],
  [/!frame \d+ failed/],                                   // frame 12：不许报失败
  // V9-3：`rot` 不再是"语法已收、硬件待接"。这两条从"必须明说待接"改成"必须真的动那个位"：
  // 留旧判据的话它会一直红（红得对，但报的是过期），而放松成"有回应就算过"又等于没判。
  [/只认：rot auto/, /rot speed/, /!\[CTRL\]/],                 // 裸 rot：用法要说全，而且**不许写寄存器**
  [/\[ROT\] speed=1 度\/帧/],                                  // rot speed 1：回声里带的就是存进去的那个数
  [/\[SPLIT\] auto/, /构建参数/],                              // #51 split auto：真的开了自动扫，并说明端点/速度仍是参数
  [/\[SPLIT\] 只认/, /待接/],                                   // split range 20 80：还没接的那部分必须**明说待接**（不许静默收下）
  // V8-3：gamma 不再是"待接"。这条判据同时钉三件事：回声里的 γ 值、曲线单调、端点 0/255 ——
  // 这三样都是 PS 侧算的（PL 只查表），所以它是 `[GAMMA]` 自检的**外部对照**。
  [/\[GAMMA\] g=1\.80 mono_bad=0 first=0 last=255/],
  [/\[GAMMA\] off/],                                        // 收尾必须关掉：电池不许留下状态改变
  // V9-4 / #112：`osd` 不再是"语法已收，硬件未接"。两条判据成对出现（电池不许留下状态改变）：
  //   off 那条要求回声 `[OSD] osd=off` **且** [CTRL] 回显里 `osd=0`（回显才是写了 gpio_o[20] 的证据），
  //   紧跟一条 `osd on` 把它还原（同样要 `osd=1`）。以前这一格是那条 not_wired 桩的判据，桩删了判据没跟着删
  //   ⇒ 2026-09-29 那一跑它就是"红得没有道理"的那一条（ISSUES #117）。
  [/\[OSD\] osd=off/, /osd=0/],
  [/\[OSD\] osd=on/, /osd=1/],
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
  // #66 之后 help 里那两句话是"帮助与屏相符"的凭据（#67 同族）：语法行把 pipe 的参数写成 `<九位>`，
  // 结尾那条旧写法清单明说"裸五位已随五位控制退役"。少任何一句 ⇒ help 在念上一版的语法。
  [/V8 语法/, /pipe <九位>/, /旧写法仍可用/, /裸五位已随五位控制退役/],
  [/不认: BOGUS/],
  [/sel=0A0/i],                                              // pipe 000001010 = 二值化 + 腐蚀 ⇒ 0x0A0
  [/sel=100/i],                                              // pipe 000000001 = 膨胀           ⇒ 0x100
  [/sel=008/i],                                              // pipe 001000000 = 锐化            ⇒ 0x008
  // ---- r58 立、#66 改的"`pipe` 长度口径"（用户报"必须发 8/10 位才读得到"）----
  // 6/7/8 位过去被静默当成"9 位前面补零"⇒ 命令串与屏上那五格（每格 0..3，另一套写法）对不上。
  // 反例判据 `!sel=` 是这一组的核心：拒了还写寄存器，等于没拒。
  // `/!5（老位序）/` 钉的是**旧口径本身**：那句话以前写的是"长度只收 **5（老位序）或 9（新位序）**"，
  // 五位退掉之后再说"收 5"就是说谎 —— 说谎的回声比没回声更难查（#67 那一族）。
  // 反例串特意写成**不带正则元字符**的字面量：`!` 那一类走的是 includes(source 去掉 '!')，
  // 写成 `!\*\*5` 就变成找字面上的反斜杠星号，等于没判（下面 bad 那里写着这条规矩）。
  [/\[PIPE\] 长度只收/, /九位/, /!sel=/, /!5（老位序）/],   // pipe 00001100（8 位）：必须拒
  [/\[PIPE\] 长度只收/, /九位/, /!sel=/, /!5（老位序）/],   // pipe 1（1 位）：同上
  [/\[PIPE\] sel=008 生效: sharpen/],                        // pipe show：只说名字，不动状态
  // 这一行以前是五位串 `pipe 00000`（"收尾恢复全旁路"）。#66 之后五位串不再生效，
  // 拿它收尾会把 `sel` 悄悄留在上一条的 0x008 ⇒ 末态 ≠ 初态。改成九位零，
  // 于是这条重新是它本来的意思：把效果关回去，并且回声里看得见 sel=000。
  [/\[PIPE\] sel=000/],                                   // pipe 000000000：九位全 0 = 全旁路
  [/\[SD\] autoplay off/],                                  // AUTOPLAY0（老写法，参数粘着）
  [/\[SD\] autoplay on/],                                   // autoplay 1（V8 写法；顺序保证电池结束时仍是默认的开）
  [/src=1/],                                                // SRC2：粘着写法也要认（数下标那种写法就是从这里翻车的）
  [/\[BILIN\] 只认/, /!bilin=/],                             // bilin 2：第三态不存在，必须拒
  [/thr=80/],                                              // TH80：把阈值恢复成 80
  // ---- V8-7 温度八条（与 board/scripts/cmd_battery_v81.txt 结尾那八条一一对位）----
  // sane=1 是这一组里唯一"不许靠放松判据变绿"的一条：raw 读到 0（FIFO 没对齐 / XADC 没释放复位）
  // 会译成 -273.15 °C，读到满码会译成 230 °C，两种都被 sane 挡下；VCCINT 必须在 0.8..1.3 V。
  // 注意 raw 的十六进制是**大写**：`xil_printf` 用的字母表是 0123456789ABCDEF，`%04x` 也一样。
  // 第一次跑这八条时这行红过一回，红在判据写成 [0-9a-f] —— 改判据去配合打印约定，不是放松判据
  // （放松是指把"必须有 4 位十六进制 raw"改成"随便什么都算过"，这里没有）。
  // V9-6 起这一条还钉住"屏上那一格"的三段账：`osd=` 是 OSD 会画出来的那三个字符，
  // `gpio=` 是从 CFG_DATA1 读回来的低字节（= PL 那条同步链正在采的值）。
  // 反引用 `\1\2` 不是装饰：BCD 的一个字节写成十六进制，两位数字就是它的两个半字节，
  // 所以 `osd=47C` 与 `gpio=0x47` 必须同形 —— 不同形就是"编码器算了、寄存器没收到"或反之。
  //（`degC` 与 `osd` 的数值关系留给下面那段 JS 去算：四舍五入不是正则能做的。）
  [/\[TEMP\] degC=\d+\.\d+ raw=0x[0-9A-F]{4} vccint=\d+mv th=85C over=0 sane=1 osd=(\d)(\d)C gpio=0x\1\2/],
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
  // 中段这条是"末态锚点"，比的是头四个字段的位置（合同同第一条）。
  // `/!ctrl en=/` 是新加的反例：`en=` 这个字段随五位一起退掉了，还在打它的 elf 就是旧固件 ——
  // 拿旧捕获跑新判据必须红（本文件开头 --replay 那段讲的就是这条规矩）。
  [/^\[STAT\] ctrl thr=(\d+) src=\d zoom=\d bilin=\d/m, /sel=[0-9A-Fa-f]{3}/, /!ctrl en=/],

  // V8-9：卡上不止一段（META.TXT 的 FILEn）。以前"想看第 3 段"只能人肉去算全局帧号
  //   （`frame 900` 这种），段表明明就在固件里。这四条钉住新加的三件事 + 一条反面：
  //   裸 `sd` 的摘要没被顺手改坏；`sd files` 真的把"每段第几帧"列出来；
  //   `sd file 1` 跳段并念出全局号；`sd file 99` 越界**明确拒绝且不改任何状态**（#67 那条规矩）。
  [/\[SD\]/, /files=|META|card=|frame/i],
  [/\[SD\] \d+ file\(s\)/, /first=\d+/],
  [/file #1 /, /first=\d+/],
  [/只认 0\./, /!file #99/],
  [/\[SPLIT\] 30% -> pos=307/, /屏上 Split 格/],                // #51：发的百分比、写进寄存器的列、屏上那格是同一个数
  [/\[SPLIT\] swap=1/, /不换缝位/],                              // swap 只换内容（原图去右边），缝不动
  [/\[SPLIT\] swap=0/],
  [/\[SPLIT\] marker=0/, /2 像素蓝线/],                          // 关线（#56-2(a) 的另一半）
  [/\[SPLIT\] marker=1/],
  [/\[SPLIT\] pos=307\/1024（显示列） = 29% manual/, /!Auto/, /marker=on/], // show 报的是**执行值**：30% ⇒ 307 列，
  //   百分比向下取整所以是 29（屏上 Split 格用同一个式子）—— 报 50% 反倒说明它在回声上一条命令。
  //   V9-1 之后括号里必须写清量的是哪一种列（显示列 / 画面列），否则 `split video` 之后
  //   "pos=204" 这种数字会被读成 20 % 屏宽（其实是 40 % 画面宽）。
  //   ⚠ `marker=on` 是这次（#105）补上去的：上一行刚把线设回"画着"，show 不跟着报这一格，
  //   就等于"设了没验"—— 而这一族病（发的、执行的、屏上写的三处不同源）在 #66 之后已经有名字了。
  // ---- #105 那四条：写**缝位**不许顺带清掉 marker 位（与电池里 `split marker 0 / split 45 / split show / split marker 1` 同序）----
  // 为什么单独立一组：上面那组只证"marker 自己设得动"；这一组证的是 PS 那句
  // `cur_split = (cur_split & ~SPLIT_POS_MASK) | (px << SPLIT_POS_SHIFT)` 的**掩码宽度**。
  // 掩码抄窄一位，缝位写高值就会溢到相邻位（#177b 刚在 `geom_check.mjs` 里抓到同一个错的手抄版）。
  // 三条判据是一个闭环：关掉线 → 写 45 %（期望 pos=460）→ show 必须**同时**写着 pos=460 与 marker=off。
  // 最后一条把线还原 —— 不还原的话本文件末尾那条"末态 = 演示默认档"（#177）就该红，红得有道理。
  [/\[SPLIT\] marker=0/, /2 像素蓝线/],                          // split marker 0（第二次设，为下一条铺状态）
  [/\[SPLIT\] 45% -> pos=460\/1024/],                            // split 45：(45*1024)/100 = 460，整数除法向下取整
  [/\[SPLIT\] pos=460\/1024（显示列） = 44% manual/, /marker=off/, /!Auto/], // show：缝位进了、线还关着 ⇒ 两位互不干扰
  [/\[SPLIT\] marker=1/],                                        // split marker 1：还原成"画着"（默认档）
  [/\[SPLIT\] 只认/, /!pos=/],                                  // split 150：越界必须拒，且不许写寄存器
  // split 100 这一条钉的是一个**已经修掉的越界写**：缝位字段 [22:13] 只有 10 位（装到 1023），
  // 而屏幕宽 1024 ⇒ 旧固件把 1024<<13 或进去时正好点到 bit23 = auto_en：
  //   用户打 `split 100` 想要"整屏都是处理图"，实际得到的是"缝跳到第 0 列 + 自动扫描开起来"，
  //   而回显还写着 manual（#66 那一族：发的、执行的、屏上写的三处不同源）。
  // 两条判据各抓一半：这一条抓"有没有明说夹了"，下一条抓**存进去的状态**（夹完应是 1023/99%/manual）。
  // 只留第一条会漏：回显说对了、寄存器写错，是这类病最常见的样子。
  [/\[SPLIT\] 100% -> pos=1023\/1024/, /已夹到 10 位上限/],
  [/\[SPLIT\] pos=1023\/1024（显示列） = 99% manual/, /!auto/],
  // 再钉**更坏的那条写口**：换空间那一路不清 auto，所以旧固件在这里 1024<<13 点亮的 bit23 会留下来
  //   —— 板上复现（build/probe_split100b_old.txt）：`split screen` 的回显是
  //   "pos=1024/1024 = 100%，auto 仍开着"，紧接着 `split show` 是 "pos=0/1024 = 0% auto"：
  //   用户要"整屏处理图"，拿到的是"整屏原图 + 自动扫描悄悄开起来"，而回显还说这状态是 inherited 的。
  //   修完之后这四条应当读成 506/512 → 512/512 → 1023/1024（明说夹了）→ manual。
  [/\[SPLIT\] video/, /pos=506\/512/, /!auto/],
  [/\[SPLIT\] pos=512 px = 100%/, /!auto/],
  [/\[SPLIT\] screen/, /pos=1023\/1024/, /已夹到 10 位上限/, /!auto/],
  [/\[SPLIT\] pos=1023\/1024（显示列） = 99% manual/, /!auto/],
  [/\[SPLIT\] 50% -> pos=512/],                                 // 收尾回到默认缝位

  // ================= V9（ISSUES #75）：几何自动化的 20 条 =================
  // 这一段的形状与前面几代一样：**每条都说清"回声里必须出现什么"，拒绝的那几条还要证明
  // 它没写寄存器**（`![CTRL]` —— 拒了还写就等于没拒，与 pipe 长度那组同一招）。
  // 另外顺序是有账的：`rot auto 1` 会顺带开 zoom fit（固件明说了），所以 fit 的那三条排在它后面，
  // 而结尾必须有 `zoom fit 0` + `rot speed 0` + `split 50` 把三个新位还得干干净净 ——
  // 还得回来这件事从今天起由 STAT 末尾那个 `geom=%08x` 把关（19 位控制字的整字指纹）。
  // #178：这一条过去只有 `auto=0` 是**板子进来的状态**给的（电池在它之前从没碰过 rot auto），
  // 所以从"眼睛判据那一态"（`rot auto 1`）起跑就红 —— 红的是起点。现在上一行是 `rot auto 0`，
  // precondition 由电池自己构造，`auto=0 speed=1` 这对组合才是它本来想证的那件事。
  [/\[ROT\] auto=0/, /停在当前角度/],                            // rot auto 0：把这一位由电池自己钉成 0
  [/\[ROT\] auto=0 speed=1/, /zoom=now/],                     // rot show：念的是**第 19 条**（`rot speed 1`）
  //   设进去的值，而不是上电默认。为什么故意这样对：这一条与第 19 条之间，`split`/`zoom`/`gamma`
  //   反复在**整字重写**同一个 cfg1，而 speed 字段（bit 12:10）能原样活到最后
  //   ⇒ 证明没有谁顺手踩了别人的位。反面：念成 speed=0 说明中途有人清了位；念成 speed=3 说明第 19 条写错了字段。
  [/\[ROT\] speed=3 度\/帧/],
  [/\[ROT\] speed 只认 0\.\.7/, /!\[CTRL\]/],                  // 越界：拒 + 不写
  [/\[ROT\] auto=1/, /顺带把缩放切到 fit/],                     // 用户指定的成对语义，回声要说出来
  [/\[ROT\] auto 只认 0 或 1/, /!\[CTRL\]/],
  [/\[ROT\] auto=0/],
  [/\[ZOOM\] fit=0/, /不再由角度定/],
  [/\[ZOOM\] fit=1/, /\(Fit\)/],                              // 屏上那一格的后缀来自同一路
  [/\[ZOOM\] fit 只认 0 或 1/, /!\[CTRL\]/],
  [/\[ZOOM\] fit=0/],
  [/\[SPLIT\] video/, /画面/, /pos=256\/512/],                 // 512/1024 → 256/512：换空间按百分比搬
  [/\[SPLIT\] 40% -> pos=204\/512/, /画面列/],                 // 此刻 40 % 量的就是画面宽
  [/\[SPLIT\] px 只认 0\.\.512/, /!\[CTRL\]/],                 // 上限跟着空间变（不是写死的 1024）
  [/\[SPLIT\] screen/, /显示列/, /pos=399\/1024/],             // 39 %（向下取整）× 1024 = 399
  [/\[SPLIT\] 50% -> pos=512\/1024/],
  [/\[ROT\] speed=0 度\/帧/],
  [/\[GAMMA\] auto：1\.00\.\.3\.00/, /每 2000 ms/],             // 区间与节奏要说出来（否则用户不知道它在动）
  [/auto 停/, /!\[GAMMA] auto：/],   // gamma manual：要说'auto 停了'，而且**不许再打印 auto 那一行**（`!\[GAMMA] auto` 这种写法会被 #165 修好的字面量匹配当成违例 —— 固件正确回声'auto 停了'本来就含 '[GAMMA] auto'，所以反例必须钉到'auto：'那一行的全角冒号上，不是删判据）
  [/\[GAMMA\] off/],                                          // 收尾：γ 复零（关闭 = 逐位旁路，表保留）
  // #99 第二处：`rot auto 1` 会顺带把缩放切到 fit（固件自己说出来），而结尾的 `zoom fit 0` 只关 fit、
  // **不把手动档还回来** ⇒ 初 `zman=1` / 末 `zman=0`。所以这里显式钉回"手动 1.00x"（= 演示默认档）。
  // 判据只用 ASCII：`uart_cap_once.ps1` 那条通道会把固件打的 CJK 落成 `?`（实测），
  // 而 `zoom_step=4 1.00x` 这一截在两条通道里都是原样 —— 不依赖编码的判据才不会看工具下菜。
  [/zoom_step=4 1\.00x/],
  // #99：**片源锚点必须在整串的最后**。中段那组 `src auto/0/2/1/auto` 自己收尾是干净的，但它后面
  // 还有 `sd` / `sd file 1` —— 跳段会让 PS 重新发布一帧（`ps_publish` ⇒ `ps_hold=1`）⇒ `mode` 变，
  // 于是"末态 = 初态"那条比的是两个不同的 mode。r75 之前一直看起来绿，是因为板子的**初态**早已
  // 被上一次电池钉在 ETH 上（初末自然相同）；今天 `ps_app_reload` 之后从 AUTO 起步才把这层揭开。
  [/\[SRC\].*mode=0/],
  // 十六进制必须**大小写都收**：`xil_printf` 的 `%x` 打的是大写（本文件上面 TEMP 那条注释记着这个坑），
  // 而 `geom=00C00400` 这种值以前只写 [0-9a-f] ⇒ 匹配不上、被当成"被心跳劈开"，报的是假诊断。
  [/^\[STAT\].*geom=[0-9A-Fa-f]{8}/m],                      // 末态这一条必须带 geom，否则元组比不了
];

/* `--align`：只做"判据表与命令表逐行对位"这一件事就退出（不碰串口、不需要板子）。
 * 为什么值得单独立一个模式：EXPECT 是**按下标**取的，电池里插一条命令就会让后面每一条错一位 ——
 * 症状是"一大片 FAIL"，最容易被误诊成固件坏了，真正的原因只是判据表没跟着插。
 * 每次动过 board/cmd_battery_*.txt 或这张表，先跑这个（几秒钟）。 */
if (process.argv.includes('--align')) {
  const bat = readFileSync(FILE, 'utf8').replace(/^\ufeff/, '').split(/\r?\n/)
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

/* #177：演示默认档（唯一出处 report/defaults.md 第一节）。`pub` 每帧翻不参与；`frames/playing/sd` 是状态量。
 * ⚠ 这一段与下面的 `--self` 必须放在**碰串口之前**：判据自己的对照实验不该驱动板子，
 *   而过去它排在捕获之后 ⇒ `node src/host/uart_cmd_check.mjs --self` 会把 100 条电池重发一遍，
 *   既占了 COM6，又把我为眼睛判据钉在板上的那一态冲掉（2026-09-30 早上撞的）。
 * ⚠ 字段名左边必须有 `(^|\s)`：`sel=` 是 `zsel=` 的子串，少了这道边界就拿 `zsel` 的值去比 `sel`
 *   的期望 ⇒ 默认档自己判红（--self 第一条对照钉的就是这个形状）。 */
const DEFAULT_TUPLE = [['thr','80'],['src','1'],['zoom','1'],['bilin','1'],['zsel','4'],['zman','1'],
                       ['sel','000'],['gm','0.00'],['mode','0'],['geom','00400000'],['osd','1']];
const fieldOf = (s, k) => s.match(new RegExp('(^|\\s)' + k + '=(\\S+)'));
/** 空/未定义的抓取**不是"默认档不一致"**，是"根本没抓到"——以前这里直接 s.match 抛 TypeError，
 *  把"这一条没测成"伪装成一次崩溃退出（ISSUES #315 第 2 条）。 */
const endsAtDefault = (s) => {
  if (typeof s !== 'string' || s.trim() === '') return null;
  return DEFAULT_TUPLE.filter(([k, v]) => {
    const m = fieldOf(s, k); return !m || m[2] !== v;
  });
};
if (process.argv.includes('--self')) {
  const D = 'thr=80 src=1 zoom=1 bilin=1 zsel=4 zman=1 sel=000 gm=0.00 mode=0 geom=00400000 osd=1';
  const cases = [[D, true, '默认档（zsel 不许冒充 sel）'],
                 [D.replace('geom=00400000','geom=00400A00'), false, '留住 rot auto + 转速'],
                 [D.replace('zman=1','zman=0'), false, '缩放被留在自动呼吸'],
                 [D.replace('thr=80','thr=120'), false, '阈值被改'],
                 [D.replace(' sel=000',' sel=008'), false, '效果链被留在第 4 级'],
                 [D.replace('geom=00400000','geom=00000000'), false, '缝被留在 pos=0（bit22 在掩码外的形状，#177b）'],
                 [D.replace('src=1','src=0'), false, '片源被留在图卡'],
                 ['', false, '空抓取（板子没回话）不许被当成"末态就是默认档"（#315）'],
                 ['   ', false, '只有空白的抓取同上']];
  let bad = 0;
  for (const [s, want, why] of cases) {
    // null = 根本没抓到 STAT。它**不是**"回到默认档"，所以 got 必须是 false（判不出来就是没过）。
    const d0 = endsAtDefault(s);
    const got = d0 !== null && d0.length === 0;
    console.log(`  ${got === want ? 'ok  ' : 'BAD '}${why}: 判 ${got}（期望 ${want}）`);
    if (got !== want) bad++;
  }
  console.log(bad ? 'SELF FAIL uart_cmd_check --self（九条里有一条不按期望动）' : 'SELF PASS uart_cmd_check --self（九条对照都按期望动）');
  process.exit(bad ? 1 : 0);
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
const cap = readFileSync(REPLAY || OUT, 'utf8').replace(/^\ufeff/, '');

const lines = cap.split(/\r?\n/).filter(l => l.startsWith('>> ')).map(l => l.slice(3));
let fail = 0, cursor = 0;

for (let i = 0; i < lines.length; i++) {
  const { seg: s } = seg(cap, lines[i], cursor);
  cursor = cap.indexOf(`>> ${lines[i]}`, cursor) + 1;
  const exp = EXPECT[i];
  if (!exp) { console.log(`SKIP ${i + 1} ${lines[i]} —— 判据表没这一条`); fail++; continue; }
  /* `!` 那一类是"这一段里不许出现"，实现走的是**字面量包含**（`re.source` 去掉 `!` 直接 includes），
   * 所以反例串里**不许有正则元字符**：`!sel=`、`!5（老位序）` 这种真的在判，
   * 而 `!\[CTRL\]` / `!\[GAMMA\] auto` 这种带了转义反斜杠的，找的是字面 "\[CTRL\]"，永远找不到
   * —— 那几条一直在空跑（本文件不动这个机制：把反例修活要连带重订 gamma/rot 那几条的口径，
   *  不是这次"五位退场"的范围，已记进本轮报告）。 */
  /* #165：反例串过去按**字面量**比较，`/!\[CTRL\]/` 找的是含反斜杠的 "\[CTRL\]" ⇒ 永远找不到，
   * 那几条"命令收了却不许写寄存器"的判据一直空跑。现在先把转义还原成字面量再比较。 */
  const bad = exp.filter(re => re.source.startsWith('!')
    ? s.includes(re.source.slice(1).replace(/\\(.)/g, '$1')) : !re.test(s));
  if (bad.length) { console.log(`FAIL ${String(i + 1).padStart(2)} ${lines[i]}\n     缺/违: ${bad.map(r => r.source).join(' | ')}\n     回声: ${s.trim().split('\n').slice(0, 2).join(' ⏎ ')}`); fail++; }
  else console.log(`ok   ${String(i + 1).padStart(2)} ${lines[i]}`);
}

/* 收尾判据：最后一条 STAT 必须等于第一条（pub 位不在比较范围内，它每帧翻）
 * gm= 也在元组里：V8-3 之后"电池不许改变板上状态"必须能抓住"gamma 被留在开着"。
 * V8-8 起 zsel/zman 也进元组：手动档留在板上就是改了状态，与 gamma 同一类，不许靠"看着像 auto"放过。
 * V9（#75）起 geom= 也进元组：那一个字段就是 19 位几何控制字（缝位 / auto / follow / swap /
 * marker / rot_auto / rot_speed / zoom_fit）。少了它，V9 那一串新命令可以把板子留在
 * "自动旋转还开着、缩放还在 fit、缝贴着右边缘"而这条判据依然绿 —— 同一课在 V8-8 就上过。
 * #66：`en=`（老五位的投影）随五位一起从 STAT 行里删了，它那一格由 `sel=%03x` 顶上 ——
 * 这不是放松：`en` 只有五位、而且是投影，`sel` 是效果链那九位的原值（看得见的是超集）。
 * ⚠ 因此电池结尾那条 `pipe 00000` 现在不再"全旁路还原"（五位不再生效），末态 sel 会比初态多一个
 *   0x008 ⇒ 这一条会红，红的是电池（`board/scripts/cmd_battery_v81.txt` 该把那一行改成 `pipe 000000000`），
 *   不是判据。把 `sel` 从元组里摘掉可以让它变绿，但那是把唯一看得见效果链的格子挖掉 ⇒ 不做。
 * 十六进制那两格（sel/geom）大小写都收：`%x` 走的是 xil_printf 的大写字母表（见上面 TEMP 那段）。 */
const cap2 = cap.split(/\r?\n/);
/* ⚠ 不能"每一行以 [STAT] 开头的都必须匹配元组"：串口捕获会把 **周期性的 [SD] 心跳行**
 *   插在一条 STAT 中间（板上每 4 秒打一行帧率），于是那条 STAT 被劈成两半 —— 前半没有
 *   `geom=`，落到 NO_MATCH，整条判据就永远红，而硬件其实没问题（2026-09-25 r62 第一次跑
 *   91 条电池就是这个形状红的：91 条里 90 条 ok，只有元组这一步 FAIL）。
 *   所以改成：**完整的 tuple 至少要有两条**才比；被劈开的碎片**单独报出来数一数**
 *   （不静默放过 —— 碎片变多本身就是在提醒串口在丢行），但不再一票否决。 */
const statLines = cap2.filter(l => l.startsWith('[STAT]'));
/* #117（2026-09-29）：`osd=` 进元组。理由与 V8-8 那次 `zsel/zman`、V9 那次 `geom=` 完全同一课 ——
 * 那天晚上电池里已经有 `osd off` 却没有还原、元组也不看这一格，于是电池把 OSD 留在"关"上而
 * "跑完回到初态"这条照样绿：**判据看不见的那一位，就等于没有判据**。 */
const TUPLE = /ctrl (thr=\d+) (src=\d) (zoom=\d) (bilin=\d) (zsel=\d) (zman=\d).*?(sel=[0-9A-Fa-f]{3}) (gm=\d+\.\d\d).*?(mode=\d) (geom=[0-9A-Fa-f]{8}) (osd=\d)/;
const stats = statLines.map(l => { const m = l.match(TUPLE); return m ? m.slice(1).join(' ') : null; }).filter(Boolean);
const torn = statLines.length - stats.length;
if (torn > 0) console.log(`WARN [STAT] 有 ${torn} 条被串口心跳行劈开（不参与初末比较；碎片 >2 就该查串口丢行）`);
if (stats.length < 2) { console.log('FAIL 没有两条完整的 STAT，初/末态无从比较（抓到的碎片另计）'); fail++; }
else if (stats[0] !== stats[stats.length - 1]) {
  console.log(`FAIL 电池改变了板上状态：初 ${stats[0]} ≠ 末 ${stats[stats.length - 1]}`); fail++;
} else console.log(`ok   跑完回到初态：${stats[0]}`);
/* #177：上面那条证的是"电池没改状态"，它**不证**"板子最后停在演示档"；起点被上一次演示钉歪时
   红的是起点而不是电池（今天 geom_check 的 G4 同族撞了第二次）。补一条与起点无关的判据。 */
{
  const last = stats[stats.length - 1];
  const badF = endsAtDefault(last);
  if (badF === null) {
    // #315：以前这里直接 badF.length 抛 TypeError —— 崩溃会被读成"这一版红得莫名其妙"，
    // 而真相是"这一条根本没测成"。判红，并把原因说出口。
    console.log('FAIL 末态那条 [STAT] 根本没抓到（板子没回话/串口被占/应用没跑）—— 这一条**没测**，按红算');
    fail++;
  } else if (badF.length) {
    const shown = badF.map(([k, v]) => { const m = fieldOf(last, k); return `${k}=${m ? m[2] : ';缺失'}≠${v}`; });
    console.log(`FAIL 电池跑完板子不在演示默认档（report/defaults.md 第一节）：` + shown.join('  '));
    fail++;
  } else console.log(`ok   末态 = 演示默认档（${DEFAULT_TUPLE.map(([k, v]) => k + '=' + v).join(' ')}）—— 与起点无关（#177）`);
}
/* #99 的前提要说出口，不能藏在"回到初态"这四个字里：这条判据证的是**电池不许改变状态**，
 * 它**不**证"初态是演示默认"。r75 那次就是因为初态已被上一轮电池钉在 ETH 上，末态自然相同，
 * 于是这条绿着而电池其实一直在改 mode（同一族：一个从不执行的判据会打 PASS）。
 * 所以这里把初态与文档默认档（手动 1.00x + AUTO 仲裁）比一次，**只报不判**（红绿都不该由
 * 上一次演示留下的状态决定），但必须让明天的人一眼看得见起点是哪一档。
 * ⚠ 与上面 #177 那条的分工别说反：这一条**报**的是起点（不参与红绿），"终点停在演示默认档"
 *   那一句现在是真的**判**了 —— 所以"要后者请重跑"那种劝退话已经不需要，末态红就是红。 */
if (stats.length >= 1) {
  const DEF = 'zsel=4 zman=1';
  const m0 = stats[0].match(/(zsel=\d) (zman=\d)/);
  const mode0 = (stats[0].match(/mode=(\d)/) || [])[1];
  const atDefault = !!m0 && `${m0[1]} ${m0[2]}` === DEF && mode0 === '0';
  console.log(atDefault
    ? `NOTE 初态 = 文档默认档（${DEF} mode=0 AUTO）⇒ 上面那条"回到初态"是在默认档上证的`
    : `NOTE 初态**不是**文档默认档（读到 ${(m0 ? m0[0] : 'zsel/zman 缺失')} mode=${mode0}；` +
      `默认 = ${DEF} mode=0）⇒ "回到初态"只证电池没改状态；板子最终停在哪一档由上面 #177 那条判`);
}

/* ---- V9-6：屏上温度那一格的三方对账（驱动读数 ↔ 编码器输出 ↔ 寄存器实值）----
 * 为什么这一段要写在 JS 里、而不是塞进上面那张正则表：这一格的分工是"PS 算十进制、PL 只照画"，
 * 三段账里唯一需要**算术**才能对上的就是"读数 → 两位十进制"（四舍五入 + BCD 拼），正则做不到。
 * 所以这里在判据器里**另写一份**编码器，与 `src/ps/main.c:temp_code_of` 互为反例源：
 * 谁改了其中一份而没改另一份，这一段就红（同一个手法见 tb_osd_overlay 的字模金表）。
 * 反例：拿没有 `osd=`/`gpio=` 字段的旧捕获跑 —— 必须红，否则这条判据就是在空集上过。 */
{
    const T3 = /\[TEMP\] degC=(-?\d+)\.(\d+) raw=0x[0-9A-F]{4} vccint=(\d+)mv th=\d+C over=(\d) sane=(\d) osd=(\S+) gpio=0x([0-9A-F]{2})/g;
    let m3, n3 = 0, bad3 = 0, anyDeg = 0;
    while ((m3 = T3.exec(cap)) !== null) {
        n3++;
        const deg = parseInt(m3[1], 10), frac = m3[2], mv = parseInt(m3[3], 10);
        // 打印口径是 `%d.%02d`，那两位是 (|mc|/10)%100 ⇒ 还原 = 度×1000 + 两位×10（符号取整数那份）
        const mc = (deg < 0 ? -1 : 1) * (Math.abs(deg) * 1000 + parseInt(frac, 10) * 10);
        const d = (mc >= 0) ? Math.floor((mc + 500) / 1000) : -Math.floor((-mc + 500) / 1000);
        // 下面三行是 main.c:temp_code_of 的同一条门的第三种写法（VCCINT 那一路 + 物理量程 + 两位装得下）
        const want = !((mv > 800 && mv < 1300) && mc > -40000 && mc < 150000 && d >= 0 && d <= 99)
                   ? 0xFF : (((Math.floor(d / 10) << 4) | (d % 10)) >>> 0);
        const osdWant = (want === 0xFF) ? '--'
                      : `${Math.floor(want >> 4)}${want & 0xF}C`;
        const got = parseInt(m3[7], 16), osdGot = m3[6];
        if (got !== want || osdGot !== osdWant) {
            bad3++;
            console.log(`FAIL V9-6 温度格：读数 ${m3[1]}.${m3[2]} / vccint=${mv}mv ⇒ 应画 ${osdWant}` +
                        `（编码 0x${want.toString(16).padStart(2, '0').toUpperCase()}），` +
                        `板上回显 osd=${osdGot} gpio=0x${m3[7]}`);
        }
    }
    anyDeg = cap.split(/\r?\n/).filter(l => l.startsWith('[TEMP] degC=')).length;
    if (n3 === 0) {
        console.log(`FAIL V9-6 温度格：${anyDeg} 行 [TEMP] degC= 但一条都对不上新格式 ⇒ ` +
                    `elf 还没有这一格（或那几行被 SD 心跳劈开了）—— 红着比静默通过好`);
        fail++;
    } else if (bad3) {
        fail += bad3;
    } else {
        console.log(`ok   V9-6 温度格三方对账：${n3} 条 [TEMP] 的 degC↔osd↔gpio 全部自洽`);
    }
}

console.log(`\nRESULT ${fail === 0 ? 'PASS' : 'FAIL'} uart_cmd_check  (${lines.length} 条命令, ${((Date.now() - t0) / 1000).toFixed(1)} s, 捕获 ${REPLAY || OUT})`);
if (fail) console.log(`     ${fail} 条不满足判据`);
process.exit(fail === 0 ? 0 : 1);
