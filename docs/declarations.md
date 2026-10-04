# 器件、工具链与板卡声明（本仓库唯一权威源）

本文件是**器件型号与工具版本的唯一权威源**。赛题 §3.3.3.1 允许 2026.1（推荐）或 2025.2，
用其他版本须在报告里说明并保证脚本可复现；§3.3.3.2 要求声明器件型号。
其余文档出现这些值时，都必须能在下面这张块里对上同一个值——
`scripts/check_repo_hygiene.sh` 的 C3 判据逐处比对，**取值不同才算红**，同值的抄写只登记条数（改抄写为引用要动 `report/` 与 `skill/`，属另一轮）。

<!-- BEGIN-AUTHORITATIVE -->
part: xc7z020clg484-2
vivado: 2025.2.1
vivado_build: 6403652
os: Windows 10.0.26300.9550
node: v24.21.0
board: RK-ZYNQ7020-F
<!-- END-AUTHORITATIVE -->

## 每个值从哪来（逐条可复核）

| 字段 | 取值 | 依据 | 复核命令（在仓库根执行） |
| --- | --- | --- | --- |
| `part` | `xc7z020clg484-2` | 构建脚本里写死的器件串；`-2` 是 PRODUCTION 速度等级 | `grep -rn "xc7z020" build/tcl/build_system_axigpio.tcl` |
| `vivado` | `2025.2.1` | 本机安装目录与所有报告头一致 | `ls /<盘>/Software/Vivado`（作者机器装在 `<盘>:\Software\Vivado\2025.2.1`，这一句是叙述不是指令） |
| `vivado_build` | `6403652` | 任一综合/实现报告头的 `Date`/`Tool Version` 行 | `head -5 build/utilization.rpt` |
| `os` | `Windows 10.0.26300.9550` | 本机 `ver` 输出（**注意**：这是 Windows 的版本号格式，不代表 Linux 环境） | `cmd //c ver` |
| `node` | `v24.21.0` | 本轮实跑 `node --version`；所有 `.mjs` 尺子用它跑 | `node --version` |
| `board` | `RK-ZYNQ7020-F` | 板卡手册封面与 `report/BOARD_PINS.md` 第一行 | `head -3 report/BOARD_PINS.md` |

## 这份声明与"版本相关事实"的关系

- 工具**行为**随版本变化的条目集中在 `skill/references/tool-version-drift/SKILL.md`，
  那份表逐行绑版本；本文件只回答"我们用的是哪一版"。
- 板卡的电气/管脚事实不在这里，见 `report/BOARD_PINS.md` 与 `board/hardware_setup.md`。
- 复现步骤（评委按哪条命令跑）在 `report/70-reproduce.md`；本文件不替代它。

## 已知边界（不伪装）

- 本报告里所有时序/资源数字都是在**上面这一版工具**上、对**这一颗器件**测出来的；
  换版本或换器件必须重跑，不能沿用数字。
- Vitis 与 Vivado 同源安装（都在 `<盘>:\Software\Vivado\2025.2.1` 树下，这是作者机器的叙述），
  PS 侧应用的本机 ELF 无法重构建（这台机器没有 `arm-none-eabi-gcc`），
  该限制记录在 `docs/build-notes.md`，不属本文件判据。
- `board/` 的板卡称呼是本队的命名习惯，不是厂商型号全称；厂商手册封面用的同样是 `RK-ZYNQ7020-F`。
