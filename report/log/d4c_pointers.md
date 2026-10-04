# D4c 的"只报数"那一档：逐条分类结论

> **本页为什么放在 `report/log/`（日记区）而不是交付区**：它的内容就是一张"盘上不存在的路径"清单。
> 2026-09-30 r96 收尾时试着把它当交付文档发出去，`build/make_submission.sh` 的自检当场数到
> **56 条死链、全部出自本页**（它把每一处点名的文件名都当链接），于是拒绝写包 —— 这是导出器该有的行为，
> 不去给它开免检名单（#172 刚记过"免检名单让自检恒绿"）。所以本页留在这里：分类口径本身
> 已经写进 `src/host/doc_currency_check.mjs` 的头部（含 `--list-adv` 那条复现命令），
> 交付文档只念那条口径，不念这张表。

任务 #121（账本 #122 那一族）欠的分类活。`src/host/doc_currency_check.mjs` 的 D4c 每天念一句
「交付文档 21 份判红；其余 N 份点名凭据 M 条只报数」——M 只给数，没给理由。
这份表把那 M 条逐条取出、逐条给理由：**哪些是合理的过程留档，哪些是尺子漏了。**

## 怎么把这批条目重新取出来（一行命令）

```bash
node src/host/doc_currency_check.mjs && PYTHONIOENCODING=utf-8 python build/r94_d4c_classify.py --all
```

前者念出 `adv` 的总数，后者复现它的分类条件并逐条打印（只读扫描，不写盘、不改任何脚本；
cmd 下把前缀换成 `set PYTHONIOENCODING=utf-8`）。两个数必须**同一时刻**对得上，
本表的快照：**2026-09-30 14:11**，当时尺子念 `交付文档 22 份判红；其余 371 份点名凭据 129 条只报数`，
分类脚本念 `m = 393 / nd = 22 / rows = 2 / adv = 129`（这一分钟的原样 dump 在 `build/r94_d4c_out.txt`，
那份 `.txt` 不在判据的扫描范围里 ⇒ 加它不改任何数）。
**这棵树是活的**（今晚台架链在写 `build/`，日记在追加）：同一句话今天从 126 漂到 130，
所以本表的条数只对这一分钟负责，条目身份（谁指谁）不漂。
（已核：④ 那 4 条在 14:07 / 14:11 / 14:16 三次扫描里**身份完全一致**，会漂的只是 ①③⑤ 的条数 ——
 14:16 时 `adv` 已经从 129 落回 126，因为台架链把 r94 那批逐轮件收走了。）
（`nd` 从 21 变 22 是**本页自己**加进去的 —— 本页在 `report/` 下且不是 log，算交付文档。）

**表里的死路径一律写成 `…/build/xxx.log` 这种带前导分隔符的样子**，这不是排版也不是省略号：
判据头部写死了"前面有路径分隔符或名字，就不该拿工作区的盘去判它存在与否"，
所以带 `…/` 前缀的字面量**不会被本页自己当成指路判红**（本页有 139 处引用别人的死路径，
不加这层前缀就会新造 139 条死链 —— 那是把"记错"变成"传染"）。读的时候请忽略那个 `…/`。

⚠ 那个 Python 自己也在被扫描的树里，它每写一条字面路径就给总数 +1（本工具踩过两次，
现版本已把自身的字面量拆开）。这是"复现口径"最容易被污染的一处，复核时先 `grep r94_d4c_classify`
看输出里有没有它自己。

## 六类怎么划的（判据出处都写在里面）

| 类 | 是什么 | 为什么不该判红 / 该怎么处置 |
|----|--------|------------------------------|
| ① | 来源是追加式日记 `report/log/*.md`（含 `build/rNN_issueNNN_entry.md` 草稿，正文已逐字并入 ISSUES.md） | 规矩本身：脚本头部写着"拿今天的盘判昨天的日记，红的不是文档过期，是逼自己回头改日记"（#98 老规矩） |
| ② | 目标**当前盘上存在** | 结构性红不了：`checkPaths()` 里 `exists(tok)` 为真直接 `continue`，**连报数桶都不进** ⇒ ② 在 M 条里恒为 0 |
| ③ | 目标不存在，但按章程**不随提交包**（`build/{evidence,frozen,failed}_*`、`build/evidence/`、`build/reports/`、`build/isolated_*`、带轮次号的逐轮件、`.bit/.elf` 构建产物） | 导出器 `build/make_submission.sh` §2/§3.9b 会剪；"要说清理由"的就是这一类 |
| ④ | 目标不存在、又不属于以上任何一类 | **真漏网**，本表末尾单列，一条没藏 |
| ⑤ | 该行是命令行/赋值/重定向，路径是**工具或脚本自己创建的输出目标**（`vivado -log X`、`> X`、`TMP=X`） | 写方不是引用方；#172 已裁过这一族："属于工具自己创建的文件，不是凭据" |
| ⑥ | 路径是**故意不存在**的假名（`no_such_report.rpt`） | 阴性对照/自测夹具；判据自己靠 `SELF` 豁免，别人的夹具没人豁免 ⇒ 尺子的口径缺口 |

**计数（129 条 = D4c 127 + D4a 2；② 另算）**：

| ① | ② | ③ | ④ | ⑤ | ⑥ |
|---|---|---|---|---|---|
| 93 | **0**（另统计：非交付文件里点名且盘上存在的凭据 **1616** 条） | 14 | **4** | 16 | 2 |

> 顺带一条读数口径：`adv` 桶里混着 **2 条 D4a**（`report/log/ISSUES.md:5186` / `:5926` 指 `…/report/PROJECT_BRIEF.md`），
> 而那句播报把它们一起算进"点名凭据 129 条"。凭据数其实是 127。

## ④ 真漏网：4 条（逐条原文）

| # | 文件:行 | 指到哪 | 归哪类 | 为什么 |
|---|---------|--------|--------|--------|
| 1 | `src/host/health_read.mjs:16` | `…/build/v76_build.log` | ④ | 注释把两个 GPIO 基地址的**唯一出处**押在一份 V7.6 时代的构建日志上。`.log` 在 `.gitignore` 里（`*.log`），任何新克隆都拿不到 ⇒ 这条指路**永远兑现不了**。应改成"见 `report/BOARD_PINS.md`"或把地址抄进注释 |
| 2 | `src/host/doc_enc_check.mjs:32` | `…/build/frozen_r57_remap/MANIFEST.md5` | ④ | 人工复核改判（机械规则先给了 ③）：目录**就在盘上**，里面那份叫 `MANIFEST.txt` 不叫 `.md5` ⇒ 理由是**文件名写错**，不是"不随包"。同族风险：`frozen_*` 用 `.txt`、`evidence_*` 才用 `.md5` |
| 3 | `build/tcl/ooc_newmods.tcl:9` | `…/build/ooc_newmods.log` | ④ | 上一行（`:8`）是 `-log …/build/ooc_newmods.log` ⇒ 判据句 `grep "Slack" …/build/ooc_newmods.log` 读的是**工具刚创建、又被 gitignore 挡住的**日志。归 ④ 是因为它确实在"叫你去查一个查不到的东西"；口径上更接近 ⑤ |
| 4 | `build/r90_phase3.sh:85` | `…/build/tb_edge_rim_r90.txt` | ④ | 本脚本 `:58` 用 `ROUND=r90 bash build/rim_report.sh` 生成它（那件的落名是 `build/tb_edge_rim_r${ROUND}.txt`），`:85` 再把它读回来当总账一行。导出器对 `tb_edge_rim_r*` 是**明确保留**的例外（所以不属 ③），而**盘上现在没有 r90 那一份** —— 是本机哪一次清理（`build/cleanup_wip.sh` 的"未被引用即删"？）走的，本表没查证，只查到了"不在" ⇒ 死指路。同型 ⑤ 那条（`:55`）是写、这条是读 |

第 3、4 条是"读自己写的东西"这一族：写侧已被 ⑤ 接走，读侧没人接。**升判据前必须先决定这一族算不算红**，
否则门禁会红在自家脚本上。

## ⑤ 写方而非引用方：16 条

| 文件:行 | 指到哪 | 为什么（写方证据） |
|---------|--------|--------------------|
| `board/serial_bytes.ps1:1` | `…/build/serial_hex.txt` | `param([string]$Out = '…/build/serial_hex.txt')`：参数默认值，脚本是写方 |
| `build/r90_phase3.sh:55` | `…/build/r90_rim_console.txt` | `bash sim/run_one.sh tb_edge_rim > 该件`（重定向目标）；同时属 ③ |
| `build/r90_phase3.sh:61` | `…/build/r90_gates.txt` | `bash build/gates.sh > 该件`；同时属 ③ |
| `build/r90_phase3.sh:69` | `…/build/evidence/r90_flash_2_program_pl.txt` | `vivado -mode batch … > 该件`；同时属 ③ |
| `build/r90_phase3.sh:71` | `…/build/evidence/r90_flash_3_app_reload.txt` | `xsdb … > 该件`；同时属 ③ |
| `build/r90_phase3.sh:88` | `…/build/r90_summary.txt` | `} > …/build/r90_summary.txt`（整段总账的落点）；同时属 ③ |
| `build/r94_bench_chain.sh:19` | `…/build/r94_tb98_report_step.txt` | `bash build/tb98_report.sh > 该件`；同时属 ③ |
| `build/r94_bench_chain.sh:22` | `…/build/r94_edge_rim_console.txt` | `bash sim/run_one.sh tb_edge_rim > 该件`；同时属 ③ |
| `build/r94_bench_chain.sh:23` | `…/build/r94_rim_report_step.txt` | `bash build/rim_report.sh > 该件`；同时属 ③ |
| `build/r94_bench_chain.sh:26` | `…/build/r94_gates.txt` | `bash build/gates.sh > …/build/r94_gates.txt 2>&1` ⇒ **今晚那两条判红等的就是它**（链跑完自己落，红自消）；同时属 ③ |
| `build/roll_isolated.sh:20` | `…/build/tcl/_tmp_isolated_roll.tcl` | `TMP=…` → `:28` 生成 → `:35` `rm -f`：设计上就留不住 |
| `build/tcl/ooc_newmods.tcl:8` | `…/build/ooc_newmods.log` | `vivado -mode batch -nojournal -log 该件`（#172 那一族） |
| `build/tcl/report_mem_hier.tcl:3` | `…/build/report_mem_hier.log` | 同上，`-log` 输出目标 |
| `build/tcl/sweep_impl_strategy.tcl:3` | `…/build/sweep.log` | 同上，`-log` 输出目标 |
| `sim/run_sim.tcl:6` | `…/sim/xsim.log` | 同上；⚠ 实盘上 Vivado 把它写在**仓库根** `xsim.log`，`…/sim/xsim.log` 从来不存在 |
| `skill/zynq-video-rtl-debug/SKILL.md:49` | `…/sim/xsim.log` | 同上，且 #172 正文已经点名"它是 `-log` 的输出文件，不是凭据" |

## ⑥ 自测夹具里的假路径：2 条

| 文件:行 | 指到哪 | 为什么 |
|---------|--------|--------|
| `build/r95_read_ce.sh:36` | `…/build/no_such_report.rpt` | `if [ -n "$(read_timing …)" ]; then echo "FAIL 缺报告却读出了数"` —— 阴性对照，路径**必须**不存在 |
| `build/r95_read_ce.sh:37` | `…/build/no_such_report.rpt` | 同上的 BRAM 那一半 |

判据脚本自己有 `SELF` 豁免（`…/build/r99_gates_nope.txt` 不会被自己咬），**别的脚本的夹具没有豁免** ⇒ 口径缺口。

## ③ 不存在、但按章程不随提交包：14 条（要说清理由的那一批）

| 文件:行 | 指到哪 | 为什么（导出器哪一条剪它） |
|---------|--------|------------------------------|
| `build/freeze_evidence.sh:55` | `…/build/r94_flash.log` | 注释讲的是"当初 `.log` 后缀进不了包"的教训本身（#172 同族）；`.log` 又被 gitignore ⇒ 双重不随包 |
| `build/r90_phase3.sh:56` | `…/build/r90_rim_console.txt` | 读自己 `:55` 写的逐轮件；`build/rNN_*` 属"逐轮过程留档"被剪 |
| `build/r90_phase3.sh:57` | `…/build/r90_rim_console.txt` | 同上（提示语里再念一次名字） |
| `build/r90_phase3.sh:62` | `…/build/r90_gates.txt` | 读自己 `:61` 写的门禁件；逐轮件不随包 |
| `build/r90_phase3.sh:63` | `…/build/r90_gates.txt` | 同上 |
| `build/r90_phase3.sh:70` | `…/build/evidence/r90_flash_2_program_pl.txt` | 读自己 `:69` 写的板级件；`build/evidence/` 整类剪（板级件搬 `board/output/`） |
| `build/r90_phase3.sh:86` | `…/build/r90_gates.txt` | 总账里读门禁件；同 `:62` |
| `build/r90_phase3.sh:89` | `…/build/r90_summary.txt` | 读自己 `:88` 写的总账；逐轮件 |
| `build/r92_doc_fixup.py:4` | `…/build/isolated_xxx/system.bit` | 占位名 `xxx`＋隔离目录＋`.bit`：三重不随包。⚠ 判据的占位白名单只认 `NN`/`$`/`*`，**认不出 `xxx`** ⇒ 口径缺口 |
| `build/r92_doc_fixup.py:35` | `…/build/isolated_xxx/system.bit` | 同上 |
| `build/r92_doc_followon.py:29` | `…/build/isolated_xxx/system.bit` | 同上 |
| `build/r92_doc_refresh.py:114` | `…/build/evidence/r90_flash_2_program_log.txt` | 这是改写脚本里的**被替换旧文常量**，不是本脚本的指路；且 `build/evidence/` 不随包 |
| `build/r94_bench_chain.sh:29` | `…/build/r94_gates.txt` | 台架跑完后 echo 门禁尾部读它；链没跑完 ⇒ 现在不在盘上 |
| `src/rtl/eth/dc_fifo.v:34` | `…/build/r83_gates.txt` | RTL 注释念 #105 第一刀回滚的凭据；`build/rNN_*` 逐轮件不随包（结论已抄进注释，读不到件也能看懂） |

## ① 日记里的中间件：93 条（规矩上就不该判红）

这一类的理由**逐条相同**：来源是追加式日记，句子里那个路径是"当时存在、随后删掉"的过程件。
把它判红等于逼人去改昨天的记录 —— 那是销毁过程凭据，比过期更糟（脚本头部与 #98 都写着这条）。
最后一列：`日` = `report/log/` 正文，`稿` = `build/rNN_issueNNN_entry.md` 草稿（正文已逐字进 ISSUES.md）。

| 文件:行 | 指到哪 | 日/稿 |
|---------|--------|-------|
| `build/r94_issue169_entry.md:37` | `…/build/r94_flash.log` | 稿 |
| `build/r94_issue172_entry.md:7` | `…/build/r94_flash.log` | 稿 |
| `build/r94_issue172_entry.md:12` | `…/sim/xsim.log` | 稿 |
| `report/log/CHANGELOG_V7.md:409` | `…/build/v76c_build.log` | 日 |
| `report/log/CHANGELOG_V7.md:704` | `…/board/uart_r28_autoplay.txt` | 日 |
| `report/log/CHANGELOG_V7.md:710` | `…/board/sd_hotspot_diag.txt` | 日 |
| `report/log/CHANGELOG_V7.md:710` | `…/board/sd_hotspot_fixed.txt` | 日 |
| `report/log/CHANGELOG_V7.md:710` | `…/board/sd_selftest_red.txt` | 日 |
| `report/log/ISSUES.md:241` | `…/sim/tb_ku5p_tx_arb.v` | 日 |
| `report/log/ISSUES.md:325` | `…/sim/tb_ku5p_telem.v` | 日 |
| `report/log/ISSUES.md:435` | `…/build/build/system.bit` | 日 |
| `report/log/ISSUES.md:746` | `…/board/uart_50_conc3min.txt` | 日 |
| `report/log/ISSUES.md:748` | `…/board/sd_frame_boundary2.txt` | 日 |
| `report/log/ISSUES.md:773` | `…/board/uart_soak_A.txt` | 日 |
| `report/log/ISSUES.md:773` | `…/board/uart_sd_wedge.txt` | 日 |
| `report/log/ISSUES.md:774` | `…/board/uart_50_dbg.txt` | 日 |
| `report/log/ISSUES.md:798` | `…/board/sd_hotspot_diag.txt` | 日 |
| `report/log/ISSUES.md:823` | `…/board/sd_hotspot_fixed.txt` | 日 |
| `report/log/ISSUES.md:826` | `…/board/uart_sd_with_eth.txt` | 日 |
| `report/log/ISSUES.md:835` | `…/board/sd_dirmap_banner.txt` | 日 |
| `report/log/ISSUES.md:838` | `…/board/sd_selftest_red.txt` | 日 |
| `report/log/ISSUES.md:838` | `…/board/sd_selftest_green.txt` | 日 |
| `report/log/ISSUES.md:869` | `…/sim/tb_v80_ku5p_cmd.v` | 日 |
| `report/log/ISSUES.md:1190` | `…/board/uart_r46_boot.txt` | 日 |
| `report/log/ISSUES.md:1259` | `…/sim/known_red/tb_v92_seam_bleed.v` | 日 |
| `report/log/ISSUES.md:1791` | `…/build/tb_v98_run.log` | 日 |
| `report/log/ISSUES.md:2115` | `…/build/rot_osd_wip.patch.txt` | 日 |
| `report/log/ISSUES.md:2366` | `…/build/ps_app_v9.log` | 日 |
| `report/log/ISSUES.md:2414` | `…/build/r60_build47.log` | 日 |
| `report/log/ISSUES.md:2685` | `…/sim/v98run/run_base.log` | 日 |
| `report/log/ISSUES.md:2986` | `…/build/cdc_who.tcl` | 日 |
| `report/log/ISSUES.md:4296` | `…/build/evidence/verify_0927_11xx.txt` | 日 |
| `report/log/ISSUES.md:4505` | `…/build/r77_gates.txt` | 日 |
| `report/log/ISSUES.md:5186` | `…/report/PROJECT_BRIEF.md`（**D4a**，不是凭据） | 日 |
| `report/log/ISSUES.md:5662` | `…/build/tcl/_tmp_isolated_roll.tcl` | 日 |
| `report/log/ISSUES.md:5663` | `…/build/crit_path.tcl` | 日 |
| `report/log/ISSUES.md:5830` | `…/build/printf_arity_check.mjs` | 日 |
| `report/log/ISSUES.md:5878` | `…/build/reports/tb_video_pipeline_top_report.txt` | 日 |
| `report/log/ISSUES.md:5926` | `…/report/PROJECT_BRIEF.md`（**D4a**，不是凭据） | 日 |
| `report/log/ISSUES.md:6144` | `…/build/reports/r87_power.rpt` | 日 |
| `report/log/ISSUES.md:6678` | `…/build/r94_flash.log` | 日 |
| `report/log/ISSUES.md:6710` | `…/build/r94_flash.log` | 日 |
| `report/log/ISSUES.md:6715` | `…/sim/xsim.log` | 日 |
| `report/log/OVERNIGHT_LOG.md:356` | `…/build/scan_l4.log` | 日 |
| `report/log/OVERNIGHT_LOG.md:549` | `…/build/r06_build.log` | 日 |
| `report/log/OVERNIGHT_LOG.md:582` | `…/build/r07_build.log` | 日 |
| `report/log/OVERNIGHT_LOG.md:661` | `…/build/v76b_build.log` | 日 |
| `report/log/OVERNIGHT_LOG.md:832` | `…/sim/tb_fb_pack.v` | 日 |
| `report/log/OVERNIGHT_LOG.md:908` | `…/sim/tb_ku5p_tx_arb.v` | 日 |
| `report/log/OVERNIGHT_LOG.md:954` | `…/build/v64_baseline.bit` | 日 |
| `report/log/OVERNIGHT_LOG.md:954` | `…/build/r05_golden.bit` | 日 |
| `report/log/OVERNIGHT_LOG.md:1329` | `…/build/failed_r19b/system_r19b_WNS-1.277.bit` | 日 |
| `report/log/OVERNIGHT_LOG.md:1882` | `…/build/build/system.bit` | 日 |
| `report/log/OVERNIGHT_LOG.md:2082` | `…/sim/tb_v80_ku5p_cmd.v` | 日 |
| `report/log/OVERNIGHT_LOG.md:2083` | `…/sim/tb_ku5p_telem.v` | 日 |
| `report/log/OVERNIGHT_LOG.md:2084` | `…/sim/top_check_ku5p.sh` | 日 |
| `report/log/OVERNIGHT_LOG.md:2119` | `…/sim/tb_v80_ku5p_cmd.v` | 日 |
| `report/log/OVERNIGHT_LOG.md:2216` | `…/sim/results/regression_v79_r37..r39.txt` | 日 |
| `report/log/OVERNIGHT_LOG.md:2261` | `…/board/uart_r28_autoplay.txt` | 日 |
| `report/log/OVERNIGHT_LOG.md:2274` | `…/board/uart_r28_stat.txt` | 日 |
| `report/log/OVERNIGHT_LOG.md:2283` | `…/board/uart_50_conc3min.txt` | 日 |
| `report/log/OVERNIGHT_LOG.md:2285` | `…/board/sd_frame_boundary2.txt` | 日 |
| `report/log/OVERNIGHT_LOG.md:2364` | `…/board/sd_hotspot_diag.txt` | 日 |
| `report/log/OVERNIGHT_LOG.md:2378` | `…/board/sd_hotspot_fixed.txt` | 日 |
| `report/log/OVERNIGHT_LOG.md:2384` | `…/board/sd_selftest_red.txt` | 日 |
| `report/log/OVERNIGHT_LOG.md:2418` | `…/board/uart_sd_with_eth.txt` | 日 |
| `report/log/OVERNIGHT_LOG.md:2426` | `…/board/uart_final_state.txt` | 日 |
| `report/log/OVERNIGHT_LOG.md:2516` | `…/board/ddr_churn_r33_newelf.txt` | 日 |
| `report/log/OVERNIGHT_LOG.md:2840` | `…/sim/known_red/tb_v92_seam_bleed.v` | 日 |
| `report/log/OVERNIGHT_LOG.md:3661` | `…/build/r57_build38.log` | 日 |
| `report/log/OVERNIGHT_LOG.md:3828` | `…/build/tb_v98_run.log` | 日 |
| `report/log/OVERNIGHT_LOG.md:4076` | `…/build/ps_app_v9b/v9d/v9e.log` | 日 |
| `report/log/OVERNIGHT_LOG.md:4081` | `…/build/r60_build47.log` | 日 |
| `report/log/OVERNIGHT_LOG.md:4229` | `…/build/r63_build.log` | 日 |
| `report/log/OVERNIGHT_LOG.md:4242` | `…/build/src/rtl/top/pl_video_top.v` | 日 |
| `report/log/OVERNIGHT_LOG.md:4246` | `…/build/r63_build.log` | 日 |
| `report/log/OVERNIGHT_LOG.md:4293` | `…/build/r63b_build.log` | 日 |
| `report/log/OVERNIGHT_LOG.md:4300` | `…/build/r63b_build.log` | 日 |
| `report/log/OVERNIGHT_LOG.md:4362` | `…/build/wip_c1i_falsify.sh` | 日 |
| `report/log/OVERNIGHT_LOG.md:4390` | `…/build/wip_flash_r63.sh` | 日 |
| `report/log/OVERNIGHT_LOG.md:4429` | `…/build/wip_flash_r63.sh` | 日 |
| `report/log/OVERNIGHT_LOG.md:4463` | `…/build/r65_flash.txt` | 日 |
| `report/log/OVERNIGHT_LOG.md:4661` | `…/build/wip_r71_finalize.sh` | 日 |
| `report/log/OVERNIGHT_LOG.md:4828` | `…/build/wip_c1i_falsify.sh` | 日 |
| `report/log/OVERNIGHT_LOG.md:4840` | `…/build/rot_osd_wip.patch.txt` | 日 |
| `report/log/OVERNIGHT_LOG.md:4840` | `…/build/video_pipeline.bit` | 日 |
| `report/log/OVERNIGHT_LOG.md:5399` | `…/sim/tb_v57_rdw_copy.v` | 日 |
| `report/log/OVERNIGHT_LOG.md:5706` | `…/build/tb_edge_rim_r81.txt` | 日 |
| `report/log/OVERNIGHT_LOG.md:5770` | `…/build/r83_gates.txt` | 日 |
| `report/log/OVERNIGHT_LOG.md:5890` | `…/build/tcl/_tmp_isolated_roll.tcl` | 日 |
| `report/log/PLAN_V8_SPEC.md:15` | `…/board/sd_hotspot_fixed.txt` | 日 |
| `report/log/PLAN_V8_SPEC.md:59` | `…/board/uart_cmd_check_r44.txt` | 日 |
| `report/log/VERSION_LINEAGE.md:165` | `…/sim/tb_v80_ku5p_cmd.v` | 日 |

## ② 的真相：M 条里一条都没有，但另有一千六百多条在盘上

`checkPaths()` 的 D4c 分支是 `if (exists(tok)) continue;` —— **盘上存在的点名根本不进任何桶**。
所以"② 只报数"这个说法不成立：它连数都没报。单独统计（非交付文件里点名且盘上存在）= **1616 条**，
形状是 `build/` 1050、`sim/` 339、`build/evidence*` 123、`board/` 43、`data/` 27，
另有 `build/evidence_r75/…` 8 条、`build/frozen_*` 若干。这一批**安全**，也解释了为什么"只报数"
这个说法听着比实际大：M 只统计了"点空了"的那些，没统计"点中了"的那些。

## 顺带查出的四处尺子口径缺口（只记，不动脚本）

1. `adv` 混了 D4a：播报句把 2 条文档指路算进"点名凭据"。
2. 占位名白名单只认 `NN`/`$`/`*`，认不出 `xxx`（3 条 ③ 因此被误当指路）。
3. `SELF` 豁免只豁免判据自己，别的脚本的阴性对照（`no_such_*`）没人豁免 ⇒ 2 条 ⑥。
4. `-log <输出文件>` / `> <输出文件>` 这类**写方**路径被当引用扫（16 条 ⑤），
   而"读自己刚写的输出"（④ 第 3、4 条）与之同族却落在另一档 —— 边界没写死。

## 如果要把 D4c 从"只报数"升成判据：能红对照长什么样

规矩是新的判据必须先有一条"能红"的变异对照才进门禁（`--self` 里 D4c 已经有正例 `d4art` 与
"通配/变量/占位名不许咬"的反例 `d4artok`，缺的是**范围那一半**）。要补的对照，思路四条：

1. **范围不漂**（#141 那一族）：同一句指路喂两遍 —— 写进交付文档必须红、写进 `report/log/` 必须只报数。
   这条现有 `scope` 用例已经做了（.txt/.md 各一，判红 0 / 报数 2）；升级后要加**反向**的一条：
   红的那一半若某天也变成 0（有人把 `DELIVERY` 放宽过头），用例必须自己炸。
2. **写方必须不红**（⑤ 那一族，16 条）：变异输入用一行
   `bash build/gates.sh > …/build/r99_will_exist_only_when_run.txt 2>&1`，断言**不判红**；
   再配一条同路径被正文引用的输入，断言**判红**。两半缺一半就是范围漂了。
3. **④ 必须能红**（真漏网那一族）：用 `src/host/health_read.mjs:16` 的形状造一条
   `// 基地址在 …/build/v76_build.log 的行里`（纯注释、非交付路径），断言**判红**；
   对照是 ⑥ 那一族 —— 同一路径写成 `no_such_report.rpt` 时**不许红**。
   这一对正好把"真死链"与"故意死的夹具"分开，是升级后最有价值的一条能红对照。
4. **章程不随包（③）要说清理由再决定**：如果打算让 `build/evidence_rNN/…` 参与判红，
   能红对照得同时喂"目录存在但文件不在"（`frozen_r57_remap/MANIFEST.md5` 那种 **④**）
   与"整个目录按章程不复制"（**③**），断言前者红、后者只报数；
   否则升级的第一批红会全落在导出器本来就剪掉的件上 —— 那是判"文档"的罪，罚的是"包"。

另有两条前置：`.log` 在 `.gitignore` 里（`*.log`），任何指向 `.log` 的"判红"在新克隆上必然长红，
升级前要么把 `log` 从 `ART_EXT` 摘出去并单独解释，要么让交付文档停止点 `.log`；
以及"复现分类的脚本自己也在扫描树里"这一条，得在断言里排除 `build/rNN_*.py` 这类一次性工具，
否则总数会被工具自己 +1（本表实测踩过两次）。

---

**诚实边界：这份表是 2026-09-30 14:11 那次扫描的人工归类快照 —— 六类的界线由人写：
④ 里 1 条是人工把机械规则的 ③ 改判过来，第 3、4 条（"读自己刚写的输出"）是本表按边界判断留下的，
⑤/⑥ 的识别规则也是本表自定的，`doc_currency_check.mjs` 里没有这套分类。
所以这份表**不是自动判据**，也不代表尺子的判定；台架链还在跑，条数会漂，重跑上面那行命令为准。**

## 复核（2026-09-30 17:5x，r96 台架链在飞期间）

- 快照数字：`node src/host/doc_currency_check.mjs` 念 **交付文档 22 份判红；其余 375 份点名凭据 126 条只报数**；
  `--list-adv` 现在可以把这 126 条**逐条打出来**（本轮给尺子补的纯打印开关，不参与退出码），
  于是"表里的身份"与"尺子当前的输出"能在同一分钟对得上，不必再靠 `build/r94_d4c_out.txt` 那份旧 dump。
- 交叉表（`PYTHONIOENCODING=utf-8 python build/r94_d4c_classify.py --all`）与本页 14:11 那次同形：
  **"盘上没有"的条目在交付文档里是 0 条**（`README.md` 14/14 存在、`README.en.md` 12/12、`report/` 414/414），
  其余分布在 `report/log/` 90、`build/` 28、`src/` 3、`board/`、`sim/`、`skill/` 各 1。
  ⇒ 本页的分类结论没有被这一轮的新增内容推翻；会漂的还是条数（今天 129 → 126），身份不漂。
- 本轮新出现的两类归属（已写进尺子头部，逐条见 `--list-adv`）：
  **历史叙述里点名"当时找错的路径"**（`ISSUES.md:435` 讲的"目录 `build` 被写了两遍的那个 bit 路径"，
  说的是 root 少一级那个已修缺陷）
  与**退役台架/wip 脚本的名字**（#108 的 sim/ 剔除、#123 的 build/ 清理删掉的）。
  两者都不该判红：它们描述的是"曾经不存在"或"按规则被清走"，不是让人去打开。
