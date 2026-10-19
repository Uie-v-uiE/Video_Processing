# 已知限制与欠账

这一页的每条按五项读：**现象**（看得见的是什么）、**已定位的原因**（已经证明到哪一步、指得出哪份件）、**还没证明什么**、**现在的处置（是否影响演示）**、**关掉它需要什么**。每条正文里紧跟读数点名的路径就是它的凭据，文末《本页依据的产物》是汇总。
分界线画在"已证明"与"还没证明"之间：前一条必须指得出件，后一条不许被前一条的语气带过去。
逐条缺陷的登记原文按编号在 `report/log/issues.md`（记录文件），人话版在 `report/known_issues.md`，本页只做交付视角的挑与摆；未决项集中登记在 `report/90-open-items.md`，那里不重复编号，这里只给指路。
名词先说一次：文中"检查脚本"指仓库 `src/host/`、`build/checks/` 里可独立复跑的只读核对工具，"发布前检查"指 `build/gates.sh` 逐项打印判定的那套检查，"未通过项"指这些检查打出的 FAIL 行；"候选件"指写好但默认不加载的约束文件；
"名册"指实现后逐时钟、逐域那份端点读数表（`build/evidence/` 里的 roster 件），"名册差分"就是两张表逐格对比。

## 1. `C5c`：帧头那一带的读侧绕回（`#98`）——**已于 r132 关闭**（台账 #129 / #478）

- **关闭的判据读数**：`C5  judged=3564 bad=0 | head rows=36 wrong=0 (OFF_LINES=4, col=512)` 与
  `PASS C5c frame head is not the previous frame's tail`。改前同一把尺子打的是 `head rows=36 wrong=24`
  （= 4 个显示行 × 3 个采样列 × 2 帧），本体行一直是 0。整架两次都是 `RESULT tb_v98_top_seam PASS`、
  165 条 PASS / 0 条 FAIL（通道 ModelSim `vsim`，2026-10-17 11:02:07→12:00:01 是"删旗标"那版树，
  12:00:35→12:34:23 是交付的 `STREAM_WRAP` 版；凭据 `build/evidence/r132_c5c_after_preparam.log`
  与 `build/evidence/r132_shipped_rack.log`）。规范通道（`build/sim/run_one.sh`，xsim）那一次还在跑，
  **跑完之前 `data/metrics.csv` 第 15 行"整屏逐像素判据"不改**。那一格必须由指纹件绑定才算数。
- **关闭之后门禁的形状**：`build/gates.sh` 的 24 项里，`C5c` 曾是那条长期写明过的未通过项——它属于"已知且公开登记"，不是被忽略的失败；关掉之后 r132 这一轮的门禁重跑并全绿，`build/r132_gates.txt` 末行是 `GATES: ALL PASS（24 项全部判定）`。采纳口径是"除声明项外无未通过项"，所以这句话现在才敢念。
- **真因（不是当年写的那条）**：帧头那一带错的不是"带着上一帧的尾巴"，而是**处理抽头发了前瞻一行的格子**。
  四个 3×3 窗口级在 `y_in==0` 时把窗口三行全换成"当前那一拍"的原色（`proc_sobel.v` 的 `d21`、
  `proc_morph.v` 的 `c21`、blur/sharpen 的 `h2x`）。这个补救的前提是"帧头槽位在行缓存里坐的是上一帧末行"，
  而 `#97`/`#98` 把读地址改成帧尾绕回之后，链子吃的是连续流（…298,298,299,299,0,0,1,1,2,2…），
  帧头槽位的中心本来就是它该显示的那一行；"当前那一拍"比槽位自己的中心**早 2 个源行**，因此屏上帧头 4 行错位。
  这一条的因果由 `sim/tb_v103_pipe_bypass.v` 窗口 C 量出来（内容行号进像素 tag、"晚几行"交给拟合）：
  同一激励并行例化两条链、只差 `STREAM_WRAP`，再叠一个 `y_in` 口径的变量，四格读数是
  `anchored 臂A bad=20 first_bad=16（帧头） / anchored 臂B bad=20 first_bad=28（帧尾） /
  wrapped 两臂都 bad=0`，`bestL=4 = u_pipe.OFF_LINES`，因此**换标签只是把带子从屏顶搬到屏底，前瞻抽头才是病**。
- **改了什么**：① 四个窗口级新增参数 `STREAM_WRAP`（默认 0 = 台架那套帧锚定流），为 1 时不武装 `stale_row`；
  `proc_pipeline` 透传，顶层 `pl_video_top.v:819` 传 1。② 顶层 `cy_chain`（`pl_video_top.v:811-816`）
  让链子的行标签与它吃进去的内容同一本账。①②合起来才是这一条的绿：只改②，帧头变帧尾（上面第二格）。
- **当年"故意留红"的口径现在换了形状**：这一条不再需要"留红当未通过项交出"，因为
  **能红的对照已经存在**：`C11d`（`STREAM_WRAP=0` 的锚定实例在同一激励下必须坏）。
  红线画在"调用方声明自己喂的是哪种流"上：`tb_edge_rim` 的 D3/R7 与 `tb_edge_rim_bottom` 的 B1 判的是
  帧锚定那一套契约，它们的既有读数继续有效（`build/evidence/r132_edge_rim_streamwrap0.log` 绿；
  对照件 `r132_edge_rim_red_if_flag_deleted.log` 是把旗标整根删掉那一版的红，两版并档就是这件事的账）。
- **残余代价（不许写成"全部消除"）**：帧头那 4 个显示行的内容是在**上一帧**消隐前读回来的，因此那几行
  位置对、值晚一帧（30 fps 下约 33 ms）。离线**没有**判据能量这一档——台架那幅坐标图逐帧不变，
  `C5b/C5c` 只能看几何。板级可见性只有人眼能给：2026-10-17 队员原话
  「现在很漂亮 基本上看起来没什么问题了 顶上的拖影我肉眼没看到」，因此记为"眼验未见"，
  **不写成"已证明不可见"**。`board/acceptance.md` 的 E2 与 E4r 两行随之需要重读一次（今晚会一并改标注）。
- **这一节原来引的旧件**（`build/evidence/r104_c5head_band.txt`、`build/r105_tb_head_rot_displace.txt`、
  `top_md5=2bf2ceeede07` 那份 55 行报告）保留为历史：它们量的是**后果大小**与当时的错位形状，
  不是现在的状态；现行状态以 §1 上面三段为准。`sim/tb_head_rot_displace.v` 仍只量位移、不判"哪几行带上一帧"。

## 2. 角度没有机读口（`#185` / `#247`）

- **现象**：`status` 口里那 9 位 `angle`（`src/rtl/top/pl_video_top.v:1102`）在 `system_top.v`
  里只被声明与连接、没有任何读者，因此综合按 unused 删掉，于是"屏上 `ROT:` 读几"这件事只能靠眼睛。
  凭据 `build/evidence/r111_angle_readback.txt`（那份件里同时记着一次把 lane0 的健康快照误读成
  `status` 的错，读之前要先认口）。
- **已定位的原因**：上电那一度的**机理**钉住了——`src/rtl/top/system_top.v:260` 这一域的
  `.sys_rst_n(1'b1)` 使复位分支成死支（`report/known_issues.md` §20 写的是 `:250`，
  行号按当前网表复核对到 `:260`），未修那份网表是 `FDRE INIT=1'b0`
  （`build/evidence/r113_ff_init.txt`），修后 4 颗全 `INIT=1'b1`（`build/evidence/r113_ff_init_probe.txt` + 判定 `build/r113_powup_rejudge.txt`）；
  台架 `sim/tb_v111_key_boot.v` 用夹逼把"只有 1°、不换模式"这个症状钉在 (20 ms, 0.6 s) 那一档。
- **还没证明什么**：板上这一版上"冷上电后按住 KEY1 到链子跑完再松手应当读 1 度"那一半——
  `board/acceptance.md` E6 那行明写它"只登记'未判'，不写成过"；机器侧仍读不到角度，
  所以 E6 的正读（「0度」，件 `build/evidence/r118_eyes/`）**不是**机器可判定的读数。
- **现在的处置（是否影响演示）**：角度这一格只有屏上 `ROT:` 一条出口，串口读不到，因此不进机器结论；
  演示里旋转功能照常放，只是改成哪一档要由人报回。
- **关掉它需要什么**：把 `angle` 变成机读量、不新增跨域、走 lane23 的保留位 `[28:20]`，
  方案已写成 角度机读口那份计划件（已随提交包精简删除，不再入库；债仍记在待办台账里）；改完接上之后 E6 才能自动化（`report/known_issues.md` §20 末行）。

## 3. 六个输出脚没有任何 `set_output_delay`（H5 那一半）

- **现象**：`check_timing -verbose` 点名 6 个"没有任何 output delay 的端口"
  `led[0]`、`led[1]`、`tmds_clk_p`、`tmds_data_p[0]`…`tmds_data_p[2]`
  （读数表在 `report/timing/debt_ledger.md` §2 追加的追加；另有 6 条 MEDIUM 是既有 false path 覆盖，
  `report/timing_global.md` §4 那张表把 HIGH/MEDIUM 分开念）。
- **已定位的原因**：屏（TMDS）那一路现在报的"MET"**不包含芯片到面板那一段**，而 LED/MDIO
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
- **还没证明什么**：**一条 `set_output_delay` 都还没进约束**——该文第 5 行的声明就是"没有改动任何代码或约束文件"，
  所以上面那些数现在是**候选依据**，
  现行覆盖状态仍是"6 个 HIGH 缺口"。因此"已按 HDMI CTS 校验"这句话没有依据：该文 §四写死了公开性边界——
  CTS 本体挂在 HDMI Adopter Extranet 之后、本工程非 Adopter、`HDMI-TP1.msk` 的几何与逐频点限值表
  拿不到，凡属 CTS 的部分**全是仪器厂商/公开实测报告的转述（代理）**。
  那两颗 LED 更没有窗可套（§2.2 与结论表 #18：HDMI 连接器信号里没有这类指示脚），
  把 TMDS 的 4.000 ns 借过去等于伪造依据；`tmds_*_n` 是否被同一对约束覆盖那一问
  （`report/timing/debt_ledger.md` §2 那句"这一条我没有官方出处（A1 未读）"）仍未答。
- **量到了哪一格（离散量这一维度）**：HDMI CTS 的 Source 侧 TP1 判据是**眼图掩模 + 抖动 + 占空比 + 边沿速率**，正式表格文本只发给 HDMI Adopter（NDA），公开能引用的只有规范正文与仪器厂商应用笔记的转述。眼图、抖动、占空比、边沿速率需要示波器/探头与合规测试治具，这一维度是 `【未实测】`——没做过眼图级量测，只量到离散参数；板级走线（连接器/线材）对离散的影响也没有单独量过。布线后逐脚实测：互对最差 **0.065 ns**（限 4.000 ns）、对内最差 **0.001 ns**（限 0.300 ns），凭据 `build/evidence/r119_window_check.txt`（含 5 份输入的现算 md5 头），口径与边界见 `report/io/hdmi_tp1_sdc_measurement.md`。出图与推流不依赖这组候选约束，演示路径不受影响；对外口径只到"离散量已测"，不含眼图那四项。
- **为什么 skew 不能直接绑进窗**：`skew ≤ 0.20 Tcharacter` 是**单边的离散上限**，`set_output_delay` 表达的是**双边捕获窗**，两者量纲不同。把前者当后者绑上去，实测直接把三条数据道判成 `−3.48 / −3.46 / −3.47 ns` 的"违反"——量纲用错，不是设计错（登记在 `report/log/issues.md` 第 335 条），发布前检查项不接受这种绑法。
- **现在的处置（是否影响演示）**：屏那一路的对外时序今天仍不出具结论——**一条 `set_output_delay` 都没进默认约束**
  （窗留在候选件里，开关 `VP_R119_TMDS_WINDOW`；**已经量过一轮**：挂上它之后新纳检的 `clkout1_1` 那 6 个输出口
  端点整批红（setup −5.408 / hold −1.923 ns，件 `build/evidence/1006d_tmdswindow_timing_summary.rpt`），
  同一轮四个老域的八个读数里七个变差（唯一变好是 `clkout0_1` 的 setup 3.630→3.945 ns），因此判 DECLINE，
  仍不进默认集；逐域读数在 `report/timing/eth_rxc_partition_options.md` 第 6 节）。
  但"六颗端口一概欠账"这句已经不准确了：`led[0]/led[1]` 与 `eth_mdc`/`eth_mdio` 现在走的是 §3.4 的 (b)——
  在 `build/check_io_timing_coverage.py` 的豁免表里**逐条写了可核的理由与出处**
  （LED 是 `rk_zynq7020.xdc:10-11` 的 LVCMOS33 直驱、无接收时钟；`system_top.v:117` 把 MDC 钉成常量 0；
  `system_top.v:116` 把 MDIO 置高阻），尺子读数从 `bare_out_ports=7` 降到 **4**，剩下那 4 组正是 TMDS。
  受影响的说法仍是"能不能说 HDMI 侧已闭合"。
- **关掉它需要什么**：4 对 TMDS 按该文 §3.1 的形状落 XDC（参考钟取转发出去的 TMDS 钟道、
  窗 = 0.20 `Tcharacter` = 50 MHz 档 ±4.000 ns，并按同节第二条把板级走线失配从窗里**减掉**而不是忽略）；
  两颗 LED 的 (b) 已经做了（见上一条），不再待办；
  然后一次带名册差分的构建 + `check_timing -verbose` 复问缺口 6 → 0，
  同时把该文文末那句"未做 HDMI CTS 合规验证"跟着写进交付文档。绑之前要先定"对外声称符合到哪一档"——档位没定，窗就没有落点。

## 4. 五个 RGMII 收端点当前没有被约束覆盖（窗退回候选件）

- **现象**：板上这一版不加载 `src/constraints/r116_rgmii_input_window.xdc`，构建默认打印
  `VP_R116_IO_WINDOW off（RGMII 输入窗留在候选件 …原因见上方注释）`
  （`build/tcl/build_system_axigpio.tcl:45-52`），因此 `eth_rx_ctl` + `eth_rxd[3:0]` 这 5 个收端点
  回到"没检查"状态（`report/timing/round_r117.md` §〇 末）。
- **已定位的原因**：这一族在合法 `τ ∈ [0,31]` 内**关不掉**：hold 要 τ ≥ 44.8、setup 要 τ ≤ 21.8，
  两个集合不相交；去掉那条 0.800 的带只把下界挪到 32.1（`report/log/issues.md` #311，
  曲线件 `build/evidence/r115_window/probe3_console.txt`）。分量的形状：钟网络角间差 **3.411 ns**
  对数据侧两角差 **0.467 ns**（同一件、`report/timing_global.md` §6.1）。
  这组数不是工具算错：#312 手工算出的"真最坏"是 hold −1.65 / setup −0.85，比报告的 −1.185 / −0.386 更坏。
- **还没证明什么**：**板上真实差额没有数**，因此"板上真实 hold 差额就是 −0.870"这句话现在没有依据——窗模型自身还有
  `TskewR` 那一行被混用的残余风险（`report/timing/rgmii_window_model.md` §6/§7.5，登记句同时抄在
  `report/timing/round_r117.md` §四与 `report/timing/round_r118.md` §四末）；
  而"报告最优点"与"硅片眼心"不是同一个数：钟网络到 IDDR C 脚的那个 C **这颗片子没测过**
  （`report/log/issues.md` #314，`report/timing/rgmii_window_model.md` §7.5(7) 登记为未定）。
  所以这 5 个端点未参与检查，首页那一行就按这个口径写（`report/timing_global.md` §9 第 ④ 条）。
- **现在的处置（是否影响演示）**：默认关着走（开关 `VP_R116_IO_WINDOW` 不开），窗留在候选件里；对外口径念成
  "片内路径零违例 + 收口 I/O 当前无窗"，不念成"收口已通过"。演示不受影响：板上这一版的串口命令电池与
  几何判定都在不带窗的这一版上跑通过（件 `build/evidence/r118_board/board_verify_console.txt`）。
- **关掉它需要什么**：`VP_R116_IO_WINDOW=1` 复现带窗那一版（`build/tcl/build_system_axigpio.tcl:42`
  写的是"一条命令复现"），但那一项发布前检查会判未通过；真正关掉它的是第 5 节那项架构改动，不是再挪一档 τ。

## 5. 唯一还能改变结论的是架构那项改动（`#194` → `#311`/`#313`，前置实测还欠着）

- **现象**：`eth_rxc` 收口那 5 格的出口只有一个——把到 IDDR 的捕获钟做短**并且**让它的角间差小下来
  （`report/log/issues.md` #311 末：要 `C_slow − C_fast` 从 3.411 降到 ≈ ≤1.2 才可能有解）。
- **已定位的原因**：这项改动**不能单独落**，代价已经先算出来了：捕获沿提前之后 IDDR 与 BUFG 域之间出现
  ~3.07 ns 发射/捕获差，而那一族最重的锥实测要 7.066 ns @ 8.000 ns 周期，因此预算被吃掉之后大概率违例
  （`report/log/issues.md` #313；周期与锥长见 `build/evidence/r118_after.txt` 的 `eth_rxc` 那一段
  `Data Path Delay: 7.066ns`）；`gmii_rx_clk` 那根广播网扇出 2546
  （`build/evidence/r118_after_roster_probefmt.txt` 的 `FANOUT|fo=2546|net=u_eth/u_rgmii/u_rgmii_rx/gmii_rx_clk`）。
- **还没证明什么**：短钟到底能省多少——BUFIO 的快角 DCD **没测**（`report/log/issues.md` #323：
  UG471（188 页）与 UG472（114 页）按行筛两遍**命中 0 页**，这句只到"没筛出来"，不能写成"手册里没有"）；
  `report/timing_global.md` §7 里那句"专用走线 ≈ 0.5 / 0.2 ns"始终标着**尚未实测**，
  它只回答"值不值得动"这一个问题，不支撑任何"已证明"。同一句理由也不支持"换短钟也关不掉"这个说法。
- **现在的处置（是否影响演示）**：这项改动没落，收口那 5 格维持第 4 节的现状；网口收流在演示里按不带窗那一版跑，
  影响的是"能不能对外说收口已闭合"，不影响画面本身。
- **时序这一章到此定型（队伍决定，不再投优化轮）**：当前状态是**四个域零违例端点、所有用户约束都满足**
  （`build/timing_summary.rpt:151` 那行给 WNS **0.687** / WHS **0.004** / 失败端点 0 / 总端点 **51027**，`:154` 给 "All user specified timing constraints are met"——这一串是 r132 现读；上一版 r118 是 0.739 / 0.052 / 0 / 51135），继续动它买的是**余量**而不是正确性；而余量的上界已经量到——把最差那一族整族
  搬走最多 +0.278 ns（接棒的是同域那条 85 % 布线主导的使能广播，见
  `report/timing/eth_rxc_partition_options.md` 第 7 节），算术方向三种改法有两把已实测判负（台账 #380 / #382）。
  所以本页**不承诺进一步的时序收益**；上面这几节（第 3–8 节）记的是**声明面的债**，补它们只会让读数变小，
  不因定型而划掉。将来要翻案的门槛也写在那一份的第 8 节里。
- **关掉它需要什么**：动手前三件只读事（§7 末列的①②③：BUFIO 慢/快角 DCD 实测、
  `gmii_rx_clk` 的 2546 个负载落在几个时钟区、名册差分把"IDDR→流水线"那一族**单独列一格**），
  然后是一次带一级同步 FIFO 的架构改动，门槛与更早一版放弃 BUFR 时记的理由是同一个。

## 6. 四个域的 WHS 不是同一套口径量出来的（`#265` / `#302`）

- **现象**：全工程只有一行自加不确定度 `set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]`
  （`src/constraints/rk_zynq7020.xdc:50`；`report/timing_global.md` §4"自加不确定度"那一行）。
- **已定位的原因**：把同一 0.800 带给每个钟量一次的结果是**全设计 WHS −0.747 / 25,742 失败端点**，
  这条读数在 `report/log/issues.md` #302（标题就写着"第一次被量出来……**测量，不采纳**"）。
  注意 两处件不同次：`report/timing_global.md` §4 那一行末写的"还没跑真件"是更早一版时写下的话，
  #302 那条才是带真件读数的一次——引用时挑对，别把旧句当现状。
- **还没证明什么**：其余三域在统一口径下的 hold 余量到底是多少（名册里 0.048 / 0.067 / 0.121
  这三格**一分没扣**，因此跨域比大小没有意义，`report/05-timing.md` §7 第 2 条就是这么写的）。
- **现在的处置（是否影响演示）**：保持只有 `eth_rxc` 那一行带自加不确定度，其余三域一分没扣；因此对外只在同一域内比大小，
  跨域比大小不做（`report/05-timing.md` §7 第 2 条）。演示与时序结论都不受影响。
- **关掉它需要什么**：给三个域加同量级的 hold 不确定度（这是**加严**方向），
  欠账登记行 `report/timing/cut_ledger.tsv` 的 C2 现在的状态是 `blocked(no approver for adoption)`，
  且它明写"读数会变小——那是揭示债不是变差；必须与 C1 分开跑"。

## 7. 异步时钟组把四条跨域路从所有检查的覆盖范围里拿走了，而界叠不上去（`#266` / `#276`）

- **现象**：`src/constraints/clock_groups_impl.xdc:28-31` 一条 `set_clock_groups -asynchronous` 三组互斥
  所以组与组之间完全不做时序分析；全 `src/constraints/` 里 `set_max_delay` 命中 0
  （`report/timing_global.md` §4c 第 1 条，两个来源都是报告与 XDC 原文，不是叙述）。
- **已定位的原因**：`report_cdc`（`build/cdc.rpt`）**一条都没念**那四条被组排除的路——不是它们安全，
  是它们不在检查的覆盖范围里（§4c）；而且界**叠不到**被排除的时钟对上：把 `set_max_delay -datapath_only`
  写在 `set_clock_groups` 之上之后，`report_exceptions` 的 A/B 两滚表体都是 13 行、
  `-datapath_only` 出现 0 次，因此四条路一条都没生效（`report/log/issues.md` #276，
  同口径另见 `report/timing/debt_ledger.md` §5）。
- **还没证明什么**：那四条路的**布线 skew 有没有界**——"结构保证"不等于"有界保证"，
  工具可以把格雷码指针的两级 FF 放到对角两端；§4c 点名的那项要求（"列出组间所有跨域寄存器路径、
  条数 ≥ 4 才许出结论、每条要求 `ASYNC_REG` + 覆盖它的界"）在写这一段时**还没写出来**，
  那一节自己标着"这个检查**还没写**……现在不点名，因为指路检查会抓'指着盘上不存在的东西'"。
- **现在的处置（是否影响演示）**：四条路维持"不在覆盖范围内"的状态，对外不念"跨域已闭合"；
  动约束的顺序是先加属性与界、再谈数字变化（§4c）。演示用的网口与屏都在这四条路之外照常跑。
- **关掉它需要什么**：先加属性与界再谈数字变化（顺序不能反，§4c）；而真正要动的是**排除口径本身**，
  那会改变 WNS 的计算对象，因此属 H1 的松动，必须单独一次带名册差分的构建去做，不能靠叠约束顺手完成。

## 8. `TIMING-10` 那条计数不点名对象，所以不能当"属性上没上"的代理（`#262` / `#290`）

- **现象**：`report_methodology` 的 TIMING-9 / TIMING-10 在加了属性之后仍是 1 / 1，
  `Checks found` 仍 446（`report/timing_global.md` §4 那两行，对照件
  `build/evidence/r113_methodology_baseline.rpt` 对 `build/methodology.rpt`）。
- **已定位的原因**：`ASYNC_REG` 真上了网表——`u_cdc` 底下 84 颗灰码 FF 里 **0 → 56 颗**带属性
  （件 `build/evidence/r114_async_netlist_pre_console.txt` 与 `build/r114_async_netlist_console.txt`）；
  同时缺属性（#262）与"这一域没复位"（#256）是**两笔不同的账**，原来写在同族是含糊的。
- **还没证明什么**：剩下那 1 条到底指谁？它正文是 `Related violations: <none>`，**不点名**。
  `report/timing/debt_ledger.md` §4 给的更硬：剩下那一处**没有被识别**，格雷码链不是它，
  并把它登记为"未知对象"欠账（G12 要求它进下一轮候选，不能写成"未知原因但已通过"）。
- **现在的处置（是否影响演示）**：这一格只登记不结论，对外说法停在"属性已上网表，剩下 1 条没点名"；演示不受影响。
- **关掉它需要什么**：一次新鲜的 `report_cdc -details` 点名到具体那对触发器；
  仓库里那份 `build/cdc_details.rpt` 是 9 月 25 日的**过期件**，§4 明写不能当本版的凭据。

## 9. 验证手段本身的边界：一家仿真器 + 占位原语 + 人眼是外部输入

- **现象**：`report/known_issues.md` §三那张表五行——只有 xsim（ModelSim 许可证判 inconsistent 已不在）、
  `sim/prim/` 是自建行为级占位件、`data/golden/` 的对比图**没有可一键重跑的生成脚本**、
  人眼判定属外部输入、可复现路径只有 `build/sim/run_one.sh` 与 `build/gates.sh`。
- **已定位的原因**：这些边界不是猜的：占位件跑出的 OSERDESE2/BUFG 告警**来自占位件不是设计缺陷**；
  非打包数组越界写 xsim 丢弃、硬件按地址位宽截断（`#103` 的来历），所以这一类只用硬件读数收口，
  而且发布前检查里有一条专门查"台架中有没有没被拦住的越界读写"。
- **还没证明什么**：任何"两家仿真都过"的说法今天**不可复现**；
  "与黄金参考逐像素一致"这句不说，因为参考图不能自动生成，只能人工比对。
- **现在的处置（是否影响演示）**：对外说法只到"一家仿真器 + 占位原语 + 人工比对"，两条越界的话（"两家仿真都过"、
  "与黄金参考逐像素一致"）都不说；演示用的画面与判定都来自这一家仿真与板上读数，不受影响。
- **眼睛与手感那一格怎么签**：需要人眼/手感验收的项（屏上四角、碎影、按键手感、SD 拔卡观感）没有机器可读的输入口
  （旋转角度那一格见第 2 节），所以检查脚本与文档写作侧不代签，由队伍成员签字确认。已收到并如实登记的两条原话是
  **"现在屏幕没问题了四角都在屏幕内"**（E4）与**"0度"**（E6 冷上电读 0，件 `build/evidence/r118_eyes/`）；
  E6 的另一半（按住 KEY1 不放时应当读 1 度）**仍未判**，那一半不写进结论，登记在 `report/60-failure-analysis.md` 的 B4。
  凭据 `board/acceptance.md`、`board/signoff.md`。
- **关掉它需要什么**：第二家可发许可的仿真器（环境里只有 xsim：ModelSim 的许可证由新版 FlexNet 签发、自带客户端判
  inconsistent，`report/known_issues.md` §三第一行）；一份能一键重跑的 golden 生成脚本；
  眼睛那一半不需要"关掉"：它是外部输入，`board/acceptance.md` 的正确用法就是把它空着等人点头。

## 10. 端到端时延那一格：读数出口在，数不在

- **现象**：`data/metrics.csv` 有一行"端到端时延,未报,—,—,…本表不填没有复核过的数"，
  另一行原写"端到端时延,核心,33.34,ms"，2026-10-07 按凭据改名"入流帧间隔（PL 内）"（`gap_sum/gap_segments` 自报 33.3434 ms），因此同名两行的矛盾消失，端到端那一格仍是未报。
- **已定位的原因**：出口是存在的——OSD 的 `Latency` lane 与 JTAG 回读，且板级那一次
  `lat.osd_ms_matches_tot → true`（`build/evidence/r118_board/board_verify_console.txt` 的读回口段）。
- **还没证明什么**：板上这一版带流跑时的端到端时延值。表里那一格写得很硬：
  "取到可信值之前不占权重也不宣称"。
- **现在的处置（是否影响演示）**：那一格留空、不占权重也不宣称，演示不受影响（屏上出图与时延无关）。
- **关掉它需要什么**：一次带流的同次测量（发送时刻 ↔ 上屏时刻成对取），然后把那行改成实测值；
  方法逐轮记录在 `board/verify_r87.md` 与 `build/evidence/`。

## 11. 交付身份与"现行句"的漂移（`#332` / `#333`）

- **现象**：板上这一版被采用时漏登记了位流与报告，HEAD 里那块 bit 仍是上一版刷入时的那块；
  另一件是为保险留的那份 `*.md` 备份被行号锚点检查器当成交付文档扫了一遍并判为未通过。
- **已定位的原因**：`git show HEAD:build/system.bit | md5sum` 抓到了这件事（`report/log/issues.md` #332）；
  补完之后（那是 r118）HEAD 与工作区对同一块 `cd04907e1369…` 逐位相同，读回件
  `build/evidence/r118_eyes/head_bit_md5.txt`；`report/log/issues.md` #333 给的是"快照落 `*.txt` 或交给 git"。
- **还没证明什么**：**端点名册逐位相同不等于提交物身份相同**，也不等于那一版的板级/眼睛复验都跟上了。
  `board/acceptance.md` 里那 10 行机器判定各自带着件内版本戳（那一版是哪一版，戳里写着），
  E1/E2/E3/E5 那几格仍是 2026-09-30 / 10-01 在 r92/r93/r101/r103 那几版上的点头，因此这几格不搬到板上这一版
  （`report/timing/round_r118.md` §四末"现行句的基线必须是本版的件"）。
- **现在的处置（是否影响演示）**：2026-10-18 为 r132 再核一遍——`md5sum build/system.bit` 与 `git show HEAD:build/system.bit | md5sum` 都是 `cb907d3e4898…`，`git cat-file -s HEAD:build/system.bit` = 1975594 = 盘上字节数，因此HEAD 与工作区仍是同一块；仓库里不再留 `*.md` 备份；
  没重跑的行各自带着版本戳交出去，不写成板上这一版的结论。演示按板上这一版实际跑通的那几格走。
- **关掉它需要什么**：在板上这一版逐行重跑那 10 行与那三格眼睛判定，或把没重跑的各行明确改标
  "本版未验"；同时按 #333 停止在仓库里留 `*.md` 备份（它会自动进入检查器的覆盖范围）。

## 12. PS 侧固件：ELF 能重建，但重建那颗要重新上板复验才算板上验证过

- **事实（实测）**：`src/ps/` 可以用一条命令编成可上板的 ELF——
  `PS_CC=<Vitis>/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe PS_BSP=<仓库根>/vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp node build/ps_app.mjs`，
  编译器自述 `arm-xilinx-eabi-gcc (GCC) 13.3.0`，跑完打印 `ENTRY _boot@0x000000cc` 与 `OK`。
  凭据 `build/evidence/1005_ps_app_rebuild.txt`（含逐条命令与两个 md5）。
- **边界**：重跑 `node build/ps_app.mjs` 得到的那颗，与随包并在板上跑过验收的那颗 `d0b07f84a068…` **不同**
  （差在源码比入库 ELF 新；实测数字只记在 `build/evidence/1005_ps_app_rebuild.txt`；那颗更早、由 IDE 侧构建）。
  所以"`src/ps/` 改了"到"板上已修好"之间缺的是**重刷 + `board_verify` 复验**这一步，不是一次编译。
  边界为什么画在这里：md5 不同就是两颗不同的程序，编译通过只证明源码能变成 ELF，不证明板上跑的就是它。
- **两个入口条件**：`PS_BSP` 要给**绝对路径**——Windows 侧 gcc 拿相对路径会去找 `vitis\platform\…\Xilinx.spec` 而读不到该文件；
  `build/ps_app.mjs` 里 `PS_CC` 的默认安装位置与实际安装位置不一致时会直接打印 `FATAL: arm-none-eabi-gcc 不存在`，
  这句只说明默认值没指对，按上面的写法显式给 `PS_CC` 就能编。
- **现在的处置（是否影响演示）**：演示走的是板上那颗已验收的 ELF，重建入口留着不碍事；`src/ps/` 的任何改动在重刷复验之前都不算上板生效。
- **关掉它需要什么**：显式给 `PS_CC`/`PS_BSP` 重建，重刷上板，再跑一遍 `board_verify` 电池并把记录落进 `build/evidence/`；
  板上那颗的身份与逐轮 `board_verify` 记录本来就在 `build/evidence/`。变量表（`PS_CC`/`PS_BSP`/`PS_OUT`）在 `report/build.md`。

## 13. 复现演练：哪些命令是别人可跑的，哪些不是

- **现算读数**：`report/repro-check.md` 的判定分母是 **61 行**，判定列读数 **PASS=49 / FAIL=0 / 未测=12**，
  判定列不成词 **0 行**（先前那 14 行是表形问题：§8.1 把判定写在第 4 列、§9 那张第三轮表根本没有判定列；
  两处都改成了"判定在末列"，换列件是 `build/r124_repro_verdict_col.mjs`，只动列序与一个判定词的写法）。
  这一层由 `node build/checks/check_repo_consistency.mjs` 的 C9 打印，同一份件现在打印的末行是
  `C9 A/B/C 路径复现演练 判 9 项 判定列在内=61 行 PASS=49 FAIL=0 未测=12 判定列不成词=0`，判 PASS。
- **旧口径的读数留在这里**：更早一版 C9 数的是整篇文本里 `PASS`/`FAIL`/`NOT_MEASURED` 的**出现次数**，读出
  `PASS=91 FAIL=30 未测=32` 并据此把 C9 判成未通过。那两个数与本件的条数分母不同源
  （`report/repro-check.md` §1：第一轮 43、第二轮 38、两轮相加 81），
  这条错位本身登记在 `report/claims-vs-evidence.md`。计数口径换成"只读每行判定列"之后 C9 的输入变了，数字随之变；
  保留旧数是为了让手上还拿着旧读数的人能对上账。
- **12 行未测的构成**：路径 B 的 9 行（`B1`/`B1b`/`B2`/`B3`/`B3b`/`B4`/`B4b`/`B5`/`B6`，都要真跑一次构建或全量仿真）、
  结果比对的 `M4`、换 ELF 对照的 `C3c`（见第 12 节：重建那颗与板上那颗 md5 不同），
  以及第三轮那张表的 `C4`：两跑健康计数的原件（`health_r118docround_a.json` 与 `_b.json`）已被记录在案的
  精简笔删掉、不随包，因此正文里那串读数是当时的转述，包内指不到件，所以它不能算成一条判定。
- **现在的处置（是否影响演示）**：交付口径是"环境自检与只读结果比对两类命令可由第三方在本机复跑，上板那一半（JTAG 三步、
  串口电池、推流）已实测跑过"；构建与全量仿真那 10 行需要在场的时间与一次完整构建，不声称第三方可以照抄复现全部结果。
  演示走的是复现说明里"接线、构建、三步上板、推流"那条最短路径。
- **关掉它需要什么**：在场的机器与时间——把路径 B 那 9 行逐条真跑一次构建或全量仿真、补 `M4` 的结果比对；
  `C3c` 要等第 12 节那比重建 ELF 的对照跑完；`C4` 只能重测一次两跑健康计数并留原件。
  凭据 `report/repro-check.md` §1 与 §9（逐条命令、期望输出、实跑摘要、判定）。

## 14. 检查脚本自己的两处不足

- **一处慢到只能记未测**：`build/checks/check_repo_hygiene.sh` 的断链层每 token 派生 4 个进程，因此整脚本 >300 s 未返回，终审 C5 记 `NOT_MEASURED`
  （读数件 `build/evidence/r120_final_gate.txt`）。C1 层已用"一次 awk 替代逐成分派生"修掉
  （同样 400 条路径：266 s 降到 0.14 s，六个计数逐位相同）；C5 层照同一配方还没改，
  登记在 `report/log/issues.md` 第 339 条末段。补齐要跑的：C5 层换同一配方，再重跑终审把读数落件。
- **三处判定口径错位**，未通过项报在检查脚本身上而不是设计上：C2 的取路径正则吞全角标点（6 条未通过 → 0 条）、
  C3 把行文碎片/运行期产物/被 `.gitignore` 排除的学习文档当成"指路"（66 → 3）、
  C1 把"别处引用版本号"当违规（改成只有取值不同才算未通过，并另放一个故意写错的文件来证明它仍会报未通过）。
  教训与规矩写在 `report/log/issues.md` 第 339 条。错位为什么要紧：它把"检查器读法不对"念成"设计有失败"，
  对外口径会被这两个来源不同的红带偏。

## 15. 命名合规没做完

- **现象（现算读数）**：改名之前的那次快照是全仓跟踪文件 **3601 个**，其中 **308 个路径含大写字母**
  （末段含大写 266 + 中间段含大写 45 − 两段都含的 3 = 308），惯例名（README/LICENSE/NOTICE/Makefile/.git\*）
  点名豁免 22 个，因此检查脚本报 **违规=286**。改名波之后同一条命令读到 `跟踪文件=3666 违规=10 点名豁免=72`，
  判据是"违规=0 才算过"，因此这一项仍未通过。
- **已定位的原因**：计数从 230 涨到 286 的增量在交付文档自身新增的路径——`git diff --name-status HEAD~2 HEAD` 现算得
  新增 61 条含大写段的路径、删掉 1 条。
- **现在的处置（是否影响演示）**：惯例名已点名豁免，其余要改名会断 `build/frozen_r*/MANIFEST` 的 md5 配对
  （目录名随构建轮次变化，属不可逆连带面），因此待裁决，不挡演示。
  逐段核对方法与第一次对账的登记见 `report/log/issues.md` 第 337 条，裁决问题记在 `report/90-open-items.md` §2A 编号 4（Q-P21-2）。
- **关掉它需要什么**：先裁 Q-P21-2——要么改名并重建各轮 MANIFEST 的 md5 配对，要么把豁免规则写进判据本身；
  判据"违规=0 才算过"在裁决前不改口。凭据：`node build/checks/check_repo_consistency.mjs` 的 C4 那一行、`build/evidence/r120_final_gate.txt`。

## 16. 工具版本绑定的东西

- **现象**：全部时序/资源数字来自 **Vivado/Vitis 2025.2.1（build 6403652）** 与 **xc7z020clg484-2** 这一颗器件
  （权威声明：`report/declarations.md`）。
- **边界在哪、为什么**：数字是那一版工具与那一颗器件算出来的，不是器件无关量。换版本或换器件，`ps7_init`、BD 地址、
  实现策略与**全部发布前检查项的读数作废**；7 系列原语（`IDDR/IDELAYE2/IDELAYCTRL/OSERDESE2/MMCME2_BASE`）在别的家族整段失效。
- **现在的处置（是否影响演示）**：演示与复现步骤都按这一版工具走，各条读数不外推到别的版本；
  复现说明第一篇就是版本与器件的环境自检，跑一遍即可确认一致。
- **凭据**：`build/timing_summary.rpt`、`build/utilization.rpt`、`build/power.rpt`、`report/declarations.md`。

## 17. 行为层面的已知缺陷

| 现象 | 状态 | 凭据 |
| --- | --- | --- |
| 收侧 ARP/ICMP 没有错误源（判不了"收到的东西坏了"这条路） | **未修**。顶层把**原始** `gmii_rx_dv`/`gmii_rxd` 直接交给 `u_arp`（`src/rtl/eth/eth_udp_video_top.v:129-131`）与 `u_icmp`（`:142-144`），而同一份顶层 `:186-192` 已经产出带 FCS 判定的干净流给视频那条路 ⇒ ICMP 校验和只采不验（`src/rtl/eth/icmp_rx.v:240-241` 存下 `icmp_checksum`，全模块没有一处比较它）、ARP 学到的地址被误码帧钉死。正常链路下不触发 | `report/known_issues.md` §17、`report/60-failure-analysis.md` A8、`report/log/issues.md` 第 205 条 |

两条**曾经**登记在行为缺陷表、现在已修并有复验读数的，写在这里防止被念成未修：

- **SD 播放中拔卡画面永久冻帧、插回不恢复**（`report/log/issues.md` 第 94 条）：修法是给 PS 片源补心跳与清零条件
  （心跳在 `src/ps/main.c:253`，读失败那一拍停心跳在 `:271-277`，卡插回自动重挂在 `:1590`），
  复测原话"拔下 SD 卡已经可以重新播放画面，并且串口也回应了这个自动重挂的消息"登记在 `report/known_issues.md` §四。
- **一条 0 字节 `ping` 把 ICMP 应答器永久打死**（第 216、218 条）：根因在收侧 `src/rtl/eth/icmp_rx.v` 的
  `st_rx_data` 出口条件在 0 载荷时回绕，修法是把 `total_length == 28` 记成旗标（`src/rtl/eth/icmp_rx.v:210`）
  并让该状态当拍收束（`:261`）；台架 `sim/tb_icmp_rx_len.v` 钉住这一族。板级复验读数在 `build/r104_board_ping.txt`：
  普通 `ping -n 4` **4/4**、`ping -l 0` **3/3**、`ping -l 32` **4/4**，全部 0 % 丢失；
  同一族在 `build/r114_board_ping.txt` 重读过一次，同样 4/4、3/3、4/4。

ARP/ICMP 那一行怎么补：给收侧接上与视频那条路同一份带 FCS 判定的干净流（顺带让 `icmp_checksum` 真的被比较、
让 `u_arp` 不再被误码帧钉死学到的地址），补完要在带误码的链路上复验一次；登记原文按第 205 条走。

## 本页依据的产物
- `report/known_issues.md`（§一 第 1 条、§20、§二、§三）
- `board/acceptance.md`（机器判据表的版本戳、E1–E6 各行、结论）
- `report/log/issues.md`（#185/#186、#247、#259、#266、#276、#290、#302、#311、#312、#313、#314、#316、#318、#323、#328、#332、#333、#335、#337、#339、#205、#216/#218、#94、#478）
- `report/timing_global.md`（§4、§4c、§4e、§6、§7、§9）
- `report/timing/round_r117.md`、`report/timing/round_r118.md`、`report/timing/round_r116.md`
- `report/timing/cut_ledger.tsv`、`report/timing/loosen_ledger.tsv`、`report/timing/debt_ledger.md`
- `report/timing/rgmii_window_model.md`（§6、§7、§7.5）
- `report/io/hdmi_cts_source_window.md`（§一 结论表、§二 前提纠正、§3.1/§3.4 的约束形式、§四 公开性边界）
- `report/io/hdmi_tp1_sdc_measurement.md`（第 3 节离散量的口径与边界）、`report/repro-check.md` §1 与 §9（第 13 节逐条命令与判定）、
  `report/claims-vs-evidence.md`（第 13 节旧计数错位的登记处）、`report/build.md`（第 12 节 `PS_CC`/`PS_BSP`/`PS_OUT` 变量表）、
  `report/declarations.md`（第 16 节工具版本与器件的权威声明）、`report/90-open-items.md`（Q-P21-2，第 15 节的裁决问题）、
  `board/signoff.md`（第 9 节眼睛原话的签收面）
- `build/tb_v98_report.txt`、`build/r118_gates_final.txt`、`build/r132_gates.txt`（第 1 节门禁末行）
- `build/evidence/r104_c5head_band.txt`、`build/r105_tb_head_rot_displace.txt`、
  `build/evidence/r111_angle_readback.txt`、`build/evidence/r113_ff_init.txt`、
  `build/evidence/r113_ff_init_probe.txt`、`build/r113_powup_rejudge.txt`、
  `build/evidence/r113_methodology_baseline.rpt`、`build/evidence/r114_async_netlist_pre_console.txt`、
  `build/evidence/r115_window/probe3_console.txt`、`build/evidence/r117/dvi_guide_scan.txt`、
  `build/evidence/r118_after.txt`、`build/evidence/r118_after_roster_probefmt.txt`、
  `build/evidence/r118_board/board_verify_console.txt`、`build/evidence/r118_eyes/head_bit_md5.txt`
- `build/evidence/r119_window_check.txt`（第 3 节逐脚离散）、`build/evidence/1005_ps_app_rebuild.txt`（第 12 节重建记录）、
  `build/evidence/r120_final_gate.txt`（第 14/15 节终审读数）、`build/r104_board_ping.txt` 与 `build/r114_board_ping.txt`（第 17 节板级复验）
- `build/ps_app.mjs`、`build/r124_repro_verdict_col.mjs`、`build/checks/check_repo_hygiene.sh`、`build/checks/check_repo_consistency.mjs`、
  `sim/tb_icmp_rx_len.v`、`src/ps/main.c`、`src/rtl/eth/eth_udp_video_top.v`、`src/rtl/eth/icmp_rx.v`（第 17 节行号锚点逐条对原文）
- `build/tcl/build_system_axigpio.tcl`、`src/constraints/rk_zynq7020.xdc`、
  `src/constraints/clock_groups_impl.xdc`
- `src/host/video_sender.py`（推流侧参数入口，见 `report/70-reproduce.md` §4 上板）、`data/metrics.csv`
- `sim/tb_head_rot_displace.v`、`sim/tb_zoom_fit_corners.v`、`sim/tb_v111_key_boot.v`（存在性逐条核对过；
  判定内容按上面点名的件引用）
- `board/verify_r87.md`（第 10 条指的路径，核对存在）
