# 08 效果链九级：数学、窗口、流水线、控制位与那笔算得出来的账

被测对象是显示通路里那条**固定深度**的处理链：`src/rtl/process/proc_pipeline.v` 和它例化的八个算法文件
（`gamma_lut`、`proc_gray`、`proc_invert`、`proc_box_blur`、`proc_sharpen`、`proc_sobel`、`proc_binary`、
`proc_morph`），加上把 PS 的控制字送进这条链的 `src/rtl/process/effect_ctrl.v`，以及顶层为这条链做的两处补偿
（读地址提前量与左窗 skid，在 `src/rtl/top/pl_video_top.v`）。旋转/缩放/插值的内部不在这章（第 05/06/07 章）。

读完要能回答这六个问题：

1. 每一位控制字从 PS 的 `Xil_Out32` 走到链子里哪一个 `bypass` 引脚，中间过了几级寄存器；
2. 每一级的数学是什么（核、系数、半径、判定），以及它在 RGB565 上为什么可以不做浮点；
3. 为什么整链延迟恒等于 15 拍、与开了哪一级无关，而内容偏移恒等于 −4 行；
4. 四个窗口级为什么要各自带一套"旗标"，那套旗标落在哪一格是由谁定的；
5. 这条链在硅上到底花了多少（LUTRAM / MUXF7 / 触发器 / 高扇出网），凭据在哪份件里；
6. 链子在全设计的时序名册上占了哪几个席位，哪些"看起来能省"的刀被量过并判负。

---

## 1 前置知识

### 1.1 这条链的接口是"光栅流"，不是握手流

链子的输入是 `de_in / x_in / y_in / din`，输出是 `de_out / dout`
（`src/rtl/process/proc_pipeline.v:38-46`）。这里**没有 ready、没有反压、没有 stall**：显示栅格每拍要么有一个
有效像素（`de=1`），要么在消隐（`de=0`），链子只能跟着走。这个约束决定了本章几乎所有设计选择：

- 一级来不及算完的组合逻辑**只能切拍**，不能"多占几拍慢慢算"，因为下一拍的像素马上就到；
- 行缓存的写地址就是列号，所以列号与数据**必须同拍**，差一拍就是硬件上的一个具体缺陷（见 3.7）；
- 想减少计算量只能靠"把数据提前"或"把地址提前"，而不能靠"等数据齐了再开始"（第 2.3 节）。

### 1.2 RGB565 的位域与 5→8 / 6→8 扩展

一个像素 16 bit：`R[15:11] G[10:5] B[4:0]`。所有需要"按 8 bit 亮度算"的级都要先扩回 8 bit，本设计用的是
**高位复制**而不是左移补零：

```
r8 = {r5, r5[4:2]}      g8 = {g6, g6[5:4]}      b8 = {b5, b5[4:2]}
```

`src/rtl/process/proc_gray.v:18-20` 就是这个式子（`proc_binary.v:19-21`、`proc_sobel.v:33-35`、
`proc_morph.v:30-32`、`src/rtl/video/gamma_lut.v:23-25` 各写了一遍同样的三行）。左移补零会把每个 5 bit 码
映射成 8 bit 轴上的一个"偏下的点"（`31→248`），高位复制把它映射到 `31→255`，端点对端点。与线性映射
`v*255/31` 比，5 bit 那一路最大偏差 0.677、6 bit 那一路 0.714（把 0..31 与 0..63 全扫一遍代出来的数，不引自某份件）
⇒ 误差小于半个最低有效位，这就是可以不做误差补偿的理由。

这四份重复是**故意的**，`src/rtl/video/gamma_lut.v:18-19` 把理由写明了：三处公式必须能被独立核对，谁改了
另一处会在"灰度图与 gamma 图对不上"时暴露。抽公共函数在这里换来的不是整洁，是一个共同的错。

### 1.3 BT.601 亮度为什么变成 77 / 150 / 29

标准权重是 `Y = 0.299R + 0.587G + 0.114B`。乘 256 取整：`0.299×256 = 76.5→77`、`0.587×256 = 150.3→150`、
`0.114×256 = 29.2→29`，三者相加正好 256，于是

```
y16 = r8*77 + g8*150 + b8*29;   y8 = y16[15:8];      // 等价于 (…)>>8，且 >>8 就是取高 8 位
```

写在 `src/rtl/process/proc_gray.v:21-23`。**没有除法器、没有乘法器阵列**：8 bit × 常数，两个乘数最大 255×150，
和的最大值 255×256 = 65280，正好装进 16 bit（`wire [15:0] y16`），取高 8 位就是归一化。这三行在链子里出现
四次（gray / binary / sobel / morph），是同一笔账的四份抄本。

### 1.4 3×3 窗口与行缓存：因果性决定"必然滞后一行"

光栅流是按行往下推的。要算第 `y` 行第 `x` 列的 3×3 窗口，需要 `y−1` 行与 `y+1` 行。`y+1` 行还没到，所以
只能"存旧行"而不是"等未来行"：把上一行、上上一行各存进一条宽度为"一行有效像素数"的行缓存（`lb0`/`lb1`），
于是在收到第 `y` 行数据的当拍，能凑齐中心的只有第 `y−1` 行。这就是一切行缓存式 3×3 滤波的**内容滞后一行**，
不是实现缺陷。四个窗口级串起来，链子的内容偏移就是 −4 行（`src/rtl/process/proc_pipeline.v:23-27`）。

### 1.5 分布式 RAM 而不是 BRAM：为什么窗口级非用 LUTRAM 不可

四条行缓存都写成 `(* ram_style = "distributed" *)`（例如 `src/rtl/process/proc_box_blur.v:19-20`）。原因是
**读必须是异步的**：窗口要在 `de_in` 这一拍就拿到 `lb1[x_in]`，然后同拍组合算出结果再寄存；BRAM 的读出带
一个时钟沿（同步读），会凭空多一拍，而这一拍会打乱整链的 15 拍账与左右抽头的同深关系
（`src/rtl/process/proc_morph.v:42-44` 把这条写成了白话：`mc1` 的读是组合读出，BRAM 做不到，所以原先写
`ram_style="block"` 只会被判 `Synth 8-6849 infeasible` 再自己退回 LUTRAM）。

代价本章第 5 节用实测数算一遍：分布式 RAM 每 64 bit 要一只 `RAMD64E`，深地址还要 `MUXF7` 树。

### 1.6 形态学：结构元素、腐蚀/膨胀的定义，以及"为什么放在阈值之后"

形态学定义在**二值集合**上：用结构元素 SE 覆盖邻域，腐蚀 = 邻域全 1 才 1，膨胀 = 邻域有 1 就 1。
本设计 SE 是 3×3 实心方、半径 1（`src/rtl/process/proc_morph.v:115-119`）：

```
all1 = m00 & m01 & … & m22        // 腐蚀：9 个邻域全是 1
any1 = m00 | m01 | … | m22        // 膨胀：9 个邻域至少一个是 1
res  = (mode == 1) ? all1 : any1;
```

`src/rtl/process/proc_morph.v:2-3` 交代了级序的理由：腐蚀/膨胀本来就是对面具图的操作，放在二值化之后；
"放在灰度图上做 min/max 也能写，但那不是形态学，是另一种局部对比度"。开/闭运算（先腐蚀再膨胀，或反过来）
需要**两遍**窗口，而这里只有一遍，所以控制字里腐蚀与膨胀两位同时置 1 时链子明确旁路（下一节）。

### 1.7 Sobel 的量值：|Gx|+|Gy| 而不是 √(Gx²+Gy²)

标准 Sobel：

```
     ┌            ┐          ┌            ┐
Gx = │ -1 0 +1    │   Gy =   │ -1 -2 -1   │
     │ -2 0 +2    │          │  0  0  0   │
     │ -1 0 +1    │          │ +1 +2 +1   │
     └            ┘          └            ┘
```

本设计照这个权重（`src/rtl/process/proc_sobel.v:111-114`，`×2` 用 `{…,1'b0}` 左移一位实现），但量值取
**曼哈顿和** `mag = |Gx| + |Gy|`（`src/rtl/process/proc_sobel.v:115-117`）。真根号要开方器或查表，而这里
只需要一个"边缘亮不亮"的单调量，曼哈顿和与欧氏距离同为 0 当且仅当同为 0、单调性一致，代价是两处
`|·|`（各 11 bit）与一个 12 bit 加法，随后饱和到 8 bit（`src/rtl/process/proc_sobel.v:118`）。
注意窗口是**先在 8 bit 亮度域里存的**（`src/rtl/process/proc_sobel.v:20-21, 41-42`），所以 Sobel 之后输出还是
把 `m8` 复制成 RGB565 的三个分量（`src/rtl/process/proc_sobel.v:119`）—— 边缘图是灰度的，只是用 565 装。

### 1.8 跨时钟域的控制字：为什么是翻转位而不是脉冲

PS 在 `axi_clk`（100 MHz）域写寄存器，链子在 `clk_pix`（50 MHz）域读。单 bit 走两级触发器同步
（`ASYNC_REG`），宽总线要么"整字 + 翻转位 + 同步沿到了再采"（`src/rtl/eth/snap_cross.v:2-5`），要么像
gamma 表那样用**翻转位当写事件**：`wr` 不是脉冲，因为一个 100 MHz 的单拍脉冲宽度 10 ns，像素域 20 ns 周期
完全可能整拍都看不见它；而"翻转"这件事每 AXI 写必然产生一个电平变化，两级同步之后仍然可辨。
`src/rtl/video/gamma_lut.v:5-6` 与 `src/rtl/process/effect_ctrl.v:36-39` 说的是同一件事的两端。

---

## 2 原理拆解：九级的定义、级序与两张常数账

### 2.1 九位控制字与级序

位定义的唯一出处是 `src/rtl/process/proc_pipeline.v:5-6`：

| 位 | 算法 | 落在哪一级 | 占拍 | 内容偏移 |
|---|---|---|---|---|
| （非控制字）| 级 0 gamma 表 | `u_gamma` | **0**（组合读出） | 0 |
| `[0]` | 灰度去色 | 级 1 第一路 `u_gray` | 1 | 0 |
| `[1]` | 反色 | 级 1 第二路 `u_inv` | 1 | 0 |
| `[2]` | 3×3 均值模糊 | 级 2 第一路 `u_blur` | 3 | −1 行 |
| `[3]` | 3×3 锐化 | 级 2 第二路 `u_sharp` | 3 | −1 行 |
| `[4]` | Sobel 边缘 | 级 3 `u_sobel` | 3 | −1 行 |
| `[5]` | 二值化 | 级 4 `u_bin` | 1 | 0 |
| `[6]` | 判决反相（仅 `[5]=1` 有意义） | 级 4 的 `pol` | 0 | 0 |
| `[7]` | 腐蚀 | 级 5 `u_morph` | 3 | −1 行 |
| `[8]` | 膨胀 | 级 5 同一只 `u_morph` | 3 | −1 行 |

级序是 `gamma → 颜色 → 滤波 → 边缘 → 阈值 → 形态学`（`src/rtl/process/proc_pipeline.v:50-51`）。
这个顺序不是审美：阈值在滤波**之后**，因为形态学的输入必须是面具图；滤波在颜色之后，因为灰度图上的模糊
比 RGB 上便宜（Sobel 那一级的行缓存因此可以存 8 bit 而不是 16 bit，`src/rtl/process/proc_sobel.v:20-21`）。

### 2.2 同一级的两个算法是**串联**的，所以两个都占拍

`proc_pipeline` 里"级"这个词有两层含义，读代码时必须分清：

- 控制字的九个**位**（八种算法 + 一个反相位）；
- 硬件的六个**例化段**（gamma、颜色、滤波、边缘、阈值、形态学）。

同一硬件段的两个算法是**串接**的（`src/rtl/process/proc_pipeline.v:118-129`：`u_blur` 的输出 `d2a` 进
`u_sharp`），只开其中一个时另一个走纯旁路，但**旁路也要占它自己的拍数**——因为旁路是
`dout <= bypass ? center : avg` 这一级寄存器（`src/rtl/process/proc_box_blur.v:147-150`），而不是绕开寄存器的
组合直通。于是逐拍账固定为（`src/rtl/process/proc_pipeline.v:17-21`）：

```
灰度 1 + 反色 1 + 模糊 3 + 锐化 3 + Sobel 3 + 阈值 1 + 形态学 3 = 15
```

`LATENCY = 15` 声明在 `src/rtl/process/proc_pipeline.v:22`，而注释里那条"窗口级是**三拍**不是两拍"
（`src/rtl/process/proc_pipeline.v:19-21`）是这一族踩过的坑：`de_in → de_d1 → de_d2 → de_out` 是三级寄存器
（`src/rtl/process/proc_box_blur.v:144-146`）。顺带一处口径不一致要说清：
`src/rtl/process/proc_sharpen.v:5` 的文件头写"延迟与 blur 一致（固定 2 拍…）"，而同一文件的
`de_d1/de_d2/de_out` 三级（`src/rtl/process/proc_sharpen.v:124-126`）与 `proc_pipeline` 的逐拍账都是 3 拍；
以台架实测为准的口径写在 `src/rtl/process/proc_pipeline.v:20-21`——顶层不许另写一个数，`tb_v86` 的 T2
**实测** `de_in→de_out` 再与 `LATENCY` 对账（`sim/tb_v86_pipe_sel.v:164-167`）。

为什么"固定 15 拍"值得专门保住：顶层左窗（原图抽头）的 skid 长度直接取这个常数
（`src/rtl/top/pl_video_top.v:816-817`），混色级要的标签深度也是由它推出来的
（`localparam MIX_D = 3 + 1 + 1 + u_pipe.LATENCY`，`src/rtl/top/pl_video_top.v:354`）。链子上任何一级偷偷多
或少一拍而常数不改，症状不是"编译错"，而是**缝两侧错开 N 个像素**
（`src/rtl/top/pl_video_top.v:812-815` 写的就是这个事故的前身：那里曾经是字面量 7）。

### 2.3 内容偏移 −4 行、0 列，以及顶层唯一的补法

`OFF_LINES = 4`（`src/rtl/process/proc_pipeline.v:27`）通过端口 `off_rows` 送出去
（`src/rtl/process/proc_pipeline.v:48`），顶层把它接在 `pipe_off_rows`
（`src/rtl/top/pl_video_top.v:236, 808`）。四个窗口级各贡献 −1 行、点运算级不贡献，所以偏移固定。

关键的一步在顶层：`src/rtl/top/pl_video_top.v:244-248` 讲得很直白——"把数据提前"不可能，只能**把地址提前**，
因为片源在帧缓存里、地址本来就是随机的。于是右窗的读行坐标是

```
y_right_adv = y + pipe_off_rows + BILIN_ROWS;        // src/rtl/top/pl_video_top.v:276
y_req_row   = y_right_adv >> 1;                      // 显示行 → 源行（×2 竖向展开）
cy_r        = (y_req_row >= IMG_H) ? y_req_row - IMG_H : y_req_row;   // :284 绕回，不减两次
```

`cy_r` 送进 `u_zmap`（`src/rtl/top/pl_video_top.v:346`）。这里两个细节都是量出来的：`BILIN_ROWS` 必须**偶数**
（`src/rtl/top/pl_video_top.v:249-250`，因为 `row0 = ~y[0]` 按奇偶成对，奇数会让一对分属两个源行），
而取模的对象必须是"请求行"而不是别的（`src/rtl/top/pl_video_top.v:281-283`）。
这条链与效果链的耦合，是第 05 章行环那节的另一半。

### 2.4 每一级的数学，逐个钉死

**gamma（级 0）**：256 项 × 8 bit 表三份（R/G/B 各一张），PS 逐项写。用表不用幂函数的理由写在
`src/rtl/video/gamma_lut.v:4`（PL 里做 `in^(1/γ)` 要堆 DSP 或做对数/指数近似）。三通道"一份三读"要额外读口，
所以复制三份、内容永远由同一个写口保证一致（`src/rtl/video/gamma_lut.v:3-4`，写侧一拍同时写三张
`tr/tg/tb`，`src/rtl/video/gamma_lut.v:41-47`）。读出是**组合**的
（`src/rtl/video/gamma_lut.v:51-52`），因此它不加拍数、`LATENCY` 常数不动；谁把它改成寄存读出，
`LATENCY` 必须同时改成 16（`src/rtl/process/proc_pipeline.v:21`）。写入协议是"先摆 idx/data、下一次写翻转
`wr`"，`PL` 只在 `wr !== prev` 那一拍写一项（`src/rtl/video/gamma_lut.v:34-39`）。

**灰度（`[0]`）**：`gray = {y8[7:3], y8[7:2], y8[7:3]}`（`src/rtl/process/proc_gray.v:24`）——把 8 bit 亮度
截成 5/6/5 再拼回 565。这一级是**去色**不是"只发亮度"，值仍然写进三个分量，所以后级的亮度判定不受影响。

**反色（`[1]`）**：三个字段各自取反（`src/rtl/process/proc_invert.v:14-17`），不是整体 `~din`——后者会把
565 里那段 G 的错位也翻掉，等价但读起来更容易核错，所以按字段写。

**模糊（`[2]`）**：3×3 均值。硬件上没有除以 9，而是 `sum * 57 >> 9`，因为 `57/512 = 0.11133` vs `1/9 = 0.11111`
（`src/rtl/process/proc_box_blur.v:114-121`）。三个通道分别求和：R/B 是 5 bit × 9 → 10 bit，G 是 6 bit × 9 →
11 bit（`src/rtl/process/proc_box_blur.v:104-112`），乘 17/18 bit 常数后取 `[13:9]` / `[14:9]`（同一个
`>>9`），落回 5/6/5。误差来源要说清（0..567 全扫一遍代出来的数，不引自某份件）：`57/512 = 0.11133` 比
`1/9 = 0.11111` 大 0.2 %，但落到整数上几乎看不出来——R/B 那两路（和值 0..279）与 `sum//9` **逐值相同、零个例外**；
G 那一路（0..567）只有 7 个和值差 1（`512/521/530/539/548/557/566`），方向恒为**多 1**。满量程仍映射到满量程
（`279*57>>9 = 31`、`567*57>>9 = 63`）。对模糊这种低通操作没有可见后果，所以判据没有为它单独立一条。

**锐化（`[3]`）**：核 `[0,-1,0 ; -1,5,-1 ; 0,-1,0]`（`src/rtl/process/proc_sharpen.v:2`）。实现成
`5×中心 − 四邻之和`，但**先比较再相减**（`src/rtl/process/proc_sharpen.v:102-104`）：

```
r_d = (r_c > r_n) ? (r_c - r_n) : 9'd0;     然后夹到 [0,31]   // :105
```

`src/rtl/process/proc_sharpen.v:4-6` 把这条讲透了：Verilog 的无符号减法会回绕，"直接 `a-b` 然后判负是错的，
表现是暗边变成一圈亮边"。`5×中心` 是 `<<2 + 原值`（`src/rtl/process/proc_sharpen.v:92`），四邻是三次加法，
没有乘法器。

**Sobel（`[4]`）**：见 1.7。有一个别处没有的结构：本级窗口链存 8 bit 亮度，但旁路要搬的是**原色 RGB565**，
所以额外有一条 16 bit 行缓存 `mc1`（`src/rtl/process/proc_sobel.v:22-27`）与两条原色抽头链
`c11/c12`、`d20/d21/d22`（`src/rtl/process/proc_sobel.v:52-53`）。为什么必须有：全链四个窗口级取旁路时用的是
**同一个中心抽头**，`tb_v84` 的差分判据是"morph 的旁路与 blur 的旁路逐位相同"；以前这里写 `dout <= din`
是"本级自洽"凌驾于"全链一致"，代价是开/关 Sobel 时画面跳一行 + 量到的 +2 列
（`src/rtl/process/proc_sobel.v:23-26, 145-150`）。

**二值化（`[5]`/`[6]`）**：`cmp = (y8 >= threshold)`，`bin = pol ? ~cmp : cmp`，输出全白 `16'hFFFF` 或全黑
`16'h0000`（`src/rtl/process/proc_binary.v:22-25`）。`[6]` 是同一级的**第二个算法**而不是叠加，所以 OSD
那一格不能报"3"（`src/rtl/video/osd_overlay.v:136-138`，第 09 章）。

**腐蚀/膨胀（`[7]`/`[8]`）**：见 1.6。亮度判定在**输入处**做一次（`src/rtl/process/proc_morph.v:33-34`，
与 `proc_binary` 同一公式同一对白/黑），所以掩码只需要 1 bit/像素，两条掩码行缓存各 H_ACTIVE bit
（`src/rtl/process/proc_morph.v:40-41`）。这两条数组的**声明形状**付过一次学费：写成
`reg [0:H_ACTIVE-1] mb0` 是一根 1024 位的向量，综合推断不出 RAM（`Synth 8-7186 … using registers`），
掩码行缓存变成 2×H_ACTIVE 个触发器、两个异步读口各变成一棵 1024:1 的 LUT 树，`r83` 之前就是这个状态，
凭据 `src/rtl/process/proc_morph.v:36-39`；那段注释自己点名的构建日志 `build/r80_build2.log` **已不在当前树上**，
所以这一笔可以引注释、不能再当作可复现的件。

### 2.5 三处互斥语义（都是"明确旁路"而不是"偷偷做一个"）

```
wire w_erode  = stage_sel[7] & ~stage_sel[8];   // 两位同时 1 ⇒ 两个都不做
wire w_dilate = stage_sel[8] & ~stage_sel[7];
wire [1:0] morph_mode = w_erode ? 2'd1 : (w_dilate ? 2'd2 : 2'd0);
```

`src/rtl/process/proc_pipeline.v:59-61`。`mode==3` 在 `proc_morph` 里同样算旁路
（`src/rtl/process/proc_morph.v:22-24`：开/闭要两遍 3×3，这里只有一遍，"代价写在注释里而不是藏在 mux 里"）。
判据在 `sim/tb_v86_pipe_sel.v:234`（T14：腐蚀|膨胀同时要 = 旁路，与全旁路帧逐位相同）。
第三处是 `[2]/[3]`（模糊/锐化）——它们是**同一级的两个选项**，控制字里各占一位、硬件上串联
（`src/rtl/process/proc_sharpen.v:2-3`：先模糊再锐化几乎等于什么都没做）。

---

## 3 代码逐段分析：四个窗口级的共同骨架

四个窗口级（blur / sharp / sobel / morph）结构**逐条同形**，这不是抄来的省事，而是
`src/rtl/process/proc_morph.v:4-7` 写明的要求：窗口级各自挑一种 de/数据对齐方式，混在一条链里就会在切换效果的
瞬间错一行。下面把这套骨架拆成四段，以 `proc_box_blur.v` 为正本（其余三处指回它）。

### 3.1 写侧：只在 `de_in` 那一拍写，按 `x_in` 索引

```
if (de_in) begin lb0[x_in] <= lb1[x_in];  lb1[x_in] <= din;  end
```

`src/rtl/process/proc_box_blur.v:44-49`。语义是"把上一行挤到上上行，本行进上一行"。消隐期不写，因为
消隐期的 `din` 不是像素。`proc_sobel` 多写一条 16 bit 的原色缓存（`src/rtl/process/proc_sobel.v:39-45`），
`proc_morph` 写两条掩码 + 一条原色（`src/rtl/process/proc_morph.v:46-52`）。

### 3.2 读侧：地址钉在末列

```
wire [11:0] x_rd = (x_in >= H_ACTIVE) ? (H_ACTIVE - 1) : x_in;
```

`src/rtl/process/proc_box_blur.v:42`（`proc_sharpen.v:43`、`proc_sobel.v:48`、`proc_morph.v:54` 同一行）。
这一句同时干两件事：① 消隐期 `x_in` 会走到 porch（顶层一屏数到 1343，而行缓存只有 1024 深），不钉住就是
越界读——xsim 给 X、硬件按地址位截断读到别的列；② 钉在末列正好是 **clamp-to-edge** 的复制边像素语义。

### 3.3 行尾补跳：`run` 计数而不是 `de` 断点

3×3 窗口的中心抽头是 `p11 <= p12 <= 行缓存读`——当拍读到的那一格要**再跳一拍**才成为中心。而移位整个被
`de_in` 钉住 ⇒ 行内最后一个有效像素读完、下一拍就是消隐，那一跳永远不来 ⇒ 每行少发一个样本，而输出流仍按
`de_out` 数够格子 ⇒ 最后一格只能重复前一列。这就是 `src/rtl/process/proc_box_blur.v:25-28` 记的那一笔
（台架 `tb_v89_align` 的 ID 判据：`first col=31 dc=-1`）。

修法要三句才说得完，而每一句都是踩过才知道的（`src/rtl/process/proc_box_blur.v:29-38`）：

```
always @(posedge clk or negedge rst_n)
    if (!rst_n)     run <= 12'd0;
    else if (de_in) run <= run + 12'd1;
    else            run <= 12'd0;                 // 清零必须 de 一断就清
wire owed     = (run == H_ACTIVE);                // 刚吃完的是末列
wire line_end = owed && de_d1 && !de_in;          // 只有一拍：就是现在欠那一跳
wire shift_w  = de_in || line_end;
```

- **只能数连续有效像素**：拿 `de_d1 && !de_in` 当行尾，在"一拍一像素"的激励下每个像素后面都算行尾，模糊整个
  坏掉（`src/rtl/process/proc_sharpen.v:32-34` 记了 2026-09-26 那次红）；
- **再加 `x_in == H_ACTIVE-1` 那一版**模块级全绿、顶层一次都没武装，因为顶层喂链子的 `x_d[3]` 与 `de_d[3]`
  不同级 ⇒ 依赖标签的判据不可用（`src/rtl/process/proc_box_blur.v:29-31`，实测读数在
  `build/r112_reasm_probe.txt` 之外另有台账，见 `开发台账`（#92 收尾那一节）：顶层探针打到
  `blur de=0 x=1032`，`flush=28200` 恰等于 `pipe_de/1024`）；
- **清零晚一拍等于永远不清**：行间隙只有一拍的激励下，`run` 在 `de` 落下那一拍的非阻塞旧值正好是本行宽度
  （`src/rtl/process/proc_box_blur.v:35`）。

`shift_w` 之后，三条抽头链**都**跟着它走，包括当前行那一路（`src/rtl/process/proc_box_blur.v:134-143`）：

```
p00<=p01; p01<=p02; p02<=r0;
p10<=p11; p11<=p12; p12<=r1;
p20<=p21; p21<=p22; p22<=de_in ? din : p22;    // 消隐 ⇒ 末列重复一次
```

只让上面两行跳的话，末列那一格的"下面一行"还停在倒数第二列 ⇒ 窗口整体错一列，而补上来的那一格既不是
clamp 也不是原始平均——`tb_edge_rim` R4 量到 `got=8c51`，而四个候选 `clamp=b596 / raw=d69a / 折回=83f0`
全不是（`src/rtl/process/proc_box_blur.v:137-141`）。

### 3.4 边界：四根旗标，落在哪一格由台架量

四条圈（左/右/上/整行陈旧）不是"一个 border 位"，而是四条 3 级移位旗标，与中心链同拍移位
（`src/rtl/process/proc_box_blur.v:66-85`）：

```
no_left_r  [0] <= ~de_in;                                    // 补跳那一拍 = 下一行第 0 槽
no_right_r [0] <= de_in && (x_in == H_ACTIVE-1);             // 末列
no_above_r [0] <= de_in && (y_in == 1) && row_first;         // 中心行 0，上面缺
stale_row_r[0] <= de_in && (y_in == 0);                      // 中心行 −1：整行都是旧的
```

`tb_edge_rim` 第一次把"边缘条带"变成一个坐标，量出三条事实（正本在
`src/rtl/process/proc_box_blur.v:54-59`，另三处各指回它，`proc_sharpen.v:47-50`、`proc_sobel.v:66-69`、
`proc_morph.v:75-78`）：

1. 拍 `k`（`x_in==k`）武装的旗标落在**槽位 k+1** ⇒ 旧写法 `x_in==0` 管的是第 1 列，真正的第 0 列没人管；
2. 行尾补跳那一拍武装的旗标落在**下一行的第 0 槽**（旧代码在这里塞 `1'b1`，那是"单旗标时代末列也算边界"的
   遗留）⇒ 第 0 列被旁路成原图直出（实测 `got==raw`）⇒ **左边一条带**；
3. 中心行 = 输入行 − 1 ⇒ 每帧第一个输出槽吃的中心是**上一帧的末行** ⇒ **上边缘那条带**：不是位置错、
   不是没裁黑，是**内容陈旧**（旧的 `y_in==0` 只标"缺上邻"、标不住整行都是旧的）。

`row_first` 是这一族里最微妙的一位：`wire row_first = (y_in != y_row_d)`，`y_row_d` 在行尾锁存本行 `y_in`
（`src/rtl/process/proc_box_blur.v:60-64`）。因为顶层是 ×2 竖向展开，同一个源行有两个显示行，只有**第一个**
才真的缺上邻。

旗标到位之后，边界处理是两级 mux：先水平后垂直，缺的邻居复制**中心那一列/中心那一行**
（`src/rtl/process/proc_box_blur.v:89-101`）：

```
h00 = no_left ? p01 : p00;   h02 = no_right ? p01 : p02;   // 水平：复制中心列
e00 = stale_row ? h20 : (no_above ? h10 : h00);            // 垂直：陈旧 ⇒ 用当前行
e10 = stale_row ? h20 : h10;
```

这样窗口宽度不变、值与内部连续，最外圈不再"直出原图"——那条断层就是用户报的带。腐蚀/膨胀用同一套
（`src/rtl/process/proc_morph.v:104-113`）：腐蚀在左沿不会因为"外面算 0"而被啃掉一圈，膨胀也不会因为行缓存里
是上一帧的尾巴而凭空鼓一圈。

还有一条容易漏：**旁路也得跟着换中心**。`wire [15:0] center = stale_row ? e21 : p11`
（`src/rtl/process/proc_box_blur.v:125`），`proc_morph` 同理 `by ? (stale_row ? c21 : p11) : …`
（`src/rtl/process/proc_morph.v:142`），`proc_sobel` 是 `stale_row ? d21 : c11`
（`src/rtl/process/proc_sobel.v:150`）。中心抽头在陈旧行上是上一帧的尾巴，旁路不换的话，"关掉效果"时上边缘那条
陈旧带原样还在。

### 3.5 复位卫生：一条旗标的复位只能写在一个块里

`src/rtl/process/proc_box_blur.v:66` 与另三处同一句警告：把 `no_left_r` 等的复位写进主 always 的复位分支，
就是**两个驱动源** ⇒ 综合报 `Synth 8-6859/8-6858 multi-driven net` 并把逻辑那一侧**忽略**（恒 0），
而仿真看不出来（xsim 按进程后写覆盖）。门禁第 13 项拦的就是它。这条对本章的意义是：窗口级的边界旗标如果
综合成恒 0，屏上的症状是"最外圈永远走 clamp 分支"，而不是任何一条错误信息。

### 3.6 形态学那一级的 `mode` 与掩码宽度

`proc_morph` 与另三级的唯一结构差别：掩码 1 bit、判定在输入处（2.4 已述），以及它用 `dv_d1/dv_d2` 而不是
`de_d1/de_d2` 命名（`src/rtl/process/proc_morph.v:63`），因为同一段里有 `din` 的原色链要区分开。
输出 `de_out <= dv_d2`（`src/rtl/process/proc_morph.v:139`）后面照旧标着"三拍，不是两拍"。

### 3.7 坐标标签链：`xd[1:12]` / `yd[1:12]`，以及 #103 那根黑线

四个窗口级不能共用顶层那一份 `x_in/y_in`：每一级的 `de_in` 是上一级的输出、逐段累积地晚 1/3/3/3 拍，
所以第 k 级拿到像素那一刻，顶层坐标已经在说"第 (n+累积延迟) 个像素"（`src/rtl/process/proc_pipeline.v:71-74`）。
链子里的修法是给坐标装一条与 de 同节奏的自由运行延迟线，每级取自己那一拍：

```
xd[1] <= x_in;  for (cp=2..12) xd[cp] <= xd[cp-1];
x_blur  = xd[2];   x_sharp = xd[5];   x_sobel = xd[8];   x_morph = xd[12];
```

`src/rtl/process/proc_pipeline.v:85-98`。抽头号 = 该级 `de_in` 之前累积的拍数（2/5/8/12）。
口径"**`xd[k]` 必须恰好 k 拍**"是 #103 的根因（`src/rtl/process/proc_pipeline.v:75-81`）：以前第一跳写的是
`xd[0] <= x_in`，于是 `xd[k]` 实际是 k+1 拍 ⇒ 四个窗口级的列标签比它自己的数据晚一整拍。后果有两条，
都在硬件上：

1. 每行最后一个有效拍上 `x_in` 只到 `H_ACTIVE-2` ⇒ 槽位 `H_ACTIVE-1` 永远没人写（上电读 0）；
2. 每行第一个有效拍上 `x_in` 还停在消隐末尾（顶层一屏数到 1343）⇒ **写地址越界**：xsim 丢掉这一笔，
   硬件按地址位截断成 `1343 mod 1024 = 319` ⇒ 每行往 319 号槽写进消隐期的 0x0000，而读回它的是真实列 320
   那一拍 ⇒ 板上一根钉死在显示列 320（源列 160）的 1 像素纯黑竖线。

判据是 `sim/tb_v103_pipe_bypass.v` 的 C10d（槽位完整性）与 C10f（越界写），改前两条都红
（`src/rtl/process/proc_pipeline.v:81`；`sim/tb_v103_pipe_bypass.v:214-220` 把"仿真丢掉 / 硬件截断"这一对
分家写在了判据注释里）。这也是 #92 那一族 `no_right_r` 武装位从 `-2` 改回 `-1` 的原因
（`src/rtl/process/proc_box_blur.v:74`）。

这条链的代价在文件里就标了：纯寄存器、每拍一跳、不参与任何运算，每跳 12 bit ⇒
`2×12×12 = 288` 个触发器（`src/rtl/process/proc_pipeline.v:82`，按 Slice 寄存器 7936 的 3.6 % 记的那一次）。
它在硅上的第二笔代价是**扇出**，见 5.3。

---

## 4 控制字：一位从 PS 走到 RTL 引脚的完整旅行

取 `[2] = blur` 这一位。链路上每一跳都有出处。

| 步 | 位置 | 发生了什么 |
|---|---|---|
| 1 | `src/ps/main.c:897`（`dispatch`）/ `:899-909`（`PIPE`） | 串口收到 9 个 '0'/'1' |
| 2 | `src/ps/main.c:576-590`（`parse_bits`） | `en \|= (s[i]-'0') << i` ⇒ **第 0 个字符 = bit0 = gray**；长度只收 9（5 位数得出来但只为翻译，`:583,587`） |
| 3 | `src/ps/main.c:454-458`（`ctrl_set_sel`） | `cur_sel = sel & 0x1FFu`，然后 `ctrl_apply()` |
| 4 | `src/ps/main.c:223-225`（`ctrl_write`） | `Xil_Out32(CFG_DATA0, (cur_sel & 0x1FFu) \| …)`；`CFG_DATA0 = 0x41220000`（`src/ps/main.c:77-78`），**一次整字写** |
| 5 | `src/rtl/top/system_top.v:86` | `axi_gpio_2` 的 `GPIO_2_tri_o` = `gpio_cfg1_o[31:0]`（声明在 `:51`）；基址由 `build/tcl/build_system_axigpio.tcl` 钉死并回读校验（`src/ps/main.c:71-76`） |
| 6 | `src/rtl/top/system_top.v:264` | `.stage_sel(gpio_cfg1_o[8:0])` 接进 `pl_video_top`（端口声明 `src/rtl/top/pl_video_top.v:30`） |
| 7 | `src/rtl/top/pl_video_top.v:198-200` | `effect_ctrl u_eff(... .stage_sel_async(stage_sel) …)`，这里是 **axi → pix 的跨域入口** |
| 8 | `src/rtl/process/effect_ctrl.v:34,50-51` | `sel_meta <= {zoom_manual, zoom_sel, stage_sel};  sel_sync <= sel_meta;`，两颗 `ASYNC_REG` 触发器 |
| 9 | `src/rtl/process/effect_ctrl.v:70-72` | `assign stage_sel = sel_sync[8:0]` |
| 10 | `src/rtl/top/pl_video_top.v:802` | `.stage_sel(sel_sync)` 接进 `proc_pipeline` |
| 11 | `src/rtl/process/proc_pipeline.v:54` | `wire w_blur = stage_sel[2]` |
| 12 | `src/rtl/process/proc_pipeline.v:119-120` | `proc_box_blur #(.H_ACTIVE(H_ACTIVE)) u_blur(.bypass(~w_blur), …)` |
| 13 | `src/rtl/process/proc_box_blur.v:147-150` | `dout <= bypass ? center : avg;` —— 这一行就是终点 |

三个值得停下来的细节：

**① 只有两位触发器，且这 13 位在同一条链上。** `sel_meta/sel_sync` 是 13 bit：
`{manual, zsel[2:0], stage[8:0]}`（`src/rtl/process/effect_ctrl.v:34`）。缩放的两个位被**并进这一条**而不另开
一组，理由是 PS 用一次整字写同时改它们，而 `zoom_ctrl` 把 `manual` 与 `zsel` 当一对用；分两组同步就会出现
"旗标到了、档号还是上一次的"（`src/rtl/process/effect_ctrl.v:30-33`）。gamma 那 32 bit 同理走
`gm_meta/gm_sync`（`src/rtl/process/effect_ctrl.v:39,54-56`），因为协议要求"idx/data 在 `wr` 翻转之前已经
稳定至少一次 AXI 写"。

**② 只有一套控制源。** V7 那五位 `effect_en` 的兜底合流与"反翻五位给 OSD"的第二出口一起删了
（`src/rtl/process/effect_ctrl.v:5-7`，`src/ps/main.c:4-6` 与 `:460-468` 的 `legacy_to_sel` 只剩翻译用途）。
理由写在 `src/rtl/process/effect_ctrl.v:6-7`：留着它，`pipe 00111` 与 `pipe 000000111` 就是两种答案。
PS 侧 `gpio_o[4:0]` **保留但恒写 0**（`src/ps/main.c:211-213`），PL 侧不接
（`src/rtl/top/system_top.v:262-263`）——位还占着是因为整字是 32 位，重排位序会把按位写的外部工具全打乱。

**③ 复位值本身是一条语义。** `th_meta/th_sync` 复位成 `8'd80`（`src/rtl/process/effect_ctrl.v:44`）而不是 0，
`gm_*` 复位成 `32'h0000_00FF`（`:48`）——低字节两个半字节都不是十进制数字 ⇒ OSD 那一格画 `--`，即"还没有可信
读数"。若复位成 0，屏上会在 PS app 起来之前画出 `Temp:00C`，那是一条没人测过的数。

链子内部**没有第二条口径**：`stage_sel` 九位逐位直连，不留兜底合流
（`src/rtl/process/proc_pipeline.v:50-61`）；给 OSD 的也只有 `sel_sync` 这一个出口
（`src/rtl/top/pl_video_top.v:1007`，`src/rtl/process/effect_ctrl.v:26-27`）。

### 4.1 链子收到的坐标与 de 是从哪一拍来的

顶层例化（`src/rtl/top/pl_video_top.v:800-810`）：

```
proc_pipeline #(.H_ACTIVE(2*IMG_W)) u_pipe (
    .stage_sel(sel_sync), .threshold(th_sync),
    .gamma_en(gm_en), .gamma_wr(gm_wr), .gamma_idx(gm_idx), .gamma_data(gm_data),
    .rotate_active(rot_on),
    .hs_in(hs_d[3]), .vs_in(vs_d[3]),
    .de_in(de_d[3]), .x_in(x_d[3]), .y_in(cy_d[3]),
    .din(pix_raw), .off_rows(pipe_off_rows), .de_out(pipe_de), .dout(pipe_dout));
```

三件必须说清的事：

- **`H_ACTIVE = 2*IMG_W = 1024` 是"一行有多少个有效拍"，不是屏幕有多宽**
  （`src/rtl/process/proc_pipeline.v:9-15`）。r59b 定下"整屏单地址流"之后，同级相邻两列在源上只差半格，
  横向模糊/锐化/Sobel 的空间尺度因此是**半个源像素**（窗口横向覆盖 3 个显示列 = 1.5 个源列，半径
  ±1 显示列 = ±0.5 源列，与顶层 `src/rtl/top/pl_video_top.v:797-798` 那句"横向覆盖 1.5 个源列"同向）。
  这是既成事实、不是待评估的新风险；`src/rtl/top/pl_video_top.v:796-799` 把代价写死在那里：行缓存宽度翻倍，
  横方向的模糊/边缘比旧版略宽。
- **喂进链子的 `y` 是 `cy_d[3]`（源行），而 `x` 是 `x_d[3]`（显示列）**，链子里"行"两个显示行同名照旧
  （`src/rtl/top/pl_video_top.v:807`）。这正是 3.4 里 `row_first` 必须存在的原因。
- **`rotate_active` / `hs_in` / `vs_in` 目前是死接线。** `src/rtl/process/proc_pipeline.v:37-39` 声明了
  `rotate_active` 但整个文件里除声明外没有一次引用；`hs_in/vs_in` 只往下传给
  `u_blur`（`:121`）与 `u_sobel`（`:134`），而 `src/rtl/process/proc_box_blur.v:10-11` 的两个端口在文件里
  也只出现于声明、`src/rtl/process/proc_sobel.v:12` 的 `vs_in` 同理。顶层仍然为它们打了两级标签
  （`hs_d[3]/vs_d[3]`，`src/rtl/top/pl_video_top.v:805`）。也就是说：窗口级的"上一帧/上一行"边界问题从来不是靠
  `vs` 解决的，而是靠 3.4 那四根旗标 + 顶层 `cy_r` 的绕回钳位解决的
  （`src/rtl/top/pl_video_top.v:278-284`）。读代码时把这三根线当"预留"看，不要当逻辑看。

### 4.2 链子出口到混色级：两个抽头必须同深

链子只有 `PROC_LAT` 拍，而原图那一路是 `raw_line_delay`（1 拍 RAM 读出）+ `orig_skid`（`PROC_LAT` 拍）
= `PROC_LAT+1` 拍 ⇒ 处理抽头比原图抽头**早一整拍**。`src/rtl/top/pl_video_top.v:819-829` 记了这笔：
1.00× 时画面铺满整屏看不出来，一缩小左边界就把"画面自己最左那一列"甩进背景带、右边界少一列——
用户念的"贴在边上的一条线"这一笔占一列。修法是给处理抽头补一级寄存器 `pipe_dout_q`（`:825-829`），
凭据 `tb_v98` 的 C1c/C2（恒为一列、不随倍率变 ⇒ 是整拍之差，不是取整偏差）。

配套的还有 `MIX_D = 3 + 1 + 1 + u_pipe.LATENCY = 20`（`src/rtl/top/pl_video_top.v:351-355`）：混色级要的列
坐标**必须由流水线深度推出来，不许再抄字面量 11**——以前 `u_split` 拿的是 `x_d[11]`，缝的判定比内容旧 9 列
（`src/rtl/video/split_display.v:9-14` 记的是同一件事的另一半：标签说左窗、内容其实是右窗那一路被清零 ⇒
一条近黑的竖带）。

---

## 5 这条链在硅上花了多少（全部给件，不给口算）

下面所有数都出自在盘上的件，并注明那一次读数的日期；不同轮的件**不许互相加减**。

### 5.1 总量口径

`build/utilization.rpt`（`report_utilization`，Design State: Routed，2026-10-04 04:37，头 12 行）：

| 资源 | 用 | 可用 | 占比 | 出处 |
|---|---|---|---|---|
| Slice LUTs | 14154 | 53200 | 26.61 % | `build/utilization.rpt:35` |
| ├ LUT as Logic | 9969 | — | 18.74 % | `:36` |
| └ LUT as Memory | 4185 | 17400 | 24.05 % | `:37` |
|  LUT as Distributed RAM | 4044 | — | — | `:38` |
| Slice Registers | 8188 | 106400 | 7.70 % | `:40` |
| F7 Muxes | 1164 | 26600 | 4.38 % | `:43` |
| Block RAM Tile | 95.5 | 140 | 68.21 % | `:106` |
| DSPs | 19 | 220 | 8.64 % | `:121` |

链子的可见成本几乎全在 **LUT as Distributed RAM** 那一行里。这一行能被独立复算：同一份位流打开时的
Unisim 变换小结写着 `RAM128X1D => (MUXF7(x2), RAMD64E(x4)) 336`、`RAM64M => (RAMD64E(x4)) 651`、
`RAM64X1D => (RAMD64E(x2)) 48`（`build/r88_resource_owners.txt:44-46`），
`336×4 + 651×4 + 48×2 = 1344 + 2604 + 96 = 4044`，与 `build/utilization.rpt:38` 的 4044 **逐位对上**。
这一条对账的价值在于：它证明"分布式 RAM 4044"不是综合器的口头报价，而是可以从基元计数推出来的。

### 5.2 归属：四个窗口级吃掉 LUTRAM 的 72 %

`build/r88_resource_owners.txt`（2026-09-29 15:50 的一次只读 DCP 探针，按两级实例路径分组）：

| 基元 | 数量 | 归属 | 出处 |
|---|---|---|---|
| RAMB36E1 | 80 | `u_pl/u_bilin`（显示帧缓存，不是链子） | `:71` |
| RAMD64E | 928 | `u_eth/u_saver`（打包器） | `:72` |
| RAMD64E | 864 | `u_pl/u_blur` | `:73` |
| RAMD64E | 864 | `u_pl/u_sharp` | `:74` |
| RAMD64E | 768 | `u_pl/u_sobel` | `:75` |
| RAMD64E | 416 | `u_pl/u_morph` | `:76` |
| RAMD64E | 108 | `u_pl/u_row` | `:77` |
| RAMD64E | 96 | `u_pl/u_pipe`（链子自己那一段） | `:78` |
| MUXF7 | 256 / 256 / 186 / 128 | `u_blur` / `u_sharp` / `u_pipe` / `u_sobel` | `:79-82` |
| MUXF8 | 72 | `u_pl/u_pipe` | `:84` |
| LUT6 / LUT5 | 765 / 324 | `u_pl/u_pipe` | `:85, :96` |
| FDCE | 910 | `u_pl/u_pipe` | `:109` |

四个窗口级合计 `864+864+768+416 = 2912` 只 RAMD64E，占那一次 4044 的 **72 %**——这个 72 % 是
`优化流水账` 里那张归属表自己给出的口径，与上面四行相加一致。
为什么 `u_blur` 与 `u_sharp` 数量相同而 `u_sobel` 少 96：前两者的行缓存是 2 × 16 bit，Sobel 是
2 × 8 bit + 1 × 16 bit；`u_morph` 只有 2 × 1 bit 掩码 + 1 × 16 bit 原色，所以最少。
MUXF7 那 926 只是深地址译码树，它是行缓存的**附属开销**，行宽减半这些也一起减半
（这段因果写在 `优化流水账` 那张归属表）。

同一份快照里 `u_pipe` 还挂着 FDCE 910——3.7 那条 `xd/yd` 延迟线按参数是 288 只，剩下的来自 `run`、四根旗标链、
抽头寄存器与 skid。这一条给出了一个可复用的判断：**窗口级链子的触发器成本里，"不参与运算的标签搬运"是
主导项之一**，它不会因为某个算法关掉而减少（旁路也占拍、也占寄存器）。

### 5.3 链子的坐标链是全设计扇出榜上的常客

`build/evidence/r114_after_roster_probefmt.txt:33-36` 的高扇出名册里，四条并列：

```
FANOUT|fo=548|net=u_pl/u_pipe/xd_reg[12][0]_0
FANOUT|fo=548|net=u_pl/u_pipe/xd_reg[12][1]_0
FANOUT|fo=548|net=u_pl/u_pipe/xd_reg[12][2]_0
FANOUT|fo=548|net=u_pl/u_pipe/xd_reg[12][3]_0
```

`xd[12]` 是喂给形态学级的那一拍坐标（`src/rtl/process/proc_pipeline.v:98`），每一 bit 扇出 548。
这份名册里排在它前面的只有 Ethernet 打包器 `u_eth/u_saver/wptr_reg[*]`（598~603，`:22-32`）与三只钟网
（`:18-21`）。这条读数对读代码的实际意义：链子的**坐标**与它的算术一样是物理负担，而且它的形状（一根网挂
548 个负载）与 `rows_hit` 那一族是同一种问题。

### 5.4 广播网的解法边界：复制驱动量过、判负，没进主线

先给一件链子外部但被反复引用的事：**`rows_hit` 的 CE 广播曾经是全设计最差路径。**
`开发台账` #96 之后的 r106/r107 记录里写得很硬：

- `build/r107_reasm_probe.txt:7`：r106 基准 `0.723ns | eth_rxc | 6.879ns | 5 级`，起点
  `off_reg[12]/C → rows_hit_reg[10..15]/CE`，route 占 81.25 %；最差 8 条里这一族占 6 条
  （对照 `build/r106_critpath_console.txt:103-108`）。
- `build/r107_reasm_probe.txt:42`（判读第 1 条）：这一族 `0.723 ns（当时全设计最差、最差 8 条占 6 条）
  → 2.006 ns，5 级 → 4 级`，r107 的十个最差里已经没有 `u_reasm`。
- `build/evidence/r109_clk01_after.txt:24-25`：r109 那一刀之后全局 WNS **0.605 ns**，最差标本
  `u_eth/u_reasm/off_reg[11]_rep/C → u_eth/u_reasm/rows_hit_reg[2..4]/CE` ⇒
  **全局瓶颈回到 `rows_hit` 位图的使能广播**。
- 现在的读数（`build/crit_paths.txt:6-10`，同一份 `timing_summary` 那一轮）：这一族在
  `1.017~1.019 ns`，排在三条 ICMP 校验和路径之后；全设计 WNS 0.739 ns
  （`build/timing_summary.rpt:151`，TNS 失败端点 0）。

链子自己的对应物就是 5.3 那 `fo=548`。于是有人把同一把刀朝链子方向试了三次，**三次都量到底、三次都没采纳**：

| 刀 | 机制是否动了 | 买到什么 | 代价 | 判定与件 |
|---|---|---|---|---|
| C1：对名册里 39 根 `fo≥200` 的广播网强制复制 | `REPLICA_CELLS` A=0 → B=**310**（`build/evidence/r115_fanout_ab/verdict_header.txt` F3） | `clk_fpga_0` setup 相对余量 0.185→0.1959、`clkout0_1` 0.1815→0.195 | 32 次比较里 **4 格红**（`eth_rxc` setup/hold、`sys_clk` setup、`clk_fpga_0` hold），FF `8188→8463`（+275）、LUT-as-Logic `9969→10004`（+35） | **判负**：`F5_roster_diff … verdict=RED`（同一份件）；结论口径见 `build/runs/ledger.md:460`"结论不是复制没用，而是在 `eth_rxc` 没有可信 hold 余量之前，复制的代价由它付" |
| r114：同一把刀在 `p_eof → rows_hit[*]/CE` 目标族上 | `REPLICA_CELLS` 0→**296**，`u_pl/u_clk/u_mmcm_0` 扇出降 58 | 目标族 `0.445 → 0.901 ns`（+0.456） | `eth_rxc` hold `0.050 → 0.035`（相对余量 −29.0 %），LUT +31，`D3_margin_cost … big_loss=1 RED` | **DECLINE**：`build/evidence/r114_mf/verdict.txt:36-41`（`MF-SUMMARY … verdict=DECLINE`）；登记在 `刀口台账` C1 行 |
| C9 / r117：只点 `u_pl/u_row/hi_reg_0[0]` 一根 | 钩子真落上：`net=u_pl/u_row/hi_reg_0[0] pins_after=1 replica_cells=10` | `clk_fpga_0` setup `1.850 → 2.104` | `clkout0_1 3.630→3.353`、`eth_rxc 0.739→0.615` 且 hold `0.052→0.044`、`sys_clk 14.876→14.815` **四格变小** | **DECLINED**：`build/r117_verdict_declined.txt`（含"两把尺子对同一份数据给不同判语"这条口径债登记）；`刀口台账` C9 行 `status=declined` |

三刀的判据形状都遵循同一条规矩（`build/r114_replication_ab.sh:23-24` 把它写在脚本头）：
**先证机制能动（两个独立来源），再谈收益，再看逐域名册与资源**；机制没动判 `MECHANISM_INERT`，不许写成
"时序收益不成立"。还有一条更硬的：**头条 WNS 的绝对差只念不判**。
链子内 `fo=548` 那四根网因此仍然挂着——不是没人看见，是**买它的代价在别的域上**。

### 5.5 链子在名册上的两个真实席位

**hold 席位归链子。** `build/timing_summary.rpt:863-868`：`clkout0_1`（50 MHz 像素域）最差的 hold 路径是

```
Source:  u_pl/u_pipe/u_sobel/no_right_r_reg[0]/C
Dest:    u_pl/u_pipe/u_sobel/no_right_r_reg[1]/D
Slack 0.059 ns，Data Path Delay 0.378 ns（logic 0.141 / route 0.237 = 62.7 %），Logic Levels 0
```

这就是 3.4 那条边界旗标移位链的第一跳：0 级逻辑、纯布线延迟撑起来的 0.378 ns，起点在 `SLICE_X48Y45`、终点在 `SLICE_X51Y45`（同一份件 `:893, :897, :913`）。它说明一件容易被忽略的事：**在 50 MHz 域里，最短的链反而最容易成为
hold 纪录保持者**，而它的余量由放置与布线决定，不由 RTL 决定。同域 setup 的最差是
`u_pl/x_d_reg[20][3]/C → u_pl/u_osd/ch_r_reg/ADDRARDADDR[6]`，3.630 ns、22 级、route 59.15 %
（`build/timing_summary.rpt:740-748`）——那是第 09 章的主题，但起点 `x_d[20]` 正是 4.2 里由
`MIX_D = … + u_pipe.LATENCY` 推出来的那一级标签，链子的深度**通过这束标签**参与了它。

**唯一的大杠杆被算过、并明确没动。** `src/rtl/top/pl_video_top.v:796-799` 与
`优化流水账` 给的是同一个判断：把 `H_ACTIVE` 从 `2*IMG_W` 改回 `IMG_W`
（链子搬到 ×2 展开之前），四个窗口级的行缓存与 MUXF7 树一起减半，粗估能拿回 1450 个左右 LUT。三条不改的理由
写在那节里，摘要如下——语义会变（等效核半径变成源图的一半，模糊/Sobel/形态学连通域尺寸一起变，
"这不是换个参数，是换效果"）；判据要重做（`MIX_D/LATENCY/OFF_LINES` 那一套对齐与 `tb_v98` 的逐像素判定都以
"展开后"为前题）；收益不确定到不值得用一次顶层重构去换（LUT 才 26.99 %）。这一条与 #105 第一刀
（给 `dc_fifo` 的 `wr_full` 加 `max_fanout=12`，想让综合复制高扇出网表）同一种"看着像免费、其实换了行为"的形状，
那一次量到的是**没有任何资源收益**（`优化流水账`）。

### 5.6 打包器那 512/512：承重的，而且"BRAM"这个说法要更正

`build/r88_packer_peak_gap0.txt:24`：

```
PROBE packer peak_occupancy=512 words of depth=512  （FW=9；这一数决定 100bit×512 那 ~800 个 LUTRAM
     能不能削 —— 峰值远低于半深才谈得上降 FW）
```

对照同一支台架限速那一档 `build/r88_packer_peak_throttled.txt:2`：`peak_occupancy=122 words of depth=512`。
⇒ GMII 线速连灌时打包 FIFO **填满**，限速 15 MB/s 时只用 122/512 且零丢。

两处口径必须说准：① 这个 512/512 是**深度**（字数），不是资源占用率；② 它是 **LUTRAM**——
`{q_addr, q_data, q_keep}` 100 bit × 512 ≈ 800 只 RAMD64E（实测归属 928，`build/r88_resource_owners.txt:72`），
属于 `LUT as Distributed RAM 4044` 里最大的单一消费者，**不是 BRAM tile**。当前位流的 Block RAM Tile 是
95.5/140（`build/utilization.rpt:106`），而 BRAM 的 86 % 是显示帧缓存那 80 块 RAMB36
（`build/r88_resource_owners.txt:71`）。把这两件事混着念，就会得出"削打包 FIFO 能腾 BRAM"这种错结论——
真实收益点是那 ~400 个 LUT，而那正是 `#140` 用一次台架补探针量出来"换不到东西"的东西
（判读见 `优化流水账`，同一件的两份读数是
`build/r88_packer_peak_gap0.txt` 与 `build/r88_packer_peak_throttled.txt`）。

顺带一句为什么它会填到顶：这一档流量形状下读侧 `sv_full` 的阻塞窗口没有被建模，所以 512/512 是**下界**
而不是设计界（这句话写在探针自己的输出注释里，`build/r88_packer_peak_gap0.txt:22-24`）。一个"下界"就足以
否决"降深度"，因为否决只需要一个 ≥ 半深的读数；但它**不足以**支持任何"还能再加"的结论。

---

## 6 整体架构：链子在整机里的位置与上下游契约

```
video_timing_1024x600 ── x/y/de/hs/vs ─┬──────────────────────────────────────────────┐
                                      │                                              │
 DDR 提交帧 ─ axi_frame_writer_gated ─► 帧缓存 ─ fb_bilin(逆映射 + 双线性) ─ pix_raw   │
                    ▲                      ▲                                        │
                    │                      │                                        │
             cy_r = (y+OFF+2)>>1 ─── u_zmap ┘                                        │
                    │                                                                │
                    ├── 原图抽头 ─► raw_line_delay(4 行) ─► orig_skid(15) ─┐          │
                    │                                                    ├─► split_display（逐像素二选一）
                    └── pix_raw ─► proc_pipeline(15 拍) ─► pipe_dout_q ──┘          │
                                                            │                       │
                                                            └──► osd_overlay ──► rgb2dvi / 面板
控制面： PS Xil_Out32 ─► axi_gpio_2 ─► effect_ctrl(2 级 ASYNC_REG) ─► stage_sel / threshold / gamma
                          └► snap_cross(19 位几何字) ─► split_ctrl / seam_src / angle_ctrl / zoom_ctrl
```

（每一段都在 `src/rtl/top/pl_video_top.v` 里：时序 `:226-230`，`cy_r` `:276-284`，`u_zmap` `:343-349`，
`pix_raw` `:772`，行环 `:781-792`，链子 `:800-810`，skid `:831-849`，混色 `:911-928`，OSD `:999-1024`。）

### 6.1 链子对上游的三条要求

1. **每一拍的 `x_in` 必须是"本拍像素在链子那一条流里的列号"**，起点不必是 0（3.3 的 `run` 计数因此不用 `>=`）；
2. **`y_in` 必须是源行**，同一源行的两个显示行给出同一个 `y`——四根旗标里的 `row_first` 靠这一点区分
   "真缺上邻"与"只是这一源行的第二行"（`src/rtl/process/proc_box_blur.v:64-65`）；
3. **读行坐标要带链子的滞后量**，而且提前量必须加在 mapper 的**显示行**输入上而不是输出的源行上
   （`src/rtl/top/pl_video_top.v:246-248`：链子的滞后发生在显示栅格上，缩放/旋转之后"源行差 4" ≠ "显示行差 4"）。

### 6.2 链子对下游给的三条承诺

1. `de_out` 与 `dout` 同拍，`de_in → de_out` 恒为 `LATENCY`（顶层据此取 skid 长度）；
2. 输出内容相对喂进来的坐标滞后 `off_rows` 行、0 列，且这个偏移与开了哪一级无关；
3. 关掉某一级时**逐位等于中心抽头**，不是等于 `din`——四个窗口级共用同一个中心抽头约定，
   这条是 `tb_v84`/`tb_v89_align` 能差分验证的前提（`src/rtl/process/proc_sobel.v:23-26`、
   `src/rtl/process/proc_morph.v:140-142`）。

### 6.3 判据地图：哪一件事被哪一支尺子钉住

| 主张 | 尺子 | 改前会红的判据 |
|---|---|---|
| 整链固定 15 拍、与 sel 无关 | `sim/tb_v86_pipe_sel.v` | T2 实测 `de_in→de_out` == `LATENCY`（`:164`）、T3 `LATENCY == 15`（`:167`） |
| 腐蚀\|膨胀同时 1 ⇒ 旁路 | 同上 | T14 与全旁路帧逐位相同（`:234`） |
| 九位逐位直连、无第二口径 | 同上 | T12 `cfg=0x008 ⇒ sel_q=0x008`（`:214`）、T13 同 cfg 两帧逐位一致（`:224`） |
| gamma 关掉必须一动不动 | `sim/tb_v88_gamma.v` | 文件头第 1 条判据（`src/rtl/process/proc_pipeline.v:33` 指它） |
| 槽位完整、无越界写 | `sim/tb_v103_pipe_bypass.v` | C10d / C10f（`:214-220`） |
| 四条边缘带（左/右/上/陈旧） | `sim/tb_edge_rim.v` | D1/D1w/D2/D2w/D3，逐 stage 52/52 行（一轮实测读数在 `build/tb_edge_rim_r118.txt:7-20`） |
| 缝两侧同级、抽头同深 | `sim/tb_v98_top_seam.v` | C1c / C2 / C3 |
| 开关某一级画面不跳一行 | `sim/tb_v92_seam_bleed.v`、`tb_v84_morph.v` | C2/C3 差分 |
| 灰度公式 | `sim/tb_proc_gray.v` | 逐像素 |

`build/tb_edge_rim_r118.txt` 头 5 行带 `top_md5 / rtl_md5 / date`，这一族件的作用是把"判据与哪一版 RTL 同跑"
钉死（门禁第 15 项缺同跑凭据就判 `n/a`，那条规矩的来历写在 `优化流水账`，
读数是 `build/r88_gates_partial.txt`）。

### 6.4 五处"注释与代码口径不同"的清单（读源码时按代码读）

以下四处是打开文件逐条核过的**文字**不一致，不是行为不一致；列出来是为了不让人按注释推设计：

1. `src/rtl/process/proc_sharpen.v:5` 写"固定 2 拍"，实际三级寄存器（`:124-126`）、`proc_pipeline` 记 3 拍；
2. `src/rtl/video/split_ctrl.v:3` 写"本模块目前没有被任何顶层例化"，实际例化在
   `src/rtl/top/pl_video_top.v:885-891`（且第 09 章整章以它为前提）；
3. `src/rtl/top/pl_video_top.v:1014` 的行尾注释写"屏幕上真的这一路：CARD / PS / ETH"，
   而屏上三个词是 `ETH / SD / TEST`（`src/rtl/video/osd_overlay.v:238-251`，改名理由就写在同一处）；
4. `src/rtl/process/proc_morph.v:7` 写"两条掩码行缓存 = 512 bit × 2"，而顶层传的是 `2*IMG_W = 1024`
   （`src/rtl/top/pl_video_top.v:800`），所以实际是 1024 bit × 2——同一文件的 `H_ACTIVE` 默认值 512
   与实测归属表里 416 只 RAMD64E 也印证的是 1024 深那一档；
5. `src/rtl/process/proc_box_blur.v:5` 与 `proc_sobel.v:2` 的文件头只说"占 3 拍 / 3×3 窗口"，没给 `H_ACTIVE`
   的语义，而 `H_ACTIVE` 的语义（1024 个有效拍、半径 = 半个源像素）写在 `proc_pipeline.v:9-15`。

---

## 7 自查：能答出这几条就算读完

1. 为什么 `LATENCY` 必须由 `proc_pipeline` 自己声明、顶层只许 `u_pipe.LATENCY` 取用？如果某一级从
   组合读出改成寄存读出，要同时改哪几处才不至于把缝错开？
2. 为什么旁路也必须走那一拍寄存器？如果把它改成 `assign dout = bypass ? din : avg`，15 拍账、`OFF_LINES`、
   `tb_v84` 的三条判据分别会发生什么？
3. `run == H_ACTIVE` 为什么不能用 `x_in == H_ACTIVE-1` 代替？给出"顶层一次都没武装"那个失败的具体形状。
4. 为什么最外圈必须用 clamp-to-edge 而不是"发原图"？分别对模糊、Sobel、腐蚀、膨胀说一遍症状。
5. `stale_row` 与 `no_above` 的差别是什么？为什么前者必须同时换中心抽头与旁路值？
6. 一位控制字从 `Xil_Out32` 到 `bypass` 经过几只触发器？为什么缩放档与手动旗标必须和它同一条链？
7. `LUT as Distributed RAM = 4044` 怎么从基元计数复算出来？链子占其中多少、怎么算的？
8. `fo=548` 那四根网是什么？为什么"复制驱动"三次量过三次没采纳？把"机制动了"与"收益成立"分开说。
9. 打包器 512/512 是哪个量纲上的 512/512？为什么说它是**下界**却仍然足以否决降深度？
10. `clkout0_1` 的 WHS 纪录为什么挂在一条 0 级逻辑的移位链上？RTL 能改的东西与不能改的东西分别是什么？

答案的出处都在本章各节；第 4、5 条的凭据是 `build/tb_edge_rim_r118.txt` 那一批 `52/52`、`60/60` 读数，
第 7 条的凭据是 `build/r88_resource_owners.txt:44-46` 与 `build/utilization.rpt:38` 的相加闭合，
第 8 条的凭据是三份 DECLINE/RED 的件本身。
