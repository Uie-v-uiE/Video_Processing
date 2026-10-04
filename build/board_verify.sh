#!/bin/bash
# build/board_verify.sh —— 板子上电、三件套刷好之后，一条命令跑完"机器能判的那一半"验收。
#
#   bash build/board_verify.sh              # 只跑不需要推流的那几项（读回口 + 开机自检）
#   bash build/board_verify.sh --stream     # 再加：推流 → 仲裁交接 → 停流交回（要 ~2 min）
#   bash build/board_verify.sh --battery    # 再加：串口命令电池（97 条 = V8 的 71 + V9 的 20 + #77 的 6，
#                                          #        会改板上控制字并复原；复原由 STAT 的 geom= 兜底）
#   bash build/board_verify.sh --geom       # 再加：V9 几何自动化的"最后一跳"（lane23 + CFG_DATA0）
#                                          #   与电池分开取证：电池看**回显**，这一条看**像素域真值**
#   bash build/board_verify.sh --round=r104  # 必给：原始串口回显那份要写成 build/evidence/r104_serial_raw.txt，
#                                          #   没有轮号就**判红而不写文件**（#179：脚本自带默认值会把今天的数
#                                          #   写成一份名字叫旧轮的假凭据）
#   bash build/board_verify.sh --self        # 只跑判据自己的五条对照（不碰串口、不需要板子）：
#                                          #   空捕获必须红、两行 [TEMP] 必须绿、低于地板必须红、
#                                          #   GBK 转码后必须绿、**没转码的那份必须红**（后面两条是一对，
#                                          #   少了第二条就没有"转码这件事真在被判"的证据）
#
# 为什么要这个脚本：这些判据以前是我半夜手敲一串命令跑的，**别人复现不了**（比赛要审"他人能否复现"）。
# 现在把顺序、判据、以及"每一项看哪一行输出"固定在一个文件里，跑完把日志留在 build/evidence/。
#
# 不做什么：不刷板子。三件套（bit/xsa/elf）的下载顺序见 README.md 的"复现三步"第 3 步（xsdb
# ps_jtag_boot → vivado program_pl → xsdb ps_app_reload）与 report/build.md §3「上板顺序」（那里还写了为什么跑过
# ps_jtag_boot 就必须重下 bit），
# 那一步会动硬件，故意留给人（或我）一条一条确认。脚本开头会把三件 md5 打出来，便于和
# build/frozen_*/MANIFEST.md 对账。
set -u
cd "$(dirname "$0")/.." || exit 1
ROOT=$PWD
OUT=build/evidence/verify_$(date +%m%d_%H%M)
mkdir -p build/evidence
LOG=$OUT.txt

# ---- 原始串口回显留档（#220 的工具那一半，2026-10-02 落地 #163）----------------------------------
# 为什么要它：`[TEMP] degC=… raw=… vccint=… osd=…C` 这类**只有固件周期性打出来**的读数，此前是我从
# 本机那份捕获（不在提交包里、也不进 git）里**手抄**进 `build/evidence/` 的。于是"板上这一刻的温度"
# 这条交付数字的凭据是一份**抄件**，工具自己不产它 ⇒ 别人复现时拿不到同一件东西（章程问的就是"他人能否复现"）。
# 三条判据，每条都能红：
#   ① 抓到的内容必须**非空**——COM6 被别的终端占住时 `powershell` 照样返回 0，空捕获以前会算绿；
#   ② `[TEMP] degC=<数字>` 的行数 >= `TEMP_FLOOR`（默认 2）；
#   ③ 落到盘上的那份必须**能用 UTF-8 解**（固件的中文回显是 GBK；GBK 原样进 git，下一轮 `doc_enc` 就红在编码上，
#      而那一红长得像"文档坏了"，不像"捕获没转码"）。
TEMP_FLOOR=${TEMP_FLOOR:-2}
to_utf8() { # $1 原始捕获 $2 目标(UTF-8)。先探测再转：本来就是 UTF-8 就照抄
    if iconv -f UTF-8 -t UTF-8 "$1" >/dev/null 2>&1; then cp "$1" "$2"; return 0; fi
    if iconv -f GBK -t UTF-8 "$1" > "$2" 2>/dev/null; then return 0; fi
    cp "$1" "$2" 2>/dev/null || : > "$2"
    return 1
}
serial_judge() { # $1=UTF-8 那份 $2=给人看的名字；置 SN_ALL/SN_TEMP/SN_DEC 并返回 0=绿
    # ⚠ 不能写 `$(grep -ac … || echo 0)`：grep **数出来是 0 时也照样打印 0 并且退出码 1**，
    #   于是式子给出 "0\n0" 两个字符，`[ 0\n0 -lt 1 ]` 报"integer expression expected"、
    #   而那**正是**空捕获该有的判红——它变成了一条 shell 错误，然后往下走成绿。
    #   （这类"尺子自己报错却继续判"在本仓记过三次，同一族。）
    SN_ALL=$(grep -ac . "$1" 2>/dev/null); SN_ALL=${SN_ALL:-0}
    SN_TEMP=$(grep -acE '\[TEMP\] degC=-?[0-9]+\.[0-9]+' "$1" 2>/dev/null); SN_TEMP=${SN_TEMP:-0}
    if iconv -f UTF-8 -t UTF-8 "$1" >/dev/null 2>&1; then SN_DEC=1; else SN_DEC=0; fi
    if [ "${SN_ALL:-0}" -lt 1 ]; then
        echo "        —— $2 是**空捕获**：COM6 打不开（多半被别的串口终端占着）或板子没在跑。空凭据不算绿。"
        return 1
    fi
    if [ "${SN_DEC:-0}" != 1 ]; then
        echo "        —— $2 解不成 UTF-8：GBK 转码那一步没生效（to_utf8 两种编码都失败了）。"
        return 1
    fi
    if [ "${SN_TEMP:-0}" -lt "$TEMP_FLOOR" ]; then
        echo "        —— $2 里 [TEMP] 只有 ${SN_TEMP:-空} 行，地板是 $TEMP_FLOOR：要么窗口太短，要么固件这一路没打。"
        return 1
    fi
    return 0
}
serial_self() {  # 判据自己的测试：造四种捕获，期望"该红的红、该绿的绿"
    local t rc n=0 m=0
    t=$(mktemp -d /tmp/kx/bvself.XXXXXX) || { echo "SELF: mktemp 失败"; return 1; }
    chk() { # $1=这一条形符期望的名字 $2=实测判定(0 绿 / 1 红) $3=期望判定
        m=$((m+1))
        if [ "$2" = "$3" ]; then echo "  PASS $1：实测 $( [ "$2" = 0 ] && echo 绿 || echo 红)（期望同）"; n=$((n+1));
        else echo "  FAIL $1：实测 $( [ "$2" = 0 ] && echo 绿 || echo 红) 期望 $( [ "$3" = 0 ] && echo 绿 || echo 红)"; fi
    }
    # ① 空捕获 ⇒ 必须红（COM6 被占住时 powershell 也返回 0，所以"空"必须是红而不是无话可说）
    : > "$t/empty.txt"
    rc=0; serial_judge "$t/empty.txt" "fixture 空" || rc=1
    chk "空捕获判红" "$rc" 1
    # ② 两行 ASCII [TEMP] ⇒ 必须绿
    printf 'ok V9-6 [TEMP] degC=61.72 raw=0xAA2B vccint=997mv th=85C over=0 sane=1 osd=62C gpio=0x62\n[TEMP] degC=61.88 raw=0xAA3D vccint=998mv th=85C over=0 sane=1 osd=62C gpio=0x62\n' > "$t/two.txt"
    rc=0; serial_judge "$t/two.txt" "fixture 两行" || rc=1
    chk "两行 [TEMP] 判绿" "$rc" 0
    # ③ 只有一行（低于地板）⇒ 必须红
    printf '[TEMP] degC=61.72 raw=0xAA2B\n' > "$t/one.txt"
    rc=0; serial_judge "$t/one.txt" "fixture 一行" || rc=1
    chk "低于地板判红" "$rc" 1
    # ④ GBK 的中文回显 + 两行 [TEMP] ⇒ 转码之后必须绿**且**能按 UTF-8 解
    printf 'ok V9-6 ' > "$t/gbk.txt"
    printf '\xce\xc2\xb6\xc8' >> "$t/gbk.txt"          # "温度"两字的 GBK 字节：当 UTF-8 读是非法序列
    printf ' [TEMP] degC=62.01 raw=0xAA44 vccint=997mv\n' >> "$t/gbk.txt"
    printf '[TEMP] degC=62.10 raw=0xAA4A vccint=997mv\n' >> "$t/gbk.txt"
    to_utf8 "$t/gbk.txt" "$t/gbk.utf8.txt"
    rc=0; serial_judge "$t/gbk.utf8.txt" "fixture GBK 转码" || rc=1
    chk "GBK 捕获转码后判绿" "$rc" 0
    # ④b 同一条的另一面：**没转码**的那份必须红（否则 ④ 的绿是"两种都绿"，判据没有牙）
    rc=0; serial_judge "$t/gbk.txt" "fixture 未转码" || rc=1
    chk "未转码的 GBK 判红" "$rc" 1
    rm -rf "$t"
    echo "SELF board_verify: $n/$m 条形符期望（地板 5/5）"
    [ "$n" = "$m" ] && [ "$m" = 5 ]
}
if [ "${1:-}" = "--self" ]; then
    serial_self; exit $?
fi

# xsdb 只有一个说法：VP_XSDB 指到 <Vitis>/bin/xsdb.bat（默认值只是本机的便利，不是标准，见 report/build.md）。
# 外面那一层双引号是必需的：XSDB 之后会被拼进命令行，路径带空格时没引号就断成两条命令——
# 所以先把**裸路径**放进 VP_XSDB 做存在性检查，再包引号交给 XSDB，不用 eval 去拆。
VP_XSDB=${VP_XSDB:-}
[ -f "$VP_XSDB" ] || { echo "REFUSE: 找不到 xsdb（当前 $VP_XSDB）。设 VP_XSDB=<Vitis>/bin/xsdb.bat 再跑（report/build.md）"; exit 2; }
XSDB="\"$VP_XSDB\""
# ⚠ 这一版之前脚本**没有总判定**：不管中间红成什么样，最后都是 `exit 0`（而且各步都挂在管道尾巴上，
#   退出码是 `tail` 的）。2026-09-25 r59a 那次日志里明写着"[ARB] 结论：1 条不通过 ⇒ 判红"，
#   而调用方看到的 VERIFY_EXIT 仍是 0 ⇒ 记成 NRED 计数，末尾一行总判定 + 非零退出。
NRED=0

DO_STREAM=0; DO_BATT=0; DO_GEOM=0        # `set -u` 在下面，未初始化就直接引用会退出
ROUND=${VP_ROUND:-}                      # 版本身份（rNN）：原始回显那份凭据要靠它才有名字
for a in "$@"; do
  case "$a" in
    --stream)   DO_STREAM=1 ;;
    --battery)  DO_BATT=1 ;;
    --geom)     DO_GEOM=1 ;;
    --round=*)  ROUND=${a#--round=} ;;
    -h|--help)  grep '^# ' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "忽略未知参数：$a（可用：--stream --battery --geom --round=rNN --self --help）" >&2 ;;
  esac
done
# 轮号写法归一：`--round=r104` 与 `--round=104` 都得落到 `r104_serial_raw.txt`。
# 不加这一手，02:41 那次实跑就产出了 `rr104_serial_raw.txt`（我把参数里的 r 又拼了一遍）。
ROUND=${ROUND#r}

echo "== board_verify $(date '+%F %T') ==" | tee "$LOG"
echo "工作目录：$ROOT" | tee -a "$LOG"
echo "-- 三件套（请与 build/frozen_*/MANIFEST.md 对账）--" | tee -a "$LOG"
for f in build/system.bit build/system.xsa build/ps_app.elf; do
  if [ -f "$f" ]; then echo "  $f  md5=$(md5sum "$f" | cut -c1-8)  $(stat -c %y "$f" | cut -c1-16)" | tee -a "$LOG"
  else echo "  $f  缺失" | tee -a "$LOG"; fi
done

echo "-- 1) 串口现在在说什么（活着、在播、没报错）--" | tee -a "$LOG"
# ⚠ 第一版这里想抓的是 [BOOT]/[CFG]/[TEMP] 那几行横幅 —— 抓不到：**横幅只在 app 被下载的那一刻打一次**。
#    单独开捕获只会看到 [SD] 的周期回声。要看横幅就一边重下 app 一边抓（r54 实测可用的两行）：
#      (powershell -File board/uart_cap_once.ps1 -Port COM6 -Seconds 14 -Out build/uart_r54_boot.txt &)
#      sleep 2; xsdb.bat build/tcl/ps_app_reload.tcl
powershell -NoProfile -ExecutionPolicy Bypass -File board/uart_cap_once.ps1 \
  -Port COM6 -Seconds 4 -Out "$OUT.boot.txt" >/dev/null 2>&1
for pat in '\[SD\] frame' '\[SD\] play refused' '\[SD\] mount failed' '\[TEMP!\]' '!!'; do
  hit=$(grep -a -m1 "$pat" "$OUT.boot.txt" 2>/dev/null || true)
  echo "  $pat → ${hit:-（没有这行）}" | tee -a "$LOG"
done

echo "-- 1b) 原始串口回显留档（被跟踪的那一份：[TEMP] 逐条，不靠手抄）--" | tee -a "$LOG"
# 为什么单独开这一档：`[TEMP] degC=… raw=… vccint=… osd=…C gpio=…` 是固件**周期性**打出来的，
# 上面那 4 秒窗口的横幅抓不到它。以前我把这些行从本机捕获里**手抄**进 build/evidence/，
# 于是交付表里"板上 XADC 温度"这一格的凭据是一份抄件（#220 的数据那一半已用 r104_temp_lines.txt 钉住，
# 这一半是让工具自己产它 —— 否则复现的人拿不到同一件东西）。
SERIAL_SECS=${SERIAL_SECS:-9}
RAWW=$OUT.serial.raw
# ⚠ `[TEMP] degC=…` 不是周期打印：那句 `xil_printf` 在 **temp 命令的处理路**里（`src/ps/main.c:889`），
#   屏上那一格才是每秒由 `temp_poll` 刷的。所以被动守窗口抓 14 秒**一行 [TEMP] 都不会有**
#   （02:39 实测：COM6 打得到、`CAPTURED_LEN 0`）—— 判据①的地板必须由**发命令**去兑现。
#   `-Cmds` 是按空白拆词的，所以这里只给不带空格的单词，逗号分隔；读命令不改板上状态。
powershell -NoProfile -ExecutionPolicy Bypass -File board/uart_cap_once.ps1 \
  -Port COM6 -Seconds "$SERIAL_SECS" -Drain -Cmds "temp,STAT,temp,STAT" -CmdDelay 2 \
  -Out "$RAWW" >/dev/null 2>&1
PSRC=$?
if [ -z "$ROUND" ]; then
  # 没有版本身份就不写 rNN 那份（#179 的教训：脚本自带默认值会把今天的数写成一份名字叫旧轮的假凭据）
  echo "  [SERIAL] 判定=红 —— ROUND 没给（--round=rNN 或 VP_ROUND），这份原始回显没有版本身份 ⇒ 不写 rNN 文件" | tee -a "$LOG"
  echo "           注：powershell 退出码 $PSRC（它就算占不到 COM6 也返回 0，所以判定只看文件内容）" | tee -a "$LOG"
  NRED=$((NRED+1))
else
  SER_DST=build/evidence/r${ROUND}_serial_raw.txt
  # ⚠ 这份文件里**不加表头、不加时间戳、不加 md5**：它的身份就是"板子这一刻打出来的原话"。
  #   一旦加了表头，"空捕获"就会变成"有两行表头的文件"，而"非空"这条判据当场失去牙
  #   （同一族的坑：#179 那个自带默认轮号的脚本）。出身信息留在 $LOG 里，那里有 md5 与时间。
  if [ -f "$RAWW" ]; then
    to_utf8 "$RAWW" "$SER_DST"; CONVRC=$?
    CONVMSG=失败（两种编码都解不开）
    [ "$CONVRC" = 0 ] && CONVMSG=成功
    echo "  [SERIAL] 转码 $CONVMSG（powershell 退出码 $PSRC，只作参考：它占不到 COM6 也返回 0）" | tee -a "$LOG"
    if serial_judge "$SER_DST" "原始回显 $SER_DST"; then
      echo "  [SERIAL] 落点=$SER_DST 行数=$SN_ALL [TEMP]=$SN_TEMP 判定=绿（地板 $TEMP_FLOOR）" | tee -a "$LOG"
    else
      echo "  [SERIAL] 落点=$SER_DST 行数=$SN_ALL [TEMP]=$SN_TEMP 判定=红" | tee -a "$LOG"
      NRED=$((NRED+1))
    fi
    echo "           这份要被跟踪：git add $SER_DST" | tee -a "$LOG"
  else
    echo "  [SERIAL] 捕获脚本没产出 $RAWW ⇒ 不写 $SER_DST（没有内容就没有凭据），判红" | tee -a "$LOG"
    NRED=$((NRED+1))
  fi
fi

echo "-- 2) 读回口：health_read（lane0..9 + 23..31）--" | tee -a "$LOG"
node src/host/health_read.mjs --json > "$OUT.health.json" 2>"$OUT.health.err"
if [ -s "$OUT.health.json" ]; then
  node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const ok = (k, v) => console.log(`  ${k} → ${v}`);
    ok("lane30 src_state", JSON.stringify(j.src_state));
    ok("lane23 zoom", JSON.stringify(j.zoom));
    ok("lat.osd_ms_matches_tot", j.lat && j.lat.osd_ms_matches_tot);
    ok("drop_words", j.drop_words);
  ' "$OUT.health.json" 2>&1 | tee -a "$LOG"
else
  echo "  health_read 没有输出（hw_server 没起？A9 没在跑？）：$(head -2 "$OUT.health.err")" | tee -a "$LOG"
  NRED=$((NRED+1))     # 读回口拿不到 json ⇒ 后面所有"读回来对不对"的判据都不成立，这一版不能算验过
fi

if [ "$DO_STREAM" = 1 ]; then
  # arb_handover_test 自己会 spawn video_sender（参数 IP/SPORT/FPS 在它内部），所以这里不再另起推流；
  # 一次跑完 PRE→STREAM→AFTER→RESTART 四个阶段，约 40 s + 采样，八条判据打在 stdout。
  echo "-- 3) 仲裁交接九条（脚本内部会自己开关推流；含 V1/V1b 拆分：外部在推流不再被当成仲裁故障）--" | tee -a "$LOG"
  # ⚠ 原来这一行是 `node ... | tee x | tail -22 | tee -a $LOG` ⇒ 流水线的退出码是**最后一个 tail 的**，
  #   arb 自己 `process.exit(1)` 的那条红在这里被吞掉：2026-09-25 r59a 那次日志明明白白写着
  #   "[ARB] 结论：1 条不通过 ⇒ 判红，这一版不能采纳"，而整个 board_verify 仍然 VERIFY_EXIT=0。
  #   这就是"假绿"——比假红危险。改法：先落盘再回放，用 PIPESTATUS[0] 拿到 node 的码。
  node src/host/arb_handover_test.mjs > "$OUT.arb.txt" 2>&1
  ARB_RC=$?
  tail -22 "$OUT.arb.txt" | tee -a "$LOG"
  grep -a "九条全过" "$OUT.arb.txt" >/dev/null 2>&1 || ARB_RC=1
  echo "[ARB] 退出码 $ARB_RC（0=九条全绿）" | tee -a "$LOG"
  [ "$ARB_RC" = 0 ] || NRED=$((NRED+1))
  grep -a "arb_handover_last.json" "$OUT.arb.txt" >/dev/null 2>&1 || true
  cp -f build/evidence/arb_handover_last.json "$OUT.arb.json" 2>/dev/null || \
    cp -f /tmp/arb_handover_last.json "$OUT.arb.json" 2>/dev/null || true
fi

if [ "$DO_GEOM" = 1 ]; then
  echo "-- 5) V9 几何自动化的『最后一跳』（geom_check：命令 → 读回像素域 lane23 / CFG_DATA0）--" | tee -a "$LOG"
  # 为什么单独一步而不并进电池：电池判的是**回显**（固件说了什么），这一条判的是
  # lane23 里像素域自己吐出来的 inv/zoom_code/fit 位，以及 CFG_DATA0 的 19 个几何位。
  # 回显绿而硬件没动，正是本项目反复踩过的那一类（#52/#66/#68），必须分开取证。
  # ⚠ 这一步会动板上状态，脚本结尾自己还原，并用 G4 证明"跑完 == 进来"。
  node src/host/geom_check.mjs --com COM6 > "$OUT.geom.txt" 2>&1
  GEOM_RC=$?
  tail -20 "$OUT.geom.txt" | tee -a "$LOG"
  grep -a "RESULT PASS geom_check" "$OUT.geom.txt" >/dev/null 2>&1 || GEOM_RC=1
  echo "[GEOM] 退出码 $GEOM_RC" | tee -a "$LOG"
  [ "$GEOM_RC" = 0 ] || NRED=$((NRED+1))
fi

if [ "$DO_BATT" = 1 ]; then
  echo "-- 4) 串口命令电池（97 条：V8 的 71 + V9 的 20 + #77 的 6，初末态必须相同）--" | tee -a "$LOG"
  # 同样不能吃管道退出码（原来 `| tail -25 | tee` 之后 $? 是 tee 的）。
  # 这里两重保险：命令自己的退出码 + stdout 里那一行 `RESULT PASS uart_cmd_check`。
  node src/host/uart_cmd_check.mjs --port COM6 > "$OUT.batt.txt" 2>&1
  BATT_RC=$?
  tail -25 "$OUT.batt.txt" | tee -a "$LOG"
  grep -a "RESULT PASS uart_cmd_check" "$OUT.batt.txt" >/dev/null 2>&1 || BATT_RC=1
  echo "[BATT] 退出码 $BATT_RC" | tee -a "$LOG"
  [ "$BATT_RC" = 0 ] || NRED=$((NRED+1))
fi

echo "== 日志留在 $LOG ==" | tee -a "$LOG"
if [ "$NRED" = 0 ]; then
  echo "RESULT board_verify PASS（判红的步骤：0）" | tee -a "$LOG"; exit 0
fi
echo "RESULT board_verify FAIL nred=$NRED ⇒ 这一版不能采纳" | tee -a "$LOG"; exit 1
