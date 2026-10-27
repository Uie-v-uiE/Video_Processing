# 器件、工具链与板卡声明（本仓库唯一权威源）

器件型号与工具版本只在这一处定值。赛题 §3.3.3.1 允许 2026.1（推荐）或 2025.2，用别的版本要在报告里说明、脚本还得能
复现；§3.3.3.2 要声明器件型号。其余文档出现这些值时都要对上下面块里的同一个值，不另立一份。
`build/checks/check_repo_hygiene.sh` 的 C3 检查逐处比对，只有取值不同才算问题，同值的抄写只登记条数（改抄写为引用要动
`report/` 与 `skills/`，属另一轮）。

<!-- BEGIN-AUTHORITATIVE -->
part: xc7z020clg484-2
vivado: 2025.2.1
vivado_build: 6403652
os: Windows 10.0.26300.9550
node: v24.21.0
board: RK-ZYNQ7020-F
<!-- END-AUTHORITATIVE -->

## 每个值从哪来

| 字段 | 取值 | 依据 | 复核命令（在仓库根执行） |
| --- | --- | --- | --- |
| `part` | `xc7z020clg484-2` | 构建脚本里写死的器件串；`-2` 是 PRODUCTION 速度等级 | `grep -rn "xc7z020" build/tcl/build_system_axigpio.tcl` |
| `vivado` | `2025.2.1` | 本机安装目录与所有报告头一致 | `ls /<盘>/Software/Vivado`（`<盘>` 是盘符占位，作者机器装在 `<盘>:\Software\Vivado\2025.2.1`） |
| `vivado_build` | `6403652` | 任一综合/实现报告头的 `Date`/`Tool Version` 行 | `head -5 build/utilization.rpt` |
| `os` | `Windows 10.0.26300.9550` | 本机 `ver` 输出；这是 Windows 的版本号格式，不代表 Linux 环境 | `cmd //c ver` |
| `node` | `v24.21.0` | `node --version` 的实跑输出；所有 `.mjs` 脚本都靠它跑 | `node --version` |
| `board` | `RK-ZYNQ7020-F` | 板卡手册封面与 `report/board_pins.md` 第一行 | `head -3 report/board_pins.md` |

## 这份声明不覆盖什么

- 工具行为随版本变，这一条写在各个技能条目的 `失效条件` 一节里（三个可操作问句见 `skills/_meta/distillation-process.md` 第三节）；旧包那张逐行绑版本的 `skills/references/tool-version-drift/SKILL.md` 在 2026-10-04 c7b325f 重建技能包时没保留，现不存在，这一行只报旧名、不指路。
  这份声明只回答交付包用的是哪一版。
- 板卡的电气与管脚事实不在这里，见 `report/board_pins.md` 与 `board/hardware_setup.md`。
- 复现步骤（评委按哪条命令跑）在 `report/70-reproduce.md`，那份才管这件事。

## 已知边界

- 时序与资源数字都在上面这一版工具、这一颗器件上测得；换版本或换器件要重跑，数字不能沿用。
- Vitis 与 Vivado 同源安装，都在 `<盘>:\Software\Vivado\2025.2.1` 树下。
- PS 侧应用的 ELF 能在本机重建（`node build/ps_app.mjs`，用 `PS_CC`/`PS_BSP` 指到安装位置，实测记录 `build/evidence/1005_ps_app_rebuild.txt`）。
  重建那颗与在板那颗 md5 不同 ⇒ 要说"板上已修好"，得重刷之后再跑一次 `board_verify` 复验。
- `board/` 的板卡称呼是本队的命名习惯，不是厂商型号全称；厂商手册封面用的同样是 `RK-ZYNQ7020-F`。
