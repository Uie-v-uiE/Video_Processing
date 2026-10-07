# glossary.md · 术语与缩写（五层阶梯）

读完这篇你能回答哪三个问题：

1. 本目录里出现过的核心名词，**它到底是什么、它不是什么、拿到陌生代码怎么认出它**？
2. 哪些"简化说法"会在什么情形下误导我？
3. 还有哪些词只是就地解释过、尚未收进本表（→ 本表第 3 节列出，别把本表当已收全）？

## 目录

- 第 1 节 阶梯的读法
- 第 2 节 词条（53 条，每条五层；第 1~24 条为前一批，第 25~53 条按 2026-10-05 两轮回述测试点名的断点补）
- 第 3 节 本表**未收全**清单（W14 红项，逐条列出）
- 第 4 节 自测题

## 第 1 节 阶梯的读法

每个词条五层：**① 零术语版**（允许不严谨，但必须紧跟一句"会在什么情形误导你"）
→ **② 它解决什么问题**（写现象不写定义）→ **③ 精确定义 + 出处** → **④ 它不是什么**
（并指出我们工程里哪一处能观察出差别）→ **⑤ 辨认方法**（打开 X，看 Y，出现 Z 就是它）。

第 3 层凡是"通用原理"口径的，只给两种出处：**本仓库里我打开过的文件**，或**我这次真的抓到的规范/文档**。
本次尝试抓取两份外部出处**均失败**（Wikipedia 的 metastability 页取不到；Arm 的 IHI 0022 页面重定向后
只返回站点配置），所以本表所有第 3 层都退到"仓库内的口径"，并在需要规范号的地方标 `【未核实】`。
这条事实也记在 `_sources.md` 与 `_progress.md`。

第 25~53 条（2026-10-05 补）的第 3 层多可用一类出处：**本机磁盘上的官方手册**，一律写全
「文件名 + 用 pypdf 取到的页序 + 该页能核对到的句子 + 核对日期」，路径都在 `D:/Xilinx/Resource/` 下面；
`docs.amd.com` 与 Wikipedia 本轮仍未取到正文，因此凡需要**规范条号/章节号**的地方照旧写
`【未核实·正文未取到】` 并附检索词，不许把条号当已核实念。
每条开头另起一行 **正文首见**：格式是「篇名 + 节号 + 行号」，节按 `README.md` 第 3 节路径 A 的先后数
（`README.md` → `prerequisites.md` → `system-overview.md` → 本表 → `myths.md` → `subsystem-map.md` →
`one-pass-walk.md` → `code-reading.md` → `mechanics.md` → `interface-contract.md` → `clocking-and-reset.md` →
`design-choices.md` → `hands-on.md` → `next-layer.md`）；这一行的作用是给 W14 一个可复查的落点 ——
表里每条都能在正文里找到用它的那一行，找不到就不该收进表。

小结 1：本表不是词典，是"每个名词走满五层"的检查表；某层空着就是这一条没写完。
小结 2：第 3 节是本表的诚实部分 —— 它说明本表**目前**没覆盖哪些正文用过的词。下一步：第 2 节。

## 第 2 节 词条

### 1. 时钟域（clock domain）

① 一套电路各自按自己的节拍走，同一块芯片上可以有好几种节拍，每种就是一个"域"。
*简化说法，会在"两个域频率相同但不同树"的情形下误导你（本设计里 `sys_clk` 与 `clk_pix` 同频不同树），精确版见第 3 层。*
② 不区分域会看到：仿真全绿、板子上某些位偶发错。本仓库的实物现象记录在
`src/rtl/top/pl_video_top.v:478-481`（同一个信号在四处被裸采、在另一处走了三级同步，"一处对一处错"）。
③ 口径：本工程把"域"等同于约束里能被 `get_clocks` 取到的那个对象；四个主域的产生者与消费者列在
`clocking-and-reset.md` 第 1 节。规范级定义 `【未核实】`（本次没抓到外部文档）。
④ 它不是"频率"。`clk_pix` 与 `sys_clk` 都是 50 MHz 却是两个域；`eth_rxc` 与 `gmii_tx_clk` 是同一个域
（`src/rtl/eth/gmii_to_rgmii.v:25` 把 TX 直接等于 RX）。
⑤ 辨认方法：打开 `build/timing_summary.rpt` 的 Clock Summary 段，一行一个时钟名 = 一个域；
在代码里则看 `always @(posedge …)` 后面跟的是哪个名字。

### 2. 跨时钟域（CDC, clock domain crossing）

① 一个域产生的数要被另一个域用，中间必须安排"交接"，不能直接连。
*简化说法，会在"我只传一根长期不变的开关线"的情形下误导你 —— 那种也要安排，只是形式最省。*
② 不安排会看到：某一位读到半新半旧、或整排数里几位来自上一轮。本仓库的落点：
`src/rtl/top/pl_video_top.v:649`（"19 位各自打两拍 ⇒ 读到半新一半旧"）。
③ 本工程的三条硬口径：跨域只准过 FIFO 格雷码指针、翻转 + 3 级、或准静态总线 + 沿
（`src/rtl/eth/eth_udp_video_top.v:5-6` 的声明、`src/constraints/clock_groups_impl.xdc:19-23` 的"结构保证"段）。
④ 它不是"时序余量不够"。CDC 是**结构**问题：`src/rtl/eth/eth_udp_video_top.v:378` 就写明
"判据是结构判据，台架判不了这一条：RTL 仿真没有门延迟"。
⑤ 辨认方法：`build/cdc.rpt` 里出现"源>目的"的 Critical 行就是它；门禁按配对集合判，
读法在 `build/gates.sh:99-100`。

### 3. 亚稳态（metastability）

① 采样时刻正好卡在数据在变的瞬间，触发器会短暂"既不是 0 也不是 1"，多打两拍就是给它时间 settle。
*简化说法，会在"多打两拍就万无一失"的情形下误导你 —— 它只把概率压低，不消除；规范口径本次 `【未核实】`。*
② 不处理会看到：同一个 lane 两次读出不同的模式高位。本仓库登记过的实物症状：
`src/rtl/top/system_top.v:224-226`（名字对得上、宽度被吞 ⇒ 读出来永远 0/1）。
③ 本工程的处理形式只有三种（第 5、6、7 条），没有第四种；每种都带工具属性或结构约束。
④ 它不是"信号有毛刺"。毛刺来自组合逻辑，亚稳来自采样沿与数据沿相遇；
两者在本工程可分别观察：毛刺那条的原文在 `src/rtl/eth/eth_udp_video_top.v:373-380`
（`|s_pkts` 的组合或缩被跨域采走 ⇒ 假"链路掉"）。
⑤ 辨认方法：`build/cdc_details.rpt`（带寄存器名的清单，入口 `build/tcl/cdc_who.tcl`，
口径见 `skills/rtl/cdc-and-async-discipline/SKILL.md` 第 3 步）里出现"没有 ASYNC_REG 的捕获寄存器"就是它。

### 4. 三级同步器 / 打拍

① 让新时钟连续看三眼，看稳了才用。
*简化说法，会在"看的是脉冲"的情形下误导你 —— 一眼宽的电平脉冲会被三眼看没了，见第 6 条。*
② 不打拍会看到：`src/rtl/top/pl_video_top.v:556-558` 记的那处真错 —— 帧起始那拍采了未同步的电平。
③ 本工程的实际取值：**三级**，且第三级专门给"异拍出沿"或"再采一次"用
（形状：`src/rtl/util/ps_publish.v:17-25`、`src/rtl/top/pl_video_top.v:491-496`）。为什么是三级不是两级，
仓库内的解释在 `src/rtl/util/ps_publish.v:17` 那一句。
④ 它不是握手。握手要有"对面收好了"的回线，这里没有；所以只适用于允许合并的准静态值
（对照 `src/rtl/eth/link_monitor.v:168-170` 的 `pend_ev`：总线不承诺每次都到）。
⑤ 辨认方法：搜 `(* ASYNC_REG = "TRUE" *)`，看到 `{a2,a1,a0} <= {a1,a0,in}` 就是它。

### 5. `ASYNC_REG`（工具的异步寄存器属性）

① 一句注释式的标记，告诉综合与布局布线"这几颗是跨域捕获用的，别乱动它们"。
*简化说法，会在"我以为标了就等于安全"的情形下误导你 —— 它只约束物理放置，不改变逻辑。*
② 不标会看到：工具把这些触发器当普通寄存器挪位或复制。仓库内口径：
`src/rtl/eth/dc_fifo.v:23-27`（"不打属性工具可以挪位、复制……亚稳态传播窗口就没保证"）。
③ 本工程用法：整条链一起标（含源域那一级），理由写在同一段注释里。工具对"缺属性"的检查号
是 `report_methodology` 的 TIMING-10，本仓库实测记 1 条（`report/timing_global.md` 第 4 节表）。
④ 它不是"约束"。它不改变时序要求，只限制放置；对照：`set_clock_groups` 才是时序侧的（第 12 条）。
⑤ 辨认方法：`report_methodology` 里 TIMING-10 的正文；⚠ 本仓库登记过一条反例：
加了属性那条计数也没降（`report/timing_global.md` 第 4 节 `TIMING-9/TIMING-10` 那一行）⇒
**不能拿计数当"标没标上"的代理**，要标没标要看网表。

### 6. 翻转位（toggle）/ 脉冲跨域

① 要传"发生了一次"，就拧一下一根线，对面看它变没变。
*简化说法，会在"两次事件挤在同一段时间里"的情形下误导你 —— 会被并成 0 次（边界见
`src/rtl/video/frame_commit_lock.v:26-28`）。*
② 不用它而直接采脉冲会看到：事件整个消失。原文：`src/rtl/util/ps_publish.v:2-5`、
`src/rtl/eth/snap_cross.v:2-5` 的契约、`src/rtl/video/frame_commit_lock.v:100-105`（"电平型 3 级同步在这里并不能修好它，实测与裸采逐相位一模一样"）。
③ 形状：源域 `if (evt) tgl <= ~tgl`；目的域三级 + 末两级异或（`src/rtl/eth/ddr_bank_commit.v:37-47`）。
④ 它不是计数器，也不保证"每一次都到"。区别的可观察处：`src/rtl/util/ps_publish.v:6-8` 明写合并是有意的。
⑤ 辨认方法：搜 `<= ~` 与 `^ `（异或）成对出现的四行；判据台架 `sim/tb_v79_abort_toggle.v`（相位扫描）。

### 7. 格雷码（Gray code）/ 异步 FIFO 指针

① 一种相邻两数只差一位的二进制编码，用来跨域传"数到几了"不会读到半新半旧。
*简化说法，会在"我要传的数每拍都可能大改"的情形下误导你 —— 格雷码只救"相邻变化"的量。*
② 不用它会看到：满/空判断读到多个位一起变的中间态。本工程指针位宽与判据都在
`src/rtl/eth/dc_fifo.v:35-47`。
③ 口径：二进制指针不跨域，只传格雷码版本，各在对方域打两拍（`src/rtl/eth/dc_fifo.v:81-95`）。
④ 它不是"握手"。它没有回线，靠"保守判定"保证安全：宁可多判一次满/空。
⑤ 辨认方法：模块里有 `bin2gray` 函数与 `*_s0/*_s1` 两级链（`src/rtl/eth/dc_fifo.v:27-32`）。

### 8. 准静态总线 + 跳变沿（`snap_cross` 形态）

① 先把一整排数站住，再拧小旗；对面看到小旗才抄，抄到的一定是整套。
*简化说法，会在"源域写得太频繁"的情形下误导你 —— 小旗到了但数还在变，就抄到半成品。*
② 不这么做会看到：读到半新一半旧的档位号（`src/rtl/top/pl_video_top.v:649`）。
③ 契约原文：`src/rtl/eth/snap_cross.v:2-5`；节流要求（两次写入之间留出 `SETTLE` 个源周期）在
`src/rtl/eth/link_monitor.v:165-166`。
④ 它不是原子读。它只是"读的时候一定完整"，不保证"读到最新的" —— 所以配了心跳两位（第 9 条）。
⑤ 辨认方法：代码里 `snap_cross #(.W(…))` 的例化；当前树里共 4 处
（`src/rtl/top/system_top.v:214`、`src/rtl/top/pl_video_top.v:674`、`:876`、`:980`）。
`src/rtl/eth/snap_cross.v:20-28` 那段注释提到 `pl_demo_top` 那棵**未进位流**的树，
但当前 `pl_demo_top.v` 里 grep 不到 `snap_cross` 例化 ⇒ 那句话讲的是历史形态，不要按"第 5 处"去找。

### 9. 心跳（heartbeat）与"源时基准不准"

① 除了传数，还定期拧一根"我还在跑"的线；对面发现它不拧了，就知道手上的数是旧的。
*简化说法，会在"心跳还在但变慢了"的情形下误导你 —— 本工程专门加了一位 `hb_slow` 管这件事。*
② 没有它会看到：拔线之后仲裁死死占住 ETH。物理事实与后果写在
`src/rtl/top/system_top.v:249-256` 与 `src/rtl/eth/snap_cross.v:6-7`。
③ 实际取值：`HB_TO_MS` 200（链路快照与 lane23）与 1000（时延那一口），慢判据 `SLOW_MS` 200
（`src/rtl/top/pl_video_top.v:674`、`:980`）。
④ 它不是看门狗复位。看门狗会打断动作（第 10 条），心跳只给数打上"可信/不可信"标签。
⑤ 辨认方法：`snap_cross` 输出端的 `hb_gone`/`hb_slow` 两位；lane31 就是把它们送到 PS（
`src/rtl/top/system_top.v:238`）。

### 10. 看门狗（timeout / abort）

① 一件事太久没完成就强行打断它，并且把"被打断"这件事说出去。
*简化说法，会在"我以为打断就干净了"的情形下误导你 —— 在途的 AXI 突发要先排空
（`src/rtl/axi/axi_frame_writer_gated.v:69-75`）。*
② 没有它会看到：一次卡住的拷贝永久占住搬运机。预算：20 ms = 2_000_000 拍
（`src/rtl/video/frame_commit_lock.v:8`、`:88-98`）。
③ 本工程的暴露方式：`copy_abort` 一拍 + `abort_tgl` 翻转，像素域清掉 `eth_has_frame`
（`src/rtl/top/pl_video_top.v:531`）。
④ 它不是重试。它只是放弃这一帧并说明原因；`src/rtl/video/frame_commit_lock.v:26-28` 那一段就是
"两次 abort 至少隔 WD_CYC"的节拍约束。
⑤ 辨认方法：找 `wd_cnt`/`arm`/`abort` 三个名字成组出现的地方。

### 11. 建立时间 / 保持时间 / 时序裕量（WNS / WHS）

① 数据必须"提前一点到、并且别太早变"，工具量出这两个余量，最小的那两个就是 WNS 与 WHS。
*简化说法，会在"我把余量当实际延迟"的情形下误导你 —— 裕量是"离违规还差多少"，不是"花了多久"。*
② 不看它会看到：改了一处代码，全局 WNS 从 0.918 变成 0.314，而那块改动与它无关。
本仓库的实测记录：同一套约束三次构建 WNS = 0.918 / 0.807 / 0.314
（`build/gates.sh:271-277` 那段），所以门禁额外打印**分组最差**。
③ 本项目取值：全局 setup WNS 0.739 ns、hold WHS 0.052 ns、失败端点 0 / 51135
（`data/metrics.csv` 第 5~7 行，出处 `build/timing_summary.rpt`）。
④ 它不是"实际延迟"，也不是"跨域安全"。可观察的差别：`src/rtl/eth/eth_udp_video_top.v:373-380`
那条 CDC 修法**不体现在时序报告里**，而 WNS 变动全在报告里。
⑤ 辨认方法：`build/timing_summary.rpt` 的 Design Timing Summary 第一行数据五列
（门禁的解析式在 `build/gates.sh:68-70`）；**读不到那行时脚本会把候选行原样打出来**（同文件 `:71-75`）。

### 12. 异步时钟组（`set_clock_groups`）

① 告诉工具"这两拍子毫无关系，别去算它们之间的时序"。
*简化说法，会在"我以为不算就是安全"的情形下误导你 —— 不算是把安全责任交给结构（第 2、4~7 条）。*
② 不声明会看到：历史上 `clk_pix` 被当成独立时钟与 `eth_rxc` 做 setup 分析，报出 WNS≈−6.7 的假违例
（原文：`src/constraints/clock_groups_impl.xdc:13-17`）。
③ 本工程取值：三组，`sys_clk` 那组带 `-include_generated_clocks`（同文件 `:28-31`）。
④ 它不是"false path"。false path 是对具体端口的豁免
（`src/constraints/rk_zynq7020.xdc:55-60`），组声明是整个域之间不分析。
⑤ 辨认方法：综合日志里若出现 `CRITICAL WARNING [Vivado 12-4739] set_clock_groups: No valid object(s)`
⇒ 这条约束**整条没生效**（后果与拆文件的修法：`src/constraints/rk_zynq7020.xdc:64-75`）。

### 13. 时钟不确定度（`set_clock_uncertainty`）

① 自己往检查里加的一笔"我不确定"，相当于把判据收紧。
*简化说法，会在"我以为加过就是所有域都加过"的情形下误导你 —— 本工程只加了一个域。*
② 不加会看到：工具认为 0.05 ns 的 hold 余量够用；加了之后同一族可能变负。
仓库内的实测口径：`report/timing_global.md` 第 4 节"自加不确定度"那一行
（统一给 0.800 之后 WHS −0.747 / 25,742 个失败端点，**本轮未采纳**）。
③ 本项目取值：只有一行 `set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]`
（`src/constraints/rk_zynq7020.xdc:50`）。
④ 它不是时钟抖动/偏斜的测量值，是人为预算。可观察处：带它那条路径的报告里会写
`clock uncertainty 0.800`（口径见 `board/README.md` 第 17-19 行那段两把尺子的说明）。
⑤ 辨认方法：`build/clock_uncertainty.rpt`（本仓库为这件事单独产的一份件，`build/tcl/clock_uncertainty.tcl` 是它的入口）。

### 14. BRAM / 分布式 RAM / LUTRAM（存储推断）

① 同样一段"数组读写"的 Verilog，工具可能用块存储、也可能用查找表搭，代价完全不同。
*简化说法，会在"我以为写法无所谓"的情形下误导你 —— 一个复位分支就能让它退化成触发器。*
② 退化会看到什么：本仓库有实测记录 —— skid 缓冲原先把读写放在带异步复位的控制块里，
综合报 `Synth 8-4767`，64×83 bit 全掉进触发器（约占整机剩余寄存器的一半），
改成已验证的分布式 RAM 写法才解决（原文：`src/rtl/axi/axi_frame_writer_gated.v:50-54`）。
③ 本工程取值：显式写 `ram_style`，块存储用于 CDC（`src/rtl/eth/dc_fifo.v:20`）与帧缓存
（`src/rtl/video/frame_buffer.v:20` 那份遗留件的写法；现役是 `frame_buffer_w64`，
例化处 `src/rtl/process/bilin/fb_bilin.v:65`），分布式用于 skid。
④ 它不是"片外内存"。DDR 是另一件事（第 15 条）。可观察差别：`build/utilization.rpt` 的
Block RAM Tile 那一行 —— 当前读数 95.5 / 140（`data/metrics.csv` 第 10 行）。
⑤ 辨认方法：综合日志里看 `Synth 8-4767` / `8-7137` 这类号；`report_methodology` 的
SYNTH-5 / SYNTH-6 计数就是"因为约束才映射成分布式 RAM"（读数 336 / 98，
`report/timing_global.md` 第 4 节表）。

### 15. 乒乓 bank（双缓冲）

① 两块内存轮流用：一块在被写，另一块在被读，写完提交再交换角色。
*简化说法，会在"我以为交换角色不需要等"的情形下误导你 —— 必须等前一块的尾巴真的落位。*
② 不等会看到：帧尾 4 字节被写进下一帧的 bank，屏上右下角少 2 个像素
（原文：`src/rtl/eth/ddr_bank_commit.v:6-7`）。
③ 本项目取值：`BANK0 = 0x1000_0000`、`BANK1 = +512 KB`（`src/rtl/eth/eth_udp_video_top.v:67-68`），
第三块给 PS 片源（`src/rtl/top/system_top.v:144`）。
④ 它不是流水线，也不是仲裁。第 3 块 bank 存在的原因就是"仲裁管不到谁写 DDR"
（`src/rtl/top/pl_video_top.v:14-15`）。
⑤ 辨认方法：看 `completed_base` 与 `sav_base` 是不是两个不同的量
（`src/rtl/eth/ddr_bank_commit.v:21`、`:31`）。

### 16. 行缓存 / 行延迟环（`raw_line_delay`）

① 想把画面整体晚几行，就用一整圈按行编号的小内存，不必真的等几行。
*简化说法，会在"我以为晚几行 = 晚几个像素"的情形下误导你 —— 晚的是显示行，长度必须取链子的行数。*
② 不这么做会看到：缝两侧不是同一行画面，或者要第二个读口（实测把 BRAM 从 80 块顶到 160 块，
`src/rtl/top/pl_video_top.v:775-779`）。
③ 本项目取值：`LINES` 的唯一合法出处是 `u_pipe.OFF_LINES`（`src/rtl/top/pl_video_top.v:781`），
数据宽度 17 位（像素 + 越界标签同一条环，`:785-788`）。
④ 它不是效果链里的行缓存（那是 3×3 窗口用的），两条线不同。可观察差别在 `:776-780` 那段。
⑤ 辨认方法：模块名带 `line` / `ring`，端口有 `de/x/y` 进、`d_out/de_out` 出
（`src/rtl/top/pl_video_top.v:788` 的例化形状）。

### 17. 消隐（blanking）/ `de` / `vsync` / `frame_start`

① 电子扫描画完一行/一帧后要"回到开头"，那段不画像素的时间就是消隐；有效像素用一根 `de` 表示。
*简化说法，会在"我以为消隐是浪费"的情形下误导你 —— 本工程把整帧搬运塞进消隐里做。*
② 不懂它会看到：为什么换帧只能发生在特定几十微秒内（窗口预算 67200 个 AXI 拍，
`src/rtl/top/pl_video_top.v:446`）。
③ 本项目取值：1024+44+88+188 = 1344、600+3+6+16 = 625（`src/rtl/video/video_timing_1024x600.v:3-4`），
`frame_start` 落在**第一个有效像素**那一拍（`src/rtl/video/video_timing.v:68`）。
④ `de` 不是 `vsync`。`vsync` 是场同步脉冲、`de` 才是"这一拍有像素"；两者极性分别由
`H_POL/V_POL` 决定（`src/rtl/video/video_timing.v:65-67`）。
⑤ 辨认方法：看时序生成器的四个参数段；报告侧看 `clk_pix` 域路径里 `u_t` 相关端点。

### 18. 位宽截断（"名字对、宽度被吞"）

① 把一排数接到一根更细的线上，工具不报错，只是把高的几位丢掉。
*简化说法，会在"我以为报错才算错"的情形下误导你 —— 它只给一条 warning，甚至什么都不给。*
② 实际发生过的现象：`dbg_src` 声明成 `[5:0]` 接 8 位端口 ⇒ 模式高位静默丢掉，
TEST(10) 读起来像自动(00)、SD(11) 像 ETH(01)（原文：`src/rtl/top/system_top.v:224-226`）。
③ 本工程的修法：位宽判据进门禁第 14 项（`build/gates.sh:247-260`），尺子自己有反例。
④ 它不是 CDC 问题。它一次事件都不涉及，纯静态；可观察差别在第 3 节那条 lane30 读数。
⑤ 辨认方法：综合日志找 `Synth 8-689`（同文件 `:198-219` 就是这条判据）。

### 19. 饱和 / 回卷 / 粘滞（三种"计数器的品德"）

① 数到顶继续涨会绕回 0（坏）；钉在顶不动（饱和，本工程选它）；一位置了就不清（粘滞）。
*简化说法，会在"我以为钉住就是丢信息"的情形下误导你 —— 仪表读数宁可说"至少这么多"。*
② 用回卷会看到：`gap_max` 被一次长空闲永久污染、之后更大的间隔读起来反而更小
（原文：`src/rtl/eth/link_monitor.v:50-51`、`:88-92`）。
③ 本项目取值：16 位字段越过 0xFFFF 钉住（`src/rtl/eth/link_monitor.v:90-92`）；
`copy_overrun` 与 `stall_ms` 是两种不同品德（粘滞 vs 递增饱和，
`src/rtl/top/pl_video_top.v:447-452`、`src/rtl/eth/link_monitor.v:151`）。
④ 粘滞位不是锁存器。区别：`src/rtl/top/pl_video_top.v:580-585` 那段就是"两位只置不清"造成的病
（拔卡后永久冻帧）⇒ 本工程把它换成了活判据。
⑤ 辨认方法：看赋值条件里有没有 `!= 16'hFFFF` 或 `> 32'h0000FFFF`；找"只置不清"就看有没有对应的清零分支。

### 20. 仲裁（arbiter）与互锁

① 一台设备两个主人抢，规矩由第三方定：谁活着 + 现在能不能安全换手。
*简化说法，会在"我以为谁有数据归谁"的情形下误导你 —— 那正是被消灭的老写法。*
② 老写法会看到：拔网线后 SD 片源永远接不回屏幕（`src/rtl/util/src_arb.v:4-8`）。
③ 本项目取值：只在两个引擎都空闲时换手；让给 PS 前再静默 20 ms（`:48`、`:67-75`、
`src/rtl/top/pl_video_top.v:421`）。
④ 它不是优先级编码器。区别的可观察处：手动锁**只改谁想要总线，不改什么时候能换手**
（`src/rtl/util/src_arb.v:41-43`）。
⑤ 辨认方法：找 `both_idle`、`quiet >= T_OFF_CYC` 这两个形状。

### 21. 反压（backpressure）

① 下游装不下了，让上游"先别取"，而不是取出来丢掉。
*简化说法，会在"我以为反压会自动往上传"的情形下误导你 —— 本工程只有一级，再上游靠丢字计数兜底。*
② 不反压会看到："取出来就丢，等于白读"（原文：`src/rtl/eth/eth_udp_video_top.v:353`）。
③ 本项目取值：`fifo_rd <= !fifo_empty && !sv_full`（同文件 `:312`）。
④ 它不是流控协议。这里没有任何东西通知上位机降速；可观察差别：丢了字只体现在 lane0。
⑤ 辨认方法：找 `*_full` 被用来门住 `rd_en`/`wr_en` 的那一行。

### 22. AXI 突发（burst）与通道独立性

① 一次说"我要连着读 N 个字"，地址由从机自己递增；读、写、响应是三条独立的通道。
*简化说法，会在"我以为 AR 发了数据就来"的情形下误导你 —— 中间可以任意拖，且要认 `rlast`。*
② 不懂会看到：为什么本工程里 AR 只在消隐窗口发、`rready` 在 abort 后不许撤回
（`src/rtl/axi/axi_frame_writer_gated.v:69-75`、`:45-47`）。
③ 本项目取值：`arsize = 8 字节`、`arburst = INCR`（`:37-38`），16 拍一个突发、4 个突发在途（`:40-47`）。
规范级口径（VALID/READY 独立性）本次 `【未核实】`：我尝试抓 Arm IHI 0022 未拿到正文，见 `_sources.md`。
④ 它不是 DMA 描述符链。可观察处：写侧 `bid`/`bresp` 悬空 ⇒ 这里根本没有错误回报通道
（`src/rtl/top/system_top.v:99`）。
⑤ 辨认方法：端口名前缀 `aw/w/b` 与 `ar/r` 分成两组；`*_len`、`*_size`、`*_burst` 三兄弟同时出现。

### 23. 逆映射与双线性插值

① 想知道屏幕上这格来自原图哪儿，就反着算回去；落在四个像素中间就按距离加权取平均。
*简化说法，会在"我以为插值只是画质问题"的情形下误导你 —— 它同时改变了"什么时候能算出这一格"的节拍。*
② 不做逆映射会看到：放大出现空洞、旋转出现缝；本项目的读口节拍是"每个源像素用满它天然的 4 个
50 MHz 拍"（`src/rtl/top/pl_video_top.v:721-725`）。
③ 本项目取值：`bilin_en` 可运行时切换、关掉时逐位等于最近邻
（`src/rtl/top/system_top.v:286` → `src/rtl/top/pl_video_top.v:254-262`）；
行方向额外晚一整对 ⇒ 顶层用 `BILIN_ROWS = 2` 抵掉（`:250`）。
④ 它不是缩放档位表。档位在 `zoom_ctrl`，插值在 `fb_bilin`；两者可从 lane23 分别读出
（`src/rtl/top/pl_video_top.v:679-688`）。
⑤ 辨认方法：找 `frac_x/frac_y`（小数权重）与 `oob`（越界）成对出现的端口。

### 24. 定点数与"不做除法"

① 用整数表示小数（把 1.00 倍写成 256），乘完之后移位；除一个不是 2 的幂的数，硬件里很贵。
*简化说法，会在"我以为只是省一点资源"的情形下误导你 —— 它会直接破坏时序。*
② 做了除法会看到：本仓库的实测账 —— 在 100 MHz 域把拍数除以 100，综合架出组合除法器，
WNS −5.014、96 个失败端点（原文：`src/rtl/top/pl_video_top.v:621-623`）。
③ 本项目取值：倍率是 10 位反比例 `inv_scale`（`src/rtl/top/pl_video_top.v:316-334`）；
行号取模用一次减法而不是除法（`:282-284`）；换算全部推给上位机的一个常量（`:71`）。
④ 它不是浮点。可观察差别：`data/metrics.csv` 第 25 行给的是 ms 的 min/avg/max，
而 PL 里从头到尾只有拍数。
⑤ 辨认方法：看名字里的 `inv_`、`frac_`、`_x100`；看是否出现"除以非 2 的幂"——本工程的规矩是不出现。

### 25. HP0（PS 侧的高性能从端口，`S_AXI_HP0`）

**正文首见**：`myths.md` 第 2 节 第 67 行；另见 `subsystem-map.md` 第 2 节 第 40 行、`one-pass-walk.md` 第 5 站 第 109 行。

① 板上那片大内存（本目录一律写 DDR，指芯片外面的内存，不是 CPU 里的高速缓存）挂在 PS 里；
PL 想把整帧数据倒进去，必须走 PS 专门为"大量搬数据"留的那扇门，这扇门编号 0，名字写作 HP0。
（"门"是比喻，不是实现；实现见 `build/tcl/build_system_axigpio.tcl:198-199` 与 `src/rtl/top/system_top.v:88-103`。）
*简化说法，会在"以为这扇门自己存数据"的情形下误导你 —— 它是通道不是存储，帧落在 DDR 里，精确版见下一层。*
② 不走它会看到：PL 没有任何一条路能把像素写进片外内存（本工程唯一的写手 `u_saver` 就是接在这扇门上）。
反过来，独占它也会看到现象：`src/rtl/eth/eth_udp_video_top.v:296-297` 原话记下"显示拷贝独占 HP0 一整个 V-blank"
⇒ 为此收侧才必须摆一块 8192 深的 FIFO，否则单包就能灌满并丢数据（`one-pass-walk.md` 第 5 站）。
③ 口径：HP = High Performance port，`S_AXI_HP0` 方向是 **Master = PL、Slave = PS**，
描述为"带读写 FIFO、在 DDR 控制器上有两个专用内存口、并有一条路通往 OCM"，这类口也称作 AFI
（出处：本机 `ug585-Zynq-7000-TRM.pdf` 第 56 页 Table 2-6 *PL AXI Interfaces*，核对日期 2026-10-05）。
本项目取值：`build/tcl/build_system_axigpio.tcl:100`（`PCW_USE_S_AXI_HP0 {1}` + `PCW_S_AXI_HP0_DATA_WIDTH {64}`）、
连线在同文件 `:198-199`（`axi_mem_intercon/M00_AXI` → `processing_system7_0/S_AXI_HP0`）。
④ 它不是 GP0（第 26 条：那是 PS 主动去按 PL 里小开关的细门），也不是 DDR 颗粒本身。
可观察的差别：HP0 这侧有按 aw/w/b/ar/r 排开的一整批端口且数据宽 64 位（`src/rtl/top/system_top.v:88-103`、
`src/rtl/axi/axi_frame_writer_gated.v:37-38` 的 `arsize = 8 字节`），GP0 侧只有 32 位寄存器写、没有突发（第 28 条）。
⑤ 辨认方法：打开 `src/rtl/top/system_top.v`，在 `design_1_wrapper` 那次例化里看到一批以 `M_AXI_HP0_` 开头、
分五组排列的端口就是它（`:88` 起）；注意同一扇门在两侧名字不同 —— BD 脚本里写的是 `S_AXI_HP0`（`build/tcl/build_system_axigpio.tcl:199`）。

### 26. GP0（PS 侧的通用主端口，`M_AXI_GP0`）

**正文首见**：`subsystem-map.md` 第 3 节 第 77 行；另见 `next-layer.md` 第 2 节 第 79 行。

① PS 里那颗 CPU 想伸手去拨 PL 侧的小开关（一个 32 位的寄存器）时走的那根细线，编号 0，叫 GP0。
（"拨开关"与"细线"是比喻，不是实现；实现见 `build/tcl/build_system_axigpio.tcl:190-197` 与 `src/ps/main.c:219`。）
*简化说法，会在"以为拨开关也得走大内存那条路"的情形下误导你 —— 控制线与控制线走 GP0，
成批的像素走 HP0，精确版见下一层。*
② 不知道它存在会看到：固件里 `Xil_Out32(0x41200000, v)` 那一句没有归宿 ——
读者会以为写的是内存，其实那串地址落在 PS 通向外设的那一大段窗口里，对面是 PL 里一只 GPIO（第 28 条）。
现象层面的代价写在 `interface-contract.md` 第 2 节 小结 2：地址是硬编码的，"写了没反应"要先怀疑地址。
③ 口径：GP = General Purpose，`M_AXI_GP0` 方向是 **Master = PS、Slave = PL**
（本机 `ug585-Zynq-7000-TRM.pdf` 第 56 页 Table 2-6，核对日期 2026-10-05）；
同文件第 113 页那张系统存储图里，`4000_0000`–`7FFF_FFFF` 那段标着 "General Purpose Port #0 to the PL, `M_AXI_GP0`"
⇒ 三只 GPIO 的 `0x41200000/0x41210000/0x41220000` 都在这段里。
本项目取值：`build/tcl/build_system_axigpio.tcl:99`（`PCW_USE_M_AXI_GP0 {1}`）、`:190-197`（GP0 串到互联、
再分三只 `axi_gpio` 的 `S_AXI`）、`:244-246`（三个基址钉死）。
④ 它不是 HP0（第 25 条），也不是中断线 —— 三只 GPIO 的 `C_INTERRUPT_PRESENT` 全是 0（`interface-contract.md` 第 7 节 第 185 行）。
可观察的差别：`src/rtl/top/system_top.v:84-87` 里 GPIO 只有 `GPIO_0_tri_o`/`GPIO_1_tri_i` 这种一根线一组的方向口，
没有 aw/w/b/ar/r 那五组。
⑤ 辨认方法：打开固件里写寄存器的那一句（`src/ps/main.c:219`、`:223` 的 `Xil_Out32`），
它写的地址在 `0x4000_0000`–`0x7FFF_FFFF` 段内 ⇒ 这一次访问走的就是 GP0；HP0 上没有 `Xil_Out32`。

### 27. BD（Block Design，"把现成模块摆成一张图"这件事）

**正文首见**：`clocking-and-reset.md` 第 1 节 第 28 行（缩写首次当名词用）；
全称 *Block Design* 首见 `subsystem-map.md` 第 2 节 第 40 行。

① 芯片里那一大堆现成件（PS 那颗 CPU、GPIO、总线之间的转接件）不必手写 Verilog 去连，
可以在工具的一张图上摆好、连线、填参数，然后让工具把这份连线**生成**成一只 Verilog 模块 —— 这张图就叫 BD。
*简化说法，会在"以为生成出来的那份 .v 还能进去改"的情形下误导你 —— 改不动，
下一次重新生成会盖掉，精确版见下一层。*
② 不知道有这回事会看到：顶层例化了一只 `design_1_wrapper`（`src/rtl/top/system_top.v:75`），
但在 `src/rtl/` 里 grep 不到它的 `module` 声明，像是凭空多出来一只模块；
`subsystem-map.md` 第 3 节 第 77 行对这件事的口径是"本工程不手写它的内部，只按端口对账"。
③ 本工程里这件事的全部落点（核对日期 2026-10-05）：
`build/tcl/build_system_axigpio.tcl:84`（`create_bd_design design_1`）、`:85`（往图里放 PS7 那只 IP）、
`:279`（`make_wrapper -files [get_files design_1.bd] -top`，生成 wrapper）、`:278`（只建图就跑路的出口 `BD_ONLY_DONE`）。
工具手册（Vivado 的 Block Design 章节）本次未抓到正文 ⇒ `【未核实·正文未取到】`，
检索词：`Vivado2025.2 UG994 Designing IP Integrator Block Designs`、`make_wrapper design_1.bd`。
④ 它不是那只 IP 本身（IP 是被摆进去的零件），也不是 RTL 模块。
另有一处**同缩写不同义**要认得：`mechanics.md` 第 7 节 第 576 行里的 `Cmd->BD` 是 DMA 硬件描述符块（Block Descriptor）的字段名，
与这张图无关 —— 观察点就是上下文：一个出现在建图的 Tcl 命令里，一个出现在 `XAxiDma` 的源码行里。
⑤ 辨认方法：打开一个 Tcl 脚本，连着看到 `create_bd_design` / `create_bd_cell -type ip` / `make_wrapper` 这三条命令
就是 BD 流程；它的产物名字总是 `<图名>.bd` 与 `<图名>_wrapper.v`（本工程是 `design_1`）。

### 28. AXI 从设备（slave，本目录也写作"从机"）

**正文首见**：`prerequisites.md` 第 2 节"总线握手"那一行（用"从机"）；
成词"从设备"首见 `myths.md` 第 9 节 第 425 行与 `interface-contract.md` 第 2 节 第 12 行。

① 一根总线上一头报地址要东西、另一头听着并应答；应答那一头就是"从设备"。
本目录里它有时被叫作"从机"，是同一个东西的两种写法。
*简化说法，会在"以为从设备就是外设芯片"的情形下误导你 —— 这里的从设备可以是芯片内部的一段逻辑，
精确版见下一层。*
② 分不清主/从会看到：把 `src/rtl/top/system_top.v:99` 那两个空括号念反方向 ——
`M_AXI_HP0_bid()` 与 `M_AXI_HP0_bresp()` 是**从机给出**的"你这笔写得对不对"的回应线，
本工程没接任何线，于是"写失败"这件事在工程里根本没有出口（同口径见 `mechanics.md` 第 1 节 第 99 行）。
③ 口径：本机 `ug585-Zynq-7000-TRM.pdf` 第 56 页 Table 2-6 就是用 Master / Slave 两列给每个口定方向
（`M_AXI_GP0` 行 Master=PS / Slave=PL；`S_AXI_HP0` 行 Master=PL / Slave=PS），核对日期 2026-10-05。
AXI 协议本体（Arm IHI 0022）里 slave 的定义条文本次未抓到正文 ⇒ `【未核实·正文未取到】`，
检索词：`IHI0022 AXI slave interface channels READY VALID`。
本工程的从设备一共四只：三只 `axi_gpio` 的 `S_AXI`（`build/tcl/build_system_axigpio.tcl:190-197`）与 PS 的 `S_AXI_HP0`（`:199`）。
④ 它不是片外总线上的从设备（I²C/SPI 那种芯片），也不是 AXI4-Lite ——
差别在工程里可观察：GPIO 那三只只有一个 `S_AXI` 口、寄存器窗按 64K 段钉地址（`:244-246`），
而 `S_AXI_HP0` 那侧是五组通道线加突发（第 25 条 ④）。
⑤ 辨认方法：打开 BD 脚本或端口清单，看名字前缀 —— `S_AXI_` 挂在那只 IP 上，它就是这条总线的从设备；
`M_AXI_` 开头的是主机侧。

### 29. BUFG（全局时钟缓冲器）

**正文首见**：`subsystem-map.md` 第 4 节 第 96 行；另见 `one-pass-walk.md` 第 1 站 第 46 行。

① 一根时钟要发给芯片里几万个会数数的元件，不能直接从管脚一路拉过去（走到远的地方就歪了），
得先接进一只"总放大器"再发，这只总放大器叫 BUFG。
（"放大器"是比喻，不是实现；实现见 `src/rtl/eth/rgmii_rx.v:51-54` 与 `src/rtl/clocks/clk_gen.v:53-56`。）
*简化说法，会在"以为进了 BUFG 就等于两边同相"的情形下误导你 —— 两只不同的 BUFG 出来的钟可以同频不同相，
本工程为这件事付过一次账，精确版见下一层。*
② 不在同一只 BUFG 上会看到什么：`mechanics.md` 第 9 节 第 724 行记的是实物账 ——
收侧的采样器原来吃 `BUFIO`（SCD 3.171 ns）、下游逻辑吃 `BUFG`（DCD 4.854 ns），同频同相却分走两棵树
⇒ 偏斜 +1.616 ns 由综合器插保持缓冲硬补，"WHS 每次重建在 ±1 ps 上掷硬币（r62 量到 +0.001）"。
③ 口径：BUFG 不属于某个时钟区域，可以到达芯片上任一个时钟落点；
全局缓冲可以透过 HROW 驱动到每个区域（本机 `ug472_7Series_Clocking.pdf` 第 15 页与第 17 页，核对日期 2026-10-05）。
本项目取值：`src/rtl/clocks/clk_gen.v:53-56` 四只（反馈、50 MHz、250 MHz、200 MHz 各一只），
收侧那只在同目录 `src/rtl/eth/rgmii_rx.v:51-54`；用量读数 `build/clock_util.rpt:43` = `BUFGCTRL 8 / 32`。
④ 它不是 BUFIO（第 30 条：只喂 I/O 那一片），也不是 MMCM（第 31 条：那是产生频率的）。
可观察的差别：`build/clock_util.rpt:45` 的 `BUFIO` 用量 0 而 `:43` 的 `BUFGCTRL` 用量 8
—— 判据原文写在 `board/acceptance.md:25`（"收口只有一棵时钟树"，r94 重念）。
⑤ 辨认方法：打开 `build/clock_util.rpt` 的第 2 段 *Global Clock Resources* 表，`BUFGCTRL` 那行 Used 大于 0 就是它；
在 RTL 里搜 `BUFG `，看到 `.I(<时钟源>)` 与 `.O(<发出去的时钟>)` 两只脚的那一段就是它。

### 30. BUFIO（I/O 时钟缓冲器）

**正文首见**：`mechanics.md` 第 9 节 第 723 行（讲的是历史形态）；
现读数在 `clocking-and-reset.md` 第 6 节 第 189 行。

① 另一只时钟放大器，但它只把时钟送进"管脚旁边那一圈"的元件，普通逻辑那片它够不着。
（"放大器"与"那一圈"是比喻，不是实现；本工程的实现侧证据是这一只用量为 0：`build/clock_util.rpt:45`，
历史用法见 `report/40-optimization.md:70`。）
*简化说法，会在"以为它比 BUFG 省资源所以可以随便换"的情形下误导你 ——
它能喂的负载范围不同，换过去会把采样沿挪走 1.683 ns，精确版见下一层。*
② 用错它会看到：正是第 29 条 ② 那笔账 ——采样的那一下和下游数数的那一下分在两棵树里，
偏斜要靠工具硬补。这一条不是传闻：`report/40-optimization.md:70` 的 r92 那一行写的就是
"#57：`rgmii_rx` 删 `BUFIO`、5 个 IDDR 改吃 BUFG；`IDELAY_VALUE` 15→26"。
③ 口径：*The I/O clock buffer (BUFIO) drives the I/O clock tree, providing access to clock all sequential I/O
resources in the same I/O bank*；同手册另一处补一句 *The BUFIO only drives I/O clocking resources while the BUFR
drives I/O resources and logic resources*（本机 `ug472_7Series_Clocking.pdf` 第 14 页与第 17 页，核对日期 2026-10-05）。
本项目取值：**现役树里 0 只** —— `grep -rn BUFIO src/rtl/` 本次只命中注释三处
（`src/rtl/eth/rgmii_rx.v:4-5`、`:7`、`src/rtl/top/system_top.v:160`），没有实例。
④ 它不是 BUFG（第 29 条），也不是"输入缓冲器 IBUF"。
可观察的差别：`build/clock_util.rpt:45` 那行 `BUFIO` Used = 0，而改前那份对照件 `build/r88_clock_util.rpt`
按 `board/acceptance.md:25` 的记录是 1。
⑤ 辨认方法：打开 `build/clock_util.rpt` 第 2 段那张表，`BUFIO` 那行 Used > 0 就说明有 I/O 时钟走的是它；
RTL 里搜 `BUFIO` 只剩注释 ⇒ 这一版没有。

### 31. MMCM（混合模式时钟管理器）

**正文首见**：`myths.md` 第 15 节 第 790 行；`subsystem-map.md` 第 2 节 第 41 行、`clocking-and-reset.md` 第 1 节 第 24 行起。

① 一块硬件：进来一个时钟，它先在里面把频率抬得很高，再从那个高频上分出好几路不同频率、不同相位的时钟给你用。
*简化说法，会在"以为三路输出的频率想填多少填多少"的情形下误导你 —— 三路都是从同一个中间高频分出来的，
而那个中间频率被器件速度等级框死，精确版见下一层（第 32 条讲那个中间频率）。*
② 没有它（或它没锁住）会看到两件事：TMDS 要的 250 MHz 与输入延时要的 200 MHz 参考都拿不到；
更重要的是"锁住了没有"这件事没有信号 ⇒ 顶层那句 `rst_n(eth_rst_n & mmcm_locked)`
（`src/rtl/top/system_top.v:175`）就不存在，复位会不按时钟稳不稳放人。
③ 口径：MMCM 的输出由"中间高频"再分频得到，倍频/分频系数在例化属性里给；
PLL 是 MMCM 的子集（同性能，除最小 CLKIN/PFD 与最小/最大 VCO 频率之外，连接与功能有削减）
（本机 `ug472_7Series_Clocking.pdf` 第 22 页，核对日期 2026-10-05）。
本项目取值：`src/rtl/clocks/clk_gen.v:15-31` 那一组属性 —— `CLKIN1_PERIOD 20.000`（50 MHz 进）、
`CLKFBOUT_MULT_F 20.000`、`CLKOUT0_DIVIDE_F 20.000`、`CLKOUT1_DIVIDE 4`、`CLKOUT2_DIVIDE 5`；
两只实例（`src/rtl/top/system_top.v:121-125` 与 `src/rtl/top/pl_video_top.v:128`），
用量读数 `build/clock_util.rpt:48` = `MMCM 2 / 4`。
④ 它不是"分频器"三个字那么简单，也不是 BUFG（第 29 条）。
可观察的差别：第二只 MMCM（`u_idelay_clkgen`）的两路输出在本层**故意不接**
（`src/rtl/top/pl_video_top.v:127` 记 `clk_200m_unused` 那条），它只为输入延时的参考钟存在 ——
这与"一只 MMCM 出来三路都在用"的第一只（`src/rtl/clocks/clk_gen.v:53-56`）形状不同。
⑤ 辨认方法：RTL 里搜 `MMCME2_BASE` 或 `MMCME2_ADV`，看到 `CLKFBOUT_MULT_F` 与一组 `CLKOUT*_DIVIDE` 成对出现就是它；
报告里 `build/clock_util.rpt:79` 那种 `MMCME2_ADV/CLKOUT0` 的"源/输出"写法也是它。

### 32. VCO（压控振荡器，MMCM 里面那根真正在振的高频钟）

**正文首见**：`myths.md` 第 15 节 第 790 行（`VCO 1000 MHz`）；另见 `mechanics.md` 第 10 节 第 790 行。

① MMCM 内部那根频率最高的钟：进来的钟先被它"抬"上去，出去的每一路都是从它身上分出来的。
（"抬上去""分出来"是比喻，不是实现；实现见 `src/rtl/clocks/clk_gen.v:19`、`:21`、`:24`、`:27` 那四个分频系数。）
*简化说法，会在"以为抬多高都行"的情形下误导你 —— 它只有 600 MHz 到某一上限这一段能待，
分频系数要凑进这一段，精确版见下一层。*
② 不看它会看到：`myths.md` 第 15 节 那一行里 `CLKOUT1_DIVIDE = 4` 与 250 MHz 之间接不上 ——
250 不是 50 除 4 得来的，而是 1000 除 4；少了中间那一步，"5x"这个命名（同节标题）就没出处。
③ 口径：VCO 的最小/最大工作频率"定义在 7 系列数据手册 DS181/DS182/DS183 的电气规范里"
（本机 `ug472_7Series_Clocking.pdf` 第 73 页 *VCO Operating Range*，核对日期 2026-10-05）；
本机 `ds187-XC7Z010-XC7Z020-Data-Sheet.pdf` 第 53 页 Table 72 给数：`MMCM_FVCOMIN` 600.00 MHz，
`MMCM_FVCOMAX` = −3 档 1600 / −2 档 1440 / −1C、−1I、−1LI、−1Q 档 1200 MHz。
本项目：器件 `xc7z020clg484-2`（`build/tcl/build_system_axigpio.tcl:16`）⇒ −2 档，上限 1440 MHz；
取值算式按 `src/rtl/clocks/clk_gen.v:3` 的注释：VCO = 50 × 20 = 1000 MHz（落在 600–1440 之内），
三路输出 1000/20 = 50（`:21`）、1000/4 = 250（`:24`）、1000/5 = 200（`:27`）。
④ 它不是 CLKFBOUT 那根反馈线的频率本身，也不是 `clk_pix5x`（那是 VCO 分出来的**输出**之一，见 `myths.md` 第 15 节）。
可观察的差别：`build/clock_util.rpt:83`、`:85` 那两行 `MMCME2_ADV/CLKFBOUT` 是反馈线在时钟树里的登记，
而 `:79`、`:82` 的 `CLKOUT0`/`CLKOUT1` 才是给逻辑用的那几路。
⑤ 辨认方法：打开一段 MMCM 例化，找 `CLKFBOUT_MULT_F`（乘）与 `DIVCLK_DIVIDE`（除）那两个属性，
"进钟 × 乘 ÷ 除"得到的就是 VCO；再看每个 `CLKOUT*_DIVIDE` 除的是这个中间数。

### 33. IDDR（输入双沿寄存器）

**正文首见**：`subsystem-map.md` 第 2 节 第 51 行；`one-pass-walk.md` 第 1 站 第 46 行、`clocking-and-reset.md` 第 1 节 第 29 行。

① 一只"上沿采一次、下沿也采一次"的输入寄存器，于是四根线一根时钟就能把 8 位收回来自已用。
*简化说法，会在"以为它等同于在代码里写两句 posedge 和 negedge"的情形下误导你 ——
它是管脚旁边专用块里的硬件，普通写法推不出同一件东西，精确版见下一层。*
② 没有它会看到：`one-pass-walk.md` 第 1 站整站不存在（片上第一份数据只有 4 位宽的双沿流），
也就没有"上升沿那半字节是字节低位、下降沿是高位"这条位段规则（原文 `src/rtl/eth/rgmii_rx.v:2`）。
它采错沿的失败形状记在同站"边界与失败"里：整包字节错位 ⇒ 下游 FCS 全错、`bad` 计数上升。
③ 口径：*7 series devices have dedicated registers in the ILOGIC blocks to implement input double-data-rate (DDR)
registers. This feature is used by instantiating the IDDR primitive.* 支持三种模式
`OPPOSITE_EDGE` / `SAME_EDGE` / `SAME_EDGE_PIPELINED`（本机 `ug471_7Series_SelectIO.pdf` 第 109 页，核对日期 2026-10-05）。
本项目取值：`src/rtl/eth/rgmii_rx.v:87-100`（`SAME_EDGE_PIPELINED`，控制线那一只）+ `:103-105` 的
generate 循环里四只数据线，共 5 只（计数口径见同文件 `:3`）；时钟吃 `rgmii_rxc_bufg`（`:95`）。
④ 它不是 `ISERDESE2`（同族但做串并转换），也不是 fabric 里的普通 `always @(posedge …)`。
可观察的差别：本工程的 5 只 IDDR 的时钟与下游 fabric **同吃一只 BUFG**（第 29 条），
而这套件原本可以吃 BUFIO（第 30 条）—— 这一改动就是 `report/40-optimization.md:70` 那一行。
⑤ 辨认方法：RTL 里搜 `IDDR #(` 与 `.DDR_CLK_EDGE(` 就是它；
时序报告里出现 `u_iddr_rx_ctl/D` 这种端点名（`src/rtl/eth/rgmii_rx.v:16` 记的 −2.885 落点）也是它。

### 34. IDELAY 与 `IDELAY_VALUE`（片内可编程输入延时线，与它的档位号）

**正文首见**：`subsystem-map.md` 第 2 节 第 41 行（IDDELAY 那行写的是 `IDELAY`）；
`IDELAY_VALUE` 这一具体写法首见 `one-pass-walk.md` 第 1 站 第 47 行。

① 一根"进来之前先在片子里垫一小段固定延迟"的可编程线；垫几格由一个整数写死，那个整数就叫 `IDELAY_VALUE`。
*简化说法，会在"以为那个整数是时间"的情形下误导你 —— 它是格数（0–31），
一格多长要另外算（→ 第 35、36 条），精确版见下一层。*
② 没有它（或给错格数）会看到：RGMII 那 4 位数据相对采样沿落在眼外面。工程里的实测形状写在
`src/rtl/top/system_top.v:166-168`：把那扇窗建起来后从 0 扫到 31，hold 由 −2.822 走到 −0.870（每格 +63 ps）、
setup 由 +2.005 走到 −0.846，两条线的交点在 31 格 ⇒ 现值取 31（`:172`）。
③ 口径：`IDELAY_VALUE` 是 Integer: 0 to 31、默认 0，"指定 FIXED 模式下的固定格数，或 VARIABLE 模式下的起始格数"；
`REFCLK_FREQUENCY` 是 Real: 190 to 210 / 290 to 310 / 390 to 410、默认 200，
"给静态时序分析用的格频参考（单位 MHz）"；FIXED 模式下这个数在配置之后不能再改
（本机 `ug471_7Series_SelectIO.pdf` 第 119 页属性表与第 120 页 *IDELAY_TYPE Attribute*，核对日期 2026-10-05）。
本项目取值：`src/rtl/eth/rgmii_rx.v:67-70`（`IDELAY_TYPE "FIXED"`、`REFCLK_FREQUENCY 200.0`），
格数从顶层传进来（`src/rtl/top/system_top.v:172` = 31），参考钟是第二只 MMCM 的 200 MHz 输出
（`src/rtl/clocks/clk_gen.v:27` 与 `src/rtl/eth/rgmii_rx.v:59-63` 的 `IDELAYCTRL`）。
④ 它不是 `set_input_delay`（那是给工具的"片外要多久才到"的**约束**，一点电路都不动），也不是 ODELAY（输出侧那套）。
可观察的差别就写在 `src/rtl/eth/rgmii_rx.v:12-16`：那句"没有窗的时候它看着像修好了，窗建起来之后
变成捕获沿比数据晚到约 5 ns 的净损失" —— 垫延时线与约束各自动了什么，两份读数一比就分开。
⑤ 辨认方法：RTL 里搜 `IDELAYE2 #(` 与 `.IDELAY_VALUE(` 就是它；
时序路径报告里出现 `IDELAYE2` 单元名也是它。本工程还有一个附加判据：格数的**唯一**出处是顶层那一个参数
（`src/rtl/top/system_top.v:172`，`mechanics.md` 第 9 节 第 758 行把这条列为辨认方法）。

### 35. tap（延时线的一格）

**正文首见**：`one-pass-walk.md` 第 1 站 第 52 行（`156 ps/tap`）。

① 第 34 条那根可编程延时线里的"一格"：编号 0 到 31，每加一格就晚一点，**一格到底是多久要标定才知道**。
*简化说法，会在"把 31 格读成 31 ns 或 31 ps"的情形下误导你 —— 编号不带时间单位，精确版见下一层。*
② 把格数当时间会看到什么：本工程同一族数字有三种口径互相打脸，全登记在
`src/rtl/eth/rgmii_rx.v:21-23`（原话"三种数互不一致……未定，不当结论用"）：
按 200 MHz 参考算的 156 ps/格（同文件 `:8`）、实测斜率约 63 ps/格（同文件 `:19`）、
由报告里 2.292 ns ÷ 26 格得到的约 88 ps/格（同文件 `:22`）。`one-pass-walk.md` 第 1 站 第 52-54 行
就是按纪律**不选边**、只取"综合进位流的那个数"（RTL 常数 31）。
③ 口径：*The tap delay resolution is contiguously calibrated by the use of an IDELAYCTRL reference clock
from the range specified in the 7 series FPGA data sheets*（本机 `ug471_7Series_SelectIO.pdf` 第 115 页）；
数据手册那条公式在本机 `ds187-XC7Z010-XC7Z020-Data-Sheet.pdf` 第 42 页：
`TIDELAYRESOLUTION` = 1/(32 × 2 × F_REF) µs（F_REF 以 MHz 代入）⇒ 200 MHz 代进去得 **78.125 ps**；
同表 `:42` 还给出参考属性只允许 200/300/400 MHz（−1I、−1LI、−1Q 档只有 200），第 43 页给 ps/格 的抖动项。
**78.125 与注释里的 156 差一个 ×2，本次不判谁对**（区分办法就是 `src/rtl/eth/rgmii_rx.v:23` 那句：先把这条量清楚）。
④ 它不是第 4 条那种"打拍同步的级数"（本目录另一处也叫"拍"），也不是抽头抽电流的那种电路。
可观察的差别：`src/rtl/top/system_top.v:167` 用的是"0.155 ns/拍 的斜率差解出 31.1"，单位是延时线的格；
而"三拍取相邻两拍的差"（`recall-run-a.md` 第 2 题复述的那条）里的拍是时钟周期。
⑤ 辨认方法：拿到一份报告，看见 `IDELAYE2` 单元旁边一个总时间除以一个 0–31 之间的整数 ⇒ 商就是每格时长；
代码里 `.IDELAY_VALUE(` 后面那个整数就是格数（本工程 = 31，`src/rtl/top/system_top.v:172`）。

### 36. ps（皮秒，作为单位）

**正文首见**：`one-pass-walk.md` 第 1 站 第 52 行；另见 `mechanics.md` 第 9 节 第 725-726 行。

① 十亿分之一秒的千分之一（10⁻¹² 秒）：一片上"一格延时""一点抖动"这种量小得只有这个单位装得下。
*简化说法，会在"以为 ps 这一档可以忽略"的情形下误导你 —— 工程里被登记成"掷硬币"的那件事就是 ±1 ps 量级的，
精确版见下一层。*
② 不用这个单位会看到：同一件事出现两种刻度而对不上 ——
`mechanics.md` 第 9 节 第 725 行那句"WHS 每次重建在 ±1 ps 上掷硬币（r62 量到 +0.001）"里，
±1 说的是 ps、+0.001 说的是 ns，同一个量的两次读数；第 35 条那三种口径（156/63/88）也全靠 ps 才能并排比。
③ 口径：pico- 表示 10⁻¹²（单位制条目本次未抓到正文 ⇒ `【未核实·正文未取到】`，检索词 `SI prefix pico 10^-12`）。
仓库里可核查的两处用法：仿真时间声明 `\`timescale 1ns/1ps`（`src/rtl/clocks/clk_gen.v:1`、
`src/rtl/util/ps_publish.v:1`；那两个数的含义是"时间单位 1 ns、最小精度 1 ps"，条文级出处本次未取到，
检索词 `IEEE 1364 timescale module directive precision`）；工具口径的 ps 读数在本机
`ds187-XC7Z010-XC7Z020-Data-Sheet.pdf` 第 43 页（`ps per tap` 那一组抖动项）。
时序报告的裕量单位是 ns（本工程读数 0.739 ns，`data/metrics.csv` 第 5 行）。
④ 它不是"ppm/百分比"，也不是"一拍"：一拍在 125 MHz 域是 8.000 ns
（`clocking-and-reset.md` 第 1 节 那张表的单位整列是 ns）。
可观察的差别：词条 11 ② 那条红线 —— 裕量（ns）与时长（拍/ms）永不相减，混单位是本目录专门写过的一条坑。
⑤ 辨认方法：打开任何一份时序或 I/O 报告，数字后面带 `ps` 的只有三类对象 ——
延时线每格时长、抖动（jitter）、位间偏斜（skew）；出现这三样之一就是它在说话。

### 37. 异拍（用相邻两拍的差换一个"刚才跳了一次"）

**正文首见**：`code-reading.md` 第 6 节 第 391 行（引的是形态名）；
成表用法首见 `clocking-and-reset.md` 第 3 节 第 77 行那一列（"翻转位 + 3 级 + 异拍"），讲法在 `clocking-and-reset.md` 第 4.2 节。

① 把同步链的最后两级各存一份样本，比较这两份**不同时刻**的样本：不一样，就说明这中间跳了一次。
*简化说法，会在"以为它和同域里的边沿检测一样一次不漏"的情形下误导你 ——
对面看一眼的间隙里连着跳两次，会被并成一次都不到，精确版见下一层。*
② 不用它、直接拿对面时钟采那根只亮一下的线会看到：事件整个消失。
工程把这件事写成模块存在的理由：`src/rtl/util/ps_publish.v:2-5`（为什么单独成模块、要能扫相位）
与 `src/rtl/video/frame_commit_lock.v:100-105`（原话：「电平型 3 级同步在这里并不能修好它」（实测与裸采逐相位一模
一样）；正确形式是翻转式脉冲同步器）。
③ 口径：本工程的定义就是代码形状 —— 三级链 `{m2,m1,m0} <= {m1,m0,tog}` 之后
`assign new_tog = m1 ^ m2;`（`src/rtl/util/ps_publish.v:20-25`），
注释把第三级的用途写明："第三级专门给'异拍出沿'用，保证 new_tog 两拍内稳定可被 consume 采样"（同文件 `:17`）。
第二处同形：`src/rtl/eth/ddr_bank_commit.v:42-47`（`wire fd_axi = fd1 ^ fd2;`）。
"脉冲同步器（pulse synchronizer）"的规范级定义本次未抓到正文 ⇒ `【未核实·正文未取到】`，
检索词 `Xilinx pulse synchronizer toggle based CDC UG949`。
④ 它不是同域里的普通边沿检测（那个不需要 3 级，也不需要 `ASYNC_REG`），也不是握手（没有回线，见词条 4 ④）。
可观察的差别：`src/rtl/eth/ddr_bank_commit.v:42` 那三级是带着 `ASYNC_REG` 属性整条链标的（词条 5），
而普通边沿检测的两级寄存器不会带这个属性。
⑤ 辨认方法：打开一份陌生 RTL，搜 `^ `（异或）且两个操作数是同一根线的相邻两级（`x1 ^ x2` 形状）就是它；
再看这两级有没有第三条 `x0`（三级 ⇒ 跨域用，两级 ⇒ 同域边沿检测）。

### 38. 准静态（"平时不动、要动就整套一起换"）

**正文首见**：`myths.md` 第 3 节 第 95 行（引 RTL 原话）与 第 104 行；
成表用法见 `clocking-and-reset.md` 第 3 节 第 78-86 行那几列；就地用法另见 `interface-contract.md` 第 5 节 第 157 行。

① 形容一排数的用法：绝大多数时刻它们一动不动，真要改的时候一次性把整排写好、同一刻动一下旗子。
*简化说法，会在"以为准静态就是很慢"的情形下误导你 —— 它可以每帧都换，
只要每次换完到下一次换之间给对面留出稳定时间，精确版见下一层。*
② 不这么用会看到：`src/rtl/top/pl_video_top.v:649` 记的那处 —— 19 位各自打两拍 ⇒ 读到"半新一半旧"的档位号，
屏幕上是一张几何参数对不上的画；`myths.md` 第 3 节 第 95 行引的 RTL 口径
（`src/rtl/eth/eth_udp_video_top.v:275-276`）则是反过来的例子：那个位**是**准静态控制位、不是脉冲。
③ 口径：本工程的定义就是契约注释 —— 源域把宽总线**整拍**写好、同拍翻转 `bus_tog`，
目的域在同步过来的跳变沿那一拍采一次；边沿要 3 级同步才到目的域，而源总线至少保持到下一次写入
（`src/rtl/eth/snap_cross.v:2-5`），节流要求（两次写入之间留出 `SETTLE` 个源周期）写在
`src/rtl/eth/link_monitor.v:165-166`。"quasi-static" 这一术语的规范级定义本次未抓到正文 ⇒
`【未核实·正文未取到】`，检索词 `quasi-static bus crossing CDC`。
④ 它不是"低频信号"，也不是"原子读"（词条 8 ④ 讲的正是这个区别）。
可观察的差别：同一个形容词在本工程有两种形态 —— 总线+沿（`clocking-and-reset.md` 第 3 节表第 3、9、10、11 行）
与单根三位电平链（同表第 4、14 行的 `gapclr_sel` 那类）。
⑤ 辨认方法：打开 `clocking-and-reset.md` 第 3 节那张跨域点全表，"形态"一栏写着"准静态总线 + 心跳"的行就是它；
在代码里则看 `snap_cross #(.W(…))` 的例化（词条 8 ⑤）。

### 39. 影子值（软件这边那份"上次到底写进去什么"的完整副本）

**正文首见**：`interface-contract.md` 第 5 节 第 158 行。

① 驱动软件自己留一份变量，记着"上一次写进那个寄存器的整排位长什么样"；下次想改其中一位，
就照这份副本重新拼一整排写回去，而不是去把硬件读回来改。
*简化说法，会在"以为这是为了跑得快而做的缓存"的情形下误导你 ——
它是正确性要求：那只寄存器里还住着别人用的位，精确版见下一层。*
② 没有它会看到：`src/ps/main.c:94-95` 警告的那条 ——
"这一组位与 gamma 协议在**同一个寄存器**里 ⇒ 所有写通道 2 的地方都必须从 `gm_w` 这个影子出发整字写回
（读-改-写会踩 #55 那个'PS 每帧重写把别的位抹掉'的同一个坑）"；
同一处坑在 `interface-contract.md` 第 3 节 小结 2（第 78 行）里也念了一遍 —— 那一行以及第 5 节 小结 2 写的源码路径
是本目录里较旧的那一套（`src/ps/main.c`），文件现在在 `src/ps/main.c`；
两套路径并存的登记见 `mechanics.md` 第 12 节 红项 3。
③ 口径（工程内）：影子变量就是 `static u32 gm_w`（`src/ps/main.c:288`，
注释自称"通道 2 当前电平：wr 位的唯一真相在这里（PL 那边只看边沿）"），
写的时候一律 `Xil_Out32(CFG_DATA1, gm_w | GM_DATA(v) | GM_IDX(i))`（`:368`、`:371`），
翻位只翻影子（`:370` `gm_w ^= GM_WR;`）。这类写法的通用名（shadow register / 读-改-写）
本次未抓到权威条目 ⇒ `【未核实·正文未取到】`，检索词 `shadow register read-modify-write atomic update`。
④ 它不是硬件里的寄存器复制（词条 5 讲"工具会挪位、复制"是综合阶段另一件事），也不是备份镜像。
可观察的差别：影子在 `.c` 文件里（一个 static 变量），而 `ASYNC_REG` 那条是 RTL 属性；
两者都在"别乱动"的语感里，但一个管软件写法、一个管物理放置。
⑤ 辨认方法：打开任何一份写硬件寄存器的代码，看 `Xil_Out32` 的第二个参数是**现拼的整字**
（本工程：`src/ps/main.c:214-219` 每一项都取自本地变量）还是"先 `Xil_In32` 回来改一位"——
前者背后一定配着一个影子，后者才是本工程明令不许用的写法。

### 40. 整字写回（一次把 32 位从头到尾整个写进去）

**正文首见**：`system-overview.md` 第 4 节 第 97 行（"两条控制字整字写回"）；
规则化表述见 `interface-contract.md` 第 3 节 第 56 行与小结 2（第 78 行）。

① 写寄存器的时候不"只改需要的那一位"，而是把这一次要的全部位拼成一个 32 位数，一次性整个写进去。
*简化说法，会在"以为整字写就等于原子、对面一定收得到"的情形下误导你 ——
原子性只到 GP0 那侧的寄存器写为止，跨进像素域还要过同步，事件语义只有其中两位，
精确版见下一层。*
② 不整字写会看到：`interface-contract.md` 第 3 节 小结 2 原话 ——
"写它必须整字写，读-改-写会踩'每帧重写把别的位抹掉'那个坑"；
写反方向的坑也登记着：`src/ps/main.c:211-213` 那句"位序一改，`set_src.tcl`/`health_read.mjs`
这些按位写的工具就全错位"。
③ 口径（工程内）：合成式在 `src/ps/main.c:214-219`（逐项或起来之后 `Xil_Out32(GPIO_DATA, v);`），
第二只在 `:223-226`（CFG_DATA0 一次写整个字）；PL 侧取位在 `src/rtl/top/system_top.v:264-293`。
协议层（AXI4-Lite 单次写）的条文级出处本次未抓到 ⇒ `【未核实·正文未取到】`，
检索词 `AXI4-Lite single write 32-bit address data channel IHI0022`。
④ 它不是 AXI 突发（第 25 条那边一次说 N 拍），也不是"一次写 64 位"——HP0 的 64 位是数据宽，不是寄存器写规则。
可观察的差别：GP0 这一侧"整字写、读回；没有突发概念"（`next-layer.md` 第 2 节 第 79 行）。
⑤ 辨认方法：搜 `Xil_Out32(`，看它的值是"现拼"还是"读回来改一位"。
本工程唯一的**故意例外**是上位机选 lane 那一次：先读回、只改高 5 位、读完再写回
（做法写在 `src/host/health_read.mjs:9-11`）—— 例外之所以成立，是因为那只脚本改的位与固件写的位不重叠。

### 41. strap（上电那一次被采样的引脚）

**正文首见**：`system-overview.md` 第 6 节 第 147 行。

① 有几根引脚在芯片刚通电（或刚复位）的那一瞬间被读一次，它们此刻的高低电平（由板上的上拉/下拉电阻定下来）
就是这块芯片的工作模式；这种引脚叫 strap 脚，效果等同于"硬件上的出厂设置开关"。
（"出厂设置开关"是比喻，不是实现；实现见数据手册那两张表与本工程 `src/rtl/top/system_top.v:113-117`。）
*简化说法，会在"以为它和软件配置一样随时能改"的情形下误导你 ——
它只在电源/复位那一瞬间有效，之后要改得走别的接口，精确版见下一层。*
② 不知道有它（或以为能用软件改）会看到：`src/rtl/top/system_top.v:113-115` 记的现象 ——
本工程的数据面不碰 MDIO，于是 `eth_mdio` 被接成高阻、`eth_mdc` 被钉 0（`:116-117`），
综合为此报一条 `Synth 8-3917 port eth_mdc driven by constant 0`，注释把它写成"陈述而不是缺陷"，
理由那一栏写的就是"PHY 的工作模式由板上 strap 定"。
③ 口径（本机手册，核对日期 2026-10-05）：Realtek RTL8211F(I)-CG 数据手册
（`D:/Xilinx/Resource/ZYNQ7020/Board_Resource/芯片手册/C187932_以太网芯片_RTL8211F-CG_规格书_REALTEK(瑞昱)以太网芯片规格书.PDF`）
§6.6 *Mode Selection (Hardware Configuration)* Table 6（PDF 第 16 页）与
§7.8 *Hardware Configuration* Table 10「CONFIG 引脚 与 配置寄存器」对照（PDF 第 23 页）。
RGMII 那两条原文：`TXDLY`＝"Pull up to add 2ns delay to TXC for TXD latching"、
`RXDLY`＝"Pull up to add 2ns delay to RXC for RXD latching"。
板上取值：`board/hardware_setup.md:97-99`（板卡原理图 `ZYNQ7020-F+V1.1原理图.pdf` 第 8 页那张 PHY2 strap 表；
结论行 `report/timing/round_r116.md:31`："RXDLY/TXDLY 都由 4.7K 上拉到 IODVDD ⇒ PHY 把 2 ns 延时加在 RXC 上"）。
**另有两处脚号不一致**：数据手册 Table 6 给 24/25，`board/hardware_setup.md:97` 记 23/24 —— 本次未区分，
区分方法是照原理图第 8 页那张表逐个脚号对一遍（那份截图在 `board/captures/`，
`board/hardware_setup.md:101` 登记了本轮实测的四个文件名）。
④ 它不是 MDIO 寄存器配置（同一片 PHY 的另一套配置面，本工程没走），也不是位流里的触发器上电初值
（第 19 条讲的"上电值只由位流承载"是 PL 侧另一件事）。
可观察的差别：`src/rtl/top/system_top.v:116-117` 那两句 assign ——只要 MDIO 不驱动，
本工程就没有任何一条能在上电之后改 PHY 设置的路径，strap 是唯一的那一次。
⑤ 辨认方法：拿到一份数据手册，翻到引脚表看 Type 那一列 ——
写成 `O/LI/PU`、`O/LI/PD`（输出 / 低有效输入 / 内部上拉或下拉的复用）的脚就是 strap 脚；
再在原理图里看那几只脚外接的是上拉还是下拉电阻。

### 42. `set_bus_skew`（管位与位之间散开多少的那条约束）

**正文首见**：`next-layer.md` 第 3 节 第 180 行（与 第 231 行的小结）。

① 一条"这一排线的长短差不能超过多少"的约束：它管的是**位与位之间散开多少**，不管"多久才到"。
*简化说法，会在"以为加了它跨时钟域就安全了"的情形下误导你 —— 它管偏斜，
不代替格雷码或翻转握手那种结构修法，精确版见下一层。*
② 该有没有的场景会看到什么：本机 UG949 中文译本第 139 页给的就是现象描述 ——
异步 CDC 路径若不控偏斜，"接收时钟域在同一时钟沿上锁存总线的多个状态"。
本工程的现状（可核查）：`src/constraints/r114_io_async.xdc:64-66` 那句"还没写的一条（如实交代，不留假话）：
`set_bus_skew` 需要点到**同步器单元名**，而 r114 的对象探针在 `get_false_paths` 上死了
（该命令在本工具不存在），异常清单还没数出来；……这一条就继续挂着，不写成'已做'"。
③ 口径：`set_bus_skew` —— 使用总线偏差代替时延来约束异步 CDC 路径之间的一组信号；
同节还建议可把它用在"以格雷编码取代 `set_max_delay -datapath_only`"的那类 CDC 总线上，
并把细节引向 UG903（本机 `ug949-vivado-design-methodology-zh-cn-2026.1.pdf` 第 134 页与第 139 页；
该文件页脚自署 `UG949 (v2024.2) 2024 年 12 月 18 日`，核对日期 2026-10-05）。
英文原句与另一份版本的指针在 `next-layer.md` 第 3 节 第 180 行。UG903 正文本次未抓到 ⇒
`【未核实·正文未取到】`，检索词 `UG903 set_bus_skew bus skew constraint`。
④ 它不是 `set_max_delay -datapath_only`（那条给的是时延上界），也不是 `set_clock_groups`（第 12 条：整对不分析）。
可观察的差别：`src/constraints/r114_io_async.xdc:57-64` 那四条 `set_max_delay` 是**写下去的**，
而 `set_bus_skew` 在同文件里只出现在注释里 ⇒ 本工程的时钟偏斜这件事目前没人管。
⑤ 辨认方法：在约束文件里搜 `set_bus_skew` —— 命中且后面点到同步器/总线对象才是"已生效"；
只在注释里出现（本仓库现状）就是"挂着"。工程口径另见 `next-layer.md` 第 3 节 第 231 行那句"同一层的下一格"。

### 43. performance extent（策略内部"试到什么程度"那一格）

**正文首见**：`design-choices.md` 第 13 节 第 638 行；另见同节小结 2（第 689 行）。

① 换实现策略（第 47 条）的时候，工具内部那张"要不要多试几轮、试多狠"的刻度；
这一格就叫 performance extent，它跟着策略档一起换。
（"油门/刻度"是比喻，不是实现；本工程的实现侧证据只有两行打印：`build/tcl/build_system_axigpio.tcl:323`、`:349`。）
*简化说法，会在"以为它是能单独抄进脚本的一个配置项"的情形下误导你 ——
它是策略内部的组成，名字与内部行为随工具版本变，精确版见下一层。*
② 不知道它会看到：换了档、跑了两小时、数字与基线**逐位相同**而没有任何东西报错 ——
`report/40-optimization.md:72`（r95 A 那一行）记的正是这条，工具自己给的理由是三行
（`All physical synthesis setup optimizations will be skipped` / `The netlist was not modified`），
本目录把它念成"结构性空转"（`design-choices.md` 第 13 节 第 669 行）。
③ 出处：本目录里这个词目前只有 `design-choices.md` 第 13 节 第 638 行那一处用法
（"`Performance_*` 一族，内部含 performance extent 档位"）。规范级条文本次未取到：
本机 UG949 中文译本全文抽取里 `performance extent` 与 `Performance_` 两种写法各 0 命中（本次实测），
`docs.amd.com` 上一轮抓不到正文 ⇒ `【未核实·正文未取到】`，检索词
`UG904 Vivado implementation strategies performance extent`、`Performance_ExploreWithRemap strategy`。
④ 它不是 directive（第 46 条：给某一步换做法），也不是策略名本身（第 47 条）——
策略是整张日程表，extent 是表里"跑多狠"的那一格。可观察的差别：本工程碰过的只有
`STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE`（`build/tcl/build_system_axigpio.tcl:343-344`），
策略只走环境变量（`:317-323`），extent 一个字没设。
⑤ 辨认方法：拿到一份策略定义，看它里面除了"跑哪几步"之外有没有"每一步跑到什么程度"那一栏；
行为侧的形状是 runtime 变了、WNS/WHS/端点数一格不差（对照 `report/40-optimization.md:72`）。

### 44. Multi-Boot（上电时按顺序试好几份位流）

**正文首见**：`myths.md` 第 18 节 第 916 行（列为"本篇不讲、下一层读"的一条）；
正文级讲法在 `next-layer.md` 第 4 节（第 235 行起）。

① 芯片上电时不是只读一份配置，而是按排好的顺序试：第一份起不来就退到第二份。
*简化说法，会在"以为它跟运行时重新下载位流是一回事"的情形下误导你 ——
它发生在配置阶段、由片内逻辑与外部存储里的镜像顺序决定，精确版见下一层。*
② 没有它（在需要现场可恢复的产品上）会看到：一份坏位流就把板子卡住，只能人过去用 JTAG 重刷。
`next-layer.md` 第 4 节 第 300 行把这条记成移植时的第一道坎（"电源与配置存储的多镜像回滚"）。
③ 出处：`next-layer.md` 第 4 节 第 262 行登记的检索结果是 —— 配置与启动顺序在 UG470，
本次在那份件里 grep 该词 0 命中 ⇒ `【未核实·正文未取到】`，检索词 `UG470 multi-boot failure recovery QSPI golden image`。
本项目现状可核查：位流侧只受管了一个压缩开关（`src/constraints/rk_zynq7020.xdc:77`
`set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]`），多镜像回滚那套没做
（同口径记在 `next-layer.md` 第 4 节 第 254 行那张表）。
④ 它不是部分重配置（PR：跑起来之后换芯片的一部分，同节讲的另一半），也不是"软件重启"。
可观察的差别：本工程换 bit 走的是 JTAG 那条三步链（`build/tcl/program_pl.tcl:30-32`），
配置存储侧没有任何镜像表可回滚 —— `next-layer.md` 第 4 节 第 275 行就明说"Multi-Boot 不是重新下载 bit"。
⑤ 辨认方法：看原理图里外部配置存储器（QSPI flash）的镜像地址安排与配置模式脚；
在本仓库里能观察到的是**反面**：没有任何一份脚本往 flash 里写第二个镜像（`report/` 的板卡口径与
`next-layer.md` 第 4 节 第 254 行一致）。

### 45. phys_opt（物理综合：摆好之后又挪一挪）

**正文首见**：`design-choices.md` 目录 第 23 行与 第 13 节（第 635 行起）；另见 `next-layer.md` 第 6 节 第 404 行。

① 布局或布线跑完之后，工具再动手把已经摆好的东西挪一挪、把太累的那根线多复制几个驱动，这一步叫 phys_opt。
*简化说法，会在"以为它跟综合一样会改电路"的情形下误导你 —— 脚本注释的原话是"它**不动网表**只动物理结果"，
精确版见下一层。*
② 不知道它存在会看到两种相反的现象：一是它确实能买到东西
（`build/tcl/build_system_axigpio.tcl:337-339` 那段记：全设计最差由两条布线主导的路径决定，
eth 那条高扇出网络 fo=96/17 正是这步的靶子）；二是开了也白开
（`design-choices.md` 第 13 节 第 669 行那一滚：读数与基线逐位相同）。
另一条工具用法教训记在同节 第 659-660 行：`catch` 在成功时返回 `"0"`，判错法会把一次成功的 phys_opt 打死整条 impl run。
③ 口径（本机 UG949 中文译本，页脚自署 `UG949 (v2024.2)`，核对日期 2026-10-05）：第 211 页 ——
物理最优化可基于裕量和布局信息自动复制高扇出信号线驱动；"在某些情况下，默认 phys_opt_design 命令不会复制所有
关键的高扇出信号线，请使用其他指令来发挥此命令的作用：Explore、AggressiveExplore 或 AggressiveFanoutOpt"；
第 221 页给 `phys_opt_design -force_replication_on_nets` 的用法与"先强制复制、再重布"的次序。
本项目取值：默认**关**（`build/tcl/build_system_axigpio.tcl:341`），开了就写死一档
`AggressiveExplore`（`:343-344`）并把出身打进日志（`:349`）。
④ 它不是 `opt_design`（综合后那一步会改网表），也不是 place（第 49 条）。
可观察的差别：它的属性名带 `POST_ROUTE_`（`:343`）挂在 route 之后；
而 `opt/place/route` 三步的 directive 本工程一个字没设（`next-layer.md` 第 6 节 第 420-421 行的实测）。
⑤ 辨认方法：构建日志里出现 `BUILD_PRPO on AggressiveExplore` 或 `BUILD_PRPO off` 两行之一（`:349`、`:351`）就是这一档；
run 属性里出现 `STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED` 也是它。

### 46. directive（给实现流程里某一步挑一个做法）

**正文首见**：`design-choices.md` 第 13 节 第 639 行；另见 `next-layer.md` 第 6 节 第 391 行与 第 404 行。

① 实现流程里那几步各自都有一个"做法档位"，挑一下就是换做法而不删这一步，这个档位叫 directive。
（"档位/挑一下"是比喻，不是实现；实现见 `build/tcl/build_system_axigpio.tcl:343-344` 那两条 `set_property`。）
*简化说法，会在"以为换了做法就一定有收益"的情形下误导你 —— 本工程那一滚换完读数与基线逐位相同，
精确版见下一层。*
② 不知道它会看到：把"换过档"当成"改进了时序" —— 观察点写在 `next-layer.md` 第 6 节 第 428-429 行
（那一滚：WNS 0.553 / WHS 0.049 / 0 / 50883 / BRAM 95 与基线一格不差）。
③ 口径：*Directives provide different modes of behavior for the following implementation commands:
`opt_design` / `place_design` / `phys_opt_design` / `route_design`*（UG949 v2019.1 印刷页 197，
本次抽取文本与转引见 `next-layer.md` 第 6 节 第 416 行，核对日期 2026-10-05）；
本机 UG949 中文译本第 212 页、第 221 页、第 224 页给的是命令级写法 `-directive <档名>` 的实例。
本项目取值：只设过一条 —— `STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore`
（`build/tcl/build_system_axigpio.tcl:344`），且默认不启用（`:341`）。
④ 它不是 strategy（第 47 条：那是整张日程表），也不是 Tcl 命令的普通选项（如 `-force_replication_on_nets`）。
可观察的差别：`build/tcl/build_system_axigpio.tcl` 全文里 `DIRECTIVE` 只命中那一条
（`next-layer.md` 第 6 节 第 420-421 行的实测），而策略那一档是 `STRATEGY`（`:323`）。
⑤ 辨认方法：打开 run 的属性名册，看见 `STEPS.<某一步>.ARGS.DIRECTIVE <档名>` 这个形状就是它；
本工程的第二个形状是日志行 `BUILD_PRPO on AggressiveExplore`（`:349`）。

### 47. strategy（实现策略：打包成一档的那一整套选项）

**正文首见**：`design-choices.md` 第 13 节 第 656-657 行；另见 `next-layer.md` 第 6 节 第 391 行。

① 把综合/实现那串步骤连同每一步的选项打包成一档、起一个名字，换名字就是换整套做法。
（"日程表/打包成一档"是比喻，不是实现；实现见 `build/tcl/build_system_axigpio.tcl:312-313`、`:317-323`。）
*简化说法，会在"以为换了名字就只是换个口味"的情形下误导你 —— 它同时改工具选项与产出的报告，
而且随工具版本变，精确版见下一层。*
② 不知道它会看到最难查的那一类：扫完策略不恢复档名，下一次构建会悄悄继承最后扫的那一档 ——
`build/tcl/sweep_impl_strategy.tcl:99-101` 的注释原话是"数字变了但没人改代码是最难查的那一类"，
工程的做法是收尾把 `impl_1` 的 strategy 设回扫描前的值。
③ 口径（UG949 v2019.1 印刷页 197，抽取文本转引在 `next-layer.md` 第 6 节 第 413-415 行，核对日期 2026-10-05）：
策略控制综合与实现 run 的工具选项与产出报告；同页 RECOMMENDED 先试默认策略
（*Try the default strategy … first. It provides a good trade-off between runtime and design performance.*）；
同页 Note：*Strategies are tool and version specific.*
本项目取值：策略走环境变量 `IMPL_STRATEGY`，不设就是工程默认（`build/tcl/build_system_axigpio.tcl:312-313`、
`:317-319`、`:323` 把实际档名打进日志）。
④ 它不是 directive（第 46 条），也不是本机 UG949 中文译本第 152 页那种"块级综合策略"（`BLOCK_SYNTH.*`，
那是按层级实例设的综合选项）。可观察的差别：一个不存在的档名在 `set_property` 那一步就被拒并打
`BUILD_STRATEGY_REJECTED`（`build/tcl/build_system_axigpio.tcl:319`），那一轮记 `NOT_MEASURED` 而不是"否决"
（`report/40-optimization.md:73`，转引见 `next-layer.md` 第 6 节 第 425-427 行）。
⑤ 辨认方法：工程模式里看 run 的属性名 `STRATEGY`；构建日志里那一行 `BUILD_STRATEGY <实际档名>`（`:323`）
就是"这颗 bit 是哪一档跑出来的"的凭据。

### 48. 综合（synthesis：把 .v 文本翻成网表）

**正文首见**：`prerequisites.md` 第 3 节"构建流程的阶段划分"那一行；
正文级用法首见 `system-overview.md` 第 6 节 第 147 行（"引来一句综合提示"）。

① 工具读你写的那份 .v 文本，决定"要用哪些现成零件、彼此怎么连"，产出一份网表；
这一步叫综合。此时还没有决定每个零件摆在芯片的哪一块地上。
*简化说法，会在"以为综合完的东西就能下载进板子"的情形下误导你 —— 它给的是网表，
没有位置也没有位流，精确版见下一层（第 49、50 条）。*
② 不知道阶段划分会看到：一条只对输出端口有意义的约束写在综合阶段拿不到的对象上，于是每次综合都报一条
而无实际作用 —— `clocking-and-reset.md` 第 5 节 第 164 行与 第 173 行记的就是这件事
（`clk_fpga_0` 由 PS7 IP 自己的约束创建，综合阶段那个名字还不存在），
后果是"改端口名或改时钟名之后要回头看综合日志里有没有 12-4739 / Constraints 18-513"（同节 小结 2）。
③ 口径（本机 `ug949-vivado-design-methodology-zh-cn-2026.1.pdf` 第 117 页"创建综合约束"一节，核对日期 2026-10-05）：
综合提取设计的 RTL 描述，用时序驱动的算法变换为映射后的网表；结果质量受 RTL 代码质量与所提供约束的影响；
这一阶段线延迟用近似建模，无法反映布局约束与拥塞这类影响。
本项目调用点：`build/tcl/build_system_axigpio.tcl:306-311`（`launch_runs synth_1`、`wait_on_run`、
进度不是 100% 就 `puts "SYNTH FAILED …"` 并 `exit 1`），另有单独跑综合的入口在同文件 `:300` 那段
（`VP_STOP_AT=project` 时分步切一刀，综合留给 `build/synth.tcl`）。
④ 它不是"把 C 编译成 .elf"（那是 PS 侧软件，第 50 条），也不是实现（第 49 条）。
可观察的差别：`Synth 8-xxxx` 这一族编号只在综合阶段出现（例：`src/rtl/axi/axi_frame_writer_gated.v:50-54`
记的那条 `Synth 8-4767`；第 18 条 ⑤ 的 `Synth 8-689` 也是），而 `Vivado 12-4739` 那类是约束对象的解析问题（词条 12 ⑤）。
⑤ 辨认方法：打开构建产物目录，看到名为 `synth_1` 的 run 与它的日志就是这一阶段；
日志里出现 `launch_runs synth_1` 与 `SYNTH FAILED` 两种串（`:306`、`:309`）之一，就是在综合。

### 49. 实现（implementation，含布局与布线）

**正文首见**：`prerequisites.md` 第 3 节"构建流程的阶段划分"那一行；
"布局布线"这个说法在 正文 里首见 `next-layer.md` 第 6 节 第 390 行。

① 把网表里那些零件真的摆到芯片的具体位置上（布局）、把线真的连起来（布线），最后生成能下载的那份配置。
这一步叫实现，布局布线是它里面两件事的名字。
*简化说法，会在"以为它是走一遍就固定的流程"的情形下误导你 ——
它有档（第 47 条）也有随机性，同一个数每次重建都可能小幅变，精确版见下一层。*
② 不分阶段会看到：只抄一个全局 WNS 就误判成"某次改动拖慢了设计" ——
`build/gates.sh:278` 记的实测账：同一套约束三次构建 WNS = 0.918 / 0.807 / 0.314，
同段 `:279` 补一句"分组数才是可比的量"，并写明 r64b 那次的 0.314 与双线性**无因果**（ETH 域一行 RTL 没动）。
③ 口径：本工程的阶段边界是可执行的两条命令 ——
`build/tcl/build_system_axigpio.tcl:353`（`launch_runs impl_1 -to_step write_bitstream -jobs 4`）与
报告那一段（`:362-371`：`report_timing_summary` / `report_utilization` / `report_cdc` / `report_methodology` /
`report_power` / `report_route_status` / `report_clock_utilization` / `write_hw_platform`）。
工具级定义（UG904 *Vivado Design Suite User Guide: Implementation* 的 optimize/place/phys_opt/route 四段）
本次未抓到正文 ⇒ `【未核实·正文未取到】`，检索词 `UG904 implementation flow place route WNS`。
④ 它不是综合（第 48 条），也不是"上板在跑"：实现结束时那颗 PL 还没被写过。
可观察的差别：写位流之后还有一步独立的 `program_hw_devices`（`build/tcl/program_pl.tcl:31`）——
实现产出文件，下载才改变板子。
⑤ 辨认方法：run 名是 `impl_1`；构建日志里 `BUILD_STRATEGY <档名>` 那行在它之前（`:323`）；
产物是 `build/system.bit`（`board/firmware/system.bit.md:5` 那张卡的"权威路径"那一格）。

### 50. 位流 / XSA / ELF（编译产物三件套与它们的身份）

**正文首见**：`prerequisites.md` 第 3 节"编译产物三件套"那一行；"位流"一词正文级首见
`system-overview.md` 第 1 节 第 32 行。

① 板上跑的东西其实是三个文件：PL 那份配置（位流 `.bit`）、给软件侧用的硬件描述包（`.xsa`）、
CPU 要执行的程序（`.elf`）。三者各自独立产出，凑成一套才叫"这一版固件"。
*简化说法，会在"以为换了一个另外两个跟着换"的情形下误导你 ——
位流换了一版不等于 ELF 换过（两张卡分开产），精确版见下一层。*
② 不逐件核会看到：交付包自己在 MANIFEST 里写"这一版不作交付"，而导出器还是正常退出 ——
根因就是门禁件只打文件时间、从不打这三件的摘要（`build/gates.sh:50-52` 那段 F2 根因记录）。
③ 口径（工程内可核查的三条产出线，核对日期 2026-10-05）：
位流 = `build/tcl/build_system_axigpio.tcl:353` 的 `write_bitstream` 那一步，
卡片 `board/firmware/system.bit.md:1`；XSA = 同文件 `:371`
（`write_hw_platform -fixed -include_bit -force -file …/system.xsa`），卡片 `board/firmware/system.xsa.md:1`
（那张卡自称它是"zip 容器"，`:5`）；ELF = 独立一条命令 `node build/ps_app.mjs`，
输出路径写在 `build/ps_app.mjs:33`，卡片 `board/firmware/ps_app.elf.md:1`，
而"它是两个独立步骤"那句原话在 `build/tcl/README.md:17`（由 `board/firmware/ps_app.elf.md:21` 转引）。
格式级规范（XSA 容器定义、ELF 文件格式）本次未抓到正文 ⇒ `【未核实·正文未取到】`，
检索词 `Vivado write_hw_platform XSA file format`、`Tool Interface Standard ELF specification`。
④ 它不是"同一轮构建"的保证 —— 三件同轮的唯一凭据是那三个摘要（`build/r118_gates.txt:3-5`），
不是文件名也不是时间戳。可观察的差别就摆在那张卡上：
`board/firmware/ps_app.elf.md:13` 那一节标题直接写"它不是 r118 那一轮产的"，
而同一颗 ELF 出现在 r106/r109/r110/r113/r114 的身份行里（同文件 `:19-20`）。
⑤ 辨认方法：跑 `bash build/gates.sh <目录>`，输出里"身份："那一行起共三行缩进的 `system.xsa md5=` / `ps_app.elf md5=`
（`build/gates.sh:50-52`）就是三件套点名；出现 `ps_app.elf 不在 …（这一版没重编应用 ⇒ 无身份可打）`
（`:53`）就是三件不齐。

### 51. md5 指纹（拿一串字符当文件身份）

**正文首见**：`README.md` 第 3 节 路径 C 第 1 步（第 104 行）；表内规则化用法见 `prerequisites.md` 第 3 节那一行。

① 把一个文件里的字节算成一串固定长度的十六进制字符；内容动一个比特，这串就变。
工程里只念前 12 位，够比对。
*简化说法，会在"以为这串字符能证明文件是对的"的情形下误导你 ——
它只证明"两份字节相同"，不证明功能、也不证明来源，精确版见下一层。*
② 不打它会看到：`build/gates.sh:50-52` 记的那条真实后果 —— 门禁件只有文件时间，
导出器按"板上那一版"去挑配对的报告恒挑不到（`grep -q` 恒假），
于是交付包自己在 MANIFEST 里写"这一版不作交付"而导出器照样正常退出。
同段那句判据是这段的本体："mtime 只说明'同一天'，md5 才说明'同一套'"。
另一面写在 `board/firmware/ps_app.elf.md:11`：文件时间**晚于**内容变更 ⇒ 时间只能说明"被写过一次"。
③ 算法级出处（MD5 消息摘要）本次未抓到正文 ⇒ `【未核实·正文未取到】`，检索词
`RFC 1321 MD5 Message-Digest Algorithm`。工程口径（核对日期 2026-10-05）：
打点在 `build/gates.sh:50-52`（`md5sum … | cut -c1-12`，三件各一行）；
冻结件实例 `build/r118_gates.txt:3-5`；完整 32 位与另一算法（SHA-256）在 `board/firmware/system.bit.md:7-8`。
④ 它不是 CRC/FCS（那两类是通信里检错的码，本目录尚未收，见第 3 节），也不是版本号；
也不是"内容一样就能上板跑"。可观察的差别：同一颗位流有两个读数 ——
卡上 32 位 `cd04907e1369da35…`（`board/firmware/system.bit.md:7`）与门禁行 12 位 `cd04907e1369`
（`build/r118_gates.txt:3`）；截断比对是**本工程的口径**，不是这个算法的性质。
⑤ 辨认方法：门禁件里以"身份："开头那三行就是它（`build/gates.sh:50-52`）；
两份同名报告若 `md5sum` 相同 ⇒ 同一内容、两个路径（实例见 `myths.md` 第 14 节 第 739 行那次核对）。

### 52. lane 读回（先报编号、再取一条 32 位健康字）

**正文首见**：`system-overview.md` 第 3 节 第 75-76 行；这一对读写口的完整位表在 `interface-contract.md` 第 3 节 第 71 行与 第 4 节。

① PL 里那一排健康数字各编一个号；想问哪一条，就先把编号写进一个寄存器，再从另一个寄存器读那一条 ——
一次只能问一条。编号本身就叫 lane 号。
*简化说法，会在"以为编号是内存地址"的情形下误导你 ——
它是挤在一只 GPIO 高 5 位里的选择码，不是地址空间，精确版见下一层。*
② 没有它会看到：调试只能靠串口打印，而 30 fps 的回放每秒往串口推约 2 KB（115200 只有 11.5 KB/s），
发布时序被打印压住 —— 这条账写在 `src/ps/main.c:204-207` 的注释里，
两条回读路的取舍与代价在 `design-choices.md` 第 11 节。
③ 口径（工程内，核对日期 2026-10-05）：编号写 GPIO_0 的 `[31:27]`（位表行 `interface-contract.md` 第 71 行）、
选择逻辑是顶层那段组合式（`src/rtl/top/system_top.v:237-246`，`always @(*)` 按 `lm_lane` 分支）、
出口 `:247`；越界编号返回 `32'hDEAD_BEEF`（`:244`）；上位机侧的纪律是"先读回、只改这 5 位、读完写回"
（`src/host/health_read.mjs:9-11`）。这不是标准术语，规范级无出处 ⇒ `【未核实·正文未取到】`，
检索词 `AXI GPIO 2.0 product guide width tri_o`（用于核对 GPIO 的位宽与方向能力）。
④ 它不是屏上那一格（这一对混淆就是 `myths.md` 第 9 节 那一节的主题，判据行在 第 425 行），
也不是 MIPI 里那种数据 lane。可观察的差别：`src/rtl/top/system_top.v:239-243` 里
lane 31、30、24-29、23 各来自不同的量，屏上画面一个字都不变。
⑤ 辨认方法：读到 `0xDEADBEEF` ⇒ 编号写错了（判据 `src/rtl/top/system_top.v:244`）；
在上位机输出里，每条读数前面带"lane N"那种编号、且同一份件里读两遍做单调性比对的（`src/host/health_read.mjs:22-24`），就是它。

### 53. 门禁（发布前检查：一条命令把该看的都看一遍）

**正文首见**：`README.md` 第 2 节 第 46 行（"读一份冻结的门禁清单"）；
正文级首见 `system-overview.md` 第 1 节 第 32 行。

① 一组"每次交东西之前跑一遍、任何一项不过就把这一版挡下来"的自动检查；
它读的是已经跑完构建产出的那些报告，自己不重新跑构建。
*简化说法，会在"以为绿了就等于一切都对"的情形下误导你 ——
它把"判红"与"今天没判"分成两种退出，未判的项不算通过，精确版见下一层。*
② 没有它会看到：构建还在跑就念门禁、念到的是上一版的数字而七项照样全绿 ——
这条坑写在 `build/gates.sh:39`（2026-09-23 那次）；另一面是"产物之间一致但整批都比 RTL 旧"，
写在同文件 `:55-56`（2026-09-24 那次，全套报告都是 30 分钟前的、七项全绿）。
③ 口径（出处就是脚本本身，核对日期 2026-10-05）：`build/gates.sh:6` 自述"一条命令读回门禁清单，并和阈值比"；
条数不写死，以脚本里 `say` 的调用次数为准（`:7-13`，原话"这里**不再写死条数**"）；
`say` 与"未判"两种记录分别是 `:179` 与 `:184`；退出码全绿 0、任一红 1（`:26`）；
末行三态在 `:586`（`GATES: 有红项（判定 N 项）`）、`:588`（`GATES: PARTIAL —— 判定 N 项全过，但有 M 项因缺凭据未判……
这一版不作"过门禁"`）、`:590`（`GATES: ALL PASS（N 项全部判定）`）；
读目录可选（`build/` 或某组成套冻结件）在 `:29-33`。
④ 它不是时序报告（那份只描述当前那次实现），也不是 Vivado 的 DRC/methodology 检查（门禁**读**它们的产物）；
也不是"跑一遍台架"。可观察的差别：`build/gates.sh:174-175` 那句 ——
结尾那句 `ALL PASS` 只有在"没有一项因缺席而没判"时才允许出现，因为下游 `freeze_evidence.sh` 就 grep 这个串。
⑤ 辨认方法：任意一份 `*gates*.txt` 的**最后一行**——`GATES: ALL PASS` / `GATES: PARTIAL` / `GATES: 有红项`
三选一（`:586-590`）；判据要念成最后一个字段才算判定，`PARTIAL` 不许当"过"。

小结 1：本表现在 53 条。第 3 层带未核实标记的是第 1、3、22 条（旧写法 `【未核实】`）与
第 27、28、36、37、38、39、40、43、44、50、51、52 条（新写法 `【未核实·正文未取到】`，
外部规范或单位制条目本轮没抓到，检索词逐条写在各条 ③ 层末）；
其余各条的第 3 层都能靠**本机手册的具体页**或**仓库里的 文件:行**站住。
本机手册共四份，全在 `D:/Xilinx/Resource/` 下，核对日期一律 2026-10-05：
`ug471_7Series_SelectIO.pdf`（v1.10，2018-05-08）、`ug472_7Series_Clocking.pdf`（v1.14，2018-07-30）、
`ug585-Zynq-7000-TRM.pdf`、`ds187-XC7Z010-XC7Z020-Data-Sheet.pdf`（v1.21，2020-12-01），
外加 `ug949-vivado-design-methodology-zh-cn-2026.1.pdf`（页脚自署 v2024.2）与板上那颗 PHY 的数据手册。
页码一律按"用 pypdf 取到的那一页"给（第 29、30、31 条那种页脚可核对：那些页的页脚印着同一个印刷页码）。
小结 2：第 25~53 条是 2026-10-05 按两轮回述测试（`_feedback/recall-run-a.md` 与 `-b.md`）点名的断点补的，
每条的**正文首见**那一行就是补它的理由；第 3 节剩下的仍未收。下一步：第 3 节。

## 第 3 节 本表未收全清单（W14 红项）

下列名词在本目录正文里出现过，但**尚未**按五层收条；已排进 `_progress.md` 的下一批：

`RGB565`、`TMDS/HDMI`、`OSD`、`RGMII/GMII/PHY/MAC`、`FCS/CRC32`、`ARP/ICMP/UDP/IP`、
`AXI GPIO`（那只 IP 本体；HP0 与 GP0 两个端口已收，见词条 25、26）、`JTAG / hw_server / xsdb`、
`台架（testbench）`、`裸机固件`、`上位机`、`片源`、
`分割线（缝）与标记线`、`阈值二值化 / 腐蚀 / 膨胀 / Sobel / gamma`（正文只在两处点名，未展开五层）、
`环境变量`（正文按名字使用，含义在 `hands-on.md` 第 1 节就地解释过）、`越界（oob）`、`采样沿`。

一句判据：这 17 组里任何一组被你在正文里当成"读者已知"使用，都是本篇的缺陷，不是读者的问题。

本轮（2026-10-05）从这份清单里**搬走**的六组，以及搬去的条目号，逐个列出来免得念成"清单没变短"：
`AXI GPIO / HP0 / GP0` 里的两个端口号 → 词条 25、26；`位流 / XSA / ELF` → 词条 50；
`综合 / 实现（布局布线）` → 词条 48、49；`门禁` → 词条 53；`md5 指纹` → 词条 51；`lane 回读` → 词条 52
（正文里的成词是"lane 读回"，两条写法在这里并成一个概念）。
同一轮另外补进 第 2 节 的是 **21 条**（词条 27~47，对应 20 个词组 —— `directive` 与 `strategy` 拆成 46、47 两条）：
`BD`（27）、`AXI 从设备`（28）、`BUFG`（29）、`BUFIO`（30）、`MMCM`（31）、`VCO`（32）、`IDDR`（33）、
`IDELAY`/`IDELAY_VALUE`（34）、`tap`（35）、`ps`（36）、`异拍`（37）、`准静态`（38）、`影子值`（39）、
`整字写回`（40）、`strap`（41）、`set_bus_skew`（42）、`performance extent`（43）、`Multi-Boot`（44）、
`phys_opt`（45）、`directive`/`strategy`（46、47）。这 21 条原先不在本表里，也不在上一版这份清单里
—— 清单只记"正文用过而表里没有"的那一批，这一批是回述测试点名的断点
（`_feedback/recall-run-a.md` 断点清单第 2、3、4、6、10 条与 `_feedback/recall-run-b.md` 的断点清单）。
两条路加起来正好是本批新增的 29 条（词条 25~53 = 上面那 6 组的 8 条 + 这 21 条）。

## 第 4 节 自测题

题目：**"三级同步器"与"翻转位 + 三级"这两条，在本工程里分别用在什么信号上？判断依据是什么？**
本文第 4、6 条给了形状，但**没给"我该怎么决定用哪个"的判据**。要拿到判据，请去查：
`src/rtl/video/frame_commit_lock.v:100-109`（那句"电平型 3 级同步在这里并不能修好它"）与
`src/rtl/top/pl_video_top.v:482-489`（同一件事在顶层的落地形状），
再看 `skills/rtl/cdc-and-async-discipline/SKILL.md` 第 2 节那几条"什么时候才用它"的触发条件。
