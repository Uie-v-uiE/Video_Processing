# r59a 冻结件（seam label tap）—— 2026-09-25 13:34 构建 / 13:43 机器复验

一句话：**缝的"选哪一路"这一格，从比内容旧 9 列的标签（`x_d[11]`）改成与两个像素抽头同一级的
`x_sel`（`MIX_D = 3 + 1 + 1 + u_pipe.LATENCY` 推出来，不再抄字面量）**，顺手把那条 2 像素蓝线
变成可以关掉的 `marker`。OSD 一个像素都没动（它的坐标仍是 `x_d11`）。

这一版**只动了标签这一半**：几何统一（4b 的第 1~3 步）在 r59b，`split_ctrl` 上顶层在 r59 步 5-6。
动机与三次尺子错的复盘在 `report/ISSUES.md` 的 **#68**，判红却不上升为链子红那一族在 **#69**。

## 三件套（务必与下面每一条凭据同一次构建）

| 件 | md5（前 8） | 来源 |
|---|---|---|
| `system.bit` | `f2ebcd4a` | 本目录，构建 #43（`build/r59a_build43.log`，13:33:39 落盘） |
| `system.xsa` | `d6544177` | 本目录，同上（13:34:17 报告时间戳） |
| `ps_app.elf` | `9144bb40` | **与 r58 同一份**（本轮没改 PS 侧） |

## 门禁 14 项（`gates_r59a.txt`，`GATES: ALL PASS`）

| 项 | 本版 | 上一版（r58，`../frozen_r58_ethsdtest/`） | 阈值 |
|---|---|---|---|
| WNS | **+0.262 ns** | +0.321 ns | ≥ 0 |
| WHS | **+0.046 ns** | +0.028 ns | ≥ 0 |
| 失败 setup / hold 端点 | 0 / 0 | 0 / 0 | == 0 |
| BRAM | 92 tile / 65.71 % | 92 / 65.71 % | ≤ 97 % |
| Slice LUT | 11143 / 20.95 % | — | ≤ 98 % |
| Slice 寄存器 | 8470 | — | 记录用 |
| Dynamic | 2.184 W | — | 与前次同量级 |
| methodology CRITICAL | 0 | 0 | == 0 |
| 布线错误网线 | 0 | 0 | == 0 |
| `cdc.rpt` Critical 行 | 3（基线 4，配对集合不新增、Unsafe 不增长） | 4 | 见 `build/CDC_BASELINE.txt` |
| 端口宽度警告 8-689 | 0（`ports_check.txt`） | 0 | == 0 |
| 多驱动 net 8-685x | 0 | 0 | == 0 |
| 顶层接线 | `CHECK PORTS: instances=81 modules=76 width_compared=548 violations=0` | — | violations=0 |

⚠ 两处必须说清楚的账（不是"改进"）：
1. **WNS 从 0.321 退到 0.262**。原因是左窗 skid 从 16 级被 `SB = MIX_D + 1 = 21` 撑长 ⇒ 混色级
   多一级选择，路径变深。仍为正、仍过门禁，但这是**代价**，不能写成"优化"。
2. 门禁日志自己标的：`基线里有而本版没有：eth_rxc>clk_fpga_0（原因未查证，不算改进）`、
   `同配对端点数增长：clk_fpga_0>clkout0_1(17→74)（记录用，不判红）`。

## 台架（L1 全量，`l1_r59a_final_console.txt`）

`SIM DONE pass=64 fail=0`（构建之后又改过台架，所以这一条是**改完之后重跑**的那一次）。
本轮新增/改动的三份：

* `tb_v99_unisim_sim`：占位时钟模型自己的判据（分频比从例化参数读回，量出 50/250/200 MHz）。
* `tb_v100_raw_delay`：4 行环形行缓存（T1 稳态逐格对齐 / T5 跨槽位回绕 / T3 de 与数据等长 /
  T4 `LINES=0` 组合直通 / T6 覆盖面不许空跑）。
* `tb_v97_seam_scan`：S7a（`marker=0` ⇒ 一列蓝都不许有）、S7b（关线不许改选择逻辑）、
  S7c（故意让 `x_sel` 落后 9 列 ⇒ 蓝线必须落在 520/521）、S8（内容分界同样跟着 `x_sel`）。
* `tb_v98_top_seam`（顶层第一份台架，`tb_v98_rerun.out`）：`RESULT PASS`，
  其中 `PROBE fb_wr_pulses=115200 = 3×38400` 证明 DDR→帧缓存在仿真里真的搬完三帧，
  而 `OBS C-tap 首格偏差 8`、`NOTE C1/C2` 写明**内容对齐这一条本轮不判定**、
  以及"没对上的是台架的映射式而不是硬件"（证据：`bad_l=459452` 与"Δcol 超量程 1182618 点"互相矛盾）。

## 板级机器复验（`r59a_board_console2.txt`，`RESULT board_verify PASS（判红的步骤：0）`）

* 仲裁八条全绿：`PASS V1 基线归 PS 静默 3s 内 owner_eth=1 的样本 0/8`、
  `PASS V0 采样密度 全程 98 / 期望约 117`、`V2 接管 1254 ms`、`V4 交回 135 ms`、`V6 再推 364 ms`。
* 串口命令电池 59 条全过，且**跑完回到初态**（`en=00 thr=80 src=1 zoom=1 bilin=1 zsel=4 zman=0 gm=0.00 mode=0`）。
* **第一次跑（13:35，`r59a_board_console.txt` + `verify_0925_1335.*`）是判红的**：V1 `0/0`。
  两份 arb json 都留在本目录里并排对账 —— 那次红的是判据的时间起点与采样链路爬坡抢跑
  （机器上同时跑着综合与一台 xsim），修法与证据见 **ISSUES #69**。同一份 bit、同一块板，改判据之后 8/8。

## 还欠什么（不许当成已完成）

1. **眼睛判据**：`board/README.md` 第 22 行（缝左右 10 列有没有暗带）、第 21/21b 行。
   这是 #68 那条修改**唯一**能证明它真的把暗带消掉了的证据，脚本替代不了。
2. **C1/C2 内容判据**：先让台架那两个自相矛盾的计数器一致（任务 #54），再把
   "屏上就是我喂的那张坐标图" 变成硬判据；在那之前"标签与内容同列"只有第 1 条那一种凭据。
3. `Split:50 %(Auto)` 那一格仍然是几何参数算出来的固定值（缝还没有执行者）⇒
   `CONTEST_CHECKLIST` 里"分割线 0~100 % 可调"这条主张**继续不写**。

## 复现

```
bash sim/run_one.sh tb_v97_seam_scan          # 或 vivado -mode batch -source sim/run_sim.tcl 跑全量
bash build/gates.sh                            # 14 项门禁（读的就是本目录那几份 .rpt 的同一次构建）
bash build/board_verify.sh --stream --battery  # 机器那一半的板级复验（末尾一行 RESULT board_verify …）
```
