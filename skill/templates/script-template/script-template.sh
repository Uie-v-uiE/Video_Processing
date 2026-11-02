#!/usr/bin/env bash
# 用途：读一组已生成的报告/日志，按写死的判据逐条判定，并归档一份可复核的凭据（脚本模板，不含任何具体业务）。
# 前置条件：bash 4+；槽位（下面 SLOTS 段）全部填好；REPORT_DIR 指向**同一套产物**的报告目录；
#           需要探测的可执行文件由 TOOL_BIN_DIR 或 PATH 提供；无需 root、无需连硬件。
# 产出物路径：$ARCHIVE/${ROUND}_${STAMP}/ 下 manifest.txt（工具版本 + 逐件 md5 + 新鲜度注）与
#             checkpoints/（设了 STAGE 才有）；逐条判定打到标准输出，由调用方重定向成该轮凭据件。
# 失败时先看哪里：第一行是 REFUSE ⇒ 前置不满足（退 3），那不是判红；没有 REFUSE 才看 n/a 行（缺凭据，退 2）；
#             两类都没有才看 FAIL 行（退 1）。
#
# 退出码约定（本模板的定义；迁移到别的仓库时对齐一种即可，别在同一套脚本里混用两种映射）：
#   0 = PASS           所有已判定项都过，且没有任何一项因缺凭据未判
#   1 = FAIL           至少一项判红（这是一个结论）
#   2 = NOT_MEASURED   读不到输入 / 判定 0 项 / 射程不足 / 有未判项（**没数不等于通过**）
#   3 = 前置不满足     可执行文件探测失败、必需报告缺、槽位没填 —— 在写任何产物之前拒绝启动
#
# 打印约定（下游按行首词判定 ⇒ "有未判"那一档必须换行首词，只加一个计数不算修好）：
#   逐项：  <两空格><名字 ≤22 字宽><实测 ≤12 字宽><判据文本 ≤28 字宽>  PASS|FAIL|n/a
#   计数：  判定 N 项、红 M 项、未判 K 项
#   收尾：  RESULT: ALL PASS（判定 N 项，未判 0 项）
#           RESULT: 有红项（判定 N 项，红 M 项）
#           RESULT: PARTIAL —— 判定 N 项全过，但有 K 项因缺凭据未判
#           RESULT: NO-VERDICT —— 判定 0 项 / 射程不足（一把扫不到东西的尺子不许报绿）
#   拒绝：  REFUSE: <缺什么>（当前 <变量名>=<值>）
#   标签一律 ASCII 或短标记：过长的非 ASCII 标签会被容器按字节从**左边**截断，
#           那条判据在日志里的编号就不是它自己了（"六条只数到五条"这一族）。
#
# 用法：
#   bash script-template.sh                    # 判 REPORT_DIR 这一套（槽位用环境变量给）
#   bash script-template.sh --self             # 跑本脚本自带的 6 条反例，证明它真的能红
#   REPORT_DIR=<某组成套冻结件> ROUND=r99 bash script-template.sh
set -u

EXIT_PASS=0; EXIT_FAIL=1; EXIT_NOT_MEASURED=2; EXIT_PRECOND=3

# ---- SLOTS：工程专有名只出现在这里；正文其余部分不许出现具体模块名/引脚名/文件名 ----
TOOL_BIN_DIR=${TOOL_BIN_DIR:-}   # 指向 <工具>/bin；不设则用 PATH 探测 REQ_TOOL
REQ_TOOL=${REQ_TOOL:-}           # 必须存在的一个可执行文件名（探测锚点）
VERSION_CMD=${VERSION_CMD:-}     # 打印版本的命令；不设则版本行记 n/a
REPORT_DIR=${REPORT_DIR:-}       # 同一套产物的报告目录
ARCHIVE=${ARCHIVE:-}             # 凭据输出根目录（不设则 /tmp）
ROUND=${ROUND:-}                 # 本轮轮次号，进归档目录名
R_TIMING=${R_TIMING:-}           # 关键读数文件名（相对 REPORT_DIR）
R_RESOURCE=${R_RESOURCE:-}       # 资源读数文件名
R_STATUS=${R_STATUS:-}           # 收尾状态文件名
DONE_TOKEN=${DONE_TOKEN:-}       # 在该文件里 grep 的收尾标记（ASCII、不带空格）
ROW_RE=${ROW_RE:-}               # 关键读数所在行的正则；示例取值需替换：本仓库 build/gates.sh:68
                                 #   认的是"带符号小数 + 整数"连排的那一行形状
COL_WNS=${COL_WNS:-1}            # 该行里裕量列的列号
COL_EP=${COL_EP:-3}              # 该行里失败端点数的列号
MIN_PARSED=${MIN_PARSED:-3}      # 射程地板：至少判成几项才算这把尺子在量东西
SRC_DIR=${SRC_DIR:-}             # 源码目录（设了才比"源是否比报告新"；不设就在清单里写明未比）

# ---- 0) --self：拿合成件喂自己；每条反例必须落到它该落的那个退出码**和那一行收尾词** ----
if [ "${1:-}" = "--self" ]; then
    SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
    T=$(mktemp -d 2>/dev/null) || { echo "SELF-FATAL 建不起临时目录"; exit "$EXIT_PRECOND"; }
    printf '%s\n' "0.739 0.000 0 51135 0.052 0.000 0 51135"  > "$T/timing.rpt"
    printf '%s\n' "-0.482 -6.457 19 51135 0.030 0.000 0 51135" > "$T/neg.rpt"
    printf '%s\n' "14154 8188 95.5"                           > "$T/usage.rpt"
    printf '%s\n' "DONE_MARKER here"                           > "$T/status.rpt"
    : > "$T/empty.rpt"
    SELF_FAIL=0; SELF_N=0
    has() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
    run_case() { # run_case <期望rc> <说明> [KEY=VAL 覆盖…]
        local want=$1 why=$2; shift 2
        local cw="$T/case.sh" kv out rc tok bad
        # 不用 `env` 传变量：这台机器 PATH 上可能有一个吞输出的 env 垫片，会把"没跑成"伪装成 rc=0。
        { echo 'set -u'
          echo "export REQ_TOOL=bash"
          echo "export VERSION_CMD='bash --version | head -1'"
          echo "export ARCHIVE='$T/out'"; echo "export ROUND=self"; echo "export REPORT_DIR='$T'"
          echo "export R_TIMING=timing.rpt"; echo "export R_RESOURCE=usage.rpt"; echo "export R_STATUS=status.rpt"
          echo "export DONE_TOKEN=DONE_MARKER"
          echo "export ROW_RE='^[ ]*[-+]?[0-9]+\.[0-9]+[ ]+[-+]?[0-9]+\.[0-9]+'"
          for kv in "$@"; do [ -n "$kv" ] && printf "%s\n" "$kv" | sed "s/^/export /; s/=/='/; s|\$|'|"; done
          echo "bash '$SELF'"
        } > "$cw"
        out=$(bash "$cw" 2>&1); rc=$?
        tok=$(printf '%s\n' "$out" | grep -a '^RESULT:' | head -1)
        SELF_N=$((SELF_N+1))
        if [ "$rc" != "$want" ]; then
            echo "FAIL 反例：$why 期望 rc=$want 实到 rc=$rc"; SELF_FAIL=$((SELF_FAIL+1)); return
        fi
        bad=""
        case "$want" in
            "$EXIT_PASS")         has "$tok" "ALL PASS"  || bad="收尾行不是 ALL PASS（tok=[$tok]）";;
            "$EXIT_FAIL")         has "$tok" "有红项"     || bad="收尾行不是「有红项」（tok=[$tok]）";;
            "$EXIT_NOT_MEASURED") { has "$tok" "NO-VERDICT" || has "$tok" "PARTIAL"; } || bad="收尾词既不是 NO-VERDICT 也不是 PARTIAL（tok=[$tok]）";;
            "$EXIT_PRECOND")      has "$out" "REFUSE"    || bad="没有 REFUSE 行（tok=[$tok]）";;
        esac
        if [ -n "$bad" ]; then
            echo "FAIL 反例：$why $bad"; SELF_FAIL=$((SELF_FAIL+1)); return
        fi
        echo "PASS 反例：$why（rc=$rc｜$tok）"; }
    run_case "$EXIT_PASS"         "正例：好读数必须绿"
    run_case "$EXIT_FAIL"         "反例 1：带符号的负裕量必须被读出来并判红" R_TIMING=neg.rpt
    run_case "$EXIT_NOT_MEASURED" "反例 2：报告里没有那一行 ⇒ 未判，不许绿" R_TIMING=empty.rpt
    run_case "$EXIT_NOT_MEASURED" "反例 3：射程地板高于判定项 ⇒ 不许绿" MIN_PARSED=99
    run_case "$EXIT_PRECOND"      "反例 4：必需报告缺文件 ⇒ 第一步拒绝，不留半截产物" R_TIMING=nosuch_file.rpt
    run_case "$EXIT_PRECOND"      "反例 5：行正则没填 ⇒ 拒绝启动（空正则会把任意行当读数）" ROW_RE=
    run_case "$EXIT_PRECOND"      "反例 6：可执行文件探测不到 ⇒ 拒绝启动" REQ_TOOL=nosuch_tool_xyz
    rm -rf "$T"
    if [ "$SELF_FAIL" = 0 ]; then echo "SELF: 全绿（$SELF_N 条）"; exit "$EXIT_PASS"; fi
    echo "SELF: 有 $SELF_FAIL 条反例不成立 —— 这把尺子没有牙，先修它再谈判读"; exit "$EXIT_FAIL"
fi

# ---- 1) 前置探测：槽位没填或工具不在就退 3，绝不往下跑 ----
REFUSE() { echo "REFUSE: $1（当前 $2=$3）"; exit "$EXIT_PRECOND"; }
[ -n "$REPORT_DIR" ] || REFUSE "没设报告目录" REPORT_DIR "$REPORT_DIR"
[ -n "$ROUND" ]      || REFUSE "没设轮次号" ROUND "$ROUND"
[ -n "$R_TIMING" ] && [ -n "$R_RESOURCE" ] && [ -n "$R_STATUS" ] \
    || REFUSE "三份必需报告名没填全" "R_TIMING/R_RESOURCE/R_STATUS" "$R_TIMING/$R_RESOURCE/$R_STATUS"
[ -n "$ROW_RE" ] && [ -n "$DONE_TOKEN" ] \
    || REFUSE "行正则或收尾标记没填" "ROW_RE/DONE_TOKEN" "$ROW_RE/$DONE_TOKEN"
[ -n "$REQ_TOOL" ] || REFUSE "没设探测锚点可执行文件" REQ_TOOL "$REQ_TOOL"
BIN_OK=""
if [ -n "$TOOL_BIN_DIR" ] && [ -x "$TOOL_BIN_DIR/$REQ_TOOL" ]; then BIN_OK="$TOOL_BIN_DIR/$REQ_TOOL"
elif command -v "$REQ_TOOL" >/dev/null 2>&1; then BIN_OK=$(command -v "$REQ_TOOL")
else REFUSE "找不到可执行文件（设 TOOL_BIN_DIR 或把它放进 PATH）" TOOL_BIN_DIR "$TOOL_BIN_DIR"
fi
[ -n "$BIN_OK" ] || REFUSE "可执行文件不可执行" REQ_TOOL "$REQ_TOOL"

TOOL_VERSION="n/a"
if [ -n "$VERSION_CMD" ]; then
    TOOL_VERSION=$(bash -c "$VERSION_CMD" 2>&1 | head -2 | tr '\n' ' ' | cut -c1-120)
    [ -n "$TOOL_VERSION" ] || TOOL_VERSION="n/a"
fi

MISS=""
for f in "$R_TIMING" "$R_RESOURCE" "$R_STATUS"; do
    [ -f "$REPORT_DIR/$f" ] || MISS="$MISS $REPORT_DIR/$f"
done
[ -z "$MISS" ] || REFUSE "缺报告（这套产物不完整，不许用其余文件外推）" "缺的文件" "$MISS"

# 产物之间成套，但整批可能都比源码旧 ⇒ 念到的是上一版。SRC_DIR 不设就在清单里写明未比。
FRESH_WARN=""; FRESH_NOTE=""
if [ -n "$SRC_DIR" ]; then
    NEWEST_SRC=$(find "$SRC_DIR" \( -name '*.v' -o -name '*.c' \) 2>/dev/null | head -1)
    if [ -n "$NEWEST_SRC" ] && [ -f "$NEWEST_SRC" ] && [ "$NEWEST_SRC" -nt "$REPORT_DIR/$R_TIMING" ]; then
        FRESH_WARN="$NEWEST_SRC 比 $R_TIMING 新 ⇒ 这份报告可能不含最新改动（先确认构建已结束再念判定）"
    else
        FRESH_NOTE="已比过 $SRC_DIR 与报告的时间戳（没有更新的源）"
    fi
fi

# ---- 2) 归档目录（版本进目录名与清单；不覆盖上一轮）----
STAMP=$(date +%Y%m%d-%H%M%S)
OUT="${ARCHIVE:-/tmp}/${ROUND}_${STAMP}"
mkdir -p "$OUT" || REFUSE "归档目录建不出来" OUT "$OUT"
{ echo "tool=$BIN_OK"
  echo "tool_version=$TOOL_VERSION"
  echo "report_dir=$REPORT_DIR"
  echo "round=$ROUND stamp=$STAMP"
  echo "freshness_warn=${FRESH_WARN:-无}"
  echo "freshness_note=${FRESH_NOTE:-未设 SRC_DIR ⇒ 未比时间戳}"
  for f in "$R_TIMING" "$R_RESOURCE" "$R_STATUS"; do
      echo "md5 $f=$(md5sum "$REPORT_DIR/$f" | cut -c1-12)"; done; } > "$OUT/manifest.txt"
[ -z "$FRESH_WARN" ] || echo "        WARN $FRESH_WARN"
echo "归档：$OUT"

# ---- 3) 判定器：三态 + 射程地板 ----
NSAY=0; NNA=0; NFAIL=0
say() { # say <名字> <实测> <判据文本> <1|0|NA>
    NSAY=$((NSAY+1))
    if [ "$4" = "NA" ]; then NNA=$((NNA+1)); printf "  %-22s %-12s %-28s %s\n" "$1" "$2" "$3" "n/a"; return; fi
    if [ "$4" = 1 ]; then printf "  %-22s %-12s %-28s %s\n" "$1" "$2" "$3" "PASS"
    else NFAIL=$((NFAIL+1)); printf "  %-22s %-12s %-28s %s\n" "$1" "$2" "$3" "FAIL"; fi; }

# 从文件按行正则取第 n 列；读不到 ⇒ 把该文件里最像的三行打出来并返回 NA（**不许返回 0**）。
# 行正则必须允许数字带符号：违例时是负数，只给部分列留符号位会让整行不匹配，
# 于是"最该看见的那个数"被换成一句"读不到"——停下来是对的，但信息丢了。
pick() { # pick <文件> <行正则> <列号>
    local f=$1 re=$2 col=$3 line
    line=$(grep -aE "$re" "$f" | head -1)
    if [ -z "$line" ]; then
        echo "        读不到：$(basename "$f") 里没有匹配该形状的行；该文件最像的三行是：" >&2
        grep -aE '^[ ]*[-+]?[0-9]+' "$f" | head -3 | sed 's/^/          /' >&2
        echo NA; return
    fi
    printf '%s\n' "$line" | awk -v c="$col" '{print $c}'
}

VAL_WNS=$(pick "$REPORT_DIR/$R_TIMING" "$ROW_RE" "$COL_WNS")
if [ "$VAL_WNS" = NA ] || [ -z "$VAL_WNS" ]; then say "关键裕量(带符号)" "NA" ">= 0" NA
else say "关键裕量(带符号)" "$VAL_WNS" ">= 0" "$(awk -v v="$VAL_WNS" 'BEGIN{print (v+0>=0)?1:0}')"; fi

VAL_EP=$(pick "$REPORT_DIR/$R_TIMING" "$ROW_RE" "$COL_EP")
if [ "$VAL_EP" = NA ] || [ -z "$VAL_EP" ]; then say "失败端点数" "NA" "== 0" NA
else say "失败端点数" "$VAL_EP" "== 0" "$([ "$VAL_EP" = 0 ] && echo 1 || echo 0)"; fi

VAL_RES=$(pick "$REPORT_DIR/$R_RESOURCE" '^[ ]*[-+]?[0-9]+' 1)
if [ "$VAL_RES" = NA ] || [ -z "$VAL_RES" ]; then say "资源读数可解析" "NA" "非空且为数字" NA
else say "资源读数可解析" "$VAL_RES" "非空且为数字" 1; fi

DONE_N=$(grep -ac "$DONE_TOKEN" "$REPORT_DIR/$R_STATUS" 2>/dev/null); DONE_N=${DONE_N:-0}
say "收尾标记行数" "$DONE_N" ">= 1" "$([ "$DONE_N" -ge 1 ] && echo 1 || echo 0)"
# 【填入】在这里加你自己的判据行（逐域读数、告警类计数、文档对账、跨域配对集合……），
#   每加一条就在 --self 里加一条"它必须能红"的反例；判据不许靠没人反对变绿。

# ---- 4) 分阶段检查点（长流程用；跨构建比较前先确认同一批种子/策略）----
if [ -n "${STAGE:-}" ]; then
    mkdir -p "$OUT/checkpoints"
    for f in "$R_TIMING" "$R_RESOURCE" "$R_STATUS"; do
        cp -f "$REPORT_DIR/$f" "$OUT/checkpoints/${STAGE}_${f}"; done
    echo "检查点：$OUT/checkpoints/${STAGE}_*（可从它低成本复算后半流程，不必重跑全量；"
    echo "        比较前先确认两跑用的是同一个检查点、同一批种子/策略，否则差值没有意义）"
fi

# ---- 5) 收尾：条数与第三态一起念出来，行首词按状态区分 ----
echo "判定 $NSAY 项、红 $NFAIL 项、未判 $NNA 项"
if [ "$NSAY" = 0 ]; then
    echo "RESULT: NO-VERDICT —— 判定 0 项（这把尺子什么都没扫到，不许当绿）"; exit "$EXIT_NOT_MEASURED"
elif [ "$NSAY" -lt "$MIN_PARSED" ]; then
    echo "RESULT: NO-VERDICT —— 判定 $NSAY 项 < 射程地板 $MIN_PARSED 项（射程不足）"; exit "$EXIT_NOT_MEASURED"
elif [ "$NFAIL" != 0 ]; then
    echo "RESULT: 有红项（判定 $NSAY 项，红 $NFAIL 项）"; exit "$EXIT_FAIL"
elif [ "$NNA" != 0 ]; then
    echo "RESULT: PARTIAL —— 判定 $NSAY 项全过，但有 $NNA 项因缺凭据未判"; exit "$EXIT_NOT_MEASURED"
else
    echo "RESULT: ALL PASS（判定 $NSAY 项，未判 0 项）"; exit "$EXIT_PASS"
fi
