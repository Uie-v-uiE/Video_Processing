# r110 批次（第二捆）—— 三刀都已经**预备完**，只差"树空下来 → 落刀 → 一次构建"

这一页的存在理由：用户要求"所有任务一起开、别一个一个搞几小时仿真"。所以第二捆里每一刀都**已经在不花构建的前提下验过**，
落刀之后只需要一次构建 + 一次顶层台架（一轮只付那 127 分钟一次）。

## 刀 0（**最先做**，因为它决定后面几刀的证据可不可信）：修回我把 `osd_addr` 变异弄钝的那处回归
r109 的 #105 那一刀把 OSD 读侧改成 `ch_addr_pre = line*MAX_CHARS + cidx` → `ch_r <= chars[ch_addr_pre]`，
`ch_addr` 从此只供台架判越界、**不再决定画出来的是什么**。后果：`sim/mut_control.sh` 的 `osd_addr` 分支
（sed 改 `ch_addr` 那一行、`EXPDIFF=2`）现在"只改判据的眼睛、不改 DUT 的画"，而且 sed 仍能匹配 ⇒ **脚本不报警，只有人会漏**。
详见 ISSUES #237。修法是两边重新同源并各配一支变异：
- `sim/tb_osd_lines.v:76` 再引出 `oob_idx2 = u_osd.ch_addr_pre;`，T17/T18 要求两根都在范围内；
- `sim/mut_control.sh` 把 `osd_addr` 拆成 `osd_addr_judge`（只改 `ch_addr` ⇒ 判据必须抓到）与
  `osd_addr_draw`（改 `ch_addr_pre` ⇒ 必须红 T17），各给 `EXPDIFF`，并改掉旧注释里"仍然 0 是限度"的说法。
落完这一刀再谈下面的刀 1..6 —— 否则后面任何"变异对照通过"都建立在一把已经失效的尺子上。

## 刀 1：#174 `gapclr` 与 `frame_done` 同拍竞争（已差分预验，凭据 `build/evidence/r174_f2e_preverify.txt`）
- 位置：`src/rtl/eth/link_monitor.v`，记账块（今天 `:137` 起的 `if (frame_done) begin stall_ms <= 0; if (have_base) begin …`）。
- 改法：`if (frame_done) begin stall_ms <= 0; if (gapclr) begin gap_last<=0; gap_min<=0; gap_max<=0; gap_sum<=0; gap_valid<=0; end else if (have_base) begin …`
  —— 与 `:110` 已有的"清 > 帧边界 > 滴答"优先级对齐；跨零点那一条完成的间隔**丢弃**，下一个 `frame_done` 重建基准。
- 预验读数：未打刀那腿 `FAIL F2e B … sum=518 > 2x130`（且只有这一条红）；打刀那腿 F2e A/B 与 F2a–F2d 全绿。
- 落刀后：`bash sim/run_one.sh tb_link_monitor`（约 38 秒）必须全绿；然后重跑 `build/f2e_preverify.sh` 只是留凭据，不再需要。
- ⚠ 不要"顺手"改期望值：F2e A 那条对照就是防这条刀把判据改宽的（规矩 30/44）。

## 刀 2：#177 死代码一轮（删完要证"输出不变"，逐端口面已在任务 #177 里查到底）
- `src/rtl/eth/eth_ctrl.v`：删厂商残肢 —— 端口 `tx_data`/`tx_req`/`rec_en`/`rec_data`/`icmp_tx_data`/`udp_tx_data`
  与随之无人读的输入 `icmp_tx_req`/`udp_tx_req`/`udp_rec_data`/`udp_rec_en`/`icmp_rec_en`/`icmp_rec_data`，
  内部 `icmp_tx_req_d0`/`udp_tx_req_d0`、`:56` 的 `assign tx_req`、`:57/:58` 两条 `assign *_tx_data`、`:72-86` 那个 `rec_en/rec_data` always 块。
  **保留**：GMII 发送仲裁（`arp_*`/`udp_*`/`icmp_gmii_*` → `gmii_tx_en/gmii_txd`）与 `arp_tx_en`/`arp_tx_type` —— 那是真在发 ARP/ICMP 的路。
- `src/rtl/eth/eth_udp_video_top.v`：删 `fifo_tx_data`/`fifo_tx_req`/`fifo_rec_en`/`fifo_rec_data` 四根线（今天只在 `:114-116` 声明、`:219-220` 空接）
  与 `:214/:218` 的 `.icmp_tx_data()` / `.udp_tx_data()`；**同时删掉 `:217` 那句"这条 rec 转发路径无人消费"的注释**（路径没了还留着话，就是 main.c 那种自相矛盾）。
- `src/rtl/video/split_ctrl.v`：`reg [11:0] pct_q` 的 `[11:8]` 由构造恒 0 ⇒ 窄化成 `reg [7:0] pct_q` + `assign shown_pct = {4'd0, pct_q}`（端口宽度不动）。按 #227 的口径**二选一**：这里选"窄化"，不另加断言。
- 证明四步（都在批判里，不额外花构建）：① `grep` 逐名命中数=预期；② 综合日志里 `Synth 8-3848 fifo_tx_data` 与 `Synth 8-3332 pct_q_reg__*` 必须消失，且 `Synth 8-xxxx` 的**种类数不许增加**；
  ③ `build/utilization.rpt` 的 Slice Registers 应下降，数字进 `build/evidence/r110_deadcode_proof.txt`；④ `bash build/timing_lane.sh` 与本轮基线同绿同红。
- 台架安全性已核：`grep -rln eth_ctrl sim/` 只命中一份历史 results 文本 ⇒ 改端口不打断任何台架编译。

## 刀 3：#158 两处死同步口 + 截断行计数器（任务 #158 里已写明"须先证输出一致"）
- 这一刀的证据姿势与刀 2 同构（先证无人消费，再删；删完对比资源与快车道）。

## 构建与判读（一轮只付一次）
1. 落三刀 → `bash build/timing_lane.sh`（约 9 分钟）先拿等价性；
2. `bash build/r110_chain.sh`（照 `build/r109_chain.sh` 抄，NN=110）：构建 → 探针（含 `probe_clk_worst.tcl` 两个时钟）→ 快车道 → 顶层台架 → 边缘条带 → 门禁两跑；
3. 采纳判读走 `build/r109_adoption_checklist.md` 那张表，只把 r109 换成 r110；
4. ⚠ 链子在飞期间**不许再起第二支 xsim**（r109 的台架阶段就是这么丢掉 127 分钟的，ISSUES #234）。
   拷贝树预验（`build/f2e_preverify.sh` 这一类）只能排在链子起飞之前，或"阶段结束"之后。

## 刀 4（新浮出来的靶，读数是 r109 自己的）：`rows_hit` 位图的 CE 广播 + 物理侧
凭据 `build/evidence/r109_hold_owner.txt` 第二节：全设计最差 setup 现在是
`u_eth/u_reasm/off_reg[11]_rep/C → u_eth/u_reasm/rows_hit_reg[2]/CE`，**0.605 ns / 6 级 / route 82.25 %**，
其中 `off_reg[11]_rep_n_0` 这一根网络 `fo=109` 自己就吃 **1.511 ns**；
`Logic Levels` 里出现 `MUXF7=1 MUXF8=1` ⇒ 那 6 级是 16 位位图的比较树。
可做的两件事（**只做一件，一轮一个变量**，规矩 #223）—— 2026-10-03 读实整段 `build/setup_paths.rpt:15-61` 后，两件事的形状都比我原先写的更具体，
更正与逐跳数据在凭据文件的**第四节**（我之前那句"MUXF7/MUXF8 是 16 位位图的比较树"是猜的，错了：那是 5×64 位图**读侧 mux**）：
① ~~再削一次扇出（对 `rows_hit` 的 CE 用 r107 同款）~~ —— **已否**：那根使能网今天仍 `fo=316`，与 r106 抱怨的数字逐字相同，
   说明"分 5 组"只切开了各组的 `rbank==k` 与项，公共的 `new_row` 被综合又提回一根广播网 ⇒ 同款第二把**不成立**。
   可落的是换形状：把 `new_row` 打成**独热**（`rok_and_k = new_row & (rbank == 3'dk)`，五根独立网、每根 fo≈64），
   且 `rows_hit` 的 CE 不吃组合 `new_row` 而吃按组与后的项；落刀前后各读一次 `setup_paths.rpt` 里那条终点 CE 的**驱动网 fo**，
   判据 = fo 必须离开 316，否则这一刀没有抓手（不改期望值、不顺手放宽）。
② 物理侧：起点 X23Y22、终点 X28Y68 —— **46 行的纵向距离**就是最后那跳 1.784 ns 的直接来源，整族 route 82.25 %。
   ⇒ Pblock/就近放置这一族（r87 实测 route 66 % 那次记过口径）。
   ⚠ 这一条属于路线图 §11.3"约束/策略放最后"，且必须与 ① 分开单独滚，否则收益归不了属。
**先做哪一个**：① 是 RTL 单点、可在快车道逐刀验等价（位图与计数器行为不许变，`sim/tb_reasm_bounds.v` 的 R1 与
`tb_udp_reasm` 都在射程内），且它同时消掉 fo=316 与它自己那 1.784 ns；② 不动逻辑、只动约束，收益在**下一刀**才能归属。
按"一轮一个变量"与 §11.3，**r110 落 ①**，② 留给它自己的那一滚（与策略扫描同批）。
hold 侧今天不动：WHS 0.049 的归属又换了（`u_rx_mac/u_crc_rx/crc_data_reg[17] → [25]`，1 级、route 80.9 %，
`gmii_rx_clk` 域），而 r108 的口径句写的是 `u_eth/u_lm/full_d_reg/D` ⇒ 采纳那笔的首页 hold 行要重写**归属句**而不是只换数字
（rule 46：D6 判的就是那句归属）。

## 刀 5（任务 #158 的第二半："截断行"计数器 —— 判据先行，很可能这一刀**只落判据不落 RTL**）
机理读实了（`src/rtl/process/proc_morph.v:66-86`，同一族还有 `proc_box_blur/proc_sharpen/proc_sobel`）：
`run` 数连续 `de_in`，`owed = (run == H_ACTIVE)`，而 **`line_end = owed && dv_d1 && !de_in`** ⇒
行尾**只在整行满员时才承认**；`y_row_d <= y_in` 又只发生在 `line_end` 那一拍 ⇒
一旦某一行被截断（de 的个数 < `H_ACTIVE`），`y_row_d` 停在"上一个完整行"的行号上，
下一行若与它同号（x2 光栅下每个源行占两个显示行，这是常态），`row_first = (y_in != y_row_d)` 就是 0 ⇒
`no_above_r[0]` 那一拍不武装 ⇒ **顶部那一行吃到上一帧的上一行**（ISSUES 里 `row_first 粘滞` 那一条说的就是它）。

**为什么先要的是"数得出截断行"而不是先改 RTL**（#146/#158 定的顺序）：
今天没有任何凭据证明板上会出现截断行 —— 上游是帧缓存读链，行宽是构造出来的常量。
所以这一刀的**判据**要能同时回答两件事：① 这种行到底有没有出现过；② 出现过的时候后果是否真的落地。

设计（新的分钟级台架 `sim/tb_row_truncate`，四家窗口级模块各跑一遍，全部走层次读 DUT 自己的信号，不在外面重算）：
- `T1 机会计数（地板）`：台架数 `de_in` 的游程，`0 < run < H_ACTIVE` 的断点算一次"截断行"；
  激励**故意**插一条 `H_ACTIVE-3` 的短行 ⇒ 期望 `truncated_seen >= 1`。数不到就说明激励没真造出这种行（红的是激励，#187 那一族）。
- `T2 后果（改前必须红）`：紧接短行之后的那一行，读 DUT 的 `line_end`/`y_row_d`/`row_first` 三者现场，
  按定义该行的 `row_first` 必须为 1（新源行的第一个显示行）⇒ 未修的树上跑必须是 **0 ⇒ 红**，
  红行里把 `y_in`、`y_row_d`、`run`、`owed` 一起打出来，让下一个人能复核机理而不是只看一个布尔。
- `T3 对照（差分对的另一半）`：同一条链、同样帧数，但**不插短行** ⇒ `T2` 那三条现场必须全绿。
  ⇒ 有了 T3，`T2` 的红就不能推给"台架相位/我的探针位置"。
- `T4 覆盖地板`：每档至少比较过 `>= 2` 行 × `4` 个模块（`morph/box_blur/sharpen/sobel`），
  一条都不比就是空集绿（rule 44/46）。
判完的两种结局都要提前接受：**若 T2 红而 T3 绿** ⇒ 缺陷成立，改法是把行尾承认的条件放宽
（`dv_d1 && !de_in && run != 0` 也算行尾），四家同改、再配变异对照；
**若 T2 根本红不起来**（激励插不进短行 / 上游根本不产生）⇒ 这一条**保持"条件可达、未立案"**，
只把 T1/T3 作为回归判据留下，不改 RTL（这就是"不许把猜测升格成缺陷"，也是 #222/#158 的一贯口径）。
⚠ 与 r109 的 C12 同一姿势：两端夹逼 + 阳性对照 + 比较次数地板，三条都要**各打一行**。

## 刀 6（任务 #102 那一格"只缺 raw 抽头半"）：把**内容 tag** 级的第 0 列判据从 1.00× 扩到 0.5× / 0.75×
今天的射程长这样（读 `sim/tb_v98_top_seam.v` 与 `sim/tb_v96_zoom_scan.v` 读出来的，不是推测）：
- `tb_v96` 的 M1/M2/M4/M5/M6 判的是**映射半**（`floor+frac` 自洽、源列单调、黑边对称、90° 交换、呼吸漂移）⇒ 0.5–1.0× 那一半有尺；
- `tb_v98` 的 `C8c`（`:1026` 起）在**八档 × 512 列**上比的是 `dut.u_split.x_sel` 与 `c2_exp_col(...)` ——
  `x_sel` 是**坐标标签**，不是行环真正交出来的那颗像素；
- 判**内容 tag**（"这颗像素自带的源行/源列"）的是 `C8a/C8b`，而它们整对被 `c5_on` 关在
  `c4_on && c4_a==0` ⇒ **只在 1.00×、不旋转**那一格跑（`C6` 同样只判第 0 列的 tag，也只在 1.00×）。
⇒ 缺口就是任务 #74 说的那半：**行环/raw 抽头的"内容"在非 1.00× 上没人判过**，
   而这恰好是 #102 第一刀（消隐期钳住读地址）与 #92 那一族（左缘细线）真正的落点。

改法（加判据，不加 RTL；插在 `C8c` 那个 `always @(posedge dut.clk_pix)` 里，复用同一个窗与同一对期望函数）：
1. 在 `c2_on && de_d[MIX_D] && y_d[MIX_D] ∈ [C2_YLO,C2_YHI]` 那一支里，除现有 `x_sel` 比对之外，
   再比一次**内容**：`mem_row(dut.u_split.orig_pix)` / `mem_col(dut.u_split.orig_pix)` 对上
   `c2_exp_row/c2_exp_col(dut.u_split.x_sel, C2_TBL(c2_k))`（tag 是 mod 128/256 ⇒ 用 `dsub` 判小偏移，与 `C5/C6` 同一路子）；
   两路各数一份：**原图抽头**（`orig_pix`）与**处理抽头**（缝选中的那一路，即 `dut.r/g/b` 复原出的 565 那颗）。
2. 三条各打一行：`C10a raw tap's own tag follows the definition (8 zoom codes)`、
   `C10b proc tap's own tag follows the definition`、`C10pre per-code sample floor`（每档 `n-skip >= 20000` 才有资格判绿，rule 44/46）。
3. 牙（阳性对照，**必须在未改的树上就能红一次**）：`sim/mut_control.sh` 里加一支 `raw_tap_clamp` ——
   把 #102 第一刀那个"消隐期读地址钳 0"改回"钳到上一行"（或直接把 `u_raw` 的读地址 +1），
   变异后**只该红 C10a 一条**（连带 C10pre 不许动）；红两条以上就是判据共享根因，要在报告里点名连带。
   ⚠ 这条对照**先跑、拿到红，再谈任何 RTL**（#158/#222 的口径：先有数得出机会的尺子）。
4. 成本：这一刀不加帧、不加循环 ⇒ 顶层台架那 127 分钟不变；变异对照走单文件回退 + 只跑 `tb_v98` 一次，
   如果只想知道"尺子有没有牙"，可以先在 `tb_edge_rim`（30 秒级）上做同款 tag 比对再升格。

## 板子那一半（与刀无关，但挡住采纳）
板子 AP 不可达（`DAP status 0xF0000021`，ISSUES #235）⇒ 需要**断电重上**；恢复后按
`ps_jtag_boot.tcl` → `program_pl.tcl` → `ps_app_reload.tcl` 三道走，逐道看 token，尤其 `DOW:` 必须是 `ok`。
在板子回来之前：`board_verify`、串口电池、`cmd_overflow_probe`、以及所有眼睛判据都挂在欠账里，不许念成完成。

## 刀 7（纯标签，不动逻辑）：把 #167 那四条从 `C12*` 改叫 `C13*`，消掉与 r83 老家的 token 撞名
凭据与理由在 ISSUES #239：`sim/tb_v98_top_seam.v` 里 `C12pre`/`C12a` 各有两条语义无关的判据（:1689/:1691 老家的 OSD 总开关，
:1860/:1862/:1864/:1866 新家的每帧换角）。门禁方向是保守的（红就变 NFAIL=2），但"按 token grep"已经不可用。
改法三处一起：`line("C12pre both…")→C13pre`、`C12c→C13c`、`C12a head request…→C13a`、`C12b frozen-angle…→C13b`；
`build/tb98_report.sh:35` 的打印白名单加 `C13 `（保留 `C12 `，老家还在用）；`$display` 那两行读数前缀同批改 `C13 rot:` / `C13 frozen:`。
⚠ 条数不变 ⇒ "整屏判据条数"那一格不许跟着动（规矩 47：项数本身是被判的数）。
落刀后先在**未打刀**的树上跑一次 `sim/mut_control.sh` 或任一快车道支，确认没有脚本按 `^C12a` 找新家的读数行。

## 刀 2 的前置复核（2026-10-03 01:1x 重跑 grep，链子在飞、只读）
按名字数"命中几个文件"（`grep -rl "\b名字\b" src/rtl src/ps sim`）：
`fifo_tx_data`=1、`fifo_rec_en`=1、`pct_q`=1 ⇒ 只有声明它的那个文件自己提它，**无人消费成立**；
`icmp_tx_data`=2、`udp_tx_data`=2 ⇒ 恰好 eth_ctrl.v（端口）+ eth_udp_video_top.v（空接），删两头不会打断别处；
**但 `tx_data`=7、`tx_req`=7、`rec_en`=8、`rec_data`=8 —— 这四个是通用名，别的模块（udp/icmp 收发链）也在用。**
⇒ 落刀**必须按文件收窄**（`sed -i` 只作用于 `src/rtl/eth/eth_ctrl.v` 与 `src/rtl/eth/eth_udp_video_top.v` 两份件、
且只删端口声明/空接那几行），**不许全仓按名字删**（这是本仓记过的那条"name-lists leak"）。
删完的对照仍按本文件第 刀2 节的四步：② 综合日志里 `Synth 8-3848 fifo_tx_data` 与 `Synth 8-3332 pct_q_reg__*` 消失、
`Synth 8-xxxx` **种类数不增**；③ Slice Registers 降；④ 快车道与本轮同绿同红（既存红仍只有 `tb_link_monitor` 的 F2e）。

## 落刀入口改口（2026-10-03 01:2x）：刀 1 与刀 4① 不再手改，走 `build/r110_apply_cuts.sh`
凭据 `build/evidence/r110_apply_cuts_proof.txt`：拷贝树里三条全 APPLIED、缩进保住、xvlog 差分对照
pristine 0 ERROR / patched 0 ERROR（自测抓到并修掉两处我自己的缺陷：`row_covered` 用在其声明前、放宽比较后丢缩进）。
树空下来之后的顺序（**不要手改 src/rtl**，手改会让 MUST/LEFTOVER 这套后验失去对象）：
1. `bash build/r110_apply_cuts.sh --check` —— 三条都要 CHECK-OK；任一 ANCHOR-* 就是树变了，重读源码改脚本，不放宽锚点；
2. `VP_I_KNOW=1 bash build/r110_apply_cuts.sh --apply` —— 这一步会自己检查"没有 vivado/xsim 在飞 + 两份 RTL 在 git 里干净"，
   所以链子在飞时它 REFUSE 是**正确行为**，不要用 `VP_ALLOW_BUSY=1` 绕过（那个开关只给拷贝树自测）；
3. `git diff` 读一眼两处改动，`bash sim/run_one.sh tb_link_monitor`（约 40 秒，F2e 整支必须绿）；
4. `bash build/timing_lane.sh`（约 9 分钟）拿刀 4 的功能等价凭据：与 r109 基线比，**只许 `tb_link_monitor` 那支从红变绿**，
   其余 27 支逐支同绿；出现新红 ⇒ 独热刀改变了行为，按 `git checkout -- src/rtl/eth/frame_reasm.v` 退回；
5. 只有第 4 步干净才 `bash build/r110_chain.sh`（它先 `pre_readings.sh` 再构建；一轮只付一次 127 分钟顶层台架）；
6. 采纳判读仍看 `build/r109_adoption_checklist.md`（把 r109 换 r110）：四句**整句**匹配、门禁两跑逐字节一致、
   首页数字全部从原件重读；收益判据 = 那条终点 CE 的驱动网 fo 离开 316，**没离开就回退这一刀**。

## 刀 2 的逐行清单（2026-10-03 02:0x 读实到行，落刀时照这张表删，不凭记忆）
`src/rtl/eth/eth_ctrl.v`：端口 :23 `icmp_rec_en`、:24 `icmp_rec_data`、:25 `icmp_tx_req`、:26 `icmp_tx_data`、
:33 `udp_rec_data`、:34 `udp_rec_en`、:35 `udp_tx_req`、:36 `udp_tx_data`、:38 `tx_data`、:39 `tx_req`、:40 `rec_en`、:41 `rec_data`；
内部 :52/:53 `*_tx_req_d0`、:56 `assign tx_req`、:57/:58 两条 `assign *_tx_data`、:61-70 那个只给 `*_d0` 用的 always 块、
:71-86 的 `rec_en/rec_data` always 块（**整块删**，它只被 :17-22 那对端口消费）。
⚠ 删端口的前提是"例化者唯一"：上面这条 grep 就是那一刀的证据，落刀前重跑一次，若多出别的例化者就停下重读。
`src/rtl/eth/eth_udp_video_top.v`：删 :114-116 三行 `fifo_tx_data`/`fifo_tx_req`/`fifo_rec_en`/`fifo_rec_data` 声明、
例化里 `.icmp_tx_data()`(:214) 与 `.udp_tx_data()`(:218) 两行、`.tx_data(fifo_tx_data) .tx_req(fifo_tx_req)`(:219-220)、
`.rec_en(fifo_rec_en) .rec_data(fifo_rec_data)`(:221)，**并同笔删掉 :217 那句"这条 rec 转发路径无人消费"的注释**（路径没了还留话就是自相矛盾）；
`.udp_rec_data(p_data) .udp_rec_en(p_valid)` 那对也一起删（它喂的正是被删的内部端口）。
`src/rtl/video/split_ctrl.v`：`reg [11:0] pct_q` → `reg [7:0] pct_q` + `assign shown_pct = {4'd0, pct_q}`。
证明顺序不变：① 逐名 grep 命中数=预期；② 综合日志 `Synth 8-3848 fifo_tx_data`、`Synth 8-3332 pct_q_reg__*` 消失且
`Synth 8-xxxx` **种类数不增**；③ `build/utilization.rpt` 的 Slice Registers 下降（预期 −14 上下， udp_tx 的 7 个 FSM 寄存器**不许动**）；
④ 快车道与本轮同绿同红。**落刀后用拷贝树 xvlog + `xelab eth_udp_video_top` 差分**（端口删了但例化里还留着具名连接，只有 elaboration 抓得到，xvlog 单文件解析抓不到）——这一条是今晚 `build/r110_apply_cuts.sh` 拷贝树自测学到的：刀 4 第一版就是被 xvlog 的 `VRFC 10-3380` 抓出来的。

## 链子文案要改口（记一笔，链子在飞不动这个脚本）
`build/r110_chain.sh` 的头与第 26 行 `say` 写着"第二捆：#174 gapclr + #177 死代码 + #158 判据 + 可选刀 4"，
但**本轮真正落进树里的只有刀 1(#174) 与刀 4①(独热化)**：#177 死代码、#158 死口/截断行判据、刀 0(#182) 都没落
（刀 0 有意延后，理由见任务 #183）。这两句会在构建控制台里被当成"本轮内容"念出来 ⇒ 链子跑完后把它们改成实际清单，
并把 #177/#158 明写在"仍待下一捆"。文案与事实分开这件事本仓犯过不止一次（#221 那条"现在是 rNN 读不出来"是同族）。
