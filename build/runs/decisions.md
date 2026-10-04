# 采用 / 回退决定记录（P15c）

这一份只记**决定**：谁批的、什么时候、依据哪两件东西、回退之后有没有留下可用基线。
每一轮的**数字与字段**在 `build/runs/ledger.md`；**与什么比**在 `build/runs/baselines.md（未写）`。

## 0. 批准人这一栏怎么填（先读这条，否则整份表会被念成"队伍批过"）

无人值守（P23 第 0 节）改变了"卡住时怎么办"，**没有**改变"谁有权批准不可逆动作"。所以本表只有三种取值：

| 取值 | 含义 | 判据 |
| --- | --- | --- |
| `队伍在场批准` | 有队伍原话、且有时间戳 | 只在件里能引到原话时这样写（例：r116 夜的用户两句、r93/r94 的眼睛判据、#232 的流程指令） |
| `规则预登记 + agent 执行` | **不是人的批准**：判据在起飞之前写死在链脚本/台账头部，agent 只按判据执行；凡"采用"都还要过 `build/gates.sh` 的发布门 | 每个这类决定都点名"判据写在哪个文件的哪一节、起飞前还是起飞后" |
| `【队伍未确认】` | 这件事**需要**人定、当晚没人可批 ⇒ 只做测量、不做采纳 | 例：r115 的 C2（统一不确定度）、r114 的四条跨域界、r116/r117 的输出侧 6 端口、r119 的两个候选件 |

**关键约束**：`loosen_ledger.tsv`（放宽台账）**全程 0 条**（r115/r116/r117/r118 四处独立复核）。
含义：没有任何一次"改小约束换绿灯"发生过；r116 那次想过"去掉与窗双重计的 0.800 hold 带"，
量过之后**没做**（"既然换不来绿，就不去碰 H1"），这条留在 `report/timing/loosen_ledger.tsv` 的注释里。

## 1. 决定清单（按轮次；采用 19 条 / 回退与否决 24 条 / 待定 6 条）

### 1.1 采用（进发布物）

| 轮次 | 采用什么 | 时间 | 批准人（按第 0 节口径） | 依据（两件，缺一不可） | 回滚基线留在哪 |
| --- | --- | --- | --- | --- | --- |
| r92 | `rgmii_rx.v` 删 BUFIO、5 个 IDDR 改吃 BUFG；`system_top.v` `IDELAY_VALUE` 15→26 | 2026-09-30 04:0x–06:0x | 规则预登记 + agent 执行（"功能那一侧才是这一刀唯一能判的地方"，写在 #154） | ① 结构判据：`BUFIO` 用量 1→0 + `build/hold_paths.rpt` 偏斜 1.616→0.013~0.349 ns ② 板侧判据：`drop_words=0`、100 条电池全过、`board_verify PASS（判红步骤 0）` | 板上换 r92；`build/system.bit` 进仓在 `b59db82`；正式件 md5 `883dd3b7654d`；门禁件 `build/r92_gates.txt` |
| r94 | `zoom_mapper.v`（#104 小数位）+ `zoom_ctrl.v`/`pl_video_top.v`（#93 旋转态钳进 fit）+ `eth_udp_video_top.v`（#158 显式 `FRAME_BYTES`） | 2026-09-30 12:1x–15:0x | 规则预登记 + agent 执行；**眼睛那三条待队员判**（不混进机器判据） | ① `sim/tb_zoom_frac.v` 改前红 298 → 改后 128 次逐像素 0 失配 ② `tb_v94_zoom_sel.v` T8a–T8f + 变异对照恰好红三条 | 板上换 r94（`a1465f29c9e4`）；`build/r94_gates.txt`、`build/tb_edge_rim_r94.txt` |
| r96 | `axi_frame_writer_gated.v` 排空态（#170）+ `frame_commit_lock.v` 一拍脉冲（#171） | 2026-09-30 17:07–18:5x | 规则预登记 + agent 执行 | ① 两把尺子各三段齐（before 3 红→12 绿；before 2 红→12 绿；单文件退回 HEAD ⇒ 五红）② `RESULT board_verify PASS（判红的步骤：0）` | 板上 `76d6442991e0`；`build/r96_gates.txt`、`build/evidence/r96_flash_*.txt` |
| r97 | 三口径刀（#174/#175/#176）+ 工具侧四条"归属写进凭据" | 2026-09-30 16:5x–22:15 | 规则预登记 + agent 执行 | ① 门禁抬头写三枚 12 位 md5（bit/xsa/elf）⇒ 按位流指纹找同批门禁件第一次可查 ② 板级 `uart_cmd_check 105 条 PASS` + `geom_check ok=10 fail=0`，**第一次"初态=末态"是绿的** | 板上 `ef03eea4886e`；`build/r97_gates.txt`、`build/evidence/r97_batt_recheck.txt` |
| r99 | #209（`link_active` 进 `gmii_rx_clk` 域触发器）+ #128 + #185/#186 + #188 + #201 | 2026-10-01 08:5x–10:0x | 规则预登记 + agent 执行 | ① 正/反控：r97 对 r75 的 CDC 差集为空（能绿）、r98 的差集 = `eth_rxc>clkout0_1`（能红）② r99 自己的 `cdc.rpt` 不再有那条 Critical 且 `report_cdc -details` 不再出现 CDC-10 | 板上 `b0f0914becc1`；`build/r99_gates.txt`、`build/r99_cdc_gate_proof.txt` |
| r101 | **只带 #206**（`icmp_rx` 的 `total_length - 28` 下界守卫）+ 四条注释 | 2026-10-01 14:50 | 规则预登记 + agent 执行 | ① `tb_icmp_len_wrap` 无守卫树 `nfail=3` → 加守卫 `4 PASS/0 FAIL` ② 门禁 19 绿/1 红（与 r97/r99 同档可采纳状态）+ `board_verify PASS（判红 0 步）` | 板上 `ddf972657525`；`build/r101_gates.txt`。**这一笔本身就把 r100 从"回退态"接回来了**（见 1.2） |
| r102 | #218（`icmp_rx` 的 `st_rx_data` 补两条出路） | 2026-10-01 20:1x–20:2x | 规则预登记 + agent 执行 | ① 板上 A/B：修前 `ping -l 0` 之后永久 0/4，修后 3/3 且回复"字节=0"、再 `ping -n 4` 4/4 ② 门禁 19 绿/1 红与 r101 逐字同形 | 板上 `bf11b78fe45d`；`build/r102_gates.txt` |
| r103 | #189（旋转支判小数改用完整 16 位 + 权重 `256−ceil(f·256)` + 删下游第二次翻转） | 2026-10-01 21:4x | 规则预登记 + agent 执行 | ① `tb_zoom_frac` S1/S2/S3：扫 3726 个旋转态像素命中 10 个 ⇒ 改前 S3 红、改后 0 个 ⇒ 绿 ② 门禁 19 绿/1 红 + 板上三步 JTAG token 齐 + ICMP 4/4·3/3·4/4 | 板上 `f8439575eec5`；`build/r103_gates.txt`。**新规矩从这里起**：每轮采纳把 `system.bit`/`system.xsa` 一起提交（#219 的缺口补上） |
| r104 | #141（`icmp_tx` 三处 16 位"减一后"提前寄存） | 2026-10-02 01:28 | 规则预登记 + agent 执行；**收益的成立判据在 r105（同日 09:1x）才闭合** | ① `build/r104_gates.txt` 21 绿/1 红 + 台架 141 条只红声明过的 `C5c` ② 代价可复现：两次独立构建都给 FF **+48** | 板上 `680f38f5794c`；`build/r104_gates.txt`、`build/isolated_r104_141/` |
| r106 | `udp_rx_parser.v` 的 `pay_start`/`pay_end` 提前一拍 + 14 份 eth 文件头注释清理 | 2026-10-02 14:58 | 规则预登记 + agent 执行 | ① 变异对照先证尺子有牙（尾界 `-1`→`-2` ⇒ 两支台架红 2/4 条）② 门禁**两跑逐字节相同** 22 项 21 绿/1 红 + `board_verify PASS` | 板上 `f55bd04d494d`；`build/r106_gates.txt` |
| r107 | `frame_reasm.v` 行覆盖位图拆 5 个 64 位 bank（砍 `fo=316` 的使能广播） | 2026-10-02 17:52 | 规则预登记 + agent 执行 | ① 同端点对夹逼 0.723 → **2.006 ns**、级数 5→4、最差 10 条里一条都没有 ② 逐拍等价 + 错组变异（`build/evidence/r107_rowok_bank_equiv.txt`，**动手之前**量的） | 板上 `1f90c795e7e3`；`build/r107_gates.txt` |
| r108 | `icmp_tx.v` IP 首部校验和：一拍 10 项 → 两拍各 5 项 | 2026-10-02 20:5x | 规则预登记 + agent 执行 | ① 同端点对 0.725 → **1.081 ns**（改前基线趁构建覆盖 DCP 之前问回）② 差分台架三场景逐字节全同 + 少加一项的变异**只红在校验和两格** | 板上 `25bf35a9900e`；`build/r108_gates.txt`、`build/r108_cone_verdict.txt` |
| r109 | `osd_overlay.v` 选中格提前一拍寄存（#105 那一刀的落点）+ `pl_video_top.v` 换角拍点（#167）+ `link_monitor.v` 清零优先级（#174） | 2026-10-03 02:4x（**第一轮判"不采纳"，第二轮才采纳**） | 规则预登记 + agent 执行 | ① `clkout0_1` 同族 1.130/23 级 → **4.094/21 级**（相对余量 5.65 % → 20.5 %）② C12a/b/c 三条，其中 **C12c 是阳性对照**（旧拍点必须不相等）⇒ 不用额外构建就拿到"改前红" | 板上 `21227687e925`；`build/r109_gates.txt`。**第一轮那份"没台架凭据"的现场**（`build/r109_lane_before.txt`）原样留在盘上 |
| r110 | `frame_reasm.v` 行覆盖使能独热化（刀 4①）+ `link_monitor.v`（刀 1） | 2026-10-03 07:5x（**先停在"−243 LUT 未归属"，归属之后才采纳**） | 规则预登记 + agent 执行 | ① 抓手判据：`fo=316` 那根网在本轮报告里不存在了、`rows_hit_*/CE` 作为最差终点出现 0 次 ② OOC 双腿把 −243 里的 **−66 归到刀 4①**（`build/evidence/r110_attrib.txt`），**剩下 −177 明确写"未归属"、不写进首页** | 板上 `2bf95588978f`；`build/r110_gates.txt`、`build/r110_notadopted/`（第一阶段的整套件都在，没删） |
| r112 | `key_debounce.v` 上电武装门（刀 A）+ `icmp_tx.v` 校验和累加器 32→20 位（刀 B） | 2026-10-03 09:0x–12:0x | 规则预登记 + agent 执行 | ① 两刀各自的凭据：改前红 `build/evidence/r112_key_boot_before.txt` + 发出字节流 `cmp` 全等 `build/evidence/r112_tx_bytes_{base,cut}.txt` ② 资源账**闭合到个位**：`+66−31=+35`、`+46−12=+34`（`build/evidence/r112_util_attrib.txt`） | 板上 `897fa9d93956`；`build/evidence/r112_bit/`（13 份 + MANIFEST，含该轮 `timing_summary.rpt`/`utilization.rpt`/`methodology.rpt`/`tb_v98_report.txt`） |
| r113 | `key_debounce.v` 把上电语义写进**声明初值**（#256 的修法） | 2026-10-03 14:3x | 规则预登记 + agent 执行 | ① 带 `rst_n=1'b1` 再综合的那个"1"确实进位流：`probe_init_tied_rst.tcl` 量到 FDRE INIT=1'b1 ×4 ② 名册对 r112 **八对逐位相同** ⇒ 时序中性的直接凭据（代价为零，不是收益） | 板上 `b94f4da6cdff`；`build/r113_gates.txt`（23 绿/1 红） |
| r114 | `dc_fifo.v` 四颗格雷码寄存器 `ASYNC_REG="TRUE"`（#262）+ `snap_cross.v` 的 `hb_gone` 声明初值（#257 尾） | 2026-10-03 21:3x | 规则预登记 + agent 执行 | ① **网表侧**凭据：`marked_true` 0→**56 颗**（不用 methodology 计数当凭据，#290 已证明那是错的读法）② 名册 16 对六条全绿（`build/evidence/r114_roster_diff.txt`，同生成器配对） | 板上 `7142a1fbf082`；`build/evidence/r114_bit/`（13 份 + MANIFEST）。**`ASYNC_REG` 的 +0.294 ns 头条差不记在本刀名下**（最差换了族） |
| r116（部分） | `IDELAY_VALUE` 26→**31**（实测眼心）—— **进构建并留在树里** | 2026-10-04 01:37 刷板 | 规则预登记 + agent 执行（采纳规则**写在起飞之前**的 `build/r116_batch_plan.md`） | ① 预测逐格命中：DCP 上扫出的 `HOLD(τ)=−2.822+0.0630τ` 在真构建里对到小数第三位（预测 −0.870 / 实测 −0.870）② V5 资源逐格中性 + 告警按类不增 | 板上 `bb2fb707aebc`；`build/evidence/r116_bit/`、`build/evidence/r116/`（原件 `r116_check_timing.txt`、`r116_io_{HOLD,SETUP}.rpt`） |
| r118 | **只带 `IDELAY_VALUE = 31`**（不带 C9 钩子、不带输入窗） | 2026-10-04 04:49:50 刷板、06:17 收口、08:0x E6 补签 | 规则预登记 + agent 执行；**E6 那一格由队员眼睛签**（原话「0度」，07:5x） | ① **B1 严格名册**：8 对逐格与 r114 逐位相同（`build/evidence/r118_strict_b1.txt`，末行 `losses=0 verdict=GREEN`）② **B4 发布门**：`build/r118_gates.txt` 与 `build/r118_gates_final.txt` 两跑逐字节一致、24 项 23 绿/1 红（唯一红 = 声明过的 `C5c`） | **现行基线**（见 `build/runs/baselines.md（未写）`）：`build/system.bit` md5 `cd04907e1369da35d21c4090d552f5ee`，`build/evidence/r118_bit/`，快照 commit `d420db6`；名册 `build/roster/roster_r118.tsv` |

### 1.2 回退 / 否决（**一条都没删**，含历史上被删过的那两笔，见第 2 节）

| # | 被否的东西 | 轮次 | 时间 | 决定人 | 依据（能指到件的那一句） | 回退之后留下什么 |
| --- | --- | --- | --- | --- | --- | --- |
| V0 | **Pblock 圈 `u_cdc` 回它自己那 9 块 BRAM 旁边**（第一次） | r89 | 2026-09-29 17:5x–18:2x | 规则预登记 + agent 执行（`report/log/issues.md` **#146**，在点名区间之外，只在这里列结论） | 三条：① 它瞄准的那一族本来就不在最差名单里 ⇒ **没有可归属的收益对象** ② 唯一可见的变化 `eth_rxc` +0.516→+0.363 落在实测摆幅内 ⇒ **"没有任何可主张的改变"** ③ 代价真实存在：把芯片一角写死，而新的最差路径贴着被圈的区 ⇒ **"买了风险，没买到东西"** | XDC 与构建脚本挂载**全部回退**；`build/r89_exp/` 两份报告**留在盘上作反例凭据** |
| V1 | **BRAM 换 setup**：`frame_buffer_w64.v` 拆三块（省 5 片 RAMB36） | r90 | 2026-09-29 19:5x–23:0x | 规则预登记 + agent 执行（`#149`→`#152`） | 省的是 140 片里 5 片、BRAM 哪版都没饱和（67.86 %/64.64 %）；付的是**最快那个域** setup 余量 6.5 %→2.3 %，而它同时是全设计 hold 最薄所在 ⇒ **"在不缺资源的地方省资源、在最薄的地方削余量，这笔账是反的"** | 三滚产物全在盘（`build/isolated_0929_2036/`、`_2105/`、`build/isolated_lenm1/`）；**副产物留下两条硬结论**：拿 FF 买级数划算、拿 BRAM 削 setup 不划算；回退用 md5 等式钉住（三处同为 `41384499f3a9`） |
| V2 | **实现策略换档**：`Performance_Explore` / `Performance_ExtraTimingOpt` | r91 | 2026-09-30 00:24–00:55 | 规则预登记 + agent 执行（门槛写在 `build/r91_strategy_round.sh` 头部，跑之前） | hold 三档 0.046/0.051/0.051 **一位没买到**；setup 第二档从 +0.516 花到 +0.157；两滚没有一同向好 ⇒ "换策略对 `+0.05x` 的 hold 必然无效，**placer 无权改布线树拓扑**" | `build/isolated_r91_*` 两份 `timing_summary.rpt` 在盘；**这一轮的负结果把 r92 的方向定死了** |
| V3 | **布线后 `phys_opt_design -directive AggressiveExplore`** | r95 A | 2026-09-30 13:2x–14:2x | 规则预登记 + agent 执行（门槛写在 `build/r95_timing_summary.txt` 头部 13:27:55 那一戳） | **工具自己那三行**就是结论：`WNS ≥ 0 ⇒ All physical synthesis setup optimizations will be skipped`、`Hold fix optimization will be skipped`、`No setup violation found. The netlist was not modified` ⇒ 这一档**永远不会**给已过时的本版带来收益（件 `build/isolated_r95_postroute_physopt/build_console.txt:2568` 起） | 判定 `DECLINED（结构性空转，凭工具自己那三行）`；数与基线逐位相同 ⇒ 这条问题关闭 |
| V4 | **策略 `Performance_ExploreWithHierarchy`** | r95 B | 同上 | —— | 这一档不在这颗器件的流里（`list_property_value strategy` 没有它 ⇒ `set_property` 就拒 ⇒ `BUILD_STRATEGY_REJECTED`） | **判 `NOT_MEASURED`，不写成"否决"**（把"读不到报告"写成 DECLINE 就是让"没数"长得像"结论"）；退出码 2 单独念 |
| V5 | **策略 `Performance_NetDelay_high` / `Performance_WLBlockPlacementFanoutOpt`** | r95b | 2026-09-30 15:01–15:57 | 规则预登记 + agent 执行 | 前者 +0.013（比基线低 0.54 ns，**已超出实测摆幅** ⇒ 这句至少不是"噪声里挑好看的看"）；后者与 r94 基线**一格不差**（位流却不同）⇒ 这一档对那两个靶子网络没有作用；按规矩不念成"打平"，只念"没达门槛" | `build/r95b_timing_summary.txt` + 两份隔离 `system.bit`（md5 各不相同、也都不同于正式件）⇒ "策略真的被应用了"有凭据，不是拿默认流程冒充 |
| V6 | **#141 与 #206 合在同一轮**（r100 那次） | r100 | 2026-10-01 10:57、12:52 | 规则预登记 + agent 执行 | 门禁红三项（`WNS −0.110 < 0`、`失败 setup 端点 1 != 0`、第 15 项无 RESULT 汇总行）；**红的那条不是 #141 动的那条路**（是同一个 `icmp_tx` 里的 IP 首部校验和累加）⇒ 最合理读法是"那 +48 FF 改了打包密度，把另一条本来贴着线的路推过了线" | **整轮回退**：`src/rtl` 与 `build/*.rpt|bit|xsa|tb_v98_report.txt` 一起回到记录 r99 的那笔（`3a5c7b8`），让"树 == 板上那块"重新成立；`#206` 单独走 r101 带走。**留下的读法**：#141 的正确处置是**搁置**，要重做必须连"多滚一轮看方差"一起做 |
| V7 | **`set_max_delay -datapath_only` 四条跨域界** | r114 | 2026-10-03 | 规则预登记 + agent 执行 | `report_exceptions` 表体 **A 滚 13 行 / B 滚 13 行**，`-datapath_only` 这个词出现 **0 次** ⇒ 写在 `set_clock_groups -asynchronous` 之上**不落表**，四条界一条都没生效（#276） | **不是"已补上界"**：正解是**口径决策**（要么把那一对从 group 排除里拿出来改用 per-path 界，要么承认这四条路不做 STA）⇒ 会动 WNS 的算法范围 ⇒ 必须单独一轮带尺子做。**这一条到 r119 仍未决** |
| V8 | **RGMII 真实到达窗进构建（第一版，±0.500 ns）** | r114 | 2026-10-03 16:0x–18:0x | 规则预登记 + agent 执行（"先修捕获钟，再绑约束；先去掉约束再修不是修"） | 绑到同一份 `system_top_opt.dcp` 重跑 place+route ⇒ 终态 **WNS 0.437 / WHS −2.885 / THS −14.344**，5 个失败端点全在 `u_iddr_rx_ctl/D`（件 `build/evidence/r114_io_roll_console5.txt` 的 `[Route 35-57]` 行）⇒ **加上真实窗口，收口现在就是红的，差异被"缺约束"藏住了** | 三份候选 XDC 全留在 `src/constraints/`（`r114_io_async.xdc`、`r114_io_varianta_rise_only.xdc`、`r114_io_variantb_phy_delay.xdc`）且**没被任何脚本 add_files**；变体 A（只声明上升沿）读数**逐位相同** ⇒ 沿的条数不是原因（#278）；变体 B 扫档 0/8/13 = −2.522/−2.018/−1.703 ⇒ 数据路径延迟这条路关不住 hold（#282） |
| V9 | **复制驱动 / `phys_opt_design -force_replication_on_nets`（第一次，39 根高扇出网）** | r114 | 2026-10-03 18:39 | 规则预登记 + agent 执行 | `MF-SUMMARY mech=2/2 gain=0.456 cost_red=1 lut_delta=31 verdict=DECLINE`：机制动了（`REPLICA_CELLS` 0→296、`u_pl/u_clk/u_mmcm_0` 扇出降 58）、目标族 0.445→**0.901**，但名册 D3 `big_loss=1`（`eth_rxc/hold 0.050→0.035`，相对余量 **−29.0 %**）⇒ **判负依据不是"WNS 没动"（T2 禁的口径），是名册差分看见的代价** | `build/evidence/r114_mf/verdict.txt` 两滚件留盘。**还欠一条老实话**：降扇出那根网正是"驱动类型是 LUT 但名字像钟"的三根之一 ⇒ 若重开这一刀，**得先把这三根从目标名单里剔出去再量一次**，否则连"收益来自哪里"都说不清 |
| V10 | **Pblock 圈 `u_rx_par`+`u_reasm`（第二次，三滚 B）** | r113 | 2026-10-03 11:3x–12:0x | 规则预登记 + agent 执行（A/B/C 三滚的变量写在脚本首行 `VARS`） | `REFUSE`：`Place 30-439` 说进位链半内半外，落点地板实测 `PB_CONTAIN total=1716 inside=1461`；矩形 v1 写法（`CLBLM_*`）还被工具直接拒（`[Vivado 12-28489] pblock resize has invalid range`，7 系要 `SLICE_*`） | **写清"这不等于物理这条路判死"**：要修得把共享 carry chain 的 `u_eth/u_rx_mac` 一起收进去再滚一次。件 `build/evidence/r113_roll_abc_verdict.txt`、`r113_roll_a_console.txt`、`r113_roll_scripts_diff.txt`（**A/B 单变量性靠这份 diff 逐行证明，不靠嘴说**） |
| V11 | **`set_max_fanout` 这一档**（想做复制驱动） | r113/r114 | 2026-10-03 | —— | **本工具不存在这条命令** ⇒ 复制驱动只能靠 `phys_opt_design`（#264） | 记成工具形状，不当设计结论 |
| V12 | **复制驱动（第二次，r115 的 C1，39 根 >200 扇出的网）** | r115 | 2026-10-03 23:12 | 规则预登记 + agent 执行 | 机制真的动了（`REPLICA_CELLS` 0→**310**，不是 `MECHANISM_INERT`），但 32 次比较里 **4 格红**且变差的正好是最紧的 `eth_rxc`（setup 0.092375→0.083125、hold 0.006500→0.004250）；代价 FF `8188→8463`（+275）⇒ **C1 拒绝，不进任何正式构建** | **结论写准**："不是『复制没用』，而是『在 `eth_rxc` 没有可信 hold 余量之前，复制的代价由它付』" ⇒ 顺序换成 C3 在前。同一条滚顺带证明"空白滚 == 正式构建名册"（快车道能复现正式构建的**逐域名册**） |
| V13 | **C2：把 0.800 hold 不确定度统一加严到四个域** | r115 | 2026-10-03 23:20 | **【队伍未确认】（无人可批）⇒ 只测不采纳** | BEFORE 只有 `eth_rxc value=0.800`，其余三域 `value=NA`（报告有、路径有、就是没有那一行）；AFTER 四域全 0.800 ⇒ **WHS −0.747、THS 失败端点 25742**，且 `−0.747 = 0.053 − 0.800` 与 `clk_fpga_0` 现行读数逐位对上 ⇒ **不是新出现的物理问题，是同一批路径换了尺子之后的读数** | 只读探针（约束只活在会话里，不写 XDC、不回写 DCP）；件 `build/evidence/r115_uncertainty_hold_console.txt`、`report/timing/uncertainty_hold_ab.md`。**这条 measurement 的价值**：#265 那条"名册那四个 WHS 不是同一把尺"第一次被量出来 |
| V14 | **C3：MMCM 负相移提前捕获沿（`CLKOUT0_PHASE = −225°`）** | r115 | 2026-10-04 00:01（副本树 `c2_scratch_1003`） | 规则预登记 + agent 执行（判据 S1..S4 预登记在 `report/timing/rgmii_window_model.md` §4） | S1 RED：终态 `WNS 0.954 / WHS −2.126 / THS −10.552 / 5 个 hold 失败端点` ⇒ **窗没关住，只买到 +0.759 ns**。**更要紧的那半条**：那 0.759 里约 **0.67 ns 是"约束作用范围被削弱"换来的**（终点已是派生钟 `mmcm_clk0`，那条路的 `Clock Uncertainty` 从 `0.835 … + UU` 变成 `0.166`，**UU 项消失了**）⇒ **没写任何放松约束的命令，它自己发生了** | `rejected-measured` 写进 `report/timing/cut_ledger.tsv` C3 行；副本树件全在。**本轮最值钱的产出**：新规矩"只要新建/改名一只钟，所有点名旧钟的约束都要重查覆盖面（`set_clock_uncertainty`、`set_clock_groups`、`set_input_delay -clock`、IDELAY/参考钟关系）" |
| V15 | **"再挪一点相"这条路由算术关死**（不是刀，是路线） | r115 | 2026-10-04 00:12 | 只读探针（两块 DCP 同一把尺子） | 真窗下主树实测 `hold −1.385 / setup −0.186`，报告自己的 `Clock Path Skew`：**主树 5.008 vs 副本树 5.919** ⇒ MMCM 那一刀把捕获沿**推迟了 0.911 ns**，`−225°` 的相位提前被 MMCM+BUFG 自己的网络延迟吃掉还有余 ⇒ **它连主树都没追上**（hold −1.426 vs −1.385） | 件 `build/evidence/r115_c2_scratch/option_a_main_console.txt`。警告：**公开改口两处**：① 00:13 那句"hold+setup 守恒"是**算式写错**，00:17 撤回（`dfc44df`）② 窗模型自身仍有 `TskewR` 混行的残余风险 ⇒ 这两个数只代表"该窗模型下的读数"，**不代表板上真实差额** |
| V16 | **tap 扫描想"少给几拍延迟"这条路** | r115 | 2026-10-03 17:29 | 规则预登记 + agent 执行 | 0/13/26/31 四档 WHS = **−4.522 / −3.703 / −2.885 / −2.570**（斜率 ≈ 63 ps/tap）⇒ 到最大档仍差 −2.57 ⇒ **超量程**，其余三域逐档不动 ⇒ 红的全部在 `eth_rxc` 的片外窗方向 | `build/evidence/r114_sweepb_console.txt`；判据脚本三条对照实测 0/1/1（**尺子自己先要有能红的牙**） |
| V17 | **IDDR 捕获钟改吃 BUFG 之后"报告看不见采样窗"这个前提** | r115 | 2026-10-03 18:09 | 只读 + 只改注释 | **#194/#57 当年搬进 BUFG 的前提（"`src/constraints/` 里没有任何 `set_input_delay`"）今天不再成立** ⇒ 那把刀的判断要重开（156 ps/tap / 88 ps/tap / 63 ps/tap 三个互不一致的数也登记为"按拍数推采样点前必须先量清"） | 只改注释（去掉 `//` 行后与 HEAD 逐字符相等已证）；`src/rtl/eth/rgmii_rx.v` 头注 |
| V18 | **RGMII 输入窗进构建（第二版，min 1.200 / max 2.800，正确取行之后）** | r116→r117 | 2026-10-04 02:5x–03:5x | 规则预登记 + agent 执行（采纳规则写在 `build/r116_batch_plan.md`） | r116 绑上之后，那 5 个**第一次被检查**的端点把发布门的 **4 条硬项**判红（WNS −0.846 / 失败 setup 5 / WHS −0.870 / 失败 hold 5，件 `build/r116_gates.txt` 第 10–13 行）；仓库自己的门禁结论是"有红项 ⇒ 不采纳，保留上一版" | **约束不删、证明不删、构建默认不加载**：`src/constraints/r116_rgmii_input_window.xdc` 原件在仓里，`VP_R116_IO_WINDOW=1` 一条命令复现带窗那一版（理由写在 `build/tcl/build_system_axigpio.tcl` 的约束加载处）。警告：**代价一起念**：撤窗之后那 5 个端点回到"没检查"状态（`check_timing` 的 `no_input_delay` 从 0 **回到 5**，这是撤窗的诚实读数，不藏）；**相对 r114 这不是放宽**（r114 从来没有这条约束，松动台账仍 0 条） |
| V19 | **C9：强制复制那根 239 引脚广播网 `u_pl/u_row/hi_reg_0[0]`** | r117 | 2026-10-04 04:16 | 规则预登记 + agent 执行（A1..A5 写在 `build/r117b_chain.sh` 头部，起飞前） | 机制成立（`pins_before=239 → pins_after=1`、`replica_cells=10`，**两处独立出水口都读到**）、`clk_fpga_0` 1.850→**2.104** 是赢；但 `clkout0_1` 3.630→3.353、`eth_rxc` 0.739→0.615、`eth_rxc` hold 0.052→0.044、`sys_clk` 14.876→14.815 **四格一起跌** ⇒ 预登记的严格判据 A2/A3 不过 ⇒ **按 H7 回滚这一处切割** | **结论不是"这刀没生效"**：生效了，代价落在最紧的两个域上（与 r114/r115 那两次复制刀**同一个形状**，`cut_ledger.tsv` 的 C1 与 C9 两行都写着 `declined`）。钩子原件留在 `build/tcl/r117_post_place_hook.tcl`，设 `IMPL_POST_PLACE_HOOK` 即可复现那一版（位流 `beda9298331d`）。**这一刀用掉了 3 次尝试里的 3 次**（#319/#320/#327 都是工具账不是设计账） |
| V20 | **`timing_roster_diff.sh` 的 D3 那把 25 % 门槛尺**（不是被否的设计，是被否的**判据口径**） | r117 | 2026-10-04 04:17 | agent 决定：**谁都不改宽** | 同一份 r117 数据，D3 判 `result=GREEN`、G1/预登记 A2A3 判 RED ⇒ 两把尺子对同一份数据给不同判语 = **口径债** | **没有去改 `timing_roster_diff.sh` 的 25 % 门槛**（那是别人在用的粗筛，改了就是把两轮的历史判语也改了），而是把严格判据落成**独立、可指路的件**（`build/evidence/r118_strict_b1.txt` 那种形状，链子里 B1 判的就是它，不是 D3）。补硬的规矩：**差分件念出来时必须同时念"比较了几对 / 其中几对在跌"，只念 `result=GREEN` 不算把差分念完**（#328） |
| V21 | **HDMI 源端 `set_output_delay` 互对窗**（`±0.20 Tcharacter = 4.000 ns`） | r119 | 2026-10-04 09:1x–09:4x | **【队伍未确认】→ 默认不加载**；本条要人定的两件事见第 3 节 | 两版都真的挂上了（`Path Group` 从 `(none)` 变成有钟），但给出 `−3.482/−3.458/−3.474 ns`（互对窗，件 `build/evidence/r119_xdc_loads_probe3.txt`）与 `−4.897/−4.873/−4.890 ns`（打在钟脚上，件 `_probe4_pinclk.txt`）。**规范那一行是 skew（两脚到达时刻之差的上限，单边离散量），`set_output_delay` 是采样窗 ⇒ 两者不同量纲** ⇒ **这条是"量纲用错"，不是"设计不合格"**（#335；`report/io/hdmi_tp1_sdc_measurement.md` §三） | **不许靠放宽窗把它变绿**；换同量纲问法（成品逐脚量 clock-to-pin `Data Path Delay`）之后：互对最差 **0.065 ns**（上限 4.000）、对内最差 **0.001 ns**（上限 0.300），判 10 项红 0（`build/evidence/r119_window_check.txt`，`--self` 十条畸形各自动红）。两件候选件**默认不加载**，保留的意义是"这一族规范量不能这样进 SDC"的**反例凭据**；处置（保留/删除）需队伍裁决 |
| V22 | **`report_methodology` 的 TIMING-10 计数当 `ASYNC_REG` 落地凭据**（读法被数据判错） | r114 | 2026-10-03 19:05 | agent 自我更正 | `ASYNC_REG` 上了网表（0→56 颗）**但 TIMING-10 计数一点没动**（仍 = 1）⇒ 预先登记的这条判据**被数据判错**：属性有没有落地不能拿 methodology 的计数当凭据（它数的是"检查项"，不是"我的属性"） | durable 的尺子换成 `report_cdc -details` 点名到具体那对触发器；警告：仓库里 9 月那份 `build/cdc_details.rpt` 是**过期件，不许引用**（#290）。剩下的那一处 TIMING-10 **没有被识别** ⇒ 这是本轮一条"未知对象"债务，G12 要求它列进下一轮候选，**不许"未知原因但绿了"** |
| V23 | **"同一条路在两次构建之间摆 0.4 ns（放置抖动）"这句被当成同树噪声底用** | r105 | 2026-10-02 09:1x（09:3x 收回一半、09:4x 结案） | agent 公开改口 | 那句把**跨变体**的散布当成**同树重复滚**的噪声底用了；同树重复滚的底今天量到是 **0.000**（两对 + 第三样本）⇒ 数不动、**用法错** | 改口写进 `report/known_issues.md` 与本台账第 2 节；**09:3x 那次收回一半**："0.4 ns 到底是不是同树的散布，两处实测互相冲突，我没资格替它结案" ⇒ 到 #223 才结案（不用重跑构建，是查清那两跑**既不同树也不同路**） |
| V24 | **一次"顺手修掉不是缺陷的东西"的尝试**（r102 前） | r102 预备段 | 2026-10-01 19:2x | agent 自我否决 | 顺着 `rec_byte_num = 0` 追到发侧，差点"顺手修"掉一个**不是缺陷**的东西 ⇒ 按"推不出修法就不要动那一行"停在只读 | 记进 `report/log/issues.md` 当日段；这条的价值是**它没进构建** |

### 1.3 待定（结果更差或原因不明，按停止条件记"待定 + 假设与判别方法"）

| # | 事项 | 轮次 | 为什么待定（不改判据、不换口径） | 判别方法（已写好，等下一轮或等人） |
| --- | --- | --- | --- | --- |
| P1 | `clk_fpga_0` 那一格（名册上唯一"明知未到极限"的域） | r116→r118 | 对症那把刀（C9 复制广播网）**量到赢但被名册判负** ⇒ 不能为了抬它去牺牲最紧两格 | `build/evidence/r117_d0/`（route 6.871 ns / 其中 5.690 ns 在这一根网上、负载铺 99 个 tile）；下一把只能是**架构级**或队伍批准的口径决定 |
| P2 | 异步组外四条跨域路要不要给界（`set_bus_skew` / per-path `set_max_delay`） | r114→至今 | 收窄排除策略**会改变 WNS 的计算对象** = 松动；当晚无人可批 | 单独一轮，判据用现成的名册差分 D1..D6 盯"别的域有没有被挤"（#266/#276） |
| P3 | 输出侧 6 个端口（`led[0..1]`、`tmds_*`）的债 | r113→r119 | 要么给可引用的窗口数，要么批准"不检查"（=放宽，进松动台账）。本机与在线都查过，**没有可引用的一页**（`build/evidence/r117/dvi_guide_scan.txt` + `report/io/hdmi_cts_source_window.md`） | r119 已把方向纠正成**源端 TP1**，并给出同量纲的离散量判据；仍欠"一次构建量名册"（四域逐格对照 r118）+ 板级走线未量 + 眼图/抖动/占空比未量（**SDC 里没有容器**） |
| P4 | τ=31 到底是"报告最好"还是"硅片最好" | r116 | 工具的 I/O 两检查取混合角（hold 慢钟/setup 快钟），真实芯片只活在一个角；**这颗片的 C 没测过** | 把 5 颗 `IDELAYE2` 从 `FIXED` 换成 `VAR_LOAD` + 串口逐档加载 + 1000M 实流量看计数（`bad>0` 即回 26）；#314 的三条纪律已写死 |
| P5 | 换短捕获钟那一刀（唯一能把 `eth_rxc` 从红做绿的路线） | r115→至今 | 动手前欠一个 40 秒只读实测：**BUFIO 的快/慢角 DCD**；本机 UG471/UG472 两遍扫描都没筛出可引用的插入延迟 ⇒ 0.5/0.2 ns 仍标**假设**（#323） | 判据 `C_slow − C_fast ≤ ~1.2 ns`（现在 BUFG 是 3.411）；若实测角间差仍 >1.7 ns，那句话就不是"换树"而是"这一代器件的 I/O 钟树对 8 ns 周期 + 1.6 ns 外部散布就是不给解"——**那句也得有件才能写** |
| P6 | r119 两个 `.xdc` 候选件的处置（保留 vs 删除） | r119 | 保留就必须带着"已知会造违例、只作反例凭据"这句话，否则下一个人会当真挂上去；删除是**不可逆动作**，无人值守不许做 | 已进 `report/questions-for-team.md` 的合并范围（`report/io/hdmi_tp1_sdc_measurement.md` §六 D2） |

## 2. 关于"回退轮不许删"：历史上被删过的，如实说

| 事件 | 实情 | 件 |
| --- | --- | --- |
| **r100 的位流与报告被回退掉**（不是删除记录） | 这是**回退**不是删档：`src/rtl` 与 `build/*.rpt|bit|xsa|tb_v98_report.txt` 一起 `git checkout` 回记录 r99 的那笔；**这一轮的负结果全文留在 ISSUES 里**（10:57 与 12:52 两节），链控制台也留着（`build/r100_chain_console.txt`） | `report/log/issues.md`；`build/r100_gates.txt`（红的那份**没删**，就是判否的凭据） |
| **r110 第一阶段那套"未采纳"件**被整批挪到 `build/r110_notadopted/` 而不是删 | 处置写得很清楚：一提交 `metric` 就会在 HEAD 上判红（自指陷阱），所以"位流/报告留在工作树里不提交" ⇒ 用**目录改名**保留，没有删除 | `build/r110_notadopted/` |
| **一次真实的删除**：仓库外/仓库内的历史清理 | `git log` 实读过两笔：`cbe697c`（#66 A 类清理：六个一次性收尾脚本 + V7 时代的 3.9 MB bit + 未入库的探针目录删掉）与 `d49a0bc`（撤出两条不该入库的留档：r87 草稿报告、串口原始字节捕获，并写进 `.gitignore`）。**这两笔删的是"未入库/不该入库"的件，不是任何一轮的回退记录** | `git log --diff-filter=D`；`report/log/issues.md` #241（讲清了"仓库外并存两个提交目录"的风险） |
| **r95 那次误启动**（`falsestart`） | 两份 `build/r95_timing_summary_falsestart.txt`、`build/r95_timing_round_falsestart.log` **原样留盘**：那一拨 bash 切词把两滚并成一滚、策略名拼成非法串 ⇒ "根本没量到"的形状也有件 | 见文件名 |
| **本轮把 ISSUES 写坏过一次** | #255 附注：用编辑工具追加时锚行选长、替换文本选短 ⇒ **删掉了 #254 第 3① 条的开头**；复原后按行号可验、`doc_enc_check` 386 个文件全干净。**这类"自己删了台账"的事故记在这里，不靠"我记得没删"抵充** | `report/log/issues.md` #255 末段 |

## 3. 待办与"应进 `report/90-open-items.md`"的清单（该件目前**不存在**，由 P18c 落地）

P15c 质量判据 4 要求"采用的轮次取不到产物就标『产物未固化』并进 `report/90-open-items.md`"。
`report/90-open-items.md` 现在盘上**没有**（`report/run-queue.md` 里 P18c = 待开），**不代写别人的件**，
先把清单钉在这一节，等 P18c 落地时按行搬过去。全部条目都做过 `test -f`（命令与输出见 `build/runs/ledger.md` 第 5.2 节）。

| # | 待办 | 类型 | 现场 |
| --- | --- | --- | --- |
| O1 | **r90 / r91 / r95 三轮回退轮的位流未固化**：`build/isolated_*/system.bit` 在盘上但 `.gitignore` 挡位流 ⇒ 不在 git；对应报告在盘 | 产物未固化（回退轮） | `ls build/isolated_0929_2105/system.bit` 等（盘上件在，`git ls-files` 为空） |
| O2 | **r92 / r94 / r96 / r97 / r99 / r101 / r102 / r103 / r106 / r107 / r108 / r109 / r110 十三轮"采用轮无该轮位流快照目录"**：`build/evidence/rNN_bit/` 从 **r112 才开始**存在。更早的采纳笔只有"当轮把 `build/system.bit` 提交进 git"这一条路（r103 起立规矩，`r103` 的 bit/xsa 在 `54346ae`；r99 在 `3a5c7b8`；r92 在 `b59db82`；r94/r96/r97 同） | 产物未固化（部分） | `git log --format=%h -- build/system.bit` 实读（见 ledger 第 5.2 节命令） |
| O3 | **r116 的原件报告未成套**：`build/evidence/r116_bit/` 只有 `system.bit` + `system.xsa`，没有该轮 `timing_summary.rpt` / `utilization.rpt` 副本；报告只在 `build/evidence/r116/` 那三份 + 后来被 r118 覆盖的 `build/*.rpt` | 产物未固化 | `test -d build/evidence/r116_bit` = OK（2 件）；`build/evidence/r116/` = 4 件 |
| O4 | **r117 判负轮的位流未固化**：`build/evidence/r117_bit_md5.txt` 只有 13 字节文本（`beda9298331d`），**没有 `r117_bit/` 目录** | 产物未固化（回退轮） | `test -d build/evidence/r117_bit` = MISS |
| O5 | **`data/metrics.csv` 的门禁项数仍是 22，与 `build/r118_gates.txt` 的"判定 24 项"不一致** | 台账数字带动文档（P15c 铁律 7） | 见 `build/runs/ledger.md` 第 4 节 **D1**（不改 `data/`，这是禁区） |
| O6 | **`report/timing/roster_round116.tsv` 的第一行标题写的是"r115 轮名册"而文件名是 round116** | 口径/命名不一致 | 见 **D3** 末句 |
| O7 | **`report/90-open-items.md` 不存在** ⇒ 上面 O1–O6 目前只能钉在本节 | 交付缺口（P18c） | `ls report/90-open-items.md` = 不存在 |
| O8 | **r119 的两个候选 XDC 处置**（保留 vs 删除）需要队伍一句话；保留就要在件里带"默认不加载 + 已知会造违例" | 需人定 | `report/io/hdmi_tp1_sdc_measurement.md` §六 D2 |
| O9 | **一次构建量名册**（把 r119 的同量纲窗判据带进构建，四域逐格对照 r118） | 需构建（本轮禁区不跑） | `report/timing/debt_ledger.md` §2 追加之二 |
| O10 | **E6 的对照那一半仍未做**（按住 KEY1 到链跑完应读 1，需要再断一次电） | 需人/需硬件 | `board/acceptance.md` E6 格、`build/evidence/r118_eyes/state.txt` |
| O11 | **`build/provenance.md` 记下的一处真实缺口**：今天这份入口脚本 `build/tcl/build_system_axigpio.tcl` 的字节数与内容**在 r118 之后改过**（加了 `VP_R119_TMDS_WINDOW` 那一档）⇒ **当前脚本 ≠ 生出 r118 那份脚本**，默认路径虽逐字等价，复现 r118 时这条要写出来 | 来源卡缺口（P15a 已登记，不重复处理） | `build/provenance.md` 第 65–67、102 行 |

## 4. 计数（分母）

- 采用（进发布物）：**19 条**（第 1.1 节，含 r116 的部分采用）
- 回退 / 否决：**24 条**（第 1.2 节 V0–V24，去掉重复计的一条 V11 是工具形状 ⇒ 实际刀/路线级 24 行）
- 待定：**6 条**（第 1.3 节 P1–P6）
- 待办：**11 条**（第 3 节 O1–O11）
- 放宽台账（`report/timing/loosen_ledger.tsv`）数据行：**0 条**（r115/r116/r117/r118 四处独立复核，末次实跑 `awk '!/^#/ && NF>1'` = 0 行）
