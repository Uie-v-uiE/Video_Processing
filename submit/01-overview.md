# 概述

## 这是什么系统
一块 Zynq-7020（器件 `xc7z020clg484-2`，出处 `build/utilization.rpt` 报告头那一行
`| Device       : xc7z020clg484-2`）上的实时视频图像处理通路。几何、滤波、显示全部在 PL 完成；
PS 只发命令、读计数、把 SD 卡上的帧 DMA 进自己那块 DDR，不中转 ETH 视频字节
（`report/ARCHITECTURE.md` §3；`src/ps/main.c` 文件头第 2 行「PS control plane + SD 卡本地回放。
UDP 视频数据通路仍然整个在 PL」）。

## 输入 → 处理 → 输出（一句话）
`RGMII 上的 UDP 视频流` / `SD 卡裸帧` / `PL 自绘动态图卡` 任一路进来 → PL 逆映射做缩放与旋转、
固定 15 拍的效果链做滤波 → HDMI 1024×600 上屏，并且一条竖线以左是未处理画面、以右是同一坐标系下
处理后的画面。链路图与关键常数（源画幅 512×300 RGB565、显示时序 `H_TOTAL 1344 / V_TOTAL 625`）
记于 `report/ARCHITECTURE.md` §1 与 §4。

## 演示时观众看到什么
按 `report/DEMO_SCRIPT.md` 的顺序，屏幕与串口自己给现象：
- 左上角 OSD 第 0 行 `1024X600 FPS:59 SRC:ETH`——`SRC:` 写的就是屏上真的那一路
  （`report/DEMO_SCRIPT.md` §0 第 3 步；OSD 共 5 行，`N_LINES = 5` 见 `src/rtl/video/osd_overlay.v:19`）。
- 拔网线后画面在 ≤0.5 s 自己让位到 SD、`SRC:` 变成 `SD`（`report/DEMO_SCRIPT.md` §1）。
- `zoom` 时画面逐格放大、`rot auto 1` 时画面开始转、屏上 `Zoom:` 同步变并带 `(Fit)`
  （`report/DEMO_SCRIPT.md` §2）。
- `pipe` 一位一位把同一帧当场变边缘、变二值、变二值+腐蚀（`report/DEMO_SCRIPT.md` §3）。
- 串口敲 `stat` 回一行 `[STAT] ctrl thr=… src=… zoom=… …`（`report/DEMO_SCRIPT.md` §0 第 2 步）。

## 三个可复核的能力（各指一个凭据）
1. **同帧逐像素对照 = 一台仪器**：分割线两侧的错位、少列、越界填黑不用探针就能被肉眼看见，
   也能被同一套几何算成数字。凭据是顶层台架 `sim/tb_v98_top_seam.v` 的 C 系列判据——它按
   "每行只应有一段连续画面""每格带回自己的源行号/列号"这类**形状**来判，历史上抓到过 #102、#68
   两族缺陷（这段记于 `report/BACKGROUND_AND_NOVELTY.md` §3 第 1 条）。
2. **链路健康由硬件自计数、三方对账**：同一组计数器同时上 OSD、经 AXI GPIO 被 JTAG 读回、
   也能用串口命令清可读（`report/BACKGROUND_AND_NOVELTY.md` §3 第 2 条）。SD 帧率的板读数
   29.8 – 30.0 fps 落在 `data/metrics.csv`（第 12 行「SD 本地播放帧率,实测,29.8 – 30.0,fps,
   …100 帧滑窗读数」）。
3. **三片源自适应仲裁是可逆的**：ETH ⇄ SD 让位在无人干预下发生，判据不是"曾收过包"（那是粘性命，
   ARP 就触发），而是"最近真有帧且量它的那个时钟还准"。凭据 `src/rtl/util/src_arb.v`
   与其台架 `sim/tb_v796_src_arb.v`（职责与例化 `pl_video_top.v:421` 记于 `report/MODULES.md`，
   取舍与反面判据记于 `report/BACKGROUND_AND_NOVELTY.md` §3 第 6 条）。

【未实测】：当前位流上的端到端时延数字。查 `data/metrics.csv`——第 20 行「端到端时延,未报,…待复测」
只给读数出口（OSD 的 Latency lane、JTAG 回读），没填复核过的值；第 25 行的 33.34 ms 是某一轮
PERF 记录，未与当前位流对账。

## 本章依据的产物
- `README.md`
- `report/ARCHITECTURE.md`
- `report/BACKGROUND_AND_NOVELTY.md`
- `report/DEMO_SCRIPT.md`
- `src/ps/main.c`
- `src/rtl/video/osd_overlay.v`
- `data/metrics.csv`
- `build/utilization.rpt`
