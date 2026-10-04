#!/bin/bash
# build/reanchor_modules.sh —— 把 report/modules.md 的「例化者 文件:行」引用**按 D5b 自己的红单**重锚到正确行
#
# 为什么不是手改：一次 RTL 改动（r109 在 pl_video_top.v 里挪了换角拍点那段）会让它之后的所有行整体位移，
# 于是 modules.md 里那一列全部指错。手改要么数偏移（会数错——#236 就记过我数错），要么逐条读（20 条要读 20 次）。
# 这里的做法是**只信尺子**：读 line_cite_check 自己打出来的红行（哪份文档的第几行、指的是哪个文件的第几行、
# 那一行第 1 列实际是什么模块），再去目标文件里找"模块名出现在第 1 列且是例化"的那一行，逐条替换，
# 然后重跑尺子直到 0 硬错。规则：最多三轮，对不上就停下重读，不许放宽尺子（规矩 30/44）。
#
# 用法：bash build/reanchor_modules.sh [--check]     默认 --apply
cd "$(dirname "$0")/.." || exit 2
MODE=${1:---apply}
[ "$MODE" = "--check" ] && APPLYTAG=--check || APPLYTAG=--apply
DOC=report/modules.md
RTLDIR=src/rtl

# 尺子的范围就是这个脚本的范围：只处理 D5b 那种「例化者列指错」，别的红（soft 候选）一概不动
node -e '
const {execSync}=require("child_process"); const fs=require("fs");
const [doc,mode]=[process.argv[1],process.argv[2]];
const apply=(mode==="--apply");
let out="";
for(let round=1;round<=3;round++){
  try{ out=execSync("node src/host/line_cite_check.mjs",{encoding:"utf8",maxBuffer:1<<26}); }
  catch(e){ out=(e.stdout||"")+(e.stderr||""); }
  const lines=out.split(/\r?\n/);
  const reds=[];
  for(const L of lines){
    const m=L.match(/^\s*(\S+\.md):(\d+)\s+D5b.*?[：:]\s*(\S+\.v):(\d+)\s+第\s*1\s*列模块是\s*([A-Za-z_][A-Za-z0-9_]*)/);
    if(m) reds.push({doc:m[1],dline:+m[2],tgt:m[3],cited:+m[4],mod:m[5]});
  }
  console.log("ROUND "+round+" 尺子给出 D5b 红 "+reds.length+" 条");
  if(reds.length===0){ console.log("CLEAN 没有 D5b 红可改"); process.exit(0); }
  if(reds[0].doc!==doc){ console.log("SCOPE 红不在 "+doc+"（是 "+reds[0].doc+"）—— 本脚本只管 MODULES 那一列，停手"); process.exit(2); }
  const cache={};
  // 尺子打的是**文件名**（modules.md 那一列也写文件名），所以要按 basename 在 src/rtl 下解析出真实路径；
  // 同名文件出现两次就拒绝（不猜路径 —— 这是本仓那条"先怀疑尺子的维度"的反面：这次是脚本自己的维度错了）。
  const {execSync:ex}=require("child_process");
  const resolve=(base)=>{
    // 注意：整个脚本在 bash 的单引号里，所以这里**不能出现字面单引号** —— 用 \u0027 拼（今天踩过一次，
    // 症状是 bash 报 `syntax error near unexpected token 'newline'`，报的行号还落在 JS 正则那一行，很误导）。
    const q="\u0027";
    const list=ex("find src/rtl -name "+q+base+q,{encoding:"utf8"}).split(/\r?\n/).filter(x=>x!=="");
    if(list.length===1) return list[0];
    console.log("REFUSE "+base+" 在 src/rtl 下解析到 "+list.length+" 个（"+list.join(" ")+"）—— 不猜路径"); return null;
  };
  const inst=(f,mod)=>{
    const key=f+"|"+mod;
    if(!(key in cache)){
      const real=resolve(f); if(!real){ cache[key]=[]; cache[key+"_bad"]=1; return []; }
      const s=fs.readFileSync(real,"utf8").split(/\r?\n/);
      const hits=[];
      s.forEach((ln,i)=>{ if(new RegExp("^\\s*"+mod+"\\s+([A-Za-z_]\\w*\\s*\\(|#\\()").test(ln)) hits.push(i+1); });   // 顶层里例化是缩进的：去缩进后第一个词是模块名，后面跟 u_x ( 或 #(
      cache[key]=hits;
    }
    return cache[key];
  };
  const docLines=fs.readFileSync(doc,"utf8").split(/\r?\n/);
  let changed=0, refuse=0;
  for(const r of reds){
    const hits=inst(r.tgt,r.mod);
    if(hits.length===0){ console.log("REFUSE "+r.mod+" 在 "+r.tgt+" 里找不到第 1 列的例化行（模块名或写法变了，不猜）"); refuse++; continue; }
    if(hits.length>1){ console.log("AMBIGUOUS "+r.mod+" 在 "+r.tgt+" 有 "+hits.length+" 处第 1 列匹配 "+hits.join(",")+" —— 逐条读再决定，本轮不改它"); refuse++; continue; }
    const old=docLines[r.dline-1];
    const nw=old.replace(r.tgt.split("/").pop()+":"+r.cited, r.tgt.split("/").pop()+":"+hits[0]);
    if(nw===old){ console.log("MISS "+r.doc+":"+r.dline+" 里找不到字面 "+r.tgt.split("/").pop()+":"+r.cited+"（那一格的写法变了）"); refuse++; continue; }
    docLines[r.dline-1]=nw; changed++;
    console.log("  "+r.doc+":"+r.dline+"  "+r.tgt.split("/").pop()+":"+r.cited+" -> :"+hits[0]+"  ["+r.mod+"]");
  }
  console.log("ROUND "+round+" 待改 "+changed+" 条、拒绝 "+refuse+" 条"+(apply?"（写盘）":"（--check 不写盘）"));
  if(changed===0){ console.log(refuse>0?("STUCK "+refuse+" 条改不动：尺子的报错形状或源码写法变了，回去读源码，别放宽尺子"):"NO-CHANGE"); process.exit(refuse>0?1:0); }
  if(apply) fs.writeFileSync(doc, docLines.join("\n"));
}
console.log("LOOP-END 三轮没收敛，停手（规矩：同一问题三次不中就换打法）"); process.exit(1);
' "$DOC" "$APPLYTAG"
RC=$?
if [ "$RC" = 0 ] && [ "$APPLYTAG" = "--apply" ]; then
    echo "== 改完再对一次尺子与编码 =="
    node src/host/line_cite_check.mjs 2>&1 | iconv -f UTF-8 -t UTF-8//IGNORE | tail -2
    bash build/enc_check.sh >/dev/null 2>&1 && echo "编码：OK" || echo "编码：脚本不在或判红，手工核一遍再提交"
    git diff --stat -- "$DOC" | tail -2
fi
exit $RC
