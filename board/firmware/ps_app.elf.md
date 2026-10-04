# 来源卡 · `build/ps_app.elf`（PS 裸机应用）

| 字段 | 值 | 怎么当场回读 |
|---|---|---|
| 权威路径 | `build/ps_app.elf` | `ls -la build/ps_app.elf` |
| 大小 | **343600 B** | `stat -c %s build/ps_app.elf` |
| MD5 | **`d0b07f84a0683db203086fb816ac71d7`** | `md5sum build/ps_app.elf` |
| SHA-256 | `307158926058e1a1655de8babb8d4e56193585aaf8a4851affce3334867b724e` | `sha256sum build/ps_app.elf` |
| git blob | `2303037dd6bc115be4b29a9ceebd9b69673e073b`，与 `git hash-object build/ps_app.elf` **相同** ⇒ 工作树与 HEAD 一致 | 本轮实测两条都跑过 |
| 最后一次**内容**变更 | 提交 `9488cb5`（2026-09-29 11:50，「串口回显改成板子默认不回显 + 新增 `echo [0|1]`」）；`git show 9488cb5:build/ps_app.elf \| md5sum` = `d0b07f84a068…`（本轮实测） | `git log -1 --format=%h_%ad -- build/ps_app.elf` |
| 文件时间 | 2026-10-01 00:12:44（**晚于**上面的内容变更 ⇒ mtime 只能说明"被写过一次"，不能说明内容变了） | `stat -c %y` 与 md5 一起看 |

## 1. 由哪一轮构建产生：**它不是 r118 那一轮产的**

这是这张卡最重要的一句话，登记成结论而不是脚注：

- r118 的身份行里三件同表：`build/r118_gates.txt:5` `ps_app.elf md5=d0b07f84a068`，
  `build/evidence/r118_board/board_verify_console.txt:6` 同一颗（`board_verify.sh:140-143` 打印）。
  同一颗 ELF 还出现在 r106 / r109 / r110 / r113 / r114 的身份行里
  （`build/evidence/r106_gates_firstselfred.txt:5`、`build/evidence/r113_board_verify_console.txt:6` 等，本轮逐条打开核对）。
- 构建入口只产 bit 与 xsa：`build/tcl/README.md:17` 原话「跑完再 `node build/ps_app.mjs` 出 `build/ps_app.elf`」
  ⇒ ELF 与位流是**两个独立步骤**，位流换了一版不等于 ELF 换过。
- **ELF 落后于源码**：`git diff --stat 9488cb5 HEAD -- src/ps/` 本轮实测 =
  `src/ps/main.c | 20 ++++--`、`src/ps/sd_play.c | 6 +++---`、`src/ps/sd_play.h | 2 +-`（3 files changed, 18 insertions(+), 10 deletions(-)）。
  其中一笔是 **#167 的 `cmd_buf` 越界修复**（提交 `61d1a2c`，2026-10-02 23:58）。该提交正文自己写着：
  「**ELF 没重建**：这台机器找不到 `arm-none-eabi-gcc`……⇒ 板上还是 r108 那版 app，这条修复**未上板、未验证**，不进任何交付口径」。
  旁证：`build/evidence/r109_cmdbound_wedge.txt:3`「板上跑的仍是 r108 那一版 app（ELF md5 d0b07f84a068）——本条修复未上板」。

⇒ **结论：`build/ps_app.elf` 的来源未固化。**
它对应的是 `src/ps @ 9488cb5`，不是当前 `src/ps`；仓库里没有任何一份"哪一轮编出这颗 ELF"的构建件
（`build/provenance.md` 还不存在，见 Q-P16a-4），也没有 PS 侧源码指纹
（`build/rtl_fingerprint.sh:26-31` 的 `rtl=` 只走 `find src/rtl -name '*.v'`，**不含 `src/ps`**）。

## 2. 再生成命令：两条都在仓库里，但本轮**一条都没跑**

| 路线 | 命令 | 本轮实测到的前置状态 |
|---|---|---|
| Node | `node build/ps_app.mjs`（可 `--clean`） | `PS_CC` 未设 ⇒ 第一步就 `FATAL: arm-none-eabi-gcc 不存在：`，**rc=2**（本轮真跑过一次这一次 REFUSE，它在任何写盘之前退出：`build/ps_app.mjs:42-44` 的三道 `need()` 在 `fs.mkdirSync(OBJ)`（同文件 60 行）之前） |
| Python | `python3 build/build_ps_app.py` | **这台机器 `python3` 不存在**（本轮实测 `/usr/bin/bash: line 1: python3: command not found`，而 `python` = 3.12.10）⇒ 文档里那一条 `python3 …` 在本机跑不通，要写成 `python …`。这是文档与现实的一处偏差，已进问题清单（Q-P16a-8） |

需要的前置（文件头写明，`build/ps_app.mjs:8-14`、`build/build_ps_app.py:8-16`）：
`PS_CC`（arm-none-eabi-gcc）、`PS_BSP`（默认指仓库内
`vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp`，本轮实测该目录下 `lib/libxil.a` **在**）、
`PS_OUT` / `PS_OBJ`（默认 `build/ps_app.elf` / `build/ps_obj`；想验脚本而不动交付件时把 `PS_OUT` 指别处）。

**必须与上面一起登记的一条更正**：任务书与 `61d1a2c` 都说"本机没有 `arm-none-eabi-gcc`"。
本轮两条相反的实测：

```
which arm-none-eabi-gcc          →  rc=1（PATH 上确实没有）
<Vitis>/gnu/aarch32/nt/gcc-arm-none-eabi/bin/  →  目录里 arm-none-eabi-gcc.exe 存在
                                          --version → arm-xilinx-eabi-gcc.exe (GCC) 13.3.0
```

⇒ "PATH 上没有"为真；"这台机器找不到"很可能是当时那条
`find /d/Software -maxdepth 8` 的**假阴性**（从 `<盘>/Software` 数到 `…/bin/` 需要 9 层）。
所以这张卡上**不写任何一条"跑过的再生成命令"**，也**不写"永远不可再生成"**：
再生成的真实状态 = `NOT_MEASURED（本轮禁跑构建）`。
要不要现在重建 ELF（它会**覆盖已入库的 `build/ps_app.elf`**，并把 #167 修复带上板，
连带要重跑 `board_verify` 与串口电池），是队伍的决定 ⇒ Q-P16a-3。

链接后那四道自检（任一不过就非零退出，**"链接成功"不等于可执行**）在 `report/BUILD.md:118-121`：
`_boot`/`_vector_table`/`_start`/`main`/`MMUTable` 都在、ELF 入口 == `_boot`、`_vector_table` == 0x0、`.text` ≥ 20 KB；
外加 `build/_scan_align.mjs` 扫非对齐 `[rN,#imm]`（`report/BUILD.md:121-122`）。
Python 那条路线的退出码分三档（2 = 输入不在 / 1 = 编译链接失败 / 3 = 成品自检不过），
理由写在 `build/build_ps_app.py:22-23`。

## 3. 它怎么进板（加载方式与易失性）

```bash
<Vitis>/bin/xsdb.bat build/tcl/ps_app_reload.tcl        # README.md:41 那一条；可跟一个别的 .elf 路径
```

- 只做 `rst -processor`（复位 Cortex-A9）+ `dow $elf` + `con` ⇒ **不动 PL 配置**，
  位流、AXI GPIO 控制字、正在跑的视频流都保留（`build/tcl/ps_app_reload.tcl:6-8`）。
- 反面对照：`board/boot27c.tcl` 第一步是 `rst -system`，会把已配好的 bit 冲掉（同文件 6-8 行写明）。
- 成功判据（脚本 stdout，`build/tcl/ps_app_reload.tcl:10-14,26-40`）：
  `DOW: ok`（**必须是 ok**；#235 那次就是 `tail` 截掉了这一行差点误判，`report/log/ISSUES.md:10916-10920`）、
  `PC_BEFORE_CON` 读得回来、3 秒后 `pc` 落在 `.text` 里且 `cpsr` 低位 `0x13`（SVC）、
  `FLOW_DONE`；串口侧要看到 `[BOOT]` 横幅（`board/uart_cap_once.ps1` 抓，`report/BUILD.md:128`）。
- **易失**：ELF 在 DDR/OCM 里，断电或 `rst -system` 后必须重新 `dow`。
  ⇒ 三步链的最后一步永远是它（`board/bringup-checklist.md（未写）` §2）。

## 4. 这颗 ELF 与那颗 bit 的配对风险（现场真实出现过）

`board/HANDS_ON.md（不随包）:80` 那条写着：开机若打 `[CFG!] … gamma 窗口不在位流上`，
说的是 **elf/bit 不配套**。因为 ELF 落后于位流一整段历史（本文 §1），
这一格现在是"已知会漂、靠开机回读判"的状态 ⇒ 回读动作 = 抓开机横幅：

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File board/uart_cap_once.ps1 -Port COM6 -Seconds 20
```

（本轮**没有执行**：这次运行不许开串口。命令与判据出处 `report/BUILD.md:128`、`board/README.md:49-50`。）

## 5. 一句话给接手的人

这颗 ELF 是**同一颗 md5 从 r97 一路用到 r118** 的携带件，不是 r118 的产物；
它身上没有 #167 修复；它能不能重建 = 未测；要不要重建 = 等队伍决定（Q-P16a-3）。
