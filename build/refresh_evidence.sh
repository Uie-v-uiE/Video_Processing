#!/bin/bash
# build/refresh_evidence.sh <NN> —— **只改了台架/文档/脚本**（RTL 与固件一字未动）时，
# 把 rNN 那套冻结件里的"台架报告 + 门禁 + MANIFEST"刷新，而**不**新建一个构建号。
#
# 这三条都是本仓库真踩过的坑，所以写进脚本而不是写进记忆：
#   ① 门禁输出**不能**直接重定向进 `build/rNN_gates.txt` —— 那是第 18 项要读的文件本身，
#      重定向会先把基线截空，于是"自己把自己判红"，`freeze_evidence.sh` 接着拒绝冻结（r74 那次）。
#      ⇒ 这里先写 /tmp，看到 `GATES: ALL PASS` 才 `cp`。
#   ② "刷新同号"只在**三件成品没变**时成立：bit/xsa/elf 的 md5 必须还等于冻结件 `MANIFEST.md5`
#      里记的那三个。变了就说明这是一次新构建，必须换新号 —— 把新 RTL 挂旧 rNN 的名字
#      是 #88 那一族最坏的一张脸。⇒ 这里 REFUSE。
#   ③ 冻结件里的 L1 记录是上一次全量回归抄来的，只改台架时它不会自己更新。
#      ⇒ 收尾打印它的实际时间，不假装它验过新台架。
#
# 用法：
#   bash build/refresh_evidence.sh 75                # 跑台架 → 出报告 → 门禁 → 冻结 → 对账
#   bash build/refresh_evidence.sh 75 --skip-bench   # 台架已经跑过，只做后面三步
#   bash build/refresh_evidence.sh --check 75        # 只对账，不做任何事
#   bash build/refresh_evidence.sh --selftest        # 反例测试（能红也能绿）
set -u
ROOT=${REFRESH_ROOT:-/d/Xilinx/Prj/pro/Video_Processing}
cd "$ROOT" || exit 1
ARTS="system.bit system.xsa ps_app.elf"

want_of() { sed -n "s|^\([0-9a-f]\{32\}\) \*$1\$|\1|p" "$2"; }      # 从 MANIFEST 里取那一条的 md5
got_of()  { md5sum "build/$1" 2>/dev/null | cut -d' ' -f1; }

# 三件成品与冻结清单是否还互相对得上（对不上 = 这是一次新构建，不该刷旧号）
artifacts_match() {                 # $1 = evidence 目录；返回 0 = 对得上
    local d=$1 f w g bad=0
    [ -f "$d/MANIFEST.md5" ] || { echo "没有 $d/MANIFEST.md5"; return 1; }
    for f in $ARTS; do
        w=$(want_of "$f" "$d/MANIFEST.md5"); g=$(got_of "$f")
        if [ -z "$w" ] || [ -z "$g" ] || [ "$w" != "$g" ]; then
            echo "$f：build/ 是 ${g:-读不到}，$d 记的是 ${w:-清单里没这一条}"; bad=1
        fi
    done
    return $bad
}

selftest() {
    local T=${TMPDIR:-/tmp}/refresh_self.$$ nbad=0 out
    mkdir -p "$T/build/evidence_r99"
    printf 'AAAA\n' > "$T/build/system.bit"; printf 'BBBB\n' > "$T/build/system.xsa"
    printf 'CCCC\n' > "$T/build/ps_app.elf"
    local h1 h2 h3
    h1=$(md5sum "$T/build/system.bit" | cut -d' ' -f1)
    h2=$(md5sum "$T/build/system.xsa" | cut -d' ' -f1)
    h3=$(md5sum "$T/build/ps_app.elf" | cut -d' ' -f1)
    printf '%s *system.bit\n%s *system.xsa\n%s *ps_app.elf\n' "$h1" "$h2" "$h3" \
        > "$T/build/evidence_r99/MANIFEST.md5"
    # 绿路：三件都对得上 ⇒ 不许 REFUSE
    out=$(REFRESH_ROOT="$T" bash "$0" --check 99 2>&1)
    echo "$out" | grep -q "允许刷同号" || { echo "SELFTEST FAIL 1：三件一致却没放行（判据恒红）"; nbad=1; }
    echo "$out" | grep -q "REFUSE" && { echo "SELFTEST FAIL 2：一致的情况下报了 REFUSE"; nbad=1; }
    # 红路：换掉 bit（模拟"其实这是一次新构建"）⇒ 必须 REFUSE 并且点名是哪一件
    printf 'DIFFERENT\n' > "$T/build/system.bit"
    out=$(REFRESH_ROOT="$T" bash "$0" --check 99 2>&1)
    echo "$out" | grep -q "REFUSE" || { echo "SELFTEST FAIL 3：成品变了却没拦住（会把新 RTL 挂旧号）"; nbad=1; }
    echo "$out" | grep -q "system.bit" || { echo "SELFTEST FAIL 4：拦下了但没说是哪一件"; nbad=1; }
    # 反例的反例：MANIFEST 缺文件 ⇒ 也不能放行
    rm -f "$T/build/evidence_r99/MANIFEST.md5"
    out=$(REFRESH_ROOT="$T" bash "$0" --check 99 2>&1)
    echo "$out" | grep -q "REFUSE\|MANIFEST" || { echo "SELFTEST FAIL 5：没有 MANIFEST 却往下走"; nbad=1; }
    rm -rf "$T"
    [ "$nbad" = 0 ] && echo "SELFTEST PASS 5/5：一致放行、变了拒绝并点名、缺清单不放行"
    exit $nbad
}

NN=${1:-}; shift || true
SKIPB=0; CHECK=0
case "$NN" in --selftest) selftest;; --check) CHECK=1; NN=${1:-}; shift || true;; esac
for a in "$@"; do case "$a" in --selftest) selftest;; --skip-bench) SKIPB=1;; --check) CHECK=1;; esac; done
case "$NN" in (''|*[!0-9]*) echo "用法: bash build/refresh_evidence.sh <构建号，如 75> [--skip-bench|--check]"; exit 2;; esac
D=build/evidence_r$NN
[ -d "$D" ] || { echo "REFUSE：$D 不存在 ⇒ 这不是刷新，是首次冻结：bash build/freeze_evidence.sh $NN"; exit 1; }

if ! artifacts_match "$D" >/tmp/art.$$.txt 2>&1; then
    echo "REFUSE：build/ 下的三件成品与 $D 所记不一致 ⇒ 这是一次**新构建**，请走完整构建 + 新号。"
    sed 's/^/        /' /tmp/art.$$.txt
    rm -f /tmp/art.$$.txt; exit 1
fi
echo "对账：三件成品仍等于 $D 所记（$(md5sum build/system.bit | cut -c1-12)/$(md5sum build/ps_app.elf | cut -c1-12)）⇒ 允许刷同号"
if [ "$CHECK" = 1 ]; then rm -f /tmp/art.$$.txt; exit 0; fi

if [ "$SKIPB" = 0 ]; then
    echo "  → bash sim/run_one.sh tb_v98_top_seam（顶层台架一轮约 80 分钟，console 在 /tmp/kx/refresh_tb98_console.txt）"
    bash sim/run_one.sh tb_v98_top_seam > /tmp/kx/refresh_tb98_console.txt 2>&1 || {
        echo "台架跑挂了：看 /tmp/kx/refresh_tb98_console.txt"; rm -f /tmp/art.$$.txt; exit 1; }
fi
echo "  → bash build/tb98_report.sh"
bash build/tb98_report.sh || { echo "出报告失败（多半是 run.log 与当前树不是同一次跑）"; rm -f /tmp/art.$$.txt; exit 1; }

GT=/tmp/refresh_gates_$NN.txt
echo "  → bash build/gates.sh（先写 $GT，只有 ALL PASS 才 cp 进 build/r${NN}_gates.txt）"
bash build/gates.sh > "$GT" 2>&1; RC=$?
if [ "$RC" != 0 ] || ! grep -q "^GATES: ALL PASS" "$GT"; then
    echo "GATES 有红项 ⇒ 不覆盖 build/r${NN}_gates.txt、也不重冻。红的是："
    grep -a "FAIL\|——" "$GT" | head -10; rm -f /tmp/art.$$.txt; exit 1
fi
cp -f "$GT" "build/r${NN}_gates.txt"
echo "  → bash build/freeze_evidence.sh $NN"
bash build/freeze_evidence.sh "$NN" || { echo "冻结失败（原因在它自己那几行）"; rm -f /tmp/art.$$.txt; exit 1; }
echo "完成。口径 ③：$D/r${NN}_l1_regress.txt 是**上一次 L1 全量**抄来的（本轮只改台架/文档，没重跑那 67 个）。"
echo "      ⚠ 不要用 `stat` 的 mtime 去说它是几点跑的：`freeze_evidence.sh` 每刷一次就 `cp -f` 一次，"
echo "        mtime 会被刷成拷贝时间（今晚打印出 05:41 而内容是 03:49，就是这么来的）。"
echo "      要看它含了什么，念这两条：`grep -c '^RESULT .* PASS' $D/r${NN}_l1_regress.txt` 与它自己头部的 Vivado banner。"
echo "      下一次真实 RTL 改动之前，仍要先重跑 L1 再冻结。"
rm -f /tmp/art.$$.txt
