# r109 采纳判读清单（写于 00:2x，顶层台架在飞、预计 02:24 前后出齐）

这一页是给"链子跑完之后那一程"的对照表：**每一项都要点名它来自哪份件**，
凡是只能靠板子的事，现在就已经写明挂在欠账里（板子 AP 不可达，见 ISSUES #235；用户没答恢复时间 ⇒ 默认先做不依赖板子的那一半）。

## 一、判"采纳还是回退"要读的四组数（不许用一句"看起来还行"代替）
1. **快车道（真树、构建后那份）** `build/r109_lane_after.txt`
   实测：`ran=28/28 green=27 red=1 refuse=0 no-verdict/other=0 wall=525s`。
   唯一红 = `tb_link_monitor` 的既存 `F2e`（任务 #174，机理与预验已就位，见 `build/evidence/r174_f2e_preverify.txt`）。
   ⇒ **OSD 那刀的等价性凭据**：`tb_osd_lines` / `tb_v794_osd_glyph` 两支都在 GREEN 里。
2. **顶层台架** `build/r109_tb98_console.txt` + `build/tb_v98_report.txt`（由 `build/tb98_report.sh` 写，白名单已补 `C12 `）
   必须逐条读：`FAIL` 行**只有** `C5c`（声明过的那条）；`C12a / C12b / C12c / C12pre` 四条各打一行；
   `C12 rot: cmp=? bad=? steps=?` 那行的 `steps>=3`（阳性对照）与 `cmp>=4`（分母）是 C12a 的牙，缺一个就是空判据。
   警告：C12a 若还红 ⇒ 换角拍点没挪对，**这一刀回退**（`rot_fs_tog` 那一处），其余两刀可留但要单独再判。
3. **时序读数** `build/evidence/r109_clk01_after.txt`（对照 `..._before.txt`）
   `clkout0_1` 已由 1.130/23 级/route 77.5 % 变成 4.094/21 级/route 62.8 %（相对余量 5.65 % → 20.5 %）。
   采纳那一步不再重跑它；但**首页逐时钟那三格要按新 `build/timing_summary.rpt` 重读**（D6 会判，别抄）。
4. **门禁两跑** `build/r109_gates.txt` 与 `/tmp/kx/g_r109_2.txt`
   条数 = **24**（第 22/23 项是新接的 `pipe_len` / `temp_formula`）；
   绿的应当 23、红 1 且红项名字在 {顶层台架, 文档时效, 数字对账, 边缘条带} 里；
   两跑必须逐字节一致（D1b/D1c 的自基准形状，#229）。

## 二、采纳那一笔必须同笔做完的事（顺序不能拆）
1. `bash build/adopt_after_chain.sh`（三步 JTAG + `board_verify --geom --battery --round=r109`）
   ⇒ **现在做不了**：板子 AP 不可达（`DAP status 0xF0000021`），且它需要 COM6。挂欠账，等断电重上。
   恢复顺序：`ps_jtag_boot.tcl` → `program_pl.tcl` → `ps_app_reload.tcl`，
   每道的 token：`DDR_ECHO … 5A5AA5A5` / `PROGRAMMED xc7z020_1` / `DOW: ok` + `RESUME: ok`（**`DOW:` 必须逐行看，不许 tail**）。
2. **门禁条数与每一句念它的文案同笔改口**（#229/#176）：22 → **24**，四处——
   README.md 的「限制与未通过项」一节、`README_EN.md` 同形状行、`report/background_and_novelty.md:31`、`:80`；
   同一笔提交里重跑 `node src/host/doc_currency.mjs` 确认不红。
3. 首页与 `data/metrics.csv` 的数字全部**从件里重读**（WNS 0.605、逐时钟四格、WHS 0.049、
   LUT 14362 / FF 8162、BRAM 95.5、功耗、身份行"板上这一版 r109 + bit md5 + 刷入时刻"），
   然后 `node src/host/metric_recheck.mjs` 要 红 0。
4. `report/log/issues.md` 落 #236（这一轮的采纳判读），`board/acceptance.md` 记 E 系列：
   **眼睛判据（旋转动起来顶部还有没有分散细线）必须由用户做**，不能代判；板子没回来就写"欠"。
5. 试冻结 `build/freeze_evidence.sh`（大概仍 REFUSE，全绿集还是 r75 —— 如实记）；
   重导提交包 `bash build/make_submission.sh`（若目录句柄被占，用 `VP_SUB_OUT` 换路径 + **数盘上文件数**验收，rule 50）。
   警告：验收算式（2026-10-03 读 `build/make_submission.sh:613-615` 定死，别再自己"发现"一个 off-by-one）：
   导出器数的是**写 MANIFEST 之前**、且**排除 MANIFEST.txt 自己**的文件数（`find . -type f ! -name MANIFEST.txt | wc -l`），
   所以正确关系是 **盘上文件数 = MANIFEST 里那个「文件数」+ 1**。本刻实测：盘上 384、MANIFEST 写 383 ⇒ 一致
   （`_pruned.txt` 已经算在 383 里，它不是差项；#106 那次修的正是这类"报的数与落地差 N"）。
6. 提交 + 推送，然后立刻开下一批（#174 + #177 + #158，见 `build/r109_batch2_ready.md`）。

## 三、明确不算完成的事（免得把"做了很多"当成"做完了"）
- 板级一切复验与眼睛判据（等断电重上）。
- app 侧那条 #167 修复**未上板**：这台机器没有 `arm-none-eabi-gcc`，ELF 没重建（ISSUES #234/#235）。
- `tb_link_monitor` 还没接进门禁（等 F2e 修绿，接成第 25 项时再一起改口）。
- #102 的 raw 抽头半、#127 四条 CANDIDATE 探针、#128 尾账、#82 文档瘦身、#115 海报：仍在账上。

## 追加（2026-10-03）：#167 那四条新判据怎么读才不会读错家（ISSUES #239）
C12 这个 token 现在有两家共用，**不许按 token grep**。按整句：
  grep -a 'C12pre both phases judged real frames'   build/r109_tb98_console.txt   → 期望 PASS（c12_rot_cmp>=4 且 c12_fz_cmp>=3）
  grep -a 'C12c rotating stimulus really steps'     build/r109_tb98_console.txt   → 期望 PASS（c12_rot_step>=3，这是正对照）
  grep -a 'C12a head request beat uses'             build/r109_tb98_console.txt   → 期望 PASS；**红 ⇒ 换角拍点没挪对，回退 src/rtl/top/pl_video_top.v 那一处**
  grep -a 'C12b frozen-angle control'               build/r109_tb98_console.txt   → 期望 PASS（钉角对照也自洽）
读数行（分母）：`C12 rot: cmp=.. bad=.. steps=.. | frozen: cmp=.. bad=.. | angle now=..` —— 这一行不在报告里就是
`build/tb98_report.sh:35` 的打印白名单漏了 `C12 `（今天已补），补前那份报告只有结论没有数。
老家的两条（`C12pre the rose probe…`、`C12a osd off removes every glyph cell…`）判的是 OSD 总开关，与这一刀无关，
但它们的红/绿也计入 NFAIL/NPASS —— 所以"FAIL 行数=1"这条断言成立时，四家都是绿的。

## 追加二（2026-10-03）：门禁句 22→24 的四处已 grep 定位；hold 那一行要改的是**落点**不是域名
`grep -rn "22 项\|22 items"` 命中恰好四处（与计划一致，没有第五处）：
README.md 的「限制与未通过项」一节、`README_EN.md:70`、`report/background_and_novelty.md:31`、`report/background_and_novelty.md:80`。
另：首页保持时间那行（README.md 关键数字表中「保持时间」那一行）现在写的是"全设计最差那一格在 `eth_rxc`（… 落点 `u_eth/u_cdc/rgray_s1_reg…`）"。
r109 的读实（`build/evidence/r109_hold_owner.txt` 第一节）：WHS 0.049 的**域名仍是 eth_rxc/gmii_rx_clk**，
但**落点换成** `u_eth/u_rx_mac/u_crc_rx/crc_data_reg[17]/C → crc_data_reg[25]/D`（1 级、route 80.9 %）⇒
按规矩 46，"最差那一格在 X"是归属判据：这次**域名那句可以留、落点半句必须重写**，且要与 D6 判的六十八个数同一笔提交换。
首页 WNS 那行今天读的是 **r108 / bit 25bf35a9900e / 0.721 ns**（板上是 r108，不是记忆里写的 r107）——
采纳那笔换数前先用 `build/r109_timing_summary` 一类原件重读，不许从 README 抄 README。

## 追加三（2026-10-03 01:5x）：门禁那份件的**出生时间**必须晚于台架 RESULT（ISSUES #240）
盘上已经有一份 `build/r109_gates.txt`（00:06 写的，bit md5=21227687e925），但那是**台架之前**跑的半成品，
它给 D1b 的身份判据提供了放行 ⇒ 判读时不许用它。规则：采纳只认 `build/r109_gates.txt` 里时间戳**比
`build/r109_tb98_console.txt` 新**的那一份，而且两跑逐字节一致；`[ "$F" -nt "$G" ]` 这一步不许省。
同一段还写明：今晚板子被恢复到 **r108**（文档态，`build/system_r108_restore.bit` 走 VP_BIT 刷入 + board_verify PASS geom 10/0），
而 `build/system.bit` 已被 r109 构建覆盖 ⇒ **采纳那笔必须同时把 r109 的位流落回 `build/system.bit`/`.xsa` 并提交**，
否则导出器打进去的位流与首页不同源（#240）。

## 追加四（01:6x）：三种判读结果各走哪条路（提前定好，凌晨不做临场设计）
1) **四句全绿 + 门禁两跑逐字节一致（唯一红 C5c）** ⇒ 采纳：
   按 `build/r109_rotation_worklist.md` 一次改完（44 条数字 + 门禁 22→24 四处 + hold 落点半句 + MODULES 重锚），
   `build/system.bit`/`.xsa` 里已是 r109 ⇒ 连同文档一笔提交；然后三步链刷板（**不设 VP_BIT**，默认就刷 build/system.bit）、
   `board_verify --geom --battery --round=r109`、取刷板时刻与新 bit md5 回填首页身份那半句（第二笔提交）、
   试冻结、`make_submission.sh`（数盘上文件，别读它的 stdout，规矩 50）、推送。
2) **只有 `C12a head request beat uses` 红**（换角拍点没挪对）⇒ 回退 `src/rtl/top/pl_video_top.v` 那一处（保留 OSD 那一刀），
   `git checkout -- src/rtl/top/pl_video_top.v`，然后 **必须重构建**（位流变了，20 分钟）再走 r110 的链子；
   首页数字里与那一刀有关的两格（`clkout0_1` 4.094/20.47 % 若受影响）重读原件，不许沿用本轮读数。
   警告：这一条同时意味着任务 #167 的第二条尺子（C12 那四条）留在树上判红 —— 尺子没错、DUT 没修好，红就是结论。
3) **`C12pre`/`C12c` 红**（分母不够：cmp/steps 太小）⇒ 是**台架自己没测到**，不是设计红。
   先读 `C12 rot:` 那行读数与激励（`split_ctl_tb[14]`、`[17:15]=3'd3`），按规矩 46"先怀疑尺子的维度"处理，
   判读结论只写"本轮不采纳、原因在激励覆盖"，**不改期望值**。
另外一条与判读无关的既有事实（今晚读实，写进 #240）：断电重上后 `build/system.bit` 是未采纳的 r109，
而板子恢复到 r108 文档态（`build/restore_documented_bit.sh --dry` 能自己认出这套关系）。
所以判读期间**不要跑 `make_submission.sh`**，也不要 `board_verify --round=r108`（会覆盖已封存的 r108 原始回显）。
