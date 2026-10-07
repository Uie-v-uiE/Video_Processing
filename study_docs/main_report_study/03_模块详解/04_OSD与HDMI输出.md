# 模块详解 04 · OSD 叠加与 HDMI 输出

> 覆盖：`osd_overlay`、`rgb2dvi`、`tmds_encoder`、`tmds_serializer`，
> 以及「HDMI 到底是不是跨钟域」这个常被问错的问题。
> 概念铺垫：[前置知识 08 HDMI 时序与 TMDS](../00_前置知识/08_HDMI时序与TMDS.md)。

---

## 1. OSD：自己写的点阵字模叠加

工程里没有用任何 IP，字模是手写的 5×7 点阵。

### 1.1 位置与盒尺寸（全部用默认参数）

`pl_video_top.v:489-502` 的 `u_osd` **没有传任何参数** ⇒ 用 `osd_overlay.v:8-15` 的默认值：

```
X0=16  Y0=12  SCALE=3  CHAR_W=18  CHAR_H=21  LINE_GAP=10  MAX_CHARS=10  N_LINES=3
BOX_W = 10*18 = 180      BOX_H = 3*(21+10) = 93
⇒ 覆盖 x = 16..195、y = 12..104   （完全落在左窗 0..511 内）
```

### 1.2 三行文本

| 行 | 内容 | 代码 | 备注 |
|----|------|------|------|
| L0 | `FPS=xx` | `:81-87` | fps 饱和到 99（`:64-66`） |
| L1 | `ANG=xxx` | `:89-96` | 0..359 三位十进制，用**常量除法/取模**拆位（`:68-72`），综合期折叠，不占 DSP |
| L2 | `EN=xxxxx` | `:98-106` | `effect_en[0..4]` 逐位显示成 '1'/'0'，**bit0 在最左** |

`chars[]` 数组在**组合块** `always @(*)`（`:75-107`）里整体重写，未使用位置先填 `8'h20`。

### 1.3 字模与取整

```verilog
// osd_overlay.v:110-163
reg [4:0] font [0:31][0:6];     // 5×7，只在 initial 里初始化
// :165-177  ASCII → 字模索引的稀疏映射
'0'-'9'→0..9   'A'-'F'→10..15   'G'→16  'N'→20  'P'→22  'S'→24  '='→27
其余一律 → 31 = 全 0（空白字模）
```

- **空格必须是空白字模**，否则会显示成数字 0（头注释 `:6` 特别强调，这是踩过的坑）。
- 因为只有这 24 个字符要用，所以不做完整 ASCII 表 —— 32×7 的表综合成 LUT-ROM，
  `build/util_hier.rpt`（R07 重建后）：`u_osd = 317 LUT / 22 FF / 0 BRAM`。
- 放大：`fx = pix_x/3`、`fy = (pix_y<21) ? pix_y/3 : 6`（`:181-182`）⇒ **整数除法 = 最近邻 3×**；
  `fy` 的钳位让最后一行点阵被多扫一个缩放行（`pix_y=18..20` 都落在 `fy=6`）。〔推断〕
- 命中：`pixel_on = in_char && (fx<5) && font_row[4-fx]`（`:184`，**行内位序左右翻转**）。
- 非 2 幂除法：`line = ly/31`、`cidx = lx/18`、`pix_x = lx%18`、`pix_y = ly - line*31`
  （`:50-53`），除数是 localparam 常量 ⇒ 综合期折叠成移位+加减。
- 颜色：命中笔划时 **rose 洋红 `{8'hFF,8'h00,8'h90}`**（`:195`），未命中透传（`:197`）。
  命中判定要求 `de` 为真（`:46`）⇒ **OSD 不会画进消隐期**。

### 1.4 插入点与一个 1 像素错位

叠加发生在 `split_display` **之后**、`rgb2dvi` **之前**
（`pl_video_top.v:450-458 → 489-502 → 504-510`），
处理的是 **RGB888 + hs/vs/de**，所以**不碰左右窗的像素选择通路** —— 这是它 safest 的地方。

但坐标取的是 `x_d11/y_d11` 而数据是 `split_display` 的**寄存后输出**：

```
split_display 的 r_in(T) 对应 x_d11(T-1)    // split_display.v:39-48 输出寄存了一拍
osd_overlay 在同一拍用 x(T)=x_d11(T) 判窗   // osd_overlay.v:46-54
⇒ 文字盒在屏幕上比名义位置右移 1 像素
```

〔推断〕y 方向不受影响（一行内 y 恒定），所以看不出来。正确写法是再延一拍 `x_d12/y_d12`。
**这是一个「差一拍」类 bug 的典型形状**：数据通路寄存了、判据没寄存。

### 1.5 五个死输入

`src_sel / eth_link / net_pkts / net_bad / bg_pix`（`:25-29`）在模块体内**一次都没出现**，
顶层还在驱动它们（`:495-497`，`.bg_pix(16'h0)`）。
⇒ **想加「LINK/PKTS/BAD」行必须改 RTL，不是改参数就行。**

## 1.5 OSD 是全设计的时序瓶颈：一拍里塞了四件事（R25 量出来的）

`build/timing_summary.rpt` 里最差的那条路径不是以太网、不是帧缓存，而是
`u_pl/x_d_reg[11] → u_pl/u_osd/b_reg` —— 27 级逻辑、10 个 CARRY4、66% 是走线延迟。
原因在 `osd_overlay.v` 的这三行组合逻辑是**同一拍**里串起来的：

```verilog
wire [7:0] ch = chars[line*MAX_CHARS + cidx];  // ① 乘 + 40 项比较链（数组是组合写的，不是 RAM）
wire [4:0] gi = glyph_idx(ch);                 // ② 一串区间比较（V7.9.4 前是 if/else 串行）
wire [4:0] font_row = font[gi][fy];            // ③ 32×7 查表 + ④ font_row[4-fx] 变位选
```

三点可复用的道理：
1. **"用数组当查找表"和"用数组当存储器"不是一回事。**`chars[]` 被一个 `always @(*)` 整片写，
   综合不出 RAM，只会摊成"拿地址和每个下标比一遍"的比较链 —— 表越大越慢，而且慢得没有征兆
   （功能完全正确、资源也不心疼，只是那一级组合变成几十级）。
   对照实验在 `sim/probes/`（同一个数组写法不同 ⇒ FF/LUTRAM 数量天差地别；那组对照实验的结论记在
   `study/04_版本演进/02_问题与修复全记录.md` 的 **V5-37**，那是该文档的内部编号，不是 `report/ISSUES.md` 的编号）。
2. **区间比较的 if/else 链是串行的**，`case` 是并行的。V7.9.4 把 `glyph_idx` 改成 `case`，
   **等价性用 256 码点全量差分证明**（`sim/tb_v794_osd_glyph.v`：`force` RTL 的 `ch`，
   逐码点比 `gi` 与"按改前语义独立重写"的黄金函数，再加一条"故意写错的期望值必须判不等"的反向断言）。
   这一改不动延迟、不动真值表，只可能减少级数 —— **收益要等布线后的 WNS 才算数**，
   所以它单独一次构建、单独一组数字，不和别的改动混在一起提交。
3. **数字每帧才变一次，晚两拍没人看得见。** 本文件上面 §1 已经为此做过一次拆分
   （十进制四位数分两拍算，"一次算完是 28 级 / 16.9 ns"）。
   OSD 是叠加在显示通路上的，**它的额外延迟直接变成屏幕上的错位**，所以这里只能做
   "等价换写法"这类零延迟变化的优化；真要加分拍，必须同步改顶层的 `PROC_LAT` 判据
   （那是第 8 篇里"效果链列延迟"的老坑）。

## 2. HDMI / TMDS

### 2.1 通道映射（有一个反直觉点）

```verilog
// rgb2dvi.v:20-32
channel0 = Blue   且携带控制位：c0 = hs, c1 = vs
channel1 = Green
channel2 = Red
// :47-51 时钟通道 = 常量 10bit 图案 1111100000 的循环串行化
```

**时钟通道不是编码器产生的**，就是一个固定图案反复发 —— 这是 DVI/HDMI 规范规定的，
接收端靠它做时钟恢复与对齐。

### 2.2 8b/10b 编码器

`tmds_encoder.v:13-36` 算 `q_m`：`use_xnor` 判据是
`n1 > 4 || (n1 == 4 && din[0] == 0)`（`:21`）—— 标准 DVI 规则（选 XOR 还是 XNOR 让
游程更少、且不引入新的不平衡）；`:42-74` 做 DM（disparity 奇偶平衡）累加，
`cnt` 是 `reg signed [5:0]`（`:38`）。

**消隐期直接发三种控制字符**（`:46-53`）：
`{c1,c0}` = 00/01/10/11 → `1101010100 / 0010101011 / 0101010100 / 1010101011`，
同时 `cnt` 清零。

〔值得注意的脆弱写法〕`cnt` 的加减里混用了 4bit 无符号 `n0q-n1q` 与 6bit signed `cnt`，
Verilog 会把整个表达式按**无符号**算，靠模 64 回绕得到正确的有符号结果。
结论对，但如果有人把 `cnt` 加宽到 7 位或改初始化，就会静默出错。

### 2.3 串并转换：OSERDESE2 主从级联

```verilog
// tmds_serializer.v:15-89
DATA_RATE_OQ = "DDR"   DATA_WIDTH = 10   SERDES_MODE = "MASTER"/"SLAVE"
主片用 D1–D8；从片只用 D3/D4
从片 SHIFTOUT1/2 → 主片 SHIFTIN1/2         // 靠这两根线把 10 bit 串起来
OCE = 1'b1、TCE = 1'b0、T1..T4/TBYTEIN = 0
输出经 OBUFDS → TMDS_33 电平管脚
```

文件头 `:2-3` 引 UG471 说明「`DATA_WIDTH=10` 必须配 `DATA_RATE_OQ=DDR`」——
这就是为什么一个 OSERDESE2 装不下、要两片。

管脚：`rk_zynq7020.xdc:12-19` —— W16/Y16 时钟对，AA17/AB17、U17/V17、U15/U16 三对数据。

### 2.4 时钟关系与「为什么不需要 CDC」

```
OSERDESE2.CLK    = clk_pix5x = 250 MHz
OSERDESE2.CLKDIV = clk_pix   = 50 MHz
每 CLKDIV 周期并行装载 10 bit，每 CLK 周期 DDR 移出 2 bit
250 × 2 = 500 Mbit/s = 50 MHz × 10
⇒ TMDS 字符率 = 像素率 = 50 Mpx/s，线路速率 500 Mbps/lane
```

50 MHz ≪ HDMI 1.0 的 165 MHz 上限，所以余量极大。

**跨钟分析**：`din` 在 `clk_pix` 域寄存（`tmds_encoder.v:42-74`），
进 OSERDESE2 的并行脚，而**装载沿就是 CLKDIV = clk_pix**，`CLK` 只负责移出
⇒ 不存在真正的异步跨钟；两个钟来自**同一个 MMCM 的 CLKOUT0/CLKOUT1**
（`clk_gen.v:21,24`，5:1 整数比、0° 相位）。

三条独立证据（这也是回答「你怎么证明你这里的 CDC 是对的」的模板）：

1. `build/cdc.rpt` 的 CDC 矩阵里**根本没有** `clkout0_1 ↔ clkout1_1` 这一对；
2. `build/clock_util.rpt:220`：`clk_pix5x` 有 **8 个 IO 负载、0 个 slice 负载**；
3. `build/timing_summary.rpt:187`：`clkout1_1` 没有 setup/hold 路径，只有 WPWS +2.408（10 端点）。

而约束里把它们**留在同一时钟组**（`rk_zynq7020.xdc:53-56`）正是为了
让 Vivado 按同步路径去检查它 —— 声明成异步反而会漏检。

**真正的跨钟风险在别处**（`build/cdc.rpt` 原文）：
`eth_rxc → clkout0_1` 33 个端点、16 unsafe / 17 unknown，对应 `eth_link` 在像素域被裸用 4 处。
详见 [时钟与复位树](../02_架构/02_时钟与复位树.md) §2。

## 3. 整条输出链的延迟与对齐总结

```
fb_rd ─(逆映射3+rd_addr_q1+BRAM1=5拍)→ pix_right
      ─(proc_pipeline，标称 PROC_LAT=7、实测 9)→ 效果像素
      ─(de_d[11]/x_d[11]/y_d[11])→ split_display 输入
      ─(+1)→ split_display 输出
      ─(+1)→ osd_overlay 输出
      ─→ rgb2dvi → 3×tmds_encoder(@50M) → 4×OSERDESE2 主从(@250M/50M) → OBUFDS
从光栅坐标到 TMDS 串行输出：13 拍（11+1+1）
```

**为什么这一节要放在 OSD 文档里**：屏幕上的任何「错位」现象（字压住图像偏 1 像素、
效果边缘差 2 列、彩条与视频错 1 拍）都只能靠**逐拍数延迟**来定位，
而这套文档里唯一完整数过一遍的地方就是这里和
[效果链 §4](../03_模块详解/05_效果链.md)。
数的时候必须注意：**BRAM 读口、split_display、osd_overlay 都各自寄存了一拍**，
而 `x/y/de` 在 `video_timing.v:63-67` 也已经寄存过一拍。

## 4. 自测

1. 为什么 OSD 放在 `split_display` 之后而不是之前？放之前会有什么好处和坏处？
2. 空格为什么必须单独有一个字模？不写会显示成什么？
3. HDMI 时钟通道的 10 bit 图案是什么？它为什么不过 8b/10b 编码器？
4. `DATA_WIDTH=10` + `DATA_RATE_OQ=DDR` 为什么必须两片 OSERDESE2 级联？
   从片贡献了哪几位？
5. 用三条互不相同的证据说明「250 MHz 域里没有用户逻辑」。
6. `tmds_encoder` 里 `cnt` 的加减混用了无符号与有符号，为什么结果仍然正确？
   什么改动会让它突然不正确？
7. 从 `x_d11` 到 HDMI 管脚，一个像素经过几拍？如果 OSD 判窗少寄存一拍，屏上会看到什么？
