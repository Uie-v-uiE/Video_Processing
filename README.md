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
- **屏上状态**：OSD 五行（`N_LINES=5`）显示片源、角度、缩放档与来源、效果码、分割线位置、
  帧率、时延、温度。
- **在线自诊断**：收包/丢包/坏字/CRC 校验、乒乓 bank 状态、链路内时延，硬件计数 + OSD +
  串口可读回，拔线与拔卡后的行为可核对。

## 复现路径

```bash
# 1) 建工程、综合、实现、出比特流（Vivado 2025.2.1，命令行）
vivado -mode batch -source build/tcl/build_system_axigpio.tcl
# 2) 门禁：时序/资源/端口/CDC/文档一致性 + 两个钉 md5 的整屏台架（项数以脚本自己打印的为准）
bash build/gates.sh
# 3) 上板（JTAG；本工程不向 QSPI 烧写）+ 串口命令电池 + 实测回读
bash build/board_verify.sh --battery --geom
```

命令表、寄存器映射、逐项判据与失败时看哪个文件，见
[docs/COMMANDS.md](docs/COMMANDS.md)、[docs/BUILD.md](docs/BUILD.md)、
[board/README.md](board/README.md)。

## 数据

一句先说清楚的话：**"板上现在跑的那一版"与"最近一套全绿冻结的那一版"不是同一版**，两个都给。

- 最近一套**门禁全绿且已冻结**的是 r75：那一轮 19 项全通过（门禁脚本现在长到 20 项，
  多出来的是当晚后加的检查），实现后 setup WNS **+0.287 ns**、BRAM 97.5 tile / 69.64 %。
  凭据：`build/r75_gates.txt` 与 `build/evidence_r75/`。
- 板上当前是 **r87**（**未冻结**）：WNS +0.152 ns、失败端点 0 / 50885，LUT 14363（27.00 %）、
  FF 8075（7.59 %）、BRAM 95 tile（67.86 %）、DSP 19（8.64 %）——逐项数值与它们出自哪份报告，
  统一在 **[data/metrics.csv](data/metrics.csv)**，报告原件在 `build/reports/r87_*.rpt`。
  它没冻结的原因写在 [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md)：顶层台架那 128 条逐像素判定里
  有 1 条是**故意留红**的（`C5c`，对应未修的 #98）。
- 走势与"为什么某一版被否掉"在 [docs/OPTIMIZATION_LOG.md](docs/OPTIMIZATION_LOG.md)；
  本报告不复制数值，只给指路——同一份数字抄在两处一定会漂（这条本身是一次真实事故的结论，#133）。

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

### 与赛程推荐目录（§3.3.5.4）的对照

本仓库按"交付文档 / 工作记录 / 本地学习件"三类摆放，与推荐结构不同 ⇒ 按指南要求在此给对照。
交出去的包由 `bash build/make_submission.sh` 一条命令生成（`../final_submission/`），
它做的三件事是**改名**而不是**改内容**：`docs` 那一层改名成 `report`（连文档里的指路一起改）、
台架按职责命名、报告展平进 `build/reports`。

| 推荐目录 | 仓库里在哪 | 包里在哪 |
|---|---|---|
| `README.md` 项目简介 + 复现步骤 | `README.md`（中）/ `README.en.md`（英） | 同名 |
| `src/` 设计源码 | `src/rtl/**`（PL）+ `src/ps/**`（裸机固件）+ `src/constraints/**` | 同名 |
| `sim/` 仿真脚本与结果 | `sim/**`（仓库里的全部台架） | 支撑交付结论的那几支 + `sim/NAMES.md`（新旧名对照）；判据结果在 `build/reports` |
| `build/` 构建脚本 + 综合实现报告 | `build/tcl/**`（入口 `build_system_axigpio.tcl`）、`build/gates.sh`、各轮留档 | `build/tcl/**` + `build/reports`（展平后的 .rpt/.txt）+ `build/bitstream/`（板上那一版 .bit/.xsa/.elf） |
| `board/` 上板工程与实测输出 | `board/**`（操作卡、验收表、JTAG 脚本） | 同名（`board/VERIFY_r87.md` 是 36 行全功能验收表） |
| `data/` 测试数据与参考结果 | `data/golden/**`、`data/measured/**`、`data/metrics.csv` | 同名 |
| `skill/` 技能包 | `skill/**`（`README.md` 是索引，每张卡固定六节） | 同名 |
| 设计报告 + 协作记录（推荐名 report） | 仓库里的 docs 目录（交付文档）与它下面的 log 子目录（工作记录） | 包里的 report 与它下面的 log |
| 不进包 | docs 下的 study 子目录（作者自用学习材料，`.gitignore` 已挡）、`vitis/`、`vivado_system/`、`sim_work/` 等工具生成物 | — |

**不随包的东西都有理由，且理由写在包里**：`../final_submission/_pruned.txt` 逐条列出"这次剪掉了谁、
按哪条判据剪的"；包内所有"路径式指路"由导出器自检，任何一条指不到包内文件就**拒绝落盘**（不通过的
包不存在，比一个有死链接的包好）。

## 阅读顺序

第一次接触这个工程：[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)（框图与模块职责）→
[docs/PS_VS_PL.md](docs/PS_VS_PL.md)（软硬件怎么切分）→
[docs/BACKGROUND_AND_NOVELTY.md](docs/BACKGROUND_AND_NOVELTY.md)（为什么这么做）→
[board/HANDS_ON.md](board/HANDS_ON.md)（动手看什么）。

## 许可

MIT，见 [LICENSE](LICENSE)。
