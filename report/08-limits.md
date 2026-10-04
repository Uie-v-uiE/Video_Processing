# 已知限制与欠账

这一章的每条都写成四行：**症状 / 已证明什么 / 还没证明什么 / 关掉它需要什么**。
分界线画在"已证明"与"还没证明"之间：左边必须指得出件，右边不许被左边的语气带过去。
台账原文按编号在 `report/log/issues.md`，人话版在 `report/known_issues.md`，本章只做交付视角的挑与摆。

## 1. `C5c`：帧头若干行的读侧绕回（`#98`）——台架上唯一一条故意留红的判据

- **症状**：`build/tb_v98_report.txt` 第 55 行每轮都打
  `FAIL C5c frame head is not the previous frame's tail | first OFF+BILIN output rows must carry their own source row on BOTH sides of the seam`；
  板级可见性由队员 2026-10-02 报回（原话与四条补充观测抄在 `report/known_issues.md` §一 第 1 条与
  `board/acceptance.md` E4/E4r 那两行）。
- **已证明什么**：帧头窗那一带有不符、本体行没有——件 `build/evidence/r104_c5head_band.txt` 的汇总行原文
  `judged=本体行 3564 格不符 0 ｜ head rows=帧头窗 36 格 不符 24 ｜ OFF_LINES=4`，
  分列行是"三个采样列各「头 12 格／不符 8」，三个采样列各「体 1188 格／不符 0」"；
  `report/known_issues.md` §一 第 1 条把同一件事念成"错的 8 格全在最上面 6 个显示行
  （`OFF_LINES` 4 加 `BILIN_ROWS` 2）……本体行一格都不错"。警告 版本戳：那份逐格件引的顶层台架是
  `top_md5=2bf2ceeede07`（r104），与 `report/06-validation.md` §2 那份 161 行的 `56c269602e18` 不同一次跑。
  后果的**大小**另有机器尺子 `sim/tb_head_rot_displace.v`（读数 `build/r105_tb_head_rot_displace.txt` 的
  `RESULT tb_head_rot_displace PASS cells=49152 pairs=12 k=1..7`，同一件头部写着
  "「哪几行带着上一帧」由顶层台架 C5c 判，不在这份件里"）；三条解释已被排除（角点出屏由
  `sim/tb_zoom_fit_corners.v` 六档 4/4 命中；`zoom_fit` 与 `angle` 差一整帧；`fb_bilin` 末行末列抽头）。
- **还没证明什么**：那条"改前必须红、改后恰好绿这一条"的**变异对照还不存在**
  （`report/known_issues.md` §一 第 1 条末："留红是有意选择"）；上面那把位移尺子量的是后果大小，
  **不判**"哪几行带着上一帧"——件里自己写着"两份凭据各说各的"。
- **关掉它需要什么**：把读侧绕回窗口从"发请求那一拍"改成"数据写进环那一拍"（第一刀已落 r78），
  这一步落在读口调度上、会同时动数据通路 ⇒ 必须先建那条能红的对照再动 RTL。

## 2. 角度没有机读口（`#185` / `#247`）

- **症状**：`status` 口里那 9 位 `angle`（`src/rtl/top/pl_video_top.v:1046-1049`）在 `system_top.v`
  里只被声明与连接、没有任何读者 ⇒ 综合按 unused 删掉，于是"屏上 `ROT:` 读几"这件事只能靠眼睛。
  凭据 `build/evidence/r111_angle_readback.txt`（那份件里也记了我第一次把 lane0 的健康快照误读成
  `status` 的错）。
- **已证明什么**：上电那一度的**机理**钉住了——`src/rtl/top/system_top.v:260` 这一域的
  `.sys_rst_n(1'b1)` 使复位分支成死支（`report/known_issues.md` §20 写的是 `:250`，
  行号按本次实测改到 `:260`），未修那份网表是 `FDRE INIT=1'b0`
  （`build/evidence/r113_ff_init.txt`），修后 4 颗全 `INIT=1'b1`（`build/evidence/r113_ff_init_probe.txt` + 判定 `build/r113_powup_rejudge.txt`）；
  台架 `sim/tb_v111_key_boot.v` 用夹逼把"只有 1°、不换模式"这个症状钉在 (20 ms, 0.6 s) 那一档。
- **还没证明什么**：r118 上"冷上电后按住 KEY1 到链子跑完再松手应当读 1 度"那一半——
  `board/acceptance.md` E6 那行明写它"只登记'未判'，不写成过"；机器侧仍读不到角度，
  所以 E6 的正读（「0度」，件 `build/evidence/r118_eyes/`）**不是**机器判据。
- **关掉它需要什么**：把 `angle` 变成机读量、不新增跨域、走 lane23 的保留位 `[28:20]`，
  方案已写成 `build/r113_angle_lane_plan.md`；落地之后 E6 才能自动化（`report/known_issues.md` §20 末行）。

## 3. 六个输出脚没有任何 `set_output_delay`（H5 那一半）

- **症状**：`check_timing -verbose` 点名 6 个"没有任何 output delay 的端口"
  `led[0]`、`led[1]`、`tmds_clk_p`、`tmds_data_p[0]`…`tmds_data_p[2]`
  （读数表在 `report/timing/debt_ledger.md` §2 追加的追加；另有 6 条 MEDIUM 是既有 false path 覆盖，
  `report/timing_global.md` §4 那张表把 HIGH/MEDIUM 分开念）。
- **已证明什么**：屏（TMDS）那一路现在报的"MET"**不包含芯片到面板那一段**，而 LED/MDIO
  连"我是假路"那句话都没写过（`report/timing_global.md` §4）；
  "UG471 那本里没有窗数"成立且已从断言升级成**查过的否定**——第 95 页只给 `TMDS_33` 的属性表
  （`report/timing_global.md` §6.4 末；扫描器 `build/tmds_source_scan.py` + 命中件
  `build/evidence/r117/dvi_guide_scan.txt`）。而**窗数本身已经换到源端那一侧取到了**：
  `report/io/hdmi_cts_source_window.md` §一 的结论表把量按"HDMI 1.4 §4.2.4 **Table 4-24**
  + 1.3 / 1.1 同值 + Keysight CTS 项 7-6/7-7/7-8/7-9 + Tektronix 逐句复述"钉住——
  钟↔数据互对偏斜 max 0.20 `Tcharacter`（50 MHz 档 = 4.000 ns）、对内偏斜 max 0.15 `Tbit`（= 0.300 ns）、
  rise/fall 75 ps ~ 0.4 `Tbit`、占空比 40/50/60 %、钟抖动 max 0.25 `Tbit`（= 0.500 ns，
  参考是 §4.2.3.1 那条 4 MHz −3 dB 的理想恢复钟）。该文 §二 开头还纠正了一处前提：
  两颗 LED 在 `src/constraints/rk_zynq7020.xdc:10-11` 是 `LVCMOS33` 而非 `TMDS_33`，
  而 `tmds_*_n` 是**真实单独出脚**的端口（故对内偏斜在本板有物理意义）。
- **还没证明什么**：**一条 `set_output_delay` 都还没进约束**——该文第 5 行自己写着
  "本轮**没有改动任何代码或约束文件**"，所以上面那些数现在是**候选依据**，
  现行覆盖状态仍是"6 个 HIGH 缺口"。也不许写"已按 HDMI CTS 校验"：该文 §四写死了公开性边界——
  CTS 本体挂在 HDMI Adopter Extranet 之后、本工程非 Adopter、`HDMI-TP1.msk` 的几何与逐频点限值表
  拿不到，凡属 CTS 的部分**全是仪器厂商/公开实测报告的转述（代理）**。
  那两颗 LED 更没有窗可套（§2.2 与结论表 #18：HDMI 连接器信号里没有这类指示脚），
  把 TMDS 的 4.000 ns 借过去等于伪造依据；`tmds_*_n` 是否被同一对约束覆盖那一问
  （`report/timing/debt_ledger.md` §2 那句"这一条我没有官方出处（A1 未读）"）仍未答。
- **关掉它需要什么**：4 对 TMDS 按该文 §3.1 的形状落 XDC（参考钟取转发出去的 TMDS 钟道、
  窗 = 0.20 `Tcharacter` = 50 MHz 档 ±4.000 ns，并按同节第二条把板级走线失配从窗里**减掉**而不是忽略）；
  两颗 LED 走 §3.4 的 (b)——登记"对外无采样器、无需窗"并写明理由；
  然后一次带名册差分的构建 + `check_timing -verbose` 复问缺口 6 → 0，
  同时把该文文末那句"未做 HDMI CTS 合规验证"跟着写进交付文档。

## 4. 五个 RGMII 收端点当前没有被约束覆盖（窗退回候选件）

- **症状**：r118 不加载 `src/constraints/r116_rgmii_input_window.xdc`，构建默认打印
  `VP_R116_IO_WINDOW off（RGMII 输入窗留在候选件 …原因见上方注释）`
  （`build/tcl/build_system_axigpio.tcl:45-52`）⇒ `eth_rx_ctl` + `eth_rxd[3:0]` 这 5 个收端点
  回到"没检查"状态（`report/timing/round_r117.md` §〇 末）。
- **已证明什么**：这一族在合法 `τ ∈ [0,31]` 内**关不掉**：hold 要 τ ≥ 44.8、setup 要 τ ≤ 21.8，
  两个集合不相交；去掉那条 0.800 的带只把下界挪到 32.1（`report/log/issues.md` #311，
  曲线件 `build/evidence/r115_window/probe3_console.txt`）。分量的形状：钟网络角间差 **3.411 ns**
  对数据侧两角差 **0.467 ns**（同一件、`report/timing_global.md` §6.1）。
  工具不是坑我：#312 手工算出的"真最坏"是 hold −1.65 / setup −0.85，比报告的 −1.185 / −0.386 更坏。
- **还没证明什么**：**板上真实差额没有数**。不许写"板上真实 hold 差额就是 −0.870"——窗模型自身还有
  `TskewR` 那一行被混用的残余风险（`report/timing/rgmii_window_model.md` §6/§7.5，登记句同时抄在
  `report/timing/round_r117.md` §四与 `report/timing/round_r118.md` §四末）；
  而"报告最优点"与"硅片眼心"不是同一个数：钟网络到 IDDR C 脚的那个 C **这颗片子没测过**
  （`report/log/issues.md` #314，`report/timing/rgmii_window_model.md` §7.5(7) 登记为未定）。
  ⇒ 没查 ≠ 达标，这条已经写在首页那一行里（`report/timing_global.md` §9 第 ④ 条）。
- **关掉它需要什么**：`VP_R116_IO_WINDOW=1` 复现带窗那一版（`build/tcl/build_system_axigpio.tcl:42`
  写的是"一条命令复现"），但那条发布硬门会红；真正关掉它的是第 5 条那一刀，不是再挪一档 τ。

## 5. 唯一还能改变结论的刀是架构那一刀（`#194` → `#311`/`#313`，前置实测还欠着）

- **症状**：`eth_rxc` 收口那 5 格的出口只有一个——把到 IDDR 的捕获钟做短**并且**让它的角间差小下来
  （`report/log/issues.md` #311 末：要 `C_slow − C_fast` 从 3.411 降到 ≈ ≤1.2 才可能有解）。
- **已证明什么**：这一刀**不能单独落**，代价已经先算出来了：捕获沿提前之后 IDDR 与 BUFG 域之间出现
  ~3.07 ns 发射/捕获差，而那一族最重的锥实测要 7.066 ns @ 8.000 ns 周期 ⇒ 预算被吃掉之后大概率违例
  （`report/log/issues.md` #313；周期与锥长见 `build/evidence/r118_after.txt` 的 `eth_rxc` 那一段
  `Data Path Delay: 7.066ns`）；`gmii_rx_clk` 那根广播网扇出 2546
  （`build/evidence/r118_after_roster_probefmt.txt` 的 `FANOUT|fo=2546|net=u_eth/u_rgmii/u_rgmii_rx/gmii_rx_clk`）。
- **还没证明什么**：短钟到底能省多少——BUFIO 的快角 DCD **没测**（`report/log/issues.md` #323：
  本机两本官方手册两遍扫描命中 0 页，这句只到"没筛出来"，不许写成"手册里没有"）；
  `report/timing_global.md` §7 里那句"专用走线 ≈ 0.5 / 0.2 ns"始终标着**尚未实测**，
  它只用来回答"值不值得动"，不支撑任何"已证明"。也不许写"换短钟也关不掉"（同一句理由）。
- **关掉它需要什么**：动手前三件只读事（§7 末列的①②③：BUFIO 慢/快角 DCD 实测、
  `gmii_rx_clk` 的 2546 个负载落在几个时钟区、名册差分把"IDDR→流水线"那一族**单独列一格**），
  然后是一次带一级同步 FIFO 的架构改动，门槛与 r92 当年放弃 BUFR 的理由是同一个。

## 6. 四个域的 WHS 不是同一把尺量出来的（`#265` / `#302`）

- **症状**：全工程只有一行自加不确定度 `set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]`
  （`src/constraints/rk_zynq7020.xdc:50`；`report/timing_global.md` §4"自加不确定度"那一行）。
- **已证明什么**：把同一 0.800 带给每个钟量一次的结果是**全设计 WHS −0.747 / 25,742 失败端点**，
  这条读数在 `report/log/issues.md` #302（标题就写着"第一次被量出来……**测量，不采纳**"）。
  警告 两处件的时刻不同：`report/timing_global.md` §4 那一行末写的"还没跑真件"是 r114 时的话，
  #302 是 r115 夜的真件读数——引用时挑对，别把旧句当现状。
- **还没证明什么**：其余三域在统一口径下的 hold 余量到底是多少（名册里 0.053 / 0.059 / 0.222
  这三格**一分没扣** ⇒ 跨域比大小没有意义，`report/05-timing.md` §7 第 2 条就是这么写的）。
- **关掉它需要什么**：给三个域加同量级的 hold 不确定度（这是**加严**方向），
  台账行 `report/timing/cut_ledger.tsv` 的 C2 现在的状态是 `blocked(no approver for adoption)`，
  且它明写"读数会变小——那是揭示债不是变差；必须与 C1 分开跑"。

## 7. 异步时钟组把四条跨域路从所有尺子的射程里拿走了，而界叠不上去（`#266` / `#276`）

- **症状**：`src/constraints/clock_groups_impl.xdc:28-31` 一条 `set_clock_groups -asynchronous` 三组互斥
  ⇒ 组与组之间完全不做时序分析；全 `src/constraints/` 里 `set_max_delay` 命中 0
  （`report/timing_global.md` §4c 第 1 条，两个来源都是报告与 XDC 原文，不是叙述）。
- **已证明什么**：`report_cdc`（`build/cdc.rpt`）**一条都没念**那四条被组排除的路——不是它们安全，
  是它们不在射程里（§4c）；而且界**叠不到**被排除的时钟对上：把 `set_max_delay -datapath_only`
  写在 `set_clock_groups` 之上之后，`report_exceptions` 的 A/B 两滚表体都是 13 行、
  `-datapath_only` 出现 0 次 ⇒ 四条路一条都没生效（`report/log/issues.md` #276，
  同口径另见 `report/timing/debt_ledger.md` §5）。
- **还没证明什么**：那四条路的**布线 skew 有没有界**——"结构保证"不等于"有界保证"，
  工具可以把格雷码指针的两级 FF 放到对角两端；§4c 点名的那把"列出组间所有跨域寄存器路径、
  条数 ≥ 4 才许出结论、每条要求 `ASYNC_REG` + 覆盖它的界"的尺子，在写这一段时**还没落地**
  （那一节自己标着"这把尺子**还没写**……现在不点名，因为 D4c 会抓'指着盘上不存在的东西'"）。
- **关掉它需要什么**：先加属性与界再谈数字变化（顺序不能反，§4c）；而真正要动的是**排除口径本身**，
  那会改变 WNS 的计算对象 ⇒ 属 H1 的松动，必须单独一轮带名册差分去做，不能靠叠约束顺手完成。

## 8. `TIMING-10` 那条计数不点名对象，所以不能当"属性上没上"的代理（`#262` / `#290`）

- **症状**：`report_methodology` 的 TIMING-9 / TIMING-10 在加了属性之后仍是 1 / 1，
  `Checks found` 仍 446（`report/timing_global.md` §4 那两行，对照件
  `build/evidence/r113_methodology_baseline.rpt` 对 `build/methodology.rpt`）。
- **已证明什么**：`ASYNC_REG` 真上了网表——`u_cdc` 底下 84 颗灰码 FF 里 **0 → 56 颗**带属性
  （件 `build/evidence/r114_async_netlist_pre_console.txt` 与 `build/r114_async_netlist_console.txt`）；
  同时缺属性（#262）与"这一域没复位"（#256）是**两笔不同的账**，原来写在同族是含糊的。
- **还没证明什么**：剩下那 1 条到底指谁——它正文是 `Related violations: <none>`，**不点名**。
  `report/timing/debt_ledger.md` §4 给的更硬：剩下那一处**没有被识别**，格雷码链不是它，
  并把它登记为"未知对象"债务（G12 要求它进下一轮候选，不许"未知原因但绿了"）。
- **关掉它需要什么**：一次新鲜的 `report_cdc -details` 点名到具体那对触发器；
  仓库里那份 `build/cdc_details.rpt` 是 9 月 25 日的**过期件**，§4 明写不能当本轮凭据。

## 9. 验证手段本身的边界：一家仿真器 + 占位原语 + 人眼是外部输入

- **症状**：`report/known_issues.md` §三那张表五行——只有 xsim（ModelSim 许可证判 inconsistent 已不在）、
  `sim/prim/` 是自建行为级占位件、`data/golden/` 的对比图**没有可一键重跑的生成脚本**、
  人眼判据属外部输入、可复现路径只有 `build/sim/run_one.sh` 与 `build/gates.sh`。
- **已证明什么**：这些边界不是猜的：占位件跑出的 OSERDESE2/BUFG 告警**来自占位件不是设计缺陷**；
  非打包数组越界写 xsim 丢弃、硬件按地址位宽截断（`#103` 的来历），所以这一类只用硬件读数收口，
  而且门禁里有一条专门查"台架中有没有没被门住的越界读写"。
- **还没证明什么**：任何"两家仿真都过"的说法今天**不可复现**；
  "与黄金参考逐像素一致"这句不说，因为参考图不能自动生成，只能人工比对。
- **关掉它需要什么**：第二家可 licens 的仿真器（本机没有）；一份能一键重跑的 golden 生成脚本；
  眼睛那一半不需要"关掉"——它是外部输入，`board/acceptance.md` 的正确用法就是把它空着等人点头。

## 10. 端到端时延那一格：读数出口在，数不在

- **症状**：`data/metrics.csv` 有一行"端到端时延,未报,—,—,…本表不填没有复核过的数"，
  而同一张表另一行"端到端时延,核心,33.34,ms"是旧轮的实测行 ⇒ 同名两行、状态不同。
- **已证明什么**：出口是存在的——OSD 的 `Latency` lane 与 JTAG 回读，且板级那一次
  `lat.osd_ms_matches_tot → true`（`build/evidence/r118_board/board_verify_console.txt` 的读回口段）。
- **还没证明什么**：本轮（r118、带流）的端到端时延值。表里那一格写得很硬：
  "取到可信值之前不占权重也不宣称"。
- **关掉它需要什么**：一次带流的同轮测量（发送时刻 ↔ 上屏时刻成对取），然后把那行改口；
  方法逐轮记录在 `board/verify_r87.md` 与 `build/evidence/`。

## 11. 交付身份与"现行句"的漂移（`#332` / `#333`）

- **症状**：r118 的"采纳笔"漏了位流与报告，HEAD 里那块 bit 仍是 r116 的；
  另一件是我为了保险做的那份 `*.md` 备份被行号锚点检查器当成交付文档扫了一遍并判红。
- **已证明什么**：`git show HEAD:build/system.bit | md5sum` 抓到了这件事（`report/log/issues.md` #332）；
  补完之后 HEAD 与工作区对同一块 `cd04907e1369…` 逐位相同，读回件
  `build/evidence/r118_eyes/head_bit_md5.txt`；`report/log/issues.md` #333 给的是"快照落 `*.txt` 或交给 git"。
- **还没证明什么**：**名册逐位相同不等于提交物身份相同**，也不等于那一版的板级/眼睛复验都跟上了。
  `board/acceptance.md` 机器判据那 10 行仍按行记版本（r92/r94/r96/r97 的读数），
  E1/E2/E3/E5 仍是 2026-09-30 / 10-01 在 r92/r93/r101/r103 上的点头 ⇒ 这几格不给 r118 借用
  （`report/timing/round_r118.md` §四末"现行句的基线必须是本版的件"）。
- **关掉它需要什么**：在 r118 上逐行重跑那 10 行与那三格眼睛判据，或把没重跑的各行明确改标
  "本版未验"；同时按 #333 停止在仓库里留 `*.md` 备份（它会自动进入检查器的射程）。

## 本章依据的产物
- `report/known_issues.md`（§一 第 1 条、§20、§二、§三）
- `board/acceptance.md`（机器判据表的版本戳、E1–E6 各行、结论）
- `report/log/issues.md`（#185/#186、#247、#259、#266、#276、#290、#302、#311、#312、#313、#314、#316、#318、#323、#328、#332、#333）
- `report/timing_global.md`（§4、§4c、§4e、§6、§7、§9）
- `report/timing/round_r117.md`、`report/timing/round_r118.md`、`report/timing/round_r116.md`
- `report/timing/cut_ledger.tsv`、`report/timing/loosen_ledger.tsv`、`report/timing/debt_ledger.md`
- `report/timing/rgmii_window_model.md`（§6、§7、§7.5）
- `report/io/hdmi_cts_source_window.md`（§一 结论表、§二 前提纠正、§3.1/§3.4 的约束形式、§四 公开性边界）
- `build/tb_v98_report.txt`、`build/r118_gates_final.txt`
- `build/evidence/r104_c5head_band.txt`、`build/r105_tb_head_rot_displace.txt`、
  `build/evidence/r111_angle_readback.txt`、`build/evidence/r113_ff_init.txt`、
  `build/evidence/r113_ff_init_probe.txt`、`build/r113_powup_rejudge.txt`、
  `build/evidence/r113_methodology_baseline.rpt`、`build/evidence/r114_async_netlist_pre_console.txt`、
  `build/evidence/r115_window/probe3_console.txt`、`build/evidence/r117/dvi_guide_scan.txt`、
  `build/evidence/r118_after.txt`、`build/evidence/r118_after_roster_probefmt.txt`、
  `build/evidence/r118_board/board_verify_console.txt`、`build/evidence/r118_eyes/head_bit_md5.txt`
- `build/tcl/build_system_axigpio.tcl`、`src/constraints/rk_zynq7020.xdc`、
  `src/constraints/clock_groups_impl.xdc`
- `src/host/video_sender.py`（推流侧参数入口，见 `report/reproduce/README.md`）、`data/metrics.csv`
- `sim/tb_head_rot_displace.v`、`sim/tb_zoom_fit_corners.v`、`sim/tb_v111_key_boot.v`（存在性本次逐条核对；
  判据内容按上面点名的件引用）
- `board/verify_r87.md`（第 10 条指的路径，本次核对存在）
