# 13 · 约束与时序收敛：工具看得见什么、这套代码量过什么、哪些刀被自己判负

> 这一章的射程：**工具眼里的时钟清单**（`build/clock_util.rpt`、`build/timing_summary.rpt`）、
> **每个约束文件负责什么以及为什么这样切**、两个环境门控候选
> （`VP_R116_IO_WINDOW` / `VP_R119_TMDS_WINDOW`）各自替谁还债、
> **输入窗的测量纪律**（IDELAY 抽头与 ns 的关系、τ=31 那条眼心扫描）、
> **逐时钟名册这套方法**（`build/roster_from_summary.sh`、`build/timing_roster_diff.sh`，
> 以及"全设计 WNS 的绝对差不算收益也不算损失"这条规矩），
> **I/O 覆盖率台账**（`build/check_io_timing_coverage.py` 的判据 I1–I9），
> 最后把**量过并拒绝**与**只是声明**两件事分开列成一张表。
>
> 读数版本：`build/timing_summary.rpt:5` 的文件头是 `Date : Sun Oct 4 04:37:30 2026`、
> `Design State : Routed`，`build/utilization.rpt:4`、`build/methodology.rpt`、`build/cdc.rpt` 同一批。
> 这一批对应板上 r118 那颗（`build/system.bit` 的 `cd04907e1369…`，
> `屏侧实测记录`）。正式构建会原地重写这几份，
> 所以每个数后面都跟着行号；`那一轮的逐轮页` 明确写着
> 部分过程件已随 `build/` 精简从盘上移除，因此凡是"只存在于文档里的读数"，
> 这一章都标成抄件而不是复量。
>
> 前置在第 00 章：setup/hold 两把尺、WNS/WHS/TNS、逻辑级数与布线占比、
> 时钟不确定度、DCD/SCD/CPR（`00-prerequisites.md` 第 7 节）。这一章不重讲定义，
> 只把定义换成这颗器件上的读数。

---

## 1. 时钟清单：工具看到的不是八只钟，是一棵树加一条线

### 1.1 八只 BUFG 与它们的负载

`build/clock_util.rpt:59-66` 这张表是读时序的第一眼，因为它同时给出钟名、周期、
驱动单元、站点与**负载数**：

| Global | 钟名 | 周期 ns | 驱动 | 时钟负载 | 网络 |
| --- | --- | --- | --- | --- | --- |
| g0 | `clk_fpga_0` | 10.000 | `buffer_fclk_clk_0.FCLK_CLK_0_BUFG/O` | 3597 | `processing_system7_0/inst/FCLK_CLK0` |
| g1 | `clkout0_1` | 20.000 | `u_pl/u_clk/u_bufg_pix/O` | 3276 | `u_pl/u_clk/clk_pix` |
| g2 | `eth_rxc` | 8.000 | `u_eth/u_rgmii/u_rgmii_rx/BUFG_inst/O` | 2544 | `u_eth/u_rgmii/u_rgmii_rx/gmii_rx_clk` |
| g3 | `sys_clk` | 20.000 | `sys_clk_IBUF_BUFG_inst/O` | 186 | `sys_clk_IBUF_BUFG` |
| g4 | `clkout1_1` | 4.000 | `u_pl/u_clk/u_bufg_5x/O` | 8 | `u_pl/u_clk/clk_pix5x` |
| g5 | `clkfbout` | 20.000 | `u_idelay_clkgen/u_bufg_fb/O` | 1 | MMCM0 反馈 |
| g6 | `clkout2` | 5.000 | `u_idelay_clkgen/u_bufg_200/O` | 1 | `idelay_clk`（IDELAY 参考 200 MHz） |
| g7 | `clkfbout_1` | 20.000 | `u_pl/u_clk/u_bufg_fb/O` | 1 | MMCM 反馈 |

同一份报告的 `:128`、`:151`、`:174` 是"Device Cell Placement Summary"里的另一组数
（Slice Loads）：g0 = 3338、g1 = 2492、g2 = **2544**。**两个 2544 是巧合还是同一个口径？
不是同一个口径**：`:61` 那一列叫 Clock Loads（`connect` 到钟引脚的单元数），
`:174` 那一列叫 Slice Loads，而 `build/timing_summary.rpt:182` 的 `eth_rxc` 端点数是 **4835**。
三个数单位不同，念的时候要分开——这一条在仓库里出过一次事故并改过两份教学文档
（`域划分候选评估` 与
`docs/course/10` 的 `eth_rxc` 行，提交 `4cf7f3e` 的记录就是"4835 是名册端点、2544 只是
`clock_util` 的寄存器数"）。**这是本章第一条纪律：一个"多少个"必须先回答"哪个口径"。**

### 1.2 谁 create 的，决定了约束能写在哪个文件里

`时序债务账` 那张表把八只钟的来源逐个钉住，其中两条是全部麻烦的根源：

- `sys_clk` 与 `eth_rxc` 是 XDC 里手写的 `create_clock`
  （`src/constraints/rk_zynq7020.xdc:6` 的 20.000、`:36` 的 8.000）。
- **`clk_fpga_0` 是 PS7 IP 自己的 XDC 从 `FCLKCLK[0]` create 的**，
  周期来自 BD 配置 `PCW_FPGA0_PERIPHERAL_FREQMHZ {100}`
  （`build/tcl/build_system_axigpio.tcl:97`），全仓 XDC 里 grep 不到这一行。
- `clkout0_1 / clkout1_1 / clkout2` 是 MMCM 输出，`clkfbout / clkfbout_1` 是反馈钟。

"综合阶段取不到 `clk_fpga_0`"这一句不是抱怨，它有具体后果，见第 2 节。
反馈钟与 `clkout1_1 / clkout2` 在 Intra Clock Table 里**没有 setup/hold 行**
（`build/timing_summary.rpt:184-188`：那五行只有 WPWS 列有数），
`时序债务账` 对这件事的口径写得很干净：
**"NA 是这一族没有同沿路径，不是'我读不到'"**。

### 1.3 设计级读数与那张 Inter Clock Table

`build/timing_summary.rpt:149-151` 是全设计那一行：

```
WNS 0.739  TNS 0.000  TNS Failing Endpoints 0  TNS Total Endpoints 51135
WHS 0.052  THS 0.000  THS Failing Endpoints 0  THS Total Endpoints 51135
WPWS 0.264 TPWS 0.000 失败 0 / 12634
```

`:154` 是那句 `All user specified timing constraints are met.`
逐时钟（`:181-188`）：`clk_fpga_0` 1.850/0.053、`eth_rxc` 0.739/0.052、
`sys_clk` 14.876/0.222、`clkout0_1` 3.630/0.059。
**头条 0.739 就是 `eth_rxc` 那一格**，这决定了后面很多事（第 6 节）。

`build/timing_summary.rpt:196-200` 的 Inter Clock Table 只有两行
（`clkout0_1 → sys_clk` 19 端点、`sys_clk → clkout0_1` 231 端点）。
**这不是"跨域路很少"，这是 `set_clock_groups` 的直接产物**：
被声明成异步的组之间根本不做时序分析，所以只剩 `sys_clk` 与它自己的生成钟 `clkout0_1`
（两者在同一个 group 里，`src/constraints/clock_groups_impl.xdc:13-17`）。
这两行与 `build/cdc.rpt:24-25` 的 `Safely Timed` 配对逐条对应（231/19）。
把两份报告并排读，就得到"哪些跨域是**被分析的**、哪些是**被结构保证的**"这张地图，
这正是第 7 节 I/O 台账的同类问题在时钟侧的样子。

---

## 2. 两个约束文件为什么必须切开

### 2.1 分工的形状

| 文件 | 阶段 | 内容 | 挂载 |
| --- | --- | --- | --- |
| `src/constraints/rk_zynq7020.xdc` | 综合 + 实现 | CFGBVS/CONFIG_VOLTAGE、30 行管脚、2 条 `create_clock`、1 条 hold uncertainty、6 条 `set_false_path`、BITSTREAM 压缩 | `build/tcl/build_system_axigpio.tcl:31` |
| `src/constraints/clock_groups_impl.xdc` | **只在实现** | 一条 `set_clock_groups -asynchronous` | 同文件 `:36-38` |
| `src/constraints/r116_rgmii_input_window.xdc` | 环境门控 | RGMII 5 个输入的输入窗 | 同文件 `:57-64` |
| `src/constraints/r119_hdmi_source_window.xdc` | 环境门控 | HDMI 源端 TP1 输出窗 | 同文件 `:75-82` |
| `r114_io_async.xdc` / `r114_io_varianta/b` / `r115_io_window_candidate.xdc` / `r119b_hdmi_tp1_pinclk.xdc` | 不加载 | 实验材料 / 反例 / 只给探针用 | 没有任何 `add_files` |

`时序债务账` 用 grep 实测确认了最后一行：
盘上有候选件、脚本里不加载 ⇒ **它们不是现行约束集的一部分**，
这一版名册的口径按"现行两文件"算。这一条很实用：读约束目录时，
`ls src/constraints/` 给你的是**候选全集**，只有 `build_system_axigpio.tcl` 的 `add_files`
那几行给你**生效集**。

### 2.2 三条工具行为把拆分钉死

`src/constraints/rk_zynq7020.xdc:62-75` 那段注释（62 行起）写的不是偏好，是三个可复现的错误：

1. **`get_clocks` 取不到对象 ⇒ 整条命令空转。**
   `set_clock_groups` 里并进 `clk_fpga_0`，综合阶段它还不存在，
   `-quiet` 只能压住 `get_clocks` 的报错、**压不住命令本身**，于是每个 run 吃一条
   `CRITICAL WARNING [Vivado 12-4739] set_clock_groups: No valid object(s) found for
   '-group [get_clocks -quiet clk_fpga_0]'`，而且**整条不生效**——
   `eth_rxc / sys_clk` 那两组一起废掉，现场只留一句 warning（`:66-70`）。
   同一件事在 `:43-45` 已经因另一条命令被记录过一次（那条把取不到的名字并进
   `set_clock_uncertainty`，会连带废掉 `eth_rxc/sys_clk` 几组）。
2. **XDC 里不许写控制流。**
   写 `if` 会报 `[Designutils 20-1307] Command 'if' is not supported in the xdc constraint file`
   （`:71-73`）。这条在 r119 那次踩得更难看：`src/constraints/r119_hdmi_source_window.xdc:3-11`
   记录了第一版候选件在 .xdc 里写了"读不到参考钟就 REFUSE"的 Tcl 守卫，
   结果**守卫被解析器整块跳过、`read_xdc` 仍然 rc=0**——
   "防呆"变成"防呆失效且不报错"，比没有守卫更危险。检查与 REFUSE 因此挪回
   `build/tcl/build_system_axigpio.tcl` 的 `VP_R119_TMDS_WINDOW` 块（那里是 Tcl 脚本，`if`/`error` 合法）。
3. **`set_false_path` 的方向用错也是空约束。**
   `rk_zynq7020.xdc:51-54`：`eth_rst_n` 是**输出**（`src/rtl/top/system_top.v:112`
   的 `assign eth_rst_n = phy_rst_cnt[23];`），所以只能当 `-to` 的终点；
   原来那行 `-from [get_ports eth_rst_n]` 每次综合报
   `CRITICAL WARNING [Constraints 18-513] ... contains no valid startpoints`，
   一条不约束任何东西、只制造噪声的空约束，已删。

拆分的代价核算写在 `clock_groups_impl.xdc:8` 与 `rk_zynq7020.xdc:74`，而且是同一句：
**综合阶段这条约束在拆分前也是失败的（等于不存在），所以拆分不改变任何时序数字。**
这句话把"改约束文件"从风险降级成噪声清理——这是它能不能被采纳的关键判断。
反过来，把两份合回去这条路被正式量过一次并判负：
`刀口台账`（C6，XDC-ORDER）状态列写
`rejected(measured)`，机制证据列写的就是上面第 1 条那个 12-4739。

### 2.3 三个环境门控旋钮的共同形状

`build/tcl/build_system_axigpio.tcl` 里四个旋钮是同一条纪律的四个实例：
`VP_R116_IO_WINDOW`（`:57-64`）、`VP_R119_TMDS_WINDOW`（`:75-82`）、
`IMPL_STRATEGY`（`:317-323`）、`IMPL_POST_PLACE_HOOK`（`:328-336`）、`IMPL_PRPO`（`:341-352`）。
共同点有三条，每条都能在代码里指出：

- **默认不设 = 历史行为**，所以已发布那一版的复现路径不被改写（`:325-327` 明写这个理由）。
- **用了什么必须打进日志**（`BUILD_STRATEGY` / `BUILD_POST_PLACE_HOOK` / `BUILD_PRPO` 三个 `puts`），
  理由是"策略一旦写死进脚本，过几个月没人知道眼前这颗 bit 是哪一档出来的"（`:312-316`）——
  **产物自己带着出身**。
- 新增约束的两个旋钮一律 `used_in_synthesis false`（`:59`、`:77`）。
  r116 那一档还额外把它当**对照**用：`:41-42` 那句
  "网表逐字节不变、只有实现阶段的检查变多，这本身就是一个对照
  （任何资源/告警差异都不该出现，出现了就是这一刀的问题）"。
  这个读法在 V5 那条判据上兑现了：`那一轮的逐轮页` 量到
  `Slice LUTs 14154 / Slice Registers 8188 / LUT as Memory 4185 / BUFGCTRL 8`
  与 HEAD 那份**一格不差**——这三行今天仍能在 `build/utilization.rpt:35,40,83,161` 复核。

### 2.4 两个候选窗各是谁的债

- `VP_R116_IO_WINDOW` 还的是 **H5**：`eth_rx_ctl` / `eth_rxd[3:0]` 从来没有 `set_input_delay`，
  `check_timing` 把它们点名成缺口（`src/constraints/r116_rgmii_input_window.xdc:3-5`）。
  文件里那句 **"未覆盖 = 不是'满足'，是'没检查'"** 是全章的口径。
- `VP_R119_TMDS_WINDOW` 还的是同一台账里输出侧那 6 个端口，
  而且它带的不是"满足"而是**"这一族规范量在 SDC 里的容器选错过一次"**的教训（第 5 节）。
- 两份文件都**默认不加载**，理由各不相同，而且都写在挂载处
  （`build/tcl/build_system_axigpio.tcl:44-56` 与 `:70`）：
  前者是被自家发布门判红（第 4.9 节），后者是**缺一次量名册的构建**——
  "新增约束必须先用一轮构建量逐时钟名册（别域不许变差），
  量过之前带进发布物就是用声明代替测量"。

---

## 3. 主 XDC 逐条：每一条都问"当初为什么"

`时序债务账` 那张"每条既有例外的当初理由"表是本节的骨架。
值得单独展开的是两条。

### 3.1 `set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]`

`src/constraints/rk_zynq7020.xdc:50`。这一行的方向**与"放松判据"相反**：
它给 hold **加** 0.5→0.8 ns 的要求（`:41-42`、`:47-49`）。
起因是 `#46` 量到的机制：IDDR 走 BUFIO（SCD 3.171 ns）、终点 fabric FF 走 BUFG（DCD 4.854 ns），
同频同相却分走两条树，偏斜 1.616 ns，而那条数据路径只有 1.855 ns
（预算 8.000 ns）⇒ 工具**垫得出来**，但每次重建垫多少是随机的：
r62 只剩 WHS +0.001、r63b 是 +0.052——**同一份 RTL 的两个数是"掷硬币"的直接证据**（`:39-40`）。
加严的目的不是变好看，是把余量做成**设计值**，验收口径也写在同一处：
`WHS 应升到 ≥ 0.4`（`:46`），而 r79 试验量到 0.5 那一档工具只做到 WHS +0.051（`:47`）
⇒ 再加严到 0.8，并预先写好"若因此关不住时序就带两个数退回 0.500，
把'工具在这个布局下垫不到 0.4'记成实测结论，而不是悄悄把验收改掉"（`:48-49`）。

这条带子后来变成了窗模型里一笔**已登记的双重计**：`收口输入窗模型`
承认它与输入窗重复计入，去掉能把 −0.870 抬到约 −0.385，但**去掉它就是 H1 的放宽**，
未获批准 ⇒ 不放宽，代价写在报告里。`放松台账`
把"两处看起来该放松但没放松"逐条列出（另一处是 ±0.500 那个窗没绑进工程）。
台账数据行 **0 条**，注释里那句理由值得抄：
"一张空表比一张'替用户批了'的表诚实"（`放松台账`）。

### 3.2 六条 false path 的两种性质

`rk_zynq7020.xdc:55-60`：`-to eth_rst_n / eth_tx_clk / eth_tx_ctl / eth_txd[*]`、
`-from key1_n / key2_n`。`时序债务账` 给这一组做了分类：

- `key1_n/key2_n`：**理由可查**——异步输入，去抖链自己做跨域；
  上电初值那格在 r113 用声明初值修，尺子是 `sim/tb_v113_key_powup.v` + `build/check_powup_init.sh`。
- `eth_tx_*` 那四条：**文件里没有写当初理由** ⇒ 被标成
  **"待复核债务"**，处置是"不补约束、不删"（H1）。
  这是这套账本最有价值的一种行：**承认一条约束正被使用，同时承认说不出它为什么**。

`eth_tx_clk` 那一行还牵出一个工具口径：它是源同步输出的**时钟**，
所以 `check_timing` 不把它算进 `no_output_delay`
（`build/check_io_timing_coverage.py:116-118` 把这条与"差分对只报 `_p` 那一半"
一起写成两条**从件里读出来的** Vivado 口径，并注明"改动它们必须同时改那份件的读法"）。

---

## 4. 输入窗测量纪律：RGMII 那一族怎么被量到"极限"的

这一节是全章方法密度最高的部分。它的产出不是一个更好的数，
而是一套**可以被下一个人照做的测量顺序**。

### 4.1 数从哪来：三条本地可核的出处

`src/constraints/r116_rgmii_input_window.xdc:7-20` 列了三条：

1. **原理图**（本机 PDF 第 8 页）：R57/R59 4.7K 把 `PHY1_RXD0/RXD1` 上拉到 `PHY1_IODVDD`
   ⇒ 板上 **RXDLY 是开的**。
2. **规格书 RTL8211F-CG Table 10（PDF p23）**：RXD0=RXDLY、RXD1=TXDLY；
   Table 11 与 Table 6（p16）："1: Add 2ns delay to RXC for RXD latching" ⇒
   **2 ns 延时加在 RXC 上，不是加在数据上**。
3. **Table 60（p67）里管这一路的行是发射端那两行**（"transmitter" = PHY 输出 = 本板收口）：
   `TsetupT` min 1.2 typ 2、`TholdT` min 1.2 typ 2；两者相加 = 半周期 4 ns ⇒
   **数据沿相对它自己的捕获沿落在 [1.2, 2.8] ns 之前**。

### 4.2 "用错行"发生过三次，每次都留下编号

`src/constraints/r116_rgmii_input_window.xdc:18-20` 与
`src/constraints/r115_io_window_candidate.xdc:17-19` 把这条链写全了：

| 误用 | 用了哪一行 | 那一行讲的是什么 | 登记 |
| --- | --- | --- | --- |
| `r114_io_async.xdc:39-43` 的 ±0.500 | `TskewT` | 发射端**没有**内部延迟集成时的输出偏差 | `issues.md #304` |
| `r115_io_window_candidate.xdc:38-41` 的 1.000/2.600 | `TsetupR/TholdR`、`TskewR` | **PHY 的接收端** = 本板 TXD/TXC 那一侧 | `issues.md #309` |
| `时序债务账`（00:12 追补那段） | `TskewR` 的 1.5–2.0 ns | 讲的是 PCB **时钟走线**，被当成数据散布用 | 同一条 #304/#309 族，自己标为残余风险 |

`r115_io_window_candidate.xdc:21-26` 那一节还留了一条好判断：
因为 PHY 的 TXDLY/RXDLY 与 RXD1/RXD0 复用、复位怎么被拉、寄存器 0x11 现值都读不到，
所以取**两种模式都更严的并集**（下界 1.0、上界 2.6），
并且明写"不许反过来写：不许先假定延迟开着再挑好看的数"。
取并集而不是猜模式，这个取舍的形状可以直接搬走。

### 4.3 工具的边配对决定 offset 从哪个沿量起

`src/constraints/r116_rgmii_input_window.xdc:22-27`：为什么写成正的 1.2/2.8
（不是 −2.8/−1.2，也不是 5.2/6.8）。理由完全来自报告自己的 Requirement 行——
工具对 IDDR 的 D 脚做的是"上升沿发射 → **下一个（下降）沿**捕获"的 setup 检查
（原文 `Requirement: 4.000ns (eth_rxc fall@4.000ns - eth_rxc rise@0.000ns)`），
hold 则对**同一个上升沿**（`Requirement: 0.000`）。
这份件今天就能开：`build/evidence/r116/r116_io_setup.rpt:22` 打的正是这一行，
而 `build/evidence/r116/r116_io_hold.rpt:22` 打的是 `0.000ns (eth_rxc rise@0 - rise@0)`。
四种拼法里 W1/W2 是 W5 各差一个/半个周期的镜像（`收口输入窗模型`
那张 W1..W4 表，±4.0 的对称红绿就是证据）。

还有一条平台差异被钉在文件里：本机 `set_input_delay` **没有** `-setup/-hold`，
也没有 `-clock_edges`，`-min` 与 `-max` **必须各写一条命令**
（合在一条会被解析成"太多 positional"，`src/constraints/r116_rgmii_input_window.xdc:30-31`，`#308`）。
所以那份文件是 4 条而不是 2 条：两沿都要写，因为 IDDR 上下各采一半字节。

### 4.4 抽头与 ns：三个数互不一致，所以不许换算

这是"IDDELAY 抽头对 ns 的非线性"在本仓库的真实形状。三行都能开：

| 说法 | 数值 | 出处 |
| --- | --- | --- |
| 设计时的算术 | 200 MHz 参考 ⇒ 每拍 1/(32×200 MHz) = **156 ps** | `src/rtl/eth/rgmii_rx.v:8-9` |
| 扫描实测斜率（hold 侧） | **+63.0 ps/拍** | `build/evidence/r115_window/probe3_console.txt:107,188`（tap0 −2.822 → tap31 −0.870，除以 31） |
| 报告分量反推 | `IDELAYE2` 在 tap26 约 2.293 ns ⇒ **≈88 ps/拍** | `收口输入窗模型` |

`src/rtl/eth/rgmii_rx.v:22` 直接把这件事写成一条警告：
"156 ps/拍 与 63 ps/拍、88 ps/拍 **三种数互不一致** ⇒ 谁要再按'拍数 = 1.683 ns / 156 ps'推采样点，
先把这条量清楚（未定，不当结论用）"。同一文件 `:8-10` 还留着那条**当年自洽的推导**：
把 IDDR 从 BUFIO 换到 BUFG 会把采样沿往后推 1.683 ns，所以数据侧补 10.8 拍取整为 11，
`15+11 = 26`。这段是理解 `src/rtl/top/system_top.v:160-172` 那一大段注释的钥匙——
26 是**算术推出来的**，31 是**工具在真窗下量出来的**，两者差 5 拍，
而 `system_top.v:162` 明写改到 31 的理由"不是那段算术而是实测曲线"。

**为什么会不一致**，物理侧也说得通：IDELAYE2 是模拟延迟线，
它的 tap 步长既不是理想的 1/32 参考周期，也**几乎不随工艺角缩放**
（`收口输入窗模型` 那句"只有 IBUF 那一段缩放 ⇒ 加更多 IDELAY 只会把
`D_slow/D_fast` 压得更低"）。而 hold 查的是慢角、setup 查的是快角
（`:376-377` 把两条报告的标题行原文都抄了），所以**同一次 tap 变化在两条曲线上给出两个斜率**
（63 ps 与 −92 ps）。结论可迁移成一句话：
**抽头不是时间单位；任何拿抽头换算采样点的推理都必须带着角。**

### 4.5 0…31 全档扫描：两条直线的交点

`build/evidence/r115_window/probe3_console.txt` 是这份扫描的原件，
`set_property IDELAY_VALUE` 在已布线 DCP 上有效、且逐档回读对上
（`收口输入窗模型`；这一条能省一整次构建）。
带 0.800 hold 带的那一组，取几个实测点：

| tap | HOLD slack | SETUP slack | 行号 |
| --- | --- | --- | --- |
| 0 | −2.822 | +2.005 | `:107`、`:111` |
| 12 | −2.066 | +0.902 | `:134`、`:138` |
| 26（出货值） | −1.185 | −0.386 | `:170`、`:174` |
| 31（上限） | **−0.870** | **−0.846** | `:188`、`:192` |

两条直线与交点（`收口输入窗模型`、`那一轮的逐轮页`）：

```
HOLD(τ) = −2.822 + 0.0630 τ
SETUP(τ) = +2.005 − 0.0920 τ
交点 τ = (2.005 + 2.822) / 0.155 = 31.1  ⇒ min(hold, setup) 在 0…31 上的最大值 = −0.870（τ=31）
```

刀 2（`IDELAY_VALUE` 26→31）因此是 **+0.315 ns 的实测收益**，不是预测
（`收口输入窗模型` 与 `cut_ledger.tsv:9` 的 C8 行都这么标）。
这份预测后来在正式构建里逐格命中：`那一轮的逐轮页` 记 V3——
正式构建实测 hold **−0.870**、setup **−0.846**，"DCP 上扫出来的那条曲线在真构建里对到了小数第三位"。
**"先在同一份 DCP 上扫、再花一次构建验它"这个顺序，是这一节最应该被抄走的东西。**

### 4.6 极限判据：把不等式写全，而不是"再找个点"

`收口输入窗模型`（§7.5(4)）。先把两条曲线各自求根：

```
HOLD(带 0.800) ≥ 0  ⇒ τ ≥ 44.8
HOLD(去掉带)   ≥ 0  ⇒ τ ≥ 32.1
SETUP          ≥ 0  ⇒ τ ≤ 21.8          而 τ 的合法区间只有 0…31
```

**hold 要的 τ 与 setup 要的 τ 区间不相交，带子去不去都一样**（32.1 与 21.8 仍不相交）。
再用报告自己的分量看同一件事，根因从"点没找好"变成"两条检查用的钟不是同一个数"：
hold 查慢角钟网络（DCD **5.008**）、setup 查快角（DCD **1.597**），
**钟网络角间差 3.411 ns 远大于数据路径的 0.467 ns**；数据长度是唯一可调量，而它同时受两边约束：

```
带 0.800： D_slow ≥ 4.763 且 D_fast ≤ 2.762 ⇒ 需要 D_slow/D_fast ≥ 1.73
去带：     D_slow ≥ 3.998 且 D_fast ≤ 2.762 ⇒ 需要 ≥ 1.45
实测（IDELAY 主导）：3.613 / 3.146 = 1.15      ← 两个门槛都够不着
```

`:343-353` 把"要多短的钟"写成一条联合不等式
`0.029·C_slow + 0.063·(C_slow − C_fast) ≤ 0.214`，
于是"下一刀的靶子"不再是单一的"降到 1.2 ns"，而是**同时**把 `C_slow` 拉低与角间差收窄。
`那一轮的逐轮页` 的收口写法值得背下来：
**这一族在当前结构下物理上不存在能同时满足两条检查的采样点；
能动的三样（数据延时、相位、不确定度带）都量过、都关不掉。**
`cut_ledger.tsv:4`（C3，把 IDDR 捕获钟提前）的状态列正是
`rejected-measured(00:01 副本树：S1 仍红 WHS −2.126；且 UU 0.800 脱离派生钟覆盖面 ⇒ 不进主树)`，
件在 `build/evidence/r115_c2_scratch/option_a_main_console.txt`。

### 4.7 角分配：报告已经比"真最坏"宽松 0.4–0.5 ns

`收口输入窗模型`（§7.5(6)）。同一只 DCP、同一个
`Path Group: eth_rxc`，两类路的角分配是**相反**的（都是报告自己的标题行）：

| 路 | 报告原文 | 数据路径 | 钟路径 DCD |
| --- | --- | --- | --- |
| 内部 setup | `Setup (Max at Slow Process Corner)` | 7.066（慢） | 慢 |
| 内部 hold | `Hold (Min at Fast Process Corner)` | 0.986（快） | 快 |
| **I/O hold（带窗）** | `Hold (Min at Slow Process Corner)` | 3.613（慢） | **5.008 慢** |
| **I/O setup（带窗）** | `Setup (Max at Fast Process Corner)` | 3.146（快） | **1.597 快** |

I/O 路把**钟**放在对该检查最不利的角上（源同步收口该有的保守方向），
而**数据**那一侧取的是同一角里偏松的值。自己算"真最坏"：

```
hold  真最坏 = 1.2 + 3.146 − (5.008 + 0.155 + 0.800) = −1.65   （报告给 −1.185）
setup 真最坏 = 2.8 + 3.613 − (4 + 1.597 − 0.035 − 0.259) = −0.85 （报告给 −0.386）
```

`:388-389` 那句是这一小节的存在理由：**"工具的读数不是被角分配坑了：
它已经比真正的最坏情况宽松 ~0.4–0.5 ns，仍然是负的"**，
这条要写在极限判据旁边，否则后面会有人拿"角分配反了"当理由去改约束或改报告口径。
（今天这份 r116 件里同样的两行是 `build/evidence/r116/r116_io_hold.rpt:21,23`
= `Hold (Min at Slow)` / `Data Path Delay 3.928ns (logic 100.000% route 0.000%)`，
`build/evidence/r116/r116_io_setup.rpt:21` = `Setup (Max at Fast)`——`route 0.000 %` 这个反常形状本身就是 I/O 路的指纹，
`那一轮的逐轮页` 念的就是这一条。）

### 4.8 报告最优不等于硅片眼心：τ=31 的采纳条件与它的未闭合

`收口输入窗模型`（§7.5(7)）把这件事登记成**未定**，
并且明写"不许圆场"。物理条件单独写一遍：`C` = 钟网络到 IDDR C 脚的延迟、
`D = 1.976 + 0.0630τ`、`Ts ∈ [1.2, 2.8]` ⇒
**采对沿的充要条件是 `|C − D| ≤ 1.2 ns`**。报告给的是 min/max 两个角，
**没有任何一件测过这颗芯片的 `C`**：

| τ | `D = 1.976+0.063τ` | 能采对沿的 C 区间 | 对角包络 [1.597, 5.008]（宽 3.41）的覆盖 |
| --- | --- | --- | --- |
| 21 | 3.30 | [2.10, 4.50] | 70 %（两端各差约 0.5） |
| 26（出货值） | 3.61 | [2.41, 4.81] | 70 %（快端差 0.81、慢端差 0.20） |
| 31（报告最优） | 3.93 | [2.73, 5.13] | **67 %（快端差 1.13）** |

⇒ `:424-426` 的结论是 **τ=31 比 τ=26 在真实角上更不鲁棒**，
它之所以是"报告最优"，是因为 hold 那一侧被 `0.800` 单方面加了 0.8 ns
（setup 侧只有 0.035），两条曲线的交点被往 setup 方向推了约 5 拍。
`:428-430` 因此改变了采纳判断，而且把两边都写出来：
**τ=31 换来的是"报告数字好看 0.315 ns"，代价是"真实角上鲁棒性 −3 %"且偏离已被板子证明能跑的 26**；
裁决条件是**只有 1000M 实流量 `bad=0` 才保留 31，一旦 `bad>0` 或 `drop_words>0` 立刻回 26**。

`:431-432` 记执行情况，而且不涂绿：τ=31 已随 r118 上板、带流 `drop_words=0`，
但同一份件里 `pkt_err=?` / `frames_bad=?` ⇒ **上面那条 `bad=0` 没有闭合**
（`board_verify` 判红步骤 0 覆盖的是几何/命令那一族，不是这一条）。
想真正量眼心需要一笔小改动：把 5 颗 IDELAYE2 换成 `VAR_LOAD`（或加一条写通路），
用串口逐档加载 + 实流量看 `bad`；**这一笔没做**——
`src/rtl/eth/rgmii_rx.v:68` 至今是 `.IDELAY_TYPE ("FIXED")` ⇒ 运行时改不了。

### 4.9 r116：绑上窗之后被自家发布门拒绝

这一节回答"为什么现在构建里默认没有输入窗"，答案是**量过的**，不是躲的。

绑窗的机制先兑现（V1，`那一轮的逐轮页`）：那 5 条路从
`Slack: inf / Path Group: (none)` 变成**有限**并出现 `Input Delay:` 行——
今天开着的两件是 `build/evidence/r116/r116_io_hold.rpt:15,25`
（`Slack (VIOLATED) −0.870ns`、`Input Delay: 1.200ns`）与
`build/evidence/r116/r116_io_setup.rpt:15,25`（`−0.846ns`、`Input Delay: 2.800ns`）。

名册差分给的却是红（`build/evidence/r116_roster_diff.txt:1-11`，逐行可核）：

```
eth_rxc/setup  0.739 → −0.846   margin_pct 9.24 → −10.57
eth_rxc/hold   0.052 → −0.870   margin_pct 0.65 → −10.88
其余三域：clk_fpga_0 18.50→19.76、clkout0_1 18.15→18.49、sys_clk 持平；四域 hold 逐格不动
D1_no_new_violation new=2 RED      D3_margin_cost big_loss=2 RED
```

于是**仓库自己的发布门禁 4 条硬项机械判红**（WNS ≥ 0、失败 setup 端点 == 0、
WHS ≥ 0、失败 hold 端点 == 0），而门禁末尾那句写死的是"有红项 ⇒ 不采纳，保留上一版"
（`build/tcl/build_system_axigpio.tcl:44-48`）。可选的两条路写在
`那一轮的逐轮页`：把发布门改成"允许设计性红"——**不做**，那是给自己开门；
**约束留在仓里当候选件、全部证明与读数保留、构建默认不加载**——做了，
`VP_R116_IO_WINDOW=1` 一条命令复现。同文件 `:16` 补了关键一句：
相对 r114 这**不是放宽**（r114 从来没有这条约束，松动台账仍 0 条），
按 `那一轮的逐轮页` 的原话是"本轮新增的约束被自家发布门拒绝"，
     处置是"按 H7 回滚这一处切割，并把回滚原因留在原处"。

`build/tcl/build_system_axigpio.tcl:48-56` 那半句必须一起念：
**"这个设计只有在'RGMII 输入不被检查'的前提下才过发布门禁"**——
撤销的是"把它带进发布物"这个动作，不是约束的正确性；
下一刀（捕获钟）落地之后，这个窗应当重新加载。
G1 与 H5 在这里天然冲突：**不绑窗就 H5 红、绑了就 G1 红**，
`门禁逐条页` 把这两条都写出来，并说"两条都写出来才是这一格的产出物"。

---

## 5. HDMI 源端窗：一次把规范量塞错容器的完整样本

第 4 节是"窗建对了但关不掉"，这一节是"窗建错了所以必红"。两份文档合起来才是完整的纪律。

### 5.1 规范行是什么形状

`src/constraints/r119_hdmi_source_window.xdc:18-27`：
出处是《HDMI Specification 1.4》§4.2.4 Table 4-24 的
`Inter-Pair Skew at Source Connector, max = 0.20 Tcharacter`
（同表在 1.3 Table 4-16 / 1.1 Table 4-13 逐字一致，Tektronix 的 CTS 应用笔记复述为
"20 % of the pixel time"）。本工程当前档 `Tcharacter` = 像素周期 = 1/50 MHz = 20.000 ns，
而 50 MHz 这一格取自 `data/metrics.csv` 第 3 行（同文件 `:23-25`）。
⇒ 半窗 = 0.20 × 20.000 = **4.000 ns**，"这是从上面两个数算出来的，不是抄来的第三个数"。

### 5.2 两次 load，两个负数，一个共同原因

`屏侧实测记录` 记了两次只读探针（都打在
`system_top_opt.dcp` 上，没重建产物）。两份件都在盘上：
`build/evidence/r119_xdc_loads_probe3.txt:113` 与
`build/evidence/r119_xdc_loads_probe4_pinclk.txt:113`。

| 参考对象 | 三条数据道 load 后的 slack | 工具的 Requirement 展开 |
| --- | --- | --- |
| 片内 250 MHz 串行钟 `clkout1_1`（周期 4.000） | −3.482 / −3.458 / −3.474 | `Path Group: clkout1_1`、`Requirement: 4.000ns` |
| 脚上钟 `r119b_tmclk`（`create_clock` 打在 `tmds_clk_p`，20.000） | −4.897 / −4.873 / −4.890 | `Requirement: 4.000ns (r119b_tmclk rise@20.000 − clkout1_1 rise@16.000)` |

两次都证明**约束真的挂上了**（`Path Group` 从 `(none)` 变成有钟，这是工具自己的行为），
也都判红。红的原因不是设计不合格，而是**量纲**：规范那一句约束的是
**两个输出脚到达时刻之差的上限**（单边离散量 skew），
不是"数据必须在参考沿前后某窗口内保持稳定"的**采样窗**；
而 `set_output_delay` 的语义恰恰是后者，它把参考时钟的沿当外部采样沿，
于是边沿对齐的 TMDS 输出被要求在一个**位周期**内准备好 ⇒ 必然造违例
（`屏侧实测记录`）。
第二次的 Requirement 展开式把这件事直接印在报告里：用 4 ns 的钟当 20 ns 周期的参考，
等于把窗口压缩成 1/5（`src/constraints/r119b_hdmi_tp1_pinclk.xdc:7-10`）。

还有一句规范原文被用来堵死"放宽窗让它绿"这条路：HDMI 1.3 第 45 页写源端眼图掩码
"specifies the clock to data jitter **indirectly**" ⇒ 规范自己**没有**给
"钟↔数据 setup/hold 窗"这个参数（`屏侧实测记录`）。

### 5.3 同量纲的问法与成品实测

正确问法（`屏侧实测记录`）：
**钟脚↔数据脚的 clock-to-pin 延迟离散 ≤ 0.20 `Tcharacter` = 4.000 ns、
P/N 对内离散 ≤ 0.15 `Tbit` = 0.300 ns**。
这条能对**已布线成品**直接问，尺子是 `build/tcl/probe_tmds_pin_skew.tcl` +
`build/r119_window_check.mjs`。读数（件 `build/evidence/r119_window_check.txt`，
判 10 项红 0）：

| 判据 | 上限 | 实测最差 | 行号 |
| --- | --- | --- | --- |
| W7 互对离散 max 角 | 4.000 ns | 0.065 ns（逐道 −0.041/−0.065/−0.049） | `:8` |
| W8 互对离散 min 角（成对换角再判） | 4.000 ns | 0.064 ns | `:9` |
| W9 对内离散（四对 P/N） | 0.300 ns | 0.001 ns | `:10` |
| W10 计数地板（数据道 3/3、P/N 对 4/4、钟道两角齐） | 缺一条不许判通过 | 全齐 | `:7` |

射程边界写在同一份文档 `:88-93`，三段式：**能说**的是 FPGA 内部（串行器钟脚→封装脚）
的离散在上限的 1/60 与 1/300 以内；**不能说**的是连接器（TP1）上的总离散
——板级走线、连接器与线缆不在这条路径里，本板未量；
**也不能说**"过了 CTS"，因为 CTS 的判据是眼图掩码 + 抖动 + 占空比 + 上升下降，
那些在 SDC 里没有容器（`:113` 的 D3 行仍标未实测，需要仪器与批准）。
`src/constraints/r119_hdmi_source_window.xdc:40-49` 把这三条同样写在文件里，
包括"`led[0]/led[1]` 是 `LVCMOS33` 直驱 LED（`rk_zynq7020.xdc:10-11`），
HDMI 连接器引脚表里没有这类信号 ⇒ 没有可引用的对外窗；本文件不替它们写任何窗"。

### 5.4 尺子自己没牙的那一次

`屏侧实测记录`：第一版探针找
`data arrival time` 这个**不存在的行**，于是十脚全打 `NO_ARRIVAL_LINE`。
形状是从报告原文量的：`build/evidence/r119_pin_skew_probe2.txt` 那批读数用的是
`Data Path Delay: 2.033ns (logic 2.032ns (99.951%) route 0.001ns (0.049%))` 这种行
（那份形状件 `build/evidence/r119_shape_tmds_data_p_0_.txt` 现已不在盘上，
原文行留在 `屏侧实测记录` 里）。
**先量报告长什么样，再写解析器**——这条与第 6.2 节 `probe_timing_roster.tcl` 里
`route_pct` 那个正则的修复是同一次教训的两次落地。
另一条同样重要：`build/evidence/r119_xdc_loads_probe2.txt`（那份记 20-1307 的件）
**现在已不在盘上**，所以 2.2 节那条守卫失效的读数只能算抄件；
而 `r119_clock_networks.rpt`（`src/constraints/r119_hdmi_source_window.xdc:33` 点名）也不在，
只有参考钟身份那件还在（`build/evidence/r119_ser_clock_probe.txt`）。

### 5.6 那份候选件后来被整体量了一遍：窗管用，但被判 DECLINE

把 `VP_R119_TMDS_WINDOW=1` 带进一次隔离构建（产物目录 `build/isolated_1006_d_tmdswindow/`，
被 `.gitignore` 的 `build/isolated_*/` 挡住，所以能引用的只有复制进 `build/evidence/` 的那几份）：

- **窗确实把缺口关上了一半以上**：`check_timing` 的 `no_output_delay` HIGH 从 6 降到 3，
  失败端点 **0**（`build/evidence/1006d_tmdswindow_timing_summary.rpt`）。
  注意"降到 3"而不是 0：那 3 个是 `led[0]`、`led[1]`、`tmds_clk_p` —— 这份候选件按 HDMI 的
  数据道口径只给 `tmds_data_p/n[*]` 绑窗，钟道那一段本来就不在它覆盖里。
- **代价落在别的域**：同生成器的逐时钟名册差分（`build/evidence/1006d_roster_diff_vs_r118.txt`，
  八对 (时钟,类型) 全配上）判 `RED`：`eth_rxc/setup` 0.739→0.471（相对余量 9.24 %→5.89 %）、
  `clk_fpga_0/setup` 1.850→1.492（−19.4 %）、`sys_clk/hold` 0.222→0.121（−46 %）、
  `clk_fpga_0/hold` −5.7 %、`clkout0_1/hold` −6.8 %；唯一变好是 `clkout0_1/setup` +8.7 %。
- **RTL 一字未改**。这是一次纯粹的"把对外端口纳入检查之后，工具重新布置"的连带代价，
  所以它给的是这条规矩的一个干净样本：**给原本没被检查的东西补检查，本身就是要付钱的改动**，
  不许记成"免费的正确性"。
- 判读按第 6 节的纪律走，不看全设计 WNS：本族没变好而别域变差 ⇒ **DECLINE**，
  默认构建不加载，候选件与开关原样留着。
- 顺手修掉名册差分的一处**假拒绝**：B 侧比 A 侧多出一颗钟（`clkout1_1` 因为绑窗才第一次被检查）
  原来一律 `REFUSE`，会把正当实验挡在门外。现在 A 的钟消失才 `REFUSE`、
  新钟 setup+hold 齐则打印 `ROSTERDIFF-NEWTIMED` 并放行、只有半行仍然 `REFUSE`；
  `--self` 的 `control_clock_inventory` 仍必须红（件 `build/evidence/1006d_roster_diff_selftest.txt`）。

---

## 6. 逐时钟名册：为什么"全设计 WNS 变了"这句话不许说

### 6.1 规矩 35 与它挡住的两种错

`build/timing_roster_diff.sh:8-12` 把动机写得最完整：
`crit_path.tcl` 只把全设计最差的那条排第一 ⇒ 每轮看到的都是同一个 `eth_rxc`，
其它三个域是涨是跌没人念；规矩 35 早就说过"全局 WNS 的绝对差不算收益也不算损失"，
**但那只挡住了"拿差值吹收益"，没挡住"把一个域改坏了而头条没动"**。
所以差分工具判的是两件别的事：有没有哪个域从 MET 变成违例、
有没有哪个域的**相对余量**（`slack/period`）掉过 25 %（`:19-20` 的 `LOST_PCT=25`、
`FLOOR_PAIRS=8`）。头条那一行按规矩 35 **只念不判**（`:179-181`）。

绝对差为什么不能算涨跌，本仓库有两个实测摆幅作锚点：
`#146` 那次 Pblock 实验里 `eth_rxc` 从 +0.516 变 +0.363，
`开发台账` 明写"**落在 0.4 ns 的实测摆幅之内**，按规矩 35 既不能算坏也不能算好"；
`门禁逐条页` 给的另一侧证据是
**空白滚逐位复现正式名册 ⇒ `noise_ns = 0.000`**（同一份 `opt.dcp` 重跑不产生噪声）。
两个数不矛盾：前者是**跨构建**的放置抖动，后者是**同构建内**的重跑噪声。
所以判据必须成对："跨构建的绝对差不许当收益"＋"同 DCP 的重跑是零噪声，
所以快车道滚之间的差**可以**归因给那一刀"（`那一轮的逐轮页`）。

### 6.2 `probe_timing_roster.tcl`：四个被咬过的形状

`build/tcl/probe_timing_roster.tcl` 只开
`vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp`（`:25-26`），
几分钟、不重建，所以"看全局"这件事很便宜（`:6-10`）。
四个坑都以注释形式钉在文件里，每一个都值得照抄成检查项：

1. `-of_objects [get_clocks X]` **同时拒绝** `-delay_type` 与 `-max_paths`
   （`[Vivado 12-1365]`）；能用的形状是 `-from $cl -to $cl`（`:12-13`、`:41`）。
2. 运行时标签保持 ASCII：Vivado Tcl 按系统代码页读这份文件，
   CJK 的 `puts` 曾把日志变成 binary、把命令替换打断（`:14-15`）。
3. `route_pct` 的正则：`Data Path Delay` 那行的百分比**在括号里**，
   第一版写 `route\s+([0-9.]+)ns\s+([0-9.]+)%` 永不命中 ⇒ 每行都带空 `route_pct`（`:56-61`）。
4. **缺列必须写 `NA`，不许留空**：空值同时表示"这一族没有路径"和"我的正则漏了"，
   那是两个不同的声明，在盘上必须长得不一样（`:68-74`）。
5. 扇出那一段最有教学价值：`report_design_analysis` **没有 `-fanout` 模式**
   （它的模式是 `-complexity/-congestion/-timing/-routes/-logic_level_distribution/...`），
   唯一的近亲 `-av_fanout_greater_than` 是 Rent 指数阈值、不是网名单。
   前两轮因此写出**空文件**——`catch` 吞掉错误、D6 判红，
   而探针注释把这件事定性成"红的是尺子，不是设计"（`:101-108`，
   实测凭据 `build/evidence/r113_help_fanout_console.txt` 仍在盘上）。
   正解被钉成代码：`report_high_fanout_nets`（`:108-118`）。
   还有一个二次坑：`get_nets` 会把 `[n]` 当 glob 类，
   所以探针**故意不做存在性检查**，只做清点，解析全部按位置无关规则
   （`:142-145`），并把原始表头打成 `FANOUT_HEAD` 让形状留在记录里（`:109-112`）。

### 6.3 `roster_from_summary.sh`：把"改前名册"从报告里长回来

`build/roster_from_summary.sh:8-12`：探针问的是**改后**那一版，
而"改前"那份 routed dcp **每轮构建都被覆盖**（`:9` 点了 r118 那次同类亏）。
好在 `timing_summary.rpt` 的 Intra Clock Table 里有每个时钟各自的 WNS/WHS 与端点数，
而这份报告每轮都被归档 ⇒ 改前名册可以从报告里长回来，不必拿全局 WNS 说事。
**口径纪律写在 `:12`：转换出来的 `levels/route_pct/dest` 一律 `NA`——
那三列只有探针给得出，缺就明说缺，不编。**

这把尺子的自测里有一条很硬的正对照（`:23-38`）：拿归档件
`build/evidence/r112_bit/timing_summary.rpt` 转出 `eth_rxc` 的 setup=0.445 / hold=0.050，
并且**额外钉一个外部真值**——周期必须是 8.000（125 MHz RGMII），
因为"周期列取错一格"会让 slack 与 margin 全都自洽地错（`:30-32`）。
为什么非得从报告拿周期：早先这里去 grep XDC 里的 `-period … -name …`，
而归档的是**报告**不是 XDC ⇒ 一条也没抓到、period 全成 NA、相对余量那条判据空转
（`:58-59`）。还有一个单位陷阱被单独做成判据 S4：
`$3` 那一格是**波形下降沿**不是周期，所以用"周期 × 频率 ≈ 1000"交叉核对，
两个操作数来自同一张表的不同列（`:62-66`）。

### 6.4 `timing_roster_diff.sh`：先问口径，再问涨跌

`:101-119` 是这把尺子的闸门，也是它最容易被跳过的部分。
两条要求：**时钟名单要一致**、**扇出节要同有同无**——
不同口径相减出来的不是代价，是尺子断。触发它的那次事故写在 `:103-106`：
拿探针生成的名册（slack 字段带 `1.135ns (required time - arrival time)` 这种散文、
里面有 `clkfbout` 这一路）去减 `roster_from_summary.sh` 生成的干净名册 ⇒
D3 一口气数出 `big_loss=8`、D6 念 `fanout_rows=0`，
看着像"别的域被挤坏了"，其实两侧根本不是一个口径。
同时 `:107-110` 承认自己第一版**矫枉过正**：把"必须纯数"也写进闸门，
结果把合法的同口径配对一起判成 REFUSE——
**"假拒绝挡掉正当实验"和"假接受"是同一类错**，所以 `--self` 里专门有
`control_prose_allowed`（散文必须照常 GREEN）与 `control_fanout_parity` /
`control_clock_inventory`（必须 REFUSE）三条（`:79-85`）。

六条判定与它们各自挡住的错（`:184-189`）：

| 判据 | 内容 | 挡的是 |
| --- | --- | --- |
| D1 | 不许出现新的 MET→违例 | 头条没动但某域掉进红 |
| D2 | 配对数 ≥ 8（4 域 × setup/hold） | 名册残缺时空转念绿 |
| D3 | 相对余量掉过 25 % 的域数 == 0 | "拆东墙补西墙" |
| D4 | hold 配对 ≥ 2 | 只比 setup |
| D5 | A 有读数、B 变 NOWRITE 计数 == 0 | 改后丢了可读的东西 |
| D6 | 扇出行 ≥ 1 | 扇出那把工具没跑成 |

D5 的口径修正单独值得学（`:141-153`）：以前只要 **B 侧**这一格是 NOWRITE 就计数，
可 MMCM 的反馈钟与辅助输出（`clkfbout/clkfbout_1/clkout1_1/clkout2`）**本来就两侧都 NOWRITE**
——没有 endpoint 是正常的（`build/timing_summary.rpt:184-188` 就是这样），
于是合法配对被念成 `empty_in_B=8 RED`。真正要抓的是"A 有读数、B 变成空"。
`--self` 一共 11 条对照（`:51-92`），其中 `control_gain_line_shape` 那一格
是复制驱动 A/B 第一次念出 GAIN 行才发现的双符号错（`+-31.7%绝对`）——
**收益行的形状本身是一条判据**。

### 6.5 两把尺子对同一份数据给不同判语 = 口径债

`build/evidence/r116_roster_diff.txt:1-12` 与 `那一轮的逐轮页`
写的是同一件事：D3 用的是 25 % 门槛、给 GREEN；而预登记的 A2/A3 是严格口径
（任何一格 rel_margin 不许变小）。同一份数据、两个判语，处理方式**不是**改宽任何一方，
而是把严格判据独立成件、按它判交付，同时把"判据阈值不一致"登记成**口径债**
（判定书 `build/r117_verdict_declined.txt:13` 末句就写着这件事记 `ISSUES #328`，
交付侧的警告行在 `那一轮的逐轮页`）。

### 6.6 r117：赢一格跌四格的那一次实测

这是"全局 WNS 不算涨跌"最好的一个正例，因为它**头条是涨的**。
`build/r117_verdict_declined.txt`（全文 14 行）与 `那一轮的逐轮页` 同一份数：

| 域/类型 | r114 | r117 | 读法 |
| --- | --- | --- | --- |
| `clk_fpga_0` setup | 1.850（18.50 %） | **2.104（21.04 %）** | 赢 +0.254 |
| `clkout0_1` setup | 3.630（18.15 %） | 3.353（16.77 %） | 跌 −0.277 |
| `eth_rxc` setup | 0.739（9.24 %） | 0.615（7.69 %） | 跌（全设计最紧那格） |
| `eth_rxc` hold | 0.052 | 0.044 | 跌（全设计最薄那格） |
| `sys_clk` setup | 14.876 | 14.815 | 跌 −0.061 |

机制**无可疑**：`impl_1/runme.log` 里 `R117HOOK ... pins_before=239 / pins_after=1
replica_cells=10`（`那一轮的逐轮页`，判定书 `build/r117_verdict_declined.txt:3` 有 `pins_after=1 replica_cells=10`），
新增端点 +10 == replica 10 颗 == 寄存器 +10 这个**闭合等式**也成立
（`那一轮的逐轮页`）。
所以结论不是"这刀没生效"，而是**"生效了，但代价落在最紧的两个域上"**——
与 r115 那夜 C1 复制刀被判负的同一个形状（`门禁逐条页`：
`REPLICA_CELLS` 0→310、三根同名网只有 1 降 2 升、FF 8188→8463、G1 红 4 格）。
两次的靶子不是同一根网（`门禁逐条页` 特意做了区分），
所以 C9 不是重复记账。

**机制与收益是两件事**这条纪律在这一刀上表现为一个具体标签：
判据 A1 规定"机制没动要打 `MECHANISM_INERT`，不许汇报成'没有收益'"
（`那一轮的逐轮页`）。负结果要归因，否则下一次会有人把
"我的钩子没咬住"读成"这条路不通"。

### 6.7 r118：B1 逐格 SAME 的正确读法

`build/evidence/r118_strict_b1.txt`（9 行）：8 对逐格与 r114 **逐位相同**、`losses=0`。
`那一轮的逐轮页` 立刻把这行的读法钉死：
**它不是"τ 改了但时序没变"的巧合**，而是 `IDELAY_VALUE` 只动 I/O 单元抽头、
不动片内任何一条锥，所以片内名册本就该逐位复现；
它顺带给的那件是**放置与布线在这套工具上可复现**。
τ=31 的收益在片外（眼心余量 +0.315 ns）。
所以 r118 的定位写成"一版把收口到达窗推到实测眼心、且名册对 r114 逐格不劣化的构建"，
判据是 **B1 不劣化 + B4 发布门 + 板级复验**，**不是"WNS 变好"**——
`那一轮的逐轮页` 那句"把 τ=31 写成 WNS 收益就是规矩 35 禁的那种读法"
就是这一节的全部答案。

---

## 7. I/O 覆盖率台账：把"其他地方的时序"变成逐端口可对账的清单

### 7.1 为什么三端对齐

`build/check_io_timing_coverage.py:4-7` 给了动机：`check_timing` 每轮只给**计数**，
而计数会随端口增删自己变，没人盯 ⇒ 一条新出厂接口可以静悄悄地
"到达/驱动时刻被当理想"，而屏上一切照旧。于是它把三端钉在一起：

```
A 源码端：system_top 的端口表 + src/constraints/*.xdc 里点到名的端口
B 报告端：归档的 timing_summary.rpt 里 check_timing 那四个数
C 基线端：钉死的一组基准计数（BASELINE = in_bare 5 / in_fp 2 / out_bare 6 / out_fp 6）
```

`:8-9` 那句是这把尺子的设计约束（规矩 46）：
**一条形状行的两个操作数不许同源**，否则就是自证。所以 `I1` 故意做成
"源码数出来的裸输入位数 == 报告的 HIGH 输入数"——**两边同源不同法，才可能撞出红**（`:14`）。
A 端从 RTL 正则解析端口表并按位宽展开（`:51-67`），XDC 端只认
`set_input_delay / set_output_delay / create_clock / set_false_path` 四类命令里点到的名字（`:76-94`）。

### 7.2 判据 I1–I10

`:206-296` 那一段逐条实现，代码里 `j()` 的 tag 就是行号：

| 判据 | 要什么 | 额外说明（写在代码注释里的理由） |
| --- | --- | --- |
| I1 输入侧对账 | 源码裸输入位数 == 报告 HIGH 输入数 | `:214-215` |
| I2 假路侧对账 | 假路输入位数 == 报告 MEDIUM 数（`key1_n/key2_n` = 2） | `:216-217` |
| I3 输出侧覆盖 | 任何用户输出/双向端口都不许是 BARE——要么给窗、要么写**带理由的豁免** | `:218-219` |
| I4 基线不涨 | 四个数任何一项都不许多于基线 | 新接口进来就红，`:220-222` |
| I5 射程地板 | 被数到的用户端口位数 ≥ 20 **且** 报告四项都解析到 | **空转不许当绿**，`:223-224` |
| I6 豁免反买通 | 每条豁免理由 ≥ 30 字，且被豁免的端口必须在 RTL 里真存在 | 幽灵豁免与空理由都判红，`:225-230` |
| I7 verbose 件自对账 | 每段 `There are N …` == 该段点名行数，且小标题 == HIGH+MEDIUM 两段之和 | 见 7.3 |
| I10 名字级两向对账 | 工具 HIGH 名单 vs 我从 RTL+XDC 推的那份：输入侧集合相同、输出侧无幽灵、我的 BARE 全被点名（差分负端除外） | 见 7.3 |
| I8 输入名字级 | 源码位展开 == `report_methodology` 的 TIMING-18 点名集合，**名字级**相等 | 少一个名字就红，"不许靠计数蒙对"，`:270-272` |
| I9 输出名字级 | TIMING-18 点名的每个输出引脚必须落进 BARE 或带理由 EXEMPT **两个集合之一** | `:273-285` |

I9 那条"两个集合之一"是后来改的，而且改的理由很实：
原来要求"工具点名的输出引脚必须落进我判 BARE 的集合"，
于是给 `led[0]/led[1]` 加了**有理由的豁免**反而变成假幽灵、判红。
反买通的两处一起保住：I6 管理由字数与端口真实性；
`--self` 注入的 `not_a_pin[9]` 两个集合都不在 ⇒ **仍然必须红**（`:275-280`、`:369-376`）。

### 7.3 单位坑：先问"这两个数是不是同一个东西"，再问差不差

`:109-118` 那段是这把尺子最难的一格，而且它**曾经把结论写反过**，值得完整讲一遍。

先说坑本身。`check_timing` 在同一个桶里给两个数：小标题 `6. checking no_output_delay (12)`，
明细 `There are 6 ports with no output delay specified. (HIGH)`。看到 12 与 6 的第一反应是
"一个是引脚、一个是端口对象"，于是有人（这里就是写这份文档的人自己）把它钉成常量：
`GAP_OUT_BARE = 6`——"源码位数 12 减报告 6 等于 6"。**差值被钉成常量之后那条判据永远绿，
而它什么都没对账**（`:29-30` 记着这条错账以及它为什么错，#251 同族）。

后来把归档的 `-verbose` 件**逐行数过**（`build/check_timing_verbose.rpt`），实情是另一回事：

| 小标题 | HIGH 点名 | MEDIUM 点名 | 两段的行号 |
|---|---|---|---|
| `no_input_delay (7)` | 5 | 2 | `:55`（5 行名字 `:57-61`）／`:63`（`:65-66`） |
| `no_output_delay (12)` | 6 | 6 | `:71`（`:73-78`）／`:80`（`:82-87`） |

⇒ **两边是同一个单位**（每个端口位算一个，各占一行名字；`eth_rxd[0]`…`eth_rxd[3]` 是四行），
差的不是单位而是**射程**：小标题数 HIGH + MEDIUM 两段，明细一行只给其中一段。
所以那个"12 − 6 = 6"的差值本来就是 MEDIUM 那 6 个被 `set_false_path` 盖住的口，
不是量纲差。**教训不在"单位错了"，而在"看见两个不相等的数就假设它们量纲不同，
是比钉常量更便宜、也更难发现的糊账方式"**——正确动作是先问第三个数（名字有几行）。

于是判据换成两条真能对账的（判据从 9 条变 **10** 条）：

- `I7_verbose_selfreconcile`：每段 `There are N …` 必须等于该段下面点名的行数，
  且小标题必须等于 HIGH+MEDIUM 两段之和。真件 `no_input_delay=7/5+2 no_output_delay=12/6+6` ⇒ **GREEN**。
- `I10_names_vs_source`：**名字级两向**对账——工具那份 HIGH 名单 vs 我从 `system_top` 端口表 + XDC 推出来的那份。
  输入侧要求集合**逐个相同**（实测 `eth_rx_ctl` + `eth_rxd[0..3]` 两边一致）；
  输出侧要求工具点名的每个名字都在我判 BARE ∪ 带理由 EXEMPT 里（无幽灵），
  并且我判 BARE 的每个引脚都被工具点名，差分对的负端按实测口径除外
  （`tmds_clk_n`、`tmds_data_n[0..2]` 在 RTL 里存在、在名单里没有，这是从那份件读出来的 Vivado 口径）⇒ **GREEN**。

`--self` 的对照因此重排成 **12 条**，全部**按标签取判定行**（`jt(res, tag)`）而不是 `judged[7]` 这种硬编号——
新判据插在中间就会让硬编号打到别人的判定行上，写这份文档的人又一次先中招：三条对照当时"全绿"，
实际打的是一条与自己无关的行。三条坏件对照分别是：小标题 12→11 ⇒ I7 红；
从 HIGH 名单删一行（`tmds_data_p[2]`）⇒ I7 与 I10 **同时**红（同一事实的两个视角）；
往名单里塞 `not_a_pin[9]` ⇒ I10 红；件不存在 ⇒ 两条一起 REFUSE。
"能判红的判据也要能判绿"这条规矩现在由第 6 条对照在**真实归档件**上验：I7 与 I10 必须都判得出绿。

还有一个纯工具层的坑，写在这里因为它会造出**假红**：
`verbose_lists()` 必须认得"任何 `N. checking …` 行都重置游标"（否则 `multiple_clock` 那几段
会被算进上一段的名单），以及"认不出 `(HIGH)`/`(MEDIUM)` 的行**不许**改动当前桶"
（`:89` 那句 `There are 0 ports … but with a timing clock defined on it` 曾把
`declared_bare=6` 覆盖成 0，读出来就是一条莫名其妙的红）。

顺带把尺子的**默认输入件**改了：原来不传参数时读归档的 `build/evidence/r112_bit/timing_summary.rpt`，
现在读盘上现行的 `build/timing_summary.rpt`（`IODEBT_SUM` 可覆盖）。两份的四个数实测相同（5/2/6/6），
所以这不是改判据而是改射程——**默认件写死成历史快照，判据念出来就永远像"上一版还没回归"**。

`report_methodology` 是第三个来源，也是**唯一点名**的那个：
`build/methodology.rpt:36` 的 `TIMING-18 | Warning | Missing input or output delay | 7`，
明细 `:2245-2273` 逐条给引脚名——5 条输入（`eth_rx_ctl`、`eth_rxd[0..3]`）
+ 2 条输出（`led[0]`、`led[1]`）。所以 I8 能做名字级对账，
而 I9 只能做子集判（`tmds_*` 那 4 个 TIMING-18 没点名，是留给 `-verbose` 的开放项，
`:273-284` 明写"念出来不判绿也不假判红"）。
**注意这三把尺子的数不许相减**：`那一轮的逐轮页` 那行专门警告
`report_methodology` 的同一族只报 TIMING-18 = 2（checks/pins 口径），
"不与 6 相减"。

### 7.4 豁免表随尺子走

`:36-46` 的 `EXEMPT` 有 7 条，每条格式是 `端口名模式|理由`，注释 `:35` 写"不许'临时/先这样'这类空话"。
三条是时钟对象本身（`sys_clk`、`eth_rxc` 是 `create_clock` 的对象，时钟端口不参与
`no_input_delay`；`:39-40` 并且把 `eth_rxc` 那一路的**真正的账**指向 IDDR 采样窗），
两条是 PS 硬块（`DDR_*`、`FIXED_IO_*`），三条是 2026-10-05 逐条带行号补的定性：

| 模式 | 理由里给的出处 | 对照读过的代码 |
| --- | --- | --- |
| `led` | `rk_zynq7020.xdc:10-11` 是 `LVCMOS33` 直驱、无接收时钟 ⇒ `set_output_delay` 没有参考对象 | 两行确实写 `IOSTANDARD LVCMOS33` |
| `eth_mdc` | 顶层钉成常量 0（`system_top.v:117`）⇒ 不存在寄存器到管脚的路径 | `src/rtl/top/system_top.v:117` 确为 `assign eth_mdc = 1'b0;` |
| `eth_mdio` | 顶层高阻（`system_top.v:116`）⇒ fabric 既不驱动也不采样 | `src/rtl/top/system_top.v:116` 确为 `assign eth_mdio = 1'bz;` |

`:44` 还留了一条**综合告警的出处**（`Synth 8-3917 port eth_mdc driven by constant 0`），
而那条告警的原文注释在 `src/rtl/top/system_top.v:113-115`，
里面写着"这是**陈述而不是缺陷**；要真做 PHY 寄存器读写得另起位时序机，那一版再来消它"。
这三条与 `屏侧实测记录`（D4 行"LED 的对外无窗登记，待裁决"）
之间有一个未合上的口子：**尺子里已经把它们当豁免，台账里仍标待裁决**。
读到这里应该得出的结论不是"谁错了"，而是这两处的口径不同——
I6 判的是"豁免有没有理由、端口真不真"，D4 判的是"这件事算不算一次放宽"。

### 7.5 这把尺子的射程边界

`:26` 只把 `rk_zynq7020.xdc` 与 `clock_groups_impl.xdc` 列进 `XDCS` ⇒
**两份环境门控候选件里的 `set_input_delay` / `set_output_delay` 不计入覆盖**。
这与默认构建不加载它们是一致的，但也意味着：**一旦有人打开
`VP_R116_IO_WINDOW`，I1/I2 与 I4 就会与报告撞红**——
那正是 I1 设计要抓的方向（"新接口进来就红"），不是尺子坏了。
另一条射程是它的基线（`:27-28`）钉在 r112 归档件上，
所以 I4 念的是"不许比那一版多"，而不是"绝对为 0"。

---

## 8. 声明的 vs 量过的：本章唯一该被记住的一张表

| 条目 | 状态 | 证据 |
| --- | --- | --- |
| 三组异步时钟（`eth_rxc` / `clk_fpga_0` / `sys_clk`+生成钟） | **声明**，并且拆分本身是量过的 | `src/constraints/clock_groups_impl.xdc:28-31`；合回去判负见 `刀口台账` |
| `clk_pix` 与 `clk_pix5x` 故意同组 | **声明**（理由是同步路径不许漏检） | `src/constraints/clock_groups_impl.xdc:25-26` |
| `set_clock_uncertainty -hold 0.800` | **声明 + 加严过程有读数**（0.5 档只做到 WHS +0.051） | `src/constraints/rk_zynq7020.xdc:46-50` |
| `eth_tx_*` 那四条 false path | **声明，理由不可查** ⇒ 标"待复核债务" | `时序债务账` |
| RGMII 输入窗 [1.2, 2.8] | **数有出处**（原理图 + Table 10/11 + Table 60 发射端两行） | `src/constraints/r116_rgmii_input_window.xdc:7-20` |
| τ=31 的眼心 | **量过并采纳**：同一份 DCP 扫 0…31，正式构建逐格命中预测（−0.870/−0.846） | `build/evidence/r115_window/probe3_console.txt:188,192`；`那一轮的逐轮页` |
| τ=31 的板侧裁决 | **未闭合**：带流 `drop_words=0`，但 `pkt_err=?`、`frames_bad=?` | `收口输入窗模型` |
| 把窗绑进发布物 | **量过并拒绝**（4 条发布硬门机械判红） | `build/evidence/r116_roster_diff.txt:1-12`、`build/tcl/build_system_axigpio.tcl:44-56` |
| C1 / C9 复制高扇出驱动 | **量过并拒绝**（两次，靶子是两根不同的网） | `门禁逐条页`、`build/r117_verdict_declined.txt` |
| Pblock 圈 `u_cdc` | **量过并拒绝**："买了风险，没买到东西" | `开发台账` |
| Pblock `SLICE_X40Y20:SLICE_X66Y52` | **没做成**（`Place 30-439` 进位链半内半外）⇒ 按 G11 只能算"没做成"，不是负结果 | `report/40-optimization.md:119`（V7）、`门禁逐条页` |
| 帧缓存拆块换 setup（省 RAMB36） | **量过并拒绝**：`eth_rxc` +0.516→+0.182、级数 4→9 | `report/40-optimization.md:114`（V2） |
| `wr_full` 加 `max_fanout` | **量过并回滚**：WNS −0.062→−0.192、失败端点 28→34 | `src/rtl/eth/dc_fifo.v:37-39` |
| `place -directive Explore` | **量过**：与对照一格不差 ⇒ 排除法收益，不进首页成绩 | `report/40-optimization.md:120`（V8） |
| IDDR 捕获钟换短钟（C3） | **量过并拒绝**（副本树 S1 仍红、UU 脱离派生钟覆盖面） | `刀口台账` |
| BUFIO 快角 DCD | **未量**（⇒ "换短钟也关不掉"这句不许写） | `那一轮的逐轮页` |
| HDMI `set_output_delay` 窗形（两种参考） | **量过并拒绝**：−3.48 与 −4.90，根因是量纲用错 | `build/evidence/r119_xdc_loads_probe3.txt:113`、`build/evidence/r119_xdc_loads_probe4_pinclk.txt:113`、`屏侧实测记录` |
| 钟↔数据、P↔N 离散 | **量过**：0.065 / 0.001 ns，上限 4.000 / 0.300 | `build/evidence/r119_window_check.txt:8-10` |
| 眼图掩模 / 抖动 / 占空比 / 上升下降 | **未实测**（SDC 里没有容器，需要仪器与批准） | `屏侧实测记录`（D3） |
| 6 个输出端口的对外窗 | **未覆盖**（H5 判红项，非 0） | `build/check_timing_verbose.rpt:71-78` |
| `led[0]/led[1]`、`eth_mdc/eth_mdio` 的"不查" | **豁免（带理由）**，与 D4 的"待裁决"口径不同 | `build/check_io_timing_coverage.py:41-45` |
| 全设计 WNS 0.739 / 0 失败端点 | **测量**，但按规矩 35 不充当任何一刀的收益或损失 | `build/timing_summary.rpt:149-154` |

这张表里唯一一条**四处都写同一句话**的，是"未覆盖 ≠ 满足"
（`src/constraints/r116_rgmii_input_window.xdc:5`、
`那一轮的逐轮页`、`时序债务账` 的 H5、
以及 I3/I5 的地板设计）。这套方法的骨架其实就这一句，
其余全是为了让这句话不许被绿灯糊过去。

---

## 9. 自查清单

1. 八只钟里哪两只是别人 create 的？这一事实决定了哪条约束必须晚一个阶段？
   （1.2、`时序债务账`）
2. Inter Clock Table 为什么只有两行？这说明 `set_clock_groups` 生效还是失效？
   （1.3、`build/timing_summary.rpt:196-200`）
3. `get_clocks -quiet` 为什么救不了一条取不到对象的命令？举两个不同的命令名。
   （2.2、`src/constraints/rk_zynq7020.xdc:43-45,62-75`）
4. 给 hold **加**不确定度为什么能修"每次重建掷硬币"？验收口径是多少、r79 量到多少？
   （3.1、`src/constraints/rk_zynq7020.xdc:39-50`）
5. 为什么窗要写成正的 1.2/2.8 而不是负数？工具的两条 Requirement 行差别在哪？
   （4.3、`build/evidence/r116/r116_io_hold.rpt:22` 与 `build/evidence/r116/r116_io_setup.rpt:22`）
6. 156 ps/拍、63 ps/拍、88 ps/拍 三个数分别是怎么来的？为什么不能拿抽头换算采样点？
   （4.4、`src/rtl/eth/rgmii_rx.v:8-10,22`）
7. "这一族关不掉"的证据是"扫遍 0…31 都不行"还是别的？把那条不等式写出来。
   （4.6、`收口输入窗模型`）
8. τ=31 的报告余量与硅片鲁棒性为什么反向？覆盖百分比各是多少？
   （4.8、`收口输入窗模型`）
9. 为什么 `0.20 Tcharacter` 不能写进 `set_output_delay`？同量纲的问法是什么？
   （5.1–5.3、`屏侧实测记录`）
10. `noise_ns = 0.000` 与"摆幅 0.4 ns"为什么不矛盾？各挡住哪种声明？
    （6.1、`门禁逐条页`、`开发台账`）
11. 名册差分为什么要先比"时钟名单 + 扇出节"再比 slack？举那次假 `big_loss=8` 的错。
    （6.4、`build/timing_roster_diff.sh:101-119`）
12. r117 头条涨了 0.254 ns，为什么仍判 DECLINED？机制标签 `MECHANISM_INERT` 防的是什么？
    （6.6、`build/r117_verdict_declined.txt`、`那一轮的逐轮页`）
13. `clkfbout` 两侧都 NOWRITE 为什么是正常的？D5 原来错在哪一步？
    （6.4、`build/timing_summary.rpt:184-185`、`build/timing_roster_diff.sh:141-153`）
14. `checking no_output_delay (12)` 与 `There are 6 ports …` 为什么**不是**两个单位？把它们的差钉成常量错在哪里？
15. I9 为什么要允许"带理由的豁免"这个第二个集合？I10 的"方向一"与"方向二"各挡住哪种漂移？
    （7.2–7.3、`build/check_io_timing_coverage.py:247-266,273-285,340-343`）
15. 这份台账只把哪两份 XDC 算进覆盖？打开候选窗之后哪几条会撞红，那是尺子坏了吗？
    （7.5、`build/check_io_timing_coverage.py:26`）

## 10. 未量 / 需要复跑才能更新的话

- 这里没有重跑任何一把尺子（仓对这一章只读），所以 `check_io_timing_coverage.py`
  **当前的逐条判定没有现场读数**；7.2/7.3 里凡涉及"这一格现在红/绿"的话，
  出处都是判据定义行与归档件，不是新跑的判定。要更新就跑
  `python build/check_io_timing_coverage.py`（不传参数时它现在读**盘上现行**那份
  `build/timing_summary.rpt`，可用 `IODEBT_SUM` 覆盖；过去这里写死成归档的 r112 件，
  等于让"当前"这句话读历史）与它的 `--self`（**12 条对照**，全部按标签取判定行）。
  最近一次的实读数在 `build/evidence/1006_d3/`：判 10 条 = 9 绿 / 1 红（红的那条仍是
  `I3_output_covered bare_out_ports=4`）。
- `build/evidence/r119_xdc_loads_probe2.txt`、`r119_clock_networks.rpt`、
  `r114_idelay_sweep_console.txt`、`r114_sweepb/`、`r115_rtl8211f_delay_source.txt`、
  `r114_after_roster.txt`、`r115_fanout_cmp.py` 这些被文档点名的件已不在盘上
  （`round_r116.md:5` 记了精简原因）。引用它们的段落都是**抄件**；
  `开发流水账` 里三份被引用的名册 tsv（`roster_baseline.tsv`、`roster_round115.tsv`、
  `roster_round116.tsv`）仍在，可以直接读。
- `r119_hdmi_source_window.xdc` 那一刀**已经量过了**（5.6 节）：带 `VP_R119_TMDS_WINDOW=1` 的隔离构建
  跑完，窗管用（HIGH 6→3、零违例）但四个域同时变差 ⇒ **判 DECLINE，不进默认构建**。
  所以本章对它的口径是"量过并拒绝的候选件"，不是"还没做"；
  引用它必须点名件（`build/evidence/1006d_*`），因为那份构建本身被 `.gitignore` 挡在 `build/isolated_*/`。
- `放松台账` 的数据行数仍是 0 ⇒ 任何"放宽"都没被批准过；
  这一条决定了 4.7 与 3.1 两节里"双重计但不动"的处理方式。
- 板侧仍是唯一真判据这一句没有被削弱：
  RGMII 那一族最终要 `bad`/`drop_words` 判（`src/rtl/eth/rgmii_rx.v:10-11`），
  而 `IDELAY_TYPE = "FIXED"` 让运行时扫档不可能（4.8）。
