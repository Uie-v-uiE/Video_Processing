# 构建与上板

> 版本注记：本文最早写于第三版，命令与脚本路径至今仍适用；**版本相关的数字**（哪块 bit、
> 门禁多少）不在这里，看 `report/DEMO_SCRIPT.md` §0 与 `report/OVERNIGHT_LOG.md` §9.5。

## 1. 本机路径

| 用途 | 路径 |
|------|------|
| 仓库根 | `D:\Xilinx\Prj\pro\Video_Processing\`（旧文档与一次性脚本里曾是**另一份工作副本**根 `D:\Xilinx\Prj\ADD\Video_Pipeline-main`；那棵树今天还在、停在 v3 时代（git HEAD `7cde28d`）⇒ 脚本指过去**不会报错，只会静默改错树**，比失败更坏；2026-09-23 已全部改成自适应路径） |
| Vivado | `D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat` |
| Vitis | `D:\Software\Vivado\2025.2.1\Vitis\bin\xsdb.bat`（批处理式跑法；无后缀的 `xsdb` 是 Linux 包装脚本，Git Bash 下会报 rlwrap 缺失） |
| Vivado 工程 | `vivado_system\zynq_video_sys.xpr`（已 gitignore，可用 TCL 重建） |
| 构建脚本 | `build\tcl\build_system_axigpio.tcl` |
| 下载脚本 | `build\tcl\program_system.tcl`；PS 起来用 `build\tcl\ps_jtag_boot.tcl`（会自动从 xsa 解出 `ps7_init.tcl`） |
| 第二块板 | `ku5p\build\tcl\ku5p_build.tcl`（`KU5P_SYNTH_ONLY=1` 只综合；正式产物在 `ku5p\build\`，实验跑法加 `KU5P_TAG=<名>` 落到 `ku5p\build\exp_<名>\` 不盖正式报告） |
| 上位机 | `src\host\`（推流 `video_sender.mjs`、健康读回 `health_read.mjs`、KU5P 遥测 `ku5p_stats.mjs`） |
| PS 源码 | `src\ps\main.c`（编译：`node build\ps_app.mjs`，需要 `PS_BSP`） |
| Git | `D:\Software\Git\Git\bin\git.exe`（**旧的 `D:\Git\Git\bin` 在这台机器上已不存在**；PATH 里也有 `git`） |

---

## 2. 常用命令

```bat
cd /d D:\Xilinx\Prj\pro\Video_Processing
set VIVADO=D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat

:: 从零生成 bit + xsa
%VIVADO% -mode batch -source build\tcl\build_system_axigpio.tcl

:: 下载 bit
%VIVADO% -mode batch -source build\tcl\program_system.tcl

:: 仿真（含 zoom）
%VIVADO% -mode batch -source sim\run_sim.tcl
%VIVADO% -mode batch -source sim\run_zoom_only.tcl

:: 增量重跑（改 RTL/约束后）
%VIVADO% -mode batch -source build\tcl\rebuild_cdc_fix.tcl

:: 读回七项门禁（也可复核任一组成套冻结件）
bash build/gates.sh
bash build/gates.sh build/frozen_r19_arb

:: 只跑一个台架（比全量回归快得多，改完 RTL 的第一道关）
bash sim/run_one.sh tb_ku5p_tx_arb

:: 推流
cd src\host
run_sender.bat
run_video.bat D:\path\to\video.mp4
run_serial.bat COM5
```

产物：`build\system.bit`、`build\system.xsa`、`build\*.rpt`。

---

## 3. 上板顺序

1. 12V 电源、HDMI 1024×600、USB（JTAG+UART）
2. 网线接 **PL 网口**（非 PS 口）
3. 下载 bit
4. （串口需要）Vitis Run PS ELF——bit 会复位 PS
5. PC：`192.168.1.100/24`
6. `ping 192.168.1.10`
7. `run_sender.bat` 推流
8. HDMI：左原图 / 右缩放+效果；OSD 见 FPS/ANG/EN；右屏自动缩放循环

---

## 4. 网络参数

| 项 | 值 |
|----|-----|
| 板卡 PL IP | `192.168.1.10` |
| UDP 端口 | **5001** |
| BOARD_MAC | `00:11:22:33:44:55` |
| PC IP | `192.168.1.100/24` |

---

## 5. 串口命令摘要

| 命令 | 作用 |
|------|------|
| `00000` / `10000` / `01000` / `00111` | 效果位 |
| `SRC0` / `SRC1` | 彩条 / 视频 |
| `TH80` | 阈值 |
| `ZOOM0` / `ZOOM1` | 缩放关/开（PL 常开时 GPIO 预留） |
| `FILL` / `STAT` | 诊断 |

效果位：gray binary blur sobel invert（bit0 在左）。

---

## 6. 报告

实现后已导出：

- `build/timing_summary.rpt`
- `build/utilization.rpt`
- `build/power.rpt`
- `build/clock_util.rpt`

手工补报告：

```tcl
open_run impl_1
report_timing_summary -file build/timing_summary.rpt
report_power -file build/power.rpt
```

约束与脚本说明见仓库根 `README.md` 与 `docs/`（本地）。

## 7. 冻结与回退（每一次改 RTL 之后都要做）

构建脚本会**原地覆盖** `build/system.bit` / `system.xsa` / 那六份报告 —— 文件名不变、内容变。
所以"某一版构建的证据"必须成套存档：

```bash
D=build/frozen_rNN_<短名>; mkdir -p $D
cp build/system.bit build/system.xsa build/ps_app.elf \
   build/{cdc,clock_util,methodology,power,route_status,timing_summary,util_hier,utilization}.rpt $D/
(cd $D && md5sum system.bit system.xsa ps_app.elf *.rpt > MANIFEST_BODY.txt)
# 再手写 MANIFEST.txt：门禁数字 + 这一版相对上一版改了什么 + 什么证据支持这个结论
```

**三条规矩（2026-09-23 凌晨用一次真实的丢失换来的）**：
1. **冻结 = 拷贝工件**。MANIFEST 里出现 `../system.bit` 这种"引用活路径"的写法 = 没冻结。
   反面教材：`frozen_r18_abort/` 当时只留了报告和 `../system.bit` 的校验和，build#19 一跑，
   冻结目录里就没有那一版的 bit 了。**它后来被救回来了** —— 因为本仓库恰好把
   `build/system.bit` 也入库，`git show 7578217:build/system.bit | md5sum` 正是 `534f7760…`，
   已复原成 `frozen_r18_abort/system.bit`。**这次没丢是运气，不是流程**：换个不入库 bit 的
   布局（`.gitignore` 里 `frozen_*/*.bit` 就是排除的）它就真没了 ⇒ 规矩仍然是实体拷贝。
2. **下板之前先 `md5sum build/system.bit` 和 MANIFEST 对前缀**；对不上就去 `build/frozen_*/` 取，
   别硬下——同名不同内容今晚发生过两次。
3. 门禁**任何一条红**都不采纳：保留上一版当明早默认，把这一版挪去 `build/failed_rNN/`
   （里面留着 `system_r24_WNS-0.327.bit` 这种带 WNS 命名的失败件，是用来对照的，不是用来下的）。

当前回退链（2026-09-23 07:1x，四块 bit 实体都在各自目录里）：
`frozen_r19_arb`（`545a27a1`，**明早默认**）→ `frozen_r18_abort`（`534f7760`，从 git 历史复原）
→ `frozen_r17_cdc`（`11998af8`）→ `frozen_r13`（`0f46ec91`，最后一次上过板验证的功能集）。
