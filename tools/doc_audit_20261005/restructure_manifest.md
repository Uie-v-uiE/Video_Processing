# 目录重构执行清单（board / build / data）

仓库：`Video_Processing`（相对路径一律从仓库根起算）。本清单只给形状、命令与判据影响，不含任何对仓库的写操作。

## 0. 实测口径（本清单里所有数字的来源）

| 项 | 实测值 | 复算命令 |
|---|---|---|
| 全仓跟踪件 | 3668 支 / 118.7 MB | `git ls-files \| wc -l`；下面第 0.1 节的 python |
| `build/` 跟踪 | 3117 支 / 107.43 MB（占全仓字节 90 %）；盘上 268 MB | `git ls-files build \| wc -l`、`du -sh build` |
| `board/` | 盘上 79 支 / 535 KB；跟踪 76 支；ignored 3 支（`board/HANDS_ON.md`、`board/uart_capture.txt`、`board/uart_script_capture.txt`） | `find board -type f \| wc -l`、`git ls-files board \| wc -l` |
| `data/` | 盘上 45 支 / 5.7 MB；跟踪 40 支；ignored 5 支（`ddr_dump.out` + `health_{clr,cur,p0,p1}.out`） | 同上 |
| `board/` 里有没有工程 | **0 支**：`find board -iname '*.xpr' -o -iname '*.xsa' -o -iname '*.elf' -o -iname '*.bit' -o -iname 'platform' -o -iname '*.mcf' \| wc -l` = 0 | 用户的"你啥都没有"成立 |
| 三个二进制在不在库 | **在**：`build/system.bit`(2 202 122 B)、`build/system.xsa`(865 533 B)、`build/ps_app.elf`(343 600 B) 全部 `git ls-files --error-unmatch` 命中；`git check-ignore` 对三者无命中。`board/system.bit|.xsa|ps_app.elf` 三件：**盘上没有、库里没有、`.gitignore` 也不挡**（`git check-ignore -q` 三支都无命中） | 用户的"你啥都没有"成立；`build/ps_app.elf` 实测 `md5=d0b07f84a0683db203086fb816ac71d7`，与 `build/r118_gates.txt:5` / `build/r118_gates_final.txt:5` 的 `ps_app.elf md5=d0b07f84a068` 同值 |
| ⚠ 本清单写作期间 HEAD 在动 | 清单初稿据 `848024b` 判 "`board/README.md:18` 说二进制不入库 = 失实"；该失实句**已被并行会话改口**（`26cda1f`，现 `board/README.md:18` 写的是"这三份**是随仓库入库的**"并给了 `git ls-files` 复算命令）。同一次并行会话还把"本机无 ARM 编译器、ELF 不能重编"证伪（`b989679`，见 B.3(1) 末段）。⇒ **执行本清单前，先把第 0 节和第 0.3 节的命令重跑一遍对表** | 剩下的真问题不是那句假话，而是 `build/gen_bit.tcl:25-26` 往 `board/` 写两件二进制、`.gitignore` 不挡、`board/` 里又从来没有过 ⇒ B.3(2) 的三选一仍要裁决 |
| 判红面（D4c 的 DELIVERY） | 54 份：`README.md`、`README_EN.md`、`board/README.md`、`report/*.md`（不含 `report/log/`） | `src/host/doc_currency_check.mjs:185-186` |
| 交付文档点名的、且此刻在盘上的凭据件 | **475 支**（其中 413 支同行没有"不随包"类豁免 ⇒ 删掉就判红） | 第 0.2 节的 node 片段 |

> 用户给的旧数（159 份逐轮件被点名）已过期：本轮实测 **475 支被点名 / 413 支无豁免**，只 `build/` 顶层就要动 **407 处行级引用**。这个数字决定了本次重构的正确顺序：**先改尺子和指路，后删件**，反过来就是"删完尺子空转"。

### 0.1 按目录的跟踪字节数

```bash
python - <<'PY'
import os, subprocess
tot = 0
for d in ["board","build","data","report","src","sim","skills"]:
    fs = subprocess.run(["git","ls-files",d],capture_output=True,text=True).stdout.split()
    b = sum(os.path.getsize(f) for f in fs if os.path.exists(f))
    tot += b
    print(f"{d:8s} n={len(fs):5d} {b/1048576:8.2f} MB")
print("合计", round(tot/1048576,2), "MB")
PY
```

### 0.2 "谁点名了谁"的通用取数片段（三段清单都由它生成）

```bash
node - <<'JS'
const {readFileSync,readdirSync,statSync}=require("fs");
const isfile=r=>{try{return statSync(r).isFile()}catch(e){return false}};
const isdir =r=>{try{return statSync(r).isDirectory()}catch(e){return false}};
const HOME=["README.md","README_EN.md"];
const DEL=r=>HOME.includes(r)||r==="board/README.md"
  ||(r.startsWith("report/")&&!r.startsWith("report/log/")&&r.endsWith(".md")&&r.split("/").length===2);
// 与 src/host/doc_currency_check.mjs:155-157 的 CITE_ART 同一条正则（不含反斜杠写法）
const CITE=/(?:^|[^A-Za-z0-9_/:.-])(build|data|sim|board|skill|report)[/][A-Za-z0-9_./-]*?[A-Za-z0-9_-]+[.](?:txt|rpt|csv|bit|elf|md5|xdc|py|mjs|sh|tcl|v|bat|log|wdb)(?:[.](?:json|txt|rpt|csv|md|log|html))*(?=[^A-Za-z0-9]|$)/g;
const NS=["不随包","不入库","本地留档","不在本包内"];   // 同 :200 的 NOSHIP_MARK
function w(d,o){for(const f of readdirSync(d===""?".":d)){if(f===".git")continue;const r=d===""?f:d+"/"+f;
  if(isdir(r)){if(d===""&&/^(node_modules|__pycache__|\.Xil|xsim\.dir|sim_work|vitis|vivado_system|c4_probe|docs)$/.test(f))continue;w(r,o);}
  else if(isfile(r))o.push(r);}return o;}
const hits=new Map();
for(const rel of w("",[]).filter(DEL)){
  const lines=readFileSync(rel,"utf8").split("\n");let fence=false;
  lines.forEach((l,i)=>{ if(/^[ ]*(```|~~~)/.test(l)){fence=!fence;return;}
    if(NS.some(k=>l.includes(k)))return;                       // 同行已声明不随包 ⇒ 只报数
    for(const m of l.matchAll(CITE)){const t=m[0].replace(/^[^a-z]/,"");
      if(/NN|[$*]/.test(t)||!isfile(t))continue;
      (hits.get(t)||hits.set(t,[]).get(t)).push(rel+":"+(i+1));}});}
console.log("被交付文档点名且盘上存在的件：",hits.size,"支；引用点：",
  [...hits.values()].reduce((a,v)=>a+v.length,0),"处");
for(const [t,s] of [...hits].sort((a,b)=>a[0]<b[0]?-1:1)) console.log(t,"<-",s.join(", "));
JS
```

### 0.3 移动性目标警告

实测期间 `vivado_system/` 从 5.9 MB 涨到 69 MB、再涨到 113 MB（另一次会话正在跑 `impl_1`）。
凡带 `.runs/.gen/.cache` 的数都要**跑一次现量再用**，不要引用本清单的快照值做决策；
本清单里"进仓形状"的数（`.xpr` + `.srcs`）是稳定量，已单独标出。

---

# A. `build/`

## A.1 现状（实测）

* 顶层 1230 支 / 28.3 MB（字节和），84 个子目录。扩展名分布：txt 781、rpt 179、sh 99、log 58、py 44、mjs 32、md 20、tcl 8、elf 2、xsa 1、bit 1、ps1 1、patch 1、marker 1、json 1、jou 1。
* 顶层按类（支数 / 字节）：

| 类 | 支数 | MB | 被交付文档点名 | 无豁免（删了就红） |
|---|---:|---:|---:|---:|
| `rNN_*.txt`（不含 gates） | 511 | 7.94 | 96 | 88 |
| `rNN_*gates*.txt` | 53 | 0.19 | 22 | 22 |
| `gates_rNN*.txt`（旧命名） | 26 | 0.04 | 1（`gates_r62.txt`） | 1 |
| `rNN_*.log` | 53 | 3.01 | 0 | 0 |
| `rNN_*.sh/.py/.mjs/.tcl/.ps1` | 115 | 0.59 | 16 | 16 |
| `rNN_*.md` | 16 | 0.11 | 2 | 2 |
| `rNN_*.rpt` | 15 | 0.47 | 5 | 4 |
| `probe_*` | 49 | 1.31 | 2 | 2 |
| `*rotate*`（与上类有重叠） | 10 | 0.08 | 2 | 2 |
| 其余顶层 `.rpt` | 125 | 7.01 | 14 | 12 |
| 其余顶层 `.txt/.log` | 187 | 3.44 | 19 | 16 |

* 子目录族（盘上 du）：`frozen_*` 29 支目录 ≈94 MB、`evidence_r*` 12 目录 ≈37 MB、`isolated_*` 13 目录 ≈39 MB、`r85_isolated/r86_exp_isolated/r88_exp/r89_exp/r105ab_pre_1/r105ab_post_1` 6 目录 ≈21 MB、`evidence/` 26 MB（**这一支是被文档咬得最狠的**）。
* 子目录族（跟踪字节）：`evidence/` 967 支 22.89 MB；`evidence_r*` 151 支 16.41 MB；`rNN_*` 目录 48 支 13.92 MB；`frozen_*` 445 支 12.51 MB；`isolated_*` 122 支 6.01 MB。

## A.2 按"谁还在指它"分四档（这是本次重构唯一需要做的判断）

对每支顶层件跑"是否被 ① 交付文档 ② 跟踪脚本 ③ 跟踪非交付 .md ④ 未跟踪 .md（`docs/`）提过名字"，实测：

| 档 | 判据 | 支数 | MB | 处置 |
|---|---|---:|---:|---|
| **E** | 谁都没提 | **634** | **16.54** | **直接删，零引用改动** |
| **C** | 只被跟踪的非交付 `.md`（`report/log/`、`build/rNN_*.md`）提 | 188 | 3.63 | 删件 + 删/改那几份 `.md`（它们本身在退役名单里） |
| **B** | 只被跟踪脚本提（`rNN_chain.sh` 互调、构建产物名） | 182 | 1.75 | 删件时**连着调用它的脚本一起删**，否则脚本变死代码 |
| **A** | 被交付文档点名 | 226 | 6.39 | 逐条改指路（见 A.4），或留件 |

E 档的扩展名分布：txt 436、rpt 142、log 40、md 5、sh 4、mjs 4、py 1、jou 1、**elf 1**（`build/ps_app_r64b.elf`）。
E 档里的 gates 件（都可删，不影响 D3，因为 D3 取的是**编号最大**的那一份，最大全绿件是 `r75_gates.txt`，属 A 档）：
`gates_parkcheck.txt gates_r46.txt gates_r47.txt gates_r48.txt gates_r49pre_restore_note.txt gates_r51.txt gates_r52.txt gates_r52b.txt gates_r53.txt gates_r54_build34_cdc_red.txt gates_r56.txt gates_r58c.txt gates_r59a.txt gates_r59b.txt gates_r60.txt gates_r60_red.txt r116_gates_wait.txt r86_gates_after_osdfix.txt r86_gates_try1.txt r94_gates164b_before.txt r96_gates_after_ce_hook.txt r96_gates_ce_broken.txt`

生成 E 档名单的命令（与 0.2 同源，只是把判定面从"交付文档"扩到"任何 .md + 任何脚本"）：

```bash
node - <<'JS'
const {readFileSync,readdirSync,statSync}=require("fs"),{execSync}=require("child_process");
const isfile=r=>{try{return statSync(r).isFile()}catch(e){return false}};
const isdir =r=>{try{return statSync(r).isDirectory()}catch(e){return false}};
const tracked=execSync("git ls-files",{maxBuffer:1<<28}).toString().split("\n").filter(Boolean);
const tset=new Set(tracked);
const HOME=["README.md","README_EN.md"];
const DEL=r=>HOME.includes(r)||r==="board/README.md"||(r.startsWith("report/")&&!r.startsWith("report/log/")&&r.endsWith(".md")&&r.split("/").length===2);
const CODE=/[.](mjs|sh|py|tcl|ps1|bat|c|h|v|xdc)$/, MD=/[.]md$/;
function w(d,o){for(const f of readdirSync(d===""?".":d)){if(f===".git")continue;const r=d===""?f:d+"/"+f;
 if(isdir(r)){if(d===""&&/^(node_modules|__pycache__|\.Xil|xsim\.dir|sim_work|vitis|vivado_system|c4_probe)$/.test(f))continue;w(r,o);}
 else if(isfile(r))o.push(r);}return o;}
function names(files){const s=new Set();for(const r of files){let t;try{t=readFileSync(r,"utf8")}catch(e){continue}
 for(const m of t.matchAll(/(?:build|data|board|sim|src|report|skills?)[/][A-Za-z0-9_.\/-]*[A-Za-z0-9_-][A-Za-z0-9_.-]*/g))s.add(m[0].replace(/[.]$/,""));}return s;}
const N={del:names(tracked.filter(DEL)),code:names(tracked.filter(f=>CODE.test(f)&&!DEL(f))),
         md:names(tracked.filter(f=>MD.test(f)&&!DEL(f))),um:names(w("",[]).filter(f=>MD.test(f)&&!tset.has(f)))};
const has=(S,t)=>{const b=t.split("/").pop();return S.has(t)||S.has(b)||[...S].some(x=>x.endsWith("/"+b)&&x.length>b.length+1)};
const E=readdirSync("build").filter(f=>isfile("build/"+f))
  .filter(f=>{const t="build/"+f;return !(has(N.del,t)||has(N.code,t)||has(N.md,t)||has(N.um,t))});
console.log(E.length,"支");console.log(E.join("\n"));
JS
```

## A.3 删除清单（按模式，附实测支数/体积/取舍）

> 命令都在仓库根跑。删之前先做 A.5 的第 1–3 步。

| # | 模式 | 支数 | 体积 | 取舍 | 备注 |
|---|---|---:|---:|---|---|
| D1 | E 档全量 | 634 | 16.54 MB | **删** | 零引用，先删这一层把体积打掉一半 |
| D2 | `build/rNN_*.log` | 53 | 3.01 MB | **删**（E 档已含 40 支，余 13 支属 B/C 档） | `.log` 从来不该入库：`.gitignore:11` 早就挡 `*.log`，这批是历史绕过 |
| D3 | `build/probe_*.rpt` | 49 | 1.31 MB | **删 47 支**，留 `probe_split100_old.txt`、`probe_split100b_old.txt` 的引用一起处理（`report/commands.md:290` 点名这两支） | 全是一次性 `report_timing` 打点 |
| D4 | `build/sweep_*_timing.rpt` | 4 | 5.02 MB | **删** | 单次策略扫描的输出，最大四支 rpt 占 `build/` 报告体积的 72 %（5.02 / 7.01）；结论已在 `report/timing_global.md`。同批检查 `build/sweep_summary.txt`（A 档，`build/README.md:24` 点名它，属"脚本会产出什么"的说明，留） |
| D5 | `build/roster_*.rpt` | 101 | 0.84 MB | **只留 3 支**：`roster_r118_after_clkout1_1_setup.rpt`（`report/build-notes.md:60` 点名，唯一在 A 档的 roster）、`roster_r118_after_clkout0_1_setup.rpt`、`roster_r118_after_eth_rxc_setup.rpt`（板上这一版的逐时钟名册） | 其余 98 支是逐轮滚档，同一形状重复 40 遍、单支约 1.0–10 KB |
| D6 | `build/rNN_*.md`（逐轮计划/清单） | 16 | 0.11 MB | **删 14 支**，留 `r113_angle_lane_plan.md`、`r116_batch_plan.md`（被交付文档点名共 9 处，改指路代价高的两份先留着） | `build/README.md`、`build/coverage.md`、`build/probe-guard.md`、`build/provenance.md` 不属这一类，见 A.4 |
| D7 | `build/rNN_*.sh/.py/.mjs/.tcl/.ps1`（一次性脚本） | 115 | 0.59 MB | **删 97 支**（115 减去 18 支带 D5 行号锚点的；这 18 支里 16 支还被交付文档按路径点名，属 A 档） | `build/make_submission.sh:112` 的 `KEEP_ALWAYS_RE` 头一项是 `\.(sh\|tcl\|py\|ps1\|bat\|xdc\|f\|v\|c\|h)$` ⇒ **凡 `.sh/.py/.tcl/.ps1` 无条件进提交包**，`.mjs` 不在这一列。所以这 115 支里只有从仓库真删掉才会缩包；只挪目录没用 |
| D8 | `build/*rotate*` | 10 | 0.08 MB | **删 9 支**：`r109/r110/r112/r113/r116/r118/r120_rotate*.*`、`r113_step5_rotate.sh`、`r117_docrotated.marker`；**留 `rotate_from_metric.mjs`**（现役文档轮转器） | 一次性文档改写器，跑完即废 |
| D9 | `build/frozen_*` | 29 目录 / 445 支 / 12.51 MB（盘上 94 MB，二进制被 `.gitignore:79-81` 挡着） | | **留 3 套、删 26 套**（见下） | |
| D10 | `build/evidence_r*` | 12 目录 / 151 支 / 16.41 MB（盘上 37 MB） | | **留 3 套、删 9 套** | |
| D11 | `build/isolated_*` | 13 目录 / 122 支 / 6.01 MB（盘上 39 MB） | | **全删 13 套**（`isolated_0929_2036` 已被 `.gitignore:166` 挡；`build/isolated_*/*.bit|*.xsa` 被 `:142-145` 挡） | 5 套属 A 档、8 套属 C/E 档 ⇒ 删 A 档那 5 套要改指路 |
| D12 | `build/r85_isolated` `r86_exp_isolated` `r88_exp` `r89_exp` `r105ab_pre_1` `r105ab_post_1` | 6 目录 / 57 支 / 约 11 MB | | **留 `r105ab_pre_1`+`r105ab_post_1`（A/B 对照，两份都是"某一改动的两端"）**；`r89_exp`、`r88_exp` 属 C/A 档，要删得先改 `build/rNN_*.md`；`r85_isolated`、`r86_exp_isolated` 删 | |
| D13 | `build/failed_r24`、`build/multidrive_r51_aborted`、`build/red_r49_wns-5.014`、`build/exp_r20_glyph`、`build/strprobe`、`build/fb_split_probe`、`build/uram_probe`、`build/c4_probe_*`（空） | 8 目录 / 46 支 / 约 6 MB | | **删**，只留 `build/red_r49_wns-5.014`？——不留：它只被 `build/rNN_*.md` 提（C 档） | `c4_probe_*` 三个目录跟踪件 0，`rm -rf` 无 git 影响 |
| D14 | `build/bitstream/`（2 支 2.93 MB） | 2 | 2.93 MB | **删**（E 档，全仓无人提名） | 是某次归档的 bit/xsa 副本，与 `build/system.*` 重复 |

### D9/D10 的取舍名单（逐目录，含理由）

留：

* `build/evidence_r75/` —— **必须留**。`build/gates.sh:150` 的默认 CDC 采纳版 `build/evidence_r75/cdc.rpt`（实测 2 279 B）；删了 `gates.sh:160-163` 打 `FATAL 取不到采纳版` 并把 `cdc_ok=0` ⇒ **门禁第 CDC 项直接红**，不是静默跳过。该目录同时是 r75 冻结套（`r75_gates.txt` 有 `GATES: ALL PASS`，是 D3 的基准）。
* `build/evidence_r69/`、`build/frozen_r19_arb/`、`build/frozen_r62_geom/` —— 被交付文档以目录名点名（D2 判据 `doc_currency_check.mjs:83` 的 `CITED` 正则专抓 `build/(frozen_|evidence_)+名字`），删了判红。
* `build/frozen_r13/` —— 用户说的"挑选几个重要的版本"里的最早一套；跟踪件 8 支。
* `build/evidence_r64b/`、`evidence_r65_notadopted/`、`evidence_r63b/` —— 三套属 A 档。取舍：**删 `evidence_r63b`、`evidence_r64b`、`evidence_r65_notadopted`**（都是"没采纳的那一版"，结论已在 `report/40-optimization.md`），代价是改 `report/comparison-notes.md:100-102` 与 `report/50-results.md:113-115` 共 5 处。要省事就连目录一起留，只删目录里 `.rpt` 之外的中间件（实测这 3 目录共 38 支、9.5 MB）。
* `build/report/` —— **必须留且不能空**：`build/deliver_spec_check.mjs:339-348`（C4）与 `:360-383`（C4b）判 `build/report/` 非空、含 utilization 与 timing 件、且每份件的名字都被 `build/report.tcl` 提到。实测 7 支 / 0.28 MB：`cdc.rpt clock_util.rpt methodology.rpt power.rpt route_status.rpt timing_summary.rpt utilization.rpt`。

删（D9/D10/D11 合计 26 + 9 + 13 = 48 套目录里，除上面点名的保留套之外全部删）。删之前必须处理它们的名字引用：**实测被交付文档点名的目录名 0 处落在 frozen_/isolated_ 之外的判红位**（`frozen_*` 目录被点名 0 支、`isolated_*` 被点名 5 支其中 3 支无豁免）⇒ 目录这一层的指路负担远小于文件那一层，可以批量删。

## A.4 保留清单（逐文件名 + 一行理由）

### 顶层构建入口（`build/deliver_spec_check.mjs:335` 的 C4 硬名单，少一支就 FAIL）

| 文件 | 为什么留 |
|---|---|
| `build/build.tcl` | C4 名单 + `README.md:36` 的第一条复现命令 |
| `build/create_project.tcl` | C4 名单 + `README.md:41` 分步入口 |
| `build/add_sources.tcl` | C4 名单 + `README.md:41` |
| `build/synth.tcl` | C4 名单 + `README.md:41` |
| `build/impl.tcl` | C4 名单 + `README.md:41` |
| `build/report.tcl` | C4 名单 + `README.md:37`；C4b 还要求它正文点到 `build/report/` 每一份件名（`:371`） |
| `build/gen_bit.tcl` | C4 名单 + `README.md:38`；`:25-26` 往 `board/` 写 `system.bit|.xsa`（见 B.3 的方案裁决） |

### 尺子与被尺子读的东西

| 文件 | 为什么留 |
|---|---|
| `build/gates.sh` | 发布前检查本体。`:29-33` 默认读 `build/` 平铺报告；`:150` 读 `build/evidence_r75/cdc.rpt`；`:452/507/524` 分别调 `doc_currency_check`、`line_cite_check`、`metric_recheck` ⇒ 这三把尺子红，门禁就红 |
| `build/timing_summary.rpt` | `gates.sh:31` 的 `$T`、`src/host/metric_recheck.mjs:207`、`README.md:64-66`、`board/README.md:14/20/38/94` 全都读**平铺这一支**，不是 `build/report/` 那一支 |
| `build/utilization.rpt` | `gates.sh:31`、`metric_recheck.mjs:208`、`README.md:67`、`report/01-overview.md:8` |
| `build/power.rpt` | `gates.sh:32`、`metric_recheck.mjs:209`、`README.md:68`、`board/README.md:95` |
| `build/methodology.rpt` | `gates.sh:32` 的 `$M` |
| `build/route_status.rpt` | `gates.sh:33` 的 `$R`；缺 ⇒ `:35-37` `FATAL 缺报告` 退出 2 |
| `build/cdc.rpt` | `gates.sh:33` 的 `$C` |
| `build/system.bit` | `doc_currency_check.mjs:280` 拿它的 md5 当 D1b 基准。实测 `md5=cd04907e1369da35d21c4090d552f5ee`，前 12 位 `cd04907e1369` 被 `build/r118_gates.txt` 的"身份："行戳着 ⇒ **删这块 bit 或删那份 gates，D1b/D1c 双双判不了** |
| `build/system.xsa` | `build/tcl/build_system_axigpio.tcl` 的产出、Vitis 平台的输入（`vitis/platform/vitis-comp.json` 的 `configuration.xsa` 指它） |
| `build/ps_app.elf` | `build/ps_app.mjs` 的 `const OUT`（现 `:33`）那一行的产物；实测 `md5sum build/ps_app.elf` = `d0b07f84a0683db203086fb816ac71d7`，与 `build/r118_gates_final.txt` 的 `ps_app.elf md5=d0b07f84a068` 同值 ⇒ **它是板上已复验的那一颗**。它能被重编（见 B.3(1) 末尾那条），但重编出来的是另一颗（`4ed58740785c…`，未上板） ⇒ 这颗不能当"可再生的派生物"删 |
| `build/gates_r62.txt` | 被 `report/40-optimization.md` 点名 6 处（A 档）；若要删就同批改这 6 行 |
| `build/r75_gates.txt` | **D3 的基准**：实测 `newestGreenSet()` 在 14 份含 `^GATES: ALL PASS` 的 `build/{gates_rNN,rNN_gates}.txt` 里取到 `r75`。删了它 D3 立刻判"首页念 r75、最新全绿的是 r74" |
| `build/r118_gates.txt` | **D1b/D1c 的基准**（戳着当前 bit 的 md5，且是唯一命中 `^r\d+_gates\.txt$` 的那份） |
| `build/r118_gates_final.txt` | `README.md:77`、`README_EN.md:68`、`report/05-timing.md:15/21/142/147` 等 20 处点名，且实测它的"身份："行与 `r118_gates.txt` 同一个 md5 |
| `build/hold_paths.rpt`、`build/clock_uncertainty.rpt` | `README.md:66`、`board/README.md:29/39` 逐行读数出自这两支 |
| `build/cdc_details.rpt`、`build/clock_util.rpt`、`build/cdc_baseline.txt`、`build/check_timing_verbose.rpt`、`build/setup_paths.rpt`、`build/crit_paths_raw.rpt`、`build/util_hier.rpt`、`build/util_hier_probe.rpt`、`build/read_run_timing.rpt` | `report/08-limits.md:177`、`report/build-notes.md:22/54/55/58/71`、`report/timing_global.md:25/98`、`report/measurements.md:60/62` 等点名，且 `build/tcl/*.tcl` 有对应重出脚本 |
| `build/tb_v98_report.txt`、`build/tb98_gate_ce.txt`、`build/tb_v98_c5_baseline.txt` | `data/metrics.csv` 的"整屏逐像素判据"行的证据列 = `build/tb_v98_report.txt` ⇒ C2 判它存在 |
| `build/ports_check.txt`、`build/width_warnings.txt`、`build/multi_driven.txt`、`build/ports_dup_ce.txt`、`build/ports_floor_ce.txt` | `gates.sh` 的 `$5` 输出（文件头 `:4` 写明"输出：build/ports_check.txt"）与 `build/tcl/build_system_axigpio.tcl:398-407` 的产出；`report/70-reproduce.md:122`、`report/build-notes.md:58` 点名 |
| `build/fingerprint_bridge.txt`、`build/isolated_r100_141_note.txt`、`build/export_r97c_console.txt`、`build/l1_console_r52.txt`、`build/board_temp_r97.txt`、`build/crit_paths.txt`、`build/tb_edge_rim_r86/r92/r94.txt` | `report/known_issues.md`、`report/perf_report.md`、`report/optimization_log.md`、`report/measurements.md` 的 A 档点名件（19 处）。**如果不想留，就按 A.5 第 2 步批量改指路** |
| `build/r118_build_console.txt`、`build/r118_console.txt` | `README.md:42`、`README_EN.md:35`、`build/README.md:4/46/69`、`report/repro-check.md:97/154/208/209` 拿它当"20 分钟实测"的出处 |
| `build/evidence/**`（967 支 / 22.89 MB） | **整目录留**。实测其中 **152 支**被交付文档无豁免点名（`build/evidence/r119_*`、`r121_*`、`r87_*`、`r113_*` 等），是全仓被指得最多的一层；`board_verify.sh` 与 `build/tcl/ps_jtag_boot.tcl` 每次也把 console 落在这里（`board/README.md:66`） |
| `build/checks/check_repo_consistency.mjs`、`build/checks/check_repo_hygiene.sh` | C1–C12 尺子本体（`:365-376` 有硬编码路径，见 A.5） |
| `build/deliver_spec_check.mjs`、`build/deliver_spec_selftest.mjs` | C0–C5 尺子本体 + 自检 |
| `build/make_submission.sh` | 导出器；`:112` `KEEP_ALWAYS_RE`、`:696` `SKIP_RE` 与 D4c 共用同一套豁免词表 |
| `build/board_verify.sh` | `README.md:48`、`board/README.md:69`；`:118` 的 `VP_XSDB` 检查 |
| `build/freeze_evidence.sh`、`build/refresh_evidence.sh`、`build/verify_evidence.sh`、`build/freeze_selftest.sh`、`build/restore_documented_bit.sh`、`build/rtl_fingerprint.sh`、`build/orphan_rtl.sh`、`build/cleanup_wip.sh` | 冻结/回验/清理这条流程的现役件；`report/06-validation.md:108`、`report/70-reproduce.md:60/166`、`report/known_issues.md:570/581` 点名 |
| `build/ps_app.mjs`、`build/build_ps_app.py` | PS 固件构建链（`ps_app.mjs` 里 `const BSP` 那一行的默认值是**仓库内**的 `vitis/platform/…/standalone_ps7_cortexa9_0/bsp` ⇒ 见 B.3(1)：这条默认值决定了 `vitis/` 进不进仓是"能不能重编 ELF"的分界） |
| `build/tb98_report.sh`、`build/tb98_gate_ce.sh`、`build/rim_gate_ce.sh`、`build/rim_report.sh`、`build/run_one_ce.sh`、`build/pre_readings.sh`、`build/timing_lane.sh`、`build/timing_roster_diff.sh`、`build/roster_from_summary.sh` | 台架与名册读数工具；`report/claims-vs-evidence.md:100`、`report/05-timing.md:18/19/63/111/165`、`report/repro-check.md:94`、`report/bench_mutation.md:16` 点名 |
| `build/ps7_init.tcl` | 被 `.gitignore:91` 挡住（派生物）—— **它在盘上但不在库**，不要因为它被脚本点名就留库 |
| `build/README.md`、`build/coverage.md`、`build/provenance.md`、`build/probe-guard.md`、`build/tcl/README.md`、`build/sim/names.md`、`build/runs/ledger.md`、`build/runs/decisions.md`、`build/reports/index.md`、`build/artifacts/README.md` | `build/README.md` 被 `deliver_spec_check.mjs:348`（C4「README 缺对照表」）判红面；其余 9 份被 `report/build-notes.md`、`report/README.md:116-117`、`report/70-reproduce.md:147/148`、`report/run-queue.md:25/27` 点名 |
| `build/tcl/**`（96 支跟踪 `.tcl`，2.7 MB） | **整目录留**，但按 `build/tcl/README.md` 的名单在 README 里划掉"别再当入口"的那几支。原因：C4（`deliver_spec_check.mjs:336-338`）对**每一支跟踪 `.tcl`** 判头 12 行必须含 `作用/前置/产出/参数` ⇒ 往 `board/` 新增 `.tcl` 也必须带这块头 |
| `build/parsed/**`（9 支）、`build/roster/**`（2 支）、`build/sim/**`（52 支） | `report/90-open-items.md:151`、`report/build-notes.md:15/19` 等点名；`build/sim/run_one.sh` 是台架入口 |
| `build/micro_rd/**`（跟踪 6 支，盘上 36 支） | 读口探针的**文本件**留（`proj_*/` 已被 `.gitignore:115` 挡） |

### 不在此列 ⇒ 一律进 A.3 的删除集

`build/*.stdout`、`build/*.marker`、`build/r71_build.jou`、`build/dfx_runtime.txt`（`.gitignore:4` 已挡）、`build/r94_top_mux_superceded.patch`、`build/r117_docrotated.marker`、`build/ps_app_r64b.elf`。

## A.5 保留但要先改引用（逐文件：谁指它 → 改成什么）

**执行顺序（照做，别倒过来）**

1. **先改尺子里写死的默认值**（下表 R1–R5），否则删完尺子空转。
2. 再改交付文档的指路（下表 + 批量 sweep）。
3. `node src/host/doc_currency_check.mjs`、`node src/host/line_cite_check.mjs` 跑到绿。
4. 才动 `rm`/`git rm`。
5. 删完再各跑一次两把尺子 + `node build/checks/check_repo_consistency.mjs`，确认没有新增红项。
6. 最后重写 `build/README.md` 的类表（A.6）。

### 尺子里写死的引用

| 编号 | 位置 | 现在写的是什么 | 改成什么 |
|---|---|---|---|
| R1 | `build/gates.sh:150` | `CDCADOPT=${CDCADOPT:-build/evidence_r75/cdc.rpt}` | **不改**，同批保住 `build/evidence_r75/cdc.rpt`（实测 2 279 B）。若必须删该目录：改成 `CDCADOPT=${CDCADOPT:-build/report/cdc.rpt}`——注意这会同时取消 #209 那条"与上一版采纳比较"的语义，所以 `gates.sh:147-149` 那段注释要一起改成"对照物是当前 `build/report/` 那一份"并在 `:158` 的打印里念出对照件的来历 |
| R2 | `build/gates.sh:18-21` | 警告"不要把本脚本输出直接重定向成它自己要读的 `build/rNN_gates.txt`"，并点名 `:20-21` 的 D3 基准 | **不改**，但删 gates 件后这条更关键：`newestGreenSet` 只剩 `r75` 一份 ⇒ 任何一次 `> build/r75_gates.txt` 截断都会让 D3 读到半空文件。建议在 `:22` 那句"正确姿势两步"后面补一行：`# 现在仓里只有 r75 一份全绿门禁件，它同时是 D3 的基准，动它之前先 cp 一份` |
| R3 | `src/host/doc_currency_check.mjs:278-296`（`currentBoardRound`）+ `:386-398`（`newestGreenSet`） | 前者要求存在一支匹配 `^r\d+_gates\.txt$` 且正文含 `system.bit md5=<当前 12 位>` 的件；后者要求匹配 `^gates_r(\d+)\.txt$|^r(\d+)_gates\.txt$` 且含 `^GATES: ALL PASS` 的最大编号件 | **不改代码**，用"保住 `build/r118_gates.txt` 与 `build/r75_gates.txt` 两支"来满足。若要改命名（比如都收进 `build/evidence/`），必须同步把 `:289` 与 `:390` 的正则改成新形状，并在两处注释里说明"基准件的形状变了" |
| R4 | `build/checks/check_repo_consistency.mjs:365-366` | `exists('build/evidence/r119_pin_skew_probe2.txt') && exists('build/evidence/r119_window_check.txt')`（C10） | `build/evidence/` 整目录留 ⇒ **不改**。若哪天真要精简 `build/evidence/`：把这两行改成"取 `build/evidence/r*_pin_skew_probe*.txt` 里编号最大的一对"，并在 `:367` 的注释里保留"原来对缺失件返回 0 会让 `0<=0` 判 PASS"那条教训 |
| R5 | `build/checks/check_repo_consistency.mjs:373` | `cand = ['build/evidence/r119_pin_skew_probe.txt', 'build/evidence/r119_window_check.txt', 'board/acceptance.md', 'report/known_issues.md']`，`:376` 判 `has>=3` | 本清单 B.5 要删 `board/acceptance.md` ⇒ 这一行**必须改**：把 `'board/acceptance.md'` 换成 `'board/evidence/index.md'`（新形状里的判读件，见 B.2），否则 `has` 从 4 降到 3，虽然 `>=3` 还成立，但一旦第二份 r119 件也漂走就直接 FAIL；改完在 `:374` 的注释念一句"候选件随 board/ 重构换过一支" |
| R6 | `build/make_submission.sh:112` | `KEEP_ALWAYS_RE='...|^build/report/|^data/golden/|MANIFEST|README|^submit/|^skills/'` | 若 C 段决定删 `data/golden/` ⇒ 必须同时删掉 `^data/golden/` 这一段，否则导出器仍按不存在的目录做形状保留，`_pruned.txt` 会念一条空规则。删 `build/frozen_*`/`evidence_r*` 时顺带检查 `:179` 与 `:382` 的 `for d in build/evidence_* build/frozen_* …` 循环是否会因 glob 空匹配而报错（bash 默认 glob 不匹配时字面量进循环，`[ -d ]` 挡不住的话要加 `shopt -s nullglob`） |
| R7 | `build/deliver_spec_check.mjs:335` | C4 的 7 支 tcl 名单 | 名单里的 7 支一支都不能删 ⇒ A.4 已保 |
| R8 | `build/deliver_spec_check.mjs:338` | 每一支跟踪 `.tcl` 的**前 12 行**必须含 `作用|前置|产出|参数|purpose|inputs?|outputs?` | B.3 往 `board/project/` 放的每一支新 `.tcl` 都要带这块头，否则 C4 从 PASS 变 FAIL（这是"往 board 塞工程"这个动作唯一会踩的硬门） |
| R9 | `src/host/metric_recheck.mjs:207-209` | 读的是 **平铺** `build/timing_summary.rpt`/`build/utilization.rpt`/`build/power.rpt`，不是 `build/report/` 那三支 | **不改**，A.4 已保平铺三支。若要把平铺三支并进 `build/report/`，这三行同批改，且 `gates.sh:29-33` 的 `pick()`（默认 `D=build`，回落 `build/../`）也要改，否则 `gates.sh` 会去仓库根找报告并 `exit 2` |
| R10 | `data/metrics.csv` 第 3/17/18/19/20/21 行的证据列 | 6 行写 `board/verify_r87.md` | 本清单 C 段保住 `board/verify_r87.md` ⇒ 不改。若 B.5 决定删它，就把这 6 个单元格改成 `board/evidence/index.md`（新形状）并同批改 `report/08-limits.md:204/244`、`report/50-results.md:38/148/152/199` 共 8 处 |

### 交付文档指路：批量 sweep 的规模（实测）

删 A.3 的 D1–D14 全部后，需要改的行按文档分布（只算无豁免的 D4c 点名）：

| 文档 | 要改的行数 | 主要是哪一类 |
|---|---:|---|
| `report/known_issues.md` | 60 | `build/rNN_*.txt` 逐轮读数件 |
| `report/optimization_log.md` | 58 | 同上 |
| `report/40-optimization.md` | 56 | `build/rNN_gates.txt` 逐轮门禁件 |
| `report/50-results.md` | 36 | `rNN_gates.txt` |
| `report/perf_report.md` | 28 | `rNN_*.txt`、`r87_*.rpt` |
| `report/repro-check.md` | 27 | `r116_bit_cycle.sh`、`r119_window_check.mjs`、`r118_build_console.txt` |
| `report/comparison-notes.md` | 21 | `rNN_gates.txt` |
| `report/measurements.md` | 19 | `r88_clock_util.rpt`、`r94_*.txt`、`r96_gates.txt` |
| `report/60-failure-analysis.md` | 12 | `r119_window_check.mjs`、`cmd_overflow_probe.sh` |
| `report/llm_collab.md` | 10 | `r88_gates_naive/partial.txt`、`r94/r95_*_ce.sh` |
| `report/timing_global.md` | 9 | `r113_roster_refanout.sh`、`r114_replication_ab.sh`、`r117_a1_read.sh` |
| `report/05-timing.md` | 9 | `r117_verdict_declined.txt`、`r118_gates_final.txt`、`r118_verdict.txt` |
| `report/claims-vs-evidence.md` | 7 | 各轮 `rNN_*.txt` |
| `README.md` | 6 | `r118_build_console.txt`、`r118_gates.txt`、`r118_gates_final.txt`、`r75_gates.txt`、`evidence/r121_*.txt` |
| `README_EN.md` | 6 | 同 `README.md` 的英文章 |
| `report/70-reproduce.md` | 6 | `r119_window_check.mjs`、`check_io_timing_coverage.py` |
| `report/08-limits.md` | 6 | `r105_tb_head_rot_displace.txt`、`r113_powup_rejudge.txt` |
| `report/90-open-items.md` | 6 | `r104_board_ping.txt`、`r120_src_map.mjs` |
| `report/acceptance-recipes.md` | 6 | `r95_batt_*.txt`、`r95_eye_park.txt` |
| `report/unattended.md` | 5 | `r120_rotate_skill_refs.mjs`、`r120_src_map.mjs` |
| `report/commands.md` | 4 | `probe_split100_old.txt`、`probe_split100b_old.txt` |
| `board/README.md` | 2 | `build/r88_jtag_scan.txt`、`build/r104_board_verify_console.txt` |
| `report/06-validation.md`、`report/demo_script.md` | 各 2 | — |
| `report/submission-package.md`、`report/run-queue.md`、`report/src-map.md`、`report/submission-checklist.md` | 各 1 | `r120_src_map.mjs` |
| **合计** | **407** | |

**每处改法的三条规则**（不要再逐条问）：

1. 该轮的**结论仍然要念** ⇒ 把 `build/rNN_x.txt` 换成同一条结论在 `build/evidence/` 里的对应件（`build/evidence/` 整目录留）；找不到对应件就写"读数件已随 rNN 轮次清理，复现命令是 `bash build/gates.sh`"。
2. 那句只是"当时那一步的现场" ⇒ **删掉路径 token，保留句子并改成过去式**，不写"已删除"。参照 `doc_currency_check.mjs:507` 的 `report/log/overnight_log.md` 那一支 fixture 的口径：退役件要明写"当时存在、现已删"。
3. 不许为了消红在同一条行里塞"不随包/本地留档" —— 件是真没了，那句话就成了 `:188-201` 那条豁免被买通的反例（脚本作者自己写了"买通它的唯一办法是当着读者写下这东西不随包，而那句话本身就是给人核对的真话"）。删了就删句，别贴豁免词。

批量跑法（红项自曝，不用手找）：

```bash
node src/host/doc_currency_check.mjs 2>&1 | grep 'D4c 点名的凭据盘上没有'
node src/host/doc_currency_check.mjs 2>&1 | grep 'D2 点名的目录盘上没有'
node src/host/doc_currency_check.mjs 2>&1 | grep 'D4a 点名的文档盘上没有'
```

### D5 行号锚点（另一把会红的尺子）

`src/host/line_cite_check.mjs` 判红之一是"引的文件不在树里"。它的扫描面是**仓库根往下所有 `.md`，只排除 `report/log/` 与 `report/study/`**（`:35-39`、`:51-69`），所以 `build/*.md`、`data/*.md`、**以及没入库的 `docs/course/*.md` 与 `docs/walkthrough/*.md` 都在射程里**（实测：D5 扫 246 份文档，被引且存在的 `build/` 代码件 42 支，其中 18 支是 `rNN_*` 一次性脚本）。

删这 18 支要同批改的锚点（实测出处）：

| 被删脚本 | 锚点在哪 | 改法 |
|---|---|---|
| `r108_stage2.sh` `r109_stage2.sh` `r110_apply_cuts.sh` `r113_after_chain_experiments.sh` `r113_after_mf_uncertainty.sh` `r113_chain2.sh` `r113_roster_refanout.sh` `r113_step5_rotate.sh` `r114_replication_ab.sh` `r115_c2_verdict.sh` `r115_fanout_ab.sh` `r116_chain.sh` `r118_chain.sh` | `build/probe-guard.md` 各节（`:13/16/18/22/23/27/29/35/43/65`） | `build/probe-guard.md` 整份退役（它讲的是"各轮滚档脚本缺哪五条自探测"，结论已在 `report/60-failure-analysis.md`）；`report/run-queue.md:25` 那条指向它的行一起删 |
| `r90_phase2.sh` `r94_bench_chain.sh` | `build/artifacts/README.md:65`、`build/runs/ledger.md:68` | 删 `build/artifacts/README.md`（目录里只有这一支说明件）；`build/runs/ledger.md` 是台账，把点名改成"当时的脚本已随 rNN 清理" |
| `r116_bit_cycle.sh` | `report/repro-check.md:4/106/112/119/128/219`、`report/reproduce/README.md:12`、`board/firmware/system.bit.md:22`；**另有 `report/repro-check.md:294` 把它列进 `bash -n` 的 10 支分母** | 这是唯一"删了会让一条已声明的复现演练缩分母"的一支。二选一：(a) 留它（它是 A 档，且 `deliver_spec_check.mjs:154/179` 把 `.sh` 计入卫生射程）；(b) 删它并把 `report/repro-check.md:294` 的分母从 10 改 9、同批删 `board/firmware/system.bit.md`（B.5 已列） |
| `r100_chain.sh` | `docs/course/01-一条命令到位流-Tcl构建.md:26`（**未入库**） | `docs/` 不在交付树里但在这台机器上会被 D5 扫到 ⇒ 同批改 `docs/`，或接受"本机 D5 红、包内绿"并在 `report/repro-check.md` 里写明这条差异 |
| `r115_roster_build.py` | `report/40-optimization.md:124/243`，且 `board/compare/roster-diff-selfcheck.txt:1` 的 `# CMD:` 行写的是 `python build/r115_roster_build.py --self` | 删脚本 ⇒ 那份 `board/compare/*.txt` 的复跑入口失效；连 `board/compare/roster-*` 五支一起删，或留脚本 |
| `r119_window_check.mjs` | `report/40-optimization.md:131/243`、`report/60-failure-analysis.md:168/585`、`report/70-reproduce.md:129`（14 处） | 这支是"输入窗自校验工具"，**建议留并改名 `build/window_check.mjs`**（去掉轮次前缀），同批改 14 处 + `check_repo_consistency.mjs:365` 的 `build/evidence/r119_window_check.txt` 是**读数件**不是脚本，不受改名影响 |

跑法：`node src/host/line_cite_check.mjs 2>&1 | tail -5`（末行 `D5: CLEAN` 才算绿；硬错计数在 `:465` 那行打印）。

## A.6 `build/README.md` 的收口

`build/README.md` 现在的"一、脚本对照"那张表（`:11-28`）形状是对的，`deliver_spec_check.mjs:348` 也判它含对照表。要动的只有三处：

* `:3` 那句"报告归档在 `build/report/`；`build/evidence/`、`build/frozen_*/` 与带历史轮次号的那批 `.txt` 是一次次留档，不随包" —— 删完之后这句话变成假话（`build/evidence/` 随包、`frozen_*` 大多已不在），改成实测后的三行：入口 TCL 清单、`build/report/` 7 支、`build/evidence/` 967 支留作凭据。
* `:4` 的 `build/r118_build_console.txt:1-4`、`:39` 的 `build/log_r45_bdonly4.txt` —— 前者留件所以不改；后者不在 A.4 名单里（实测它是"其它顶层 .txt"档），**要么留要么改这行**。
* 新增一节"各脚本构建什么"的收尾表：把 `build/tcl/` 的 96 支按「入口 / 只读查询 / 探针 / 滚档」四类各给一行数量（`build/tcl/README.md` 已有名单，直接引用它并念数量）。

目标体积（实测推算）：入口 TCL 7 支 + 尺子与被读物 + `build/evidence/` + `build/report/` + `build/tcl/` + `build/sim/` + 约 30 支现役脚本 ≈ **1 200 支 / 26 MB**（现在 3 117 支 / 107 MB）。

---

# B. `board/`

## B.1 现状（实测）

盘上 79 支 / 535 KB（跟踪 76、ignored 3），**零工程件**（见第 0 节）。按类：

| 类 | 支数 | 字节 | 处置 |
|---|---:|---:|---|
| 叙述/台账 `.md`（`README.md` `acceptance.md` `hardware_setup.md` `signoff.md` `signoff-questions.md` `raw-vs-golden.md` `verify_r87.md` `ddr_churn_r33_pair.md` `HANDS_ON.md`） | 9 | 163.1 KB | 见 B.5 |
| 真运行脚本（4 支 `.tcl` + 3 支 `.ps1` + 1 支 `.mjs`） | 8 | 15.3 KB | 全留 |
| 命令清单（`cmd_battery_v81.txt` `cmd_overflow_probe.sh` `cmd_prime_demo.txt` `cmd_r84_osd.txt`） | 4 | 9.5 KB | 前两支留（被 20/8 处点名），后两支 **0 字节 / 39 字节且 0 处引用** ⇒ 删 |
| 运行时捕获（`uart_capture.txt` `uart_script_capture.txt` `demo_rehearsal.txt` `card_v2_preview.png`） | 4 | 26.6 KB | `uart_*.txt` 被 `.gitignore:135-136` 挡 ⇒ 不在库；`demo_rehearsal.txt`、`card_v2_preview.png` 在库 |
| 摘要卡（`firmware/system.bit.md` `system.xsa.md` `ps_app.elf.md`） | 3 | 21.0 KB | **删**（用户点名"不是让你放什么 xsa/bit 的 md 文件"） |
| 条件卡（`conditions/*` 4 支） | 4 | 33.1 KB | 见 B.5 |
| 索引件（`captures/index.md` `logs/index.md` `compare/index.md`） | 3 | 23.5 KB | 合并成一支 `evidence/index.md` |
| 实测输出（`evidence_r29/` 17 支含 1 支 README、`evidence_r41/` 14 支、`compare/` 14 支含 index.md） | 45 | 93.7 KB（三个目录字节和） | 数据件全留、改名进 `evidence/`；三份 index/README 合成一支 |

## B.2 目标形状（三类，含每条一行为什么留）

```
board/
  README.md                         ← 重写，只写"有什么 / 落在哪个文件 / 上板四步 / 判据指针"（B.6）
  project/                          ← (1) 上板工程，见 B.3 两个方案
    vivado/                         ← 工程文本（方案 A）或整树（方案 B）
    vitis/                          ← 平台文本 +（方案 B 才有）BSP
  boot27c.tcl                       ← 真运行脚本：connect→rst -system→下载→释放，三步链的"一把过"版本
  pswhy.tcl                         ← 真运行脚本：板子没反应时读 UndefinedExceptionAddr/PrefetchAbortAddr（0x11488/0x1148c），别猜
  rdbck.tcl                         ← 真运行脚本：mrd GPIO_0(0x41200000)，确认控制字落板
  rdddr.tcl                         ← 真运行脚本：GPIO 一个字 + DDR 头 8 个字，用来分"控制字没写进去"和"数据没落内存"
  serial_bytes.ps1                  ← 串口按字节捕获（`.gitignore:150` 明写它的输出不入库，件本身入库）
  uart_cap_once.ps1                 ← 串口一次捕获；report/* 里 34 处指它
  uart_cmd_script.ps1               ← 把 cmd 清单逐条灌进 COM6；`cmd_battery_v81.txt` 的头两行就写着"发送器：board/uart_cmd_script.ps1"
  cmd_battery_v81.txt               ← 105 条串口命令的清单本体（139 行）；`report/commands.md:97`、`demo_script.md:19`、`host_guide.md:112` 共 20 处指它
  cmd_overflow_probe.sh             ← ISSUES #167 `cmd_buf` 越界一字节的两端夹逼探针；`60-failure-analysis.md:94/98/549`、`src/ps/main.c` 指它
  ddr_churn_probe.mjs               ← DDR 翻帧探针；13 处指它
  evidence/
    index.md                        ← 唯一一份索引，取代 captures/logs/compare 三份 index.md
    r29/                            ← 16 支：SD 挂载/播放/仲裁交接的现场回读（`arb_sd_with_cable_in.txt` 是"网线插着时 SD 能不能读"的反面凭据）
    r41/                            ← 14 支：`node src/host/metrics.mjs --out board/evidence_r41` 的产物（`metrics.mjs:10/164` 的默认输出目录形状），clean30/drop200/drop2000/nopause60/nopause120/soak300/soak300b 七对 json+md
    compare/                        ← 13 支：每份件头两行 `# CMD:` / `# RUN_AT:` 就是复跑入口（实测 `temp-formula-check.txt:1` = `node src/host/temp_formula_check.mjs`、`metric-recheck.txt:1` = `node src/host/metric_recheck.mjs`）
  verify_r87.md                     ← 全功能上板验收表；`data/metrics.csv` 6 行、`report/08-limits.md`、`report/50-results.md` 共 14 处指它（R10）
  hardware_setup.md                 ← 线材/供电/跳线这一格没有别的件兜着；`report/70-reproduce.md:54/106/175` 等 14 处指它
  acceptance.md                     ← 见 B.5（它是 C11 候选件、且被 98 处指）
```

`build/` 与 `board/` 的分界（写进 `board/README.md`，别再让评审猜）：
**上板动作的脚本在 `build/tcl/`**（`scan_jtag.tcl` `ps_jtag_boot.tcl` `program_pl.tcl` `ps_app_reload.tcl`——`board/README.md:49-55` 那四条命令本来就指它们），`board/` 只放"到板子跟前才用得着"的小工具与实测输出。

## B.3 (1) Vivado / Vitis 工程进仓的形状：两个方案的实测

### 实测底数

`vivado_system/`（`.gitignore:2` 整树挡，跟踪 0 支）：

| 目录 | `du -sh` | 说明 |
|---|---:|---|
| `zynq_video_sys.gen/` | 36 M | IP 输出产品（`sources_1/bd/design_1/**` 的 OOC xdc、`_ooc.xdc` 逐 IP 一份）。`.runs` 也在跑时又长了一份 |
| `zynq_video_sys.runs/` | 30 M | `impl_1` 24 M、`synth_1` 3.7 M、6 支 OOC `*_synth_1` 各 0.25–0.46 M |
| `zynq_video_sys.cache/` | 3.1 M | 综合缓存 |
| `zynq_video_sys.srcs/` | 652 K | **工程文本**：`design_1.bd`(73 272 B) + `design_1.bda`(8 678 B) + 8 支 `.xci`（最大 `design_1_axi_gp0_ic_imp_xbar_0.xci` 228 892 B、`processing_system7_0_0.xci` 155 476 B） |
| `zynq_video_sys.xpr` | 52 K（字节 34 248） | 工程文件 |
| `zynq_video_sys.hw/` | 1 K | — |
| `zynq_video_sys.ip_user_files/` | 0 | 空 |
| `.sim` / `.data` | **不存在** | 这条树今天没有这两档，别按旧数估 |
| 合计 | 69 M（一次构建中间态）；另一时刻字节和 113.50 M / 404 支 | 移动目标，见 0.3 |

`vitis/`（`.gitignore:8` 写的是 `VITIS/`，实测 `git check-ignore -v vitis` 命中 `.gitignore:8` ⇒ 这台机器 `core.ignorecase=true` 才挡得住；跟踪 0 支）：

| 目录 | 支数 | 字节 | 说明 |
|---|---:|---:|---|
| `platform/zynq_fsbl/` | 1 105 | 18.59 M | 其中 `zynq_fsbl_bsp/` 1 027 支 15.79 M、`build/` 37 支 2.02 M |
| `platform/ps7_cortexa9_0/` | 983 | 13.10 M | **`standalone_ps7_cortexa9_0/bsp` 实测 16 M（du）**——`build/ps_app.mjs` 里 `const BSP` 那一行的默认 `PS_BSP` 就指这里（⇒ 它进不进仓，决定 clone 之后能不能重编 `ps_app.elf`） |
| `platform/export/` | 140 | 10.00 M | 导出的 sysdef/`fsbl.elf`(582 964 B)/库 |
| `platform/hw/` | 37 | 6.76 M | 其中 `sdt/` 36 支 5.96 M；`hw/system.xsa` ≈ 0.8 M |
| `platform/resources/` | 3 | ~0 | — |
| `_ide/` | 10 | 0.13 M | 工作区壳（`.peers.ini`、`logs/`） |
| `platform/vitis-comp.json` | 1 | 2 122 B | **含绝对机器路径**：`configuration.xsa` 的值是"本机仓库根 + `/build/system.xsa`"展开成的绝对路径串，`configuration.xsaPathInPlatform` = `platform/hw/system.xsa` |
| 合计 | 2 281 | 48.59 M（du 54 M） | |

### 方案 A：只进工程文本（推荐）

进：`vivado_system/zynq_video_sys.xpr` + `vivado_system/zynq_video_sys.srcs/**` + `vitis/platform/vitis-comp.json` + `vitis/platform/resources/**`。
实测体积 **11 支 / 0.66 MB**（Vivado 侧），Vitis 侧 json + resources ≈ 4 支 / 12 KB。

* 代价/注意：`.gitignore:2 vivado_system/` 与 `:8 VITIS/` 要先加例外，照 `:26-27` 已有的写法：
  `!vivado_system/zynq_video_sys.xpr`、`!vivado_system/zynq_video_sys.srcs/**`、`!vitis/platform/vitis-comp.json`、`!vitis/platform/resources/**`。
* `vitis-comp.json` 里的绝对路径必须在入库前改写成相对 `hw/system.xsa`，否则评审 clone 到别的机器上平台直接指不回。
* `.xci` 里带 IP 的 `PROJECT_ID` 与本机构件版本，换 Vivado 小版本会 `upgrade_ip` —— 这条要在 `board/README.md` 写明，别让人以为 `.xci` 是免检的。

### 方案 B：整目录进（不推荐，但把数摆出来）

进整个 `vivado_system/` + `vitis/`：实测 **2 281 + 约 400 支 / 49–114 MB**（视构建跑到哪一步），其中 `.gen`+`.runs`+`.cache` 占 69 M 里的 69 M 中 69 M 的绝大部分（36+30+3.1 = 69.1 M，也就是说除了 `.srcs` 的 0.65 M 全是可再生的）。
再加两条硬约束：`build/frozen_*`/`evidence_r*`/`isolated_*` 的二进制被 `.gitignore:79-81/125-127/142-145` 一条一条挡过，说明这个仓的既定口径就是"二进制不入库、报告入库"；把 24 M 的 `impl_1` 塞进去会自相矛盾。C0-4（`deliver_spec_check.mjs:57`）还会把新增的顶层目录当"多余"判红——好在 `vivado_system/`、`vitis/` 一旦入库就会成为顶层目录，**必须同步把 `allowDirs` 加上这两项，或者把工程放进 `board/project/` 里**（推荐后者：不动 C0-4 名单）。

### 一键重生（两案都要写进 `board/README.md`）

```bash
# Vivado 工程 + BD + 综合 + 实现 + 位流 + XSA + 7 份报告，一把跑完（约 20 分钟，见 report/build.md）
vivado -mode batch -source build/tcl/build_system_axigpio.tcl
#   实测入口是 build/tcl/build_system_axigpio.tcl:21 的 create_project zynq_video_sys vivado_system -part xc7z020clg484-2 -force
#   ⇒ 工程壳（.xpr/.srcs/.gen/.runs）本来就能从这一支脚本从零长出来，这是方案 A 只进文本也站得住的依据
# 只要 BD 与地址回读（19 秒）：
vivado -mode batch -source build/tcl/build_system_axigpio.tcl -tclargs bd_only
# 位流与 XSA 的归档落点：
vivado -mode batch -source build/gen_bit.tcl   # gen_bit.tcl:25-26 现写 board/system.xsa、board/system.bit
#   ⚠ 这一条的落点就是 B.3(2) 要裁决的那件事：选 (a) 则 board/ 里真的长出这两件（并要在库里）；
#      选 (b) 则先把 gen_bit.tcl:12-13 的默认目录改成 build、并把 :2/:4 的注释同批改口，
#      否则评审照这条命令跑一次就在 board/ 造出两个未跟踪的二进制（gen_bit.tcl:29-30 还会打印 ARTIFACT_MISSING 之前的成功假象）
# 身份核对（实测三处一致，重写 README 时指这一组，别另立第四处）：
#   build/evidence/r118_board/board_now.txt:1  板上现在 = r118（含刷入时刻与 board_verify 结果，254 B）
#   build/r118_gates.txt:5  ps_app.elf md5=d0b07f84a068（同一段还有 system.bit 的 cd04907e1369，即 D1b 的基准）
#   board/README.md:6-7     念的就是上面这两处
# 重出 7 份报告到 build/report/：
vivado -mode batch -source build/report.tcl
# PS 应用 ELF（需要 Vitis 的 arm-none-eabi-gcc + 一个已 generate 的平台）：
node build/ps_app.mjs                                  # PS_CC / PS_BSP 可覆盖，默认 BSP = vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp
```

**必须诚实写进去的一条（本轮实测把旧说法证伪了，别再照抄 `build/README.md:53-54`）**：
`build/ps_app.mjs` **能**在这台机器上重编 ELF —— 编译器不在 PATH 里（`which arm-none-eabi-gcc` 无命中），但在 Vitis 安装树里（`…/Vitis/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe`，自述 `arm-xilinx-eabi-gcc.exe (GCC) 13.3.0`）。实测记录与两个入口坑：

* `build/evidence/1005_ps_app_rebuild.txt`（879 B，实测在册）给了能跑通的三条：显式 `PS_CC=<编译器绝对路径>`、`PS_BSP=<仓库根>/vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp`（**必须绝对路径**）、`node build/ps_app.mjs`。
* `build/ps_app.mjs:10` 写"默认取 2025.2.1 的安装位置"，而 `:26` 实际是 `process.env.PS_CC || ''` —— **没有默认值**。这句文件头是失实的，重写 `board/README.md` 时不要沿用它；改 `build/ps_app.mjs` 时二选一（补默认值或改注释），别留两处漂。
* 重建那颗 `md5=4ed58740785c…`，随包/在板那颗 `md5=d0b07f84a068…`（实测 `md5sum build/ps_app.elf` = 后者）。**两颗不同** ⇒ 板上已复验的行为只绑定 `d0b07f84` 那颗；重建件要先上板 `board_verify` 复验才谈得上采纳。这条口径要在 `board/README.md` 明写。
* 对"进仓形状"的真实约束因此不是"本机编不出来"，而是：**方案 A 下 `vitis/` 那 16 MB 的 BSP 不入库 ⇒ clone 之后要重做 `build/ps_app.mjs:14-17` 写的那一次手工 New Platform**（Vitis → New → Platform → 选 `build/system.xsa` → BSP 勾 `uartps/xsdps/xgpiops` → Generate）。要么接受它作为一条标注过的不可复现步骤，要么按方案 B 把 `vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp`（16 M / 983 支，实测 du）进仓。
* `build/README.md:53`、`board/firmware/ps_app.elf.md`、`report/known-limitations.md`、`report/known_issues.md` 这四处仍留着"本机没有编译器/不能重编"的旧口径 —— B.5 删 `board/firmware/ps_app.elf.md` 会带走其中一处，另外三处要在同一次改动里跟着改口（`src/ps/README.md:37` 是第五处）。

### `gen_bit.tcl` 往 `board/` 写东西这件事（用户点名要处理的矛盾）

实测：`build/gen_bit.tcl:4` 声明产出 `board/system.bit`、`board/system.xsa`；`:25` `write_hw_platform … -file board/system.xsa`；`:26` `file copy … board/system.bit`；`:29-30` 缺任何一份就 `ARTIFACT_MISSING` 并置 `ok 0`。
但 `git log --all -- board/system.bit board/system.xsa board/ps_app.elf` **一条提交都没有**，`git check-ignore` 也不挡这三个名字 ⇒ 现状是三件事互相不打照面："脚本往 `board/` 写" + "`.gitignore` 没挡" + "`board/` 里从来没有过"。（第四件"`board/README.md:18` 说它被挡了"已经由并行会话改口成"这三份是随仓库入库的"，见第 0 节的 HEAD 警告——裁决这一条时别再按旧文处理。）
三选一，必须选一个写死：

* **(a) 兑现脚本**：`board/system.bit`、`board/system.xsa`、`board/ps_app.elf` 三件真进仓（2.2 MB + 0.83 MB + 0.33 MB = 3.4 MB），并把 `board/README.md:18` 那一行从"在 `build/`"改成"在 `board/`（与 `build/` 同哈希）"——这行刚被并行会话改口过，改之前先 `awk 'NR==18' board/README.md` 取现文（实测现文点名的是 `build/` 那三件）。表面上最贴"把工程放进去"的字面读法。
* **(b) 收口在 `build/`**：`build/gen_bit.tcl:12-13` 的默认目录从 `board` 改成 `build`（`VP_BIT_DIR` 已经支持），`board/` 不放二进制 ⇒ 脚本声明、`.gitignore`、盘上形状三者对齐；`board/README.md:18` **不用改**（它已经写着三件在 `build/`），只需把 `build/gen_bit.tcl:2/:4` 的两处"归档到 board/"改成"归档到 build/"。
* **(c) 保持现状**：不可选——`gen_bit.tcl:29-30` 那两条 `ARTIFACT_MISSING` 判据在指向一个既不存在也不被忽略的落点，评审照 `README.md:38` 跑一次就会在 `board/` 长出两个未跟踪的二进制（`git status` 立刻脏）。

推荐 **(b)**：`build/system.bit|.xsa|ps_app.elf` 已经在库、md5 已经在 `build/r118_gates.txt:5` 与 `build/r118_gates_final.txt:5` 的"身份"段里被戳（D1b 基准取的就是这块 bit 的 md5），再加一份副本进 `board/` 就是两处身份、一处漂移。`board/project/` 放工程文本就够。

## B.4 要保留的运行脚本与实测输出（已在 B.2 逐条给了理由，此处只列不可动的三件）

* `board/verify_r87.md` —— `data/metrics.csv` 6 行的证据列（R10）。
* `board/cmd_battery_v81.txt` —— `src/host/uart_cmd_check.mjs` 的输入清单（文件头 `:2` 自己写了发送器与判据）。
* `board/compare/*.txt` 的 13 支 —— 每支都带 `# CMD:` 复跑入口；**唯一例外**：`roster-diff-selfcheck.txt:1` 指 `build/r115_roster_build.py`，`roster-diff-baseline-vs-r116e1.txt`、`roster-golden_compare-crosscheck.txt` 同理 ⇒ 若 A.3 删了 `r115_roster_build.py`，这三支要么一起删，要么把 `# CMD:` 改成新入口。

## B.5 删除清单（逐文件）

**必删（用户点名 + 零引用或引用可随手消）**

| 文件 | 字节 | 为什么删 | 删之前要改 |
|---|---:|---|---|
| `board/firmware/system.bit.md` | 7.2 K | "不是让你放什么 xsa/bit 的 md 文件"——它是一份把 `git diff --stat` 抄进去的来源卡，本体二进制在 `build/` | `report/90-open-items.md:231` 一处（实测 `grep -n 'board/firmware' board/README.md` 现在**无命中**——那两处同行引用已随 `:18` 改口一起消掉了，删卡前再 `grep -rn 'board/firmware'` 复核一次）；`docs/walkthrough/glossary.md`、`docs/walkthrough/prerequisites.md`（未入库，见 0.2 的射程说明） |
| `board/firmware/system.xsa.md` | 6.2 K | 同上 | `report/90-open-items.md:232` |
| `board/firmware/ps_app.elf.md` | 7.5 K | 同上；另：它记的"文件时间与校验和"正是 `build/README.md:54` 那条被证伪口径的落点之一（B.3(1) 末段列了五处旧口径） | `report/90-open-items.md:230` |
| `board/cmd_prime_demo.txt` | 30 B | 4 行命令、0 处引用，且 `cmd_battery_v81.txt` 已含同样四条 | 无 |
| `board/cmd_r84_osd.txt` | 39 B | 6 行、0 处引用 | 无 |
| `board/demo_rehearsal.txt` | 0.6 K | 演练草稿；正文已被 `report/demo_script.md` 顶替；只被 `src/host/demo_cmds.mjs`（生成它的脚本）与 `report/study/` 提 | `src/host/demo_cmds.mjs` 里那句输出路径改成 `board/evidence/demo_rehearsal.txt` 或直接删默认值 |
| `board/card_v2_preview.png` | 5.5 K | 一张预览图，无引用；图卡本体的判据在 `report/` | 无 |
| `board/ddr_churn_r33_pair.md` | 3.3 K | 一次配对的叙述件，原始件在 `data/measured/` 与 `build/evidence/` | 无（0 处引用实测） |
| `board/captures/index.md`、`board/logs/index.md`、`board/compare/index.md` | 6.2 + 10.5 + 9.7 K | 三份"索引件"合成一份 `board/evidence/index.md` | `report/90-open-items.md:224/225/226/234`、`report/build-notes.md:5`、`report/README.md:117` 共 6 处（D4a，`.md` 指路判红面） |
| `board/conditions/card-*.md`（4 支） | 33.1 K | 采集条件卡：内容在 `board/README.md` §2 的分步表与 `hardware_setup.md` 里已经有了 | `report/90-open-items.md:227/228/229` 三处 |
| `board/raw-vs-golden.md` | 20.2 K | 讲的是"实测与 `data/golden/` 参考结果比对这一格现在依然是 0 行"——这条结论应进 `report/known-limitations.md`，不该住在交付目录 | `report/90-open-items.md:235/236`、`report/run-queue.md:29` 三处 |
| `board/signoff-questions.md` | 10.1 K | 问队伍的清单，与 `report/questions-for-team.md` 重复 | `report/90-open-items.md:237`、`report/acceptance-recipes.md:135/175`、`report/measurements.md:142/178` 五处 |

**要判断才能删（引用最重的两支）**

| 文件 | 字节 | 实测被交付文档点名 | 删的代价 |
|---|---:|---:|---|
| `board/acceptance.md` | 24.8 K | **98 处**（`board/README.md:99` + `report/03-algorithm.md:81` + `report/06-validation.md:11/148/151/159` + …）；同时是 `check_repo_consistency.mjs:373` 的 C11 候选件（R5） | 删它 = 改 98 处 + 换 C11 候选件。用户的"全删了重新写"在这一支上应读成**重写**：把它压成一页"要人眼确认的"表（`board/README.md:97-99` 已有那三条），其余 21 K 的过程叙述进 `report/log/`；C11 候选件按 R5 换成 `board/evidence/index.md` |
| `board/signoff.md` | 51.2 K | **29 处**（`report/90-open-items.md:37/237/238`、`report/acceptance-recipes.md:135/173`、`report/measurements.md:…`、`data/README.md:60`）；`data/README.md:60` 那句"golden/ 与屏上照片的比对仍是人工眼看（`board/signoff.md` 的相应行由人签）"是交付文档引用，删了判红 | 同上：把签字表压成 `board/README.md` 的一节（评审只要看得见"哪一格由人签、签的判据是什么"），51 K 的问答过程进 `report/log/`；改 29 处 |

`board/HANDS_ON.md`（17.8 K）已被 `.gitignore:154` 挡住、不在库，且 `report/README.md` 提它一次 —— 那条提法在库内会指到一个不存在的件（`.md` 类 D4a 判红）。**顺手把 `report/README.md` 那一行删掉**。

## B.6 `board/README.md` 重写要点

只写四块，每块不超过一屏；**任何一句都要能落到盘上一个文件**（用户："README 目录都不知道在写什么"）。

1. **这块目录里有什么**——三张表，对应 B.2 的三类：
   * 上板工程：`board/project/vivado/`（列 `.xpr` + `.srcs` 的实际支数与字节，实测 11 支 / 0.66 MB）、`board/project/vitis/`（json + resources，并写明 BSP 不入库 ⇒ 重编 ELF 的那一次手工 New Platform 是不可复现步骤，指 `build/ps_app.mjs:14-17`）。
   * 运行脚本：`boot27c.tcl` `pswhy.tcl` `rdbck.tcl` `rdddr.tcl` `serial_bytes.ps1` `uart_cap_once.ps1` `uart_cmd_script.ps1` `cmd_battery_v81.txt` `cmd_overflow_probe.sh` `ddr_churn_probe.mjs` —— 每支一行"什么时候用它"（例：`pswhy.tcl` = 板子没反应时先读 `0x11488/0x1148c`，别猜）。
   * 实测输出：`evidence/r29/`、`evidence/r41/`、`evidence/compare/` 各一行 + 复跑命令（`compare/*` 的复跑命令就在件头 `# CMD:` 那一行，指出来即可，不要抄进 README 造成两处漂）。
2. **上板四步命令**——沿用现有 `:47-56` 那一段（实测四支 `.tcl` 都在 `build/tcl/` 且都在库），只补一条 `board/` 侧的读回工具行（`rdddr.tcl`）。`:18` 那一行**已经改口成"这三份是随仓库入库的"，不要再抄回"被 `.gitignore` 挡住"的老话**；按 B.3 选 (b) 之后还要补上身份的具体落点：`build/r118_gates.txt:5` 的 `ps_app.elf md5=d0b07f84a068`、同件"身份"段的 `system.bit md5=cd04907e1369`（实测 D1b 就是拿这两个值当基准），并写明"重编出来的 ELF 是另一颗（`4ed58740785c…`，未上板），别把重建件当成板上那颗"。
3. **判据指针**——只给去处不给内容，每条一行：发布前检查 = `bash build/gates.sh` 的末行（不复制条数，避免 D1c 那句"门禁 N 项 X 绿 / Y 红"对不上基准件）；逐轮身份 = `build/r118_gates.txt`；全绿的那一版 = `build/r75_gates.txt`；指标表 = `data/metrics.csv` 第 N 行；已知未修 = `report/known_issues.md`。**现在的 `:20-39` 那张三时钟域表和 `:29-34` 那段 hold 口径叙述要删**：同一组数已经写在 `README.md:64-66` 和 `report/measurements.md`，两处并写就是漂移源（`:94` 那一行自己就与 `README.md:64` 不一致——前者写 WNS 0.720 ns / WHS 0.033 ns / 失败端点 0/50890，后者写 0.739 / 0.052 / 0/51135，实测两支都点名同一份 `build/timing_summary.rpt`）。重写时把这句留作唯一口径：读数以 `bash build/gates.sh` 打印的那一行为准。
4. **不许出现的三类内容**：`.md` 摘要卡（B.5 已删）、与 `report/` 重复的叙述台账、以及任何"已验证/已改"而没有点名盘上件的说法。

---

# C. `data/`

## C.1 现状（实测）

盘上 45 支 / 5.7 MB（跟踪 40 / 3.98 MB）。四类字节：`inputs/` 8 支 1.90 MB、`golden/` 14 支 1.40 MB、`measured/` 盘上 20 支 2.26 MB（跟踪 15 支 0.65 MB）、`generated/` 1 支 0.014 MB，另有 `README.md` 0.005 MB + `metrics.csv` 0.009 MB。

**"测试数据与参考结果"这一句的实际兑现度**（用户："你又在放些什么"）：

* `inputs/` —— 真数据。8 支全部由 `data/generated/gen_inputs.mjs:131-138` 定义，一条命令重生（`node data/generated/gen_inputs.mjs --write`）。但**实测只有 1 支被代码读过**：`wordid_512x300.rgb565`（`src/host/one_click_test.mjs`、`.py`）。`grep -rl 'data/inputs' sim` = **0** ⇒ `data/README.md:12` 那句"台架与主机脚本按文件名点用"里"台架"这一半没有兑现。
* `golden/` —— 14 支 = 11 张 PNG + 1 支 `frame_640x360.mem` + `README.md` + `manifest.md`。**没有任何 `.v/.mjs/.sh/.py` 读它**（实测 `grep -rn data/golden src sim build --include='*.v' --include='*.mjs' --include='*.sh' --include='*.py'` 只命中 `make_submission.sh:112` 的打包形状规则和两支一次性迁移脚本 `r121_rename_scope.mjs`、`r122_ps_relocate.mjs`）。`golden/README.md:4-6` 自己承认了这一点。`frame_640x360.mem` 1.32 MB，640×360 而设计是 512×300，`golden/README.md:17/25-27` 自称"孤儿"。
* `measured/` —— 20 支里 **4 支是 `.md` 判读文档**（`board_measure_r06_r07.md`、`r08.md`、`r09.md` + `README.md`）、`arb_handover_last.json` 128 K 是**运行台账**（`src/host/arb_handover_test.mjs:446` 每次 `appendFileSync` 往上追加）、`arb_uart.txt` 0.2 K 含乱码、`lane30_watch.out`+`.tcl` 是一对、`health_*.out` 4 支已被 `.gitignore:68` 挡、`ddr_dump.out` 1.61 MB 已被 `.gitignore:58` 挡。真正"被代码读的"只有 `arb_handover_last.json`（被 `arb_handover_test.mjs` 自己写、`board_verify.sh:234-236` 复制）。
* `generated/` —— 一支脚本，`data/README.md:15` 自己写"（不是数据；放这里是因为它和 `inputs/` 同源同版本）"。
* `metrics.csv` —— 29 行（1 表头 + 28）。`grep -c data/ data/metrics.csv` = **0**：证据列一条都不指 `data/` 里的东西。它指的 6 行是 `board/verify_r87.md`，其余指 `build/*.rpt`、`build/evidence/*`、`report/perf_report.md`、`src/constraints/`、`build/gates.sh`、`build/sim/mut_control.sh`、`build/tb_v98_report.txt`。⇒ **"测试数据与参考结果"这一层的定位，跟全仓唯一那张数字表的证据链是断开的**，这才是用户那句"你又在放些什么"底下真正的问题。

## C.2 三列清单

### 删除

| 模式 / 文件 | 支数 | 字节 | 依据 |
|---|---:|---:|---|
| `data/measured/arb_handover_last.json` | 1 | 127.9 K | 运行台账，`arb_handover_test.mjs:446` 每次跑都 append；判据原件在 `build/evidence/`。删件 + 在 `.gitignore:60` 之后补一行 `data/measured/arb_handover_last.json` |
| `data/measured/arb_uart.txt` | 1 | 0.2 K | 含乱码的串口残片，0 处引用 |
| `data/measured/arb_r32_run1.txt`、`arb_gpio0.out` | 2 | 1.4 K | 0 处引用（`arb_gpio0.out` 0 B） |
| `data/measured/sender_during_sd.txt` | 1 | 4.0 K | E 档，0 处引用 |
| `data/measured/lane30_watch.out` + `lane30_watch.tcl` | 2 | 10.8 K | 一对；`.out` 是 `.tcl` 跑出来的现场，`src/host/lane30_watch.mjs` 才是工具。留 `.mjs`、删这两支 |
| `data/measured/ddr_dump_20260921_15fps.out.gz` | 1 | 460.9 K | `data/measured/README.md:5-6/19-22` 给了复跑链（`gunzip` + `node src/host/ddr_stale.mjs`），但 460 K 的原始 bank 回读不是"测试数据与参考结果"，属凭据 ⇒ 移 `build/evidence/` 或直接删（判读表已在 `README.md:8-15`，那张表本身要移进 `report/`，见下） |
| `data/golden/frame_640x360.mem` | 1 | 1 350 K | 640×360 与 512×300 不符、0 个读者。`golden/README.md:25-27` 自己给了二选一："接到 `video_sender.mjs` 上当测试数据，或者从提交包里去掉" ⇒ 走后者 |
| `data/measured/board_measure_r06_r07.md`、`r08.md`、`r09.md` | 3 | 24.3 K | **判读文档，不是数据**。移进 `report/measurements.md`（那里已经有同一批读数）或 `report/log/`。`r08.md` 属 A 档（被交付文档点名），移走要同批改指路；`r06_r07.md`、`r09.md` 属 C 档 |
| `data/inputs/`（可选）| — | — | **不删**：可重生不等于不该入库，`data/README.md:19-20` 的规则 1 写的正是"只放重跑一条命令就能得到同样的字节的那些" |

小计删除 **13 支 / 约 2.0 MB**（跟踪件口径）。

### 保留

| 文件 | 理由 |
|---|---|
| `data/README.md` | C0-4/C5 之外，`report/submission-checklist.md:16` 把"data/ 说明"列成第 8 项交付件；但**内容要改**（C.4） |
| `data/metrics.csv` | 全仓唯一数字表，被交付文档点名 180+ 处，C2 判它每行的证据路径存在 ⇒ 一支都不能少（`data/README.md:27` 的"一张表"规则） |
| `data/inputs/` 8 支 | `gen_inputs.mjs --write` 一键重生；`wordid_512x300.rgb565` 被 `one_click_test.{mjs,py}` 真读 |
| `data/generated/gen_inputs.mjs` | `inputs/` 的唯一生成器。留在 `data/` 与 `data/README.md:15` 的自认相冲 ⇒ 二选一：移到 `src/host/gen_inputs.mjs`（并改 `data/README.md:12/15`、`report/run-queue.md:31`、`report/submission-checklist.md` 三处指路），或在 README 里把"data/ 只放数据"改成"data/ 放数据与它自己的生成器"。**推荐移动**，因为 C 段之后 `data/` 就只剩数据 + 表 + 三个 README |
| `data/golden/README.md`、`data/golden/manifest.md` | 只要 `golden/` 里有 PNG，这两支就是"这张图能不能当参考"的判据说明（`report/08-limits.md:182`、`report/known_issues.md:860` 都引它） |
| `data/golden/*.png` 11 张 | 见 C.3 的判定 |
| `data/measured/README.md` | 只要 `measured/` 非空就留；删满之后（见 C.3）它可以直接删 |

### 先改引用（保留件 / 删除件都要动的行）

| 位置 | 现在写的 | 改成 |
|---|---|---|
| `README.md:21` | "data/ —— 测试数据与参考结果：`data/inputs/` 8 份输入序列、`data/golden/` 参考图、`data/metrics.csv` 第 1 行是表头、往下 28 行指标" | 按实测改：`data/ —— 输入向量与指标表：data/inputs/ 8 份（由 data/generated/gen_inputs.mjs --write 一键重生）、data/golden/ 11 张软件渲染参考图（**没有任何台架读它们**，判据见 data/golden/README.md）、data/measured/ 原始回读留档、data/metrics.csv 表头 1 行 + 指标 28 行`。`README_EN.md:17` 同改 |
| `data/README.md:12` | inputs 那一格"台架与主机脚本按文件名点用" | 改"由 `data/generated/gen_inputs.mjs --write` 生成；实测 `sim/tb_*.v` 里 **0 支**读它，唯一读者是 `src/host/one_click_test.mjs` 与 `.py`（读 `wordid_512x300.rgb565`）；其余 7 支是边界向量，还没有统一入口一次跑完（缺口见 `report/90-open-items.md`）" |
| `data/README.md:13` | golden 那一格"14" | 改件数与形状（11 PNG + manifest + README，删 `.mem` 之后是 13）；并把"谁读它"那列直接写"没有代码读它" |
| `data/README.md:14` | measured 那一格"20" | 改成删除后的实测数，并把"报告里的实测数字指回这里"改成"指回 `build/evidence/`"（实测 `metrics.csv` 的证据列 0 处指 `data/`） |
| `data/README.md:15` | generated 那一格"生成上面那些向量的脚本本身（不是数据…）" | 移到 `src/host/` 后这一整格删掉；或删掉"不是数据"这句自辩 |
| `data/README.md:44-48` | "`measured/` 这一格在工作目录里是 20，在只含入库文件的检出里数到 15——差额 5 支…" | 数量随删除变；改成删除后现量的两个数，并保留"差额是不入库的原始抓取件"这个口径解释 |
| `report/repro-check.md:296` | `data/measured/` 件数 = 20，PASS，命令 `ls data/measured \| wc -l` | 改成删除后的现量，或整行删（它是一次演练的读数，改数=伪造记录；按 `report/log/` 那条口径处理：这一行属于交付文档 `report/repro-check.md`，**可以直接改，但要把"本轮重构后的现量"写清楚**） |
| `report/repro-check.md:165-166` | "第一轮量时 `data/measured/` 是空的，第二轮已有 20 个件" + "README §3.1 那一行已改成 20 个件" | 与上一行同步；否则 `data/README.md` 与 `repro-check.md` 两处漂 |
| `report/submission-checklist.md:16` | 第 8 项 = `data/README.md` + `data/golden/README.md` + `data/measured/README.md` | 若 `measured/` 清空 ⇒ 第三支删；`test -e data/measured/README.md` 那条检查命令同批改 |
| `data/golden/README.md:5-9`、`manifest.md` | 自认"没有任何 `.v/.mjs/.sh` 读这里面的文件" | 保留这段（它是诚实的），但删 `.mem` 后 `README.md:17/25-27` 那两行与 `manifest.md` 里 `.mem` 那一行必须一起删；`manifest.md` 的件数（`board/raw-vs-golden.md:106` 实测指出"表里 14 / 现算 13"）一并核对 |
| `make_submission.sh:112` | `KEEP_ALWAYS_RE` 含 `^data/golden/` | 见 R6 |

## C.3 `golden/` 与 `measured/` 的去留判定

**`golden/`：留图、删 `.mem`、降级命名。**
依据（全部实测）：`data/golden/README.md:21-24` 明写这批 PNG"无法一键重跑，那份工具现在不在树里"；`report/08-limits.md:182`、`report/60-failure-analysis.md:464-465`、`report/70-reproduce.md:178`、`report/known_issues.md:860` 已经把"参考图不是自动生成的"登记成一条限制，而 `report/70-reproduce.md:178` 给的是**【不可复现】**。
所以它不是"参考结果（golden）"，是"历史参照图"。两条出路：

1. （推荐）留 11 张 PNG，把 `golden/` 目录**改名 `data/reference/`**，`README.md:21` 与 `data/README.md:13` 同批改；`golden` 这个词继续留在原地只会让评审以为有逐像素对账（`board/raw-vs-golden.md:10-11` 实测就写着"这一格现在依然是 0 行"）。改名要付的代价：`make_submission.sh:112`（`^data/golden/`）、`build/r122_ps_relocate.mjs:28`、`build/r122_skills_cite_exempt.mjs:29` 三处形状规则 + 交付文档里 `data/golden` 的 10 处。
2. 或补一支与 `src/rtl/process/` 定点算术一致、含同套饱和/取整的渲染脚本（`golden/README.md:22-24` 已经写清了它长什么样）——那是功能活，不是目录活，不属本轮。

**`measured/`：拆。**
理由：这一格里三种东西混着——原始回读（`.out/.gz`）、判读文档（3 支 `.md`）、运行台账（`arb_handover_last.json`）。判读文档按 `data/README.md:24-25` 自己的规则 3 就该在 `report/` 或 `board/`；原始件里凡是"一次测量的现场"按同一条规则应与 `build/evidence/` 里的凭据成对，那就并过去；`.out.gz` 那 460 K 只有 `ddr_stale.mjs` 能读，属"作者本地对照"，与 `.gitignore:58` 挡 `ddr_dump.out` 是同一条口径。**`measured/` 清空后整目录删**（注意 C5/`deliver_spec_check.mjs:387` 只要求 `data` 顶层有跟踪件，不要求 `measured/` 在）。

---

# D. 风险段：删完之后哪几把尺子会红 / 会空转

"变红"= 判据报红；"空转"= 判据安静地判 0 条或降级成 `NOT_MEASURED`，评审只看得到绿。两者都要防。

| # | 尺子 | 判据行 | 删什么会触发 | 症状 | 必须配套改的那一行 | 改前必须红 / 改后必须绿 的跑法 |
|---|---|---|---|---|---|---|
| 1 | `src/host/doc_currency_check.mjs` **D3** | `:386-398 newestGreenSet()` + `:115-127` | 删 `build/r75_gates.txt` | 首页 `README.md:82/84` 念 r75，尺子算出的最新全绿变 r74 ⇒ 判 2 条红；若全绿件一支不剩 ⇒ `newestGreen=0`，`:115` 那个 `if` 整块跳过 ⇒ **D3 空转**（`README.md:122-124` 那条"至少要有一句"也不跑了） | 保住 `build/r75_gates.txt`；或把 README 那两句改成"不作门禁全绿声明"（`:121` 认这句为第二种诚实写法） | `node src/host/doc_currency_check.mjs` ⇒ 末行必须是 `CURRENCY: 干净`，倒数第 3 行必须念 `最新且 ALL PASS 的冻结集 = r75_gates.txt`。红/绿演练：`cp build/r75_gates.txt /tmp/kx/ && rm build/r75_gates.txt && node src/host/doc_currency_check.mjs`（应红，且基准变成 r74）→ `cp /tmp/kx/r75_gates.txt build/ && node src/host/doc_currency_check.mjs`（应回绿） |
| 2 | 同上 **D1b / D1c** | `:278-296 currentBoardRound()`、`:441-450` | 删 `build/r118_gates.txt`，或删/改 `build/system.bit` | `:292` 要求某件正文含 `system.bit md5=cd04907e1369`；删件 ⇒ `best=0` ⇒ `:439-440` 打 `D1b 判不了：没有一份 rNN_gates.txt 戳着这块 bit`，D1c 同批失去基准（`:450`）。注意**这条不会因为 `system.bit` 不存在而红**（`:284-285` 把"提交包没二进制"判成不可判），所以只有仓库里能验 | 保住 `build/r118_gates.txt` 与 `build/system.bit` 的**同一份**（`:280` 取 md5 前 12 位） | `node src/host/doc_currency_check.mjs 2>&1 \| grep 'D1b 基准'` ⇒ 应念 `bit md5=cd04907e1369 → r118_gates.txt`。红/绿演练：`mv build/r118_gates.txt /tmp/kx/ && node src/host/doc_currency_check.mjs \| tail -3`（应有"D1b 判不了"）→ `mv` 回来，应回绿 |
| 3 | 同上 **D4c / D4a / D2** | `:155-157 CITE_ART` + `:143 CITE_MD` + `:83 CITED` + `:185-186 DELIVERY` + `:209-243` | A.3 的 D1–D14、B.5、C.2 全部 | 判红面是 54 份交付文档。实测被点名且存在的件 475 支、413 支无豁免 ⇒ **一次删满 = 407 处 `build/` + 175 处 `board/` 的红** | 按 A.5 的三条规则改；不许贴"不随包"（`:188-201` 的豁免是给"存在但不随包"的，件删光了那句就是假话） | 每删一批跑 `node src/host/doc_currency_check.mjs 2>&1 \| grep -c '盘上没有'`，改到 0，末行回 `CURRENCY: 干净`。反例自检：`node src/host/doc_currency_check.mjs --self`（`:501-507` 有 D4c/D3 的坏输入对照，必须仍然全 PASS，否则说明你把尺子的牙磨掉了） |
| 4 | `src/host/line_cite_check.mjs` **D5** | `:35-39` 射程（全仓 `.md`，只排 `report/log/`、`report/study/`）、`:48 CITE`、`:25-26` 判红三类、`:465` 汇总行 | 删 A.5 表里那 18 支 `rNN_*` 脚本 | 判红"文件不在树里" ⇒ `D5: RED`。⚠ 射程包含 **`docs/course/`、`docs/walkthrough/` 这两层未入库的 `.md`** ⇒ 会出现"本机红、提交包里绿"的分裂读数 | 同批改 `build/probe-guard.md`、`build/artifacts/README.md`、`build/runs/ledger.md`、`build/coverage.md`、`report/repro-check.md:294`（`bash -n` 分母 10→9）；`docs/` 那两处一起改 | `node src/host/line_cite_check.mjs 2>&1 \| tail -2` ⇒ 必须 `D5: CLEAN（…硬错 0 条…）`。反例自检 `node src/host/line_cite_check.mjs --self` 必须全 PASS（`:438` 的计数地板是 8 + D5d 五条，少跑一条就 FAIL） |
| 5 | `build/gates.sh` **CDC 项** | `:150 CDCADOPT`、`:151-163` | 删 `build/evidence_r75/` | `:160-162` 走 else：打 `FATAL 取不到采纳版 … 这一项少了一把尺子，不敢判绿` 并 `cdc_ok=0` ⇒ **门禁那一项红**（不是静默跳过——这点和很多人以为的不一样，实测在 `:161`） | 保住 `build/evidence_r75/cdc.rpt`（2 279 B），或按 R1 改默认值并同批改 `:147-149` 的注释 | ⚠ `gates.sh` 会写 `build/ports_check.txt`（`:4`），跑之前先 `cp build/ports_check.txt /tmp/kx/`。跑法：`bash build/gates.sh 2>&1 \| grep -E '采纳版|CDC|GATES:'`。红/绿演练：`mv build/evidence_r75 /tmp/kx/ && bash build/gates.sh; mv /tmp/kx/evidence_r75 build/`（注意 `:18-21` 那条警告：**不要**把输出直接重定向进 `build/rNN_gates.txt`） |
| 6 | `build/gates.sh` 报告读取 | `:29-37 pick()` | 删平铺 `build/timing_summary.rpt`/`utilization.rpt`/`power.rpt`/`route_status.rpt` 任一支 | `:35-37` 打 `FATAL 缺报告：$f` 并 `exit 2` ⇒ 门禁跑都不跑 | 平铺那三支 + `methodology/route_status/cdc` 一起留（A.4）；要挪就同批改 R9 | `bash build/gates.sh 2>&1 \| head -3` ⇒ 应念 `报告目录：build` 而不是 FATAL |
| 7 | `src/host/metric_recheck.mjs` **D6** | `:207-209`、`:213-215` 的 fixture | 删平铺三支 | 读不到报告 ⇒ 首页与 `data/metrics.csv` 的数字对账这一层失效（D6 在 `gates.sh:524-546` 里是第 21 项） | 同 R9 | `node src/host/metric_recheck.mjs 2>&1 \| tail -3` 与 `node src/host/metric_recheck.mjs --self`（`:546` 那句"该红的没红"就是空转检测） |
| 8 | `build/checks/check_repo_consistency.mjs` **C2** | `:225-233` + `:97 C2_RE` | 删 `board/verify_r87.md`（6 行证据列指它）、删 `build/evidence/r87_boot_stat_drain.txt`、`build/tb_v98_report.txt`、`build/sim/mut_control.sh`、`build/evidence/r86_osd_t18_teeth_addr.txt`、`build/evidence/r113_temp_lines.txt`、`build/evidence/r113_serial_raw.txt` | `miss.length>0` ⇒ C2 从 PASS 变 **FAIL**，整表末行不再是 12 项全过 | R10；`build/evidence/` 整目录留 ⇒ 天然满足 | `node build/checks/check_repo_consistency.mjs 2>&1 \| grep -E '^C2 '`。自检：`node build/checks/check_repo_consistency.mjs --self`（`:163-220`，含 C3/C9 对照） |
| 9 | 同上 **C3** | `:235-253` + `:245 --list` | 任何被 `.md` 点名的路径消失 | `agg.dead.length>0` ⇒ FAIL；`agg.total==0` ⇒ 变 `NOT_MEASURED`（**空转的另一种形状：件全删光、文档也全删光，C3 就"没东西可判"了**） | 按 A.5 的三条规则；每删一层都要看见 `死引用=0` 而不是 `检查路径引用=0` | `node build/checks/check_repo_consistency.mjs --list 2>&1 \| grep '^DEAD ' \| wc -l` ⇒ 必须 0；同时 `扫=` 的分母不能比删之前掉太多（掉了就说明连指路文档一起删了） |
| 10 | 同上 **C10 / C11** | `:363-369`（C10 两份 r119 件都必须在盘上）、`:372-376`（C11 四支候选 `>=3`） | 删 `build/evidence/r119_pin_skew_probe2.txt`、`r119_window_check.txt`、`r119_pin_skew_probe.txt` 或 `board/acceptance.md` | C10 → `NOT_MEASURED`（`both=否`）；C11 → `FAIL`（`has<3`）。`board/acceptance.md` 是四支候选之一 | R5 | `node build/checks/check_repo_consistency.mjs 2>&1 \| grep -E '^C1[01] '` ⇒ 改前 C10 应显示"两件齐=是 判定=PASS"，删件后应见"两件齐=否 ⇒ NOT_MEASURED"，改完 R5 应回 PASS |
| 11 | `build/deliver_spec_check.mjs` **C4 / C4b** | `:335` 7 支 tcl 名单、`:338` 每支跟踪 `.tcl` 的头 12 行要素、`:339-348` `build/report/` 非空 + `build/README.md` 含对照表、`:360-383` 每份归档件都被 `build/report.tcl` 点名 | 删 A.4 名单里任一支 tcl；往 `board/project/` 放 `.tcl` 却不写头注释；把 `build/report/` 里某支删掉但 `build/report.tcl` 还点它名（或反过来） | C4/C4b FAIL（`:343` 缺脚本、`:344` 头缺要素、`:345` 空、`:348` README 缺对照表、`:371` orphan） | R7 / R8；B.3(1) 新增的每支 `.tcl` 都要带 `作用/前置条件/产出物/关键参数` 那块头（照 `build/gen_bit.tcl:1-6` 的形状抄） | `node build/deliver_spec_check.mjs 2>&1 \| grep -E '^C4'` |
| 12 | 同上 **C0-4 顶层结构** | `:57-64`，`allowDirs = src sim build board data skills report` | 把 `vivado_system/` 或 `vitis/` 整目录入库并放在**仓库根**（`.gitignore:2/:8` 一旦加例外就会引入新顶层目录） | `多余=1[……]` ⇒ C0-4 FAIL | B.3 的方案 A 把工程放进 `board/project/`，不动顶层 ⇒ 无需改名单 | `node build/deliver_spec_check.mjs 2>&1 \| grep 'C0-4'` |
| 13 | 同上 **C5 四类目录齐** | `:387-388` `need=['board','data','skills','report']`，任一目录跟踪件为 0 ⇒ FAIL | "board 全删了重新写"这一步如果先删后写、中途跑一次检查 | `缺目录=1[board]` ⇒ FAIL | 删与写在**同一个 commit** 里完成；或先只删到剩 1 支 | `git ls-files board \| wc -l` ⇒ 任何时刻都要 > 0 |
| 14 | `build/make_submission.sh` | `:112 KEEP_ALWAYS_RE`（含 `^data/golden/`）、`:179/:382` 的 `for d in build/evidence_* build/frozen_* build/isolated_* build/*_probe board/evidence_*`、`:696 SKIP_RE` | 删掉 `data/golden/` 或全部轮次目录 | 规则不报错但变成**死规则**：`:162` 的射程行会念出一条兜不住任何东西的形状规则；glob 无匹配时字面量进循环，`[ -d "$d" ]` 若在循环外就是一次空跑 | R6：同批删形状规则那一段 + `shopt -s nullglob` | `bash -n build/make_submission.sh && bash build/make_submission.sh --dry 2>&1 \| grep -E '射程|KEEP'`（若该脚本无 dry 档，读 `:247/:261` 那段裁池逻辑确认新形状） |
| 15 | `.gitignore` 本身 | `:8 VITIS/` | 在**区分大小写**的文件系统（Linux CI / WSL）上把 `vitis/` 改名或入库 | 实测这台机器 `core.ignorecase=true` 才让 `VITIS/` 命中 `vitis/`；换机器就挡不住了，一个 49 MB 的树会突然变成"待提交的未跟踪件" | 把 `:8` 改成两行都写：`VITIS/` + `vitis/`；`:7 vit/` 同理核对 | `git check-ignore -v vitis/platform` 应命中；`git config core.ignorecase` 记下当前值 |
| 16 | `data/metrics.csv` 的证据链 | C.1 实测：`grep -c data/ data/metrics.csv` = 0 | — | **这不是删除风险，是本来就断的那一条**：重构完之后 `data/README.md:24-25` 那句"报告里的实测数字指回这里"依然不成立 | C.4：把这句改成事实，或把 `.mem`/`inputs/` 真接进一条有出处的读数链 | `node build/checks/check_repo_consistency.mjs 2>&1 \| grep '^C2 '` 只判"指得到"，不判"指到 data/" ⇒ 用 `grep -c 'data/' data/metrics.csv` 这条命令本身当尺子，重构后仍为 0 就必须让 `data/README.md` 的措辞与它一致 |

## D.1 一把跑完的验证顺序（每步都要看到指定输出）

```bash
# 0) 存基线（只读）
node src/host/doc_currency_check.mjs        | tee /tmp/kx/d_before.txt      # 期望末行 CURRENCY: 干净
node src/host/line_cite_check.mjs           | tee /tmp/kx/d5_before.txt     # 期望末行 D5: CLEAN
node build/checks/check_repo_consistency.mjs| tee /tmp/kx/c_before.txt      # 记下 C2/C3/C10/C11 四行
node src/host/metric_recheck.mjs            | tee /tmp/kx/d6_before.txt
node build/deliver_spec_check.mjs           | tee /tmp/kx/spec_before.txt   # 记下 C0-4/C4/C4b/C5
git ls-files | wc -l; git ls-files | xargs -d '\n' stat -c '%s' 2>/dev/null | awk '{s+=$1} END{print s/1048576" MB"}'

# 1) 先改尺子与文档（A.5 / B.5 / C.2 的表），一件都不删，跑一遍：四把尺子必须全绿
# 2) 删 E 档（634 支 / 16.54 MB，零引用）→ 再跑一遍：应与第 1 步完全相同的绿
# 3) 删 D2–D8（逐轮 txt/log/md/rpt/一次性脚本/probe/rotate）→ 每删一类跑一次 D4c 计数
node src/host/doc_currency_check.mjs 2>&1 | grep -c 'D4c 点名的凭据盘上没有'
# 4) 删目录族（D9–D14）→ 跑 D2
node src/host/doc_currency_check.mjs 2>&1 | grep 'D2 点名的目录盘上没有'
# 5) board/ 与 data/ 的删除与重写放在同一个 commit（防 C5 空窗），跑 C2/C3
# 6) 门禁与交付规格（gates.sh 会写 build/ports_check.txt，跑前先备份该件）
cp build/ports_check.txt /tmp/kx/ports_check.bak
bash build/gates.sh > /tmp/kx/g.txt 2>&1; tail -3 /tmp/kx/g.txt
cp /tmp/kx/ports_check.bak build/ports_check.txt   # 若门禁把这份凭据改了，按需决定留不留新值
node build/deliver_spec_check.mjs | grep -E '^(C0|C4|C4b|C5)'
```

改前必须红、改后必须绿的三组**最小标本**（不用真删，用临时挪开验一次就放回）：

```bash
mkdir -p /tmp/kx
# 标本 1 —— D3 基准
mv build/r75_gates.txt /tmp/kx/ && node src/host/doc_currency_check.mjs | grep D3;   # 应红
mv /tmp/kx/r75_gates.txt build/ && node src/host/doc_currency_check.mjs | tail -1;   # 应回"干净"
# 标本 2 —— D1b/D1c 基准
mv build/r118_gates.txt /tmp/kx/ && node src/host/doc_currency_check.mjs | grep -E 'D1b|D1c';  # 应念"判不了/没有一份"
mv /tmp/kx/r118_gates.txt build/ && node src/host/doc_currency_check.mjs | grep 'D1b 基准';    # 应念 cd04907e1369 → r118_gates.txt
# 标本 3 —— C2 的 6 行
mv board/verify_r87.md /tmp/kx/ && node build/checks/check_repo_consistency.mjs | grep '^C2';  # 应 FAIL 且 miss 非空
mv /tmp/kx/verify_r87.md board/ && node build/checks/check_repo_consistency.mjs | grep '^C2';  # 应 PASS
```
