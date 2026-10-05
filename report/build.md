# 构建与上板

> 版本注记：本文最早写于第三版，命令与脚本路径至今仍适用；**版本相关的数字**（哪块 bit、
> 门禁多少）不在这里，看 `report/demo_script.md` §0 与 `report/log/overnight_log.md` §9.5。

## 1. 怎么定位工具链（本节**不写任何一台机器的绝对路径**）

| 用途 | 在哪 |
|------|------|
| 仓库根 | 由脚本自己按所在位置往回算，不用设任何东西（验证方法见本节末尾） |
| Vivado / Vitis | 2025.2.1（版本注记在 `report/perf_report.md` 与仓库根首页）。定位方式两种：把对应 `bin` 目录放进 `PATH`，或设下面那几个变量 |
| Vivado 工程 | `vivado_system/`（已 gitignore，用 `build/tcl/build_system_axigpio.tcl` 重建） |
| 构建入口 | `build/tcl/build_system_axigpio.tcl`（**只有这一个**；同目录另几支是历史/局部构建，见 `build/tcl/README.md`） |
| 下载脚本 | `build/tcl/program_system.tcl`；PS 起来用 `build/tcl/ps_jtag_boot.tcl`（会自动从 xsa 解出 `ps7_init.tcl`） |
| 上位机 | 推流 `python3 src/host/udp_push.py`（协议、限速、确定性丢包都在文件头）；其余取证类工具是 Node 写的（`src/host/*.mjs`），需要 Node 24，**不在演示主链路上** |
| PS 源码 | `src/ps/main.c`（编译：`python3 build/build_ps_app.py`，需要 `PS_BSP`，见下表） |

> 曾经这一节的第一行就是本机安装路径的清单（Vivado 装在哪、仓库在哪、git 装在哪），
> 换一台机器照着抄会全错，而且"仓库里还有另一份旧的工作副本"这种事写进交付文档只会让人误判。
> 规矩：**代码、Tcl、脚本与交付文档都不许出现绝对路径**；这条现在由导出器判（见 §5 与 `build/make_submission.sh` 头部判据 4）。

### 换一台机器只要设这几个变量

| 变量 | 指哪儿 | 谁读它 | 不设会怎样 |
|---|---|---|---|
| `VP_VIVADO_BIN` | `<Vivado>/bin`（Git Bash 里写成 `/d/...` 这种） | `build/sim/run_one.sh`、`build/sim/mut_control.sh`、`build/roll_isolated.sh` | 脚本第一步 `REFUSE: 找不到 xvlog（当前 …）` 并念出变量名——不会让人对着 RTL 怀疑 |
| `VP_XSDB` | `<Vitis>/bin/xsdb.bat` | `build/board_verify.sh`（以及手工跑 `build/tcl/ps_app_reload.tcl` 时） | 同上 `REFUSE: 找不到 xsdb` |
| `PS_CC` | `arm-none-eabi-gcc` 的前缀或完整路径 | `build/build_ps_app.py`、`build/_scan_align.mjs` | 不设就假定工具链在 `PATH` 上；两处都没有时报 `FATAL: PATH 上找不到 …`（退出码 2），不会去怀疑 RTL |
| `PS_BSP` | 已 generate 过的 zynq BSP 目录（里面有 `include/` 与 `lib/libxil.a`） | `build/build_ps_app.py` | 默认指**仓库内**那份 `vitis/platform/…/bsp`（2026-09-26 起，#89/#90：以前默认指仓库外一个"曾经存在过"的目录，那树一删，PS 侧就悄悄变成"只能沿用旧 ELF、不敢重编"） |
| `PS_OUT` / `PS_OBJ` | ELF 输出路径 / 中间件目录 | `build/build_ps_app.py` | 默认 `build/ps_app.elf` 与 `build/ps_obj`；**想验证脚本而不动交付件时把 `PS_OUT` 指到别处**——2026-09-29 就是这么证明 Python 端口与 Node 端口产出逐字节相同（`md5 d0b07f84a068…`，即板上那一版） |

**仓库根不用设**：`sim/*.sh` 与 `build/*.sh` 都按自己所在位置往回两级算根
（`ROOT="$(cd "$(dirname "$0")/.." && pwd)"`），`build/tcl/*.tcl` 用 `[file dirname [info script]] .. ..`。
**这句话怎么当场验**（正对照，2026-09-29 06:14 在这台机器上跑过，输出就是这两行）：

```
$ VP_VIVADO_BIN=/nonexistent_path bash build/roll_isolated.sh; echo "rc=$?"
REFUSE: 找不到 xvlog（当前 /nonexistent_path）。设 VP_VIVADO_BIN=<Vivado>/bin 再跑（report/build.md）
rc=2
```

拒绝发生在 `mkdir`/`sed` 之前，所以**连那份临时 Tcl 都不会被创建**（脚本正常走完时也会自己删掉它）——
"换一台机器会怎样"这件事本来只能靠推理，这一条让它变成一次可以跑的观察。
`VP_XSDB` 那一支故意不当场跑：`board_verify.sh` 会占 COM6 并改写留档，拿板子做这种对照不值。
2026-09-29 之前这几个脚本里写死的是**这台机器的绝对路径**（Vivado 装在哪、仓库在哪），换机器要改一堆行——
#93 记的就是这件事，r85 那一轮把它落地了。**默认值仍然留着**（本机少敲一步），但它是"便利"不是"标准"，
所以每一个读默认值的脚本都带一条存在性检查：宁可在第一步拒绝，也不要跑到一半留下半份产物。

---

## 2. 常用命令

```bat
cd /d <仓库根>
set VIVADO=<Vivado>\bin\vivado.bat

:: 从零生成 bit + xsa
%VIVADO% -mode batch -source build\tcl\build_system_axigpio.tcl

:: 下载 bit
%VIVADO% -mode batch -source build\tcl\program_system.tcl

:: 仿真（含 zoom）
%VIVADO% -mode batch -source sim\run_sim.tcl
%VIVADO% -mode batch -source sim\run_zoom_only.tcl

:: 增量重跑（改 RTL/约束后）
%VIVADO% -mode batch -source build\tcl\rebuild_cdc_fix.tcl

:: 读回门禁（项数以 `build/gates.sh` 自己打印的为准：2026-09-27 晚上是 19 项，今天 07:5x 起 20 项（新增 15b = 边缘条带 `tb_edge_rim` 的凭据与反例，见 `build/rim_gate_ce.sh`））（也可复核任一组成套冻结件）
bash build/gates.sh
bash build/gates.sh build/evidence_rNN

:: 只跑一个台架（比全量回归快得多，改完 RTL 的第一道关）
bash build/sim/run_one.sh tb_osd_lines

:: 推流
cd src\host
run_sender.bat
run_video.bat <你的视频.mp4>
run_serial.bat COM5
```

产物：`build\system.bit`、`build\system.xsa`、`build\*.rpt`。

---

## 3. 上板顺序

1. 12V 电源、HDMI 1024×600、USB（JTAG+UART）
2. 网线接 **PL 网口**（非 PS 口）—— 但**要先决定这一轮演哪一幕**：演 SD 回放就得在
   下 bit 之前把网线拔掉（PL 里 `link_active = |s_pkts` 是"自配置以来收过任何一个包"，ARP 就够触发，
   拔线不清零、只有重配清零；判据与改法见 ISSUES #47）
3. 下载 bit：`vivado -mode batch -source build/tcl/program_pl.tcl`（下 bit 前先 `md5sum` 对 MANIFEST）；拿隔离滚的产物做板上对照时可以 `VP_BIT` 指过去，**默认路径不变**，交付件身份仍由 md5 认
4. PS 应用（**不需要 Vitis、不需要 FSBL**）：`xsdb build/tcl/ps_app_reload.tcl`
   —— 串口应出现 `[BOOT] video_pipeline PL-UDP control plane`；它只做 `rst -processor`，
   所以位流与 GPIO 控制字都不受牵连。反过来 `ps_jtag_boot.tcl` 含 `rst -system`，跑过它就必须重下 bit。
5. PC：`192.168.1.100/24`
6. `ping 192.168.1.10`
7. `run_sender.bat` 推流
8. HDMI：左原图 / 右缩放+效果；OSD 见 FPS/ANG/EN；右屏自动缩放循环

### 3.1 PS 应用怎么重建、怎么自检（`node build/ps_app.mjs`）

```bat
set PS_CC=<Vitis>\gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-gcc.exe
set PS_BSP=<一个已经 generate 过的 zynq 平台>\ps7_cortexa9_0\standalone_ps7_cortexa9_0\bsp
node build\ps_app.mjs --clean        :: 产出 build\ps_app.elf
```

链接时必须**同时**喂进 BSP 自己的三个启动文件（脚本已经做了，改脚本前先读这段）：
`asm_vectors.S`（向量表 + 各 handler 把出错指令地址写进 `DataAbortAddr` 等全局）、
`boot.S`（`_boot`：设 VBAR、六个模式的栈、CPACR+FPEXC、L2/SCU、开 MMU，然后 `b _start`）、
`translation_table.S`（`MMUTable`）。少了它们的后果不是报错而是四件怪事，逐条实测记录在
ISSUES #44；入口只能写在链接脚本里（`ENTRY(_boot)`）—— 命令行 `-Wl,-e,_boot` 会被脚本里的
`ENTRY` 顶掉，`readelf` 的入口悄悄变 0x0，一声不响。

脚本链接后有四道自检，任何一道不过就非零退出（"链接成功"不等于可执行，历史上产出过 .text 只有
80 字节的空 ELF）：`_boot`/`_vector_table`/`_start`/`main`/`MMUTable` 都在；
**ELF 入口 == `_boot`**；**`_vector_table` == 0x0**；`.text` ≥ 20 KB。
另有一个 `build/_scan_align.mjs`：扫整份镜像的 `[rN,#imm]` 字访问有没有非对齐
（MMU 关着时这类指令必发对齐异常；当前 482 条、非对齐 0 条）。

串口侧工具（验收机不保证有 pyserial，所以走 Windows 自带 API）：

| 用途 | 命令 |
|---|---|
| 抓开机横幅 | `powershell -File board\uart_cap_once.ps1 -Seconds 20` |
| 发命令收回应 | `... -Cmd STAT` |
| 多条 + 间隔（量帧率） | `... -Cmds "SD,PLAY,STOP" -CmdDelay 12 -Seconds 8` |
| 板子没反应时看核 | `xsdb board\pswhy.tcl`（pc/cpsr/lr/sp + 三个 abort 地址全局） |
| 看 PS 有没有真写进 DDR | `xsdb board\rdddr.tcl`（GPIO 回读 + `0x10000000` 头几字） |

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

约束与脚本说明见仓库根 `README.md` 与 `report/`（本地）。

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
