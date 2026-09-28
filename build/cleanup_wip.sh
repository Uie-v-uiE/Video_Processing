#!/bin/bash
# build/cleanup_wip.sh —— WIP 目录清点：**默认只报清单，一个字节都不删**
#
# 为什么要它而不是直接 `rm -rf`：本项目的"临时目录"里绝大部分是**凭据**——
# `build/frozen_rNN_*` 与 `build/evidence_rNN` 是 ISSUES / PERF_REPORT / OVERNIGHT_LOG
# 里点名引用的那一份报告与 md5 清单（"每一条说法都要说出它的凭据是哪一份"）。
# 删掉一份被引用过的冻结件 = 把那句话变成不可复查的空话（#68 那一族的反面）。
# 所以这张表的判据是：**凡被 docs/ board/ skill/ 里任何一个文件点到名字的，一律不删**，
# 并且把"为什么不删"一起打在清单里 —— 清单本身要能回答"你凭什么说这个是没用的"。
#
# 用法：
#   bash build/cleanup_wip.sh              # 干跑：报清单（KEEP-CITED / KEEP-NEWEST / DELETE-CAND / 空壳）
#   bash build/cleanup_wip.sh --yes        # 真的删（只删未被引用的）
#   bash build/cleanup_wip.sh --selftest   # 这张表自己的反例测试（能红也能绿，见文件尾）
#
# 顺序上它属于"项目竣工之后"那一步（用户 2026-09-26 的原话是文档之后再清文件），
# 所以今晚只交工具与清单，不交"已经删了"。
#
# ⚠ 两条使用前提，缺一条就可能把正在跑的东西踢掉：
#   ① **跑着 xsim / Vivado 时不要加 --yes** —— `.Xil/` 与 `xsim.dir/` 是它们正在用的锁目录，
#      清单认得它们是"运行壳"，但此刻删等于从车轮下抢扳手；
#   ② `sim_work/` 是老 `run_sim.tcl` 全量流程的工作目录（现在单台架走 `sim/run_one.sh`，
#      跑在 /tmp 下）—— 如果哪天要回退到那条路，它自己会重建，不需要留着。
set -u
ROOT=${CLEANUP_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
CITEDIR=${CLEANUP_CITEDIR:-report board skill}      # 引用来源（selftest 会把它指到一棵假树）
cd "$ROOT" || exit 1
YES=0
for a in "$@"; do [ "$a" = "--yes" ] && YES=1; done

# 候选：构建产物快照 / 冻结件 / 仿真运行壳。全是 .gitignore 已忽略的东西（入库的不在这张表里）。
cands() {
    # shellcheck disable=SC2086
    ls -d build/frozen_* build/evidence build/evidence_* build/failed_* build/snap_* \
          sim_work xsim.dir .Xil .srcs sim/xsim.dir sim/*.run sim/msim \
          build/micro_rd/proj_* build/micro_rd/gen sim/v98run sim/xtest sim/tagchk \
          sim/syntaxchk sim/v100run2 2>/dev/null | LC_ALL=C sort -u
}

# `evidence_rNN` 里号最大的那一份 = 当前冻结件：门禁第 18 项与首页都指着它念，
# 就算文档一时没写上号，也不许被"没被引用"这一条误删。
newest_evidence() {
    ls -d build/evidence_r* 2>/dev/null | sed 's#.*evidence_r##' | LC_ALL=C sort -n | tail -1
}

cited() {                       # $1 = 路径（整串）与 basename 都查一遍
    # shellcheck disable=SC2086
    grep -ra -- "$1" $CITEDIR >/dev/null 2>&1 || grep -ra -- "$(basename "$1")" $CITEDIR >/dev/null 2>&1
}

# 两档口径，不是一条：**构建快照**（frozen_* / evidence_* / failed_* / snap_*）里装的是凭据本身，
# 所以"有没有被文档点名"才决定删不删；**仿真运行壳**（工具就地生成的工程壳、快照、日志）
# 按定义可再生，里面不可能有凭据 ⇒ 无条件可删。
# 为什么不给后者也查引用：`.Xil` 这类名字在 `docs/log/CHANGELOG_V7.md` 里出现过的是
# "Windows 上连跑三次 synth_design 会撞 .Xil 目录锁"这条**技术注记**，不是凭据引用 ——
# 拿它当"被引用"就等于永远清不掉，而这正是本脚本要治的那件事。
junk() {
    case "$(basename "$1")" in
        .Xil|.srcs|xsim.dir|sim_work|msim) return 0 ;;
        *) case "$1" in sim/*.run|sim/v98run|sim/xtest|sim/tagchk|sim/syntaxchk|sim/v100run2) return 0 ;;
                      build/micro_rd/*) return 0 ;; esac ;;
    esac
    return 1
}

report() {
    local NEW KEEP=0 DEL=0
    NEW=$(newest_evidence)
    echo "# 清点 $(date -Iminutes)  引用来源={$CITEDIR}  最新冻结件=r${NEW:-无}"
    for d in $(cands); do
        [ -e "$d" ] || continue
        if junk "$d"; then
            echo "DELETE-JUNK  $d  $(du -sh "$d" 2>/dev/null | cut -f1)   （工具就地生成的运行壳，重跑就有）"
            DEL=$((DEL+1)); [ "$YES" = 1 ] && { rm -rf "$d"; echo "             已删 $d"; }
        elif cited "$d"; then
            echo "KEEP-CITED   $d"
            KEEP=$((KEEP+1))
        elif [ "$(basename "$d")" = "evidence_r$NEW" ]; then
            echo "KEEP-NEWEST  $d          （首页/门禁第 18 项念的是它，没写进引用也不算可删）"
            KEEP=$((KEEP+1))
        elif [ -d "$d" ] && [ -z "$(ls -A "$d" 2>/dev/null)" ]; then
            echo "EMPTY        $d          （空壳）"
            DEL=$((DEL+1)); [ "$YES" = 1 ] && rmdir "$d" 2>/dev/null
        elif [ -f "$d" ] && [ ! -s "$d" ]; then     # ⚠ 必须先 `-f`：本机 `[ -s 目录 ]` 恒为假，
            echo "ZERO-BYTE    $d"                  #   少了这一句会把每个非空目录都误判成"零字节"，
            DEL=$((DEL+1)); [ "$YES" = 1 ] && rm -f "$d"   # 而 `rm -f 目录` 删不动 ⇒ selftest 第 8 条抓住的就是它
        else
            echo "DELETE-CAND  $d  $(du -sh "$d" 2>/dev/null | cut -f1)"
            DEL=$((DEL+1)); [ "$YES" = 1 ] && { rm -rf "$d"; echo "             已删 $d"; }
        fi
    done
    echo "# 小结：KEEP $KEEP，可删 $DEL"
    if [ "$YES" = 1 ]; then echo "# ⚠ 这一轮是 --yes：可删的那些已经删了"; else
        echo "# 这一轮没有删任何东西（要删就加 --yes，并先把上面这张表看一遍）"; fi
}

# ---------- 反例测试：证明这张表既不会删凭据、也不会什么都清不掉 ----------
# 跑法：造一棵只读意义上的假树（三个目录 + 一份"报告"），把 ROOT/CITEDIR 指过去再跑本脚本。
selftest() {
    local T=${TMPDIR:-/tmp}/cleanup_wip_self.$$
    local nbad=0 out
    # 四个 fixture 各钉住**一条分支**：目录里必须真有东西，否则会一律掉进"空壳"那条，
    # 于是"被引用不删"这一条其实从没被验过（第一版就是这样：四个空目录，三条期望全红）。
    mkdir -p "$T/report" "$T/build/frozen_r99_cited" "$T/build/frozen_r98_uncited" \
             "$T/build/evidence_r97" "$T/build/frozen_r00_empty" "$T/sim_work"
    : > "$T/build/frozen_r99_cited/x.rpt"
    : > "$T/build/frozen_r98_uncited/x.rpt"
    : > "$T/build/evidence_r97/x.rpt"                 # 故意**不**被引用：验的是 KEEP-NEWEST 那条
    : > "$T/sim_work/x.rpt"                           # 运行壳：即使被引用也归可删（第 9 条钉的就是它）
    echo "凭据见 build/frozen_r99_cited；顺带提一句 sim_work" > "$T/docs/X.md"
    out=$(CLEANUP_ROOT="$T" CLEANUP_CITEDIR=report bash "$0" 2>&1)
    chk() { echo "$out" | grep -q "$1" || { echo "SELFTEST FAIL $2: 清单里没有这一行 [$1]"; nbad=1; }; }
    chk "KEEP-CITED   build/frozen_r99_cited" 1
    chk "DELETE-CAND  build/frozen_r98_uncited" 2
    chk "KEEP-NEWEST  build/evidence_r97" 3
    chk "EMPTY        build/frozen_r00_empty" 4
    chk "DELETE-JUNK  sim_work" 9
    [ -d "$T/build/frozen_r98_uncited" ] || { echo "SELFTEST FAIL 5: 干跑就删了东西"; nbad=1; }
    [ -d "$T/sim_work" ] || { echo "SELFTEST FAIL 10: 干跑把运行壳删了"; nbad=1; }
    CLEANUP_ROOT="$T" CLEANUP_CITEDIR=report bash "$0" --yes >/dev/null 2>&1
    [ -d "$T/build/frozen_r99_cited" ] || { echo "SELFTEST FAIL 6: --yes 把被引用的删了"; nbad=1; }
    [ -d "$T/build/evidence_r97" ]     || { echo "SELFTEST FAIL 7: --yes 把最新冻结件删了"; nbad=1; }
    [ -d "$T/build/frozen_r98_uncited" ] && { echo "SELFTEST FAIL 8: --yes 没删掉可删项"; nbad=1; }
    [ -d "$T/sim_work" ] && { echo "SELFTEST FAIL 11: --yes 没删掉运行壳"; nbad=1; }
    rm -rf "$T"
    if [ "$nbad" = 0 ]; then
        echo "SELFTEST PASS 11/11：留被引用的、留最新冻结件、空壳认得出、运行壳无条件可删、干跑不删、--yes 才删且只删可删项"
    fi
    exit $nbad
}

for a in "$@"; do [ "$a" = "--selftest" ] && selftest; done
report
