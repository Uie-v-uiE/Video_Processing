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

---

# r116 版门禁判定（03:1x 填齐；构建 01:34 回来、板 01:37 刷、台架与门禁 03:0x 在飞）

| 门 | 内容 | r116 状态（每一项都指到件） |
| --- | --- | --- |
| **G1** | 所有域 rel_margin ≥ 基线 | ❌ **按字面红**：`eth_rxc` 两格变小（setup 9.24→−10.57 %、hold 0.65→−10.88 %），件 `build/evidence/r116_roster_diff.txt`（`judged=6 pairs=8 result=RED`）。**这一条我没有话术**：变小的那两格是本轮第一次被检查的 5 个 I/O 端点（绑窗前它们是 `Slack: inf`），G1 与 H5 在这里天然冲突——不绑窗就 H5 红、绑了就 G1 红，两条都写出来才是本轮的产出物。其余三域**一格没掉**：`clk_fpga_0` 18.50→19.76 %（+6.8 %）、`clkout0_1` 18.15→18.49 %（+1.9 %）、`sys_clk` 持平；四域 hold 逐格不动 ⇒ **没有任何域被"搬"过来**（`ROSTERDIFF-COST` 只点 `eth_rxc` 两格，`GAIN` 点两格） |
| **G2** | 两类"没覆盖"计数不许变大 | ✅ `unconstrained_internal_endpoints` **0→0**；`no_input_delay` 里真正没约束的端口 **5→0**（另有 2 个输入是既有 false_path 覆盖，本轮没动）；`no_output_delay` 里 **6→6**（`led[0..1]`、`tmds_clk_p`、`tmds_data_p[0..2]`——**这一族数字非 0  ⇒ H5 按字面判红**，见 §6.4 的两条出口）；第二把尺子 `report_methodology` 的 `TIMING-18` 从 **7→2**（checks 口径，不与端口数相减）。件 `build/evidence/r116/r116_check_timing.txt`、`build/methodology.rpt` vs `git show HEAD:build/methodology.rpt` |
| **G3** | 松动台账为空 | ✅ **0 条数据行**，且两条"看起来该放松"的都在台账注释里点明没放松：`eth_rxc` 的 0.800 hold 带与输入窗双重计（去掉能把 −0.870 抬到约 −0.385，仍不是绿 ⇒ 不换）、`r114_io_async.xdc` 那个用错行的 ±0.500 窗没进工程 |
| **G4** | 每域"到没到极限"逐域判定 | ✅ 从"未测"变成**逐域有件**（`docs/timing/limit_audit_r116.md` + 交付侧 `report/TIMING_GLOBAL.md` 第 6 节）：`sys_clk` 74.38 % 不是瓶颈；`clkout0_1` 主导项是 22 级逻辑（9 级 CARRY4）＝功能面授权之外；`eth_rxc` I/O 那 5 格有不相交区间 + 角间差不等式；**`clk_fpga_0`：02:49 的量把根因从"两端离得远"改成 FANOUT（一根 239 引脚网吃 5.690 ns），03:01 的快车道单变量滚量到一把**赢**的刀**（+0.033/+0.187/+0.298，代价 +10 只 FF，别的域一格不动，件 `build/evidence/r117_repl3/B_console.txt`）⇒ 落地入口 `build/tcl/r117_post_place_hook.tcl` |
| **G5** | 机制侧读数（不能只看 slack） | ✅ 刀 1：5 条路从 `Slack: inf / Path Group: (none)` 变**有限**并出现 `Input Delay: 1.200 / 2.800 ns` 行（`build/evidence/r116/r116_io_{HOLD,SETUP}.rpt`，且 `Path Type` 分别是 `Hold (Min at Slow)` / `Setup (Max at Fast)`——I/O 路与片内路的角分配是反的，这条已写进窗模型）；刀 2：`IDELAY_VALUE` 逐档回读 0/4/…/31 全对上（`probe3_console.txt`） |
| **G6** | 噪声底 / 反事实 | `noise_ns=0.000`（r115 两次空白滚逐位复现）。**本轮新增一条同尺反事实**：对照滚 A（不加 phys_opt）逐格复现 r116 正式名册（件 `build/evidence/r117_fb_pblock/A/roll_console.txt` 的 `ROW` 行 vs `build/evidence/r116_after_roster.txt`）⇒ 复制滚 B 与它的差可以直接归因给那一刀（H3） |
| **G7** | 每条新判据能变红 | ✅ 本轮新增的是尺子而不是门禁项：`metric_recheck` 补**符号维**（首页第一次写负 slack，旧式子读不出负数 ⇒ 写对也红、写错也红，射程为零，#321）；自带 6 条合成对照（`SELFSIGN-SUMMARY 判 6 条：负数可读=绿、负数写错=红，红 0`），且 `--self` 原有两条 fixture 仍恰好红 2 次 |
| **G8** | 指纹先打、构建中不改源 | ✅ `rtl=07570b1ac1b4` 于 01:13:24 打（`build/evidence/r116_tree_fp.txt`），构建期间 `src/` 未动；改口的交付文档在构建之后（不属构建期源改动）。构建在飞期间**没有编辑任何正在被后台执行的脚本**：`r116_stage2.sh` 只读、新刀一律另起文件名（`repl117_roll3.tcl` 而不是改 `roll2`） |
| **G9** | 告警/方法学计数只算成本 | ✅ **实例 446→441、类数仍 3**（TIMING-9/10/18），没有新增类 ⇒ 计数是降的；预期会出现的 `TIMING-15` 没来（工具把 I/O 违例归到既有 `TIMING-18` 之外的 `report_timing`，摘要里没新增类）。比较次数念出来：`judged=6 pairs=8`（名册）、`判 115 个数`（metric_recheck）、`CURRENCY 6 条`（指路）——三个 N 各有自己的行，见 `build/evidence/r116_roster_diff.txt`、`node src/host/metric_recheck.mjs` 末行、`node src/host/doc_currency_check.mjs` 末行 |
| **G10** | 未经板验不写板级口吻 | ✅ 板级话只有一句、且有件：01:37 刷入、01:50 `board_verify --geom --battery` PASS 判红步骤 0、02:14 带流 `drop_words=0`/`pkt_err=0`、回刷 r114 做 A/B（#318）。其余全部是报告/规格书口吻；`src/ps` 一字未动 ⇒ 没有任何 ELF 层面的承诺 |
| **G11** | 不把已判负的刀再记一次收益 | ✅ 复制驱动 #288（那是 **`eth_rxc` 域**的高扇出驱动，与本轮 `clk_fpga_0` 那根 239 引脚网**不是同一根网**，所以 C9 不是重复记账——这一点在 cut_ledger 的两行里分别点名了目标网）、MMCM 相移（r115 §7.3）、Pblock（r113 + 本轮 `PB_EXISTING_BOX=` 空自拒）都没有被重新记成收益 |
| **G12** | "极限"这句话的强度 | 见附录 3 第 12 问：**L1 有件（逐段分解 + route 0.000 %）；L2 有 4 条独立负结果（tap 全档、MMCM、Pblock、统一带子）；L3 有件（差分只红在被新检查的那两格，其余三域持平或变好）** ⇒ 允许写"这一格在当前结构下不存在能同时满足两条检查的采样点"。仍然**不许**写的两句：① "已证明是板上真实的差额"（窗模型自身还有 `TskewR` 那行的残余风险，§6 写着）；② "BUFIO 换树也关不掉"（那条路的快角 DCD 还没量，第 7 节给了它 40 秒的前置探针） |