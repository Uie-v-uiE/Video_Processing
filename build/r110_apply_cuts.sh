#!/bin/bash
# 用途：把 r110 第二捆里"已预备完"的两刀一次落下（刀 1 #174、刀 4① new_row 独热）
# 输入：命令行参数
# 输出：stdout
# 退出码：0=跑完 1=非 0 分支（该文件 exit 1 那一行） 2=非 0 分支（该文件 exit 2 那一行）
# build/r110_apply_cuts.sh —— 把 r110 第二捆里"已预备完"的两刀一次落下（刀 1 #174、刀 4① new_row 独热）
#
# 为什么要有这个脚本：用户要求"所有任务一起开、别一个一个搞几小时仿真"。第二捆每一刀先在不花构建的前提下验过：
#   刀 1 = 差分预验（`build/evidence/r174_f2e_preverify.txt`：base 只红 F2e B；打刀后 F2e A/B 与 F2a–F2d 全绿），
#   刀 4① = **按构造等价**的改写（布尔函数与今天逐字相同，见下面注释），只换使能网的形状。
#
# 当场就判的规矩：
#   1) 链子在飞不许落刀（构建会静默重吃 src/rtl）；
#   2) 落刀前两份 RTL 必须在 git 里干净 —— 先只读证实"能退回"，再动手写；
#   3) 锚点必须**恰好命中一次**、打完必须变长、文件末尾字符不许变；
#   4) `--check` 只读不写（链子在飞时也能跑）；真落刀要 `--apply` + `VP_I_KNOW=1`。
#   5) 行尾自适应：`frame_reasm.v` 被 node 逐字符读出是 **LF/CRLF 混排**（同一语句前后两行 terminator 不同），
#      所以匹配按"整行去 terminator 比内容"，写回沿用**命中那一行自己的** terminator（file(1) 报的
#      "with CRLF, LF line terminators" 就是这个坑，第一次尝试按字面 \n 匹配直接 ANCHOR-MISS）。
#
# 用法：
#   bash build/r110_apply_cuts.sh --check          [1|4]
#   VP_I_KNOW=1 bash build/r110_apply_cuts.sh --apply [1|4]
cd "$(dirname "$0")/.." || exit 2

MODE=${1:---check}
WHICH=${2:-all}
case "$MODE" in --check|--apply) : ;; *) echo "用法: $0 --check|--apply [1|4]"; exit 2 ;; esac
case "$WHICH" in all|1|4) : ;; *) echo "WHICH 只许 all/1/4（给的是 $WHICH）"; exit 2 ;; esac
RTL_LM=src/rtl/eth/link_monitor.v
RTL_RS=src/rtl/eth/frame_reasm.v
APPLY=
if [ "$MODE" = "--apply" ]; then
    APPLY=1
    [ "${VP_I_KNOW:-}" = 1 ] || { echo "APPLY-REFUSE: 要落刀请显式 VP_I_KNOW=1（本脚本会改 src/rtl）"; exit 2; }
    if [ "${VP_ALLOW_BUSY:-}" = 1 ]; then
        echo "WARN SANDBOX-override 生效：跳过 xsim/vivado 活性检查 —— **这只给拷贝树的自测用，真树落刀时不要设它**"
    else
        tasklist 2>/dev/null | grep -qi "vivado\.exe" && { echo "APPLY-REFUSE: vivado.exe 活着 —— 构建/探针在飞"; exit 2; }
        tasklist 2>/dev/null | grep -qi "xsim\.exe"   && { echo "APPLY-REFUSE: xsim.exe 活着 —— 台架链在飞"; exit 2; }
    fi
    dirty=$(git status --porcelain -- "$RTL_LM" "$RTL_RS")
    [ -z "$dirty" ] || { echo "APPLY-REFUSE: 这两份 RTL 不干净，退回能力未证实："; echo "$dirty"; exit 2; }
    echo "PRE-OK 树空、两份 RTL 在 git 里干净（'git checkout -- <file>' 是真退路）"
fi

# anchor_replace FILE IF_TEXT TARGET_LINES PATCH_LINES NAME
anchor_replace() {
    local f=$1 IF=$2 T=$3 P=$4 NAME=$5 KIND=${6:-grow} MUST=${7:-} MUSTNOT=${8:-}
    APPLY=$APPLY node -e '
const [f,IF,T,P,NAME]=process.argv.slice(1);
const fs=require("fs");
const s=fs.readFileSync(f,"utf8");
const lines=[]; const re=/[^\r\n]*(?:\r\n|\n)/g; let mm;
while((mm=re.exec(s))!==null){ lines.push(mm[0]); }
if(lines.join("").length<s.length) lines.push(s.slice(lines.join("").length));  // 末行没有 terminator 也要收进来
const clean=(x)=>x.replace(/^\s+/,"").replace(/[\r\n]+$/,"");   // 比较时**两侧去空白**：缩进不是语义，
const TL=T.replace(/\r/g,"").split("\n").filter((l,i,a)=>!(i===a.length-1&&l==="")).map(clean);   // 但这份件里
//  ⚠ 放宽只发生在"行内比较"这一层，仍然要求**整段逐行等值**且**全文件唯一命中**（hits.length!==1 就 REFUSE），
//    写回用的是我自己那份缩进 ⇒ 不会因为放宽匹配而改到别处（第一版按字面全行比，`if (have_base) begin`
//    这条就因为它前面有 16 个空格而 ANCHOR-MISS，这是我踩出来的，不是树的错）。
const need=TL.length;
const hits=[];
for(let k=0;k+need<=lines.length;k++){
  let ok = clean(lines[k])===TL[0];
  if(ok) for(let i=1;i<need;i++){ if(clean(lines[k+i])!==TL[i]){ ok=false; break; } }
  if(ok) hits.push(k);
}
if(hits.length===0){ console.log(NAME+" ANCHOR-MISS(target 整行去行尾比也对不上): "+TL[0].slice(0,44)+"…"); process.exit(2); }
if(hits.length>1){ console.log(NAME+" ANCHOR-MULTIPLE: target 命中 "+hits.length+" 次（"+hits.join(",")+"），替换范围不清"); process.exit(2); }
const i0=s.indexOf(IF); if(i0<0){ console.log(NAME+" ANCHOR-MISS(if): "+IF); process.exit(2); }
const k=hits[0];
const j=lines.slice(0,k).join("").length;                     // 命中处起始字节
if(j < i0){ console.log(NAME+" ANCHOR-ORDER: target 在 if 锚点**之前**出现（说明我抄的这段形状换了位置）"); process.exit(2); }
const term=lines[k].endsWith("\r\n") ? "\r\n" : "\n";         // 沿用命中那一行自己的行尾
// 缩进自适应：比较放宽成"两侧去空白"之后，**写回**必须把命中行的缩进带回来（拷贝树自测抓到刀1把
// `                if (have_base) begin` 换成顶格的 `if (gapclr) begin …` —— 语法没问题但白吃一次 diff/行位移）。
const indent=(lines[k].match(/^[ \t]*/)||[""])[0];
const PL=P.replace(/\\n/g,"\n").split("\n").map(l=>/^[ \t]/.test(l)||l==="" ? l : indent+l);
const before=lines.slice(0,k).join(""), after=lines.slice(k+need).join("");
const out=before + PL.map(l=>l+term).join("") + after;
// 期望的形状由调用方给（第一版只有"必须变长"，那是**插入刀**的尺度；刀 4b 是把 8 行换成 6 行，
// 正确的尺子是"变短 + 旧守卫整段消失 + 新形状六条都在"—— 尺子的维度对不上时先怀疑尺子，不改判据迁就）
const KIND=process.argv[6]||"grow";
const MUST=(process.argv[7]||"").split(";").filter(x=>x!=="");
const MUSTNOT=(process.argv[8]||"").split(";").filter(x=>x!=="");
if(KIND==="grow" && out.length<=s.length){ console.log(NAME+" NO-GROWTH: 插入刀打完没变长（可能吞了尾巴）"); process.exit(2); }
if(KIND==="shrink" && out.length>=s.length){ console.log(NAME+" NO-SHRINK: 替换刀打完没变短（旧形状可能没被换掉）"); process.exit(2); }
for(const x of MUST){ if(out.indexOf(x)<0){ console.log(NAME+" MISSING: 打完刀找不到应该出现的 \""+x.slice(0,40)+"\""); process.exit(2); } }
for(const x of MUSTNOT){ if(out.indexOf(x)>=0){ console.log(NAME+" LEFTOVER: 打完刀旧形状 \""+x.slice(0,40)+"\" 还在"); process.exit(2); } }
if(out[out.length-1]!==s[s.length-1]){ console.log(NAME+" TAIL-DRIFT: 文件最后一个字符变了"); process.exit(2); }
const grow=out.length-s.length;
if(process.env.APPLY==="1"){ fs.writeFileSync(f,out); console.log(NAME+" APPLIED +"+grow+" 字节 行尾="+(term==="\r\n"?"CRLF":"LF")); }
else console.log(NAME+" CHECK-OK 唯一命中@第"+(k+1)+"行，替换后 +"+grow+" 字节 行尾="+(term==="\r\n"?"CRLF":"LF"));
' "$f" "$IF" "$T" "$P" "$NAME" "$KIND" "$MUST" "$MUSTNOT"
}

fail=0
echo "== r110 落刀器 mode=$MODE which=$WHICH $(date '+%F %H:%M:%S') =="

# ---------------- 刀 1：#174 gapclr 与 frame_done 同拍竞争（三个字符串逐字取自预验脚本） ----------------
if [ "$WHICH" = "all" ] || [ "$WHICH" = "1" ]; then
    LM_IF="stall_ms  <= 0;"
    LM_T="if (have_base) begin"
    LM_P="if (gapclr) begin gap_last<=0; gap_min<=0; gap_max<=0; gap_sum<=0; gap_valid<=0; end else if (have_base) begin"
    anchor_replace "$RTL_LM" "$LM_IF" "$LM_T" "$LM_P" "刀1" grow "if (gapclr) begin gap_last<=0;" "" || fail=1
fi

# ---------------- 刀 4①：new_row 独热化（每 bank 一根使能网，rows_hit 的 CE 只吃 5 输入或） ----------------
# 为什么同函数：今天 `if (row_idx<IMG_H && !row_covered) begin if (rbank==3'dk) rokk[roff]<=1 … end` 里
#   每条写使能布尔上就是 new_row & (rbank==k)。`5'b00001 << rbank` 在 rbank<=4 时给同一个独热；
#   rbank>=5 ⇒ row_idx>=320>IMG_H=300 ⇒ new_row 本已为 0 ⇒ 独热全 0 ⇒ `|bank_one` 与 new_row 同值。
# 要买的东西：综合把公共项提成**一根 fo=316 的广播网**（ISSUES #238，`build/setup_paths.rpt:59`）；
#   独热后每组一根网（fo≈64），计数器 CE 吃 5 输入或。
# ⚠ 落刀不等于收益（综合可以再折回去）：下一轮读 `build/setup_paths.rpt` 里那条终点 CE 的驱动网 fo，
#   **必须离开 316** 才算数；没离开就回退，不许改判据迁就它（#223 一轮一变量）。
if [ "$WHICH" = "all" ] || [ "$WHICH" = "4" ]; then
    RS_IF="reg [15:0]      rows_hit;"
    RS_T="        :                    rok4[roff];"
    RS_P="        :                    rok4[roff];\n    // 独热化（r110 刀 4① / ISSUES #238）：公共的\"新行\"拆成每 bank 一根使能网。\n    // ⚠ 必须放在 row_covered 的定义**之后**：拷贝树自测里我把它插在定义之前，\n    //    xvlog 直接 [VRFC 10-3380] identifier 'row_covered' is used before its declaration（pristine 0 错 vs patched 2 错）。\n    wire        new_row_w = (row_idx < IMG_H) && !row_covered;\n    // rbank<=4 由 row_idx<IMG_H(=300) 保证（ridx<=299 ⇒ rbank=ridx[8:6]<=4）；>=5 时 new_row_w 本已为 0。\n    wire [4:0]  bank_one  = new_row_w ? (5'b00001 << rbank) : 5'b00000;"
    anchor_replace "$RTL_RS" "$RS_IF" "$RS_T" "$RS_P" "刀4a" grow "wire [4:0]  bank_one" "" || fail=1

    RS_IF2="if (off < FRAME_BYTES) begin"
    RS_T2="                                    if (row_idx < IMG_H && !row_covered) begin
                                        if (rbank == 3'd0) rok0[roff] <= 1'b1;
                                        if (rbank == 3'd1) rok1[roff] <= 1'b1;
                                        if (rbank == 3'd2) rok2[roff] <= 1'b1;
                                        if (rbank == 3'd3) rok3[roff] <= 1'b1;
                                        if (rbank == 3'd4) rok4[roff] <= 1'b1;
                                        rows_hit <= rows_hit + 16'd1;
                                    end"
    RS_P2="                                    if (bank_one[0]) rok0[roff] <= 1'b1;\n                                    if (bank_one[1]) rok1[roff] <= 1'b1;\n                                    if (bank_one[2]) rok2[roff] <= 1'b1;\n                                    if (bank_one[3]) rok3[roff] <= 1'b1;\n                                    if (bank_one[4]) rok4[roff] <= 1'b1;\n                                    if (|bank_one) rows_hit <= rows_hit + 16'd1;"
    anchor_replace "$RTL_RS" "$RS_IF2" "$RS_T2" "$RS_P2" "刀4b" shrink "if (bank_one[4]) rok4[roff]" "if (row_idx < IMG_H && !row_covered) begin" || fail=1
fi

echo "== 结论 =="
if [ "$fail" = 0 ]; then
    if [ "$MODE" = "--apply" ]; then
        echo "APPLIED 落刀完成 —— 顺序：① bash build/sim/run_one.sh tb_link_monitor（约 40 秒，F2e 必须整支绿）"
        echo "          ② bash build/timing_lane.sh（约 9 分钟，与 r109 基线比：只许 tb_link_monitor 那支从红变绿）"
        echo "          ③ bash build/r110_chain.sh（构建+探针+台架+门禁；收益判据 = 那条 CE 的 fo 离开 316）"
    else
        echo "CHECK-OK 锚点全部唯一命中（本次未写任何文件；md5 需前后一致，见调用处那条断言）"
    fi
    exit 0
else
    echo "FAILED 有锚点没对上 —— 树已经和写这份计划时不一样了：逐条重读源码再改本脚本，**不许放宽锚点**"
    exit 1
fi
