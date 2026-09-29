# `build/` —— 一条命令复现这一版，外加综合与实现报告

这里只有两样东西：**能跑的构建脚本**（`tcl/` 与几个 `.sh`/`.py`）和**这一版跑出来的报告**
（`reports/`、`bitstream/`）。报告是 Vivado 自己产出的原文，不做二次加工；脚本是复现路径，
按下面三步走就能得到同一块位流。工具版本：Vivado / Vitis 2025.2.1，器件 `xc7z020clg484-2`。

## 复现（唯一入口）

```bash
vivado -mode batch -source build/tcl/build_system_axigpio.tcl
```

它做四件事：建工程 → 收 RTL/约束/BD（清单在 `build/tcl/set_src.tcl`）→ 综合 → 实现并出位流。
跑完的产物：`build/system.bit`、`build/system.xsa`、`build/ps_app.elf`，以及
`build/reports/` 里的 `timing_summary.rpt`、`utilization.rpt`、`power.rpt`、
`route_status.rpt`、`methodology.rpt`、`cdc.rpt`。中途任何一步失败，脚本会打印它停在哪一步，
不会带着半套产物退出。

```bash
bash build/gates.sh                 # 门禁：时序/资源/端口/CDC/文档一致性（项数以脚本打印的那行为准）
VP_XSDB=<Vitis>/bin/xsdb.bat bash build/board_verify.sh --battery --geom   # 上板回读与串口命令电池
```

门禁里任何一项判红，这一版就**不采纳**、不冻结；脚本自己会念"有红项"还是"全部判定"。

## `tcl/` 里各脚本干什么

| 脚本 | 用途 |
|---|---|
| `build_system_axigpio.tcl` | **入口**，上面那条命令跑的就是它 |
| `set_src.tcl` | 文件清单：哪些 RTL/约束/BD 进这一版位流，只在这里决定 |
| `create_project.tcl`、`build_system.tcl`、`build_bitstream.tcl`、`build_pl_full.tcl`、`synth_pl_only.tcl` | 入口调用的分段步骤，单独跑是给调试用 |
| `crit_path.tcl`、`hold_paths.tcl` | 只读查询：关键路径逐条（逻辑级数 / 布线占比）、保持时间最差路径 |
| `report_mem_hier.tcl`、`cdc_who.tcl` | 只读查询：BRAM 按模块归属、CDC 发射端清单 |
| `sweep_impl_strategy.tcl`、`read_run_result.tcl` | 实现策略扫描与读数（时序采纳就是拿这两条比） |
| `ooc_newmods.tcl` | 新模块 out-of-context 快速综合，先看资源再谈集成 |
| `scan_jtag.tcl` | JTAG 链诊断（跑法是 `vivado -mode batch -source`，不是 xsdb） |
| `ps_jtag_boot.tcl` → `program_pl.tcl` → `ps_app_reload.tcl` | 上板三件套：PS 起来 → 烧 PL → 重载应用。**全程只走 JTAG，本工程的脚本从不向 QSPI/SPI flash 写入** |

## 报告怎么读

- `reports/timing_summary.rpt` 的第一段 Design Timing Summary 给 WNS / TNS / 失败端点数；
   slack 的绝对值在相邻两版之间会摆零点几 ns（放置运气），所以判断"有没有变好"要同口径复跑，
  不看单个 WNS。
- `reports/utilization.rpt` 给 Block RAM Tile、LUT、FF、DSP；BRAM 要分清是
  `RAMB36/FIFO*` 的**单元数**还是 `Block RAM Tile` 的**瓦片数**，两个数不一样。
- `reports/power.rpt` 是**估算**（没有仿真活动文件、没有实测），引用时必须说"估算"。
