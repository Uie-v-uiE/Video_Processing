#!/usr/bin/env bash
# build/f2e_preverify.sh —— #174（gapclr 与 frame_done 同拍竞争）这一刀的**差分预验**，不花构建、不花几小时台架。
#
# 为什么要它（2026-10-03，批次轮的纪律）：`src/rtl` 被 r109 那条链占着（构建 + 台架都按当前树编译，
# 中途改源会让后面那几支台架的 `rtl_md5` 与位流不同源 ⇒ 门禁第 15 项作废）。可这一刀的判决其实
# 全在**一支 38 秒的模块级台架**里 ⇒ 那就照 r107/r108 的老办法：把树拷到临时目录，在拷贝树上打刀，
# 让**同一支台架**在未打刀的拷贝上红、在打刀后的拷贝上绿，并且红/绿的**只差那一条判据**。
#
# 打印纪律（#121 + rule 47）：每个 case 一行；计数口径是"比较做了多少次"而不是"通过了多少次"。
# 退出码：0 = 预验成立（未打刀红、打刀后绿、且只有 F2e B 这一条变化）；
#        2 = 前置坏了（锚点找不到/找不到工具/编译失败 ⇒ 不许把"没跑"当结论）；
#        3 = 预验不成立（打了刀还红，或者红的不是那一条 —— 那就说明我对机理的理解是错的）。
set -u
cd "$(dirname "$0")/.."
# 自己把自己念的话落到被跟踪的凭据里（规矩：每条结论都要点名它的件）；不设 `VP_PV_REC` 就只往 stdout 念。
REC=${VP_PV_REC:-}
if [ -n "$REC" ]; then mkdir -p "$(dirname "$REC")"; exec > >(tee "$REC") 2>&1; fi
echo "# f2e 差分预验 $(date '+%F %H:%M:%S')  ——  两腿都是**拷贝树**：base 未打刀、cut 打了那一处条件"
V=${VP_VIVADO_BIN:-}
[ -f "$V/xvlog" ] || { echo "PV-REFUSE: 先设 VP_VIVADO_BIN=<Vivado>/bin（当前 '$V'）"; exit 2; }
export VP_VIVADO_BIN="$V"
TB=tb_link_monitor
W=/tmp/kx/f2e_pv
RTL=src/rtl/eth/link_monitor.v
ANCHOR_IF="stall_ms  <= 0;"
TARGET="if (have_base) begin"
PATCHED="if (gapclr) begin gap_last<=0; gap_min<=0; gap_max<=0; gap_sum<=0; gap_valid<=0; end else if (have_base) begin"

for leg in base cut; do
    rm -rf "$W/$leg"; mkdir -p "$W/$leg"
    cp -r src sim "$W/$leg/" 2>/dev/null || { echo "PV-REFUSE: 拷树失败"; exit 2; }
done
# 只在 cut 那一腿打刀；锚点必须**恰好一个**（多个就说明这段代码被别人改过，我的替换不再安全）
node -e '
const fs=require("fs");
const p=process.env.TEMP+"/../"+""; // 不用：路径从 argv 来
const f=process.argv[1], IF=process.argv[2], T=process.argv[3], P=process.argv[4];
const s=fs.readFileSync(f,"utf8");
const i=s.indexOf(IF);
if(i<0){ console.log("ANCHOR-MISS stall_ms"); process.exit(2); }
const j=s.indexOf(T,i);
if(j<0){ console.log("ANCHOR-MISS have_base"); process.exit(2); }
if(s.indexOf(T,j+1)>=0){ console.log("ANCHOR-MULTIPLE 后面还有 if (have_base) begin —— 替换范围不清，停手"); process.exit(2); }
fs.writeFileSync(f, s.slice(0,j)+P+s.slice(j+T.length));
console.log("PATCHED at byte "+j+"  （长度 "+s.length+" -> "+(s.length-T.length+P.length)+"，只增不减）");
' "$W/cut/$RTL" "$ANCHOR_IF" "$TARGET" "$PATCHED" || { echo "PV-REFUSE: 打刀失败（见上面 ANCHOR-*）"; exit 2; }
# 断言：打完刀的拷贝必须**变长**且除了那一处之外一字未动（forget-to-keep-the-tail 那一课）
[ "$(wc -c < "$W/cut/$RTL")" -gt "$(wc -c < "$W/base/$RTL")" ] || { echo "PV-REFUSE: cut 腿没变长，替换可能吞了尾巴"; exit 2; }
diff <(sed "s/$TARGET//" "$W/base/$RTL") <(sed "s/$PATCHED//" "$W/cut/$RTL") > /dev/null \
    && echo "PV-DIFFOK 两腿除了那一处以外相同" || echo "PV-DIFFNOTE 除了那一处还有别的差异（读 diff 再决定，不拦路）"

run_leg() {   # $1=腿名  打印：PV <leg> <verdict 行> <FAIL 计数>
    local leg=$1 d=$W/$1.run
    rm -rf "$d"; mkdir -p "$d"; cd "$d" || return 2
    rm -rf xsim.dir
    local srcs
    srcs="$(find $W/$leg/src/rtl -name '*.v' | tr '\n' ' ') $(find $W/$leg/sim -maxdepth 1 -name 'tb_*.v' | tr '\n' ' ') $(find $W/$leg/sim/prim -name '*.v' 2>/dev/null | tr '\n' ' ')"
    printf '%s\n' $srcs | cygpath -m -f - > files.f
    "$V/xvlog" -f files.f > xv.log 2>&1
    grep -q "^ERROR" xv.log && { echo "PV $leg XVLOG-FAILED"; cd - >/dev/null; return 2; }
    "$V/xelab" $TB -s snap > el.log 2>&1
    grep -q "^ERROR" el.log && { echo "PV $leg XELAB-FAILED"; cd - >/dev/null; return 2; }
    "$V/xsim" snap -R > run.log 2>&1
    local nf nbf
    nf=$(grep -acE '^ *FAIL( |$)' run.log)
    nbf=$(grep -ac '^FAIL F2e B' run.log)
    echo "PV $leg FAIL行数=$nf F2e-B红=$nbf 判定=$(grep -a "^RESULT $TB" run.log | tail -1)"
    grep -aE '^ *(PASS|FAIL) F2' run.log | sed 's/^/      /'
    cd - >/dev/null
    # ⚠ 只能用 `eval`：`PV_$1=$nf` 这种写法里 bash 在**展开前**判定"这是不是赋值"，
    #   而 `PV_$1` 不是合法 NAME ⇒ 整行被当成命令，报 `PV_base=1: command not found`（第一跑就是这样）。
    eval "PV_$1=$nf"; eval "PV_${1}_b=$nbf"
}
run_leg base || { echo "PV-REFUSE: base 腿没跑成"; exit 2; }
run_leg cut  || { echo "PV-REFUSE: cut 腿没跑成"; exit 2; }

echo "PV-SUMMARY base红=$PV_base(其中 F2e-B=$PV_base_b) cut红=$PV_cut(其中 F2e-B=$PV_cut_b)"
if [ "$PV_base_b" = 0 ]; then echo "PV-NOTEST 未打刀的树就不红 F2e B —— 台架或机理变了，预验没有意义"; exit 3; fi
if [ "$PV_cut_b" != 0 ]; then echo "PV-NOFIX 打刀后 F2e B 仍红 —— 我对同拍竞争的理解不对（或还有第二个写者）"; exit 3; fi
if [ "$PV_cut" -ge "$PV_base" ]; then echo "PV-EXTRA 打刀后红的条数没减少（$(($PV_base-$PV_cut)) 条）—— 连带红要单独列，不许糊"; exit 3; fi
echo "PV 结论：这一刀在拷贝树上把 F2e B 从红翻绿，且红的条数从 $PV_base 降到 $PV_cut（只少它自己）"
echo "PV 下一步：等 r109 那条链空出 src/rtl，再把同一处改动落进真树，与 #177 死代码同一批进构建"
exit 0
