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
   ⚠ C12a 若还红 ⇒ 换角拍点没挪对，**这一刀回退**（`rot_fs_tog` 那一处），其余两刀可留但要单独再判。
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
   `README.md:56`、`README.en.md` 同形状行、`report/BACKGROUND_AND_NOVELTY.md:31`、`:80`；
   同一笔提交里重跑 `node src/host/doc_currency.mjs` 确认不红。
3. 首页与 `data/metrics.csv` 的数字全部**从件里重读**（WNS 0.605、逐时钟四格、WHS 0.049、
   LUT 14362 / FF 8162、BRAM 95.5、功耗、身份行"板上这一版 r109 + bit md5 + 刷入时刻"），
   然后 `node src/host/metric_recheck.mjs` 要 红 0。
4. `report/log/ISSUES.md` 落 #236（这一轮的采纳判读），`board/ACCEPTANCE.md` 记 E 系列：
   **眼睛判据（旋转动起来顶部还有没有分散细线）必须由用户做**，我不能代判；板子没回来就写"欠"。
5. 试冻结 `build/freeze_evidence.sh`（大概仍 REFUSE，全绿集还是 r75 —— 如实记）；
   重导提交包 `bash build/make_submission.sh`（若目录句柄被占，用 `VP_SUB_OUT` 换路径 + **数盘上文件数**验收，rule 50）。
   ⚠ 验收算式（2026-10-03 读 `build/make_submission.sh:613-615` 定死，别再自己"发现"一个 off-by-one）：
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
