# 00 · 读这个项目之前要先会什么

这一章不讲本项目的功能，只讲门槛：一个"会写 C、学过数字电路、没碰过 FPGA 时序与跨时钟域"
的人，在读后面八章之前需要建立哪些概念，以及每个概念在本仓库的哪一行代码里真的咬过人。

每一小节固定四块内容：

1. **为什么要它** —— 不知道这件事会在后面哪一句上读不通；
2. **原理** —— 推到能自己算出结论的程度，不写"显然"；
3. **本仓库在哪一处** —— 给 `文件:行`，行号是这一轮逐个 grep 确认过的；
4. **你可以自己验证** —— 一条命令或一个五到二十分钟的小实验。

不需要先把这一章全部读完再往下走。更有效的用法是：读到后面某一句看不懂，回到这里按
目录找到对应小节，把那一节的四块一次看完。

阅读前提：本仓库是一颗 Zynq-7020（`xc7z020clg484-2`）上的工程，PL 侧做
"网口/SD 卡/片内图卡 → DDR 乒乓帧缓存 → 几何变换与效果链 → HDMI 1024×600"，
PS 侧跑一个裸机 Arm 程序发命令与读计数。全工程的骨架见 `01_project_map.md`。

---

## 目录

| 节 | 主题 | 不读它会卡在什么地方 |
|---|---|---|
| 1 | 组合逻辑 / 时序逻辑 / 多驱动 | 看不懂为什么一段代码要拆成两个 `always` |
| 2 | Verilog 真正会咬人的六处 | 判据"看起来过了"其实从没执行 |
| 3 | 有效数据使能与视频时序 | 全项目最高频的名词，以及两个缺陷的根 |
| 4 | 建立保持、时钟域与四种跨域做法 | 看不懂 `ASYNC_REG`、格雷码、翻转位 |
| 5 | 流水线与延迟记账 | 看不懂"标签必须与内容同级" |
| 6 | 定点数：没有除法、没有浮点 | 所有算术小节都读不动 |
| 7 | 片上存储：BRAM / LUTRAM / DDR | 看不懂"不能开第二个读口" |
| 8 | AXI 与 Zynq 的软硬件边界 | 分不清 PS 的寄存器与 PL 的 DDR 地址 |
| 9 | 嵌入式 C 与裸机启动 | 固件章读不动 |
| 10 | Tcl / bash / node 三种脚本 | 不知道怎么把工程跑起来 |
| 11 | Vivado 报告的读法 | 门禁清单上一行数字都看不懂 |
| 12 | 先量后修的工作方式 | 不理解代码里为什么有那么多"多余"的钳位 |

---

## 1. 组合逻辑与时序逻辑，以及"同一根寄存器两个进程写"

**为什么要它。** 后面所有章节里，凡是出现"晚一拍""同一拍""打两拍"的说法，前提都是分得清
`always @(posedge clk)` 生成的是触发器、`always @(*)`（或 `assign`）生成的是连线。
如果这两类东西混不起来，"延迟 20 拍"就只是一个记不住的数字。

**原理。** 综合器看一个信号在什么时候被赋值来决定它是什么：只在时钟沿赋值 ⇒ 触发器；
按输入变化赋值 ⇒ 组合网络。由此推出三条硬规则：

- 组合网络里不能有环路（`assign a = b; assign b = a;`），否则时序分析无法收敛；
- 一个触发器的输入只能是组合值或别的触发器的输出，不能"半个周期变一次"；
- **同一根信号只能有一个驱动源**。两个 `always` 都往同一根 `reg` 里写，综合直接报多驱动
  （本仓库把它记成判据 `多驱动 net 8-685x`，见 `build/gates.sh:179-197`）。

第三条最容易在"想给一段逻辑加个复位"的时候踩到：RAM 与其读出通常故意不复位（省复位布线），
如果为了别的目的写了一次复位，那个 `always` 块就得把整段读出逻辑一起搬过去。

**本仓库在哪一处。** 最典型的是 `src/rtl/video/raw_line_delay.v`：

- `raw_line_delay.v:80-83` 一个不带异步复位的 `always` 里同拍做"写本行本列"和"读 N 行之前的同一列"；
- `raw_line_delay.v:86-94` 另一个带复位的 `always` 里只写 `v / look / head_q` 三根寄存器；
- 两处之间隔着一段专门的警告注释：`raw_line_delay.v:84-85`
  ——「`look/head_q` 只许在这**一个** always 里写……把同一根寄存器分给两个进程综合会直接报多驱动」。

**你可以自己验证。** 跑一次端口/网表静态判据，它就顺带把这类结构问题挡在门外：

```bash
python build/check_ports.py            # 端口名、悬空输入、位宽；本仓库是门禁第 14 项
grep -n "多驱动" build/gates.sh         # 看这条判据是怎么被写进门禁的（Synth 8-6859/8-6858）
```

想亲眼看见多驱动长什么样，就在 `raw_line_delay.v` 里把 `head_q <= q;` 那一行复制到上面那个
不带复位的 `always` 中，跑 `bash sim/run_one.sh tb_v100_raw_delay`，编译器会拒绝。看完记得改回去。

## 2. Verilog 真正会咬人的六处

**为什么要它。** 项目里至少有六个缺陷不是"想法错了"，而是"语言细节让错的东西看起来很正常"。
下面每一条都在本仓库留了痕迹，读到相关章节时回来看这一节会更省力。

### 2.1 位宽隐式截断：不报错，只少算

`wire [1:0] line` 接一个值域 0..4 的行号，综合与时序报告全绿，屏幕上是"第 5 行永远取不到"。
本仓库把这句话直接写进了注释：`src/rtl/video/osd_overlay.v:88-90`
「行号位宽必须跟着 `N_LINES` 走：写死 [1:0] 时加到第 5/6 行屏幕上永远取不到，
而综合与时序报告全绿 —— 这种错只有屏能看见，工具链不报」。

同一个坑换了个外衣出现在别处：

- `src/rtl/eth/link_monitor.v:39-42`：毫秒分频器的位宽必须从参数算出来
  （`localparam integer DW = $clog2(TC + 1);` 在 `link_monitor.v:42`）。原来写死 `[15:0]`
  装不下 125000，于是 `ms_div == TC-1` 恒假，整套毫秒级统计在板上全死；仿真时把 `CLK_HZ`
  改成 1000（`TC=1`）完全看不出来。取证方式是综合日志里那句
  `WARNING [Synth 8-6014] Unused sequential element ms_div_reg was removed.`。
- `src/rtl/top/system_top.v:208`：lane 读回口的位宽必须与 `pl_video_top.dbg_src` 一模一样
  （r54 起是 16 bit），以前写过 `[5:0]`，综合只给一条警告。

**验证**：`grep -n "clog2\|\$clog2" src/rtl -r` 会看到本项目凡是"位宽跟着参数走"的地方都留了注释。

### 2.2 `integer` 与未初始化 RAM 在仿真里是 X

仿真里标量 `reg` 默认 0，`integer` 与数组元素默认是 X。X 参与任何比较结果都是 X（不成立），
于是"判据一条都没红"和"判据一条都没跑"打印出来的字是一样的。本仓库的对策有两类：

- 台架侧：把 RAM 显式清零，或者把"这条没有效"写进判据本身。
  `src/rtl/video/raw_line_delay.v:53` 那句 `initial for (...) mem[m] = {DW{1'b0}};`
  存在的全部理由就是"别让台架看到 X"。
- 硬件侧：宁可画 `--` 也不画一个没测到的数，见 `osd_overlay.v:43`（`lat_ok=0`）与
  `src/rtl/process/effect_ctrl.v:45-48`（温度复位值 `32'h0000_00FF`，两个半字节都不是十进制数字
  ⇒ 屏上画 `Temp:--`，而不是上电先画一个 `00C`）。

### 2.3 参数是 32 位整数，切片要先生出一个定位宽的 `localparam`

`W[3:0]` 这种"直接切一个参数"的写法在不同工具里待遇不同，本仓库的做法是先 `localparam`
再切。同时要注意 `localparam integer` 与 `localparam [3:0]` 的位宽差别会一路传到例化处的
位宽检查里（门禁第 14 项正是判这个）。

### 2.4 `function` 只能是组合逻辑，`task` 里读的信号不进敏感表

`function` 综合出来就是一张组合表；放在关键路径上，它就是整个设计最差的那条链。本项目的
OSD 字形译码原来就是这样一条深组合链，后来把"字格几何"算完先寄存一拍
（`osd_overlay.v:71-104`，注释里写清了原最差链是 29 级 + 9 个 CARRY4）。

`task` 的那一课更阴：`always @(*)` 的敏感表只收本块自己读到的信号，**任务体内读的不算**。
`osd_overlay.v:237-239` 因此要求 `put_src` 的 `se/md` 必须是任务入参而不是在任务里直接读切片，
否则"屏上永远留着旧名字"。这条被记进本仓库的坑编号 #92 同族。

### 2.5 端口先引用会造出隐式 net

Verilog-2001 允许一个从没声明的信号名自动成为一个 1 bit 线网。后果是"看着接上了，其实常 0"，
而后面再显式声明同一根线就成重定义。本仓库在两处立了规矩：

- `src/rtl/top/pl_video_top.v:169-171`：19 位几何控制字 `gp` 必须先声明再被下面的 `snap_cross` 驱动，
  原因是 `angle_ctrl` / `zoom_ctrl` 排在驱动它的那条之前；
- `pl_video_top.v:511-513`：`pub_new` 必须在例化 `ps_publish` 之前声明。

端口名拼错同理 —— 所以门禁第 14 项 `build/check_ports.py` 逐实例核对端口名、悬空输入与位宽。

### 2.6 快时钟域里不做算术

这条严格说属于时序，但它表现得像语言问题，所以放在这里。`clk_pix5x` 周期 4 ns，
而慢域触发器的输出最早只能在下一个快沿被采走，跨进快域的那一拍只有 4 ns 预算。
`src/rtl/process/bilin/tap_sched.v:43-47` 把这笔账写全了：
"快域做 base+ROWW 加法再进 5:1 mux"实测需要约 5.3 ns（WNS −1.277、1400 个失败端点），
于是四个抽头字号与左窗字号全部在慢域算好并各自打一拍，快域只做一次 5 选 1。
这条纪律"是有门的，门就是 timing_summary"。

**你可以自己验证。** 一次就能同时看到 2.1 与 2.6 的写法：

```bash
grep -n "clog2\|ASYNC_REG\|ram_style" src/rtl/eth/link_monitor.v src/rtl/eth/dc_fifo.v
sed -n '40,50p' src/rtl/process/bilin/tap_sched.v
```

## 3. 有效数据使能与视频时序

**为什么要它。** 这是全项目用得最多的概念。后面每一处"错位""竖带""黑纹"的讨论，
根都在这一节的两个事实上：只有 `de` 高电平那几拍是真像素；消隐期计数器照样在走。

**原理。** 一个显示接口每一行输出的时钟拍数比有效像素多，多出来的部分叫消隐，
分成前肩、同步脉冲、后肩三段；每一帧比有效行多的那几行叫竖直消隐：

```
      <--------------- H_TOTAL = 1344 个像素时钟 --------------->
      |-- H_ACTIVE 1024 --|-- 前肩 44 + 同步 88 + 后肩 188 = 320 --|
de ____|██████████████████|________________________________________|____
hs ________________________|‾‾‾‾‾‾‾‾‾|_______________________________     ← 同步在消隐中间
      ^h_cnt=0                                                    ^h_cnt=1343
```

一帧 625 行里只有 600 行有效（前肩 3 + 同步 6 + 后肩 16 = 25 行竖直消隐）。
把两个总数乘起来：`1344 × 625 × 60 Hz ≈ 50.4 MHz`，这就是像素时钟取 50 MHz 的理由
（刷新率因此约 59.4 Hz，`src/rtl/video/video_timing_1024x600.v:2-4` 明确写了
"spec 50.25 MHz, 0.5% ok"）。

本项目在哪一处：

- 参数正本：`src/rtl/video/video_timing_1024x600.v:17-20` —— `H_ACTIVE(1024)`、`V_ACTIVE(600)`、
  `H_FP(44) H_SYNC(88) H_BP(188)`、`V_FP(3) V_SYNC(6) V_BP(16)`，同步极性 `H_POL=1`、`V_POL=0`；
- 发生器本体：`src/rtl/video/video_timing.v` —— 两个自由运行的计数器 `h_cnt/v_cnt`
  （`video_timing.v:32-47`，`v_cnt` 只在 `h_cnt` 回绕那一拍加一，见 `:37` 与 `:42`），
  组合出 `hs_act/vs_act/de_act`（`:49-51`），再统一打一拍输出
  （`video_timing.v:53-70`，其中 `x <= h_cnt` 在 `:63`）。
  这一拍延迟不是随手写的：它让"行首那一拍"与"`y` 加那一拍"的先后次序固定下来，
  而 `raw_line_delay.v:68-72` 的预读逻辑直接依赖这个次序。

两个真实缺陷的根都在"消隐期计数器继续走"：

1. **行首那一格读到消隐期的地址。** 一行 1344 拍里有效列只有 1024，尾部 320 拍里 `x` 从 0 数到 319，
   而 RAM 读出的是上一拍发出去的那个地址 ⇒ 下一行第一个有效列摆出的恰好是消隐期最后那个格子。
   推导写在 `raw_line_delay.v:58-62`，修法（掉进消隐那一拍做一次预读）在 `:68-76`。
2. **竖直消隐把行环的槽位相位挪走。** 环深是 8 行，而 `V_TOTAL=625` 不是 8 的整数倍，
   那 25 行消隐会把"第 y 行该读哪个槽"的对应关系推歪，所以"消隐期读地址一律钳到 0"这种
   看起来更简单的修法不行 —— `raw_line_delay.v:77-79` 把这条推演写全了。

**你可以自己验证。** 两件五分钟内能做完的：

```bash
grep -n "H_ACTIVE\|V_ACTIVE\|H_FP\|V_FP" src/rtl/video/video_timing_1024x600.v   # 亲手加一遍 1344 / 625
bash sim/run_one.sh tb_timing        # 数 `de` 每帧高 1024×600 次、周期 1344×625
```

再手算一次带宽账：显示侧每拍要一个像素 ⇒ 50 M 像素/秒；一帧拷贝要在竖直消隐的
25 行 × 1344 拍里搬完 600 行 × 512 个 64bit 字，本仓库把这个预算写成了
`VBLANK_AXI_CYC = 32'd67200`（`src/rtl/top/pl_video_top.v:401`），超了就点亮
`copy_overrun`（`:402-406`）并让 LED 改成快闪（`:983`）。

## 4. 建立/保持时间、时钟域与四种跨域做法

**为什么要它。** 本工程里同时跑着六股时钟：板晶振 50 MHz、MMCM 出来的像素 50 MHz 与 250 MHz、
IDELAY 参考 200 MHz、PHY 恢复出来的 125 MHz、PS 送进 PL 的 100 MHz。
只要一段逻辑跨了两股，"打两拍"就不再是可选的好习惯，而是数据正确性的前提。
后面第 30 章逐个列这些边界，这一节先把词汇与四种做法讲清。

**原理（亚稳态）。** 触发器要求在时钟沿之前的一段时间（建立）与之后的一段时间（保持）里输入不动。
当输入来自另一股异步时钟，它可能在采样沿正在变化，于是触发器输出停在一个不确定的电平上，
并且**在下一个沿之前谁都可能读到它**。这就是亚稳态。它的两个可操作结论：

- 单 bit 可以用"打两拍"把出错概率压到工程上可忽略：第二级在"第一级已经稳定"的窗口里采样的
  概率极高，平均无故障时间 MTBF 随同步级数指数改善。所以同步器要标
  `(* ASYNC_REG = "TRUE" *)`，否则综合会把两级合并成一级、把保护优化掉；
- **多 bit 总线不能各打各的两拍**：16 个数各自新旧不一，读回来可能是"半新一半旧"的合成物。
  于是需要别的机制。

本仓库用到四种做法，各自的适用条件都写在代码里：

| 做法 | 适用对象 | 本仓库的出处 |
|---|---|---|
| 2~3 级 `ASYNC_REG` | 准静态单 bit 电平 | `pl_video_top.v:208-217`（`zoom_en`）、`:254-261`（`bilin_en`）、`src/rtl/process/effect_ctrl.v:34-42`（三对同步器） |
| 脉冲 → 翻转位 + 目的域边沿检测 | 一次事件（按键长按、帧提交、拷贝中止） | `pl_video_top.v:144-146`（`key_long` 出 `ltog`）、`:435-444`（`abort_tgl` 3 级 + 异拍）、`src/rtl/util/ps_publish.v` |
| 准静态总线 + 跳变沿（`snap_cross`） | 一帧内不变、由一侧整拍写入的宽总线 | `src/rtl/eth/snap_cross.v:1-8`（契约原文）、`src/rtl/top/system_top.v:198`（320 bit 健康快照 → axi 域）、`pl_video_top.v:821`（19 bit 几何控制字 → 像素域）、`:925`（18 bit 时延 → 像素域） |
| 格雷码指针异步 FIFO | 真正的流数据 | `src/rtl/eth/dc_fifo.v`（`dc_fifo.v:20` 存储强制 BRAM；指针格雷码 + 双级同步 `:22-24`），实例在 `src/rtl/eth/eth_udp_video_top.v:294`（36 bit × 8192） |

这里有一条本仓库反复付学费的规矩，值得提前知道：**同一个翻转位不许扇出到两组目的域同步器**。
两个目的域各有一对同步触发器去采同一个翻转位，就会被 CDC 工具判成
`CDC-11 Critical`。`pl_video_top.v:228-234`（自动旋转的帧首翻转位）与 `:916-924`
（时延心跳另起一个触发器）两段注释写的都是这件事，判据是门禁第 6 项
（`build/gates.sh:79-136`：与 `build/CDC_BASELINE.txt` 的**配对集合**比，新增配对或 unsafe 增长即红）。

**你可以自己验证。** 看一条格雷码 FIFO 真的只在两端各同步指针：

```bash
sed -n '20,84p' src/rtl/eth/dc_fifo.v
bash sim/run_one.sh tb_sync_fifo          # 台架自己会验空满与指针回绕
```

再跑一次变异检验的"反面教材"：把 `effect_ctrl.v:34` 那三对里的 `(* ASYNC_REG = "TRUE" *)`
删掉，重新综合，看 `build/cdc.rpt` 里对应的 unsafe 端点数怎么变 —— 这正是第 6 项会抓的东西
（看完记得改回去，并用 `md5sum src/rtl/process/effect_ctrl.v` 确认自己改回去了）。

## 5. 流水线与延迟记账

**为什么要它。** 本项目最容易被忽略也最容易出事的知识点。约定是：**说"延迟 N 拍"必须能说出
这 N 拍花在哪些 `reg` 上**，并且凡是跟它比相位的信号都要按同一个 N 记账。
图像流水线里"内容"与"关于内容的标签（列号、行号、有效标志、越界标志）"必须站同一拍，
差几拍就是一条看得见的竖带。

**原理与算法。** 一个读口型的存储器，请求到数据之间固定的有几拍：地址先打一拍（1）+
BRAM 内部输出寄存器（1）。本项目的混合级总延迟是这样组成的
（`src/rtl/top/pl_video_top.v:306-309`）：

```
MIX_D = 3(打地址到 mapper 与两条抽头的打拍) + 1(读地址寄存) + 1(BRAM 读出) + u_pipe.LATENCY(15) = 20
```

`LATENCY` 只有一个合法出处，就是效果链自己声明的那个数（`src/rtl/process/proc_pipeline.v:19`），
它上面的注释把 15 拍逐段拆开：灰度 1 + 反色 1 + 模糊 3 + 锐化 3 + Sobel 3 + 阈值 1 + 形态学 3 = 15
（`proc_pipeline.v:14-15`）。三个窗口级各是**三拍**而不是两拍，因为 `de` 链是
`de_in → d1 → d2 → de_out` 三级寄存器（`proc_pipeline.v:16`）。
级 0 的 gamma 是分布式 RAM 的组合读出，**不占拍**（`proc_pipeline.v:18`）。

有了 `LATENCY` 这一处定义，其余三处都从它推：

- 混合级 `MIX_D`（`pl_video_top.v:309`）；
- 原图那条抽头的 skid 长度 `PROC_LAT = u_pipe.LATENCY`（`pl_video_top.v:761-762`）；
- 图像域分割线的抽头号 `SEAM_TAPS = MIX_D + 1 - 3`（`pl_video_top.v:847`，默认值同样写在
  `src/rtl/video/seam_src.v:9`）。

三条真实缺陷都来自"记账记漏了一处"：

1. **标签比内容旧 9 列。** `split_display` 判"这一格给原图还是给处理图"用的是列坐标，历史上那里
   用的是第 11 级标签而内容是第 20 级 ⇒ 缝左边约 9 列里标签说"左窗"、内容其实是"被清 0 的那一路"，
   屏上出现一条近黑竖带。正本注释在 `src/rtl/video/split_display.v:10-15`，修法是把
   `x_sel` 与整束 `x/y/de/hs/vs` 一起提到 `MIX_D`（`pl_video_top.v:858-866`）。
2. **两条抽头不等深差一整拍。** 原图一路是"行环 1 拍 + skid 15 拍"，链子只有 15 拍
   ⇒ 处理抽头早一整拍 = 混色级早一整列；1.00x 铺满屏看不出来，一缩小就把画面自己最左那一列
   甩进背景带。注释与凭据在 `pl_video_top.v:764-774`（那里最后多打了一拍 `pipe_dout_q`）。
3. **越界标签绕过行环。** 像素过环（4 行 + 1 拍）、`oob` 只走等长 skid ⇒ 到混色级两者差
   (4 行, 1 列)，表现为"上边缘有东西闪"。教训直接写进模块端口注释
   （`src/rtl/video/raw_line_delay.v:11-16`），修法是标签与像素打包成 17 位一起过环
   （`pl_video_top.v:727-737`）。

**你可以自己验证。** 这一节有三条不碰硬件、不碰板子就能跑的尺子：

```bash
bash sim/run_one.sh tb_v86_pipe_sel     # 实测 de_in→de_out 的拍数，并与 LATENCY 声明值对账
bash sim/run_one.sh tb_v89_align        # 四个窗口级的内容滞后与 off_rows 对账
```

`tb_v86` 的价值在于它是"实测"而不是"照抄声明"：任一处漂移（有人在链上加了一级而忘了改
`LATENCY`，或者顶层自己另写一个数）都会当场红一条。

## 6. 定点数：没有除法、没有浮点

**为什么要它。** 图像算法的教科书写法里全是除法与浮点：加权平均、除以 9 的均值、
双线性插值的权重、缩放的比例因子。FPGA 里没有浮点单元也没有硬件除法器
（这颗 7020 只有 220 个 DSP48，而且每个乘法器只能做一次乘加），所以一切除法都变成
"乘一个倒数 + 移位"，一切小数都是 Q 格式。不懂这层翻译，看后面的算术代码就会觉得"莫名其妙少了两位"。

**原理。** Q10.6 这类记法的意思是：16 bit 里高 10 位是整数部分、低 6 位是小数部分，
一个无符号数 `v` 的真值是 `v / 2^6`。两个 Q10.6 相乘得到 Q16.12，取回 Q10.6 就是右移 6 位
（本项目的做法是"在需要的位上切片"，见下面 blur 那一处）。
除法 `x / 9` 的替身是 `x * (1/9)`，把 `1/9` 写成分母为 2 的幂：`57/512 = 0.1113` vs `1/9 = 0.1111`，
误差约 0.2 % ⇒ 乘 57 再右移 9 位。什么时候必须饱和、什么时候可以截断，取决于这个数后面
还要不要参与减法（截断会把越界变成回绕，回绕在图像上就是一圈亮边）。

**本仓库在哪一处（四处，逐个给位宽）。**

- **灰度**（BT.601）：`0.299R + 0.587G + 0.114B` 翻译成整数乘 77/150/29 再取高 8 位
  （`src/rtl/process/proc_gray.v:19-21`）。RGB565 展开到 8 bit 用**位复制**而不是左移补零：
  `{r5, r5[4:2]}`（`proc_gray.v:16-18`），这样全 1 展开正好 255，纯白不会因为展开变灰。
- **均值模糊**：三个 3×3 求和（5bit×9 = 9bit、6bit×9 = 10bit，`src/rtl/process/proc_box_blur.v:102-111`），
  再 `× 57 >> 9 ≈ /9`（`proc_box_blur.v:113-119`）。
- **Sobel**：`gx/gy` 是 11 bit 有符号（`src/rtl/process/proc_sobel.v:108-111`），
  取模用"符号位判一下再取负"（`:112-113`），幅值用 `|gx| + |gy|`（`:114`，省掉平方与开方），
  再夹到 255（`:115`）—— 这一处**必须**饱和，因为截断会让强边缘变成弱边缘。
- **缩放/旋转的逆映射**：倍率用 Q8 的倒数 `inv_scale` 表示，256 = 1.0x、512 = 0.5x
  （`src/rtl/process/zoom/zoom_ctrl.v:2-4` 与 `src/rtl/process/zoom/zoom_mapper.v:2-3`），
  三角函数查 360 项 Q8 表（`src/rtl/process/rotate/sin_rom.v:2-3`：`round(sin(θ)×256)`，有符号 10 bit）。
  双线性插值的权重也是 Q8：`fx/fy ∈ [0,255]` 表示 [0,1) 的小数，两两权重之和恒为 256，
  于是横向积 ≤ 255×256 = 65280（17 bit 封顶）、纵向 ≤ 255×65536 + 舍入 = 25 bit ⇒ **不需要饱和**，
  而"不需要饱和"这件事由台架判据"四角同色 ⇒ 输出恒等"强制检验（`src/rtl/process/bilin_lerp.v:4-6`）。
- 还有一条贯穿全工程的硬件规矩：**运行时不做除法与取模**。所有必须除的地方要么除掉的是
  2 的幂（切位），要么除数是 elaboration 常数（综合折成接线），要么把商与余数分两拍算。
  OSD 里那两处 `lat_v / 100`、`lat_v % 100` 分成两拍（`osd_overlay.v:160-173`），
  注释里连代价都记着：一次算三位在 50 MHz 像素域是二十几级组合链，WNS 到过 −6.765。

**你可以自己验证。** 一条命令就能看见"倒数近似"的误差到底多大：

```bash
node src/host/interp_study.mjs      # 在真实的 inv 区间 256..512 上算插值收益，纯离线算术
awk 'BEGIN{printf "1/9=%.6f 57/512=%.6f 误差=%.3f%%\n",1/9,57/512,(57/512-1/9)/(1/9)*100}'
```

## 7. 片上存储：BRAM、LUTRAM、DDR

**为什么要它。** 视频工程是内存工程。一帧 512×300×2 B = 307200 B 装不进片内，
于是必须去 DDR 走一圈；而 3×3 滤波又要"邻域"，一行缓冲比整帧便宜得多。
分不清这三层，就看不懂"为什么只许一个读口""为什么环深是 8 行""为什么 FIFO 要标 `ram_style`"。

**原理与容量账（7020 的真实预算）。**

| 载体 | 特点 | 本项目用在 |
|---|---|---|
| BRAM（块 RAM） | 硬宏，双端口，18 Kb 一块；全片 140 个 RAMB36 tile | 显示帧缓存、行缓存、CDC FIFO |
| LUTRAM（分布式 RAM） | 用查找表当 RAM，省 BRAM 但吃 LUT，位宽/深度都受限制 | 打包 FIFO（512 条 × 100 bit 量级） |
| DDR3（片外） | 大，但要经 PS 的 HP 口 + AXI 才能进，带宽与时延都要排队 | 乒乓双 bank + PS 专用第三 bank |

一条必须记住的实测结论：**同一组存储阵列上再加一个逻辑读口，会把块数翻倍**。
本项目的帧缓存加第二个读口实测从 80 块 RAMB36 顶到 160 块，而全片只有 140 块 ——
这句话写在 `src/rtl/top/pl_video_top.v:722-723`（原图抽头为什么改用行延迟环而不是开第二个读口）
和 `src/rtl/process/bilin/tap_sched.v:9-10`（每像素周期 5 槽为什么刚好占满、不许再加）。
所以"读两遍"的方案在这里都不是免费的：本仓库的解法是分时（一拍只读一个字）+ 复制一份标签一起走。

LUTRAM 那一课写在 `src/rtl/eth/axi_frame_saver64.v:9-13`：512 条 × 100 bit 的打包 FIFO
如果被推成触发器，就是约 5.1 万个 FDRE，占整机 Slice 寄存器的 94 %，深度参数一改直接
DRC UTLZ-1。强制成分布式 RAM 之后释放出来的正是那几万个触发器。BRAM 那一路的写法在
`src/rtl/eth/dc_fifo.v:20`（`(* ram_style = "block" *)`）与
`src/rtl/process/proc_box_blur.v:18-19`（两条 16 bit 行缓存）。

今天板上的实际占用可以在门禁清单里读到（`BRAM 97.5 %`、`Slice LUT 28.27 %` 这类数），
项名见 `build/gates.sh:66-72`；**数字本身要念哪一版，看 `report/PERF_REPORT.md` 点名的那一份冻结件**，
本套文档不抄数（抄了就必然出现"两处各说各话"，这一天真的发生过，见 `report/log/ISSUES.md` #88）。

**你可以自己验证。** 两块不同的存储各自怎么被推断出来，读一眼就明白：

```bash
grep -rn "ram_style" src/rtl | sort          # block（BRAM）与 distributed（LUTRAM）各出现在哪
bash sim/run_one.sh tb_v100_raw_delay        # 行环：延迟恰 = LINES 行 + 1 拍且列不偏
```

顺手算一遍行环的容量账，能理解为什么环深必须是 2 的幂：`LINES=4 ⇒ RLOG=clog2(4+1)=3`
（`src/rtl/video/raw_line_delay.v:41`），环 8 行 × 每行 W 列，槽位选择就是切 `y` 的低 3 位，
不留运行时取模（`raw_line_delay.v:37-38`）。

## 8. AXI 与 Zynq 的软硬件边界

**为什么要它。** 这颗芯片里 Arm 与可编程逻辑共用同一份 DDR。谁发起、走哪个端口、
位宽与突发多长、缓存要不要刷 —— 这四问没搞清楚，就读不懂"网口进来的字节 PS 完全不碰"
这句本项目最要紧的话。

**原理。** Zynq-7000 给 PL 两类通道：

- `M_AXI_GP0`：AXI-Lite，32 bit、单拍，PS 主动写 PL 里的寄存器（或反过来读）。
  本项目三只 GPIO 挂在它下面：**控制面**全在这条路上。
- `S_AXI_HP0`：AXI-Full（本设计是 AXI3：`ARLEN/AWLEN` 只有 4 bit，最长突发 16 拍），
  64 bit 宽，PL 作为主设备直接读写 DDR。**数据面**全在这条路上。
  长度位宽这件事写在 `src/rtl/top/system_top.v:72`（`wire [3:0] m_awlen_axi3 = m_awlen[3:0];`）
  与 `:89`、`:94`（BD 的 `M_AXI_HP0_arlen / awlen` 接的都是那个 4 bit 版本）。
- DMA 与 CPU 缓存不一致：CPU 写进缓存的行不会自动出现在 DDR 里，DMA 读到的可能是旧数据。
  裸机程序必须显式 `Xil_DCacheFlushRange / InvalidateRange`。

**本仓库在哪一处。** 先把两类地址分清楚（这是旧版本文档搞混过的地方，见 §12）：

| 名字 | 值 | 是什么 | 出处 |
|---|---|---|---|
| `axi_gpio_0`（`gpio_o`） | `0x4120_0000` | PS→PL 的 32 bit 控制字（阈值/片源/缩放/发布位/lane 号） | `src/ps/main.c:47` |
| `axi_gpio_1`（`GPIO_1_tri_i`） | `0x4121_0000` | PL→PS 的 32 bit 状态窗口（先写 lane 号再读这一字） | `src/rtl/top/system_top.v:45,84` |
| `axi_gpio_2` 通道 1 | `0x4122_0000` | 九位 `stage_sel` + 几何控制字 + 缩放档 | `main.c:71-72` |
| `axi_gpio_2` 通道 2 | `0x4122_0008` | gamma 表窗口 + 只给 OSD 的两个显示值 | `main.c:90` |
| ETH 乒乓双 bank | `0x1000_0000` / `0x1008_0000` | **DDR 地址**，PL 自己当主设备写 | `src/rtl/eth/eth_udp_video_top.v:67-68` |
| PS 专用 bank | `0x1010_0000` | **DDR 地址**，SD 回放/FILL 由 PS 的 DMA 写 | `pl_video_top.v:13`、`main.c:45` |

数据面那条链的完整形状：`frame_reasm`（125 MHz 域，判定"这一帧的每一行都写过了吗"，
`src/rtl/eth/frame_reasm.v:2-3`）→ `dc_fifo`（格雷码 CDC，`eth_udp_video_top.v:294`）→
`axi_frame_saver64`（16→64 bit 打包 + AXI3 写，写通道流水化后 ≤2 拍/字，
`axi_frame_saver64.v:2-8`）→ `ddr_bank_commit`（换页与提交，`eth_udp_video_top.v:326-327`）。
这里最值得记的一件事是"为什么必须把 AW/W 并行挂出"：在途深度恒 1 时，HP0 的写延迟（约 40 拍，
被显示拷贝抢端口时上百拍）直接成为吞吐上限 ≈20 MB/s，板上表现为"每包固定从第 48 字节起丢字"；
而**加深缓冲治不了它**，因为瓶颈是平均排空速率不是深度（同文件 `:6-8`）。

**你可以自己验证。** 一条命令看清"谁是谁的主设备"：

```bash
grep -n "M_AXI_HP0\|GPIO_0_tri_o\|GPIO_1_tri_i\|FCLK_CLK0" src/rtl/top/system_top.v | head
```

再读一次缓存一致性那处代码：`grep -n "Xil_DCache" src/ps/*.c` —— 那是 SD 回放这条 DMA 路的命门。

## 9. 嵌入式 C 与裸机启动

**为什么要它。** PS 这一侧没有操作系统。"上电 → BootROM → FSBL → 应用 main → 轮询 UART →
写寄存器"这条链是理解第 40 章的前提，也是理解"为什么屏上那个数字要 PS 先算成十进制再传"的前提。

**原理与本项目取舍。**

- 启动介质：演示与验收**只从 JTAG 下载**；把一版固化进板载 QSPI 是 2026-10-05 按要求另做的一次（`board/tcl/flash_qspi.tcl`）。三件套的顺序是有原因的：
  `xsdb build/tcl/ps_jtag_boot.tcl` → `vivado -mode batch -source build/tcl/program_pl.tcl` →
  `xsdb build/tcl/ps_app_reload.tcl`（见 `report/HOST_GUIDE.md` §1 与 `board/README.md`）。
  注意 `ps_jtag_boot.tcl` 含 `rst -system`，跑过它就必须重下位流；`ps_app_reload.tcl` 只
  `rst -processor`，位流与 GPIO 控制字不受牵连。
- 中断还是轮询：本项目主循环轮询 UART。理由是"命令是人在敲的，一秒几十次顶天"，
  而 SD 回放那条 DMA 路需要稳定的节拍，少一条中断服务路径就少一处抖动。
- 栈与放哪：链接脚本 `src/ps/lscript_ocm.ld:21-22` 把可用的两块片内 RAM 定义成
  `0x0000_0000`（192 KB）与 `0xFFFF_0000`，程序与栈都落在前一块 OCM 里。为什么不用 DDR：
  位流刚配置完、DDR 还没稳定时也要能起来跑命令。异常表跟着落在 `0x0`，
  这件事在构建脚本里被当成一条正确性检查（`build/ps_app.mjs:93`、`:154`）。
- 一个"链接成功却产出空镜像"的教训值得先知道：`--gc-sections` 曾把 `main` 与整个 SD 驱动裁光，
  产出一个 `.text = 80 B` 的 ELF 而编译器毫无报错（`build/ps_app.mjs:132`）。今天那条自检是
  `build/ps_app.mjs:145-147`：`.text` 小于 20000 B 直接 FATAL。**"构建成功"不等于"产物可用"**，
  这句话在本仓库不是一句修辞。
- 整字写回：`src/ps/main.c:188` 的 `ctrl_write()` 每次都从影子寄存器整字写出，不做读-改-写。
  原因写在 `main.c:88-89` 与 `main.c:267`：同一个 GPIO 里既放着 gamma 协议位又放着两个只给屏看的
  显示值，读-改-写会把别的位抹掉（编号 #55 那一族）。

**本仓库在哪一处。** 固件主体 `src/ps/main.c`（1525 行）+ SD 卡回放 `src/ps/sd_play.c`（878 行，
裸机 FAT32 簇链只读解析）。串口命令入口 `main.c:864`（`dispatch()`），帮助文本 `main.c:1349`，
九位算法控制字的宏在 `main.c:104-112`，位段的唯一事实来源是
`src/rtl/process/proc_pipeline.v:5-6`（RTL 侧），固件里那份只是抄一份并注明出处。

**你可以自己验证。** 不碰板子也能验命令口径：

```bash
node src/host/pipe_len_check.mjs        # `pipe` 这一条命令的九位/五位口径离线核对
node src/host/temp_formula_check.mjs    # 温度 BCD 与 OSD 显示之间那条换算
```

## 10. Tcl / bash / node 三种脚本各管什么

**为什么要它。** 工程的"跑起来"由三类脚本拼成：工具链本身是 Tcl 驱动的（Vivado、xsdb），
门禁与冻结是 bash，上位机与文档自检是 node。搞混了就会问"为什么构建入口只有一个"。

**各管什么（当前版本）。**

| 层 | 入口 | 说明 |
|---|---|---|
| 建工程 + 综合 + 实现 + 出位流 | `vivado -mode batch -source build/tcl/build_system_axigpio.tcl` | **唯一**构建入口；`build/tcl/` 里其它 `.tcl` 是它的辅助件或一次性重建脚本 |
| 读回门禁 | `bash build/gates.sh`（或 `bash build/gates.sh build/evidence_rNN`） | 只读已有报告并与阈值比，不重跑构建 |
| 冻结一套凭据 | `bash build/freeze_evidence.sh <NN>` | 两道硬门：门禁必须 `ALL PASS`，且台架报告的 `top_md5`/`rtl_md5` 必须还等于当前树 |
| 单个台架 | `bash sim/run_one.sh <tb名>` | 编译前盖三枚 md5；同一时刻只许一个 xsim 在写运行目录 |
| 全量台架 | `vivado -mode batch -source sim/run_sim.tcl` | 63 个 `sim/tb_*.v` 一起跑 |
| 板级机器验收 | `bash build/board_verify.sh --battery --geom` | 串口电池 + 几何自动化 |
| PC 侧工具 | `node src/host/*.mjs` | 推流、健康读回、DDR 回读比对、文档自检 |

关于"入口只有一个"这件事，本仓库踩过一个具体的坑：构建脚本用
`file dirname [info script]` 再往上跳两级来定位仓库根（`build/tcl/build_system_axigpio.tcl:2`），
所以**必须从 `build/tcl` 目录里以 `-source` 方式跑**；把某个辅助脚本单独复制出去跑，
它会把根算错一级，于是在 `add_files` 阶段就找不到文件 —— 而某些写法下它还会以 0 退出码结束，
看起来像"跑完了"。这就是第 50 章要专门讲一遍 Tcl 路径语义的原因。

上位机侧只依赖 Node.js 与 Windows 自带的 PowerShell（`report/HOST_GUIDE.md:3-10`）：
推流 `node src/host/video_sender.mjs`，真实视频用根目录的 `stream_video.bat`
（ffmpeg 解成 512×300 RGB565 裸流后用管道喂 `--file -`），串口
`board/uart_cmd_script.ps1` / `board/uart_cap_once.ps1`。

**你可以自己验证。**

```bash
bash build/gates.sh | tail -30          # 只读报告，几秒钟；看清今天到底几项、哪项红
node src/host/doc_enc_check.mjs         # 手写文件的编码自检（门禁第 17 项）
```

## 11. Vivado 报告的读法：WNS 不是"越快越好"，CRITICAL WARNING 才是牙

**为什么要它。** 本项目一大半门禁项读的是 Vivado 写出来的报告文件。看不懂那一行数字，
就等于把判据交给运气。

**四组数字。**

- **WNS**（Worst Negative Setup，实际是"最差建立时间裕量"）：所有同步路径里最小的那个裕量，
  **≥ 0 才叫满足**；负数就是真的有可能采错。报告第一行数据那形状
  `wns whs tns_whs …` 的解析写在 `build/gates.sh:50-64`。
- **TNS**：所有违例路径的裕量之和，违例时为**负数** —— 这里有个门禁自己坏掉的真事故：
  原解析式子只给 WNS/WHS 留了符号位、TNS 两列没留，于是违例时 awk 不匹配、脚本打印
  "读不到 timing summary" 并 `exit 2`（停在没把自己判绿，是对的），但它把最该看见的数字换成了
  一句"读不到"。修好之后的规矩是"四列都允许带符号，而且读不到时把候选行原样打出来"
  （`build/gates.sh:51-58`）。**尺子读不懂被测对象时，必须说"我读的是这一行"。**
- **WHS**（保持时间裕量）：≥ 0。保持违例在 FPGA 上是致命的，因为它与频率无关、降频也救不回来。
- **CRITICAL WARNING**（methodology 与 CDC 两类）：`build/gates.sh:75-77` 数总条数；
  CDC 那一项**不与一个写死的数字比**，而是与 `build/CDC_BASELINE.txt` 的"配对集合"比：
  新增一条 `src→dst` 配对即红，某条配对的 unsafe 端点变多也红，端点数变多只记录不红
  （`build/gates.sh:79-136`）。这个口径的来历是编号 #26 那次"门禁把自己要挡的东西漏掉了"。

还有一条新鲜度规矩值得学：读门禁之前先确认"报告与位流是同一套产物"。
`build/gates.sh:33-52` 会打印 `system.bit` 与 `timing_summary.rpt` 的修改时间、相差超过 10 分钟就 WARN，
并且在 `D=build` 时用 `find src/rtl -name '*.v' -newer <bit>` 检查"是不是改完没重跑"。
这两条对应的都是真实事故：构建还在跑就念门禁，念到上一版数字，七项照样全绿。

**你可以自己验证。** 跑完第 10 节那条 `bash build/gates.sh`，然后：

```bash
head -20 build/timing_summary.rpt        # 找到 WNS 那一行，与门禁打印的第一项对上
grep -n "Critical" build/cdc.rpt | head  # 与 build/CDC_BASELINE.txt 的三列对上
```

## 12. 先量后修：这个仓库的改 bug 规矩

**为什么要它。** 如果不说明这条，后面章节里大量"看起来多余"的钳位、注释、判据都读不通。
这不是知识，是习惯，但它决定了代码的形状。

**规矩。** 没有测量结果之前不改 RTL。所以每个修复都是成对的产物：一段解释"为什么不能那样修"
的注释 + 一条**能红**的判据 + 一份留档报告。三个关键词：

- **判据要能红。** 一条永远不会失败的判据等于没有判据。本项目的做法是"变异对照"：
  故意把被测对象改坏，看**是否恰好只有该红的那条红**。例如 `raw_line_delay` 行首那一格，
  是把 `raw_line_delay.v:95` 那一行的 `d_out` 选择改回 `assign d_out = q;`（去掉行首预读那一支）
  这一刀跑出来、确认只红一条之后，才算这条判据有牙。台架 `sim/tb_v100_raw_delay.v`，
  三跑对照（同一台架、同一 RTL，只改那一行）的留档在
  `build/evidence/r80_ring_head_module_cred.txt`。
  门禁项自己也有反例脚本：`build/tb98_gate_ce.sh`、`build/rim_gate_ce.sh`、
  `build/gates_cdc_test.sh`，`--self` 那一份份跑的就是"这条判据能不能红"。
- **报告要绑定出处。** `bash sim/run_one.sh` 在**编译之前**写下 `top_md5`（顶层源）、
  `rtl_md5`（整棵 `src/rtl` 的合指纹）、`tb_md5`（台架源）三枚
  （`sim/run_one.sh:42-45`）。为什么两枚不够：只比顶层的话，改四个窗口级时
  `pl_video_top.v` 一字未动，旧报告能原样冒充当前凭据 —— 这件事在 r72 那天真的发生过
  （`sim/run_one.sh:38-40`、`build/freeze_evidence.sh:7-11`）。
- **红 = 没做完。** 门禁红的东西不许冻结、不许念给评审（`build/freeze_evidence.sh:23-24`：
  `build/rNN_gates.txt` 不是 `ALL PASS` 就直接 `REFUSE`；`:33` 是第二道 md5 门的 `REFUSE`）。

**你可以自己验证。** 挑一条最小的判据做变异，二十分钟以内：

```bash
bash sim/run_one.sh tb_v100_raw_delay         # 先看它全绿
# 然后把 src/rtl/video/raw_line_delay.v:95 的 d_out 选择改成 `assign d_out = q;`，再跑一次，
# 看是不是恰好红在行首那一格（T7 一族），其余照旧
```

改回去之后 `md5sum src/rtl/video/raw_line_delay.v` 应当与改之前一致 —— 这也是本仓库习惯的
"我确定自己复原了"的凭据方式。

## 13. 术语速查

后面章节里反复出现、但前面没单独成节的名词，一次性钉在这里。

| 词 | 含义 | 本仓库的对应 |
|---|---|---|
| 乒乓 bank | 两个 DDR 帧缓冲区轮流当"写的那一个"和"读的那一个"，收完一帧翻一次 | `eth_udp_video_top.v:67-68` |
| 提交锁 | 拷贝只被允许在显示消隐窗口里开始，超时看门狗中止并可重试 | `src/rtl/video/frame_commit_lock.v:1-4`、`pl_video_top.v:385` |
| 片源仲裁 | 决定 DDR→帧缓存这台搬运机此刻归 ETH 还是归 PS | `src/rtl/util/src_arb.v:1-9`、`pl_video_top.v:376` |
| 存在性判据（活判据） | "PS 这一路还有帧吗"用心跳超时判，不用"曾经有过"的粘滞位 | `src/rtl/util/src_life.v`、`pl_video_top.v:538` |
| 抽头 | 同一份源坐标读出的两条像素流各叫一条抽头：原图抽头、处理抽头 | `pl_video_top.v:720-755` |
| 缝 / seam | 屏幕上"这一格给原图还是给处理图"的那条分界 | `split_display.v:44-54`、`split_ctrl.v`、`seam_src.v` |
| oob | out-of-bound，这一格的源坐标落在画面外 ⇒ 涂黑 | `zoom_mapper.v:17`（输出 `oob`）、`pl_video_top.v:717` |
| lane | PS 读 PL 状态用的 32 位窗口编号，先写号再读一个字 | `system_top.v:203-229`，lane0~9 定义在 `link_monitor.v:178-187` |
| rNN | 第 NN 次构建的编号，用于点名一整套凭据 | `build/evidence_rNN/`、`build/rNN_gates.txt` |
| #NN | 缺陷账本里的编号 | `report/log/ISSUES.md`（追加式，不重写） |

关于 rNN 与 #NN 的一条口径：板子上现在是哪一版、门禁多少项，**只写在 `report/PERF_REPORT.md`
与仓库根首页**，本套学习文档一律指路不抄数。要复核就去认 md5：
`build/evidence_rNN/MANIFEST.md5` 里那三件成品的指纹（认 md5 不认文件名）。

---

## 14. 这一章没讲、但你迟早要补的

诚实清单，免得后面章节里出现这里没铺垫的名词：

- **AXI 握手细节**（五个通道、`READY/VLD` 交错、突发拆分）。本工程只用到 AXI3 读突发与写单拍，
  用到的部分在第 20 章会逐信号讲，但"完整的 AXI 协议"要查 AMBA AXI & ACE Issue G 手册。
- **IDELAYE2 / ISERDESE2 / OSERDESE2 这类原语的时序模型**。`src/rtl/eth/rgmii_rx.v` 与
  `src/rtl/hdmi/tmds_serializer.v` 用到了它们，本套文档只讲"在这里做什么用"，不讲"内部几级流水"。
  仿真侧的占位件在 `sim/prim/`（`MMCME2_BASE.v`、`unisims_sim.v`），这是台架能跑但不碰库的原因。
- **约束文件的写法**（`create_clock`、`set_clock_groups`、`set_max_delay -datapath_only`、`false path`）。
  本工程的正本只有两份：`src/constraints/rk_zynq7020.xdc` 与
  `src/constraints/clock_groups_impl.xdc`（后者**只在实现阶段生效**，因为 `clk_fpga_0` 由
  PS7 IP 自己的 XDC 创建，综合阶段还不存在，见 `build/tcl/build_system_axigpio.tcl:19-26`）。
  为什么异步时钟组必须带 `-include_generated_clocks`，第 30 章讲。
