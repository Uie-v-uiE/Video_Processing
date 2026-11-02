# 30 · 时钟、复位、跨域（CDC）、HDMI 输出与 Zynq 侧的时钟资源

> 读者假设：你会写 C，学过数字电路，知道触发器有建立/保持时间，但没有碰过 FPGA 的时序收敛，
> 也没读过 XDC，不知道 `report_cdc` 那张表怎么读。
>
> 这一章只回答一件事：**这颗 Zynq-7020 里一共有几股时钟，它们在哪里见面，见面时靠什么不
> 打架，以及我怎么知道没打架。**
> 所有结论都带 `文件:行`（相对仓库根 `Video_Processing/`），每一条都在写这一版文档时重新
> grep 过。行号会随提交漂移，对不上就以文件名加信号名重新找，不要相信这里胜过相信代码。
> 本章不碰 MAC/ARP/UDP 的协议内容，只碰它们的**时域交界**；协议那部分在
> `report/study/03_模块详解/01_以太网入包链.md` 与本套 `20_capture_and_display_path.md`。
>
> 概念层的那两篇是本章的前置：`report/study/00_前置知识/02_时钟复位与CDC.md`（亚稳态、
> 三类跨域问题）与 `report/study/02_架构/02_时钟与复位树.md`（架构视角的一张总表）。
> 本章与它们的差别是"为什么长成这样、改它会红什么"，以及把每条结论钉到当前代码的行号上。

---

## 0. 先把名词钉死（后面不再解释）

| 术语 | 一句话解释 |
|---|---|
| **时钟域（clock domain）** | 一组触发器共用同一股时钟边沿，它们的取值只在那条边沿上"算数"。两股没有固定相位关系的时钟就是两个域，它们之间的路径工具无法保证采样落在数据稳定期内。 |
| **MMCM / PLL** | 芯片里的时钟合成器。本项目用的是 `MMCME2_BASE`：吃一个输入时钟，锁到内部 **VCO**（压控振荡器，这里 1000 MHz），再分路出若干低频输出，比例精确、相位可控（`src/rtl/clocks/clk_gen.v:15`）。PLL 是它的简化版（少几路输出与调相能力），本项目没用。 |
| **BUFG** | 全局时钟缓冲器。把时钟接到全片时钟网络，让各处到达延迟尽量一致。MMCM 出来的每一路都要过一级 BUFG 才适合驱动大量触发器（`src/rtl/clocks/clk_gen.v:53-56`）。 |
| **BUFIO / ILOGIC** | 另一种时钟缓冲，**只服务 IO 逻辑（ILOGIC/OLOGIC），不驱动普通触发器**（`src/rtl/eth/rgmii_rx.v:3-4`）。这个限制是 §5.1 之外第 10 节那条 WHS 故事的根。 |
| **IDDR / ODDR** | 输入/输出双沿触发器：时钟上升沿和下降沿各取一个比特，等于把比特率翻倍（`src/rtl/eth/rgmii_rx.v:76-84`、`src/rtl/eth/rgmii_tx.v:33-39`）。 |
| **串行器（serializer）** | 把并行 N 比特按低位在前一个一个送出去。本项目用 `OSERDESE2` 主从级联做 10:1（`src/rtl/hdmi/tmds_serializer.v:15`、`:53`）。 |
| **TMDS** | Transition Minimized Differential Signaling。HDMI/DVI 的线下编码：每 8 bit 像素数据编成 10 bit 符号，三对数据差分线 + 一对时钟差分线，全速串行。 |
| **亚稳态（metastability）** | 触发器在建立/保持窗口里被变化的数据"卡住"，输出既不是 0 也不是 1，要过一会儿才随机落到某一侧。跨时钟域直接采信号就会撞上它，而且**决断值与你的输入无关**。 |
| **同步器（打两拍/三拍）** | 对付亚稳态的标配：源信号先被目的时钟采一级（承认可能亚稳），再连采一两级把它稳定下来。`(* ASYNC_REG = "TRUE" *)` 是给工具的承诺——"这几个触发器是刻意挨着放的"，不标它可能被优化拆开。本项目清一色带 `ASYNC_REG`，但**级数不统一**：单 bit 电平/事件多为 3 级（`src/rtl/top/pl_video_top.v:426-431`、`:439-444`、`:446-451`），`effect_ctrl` 里那三对控制字链是 2 级（`src/rtl/process/effect_ctrl.v:34-39`）。级数差别的道理写在 `src/rtl/util/ps_publish.v:17`：前两级打异步，**第三级专门给"异拍出沿"用**——所以"只当电平读"的 2 级够用，"要抓边沿"的必须 3 级。 |
| **跨域 FIFO（异步 FIFO / 格雷码 FIFO）** | 两边各用自己的时钟读写同一个双口存储，读写指针换成**格雷码**（相邻计数值只差 1 bit）后跨域，于是误采只可能读到一个"旧的"指针，不会读到一个"半新半旧"的指针（`src/rtl/eth/dc_fifo.v:31-32`、`:69`）。 |
| **翻转位（toggle）+ 边沿检测** | 要跨的是一个单拍脉冲时，先在本域把它变成"每发生一次就翻转一位"，目的域打三拍再异拍出沿。脉冲直接跨会被整拍吃掉（`src/rtl/util/key_long.v:4-5`、`src/rtl/eth/ddr_bank_commit.v:37-47`）。 |
| **准静态总线 + 快照** | 宽总线跨域的唯一安全做法：源域**整拍**写好总线并同拍翻转一个 toggle，目的域等同步过来的沿再采整条总线，于是采到的必是完整值（`src/rtl/eth/snap_cross.v:2-5`、`:60-63`）。 |
| **CDC-10 / CDC-11 / CDC-6** | `report_cdc -details` 的规则号。CDC-10 = 同步器之前挂了组合逻辑；CDC-11 = 同一个发射触发器扇出到**两组**目的域同步器；CDC-6 = 多位总线过同一组带 `ASYNC_REG` 的同步器（工具不知道那是格雷码）。三个号在本仓库都真实红过，见 §5 与 §6。 |
| **AXI-Lite 寄存器 / AXI GPIO** | PS 用一条简单的 AXI-Lite 总线读写 PL 里的寄存器。本项目用三个 `axi_gpio` IP 当"信箱"：写 32 bit 就是发命令，读 32 bit 就是收遥测（`build/tcl/build_system_axigpio.tcl:184-192`）。 |
| **XDC** | 约束文件（`*.xdc`）：告诉工具哪个脚在哪、时钟多少周期、哪些路径不用算。综合与实现都读它，但**读哪几份可以不一样**，这是 §8 的主题。 |
| **WNS / WHS / WPWS** | Worst Negative/Healthy Slack：全设计最差的一条 setup 余量与 hold 余量；WPWS 是最差脉宽余量。负数就是没守住。见 §10。 |

一张表先记住本章的对象：本仓库当前有**六股时钟、两颗 MMCM、四个真实跨域方向**。
其中一股（250 MHz）里没有任何用户逻辑，一股（200 MHz）只有一个负载——
这两个事实本身就是 §1 与 §7 的结论，不是巧合。

**验证动作。** 先把六股钟的名字与频率从已布线报告里抄出来，它是本章所有数字的锚：

```bash
awk '/^\| Clock Summary/,/^\| Intra Clock Table/' build/timing_summary.rpt | grep -E "^[a-z ]" 
```

期望看到 8 行：`clk_fpga_0` 10.000 ns、`eth_rxc` 8.000 ns、`sys_clk` 20.000 ns，
外加缩进的生成钟 `clkfbout`、`clkfbout_1`、`clkout0_1`、`clkout1_1`、`clkout2`
（当前这份的段落在 `build/timing_summary.rpt:164-171`）。缩进 = 生成钟，
非缩进 = `create_clock` 造出来的，这个区别在 §8 会变得重要。

---

## 1. 这颗芯片里一共有几股时钟

**是什么。** 到 PL 的**外部**时钟源只有两根：板上 50 MHz 晶振 `sys_clk`
（`src/rtl/top/system_top.v:25`，封装脚 W17，`src/constraints/rk_zynq7020.xdc:5-6`）
和 PHY 随 RGMII 一起送过来的 `eth_rxc` 125 MHz（引脚 Y19，
`src/constraints/rk_zynq7020.xdc:20`、`:36`）。第三根 `clk_fpga_0` 100 MHz 不是外部输入，
是 PS 内部 FCLK0 从 BD 引出来再喂回 PL 的（`src/rtl/top/system_top.v:82`）。
其余四路全是 MMCM 生成的。

**为什么要这几股。** 四件事各自要求完全不同的节拍，凑不到一股钟上：

- 显示扫描必须**正好**是面板时序需要的那个像素率（1024×600 的 H_TOTAL 1344 ×
  V_TOTAL 625 ≈ 50 MHz，见 §7），而且必须是 MMCM 出来的低抖动钟；
- TMDS 线下每比特率是像素率的 10 倍，串行器要一路**正好 5 倍**于像素钟的高速钟
  （DDR 出 2 bit ⇒ 5 × 2 = 10）；
- AXI 事务希望越快越好，而它的频率**由 PS 定**，PL 无权改；
- RGMII 的采样时钟**必须由 PHY 给**——数据是跟着对方时钟来的，本端只能恢复、不能选速。

**原理怎么推。** 多路输出挂**同一颗** MMCM 的好处是：它们同源、比例精确、相位已知，
彼此之间的路径仍然是**同步路径**，工具能做真正的 setup 分析。反过来，一旦两股钟来自
不同 MMCM（或一个来自板晶振、一个来自 PS），它们之间就没有任何相位关系，
只能靠电路结构保证正确性。所以"该在一起的两股钟一定同一个 MMCM"是布局时序的前提。
本项目真的有两颗 MMCM，第二颗只为了取 200 MHz 参考钟（下面第 2 点会看到它的后果）。

**实现（对代码）。** `src/rtl/clocks/clk_gen.v` 全文只有 57 行，值得逐行读：

- 输入 50 MHz（`.CLKIN1_PERIOD (20.000)`，`:17`）；
  VCO = 50 × 20 = 1000 MHz（`.CLKFBOUT_MULT_F (20.000)`，`:19`，文件头 `:3` 写的就是这笔乘法）。
- `clk_pix` = 1000 / 20 = **50 MHz** 像素钟（`.CLKOUT0_DIVIDE_F (20.000)`，`:21`），
  网表里的时钟名是 `clkout0_1`。
- `clk_pix5x` = 1000 / 4 = **250 MHz**（`.CLKOUT1_DIVIDE (4)`，`:24`），网表名 `clkout1_1`。
- `clk_200m` = 1000 / 5 = **200 MHz**（`.CLKOUT2_DIVIDE (5)`，`:27`），只作 IDELAY 参考钟。
- `RST(~rst_n)`（`:49`）、`LOCKED(locked)`（`:50`），四路各过一级 BUFG（`:53-56`）。

`1000/4`、`1000/5`、`1000/20` 三个除法都是整数，这是能这么摆参数的**唯一**原因：
VCO 必须落在 600–1200 MHz，输出分频必须是整数（CLKOUT0 允许小数，其余不允许）。
这一条在仿真侧也被刻意守住——`sim/prim/MMCME2_BASE.v:7` 写着"分频比一个都不写在模型里，
全部从例化参数读回来"，所以 RTL 改了比例模型会跟着改，不会出现"两处各说一遍"。

**实现（对 BD）。** PS 侧 FCLK0 在 BD 里被显式声明成 100 MHz 端口：
`build/tcl/build_system_axigpio.tcl:150`
（`create_bd_port -dir O -type clk -freq_hz 100000000 FCLK_CLK0`），
源头配置是同一脚本 `:41` 的 `CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100}`。
但**真正那条 `create_clock` 不在我们的 XDC 里**，而在 PS7 IP 自带的约束里：
`vivado_system/zynq_video_sys.gen/sources_1/bd/design_1/ip/design_1_processing_system7_0_0/design_1_processing_system7_0_0.xdc:20`
（`create_clock -name clk_fpga_0 -period "10" [get_pins "PS7_i/FCLKCLK[0]"]`）。
注意它是 `get_pins` 不是 `get_ports`——它约束的是 PS7 实例内部的一根线，
我们的手写 XDC 取不到这个名字。§8 那条"异步时钟组必须拆文件"的全部理由就是这一行。

**六股域，一张表**（频率出处：`build/timing_summary.rpt:164-171` 的 Clock Summary；
负载数出处：`build/clock_util.rpt`）：

| 域（网表名） | 频率 | 从哪来 | 谁住在这里 | 负载实测 |
|---|---|---|---|---|
| `sys_clk` | 50 MHz | 板上晶振 W17 | 两颗 MMCM 的输入、按键消抖与长按（`src/rtl/top/pl_video_top.v:132-146`）、旋转角累加（`:179-184`）、FPS 计数与心跳 LED（`:886-895`、`:978-981`） | `timing_summary.rpt:183` 组内 255 端点 |
| `clkout0_1`（`clk_pix`） | 50 MHz | MMCM#1 CLKOUT0 | 显示扫描、逆映射、效果链、混合、OSD、帧缓存读口 | `clock_util.rpt:59` 4774 loads / 6 个时钟区 |
| `clkout1_1`（`clk_pix5x`） | 250 MHz | MMCM#1 CLKOUT1 | **没有任何普通逻辑**：只挂 8 个 `OSERDESE2` 的 CLK 脚 | `clock_util.rpt:63` 8 loads，`clock_util.rpt:220` 的 Slice Loads = 0 |
| `clkout2`（`clk_200m`） | 200 MHz | **MMCM#2** `u_idelay_clkgen` CLKOUT2 | 只给 `IDELAYCTRL` 当参考 | `clock_util.rpt:65` 1 load |
| `clk_fpga_0`（`axi_clk`） | 100 MHz | PS FCLK0 | 所有 AXI 事务、AXI GPIO、仲裁、时延测量、lane 读回 | `clock_util.rpt:60` 3591 loads，驱动脚是 PS7 内部 BUFG |
| `eth_rxc` → `gmii_rx_clk` | 125 MHz | PHY（引脚 Y19），经 IBUF → **一只 BUFG**（#57 之后解串器与 fabric 同一棵树）| RGMII 解串、整条自研协议栈、`frame_reasm`、`link_monitor`、`dc_fifo` 写侧 | `clock_util.rpt:61` BUFG 那路 2471 loads / 4 个时钟区 |

三个容易看错的地方：

1. **综合后 125 MHz 那条全局网线的名字不是 `eth_rxc`。**
   `src/rtl/eth/gmii_to_rgmii.v:25` 有一句 `assign gmii_tx_clk = gmii_rx_clk;`，
   发送侧不发自己的时钟，于是工具给时钟网络取了别名
   （`clock_util.rpt:61` 的 Net 列写的是 `u_eth/u_rgmii/u_rgmii_rx/gmii_rx_clk`）。
   看报告时别以为是两根钟。也正因为这句，`arp` / `icmp` / `udp_tx` / `eth_ctrl`
   全都和收侧在同一个域（`src/rtl/eth/eth_udp_video_top.v:131`、`:144`、`:164`、`:207`）——
   **GMII 侧内部不算跨域**。
2. **`clkout2`（200 MHz）来自另一颗 MMCM，和像素钟不同源。**
   `src/rtl/top/system_top.v:117-121` 第二颗 `clk_gen u_idelay_clkgen` 把
   `clk_pix` / `clk_pix5x` 接到名字就叫 `clk_pix_unused / clk_pix5x_unused` 的空线上（`:115`），
   只取 `clk_200m` 与 `locked`。为什么要第二颗：第一颗在 `pl_video_top` 里面
   （`src/rtl/top/pl_video_top.v:124-127`），而 IDELAY 参考钟要在 `system_top` 这一层拿。
   两颗同频但**互相异步**；第二颗的 `rst_n` 直接钉 `1'b1`（`system_top.v:118`），它从不下电复位。
3. **250 MHz 域里没有逻辑，所以 HDMI 这一级根本不需要同步器。**
   `din` 在 `clk_pix` 里寄存（`src/rtl/hdmi/tmds_encoder.v:42-73`），
   `OSERDESE2` 的并行装载沿是 `CLKDIV = clk_pix`（`src/rtl/hdmi/tmds_serializer.v:32`），
   `CLK = clk_pix5x` 只负责移出（`:31`）。三条互相独立的凭据：
   `build/cdc.rpt:17-24` 那张配对表里**根本没有 `clkout0_1 ↔ clkout1_1` 这一对**；
   `build/timing_summary.rpt:942-944` 里 `clkout1_1` 自己的 Setup 与 Hold 写的是 `NA`；
   `build/clock_util.rpt:220` 显示它的 Slice Loads = 0。

**你可以自己验证。** 上面第 3 条是本章最容易误判的一条（"250 MHz 这么快，一定跨了域"），
两条命令就能否掉它：

```bash
grep -c "clkout1_1" build/cdc.rpt
awk 'NR>=939 && NR<=944' build/timing_summary.rpt
```

期望：第一条输出 **0**（`report_cdc` 从没把 250 MHz 当成跨域的一端，
连一行 `clkout0_1 ↔ clkout1_1` 都没生成）；第二条打印 `clkout1_1 → clkout1_1` 那一组的
三行小结，其中 **Setup 与 Hold 两行写的是 `NA`**（不是 0 个端点，是**根本没有这类路径**），
只有 `PW` 那一行有数（0 failing / Worst Slack 2.408 ns）。
"NA 而不是 0"是关键区别：0 意味着"检查过、都过"，NA 意味着"这一级不进 fabric 的建立分析"。

---

## 2. 复位树：四条复位，以及"异步释放"这件事的代价

**是什么。** 本工程有四条互不相同的复位，各自管一个域：

| 复位 | 表达式 | 管的域 | 代码位置 |
|---|---|---|---|
| `sys_rst_n` | 顶层**恒 1'b1** | `sys_clk` | `src/rtl/top/system_top.v:244`（`.sys_rst_n(1'b1)`） |
| `axi_rst_n` | PS 的 `FCLK_RESET0_N` | `clk_fpga_0` | `src/rtl/top/system_top.v:82`（`.FCLK_RESET0_N(fclk0_rst_n)`）→ `:245` |
| `rst_pix_n` | `sys_rst_n & locked` | `clk_pix` / `clk_pix5x` | `src/rtl/top/pl_video_top.v:128` |
| 以太网侧 `rst_n` | `eth_rst_n & mmcm_locked` | `eth_rxc` | `src/rtl/top/system_top.v:159` |

**为什么这样分。** 三个理由，都能对上代码：

1. **板上没有可用的复位输入**，所以顶层把 `sys_rst_n` 钉成常量（`system_top.v:244`），
   第二颗 MMCM 的 `rst_n` 也钉 `1'b1`（`:118`）。真正的"复位责任"落在两件事上：
   MMCM 的 `locked`，和 PS 的 `FCLK_RESET0_N`。
2. **PS 那一路是 BD 端口、低有效**，由 `FCLK_RESET0_N` 出（`system_top.v:82`），
   AXI GPIO 的复位也挂在这一支上。这是唯一一条"外部会真的拉下来"的复位。
3. **MMCM 没锁之前，像素域的一切都没有意义**，所以 `rst_pix_n = sys_rst_n & locked`
   （`pl_video_top.v:128`）。同理 RGMII 那一路是"PHY 复位释放**且** IDELAY 那颗 MMCM 已锁"
   （`system_top.v:159`，`mmcm_locked` 来自 `:117-121` 那颗）。

**`eth_rst_n` 是数出来的，不是等来的。** `src/rtl/top/system_top.v:107-111`：
50 MHz 上一个 24 位计数器，`assign eth_rst_n = phy_rst_cnt[23];`（`:111`）
⇒ 上电后约 2^23 拍 ≈ 168 ms 才拉高。PHY 的数据手册要的是"上电后复位保持若干毫秒"，
这里用计数器满足它。因为它是**输出**，所以 XDC 里只能写成 `set_false_path -to`
（`src/constraints/rk_zynq7020.xdc:55`）——`:51-54` 记着一条老教训：
以前写成 `-from`，每次综合都吃一条 `CRITICAL WARNING [Constraints 18-513] ...
contains no valid startpoints`，那是一条**空约束**：不约束任何东西，只制造噪声。

**为什么复位是异步释放。** 代码里清一色 `always @(posedge clk or negedge rst_n)`
（例：`src/rtl/top/pl_video_top.v:162`、`:209`、`src/rtl/eth/dc_fifo.v:38`、`:58`）。
理由很直白：`clk_pix` 在 MMCM 锁定之前根本没有可靠的时钟沿，
如果复位是"异步断言、同步释放"，那一域的触发器要等同步释放逻辑走完才出复位态，
而那套逻辑自己也需要一个可信时钟——循环依赖。代价是**释放瞬间的 recovery/removal 完全交给物理**，
而 `locked` 在这里是直接和 `sys_rst_n` 相与、没有额外打拍（`pl_video_top.v:128`），
`locked` 又直接扇出到整个像素域的 CLR。这一处是本仓目前唯一一处"目的域拿异步信号直接当复位"
的写法（我的判断，依据是全仓 `rst_pix_n` 的产生处只有这一行引 `locked`）。
仓库没有为它单独写判据，只在台架里钉住它的**结果**：
`sim/tb_v99_unisim_sim.v:76` 的 C2 要求复位释放后 `locked` 为 1，
判据文案写的是"它就是 `rst_pix_n = sys_rst_n & locked` 的另一半"。

**和同步链的复位值相关的那条老规矩（这段必读）。**
同步链的**复位值必须等于源头复位后的值**，否则"复位释放"本身就是一次数据跳变。
真实事故：长按翻转位的三级链复位成 `3'b111`，而源头 `key_long.tog` 复位是 0
（`src/rtl/util/key_long.v:27`）⇒ 链里灌进的第一个 0 让异拍出沿为真连续两拍
⇒ 一次都没按的板上白走两步 AUTO→锁 ETH→锁 SD，`force_eth` 就此长占，"停流交回"永不发生。
事故经过与逐拍解释写在 `report/log/ISSUES.md:874-911` 一族；
台架侧的复述更紧凑：`sim/tb_v82_src_mode.v:4-8`
（"核心判据只有一条：**一次都没按，模式不许动**"）。
修法不是只把复位改成 0，而是**复位后先给 8 拍灌满期**，期间让比较基准跟住链尾
（`src/rtl/util/src_mode.v:36` 的 `settle`，`:62-65` 那段"灌满期里让 `prev` 跟住链尾，
别把历史当事件"）。为什么必须补这一段：像素复位在换分辨率/掉锁时还会再来一次，
那时 `tog` 完全可能停在 1，光把复位值对齐是不够的。
这段逻辑以前写在顶层里，"顶层没有任何台架碰得到它"正是它能藏一整天的原因，
所以被抽成独立模块（`src/rtl/top/pl_video_top.v:149-151` 记着这次搬迁的理由）。

**还有一条容易忘的：同步链可以不带复位。**
`src/rtl/top/pl_video_top.v:883-884` 那三级 `vt0/vt1/vt2` 写的是
`always @(posedge sys_clk) {vt2,vt1,vt0} <= {vt1,vt0,vs_tick};`——没有 `if (!rst_n)`。
这是有意的：移位链带复位会妨碍工具把它认成一条完整同步器，而且它的"复位值 vs 源头值"
问题由 §2 上面那条灌满期规矩在**别的**链上解决。紧挨着它的下一段（`:886-895`）却是
`always @(posedge sys_clk or negedge rst_pix_n)`——**用像素域的复位脚清 `sys_clk` 域的计数器**。
这是一处真实的跨域复位，`cdc.rpt` 不报它（那份报告只管数据路径），
它现在不出问题是释放只发生在上电那一次（推断，本仓没有为它写判据）。

**复位还要服从推断。** 异步 FIFO 的存储阵列**故意不带复位**
（`src/rtl/eth/dc_fifo.v:47-51`，注释 `// memory write: no reset → BRAM-friendly`），
同步 FIFO 同理（`src/rtl/eth/sync_fifo.v:3-4`，那里还多记一句实测后果：
带异步复位时大深度 `icmp_fifo` 落到寄存器堆，直接把 `eth_rxc@125 MHz` 域打成 WNS 负数）。
道理是同一句：带异步复位的存储推断不出 BRAM，会被摊成几万个触发器。

**你可以自己验证。** 复位树不需要构建就能审，三条静态检查：

```bash
grep -rn "or negedge" src/rtl/top/pl_video_top.v | grep -c "posedge clk_pix"
grep -n "sys_rst_n" src/rtl/top/system_top.v
grep -n "no reset\|BRAM-friendly\|异步复位" src/rtl/eth/dc_fifo.v src/rtl/eth/sync_fifo.v
```

期望：第一条给出一个非零数字（像素域清一色异步复位）；第二条只应命中
`.sys_rst_n(1'b1)` 那一行（`system_top.v:244`）——如果哪天它变成别的表达式，
说明有人给顶层接了真复位输入，§4 的清单要重画；第三条应命中
`dc_fifo.v:47` 与 `sync_fifo.v:3` 两处"不带复位"的注释。

---

## 3. 跨域的四种正规做法，以及各自的适用边界

**是什么。** 工具替代不了的规矩只有四条，按"要跨的东西是什么形状"分：

| 要跨的东西 | 错误做法（本仓真实踩过） | 正规做法 | 本仓的现成实现 |
|---|---|---|---|
| 单 bit **准静态电平** | 直接采 | 3 级 `ASYNC_REG`，同步后当电平用 | `pl_video_top.v:426-431`（`src_sel`）、`:446-451`（`eth_link`）、`:472-477`（`owner_eth`）、`:254-262`（`bilin_en_axi`）；`eth_udp_video_top.v:272-276`（`gapclr_sel`） |
| 单 bit **事件（1 拍脉冲）** | 把脉冲接到对方时钟；或"看起来更稳"的电平型 3 级同步 | 翻转位 → 3 级 → 目的域异拍出沿 | `ddr_bank_commit.v:37-47`；`frame_commit_lock.v:106-109` + `pl_video_top.v:439-444`；`ps_publish.v:18-25`；`key_long.v:41` → `src_mode.v:59`；`angle_ctrl.v:24-29` |
| **宽总线**（>1 bit，会跳变） | 每一位各自打拍再拼 | 准静态总线 + toggle + 目的域边沿捕获 | `snap_cross.v`（`system_top.v:198-202`、`pl_video_top.v:821-825`、`:622-626`、`:925-930`）；`zoom_snap.v:5-7` |
| **连续数据流** | 加深度、限流、或靠"平均速率够"论证 | 格雷码异步 FIFO | `dc_fifo.v`（`eth_udp_video_top.v:294-301`，36 bit × 8192） |

**为什么要分形状，而不是"统一打三拍"。** 因为三拍的语义只有一条：**目的域看到的
是一个已经稳定了至少两拍的电平**。它对"电平"是对的，对"脉冲"是错的（脉冲可能在两拍
之间已经过去，采到 0 次），对"多位总线"是灾难（每位各自决断，读到根本不存在的中间值）。
本仓对这三条都付过学费，最贵的一次是 §5 会讲的 `copy_abort`。

**原理怎么推：为什么宽总线必须"整拍写 + toggle"。**
`snap_cross.v:3-5` 那句话是完整的推导：源域把宽总线**整拍**写好、同拍翻转 `bus_tog`；
沿要过 3 级同步才到目的域（`:29-36`），而源总线至少保持到下一次写入——
本项目 ≥1 ms——所以目的域采的那一刻，总线一定还是同一份值，不会撕烈。
关键在于**"准静态"这三个字必须有来源**，它是设计约束不是自然规律：

- `link_monitor` 的 320 bit 快照由 `SETTLE=32` 个源周期节流（`link_monitor.v:10`、`:156-157`、`:162`），
  两次写入之间必留 256 ns；
- 19 bit 几何控制字在 axi 域每 `17'h1FFFF` 拍整抄一次并翻 toggle
  （`pl_video_top.v:807-820`，`:813` 那个计数在 100 MHz 下 = 1.31 ms）；
- 像素域→axi 的缩放实况只在**帧首**换总线，且发沿再推迟 8 个像素周期
  （`zoom_snap.v:5-7`：不变量①总线每帧只换一次、②沿翻在总线已稳定之后，"早一拍都不行"）。

**实现：`snap_cross` 这一个模块干了两件事。**
除了总线捕获（`:60-63`，只在 `bus_edge` 那一拍写 `bus_q`），它还独立看**源时钟健康**
（`:39-58`）：`hb_tog` 是心跳翻转位，目的域数"隔了多久没等到沿"，量到 `to_cnt < FAST_ENOUGH`
就把 `hb_slow` 置 1（`:52`），量到 `to_cnt` 归零就把 `hb_gone` 置 1（`:54-56`）。
为什么慢与停要分两位——文件头 `:6-7` 与 `:51` 给了答案：
**源时钟变慢 ⇒ 目的域量到的心跳间隔变长**（不是变短），而 RTL8211 断链时不停供 RXC
而是把它拉到约 1/48，只测"心跳有没有停"不够，`hb_gone` 永远不会触发。

**实现：`effect_ctrl` 为什么把三对同步器写成"同源同深度"。**
`src/rtl/process/effect_ctrl.v:29-39` 那三对（13 bit / 8 bit / 32 bit）都带 `ASYNC_REG`，
文件头 `:3-4` 写着"这三对寄存器都是跨域入口，必须 ASYNC_REG，否则工具会把它们当普通
逻辑优化掉（这条踩过）"。而 `:30-33` 与 `:36-38` 讲的是另一件事：**同一件事的多个位
必须过同一条链**。缩放的手动旗标与档号分两组同步，就会出现"旗标到了、档号还是上一次的"；
gamma 的 `wr` 与 `idx/data` 分两组同步，就会出现"边沿到了、数据还是上一次的"。
这不是风格偏好——它是协议前提。

**你可以自己验证。** 一条命令列出全仓所有同步器入口，看它们的分布：

```bash
grep -rc "ASYNC_REG" src/rtl --include=*.v | grep -v ":0" | sort
```

期望：命中集中在 `pl_video_top.v`（12 处）、`effect_ctrl.v`（6）、`frame_commit_lock.v`（3）、
`src_mode.v`（3）、`snap_cross.v`（2），外加 `ddr_bank_commit.v`、`eth_udp_video_top.v`、
`angle_ctrl.v`、`ps_publish.v`、`system_top.v`、`frame_latency.v` 各 1 处。
**`dc_fifo.v` 应该一个都不出现**——这不是漏写：它两条指针同步链（`:70-76`、`:77-83`）
刻意没打 `ASYNC_REG`，这正是 `build/cdc.rpt:17`、`:20-21` 末尾那三行
"No ASYNC_REG = 2 / 14 / 14" 的来源之一（汇总表不点名，要点名就交给 §6 的 `cdc_who.tcl`）。
然后跑一遍门禁里那条 CDC 判据的解析式，看工具同意不同意这份清单：

```bash
awk '/^Critical/{print $2">"$3, $(NF-4), $(NF-2)}' build/cdc.rpt | sort
```

期望两行（`build/cdc.rpt:17-18`）：`clk_fpga_0>clkout0_1 99 1` 与 `sys_clk>eth_rxc 1892 2`。
第三列就是 unsafe，§6 会讲它为什么是这三列里唯一判红的那一列。

---

## 4. 每一条跨域边界的清单（照这张表读代码）

这张表是本章最有价值的部分，也是改动前后都该重看的一张表。它按"从哪个域到哪个域 +
什么东西 + 靠什么办法"三件事排列，每一条都能直接翻到代码。

| # | 从 → 到 | 内容 | 办法 | 证据（`文件:行`） |
|---|---|---|---|---|
| 1 | `eth_rxc` → `clk_fpga_0` | 16 bit 写数据 + 19 bit 地址 + flush 标记 = 36 bit/拍，线速 | 格雷码异步 FIFO，BRAM，8192 深 | `src/rtl/eth/eth_udp_video_top.v:294-301`；`src/rtl/eth/dc_fifo.v:33-35`、`:56`、`:69-83`；`ram_style="block"` 在 `dc_fifo.v:20` |
| 2 | `eth_rxc` → `clk_fpga_0` | "这一帧收完了"事件 | 翻转位 + 3 级 + 异拍出沿 | `src/rtl/eth/ddr_bank_commit.v:37-47` |
| 3 | `eth_rxc` → `clk_fpga_0` | 320 bit 链路健康快照（10 lane × 32） | `snap_cross` 准静态总线 + 独立心跳 | `src/rtl/top/system_top.v:198-202`；`src/rtl/eth/snap_cross.v:37`、`:60-63`；总线由 `link_monitor.v:177-196` 拼好 |
| 4 | `clk_fpga_0` → `eth_rxc` | `gapclr_sel` 清零选择位（电平） | 3 级 `ASYNC_REG`，同步后当电平用 | `src/rtl/eth/eth_udp_video_top.v:272-276`；注释 `:270-271` 明写"准静态控制位、不是脉冲，所以不需要握手" |
| 5 | `clk_fpga_0` → `clk_pix` | 13 bit（九级效果 + 缩放档 + 手动旗标）、8 bit 阈值、32 bit gamma 字 | 各一对 2 级 `ASYNC_REG`，**同一条链同源同深度** | `src/rtl/process/effect_ctrl.v:34-39`、`:41-58`、`:70-75`；例化在 `src/rtl/top/pl_video_top.v:194-206` |
| 6 | `clk_fpga_0` → `clk_pix` | 单个使能位（`zoom_en` / `bilin_en_axi` / `src_sel` / `eth_link` / `eth_live` / `owner_eth`） | 3 级 `ASYNC_REG` | `pl_video_top.v:208-218`、`:254-262`、`:426-431`、`:446-451`、`:457-462`、`:472-477` |
| 7 | `clk_fpga_0` → `clk_pix` | 19 bit 几何控制字（缝位、自动扫描、旋转三档、拟合旗标） | axi 域每 1.31 ms 整拍抄一次并翻 toggle → `snap_cross` | `pl_video_top.v:807-825`（`17'h1FFFF` 计数在 `:813`）；位图 `:44-50` |
| 8 | `clk_pix` → `clk_fpga_0` | 消隐窗口是否安全（电平）+ vsync 事件 | 像素域 3 级采样 → 翻转位 → axi 域 3 级 | `src/rtl/video/frame_commit_lock.v:45-57`、`:59-69`、`:71-76` |
| 9 | `clk_pix` → `clk_fpga_0` | "拷贝完成"、"PS 请求上屏"、"长按"、"每帧一次" | 翻转位 + 3 级 + 异拍 | `frame_commit_lock.v:126-138`；`ps_publish.v:18-25`；`pl_video_top.v:518-528`、`:557-561`、`:231-234` |
| 10 | `clk_pix` → `clk_fpga_0` | 19 bit 像素域缩放实况（lane23 回读） | `zoom_snap` 打包 + 独立心跳 `z_hb_tog` + `snap_cross` | `pl_video_top.v:600-606`、`:609-617`（心跳为什么必须单独一个 FF）、`:622-626` |
| 11 | `clk_fpga_0` → `clk_pix` | 18 bit 换算好的时延 ms（OSD 那一格） | `snap_cross`，心跳**另起一个 FF** | `pl_video_top.v:914-932`；为什么要另起：`:916-919` |
| 12 | `clk_pix` → `sys_clk` | vsync 沿（FPS 计数）、帧首翻转（自动旋转节拍） | 3 级 + 异拍 | `pl_video_top.v:875-885`；`angle_ctrl.v:24-29`，规矩写在 `angle_ctrl.v:20-23` |
| 13 | `axi_clk` → `axi_clk`（**不跨域**） | `dbg_src` / `dbg_lat` | 全取现成的 axi 域电平，零新增跨域 | `pl_video_top.v:547-553`、`:592`；`system_top.v:219` 明写"这不是跨域信号" |
| 14 | 帧缓存 BRAM 本体 | 写口 `clk_fpga_0`、读口 `clk_pix` | **不做同步器**：靠"只在消隐窗口写"的协议 + 写窗使能位的 3 级同步 | 写在 axi 域 `pl_video_top.v:677-695`（`.wr_clk(axi_clk)`）、读在 `clk_pix`；写窗 `:345-356`、`:385-395`；采到允许位之前的像素保持不读 `:492-503` |

一个容易看漏的点：**同一个位的"请求"和"生效"分属两个域时，回读口不许把像素域那份
直接塞进 axi 域的输出口。** `dbg_zoom` 的 bit19 取的是 axi 域原始的 `split_ctl[18]`，
不是像素域副本 `zoom_fit_en`，`pl_video_top.v:631-633` 明写了这句话；账本在
`report/log/ISSUES.md:3138`（#84）——那次就是把 `bilin_en_pix` 直接接到 axi 输出口，
撞上了本文件更早记过的同一个错。

### 4.1 一条网口帧的完整旅程（RGMII 收包 → DDR → 显示）

这是本章唯一需要串起四个域的例子。数据一共换**三次**时域，每次的办法都不同：

1. **引脚 → GMII（仍在 `eth_rxc` 域内部）**：RGMII 是 4 bit DDR，`IDDR` 抽成 8 bit GMII
   （`src/rtl/eth/rgmii_rx.v:76-84`）。数据在 ILOGIC 里被 **BUFG** 采（#57 之前是 BUFIO，那样 IO 与 fabric 分走两条树，偏斜 1.616 ns ⇒ 最差 hold 每次重建掷硬币）
   （`rgmii_rx.v:40`），交给 fabric 的触发器时用的是 **BUFG** 那份同频时钟
   （`rgmii_rx.v:30` `assign gmii_rx_clk = rgmii_rxc_bufg;`）——两棵树的偏斜就是 §10 那条
   WHS 故事的根。`IDELAY` 的参考钟是另一颗 MMCM 的 200 MHz
   （`eth_udp_video_top.v:70-78`，端口 `idelay_clk` 在 `:20`；
   `REFCLK_FREQUENCY 200.0` 在 `src/rtl/eth/rgmii_rx.v:59`）。
2. **GMII 字节流 → 半字写入（仍在 `eth_rxc` 域）**：`frame_reasm` 吃 `udp_rx_parser`
   给的 `p_valid/p_sof/p_eof/p_good`（`eth_udp_video_top.v:231-241`），吐出 16 bit 写。
   这里没有跨域，但有一个真实的丢数通道：打包器满时 `sv_full` 反压 CDC 读（`:252`、`:308`），
   而 125 MHz 线速下这个反压必须靠深 FIFO 吸收——`dc_fifo` 因此做成 8192 × 36 bit 的 BRAM
   （`:291-294`）。为什么不能再限流：`:253-257` 记着实测——原来"每 3 个 axi 周期取 1 条"
   = 66 MB/s < 125 MB/s，单包就能灌满 ⇒ 稳定丢约 46% 的字，屏上是"每隔一个 16 bit 空洞"的黑纹。
3. **`eth_rxc` → `clk_fpga_0`（第一次真跨域）**：就是清单第 1 条的格雷码 FIFO。
   读侧随后串成 AXI write 突发落到 DDR（`src/rtl/eth/axi_frame_saver64.v`，
   例化在 `eth_udp_video_top.v:350-363`，时钟 `axi_clk`）。乒乓双 bank 是 `BASE_ADDR`
   与 `BASE_ADDR + 0x0008_0000`（`:67-68`），地址常量在 `system_top.v:132-140` 只出现一次。
4. **"这帧可以显示了"这件事 → 显示侧（第二次、第三次跨域）**：`ddr_bank_commit` 先把
   `frame_done` 用翻转位跨进 axi 域，再等"本帧数据已全部穿过 CDC"才提交基址与脉冲
   （`ddr_bank_commit.v:49-51`）。少等这一步的症状写在文件头 `:6-7`：
   帧尾 4 字节被写进下一帧的 bank，板上是"HDMI 右下角少 2 像素"。
   到了 axi 域之后，`eth_commit` / `eth_ddr_base` 进 `pl_video_top`（`system_top.v:294-295`），
   由 `frame_commit_lock` 再跨一次到像素域才敢动帧缓存（`pl_video_top.v:385-395`）。

**为什么要把"换三次时域"写出来而不是画一条流水线**：因为这四步里任何一步用错同步办法，
症状都不是编译错误，而是**画面局部错位、偶发丢包计数、右下角少两块**这类"看起来像硬件坏了"
的现象。上面每一条都配了一句"错的话屏上是什么样"，那就是排查表。

**你可以自己验证。** 这张表最该验的是"有没有表外的跨域"。一条命令把全仓所有
`ASYNC_REG` 链的**目的时钟**列出来，和表对照：

```bash
grep -rn -A2 "ASYNC_REG" src/rtl --include=*.v | grep "posedge" | sed 's/.*posedge \([a-z_0-9]*\).*/\1/' | sort | uniq -c
```

期望（当前树上的实测分布）：

```
      8 clk_pix       5 axi_clk       3 clk       1 dst_clk
      1 gmii_rx_clk   1 pix_clk       1 sys_clk
```

`clk` / `dst_clk` / `pix_clk` 是模块端口名形式（`effect_ctrl`、`snap_cross`、
`frame_commit_lock`），追进去就能认出真实钟。关键是**不要出现这七个名字之外的钟**——
多出来一个就说明表要加一行。（`dc_fifo.v` 的 `wr_clk`/`rd_clk` 两条链不在这张表里，
因为 grep 抓的是 `ASYNC_REG`，而它没打这个属性，见 §3 末尾。）

---

## 5. 两条写进代码头的禁令

这一节讲的两条都不在教科书目录里，它们是本仓库被真实事故逼出来的规矩，
而且都写进了代码注释。它们的共同点是：**看起来是"更小心"的写法，实际上更危险。**

### 5.1 不许把 `full` / `empty` 这类标志"寄存一下再用"

**规矩。** `report/log/OVERNIGHT_LOG.md:5668-5670` 那句是原话：
结构性修法是"把丢字脉冲打在它出生的 `dc_fifo` 里（`wr_drop_r <= wr_en & full`），
跨模块只送 1 bit；**不许**把 `full` 打一拍再用（会漏计真正的溢出拍，
而 `drop_words` 是板上唯一真实的丢数据判据）"。

**为什么要立这条。** 先看当前那份最差 setup 是什么（`build/timing_summary.rpt:365-374`）：
起点 `u_eth/u_cdc/wbin_reg[2]/C`、终点 `u_eth/u_lm/drop_words_reg[12]/CE`、
Path Group `eth_rxc`、slack −0.062 ns、8 级逻辑、route 占 67.7 %。
翻译一下：`dc_fifo` 里那个 14 位二进制写指针的**进位链**，被组合地送出了模块边界，
跨进 `link_monitor`，和 `cdc_full`、`wr_en` 拼在一起，最后成了 32 位丢字计数器的使能。
也就是说：**一条仪表的使能脚，挂在了数据通路的指针上**（`link_monitor.v:113`
`if (cdc_wr_req && cdc_full) drop_words <= drop_words + 1'b1;`）。

**"那把它打一拍不就简单了"——不行，理由有三层：**

1. **会漏事件。** 溢出是**按拍**发生的事件。`full` 晚一拍到位，那一拍的写就被吞掉而没人记账；
   更糟的是这一位一旦晚一拍，`cdc_wr_req && full_d` 这一拍可能已经不成立了。
   仪表少记一次 = 这块屏上"其实丢了数据但报告说一切正常"。
   `link_monitor.v:4` 写得很直白：**板上唯一会吃掉数据的通道就是 CDC 写口被 `fifo_full`
   挡住那一拍**，所以这个计数器的正确性是整个链路的信用基础。
2. **`full` / `empty` 本来就是组合的，而且必须保守。** 看 `dc_fifo.v:33-35`：
   `wr_full` 比的是**下一个**格雷码写指针 `wgray_n` 与同步过来的读指针，
   于是它在"还能写最后一格"的下一拍就提前拉高（宁可假满，不可假空）；
   `rd_empty`（`:56`）比的是本域 `rgray` 与已经晚了两拍的 `wgray_s1`，
   于是它在对面刚写了数据之后还多空一会儿（宁可假空，不可假满）。
   这两个"晚"是安全方向上的设计，不是缺陷。再往这两个标志后面加一级寄存，
   等于在写侧往**不安全**的方向挪：门控 `wr_en && !wr_full` 的拍和真正写进 `mem` 的拍
   不再是同一拍（`:41` 与 `:49` 用的是同一个 `wr_full`）。
3. **加了那一拍，问题也没解决。** 这条路径的瓶颈不是"逻辑级数多了 1"，
   而是 14 位指针进位链跨了两个模块（`OVERNIGHT_LOG.md:5662` 的结论：
   布局后估计一度是 +0.645，布线把它拉到 −0.062 ⇒ 是**路由拥塞**，不是逻辑深度）。
   正确的修法是把组合留在出生地：在 `dc_fifo` 里把 `wr_en & full` 打一拍（那是一拍宽
   的真实事件，寄存器输出），跨模块只走 1 bit。

**同一条禁令的另一半：不许为了时序挪仪表的读数节拍。**
`link_monitor.v:46-49` 记着一次已经回退的尝试（账本 `report/log/ISSUES.md:3820`，#95）：
把帧间隔统计拆成三级寄存器，算术与 min/max 全对，但
**`lm_bus` 快照在记账前就被采走** ⇒ 台架红两条。原话是
"仪表的读数节拍是对外契约，不许为了时序去挪它"。
那次回退还留下一条更值钱的判据（`report/log/ISSUES.md:3835-3846`）：
"统计值"与"发布出去的值"是两个时刻，判据必须先决定自己钉哪一个。

**你可以自己验证。** 不需要构建，只需要确认当前最差 setup 的两端确实跨了模块：

```bash
awk 'NR>=365 && NR<=374' build/timing_summary.rpt
grep -n "cdc_wr_req\|cdc_full" src/rtl/eth/eth_udp_video_top.v src/rtl/eth/link_monitor.v
```

期望：第一段里 `Source` 是 `u_eth/u_cdc/...`、`Destination` 是 `u_eth/u_lm/...`
—— 一条跨模块的组合路径；第二段里 `link_monitor.v:19-20` 那两个端口
（`cdc_wr_req`、`cdc_full`）就是这条路径的入口。修法落地之后，这两段输出应该变成
"终点在 `u_cdc` 内部、跨模块只走 1 bit"。

### 5.2 非整数比的时钟之间，不许拿计数器当时间

**规矩。** 跨域的正确性只能由**结构**保证，不能由"我数了 N 拍，那时候一定稳定了"保证。
需要时间门限时（心跳有没有停）也只允许在**目的域**数，并且必须留 5 倍以上的余量。

**为什么。** 三条独立的理由，本仓各有一条真实证据：

1. **相位是未知的，而且是会漂的。** 两股异步时钟的相对相位由物理决定，不由频率决定。
   `frame_commit_lock.v:100-105` 是这件事最干净的标本：`copy_abort` 是 axi 域上只有
   1 拍（10 ns）的脉冲，消费者在 50 MHz 像素域，而**两股钟同源同相**（同一颗 MMCM 的
   100/50 MHz 输出）——听起来最安全的一种情况，实际是"翻转沿正好压在采样沿上，
   收不收得到取决于建立/保持窗口里的亚稳"。那里还有一句更重要的：
   **电平型 3 级同步在这里并不能修好它**（实测与裸采逐相位一模一样）。
   凭据是台架 `sim/tb_v79_abort_toggle.v`：故意把两钟做成同相起步、逐相位错开 0..9 ns，
   判据 A1 要求 TOG（翻转式）在每个相位都恰好收到 N 次，A2 要求至少一个相位 RAW 漏看，
   A3 要求 LVL3 与 RAW 在**每一个**相位数目都一样——"换电平同步"根本不是修法，
   这是实测不是推论（`tb_v79_abort_toggle.v:2-7`）。
   仿真侧同样不许靠"等某个事件"来对齐：`sim/tb_ps_publish.v:4-5`、`:10-11` 把两钟做成
   **7 ns / 20 ns 非整数比**，再加 LFSR 伪随机相位（`:20-21`），
   目的就是"让翻转沿相对 clk 的相位在几十次迭代里扫遍整周期"——
   任何靠固定拍数蒙对的写法，在这种激励下一定会在某个相位上露出来。
2. **计数器脚下的钟可能根本不是你以为的那个频率。** `link_monitor.v:6-7`：
   板级实测断链时 RTL8211 **不停供 RXC，而是把它拉到约 2.5 MHz（慢 48 倍）** ⇒
   "这里所有'ms'其实是周期数、饱和在 0xFFFF，下游拿它做实时判断必须先与'源时钟健康'相与"。
   后果写在 `system_top.v:236-238`：单看 `stall_ms < 200` 那一位会**永远判"活着"**，
   仲裁死死占住 ETH、SD 再也接不回画面。这就是 `hb_slow` 存在的理由，也是清单第 3 条里
   `snap_cross` 要多接一根 `hb_tog` 的理由（`snap_cross.v:6-7`、`:25`、`:52`）。
   而"这个活着必须先确认量它的时钟还算准才可以用"这条判据**为什么落在
   `src_arb` 模块里**，`src/rtl/util/src_arb.v:11-14` 给了答案：
   "原来在 `system_top` 里是一个裸与门，没有任何台架能验到它"——
   这和本章已经见过三次的同一课一致：抽成模块不是为了整洁，是为了**有台架**
   （另两处：`src_mode`（`pl_video_top.v:149-151`）、`ddr_bank_commit`
   （`ddr_bank_commit.v:4-5`））。
3. **同一个域里的两个计数器也会锁相。** `report/OPTIMIZATION_LOG.md` §4 第 (a) 条
   给的警告是：`frame_done` 与 `ms_tick` 共享同一时钟根，30 fps 源的帧周期 ≈ 33 个 ms 刻度，
   "与 1 ms 分频**可能锁相**，不是'十万分之一'的巧合可以糊过去的量"。
   所以连"每 N 拍做一次"这种同域节流也要按最坏对齐来设计：`link_monitor.v:156-157` 那句
   `SETTLE=32 ⇒ 256 ns，覆盖到 31 MHz 以下的目的时钟` 就是在给节流窗口算**下界**，
   而不是随手挑一个 2 的幂。

**结论性的做法（本仓统一口径）：**

- 传事件用翻转位，不用脉冲：`ddr_bank_commit.v:37-47`、`ps_publish.v:17-25`、
  `angle_ctrl.v:20-23`、`pl_video_top.v:555-561`；
- 传总线用"整拍写 + toggle + 目的域边沿捕获"：`snap_cross.v:60-63`、`zoom_snap.v:5-7`；
- 需要**时间**这件事的时候，只在目的域数，并且把门限按参数算出来、留够余量：
  `snap_cross.v:23-25`（`FAST_ENOUGH` 把 1 ms 与 ~50 ms 分居两侧，余量 5×/10×）、
  `pl_video_top.v:910-911`（时延心跳门限取 1000 ms，正常一轮 16~33 ms，留 30 倍）；
- 不许把 2 位码各自打 3 拍再拼回一个数：`src_mode.v:14` 是禁令原文；
  码必须走一条**与翻转位等长**的延迟线，在沿到链尾那一刻取延迟线尾部那一份
  （`src_mode.v:28-33`、`:61`、`:74`——"取的是**沿出发那一刻**已经站住的码，不是现在的码"）。
  固件侧对称地保证顺序：`src/ps/main.c:482-491` 的 `ctrl_publish_mode()` 刻意分两笔写，
  第一笔只更新码、第二笔只翻位，注释里写清了"一次写同时改码和翻位，对面读到的可能是
  新码 + 还没认的沿"。

**你可以自己验证。** 禁令 5.2 有一份专门的相位扫描台架，它也是本仓少数"能证明错写法会红"
的判据之一：

```bash
bash sim/run_one.sh tb_v79_abort_toggle
bash sim/run_one.sh tb_ps_publish
```

期望：两份输出都以 `RESULT <tb 名> PASS` 结尾，并且 `tb_v79_abort_toggle` 里
**A2 是"RAW 确实漏看了"**（如果 A2 说 RAW 一次没漏，那这条激励已经失效，PASS 不算数）；
`tb_v79_abort_toggle.v:7` 那句 A3 也要能看到。跑之前注意 `sim/run_one.sh:15-22`
那条守卫：同时只允许一个 xsim 在跑，有活的就拒绝启动并告诉你该杀谁。

---

## 6. 报告怎么读：`report_cdc` 的三列、`cdc_who.tcl`、以及 WNS 归因

### 6.1 `build/cdc.rpt`：端点数与 unsafe 是两回事

**是什么。** `report_cdc` 出的是一张**按"时钟对"聚合**的表。当前这份
（`build/cdc.rpt:4` 写着 Date 2026-09-28 03:03，Design State: Routed 在 `:10`）
表头在 `:15`：

```
Severity  Source Clock  Destination Clock  CDC Type  Exceptions  Endpoints  Safe  Unsafe  Unknown  No ASYNC_REG
```

八行内容（`:17-24`）：两条 Critical、四条 Warning、两条 Info。
其中值得逐条认的：

| 行 | 配对 | 端点 | Safe | Unsafe | 读法 |
|---|---|---|---|---|---|
| `:17` | `clk_fpga_0 → clkout0_1` Critical | 99 | 98 | **1** | 全部控制字/快照都走这一对。基线里它是 17，现在 99 = 端点数增长 |
| `:18` | `sys_clk → eth_rxc` Critical | 1892 | 1365 | **2** | Unknown 525：这一对里没有共同主时钟，工具认不出结构 |
| `:19` | `clkout0_1 → clk_fpga_0` Warning | 27 | 27 | 0 | 反向那条；**是 Warning 不是 Critical** |
| `:20-21` | `eth_rxc ↔ clk_fpga_0` Warning | 271 / 15 | — | 0 | No ASYNC_REG 各 14（`dc_fifo` 指针链 + `snap_cross` 的 `bus_q`） |
| `:23-24` | `sys_clk ↔ clkout0_1` Info | 191 / 22 | 全 Safe | 0 | CDC Type 是 **Safely Timed**：同 MMCM 生成钟，工具做了真 setup 分析 |

**为什么要分清"端点数"与"unsafe"。** Critical **不等于错**：它表示"这里发生了异步跨域，
工具无法自动判定安全性"，需要人去确认。`Unsafe` 才是唯一真正要盯的数——它是
"这条跨域上又多了一处没被 `ASYNC_REG` / 握手保护住的采样点"。所以门禁的判据长成这样
（`build/gates.sh:86-131`）：

- **新增配对 → 判红**（`gates.sh:124`）；
- **同一配对的 unsafe 变多 → 判红**（`gates.sh:131`，标着"#65"）；
- **同一配对的端点数变多 → 只提示**（`gates.sh:129`），因为加一级仲裁寄存就会 +1，
  判红只会逼人绕开门禁；
- **基线里有而本版没有 → 提示"原因未查证，不算改进"**（`gates.sh:126`）。

第三条与第四条合起来就是"不许把数字变好看当收益"。拿当前这份和基线
`build/CDC_BASELINE.txt:20-23`（四行：`eth_rxc>clk_fpga_0 272 1`、
`clk_fpga_0>clkout0_1 17 1`、`eth_rxc>clkout0_1 51 1`、`sys_clk>eth_rxc 1909 2`）比，
今天这一版会打印两行提示：`clk_fpga_0>clkout0_1` 端点 17→99，
以及 `eth_rxc>clk_fpga_0`、`eth_rxc>clkout0_1` 两条"基线里有而本版没有"——
两条都不判红，两条都不算改进。

**第三列为什么是后来才加的。** 基线文件头 `build/CDC_BASELINE.txt:4-7` 写了原因：
unsafe 列是 2026-09-25 r56 才补上的（ISSUES #65）。在那之前判据只比"配对集合 + 端点数提示"，
于是 V8-5 那条时延快照把 `bus_tog` 与 `hb_tog` 接在**同一根发射触发器**上
（CDC-11），`clk_fpga_0→clkout0_1` 的 unsafe 从 1 长到 3，而门禁**一声不响**——
因为它落在已有配对上就看不见。事故全文在 `report/log/ISSUES.md:1585-1634`，
里面那条 `-details` 摘出来的原文值得记住：

```
u_pl/u_lat/lat_tog_reg/C → u_pl/u_lat_x/hs_reg[0]/D
u_pl/u_lat/lat_tog_reg/C → u_pl/u_lat_x/ts_reg[0]/D
```

同一个工程里这个签名红过三次：r55（#65）、r54 构建 #34、以及缩放心跳那一处
（`pl_video_top.v:609-617` 与 `:916-919` 两处注释都记着"一个 FF 换回配对集合不新增"）。

### 6.2 `build/tcl/cdc_who.tcl` 是干什么的

**它回答一个汇总表答不了的问题：是哪几个寄存器让那一行变 Critical 的。**
脚本头 `build/tcl/cdc_who.tcl:1-9` 就是这么写的：汇总表只给"源钟→目的钟 + 端点数"，
改完 RTL 只知道行数变了、不知道是谁；#27 的门禁在 `clkout0_1 → clk_fpga_0`
这一行报红（5 端点 / 2 unsafe），必须先回答"那 2 个 unsafe 是谁"再谈修。
做法是打开已布线的 dcp 出 `report_cdc -details`，落到 `build/cdc_details.rpt`
（`:25`、`:27-29`）。

它自己也是一个"别踩"的教学样本：`:11-13`、`:14-22` 那段解释为什么不能把 dcp 文件名写死
——`-to_step write_bitstream` 产出的叫 `system_top_routed.dcp`，策略/版本不同会变成
`*impl_1_routed.dcp`，而 `create_project -force` 会删掉整个 runs 目录重建；
在构建进行到这 20 分钟之外去跑它，就会撞 `NO_DCP`（`:23` 那句报错文案就是这个）。

**这条路径上最值钱的一次点名**（`report/log/ISSUES.md:661-687`）：`cdc_who` 查出
`u_pl/FSM_onehot_mode_reg[2]/C → u_pl/ms0_reg[0..1]/D`，规则号 **CDC-10
"同步器之前有组合逻辑"**。根因不是有人插了组合逻辑，而是**综合把四状态 `mode` 重编码成
one-hot**，于是"打两拍"在网表里变成"3 个 one-hot 触发器经组合译码进 2 个目的触发器"——
格雷码的意义（逐位直连）在实现层被抹掉了。修法两步：`(* fsm_encoding = "none" *)`
禁止重编码，再把下一状态写成**按位**的 `mode <= {mode[0], ~mode[1]}`
——今天这条就活在 `src/rtl/util/src_mode.v:20-24` 与 `:86`，注释写的正是这个理由。
剩下的那条 `CDC-6 Warning「Multi-bit synchronized with ASYNC_REG property」`
**不再往下压**，因为工具看见"两位总线进一组同步器"就报 CDC-6，
它没有办法知道这两位是格雷码（`report/log/ISSUES.md:680-684`）：
"判定能力到此为止的性质，就交给台架去证明"（`sim/tb_v82_src_mode.v` 的 T3）。

### 6.3 WNS 归因为什么不能只看那一个数字

**是什么。** 门禁念的 WNS 是 `timing_summary.rpt` 里 Design Timing Summary 的第一行数据
（`:149` 是表头、`:151` 是数据、`gates.sh:58-61` 用 awk 抓的就是这一行），
而它是**所有约束组的最小值**。

**为什么不能只抄那一个数。** `report/OPTIMIZATION_LOG.md` §4（`:224` 起）用三份报告
（r63b / r63c / r64b，同一套约束）摊开了这件事：那一个数由两条**互不相干**的路径轮流决定——
一条在 125 MHz 的 ETH 收包域（`u_cdc/wbin → BRAM ENARDEN`、`u_lm/ms32 → gap_min`），
一条在 50 MHz 的像素域（`u_pipe/xd_reg → u_osd/g_reg`，27 级）。
三次构建的门禁 WNS 是 0.918 / 0.807 / 0.314，因为每次"谁小谁是裁判"。
所以"这次 WNS 掉了 0.5 ns"这句话单独讲没有任何指向，**必须先问掉的是哪一组**。
这一项因此进了门禁但**只记录、绝不判红**（`build/gates.sh:225-246`，
它会把每个 From==To 组的 setup/hold 列出来，并标出"门禁 WNS 就是这一组"，
读不到分组行时明说"这一项未验"，不许把空表当通过）。

**"掷硬币"这个说法要精确化。** 本仓在这句话上交过两次账，两次都写了自我更正：

- `report/OPTIMIZATION_LOG.md` §8（`:312` 起）：§4 里那句"ETH 域一行 RTL 没动、
  eth 组却从 0.912 掉到 0.314 ⇒ 这是掷硬币"被自己否掉了——r65 那次
  同一份 RTL/约束只差一个流程开关的最小配对显示**实现结果不自己动**，
  0.912→0.314 是"加了东西之后全局摆放变了"的**确定性后果**。
  口径收在："只说这套设计 + 这个流程 + `-jobs 4` + 同一台机器可复现"，不外推到
  "Vivado 永远确定"。
- r81 那一轮又钉了一次（`report/log/OVERNIGHT_LOG.md:5664-5666`）：
  §82 里写过"−0.062 更像在零附近掷骰子，正式构建等于免费再滚一次"，
  第四滚就是那次免费再滚，它落在**与前两滚逐位相同**的地方
  ⇒ **同一策略 + 同一网表 = 确定性落点，"再滚一次"从来不是一条路**。

所以正确的一句话是：**跨策略、跨"动了别的东西"的两次构建之间那个差值不能当时序结论；
同一策略 + 同一网表之间不存在运气。** 结论要成立需要多轮/多策略对照
（`report/OPTIMIZATION_LOG.md` §4 第 4 条"不结论，守住口径"）。

**还有一条会咬人的比较规矩。** 改过最差路径的**归属**之后，不同版的 WHS 不是同一把尺子
量出来的，禁止直接比大小。真实的一次是 `set_clock_uncertainty -hold` 从 0.5 加严到 0.8
之后 WHS 仍是 +0.051，但新的最差 hold 终点已经被同一轮改动换掉了
（`report/log/ISSUES.md:2560` 那一族）。

**你可以自己验证。** 三件事一条命令就够，而且**不许凭记忆 grep 一份单文件**
（`report/log/ISSUES.md:672-675` 就记着这次踩坑：几分钟前刚跑完门禁、又去 awk 一次
`cdc.rpt`，那还是旧文件，于是得出错误结论并差点据此改设计）：

```bash
head -6 build/cdc.rpt | grep Date ; bash build/gates.sh 2>&1 | tail -30
```

期望：第一句告诉你手上这份 `cdc.rpt` 是哪一次实现写的（当前是 2026-09-28 03:03）；
第二句跑的是纯报告读取（`gates.sh:20` 明写"数字全部来自 Vivado 报告本身，不重新跑构建"），
它会打印 WNS/WHS/失败端点、资源、CDC 三行提示，以及分组最差那一块
（`gates.sh:232-246`）。当前这份**门禁不会全绿**：WNS 是 −0.062、失败 setup 端点 28，
见 §10。

---

## 7. HDMI 输出：面板时序、相位关系、TMDS 编码与串行化

### 7.1 面板时序参数在哪定义

**是什么。** 1024×600@59.5 Hz（= 50 MHz ÷ 1344 ÷ 625），像素钟 50 MHz（规格 50.25 MHz，±0.5 % 可用）。
参数只有一份，在 `src/rtl/video/video_timing_1024x600.v:2-4` 的文件头与 `:17-22` 的实参里：

| 方向 | 有效 | 前肩 | 同步 | 后肩 | 合计 |
|---|---|---|---|---|---|
| 行（H） | 1024 | 44 | 88 | 188 | **1344** |
| 场（V） | 600 | 3 | 6 | 16 | **625** |

极性：HS 正、VS 负（`:21` 的 `H_POL(1'b1)`、`V_POL(1'b0)`；文件头 `:5`）。
帧率算出来是 50 MHz / (1344 × 625) = 50 000 000 / 840 000 ≈ **59.52 Hz**
（面板规格那一栏写 50.25 MHz，对应 59.82 Hz；`video_timing_1024x600.v:2`
那句 "spec 50.25MHz, 0.5% ok" 说的就是这个容差）。
这个模块只是 `video_timing.v` 的参数化封装（`:17-26`），真正数数的是后者：
`H_TOTAL/V_TOTAL` 由参数相加（`video_timing.v:26-27`），
行场计数器 `:32-47`，窗口译码 `:49-51`。

**为什么消隐期是设计的主角而不是边角。** 整个"不撕裂"设计就是把整帧搬运塞进竖向那 25 行里。
`pl_video_top.v:347-356` 那段注释把算术写全了：625 − 600 = 25 行消隐
= 33.5 k 像素拍 = 67 k 个 axi(100 MHz) 拍，而一帧是 38.4 k 个 64 bit 字 ⇒ 搬运一定
在第一条有效行画出来之前结束。那个 67200 就是 `VBLANK_AXI_CYC` 常量（`:401`），
超出它说明换帧跨了两个消隐期，屏上同一帧新旧两半并存、运动物体被一条水平缝切开——
`copy_overrun` 粘滞位因此把 `led[0]` 从 1.5 Hz 心跳换成 6 Hz 快闪（`:402-407`、`:982-983`）。
`VB_X_GUARD = 1279`（`:354`）是同一笔算术的收尾：早关 64 个消隐像点，
因为 `allow_copy_axi` 过 `frame_commit_lock` 的 CDC 要晚约 5 个像素拍。

### 7.2 `de/hs/vs` 与像素钟的相位关系，以及"输出为什么要打一拍"

**实现。** `video_timing.v:62-69` 是关键：`h_cnt/v_cnt` 是寄存器，
`hs_act/vs_act/de_act`（`:49-51`）是**组合译码**出来的窗口比较，
而端口上的 `x/y/hs/vs/de` 是**再打一拍**的寄存器输出。
为什么要这一拍，两个理由，都不是"风格"：

1. **组合译码必然出毛刺。** `de_act = (h_cnt < H_ACTIVE) && (v_cnt < V_ACTIVE)` 是两条
   比较器的与，`h_cnt` 从 1023 跳到 1024 那一拍，比较器的各位决断时刻不同，
   组合输出中间会出现几 ns 的尖峰。而 `OSERDESE2` 的并行输入在 CLKDIV 沿**装载**
   （`src/rtl/hdmi/tmds_serializer.v:32`）——装载沿采到毛刺，线下就少一个/多一个符号。
   打一拍之后，端口值在整个像素周期里都是恒定的，装载沿落在这段稳定期的中点。
2. **像素数据与同步位必须同源同拍。** 一路走到底看：
   `split_display.v:61-63` 把 `de/hs/vs` 与像素一起寄存，
   `osd_overlay.v:493-497` 再一起寄存一次（注释 `:495`："格子与背景像素一起晚了一拍
   ⇒ 这里跟着晚一拍"），`tmds_encoder.v:42-75` 第三拍寄存 10 bit 符号，
   然后才进串行器。三个通道 + 时钟通道在串行器里同沿装载，所以**线上不存在
   "时钟已经到下一像素、数据线还在上一像素"这种错开**。

`de` 与 `x/y` 因此是同一个像素的两个视图，而 `vs/hs` 是"这个像素所在的那行/那场"的
同步位。TMDS 的消隐期控制符号就靠这两个位选出来（下一小节）。

### 7.3 TMDS 编码：为什么是 8b/10b，两段怎么算

**为什么要它。** 两个约束同时压着：线上不能有直流偏置（AC 耦合的接收端靠电容恢复电平），
且跳变不能太多也不能太少（太多则带宽/EMI 爆，太少则接收端锁不住时钟）。
TMDS 的答案是"先做最小跳变编码，再做游程平衡"，代价是每个字节多 2 bit。

**第一段：最小跳变**（`src/rtl/hdmi/tmds_encoder.v:13-36`）。
数 1 的个数 `n1`（`:20`），据此决定走 XOR 还是 XNOR 链：
`use_xnor = (n1 > 4) || (n1 == 4 && din[0] == 1'b0)`（`:21`）。
两条链都是"上一位与当前输入位"的累计运算（`:29`、`:33`），区别只在输出的是**跳变**还是
**不变**：XOR 链里 `q_m[i] != q_m[i-1]` 恰好等价于 `din[i] == 1`，所以低 8 位输出里的
跳变次数 = `din[7:1]` 里 1 的个数；XNOR 链正好取反，跳变次数 = 7 减去那个数。
于是"1 多就换 XNOR"的意义是**两者取小，跳变次数被压到不超过 3**
（我按 `:25-36` 逐字节枚举 256 个输入验过，最大值确实是 3）。
第 9 位 `q_m[8]` 记录这一拍用了哪条链（`:30`、`:34`），接收端靠它把累计运算还原回原字节。

**第二段：游程平衡**（`:38-74`）。维护一个有符号计数器 `cnt`（`:38`，6 位二进制补码）
代表"线上到目前为止 1 比 0 多还是少"。三个分支：`cnt == 0` 或这一拍两侧一样多时直接发
（`:55-62`）；`cnt` 的符号和这一拍的偏向同向时**按位取反再发**（`:63-67`）；
否则原样发（`:68-72`）。两种"补"的情况下第 10 位 `dout[9]` 都是这次补的符号位
（`:64`、`:69`）。**不要把它读成"每个 10 bit 符号恰好 5 或 6 个 1"**——
单个符号可以偏到全 0 或全 1；它保证的是**长期**平衡，即 `cnt` 不发散。
（这一条我按 `:54-73` 写了个模型跑随机字节验过，`|cnt|` 最大到 8，
所以 `:38` 那个 6 位有符号寄存器的位宽是够的——但那是我临时跑的，
**不是仓库里的判据**，也没有台架凭据；要当回归判据就得先写成 `sim/tb_*.v` 并过
`build/run_sim.tcl`。）

**消隐期发的是四个固定控制符号**（`de = 0` 时，`:46-53`），同时 `cnt` 清零（`:47`）；
而 `c1/c0` 就是 VS/HS：**只有 channel0 携带同步，channel1/2 的 `c0/c1` 恒 0**
（`src/rtl/hdmi/rgb2dvi.v:21-32`，绿、红两路那两个口接的是 `1'b0`）。
这就是为什么显示器只插一根线也能拿到时序。`:44` 那个复位值
`10'b1101010100` 正是这张表里 `2'b00` 那一项，即"没有同步"的默认符号。

### 7.4 串行化：为什么 5× 不是性能指标而是算术结果

**实现。** 四个编码器 + 四个串行器都在 `src/rtl/hdmi/rgb2dvi.v:21-51`，
通道分配是 DVI 习惯：ch0 = 蓝 + HS/VS、ch1 = 绿、ch2 = 红（注释 `:20`）。
时钟通道不编码，喂一个常量 `10'b1111100000` 给**同一个**串行器（`:47-51`）——
它在 5×/DDR 下打出来就是"每 10 拍 5 个 1"的方波，线下正好是像素时钟。

- 用 **`OSERDESE2` 主从级联**做 10:1：`DATA_WIDTH=10` 时硬件只给 8 个数据脚，
  所以 `DATA_RATE_OQ` **必须**是 `DDR`（`src/rtl/hdmi/tmds_serializer.v:2-3`、`:16`）。
  主片吃 `D1..D8 = din[0..7]`（`:33-40`），从片只吃 `D3/D4 = din[8]/din[9]`（`:73-74`），
  两片之间用 `SHIFTOUT1/2 → SHIFTIN1/2` 串起来（`:43-44`、`:64-65`）。
- 两处时钟脚就是相位关系的落点：`CLK(clk_pix5x)`、`CLKDIV(clk_pix)`（`:31-32`、`:69-70`）。
  5 个高速周期 × 每周期 DDR 出 2 bit = 10 bit，正好一个像素周期一位不漏。
  所以 250 MHz 不是"越快越好"，而是 **10 × 50 MHz ÷ 2 = 250 MHz** 的算术结果
  （分频值 `src/rtl/clocks/clk_gen.v:24`）。
- 复位是原语自己的高有效 `RST`，取 `~rst_n`（`:42`、`:80`）。这一路追上去是 `rst_pix_n`
  （`pl_video_top.v:970-976` → `rgb2dvi.v:6`）——串行器不在锁定后复位，
  线上出来的第一个符号就是错的，这是 §2 里那条 `locked` 与门的物理理由之一。
- 差分输出用 `OBUFDS`（`:91`），IO 标准 `TMDS_33`
  （`src/constraints/rk_zynq7020.xdc:12-19`，八只脚：时钟 1 对 + 数据 3 对）。

**怎么验证。** 诚实的答案：**比特级没有仿真凭据。**
本机 xsim 没有 UNISIM 库，`MMCME2_BASE / BUFG / OBUFDS / OSERDESE2` 全部是仓库自带的
占位模型（`sim/prim/unisims_sim.v:9`、`:13`、`:18`），而那个文件头写明了不许拿它们当真相：
"允许用它们的前提是'判据读的是并行像素，不读 DVI 引脚上的比特'……
谁哪天要判 DVI 串行输出的正确性，必须换真模型，不许把判据挪到这几个占位件的输出上——
**那会造出一条永远不可能红的判据**"（`sim/prim/unisims_sim.v:5-7`，
`OSERDESE2` 那一句的重复在 `:42`、`:52`）。所以能验的只有编码器的**并行侧**与**时钟比例**。

**你可以自己验证。** 两条，一条量时钟树、一条量"占位件不建模"这件事本身：

```bash
bash sim/run_one.sh tb_v99_unisim_sim
grep -n "不建模\|不串行化\|不许读 DVI" sim/prim/unisims_sim.v
```

期望：第一条的判据全部围绕**比例**而不是绝对值——C1a 要求 5× 边沿数正好是 pix 的 5 倍、
C1b 要求 200m 是 4 倍（`sim/tb_v99_unisim_sim.v:67-70`），理由写在 `:65-66`：
"谁把 `CLKOUT1_DIVIDE` 从 4 改成 5，模型会正确地跟着变 200 MHz，而 TMDS 串行器要的 5×
就没了 ⇒ C1 红"（只判"pix = 50 MHz"则照样绿）；C4 先判"量到了没有"，窗口不够就报
"量不出"而不许判 C1/C3（`:58-64`，防"空跑判据"）；C2 判 `locked`（`:76`）、
C3 判绝对周期 20/4/5 ns（`:72-73`）。最后要有 `RESULT tb_v99_unisim_sim PASS`。
第二条应命中三行，正是上面引的那几句——**这条限制不是偷懒，是本仓库区分
"机器判据"与"眼睛判据"的口径**；线下波形的最终凭据是显示器加眼睛，
那几条还没签的账记在 `board/README.md` 那张表的尾部。

---

## 8. 约束文件逐条，以及异步时钟组为什么要单独一个文件

**是什么。** 手写约束只有两个文件，而且它们**在被读的阶段上不一样**：

| 文件 | 内容 | 生效阶段 | 绑定处 |
|---|---|---|---|
| `src/constraints/rk_zynq7020.xdc`（77 行） | 配置电平、52 只脚的引脚与 IO 标准、2 条 `create_clock`、4 条 `set_false_path`、1 条 `set_clock_uncertainty`、比特流压缩 | 综合 + 实现 | `build/tcl/build_system_axigpio.tcl:19` |
| `src/constraints/clock_groups_impl.xdc`（31 行） | 一条 `set_clock_groups -asynchronous` | **只在实现** | 同一脚本 `:24-26`：`set_property used_in_synthesis false` + `used_in_implementation true` |

### 8.1 为什么异步时钟组必须拆成单独一个文件

这是本章最"工具学"的一件事，值得完整推一遍。

**约束要说的三组钟**：`eth_rxc`（125 MHz）、`clk_fpga_0`（100 MHz）、
`sys_clk` 及其全部生成钟（50/250/200 MHz）。前两组我们的 XDC 自己 `create_clock` 得到，
**第三组 `clk_fpga_0` 不是我们造的**——它由 PS7 IP 自己的 XDC 用 `get_pins` 创建
（§1 引的那行：`design_1_processing_system7_0_0.xdc:20`）。

**问题**：综合阶段还没有已布线设计，那条 `create_clock` 尚未生效，
于是 `get_clocks clk_fpga_0` 在综合时取到空集。而 XDC 的求值语义是**整条命令**失败：
`-quiet` 只能压住 `get_clocks` 自己的报错，压不住命令本身。后果不是"少约束一组"，
而是**整条 `set_clock_groups` 不生效**，连带把 `eth_rxc`、`sys_clk` 两组一起废掉，
现场只留下一句 `CRITICAL WARNING [Vivado 12-4739]`。
这段话在仓库里写了两遍：`rk_zynq7020.xdc:65-73` 与 `clock_groups_impl.xdc:3-8`。

**为什么不能就地判断**：XDC 文件里**不允许写控制流**——`if` 会报
`[Designutils 20-1307] Command 'if' is not supported in the xdc constraint file`
（`rk_zynq7020.xdc:71-72` 记的正是这条）。所以"按时机分文件"是唯一正规解：
把这条约束放进只在 implementation 生效的那份。

**会不会改变时序数字**：不会。`rk_zynq7020.xdc:74` 与 `clock_groups_impl.xdc:8`
各自都写了这句话，理由是同一个事实——综合阶段这条命令本来就是失败的，
等于不存在，拆分只是把"失败"变成"不参与"。

### 8.2 四类约束，各举一个真实例子

1. **时钟约束**：`create_clock -period 20.000 -name sys_clk [get_ports sys_clk]`
   （`rk_zynq7020.xdc:6`）、`create_clock -period 8.000 -name eth_rxc [get_ports eth_rxc]`
   （`:36`）。全仓**只有这两条**，0 条 `create_generated_clock`：MMCM 输出的
   50/250/200 MHz 全部由工具从 `CLKIN1_PERIOD` + 分频参数自动推导
   （这也解释了为什么 §1 那张表里它们缩进显示）。
2. **异步组里那个必须带后缀的**：`clock_groups_impl.xdc:31` 的
   `-include_generated_clocks`。少了这个后缀，`clk_pix` 会被当成独立时钟去和
   `eth_rxc` 做 setup 分析，历史上是 `WNS ≈ −6.7` 的**假违例**（`:13-17`；
   账本条目 `report/log/ISSUES.md:143-145`，编号 #18，标题就是"eth_rxc→clk_pix 假违例"）。
3. **反方向的例子（要认得）**：`clk_pix` 与 `clk_pix5x` **有意留在同一组内**，
   让 TMDS 并串转换按同步路径做 setup 分析——"声明成异步反而会漏检"
   （`clock_groups_impl.xdc:25-26`）。这不是漏写，是主动选择不豁免。
   §1 结尾那三条凭据（`cdc.rpt` 里没这一对、`timing_summary.rpt:942-944` 的
   Setup/Hold 是 NA、`clock_util.rpt:220` 的 Slice Loads = 0）就是这句话的机器证据。
4. **false path**：按键 `set_false_path -from [get_ports key1_n]`（`:59-60`）。
   为什么合法：按键在 `sys_clk` 域里被**两级同步 + 20 ms 消抖**
   （`src/rtl/util/key_debounce.v:13`、`:25-26` 是那两个同步位，`:4` 的
   `CNT_MAX(1_000_000)` 在 50 MHz 下就是 20 ms；例化在 `pl_video_top.v:132-137`），
   毫秒级机械抖动对 20 ns 的建立保持完全不敏感，
   算它没意义。同类还有 `:55-58` 那四条 `-to`（`eth_rst_n`、`eth_tx_clk`、
   `eth_tx_ctl`、`eth_txd[*]`）——方向词必须对上真实方向，`eth_rst_n` 是输出
   （`system_top.v:41`）所以只能 `-to`，这条规矩的来历见 §2 那条 18-513。
   **副作用要说清**：这四条一挂，RGMII 发送侧的接口时序就完全不被检查了，
   它的正确性只剩板级证据（ping 通、ARP 应答对）。
5. **一条方向相反的量**：`set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]`
   （`:50`）。这一行的注释值得读完整（`:37-49`）：它给 hold **加** 0.5→0.8 ns 要求，
   逼工具把余量做成设计值（因为数据路径还有约 6 ns 的 setup 余量"垫得起"，
   而 `-hold` 的不确定性不参与 setup 检查）。它还写了**退回条件**（`:48-49`：
   若这一版关不住时序就带着两个数字退回 0.500，并把"工具在这个布局下垫不到 0.4"
   记成 #46 的实测结论，而不是悄悄把验收改掉）与**验收口径**（`:46`：WHS 应升到 ≥ 0.4）。
   `:43-45` 还有一条重要的"只写一个对象"：把 `get_clocks` 取不到的名字并进同一条命令，
   会让整条命令空转——这就是 8.1 那个坑的通用形式。

关于 `set_max_delay`：**本仓库的 XDC 里没有一条 `set_max_delay`**
（全库 `*.xdc` 搜 `set_max_delay` / `set_min_delay` / `set_multicycle_path` 零命中）。
承担"放松判据"这一角色的是 `set_false_path` 和上面那条**收紧**判据的 `set_clock_uncertainty`。
**放松或收紧判据，永远要说清代价与退回条件**，这是本仓库写约束的口径。

**你可以自己验证。** 三条静态检查，都不需要构建：

```bash
grep -n "create_clock\|create_generated_clock" src/constraints/*.xdc
grep -rn "set_max_delay\|set_min_delay\|set_multicycle_path" src/constraints/ ; echo "（上一条应无输出）"
grep -n "used_in_synthesis\|used_in_implementation" build/tcl/build_system_axigpio.tcl
```

期望：第一条恰好 2 行命中、且都在 `rk_zynq7020.xdc`（`:6`、`:36`），
`create_generated_clock` 0 命中；第二条无输出（确认"没有 max_delay 这类放松"这件事）；
第三条命中 `:25`、`:26` 两行。第三件事还可以反向确认：实现日志里**不该**再有
`CRITICAL WARNING [Vivado 12-4739]`——把它当判据的话，凭据文件是
`vivado_system/zynq_video_sys.runs/impl_1/runme.log`。

---

## 9. PS↔PL 边界：三条 32 bit 信箱与时域关系

**是什么。** PS 侧只有一件事：`Xil_Out32` 写 32 bit、`Xil_In32` 读 32 bit。
PL 侧只有一件事：那 32 bit 是 `clk_fpga_0` 域里的寄存器输出，谁要用就去同步。
所以这一节的重点不是位表（位表正本在 `src/ps/main.c:4-14` 与
`src/rtl/top/pl_video_top.v:25-53` 的端口注释里，两边互为镜像），
而是**为什么 PS 写下去的值可以安全地被像素域读**。

**为什么 AXI GPIO 不需要额外的跨域协议。** `axi_gpio` 的 `gpio2_o` 寄存器就在
`clk_fpga_0` 域里（AXI-Lite 从设备跟着 FCLK 跑），它到像素域是**一次普通的
`clk_fpga_0 → clk_pix` 跨域**，于是 §3 那张表直接适用：
单 bit 走 3 级、多位走 `effect_ctrl` 那条同源同深度的链、宽字走 `snap_cross`。
PS 的"写"这件事本身慢到不用担心（一次 AXI 写几十 ns，而人是毫秒级在按命令）。

**三个基址是被钉死的，不是让它自动排的。**
`build/tcl/build_system_axigpio.tcl:184-192` 用 `assign_bd_address -offset` 把
`axi_gpio_0/1/2` 钉在 `0x4120_0000` / `0x4121_0000` / `0x4122_0000`，
然后 `:202-215` **回读校验**、失败就 `exit 1`（`:218`）。
为什么不能"让它自动排"，脚本 `:184-186` 写得直白：手工链接的 BSP 不会重新生成
`xparameters.h`，固件里的基址是硬编码的，**地址一挪，现象不是编译失败而是"写了没反应"**。
校验必须是**数值**比对而不是字符串比对，因为那个属性经数字一走会显示成十进制
（`:211-214`）。固件侧同一件事再讲一遍：`src/ps/main.c:65-69`，
并且补了一条"这一条把 elf 与 bit 绑死了：旧位流上没有这个从设备"。

**读回是一条通道，所以做成信箱。** 320 bit 的链路健康 + 19 bit 缩放实况 + 6 个时延字
+ 仲裁状态全挤在一条 32 bit 的 `GPIO_1` 上，于是 PS 先把 lane 号写进
`gpio_o[31:27]`（`system_top.v:203`），PL 用组合 mux 从**已经同步到 `fclk0` 的快照**里
挑一条送出去（`:221-230`，`assign gpio1_i = lm_rd;` 在 `:231`）。三条值得学的细节：

- **越界的 lane 返回 `0xDEAD_BEEF`**（`:228`）：故意让脚本一眼看出自己写错了号，
  而不是安静地返回 0。
- **lane31 是 `{30'd0, hb_slow, hb_gone}`**（`:222`，注释 `:193-195`）：
  这两位来自 §3 那个 `snap_cross` 的时钟健康检测。为什么必须有"慢"这一位，
  §5.2 已经给了板级实测（RXC 被拉到约 2.5 MHz 而不是停掉）。
- **读要成组抄**：lane25 同时是这一组五个字的武装位（`lat_arm`，`:220`），
  因为恒等式 `tot ≥ c1 + c2` 在逐 lane 各读各的时会读到不同轮次
  （`:216-218` 与 `pl_video_top.v:586-592` 记着板级 11 组读数里 4 组破坏恒等式那次）。

**"这不是跨域信号"也要写下来。** `system_top.v:219` 那句
"域：`gpio_o` 由 axi 写更新，`frame_latency` 也在 axi 域 ⇒ **这不是跨域信号**"
是本仓的一个重要习惯：把**没有**跨域这件事也记进注释。因为下一个读者会问
"这里要不要打两拍"，没有答案时他就会顺手加一对同步器，而加一对 `snap_cross`
就多一条配对行、基线要重画（`effect_ctrl.v:62` 讲的正是这笔税）。
同类记录还有 §4 清单第 13 行与 `pl_video_top.v:550-551`（"要看模式就取现成的 `ms2`"）。

**你可以自己验证。** 板子在手上时一条命令就够：

```bash
node src/host/health_read.mjs
```

期望：它默认按 `--gpio0 41200000 --gpio1 41210000` 读（`src/host/health_read.mjs:34-35`，
用法行 `:13`），把 10 条 lane 读两遍——**单调计数器第二遍变小就是采到了快照刷新那一拍**
（`:18-20`）；lane30/lane23 各有一份独立译码器与逐位独热走查（`:67`、`:86`）。
板子不在手上时，能验的是"RTL 与固件的位表是不是同一份"：
`grep -n "\[15:8\]\|\[16\]\|\[17\]\|\[18\]\|\[19\]\|\[26\]\|\[31:27\]" src/ps/main.c`
应与 `src/rtl/top/system_top.v:248-276` 的连线逐位对上。

---

## 10. 时序余量：当前那份报告的数，以及它现在为什么不绿

**先说清这份数是谁。** 本章所有时序数字来自 `build/timing_summary.rpt`，
它的 Date 在 `:4`（**2026-09-28 03:03**）、Design State 是 Routed（`:10`），
`build/cdc.rpt:4` 与 `build/clock_util.rpt` 的 Date 是同一次实现。
注意 `build/setup_paths.rpt` 与 `build/hold_paths.rpt` 这两份**不是**同一次的产物
（它们的 mtime 早于上面三份），所以 §10 末尾那条"先认 Date"的规矩对它们同样适用。
**这一版是诊断版，不是交付版**：板上跑的是哪一颗、门禁几项，只认
`board/README.md` 第一行的 md5 名片与 `build/evidence_rNN/`，本套文档不抄这个数
（`board/README.md:1`、`:7`）。

**全局那一行**（`build/timing_summary.rpt:149` 表头、`:151` 数据）：

```
WNS -0.062   TNS -0.812   失败 setup 端点 28 / 40125
WHS +0.050   THS  0.000   失败 hold 端点  0 / 40125
WPWS +0.264               失败脉宽端点    0 / 12864
```

紧跟着一行 `Timing constraints are not met.`（`:154`）。
**注意这一句**：它和 `All user specified timing constraints are met.` 是两个不同的世界，
而门禁第 1 项判的就是上面那两个数（`build/gates.sh:145-147`：WNS ≥ 0、失败端点 == 0）。
所以当前这份产物**跑门禁不会全绿**，这是事实而不是笔误。

**分组那一列才是可比的量**（`:181-188` 的 Intra Clock Table）：

| 组 | WNS | WHS | 失败端点 | 备注 |
|---|---|---|---|---|
| `clk_fpga_0` 100 M | +1.048 | +0.050 | 0 | `:181`，15713 端点 |
| `eth_rxc` 125 M | **−0.062** | +0.050 | **28** | `:182`，4719 端点——全局那个负数就是它 |
| `sys_clk` 50 M | +13.432 | +0.105 | 0 | `:183`，只有 255 端点 |
| `clkout0_1` 50 M 像素 | +1.232 | +0.051 | 0 | `:186`，19360 端点，全设计最大的一组 |
| `clkout1_1` 250 M | 无此列 | 无此列 | — | `:187` 只有 WPWS +2.408 / 10 端点（`NA` 的来历见 §1） |
| `clkout2` 200 M | 无此列 | 无此列 | — | `:188` 只有 WPWS +0.264 / 3 端点 |

跨组只剩两条：`clkout0_1 ↔ sys_clk`（`:198-199`，WNS +13.798 / +3.159）。
其它组之间查不到路径 = `set_clock_groups` 生效了，这正是 §8.1 那条约束的验收证据。

**那 28 个失败端点是谁。** `:365-374` 第一条违例路径摊得很开：
`u_eth/u_cdc/wbin_reg[2]/C → u_eth/u_lm/drop_words_reg[12]/CE`，8 级逻辑
（CARRY4=5 LUT4=2 LUT5=1），数据路径 7.632 ns 里 **route 占 67.7 %**，
时钟偏斜 −0.227 ns。这就是 §5.1 讲的那条：一条仪表的使能挂在了数据通路的指针进位链上。
账本记了四滚的结论（`report/log/OVERNIGHT_LOG.md:5650-5662`）：
换策略（Explore / ExplorePostRoutePhysOpt / Retiming）与第四滚都落在**同一个地方**，
布局后估计一度是 +0.645、布线把它拉到 −0.062 ⇒ **是路由拥塞，不是逻辑深度**；
`Performance_Retiming` 更差（−0.195 / 32）。

**WHS 这一侧的两件事**，一件是好消息一件不是：

- 好消息：当前最差 hold 已经不是 RGMII 那条了。`timing_summary.rpt:289-291` 显示
  全局 WHS +0.050 那条落在 **AXI GP 互连内部**（`s_awid_r_reg[7] → memory_reg[3][15]`
  的 SRL16E，`clk_fpga_0` 组）；`eth_rxc` 组的 hold 也是 +0.050 且 0 失败（`:182`）。
- 不好的是那句**自定的验收口径**：`rk_zynq7020.xdc:46` 写的是
  "WHS 应升到 ≥ 0.4（工具真的插了 buffer）"。当前 0.050 < 0.4，
  而 `:47-49` 已经预告过这件事（r79 试 0.5 那一档时工具只做到 +0.051）。
  按注释自己的话，退回条件与"把结论记成 #46 的实测"才是收尾，
  **不许把验收线悄悄改掉**。

那条 RGMII hold 的机制本仓已经量到，不再靠猜（`report/log/ISSUES.md:2875`，#80；
数字在 `:2881-2885`）：起点 `IDDR` 走 `eth_rxc → IBUF → BUFIO → ILOGIC`（SCD 3.171 ns），
终点 fabric 里的 `m_good_reg` 走 `IBUF → BUFG(fo=2520) → SLICE`（DCD 4.854 ns）
⇒ **两条时钟树差 1.616 ns**，而数据路径只有 1.855 ns。原话是
"综合器只能靠插 hold buffer 硬补，而两条树的相对延迟随布线变"
（`:2889-2892`）。同一段还排除了三条"看起来便宜"的修法：对 IDDR→fabric 加
`set_false_path` 是**错**的（两侧同频同相，这是真实同步路径，判成假路径等于允许终点
采上一拍的值，症状会变成"偶发错帧/CRC 计数错"）；搬走计数器只是让下一条最差路径顶上；
让 fabric 吃 BUFIO 在 7 系列上做不到。****（r92 已落地：IDDR 改吃那只 BUFG、`IDELAY_VALUE` 15→26 把采样沿挪回去；最差 20 条 hold 的偏斜实测从 1.616 ns 变成 0.013~0.349 ns。但 WHS 的**数字**没跟着涨——现在压住它的是 r79 自加严的 0.8 ns hold 不确定度和工具插延迟的粒度，见 `report/OPTIMIZATION_LOG.md` 的 r92 那一节）** 结构性解法要换 IDDR 的时钟源 + 重调 IDELAY +
在线验证，被明确定性为"不是凌晨三点能悄悄塞进构建的东西"。**

**`report_methodology` 里认得这几条**（`build/timing_summary.rpt:43-50`）：

| 规则 | 条数 | 认得它 |
|---|---|---|
| `DPIR-1 Asynchronous driver check` | 2 | 异步复位驱动清单。这一家从 129 条降到 2 条：`bilin_lerp` 那七个数据寄存器不再带异步复位（`report/log/OVERNIGHT_LOG.md:5606-5610`），于是它们能被打进 DSP 流水级（对照写法在 `src/rtl/process/bilin_lerp.v:37`） |
| `LUTAR-1 LUT drives async reset alert` | 1 | 有 LUT 输出驱动异步复位脚——工具能推断，但物理上释放时刻不确定（§2 那条 `locked` 直分发就是这类形状） |
| `SYNTH-5 / SYNTH-6` | 320 / 102 | 分布式 RAM 与 RAM 块时序次优。不是错误，是"这块存储被摊成 LUTRAM 了"的清单 |
| `TIMING-9 Unknown CDC Logic` | 1 | 有一条跨域**没被工具认出来**——和 §6.2 的 `cdc_who` 是同一件事的两个视图 |
| `TIMING-10 Missing property on synchronizer` | 1 | 有同步器**少标 `ASYNC_REG`**（§3 末尾那个 `dc_fifo` 现象是这类计数的来源之一） |
| `TIMING-18 Missing input or output delay` | 7 | 有端口没有任何 IO 延迟约束。所以"`All constraints are met`"这句话的准确解读是**片内**被约束的路径都满足，片外接口没做检查 |

**报告地图**（想查一个数，先认清该开哪个文件；都由 `build/tcl/*.tcl` 在读已布线设计时写出）：

| 文件 | 回答什么 | 一个真实读数 |
|---|---|---|
| `build/timing_summary.rpt` | 全局/分组 WNS·WHS、失败端点、时钟清单 | `:151` 全局 −0.062 / +0.050 / 28 |
| `build/setup_paths.rpt` | 最差几条 setup 落在哪条线上（**路径级**，不是一个数） | 出件脚本 `build/tcl/crit_path.tcl` 已失效（它 `open_project` 的是仓库外的路径），改用 `timing_summary.rpt` 的 Timing Details 段 |
| `build/hold_paths.rpt` | 最差几条 hold 同上 | 出件工具 `build/tcl/hold_paths.tcl:1-6` 那句"为什么要单独写这个"就是本节的主张 |
| `build/cdc.rpt` | 跨域配对表（钟对 + 端点数 + unsafe） | `:17-18` 两条 Critical |
| `build/cdc_details.rpt` | 上一份的逐端点展开（谁） | 由 `build/tcl/cdc_who.tcl:27-29` 写出 |
| `build/clock_util.rpt` | 每个 BUFG 驱动多少负载、占几个时钟区 | `:59` 4774 / 6 区；`:61` `eth_rxc` 的 BUFG 2471 |
| `build/methodology.rpt` | `report_methodology` 的规则命中 | 摘要已抄进 `timing_summary.rpt:43-50` |
| `build/CDC_BASELINE.txt` | CDC 判据比的那四行基线 | `:20-23` |
| `build/gates.sh` | 门禁怎么解析上面这些文件 | `:58-61`、`:86-131`、`:225-246` |

两个"只有 `clock_util.rpt` 看得到"的事实：

- **`eth_rxc` 有两棵全局树**。`build/clock_util.rpt:61` 只列 BUFG 那份（2471 负载 / 4 区），
  `:80` 显示它的源是 `IBUF/O` 在 `IOB_X1Y28`；BUFIO 那份不在这张表里，
  因为它的负载是 ILOGIC 而不是全局网络（**这一句是 #57 落地前的观测**）——这正是上面那条 1.616 ns 偏斜的物理来源。
- **`clk_fpga_0` 的驱动脚是 PS7 内部的 BUFG**：`:60` 的 Driver Path 一路写到
  `processing_system7_0/inst/buffer_fclk_clk_0.FCLK_CLK_0_BUFG/O`。
  所以它的 `create_clock` 只能来自 PS7 IP，我们的手写 XDC 取不到它——8.1 拆文件的全部理由。

**你可以自己验证。** 一句命令把"这份报告是不是当前实现的"钉住，
再顺手确认那 28 个端点属于哪一组：

```bash
grep -n "^| Date\|Design State" build/timing_summary.rpt ; grep -c "Path Group:             eth_rxc" build/timing_summary.rpt
```

期望：第一句打印 `Date : Mon Sep 28 03:03:02 2026`（`:4`）与
`Design State : Routed`（`:10`）——**比任何数字之前先认这两个字段**，
`report/log/ISSUES.md:672-675` 记的那次"念了旧报告"就是这么防的。
第二条给出的就是违例路径明细里 `eth_rxc` 组出现的次数，它必须和分组表 `:182`
那行的"28 个失败端点"同源。

---

## 11. 接手时按这个顺序自查

1. 我要动的这根线，**发射端在哪个域、消费端在哪个域**？拿 §4 那张表和
   `build/cdc.rpt:17-24` 的配对表、`src/constraints/clock_groups_impl.xdc:19-23`
   （那份"跨域靠结构、不靠时序分析"的四行清单）三方对照。
2. 它是**电平、脉冲、还是总线**？分别对应 §3 那张表的第二、三列。
   宽总线自己打拍 = 迟早读到半新半旧（`pl_video_top.v:897-899` 记着删掉那一段的账，
   `src_mode.v:14` 是禁令原文）。
3. 我要不要新开一对同步器？**能并进已有的那条链就别新开**：加宽 `effect_ctrl` 那条链
   会让 unsafe 端点按位长涨（`src/rtl/process/effect_ctrl.v:62`，账本
   `report/log/ISSUES.md:2138` #71），新开一对 `snap_cross` 就多一条配对行、基线要重画。
   反过来，**"这里没有跨域"也要写进注释**（`system_top.v:219` 是样板）。
4. 我要不要把一个发射触发器扇出到两组目的域？这是 **CDC-11** 的签名，
   本仓库红过三次（`pl_video_top.v:229-234`、`:609-617`、`:916-919`），
   修法都是"多花一个 FF"。
5. 同步链的**复位值**与源头一致吗？不跨域的回读口有没有顺手把像素域信号塞进 axi 输出口
   （`pl_video_top.v:631-633`；账本 `report/log/ISSUES.md:3138` #84）？
6. 我准备做的"把某个标志打一拍再用"，是不是 §5.1 那条禁令？
   我准备做的"数 N 拍然后认为稳定了"，是不是 §5.2 那条禁令？
7. 时序数字：**报分组、报失败端点、报是哪一条路径**，
   只有策略名的结论不许当收益（`build/gates.sh:225-246`、
   `report/OPTIMIZATION_LOG.md` §4 与 §8）；跨版比之前先确认**归属没换人**；
   同一策略 + 同一网表的重掷不是一条路（`report/log/OVERNIGHT_LOG.md:5664-5666`）。
8. 改 bit 之前先 `md5sum`。认 md5 不认文件名（`board/README.md:7` 那句"名片"），
   比数字之前先认报告的 `Date` 行（§10 末）。

---

## 附：本章读过的文件

**RTL**：`src/rtl/clocks/clk_gen.v`、`src/rtl/top/{system_top,pl_video_top}.v`、
`src/rtl/eth/{eth_udp_video_top,dc_fifo,sync_fifo,snap_cross,ddr_bank_commit,link_monitor,rgmii_rx,gmii_to_rgmii,gmii_rx_mac,udp_rx_parser}.v`、
`src/rtl/video/{video_timing,video_timing_1024x600,frame_commit_lock,split_display,osd_overlay}.v`、
`src/rtl/util/{src_mode,key_long,ps_publish,angle_ctrl,src_arb}.v`、
`src/rtl/process/{effect_ctrl,bilin_lerp}.v`、`src/rtl/process/zoom/zoom_snap.v`、
`src/rtl/hdmi/{rgb2dvi,tmds_encoder,tmds_serializer}.v`。
**约束与构建**：`src/constraints/rk_zynq7020.xdc`、`src/constraints/clock_groups_impl.xdc`、
`build/tcl/build_system_axigpio.tcl`、`build/tcl/{cdc_who,hold_paths,crit_path}.tcl`、
`build/gates.sh`、`build/CDC_BASELINE.txt`、
`vivado_system/zynq_video_sys.gen/sources_1/bd/design_1/ip/design_1_processing_system7_0_0/design_1_processing_system7_0_0.xdc`。
**报告**：`build/{timing_summary,cdc,cdc_details,clock_util}.rpt`。
**仿真**：`sim/prim/{MMCME2_BASE,unisims_sim}.v`、
`sim/{tb_v99_unisim_sim,tb_v79_abort_toggle,tb_v82_src_mode,tb_ps_publish}.v`、`sim/run_one.sh`。
**固件与上位机**：`src/ps/main.c`、`src/host/health_read.mjs`。
**记录**：`report/log/ISSUES.md`（#18/#38/#46/#47/#49/#65/#71/#80/#84/#95/#105 各段）、
`report/log/OVERNIGHT_LOG.md`（§82–§83）、`report/log/CHANGELOG_V7.md`、
`report/OPTIMIZATION_LOG.md`（§4、§8）、`report/study/00_前置知识/02_时钟复位与CDC.md`、
`report/study/02_架构/02_时钟与复位树.md`、`board/README.md`。

## 附二：这一版纠正掉的旧说法

这一版是重写，以下几条与旧稿不同，**旧稿的写法是错的或已经过期**：

1. **旧稿里指向工作记录的那批引用，用的都是搬家前的那个目录名，已全部改掉**：
   那个目录已经不存在。今天交付文档在 `report/`、工作记录在 `report/log/`
   （`report/log/ISSUES.md`、`report/log/OVERNIGHT_LOG.md`、`report/OPTIMIZATION_LOG.md`），
   分派表在 `report/README.md`，本套的口径写在 `learn/README.md` §3 第 1 条。
2. **全局时序数不再是 "WNS +0.066 / WHS +0.056 / 失败端点 0 /
   `All user specified timing constraints are met.`"**：当前这份
   （r81 的实现，2026-09-28 03:03）是 **WNS −0.062 / 28 个失败 setup 端点 /
   `Timing constraints are not met.`**，而且违例路径已经点名到
   `u_cdc/wbin → u_lm/drop_words`。旧稿那份是 r80 换策略后那一颗的数字，
   它现在只以文字形式留在 `board/README.md:7` 那句名片里，
   报告文件本身已经被后一次实现覆盖掉了（r80 当时没冻结）。
3. **旧稿把 `eth_rxc→clkout0_1` 当成一条会涨的 Critical 记账（"51 端点 / 1 unsafe"，
   并且用它当 U11 那次改动的证据）——今天这一行已经从 `cdc.rpt` 的 Critical 里消失了**：
   现在只剩两条 Critical（`:17-18`），基线里那四行中有两行属于"基线里有而本版没有"。
   按 `build/gates.sh:126` 那句话，这**记成改进之前必须先查清原因**；
   本仓对同一现象有一次完整的示范（`build/CDC_BASELINE.txt:9-18`：
   `eth_rxc>clk_fpga_0` 那一行的配对没消失，是它唯一那个 unsafe 端点被删掉了，
   工具因此把整行降成 Warning——查清之后才敢记账）。
   另一处措辞校正：`clkout0_1↔sys_clk` 那两行今天叫 **Info / Safely Timed**
   （`:23-24`），也就是"同 MMCM 生成钟，工具做了真 setup 分析"，
   旧稿只说"跨组只剩两条"而没说清它的性质。
4. **`DPIR-1` 不再是 129 条**（今天是 2 条，`build/timing_summary.rpt:46`）：
   降下来是因为 `bilin_lerp` 那七个数据寄存器不再带异步复位。
5. **"同一套约束三次构建 WNS = 0.918 / 0.807 / 0.314 是掷硬币"这句话旧稿留着没删**：
   本仓自己在 `report/OPTIMIZATION_LOG.md` §8 已经否掉它，r81 四滚又钉了一次
   （同一策略 + 同一网表 = 确定性落点）。旧稿只保留了 r65 那一条更正的引用，
   正文的语气还是"掷硬币"，现在按 §10 的说法改回来了。
6. **旧稿的 `clock_util.rpt` 负载数（`clkout0_1` 4876 / 6 区）已经旧**：今天是 4774 / 6 区
   （`build/clock_util.rpt:59`）。
7. **旧稿把 `clkout1_1` 那一行读成"只有脉宽检查有数（WPWS 2.408）"**，
   更准确的凭据是 `build/timing_summary.rpt:942-944` 里 **Setup/Hold 写 `NA`**
   ——NA 与 0 的含义差别正是这一章要教的（§1 末尾）。
8. **旧稿说"`p_good` 在顶层硬接 1、坏包统计是死的"**：这条已经不成立。
   `src/rtl/eth/gmii_rx_mac.v:4-7` 现在自己算 FCS-32，`udp_rx_parser.v:199` 把
   `p_good <= s_good`，`eth_udp_video_top.v:234` 注释明写"这一位从此是真值"。
   **注意 `link_monitor.v:5` 与 `eth_udp_video_top.v:270` 两处注释还留着旧话**——
   读代码时以 `gmii_rx_mac.v:4-7` 与 `eth_udp_video_top.v:234` 为准
   （`report/log/ISSUES.md:295` 是那条老账的原文，它自己标着"发现未修"，那一步
   在 V7.9.5 做了第 1 步）。这条也说明：**源码注释会旧于代码**，
   `learn/README.md` §5 那张表里已经收了同类的一条。
9. **所有行号重新核对过一遍**。`system_top.v` 现在 305 行、`pl_video_top.v` 994 行、
   `link_monitor.v` 198 行，而旧稿引用的 `system_top.v:307-308`、
   `pl_video_top.v:1023-1026`、`link_monitor.v:212-221` 都已经**超出文件长度**——
   那是 2026-09-28 那一轮"注释手术"（5003 行注释压到 3552 行）之后的位移，
   不是旧稿当时写错。这一条本身就是本套文档"行号会漂"约定的活例子。
