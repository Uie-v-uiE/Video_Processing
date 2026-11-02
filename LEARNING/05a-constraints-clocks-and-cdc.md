# 05a 约束、时钟、复位与 CDC

> 本篇讲**约束侧的事实**：哪些 .xdc 真的进了构建、五个时钟域各自的读数、帧缓存的写侧读侧到底挂在哪个钟上、`set_clock_uncertainty` 的射程边界、换钟之后约束静默失效的机制、复位树与 CDC 结构、I/O 约束欠账的定性。
> 逐刀时序账（r62→r126 每一刀的 WNS/WHS 变化与验收体系）在 `05b-timing-cuts-and-verification.md`，本篇不重复；时序基础概念（周期/setup/hold/余量怎么算）在 `study_docs/main_report_study/timing/00-from-zero-clock-period-setup-hold.md`。
> 所有数字都点名出处；核不到出处的，本文明确写"没找到"，不猜。

---

## 1 在用哪两份 .xdc：文件存在 ≠ 文件生效

**结论：整个构建只加载两份约束——`src/constraints/rk_zynq7020.xdc` 和 `src/constraints/clock_groups_impl.xdc`。同目录另外 7 份 .xdc 全是候选件或实验件，默认一行都不生效。**

流程脚本里 `add_files -fileset constrs_1` 只有这三处调用（第三、第四处在环境变量开关里面）：

| 行号 | 加载对象 | 生效条件 |
| --- | --- | --- |
| `build/tcl/build_system_axigpio.tcl:31` | `rk_zynq7020.xdc` | 无条件，综合 + 实现都用 |
| `build/tcl/build_system_axigpio.tcl:36-38` | `clock_groups_impl.xdc` | 无条件，但 `used_in_synthesis false` / `used_in_implementation true` |
| `build/tcl/build_system_axigpio.tcl:57-60` | `r116_rgmii_input_window.xdc` | 仅当 `VP_R116_IO_WINDOW=1` |
| `build/tcl/build_system_axigpio.tcl:75-78` | `r119_hdmi_source_window.xdc` | 仅当 `VP_R119_TMDS_WINDOW=1` |

`build/tcl/build_pl_full.tcl:22` 只加 `rk_zynq7020.xdc` 一份——那是条 PL-only 的短路径，不是交付路径。

7 份没在用的：`r114_io_async.xdc`、`r114_io_varianta_rise_only.xdc`、`r114_io_variantb_phy_delay.xdc`、`r115_io_window_candidate.xdc`、`r116_rgmii_input_window.xdc`、`r119_hdmi_source_window.xdc`、`r119b_hdmi_tp1_pinclk.xdc`。它们的身份被 `build/tcl/r124_tiers_probe.tcl:42-45` 写得很直白——脚本里有两个显式列表：`:42` 的 `set want` 正好是上面那两份，`:43-45` 的 `set banned` 逐名列出这 7 件（`r119_hdmi_source_window` / `r119b_hdmi_tp1_pinclk` / `r116_rgmii_input_window` / `r114_io_async` / `r115_io_window_candidate` / `r114_io_varianta_rise_only` / `r114_io_variantb_phy_delay`）。`:66` 那条判据是 `if {[llength $after] != [llength $want]}` → 打印 `REFUSE: impl constraint count ... != 2`。**一份只读探针脚本把"实现期约束集必须正好是 2 份"做成了硬门禁**，多挂任何一件候选件它就直接拒绝跑。

### 这条教训为什么值得单独立一节

`clock_groups_impl.xdc` 存在的原因是 `rk_zynq7020.xdc:62-75` 那段留档里的一条实测踩坑：异步时钟组原先就写在主 .xdc 里，`set_clock_groups -group [get_clocks -quiet clk_fpga_0] ...`，而 `clk_fpga_0` 是 PS7 IP 在自己的 XDC 里 `create_clock` 出来的（`FCLKCLK[0]`），**综合阶段这个对象还不存在**。后果分两层：

1. 每个 run 吃一条 `CRITICAL WARNING [Vivado 12-4739] set_clock_groups: No valid object(s) found for '-group [get_clocks -quiet clk_fpga_0]'`（`rk_zynq7020.xdc:68-69` 原文记录了这条）。
2. **整条命令不生效**，连带把本来能取到的 `eth_rxc` / `sys_clk` 两组一起废掉（`rk_zynq7020.xdc:70`）。

`-quiet` 只能压住 `get_clocks` 自己的报错，压不住命令失败——这是很多人对 `-quiet` 的误解。同样的坑在 `rk_zynq7020.xdc:43-45` 又出现一次：把取不到的名字并进 `set_clock_uncertainty` 那条命令，会让整条命令空转，现场只留一句 warning。

想再补一刀：把 Tcl 守卫写进 .xdc 也不行。`build/tcl/build_system_axigpio.tcl:72-74` 记的是 2026-10-04 实测：.xdc 里写 `if`/`puts`，Vivado 报 `Designutils 20-1307` 并且**整块跳过**（留档件 `build/evidence/r119_xdc_loads_probe3.txt`），也就是说守卫会静默失效。`rk_zynq7020.xdc:71-73` 同一段给出结论：唯一正规解法是"按时机分文件"。

所以三条可迁移的判据：

- **看流程脚本，不看目录列表。** 判"某份约束是否生效"，唯一凭据是构建脚本里的 `add_files` 加上它的 `used_in_*` 属性和环境变量开关。文件名里带 `r119`、注释写得再详细都不算。
- **一条命令一个对象集。** 取不到对象的名字必须拆开，不能和有效名字混在一条命令里——混了的代价是有效部分也一起作废。
- **拆分不改数字。** `clock_groups_impl.xdc:8` 特意说明：综合阶段这条约束在拆分前也是失败的（等于不存在），所以按时机拆分**不改变任何时序数字**，只是让它在实现阶段真的生效。凡是"我加了约束但 WNS 没动"，先怀疑它到底有没有被加载，而不是怀疑约束写错了。

---

## 2 五个时钟域逐条读：谁定义的、驱动什么、读数多少

**结论：五个域里只有两个是这份仓库自己 `create_clock` 的；一个由 PS7 IP 定义；两个是 MMCM 生成钟；而 250 MHz 那一档在时序报告里根本没有 setup/hold 行——它不是"过了"，是"没被检查"。**

下面所有 WNS/WHS 都读自 `build/report/timing_summary.rpt`（Intra Clock Table，181-188 行）。这份报告的 Design Timing Summary 一行给的是 WNS 0.739 / WHS 0.052 / 失败 setup 端点 0 / 端点总数 51135（`:151`），下一句 `All user specified timing constraints are met.`（`:154`）。

### 2.1 `sys_clk` 50 MHz — 唯一真正的输入钟

- 定义：`rk_zynq7020.xdc:6` `create_clock -period 20.000 -name sys_clk [get_ports sys_clk]`，脚位 W17 LVCMOS33（`:5`）。
- 驱动什么：MMCM 的 `CLKIN1`（`src/rtl/clocks/clk_gen.v:17` `.CLKIN1_PERIOD (20.000)`），是**两个 MMCM 实例共同的源**；另被 IDelayCtrl 参考链与上电复位计数器用到。
- 读数：WNS 14.876 / WHS 0.222，端点 323（`timing_summary.rpt:183`）。WNS 14.876 配 20 ns 周期，等于这个域里最长的锥只用了约 5 ns 逻辑。
- **323 端点这个数字要留意**：全设计 51135 个端点里只有 323 个挂在 `sys_clk` 本身。"50 MHz 输入钟很松"这件事对全局没有代表性。

### 2.2 `clk_fpga_0` 100 MHz — 不在本仓 .xdc 里

- 定义：PS7 IP 自己的 XDC（`FCLKCLK[0]`），本仓没有任何 `create_clock` 命中它——`rk_zynq7020.xdc:65` 与 `clock_groups_impl.xdc:3` 都写明了这一点。频率来自 BD 参数 `CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100}`（`build/tcl/build_system_axigpio.tcl:97`）。
- 驱动什么：所有 AXI 事务（`clock_groups_impl.xdc:12`）。顶层 `axi_clk` 就是它的别名（见 §3）。
- 读数：WNS 1.850 / WHS 0.053，端点 15721（`timing_summary.rpt:181`）。
- 因为它不归本仓的 `create_clock` 管，`get_clocks clk_fpga_0` 在综合阶段取不到 ⇒ 约束必须拆到只在实现阶段生效的文件（§1）。

### 2.3 `clkout0_1` 50 MHz — 像素域，端点数最大的一档

- 定义：MMCM `CLKOUT0` 生成钟。`clk_gen.v:21` `.CLKOUT0_DIVIDE_F (20.000)` 对 VCO 1000 MHz（`:19` `.CLKFBOUT_MULT_F (20.000)` × 50 MHz 输入）⇒ 50.000 MHz。Vivado 报出的名字带 `_1` 后缀：`clk_gen` 被例化两次，第二个实例的输出净名与第一个重名，工具自动加后缀区分。
- 驱动什么：像素/显示链全体。`clock_util.rpt:60` 那行是 `u_pl/u_clk/u_bufg_pix/O`，Non-Clock Loads 3276，是全局钟里负载最重的一棵。
- 读数：WNS 3.630 / WHS 0.059，端点 **30179**（`timing_summary.rpt:186`）——全设计端点的约 59%（30179/51135）在这一档里。
- 与 `sys_clk` 之间是全表**仅有的两行**跨域检查：`clkout0_1 → sys_clk` WNS 14.757 / WHS 0.165（19 端点）、`sys_clk → clkout0_1` WNS 3.695 / WHS 0.200（231 端点），`timing_summary.rpt:198-199`。其余域被 `set_clock_groups` 判成异步，不参与 setup/hold 分析——这两行存在，恰恰说明 `sys_clk` 与 `clkout0_1` **在同一个异步组内**且没被 `set_clock_groups` 打掉（`clock_groups_impl.xdc:31` 的 `-include_generated_clocks sys_clk`）。

### 2.4 `eth_rxc` 125 MHz — 全设计 WNS 的持有者

- 定义：`rk_zynq7020.xdc:36` `create_clock -period 8.000 -name eth_rxc [get_ports eth_rxc]`，脚位 Y19（`:20`）。
- 驱动什么：RGMII 收口 + 整个以太网协议栈与帧重组（`clock_groups_impl.xdc:11`）。
- 读数：WNS **0.739** / WHS 0.052，端点 4835（`timing_summary.rpt:182`）。WNS 0.739 等于设计级 WNS（`:151`）——最差那条 setup 路在 125 MHz 域里，而不是在最快的域里；100 MHz 域反而有 1.850。"频率高 ≠ 更紧"的直接例子。
- 唯一一个带 hold 不确定度带的域（`rk_zynq7020.xdc:50`，见 §4）。

### 2.5 `clkout1_1` 250 MHz — 报告里没有 setup/hold 这一行

- 定义：MMCM `CLKOUT1` 生成钟，`clk_gen.v:24` `.CLKOUT1_DIVIDE (4)` ⇒ 1000/4 = 250 MHz，`CLKOUT1_PHASE (0.0)`（`:25`）。
- 读数：Intra Clock Table 的 `clkout1_1` 一行，WNS/WHS/TNS/THS 与各端点列**全空**，只有 WPWS 2.408 与 10 个脉宽端点（`timing_summary.rpt:187`）。Timing Details 更直接（`:945-947`）：

  ```
  Setup :   NA  Failing Endpoints,  Worst Slack   NA  ,  Total Violation   NA
  Hold  :   NA  Failing Endpoints,  Worst Slack   NA  ,  Total Violation   NA
  PW    :    0  Failing Endpoints,  Worst Slack   2.408ns,  Total Violation  0.000ns
  ```

  `NA` 不是 0，意思是**这个域里不存在被计时的 setup/hold 端点**，工具没得比。`Pulse Width Checks` 段的两条也印证它的身份：`Min Period  BUFG/I  Required 1.592  Actual 4.000  Slack 2.408  BUFGCTRL_X0Y2  u_pl/u_clk/u_bufg_5x/I`（`:959`）与 `Max Period  MMCME2_ADV/CLKOUT1  213.360  4.000  209.360`（`:960`），`Sources: { u_pl/u_clk/u_mmcm/CLKOUT1 }`（`:956`）。全是单元库自己的脉宽窗口，跟数据路径无关。
- 为什么不纳检——工具/结构层面的事实：这棵钟树几乎没有负载。`clock_util.rpt:63` 给 `clkout1_1`（驱动脚 `u_pl/u_clk/u_bufg_5x/O`，站点 BUFGCTRL_X0Y2）的 Clock Loads 是 1；`clock_util.rpt:220` 的 `u_pl/u_clk/clk_pix5x` 网络行负载计数是 `0 | 8`，对照 `clock_util.rpt:151` 的 `clk_pix` 行是 `2492 | 8`。**钟在跑、BUFG 占着名额，但它没有驱动一片需要互相计时的寄存器** ⇒ 没有 setup/hold 端点 ⇒ 报告留空。
- 两条推论：
  1. 念名册时看到"250 MHz 那档没数"，只能念成"这一轮没被检查"，不能念成"250 MHz 很安全"。想让它被检查，前提是往它上面挂真实寄存器负载。
  2. 想加严这一档也加不动：`set_clock_uncertainty` 挂上去只作用到那 10 个脉宽端点，而 4 ns 周期对 `BUFG/I` 的 1.592 ns 最小周期要求给的余量是固定的 2.408 ns，与逻辑无关。
- 例化上下文：`clk_gen` 确实被例化两次——`pl_video_top.v:128` 的 `u_clk` 出像素钟与 5x 钟；`system_top.v:121` 的 `u_idelay_clkgen` 只用 `clk_200m`，它的 `clk_pix` / `clk_pix5x` 在 `:123` 被接到 `clk_pix_unused` / `clk_pix5x_unused` 两根不驱动的线上。工具用量表：`BUFGCTRL Used 8 / Available 32`、`MMCM Used 2 / Available 4`、`BUFIO Used 0`（`clock_util.rpt` 第 2 节前的用量表，`:43-48`）。

---

## 3 怎么自己查清一条跨域路：帧缓存的写侧与读侧到底在哪个域

**结论（先给）：显示帧缓存 `fb_bilin` 的写口在 `axi_clk` = `clk_fpga_0` 100 MHz，读口在 `clk_pix` = `clkout0_1` 50 MHz——这是一条真实的跨域 BRAM。而"网包 → 帧缓冲"那一跳的 `dc_fifo` 写口在 `eth_rxc` 125 MHz、读口在 `axi_clk` 100 MHz。两条路的域完全不同，绝不能混着念。**

下面记的是**过程**，因为这类问题只能靠过程回答。方法就三步：从顶层端口倒推别名 → 到实例处读端口连接 → 用报告确认这条钟真的存在且频率对。

### 第 1 步：`axi_clk` 到底是谁

顶层 `system_top.v` 里搜 `axi_clk`，命中两处（`:176`、`:261`），两句都是 `.axi_clk(fclk0)`。再往上找 `fclk0` 的出生地：`:83` PS7 实例的 `.FCLK_CLK0(fclk0)`。所以：

```
fclk0  ≡  PS7 FCLK_CLK0  ≡  报告里的 clk_fpga_0  ≡  100 MHz
axi_clk 只是它在 PL 侧的局部别名
```

配套复位：`:83` 同一行还有 `.FCLK_RESET0_N(fclk0_rst_n)`，`:261` 把它作为 `.axi_rst_n(fclk0_rst_n)` 送进 `u_pl`。**读跨域路的正确顺序永远是"先解别名，再看连接"，直接搜 `clk_fpga_0` 在 RTL 里是搜不到的**——那个名字只存在于 PS7 的 XDC 和时序报告里。

### 第 2 步：帧缓存的两个时钟端口

`pl_video_top.v:732-749` 是唯一的实例点，端口清单里两个时钟各管一头：

```verilog
) u_bilin (
    .clk(clk_pix), .rst_n(rst_pix_n),                                    // :735 读侧 = clkout0_1 50 MHz
    .wr_clk(axi_clk), .wr_en(aw_wr_en), .wr_addr(aw_wr_addr), .wr_data(aw_wr_data),  // :736 写侧 = clk_fpga_0 100 MHz
```

`clk_pix` 在 `pl_video_top.v` 里的出生地是 `pl_video_top.v:126` `wire clk_pix, clk_pix5x, locked;` + `:128` `clk_gen u_clk (` + `:130` `.clk_pix(clk_pix)`。`clk_gen.v:54` `BUFG u_bufg_pix (.I(clkout0), .O(clk_pix))`，`:21` `CLKOUT0_DIVIDE_F (20.000)` ⇒ 50 MHz。**别名链一路走到底，每一跳都有行号，这才是"查清了"**。

再用报告复核：`clock_util.rpt:60` 那行把 `u_pl/u_clk/u_bufg_pix/O` 直接标成 Clock `clkout0_1`、Net `u_pl/u_clk/clk_pix`——RTL 名与报告名在这里对上，频率列 20.000 ns。文件头 `pl_video_top.v:6` 也留了一句人话口径：`Display BRAM written ONLY by axi_frame_writer_gated during blanking (~de).`——写只在消隐期发生，这是"为什么敢让两个域共用一块 BRAM"的结构理由，不是时序结论。

### 第 3 步：`dc_fifo` 那一跳（网包侧进 AXI 侧）

`eth_udp_video_top.v:298-304`：

```verilog
dc_fifo #(.DATA_W(36), .ADDR_W(13)) u_cdc (
    .wr_clk(gmii_rx_clk), .wr_rst_n(rst_n),
    ...
    .rd_clk(axi_clk), .rd_rst_n(axi_rst_n),
```

`gmii_rx_clk` 的出生地：`rgmii_rx.v:47` `assign gmii_rx_clk = rgmii_rxc_bufg;`——它就是 PHY 恢复出来的 `eth_rxc`，125 MHz。`eth_ctrl.v:3` 明确写了"RGMII 下 `gmii_tx_clk` 就是 `gmii_rx_clk`"，`gmii_to_rgmii.v:25` 用一句 `assign gmii_tx_clk = gmii_rx_clk;` 落实。所以写侧域 = `eth_rxc`，读侧域 = `clk_fpga_0`，跟第 2 步那条**不是同一条路**。

顶层怎么把 `eth_rxc` 递进去的：`system_top.v:34` 端口 `input wire eth_rxc` → `:174` `.rgmii_rxc(eth_rxc)`。同时 `:303` 还有一条 `.eth_wr_clk(eth_gmii_clk)` 把 125 MHz 收钟单独引出给 `u_pl`（源头是 `eth_udp_video_top.v:387` `assign eth_gmii_clk = gmii_rx_clk;`）——注意这个名字带 `wr`，但它是**入包流的写钟**，不是显示帧缓存的写钟；两者混淆是这类问题最常见的错法。

### 第 4 步：跨域清单以约束文件为准，别自己数

`clock_groups_impl.xdc:19-23` 已经把全设计的跨域路写成了四条台账，并逐条给出"靠什么保证"：

| 方向 | 用的结构 |
| --- | --- |
| `eth_rxc → clk_fpga_0` 视频流 | `dc_fifo`（格雷码 + 2FF，BRAM） |
| `eth_rxc → clk_fpga_0` 帧事件 | 翻转 + 3FF 边沿检测（`ddr_bank_commit`） |
| `clk_pix → clk_fpga_0` 消隐窗 | 3 级像素 + 3FF（`frame_commit_lock`） |
| `clk_fpga_0 → clk_pix` 控制字 | 3FF（`pl_video_top` / `effect_ctrl`） |

对照 `pl_video_top.v` 能看到这些 3FF 实名：`:165` `(* ASYNC_REG = "TRUE" *) reg [1:0] ms0, ms1, ms2;` 配 `:166` `always @(posedge axi_clk ...)`（`:163` 的 `mode` 从 AXI 侧取），以及 `:472-519` 一串 `{ss2,ss1,ss0}`、`{ab2,ab1,ab0}`、`{el2,el1,el0}`、`{lv2,lv1,lv0}`、`{op2,op1,op0}` 全部在 `posedge clk_pix` 上复位到 `rst_pix_n`。`:479` 那条注释本身就是一次纠错记录：`src_sel` 早就走了 3 级而同处另一条只走了 2 级，"一处对一处错"，现在统一成 3 级。

### 三条能带走的做法

1. **只认端口连接，不认信号名。** `axi_clk` 听起来像总线时钟、`eth_wr_clk` 听起来像帧缓存写钟，两个都必须靠 `system_top.v` / `pl_video_top.v` 里的实际连线才能定域。名字是给人看的，端口表才是工具看的。
2. **每条跨域路要在两个地方各出现一次。** RTL 里有同步链（§3 第 2/3 步）+ 约束文件或报告里有它的身份（第 4 步、`cdc.rpt` 的域对表）。只在一处出现的那条，要么是被漏掉的隐患，要么是你数错了。
3. **BRAM 双端口分域 ≠ 被时序检查。** `eth_rxc` 与 `clk_fpga_0`、`clk_fpga_0` 与 `clkout0_1` 都被 `set_clock_groups` 判异步，所以这些跨域 BRAM 路**不参与 setup/hold 分析**（Inter Clock Table 只有 §2.3 那两行）。安全性来自结构（格雷码 + 2FF + 只在消隐期写），不来自 slack 读数——这句话在 §6 会再兑现一次。

---

## 4 `set_clock_uncertainty` 的射程：读别人名册之前的前置检查

**结论：全仓现行约束里 `set_clock_uncertainty` 只有一条，只加在 hold 上、只加在一个对象上（`rk_zynq7020.xdc:50`）。所以四个域的 WHS 不是四把一样的尺子量出来的，跨域比大小没有意义。**

```tcl
set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]   # rk_zynq7020.xdc:50
```

把它套到 §2 的读数上：

| 域 | WHS（`timing_summary.rpt`） | 这一列里含不确定度带吗 |
| --- | --- | --- |
| `eth_rxc` | 0.052（`:182`） | 含 0.800 ns 自加悲观 |
| `clk_fpga_0` | 0.053（`:181`） | 不含 |
| `clkout0_1` | 0.059（`:186`） | 不含 |
| `sys_clk` | 0.222（`:183`） | 不含 |
| `clkout1_1` | 无该行（`:187`，见 §2.5） | 不适用 |

"0.052 和 0.053 差不多、`sys_clk` 的 0.222 最厚"——这类话在这张表里**一句都不能说**：`eth_rxc` 是已经被扣掉 0.800 之后还剩 0.052，另外三列一分没扣。这条不是理论洁癖，写它的地方有两处：`build/tcl/probe_uncertainty_uniform.tcl:6-11`（原话 `Saying "hold 四域都差不多" would be an artifact of the constraint, not of the design`）与 `study_docs/main_report_study/timing/02-how-this-project-did-it.md:67-78`。

### 4.1 那次实测：把同一条带子挂到所有域上

`probe_uncertainty_uniform.tcl` 的设计值得照抄：开已布线 dcp、只改一个变量（`:44` `set_clock_uncertainty -hold $BAND [get_clocks *]`，BAND 默认 0.800 见 `:23`）、逐域读 before/after（`:66` 打印 `UNC|clk=...|whs_before=...|whs_after=...`）。它还带两条防空转的判据：`:47` 若一条也没落上就 `REFUSE`（脚本原话"这一体检没有变量"），`:51-52` 用 `get_property HOLD_UNCERTAINTY` 把属性**读回来**——`:48` 的注释说得很直白："写了但工具没吃"是这类实验最常见的假绿。

实跑结果留在 `build/evidence/r115_unc/summary_hold_after.txt`：

- 设计级那一行（`:151`）：`-0.747 / -8112.086 / 25742 / 51135`，即 WHS 从 0.052 或 0.053 那一档整体变 **−0.747**、失败 hold 端点 **25742**。同一行右半段 WPWS 仍是 0.264、失败 0——脉宽检查不吃 hold 带，这条不变本身就是"口径隔离干净"的证据。
- 逐域（`:181-188`）：`clk_fpga_0` −0.747 / 8124 端点、`sys_clk` −0.578 / 310、`clkout0_1` −0.741 / 17304，而 `eth_rxc` **仍是 +0.052 / 0 失败**（`:182`）——因为它本来就是在 0.800 带下做到正的。
- 等式核对：−0.747 = 0.053 − 0.800。这条等式在 `timing/02-how-this-project-did-it.md:80-83` 被点名，那里还指向两份对照件 `report/40-optimization.md` §3 的 V13 行与 `report/timing/cut_ledger.tsv` 的 C2 行；本文只引用能直接核到读数的 `build/evidence/r115_unc/`。

那次实验的定位，`timing/02-….md:84-86` 写得很克制：**这是测量，不是采纳**；方向是加严，本来就不产收益，它买到的是"欠账显形"。同处留下一条文档纪律：交付文档里"四域 hold 全为正"那句必须限定成"在现行约束集下为真"。

还有一条方法层面的警告在 `probe_uncertainty_uniform.tcl:14-16`：布线后只改 uncertainty，工具只重算余量、**不重跑布局布线**，所以 "after" 是"统一悲观模型下的 what-if"，不是重新优化过的设计。驱动脚本会把这句话打印出来，就是为了没人把负数念成"板子坏了"。

### 4.2 前置检查：拿到任何一份名册先做这四步

1. `grep -c set_clock_uncertainty src/constraints/*.xdc` 数一数这份设计到底有几条——"只有一条"或"一条都没有"是常态，不是特例。
2. 看每条命中哪个对象。`[get_clocks *]` 与 `[get_clocks eth_rxc]` 出来的表，列名可以一样，含义不一样。
3. 检查有没有 setup 侧的带子。本仓**四个域都没有 setup 项的 `set_clock_uncertainty`**，这条欠账在 `timing/02-….md:778` 被自己列了出来，并附一句判断："补上它们只会让读数变小（把债显形），不会让设计变快。"
4. 只有同一口径下的两个数才能相减。跨口径的差值要显式写清哪一侧带了带子、带多宽。

---

## 5 换钟 / 加 MMCM 会静默缩小约束射程

**结论：`set_clock_uncertainty`、`set_clock_groups`、`set_input_delay`/`set_output_delay` 都是按名字取对象的。重源化（换 MMCM、换 BUFG、多例化一个 `clk_gen`、改分频）之后生成的钟名会变，旧名字不再命中任何对象——而工具不报错，只留一句 warning，于是同一份 .xdc 覆盖的范围悄悄变小，slack 读数却"更好看"。**

### 5.1 本仓已经有的名字证据

`clk_gen` 被例化两次（§2.5 末尾），时序报告的 Clock Summary 因此同时列出 `clkfbout` 与 `clkfbout_1`、`clkout2` 与 `clkout0_1` / `clkout1_1`（`build/report/timing_summary.rpt:167-171`）。`_1` 这个后缀不是人写的，是工具为了区分重名生成的。**任何写死 `get_clocks clkout0` 的约束，在这份工程里现在会取不到对象**——现在报告里存在的名字是 `clkout0_1`。这条变化连一次"优化"都不需要，只是多例化了一个模块。

对照本仓两种写法的稳健性：

| 写法 | 出处 | 换钟后的行为 |
| --- | --- | --- |
| `-include_generated_clocks sys_clk` | `clock_groups_impl.xdc:31` | 稳健：按拓扑关系抓下游生成钟，不依赖具体生成钟名 |
| `set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]` | `rk_zynq7020.xdc:50` | 稳健：`eth_rxc` 是顶层端口钟，名字由本仓 `create_clock -name` 钉死（`:36`） |
| `set_output_delay -clock clkout1_1 …` | `r119_hdmi_source_window.xdc:51-52` | **脆**：直接写死 `_1` 后缀。若再加第三个 MMCM 实例，像素钟可能变成 `clkout0_2`，这条窗会静默脱靶 |

`clock_groups_impl.xdc:14-17` 那段注释实际上已经把"名字写法"当经验记下来了：少了 `-include_generated_clocks` 这个后缀，`clk_pix` 会被当成独立时钟去和 `eth_rxc` 做 setup 分析，历史上是 WNS≈−6.7 的假违例（它点名的 `issues.md #18` 这条我没在本次工作树里核到原文，所以只按注释转述，不引用编号内容）。

### 5.2 覆盖面丢失能量成硬读数

`study_docs/main_report_study/timing/02-how-this-project-did-it.md:88-93` 把这件事写成了两段：同名风险在加 MMCM 或重新源化时钟之后更常见，"都可能不再命中任何时钟名而工具不报错"；因此**读任何 slack 之前，先按名字复查约束还在不在**。它还给了一个把覆盖面丢失折算成纳秒的实例：某次对照里 **+0.759 ns 里约 0.67 ns 是覆盖面丢失换来的**（该文点名出自 `report/timing/gates_g1_g12.md` 的 C3 行）。也就是说这条"收益"里 88% 不是设计变快，是检查变少。

顺带把 §1 那条串起来：`rk_zynq7020.xdc:43-45` 记的是同一种失效的另一半——把 `get_clocks` 取不到的名字并进一条命令，会让**整条命令空转**，连带把有效部分一起废掉。一个是"射程变小"，一个是"整条归零"，共同点是现场都只留 warning。

### 5.3 三条复查动作

1. **建一张钟名清单再建 slack 清单。** `report_clock_timing -type clock` 或直接看报告的 Clock Summary 那一节，把在逃的钟名列出来，与 .xdc 里所有 `get_clocks` 的字面量取交集；差集非空就是射程问题，先解释差集再看数。
2. **把"约束命中数"当成一个读数记进台账。** 本仓的探针已经在这么干：`build/tcl/probe_uncertainty_uniform.tcl:43-47` 用 `set nset [llength [...]]` 数命中条数，`$nset == 0` 直接 `REFUSE`；`:51-52` 再把 `HOLD_UNCERTAINTY` 属性读回来。这两步合起来就是"写进去且真吃上"的证据链。
3. **改钟之后第一次读数不当收益。** 换了钟的构建，第一份名册只能用来判"射程有没有变小"，不能用来判"设计有没有变快"。

### 5.4 负 MMCM 相位不等于沿提前

`clk_gen.v:20/25/28` 三个 `CLKOUT*_PHASE` 现在都是 `(0.0)`。这一条留在这里是为了防一个常见误读：把 `CLKOUTx_PHASE` 设成负值，直觉上像"把沿往前挪"，但 datasheet 层的实现是**相移累加到 VCO/输出分频器的内部计数上**，负值并不保证该输出相对输入的第一个沿提前，而且首个沿的建立过程与 `LOCKED` 之后的稳态不是一回事。所以"用负相位换 RGMII 捕获点"这类改法，必须用布线后的报告复核实际到达时刻，不能按参数值推。⚠ 本仓我没找到做过这件事的实测件（`build/evidence/r109_clk01_before.txt` / `_after.txt` 那对文件确实存在，但里面没有 PHASE 相关的读数），所以这里只留机制说明，不给数字。

---

## 6 复位与 CDC

**结论：复位树上有一条组合等式跨着两个域，CDC 的正确性靠结构与属性保证，`ASYNC_REG` 这类"改了标签"的动作必须用网表计数量它到底动没动。**

### 6.1 复位树

`pl_video_top.v:132` 一句：

```verilog
wire rst_pix_n = sys_rst_n & locked;
```

`locked` 是 MMCM 的 `LOCKED`（`clk_gen.v:50`），`sys_rst_n` 名义上是上电复位计数器（`rk_zynq7020.xdc:51-54` 那段注释在解释 `eth_rst_n` 时顺带确认它是"由上电复位计数器驱动"的输出）。但**在当前位流里 `sys_rst_n` 是个常量**：`system_top.v:260` 给 `u_pl` 接的是 `.sys_rst_n(1'b1)`（同一处 `:261` 才把 `.axi_clk(fclk0), .axi_rst_n(fclk0_rst_n)` 接上）。于是 `rst_pix_n = sys_rst_n & locked ≡ 1'b1 & locked ≡ locked`（`pl_video_top.v:132`）。这条读法有两个后果，都不写在注释里就看不见：

1. 像素域的复位**实际只由 MMCM 锁定状态承载**，上电复位计数器对像素域没有任何作用；那句 `&` 是结构上的空操作。同理 `system_top.v:122` 给 idelay 那台 MMCM 的 `rst_n` 也接 `1'b1`，于是 `clk_gen.v:49` `.RST(~rst_n)` 恒为 0，那台 MMCM 永不主动复位。
2. `locked` 是异步源，`rst_pix_n` 又是组合复位，被 `pl_video_top.v` 里几十个 `always @(posedge clk_pix or negedge rst_pix_n)` 当异步低有效复位用（`:213`、`:255`、`:304`、`:359`、`:472`…）。"locked 释放的那一拍与 `clk_pix` 的关系"没有任何约束声明——它靠的是"复位释放本来就该当异步事件处理"这一约定。读 slack 时看不到它，不代表它安全。

AXI 侧另走一路：`system_top.v:83` `.FCLK_RESET0_N(fclk0_rst_n)` → `:261` `.axi_rst_n(fclk0_rst_n)`，与 `rst_pix_n` 无交集。同步链一律用 `async rst` + 各自的 `rst_n`，见 `dc_fifo.v:50`、`:70`、`:82`、`:89` 四个 always 块分别挂在 `wr_clk`/`rd_clk` 上。

还有一条更狠的：**有的复位分支永远走不到**。`snap_cross.v:21-24` 记的就是这一处——顶层把 `sys_rst_n` 绑成常量 `1'b1`（就是本节开头 `system_top.v:260` 那一句），于是 `if (!dst_rst_n)` 永远不执行 ⇒ 上电值只由位流里的 INIT 承载。修法：`snap_cross.v:29` `output reg hb_gone = 1'b1,` ——把"声明初值"写成与复位分支想要的同一个值。它同时给出这条纪律的边界（`:27-28`）：`pl_demo_top` **不在当前位流里**（正式构建的是 `system_top`），所以这一处对名册与 WNS 是无感的，**不能拿来当收益讲**。

⚠ 顺带一条与本文件主题完全一致的观察：`snap_cross.v:22` 把那条死复位指为 `system_top.v:250`，而现版 `system_top.v` 的 250 行是片源仲裁的注释。现版里 `snap_cross` 挂在 `pl_video_top` 下（`pl_video_top.v:51`、`:53` 说明 19 位一起过同一条 `snap_cross`），`u_pl` 的 `sys_rst_n` 就是 `system_top.v:260` 那个 `1'b1`；注释原指的 `pl_demo_top` 只在 PL-only 短路径里当顶层（`build_pl_full.tcl:23`），不在交付位流里。**行号引用会过期，机制引用不会**——这正是 §5 那条"读任何 slack 前先按名字复核"用在文档上。

### 6.2 `dc_fifo` 的灰码链与 `ASYNC_REG`：怎么验"标签真的动了"

结构在 `dc_fifo.v`：`:29-32` 的 `bin2gray` 函数，`:47` 满判据只用灰码（`{~rgray_s1[ADDR_W:ADDR_W-1], rgray_s1[ADDR_W-2:0]}`），`:68` 空判据 `rd_empty = (rgray == wgray_s1)`，`:82-95` 两个 always 块各在**对方**时钟域把灰码打两拍（`s0 → s1`）。二进制指针永不跨域（`:50-57` 在 `wr_clk`、`:70-79` 在 `rd_clk`，各自只在自己的域推进）。

标签在 `:27`：

```verilog
(* ASYNC_REG = "TRUE" *) reg [ADDR_W:0] wgray_s0, wgray_s1, rgray_s0, rgray_s1;
```

`:23-26` 注释写清了为什么是四颗一起标（含同域的 `s0`）以及尺子在哪：那把 ASYNC_REG 覆盖率扫描尺子没随包留下，改前 `A2 RED missing=2`，件 它的扫描输出也没随包留下。

改完之后的读数在 `build/evidence/r114_async_reg_post.txt`，一共 9 行，每行都是一个可核对的计数：

```
SYNCREG src/eth/... dc_fifo.v :86  rgray_s0 (wr_clk) <- rgray   (rd_clk) MARKED
SYNCREG ...         dc_fifo.v :93  wgray_s0 (rd_clk) <- wgray   (wr_clk) MARKED
SYNCREG-EDGE rd_clk -> wr_clk  pairs=1
SYNCREG-EDGE wr_clk -> rd_clk  pairs=1
SYNCREG A1_scope  cross_domain_pairs=2  want>=2 GREEN
SYNCREG A2_all_marked missing=0  want=0 GREEN
SYNCREG A3_no_ghost   ghost=0    want=0 GREEN
SYNCREG-SUMMARY root=src/rtl pairs=2 missing=0 ghosts=0 edges=2 result=GREEN
```

**"计数从 0 变到 N"这种验法的完整形态要三段**：改前的 RED 计数（`missing=2`）、改后的 GREEN 计数（`missing=0`、`pairs=2`）、以及一条防假绿的 `A3_no_ghost ghost=0`（只标了属性但根本没跨域的"幽灵同步器"必须是 0，否则 `missing` 会因为范围算错而虚降）。这里的 N=2 是**跨域对**的条数，不是寄存器个数——别把 4 颗寄存器念成 4 对。

反面证据也要看：改前的网表探针 `build/evidence/r114_async_netlist_pre_console.txt` 列出的 6 行 `FFLINE cell=u_eth/u_cdc/rgray_reg[...] ref=FDCE ASYNC_REG=` 属性**全是空**（`:75-80`），而同一个文件里 `ALT_LOOKUP s0_reg_style=28 s1_reg_style=28`（尾部）说明按 `*s0_reg*` 这种通配去捞，能捞到 28 颗——不是只有那 4 颗。结论：**属性有没有生效要按确切 cell 名读，不能用通配计数**，通配会连带捞进别的域的同名寄存器。

### 6.3 `snap_cross`：准静态总线 + 沿捕获

`dc_fifo` 是流式跨域，`snap_cross.v` 是另一套路子，`ddr_bank_commit` 用同一个形状（`:2`）。机制三件：

- 源域整拍写好宽总线、同拍翻转 `bus_tog`；目的域 `:36-37` 两颗 `(* ASYNC_REG = "TRUE" *) reg [2:0] ts / hs` 各打三级，`:45-46` 用 `ts[2]^ts[1]`、`hs[2]^hs[1]` 出边沿。
- `:5-7` 给了为什么敢这么采：边沿要 3 级同步才到目的域，而源总线至少保持到下一次写入（本项目 ≥1 ms），所以采到的必是完整值。
- 心跳分两条判据（`:58-65`）：`hb_slow <= (to_cnt < FAST_ENOUGH)` 与 `hb_gone <= 1'b1` 分开，因为**时钟退化 ≠ 时钟停**。`:6-7` 特别标了方向：源时钟变慢 ⇒ 目的域量到的心跳间隔**变长**（不是变短）；RTL821 断链时不停供 RXC 而是把它拉到约 1/48，所以只测"心跳有没有停"永远不触发 `hb_gone`。`DST_HZ 25_175_000` / `HB_TO_MS 100` / `SLOW_MS 5`（`:10-12`）把 `FAST_ENOUGH` 定成 1 ms 与 ~50 ms 的分界（`:34` 注释给的是 5×/10× 余量）。

### 6.4 CDC / 时序检查报告怎么读

四类件，四种读法：

| 报告 | 它给什么 | 读法与陷阱 |
| --- | --- | --- |
| `check_timing -verbose` → `build/check_timing_verbose.rpt` | 只**计数**：12 个桶，本设计是 `no_clock (0)`、`unconstrained_internal_endpoints (0)`、`no_input_delay (7)`、`no_output_delay (12)`，其余 8 个桶 0（`:18-29`） | 括号里的数与正文条数**单位不同**（见下条）。`check_timing` 不产生任何 slack，它只回答"有没有东西没被约束" |
| `report_methodology` → `build/report/methodology.rpt` | SUMMARY 表 + 明细。表头 `Checks found: 446`（`:26`） | 数只能从 SUMMARY 表读，而且要能加总：`DPIR-1 2 + LUTAR-1 1 + SYNTH-5 336 + SYNTH-6 98 + TIMING-9 1 + TIMING-10 1 + TIMING-18 7 = 446`（`:30-36`）。加不平就是口径错了或表被截了 |
| `report_cdc` → `build/report/cdc.rpt` | 域对表：`Severity / Source Clock / Destination Clock / CDC Type / Endpoints / Safe / Unsafe / Unknown / No ASYNC_REG` | 只有 `eth_rxc→clk_fpga_0 271 端点 Safe=271 Unsafe=0`、`clk_fpga_0→clkout0_1 103 端点 Unsafe=1 No ASYNC_REG=2` 这种**聚合计数**，不点名信号。`pl_video_top.v:480-481` 就把这条限制写在注释里："这份报告不点名信号 ⇒ 它只能证明这一类端点变少了，逐信号的凭据要写台架" |
| `report_timing_summary` | setup/hold/pulse 三类 WNS | 见 §2 与 §4：先确认这一档到底有没有被检查，再谈数 |

单位陷阱这一段值得单独立出来，因为 `build/tcl/probe_io_timing_names.tcl:3-8` 就是为它写的。原话：`check_timing` 在同一件事上给了两个不同单位的数——段标题 `checking no_output_delay (12)` 数的是 **pin**，正文 `There are 6 ports with no output delay specified` 数的是 **port**，而且它从不点名是哪 6 个。于是那个探针把 `check_timing -verbose` 与 `report_methodology -checks {TIMING-18}`（`build/tcl/probe_io_timing_names.tcl:68`）两路各扫一遍，逐 pin 打印 `IONAMES|check=no_output_delay|pin=$tok`（`:58`，`$tok` 就是端口名），让"哪一个"可核。本仓现在的 `no_output_delay` 明细正是 6 个端口（`check_timing_verbose.rpt:73-78`：`led[0]`、`led[1]`、`tmds_clk_p`、`tmds_data_p[0..2]`），另有 6 个"无输出延迟但有 false path"（`:82-87`），12 = 6 + 6 才对得上段标题。

---

## 7 I/O 约束的欠账：写成公开的限制，不是修掉的 bug

**结论：本设计有一族 I/O 端点从来没被检查过，这件事在交付物里是公开的限制。两份候选件（`r116_rgmii_input_window.xdc`、`r119_hdmi_source_window.xdc`）都试过、都量了、都没进默认构建，而且"为什么没进"是两种不同的理由。**

### 7.1 欠账的账面

`check_timing` 只计数（§6.4），点名要靠 `build/evidence/r113_io_debt.txt`——它逐端口打 `IODEBT-PORT <名> <方向> bits=<n> <分类>`，分类取 `PS_INTERNAL / CLOCK_SRC / FALSEPATH / BARE`。BARE 名单（即"无窗"）：`led`(2 bits)、`tmds_clk_p`、`tmds_clk_n`、`tmds_data_p`(3)、`tmds_data_n`(3)、`eth_rx_ctl`、`eth_rxd`(4)、`eth_mdc`、`eth_mdio`（`:25-37`）。这与 `check_timing_verbose.rpt` 的 5 个 HIGH 输入（`:57-61`：`eth_rx_ctl`、`eth_rxd[0..3]`）与 6 个 HIGH 输出（`:73-78`）能对上，而且解释了为什么总数是"5 个输入"而不是"9 个 BARE 输入位"。

### 7.2 那 5 个 RGMII 输入：约束是对的，但这一族在合法档内关不掉

`build/tcl/build_system_axigpio.tcl:40-56` 记了全过程，四条都是事实不是评价：

- 数字有出处：RTL8211F-CG 规格书 Table 60 发射端两行 + 原理图 strap ⇒ min 1.200 / max 2.800（`:49`）。
- 绑上之后，仓库自己的发布门禁 `build/gates.sh` 有 4 项机械判红（WNS ≥ 0、失败 setup 端点 == 0、WHS ≥ 0、失败 hold 端点 == 0），而它末尾写死"有红项 ⇒ 不采纳，保留上一版"（`:45-48`）。
- 关不掉的原因是一个区间不相交：hold 要 τ ≥ 44.8、setup 要 τ ≤ 21.8，根因是两只钟的角间差 3.411 ns 对上数据 0.467 ns（`:50-52`，该文点名 `report/timing/rgmii_window_model.md` §7.5 与 `report/timing/limit_audit_r116.md`）。
- 所以默认**不加载**，留在仓里当候选件 + 全份证明；复现只要 `VP_R116_IO_WINDOW=1`。原文一句定性（`:55`）："撤销的不是约束的正确性，是把它带进发布物这个动作。"

### 7.3 TMDS 那 6 个输出：先把"该引哪本规范"搞对

`tmds_clk_p/_n`、`tmds_data_p[0..2]/_n` 是本工程（Source）的**输出脚**，所以对应 HDMI 源端合规里 **TP1** 那一组量，不是 Sink 侧 **TP2** 的接收窗；也不能拿 UG471 的数——`r119_hdmi_source_window.xdc:15-16` 写得很干脆：**UG471 只有 TMDS_33 的电气属性，没有窗时间**。这个方向是 2026-10-04 才被指出来纠正的，此前记成"要面板/接收端的窗口数"。

窗宽只有一个来源：《HDMI Specification 1.4》§4.2.4 Table 4-24 "Source AC Characteristics at TP1" 的 `Inter-Pair Skew at Source Connector, max = 0.20 Tcharacter`（同表在 1.3 Table 4-16 / 1.1 Table 4-13 逐字一致；`:19-22`）。当前档 Tcharacter = 像素周期 = 1/50 MHz = 20.000 ns（`:23-25`）⇒ **半窗 = 0.20 × 20.000 = 4.000 ns**，写成 `set_output_delay -clock clkout1_1 -max 4.000 / -min -4.000`（`:51-52`）。参考钟身份不是猜的：四条串行器的 CLK 脚在实现网表里同属 `clkout1_1`，件 `build/evidence/r119_ser_clock_probe.txt`（`:29-32`），且 `report_clock_networks` 只列 3 条主钟，所以"用哪条钟做参考"必须由 pin 反查。

### 7.4 负 slack 来自量纲，不是来自设计

`0.20 Tcharacter` 是**互对偏斜的上限**（各对之间最多差多少），是一个展开量；它不是"数据必须在钟沿前后 ±4 ns 内被捕获"的那种窗口。把它当捕获窗写进 `set_output_delay`，参考钟又取了片内 250 MHz 串行器钟 `clkout1_1`（周期 4.000 ns），量纲就错了：拿 4 ns 的钟当 20 ns 周期的参考，等于把窗口压缩成 1/5（`r119b_hdmi_tp1_pinclk.xdc:7-10` 原话）。两次读数都在仓里：

- 只读探针：load 之前 4 个端口的 `Path Group` 全是 `(none)`，load 之后 3 条数据道变成 `Path Group: clkout1_1`、`Requirement: 4.000ns`、`Slack (VIOLATED): -3.482 / -3.458 / -3.474 ns`（`r119b_hdmi_tp1_pinclk.xdc:4-7`，件 `build/evidence/r119_xdc_loads_probe3.txt`）。约束确实挂上了，错的是参考量纲——这两件事能同时成立，只有把"生效了吗"和"合理吗"分开查才看得见。
- 带窗完整构建：`clkout1_1` 那一行从 §2.5 的空白变成 **WNS −5.408 / 6 个 setup 违例端点、WHS −1.923 / 6 个 hold 违例端点**（`build/evidence/1006d_tmdswindow_timing_summary.rpt:189`），并把设计级 WNS 拉到 −5.408、失败 setup 端点 6、端点总数从 51135 变 51141（`:153`）。这同时回答 §2.5：**这一档本来 0 个 setup/hold 端点，是新增的 I/O 窗创造了 6 个被检查的端点**——"没数"与"有数并且红"是同一件事的两个射程。

`r119b` 的第二版把参考钟改挂在 `tmds_clk_p` 脚上（`:24` `create_clock -name r119b_tmclk -period 20.000`），窗宽仍用 4.000 ns；它自我定位是"探针输入，不进任何构建"，并在 `:20-22` 如实留了一个未决问题：`create_clock` 打在输出脚上得到的是外部参考钟，与片内启动钟 `clkout1_1` 之间没有声明的时序关系，工具会不会因此根本不产生到数据道的路径，"由探针实测回答，这里不预判结论"。

### 7.5 三条不能抵的账

1. **TP1 的真判据不在 SDC 语义里。** 眼图掩模 + 抖动 / 占空比 / 上升下降 / 对内偏斜，`set_output_delay` 只约束沿的到达时刻（`r119_hdmi_source_window.xdc:41-43`）。换成同量纲的问法（已布线成品逐脚 clock-to-pin 到达离散）判 10 项未通过 0（件 `build/evidence/r119_window_check.txt`，转述自 `timing/02-how-this-project-did-it.md:773`），但那两笔新欠账——板级走线/连接器离散、眼图/抖动/占空比/沿——不能拿"窗已过"来抵（同处原话）。
2. **`led[0]`/`led[1]` 没有可引用的对外窗。** LVCMOS33 直驱 LED（`rk_zynq7020.xdc:10-11`），HDMI 连接器引脚表里没有这类信号；要给它们"不查"的定性属于一次放宽，必须先进放宽账本，而 `r119_hdmi_source_window.xdc:45-47` 当时写的是"当前账本仍 0 条"，所以那份文件不替它们写任何窗。
3. **新增约束必须先过一轮"量名册"。** `build/tcl/build_system_axigpio.tcl:70`：新增约束必须先用一轮构建量名册（别域不许变差），量过之前带进发布物就是用声明代替测量。这一条与 §5 是同一件事的两面。

---

## 8 一份能照抄的约束自检清单

| # | 命令 / grep 目标 | 它判什么 |
| --- | --- | --- |
| 1 | `grep -n "add_files -fileset constrs_1" build/tcl/*.tcl` | 真正被加载的是哪几份 .xdc，以及有没有环境变量开关绕开默认路径（§1） |
| 2 | 同批脚本里 `grep -n "used_in_synthesis\|used_in_implementation"` | 哪些约束只在实现阶段生效——综合阶段的读数不能拿它解释 |
| 3 | `grep -n "^set_clock_uncertainty" src/constraints/*.xdc` | 不确定度射程：几条、命中哪个对象、有没有 setup 侧的带子（§4） |
| 4 | `grep -n "get_clocks" src/constraints/*.xdc`，再与报告 Clock Summary 逐名核验 | 写死的钟名在换钟 / 多加一个 MMCM 实例之后是否还命中（§5） |
| 5 | `grep -n "include_generated_clocks" src/constraints/*.xdc` | 生成钟有没有被抓进父钟所在组；少了它历史上是 WNS≈−6.7 的假违例（`clock_groups_impl.xdc:14-17`） |
| 6 | Intra Clock Table 逐档确认 WNS/WHS 单元格**有没有值** | 区分"检查过了并且过"与"根本没被检查"（`NA` / 空白格，§2.5） |
| 7 | Inter Clock Table 与 Other Path Groups Table 的行数 | 异步组声明后跨域路不再被计时。本仓 2 行（`timing_summary.rpt:198-199`）、Other Path Groups 空表（`:207-208`）；行数无故变 0 通常是约束失效而非设计变好 |
| 8 | `check_timing -verbose` 的 12 个桶计数 | 只判"有没有没被约束的东西"，不给 slack。桶标题与正文条数单位不同（pin vs port），别当同一个数（§6.4） |
| 9 | `report_methodology` 的 `Checks found` 与 SUMMARY 表逐行加总 | 加不平就是口径错或表被截。本仓 2+1+336+98+1+1+7 = 446（`methodology.rpt:26-36`） |
| 10 | `report_cdc` 的 `Unsafe / Unknown / No ASYNC_REG` 三列 | 逐域对找结构缺口；它不点名信号，逐信号凭据要另写尺子（`pl_video_top.v:480-481`） |
| 11 | `report_clock_networks` / `report_utilization -clock` 看每棵钟的负载数 | 钟在跑不代表被检查；负载为 0 的那棵就是射程空白（`clock_util.rpt:63` 对照 `:60`） |
| 12 | 网表里按**确切 cell 名**读 `ASYNC_REG` 属性（`get_property ASYNC_REG`） | 属性是否真落到跨域那几颗上；通配计数会连带捞进同名不同域的寄存器（§6.2） |

一句收口：这 12 条里没有一条是"看 WNS 是不是正数"。WNS 为正是结果；前 11 条判的是**这份结果是在什么射程下得到的**。射程没复核之前，slack 读数不属于这份设计，属于那份约束。
