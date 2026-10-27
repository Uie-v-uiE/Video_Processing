---
name: win-bash-path-split
description: 处理 Windows 上 Git Bash/MSYS 与工具、Node 各看各的路径与参数这一类：症状是 Vivado 报 ERROR: [Common 17-37] Directory in which file … does not exist [/tmp/…]、xvlog 报 Can not find file、命令行被截成"参数太多"最后只剩 Cannot find design unit、脚本自调 rc=127、后台链读不到刚 export 的变量、以及 .bat 用 [ -x ] 判可执行永远假。
---

## 1. 一句话用途

同一台机上，路径与参数有三种视图。

## 2. 适用场景

- 当 Tcl/批处理工具报 `Directory … does not exist [/tmp/…]`，而 bash 里 `ls /tmp` 明明有那个目录时。
- 当 `xvlog -f <文件>` 报 `Can not find file`，而文件确实存在时。
- 当编译清单变长之后，日志里没有 `ERROR`，最后只冒出一句 `Cannot find design unit`。
- 当脚本自己调用自己时报 `rc=127`，而仿真/主流程其实跑完了。
- 当 `export VAR=… && cmd &` 或"上一条命令 export 过"之后，下一条命令里 `VAR` 是空的。
- 当 `[ -x "$DIR/xsdb.bat" ]` 恒假、或 `cut -c` 把中文串切坏时。

## 3. 不适用 / 失效条件

- 不适用：纯 Linux/WSL 环境（`/tmp` 只有一份视图）——本条只剩 `-f 文件路径风格`与"每次调用是新 shell"两半，且后者只对你用工具型 agent/CI 分步执行时成立。
- 不适用：路径与工具都正常、报错指向设计本身（先按报错原文判对象，见 `tcl-query-empty-means-broken-ruler`）。
- 失效：换 Vivado/Vitis 主版本后命令行长度上限与 MSYS 换算行为可能不同；本文只写本仓 2025.2.1 + MSYS 上量到的形状。
- 不许越界：本条不建议为了绕过限制去关安全设置；只改写法（走文件、用绝对路径、写仓库内目录）。
- 不适用：非 Windows 的交叉编译主机（Linux 跑 Vitis）——`tasklist` 那一半换成 `pgrep`。

## 4. 前置条件

- Windows + Git Bash（MSYS）；`cygpath` 可用。
- 工具定位走环境变量而不是写死绝对路径（本仓口径在 `report/BUILD.md` §1 的变量表）：
  `VP_VIVADO_BIN` 指 `<Vivado>/bin`、`VP_XSDB` 指 `<Vitis>/bin/xsdb.bat`（示例取值，需按自身工程替换）。
- 一个**仓库内**的输出目录给工具写文件（本仓形状：`build/evidence/<本轮>/`）。
- 脚本能找到自己的根：`ROOT="$(cd "$(dirname "$0")/.." && pwd)"`（本仓形状 `sim/run_one.sh:48`）。

## 5. 使用方法

1. 先把所有"工具要写的文件"的目标目录改成仓库内路径：
   `report_timing -file $out/hold_0.rpt`，其中 `$out` 是仓库内目录；不要用 `/tmp/…`。
   完成后应看到：报告文件真的出现在那个目录里（而不是 `[Common 17-37]`）。
2. 长清单一律走 `-f` 文件：`printf '%s\n' $SRC | cygpath -m -f - > files.f`，再 `xvlog -f files.f`（本仓形状 `sim/run_one.sh:72`）。
   完成后应看到：`xv.log` 里没有 `Can not find file`，且 `xsim.dir/work` 被建出来（本仓对该分支的判据在 `sim/run_one.sh:98`）。
3. 检查 `-f` 文件里写的是不是 **Windows 正斜杠**形式（`D:/…`）而不是 MSYS 形式（`/d/…`）。
   完成后应看到：`head -1 files.f` 以盘符开头；命令行参数会被 MSYS 自动换算，但 `-f` 文件内容不会。
4. 脚本内部自调一律用绝对路径：`bash "$ROOT/sim/run_one.sh" --verdict "$TB" run.log`（本仓形状 `sim/run_one.sh:123`）。
   完成后应看到：rc 是 0/3/4 而不是 127。
5. 给后台链或多步调用传变量，用前缀式或让脚本自己 export：
   `VP_XSDB=… node src/host/health_read.mjs`（前缀式），或链里第一步就 export。
   完成后应看到：脚本打印它实际用的工具路径，且该路径存在。
6. 判"文件存在/可执行"时不要对 `.bat` 用 `[ -x ]`（本仓 #244 记的同族），改判 `-f` 或按工具自己的 REFUSE 分支。
   完成后应看到：REFUSE 只在真的没配环境变量时出现，并且它念出变量名（本仓形状 `sim/run_one.sh:47`）。
7. 需要截字符串时用 ASCII 安全的切法（`cut -c` 按字节切会咬坏中文），或改成 `awk substr` 前先确认全是 ASCII。
   完成后应看到：被截出来的标签没有乱码/半个字。

## 6. 判读与失败分叉

- 步骤 1：
  通过 = 文件按预期出现在仓库内目录。
  失败 = 仍报 `Common 17-37` ⇒ `FAIL`，检查那个目录是否**在工具进程可见的盘**上（`mkdir` 是否在 bash 侧刚建、工具在另一台/另一层）。
  读不到输入 = 目录存在但文件为 0 字节 ⇒ `NOT_MEASURED`，转 `who-else-writes-this-artifact` 查是不是两份进程在写。
- 步骤 2：
  通过 = `xv.log` 干净、work 库建出。
  失败 = `xv.log` 有 `Can not find file` ⇒ 走步骤 3 改路径形式；有"参数太多"而没 ERROR ⇒ 说明清单还走在命令行上，改成 `-f`。
  读不到输入 = `xv.log` 不存在 ⇒ `NOT_MEASURED`，先确认重定向有没有生效（不要用 `| tail` 包一层）。
- 步骤 3：
  通过 = 首行是 `D:/…` 形式。
  失败 = 是 `/d/…` ⇒ `FAIL`，重跑 `cygpath -m` 生成。
  读不到输入 = `files.f` 为空 ⇒ `NOT_MEASURED`，`$SRC` 的 find 没命中，先核对清单口径与目录（本仓口径：整棵 `src/rtl` + `sim/tb_*.v` + `sim/prim`）。
- 步骤 4：
  通过 = rc ∈ {0,3,4}。
  失败 = rc=127 ⇒ `FAIL`，脚本里还有相对 `$0`/相对 `$BASH_SOURCE` 的自调。
  读不到输入 = 找不到 `run.log` ⇒ `NOT_MEASURED`，先确认脚本 `cd` 到哪一层（本仓在 `sim/run_one.sh:62` 已经 `cd` 进临时运行目录）。
- 步骤 5：
  通过 = 打印出的路径存在且被真正调用。
  失败 = 脚本回落到 PATH 里的名字并失败（本仓形状：`process.env.VP_XSDB || 'xsdb.bat'` 而 PATH 里没有它）⇒ `FAIL`，改前缀式或脚本内 export。
  读不到输入 = 变量为空且没有任何打印 ⇒ `NOT_MEASURED`，先加一行"我用的解释器/工具是 X"的打印。
- 步骤 6：
  通过 = REFUSE 分支只在缺配置时触发。
  失败 = 配了仍 REFUSE ⇒ 判 `-x` 对 `.bat` 不成立这一类，改成 `-f` + 试跑一条 `--version` 式命令。
  读不到输入 = 变量指向的路径根本不存在 ⇒ `NOT_MEASURED`，按 `report/BUILD.md` 变量表逐项填。
- 步骤 7：
  通过 = 标签完整。
  失败 = 半个字/问号 ⇒ `FAIL`，转 `console-codepage-verdict-shift`。
  读不到输入 = 没有可对照的原始字节 ⇒ `NOT_MEASURED`，把原始字节数打出来（本仓形状：逐字节数 >127 的个数）。

## 7. 已验证的效果

- 基线（不用本条，件里可读）：
  `build/evidence/r114_idelay_sweep_console.txt:688` 原文
  `HOLDWorst|0|slacks=|dests=|rc=ERROR: [Common 17-37] Directory in which file hold_0.rpt is to be written does not exist [/tmp/kx/r114sweep]`
  （同文件 `:1275`、`:1876` 两档同形）⇒ 五份读数为空，扫档判据当时读的是"什么都没有"。台账 `report/log/ISSUES.md` #280 末尾。
- 命令行长度那一支的基线形状（台账原文，本轮未复现长清单现场）：`sim/run_one.sh:67-71` 的注释记"清单拼在命令行上会被 Windows 命令行长度上限截成一句『参数太多』，而 xv.log 里连 ERROR 都没有 ⇒ 脚本只看 `^ERROR` 就往下走，最后报成看不懂的 `Cannot find design unit`"；
  同形事故另见 `report/log/ISSUES.md` 第 556 行、第 2755 行。判 `【未实测】`（本轮没有把清单放回命令行去撞它）。
- 用它之后的形状（本轮 2026-10-04 实跑，只读）：
  `bash sim/run_one.sh --verdict tb_v98_top_seam build/tb_v98_report.txt` 打出
  `VERDICT tb_v98_top_seam: RESULT tb_v98_top_seam FAIL nfail=1 || FAIL 行数=1 || PASS 行数=161`，`rc=3`
  ⇒ 离线分支排在 Vivado 存在性检查**之前**，所以"没有工具路径也能读旧日志"这一条被证明可用（`sim/run_one.sh:8-9` 声明了这个顺序，本轮实跑吻合）。
- 本轮未做的：没有重跑任何 `xvlog -f` 或 Tcl `report_timing` 落盘（需要工具现场与许可证），
  所以步骤 1–3 的"当前这台机上重跑一定成功"记 `【待验证】`。

## 8. 提炼来源与边界

- 证据：`report/log/ISSUES.md` #280（`Common 17-37`）、#317（`export … && cmd &` 进了子 shell、每次调用是新 shell、node 眼里的 `/tmp` 是 `C:\tmp`）、#244（`ps -W` 看不到 Windows 映像名，同族含 `cut -c` 按字节切、`[ -x ]` 对 `.bat` 不成立）、
  第 9193 行（`-f` 文件里写 `/d/…` 会 `Can not find file`）、第 6859 行（`$0` 相对路径在 `cd` 之后解析不了 ⇒ rc=127）。
- 代码形状：`sim/run_one.sh:47/48/62/72/98/123`；文档口径 `report/BUILD.md` §1 变量表。
- 件：`build/evidence/r114_idelay_sweep_console.txt`。
- 工具行为断言的来源行见 `skill/pitfalls/_proposed-sources.md`。
- 停止适用的条件：把全部工具调用改在 Linux 主机/容器里跑，且输出目录在工具与 shell 共享的挂载点上；本条只剩"每次调用是新 shell"这条纪律。
- 迁移到新题目/新板卡要改的地方：
  1. 环境变量名（本仓 `VP_VIVADO_BIN`/`VP_XSDB`/`PS_CC`/`PS_BSP` 都是自家约定，示例取值，需按自身工程替换）；
  2. 工具写文件的默认目录（Vivado 与 xsdb 的相对路径基准不同）；
  3. 换 Linux 主机后 `tasklist`/`cygpath` 整段作废，改 `pgrep`/原生路径；
  4. 器件家族无关，**主机操作系统相关**——这条要显式标出来给评审看。
