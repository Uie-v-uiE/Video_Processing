# 附录 3 — 交付前 12 问自检（逐条有答案，没有一条留空）

本轮 = r115（2026-10-03 夜，快车道 D1；没有正式构建、没有上板、没有采纳）。

**1. 有没有任何一个域的 rel_margin 变小了？（差值列在哪）**
有，4 格，全在**被拒绝的那把刀**（C1 复制驱动）身上：差值列在 `docs/timing/roster_round115.tsv` 的
`rel_margin_setup_delta / rel_margin_hold_delta`，红行是 `eth_rxc`(setup 与 hold)、`sys_clk`(setup)、`clk_fpga_0`(hold)。
**当前采用状态（= r114 那一版）没有任何域变差**：本轮没动 `src/`，树 fp 逐位不变（`rtl=3969247aaf7f`）。

**2. 本轮的 WNS 变化，D1 反事实跑了几次？噪声底是多少？**
反事实共 **4 滚**：噪声标定 2 滚（22:31→22:43）+ 本刀 A/B 2 滚（22:54→23:07），一滚 6.4–7.5 分钟。
噪声底 **noise_ns = 0.000**（件 `/tmp/kx/r115_noise/noise.txt`：头条四数逐位相等 **且** 最差路径身份相等才算 0）。
所以 G1 那 4 格红**严格大于噪声**，不是骰子。

**3. 我引用的每个数字，紧跟的是哪个工件、指纹对不对？**
判定表逐格带件路径（`docs/timing/gates_G1_G12.md`）；基线 22 份报告的 md5 与 producing command 在
`docs/timing/baseline_INDEX.md`。**一处不自对**：`build/evidence/r115_base/check_timing.txt` 文件名与内容不符
（里面是 `report_timing`），已按 ⚠ 行写明，本轮 I/O 债的读数一律只取 `check_timing_verbose.txt`（ISSUES #299）。
设计指纹在每次起跑**前**取（H4）：`fpver=norm1 files=80 top=56c269602e18 rtl=3969247aaf7f`，`dcp md5=4c895816c4f2`。

**4. 松动台账是不是空的？不空的话每条的非时序证据是什么？**
空的（`docs/timing/loosen_ledger.tsv` 数据行 0）。夜里没有批准人，按 H1/G3 一条都不松。
两处"看起来该放松但没放松"（eth_rxc 的 hold 不确定度 0.800 没调小；RGMII ±0.5 ns 输入窗没绑进工程）写在台账注释里，
**并给的是反向证据**：绑上真窗之后实测 WHS −2.885 / THS −14.344（件 `build/evidence/r114_io_roll_console5.txt` 的 `[Route 35-57]`）——
方向是"先修捕获钟再绑约束"，不是"去掉约束让它绿"。

**5. `unconstrained_endpoints` 和 `io_unconstrained_ports` 现在是多少？**
0 与 **11**（输入 5：`eth_rx_ctl`、`eth_rxd[0..3]`；输出 6：`led[0]`、`led[1]`、`tmds_clk_p`、`tmds_data_p[0..2]`）。
⇒ **按 H5 本轮直接判红**：这两个数不为 0 时 WNS 数字无意义。这一格是本轮最重要的一条诚实记录——
它把"设计所有域都绿"这件事从结论降级成了"未被约束覆盖"。

**6. `report_methodology` 警告类别计数相比基线增加了吗？增加算成本还是收益？**
本轮**没测**（快车道滚的报告清单里还没有 methodology，见 gates 表 G4 行）——写"未测"，不写绿。
基线的数是 `Checks found: 446 = 2+1+336+98+1+1+7`（SUMMARY 表，七项相加闭合）。
按今天的口径：**警告类别数算成本**，不当收益（规矩 35 的延伸）。

**7. 我的判定器"做了多少次比较"？这个数字在哪一行打印的？**
四个打印点：名册差分 `ROSTERDIFF-SUMMARY comparisons_made=32`（= 8 域 × 4 列）；
轮名册 `ROUND rows=8 comparisons_made=24 both_NA=8 single_NA=0 reds=4`；
扇出自比 `cmp=60 lower=0 equal=60`；噪声标定 N1–N4 四行 + N5 一行 INFO。
没有一个计数器按"通过"计数（G9；上一轮就为这条改过 `judged++` 的形状）。

**8. 每条新增门禁，有没有它自己能变红的测试？**
有，而且**今天每一条都真的红过一次**：`r115_roster_build.py --self` 5 条（both_NA 常量假红把它逼成"由夹具算期望"）；
`r115_round_roster.py --self` 3 条；`r115_fanout_cmp.py --self` 4 条（列索引错时 2 条当场 FAIL）；
驱动脚本的 F1/F6 因为形状猜错判过假红（`^ROLLDONE` 锚点、route_status 里根本没有 "successful"），已按实测形状改对。

**9. 有几次尝试触到了 H7 的 3 次上限？回滚了吗？回滚先只读跑过吗？**
没有一把刀用满 3 次。C1 是**第 1 次**就被名册判负 ⇒ 直接拒绝，没重试（也不换口径重试）。
本轮没有需要回滚的源改动（`src/` 一字未动）；被"回滚"的是两把**文档/脚本**层的错尺子，
回滚能力先只读验过：`bash -n` + 各 `--self` + 用现成滚重跑 `--analyze`（不重烧 GPU）确认它们回到能判的形状。

**10. 有没有哪句话我用了板级口吻但实际没上板？**
没有。本轮全部是网表/报告层读数，文档里凡涉及行为一律不带"板上验证过"的口气；
`src/ps` 一字未动（本机无 `arm-none-eabi-gcc`，改了也只能是 source-only，H6）。
唯一与板有关的现况陈述仍是 r114 那条（bit `7142a1fbf082`、board_verify 21:34 PASS），本轮**没有**新刷板。
还欠着的眼睛判据：`board/ACCEPTANCE.md` E6 在 r114 上标"待重判"。

**11. 剩余红路径的根因标签是不是每个都挂上了？有没有"未知原因但绿了"？**
本轮红项两类都挂了标签：G1 的 4 格 = `FANOUT`（C1 自身的代价，刀已拒）；H5 的 11 端口 = `UNCONSTRAINED`（C4）。
有一条**对象未明**的挂在债务里而不是绿灯里：`TIMING-10` 还剩 1 条"Missing property on synchronizer"，
它**不是**格雷码链（`ASYNC_REG` 落地 0→56 颗之后该计数一点没动，ISSUES #290）——标签 `ASYNC`，进下一轮候选。
"未知原因但绿了"：没有；但有一条"未测却容易被当绿"的（G4 methodology），我在表里明写未测。

**12. 我这轮写下的"极限/完成/无风险"里，哪一句其实只满足了 §7 的两条？**
我**没有**写"到极限"。本轮真实的一句话是：**收敛 0 ns（没有任何切割被采纳），未证明到极限**。
离 §7 差什么：L2 要"至少 3 条互相独立的候选被 D1 实测收益 < noise_ns"——本轮只新增 1 条（C1，且是判负不是判平）；
L1 的分段占比我手里有分解读数（最差的 eth_rxc 那族 route 占 58 %、级数 11，件 `build/evidence/r115_base/timing_summary.txt`
与 `da_levels.txt`），但没按 §7 要求把"四段占比 + 不可再压"论证完；L3 因为本轮什么都不采纳而自动成立。
三条不齐 ⇒ 不许用那个词。

（L1 那半句的分段读数是 `Data Path Delay: 7.066ns (logic 2.936ns 41.553% route 4.130ns 58.447%)` 与
`Logic Levels: 11 (CARRY4=6 …)`，出自件 `build/evidence/r115_base/check_timing.txt` 的第一条路径
——⚠ 那份文件**实为 `report_timing`**（见 debt_ledger §6 与 ISSUES #299），所以这里点名它时按"内容"而不是按"文件名口径"引用；
级数分布另有 `build/evidence/r115_base/da_levels.txt`。）
