#!/usr/bin/env bash
# build/checks/check_repo_hygiene.sh —— 仓库级"许可 + 声明 + 命名 + 敏感信息 + 断链"机检（P20 交付物）
#
# 只读：不修改任何工程文件、不写仓库内任何东西、不联网。--self 的反例只写在临时目录，跑完删掉。
#
# 用法
#   bash build/checks/check_repo_hygiene.sh            # 正式运行
#   bash build/checks/check_repo_hygiene.sh --self     # 自带反例：证明每一条判据都会红
#   bash build/checks/check_repo_hygiene.sh --help
#
# 输出契约
#   * 每条检查一行，判定 token 恒在**最后一个字段**：PASS / FAIL / NOT_MEASURED
#   * 每行都打印分母：`判 N 项`
#   * 读不到输入 = NOT_MEASURED，绝不等于 PASS
#   * 判据动不了的行明写"这条判据没有牙"
#
# 退出码（固定，与判据内容无关）
#   0 = 所有判定项都 PASS        1 = 至少一项 FAIL
#   2 = 无 FAIL 但有 NOT_MEASURED 3 = 前置不满足（缺工具 / 不在 git 工作树 / 临时目录落在仓库内）
#
# 条文依据与处置口径：docs/provenance-and-licenses.md；权威声明：report/declarations.md。
set -u

SELF=0; WANT_HELP=0
for a in "$@"; do
    case "$a" in
        --self) SELF=1 ;;
        -h|--help) WANT_HELP=1 ;;
        *) echo "未知参数：$a（可用：--self --help）" >&2 ;;
    esac
done
if [ "$WANT_HELP" = 1 ]; then sed -n '2,23p' "$0"; exit 0; fi

# ---------------------------------------------------------------- 前置（exit 3）
MISSING=""
for t in git grep find sed awk sort uniq stat mktemp tr wc xargs dirname basename; do
    command -v "$t" >/dev/null 2>&1 || MISSING="$MISSING $t"
done
if [ -n "$MISSING" ]; then echo "PREQ | 前置检查 | 判 1 项 | 缺工具：$MISSING | NOT_MEASURED"; exit 3; fi
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$ROOT" ]; then echo "PREQ | 前置检查 | 判 1 项 | 不在 git 工作树内，分发集无从确定 | NOT_MEASURED"; exit 3; fi
cd "$ROOT" || { echo "PREQ | 前置检查 | 判 1 项 | 进不去仓库根 $ROOT | NOT_MEASURED"; exit 3; }

# ---------------------------------------------------------------- 作用域
TRACKED=$(mktemp); UNTRACKED=$(mktemp); ALLF=$(mktemp); HW=$(mktemp); GEN=$(mktemp); OTHER=$(mktemp)
DIRS=$(mktemp); PATHS=$(mktemp); IDENT=$(mktemp); LIVE_MD=$(mktemp)
SANDBOX=""
cleanup() {
    [ -n "$SANDBOX" ] && [ -d "$SANDBOX" ] && rm -rf "$SANDBOX" 2>/dev/null
    rm -f "$TRACKED" "$UNTRACKED" "$ALLF" "$HW" "$GEN" "$OTHER" "$DIRS" "$PATHS" "$IDENT" "$LIVE_MD" \
          "${SB_ALL:-}" "${SB_PATH:-}" "${SB_HW:-}" "${SB_MD:-}" 2>/dev/null
    return 0
}
trap cleanup EXIT

git ls-files > "$TRACKED" 2>/dev/null
git ls-files --others --exclude-standard > "$UNTRACKED" 2>/dev/null
cat "$TRACKED" "$UNTRACKED" | LC_ALL=C sort -u | LC_ALL=C grep -v '^$' > "$ALLF" || true

# 手写件 = 源码/文档/脚本扩展名 + 无扩展名惯例件；生成件 = 工具吐出来的报告与二进制；都不算的进"未分类"并报数
GEN_RE='(\.rpt|\.txt|\.raw|\.out|\.out\.gz|\.gz|\.log|\.jou|\.pb|\.str|\.wdb|\.hwdef|\.hwh|\.ltx|\.dcp|\.xpr|\.bit|\.xsa|\.elf|\.png|\.mem|\.md5|\.note|\.patch|\.json|\.tsv|\.o|\.pyc)$'
HW_RE='(\.md|\.v|\.sv|\.c|\.h|\.py|\.sh|\.tcl|\.mjs|\.xdc|\.ps1|\.bat|\.ld|\.csv)$'
HWN_RE='^(LICENSE|NOTICE|Makefile|\.gitignore|\.gitattributes)$'
while IFS= read -r f; do
    [ -f "$f" ] || continue
    if printf '%s' "$f" | LC_ALL=C grep -qE "$GEN_RE"; then printf '%s\n' "$f" >> "$GEN"
    elif printf '%s' "$f" | LC_ALL=C grep -qE "$HW_RE"; then printf '%s\n' "$f" >> "$HW"
    elif printf '%s' "$f" | LC_ALL=C grep -qE "$HWN_RE"; then printf '%s\n' "$f" >> "$HW"
    else printf '%s\n' "$f" >> "$OTHER"; fi
done < "$ALLF"
touch "$HW" "$GEN" "$OTHER"

n_of() { grep -c '' "$1" 2>/dev/null || echo 0; }
NALL=$(n_of "$ALLF"); NHW=$(n_of "$HW"); NGEN=$(n_of "$GEN"); NOTH=$(n_of "$OTHER")

# 本机身份串（用户名/机器名），从环境现取；取不到就在行里明写"这一类没扫"
for v in "${USERNAME:-}" "${USER:-}" "${COMPUTERNAME:-}" "${HOSTNAME:-}" "$(basename "${HOME:-none}" 2>/dev/null)"; do
    [ -z "$v" ] && continue
    [ ${#v} -lt 3 ] && continue
    l=$(printf '%s' "$v" | LC_ALL=C tr 'A-Z' 'a-z')
    case "$l" in root|admin|administrator|user|public|system|owner|default|jenkins|runner|docker|vagrant|none) continue ;; esac
    printf '%s\n%s\n%s\n' "$v" "$l" "$(printf '%s' "$v" | LC_ALL=C tr 'a-z' 'A-Z')" >> "$IDENT"
done
LC_ALL=C sort -u "$IDENT" -o "$IDENT" 2>/dev/null; NIDENT=$(n_of "$IDENT")

mask() { # 输出里只打码身份串，其余原样（扫描记录要留档，但不能把用户名再抄一遍）
    local s="$1" t esc
    [ "$NIDENT" -eq 0 ] && { printf '%s' "$s"; return 0; }
    while IFS= read -r t; do
        [ -z "$t" ] && continue
        esc=$(printf '%s' "$t" | sed 's/[][\.*^$/&]/\\&/g')
        s=$(printf '%s' "$s" | sed "s|$esc|<身份串>|g")
    done < "$IDENT"
    printf '%s' "$s"
}
clip() { printf '%s' "$1" | cut -c1-300; }
uniq_head() { printf '%s' "$1" | tr ' ' '\n' | LC_ALL=C grep -v '^$' | LC_ALL=C sort -u | head -3 | tr '\n' ' '; }

# ---------------------------------------------------------------- C1 命名
EXEMPT_NAMES=' README.md README_EN.md LICENSE NOTICE Makefile .gitignore .gitattributes '
c1() { # c1 <pathlist>
    # 原实现为每个"路径成分"派生 3 个 grep（3632 条路径 ≈ 3 万次进程），一台 Windows 上跑不完 ⇒ 曾让终审 C5 只能记 NOT_MEASURED。
    # 现在把同样的三段判断搬进一次 awk：判定顺序、豁免名单、计数口径逐字不变（`[^ -~]` 在 LC_ALL=C 下按字节算，与原来 grep 一致）。
    local list="$1"
    local RES NONASCII UPPER ILLEGAL EXEMPTN TOTAL BAD
    local USED EX
    RES=$(mktemp)
    LC_ALL=C awk -v exl="$EXEMPT_NAMES" '
        BEGIN{ FS="/"; total=0; nonascii=0; upper=0; illegal=0; exemptn=0; bad=0; used=""; ex="" }
        { last=NF; for (i=1;i<=NF;i++) { c=$i; if (c=="") continue; total++;
            if (i==last && index(exl, " " c " ")>0) { exemptn++; used=used" "c; continue }
            if (c ~ /[^ -~]/)                 { nonascii++; bad++; ex=ex" "$0; continue }
            if (c !~ /^[A-Za-z0-9._-]+$/)     { illegal++; bad++; ex=ex" "$0; continue }
            if (c ~ /[A-Z]/)                  { upper++; bad++; ex=ex" "$0 }
        } }
        END{ printf "%d %d %d %d %d %d\n", total, bad, nonascii, upper, illegal, exemptn;
             printf "%s\n", used; printf "%s\n", ex }
    ' "$list" > "$RES" 2>/dev/null
    read -r TOTAL BAD NONASCII UPPER ILLEGAL EXEMPTN <<< "$(sed -n '1p' "$RES")"
    USED=$(sed -n '2p' "$RES"); EX=$(sed -n '3p' "$RES")
    rm -f "$RES"
    TOTAL=${TOTAL:-0}; BAD=${BAD:-0}; NONASCII=${NONASCII:-0}; UPPER=${UPPER:-0}
    ILLEGAL=${ILLEGAL:-0}; EXEMPTN=${EXEMPTN:-0}
    C1N=$TOTAL
    if [ "$TOTAL" -eq 0 ]; then C1V="NOT_MEASURED"; C1D="路径清单为空，读不到输入"
    elif [ "$BAD" -eq 0 ]; then C1V="PASS"; C1D="违规 0；豁免点名$(uniq_head "$USED")共 $EXEMPTN 处"
    else C1V="FAIL"
         C1D="违规成分 $BAD（非 ASCII $NONASCII / 大写 $UPPER / 空格或其它非法字符 $ILLEGAL）；豁免点名：$(printf '%s' "$USED" | tr ' ' '\n' | LC_ALL=C sort -u | LC_ALL=C grep -v '^$' | tr '\n' ' ')共 $EXEMPTN 处——理由=§3.3.5.4 要求全小写，但 README/LICENSE/NOTICE/.gitignore 是评委与 Git 平台按**文件名**识别的惯例名，改名等于取消识别；批准人【队伍未确认】；样例：$(uniq_head "$EX")"
    fi
    return 0
}

# ---------------------------------------------------------------- C2 敏感信息
SENS_PATS='win绝对路径|[A-Za-z]:[\\/][A-Za-z0-9_ .-]{4,}
posix家目录|/(home|Users)/[A-Za-z0-9._-]{3,}
令牌ghp|ghp_[A-Za-z0-9]{16,}
令牌github_pat|github_pat_[A-Za-z0-9_]{16,}
令牌aws|AKIA[0-9A-Z]{12,}
键值型凭据|(api[_-]?key|secret|passwd|password)[ ]*[:=][ ]*[A-Za-z0-9_/+.-]{6,}
内网IPv4|(192\.168|10\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}
个人邮箱域|@[A-Za-z0-9.-]+\.(qq|163|126|outlook|gmail|foxmail|189|sina)\.com
机器名后缀laptop|[A-Za-z0-9_-]+-laptop'

c2() { # c2 <filelist>
    local list="$1" nf; nf=$(n_of "$list")
    C2N=0
    if [ "$nf" -eq 0 ]; then C2V="NOT_MEASURED"; C2D="作用域为空，读不到输入"; return 0; fi
    local scans=0 hits=0 det="" name pat cnt ex
    while IFS='|' read -r name pat; do
        [ -z "$name" ] && continue
        scans=$((scans+1))
        cnt=$(tr '\n' '\0' < "$list" | xargs -0 grep -lE "$pat" 2>/dev/null | wc -l); cnt=${cnt:-0}
        if [ "$cnt" -gt 0 ]; then
            hits=$((hits+cnt))
            ex=$(tr '\n' '\0' < "$list" | xargs -0 grep -nlE "$pat" 2>/dev/null | head -2 | cut -d: -f1,2 | tr '\n' ' ')
            det="$det ${name}=${cnt}件@$(mask "$ex")"
        fi
    done <<< "$SENS_PATS"
    if [ "$NIDENT" -gt 0 ]; then
        scans=$((scans+1))
        cnt=$(tr '\n' '\0' < "$list" | xargs -0 grep -lwFf "$IDENT" 2>/dev/null | wc -l); cnt=${cnt:-0}
        if [ "$cnt" -gt 0 ]; then
            hits=$((hits+cnt))
            ex=$(tr '\n' '\0' < "$list" | xargs -0 grep -nwFf "$IDENT" 2>/dev/null | head -2 | cut -d: -f1,2 | tr '\n' ' ')
            det="$det 本机身份串=${cnt}件@$ex"
        fi
    fi
    C2N=$nf
    C2D="扫 $scans 类 × $nf 文件，命中 $hits 个文件；身份串名单 $NIDENT 条（取不到就整类不判，见 --help）；串口名 COM\\d+ 按 P20 允许故不判；明细：$(clip "$det")"
    if [ "$hits" -gt 0 ]; then C2V="FAIL"; else C2V="PASS"; fi
    return 0
}

# ---------------------------------------------------------------- C3 声明一致性
PART_RE='[Xx][Cc]7[Zz][0-9]{2}[A-Za-z]{2,3}[0-9]{2,3}[A-Za-z]*-?[0-9][A-Za-z]?|[Xx][Cc][Kk][Uu]5[Pp]-[A-Za-z0-9]+-[0-9]-[A-Za-z]'
VER_RE='(Vivado|Vitis)[^0-9A-Za-z]{0,8}(v\.|版本)?[ ]?20[0-9]{2}\.[0-9]+(\.[0-9]+)?'
norm_part() { printf '%s' "$1" | LC_ALL=C tr 'a-z' 'A-Z' | LC_ALL=C tr -d '-_'; }
auth_of() { sed -n '/<!-- BEGIN-AUTHORITATIVE -->/,/<!-- END-AUTHORITATIVE -->/p' "$1" 2>/dev/null \
                | grep -m1 -E "^$2:" | sed "s/^$2:[[:space:]]*//" | tr -d '\r'; }

c3() { # c3 <hwlist> <declarations>
    local list="$1" decl="$2"
    C3N=0; C3DUP=0
    if [ ! -f "$decl" ]; then C3V="NOT_MEASURED"; C3D="权威声明文件 $decl 读不到"; return 0; fi
    local p v b o nd bd
    p=$(auth_of "$decl" part);  v=$(auth_of "$decl" vivado)
    b=$(auth_of "$decl" vivado_build); o=$(auth_of "$decl" os)
    nd=$(auth_of "$decl" node); bd=$(auth_of "$decl" board)
    if [ -z "$p" ] || [ -z "$v" ] || [ -z "$b" ] || [ -z "$o" ] || [ -z "$nd" ] || [ -z "$bd" ]; then
        C3V="NOT_MEASURED"; C3D="$decl 的 BEGIN-AUTHORITATIVE 块里 part/vivado/vivado_build/os/node/board 有取不到的字段"; return 0
    fi
    local want seen sites=0 conflict=0 form=0 vbad=0 dupf=0 ex="" vex="" f t num
    want=$(norm_part "$p")
    seen=$(mktemp)
    tr '\n' '\0' < "$list" | xargs -0 grep -HoE "$PART_RE" 2>/dev/null | LC_ALL=C sort -u | while IFS= read -r ln; do
        [ -z "$ln" ] && continue
        printf '%s\n' "$ln"
    done > "$seen"
    while IFS= read -r ln; do
        [ -z "$ln" ] && continue
        f="${ln%%:*}"; t="${ln#*:}"
        [ "$f" = "$decl" ] && continue
        sites=$((sites+1))
        if [ "$(norm_part "$t")" = "$want" ]; then
            dupf=$((dupf+1))
            [ "$t" != "$p" ] && { form=$((form+1)); ex="$ex $f::$t"; }
        else
            conflict=$((conflict+1)); ex="$ex $f::$t"
        fi
    done < "$seen"
    rm -f "$seen"
    while IFS= read -r ln; do
        [ -z "$ln" ] && continue
        f="${ln%%:*}"; t="${ln#*:}"
        [ "$f" = "$decl" ] && continue
        num=$(printf '%s' "$t" | grep -oE '20[0-9]{2}\.[0-9]+(\.[0-9]+)?' | head -1)
        [ -z "$num" ] && continue
        sites=$((sites+1))
        if [ "$num" != "$v" ]; then vbad=$((vbad+1)); vex="$vex $f::$t"; fi
    done < <(tr '\n' '\0' < "$list" | xargs -0 grep -HoE "$VER_RE" 2>/dev/null | LC_ALL=C sort -u)
    C3N=$sites; C3DUP=$dupf
    C3D="声明点 $sites 处（器件串+工具版本串，$decl 自身除外）；真值冲突 $conflict；写法不统一 $form；版本冲突 $vbad；把权威值抄下来而不是引用它的文件 $dupf 处；样例：$(uniq_head "$ex$vex")"
    if [ "$sites" -eq 0 ]; then C3V="NOT_MEASURED"; C3D="$C3D；一个声明点都没读到，判不了"
    elif [ $((conflict+form+vbad)) -gt 0 ]; then C3V="FAIL"
    else C3V="PASS"; fi
    return 0
}

# ---------------------------------------------------------------- C4 许可黑名单
BLACK='仅供评估|评估用|仅限评估|禁止再分发|不得再分发|不许再分发|not for redistribution|not for further distribution|evaluation only|for evaluation only|non-commercial|noncommercial|AGPL|LGPL|GPL|Creative Commons|CC BY|CC-BY|confidential|保密|proprietary|NDA|all rights reserved'
c4() { # c4 <list>
    local list="$1" nf; nf=$(n_of "$list")
    if [ "$nf" -eq 0 ]; then C4N=0; C4V="NOT_MEASURED"; C4D="作用域为空，读不到输入"; return 0; fi
    local files hits ex
    files=$(tr '\n' '\0' < "$list" | xargs -0 grep -ilE "$BLACK" 2>/dev/null | wc -l)
    hits=$(tr '\n' '\0' < "$list" | xargs -0 grep -inE "$BLACK" 2>/dev/null | wc -l)
    ex=$(tr '\n' '\0' < "$list" | xargs -0 grep -inE "$BLACK" 2>/dev/null | head -2 | cut -c1-90 | tr '\n' ' ')
    C4N=$nf
    C4D="命中行 $hits（$files 个文件）；P20 铁律 2 要求每条命中都在 docs/provenance-and-licenses.md 有处置行；样例：$ex"
    if [ "$hits" -gt 0 ]; then C4V="FAIL"; else C4V="PASS"; fi
    return 0
}

# ---------------------------------------------------------------- C5 断链
TRANS='(impl_1|[^/]*\.runs|runme\.log|[^/]*\.dcp|xsim\.dir|sim_work|\.Xil|vivado_system|ps_obj)'
c5() { # c5 <mdlist> <root>
    local list="$1" root="$2" nf; nf=$(n_of "$list")
    if [ "$nf" -eq 0 ]; then C5N=0; C5V="NOT_MEASURED"; C5D="没有可判的活跃文档（*.md 清单为空）"; return 0; fi
    local sites=0 hard=0 trans=0 ex="" prev="" dir="" tok
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        if [ "$f" != "$prev" ]; then dir=$(dirname "$f"); prev="$f"; fi
        while IFS= read -r tok; do
            tok=$(printf '%s' "$tok" | sed -E 's/[.,;:]+$//')
            [ -z "$tok" ] && continue
            case "$tok" in
                http*|*\[*|*\]*|*'<'*|*'>'*|*'*'*|*'?'*|*'$'*|*' '*|*'|'*|*':'*|*'('*|')'*|*'#'*|*'{'*|'}'*|*'='*|'/'*|*'!'*|*'"'*|*"'"*) continue ;;
            esac
            printf '%s' "$tok" | LC_ALL=C grep -q '[^ -~]' && continue
            printf '%s' "$tok" | LC_ALL=C grep -qE '^[A-Za-z0-9_.@+-][A-Za-z0-9_./@+-]*$' || continue
            tok=${tok%/}
            case "$tok" in */*) : ;; *) continue ;; esac      # 只判带目录的路径式引用；裸文件名不是断链
            sites=$((sites+1))
            if [ -e "$root/$tok" ] || [ -e "$root/$dir/$tok" ]; then continue; fi
            if printf '%s' "$tok" | LC_ALL=C grep -qE "$TRANS"; then trans=$((trans+1)); continue; fi
            hard=$((hard+1)); ex="$ex $f::$tok"
        done < <(grep -oE '`[^`]{4,140}`' "$root/$f" 2>/dev/null | tr -d '`')
    done < "$list"
    C5N=$sites
    C5D="引用 $sites 处；断链 $hard；运行期产物路径（impl_1/ *.runs/ *.dcp runme.log 等）豁免 $trans 处——理由：这类文件按 .gitignore 就不该在盘上，判它们存在等于判工具没跑；样例：$(uniq_head "$ex")"
    if [ "$sites" -eq 0 ]; then C5V="NOT_MEASURED"; C5D="$C5D；解析不到 path 形态的引用，判不了"
    elif [ "$hard" -gt 0 ]; then C5V="FAIL"
    else C5V="PASS"; fi
    return 0
}

# ---------------------------------------------------------------- 报告器
NT=0; NPASS=0; NFAIL=0; NNM=0
line() { # line <编号> <名称> <分母N> <详情> <判定>
    NT=$((NT+1))
    printf '%s | %s | 判 %s 项 | %s | %s\n' "$1" "$2" "$3" "$(clip "$4")" "$5"
    case "$5" in PASS) NPASS=$((NPASS+1)) ;; FAIL) NFAIL=$((NFAIL+1)) ;; *) NNM=$((NNM+1)) ;; esac
}

run_all() { # run_all <paths> <hw> <md> <root> <declarations>
    local paths="$1" hw="$2" md="$3" root="$4" decl="$5" gencopy
    c1 "$paths";        line C1  "目录与文件名纯 ASCII 小写（字母/数字/-/_/.；大写与非 ASCII 都算违规）" "$C1N" "$C1D" "$C1V"
    c2 "$hw";           line C2a "敏感信息——手写件（绝对路径/用户名/令牌/内网地址/机器名；串口名允许）" "$C2N" "$C2D" "$C2V"
    c2 "$GEN";          line C2b "敏感信息——工具生成件（处置口径不同：由导出器成包时剔除）" "$C2N" "生成件在仓库里留档不脱敏，交付包内由 build/make_submission.sh 判据 4 要求本机绝对路径=0；批准人【队伍未确认】；$C2D" "$C2V"
    c3 "$hw" "$decl";   line C3  "器件与版本声明一致性（权威值只允许 $decl 一处，其余是引用）" "$C3N" "$C3D" "$C3V"
    line C3d "重复抄写权威值的文件数（抄写 vs 引用）" "$C3DUP" "只报数：P20 铁律 4 的红条件是「两处不一致」而不是「有两处」；把抄写改成引用要动 report/ 与 skills/，本轮是禁区 ⇒ 这条判据没有牙" "NOT_MEASURED"
    c4 "$hw";           line C4  "许可黑名单标记（仅供评估/禁止再分发/non-commercial/GPL/LGPL/AGPL/CC/confidential/保密/NDA/all rights reserved）" "$C4N" "$C4D" "$C4V"
    gencopy=$(tr '\n' '\0' < "$GEN" | xargs -0 grep -lE "Copyright 1986-2022 Xilinx|2022-2026 Advanced Micro Devices" 2>/dev/null | wc -l)
    line C4b "生成件里带 Xilinx/AMD 版权行的文件数（要求保留声明 ⇒ 不是违规，但要逐类登记）" "$NGEN" "带行文件 $gencopy；本行只报数：「是否每一类都在登记表里有行」要人读 docs/provenance-and-licenses.md，脚本动不了它 ⇒ 这条判据没有牙" "NOT_MEASURED"
    c5 "$md" "$root";   line C5  "断链——活跃文档里反引号相对路径在盘上是否存在（report/ 与 build/ 的历史档案除外）" "$C5N" "$C5D" "$C5V"
    return 0
}

# ---------------------------------------------------------------- --self 反例
if [ "$SELF" = 1 ]; then
    echo "SELF | 自带反例模式（只写临时目录，不动仓库任何文件）"
    SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/hyg-self.XXXXXX") || { echo "SELF PREQ | 建不出临时目录 | 判 1 项 | NOT_MEASURED"; exit 3; }
    SBABS=$(cd "$SANDBOX" && pwd -P)
    case "$SBABS" in
        "$ROOT"/*) echo "SELF PREQ | 临时目录落在仓库内（$SBABS），拒绝运行 | 判 1 项 | NOT_MEASURED"; exit 3 ;;
    esac
    SB_ALL=$(mktemp); SB_PATH=$(mktemp); SB_HW=$(mktemp); SB_MD=$(mktemp)

    # C1 反例：大写 + 空格；另尽力造一个非 ASCII 名（造不出来就明写这一子类没被覆盖）
    printf 'x\n' > "$SBABS/Bad Name.txt"
    mkdir -p "$SBABS/Sub Dir" && printf 'x\n' > "$SBABS/Sub Dir/keep.md"
    NONASCII_MADE=0
    if printf 'x\n' > "$SBABS/非法文件.md" 2>/dev/null && [ -e "$SBABS/非法文件.md" ]; then NONASCII_MADE=1; fi

    # C2 / C4 反例内容（都是与本机无关的通用形态，换一台机器照样命中）
    mkdir -p "$SBABS/in"
    {
        echo 'build path D:\\Somewhere\\project and /home/example/proj'   # abs-fixture：这是反例内容，不是本机路径
        echo 'token ghp_AAAAAAAAAAAAAAAA1234567890 plus secret = Abc12345678'
        echo 'board ip 192.168.9.9 mail someone@qq.com host any-laptop'
        echo '本例程仅供评估，禁止再分发；参考实现是 GPL 的。'
    } > "$SBABS/in/leak.md"

    # C3 反例：权威块 + 真值冲突 + 写法不统一 + 版本冲突
    {
        echo '<!-- BEGIN-AUTHORITATIVE -->'
        echo 'part: xc7z020clg484-2'
        echo 'board: SB-BOARD-1'
        echo 'vivado: 2025.2.1'
        echo 'vivado_build: 6403652'
        echo 'os: Windows 11 (10.0.26300) win64'
        echo 'node: v24.21.0'
        echo '<!-- END-AUTHORITATIVE -->'
    } > "$SBABS/declarations.md"
    {
        echo '器件 xc7z010clg400-1 上跑过（真值冲突）'
        echo '另有 XC7Z020-CLG484-2 这种写法（写法不统一）'
        echo '工具 Vivado 2020.1（版本冲突）'
        echo '断链示例：`in/no_such_file.txt`'
        echo '运行期豁免：`impl_1/runme.log`'
        echo '好引用（不该算断链）：`in/leak.md`'
    } > "$SBABS/in/claims.md"

    ( cd "$SBABS" && find . -mindepth 1 \( -type f -o -type d \) | sed 's|^\./||' | LC_ALL=C sort ) > "$SB_ALL"
    ( cd "$SBABS" && find . -mindepth 1 -type f | sed 's|^\./||' | LC_ALL=C sort ) > "$SB_PATH"
    grep -E '(\.md|\.txt)$' "$SB_PATH" > "$SB_HW" || true
    grep -E '\.md$' "$SB_PATH" | LC_ALL=C grep -v '^declarations\.md$' > "$SB_MD" || true

    SB_NT=0; SB_OK=0; SB_DRY=()
    sb_check() { # sb_check <编号> <期望判定> <实得>
        SB_NT=$((SB_NT+1))
        if [ "$2" = "$3" ]; then SB_OK=$((SB_OK+1)); printf 'SELF %s | 反例把判据变红了 | 判 1 项 | 期望 %s 实得 %s | PASS\n' "$1" "$2" "$3";
        else SB_DRY+=("$1 期望=$2 实得=$3"); printf 'SELF %s | 反例没能改动这条判据 | 判 1 项 | 期望 %s 实得 %s | FAIL\n' "$1" "$2" "$3"; fi
    }

    pushd "$SBABS" >/dev/null || { echo "SELF PREQ | 进不去沙箱 | 判 1 项 | NOT_MEASURED"; exit 3; }
    c1 "$SB_ALL"; sb_check C1 FAIL "$C1V";       printf 'SELF C1 明细 | - | 判 %s 项 | %s | PASS\n' "$C1N" "$C1D"
    c2 "$SB_HW";  sb_check C2a FAIL "$C2V";      printf 'SELF C2a 明细 | - | 判 %s 项 | %s | PASS\n' "$C2N" "$C2D"
    c2 "$SB_HW";  sb_check C2b FAIL "$C2V";      printf 'SELF C2b 明细 | - | 判 %s 项 | （与 C2a 同一份沙箱输入，生成件作用域另由 --self 的 leak.md 覆盖）%s | PASS\n' "$C2N" "$C2D"
    c3 "$SB_HW" "declarations.md"; sb_check C3 FAIL "$C3V";  printf 'SELF C3 明细 | - | 判 %s 项 | %s | PASS\n' "$C3N" "$C3D"
    c3 "$SB_HW" "no_such_declarations.md"; sb_check C3-缺输入 NOT_MEASURED "$C3V"
    c4 "$SB_HW"; sb_check C4 FAIL "$C4V";        printf 'SELF C4 明细 | - | 判 %s 项 | %s | PASS\n' "$C4N" "$C4D"
    c5 "$SB_MD" "$SBABS"; sb_check C5 FAIL "$C5V"; printf 'SELF C5 明细 | - | 判 %s 项 | %s | PASS\n' "$C5N" "$C5D"
    c5 /dev/null "$SBABS"; sb_check C5-缺输入 NOT_MEASURED "$C5V"
    popd >/dev/null

    if [ "$NONASCII_MADE" = 1 ]; then
        printf 'SELF C1-非ASCII | 沙箱里造出了中文文件名，这一子类被反例覆盖 | 判 1 项 | 见上面 C1 明细的非 ASCII 计数 | PASS\n'
    else
        printf 'SELF C1-非ASCII | 这台机器造不出中文文件名，非 ASCII 这一子类没被反例覆盖 ⇒ 这条子类没有牙 | 判 1 项 | 未覆盖 | NOT_MEASURED\n'
    fi
    printf 'SELF C3d/C4b | 这两行是"只报数"的信息行，设计上就不参与红绿（正式输出里已明写没有牙） | 判 2 项 | 不造反例 | NOT_MEASURED\n'

    echo "SELF SUMMARY: 反例 $SB_NT 项，生效 $SB_OK 项，未生效 ${#SB_DRY[@]} 项"
    if [ "${#SB_DRY[@]}" -gt 0 ]; then
        for d in "${SB_DRY[@]}"; do echo "SELF 未生效明细：$d"; done
        echo "SELF_VERDICT: FAIL"; exit 1
    fi
    echo "SELF_VERDICT: PASS"; exit 0
fi

# ---------------------------------------------------------------- 正式运行
awk -F/ '{ out=""; for(i=1;i<NF;i++){ out=(out==""?$i:out"/"$i); print out } }' "$ALLF" | LC_ALL=C sort -u > "$DIRS"
cat "$ALLF" "$DIRS" | LC_ALL=C grep -v '^$' > "$PATHS"
grep -E '\.md$' "$ALLF" | LC_ALL=C grep -vE '^(report|build)/' > "$LIVE_MD" || true

printf 'SCOPE | 分发集 = git 跟踪 ∪ 未跟踪未忽略 | 判 %s 项 | 手写 %s / 生成 %s / 未分类 %s（未分类不参与 C2/C3/C4 判定，只在这里点名） | PASS\n' "$NALL" "$NHW" "$NGEN" "$NOTH"
run_all "$PATHS" "$HW" "$LIVE_MD" "$ROOT" "$ROOT/report/declarations.md"
printf 'SUMMARY: 判 %s 项 PASS=%s FAIL=%s NOT_MEASURED=%s\n' "$NT" "$NPASS" "$NFAIL" "$NNM"
if [ "$NFAIL" -gt 0 ]; then echo "REPO_HYGIENE: FAIL"; exit 1; fi
if [ "$NNM" -gt 0 ]; then echo "REPO_HYGIENE: NOT_MEASURED"; exit 2; fi
echo "REPO_HYGIENE: PASS"; exit 0
