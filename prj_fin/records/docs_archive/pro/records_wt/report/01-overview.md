# 概述

这一章按四步读：这颗板子做什么、数据怎么走、关键数字是多少、哪里还做不到。
每个数字后面都跟着它落在盘上的那份件；没有件支撑的话写在第 5 节，不混在第 3 节里。

## 1. 这颗板子做什么

一块 Zynq-7020（器件 `xc7z020clg484-2`，出处 `build/utilization.rpt` 报告头那一行
`| Device       : xc7z020clg484-2`）上的实时视频图像处理通路。几何、滤波、显示全部在 PL 完成；
PS 只发命令、读计数、把 SD 卡上的帧 DMA 进自己那块 DDR，不中转 ETH 视频字节
（软硬件划分见 `report/architecture.md` §3；`src/ps/main.c` 文件头第 2 行写的是同一件事：
「PS control plane + SD 卡本地回放。UDP 视频数据通路仍然整个在 PL」）。

输出是 1024×600 的 HDMI 画面，画面里有一条竖缝：缝一侧是未处理的画面，另一侧是同一坐标系下
处理后的画面，两侧逐像素对齐、同一拍送到缝上。这条对照既是演示效果，也是一台仪器——错位、少列、
越界填黑这类几何问题不需要探针就能被看见，也能被同一套坐标关系算成数字。

## 2. 数据怎么走

`RGMII 上的 UDP 视频流` / `SD 卡裸帧` / `PL 自绘动态图卡` 任一路进来 → PL 逆映射做缩放与旋转、
固定 15 拍的效果链做滤波 → HDMI 1024×600 上屏。三路在"进帧缓存"这一层由仲裁器选一路，
选中的那一路经行缓存与效果链后与分割线合成。完整链路图与关键常数（源画幅 512×300 RGB565、
显示时序 `H_TOTAL 1344 / V_TOTAL 625`）记于 `report/architecture.md` §1 与 §4，
逐模块的端口与被例化关系记于 `report/modules.md`。

演示时屏幕与串口自己给现象，操作顺序按 `report/demo_script.md`：

- 左上角 OSD 第 0 行 `1024X600 FPS:59 SRC:ETH`——`SRC:` 写的就是屏上真的那一路
  （`report/demo_script.md` §0 第 3 步；OSD 共 5 行，`N_LINES = 5` 见 `src/rtl/video/osd_overlay.v:19`）。
- 拔网线后画面在 ≤0.5 s 自己让位到 SD、`SRC:` 变成 `SD`（`report/demo_script.md` §1）。
- `zoom` 时画面逐格放大、`rot auto 1` 时画面开始转、屏上 `Zoom:` 同步变并带 `(Fit)`
  （`report/demo_script.md` §2）。
- `pipe` 一位一位把同一帧当场变边缘、变二值、变二值+腐蚀（`report/demo_script.md` §3）。
- 串口敲 `stat` 回一行 `[STAT] ctrl thr=… src=… zoom=… …`（`report/demo_script.md` §0 第 2 步）。

## 3. 关键数字

| 数字 | 值与单位 | 落在哪份件上 |
|---|---|---|
| 器件 | `xc7z020clg484-2` | `build/utilization.rpt` 报告头 |
| 片源画幅与格式 | 512×300 RGB565 | `report/architecture.md` §4 |
| 显示画幅与时序 | 1024×600，`H_TOTAL 1344 / V_TOTAL 625` | `report/architecture.md` §4 |
| 效果链固有延迟 | 15 拍 | `report/architecture.md` §4、`src/rtl/process/proc_pipeline.v` |
| OSD 行数 | 5 行（`N_LINES = 5`） | `src/rtl/video/osd_overlay.v:19` |
| SD 本地播放帧率 | 29.8 – 30.0 fps | `data/metrics.csv` 第 12 行 |
| 端到端时延 | 未报（见第 5 节） | `data/metrics.csv` 第 20 行 |

`data/metrics.csv` 是全仓只有这一份的数字表，两处与本节直接相关的原文：
第 12 行「SD 本地播放帧率,实测,29.8 – 30.0,fps,…100 帧滑窗读数」；
第 20 行「端到端时延,未报,…待复测」。表里其余各行的取舍口径写在 `data/README.md`。

## 4. 三项能被第三方复核的主张

1. **同帧逐像素对照 = 一台仪器**：分割线两侧的错位、少列、越界填黑不用探针就能被肉眼看见，
   也能被同一套几何算成数字。凭据是顶层仿真台架 `sim/tb_v98_top_seam.v` 的 C 系列检查——它按
   "每行只应有一段连续画面""每格带回自己的源行号/列号"这类**形状**来判，以往运行里暴露过
   `report/log/issues.md` 的第 102 条与第 68 条两族缺陷（这条设计的完整说法见
   `report/background_and_novelty.md` §3 第 1 条）。
2. **链路健康由硬件自己计数、三方可对账**：同一组计数器同时上 OSD、经 AXI GPIO 被 JTAG 读回、
   也能用串口命令清可读（`report/background_and_novelty.md` §3 第 2 条）。SD 帧率的板读数落在
   `data/metrics.csv` 第 12 行（原文见上一节）。
3. **三片源自适应仲裁是可逆的**：ETH ⇄ SD 让位在无人干预下发生，依据不是"曾收过包"（那种条件
   一旦成立就不会回落，ARP 一个包就能触发），而是"最近真有帧且量它的那个时钟还准"。
   凭据 `src/rtl/util/src_arb.v` 与其仿真台架 `sim/tb_v796_src_arb.v`（职责与例化点
   `src/rtl/top/pl_video_top.v:421` 记于 `report/modules.md`，取舍与反面对照记于
   `report/background_and_novelty.md` §3 第 6 条）。

## 5. 限制与未实测

- 【未实测】：当前位流上的端到端时延数字。查 `data/metrics.csv`——第 20 行「端到端时延,未报,…待复测」
  只给读数出口（OSD 的 Latency lane、JTAG 回读），没填复核过的值；第 25 行的 33.34 ms 是以往某一次
  性能记录的数，未与当前位流对账（四处口径落后的登记见 `build/evidence/r121_note_metrics.txt` 第 2 行）。
- 整屏逐像素检查里有一条**写明过的未通过项** `C5c`（帧头若干行的读侧绕回），重跑这条检查时它一直报未通过、不掩盖，
  现象与已定位到哪一步见 `report/08-limits.md` §1 与 `report/known_issues.md` §一 第 1 条。
- 本章只讲"这颗板子现在做什么"。器件版本、构建命令与逐条复现步骤在 `report/70-reproduce.md`；
  还没做到的事集中在 `report/90-open-items.md`。

## 本章依据的产物
- `README.md`
- `report/architecture.md`
- `report/background_and_novelty.md`
- `report/demo_script.md`
- `report/modules.md`
- `report/08-limits.md`
- `report/known_issues.md`
- `report/log/issues.md`
- `src/ps/main.c`
- `src/rtl/video/osd_overlay.v`
- `src/rtl/process/proc_pipeline.v`
- `src/rtl/top/pl_video_top.v`
- `data/metrics.csv`
- `data/README.md`
- `build/utilization.rpt`
- `build/evidence/r121_note_metrics.txt`
