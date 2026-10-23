# 纠错轨迹

每条按三件事写：错误断言、否定它的实验或证据、更正后的结论与影响范围。这里只留最终包内能复核的锚点；早期台账和原始导出在本地归档，不随包。

## C1 · 字节数到齐不等于一帧完整

**错误断言：** 重组器只要收满 307200 字节且没有坏包，就可以提交。

**判别实验：** 给“字节数够、只覆盖 3/4 行”的激励。错误实现仍然提交，因为字节门单独成立。把行计数改成“每写一个字加一”的变异体后，判据报 `FAIL commit with full byte count but only 3/4 rows`。

**更正：** 提交条件必须是整帧字节数、行覆盖位图、坏包门三件事同时成立。影响范围是重组器、显示侧读回和作废计数；证据在 `sim/results/regression.txt` 的 `rows`、`udp_reasm` 判定行。

## C2 · 4 ms idle timer 不是可选优化

**错误断言：** 上一帧丢尾、下一帧丢头时，只要最终字节数够，重组器可以继续拼。

**判别实验：** 在 `tb_udp_reasm` 的 A9 段让上一帧丢尾、下一帧丢头，中间静默超过 4 ms，再恢复干净流。没有 idle timer 时两帧会混，恢复后的第 3 帧也不干净。

**更正：** 用 12 位预分频的 4 ms idle timer 在静默后清掉半帧状态；判据要求两帧不混、恢复后第 3 帧仍能提交。影响范围是重组器状态机和帧提交计数；证据在 `report/design-report.md` 的 A9 段和 `sim/tb_udp_reasm.v`。

## C3 · `p_good` 按包清零会放过坏包帧

**错误断言：** 每个包处理完把 `p_good` 清掉，坏包只会影响当前包。

**判别实验：** 在同一帧里先注入一个坏包，再送完整字节。按包清零的实现仍会把整帧提交；按帧维护时，坏包帧被作废，下一帧重新累计。

**更正：** `p_good` 按帧维护，坏包帧不提交；作废计数按帧增长。影响范围是重组器提交门和板上 `aborts` 读数；证据在 `sim/results/regression.txt` 的 `udp_reasm` 判定行与 `board/measured/link_gap.txt`。

## C4 · 用瞬时帧率做故障判据会误判

**错误断言：** 自检的干净段和故障段都用当前帧率比较。

**判别实验：** 启动瞬间帧率低，故障段又可能残留上一秒的计数；用绝对值时，故障段会被判成通过。

**更正：** 三阶段自检只认每秒 `frames` 与 `aborts` 的变化量。干净段 22.0 fps、故障段 0 fps + 14.3 次作废每秒、恢复段 18.9 fps，才是可复核的读数。证据在 `board/measured/link_selftest.txt`。

## C5 · 处理窗漏进原图不能用“看起来对”判断

**错误断言：** 灰度单级加 split video 时，处理窗里出现彩色像素只是显示抖动。

**判别实验：** 用非灰像素计数 `pane_bad`，在 185°、30 fps 连续流下统计处理窗。计数有效且 `pane_bad=0` 才能排除漏图；只靠人眼看会漏掉少量像素。

**更正：** 把 `pane_bad` 和 `pane_valid` 作为板级判据，原图/处理图共用同一帧和同一几何。证据在 `board/measured/pane_integrity.txt`。

## C6 · 两条显示链各自缩放会让竖缝对不上

**错误断言：** 原图和效果图各做一套缩放/旋转，只要参数相同就能对齐。

**判别实验：** 两条链的窗口级延迟和行标签不同，竖缝处会出现一行错位；C31 的 9 位列标签能直接指出哪一格选错抽头。

**更正：** 改成一条几何引擎、一个源坐标，竖缝处按显示列二选一；`sx` 先过两行环再进 `seam_src`。C31 从帧尾两整行各 1028 格不符降到 swap 两态全帧 0。证据在 `sim/results/c31_edge_rim.log`。

## C7 · 判据第一次跑就绿，要先怀疑空集

**错误断言：** 台架打印 PASS，就说明被测逻辑被覆盖到了。

**判别实验：** 检查激励的覆盖计数，发现有的臂只跑了单个窗口或空样本；把样本集清空，判据仍然绿。给每条判据加覆盖计数和反例后，空集分支会报 `NOT_MEASURED` 或直接失败。

**更正：** 判据必须能红；第一次跑就绿要查激励、样本集和变异体。证据在 `report/verification.md` 的三态说明和 `sim/results/regression.txt` 的覆盖行。

## C8 · bootgen 返回 0 不等于镜像更新

**错误断言：** bootgen 打印 `Bootimage generated successfully` 且进程返回 0，`BOOT.bin` 就是新的。

**判别实验：** 输入路径缺失时 bootgen 仍可能返回 0，旧镜像留在盘上。用三件套 MD5 对比，发现镜像没有变化。

**更正：** 打包前删旧镜像，检查日志里的 `[ERROR]` 和成功行，并生成 `boot_manifest.txt` 记录 FSBL、位流、应用和镜像的 MD5。当前镜像 `a4ca985c...`，三件套哈希在 `board/flash/boot_manifest.txt`。

## C9 · 函数存在不等于命令可达

**错误断言：** `cmd_link` 已经写好，串口敲 `link` 就应该能读帧间隔。

**判别实验：** 板上敲 `link` 回“不认”，帮助行里也没有 `link`；查 dispatch 表，函数没有接进去。

**更正：** 把 `link` / `link clr` 接进命令分派和帮助行，重编 ELF 后实测 `[LINK]` 能读 `stall`、`gap_last/min/max/sum`、`gap_valid`、`live`。证据在 `board/measured/link_gap.txt`。

## C10 · 目录移动后，脚本默认路径会悄悄失效

**错误断言：** 工程和脚本换目录后，原来的相对路径仍然可用。

**判别实验：** `board/vivado` 深了一层，`$PPRDIR/../src` 指到 `board/src`；`build/ps` 和 `build/vitis` 的仓库根少算一层；文档里的相对 `PS_OUT` 在中间目录链接时找不到输出。

**更正：** 工程路径改为 `$PPRDIR/../../src`；脚本用三层 `dirname` 求仓库根；`PS_OUT`/`PS_OBJ` 统一规范成绝对路径；Boot 脚本优先找 `board/flash/fsbl.elf`，再找 `board/vitis_ws`。重编 PS 应用得到的 ELF 与交付件逐字节一致（`aaf2c867...`）。

## C11 · 工程能打开不等于能综合

**错误断言：** `board/vivado` 的 `missing_files=0`、绝对路径为 0，工程就可以直接综合。

**判别实验：** 干净副本综合时找不到 `design_1_wrapper`；wrapper 原先只存在于构建目录的 `.gen`，没有随 `.srcs` 入库。

**更正：** 把 wrapper 放进 `board/vivado/zynq_video_sys.srcs/sources_1/bd/design_1/hdl/` 并加入工程；干净副本从零综合到 100%。证据是 `board/vivado/README.md` 的工程说明和 `build/tcl/stage_board_projects.tcl` 的 wrapper 检查。

## C12 · 文档数字要回到证据，不跟着旧稿走

**错误断言：** 旧稿里的 99 份 RTL、102 个文件、`sys_clk` 100 MHz、板温 57–62 °C 可以继续用。

**判别实验：** 工程实际是 92 份手写 RTL + 1 份 wrapper + 1 个块设计 + 3 份约束 = 97 个文件；约束和 MMCM 都是 20 ns（50 MHz）；包内温度读数是 61.79–63.82 °C。

**更正：** 文档统一改成 97 个文件、`sys_clk` 50 MHz、板温 61.8–63.8 °C；异常向量判据改成“标签可读”，不再写“地址为 0”。证据在 `board/vivado/zynq_video_sys.xpr`、`build/reports/build_timing_summary.rpt`、`board/measured/health.txt` 和 `board/measured/uart_battery_capture.txt`。
