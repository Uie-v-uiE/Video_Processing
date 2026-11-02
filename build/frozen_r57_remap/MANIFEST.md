# r57 冻结集 —— 2026-09-25 07:3x · 步骤② 第一次可记账的采纳：实现策略 `Performance_ExploreWithRemap`

**RTL 与 r56 逐字节相同**（`git diff` 为空）——这一版变的只有一件事：构建时用
`IMPL_STRATEGY=Performance_ExploreWithRemap`（构建脚本新增的开关，见下一节），
所以差异全部归到"实现策略"这一档，不与任何代码改动混在一起。

## 成套三件（md5 前 8 位）

| 文件 | md5 | 说明 |
|---|---|---|
| `system.bit` | **1d588efc** | build **#38**（`r57_build38_log.txt`，末行 `SYSTEM BUILD DONE`、`grep -c "^ERROR"` = 0）——**板上现在跑的就是这一颗** |
| `system.xsa` | **f987baad** | 与 bit 同一次导出 |
| `ps_app.elf` | **812790ec** | 与 r54/r55/r56 **逐字节相同**（PS 零改动，故意沿用，好把差异全归到 PL） |

## 怎么复现这一版（关键：策略要传进去）

```bash
# 1) 完整构建（日志里会出现 BUILD_STRATEGY Performance_ExploreWithRemap —— 产物自带出身）
IMPL_STRATEGY="Performance_ExploreWithRemap" \
  cmd //c "D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat" -mode batch -nojournal \
  -source build/tcl/build_system_axigpio.tcl
# 2) 门禁（14 项，含 r56 新加的"unsafe 端点不增长"）
bash build/gates.sh > build/gates_r57.txt
# 3) 下载（顺序不能反）：先 PS，再 PL，再固件
cmd //c "D:\Software\Vivado\2025.2.1\Vitis\bin\xsdb.bat" build/tcl/ps_jtag_boot.tcl
cmd //c "D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat" -mode batch -nojournal -source build/tcl/program_pl.tcl
cmd //c "D:\Software\Vivado\2025.2.1\Vitis\bin\xsdb.bat" build/tcl/ps_app_reload.tcl
# 4) 机器复验（三件套 md5 → 串口活着 → 读回口 → 仲裁八条 → 命令电池 51 条）
bash build/board_verify.sh --stream --battery
```
不设 `IMPL_STRATEGY` 就回到工具默认策略（即 r56 那一档）⇒ 这是一个**可逆**的采纳，不改任何默认值。

## 这一版换到了什么（三条判据都齐，所以这笔记得住）

| 版本 | 策略 | bit | WNS | WHS | 失败 setup/hold | Dynamic | 门禁 | 板级 |
|---|---|---|---|---|---|---|---|---|
| r56 (#37) | 工具默认 | `c15454ae` | 0.540 | 0.019 | 0 / 0 | 2.182 W | 14/14 | 八条 + 51/51 |
| **r57 (#38)** | ExploreWithRemap | **`1d588efc`** | 0.518 | **0.028** | 0 / 0 | 2.185 W | 14/14 | **八条 + 51/51**（本目录） |
| r57b (#39，独立复跑) | 同上 | `06e56edc` | 0.518 | **0.028** | 0 / 0 | 2.185 W | 14/14 | 未刷（见下） |

- **① 完整构建过 14/14**：凭据 `gates_r55.txt` 隔壁的 `gates_r56.txt`/本目录 `gates_r57.txt`，
  第二次是 `../gates_r57b.txt`（#39）。
- **② 板级全绿**：`r57_board_verify_console.txt` —— SD 29.999 fps、`lane23 verdict=OK`、
  `osd_ms_matches_tot=true`、`drop_words=0`、仲裁八条（接管 417 ms、稳占段 28/28 零翻转、
  停流交回 471 ms、交回后 0/39 不回跳、再推 96 ms、采样 100/117、原因位不可用 0）、电池 51/51 且末态=初态。
- **③ 两次独立构建同方向**：#38 与 #39 的 bit **逐字节不同**却给出同样的三个数 ⇒ 不是某一次布局的运气。
- **#39 为什么不刷板**：它相对 #38 没改任何输入，作用只是"第二次实现"来证伪运气说；
  要交付的那一颗是 #38（已刷已验）。若以后某次复跑变成要交付的件，就得重走板级。

**资源与功耗**：BRAM 92 tile / 65.71 %（不变）、Slice LUT 11102（r56 是 11108）、寄存器 8431（不变）、
端点 29527（不变）。Dynamic **2.185 W vs 2.182 W（+0.14 %）** —— 但这台工具对这份报告的
**总体置信度标的是 `Low`**（I/O 活动 >75 % 未指定、内部节点 <25 % 指定，见 `power.rpt` §1.3），
所以这个差值只说明"没有可辨识的功耗代价"，**不许写成"实测功耗"**。

**口径边界（不许越界的话）**：hold 在 r56 就已经全部 met（失败端点 0），这一版是**余量移动**，
不是"把时序修好了"；而且 §39 的路径级归因说明这一族 hold 由偏斜/布线决定（19/20 条是 0 级逻辑），
**RTL 侧无事可做**。对外可说的是：
> 最小 hold 裕量 0.019 ns → 0.028 ns（实现策略给出，两次独立构建一致）；
> 代价是 setup 裕量 0.540 → 0.518 ns、估算功耗 +0.14 %（低置信度）。

## 本目录里其他值得一看的件

- `arb_handover_r57.json` / `battery_r57.txt` / `verify_0925_0714*.txt`：板级原始样本。
- `uram_probe_console.txt`：§41 那两个 UltraRAM 探针里**唯一有结论的那一半**（`Synth 8-11376` + 96/384 RAMB36）。
- 策略变更**之前**（r56 dcp）的路径级归因在隔壁：`../frozen_r56_cdcfanout/hold_paths.rpt` 与
  `setup_paths.rpt` —— "为什么只动策略、不动 RTL"的依据在那两份里。
- `r57_build38_log.txt`：`BUILD_STRATEGY` 那一行在这。
- `read_run_timing.rpt` / `restore_strategy_console.txt` / `sweep_summary_20260925_*.txt`：
  扫描挂掉之后用来捞数、以及把工程属性恢复原状的凭据。
- `gates_r57.txt` = #38 的门禁，`gates_r57b.txt` = #39 的门禁，`gates_r57_build38.txt` 是前者的副本（防混淆）。

## 还欠的

- 眼睛清单不变：`board/README.md` 行 12~20（含用户报的 #56 两条）。
- 演示默认 bit 仍是 #23（`frozen_r23_srcseen`）——换不换是用户的决定。
- 步骤② 剩下的：`Performance_ExtraTimingOpt` 没扫；功耗要变准需要喂真实活动量或量整板；
  UltraRAM 那条已按"未证实且方向可能不成立"改写（`OVERNIGHT_LOG` §41）。
