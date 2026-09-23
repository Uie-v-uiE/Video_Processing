# Zynq7020 以太网视频处理流水线（第五版：资源与入包链再优化）

[中文](README.md) | [English](README.en.md)

基于 Zynq-7000（XC7Z020）的 UDP 视频接收与实时图像处理工程。

上位机通过 **UDP** 推送 **512×300 RGB565** 视频；**PL** 完成 RGMII 收包、ARP/ICMP/UDP、offset 拼帧、图像效果、旋转、连续缩放与 HDMI 双窗输出；**PS** 仅负责控制面（串口 + AXI GPIO）。

| 项目 | 说明 |
|------|------|
| 板卡 | RK-ZYNQ7020-F（`xc7z020clg484-2`） |
| 工具 | Vivado / Vitis 2025.2.1 |

> **工具版本说明（比赛指南 3.3.3.1 要求"使用其他版本须在报告中说明并保证脚本可复现"）**：
> 指南点名的是 2026.1（推荐）或 2025.2，本工程用的是 **2025.2.1**（2025.2 的补丁版，同一主版本线）。
> 复现性由两件事保证，不靠"我们机器上能跑"：
> ① 所有构建/回归/下载入口都是**仓库相对的 Tcl 脚本**（路径用 `[file dirname [info script]]` 自适应，
>    换机器、换盘符不用改；见 `report/BUILD.md` §2 与 `sim/run_sim.tcl`）；
> ② 每一次实现都留下**成套冻结件**（报告 + bit 实体 + md5 清单，`build/frozen_*`），
>    所以别人重跑后能逐条比对数字，而不是只能信我们贴的截图。
> 已知与版本相关的行为差异只有一条并写进文档：2025.2.1 **拒绝** `ram_style = "ultramark"/"ultraram"`
> 两种拼法（`WARNING [Synth 8-11376]` 后静默退回 `auto`），所以 UltraRAM 那笔实验**没有收口**、
> 也没有当成已量化结论（`ku5p/src/rtl_exp/frame_buffer_uram.v` 文件头与 `report/OVERNIGHT_LOG.md` R23-G）。
| 源分辨率 | 512×300 RGB565 |
| 显示 | HDMI 1024×600 @ 50 MHz（左原图 / 右处理+缩放） |
| 网络 | 板卡 PL 口 `192.168.1.10:5001`，PC `192.168.1.100` |
| 控制 | AXI GPIO `@0x41200000`，UART 115200 |
| 实现结果 | WNS **+0.499 ns**、全约束满足；BRAM 64.64%、寄存器 4.08%、Slice 18.03%、Total 2.350 W |
| 开源协议 | MIT |

### 项目简介

本工程在 Zynq-7020 上实现一条完整的以太网视频处理流水线：上位机以 UDP 推送 512×300 RGB565 画面，PL 侧自研 RGMII/ARP/ICMP/UDP 协议栈与 offset 拼帧，经跨钟 FIFO 与 AXI 打包写入 **DDR 乒乓 bank**，再由提交锁在显示**消隐窗口**内把整帧原子拷进显示 BRAM；HDMI 1024×600 双窗输出——左窗原图，右窗经灰度/二值/模糊/Sobel/反色效果链、做连续缩放并可叠加 0–359° 任意角旋转（旋转只作用于右窗，左窗始终是未旋转原画面）。

网络跨钟数据经手写 Gray 码 `dc_fifo`，同钟缓存用自建 `sync_fifo`（均非厂商 IP）；画面左上角由自写 `osd_overlay` 叠加 FPS、旋转角与效果使能状态；PS 只经串口 + AXI GPIO 做控制，延迟确定、便于二次开发。

设计上值得看的四块：**自写 PL 以太网协议栈与 FIFO**（接口协议）、**DDR 乒乓 + 消隐窗口原子换帧的状态机**（逻辑与时序）、**入包写通道的吞吐建模**（为什么"深度无用、在途深度才有用"）、以及**综合行为与报告驱动的资源优化**（同一份功能，寄存器从 51.30% 降到 4.08%）。

---

## 版本说明

| 分支 | 版本 | 内容 |
|------|------|------|
| **`main`（当前）** | **第五版** | 三次综合行为改造（打包 FIFO / 显示 skid 改分布式 RAM、帧缓存地址空间按 2 的幂分块）+ 换页判据补「等本帧数据穿过 CDC」；BRAM 98.93%→64.64%、寄存器 51.30%→4.08%、Slice 99.92%→18.03% |
| `dev/night-2026-09-22`（**仅本地，待复核**） | V7.7 → V7.9 的夜间工作 | 链路健康自诊断、PS 发布握手、旋转限制到右窗、三笔 CDC 账（`eth_link`/`ASYNC_REG`/`copy_abort` 翻转同步）、KU5P 第二块板（含每秒一包 UDP 遥测 + 自研发送仲裁）；双线性插值未合入，打在 tag `v7.8-bilinear-wip`。逐轮判据见 `report/OVERNIGHT_LOG.md`，版本对应见 `report/VERSION_LINEAGE.md` §6 |
| `v4-zero-loss` | 第四版 | 入包链零丢字：写通道流水化（V6.3）+ 按 16bit lane 生成 `WSTRB`（V6.4） |
| `v3-seamless-zoom` | 第三版 | 右屏连续（无极）缩放；**拖影此时仍未解决**（量化：最新帧仅占 42~52%） |
| `v3-ghosting-attempts` | 第三版攻关过程 | 去拖影的三次未收敛尝试：BRAM 双缓冲 → DDR 三槽位管理 → DDR 双 bank 乒乓（含咨询简报与当时的 TB） |
| `v2-pl-ethernet` | 第二版 | **以太网搬进 PL**（自研硬件协议栈）、修掉旋转×窗口滤波不兼容、自建 FIFO；拖影作为已知问题记录 |
| `v1-ps-ethernet` | 初版 | **PS 以太网**（lwIP UDP → PS → DDR，PL 经 HP0 读出），PL 做特效与旋转 |

```bash
git fetch origin
git checkout main                   # 第五版（默认分支）
git checkout v4-zero-loss           # 第四版
git checkout v3-seamless-zoom       # 第三版
git checkout v3-ghosting-attempts   # 第三版的去拖影攻关过程
git checkout v2-pl-ethernet         # 第二版
git checkout v1-ps-ethernet         # 初版
```

各版之间"遇到什么问题、怎么定位、怎么解、数字是多少"见
**[`report/VERSION_LINEAGE.md`](report/VERSION_LINEAGE.md)**（含本地快照目录与远程分支的对应关系）。

### 第五版相对第四版改了什么（一句话版）

第四版功能已经正确，但器件被**综合行为**而非设计本身占满：`utilization.rpt` 显示寄存器 51.30%、
Slice 99.92%、BRAM 98.93%——三处都贴着上限，任何新功能都塞不进去。三处都不是"用法需要这么多资源"：

1. `axi_frame_saver64` 的 512×100bit 存储被综合成**触发器**（约 5.1 万个 FDRE，占整机 94%），
   而器件里 98% 的分布式 RAM 在闲置；只加 `ram_style` 属性无效（综合报 `Synth 8-7186` 拒绝推断），
   真因是"数组写与带异步复位的控制逻辑同在一个 always 块"——拆开即正确推断（FF 32904→85、LUTRAM 864）。
2. 显示帧缓 `frame_buffer_w64` 一个模块独占 **128/140 个 RAMB36**（数据量本身只需 67 个）。
   6 个写法变体逐个 out-of-context 综合实测证明：浪费与数组声明深度、位宽、分 bank 都无关，
   而是**地址空间被向上填充到 2^16 个字**；改成按 2 的幂拆两块（32768 + 8192）后实测 80 个。
3. 显示拷贝侧 `axi_frame_writer_gated` 的 skid 缓冲是同一类问题（`Synth 8-4767`），同方子解决。

另外修掉一个第四版遗留的功能缺陷：**帧尾最后 4 字节（2 个像素）偶发丢失**。根因是换页判据
`saver_idle` 对 8192 深的 CDC 与它后面两级读流水**不可见**——打包器一旦在帧的最后一个字中间
排空就翻 bank，本帧尾部还排在 CDC 里的 lane 会被写进下一帧的 bank。
该缺陷在仿真里用**双向判据**验证（旧逻辑必须复现丢尾、新逻辑必须整帧完整，缺一侧即判 FAIL）。

| 指标 | 第四版 | 第五版 |
|------|--------|--------|
| Slice Registers | 51.30% | **4.08%** |
| Slice LUTs | 37.27% | **11.87%** |
| Slice | 99.92% | **18.03%** |
| Block RAM Tile | 98.93% | **64.64%** |
| Total Power | 2.525 W | **2.350 W** |
| WNS | +0.708 ns | **+0.499 ns**（全约束满足） |
| 回归仿真 | 28/28 | **30/30** |
| 板级 | 15/30/60 fps 100% 命中 | **15→36 MB/s、60/120 fps 不限速共 22 轮，每 bank 恰好一帧、逐 lane 100.0%** |

完整逐条记录、判据与否决项：[`report/CHANGELOG_V7.md`](report/CHANGELOG_V7.md)、[`report/OVERNIGHT_LOG.md`](report/OVERNIGHT_LOG.md)。

---

## 功能

- PL 硬件网络栈：RGMII → ARP/ICMP/UDP → 帧缓
- UDP offset 协议：乱序可拼帧，坏帧丢弃
- 效果链：灰度 / 二值化 / 模糊 / Sobel / 反色（串口控制，任意旋转角下均可用）
- 任意角旋转（Q8 sin/cos 逆映射，0–359°）——**只作用于右窗**，左窗保持未旋转原画面
- 右屏连续缩放（Q8 `inv_scale`，256=1.0× ↔ 512=0.5×，可与旋转叠加）
- **自写 OSD 叠加**：左上角实时显示 FPS / 旋转角 ANG / 效果位 EN（3 倍点阵字模）
- **自建 FIFO**：同钟 `sync_fifo` + 跨钟 Gray 码 `dc_fifo`（非 IP 核，RTL 手写）
- **自建乒乓帧存**：DDR 双 bank + 提交锁 + 消隐窗口原子拷贝
- 源选择：彩条或 ETH/DDR 视频
- 上位机：UDP 推流 + 串口控制台 + 一套「不看屏幕」的 DDR 回读判据工具
- **第二块板（RK-XCKU5P-F / UltraScale+）**：同一套自研以太网栈只换 RGMII 物理层就综合/实现收敛，
  并且现在会**每秒主动发一包 UDP 遥测**（帧数/包数/字节/错包/越界/缺行/上电秒数），
  PC 侧 `node src/host/ku5p_stats.mjs` 一行显示；发送仲裁为自研（替掉厂商 mux 的一处帧内换源缺陷）。
  板级判据排在白天，台架判据与数字见 `ku5p/README.md`

---

## 目录结构

```
├── src/
│   ├── rtl/           Verilog 源码
│   │   ├── top/       system_top / pl_video_top / eth_udp_video_top
│   │   ├── eth/       自研 RGMII、ARP/ICMP/UDP、offset 拼帧、CDC、AXI 打包、乒乓提交 glue
│   │   ├── axi/       DDR 读回（消隐窗口拷贝）与诊断写通路
│   │   ├── video/     帧缓、帧缓锁、分屏、OSD、显示时序
│   │   ├── process/   效果链 + rotate/ + zoom/（逆映射与 sin/cos ROM）
│   │   ├── hdmi/      TMDS 编码与串行化
│   │   └── clocks/    MMCM 时钟生成
│   ├── ps/            裸机 UART + GPIO 控制（仅控制面）
│   ├── host/          上位机推流、串口工具与 JTAG 回读判据脚本（Node 为主）
│   └── constraints/   管脚与时序约束（rk_zynq7020.xdc）
├── sim/
│   ├── tb_*.v         41 个 testbench
│   ├── run_sim.tcl    仓库相对的 xsim 一键回归
│   ├── run_one.sh     只跑一个台架（改完 RTL 的第一道关，几十秒）
│   ├── probes/        综合行为对照实验（不是 TB：回答"这段写法会被综合成什么"）
│   └── results/       回归结果留档
├── build/
│   ├── gates.sh       一条命令读回七项门禁（可指向任一组成套冻结件复核）
│   ├── tcl/           可复现构建 / 下载 / 报告脚本
│   ├── system.bit     比特流（第五版）
│   ├── system.xsa     Vitis 硬件平台（内含 ps7_init.tcl）
│   └── *.rpt          时序 / 资源 / 功耗 / 布线 / CDC / 方法学 / 层次化资源报告
├── board/             上板说明与不看屏幕的复验方法
├── data/
│   ├── golden/        金标参考图
│   └── measured/      JTAG 回读实测输出与判据文本
├── skill/             可复用技能包（问题模式 → 判据 → 失效条件）
├── report/            架构、模块、优化、性能、根因、版本谱系与逐版变更记录
└── ku5p/              第二块板（RK-XCKU5P-F / UltraScale+）的移植：同一套自研栈，见 ku5p/README.md
```

---

## 快速开始

### 1. 生成比特流与 XSA

```bat
cd /d <仓库根目录>
set VIVADO=D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat
:: 从零建工程（PS7 + M_AXI_GP0 + AXI GPIO + 对外 HP0 + src\rtl）并出 bit / XSA / 全套报告
%VIVADO% -mode batch -nojournal -log build\build.log -source build\tcl\build_system_axigpio.tcl
```

产物：`build/system.bit`、`build/system.xsa`、`build/timing_summary.rpt`、`build/utilization.rpt`、
`build/power.rpt`、`build/route_status.rpt`、`build/cdc.rpt`、`build/methodology.rpt`。

> **可复现性已实测**：在干净克隆上直接跑上面这条命令（连 `vivado_system/` 工程都是它现建的），
> 第四版得到 WNS +0.708 / 寄存器 51.30% / BRAM 98.93%（与库内提交一致，见 `report/CHANGELOG_V6.md` §3）；
> 第五版得到 WNS +0.499 / 寄存器 4.08% / BRAM 64.64%（`report/CHANGELOG_V7.md`）。
> bit 文件因布线种子与时间戳不同而不逐字节相同。

### 2. 上板（JTAG）

```bat
set XSDBAT=D:\Software\Vivado\2025.2.1\Vitis\bin\xsdb.bat
:: 先起 PS（DDR + FCLK_CLK0=100 MHz），再配 PL，最后写 AXI GPIO
%XSDBAT% build\tcl\ps_jtag_boot.tcl   :: 自动从 build\system.xsa 里解出 ps7_init.tcl（无需手工准备）
%VIVADO% -mode batch -nojournal -source build\tcl\program_pl.tcl
%XSDBAT% build\tcl\set_src.tcl         :: 0x41200000 = 0x000B0000（SRC1=视频、zoom 开、双线性开、特效关闭）
```

### 3. （可选）下载 PS ELF —— 串口命令需要

1. Vitis 打开工作区，Platform 指向 `build/system.xsa`
2. 应用源码：`src/ps/main.c`
3. Build → Run

> 下载 bit 后 PS 会复位，需再次 Run ELF 串口才有效。仅看右屏缩放时，只下 bit 即可。

### 4. 仿真（41 个 testbench）

```bat
%VIVADO% -mode batch -nojournal -log sim\xsim.log -source sim\run_sim.tcl
:: 只跑某几个 / 带 plusargs：
::   set SIM_TB=tb_v6_ingress_integrity & set SIM_ARGS=+FULL
::   set SIM_TB=tb_v6_tail_bank         :: 帧尾换页 A/B（旧逻辑必须坏、新逻辑必须好）
::   set SIM_TB=tb_fb_roundtrip         :: 帧缓存 153600 像素逐点回读
```

### 5. 上位机推流与判据

```bat
:: Node 版（无第三方依赖），图案自描述，可不看屏幕判定链路是否丢字
node src\host\video_sender.mjs --fps 15 --test move            :: 四象限+红块（看拖影）
node src\host\video_sender.mjs --fps 30 --count 60 --test frameid
node src\host\measure_v63.mjs  --fps 15 --count 200           :: 推流→停→JTAG 回读→相位判据
node src\host\ddr_verify.mjs --frameid & node src\host\ddr_stale.mjs
```

PC 网卡 `192.168.1.100/24`，网线接 **板卡 PL 网口**。默认 15 MB/s 帧内限速。
详见 `src/host/HOST_GUIDE.md` 与 `board/README.md`。

---

## 串口命令（115200 8N1，CR+LF）

| 命令 | 作用 |
|------|------|
| `00000` | 关闭全部效果 |
| `10000` | 灰度 |
| `01000` | 二值化 |
| `00111` | 模糊 + Sobel + 反色 |
| `SRC0` / `SRC1` | 彩条 / 视频源 |
| `TH80` | 二值化阈值 |
| `ZOOM0` / `ZOOM1` | 右屏缩放 关/开（V7.7 起真正生效；`set_src.tcl` 写 1 保持旧观感） |
| `BILIN0` / `BILIN1` | 右窗双线性插值 关/开（AXI GPIO bit19）。关掉即退回最近邻，**同一条数据通路**，用来现场对比效果。**主线目前不含此项**（V7.8 收口在 250 MHz 分时读口上差 0.327 ns），完整实现在 tag `v7.8-bilinear-wip`；下 build#13 的 bit 时这一位没有连接，命令只会打印状态 |
| `SD` / `PLAY` / `STOP` / `FRAME<n>` | 挂载并打印 SD 卡帧库 / 循环回放 / 停止 / 跳到第 n 帧 |
| `FILL` / `STAT` | 诊断 / 状态 |

效果位顺序：**gray / binary / blur / sobel / invert**（bit0 在左）。ETH 收到完整帧后自动切到视频源。

---

## UDP 协议

```
[u32 小端 byte_offset][RGB565 载荷]
一帧：512×300×2 = 307200 字节
单包载荷：推荐 1392 字节（8 的倍数）。
```

板端按 offset 写帧缓；乱序可拼对；丢包丢弃，下一帧恢复。自 V6.4 起打包器按 16bit lane 驱动
`WSTRB`，分包长度不再影响正确性——但取 8 的倍数仍可少发约 0.3% 的重复 beat，并保持
「一个包不跨两个 64bit 字」这个便于分析的性质。历史上 1396 会在屏上留下均匀散布的黑点
（每帧约 111 处 4 字节洞），机理与实测见 `report/ISSUES.md` #29。

---

## 设计要点

- **DDR 乒乓 + 消隐窗口原子换帧**：入包写 `0x1000_0000 / 0x1008_0000` 两个 bank，
  `frame_commit_lock` 把「新帧就绪」锁到消隐窗口上升沿才启动整帧拷贝；
  **第五版起换页还额外要求本帧数据已全部穿过 CDC**（`ddr_bank_commit.v`），否则帧尾会落到下一帧的 bank。
  拷贝预算：一帧 38400 拍 ÷ 67200 个 axi 周期 = 0.571 拍/周期 ≈ 457 MB/s，实测未越窗。
- **入包写吞吐 = 在途深度 × 64bit ÷ 往返延迟**：一旦逐字等 B 响应，在途深度恒为 1 ⇒ 20 MB/s 封顶
  （这就是第四版之前拖影的根因）；流水化后由握手决定。**加深缓冲不能替代在途深度**——这条被实测证伪过。
- **单口显示帧缓**：分块后 80 个 RAMB36（数据量理论下限 67）；仍放不下第二份整帧，
  但剩余 ~49 个 tile 已足够放行缓存/插值这类增量功能。
- **缩放**：连续 `inv_scale`（Q8）逆映射；效果挂在右窗缩放后的数据流上（目标域窗滤），
  所以任意旋转角下 blur/sobel 都成立。
- **自写 OSD**：在 HDMI 扫描坐标上开窗叠加 `FPS=xx / ANG=xxx / EN=xxxxx`，内置点阵字模 3 倍放大；
  叠加发生在 `split_display` 之后、`rgb2dvi` 之前，不影响左右窗像素通路。
- **自建 FIFO（非厂商 IP）**：`sync_fifo.v` 同钟、`dc_fifo.v` 跨钟 Gray 码双级同步；
  存储阵列的写法刻意避开异步复位块以便正确推断 BRAM/分布式 RAM（原因见第五版一节）。
- **综合行为驱动的资源优化**：`sim/probes/` 里的对照实验回答的是「这段写法会被综合成什么」，
  这类问题写 testbench 测不出来，只能 out-of-context 综合后数单元。

---

## 文档

> 说明：仓库里出现的 `study/…` 路径是**作者自用的学习文档集，不随仓库发布**（`.gitignore` 已排除），
> 文中引用它的地方都是"延伸阅读"，评审看不到也不影响任何结论——每条结论在 `report/` 里都有出处。
> 第二块板（UltraScale+）的工程文档是 [ku5p/README.md](ku5p/README.md)，技能包入口是
> [skill/SKILL.md](skill/SKILL.md)。

| 路径 | 内容 |
|---|---|
| `report/BACKGROUND_AND_NOVELTY.md` | 选题背景、**前人做过什么**（含"未做系统检索"的边界声明）、五条创新点逐条挂证据、明确不做什么 |
| `report/CONTEST_CHECKLIST.md` | **比赛条目对照表**：指南 §3.3 每一条 → 本仓库里可核查的落点 + 一份"还没做到"的诚实清单（含 KU5P 尚未上板这一条） |
|------|------|
| [report/VERSION_LINEAGE.md](report/VERSION_LINEAGE.md) | **版本谱系与问题处置记录**：分支/提交/本地快照的对应关系，每版的问题-定位-方案-证据 |
| [report/CHANGELOG_V7.md](report/CHANGELOG_V7.md) | **第五版完整变更记录与优化对比**：逐条措施、数字、否决项 |
| [report/DEMO_SCRIPT.md](report/DEMO_SCRIPT.md) | **演示与答问脚本**：起板命令、三幕流程、每句可核对的数字与出处、被追问时的弹药、千万别说哪五句 |
| [report/CHANGELOG_V6.md](report/CHANGELOG_V6.md) | 第四版完整变更记录（V6.0→V6.4，含被证伪的方向） |
| [report/V6_ROOT_CAUSE.md](report/V6_ROOT_CAUSE.md) | 第四版根因分析：判据方法、方向纠正、修复 |
| [report/V6_BOARD_MEASUREMENT.md](report/V6_BOARD_MEASUREMENT.md) | 板级复测单：速率分档数据、观察项、已知残留 |
| [report/OVERNIGHT_LOG.md](report/OVERNIGHT_LOG.md) | 第五版工程日志：每轮的动机、判据、报告门禁数字、上板复验 |
| [report/ARCHITECTURE.md](report/ARCHITECTURE.md) | 数据通路、时钟域、带宽 |
| [report/MODULES.md](report/MODULES.md) | 模块说明 |
| [report/ROTATION_AND_EFFECTS.md](report/ROTATION_AND_EFFECTS.md) | 旋转 / 效果 / 缩放的目标域窗滤 |
| [report/OPTIMIZATION_LOG.md](report/OPTIMIZATION_LOG.md) | 时序 / 布局 / 功耗优化记录 |
| [report/PERF_REPORT.md](report/PERF_REPORT.md) | 性能与资源报告 |
| [report/ISSUES.md](report/ISSUES.md) | 问题清单（按时间，含症状速查表） |
| [report/PS_VS_PL.md](report/PS_VS_PL.md) | PS / PL 方案划分与对比 |
| [report/AI_COLLABORATION.md](report/AI_COLLABORATION.md) | 大模型协作记录：提示—判断—被数据推翻 |
| [src/host/HOST_GUIDE.md](src/host/HOST_GUIDE.md) | 上位机使用说明 |
| [skill/README.md](skill/README.md) | 技能包索引 |
| [sim/probes/README.md](sim/probes/README.md) | 综合行为对照实验（怎么跑、回答什么问题） |

---

## 许可

MIT License，详见 [LICENSE](LICENSE)。
