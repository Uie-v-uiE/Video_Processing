# mechanics.md · 通用原理层：本项目用到、别处没解释的机制

口径：这一篇讲**通用原理**——本工程代码用到了、但其余 12 篇没有解释其所以然的东西。
每一讲的形状都是五层阶梯（① 零术语版并自带误导提示 → ② 不用它会看到什么现象 → ③ 精确定义加出处
→ ④ 它不是什么 + 在本工程哪一处能观察出差别 → ⑤ 辨认方法，写成"打开 X，看 Y，出现 Z 就是它"），
每节末尾再给两条本项目之外的应用场景。
连线、层次、逐行写法、取舍**不在这里重复**：层次看 `subsystem-map.md`，时间顺序看 `one-pass-walk.md`，
逐行看 `code-reading.md`，为什么这么搭看 `design-choices.md`，本工程的时钟与跨域全表看
`clocking-and-reset.md`，寄存器与包形看 `interface-contract.md`。
本篇里出现的每个 `文件:行` 都是一个落点：那条原理在我们这块板上真的能被观察或被打量。

读完这篇你能回答这三件事：

1. 这套机制在别人的项目/芯片里出现时，我凭什么在报告、波形或代码里认出它（每讲的第 ⑤ 层）。
2. 这些原理的官方口径具体写在哪份文档的第几页（每讲第 ③ 层 + 第 8 节的出处表）。
3. 哪些"看起来是收益"的数字其实是**射程变窄**造成的，怎么用一条命令把它证伪（第 6 节）。

目录

- 第 1 节 总线握手：VALID/READY 的独立性、突发与对齐、地址通路位宽、在途额度
- 第 2 节 跨时钟域：五种同步形状，以及亚稳态为什么只能降概率
- 第 3 节 存储与乘加的推断：写法怎么决定落到块 RAM、查找表还是触发器
- 第 4 节 建立/保持与裕量：报告里那几个数分别回答什么问题
- 第 5 节 缓存与 DMA：为什么"我写完了"不等于"对方读得到"
- 第 6 节 约束射程：按名字点人的语言，改名之后不会报错
- 第 7 节 本篇讲不出落点、因此挪给 `next-layer.md` 的机制
- 第 8 节 出处清单（文档号 / URL / 本机 PDF + 页码 + 核对日期）
- 第 9 节 自测题

---

## 第 1 节 总线握手：VALID/READY 的独立性、突发与对齐、地址通路位宽、在途额度

### 1.1 一讲：两个开关各表各的（VALID 与 READY 相互独立）

① **零术语版**：一条数据通道上有两个各自独立的开关——发的一方有一个"我这批东西准备好了"的灯，
收的一方有一个"我现在接得住"的灯。**两盏灯同时亮的那一个节拍，东西才交出去**；
谁都不许把"等对方先表态"当成自己表态的条件。
*这种简化会在"我以为对方不接，我就把东西收回去换一批"的情形误导你 —— 灯一旦亮起就不许换、不许撤，
要一直等到对方表态为止。精确版见下一层。*
（把 READY/VALID 说成"两盏灯"是比喻，不是实现；实现见
`src/rtl/axi/axi_frame_writer_gated.v:79` 的 `m_axi_rready` 驱动式与
`src/rtl/eth/axi_frame_saver64.v:74-79` 的 `awvalid`/`wvalid` 挂出。）

② **不用它会看到什么现象**：本工程的实测形状不是"丢一帧"，而是**整幅画错位**。
搬运机在 `abort`（超窗中止）时把接收开关 `m_axi_rready` 直接掉 0，但那些**已经被答应的**读数据拍
不会因此消失：它们等在下一帧门口，于是下一帧收下的头几拍其实是上一帧的数据
（原文注释：`src/rtl/axi/axi_frame_writer_gated.v:75-79`）。后果写在那三行里：整帧平移 + 帧尾越界写，
台架 `sim/tb_writer_abort.v` 的三条判据钉的就是它——`B3_new_frame_starts_at_own_head`（`:171`）、
`B5_new_frame_word_count`（`:176`）、`B6_new_frame_in_order`（`:177`）。
修法是"继续接、但丢掉不写"（`axi_frame_writer_gated.v:78-79` 的 `dropping`）。
第二种形状长在吞吐上：写侧每完成一个字都要等 AW→W→B 走一遍时，在途深度恒为 1，
总线往返延迟直接成为速率上限，板上的表现是"每包固定从第 48 字节起丢字"
（原文：`src/rtl/eth/axi_frame_saver64.v:5-7`，ISSUES #31 的结案）。

③ **精确定义 + 出处**：Arm《AMBA AXI Protocol Specification》，文档号 **ARM IHI 0022**，Issue J，
2023 年 3 月，§A3.2 "Channel handshake"，p.39（核对日期 2026-10-05；从 Arm 文档服务下载该 PDF
后用本机文本抽取读到的原文，URL 见第 8 节）。该页三条：
"Transfer occurs only when both the VALID and READY signals are HIGH"；
"A source is not permitted to wait until READY is asserted before asserting VALID"；
"When VALID is asserted, it must remain asserted until the handshake occurs, at a rising clock edge
when VALID and READY are both asserted"。同页还允许收的一方**等** VALID 到来再举 READY，
并允许 READY 在 VALID 到来之前再放下去。§A3.1.1 p.38 与 §A3.2 p.39 各写了一条
"there must be no combinatorial paths between input and output signals"（接口上不许用组合逻辑
把输入直接连到输出）——这一条才是"独立性"三个字的物理形式。§A3.3.1 p.41 单独把写请求通道说清：
`AWVALID` 必须保持到从机拉起 `AWREADY` **之后的那个时钟沿**，并建议 `AWREADY` 默认态取高。
本项目取值：`assign m_axi_rready = (active && !sk_full) || dropping;`
（`src/rtl/axi/axi_frame_writer_gated.v:79`）——驱动式里只有本机状态（是否忙、skid 满不满、是否在排空），
没有对端的 `rvalid`；`m_axi_arvalid` 只在 `arvalid && arready` 那一拍之后清（同文件 `:155`）；
写侧 `awvalid`/`wvalid` 各自独立挂出（`src/rtl/eth/axi_frame_saver64.v:74-79`）。

一处必须如实分开的地方：`src/rtl/axi/axi_frame_writer_gated.v:138-146` 的 `abort` 分支无条件把
`m_axi_arvalid` 清 0。按 p.39 / p.41 的字面，如果那一刻 `arready` 还没来，这就是"握手前撤 VALID"。
本仓库没有任何记录说明互联或 PS7 的 S_AXI_HP 因此报过错，也没有一条判据覆盖它 ⇒
**这一处记为【未确认】**：要问用户的是"要不要把它立成一条债，并补一支把 `arready` 压住再落 `abort`
的台架"；自己能分辨的办法是给互联接上接口协议检查器（protocol checker）后重跑一次搬运，看违例列表。

④ **它不是什么**：它不是"反压 = 允许丢"，也不是"两个信号必须同相"。
最容易混的是**AXI 的内存通道**与 **AXI-Stream 的流通道**：后者只有 `TVALID/TREADY/TDATA`
（加 `TLAST/TKEEP/TUSER`），没有地址通道、没有突发长度、没有写响应，
所以"4KB 边界""`WSTRB`"那一套不存在。本工程里两条通路同时在场，能直接对比：
DDR 侧是完整内存通道（`src/rtl/eth/axi_frame_saver64.v:26-38` 有 `awlen/awsize/awburst/awaddr/wstrb/bvalid`），
UDP 收包链内部是自定义三件（`src/rtl/eth/frame_reasm.v:15-19` 的 `p_valid/p_sof/p_eof/p_good`，
命名与 AXI 无关）。"两灯同时高才算数"这一条在两种形状里都成立，**只有前者**还要守 §A4.1 的边界规则
（见 1.2）。

⑤ **辨认方法**：打开 RTL，搜 `VALID` 的驱动表达式。表达式右边出现**同一条通道的** `READY`
（形如 `assign avalid = aready && have_data;` 或 `if (aready) avalid <= ...;`）⇒ 违反 p.39 第二条。
打开波形，看 `VALID` 一次抬起与一次落下之间有没有出现过 `READY` 为高的采样沿：
`VALID` 掉了而中间从未两灯同高 ⇒ 就是"撤 VALID"。
打开 Vivado 工程：`report_methodology` 里没有哪一条规则管握手合规
（本工程的读数见 `build/report/methodology.rpt:30-36`，全是 `DPIR-/LUTAR-/SYNTH-/TIMING-` 四族），
所以"方法学报告全绿"不等于"握手合规"，这一类要靠协议检查器。

### 1.2 一讲：一次说 N 段（突发长度、每段字节数、起始地址对齐、字节写选通）

① **零术语版**：一次交易可以说"我要连着搬 N 段"，但只给**第一段的地址**与**每段几个字节**，
后面每段落在哪儿由接的那一方自己往上加。所以"第一段地址"和"每段字节数"合起来决定整批数据的落点；
另外还有一个逐字节的开关，说"这一段的哪几个字节真有数据"。
*这种简化会在"我以为起点随便填都行"的情形误导你 —— 起点与段长合起来决定每一段用哪些字节道；
填错时没人报错，数据只是写进了邻居的地盘。精确版见下一层。*
（"写进邻居的地盘"是比喻，不是实现；实现见 `src/rtl/eth/axi_frame_saver64.v:80-86`
的 `wstrb` 按 lane 生成与 `:111` 的地址拼装。）

② **不用它会看到什么现象**：本工程的形状是"屏上均匀散布的黑点"。
写侧每拍往 64 位（8 字节）的数据道推一个容器，而像素是 2 字节一个：容器里哪几个 16 位道有数据
随分包长度逐包变化。旧实现把字节写选通恒写成 `8'hFF`（"整个容器都有效"），于是同一个容器被相邻两包
分两次写时，**后一次会把前一次的半个字覆盖成 0**；分包长度不是 8 的倍数（例如 1396 B）时
每帧 111 处、共 222 个 16 位像素变成黑洞（原文：`src/rtl/eth/axi_frame_saver64.v:80-86`）。
现行写法是每个 16 位道用一位 `keep` 展开成两根字节选通：
`assign m_axi_wstrb = { {2{keep_r[3]}}, {2{keep_r[2]}}, {2{keep_r[1]}}, {2{keep_r[0]}} };`（同文件 `:83-84`）。

③ **精确定义 + 出处**：仍是 ARM IHI 0022 Issue J（核对日期 2026-10-05）。
§A4.1 p.50 两句要紧："If the transaction includes more than one data transfer, the Subordinate must
calculate the addresses of subsequent transfers"（后续地址由从机自己算，所以起点必须讲清楚），以及
"A transaction must not cross a 4KB address boundary"（一笔交易不许跨 4KB 边界；同一句给出理由：
既防止跨到另一个从机，也限制从机要支持的地址递增位数）。§A4.1.1 p.50 是 `AxSIZE` 编码表：
`0b011` = 每段 8 字节；并写明 `Size` 是"每段允许的字节道数上限"，写选通才决定其中哪些字节真的有数据。
§A4.1.4 p.52-53 给出三种突发类型：`FIXED`（每段同址，`Length` 最多 16 段，有效字节道恒定但 `WSTRB`
可逐段不同）、`INCR`（每段地址按 `Size` 递增）、`WRAP`（起始地址必须按每段大小对齐，首段可以高于
回卷边界，文中说明它用于缓存行访问）。§A4.2.1 p.58 是写选通定义
"WSTRB[n] corresponds to WDATA[(8n)+7:(8n)]"，加一条硬要求
"A Manager must ensure that the write strobes are HIGH only for byte lanes that contain valid data"。
§A4.2.2 p.58 讲非满宽（narrow）传输：`INCR/WRAP` 时每段用**不同**字节道，`FIXED` 时每段用**同一**字节道。
§A4.2.4 p.62-63 给出非对齐起点的两种合法表达：用低位地址线表示未对齐，或给对齐地址并用字节选通表示。
本项目取值：读侧 `arsize = 3'b011`（8 字节/段）、`arburst = 2'b01`（INCR）、`arlen` 常数 15（16 段）
（`src/rtl/axi/axi_frame_writer_gated.v:37-38`、`:41`、复位默认值 `:105`），
每个突起的起始地址 `= base_r + burst_idx * (BEATS * 8)` = 每 128 字节一个起点（同文件 `:149`）。
"不跨 4KB"在这里由算术成立：一个突发恰好 128 B 且起点按 128 B 对齐，而一个 bank 只有 307200 B
（两个基址 `32'h1000_0000` / `32'h1008_0000`，`src/rtl/eth/ddr_bank_commit.v:9-10`），
128 B 对齐的段跨不过 4 KB 格线。写侧走另一条形状：`awlen = 8'd0`（单段）、`wlast` 恒 1、
`awsize = 3'b011`（`src/rtl/eth/axi_frame_saver64.v:40-44`），地址由打包器算好整字给出
（同文件 `:111` 的 `pack_base + {10'd0, cur_widx, 3'b000}`，按 8 字节左移三位）。
PS 侧的支持口径在 UG585 v1.13 §22.4.4 p.654：S_AXI_HP 口"内部带控制与数据 FIFO……
适合 DDR 里的视频帧缓冲这类负载"，同时提醒这层仲裁带来**更高的最小延迟**。

④ **它不是什么**：它不是"页对齐/缓存行"那类内存管理概念，也不是 DMA 描述符链
（"整帧一次提交"是另一件事，见 `design-choices.md` 第 3 节）。
最容易被当成同一件事的是 `WSTRB` 与"字节序"：`WSTRB` 只管**这一拍哪些字节道有数据**，
字节序管的是**一段之内字节怎么排**（IHI0022 §A4.2.3 p.61 用 byte invariance 讲后者）。
在本工程能观察出差别的是**症状形状**：写选通错 ⇒ 离散黑点（上面 ②）；
排空速率跟不上 ⇒ 与包边界对齐的**周期性**缺失。两种形状的判读规则本仓库已经写成脚本注释：
`src/host/ddr_stale.mjs:6-11`（丢字率对包内字节偏移强烈相关 ⇒ 下游平均排空速率跟不上；
丢字集中在几条连续地址长带 ⇒ 端口被长时间独占；`u32` 内两个 16 位不一致 ⇒ 丢在 16 位粒度）。

⑤ **辨认方法**：打开 RTL，`*_len`、`*_size`、`*_burst` 三兄弟同时出现并给出常数 ⇒ 这是内存通道的突发。
换算表：`len = 段数 − 1`；`size` 查 §A4.1.1 p.50 那张编码表（`0b011` 就是 8 字节）；
`burst` 查 §A4.1.4 p.52-53（`0b01` = INCR）。打开波形：一次 AR 之后应当连拍看到 N 段 R 数据、
地址通道整段不再出现、最后一拍 `RLAST` 为高 ⇒ 就是一个 burst。核对上界：把"每段字节数"与互联数据宽度对照
（本工程 64 位：`build/tcl/build_system_axigpio.tcl:100` 的 `PCW_S_AXI_HP0_DATA_WIDTH {64}`），
段字节数小于通道宽度 ⇒ 你在做 narrow transfer，要按 §A4.2.2 p.58 想清楚字节道怎么走。
### 1.3 一讲：地址是一根线，不是数组下标（地址通路位宽与越界）

① **零术语版**：给内存编号的那组线只有那么多根。编号大到线装不下时，多出来的位没有任何人会提醒你；
软件里越界至少会崩，硬件里它只是安静地写到别人的地盘上，写到哪儿由"哪些位被丢掉"决定。
*这种简化会在"我以为工具或总线会拦住越界"的情形误导你 —— 位宽截断发生在你的代码里，不在互联里；
报告里没有任何字段说"这次越界了"。精确版见下一层。*
（"写到别人的地盘"是比喻，不是实现；实现见 `src/rtl/eth/frame_reasm.v:144-152`
的 `wr_addr <= off[18:1]` 与上界门 `:152`。）

② **不用它会看到什么现象**：本工程有一条改完还没重刷位流的实案。
`frame_reasm` 的字节偏移来自**网络上任何人发的包**：填什么偏移，硬件就把字写到 `off[18:1]` 那个索引上。
`off[18:1]` 最大 131071，而一帧只有 76800 个 64 位字（307200 字节 = 153600 个 16 位字），
越界之后落在谁身上由下游 `axi_frame_saver64` 的地址乘法决定，而**它自己没有上界检查**
（原文：`src/rtl/eth/frame_reasm.v:144-152` 的 `#201` 注释）。修法是让写使能与行覆盖统计吃同一个边界：
`wr_en <= (off < FRAME_BYTES);`（同文件 `:152`），并留一个只增计数器 `stat_oob_off` 作证据出口（`:161`）。
改前红的凭据：`build/r98_201_before.txt`（越界包发了 2 次写、最大字索引 145 > 128），
台架判据 R1 在 `sim/tb_reasm_bounds.v`。第二种形状在仿真与硬件之间：非打包数组的越界写，
**xsim 直接丢弃，硬件按地址位宽截断**（登记原文：`report/known_issues.md:725`），
所以这一类问题上"台架绿"不能当证据。第三种形状是"名字对、宽度被吞"：
同文件 `:84-85` 明写行号**不许**用 `off[16:1]` 算——16 位像素索引会截断约 172/300 行，
后果是 `frame_done` 永不成立、屏上那一路变黑纹。

③ **精确定义 + 出处**：IHI0022 Issue J §A4.1 p.50 要求**从机自己算后续地址**，
这把"上界检查必须由持有这块内存的人做"写成了协议的后果；协议本身没有"数组越界异常"这一类响应。
Zynq 侧的地址分发口径在 UG585 v1.13 p.32 与 §5.4/§5.5（p.138-139）：DDR 与 OCM 由互联按地址段分发，
OCM 那 256 KB 是"at level of L2, but is not cacheable"。工程用的三个基址都在 DDR 段：
ETH 乒乓 `0x1000_0000` / `0x1008_0000`（`src/rtl/eth/ddr_bank_commit.v:9-10`）、
PS 专用第三 bank `0x1010_0000`（`src/rtl/top/pl_video_top.v:16`、`src/rtl/top/system_top.v:144`、
`src/ps/main.c:41-46`）。截断的形式在 RTL 里看得见：`src/rtl/eth/frame_reasm.v:151`
（`wr_addr <= off[18:1]`）、`src/rtl/axi/axi_frame_writer_gated.v:159`
（`fb_wr_addr <= sk_addr_q[18:2]`）、`src/rtl/eth/axi_frame_saver64.v:111`
（`{10'd0, cur_widx, 3'b000}` 拼满 32 位）。

④ **它不是什么**：它不是"地址通道的建立时间"（那是第 4 节的量），也不是缓存一致性（第 5 节）。
分辨方法在本工程很具体：越界写**不进时序报告**，也不进 `report_cdc`，只进**边界台架**。
`build/report/timing_summary.rpt:62-66` 那一串 `check_timing` 只回答"这个对象有没有被时序约束覆盖"，
没有一列回答"这个索引有没有超出数组"。可以对照的一处证据出口：`data/metrics.csv:17`
"越界读写的机会计数 190464 拍"（OSD 字模索引在 1024×600 有效区整屏走一遍时越出数组上界的拍数，
凭据 `build/evidence/r86_osd_t18_teeth_addr.txt`，判据 T18）——这道"机会地板"就是为了让
"屏上没现象"与"真的被门住了"两种说法可区分而存在的。

⑤ **辨认方法**：打开 RTL，搜地址是不是由**切片赋值**给出（`x[18:1]`、`x[18:2]`、`{pad, idx, 3'b000}`）。
出现切片就问三句，答不出任何一句就是没做：**(a)** 上界在哪里检查？**(b)** 谁检查（本模块还是下游）？
**(c)** 越界时有没有一个只增的计数器把这件事说出来？本工程三句的答案分别是
`src/rtl/eth/frame_reasm.v:152`（上界门）、同一处而不是下游 `axi_frame_saver64.v:111`（检查者）、
`src/rtl/eth/frame_reasm.v:161` 的 `stat_oob_off`（只增计数器）。
拿到陌生工程，在台架产物里搜 `oob`、`越界`、`bounds`、`R1`（`sim/tb_reasm_bounds.v`）、
`T18`（件 `build/evidence/r86_osd_t18_teeth_addr.txt`）这类边界判据名；一个都没有 ⇒ 这条通路的
地址上界未测。

### 1.4 一讲：反压决定的是速率，缓冲深度不替它（在途额度）

① **零术语版**：握手把"慢"往上游传，于是整条链的**平均吞吐**由最慢那一段决定。
在同一段路上，"我已经发出去、对方还没答"的份数（在途额度）越多，等回应的时间越能被重叠掉；
把本地缓冲区挖深只是把洪峰往后推，**推不出更高的平均速率**。
*这种简化会在"我以为加深 FIFO 就能不丢字"的情形误导你 —— 本工程的实测结论正好相反：
加深缓冲那一刀在板上毫无改善。精确版见下一层。*
（"把洪峰往后推"是比喻，不是实现；实现见 `src/rtl/eth/axi_frame_saver64.v:5-7` 的在途深度记录与
`:66` 的 `OST = 4'd8`。）

② **不用它会看到什么现象**：`src/rtl/eth/axi_frame_saver64.v:5-7` 记着两笔相邻的账。
ISSUES #31：每字走完 AW→W→B 时"在途深度恒 1"，HP0 的写延迟（约 40 拍，被显示拷贝抢端口时上百拍）
直接成为吞吐上限（约 20 MB/s），板上表现是"每包固定从第 48 字节起丢字"。
ISSUES #32：于是把 CDC 缓冲加到 8192 条，**上板毫无改善**，因为瓶颈是"平均排空速率"不是"深度"。
真正的改动是流水化：`OST = 4'd8`（同文件 `:66`）让 AW/W 并行挂出、B 只回收计数（`:74-79`）。
读侧同一个形状：`MAX_OUT = 3'd4` 个 16 拍突发在途 ≈64 拍，注释写的理由是"够盖住 HP0/DDR 读延迟，
并能在 25 行的窗口里维持约 1 拍/字"（`src/rtl/axi/axi_frame_writer_gated.v:44-47`）。

③ **精确定义 + 出处**：IHI0022 Issue J §A3.2 p.39 第一段就把握手称为 "two-way flow control mechanism"，
并说明它 "means both the Manager and Subordinate can control the rate that the information moves
between Manager and Subordinate"——这是"反压决定速率"的规范口径。
"多发几笔在途把延迟重叠掉"的厂商口径在 UG585 v1.13 §22.4.4 p.654：接在 HP 口上的高性能设备
"should be able to issue multiple outstanding transactions to take advantage of the AXI_HP FIFOs"。
本项目取值见上面 ②（`OST = 8`、`MAX_OUT = 4`）。

④ **它不是什么**：它不是"反压 = 丢数据"——本工程 `fifo_full` 时**确实丢字**，而且这条是被注释钉住的
既有语义（`src/rtl/eth/axi_frame_saver64.v:100`："原样保留 v6.4 语义：FIFO 满时该字被丢弃"）；
它也不是时钟域问题（第 2 节）。可观察差别在本工程有一处很干净：把满判据从"下一个写指针"改成
"当前写指针"，同时换来**锥体变短**（时序）与**可用深度从 `DEPTH−1` 变成 `DEPTH`**（容量），
两件事同源但不同量（记录：`src/rtl/eth/dc_fifo.v:37-47`；钉容量的台架 `sim/tb_cdc_capacity.v` 的 C1）。
只念一边就会把另一边的账记错。

⑤ **辨认方法**：打开任何一段"发出去要等回应"的 RTL，找**那个数在途份数的寄存器**
（名字常含 `outstanding`、`ost`、`inflight`、`beat`）。它的比较阈值就是这套设计允许的并发额度；
没有这种计数、每次只发一笔 ⇒ 吞吐上限 ≈ 通道宽度 × 频率 ÷ 往返延迟。
读板侧计数：如果丢字对**包内字节偏移**强烈相关（包首好、包尾差）⇒ 下游平均排空速率跟不上；
如果丢字集中在几条**连续地址长带**⇒ 端口被长时间独占。这两条签名写在 `src/host/ddr_stale.mjs:6-11`
（脚本用 JTAG 回读区分是哪一级丢字）。

**本节的题外场景**

- PCI Express 集成块（Xilinx《PG054: 7 Series FPGAs Integrated Block for PCI Express》v3.3，2017-10-04，
  本机 `D:/Xilinx/Resource/ZYNQ7020/Board_Resource/芯片手册/ZYNQ7000/pg054-7series-pcie.pdf`）：
  p.17 表 2-8 把事务钟频率与接口位宽绑成"静态选择"（`Interface width is a static selection`），
  64/128 位决定一拍能带多少字节；p.18 的字节有效说明写着
  "during a given beat (s_axis_tx_tvalid and s_axis_tx_tready both asserted)"，
  并给出位序映射"Bit 0 corresponds to the least significant byte"。这与 IHI0022 §A3.2 p.39
  的"两灯同时高才算交接"、§A4.2.1 p.58 的"`WSTRB[n] ↔ WDATA[(8n)+7:(8n)]`"是**同两条规则**换了接口名字；
  把本工程的收包链搬到 PCIe 核上时，要改的是这张名字表，不是规则。
- 10G 以太网 UDP/IP 协议栈 IP（本机 `D:/Xilinx/Resource/Reference Material/ad/10G Ethernet UDPIP 协议栈规格书.pdf`，
  Rev 1.0，2026-04-15）：p.1 明写"纯 RTL Verilog，无 AXI4-Lite，单时钟域"，p.3 端口表给的是
  `mac_tx_valid`(out) / `mac_tx_ready`(in) 与 `m_udp_rx_tvalid/tlast/tkeep/tuser`。
  也就是说：握手与字节有效掩码这两件事一个都没少，少的是地址通道与突发——
  这是"内存通道 / 流通道"两种形状并存的最直白对照（对应 1.1 ④ 与 1.2 ④）。
- 同一份规格书 p.3 还列出 `m_udp_rx_udp_length`、`m_udp_rx_dst_port` 这类**旁路信息**随流一起走，
  与本工程的旁路位（`src/rtl/eth/frame_reasm.v:29-30` 的 `frame_abort` / `rows_missed`
  这两个"只增不改行为"的观测口）形状相同：数据流之外另走一条"这一批健不健康"的边带。

小结 1：AXI 这一侧有四件事环环相扣——握手规则（谁都不许等对方，IHI0022 p.39/p.41）、
突发与对齐（起点 × 段长 × 写选通，p.50 / p.52-53 / p.58 / p.62-63）、地址位宽（越界无人报警，
落点 `frame_reasm.v:144-152`）、在途额度（决定速率的是它，不是深度，落点 `axi_frame_saver64.v:5-7`）。
小结 2：逐行讲搬运机在 `code-reading.md` 片段 6，包形在 `interface-contract.md` 第 6 节。下一步：第 2 节。

---

## 第 2 节 跨时钟域：五种同步形状，以及亚稳态为什么只能降概率

本节只讲"为什么这五种形状各自成立、不成立时现象长什么样"。全表与连线在 `clocking-and-reset.md`
第 3、4 节，逐行写法在 `code-reading.md` 片段 3、4、5。术语（→ 术语表）：跨时钟域、亚稳态、
三级同步器 / 打拍、`ASYNC_REG`、翻转位、格雷码、准静态总线 + 跳变沿、心跳、看门狗。

### 2.1 一讲：单 bit 电平，打两拍 / 三拍

① **零术语版**：对方那组节拍里的一根线，**不能直接**拿到自己这组节拍里用。
先用自己的节拍把它抄进一个开关，再抄一次、再抄一次；抄第三次的原因是
"第一次抄的时候很可能抄到一个还没定的值"，多给的节拍是给它时间定下来。
*这种简化会在"我以为多打两拍就绝对安全"的情形误导你 —— 打拍降低的是**出错概率**，
不是把错误变成不可能；并且它只对"一个会稳定下来的电平"有意义，对只亮一下的脉冲没有意义（见 2.2）。
精确版见下一层。*
（"抄进一个开关、再抄一次"是比喻，不是实现；实现见
`src/rtl/video/frame_commit_lock.v:64-69` 的 `{b2,b1,b0} <= {b1,b0,blank_tog}`。）

② **不用它会看到什么现象**：签名是"不可复现 + 与相位相关"，而不是每次错。
本工程有一处干净的对照（`src/rtl/video/frame_commit_lock.v:100-105`）：`copy_abort` 在 100 MHz 域只亮
**一拍（10 ns）**，消费者在 50 MHz 像素域，两只钟同源同相（同一 MMCM 出来的 100/50 MHz），
于是翻转沿**正好压在**采样沿上——注释的原话是"收不收得到取决于建立/保持窗口里的亚稳"。
把它改对的形状是翻转位（同文件 `:106-108`），台架 `sim/tb_v79_abort_toggle.v` 的相位扫描读数：
错开 4 ns 时裸采 0/3、翻转式 3/3（同注释 `:104-105`）。
第二种形状长在构建之间：`src/constraints/rk_zynq7020.xdc:37-42` 记的"同一份 RTL 的两个 WHS 数
是掷硬币"（r62 的 +0.001 与 r63b 的 +0.052），根因是 IDDR 走 BUFIO、fabric 走 BUFG，
同频同相却分走两条树、差 1.616 ns 由综合器插 hold buffer 硬补，每次补多少随机。

③ **精确定义 + 出处**：AMD《UltraFast 设计方法指南》UG949 中文版 2026.1，本机
`D:/Xilinx/Resource/Timing Analysis/ug949-vivado-design-methodology-zh-cn-2026.1.pdf`
（页脚同时保留来源行"UG949 (v2024.2) 2024 年 12 月 18 日"，核对日期 2026-10-05）。
p.112"时钟域交汇"一节："设计中存在的时钟域交汇 (CDC) 电路会直接影响设计可靠性。您可自行设计电路，
但 Vivado Design Suite 必须能够识别该电路，并且您必须正确应用 `ASYNC_REG` 属性"；同页的
**单比特 CDC 决策树**（图 86）把三枝分开：复位信号 → `XPM_CDC_SYNC_RST`；是脉冲 → `XPM_CDC_PULSE`；
否则 → `XPM_CDC_SINGLE`。p.108 给属性的物理效果：打上 `ASYNC_REG=TRUE` 后
"所有寄存器都将布局在单个 slice 中"。p.114 给级数这个旋钮：`DEST_SYNC_FF`
"可设置亚稳态保护寄存器的数量。该寄存器值会影响 MTBF、设计大小和交汇点处的时延"。
本项目取值：电平型三级同步 `(* ASYNC_REG = "TRUE" *) reg b0,b1,b2;`（消隐窗口从像素域跨到 AXI 域，
`src/rtl/video/frame_commit_lock.v:64-69`）与 `reg d0,d1,d2`（同文件 `:71-74`）；
格雷码捕获链四颗一起打属性（`src/rtl/eth/dc_fifo.v:23-27`，注释点名 `report_methodology` 的
TIMING-10 就是冲这个来的）；顶层纪律一句话：
"之间只准过 dc_fifo 的格雷码指针与 ddr_bank_commit 的 3 级同步器，其余一律禁止组合跨域"
（`src/rtl/eth/eth_udp_video_top.v:6`）。

④ **它不是什么**：它不是"两级和三级哪个够"的答案来源。UG949 p.114 给的是**迭代流程**，
并且把定量命令 `report_synchronizer_mtbf` 只列在 UltraScale 那一支（p.114 第 2 步的两个分支：
7 系列取默认值并称其为保守做法，UltraScale 才跑该命令）⇒
**7 系列上"几级对应多少 MTBF"的数值口径本次【未核实】**（要问用户：是否有厂商文档渠道可取；
本篇因此不给任何"几年一次"的数字）。
第二件"不是"：电平型同步器不修脉冲——本工程那一处"电平型 3 级同步在这里并不能修好它
（实测与裸采逐相位一模一样）"（`src/rtl/video/frame_commit_lock.v:102-103`）。
第三件：同步器前面不许挂组合逻辑——可观察差别的地点在 `src/rtl/util/src_mode.v:41`
（"下游 `pl_video_top` 拿 `mode` 去喂 axi 域的 3 级同步链，组合式等于同步器前面挂一级[组合]"），
以及 `report_cdc` 的拓扑分类里"同步装置前组合逻辑"那一条（UG949 p.138 列的七种之一）。

⑤ **辨认方法**：打开 RTL，找连续两三颗"数据端就是上一颗 Q"的寄存器（形如
`{s2,s1,s0} <= {s1,s0,d_in};`）就是它，然后看它们有没有 `ASYNC_REG`：没有 ⇒ 工具可以挪位、复制、
拆分，亚稳态传播窗口没保证。打开 `build/report/methodology.rpt`：
`TIMING-10 Missing property on synchronizer`（该文件 `:35`）就是"有同步器但缺属性"；
`TIMING-9 Unknown CDC Logic`（同文件 `:34`）是"工具认出那是跨域但不认识这个形状"。
**当前读数都不是 0**：各 1 条（同一张方法学表也印在 `build/report/timing_summary.rpt:44-52`）。
### 2.2 一讲：脉冲不许直接跨，要改成翻转位

① **零术语版**：只亮一个节拍的灯，对方可能整个错过它，因为两次"看一眼"之间正好夹着它。
正确的做法是别传"亮一下"，改成"我把一根常亮的灯**翻一个面**"——对方每拍盯着这根灯，
只要看到它换了面，就知道事情发生了一次。
*这种简化会在"我以为对方一定看得见那一拍"的情形误导你 —— 两只钟同频同相时，
事件沿恰好压在采样沿上的概率最高，此时"看得见"完全由建立/保持窗口里的亚稳决定（见 2.1 ②）。
精确版见下一层。*
（"把一根常亮的灯翻一个面"是比喻，不是实现；实现见 `src/rtl/eth/ddr_bank_commit.v:37-47`
的 `frame_done_tog <= ~frame_done_tog` 与 `fd_axi = fd1 ^ fd2`。）

② **不用它会看到什么现象**：本工程的形状是"屏停在旧帧 + 台账上少一次事件"。
裸采的台架读数 0/3、翻转式 3/3（`src/rtl/video/frame_commit_lock.v:104-105`，
`sim/tb_v79_abort_toggle.v`）。第二种是**事件被合并**：如果消费者只读电平，两次翻转落在同一次读里
计数就少一次。本工程为此把两次 `abort` 的最小间隔也写进设计——`WD_CYC = 32'd2_000_000` 个 AXI 拍
（100 MHz 下 = 20 ms，同文件 `:8`，计数与触发在 `:89-95`），并把这件事写进端口注释（`:26-27`）：
两次翻转至少隔 `WD_CYC`，"不会两次翻转落进同一像素周期被并成 0 次"。

③ **精确定义 + 出处**：UG949 中文版 p.112 的单比特 CDC 决策树把"是不是脉冲"单独分一枝
（脉冲走 `XPM_CDC_PULSE`），这就是"脉冲要变成事件语义再跨"的官方形式。
本仓库技能卡的同一条更硬："脉冲跨域只能走翻转式；发射触发器各自独立"
（`skills/rtl/cdc-and-async-discipline/SKILL.md:78-82`：把"用几级同步器同步脉冲"列为反例——
"接收钟周期长于脉冲宽度时事件整拍丢掉；要传事件就变电平或走握手"，同段还把"只同步了标志、数据仍是多位"
与"格雷码用错处"列为反例）。
本项目取值（四件齐全的一套）：源侧翻转（`src/rtl/eth/ddr_bank_commit.v:37-41`）、
目的域三级捕获（同文件 `:42-46`）、异或出边沿 `fd_axi = fd1 ^ fd2`（同文件 `:47`）、
以及**发射触发器各自独立**：`abort_tgl` 与 `blank_tog` 分处两侧
（`src/rtl/video/frame_commit_lock.v:106-108`、`:59-68`），旋转角那边把这条写在注释里
（`src/rtl/process/rotate/angle_ctrl.v:22`："顶层为它单起一个翻转触发器（不共用
`sof_tgl`/`z_hb_tog`）"）。

④ **它不是什么**：它不是"电平语义的发布请求"。本工程把两者分开的例子最清楚：PS 的发布位是
**电平语义**（会合并），因此单独成模块以便台架逐相位验（`src/rtl/util/ps_publish.v`，
登记于 `_sources.md` 第 1 节与 `subsystem-map.md` 第 5 节）；而 `frame_done` 是**事件语义**
（不许合并），因此必须翻转（`src/rtl/eth/ddr_bank_commit.v:37-47`）。可观察差别的地点：
`data/metrics.csv` 的 ETH 零丢包行（凭据 `report/perf_report.md`）说的是"帧事件一次都没丢"，
而串口 `[STAT]` 里的帧计数是电平合并后的结果——两者不等价。

⑤ **辨认方法**：打开源侧那一拍，看有没有 `if (evt) tog <= ~tog;`——**有翻转** ⇒ 这是脉冲跨域的
正确形状；只看到 `pulse <= evt;` 而目的域 `if (pulse_d) ...` ⇒ 违反。打开目的侧，看边沿是不是异或
（`q1 ^ q0`，或本工程这种取三级中间两颗的 `fd1 ^ fd2`）；出现 `&` 或裸采某一级都不是脉冲跨域。
在报告侧：`report_cdc` **不点名信号**，所以这件事只能靠结构判据 + 台架相位扫描
（登记原文：`src/rtl/video/frame_commit_lock.v:103-104`"这条不会体现在 `report_cdc` 里
（那份报告只有'时钟对 + 端点数'的粒度）……两份 cdc.rpt 逐行相同"）。

### 2.3 一讲：多 bit 不许各打各的拍——格雷码指针

① **零术语版**：一次要传**好几个**开关的状态时，最危险的是它们换值的时间不完全一样：
对方可能在"一半新、一半旧"的那一刻看了一眼，于是读到一个既不是旧值也不是新值的编号。
格雷码的做法是让相邻编号之间**只有一位**会动，这样"半新半旧"这件事就不存在了。
*这种简化会在"我以为格雷码把所有多位量都救得了"的情形误导你 —— 它只救**相邻取值有意义**的量
（指针、序号），不救任意数据总线；数据总线要走 2.4 那一种。精确版见下一层。*
（"看一眼就采到一半新、一半旧"是比喻，不是实现；实现见 `src/rtl/eth/dc_fifo.v:81-95` 的两条捕获链与 `:29-32` 的 `bin2gray`。）

② **不用它会看到什么现象**：异步 FIFO 的两个判据会**同时**看错方向。把二进制指针直接打两拍，
跨域那一刻可能采到 `0111 → 1000` 之间的任意中间态，于是"满"被判成"空"（数据被丢）
或"空"被判成"满"（链子卡死）。本工程的写法是把这件事写死在结构里：`wbin`/`rbin` 二进制指针
**永不跨域**，跨域只有格雷码版本（`src/rtl/eth/dc_fifo.v:81-95`，注释原话"二进制指针永不跨域"），
转换式只有一行 `bin2gray = b ^ (b >> 1);`（同文件 `:29-32`），判据两条：
`rd_empty = (rgray == wgray_s1)`（`:68`）、
`wr_full = (wgray == {~rgray_s1[ADDR_W:ADDR_W-1], rgray_s1[ADDR_W-2:0]})`（`:47`）。
还有一处形状值得记：这条锥体的长度直接决定时序——原式（用"下一个写指针"）把 14 位加法 +
二进制转格雷 + 比较整条挂在 `wr_en → ENARDEN` 上，r87 的最差路径因此是 8 级逻辑、0.152 ns
（记录：`src/rtl/eth/dc_fifo.v:40-44`，那份逐轮件现在在 `build/r87_timing_summary.rpt` 这个位置）。

③ **精确定义 + 出处**：UG949 中文版 p.112 的多比特 CDC 一节把多位量的跨域方式列成
"格雷码 + 指针 / 握手 / FIFO"三类；p.138 列出 `report_cdc` 能识别的拓扑，其中"多位总线同步装置"
就是把多位数据直接打拍这一危险形状点了名。本项目取值：`ADDR_W = 13` ⇒ 深度 8192、指针 14 位
（`src/rtl/eth/dc_fifo.v:3-5`、`:19-22`），顶层例化
`dc_fifo #(.DATA_W(36), .ADDR_W(13)) u_cdc`（`src/rtl/eth/eth_udp_video_top.v:298`，
同文件 `:295-296` 给出容量账：8192 条 36 位 = 16 KB，用来吸收"显示拷贝独占 HP0"那一整个窗口）。
满判据用"对端格雷码最高两位取反、其余相等"，省掉一次二进制比较（`src/rtl/eth/dc_fifo.v:35-47` 的注释与代码）。

④ **它不是什么**：它不是"把数据也编成格雷码"；也不是"有格雷码就不需要 `ASYNC_REG`"——
本工程两件事同时做（`src/rtl/eth/dc_fifo.v:23-27`），注释说四颗一起打属性的理由是
"官方口径是让整条链待在一起"。可观察差别的地点在报告字段：`build/report/cdc.rpt:17` 那一行
（`clk_fpga_0 → clkout0_1`，Critical）给出 Endpoints 103 / Safe 102 / **Unsafe 1** / Unknown 0 /
**No ASYNC_REG 2**；格雷码本身在报告里**不可见**，可见的是"这条配对上还剩几处不安全"。
本仓库为这件事有一把专用尺子：`build/scan_async_reg_coverage.py`，改前 A2 RED missing=2、
件 `build/evidence/r113_async_reg_scan.txt`（出处是 `src/rtl/eth/dc_fifo.v:26` 的注释登记；
**本次未重跑该脚本** ⇒ 该读数按引用处理，不是本次实测）。

⑤ **辨认方法**：打开异步 FIFO 的代码，问三句：**(a)** 跨过去的是格雷码还是二进制？
**(b)** 满/空判据用"当前指针"还是"下一个指针"？**(c)** 捕获链有没有 `ASYNC_REG`？
三句都答得出才算这条完成。要搜的关键形状：`^ (b >> 1)`、`bin2gray`、`{~x[hi], x[lo]}`。
在报告侧：打开 `build/report/cdc.rpt`，看该时钟对那行的 `Unsafe` 与 `No ASYNC_REG` 两列
（列名在文件头 `:15-16`）；`No ASYNC_REG > 0` 就是"有捕获寄存器缺属性"。

### 2.4 一讲：宽总线不"同步"，只"采快照"（准静态 + 跳变沿 + 心跳）

① **零术语版**：要跨过去的是一整块会变的数字（本工程那块是 320 位），打拍救不了它。
办法是：**先把整块写完**，写完后翻一下那根"我翻面了"的灯；对方在自己的节拍里看到灯翻了面，
就在那一刻抄一份。抄到的必然是一份完整值，因为写的一侧在下一轮开始之前不会碰它。
*这种简化会在"我以为对方一定来得及抄"的情形误导你 —— 前提是"源总线保持的时间远大于一次跨域延迟"；
源头刷新比这快就会撕开快照。本工程的依据是源头最快 1 ms 一次（见 ③）。精确版见下一层。*
（"写完一整块再翻一下那根灯、对方在那一刻抄一份"是比喻，不是实现；实现见 `src/rtl/eth/snap_cross.v:41-45`、`:70-71`。）

② **不用它会看到什么现象**：读回的值是"上半截新的、下半截旧的"拼出来的。本工程的这条数据流是
**仪表**：320 位健康快照 `lm_bus`（`src/rtl/eth/link_monitor.v:32-33`）从 125 MHz 收包域跨到像素域
显示在 OSD 上；撕裂的后果是屏上那一格显示一个既不是上一轮也不是这一轮的数。
`link_monitor.v:48-49` 记了同一族的**另一次**事故形状："拆两拍的版本记账与 min/max 全对，
但 `lm_bus` 快照在记账前就被采走 ⇒ 台架红两条"，下一句是纪律：
"仪表的读数节拍是对外契约，不许为了时序去挪它。"
第二种现象更绕：`src/rtl/eth/snap_cross.v:6-7` 写的是 RTL8211F 断链时**不停供 RXC 而是把它拉到约 1/48**，
于是心跳一直在、"时钟消失"那一条永不触发；文件头把关键方向钉成一句：
"**源时钟变慢 ⇒ 目的域量到的心跳间隔变长**（不是变短）"。

③ **精确定义 + 出处**：UG949 中文版 p.137 是这条做法的依据："……此类同步电路不依赖时序正确性，
并且可以最大限度降低发生亚稳态的概率"；p.112 的多比特分支给出"握手 / 双口存储 / 格雷码"三类；
p.138 补一句"Report CDC 不提供时序信息，因为时序裕量对于跨异步时钟域的路径没有意义"。
本项目取值：`snap_cross` 的参数 `W = 320`、`DST_HZ = 25_175_000`、`HB_TO_MS = 100`、`SLOW_MS = 5`
（`src/rtl/eth/snap_cross.v:9-12`），`FAST_ENOUGH` 把 1 ms 与约 50 ms 分居两侧（同文件 `:34`），
沿捕获三件套 `ts <= {ts[1:0], bus_tog}` / `bus_edge = ts[2] ^ ts[1]` / `if (bus_edge) bus_q <= bus`
（同文件 `:38-45`、`:70-71`），两条独立判据 `hb_gone`（时钟停）与 `hb_slow`（时钟退化）在 `:48-69`。
源侧保持时间的依据写在同文件 `:3-5`："源总线至少保持到下一次写入（本项目 ≥1 ms）"，
而跨域延迟是"3 级 + 1 拍"。归属纪律另有一句：
"跨域（像素域 OSD / PS 侧 GPIO）由消费方用 `snap_cross` 完成"（`src/rtl/eth/eth_udp_video_top.v:59`）。

④ **它不是什么**：它不是异步 FIFO——FIFO 处理"两边连续交数据"，这里处理"偶尔更新、经常读"；
也不是"加了握手回路就安全"——这条路上没有反向握手，只有**单向的沿**加**独立心跳**。
可观察差别的地点在"能不能为时序挪节拍"：FIFO 那侧的判据可以改（2.5 的满判据那一刀就改了），
快照这侧的读数节拍不许改（`src/rtl/eth/link_monitor.v:48-49`）。
第三条"不是"：`report_cdc` 认得出"由 MUX 和 CE 控制的电路"这类形状（UG949 p.138），
但它**不点名信号**，所以"这条快照是不是准静态"只能由代码与台架证明。

⑤ **辨认方法**：打开源侧，找"整块写完的那一拍翻一位"的两行（`bus_tog <= ~bus_tog`）；
打开目的侧，找 `ts <= {ts[1:0], tog}` + `edge = ts[2] ^ ts[1]` + `if (edge) bus_q <= bus` 这三件套。
**在目的域逐位打拍一根宽总线**就是错的形状，它会在 `report_cdc` 里以"多位总线同步装置"出现
（UG949 p.138 那一条）。判据级辨认：这条跨域不会出现在时序汇总的失败端点里（被时钟组排除，见 4.5），
所以只能查结构表 `clocking-and-reset.md` 第 3 节 + 台架。
### 2.5 一讲：异步 FIFO 是 2.1 与 2.3 的组装，判据全在指针上

① **零术语版**：把"单 bit 打拍"和"格雷码指针"合起来，就得到一个两边各用自己的节拍读写同一块内存的队列。
写的一侧数"我写了几个"，读的一侧数"我读了几个"，两边各自把序号变成只动一位的形式告诉对方，
于是"空"和"满"各退化成一次比较，而不是两次通信。
*这种简化会在"我以为深度就是可用条目数"的情形误导你 —— 判据写法会让深度少一格，
而且少一格这件事在模块级台架里看不见。本工程这一格是实测改回来的（见 ②）。精确版见下一层。*
（"两边各数自己写了几个、读了几个"是比喻，不是实现；实现见 `src/rtl/eth/dc_fifo.v:49-79` 的两套指针与 `:47`、`:68` 的两条判据。）

② **不用它会看到什么现象**：两个方向都错。判据太乐观 ⇒ 还没落盘的数据被当成已交付；
本工程那一例是帧尾 4 字节被写进下一帧的 bank、屏上右下角少 2 个像素
（原文：`src/rtl/eth/ddr_bank_commit.v:6-7`，配套门 `TAIL_GUARD` 在同文件 `:11`、`:49-51`）。
判据太悲观 ⇒ 可用深度少一格，并且那条锥体会拖垮时序
（`src/rtl/eth/dc_fifo.v:40-44`：改前 8191、改后 8192，由 `sim/tb_cdc_capacity.v` 的 C1 钉住）。

③ **精确定义 + 出处**：结构要件在 UG949 中文版四处：p.112（两枝决策树）、p.108（`ASYNC_REG` 效果）、
p.114（`DEST_SYNC_FF` 与 MTBF 的迭代流程）、p.115（"XPM CDC 提供了自带的
`set_max_delay -datapath_only` 约束"）。本项目实现要件逐条对应：双口存储
（`src/rtl/eth/dc_fifo.v:20` 显式 `ram_style="block"`）、写口不带复位（`:59-63`，注释
`memory write: no reset → BRAM-friendly`）、两套指针与各自复位（`:49-57`、`:65-79`）、
两条互反的捕获链（`:81-95`）、两条判据（`:47`、`:68`）、容量 `DATA_W = 36, ADDR_W = 13` ⇒ 8192 条
（`:3-5`、`:19`）。

④ **它不是什么**：它不是同步 FIFO——同一只钟下可以只用二进制指针比较，本工程打包 FIFO 就是这种
（`src/rtl/eth/axi_frame_saver64.v:52-58`：`fifo_full` 用"高位不同、低位相同"，
`fifo_empty` 直接比 `wptr == rptr`）。也不是"共享内存 + 软件轮询"。可观察差别的地点：
同一条链上两种存储并存且刻意不同——CDC 用块 RAM 做深缓冲（8192 条，
`src/rtl/eth/eth_udp_video_top.v:295-298`），skid 用分布式 RAM 做 64 条
（`src/rtl/axi/axi_frame_writer_gated.v:48-54`），理由就是 1.4 的"平均排空速率"与"每拍可用性"
不是同一件事。

⑤ **辨认方法**：打开一份没见过的 FIFO，先看**复位是不是两套**（`wr_rst_n` / `rd_rst_n` 分开 ⇒ 异步）；
再看**跨过去的只有指针还是数据也跨**；最后看空满判据两侧各用谁家的时钟。
在门禁侧，本仓库的读法值得照抄：`build/gates.sh:101-104`——
"端点数取倒数第 5 个字段、unsafe 取倒数第 3 个，而不是固定列号（CDC Type 的 token 数会变）"；
判红条件是"出现新的时钟配对"或"某配对的 unsafe 变大"（同文件 `:125-131`，ISSUES #65 立案）。

### 2.6 一讲：亚稳态为什么只能降概率，以及工具射程的粒度

① **零术语版**：触发器要在一个沿上"把输入抓住"。如果输入正好在那一刻换值，输出会有一段很短的时间
悬在既不 0 也不 1 的电平上；它最终会落到某一边，但**落到哪一边、什么时候落定都不由你决定**。
同步器做的事是给这段悬空多留几拍时间，让"还没定"的概率随着拍数迅速变小——不是变成零。
*这种简化会在"我把'概率很小'读成'这一版量过'"的情形误导你 —— 概率小不等于已验证；
本工程的器件这一族上，没有任何一个报告字段给出那个概率的数值（见 ③ 末）。精确版见下一层。*
（"悬在既不 0 也不 1 的电平上、给它几拍时间定下来"是比喻，不是实现；可核对点是 `src/rtl/eth/dc_fifo.v:23-27` 的 `ASYNC_REG` 声明与 `build/report/cdc.rpt:15-18` 的 `Unsafe`、`No ASYNC_REG` 两列。）

② **不用它会看到什么现象**：三个签名，本仓库都有现场记录。
(a) 与相位相关、不可复现：`frame_commit_lock.v:100-105` 那一例（裸采 0/3、翻转式 3/3）。
(b) 构建之间摇摆：`rk_zynq7020.xdc:37-42` 记的 r62 `WHS +0.001` 与 r63b `+0.052`，
根因是两棵时钟树差 1.616 ns 由工具硬补。
(c) **毛刺被当成事件采走**：`src/rtl/eth/eth_udp_video_top.v:373-380` 那段 `#209` 记录——
一位 16 位计数器的**组合或缩**被像素域三级 `ASYNC_REG` 链的第一拍直接采走，
计数器进位的那几拍或树会出毛刺，采进去就是一次假的"链路掉"；同一段注释还补了一句更狠的：
"RTL 仿真没有门延迟，`|s_pkts` 在仿真里永不出毛刺"，所以判据只能是**结构**判据
（改前红凭据 `build/r98_cdc_details.txt` 的 CDC-10 行）。

③ **精确定义 + 出处**：UG949 中文版三处合起来给出可核对的口径。
p.137："……此类同步电路不依赖时序正确性，并且可以**最大限度降低发生亚稳态的概率**"，
同段还强调"即使时钟周期相同，从不同时钟源生成的时钟仍为异步关系"。
p.114：`DEST_SYNC_FF` 的取值"会影响 MTBF、设计大小和交汇点处的时延"，且"对于 7 系列器件，
选择 `DEST_SYNC_FF` 的默认值。这是一种满足典型可靠性要求的保守方法。对于关键设计，
请执行进一步分析"；定量命令 `report_synchronizer_mtbf` 只出现在 UltraScale 分支。
p.138："Report CDC 不提供时序信息，因为时序裕量对于跨异步时钟域的路径没有意义"，并列出的七种拓扑含
"多位总线同步装置""同步装置前组合逻辑""多时钟扇入到同步装置"。
⇒ **7 系列的 MTBF 数值口径本次【未核实】**（本仓库既无该命令读数、也无带参数的公式来源），
所以这一篇不给任何"几年一次"的数字，只写"结构 + 计数 + 相位台架"三件。
本项目取值：五处 `ASYNC_REG` 声明（`src/rtl/eth/dc_fifo.v:27`、
`src/rtl/eth/ddr_bank_commit.v:42`、`src/rtl/eth/snap_cross.v:36-37`、
`src/rtl/video/frame_commit_lock.v:64`、`:71`）；两条未识别读数
（`build/report/methodology.rpt:34-35`，TIMING-9 = 1、TIMING-10 = 1，都不是 0）；
`build/report/cdc.rpt:17-22` 的 `Unsafe` / `Unknown` / `No ASYNC_REG` 三列计数。

④ **它不是什么**：它不是"时序违例"。本工程最干净的对照就是 ②(c) 那条：组合毛刺被采样这件事
**不会**出现在 WNS/WHS 里（同域路径完全 MET），也不会出现在 `report_cdc` 的信号级列表里
（那报告只给时钟对与端点数，`frame_commit_lock.v:103-104`）。
第二件：它不是"被时钟组排除就等于已解决"——`report/timing_global.md:152` 写的是
"组排除下的路径本来就不进 WNS，所以'改了 WNS 没动'是预期，不是证据"；
`report/timing_global.md:146-147` 给的补救是"官方口径是给同步器补一条**有出处的**
`set_max_delay -datapath_only`（数值口径按目的时钟周期与建立时间推，不许随手填 ns）"，
出处正是 UG949 p.115。可观察差别的地点：本工程的四条界写在候选件里、**没有进构建**
（`src/constraints/r114_io_async.xdc:57-66`；加载清单只有两个文件，
`build/tcl/build_system_axigpio.tcl:31`、`:36-37`）。

⑤ **辨认方法**：拿到一份 `report_cdc` 产物，看四列：`Safe`、`Unsafe`、`Unknown`、`No ASYNC_REG`
（本工程的列名在 `build/report/cdc.rpt:15-16`）。`Unsafe > 0` ⇒ 有结构没被认成同步器；
`No ASYNC_REG > 0` ⇒ 有捕获寄存器缺属性；`Unknown` 很大 ⇒ 工具看不清这条跨域
（本工程 `sys_clk → eth_rxc` 那行 Unknown = 530，同文件 `:18`）。
拿到一份时序报告，发现某条结构上有跨域**根本不在 Inter Clock Table 里**（本表只有两对，
`build/report/timing_summary.rpt:192-199`）⇒ 那是被时钟组排除的形状；
分辨办法是把排除临时去掉跑一次对照（本工程就是这么量的，件
`build/evidence/r115_c2_scratch/option_a_console.txt`）。

**本节的题外场景**

- 高速变换器接口 JESD204B（《JESD204B 应用指南》中文版，本机
  `D:/Xilinx/Resource/Reference Material/ad/JESD204B应用指南_中文版.pdf`，78 页）：p.15 讲链路必须先用
  CGS/ILAS 两阶段建立同步才能传数据；p.18 讲"接收器将把数据送入 FIFO，然后在下一个 (Rx) LMFC 边界
  开始输出数据"，并把这个已知关系命名为**确定性延迟**；p.22 要求把最大时钟与 SYSREF 偏斜算进 PCB 布局。
  这三段正好是 2.4（多帧边界 = 准静态窗）与 2.5（异步队列）在另一类系统上的形态，
  而且**没有一条能靠时序报告证明**。同页 p.20 的排查清单还给了"时钟退化"这一族在别的系统上的样子：
  "周期性或带隙周期性 SYSREF 或 SYNC~ 信号的建立和保持时间无效"会让链路退回 CGS/ILAS 重来。
- PCI Express 集成块的复位与钟释放（PG054 v3.3 p.16、p.13）：`user_clk_out` 的说明是
  "guaranteed to be stable at the selected operating frequency only after `user_reset_out` is deasserted"，
  而 `user_reset_out` 会因带内复位（Hot Reset、Link Disable）自动拉起、`sys_rst_n` 对它无效（p.16）；
  p.13 又写"The system reset signal is an asynchronous input"。通用形状是：
  **消费者必须等一条跨域过来的状态位**，不能假设"钟在 = 钟可信"。本工程对应的是 2.4 的心跳
  与 `link_monitor` 的两条判据（`src/rtl/eth/snap_cross.v:48-69`）。
- HDMI/DVI 源端采样关系（本机候选约束 `src/constraints/r119b_hdmi_tp1_pinclk.xdc:4-8`）：
  把 0.20 Tcharacter 的 ±4.000 ns 窗挂到片内 250 MHz 串行钟（周期 4.000 ns）上，窗确实生效
  （`Slack (VIOLATED): -3.482 / -3.458 / -3.474 ns`），但**参考量纲错了**——规范那个数是对 TMDS 钟
  （本档 20.000 ns）定义的（该文件 `:8`）。与亚稳态同族之处是：**采样关系错了的时候，
  报告只会告诉你窗内/窗外，不会告诉你在别人家里采**（同文件 `:16-17` 明说"量出来的 slack 只能说明
  这一族约束在 SDC 里怎么表达，不能当'过了 CTS'"）。

小结 1：六种形状各有唯一适用面——电平打拍（单 bit、会稳定）、翻转位（单事件、不许合并）、
格雷码（相邻取值有意义的计数）、准静态 + 沿 + 心跳（宽数据、慢刷新）、异步 FIFO（两边连续交数据）、
以及"结构判据 + 相位台架"这套替掉数值证明的做法。选哪一种的判据是
"数据变化频率 ÷ 采样频率"和"错一次的代价"，不是"看起来哪个更稳"。
小结 2：官方口径集中在 UG949 p.108/p.112/p.114/p.115/p.137/p.138 六页；7 系列的 MTBF 数值口径
记为【未核实】。跨域点全表在 `clocking-and-reset.md` 第 3 节。下一步：第 3 节。

---

## 第 3 节 存储与乘加的推断：写法怎么决定落到块 RAM、查找表还是触发器

本工程的存储选型与两处回滚记在 `design-choices.md` 第 6、7 节，逐行写法在 `code-reading.md` 片段 3、7。
术语（→ 术语表）：BRAM / 分布式 RAM / LUTRAM。

### 3.1 一讲：三岔口由深度、位宽与读口形状决定

① **零术语版**：一段"数组 + 按下标读写"的代码，工具会问三件事再决定用什么搭：这个数组有多少**行**？
每行多少**位**？读的时候要不要"同一拍就要结果"？行数少就用查找表搭（读可以异步、但吃逻辑），
行数多就用片上的专用存储块（省逻辑、但**读必须等一拍**），两个都不用就退化成一个个触发器
（吃触发器吃得凶）。
*这种简化会在"我以为工具总会自动挑最经济的搭法"的情形误导你 —— 它会为了**关住时序**主动改成
更贵的搭法，而且只在一份方法学报告里说一声。精确版见下一层。*
（"三岔口"、"用查找表搭"、"专用存储块"是比喻，不是实现；实现见 `src/rtl/eth/dc_fifo.v:20` 的 `ram_style="block"`、`src/rtl/axi/axi_frame_writer_gated.v:53-54` 的 `ram_style="distributed"` 与 `:50-54` 的退化记录。）

② **不用它会看到什么现象**：三笔实测，代价数量级不同。
(a) **退化成触发器**：skid 缓冲原先把数组读写放在**带异步复位的控制块**里，
综合报 `Synth 8-4767`"Block RAM or DRAM implementation is not possible"，64×83 bit 全掉进触发器，
注释写"约占整机剩余寄存器的一半"（`src/rtl/axi/axi_frame_writer_gated.v:50-54`）。
(b) **同一族更凶的一次**：512×100 bit 的数组被综合成触发器时是 5.1 万个 FDRE，
"占整机 Slice Register 的 94%，`FW=11` 直接 DRC UTLZ-1"；显式要分布式 RAM 之后只要约 800 个 LUT-RAM
（`src/rtl/eth/axi_frame_saver64.v:10-13`、`:46-50`），同文件 `:104-108` 还留一组对照数：
task 写法 FF=32904 / LUTRAM=0，现写法 FF=85 / LUTRAM=864。
(c) **工具自己降级**：现役 `SYNTH-5 Mapped onto distributed RAM because of timing constraints`
**336** 条（`build/report/methodology.rpt:32`），展开实例名与原因句在 `:63-66`
（`u_pl/u_blur/lb1_reg_0_127_0_0`，"The timing constraints suggest that the chosen mapping will yield
a better timing"）；另有 `SYNTH-6 Timing of a RAM block might be sub-optimal` **98** 条（同文件 `:33`）。
净落到报告字段上的数：`LUT as Distributed RAM` 4044（`build/report/utilization.rpt:38`）、
`RAMD64E` 4044（同文件 `:195`）、`Slice LUTs` 14154（`:35`）、
Block RAM Tile **95.5 / 140 = 68.21 %**（`:106-107`：RAMB36/FIFO 93 只 + RAMB18 5 只）。

③ **精确定义 + 出处**：UG949 中文版 p.50"实现 RAM 时的性能注意事项"给的是深度这条主轴：
"RAM 所需深度即第一项标准。深度高达 64 位的存储器阵列通常在 LUTRAM 内实现，其中，深度不超过 32 位时，
每个 LUT 映射 2 位，深度高达 64 位时每个 LUT 映射 1 位……深度超过 256 位的存储器阵列一般在块存储器中实现"，
紧随其后的条目是"使用输出流水线寄存器"。p.53 给属性语义：靠综合时在 HDL 的存储器声明上设置
`ram_style` 属性来决定映射成哪一类块（该页举的是 UltraRAM 那一例，`"block"`/`"distributed"` 同规则）。
块 RAM 的物理形状在 UG473（7 series Memory Resources，本机
`D:/Xilinx/Resource/Reference Material/6-Xilinx Zynq系列部分官方手册/ug473_7Series_Memory_Resources.pdf`）
p.11：36 Kb 块可配成"…2K x 18, 1K x 36, or 512 x 72 in simple dual-port mode"，
18 Kb 块可配成"…1K x 18 or 512 x 36"，同页并写"Write and Read are synchronous operations"。
读延迟的数值在 DS187（XC7Z010/020 数据手册 v1.21，2020-12-01）p.46 表 65：-2 档 Clock-to-Out
不带输出寄存器 2.13 ns、带输出寄存器 0.74 ns。本项目取值：显式 `(* ram_style = "block" *)` 四处
（`src/rtl/eth/dc_fifo.v:20`、`src/rtl/eth/sync_fifo.v:21`、`src/rtl/process/bilin/fb_bilin.v:142`、`:184`；
帧缓存另见 `src/rtl/video/frame_buffer.v:20`、`frame_buffer_db.v:22-23`、`frame_buffer_w64.v:37-38`）；
显式 `(* ram_style = "distributed" *)` 的十二处（`axi_frame_writer_gated.v:53-54`、
`axi_frame_saver64.v:48-50`、`proc_box_blur.v:19-20`、`proc_sharpen.v:20-21`、`proc_sobel.v:20-21`、`:27`、
`proc_morph.v:40-44`、`gamma_lut.v:27-29`）。

④ **它不是什么**：它不是"片外内存"（DDR/OCM 是另一条路，乒乓 bank 那条在术语表第 15 项）；
也不是 ARM 的缓存（第 5 节）。最容易混的是"分布式 RAM"与"把块 RAM 配成窄而深"：前者是 LUT + MUXF
搭出来的读写阵列（`RAMD64E`、`SRL16E`、`SRLC32E` 三个原语，见
`build/report/utilization.rpt:195` 与其下两行），后者是一块真 BRAM。可观察差别的地点就是那两行：
**两个不同的资源池**，一个降一个升不一定是坏事，但必须两个一起念
（`build/report/utilization.rpt:37-39` 与 `:106`）。

⑤ **辨认方法**：打开工程，`grep -n "ram_style" src/rtl/**/*.v` 看有没有显式声明；
打开综合日志，搜这四个号：`Synth 8-4767`（推不出 RAM）、`8-7186`（改成触发器）、
`8-6849 infeasible`（要求的样式做不到，之后自己退回 LUTRAM——本工程的这条写在
`src/rtl/process/proc_morph.v:42-44`）、`8-6014`（顺带：`src/rtl/eth/link_monitor.v:40` 用它证明过
"宽度写死装不下"这一族）。打开实现后的方法学报告，看 SYNTH-5 / SYNTH-6 计数与实例名
（`build/report/methodology.rpt:32-33`、`:63-66`）。打开利用率报告，看 `LUT as Memory` 是否在没改功能时
突然涨（现役 4185，其中分布式 RAM 4044、移位寄存器 141，`build/report/utilization.rpt:37-39`），
以及 `Slice Registers` 是否成倍增加（现役 8188，同文件 `:40`）。
### 3.2 一讲：两道闸——异步复位与组合读口

① **零术语版**：专用存储块内部的寄存器是**固定**的：读出只能等时钟沿，置位/复位只能是同步那种。
所以如果你写的代码里有"复位一来就把这块数组或它的读出清成 0"，或者"我这一拍就要结果"，
工具只能放弃这块专用存储，改用普通逻辑搭。
*这种简化会在"我以为复位写法只是习惯问题"的情形误导你 —— 在这两处，复位写法**直接改变硬件的存储类型**，
进而改变时序与资源。精确版见下一层。*
（"两道闸"是比喻，不是实现；实现见 `src/rtl/axi/axi_frame_writer_gated.v:91-99`（数组写独占不带复位的块）与 `:60-64`（分布式 RAM 的异步读口）。）

② **不用它会看到什么现象**：四条报错文本，同一件事的四个出口。
`Synth 8-4767`（`src/rtl/axi/axi_frame_writer_gated.v:51`，数组读写与异步复位同块）；
`Synth 8-91 ambiguous clock in event control`（`src/rtl/process/bilin/fb_bilin.v:146`、`:186`，
写口带异步复位 ⇒ 一个块里出现两只钟）；`Synth 8-7186 ... using registers`
（`src/rtl/eth/axi_frame_saver64.v:104-106`、`src/rtl/process/proc_morph.v:38`：
"两条掩码行缓存变成 2×H_ACTIVE 个触发器"）。组合读口那条形状不同——`proc_morph.v:42-44` 写的是
"`mc1` 的读是**异步**的（组合读出），BRAM 做不到 ⇒ 原来写 `ram_style=\"block\"` 只会被判
`Synth 8-6849 infeasible` 然后自己退回 LUTRAM"。同一族的另一半：
`src/rtl/axi/axi_frame_writer_gated.v:60-64` 干脆按"分布式 RAM 只有异步读"来写读口。

③ **精确定义 + 出处**：UG949 中文版 p.41 的复位一节两句就是这道闸：
"复位断言有效期间，异步复位导致块 RAM、LUTRAM、以及 SRL 的存储器内容损坏的可能性更高。
对于含异步复位（用于驱动块 RAM、LUTRAM 和 SRL 的输入管脚）的寄存器尤其如此"；
"DSP48 和块 RAM 等部分资源仅包含同步复位以供块内的寄存器元件使用。在与这些元件关联的寄存器元件上
使用异步复位时，可能无法在不影响功能的前提下直接将这些寄存器推断到这些块中"。
"读必须同步"在 UG473 p.11；"输出寄存器改变 clock-to-out"在 UG473 p.11 的输出锁存/寄存器描述
与 DS187 p.46 表 65 的数字。本工程的落地写法（三条合起来才是完整形状）：存储写**独占一个不带复位的
always 块**（`src/rtl/axi/axi_frame_writer_gated.v:91-99`，注释原话"这是 R02 探针实测出的唯一能被
推断成 RAM 的形状"；以及 `src/rtl/eth/axi_frame_saver64.v:104-115` 同一形状），
读出与标志位在**另一个带复位的块**里（`src/rtl/video/raw_line_delay.v:84-94`：
"`look/head_q` 只许在这**一个** always 里写……把同一根寄存器分给两个进程综合会直接报多驱动"）。

④ **它不是什么**：它不是"功能上的复位域划分"。本工程同族但不同病的是**死支路复位**
（`src/rtl/util/key_debounce.v:1-31`；`src/rtl/eth/snap_cross.v:16-27` 把这条讲得很细：那一颗寄存器
所在的顶层把复位绑成常量 1'b1，于是"上电值只由位流里的 INIT 承载，不写声明初值它就不是复位分支
想要的那个值"）。也不是"综合选项没打开"。可观察差别的地点：`src/rtl/process/proc_box_blur.v:66` 与
`proc_morph.v:86`、`proc_sharpen.v:58`、`proc_sobel.v:77` 四处同一条纪律（复位只写在一个块里），
后果写得很直白："`Synth 8-6859/8-6858 multi-driven net` 并把逻辑那一侧**忽略**（恒 0），
而仿真看不出来（xsim 按进程后写覆盖）"——与 `report/known_issues.md:725` 那条"仿真 ≠ 硬件"是同一族。

⑤ **辨认方法**：打开一个含数组的 always 块，问两条：**(a)** 这个块里有没有 `if (!rst_n)`？
**(b)** 数组的**读**是不是在组合敏感列表里（`always @(*)` 或 `assign x = mem[i]`）？
(a) 有 ⇒ 这块数组大概率进不了 BRAM；(b) 是 ⇒ 只能进分布式 RAM 或触发器。
报告侧：综合日志搜 `8-4767` / `8-7186` / `8-6849` / `8-91`；实现后把 `LUT as Memory` 与
`Block RAM Tile` 两行的前后差并排列出来（`build/report/utilization.rpt:37-39`、`:106`），
两个一起看才知道有没有被降级。

### 3.3 一讲：位宽决定"几块"，不是"多大"（18 位那一档的台阶）

① **零术语版**：专用存储块是按固定宽度切好的格子（每格到 18 位或 36 位）。
你的一行数据是 16 位还是 17 位，都塞得进同一个 18 位格子；但从 18 位跨到 19 位就要多占一整列格子。
所以**位宽的代价是台阶式跳变**，不是线性。
*这种简化会在"我以为多留 1 位不花钱"的情形误导你 —— 只有在那两个台阶以内才不花钱。
本工程把这句话写成"必须在报告上核对"，见 ②。精确版见下一层。*
（"按固定宽度切好的格子"、"多占一整列格子"是比喻，不是实现；实现见 `src/rtl/video/raw_line_delay.v:11-16`（17 位仍在 18 位档）与 `:37-43`（环深 8 行的块数账）。）

② **不用它会看到什么现象**：本工程的这条写成了一个要去核的账，而不是一个感觉。
行延迟环把"越界标签"和像素一起打包过环，代价是 RAM 宽度 16 → 17 位；注释给的说法是
"17 位仍在 RAMB36 的 18 位宽度模式里 ⇒ **一块 BRAM 都不多要**"，紧跟一句
"这条要在构建后的 `utilization.rpt` 上核对，不许停在注释"（原文：
`src/rtl/video/raw_line_delay.v:11-16`）。环深那一侧同族："LINES=4 ⇒ RLOG=3、环 8 行、
深度 8×512×16 ≈ 4 块 RAMB36（级联方案要 8 块，省一半）"（同文件 `:37-43`），
前提是把取模做成**切位**而不是运行时除法（同文件 `:37` 那句"#58 那条硬件规矩"）。

③ **精确定义 + 出处**：档位表在 UG473 p.11（`2K x 18`、`1K x 36`、`512 x 72` 与 18 Kb 那一列）；
"读必须同步"同页。本工程 36 位那条正好是一条 RAMB36 的宽度档（`src/rtl/eth/dc_fifo.v:4` 的
`DATA_W = 36`；顶层例化 `src/rtl/eth/eth_udp_video_top.v:298`）。净读数：
`build/report/utilization.rpt:106-109`（Block RAM Tile 95.5、RAMB36/FIFO 93、RAMB18 5），
分母 140 与 68.21 % 同行；`data/metrics.csv:10` 抄的是同一格并注明"一次构建"与
"帧缓存由 64-bit 宽 + 乒乓两块拼出，是 BRAM 的主要去向"。

④ **它不是什么**：它不是"总比特数 ÷ 36K"这种除法能算对的估算——形状（宽 × 深 × 端口数）决定占几块，
是否带输出寄存器还会改 clock-to-out（DS187 p.46 表 65 的两个数）。也不是"地址位宽被吞"（那是 1.3）。
可观察差别的地点：帧缓存为了用满 64 位宽刻意拆成 `lo` / `hi` 两块数组
（`src/rtl/video/frame_buffer_w64.v:37-38`），这与"把 64 位塞进一块 36 位"的直觉不同；
那笔拆块账在 `design-choices.md` 第 6 节。

⑤ **辨认方法**：打开模块，读数组声明那一行的**位宽**与**深度**，对照 UG473 p.11 的档位
（1/2/4/9/18/36/72）问一句"我的位宽落在哪一档的上限以内"；跨档就必须在实现后的报告里核对块数
（`build/report/utilization.rpt:106-109` 的 RAMB36 与 RAMB18 两行）。把报告里的数与
"你按位宽算出来的列数"对不上 ⇒ 是形状没吃到，或者被工具降级了（见 3.5）。

### 3.4 一讲：乘加进 DSP 的条件（位宽、操作数寄存、结果寄存）

① **零术语版**：片上有专用的乘法器格子，一次能乘 25 位 × 18 位，格子内部还自带几级寄存器。
要把它用上，得满足两件事：**宽度别超过格子**，以及**喂进去的数和拿出来的数都挂在格子里那些寄存器上**。
如果乘完还跟一大坨组合逻辑，或者把带异步复位的寄存器混进去，工具只能用查找表拼乘法。
*这种简化会在"我以为写了乘号就等价于用 DSP"的情形误导你 —— 一个乘号可能吃 0 个也可能吃好几个格子；
真正决定的是"寄存器挂在哪一级"。精确版见下一层。*
（"乘法器格子"、"喂进去的数与拿出来的数挂在格子里那些寄存器上"是比喻，不是实现；实现见 `src/rtl/process/rotate/rotate_mapper.v:30-38`（操作数与结果分两级寄存）与 `src/rtl/process/zoom/zoom_mapper.v:58-61`。）

② **不用它会看到什么现象**：本工程的这条是**结果级**的，不是逐行级的。
现役 `DSPs = 19 / 220（8.64 %）`（`build/report/utilization.rpt:121`，原语表 `:212` 同一数），
用途口径见 `data/metrics.csv:11`："实现后报告；用在缩放/旋转的坐标乘法与 gamma 计算"。
推断失败时的可见症状不是报错，而是**两份数字同时变脸**：`DSP` 掉、`Slice LUTs` 涨（`:35`，现役 14154），
并且 125 MHz / 50 MHz 那两族的 WNS 变差——因为乘法锥被摊成组合逻辑。
**注意**：哪几个乘号真的进了哪几只格子，本仓库没有逐实例的对账件 ⇒ 这条用途口径是 `metrics.csv`
那句话的转述，**逐实例归属记为【未确认】**（要问用户：要不要出一份
`report_utilization -hierarchy` 的 DSP 归属表并钉进构建）。

③ **精确定义 + 出处**：UG479（7 series DSP48E1，本机
`D:/Xilinx/Resource/Reference Material/6-Xilinx Zynq系列部分官方手册/ug479_7Series_DSP48E1.pdf`）
p.9 是格子本体："25 × 18 two's-complement multiplier"、"48-bit accumulator"、"power saving pre-adder"；
p.10 是寄存器归属："The A register width is improved from 18 bits in the Spartan-6 family to 30 bits
in the 7 series … A and B registers can be concatenated … The A register feeds the pre-adder"，
同页给级联能力（更大的乘法器与更大的后加法器）；p.14 给打拍要求：
"Add/Sub and Logic Unit operations require at least two pipeline registers (input, output) to run at
full speed"与"When only one or two registers exist in the multiplier design, the M register should
always be used"。UG949 中文版 p.49 把它写成设计建议："一般乘法针对的是 DSP 块。宽度小于 18x25 的
有符号位将映射到单个 DSP 块。乘积更大的乘法可能会映射到多个 DSP 块。DSP 块内部具有流水打拍资源……
描述乘法时，围绕乘法进行**三级流水打拍**操作可生成最好的建立时间、clock-to-out 和功耗特性。
流水打拍操作层级过浅（一级或无）可能导致时序问题并导致这些块的功耗增加，而 DSP 内部的流水打拍寄存器
却被闲置"。异步复位这道闸仍由 UG949 p.41（见 3.2 ③）给。器件侧引脚要求是 DS187 p.49 表 66 的标题：
"Setup and Hold Times of Data/Control Pins to the Input Register Clock"。
本项目取值：旋转支把乘法分成三处寄存——注释直书动机
（`src/rtl/process/rotate/rotate_mapper.v:4`"Multiplies registered in 2 stages for timing at 75 MHz"），
代码是 `:24-28`（stage0 中心化）、`:30-38`（stage1 乘加）、`:39-43`（stage2 移位与反算）、
`:45-52`（出口寄存 `x_out/y_out/oob`）。缩放支的四处乘法在
`src/rtl/process/zoom/zoom_mapper.v:58-61`，操作数来自 `:31`、`:42` 两个 always 的寄存器，
结果在 `:96` 起的 always 里寄存；移位代替除法在 `:63-66`。gamma 那一侧是查找表 + 分布式 RAM
（`src/rtl/video/gamma_lut.v:27-29`），不是格子。

④ **它不是什么**：它不是"`use_dsp` 属性写了就有 DSP"——属性只允许推断，不保证吃进格子；
位宽与打拍形状才是条件（UG479 p.14 的"至少两级流水"、UG949 p.49 的"三级流水最好"）。
也不是"乘法器 = 浮点单元"：本工程的定点口径在术语表第 24 项（定点数与"不做除法"）。
可观察差别的地点是 `Primitives` 表里 `DSP48E1` 那一行与 `DSP` 段的两行必须同数
（`build/report/utilization.rpt:121` 与 `:212` 都是 19）；对不上说明你在拿综合后的数念实现后的账。

⑤ **辨认方法**：打开 RTL 找 `*` 号，逐处问三句：操作数是不是上一拍的寄存器？
结果是不是下一拍的寄存器？两个位宽乘起来是否 ≤ 25×18（超过要多块级联，UG479 p.10）？
三句都对 ⇒ 大概率进格子。打开报告先看 `DSPs` 行再看 `Primitives` 的 `DSP48E1` 行（同上两行号）；
再看 `Slice LUTs` 是否在同轮里反常上涨。综合日志里 `Synth 8-4767` 那一族的兄弟消息同样适用于 DSP
（UG949 p.41 那句把 DSP48 与块 RAM 并列写着）。

### 3.5 一讲：工具会为了时序自己改主意（SYNTH-5 那一刀）

① **零术语版**：工具的目标是"关住时序"。当它认为"这块数组用查找表搭更容易关住"，
它会自己放弃专用存储块改用查找表，并在一份方法学报告里留下一句话解释为什么。
不读那份报告，你就会以为资源变化全是"我改代码改出来的"。
*这种简化会在"我以为资源账只反映我的写法"的情形误导你 —— 它同时反映工具的映射决定，
而决定会随约束变。精确版见下一层。*
（"工具自己改主意"是比喻，不是实现；实现是报告里的降级记录，见 `build/report/methodology.rpt:32`、`:63-66`。）

② **不用它会看到什么现象**：形状是"改了一处约束，LUT 与 BRAM 同时变，而且报告里没红字"。
现役计数 `SYNTH-5` 336 条、`SYNTH-6` 98 条（`build/report/methodology.rpt:32-33`）。
一个要紧的细节：展开列表里被点名的 `u_pl/u_blur/lb1*`（`:63-66`）在源码里**已经**显式要求分布式
（`src/rtl/process/proc_box_blur.v:19-20`），而工具给出的理由仍然是"约束建议这样映射时序更好"
⇒ 这句话在本案里不是"我写错了"的证据，而是"报告里的降级理由与我的声明并不矛盾"的一条现场对照。

③ **精确定义 + 出处**：规则号、严重级别与说明文本取自工具自己的报告，两处同源：
`build/report/methodology.rpt:32-33` 与 `build/report/timing_summary.rpt:48-49`。
**官方规则目录里这一条的解释文字本次没有取到**：本机 UG906 中文版正文里 `SYNTH-` 编号 0 次命中
（该文目录列的是 `TIMING-15/16/17/18` 那一族，UG906 p.3）⇒ 该条的解释句记为【未核实】，
本篇只保留"报告字段 + 实例名 + 原因句"这三件可核对的东西。
另一条与本讲相关的官方口径在 UG906 中文版 p.45 与 p.47（本机
`D:/Xilinx/Resource/Timing Analysis/ug906-vivado-design-analysis-zh-cn-2025.2.pdf`，v2025.2，
2025 年 12 月 10 日，核对日期 2026-10-05）：豁免是"一等对象"、
"在创建豁免之前，请确保设计中存在引用对象"、"避免在实现后的设计上创建豁免，因为引用的对象可能
不存在于综合后的网表中……如果在错误阶段对不存在的对象应用无效豁免，则会丢弃这些豁免"，
以及"重新运行报告后，会筛选掉豁免的违例"⇒ 意思是：把这类降级豁免掉之后，下次报告就看不见它了。
这是"降级层静默"的另一条通道。

④ **它不是什么**：它不是"综合选项被改了"；也不是"估算不准"。与第 6 节那条的区别是关键：
这一条是**工具明说过的降级**（有实例名与原因句），第 6 节那一条是**没有任何声明的覆盖面缩小**。
可观察差别的地点：本仓库把两笔账分开钉——资源账用两份逐层件相减闭合
（`data/metrics.csv:8` 那句"净账由两份逐层件相减闭合（`build/evidence/r112_util_attrib.txt`）"），
射程账用命中数与名册配对（第 6 节 ⑤）。

⑤ **辨认方法**：打开 `build/report/methodology.rpt`，搜 `SYNTH-5`，读它的**原因句**与**实例名**；
实例名能反查到模块（本案 `u_pl/u_blur/…` ⇒ 模糊那一级的行缓存）。再看该模块源码有没有显式
`ram_style`：有 ⇒ 这是"工具按约束改主意"，不是"忘了写属性"；没有 ⇒ 先补属性再看计数变化。
最后把 `LUT as Memory` 与 `Block RAM Tile` 两行的前后差并排列出（`build/report/utilization.rpt:37-39`、
`:106`），**两个一起念才不骗人**。

**本节的题外场景**

- 高层次综合（HLS）侧的同一族问题：XAPP793 (v1.0)，2012-09-20，本机
  `D:/Xilinx/Resource/ZYNQ7020/MLK_demo/04_example_HLS_Image/HLS参考资料/xapp793-memory-structures-video-vivado-hls.pdf`
  p.3 把视频算法里的三类存储形状分开（移位寄存器、窗口、行缓存），并写明"所有这些存储结构都会对延迟、
  计算顺序与功能正确性产生影响"；同页最关键一句是"这个影响保证 HLS 工具不会自动向设计中插入新的
  存储器"——也就是说在 HLS 一侧**存储形状完全由写法决定，工具不替你补**；
  与本节 3.1/3.2 是同一条因果的另一端。同一篇 p.6 给出"垂直方向的移动被约束在行缓存里，由它给窗口供数"
  的写法形状，与本工程的行环形缓存（`src/rtl/video/raw_line_delay.v:5-7`）是同一道题的两种解法。
- 另一支图像缩放 IP 的资源账（本机 `D:/Xilinx/Resource/Reference Material/ad/lanczos_ip_spec.pdf`，20 页）：
  p.2 写"不使用 full-frame 中间帧缓存；使用 line buffer + 6-line ring buffer 结构进行数据复用"；
  p.4 的表按灰度 / RGB 两档给出 `Slice LUTs 3545 / 5197`、`DSP48E1 8 / 24`、`RAMB36E1 11 / 27`
  （BRAM18 折算 22 / 54），同一张表还列出 `WNS (Setup) 0.294 / 0.114 ns`、`WHS (Hold) 0.071 / 0.069 ns`、
  工作频率 148.5 MHz。这份件的价值是形状对照：**模式/位宽一变，三类资源与时序一起变**，
  本节 3.3 的台阶与 3.4 的三句问话在它身上同样成立。
- DDR 颗粒那一侧的对照（Micron MT41K256M16 Rev. Q p.102）：容量与地址位分配写在密度表里
  （4Gb: x4, x8, x16），行/列/bank 位数由密度决定 ⇒ "位宽决定形状"这条不只是 FPGA 内部的事，
  存储颗粒自己的地址解码也是同一套台阶。

小结 1：存储与乘加的推断只有四道闸——深度、位宽档、读口是否同步、复位是否与数组同块；
外加一条"工具会为时序自己改主意"。本工程的实测代价从 85 个触发器到 5.1 万个触发器都在同一道题上
（`axi_frame_saver64.v:10-13`、`:104-108`）。
小结 2：官方口径分别落在 UG949 p.41/p.49/p.50/p.53、UG473 p.11、UG479 p.9/p.10/p.14、
DS187 p.46/p.49、UG906 p.45/p.47；SYNTH-5 的解释文字【未核实】、DSP 逐实例归属【未确认】。
下一步：第 4 节。
---

## 第 4 节 建立/保持与裕量：报告里那几个数分别回答什么问题

本工程的逐域读数与"名册"方法在 `report/05-timing.md` 与 `report/timing_global.md`，
时钟清单在 `clocking-and-reset.md` 第 1 节；本节只讲**口径从哪来**与**怎样被念错**。
术语（→ 术语表）：建立时间 / 保持时间 / 时序裕量（WNS / WHS）、异步时钟组、时钟不确定度。

### 4.1 一讲：slack 是"离违规还差多少"，不是"花了多久"

① **零术语版**：工具在每个沿检查两件事——"数据是不是来得够早"（建立）与
"数据是不是没变得太早"（保持）。检查完给一个差值：**差多少才够**（正的）或**超了多少**（负的）。
这个差值就是裕量。它不是延迟本身，它是"离不合格还差多少分"。
*这种简化会在"我把'余量 0.7 ns'读成'这一拍花 0.7 ns'"的情形误导你 —— 周期 8 ns 时 0.7 ns 的余量
意味着数据大约花了 7.3 ns。这是两件不同的事。精确版见下一层。*
（"离不合格还差多少分"是比喻，不是实现；实现见 `build/report/timing_summary.rpt:149-151` 那一行五列，以及单条路径里的 `Slack` 与 `Data Path Delay` 两行（`build/clock_uncertainty.rpt:20`、`:45`）。）

② **不用它会看到什么现象**：形状是"改了一处代码，头条数字变了，但没人知道是谁"。
本仓库为这件事有一条记录：同一套约束三次构建 WNS = 0.918 / 0.807 / 0.314，
而 0.314 那一轮"与双线性**无因果**：ETH 域一行 RTL 没动"⇒ 结论是"分组数才是可比的量"
（原文：`build/gates.sh:275-279`，出处另有 `report/optimization_log.md` §4）。
另一种形状是报错文本长什么样：`report_timing` 的第一行写 `Slack (VIOLATED) : -3.482ns` 这样的东西——
本工程的实测三条在 `src/constraints/r119b_hdmi_tp1_pinclk.xdc:4-6`
（`-3.482 / -3.458 / -3.474 ns`，件 `build/evidence/r119_xdc_loads_probe3.txt`）。

③ **精确定义 + 出处**：UG906 中文版 p.6 给的是这组数的名字与用途：
"WNS、TNS、WHS、THS、WBSS、TPWS：该轮运行的时序分数，用于快速检查时序结果。
如果未满足时序要求，请通过'时序汇总报告'开始分析"。器件侧的"窗口"数值在 DS187 p.49 表 66
（DSP48E1 数据/控制脚到输入寄存器的建立与保持，-2 档 A→A 寄存 0.30/0.13 ns）与 UG473 p.11
（块 RAM 读写是同步操作）；内存颗粒侧在 Micron MT41K256M16 Rev. Q p.102（`tIS/tIH(base)` 分档）
与 p.109（要用的 tDS/tDH = 手册 base 值加 derating）。
本项目取值（一次布线后，`build/report/timing_summary.rpt:149-151`）：WNS 0.739 ns、TNS 0.000、
setup 失败端点 0 / 总端点 51135；WHS 0.052 ns、THS 0.000、hold 失败端点 0 / 总 51135；
WPWS 0.264 ns、脉冲宽度失败端点 0 / 总 12634；同文件 `:154` 那句是
"All user specified timing constraints are met."。逐域（同文件 `:181-188`）：`clk_fpga_0` 1.850 / 0.053
（15721 端点）、`eth_rxc` 0.739 / 0.052（4835）、`sys_clk` 14.876 / 0.222（323）、
`clkout0_1` 3.630 / 0.059（30179）。`data/metrics.csv:5`、`:7` 抄的是头条那两格并注明
"一次布线后报告"。

④ **它不是什么**：它不是"实际延迟"（① 的风险提示），也不是"跨域安全"
（`src/rtl/eth/eth_udp_video_top.v:373-380` 那条 CDC 修法不体现在时序报告里，见 2.6 ②(c)）。
第三件：它不是最大频率——`eth_rxc` WNS 0.739 ns 与它的周期 8.000 ns（波形行
`{0.000 4.000} 8.000 125.000`，`build/report/timing_summary.rpt:165`）要合起来念；
本仓库从未把这条推论写成结论。第四件：WNS 的绝对差既不是收益也不是损失，这条本仓库写成了规矩——
`report/timing_global.md:170`"头条 WNS 的绝对差只念不判（rule 35）"。

⑤ **辨认方法**：打开时序汇总，找表头那一行的列（WNS / TNS / TNS Failing Endpoints /
TNS Total Endpoints / WHS …，`build/report/timing_summary.rpt:149`，数据在 `:151`）。
读不到那一行时，本仓库的门禁会把候选行原样打印出来而不是只报"读不到"
（理由与形状见 `build/gates.sh:64-71`）。打开单条路径，认四个字段：`Slack (MET|VIOLATED)`、
`Path Type`（`Setup (Max …)` 或 `Hold (Min …)`）、`Requirement`、`Data Path Delay`——
`Data Path Delay` 是"花了多久"、`Slack` 是"差多少"，两行同时在场，这就是 ① 那句提示的可读证据。

### 4.2 一讲：相对余量（slack ÷ 周期）才是跨域可比的那把尺

① **零术语版**：同一个 0.7 ns 的余量，在 8 ns 的节拍上很紧，在 20 ns 的节拍上很松。
所以跨域比较要除以周期，念成百分比。
*这种简化会在"我以为百分比在所有域都同一定义"的情形误导你 —— 百分比只覆盖**被同一把尺量过**的那些族；
本工程四个域的 hold 不是同一把尺（见 4.4）。精确版见下一层。*
（"同一把尺"是比喻，不是实现；实现见 `report/05-timing.md:10-13` 定义的 `margin_pct` 字段与件 `build/evidence/r118_after_roster_probefmt.txt` 的逐域行。）

② **不用它会看到什么现象**：形状是"跨域比大小比错了方向"。
`report/05-timing.md:26-29` 的名册：`sys_clk` 的 14.876 ns 看着最大但那是 74.38 %；
`eth_rxc` 的 0.739 ns 是 9.24 %，`clk_fpga_0` 的 1.850 ns 是 18.50 %，`clkout0_1` 的 3.630 ns 是 18.15 %
⇒ 只有相对余量能说出"哪一格真的顶在边界上"。第二种形状是复制刀那一类：
`report/timing_global.md:227` 与 `:238` 记录的"机制能动、目标族 +0.456 ns，但 `eth_rxc` hold
从 0.050 掉到 0.035（相对余量 −29.0 %）⇒ 放弃"。只看全局 WNS 就看不见这笔代价。

③ **精确定义 + 出处**：口径正本不在这里重述，指路即可：`report/05-timing.md:10-13`——
"**相对余量 = slack ÷ 周期**：名册文件自己把这个商印成 `margin_pct` 字段（件
`build/evidence/r118_after_roster_probefmt.txt` 的 `ROSTER|setup|clk=…|period=…|slack=…|margin_pct=…` 行）。
本章直接引用它，不重算、不换口径"。差分判据在 `report/timing_global.md:168-170`
（D3：相对余量掉 25 % 以上的域数）。工具侧对"这些分数是用来快速检查的分数"的口径是 UG906 p.6。
本项目取值（把 ② 的数字一次列全，来源 `report/05-timing.md:26-29` 与
`build/report/timing_summary.rpt:181-188` + 波形行 `:164-171`）：setup 9.24 / 18.50 / 18.15 / 74.38 %，
hold 0.65 / 0.53 / 0.29 / 1.11 %。

④ **它不是什么**：它不是"占空比 / 脉冲宽度裕量"——第三个量 WPWS 走另一套检查
（现役 0.264 ns，`build/report/timing_summary.rpt:151`；对应 `clkout2` 那一行 `:188`，只有 3 个端点）。
也不是"抖动预算"（那是 4.4）。可观察差别的地点：`eth_rxc` 的 hold 0.052 ns 与 0.65 % 同时在场，
但真正限制它的不是百分比而是那条唯一自加的不确定度（4.4）。

⑤ **辨认方法**：拿到一份逐时钟表，先找周期列（Vivado 的 Clock Summary 波形行，
本工程 `build/report/timing_summary.rpt:164-171`），再拿 slack 除它；商落进 5 % 以内 ⇒ 这一族顶在边界，
商落进 30 % 以上 ⇒ 谁都没顶到。手上是本仓库的件时，直接搜 `margin_pct=` 这一字段
（读法见 `report/05-timing.md:11-13`）。

### 4.3 一讲："0 失败端点"只覆盖被约束的对象（未检查 ≠ 满足）

① **零术语版**：工具只检查**被约束到的**东西。没被约束的地方它不打分、也不报错——
于是"0 个失败"里既包含"检查过并且合格"，也包含"根本没检查"。
*这种简化会在"我把'没有 FAIL'读成'全都查过'"的情形误导你 —— 这一条本仓库写成了硬判据 H5。
精确版见下一层。*
（"不打分、也不报错"是比喻，不是实现；实现见 `build/report/timing_summary.rpt:66`、`:95-104` 的 `check_timing` 计数行。）

② **不用它会看到什么现象**：现象不是屏上出错，而是**说不出谁在负责**。
现役读数：`check_timing` 段里 `5. checking no_input_delay (7)`，展开是
"There are 5 input ports with no input delay specified. (HIGH)" 加
"There are 2 input ports with no input delay but user has a false path constraint. (MEDIUM)"；
输出侧是 6 HIGH + 6 MEDIUM（`build/report/timing_summary.rpt:66`、`:95-104`）。
那 5 个输入就是 RGMII 收口的 `eth_rx_ctl` 与 `eth_rxd[3:0]`（点名清单：
`report/timing/debt_ledger.md:37`）。读法在 `report/05-timing.md:125-131`：现行 `eth_rxc` 的 WHS 0.052
是"假设数据恰好在时钟沿到达"量出来的**片内**数，不含 PHY→FPGA 走线与 PHY 内部延迟那一段 ⇒
"没查 ≠ 达标"。`data/metrics.csv:6` 把同一句话写在"全局 setup 失败端点"那一格的测量条件列里。

③ **精确定义 + 出处**：两条官方口径。UG949 中文版 p.137：异步 CDC 路径
"不应使用默认时序分析来对其进行时序约束，此分析无法证明其能否在硬件中正常工作"
——即"分析不覆盖"是被明说的状态。UG906 中文版 p.45：豁免"在创建豁免之前，请确保设计中存在引用对象。
如果在创建豁免时不存在设计对象，则豁免不适用于这些设计对象"；p.47："重新运行报告后，会筛选掉豁免的违例"。
两句合起来就是：覆盖面可以被静默缩小，且缩小之后报告里看不见。本仓库的排查文本在
`skills/pitfalls/constraint-coverage-loss/SKILL.md:89-98`（⑥ 未约束端口不报错，只在检查里点名；
"把'没被点名'当成'已满足'"）与 `:100-109`（⑦ 手写文件清单当射程，目录一变深就失效）。
本项目读数：`io_unconstrained_ports = 11`（输入 5 + 输出 6）在 r115 那轮判红
（`report/timing/debt_ledger.md:30-31`）；r116 把 5 个输入进构建后缺口从 11 变 6（同文件 `:113-126`）；
现役版本又退回候选件（开关与原因：`build/tcl/build_system_axigpio.tcl:54-63`；
`data/metrics.csv:5` 的测量条件列同一句）。

④ **它不是什么**：它不是"检查器坏了"，也不是"这些端口本来就不需要约束"。两者要分开写：
本工程的 `led`、`tmds_*` 属于"确实没约束、但要给出为什么"的一类，RGMII 那 5 个属于"需要但没有"的一类
（逐条理由的正本：`report/timing/debt_ledger.md:140-143`）。可观察差别的地点：窗一挂上，
那 5 个端点会**出现**并给出有限违例——`src/rtl/eth/rgmii_rx.v:12-20` 记的实测是
"窗一建起来，`eth_rxc` 的 hold 立刻 −2.885 / 5 个失败端点，落点就是本模块的 `u_iddr_rx_ctl/D`"。

⑤ **辨认方法**：打开时序汇总里的 `check_timing` 段（本工程 `:60-104`），只看括号里的数字与分级：
`no_clock (0)`、`unconstrained_internal_endpoints (0)`、`no_input_delay (7)`、`no_output_delay (12)`。
四个都 0 才可以说"全部被覆盖"。再看 `report_methodology` 的
`TIMING-18 Missing input or output delay` 计数（本工程 7，`build/report/methodology.rpt:36`）。
最后问一句"这些缺口在交付文档里有没有逐条理由"；没有 ⇒ 按"未检查"处理，不许写成"满足"。
本仓库还有两支专门尺子（**本次未跑，只点名**）：`build/check_io_timing_coverage.py`、
`build/uncertainty_uniform_ab.sh` + `build/tcl/probe_uncertainty_uniform.tcl`。
### 4.4 一讲：不确定度是一笔人为预算；不对称时几个 WHS 不能互相比较

① **零术语版**：工具算窗口时只知道"理想时钟长什么样"，不知道真实的抖动、占空比误差，
以及你自己没建模的那段散布。所以设计师可以主动往检查里**加一笔扣减**（不确定度），
意思是"这里我不放心，请多留一点"。加了之后判据变严，数字可能变负——
**这不是变坏，是终于开始算这笔账**。
*这种简化会在"我以为所有域都被同一笔扣减过"的情形误导你 —— 本工程只扣了一个域，
于是四个 WHS 不是同一把尺量出来的。精确版见下一层。*
（"往检查里加一笔扣减"是比喻，不是实现；实现见 `src/constraints/rk_zynq7020.xdc:50` 与 `build/clock_uncertainty.rpt:107` 的 `Clock Uncertainty` 行。）

② **不用它会看到什么现象**：形状是"同一个 hold 数，换个说法就反过来"。
现役只有 `eth_rxc` 被扣 0.800 ns，所以它的 WHS 0.052 是**已经付过这笔账**的数，
其余三个域（0.053 / 0.059 / 0.222）一分没扣。把同一个 0.800 带给每个钟量一次之后：
全设计 WHS **−0.747 ns、25,742 个失败端点**（登记：`report/log/issues.md` #302，
引用处 `report/05-timing.md:141-147` 与 `report/timing_global.md:103`）。
`report/05-timing.md:146-147` 的结论句就是这条：**不可跨域比大小**；
"'四域 hold 余量差不多'是约束口径造出来的形状，不是设计事实"。

③ **精确定义 + 出处**：UG949 中文版里有这一族的条目（页名"Additional Uncertainty"，
本仓库先前只抓到页名，登记在 `report/timing_global.md:394-396`）；
**本节要用的原句正文本次未取到** ⇒ 该条的规范解释句标为【未核实】。支撑"定义"的是两处可核对的东西：
**(a)** 报告字段本身——单条 min 路径里写
`Clock Uncertainty: 0.800ns ((TSJ^2 + TIJ^2)^1/2 + DJ) / 2 + PE + UU`
（`build/clock_uncertainty.rpt:107`；该路径 Path Group `eth_rxc`、Slack 0.049 ns，同文件 `:93`、`:98`）；
**(b)** 另一条 min 路径（全设计最差那条，Path Group `clk_fpga_0`、Slack 0.037 ns，同文件 `:20`、`:25`）
**整块里没有** `Clock Uncertainty` 这一行。这两件就是"不对称"的直接物证。
本项目取值：约束原文 `set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]`
（`src/constraints/rk_zynq7020.xdc:50`）；为什么只点一个对象，同文件 `:43-45`（见 6.2）；
为什么取 0.800 而不是 0.500，同文件 `:46-49` 记了 r79 那一档只做到 WHS +0.051 的实测与再加严的理由；
这份件的入口脚本明写"写了不等于生效"（`build/tcl/clock_uncertainty.tcl:10-11`）。
新鲜度提醒：`build/clock_uncertainty.rpt` 的两个 slack 是 2026-09-30 的读数（该文件日期行在 `:9`），
与现役名册的 WHS 0.052（r118）**不是同一次构建**，不许混念（口径声明：`report/05-timing.md:14-15`）。

④ **它不是什么**：它不是测出来的抖动/偏斜——报告那一行括号里 `TSJ / TIJ / DJ / PE` 才是那几项，
`UU` 是人为加的那笔（`build/clock_uncertainty.rpt:107` 把它们并列写出）。
第二件：它不是"放松判据"——本工程这一行是**加严**方向，同文件 `:41-42` 那句写的是
"这一行方向与'放松判据'相反：给 hold **加** 0.5 ns 要求，逼工具把余量做成设计值"，
`:47` 再记下 r79 那一档只做到 WHS +0.051、于是加严到 0.8 的经过。
第三件：它不是全局开关——一次点名一个对象，其余域不受影响（这就是 ② 的病根）。
可观察差别的地点还是那条路径报告：**那一行在不在**（③ 的 (a)/(b)）比任何文字都直接。

⑤ **辨认方法**：打开一条 min 路径报告，找 `Clock Uncertainty:` 行。**没有 ⇒ 这一族的 hold 没扣过
自加带子**；有 ⇒ 读括号里的式子看 `UU` 在不在（在 ⇒ 你的 `set_clock_uncertainty` 真的落在了这条路上）。
再打开 `build/clock_uncertainty.rpt` 的两段小标题（`:5` 与 `:78` 分别是 (a) 与 (b)），把两个 Slack 并排
——这就是"不对称"的标准读数形状。拿到陌生工程：`grep -n "set_clock_uncertainty" *.xdc`
数点名了几个钟，再与实现后**实际存在**的钟名比（本工程的打印件口径：
`build/tcl/clock_uncertainty.tcl:29-30` 那两行 `GET_CLOCKS_eth_rxc` / `GET_CLOCKS_clk_fpga_0`）。
**【需板上验证】**：本仓库目前**没有"四域统一带子之后的板侧 hold 真值"**
（`report/timing_global.md:103` 末句写"还没跑真件"），所以"其余三域也扣 0.800 会怎样"只能作为待测项，
不能写成结论。

### 4.5 一讲：被排除的路径不进任何分数（把 4.3 推到跨域那一侧）

① **零术语版**：声明"这两组拍子没关系"之后，它们之间的路径就**不再被打分**。
这是必要的（否则会出假违例），代价是那几段路上的正确性**完全**由你的结构负责，报告不会再说话。
*这种简化会在"我把'排除'读成'已证明安全'"的情形误导你 —— 排除只是免除分析。精确版见下一层。*
（"不再被打分"是比喻，不是实现；实现见 `src/constraints/clock_groups_impl.xdc:28-31` 与 `build/report/timing_summary.rpt:192-199` 的 Inter Clock Table。）

② **不用它会看到什么现象**：形状是"改了跨域结构，WNS 一动没动，于是被当成没生效"。
本仓库的登记句在 `report/timing_global.md:152`。反向形状也有，而且历史很贵：没排除时 `clk_pix`
被当成独立时钟与 `eth_rxc` 做 setup 分析，报出 WNS ≈ −6.7 的**假**违例（原文：
`src/constraints/clock_groups_impl.xdc:13-17`；事故标题见 `report/log/issues.md:143`
"eth_rxc→clk_pix 假违例（WNS≈−6.7）"）。漏掉的那个后缀是 `-include_generated_clocks`。

③ **精确定义 + 出处**：UG949 中文版 p.137 给了这一族的规范说法（无公共基准时钟或无公共周期的时钟对
是异步关系，必须用不依赖时序正确性的同步电路，"不应使用默认时序分析来对其进行时序约束"）；
p.115 给补救形式（"XPM CDC 提供了自带的 `set_max_delay -datapath_only` 约束"）。
本项目取值：三组互斥 `set_clock_groups -asynchronous`（`src/constraints/clock_groups_impl.xdc:28-31`；
`sys_clk` 那组必须带 `-include_generated_clocks`，原因同文件 `:13-17`；
为什么按时机拆成单独文件，同文件 `:1-8`）。**欠账的形状**：`report/timing_global.md:127`（4c 节）标题就是
"异步时钟组把四条跨域路**从所有尺子的射程里拿走了**"，`:146-147` 要求"给同步器补一条**有出处的**
`set_max_delay -datapath_only`（数值口径按目的时钟周期与建立时间推，不许随手填 ns）"。
候选件里四条界已经写好并给了数值（`src/constraints/r114_io_async.xdc:57-66`：
`eth_rxc↔clk_fpga_0` 取 10.000 / 8.000，`clk_fpga_0↔clkout0_1` 取 20.000 / 10.000），
但**没有进构建**（加载清单：`build/tcl/build_system_axigpio.tcl:31`、`:36-37`）。

④ **它不是什么**：它不是 `set_false_path`。本工程两者并存且各有用途：
`set_false_path -to [get_ports eth_rst_n]` 那几条是**对具体端口**的豁免
（`src/constraints/rk_zynq7020.xdc:55-60`），组声明是**整组之间**不分析；`check_timing` 对两者表现不同——
4.3 里那 2 个"有 false path 但没有 input delay"的输入被分到 MEDIUM 而不是 HIGH
（`build/report/timing_summary.rpt:98-100`）。也不是"跨域可以不管"：跨域点靠结构清单管住
（`clocking-and-reset.md` 第 3 节全表 + `src/constraints/clock_groups_impl.xdc:19-25`
那四条"跨域数据由结构保证"的对应关系）。

⑤ **辨认方法**：打开 `build/report/timing_summary.rpt` 的 Inter Clock Table（`:192` 起），
数里面有几对。现役只有两对（`sys_clk ↔ clkout0_1`，`:198-199`，19 与 231 个端点）；
凡是你结构上有、而这张表里没有的跨域对，就是被排除的那批。拿到陌生工程：把 RTL 里所有
"在别的钟沿采样"的捕获寄存器列出来（本工程那把尺子 `build/scan_async_reg_coverage.py`，
件 `build/evidence/r113_async_reg_scan.txt`；本次未重跑），再与 Inter Clock Table 的时钟对取差；
差集不为空 ⇒ 要么被排除、要么根本没被分析。

**本节的题外场景**

- DDR3 颗粒侧的"预算表"写法：Micron MT41K256M16 Rev. Q p.109 把建立/保持写成
  "要用的值 = 手册 base 值 + derating"，p.102 给分档 base 数（`tIS/tIH`，单位 ps）。
  这是 4.1 与 4.4 的合成版：**窗口不是测量结果，是一张要加总的预算表**——derating 那一列存在的意义
  就是"真实的时钟与电压会把窗口吃掉一点"，与 `set_clock_uncertainty` 是同一件事的两种表达。
- HDMI/DVI 一致性测试的源端 TP1（本机候选约束 `src/constraints/r119b_hdmi_tp1_pinclk.xdc:16-17`）：
  文件头自己划的界——"量出来的 slack 只能说明这一族约束在 SDC 里怎么表达，不能当'过了 CTS'；
  TP1 的真判据是眼图/抖动/占空比/沿，那些不在 SDC 语义里"。这是 4.3 的另一面：
  **报告里没有那一栏，不代表判据不存在**。同一文件 `:20-22` 还登记了一条未定项：
  `create_clock` 打在输出脚上得到的是"外部参考钟"，它与片内启动钟之间没有声明的时序关系，
  工具会不会因此不产生到数据道的路径"由探针实测回答，这里不预判结论"。
- 高速变换器接口的板级预算（《JESD204B 应用指南》中文版 p.22）：
  "需要将最大时钟和 SYSREF 信号偏斜纳入考虑范围，并仔细布局 PCB"——同一条"窗口要留预算"
  在板级而不是片内；p.20 更把"SYSREF/SYNC 的建立和保持时间无效"列成链路反复回退到 CGS/ILAS 的
  第一条嫌疑。这就是 4.1 的 slack 概念在另一个尺度上的样子。

小结 1：四个数各回答一个问题——WNS/WHS 回答"被约束的对象差多少"，相对余量回答"哪一族顶到边界"，
`check_timing` 的计数回答"有多少对象根本没被问"，路径报告里那一行 `Clock Uncertainty` 回答
"这一族的账是不是被同一把尺算过"。四个一起念，缺一个都可能念反。
小结 2：官方口径落在 UG906 p.6（分数用途）、UG949 p.137（异步对不分析）、UG949 p.115（datapath_only
补救）；"Additional Uncertainty"正文与四域统一带子的板侧真值分别是【未核实】与【需板上验证】。
下一步：第 5 节。
---

## 第 5 节 缓存与 DMA：为什么"我写完了"不等于"对方读得到"

### 5.1 一讲：写回式缓存 + 不一致的端口 = 两份真相

① **零术语版**：CPU 写数据时先写进离它很近的一块高速小存储（缓存），什么时候真正落到外面那块大内存
（DDR）由它自己决定。外面的硬件设备不经过这块小存储，它只看大内存。于是同一个地址可以有两种
"当前值"：CPU 以为的，和 DDR 里躺着的。
*这种简化会在"我以为 CPU 写完就全局可见"的情形误导你 —— 只写不刷，设备读到的还是旧的；
反过来设备写完、CPU 读，CPU 可能读到缓存里那份旧的。精确版见下一层。*
（"两份真相"是比喻，不是实现；实现见 `src/ps/main.c:714`、`src/ps/sd_play.c:86-95` 与 `vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/libsrc/standalone/src/arm/ARMv8/32bit/xil_cache.c:455-467`。）

② **不用它会看到什么现象**：三种形状。
(a) **设备读到旧数据**：CPU 画的诊断帧没刷，PL 搬过去的仍是上一帧 ⇒ 屏上"画面不动"，而串口日志说
"我发了"。本工程的这一句是**做了**的：`cmd_fill()` 用 CPU 把整帧写进 DDR 之后，下一句就是
`Xil_DCacheFlushRange(FRAME_ADDR, FRAME_BYTES);`，然后才 `ctrl_set_src(1)` + `ps_publish()`
（`src/ps/main.c:701-716`，写循环首行是 `:702` 的 `volatile u16 *p`）。
(b) **CPU 读回被覆盖**：`src/ps/sd_play.c:86-95` 记的是反方向的账，写得很具体——
"驱动读完会 invalidate 目标区间，但**进**去之前若那里有脏行（例如刚跑过 FILL），invalidate 之后脏行
仍会被写回，把刚 DMA 进来的数据盖掉"，所以 `read_secs()` 在每次 `XSdPs_ReadPolled()` 之前先
`Xil_DCacheFlushRange((INTPTR)dst, (s32)(n * 512u));`（同文件 `:95`）。
(c) **"两边都以为自己对"**：`report/known_issues.md:725` 那条同族教训（非打包数组越界写：
xsim 丢弃、硬件按地址位宽截断 ⇒ 只用硬件读数收口）提醒"日志里的成功"与"内存里真的有"是两件事。

③ **精确定义 + 出处**：Xilinx《Zynq-7000 SoC Technical Reference Manual》UG585 (v1.13)，2021-04-02，
本机 `D:/Xilinx/Resource/Reference Material/6-Xilinx Zynq系列部分官方手册/ug585-Zynq-7000-TRM.pdf`，
核对日期 2026-10-05。四条要紧的：§22.4.5 p.655——"The ACP connects to the snoop control unit (SCU)
which is also connected to the CPU L1 and the L2 cache……**These optionally cache-coherent operations
can prevent the need to invalidate and flush cache lines**"（只有走 ACP 才有"可能不必手动刷"这个选项）；
§22.4.4 p.654——HP 口的描述里没有任何一致性承诺，只讲带宽、内部 FIFO 与更高的最小延迟；
§5.4 p.138——ACP 提供"low-latency access to programmable logic masters, with optional coherency with
L1 and L2 cache"，同页另有两条系统级坑："The PL level shifters must be enabled by LVL_SHFTR_EN
before PL logic communication can occur"，以及默认 TrustZone 下"any non-secure accesses indicated with
AxPROT[1]=1 will receive a DECERR response"；p.32——256 KB OCM "At level of L2, but is not cacheable"。
动作语义在随工具装进本工程的驱动源码里（仓库内路径可直接打开）：
`vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/libsrc/standalone/src/arm/ARMv8/32bit/xil_cache.c:455-459`
——"Flush the Data cache for the given address range… the cachelines containing those bytes are
invalidated. If the cachelines are modified (dirty), they are written to the system memory before the
lines are invalidated"（**flush = 先写回再作废**），函数体 `:467`。本项目状态：缓存是开着的
（`src/ps/main.c:1546-1547` 的 `Xil_DCacheEnable(); Xil_ICacheEnable();`），
所以"维护"不是可选项。

④ **它不是什么**：它不是"跨时钟域"（第 2 节：那是两只钟的采样关系；这是"谁手里那份数据算数"）；
也不是"地址映射没对上"（1.3：那是写到别人的地盘；这是数据没落地或被盖掉）。
最直接的分辨实验在本工程里现成：JTAG 通路读 DDR **不经过 ARM 的 L1/L2**
（`src/host/ddr_verify.mjs:1-11`，走 `xsdb` 回读两个乒乓 bank）。于是
"xsdb 读到新值、CPU 指针读到旧值"这一对比就能把"缓存没维护"与"数据真没写进去"分开。
第三条"不是"：`flush` 不等于 `invalidate`（见 5.2）。

⑤ **辨认方法**：打开 PS 应用源码，搜 `Xil_DCacheFlushRange` / `Xil_DCacheInvalidateRange` 的调用点，
核对**时机**：源侧应出现在"通知硬件之前"（本工程 `main.c:714` 在 `ps_publish()` 之前一行），
目的侧应出现在"读数据之前"（驱动里那次 invalidate 在读完之后，见 5.2）。一个调用都没有 ⇒ 这条路
要么走了硬件一致性端口，要么就是债。打开硬件设计核对是哪条路：
`build/tcl/build_system_axigpio.tcl:100` 只开了 `PCW_USE_S_AXI_HP0`，工程里没有任何 ACP 连接
（同一脚本的互联连接行只有 HP0：`:174`、`:199`、`:203`）⇒ **软件维护是必须的**，这一条可以查死。

### 5.2 一讲：方向决定动作（源侧写回、目的侧作废）

① **零术语版**：两个方向要做的事不一样。别人要来读我写的东西 ⇒ 我得把自己手里那份**交出去**（写回）；
我要读别人写好的东西 ⇒ 我得把自己手里那份**扔掉**（作废），否则读到的是自己缓存里的旧副本。
两个都做过头会各出一次事故：写回不彻底 ⇒ 对方读到旧的；作废不彻底 ⇒ 我自己的旧副本被写回、
把对方的新数据盖掉（正是 5.1 ②(b) 那句话）。
*这种简化会在"我以为只要 invalidate 就干净了"的情形误导你 —— 对**脏行**做 invalidate 会把数据丢掉，
对**别人的读**来说那行数据根本没出门。精确版见下一层。*
（"把自己手里那份交出去 / 扔掉"是比喻，不是实现；实现见 `.../cortexa9/xil_cache.c:455-467` 与 `.../libvitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/libsrc/dmaps/src/xdmaps.c:1510-1516` 的两向写法。）

② **不用它会看到什么现象**：本工程的形状有两条现成的说法。
一条在应用侧：FILL 画完帧之后不刷，PL 的整帧搬运机（`src/rtl/axi/axi_frame_writer_gated.v` 那台）
拉回来的还是上一帧的内容——屏上停在旧画面。**这一条本仓库没有做过对照实验**，
记为【需板上验证】（配方见 `hands-on.md` 第 6 节的独立副本法：把 `main.c:714` 那一行注释掉重建 elf，
看屏与串口）。另一条在驱动侧，是**已经付过学费**的写法：`sd_play.c:86-88` 解释为什么在读之前还要 flush，
而驱动在读完之后 invalidate（`.../libvitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/libsrc/sdps/src/xsdps.c:352-357`）：
`if (InstancePtr->Config.IsCacheCoherent == 0U) { Xil_DCacheInvalidateRange(...) }`
——**只有在不一致的宿主上才作废**，这一行本身就是"方向 + 一致性能力"两个条件决定的动作。

③ **精确定义 + 出处**：动作的官方定义在 BSP 头与实现里（同一份工具自带的源码，路径在仓库内可打开）：
`.../standalone/vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/libsrc/standalone/src/arm/ARMv8/32bit/xil_cache.c:455-459`（flush 的定义：脏行先写回再作废）与
`:467`（实现），`:319`（`Xil_DCacheInvalidateRange` 的实现）。PDMA 驱动把两条规则并排写在一起
（`.../libvitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/libsrc/dmaps/src/xdmaps.c:1510-1516`）：源地址递增时 `Xil_DCacheFlushRange(Cmd->BD.SrcAddr, …)`，
目的地址递增时 `Xil_DCacheInvalidateRange(Cmd->BD.DstAddr, …)`——这就是"方向决定动作"的可核对样本。
UG585 v1.13 §22.4.5 p.655 给出反向证据：走 ACP 时"cache-coherent operations can prevent the need
to invalidate and flush cache lines"，即**动作可以省的前提是硬件有一致性路径**，不是"运气好"。
本项目状态：`main.c:714` 与 `sd_play.c:95` 两处都是 **flush**；`main.c` 里**没有**任何
`Xil_DCacheInvalidateRange` 调用（全仓 grep 只命中 flush 两处 + `Xil_DCacheEnable`，见 5.5）。

④ **它不是什么**：它不是"内存屏障/编译屏障"（那是指令重排问题，本处讨论的是数据在哪一层存储里）；
也不是"未初始化内存"（那是 1.3 的地址问题）。可观察差别的地点在本工程很直白：
两个方向的落点不同——PS→PL 那一侧的 flush 在 `main.c:714`（通知硬件**之前**），
外设→PS 那一侧的 invalidate 在 `xsdps.c:352-357`（传输**完成之后**）；
如果只在其中一侧动作，另一侧的症状形状完全不同（旧画面 vs 被盖掉的新数据）。

⑤ **辨认方法**：拿到任何一段 DMA/共享内存代码，画一张两列的表：**谁写、谁读**。
"CPU 写 → 外设备" ⇒ 找 flush（或 clean）；"外设备写 → CPU 读" ⇒ 找 invalidate。
两个都找不到 ⇒ 检查硬件是否有一致性端口（Zynq 上就是查有没有连 S_AXI_ACP：
本工程 `build/tcl/build_system_axigpio.tcl:100` 那行只开 HP0）。
再查驱动是否有 `IsCacheCoherent` 这一类判定（`xsdps.c:352`）——**有判定**说明这段代码知道自己在处理
"两种平台"；**没有判定**而直接 invalidate 的写法在非对齐地址上会连累邻居（见 5.3）。

### 5.3 一讲：动作的粒度是一整行（32 字节），不是你的那个字节

① **零术语版**：缓存的进出都是以"一小段连续地址"为单位的（本工具的实现按 32 字节一行）。
所以"我只作废我这几个字节"这件事做不到：作废会连累同一行里别人的数据，写回也会把别人的数据一起带走。
*这种简化会在"我按缓冲区边界精确算范围"的情形误导你 —— 缓冲区首尾常常不对齐，
越界那一行的处理必须由库来兜，自己算就会丢数据。精确版见下一层。*
（"一小段连续地址"、"连累同一行里别人的数据"是比喻，不是实现；实现见 `.../cortexa9/xil_cache.c:469` 的 `cacheline = 32U` 与 `:337-341` 的非对齐端点处理。）

② **不用它会看到什么现象**：本工程的现场样本是 SD 读：每次读 `n` 个扇区（`n * 512u` 字节）
（`src/ps/sd_play.c:93-95`）。512 不是 32 的奇数倍问题（512 是 32 的整数倍），
但**缓冲区起始地址 `dst` 是否 32 字节对齐**由上层给的偏移决定，
这就是库必须处理非对齐端点的原因。症状形状是"数据错位几个字节"或"邻居缓冲区莫名被清"。

③ **精确定义 + 出处**：库的实现把这件事写死了：`.../cortexa9/xil_cache.c:469` 的
`const u32 cacheline = 32U;`（flush 路径）、`:321` 同值（invalidate 路径）；
flush 一侧把起始地址向下取整到行边界再逐行推进（`:482` 的 `adr &= ~(cacheline - 1U);`）；
invalidate 一侧对**非对齐起点**先做一次 flush 再作废（`:337-341`：
`if ((adr & (cacheline-1U)) != 0U) { … Xil_L1DCacheFlushLine(adr); … }`），
注释块 `:78-79`、`:89`、`:95` 记录了该系列接口在多个版本里修的问题
（"Fix issues in cache maintenance APIs Xil_DCacheFlushRange and Xil_DCacheInvalidateRange to ensure
that clean and …"、"The existing Xil_DCacheInvalidateRange has a bug where…"）。
行大小这一事实的器件侧出处是 UG585 v1.13：缓存维护按 line 进行，
§22.4.5 p.655 谈"coherent transfers 太大反而造成 cache 抖动（thrashing）"时用的单位也是 cache line；
L2 控制器的寄存器语义在 p.1377 一类页面上写作 "Clean Line by PA / Invalidate"（按物理地址清一行）。

④ **它不是什么**：它不是"页"（MMU 的页是 4 KB，见 1.2 那条 4KB 边界，两者不同尺度）；
也不是 AXI 的 beat 宽度（那是 64 位/8 字节，`PCW_S_AXI_HP0_DATA_WIDTH {64}`）。
可观察差别的地点在数字上：本工程一次 flush 的范围是 `FRAME_BYTES = 512*300*2 = 307200` 字节
（`src/ps/main.c:40`、`:714`），按 32 字节一行是 9600 次行操作——这个量级决定了
"帧边界 flush"能放进 30 fps 的循环，而"整段 DDR flush"不行；这也是为什么必须按区间而不是全局动作。

⑤ **辨认方法**：打开调用点，看传进去的地址与长度：长度是 32 的整数倍吗？地址 32 对齐吗？
两个都不是 ⇒ 库会替你处理端点，但你必须知道它处理的方式（flush 端点 or 作废整行）。
在实现文件里搜 `cacheline = 32U`（`xil_cache.c:469` 与 `:321`）就能确认这颗核的行宽。

### 5.4 一讲：硬件一致性端口存在，代价是抢 CPU 的路；另一条路是不缓存的地址区

① **零术语版**：想彻底不用手动刷，有两条路。一条是让设备走一个"会问 CPU 要最新副本"的专用入口
（ACP）；另一条是把共享数据放在一块**根本不被缓存**的内存区（OCM）。
两条各有代价：前者和 CPU 抢同一条路、传太多反而把 CPU 拖慢；后者容量小（256 KB）且没有大内存的带宽。
*这种简化会在"我以为一致性端口是免费的加速口"的情形误导你 —— 它是拿 CPU 的性能换软件简洁；
工程上要不要走它取决于数据量与实时性。精确版见下一层。*
（"会问 CPU 要最新副本的专用入口"、"抢 CPU 的路"是比喻，不是实现；文档口径见 UG585 v1.13 §22.4.5 p.655 与 §5.4 p.138，本工程的可核对点是 `build/tcl/build_system_axigpio.tcl:100` 只开 HP0、没有 ACP 连接。）

② **不用它会看到什么现象**：本工程的形状是**主动选了不一致的那条口**：所有帧数据走 HP0
（`build/tcl/build_system_axigpio.tcl:100` 的 `PCW_USE_S_AXI_HP0 {1}`，脚本里没有一处 ACP 连接），
软件维护两处 flush（`src/ps/main.c:714`、`src/ps/sd_play.c:95`，见 5.1/5.5）。假如改用 ACP 而不做 flush，症状不会立刻出现——
它会在"CPU 大量读那块共享内存"时表现成 CPU 变慢或数据抖动，而不是画面错误。
这条代价在文档里是明写的（见 ③）。

③ **精确定义 + 出处**：UG585 v1.13 §22.4.5 p.655 给出好处与代价两面："The ACP differs from the HP
performance ports due to its connectivity inside of the PS. The ACP connects to the snoop control unit
(SCU)… These optionally cache-coherent operations can prevent the need to invalidate and flush cache
lines. The ACP also has the lowest memory latency to memory of the PL interfaces."
紧接着一段是代价："Memory accesses through the ACP utilize the same interconnect paths as the APU,
potentially decreasing CPU performance. Large, coherent ACP transfers can cause thrashing of the cache.
Thus ACP coherent transfers are best suited for less than the largest data-sets."
§5.4 p.138 补一句系统视角："From a system perspective, the ACP interface has similar connectivity
as the APU CPUs. Due to this close connectivity, the ACP directly competes with them for resource
access outside of the APU block."；p.32 给 OCM 那条路："256 KB of on-chip SRAM (OCM) with parity…
At level of L2, but is not cacheable"。本项目状态：没有 ACP 连接、没有用 OCM 做帧缓冲
（`build/tcl/build_system_axigpio.tcl:100` 只开 HP0；三个帧基址都在 DDR，见 1.3 ③）。

④ **它不是什么**：它不是"总线的原子性/突发保护"（那是 1.2 的 4KB 边界问题）；也不是"缓存命中率优化"。
可观察差别的地点在拓扑：同一个 PL master 走 HP 还是走 ACP，改变的是**它接进 PS 的哪一个口**，
RTL 里端口名就不同（HP 是 `S_AXI_HP0`、ACP 是 `S_AXI_ACP`，UG585 p.56 的接口清单把两者分开列着，
并给 ACP 标了"cache-coherent transaction"）。这一眼就能分辨。

⑤ **辨认方法**：打开 block design / 系统整合脚本，搜 `S_AXI_ACP`：接了 ⇒ 一致性由硬件参与；
没接 ⇒ 一致性由软件负责（本工程属后者）。再打开地址映射，看共享缓冲落在 DDR 还是 OCM
（Zynq 的 OCM 地址段与 DDR 段不同；本工程三个基址 `0x1000_0000` / `0x1008_0000` / `0x1010_0000`
都在 DDR 段，见 1.3 ③）。两个问题都答得出，才知道"要不要 flush"这件事归谁。

### 5.5 本工程的实况（做没做、做了什么、什么没测）

- **做**：两处 `Xil_DCacheFlushRange`——`src/ps/main.c:714`（整帧 307200 字节，通知 PL 之前）与
  `src/ps/sd_play.c:95`（每次 SD 读之前，按 `n*512` 字节的区间）。缓存是开的
  （`main.c:1546-1547`）。
- **没自己做的那一半**：`main.c` 里没有 `Xil_DCacheInvalidateRange`；读方向由官方驱动代做
  （`.../libvitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/libsrc/sdps/src/xsdps.c:352-357`，且带 `IsCacheCoherent` 判定）。
  所以"驱动若不做会怎样"这一问不在本工程的实测范围内，属于依赖别人的行为，
  读代码可核对，未独立验证。
- **地址分开的另一笔账**：PS 帧缓冲原先与 ETH 的第 0 块 bank 重叠（同是 `0x1000_0000`），
  于是 SD/FILL 一边写、ETH 一边读写同一块内存，屏上表现为"两个片源打架、闪"
  （板级实测 2026-09-24，原文：`src/ps/main.c:41-46`）。这条**不是**缓存问题，
  是所有权问题；两者容易混，所以在这里点名分开。
- **对照实验未做**：注释掉 `main.c:714` 之后屏与串口各会怎样 ⇒ **【需板上验证】**，
  因此本节不把"不刷就一定看到旧帧"写成实测结论，只写现象与风险。
- **一条不受影响的通路**：`src/host/ddr_verify.mjs` / `src/host/ddr_stale.mjs` 走 JTAG（`xsdb`）回读，
  不经过 ARM 缓存 ⇒ 可以用它们把"缓存问题"与"数据没写进去"分开（5.1 ④）。

**本节的题外场景**

- 同一套规则在另一支外设驱动里的样子：PS 的 PDMA 驱动把两个方向并排写出来
  （`.../libvitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/libsrc/dmaps/src/xdmaps.c:1510-1516`：源递增 ⇒ flush、目的递增 ⇒ invalidate）。
  这不是本工程写的代码，是工具自带的另一套系统；它的存在说明"方向决定动作"不是某个驱动的巧合，
  而是这套核的通用要求。
- 把共享暂存放在不缓存的 OCM 里：UG585 v1.13 p.32 的"OCM … is not cacheable"，
  加上 p.178 记录的实际流程"BootROM normally copies FSBL/User code to OCM memory"
  （启动阶段代码在 OCM 里跑，不需要为它做一致性动作）。
  这是另一台系统（启动链）用第二种解法的例子，代价是 256 KB 的容量。

小结 1：这一节的四件事按顺序成立——写回缓存与不一致端口造成两份真相（5.1）；方向决定该 flush 还是
invalidate（5.2）；动作的粒度是 32 字节行、端点由库兜（5.3）；不想手动刷就只有两条路：
硬件一致性端口（有代价）或不缓存地址区（有容量上限）（5.4）。
小结 2：官方口径落在 UG585 v1.13 p.32/p.138/p.654/p.655/p.1377 与仓库内 BSP 源码
`xil_cache.c:455-469` / `:319-340`、`xsdps.c:352-357`、`xdmaps.c:1510-1516`。
本工程**未做**的是对照实验（【需板上验证】）。下一步：第 6 节。
---

## 第 6 节 约束射程：按名字点人的语言，改名之后不会报错

本节讲"约束的作用范围"这件事本身。本工程的跨域点全表与两文件拆分的原因在
`clocking-and-reset.md` 第 3、5 节（那里已经把"约束悄悄不生效"的三个现场观察列全），
本节只补它的**通用形状**与"别的系统里也会这样"的证据。

### 6.1 一讲：约束命令的作用域是"当时存在的那批对象"

① **零术语版**：约束语言是"按名字点人"的命令：先找到满足条件的对象（这根钟、这个端口、这些触发器），
再把规则压上去。如果点名的东西此刻不存在，命令就没压到任何人——而工具通常**不把流程停下来**，
它只留下一句提示，报告于是变得好看。
*这种简化会在"我以为没报错就是都压上了"的情形误导你 —— 报错的级别可以低到 warning，
甚至可以完全没有；"报告里没红字"与"所有对象都在射程里"是两件事。精确版见下一层。*
（"按名字点人"是比喻，不是实现；实现见 `src/constraints/rk_zynq7020.xdc:43-45`、`:50`、`:64-70` 三处现场记录。）

② **不用它会看到什么现象**：本工程的三种现场形态，全部有原文记录。
(a) **整条命令空转、只留一条 CRITICAL WARNING**：`set_clock_groups` 里点了一个当时还不存在的名字
（`clk_fpga_0` 由 PS7 IP 自己的约束创建，综合阶段它还不存在），于是三组关系一条都没生效，
现场只留下一句 `CRITICAL WARNING [Vivado 12-4739] set_clock_groups: No valid object(s) found for
'-group [get_clocks -quiet clk_fpga_0]'`（原文：`src/constraints/rk_zynq7020.xdc:64-70`；
修法与"为什么不能写在同一个文件里"见 `src/constraints/clock_groups_impl.xdc:1-8`）。
(b) **方向搞反的空约束**：把只对输出端口有意义的 `set_false_path -from` 写在 `eth_rst_n`（它是输出）上，
每次综合报一条 `CRITICAL WARNING [Constraints 18-513] ... -from ... contains no valid startpoints`，
"是一条空约束（不约束任何东西，只制造噪声）"（原文：`src/constraints/rk_zynq7020.xdc:51-55`）。
(c) **约束文件里写控制流被整块跳过**：`if` 在 XDC 里会报 `[Designutils 20-1307]`
（同文件 `:71-72`），而构建脚本侧的同族事故记在 `build/tcl/build_system_axigpio.tcl:71-74`：
"守卫会静默失效"，件 `build/evidence/r119_xdc_loads_probe2.txt`。

③ **精确定义 + 出处**：**这一条的官方解释句本次未取到正文**（本机可用的 UG906 中文版正文里没有
"对象不存在 ⇒ 命令空转"这一段；UG835《Vivado Tcl Commands》本机 PDF 只给出约束语言的位置——
p.3："SDC is the mechanism for communicating timing constraints for FPGA synthesis tools …
consequently, the Tcl infrastructure is a 'Best Practice' for scripting language"，
讲的是"约束是命令式、按对象说话"这一语言形态，不是失败语义）⇒ **该定义句标为【未核实】**，
本节因此不写"工具规定……"，只写"本工具在本仓库的现场表现是……"。
现场证据（可核对，含编号）：上面 ② 的三条 ID 与文件行号；`-quiet` 的边界是同文件
`:67-70` 那句"`-quiet` 只能压住 `get_clocks` 的报错、压不住命令本身"；
拆分后为什么不改变时序数字，同文件 `:73-74` 的理由是"综合阶段本来就拿不到这条约束（命令是失败的）"。
本项目取值：现役构建只加载两个约束文件
（`build/tcl/build_system_axigpio.tcl:31`、`:36-37` 的 `add_files -fileset constrs_1`
与 `set_property used_in_synthesis false`），其余四份（`r114_*`、`r115_*`、`r116_*`、`r119*`）
是候选件，由环境变量开关控制（`:57-63`、`:75-81`）。

④ **它不是什么**：它不是"约束写错了会报错"。三者的区别在症状：写错方向会留 CRITICAL WARNING（②(b)）、
点名不存在的对象会留 CRITICAL WARNING（②(a)）、而**改名/换源之后点名旧名的约束**通常连 warning 都
不留——因为那条命令语法完全正确，只是命中集合空了（见 6.3）。可观察差别的地点就在 6.3 那一刀：
同一族报告里 `Clock Uncertainty` 那一行从**带 `UU`**（`build/clock_uncertainty.rpt:107`）变成
**只剩抖动项**（`report/log/issues.md:12579-12580` 那两行），不是报错。

⑤ **辨认方法**：不要读日志级别，读命中数。三条固定动作：
**(a)** 打印实现后**实际存在**的时钟名集合（本工程那两行打印：
`build/tcl/clock_uncertainty.tcl:29-30` 的 `GET_CLOCKS_eth_rxc` / `GET_CLOCKS_clk_fpga_0`；
另一把尺子取全部钟：`build/tcl/c2_scratch_probe.tcl:33` 的 `get_clocks -quiet *`）；
**(b)** 把约束文件里所有"提到时钟名/端口名"的行按名字分组，与 (a) 取差；
**(c)** 对每条点名约束问一次"它约束了几个对象"，改前改后各打一次，从 N 变成 0 的那条就是本案。
这套顺序在 `skills/pitfalls/constraint-coverage-loss/SKILL.md:28-39`（①）与 `:41-50`（②）里写成了
排查清单；该卡自己也承认代价形式："未量过，属建议"（同文件 `:132-137`）。

### 6.2 一讲：一条命令里点多个对象，一个错名会让整条空转

① **零术语版**：一条命令里可以同时点一串对象。人以为它是"逐个尽力"——能约束几个算几个；
它的实际语义常常是"全有或全无"——有一个取不到，整条就不生效，连取到的那几个也一起废掉。
*这种简化会在"我把'去掉一个错名'当成'少约束了一个对象'"的情形误导你 ——
去掉那一个之后重新生效的是**一整组**关系，量出来的数字变化会远超预期。精确版见下一层。*
（"逐个尽力"、"全有或全无"是比喻，不是实现；实现见 `src/constraints/rk_zynq7020.xdc:43-45` 那条警告与 `src/constraints/clock_groups_impl.xdc:1-8` 的拆分修法。）

② **不用它会看到什么现象**：本工程的现场句写在
`src/constraints/rk_zynq7020.xdc:43-45`："只写 eth_rxc 一个对象：本文件下面那段旧账证明，
把 `get_clocks` 取不到的名字（例如 PS7 IP 自己 create 的 `clk_fpga_0`）并进同一条命令，
会让**整条命令空转**、连带把 `eth_rxc`/`sys_clk` 那几组一起废掉，而且现场只留下一句 warning。"
同族的第三种形状是"少了那个后缀"：`set_clock_groups` 的 `-group` 若不带
`-include_generated_clocks`，MMCM 的输出钟就不在组里，`clk_pix` 会被当成独立时钟去和 `eth_rxc`
做 setup 分析，历史上是 WNS ≈ −6.7 的**假违例**（原文：
`src/constraints/clock_groups_impl.xdc:13-17`；事故登记 `report/log/issues.md:143`）。
⇒ 这一条的教训方向与直觉相反：不是"覆盖太窄所以漏查"，也可能是"覆盖太窄所以**假红**"。

③ **精确定义 + 出处**：与 6.1 同一处境——**"命令失败语义"的官方条款正文本次未取到** ⇒
【未核实】。可核对的仓库侧口径有两条：`skills/pitfalls/constraint-coverage-loss/SKILL.md:41-50`
把根因写成"批量命令的失败语义是'全有或全无'，而人以为它是'逐个尽力'"，并给出四条排查（数对象、
逐个查存在、拆成一条一对象再对比命中数、看实现日志里有没有被跳过的痕迹）；修法两条都在本仓库落地了：
每条命令只点一个对象（`rk_zynq7020.xdc:50`）+ 按时机拆文件（`clock_groups_impl.xdc:1-8`、
`build/tcl/build_system_axigpio.tcl:36-37`）。本项目取值：现役那三组异步关系的完整写法是
`src/constraints/clock_groups_impl.xdc:28-31`（`eth_rxc` 一组、`clk_fpga_0` 带 `-quiet` 一组、
`sys_clk` 带 `-include_generated_clocks` 一组），文件头 `:25-26` 还明写了一件**故意**的事：
`clk_pix` 与 `clk_pix5x` 有意留在同一组内，让 TMDS 并串转换按同步路径做 setup 分析，
"声明成异步反而会漏检"。

④ **它不是什么**：它不是"对象名写错所以那条约束被忽略"（那是 6.1，只影响自己）；也不是"约束优先级"
问题（同名约束的读写先后另有规则，本仓库在 `report/command_precedence.md` 专门处理，不在本节范围）。
可观察差别的地点：本案的特征是**别的域也一起变**——去掉错名之后 `eth_rxc` 与 `sys_clk` 两组关系
同时出现（这正是 `:43-45` 那三行警告要防的读法错误）。

⑤ **辨认方法**：打开任何一条多对象命令，数它点了几个名字；然后逐个名字单独查一次存在性
（Vivado 侧就是 `get_clocks -quiet <名>` / `get_ports -quiet <名>` 是否为空）。
只要有一个为空，就把这条命令当成**没执行过**来读报告，而不是当成"执行了一部分"。
在报告侧的辨认：本工程的 `report/timing/debt_ledger.md:30-31` 用两个计数把"射程"钉成数字
（`unconstrained_endpoints = 0`、`io_unconstrained_ports = 11`），换约束之后这两个数一起动，
就知道整条命令确实重新生效了。

### 6.3 一讲：换钟源 = 换终点 = 覆盖面自动缩小（本工程真踩过的那一刀）

① **零术语版**：约束点的是**那只钟**。你把某段逻辑从"直接用外面进来的钟"改成"用一颗 MMCM 派生出来的钟"，
这段逻辑的终点就换成了另一只钟的名字；所有点名旧钟的约束从此管不到它——
而你**一条约束都没删、一个字都没改**。
*这种简化会在"我以为没改约束就等于约束都还在"的情形误导你 —— 改的是被约束对象的身份，
不是约束语句；报告不会提醒你，只会让数字变好。精确版见下一层。*
（"换终点"、"点名旧名的约束管不到它"是比喻，不是实现；实现见 `report/log/issues.md:12578-12589` 的 UU 消失记录与件 `build/evidence/r115_c2_scratch/option_a_console.txt`。）

② **不用它会看到什么现象**：本工程的记录很具体（`report/log/issues.md:12567-12589`，#305）：
副本树把 IDDR 的捕获钟换成 MMCM 派生钟之后，最差 hold 路径的两行读数是
`Requirement : -1.000 ns (mmcm_clk0 rise@3.000ns - eth_rxc fall@4.000ns)` 与
`Clock Uncertainty : 0.166 ns ((TSJ^2 + DJ^2)^1/2) / 2 + PE`——**UU 项不见了**；
同一条路在 r114 是 `0.835 … + UU`（件 `r114_sweepB/rt_tap0_eth_rxc_hold.rpt`）。
于是这一刀"买到"的 `+0.759 ns` 里，**约 0.67 ns 是约束作用范围被削弱换来的，不是物理改善**
（原文同页；另一处摘要在 `report/40-optimization.md:120` 的 V14 行）。台账把可复用清单写成一句话
（`report/log/issues.md:12589`）："**只要新建/改名一只钟，所有点名旧钟的约束都要重查覆盖面**
（`set_clock_uncertainty`、`set_clock_groups`、`set_input_delay -clock`、IDELAY/参考钟关系）"，
这条清单同时进了 `report/timing/rgmii_window_model.md` §7。附带还有一件：名册的按名字配对因此失效
（#305 的 S3 判不了：终点换了名字 ⇒ 2 个 presence 变化、6 个 margin 红，
"配对失效不等于 G1 红，脚本按约定没替它圆场"）。

③ **精确定义 + 出处**：这一讲的"定义"由四件现场组成，全部可打开：
**(a)** 约束原文 `set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]`
（`src/constraints/rk_zynq7020.xdc:50`）；**(b)** 事故前后两行读数（上面 ②，
`report/log/issues.md:12578-12585` 的代码块，件
`build/evidence/r115_c2_scratch/option_a_console.txt`）；**(c)** 处置记录：C3 判负、不进主树、
不刷板，台账行 `report/timing/cut_ledger.tsv` 的 C3 = `rejected-measured`
（`report/40-optimization.md:120` 末列）；**(d)** 资源侧对照：这条结构刀的代价几乎为零
（`MMCME2_ADV` 2/4 → 3/4、LUT +5、FF 不变，"死因是机制不是代价"，
`report/log/issues.md:12596-12598`；现役占用行 `build/report/utilization.rpt:163` 是 2/4）。
工具侧对"派生时钟需要被点名"的正面口径在同一条事故里也出现过：
下一轮的两条出路之一是"把三条约束改成 `-include_generated_clocks`"（同文件 `:12594-12595`）。

④ **它不是什么**：它不是"约束被覆盖了（precedence）"；也不是"该约束本来就不适用"。
分辨方法在本工程现成：本案的特征是**报告里那一行 `Clock Uncertainty` 整行消失或数值变小**，
而约束文件一字未改（对照 4.4 ⑤ 的辨认动作）。第二件区别：如果是"对象不存在"，
工具会留下 ②(a)(b) 那一类 CRITICAL WARNING（现场编号 `[Vivado 12-4739]`、`[Constraints 18-513]`，原文行号
`src/constraints/rk_zynq7020.xdc:64-70`、`:51-55`）；本案**什么都没留**，只让数字变好
（对照 `build/clock_uncertainty.rpt:107` 有 `UU` 的那一行）。

⑤ **辨认方法**：任何一次动了时钟源/相移/分频的改动之后，跑这四步（本工程全部有对应件）：
**(1)** 打开最差 min 路径报告，看 `Clock Uncertainty` 那一行还在不在、`UU` 在不在括号里
（`build/clock_uncertainty.rpt:93-107` 就是这份件的标准形状）；
**(2)** 打印实现后时钟名册（`report_clocks`/`get_clocks`），与约束里点名的名字取差；
**(3)** 对每条点名约束打"命中对象数"，改前改后对比，N→0 的那条就是本案
（`skills/pitfalls/constraint-coverage-loss/SKILL.md:26` 的"核心动作只有一个"）；
**(4)** 名册差分按**配对集合**比而不是按绝对数比，配对失效要单独说
（`build/gates.sh:101-104`、`:125-131` 的 CDC 门禁就是这个形状，时序名册同族：
`report/timing_global.md:168-170`）。

### 6.4 一讲：把"射程"变成可打印的数（否则下一次还是会被数字骗）

① **零术语版**：能被静默改变的东西，只能用**被打印出来的数**去守。射程这件事有三个可打印的数：
被点名的对象数、被比较的比较次数、被扫到的文件数。三个数只要有一个"读不到"或"为 0"，
判定就不许写"通过"，要写"没测"。
*这种简化会在"我以为检查器报了 0 就是没问题"的情形误导你 —— 0 也可能是"它什么都没看到"；
尺子看不见被测对象的时候最像绿。精确版见下一层。*
（"射程"、"尺子看不见"是比喻，不是实现；实现见 `build/gates.sh:64-71`、`:101-104`、`:125-131` 三段读数字段的代码与注释。）

② **不用它会看到什么现象**：本仓库有三条同族事故记录，都不是设计错、而是**尺子看不见**。
(a) 门禁自己没牙：`build/gates.sh:66-71` 记的是 r60 那一次——TNS 在违例时是负数，
而解析式只给 WNS/WHS 留了符号位 ⇒ awk 不匹配 ⇒ 脚本打印"FATAL 读不到"然后 exit 2，
"停下来是对的（没把自己判绿），但它把最该看见的数字（WNS −0.482 / 19 个失败端点）换成了
'读不到'这句话"。现在的做法是"读不到时把候选行原样打出来"。
(b) CDC 判据按配对集合比：`build/gates.sh:93`（"与基线的'行集合'比，不与一个写死的数字比"）、
`:109-114`（基线里有一行不是三列 ⇒ 直接 FATAL，不"静默把缺的第三列当 0"）、`:125-131`
（unsafe 变大判红）、`:150-156`（比上一版采纳件多出的 Critical 配对 ⇒ 判红，#209）。
(c) 名册口径不配对就拒判：`report/05-timing.md:52-58` 记的是"对照侧必须是同一个生成器产的"，
混口径会被口径闸门判 REFUSE（账在 `report/log/issues.md` #326）。

③ **精确定义 + 出处**：可打印数的三条硬要求都能指到具体判据上，不用抽象说法：
**比较次数**地板：`report/timing_global.md:103` 给的那把尺子的判据清单
（U1 逐时钟行数地板、U2 四域不许缺数、U3 带子真落上"applied≥1 且至少一域 after<before"、
U4 与归档 WNS 对齐、U5 负数计数与点名一致、U6 对齐——六条，且自带能红的对照）；
**扫描面**地板：`skills/pitfalls/constraint-coverage-loss/SKILL.md:100-109`（射程由遍历现算、
分层打印每层命中数、地板不为 0）；**否证力**地板：同文件 `:111-121`（"以'搜不到'为根据的判定，
都要要求一次正对照命中才允许写 PASS"）。本仓库的判定值域也写死了：
同文件 `:136-137`"结论行末位只允许 `PASS / FAIL / NOT_MEASURED`，空集与读不到一律第三种"。

④ **它不是什么**：它不是"多做几项检查"；也不是"把阈值调宽"。本案里两个数字都动过，
但真正的账是"这把尺此刻看得见多少对象"。可观察差别的地点：`report/timing_global.md:103`
那句"这不是'板子 hold 坏了'——是**没测过**"，以及 `report/05-timing.md:129-131`
"那 5 格根本不在被检查的集合里 ⇒ 没查 ≠ 达标"。

⑤ **辨认方法**：拿到任何一条"检查通过"，先看它同一次输出里有没有这三个数之一：
比较次数、命中数、扫描到的文件数；没有 ⇒ 当 `NOT_MEASURED` 处理。
本工程的样例形状：`build/gates.sh:104` 的 `rows()` 打印"配对 端点数 unsafe"三列，
`report/timing/debt_ledger.md:140-143` 那张表把 `unconstrained_internal_endpoints`、
`no_input_delay` 的 HIGH 计数、`no_output_delay` 的 6 个端口名逐行列出——
**每行都是一个数，不是一句"已检查"**。

**本节的题外场景**

- 豁免（waiver）是第二条静默通道：UG906 中文版 p.45 写"在创建豁免之前，请确保设计中存在引用对象。
  如果在创建豁免时不存在设计对象，则豁免不适用于这些设计对象"，并警告"避免在实现后的设计上创建豁免，
  因为引用的对象可能不存在于综合后的网表中。如果在错误阶段对不存在的对象应用无效豁免，则会丢弃这些豁免"；
  p.47 又写"重新运行报告后，会筛选掉豁免的违例"。⇒ 另一台系统上的同一形状：
  **报告变干净，可以是因为记录被筛掉了，也可以是因为对象换了名字使豁免失效**；
  两侧都要求"命中数"这种读数才能分辨。
- IP 换版本 / 换配置带来的名字漂移：PG054 v3.3 p.16-18 用整页说明信号名的引用约定
  （p.17："Throughout this document, … the Transmit Source Discontinue signal is referenced as:
  (tsrc_dsc) `s_axis_tx_tuser[3]`"），并声明接口位宽是"static selection"（p.17 表 2-8 注 1）。
  也就是说：**位宽/速率配置一变，一拍能带的字节数与位序映射就跟着变**（p.18 的 `tstrb` 位序
  按 64/128 位分别定义）——按位序写死的约束、台架路径与上位机常量都要重查覆盖面。
  本工程的同类清单在 `src/host/repo_path.mjs` 与 `build/gates.sh` 的硬编码字段位置上
  （后者 `:101` 就写明"不是固定列号"，因为列数会变）。

小结 1：这一节的四个概念是同一条链——约束按对象点名（6.1）、多对象命令是全有或全无（6.2）、
换钟源会让点名旧名的约束自动脱靶（6.3，本工程量到过：+0.759 ns 里约 0.67 ns 是这个来源）、
所以射程必须被打印成数（6.4）。
小结 2：本节两条"官方解释句"（6.1 ③、6.2 ③）标为【未核实】，其余全部落到本仓库可打开的件与行号；
`clocking-and-reset.md` 第 5 节是本节三个现场观察的仓库内正本。下一步：第 7 节。
---

## 第 7 节 本篇讲不出落点、因此挪给 `next-layer.md` 的机制

规矩是"用到才写"：讲不出"在本工程哪一处能观察出差别"的机制不进本篇。以下六条本次被挪出，
每条都写出**挪出的原因**与**该往哪儿接着读**，不留空口。

1. **MTBF 的数值公式与器件参数**（第 2.6 讲只给了"级数换 MTBF"的流程）。
   原因：UG949 p.114 把定量命令只列在 UltraScale 分支，本器件（7 系列）无对应读数，
   本仓库也没有带参数的公式来源 ⇒ 无法给出"可核对的数"。下一层要读：UG949 第 3 章 CDC 一节全段
   （本机 PDF p.112-115）与库指南里对应同步器的参数表。
2. **CDC 的形式验证 / 模型检查**（本篇的判据全部是结构 + 仿真）。
   原因：本仓库没有跑过任何形式工具，没有件 ⇒ 讲不出落点。下一层要读：工具自带的形式验证流程文档，
   入口是本仓库现有 `report_cdc` 与 `report_methodology` 两条产物的字段定义（UG906 中文版相应章节）。
3. **AXI 接口协议检查器（protocol checker）的接线与违例名**。
   原因：本工程的互联没开检查器，1.1 ③ 那条 `abort` 撤 `arvalid` 的疑点因此只能标【未确认】；
   等检查器接上再写。下一层要读：互联 IP 的"接口检查"文档（本仓库现有正本是
   `build/tcl/build_system_axigpio.tcl` 的建链段，`:174`、`:199`、`:203` 三行是接线点）。
4. **硬件一致性（ACE / ACP）的实际使用与限制**。
   原因：本工程一个 ACP 端口都没连（5.4 ③ 只能引用文档、给不出观察）。
   下一层要读：UG585 v1.13 §5.4（本机 PDF p.138）与第 3 章 APU 一节里"its limitations"指向的那段。
5. **约束优先级与同类约束的读写顺序**。
   原因：本仓库已有专门正本 `report/command_precedence.md`，本篇不重复（6.2 ④ 已点出边界）。
6. **总线 QoS / 仲裁公平性**（1.4 只讲了"平均排空速率"，没讲"谁被优先服务"）。
   原因：本平台没有 QoS 读数出口。下一层要读：UG906 中文版第 8 章"NoC 服务质量分析"
   （本机 PDF 目录 p.3 那一段，正文 p.288 起）。

小结 1：这六条的共同点不是"太难"，而是**本仓库此刻拿不出一个可打开的观察点**；
每条都留了原因与去处，方便下一轮直接接着量。
小结 2：如果其中任何一条被补上了件（尤其是第 3、4 条），它就应该从本节移进第 1 或第 5 节正文。
下一步：第 8 节。

---

## 第 8 节 出处清单（文档号 / URL / 本机 PDF + 页码 + 核对日期）

外部官方文档（全部为本次真的下载或打开、并用本机文本抽取读到原文的件；核对日期 2026-10-05）

| 文档号 / 版本 / 日期 | 位置 | 本篇用到哪几页 | 用在哪一讲 |
|---|---|---|---|
| ARM IHI 0022, Issue J（AMBA AXI Protocol Specification），2023-03 | 下载自 `https://documentation-service.arm.com/static/63ff0ebd56ea36189d4e7ee7`（273 页；`https://developer.arm.com/documentation/ihi0022k/` 会 301 到 `support.arm.com`，那条路只返回站点配置，正文要用上面这个静态件） | §A3.1.1 p.38；§A3.2 p.39-40；§A3.3.1 p.41；§A4.1 p.50；§A4.1.3-4 p.52-53；§A4.2.1-2 p.58；§A4.2.4 p.62-63 | 1.1 / 1.2 / 1.3 / 1.4 / 5.1 |
| UG949《UltraFast 设计方法指南》中文版 2026.1（页脚保留来源行 v2024.2，2024-12-18） | `D:/Xilinx/Resource/Timing Analysis/ug949-vivado-design-methodology-zh-cn-2026.1.pdf` | p.40-41（控制集与异步复位对 BRAM/DSP 的影响）、p.49（乘法与 DSP 块、三级流水）、p.50（RAM 深度→LUTRAM/BRAM）、p.53（`ram_style`）、p.108（`ASYNC_REG` 单 slice）、p.112（单/多比特 CDC 决策树）、p.114-115（`DEST_SYNC_FF`/MTBF、`set_max_delay -datapath_only`）、p.137（异步 CDC 不应用默认时序分析）、p.138（`report_cdc` 拓扑与"不提供时序信息"） | 2.1 / 2.2 / 2.3 / 2.4 / 2.6 / 3.1 / 3.2 / 3.4 / 3.5 / 4.3 / 4.5 |
| UG906《设计分析与收敛技巧》中文版 v2025.2，2025-12-10 | `D:/Xilinx/Resource/Timing Analysis/ug906-vivado-design-analysis-zh-cn-2025.2.pdf` | p.3（目录：TIMING-15/16/17/18 与第 8 章 NoC QoS 页码）、p.6（WNS/TNS/WHS/THS/WBSS/TPWS 的用途）、p.45、p.47（豁免机制与"重跑报告会筛掉豁免的违例"） | 4.1 / 4.2 / 4.3 / 6.1 / 6.4 / 第 7 节第 6 条；正文内**无** `SYNTH-` 编号（3.5 ③ 因此标【未核实】） |
| UG585《Zynq-7000 SoC Technical Reference Manual》v1.13，2021-04-02 | `D:/Xilinx/Resource/Reference Material/6-Xilinx Zynq系列部分官方手册/ug585-Zynq-7000-TRM.pdf`（1825 页；另一份同名件在 `D:/Xilinx/Resource/ZYNQ7020/Board_Resource/芯片手册/ZYNQ7000/` 是截断件，pypdf 打不开） | p.32（SCU / ACP / OCM 三条概览，含"not cacheable"）、p.41（AXI_ACP 是 coherent 从端口、AXI_HP 四个高性能主口）、p.56（§3.5.1 接口清单）、p.138（§5.4 AXI_ACP：LVL_SHFTR_EN、TrustZone DECERR）、p.178（BootROM 把代码拷进 OCM）、p.654（§22.4.4 HP 口：内部 FIFO、更高最小延迟、要多笔在途）、p.655（§22.4.5 ACP：可省 invalidate/flush，代价是抢 APU 路径、大数据集会抖缓存）、p.1377（L2 的 Clean/Invalidate Line by PA 寄存器语义） | 1.2 / 1.3 / 1.4 / 5.1 / 5.2 / 5.3 / 5.4 |
| UG473《7 Series FPGAs Memory Resources》 | `D:/Xilinx/Resource/Reference Material/6-Xilinx Zynq系列部分官方手册/ug473_7Series_Memory_Resources.pdf` | p.11（36Kb/18Kb 的宽度档位；"Write and Read are synchronous operations"；可选输出寄存器/锁存） | 3.1 / 3.2 / 3.3 |
| UG479《7 Series DSP48E1」 | `D:/Xilinx/Resource/Reference Material/6-Xilinx Zynq系列部分官方手册/ug479_7Series_DSP48E1.pdf` | p.9（25×18 乘法器、48 位累加器、pre-adder）、p.10（A 寄存器 30 位、A 喂 pre-adder、级联）、p.14（至少两级流水才跑满速；M 寄存器的使用） | 3.4 |
| DS187《XC7Z010/XC7Z020 Data Sheet》v1.21，2020-12-01 | `D:/Xilinx/Resource/Reference Material/6-Xilinx Zynq系列部分官方手册/ds187-XC7Z010-XC7Z020-Data-Sheet.pdf` | p.46 表 65（Block RAM clock-to-out：带/不带输出寄存器）、p.47（RAM 使能/CE/复位脚的 min 时序）、p.49 表 66（DSP48E1 数据/控制脚到输入寄存器的建立与保持） | 3.1 / 3.3 / 3.4 / 4.1 |
| PG054《7 Series FPGAs Integrated Block for PCI Express》v3.3，2017-10-04 | `D:/Xilinx/Resource/ZYNQ7020/Board_Resource/芯片手册/ZYNQ7000/pg054-7series-pcie.pdf` | p.13（sys_rst_n 是异步输入）、p.16（表 2-7：`user_clk_out` 仅在 `user_reset_out` 撤销后保证频率稳定；`user_reset_out` 由带内复位拉起）、p.17（表 2-8 事务钟频率与"位宽是静态选择"）、p.18（`tstrb` 位序 ↔ `s_axis_tx_tdata`） | 1.1 / 1.4 / 2.6 / 6.4 |
| Micron MT41K256M16TW-107（DDR3L 4Gb x16）数据手册 Rev. Q，12/17 | `D:/Xilinx/Resource/ZYNQ7020/Board_Resource/芯片手册/C253882_DDR+SDRAM_MT41K256M16TW-107-P_规格书_MICRON(镁光)DDR+SDRAM规格书.PDF` | p.102（Command and Address Setup/Hold and Derating，`tIS/tIH(base)` 分档）、p.109（Data Setup, Hold, and Derating：tDS/tDH = base + derating） | 2.6 / 3.3 / 4.1 / 4.4 |
| 《JESD204B 应用指南》中文版（78 页；第 1 页未标应用笔记编号，按路径 + 页码引用） | `D:/Xilinx/Resource/Reference Material/ad/JESD204B应用指南_中文版.pdf` | p.15（CGS/ILAS 两阶段与器件时钟/SYSREF 的角色）、p.18（接收器把数据送入 FIFO、LMFC 边界输出 ⇒ 确定性延迟）、p.20（M/L 不一致与"参数值−1"的排查清单）、p.22（时钟与 SYSREF 偏斜要计入 PCB 布局） | 1.3 / 1.4 / 2.6 / 4.4 |
| XAPP793《Vivado HLS Memory Structures in Video and DSP algorithms》v1.0，2012-09-20 | `D:/Xilinx/Resource/ZYNQ7020/MLK_demo/04_example_HLS_Image/HLS参考资料/xapp793-memory-structures-video-vivado-hls.pdf` | p.3（三类存储形状与"工具不会自动插入新存储器"）、p.6（窗口移动约束在行缓存上） | 1.4 / 3.5 |
| 《10G Ethernet UDP/IP 协议栈规格书》Rev 1.0，2026-04-15（第三方 IP 说明，非厂商手册） | `D:/Xilinx/Resource/Reference Material/ad/10G Ethernet UDPIP 协议栈规格书.pdf` | p.1（纯 RTL、无 AXI4-Lite、单时钟域）、p.3（`mac_tx_valid/ready`；`m_udp_rx_tvalid/tkeep/tlast/tuser` 端口表） | 1.1 / 1.4 |
| 《Lanczos 各向异性缩放 IP 规格书》（另一支图像缩放 IP 的自述件，20 页） | `D:/Xilinx/Resource/Reference Material/ad/lanczos_ip_spec.pdf` | p.2（流式架构、line buffer + 6-line ring buffer）、p.4（按灰度/RGB 列 LUT/DSP/RAMB36 与 WNS/WHS/Fmax） | 3.5 |
| UG835《Vivado Design Suite Tcl Commands》 | `D:/Xilinx/Resource/ZYNQ7020/MLK_demo/04_example_HLS_Image/HLS参考资料/ug835-vivado-tcl-commands.pdf` | p.3（SDC 是传递时序约束的机制、Tcl 基础设施的位置）；正文**未**含"对象不存在 ⇒ 命令空转"的解释句 ⇒ 6.1 ③ 标【未核实】 | 6.1 |

本仓库内的实证件（本篇正文每一格的出处；这些不是"引用别人的结论"，是可直接打开的件）

- 时序与资源：`build/report/timing_summary.rpt`（`:44-52` 方法学、`:62-104` `check_timing`、
  `:149-154` 头条、`:164-171` 时钟清单、`:181-188` 逐域、`:192-199` 跨域两对）、
  `build/report/utilization.rpt`（`:35-40`、`:106-109`、`:121`、`:163`、`:195`、`:212`）、
  `build/report/methodology.rpt`（`:30-36`、`:63-66`）、`build/report/cdc.rpt`（`:15-25`）、
  `build/report/route_status.rpt`、`build/clock_uncertainty.rpt`（`:3-5`、`:20`、`:25`、`:78`、`:93-107`）、
  `data/metrics.csv`（`:5-8`、`:10-11`、`:17`）。
- 约束与构建：`src/constraints/rk_zynq7020.xdc`（`:36-50`、`:51-60`、`:64-75`）、
  `src/constraints/clock_groups_impl.xdc`（`:1-8`、`:13-17`、`:19-25`、`:28-31`）、
  `src/constraints/r114_io_async.xdc`（`:57-66`）、`src/constraints/r115_io_window_candidate.xdc`
  （`:7-16` 的 RTL8211F Table 60 出处，手册页 60 = PDF 第 67 页，本机件
  `D:/Xilinx/Resource/ZYNQ7020/Board_Resource/芯片手册/C187932_以太网芯片_RTL8211F-CG_规格书_REALTEK(瑞昱)以太网芯片规格书.PDF`）、
  `src/constraints/r119b_hdmi_tp1_pinclk.xdc`（`:4-8`、`:16-22`）、
  `build/tcl/build_system_axigpio.tcl`（`:31`、`:33-37`、`:54-63`、`:71-74`、`:75-81`、`:100`、`:174`、
  `:199`、`:203`）、`build/tcl/clock_uncertainty.tcl`（`:10-11`、`:29-30`）、
  `build/tcl/c2_scratch_probe.tcl`（`:33`）、`build/gates.sh`（`:64-71`、`:93-104`、`:109-131`、`:150-156`、
  `:275-279`）、`build/check_io_timing_coverage.py`、`build/uncertainty_uniform_ab.sh` +
  `build/tcl/probe_uncertainty_uniform.tcl`（后两支本次未跑，只点名）、
  `build/scan_async_reg_coverage.py` + `build/evidence/r113_async_reg_scan.txt`（本次未跑，只点名）。
- RTL 与台架：`src/rtl/eth/dc_fifo.v`、`ddr_bank_commit.v`、`snap_cross.v`、`frame_reasm.v`、
  `axi_frame_saver64.v`、`eth_udp_video_top.v`、`link_monitor.v`、`rgmii_rx.v`、`sync_fifo.v`；
  `src/rtl/axi/axi_frame_writer_gated.v`；`src/rtl/video/raw_line_delay.v`、`frame_commit_lock.v`、
  `osd_overlay.v`、`gamma_lut.v`、`frame_buffer*.v`；`src/rtl/process/rotate/rotate_mapper.v`、
  `angle_ctrl.v`、`src/rtl/process/zoom/zoom_mapper.v`、`src/rtl/process/bilin/fb_bilin.v`、
  `src/rtl/process/proc_*.v`；`src/rtl/util/src_mode.v`、`ps_publish.v`、`key_debounce.v`；
  `src/rtl/top/system_top.v`、`pl_video_top.v`；`sim/tb_writer_abort.v`、`tb_reasm_bounds.v`、
  `tb_cdc_capacity.v`、`tb_v79_abort_toggle.v`。
- 主机与 PS：`src/ps/main.c`（`:19`、`:40-46`、`:701-716`、`:1546-1547`）、
  `src/ps/sd_play.c`（`:35`、`:86-95`）、`src/ps/sd_play.h`、`src/host/README.md`；
  工具自带驱动 `vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/libsrc/standalone/src/arm/ARMv8/32bit/xil_cache.c`
  （`:455-469`、`:319-340`）、`.../libvitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/libsrc/sdps/src/xsdps.c`（`:352-357`）、
  `.../libvitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/libsrc/dmaps/src/xdmaps.c`（`:1510-1516`）；上位机
  `src/host/ddr_verify.mjs`（`:1-11`）、`src/host/ddr_stale.mjs`（`:6-11`）、
  `src/host/video_sender.py`（包形正本，见 `interface-contract.md` 第 6 节）。
- 报告与记录：`report/05-timing.md`（`:10-15`、`:24-31`、`:52-58`、`:120-132`、`:135-147`、`:155-163`）、
  `report/timing_global.md`（`:17`、`:103`、`:127-152`、`:168-170`、`:227`、`:238`、`:394-396`）、
  `report/known_issues.md`（`:725`）、`report/40-optimization.md`（`:120`）、
  `report/log/issues.md`（`:143`、`:12567-12598`）、`report/timing/debt_ledger.md`
  （`:30-31`、`:37`、`:113-126`、`:140-143`）、`report/timing/rgmii_window_model.md` §7、
  `report/command_precedence.md`、`skills/pitfalls/constraint-coverage-loss/SKILL.md`
  （`:26`、`:28-39`、`:41-50`、`:52-63`、`:89-98`、`:100-109`、`:111-121`、`:132-137`）、
  `skills/rtl/cdc-and-async-discipline/SKILL.md`（`:76-82` 反例清单）。
- 凭据件：`build/r98_201_before.txt`、`build/r98_cdc_details.txt`、`build/r87_timing_summary.rpt`、
  `build/evidence/r86_osd_t18_teeth_addr.txt`、`build/evidence/r112_util_attrib.txt`、
  `build/evidence/r115_c2_scratch/option_a_console.txt`、`build/evidence/r119_xdc_loads_probe2.txt`、
  `build/evidence/r119_xdc_loads_probe3.txt`、`build/evidence/r118_after_roster_probefmt.txt`、
  `build/evidence_r75/`（冻结件目录）。

小结 1：本表把"外部官方"与"仓库内实证"分列，凡是外部件都写了文档号、版本、日期、本机路径或 URL、
页码与核对日期（2026-10-05）；凡是本次没抓到正文的解释句都不在这张表里冒充出处，而在正文标了【未核实】。
小结 2：本目录的 `_sources.md` 由另一条流程维护，本篇不写它；这张表就是本篇的自足登记。下一步：第 9 节。

---

## 第 9 节 自测题

答案一律是"去某个文件或报告的某一列查"，不在本篇内直接给结论。

1. 你要确认"搬运机在 `abort` 期间还会继续接收 AXI 读数据"这件事是真的：
   去 `src/rtl/axi/axi_frame_writer_gated.v` 找 `m_axi_rready` 的驱动式，再看台架 `sim/tb_writer_abort.v`
   里哪三条判据（按名字找）钉住了这个行为？
2. 有人说"我们这版 hold 全绿，所以片外收口也安全"。你要用两份件证伪或证实这句话：
   打开 `build/report/timing_summary.rpt` 的 `check_timing` 段，读出 `no_input_delay` 那一行里的
   HIGH 计数；再到 `report/timing/debt_ledger.md` 找被点名的端口清单，确认它是否包含
   `eth_rx_ctl` 与 `eth_rxd`。两份件给出的答案一致吗？
3. `eth_rxc` 的 WHS 与 `clk_fpga_0` 的 WHS 能不能直接比大小？依据不在本篇：
   打开 `src/constraints/rk_zynq7020.xdc` 数 `set_clock_uncertainty` 的行数与点名对象，
   再打开 `build/clock_uncertainty.rpt` 比较 (a)(b) 两段里 `Clock Uncertainty` 这一行的有无。
4. 换了一只派生钟之后，你怎么证明"约束覆盖面没有静默缩小"？
   去 `report/log/issues.md` 的 #305 那一段，抄出它给出的四类要重查的约束名，
   再按本篇 6.3 ⑤ 的四步各写一条你要跑的命令。
5. 一段"数组读写带异步复位"的代码推不出 BRAM。要核实这句话在本工具里的**表现**（不是定义）：
   去 `src/rtl/axi/axi_frame_writer_gated.v` 与 `src/rtl/eth/axi_frame_saver64.v` 找被留下的
   综合消息号，再到 `build/report/utilization.rpt` 找哪两行能看出"降级"发生了。
6. 你想知道 PS 侧"有没有做缓存维护"，而不是"文档上说要不要做"：
   去 `src/ps/` 下 grep `Xil_DCache`，逐条判断它是在"通知硬件之前"还是"读数据之后"；
   再看官方驱动 `xsdps.c` 里的 `IsCacheCoherent` 判定，说明本工程为什么必须自己做。
7. 有人说"`report_cdc` 没有新增行，所以这次改同步器是安全的"。
   去 `src/rtl/video/frame_commit_lock.v` 找那条明写"不会体现在 `report_cdc` 里"的注释，
   按它的写法说出你要补的那一支台架与它的判据名（在 `sim/` 下）。
8. 你要向没做过 FPGA 的人解释"格雷码指针为什么够用"，但不许用任何本工程的词：
   依据本篇 2.3 的第 ① 层与第 ⑤ 层，写出你的话，并指出你在对方代码里会先看哪一行来验证它。

红项自检：本篇若出现"讲不出落点的机制"、"没有出处的解释句"、"未标注的比喻"、
或任何 `【未确认】/【未核实】/【需板上验证】` 没有配一条具体待办，都算未完成。

| 标记 | 本篇条数 | 各自对应的待办 |
|---|---|---|
| 【未确认】 | 2 条（正文出现 6 次） | ① `abort` 撤 `arvalid` 要不要立案 + 台架（1.1 ③）；② DSP 逐实例归属要不要出 `-hierarchy` 件（3.4 ②） |
| 【未核实】 | 4 条（正文出现 15 次） | 7 系列 MTBF 数值口径（2.1 ④ / 2.6 ③）；`Additional Uncertainty` 正文（4.4 ③）；SYNTH-5 规则解释句（3.5 ③）；XDC"对象取不到 ⇒ 命令空转"的官方条款（6.1 ③、6.2 ③ 共用同一条缺口） |
| 【需板上验证】 | 2 条（正文出现 7 次） | 四域统一 0.800 之后的板侧 hold 真值（4.4 ⑤，正本 `report/timing_global.md:103` 末句）；注释掉 `main.c:714` 后的屏与串口对照（5.2 ②） |

