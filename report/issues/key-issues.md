# 关键问题台账（精选）

编号沿用原台账；这里只保留真正改变过设计或判据的条目。完整台账在 `FIN/records/issues/issues-full.md`。

## 1. #27–35 · 入包链丢字：拖影和黑横纹的真正根因

**现象**：静止画面也撕裂；每隔一个 16 位出现黑横纹；加深缓冲没有改善。
**根因**：UDP 分包长度不是 8 的倍数，打包器按 16 位半字对齐后确定性错位；打包器每写一个字都等 AXI B 响应，吞吐被往返延迟钉死；FIFO 被综合成触发器，资源爆掉。
**判据**：`tb_udp_reasm` 按帧内偏移逐字比对；`tb_saver` 检查 16→64 位拼接、突发长度和尾字。
**修复**：发送端载荷强制 8 的倍数；打包器改成写地址/写数据并行握手，B 响应只回收计数；FIFO 用分布式 RAM 实现。**状态**：已修。
**证据**：`src/rtl/eth/axi_frame_saver64.v`、`sim/tb_udp_reasm.v`、`sim/results/regression.txt`。

## 2. #38 · `p_good` 硬接 1，坏包统计是死的

**现象**：坏包计数长期为 0，看起来链路从不丢包。
**根因**：`frame_reasm.p_good` 在两个板的顶层都硬接 1，`stat_bad` 没有真实输入。
**判据**：故意注入坏包/FCS 错包，`bad` 必须增长；`flags` 的丢过字/作废过帧位必须能置起。
**修复**：把 MAC 的坏包标志接进重组器，坏包计数和作废计数分开。**状态**：已修。
**证据**：`src/rtl/eth/frame_reasm.v`、`board/measured/link_selftest.txt`。

## 3. #42 / #44 · PS 启动链：浮点陷进 Undefined，手工镜像丢了启动文件

**现象**：JTAG 下载后 PS 应用不跑，PC 落在异常向量；换手工链接的 ELF 后四件事一起坏。
**根因**：CPACR 没开，VFP 指令陷成 Undefined Instruction；手工链接的 standalone 镜像漏了 `boot.S`、`asm_vectors.S`、`translation_table.S`，入口、向量表、MMU 都没了。
**判据**：ELF 必须有 `_boot`、`_start`、`_vector_table`、`MMUTable`；异常向量地址为 0；串口和 GPIO 回读都要有。
**修复**：编译脚本强制把三个 BSP 启动文件链进来，并做符号/入口自检。**状态**：已修。
**证据**：`build/ps/build_ps_app.py`、`src/ps/lscript_ocm.ld`、`board/measured/health.txt`。

## 4. #45 · `XSdPs_CfgInitialize` 每个上电周期只能成功一次

**现象**：第一次 `sd` 能挂载，之后同样的命令失败；重下 ELF 才恢复。
**根因**：SD 驱动初始化在每个核上电周期只成功一次，第二次必失败。
**判据**：`sd remount` 必须能在不重新上电的情况下恢复；失败要打印下一步。
**处置**：不自动挂载，第一次失败后提示 `sd remount` 或重下 ELF；这是规避，不是根因修复。**状态**：规避。
**证据**：`src/ps/sd_play.c`、`board/measured/sd_playback.txt`。

## 5. #46 · 把“自首次播放起的累计平均”当帧率，读数离谱 20 倍

**现象**：播放一段时间后报的 fps 明显偏高，和窗口内实际帧率对不上。
**根因**：分子用了自首次播放以来的总帧数，分母用了当前窗口时间。
**判据**：同一窗口内的帧数增量 ÷ 时间增量；平均值必须落在 min/max 之间。
**修复**：改成窗口速率，标签写清窗口；`metrics.mjs` 加自相矛盾检查。**状态**：已修。
**证据**：`src/host/metrics.mjs`、`data/metrics.csv`。

## 6. #48 · 只读 META.TXT 第一个扇区，制造“卡少了 4 个文件”的假缺口

**现象**：SD 卡上文件明明存在，固件报清单被截断。
**根因**：只读了 META.TXT 的第一个扇区，清单从中途截断。
**判据**：`sd files` 的文件数必须与卡上实际文件数一致；跨扇区清单要能读全。
**修复**：按 FAT32 簇链读完整文件，不假设单扇区。**状态**：已修。
**证据**：`src/ps/sd_play.c`、`board/measured/sd_playback.txt`。

## 7. #50 · SD 第 3584 帧必然读失败：FAT32 高簇字按大端拼了

**现象**：播到第 8 个文件的第一帧必失败，报“文件找不到”。
**根因**：目录项里的 FAT32 高 16 位簇号被按大端拼，簇链跳到错误位置。
**判据**：跨文件边界连续播放；`sd file n` 选段后能从该段续播。
**修复**：按小端拼高/低簇字；`play` 不再把 `nxt` 归零，从选中段续播。**状态**：已修。
**证据**：`src/ps/sd_play.c`、`board/measured/sd_playback.txt`。

## 8. #54 · 窗口级效果链“数据与 Valid 错位”，总延迟写的还是错数

**现象**：模糊/锐化/Sobel/形态学打开后，行边界出现固定错位，OSD 总延迟与实际不符。
**根因**：窗口级的内容比行标签多滞后一行；顶层的总延迟常数没有把窗口级算进去。
**判据**：C22 逐行比较行标签与内容；C31 用 9 位列标签帧检查每个像素选中的抽头。
**修复**：行首采输入行标签历史 `yl1/yl2/yl3`；竖缝 `sx` 先过 2 行环再进 `seam_src`。**状态**：已修。
**证据**：`sim/tb_video_pipeline_top.v` 的 C22/C31 段、`sim/results/c31_edge_rim.log`。

## 9. #58 · 在 100 MHz 域里做组合除法器

**现象**：WNS −5.014 ns，96 个失败端点。
**根因**：新加的门禁逻辑在 100 MHz 域里做了一个组合除法器。
**判据**：实现后 WNS ≥ 0、失败端点 0；新逻辑必须先看它落在哪个时钟域。
**修复**：除法移出组合路径/换定点移位。**状态**：已修。
**证据**：`build/reports/build_timing_summary.rpt`、`report/optimization.md`。

## 10. #60 / #61 · 台架与综合的两类假绿

**现象**：判据在 X 条件下两个分支都不走，静默绿；综合把两个 always 块争抢的旗标接成常量，台架 56 条全绿但硬件那根线恒 0。
**根因**：`if (!cond)` 对 X 的开放性；仿真按后写覆盖，综合按常量优化。
**判据**：判据必须能被打红；关键旗标要有 `default`/唯一驱动；综合后网表要复查。
**修复**：台架加 `!==`/显式 X 检查；旗标改成单 always 驱动。**状态**：已修。
**证据**：`sim/` 相关台架、`report/verification.md`。

## 11. #62 · “分割线 0–100% 可调”与“左右各 512 的固定双窗几何”数学上不相容

**现象**：缝位一改，左右窗口的几何就对不上。
**根因**：两套几何各自维护，分割线被当成两个独立窗口。
**判据**：一个视口、一条地址流、逐像素选择；缝位变化不改变两侧坐标。
**修复**：统一成单视口 + 逐像素二选一。**状态**：已修。
**证据**：`src/rtl/video/split_display.v`、`sim/tb_split_ctrl.v`。

## 12. #63 · `zoom 1` 与 `zoom 1.0` 不是一回事

**现象**：想回到 1.00 倍，输入 `zoom 1` 却把呼吸自动缩放打开了。
**根因**：V7 的开关语义与 V8 的倍率语义撞在同一个词上。
**判据**：命令回声必须写清“开关”还是“倍率”；`zoom 1.0` 必须落在最近档 1.00。
**修复**：帮助行和拒绝消息明确区分；`zoom 1.0` 走倍率解析。**状态**：已修。
**证据**：`src/ps/main.c`、`src/host/uart_cmd_check.mjs`。

## 13. #66 · `src 0/1/2` 只写 1 bit，模式覆盖位没接

**现象**：串口切源后，屏幕仍被自动仲裁抢回去。
**根因**：`src` 只写 `src_sel`，V8-2 的 mode 覆盖位没有接进控制字。
**判据**：切源后读回 lane30，`owner`/`mode` 必须与命令一致；长按要能释放覆盖。
**修复**：把 mode 覆盖位接进控制字；`src auto` 释放。**状态**：已修。
**证据**：`src/ps/main.c`、`src/rtl/top/pl_video_top.v`、`board/measured/health.txt`。

## 14. #67 · `pipe` 收 8 位却按 9 位解释

**现象**：输入八位效果串后，实际生效的位数与屏幕显示对不上。
**根因**：解析器接受了 8 位，内部按 9 位补零解释。
**判据**：只接受 9 位；5 位老写法只回等价串、不写寄存器；其他长度一律拒。
**修复**：解析器只认 9 位，老写法走翻译出口。**状态**：已修。
**证据**：`src/ps/main.c`、`src/host/uart_cmd_check.mjs`。

## 15. #68 · 混色级的列标签比内容旧 9 列

**现象**：竖缝在缩放/旋转时位置偏，缝周围出现颜色条。
**根因**：`split_display` 用 `x_d[11]` 判缝，而两路像素到第 20 级才到；列标签与内容不同拍。
**判据**：9 位列标签帧逐格检查；缝两侧同帧、同坐标。
**修复**：把缝位判断移到与像素同拍的级；C31 覆盖旋转帧尾。**状态**：已修。
**证据**：`src/rtl/video/split_display.v`、`sim/results/c31_edge_rim.log`。

## 16. #69 · `board_verify.sh` 没有总判定，各步退出码被管道吃掉

**现象**：前面步骤红了，脚本仍然以 0 退出。
**根因**：没有汇总判定行；`cmd | tee` 的退出码来自 `tee`，不是 `cmd`。
**判据**：末尾必须有一行总判定，写明判定项数/失败项；退出码服从总判定。
**修复**：加总判定行和三态；管道用 `PIPESTATUS`/显式检查。**状态**：历史脚本已修；最终包改用 `board/scripts/board_health.sh` 与 `board/measured/` 的判定行。
**证据**：`board/README.md`、`board/measured/README.md`。

## 17. #98 · 帧头若干行：读侧绕回与内容旧一帧

**现象**：帧头几行出现上一帧的尾巴/拖影。
**根因**：处理抽头提前发了下一行；四个窗口级的行缓存读到了绕回后的内容。
**判据**：C5c 帧头行必须携带自己的源行；`STREAM_WRAP=1` 只对连续流生效。
**修复**：窗口级加 `STREAM_WRAP`；顶层行标签换成与内容同一本账的 `cy_chain`。**状态**：已修；残余代价是帧头 4 行内容比同屏其余行旧一帧（≈33 ms），只能人眼判。
**证据**：`sim/tb_pipe_bypass.v`、`report/verification.md`、`report/limits.md`。

## 18. #181 / A9 · 上一帧丢尾、下一帧丢头，拼成一整帧

**现象**：链路短暂静默后，屏幕出现半旧半新的混合帧。
**根因**：重组器只按字节数和行覆盖提交，静默期间两帧的账被拼在一起。
**判据**：`tb_udp_reasm` 的 A9 段让上一帧丢尾、下一帧丢头，中间静默超过 4 ms；要求两帧不混，恢复后的第 3 帧干净。
**修复**：4 ms idle timer + 12 位预分频，`idle_clear` 只驱动一个单 bit 进入 header 清位锥；未预分频版本和 `last_hdr` 版本都因 WNS 被否决。**状态**：已修。
**证据**：`src/rtl/eth/frame_reasm.v`、`sim/tb_udp_reasm.v`、`report/optimization.md`。

## 19. #507 / #508 · 续播游标与满 FIFO 尾字

**现象**：`sd file n` 选段后 `play` 从第 0 帧开始；满 FIFO + flush 时尾字丢失。
**根因**：`play` 把 `nxt` 归零；saver 在满 FIFO/flush 分支把未写完的尾字清掉。
**判据**：`sd file 1` → `play` 后帧计数大于一个文件；`tb_saver_tail_full` 要求 514/514 逐字对。
**修复**：`play` 从选中游标续播；满 FIFO + flush 保留尾字。**状态**：已修。
**证据**：`src/ps/sd_play.c`、`src/rtl/eth/axi_frame_saver64.v`、`sim/results/regression.txt`、`board/measured/sd_playback.txt`。

## 20. 本轮新增 · `link` 命令不可达与 BSP 路径错误

**现象**：源码里有 `cmd_link`，板上敲 `link` 回“不认”；文档写 `PS_BSP=board/vitis_platform/bsp`，按字面编译找不到 BSP。
**根因**：`cmd_link` 没有接进 `dispatch`；平台描述目录没有 BSP，文档把“平台描述”当成了“BSP 目录”。
**判据**：板上串口 `link` 必须返回 `[LINK] ... gap_valid=...`；编译脚本必须在 BSP 缺失时提前退出并指路。
**修复**：接回分派和帮助行，重编 ELF 并写 QSPI；BSP 改成“平台构建生成的 BSP 目录”，脚本加前置检查。**状态**：已修。
**证据**：`src/ps/main.c`、`board/measured/link_gap.txt`、`build/ps/build_ps_app.py`、`report/collaboration/corrections.md`。

## 仍未修 / 边界

RGMII 发侧约 0.845 ns 的 TskewT 保持缺口、复位恢复路径、hold 0.025 ns、BRAM 70%、端到端时延未测、HDMI 人眼项。逐条见 [`../limits.md`](../limits.md)；不要把这些写成本目录里的“已修”。
