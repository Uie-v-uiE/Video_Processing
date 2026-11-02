# clocking-and-reset.md · 时钟域与复位结构

读完这篇你能回答哪三个问题：

1. 这颗器件上一共有几颗时钟在跑，每一颗**谁产生、谁消费、约束写在哪一行**？
2. 复位有几条、哪一条其实是"死支路"，死支路逼出了哪些写法？
3. 全工程的跨域点一共有哪些，每处用的是三种形态里的哪一种，为什么是那种？

## 目录

- 第 1 节 时钟清单（产生者 / 消费者 / 约束出处）
- 第 2 节 复位清单与那条死支路
- 第 3 节 跨域点全表
- 第 4 节 三种跨域形态（五层阶梯）
- 第 5 节 约束为什么按时机拆两个文件（"约束悄悄不生效"的观察点）
- 第 6 节 辨认方法：拿到一份报告怎么认出这些结构
- 第 7 节 小结与下一步
- 第 8 节 自测题

## 第 1 节 时钟清单

| 时钟 | 频率 | 谁产生 | 谁消费 | 约束出处 |
|---|---|---|---|---|
| `sys_clk` | 50 MHz 输入（周期 20.000 ns） | 板载晶振，管脚 W17 | 上电计数器（`src/rtl/top/system_top.v:109`）、两只 MMCM（`src/rtl/top/system_top.v:121`、`src/rtl/top/pl_video_top.v:128`）、按键消抖与长按（`src/rtl/top/pl_video_top.v:136`、`:139`、`:148`）、角度机（`src/rtl/top/pl_video_top.v:183`）、心跳 LED（`src/rtl/top/pl_video_top.v:1034-1036`） | `src/constraints/rk_zynq7020.xdc:5-6` |
| `clk_pix`（报告里叫 `clkout0_1`） | 50 MHz | `clk_gen` 的 MMCM CLKOUT0（`src/rtl/clocks/clk_gen.v:21`） | 整条像素链：栅格 `u_t`、几何 `u_zmap`、读口 `u_bilin`、效果链 `u_pipe`、缝 `u_split`、OSD `u_osd`（`src/rtl/top/pl_video_top.v:226`、`:343`、`:732`、`:800`、`:911`、`:999`） | 不单独 `create_clock`，随 `sys_clk` 的生成钟被收进同一组（`src/constraints/clock_groups_impl.xdc:31`） |
| `clk_pix5x`（`clkout1_1`） | 250 MHz | 同一 MMCM 的 CLKOUT1（`src/rtl/clocks/clk_gen.v:24`） | TMDS 并串转换 `u_dvi`（`src/rtl/top/pl_video_top.v:1026`） | 同上，与 `clk_pix` **有意留在同一组**（`src/constraints/clock_groups_impl.xdc:25-26`） |
| `clk_200m`（`clkout2`） | 200 MHz | `u_clk` 的 CLKOUT2（`src/rtl/clocks/clk_gen.v:27`）与第二只 MMCM `u_idelay_clkgen`（`src/rtl/top/system_top.v:121-125`） | 只有收包子系统用它做 IDELAY 参考（`src/rtl/eth/rgmii_rx.v:59-63`）；`u_pl` 里那一路是**故意不接**的（`src/rtl/top/pl_video_top.v:127`） | 无独立约束 |
| `fclk0`（报告里叫 `clk_fpga_0`） | 100 MHz | PS7 的 FCLK_CLK0，频率在 BD 里配（`build/tcl/build_system_axigpio.tcl:67`） | 全部 AXI 事务与两台搬运机（`src/rtl/top/system_top.v:177`、`:261`）、`u_arb`、`u_lat`（`src/rtl/top/pl_video_top.v:421`、`:624`） | 由 PS7 IP 自己的 XDC 创建，所以约束文件里 `get_clocks` 在综合阶段取不到它（`src/constraints/rk_zynq7020.xdc:64-70`） |
| `eth_rxc` | 125 MHz 输入（周期 8.000 ns） | PHY 恢复出来的接收时钟，管脚 Y19 | 整个收包链：IDDR、FCS、解析、重组、`u_lm`、`u_cdc` 写侧（`src/rtl/eth/eth_udp_video_top.v:73`、`:186`、`:197`、`:235`、`:284`、`:298`） | `src/constraints/rk_zynq7020.xdc:20`、`:36`；hold 那一条额外不确定度在 `:50` |
| `eth_tx_clk` | 125 MHz **输出** | PL 送给 PHY 的发送时钟：`u_rgmii` 把 `gmii_tx_clk` 直接等于 `gmii_rx_clk`（`src/rtl/eth/gmii_to_rgmii.v:25`） | 片外 PHY | 管脚约束 `src/constraints/rk_zynq7020.xdc:26`，时序上被豁免 `:56` |

**七行、六个域。** 三个"看起来该独立、其实不独立"的点，逐个说明：

- `gmii_tx_clk` 与 `gmii_rx_clk` 是**同一根**：RGMII 只有 RXC/TXC 两根时钟，所以整个 ETH 逻辑是单域
  （`src/rtl/eth/eth_udp_video_top.v:5-6` 的声明、`src/rtl/eth/gmii_to_rgmii.v:1-3` 的实现）。
- `clk_pix` 与 `clk_pix5x` 同 MMCM、5:1、0° 相位，故意不做异步处理，让它们按同步路径被检查
  （`src/constraints/clock_groups_impl.xdc:25-26`）。
- `sys_clk` 与 `clk_pix` 同频不同树：`angle` 那 9 位从 `sys_clk` 域进 `clk_pix` 域的几何，被工具按**同一时钟组内**
  的路径做时序分析 —— 组内声明见 `src/constraints/clock_groups_impl.xdc:31`，实测的跨这两个名的路径见
  `report/timing_global.md` 第 2 节表里"跨域 `sys_clk↔clkout0_1`"那一行（231/19 个端点，其中一条含 DSP48E1 的 15 级路）。

小结 1：数时钟的正确方式是"数域"，本设计是 6 个域：`sys_clk`、MMCM 生成家族、`fclk0`、`eth_rxc`、TMDS 的 5x、200 MHz 参考。
小结 2：每一颗都能说出产生者与消费者，这一栏就是 W10 要的账。下一步：复位。

## 第 2 节 复位清单与那条死支路

| 复位 | 谁产生 | 极性 | 谁用它 |
|---|---|---|---|
| `fclk0_rst_n` | PS7 的 `FCLK_RESET0_N`（`src/rtl/top/system_top.v:83`），BD 里标成低有效（`build/tcl/build_system_axigpio.tcl:178-179`） | 低有效 | 所有 AXI 侧逻辑（`src/rtl/top/system_top.v:177`、`:261`） |
| `eth_rst_n` | 顶层那 24 位上电计数器：`phy_rst_cnt` 计到顶才置 1（`src/rtl/top/system_top.v:108-112`） | 低有效 | `u_eth` 的复位与 MMCM 锁定相与（`src/rtl/top/system_top.v:175`） |
| `rst_pix_n` | `sys_rst_n & locked`，`locked` 是 MMCM 的 LOCKED 输出（`src/rtl/top/pl_video_top.v:130-132`，元件在 `src/rtl/clocks/clk_gen.v:50`） | 低有效 | 整条像素链与所有像素域同步器 |
| `sys_rst_n` | **顶层恒接 `1'b1`**（`src/rtl/top/system_top.v:260`） | — | 见下面这段 |

`sys_rst_n = 1'b1` 这一条是本项目最值得读的一处"结构决定写法"：这一域的复位支路**永远走不到**，
于是所有 `if (!rst_n)` 都成了死代码，上电值只能由位流里的 FF 初值承载。这件事在两个地方被具体处理：

- `src/rtl/util/key_debounce.v:10-17`：因为复位支路走不到，寄存器 `key_stable` 的上电值必须由**声明初值**给出
  （写法在 `src/rtl/util/key_debounce.v:25`、`:30-31`），否则上电白送一次"松手"事件。
- `src/rtl/eth/snap_cross.v:20-26`：同一个道理用在 `hb_gone` 上，声明初值 `= 1'b1`（`:29`）。
  那里的注释明确写了这条改动**对当前位流无感**：`pl_demo_top` 不在正式构建的树里
  （构建收的顶层是 `system_top`，`build/tcl/build_system_axigpio.tcl:258`），所以不许把它讲成时序收益。

还有一条与复位有关的现象值得单独记：`src/rtl/eth/snap_cross.v:20-24` 说"复位摘掉之后，上电值只由位流承载"，
这就是为什么本项目要专门有一把尺子去扫**死复位下的初值**（脚本与判据点名为 `build/scan_dead_reset_init.py`，
出处同上）。

小结 1：本工程的复位是"三条真复位 + 一条名义复位"，名义那条把责任推给了声明初值。
小结 2：读任何一段 `if (!rst_n)` 之前先问"这一域的 rst_n 是真信号还是常量 1"，答案决定这段代码到底会不会执行。下一步：跨域点。

## 第 3 节 跨域点全表

按方向列。每行给出**位宽**与**用的形态**（形态编号在第 4 节解释）。

| # | 信号 | 位宽 | 方向 | 形态 | 代码位置 |
|---|---|---|---|---|---|
| 1 | 视频流（地址 + 数据 + flush 标记） | 36 | `eth_rxc → fclk0` | 格雷码异步 FIFO | `src/rtl/eth/eth_udp_video_top.v:298`，机制在 `src/rtl/eth/dc_fifo.v:68`、`:82-95` |
| 2 | `frame_done` | 1 | `eth_rxc → fclk0` | 翻转位 + 3 级 + 异拍 | `src/rtl/eth/ddr_bank_commit.v:37-47` |
| 3 | 健康快照 `lm_bus` | 320 | `eth_rxc → fclk0` | 准静态总线 + 心跳 | `src/rtl/top/system_top.v:214`，机制在 `src/rtl/eth/snap_cross.v:36-46`、`:69-72` |
| 4 | `gapclr_sel`（准静态控制电平） | 1 | `fclk0 → eth_rxc` | 3 级电平同步 | `src/rtl/eth/eth_udp_video_top.v:277-281` |
| 5 | 消隐窗口 `allow_copy_axi` | 1 | `clk_pix → fclk0` | 3 级电平同步 | `src/rtl/video/frame_commit_lock.v:71-76` |
| 6 | 场同步沿 `blank_tog` | 1 | `clk_pix → fclk0` | 翻转位 + 3 级 + 异拍 | `src/rtl/video/frame_commit_lock.v:59-69` |
| 7 | `frame_ready_pix` | 1 | `fclk0 → clk_pix` | 翻转位 + 3 级 + 异拍 | `src/rtl/video/frame_commit_lock.v:126-145` |
| 8 | `copy_abort`（1 拍脉冲） | 1 | `fclk0 → clk_pix` | **必须**翻转位，不许电平同步 | `src/rtl/video/frame_commit_lock.v:100-109`、消费在 `src/rtl/top/pl_video_top.v:484-489` |
| 9 | 19 位几何控制字 | 19 | `fclk0 → clk_pix` | 准静态总线 + 心跳（`snap_cross`） | 发射在 `src/rtl/top/pl_video_top.v:865-875`，跨域在 `:876-880` |
| 10 | 20 位像素域缩放状态 | 20 | `clk_pix → fclk0` | 帧首准静态快照 + `snap_cross` | `src/rtl/top/pl_video_top.v:652-658`、`:674-678` |
| 11 | 18 位时延（ms + 两位状态） | 18 | `fclk0 → clk_pix` | 准静态总线 + 独立心跳 | `src/rtl/top/pl_video_top.v:975-985` |
| 12 | `ps_publish`（PS 发布翻转位） | 1 | `fclk0 → clk_pix` | 翻转位 + 3 级 + 异拍 | `src/rtl/util/ps_publish.v:18-25`，发射在 `src/ps/main.c:242-251` |
| 13 | 显示帧起始 `sof_tgl` / `fs_tog` / `z_hb_tog` / `rot_fs_tog` | 各 1 | `clk_pix → fclk0` 或 `clk_pix → sys_clk` | 翻转位 | `src/rtl/top/pl_video_top.v:607-611`、`:568-572`、`:665-669`、`:304-314`；角度那一路在 `src/rtl/process/rotate/angle_ctrl.v:24-29` |
| 14 | 准静态控制电平：`zoom_en`、`bilin_en_axi`、`osd_off_axi`、`src_sel`、`owner_eth`、`eth_link`、`eth_live` | 各 1 | `fclk0 → clk_pix` | 3 级电平同步（各自**独立**一条链） | `src/rtl/top/pl_video_top.v:212-221`、`:254-261`、`:267-274`、`:471-475`、`:491-496`、`:502-507`、`:517-522` |
| 15 | 多位控制字（效果九位、阈值、gamma 窗口、缩放档） | 9/8/32/3/1 | `fclk0 → clk_pix` | `effect_ctrl` 内部一条 sel 链 | 顶层例化在 `src/rtl/top/pl_video_top.v:198-210`，链本体 `src/rtl/process/effect_ctrl.v` |
| 16 | 仲裁模式 `mode` | 2（格雷码） | `clk_pix → fclk0` | 3 级电平同步 + 格雷码编码 | `src/rtl/top/pl_video_top.v:165-169`，格雷码的理由在 `src/rtl/util/src_mode.v:19-24` |

表里三处"为什么不合并"的注释是这套结构的全部学费：
`src/rtl/top/pl_video_top.v:283-284`、`:661-664`、`:971-974` 三段讲的是同一件事 ——
一个发射触发器扇出到**两组**目的域同步器会被工具的 CDC 检查提级，本仓库为此红过两次。
`src/rtl/util/src_mode.v:40-44` 补了另一半：同步器前面不许挂组合逻辑，否则会被判成未受保护的采样点。

小结 1：16 条跨域路径：6 条走翻转位（第 2、6、7、8、12、13 行）、5 条走电平三级（4、5、14、15、16）、
4 条走总线 + 心跳（3、9、10、11）、1 条走格雷码异步 FIFO（1）。
小结 2：判断"这根线要不要跨"的准绳是**它属于哪个域、被谁采样**，不是它从哪个模块来。下一步：为什么只有这三种形态。

## 第 4 节 三种跨域形态（五层阶梯）

### 4.1 电平型三级同步（形态"3 级电平同步"）

1. **零术语版**：让一个"现在是开还是关"的开关，先被新时钟连续看三次，看完才用。
   *简化说法，会在"这个开关其实只是一拍亮一下"的情形下误导你 —— 那一拍会被整个吃掉，精确版见 4.2。*
2. **不这么用会看到什么**：`src/rtl/top/pl_video_top.v:478-479` 记的就是这个现象的历史：同一个文件里
   `eth_link` 被裸采样了 4 处、`src_sel` 走了三级同步，一处对一处错，工具的 CDC 报告里那一类端点数
   从 84 掉到 51、被标记的从 16 掉到 1（同段注释）。
3. **精确定义**：源域寄存器 → 目的域两级以上串联触发器 → 从最后一级取值。本项目的实际取值是**三级**
   （`src/rtl/top/pl_video_top.v:491-496` 等六处），并且给这几级打上工具的异步寄存器属性
   （`src/rtl/eth/dc_fifo.v:23-27` 说明了为什么要打：不打，工具会把它们当普通寄存器挪位、复制、拆开）。
4. **它不是什么**：它不是"脉冲同步器"。区别在本工程一处能直接看出来：
   `src/rtl/video/frame_commit_lock.v:100-105` 明写"电平型 3 级同步在这里并不能修好它（实测与裸采逐相位一模一样）"。
5. **辨认方法**：打开文件搜 `(* ASYNC_REG = "TRUE" *)`，看到"一行里连写三个同名不同下标的 1 bit 寄存器 +
   移位赋值 `{a2,a1,a0} <= {a1,a0,in}`"（形状见 `src/rtl/top/pl_video_top.v:491-495`）就是它。

### 4.2 翻转位脉冲同步（形态"翻转位 + 3 级 + 异拍"）

1. **零术语版**：要传一个"发生了一次"的事件，就别传那根跳一下的线，改成"每发生一次就把一根线拧到反面"，
   对面看到这根线变了就知道发生了一次。
   *简化说法，会在"事件来得比对面看得快"的情形下误导你 —— 两次翻转会被并成 0 次，精确版是下一层那句。*
2. **不这么用会看到什么**：`src/rtl/eth/ddr_bank_commit.v:2-3` 与 `src/rtl/util/ps_publish.v:2-8` 都写了后果：
   脉冲跨域被吃掉 ⇒ 提交/发布这件事在对面根本不存在；`src/rtl/video/frame_commit_lock.v:26-28` 给了"两次 abort
   落进同一个像素周期被并成 0 次"的边界与它的规避条件（两次至少隔 `WD_CYC`）。
3. **精确定义**：源域 `if (evt) tgl <= ~tgl`；目的域三级移位 + 取后两级的异或，得到恰好一拍
   （形状：`src/rtl/eth/ddr_bank_commit.v:37-47`、`src/rtl/util/ps_publish.v:20-25`、
   `src/rtl/process/rotate/angle_ctrl.v:24-29`）。仓库技能卡把这条列成了动作清单：`skills/rtl/cdc-and-async-discipline/SKILL.md` 第 21-27 行那段最小形状。
4. **它不是什么**：它不是计数器，也不是握手。区别在本工程很具体：`ps_publish` 的语义是**电平**
   —— 连发两次只消费一次（`src/rtl/util/ps_publish.v:6-8` 就写明了这是有意的）。
5. **辨认方法**：搜 `^ reg.*tog` 或 `~tgl`、`<= ~` 那一类翻转赋值，再看目的域有没有 `x1 ^ x2`
   的三个异或点（`src/rtl/video/frame_commit_lock.v:69`、`src/rtl/eth/ddr_bank_commit.v:47`、
   `src/rtl/top/pl_video_top.v:489`、`:578`）。

### 4.3 准静态总线 + 跳变沿（形态"总线 + 心跳"，含格雷码 FIFO 那个特例）

1. **零术语版**：要一次传一整排数，就先让这排数**稳稳站住**，再拧一下"换新值"的小旗，
   对面看到小旗才抄一次，抄到的必然是整套新值。
   *简化说法，会在"这排数其实在对面看见小旗之前还在变"的情形下误导你 —— 那时抄到的就是半新一半旧，精确版是第 3 层那句契约。*
2. **不这么用会看到什么**：`src/rtl/top/pl_video_top.v:649` 那句写的是后果形态 ——
   "19 位各自打两拍 ⇒ 读到半新一半旧"；同一个病在 `src/rtl/top/system_top.v:224-226` 是另一种长相
   （位宽被吞导致模式高位静默丢掉）。
3. **精确定义**：源域把总线**整拍**写好、同拍翻转 `bus_tog`；目的域等同步过来的沿再采一次，
   并且要求总线至少保持到下一次写入（`src/rtl/eth/snap_cross.v:2-5` 就是这个契约的原文）。
   本项目两处实际取值：源域写入节流 32 个源周期（`src/rtl/eth/link_monitor.v:11`、`:165-166`），
   以及帧首才更新总线（`src/rtl/top/pl_video_top.v:652-658` 用 `zoom_snap`）。
   数据量再大、节奏更快时换形态：36 位视频流用格雷码指针的异步 FIFO（`src/rtl/eth/dc_fifo.v:35-47`）。
4. **它不是什么**：它不是"握手"（没有"对面收好了"的回线），所以只能用于**允许合并**的准静态值。
   这一条在本工程的落点是 `src/rtl/eth/link_monitor.v:168-170`：节流窗口里的事件被 `pend_ev` 记下来补发，
   否则一次 `frame_done` 会被整个丢掉 —— 也就是说这套总线**不承诺每一次都到**，承诺靠 `pend_ev` 额外买回来。
5. **辨认方法**：在报告里找时钟对；在本仓库的门禁输出里，CDC 那一项打印的就是"配对 + 端点数 + unsafe 数"
   三元组（`build/gates.sh:100`、`:196`）。看到一对时钟之间有 Critical 行，就去代码里找那一对上的
   `snap_cross`/`dc_fifo`/`ASYNC_REG` 三者之一；找不到就是真问题。

小结 1：三种形态的选择只由两个问题决定 —— "它是一拍还是一段时间"与"允许不允许合并"。
小结 2：本工程的 16 条路径全部能被这三形态覆盖，剩下的是"同一个模块里同时用了两种"。下一步：约束侧。

## 第 5 节 约束为什么按时机拆两个文件（"约束悄悄不生效"的观察点）

`src/constraints/rk_zynq7020.xdc` 里**故意不写**异步时钟组，改由实现阶段专用文件承担
（`src/constraints/clock_groups_impl.xdc:1-8`）。原因在本仓库是有实据的一条观察：

- `clk_fpga_0` 由 PS7 IP 自己的约束创建，综合阶段那个名字还不存在；
- 对取不到的对象用 `-quiet` 只能压住报错、**压不住命令本身**，于是整条 `set_clock_groups` 不生效，
  现场只留一条 `CRITICAL WARNING [Vivado 12-4739]`（原文记录：`src/constraints/rk_zynq7020.xdc:64-70`）；
- 约束文件里又不允许写控制流（`if` 会报 `[Designutils 20-1307]`，同文件 `:71-72`），
  所以唯一解法是"按时机分文件"，用 `used_in_synthesis false` 把它绑到实现阶段
  （`build/tcl/build_system_axigpio.tcl:24-26`）。

同一族病还有两件，都在同一个文件里能读到：

- 把一条只对**输出**端口有意义的 `set_false_path -from` 写在 `eth_rst_n` 上，结果是每次综合报一条
  "没有有效起点"的空约束（`src/constraints/rk_zynq7020.xdc:51-55`，那条现在写成 `-to`）。
- 同一条命令里混进一个取不到的时钟名，会连带把别的组一起废掉（`:43-45` 就是为这件事写的警告）。

**这三件合起来是本仓库对"约束覆盖会悄悄丢"的观察口径**：不是"某个地方没约束会红"，而是
"你以为绑上了、命令其实一行都没执行，而且只留一句 warning"。

小结 1：本工程的约束分两个文件不是洁癖，而是"综合阶段拿不到 PS 生成的那个时钟"这件事的直接后果。
小结 2：改端口名或改时钟名之后，要回头看综合日志里有没有 12-4739 / Constraints 18-513 这两类提示。下一步：第 6 节。

## 第 6 节 辨认方法：拿到一份报告怎么认出这些结构

| 想知道 | 打开 | 看哪一列/字段 | 出现什么就是它 |
|---|---|---|---|
| 有几颗时钟、各自频率与域 | `build/timing_summary.rpt` 的 Clock Summary 段（本仓库的门禁读法见 `build/gates.sh:279-292`） | Waveform Table / Period | 一行一个时钟名；`From==To` 的分组行说明它是域内 |
| 跨域配对有几条、危险不危险 | `build/cdc.rpt` | 行首 `Critical`、第 2/3 列是源/目的时钟、倒数第 5 与第 3 列 | 出现新的"源>目的"配对，或某配对的 unsafe 数变大 ⇒ 门禁判红（`build/gates.sh:118-141`） |
| 收口那一路是不是只有一棵时钟树 | `build/clock_util.rpt` | `BUFIO` 用量、`BUFG` 的驱动 | 本项目 r94 那一版的读数是 `BUFIO` 用量 0、`eth_rxc` 只经一只 BUFG（`board/ACCEPTANCE.md` 机器判据表第 10 条） |
| 某条 hold 余量是不是被自加的不确定度扣过 | `build/timing_summary.rpt` 里那条路径的 `clock uncertainty` 字段 | 有没有 0.800 那一行 | 全工程只有一处 `set_clock_uncertainty -hold 0.800`（`src/constraints/rk_zynq7020.xdc:50`），所以只有 `eth_rxc` 的 WHS 被扣过（口径见 `report/timing_global.md` 第 4 节"自加不确定度"那一行） |
| 某个"复位"是不是死支路 | 综合日志 + `build/scan_dead_reset_init.py`（尺子名取自 `src/rtl/eth/snap_cross.v:25`） | `Synth 8-7137` / 未复位寄存器清单 | 复位支路永远走不到、上电值只由 INIT 承载 ⇒ 就是这类 |

一句提醒：本表最后一行的**脚本名来自代码注释**，我本次没有运行过它 ⇒ 该读数按
`【未实测】` 处理，要用之前先自己确认盘上有没有那个脚本（`ls build/scan_dead_reset_init.py`）。

小结 1：辨认方法全部是"打开 X，看 Y 字段，出现 Z 就是它"，没有一条依赖感觉。
小结 2：这张表也是 `hands-on.md` 第 2、3 节实验的取材处。下一步：第 7 节。

## 第 7 节 小结与下一步

三句话：六个时钟域、七行清单；三条真复位 + 一条恒 1 的名义复位，后者逼出了"声明初值"这一族写法；
16 条跨域路径全部落在电平三级、翻转位、准静态总线（含格雷码 FIFO 特例）三种形态里，
而约束侧的两个文件拆分与两条 warning 的成因是同一件事的两面。
下一篇去 `one-pass-walk.md`：把这篇的结构放到一条真实数据的时间顺序里走一遍。

## 第 8 节 自测题

题目：**`copy_abort` 为什么不能用本工程里最常见的"三级电平同步"来跨？**
本文不给结论。要回答它，去查这两处的原文与台架名：`src/rtl/video/frame_commit_lock.v:100-109` 与
`src/rtl/top/pl_video_top.v:480-489`，再看相位扫描那支台架的名字出现在哪一行（提示：找 `tb_v79_abort_toggle`）。
