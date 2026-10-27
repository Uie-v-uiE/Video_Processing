# D→C→B 时序测试链（2026-10-05 午起，逐条单变量）

**目标**：用户指定按 D→C→B 的顺序把 `eth_rxc` / 对外时序这三条候选各量一次，每条一个变量，
判据统一是**同生成器逐时钟名册差分**（`build/roster_from_summary.sh` 各出一份名册 +
`build/timing_roster_diff.sh` 配对；八对 (时钟,类型) 必须全配上，floor=8）。
规矩 35：WNS 的绝对差不算收益也不算损失；判的是**逐域相对余量**——目标域要变好、别的域不许变差。

---

## D：对外 I/O 约束（先做，因为它把"未声明"变成"有界"）

**D1 变量**：把 HDMI 源端 TP1 窗进实现 ⇒ `VP_R119_TMDS_WINDOW=1`。
- 启动（已发起，2026-10-05 14:43 本地）：cwd=`build/tcl`，
  `VP_VIVADO_BIN=<Vivado>/bin VP_R119_TMDS_WINDOW=1 VP_OUTDIR=build/isolated_1006_d_tmdswindow`
  `vivado.bat -mode batch -nojournal -source build_system_axigpio.tcl`
  控制台：`build/isolated_1006_d_tmdswindow/build_console.txt`
  （第一次启动我用错了 `-logfile`——Vivado 没这个选项，秒退；仓里的写法是 `-mode batch -nojournal -source` +
  shell 重定向，见 `build/adopt_after_chain.sh:87`、`build/pre_readings.sh:41`。**别再猜命令行语法**。）
- 约束内容（`src/constraints/r119_hdmi_source_window.xdc:51-52`）：
  `set_output_delay -clock clkout1_1 -max 4.000 / -min -4.000 [get_ports {tmds_data_p[*] tmds_data_n[*]}]`
  参考钟身份：四条 TMDS 串行器的 CLK 脚（该文件 `:29` 说明），周期 4.000 ns = 250 MHz。
- 要读的三件：
  1. `build/isolated_1006_d_tmdswindow/timing_summary.rpt` 名册（与 `build/timing_summary.rpt` 配对差分）；
  2. `node build/r119_window_check.mjs`（TP1 窗的专用尺子，含 `--self` 能红对照）；
  3. `report_io` / `route_status`，以及**告警类计数**（新增的失败端点要逐条列，不能只念 WNS）。
- 预期与判读口径（先写下来，防止读数出来后再找说法）：
  - TMDS 6 个输出脚此前"零声明"，绑窗后**很可能出现 setup/hold 违例**——
    r116 那轮 G1/H5 就是"0…31 全档无解 + 角间差 3.411 ns"，那是**器件边界**，不是设计错；
  - 出现违例 ⇒ 这一条写成 `DECLINE`：候选件继续留在仓里但**不进默认构建**，
    并如实记"对外窗已被量过、量到的失败端点是哪几个、为什么发布门拒绝它"；
  - 不出现违例且别域不动 ⇒ 才谈得上采纳；采纳要过 `build/gates.sh` 全 24 项 + 上板复验才写"板上已验"。

**D2 变量（D1 落定之后，不与 D1 混在一轮）**：`led[1:0]` / `eth_mdc` / MDIO 的处置声明。
- 这三组**没有对外时序接口可引**（LED 是 DC 驱动、MDIO 在本设计里没有 app 侧读命令）。
  诚实做法不是编一个窗，而是写一份 `src/constraints/r120_led_mdio_nontiming.xdc`：
  逐脚说明"无外部时序界 ⇒ 不声明 `set_input_delay`/`set_output_delay`"，并给出**为什么这样处理是安全的**依据；
  同时把这条判断挂到 `时序债务账` 的债目上（#259 的尾）。
- 判据：`build/checks/check_repo_consistency.mjs` 的 C3/C4、`开发流水账` 的清单一致性。

## C：`#194` RGMII 捕获钟提前（BUFIO 或 MMCM 相移）
- 前置事实：#57 已把 IDDR 捕获钟放到共享 fabric BUFG（BUFIO 用量 1→0，skew 1.616→0.013–0.349 ns，
  `IDELAY_VALUE` 15→26），r116/r118 用带窗口径下扫到眼心 τ=31。
- **单变量**：只动捕获钟的相位/来源，不动 `IDELAY_VALUE`、不动输入窗声明。
- 判据必须成对：`eth_rxc` 的 setup **和** hold 一起看，外加输入窗是否仍包住 τ=31
  （`build/evidence/` 里有窗扫描的现成件可对照）。BUFIO 快角 DCD 本机仍未实测（#323）——
  如果这条刀要引 BUFIO 的 DCD 数据，就先记 `未量`，不许用二手转述填。

## B：发侧协议栈解耦（TX 独立 125 MHz）
- 依据：`rgmii_tx_clk` 是 PL 输出端口（`src/rtl/eth/eth_udp_video_top.v:25`），`gmii_tx_clk` 与
  `gmii_rx_clk` 现在是同一根（同文件 `:5` 的时钟域注释）。
- 这一步会**新增跨域**（RX 事件触发 TX 包：ARP 请求→应答、echo→reply），所以顺序上必须：
  ① 先做只读的跨域清单（哪些信号会越界、各自现有同步形态）；② 再动 RTL；
  ③ 台架（`tb_icmp_rx_len`、`tb_link_monitor`、顶层 `tb_v98`）先红后修；④ 构建 + 名册差分；⑤ 门禁 + 上板。
- 这条的代价最大（一整轮），也是唯一真正打"域过载"的；D 与 C 做完再上它。

## 每一轮都要留的东西（不许省）
1. 产物目录 `build/isolated_<日期>_<刀名>/`，至少留 `timing_summary.rpt`、`route_status.rpt`、`utilization.rpt`、
   控制台（**`.bit`/`.xsa` 被 `.gitignore` 挡着**，所以凡是要被文档引用的读数必须落在 `.rpt` 里或复制进 `build/evidence/`，
   否则包里的指路会落空——#383 已经踩过一次）。
2. 名册三件：基线名册、本轮名册、差分输出，落 `build/evidence/`。
3. 台账一行（`开发台账`），带读数、判据、采纳/回退、以及**没量到的部分**。
4. 若回退：`git checkout --` 之后用 md5 对回 `git show HEAD:<file>`，把等式写进台账。

## 补：C 的一手限制（2026-10-05 读到，写在被改的那只模块头上）
`src/rtl/eth/rgmii_rx.v:19` 记着"**数据侧没有出口：IDELAY 从 26 加到最大 31 档只买到 0.43 ns**"，
同文件 `:17` 记这只 BUFG 的 `DCD = 5.008 ns、SCD = 0`，`:22` 记三个 tap 斜率读数互不一致（≈63 ps、≈88 ps、CTS 口径）。
所以 C 的正确第一步不是构建，而是**把算术写成判据**：可用档数 = 31 − 26 = 5 ⇒ 可补偿上限约 0.32–0.44 ns；
而"提前捕获钟"想要的移动量级是当年 BUFIO→BUFG 那 **1.683 ns**（`:7`）——**5 档买不起**。
⇒ 结论：C 先不排队做构建，按"方向被器件档数封死"记录；要翻案必须先给出 `Δ` 与每档实测值的依据，
或者改成"整条钟树一起动相位"（那是另一个单变量，要动 BD 里的 MMCM 参数 + 重过 CDC 与台架）。
