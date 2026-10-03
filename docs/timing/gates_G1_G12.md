# §4 E2 判定表 — G1..G12 逐条（本轮 = r115，2026-10-03 夜，快车道 D1 双滚）

**本轮总裁决：RED（不采纳任何东西）**。红在哪、为什么红、哪些是债哪些是刀，见下表与"红项归因"节。
基线工件：`docs/timing/roster_baseline.tsv`（md5 `039c16e373e5…`）；本轮工件：`docs/timing/roster_round115.tsv`
（8 行、24 次数值比较 + 8 格双侧 NA = 32 次比较、4 红）。
两滚输入：同一份 `system_top_opt.dcp`（md5 `4c895816c4f2`）+ 同一棵树 fp（`top=56c269602e18 rtl=3969247aaf7f`）。

| 门禁 | 判定 | 依据（数字后面紧跟它出自哪个工件） |
| --- | --- | --- |
| **G1** 没有任何域的 rel_margin 变小（容差 = noise_ns=0.000） | **RED（4 格）** | `docs/timing/roster_round115.tsv` 的 4 行 ROUND-RED：eth_rxc setup 0.092375→0.083125（WNS 0.739→0.665）、eth_rxc hold 0.006500→0.004250（WHS 0.052→0.034）、sys_clk setup 0.743800→0.738600（14.876→14.772）、clk_fpga_0 hold 0.005300→0.004200（0.053→0.042）。**这就是提示词点名的"拆东墙补西墙"形状**：同一把刀确实把 clk_fpga_0 setup 抬了 0.185→0.1959（1.850→1.959）、clkout0_1 setup 抬了 0.1815→0.195（3.630→3.900），代价落在 eth_rxc 的 setup+hold 与 sys_clk 的 setup |
| **G2** 两列债务不增加 | **GREEN** | `ROSTERDIFF … unconstrained_endpoints 0.000000→0.000000`、`io_unconstrained_ports 11.000000→11.000000` 八个域逐格相同（件 `/tmp/kx/r115_fan/roster_diff.txt`，已随 `build/evidence/r115_fanout_ab/roster_diff.txt` 归档）。**注意**：绿灯不等于债清了——`io_unconstrained_ports` 本来就是 **11**，见 H5 |
| **G3** 松动台账 = 0 条 | **GREEN** | `docs/timing/loosen_ledger.tsv` 只有表头 + 注释，数据行 0。夜里没有批准人 ⇒ 一条都不松（H1/G3） |
| **G4** 警告类别计数不增加 | **未测（不许念成绿）** | B 滚没有出 `report_methodology`：`build/tcl/mf114_roll.tcl` 的报告清单今天才补了 `check_timing -verbose` 与 `-logic_level_distribution` 两行（ISSUES #298），**methodology 还没补**。基线侧的数是 `Checks found: 446 = 2+1+336+98+1+1+7`（件 `build/evidence/r115_base/methodology.txt`）。下一刀进快车道前先把这行补齐，否则 G4 永远是空的 |
| **G5** route_status successful 且无 Place 30-439 | **GREEN** | `FANAB F6_route_status A[err=0 full/rout=20882/20882] B[err=0 full/rout=21197/21197] place30439=0 … GREEN`（件 `build/evidence/r115_fanout_ab/verdict_header.txt`）。形状是量出来的：`report_route_status` 的**文件里没有 "successful" 这个词**，它是一张净计数表 ⇒ 判据写成"路由错误 0 且 全布==可布 且 >0"（ISSUES #301） |
| **G6** 利用率不越器件红线 | **GREEN** | B 滚 `Block RAM Tile 95.5/140 = 68.21 %`、`Register as Flip Flop 8463/106400 = 7.95 %`、`DSP48E1 19`（件 `/tmp/kx/r115_fan/B/util.rpt`）；A→B 的增量 = **FF +275、LUT +35**（`FANAB F7` 行，两个操作数来自两份 util.rpt 而不是同一份）。没有新越界 |
| **G7** D3 RTL 改动的单元台架全绿（含正对照） | **不适用（本轮 D3 改动 0 处）** | 本轮只动探针/文档，没动 `src/rtl`（树 fp 与基线逐位相同：`rtl=3969247aaf7f`，`FANAB` 头行）。空集分支按规矩不当绿：它记为"比较次数 0" |
| **G8** 每个数字都点名工件且工件内容支持这句话 | **GREEN（有自查过程）** | 本表每一格右边都有件路径；两处**做不到的地方直接写"未测/不适用"而不是借用别的数**（G4、G7）。另外 `build/evidence/r115_base/check_timing.txt` 文件名与内容不符（里面是 `report_timing`），已写成 ⚠ 行而不是悄悄改名（ISSUES #299） |
| **G9** 作用域计数器数的是"做了多少次比较" | **GREEN** | 四个打印点：名册差分 `comparisons_made=32`（8 域 × 4 列，含 8 格 both_NA，`red` 是另一列）；轮名册 `rows=8 comparisons_made=24 both_NA=8 single_NA=0 reds=4`；`report_high_fanout_nets` 自比 `cmp=60 lower=0 equal=60`；噪声标定 4 条判定 + 1 条 INFO。没有一个计数器按"通过"加一 |
| **G10** 每条新门禁项自己有能红的测试 | **GREEN** | `r115_roster_build.py --self` **5 条**（含注入 hold 变差、注入 I/O 债变大、丢时钟、both_NA 计数与身份）；`r115_round_roster.py --self` **3 条**；`r115_fanout_cmp.py --self` **4 条**。今天这些对照**真的各咬红过一次**（both_NA=3 假红、扇出列索引 [0]/[1] 两条 FAIL、驱动目录 0 秒全红），不是纸面绿 |
| **G11** 声称"到极限"必须满足 L1/L2/L3 | **不声称** | 而且要先纠正我自己一处口径：今夜这把 C1 与 r114 的 **#288 是同一个候选**（复制驱动），两支尺子 agree 只加**可信度**、不加**样本数** ⇒ L2 要求的"3 条互相独立候选"现在数得上的是：复制驱动（两次同候选）、Pblock（r113：1716 个目标里 255 个被留在块外，那次其实不是单变量）、RGMII 真窗（一绑上 hold 即 −2.885）——**三条里只有第一条是 D1 实测判负**，其余两条一条是"没做成"、一条是"前置未做"。L1 的分段占比也没按 §7 走完。所以本轮的话只能写成："收敛到 0，未证明到极限"（见 twelve_questions 第 12 问） |
| **G12** 每个红项要么归因、要么进下一轮候选 | **GREEN** | 红项共 2 类：① H5 的 `io_unconstrained_ports=11` ⇒ 归因为"缺 I/O 窗口约束"，且**已量到**加上 ±0.5 ns 真窗会 hold −2.885（债务条目 + 候选 C4/C3）；② G1 的 4 格 ⇒ 归因为 C1 这把刀本身的代价，刀已**拒绝**，不进名册不进构建。没有"未知原因但绿了"的格子 |

## 本轮唯一那条刀的读数（C1 FANOUT，机制确实动了）

| 项 | A 滚（对照） | B 滚（`phys_opt_design -force_replication_on_nets` 39 根网） |
| --- | --- | --- |
| `REPLICA_CELLS` | 0 | **310**（机制动了，不是 MECHANISM_INERT） |
| 名册里能对上的网扇出 | 3 根同名网 | 1 降（`u_pl/u_clk/u_mmcm_0` 2109→2062）、**2 升** |
| 头条（A 滚自己） | WNS 0.739 / WHS 0.052 / 失败端点 0+0 | 见 G1 的四格：eth_rxc 0.665/0.034 |
| 资源 | FF 8188 / LUT 9969 | FF **8463** / LUT **10004** |
| 判定 | — | **拒绝（G1 红 4 格，代价 > 收益）** |

⚠ 一条重要的**反证**同时成立：A 滚（不带任何变量的空白滚）的名册与 `roster_baseline.tsv` **逐格相同**
（32 次比较全绿、8 格 both_NA，件 `/tmp/kx/r115_fan/`+`build/evidence/r115_fanout_ab/roster_A.tsv`）。
⇒ 快车道在这棵树上**复现了正式构建的逐域名册**，这也反过来支持"F5 那 4 格红是刀造成的，不是滚造成的"。
但它仍**不是**正式构建（没有新 bitstream、没有台架），所以本轮不采纳任何东西。

## 为什么不"退一步"把 C1 只用在 clk 域上

收窄 `-force_replication_on_nets` 的网清单会同时改变被分析对象与放置，那就不是单变量实验（#223 的纪律），
而且真正的痛点在 eth_rxc：它的名册余量最小（0.092375）却是**唯一被复制代价打到**的域。
下一轮的刀应该砍在 eth_rxc 的**捕获钟相位**（C3/#194），而不是砍在广播网的驱动数量上。
