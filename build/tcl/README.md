# Vivado / xsdb 脚本：现在到底跑哪几条

> 这一页只写**今天还在用**的那几条，并把"看着能用、其实会骗人"的那几条点名。
> 历史上这里还推荐过 `create_project.tcl` + `build_bitstream.tcl` 那套 V7 流程 —— 那两条已经
> 不能描述现在的设计（工程里有 BD、有 AXI GPIO、有 `system_top`），文件先留着是因为
> `docs/log/CHANGELOG_V7.md` 与 `ISSUES.md` 的若干条目按名字指它们；**不要**拿它们当构建入口。

## 1. 构建（唯一规范入口）

```bat
set VIVADO=D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat
%VIVADO% -mode batch -source build\tcl\build_system_axigpio.tcl
```

从仓库根跑（脚本内部全是相对路径）：建工程 + 建 BD → 综合 → 实现 → `build/system.bit` 与
`build/system.xsa` → 顺手落四份报告（`timing_summary.rpt` / `utilization.rpt` /
`methodology.rpt` / `cdc.rpt`）。跑完再 `node build/ps_app.mjs` 出 `build/ps_app.elf`。

⚠ **两个"根目录少解析一层"的陷阱脚本**：`build_system.tcl`、`build_pl_full.tcl` 用
`[file dirname [info script]] ..`（少一层 `..`），`add_files` 指向 `build/src/...` 而**报错之后仍然 exit 0**
（ISSUES #22 / #41 记过两次）。同一类 bug 在 `create_project.tcl`、`synth_pl_only.tcl` 里也还在。
⇒ 要构建只认 `build_system_axigpio.tcl`；跑完必须自己去 `build/` 里核对报告的时间戳，
**不要相信退出码**。

## 2. 上板（JTAG only —— 永不写 QSPI/SPI flash）

| 脚本 | 用途 |
|---|---|
| `ps_jtag_boot.tcl` | 一条龙：`rst -system` → `ps7_init` → 编 PL → 下 elf → `con`（**开机第一命令**） |
| `program_pl.tcl` | 只重编 PL 位流（`ps_app.elf` 不动） |
| `ps_app_reload.tcl` | 只换 PS app（PL 不动） |
| `program_system.tcl` / `program_and_check.tcl` | 上面两件的组合 / 带读回检查 |
| `scan_jtag.tcl` | JTAG 链扫不到时用（DAP 全 0 就是板子侧的事，见 `docs/BUILD.md`） |
| `build/board_verify.sh` | 刷完之后"机器能判的那一半"验收（有 `RESULT … PASS/FAIL nred=` 总判定，#69） |

⚠ `program_board.tcl` 属 V7 那条纯 PL 流程（下载 `output/video_pipeline.bit`），那个 bit 已从仓库删除
⇒ 这条路径现在**跑不通**，留着只为对照旧文档里的数字。

## 3. 报告与探针（按需，都不改设计）

`crit_path.tcl`（关键路径）、`hold_paths.tcl`（hold 违例清单）、`cdc_who.tcl`（CDC 违例归因；
门禁里"`cdc.rpt` Critical 行 = 基线那几行，配对不新增、unsafe 不增长"那一项用的就是构建落下的 `build/cdc.rpt`）、
`report_mem_hier.tcl`（存储层次）、`read_run_result.tcl`（读 run 状态）。`ooc_newmods.tcl` / `sweep_impl_strategy.tcl` 是
`docs/OPTIMIZATION_LOG.md` §5 那次"实现策略扫描"用的工具，那一份 A/B 对比脚本
（仓库里曾有的 `wip_r65_ab.sh`）已经退役，扫描结论本身在 OPTIMIZATION_LOG 里。

## 4. 一次性修复脚本（别当模板抄）

`apply_cdc_report.tcl`、`fix_bd_and_top.tcl`、`rebuild_opt.tcl`、`rebuild_zoom_out.tcl` 这四条
当年只修某一个版本的 BD/顶层，没有任何脚本或现行文档调用它们，留在这里只为可追溯；
`rebuild_cdc_fix.tcl` 在 `docs/BUILD.md` 里被点名，所以也留着。**新工作不要基于它们改。**

`uram_presence.tcl` / `uram_probe.tcl` / `uram_sites.tcl` 是"7 系列有没有 URAM"那次探针
（结论：没有），`build/uram_probe/` 这条路径被 `src/host/doc_enc_check.mjs` 的白名单写死，
所以**不能整目录删掉**。

## 5. 仿真

`sim/run_one.sh <tb名>`（xvlog + xelab + `xsim -R snap`，单台架，编译清单与全量同口径，
并在**编译前**记 `top_md5`/`tb_md5`/`rtl_md5` 三枚指纹 —— 门禁第 15 项就靠它把报告与树绑在一起）；
`sim/run_sim.tcl` 跑 L1 全量（同一个 glob 清单）。
