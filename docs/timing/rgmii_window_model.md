# RGMII 收口的窗到底该怎么建：把 −2.885 那条 hold 拆到每一项（r115 夜，23:30）

> **编号别名（先钉住，免得两份文档打架）**：这把"把捕获沿提前"的刀，在
> `docs/timing/cut_ledger.tsv` / `gates_G1_G12.md` / 本轮 README 里的正式编号是 **C3（根因 CLKTOPO）**；
> 而 `build/r115_capture_clock_plan.md` 把它叫 "C2"、丢弃副本树因此叫 `c2_scratch_1003`。
> **以 `cut_ledger.tsv` 的编号为准**；本文件下面提到 "C2 落地后" 指的是**同一把刀**（计划文件里的那个候选号）。
> 同一轮里出现两套 C 编号是我自己的账，已记 ISSUES #304。

这一页存在的理由：提示词 §7 L1 要求"剩余红路径的四段占比全部有报告出处"，而 `build/r115_capture_clock_plan.md`
里我自己标了一条 **未定**——"arrival/required 还差 0.155 ns 没逐项拆开"。现在拆开了，而且拆完之后，
**下一刀的目标值从 2.7 ns 变成 5.0 ns**。所有数字都抄自件，没抄的地方标"预测"。

## 1. 那条 −2.522 的全部分量（件 `build/evidence/r114_sweepB/rt_tap0_eth_rxc_hold.rpt`，17:40 跑，模型 b）

```
Source      eth_rx_ctl（输入端口，clocked by eth_rxc，rise@0 fall@4 period=8）
Destination u_eth/u_rgmii/u_rgmii_rx/u_iddr_rx_ctl/D（rising-edge IDDR，同一个 eth_rxc）
Requirement 0.000（eth_rxc rise@0 − eth_rxc rise@0）⇒ 同沿检查，不是跨半周期

arrival  3.476 ns = input_delay_min 1.500
                   + IBUF(eth_rx_ctl)     1.321
                   + IDELAYE2 IDATAIN→DATAOUT 0.655
required 5.998 ns = DCD 5.008
                   + Clock Uncertainty 0.835 (= ((TSJ²+TIJ²)^½ + DJ)/2 + PE + UU，UU=0.800 全部来自 rk_zynq7020.xdc:50)
                   + **IDDR (Hold_iddr_C_D) 0.155**        ← 那条"未定"就是它，来自报告正文最后一行
slack    −2.522 = 3.476 − 5.998
```

DCD 那 5.008 的构成也在同一份报告里，逐项对得上：
`IBUF 1.430 + 走线 1.873 + BUFG 0.085 + 走线 1.620 = 5.008`（`BUFG_inst` 就是 `rgmii_rx.v:51` 那一只）。

**所以那 0.155 不是没解释的余数**，是 IDDR 单元自己的 hold 时间；`−2.885`（模型 a，input_delay_min=−0.500）
与 `−2.522`（模型 b，+1.500）的差恰好 2.000 ⇒ 印证计划文件里的 F4：**整条曲线随窗外平移 1:1**。

## 2. 关键结论： deficit 不在数据侧，在"捕获钟被故意挪晚了 5.008 ns"这一项上

把 DCD 拆开看，这 5.008 里 **3.49 是网络延迟**（IBUF+走线+BUFG+走线），而数据侧只有 3.476 的总延迟。
也就是说 IDDR 的 C 脚比 D 脚的数据**晚到 ~1.5 ns**，hold 检查要求"数据不能比沿早到"，于是报负。

而板上不丢包（`bad=0`、1000M 实流量，见 `board/ACCEPTANCE.md` 与 r92 的签收）的物理解释在同一份数里：
D 脚上的数据在 **[3.476, 7.476]** 这一段是稳定的（下一个符号在 4 ns 后才改变），
捕获沿落在 5.008 ⇒ **距前一次跳变 1.53 ns、距后一次跳变 2.47 ns**，采样点在眼内。
⇒ 这不是"设计坏了没人发现"，是**同一个符号关系在两套口径下的两种读法**：
STA 的 hold 拿"同一 pad 沿"当发射沿，而这套结构是**故意把捕获沿推到数据眼中间**的。

## 3. 三条出路，只有一条能既建窗又不骗自己

| 出路 | 做什么 | 代价 / 风险 | 状态 |
| --- | --- | --- | --- |
| A 继续不建窗 | 现状（`src/constraints/` 里 `set_input_delay` 0 次） | H5 永远红；交付文档必须书面写明"为什么这一路没有约束"（这正是 UG949 I/O 规则要的那句话） | 债务，已在 `debt_ledger.md` §2 |
| B 把捕获沿**提前 ≈5.0 ns** | MMCM 负相移（−225° @ 125 MHz = 5.000 ns，35 步整除无取整误差），IDDR 与 fabric 仍吃同一只 BUFG ⇒ 保住 r92 的同树成果 | 多一只 MMCM；`eth_rxc` 的下游变成**派生钟** ⇒ 异步组必须按 `clock_groups_impl.xdc:29` 加 `-include_generated_clocks`，否则派生钟会被当成独立钟去和 `clk_fpga_0` 做 setup 分析（这正是 #18 的 WNS≈−6.7 假违例形状） | **正在丢弃副本树上量**（判据见下面第 4 节） |
| C 换参考沿 | 把窗声明在派生钟上 / 用 `set_data_check` 表达"数据 vs 数据"的窗 | 本机 `set_input_delay` **没有** `-setup/-hold`（A2 探针实测），改参考沿等于换被分析的对象 ⇒ 属于 H1 的"缩小作用范围" | 未试，需要用户批准才能碰 |

B 里那条"异步组加 `-include_generated_clocks`"**不是放松**：今天 IDDR 与 fabric 都在 `eth_rxc` 上，
那批路径本来就不与 `clk_fpga_0` 做时序分析；改完之后它们落在 `eth_rxc` 的派生钟上，加这个后缀只是**把同一个集合搬回去**。
不过按 H1/G3 的字面口径，凡是让被分析路径变少的改动都得进 `loosen_ledger.tsv` 并要有批准人——
所以这一条**记在台账里等用户签**，本轮不自作主张采纳。

## 4. 预先登记的判据（写在这份件产出的时刻，结果出来之后不许改口径）

副本树：`D:/Xilinx/Prj/pro/c2_scratch_1003`（起点 fp 与主树逐位相同：`files=80 top=56c269602e18 rtl=3969247aaf7f`）。
变量两处、缺一不可：`rgmii_rx.v` 的 MMCM + `rk_zynq7020.xdc` 末尾那 4 行窗。

- **S1 这一刀要关住的东西**：`eth_rxc` 域 hold 头条 **WHS ≥ 0 且 I/O hold 失败端点 = 0**
  （改前的红是 −2.885/模型 a、−2.522/模型 b，件 `r114_io_roll_console5.txt` 与本文件 §1）。
- **S2 机制有没有动**：`report_clock_utilization` / `report_clock_networks` 里 **MMCM 计数 +1**、BUFG 计数不变；
  计数没动就写 `MECHANISM_INERT`，不许写成"时序收益不成立"（附录 1 那条）。
- **S3 名册八对**（`build/r115_roster_build.py` 造表，逐域 G1+G2）：其余三域（`clk_fpga_0`/`clkout0_1`/`sys_clk`）
  不许从 MET 掉进违例；`eth_rxc` 的 **setup 不许变差**（同树整体平移，预测不变，变了就说明结构理解错）。
- **S4 债务方向**：`io_unconstrained_ports` 应从 **11 → 6**（这一刀只消输入侧 5 个），`unconstrained_endpoints` 仍 0。
- **S5 钟名**：派生钟的实名要能被 `-include_generated_clocks eth_rxc` 抓到；若综合把 MMCM 输出并回 `eth_rxc` 同名，
  也要在 CLOCKS_LIST 里说明，不许靠"CLOCK 名没变"当成通过。
- **不在这一轮判**：板侧 `bad`/`drop_words`（那要采纳时才付 D3+上板），眼睛判据仍归用户。
  所以 S1–S5 全绿也**只等于**"值得进正式一轮"，不等于"可以采纳"。

## 6. A1 的真件终于拿到了：本机就有 RTL8211F 的数据手册，窗的数字有了出处（23:44）

**先前状态**：候选件 `src/constraints/r114_io_async.xdc:39-43` 用的是 ±0.500 ns（RGMII 汇总页给的"沿对齐公差"），
并且文件里写着"本机取不到规范原文"。**这个说法现在被推翻了**：

- 手册就在本地：`D:/Xilinx/Resource/ZYNQ7020/Board_Resource/芯片手册/C187932_以太网芯片_RTL8211F-CG_规格书_REALTEK(瑞昱)以太网芯片规格书.PDF`
  （69 页，Track ID **JATR-8275-15 Rev. 1.4**）。取数方式：本机 `pip install pypdf` 后按文本抽取
  （`Read` 工具读 PDF 要 poppler，本机没装 ⇒ 这是一条真实的环境限制，不是"文档不存在"）。
- **Table 60 "RGMII Timing Parameters"（手册第 60 页 = PDF 第 67 页）** 原文读数：

| 符号 | 含义（原文） | Min | Typ | Max | 单位 |
| --- | --- | --- | --- | --- | --- |
| `Tcyc *` | Clock Cycle Duration @1000 Mbps | 7.2 | 8 | 8.8 | ns |
| `tR` / `tF` | RXC/TXC 上升/下降（20 %~80 %） | – | – | 0.75 | ns |
| `TsetupR` | Data→Clock **Input Setup** at receiver（发射端内部延迟已集成） | **1.0** | 2 | – | ns |
| `TholdR` | Clock→Data **Input Hold** at receiver（同上） | **1.0** | 2 | – | ns |
| `TskewT **` | Data→Clock Output Skew（**无**内部延迟时） | **−0.5** | 0 | **+0.5** | ns |
| `TskewR **` | Data→Clock Input Skew（**PCB 走线延迟**模式），并注明"板上必须让时钟比数据多走 **>1.5 ns 且 <2.0 ns**" | **1** | 1.8 | **2.6** | ns |

三条要紧的结论，都是这一页给的，不是我的推断：

1. **±0.500 是 `TskewT` 那一行的数**（发射端**没有**内部延迟时的输出偏差），它**不是** FPGA 收口该用的窗。
   收口的窗应该来自 `TsetupR/TholdR`（延迟集成时）或 `TskewR`（PCB 延迟时）。⇒ 我原先那条"规范给的沿对齐公差 ±500 ps"用错了行。
2. **两种模式的下界都是 +1.0 ns 量级、上界 +2.6 ns**，与 F4 的模型 b（1.5–2.5 ns）落在同一区间。
   ⇒ 取**并集**当候选约束最诚实：`set_input_delay -clock eth_rxc -min 1.000 -max 2.600`（+ `-clock_fall` 那一对）。
   这是**两个方向都更严**的写法，绿了就说绿得放心，不必先假定板子站在哪一边。
3. **哪一边仍然要量，不许猜**：`TXDLY/RXDLY` 在 RTL8211F 上与 RXD1/RXD0 复用（原理图
   `ZYNQ7020-F+V1.1原理图.pdf` 第 8 页的引脚表原文：`23 TXDLY/RXD1`、`24 RXDLY/RXD0`），
   复位时怎么被拉的、以及寄存器 0x11 的当前值，本机都**读不到**（没有 MDIO 读命令，且无 `arm-none-eabi-gcc` ⇒ app 不能重建，#131/#170）。
   ⇒ 所以第 2 条用并集，而不是宣称"延迟已确认打开"（这正是 `r115_capture_clock_plan.md` §三.5 立的规矩）。

**换成真数之后重算 §1 那条路**（模型：捕获钟仍走今天这只 BUFG，DCD 5.008 不变）。
⚠ 这里要先把我自己算错的一处改对：§1 那条 −2.522 是 **tap 0** 的读数（件名 `rt_tap0_*` 就写着），
它里面的 IDELAYE2 只贡献 **0.655 ns**（那是 tap0 的本底），不是 tap 26 的量。
tap 26 的实测斜率 ≈63 ps/tap（`build/evidence/r114_idelay_sweep_console.txt`）⇒ IDELAYE2 ≈ 0.655 + 26×0.063 = **2.293**。

```
现行结构 + 真窗（min 1.000）：
  arrival  = 1.000 + IBUF 1.321 + IDELAYE2 2.293 = 4.614
  required = DCD 5.008 + 不确定度 0.835 + IDDR hold 0.155 = 5.998
  ⇒ WHS(I/O) ≈ −1.384
交叉核对：把 min 换回 ±0.5 那一档（min −0.500）算出 3.114 − 5.998 = −2.884，
与 r114 实测的 −2.885（件 r114_io_roll_console5.txt）逐位对上 ⇒ 这套分量的算法是可信的。
```

**C2 若真把捕获沿提前 5.000 ns**（required 变成 0.008+0.835+0.155 = 0.998）：
`WHS(I/O) ≈ 4.614 − 0.998 = +3.62`；setup 侧 `≈ (8.008+0.008) − (2.600+1.321+2.293) − tSU − 0.835 ≈ +0.9`（**预测**，`tSU` 按 IDDR 读数）。
⇒ 方向上两个都能转正，但**余量不对称**：hold 很松、setup 只剩 ~0.9 ns，
所以真落地时相移量与 `IDELAY_VALUE` 要**一起调**（把捕获点放到眼中心，而不是贴着 setup 边）。

**第一个中间读数（23:50，route 阶段 `Route 35-416`，不是终态）**：
`WNS=0.981 TNS=0.000 WHS=-0.228 THS=-1331.x`（件 `c2_scratch_1003/build/c2_build_console2.txt`）。
读法要老实：与 r114 同窗终态的 `WHS −2.885 / THS −14.344` 比，**头条 hold 变好了 2.66 ns，但 THS 涨了 90 倍**
⇒ 说明失败的**端点集合换了**（原来是 5 个 I/O 端点，现在是一大批 ~−0.2 的端点）。
这批端点是"相移没有真的提前 5 ns（`−225°` 可能被工具归一化成 `+135°` 的等效延迟）"还是
"布线器为了关 hold 插了大量延迟"，**必须从终态 `report_timing` 的 DCD 与路径分量里读**，现在**未定**（不许圆场）。
终态读数落进 `build/evidence/r115_c2_scratch/`，判定按 §4 的 S1–S5。

**还剩的债**：输出侧那 6 个端口（`tmds_clk_p`、`tmds_data_p[0..2]`、`led[0..1]`）仍然没有来源数——
需要 DVI/HDMI 接收端或面板的窗口数，本机板级资料（用户手册 + 原理图）里没有这一项。
**没有来源就不写数**，这一条继续留在 `debt_ledger.md`，不许用"看起来宽松"的数字凑。

## 7. 读数落在哪

跑完的原始件在副本树里（`c2_scratch_1003/build/…`），摘出来的关键读数与被跟踪的差分一起复制进
`build/evidence/r115_c2_scratch/`。**负结果也写在这一页的末尾**（提示词 §7 L2：负结果是本轮的产出物）。
