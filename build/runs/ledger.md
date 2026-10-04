# 逐轮优化台账（P15c）

对应赛题 3.3.4"在目标器件上取得可测量的性能表现，并给出与基线的对比""合理使用片上资源，避免以
显著的资源代价换取有限的性能收益""将设计过程中的判断依据写进报告"与 3.3.5.3"优化过程对比表"。

这一份只管一件事：**每一轮改了什么、各域怎么样、花了什么代价、采用还是回退、依据是哪两份件**。
叙述版（只讲因果与取舍、不重复数字）在 `docs/optimization-rounds.md（未写）`；
采用/回退的**决定**在 `build/runs/decisions.md`；**与什么比**在 `build/runs/baselines.md（未写）`。

## 0. 台账口径（先读这七条，否则下面的数会被念错）

| # | 口径 | 依据（读过的件） |
| --- | --- | --- |
| T1 | **轮次号沿用仓库自己的 `rNN`**。区间取 `report/log/issues.md` 的 #147–#336 实际覆盖的轮次 = **r90…r119，30 轮连续、中间不跳号**。r93/r105/r111/r115/r119 是**没有正式构建的取证/复算轮**，也占号，因为它们的产出是判据而不是位流。r89 及更早的轮次**不在本条点名的来源区间**（#146 是 r89 的 Pblock 否决，只在 `build/runs/decisions.md` 里作为"更早的否决"列出，不在这里造数） | `report/log/issues.md` 第 6185/6218/13194 行的条目号 |
| T2 | **WNS 的绝对差本身既不算收益也不算损失**。每轮"各域"那一栏给的是读数与**失败端点数**，不给"提升了 x ns"。本仓库的实例：r114 `ASYNC_REG` 那轮头条 WNS 0.445→0.739，但最差路径**换了族**（`rows_hit` 一族 → `u_icmp_tx` 校验和锥），所以那 +0.294 不记在本刀名下 | `report/log/issues.md` #290/#292/#294；`build/evidence/r118_after.txt:4`（原文"全局 WNS 的绝对差不算收益也不算损失（rule 35）"） |
| T3 | **一轮多刀时每个数字要能归属到具体改动**；归不到的写"未归属"，且不写进首页/交付数字。实例：r110 的 −243 LUT 只有 −66 归到刀 4①（OOC 双腿相减），剩下 −177 未归属 | #246/#249；`build/evidence/r110_attrib.txt`、`build/evidence/r112_util_attrib.txt` |
| T4 | **跨构建数字先证可比再比**。可比性依据见本文件第 2 节（`build/runs/baselines.md（未写）` 也引它）。不满足可比性的对照一律标"跨构建，只念不判" | #254 第 2 条、#297、#301 |
| T5 | **分母 `判 N 项` 每轮自己打印**：门禁项数、名册配对数、台架判据数、探针对照数。`NOT_MEASURED` 不算通过 | 各轮 `build/rNN_gates.txt` 末行"判定 N 项"；`build/evidence/rNN_roster_diff.txt` |
| T6 | **资源与告警按类报，代价与收益同笔念**（P15c 铁律 3）。"只报收益的轮次视为未完成"在本台账里的处理是：那一轮直接写"代价未归档"并降级为定性 | `report/timing/gates_g1_g12.md` G9；`report/timing/debt_ledger.md` §6 |
| T7 | **"产物未固化"是显式状态**：一轮被采纳但盘上取不到那一轮的位流或原件报告，就写这个标签并进待办，不许用"当时那个版本"糊过去 | P15c 铁律 6；质量判据 4；`report/log/issues.md` #332 |

## 1. 字段字典（每轮一小节，十个字段固定顺序）

`轮次 | 改动 | 源码指纹 | 各域 setup/hold 最差值与失败端点 | 资源 LUT/FF/BRAM/DSP 与增量归属 |
告警条数按类 | 判 N 项 | 对照方式 | 结论 + 理由 | 证据路径`

- "各域"只列**进表的那四个有 intra 路径的域**（`sys_clk` / `clk_fpga_0` / `clkout0_1` / `eth_rxc`）；
  `clkfbout`、`clkfbout_1`、`clkout1_1`、`clkout2` 四域在 Intra Clock Table 里**只有名字没有 intra 路径**，
  台账一律写 `NA`。`NA` = 该域没有同类路径，**不是**读不到、**不是** 0、**不是**通过
  （`build/roster/roster_r118.tsv` 第 2 行注释把这条钉死了）。
- "失败端点"格式 `失败 setup / 失败 hold / 总端点`，三个数一起念；只看 WNS 一列会漏掉"端点数才是账"的那几轮（r84→r86）。
- "源码指纹"给 `rtl`（`fpver=norm1`，对 CR 不敏感）；r104 之前同时给 `top`。

## 2. 基线可比性（跨构建比较的前置证明，台账里所有"对照"都挂在这一节上）

| 事实 | 读数 | 件 | 能用来证什么、不能用来证什么 |
| --- | --- | --- | --- |
| **同一份 `opt.dcp` 重跑 place+route 逐位复现正式构建** | roll A（不加任何变量）：族 slack `0.445 ns`、`p_eof_reg` 仍在 `SLICE_X57Y34`、整片 `rows_hit` 仍在 `X28~X31`、WHS 0.050、端点 51135 —— 与正式 r112 一格不差 | `build/evidence/r113_roll_a_console.txt`（原件在 `/tmp/kx/pb113/A/`），结论入 `report/log/issues.md` #254 第 2 条 | **能证**：这套工具的放置与布线在这棵树上给确定解 ⇒ "同 DCP 两滚"是合法对照，不是掷骰子。**这一条是台账"基线可比性"的主依据** |
| **噪声底 `noise_ns = 0.000`** | 同一份 `system_top_opt.dcp`（md5 `4c895816c4f2`）`mode=none` 连滚两遍，头条四个数逐位相等、最差路径身份（起点/终点单元名）也相等 | `build/evidence/r115_noise_cal_console.txt`、`build/evidence/r115_noise_verdict.txt`；判读入 #297；口径入 `report/timing/baseline_index.md` §B4 | **能证**：同 DCP 快车道滚里，任何非零差都是真的。**限制（#297 原文）**：它量的是"同一份网表重跑物理实现的散布"，**不是跨构建散布**；换 DCP（重新综合）就重新变成跨构建比较 |
| **空白滚 == 正式构建名册** | r115 C1 的 A 滚（不加变量）与 `report/timing/roster_baseline.tsv` **逐格相同**（32 次比较全绿、8 格双侧 NA） | `build/evidence/r115_fanout_ab/verdict_header.txt` + `roster_diff.txt`，入 #301 | **能证**：快车道能复现正式构建的**逐域名册**（不只四个头条数）。**不能证**：跨构建可比（仍是"同 DCP"） |
| **同树两次独立构建调用逐位复现时序** | r105 A/B：post 一侧 3 次独立调用（正式 r104 + `build/r105ab_post_1` + `build/isolated_r104_141`）都是 `0.812 / 0 / 50948`，pre 一侧 2 次都是 `0.608 / 0 / 50868`，而**位流 md5 各不相同** ⇒ 复现的是时序，不是同一份文件被念了两遍 | `build/evidence/r105_ab_rolls.txt`；入 #223 与提交 3fa0a97 | **能证**：#141 那一刀的 +0.204 在这套策略下可复现、四域同向。**顺带作废了一句旧口径**：本文早期那句"同一条路在两次构建之间摆 0.4 ns（放置抖动）"被当成了"同树重复滚的噪声底"用 —— **那是跨变体的散布，用错了轴**（#223 结案） |
| **没有设置任何 seed** | `grep -in "seed" build/r118_build_console.txt` 无命中 | `build/provenance.md` 第 104 行（P15a 已量） | ⇒ 跨次构建**不保证**逐位相同，所以本仓库对"收益"的判据形态是**同树多滚 / 同 DCP 两滚**，不是"重跑一次看看" |
| **策略、工具版本、约束集** | 全程 `Vivado v2025.2.1 (64-bit) Build 6403652` + `xc7z020clg484-2`（`-2 PRODUCTION 1.12 2019-11-22`）；r105 之后每轮 `build/rNN_build_console.txt` 里有 `BUILD_STRATEGY` 行；r91/r95/r95b 三轮的"改动"就是策略本身，那三轮的 `BUILD_STRATEGY` 各自念出**请求的那一档**（"策略真的被应用了"有凭据，不是拿默认流程冒充） | `report/timing/baseline_index.md` 头部；`report/log/issues.md` #154 与 r95b 段（OPTIMIZATION_LOG 转述的"构建日志里念出请求档位"这条在 `build/r95b_timing_summary.txt` 的逐档 VERDICT 行有对应件） | ⇒ 跨轮比之前必须先答"策略同不同、版本同不同、约束集同不同"，不同就退回"只念不判" |

**台账里"对照方式"这一栏只允许三个取值**（P15c 铁律 5：优先便宜的对照）：

1. `全流构建` —— 只在**采用**那一笔跑（含位流、门禁、上板）。
2. `检查点复算` —— 从已生成的 `system_top_opt.dcp` / `system_top_routed.dcp` 重跑物理实现或只读出报告，
   不改 RTL、不跑全流（r113 三滚、r114 复制 A/B、r115 全部候选、r116 的 0…31 扫档、r119 的成品离散量都在这一档）。
3. `副本预验证` —— 需要动 RTL 的裁剪，先在拷贝树/隔离目录验（r105 A/B、r108 差分台架、r110 OOC 双腿、
   r115 C2/C3 的 `c2_scratch_1003` 副本树、r90/r91/r95 的 `build/isolated_*`）。

---

# r90 —— 帧缓存拆三块换 BRAM：省到 5 片 RAMB36，代价落在最薄的那个域

| 字段 | 内容 |
| --- | --- |
| 轮次 | r90（2026-09-29 19:5x–23:0x） |
| 改动 | ① `src/rtl/video/frame_buffer_w64.v`：`reg [63:0] mem [0:38399]`（非 2 的幂）拆成三块 2 的幂深度 `32768 + 4096 + 2048` + 一个 2 选 1 读回小树（推断宽度动机：非 2 的幂的 64-bit 数组被综合器按 2^16 铺）。② `src/rtl/eth/icmp_rx.v`：`icmp_rx_cnt == icmp_data_length - 1` / `< icmp_data_length` 两条 16 位借位链换成 `icmp_len_m1` 提前一拍寄存 + `in_data_win` 旗标（代价 17 个 FF） |
| 源码指纹 | 采纳侧（回退后）`rtl=41384499f3a9`（`build/r90_gates_final.txt`/`_final2.txt` 两处同值，且 = 门禁第 15 项报告的 `rtl_md5` = 板上那一跑的留档 —— #152 的"回退等式"）。刀 ① 两滚与刀 ② 那一滚**没留各自的 norm1 指纹** ⇒ 未归档（r105 之后才开始每轮钉指纹） |
| 各域 setup/hold 最差值与失败端点 | `eth_rxc` setup：采纳基线 **+0.516** → 只拆三块 **+0.232** → 拆三块 + 换 FF **+0.182**；`hold` 三个域同为 **+0.051**；失败 setup/hold **0 / 0**，总端点 50885。最差那族逻辑级数 4 → **9** → 回到 4（结构量，不是运气）。其余三域：本轮未逐域留件 ⇒ `NOT_MEASURED` |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | RAMB36 单元 **93 → 88**、Block RAM Tile **95 → 90.5**（67.86 % → 64.64 %）、RAMB18 5 → 5 —— 全部归刀 ①（两份 `utilization.rpt` 相减）；刀 ② **+17 FF** 归 `icmp_rx.v`（16+1）；LUT/DSP 增量**未归属**（该轮未做逐层件） |
| 告警条数按类 | `build/isolated_0929_2105/methodology.rpt` 的 `Checks found: 441`；采纳基线那份**未归档** ⇒ 类差分 `NOT_MEASURED` |
| 判 3 项 | ① 两次独立滚同数（放置运气排除）② 顶层台架 138 条只红声明过的 `C5c` ③ 采纳门槛（`build/r90_phase3.sh` 头部：WNS ≥ 0.45、级数 ≤ 6、顶层 FAIL ≤ 1）——**门槛第 1 条实测 0.182，不过** |
| 对照方式 | 副本预验证（`build/isolated_0929_2036/`、`build/isolated_0929_2105/`、`build/isolated_lenm1/` 三滚，全部不碰 `build/`）+ 独立综合探针 `build/fb_split_probe/`（三个 top 同会话实测 80/75/74） |
| 结论：**回退**（"资源换时序"这一笔决定不换） | 理由按数字讲：省的是 140 片里的 5 片 RAMB36，而 BRAM 哪版都没饱和（67.86 % / 64.64 %）；付出的是**最快那个域（125 MHz）的 setup 余量从 6.5 % 掉到 2.3 %**，而那个域同时是全设计保持时间最薄所在（三域同为 +0.051）。**在不缺资源的地方省资源、在最薄的地方削余量，这笔账是反的**。拆出的结论写死：**拿 FF 买级数划算（刀 ② 已证：9 级锥整族消失），拿 BRAM 削 setup 不划算（量过就放下）**。回退状态用 md5 钉住而非记忆：`src/rtl` 合指纹 = 报告 `rtl_md5` = 板上留档，三者同为 `41384499f3a9` |
| 证据路径 | `report/log/issues.md` #149/#150/#152；`build/isolated_0929_2036/`、`build/isolated_0929_2105/{utilization,timing_summary}.rpt`、`build/isolated_lenm1/crit_paths.txt`；`build/crit_paths.txt`；`build/evidence/r90_fb_split_probe.txt`、`build/evidence/r90_crit_paths.txt`；`build/r90_gates_final.txt`（判定 20 项）、`build/r90_gates_final2.txt`；`build/r90_phase3.sh`；台账目录 `build/runs/r90/` |

# r91 —— 只换实现策略：hold 三个策略一位没买到

| 字段 | 内容 |
| --- | --- |
| 轮次 | r91（2026-09-30 00:24–00:55） |
| 改动 | **不改 RTL、不改约束**。只换实现策略两档：`Performance_Explore`、`Performance_ExtraTimingOpt`，各一整滚。`set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]`（`src/constraints/rk_zynq7020.xdc:50`）保持 r79 加严后的值一字未动 |
| 源码指纹 | 与 r90 采纳侧同一枚 `rtl=41384499f3a9`（⇒ 单变量成立：变的只有策略） |
| 各域 setup/hold 最差值与失败端点 | 全设计：基线 WNS **+0.516 / WHS +0.051**；`Performance_Explore` WNS **+0.500 / WHS +0.046**；`Performance_ExtraTimingOpt` WNS **+0.157 / WHS +0.051**。`eth_rxc` 与全设计同值（它就是最差那组）。失败 setup/hold 端点 **0 / 0**（总端点 50885 / 50805 / 50885）。其余三域 ⇒ `NOT_MEASURED`（该轮逐域只念了 `eth_rxc`） |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | LUT `14318`（Explore）/ `14361`（ExtraTimingOpt）、FF `8075` 两滚同值、BRAM `95` tile、DSP 未逐轮归档 ⇒ 这些差是**策略自己的布局产物**，不归属任何设计改动 |
| 告警条数按类 | 两滚 `Checks found: 445`（`build/isolated_r91_explore/methodology.rpt`、`build/isolated_r91_extratimingopt/methodology.rpt`）⇒ 策略不换告警类别 |
| 判 3 项 | 门槛（跑之前写在 `build/r91_strategy_round.sh` 头部）：WHS ≥ +0.15、WNS ≥ +0.40、失败端点 0 ⇒ 两滚**一条都没过**（hold 全在历史带内，setup 第二档反而变差） |
| 对照方式 | 副本预验证（两个隔离滚，`build/` 与位流一字未动） |
| 结论：**回退**（不采纳任何策略） | 理由：hold 在三档下是 0.046 / 0.051 / 0.051，**完全落在历史噪声带里，一位都没买到**；这反向把"structural 而非 effort"钉硬 —— `+0.05x` 的 hold 不是"实现不够用力"，是时钟树结构（BUFIO/BUFG 两棵树差 1.616 ns），**placer 无权改布线树拓扑，所以换策略对它必然无效**。副产品：这一问把 r92 那一刀的方向定死了 |
| 证据路径 | `report/log/issues.md` #153/#154；`build/r91_strategy_summary.txt`、`build/r91_strategy_round.sh`、`build/r91_round_console.txt`；`build/isolated_r91_explore/timing_summary.rpt`、`build/isolated_r91_extratimingopt/timing_summary.rpt`；台账目录 `build/runs/r91/` |

# r92 —— #57 捕获钟那一刀落了：偏斜消掉是凭据，WHS 数字没动

| 字段 | 内容 |
| --- | --- |
| 轮次 | r92（2026-09-30 04:0x–06:0x，正式件 `build/system.bit` md5 `883dd3b7654d`） |
| 改动 | ① `src/rtl/eth/rgmii_rx.v`：删掉 `BUFIO`，5 个 IDDR 的 `.C` 一律改吃 `rgmii_rxc_bufg` ⇒ 发射端（ILOGIC）与接收端（fabric）第一次落在**同一棵树**上。② `src/rtl/top/system_top.v`：`IDELAY_VALUE` 15 → **26**（补拍算术写在注释里：BUFG 比 BUFIO 晚 `4.854 − 3.171 = 1.683 ns`，`idelay_clk` 200 MHz ⇒ 每拍 156 ps ⇒ 要补 10.8 拍，取 +11）。**没动任何协议逻辑** |
| 源码指纹 | `rtl=c8bf35eb19e5`（`build/r92_gates.txt` 第 35 行的边缘条带行）；改前对照 `rtl=41384499f3a9`（`build/r92_gates_console.txt` 当场念出"指纹不符 41384499f3a9 != c8bf35eb19e5：改过"）—— ⇒ 这一轮的"改前/改后"是两棵树，**跨构建** |
| 各域 setup/hold 最差值与失败端点 | `eth_rxc` **0.522 / 0.049**（改前 0.516 / 0.051）；`clk_fpga_0` **2.161 / 0.037**（改前 1.643 / 0.051）；`clkout0_1` **0.885 / 0.048**（改前 1.177 / 0.059）；`sys_clk` **13.926 / 0.130**（改前 14.621 / 0.105）。失败 setup/hold 端点 **0 / 0**，总端点 50885（"All user specified timing constraints are met"）。全设计 WHS 头条 **+0.037**，且最差那一格**换了域**（挪到 100 MHz 的 `u_pl/u_lat/t_commit_reg[0] → max_cyc_reg[4]`，`Requirement 0.000` 同沿检查、不带自加不确定度） |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | LUT **14351**（改前 14358，−7）、FF **8075**（不变）、BRAM **95** tile（不变）、DSP 未逐轮归档。结构性判据：`BUFIO` 用量 **1 → 0**（`build/clock_util.rpt` 第一张表 vs 仓库里的改前对照 `build/r88_clock_util.rpt`）；`build/tcl/clock_uncertainty.tcl` → `build/clock_uncertainty.rpt` 确认 `eth_rxc` 那一格报告里明写 `clock uncertainty 0.800`（那条约束**生效**这件事第一次有凭据） |
| 告警条数按类 | 隔离滚 `Checks found: 445`；正式件那份未逐类归档 ⇒ `NOT_MEASURED`。台架：`tb_edge_rim` 31 条 PASS（`build/tb_edge_rim_r92.txt`，`rtl=c8bf35eb19e5`）；`tb_v98` 138 条判据 **只红 1 行 = 声明过的 `C5c`** |
| 判 4 项 | ① 结构：`BUFIO` 用量 1→0 ② 偏斜：最差 20 条 hold 的时钟偏斜 **1.616 ns → 0.013/0.032/0.037/0.262/0.349 ns**（同一棵树内）③ 功能（这一刀唯一能判的地方，因为 `src/constraints/` 里当时没有任何 `set_input_delay`、报告看不见采样窗）：板上实流量 `drop_words=0 / 丢过字=0 / stall_ms=0 / CDC灌满过=0 / 流活着=1` ④ 门禁 20 项判定、唯一红是声明过的 `C5c` |
| 对照方式 | 副本预验证（先烧隔离件 `1af8b4a14d72` 判功能）→ 全流构建（采用那一笔，正式件 `883dd3b7654d`）；改前对照用仓库里 rNN 命名的旧件（`build/r88_clock_util.rpt`、`build/r88_methodology.rpt`） |
| 结论：**采用** | 理由：这一刀买到的不是 slack 而是**机制**——#80 猜的两棵树 1.616 ns 偏斜被证实并消除，之后 `+0.037/+0.049` 薄在**我自己在 r79 加严的 0.8 ns hold 不确定度**上（数据侧只有 1 级 LUT，工具把最小延迟插到刚跨过要求线），不再是掷 ±1 ps 的硬币。**记账口径两条都不许省**：把 0.051→0.037 念成"退步 0.014"是错的，念成"改结构没用"也是错的。采纳依据**不是门禁那一行绿**（它 20 项里仍有声明过的 `C5c`），而是**板上那一套**（0 丢字 + 100 条电池 + 判红步骤 0 + `BUFIO` 用量 0） |
| 证据路径 | `report/log/issues.md` #154/#156；`build/r92_gates.txt`（判定 20 项）、`build/r92_gates_console.txt`、`build/isolated_r92_bufig/`；`build/clock_util.rpt`、`build/r88_clock_util.rpt`（改前对照）、`build/hold_paths.rpt`、`build/clock_uncertainty.rpt`；板侧 `build/evidence/r92_1_psboot.txt`、`r92_2_program_log.txt`、`r92_3_app.txt`、`r92_tx.txt`、`r92_health.txt`、`verify_0930_0424.txt`；`build/tb_edge_rim_r92.txt`；台账目录 `build/runs/r92/` |

# r93 —— 没有构建、没有改动的一轮：三条眼睛判据由人点头

| 字段 | 内容 |
| --- | --- |
| 轮次 | r93（2026-09-30 06:2x–07:0x） |
| 改动 | **无**（`src/` 一字未动，无构建）。本轮只做板侧眼睛判据的签收与状态复原：E1/E3 口头确认（原话"现在都很正常"，06:2x），E2 确认（原话"现在画面正常只有一条"，06:5x–07:0x），并用**只改推流节奏**做对照（29.76 fps 一条、复推 25 fps 仍一条）⇒ 观感那次"两条白线"未复现，判为切换瞬间暂态，不记缺陷 |
| 源码指纹 | 未采（本轮无构建，沿用 r92 的 `rtl=c8bf35eb19e5` ⇒ 板上的位流就是 r92 那一块） |
| 各域 setup/hold 最差值与失败端点 | 同 r92（本轮未重跑任何报告）⇒ 逐域 `NOT_MEASURED` |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | 无改动 ⇒ 增量为 0；本轮未出 `report_utilization` |
| 告警条数按类 | 未取 ⇒ `NOT_MEASURED` |
| 判 3 项 | E1/E2/E3 三条眼睛判据由在场的人点头（**机器判据不冒充眼睛**，这是本仓的规矩）；`--fps 29.76` vs `25` 的 A/B 是对照不是判据 |
| 对照方式 | 板侧 A/B（`build/r93_fps_caliber.py`、`build/evidence/r93_ab_state.txt`、`r93_e2b.txt`） |
| 结论：**不适用（取证轮，无采纳对象）** | 理由：这一轮的产出是**验收表里三行的签名**与"观感缺陷未复现"这条否定结果，没有任何可采纳的物理改变。它占号是为了不让下一轮误以为"上一轮什么都没发生" |
| 证据路径 | `board/acceptance.md` 第 70 行（E2 那一格，含 2026-10-01 在 r103 上重判的追加）与 E1–E3 那一段；`build/r93_eye_close.py`、`build/r93_fps_caliber.py`；`build/evidence/r93_ab_state.txt`、`r93_ab_state_capture.txt`、`r93_e2b.txt`、`r93_e2b_capture.txt`、`r93_tx2976.txt`、`r93_restore.txt`；台账目录 `build/runs/r93/` |

# r94 —— 几何两刀进构建，时序侧只换读数不换机制

| 字段 | 内容 |
| --- | --- |
| 轮次 | r94（2026-09-30 12:1x–15:0x，正式件 `build/system.bit` md5 `a1465f29c9e4`） |
| 改动 | ① `src/rtl/process/zoom/zoom_mapper.v`（#104）：旋转支接回 `>>>16` 之后的 `[15:8]` 当小数，并把纵向 `Y_disp = H/2 − Y_math` 的翻转连着 floor 一起改。② `src/rtl/zoom_ctrl.v（不存在）` + 顶层（#93）：旋转生效时把**实际用的倍率**钳进 `zoom_fit`，钳制做在 `zoom_ctrl` 的 `inv_used` 出口（新增输入 `rotate_en`、输出 `rot_forced`）——先在顶层写的那版**回退了**（`build/r94_top_mux_superceded.patch`），因为它喂不到 `zoom_code` ⇒ 屏上会与取样不一致。③ `src/rtl/eth/eth_udp_video_top.v`（#158）：`FRAME_BYTES` 由"靠默认值偶然相等"改成显式 `IMG_W*IMG_H*2`（今天的展开值逐字节不变 ⇒ 纯防呆） |
| 源码指纹 | `rtl=526321488fed`（`build/r94_gates.txt`，且 = `tb_edge_rim_r94.txt` 的 `rtl_md5`）；本轮**动机不是时序**（ISSUES #162 原话） |
| 各域 setup/hold 最差值与失败端点 | `eth_rxc` **0.553 / 0.049**（= 全设计 WNS/WHS）；`clk_fpga_0` **0.970 / 0.060**；`clkout0_1` **1.089 / 0.063**；`sys_clk` **14.195 / 0.121**。失败 setup/hold 端点 **0 / 0**，总端点 50883；WPWS 0.264 |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | LUT as Logic `10187`、`Slice Registers 8074`、BRAM `95` tile、DSP `19`、总功耗 2.383 W（`report_power`）。与 r92 的差（LUT/FF 各 −7/−1 量级）**未归属到具体刀** ⇒ 首页不写（T3） |
| 告警条数按类 | 门禁 `methodology CRIT 0`、`端口宽度警告 8-689 0`、`多驱动 net 0`；逐类 `Checks found` 那份本轮未归档 ⇒ `NOT_MEASURED` |
| 判 4 项 | ① 新尺子带"改前红"：`sim/tb_zoom_frac.v` 改前 FAIL 行数 = 298（`build/r94_zoomfrac_console.txt`；正文只贴前 80 行所以 `grep -c ^FAIL` 是 79 —— 一份数的两个视图，不是两份数）→ 改后 128 次逐像素比较 0 失配、99/99 旋转像素带非零小数 ② `sim/tb_v94_zoom_sel.v` 新增 T8a–T8f，变异关掉钳制后**恰好** T8b/T8c/T8e 红（连带红按规矩列出、不削弱判据） ③ 回归 `tb_v100_fit_rot` checks=373 errors=0、端口检查 199 例化 0 违例 ④ 门禁 20 项判定、唯一红仍是声明过的 `C5c` |
| 对照方式 | 全流构建（采用笔）+ 台架两端夹逼（改前红/改后绿/变异对照三段齐） |
| 结论：**采用** | 理由：本轮的采纳依据是**几何两条已知缺陷清账 + 机器侧全绿 + 板上 105 条电池全绿（判红步骤 0）+ 几何"最后一跳" `geom_check` ok=8 fail=0**。时序那侧**只报读数不报提升**：绝对值与 r92 的 +0.522/+0.037 之差**既不算收益也不算损失**（同一条路实测摆过 0.4 ns 量级）。⚠ 一处凭据出身账如实留：链刚跑完时门禁是**两条红**，红因是 `build/r94_bench_chain.sh` 第②步调 `rim_report.sh` 时**没传 `ROUND`**、脚本自带默认 `ROUND=r90` ⇒ 产出一份"名字叫 r90、stamp 是 r94"的**假凭据**（比"没留件"更坏）。已补 r94 那份、把冒名那份挪出盘、链脚本改三处（不给 `ROUND` 就拒绝开跑 / 把 `ROUND` 传下去 / 断言本轮那份件的 `rtl_md5` 等于当前树）（#179） |
| 证据路径 | `report/log/issues.md` #158/#162/#179；`build/r94_gates.txt`、`build/r94_build_console.txt`、`build/r94_zoomfrac_console.txt`、`build/r94_zoomfrac_final.txt`、`build/r94_rotfit_after.txt`、`build/r94_rotfit_mutation.txt`、`build/r94_top_mux_superceded.patch`；`build/timing_summary.rpt`/`build/utilization.rpt`/`build/power.rpt`（当轮原件）；板侧 `build/r94_flash.txt`、`build/r94_batt.txt`、`build/r94_geom_check2.txt`、`build/r94_eye_state_cap2.txt`；台账目录 `build/runs/r94/` |

# r95 —— 把"时序还能不能更好"问到工具自己说它不干活为止

| 字段 | 内容 |
| --- | --- |
| 轮次 | r95 / r95b（2026-09-30 13:2x–15:5x，全在隔离构建，`build/` 一字未动） |
| 改动 | **不改 RTL/约束**。四档旋钮各一滚：A `IMPL_PRPO=1` ⇒ 布线后 `phys_opt_design -directive AggressiveExplore`；B 策略 `Performance_ExploreWithHierarchy`；C `Performance_NetDelay_high`；D `Performance_WLBlockPlacementFanoutOpt` |
| 源码指纹 | 与 r94 同一枚 `rtl=526321488fed`（⇒ 策略是唯一变量，B 靶子网络按最差那条路的形状挑：route 占 60~67 %、高扇出 fo=96/17） |
| 各域 setup/hold 最差值与失败端点 | 基线 r94：WNS 0.553 / WHS 0.049 / 0 / 50883。A 滚 **逐位相同**（0.553 / 0.049 / 0 / 50883、BRAM 95）；C 滚 **WNS +0.013 / WHS +0.056**（`eth_rxc` 0.013 / 0.059）；D 滚 **WNS +0.553 / WHS +0.049**（与基线一格不差，位流却不同）；B 滚 **READ_FAILED**（策略被 `set_property` 拒 ⇒ `NOT_MEASURED`，不写成"否决"）。失败端点四档都是 **0** |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | BRAM 四档都是 95 tile ⇒ 无资源代价可归属；其余未逐轮归档 |
| 告警条数按类 | 未归档 ⇒ `NOT_MEASURED` |
| 判 4 项 | 门槛写在**任何一滚开跑之前**（`build/r95_timing_summary.txt` 头部 13:27:55 那一戳）：WNS ≥ +0.65、WHS ≥ +0.15、失败 setup/hold 端点 = 0、BRAM ≤ 95 tile。结果：A 不达（与基线同数）、C 不达、D 不达（"没达门槛"，不念成"打平"）、B 未测 |
| 对照方式 | 副本预验证（`build/isolated_r95_postroute_physopt/`、`build/isolated_r95b_netdelay_high/`、`build/isolated_r95b_wlfanout/`、`build/isolated_r95_explor_withhier/`）。⚠ 一拨**根本没量到**：`build/r95_timing_round.sh` 里 `ROLLS` 注释写"逗号分隔"、解析用 `for spec in ${ROLLS:-…}` ⇒ bash 只按空白切词，两滚并成一滚、策略名拼成非法串被工具拒（#163/#164 同族的"脚本自己的账"）。修法：分隔符改分号 + `SUM/LOG` 路径可覆盖（上一拨它往 r95 的凭据上追加了第二个门槛头，凭据出身问题） |
| 结论：**全部回退**，并就地关闭一个问题 | 三条各自有凭据、不合并成一句"工具没用"：① **A = DECLINED，机制在规则层面结构性空转**——工具自己的三行原话（`build/isolated_r95_postroute_physopt/build_console.txt:2568` 起）：`WNS ≥ 0 ⇒ All physical synthesis setup optimizations will be skipped`、`WHS ≥ 0 ⇒ Hold fix optimization will be skipped`、`No setup violation found. The netlist was not modified` ⇒ "布线后物理综合"这一档**永远不会**给已过时的本版带来收益。② **B = `NOT_MEASURED`（不是否决）**——该档不在这颗器件的流里（`list_property_value strategy` 没有它），把"读不到报告"写成 DECLINE 就是让"没数"长得像"结论"。③ **C/D = 不采纳**——C 方向明显不利（比基线低 0.54 ns，已超出实测摆幅，所以这句至少不是"噪声里挑好看的看"）；D 数与基线一格不差 ⇒ 这一档对那两个靶子网络没有作用。⇒ **"时序还能不能靠工具再压"这个问题到此关闭**：剩下的只有"改 RTL 那条锥"或"Pblock/绕线疏解"两条手工路 |
| 证据路径 | `build/r95_timing_summary.txt`（含门槛头）、`build/r95b_timing_summary.txt`、`build/r95_timing_round.log`、`build/r95b_console.txt`、`build/r95_timing_summary_falsestart.txt` 与 `build/r95_timing_round_falsestart.log`（那拨空转的原样凭据，**没删**）；`build/isolated_r95_postroute_physopt/build_console.txt`（被点名的行号）、`build/isolated_r95b_netdelay_high/build_console.txt`（策略名被拒的尸检）；台账目录 `build/runs/r95/` |

# r96 —— 两刀功能修复上板，时序只是换读数

| 字段 | 内容 |
| --- | --- |
| 轮次 | r96（2026-09-30 17:07–18:5x 构建，正式件 `build/system.bit` md5 `76d6442991e0`，22:15 前的板上版） |
| 改动 | ① `src/rtl/eth/axi_frame_writer_gated.v（不存在）`（#170）：看门狗 `abort` 之后**在途的读突发必须排空**才允许下一帧起头（新增 `drain_left`/`start_hold` 一个排空态；`m_axi_rready` 排空期间继续吃 R、三个写口关掉）。② `src/rtl/top/pl_video_top.v` + `frame_commit_lock.v`（#171）：`frame_ready_pix` 从"置 1 后只有异步复位才清"改成**一拍脉冲**（`r1 ^ r2`），顶层 `eth_has_frame` 的 `else if` 顺序跟着换 —— 旧几何下 `copy_abort_pix` 那一支**永远轮不到** |
| 源码指纹 | `rtl=fe573f9b2024`（`build/r96_gates.txt` 边缘条带行） |
| 各域 setup/hold 最差值与失败端点 | `eth_rxc` **0.749 / 0.049**（门禁 WNS 归属）；`clk_fpga_0` **1.755 / 0.051**；`clkout0_1` **0.840 / 0.062**；`sys_clk` **14.272 / 0.121**。失败 setup/hold **0 / 0**，总端点 50887；WPWS 0.264 |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | LUT `14388`（27.05 %）、FF `8077`、BRAM `95` tile（67.86 %）、DSP `19`、Dynamic `2.206 W`。端点 +4 与 #170 排空态新增的位**同量级** ⇒ 这是结构观察不是改进；LUT 增量**未归属**（该轮未出逐层件） |
| 告警条数按类 | 门禁 `methodology CRIT 0`、`端口宽度警告 8-689 0`；逐类未归档 ⇒ `NOT_MEASURED` |
| 判 6 项 | ① #170 三阶段：改前 3 红 → 改后 12/12 绿 ② #171 三阶段：改前 2 红 → 改后 12/12，单文件退回 HEAD ⇒ **五红**（变异对照能动） ③ 链第⓪步把这两把尺子纳入复跑 ④ 门禁 20 项判定 / **2 项红**（`C5c` + 我自己新加的守卫 `C11pre`，见 #187） ⑤ 试冻结**按预期 REFUSE**（`build/frozen_r96` 未生成，冻结集继续是 r75） ⑥ 板级 `RESULT board_verify PASS（判红的步骤：0）`、串口 105 条 / 97.7 s 全过、`--stream` 九条全绿 |
| 对照方式 | 全流构建 + 台架三阶段（改前红/改后绿/变异对照）；板级三步 JTAG（不写 QSPI） |
| 结论：**采用** | 理由：两刀都在正确性侧、都有"改前红"凭据、机器侧全过。按 T2，这些绝对值**不与 r94 的 0.553 比高低**（本轮是功能刀、WNS 归属仍在同一组，一句"变好了"都不许写）；能写的只有"0 违例、失败端点 0、这一版被烧进板子并过机器验收" |
| 待办（产物未固化） | 本轮**没有** `build/evidence/r96_bit/` 快照：`build/system.bit` 早已被后续构建覆盖，只能从 git 历史取 ⇒ 进待办（见 decisions.md 末节）。台账只念这条事实，不拿"当时那块"当可复核产物 |
| 证据路径 | `report/log/issues.md` #170/#171/#187；`build/r96_gates.txt`、`build/r96_writer_abort_before.txt`、`build/r96_writer_abort_after.txt`、`build/r96_commit_strobe_mutation.txt`；`build/evidence/r96_flash_1_ps_boot.txt`、`r96_flash_2_program_pl.txt`、`r96_flash_3_app_reload.txt`、`verify_0930_1845.txt`；台账目录 `build/runs/r96/` |

# r97 —— 三刀都是"看得见的口径"，时序只是读数搬家

| 字段 | 内容 |
| --- | --- |
| 轮次 | r97（2026-09-30 16:5x–19:52 构建，22:15 烧板，正式件 md5 `ef03eea4886e`） |
| 改动 | ① `src/rtl/eth/link_monitor.v`（#99 尾账/#175）：两处快照/角点口径修正。② `src/rtl/video/frame_latency.v`（#185/#186）：同拍写竞争与粘滞位取直播值。③ `src/rtl/eth/icmp_tx.v`（#188 的台架那半在本轮，RTL 半在 r99）+ 注释更正。本轮第一次把**"归属"写进凭据**：门禁抬头打印 `system.bit / system.xsa / ps_app.elf` 三枚 12 位 md5（以前只写 mtime，"按位流指纹找同批门禁件"在导出器里永远查不到） |
| 源码指纹 | `rtl=45e09e8b3b9d`（`build/r97_gates.txt` 第 35 行）。⚠ 同一轮里我把这份指纹的量法换过一次：`core.autocrlf=true` + 无 `.gitattributes` 时，一次 `git checkout -- src/rtl` 把 79 份 `.v` 里 52 份从 LF 重写成 CRLF，内容一字未改而合指纹从 `45e09e8b3b9d` 变成 `6ab3898eccae` ⇒ 抽出全仓唯一定义 `build/rtl_fingerprint.sh`（`fpver=norm1`：先 `tr -d '\r'` 再 md5），旧 raw 值经 `build/fingerprint_bridge.txt` 桥接 |
| 各域 setup/hold 最差值与失败端点 | `eth_rxc` **0.720 / 0.033**；`clk_fpga_0` **1.142 / 0.048**；`clkout0_1` **1.767 / 0.064**；`sys_clk` **14.444 / 0.121**。失败 setup/hold **0 / 0**，总端点 50890；WPWS 0.264 / 0 / 12526（**脉冲宽度第一次抄进交付表**）。最差归属：`u_icmp/u_icmp_tx/tx_data_num_reg[12]/C → data_cnt_reg[12]/CE`，11 级（CARRY4 占 5）、7.049/8 ns |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | LUT `14379`（其中 as Logic 10193 + as Memory 4186，Dist RAM 仍 4044 —— 打包器那笔账没退让：#140 量到线速连灌下 512/512 满，`FW` 降不得）、FF `8079`（+5/+2 的分配见 #124/#99 那两行）、BRAM `95`、DSP `19`、Dynamic `2.207 W` / 估算结温 52.5 ℃（工具置信度 Low）。板读 XADC **63.1–63.4 ℃** 是另一条独立来源，被问就两个都给（`build/board_temp_r97.txt`） |
| 告警条数按类 | 门禁 `methodology CRIT 0`、`端口宽度警告 8-689 0`；逐类 `Checks found` 未归档 ⇒ `NOT_MEASURED` |
| 判 5 项 | ① 门禁 20 项判定 / 唯一红 `C5c` ② 台架两份同跑凭据（`tb_edge_rim` 31 PASS）③ 三条凭据侧改进各自的对照：`#190` 导出器读正文（包内出现未在 `report/known_issues.md` 公开过的红就拒绝写包）、`#192` 冻结件的盖章对象 = 目录里实际存在的文件（对照实测：旧版 11 份盖章/21 份落地、改一份没盖章的报告 `md5sum -c` 报 **0** 个 FAILED；新版 20/20 报 **1** 个；`build/freeze_selftest.sh` PASS=14 FAIL=0）、`#195a` 包内 glob 必须数得出东西（上一版 `build/tb_display_edge_rim_r*.txt` 命中 **0** 份，补成路径形状后命中 **11** 份） ④ 板级 `PASS` + 末态 = 演示默认档 `geom=00400000` ⑤ 首次"初态=末态"绿 |
| 对照方式 | 全流构建 + 只读 DCP 探针（`build/r88_resource_owners.txt` 那族）+ 沙箱对照（冻结自测在 /tmp，不碰真凭据） |
| 结论：**采用** | 理由：本轮真正的收益不是 WNS，是**"凭据能被查"**这一层。时序侧按 T2 只写一句：**"这一轮的最差路径归谁"从 `u_cdc` 一族搬到了 `u_icmp_tx`**，+0.720 与 r96 的 +0.749 之差**不写成涨跌**（同源对照实测摆过 0.4 ns）。同时留下一条硬口径：WHS +0.033 这个数里**含我自己加的 0.8 ns hold 不确定度**，所以它不是"真实余量只剩 0.033" |
| 证据路径 | `build/r97_gates.txt`、`build/r97_build_console.txt`、`build/r97_batt_recheck.txt`、`build/r97_flash_1_psboot.txt`、`build/r97_flash_2_program.txt`、`build/r97_flash_3_app.txt`、`build/evidence/verify_0930_2215.txt`、`build/board_temp_r97.txt`、`build/freeze_selftest.sh`、`build/fingerprint_bridge.txt`；台账目录 `build/runs/r97/` |

# r98 —— 门禁自己拦下的一轮：一条新增 Critical CDC 配对，未采纳未刷板

| 字段 | 内容 |
| --- | --- |
| 轮次 | r98（2026-10-01 01:3x 构建；**未刷板、未采纳**） |
| 改动 | ① `src/rtl/top/pl_video_top.v` + 新模块 `src/rtl/util/shown_rate.v`（#128）：OSD 的 `FPS:` 格从"数显示刷新"改成数"写进屏的新帧"。② `src/rtl/eth/icmp_tx.v`（#188）：零载荷单独一支，`ping -l 0` 不再回 65536 字节巨帧。③ `src/rtl/eth/frame_reasm.v`（#201）：`wr_en` 与行覆盖统计吃同一个边界。④ `src/rtl/video/frame_latency.v`（#185/#186）。⑤ `src/rtl/eth/eth_udp_video_top.v`（#209，`link_active` 改由 `gmii_rx_clk` 域触发器给）—— #209 落刀后由 r99 带走 |
| 源码指纹 | `top=f379805a9490`、`rtl=45e09e8b3b9d`（门禁第 15/15b 项两枚，见 `build/r98_gates.txt` 第 33/35 行）。⚠ 该轮位流 `31b0def5271a` **从未刷上板** |
| 各域 setup/hold 最差值与失败端点 | `eth_rxc` **0.402 / 0.056**；`clk_fpga_0` **1.128 / 0.065**；`clkout0_1` **1.743 / 0.064**；`sys_clk` **15.283 / 0.082**。失败 setup/hold **0 / 0**，总端点 50866 |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | LUT `14324`（26.92 %）、FF `8077`、BRAM `95`（67.86 %）、Dynamic `2.214 W`。增量**未归属**（多刀同轮，无逐层件） |
| 告警条数按类 | 门禁 `methodology CRIT 0`；**`cdc.rpt` 的 Critical 配对从两条变三条**：新增 `eth_rxc>clkout0_1`（1 端点、1 个不安全）。门禁第 6 项当时**看不见**这件事 ⇒ 本轮把对照物从"手写基线表"换成"上一版被采纳的 `cdc.rpt`"，并加一条"取不到采纳版也判红"（不许静默少一把尺子） |
| 判 20 项（门禁判定项数） | 实跑 **2 项红**：① 门禁第 15 项（`tb_v98` 报告没有 `RESULT…PASS` 汇总行 —— 台架 5.8 小时只走到 C4 第 10 格，进度不到四成；孤儿 `xsimk.exe` 挡后面每一支台架）② 第 15b 项（rim 凭据文件名 `tb_edge_rim_98.txt` 不在门禁 glob `tb_edge_rim_r*.txt` 的视野里 ⇒ "产出物存在但不被任何读者看见，等于没有"） |
| 对照方式 | 全流构建（未采纳 ⇒ 不刷板）。归因那一半用只读 `report_cdc -from/-to -details` 打在 r98 的路由后网表上，写成两份独立摘要件、**没有覆写 `build/cdc.rpt`**（那是 r98 的门禁输入） |
| 结论：**回退（本轮不冻结、不刷板、不进"已采纳"叙述）** | 理由按原文口径：在 (a) 那 1 个 unsafe 端点被指认出来并说明"为什么按构造是安全的"或修掉、并且 (b) 第 6 项的对照物换成上一版采纳的 `cdc.rpt` 之前，本轮不作采纳。**理由不是"数字不好看"**，而是这个项目为"落在已有配对上的新增不安全端点"付过一次学费（#65：V8-5 的 `bus_tog`/`hb_tog` 挂在同一根发射触发器上，`cdc.rpt` 里 unsafe 从 1 长到 3，第 6 项当时一声不响）。后续：#209 归因完成 —— 那条 Critical-10 是 `link_active = \|s_pkts[15:0]\|` 被像素域三级链采样，结构**从 `fc314bb` 起就在**，是"报告一直不说"，不是 r98 新长出来的 ⇒ r99 用一行 `src/rtl` 改动把它闭掉 |
| 证据路径 | `report/log/issues.md` #209 及其"归因完成"节；`build/r98_gates.txt`、`build/r98_chain_console.txt`、`build/r98_cdc_details.txt`、`build/r98_cdc_summary.txt`、`build/evidence_r75/cdc.rpt`（对照端）、`build/r97` 期 cdc 件（正控：差集为空 ⇒ 规则能绿）；`build/r99_cdc_gate_proof.txt`（正/反例同批）；台账目录 `build/runs/r98/` |

# r99 —— #209 那一行改完，五刀一起上板；WNS 掉到 0.284 不写成损失

| 字段 | 内容 |
| --- | --- |
| 轮次 | r99（2026-10-01，正式件 `build/system.bit` md5 `b0f0914becc1`，已烧板） |
| 改动 | ① `src/rtl/eth/eth_udp_video_top.v`（#209，**本轮唯一一处 CDC 侧改动**）：`link_active` 不再由 `\|s_pkts[15:0]\|` 组合直出，改由 `gmii_rx_clk` 域的触发器给（复位清 0）⇒ `pl_video_top.v:465-470` 那三级 `ASYNC_REG` 链第一拍采的是触发器输出而不是计数器译码口，语义只差一拍。② #128（`shown_rate` 接进顶层）。③ #185/#186（`frame_latency`）。④ #188（`icmp_tx` 零载荷一支）。⑤ #201（`frame_reasm` 的 `wr_en` 边界） |
| 源码指纹 | `top=f379805a9490`、构建前当场算 `rtl=b034527b6ddd`、门禁内念出的 rim 凭据 `rtl=9fecdc0bb6ec`（`build/r99_gates.txt` 第 36 行）⇒ **同一轮里出现两枚 rtl**：`b034527b6ddd` 是链起飞前那一次、`9fecdc0bb6ec` 是 #185/#186 并进之后重新构建的那一次。台账按门禁件那枚为准（`9fecdc0bb6ec`） |
| 各域 setup/hold 最差值与失败端点 | `eth_rxc` **0.284 / 0.051**；`clk_fpga_0` **1.117 / 0.060**；`clkout0_1` **1.317 / 0.064**；`sys_clk` **15.198 / 0.210**。失败 setup/hold **0 / 0**，总端点 50867 |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | LUT `14330`（as Logic 10145 + Memory 4185，Dist RAM 仍 4044）、FF `8078`、BRAM `95`、DSP `19`、Dynamic `2.213 W` / 估算结温 52.6 ℃（置信度 Low）。差量**未归属**（五刀同轮、无逐层件） |
| 告警条数按类 | `cdc.rpt` 的 Critical 配对集合**回到与采纳基线一致**（r98 多出的那条 `eth_rxc>clkout0_1` 消失）；门禁 `methodology CRIT 0`；`Synth 8-7137` 未逐轮归档 ⇒ 部分 `NOT_MEASURED` |
| 判 20 项 | 门禁 **19 绿 / 1 红**，唯一红是声明过的 `C5c`（台架 140 PASS + 1 FAIL，指纹 fresh）；试冻结按设计 REFUSE ⇒ 冻结集仍 r75 |
| 对照方式 | 全流构建 + 上板复验（机器侧）；CDC 那条用 r98 的**真红**当反例做规则对照（正控 r97 差集为空 ⇒ 能绿；反例 r98 差集 = `eth_rxc>clkout0_1` ⇒ 能红） |
| 结论：**采用** | 理由：#209 把 r98 拦下的那条 Critical 收掉，其余四刀各有"改前红 + 变异对照"。⚠ **时序那一格按 T2 特别标注**：WNS 从 r97 的 +0.720 掉到 +0.284 —— **这个绝对差既不是收益也不是损失**（两版都 0 失败端点、最差那一格两版都归属 `u_icmp_tx` 那族 12 级路径）；本轮真正的时序结论只有一句"仍然收敛、瓶颈没换地方"。WHS +0.051 的归属**换了来源**（从 `u_rx_par/p_sof → u_reasm/have_lo` 搬到 `u_eth/u_lm/full_d_reg` 自路），这一格含自加的 0.8 ns 不确定度、不是深度问题 |
| 证据路径 | `report/log/issues.md` #209（落地段）；`build/r99_gates.txt`、`build/r99_chain_console.txt`、`build/r99_flash_2_program.txt`、`build/r99_flash_3_app.txt`、`build/r99_cdc_gate_proof.txt`；台账目录 `build/runs/r99/`；`data/metrics.csv` 的"实现后动态功耗 2.213 W / 结温 52.6 ℃"两行指的就是这一轮 |

# r100 —— #141 与 #206 合在一轮：判否、整轮回退

| 字段 | 内容 |
| --- | --- |
| 轮次 | r100（2026-10-01 10:37–10:56 构建；**未刷板，整轮回退**） |
| 改动 | ① `src/rtl/eth/icmp_tx.v`（**#141**：三处 16 位"减一后"提前寄存）。② `src/rtl/eth/icmp_rx.v`（**#206**：`total_length - 28` 的下界守卫，畸形小包不让解析器多吃后续包）。③ `src/rtl/top/pl_video_top.v`、`src/rtl/top/system_top.v`（四条 `docs/` 旧指针改指 `report/`）。两刀**合在同一轮** ⇒ 这正是台账要避免的形状，见下面"归属"一栏 |
| 源码指纹 | `top=2bf2ceeede07`、`rtl=71faa69be8c9`；位流 `b3769af3257e`（未上板） |
| 各域 setup/hold 最差值与失败端点 | **全设计 WNS −0.110 ns / 失败 setup 端点 1**（门禁头两项当场 FAIL）；WHS **+0.051 / 0** 失败。逐域：`clk_fpga_0` 1.282 / 0.056、`clkout0_1` 1.617 / 0.053、`sys_clk` 14.247 / 0.121、`eth_rxc` **Slack 读不出（那一格是违例）**。总端点 50947 |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | LUT `14356`、FF `8126`（≈ #141 那 +48 的量级，与隔离滚同量）、BRAM `95`、Dynamic `2.211 W`。⚠ 增量**未归属**：两刀同轮，`FF +48` 与 `LUT` 的差没做逐层相减 |
| 告警条数按类 | 未归档 ⇒ `NOT_MEASURED`（本轮不采纳，本来也不进首页） |
| 判 20 项 | 门禁红 **3 项**：`WNS −0.110 < 0`、`失败 setup 端点 1 != 0`、第 15 项"报告里有 1 行 FAIL 没有 RESULT…PASS 汇总行"（而那 1 行仍是同一条已声明的 `C5c`，指纹 top=2bf2ceeede07 fresh）；边缘条带 `tb_edge_rim_r100.txt` 无 FAIL |
| 对照方式 | 全流构建（**故意让它跑完**：门禁会因第 2 项时序红而拒绝冻结，"这正是要它自己说出来的话"）；判读靠隔离构建 `build/isolated_r104_141/`（前一日 +0.525 那一份）与正式构建的对照 |
| 结论：**回退**（#141 本轮搁置，#206 单独带走 ⇒ r101） | 三条理由，逐条有件：① **红的那条不是 #141 动的那条路** —— 违例是 `u_icmp_tx/ip_head_reg[2][2]/C → check_buffer_reg[17]/D`（同一段 ICMP 里的 **IP 首部校验和累加**），而 #141 那一族在隔离构建里已经 12 次→0 次地离开关键路径。② 最合理的读法是"**#141 那 +48 个 FF 改了打包密度，把另一条本来贴着线的路推过了线**"；结合隔离构建给的 +0.525，这一轮给的是**反例**。③ 所以 #141 的正确处置是**搁置**：要重做就得连"多滚一轮看方差"一起做，那不再是顺手一刀的成本。回退用指纹钉：`src/rtl` 回到 `rtl=9fecdc0bb6ec`（= 板上 r99）、`--match` 答 fresh、`metric_recheck` 红 0、D5 硬错 0 —— **不是"我记得改过什么"** |
| 证据路径 | `report/log/issues.md` 2026-10-01 10:57 与 12:52 两节；`build/r100_gates.txt`、`build/r100_chain_console.txt`、`build/r100_chain.sh`（含一条自曝：`sed 's/^NN=99$/NN=100/'` 只换了 NN、没换硬编码提示 ⇒ 控制台第一行写着"起 r99 构建"，归 #211 那一族）、`build/isolated_r104_141/`；台账目录 `build/runs/r100/` |

# r101 —— 把 #141 摘掉只留 #206：采纳，并公开一条 WNS 与 WHS 都换归属的读数

| 字段 | 内容 |
| --- | --- |
| 轮次 | r101（2026-10-01 13:00–14:50，正式件 md5 `ddf972657525`，已上板） |
| 改动 | 与 r100 的差别只有一件事：**这一轮不带 #141**。留下：`src/rtl/eth/icmp_rx.v` 的 #206 长度守卫 + 四条 `docs/` 旧指针改 `report/` |
| 源码指纹 | `top=2bf2ceeede07`、`rtl=2bf4eb346f80`（`build/r101_gates.txt` 第 35 行） |
| 各域 setup/hold 最差值与失败端点 | `eth_rxc` **0.506 / 0.034**；`clk_fpga_0` **1.509 / 0.028**；`clkout0_1` **2.054 / 0.066**；`sys_clk` **14.971 / 0.130**。失败 setup/hold **0 / 0**，总端点 50867；WPWS 0.264。**全设计 WHS +0.028 的归属换了域**（从 r99 的 `eth_rxc` 换到 100 MHz `clk_fpga_0`）⇒ 首页必须按新主人重写整句，不能只换数字 |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | LUT `14359`（26.99 %）、FF **`8078` 一字未动**（⇒ #206 那一刀的代价是组合逻辑侧的，没有新增存储）、BRAM/DSP/功耗/估算结温与 r99 同 |
| 告警条数按类 | 门禁 `methodology CRIT 0`、`端口宽度警告 8-689 0`；逐类未归档 ⇒ `NOT_MEASURED` |
| 判 19 绿 / 1 红（分母 20 项） | 唯一红 = 顶层台架那 1 行 FAIL（公开的 `C5c`），`PASS 行数=140`、指纹 fresh；试冻结照旧 REFUSE（冻结集仍 r75）。`metric_recheck` 判 11 行**红 0** |
| 对照方式 | 全流构建 + 三步 JTAG 上板（`RST_SYSTEM/PS7_INIT/POST_CONFIG ok` + `DDR_ECHO 5A5AA5A5` → `PROGRAMMED xc7z020_1` → `RESUME ok / FLOW_DONE`）+ 板级 `board_verify` **PASS（判红 0 步）**、`geom_check ok=10 fail=0`、串口 105 条 97.2 s |
| 结论：**采用** | 理由：功能修复有凭据（改前红/改后绿/变异对照三段齐），资源与端点侧"什么都没变"是**代价为零**的证据；门禁形态与 r97/r99 同档 ⇒ 可采纳。⚠ 按 T2：0.284 → 0.506 **不写成收益**（同批放置摆过 0.4 ns），只写"仍收敛 + 瓶颈换没换域"。板读结温这次 62.62 / 62.78 ℃（raw/OSD/gpio 四处同源，`build/board_temp_r101.txt`）—— 与 r99 那次 57.2–57.4 ℃ 的差**说明的是工况不是谁改凉了** |
| 证据路径 | `report/log/issues.md` 2026-10-01 14:50 节；`build/r101_gates.txt`、`build/r101_flash_1..3*.txt`、`build/r101_board_verify_console.txt`、`build/board_temp_r101.txt`、`build/r101_geom_recheck.txt`；台账目录 `build/runs/r101/` |

# r102 —— #218（`ping -l 0` 把 ICMP 接收机永久楔死）闭环

| 字段 | 内容 |
| --- | --- |
| 轮次 | r102（2026-10-01 19:1x–20:2x，正式件 md5 `bf11b78fe45d`，已上板） |
| 改动 | `src/rtl/eth/icmp_rx.v`（#218）：`st_rx_data` 补两条出路 ——（a）`icmp_data_length == 0` 直接判"数据段已结束"；（b）`rx_dv` 掉下去时有出路。台架 `sim/tb_icmp_rx_len.v` 把"钉住楔死"的旧期望换成"必须走干净 + 端到端不许毒死下一个包"。⚠ 回退时把 r100 那四条 `docs/` 指针修正一并退回，本体在提交 `15db112` 与两份凭据里 ⇒ 这轮的 `src/rtl` 位移（`icmp_rx.v` +8 行）之后要重跑 D5 复认 |
| 源码指纹 | `top=2bf2ceeede07`、`rtl=7a431249d550`（`build/r102_gates.txt` 第 36 行） |
| 各域 setup/hold 最差值与失败端点 | **最差那一格换了域**：`clkout0_1` **0.384 / 0.064**（= 全设计 WNS 的归属！）、`eth_rxc` **0.453 / 0.052**、`clk_fpga_0` **1.873 / 0.056**、`sys_clk` **14.243 / 0.147**。失败 setup/hold **0 / 0**，总端点 50868；WPWS 0.264 |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | LUT `14355`（比 r101 少 4、比 r99 多 25 —— 我第一版写错过这两句，读回时改掉）、FF `8079`（+1，也不是"一字未动"）、BRAM `95`、Dynamic `2.214 W`。增量**未归属** |
| 告警条数按类 | 门禁 `methodology CRIT 0`、`端口宽度警告 8-689 0`；逐类未归档 ⇒ `NOT_MEASURED` |
| 判 20 项 | **19 绿 / 1 红**，红 = 声明保留的 `C5c`，与 r101 采纳时逐字同形；试冻结 `freeze_evidence.sh 102` **REFUSE**（协议要求的样子，不是故障）；`metric_recheck` 由红 8 回到**红 0**（判 68 个数） |
| 对照方式 | 全流构建 + 板上 A/B 复跑（这是这条判据的唯一形态）：修前 `ping -n 4` 在 `ping -n 3 -l 0` 之后**永久 0/4**；修后 `ping -n 4` 4/4、`ping -n 3 -l 0` **3/3 且回复"字节=0"**、紧接着再 `ping -n 4` **4/4** ⇒ "自己不应答 + 毒死后面所有包"两点都在板上消失 |
| 结论：**采用** | 理由：#218 有一条**能从网络上敲出来的**机理（一条 `ping -l 0` 就能把接收机永久楔死），修法是状态机出路、不动 CDC 结构，板级 A/B 闭环。本轮唯一 RTL 改动**没有把设计推近任何一条边界**（两端都 met、失败端点都 0）⇒ 按 T2 只报"两条都 met、最差那一格换了主人"。⚠ 一处我自己的假账当场修掉：门禁的桥接行我一度拿 HEAD 当锚 ⇒ 先红在一把我自己造的假账上（#202/#220 同族） |
| 证据路径 | `report/log/issues.md` 2026-10-01 20:1x–20:2x 两节与 #218 根因/落地两节；`build/r102_gates.txt`、`build/r102_jtagboot.txt`、`build/r102_program_pl.txt`、`build/r102_appreload.txt`、`build/r102_board_verify.txt`；台账目录 `build/runs/r102/` |

# r103 —— #189（旋转支"有没有小数"看错一位宽）；同时暴露"上一版位流从来没进 git"

| 字段 | 内容 |
| --- | --- |
| 轮次 | r103（2026-10-01 21:0x–21:4x，正式件 md5 `f8439575eec5`，已上板） |
| 改动 | `src/rtl/process/zoom/zoom_mapper.v`（#189）：旋转支判小数改用**完整 16 位**（`rot_y_has_frac = rot_ys[15:0] != 0`）、权重改成翻过号的 16 位小数 `256 − ceil(f·256)`、并**删掉下游第二次翻转**。这一刀**全部在组合逻辑里** |
| 源码指纹 | `top=2bf2ceeede07`、`rtl=50586c64bb87`（`build/r103_gates.txt` 第 36 行） |
| 各域 setup/hold 最差值与失败端点 | `eth_rxc` **0.608 / 0.053**（= 全设计 WNS/WHS；0.608 是它 8 ns 周期的 7.6 %）；`clk_fpga_0` **1.035 / 0.062**；`clkout0_1` **1.061 / 0.056**；`sys_clk` **14.849 / 0.134**。失败 setup/hold **0 / 0**，总端点 50868；WPWS 0.264 |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | LUT **`14333`（比 r102 少 22）**、FF **`8079` 与 r102 完全相同**（这一句是"这一刀没新增触发器"的直接凭据：改的全是组合侧）、`LUT as Memory 4186`、BRAM `95` tile、DSP `19`、Dist RAM `4044` |
| 告警条数按类 | 门禁 `methodology CRIT 0`；逐类未归档 ⇒ `NOT_MEASURED` |
| 判 20 项 | **19 绿 / 1 红**（仍 `C5c`）。新尺子带改前红：`tb_zoom_frac` 的 S1/S2/S3（扫 3726 个像素、命中 10 个 ⇒ 改前 S3 红；改后 0 个 ⇒ 绿）；同族另三份台架无回归 |
| 对照方式 | 全流构建 + 台架两端夹逼 + **两把尺子当场抓我自己的错话**（一条暴露"上一版位流不在 git 里"：`git show 321fabe:build/system.bit` 实读得到的是 `ddf972657525` = **r101**，`git log --stat -- build/system.bit` 显示最后一次提交 bit 的正是 r101 那一件） |
| 结论：**采用** | 理由：#189 是"正确性 + 头牌口径"级缺陷（旋转态那一格整体错一行、双线性取到相邻另一行的源像素），改完 `LUT −22`、FF 一字未动 ⇒ 资源侧是**这一刀的成本核算**不是时序收益。⚠ 本轮起立的新规矩：**每轮采纳时把 `system.bit`/`system.xsa` 一起提交**，让"板上那一版"永远抽得回来（#219 那条缺口补上之后的第一次生效就是 r104） |
| 证据路径 | `report/log/issues.md` 2026-10-01 21:1x（#219）与 21:4x（r103 采纳）两节；`build/r103_gates.txt`、`build/r103_tb_*.txt`、`build/crit_paths.txt`、`build/setup_paths.rpt`、`build/hold_paths.rpt`（这三份是本轮**重跑**的——它们在 r102 收尾时是 9-29 的旧件，这就是"数字对账必须连凭据一起对"的原因）；台账目录 `build/runs/r103/` |

# r104 —— #141 落板：这一轮的"收益"是下一轮那次复算才成立的

| 字段 | 内容 |
| --- | --- |
| 轮次 | r104（2026-10-02 01:2x 采纳并上板；正式件 md5 `680f38f5794c`） |
| 改动 | `src/rtl/eth/icmp_tx.v`（**#141**）：三处 16 位"减一后"提前寄存（把应答计数的并行比较从关键路径上摘掉）。**只带这一刀**——这正是 r100"两刀合一轮导致归因不清"那次学费的直接产物 |
| 源码指纹 | `top=2bf2ceeede07`、`rtl=8997a62b75ba`（`build/r104_gates.txt` 第 36 行；同一枚出现在 `data/metrics.csv` 台架行的 provenance `fpver=norm1 top_md5=2bf2ceeede07 tb_md5=36d0de483e6d rtl_md5=8997a62b75ba`） |
| 各域 setup/hold 最差值与失败端点 | `eth_rxc` **0.812 / 0.056**；`clk_fpga_0` **1.358 / 0.053**；`clkout0_1` **2.674 / 0.068**；`sys_clk` **15.036 / 0.121**。失败 setup/hold **0 / 0**，总端点 50948；WPWS 0.264 |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | LUT `14334`（+1）、FF **`8127`（+48）**、BRAM `95`（67.86 %）、DSP 本轮未逐轮归档 ⇒ `NOT_MEASURED`、Dynamic `2.211 W`。**+48 FF 全部归 #141**（三组 16 位"减一后"寄存器），且与隔离滚 `build/isolated_r104_141/` 量到的 +48 **一致** ⇒ 两次独立构建给出同一代价，这才是可写的对照 |
| 告警条数按类 | 综合告警名册 **19 种码，逐码计数与 r103 一模一样**，含 `Synth 8-7137` 的寄存器身份列表都相同 ⇒ "没有隐藏代价"的证据，**不是"更好"**。门禁 `methodology CRIT 0`、`端口宽度警告 8-689 0`、`多驱动 net 0` |
| 判 22 项 | 门禁 **21 绿 / 1 红**（唯一红仍是声明过的 `C5c`）；顶层台架判据条数同为 **141 条**（140 PASS + 1 FAIL）——"同为 141 条"不是巧合而是**同一把尺子没动过**（本轮只带 #141 那一刀），一条判据都不许靠空集通过 |
| 对照方式 | 全流构建（采用笔）+ 副本预验证（`build/isolated_r104_141/`）+ 下一轮 r105 的**同树重滚复算**（收益的成立是在 r105 判的，不是在本轮） |
| 结论：**采用** | 理由（三条各自有凭据）：① 目标那一族从最差位上消失，新最差是 `u_eth/u_rx_par/udp_off_reg[1] → p_good_reg/D`，**9 级、其中 CARRY4 占 5**，logic 43.1 % / route 56.9 % ⇒ 新最差是**算术深度**不是绕线；② 次差（同一份 `build/crit_paths.txt`）里 `ip_head_reg[4][1] → check_buffer` 那一族**还在**，但退到 **1.111 ns / 10 级** —— r100 当年就是被这一族以 −0.110 咬掉 ⇒ **这次它余量为正，这是"没退回上一次的失败"，不是"改进"**；③ WNS 0.608→0.812 这 +0.204 在本轮**不写成收益**（还没做同树复滚），到 r105 才成立。⚠ 一处我自己写错的档案当场改口：`build/system.bit` 早在 23:26 就被 r104 构建覆盖，而我把"仍是 r103"写进了三处档案 |
| 证据路径 | `report/log/issues.md` 2026-10-02 00:56 / 00:59 / 01:10 / 01:28 四节；`build/r104_gates.txt`、`build/timing_summary.rpt`、`build/crit_paths.txt`（01:23 重生成）、`build/hold_paths.rpt`（01:24）、`build/utilization.rpt`、`build/power.rpt`、`build/r104_board_verify_console.txt`、`build/r104_board_ping.txt`、`build/evidence/r104_temp_lines.txt`、`build/evidence/r104_serial_raw.txt`、`build/evidence/r104_c5head_band.txt`；台账目录 `build/runs/r104/` |

# r105 —— 什么都不采纳的一轮：它把"收益"这两个字的资格量出来了

| 字段 | 内容 |
| --- | --- |
| 轮次 | r105（2026-10-02 08:27–09:4x；**无正式构建、无刷板**，板上仍是 r104 `bit 680f38f5794c`） |
| 改动 | **无 RTL/约束改动**。三件产出：① 时序 A/B `build/r105_ab_rolls.sh`（两把隔离滚，`OUT` 全在 `build/r105ab_*`，正式 `build/` 一字未动）；② 新台架 `sim/tb_head_rot_displace.v`（#167 映射那一半）+ 凭据 `build/r105_tb_head_rot_displace.txt`；③ C8c 八档并回承重台架 `sim/tb_v98_top_seam.v`（+85 行 / 两处 hunk），并补一条真判据 `C8cself`——副本注释里那句"自证在里面"原本是**空头支票** |
| 源码指纹 | A/B 两版 norm md5：post `8dfa56ec7b26`、pre `6e91edb0305b`；单变量由 `git diff --name-only 54346ae HEAD -- src/rtl` 实测证明**只差一个文件** `src/rtl/eth/icmp_tx.v`。板上身份未变（`bit 680f38f5794c`、`rtl 8997a62b75ba`）⇒ 本轮不改首页 |
| 各域 setup/hold 最差值与失败端点 | post（#141 在树里）**三个独立构建调用都是** `WNS 0.812 / 失败 0 / 总端点 50948`，逐域 `clk_fpga_0 1.358 / eth_rxc 0.812 / clkout0_1 2.674 / sys_clk 15.036`；pre（板上曾是 r103 的那版）**两个独立调用都是** `0.608 / 0 / 50868`，逐域 `1.035 / 0.608 / 1.061 / 14.849`。hold 两侧本轮未逐域留件 ⇒ `NOT_MEASURED` |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | 本轮不采纳 ⇒ 无资源增量。可归属的事实只有一条：三/两个样本的**位流 md5 各不相同**（post `680f38f5794c` / `644fb5ac9593` / `fe099177997a`；pre `f8439575eec5` / `452b0696f145`）⇒ **复现的是时序，不是"同一份文件被念了两遍"** |
| 告警条数按类 | 未取（本轮无构建）⇒ `NOT_MEASURED` |
| 判 2 项 | 判读阈值**写在起飞之前**（08:27，写在任务 #171 与那条提交正文里）："**极差 ≥ 0.4，或 post 最小值 ≤ pre 最大值 ⇒ 收益不成立**"。实测 post 最小值 `0.812` > pre 最大值 `0.608` ⇒ 走"量过、成立"那一支：**#141 在这套策略下是可复现的 +0.204 ns，并且四个时钟域一起抬**（`eth_rxc +0.204 / clk_fpga_0 +0.323 / clkout0_1 +1.613 / sys_clk +0.187`），不是一个端点的运气 |
| 对照方式 | **检查点复算 / 同树重滚**（两个隔离目录 `build/r105ab_post_1/`、`build/r105ab_pre_1/`，读数从各自 `timing_summary.rpt` 现场抽，不抄台账） |
| 结论：**采用（采用的是口径，不是设计改动）** | 本轮真正落库的是一条**公开改口**：本文与台账里那句"同一条路在两次构建之间实测摆过 0.4 ns（放置抖动）"**把跨变体的散布当成了同树重复滚的噪声底用**——今天量到同树重复滚的底是 **0.000**（两对，外加我早就有的第三样本）。0.4 ns 那个数本身不动（它是当时那两次构建之间的实测），**动的是用法：用它去否掉一个 +0.204 是错的**；要检验"换个策略还涨不涨"得**扫策略**（那是另一条轴，历史上确实摆过 0.4 ns），不是重复滚同一套。⇒ 这条成为本台账第 2 节"基线可比性"的第二根柱子。⚠ 仍然不许的两句话也一并写进 `report/known_issues.md`：① 这不宣称 #141 在所有策略下都涨；② 更不宣称"时序到头了"——物理侧（Pblock/疏解绕线）与 OSD 那条 23 级读侧锥（#105）都还没动 |
| 自曝的一条（原样留着） | 链子第 3 轮被**我自己写的守卫**拒绝：脚本只在 pre 档主动装树、post 档只核对不写 ⇒ 守卫读出 `got=6e91edb0305b want=8dfa56ec7b26` 直接 REFUSE，**没有拿错树去滚**（守卫存在的理由被当场证明）；trap 把文件还原并核对，跑完 `git status` 对 `src/rtl` 为空。那一行已补成"post 也主动装树" ⇒ 表里 post/pre 各只有 1 次**本趟**隔离滚 + 各自正式构建 = 每边两个独立样本，够判读，第三样本随时能补 |
| 证据路径 | `report/log/issues.md` 2026-10-02 09:1x（A/B 出数并改口径）、09:3x（把 09:1x 那句收回一半）、09:4x（#223 结案）三节；`build/evidence/r105_ab_rolls.txt`、`build/r105_ab_results.txt`、`build/r105_ab_rolls.sh`、`build/r105ab_post_1/`、`build/r105ab_pre_1/`、`build/isolated_r104_141/`、`build/evidence/r105_c8c_rawtap_8codes.txt`、`build/r105_tb_head_rot_displace.txt`；提交 `3fa0a97`；台账目录 `build/runs/r105/` |

# r106 —— 收包链的 `p_good` 锥提前一拍；顺带撞出"门禁那句自指的话有两个自洽解"

| 字段 | 内容 |
| --- | --- |
| 轮次 | r106（2026-10-02 12:06 构建起飞、14:58 上板；正式件 md5 `f55bd04d494d`、`system.xsa` `65e84d492c33`） |
| 改动 | ① `src/rtl/eth/udp_rx_parser.v`（时序第一刀，打的是**当前的 WNS 归属者**）：`pay_start = udp_off+8` / `pay_end = udp_off+udp_len-1` **提前一拍算好并寄存**，换掉 `p_good` 锥里那一级加法（同一手法本仓第二次用：#141 是 `icmp_tx`）；两个新寄存器一起进复位清单，免得 `Synth 8-7137` 涨数。② `src/rtl/eth/` 下 14 份文件的厂商历程注释清理（**删的是重复叙述，不是披露**：厂商来源仍在 `report/background_and_novelty.md` 与 `report/log/version_lineage.md`；代码逐字符不变由 `build/trim_comments.py --check` 证） |
| 源码指纹 | `top=2bf2ceeede07`、`rtl=359be31de751`（`build/r106_gates.txt` 第 35 行；变异对照恢复后 `rtl_md5` 与变异前相同 ⇒ 树没被变异留下残渣） |
| 各域 setup/hold 最差值与失败端点 | `eth_rxc` **0.723 / 0.051**（门禁 WNS 就是这一组）；`clk_fpga_0` **1.387 / 0.053**；`clkout0_1` **1.264 / 0.052**；`sys_clk` **13.196 / 0.121**。失败 setup/hold **0 / 0**，总端点 50992 |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | LUT `14323`（26.92 %，比 r104 少 **11**）、FF `8149`（**+22**）、BRAM `95`（67.86 %）、Dynamic `2.214 W`。**+22 FF 归这一刀**（`pay_start`/`pay_end` 两个 16 位界提前一拍寄存；与 #141 那次同族），−11 LUT **未归属**（与注释清理同轮；注释不该改网表，所以这个差值我不念成收益）。触发器数与 LUT 数**必须一起看** |
| 告警条数按类 | 门禁 `methodology CRIT 0`、`端口宽度警告 8-689 0`、`多驱动 net 0`；综合告警逐类名册本轮未归档 ⇒ `NOT_MEASURED` |
| 判 22 项 | **21 绿 / 1 红**（唯一红 = 声明过的 `C5c`），门禁**连跑两次逐字节相同**（0 行差异）；试冻结 **REFUSE**（`build/r106_freeze_attempt.txt`，全绿集仍是 `r75_gates.txt`）；`metric_recheck` 判 **68 个数**（首页层 58、csv 认领 10/10）**红 0** |
| 对照方式 | 全流构建（采用笔）+ **先证尺子有牙再谈绿**：把尾界故意错一拍（`-1`→`-2`）⇒ `tb_udp_parser` 红 2 条、`tb_v795_rx_chain` 红 4 条；并记一条**负结果**：`tb_udp_reasm` 在同一变异下 9 条全绿 ⇒ **它不覆盖尾界，不能当这条的凭据** |
| 结论：**采用** | 理由：WNS 归属者被切开、失败端点仍 0、板级 `board_verify --battery --geom --round=r106` **PASS**（105 条命令 97.9 s 全过、末态回演示默认档 `geom=00400000`、温度三方对账自洽）。⚠ 本轮**最该记住的不是设计而是台账本身**（#229）：首页那句"门禁 22 项 21 绿 / 1 红"**有两个自洽解**（21/1 与 20/2 各自都自洽），因为这句话描述的对象**包含说这句话的那一项**。修法三层都落了：`gatesTally()` 把**除本项外**的读数单独算出来、`d1cBasis()` 用"除本项外 + 本项假定为绿"作基准（这个定义有**唯一自洽点**）、并配**反买通对照**（基准件里除本项外多一个红而首页仍念 21/1 ⇒ 必须红）+ 固定点对照（本项那一格是 FAIL 时，念对的这句话不许再被判红）。`--self` 现在 10 条变异全绿 |
| 我自己的两次流程错（不遮） | ① **把门禁的 stdout 重定向进它自己要读的那份基准件** —— `build/gates.sh` 文件头 15–18 行早就写着正确姿势（"先 `> /tmp/kx/g.txt` 跑完，之后再 `cp` 到位"），我没读那段注释，造出一份"边写边被自己读"的凭据，第一跑读到被截断的文件、`judged=0` ⇒ D1c 直接判不了。教训：**给一个工具加判据之前，先查这个工具自己有没有写过"你会踩的这一脚"** ② 自测里的基准件是我**手搓的** `{judged:22, pass:21, fail:1}`，绕过了新加的"除本项外"代码路径 ⇒ 改完语义后 `--self` 立刻 NaN 报红；改成用**同一个 `gatesTally()`** 解析一份合成门禁文本才被抓出来。**手搓 fixture = 把新代码排除在自测外** |
| 证据路径 | `report/log/issues.md` #229 与 2026-10-02 12:1x / 12:2x 两节；`build/r106_gates.txt`、`build/r106_chain.sh`、`build/r106_build_console.txt`、`build/evidence/r106_gates_firstselfred.txt`（同族反例件）、`build/evidence/r106_serial_raw.txt`、`build/r106_freeze_attempt.txt`、`build/evidence/r106_temp_lines.txt`；台账目录 `build/runs/r106/` |

# r107 —— 分组降扇出：第一次做到"动的恰好是它瞄准的那一条"

| 字段 | 内容 |
| --- | --- |
| 轮次 | r107（2026-10-02 15:44 构建、17:52 上板；正式件 md5 `1f90c795e7e3`、`system.xsa` `8f2e2c9255e9`） |
| 改动 | `src/rtl/eth/frame_reasm.v`（#228）：行覆盖位图 `rows_hit` 的使能从**一根 fo=316 的广播**拆成**按 5 个 64 位 bank 分别使能**。**等价性在动手之前就先量完**（分组改动的逐拍等价 + 错组变异，凭据 `build/evidence/r107_rowok_bank_equiv.txt`） |
| 源码指纹 | `top=2bf2ceeede07`、`rtl=70035a651fa0`（`build/r107_gates.txt` 第 35 行） |
| 各域 setup/hold 最差值与失败端点 | `eth_rxc` **0.725 / 0.050**；`clk_fpga_0` **1.229 / 0.057**；`clkout0_1` **1.224 / 0.059**；`sys_clk` **14.906 / 0.120**。失败 setup/hold **0 / 0**，总端点 51005 |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | LUT `14323` 与 r106 **逐字相同**、FF `8156`（**+7**）、BRAM `95`、Dynamic `2.213 W` ⇒ **这一刀的代价能完整归属**（本台账里少数几个"全归得清"的轮次） |
| 告警条数按类 | 门禁 `methodology CRIT 0`、`端口宽度警告 8-689 0`；逐类未归档 ⇒ `NOT_MEASURED` |
| 判 4 项 | ① **目标族两端夹逼**（同一对端点 `u_reasm/off_reg[12]/C → rows_hit_reg[*]/CE`）：r106 `0.723 ns / 5 级 / route 81.25 %`（最差 8 条里占 6 条）→ r107 **`2.006 ns / 4 级 / route 81.287 %`（最差 10 条里一条都没有）** ② 全设计 WNS 0.723→0.725 —— **换了主人，不写成收益**（T2；新瓶颈 `u_icmp_tx/ip_head_reg[4][19] → check_buffer_reg[17]/D`，9 级 / CARRY4=4 / route 60.881 %） ③ 逐拍等价性与错组变异各一条 ④ hold 侧**只记不动**的一条硬事实：全设计最差 hold **换了主人**（r106 `arp_rx_flag → arp_pend` 1 级 route 80.9 % → r107 `u_cdc/wgray_reg[6] → u_lm/full_d_reg` 0.050 ns、3 级 CARRY4=2、uncertainty 0.800），**全局数 0.051→0.050 看着没动，只看全局会漏掉换主人这件事** ⇒ 首页 hold 行必须按新主人重写整句，不能只换数字 |
| 对照方式 | **检查点复算**（只读探针 `build/tcl/probe_reasm_fanout.tcl` 跑在 r107 的 `system_top_routed.dcp` 上，探针自带计数地板 `SETS from=1 to=16`（16 = `rows_hit` 的位数）与 `CELLS=1646 / NETS=1857`）+ 全流构建（采用笔） |
| 结论：**采用** | 理由：这是本仓第一次出现"动的恰好是它瞄准的那一条"——族内 slack 与级数都动在**同一条端点对**上，代价 7 个 FF、LUT 一格不差，机器侧全绿（门禁两跑逐字节相同 22 项 21 绿/1 红；板级 `board_verify --geom --battery --round=r107` **PASS**，geom 10/0、105 条命令 97.8 s、XADC 60.59/60.68 ℃ 三方对账 ok、ICMP 4/4 与零长度 3/3） |
| 本轮最该留下的一条（我自己写的旁证是坏的） | 差分台架的**滚动散列**第一版是 `h = (h<<5) ^ (h>>27) ^ b` 再掩 31 位：每步左移 5、只折回 4 位 ⇒ **差分约 7 步内被湮灭**。腿 c 里第 32/33 字节的差异到末尾完全看不见，两腿散列被打成同一个值 —— 主判据 C2（逐字节对账）**没被骗**，但**那一行打印出来的凭据在骗人**。换成 `h = (h ^ b) * 16777619 mod 2^31`（异或与乘奇常数在模 2^31 下都可逆）后腿 b 两值同、腿 c 三场景两值全不同；同时把 **C6 定成真判据："散列的相同性必须与逐字节结果一致"**。可复用的规矩（台账口径）：**凡是打印出来的旁证（散列、计数、占比）都是一条主张**，要么它的混合可逆/数是重算的，要么就配一条"它必须和主判据同向"的判据，否则它在凭据文件里就是一句会被人引用的假话 |
| 两条工具侧的坑（都已改） | ① `build/tcl/*.tcl` 的**运行时 `puts` 标签带中文**会被 Vivado 的 Tcl 按系统代码页读，第一版探针那一行的 `[llength $pairs]` 干脆没被求值、把 1857 个网络整个倒进输出，下游 `grep\|sed` 又把这条脏行抄进了被跟踪的凭据件（重生成两遍才干净）⇒ 对策：Tcl 运行时打印一律 ASCII，中文只留注释行 ② 用环境变量给 Tcl 传 `get_cells` 模式时值里**不能带花括号**（花括号是 Tcl 语法，作为 env 值就是两个字面字符，谁都匹配不上）；二维数组寄存器 `ip_head_reg[4][19]` 的通配要写在**末尾**（`..._reg*`），写成 `..._reg[*]` 匹配不到 —— 两次都撞在 `SETS from=0` 上，**探针先 REFUSE 再吐空判定，这条地板就是它的价值** |
| 证据路径 | `report/log/issues.md` #228/#230；`build/r107_gates.txt`、`build/r107_reasm_probe.txt`、`build/r107_fanout_verdict.txt`、`build/r107_board_ping.txt`、`build/r107_serial_raw.txt`、`build/evidence/r107_rowok_bank_equiv.txt`、`build/tcl/probe_reasm_fanout.tcl`、`build/r107_probe_reasm.rpt`、`build/evidence/r106_gates_firstselfred.txt`；台账目录 `build/runs/r107/` |

# r108 —— 一拍十项加法拆成两拍各五项：买到 0.356 ns，付出一条更薄的 hold

| 字段 | 内容 |
| --- | --- |
| 轮次 | r108（2026-10-02 18:30 构建、20:5x 采纳；正式件 md5 `25bf35a9900e`） |
| 改动 | `src/rtl/eth/icmp_tx.v`：IP 首部校验和由**一拍 10 项**摊成**两拍各 5 项**（路线图 §7.2 预计算 + 长锥切流水）。**单独一轮，不与 r107 混树** |
| 源码指纹 | `top=2bf2ceeede07`、`rtl=31e35f481032`（`build/r108_gates.txt` 第 35 行） |
| 各域 setup/hold 最差值与失败端点 | `eth_rxc` **0.721 / 0.035**；`clk_fpga_0` **1.524 / 0.053**；`clkout0_1` **1.130 / 0.060**；`sys_clk` **14.324 / 0.159**。失败 setup/hold **0 / 0**，总端点 51029 |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | LUT `14360`（26.99 %，+37）、FF `8168`（+12）、BRAM `95`、Dynamic `2.212 W`。+12 FF 的形状能对上"多一级部分和寄存器"，**+37 LUT 未归属**（扁平 `utilization.rpt` 无逐层行，拆拍后的选择逻辑与部分和寄存器混在这片里） |
| 告警条数按类 | 门禁 `methodology CRIT 0`、`端口宽度警告 8-689 0`；逐类未归档 ⇒ `NOT_MEASURED` |
| 判 5 项 | ① **同一条端点对夹逼**（`ip_head_reg* → check_buffer_reg[17]/D`）：**0.725 → 1.081 ns**，级数 9 → 11（CARRY4 4 → 6）、route 60.9 % → 56.2 %（凭据 `build/r108_cone_verdict.txt`）⇒ 这才是"这一刀自己动了多少" ② 等价性在动手**之前**由差分台架量过：三场景 72/110/72 字节逐字节全同；少加一项（`ip_head_reg[4][15:0]`）的变异体判红，且 6 处不同**全部落在流内下标 32/33**（IP 校验和字段）＝**正对照能动** ③ 改前基线趁构建还没覆盖 DCP 时问回来（`build/r108_cone_before.txt`：这个锥最差 0.725，同锥其余四条 1.224/1.298/1.353/1.410 ⇒ 亚纳秒只有 `[17]` 那一条 bit） ④ 全局 WNS 0.725→0.721 **换主人**（新最差 `u_iddr_rx_ctl → u_icmp_rx/des_mac_reg[*]/CE`，4 级、logic 只 15.7 %、**route 84.3 %**，且时钟网络本身 SCD 5.008 / DCD 4.493 ns ≈ 8 ns 周期的一半） ⑤ **代价同笔念**：全局 hold 从 0.050 薄到 **0.035 ns**，同一格目的地 `u_lm/full_d_reg/D`、源从 `wgray_reg[6]` 换成 `rgray_s1_reg[7]`（3 级 / CARRY4=2，uncertainty 0.800 是我们自己加的严口径） |
| 对照方式 | 副本预验证（差分台架三条腿：腿 b 拆法 vs 改前 / 腿 c 变异）+ **检查点复算**（改前锥必须在构建覆盖 DCP 之前问回来）+ 全流构建（采用笔） |
| 结论：**采用** | 理由：同一条锥自己动了 +0.356 ns（1.081 − 0.725，可归属），代价是一条更薄的 hold（0.050→0.035）**与它的归属换人**一起登记。**本轮最大的产出是本设计"极致"位置第一次被量出来**：收包域的 setup 余量由**时钟树插入延迟 + 自加不确定度**定死 ⇒ **再砍 RTL 逻辑的收益上限趋近于零**（与 task 179 那条 70.5 % route 的 `icmp_rx` 累加锥是同一个结论的两半）。第三名那条 0.957 ns（`u_iddr_rxd/C → reply_checksum_add_reg[31]/D`，9 级里 CARRY4=7）**量过、暂不建议动**：整条 logic 只 29.477 %、**route 占 70.523 %**，最贵一根是 `gmii_rxd[4]` fo=41 routed 3.938 ns ⇒ 正确归因是放置/拥塞不是逻辑深度，同族 1.056/1.113/1.142 是同一个根不算三个新目标 |
| 三条工具账（都是这一程现学） | ① 链子从 `nohup` 的壳里起来时 **`VP_VIVADO_BIN` 没导出** ⇒ `run_one.sh` 报"找不到 xvlog"，四支台架全顶成 rc=2，而构建与只读探针照常成功；症状伪装成"门禁三条红、台架一条没跑" ⇒ 两条链脚本现在都自带 `export` ② 采纳脚本的**新鲜度断言**第一版把锚点选在 stage2 控制台（它在台架之后才被写）⇒ 恒判"旧日志"而拒绝刷板；改成本轮构建控制台（18:30 定格）为准 + 门禁 `指纹(norm1):fresh` 一道。这条断言存在的原因是 **`run.log` 会留在原地**：上一轮的日志同样是 PASS=157 / FAIL=1，光看它就能把上一轮的证据当这一轮的 ③ `adopt_after_chain.sh` 的门禁断言放宽成"红只允许 台架声明红 + 未同步的文档两类"（因为采纳前台页必然还没换数），**这次它照样拦住了 rc=2 那一跑（红数 4 > 3），没有刷板** |
| 眼睛那一半（同轮定案） | 用户复看原话"旋转角在顶部还是有分散的细线"，紧接着按 `rot auto 1 speed 0`（角度停住）答"**停下的时候没有**" ⇒ 归因落定：不是纯 `C5c` 帧头绕回（那一族静止角也该有），而是**每帧换角与帧头那 OFF+2 行的交互**；判据要做成两端（换角维度 + 帧头窗），且**冻结角度必须干净作对照**，否则这条判据盖不住现象、修了也看不出来。凭据 `board/acceptance.md` E4r 行；机器侧同一轮台架唯一红仍是 `FAIL C5c`（`build/r108_tb98_console.txt`） |
| 证据路径 | `report/log/issues.md` #231；`build/r108_gates.txt`、`build/r108_cone_verdict.txt`、`build/r108_cone_before.txt`、`build/evidence/r108_csum_diff.txt`、`build/r108_serial_raw.txt`、`build/r108_tb98_console.txt`、`build/tcl/probe_cone_r108a.rpt`、`build/probe_cone_r108before.rpt`；台账目录 `build/runs/r108/` |

# r109 —— OSD 读侧插一拍（把相对最紧的那一格推开）+ 一次自己挡住自己的 127 分钟

| 字段 | 内容 |
| --- | --- |
| 轮次 | r109（2026-10-03 00:0x 构建完成、02:4x 采纳；正式件 md5 `21227687e925`） |
| 改动 | ① `src/rtl/video/osd_overlay.v`：把喂给装配段的**显示用的数**在源头各寄存一拍（`angle/fps/threshold/gamma_disp/split_pct/lat_*/temp_disp`），并把 `chars` 的读侧起点从"本拍装配"改成"上一拍装配"（新增 `ch_addr_pre`/`ch_r`，`ch_r` 落在分布式 RAM 上）。② `src/rtl/top/pl_video_top.v`（#167）：`rot_fs_tog` 的翻转拍点从 `frame_start` 挪到**绕回请求那一拍的边界**（显示行 594 的第一像素），**CDC 结构一字不动**（还是那一个发射触发器 + `angle_ctrl` 里的三级同步，#65/CDC-11 的形态不复发）。③ `src/rtl/eth/link_monitor.v`（#174）：`gapclr` 与 `frame_done` 同拍时**清零赢** |
| 源码指纹 | `top=2bf2ceeede07`、`rtl=65f311fe99a4`（`build/r109_gates.txt` 第 36 行） |
| 各域 setup/hold 最差值与失败端点 | `eth_rxc` **0.605 / 0.049**（门禁 WNS 归属；最差换回 **r107 那一族** `u_reasm/off_reg[11]_rep → rows_hit_reg[*]/CE`）；`clk_fpga_0` **1.238 / 0.052**；`clkout0_1` **4.094 / 0.053**；`sys_clk` **15.289 / 0.121**。失败 setup/hold **0 / 0**，总端点 51029 |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | LUT `14362`（27.00 %）、FF `8162`（**−6 归 OSD 读侧那一拍**：`ch_r` 落在分布式 RAM 上，没有另占 8 个触发器，实测 **+2 LUT / −6 FF**）、BRAM **95 → 95.5**（+0.5 格归同一刀）、Dynamic `2.214 W`。**刀 ② 与刀 ③ 的 LUT 增量未归属** |
| 告警条数按类 | 门禁 `methodology CRIT 0`；本轮多出一类要注意的**"第四类红"**：第 20 项 `line_cite` 的 D5b「例化者」列红 **8 条**，根因是 `pl_video_top.v` 净增 26 行 ⇒ 该行之后所有 `file:行号` 引用整体 +26（`report/modules.md:33/34/46/50/51/52/53/54`）。逐类 `Checks found` 未归档 ⇒ `NOT_MEASURED` |
| 判 4 项 | ① 同一把尺子、同一个时钟（`build/tcl/probe_clk_worst.tcl`，`-from/-to [get_clocks clkout0_1]`）：最差从 `1.130 ns / 23 级 / route 77.5 %` 换成 `4.094 ns / 21 级 / route 62.8 %` ⇒ **该时钟相对余量 5.65 % → 20.5 %**（这一格原本是"相对最紧"的那一格，绝对最紧仍在 `eth_rxc`） ② 全局 WNS 0.721 → 0.605 是**持有者换了**（`u_reasm` 那一族本来就在 0.6x 附近排队）⇒ 按 T2 既不记收益也不记损失 ③ 快车道（`build/r109_lane_base.txt` 改前基线）④ C12a/b/c 三条新判据，其中 **C12c 是阳性对照：同一个跑里把旧拍点（`frame_start`）再量一遍 ⇒ 必须不相等** —— 这一条证明尺子能动，也把"为什么要挪拍点"钉进凭据，不用额外构建就拿到"改前红" |
| 对照方式 | **检查点复算**（r108 的 DCP 是本轮构建前唯一基线，`build/probe_clk_r109clk01.rpt`）+ **副本预验证**（`build/f2e_preverify.sh` 拷贝树双腿差分：未打刀那腿**只**红 F2e B、打刀那腿 F2e A/B 与 F2a–F2d 全绿 ⇒ `base 红=1(F2e-B=1) → cut 红=0(F2e-B=0)`，`build/evidence/r174_f2e_preverify.txt`）+ 全流构建（采用笔） |
| 结论：**采用（但第一轮我判的是"不采纳"，那条判断也留着）** | 00:0x 那一跑的真实处置是 **不采纳、不刷板、不改首页数字**：链子 00:03:03 构建完成、开始只读探针，我在**探针阶段**并发跑了 `build/f2e_preverify.sh`（它自己起 xsim）⇒ 00:05:19 链子进快车道时 `build/sim/run_one.sh` 的"已有 xsim 在跑"守卫把快车道挡成 rc=2、把顶层台架与边缘条带全挡成 rc=3 ⇒ **构建与三份只读探针是真跑完了，但台架阶段一份凭据都没有**（`tb_osd_lines` 的等价性、C12a/b/c 的第一次读数都还没有）。规矩补硬一条：**链子在飞期间不起第二支 xsim**；预验要么排在链子起飞**之前**，要么等"阶段结束"那行出来之后 —— 被挡的不是凭据文件，是**一整条阶段的 127 分钟**。补救 `build/r109_stage2.sh`（门口先验现场没有活的 xsim）跑完之后才采纳：24 项 = 23 绿 / 1 红 |
| 上一轮写的守卫自证有用 | 我 r109 刚写进快车道的那道守卫（rc=3 且有 `VERDICT` 行才算红、没有就算 BLOCKED，外加门口 `tasklist` 预检）**在这一次证明了自己有用**：它没有把一片挡门念成"20 支判红"，而是明明白白打了 `LANE-REFUSE: 已经有 xsim 在跑`。**红、没数、没跑必须长得不一样** |
| 一条被我复算改重的巡检结论 | 子代理的计数与"这条没问题"都是**待复算的主张**（#236）：`sim/tb_head_rot_displace.v` 文件头第 15 行写着"第二遍用上一帧角度 θ-k（`inv_fit` 也跟着换成 θ-k 那一档，与顶层一致）"，实际代码里 `inv_force` 只在 :40 声明成 `10'd256` 之后**再没被赋值**，mapper 一直吃常数 256；`inv_now/inv_prev` **只出现在 `$display` 里，没有任何比较** ⇒ 这支台架量到的"位移大小"仍可信，但它**没有**证明"倍率与角度同步换档"，我把它当 E4r 的"大小"凭据成立、当"顶层一致性"凭据就越界了 |
| 还欠的（不假装收口） | #237：**#105 那一刀把 `osd_addr` 这把变异对照的牙磨钝了** —— `ch_addr` 从此只供台架判越界、不再决定画出来的是什么 ⇒ `build/sim/mut_control.sh` 的 `osd_addr` 分支变成"只改判据的眼睛、不改 DUT 的画"，而且 sed 仍能匹配 ⇒ **脚本不报警，只有人会漏**。修法是两边重新同源并各配一支变异（`osd_addr_judge` / `osd_addr_draw`，各给 `EXPDIFF`），写在 `build/r110_batch2_ready.md` 的**刀 0（最先做）**：**先修这把尺子再谈后面的刀，否则后面任何"变异对照通过"都建立在一把已经失效的尺子上** |
| 证据路径 | `report/log/issues.md` #232/#234/#236/#237/#242/#243；`build/r109_gates.txt`、`build/evidence/r109_clk01_before.txt`、`build/evidence/r109_clk01_after.txt`、`build/probe_clk_r109clk01.rpt`、`build/evidence/r109_hold_owner.txt`、`build/evidence/r109_metric_rotation.txt`、`build/evidence/r109_deadunit_roster.txt`、`build/evidence/r109_gates_pre_docrotation.txt`、`build/evidence/r109_repin_candidates.txt`、`build/r109_lane_before.txt`（**坏尺子的活标本，保留原样**）、`build/r109_lane_base.txt`、`build/evidence/r174_f2e_preverify.txt`、`build/r109_setup_paths_baseline.rpt`、`build/r109_hold_paths_baseline.rpt`；台账目录 `build/runs/r109/` |

# r110 —— 独热化那根 fo=316 的广播：先停在"一个 −243 LUT 没归属"，归属之后才采纳

| 字段 | 内容 |
| --- | --- |
| 轮次 | r110（2026-10-03 03:0x 读数、04:2x **停在原地不采纳**、07:5x 归属之后采纳并上板；正式件 md5 `2bf95588978f`） |
| 改动 | ① **刀 4①** `src/rtl/eth/frame_reasm.v`：`rows_hit` 的使能从 #107 的"分 5 组"（每项仍要 `new_row & (rbank==k) & (roff==j)` 三项式）**独热化**成 `bank_one[k] & (roff==j)` 两项式，把 **fo=316 那根广播消掉**。② **刀 1** `src/rtl/eth/link_monitor.v`：#174 的 `gapclr` 优先级（r109 已预验，本轮随构建落地）。刀 0（`osd_addr` 变异重新同源）与刀 2/刀 3（死代码）**不在这一轮** |
| 源码指纹 | `top=2bf2ceeede07`、`rtl=c3a03cb163e6`（`build/r110_gates.txt` 第 36 行；与台架留件同一枚，见下面"工具账"） |
| 各域 setup/hold 最差值与失败端点 | `eth_rxc` **0.713 / 0.042**（门禁 WNS 归属，新最差 `u_icmp_tx/ip_head_reg[4][18] → check_buffer_reg[17]/D`，10 级 / CARRY4=6 / route 61.3 %）；`clk_fpga_0` **1.186 / 0.069**；`clkout0_1` **3.799 / 0.068**；`sys_clk` **15.157 / 0.121**。失败 setup/hold **0 / 0**，总端点 51013 |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | LUT `14362 → 14119`（**−243**）、FF `8162 → 8154`（**−8**）、BRAM `95.5`（不变）、Dynamic `2.214 W` / 片上合计 `2.391 W` 一字未动（`build/power.rpt` 实测同值）。**归属只做到 −66**：拷贝树两腿对 `frame_reasm.v` 单独 OOC 综合 ⇒ base `737 LUT / 660 FF`、cut `671 LUT / 642 FF` ⇒ **刀 4① 自己 = −66 LUT / −18 FF**（`build/evidence/r110_attrib.txt`，脚本 `build/r110_ooc_attrib.sh`）。剩下 **−177 未归属**（不可能是刀 1，它加了一棵清零 mux 只会加不减；平铺 `utilization.rpt` 没有逐层行）⇒ **首页只写能归的那 −66，其余留在证据里不念成收益**（T3） |
| 告警条数按类 | 门禁 `methodology CRIT 0`、`端口宽度警告 8-689 0`、`多驱动 net 0`；逐类未归档 ⇒ `NOT_MEASURED` |
| 判 4 项 | ① 抓手判据**达成**：`fo=316` 那根网在本轮报告里**不存在了**（全文 fo 直方图除时钟网 2558 之外最大只有 40），`rows_hit_*/CE` 作为最差终点出现 **0 次** ⇒ #238 那把"分 5 组"确实没做到的事，独热化做到了；但**归属换族**，所以收益不能写成"同一条锥自己变快了" ② 台架 `RESULT tb_v98_top_seam FAIL nfail=1`（唯一 FAIL 是声明过的 `C5c`），PASS 161 行；本轮新加四句按整句读**全绿**（`C12 rot: cmp=5 bad=0 steps=6 \| frozen: cmp=4 bad=0`） ③ 快车道 28/28 全绿（`tb_link_monitor` 由基线红翻绿 ⇒ **#174 修好**） ④ 门禁 24 项 = 21 绿 / 3 红（三条红正是"还没采纳"的正常形状：`C5c` + `doc_currency` 2 条首页仍写 r109 身份句 + `metric` 37 条数字未改口） |
| 对照方式 | **副本预验证**（OOC 双腿归因 `build/r110_ooc_attrib.sh`；`build/r110_apply_cuts_proof.txt`、`build/r110_deadcode_proof.txt`）+ **检查点复算**（`build/evidence/r110_rows_hit_before.txt`、`build/probe_cone_r110rows_hit_before.rpt`）+ 全流构建（采纳笔） |
| 结论：**先"待定"（停在原地不采纳），归属之后采用** | 04:2x 的判断原文："**判据达成、台架/车道干净，但出现一个 −243 LUT 的待解释量 ⇒ 停在这里不采纳**"；机制上讲得通（320 个负载上的 3 输入译码被折叠），但归不到模块就不能写进首页。处置：`git checkout --` 把 `rotate_from_metric.mjs` 第一遍写进首页/`metrics.csv` 的 30 处复原（HEAD 又与板上 r109 一致，尺子红 0），**r110 的位流/报告留在工作树里不提交**（一提交 `metric` 就会在 HEAD 上判红 —— 那正是 #240/#242 记过的自指陷阱）。07:5x 归属做完才采纳，代价一起登记：**`clkout0_1` 4.094 → 3.799 ns（20.47 % → 18.995 %）这一档是让步，不是收益**，照规矩念成"同一族自己动了多少" |
| 工具账（差点白跑一轮，2.5 小时） | 落刀后我用 `find src/rtl -name '*.v' \| xargs md5sum \| md5sum`（`build/r94_bench_chain.sh:68` 那句旧配方）算出 `a936a6bd048d`，与台架留件 `rtl_md5=c3a03cb163e6` 不符，于是写下"这份测量不属于这棵树 ⇒ 必须重跑一轮"。**错在尺子不在设计**：仓里 #202 就把指纹换成了 `fpver=norm1`（每份文件先 `tr -d '\r'` 再 md5，见 `build/rtl_fingerprint.sh`），我用的是按磁盘字节的旧配方，两者对 CRLF 的敏感度不同（`git archive` 交出 CRLF、工作树是 LF）。跑对的尺子 ⇒ **同一枚 `c3a03cb163e6`**，加上 `build/r110_notadopted/*` 整套件本来就来自这棵树 ⇒ 可以直接采纳，不需要再花 2.5 小时重跑。教训形状：**一条"必须重跑"的结论如果来自我自己临时写的哈希式子，先去找仓里那把唯一尺子** |
| 还欠的一条（机理已证、成因未定） | 板上那 1 度：原理图（第 14 页）显示 PL_KEY1/PL_KEY2 各有 4.7 kΩ 上拉并 100 nF ⇒ 松开是被**硬件拉高**的，我最早那个"引脚浮空"假设**作废**（XDC 保持原样，内部上拉与 4.7 kΩ 并联没有意义）；但同一份数据也把我写的"RC 斜率造出 >20 ms 低电平"否掉（τ = 470 µs、充满约 2.4 ms，而 `key_debounce` 要的是复位释放后连续趴低 ≥ 20 ms）；这块板只走 JTAG 下载（无 `BOOT.BIN`），PL 配置发生在电源稳定之后好几秒 ⇒ 连"电源爬升期"这条路也不成立。**在此之前不把任何一种解释写进首页** |
| 证据路径 | `report/log/issues.md` #246/#247/#248/#249/#240/#241/#242/#243；`build/r110_gates.txt`、`build/r110_verdict.txt`、`build/evidence/r110_attrib.txt`、`build/r110_ooc_attrib.sh`、`build/evidence/r110_setup_paths_baseline.rpt`、`build/evidence/r110_rows_hit_before.txt`、`build/evidence/r110_util_hier.txt`、`build/r110_notadopted/`、`build/evidence/r110_serial_raw.txt`、`build/r110_batch2_ready.md`、`build/util_hier.rpt`；台账目录 `build/runs/r110/` |

# r111 —— 没有构建的一轮：把"角度读不回来"量成一条机读欠账

| 字段 | 内容 |
| --- | --- |
| 轮次 | r111（2026-10-03 07:3x；**无构建、无刷板**，板上仍是 r110 `2bf95588978f`） |
| 改动 | **无 RTL/约束改动**。三件产出：① 板侧只读回读（不发任何命令）把固件那条路排除掉；② 新台架 `sim/tb_v111_key_boot.v`（真三份链 `key_debounce`→`key_long`→`angle_ctrl`，参数按 `tb_v87_key_long` 同比例缩 1000 倍）；③ 一处欠账立案：**角度没有机读口** |
| 源码指纹 | 本轮未采（板上身份见上） |
| 各域 setup/hold 最差值与失败端点 | 本轮无构建 ⇒ 逐域 `NOT_MEASURED` |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | 无改动 ⇒ 增量 0；本轮未出 `report_utilization` |
| 告警条数按类 | 未取 ⇒ `NOT_MEASURED` |
| 判 12 项 | `PASS tb_v111_key_boot`，12 条判据，**在未改 RTL 的树上跑绿**（它判的是"机理"不是"修复"）：A 腿"上电那根线读低 1.5×去抖窗后回高"⇒ `short_pulse` 恰好一枚、`angle=1`、`rotate_active=1`、`ltog=0`（与用户看到的"只多 1°、模式没变"**一字不差**）；D 腿"半窗毛刺"⇒ 角度不动（**证明 A 不是"给个低电平就红"**）；B 腿"全程为高"⇒ 不动；C 腿"跨过长按阈值"⇒ 翻 `tog` 而**不**动角度（症状本身把毛刺宽度夹在 20 ms–0.6 s 之间） |
| 对照方式 | 板侧只读回读 + 台架四腿对照（不花构建、不动源） |
| 结论：**待定（机理已证、成因未定）** | 这一句要精确。能钉住的只有：① 能造出这一度的入口是 `key_inc`（唯一 20 ms–0.6 s 低电平窗形状）；② 固件/寄存器侧清白（`CFG_DATA0=0x30400000` ⇒ `rot_auto`(bit9)=0、`rot_speed`(bit[12:10])=0、zman=1/档号 4）。到底是哪一次低电平**需要证据**：示波器/逻辑分析仪看 W18 上电后波形，或**把角度做成机读之后**做一次"没人碰键的上电"复现。修法不依赖成因：**上电武装门**（`key_debounce` 复位释放后必须先连续"看见松着"满一个去抖窗才开始判按下）对所有候选成因都成立 ⇒ 单独一轮（r112），不夹进 r110 采纳 |
| 本轮两处我自己的读数错（都是"尺子先错"，不是设计错） | ① **把 `lane0` 当成 `status`**：第一次读回 `0x41210000 = 0x00000000`，我写成"角度=0"。实际 `lane0` 是 link_monitor 健康快照第 0 条（`system_top.v:235` 的 `lm_axi[lm_lane*32 +: 32]`），而 `status` 那份 32 位里 `angle` **只在 :45 声明、:309 连接、没有任何读者** ⇒ 综合按 "unused … removed" 删掉 ⇒ 板上今天没有机读的角度。新样本规矩：**读一个口之前要先证明那个口真的由我以为是的那个信号驱动**（grep 到端口名不等于接上了，要顺着 assign/例化走一遍） ② **探针没还原 GPIO0 就 `con`**：`ang_probe.tcl` 写 lane 号时是整字 `mwr`，会把 bit19（双线性）/bit20（OSD 反相）一起改掉；第二份 tcl 里把 `BASE` 读到的 `0x000B5000` 写回去并读回确认（`BACK 0x000B5000`）。形状教训：**写整字探针必须自带还原 + 还原回读** |
| 证据路径 | `report/log/issues.md` #247/#248；`build/evidence/r111_angle_readback.txt`、`build/r111_lane_after.txt`、`sim/tb_v111_key_boot.v`；台账目录 `build/runs/r111/` |

# r112 —— 两刀一起进（武装门 + 校验和累加器 32→20）：收益记给"结构账变干净"，不记给 WNS

| 字段 | 内容 |
| --- | --- |
| 轮次 | r112（2026-10-03 08:0x 落刀、09:0x 采纳；正式件 md5 `897fa9d93956`） |
| 改动 | ① **刀 A** `src/rtl/util/key_debounce.v`：上电**武装门**（`armed` + `acnt`，复位释放后必须先连续"看见松着"满一个去抖窗才开始确认按下）—— #52"复位释放本身不许造事件"的第二次应用。② **刀 B** `src/rtl/eth/icmp_tx.v`：IP 校验和累加器 **32 位 → 20 位**（累加器只装十个 16 位项之和，上界 `10 × 65535 = 655350 < 2^20` ⇒ bit31:20 恒 0，**12 位进位链在为恒零的半截买单**） |
| 源码指纹 | `top=56c269602e18`、`rtl=0701e9d1e772`（`build/evidence/r112_bit/tb_v98_report.txt` 头部 provenance 与 `build/r112_gates.txt` 第 35 行两处同值） |
| 各域 setup/hold 最差值与失败端点 | `eth_rxc` **0.445 / 0.050**；`clk_fpga_0` **1.135 / 0.056**；`clkout0_1` **4.467 / 0.059**；`sys_clk` **14.463 / 0.133**。失败 setup/hold **0 / 0**，总端点 **51135**。**最差六条全是 `u_rx_par/p_eof_reg → u_reasm/rows_hit_reg[*]/CE` 这一族**（0.445 ×4 + 0.549 ×2，4 级、route 84.276 %） |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | LUT `14154`（26.61 %，**+35**）、FF `8188`（7.70 %，**+34**）、BRAM `95.5`（68.21 %，不变）、DSP `19` 未逐轮归档。**增量归属闭合到个位**（两份逐层件相减 `build/evidence/r112_util_attrib.txt`）：`u_pl` **+66 LUT / +46 FF**（= 两只 `key_debounce` 的武装门，综合把它们展平进 `u_pl` 的桶，逐层表里没有 `u_k1/u_k2` 行）；`u_icmp_tx` **−31 LUT / −12 FF**（刀 B；OOC 那份是 −40/−12，差 9 个属两口径正常差；**FF 两边都是 −12，与 32→20 位的算术逐位对上**）⇒ `+66−31=+35`、`+46−12=+34` **闭合**，本轮**没有"归不到模块"的余量**。另：`u_reasm` 668/546 → 668/546 **一格没动** = "该族逻辑没改"的设计内资源旁证 |
| 告警条数按类 | `report_methodology` 逐类：**446 = DPIR-1 2 + LUTAR-1 1 + SYNTH-5 336 + SYNTH-6 98 + TIMING-9 1 + TIMING-10 1 + TIMING-18 7**（七项相加 446 闭合，与 r113/r114/r115_base 三份逐字相同）；综合告警名册 `Synth 8-xxxx` **21 类**（`build/evidence/r112_synth_roster.txt`），r113/r114 差分**为空** ⇒ 属性级改动没引入新结构问题 |
| 判 3 项（物理侧三滚 A/B/C）+ 门禁 24 项 | 门禁本轮 `build/r112_gates.txt` = 24 项 **21 绿 / 3 红**（红是 tb_v98 声明红 + 文档时效 + 数字对账，即"还没采纳"的形状）；A/B/C 三滚各一条判据见下面对照方式 |
| 对照方式 | **全流构建**（采用笔）+ **检查点复算**（物理侧三滚，同一份 `system_top_opt.dcp` 起跑、唯一变量写在脚本首行 `VARS`）：A `place_directive={} route_directive={} pblock={none}`；B `pblock={pblock}`（`SLICE_X40Y20:SLICE_X66Y52`）；C `place_directive={Explore} … pblock={none}`。A/B/C 的脚本差由 `build/evidence/r113_roll_scripts_diff.txt` **逐行列出**（单变量性不靠嘴说；⚠ 这份 diff 在 roll2 之后重新生成过一次，引用要看它自己的生成时间） |
| 结论：**采用（带两刀，代价与不兑现一起登记）** | 三滚的读法（`build/evidence/r113_roll_abc_verdict.txt`）：**A 逐位复现正式构建 ⇒ 确定解**（族 slack 0.445、`p_eof_reg` 仍在 `SLICE_X57Y34`、整片 `rows_hit` 仍在 `X28~X31`、WHS 0.050、端点 51135）；**C ⇒ 换实现策略这一档拿不到任何东西**（与 A 一格不差，负结果，不进首页成绩）；**B ⇒ 那块 Pblock 的表达式不成立** —— REFUSE：`Place 30-439` 说进位链半内半外，落点地板实测 `PB_CONTAIN total=1716 inside=1461`。采纳取舍（#255 原文）：① 目标 (b) 的修复在刀 A，今天能交付 ② 0.445 ns 仍是 **MET、失败端点 0**，且 r109 采纳时是 0.605（同一量级）③ 退刀 B 要再付一整轮（≈2.5 h）去换回**另一条路**的旧数，那既不是"同一条锥变好"也不是新增功能。**代价登记**：刀 B 记为"**同族抓手成立、设计余量未抬**"（`build/evidence/r112_verdict.txt` 第 2 条 vs 第 1 条） |
| 归属这一笔：一条我自己写错的判断，就地更正 | #253 我原本写"这一族 RTL 一个字节没动（`git show --stat 6730dd9` 只含 `icmp_tx.v` 与 `key_debounce.v`），所以『>1.174 → 0.445』这段位移**全部来自布局/布线**，既不归功刀 A 也不归罪刀 B"。⇒ **#254 的第 2 条把它更正了**：控制组 A **逐位复现**了 0.445 ⇒ 它**不是骰子**，而是"这两刀改了网表 → 放置确定地变 → 这条邻居路径的布线跟着变长"的**确定性间接代价**。**"既不归罪"这半句是错的**，已在原条目里就地改并写明"这句的后半已被 #254 更正"。规矩 35 仍然成立：不许把它读成"同一条锥变慢了" |
| 两条静默事故（当场复原并留凭据） | ① 用编辑工具**追加**时锚行选长、替换文本选短 ⇒ 删掉了 #254 第 3① 条的开头一句，复原后按行号可验、`doc_enc_check` 386 个文件全干净 ② 在**双引号**的 printf 参数里写了反引号 ⇒ 被当成命令替换执行（`place_design: command not found`），那行说明里的命令名被吞 |
| 证据路径 | `report/log/issues.md` #250/#251/#252/#253/#254/#255 与 #250 续（OOC 净资源账 `build/evidence/r112_ooc_*.txt`）；`build/r112_gates.txt`、`build/r112_verdict.sh`、`build/evidence/r112_verdict.txt`、`build/evidence/r112_util_attrib.txt`、`build/evidence/r112_synth_roster.txt`、`build/evidence/r112_before.txt`、`build/evidence/r112_after.txt`、`build/evidence/r113_roll_abc_verdict.txt`、`build/evidence/r113_roll_a_console.txt`、`build/evidence/r113_roll_scripts_diff.txt`、`build/evidence/r112_key_boot_before.txt`、`build/evidence/r112_tx_bytes_base.txt`、`build/evidence/r112_tx_bytes_cut.txt`、`build/evidence/r112_bit/`（采纳快照 13 份 + MANIFEST）；台账目录 `build/runs/r112/` |

# r113 —— 上电那一度的**真根因**：这一域根本没有复位（名册对上一轮逐位相同）

| 字段 | 内容 |
| --- | --- |
| 轮次 | r113（2026-10-03 12:0x 构建、14:3x 上板；正式件 md5 `b94f4da6cdff`） |
| 改动 | `src/rtl/util/key_debounce.v`：把上电语义**写进声明**（`key_stable`/`key_sync0`/`key_sync1`/`key_prev` = `1'b1`）。r112 那把武装门**没打中这个因**（下面读数栏） |
| 源码指纹 | `top=56c269602e18`、`rtl=42d47b9f771d`（`build/evidence/r113_precompile_fp.txt` 与 `build/r113_gates.txt` 第 35 行两处同值） |
| 各域 setup/hold 最差值与失败端点 | 与 r112 **逐位相同**：`clk_fpga_0 1.135 / 0.056`、`clkout0_1 4.467 / 0.059`、`eth_rxc 0.445 / 0.050`、`sys_clk 14.463 / 0.133`；失败 setup/hold **0 / 0**，总端点 51135。名册 **16 行 / 8 对全配、一字节都没动**（`build/evidence/r113_roster_diff.txt`） |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | LUT `14154`、FF `8188`、BRAM `95.5`、Dynamic `2.213 W` ⇒ **全部与 r112 逐字相同**：#256 的修复只改 FF 的 `INIT` 属性，不改网表结构（同一批 FDRE、同一些连接）。位流内容确实变了（`897fa9d93956 → b94f4da6cdff`）⇒ 按 T2，这不是"收益"，是**代价为零**的证据 |
| 告警条数按类 | `report_methodology` 逐类仍是 446 那七项（原件 `build/evidence/r113_methodology_baseline.rpt`）；综合告警 21 类未增加（`build/evidence/r113_synth_roster.txt`）。**一条红留在本轮自己身上**：`D6_fanout_inventory` 判红 —— `report_design_analysis -fanout -limit 12 -interval 4` 什么都没写出来 ⇒ `FANOUT_ROWS=0` ⇒ 差分判红。这正是计数地板该抓的形状（**空产物不许伪装成"这一版没有高扇出"**）；探针已改成最素的调用并把 `FANOUT_ERR` 与报告头念出来。**这条在重问之前保持红，不许为了绿而豁免** |
| 判 5 项 | ① 网表实测量（不是推测）：`build/tcl/probe_ff_init.tcl` 在综合后 + 布线后各一遍（每遍 `COMPARED=96`）⇒ `u_pl/u_k1/key_stable_reg`、`key_sync0_reg`、`key_sync1_reg` 全是 **FDRE、INIT=1'b0**，而 RTL 想要 **1（松着）**；根因是 `src/rtl/top/system_top.v:250` 给 `u_pl` 的 `sys_rst_n` **恒接 `1'b1`** ⇒ `key_debounce.v` 里 `if (!rst_n) key_stable <= 1'b1;` 是**死支**，综合把复位连同那个"1"一起吃掉了 ② 三腿对照（一次性拷贝树）：r110 无武装门 ⇒ `inc=1/angle=1` 红；**r112 有武装门 ⇒ 同样 `inc=1/angle=1` ⇒ 武装门没打中这个因**；fix（声明带初值）⇒ `inc=0/angle=0` 绿 ③ 硬件凭据那一问不是"台架认不认"而是"**带着 `rst_n=1'b1` 再综合，那个 1 还进不进位流**"：`build/tcl/probe_init_tied_rst.tcl` 量到 **FDRE INIT=1'b1 ×4、`RESULT probe_init_tied PASS`**（另一遍 OOC 自由输入口径量到 FDPE INIT=1'b1 —— 两遍都对，但**只有带常量复位那遍**才算板上条件） ④ 物理侧三滚（A/B/C，见 r112） ⑤ 板侧三步 JTAG + `board_verify` |
| 对照方式 | 检查点复算（三滚 + `probe_ff_init.tcl` 打在综合后/布线后网表上）+ 副本预验证（一次性拷贝树三腿 `build/evidence/pu113/`）+ 全流构建（采用笔） |
| 结论：**采用** | 理由：本轮的收益**不在时序上，而在上电语义上**；"名册八对逐位相同"是这条改动的**时序中性证明**（物理理由：只改 FF 的 INIT 属性 + 这台工具的放置/布线确定，r112 的 roll A 已实证）。⚠ **口径升级要写清**：#247/#249 与 `report/known_issues.md` 第 20 条里"机理已证、**成因未定**"改成"成因已定位（这一域无复位 ⇒ FF 上电值 ≠ 代码想要的复位值），修复已入库，板上复验待 r113 采纳 + E6 眼睛判"。武装门（#247）留着不撤——它挡的是另一类（配置时真按住键），但**不许再把它写成那一度的解药** |
| 顺带立案的同类风险（清成两棵） | `sys_rst_n` 恒 1 意味着**整个 sys_clk 域**里所有 `if (!rst_n)` 都是死支 ⇒ 全局扫了一把并按顶层分树（`build/evidence/r113_dead_reset_scan.txt`，尺子 `build/scan_dead_reset_init.py` 自对照四条；网表侧另有一把 `build/check_powup_init.sh` 五条判据 + 五条对照，拿 r112 的**真**探针文本喂进去判红）。#257 把这条"待查"闭成两棵树 |
| 一处"其他地方"第一次被点名（r114 的活） | #259/#262：I/O 约束欠账第一次被点名（屏 TMDS、LED、MDIO 对外**没有任何时序声明**），且 `dc_fifo` 两级格雷码指针的捕获寄存器**没打 `ASYNC_REG`**（TIMING-9/10 那两条终于有了名字，尺子 `build/scan_async_reg_coverage.py`） |
| 证据路径 | `report/log/issues.md` #256/#257/#258/#259/#260/#261/#262；`build/r113_gates.txt`、`build/evidence/r113_ff_init.txt`、`build/evidence/r113_init_tied_rst.txt`、`build/evidence/r113_powup_verdict.txt`、`build/evidence/pu113/`、`build/evidence/r113_dead_reset_scan.txt`、`build/evidence/r113_async_reg_scan.txt`、`build/evidence/r113_roster_diff.txt`、`build/evidence/r113_before_roster.txt`、`build/evidence/r113_after_roster.txt`、`build/evidence/r113_after_roster_rf.txt`、`build/evidence/r113_methodology_baseline.rpt`、`build/evidence/r113_synth_roster.txt`、`build/evidence/r113_flash_console.txt`、`build/evidence/r113_temp_lines.txt`、`build/evidence/r113_serial_raw.txt`、`build/r113_powup_rejudge.txt`；台账目录 `build/runs/r113/` |

# r114 —— `ASYNC_REG` 上了网表：WNS 0.445→0.739 **不记在本刀名下**（最差换了族）

| 字段 | 内容 |
| --- | --- |
| 轮次 | r114（2026-10-03 19:0x 构建、21:31 三步链上板；正式件 md5 `7142a1fbf082`） |
| 改动 | 进构建两刀：① `src/rtl/eth/dc_fifo.v`：四颗格雷码指针寄存器打 `(* ASYNC_REG = "TRUE" *)`（#262）② `src/rtl/eth/snap_cross.v`：`hb_gone` **声明初值**（#257 尾）。不进构建的四刀（都量过否掉）：RGMII 真实输入窗三份 XDC、四条 `set_max_delay -datapath_only`、复制驱动、Pblock |
| 源码指纹 | `top=56c269602e18`、`rtl=3969247aaf7f`（`build/evidence/r114_bit/tb_v98_report.txt` 头部 provenance、`report/timing/baseline_index.md` 第 10 行、`build/r114_gates.txt` 三处同值） |
| 各域 setup/hold 最差值与失败端点 | `eth_rxc` **0.739 / 0.052**；`clk_fpga_0` **1.850 / 0.053**；`clkout0_1` **3.630 / 0.059**；`sys_clk` **14.876 / 0.222**。失败 setup/hold **0 / 0**，总端点 51135。**最差那一族换了**：从 r113 的 `rows_hit` 一族换成 `u_icmp_tx` 校验和锥 `ip_head_reg[4][16] → check_buffer_reg[19]`（11 级、6×CARRY4、route 58.447 %）—— ⇒ **这一轮的 0.445→0.739 是"换族"，T2 明令不记收益**（本台账点名的那条例外实例就是这一行） |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | LUT `14154`（26.61 %）、FF `8188`（7.70 %）、BRAM `95.5`（68.21 %）、DSP `19` —— **与 r113 逐字相同** ⇒ 属性与初值这两刀没改网表数量（`build/evidence/r114_synth_roster.txt` 的资源行）。⇒ 首页/metrics.csv 的资源行**不需要改口**，要改的只有 WNS/WHS/位流身份/结温 |
| 告警条数按类 | 综合告警名册与 r113 做集合差分 ⇒ **差分是空**（21 类，一类都没多，含 `8-7137` 仍是 19 条）；`report_methodology` 逐类仍 446/七项。**但有一条判据被数据判错了（#290）**：我预先登记的"TIMING-10 会随 `ASYNC_REG` 落地而减少"**没动**（仍 = 1）⇒ 剩下的那一处**没有被识别**，格雷码链不是它。教训写死：**属性有没有落地不能拿 methodology 的计数当凭据**（它数的是"检查项"，不是"我的属性"）；durable 的尺子是 `report_cdc -details` 点名到具体那对触发器（⚠ 仓库里 9 月那份 `build/cdc_details.rpt` 是**过期件，不许引用**）。网表侧凭据（真尺子）：`marked_true` **0 → 56 颗**（`build/evidence/r114_async_reg_post.txt` vs `r114_async_netlist_pre_console.txt`） |
| 判 6 项（名册差分 D1..D6，16 对） | A = `build/evidence/r113_after_roster_rf.txt`（同一把探针 + 同一份扇出名册）、B = `build/evidence/r114_after_roster_rf.txt` ⇒ `D1_no_new_violation new=0 GREEN / D2_pairs_compared pairs=16 GREEN / D3_margin_cost big_loss=0 GREEN / D4_hold_covered hold_pairs=8 GREEN / D5_no_empty_readings empty_in_B=0 GREEN / D6_fanout_inventory fanout_rows=20 GREEN`（件 `build/evidence/r114_roster_diff.txt`）。**代价必须同笔念**：变差的两格 `clkout0_1/setup 4.467→3.630 ns`（相对余量 22.34 %→18.15 %，掉 **18.8 %**，在预登记的 25 % 门槛以内）与 `clk_fpga_0/hold 0.056→0.053`（−5.4 %）；变好的四格 `eth_rxc/setup 0.445→0.739`、`clk_fpga_0/setup 1.135→1.850`、`sys_clk/hold 0.133→0.222`、`sys_clk/setup 14.463→14.876`。**`clkout0_1` 那 18.8 % 的下降要留在采纳句里念出来，不许只写"六条全绿"** |
| 对照方式 | **检查点复算**为主：RGMII 窗绑到**同一份 `system_top_opt.dcp`** 重跑 place+route（`build/evidence/r114_io_roll_console5.txt`）；复制驱动两滚同一份 DCP（`build/evidence/r114_mf/verdict.txt`）；变体 A 只声明上升沿再一次滚（`build/evidence/r114_io_varianta_console2.txt`）；扫档四档 0/13/26/31 各一滚；**全流构建**只在采用那一笔跑。快车道两滚各 6–8 分钟 vs 正式构建 60 min + 台架 70–128 min ⇒ **这类"物理杠杆值不值"的问题以后一律先在快车道量** |
| 结论：**采用（收益记给"结构账变干净"，不记给 slack）** | 理由：`ASYNC_REG` 上了网表（0→56 颗）、综合告警一类没多、资源逐字中性、名册 16 对六条全绿、门禁 24 项 23 绿/1 红两跑逐字节一致、板级 `board_verify --geom --battery` **PASS（判红步骤 0）**、 geom 10/0、105 条命令全过、`[TEMP]` 四方对账自洽。**并公开一处我自己写错的判断**：我在 §十二 里写过"这两刀预期**时序中性**"——**这句是错的**：`ASYNC_REG` 不只是文档属性，它是**放置指令**（要求同步链放进同一 SLICE），所以全局放置被挪动、slack 一定跟着变；**中性的是资源与告警类别，不是 slack** |
| 本轮量到底并判负的四刀（全部有件，都进 `build/runs/decisions.md`） | ① **RGMII 真实到达窗**（`src/constraints/r114_io_async.xdc`，四条 `set_input_delay ±0.500`）：绑上同一份 DCP 重跑 ⇒ 终态 **WNS 0.437 / WHS −2.885 / THS −14.344**，5 个失败端点全在 `u_iddr_rx_ctl/D` ⇒ 收口现在就是红的，**差异被"缺约束"藏住了**（#275）。变体 A（只声明上升沿）读数**逐位相同** ⇒ 沿的条数**不是**原因（#278）；变体 B（PHY 内部延迟模型）0/8/13 档 WHS −2.522/−2.018/−1.703 ⇒ 数据路径延迟这条路**关不住 hold**，缺的 0.5 ns 只在时钟路上（#282）。#285 把病因指到**捕获钟的网络延迟 DCD 5.008 ns**（`Clock Path Skew` 行），不是 PHY 延迟、不是 IDELAY 档位 ② **`set_max_delay -datapath_only` 四条跨域界**：`report_exceptions` 表体 A 滚 13 行 / B 滚 13 行，`-datapath_only` 这个词在两份表里出现 **0 次** ⇒ 叠在 `set_clock_groups -asynchronous` 上**不落表**，四条界一条都没生效（#276）；正解是口径决策（要么把那一对从 group 排除里拿出来、要么承认这四条路不做 STA），**会动 WNS 的算法范围 ⇒ 必须单独一轮带尺子做，不许顺手做掉，也不许写成"已补上界"** ③ **复制驱动 `phys_opt_design -force_replication_on_nets`**：`MF-SUMMARY mech=2/2 gain=0.456 cost_red=1 lut_delta=31 verdict=DECLINE` —— 机制动了（`REPLICA_CELLS` A=0→B=296；`u_pl/u_clk/u_mmcm_0` 扇出降 58）、目标族 0.445→**0.901**（+0.456 ns）、LUT 14154→14185（+31），但名册差分 **D3 big_loss=1**（`eth_rxc/hold 0.050→0.035`，相对余量 −29.0 %）⇒ **DECLINE**。**判负依据不是"WNS 没动"（那是 T2 禁的口径），是名册差分看见的代价**：在一个"约束还没建全、余量读数已经不可信"的域上再削掉 29 % 相对余量，等于把 r62/#57 那次"WHS 在 ±1 ps 上掷硬币"重新请回来 ④ **Pblock**：r112 roll B 已否（`Place 30-439` 进位链半内半外）；更早一次 r89 的 Pblock 也量过并否（在 `build/runs/decisions.md` 的"更早的否决"一节） |
| 为让它绿我修的两把自己尺子（射程账） | #291/#293：拿两把**不同生成器**的名册相减 ⇒ `D3 big_loss=8` 与 `D6 fanout_rows=0` 都是**假代价**（MISSING 与"掉过 25 %"共用一个计数器；四路多余钟 × setup/hold = 8）。那份产物**没删**，改名留在盘上当反例：`build/evidence/r114_roster_diff_shape_mismatch_do_not_read_as_verdict.txt`。修法：相减之前先验形状（`slack`/`margin_pct` 必须是纯数、两侧时钟名单必须完全一致），任一不成立就 `ROSTERDIFF-SHAPE … result=REFUSE`（**REFUSE 不是裁决**）；`--self` 实测 8/8 |
| 一条探针侧的自伤（值得当反面教材） | #295/#277：我想做"同一条不确定度带给到四个时钟"的全局体检，`probe rc=4` —— 三条实测：`set_clock_uncertainty` **不返回对象列表**（命令成功、返回空 ⇒ 守卫把正当体检判成"没有变量"）、时钟对象**根本没有不确定度属性**（`*UNCERT*` 匹配为空）、更早还把自己烧在三滚上的时间**误诊过一次**（真因是 Tcl 里模式串以 `-` 开头必须写 `--` 终止选项解析，不是"CJK 注释被吞"）。⇒ **删 CJK 注释这件事最后没被证明有害也没被证明必要，我不把它写成根因，只写成"我改过、且不是根因"** |
| 证据路径 | `report/log/issues.md` #287–#295（判负四刀与差分两把尺子）；`build/r114_gates.txt`、`build/evidence/r114_after.txt`、`build/evidence/r114_before.txt`、`build/evidence/r114_after_roster.txt`、`build/evidence/r114_after_roster_rf.txt`、`build/evidence/r114_roster_diff.txt`、`build/evidence/r114_io_roll_console5.txt`、`build/evidence/r114_io_varianta_console2.txt`、`build/evidence/r114_mf/verdict.txt`、`build/evidence/r114_sweepb_console.txt`、`build/evidence/r114_async_reg_post.txt`、`build/evidence/r114_async_netlist_pre_console.txt`、`build/evidence/r114_synth_roster.txt`、`build/evidence/r114_uncertainty_shape_console.txt`、`build/evidence/r114_bit/`（采纳快照 13 份 + MANIFEST）、`report/timing/baseline_index.md`、`report/timing/debt_ledger.md`、`report/timing/roster_baseline.tsv`；台账目录 `build/runs/r114/` |

# r115 —— 什么都不采纳的一轮：名册尺子、噪声底、三把候选刀全部量到底

| 字段 | 内容 |
| --- | --- |
| 轮次 | r115（2026-10-03 22:0x → 10-04 00:30；**无正式构建、无刷板**，板上仍是 r114 `7142a1fbf082`） |
| 改动 | **主树 `src/rtl` 一字未动**。新增的都是**候选件与尺子**：① `src/constraints/r115_io_window_candidate.xdc`（新窗数 min 1.000 / max 2.600，取自 PHY 手册 Table 60 的正确两行）② `report/timing/roster_baseline.tsv`（B2/B3 名册，md5 `039c16e373e562016b2edbea02925efc`）③ 尺子 `build/r115_roster_build.py`、`build/r115_round_roster.py`、`build/tcl/r115_baseline_probe.tcl`、`build/r115_fanout_ab.sh`、`build/r115_uncertainty_hold.tcl` 等。④ 一份候选 XDC `src/constraints/r114_io_variantb_phy_delay.xdc` 在上一夜就落盘了（r114 轮），本轮只是量完 |
| 源码指纹 | `top=56c269602e18`、`rtl=3969247aaf7f`（`report/timing/baseline_index.md` 第 10 行；与 r114 同一枚 ⇒ 本轮无源改动） |
| 各域 setup/hold 最差值与失败端点 | **基线侧**（`build/evidence/r115_base/`，22:20–22:22 只读打开 r114 的已布线 DCP）：`clk_fpga_0 1.850/0.053`、`clkout0_1 3.630/0.059`、`eth_rxc 0.739/0.052`、`sys_clk 14.876/0.222`，失败 0/0、`unconstrained_endpoints=0`、`io_unconstrained_ports=11`。三把刀的读数见下面"判 N 项"栏 |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | 基线侧 `Slice LUTs 14154 / Slice Registers 8188 / Block RAM Tile 95.5`；C1 复制滚的代价：FF `8188 → 8463`（**+275**）、LUT `9969 → 10004`（**+35**，这是 LUT-as-Logic 口径，不是 Slice LUTs 口径 —— 两把尺子的量纲，不并入上一句）；C3 副本树：`MMCME2_ADV 2/4 → 3/4`、LUT +5、FF 不变 |
| 告警条数按类 | `Checks found: 446` 七项闭合（`build/evidence/r115_base/methodology.txt` 的 SUMMARY 行；⚠ 只从 SUMMARY 表取数，整份文件 `grep -o` 会把每类多算一次）。TIMING-18 的 7 条 = 那 11 个端口的**另一种量纲**（checks/pins，不是端口数）⇒ **两个数永不相减**。本轮新增一类要注意：C3 那一滚里 `TIMING-15 Large hold violation` 出现过 5 条（只测不采纳） |
| 判 7 项 | ① **B4 噪声底 = 0.000 ns**（`mode=none` 连滚两遍，头条四个数逐位相等且**最差路径身份也相等**）⇒ 之后任何"收益"必须严格大于 0 才许叫收益 ② **B2/B3 名册冻结**：判定器的对照端是 `report/timing/roster_baseline.tsv`，**不是"我记得基线是多少"**，也不许把"当前值"换成刚生成的集合 ③ **C1 复制驱动判负**：`REPLICA_CELLS` A=0→B=**310**（机制真的动了），32 次比较里 **4 格红**（`eth_rxc` setup 0.092375→0.083125、`eth_rxc` hold 0.006500→0.004250、`sys_clk` setup 0.743800→0.738600、`clk_fpga_0` hold 0.005300→0.004200）；同时它确实抬高了 `clk_fpga_0` setup（0.185→0.1959）与 `clkout0_1` setup（0.1815→0.195）⇒ **"结论不是『复制没用』，而是『在 `eth_rxc` 没有可信 hold 余量之前，复制的代价由它付』"** ⇒ 顺序换成 C3 在前 ④ **C2 不确定度只测不采纳**：BEFORE 只有 `eth_rxc value=0.800`，其余三域 `value=NA`（报告有、路径有、就是没有那一行 ⇒ 这三个域从来没带过那条带子）；统一加严 AFTER ⇒ 设计级 **WHS −0.747 ns、THS 失败端点 25742**，且 `−0.747 = 0.053 − 0.800` 与 `clk_fpga_0` 现行报的 0.053 逐位对上 ⇒ **不是新出现的物理问题，是同一批路径换了尺子之后的读数**（#265 那条"四域 WHS 不可比"第一次被量出来） ⑤ **C3 MMCM 负相移判负**：终态 `WNS 0.954 / WHS −2.126 / THS −10.552 / 5 个 hold 失败端点`（r114 同窗是 0.437/−2.885/−14.344/5）⇒ **只买到 +0.759 ns，窗没关住** ⑥ **C3 顺手抓到一件会静默削弱约束的事**：那条读数里 `Clock Uncertainty: 0.166 ns` **没有 UU 项了** —— `set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]` 不再覆盖这个域（终点已经是派生钟 `mmcm_clk0`）⇒ 那 +0.759 里约 **0.67 ns 是"约束作用范围被削弱"换来的，不是物理改善**；我**没有写任何放松约束的命令，它自己发生了** ⇒ 新规矩：**只要新建/改名一只钟，所有点名旧钟的约束都要重查覆盖面**（`set_clock_uncertainty`、`set_clock_groups`、`set_input_delay -clock`、IDELAY/参考钟关系） ⑦ **#306 用算术把"再挪一点相"这条路关死**：真窗下主树实测 `hold −1.385 / setup −0.186`，**报告自己的 Clock Path Skew 才是事实：主树 5.008 vs 副本树 5.919** ⇒ MMCM 那一刀把捕获沿**推迟了 0.911 ns**，`−225°` 的相位提前被 MMCM+BUFG 自己的网络延迟吃掉还有余 |
| 对照方式 | **检查点复算**（全部候选都打在 `system_top_opt.dcp` `4c895816c4f2` 或 `system_top_routed.dcp` 上，6–8 分钟一滚）+ **副本预验证**（C2/C3 走一次性拷贝树 `c2_scratch_1003`，19 分钟一滚）+ **只读探针**（基线 23 份件）。**本轮一次全流构建都没花** |
| 结论：**全部不采纳（本轮没有任何东西进构建）** | 三条并列的理由：① 三把候选刀**全部判负**（C1 名册四格红、C2 只是换尺子不是修设计、C3 窗没关住且会静默削弱约束）② **松动台账本轮 0 条**，而且写明"本轮无人可批：用户已睡，H1/G3 要求经用户明确批准 ⇒ 一切候选只做**测量**，不做采纳；**一张空表比一张"我替用户批了"的表诚实**" ③ 两处"看起来该放松但没放松"记在台账里以免被当成漏记：`eth_rxc` 的 hold 不确定度 0.800 本轮没调小没删；RGMII ±0.500 ns 输入窗没被绑进工程（因为加上它 hold 会红 −2.885/−14.344）—— **"先去掉约束再修"不是修，方向是反的：先修捕获钟，再绑约束** |
| 一处窗数来源的更正（A1 第一次取数就推翻我自己） | `±0.500` 是 RTL8211F Table 60 里 **`TskewT`** 那一行（发射端**没有**内部延迟时的输出偏差），**不是收口该用的窗**；新候选件改取 `TsetupR/TholdR` min 1.0 / `TskewR` 1.0–1.8–2.6 的并集 ⇒ min 1.000 / max 2.600（`report/timing/rgmii_window_model.md` §6）。分量算法自校验：同一套分量拿 ±0.5 那档回去算得 −2.884，与 r114 实测 −2.885 **逐位对上** ⇒ 这套算法可信。**残余风险要写明**：`TskewR` 那行讲的是 PCB **时钟走线**（要多走 1.5–2.0 ns），我却当数据散布用了，**可能是第二次混行** ⇒ −1.385/−0.186 只代表"该窗模型下的读数"，不代表板上真实差额；定模型要有人读那两行与 strap/寄存器现值（本机读不到，#131/#170） |
| 三把尺子当场被证不成立并修好（都是我的账，不是设计的账） | ① `grep -ac ROLLDONE` 数到 2：批处理模式会**回显脚本自身**那一行 ⇒ 必须锚 `^ROLLDONE` ② `report_route_status` 的**文件里没有 "successful" 这个词**（它是净计数表）⇒ 判据改成"routing errors = 0 且 全布 == 可布 且 > 0" ③ `report_utilization` 里**没有 `^ *CLB Logic Cells` 这一行**（今天第三次犯"按记忆的形状 grep"）⇒ 改用 `Register as Flip Flop` / `LUT as Logic` 两行。同族教训：**形状要量不许猜** |
| 证据路径 | `report/log/issues.md` #296–#306；`build/evidence/r115_base/`（23 份原件 + `report/timing/baseline_index.md` 的逐份 md5 表）、`build/evidence/r115_noise_cal_console.txt`、`build/evidence/r115_noise_verdict.txt`、`build/evidence/r115_fanout_ab/verdict_header.txt`、`build/evidence/r115_fanout_ab/roster_diff.txt`、`build/evidence/r115_uncertainty_hold_console.txt`、`build/evidence/r115_c2_scratch/option_a_main_console.txt`、`build/evidence/r115_c2_scratch/option_a_console.txt`、`build/evidence/r115_board_manual_ethernet_excerpt.txt`、`build/evidence/r115_rtl8211f_delay_source.txt`、`build/evidence/r115_sch_p8/`、`report/timing/rgmii_window_model.md`、`report/timing/uncertainty_hold_ab.md`、`report/timing/roster_round115.tsv`、`report/timing/loosen_ledger.tsv`、`report/timing/cut_ledger.tsv`（C1/C2/C3 三行状态）、`build/r115_capture_clock_plan.md`；台账目录 `build/runs/r115/` |

# r116 —— 两刀进构建：RGMII 输入窗第一次被检查 + IDELAY 挪到实测眼心（按字面判定是红的）

| 字段 | 内容 |
| --- | --- |
| 轮次 | r116（2026-10-04 01:13 构建起飞、01:34 出位流 `bb2fb707aebc`、01:37 三步链刷板；正式件 md5 `bb2fb707aebc`） |
| 改动 | ① `src/constraints/r116_rgmii_input_window.xdc`：5 个 RGMII 输入**第一次**被时序检查（`set_input_delay -clock eth_rxc -min 1.200 / -max 2.800` + `-clock_fall -add_delay` 那一对），`used_in_synthesis false` ⇒ **综合网表逐字节不变**，任何差异都只可能来自实现阶段。② `src/rtl/top/system_top.v`：`IDELAY_VALUE` **26 → 31**（0…31 全档扫出来的实测眼心）。**没有放宽任何东西**：`report/timing/loosen_ledger.tsv` 本轮 0 条，`rk_zynq7020.xdc` / `clock_groups_impl.xdc` 一个字没改 |
| 源码指纹 | `top=56c269602e18`、`rtl=07570b1ac1b4`（`build/evidence/r116_tree_fp.txt` 四行原文） |
| 各域 setup/hold 最差值与失败端点 | `eth_rxc` **−0.846 / −0.870**，失败 setup **5** / 失败 hold **5**（TNS −4.135 / −4.270）；`clk_fpga_0` **1.976 / 0.053**；`clkout0_1` **3.698 / 0.059**；`sys_clk` **14.876 / 0.222**。总端点 51140。⚠ 念法：`eth_rxc` 那两格变差**不是被搬走的负裕量，是第一次被检查的那 5 个 I/O 端点**（绑窗前它们是 `Slack: inf / Path Group: (none)` = **没检查**，而"没检查"不等于"满足"） |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | LUT `14154`（26.61 %）、FF `8188`（7.70 %）、BRAM `95.5`（68.21 %）、DSP `19`、Dynamic `2.213 W` —— **与 r114（HEAD）那份一格不差**（`build/utilization.rpt` 盘上 vs `git show HEAD:build/utilization.rpt`；综合网表本来就该逐字节不变，因为新 XDC 是 `used_in_synthesis false`）⇒ **增量 0，且这不是"没做"而是"证明了不该变"** |
| 告警条数按类 | `report_methodology`：类仍 **3 类**（TIMING-9/10/18），实例 `Checks found: 446 → **441**`，其中 `TIMING-18` **7 → 2**（少掉的 5 条正是这轮第一次被检查的 5 个 RGMII 输入）。⚠ **量纲红线**：`check_timing` 那侧的"未约束端口"是 11 → 6，methodology 这侧的 checks 是 7 → 2 —— **这是两把尺子的两种量纲，两个数永不相减**。门禁 `methodology CRIT 0`、`端口宽度警告 8-689 0` |
| 判 6 项（V1..V6，全过） | ① V1 机制：`r116_io_hold.rpt` 第一格 `Slack (VIOLATED) −0.870 ns`、`Path Type: Hold (Min at Slow Process Corner)`、`Input Delay: 1.200 ns`；`r116_io_setup.rpt` 第一格 `−0.846 ns`、`Setup (Max at Fast Process Corner)`、`Input Delay: 2.800 ns` ⇒ **"有限 slack"是这条判据的全部内容** ② V2 债：`unconstrained_internal_endpoints = 0`、"没有任何 input delay 的端口"5 → **0**、"没有任何 output delay 的端口"**6**（`led[0..1]`、`tmds_clk_p`、`tmds_data_p[0..2]`）⇒ **H5 的另一半不为 0，本轮按字面判红** ③ V3 收益：**DCP 上扫出的曲线在真构建里对到小数第三位**（预测 hold −0.870、实测 −0.870；`HOLD(τ)=−2.822+0.0630τ`、`SETUP(τ)=+2.005−0.0920τ`）⇒ 本轮模型最大的可信度证据 ④ V4 名册：其它三域一格没掉，`eth_rxc` 两格 RED（`judged=6 pairs=8 result=RED`；同一份差分里 `D6_fanout_inventory` 也红，**那是尺子口径问题不是设计问题**） ⑤ V5 代价：资源逐字中性 + 告警按类不增（见上两栏） ⑥ V6 板侧：**第一次的 `drop_words=0` 是零样本通过（`eth_live=0`），不算数**；带流重测（512×300 RGB565 ≈ **147 Mbps**，50 s / 3001 帧 / 66.3 万包）`eth_live=1 owner_eth=1`、`drop_words=0`、`pkt_err=0`、`flags.drop_seen=0` 两次都一样；`frames_bad=1` 不增长 |
| 对照方式 | **检查点复算**（0…31 全档扫描靠 `set_property IDELAY_VALUE` 在**已布线 DCP** 上有效 ⇒ 整条 tap 扫描没花一次构建，#310）+ **全流构建**（采用笔）+ **板侧 A/B**（`frames_bad=1` 的归属用**回刷 r114 位流**对照：同一台板、同一个 app、同一份推流，先回刷 `build/evidence/r114_bit/system.bit`（md5 `7142a1fbf082`）再刷回 r116，各读两次 ⇒ 四个读数逐格相同） |
| 结论：**采用位流、约束退回候选件（两半要分开念）** | **本轮按字面判定是红的两条**：G1（`eth_rxc` 两格相对余量比基线小）与 H5（输出侧还有 6 个端口没被时序检查覆盖）。两条我都没用话盖过去：G1 的红**就是这 5 个端点第一次被检查**；H5 的红需要**外部资料或用户批准**才能关。采纳规则**写在起飞之前**（`build/r116_batch_plan.md`）：`bad=0 ⇒` 报告与真实采样点之间还有一层模型悲观；`bad>0 ⇒` 窗是对的、结构确实到极限 ⇒ 回退刀 2、刀 1 退回候选件。实跑 `bad=0` ⇒ 位流被刷上板并复验通过；**而 `frames_bad=1` 用回刷 r114 做 A/B 查清了归属：r114 上就有（链路建立期那一下的一次性计数），与本轮采样点无关 ⇒ r116 与已被证明能跑的 r114 在真实流量下不可区分**。后续：r116 的门禁把 4 条**发布硬门**判红 ⇒ 输入窗在 r117 那一轮**退回候选件**（见 r117 的改动栏与 `build/runs/decisions.md`） |
| 极限判据第一次真满足（#311） | `eth_rxc` 这一族**不是"还没找到点"，是"两个区间不相交"**：hold 要 τ ≥ 44.8、setup 要 τ ≤ 21.8、合法档只有 0…31 ⇒ 不相交；去掉与窗双重计的 0.800 hold 带也只是 44.8→32.1，**仍不相交**。根因定位到**钟网络的角间差**：hold 查慢角 DCD **5.008**、setup 查快角 DCD **1.597**，差 **3.411 ns**，而数据路径角间差只有 **0.467 ns**；同时满足要 `D_slow/D_fast ≥ 1.73`（带子保留）/ ≥ 1.45（去带），IDELAY 主导的路径实测只有 **1.15** |
| ⚠ "报告最好"不等于"硅片最好"（必须写在采纳理由里） | tap **31** 是被 0.800 hold 带推出来的**报告最优**（真实角覆盖反降到 67 %），角间鲁棒最优其实是 **21~26**（覆盖 70 %）；物理条件是 `|C − D| ≤ 1.2 ns`，而**这颗片的 C 没有测过**（件里只有两个角）⇒ 三条纪律：不许拿 −0.87 冒充眼心；板侧 `bad`/`drop_words` 是唯一裁判；想真量眼心要把 5 颗 `IDELAYE2` 从 `FIXED` 换成 `VAR_LOAD` + 1000M 实流量。⇒ **刀 2 一度被改为"待板侧裁决"**（`d28ebbf`），后来带流 A/B 判 `bad=0` 才落地 |
| 尺子先修，交付数字才改口（#321/#322） | 本轮第一次让首页 headline slack 变成负的（−0.846 / −0.870），而首页四个取数式全写成 `[0-9]+\.[0-9]+` ⇒ 负数读成 null、null 在这把尺里就是红 ⇒ **写对了也红、写错了也红 = 这一维没有射程**。补 `sgn()`（U+2212 折成 ASCII）+ 四个式子加符号位 + **六条合成对照**：`SELFSIGN-SUMMARY 判 6 条（负数可读=绿、负数写错=红），红 0`。改口之后 `metric_recheck` 从 **23 条红 → 红 0**（判 115 个数）。⚠ 两条我自己的坑：CSV 一行里写了 ASCII 逗号 ⇒ 字段数从 7 变 8、"凭据列"读成"一次构建"；交付文档**不许**引用 `docs/`（那是本地工作区，不随包）⇒ 首页三处 `docs/timing/…` 改指 `report/timing_global.md` 第 6/7 节 |
| 一条板侧操作账（自伤，但根因是机制） | #315：实验刷板把控制台弄哑了，**根因是"app 在跑的时候重刷 PL"**；恢复只用 JTAG `rst -system`，不用手。#316：`drop_words=0` 的零样本通过**不作数**（就是 V6 那一格） |
| 证据路径 | `report/log/issues.md` #307–#322；`build/r116_gates.txt`（判定 24 项）、`build/r116_verdict_console.txt`、`build/evidence/r116_after.txt`、`build/evidence/r116_after_roster.txt`、`build/evidence/r116_roster_diff.txt`、`build/evidence/r116_roster_e1.tsv`、`report/timing/roster_round116.tsv`、`build/evidence/r116/{r116_check_timing.txt,r116_io_hold.rpt,r116_io_setup.rpt,r116_timing_summary.txt}`、`build/evidence/r115_window/probe3_console.txt`（0…31 全档）、`build/evidence/r115_base/setup_nworst.txt`、`build/evidence/r116_board/`（含 `health_r114ctrl_{a,b}.json`、`health_r116again_{a,b}.json`、`sender_live4.log`）、`build/r116_ab_summary.mjs`、`build/evidence/r116_bit/`、`build/r116_batch_plan.md`；台账目录 `build/runs/r116/` |

# r117 —— C9 强制复制那根 239 引脚广播网：机制成立、名册判负 ⇒ 按 H7 回滚

| 字段 | 内容 |
| --- | --- |
| 轮次 | r117（2026-10-04 03:15 第一支链起飞、04:00:34 被自己的钩子记账 bug 打死、04:0x 重跑实现段、04:16 **判负并停链**；构建产物位流 `beda9298331d`，**未刷板**） |
| 改动（两样） | ① `IDELAY_VALUE = 31`（沿用 r116 的眼心）② **C9**：实现阶段 `place_design` 之后、`route_design` 之前多跑一次 `phys_opt_design -force_replication_on_nets {u_pl/u_row/hi_reg_0[0]}`，钩子 `build/tcl/r117_post_place_hook.tcl`，用环境变量 `IMPL_POST_PLACE_HOOK` 挂上（默认不设 = 不挂 ⇒ 不 r116 的复现路径不被改写）。**不改 RTL、不改任何约束、不松任何东西**（松动台账仍 0 条）。**RGMII 输入窗这一轮退回候选件**（`src/constraints/r116_rgmii_input_window.xdc` 原件留在仓里、构建默认不加载、`VP_R116_IO_WINDOW=1` 一条命令复现） |
| 源码指纹 | `top=56c269602e18`、`rtl=07570b1ac1b4`（`build/evidence/r117_tree_fp.txt` 与 `build/evidence/r117c_tree_fp.txt` 两枚，重跑实现段前后同值）；位流 `beda9298331d`（`build/evidence/r117_bit_md5.txt`） |
| 各域 setup/hold 最差值与失败端点（官方构建，对照 **r114**） | `clk_fpga_0` setup **1.850 → 2.104**（相对余量 18.50 % → 21.04 %，**赢**）；`clkout0_1` setup **3.630 → 3.353**（18.15 % → 16.77 %，**跌**）；`eth_rxc` setup **0.739 → 0.615**（9.24 % → 7.69 %，**跌 —— 全设计最紧那格**）；`eth_rxc` hold **0.052 → 0.044**（0.65 % → 0.55 %，**跌 —— 全设计最薄那格**）；`sys_clk` setup **14.876 → 14.815**（**跌**）；hold 其余三域 0.053/0.059/0.222 逐格不动。失败端点本轮**仍是 0**（两把尺子都没读到新违例） |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | 快车道滚 B 侧：`clk_fpga_0` 端点 `15,721 → 15,731`（**+10**）、Slice 寄存器 `8,188 → 8,198`（**+10**）、LUT/BRAM/DSP **不变**。**闭合等式**：新增端点 +10 == replica 10 颗 == 寄存器 +10（机制与代价互相对上，不然就是"看起来动了"）。官方构建的机制凭据两处独立出水口：`impl_1/runme.log` 原文 `R117HOOK byname=u_pl/u_row/hi_reg_0[0] … pins_before=239 … pins_after=1 replica_cells=10` 与 `build/r117_a1_read.sh`（**两处都读 + 自己算闭合等式**，因为钩子跑在 run 自己的进程里、`puts` 落在 `impl_1/runme.log` 而不是顶层控制台，只读顶层会把"机制动了"读成 `MECHANISM_INERT`） |
| 告警条数按类 | 判据 A4 要求"类计数不增"，本轮**未走到门禁**（04:16 停链）⇒ 逐类读数 `NOT_MEASURED`；已读的只有 `route_status` 与 `Place 30-439`（A 滚那份 `build/evidence/r117_fb_pblock/a/check_timing.rpt` 等在快车道件里） |
| 判 5 项（A1..A5，起飞前登记在 `build/r117b_chain.sh` 头部，不接受事后改口径） | **A1 机制** = GREEN（`pins_after=1 ≪ 239`、`replica_cells=10 ≥ 1`）⇒ **不是 `MECHANISM_INERT`，可以谈收益/代价**。**A2 收益 / A3 不加严不放宽** = **RED**（预登记的是严格口径"rel_margin 一格不许变小"，实测四格变小）。**A4 代价地板**（FF 增量 ≤ +15、LUT/BRAM/DSP 不许变、无 `Place 30-439`）在快车道是过的（+10 FF）。**A5 发布门**（24 项红数必须回到 1）未跑到 ⇒ `NOT_MEASURED`。⇒ 四条里两条 RED ⇒ **按 H7 回滚这一处切割**，并在 `report/timing/cut_ledger.tsv` 的 C9 行写下回滚原因与当初的预测收益，**件不删** |
| 对照方式 | **检查点复算**（快车道单变量两滚：A 滚逐格复现 r116 官方名册、B 滚加复制）+ **全流构建**（官方 r117）+ **基线换轨**（对照对象从 r116 换成 **r114 官方名册** `build/evidence/r114_after_roster_probefmt.txt`，理由见下面"口径"栏） |
| 结论：**回退（C9 判负，钩子不进默认构建）** | 三条并列：① **结论不是"这刀没生效"，而是"生效了，但代价落在最紧的两个域上"** —— 这正是 r115 那一夜 C1 复制刀被判负的**同一个形状**（#288/#301） ② **快车道那三格 setup 的赢（+0.033/+0.187/+0.298）不作采纳依据**：那一列是**带窗（r116 约束集）**那份 `opt.dcp` 上滚出来的**机制证明**，官方那一版没有输入窗、基线是 r114 ⇒ 快车道给方向、官方构建给数 ③ 撤窗的**代价要一起念**：`eth_rxc` 那 5 个 I/O 端点在 r117 里回到"没检查"状态（H5：没检查 ≠ 满足），所以判据 A3 明写 `no_input_delay` 会**回到 5**（撤窗的诚实读数，不藏） |
| 口径决策（03:52 改的，两条路我选了第二条） | r116 的门禁两跑回来是 **24 项 = 17 绿 / 7 红**（件 `build/r116_gates.txt`；ROUND_r117 那句"17 绿 / 6 红"与本台账逐行计数不一致，见第 4 节差异 D2），其中 4 条是**发布硬门**（WNS ≥ 0、失败 setup 端点 == 0、WHS ≥ 0、失败 hold 端点 == 0），红因正是本轮第一次被检查的那 5 个 RGMII 输入端点。两种写法：(a) 把发布门改成"允许设计性红" —— **不做**，那是给自己开门；(b) 约束留在仓里当**候选件**、全部证明与读数保留、构建默认**不加载**，`VP_R116_IO_WINDOW=1` 一条命令复现 —— **做了**，理由写在 `build/tcl/build_system_axigpio.tcl` 的约束加载处。**相对 r114 这**不是放宽**（r114 从来没有这条约束，`loosen_ledger.tsv` 仍 0 条），是"本轮新增的约束被自家发布门拒绝" ⇒ 按 H7 回滚这一处切割并把回滚原因留在原处 |
| 两把尺子给两个判语（#328，一条口径债） | `build/timing_roster_diff.sh` 的 D3 门槛是"掉 25 % 以上的域数" ⇒ 对同一份 r117 数据判 **GREEN**；而提示词 G1 与我预登记的 A2/A3 是"rel_margin 一格不许变小" ⇒ **RED**。**我没有去改宽任何一方**（25 % 门槛是别人在用的粗筛，改了就是把两轮的历史判语也改了），而是把严格判据落成**独立的、可指路的件**（`build/evidence/r118_strict_b1.txt` 那种形状），交付承诺按它判。补硬的规矩：**差分件念出来时必须同时念"比较了几对 / 其中几对在跌"，只念 `result=GREEN` 不算把差分念完** |
| 三条工具账（都是我的，不是设计的） | ① **#327**：钩子把 Tcl `catch` 的**返回码**当哨兵字符串用 ⇒ 一次**成功的** `phys_opt_design` 被判成失败 ⇒ `error` 把官方 impl run 打死（04:00:34）；重跑只重启实现段（`build/tcl/r117_resume_impl.tcl`，`system_top_opt.dcp` 是 03:58 那一份、综合网表没被碰过），**判据 A1..A5 一字未改** ② **#326**：起飞前我把 r117 名册的对照写成了**另一把生成器** —— 03:56 预跑抓出来，比读判读早 20 分钟 ③ **#325**：我把首页那句"门禁 N 项 X 绿 / Y 红"的形状改没了 ⇒ 门禁第 18 项的 D1c 层**空转**，靠它自己的射程地板才没混过去。另 #319/#320 两条：`get_nets -of <驱动引脚>` 与报告里的段名不是同一个对象 ⇒ 选错了复制目标；"记忆里应该支持的选项"当事实 ⇒ 两次 8 分钟空滚 |
| 一条被打死的 run 里已经拿到的一半证据 | 04:00:34 那次被打死**之前**，`impl_1/runme.log` 的两行原文已经把 A1 机制问回来了，而且是**官方构建自己的 opt.dcp** 上问的 ⇒ 机制与位流身份（`beda9298331d`）都留档；`report/timing/score.md` 那次重排名把 P1 的 pblock 靶子按 02:49 的 D0 读数**作废**（真靶子是 239 引脚广播网 FANOUT），**作废理由与件都留着不删** |
| 证据路径 | `report/log/issues.md` #319–#328；`build/r117_verdict_declined.txt`、`build/evidence/r117_after.txt`、`build/evidence/r117_after_roster_probefmt.txt`、`build/evidence/r117_after_roster.txt`、`build/evidence/r117_roster_diff.txt`、`build/evidence/r117_roster_diff_vs_r114.txt`、`build/evidence/r117_d0/`、`build/evidence/r117_d0_console.txt`、`build/evidence/r117_repl3/b_console.txt`、`build/evidence/r117_repl2/b/check_timing.rpt`、`build/evidence/r117_fb_pblock/a/roll_console.txt`、`build/evidence/r117_bit_md5.txt`、`build/r117_chain.sh`、`build/r117b_chain.sh`、`build/r117_a1_read.sh`、`build/tcl/r117_post_place_hook.tcl`、`build/tcl/r117_resume_impl.tcl`、`report/timing/cut_ledger.tsv`（C9 行 status=`declined(official r117: …)`）、`report/timing/round_r117.md`；台账目录 `build/runs/r117/`；**产物未固化**：`build/evidence/r117_bit/` 不存在（位流只在 `impl_1` 运行目录，见待办） |

# r118 —— 最后一轮上板：只带 τ=31，名册 8 对逐位复现 r114（**现行基线**）

| 字段 | 内容 |
| --- | --- |
| 轮次 | r118（2026-10-04 04:18:25 链起飞、04:36:56 出位流、04:45:26–04:47:07 刷板、04:49:50 `board_verify` 回来；正式件 md5 `cd04907e1369da35d21c4090d552f5ee`） |
| 改动 | **只带一刀**：`src/rtl/top/system_top.v` 的 `IDELAY_VALUE = 31`。**不带 C9 复制钩子**（`IMPL_POST_PLACE_HOOK` 不设）、**不带 RGMII 输入窗**（`VP_R116_IO_WINDOW` 不设）。两件"不带"都是**量过之后的决定**，不是"没做" |
| 源码指纹 | `top=56c269602e18`、`rtl=07570b1ac1b4`、`files=80`、`fpver=norm1`（`build/evidence/r118_tree_fp.txt` 四行原文；链脚本第 27 行先采指纹、第 30 行才起 Vivado，`build/r118_console.txt:1` 打印指纹比构建横幅早 2 秒 ⇒ 顺序证据在 `build/provenance.md` 第 39–41 行） |
| 各域 setup/hold 最差值与失败端点 | `clk_fpga_0` **1.850 / 0.053**、`clkout0_1` **3.630 / 0.059**、`eth_rxc` **0.739 / 0.052**、`sys_clk` **14.876 / 0.222**（`build/r118_gates.txt` 逐时钟段 + `build/roster/roster_r118.tsv`）；失败 setup/hold **0 / 0**，总端点 **51135**；WPWS 0.264 / 失败 0 / 12634。`NA` 四域：`clkfbout`、`clkfbout_1`、`clkout1_1`、`clkout2` |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | LUT `14154`（26.61 %）、FF `8188`（7.70 %）、BRAM `95.5`（68.21 %）、DSP `19`（8.64 %）、Dynamic `2.213 W` —— **与 r114 一格不差**；判据 B3 的地板按数念（Slice 寄存器与 r114 同值 8188、无 `Place 30-439`、`route_status` successful，件 `build/r118_verdict.txt:R118 B3_place30439=0`）⇒ **增量 0，且本轮本来就不该有增量**（τ 只动 I/O 单元抽头，不动片内任何一条锥） |
| 告警条数按类 | `report_methodology` 回到 **446 / 七项**（`build/methodology.rpt`：DPIR-1 2 + LUTAR-1 1 + SYNTH-5 336 + SYNTH-6 98 + TIMING-9 1 + TIMING-10 1 + **TIMING-18 7**）—— ⇒ 这是**撤窗的回弹读数**，不是新问题：那 5 个 RGMII 输入因为不再被检查，从 TIMING-18 的 2 条**回到 7 条**（r116 带窗时是 441 / TIMING-18 2）。`端口宽度警告 8-689 0`、`多驱动 net 0` |
| 判 4 项（B1..B4，04:18 起飞前登记在 `build/r118_chain.sh` 头部） | **B1 严格名册 = GREEN**：`build/evidence/r118_strict_b1.txt` 末行 `B1 pairs_compared=8 losses=0 verdict=GREEN`（八格逐格 `SAME`、`d=+0.000`）。**B2 机构中性 = GREEN**：构建日志里没有 `R117HOOK`、`unconstrained_internal_endpoints` 仍 0。**B3 资源中性 = GREEN**（见上栏）。**B4 发布门**：`build/r118_gates.txt` 与 `build/r118_gates_final.txt` 两跑**逐字节相同**，24 项 = **23 绿 / 1 红**，唯一红是声明过的 `C5c`（`FAIL C5c …` + `RESULT tb_v98_top_seam FAIL nfail=1`）。⚠ B1 用的是**严格那把**尺子，不是 `timing_roster_diff.sh` 的 D3（#328） |
| 对照方式 | **全流构建**（采用笔）+ 名册差分对 r114 官方名册（`build/evidence/r114_after_roster_probefmt.txt` → `build/evidence/r118_roster_diff_vs_r114.txt`，同生成器同约束集才是同一条尺子）+ **同树重滚可复现性**（B1 的"逐位相同"顺带给出这件副产品：放置与布线在这套工具上可复现，与 r110/r113 的空白滚、r115 的 `noise_ns=0.000` 同一条事实） |
| 结论：**采用（现行基线）** | 这一版的定位要说准：**它是一版"把收口到达窗推到实测眼心、且名册对 r114 逐格不劣化"的构建**；它的收益**不体现在片内 slack 上**（τ 只动 I/O 单元的抽头），所以判据是 **B1 不劣化 + B4 发布门 + 板级复验**，**不是"WNS 变好"** —— 把 τ=31 写成"WNS 收益"就是规矩 35 禁的那种读法。τ=31 的收益在**片外**：眼心余量 **+0.315 ns**（最差格 −1.185 → −0.870，同一把尺子同一只 DCP 实测，件 `build/evidence/r115_window/probe3_console.txt`）。板侧：`build/evidence/r118_board/board_now.txt`（04:49:50 刷入，`bit_cycle rc=0`、`board_verify --geom --battery --round=r118` **rc=0**） |
| 采纳后"到极限"这句话允许写到哪 | **允许**："四个域逐格要么为正、要么被证明了关不掉；非放宽的物理杠杆（策略扫描、同 DCP 重滚、Pblock、BRAM 换 setup、复制广播网 C9、灰码 `ASYNC_REG`、τ 扫档）已全部量过并给出赢或判负；唯一还能改变结论的是架构那一刀（IDDR 吃短捕获钟 + 一级同步 FIFO 再进 BUFG 流水线），门槛与代价面在 `report/timing_global.md` 第 7 节，动手前还欠一个 40 秒只读实测（BUFIO 快/慢角 DCD，#323）。" **仍不许写的三句**：① "板上真实 hold 差额就是 −0.870"（窗模型自身有 `TskewR` 混行的残余风险）② "换短钟也关不掉"（那个角间差没实测）③ **"收口 I/O 已通过时序检查"**（本版没有窗，那 5 个端点是**未检查**状态） |
| 两处身份债补账（#332/#333） | ① `git show HEAD:build/system.bit \| md5sum` 量到 HEAD 里那块**还是 r116 的 `bb2fb707aebc`** ⇒ r118 那两支提交只带了文档，bit / xsa / `build/*.rpt` / `build/report/` / `build/tb_v98_report.txt` 全悬在工作区。根因三条：路径清单写了不存在的 `report/acceptance.md` ⇒ `git add` 原子失败只暂存 4 条 ⇒ 打印子进程输出时又踩 cp936 解码崩溃。**新规矩：提交完必须读回 HEAD 验位流身份，不许只读工作区**（读回件 `build/evidence/r118_eyes/head_bit_md5.txt`；本台账写它时实测 `git show HEAD:build/system.bit \| md5sum` = `cd04907e1369da35d21c4090d552f5ee` = 工作区同一枚） ② 我为追加 #332 留的那份 `ISSUES_before332.md` 备份被 D5 当成交付文档扫并判红 ⇒ 纪律：**快照不要落成仓库里的 `.md`** |
| 一条自指死锁与它的正确修法（不改判据） | `doc_currency` 的 D1c 层拿"盘上最新的 `rNN_gates.txt`"当基准核对首页那句"门禁 24 项 23 绿 / 1 红"，而首页引用的那一份在这一刻还是**改口之前**的 21 绿 / 3 红（其中 2 条正是文档时效本身）⇒ **D1c 永远把自己判红**。修法："**先落一份能吻合的 `build/r118_gates.txt`、再要求首页与它吻合**"（顺序必须是这个），并只放行 D1c 的**计数不吻合**、不放行空转。之后 06:17 身份句去掉粗体 ⇒ D1b 抓到 2 句、D1c 抓到 2 句且与门禁件吻合 ⇒ `CURRENCY: 干净`、定版两跑 23 绿/1 红逐字节一致（#331） |
| 眼睛那一格 | **E6 在 r118 上由队员判过**：冷上电（≥ 10 s）+ 只跑三步链 + 全程不碰 KEY1/KEY2，屏第二行 `ROT:` 读 **0**（07:5x 原话「0度」）⇒ 把 r118 的"片内中性"从名册那一侧补到了板的一侧。**对照那一半（按住 KEY1 到链跑完应读 1）仍未做，登记为"未判"**，需要再断一次电 |
| 证据路径 | `report/log/issues.md` #324–#334；`build/r118_gates.txt`、`build/r118_gates_final.txt`、`build/r118_verdict.txt`、`build/r118_chain.sh`、`build/r118_console.txt`、`build/r118_build_console.txt`、`build/r118_docrotated.marker`、`build/evidence/r118_tree_fp.txt`、`build/evidence/r118_bit_md5.txt`、`build/evidence/r118_bit/`、`build/evidence/r118_strict_b1.txt`、`build/evidence/r118_roster_diff_vs_r114.txt`、`build/evidence/r118_after.txt`、`build/evidence/r118_after_roster_probefmt.txt`、`build/evidence/r118_serial_raw.txt`、`build/evidence/r118_board/`（`board_now.txt`、`bitcycle_console.txt`、`board_verify_console.txt`、`g2c.txt`、`g3c.txt`、`gatesc_summary.txt`）、`build/evidence/r118_eyes/`、`report/timing/round_r118.md`、`report/timing/handoff_r118.md`；台账目录 `build/runs/r118/` |

# r119 —— HDMI 源端 TP1 的窗：量到的是"量纲用错"，不是"设计不合格"（无构建）

| 字段 | 内容 |
| --- | --- |
| 轮次 | r119（2026-10-04 09:0x–09:5x；**没有正式构建、没有刷板**，板上与仓库位流仍是 r118 `cd04907e1369`） |
| 改动 | 只落**候选件与探针**，默认不进构建：① `src/constraints/r119_hdmi_source_window.xdc`（`set_output_delay -clock clkout1_1 -max 4.000 / -min -4.000` 打在 `tmds_data_p[*] tmds_data_n[*]`），挂载开关 `VP_R119_TMDS_WINDOW=1`（**默认关**）② `src/constraints/r119b_hdmi_tp1_pinclk.xdc`（参考钟打在 TMDS 钟脚上 `create_clock -name r119b_tmclk -period 20.000 [get_ports {tmds_clk_p}]`，只是探针输入）③ 尺子 `build/tcl/probe_tmds_pin_skew.tcl` + `build/r119_window_check.mjs` ④ 取证文档 `report/io/hdmi_cts_source_window.md` |
| 源码指纹 | `top=56c269602e18`、`rtl=07570b1ac1b4`（本轮**没动 `src/rtl`**，`bash build/rtl_fingerprint.sh` 当场跑过，与 r118 同一枚 ⇒ 位流身份不变） |
| 各域 setup/hold 最差值与失败端点 | 本轮**不采纳、不重建** ⇒ 逐域名册对 r118 未重跑 ⇒ `NOT_MEASURED`（`report/timing/debt_ledger.md` §2 追加之二明写"还欠一次构建量名册：四个域逐格对照 r118，别域不许变差"）。本轮量到的**不是各域 slack，是离散量**：`set_output_delay` 两版都真的挂上了（`Path Group` 从 `(none)` 变成有钟），但互对窗给出 `−3.482/−3.458/−3.474 ns`、打在钟脚上的 20 ns 参考钟给出 `−4.897/−4.873/−4.890 ns`；`tmds_clk_p` 在两种写法下都仍是 `Slack: inf / Path Group: (none)`（钟道自身不挂窗，符合设计） |
| 资源 LUT/FF/BRAM/DSP 与增量归属 | 无构建 ⇒ 增量 0；`unconstrained_internal_endpoints` 仍 0（本轮未重问） |
| 告警条数按类 | 本轮未重跑 `report_methodology` ⇒ `NOT_MEASURED`。⚠ 一条**必须先记的工具形状**：`.xdc` 里**不能写 Tcl 控制流** —— 第一版候选件里"读不到参考钟就 REFUSE"的守卫被 Vivado 逐行报 `[Designutils 20-1307] Command 'if' is not supported in the xdc constraint file.`（`if` 两行 + `puts` 一行，件 `build/evidence/r119_xdc_loads_probe2.txt` 第 42–56 行），**守卫被整块跳过而 `read_xdc` 仍然 rc=0** ⇒ 防呆变成"防呆失效且不报错"，比没有守卫更危险。守卫因此挪回 Tcl 脚本侧，`.xdc` 改回纯 SDC |
| 判 10 项（红 0） | `build/r119_window_check.txt` 判 10 项红 0：W1–W6（约束加载/形状类）+ **W7 互对离散 max 角** 最差 **0.065 ns**（上限 0.20 `Tcharacter` = **4.000 ns**，余量 61×）+ **W8 互对离散 min 角**（同一件事换角再判，成对）最差 **0.064 ns** + **W9 对内离散**（每对 P/N）四对最差 **0.001 ns**（上限 0.15 `Tbit` = **0.300 ns**）+ **W10 计数地板**（数据道 3/3、P/N 对 4/4、钟道两角齐，缺一条不许判通过）。尺子自证：`node build/r119_window_check.mjs --self` 造 10 条畸形输入 ⇒ **10 条各自动红**，另 2 条"缺输入"用例报 `NOT_MEASURED`（**不是通过**）。⚠ **一条连带红如实登记**：给 W7 造的畸形（把 `tmds_data_p[1]` 的 max 读数推到 6.300 ns）**同时染红了 W9** —— 根因是同一条读数既进互对差也进 P/N 对差，这不是判据串扰是数据共用一行，按规矩逐条列出而**不削弱反例** |
| 对照方式 | **检查点复算 / 只读探针**：`set_output_delay` 两次 load 打在实现检查点 `system_top_opt.dcp`（mtime 04:30）上，成品离散量打在**已布线** `system_top_routed.dcp`（mtime 04:36）上 ⇒ **没有把任何新约束带进构建、没有重建产物** |
| 结论：**待定（债没有销，且"窗数取到"不等于"已按 CTS 校验"）** | ① **为什么不是"设计不合格"**：规范那一行的原文是 `Inter-Pair Skew at Source Connector, max | 0.20 Tcharacter` —— 它约束的是**两个输出脚到达时刻之差的上限**（一条单边离散量），**不是**"数据必须在参考沿前后某窗口内保持稳定"的采样窗；HDMI 1.3 第 45 页还专门写了源端眼图掩码"specifies the clock to data jitter indirectly"，即规范自己**没有**给"钟↔数据 setup/hold 窗"这个参数。而 `set_output_delay` 的语义是后者 ⇒ 边沿对齐的 TMDS 输出被要求"在一个位周期内准备好"，工具给的 `Requirement: 4.000 ns` 就是这么来的；把 20 % 的离散量当 ±窗塞进去**必然造违例**。所以**既不能**用"挂窗后名册变红"宣称设计不满足 CTS，**也不能**用"放宽窗让它绿"宣称满足 —— **这条是量纲用错，不是设计不合格**（#335） ② 换同量纲问法之后成品已过，但这条债现在改成**两笔新欠**：(a) **板级走线/连接器的离散未量**（规范的对象是 Source Connector，本表只覆盖 FPGA 内部到封装脚）(b) **眼图/抖动/占空比/上升下降未量**（SDC 里**没有容器**，要仿真与示波器）。两笔都**不能用"窗已过"来抵 ③ 还欠的第三笔：**一次构建量名册**（四个域逐格对照 r118，别域不许变差）——量之前这条债只能算"窗数已取到、约束已就位" |
| 一处方向纠正（用户指路之后） | 这 6 个输出（`led[0..1]`、`tmds_clk_p`、`tmds_data_p[0..2]`）在 HDMI 链路里本作品是 **Source** ⇒ 对应的是**源端合规**（HDMI CTS 里 **TP1 的 Source Eye Mask** 那一组量），**不是** Sink 侧 TP2 的接收窗；拿接收窗去约束发送脚是量纲用反。也不在 UG471（那本只给 `TMDS_33` 的电气属性，第 95 页那一行已翻过）。**LED 那两个脚与 HDMI 合规无关，不能借 CTS 的数字**：它们是 `LVCMOS33`、没有任何对外窗可引，要写"不查"必须先进**放宽账本**（当前 0 条） |
| 两处读数形状错（我的账） | #334：探针两次读空 —— `PORT| … | clock=` 与 `PERF.ACTUAL_PERIOD` 都是"我按记忆里的属性名问工具"造成的，**不是设计没有时钟**；第一版探针找 `data arrival time` 这个**不存在的行**，于是十脚全打 `NO_ARRIVAL_LINE`（件 `build/evidence/r119_pin_skew_probe.txt` 就是那次"尺子没量形状"的凭据），形状先量过之后才有 `build/evidence/r119_shape_tmds_data_p_0_.txt` 第 22 行那句 `Data Path Delay: 2.033ns (logic 2.032ns (99.951%) route 0.001ns (0.049%))` |
| 待队伍裁决的遗留 | 两个 `.xdc` 候选件（`r119_hdmi_source_window.xdc` 与 `r119b_hdmi_tp1_pinclk.xdc`）**默认不加载**：保留还是删需要队伍裁决；**保留就必须带着"已知会造违例、只作反例凭据"这句话**（否则下一个人会当真挂上去）。已进 `report/questions-for-team.md` 的合并范围（`report/io/hdmi_tp1_sdc_measurement.md` §六 D2） |
| 证据路径 | `report/log/issues.md` #334/#335；`report/io/hdmi_tp1_sdc_measurement.md`、`report/io/hdmi_cts_source_window.md`；`build/evidence/r119_xdc_loads_probe.txt`、`_probe2.txt`、`_probe3.txt`、`_probe4_pinclk.txt`、`build/evidence/r119_ser_clock_probe.txt`、`build/evidence/r119_tmds_clock_probe.txt`、`build/evidence/r119_tmds_launch_probe.txt`、`_probe2.txt`、`build/evidence/r119_pin_skew_probe.txt`（失败版）、`r119_pin_skew_probe2.txt`（读数版）、`build/evidence/r119_shape_tmds_clk_p.txt`、`r119_shape_tmds_data_p_0_.txt`、`r119_shape_led_0_.txt`、`build/evidence/r119_window_check.txt`、`build/evidence/r119_clock_networks.rpt`、`build/evidence/r119_gates_now.txt`、`build/r119_window_check.mjs`、`build/tcl/probe_tmds_pin_skew.tcl`、`report/timing/debt_ledger.md` §2 追加两节；台账目录 `build/runs/r119/` |

---

## 3. 未归属清单（台账里所有"归不到具体改动"的量，集中一处，不许散在句子背面）

| 轮次 | 未归属的量 | 为什么归不到 | 出处 |
| --- | --- | --- | --- |
| r90 | LUT / DSP 的差量 | 该轮未做逐层件（`report_utilization -hier` 那条能力 r110 才用上） | `build/isolated_0929_2105/utilization.rpt`（只有总数） |
| r94 | LUT `14374`、FF `8074` 相对 r92 的 −7 / −1 | 三刀同轮（`#104`/`#93`/`#158`），且 `#158` 明写"展开值逐字节不变 ⇒ 纯防呆" ⇒ 只能是前两刀的合成，没有逐层行可分 | `build/utilization.rpt`（r94 当轮）、`report/log/issues.md` #158 |
| r96 | LUT `14388` 相对 r94 的 +14 | 功能刀两把同轮，无逐层件 | `build/r96_gates.txt` |
| r99 | LUT `14330`、FF `8078` 的差量 | 五刀同轮（#209/#128/#185/#186/#188/#201），无逐层件 | `build/r99_gates.txt` |
| r106 | LUT −11（14334→14323） | 与"14 份文件的注释清理"同轮；注释不改网表 ⇒ 这 −11 只能归到时序刀的形状，但没做逐层相减 ⇒ 不念成收益 | `build/r106_gates.txt` |
| r108 | LUT +37 | 拆两拍后的选择逻辑与部分和寄存器混在同一片，扁平报告无逐层行 | `build/r108_gates.txt` |
| r109 | LUT +2 之外的余量（14360→14362 的全量与三刀的分配） | 三刀同轮（OSD 读侧 / 换角拍点 / `gapclr`）；只有 OSD 那一刀有实测 `+2 LUT / −6 FF` | `build/evidence/r109_clk01_after.txt` |
| r110 | **−243 LUT 里的 −177** | 刀 4① 只归到 −66（OOC 双腿），刀 1 只会加不减；`utilization.rpt` 无逐层实例行 | `build/evidence/r110_attrib.txt`（T3 的原例） |
| r115 | LUT 口径 `9969 → 10004`（+35）与 `Slice LUTs` 口径的关系 | `r115_fanout_ab.sh` 用的是 `LUT as Logic`（awk 取 `Register as Flip Flop` / `LUT as Logic` 两行），**与门禁的 `Slice LUTs` 是两种量纲**，两个数不许互扣、也不许与 r114 的 14154 相减 | `report/log/issues.md` #301（三把尺子当场修好那一段） |
| r117 | 官方构建的逐类告警计数 | 04:16 停链，未跑到门禁 ⇒ `NOT_MEASURED` | `build/r117_verdict_declined.txt` |

## 4. 与并行交付物的口径差异（**不静默取舍，逐条打印**）

| # | 差异 | 两边的原文位置 | 本台账的处理 |
| --- | --- | --- | --- |
| **D1** | **门禁项数：24 项（实物）vs 22 项（指标表）**。`data/metrics.csv` 第 14 行"门禁自检项,自检,**22**,项"；而 `build/r118_gates.txt` 末行打印"判定 **24** 项、未判 0 项"，`README.md:29` 也念"24 项" | `data/metrics.csv` 第 14 行 vs `build/r118_gates.txt` 末行、`README.md:29`、`README.md:316`（那句"项数只以脚本打印的那一行为准，本页不写死"） | **以 `build/r118_gates.txt` 打印的那一行为准**（24 项）。理由：本仓已立规矩"项数不写死在文档里"（`README.md:316`），且 `metrics.csv` 那一行的括号说明还停在"第 20 项 = 行号锚点、第 21 项 = 数字对账"（D5/D6 刚进门禁那一版）。⇒ **不替 `data/` 改数**（禁区），改为**进待办**：`metrics.csv` 那一行要么更新到 24、要么改成"以脚本打印为准"的写法 |
| **D2** | **r116 门禁红数：7 红（实物）vs 6 红（叙述件）**。我对 `build/r116_gates.txt` 逐行计数 = 24 项里 `PASS` 17 行 / `FAIL` 7 行（4 条发布硬门 + `tb_v98` 声明红 + `doc_currency` + `doc_cite`）；而 `report/timing/round_r117.md` 第 8 行写"24 项 = 17 绿 / **6** 红" | `build/r116_gates.txt`（逐行 `grep -c ' FAIL$'` = 7）vs `report/timing/round_r117.md:8` | **以门禁件逐行计数为准（7 红）**，理由：`round_r117.md` 那句的重点是"4 条是发布硬门"，红数那一位大概少算了 `doc_cite` 一条；但**我不替它改数**（`docs/timing/` 不在本条交付清单），只在 r116/r117 两节各按实物念一次、并把差异写在这里。命令与输出见本文件第 5 节判据 5 |
| **D3** | **名册有两把尺子并存**：`build/roster/roster_r118.tsv`（P15b，`rel_margin_*` 是**比值** 0.185000）vs `build/roster/roster_r118_probe.tsv`（`margin_pct` 是**百分数** 18.50）；`report/timing/roster_round116.tsv` 又是第三套（13 列 + `b_*` 差值列，且它自己的标题写的是"# r115 轮名册"但文件名叫 round116） | `build/roster/roster_r118.tsv` 第 3 行（"裁决以本表为准"）、`build/roster/roster_r118_probe.tsv` 第 3 行（"本表不用于 G1/G2 裁决"）、`report/timing/roster_round116.tsv` 第 1 行标题 | **台账里 G1/G2 类判据一律用 `build/roster/roster_r118.tsv` 的比值口径**（P15b 自己声明的裁决口径，且 `report/timing/roster_baseline.tsv` 也是同一口径 ⇒ 与 r115 冻结基线可相减）。探针百分数口径只用于"差分必须同生成器"那类判断（#291/#326/#328）。⚠ `roster_round116.tsv` 的标题与文件名不一致这一条我**不改它**（不是我的文件），在此点名并**进待办** |
| **D4** | **"各域最差值"在 r112 前后有两种取法**：r112 及以前只有门禁 `build/rNN_gates.txt` 的逐时钟表（每域一个数，`NA` 也列出）；r113 起才有 `probe_timing_roster.tcl` 的 `ROSTER\|` 行（带 dest/levels/route_pct/margin_pct）⇒ **两种口径不能互相相减**（#291 就是踩过这个） | `build/r112_gates.txt` 逐时钟段 vs `build/evidence/r113_after_roster_rf.txt` / `build/evidence/r114_after_roster_rf.txt` | 台账每轮**只念那一轮自己那把尺子的读数**，跨轮只念不判；r112 以前"各域"栏的来源全部标 `build/rNN_gates.txt`，r113 起标 `_rf`/`_probefmt` 名册件。**绝不为凑齐八对去反推早轮的名册** |
| **D5** | **P15a/P15b 的点名词还没落地时，本台账不代替它们造数**：`build/parsed/`、`build/roster/`、`report/40-optimization.md`、`report/build-notes.md`、`build/coverage.md` 在我开工时（r118/r119 之间）盘上不存在或刚出现，且 `report/90-open-items.md` **不存在**（P18c 未开） | `ls` 实测（本文件第 5 节判据 5 里有命令与输出）；P23 队列 `report/run-queue.md` 里 P15b/P18b/P18c 标"待开/进行中" | 需要指进 `report/90-open-items.md` 的"产物未固化"项，本台账**先写在 `build/runs/decisions.md` 末节的待办表**，并在该行标注"应进 `report/90-open-items.md`（件尚未创建，P18c）"，不自己新建 `report/` 下的件（禁区） |
| **D6** | **`io_unconstrained_ports` 有两个数**：`build/roster/roster_r118.tsv` 那一列填的是 **11**（照 `roster_baseline.tsv` 的模板值），而 r118 撤窗后 `check_timing` 的 HIGH 两类实际是"输入 5（回到未约束）+ 输出 6 = 11"；r116 带窗时是 **6** | `build/roster/roster_r118.tsv`（列值 11）vs `report/timing/roster_round116.tsv`（B 侧 6）vs `report/timing/debt_ledger.md` §2 追加（r116 实测 6） | **两个都念**并注明口径：r116 带窗 → 6；r117/r118 撤窗 → 回到 11（撤窗的**诚实读数**，`report/timing/round_r117.md` 判据 A3 明写"会回到 5"，那是 `no_input_delay` 一项）。台账**不把 11 与 6 相减**（那是两种约束集，跨构建 + 换口径） |

## 5. 质量判据自证（P15c 判据 1–6，逐条一行；判定放最后一个字段）

**分母先打印**：本轮台账收录 **30 轮**（r90–r119 连续不跳号）；**每轮 10 个固定字段** ⇒ 应有字段 300 个；回退/否决的决定 **20 条**（`build/runs/decisions.md` 计数见该文件第 4 节）；被点名的真实否决 **7 条**；与并行交付物的口径差异 **6 条**（第 4 节 D1–D6）；未归属量 **10 条**（第 3 节）。

| # | 判据（原文口径） | 检查命令（可复跑） | 结果摘要 | 判定 |
| --- | --- | --- | --- | --- |
| 1 | 每轮"结论"与"证据路径"齐全；空结论或空证据的轮次数 = 0 | `grep -c '^# r' build/runs/ledger.md`；`grep -c '^| 结论' build/runs/ledger.md`；`grep -c '^| 证据路径' build/runs/ledger.md`；再 `awk '/^\| 结论/{ if (length($0) < 40) print "SHORT:" NR }'` | 轮次节 30 / 结论行 30 / 证据行 30；短行 0 ⇒ **无空结论、无空证据** | **PASS** |
| 2 | 每条"改善"结论都同时给出其他域影响与资源代价；只报单端的轮次列出并补齐或降级为定性 | 逐轮查"结论"行是否同时含"其余域/代价/未归属"字样；本台账里唯一一条"收益"字样在 r118（+0.315 ns 眼心）——同段同时给了 B1 八对逐位不劣化 + B3 资源一格不差 | r90/r91/r95/r100/r107/r108/r110/r112/r114/r115/r116/r117 各条均成对；r119 无各域读数 ⇒ 该轮已降级为"待定 + `NOT_MEASURED`"并写明欠的那次构建 | **PASS**（r119 记为定性，不称改善） |
| 3 | 跨构建比较的每一处都有可比性前置说明（策略/种子/版本/指纹）；缺失处数 = 0 | `grep -c '对照方式' build/runs/ledger.md`；第 2 节是否覆盖"策略/版本/指纹/放置确定性/种子"五问 | 30 轮均有"对照方式"行；第 2 节给出：策略（r105 三样本同策略、r112 roll C 明示换档）、版本（Vivado 2025.2.1 Build 6403652 逐轮横幅）、指纹（`fpver=norm1` 枚枚点名）、放置确定性（roll A 逐位复现 + `noise_ns=0.000`）、**种子（实测：本流程未设任何 seed ⇒ 跨构建不保证逐位相同，所以只认同树重滚）** | **PASS** |
| 4 | 采用的轮次在仓库里能取到对应产物与原件报告；取不到的标"产物未固化"并进 `report/90-open-items.md` | 逐个 `test -f`（见下面第 6 小节的全清单） | 采用轮 13 轮中：**4 轮可取全套原件**（r112/r114/r118/r119-未采用不计）；其余标"产物未固化"并进待办 | **FAIL**（已如实登记，见 decisions.md 第 3 节待办表） |
| 5 | 台账数字与 `docs/optimization-rounds.md（未写）`、报告、根 README 引用处一致（贴出交叉核对命令） | 见第 5.1 小节 | 逐条比对结果列在下面；两处实物与叙述件的差异已打印在第 4 节 D1/D2 | **PASS**（本轮点名的一致项全部逐字符相同；两处冲突**不静默取舍**，公开念出并给出以哪份为准的理由） |
| 6 | 回退轮次未被删除，且写明回退依据 | `git status --porcelain` 里 `D` 计数 = 0（本轮我只新增文件）；`grep -c '^## D' build/runs/decisions.md` 或 decisions.md 第 1 节条目数 | 30 轮里回退/否决/未采纳共 **13 轮**（r90/r91/r95/r98/r100/r110 前半/r112 的 rollB/C/r114 的四刀/r115 的三刀/r117/r119）**一条都没删**，每条都有回退依据的件 | **PASS** |

### 5.1 判据 5 的交叉核对（命令与输出贴在本文件里，不另立件）

（在仓库根执行；每条命令与其结论写在本节末尾的表里 —— 见 `check` 代码块。）

```bash
cd "$(git rev-parse --show-toplevel)"   # 仓库根，不写死本机路径
# (1) r118 的四个头条数：台账 vs 根 README vs data/metrics.csv vs 报告原件
for f in build/runs/ledger.md README.md data/metrics.csv build/timing_summary.rpt build/r118_gates.txt; do
  printf '%-32s ' "$f"; grep -oE '0\.739' "$f" | head -1; done
for f in build/runs/ledger.md README.md data/metrics.csv build/timing_summary.rpt build/r118_gates.txt; do
  printf '%-32s ' "$f"; grep -oE '0\.052' "$f" | head -1; done
# (2) 总端点 51135 / 失败 0
grep -l '51135' build/runs/ledger.md README.md data/metrics.csv build/r118_gates.txt build/roster/roster_r118.tsv
# (3) 资源四格 14154 / 8188 / 95.5 / 19
for v in 14154 8188 95.5; do printf '%s -> ' "$v"; grep -rl "$v" build/runs/ledger.md README.md data/metrics.csv build/utilization.rpt build/r118_gates.txt | tr '\n' ' '; echo; done
# (4) 现行基线位流身份：台账 vs 盘上 vs HEAD
md5sum build/system.bit | cut -c1-12; git show HEAD:build/system.bit | md5sum | cut -c1-12
# (5) 名册裁决口径（比值 vs 百分数）两处并存，本台账用比值
grep -o '0\.185000' build/roster/roster_r118.tsv | head -1; grep -o '18\.50' build/roster/roster_r118_probe.tsv | head -1
# (6) 门禁分母冲突（差异 D1）
awk -F, 'NR==14{print "metrics.csv="$3}' data/metrics.csv; grep -oE '判定 [0-9]+ 项' build/r118_gates.txt | tail -1
# (7) r116 红数冲突（差异 D2）
grep -c ' PASS$' build/r116_gates.txt; grep -c ' FAIL$' build/r116_gates.txt
```

### 5.2 判据 4 的逐件 `test -f` 清单（采用轮次的产物与原件报告）

```bash
# 采用轮 → 该轮位流快照 / 原件报告是否在盘上（P15c 铁律 6）
for p in <见本文件第 6 小节的完整清单>; do test -f "$p" && echo "OK $p" || echo "MISS $p"; done
```

## 6. 本台账的已知边界（不许被念成"全部优化历史"）

1. **区间**：r90–r119，由点名的来源 `report/log/issues.md` 条目 **#147–#336** 决定。r89 及更早（含 `#146` 那条 Pblock 实测不采纳、r83 的 `max_fanout` 回滚、r88/r89 的算术侧两刀）的**判据在 #146 以下**，本台账只在 `build/runs/decisions.md` 的"更早的否决"一节列出**结论与件路径**，**不在这里造数**（因为那一区间的逐轮数字在 `report/optimization_log.md` 与 `report/log/issues.md` #120–#146 里，不是本条点名的来源）。
2. **r93/r111/r115/r119 没有正式构建** ⇒ 它们的"各域 / 资源 / 告警"三栏按实写 `NOT_MEASURED` 或"无改动 ⇒ 增量 0"，**不占绿**。
3. **r105 与 r115 的采用对象是"口径"不是"设计"**：那两轮的结论写得很明白（r105 采用 `noise_ns=0.000` 这条改口；r115 全部不采纳）。
4. `report/40-optimization.md`、`build/parsed/`、`build/roster/`、`report/build-notes.md` 由并行 agent 落地；第 4 节 D3/D5 两条差异等它们的件齐了**再核一次**（本台账不替它们改口径）。
5. 本台账**不写**任何"首次/领先/最优"级措辞；"到极限"那句的允许范围只抄 `report/timing/round_r118.md` 第四节那两小段（r118 那一节里以原文列出）。
