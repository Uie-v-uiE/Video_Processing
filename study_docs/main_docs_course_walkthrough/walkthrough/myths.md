# myths.md · 易混淆对照表：本工程真会撞上的 14 对

读完这篇能回答哪三个问题：

1. 眼前这两个名字（或两个读数）是不是同一件事？差别在哪一句、在本工程哪一处能被看见？
2. 把它们认成对方，会让我把哪一句错的结论写进报告或说给评委？
3. 我现在手上这份文件 / 这一份报告，跑哪一条命令、看哪一列，能当场把它定性？

## 目录

- 第 1 节 这一篇的读法：每条五层 + 收录取舍
- 第 2 节 总表：14 对混淆、一眼判据、主证据
- 第 3 节 翻转位 vs 电平同步
- 第 4 节 WNS vs 实际延迟
- 第 5 节 饱和 vs 回卷
- 第 6 节 仲裁 vs 优先级
- 第 7 节 BRAM（片上块 RAM）vs 片外 DDR
- 第 8 节 场频 vs 像素钟
- 第 9 节 lane 读回 vs 屏上那一格
- 第 10 节 `udp_tx`「接着但没人启动」vs「能用」
- 第 11 节 丢字 vs 丢包 vs 坏包（三个计数器）
- 第 12 节 「0 失败端点」vs「时序有余量」
- 第 13 节 约束存在 vs 约束有射程
- 第 14 节 工具估算结温 vs 板上实测温度
- 第 15 节 串行钟名里的 `5x` vs TMDS 的 `10x`
- 第 16 节 行环的「环深」vs「延迟行数」
- 第 17 节 本篇的未确认清单与去处
- 第 18 节 小结与下一步
- 第 19 节 自测题

## 第 1 节 这一篇的读法：每条五层 + 收录取舍

这一篇只做一件事：把**这个仓库里真的会让人念错的两两成对的东西**摆开。每条固定五层，
与 `glossary.md` 第 1 节讲的五层阶梯同形（术语表：`glossary.md`）：

| 层 | 这一篇里回答的问题 | 硬性形式 |
|---|---|---|
| ① 零术语版 | 不用行话说一遍 | 必须紧跟一句「这样说会在 X 情形下误导你」 |
| ② 误认成对方会得到什么结论 | 错在哪句话上 | 写成一句会被念出口的错话 |
| ③ 两边的精确定义 | 各自的口径是什么 | 通用原理带出处（文档号 + 核对日期）；工程事实带 `文件:行` |
| ④ 在本工程哪一处能观察出差别 | 打开哪个文件看哪一行、翻到报告的哪一列 | 至少一个 `文件:行` 或一个报告字段名 |
| ⑤ 怎么当场排除 | 可执行的辨认动作 | 写成「打开 X，看 Y，出现 Z 就是它」 |

收录规则三条：

1. **只收本工程真撞上的**。判据是：能指出一个 `文件:行` 或一份 `build/report/*.rpt` 的列，
   在那里两条说法会给出不同读数。指不到的不写。
2. **不重复别的篇目**。`glossary.md` 已经把每个术语的五层走完（词条 6、11、14、16、19、20、22 等），
   `design-choices.md` 已经写完每一处取舍的代价账，`clocking-and-reset.md` 已列 16 条跨域点。
   这一篇只写"配对与观察点"，同一句话不抄第二遍。
3. **口径不一致的地方如实报，不替任何一方圆场**。第 3、11 条里各有两处注释与现役连线对不上，
   按规范写成"现象 + 两种解释 + 怎么区分"，并登记进第 17 节。

小结 1：读法 = 先看第 2 节总表定位自己那条，再跳到对应小节把 ④ 与 ⑤ 做完；
只做 ① 等于没做，因为 ① 的作用只是让人听懂，判据全在 ④⑤。
小结 2：比喻在本篇只出现在概念首次引入处，且紧跟一行「（比喻，不是实现；实现见 文件:行）」；
全文只用了 1 次（第 5 节的车速表）。下一步：第 2 节。

## 第 2 节 总表：14 对混淆、一眼判据、主证据

| 条 | X vs Y | 一眼判据（哪个符号/哪一列） | 主证据 |
|---|---|---|---|
| 3 | 翻转位 vs 电平同步 | 端口名带 `tog` 且下游有 `a ^ b` = 翻转位；直接用一个三级链末位 = 电平 | `src/rtl/util/ps_publish.v:25`、`src/rtl/top/pl_video_top.v:262` |
| 4 | WNS vs 实际延迟 | 单位：ns 的名册列 vs 拍数/ms 的 lane 读数 | `build/report/timing_summary.rpt:151`、`src/rtl/video/frame_latency.v:2-3` |
| 5 | 饱和 vs 回卷 | 读数钉在满量程（`0xFFFF`）= 饱和；从 0 重来 = 回卷 | `src/rtl/eth/link_monitor.v:87`、`:90-92` |
| 6 | 仲裁 vs 优先级 | 换手条件里有没有 `busy` 项 | `src/rtl/util/src_arb.v:48`、`:67-76` |
| 7 | BRAM vs 片外 DDR | 出现 AXI 地址与 HP0 端口 = 片外 | `src/rtl/eth/ddr_bank_commit.v:9-10`、`build/report/utilization.rpt:106` |
| 8 | 场频 vs 像素钟 | 59.5 Hz 是除法结果，50 MHz 是时钟周期 | `data/metrics.csv:3` |
| 9 | lane 读回 vs 屏上那一格 | `lane24` 的 bit17（配对完成位）与 bit16（钳位位） | `src/host/health_read.mjs:416-421`、`:532-537` |
| 10 | `udp_tx` 接着 vs 能用 | 例化那行的 `.tx_start_en()` 实参 | `src/rtl/eth/eth_udp_video_top.v:166` |
| 11 | 丢字 vs 丢包 vs 坏包 | lane0 / lane8 / lane1 高低半 16 位 | `src/rtl/eth/link_monitor.v:187-198` |
| 12 | 0 失败端点 vs 时序有余量 | `check_timing` 的 `no_input_delay` 计数行 | `build/report/timing_summary.rpt:99`、`:151` |
| 13 | 约束存在 vs 约束有射程 | 构建日志里那句 `VP_R116_IO_WINDOW off/loaded` | `build/tcl/build_system_axigpio.tcl:57-63` |
| 14 | 估算结温 vs 实测温度 | `Confidence Level` 行是不是 `Low` | `build/report/power.rpt:40-41`、`data/metrics.csv:28-29` |
| 15 | `5x` vs `10x` | `DATA_WIDTH=10` 与 `DATA_RATE_OQ="DDR"` 同时出现 | `src/rtl/hdmi/tmds_serializer.v:2-3`、`:16-18` |
| 16 | 环深 vs 延迟行数 | 参数 `LINES` 与 `localparam RLOG` 是两个数 | `src/rtl/video/raw_line_delay.v:9`、`:41-43` |

小结 1：14 条里有 6 条（3、5、9、11、12、14）的判据是"看同一个字段的第几位/哪一列"，
其余 8 条的判据是"看某一行的实参或某个数是不是除法得来的"。
小结 2：这一篇只给判据，不给改法——改法在 `design-choices.md` 对应节。下一步：逐条展开。

## 第 3 节 翻转位 vs 电平同步

**① 零术语版**：有一种跨时钟域的线，它传的不是"现在是 1 还是 0"，而是"我又翻了一次"——
对面看到它变了，就算收到一次。另一种线传的就是"现在是开着还是关着"，对面随时看都行。
**这样说的误导处**：当"开着"这件事本身只持续一拍（一个事件的痕迹）时，第二类线会整件事看不见；
反过来，当对面这段时间没空接收时，第一类线会把两次事件并成一次。精确版见下一层。

**② 误认成对方会得出什么错误结论**

- 把翻转位当电平读：会念成"这一帧的发布请求还挂着，可以随便什么时候搬"——
  实际上 `ps_publish` 的注释明写连着两次发布会被**合并**，第二次不再生效
  （`src/rtl/util/ps_publish.v:6-8`）。按"电平=随时有效"设计，就会在 PS 连发两帧时以为屏上会出两次刷新。
- 把电平当脉冲用：会念成"这个控制位只在事件那一拍有用，错过就没了"——
  而 `src/rtl/eth/eth_udp_video_top.v:275-276` 给 `gapclr` 的口径是"它是准静态控制位、不是脉冲，
  所以同步后直接当电平用，不需要握手"。按脉冲去做握手，就会为一条清零线多加一对跨域配对。

**③ 两边的精确定义**

| 名字 | 定义（本工程的写法） | 出处 |
|---|---|---|
| 电平同步 | 慢变量直接打三拍，取最后一级当新域的电平；语义 = "此刻是什么" | `src/rtl/top/pl_video_top.v:254-259`、`:262`（`bilin_en_pix = be2`） |
| 翻转位 + 边沿检测 | 源域每发生一次事件就把一根线取反；目的域把这条线打三拍后取相邻两拍异或，得到"新事件"脉冲 | `src/rtl/eth/ddr_bank_commit.v:37-41`（取反）、`:42-47`（`fd_axi = fd1 ^ fd2`） |
| 两者的混合形态 | 准静态宽总线 + 翻转沿：整拍写好总线、同拍翻转，对面在沿那一拍采一次 | `src/rtl/eth/snap_cross.v:3-5`、`:45-46`、`:71`；术语表条目 `glossary.md` 第 8 条 |

通用侧（多位总线不许顺手打过去、要传事件要么变电平要么走握手）在本仓库的正式口径写在技能卡
`skills/rtl/cdc-and-async-discipline/SKILL.md:33-37`，其反面教训在 `:80`
（"用几级同步器同步脉冲：接收钟周期长于脉冲宽度时事件整拍丢掉；要传事件就变电平或走握手"）。
工具层为什么要求这条链待在同一处，见 `glossary.md` 词条 5（`ASYNC_REG`）。

**④ 在本工程哪一处能观察出差别**

| 观察点 | 位置 | 看到的形态 |
|---|---|---|
| 电平那一支 | `src/rtl/top/pl_video_top.v:254-262` | 三颗寄存器 `be0/be1/be2`，末级直接命名成 `*_pix`，没有异或 |
| 翻转那一支 | `src/rtl/eth/ddr_bank_commit.v:37-47` | 先有"事件→取反"的一条 always（`:38-41`），再有三颗 `fd0/fd1/fd2` 与一根 `fd_axi = fd1 ^ fd2` |
| 两类的复位值 | `src/rtl/top/pl_video_top.v:254-262` 取 **1**、`:264-276` 的 OSD 开关链取 **0** | 电平链的复位值决定"PS 没写过时屏上是什么样"；翻转链没有这个问题，因为它看的是变化 |
| 被合并的那一次 | `src/rtl/util/ps_publish.v:29-31` | `pend` 在 `new_tog` 时置 1、`consume` 时清 0，顺序有意：刚到又消费时请求不被吃掉 |

**⑤ 怎么当场排除**

打开那条跨域线的**目的域**代码：搜 `^`（异或）。

- 出现 `wire xxx = a[1] ^ a[2];` 这种形式（例：`snap_cross.v:45-46`、`ddr_bank_commit.v:47`）⇒ 翻转位，
  一次事件对应一个脉冲，**连着两次事件会被合并成两次脉冲但消费方只有排队一格**（`ps_publish.v:14`）。
- 三级链的末级被直接 `wire` 成一个 `*_pix`/`*_axi` 名字（例：`pl_video_top.v:262`）⇒ 电平语义，
  它的值代表"此刻"，不代表"发生过"，所以**必须**是慢变量。
- 再问一句"这条线会不会只高一拍"：会 ⇒ 不许当电平读；答案在端口名带不带 `tog`
  （`ps_publish.v:12`、`snap_cross.v:17-18` 全带）。

一处口径不一致要如实报（本次未区分）：`src/rtl/eth/link_monitor.v:4-5` 的文件头写
"板上唯一会吃掉数据的通道是 CDC 写口被 `fifo_full` 挡住那一拍（`p_good` 在顶层硬接 1）"，
而 `src/rtl/eth/eth_udp_video_top.v:238` 那一行写 `p_good` "从此是真值（原来是 1'b1）"。
两种解释：① 文件头属 V7.9.6 之前的旧轮，注释没跟着删；② 现役连线里 `p_good` 还有另一条被钉死的路径。
区分方法：见第 11 节第 ⑤ 层的三步排除法，本次按第 11 节的方式二核，本节先只登记冲突。

小结 1：这两类的分界不在"打几拍"（都是三级），在**目的域有没有那个异或**。
小结 2：拿到一条新跨域线，先问"它只高过一拍吗"——是 ⇒ 必须走翻转或握手，判据与反面教训见
`skills/rtl/cdc-and-async-discipline/SKILL.md:33-37`、`:80`。下一步：第 4 节。

## 第 4 节 WNS vs 实际延迟

**① 零术语版**：时序报告里那个正数说的是"每条连线都还有多少空闲时间没用到"，
不是"一帧从网口走到屏幕要多久"。前者是**余量**（术语表：`glossary.md` 词条 11），后者是**时长**。
**这样说的误导处**：当有人把"余量 +0.739 ns"念成"延迟不到 1 ns"时，两个数量级差 4 万倍
（0.739 ns 对 33.34 ms）；这一句误导只在跨单位时发生，同一张表里不会。

**② 误认成对方会得出什么错误结论**

会念成："WNS 是正的，所以这一帧上屏只花零点几纳秒，实时性没问题。"
错在：WNS 描述的是**一个时钟周期内**某条路径还差多少没吃掉；一帧上屏要等的是
"提交 → 消隐窗口 → 整帧搬运 → 下一帧开始扫描"这一串**帧级**的事，它的读数单位是拍数，
换算成 ms 之后是 20 / 33.34 / 51 ms（一轮 600 帧）这一档（`data/metrics.csv:25`）。

**③ 两边的精确定义**

| 名字 | 口径 | 本工程取值与出处 |
|---|---|---|
| WNS（worst negative slack） | 全设计最差那条路径的裕量；正 = 满足该路径的时序要求 | `build/report/timing_summary.rpt:151` 的 `WNS(ns)` 列 = `0.739`；同格 `TNS Failing Endpoints` = `0`、`TNS Total Endpoints` = `51135` |
| 实际延迟（端到端） | 上位机发出该帧的时刻 → 屏上出现该帧的时刻 | `data/metrics.csv:25`（min/avg/max = 20 / 33.34 / 51 ms，一轮 600 帧，凭据 `report/perf_report.md`） |
| 链路内时延（PL 内部三段） | c1 = 提交→起拷、c2 = 起拷→搬完、c3 = 搬完→开始扫描；输出是 **axi 拍数** | `src/rtl/video/frame_latency.v:2-4`（"输出一律是 axi 拍数，换算在读的那一侧做"）、`:4`（口径只量 PL 内部，c3 分辨率 = 一个显示帧 ⇒ 报数带 ±1 帧） |
| 换算点 | 100 MHz ⇒ 1 拍 = 10 ns，只在一处写 | `src/host/health_read.mjs:399`（`NS_PER_CYC = 10`，注释写明"换 fclk 频率只改这里"） |

**④ 在本工程哪一处能观察出差别**

- 报告的列名：WNS 只出现在 `WNS(ns)` / `TNS(ns)` 这两列（`build/report/timing_summary.rpt:151`、
  逐时钟名册 `:181-188`）；ms 或拍数**从来不在这份报告里**。
- 时延的数字在另外两个地方：串口 `[LAT]`/`[STAT]` 一类回显与 JTAG lane24..29
  （`src/host/health_read.mjs:394-397` 列出五条 lane 各自的含义）。
- 一处"看时序数字猜不出来的事"：拷贝超出一个消隐窗口这件事的判据是**拍数**，
  `src/rtl/top/pl_video_top.v:446` 的 `VBLANK_AXI_CYC = 32'd67200` 与 `:450`
  （`row_done && row_copy_cycles > VBLANK_AXI_CYC` ⇒ `copy_overrun`，粘滞在 `led[0]`）。
  WNS 是正的并不能让这条判据变绿。
- 一处"两个都有余量却仍然慢"的形态：`data/metrics.csv:20` 那一格现在写的是 `未报`——
  本表拒绝填没复核过的数；同一份表 `:25` 那行是另一轮（600 帧）的读数。
  把它们混着念就是把某一轮的工况当所有轮的结论。

**⑤ 怎么当场排除**

问一句"这个数的**分母**是什么"：

- 打开 `build/report/timing_summary.rpt`，看 `WNS(ns)` 列 ⇒ 分母是"一个时钟周期内的一条路径"。
- 打开 `src/host/health_read.mjs`，看到变量名以 `_cyc` 结尾（`:428-430`）⇒ 那是拍数；
  以 `_ms` 结尾 ⇒ 已经过 `NS_PER_CYC` 换算。
- 打开 `data/metrics.csv`，看该行的"单位"列与"测量条件"列：`ns` + "一次布线后报告" ⇒ 时序名册；
  `ms` + "一轮 600 帧" ⇒ 端到端测量。单位与条件同时相同才是同一个量。

小结 1：WNS 是"周期内还剩多少"，延迟是"跨周期要等多少轮"；本工程里前者在报告的列上，
后者在 lane 的拍数上，两边永不相减。
小结 2：这一对的通用侧（建立/保持时间的物理含义）在 `next-layer.md` 没有单独列，
因为 `glossary.md` 词条 11 已走完五层。下一步：第 5 节。

## 第 5 节 饱和 vs 回卷

**① 零术语版**：一个计数器数到装不下时，有两种停法——钉在最大不动了（饱和），
或者掉回 0 从头数（回卷）。这一篇里"掉回 0"是本工程明确禁止的一种行为，
而"钉住"是刻意做的。比喻一次：**车速表跑到刻度尽头停在尽头，是饱和；转一圈回到 0，是回卷**
（比喻，不是实现；实现见 `src/rtl/eth/link_monitor.v:87`、`:90-92`）。
**这样说的误导处**：钉在尽头不是"精确值"，它只说"至少这么大"；把尽头当精确读数，
就是把一个下界念成了实测。

**② 误认成对方会得出什么错误结论**

会念成："lane4 的高 16 位（`gap_max`）读回 0，说明最大帧间隔很小，链路很稳。"
错在：0 恰是回卷后的读数。`src/rtl/eth/link_monitor.v:50-51` 把这条病史写在注释里——
"16 位回卷曾把 `gap_max` 永久污染，且之后更大的间隔读起来反而更小 ⇒ 两个方向都说谎"。
反过来说，读到 `0xFFFF` 时正确结论是"至少 65535 ms（≈65.5 s）"，不是"正好 65535"
（判据文字在 `src/host/health_read.mjs:59`，同类口径在 `:451-453` 的 `n_meas_saturated`）。

**③ 两边的精确定义**

| 名字 | 写法 | 出处 |
|---|---|---|
| 饱和（本工程选择） | 比较后夹到满量程：17 位计数器的第 16 位一旦置起就报 `16'hFFFF` | `src/rtl/eth/link_monitor.v:87`（`gap_new`）、`:112`（`!gap_cnt[16]` 才加）、`:90-92`（三个 16 位字段各自 `> 0xFFFF ? 0xFFFF`） |
| 自由运行计数器 + 上限保护 | 另一个字段用"不等于满量程才加" | `src/rtl/eth/link_monitor.v:151`（`ms_tick && stall_ms != 16'hFFFF`） |
| 回卷（本工程两处实例） | 16 位减法在 0 载荷时 wrap：`tx_data_num - 16'd1` 变 65535 | 记录在 `report/known_issues.md:266-270`（条目 `#188`），改后代码注释留在 `src/rtl/eth/icmp_tx.v:352` |
| 回卷（第二类，位宽不够） | 10 位字段装不下 1024 ⇒ 变成 0 | `src/host/health_read.mjs:107-110`（0.25x 的期望 1024 被夹到 1023）、`:228-229` 的 `S5b` 判据 |
| 粘滞（第三种） | 事件发生过就一直保持，直到重新加载 bit | `src/rtl/top/pl_video_top.v:443-452`（`copy_overrun`）；术语表 `glossary.md` 词条 19 |

**④ 在本工程哪一处能观察出差别**

- 读数的**形状**：饱和的读数会长期等于该字段的满量程（`0xFFFF`/`0xFF`），
  且多个字段同时钉住（`lane1` 的高/低半、`lane2`、`lane26` 各半 16 位）；
  回卷的读数会"比上一次更小"，甚至回到 0。
- 判据位置：`src/host/health_read.mjs:489-493` 专门把"单调计数器**变小**"标成
  `撕烈：<== 单调计数器变小了` 并计入 `torn`，注释 `:50` 说明非单调 lane（gap/flags/stall）
  两遍不等属正常——这两类在同一个脚本里分开判，就是"饱和/回卷"与"跨域采到刷新"的交界。
- `gap_max` 终身保持这件事的另一半证据：`src/host/health_read.mjs:42-45` 解释为什么要给 `--gapclr`
  入口（不清零就只能当"自启动以来"看）。

**⑤ 怎么当场排除**

- 打开 `src/host/health_read.mjs` 的 `--json` 输出（`:362-473`）：
  某个 16 位字段等于 `65535` ⇒ 饱和，按"至少"念；
  同一个字段两次读取且**第二次更小** ⇒ 先怀疑回卷，再看 `flags` 位（`bit0..bit4`，`:470-471`）
  是否同时翻转。
- 打开 RTL：搜 `? 16'hFFFF` 这种三目（`link_monitor.v:90-92`）⇒ 饱和是**写出来的**；
  找不到这种式子的计数器，就要自己数位宽（`icmp_tx.v:352` 那一族的教训是没数到 16 位减法会退到 65535）。

小结 1：健康统计里 16 位字段一律饱和不回卷，理由写在 `link_monitor.v:88-89`
——"回卷到 0 会被读成'没问题'，这是比少报更坏的错"。
小结 2：念任何一个钉住的读数时，把"至少"两个字一起念。下一步：第 6 节。

## 第 6 节 仲裁 vs 优先级

**① 零术语版**：优先级是"谁资格高谁先走"，仲裁在这里还多问一句"现在换人会不会把正干到一半的活打断"。
**这样说的误导处**：如果只看"资格高"，就会以为"改了控制字屏幕立刻归我"；
本工程把这两件事分开了，改控制字只改变**想要**，不改变**换手时刻**。

**② 误认成对方会得出什么错误结论**

会念成："给 PS 打了 `src 2`（钉住 SD），屏幕这一帧就归 PS 了。"
错在：`src_arb.v:41-43` 的注释把这一条写成"最容易想到的写法，也是错的"——
直接在输出上加一个多路选择器会在一次拷贝中途把选择位翻掉，留下半开的 AXI 读突发。
真实行为是：手动锁只改 `eth_wanted`（`:51`），主人只在两个引擎都空闲时换（`:67-76`），
往 PS 方向还要再多等 20 ms 静默（`T_OFF_CYC`，`src/rtl/util/src_arb.v:19-20`
接在 `src/rtl/top/pl_video_top.v:421`）。

**③ 两边的精确定义**

| 名字 | 定义 | 本工程的落点 |
|---|---|---|
| 固定优先级（组合选择） | 一组请求按预先写死的顺序选中一个，不看被选中者是否处在一次传输中间 | `src/rtl/eth/eth_ctrl.v:143-158`（`protocol_sw` 三态：UDP > ICMP > ARP），出口多路选择 `:92-96` |
| 带互锁的所有权仲裁 | 判据（谁该拿）与时机（能不能换）分家，只在 `both_idle` 那一拍写主人位 | `src/rtl/util/src_arb.v:48`（`both_idle = ~row_busy & ~fill_busy`）、`:67-76` |
| 滞回 | 往某一方向让位要额外静默若干拍 | `src/rtl/util/src_arb.v:61-64`（计数器只服务"往 PS 让位"这一方向） |

**④ 在本工程哪一处能观察出差别**

- 观察点在**同一份回读里**：`lane30` 同时给了主人位与两个 busy 位
  （组装行 `src/rtl/top/pl_video_top.v:603`，位序解释 `src/host/health_read.mjs:71-85`）。
  纯优先级不会有 busy 参与判决，因此这一格里"主人没换但 `eth_live` 翻了"就是互锁在起作用。
- 观察点二：`why_ps` 三位是**判决那一拍的输入快照**，不是当前输入
  （`src/rtl/util/src_arb.v:35-39`、`:73`）。若把它当"现在的输入"念，就会误判成"判据说谎"。
  台架 `sim/tb_src_arb_why.v` 的 `W5`/`W7` 成对钉这两件事（注释在 `src_arb.v:69-72`）。
- 反面对照：`src/rtl/eth/eth_ctrl.v:139-141` 的注释记了 ARP 那一支为什么从"任一空闲"
  改成"两个 busy 都为 0"——那是一次把优先级修得像仲裁的改动，理由写在同一行
  （旧写法会在帧中间把多路选择切走，正在发的那帧作废）。

**⑤ 怎么当场排除**

打开那个决定"归谁"的 always 块：

- 判决条件里出现 `busy`/`idle`/`drain` 这类"活干完没"的项（`src_arb.v:48`、`:67`；
  `axi_frame_writer_gated.v:115-121` 的排空态）⇒ 这是**带互锁的仲裁**。
- 条件里只有请求位与一个写死的先后（`eth_ctrl.v:151-158`）⇒ 这是**优先级**。
- 再问"中途改输入会不会立刻改变输出"：会 ⇒ 优先级；不会 ⇒ 仲裁。本工程的答案
  能在 `lane30` 上量到（第 ④ 层第 1 条）。

小结 1：`src_arb` 与 `src_mode` 是两套编码，顶层用一行适配器翻译
（`src/rtl/top/pl_video_top.v:171`，警告在 `src_arb.v:27-28`）——改一套时另一套不动，就会得到
"钉住了但屏上没换"的观察，这正是仲裁不是优先级的证据。
小结 2：想复现"半开突发"的坏结果，看第 10 节 `udp_tx` 那条的 ⑤；那边是另一种"接了但不可达"。
下一步：第 7 节。

## 第 7 节 BRAM（片上块 RAM）vs 片外 DDR

**① 零术语版**：一种存储长在芯片里面、容量按"块"数得出来、读写不用发总线命令；
另一种长在芯片外面，读它必须先发一条带地址的请求并等回答。
**这样说的误导处**：把"不用发命令"读成"不用等"——片上 RAM 也要一拍读出
（`src/rtl/video/frame_buffer_w64.v:3` 写"读延迟 = 1 个时钟"）；两者只是等的量级不同。

**② 误认成对方会得出什么错误结论**

会念成："帧缓存和收包缓冲都在芯片里，所以上屏不需要挑时间，随时都能整帧搬。"
错在：本工程把**收到的整帧放在片外 DDR 的乒乓两块**里
（`src/rtl/eth/ddr_bank_commit.v:9-10` 的 `0x1000_0000` / `0x1008_0000`），
显示侧要的是**片上那块帧缓存**（`src/rtl/video/frame_buffer_w64.v:1-2`、`:37-38` 强制 `block`），
中间那一次 DDR→帧缓存的整帧搬运**只在消隐窗口做**，超窗就把 `led[0]` 变成快闪
（`src/rtl/top/pl_video_top.v:443-452`）。不认这件事，就会去问"为什么屏上会有水平缝和拖影"，
而答案正是"拷贝跨了两个消隐期"。

**③ 两边的精确定义与出处**

| 对象 | 容量口径 | 访问方式 | 本工程出处 |
|---|---|---|---|
| BRAM tile（片上块 RAM） | 全片 140 个，本设计用 95.5 个（68.21 %） | 地址直接进、下一拍出数据 | `build/report/utilization.rpt:106` 的 `Block RAM Tile` 行；`data/metrics.csv:10` |
| 分布式 RAM / LUTRAM | 用 LUT 做小容量：4044 个 LUT 用作分布式 RAM | 同上，但深度上不去 | `build/report/utilization.rpt:38`；映射原因见 `build/report/methodology.rpt:32`（SYNTH-5 = 336 条） |
| 片外 DDR | 每帧 307200 B，三块 bank（乒乓 2 + PS 专用 1） | AXI4：发 `AR` → 收 `R` 数据拍，16 拍一次突发、4 个在途 | `src/ps/main.c:41-46`、`src/rtl/axi/axi_frame_writer_gated.v:25-35`、`:40-47` |

**④ 在本工程哪一处能观察出差别**

1. 报告列：`utilization.rpt:106` 只有片上 BRAM 的用量；DDR 的用量**从来不出现在资源表里**，
   它出现在**地址常量**（`ddr_bank_commit.v:9-10`、`main.c:46` 的 `0x10100000u`）与
   **AXI 端口**（`axi_frame_writer_gated.v:25-35`）上。找一件存储属于哪一类，就找它的地址或它的 AXI 口。
2. 时间形状：片上那块的读口没有"窗口"概念（`src/rtl/process/bilin/fb_bilin.v:65-68` 直接一个读口）；
   片外那块必须等窗口，窗口预算用拍数写死（`pl_video_top.v:446` 的 `67200`）。
3. 工具口径的一处必须报出来的不一致：`build/report/methodology.rpt:2210` 把
   `u_pl/u_raw/g_ring.mem_reg_0` 写成 `implemented as a RAM block`，
   而 `report/04-resources.md:58-59` 把原图行环归进"走 LUT-RAM 的直接代价"。
   两种解释：① 那一行写的是更早一轮；② 那一行误并了两处。
   区分方法：复跑 `report_methodology`，看 `u_raw` 出现在 SYNTH-5（分布式）还是 SYNTH-6（块）。
   本次未复跑 ⇒ 只登记冲突，`design-choices.md` 第 6 节同一条以"当前 methodology 件"为准。

**⑤ 怎么当场排除**

- 打开 `build/report/methodology.rpt`，搜那个数组的名字（如 `g_ring.mem_reg_`、`u_cdc`、`u_fb`）：
  命中 `SYNTH-5` ⇒ 分布式 RAM；命中 `SYNTH-6` 且句子里有 `RAM block` ⇒ 片上 BRAM。
- 打开 `src/rtl/**`，搜 `ram_style`：`= "block"`（`dc_fifo.v:20`、`frame_buffer_w64.v:37-38`、
  `fb_bilin.v:142`、`:184`）⇒ 写的人指定放片上；`= "distributed"`（`axi_frame_writer_gated.v:53-54`）
  ⇒ 指定放 LUT；找不到属性 ⇒ 交给工具按约束判（`src/rtl/video/raw_line_delay.v:51`）。
- 若这件存储带一个 `0x1xxx_xxxx` 的地址并通过 `m_axi_ar*` / `m_axi_aw*` 访问 ⇒ 它是片外 DDR，
  与 BRAM 无关。
- 数 2 的幂那一条也算辨认法：数组深度非 2 幂会让 BRAM 用量翻倍
  （`src/rtl/video/frame_buffer_w64.v:4-7`，对照件 `tmp_ramtest/fbtest.v`：128 → 80 个 RAMB36）。

小结 1：本工程里"片上 vs 片外"不是一句容量比较，而是三种可观察的差别：
报告里的行、有没有 AXI 端口、要不要挑消隐窗口。
小结 2：换题目时最常被误认的就是这一对——想省掉那台搬运机，就得把整帧搬到片上，
代价见 `design-choices.md` 第 6 节那一栏。下一步：第 8 节。

## 第 8 节 场频 vs 像素钟

**① 零术语版**：像素钟是"每秒钟送多少个格子"，场频是"每秒钟画完整几幅"。
一幅由很多行、每行很多格子组成，而且每行、每幅后面都还有一段不画东西的空歇，
所以两个数永远差着一大截。
**这样说的误导处**：说"每秒钟送多少个格子"会漏掉"其中只有 1024/1344 在画东西"——
空歇期那些拍子也在送，屏幕不显示；用格子数去除时把空歇算进去才对
（`src/rtl/video/video_timing.v:26-27`）。

**② 误认成对方会得出什么错误结论**

两种错话都在本工程出现过：

1. "面板是 50 MHz，所以是 50 帧每秒。" —— `data/metrics.csv:3` 的测量条件列明写
   `H_TOTAL 1344、V_TOTAL 625 ⇒ 场频 59.5 Hz（50 MHz ÷ 1344 ÷ 625，#153：不是 50 Hz）`。
   把 50 MHz 当 50 Hz，差 1200 倍。
2. "场频 59.5 Hz ⇒ 我们的 30 fps 输入会掉帧。" —— 场频是扫描的重复率，
   片源交付是另一件事（一次提交只在 `frame_start` 触发一次拷贝，
   `src/rtl/top/pl_video_top.v:559` 的 `pub_consume = frame_start && src_use && !owner_eth_pix`）。
   30 fps 与 59.5 Hz 之间不是"必须整除"的关系。

**③ 两边的精确定义**

| 名字 | 定义 | 出处 |
|---|---|---|
| 像素钟 | 一个显示格子的节拍，本工程 50 MHz（周期 20.000 ns） | `src/rtl/clocks/clk_gen.v:2`、`:22`（`CLKOUT0_DIVIDE_F = 20.000` ⇒ 50 MHz）；名册列 `build/report/timing_summary.rpt:169`（`clkout0_1` 周期 20.000） |
| 一帧的总拍数 | `H_TOTAL × V_TOTAL`，含消隐 | `src/rtl/video/video_timing.v:26-27`；栅格参数在 `src/rtl/video/video_timing_1024x600.v` |
| 场频 | 像素钟 ÷ (H_TOTAL × V_TOTAL) | `data/metrics.csv:3`（1344、625 ⇒ 59.5 Hz） |
| `frame_start` | 落在**第一个有效像素**那一拍，不是行首空歇 | `src/rtl/video/video_timing.v:68`；被 `pl_video_top.v` 用作换角与消费的同一时刻（注释 `:276` 起那段 #167 记录） |

**④ 在本工程哪一处能观察出差别**

- 读数列：`data/metrics.csv:3` 的"测量条件"列把除法整条写出来；
  `build/report/timing_summary.rpt` 的 `Clock Summary` 只有周期，没有帧率——**报告里搜不到"Hz 帧率"**。
- 空歇期真的在消耗拍子：`src/rtl/video/raw_line_delay.v:58-62` 记的就是
  "一行 1344 拍而有效列只有 1024 ⇒ 尾部那 320 拍"引发的 #102 根因（探针件 `r80` 的 P100）。
  如果 1344 与 1024 是同一个数，这条注释与那台探针都不会存在。
- 拷贝窗口的预算用的是 **axi 拍数**，不是 ms：`pl_video_top.v:446` 的 `67200`
  旁边那行注释（`:443`）写的是"25 行 × 1344 像素 × 2 axi 拍"——这里同时出现 1344（含消隐的行宽），
  是"场频口径"而非"像素口径"的证据。

**⑤ 怎么当场排除**

打开 `data/metrics.csv` 第 3 行：

- "单位"列是 `MHz` 且条件列里有 `÷ 1344 ÷ 625` ⇒ 这一格给的是像素钟，帧率要自己算；
- 出现 `@59.5` 这种写法（第 4 行 `1024×600 @59.5`）⇒ 那是场频，不是钟；
- 要看某段等待多久：先问"这个数在哪个域数"（像素拍 / axi 拍 / ms tick），
  三者的换算在 `pl_video_top.v:446`、`link_monitor.v:36`（`TC = CLK_HZ/1000`）、
  `health_read.mjs:399` 三处各自写着。

小结 1：场频是除法的结果，像素钟是除法的一项；本工程的两个数分别是 59.5 Hz 与 50 MHz，
差 1200 倍，任何一个演示口径都不该把它们并成一格。
小结 2：这一对与第 15 节的 `5x/10x` 是同族错——都是把"节拍名"当"频率值"。下一步：第 9 节。

## 第 9 节 lane 读回 vs 屏上那一格

**① 零术语版**：屏上那一格是**画给眼睛的**，JTAG 那条 lane 是**读给脚本的**。
本工程把它们接成"同一个数"是有条件的：必须同一轮、同一个快照、按固定顺序读。
**这样说的误导处**："同一个数"不等于"同时看到"——它们各自跨了一次域，
屏上那一格还要再过一级寄存（`src/rtl/top/pl_video_top.v:987`）。

**② 误认成对方会得出什么错误结论**

会念成："屏上 `Latency:12` 说明回读 lane24 也是 12，报告随便写哪个都行。"
错在：这条同源关系要同时满足三件事才成立，`src/host/health_read.mjs:416-421` 逐条判：
`pair_ok=1`（武装那一拍的除法已收工）、本轮未钳位（`sticky=0`）、`q_tot` 不是饱和值。
少任何一条，`:534-537` 打印的是"这一组不可判 / 本轮不可判 / 不一致"，
并把话说到"别把屏上那个数写进报告"这一句。

**③ 两边的精确定义**

| 通道 | 口径 | 出处 |
|---|---|---|
| JTAG lane 读回 | lane 号写在 GPIO_0 的 `bit[31:27]`，数据从只读 GPIO_1 取；不加新从设备 | `src/host/health_read.mjs:9-15`；mux 在 `src/rtl/top/system_top.v:238-245`，出口 `:247` |
| 武装（一次读把五个字抄成一组） | `lat_arm = (lane == 25)` ⇒ 指到 lane25 这件事本身就是快照触发 | `src/rtl/top/system_top.v:236`；为什么要武装：`:232-235`（#59 逐 lane 各读各的会读到不同轮） |
| 屏上那一格 | axi 域算好的 ms 跨回像素域，由 OSD 画 | `src/rtl/top/pl_video_top.v:963-987`（含 `lat_ok_pix = … & ~lat_gone`）；OSD 文字位 `src/rtl/video/osd_overlay.v:304`（`Latency:`）、`:315`（`Temp:`） |
| 屏上没可信读数时 | 画 `--`（不是画 0，也不是画上一轮） | `src/rtl/video/osd_overlay.v:473`；温度那一格同规矩 `src/ps/main.c:92-93` |

**④ 在本工程哪一处能观察出差别**

- **顺序**本身是判据：`src/host/health_read.mjs:328-334` 的注释写"24 必须排在 25 之后"，
  并把 `want` 数组按 `…, 25, 26, 27, 28, 29, 24, 23, 30, 31` 排定；
  把 24 提到 25 前面 ⇒ 拿到的是上一遍武装的那一轮 ⇒ 同源判据恒红（假红，脚本自造）。
- 字段：`--json` 输出里 `osd_ms_matches_tot` 有三个取值——
  `true` / `false` / `null`（`src/host/health_read.mjs:441`，注释 `:430-432` 解释
  `null` = 没判过，**没判过就不算绿**）。
- 另一例：`lane23` 的 `alive` 位（像素帧心跳 200 ms 内有没有）决定这一组是新值还是旧值，
  `src/host/health_read.mjs:383-385`（旧值只报 `STALE`、不下结论）、
  `src/rtl/top/pl_video_top.v:688`（`dbg_zoom` 的最高位是 `~z_pix_gone`）。
- 跨域税不同：`dbg_src`/`dbg_lat` 全取自 axi 域现成电平 ⇒ 零新增跨域；
  `dbg_zoom` 那 19 位必须真跨一次（`src/rtl/top/pl_video_top.v:76-78`）。
  这一条解释了为什么"读回有、屏上没有"与"屏上有、读回旧"会是两种不同的坏。

**⑤ 怎么当场排除**

按动作顺序：

1. 打开 `src/host/health_read.mjs` 跑一次 `--json`，看 `lat.osd_ms_pair_ok` 与 `lat.osd_ms_sticky`
   两位；出现 `pair_ok=0` ⇒ 这一组不可判（重读一次），出现 `sticky=1` ⇒ 本轮钳位，屏上是饱和值。
2. 看 `lat.torn`（`:447`）：`true` ⇒ 回读口又变回"各读各的"，屏上那个数与回读不是同一组。
3. 只看屏上：`--` 出现在 `Latency:` 或 `Temp:` 那一格 ⇒ 是"没有可信读数"的显式表态，
   不要把它读成 0；对应代码位 `osd_overlay.v:473`、`main.c:92-93`。
4. 若判据"恒红"：先查读 lane 的顺序（`:334` 那行 `want`），再怀疑硬件——本工程的历史红项是脚本自己造成的。

小结 1：lane 与屏上那一格同源这件事，是被板级红项（`#59`）逼出来的设计，不是天然属性；
判据在 `lane24` 的 bit[17:16]。
小结 2：两条回读路（串口与 JTAG）的分工在 `design-choices.md` 第 11 节，这一篇不复述。
下一步：第 10 节。

## 第 10 节 `udp_tx`「接着但没人启动」vs「能用」

**① 零术语版**：有一个模块被装进了电路，线也都接好了，但唯一能让它开始干活的那根输入，
在顶层被写成了常量 0，于是它在板上从来不会开始干活。它真的开始干活的场景只出现在台架里。
**这样说的误导处**："线都接好了"不等于"这些线在板上被驱动过"——它的 `tx_req` 与 `gmii_*` 输出
确实进了发送多路选择器，所以它不是死代码，只是选中它的那条分支进不去。
（"死代码"在这里只取"从不会被执行的那段逻辑"这一层意思，不等于"工具会把它删掉"——
后者要靠综合日志判，见第 17 节 U-2。）

**② 误认成对方会得出什么错误结论**

两个方向的错话：

- "板子能主动往外发 UDP。" 错：顶层把它的启动线钉死
  （`src/rtl/eth/eth_udp_video_top.v:166` 的 `.tx_start_en(1'b0)`，另一处
  `:215` 的 `.udp_tx_start_en(1'b0)`），注释 `:158` 原话是
  "发侧维持今天的状态（`tx_start_en` 恒 0，Z7 上 UDP 发送**接着但没人启动**）"。
- "台架里 `udp_tx` 跑通过，所以板上这条路也算验过。" 错：
  `sim/tb_eth_video.v:2` 的被测口径写的是 `udp_tx + crc32_d8 + udp_rx + frame_reasm`
  （GMII 直环，例化在 `:31`）——那里驱动 `tx_start_en` 的是测试台，不是这个设计。
  技能卡里同族的教训是"以搜不到为根据的判定要先证明可达"
  （`skills/pitfalls/constraint-coverage-loss/SKILL.md:111-121`，条目 ⑧）。

**③ 两边的精确定义**

| 说法 | 精确口径 | 出处 |
|---|---|---|
| 接着（instanced & wired） | 例化存在、端口有连线、下游多路选择器保留该分支 | `src/rtl/eth/eth_udp_video_top.v:163-179`；下游 `src/rtl/eth/eth_ctrl.v:92-96`（`case (protocol_sw)`） |
| 没人启动 | 选择该分支的**唯一**条件被常量钉死 | `src/rtl/eth/eth_ctrl.v:151-152`（`protocol_sw <= 2'b01` 只能由 `udp_tx_start_en` 触发，而顶层给的是 `1'b0`）；状态机停在 `src/rtl/eth/udp_tx.v:36`（`st_idle … 等待开始发送信号`） |
| 能用（可交付的口径） | 需要在当前位流下由外部输入触发并看到输出——本工程**没有**这条凭据 | 与 `design-choices.md` 第 1 节的标签口径对照：`【实测】` 才是板上量过的 |

**④ 在本工程哪一处能观察出差别**

- 主证据是那一行的**实参**：`eth_udp_video_top.v:166`（`.tx_start_en(1'b0)`）；
  对照台架 `sim/tb_eth_video.v:31` 的例化里，同一个端口接的是 TB 的信号。
- 次级证据是**分支不可达**：`eth_ctrl.v:94` 的 `2'b01` 那一支，其进入条件只有
  `udp_tx_start_en`（`:151`），而 `:215` 给它常量 0 ⇒ 该支在板上永不被选。
- 第三处证据是别人也这样念过：`report/known_issues.md:271` 在解释
  "为什么 ICMP 那条畸形大帧不影响画面"时写的就是"Z7 不经这条通路发 UDP 视频，
  `:166-168` 那句 `tx_start_en(1'b0)` 就是它"。

**⑤ 怎么当场排除**

1. 打开例化处，看被问的那个模块的**启动端口实参**：是 `1'b0`/`1'b1` 常量 ⇒ 该模块在本设计里
   被接线但不被驱动（例：`eth_udp_video_top.v:166`）；是信号 ⇒ 继续问"谁驱动它"。
2. 打开下游多路选择器，看选中该支的条件能不能同时成立（`eth_ctrl.v:151-158`）。
3. 台架绿不等于板上会走：查那份台架**自己例化的是不是同一份实现**
   （`src/rtl/eth/ddr_bank_commit.v:4-5` 的注释给了这条规矩的正面版本：
   抽成模块是为了让台架例化上板的实现而不是手抄副本）。
4. 需要"它真的被综合进去了"的证据时，看综合日志的 `unused … removed` 名单——
   被删掉的元素才是真的没接；本工程把这条日志当死代码预言机用（技能卡口径见
   `skills/pitfalls/`；本轮未跑构建，故此处只给动作不给结论）。`【需重跑构建核对】`

小结 1："接着但没人启动"是可交付的事实，"能用"需要一次外部触发 + 一次输出观察，
两者只差在 `eth_udp_video_top.v:166` 那一行的实参。
小结 2：同一根线上"控制面发侧"的另一半（ARP/ICMP 为什么活着）在
`subsystem-map.md` 第 4 节的实例表里，本篇不重复。下一步：第 11 节。

## 第 11 节 丢字 vs 丢包 vs 坏包（三个计数器）

**① 零术语版**：这台上数了三件不同的事：① 有个 16 位的小格子因为缓冲区满了没能写进去（丢字）；
② 有一整帧缺了行或字节，被作废（丢帧）；③ 收到的某个包本身是坏的（坏包）。
它们不是同一个计数器的三个名字。
**这样说的误导处**：说"小格子"会低估后果——丢一个字就是屏上少两个字节，
表现是一条黑纹而不是一条错误信息（`src/rtl/eth/frame_reasm.v:2-3` 的文件头写的就是这个现象）。

**② 误认成对方会得出什么错误结论**

- 把 `lane8`（收到的包数）当"该收到的包数"：会念成"0 丢包"。
  UDP 这条路没有重传，也没有"该收到多少"的对照面；
  真正说"缺了什么"的是 `lane2` 的高 16 位（缺行峰值）与 `lane1` 低 16 位（作废帧数）。
- 把 `stat_bad` 当"坏包数"：`src/rtl/eth/frame_reasm.v:34` 声明的 `stat_bad`
  在**两处**被加一——`:197`（字节凑够了但验收门没过 ⇒ 短帧/缺行作废）与
  `:207`（收到坏包）。一个计数器装两件事。
- 把"丢字"说成"丢包"：`lane0` 是字（16 bit）的个数，换算成字节要 ×2。

**③ 三件的精确定义与落点**

| 计数器 | 定义（谁在什么条件下加一） | 落在哪一口 |
|---|---|---|
| 丢字 | `cdc_wr_req && cdc_full` 的那一拍被挡住 ⇒ 该拍的数据永久消失；使能本身晚一拍入账 | `src/rtl/eth/link_monitor.v:105`（`drop_ev_d`）、`:122`、`:187`（`lane0`）；上游 `src/rtl/eth/eth_udp_video_top.v:283` |
| 作废帧 | 一帧字节预算到了但验收门（逐行覆盖 + 字节 + 无坏包）没过，在末包那一拍脉冲一次 | `src/rtl/eth/frame_reasm.v:196-202`（含 `rows_missed` 的"缺的不是行而是最后一包字节"这一支）、`src/rtl/eth/link_monitor.v:126-129`、`:188`（`lane1` 低 16） |
| 坏包 | `p_eof` 那一拍 `p_good=0` ⇒ `frame_err` 脉冲 + 整帧作废位 | `src/rtl/eth/frame_reasm.v:206-209`（`stat_bad++` 与 `bad_frame<=1`）、`src/rtl/eth/link_monitor.v:130`、`:188`（`lane1` 高 16 = `err16`） |
| 越界写被挡 | 发包方给的偏移越过 `FRAME_BYTES` ⇒ 不写、只数 | `src/rtl/eth/frame_reasm.v:152-161`（`stat_oob_off`）；病史 `report/known_issues.md` 第 15 条（`:447` 起） |
| 收侧丢弃原因 | 三个只脉冲一位的统计口：`stat_drop_bad`（FCS 坏）、`stat_drop_filt`（端口过滤）、`stat_udp_ok` | `src/rtl/eth/udp_rx_parser.v:21-23`；顶层只把它们接成 wire（`src/rtl/eth/eth_udp_video_top.v:196`、`:203`），**没有寄存器数它们** |

**④ 在本工程哪一处能观察出差别**

- 报告/读数的**列**：`lane0 / lane1 / lane2 / lane8 / lane9` 五个 32 位字，
  组装在 `src/rtl/eth/link_monitor.v:187-196`，位序解释在 `src/host/health_read.mjs:53-64`。
  `lane1` 一格里同时装着"坏包"与"作废帧"两半 16 位——只看一个数就会混。
- 标志位对照：`lane7` 的 `bit0/bit1/bit2`（丢过字 / 作废过帧 / 灌满过）
  定义在 `src/rtl/eth/link_monitor.v:158-162`。
- 必须如实报的第二处口径冲突：`link_monitor.v:4-5`、`:23` 与
  `src/host/health_read.mjs:55` 三处都还写着"板上 `p_good` 恒 1 ⇒ 坏包应为 0 / 死数字"，
  而 `src/rtl/eth/eth_udp_video_top.v:238` 写这一位"从此是真值（原来是 1'b1）"，
  错误源的产生方式写在 `src/rtl/eth/gmii_rx_mac.v:4-7`（自算 FCS-32，拿整帧残值当判据）。
  两种解释：① 那三处是 V7.9.6 之前的旧注释未删；② 现役连线仍有把这一位钉死的路径。
  区分方法见下面第 ⑤ 层第 3 步；本次未做台架复跑，故登记为未确认（第 17 节 U-1）。

**⑤ 怎么当场排除**

1. 先问单位：出现"字/word" ⇒ 丢字（`lane0`）；出现"帧" ⇒ 作废帧（`lane1` 低 16 或 `lane7.bit1`）；
   出现"包" ⇒ 坏包（`lane1` 高 16）或"被丢弃的包"（`udp_rx_parser` 的三个脉冲，目前无寄存器）。
2. 打开 `src/rtl/eth/frame_reasm.v` 搜 `stat_bad`：命中两处（`:197`、`:207`）⇒ 这个口不能当"坏包数"念，
   要念"作废帧 + 坏包之和"。
3. 判"坏包这条链到底通不通"的可执行三步：
   a. 打开 `src/rtl/eth/udp_rx_parser.v` 看 `p_good` 的赋值来源（`:68`、`:84`、`:100`、`:199`、`:205`）；
   b. 打开 `src/rtl/eth/eth_udp_video_top.v:186-204` 确认 `gmii_rx_mac` 的 `m_good/m_bad`
      进了 parser、parser 的 `p_good` 进了 `u_reasm`；
   c. 跑 `sim/tb_v795_rx_chain.v` 与 `sim/tb_v795_rx_fcs.v`（两份都在 `sim/`，
      文件名本次 `ls` 实测存在），看有没有"注入坏帧 ⇒ `frame_err` 脉冲一次"的判据行。
      这一步需要 Vivado 仿真器 ⇒ `【需仿真复跑】`。

小结 1：三个计数器分别落在 `lane0`、`lane1` 高半、`lane1` 低半；`stat_bad` 是后两者的和，
不是其中之一。
小结 2：`0 丢帧 / 坏帧`（`data/metrics.csv:22`）这句只能念成"PL 自己数的这两个计数器是 0"，
念成"网络没丢包"就是本条的错。下一步：第 12 节。

## 第 12 节 「0 失败端点」vs「时序有余量」

**① 零术语版**：报告里"失败端点 0"的意思是"被检查过的那些连线里，没有一条不合格"。
它不包括：根本没被检查的线、被规则主动排除的线、以及靠电路结构而不是靠时序保证的线。
**这样说的误导处**："被检查过的那些"这句容易被听成"全部"——本工程的两个数
（`51135` 个端点 与 `11` 个未约束端口 / `7` 条 `no_input_delay`）不在同一张表里，
所以要跳两处才看得全。

**② 误认成对方会得出什么错误结论**

会念成："0 失败端点 ⇒ 跨时钟域安全 ⇒ 可以宣称时序收敛。"
三处会塌：

1. 异步跨域**根本没参与**这次检查：`src/constraints/clock_groups_impl.xdc:28-31` 把
   `eth_rxc`、`clk_fpga_0`、`sys_clk` 及其生成钟声明成三组互异步，
   于是 `build/report/timing_summary.rpt:192-199` 的 Inter Clock Table 只剩两行
   （`sys_clk ↔ clkout0_1`，同源派生）。被排除的那几对，工具不给数。
2. 排除之后**也没有别处给的界**：`report/timing/debt_ledger.md:94-101` 第 5 节写的正是
   "这两对被整体排除，没有任何 `set_max_delay -datapath_only` 给出界；
   界叠不到被排除的时钟对上"，并明确"这条债不能靠加约束消"。
3. 跨域数据面靠的是结构，不是裕量：`clock_groups_impl.xdc:19-23` 列了四条结构保证
   （格雷码 FIFO / 翻转+3FF / 3 级像素+3FF / 3FF 控制字）。
   `build/report/cdc.rpt:15-18` 给的是结构核查读数：`Unsafe` 列 1 + 2 = 3、`Unknown` 列 530，
   这些列里没有任何 ns 单位的裕量。

**③ 两边的精确定义 + 出处**

| 口径 | 规范/文档原文口径 | 出处与核对日期 |
|---|---|---|
| WNS / 失败端点 | 时序名册：`WNS(ns)`、`TNS Failing Endpoints`、`TNS Total Endpoints` 三列同格 | `build/report/timing_summary.rpt:151`（本次打开，2026-10-05） |
| "被排除的时钟对不靠时序分析证明功能" | *The asynchronous CDC paths … should not be timed with the default timing analysis, which cannot prove they will be functional in hardware.* | UG949（v2019.1，2019-06-26）第 3 章 `Clock Groups and CDC` 一节，第 175-176 页；本次由 `https://docs.amd.com/r/en-US/ug949-vivado-design-methodology` 同族文档的 PDF 抽取文本核对，2026-10-05 |
| `report_cdc` 是结构分析、不给时序 | *Report CDC … performs a structural analysis … does not provide timing information because timing slack does not make sense on paths that cross asynchronous clock domains.* | 同上，第 176 页（`Report CDC` 小节） |
| "未检查 ≠ 满足"（本工程口径） | `check_timing` 的 `no_input_delay` 计数行与"5 个 I/O 端点当前无输入窗" | `build/report/timing_summary.rpt:99`、`data/metrics.csv:6`；`src/constraints/r116_rgmii_input_window.xdc:5`（"未覆盖 = 不是'满足'，是'没检查'"） |

**④ 在本工程哪一处能观察出差别**

| 观察点 | 位置 | 出现什么算"没被检查" |
|---|---|---|
| `no_input_delay` 段落 | `build/report/timing_summary.rpt:97-101` | `There are 5 input ports with no input delay specified. (HIGH)` ⇒ 名册的 51135 不包含这些 I/O 的收口判定 |
| `no_output_delay` 段落 | `build/report/timing_summary.rpt:103-105` | `6 ports with no output delay specified. (HIGH)` |
| Inter Clock Table | `build/report/timing_summary.rpt:192-199` | 只有 2 行 ⇒ 异步对不参与（被排除，不是"很快"） |
| CDC 名册 | `build/report/cdc.rpt:15-18` | `Exceptions` 列写 `Asynch Clock Groups`、`Unsafe`/`Unknown` 非 0 |
| 加窗之后的对照 | `build/tcl/build_system_axigpio.tcl:57-63`（`VP_R116_IO_WINDOW=1` 打印 `预计 5 个 I/O 端点会红`）与 `report/timing/debt_ledger.md:125-127`（"缺口从 11 变 6，同时多出 5 个有限的违例端点"） | 同一颗器件，绿/红取决于约束是否存在，而不是布线变好 |
| 假违例的反方向证据 | `src/constraints/clock_groups_impl.xdc:16-17` | 少写 `-include_generated_clocks` 时，历史上得到 `WNS≈-6.7` 的**假**违例 |

**⑤ 怎么当场排除**

1. 打开 `build/report/timing_summary.rpt`，先看 `:97-105` 的 `no_input_delay` /
   `no_output_delay` 两段计数，再看 `:151` 的 `TNS Failing Endpoints`。
   前者非 0 ⇒ 后者**只覆盖被约束集**，两句要连着念。
2. 打开 `build/report/cdc.rpt` 的表头行（`Severity / Exceptions / Safe / Unsafe / Unknown`）：
   出现 `Asynch Clock Groups` ⇒ 这些路径按时序名册"不存在"，要改问结构；
   `Unsafe` 非 0 ⇒ 结构核查本身也没过（本工程当前 `= 3`，两条 `Critical` 行）。
3. 要"界"的证据：`set_max_delay` 有没有写在同一对钟上。本工程的答案是"没有"，
   凭据 `report/timing/debt_ledger.md:96-99`（`report_exceptions` 那两行的 `Setup/Hold` 列写 `clock_group`）。
4. 最后一步才是把 `WNS` 与 `WHS` 一起念（`data/metrics.csv:5`、`:7`，还有 `WPWS 0.264`）——
   三个都是 ns 级的裕量，都不能单独支撑"跨域安全"或"无未检项"。

小结 1："0 失败端点"是被检查集内的结论，跨域那条路的安全性在 `cdc.rpt` 与结构注释里，
两处的单位不同（ns vs 计数），不许互相换算。
小结 2：把"约束缺失"当"时序好"是本篇最常见的一种"没有代价的收益"，
判据与修法在 `skills/pitfalls/constraint-coverage-loss/SKILL.md:28-40`（条目 ①）。下一步：第 13 节。

## 第 13 节 约束存在 vs 约束有射程

**① 零术语版**：约束文件里写着这一行，和这一行真的管到了某些连线，是两件事。
工具按名字点对象：名字取不到，整行就白写，而且很多时候只是不吭声
（技能卡原话是"约束工具的语言是按名字点人"，见 `skills/pitfalls/constraint-coverage-loss/SKILL.md:8`）。
**这样说的误导处**：说"整行白写"会让人以为会报错——本工程实测过的两种情况里，
一种只留一句 warning，另一种连 warning 都只指向"没被支持"而不说"没生效"。

**② 误认成对方会得出什么错误结论**

会念成："`set_clock_groups` 这一行在文件里 ⇒ 这三组钟的跨域关系已经被声明了。"
本工程量过的两个反例：

1. 把 PS7 IP 自己创建的 `clk_fpga_0` 并进同一条命令时，
   `get_clocks` 取不到该名字会让**整条命令空转**，连带把 `eth_rxc`/`sys_clk` 两组一起废掉，
   现场只留一句 warning：`src/constraints/rk_zynq7020.xdc:43-45`（写约束时引用的这条教训），
   完整病史与 CRITICAL WARNING `[Vivado 12-4739]` 在 `:62-74`。
2. 在 `.xdc` 里写 Tcl 守卫（`if`/`puts`）会被解析器整块跳过，
   "防呆"变成"防呆失效且不报错"：`src/constraints/r119_hdmi_source_window.xdc:5-10`
   （原文引 `CRITICAL WARNING: [Designutils 20-1307]`，凭据件
   `build/evidence/r119_xdc_loads_probe2.txt`）。

**③ 两边的精确定义 + 出处**

| 口径 | 内容 | 出处 |
|---|---|---|
| 约束存在 | 文本在某个 `.xdc` 里 | `ls src/constraints/` 本次实测 9 个文件 |
| 约束被加载 | 该文件被工程脚本 `add_files` 且绑到正确时机 | `build/tcl/build_system_axigpio.tcl:31`（`rk_zynq7020.xdc`）、`:36-38`（`clock_groups_impl.xdc` + `used_in_synthesis false`）、`:57-63`、`:75-81`（两个候选窗各带一个环境变量开关） |
| 约束有射程 | 这一行点到的对象此刻存在，且命中数 = 应约束对象数 | 判据写法：`skills/pitfalls/constraint-coverage-loss/SKILL.md:26`（"每条按名的约束都留下命中数这个读数"）、`:41-50`（条目 ②：批量命令的失败语义是全有或全无）、`:100-109`（条目 ⑦：手写文件清单当射程会随目录加深失效）、`:111-121`（条目 ⑧：搜不到不等于不存在，要先证明可达） |
| 工具的边界 | XDC 文件里不许写控制流 | `src/constraints/clock_groups_impl.xdc:4-8`；`rk_zynq7020.xdc:71-73` |

**④ 在本工程哪一处能观察出差别**

- 盘上有 9 个 `.xdc`，正式构建只加载 2 个：账目写在 `report/timing/debt_ledger.md:13-15`
  （"还有三个没有被任何脚本 `add_files` 的候选件 ⇒ 它们是实验材料，不是现行约束集"）。
  注意这一段的行号引用（`:10` 写 `build_system_axigpio.tcl:19`、`:11-12` 写 `:24-26`）
  与当前脚本的实际行号（`:31`、`:36-38`）不同 ⇒ 念那份账时用行内容，不用它的行号。
- 判据件把"射程"直接印成数字：`build/evidence/r119_window_check.txt` 第 5 行
  `W5 射程只含数据道 判 5 项 命中道=[tmds_data_p[*],tmds_data_n[*]] 误挂led/钟道=否 PASS`、
  第 6 行 `W6 默认不加载 判 6 项 引用行=2 全在开关块内=是 PASS`。
  这两行就是"存在 ≠ 生效 / 生效 ≠ 覆盖全部"的机器化写法。
- 空约束的历史形态：`rk_zynq7020.xdc:51-54` 记的 `set_false_path -from eth_rst_n`
  每次综合报 `[Constraints 18-513] … contains no valid startpoints`——那是一条**不约束任何东西、
  只制造噪声**的行，已删；现役写法在 `:55`（`-to`）。

**⑤ 怎么当场排除**

1. 打开构建日志或 `build_system_axigpio.tcl:57-81`，看那两行 `puts` 打印的是 `loaded` 还是 `off`：
   `off` ⇒ 这条窗约束此刻**不在**射程内（本工程当前是 off，见 `data/metrics.csv:5` 的条件列）。
2. 打开实现日志，搜这一行涉及的时钟名或端口名：搜不到 ⇒ 名字取不到，整条命令可能空转；
   搜到了也不能定论 ⇒ 按 `skills/pitfalls/constraint-coverage-loss/SKILL.md:111-121` 补一次
   **正对照**（用一个已知存在的对象跑同一个查询，必须命中）。
3. 让射程变成打印量：写/跑一把像 `build/r119_window_check.mjs` 那样的只读尺子，
   把"命中道 / 误挂道 / 引用行数"印出来（判据样例 `build/evidence/r119_window_check.txt`），
   而不是靠人眼读 `.xdc`。
4. 问一句"这条约束的作用对象在这个阶段存在吗"：
   `clk_fpga_0` 由 PS7 IP 创建 ⇒ 综合阶段不存在 ⇒ 该约束必须绑到只在实现生效的文件
   （`clock_groups_impl.xdc:3-8`）。

小结 1："文件里有这一行"与"这颗 bit 受这条约束"之间隔着三件事：加载时机、名字命中、对象存在性。
小结 2：这一条与第 12 条是一对——第 12 条讲读数的射程，第 13 条讲约束的射程；
两条合起来才是"没检查 ≠ 满足"（`src/constraints/r116_rgmii_input_window.xdc:5`）。下一步：第 14 节。

## 第 14 节 工具估算结温 vs 板上实测温度

**① 零术语版**：一个数是人拿探针在芯片内部量出来的，另一个数是工具按"假定多少瓦 + 假定散热多差"
算出来的。这一篇里它们相差近 9 ℃，而且算出来的那个，工具自己标了"不太可信"。
**这样说的误导处**：说"探针量出来的"会让人以为它是芯片外部真实温度——它是片上传感器的读数，
量的是结温，不是壳温，也不是环境温度。

**② 误认成对方会得出什么错误结论**

会念成："报告显示结温 52.6 ℃，离 100 ℃ 还远，所以长时间演示不会热出问题。"
错在三处：

1. `52.6` 是估算，且同一张表的 `Confidence Level` 行写的是 `Low`
   （`build/report/power.rpt:40-41`）；置信度低的原因是活动量输入不全——
   分项表里 `I/O nodes activity` = `Low`、`Internal nodes activity` = `Medium`
   （`build/report/power.rpt:104-116`），`Simulation Activity File` 那一行是 `---`
   （`:43` 那一行 `Simulation Activity File` = `---`）。
2. 板上同一颗器件的片上传感器读数区间是 61.2 – 61.7 ℃（`data/metrics.csv:29`，
   六次 `[TEMP]` 回显的极值，凭据 `build/evidence/r113_temp_lines.txt`）。
3. 屏上那一格与串口那一行是**同一份编码**：两位十进制 BCD 由 PS 算好后跨过去
   （`src/ps/main.c:83-93`），PL 不参与换算（`src/rtl/process/effect_ctrl.v:63-67`）；
   量程只有 0..99 ℃，装不下就画 `--`。把"屏上 61C"当成另一路测量是错的。

**③ 两边的精确定义**

| 口径 | 输入 | 本工程取值 | 出处 |
|---|---|---|---|
| 估算 | 布线后功耗 + 假定的环境温度/热阻/风速 | 动态 2.213 W、片上合计 2.391 W、`Junction Temperature (C) = 52.6`、`Max Ambient = 57.4`、`Ambient 25.0`、`ThetaJA 11.5`、`Airflow 250 LFM` | `build/report/power.rpt:36`、`:33`、`:40`、`:39`、`:127`、`:104-116`（Environment 表在 `2. Settings` 一节） |
| 实测 | 片上温度传感器（XADC）读数，PS 驱动打印 | 61.2 – 61.7 ℃（六条 `[TEMP]` 的极值），同时给 `raw=`、`vccint=`、`osd=`、`gpio=` 四路 | `data/metrics.csv:29`（含凭据路径与一次三方对账） |
| 三方对账 | 驱动读数 ↔ 屏上三字符 ↔ 写进 PL 的 gpio 位 | 4 条全自洽（判据编号 V9-6） | `data/metrics.csv:29` 中段 |

一处要如实报出的转录差异：`data/metrics.csv:28` 的条件列写 `Max Ambient 57.5 ℃`，
而本次打开的**两份**功耗报告都打印 `57.4`：`build/report/power.rpt:39` 与 `build/power.rpt:39`
（两份件本次 `md5sum` 相同 ⇒ 同一内容，路径不同）。两种解释：① 那一行是转录时的舍入/笔误；
② 那一行抄的是更早一轮、已被覆盖的件。这一条已不是"读不到"，而是"文档与件不一致"，
处理它要改 `data/metrics.csv`（不在本批权限内）⇒ 登记为 U-3 那条要问队伍的问题。

**④ 在本工程哪一处能观察出差别**

- 报告的列：`build/report/power.rpt` 的 `Junction Temperature (C)` 与 `Confidence Level`
  在同一张 Summary 表里（`:40-41`）——念第一个数必须把第二个一起念。
- 串口/屏：`[TEMP]` 行同时打印 `degC=` 与 `raw=`（见 `data/metrics.csv:29` 引的读数形态），
  屏上只画两位（`main.c:83-93`）；`osd=`/`gpio=` 两列是同源核对用的，不是第三次测量。
- 原始回显件：`build/evidence/r113_temp_lines.txt` 与 `build/evidence/r113_serial_raw.txt`
  （后者是第 1b 步自己产出的原始行，登记在 `data/metrics.csv:29` 末段）。

**⑤ 怎么当场排除**

1. 打开 `build/report/power.rpt`，搜 `Confidence Level`：出现 `Low` ⇒ 这一格是估算，
   且 `Simulation Activity File` 那行是 `---`（没有仿真活动文件输入）。
2. 打开 `data/metrics.csv`，看"类别/数值"列：写 `估算` 的行与写 `板读 XADC` 的行**是两行**
   （`:28` 与 `:29`）；单位都是 ℃，但测量条件列一个是"一次构建"、一个是"一次板级校验"。
3. 要看真实热状态 ⇒ 只有板上那一路：跑 `board_verify` 或串口 `[TEMP]`，并检查
   `degC / osd / gpio` 三者是否一致（口径见 `data/metrics.csv:29`）；
   没有板子时，这一格按 `【需板上验证】` 处理，不许用估算值顶替。

小结 1：52.6 与 61.2–61.7 之间的差不是"散热好不好"，而是"一个是算的、一个是读的"，
且算的那个自己标了 Low。
小结 2：屏上 `Temp:` 那一格是**编码显示**，不是第四个测量源（判据 `tb_osd_lines` T15 的口径
写在 `src/rtl/process/effect_ctrl.v:68`）。下一步：第 15 节。

## 第 15 节 串行钟名里的 `5x` vs TMDS 的 `10x`

**① 零术语版**：送出一个字符要用到两个东西：一个"比像素快几倍的钟"和一套"每个钟沿都摆一个比特"的
电路。名字叫 `5x` 说的是这个钟比像素钟快 5 倍，而每个字符是 10 个比特——
因为一个周期里摆了两次（上升沿一次、下降沿一次）。
**这样说的误导处**："快 5 倍"不等于"每秒发 5 个比特"；把 `5x` 当"每字符 5 拍"会把比特率算成实际的两倍误差。

**② 误认成对方会得出什么错误结论**

- 把 250 MHz 当字符率：会念成"每 lane 每秒 250 M 字符"。实际每 lane 每秒
  250 M × 2 = 500 M 比特 = 50 M 字符（`src/rtl/hdmi/tmds_serializer.v:2` 的
  `10:1 … DATA_WIDTH=10 requires DATA_RATE_OQ=DDR`）。
- 把 `4.000 ns` 当字符周期：`4.000` 在本工程同时是两样东西——
  `clkout1_1` 的周期（`build/report/timing_summary.rpt:170`）和 HDMI 源端窗的半宽
  （0.20 × 20.000 ns = 4.000 ns，`src/constraints/r119_hdmi_source_window.xdc:23-26`）。
  字符周期是 20.000 ns（像素周期），位周期是 2.000 ns
  （判据行 `build/evidence/r119_window_check.txt:1`、`:9`）。三个数都叫 ns，量纲不同。

**③ 两边的精确定义 + 出处**

| 量 | 定义 | 出处 |
|---|---|---|
| 像素周期 `Tcharacter` | 一个 TMDS 字符（10 比特）的时间 = 50 MHz 的周期 = 20.000 ns | `data/metrics.csv:3`；`src/constraints/r119_hdmi_source_window.xdc:23-25` |
| `clk_pix5x` | MMCM 的第二路输出，250 MHz（`CLKOUT1_DIVIDE = 4`，VCO 1000 MHz） | `src/rtl/clocks/clk_gen.v:2`、`:24-25`、`:55` |
| 10:1 串并 | OSERDESE2 主从级联，`DATA_WIDTH=10`、`DATA_RATE_OQ="DDR"`，`CLK=clk_pix5x`、`CLKDIV=clk_pix` | `src/rtl/hdmi/tmds_serializer.v:2-3`、`:15-22`、`:31-32` |
| 位周期 `Tbit` | `Tcharacter / 10` = 2.000 ns | `build/evidence/r119_window_check.txt:9`（`0.15×Tbit=2.000ns` 那句里同时给出） |

规范口径（`0.20 Tcharacter` / `0.15 Tbit` 这两行出自哪份文档、哪张表）在本仓库有专门的取证件：
`report/io/hdmi_cts_source_window.md:20-21`（第 1、2 行，含 HDMI 1.4 §4.2.4 Table 4-24、
1.3 Table 4-16、1.1 Table 4-13 与两份仪器厂商文档的逐句复述、页面号与镜像 URL）。
这些 URL 是那份取证文档登记的（核对日期 2026-10-04），本次（2026-10-05）没有重新抓取原文
⇒ 引用它们时说"仓库已登记的取证记录"，不说"今天核过"。`【本次未复核外部原文】`

**④ 在本工程哪一处能观察出差别**

- 看 `tmds_serializer.v:15-22` 的参数块：只有当 `DATA_WIDTH=10` 与 `DATA_RATE_OQ="DDR"` 同时出现，
  "5 倍钟"才配得上"10 倍数据"。任一处被改动，比特率立刻变。
- 看名册：`build/report/timing_summary.rpt:170` 的 `clkout1_1 4.000 ns` 与
  `:169` 的 `clkout0_1 20.000 ns` 同表相邻，比 5 倍。
- 看窗件：`build/evidence/r119_window_check.txt` 的第 1、8、9、10 行分别把
  `0.20×20.000ns` 与 `0.15×Tbit=2.000ns` 两条算式印出来了——想混单位时先跑这把尺子。

**⑤ 怎么当场排除**

打开 `src/rtl/hdmi/tmds_serializer.v` 第 15-22 行，读三个参数：`DATA_WIDTH`、`DATA_RATE_OQ`、
以及 `CLK`/`CLKDIV` 接的是谁。得到"每字符比特数 = DATA_WIDTH"、
"每秒字符数 = CLKDIV 频率"，再乘回去与 `data/metrics.csv:3` 的像素钟对齐——
不一致就是混了 `5x` 与 `10x`。

小结 1：`5x` 是时钟比，`10x` 是比特比，中间那个乘数是"双沿"；
这一对与第 8 节同族：节拍名不等于频率值。
小结 2：源端 TMDS 窗的**规范口径 vs 本工程实测口径**（0.065 / 0.001 ns 对 4.000 / 0.300 ns）
属于"下一层"内容，写在 `next-layer.md` 第 6 节，这里只给命名混淆那半。下一步：第 16 节。

## 第 16 节 行环的「环深」vs「延迟行数」

**① 零术语版**：想把画面晚几行出来，就准备一圈格子轮流写、轮流读。
圈的大小必须凑成 2 的幂（好用切位代替除法），所以圈往往比要延迟的行数大一格；
"大出来的那一格"不是延迟。
**这样说的误导处**：说"圈比延迟大"会让人以为可以随手取整——它受两个条件夹住：
必须 ≥ 延迟行数 + 1，且必须是 2 的幂（`src/rtl/video/raw_line_delay.v:37-41`）。

**② 误认成对方会得出什么错误结论**

会念成："环是 8 行 ⇒ 内容延后 8 行，那顶层就要补 8 行。"
错在：延迟量由参数 `LINES` 决定，环深是它的派生量
（`src/rtl/video/raw_line_delay.v:9` 参数、`:41` `RLOG = clog2(LINES+1)`、
`:43` `DEPTH = (1 << RLOG) * W`；LINES=4 ⇒ 环 8 行、延后 4 行 + 1 拍）。
顶层读的是效果链自己声明的输出口，不是环深
（`src/rtl/top/pl_video_top.v:236` 的 `pipe_off_rows` 与 `:276` 的提前量算式）。
另一种错法在文件头记着：把几级行缓存串起来（第一版就是这么写的），
会"延后 N 行**又**多花 N 拍 ⇒ 列偏 N 格"，而模块级台架看不见（`raw_line_delay.v:6-7`）。

**③ 两边的精确定义**

| 量 | 定义 | 出处 |
|---|---|---|
| 延迟行数 `LINES` | 输出比输入晚几个**显示行**，唯一合法来源是效果链的 `OFF_LINES` 输出口 | `src/rtl/video/raw_line_delay.v:9`、`:39-41`（"N 只有一个合法出处"）；链子侧 `src/rtl/process/proc_pipeline.v:23-27`、`:44` |
| 环深 | `2^RLOG × W`，`RLOG = clog2(LINES+1)` ⇒ `mod` 就是切位 | `src/rtl/video/raw_line_delay.v:37`、`:41-43` |
| 多出来的那 1 拍 | 块 RAM 的读出发出早于写生效 ⇒ "延迟恰好 = LINES 行 + 1 拍、列不偏" | `src/rtl/video/raw_line_delay.v:6`；BRAM 读延迟的同类口径 `src/rtl/video/frame_buffer_w64.v:3` |
| 行首的例外 | "列不偏"只在**一行之内**成立：掉进消隐那一拍要预读 | `src/rtl/video/raw_line_delay.v:58-62`（#102 根因）、`:68-76`（做法）、`:77-79`（两种"看起来更简单"的错法） |

**④ 在本工程哪一处能观察出差别**

- 看一个模块里有没有**两个数**：`LINES = 4` 与 `RLOG = 3`（环 8 行）同时出现，
  就说明环深不是延迟量（`raw_line_delay.v:9`、`:41-43`）。
- 看现象落在哪：`#102` 那次板上的表现是"从视频里切出来贴在屏幕左边缘的一条线"，
  一帧 600 行、行行都有一格（`raw_line_delay.v:58-62` 的注释原文）。
  环深算错会让整幅**平移若干行**，不会只在行首留一格——两种坏长得不一样。
- 顶层补偿量：`src/rtl/top/pl_video_top.v:276` 的 `y_right_adv = y + pipe_off_rows + BILIN_ROWS`
  ——加的是链子的滞后与双线性的 2 行，不是环深。

**⑤ 怎么当场排除**

打开 `raw_line_delay.v`：

- 出现 `localparam RLOG = clog2(LINES + 1)` 这一族式子 ⇒ 环深是派生量，延迟量看 `LINES`；
- 出现 `rslot = y[RLOG-1:0] - LINES[RLOG-1:0]` ⇒ 延迟 = LINES（`mod` 用切位实现）；
- 若某个顶层手写了一个"4"或"8"当作延迟：与 `u_pipe.OFF_LINES` 对一次
  （规矩写在 `src/rtl/process/proc_pipeline.v:19-21`：顶层不许另写一个数）。

小结 1：环深解决"能不能用切位做取模"，`LINES` 解决"晚几行"；两个数都在同一个文件里，
念错其中一个，补偿量就整体错位。
小结 2：这一条与 `glossary.md` 词条 16 是同一术语的两面，词条讲定义，这里讲怎么混。下一步：第 17 节。

## 第 17 节 本篇的未确认清单与去处

W7 口径：逐标记计数见 `_progress.md` 第 4 节的统计方式（`grep -o "<标记>" myths.md | wc -l`）。
每个标记都对应一条能被回答的问题，不写修辞性含糊。

| 编号 | 位置 | 标记 | 要谁来消掉 / 怎么做 |
|---|---|---|---|
| U-1 | 第 3 节末段、第 11 节第 ④ 层（`link_monitor.v:4-5` 与 `eth_udp_video_top.v:238` 的口径冲突） | `【需仿真复跑】` | 跑 `sim/tb_v795_rx_chain.v` 与 `sim/tb_v795_rx_fcs.v`（需 `VP_VIVADO_BIN`），看"注入坏帧 ⇒ `frame_err` 脉冲一次"的判据行是否存在；同时可问一句：V7.9.6 之后那三处旧注释是否应当删 |
| U-2 | 第 10 节第 ⑤ 层第 4 步 | `【需重跑构建核对】` | 需要一次构建的综合日志，搜 `Synth 8-6014` / `unused … removed` 里有没有 `u_udp_tx` 的元素；否则"接着但没启动"只到结构层 |
| U-3 | 第 14 节第 ③ 层末段 | `【需队伍确认】` | 两份功耗报告都印 `Max Ambient 57.4`（`build/report/power.rpt:39`、`build/power.rpt:39`，本次 `md5sum` 相同），而 `data/metrics.csv:28` 写 57.5 ⇒ 要问的是"改指标表那一格，还是那份件另有出处"；改 `data/metrics.csv` 不在本批权限内 |
| U-4 | 第 14 节第 ⑤ 层第 3 步 | `【需板上验证】` | 无板时 `Temp` 实测那一格不许由估算顶替；有板时跑 `board_verify` 并核 `degC/osd/gpio` |
| U-5 | 第 15 节第 ③ 层（HDMI 规范 URL 本次未重抓） | `【本次未复核外部原文】` | 需要一次能访问规范镜像的网络核对；仓库内登记见 `report/io/hdmi_cts_source_window.md:20-21` |

计数口径（W7 要求逐篇报出；命令与 `_progress.md` 第 4 节同款：`grep -o "<标记>" myths.md | wc -l`；
2026-10-05 实测）：本篇有 5 个待办格（U-1…U-5）。实测命中数：`需仿真复跑` 2（正文 1 + 表格 1）、
`需重跑构建核对` 2（正文 1 + 表格 1）、`需板上验证` 2（正文 1 + 表格 1）、
`本次未复核外部原文` 2（第 15 节 ③ 1 + 表格 1）、`需队伍确认` 1（只在表格里——
第 14 节 ③ 那一处用文字说"登记为 U-3"而没有再放一次带方括号的标记）；
`未确认` 这一种本篇为 0 次。
本段刻意把标记名写成不带方括号的形态，就是为了不让计数句自己进计数（否则每条会多 1）。
这五种标记都算 W7 的"未确认类计数"，与 `design-choices.md` 的三类标签（实测/注释记载/报告记录）不同源，
不要合并念。

小结 1：14 条里只有 U-1、U-2 是"这条本身还差证据"，其余三条是"辨认动作的前置条件不在手上"。
小结 2：任何一条被消掉，改的应该是那条的 ⑤ 层，而不是把标记删掉。下一步：第 18 节。

## 第 18 节 小结与下一步

14 对混淆按"能被观察的位置"分三家：

- **在 RTL 的某一行上**：3（异或在不在）、6（判决条件里有没有 busy）、10（端口实参是不是常量）、
  13（`puts` 打的是 `loaded` 还是 `off`）、15（`DATA_WIDTH` 与 `DATA_RATE_OQ` 是否成对）、
  16（`LINES` 与 `RLOG` 是否两个数）。
- **在报告的某一列上**：4（`WNS(ns)` 列）、5（满量程钉住的读数）、12（`no_input_delay` 计数行）、
  14（`Confidence Level` 行）、7（`Block RAM Tile` 行 vs 地址/AXI 端口）。
- **在回读或表格的某一位/某一行上**：8（`lane24` 的 bit[17:16]）、9（`lat` 段的 `osd_ms_matches`）、
  11（`lane0 / lane1 高半 / lane1 低半`）、14（`metrics.csv:28` 与 `:29` 是两行）。

与别的篇目的接缝：术语定义一律在 `glossary.md`（词条 6、11、14、16、19、20、22 直接对上第 3、4、7、16、5、6、12 节）；
取舍代价一律在 `design-choices.md`（第 4、6、7、11、13 节）；跨域点全表在 `clocking-and-reset.md`；
接口位表在 `interface-contract.md`。这一篇只写"配对与观察点"，任何一段读起来像在复述别篇的话，
那一段就该删（判据写在 `README.md` 第 5 节末段）。

再深一层没在这套文档里走的：AXI 三类接口的语义、`set_clock_groups` 与
`set_max_delay -datapath_only` 各表达什么、部分重配置与 Multi-Boot、PS 侧缓存一致性、
实现策略旋钮的内部、HDMI 源端窗的规范条文与本工程实测的差距——全部收在 `next-layer.md`。

## 第 19 节 自测题

题目：**第 12 节里"`build/report/timing_summary.rpt:151` 的 `TNS Failing Endpoints` 是 0"这一格，
到底覆盖了收口 I/O 吗？**

本篇不给答案。要得出答案必须自己打开两处：
① `build/report/timing_summary.rpt` 的 `5. checking no_input_delay` 与
`6. checking no_output_delay` 两段（本次实测分别是 7 与 12，见 `:97-105`）；
② `report/timing/debt_ledger.md` 第 1 节的 `unconstrained_endpoints` 与
`io_unconstrained_ports` 两行（`:30-31`）。
答出来的判据必须同时包含"端点"和"端口"这两个量纲，并且说明它们为什么不能相减
（同类红线写在 `report/timing/debt_ledger.md:105-107`）。

第二题：**第 5 节说 `gap_max` 饱和不回卷——当前这份读数的语义是"精确值"还是"下界"？**
去查：`src/rtl/eth/link_monitor.v:87`、`:90-92` 与 `src/host/health_read.mjs:59`、`:451-453`，
说出"哪一行让它只能当下界"。
