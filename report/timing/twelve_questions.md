# 附录 3 — 交付前 12 问自检（逐条有答案，没有一条留空）

这份自检有两份，各自独立成段：**第 1–75 行是 r115 那一次快车道 D1 的量**（只有网表/报告层的滚：没有正式构建、没有上板、没有任何切割被采纳）；**第 79 行起是 r116 那一版**（正式构建 + 刷板 + 板级 A/B 之后的读数）。两份点名的 `build/evidence/r115_*`、`r116_*`、`r117_fb_pblock/*` 有一部分是**过程件**，`build/` 精简之后已不在盘上，名字留着是为了对回 `report/log/issues.md` 的编号。

**1. 有没有任何一个域的 rel_margin 变小了？（差值列在哪）**
有，4 格，全部落在**被拒绝的那一刀**（C1 复制驱动）身上：差值列在 `report/timing/roster_round115.tsv` 的
`rel_margin_setup_delta / rel_margin_hold_delta`，红行是 `eth_rxc`(setup 与 hold)、`sys_clk`(setup)、`clk_fpga_0`(hold)。
**对照的那一版（= r114 构建）没有任何域变差**：r115 那一次没动 `src/`，树 fp 逐位不变（`rtl=3969247aaf7f`）。

**2. 这一版的 WNS 变化，D1 反事实跑了几次？噪声底是多少？**
反事实共 **4 滚**：噪声标定 2 滚 + 这一刀的 A/B 2 滚，一滚 6.4–7.5 分钟（起止时刻印在各滚的 console 里）。
噪声底 **noise_ns = 0.000**（件 `/tmp/kx/r115_noise/noise.txt`：头条四数逐位相等 **且** 最差路径身份相等才算 0）。
所以 G1 那 4 格红**严格大于噪声**，不是骰子。

**3. 我引用的每个数字，紧跟的是哪个工件、指纹对不对？**
判定表逐格带件路径（`report/timing/gates_g1_g12.md`）；基线 22 份报告的 md5 与 producing command 在
`report/timing/baseline_index.md`。**一处不自对**：`build/evidence/r115_base/check_timing.txt` 文件名与内容不符
（里面是 `report_timing`），已按 警告 行写明，那一次 I/O 债的读数一律只取 `check_timing_verbose.txt`（ISSUES #299）。
设计指纹在每次起跑**前**取（H4）：`fpver=norm1 files=80 top=56c269602e18 rtl=3969247aaf7f`，`dcp md5=4c895816c4f2`。

**4. 松动台账是不是空的？不空的话每条的非时序证据是什么？**
空的（`report/timing/loosen_ledger.tsv` 数据行 0，只剩表头）。没有批准人在场时按 H1/G3 一条都不松。
两处"看起来该放松但没放松"（eth_rxc 的 hold 不确定度 0.800 没调小；RGMII ±0.5 ns 输入窗没绑进工程）写在台账注释里，
**并给的是反向证据**：绑上真窗之后实测 WHS −2.885 / THS −14.344（件 `build/evidence/r114_io_roll_console5.txt` 的 `[Route 35-57]`）——
方向是"先修捕获钟再绑约束"，不是"去掉约束让它绿"。

**5. `unconstrained_endpoints` 和 `io_unconstrained_ports` 现在是多少？**
0 与 **11**（输入 5：`eth_rx_ctl`、`eth_rxd[0..3]`；输出 6：`led[0]`、`led[1]`、`tmds_clk_p`、`tmds_data_p[0..2]`）。
⇒ **按 H5 直接判红**：这两个数不为 0 时 WNS 数字无意义。这一格把"设计所有域都绿"从结论降级成了"未被约束覆盖"——
默认不加载输入窗的那一版至今是 `0 / 11`，把窗绑上去的那一版是 `0 / 6`（绑窗那一次的读数在后半第 5 问）。

**6. `report_methodology` 警告类别计数相比基线增加了吗？增加算成本还是收益？**
**没测**（快车道滚的报告清单里还没有 methodology，见 gates 表 G4 行）——写"未测"，不写绿。
基线的数是 `Checks found: 446 = 2+1+336+98+1+1+7`（SUMMARY 表，七项相加闭合）。
按口径：**警告类别数算成本**，不当收益（规矩 35 的延伸）。

**7. 我的判定器"做了多少次比较"？这个数字在哪一行打印的？**
四个打印点：名册差分 `ROSTERDIFF-SUMMARY comparisons_made=32`（= 8 域 × 4 列）；
轮名册 `ROUND rows=8 comparisons_made=24 both_NA=8 single_NA=0 reds=4`；
扇出自比 `cmp=60 lower=0 equal=60`；噪声标定 N1–N4 四行 + N5 一行 INFO。
没有一个计数器按"通过"计数（G9）：这四行打印的都是 `comparisons_made`、`both_NA` 这类**比较次数**，不是通过条数。

**8. 每条新增门禁，有没有它自己能变红的测试？**
有，而且**每一条都真的红过一次**：`r115_roster_build.py --self` 5 条（both_NA 常量假红把它逼成"由夹具算期望"）；
`r115_round_roster.py --self` 3 条；`r115_fanout_cmp.py --self` 4 条（列索引错时 2 条当场 FAIL）；
驱动脚本的 F1/F6 因为形状猜错判过假红（`^ROLLDONE` 锚点、route_status 里根本没有 "successful"），已按实测形状改对。

**9. 有几次尝试触到了 H7 的 3 次上限？回滚了吗？回滚先只读跑过吗？**
没有一把刀用满 3 次。C1 是**第 1 次**就被名册判负 ⇒ 直接拒绝，没重试（也不换口径重试）。
这一版没有需要回滚的源改动（`src/` 一字未动）；被"回滚"的是两把**文档/脚本**层的错尺子，
回滚能力先只读验过：`bash -n` + 各 `--self` + 用现成滚重跑 `--analyze`（不重烧 GPU）确认它们回到能判的形状。

**10. 有没有哪句话我用了板级口吻但实际没上板？**
没有。这一段全部是网表/报告层读数，凡涉及行为一律不带"板上验证过"的口气；
`src/ps` 一字未动（改了也只是源码级：ELF 可用 `node build/ps_app.mjs` 重建，但重建那颗与板上那颗 md5 不同，要重刷 + `board_verify` 复验才算板上验证，H6）。
r116 那一版是真刷过板并板级复验的：bit `bb2fb707aebc`、三步 JTAG 链、`board_verify --geom --battery` **PASS 判红步骤 0**（geom 10/0、105 条串口命令全过）、带真实流量（147 Mbps）两次读数 `drop_words=0`/`pkt_err=0`，并用回刷 r114 做 A/B 证明 `frames_bad=1` 与 r116 无关（读数抄在 `round_r116.md` 的 V6 与 ISSUES #318）。
眼睛判据的现况按 `board/acceptance.md` 的 E6 那一行：当前板上那颗（位流 `cd04907e1369`）冷上电读 0、已由在场的人判过；仍欠的是"按住 KEY1 那一次"的对照那一半。

**11. 剩余红路径的根因标签是不是每个都挂上了？有没有"未知原因但绿了"？**
两类红都挂了标签：G1 的 4 格 = `FANOUT`（C1 自身的代价，刀已拒）；H5 的 11 端口 = `UNCONSTRAINED`（C4）。
有一条**对象未明**的挂在债务里而不是绿灯里：`TIMING-10` 还剩 1 条"Missing property on synchronizer"，
它**不是**格雷码链（`ASYNC_REG` 落地 0→56 颗之后该计数一点没动，ISSUES #290）——标签 `ASYNC`，进候选队列。
"未知原因但绿了"：没有；但有一条"未测却容易被当绿"的（G4 methodology），表里明写未测。

**12. 这里写下的"极限/完成/无风险"里，哪一句其实只满足了 §7 的两条？**
**没有**写"到极限"。这一版真实的一句话是：**收敛 0 ns（没有任何切割被采纳），未证明到极限**。
离 §7 差什么：L2 要"至少 3 条互相独立的候选被 D1 实测收益 < noise_ns"——这里只新增 1 条（C1，且是判负不是判平）；
L1 的分段占比有分解读数（最差的 eth_rxc 那族 route 占 58 %、级数 11，件 `build/evidence/r115_base/timing_summary.txt`
与 `da_levels.txt`），但没按 §7 要求把"四段占比 + 不可再压"论证完；L3 因为这一版什么都不采纳而自动成立。
三条不齐 ⇒ 不许用那个词。

（L1 那半句的分段读数是 `Data Path Delay: 7.066ns (logic 2.936ns 41.553% route 4.130ns 58.447%)` 与
`Logic Levels: 11 (CARRY4=6 …)`，出自件 `build/evidence/r115_base/check_timing.txt` 的第一条路径
——警告 那份文件**实为 `report_timing`**（见 debt_ledger §6 与 ISSUES #299），所以这里点名它时按"内容"而不是按"文件名口径"引用；
级数分布另有 `build/evidence/r115_base/da_levels.txt`。）

---

# 附录 3 · r116 那一版（正式构建 + 刷板之后的读数；凡依赖构建的格子都已按件填实）

**1. 有没有任何一个域的 rel_margin 变小了？**
两刀都落在 `src/` 上，所以这一格的答案由名册差分给：件 `build/evidence/r116_roster_diff.txt` 末行 `judged=6 pairs=8 result=RED`，
变小的两格正是 `eth_rxc` 的 setup（0.739→−0.846）与 hold（0.052→−0.870）；变好的两格是 `clk_fpga_0` 1.850→1.976 与 `clkout0_1` 3.630→3.698；`sys_clk` 14.876→14.876 一格不动。
**刀 1 是纯加严**（5 个端口从"无检查"变"有检查"）、**刀 2 只改 I/O 延迟线参数**（网表里除 IDELAYE2 的 `IDELAY_VALUE` 外无差别）⇒
若差分显示某个**与 I/O 无关**的域变差，那一定是实现阶段的重排副作用，不是这两刀的直接效果——这一条判法写在 `build/r116_batch_plan.md` V4。

**2. 这一版的 WNS 变化，D1 反事实跑了几次？噪声底是多少？**
答：噪声底 `noise_ns = 0.000`（r115 两次空白滚逐位复现）。同尺反事实 **2 次**：① 对照滚 A 从 `impl_1/system_top_opt.dcp` 重跑 place+route，**逐格复现 r116 正式名册**（件 `build/evidence/r117_fb_pblock/a/roll_console.txt` 的 `ROW` 行 vs `build/evidence/r116_after_roster.txt`）⇒ 这台工具的跨构建差不是骰子；② 复制滚 B 与 A 只差一个变量（`phys_opt_design -force_replication_on_nets`），所以 +0.033 / +0.187 / +0.298 直接归因给那一刀（件 `build/evidence/r117_repl3/b_console.txt`）。
**不拿 WNS 变化当收益**（rule 35）。刀 2 的收益是**同一只已布线 DCP 上、同一把尺、逐档扫出来的**
（`probe3_console.txt`：τ 26→31 让最差格从 −1.185 到 −0.870，+0.315 ns），
它不需要反事实，因为它不是跨构建比较。噪声底 r115 已钉：`noise_ns = 0.000`（空白滚逐格复现基线名册）。

**3. 我引用的每个数字，紧跟的是哪个工件、指纹对不对？**
新增的数字全部有件：strap 电阻（`r115_sch_p8/rxd_area.png`、`phy2_straps.png`）、
规格书行（`r115_rtl8211f_delay_source.txt` 整页原文）、窗的四种拼法（`r115_window/probe2_console.txt`）、
0…31 扫描（`probe3_console.txt`）、逐域最差路（`r115_base/setup_nworst.txt`、`r114_after.txt`）。
树指纹 `rtl=07570b1ac1b4`（`build/evidence/r116_tree_fp.txt`，构建起飞前打的，H4）。
**复算过**：斜率 62.97/−91.97 ps/拍、交点 31.1、零点 44.8/21.8、角间差 3.411/0.467、
比率门槛 1.73(有带)/1.45(去带)、覆盖率 70.4/70.4/66.8 % —— 全部由脚本从表里的数重算一遍对上。

**4. 松动台账是不是空的？**
**是空的（0 条）**。而且连"看起来该松"的那条都没松：`eth_rxc` 的 0.800 `-hold` 与输入窗双重计一条保护带，
去掉它能把 hold 从 −1.185 抬到 −0.385 —— 但**抬不到绿**（setup 侧 τ ≤ 21.8 不动），
所以它换不来任何绿色，也就不构成"为绿而放宽"。留着的代价写在 §7.5(8)（它把 τ 的最优点从 21~26 推到 31）。

**5. `unconstrained_endpoints` / `io_unconstrained_ports` 现在是多少？**
r115 是 `0 / 11`。刀 1 专门打这 11 里的 5 个 ⇒ 按字面应当落到 `0 / 6`。
**实测（件 `build/evidence/r116/r116_check_timing.txt`）：`unconstrained_internal_endpoints = 0`；真正没有 input delay 的输入端口 = 0（5→0，另有 2 个是既有 false_path 覆盖、这一版没动它）；没有 output delay 的输出端口 = **6**（`led[0..1]`、`tmds_clk_p`、`tmds_data_p[0..2]`）⇒ 第二数非 0 ⇒ H5 按字面判红。**这 6 个端口缺的是**外部规范数**，
当时本机板级资料没有、两次在线取原文也没拿到可引用的一页 ⇒ 按"没有来源就不写数"，H5 这一条**当时判不满**；
这一格后来换了状态：数取回来了（HDMI 1.4 §4.2.4 Table 4-24 的钟↔数据 0.20 Tcharacter，逐条判定写在 `report/io/hdmi_cts_source_window.md`、扫档件 `build/evidence/r117/dvi_guide_scan.txt`），约束写成候选件 `src/constraints/r119_hdmi_source_window.xdc`（默认不加载，`VP_R119_TMDS_WINDOW=1` 复现），欠的是一次量名册的构建；欠账本体仍在 `debt_ledger.md` §2 追加节。

**6. `report_methodology` 警告类别计数增加了吗？**
答：**没增**：带窗那一版类仍是 3（TIMING-9/10/18），实例 `Checks found` 446→**441**，其中 `TIMING-18` 从 7→**2**（少掉的 5 条就是这 5 个第一次被检查的 RGMII 输入）。警告 盘上现在的 `build/methodology.rpt` 是**不带窗**那一版的 `446 / TIMING-18=7`，与带窗那份是两个对象，不许互相顶替。按 G4 这只当成本，带窗那一版的成本是**降**的；它同时是第二把尺子（checks 口径 2 ≠ 端口口径 6），两数永不相减。
基线 446 = 2+1+336+98+1+1+7；r115 候选滚曾出现新类 `TIMING-15 Large hold violation 5`。
那一次真绑上窗之后**并没有多出 TIMING-15**（类仍是 3，`build/r116_gates.txt` 第 18 行的 methodology CRIT 也是 0）⇒ 这条预期按实测改口，成本落在 G1 与 H5 那两条红上，不落在告警计数上。

**7. 判定器"做了多少次比较"？**
答（三个 N 各有各的行，不互相冒充）：名册差分 `judged=6 / pairs=8`（`build/evidence/r116_roster_diff.txt` 的 `ROSTERDIFF-SUMMARY`）；数字对账 `判 115 个数（首页层 61 个／解析到 10/10 行）` + `SELFSIGN-SUMMARY 判 6 条`（`node src/host/metric_recheck.mjs`；那一次跑完抄进 `build/r116_gates.txt` 第 54 行的 `判=115 首页=61`）；指路对账 `CURRENCY 6 条`（`node src/host/doc_currency_check.mjs`）。
`r115_roster_build.py --self` 5/5、`timing_roster_diff.sh --self` 11/11、`r115_round_roster.py --self` 3/3 都在 r115 跑绿；
差分层现在打印的是 `judged=6 pairs=8 result=RED`（E1 名册的 `comparisons_made=24` 由生成器打印，不写进 tsv）。**新增的尺子 `build/r115_fanout_cmp.py` 没用上**（复制驱动判负）。

**8. 每条新增门禁有能变红的测试吗？**
**没有新增门禁项**（不扩门禁，避免"门禁条数"本身变成要改口的数字）。新增的是**工具**：
`pb117_roll.tcl` + `r117_fb_pblock_fastlane.sh`（预验，不进门禁），它的判据 P1 就是防"机制没动却写成没收益"。

**9. 有几次尝试触到 H7 的 3 次上限？**
探针层面：`r115_window_true_probe.tcl` 连撞 3 次接口形状（`-min/-max` 合写、`report_timing_summary -check_timing_override`、
`read_xdc -unmerged`）+ 1 次 CJK 注释打断解析 ⇒ 第 4 次换了一支新探针（`probe2/probe3`）而不是继续改同一支，
并把四条都记进 #307/#308。**设计层面的刀没有触到 3 次**：刀 1/刀 2 各一次落刀。

**10. 有没有哪句话用了板级口吻但没上板？**
没有。这一段的新结论都是"报告/规格书/原理图"口吻；板侧判据（1000M 实流量 `bad`/`drop_words`）在 `round_r116.md` 的 V6
是**实测**（三步链 + `board_verify --geom --battery` PASS 判红步骤 0 + 147 Mbps 带流两次读数），但它仍不等于 1000M 线速——那半句写在 V6 的"两条未定"里，不许把 147 Mbps 的通过念成 1000M 的通过。`src/ps` 一个字没改（改也只能是源码级，重建 ELF 与重刷复验是两件事，见 `report/known-limitations.md` 第 2 节）。

**11. 剩余红路径的根因标签都挂上了吗？**
新增的红（实测 5 个 I/O 端点，`−0.846 / −0.870`）根因标签按附录 2 的枚举取 **`CLKTOPO`**（主项是两只钟的角间插入延迟差 3.411 ns；"I/O 标准/参考沿选错"那一维由 `IODELAY-STD` 覆盖，且它在 §6.1 里是**被排除**的候选而不是标签），
它带的是不等式（§7.5(4) 的联合条件 `0.029·C_slow + 0.063·ΔC ≤ 0.214`）而不是"未知"。
其余三域：`sys_clk` 无红；`clkout0_1` 的主导项是 22 级逻辑（功能面）；
`clk_fpga_0` **没有红**（19.76 % 绿的），但它被判"未到极限"，标签取枚举里的 **`FANOUT`**（件 `build/evidence/r117_d0/`：一根 239 引脚的网 `u_pl/u_row/hi_reg_0[0]` 吃 5.690 ns，占那条路 route 6.871 ns 的大头）。警告 这一页原先写的 `PLACEMENT_DISTANCE_NOT_AT_LIMIT` **是自造词、不在附录 2 的枚举里**（ISSUES #322 登记的就是这两个自造词），按 C 节的规矩改口；而"距离"那个解释也被 D0 的读数推翻——能动的只有复制那根广播网（C9），而 C9 在正式构建里判 **DECLINED**：本域 setup 1.850→2.104，代价是其余三域各变小（`clkout0_1` 3.630→3.353、`eth_rxc` 0.739→0.615、`sys_clk` 14.876→14.815，件 `build/r117_verdict_declined.txt`、bit `beda9298331d`）。**"绿但不是极限"和"红但是极限"必须分开说**，这是这一页审计的核心。

**12. 写下哪句"极限"其实只满足了 §7 的两条？**
`eth_rxc` 的 I/O 那 5 格：L1（逐域判定）✅、L2（杠杆全枚举并量过：数据延时/相位/带子/策略/复制）✅、
**L3（同一 DCP 反事实复现）只对刀 2 的 +0.315 成立，对"结构无解"这句还没有独立复现**
——它现在是**推导**（从两条实测直线外推出区间不相交），不是"另一把尺子量出来的同一结论"。
⇒ 这句话的强度只能写到"在 0…31 全档实测 + 分量不等式两条互相印证之下无解"，
不许写成"已证明是器件边界"。器件边界那句要等 BUFIO 的慢/快角 DCD 实测回来才能说——那支 40 秒只读探针仍未跑（`report/timing_global.md` 第 7 节、ISSUES #323）。
