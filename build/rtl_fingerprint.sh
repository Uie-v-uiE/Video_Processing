#!/bin/bash
# 用途：全仓唯一的一处"源码指纹"定义（`fpver=norm1`）
# 输入：命令行参数
# 输出：stdout
# 退出码：0=跑完 1=FAIL 2=非 0 分支（该文件 exit 2 那一行）
# build/rtl_fingerprint.sh —— 全仓唯一的一处"源码指纹"定义（`fpver=norm1`）
#
#   bash build/rtl_fingerprint.sh                        # 打印 fpver/files/top/rtl，可 eval
#   bash build/rtl_fingerprint.sh sim/tb_v98_top_seam.v  # 单文件的 norm1（32 位）
#   bash build/rtl_fingerprint.sh --bridge <kind> <raw12> [路径]   # 旧 raw → norm1，查不到交空串
#   bash build/rtl_fingerprint.sh --match <kind> <报告值> <当前值> [路径]  # 只念 fresh/bridge/no
#   bash build/rtl_fingerprint.sh --self                 # 六条对照，红即这把尺子不可用
#
# 为什么要把定义抽出来（2026-09-30，r97 收口当晚撞出来的）：
#   原来 `build/sim/run_one.sh`、`build/gates.sh`(15/15b)、`build/freeze_evidence.sh` 各写了一遍
#   `find src/rtl … | xargs md5sum | md5sum`，算的是**磁盘字节**。本机 `core.autocrlf=true`
#   且没有 `.gitattributes` ⇒ 一次 `git checkout -- src/rtl` 把 79 份 `.v` 里的 52 份从 LF 重写成
#   CRLF：内容一字未改（`git diff -- src/rtl` 为空），合指纹却从 45e09e8b3b9d 变成 6ab3898eccae，
#   于是第 15/15b 项把"我自己刚还原的树"念成"这份报告不算当前树"。
#   尺子量的维度错了：**换行编码不是设计**（Verilog 里 CR 是空白，Vivado/xsim 都按内容读），
#   而"内容被改过"这件事仍然一个字符都瞒不住 —— 见 --self 的 F2。
#   norm1 = 每份文件先 `tr -d '\r'` 再取 md5，行格式固定为 "<32位md5>  <相对路径>\n"
#   （不依赖 md5sum 在 MSYS 上给文件名加 `*` 这个二进制标记习惯），按 C 排序后合一次 md5 取 12 位。
#
# 旧的 raw 值不作废：`build/fingerprint_bridge.txt` 每行把一次构建留下的 raw 指纹桥到它的
#   norm1，依据是**那次提交里的内容**（git 对象），--self 的 F4/F4b 会把每行重算并证明
#   "陌生 raw 查不到"（查不到调用方就判红，不许"桥不了就当过"）。
set -u
ROOT=${FP_ROOT:-"$(cd "$(dirname "$0")/.." && pwd)"}
cd "$ROOT" || exit 2
BRIDGE=build/fingerprint_bridge.txt

norm1_file() { tr -d '\r' < "$1" | md5sum | cut -d' ' -f1; }   # 32 位

norm1_rtl() {   # 整个 src/rtl 的合指纹（相对路径就是 find 的输出形状）
    find src/rtl -name '*.v' | LC_ALL=C sort | while read -r f; do
        printf '%s  %s\n' "$(norm1_file "$f")" "$f"
    done | md5sum | cut -c1-12
}

case "${1:-}" in
    ('')
        echo "fpver=norm1"
        echo "files=$(find src/rtl -name '*.v' | wc -l)"
        echo "top=$(norm1_file src/rtl/top/pl_video_top.v | cut -c1-12)"
        echo "rtl=$(norm1_rtl)"
        ;;
    (--bridge)
        KIND=${2:-}; LEG=${3:-}; PW=${4:-}
        [ -f "$BRIDGE" ] || exit 0
        [ -n "$KIND" ] && [ -n "$LEG" ] || exit 0
        grep -v '^#' "$BRIDGE" | awk -v k="$KIND" -v l="$LEG" -v p="$PW" '
            { kind=""; raw=""; norm=""; fp=""
              for (i=1;i<=NF;i++) {
                  if ($i ~ /^kind=/)       { split($i,a,"="); kind=a[2] }
                  if ($i ~ /^legacy_raw=/) { split($i,a,"="); raw=a[2] }
                  if ($i ~ /^norm1=/)      { split($i,a,"="); norm=a[2] }
                  if ($i ~ /^path=/)       { split($i,a,"="); fp=a[2] }
              }
              if (kind==k && raw==l && (k!="file" || fp==p)) { print substr(norm,1,12); exit } }'
        ;;
    (--match)
        # 门禁/冻结只念这一个函数：fresh=报告里就是当前 norm1；bridge=报告还是旧 raw 且该 raw
        # 经桥接表指到同一个 norm1；其它一律 no（调用方判红）。三种都由 --self 的 F5 演过。
        KIND=${2:-}; YES=${3:-}; WANT=${4:-}; PW=${5:-}
        if [ "$YES" = "$WANT" ]; then echo fresh; exit 0; fi
        B=$(bash build/rtl_fingerprint.sh --bridge "$KIND" "$YES" "$PW")
        if [ -n "$B" ] && [ "$B" = "$WANT" ]; then echo bridge; else echo no; fi
        ;;
    (--self)
        FAIL=0
        say() { # $1 名字 $2 期望 $3 实际
            if [ "$2" = "$3" ]; then echo "PASS F-SELF $1"
            else echo "FAIL F-SELF $1 (want=$2 got=$3)"; FAIL=$((FAIL+1)); fi
        }
        T=$(mktemp -d)
        pair() { ( cd "$1" && { printf '%s  %s\n' "$(norm1_file src/a.v)" src/a.v
                                 printf '%s  %s\n' "$(norm1_file src/b.v)" src/b.v; } \
                   | md5sum | cut -c1-12 ); }
        # F1 换行编码不变性：同一份内容，全 LF 与全 CRLF 两棵树必须给同一个合指纹
        mkdir -p "$T/lf/src" "$T/crlf/src"
        printf 'module a;\nendmodule\n' > "$T/lf/src/a.v"
        printf 'module b;\nendmodule\n' > "$T/lf/src/b.v"
        sed 's/$/\r/' "$T/lf/src/a.v" > "$T/crlf/src/a.v"
        sed 's/$/\r/' "$T/lf/src/b.v" > "$T/crlf/src/b.v"
        BASE=$(pair "$T/lf")
        say "F1 CRLF 翻转不改指纹" "$BASE" "$(pair "$T/crlf")"
        # F2 正对照：真改一个字符，指纹必须动（不然这把尺子在空集上绿）
        printf 'module a;\nendmodule //x\n' > "$T/lf/src/a.v"
        if [ "$(pair "$T/lf")" = "$BASE" ]; then say "F2 改内容必须动" "动了" "没动"
        else echo "PASS F-SELF F2 改内容会动指纹"; fi
        # F3 扫描面：文件数必须等于 git 跟踪的 src/rtl/*.v 数（尺子的范围会静默漂，#194 同族）
        NOW=$(find src/rtl -name '*.v' | wc -l)
        GIT=$(git ls-files 'src/rtl/*.v' 2>/dev/null | wc -l)
        say "F3 扫描面=git 跟踪数" "$GIT" "$NOW"
        # F4 桥接表：每一行按**它自己点名的那个 git 对象**重算，不是按当前树重算。
        #   按当前树重算是错的（我第一版就这么写）：桥接行描述的是"某一次构建当时的内容"，
        #   下一轮只要动一次 RTL，它就该与当前树不等 ⇒ 这条对照会在之后的每一个真实轮次里红一次，
        #   最后被人当噪声关掉 —— 那正是 #194 说的"尺子自己变成障碍"。
        #   不变的性质应该是："行里的 norm1 能从它引用的提交里重新算出来"。
        NROW=0; BOK=1
        if [ -f "$BRIDGE" ]; then
            while read -r kind sha path norm; do
                [ -n "$kind" ] || continue
                NROW=$((NROW+1))
                case "$kind" in
                    rtl)
                        A=$(mktemp -d)
                        if ! git -C "$ROOT" archive "$sha" src/rtl 2>/dev/null | tar -x -C "$A"; then
                            echo "        桥接行引用的 $sha 取不出来"; BOK=0; rm -rf "$A"; continue; fi
                        WANT=$( cd "$A" && find src/rtl -name '*.v' | LC_ALL=C sort | while read -r f; do
                                    printf '%s  %s\n' "$(norm1_file "$f")" "$f"; done | md5sum | cut -c1-12 )
                        rm -rf "$A";;
                    file)
                        WANT=$(git -C "$ROOT" show "$sha:$path" 2>/dev/null | tr -d '\r' | md5sum | cut -c1-12)
                        [ -n "$WANT" ] || { echo "        桥接行引用的 $sha:$path 取不出来"; BOK=0; continue; };;
                    *)  echo "        桥接行 kind=$kind 不认识"; BOK=0; continue;;
                esac
                [ "$WANT" = "$norm" ] || { echo "        桥接行 $kind $sha 写的是 $norm，重算=$WANT"; BOK=0; }
            done < <(grep -v '^#' "$BRIDGE" | awk '
                { kind=""; norm=""; fp=""; sha=""
                  for (i=1;i<=NF;i++) {
                      if ($i ~ /^kind=/)     { split($i,a,"="); kind=a[2] }
                      if ($i ~ /^norm1=/)    { split($i,a,"="); norm=a[2] }
                      if ($i ~ /^path=/)     { split($i,a,"="); fp=a[2] }
                      if ($i ~ /^from=git:/) { split($i,a,"="); split(substr(a[2],5),b,":"); sha=b[1] }
                  }
                  if (kind=="rtl")  print kind, sha, "none", norm
                  if (kind=="file") print kind, sha, fp, norm }')
        fi
        if [ "$NROW" -gt 0 ]; then
            if [ "$BOK" = 1 ]; then echo "PASS F-SELF F4 $NROW 条桥接行都能从点名的提交里重算出来"
            else say "F4 桥接行对账" "1" "0"; fi
        else echo "PASS F-SELF F4 没有桥接行（当前没有 legacy 值要对）"; fi
        # F4b 反例：表里没有的 raw 必须查不到（否则"桥不了"会被当成"过了"）
        if [ -n "$(bash build/rtl_fingerprint.sh --bridge rtl deadbeefdead)" ]; then
            say "F4b 陌生 raw 必须查不到" "空" "非空"
        else echo "PASS F-SELF F4b 陌生 raw 查不到"; fi
        # F5 --match 的三种答案各演一次：过桥不等于放行（陌生 raw 必须 no）
        say "F5a 同值=fresh" "fresh" "$(bash build/rtl_fingerprint.sh --match rtl 438f72a4e150 438f72a4e150)"
        say "F5b 旧 raw 在表里=bridge" "bridge" "$(bash build/rtl_fingerprint.sh --match rtl 45e09e8b3b9d 438f72a4e150)"
        say "F5c 旧 raw 不在表里=no" "no" "$(bash build/rtl_fingerprint.sh --match rtl 1234567890ab 438f72a4e150)"
        say "F5d 旧 raw 在表里但指的不是当前值=no" "no" "$(bash build/rtl_fingerprint.sh --match rtl 45e09e8b3b9d aaaaaaaaaaaa)"
        rm -rf "$T"
        [ "$FAIL" = 0 ] || { echo "RESULT rtl_fingerprint --self FAIL nfail=$FAIL"; exit 1; }
        echo "RESULT rtl_fingerprint --self PASS"
        ;;
    (*)
        [ -f "$1" ] || { echo "FATAL 读不到 $1"; exit 2; }
        norm1_file "$1"
        ;;
esac
