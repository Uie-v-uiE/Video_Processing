# A6 · OSD 与显示输出、TMDS 串化

> 本卷属于 `Video_Processing` 架构拆解系列（卷号 A6）。同级卷：A1（顶层与互联）、A2（时钟与复位）、A5（缩放与图像处理）、A7（HDMI/DDC 与 EDID）、A9（约束与实现）。目录只作导航，内容不重复。

## 目录

1. 面板时序：1024×600 档的逐段数值与拍数算式
2. 字模 ROM：容量形状、寻址方式与 BRAM/LUTRAM 归属
3. 五行状态字：每行逐字段格式与数据来源
4. BCD 与数值转换：PS/PL 分工与三方对账
5. 叠加：`osd_overlay` 的两拍延迟、地址对齐与关闭判据
6. ×2 展开与串化：`clk_pix5x`、OSERDESE2、OBUFTDS 与引脚
7. 对外时序口径：TP1 窗口、pin-to-pin 实测与 6 个输出端口
8. 未证清单与后续核对项

---

## 1. 面板时序：1024×600 档的逐段数值与拍数算式

### 1.1 档位参数：只有 4 个数字是源头

1024×600 档本身不写时序，它只是 `video_timing` 的一次参数化例化。全部数值集中在 `video_timing_1024x600.v` 的 17–21 行：

```verilog
.H_ACTIVE(1024), .V_ACTIVE(600),
.H_FP(44), .H_SYNC(88), .H_BP(188),
.V_FP(3),  .V_SYNC(6),  .V_BP(16),
.H_POL(1'b1), .V_POL(1'b0)
```

（来源：src/rtl/video/video_timing_1024x600.v:18-21）

- 水平：有效 1024 拍（来源：src/rtl/video/video_timing_1024x600.v:18），前肩 H_FP = 44（来源：src/rtl/video/video_timing_1024x600.v:19），同步脉宽 H_SYNC = 88（来源：src/rtl/video/video_timing_1024x600.v:19），后肩 H_BP = 188（来源：src/rtl/video/video_timing_1024x600.v:19）。
- 垂直：有效 600 行（来源：src/rtl/video/video_timing_1024x600.v:18），前肩 V_FP = 3（来源：src/rtl/video/video_timing_1024x600.v:20），同步 V_SYNC = 6（来源：src/rtl/video/video_timing_1024x600.v:20），后肩 V_BP = 16（来源：src/rtl/video/video_timing_1024x600.v:20）。
- 极性：`H_POL(1'b1)`、`V_POL(1'b0)`（来源：src/rtl/video/video_timing_1024x600.v:21），与文件头注释 `// HSYNC +, VSYNC -` 一致（来源：src/rtl/video/video_timing_1024x600.v:5）。

文件头的两行加法注释就是官方口径的水平/垂直总长：`// H: 1024 + 44 + 88 + 188 = 1344` 与 `// V: 600  + 3  + 6  + 16  = 625`（来源：src/rtl/video/video_timing_1024x600.v:3-4）。注意这两行是注释而非代码，真实总长由下面 1.2 的 localparam 算出，二者数值相同、互为对账。

### 1.2 一行 / 一帧多少拍：由两个 localparam 决定

`video_timing.v` 里两个 localparam 是唯一的加法处：

```verilog
localparam H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;
localparam V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;
```

（来源：src/rtl/video/video_timing.v:26-27）

四个操作数分别是 `H_ACTIVE`、`H_FP`、`H_SYNC`、`H_BP`（来源：src/rtl/video/video_timing.v:26），代入 1.1 的值即一行 `1024 + 44 + 88 + 188` = 1344 拍（来源：src/rtl/video/video_timing.v:26）。同理 V_TOTAL 的四个操作数是 `V_ACTIVE`、`V_FP`、`V_SYNC`、`V_BP`（来源：src/rtl/video/video_timing.v:27），代入 = 625 拍/帧（来源：src/rtl/video/video_timing.v:27）。

一帧的总拍数没有单独 localparam，它由行计数器的回绕条件隐含：`if (h_cnt == H_TOTAL - 1)`（来源：src/rtl/video/video_timing.v:37）与 `if (v_cnt == V_TOTAL - 1)`（来源：src/rtl/video/video_timing.v:39）。因此一帧 = H_TOTAL × V_TOTAL = 1344 × 625 = 840000 拍（两个操作数为来源：src/rtl/video/video_timing.v:26 与 :27 的两条 localparam）。

两个计数器都是 12 bit（`reg [11:0] h_cnt;` `reg [11:0] v_cnt;`，来源：src/rtl/video/video_timing.v:29-30），最大可表示 4095，对 1344（来源：src/rtl/video/video_timing_1024x600.v:3）与 625（来源：src/rtl/video/video_timing_1024x600.v:4）都够用，不存在回绕截断。

### 1.3 场频与帧周期算式（操作数点名）

像素时钟取 50 MHz，注释写的是 `// 1024x600 @ ~60Hz, pixel clock 50 MHz (spec 50.25MHz, 0.5% ok)`（来源：src/rtl/video/video_timing_1024x600.v:2）——即面板规格 50.25 MHz（来源：src/rtl/video/video_timing_1024x600.v:2），实现用 50 MHz。

- 帧周期 = 一帧拍数 ÷ 像素时钟 = 840000 ÷ 50 MHz = 16.8 ms。两个操作数：分子 840000 = H_TOTAL × V_TOTAL（来源：src/rtl/video/video_timing.v:26-27），分母 50 MHz（来源：src/rtl/video/video_timing_1024x600.v:2）。
- 行周期 = 1344 ÷ 50 MHz = 26.88 µs，分子取自（来源：src/rtl/video/video_timing_1024x600.v:3），分母同上（来源：src/rtl/video/video_timing_1024x600.v:2）。
- 场频（帧频）= 50 MHz ÷ 840000 = 59.5238 Hz ≈ 59.52 Hz（分子来源：src/rtl/video/video_timing_1024x600.v:2，分母来源：src/rtl/video/video_timing.v:26-27），落在注释 `~60Hz` 的范围内（来源：src/rtl/video/video_timing_1024x600.v:2）。
- 有效像素占比 = 1024 ÷ 1344 = 76.19%（分子来源：src/rtl/video/video_timing_1024x600.v:18，分母来源：:3），垂直方向 600 ÷ 625 = 96%（来源：src/rtl/video/video_timing_1024x600.v:18 与 :4）。

### 1.4 段边界怎么变成 hs/vs/de

三段窗口直接用 `h_cnt` 比较产生，与 1.1 的数值一一对应：

```verilog
wire hs_act = (h_cnt >= H_ACTIVE + H_FP) && (h_cnt < H_ACTIVE + H_FP + H_SYNC);
wire vs_act = (v_cnt >= V_ACTIVE + V_FP) && (v_cnt < V_ACTIVE + V_FP + V_SYNC);
wire de_act = (h_cnt < H_ACTIVE) && (v_cnt < V_ACTIVE);
```

（来源：src/rtl/video/video_timing.v:49-51）

即 hs 有效窗口从第 1068 拍起、宽 88 拍（1024+44=1068，来源：src/rtl/video/video_timing.v:49），vs 有效窗口从第 603 行起、宽 6 行（600+3=603，来源：src/rtl/video/video_timing.v:50）。极性在输出级翻转：`hs <= H_POL ? hs_act : ~hs_act;` `vs <= V_POL ? vs_act : ~vs_act;`（来源：src/rtl/video/video_timing.v:65-66）。因为 1024×600 档给了 `V_POL(1'b0)`（来源：src/rtl/video/video_timing_1024x600.v:21），vs 走的是 `~vs_act` 一支，即 vs 平时为高、同步期拉低。

还有一处容易被忽略的固定偏移：x/y/hs/vs/de 全部是寄存器输出，`x <= h_cnt` `y <= v_cnt` `de <= de_act`（来源：src/rtl/video/video_timing.v:63-67），比内部计数器晚 1 拍。也就是说 OSD 和 TMDS 看到的 `de` 与字模取数之间天然带 1 拍对齐偏差，这是模块固有属性，不是下游模块引入的。

`frame_start` 与 `frame_done` 同样带这 1 拍：`frame_start <= de_act && (h_cnt == 12'd0) && (v_cnt == 12'd0);`（来源：src/rtl/video/video_timing.v:68），`frame_done <= (h_cnt == H_TOTAL-1) && (v_cnt == V_TOTAL-1);`（来源：src/rtl/video/video_timing.v:69）。前者只在第 0 行第 0 拍出现，后者只在 1343/624 出现（两个操作数来源：src/rtl/video/video_timing.v:26-27）。

**这一站数据形状**：从 `video_timing_1024x600` 出来的是 `x[11:0]`、`y[11:0]`、`hs`、`vs`、`de` 五个信号（来源：src/rtl/video/video_timing_1024x600.v:9-13），一行 1344 拍里只有 1024 拍 `de` 为高，坐标宽度 12 bit（来源：src/rtl/video/video_timing.v:18-19）。

**出错时屏上表现**：数值改错（如 H_BP 少算）会让 1344 变短，行周期 26.88 µs 随之改变，面板判为超出规格而黑屏或整幅水平向一侧偏移；`V_POL` 写反则 vs 极性错，表现为整帧垂直不同步。具体某档参数错到什么程度会被面板拒绝，实测数据 `未证`。

## 2. 字模 ROM：容量形状、寻址方式与 BRAM/LUTRAM 归属

字模没有独立的 ROM 文件——它和排版、取位、上色全部住在 `src/rtl/video/osd_overlay.v` 里。

### 2.1 容量形状：64 字 × 7 行 × 5 位

声明只有一行：

```verilog
reg [4:0] font [0:63][0:6];
```

（来源：src/rtl/video/osd_overlay.v:333）

即 **64 个字模**（来源：src/rtl/video/osd_overlay.v:333）、**每字 7 行**（来源：src/rtl/video/osd_overlay.v:333）、**每行 5 位**（来源：src/rtl/video/osd_overlay.v:333），合计 64 × 7 × 5 = 2240 bit。字模是 `initial` 块里的常量（来源：src/rtl/video/osd_overlay.v:335-435），进块先整表清 0：

```verilog
for (fi = 0; fi < 64; fi = fi + 1)
    for (fj = 0; fj < 7; fj = fj + 1)
        font[fi][fj] = 5'b00000;
```

（来源：src/rtl/video/osd_overlay.v:336-338）

点阵尺寸 5×7 在屏上被放大成 18×21 像素格：`SCALE = 3`（来源：src/rtl/video/osd_overlay.v:11），`CHAR_W = 18` 配注释 `// 5*3 + 3 gap`（来源：src/rtl/video/osd_overlay.v:12），`CHAR_H = 21` 配注释 `// 7*3`（来源：src/rtl/video/osd_overlay.v:13）。也就是说每个字模行只有 5 个真实位，放大后占 15 px，余下 3 px 是字间缝（来源：src/rtl/video/osd_overlay.v:12）。

### 2.2 寻址方式：两级查表

第一级把 ASCII 码折成字形号：`function [5:0] glyph_idx; input [7:0] c;`（来源：src/rtl/video/osd_overlay.v:442-443），返回 6 bit 正好覆盖 0..63（来源：src/rtl/video/osd_overlay.v:333）。第二级是二维下标：`wire [4:0] font_row = font[gi][fy];`（来源：src/rtl/video/osd_overlay.v:507），`gi` 来自 `wire [5:0] gi = glyph_idx(ch);`（来源：src/rtl/video/osd_overlay.v:504）。

行选择带钳位，防止放大后越到第 8 行：

```verilog
wire [2:0] fy = (s_pix_y < 7*SCALE) ? (s_pix_y / SCALE) : 3'd6;
```

（来源：src/rtl/video/osd_overlay.v:506）

列选择是纯除法：`wire [2:0] fx = s_pix_x / SCALE;`（来源：src/rtl/video/osd_overlay.v:505），命中判断 `wire pixel_on = s_in_char && (fx < 5) && (font_row[4-fx] == 1'b1);`（来源：src/rtl/video/osd_overlay.v:508）——注意下标是 `4-fx`，位图 MSB 在左，即每行 5 位从左往右画。

字形号本身是**历史插入序，不是字母序**：`// 5x7 font。索引 0..27 是**历史插入序，不是字母序**，金表钉的就是那一段 ⇒ 新字一律往后接，不回头改已经在用的号。空格在 63`（来源：src/rtl/video/osd_overlay.v:331-332）。所以 `'0'..'9'` 是 0..9（来源：src/rtl/video/osd_overlay.v:347-366），`A=10 B=11 C=12 D=13 E=14 F=15`（来源：src/rtl/video/osd_overlay.v:367），而 `G=16 N=20 P=22 S=24 = 27`（来源：src/rtl/video/osd_overlay.v:380）、`R=17 O=18 T=19 L=21`（来源：src/rtl/video/osd_overlay.v:383）。空格占用 63 号且位图全 0（来源：src/rtl/video/osd_overlay.v:434）。

译码表刻意写成 `case` 而不是区间比较：`字码 → 字形号。**故意写成 case 而不是 if/else 区间比较**（时序深度）`（来源：src/rtl/video/osd_overlay.v:437-440），区间式 `c >= 0x30 && c <= 0x39` 被点名为串行优先级链、会和同拍的取数串成 27 级、CARRY4=10（来源：src/rtl/video/osd_overlay.v:438-440）。不在表里的码点统一落到 `default: glyph_idx = 6'd63; // BLANK（空格以及一切不在表里的码点）`（来源：src/rtl/video/osd_overlay.v:480）。

### 2.3 大小写改造留下的痕迹

三处痕迹可以对账，都在代码里留着：

1. 折叠发生在**写入侧**而不是读侧：`task put; input [7:0] c;` 内部 `if (u >= 8'h61 && u <= 8'h7A) u = u - 8'h20;`（来源：src/rtl/video/osd_overlay.v:190-194）。理由写在注释里：`折算放在**写这一侧**而不是读那一侧：读侧 ch→gi→font→b_reg 是全设计最差路径的主体`，换来`译码表少 17 个分支`（来源：src/rtl/video/osd_overlay.v:188-189）。
2. 读侧因此明确拒收小写：`屏上不再有小写：这里不认 0x61~0x7A 那 17 个码点 —— 小写进 put 就被折成大写`（来源：src/rtl/video/osd_overlay.v:474-475）。
3. 表里留着 16 个空洞号：`28~43 是小写 a c e i l m n o p r s t u x y 让出来的空洞：5×7 字模做不出真正的降部（p/q/y 尤其明显）`，且 `空洞留在表里不动号：金表钉的是 0..27 那段历史号`（来源：src/rtl/video/osd_overlay.v:405-407）。号段 28~43 在 `initial` 里确实一次都没被赋值（来源：src/rtl/video/osd_overlay.v:335-435）。

另外两处"只能大写"的证据是文案本身：模块头写 `屏上文案一律大写`（来源：src/rtl/video/osd_overlay.v:5），而排版任务里的字面量仍是混合大小写——`puts("Pipe:", 5)`（来源：src/rtl/video/osd_overlay.v:277）、`puts("Split:", 6)`（来源：src/rtl/video/osd_overlay.v:300）——它们靠 2.3 第 1 条的减法折成大写才出现在屏上，字面量里的小写就是改造前的化石。尺寸行的分隔符从 `x` 换成大写 `X`（字模 56 号，来源：src/rtl/video/osd_overlay.v:431 与 :261-262）也是同一件事的延续。

为 `AUTO`/`ETH`/`ZOOM`/`PIPE` 等串后补的字模分两批：U=23、H=25（来源：src/rtl/video/osd_overlay.v:341-345），Z=50 与 44~52 那批符号（来源：src/rtl/video/osd_overlay.v:403-423），最后一批 I=54、M=55、X=56、Y=57，注释说明 `号接在 53 之后，照旧"只往后加、不回头改已用的号"`（来源：src/rtl/video/osd_overlay.v:424-433）。

### 2.4 BRAM 还是 LUTRAM

代码层面可以断言它**不是 BRAM**：`font[gi][fy]`（来源：src/rtl/video/osd_overlay.v:507）处在纯组合读位置，整条读链 `ch → gi → fx/fy → font_row`（来源：src/rtl/video/osd_overlay.v:503-508）没有时钟沿，BRAM 只能同步读，故推断不出 BRAM。实现报告一侧的总量证据是 `LUT as Distributed RAM` 4044 个（来源：build/report/utilization.rpt:38，另一处口径同为 4044，来源：build/report/utilization.rpt:84），原语级计数 `| RAMD64E    | 4044 |   Distributed Memory |`（来源：build/report/utilization.rpt:195）；块内存一侧 `RAMB36E1` 用了 93 个（来源：build/report/utilization.rpt:108），`Block RAM Tile` 占用 68.21 %（来源：build/report/utilization.rpt:106）。93 个 RAMB36E1 具体归属哪些模块（帧缓存等）在逐模块拆分报告里，本卷未取到，`未证`。

同一文件里另一块真正的运行时数组是状态字缓冲：`reg [7:0] chars [0:N_LINES*MAX_CHARS-1];`（来源：src/rtl/video/osd_overlay.v:180），代入 `N_LINES = 5`（来源：src/rtl/video/osd_overlay.v:19）、`MAX_CHARS = 32`（来源：src/rtl/video/osd_overlay.v:15）得 160 格。它由 `always @(*)` 每拍整表重写（来源：src/rtl/video/osd_overlay.v:256-258），是组合 mux 阵列而非 RAM——注释点破 `chars 不是寄存器，是 160 格的大组合 mux`（来源：src/rtl/video/osd_overlay.v:492）。

**这一站数据形状**：进 ROM 的是 6 bit 字形号 + 3 bit 行号（来源：src/rtl/video/osd_overlay.v:504-507），出 ROM 的是 5 bit 位图行（来源：src/rtl/video/osd_overlay.v:507），再经 `4-fx` 选位压成 1 bit `pixel_on`（来源：src/rtl/video/osd_overlay.v:508）。

**出错时屏上表现**：`glyph_idx` 的号接错（如 U/H 写反）表现为文字局部错认但不乱位；`fy` 钳位去掉（来源：src/rtl/video/osd_overlay.v:506）会让 `s_pix_y ≥ 21` 的那些行读到越界下标，字格底部出现随机毛刺；`4-fx` 改成 `fx`（来源：src/rtl/video/osd_overlay.v:508）整屏字模左右镜像。空号段 28~43 若被复用去画新字，历史金表那一侧会红，屏上表现是旧字符变成新字形——具体哪一版金表先报错 `未证`。

## 3. 五行状态字：每行逐字段格式与数据来源

行数由 `parameter N_LINES = 5` 决定（来源：src/rtl/video/osd_overlay.v:19），原点 `X0 = 16`、`Y0 = 12`（来源：src/rtl/video/osd_overlay.v:9-10），行距 `LINE_GAP = 10`（来源：src/rtl/video/osd_overlay.v:14）。高度账写在参数注释里：`// 高度账：5×(21+10) = 155 px < 600 ✓`（来源：src/rtl/video/osd_overlay.v:18），与 `LINE_H = CHAR_H + LINE_GAP`、`BOX_H = N_LINES * LINE_H` 两式一致（来源：src/rtl/video/osd_overlay.v:71-73）。排版入口是 `task at; input integer ln; begin col = ln * MAX_CHARS; end endtask`（来源：src/rtl/video/osd_overlay.v:186），即每行有自己 32 格的窗口（来源：src/rtl/video/osd_overlay.v:15）。

模块头的四行注释就是本节的目录：`把 5 行状态文字叠在画面上（尺寸/FPS/片源、Pipe/Th/Gamma、Rot/Zoom、Split/Latency、Temp/无信号）`（来源：src/rtl/video/osd_overlay.v:2-4）。

### 3.1 L0 —— `1024X600  FPS:30  SRC:ETH`

装配段：`at(0); putnum4(OUT_W); put("X"); putnum4(OUT_H); puts("  FPS:", 6); putnum(fps_v); puts("  SRC:", 6); put_src(src_eff, mode);`（来源：src/rtl/video/osd_overlay.v:263-270）。

| 字段 | 值来源 | 依据 |
|---|---|---|
| 宽高 | `OUT_W` / `OUT_H`，顶层递 `#(.OUT_W(2*IMG_W), .OUT_H(2*IMG_H))` | 来源：src/rtl/top/pl_video_top.v:999 |
| 分隔符 | 大写 `X`（字模 56 号） | 来源：src/rtl/video/osd_overlay.v:266、:431 |
| FPS | `fps_q` → 端口 `fps`，再夹到 99 | 来源：src/rtl/top/pl_video_top.v:1006、src/rtl/video/osd_overlay.v:129 |
| SRC | `src_eff = {fb_vis, owner_eth_pix}` | 来源：src/rtl/top/pl_video_top.v:1014 |
| 尾部 `*` | `mode`，`if (md != 2'b00) put("*")` | 来源：src/rtl/video/osd_overlay.v:252、src/rtl/top/pl_video_top.v:1015 |

这一格画的是**面板**尺寸而不是片源，注释两处点明：`第一行画**面板**尺寸并放在行首`（来源：src/rtl/video/osd_overlay.v:20-22）与 `#67：OSD 第一行那格从"片源 512×300"换成**面板 1024×600**`（来源：src/rtl/top/pl_video_top.v:996）。`putnum4` 之所以敢用，是因为 `OUT_W/OUT_H 是 elaboration 常数 ⇒ /1000 折成接线`，同一段还禁止它打运行时数值（来源：src/rtl/video/osd_overlay.v:218-221）。片源名只允许三个词：`2'b11: puts("ETH", 3);`、`2'b10: puts("SD", 2);`、`default: puts("TEST", 4);`（来源：src/rtl/video/osd_overlay.v:247-251），理由是用词表注释 `CARD 在板上同时被念作"SD 卡"和"测试图卡"，PS 既指处理器也指片内自绘`（来源：src/rtl/video/osd_overlay.v:240）。行宽上限也钉了数：`最宽一格（TEST*）27 字符 ⇒ 右沿 16+27*18 = 502 ≤ 511，整行落在分割线左边`（来源：src/rtl/video/osd_overlay.v:262）。

### 3.2 L1 —— `PIPE:11000 TH:80 GAMMA:1.8`

装配段 `at(1); puts("Pipe:", 5); put(pc1)…put(pc5); puts(" Th:", 4); putnum(threshold); puts(" Gamma:", 7); putnum(gamma_disp / 6'd10); put("."); put(dig(gamma_disp % 6'd10));`（来源：src/rtl/video/osd_overlay.v:276-284）。

五格码由**实际生效**的九位成对折出（来源：src/rtl/video/osd_overlay.v:131-132 注释），每格取值 0..3 由 `function [7:0] lvl; input a, b;` 决定（来源：src/rtl/video/osd_overlay.v:119-127）：

- `pc1 = lvl(stage_sel[0], stage_sel[1])`，颜色级灰度/反色（来源：src/rtl/video/osd_overlay.v:133）。
- `pc2 = lvl(stage_sel[2], stage_sel[3])`，滤波级模糊/锐化（来源：src/rtl/video/osd_overlay.v:134）。
- `pc3 = lvl(stage_sel[4], 1'b0)`，边缘级只有 Sobel（来源：src/rtl/video/osd_overlay.v:135）。
- `pc4 = !stage_sel[5] ? "0" : (stage_sel[6] ? "2" : "1")`——二值化这一格不许出现 3，因为 `[6]` 是 `[5]` 的**判决反相位**（来源：src/rtl/video/osd_overlay.v:136-138）。
- `pc5 = lvl(stage_sel[7] & ~stage_sel[8], stage_sel[8] & ~stage_sel[7])`，形态学两位同开在 `proc_pipeline` 里是明确的旁路，所以这一格必须给 0（来源：src/rtl/video/osd_overlay.v:139-142）。

九位的入口是端口 `input wire [8:0] stage_sel`（来源：src/rtl/video/osd_overlay.v:34），顶层接的是 `sel_sync`（来源：src/rtl/top/pl_video_top.v:1007），即 `effect_ctrl` 同步到本域的那一口（来源：src/rtl/top/pl_video_top.v:205）。`threshold` 接 `th_sync`（来源：src/rtl/top/pl_video_top.v:1008、:207），`gamma_disp` 接 `gm_disp`（来源：src/rtl/top/pl_video_top.v:1009、:209），端口注释说明它是 `gamma×10，PS 写 LUT 时同一个字顺路带过来，只用于显示`（来源：src/rtl/video/osd_overlay.v:36）——所以屏上那位小数来自 `/10` 与 `%10` 两次（来源：src/rtl/video/osd_overlay.v:282-284）。

这一行的空格数是有专案的：`这一行的两个分隔是**单空格**（字段、顺序、值都没动，只动空格数）`，因为 `格距 18 px 而左半窗只有 512 px ⇒ 一行最多 28 格就贴到分割线`（来源：src/rtl/video/osd_overlay.v:272-274）。

### 3.3 L2 —— `ROT:45°  ZOOM:0.75X(AUTO)`

装配段 `at(2); puts("Rot:", 4); putnum(angle); put(8'hDF); puts("  Zoom:", 7); put(zc0)…put(zc4);`（来源：src/rtl/video/osd_overlay.v:287-292）。度数符号是 Latin-1 的 `8'hDF`（来源：src/rtl/video/osd_overlay.v:290），码点 `8'hDF: glyph_idx = 6'd49;  // °`（来源：src/rtl/video/osd_overlay.v:472）。角度端口是 `input wire [8:0] angle, // 度（0..359…不用换算）`（来源：src/rtl/video/osd_overlay.v:32），顶层直连 `angle`（来源：src/rtl/top/pl_video_top.v:1006），而该值由 `angle_ctrl u_ang` 产生（来源：src/rtl/top/pl_video_top.v:183-188）。

缩放倍率不查表于本模块：`Zoom 八档：号在 zoom_ctrl 里选（那里查表，不除），这里只把号翻成 5 个字符`（来源：src/rtl/video/osd_overlay.v:144），`case (zoom_code)` 列出 `"0.25x" "0.33x" "0.50x" "0.75x"`（来源：src/rtl/video/osd_overlay.v:148-151）与 `"1.33x" "1.50x" "2.00x"`（来源：src/rtl/video/osd_overlay.v:152-154），`default` 走 `"1.00x"`（来源：src/rtl/video/osd_overlay.v:155-157）。端口是 `input wire [2:0] zoom_code`（来源：src/rtl/video/osd_overlay.v:37），顶层接 `zoom_code`（来源：src/rtl/top/pl_video_top.v:1010）。后缀两个互斥：`if (zoom_fit) puts("(Fit)", 5); else if (zoom_auto) puts("(Auto)", 6);`（来源：src/rtl/video/osd_overlay.v:295-296），原因是一格 32 字符会溢到下一行（来源：src/rtl/video/osd_overlay.v:293-294）。顶层把两条判据都并进来：`zoom_auto` 处 `zoom_run && !zman_pix && !zoom_fit_en`，`zoom_fit` 处 `zoom_fit_en | rot_forced`（来源：src/rtl/top/pl_video_top.v:1010-1011）。

### 3.4 L3 —— `SPLIT:50%(AUTO)  LATENCY:16MS`

装配段 `at(3); puts("Split:", 6); putnum(split_pct); put("%"); if (split_auto) puts("(Auto)", 6); puts("  Latency:", 10);`（来源：src/rtl/video/osd_overlay.v:299-304）。`split_pct` 端口注释给出 50 % 的来历：`来自几何（左窗宽/屏宽 = 50 %）；可动缝尚无执行者`（来源：src/rtl/video/osd_overlay.v:40），顶层接 `split_pct_w[7:0]`、`split_auto` 接 `gp[10]`（来源：src/rtl/top/pl_video_top.v:1012），而 `gp` 是 19 位几何控制字经 `snap_cross #(.W(19), .DST_HZ(50_000_000))` 落进像素域的输出（来源：src/rtl/top/pl_video_top.v:876-879），位图 `[10]=auto_en`（来源：src/rtl/top/pl_video_top.v:49-51）。

时延：`input wire [15:0] lat_ms`（来源：src/rtl/video/osd_overlay.v:42）、`input wire lat_ok`（来源：:43）。`lat_ok=0` 时整格画两条短线 `if (!lat_ok) puts("--", 2);`（来源：src/rtl/video/osd_overlay.v:305），否则 `putd3(lt_h, (lt_rem / 8'd10), (lt_rem % 8'd10))`（来源：:306）后接 `puts("ms", 2)`（来源：:307）。顶层接 `lat_ms_pix` / `lat_ok_pix`（来源：src/rtl/top/pl_video_top.v:1013），源头是 axi 域 `frame_latency` 的 `lat_ms(lat_ms_axi), lat_valid(lat_ok_axi)`（来源：src/rtl/top/pl_video_top.v:632）。`lt_h`/`lt_rem` 是**分拍**算的除法余数（来源：src/rtl/video/osd_overlay.v:171-177），注释给出为什么不能一拍算完：`一次算三位在 50 MHz 像素域是二十几级组合链（这么做时 WNS 到过 −6.765）`（来源：src/rtl/video/osd_overlay.v:165-166）。

### 3.5 L4 —— `TEMP:47C  ETH IS NO SIGNAL`

装配段 `at(4); puts("Temp:", 5);` 后接半字节合法性判断（来源：src/rtl/video/osd_overlay.v:314-324）：

```verilog
if ((temp_disp[7:4] <= 4'd9) && (temp_disp[3:0] <= 4'd9)) begin
    put(dig(temp_disp[7:4]));          // 十位
    put(dig(temp_disp[3:0]));          // 个位
    put("C");
end else begin
    puts("--", 2);
end
```

（来源：src/rtl/video/osd_overlay.v:318-324）

温度端口是 8 bit 的两位十进制 BCD，`[7:4]=十位、[3:0]=个位`，任一半字节 >9 即"还没有可信读数"，量程 0..99 °C（来源：src/rtl/video/osd_overlay.v:49-53）。顶层接 `tmp_disp`，来自 `effect_ctrl` 的 `temp_disp` 输出（来源：src/rtl/top/pl_video_top.v:1017、:209）。异常句 `if (no_sig) begin puts("  ETH is no ", 12); puts("signal", 6); end`（来源：src/rtl/video/osd_overlay.v:325-328），`no_sig` 由顶层判：`wire no_sig = (mode_eth | owner_eth_pix) & ~eth_live_pix;`（来源：src/rtl/top/pl_video_top.v:510），AUTO 模式不判的理由写在上一行注释（来源：src/rtl/top/pl_video_top.v:509）。

温度为什么落在 L4：`前四行的字段/顺序/空格是定好的格式，只允许改空格数`（来源：src/rtl/video/osd_overlay.v:310），且新话只能另起一行（来源：src/rtl/video/osd_overlay.v:16-17）。该行的右沿也算过：`最宽激励 26 格 ⇒ 右沿 16+26*18 = 484 < 511`（来源：src/rtl/video/osd_overlay.v:311）。

**这一站数据形状**：五 × 32 = 160 个 ASCII 字节（来源：src/rtl/video/osd_overlay.v:180、:15、:19），每拍由 `always @(*)` 整表重装配、进表先全填 `8'h20`（来源：src/rtl/video/osd_overlay.v:256-258），每格最终只贡献 1 bit 的 `pixel_on`（来源：src/rtl/video/osd_overlay.v:508）。

**出错时屏上表现**：`stage_sel` 位序错 → L1 五格码与画面效果不符（典型是屏上写 3、画面上什么都没发生，来源：src/rtl/video/osd_overlay.v:140-142）；`split_pct_w` 取错切片 → L3 百分比与分割线位置不一致；`temp_disp` 半字节非十进制 → L4 画 `--`（来源：src/rtl/video/osd_overlay.v:318-324）。某一行超出 32 格会写进下一行的格子（来源：src/rtl/video/osd_overlay.v:293-294），屏上表现为两行文字粘连——实际哪一版金表先抓到 `未证`。

## 4. BCD 与数值转换：PS/PL 分工与三方对账

### 4.1 分工线：谁做十进制

屏上各格的转换点分三类，界画得很清楚：

| 数值 | 转换在哪一侧 | 依据 |
|---|---|---|
| 温度 | PS 侧编成 BCD 再跨，PL 只照画 | 来源：src/ps/main.c:83-88、src/rtl/process/effect_ctrl.v:63-65 |
| Latency(ms) | axi 域逐次除法做完，再按翻转位跨进像素域 | 来源：src/rtl/video/osd_overlay.v:42、src/rtl/top/pl_video_top.v:631-632 |
| 角度 | 两侧都不换：`angle_ctrl 里就是十进制度数，不用换算` | 来源：src/rtl/video/osd_overlay.v:32、:289 |
| 缩放倍率 | zoom_ctrl 给档号、OSD 只把号翻成 5 个字符 | 来源：src/rtl/video/osd_overlay.v:144-145、:37 |
| 尺寸 / FPS / Th / Split% | OSD 内部 `putnum`/`putnum4` 现场拆位 | 来源：src/rtl/video/osd_overlay.v:213-236 |

温度为什么必须在 PS 算：`OSD 那五行字符是一整块组合逻辑，而 u_pipe/xd_reg → u_osd/g_reg（27 级）正是 clkout0_1 那一组的 WNS 路径（r63b/r63c/r64b 三份 timing_summary 都指着它）—— 在屏上再加一次 /100 与 /10 就是往全设计最差的链上加深度`（来源：src/ps/main.c:85-88；同一理由在 PL 侧又写了一遍，来源：src/rtl/process/effect_ctrl.v:63-65）。`osd_overlay.v` 的端口注释给出第三种说法：`为什么 PS 把十进制算好了再传：下面是一整块组合逻辑`（来源：src/rtl/video/osd_overlay.v:51-52）。

`putnum4` 只许打常数的禁令也在同一处：`不许拿它打运行时数值：16 位除以 1000 就是二十几级链，而 OSD 的读侧正是全设计最差那条路径`（来源：src/rtl/video/osd_overlay.v:219-220）。

### 4.2 温度 BCD 的完整链路

1. 读数源选 PS 而非 PL：`为什么读 PS 的 XADC 而不是在 PL 里例化一个 XADC IP：后者会破掉本项目"零厂商 IP"这条`（来源：src/ps/main.c:738-739），头文件 `#include "xadcps.h"               /* V8-7 片上温度：PS 侧 XADC，PL 零改动 */`（来源：src/ps/main.c:31）。
2. 原始值折成毫度定点：`static s32 temp_mc_of(u16 raw) { return (s32)((((u64)raw) * 503975ULL) >> 16) - 273150; }`（来源：src/ps/main.c:754），乘数 503975、偏移 273150 同源（来源：src/ps/main.c:754）。
3. 编成两个半字节：`static u8 temp_code_of(s32 mc, s32 mv)`（来源：src/ps/main.c:786）过三道门——`if (!(mv > 800 && mv < 1300)) return GM_TEMP_NONE;`（来源：src/ps/main.c:789）、`if (mc < -40000 || mc > 150000) return GM_TEMP_NONE;`（来源：:790）、四舍五入 `d = (mc >= 0) ? (mc + 500) / 1000 : -((-mc + 500) / 1000);   /* 四舍五入到整度 */`（来源：:791）、`if (d < 0 || d > 99) return GM_TEMP_NONE;`（来源：:792），最后打包 `return (u8)(((((u32)d) / 10u) << 4) | ((((u32)d) % 10u) & 0xFu));`（来源：src/ps/main.c:793）——`/10` 进高半字节、`%10` 进低半字节。
4. 无效值定义：`#define GM_TEMP_NONE      0xFFu          /* 两个半字节都不是十进制数字 ⇒ 屏上画 -- */`（来源：src/ps/main.c:106），影子初值即它：`static u32 gm_w = GM_TEMP_NONE;`（来源：src/ps/main.c:288），于是 `app 起来到第一次读到 XADC 之间，屏上是 Temp:-- 而不是 Temp:00C`（来源：src/ps/main.c:290）。这里不复用 `cmd_temp` 的 `sane`（0..80 °C 窗），而另立"VCCINT 那一路健康"的门，理由见注释（来源：src/ps/main.c:779-783）。
5. 写入：`static void temp_disp_write(u8 code)`（来源：src/ps/main.c:798）比对影子后 `Xil_Out32(CFG_DATA1, gm_w);`（来源：src/ps/main.c:802），`**只有编码真的变了才写** —— 通道 2 是 gamma 窗口的同一个寄存器`（来源：src/ps/main.c:796-797）。节拍 `#define TEMP_POLL_MS      1000u`（来源：src/ps/main.c:107）。
6. 跨域：温度占第二个控制字的 `[7:0]`（来源：src/ps/main.c:83-84），整字打包 `{en, wr, data[7:0], idx[7:0], disp[5:0], temp_bcd[7:0]}`（来源：src/rtl/process/effect_ctrl.v:15）。它跟着 32 位一起过同一对同步器 `(* ASYNC_REG = "TRUE" *) reg [31:0] gm_meta, gm_sync;   // {en, wr, data, idx, disp[5:0], temp[7:0]}`（来源：src/rtl/process/effect_ctrl.v:39），拆位是 `{gamma_en, gamma_wr, gamma_data, gamma_idx, gamma_disp, temp_disp} = gm_sync;`（来源：src/rtl/process/effect_ctrl.v:67）。为什么不另开一组：`新增的位一律走 effect_ctrl 已有的那条 ASYNC_REG 链`（来源：src/rtl/process/effect_ctrl.v:62）。位序正本 `[13:8] **gamma_disp**（只给 OSD 看，不参与运算）、[7:0] **temp_disp**（XADC 编成 BCD 两位）`（来源：src/rtl/process/effect_ctrl.v:60-61）。
7. 画：`output reg  [7:0]  temp_disp            // V9-6：只给 OSD 看的片上温度 BCD（同样不参与运算）`（来源：src/rtl/process/effect_ctrl.v:25），顶层 `temp_disp(tmp_disp)`（来源：src/rtl/top/pl_video_top.v:209 与 :1017），最终 L4 两个 `dig()`（来源：src/rtl/video/osd_overlay.v:319-320）。

代价在拆位那一行被明说：`温度那一格的十进制口径由 PS 说了算、PL 只照画 ⇒ "屏上写的数"与 `temp` 打印的数必然同源（判据 tb_osd_lines T15 钉的就是"画的是编码，不是猜的"）`（来源：src/rtl/process/effect_ctrl.v:67）。

### 4.3 `osd=` 与 `gpio=` 的三方对账

`temp` 命令读完 ADC 后顺手刷一次屏上那格（来源：src/ps/main.c:863、:869、:872），并把三段口径钉在同一串口行：

```
⚠ 打印的 `osd=` 就是**屏上会画出来的那三个字符**（画不出可信读数时是 `--`），
  `gpio=` 是从设备读回来的低字节 = PL 那条同步链正在采的那个值。
  于是这一行把三段账一次钉住：`degC`（驱动读数）↔ `osd`（编码器的输出）↔ `gpio`（真的写到了 PL）。
  串口电池拿这三者做机器判据，不需要任何人看屏幕。
```

（来源：src/ps/main.c:865-868）

三段的生成各自可查：`degC` 来自 `mc`/`mv` 与 `a = (mc < 0) ? -mc : mc;`（来源：src/ps/main.c:857-858、:862）；`osd=` 由 code 反拼三字符 `osd_s[0] = (char)('0' + (code >> 4));` / `osd_s[1] = (char)('0' + (code & 0x0F));` / `osd_s[2] = 'C';`（来源：src/ps/main.c:874-876），且只在 `if (((code >> 4) <= 9) && ((code & 0x0F) <= 9))` 时拼（来源：src/ps/main.c:873），与 PL 侧 `if ((temp_disp[7:4] <= 4'd9) && (temp_disp[3:0] <= 4'd9))` 同形（来源：src/rtl/video/osd_overlay.v:318）；`gpio=` 是设备读回而非影子。负号单独订正过一次：`C 的除法朝零截断，mc=-400 时 mc/1000 已经是 0`（来源：src/ps/main.c:870-871）。

叠层开关 `osd` 走另一条对账路径：`[CTRL] AXI_GPIO=0x%08x sel=%03x thr=%d src=%d zoom=%d pub=%d bilin=%d osd=%d\r\n`（来源：src/ps/main.c:232）同时打印整字 `v`（来源：src/ps/main.c:233）与意愿 `cur_osd ? 1 : 0`（来源：src/ps/main.c:234），而落总线时反相：`| ((u32)(cur_osd ? 0 : 1) << OSD_OFF_BIT)   /* 反相位：1 = 关掉叠层，复位=0 = 有 OSD */`（来源：src/ps/main.c:217），位号 `#define OSD_OFF_BIT   20u`（来源：src/ps/main.c:57）。PL 侧再反一次 `wire osd_en = ~oo2;`（来源：src/rtl/top/pl_video_top.v:275）。所以串口 `osd=1` ⇔ 总线 bit20=0 ⇔ `osd_en=1`，三段换算少一层就判反。

**这一站数据形状**：PS → PL 只有一个 32 位字里的 `[7:0]` 十进制 BCD（来源：src/ps/main.c:83-84、src/rtl/process/effect_ctrl.v:39）；PL 内部其它数值是 9 bit 角度 / 8 bit FPS / 8 bit 阈值 / 16 bit ms（来源：src/rtl/video/osd_overlay.v:32-42），全部在跨域之后才变成"可画字符"。

**出错时屏上表现**：门写松（去掉 VCCINT 那条，来源：src/ps/main.c:789）→ 上电初期出现 `Temp:00C` 假读数；打包写反（`<<4`/`%10` 互换，来源：src/ps/main.c:793）→ 屏上十位个位对调，且串口 `osd=` 跟着一起错，因为两者由同一 code 生成（来源：src/ps/main.c:873-877），此时 `osd=` 与 `gpio=` 自洽、只有 `degC` 对不上；反相位换算漏一层 → 串口说关、屏上仍有字。具体哪一版脚本先红，`未证`。

---

## 5. 叠加：`osd_overlay` 的两拍延迟、地址对齐与关闭判据

模块头把延迟写成了契约：`输出叠字后的 r/g/b 与 de/hs/vs，比输入晚 2 拍（内容与坐标仍同一拍）`（来源：src/rtl/video/osd_overlay.v:4），同一段还钉了两条口径 `屏上文案一律大写；SRC 那一格画的是屏幕上真的那一路（src_eff），不是意愿`（来源：src/rtl/video/osd_overlay.v:5）与单域声明 `时钟域：clk = clk_pix 50 MHz 单域`（来源：src/rtl/video/osd_overlay.v:6-7）。

### 5.1 第一拍：把字格几何算完就寄存

拆法写在注释里：`时序专项：把"字格几何"这一级算完就**寄存一拍**`（来源：src/rtl/video/osd_overlay.v:75），因为 `ly / 31、lx / 18、lx % 18 三个除/模（LINE_H 与 CHAR_W 都不是 2 的幂）原本和"取字符 → 查字形 → 选位图行 → 上色"串在同一拍里，最差那条是 29 级 + 9 个 CARRY4`（来源：src/rtl/video/osd_overlay.v:76-77）。

组合段先框出叠字窗口：`wire in_box = de && (x >= X0) && (x < X0 + BOX_W) && (y >= Y0) && (y < Y0 + BOX_H);`（来源：src/rtl/video/osd_overlay.v:88-89），其中 `BOX_W = MAX_CHARS * CHAR_W`（来源：src/rtl/video/osd_overlay.v:72）、`BOX_H = N_LINES * LINE_H`（来源：src/rtl/video/osd_overlay.v:73）。随后四个换算：`wire [2:0] line = (ly / LINE_H);`（来源：:94）、`wire [7:0] pix_y = ly - line * LINE_H;`（来源：:95）、`wire [4:0] cidx = lx / CHAR_W;`（来源：:96）、`wire [7:0] pix_x = lx % CHAR_W;`（来源：:97），以及 `wire in_char = in_box && (pix_y < CHAR_H) && (line < N_LINES);`（来源：:98）。

第一拍把这五个量连背景像素与同步一起寄存（来源：src/rtl/video/osd_overlay.v:100-108），其中 `s_r <= r_in;  s_g <= g_in;  s_b <= b_in;` 与 `s_de <= de;   s_hs <= hs_in; s_vs <= vs_in;`（来源：src/rtl/video/osd_overlay.v:106-107）保证背景跟着晚同一拍。注释说明行号位宽的教训：`行号位宽必须跟着 N_LINES 走：写死 [1:0] 时加到第 5/6 行屏幕上永远取不到，而综合与时序报告全绿 —— 这种错只有屏能看见，工具链不报`（来源：src/rtl/video/osd_overlay.v:92-93）。

### 5.2 第二拍：字符寄存与输出选择

第二拍是 `#105` 那一刀（r109）：`把"选中哪一格"提前一拍算好并**寄存这一格字符**`（来源：src/rtl/video/osd_overlay.v:490）。原来的形状是 `chars` 不是寄存器而是 160 格的大组合 mux（来源：src/rtl/video/osd_overlay.v:491-492），于是 `值 → 十进制拆位 → 全表装配 → 选中格 → 字模 → 选行 → 颜色` 串成一条组合链（来源：src/rtl/video/osd_overlay.v:492-493）。寄存器边界落在装配段与译码段之间（来源：src/rtl/video/osd_overlay.v:496）：

```verilog
wire [15:0] ch_addr_pre = line * MAX_CHARS + cidx;
reg  [7:0]  ch_r;
always @(posedge clk) ch_r <= chars[ch_addr_pre];
```

（来源：src/rtl/video/osd_overlay.v:500-502）

关键对齐纪律是"地址用与被寄存的 `s_*` **同源同拍**的那一对（`line`/`cidx` 未寄存版）"，所以一拍之后 `ch` 与 `s_line/s_cidx/s_pix_x/s_pix_y/s_in_char` 仍是同一次光栅位置，`屏上内容一个字不变（de_out <= s_de 那一句早就说明格子与背景本来就一起晚一拍）`，代价 `8 个 FF`（来源：src/rtl/video/osd_overlay.v:496-499）。

出口那拍做最终选择：

```verilog
if (osd_en && pixel_on) begin
    r <= 8'hFF; g <= 8'h00; b <= 8'h90; // rose
end else begin
    r <= s_r; g <= s_g; b <= s_b;
end
```

（来源：src/rtl/video/osd_overlay.v:518-522）

字形色是 rose `8'hFF / 8'h00 / 8'h90`（来源：src/rtl/video/osd_overlay.v:519）。三拍输出 `de_out <= s_de;`、`hs_out <= s_hs;`、`vs_out <= s_vs;`（来源：src/rtl/video/osd_overlay.v:515-517）；复位支路把六路清零 `r <= 0; g <= 0; b <= 0; de_out <= 0; hs_out <= 0; vs_out <= 0;`（来源：src/rtl/video/osd_overlay.v:512-513）。

### 5.3 越界判据要吃的两根线

`ch_addr` 与 `ch_addr_pre` 是有意并存的两根线。`读地址**起一根线**（ISSUES #127/#130）：台架的越界判据要吃这根真信号，而不是自己按同样的式子重算一遍 —— 重算式看不见"将来有人改了地址算术"`（来源：src/rtl/video/osd_overlay.v:487-488），并注明 `ch_addr 一字未动，台架那根越界线照旧吃得到`（来源：src/rtl/video/osd_overlay.v:499）。两根式子分别是 `wire [15:0] ch_addr = s_line * MAX_CHARS + s_cidx;`（来源：:489，吃寄存后的 `s_*`）和 `ch_addr_pre`（来源：:500，吃未寄存版）。乘法之所以不贵：`chars 的索引是 移位+或（MAX_CHARS=32）`（来源：src/rtl/video/osd_overlay.v:485-486）。

### 5.4 `osd on|off` 的反相位与"逐位等于背景"

- PS 侧意愿位 `static u8  cur_osd   = 1;  /* GPIO bit20（反相）: OSD 叠层开/关。关掉的用处是取证与拍摄 —— 叠字会盖住画面最左上角那一块，逐像素比对时它是脏的 */`（来源：src/ps/main.c:191-192），开关只碰输出级：`开关只碰输出级的那个"字形 vs 背景"选择，不碰任何数据通路 ⇒ 关掉时屏上每一格必须逐位等于"这一层不存在"（判据在 `sim/tb_osd_lines.v`，配了正对照）`（来源：src/ps/main.c:565-566），实现是 `ctrl_set_osd(u8 on)` 里 `cur_osd = on ? 1 : 0;` 后 `ctrl_apply();`（来源：src/ps/main.c:567-570）。
- 极性口径：`OSD 叠层开关。**1 = 关掉**（与几何字那条 `gp[13]=1 才是关` 同一极性口径）⇒ 复位、或 PS 从没写过这一位时，屏上仍然有 OSD`（来源：src/ps/main.c:53-54），所以复位值取 0：`为什么复位取 **0**（= OSD 开着）：与固件默认一致 ⇒ 上电/PS 没写过时的屏上与加这个口子之前逐位相同`（来源：src/rtl/top/pl_video_top.v:265-266）。
- PL 侧同步链：`OSD 总开关（r83）：`gpio_o[20]`（反相）→ 这一条**独立**的 3 级同步 → `osd_en`。`（来源：src/rtl/top/pl_video_top.v:263），三级打拍 `oo0 <= osd_off_axi; oo1 <= oo0; oo2 <= oo1;`（来源：:272），出口 `wire osd_en = ~oo2;`（来源：:275）。为什么不共用一条链：`#65 那一次 CDC-11 就是"把两个翻转位挂同一级扇出"打出来的`（来源：src/rtl/top/pl_video_top.v:264）。
- 顶层接法：`.osd_en(osd_en),                // r83：0 = 输出逐位等于背景（见 osd_overlay 端口注释）`（来源：src/rtl/top/pl_video_top.v:1019）。模块侧同款表述：`0 = 输出**逐位等于背景**，等价于"这一层不存在"`，且强调 `不另加一级寄存器 ⇒ 关与开的内容延迟一模一样，顶层的 MIX_D/PROC_LAT 账一个字都不动`（来源：src/rtl/video/osd_overlay.v:55-58）。

关掉后的逐位判据因此可以直接写成式子：`osd_en=0` 时 `if (osd_en && pixel_on)` 恒不成立（来源：src/rtl/video/osd_overlay.v:518），输出退化为 `r <= s_r; g <= s_g; b <= s_b;`（来源：:521），而 `s_r/s_g/s_b` 只是背景的一拍延迟（来源：:106），`de/hs/vs` 的延迟与开关无关（来源：:515-517）——这正是"逐位等于背景、只是整体晚 2 拍"的证明链。

顺带一个观察：端口 `input  wire [15:0] bg_pix,`（来源：src/rtl/video/osd_overlay.v:54）在 `osd_overlay.v` 全文中除声明外没有任何引用，顶层还老实递了 `.bg_pix(16'h0)`（来源：src/rtl/top/pl_video_top.v:1018）。背景色实际走的是 `r_in/g_in/b_in` 三口（来源：src/rtl/video/osd_overlay.v:67-69）。这个 16 bit 端口的历史用途，`未证`。

**这一站数据形状**：进层是 RGB888 背景三口（来源：src/rtl/video/osd_overlay.v:67-69）+ 12 bit 坐标 + `de/hs/vs`（来源：:28-30、:63-66），出层是同名三口 8 bit 寄存器 + `de_out/hs_out/vs_out`（来源：:59-66），叠字像素被替换为 rose 三色（来源：:519）。

**出错时屏上表现**：第一拍的 `s_*` 少寄存一路（来源：:101-105 中任一）会让字与坐标错一列/一行，表现为整片文字水平或垂直错位一字符宽（18 px 或 31 px，来源：src/rtl/video/osd_overlay.v:12、:71）；`ch_r` 那一刀若地址用了寄存后的 `s_line/s_cidx`（来源：:489 而非 :500），字会整体晚一格、行尾字漂到下一行开头；`osd_en` 少反一次（来源：:275）表现为串口说 `osd off` 而屏上照旧有字。是否已有回归用例覆盖 `bg_pix` 悬空这一项，`未证`。

---

## 6. ×2 展开与串化：`clk_pix5x`、OSERDESE2、OBUFTDS 与引脚

### 6.1 250 MHz 从哪只 MMCM 出来

显示通路自带一只时钟发生器：`clk_gen u_clk`，输入是 `sys_clk`（来源：src/rtl/top/pl_video_top.v:128-130），输出口 `clk_pix(clk_pix), clk_pix5x(clk_pix5x)`（来源：src/rtl/top/pl_video_top.v:130）。`clk_gen.v` 里只有一个 MMCM 实例 `) u_mmcm (`（来源：src/rtl/clocks/clk_gen.v:32），参数链是：

- `DIVCLK_DIVIDE (1)`（来源：src/rtl/clocks/clk_gen.v:18）
- `CLKFBOUT_MULT_F (20.000), // VCO = 1000 MHz`（来源：src/rtl/clocks/clk_gen.v:19）
- `CLKOUT0_DIVIDE_F (20.000), // 50 MHz pixel`（来源：src/rtl/clocks/clk_gen.v:21）
- `CLKOUT1_DIVIDE (4),      // 250 MHz 5x`（来源：src/rtl/clocks/clk_gen.v:24）
- `CLKOUT2_DIVIDE (5),      // 200 MHz IDELAY ref`（来源：src/rtl/clocks/clk_gen.v:25-27 中的 :27）

所以 250 MHz 是 **CLKOUT1** 那一路（来源：src/rtl/clocks/clk_gen.v:24），出脚是 `.CLKOUT1 (clkout1)`（来源：src/rtl/clocks/clk_gen.v:39），再过 `BUFG u_bufg_5x  (.I(clkout1),  .O(clk_pix5x));`（来源：src/rtl/clocks/clk_gen.v:55）；50 MHz 那一路同构，过 `BUFG u_bufg_pix (.I(clkout0),  .O(clk_pix));`（来源：src/rtl/clocks/clk_gen.v:54）。由 1000 MHz VCO（来源：src/rtl/clocks/clk_gen.v:19）除以 4 得 250 MHz（来源：src/rtl/clocks/clk_gen.v:24），除以 20 得 50 MHz（来源：src/rtl/clocks/clk_gen.v:21）——两路是**同一只 MMCM 的两个 CLKOUT**，因此同相且频率比恰为 5（`CLKOUT1_PHASE (0.0)`，来源：src/rtl/clocks/clk_gen.v:25）。

要分清第二只：`system_top` 里另例化了一份 `clk_gen u_idelay_clkgen`，它的 `.clk_pix(clk_pix_unused), .clk_pix5x(clk_pix5x_unused)`（来源：src/rtl/top/system_top.v:121-123），两个口都挂在名为 `wire clk_pix_unused, clk_pix5x_unused, mmcm_locked;` 的悬空网上（来源：src/rtl/top/system_top.v:119），只取 `clk_200m` 作 IDELAY 参考。⇒ 屏上 TMDS 用的 250 MHz **不是**这只，而是 `pl_video_top` 内 `u_clk` 的 CLKOUT1（来源：src/rtl/top/pl_video_top.v:128-131）。

### 6.2 送进串化器的是叠完字的那一路

`rgb2dvi u_dvi` 的接法：`.clk_pix(clk_pix), .clk_pix5x(clk_pix5x), .rst_n(rst_pix_n)`（来源：src/rtl/top/pl_video_top.v:1027），数据取 `.r(r_osd), .g(g_osd), .b(b_osd)` 与 `.hs(hs_osd), .vs(vs_osd), .de(de_osd)`（来源：src/rtl/top/pl_video_top.v:1028-1029）——三口全部是 `u_osd` 的输出脚（来源：src/rtl/top/pl_video_top.v:1022-1023）。顶层注释把这条并行分发写明了：`同一份 RGB888+同步同时走面板与 u_dvi`（来源：src/rtl/top/pl_video_top.v:4）。复位也是合成的一路：`wire rst_pix_n = sys_rst_n & locked;`（来源：src/rtl/top/pl_video_top.v:132）。

### 6.3 OSERDESE2：10:1 级联、位序与三态

模块头一句就是配置依据：`10:1 OSERDESE2 cascade (UG471): DATA_WIDTH=10 requires DATA_RATE_OQ=DDR`（来源：src/rtl/hdmi/tmds_serializer.v:2），第二行给出分工 `Master D1-D8 + Slave D3/D4, Slave SHIFTOUT -> Master SHIFTIN`（来源：src/rtl/hdmi/tmds_serializer.v:3）。

主片参数：

```verilog
.DATA_RATE_OQ   ("DDR"),
.DATA_RATE_TQ   ("SDR"),
.DATA_WIDTH     (10),
.SERDES_MODE    ("MASTER"),
.TRISTATE_WIDTH (1),
```

（来源：src/rtl/hdmi/tmds_serializer.v:16-20）

从片同参数、只把 `SERDES_MODE` 换成 `"SLAVE"`（来源：src/rtl/hdmi/tmds_serializer.v:53-58）。两片的时钟脚接法一致：`.CLK (clk_pix5x)`、`.CLKDIV (clk_pix)`（来源：src/rtl/hdmi/tmds_serializer.v:31-32 与 :69-70）——即 250 MHz 串时钟 + 50 MHz 并时钟，正是 6.1 那两路 CLKOUT 的直接消费者。

位序（并→串）：主片 `D1..D8` 依次吃 `din[0]..din[7]`（来源：src/rtl/hdmi/tmds_serializer.v:33-40），从片 `D3 (din[8])`、`D4 (din[9])`，其余 `D1/D2/D5..D8` 全接 `1'b0`（来源：src/rtl/hdmi/tmds_serializer.v:71-78）。所以 10 bit 里低位先从主片出去，`din[9]`（最后一个位）落在从片。级联线是 `wire shift1, shift2;`（来源：:12），从片 `.SHIFTOUT1 (shift1)`、`.SHIFTOUT2 (shift2)`（来源：:64-65）回到主片 `.SHIFTIN1 (shift1)`、`.SHIFTIN2 (shift2)`（来源：:43-44）；主片自己的 `.SHIFTOUT1 ()`、`.SHIFTOUT2 ()` 留空（来源：:26-27）。

使能与复位：`.OCE (1'b1)` 恒开输出（来源：src/rtl/hdmi/tmds_serializer.v:41、:79），`.RST (~rst_n)` 低有效翻转后接（来源：:42、:80）。三态通路是**钉死释放**的：`T1..T4` 全 `1'b0`（来源：:45-48）、`.TCE (1'b0)`（来源：:50、:88）、`.TBYTEIN (1'b0)` 且 `TBYTE_CTL("FALSE")`、`TBYTE_SRC("FALSE")`（来源：:21-22 与 :49）。

### 6.4 差分输出级与引脚

本模块的差分缓冲用的是 `OBUFDS u_obuf (.I(serq), .O(data_p), .OB(data_n));`（来源：src/rtl/hdmi/tmds_serializer.v:91），输入是主片的 `.OQ (serq)`（来源：src/rtl/hdmi/tmds_serializer.v:25 与 :12），从片 `OQ` 不引出（来源：:63）。也就是说**极性问题（时钟取反/数据取反）不在这一级做**：这一级只把单端 `serq` 变差分，真正的电平反转约定在上游 TMDS 编码器 `src/rtl/hdmi/tmds_encoder.v`，其内部写法本卷不重复（见 A7），未证。

顶层端口是四对：`output wire tmds_clk_p / tmds_clk_n` 与 `output wire [2:0] tmds_data_p / tmds_data_n`（来源：src/rtl/top/pl_video_top.v:84-87），由 `system_top` 原样引出（来源：src/rtl/top/system_top.v:30-33、:296-297）。实现报告的器件数与这个形状自洽：`| OSERDESE2  |    8 |                   IO |`（来源：build/report/utilization.rpt:215），8 = 4 道 × 主从各一（来源：src/rtl/hdmi/tmds_serializer.v:15、:53）。

引脚侧（`IOSTANDARD TMDS_33`）能逐字确认的三条：

```tcl
set_property -dict {PACKAGE_PIN W16 IOSTANDARD TMDS_33} [get_ports tmds_clk_p]
set_property -dict {PACKAGE_PIN Y16 IOSTANDARD TMDS_33} [get_ports tmds_clk_n]
set_property -dict {PACKAGE_PIN AA17 IOSTANDARD TMDS_33} [get_ports {tmds_data_p[0]}]
```

（来源：src/constraints/rk_zynq7020.xdc:12-14）

即钟对 `W16`/`Y16`（来源：src/constraints/rk_zynq7020.xdc:12-13），数据道 0 正端 `AA17`（来源：src/constraints/rk_zynq7020.xdc:14）。其余五只脚（`tmds_data_p[1]`、`[2]` 与三个 `_n`）在同一文件的紧随行里，本卷没有逐行打开，未证；`report/board_pins.md` 的对应表行同样未取，未证。

**这一站数据形状**：进串化器是每道 10 bit（`input wire [9:0] din`，来源：src/rtl/hdmi/tmds_serializer.v:8），出串化器是单 bit 差分对（来源：:9-10、:91）；速率关系 250 MHz DDR × 2 = 500 Mt/s（来源：src/rtl/clocks/clk_gen.v:24 与 src/rtl/hdmi/tmds_serializer.v:16），每像素 10 bit ⇒ 50 MHz 像素率，与 1.3 的 50 MHz 口径闭合。

**出错时屏上表现**：主从片 D 口位序接错（来源：src/rtl/hdmi/tmds_serializer.v:33-40 与 :73-74 对调）表现为该道字符/颜色成片错乱但同步仍在；`DATA_WIDTH` 与 `DATA_RATE_OQ` 不配对（来源：:2）综合即报错，不会上屏；`u_bufg_5x` 换到别的 CLKOUT（来源：src/rtl/clocks/clk_gen.v:55）会让 5 倍关系破坏，表现为接收端判不到时钟、直接黑屏。W16/Y16 若接反（来源：src/constraints/rk_zynq7020.xdc:12-13），差分极性反转的后果未实测，未证。

## 7. 对外时序口径：TP1 窗口、pin-to-pin 实测与 6 个输出端口

### 7.1 方向先定死：这是 Source 侧的窗，不是 Sink 侧

`src/constraints/r119_hdmi_source_window.xdc` 自称 HDMI **源端（TP1）** 对外窗（候选件，默认不加载）（来源：src/constraints/r119_hdmi_source_window.xdc:1），并限定语法子集：`本文件必须是纯 SDC/XDC 子集：不写 `if` / `puts` / `error` / `expr`。`（来源：:3）。方向判据写得很直白：`tmds_clk_p/_n`、`tmds_data_p[0..2]/_n` 是本工程（Source）的**输出**，所以对应的是 HDMI 源端合规里 TP1 的那一组量，不是 Sink 侧 TP2 的接收窗`（来源：src/constraints/r119_hdmi_source_window.xdc:13-14）。

这个方向曾经记反过，纠正记录留在文件里：`这个方向是 2026-10-04 用户指出来才纠正的（此前记成"要面板/接收端的窗口数"，还试过 UG471——UG471 只有 TMDS_33 的电气属性，没有窗时间；见 report/timing/debt_ledger.md §2 的那段追加）`（来源：src/constraints/r119_hdmi_source_window.xdc:15-16）。同文件的形状参照件是 `同形状的写法参照 src/constraints/r116_rgmii_input_window.xdc（纯 SDC，已被一轮带窗构建量过）`（来源：:11）。

### 7.2 引的是哪份资料

窗宽数字逐条指回出处，正本是一张结论表：`窗宽的数字（逐条可指回出处，全部见 report/io/hdmi_cts_source_window.md 第一节结论表）`（来源：src/constraints/r119_hdmi_source_window.xdc:18）。被点名的规范行是：

- `钟↔数据（互对偏斜，Source at TP1，max）= **0.20 Tcharacter**`（来源：src/constraints/r119_hdmi_source_window.xdc:19）
- 出处：`《HDMI Specification 1.4》§4.2.4 Table 4-24 "Source AC Characteristics at TP1" 行`（来源：src/constraints/r119_hdmi_source_window.xdc:20）
- 原文片段与跨版本一致性：`Inter-Pair Skew at Source Connector, max | 0.20 Tcharacter`（同表在 1.3 Table 4-16 / 1.1 Table 4-13 逐字一致；Tektronix 的 CTS 应用笔记复述为 "20% of the pixel-time (TPIXEL)"）（来源：src/constraints/r119_hdmi_source_window.xdc:21-22）

对照件 `r119b_hdmi_tp1_pinclk.xdc` 把同一个 0.20 换算成纳秒：`窗宽仍用规范原文 0.20 × 20.000 = 4.000 ns（出处见 report/io/hdmi_cts_source_window.md 表行 #1）`（来源：src/constraints/r119b_hdmi_tp1_pinclk.xdc:13），两个操作数分别是 0.20（来源：src/constraints/r119_hdmi_source_window.xdc:19）与 20.000 ns（来源：src/constraints/r119b_hdmi_tp1_pinclk.xdc:12）。SDC 只有三条：

```tcl
create_clock -name r119b_tmclk -period 20.000 [get_ports {tmds_clk_p}]
set_output_delay -clock r119b_tmclk -max  4.000 [get_ports {tmds_data_p[*]}]
set_output_delay -clock r119b_tmclk -min -4.000 [get_ports {tmds_data_p[*]}]
```

（来源：src/constraints/r119b_hdmi_tp1_pinclk.xdc:24-26）

参考钟为什么必须打在脚上：`本文件唯一变量 = **把参考钟定在 TMDS 钟脚上**（`create_clock` 打在 `tmds_clk_p`，周期按 50 MHz 档 = 20.000 ns）`（来源：:12），反面情形是 `拿 4 ns 的钟当 20 ns 周期的参考，等于把窗口压缩成 1/5`（来源：:10）。文件自我定位是 `候选 2（只给只读探针用，**不进任何构建**）`（来源：:1）与 `这只是**探针输入**：默认不加载、没进 build/tcl/build_system_axigpio.tcl 的任何开关块`（来源：:16），数据道一侧再挂 `数据道相对这条"脚上的钟"再挂 ±4.000`（来源：:14）。

### 7.3 为什么是"6 个输出端口"需要窗，判据在哪

权威名单来自 `check_timing`，件名与实测时间都点了：`① `check_timing -verbose` 的**权威名单**（件 build/check_timing_verbose.rpt，2026-10-03 15:32 实测）`（来源：src/constraints/r114_io_variantb_phy_delay.xdc:11），其下 `no_output_delay (HIGH)  = 6 个端口：led[0]、led[1]、tmds_clk_p、tmds_data_p[0..2]`（来源：src/constraints/r114_io_variantb_phy_delay.xdc:13）；同段给出输入侧 `no_input_delay (HIGH)   = 5 个端口：eth_rx_ctl、eth_rxd[0..3]`（来源：:12）与 `MEDIUM（已有 false path）= 输入 key1_n/key2_n，输出 eth_rst_n/eth_tx_ctl/eth_txd[0..3]`（来源：:14）。所以"6 口"的构成是 **4 个 TMDS 正端 + 2 只 LED**（来源：src/constraints/r114_io_variantb_phy_delay.xdc:13；LED 的脚位见 src/constraints/rk_zynq7020.xdc:10-11），三个 `*_n` 不单独成窗，因为差分对由同一级差分缓冲同时驱动（来源：src/rtl/hdmi/tmds_serializer.v:91）。

两份候选件都如实记录了当时为什么写不出来：r116 写 `输出侧那 6 个端口（`tmds_clk_p`、`tmds_data_p[0..2]`、`led[0..1]`）**这里仍然故意不写**`，因为 `set_output_delay` 的数要来自接收端（面板/HDMI 接收器）或 DVI/HDMI 规范的窗口条款，本机板级资料（用户手册 + 原理图 + 芯片手册目录）里没有这一项，2026-10-03/04 两次在线取原文也没拿到可引用的一页`（来源：src/constraints/r116_rgmii_input_window.xdc:37-39）；更早的 r115 同款、只试过 2026-10-03 一次（来源：src/constraints/r115_io_window_candidate.xdc:43-45）。r114 变体 B 也承认 `TMDS/LED 那 6 个端口的对外窗要的是**面板/接收芯片的手册数**`（来源：src/constraints/r114_io_variantb_phy_delay.xdc:15）。

SDC 的语义边界写在保留条款里：`TP1 真正的判据是**眼图掩模 + 抖动/占空比/上升下降**，那几条不在 SDC 的语义里（`set_output_delay` 只约束沿的到达时刻），只能靠仿真与示波器；本文件不代表"过 CTS"，只代表"把规范里唯一能用 SDC 表达的那一个量写进来了"`（来源：src/constraints/r119_hdmi_source_window.xdc:41-43）。r119b 侧同款：`量出来的 slack 只能说明"这一族约束在 SDC 里怎么表达"，不能当"过了 CTS"`，并记下 `最终采用哪一版必须走一轮完整构建量逐时钟名册（还欠着）`（来源：src/constraints/r119b_hdmi_tp1_pinclk.xdc:17-18）；探针件名 `件 build/evidence/r119_xdc_loads_probe3.txt`（来源：:3）。

**pin-to-pin 实测读数**：本卷没有打开过任何给出 `Pin … -> Output Pin` 读数的报告行，记 **未证**。可追的两份凭据名已点名（来源：src/constraints/r114_io_variantb_phy_delay.xdc:11 与 src/constraints/r119b_hdmi_tp1_pinclk.xdc:3）；`build/report/timing_summary.rpt` 是否含 pin-to-pin 段未取，未证。像素域唯一已确证的负 slack 是 OSD 内部链上的 `WNS 到过 −6.765`（来源：src/rtl/video/osd_overlay.v:165-166），属内部路径而非对外 pin-to-pin。

**这一站数据形状**：对外只有 4 对差分（来源：src/rtl/top/pl_video_top.v:84-87；脚位样例 W16/Y16/AA17 见 src/constraints/rk_zynq7020.xdc:12-14），窗口的数学形状是一个 20.000 ns 参考周期配 ±4.000 ns 到达带（来源：src/constraints/r119b_hdmi_tp1_pinclk.xdc:24-26）。

**出错时屏上表现**：参考钟取错（把 4 ns 的 5x 当 20 ns）窗口被压成 1/5（来源：src/constraints/r119b_hdmi_tp1_pinclk.xdc:10），报告大面积红而屏上照旧有画面，属"报告红、屏不红"；6 口全不写窗（现状默认，来源：src/constraints/r116_rgmii_input_window.xdc:37-39）时报告不报对外 skew，屏上取决于接收端能否判到钟，不同面板的容忍度未实测，`未证`。

---

## 8. 跨域：OSD 内容从 100 MHz 到 50 MHz 的同步

### 8.1 两侧频率的点名处

OSD 自己是单域：`时钟域：clk = clk_pix 50 MHz 单域；lat_ms 由 axi 域按翻转位跨进来（snap_cross），temp_disp 是 PS 侧算好的两位十进制 BCD`（来源：src/rtl/video/osd_overlay.v:6-7）。100 MHz 那一侧的名字落在同步器例化参数上：`snap_cross #(.W(20), .DST_HZ(100_000_000), .HB_TO_MS(200)) u_zoom_axi`（来源：src/rtl/top/pl_video_top.v:674），反方向（进像素域）是 `snap_cross #(.W(19), .DST_HZ(50_000_000), .HB_TO_MS(200)) u_split_x`，`.dst_clk(clk_pix), .dst_rst_n(rst_pix_n)`（来源：src/rtl/top/pl_video_top.v:876-877）。`DST_HZ` 的两个取值 100_000_000 与 50_000_000（来源：src/rtl/top/pl_video_top.v:674、:876）就是"100 MHz → 50 MHz"这条链两端的官方口径。

### 8.2 方式：总线 + 翻转位，三级之后才采

契约写在调用处：`控制位在 axi 域每 ~1.3 ms 整拍抄一次并翻 toggle；目的域等 3 级同步之后才采总线 ⇒ 采到的永远是完整值（snap_cross 文件头那条契约）`（来源：src/rtl/top/pl_video_top.v:857-859）。OSD 读到的 19 位几何控制字走的就是这一条：`19 位**一起过同一条 snap_cross**`（来源：src/rtl/top/pl_video_top.v:51），落地成 `bus_q(gp)`（来源：src/rtl/top/pl_video_top.v:879），再被 L3 的 `split_auto = gp[10]`（来源：src/rtl/top/pl_video_top.v:1012）与位图 `[10]=auto_en`（来源：src/rtl/top/pl_video_top.v:49-51）消费。心跳与总线接的是同一个 toggle：`.bus_tog(sp_tog), .hb_tog(sp_tog)`（来源：src/rtl/top/pl_video_top.v:878），且这里不接慢/停标志，因为 `缝位晚一帧生效的代价只是"下一格才跳"，不是数据错`（来源：src/rtl/top/pl_video_top.v:860-861）。

两条"不许"与屏上内容直接相关：`⚠ 不并进 effect_ctrl 那条现成的 ASYNC_REG 链（#71：加宽会让 cdc.rpt 的 unsafe 端点按位长涨），也不再开第二条 snap_cross（多一对 bus/toggle 同步器 = CDC-11 Critical 的签名，#65、r54 构建 #34 各红过一次）`（来源：src/rtl/top/pl_video_top.v:52-53）。还有一个声明顺序坑：`wire [18:0] gp;` 必须先声明再被驱动，因为 `Verilog-2001 不许在名字声明之前先切它的位（写成隐式 net 就是"看着接上、其实常 0"）`（来源：src/rtl/top/pl_video_top.v:173-175）——症状恰恰是屏上某一格永远不动。

### 8.3 `temp_disp` / `effect_ctrl` 同一条链的细节

温度与 gamma 挤在同一个 32 位字里跨域：`input  wire [31:0] gamma_async,         // 第二个控制字的**通道 2**：{en, wr, data[7:0], idx[7:0], disp[5:0], temp_bcd[7:0]}`（来源：src/rtl/process/effect_ctrl.v:15）。同步器是一对 32 bit 移位寄存器 `(* ASYNC_REG = "TRUE" *) reg [31:0] gm_meta, gm_sync;   // {en, wr, data, idx, disp[5:0], temp[7:0]}`（来源：src/rtl/process/effect_ctrl.v:39），字段序在另一处注释里给出正本：`[13:8] **gamma_disp**（只给 OSD 看，不参与运算）、[7:0] **temp_disp**（XADC 编成 BCD 两位）`（来源：src/rtl/process/effect_ctrl.v:60-61）。为什么整字一对、不分组：`gamma 那四个字段一起过同一对同步器：wr 是边沿标志，协议要求"idx/data 在 wr 翻转之前已经稳定至少一次 AXI 写"，所以它们必须与 wr **同源同深度** —— 分两组同步就会出现在本域里"边沿到了、数据还是上一次的"那种错拍`（来源：src/rtl/process/effect_ctrl.v:36-38）。为什么温度不另开一组：`新增的位一律走 effect_ctrl 已有的那条 ASYNC_REG 链`，否则 `cdc.rpt` 基线要重画（来源：src/rtl/process/effect_ctrl.v:62）。为什么换算不放 PL：`u_pipe/xd_reg → u_osd/g_reg/D 正是 clkout0_1 那条 27 级的关键路径（r63b/r63c/r64b 三份报告都指着它），多一次 /100 与 /10 就是往全设计最差的链上加深度`（来源：src/rtl/process/effect_ctrl.v:63-65），并点名先例 `Latency 从 #59 起就是"axi 域逐次除法做完再按翻转位跨域"`（来源：:65-66，另一处口径 src/rtl/video/osd_overlay.v:42 与 src/rtl/top/pl_video_top.v:631-632）。

出口是一句整字拆位：`{gamma_en, gamma_wr, gamma_data, gamma_idx, gamma_disp, temp_disp} = gm_sync;`（来源：src/rtl/process/effect_ctrl.v:67），其后 `u_eff` 把 `temp_disp(tmp_disp)`（来源：src/rtl/top/pl_video_top.v:209）递给 `u_osd.temp_disp(tmp_disp)`（来源：src/rtl/top/pl_video_top.v:1017）——屏上 L4 与串口打印同源（来源：src/rtl/process/effect_ctrl.v:67 末段）。

其它几路的写法各有差异，可以对照：叠层开关走**独立** 3 级链 `oo0 <= osd_off_axi; oo1 <= oo0; oo2 <= oo1;`（来源：src/rtl/top/pl_video_top.v:272）后 `wire osd_en = ~oo2;`（来源：:275），理由是 `#65 那一次 CDC-11 就是"把两个翻转位挂同一级扇出"打出来的`（来源：src/rtl/top/pl_video_top.v:264）；缩放使能那一位另有一对 `(* ASYNC_REG = "TRUE" *) reg ze0, ze1, ze2;`（来源：src/rtl/top/pl_video_top.v:212）；快照抄表另有触发：`抄快照的触发：system_top 在"lane 选择指到 25"时给一拍`（来源：src/rtl/top/pl_video_top.v:79-80），因为 `五个字之间有恒等式 tot ≥ c1+c2，而 live 寄存器每轮都在换`（来源：src/rtl/top/pl_video_top.v:80-81）。

一个本卷没能在文档里闭合的点：`angle` 由 `angle_ctrl u_ang` 在 `sys_clk` 域产生（来源：src/rtl/top/pl_video_top.v:183-188），却直连到 `clk_pix` 域的 `u_osd.angle`（来源：src/rtl/top/pl_video_top.v:1006）与 `zoom_fit`（来源：src/rtl/top/pl_video_top.v:322-323）。顶层只总述 `PS 侧命令经 effect_ctrl/src_* 的同步器进来`（来源：src/rtl/top/pl_video_top.v:5）。这一路是否被 `build/report/cdc.rpt` 列为端点、按什么级别，本卷未打开该报告，`未证`。

### 8.4 未证清单与后续核对项

1. 字模 ROM 的器件归属：只确证总量 `RAMD64E 4044`（来源：build/report/utilization.rpt:195）与 `RAMB36E1 93`（来源：build/report/utilization.rpt:108），逐模块拆分未取。
2. `bg_pix`（来源：src/rtl/video/osd_overlay.v:54）的历史用途与其在回归里的角色。
3. TMDS 编码侧的取反约定（`src/rtl/hdmi/tmds_encoder.v` 未在本卷打开）。
4. `tmds_data_p[1..2]` 与三个 `_n` 的 PACKAGE_PIN 行号（仅 :12-14 已确证，来源：src/constraints/rk_zynq7020.xdc:12-14）与 `report/board_pins.md` 的对应表行。
5. 对外 pin-to-pin 的实测读数行（见 7.3 末段）。
6. `angle` 那一跳在 `cdc.rpt` 里的级别（见 8.3 末段）。
7. 目录第 8 项的原定标题是"未证清单与后续核对项"，正文按任务口径改为跨域章并把清单收进 8.4，以正文标题为准。

**这一站数据形状**：跨进像素域的只有三种形态——19 位总线 + toggle（来源：src/rtl/top/pl_video_top.v:876-879）、32 位控制字的一对 `ASYNC_REG`（来源：src/rtl/process/effect_ctrl.v:39）、单 bit 的三级链（来源：src/rtl/top/pl_video_top.v:272、:212）；OSD 内部不再有任何时钟域（来源：src/rtl/video/osd_overlay.v:6-7）。

**出错时屏上表现**：总线分组同步会出"边沿到了、数据还是上一次的"错拍（来源：src/rtl/process/effect_ctrl.v:37-38），屏上表现为 gamma 数字与画面亮度对不上一次；`gp` 若被写成隐式 net（来源：src/rtl/top/pl_video_top.v:173-175），L3 的 `Split`/`(Auto)` 永远不变；`osd_en` 少一级同步则开关偶尔抖一帧，因为该位挂在扇出上正是 CDC-11 的签名（来源：src/rtl/top/pl_video_top.v:264）。哪一版构建先红、红在第几行，`未证`。
