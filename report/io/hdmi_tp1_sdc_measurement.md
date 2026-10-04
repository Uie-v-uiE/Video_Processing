# HDMI 源端 TP1 的窗在 SDC 里到底怎么表达 —— 两次 load 实测与一次量错方向的记录

日期：2026-10-04。工具：Vivado 2025.2.1 (64-bit) build 6403652。器件：`xc7z020clg484-2`。
所有读数都是**只读探针**打在实现检查点上得到的，本轮**没有把任何新约束带进构建，也没有重建产物**。
被动的检查点：`vivado_system/zynq_video_sys.runs/impl_1/system_top_opt.dcp`（mtime 04:30）与
`system_top_routed.dcp`（mtime 04:36）。板上与仓库当前的位流摘要实测 `build/system.bit` = `cd04907e1369…`（= r118），
这两个 DCP 与它出自**同一个 impl_1 运行目录、时间戳连续**——这是"目录与时间戳的对应"，
不是工具出具的指纹绑定，所以这句话记为**推断**，严格绑定要等 `docs/run-queue.md` 里 P15a 的来源卡补齐。

规范侧的数字与逐条出处在 `report/io/hdmi_cts_source_window.md`（三版 HDMI 规范本体 + Keysight/Tektronix 复述）。
本文只回答一件事：**这些数能不能变成约束，以及变成什么。**

---

## 一、第一次 load：把 ±0.20 `Tcharacter` 当输出窗挂到片内串行钟上（件 `build/evidence/r119_xdc_loads_probe3.txt`）

先纠正一个我自己的错：**`.xdc` 里不能写 Tcl 控制流**。
第一版候选件在文件里写了"读不到参考钟就 REFUSE"的守卫，Vivado 解析时逐行报
`CRITICAL WARNING: [Designutils 20-1307] Command 'if' is not supported in the xdc constraint file.`
（`if` 两行 + `puts` 一行，件 `build/evidence/r119_xdc_loads_probe2.txt` 第 42–56 行），
**守卫被整块跳过，`read_xdc` 仍然 rc=0**——防呆变成"防呆失效且不报错"，比没有守卫更危险。
守卫因此挪回 Tcl 脚本侧，`.xdc` 改回纯 SDC（与已被量过的 `src/constraints/r116_rgmii_input_window.xdc` 同一形状）。

改成纯 SDC 之后（`src/constraints/r119_hdmi_source_window.xdc`：
`set_output_delay -clock clkout1_1 -max 4.000` / `-min -4.000` 打在 `tmds_data_p[*] tmds_data_n[*]`）实测：

| 端口 | load 之前 | load 之后（原文行摘录） |
| --- | --- | --- |
| `tmds_data_p[0]` | `Slack: inf`、`Path Group: (none)` | `Slack (VIOLATED) : -3.482ns`、`Path Group: clkout1_1`、`Requirement: 4.000ns` |
| `tmds_data_p[1]` | 同上 (none) | `-3.458ns`，其余同 |
| `tmds_data_p[2]` | 同上 (none) | `-3.474ns`，其余同 |
| `tmds_clk_p` | 同上 (none) | 仍是 `Slack: inf`、`Path Group: (none)`（钟道自身不挂窗，符合设计） |

**这一步收获了两件事**：① 约束真的挂上了（`Path Group` 从 `(none)` 变成有钟，这是工具自己的行为，不是属性读取）；
② 它**立刻判红 −3.48 ns**。红不是"设计不合格"的证据——见第三节为什么这个量纲本来就用错。

## 二、第二次 load：把参考钟定在 TMDS 钟脚上（件 `build/evidence/r119_xdc_loads_probe4_pinclk.txt`）

单变量对照（`src/constraints/r119b_hdmi_tp1_pinclk.xdc`，只是探针输入，不进任何构建开关块）：
`create_clock -name r119b_tmclk -period 20.000 [get_ports {tmds_clk_p}]`，窗宽仍是规范的 0.20 `Tcharacter` = 4.000 ns。

| 端口 | load 之后 |
| --- | --- |
| `tmds_data_p[0]` | `Slack (VIOLATED) : -4.897ns`、`Path Group: r119b_tmclk`、`Requirement: 4.000ns  (r119b_tmclk rise@20.000ns - clkout1_1 rise@16.000ns)` |
| `tmds_data_p[1]` | `-4.873ns`，其余同 |
| `tmds_data_p[2]` | `-4.890ns`，其余同 |
| `tmds_clk_p` | 仍 `Slack: inf`、`Path Group: (none)` |

工具自己把这条路径的"要求时间"展开成 `脚上钟的沿(20.000) − 片内钟的沿(16.000) = 4.000 ns`，
也就是说：**它按"外部接收器用 TMDS 钟在沿附近采样数据"来算 setup**。这正好暴露了量纲问题。

## 三、为什么 `set_output_delay` 不是这个规范量的正确容器（结论，带证据）

1. 规范行的原文是 **`Inter-Pair Skew at Source Connector, max | 0.20 Tcharacter`** ——
   它约束的是**两个输出脚到达时刻之差的上限**，是一条**单边离散量**（skew），
   不是"数据必须在参考沿前后某窗口内保持稳定"的**采样窗**。
   HDMI 1.3 第 45 页还专门写了源端眼图掩码"specifies the clock to data jitter indirectly"，
   即规范自己**没有**给"钟↔数据 setup/hold 窗"这个参数（取证文档表行 #13）。
2. `set_output_delay` 的语义（SDC 通用语义）是后者：它把参考时钟的沿当外部采样沿，于是
   边沿对齐的 TMDS 输出被要求"在一个位周期内准备好"，工具给出的 `Requirement: 4.000ns` 就是这么来的。
   对 50 MHz 像素钟这一档，片内启动钟周期 4.000 ns、`Tcharacter` 20.000 ns，
   把 20% 的离散量当 ±窗塞进去，等于要求数据在 4 ns 内落到采样沿附近 ⇒ 必然造违例。
3. 因此**不能**用"挂窗后名字册变红"来宣称设计不满足 CTS，也**不能**用"放宽窗让它绿"来宣称满足。
   同量纲、工具能表达、且能对成品直接问的问法是：**钟脚↔数据脚的时钟到引脚延迟离散 ≤ 0.20 `Tcharacter`（4.000 ns）、
   P/N 对内离散 ≤ 0.15 `Tbit`（0.300 ns）**。
   这一问由只读探针在**已布线**成品上回答：`build/tcl/probe_tmds_pin_skew.tcl` 逐脚打印
   `Data Path Delay`（字段位置先量过形状：`build/evidence/r119_shape_tmds_data_p_0_.txt` 第 22 行原文
   `Data Path Delay:        2.033ns  (logic 2.032ns (99.951%)  route 0.001ns (0.049%))`；
   第一版探针找 `data arrival time` 这个**不存在的行**，于是十脚全打 `NO_ARRIVAL_LINE`，
   件 `build/evidence/r119_pin_skew_probe.txt` 就是那次"尺子没量形状"的凭据）。
   读数件 `build/evidence/r119_pin_skew_probe2.txt`，判读尺子 `build/r119_window_check.mjs`（W7–W10）。

## 四、成品实测：离散量（这一节是**量出来的**，件 `build/evidence/r119_window_check.txt`）

| 判据 | 规范上限与出处 | 实测（r118 已布线成品） | 判定 |
| --- | --- | --- | --- |
| W7 互对离散 max 角（数据道 vs 钟道，clock-to-pin 延迟差） | 0.20 `Tcharacter` = **4.000 ns**（HDMI 1.4 Table 4-24；1.3/1.1 同值） | 逐道 `[−0.041, −0.065, −0.049] ns`，最差 **0.065 ns** ⇒ 余量 61× | PASS |
| W8 互对离散 min 角（同一件事换角再判，成对） | 同上 | 逐道 `[−0.040, −0.064, −0.048] ns`，最差 **0.064 ns** | PASS |
| W9 对内离散（每对 P/N 之间） | 0.15 `Tbit` = 0.15 × 2.000 = **0.300 ns** | 四对逐对 `[−0.001 ×4] ns`，最差 **0.001 ns** | PASS |
| W10 计数地板 | 数据道 3/3、P/N 对 4/4、钟道两角齐（缺一条不许判通过） | 全齐 | PASS |

原始逐脚读数（`build/evidence/r119_pin_skew_probe2.txt` 摘录）：`tmds_clk_p` max 2.074 / min 1.034；
`tmds_clk_n` 2.075 / 1.035；`tmds_data_p[0]/[1]/[2]` max 2.033 / 2.009 / 2.025，min 0.994 / 0.970 / 0.986；
各自 `_n` 与 `p` 差 0.001 ns。`led[0]/led[1]` 是 8.880/8.613 ns，但它们的启动钟是 `sys_clk`（另一条域），
**不参与、也不能拿去比 TMDS 的窗**（取证文档表行 #18：LED 没有可引用的对外窗）。

**这三行能说什么、不能说什么**（同一条读数说明，别越界）：
- 能说：在 r118 这个已布线成品上，**FPGA 内部（串行器时钟脚 → 封装脚）**的钟↔数据离散 ≤ 0.065 ns、
  P↔N 离散 ≤ 0.001 ns，都在规范上限的 1/60 与 1/300 以内。
- 不能说：连接器（TP1）上的总离散。板级走线、连接器与线缆的离散不在这条路径里，
  规范那一句写的对象是 Source Connector ⇒ 端到端余量还要减掉板级项（本板未量，`【未实测】`）。
- 不能说："过了 CTS"。CTS 的判据是眼图掩码 + 抖动 + 占空比 + 上升下降时间（见第六节 D3），
  这些在 SDC 里没有容器，只能仿真与示波器。

尺子本身的可信度：`node build/r119_window_check.mjs --self` 造 10 条畸形输入，**10 条各自动红**，
另 2 条"缺输入"用例报 `NOT_MEASURED`（不是通过）。
连带红如实登记一条：给 W7 造的畸形（把 `tmds_data_p[1]` 的 max 读数推到 6.300 ns）**同时染红了 W9**，
根因是同一条读数既进互对差也进 P/N 对差——这不是判据串扰，是数据共用一行，按规矩逐条列出而非削弱反例。

## 五、与两个候选件的关系（别把它们当"CTS 校验"）

`src/constraints/r119_hdmi_source_window.xdc`（窗形，已测会造 −3.48 ns 违例）与
`src/constraints/r119b_hdmi_tp1_pinclk.xdc`（脚上钟形，−4.90 ns）**都默认不加载**，
保留的意义是"这一族规范量不能这样进 SDC"的反例凭据；第四节的离散量才是与规范同量纲、且能对成品直接问的形式。
两件的处置（保留 / 删除）需要队伍裁决，已进 `docs/questions-for-team.md` 的合并范围（D2）。

## 六、还欠什么（写在这里，免得下一轮把它当已完成）

| 编号 | 欠的东西 | 为什么不能省 | 状态 |
| --- | --- | --- | --- |
| D1 | 在**已布线**成品上量钟脚↔数据脚、P/N 脚的到达时刻离散，并对回 0.20 `Tcharacter` / 0.15 `Tbit` | 这是与规范同量纲、且工具能直接答的问法 | **已量**：最差互对 0.065 ns（上限 4.000）、对内 0.001 ns（上限 0.300），件 `build/evidence/r119_window_check.txt` 判 10 项红 0；但只覆盖 FPGA 内部到封装脚，板级走线未量 |
| D2 | 两个 `set_output_delay` 候选件的处置：留在 `src/constraints/` 当"这一族量不能这样表达"的反例凭据，还是删 | 留着必须写清"默认不加载且已知会造违例"，否则下一个人会当真挂上去 | 待队伍裁决（已进 `docs/questions-for-team.md` 合并范围） |
| D3 | 上升/下降时间 75 ps…0.4 `Tbit`、占空比 40/50/60 %、钟抖动 ≤0.25 `Tbit`（相对 4 MHz −3 dB 理想恢复钟）、眼掩码 0.25–0.75 UI × ±200 mV / 绝对 ±780 mV / 最小开度 400 mV | 这几条**不在 SDC 语义里**，只能仿真 + 示波器判 | `【未实测】`，需要仪器与队伍批准 |
| D4 | `led[0]`/`led[1]` 的"对外无窗"登记 | 它们是 `LVCMOS33` 直驱 LED，不在 HDMI 连接器引脚表里；写"不查"属于一次放宽，必须先进放宽账本（当前 0 条） | 待裁决 |

一句话给评审：**6 个输出端口里 4 对 TMDS 差分有规范原文窗数可用（已取到、三版规范核对一致），
其中"互对/对内偏斜"这一族已在本工程成品上量过（最差 0.065 ns 与 0.001 ns，上限 4.000 ns 与 0.300 ns）；
`set_output_delay` 那两次挂窗实测各造 −3.48 ns 与 −4.90 ns 违例，原因是量纲用错而不是设计不合格；
眼图/抖动/占空比/沿这几条 SDC 里没有容器，仍是 `【未实测】`。LED 两颗没有可引用的对外窗。**

