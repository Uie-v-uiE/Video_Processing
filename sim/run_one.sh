#!/bin/bash
# 快速单台架回归（绕开全量 run_sim.tcl 的两分钟编译），用法：run_one.sh <tb_name>
#
# 编译清单与 run_sim.tcl 同口径：src/rtl 整棵树 + sim/prim 占位件 + sim/tb_*.v。
# 以前这里是手写的一小串文件，结果是"改了 pl_video_top 想快点看一眼"时 xelab 直接报
# Cannot find design unit —— 顶层唯一的台架 tb_v6_vblank_copy 根本不在清单里（2026-09-23 撞到）。
# 工具路径只有一个说法：VP_VIVADO_BIN 指到 <Vivado>/bin（清单见 docs/BUILD.md §1）；找不到就第一步 REFUSE。
# 工具路径只有一个说法：VP_VIVADO_BIN 指到 <Vivado>/bin（清单见 docs/BUILD.md §1）；找不到就第一步 REFUSE。
# ⚠ 这两道 REFUSE 排在 `--verdict` 分支**之后**：判定解析是纯文本工作，不该要求现场有 Vivado、
#   也不该因为有别人的 xsim 在跑就不让我离线读一份旧日志（#166 的对照实验因此必须能离线跑）。
TB=$1
# `--verdict <tb> <run.log>`：**只解析判定**，不起仿真、不碰 xsim。
# 为什么开这个口子（#166，2026-09-30）：判定的形状与退出码是"尺子"，它必须能离线被对照实验喂
# 合成日志来验（`build/run_one_ce.sh` 五条），而不是"改了 run_one.sh 之后拿一支真台架跑两小时"才看得见。
if [ "$TB" = "--verdict" ]; then
    TB=${2:-}; LOG=${3:-}
    [ -f "$LOG" ] || { echo "CE-FATAL 读不到 $LOG"; exit 2; }
    V=$(grep -a "RESULT $TB" "$LOG" | tail -1)
    [ -n "$V" ] || V=$(grep -aE "^(PASS|FAIL) $TB( ALL)?$" "$LOG" | tail -1)
    # 第三种形状是 `TB RESULT PASS|FAIL`（tb_v94 那一族，判定行里**没有台架名**）。
    # ⚠ 必须限定"这份日志里出现过本台架的名字"才认它：不加这个限定条件时，一份别人的过期日志
    #   能直接替这支台架答复"通过"（#163 那天我第一次补兜底就犯了这个，比原洞更坏）。
    if [ -z "$V" ] && grep -aq -- "$TB" "$LOG"; then
        V=$(grep -aE "^TB RESULT (PASS|FAIL)" "$LOG" | tail -1)
        [ -n "$V" ] && V="$V（$TB）"
    fi
    # 计数要**容错缩进**：十二支台架把每条判据打成 `  FAIL <名字>`（前面两个空格），
    # 老的 `^FAIL` 看不见它们 ⇒ 一支真红的台架会被报成"FAIL 行数=0"（#166 的机制就是这）。
    NF=$(grep -acE '^ *FAIL( |$)' "$LOG"); NP=$(grep -acE '^ *PASS( |$)' "$LOG")
    if [ -z "$V" ]; then
        echo "VERDICT $TB: NO-VERDICT-LINE（这支台架一条判定都没打，去数判据条数） || FAIL 行数=$NF || PASS 行数=$NP"
        exit 4
    fi
    echo "VERDICT $TB: $V || FAIL 行数=$NF || PASS 行数=$NP"
    # 退出码分得很开（1=编译/例化失败由上面各步给出）：0 绿、3 **判红**、4 认不出判定。
    # 3 与 4 必须分开：红是结论，"没数"不是结论（#163/#164 那一族的另一半）。
    case "$V" in *FAIL*) exit 3;; esac
    [ "$NF" = 0 ] || exit 3
    exit 0
fi
V=${VP_VIVADO_BIN:-}
[ -x "$V/xvlog" ] || { echo "REFUSE: 找不到 xvlog（当前 $V）。设 VP_VIVADO_BIN=<Vivado>/bin 再跑（docs/BUILD.md）"; exit 2; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"   # 仓库根自适应：本文件在 <repo>/sim/（原来写死本机路径）
R=/tmp/kx/$TB.run
# ⚠ 2026-09-27 12:48 撞到的一件事：**同一时刻只能有一个 xsim 在写这个目录**。
#   第二次 `run_one.sh` 并不会让第一次停下 —— 前一个 xsim/xsimk 还活着，继续往同一个
#   `run.log` 里写它那一跑的行。两次跑的行混在一份文件里，`tb98_report.sh` 就会把
#   "上一跑的 C5c" 与 "这一跑的 C5c" 拼成一份报告（今天 12:45 那份就是这么废掉的，
#   而它的头部 md5 全对 —— 认 md5 也救不了"正文来自两个进程"这件事）。
#   所以：门口先看有没有活的 xsim/xsimk，有就**拒绝启动**并说清该杀谁（不自动杀：
#   正在跑的那一跑可能是别人要的凭据）。
if tasklist //FI "IMAGENAME eq xsim.exe" 2>/dev/null | grep -qi "xsim.exe"; then
    echo "REFUSE: 已经有 xsim 在跑（它会把行写进同一份 run.log）。先看是谁的：tasklist //FI \"IMAGENAME eq xsim.exe\""
    echo "        确认可以中断再：taskkill //F //IM xsim.exe //T && taskkill //F //IM xsimk.exe //T"
    exit 3
fi
mkdir -p $R && cd $R || exit 1
rm -rf xsim.dir
SRC="$(find $ROOT/src/rtl -name '*.v' | tr '\n' ' ') \
$(find $ROOT/sim -maxdepth 1 -name 'tb_*.v' | tr '\n' ' ') \
$(find $ROOT/sim/prim -name '*.v' 2>/dev/null | tr '\n' ' ')"
# ⚠ 清单**必须走 -f 文件**，不能拼在命令行上：台架加多之后 xvlog 会被 Windows 命令行长度上限
#   截成一句"参数太多"，而 xv.log 里连 ERROR 都没有 ⇒ 本脚本只看 "^ERROR" 就往下走，
#   最后报成一句看不懂的 "Cannot find design unit"（2026-09-25 加 tb_v94 时撞到）。
# ⚠ 文件里写的必须是 **Windows 正斜杠路径**（`cygpath -m`）：命令行参数会被 MSYS 自动换算，
#   但 -f 文件的内容不会 —— 直接写 /d/... 会让 xvlog 报 "Can not find file"（同一天撞到第二次）。
printf '%s\n' $SRC | cygpath -m -f - > files.f
# 出处（provenance）：**编译之前**记下这次跑的树里两份关键源的 md5。
# 为什么在这里记而不是事后：门禁第 15 项要的恰恰是"这份报告是不是**当前这份顶层**跑出来的"，
# 而事后补 md5 等于把今天的指纹盖在昨天的日志上（#88 那几天"gates 全绿 + 顶层台架红着"的根源
# 就是没有任何东西把报告与被测的树绑在一起）。
# ⚠ 只有 `top_md5` 是**不够的**（2026-09-26 r72 那天撞见）：那一轮改的是四个窗口级
#   （`proc_box_blur/sharpen/sobel/morph`），`pl_video_top.v` 一个字节没动 ⇒ 顶层 md5 仍然"对得上"，
#   而 r71 那份旧报告可以原样冒充"当前这一版台架"。所以再加一枚 `rtl_md5`：整个 `src/rtl` 的合指纹。
RTLALL=$(cd "$ROOT" && find src/rtl -name '*.v' | LC_ALL=C sort | xargs md5sum | md5sum | cut -c1-12)
# ⚠ #169（2026-09-30）：md5 仍然必须在**编译之前**取（事后补等于把今天的指纹盖在昨天的日志上，
#   上面那段就是这件事），但**发布**要等到编译真的成功：以前 `prov.txt` 一落地就等着被读，
#   于是一次 xvlog/xelab 失败的编译会留下"新树指纹 + 旧 run.log 正文"，
#   而 `build/tb98_report.sh` 会把这对指纹原样盖到旧正文上 ⇒ 门禁第 15 项"报告与当前树同一次跑"就此作废。
#   现在：先写 prov.tmp，编译两步都过了才 `mv` 成 prov.txt 并**删掉旧 run.log**（要跑就重新生成），
#   编译失败时盘上留下的还是**成对旧**的 prov.txt + run.log（自洽，冒充不了当前树）。
{ echo "top_md5=$(md5sum $ROOT/src/rtl/top/pl_video_top.v | cut -c1-12)"
  echo "tb_md5=$(md5sum $ROOT/sim/$TB.v 2>/dev/null | cut -c1-12)"
  echo "rtl_md5=$RTLALL"
  echo "date=$(date -Iseconds)"; } > prov.tmp
$V/xvlog -f files.f > xv.log 2>&1
if grep -q "^ERROR" xv.log; then echo "XVLOG FAILED"; grep "^ERROR" xv.log | head -8; rm -f prov.tmp; exit 1; fi
if [ ! -d xsim.dir/work ]; then echo "XVLOG 没建出 work 库，xv.log 尾部："; tail -3 xv.log; rm -f prov.tmp; exit 1; fi
$V/xelab $TB -s snap > el.log 2>&1
if grep -q "^ERROR" el.log; then echo "XELAB FAILED"; grep -A3 "^ERROR" el.log | head -20; rm -f prov.tmp; exit 1; fi
mv -f prov.tmp prov.txt && rm -f run.log
$V/xsim snap -R > run.log 2>&1
# ⚠ 过滤词表必须包含台架**专门为了回答"缺口在哪"而打的那些行**（PROBE/DIAG/NOTE/OBS）：
#   2026-09-25 台架 tb_v98 数出"帧缓存到底被写了多少字"的那条 PROBE 就是被这个过滤器挡在
#   run.log 里的，我因此多绕了一趟临时目录才看到它 —— 而那份 console 才是要留在报告里的凭据。
grep -aE "FAIL|PASS|INFO|PROBE|DIAG|NOTE|OBS |GOLDEN|^D[123] |error|Error" run.log | head -80
tail -2 run.log
# 统一收尾 token（2026-09-29 07:46，#104）：L1 的 `run_sim.tcl` 会给每支台架补一行 `RESULT <tb> …`，
# 逐支跑以前没有 ⇒ 只打 `PASS <tb>[ ALL]` 的那几支（tb_sync_fifo / tb_udp_parser / tb_proc_gray /
# tb_v794_osd_glyph / tb_rotate_window）在 `grep ^RESULT` 眼里等于"没判定"。这里补一行，
# 并把 FAIL 行数一起报出来：判定与计数同源，省得再拿"0 个 FAIL"当结论。
# 统一收尾 token + **退出码要能表达"判红"**（#166，2026-09-30）：
#   以前这一支脚本无论台架判成什么都 exit 0 ⇒ 链里 `run_one.sh … || die` 的"没断链"被读成"过了"，
#   而真正的判定只在那一行 `VERDICT` 里；加上判定形状漏了 `TB RESULT PASS|FAIL` 那一族、
#   FAIL 计数只认顶格的 `^FAIL`（十二支台架打的是 `  FAIL <名字>`），
#   一支真红的台架会被写成"NO-VERDICT-LINE + FAIL 行数=0"—— 红与"没数"长得一模一样。
#   现在退出码：0 绿 / 1 编译或例化失败 / 2 REFUSE / 3 **判红** / 4 认不出判定行。
#   解析本身放在文件开头的 `--verdict` 分支里（**同一个实现**），这样它能被合成日志离线对照
#   （`build/run_one_ce.sh` 五条，含"别人的过期日志不许替这支台架答复"那条）。
# ⚠ 必须用 **绝对路径** 自调：本脚本在第 25 行已经 `cd` 进 `/tmp/kx/<tb>.run`，
#   这时 `$0`（相对路径 `sim/run_one.sh`）不再能解析 —— 第一次真跑就是这么栽的（rc=127，
#   仿真明明跑完了）。run.log 用相对名，它就在当前目录。
bash "$ROOT/sim/run_one.sh" --verdict "$TB" run.log
exit $?
