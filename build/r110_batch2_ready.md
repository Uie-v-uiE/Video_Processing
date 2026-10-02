# r110 批次（第二捆）—— 三刀都已经**预备完**，只差"树空下来 → 落刀 → 一次构建"

这一页的存在理由：用户要求"所有任务一起开、别一个一个搞几小时仿真"。所以第二捆里每一刀都**已经在不花构建的前提下验过**，
落刀之后只需要一次构建 + 一次顶层台架（一轮只付那 127 分钟一次）。

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
可做的两件事（**只做一件，一轮一个变量**，规矩 #223）：
① 再削一次扇出：r107 那把（位图分组）对 `row_ok` 有效（`fo` 316 → 552/317 那一族重排），这里可对 `rows_hit` 的 CE 用同款；
   但要先量 `rows_hit` 现在是否已经分过组（`grep -n "rows_hit" src/rtl/eth/frame_reasm.v` 读使能项的形状）。
② 物理侧：route 占 82 % 说明大头是**距离/拥塞**，不是算术 ⇒ Pblock/就近放置这一族（r87 实测 route 66 % 那次记过口径）。
   ⚠ 这一条属于路线图 §11.3"约束/策略放最后"，且必须与 ① 分开单独滚，否则收益归不了属。
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
