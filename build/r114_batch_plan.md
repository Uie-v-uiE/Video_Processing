# r114 批次计划（全局口径：每一刀都带自己的尺子与代价面，一轮只付一次台架的钱）

写在前面：这份清单是"别只追最差那条"的执行版。每一刀都写四件事——
① 动什么；② 谁来判（尺子 + **改前必须红**的凭据）；③ 代价面（逐时钟名册差分 D1..D6，不看头条 WNS 的绝对差）；
④ 走哪条车道（快车道 = 同一份 `opt.dcp` 重跑 place/route ≈ 7–9 分钟/滚；正式一轮 = 构建 + 31 支车道 + 顶层台架 70–128 分钟）。

## 一、先量的两刀（不动 RTL，只动约束/属性；同一笔构建）

| # | 动什么 | 谁来判（改前必须红） | 代价面 | 车道 |
|---|---|---|---|---|
| 1 | `dc_fifo` 四颗格雷码捕获寄存器打 `ASYNC_REG`（`rgray_s0/s1`、`wgray_s0/s1`，#262） | `build/scan_async_reg_coverage.py`：现在 A2 RED，只点这两处（件 `build/evidence/r113_async_reg_scan.txt`）；打完必须 A2 GREEN 且 A1/A5 计数与名字钉住 | 属性不改网表，但要念 `report_methodology` 的 TIMING-10 计数（当前 1）与名册差分 | 正式一轮（要综合） |
| 2 | 异步组间四条跨域路补 `set_max_delay -datapath_only`（#266：`dc_fifo`、`ddr_bank_commit`、`frame_commit_lock`、`effect_ctrl`） | 尺子**还没写**（写时按 `build/` 命名规矩起，别在此文件提前点名不存在的路径）；判据必须"条数地板 ≥4 + 两维同现（ASYNC_REG 与 max_delay）"，且自带能红的对照 | 组排除下的路径不进 WNS ⇒ **"WNS 没动"是预期不是证据**（rule 35 反面）；要看的是名册里别的域没被挤 | 与 1 同笔构建 |

## 二、I/O 约束这一捆（#259/#267/#268，三个来源三种单位，先对口径再写数）

1. **先问工具**：`check_timing -verbose` 出权威端口名单，把三个现数对到同一套名字上——
   `check_timing` 念 5 输入 + 6 输出（HIGH）、`check_io_timing_coverage.py` 念 2/7 个端口（= 5/12 引脚）、
   `report_methodology` 念 TIMING-18 = 7 条。谁也不许替谁解释（#267/#268）。
2. 然后按 `report/timing_global.md` 第 4b 节的分组配方落约束：TMDS 一路先量面板/走线窗再写 `set_output_delay`，
   数值**必须**有出处（手册或实测），写不出出处就在 XDC 注释里标成估计并给区间；LED/MDIO 各一条**带理由**的声明。
3. 判据收口口径：**I3 与 I7 都要由 RED 转 GREEN，且有 -verbose 名单支撑**；只改绿 I3、把 I7 的期望值改掉 = 假收口。

## 三、物理那一刀（先做单变量 A/B，再谈进不进正式轮）

* 入口 `build/r114_replication_ab.sh`（旧名 `r114_maxfanout_ab.sh` 已是转接）：同一份 `opt.dcp` 滚两遍，
  两遍都 `place → phys_opt → route`，**唯一变量**是 B 多带 `phys_opt_design -force_replication_on_nets`。
* 判据顺序已改成"先证机制能动再谈收益"：V2b `_replica` 对象数 B>A、V2c 名册里至少一根网扇出下降（两个不同来源），
  任一红 ⇒ `MECHANISM_INERT`（这一刀没打到东西），**不许**写成"时序收益不成立"；机制绿后才看 V3 目标族 / V4 名册差分 / V5 资源。
* 尺子自带 `--self` 三条对照，实测 3/3（件 `build/evidence/r114_mf/` 与 `verdict.txt`，跑完回填）。
* 警告：杠杆的名字是量出来的：`set_max_fanout` 在本工具不存在（#264）；`MAX_FANOUT` **属性**那条路还没验过（要开设计 `list_property`），
  所以不许提前写成"已按官方 MAX_FANOUT 做"。

## 四、结构那一刀（fo=305 的 CE 广播，#187 尾）

先配能红的尺子再落刀：目标是 `rok4[51]_i_1_n_0`（fo=305，route 84 %）这根广播的扇出**读数离开 305**，
并同时念 `route_status`/`utilization` 与其余三域（名册差分）。上一版这把"没真降"过（#238），所以判据必须是**计数**而不是"看起来好一些"。

## 五、还欠着的两小笔（同一轮顺手带走，各自带尺子）

* `pl_demo_top` 那棵树里 `snap_cross.hb_gone` 补声明初值（#257 第 2 条；尺子 `build/scan_dead_reset_init.py` 现在念 init_miss=1）。
* 角度机读口（#185）：`ROT:` 现在只能靠眼睛；方案在 `build/r113_angle_lane_plan.md`，落地后 E6 可自动化。

## 六、需要用户点头的一项（测量之后再决定，不是现在猜）

**hold 不确定度要不要给到全部时钟**。现状只 `eth_rxc` 有 `-hold 0.800`，其余三域裸数（#265），
所以四域 WHS 不可比；把同一条带给每个时钟的体检尺子已落地（`build/uncertainty_uniform_ab.sh`，六条判据、`--self` 7 条对照全过），
**但真件还没跑**。跑完若出现"三域翻负"，那是要不要做 hold fixing 的**新范围**，需要单独一次决定——
在那之前谁也不许把负数念成"板子 hold 坏了"（那只是同一悲观带下的 what-if，没重跑布线）。

## 七、纪律（这一轮不许破的）

* 一次构建带多刀，但每刀**各自的判据先红后绿**，红绿凭据都进 `build/evidence/`；
* 不改正在被后台实例执行的脚本（要改就复制新名字）；构建在飞时不动 `src/rtl`、`src/constraints`；
* 门禁项数一旦变（把上面任何尺子接进门禁），必须与"门禁 N 项"那四处句子**同一笔**改（#242/D1c）；
* 采纳笔要含 bit/xsa，刷板后跑 `board_verify --geom --battery --round=r114`，眼睛判据仍归用户。

## 九、变体 A 的判别结果（2026-10-03 16:47，件 `build/evidence/r114_io_varianta_console2.txt`）

只给上升沿的那一版与两沿那一版**每一个数都相同**（WNS 0.424 / WHS −2.885 / 5 个失败 hold 端点、同一落点
`u_iddr_rx_ctl/D`、levels=2、走线 0.000 %）⇒ "窗写重了"被排除，`set_input_delay -clock eth_rxc` 本来就吃这条钟的
全部工作沿。下一刀因此收窄成**一个单变量**：在带窗口径下扫 `IDELAY_VALUE`（现值 26）找眼心，
判据仍是逐钟名册差分（其余三域 1.155/4.206/14.109 与 0.058/0.064/0.133 不许被挤）。

## 八、2026-10-03 16:15 的实测状态（这一节的每一条都有件，不覆盖上面的计划文本）

* §一.1 `ASYNC_REG`：**已落源码**（`src/rtl/eth/dc_fifo.v:23` 四颗一起打属性），尺子
  `build/scan_async_reg_coverage.py` 从 A2 RED(missing=2) 变 GREEN(missing=0, ghost=0)；
  属性只影响实现阶段的挪位/复制，正式名册还要等一轮构建才念得出变化（不许提前念收益）。
* §一.2 四条 `set_max_delay -datapath_only`：**测了，没生效**（ISSUES #276）⇒ 这一刀从"补约束"改判成
  "改排除口径"，需要单独一轮，见 §六之后的那条决定项。
* §二.1 三个来源一个名字集：**`check_timing -verbose` 的权威名单已问到**
  （件 `build/check_timing_verbose.rpt`：HIGH 输入 5 = `eth_rx_ctl` + `eth_rxd[0..3]`；
  HIGH 输出 6 = `led[0..1]` + `tmds_clk_p` + `tmds_data_p[0..2]`；MEDIUM 输入 2 = 两把键；MEDIUM 输出 6 =
  `eth_rst_n/eth_tx_ctl/eth_txd[0..3]`）。
* §二.2 输入侧约束：**写了也量了** —— 加上 ±0.5 ns 的规范窗之后输入欠账 5→0，
  但 `eth_rxc` 的 hold 变成 −2.885 / 5 个失败端点（ISSUES #275）⇒ **候选文件不许接进构建**
  （`build/tcl/build_system_axigpio.tcl` 目前只加 `rk_zynq7020.xdc` 与 `clock_groups_impl.xdc`，已核对），
  下一步先做两个单变量：只给上升沿、以及 `IDELAY_VALUE` 扫档。
  输出侧（TMDS/LED）仍缺规范原文出处，如实挂着，不编数。
* §五 `snap_cross.hb_gone` 声明初值：**已落**，`build/scan_dead_reset_init.py` 从 init_miss=1 变 0
  （`result=CLEAN`，件 `build/evidence/r114_dead_reset_scan.txt`）；该模块不在当前位流那棵树里 ⇒ 时序无感，
  只算补上"复位分支说的值与上电值一致"这条结构欠账（没有专属台架，如实写明）。

## 十、扫档跑完的收口（2026-10-03 18:01，ISSUES #280/#281/#282）

两批扫档把"数据路径能不能关住 hold"判死了：模型 (a) 窗 ±0.5 ns 在 tap 0/13/31 = −4.522/−3.703/−2.570；
模型 (b) 窗"沿后 1.5–2.5 ns"（PHY RX 内部延迟打开）在 tap 0/8/13 = −2.522/−2.018/−1.703，
按实测斜率 63 ps/tap 外推到最大 31 档仍差 ≈0.5 ns（外推值，未实测）。⇒ **§九 那把"扫 IDELAY 找眼心"的钥匙用完了**，
任务 #193 判完成（结论是"这条路关不住"，不是"找到了"）。

下一刀换轴：让 `rgmii_rx` 的 IDDR 吃**更早的捕获钟**（① 回 BUFIO；② 给那只 MMCM 输出加相位偏移），
判据不许改：同一窗下 `eth_rxc` hold ≥ 0 且 `fail_hold=0`、其余三域逐格不比 #282 表格变差；
红就退回 BUFG，并把"BUFG + 真窗关不住"记成实测结论。前置债：`main.c` 没有 MDIO 读命令 + 本机无 arm-none-eabi ⇒
读不到 PHY 的 RXDLY 寄存器（#131/#170），所以这一判只能靠时序实验或原理图脚带，不许用"我记得 PHY 延迟是开的"。
`r114_io_async.xdc` / `r114_io_variantb_phy_delay.xdc` 都不进构建（核对过 add_files 只有两份现行 XDC）。

## 十一、扇出复制那一刀的尺子修复（2026-10-03 18:25，ISSUES #286）

§三 那一刀在 18:11 那一次不是"这一刀没打到东西"，是**尺子断在对象查找层**：名册 41 行全部解析成功、
`get_nets` 一个都没找回（三种 `-filter` 形式在网对象上实测恒空，只有不带 `-hier` 的分层路径写法可用）。
现在（同一份 `system_top_opt.dcp`，只读）：

* 名册行按实测三列形状解析，表头/`Command` 散文行出局；
* 找回后**再核对一次 NAME 字面相等**，核对不过逐条点名计数；
* BUFG/BUFH/MMCM/PLL 驱动的钟网只进名册（差分用）、不进 B 滚变量；
* 新增 `MF_DRY=1` 干跑档：2 分钟先验"解析 + 找回"这一层，实测
  `build/evidence/r114_mf_dry_console.txt` ⇒ `BIG_NETS=39 roster_skipped_clock=1 roster_skipped_name=0`。
* 判据口径修正：网对象**没有** `FANOUT` 属性（实测为空），`get_pins -of` 的数与报告差很远 ⇒
  扇出读数只认 `report_high_fanout_nets` 一家；V2b 的来源是复制单元（cell 对象）、V2c 的来源是布线前后
  两份报告的名册差分——两个来源仍在，但**不是**"三种独立读数"，别再这么写。

## 十二、r114 正式轮的范围（今天收口的口径，动手前先照着念）

飞过的三刀里只有两刀进构建：`dc_fifo` 四颗格雷码寄存器的 `ASYNC_REG`（#262，尺子 A2 已由 RED 转 GREEN）
与 `snap_cross.hb_gone` 声明初值（#257 尾，`scan_dead_reset_init` 由 init_miss=1 转 0，且该模块不在出货网表里）。
**不进**的：`r114_io_async.xdc` 与两份变体（#275/#282/#285：窗一建起来 `eth_rxc` hold 就 −2.885，
这是"约束把没建模的片外窗暴露出来"，不是可直接采纳的修法）；四条 `set_max_delay -datapath_only`
（#276：叠在 `set_clock_groups -asynchronous` 上不产生新异常行 ⇒ #191 改判成"排除范围的决定"，要单独一轮）；
复制驱动那一刀要等 §十一 之后的 A/B 真裁决（`MECHANISM_INERT` / `ADOPT_CANDIDATE` / `DECLINE`）。
⇒ r114 正式轮的判据仍是**名册八对逐格差分**（两刀都是属性/初值级，预期时序中性），
下一把真正的时序刀是 #194（捕获钟），它需要一次自己的正式轮，且判据已写死在 §十。

## 十三、复制驱动 A/B 的真裁决（2026-10-03 18:39，件 `build/evidence/r114_mf/verdict.txt`，ISSUES #288）

`MF-SUMMARY mech=2/2 gain=0.456 cost_red=1 lut_delta=31 verdict=**DECLINE**`。
机制确实能动（复制单元 0→296、`u_pl/u_clk/u_mmcm_0` 扇出 −58），目标族也确实抬了（0.445→0.901），
但名册差分（8 对）里 `eth_rxc/hold` 从 0.050 掉到 0.035（相对余量 −29 %）⇒ D3 红 ⇒ 不采纳。
否决的理由与 §十/§十二 是同一条：这个域的 hold 今天刚被量出"挂上真实窗就是 −2.885"，
所以它现在的余量读数本来就不作数，不能再削。⇒ **这一刀不进 r114 构建**（也没进：构建 18:43 起飞，只带两刀）。
