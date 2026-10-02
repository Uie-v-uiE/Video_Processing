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

## 板子那一半（与刀无关，但挡住采纳）
板子 AP 不可达（`DAP status 0xF0000021`，ISSUES #235）⇒ 需要**断电重上**；恢复后按
`ps_jtag_boot.tcl` → `program_pl.tcl` → `ps_app_reload.tcl` 三道走，逐道看 token，尤其 `DOW:` 必须是 `ok`。
在板子回来之前：`board_verify`、串口电池、`cmd_overflow_probe`、以及所有眼睛判据都挂在欠账里，不许念成完成。
