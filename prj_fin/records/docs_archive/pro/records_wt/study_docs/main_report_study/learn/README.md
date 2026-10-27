# 学习文档（本地）

这套文档不上传、不参与构建，它的作用只有一个：让一个没看过这个仓库的人，从"什么是有效数据
使能"开始，一路读到"为什么 `raw_line_delay` 的环深必须是 `2^clog2(LINES+1)`、为什么消隐期
那一拍的读地址要单独做一次预读、为什么缝的判定必须与内容同一拍"。

工程本体是一颗 Zynq-7020（`xc7z020clg484-2`）：网口 / SD 卡 / 片内图卡三选一送来 512×300
的视频，PL 做几何变换与图像处理，以 HDMI 1024×600 输出，屏幕上任何一条竖线以左是未经处理的
画面、以右是同一坐标系下处理后的画面。Verilog RTL + 裸机 Arm 固件 + Vivado / Vitis 2025.2.1。

## 1. 这套文档在仓库里的位置

`report/study/` 整个目录被 `.gitignore:105` 挡住，不进提交包。它与仓库里另外两层文档的分工：

| 位置 | 是什么 | 口径 |
|---|---|---|
| `report/` | **交付文档**：简介、背景与创新、架构、模块清单、命令表、性能报告、构建与上板、演示脚本 | 结论 + 证据，克制；数字只出现在 `PERF_REPORT.md` |
| `report/log/` | **工作记录**：`ISSUES.md`（缺陷账本，`#NN` 一条一节）、`OVERNIGHT_LOG.md`（时间线）、版本谱系 | 追加式，按定义会过期；追因时才查，别当现状读 |
| `report/study/` | **学习文档**（本目录的上一层） | 允许出现"文档说 A、代码是 B"，并把两边都列出来 |

上一层 `report/study/` 里并排放着两套东西：

- `00_前置知识/ … 06_自测/`：中文目录那一套，十篇前置 + 三篇图像原理 + 四篇架构 + 十篇模块详解 +
  三篇版本演进 + 三篇验证上板 + 一篇自测。它是本套的**写作范本**：每章按
  "是什么 / 为什么要它 / 原理怎么推 / 代码在哪几行怎么实现 / 怎么自己验证"来写，讲透而不是罗列。
- `learn/`（本目录）：进阶集，篇幅更长、推导更细，尤其是效果链、几何、采集显示通路、时钟与
  PS 软件、Tcl、验证方法这六块。

两套不是替代关系。想按主题从零建概念，读中文那一套；想知道"这一处代码为什么长成这样、
改它会红什么"，读本目录。两套的引用格式相同（`文件:行` 相对仓库根 `Video_Processing/`）。

## 2. 章节表与本目录的读法

| 序号 | 文件 | 回答什么问题 | 需要的前置 |
|---|---|---|---|
| 00 | `00_prerequisites.md` | 读这个项目要先会什么：数字逻辑与 Verilog 的六个坑、视频时序、时钟域与四种跨域做法、流水线记账、定点数、BRAM/LUTRAM/DDR、AXI 与 Zynq 边界、裸机启动、脚本分层、报告读法、先量后修的规矩 | 会写一点 C |
| 01 | `01_project_map.md` | 整体框架：数据流、目录地图、三个顶层、`pl_video_top` 全部实例、控制字位段、关键常数、两条抽头的相位、六股时钟、三路片源与仲裁、观测 lane、哪些文件不在位流里、改哪里会红 | 00 |
| 10 | `10_effect_pipeline.md` | 效果链怎么摆：级 0 gamma + 五级可选算法（九位 `stage_sel`，一位一级）、每级的定点算术与行缓存、固定 15 拍怎么来的、陈旧行与边缘条带 | 01 |
| 11 | `11_geometry_zoom_rotate.md` | 缩放、旋转、双线性插值、图像域分割线：逆映射的算术、Q8 定点、三角表、单读口的分时 | 01 |
| 20 | `20_capture_and_display_path.md` | 片源进来到像素出去：收包链、DDR 乒乓与提交锁、消隐拷贝窗口、两条抽头、逐像素混合、OSD 与显示时序 | 01 |
| 30 | `30_clocks_hdmi_soc.md` | MMCM 时钟树、TMDS 串行化、PS↔PL 边界、约束文件与时序余量 | 01 |
| 40 | `40_ps_software.md` | Arm 侧固件：命令解析、整字写回、寄存器位段、SD 回放、自诊断计数器与心跳 | 01 |
| 50 | `50_tcl_tutorial.md` | Tcl 从零到能干活：Vivado / xsim / xsdb 批处理，以及本仓库脚本的已知坑（路径解析、退出码、`-f` 文件清单） | 00 |
| 60 | `60_verification.md` | 这套门禁怎么工作：台架如何钉 md5、判据为什么必须能红、变异对照、"报告与树不是同一次跑"怎么防 | 01、50 |

不必按顺序读完。三条常用路线：

- **看懂这个工程**：`00` → `01` → `20` →（`10` / `11` 任选）。
- **要改某个模块**：直接跳 `01` §13 的"改哪里会红"表，再进对应章；每章开头都有职责与端口表。
- **板子在手上要复现**：`01` §14（四个入口 + 上板三件套）→ `50`（脚本怎么读）→ `40`（命令与回读）。

## 3. 本套的事实基线：这五条是这一轮重新核对过的

工程这几天改了不少，旧稿里几处描述已经不准。下面五条**每条都附一条当场可跑的核对命令**，
以后读到与本套不一致的地方，以命令的输出为准。

1. **文档目录搬过家。** 没有 `report/` 目录：交付文档在 `report/`，工作记录在 `report/log/`
   （`report/README.md:5-9` 就是这张分派表）。任何 `report/xxx.md` 的写法都是搬家前的路径。

   ```bash
   ls docs && ls report/log          # 期望：report/ 下有一堆交付文档 + log/ + study/；没有 report/
   ```

2. **第二块板（KU5P）整个工程已删除。** 本仓库不再包含 `ku5p/` 目录、`tb_ku5p_*` 台架、
   `src/host/ku5p_*.mjs`，因此本套文档之后不再讲"跨器件移植 / UltraScale"这条线；
   再看到这类段落，按"本仓库不再包含"处理。

   ```bash
   ls | grep -i ku5p; ls src/host | grep -i ku5p; ls sim | grep -i ku5p   # 三条都应当没有输出
   ```

3. **上位机只剩 Node.js 与 PowerShell。** Python 那套（`video_sender.py`、`serial_ctrl.py`、
   `make_test_mjpeg.py`、`requirements.txt`）与三个 `run_*.bat` 都删了。今天只有：
   推流 `node src/host/video_sender.mjs`，真实视频用根目录唯一那个 `stream_video.bat`
   （ffmpeg 解成 512×300 RGB565 裸流，管道喂 `--file -`），串口
   `board/uart_cmd_script.ps1`（从文件按行读命令）与 `board/uart_cap_once.ps1`（一次性 `-Cmds`）。

   ```bash
   ls *.bat; ls board/*.ps1; ls src/host | grep -v mjs     # 期望：只有一个 stream_video.bat、两个 ps1、无残留
   ```

4. **RTL 现状四件事。** 效果链是九位 `stage_sel`（gray / invert / blur / sharpen / sobel /
   binary / bin_pol / erode / dilate，位表正本 `src/rtl/process/proc_pipeline.v:5-6`）；
   双线性插值走的是**单读口分时**（`src/rtl/process/bilin/fb_bilin.v`，每源像素用满 4 个
   50 MHz 拍；`tap_sched.v` 与 `fb_rd5x.v` 是被换掉的另一条方案，现在只有台架驱动）；
   几何是**单视口 + 逐像素原图/处理图混合**（`src/rtl/video/split_display.v`、
   `src/rtl/process/zoom/zoom_mapper.v`，旋转叠在同一个 mapper 里，
   `rotate/rotate_mapper.v` 只有台架例化）；以太网侧有硬件在线健康统计
   （`src/rtl/eth/link_monitor.v`）与自研收包链（`src/rtl/eth/gmii_rx_mac.v`、
   `src/rtl/eth/udp_rx_parser.v`）；OSD 是**五行版式**，其中前四行的字段与顺序是定好的格式、
   第 5 行放片上温度与"没有 ETH 信号"那句提示（`src/rtl/video/osd_overlay.v:16-19`）。

   ```bash
   grep -n "stage_sel\[" src/rtl/process/proc_pipeline.v | head      # 九位逐位解码
   grep -n "N_LINES" src/rtl/video/osd_overlay.v | head -3           # 版式行数写在参数里
   grep -rn "rotate_mapper\|fb_rd5x\|tap_sched" src/rtl sim --include=*.v | head
   ```

5. **构建入口只有一个。** `build/tcl/build_system_axigpio.tcl`（必须从 `build/tcl` 目录里以
   `-source` 方式跑，因为脚本按自身位置往上两级算仓库根）；门禁 `bash build/gates.sh`；
   冻结 `bash build/freeze_evidence.sh <NN>`；板级机器验收 `bash build/board_verify.sh --battery --geom`。

   ```bash
   grep -n "set top\|launch_runs" build/tcl/build_system_axigpio.tcl | head   # 顶层与两条 run
   ```

## 4. 写作约定

- **五问结构。** 每节固定：它是什么 / 为什么要它 / 原理怎么推 / 代码在哪几行怎么实现 /
  怎么自己验证。跳过"显然"，定点位宽、Q 格式、取整方式、饱和在哪一级都写出来。
- **引用格式。** 一律 `文件:行`，相对仓库根；同时给信号名。行号会随提交漂移，
  发现对不上就以文件名加信号名重新 grep，**不要相信这里的行号胜过相信代码**。
- **指路不抄数。** 板子上是哪一版、门禁多少项、资源占用多少，这类会过期的数只写在
  `report/PERF_REPORT.md` 与仓库根首页；本套文档给的是"去哪里读、怎么复核"（认 md5，
  不认文件名：`build/evidence_rNN/MANIFEST.md5`）。
- **不确定就写明。** 代码里没写注释、靠逻辑或算术推出来的，句子末尾标"推断"；
  没能证实的直接写"这条我没能从代码里证实"，不用含糊话糊过去。
- **编码。** UTF-8 无 BOM、换行 LF。这条由门禁第 17 项把关：
  `node src/host/doc_enc_check.mjs`（`--self` 会跑它自己的三条反例）。
  历史事故是 `docs/COMMANDS.md` 第 5 节曾被 cp936 控制台打坏一整段，而位流、台架、门禁
  一个都没红 —— 坏的是"念给人看的那一份"（`src/host/doc_enc_check.mjs:4-9`）。

## 5. 已知会误导人的几处

本套文档之外的那几页也有过期句子，读的时候留意；完整核对记录在 `01_project_map.md` §12。

| 在哪会看到 | 实情 |
|---|---|
| 早期笔记或旧稿里的 `report/ISSUES.md` | `report/log/ISSUES.md` |
| 旧稿说"AXI-Lite 基址 `0x1000_0000` / `0x1010_0000`" | 那是 **DDR 帧 bank 地址**；GPIO 是 `0x4120_0000` / `0x4121_0000` / `0x4122_0000(+0x08)` |
| 第 10 章标题里的"七级管线" | 今天是一张**九位**控制字：八个算法位 + 一个判决反相位，级序 gamma → 颜色 → 滤波 → 边缘 → 阈值 → 形态学，固定 15 拍 |
| 第 20 章页首那句"板上跑 rNN" | 板上是哪一版只看 `board/README.md` 第一行的 md5 名片与 `build/evidence_rNN/`，本套不抄这个数 |
| `src/rtl/video/split_ctrl.v:3-7` 的文件头 | 那句"本模块目前没有被任何顶层例化"已经不成立，它就在 `pl_video_top.v:830`。**源码注释也会旧于代码** |
| `report/ARCHITECTURE.md` / `report/MODULES.md` 里的行号 | 架构结论是对的，部分 `文件:行` 有漂移，引用前先 grep 一次 |

## 6. 每章末尾都有的"你可以自己验证"

这些动作分成三档，按手上有什么挑：

| 档 | 要什么 | 典型命令 | 耗时 |
|---|---|---|---|
| 只读盘 | 一个终端 | `bash build/gates.sh`、`node src/host/doc_enc_check.mjs`、`node src/host/pipe_len_check.mjs`、各类 `grep` | 秒级 |
| 跑台架 | Vivado（xsim）在 PATH | `bash sim/run_one.sh tb_v100_raw_delay`、`tb_v86_pipe_sel`、`tb_osd_lines` | 分钟级；全量 `sim/run_sim.tcl` 几十分钟 |
| 上板 | 板子 + JTAG + 网线 | `bash build/board_verify.sh --battery --geom`、`node src/host/health_read.mjs` | 一次十几分钟 |

**永远不要为了看一条判据去动硬件**：本仓库的先量后修规矩（`00_prerequisites.md` §12）
要求先有一份能红的判据、再改代码。上板类脚本会读串口与 JTAG，跑之前确认没有别人在用
同一块板与同一个 COM 口。
