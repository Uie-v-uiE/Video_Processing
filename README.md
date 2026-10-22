# 多源视频流多效果变换处理系统

Zynq-7020 上的一条全硬件视频通路，加上一套能从网线和串口读回来的观测仪表。

上位机把 512×300、RGB565 的帧切成不超过 1392 字节的 UDP 报文发到 5001 端口。PL 从 RGMII 开始收包，经 MAC、UDP 过滤、按帧内偏移重组，写入 DDR 乒乓缓存；显示侧读回整帧，做缩放、任意角度旋转、双线性插值和六级效果处理，与 OSD 一起按 ×2 展开到 1024×600、59.5 Hz HDMI。像素通路不经过 PS。屏幕中间的竖缝左侧是原图、右侧是同一帧的处理图，两侧共用几何算子和固定 15 拍的效果链。

## 可复核的结果

| 结论 | 怎么看 | 读数 |
|---|---|---|
| 帧收满才提交 | 行覆盖位图、字节门与作废计数 | 8 秒推流收到 241 帧，30.01 fps；作废计数不随干净流增长 |
| 处理窗没有漏进原图 | 灰度单级 + split video 下的非灰像素计数 | 185°、30 fps 连续流下 `pane_bad=0`，计数有效 |
| 仪表能被打红 | 干净流 → 每 100 包丢 1 包 → 干净流 | 19.0 fps / 0 fps + 13.0 次作废每秒 / 22.2 fps，PASS |
| 效果链延迟不随配置变 | 完整视频台架的逐拍对齐与 OSD 时延 | 恒 15 个像素时钟；板上 PL 内部帧时延 2–16 ms |
| 帧间隔统计可读 | 串口 `link clr` → 推流 → 停流 → `link` | 新固件已编译，待上板复验 |

## 实现读数

器件 `xc7z020clg484-2`，工具 Vivado / Vitis 2025.2.1。

| 项 | 读数 |
|---|---|
| 时序 | WNS 1.341 ns，WHS 0.025 ns，TNS = THS = 0，失败端点 0 |
| 逐时钟 setup | `clk_fpga_0` 2.159 ns；`eth_rxc` 3.247 ns；`sys_clk` 14.797 ns；`clkout0_1` 3.264 ns；`clkout3` 1.727 ns |
| 资源 | LUT 14 967（28.13%），FF 9 095（8.55%），BRAM 98（70.00%），DSP 19（8.64%） |
| 功耗 / 结温 | 2.228 W 动态（总 2.406 W）/ 52.8 °C，工具估算，置信度低 |
| 仿真 | 19 支标准回归（17 支 + `eth_ingress_integrity` / `saver_tail_full`）`fail=0`；完整视频台架 C17/C25/C26 专项 PASS |
| 上板 | QSPI 写入并硬件回读校验；串口、网络遥测、故障注入、连续流和温度通过；冷启动与 `link` 待最终复验 |
| 显示 | 1024×600，59.5 Hz；源画面 512×300，30 fps |

## 构建与运行

```bash
vivado -mode batch -source build/tcl/build_system_axigpio.tcl
bash build/sim/run_msim.sh rows udp_reasm reasm_bounds udp_telemetry \
     eth_ctrl_arb eth_top_rgmii split_ctrl osd_overlay link_monitor
VP_XSDB=<Vitis>/bin/xsdb.bat VP_VIVADO_BIN=<Vivado>/bin bash board/scripts/board_flash.sh
python src/host/video_sender.py --demo --seconds 8
```

PS 应用、Vitis 平台、QSPI 固化和串口验收的完整步骤在 [`report/reproduction.md`](report/reproduction.md)；板级脚本与实测输出在 [`board/README.md`](board/README.md)。

## 目录

```text
src/              RTL、PS 固件、约束、上位机工具
sim/              单元、集成与完整视频台架
build/            构建 TCL、检查脚本、实现报告
board/            Vivado/Vitis 工程、上板脚本、实测输出
data/             测试输入、金标图像、指标表
skill/            与大模型协作提炼的技能包
report/           设计报告、验证、优化、复现、协作记录
technical_document.pdf/docx
poster.pdf/png
```

## 面向评委

- 技术文档：[`technical_document.pdf`](technical_document.pdf) / [`report/design-report.md`](report/design-report.md)
- 海报：[`poster.pdf`](poster.pdf)
- 验证与判据：[`report/verification.md`](report/verification.md)
- 时序与资源优化：[`report/optimization.md`](report/optimization.md)
- 复现：[`report/reproduction.md`](report/reproduction.md)
- 局限：[`report/limits.md`](report/limits.md)
- 大模型协作：[`report/llm-collaboration.md`](report/llm-collaboration.md)
- 技能包：[`skill/README.md`](skill/README.md)

## 边界

遥测时延只覆盖 PL 内部（帧提交到开始扫描），不是玻璃到玻璃。RGMII 发侧在 HR bank 上没有 ODELAYE2，0° 转发仍有约 0.845 ns 的 TskewT 保持缺口；90° 与 −45° 都被否决。BRAM 70% 由整帧缓存决定，512×300 以上画幅放不下。185° 细线已由 RTL 和台架闭环，人眼目视仍建议做一次。逐条说明在 [`report/limits.md`](report/limits.md)。

[English version](README_EN.md)
