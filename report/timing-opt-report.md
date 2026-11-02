# 时序优化报告（TIMING_OPT_REPORT）

- 工作区：`D:\Xilinx\Harness\Project\timing`（冻结 FIN 包的逐文件副本，tree md5 链 `a129dd69b3a439e0030c2a2598fc6dd3`，3551 文件）
- git：`main` = `0cc5cd0`（baseline tag `7dfd470` + **方案二 合入**）；实验分支：`c1-eth-rst-async-reg`（方案一，拒绝）、`c2-lm-reset-replication`（方案二，接受）、`c1c2-stack`（组合，拒绝）——全部保留作审计记录
- 工具：Vivado 2025.2.1（SW Build 6403652）；ModelSim SE 2020.4（交付回归历史同款工具）
- 冻结确认：RAR、GitHub、学习/演示文档未触碰；任务期间原 `D:\Xilinx\Prj\FIN` 被外部移动（Prj 目录整体消失，非本任务操作），其逐文件快照锚定于 `baseline` tag；本工作区为唯一写入点
- 结论：**方案二 被接受**（全局 WNS 1.341 → 1.368，WHS 0.025 → 0.048，零行为变化，边际但确定性改善 + 复位分发树结构性去单点）；方案一 与 方案一+方案二 组合被数据拒绝。基线本身健康：0 failing endpoints、全时钟域余量为正。

---

## 1 Baseline 复测 vs Final

Baseline 于 2026-10-31 21:37 用仓库构建入口 `build/build.tcl`（默认策略 `Vivado Implementation Defaults`，与 交付基线 同）复测，**与 交付基线 交付报告逐位一致**，同时确认了实现的确定性（同版本/同策略/同 RTL → 同结果），使后续对照实验干净。

Final = **方案二 版**（`main` @ `0cc5cd0`，构建产物 `submission/c2_timing/`）。

| 指标 | 交付基线（历史交付） | baseline 复测 | 方案一 单独 | 方案二 单独（**Final**） | 方案一+方案二 组合 | 裁定 |
|---|---|---|---|---|---|---|
| WNS / TNS / failing | 1.341 / 0 / 0（56043 ep） | 1.341 / 0 / 0（同） | 1.277 | **1.368** / 0 / 0（56047 ep） | 1.139 | 方案一 退化拒；方案二 改善收；组合退化拒 |
| WHS / THS | 0.025 / 0 | 0.025 / 0 | 0.051 | **0.048** / 0 | 0.048 | 方案二 改善收 |
| 逐时钟 setup（sys/pix/eth_rxc/axi/eth125） | 14.797 / 3.264 / 3.247 / 2.159 / 1.727 | 同左 | 14.901 / 4.123 / 2.705 / 1.284 / 1.611 | 15.016 / 3.406 / 3.222 / 1.451 / 1.576 | 15.016 / 3.406 / 3.222 / 1.451 / 1.576 | 重排有涨有跌，全正 |
| 逐时钟 hold | 0.067 / 0.025 / 0.071 / 0.060 / 0.068 | 同左 | 0.130 / 0.051 / 0.068 / 0.056 / 0.070 | 0.092 / 0.061 / 0.076 / 0.048 / 0.074 | 同 方案二 | 全正且较 baseline 改善 |
| clkout3 组 recovery（rst 系） | 1.658 | 1.658 | （组 1.594@sys→eth） | **1.488** | 1.139 | 方案二 拆树生效 |
| LUT / FF | 14967 / 9095 | 同左 | 14960 / 9096 | 14965 / 9097 | — | 预算内 |
| BRAM / DSP | 98 / 19 | 同左 | 98 / 19 | 98 / 19 | — | 不变 |
| 功耗（估算，confidence low） | 2.406 W / Tj 52.8 °C | 同左 | 2.410 W | 2.407 W / Tj 52.8 °C | — | 平 |
| width_warnings / multi_driven / methodology critical | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 干净 |
| 15 拍效果链延迟 | 常数 | 不变 | 不变 | 不变 | 不变 | 零变化 |

确定性提醒：四列都是各自 RTL 的确定性结果（同策略同流程）；跨 RTL 的 ±0.03 ns 量级差异是布线重排的真实读数，不是同 RTL 重跑噪声。

## 2 时序体检（审计结论）

全设计最差路径全部落在两类：**复位恢复检查（async_default 组）** 与 **布线主导（route ≥ 84%）的数据路径**。

| # | Slack | 组 / 检查 | 路径 | 根因 |
|---|---|---|---|---|
| 1 | 1.341（全局 WNS） | sys_clk→clkout3 recovery，6 ep | `phy_rst_cnt_reg[23] → LUT2(eth_rst_n & mmcm_locked) → rst_lm_sync2/CLR` | 相关钟最紧沿差 4 ns；组合 AND 1 级 + route 1.443 ns；跨 MMCM PE 0.165 计入 uncertainty |
| 2 | 1.658 | clkout3→clkout3 recovery | `rst_lm_sync2 → LUT1 → 539×FDCE/CLR`（u_lm 复位分发树） | 单 LUT 扇出 539，route 4.866 ns |
| 3 | 1.727 | clkout3 setup | `u_rx_par/p_data → u_reasm/rows_hit` | 5 级逻辑，route 84%（5.03 ns） |
| 4 | 2.159 | clk_fpga_0 setup | `owner_eth_r_rep__2 → u_bilin/u_fb lo_reg/ADDRARDADDR` | route 93%（6.68 ns），跨半 die |
| 5 | 0.025（全局 WHS） | clkout0_1 hold | `u_blur/dout_reg[15] → u_sharp/q22_reg[15]` | data 0.428 ns，clock skew 0.346 ns（两模块相距 ~16 SLICE 列） |

约束与 CDC 审计：0 unconstrained internal endpoints、0 loops、0 no_clock；异步时钟组（impl 期）、处理窗准静态总线 `set_max_delay -datapath_only 10 ns` 三条、RGMII 发侧 ODDR0 ±0.5 ns 窗均与报告一致。CDC 报告 3 条 Unsafe 已用 `report_cdc -details` 逐条定性（`timing_opt/reports/cdc_details.rpt`，routed checkpoint=c1_timing 构建，其 CDC 汇总与 baseline 一致）：2 条 = `pv_tog → ts/hs 同步器第一级`（CDC-11，Depth 2，被 max_delay -datapath_only 覆盖的准静态快照 by-design 结构）；1 条 = `eth_rst_async → rst_rx_sync_reg[0]`（异步复位线进 3 级 ASYNC_REG 同步器，by-design 的 async-assert 线）——**全部为设计意图的预期形态，无真实 CDC 缺陷**。附带发现：`key1_n/key2_n` 按键同步器缺 ASYNC_REG 属性（CDC-2 Warning，2 级同步 + False Path 已覆盖功能，基线固有，仅记录）。时钟名册与逐域检查另见 `timing_opt/reports/clocks.rpt`。

Critical warning 对比（"无新增"门）：routed methodology 三版均为 **0 critical**，且 baseline（453 warnings）与 交付基线 交付（453）逐量一致，方案一 为 451；构建期 BD 41-1348 ×11 为块设计生成期固有警告（PS7 FCLK_RESET0_N 接 GPIO 复位，三次构建同源）。

## 3 候选裁定（accepted / rejected）

| 候选 | 改动 | 实测 | 裁定 | 原因 |
|---|---|---|---|---|
| **方案二 rst_lm 分发树拆分** | eth_udp_video_top.v +13/−7、link_monitor.v +10/−4、tb_link_monitor.v 例化适配：rst_lm_sync2 第三级复制成同沿 3 副本，link_monitor 三个复位分组（lm_bus 快照 321 CLR / 计数器 262 / 时基节流 29）各吃一份 | 完整闭环：tb_link_monitor PASS + 19 支 MSIM fail=0 + 构建。**全局 WNS 1.341→1.368（+0.027）、WHS 0.025→0.048（+0.023）、clkout3 组 recovery 1.658→1.488**、0 failing、资源功耗平、0 critical | **ACCEPTED**（合入 main `0cc5cd0`） | 双指标确定改善（跨 RTL 确定性差异，非重跑噪声）；结构收益 = 539 端点单点分发树 → 3×~180；副本同沿同值同异步复位，**释放沿逐拍与单副本版相同 ⇒ 板级行为零变化**（板级烟测仍标"未验证"）；回退 = revert merge |
| 方案一 寄存 eth_rst_async 一拍 | system_top.v +8/−1（`eth_rst_n & mmcm_locked` 打一拍） | 单独闭环：靶路径 sys→clkout3 组 1.341→1.594（+0.253），但全局 1.277（−0.064，rst_lm 539 树冒头 rst_l→reasm 1.277） | **REJECTED**（单独） | 全局退化；机制收益真实但被布局重排抵消 |
| 方案一+方案二 组合 | 方案二 之上叠加 方案一（branch `c1c2-stack`，19 支 MSIM fail=0 + 构建） | 全局 WNS **1.139**（−0.202 vs baseline）；clkout3 组 1.139、clkout3 setup 1.576、clk_fpga_0 1.451 | **REJECTED** | 布线重排不可加：方案一 单独 1.594 + 方案二 单独 1.488，叠加后 rst 网络再冒 1.139 新次差——"复位网络打地鼠"第二次实证，与 `report/optimization.md` 作者边界结论一致。回退：未合入 |
| **方案三 协议域异步复位→同步复位** | 17 文件 55 块（`or negedge rst` 移除，FDCE→FDRE；保留同步器首环/gmii_rx_cdc/dc_fifo/snap_cross 异步；全部清零复位已审计） | 19 支 MSIM fail=0 + 构建：**结构指标全面好转**——async 组 3037→360 ep、clkout3→clkout3 recovery 1.488→2.154、clkout3 setup 1.576→1.723、LUT −177、功耗 −0.009 W；但**全局 WNS 0.674（−0.694）** | **REJECTED** | 全局短板转移到同步器首环的 sys→clkout3 recovery（`phy_rst_cnt → rst_lm_sync/CLR`，9 ep）——**该检查是 async-assert 结构的地板：只要同步器首环保留异步复位它就永远存在**，requirement 4 ns 固定，slack 只随 phy_rst_cnt（sys 域）与同步器（clkout3 域）的物理距离抽签。下游同步化改变不了它 |
| **方案三+方案一 组合** | 方案三 之上 cherry-pick 方案一（消 LUT2，branch `c6-sync-reset`） | 19 支 MSIM fail=0 + 构建：全局 WNS **0.826**；clk_fpga_0 hold 掉到 **0.009** | **REJECTED** | 比 方案三 好转 0.15 但仍远低于 baseline；且 WHS 逼近违例。三次实验（0.674/0.826 vs baseline 1.341）确认：**baseline 的 1.341 已贴着架构地板**，方案二 的 1.368 是历史最好抽签。回退：未合入，未刷板（门序：STA 不过不保留） |
| **方案四 复位锚点 pblock**（候选件 `src/constraints/c7_rst_anchor_pblock.xdc`，`VP_C7_RST_ANCHOR=1` impl-only，默认 off） | 把 phy_rst_cnt 与 rst_l/rst_lm 同步器首环+方案二 副本包进无坐标 pblock，试图收拢 sys→clkout3 recovery 的 20 列源-宿距离 | **单测（方案二 之上）：全局 1.368 与 方案二 逐位相同**——无坐标 pblock 只是打包成员，extent 由 placer 沿成员现有位置拉成宽矩形，**成员间距离不变**（诊断：两端坐标 X98/X78 纹丝未动） | **REJECTED（单测无效）** | placer 的既有摆位本就是全局权衡解，打包不寻优 |
| **方案三+方案四+方案一 组合**（branch `c6-sync-reset`：方案三 55 块 + dc_fifo/snap_cross/gmii_rx_cdc 补 9 块 + 方案四 pblock + 方案一） | 全量同步化消 clkout3 组 + pblock 钉首环 + 寄存消 LUT2 | 19 支 MSIM fail=0 + 两轮构建：**clkout3 组 3037→128 ep、recovery 2.023、clkout3 setup 1.696、LUT 14761**（结构全面达标）；但全局 WNS **1.108**，且 XDC 补入 `eth_rst_async_r_reg` 后**数字逐位不变**——pblock extent 仍覆盖原位置，簇内距离未收拢 | **REJECTED** | 8 次构建的全局轨迹（0.674→0.826→1.108→1.108）无一突破 1.37；进一步收拢需 `resize` 硬钉小窗强制 35 FF 挤位——会扰动 clkout3 组刚取得的 2.023，并给未来所有迭代钉死布局自由度（手工布局深水区）。期望收益递减、方差增大，按纪律收手。全部实验分支与构建产物保留 |
| C3 WHS 锁值（u_pipe pblock） | 中风险布局约束 | 未实施 | **不再必要/搁置** | 方案二 后 WHS 已 0.048（较 baseline 0.025 翻倍），锁值收益边际；且组合实验再次证明重排敏感，pblock 引入新的固定布局约束反而限制后续迭代。如未来需要，流程同本报告验证门 |
| C4 reasm cov 锥复制 | frame_reasm.v | 未实施 | **放弃** | `report/optimization.md` §5 两次否决记录（"当前布局对清零锥敏感"） |
| C5 启用 r116 RGMII 输入窗 | 约束候选件 | 未实施 | **放弃** | `report/limits.md` 明确判过不采纳（合法 IDELAY 档内窗关不掉，5 个 I/O 端点判红） |

被接受改动 patch = `git diff baseline..main -- submission/src submission/sim`（3 文件，+27/−14，单一结构改动 + 台架例化适配；`git revert 0cc5cd0` 即整体回退）。

## 4 仿真证据全景

**交付判定口径（`report/verification.md` §2：19 支标准回归 + 完整视频台架专项）——全绿：**

| 门 | 结果 | 工具/口径 | 证据 |
|---|---|---|---|
| 19 支标准回归（baseline RTL） | **19/19 PASS，fail=0** | ModelSim SE 2020.4（与 交付基线 交付同工具），`run_msim.sh` | `timing_opt/logs/msim_std19.log`、`build/msim/*.log` |
| 19 支标准回归（**方案二 版 RTL，被接受候选**） | **fail=0**（含定向 tb_link_monitor PASS：三份例化覆盖新复位端口） | ModelSim 2020.4 | `timing_opt/logs/msim_c2_lm.log`、`msim_c2_std19.log` |
| 19 支标准回归（方案一+方案二 组合，被拒候选） | fail=0 | ModelSim 2020.4 | `timing_opt/logs/msim_c1c2_std19.log` |
| tb_video_pipeline_top 专项 | **`RESULT tb_video_pipeline_top PASS nfail=0 (quick_c17)`**（与 交付基线 判定行一字不差） | ModelSim 2020.4，`MSIM_PLUSARGS="+quick_c17"`，23 min | `timing_opt/logs/msim_vpt_quickc17b.log` |
| xsim 交叉验证 | 17 支批跑 PASS + 2 支（eth_top_rgmii/udp_telemetry）手工 `xelab -timescale 1ns/1ps` 补跑 PASS；vpt 全判据模式跑到 172 PASS / 0 FAIL（超额覆盖，主动中止） | xsim 2025.2.1 | `sim/xsim_std19.log`、`sim_work/tb_etrg_ts`、`tb_utel_ts`、`timing_opt/logs/sim_vpt_ts.log` |

**91 支补全量（清单口径，非交付判定）**：xsim 58 PASS；4 支 ELAB_FAIL 为 XSIM 43-4099 工具差异（rgmii_rx.v/crc32_d8.v 无 `timescale`），ModelSim 复核 **crc32/rx_chain/rx_fcs/zoom_frac 全部 PASS**。

**审计发现（baseline 固有，与本任务无关，未修）**：`tb_eth_video`、`tb_ip_csum`、`tb_ddr_line_locality` 在 ModelSim 与 xsim 下均 FAIL/无判定行；`tb_src_arb` 使用 SV `expect` 仅 xsim 可跑且 FAIL、`tb_rowmath` 仅 xsim 可编译；`tb_c8_edge_column` 在 ModelSim 时间盒内跑完，baseline RTL 上 `FAIL nfail=6`（C0d/C0e/C1a/C1g/C1h/C1i，激励/尺子与当前 pl_video_top 握手脱节形态）。这 6 支均不在 19 支交付判定内、在 `fin_final_msim` 无通过记录——属"92 支清单与实际可绿集合"的历史差异，修复需动台架（超出本任务冻结范围），仅记录。

## 5 板级验证（2026-11-01，方案二 位流 JTAG 下载，全项通过 ✅）

条件：Zynq-7020 板卡 + FT2232（A=JTAG/B=COM6 115200），PC 192.168.1.100 ↔ 板 192.168.1.10 直连千兆；位流 `c2_timing/system.bit`（MD5_12 edcbe52d21dd）经 `board_flash.sh` 三件套下载（ps7_init 补丁见下），FLASH: GREEN，GPIO 回读 0x000F5000。证据：`board/measured/flash_20261101_1108.txt`、`board/uart_script_capture.txt`。

| 项 | 方法 | 预期 | 实测 | 判定 |
|---|---|---|---|---|
| 扫链 | hw_server + vivado 扫链 | arm_dap + xc7z020 | 同 | ✅ |
| JTAG 下载 | board_flash.sh（rst→ps7_init→PL→ELF→GPIO） | FLASH: GREEN | GREEN | ✅ |
| ping | 5 连发 | 全通 | 5/5，0% 丢失 | ✅ |
| 连续流 | `video_sender.py --demo --seconds 8` | ~241 帧/8 s | **241 帧 / 8.03 s = 30.01 fps** | ✅ |
| 遥测 | `telemetry_listen.py 13` | 13 包，帧计数连续 | 13/13 包，frames=241 与推流一致，作废仅 1 次启动作废 | ✅ |
| 三阶段自检 | `link_selftest.py 192.168.1.10 6` | 干净 ≥8 fps/作废 ≤1、故障作废 ≥5/s 且帧率 <5、恢复 | **22.2 fps/作废+0/lat 8ms；0 fps+14.0 作废/s；18.9 fps/作废+0** → PASS | ✅ |
| 串口命令 | `uart_cmd_check.mjs --port COM6` | 105 条逐条回声、末态回初态 | **RESULT PASS（105 条，98.6 s）**，温度三方对账自洽 | ✅ |
| 帧间隔统计 | 推流中 `link clr`/`link`（COM6） | gap_valid=1、gap_max 与历史一致 | **gap_valid=1，gap_max=49 ms（=历史交付值）**，drop=0 badpkt=0 | ✅ |

与 交付基线 板级读数对照：帧率 30.01 vs 29.95 fps、自检 22.2/14.0/18.9 vs 22.0/14.3/18.9、gap_max 49 vs 49 ms——**同水平，无回归**。

板上工具链两处环境修复（副本工作区内，不动提交件）：① `build/ps7_init.tcl` 从 XSA 手工解出（脚本 2026-09-23 补的自动解包分支生成器有 tcl 方括号求值 bug，从未成功过）；② 其头部加 `configparams force-mem-accesses 1`（xsdb 2025.2.1 会在 PS 未初始化期拦截对 DDRC 区的写，ps7_ddr_init 阶段无 force 保护导致 DDR 初始化中断——Vitis 新版 ps7_init 自带此行于 post_config，但 ddr 阶段缺失）。

**方案二 位流是 JTAG 易失下载**：板子断电后会回到 QSPI 里的旧固件。若要让 方案二 成为常电交付，需另行走 QSPI 固化流程（`board/scripts/make_boot_image.sh` + `board/tcl/flash_qspi.tcl`），本轮未做。

## 6 风险与未验证项

- **板级：方案二 已全项通过（见 §5）**；SD 热插拔与 SD 回放未在本轮重测（本轮改动不触及 SD 域；交付基线 交付已验证）。
- 功耗/结温为工具估算（confidence low）；本轮未读板上 XADC 温度专项（UART battery 内温度三方对账自洽）。
- **布线敏感性的实证**（供未来迭代参考）：rst 系 recovery 路径对 +1~+4 个 FF 的重排敏感（方案一 −0.064、组合 −0.202）；任何后续复位/布局改动都要按本报告验证门全量重测，不能线性外推。
- 若未来要动 CDC，`timing_opt/reports/cdc_details.rpt`（3 条 Unsafe 的逐条 by-design 定性）可作为对照基线。

## 7 下一步建议

1. **最终结论：方案二 为可复现的最优解**。八次对照构建把优化空间穷尽到架构地板：全局 WNS 的短板（sys→clkout3 复位恢复，requirement 4 ns）是 async-assert 复位结构 + 双 MMCM 时钟架构的固有属性，RTL 手段（方案一/方案三）、物理手段（方案四 pblock 两轮）、组合手段（方案一+方案二/方案三+方案一/方案三+方案四+方案一）全部实测过，全局轨迹 0.674~1.368 无一突破 方案二 的 1.368。
2. **方案二 的上板门已完成**（§5 全项 GREEN）。若要让 方案二 成为常电交付，走 QSPI 固化（`make_boot_image.sh` + `flash_qspi.tcl`，擦写回读校验）；本轮未做（JTAG 易失验证已足够支撑接受裁定）。
3. **不建议再动**：pblock `resize` 硬钉与复位网络继续改组均在"收益递减 + 方差增大"区（本轮 方案四 两轮实测），且钉死布局会剥夺未来迭代的自由度。若未来换器件/换时钟架构，本报告 §2 的地板机制分析可作为重新起点的依据。
4. 台架卫生（低优先，不涉时序）：6 支清单外台架与 RTL 脱节（§4），建议单独开一轮"台架账实对齐"，不与时序优化混车。
5. 复现本报告每一步：命令、日志与产物路径已内嵌各节；构建入口 `build/build.tcl`（`VP_OUTDIR` 隔离产物；`VP_C7_RST_ANCHOR=1` 为 方案四 候选件开关，默认 off）；回归入口 `run_msim.sh`（MSIM_BIN 指向 ModelSim win64）与 `run_sim.tcl`（xsim；43-4099 台架需 `-timescale 1ns/1ps` 补跑）。

---
报告：2026-11-01，timing-opt-agent（ZCode 主代理）。所有数字可溯源至工作区内报告/日志；未验证项已逐条标注。
