[English](README.en.md)

# Zynq 实时视频图像处理与逐像素对照显示

一颗 Zynq-7020（`xc7z020clg484-2`）在做这件事：网口、SD 卡或片内图卡送来 512×300 的
视频流，PL 侧完成缩放、旋转与七级图像处理，并以 1024×600 的 HDMI 输出。屏幕上任何
一条竖线以左是**未经处理**的画面、以右是**同一坐标系下处理后**的画面，分割线可以固定、
自动扫描，也可以贴在图像域里跟着旋转缩放一起走。

这个"同帧逐像素对照"是本项目的立足点：它既是一种显示方式，也是一台测量仪器——
边缘条带、一行错位、一个越界格子，都能在没有任何额外探针的情况下被肉眼看见，
也能被同一套几何关系直接算出来。

## 特性

- **三路片源**：千兆 RGMII 收 UDP 视频流、SD 卡本地播放（FAT32 簇链自研解析）、片内动态
  测试图卡；仲裁与回退在 PL 里完成，PS 只发命令。
- **几何通路**：八档缩放（定点逆序比例，不做实时除法）、多档旋转（正弦/余弦 ROM + 象限折叠），
  最近邻与双线性插值可运行时切换。
- **效果链**：灰度、反色、3×3 均值模糊、锐化、Sobel 边缘、阈值二值化（含判决反相位）、
  3×3 腐蚀/膨胀，共九位控制字，逐级可旁路，整链固定 15 级流水。
- **对照显示**：0–100% 任意分割线、左/右互换、2 像素标记线可关；原图抽头用行延迟环与
  处理链对齐到同一拍同一列。
- **屏上状态**：OSD 四行显示片源、角度、缩放档、效果码、分割线位置、帧率、时延、温度。
- **在线自诊断**：收包/丢包/坏字/CRC 校验、乒乓 bank 状态、链路内时延，硬件计数 + OSD +
  串口可读回，拔线与拔卡后的行为可核对。

## 复现路径

```bash
# 1) 建工程、综合、实现、出比特流（Vivado 2025.2.1，命令行）
vivado -mode batch -source build/tcl/build_system_axigpio.tcl
# 2) 二十项门禁：两个大台架 + 时钟/资源/端口/文档一致性检查
bash build/gates.sh
# 3) 上板（JTAG；本工程不向 QSPI 烧写）+ 串口命令电池 + 实测回读
bash build/board_verify.sh --battery --geom
```

命令表、寄存器映射、逐项判据与失败时看哪个文件，见
[docs/COMMANDS.md](docs/COMMANDS.md)、[docs/BUILD.md](docs/BUILD.md)、
[board/README.md](board/README.md)。

## 数据

最近一次门禁全绿的冻结集 = r75：二十项全通过，实现后 WNS +0.287 ns。
资源占用、功耗、帧率与时延的完整表格（含每一项出自哪份报告）见
[docs/PERF_REPORT.md](docs/PERF_REPORT.md)，留档在 `build/` 与 `build/evidence/`。

## 目录

| 目录 | 内容 |
|---|---|
| `src/rtl/` | RTL，按 `top / video / process / eth / hdmi / clocks / axi / util` 分层 |
| `src/ps/` | PS 侧裸机固件（串口命令解析、寄存器配置、SD 播放、自诊断读回） |
| `src/host/` | PC 侧工具与自检脚本（发流、回读、文档与命令表一致性检查） |
| `sim/` | 台架与两个 runner；`tb_v98_top_seam` 例化整个视频顶层，是几何与显示的主尺子 |
| `build/` | 构建与门禁脚本、`tcl/`、综合实现报告、`rNN_gates.txt` 与 `evidence/` 留档 |
| `board/` | 上板操作说明、验收表、串口捕获 |
| `data/` | `golden/` 参考图，`measured/` 实测数据 |
| `skill/` | 大模型协作沉淀的技能包（每项四段：适用场景 / 使用方法 / 已验证效果的凭据 / 失效条件；条目数以 `skill/README.md` 自己那行为准） |
| `docs/` | 设计报告、优化记录、命令表、复现说明 |
| `docs/log/` | `ISSUES.md` 与 `OVERNIGHT_LOG.md`（追加式工作记录） |

对应关系与赛程推荐结构的差异已在表中说明；`docs/log/ISSUES.md` 与
`docs/log/OVERNIGHT_LOG.md` 是只追加的历史记录，不重写。

## 阅读顺序

第一次接触这个工程：[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)（框图与模块职责）→
[docs/PS_VS_PL.md](docs/PS_VS_PL.md)（软硬件怎么切分）→
[docs/BACKGROUND_AND_NOVELTY.md](docs/BACKGROUND_AND_NOVELTY.md)（为什么这么做）→
[board/HANDS_ON.md](board/HANDS_ON.md)（动手看什么）。

## 许可

MIT，见 [LICENSE](LICENSE)。
