# A3 帧缓存与 DDR 的数据组织（Zynq-7020 视频工程架构拆解 · 第三卷）

> 卷别：A3　主题：帧缓存（frame buffer）与 DDR 的数据组织、提交通路、显示侧写入、读侧带宽与历史冲突
> 姊妹卷：A1《整体架构与时序域划分》(`ARCH/A1-architecture-and-clocking.md`)、A2《入口数据通路》(`ARCH/A2-ingress-datapath.md`)
> 本卷不重复 A1/A2 的内容，只引用其结论并给出本卷自己的行号证据。

## 目录

1. [范围、读法与证据约定](#1-范围读法与证据约定)
2. [帧格式与内存布局](#2-帧格式与内存布局)
3. [提交（publish）通路](#3-提交publish通路)
4. [显示侧写入：`axi_frame_writer_gated.v`](#4-显示侧写入axi_frame_writer_gatedv)
5. [读侧与带宽](#5-读侧与带宽)
6. [冲突史与解法](#6-冲突史与解法)
7. [完整性防护与失败模式清单](#7-完整性防护与失败模式清单)
   （含 abort/撕裂标志、半帧丢弃、判据兜底情况）
8. [一张表：本层信号台账](#8-一张表本层信号台账)

---

## 1. 范围、读法与证据约定

### 1.1 本卷覆盖的范围

A3 只回答一个问题：**一帧像素在从"网口/SD 卡到齐"到"点亮某个面板像素"之间，究竟躺在哪里、被谁写、被谁读、什么时候允许被读。**
具体拆成五块（对应本卷 §2–§6）：内存布局与 bank 划分、PS→PL 的提交通路、显示帧缓存的写入机器、DDR 读侧的带宽账、以及这两个片源抢同一块内存的历史事故与解法。

划界（不重复姊妹卷）：

- A1 §1 已经给出三棵顶层的包含关系（`system_top` → `u_eth` / `u_pl` 平级兄弟，来源：`ARCH/A1-architecture-and-clocking.md:13-25`）和跨层端口的时钟域表；本卷直接沿用"`clk_pix` 单域 / `clk_fpga_0` 100 MHz"这两个名字，不再推导。
- A2 的目录把入流侧收进 §1–§5：RGMII 物理层、协议栈、UDP 载荷→像素、`frame_reasm.v` 行环、AXI 写侧 `awlen/awsize/awburst/wlast`（来源：`ARCH/A2-ingress-datapath.md:7-14`）。也就是说 **A2 结束在"DDR 已经被写完"那一刻**，A3 从"写完之后谁负责把它搬上屏"开始接。两卷唯一的接口是行环→DDR 的落点地址与 bank 概念，本卷只在 §2、§6 复述地址数值，不复述写通道时序。

显示侧的总策略在本工程里是被写进文件头的，两处互相印证：
`pl_video_top.v:2-3` 说链路是 "`axi_frame_writer_gated/64` 把 DDR 里刚提交的一帧搬进显示帧缓存"（来源：`src/rtl/top/pl_video_top.v:2-3`），
`pl_video_top.v:6` 给硬约束 "`Display BRAM written ONLY by `axi_frame_writer_gated` during blanking (`~de`)"（来源：`src/rtl/top/pl_video_top.v:6`）。

### 1.2 读法与证据口径

1. 每个数字后面都跟 `（来源：文件:行号）`；文件路径以 `D:\Xilinx\Prj\Video_Processing\` 为根（该目录是可读副本，不是 git 工作树）。
2. 只引用"我这一轮真的打开过、且该行非空"的行号。行号以 `src/`、`sim/` 下那份为准；工程里另有一份 `final_submission/` 影子副本（例如 `final_submission/src/rtl/axi/axi_frame_writer_gated.v`），本卷不引用影子副本，两份是否逐字相同列为 `未证`。
3. 反引号里的原话按文件自身的拼写与大小写抄，允许 ±6 行容差；超出容差的改写一律不加引号。
4. 凡是我从注释、文档或命名推断而没有代码直证的，写在 §7 并标 `未证`，不混进正文的数字里。
5. 已存在的二手材料（`ARCH/A1`–`A7`、`LEARNING/01`–`04`、`study_docs/main_report_study/`）在本卷里**只当索引不当证据**：正文引用一律落到 `src/` 下的原始文件；二手文档自己的行号只在需要指出"文档与代码不一致"时出现。

### 1.3 本卷涉及的目录

| 目录 | 在本卷里的角色 |
|---|---|
| `src/rtl/axi/` | 显示侧 DDR→BRAM 的两台搬运机器（`axi_frame_writer_gated.v`、`axi_frame_writer64.v`） |
| `src/rtl/eth/` | DDR 的另一端：入包写入、乒乓 bank 提交（`eth_udp_video_top.v`、`ddr_bank_commit.v`、`frame_commit_lock.v`） |
| `src/rtl/util/` | 提交握手的独立模块 `ps_publish.v`，以及 `shown_rate.v`、`src_life.v` 这两个以发布事件为饲料的计量器 |
| `src/rtl/top/` | 参数与地址的下传（`system_top.v`、`pl_video_top.v`） |
| `src/ps/` | 位表、`FRAME_ADDR`、`ps_publish()` 的 C 侧实现（`main.c`、`sd_play.c/.h`） |
| `sim/` | 逐相位台架：`tb_ps_publish.v`、`tb_writer_abort.v`、`tb_fb_pingpong.v`、`tb_fb_vblank_copy.v` |
| `data/measured/`、`board/compare/` | 板级与台架的实测台账（§6 引用其文件名与条目，见 §7 的缺口声明） |

---

## 2. 帧格式与内存布局

### 2.1 一帧的字节数

片源几何在整个工程里只有一对数字：**512 × 300、每像素 2 字节（RGB565）**。

- C 侧：`#define FRAME_W     512`、`#define FRAME_H     300`（来源：`src/ps/main.c:38-39`），`#define FRAME_BYTES (FRAME_W * FRAME_H * 2)`（来源：`src/ps/main.c:40`）。
- 回放模块里**独立再定义一次**：`#define FRAME_BYTES    (512u * 300u * 2u)`，同行注释直接写了换算结果 "`RGB565 = 307200 B = 600 扇区`"（来源：`src/ps/sd_play.c:34`）。两处重复不是疏忽，是被要求的——`sd_play.c:33` 的文件级注释写着 "`与 RTL 必须一致的数：改这里要同时改 pl_video_top.v 的 BASE_ADDR / IMG_W / IMG_H`"（来源：`src/ps/sd_play.c:33`）。
- RTL 侧同一对数字：`parameter IMG_W = 512`、`parameter IMG_H = 300`（来源：`src/rtl/axi/axi_frame_writer_gated.v:9-10`），顶层 `parameter IMG_W = 512` / `IMG_H = 300` / `PANE_W = 512`（来源：`src/rtl/top/pl_video_top.v:9-11`）。

算式与结果（操作数全部来自上面两处，没有新增测量）：
`512 × 300 = 153600 像素`，`× 2 B/px = 307200 B = 300 KiB = 0x4_B000`，
`307200 / 512 = 600` 个 SD 扇区（与 `sd_play.c:34` 的注释一致）。
卡上一个满块文件是 "`512 × 307200 B = 157286400 B = 150.0 MiB`"（来源：`src/ps/sd_play.c:9`；
同一行现在还写着"末块按余数（本卡 VIDEO008=302，共 4398）"。这一格旧版抄的是"153.6 MiB"——那是把 1 MB 当成 1024×1000 B 得到的，
固件注释与本文都在 `eb5933b`（2026-10-07 20:0x）改对，两边那个不等式记在 A7 卷"每段体积"那一行）。

`PANE_W` 与 `IMG_W` 同值但语义不同，`system_top.v:138` 的注释说得很直白："`右半窗宽（当前与 VIDEO_W 同值，语义不同）`"（来源：`src/rtl/top/system_top.v:138`）。512×300 到面板 1024×600 的放大属于输出几何那卷，本卷不管。

### 2.2 DDR 起始地址与三份定义

`BASE_ADDR` 的默认值在三处出现，值相同：

| 位置 | 写法 | 引用 |
|---|---|---|
| 搬运机器自己的参数 | `parameter BASE_ADDR = 32'h1000_0000` | `src/rtl/axi/axi_frame_writer_gated.v:11` |
| 显示顶层参数 | `parameter BASE_ADDR = 32'h1000_0000` | `src/rtl/top/pl_video_top.v:12` |
| 系统顶层唯一的 `localparam` | `localparam [31:0] DDR_BASE   = 32'h1000_0000` | `src/rtl/top/system_top.v:139` |

这一份 `localparam` 是 V7.9.6 收口的结果：`system_top.v:135` 记录了动机——"原来 512/300/0x1000_0000 在下面两个例化上各写一遍字面量 …… 没有任何东西阻止两边不一致"（来源：`src/rtl/top/system_top.v:135`），后果不是编译错而是"写进去的帧几何与读出来的显示几何对不上"（同上行）。下传口只有一处：`eth_udp_video_top #(.IMG_W(VIDEO_W), .IMG_H(VIDEO_H), .BASE_ADDR(DDR_BASE))`（来源：`src/rtl/top/system_top.v:154-156`）。

注意 `axi_frame_writer_gated` 的参数 `BASE_ADDR` **只当复位值用**（`base_r<=BASE_ADDR`，来源：`src/rtl/axi/axi_frame_writer_gated.v:106`），真正的基址走端口 `base_addr`（同文件 `:131` 的 `m_axi_araddr<=base_addr`）。也就是说参数与端口可以不一致——这条列为已知隐患，见 §7。

### 2.3 三块 bank：ETH 乒乓 + PS 专用

ETH 在 `BASE_ADDR` 上做乒乓，两个 bank 的定义在入流顶层：

```
localparam [31:0] BANK0 = BASE_ADDR;                      // 0x1000_0000
localparam [31:0] BANK1 = BASE_ADDR + 32'h0008_0000;      // 0x1008_0000
```
（来源：`src/rtl/eth/eth_udp_video_top.v:67-68`）

PS 片源（SD 回放、`fill` 诊断帧）落在**第三个 bank**：`localparam [31:0] PS_DDR_BASE = 32'h1010_0000`（来源：`src/rtl/top/system_top.v:144`），C 侧两处各有一份：`#define FRAME_ADDR  0x10100000u`（来源：`src/ps/main.c:46`）与 `#define FRAME_ADDR     0x10100000u`（来源：`src/ps/sd_play.c:35`）。`main.c` 文件头把这张地图写成一句话： "`DDR frame @ 0x10100000（FILL 诊断帧 / SD 回放帧都落在这里；ETH 用 0x10000000/0x10080000）`"（来源：`src/ps/main.c:19`）。

按 §2.1 的帧长展开，三块的边界互不相交（间距取自 `32'h0008_0000` 与 `0x1010_0000`，帧长取自 `sd_play.c:34`）：

| bank | 起始 | 结束（起 + 307200 B） | 归属 |
|---|---|---|---|
| ETH bank0 | `0x1000_0000` | `0x1004_B000` | `eth_udp_video_top.v:67` |
| ETH bank1 | `0x1008_0000` | `0x100C_B000` | `eth_udp_video_top.v:68` |
| PS bank | `0x1010_0000` | `0x1014_B000` | `system_top.v:144` |

每个 bank 后面还剩 `0x0008_0000 − 0x0004_B000 = 0x3_5000 = 217088 B` 的空档（操作数：`eth_udp_video_top.v:68` 的间距与 `sd_play.c:34` 的帧长）。`system_top.v:141` 对这个间距的说法是 "`每帧 300 KB，间隔 512 KB 够用`"（来源：`src/rtl/top/system_top.v:141`）——**留余量的用途文件里没写**，推断见 §7。

### 2.4 搬运机眼里的同一帧

同一块内存，`axi_frame_writer_gated` 是按 64 bit（= 4 个 RGB565 像素）一拍来数的：

```
localparam integer PIX_PER_BEAT = 4;
localparam integer BEATS        = 16;
localparam integer TOTAL_PIX    = IMG_W * IMG_H;              // 153600
localparam integer TOTAL_WORDS  = (TOTAL_PIX + 3) / 4;        // 38400
localparam integer TOTAL_BURSTS = (TOTAL_WORDS + 15) / 16;    // 2400
```
（来源：`src/rtl/axi/axi_frame_writer_gated.v:40-44`，注释形式做了算术代入）

于是一帧 = 38400 个 64 bit 字 = 2400 个 `arlen=15` 的 INCR burst（`m_axi_arlen <= BEATS[7:0]-8'd1`，来源：`src/rtl/axi/axi_frame_writer_gated.v:132`；`m_axi_arburst = 2'b01` 即 INCR，来源：同文件 `:38`）。

---

## 3. 提交（publish）通路

### 3.1 一个位的完整生命周期

提交这件事在硬件上只有**一个位**：AXI GPIO `gpio_o` 的第 18 位。位表写在固件文件头：

```
[18]    ps_publish —— 翻转一次 = "DDR 里这一帧写完了，请在下一个 frame_start 搬走"
```
（来源：`src/ps/main.c:9`），宏是 `#define PUBLISH_BIT   18u`（来源：`src/ps/main.c:51`）。
整字在 `ctrl_write()`（来源：`src/ps/main.c:208`）里拼出来，那一项是 `| (pub_lvl << PUBLISH_BIT)`（来源：`src/ps/main.c:215`），一次 `Xil_Out32(GPIO_DATA, v)` 落盘（来源：`src/ps/main.c:219`）。
顶层把它接到 PL：`.ps_publish(gpio_o[18])`，同行注释 "`每翻转一次 = PS 请求把 DDR 里那一帧搬上屏一次`"（来源：`src/rtl/top/system_top.v:288`）。

PS 侧唯一的调用点：

```
void ps_publish(void)
{
    pub_lvl ^= 1u;
    (void)ctrl_write();
    ps_hold = 1u;
    XTime_GetTime(&ps_ka_t);
}
```
（来源：`src/ps/main.c:242-251`，中间三段注释已省略）

这里有一条工程上的教训值得单独记：`ps_publish()` **不调 `ctrl_apply()` 而调 `ctrl_write()`**，因为 `ctrl_apply()` 会打两行 `[CTRL]`。`main.c:205-207` 给了量化的理由："`原来 ps_publish() 直接调 ctrl_apply()，于是 30 fps 的回放每秒往串口推约 2 KB（115200 只有 11.5 KB/s ……），板上实测 PLAY 10 s 收回 28549 B 全是 [CTRL] 行`"（来源：`src/ps/main.c:205-207`）——刷屏之外还把发布时序压在打印上（同上行）。

### 3.2 PL 侧的握手：`ps_publish.v`

跨域握手被刻意拆成独立模块，动机写在文件头："`塞在 pl_video_top 里就只能靠"上板看有没有撕裂"来验；单独拿出来才能用台架把相位扫一遍、把"一次发布 = 一次消费"钉死`"（来源：`src/rtl/util/ps_publish.v:4-5`）。

| 信号 | 方向 | 含义（原文） | 引用 |
|---|---|---|---|
| `clk` | in | "`消费侧时钟（clk_pix）`" | `src/rtl/util/ps_publish.v:10` |
| `tog` | in | "`来自其它时钟域的翻转位`" | 同文件 `:12` |
| `consume` | in | "`本拍愿意接收一次`" | 同文件 `:13` |
| `pend` | out | "`有未消费的发布请求`" | 同文件 `:14` |
| `new_tog` | out | "`本拍检测到新翻转`"，注释还说明 `edge` 是保留字不能当端口名 | 同文件 `:15` |

三级同步：`(* ASYNC_REG = "TRUE" *) reg m0, m1, m2`（来源：`src/rtl/util/ps_publish.v:18`），链子是 `{m2, m1, m0} <= {m1, m0, tog}`（来源：同文件 `:22`）。沿检测用打后的两级异或：`assign new_tog = m1 ^ m2`（来源：同文件 `:25`）。`:17` 解释了为什么是三级而不是两级："`前两级打异步，第三级专门给"异拍出沿"用，保证 new_tog 两拍内稳定可被 consume 采样`"（来源：同文件 `:17`）。
`pend` 的置/清顺序也是刻意的："`new_tog 优先于 consume ⇒ "这拍刚到又这拍消费"时请求不会被吃掉`"（来源：`src/rtl/util/ps_publish.v:28`），代码即 `if (new_tog) pend <= 1'b1; else if (consume) pend <= 1'b0;`（来源：同文件 `:30-31`）。

### 3.3 消费条件与 `owner_eth_pix`

顶层的接收条件只有一行：

```
wire pub_consume = frame_start && src_use && !owner_eth_pix;
```
（来源：`src/rtl/top/pl_video_top.v:559`）

`owner_eth_pix` 是"当前片源是不是网口"的像素域名字，声明在 `src/rtl/top/pl_video_top.v:142`（注释 "`前面声明、下面赋值：u_mode 要拿它挑 AUTO 的下一态`"，同文件 `:142`），赋值是 `assign owner_eth_pix = op2;`（来源：`src/rtl/top/pl_video_top.v:522`）。为什么 `pub_consume` 必须带 `!owner_eth_pix`：网口在放的时候，DDR→帧缓存那台搬运机归 ETH 的提交链路用，PS 的发布位不该抢。`:557-558` 还记了一次真错的修法："这里原来用 `src_sel`（axi_clk 域的未同步电平）…… 帧起始那拍采它会采到亚稳态"（来源：`src/rtl/top/pl_video_top.v:557-558`）。

例化与消费后果：

```
ps_publish u_pub (.clk(clk_pix), .rst_n(rst_pix_n),
    .tog(ps_publish), .consume(pub_consume), .pend(pub_pend), .new_tog(pub_new));
```
（来源：`src/rtl/top/pl_video_top.v:564-566`）
`pub_new` 同时是 #94 心跳的"活判据"来源："`心跳吃 ps_publish 的 new_tog ⇒ 零新增异步配对`"（来源：`src/rtl/util/src_life.v:55`，端口定义 `src/rtl/util/src_life.v:20` 写作 "`脉冲：PS 刚提交了一帧（= ps_publish 的 new_tog）`"）。
消费成功后翻一个帧拍翻转位：`else if (pub_consume && pub_pend) fs_tog <= ~fs_tog;`（来源：`src/rtl/top/pl_video_top.v:571`），`fs_tog` 声明在 `:568`。
同一对信号还被帧率计量器直接复用：`wire new_shown = frame_start && (owner_eth_pix ? eth_pend : (fb_vis ? (pub_consume && pub_pend) : 1'b1));`（来源：`src/rtl/util/shown_rate.v:42`，端口注释 `:31` 写作 "`这一场取走了 PS 发布的内容`"）。

### 3.4 为什么是"复制一次"而不是"每帧都复制"

协议原文在回放模块的文件头："`PS 把一帧 DMA 进 DDR → 翻转 GPIO bit18 → PL 在下一个 frame_start 复制一次`"（来源：`src/ps/sd_play.c:16`），紧接着是理由：

> "`"复制一次"而不是"每帧都复制"是关键：前者让 PS 有整个帧周期可以安全覆写 DDR；后者会在 PS 写到一半时把半张新图 + 半张旧图搬上屏（撕裂）。`"
> （来源：`src/ps/sd_play.c:17-18`）

换句话说：如果搬运机每个 `frame_start` 都无条件重读 DDR，那么 PS 的 SD DMA（走 PS 自己的 HP0，不经过 PL，见 `src/rtl/top/pl_video_top.v:14`）正写到一半的那一行就会被当成有效像素搬上屏；把"搬"绑在**发布沿**上之后，PL 只在 PS 明确说"这帧我写完了"之后的那一个帧周期搬一次，其余帧周期里 DDR 那块内存归 PS 独占。
握手语义是**电平而不是计数**，这一点 `ps_publish.v:6-8` 自己交代了代价与边界："`连着发两次、PL 只消费一次 ⇒ 第二次被合并 …… 本项目里 SD 读一帧 30~60 ms >> 16.8 ms，真要合并也只是"少刷一帧"，不会撕裂；换成计数器就要多一套溢出/复位约定，收益为零`"（来源：`src/rtl/util/ps_publish.v:6-8`）。

---

## 4. 显示侧写入：`axi_frame_writer_gated.v`

### 4.1 先把名字纠正过来：它没有 AXI 写通道

`axi_frame_writer_gated` 这个名字里的 "writer" **不是 AXI 写通道（AW/W/B）的 master**，而是"显示帧缓存 BRAM 的写者"。端口表就是判据：

- AXI 侧只有读地址通道：`m_axi_araddr/arlen/arsize/arburst/arvalid/arready`（来源：`src/rtl/axi/axi_frame_writer_gated.v:25-30`）和读数据通道 `m_axi_rdata/rlast/rvalid/rready`（来源：同文件 `:31-34`）。
- 全文（191 行）没有一个 `aw*` / `w*` / `b*` 端口；`m_axi_arsize = 3'b011`（8 字节）、`m_axi_arburst = 2'b01`（INCR）（来源：同文件 `:37-38`）。
- 真正的写入是三只**本地**口：`fb_wr_en`、`fb_wr_addr[18:0]`、`fb_wr_data[63:0]`（来源：同文件 `:22-24`），它们直连显示帧缓存，不经过任何互联。

所以这台机器的准确描述是："**AR/R 读 DDR，本地端口写 BRAM**"。文件头自己也是这么写的："`从 HP0 把 DDR 里刚提交的一帧拉回来，只在 allow（消隐、链子排空之后）那几拍落 BRAM`"（来源：`src/rtl/axi/axi_frame_writer_gated.v:2-3`）。DDR 的**写入**方在另外两处：入流侧的 `src/rtl/eth/axi_frame_saver64.v` / `axi_frame_saver_burst.v`（A2 §5 的范围）和 PS 自己的 SD DMA（走 HP0，不经过 PL，来源：`src/rtl/top/pl_video_top.v:14`）。

### 4.2 "只在消隐期写"是怎么保证的

顶层的硬约束写在 `pl_video_top.v:6`："`Display BRAM written ONLY by axi_frame_writer_gated during blanking (~de)`"（来源：`src/rtl/top/pl_video_top.v:6`）。窗口本身由三行常量算出来：

| 量 | 值 | 含义 | 引用 |
|---|---|---|---|
| `DISP_V_LINES` | `12'd600` | "`active lines of 1024x600`" | `src/rtl/top/pl_video_top.v:397` |
| `DISP_V_LAST` | `12'd624` | "`V_TOTAL-1`" | 同文件 `:398` |
| `VB_X_GUARD` | `12'd1279` | "`H_TOTAL(1344)-65：早关 64 个消隐像点`" | 同文件 `:399` |

```
wire disp_quiet = (y >= DISP_V_LINES) && ((y < DISP_V_LAST) || (x <= VB_X_GUARD));
```
（来源：`src/rtl/top/pl_video_top.v:400-401`）

`:399` 解释了那 64 点余量的用途："`allow_copy_axi 过 frame_commit_lock 的 CDC 要晚这个窗口约 5 个像素拍`"（来源：同文件 `:399`）。
`disp_quiet` 进 `frame_commit_lock` 的 `.blank_safe()`（来源：`src/rtl/top/pl_video_top.v:434`），出来的 `allow_copy` 再进搬运机的 `.allow_wr()`（来源：同文件 `:459`）。

`allow_wr` 在机器内部被用在**三个**地方，语义各不相同：

1. 发请求：`can_issue = active && allow_wr && !m_axi_arvalid && !abort && !dropping && (outstanding < MAX_OUT) && (burst_idx < TOTAL_BURSTS) && (sk_level <= ((1<<SK)-1-BEATS))`（来源：`src/rtl/axi/axi_frame_writer_gated.v:81-84`）——窗口一关，连 AR 都不再发。
2. 直通落 BRAM：`do_direct = r_hit && allow_wr && sk_empty && !dropping`（来源：同文件 `:87`），这是"R 当拍就写"的快速路径，文件头给它的评价是 "`copy finishes inside one display frame → no motion ghosting`"（来源：同文件 `:5-6`）。
3. 排空 skid：`sk_drain = active && allow_wr && !sk_empty && !do_direct && !dropping`（来源：同文件 `:89`），写口在 `:157-161` 打开。

`:45-46` 的注释还给出在途深度的设计目标："`4 x 16-beat bursts in flight ≈ 64 beats, enough outstanding to cover HP0/DDR read latency and hold ~1 beat/cycle through the 25-line window`"（来源：同文件 `:45-46`，`MAX_OUT = 3'd4` 在 `:47`）。

### 4.3 skid 缓冲：一次综合教训的形状

`SK = 6`（64 项）的两只分布式 RAM `sk_addr` / `sk_data` 各自挂了 `(* ram_style = "distributed" *)`（来源：`src/rtl/axi/axi_frame_writer_gated.v:48-54`）。原因是 `:50-52` 记的那条："`原先写和指针同在带异步复位的控制块里，综合报 Synth 8-4767「Block RAM or DRAM implementation is not possible」，64×83bit 全掉进触发器（约占整机剩余寄存器的一半）`"（来源：同文件 `:50-52`）。
于是数组写被单独拆进一个**不带复位**的 `always` 块（来源：`src/rtl/axi/axi_frame_writer_gated.v:94-99`），`:91-93` 说明合并成单写脉冲的依据。因为是分布式 RAM，读口才退回异步：`sk_addr_q = sk_addr[sk_rid]`（来源：同文件 `:63`），`:60-61` 承认"同一地址被读写时读出旧值"与旧语义一致。

### 4.4 起、停与完成

- 起：`(enable && start) || start_hold` 时 `active<=1`、`base_r<=base_addr`、并把第一个 burst 的地址直接摆出去 `m_axi_araddr<=base_addr`（来源：`src/rtl/axi/axi_frame_writer_gated.v:125-136`）。顶层只让它在网口模式下跑：`.enable(eth_mode)`、`.start(eth_mode ? row_start : 1'b0)`、`.abort(eth_mode ? copy_abort : 1'b0)`（来源：`src/rtl/top/pl_video_top.v:456-460`）。
- 后续 burst 的地址是 `base_r + burst_idx * (BEATS * 8)`（来源：`src/rtl/axi/axi_frame_writer_gated.v:149`）——即每 burst 前进 16×8 = 128 字节，与 §2.4 的 2400 burst 对得上。
- 完成：`wr_words >= TOTAL_WORDS && sk_empty && !m_axi_arvalid && outstanding==0 && !sk_drain && !fb_wr_en` 才 `active<=0; done<=1;` 并锁存 `copy_cycles<=cyc`（来源：同文件 `:182-186`）。`wr_words` 是**真正落进 BRAM 的字数**（`if (fb_wr_en) wr_words <= wr_words + 1`，来源：同文件 `:113`），不是收了多少拍——这保证"半途 abort 的帧"绝不会被记成完成。
- 越界判据：顶层用 `copy_cycles` 和 `VBLANK_AXI_CYC = 32'd67200` 比，超出就把 `copy_overrun` 粘住（来源：`src/rtl/top/pl_video_top.v:446-451`）；`:442-444` 说清了这件事的物理意义："`换帧跨了两个消隐期 ⇒ 屏幕上同一帧的新旧两半并存 ⇒ 运动物体被一条水平缝「切开」+ 拖影 …… 用 led[0] 看`"（来源：同文件 `:442-444`）。窗口预算的算法（25 行 × 1344 像素 × 2 axi 拍）与 `67200` 这个数同源（来源：同文件 `:442`）。

---

## 5. 读侧与带宽

### 5.1 HP0 上其实挂着两台机器，二选一

显示侧从 DDR 拉帧的机器有**两台**，按片源二选一，共用同一个 HP0 读口和同一组 BRAM 写口：

| 例化 | 模块 | 基址参数 | 服务于 | 引用 |
|---|---|---|---|---|
| `u_row` | `axi_frame_writer_gated` | `.BASE_ADDR(BASE_ADDR)` = `0x1000_0000` | 网口片源（`eth_mode`） | `src/rtl/top/pl_video_top.v:454` |
| `u_aw` | `axi_frame_writer64` | `.BASE_ADDR(PS_BASE_ADDR)` = `0x1010_0000` | PS/SD 片源 | 同文件 `:692-694` |

三选一的 mux 写在顶层：`assign m_axi_rready = eth_mode ? row_rready : fill_rready;`（来源：`src/rtl/top/pl_video_top.v:714`），写口三根同理 `aw_wr_en = eth_mode ? row_wr_en : fill_wr_en`、`aw_wr_addr = … : fill_wr_addr`、`aw_wr_data = … : fill_wr_data`（来源：同文件 `:716-718`，声明处的位宽 `wire [18:0] row_wr_addr` / `wire [63:0] row_wr_data` 见同文件 `:379-381`）。
文件头把这条链画成一句话："`axi_frame_writer_gated/64` 把 DDR 里刚提交的一帧搬进显示帧缓存 → `fb_bilin` 读口 → `proc_pipeline` 效果链"（来源：`src/rtl/top/pl_video_top.v:3`）——注意 `gated/64` 的写法，一台机器两个名字。

### 5.2 一帧读出的拍数与字节数（算式）

搬运机每帧的操作量由 §2.4 的常数直接推出，操作数出处都已在正文点名：

- 字数：`TOTAL_WORDS = 38400`（来源：`src/rtl/axi/axi_frame_writer_gated.v:43`，代入 `IMG_W*IMG_H = 153600`、`PIX_PER_BEAT = 4`，同文件 `:40-42`）
- 字节数：`38400 拍 × 8 B/拍 = 307200 B`（8 B/拍来自 `arsize = 3'b011` 与 64 bit 数据口，来源：同文件 `:37`、`:31`）
- burst 数：`TOTAL_BURSTS = 2400`（来源：同文件 `:44`，代入 `BEATS = 16`，同文件 `:41`）
- 每次起 burst 的地址步长：`BEATS * 8 = 128 B`（来源：同文件 `:149`）

带宽账（一次完整拷贝落在一个消隐窗口里）：

```
axi_clk = clk_fpga_0 = 100 MHz（来源：ARCH/A1-architecture-and-clocking.md:31）
窗口预算 = VBLANK_AXI_CYC = 67200 axi 拍 = 672 µs（来源：src/rtl/top/pl_video_top.v:446）
需求吞吐 = 307200 B / 672 µs ≈ 457 MB/s
HP0 上限 = 100 MHz × 8 B = 800 MB/s（来源：ARCH/A1-architecture-and-clocking.md:37，64 bit 数据口）
占空比 ≈ 457 / 800 ≈ 57 %
拍数利用率 = 38400 / 67200 ≈ 0.571 beat/cycle
```

`gated.v:45-46` 的注释正是按这个利用率设计的：目标是 "`hold ~1 beat/cycle through the 25-line window`"（来源：`src/rtl/axi/axi_frame_writer_gated.v:46`），而窗口行数是 25 行（同上行）。
"25 行 × 1344 像素 × 2 axi 拍 = 67200" 这条换算写在 `pl_video_top.v:442` 的注释里（来源：`src/rtl/top/pl_video_top.v:442`），其中 1344 = `H_TOTAL`（来源：同文件 `:295` 的 "`1344−1024=320 拍`"）。

平均带宽则是另一个量级：一次拷贝只服务一次提交。ETH 路径每提交一帧搬一次，PS 路径每发布一次搬一次，而 PS 的"我还在这帧"心跳是 `#define PS_HB_MS 100u`（来源：`src/ps/main.c:260`），即最闲的时候也是每 100 ms 补一次发布（来源：同文件 `:267-268`）。显示帧周期 `16.8 ms` 这个数在握手模块里被引用过："`本项目里 SD 读一帧 30~60 ms >> 16.8 ms`"（来源：`src/rtl/util/ps_publish.v:7-8`）——按 `H_TOTAL 1344 × V_TOTAL 625`（来源：`src/rtl/top/pl_video_top.v:398` 的 `DISP_V_LAST = 624` 即 `V_TOTAL-1`）与 50 MHz 像素钟（来源：同文件 `:721` 的 "`每源像素用满它天然的 4 个 50 MHz 拍`"）反算 `1344×625/50 MHz = 16.8 ms`，两处一致。

### 5.3 读口与行环/提交锁的耦合

入流侧的行环（A2 §4）把整帧写进某个 bank，之后只剩一件事需要保证：**在搬运机把那个 bank 读完之前，它不能被下一次提交覆写。** 这件事不在搬运机里做，而是交给 `frame_commit_lock`：

```
frame_commit_lock #(.IMG_H(IMG_H), .DISP_H(600)) u_cmt (
    .commit_req(eth_commit), .commit_base(eth_ddr_base),
    .de(de), .vsync(vs), .blank_safe(disp_quiet),
    .copy_busy(row_busy), .copy_done(row_done),
    .start_copy(row_start), .copy_base(row_base), … );
```
（来源：`src/rtl/top/pl_video_top.v:430-438`）

`copy_busy`/`copy_done` 就是 `u_row` 的 `row_busy`/`row_done`（来源：同文件 `:461`，`:377` 的线声明），`start_copy`/`copy_base` 又反过来喂给 `u_row` 的 `.start()`/`.base_addr()`（来源：同文件 `:457-458`）。这条闭环的不变式写在文件头："`commit base locked until copy completes`"（来源：`src/rtl/top/pl_video_top.v:7`）——即新提交只更新 pending 基址，锁存的 `copy_base` 在一次拷贝 `done` 之前保持不变，搬运机读到的永远是同一个完整 bank。
搬运机侧配合的是"完成"的严格定义：`outstanding==0 && sk_empty && !fb_wr_en` 才 `done<=1`（来源：`src/rtl/axi/axi_frame_writer_gated.v:182-184`），不会出现"还有拍在飞就宣称搬完"。

### 5.4 显示帧缓存的读口

BRAM 的读侧只有一个口，且它本身就是双线性核：`r63 / #52：显示侧读口换成 fb_bilin（双线性，每源像素用满它天然的 4 个 50 MHz 拍）`（来源：`src/rtl/top/pl_video_top.v:721`）。换口时最要紧的账是延迟而不是吞吐："`对外形状与旧的"rd_addr_q + frame_buffer_w64"逐位同深（请求 → 2 拍到数据），所以 MIX_D = 3 + 1 + 1 + LATENCY 的两个 1 原样成立 ⇒ 混色级、skid、SEAM_TAPS 全不动`"（来源：同文件 `:722-723`）。
读口一次取的是**源像素**坐标（512×300 那一侧），而屏上走的是 1024×600 面板时序，所以每个源像素会被消费多次放大——放大与几何属于后续卷，本卷只记"读口按源像素发请求、每源像素占 4 个 50 MHz 拍"这条带宽事实（来源：同文件 `:721`）。

---

## 6. 冲突史与解法

### 6.1 事故本体：两个片源写同一块内存

三份独立注释记录了同一件事。固件侧说得最完整：

```
/* PS 片源的帧落在 DDR 的**第三个 bank**：0x1010_0000。
 * 以前是 0x1000_0000，与 ETH 乒乓双 bank 的第 0 块重叠 ⇒ SD/FILL 一边写、ETH 一边读写同一块内存，
 * 屏幕上就是"两个片源打架、闪"（板级实测 2026-09-24）。仲裁只管谁用 DDR→帧缓存那台搬运机，
 * 管不到谁写 DDR（SD 的 DMA 走 PS 自己的 HP0，不经过 PL），所以只能靠地址分开。
 * 这个数必须等于 `system_top.v` 的 PS_DDR_BASE / `pl_video_top.v` 的 PS_BASE_ADDR。 */
```
（来源：`src/ps/main.c:41-45`）

PL 侧是同一套话的镜像："`PS 片源（SD 回放 / FILL 诊断帧）专用 DDR bank，与 ETH 的乒乓双 bank 错开`"（来源：`src/rtl/top/pl_video_top.v:13`）、"`两路同时跑时重叠只能靠地址分开`"（来源：同文件 `:15`）。
顶层收口时又写了一遍："`ETH 占 0x1000_0000 与 0x1008_0000 乒乓两 bank（每帧 300 KB，间隔 512 KB 够用），所以第三个 bank 从 +1 MB 起`"（来源：`src/rtl/top/system_top.v:140-141`）。

### 6.2 机制：为什么"仲裁"救不了这件事

关键在于**写 DDR 的两个 agent 不在同一条仲裁链上**：

- 入流侧：`u_eth` 的 AXI writer（A2 §5 的 saver）在 PL 里，走 PL→HP0 的互联，写 `BANK0`/`BANK1`（来源：`src/rtl/eth/eth_udp_video_top.v:67-68`）。
- 回放侧：SD 控制器的 DMA 在 **PS 内部**，同样落在 HP0 上，但不经过 PL 的任何逻辑（来源：`src/ps/main.c:44` 与 `src/rtl/top/pl_video_top.v:14`）。

PL 里的 `src_arb` 只决定"谁拥有 DDR→帧缓存那台搬运机"，落到本卷就是 `u_row` 与 `u_aw` 的二选一 mux（来源：`src/rtl/top/pl_video_top.v:714-718`）。搬运机是**读端**，两个写端各写各的，地址一样就必然互相踩。所以修法只能是地址：`localparam [31:0] PS_DDR_BASE = 32'h1010_0000`（来源：`src/rtl/top/system_top.v:144`）+ `#define FRAME_ADDR  0x10100000u`（来源：`src/ps/main.c:46`）+ `#define FRAME_ADDR     0x10100000u`（来源：`src/ps/sd_play.c:35`）+ `parameter PS_BASE_ADDR = 32'h1010_0000`（来源：`src/rtl/top/pl_video_top.v:16`）。

### 6.3 解法之后的账

| 项 | 事故前 | 事故后 | 引用 |
|---|---|---|---|
| ETH bank0 | `0x1000_0000`（被 SD/FILL 共用） | `0x1000_0000`（ETH 独占） | `src/rtl/eth/eth_udp_video_top.v:67` |
| ETH bank1 | `0x1008_0000` | `0x1008_0000`（不变） | 同文件 `:68` |
| PS 片源 | `0x1000_0000` ← 与 bank0 重叠 | `0x1010_0000` | `src/rtl/top/system_top.v:144`、`src/ps/main.c:46` |

同一个数现在**有 4 处定义**（`system_top.v:144`、`pl_video_top.v:16`、`main.c:46`、`sd_play.c:35`），约束完全靠注释与人工同步，`system_top.v:142-143` 也承认这一点并给出症状："改这里不改那边 ⇒ 现象是 `PS 片源在屏上不动`（搬运机读的是另一块内存）"（来源：`src/rtl/top/system_top.v:142-143`）。这条属于"有说法、没有判据"的账，列进 §7.8。

### 6.4 台账与条目号

代码注释里能直接查到的只有日期 "`板级实测 2026-09-24`"（来源：`src/ps/main.c:42`）；与之相邻的另一条收口（V7.9.6 / P0-C ③，来源：`src/rtl/top/system_top.v:134-135`）也是同一时期的改动。本工程另有 ISSUES 台账（搬运机内部就引用了 `#170`，来源：`src/rtl/axi/axi_frame_writer_gated.v:69-70`；提交锁引用 `#171`，来源：`src/rtl/top/pl_video_top.v:526`），但**这三条注释都没有写出"抢 bank"对应的 ISSUES 编号**，故条目号记 `未证`。

---

## 7. 完整性防护与失败模式清单

### 7.1 abort 与排空：一帧"半途而废"必须被吃干净

`#170` 是本层最硬的一条防护。旧行为是 `rready = active && !sk_full`，abort 一落 `rready` 直接掉 0：

> "`AXI 不许 master 撤回已经举起的 `rvalid` ⇒ 那些拍不会消失，它们会**等在下一帧门口**，下一帧收下的头几拍其实是上一帧的数据（整帧平移 + 帧尾越界写；台架 `sim/tb_writer_abort.v` 的 B3/B5/B6 三条红钉的就是这个）。`"
> （来源：`src/rtl/axi/axi_frame_writer_gated.v:75-78`）

现在的做法：`assign m_axi_rready = (active && !sk_full) || dropping;`（来源：同文件 `:79`），排空预算直接拿在途 burst 数当：`drain_left <= outstanding`（来源：同文件 `:144`），排空期间"收 R 拍但一个都不写"（来源：同文件 `:116-121`），每个 `rlast` 减一（来源：同文件 `:121`）。
半帧必须丢的根本原因写在完成条件里：`wr_words` 只统计真正落进 BRAM 的字（来源：`src/rtl/axi/axi_frame_writer_gated.v:113`），abort 时 `wr_words<=0` 一并清掉（来源：同文件 `:146`），于是被撕掉的那一帧永远不可能 `done`——**BRAM 里剩的仍是上一整帧**，而不是新旧两半的拼贴。
排空期间又来一次 start 也不会丢：`if (enable && start) start_hold <= 1'b1;`，注释给了理由——"`免得"这一次 start 被吞掉"变成"屏上一直停在旧帧"（那又是另一条锁死账）`"（来源：同文件 `:118-122`）。

### 7.2 跨域的 abort 只能用翻转位

`copy_abort` 是 `axi_clk` 上只有一拍的脉冲，不能照电平同步器抄："`电平型 3 级同步会整拍漏掉它（比裸采样更糟）⇒ 要的是翻转式脉冲同步器`"（来源：`src/rtl/top/pl_video_top.v:482-483`）。代码就是那三级 + 异或：`{ab2,ab1,ab0} <= {ab1, ab0, abort_tgl}` 与 `wire copy_abort_pix = ab1 ^ ab2;   // 每次 abort 恰好一拍`（来源：同文件 `:487`、`:489`）。
同一课在 PS 侧也复述过一次：长键"`输出是翻转位 tog 而不是脉冲：脉冲跨域会被吃掉（`ps_publish` 与 ISSUES #36 那一课）`"（来源：`src/rtl/util/key_long.v:4`）。

### 7.3 撕裂 / 越界：三道判据

| 判据 | 触发条件 | 兜底动作 | 有没有点名 |
|---|---|---|---|
| `copy_overrun` | `row_done && (row_copy_cycles > VBLANK_AXI_CYC)`，即一次拷贝超过 67200 axi 拍 | 粘滞位，"`用 led[0] 看`"，直到重新加载 bit | 有（来源：`src/rtl/top/pl_video_top.v:446-451`，症状解释 `:442-444`） |
| `frame_ready` 改成一拍脉冲 | 过去是永久电平，"`所以这一支天天为真、下面那一支根本轮不到`" | `eth_has_frame` 的 abort 支排到"刚提交"之前（`#171`） | 有（来源：`src/rtl/top/pl_video_top.v:526-529`） |
| 提交锁 | `commit base locked until copy completes` | 未完成不换 bank | 有（来源：同文件 `:7`，端口闭环 `:430-438`） |

### 7.4 失败模式清单（逐条注明判据）

1. **拔卡冻帧 / 读失败。** 判据：`ps_source_lost()` 停心跳，`"[SRC] PS 停心跳：片源不可信（拔卡 / 读错），画面交回仲裁"`（来源：`src/ps/main.c:273-277`）。**有判据兜着**：PL 侧 `src_life` 用 500 ms 活判据，"`500 ms 没见到发布就当没片源`"（来源：同文件 `:246-247`）。
2. **暂停后画面被抢走。** 判据：`ps_hold = 1u;` + `XTime_GetTime(&ps_ka_t)`（来源：`src/ps/main.c:249-250`），心跳 `PS_HB_MS = 100u`（来源：同文件 `:260`）每 100 ms 重发同一帧（来源：同文件 `:267-268`）。**有判据，而且是双向的**：`:257-258` 明确 "100 ms 与 PL 那侧的 500 ms 是同一件事的两半，比例 1:5 由 `sim/tb_v102_src_life.v` 的 S12 钉住（改这里就要改那里，两边各自成立不等于合起来成立）"。
3. **上电默认。** OSD 位刻意做成反相："`写 1 = 关掉叠层，复位 = 有 OSD`"，理由是"`不会因为"忘了初始化"变成干净画面`"（来源：`src/ps/main.c:53-57`，位表 `:11`）。发布握手复位成 `pend <= 1'b0`（来源：`src/rtl/util/ps_publish.v:29`），搬运机复位成 `m_axi_arlen<=8'd15`、`base_r<=BASE_ADDR`、指针清零（来源：`src/rtl/axi/axi_frame_writer_gated.v:105-108`）。**有判据**（复位值本身就是判据，台架 `sim/tb_ps_publish.v` 逐相位验，来源：`src/rtl/top/pl_video_top.v:556`）。
4. **纯 PL 演示树没有 PS。** `pl_demo_top.v` 把 AXI/PS 侧全部钉成常量、`.ps_publish(1'b0)`，文件头自述 "Pure-PL demo top … No PS required."——这条由 A1 §1.4 记录（来源：`ARCH/A1-architecture-and-clocking.md:77`），本卷不重复其判据。
5. **QSPI / SD 启动路径差异。** 本卷在 `src/` 下只检索到一处提及：调试脚本故意不连 JTAG，"`让 A9 停在复位态，避免它重新跑 boot ROM 把 SD/QSPI 里的旧 bit 刷回 PL`"（来源：`src/host/ddr_verify.mjs:53`）。可见的差异只有"flash/卡里可能躺着旧 bitstream，重连会把它刷回"这一条；**QSPI 与 SD 两条启动路径在帧缓存层面的完整差别：未证**（本卷未找到 RTL/固件级的第二处证据）。
6. **串口把发布时序拖死。** 判据见 `main.c:205-207` 的 28549 B / 11.5 KB/s 那笔账（来源：`src/ps/main.c:205-207`）——发布走静默的 `ctrl_write()` 而不是 `ctrl_apply()`。**有判据，但是账本型的**（一次性板级实测记录，没有回归测试）。

### 7.5 实测数据怎么核对（`data/measured/` 与 `board/compare/`）

两处的分工由文件名本身就分得开（本卷只列名、不引用其内部数字，内容核对列为未证）：

- `data/measured/`：`README.md`、`arb_handover_r28_red.json`、`board_measure_15fps.txt`、`board_measure_r08.md`、`interp_gain_attribution.txt` —— 板级一次测量的原始记录（"15 fps" 那一档正是搬运机窗口吃不下整帧时的现象）。
- `board/compare/`：`ddr-stale-15fps-dump.txt`、`ddr-stale-wordid-dump.txt`、`cdc-golden_compare-console.txt`、`cdc-golden_diff.csv`、`golden-digest-verify.txt`、`metric-recheck.txt`、`roster-golden_compare-crosscheck.txt`、`roster-diff-selfcheck.txt`、`soak300-lane-delta.txt` 等 —— 与金标逐字/逐词比较的差集。

用法上的差别可以这样记：`measured/` 回答"**板上是多少**"，`compare/` 回答"**与上一版/与仿真差在哪**"。DDR 这一层最相关的两件是 `ddr-stale-*`（过期帧：帧缓存里停留的是哪一帧、以字为单位定位）与 `cdc-golden_*`（本卷 §7.2 那类跨域脉冲同步器的形态回归）。

### 7.6 本卷的未证与缺口

1. `final_submission/src/...` 影子副本与 `src/...` 是否逐字节相同——本卷一律引用 `src/`，未做 diff。
2. bank 间距取 512 KiB 而帧只有 300 KiB，注释只说"够用"（来源：`src/rtl/top/system_top.v:141`），余量的真实用途（对齐？未来分辨率？）未证。
3. `fb_wr_addr` 是 19 位而喂进去的是**字**索引 `r_pix[18:2]`（来源：`src/rtl/axi/axi_frame_writer_gated.v:170`），而入流侧 `eth_wr_addr` 同为 19 位（来源：`src/rtl/top/system_top.v:128`）却按 `system_top.v:129` 的 16 位数据组织——两者是否为同一张 BRAM 的同一口径，需要读 `fb_bilin`/帧缓存实例才能定，本卷未开。
4. `pl_video_top.v:454` 例化同时传参数 `.BASE_ADDR(BASE_ADDR)` 与端口 `.base_addr(row_base)`（来源：同文件 `:458`），参数只作复位值（`gated.v:106`），二者不一致时行为以端口为准——是否曾有实害，未证。
5. "抢 bank" 事故对应的 ISSUES 条目号，未证（见 §6.4）。
6. `data/measured/`、`board/compare/` 内部的具体判据文本与本卷数字的对应关系，未开文件核对。

---

## 8. 一张表：本层信号台账

域的名字沿用 A1 §1.2：`clk_fpga_0`（= `axi_clk`，100 MHz，来源：`ARCH/A1-architecture-and-clocking.md:31`）、`clk_pix`（50 MHz，来源：`src/rtl/top/pl_video_top.v:721`）。

| # | 信号 | 位宽 | 时钟域 | 产生者 | 消费者 | 行号 |
|---|---|---|---|---|---|---|
| 1 | `gpio_o[18]` / `ps_publish` | 1 | `clk_fpga_0`（PS 写） | `ctrl_write()` 的 `pub_lvl << PUBLISH_BIT` | `u_pl` 端口 | `src/ps/main.c:215`、`src/rtl/top/system_top.v:288`、`src/rtl/top/pl_video_top.v:57` |
| 2 | `PUBLISH_BIT` | 宏 = 18 | — | 固件位表 | `ctrl_write()` | `src/ps/main.c:51`、位表 `src/ps/main.c:9` |
| 3 | `tog` | 1 | 异步（`axi_clk`→`clk_pix`） | 顶层 `ps_publish` 端口 | 3 级同步链 | `src/rtl/util/ps_publish.v:12`、`:22` |
| 4 | `new_tog` / `pub_new` | 1 | `clk_pix` | `m1 ^ m2` | 心跳活判据 `src_life` | `src/rtl/util/ps_publish.v:25`、`src/rtl/top/pl_video_top.v:561` |
| 5 | `consume` / `pub_consume` | 1 | `clk_pix` | `frame_start && src_use && !owner_eth_pix` | `u_pub` | `src/rtl/top/pl_video_top.v:559`、`:566` |
| 6 | `pend` / `pub_pend` | 1 | `clk_pix` | `u_pub` | `fs_tog`、`shown_rate` | `src/rtl/util/ps_publish.v:14`、`src/rtl/top/pl_video_top.v:571`、`src/rtl/util/shown_rate.v:42` |
| 7 | `owner_eth_pix` | 1 | `clk_pix` | `op2`（3 级同步的 3 拍） | `pub_consume`、`no_sig`、OSD | `src/rtl/top/pl_video_top.v:522`、`:517`、`:510` |
| 8 | `src_eff` | 2 | `clk_pix` | `{fb_vis, owner_eth_pix}` | `osd_overlay` | `src/rtl/top/pl_video_top.v:1014` |
| 9 | `eth_wr_en` / `eth_wr_addr` / `eth_wr_data` | 1 / 19 / 16 | `u_eth` 出 | 入流侧（A2 §5） | `u_pl` | `src/rtl/top/system_top.v:127-129` |
| 10 | `eth_ddr_base` | 32 | `axi_clk` 侧送 | `u_eth` 的 bank 提交 | `u_cmt .commit_base()` | `src/rtl/top/system_top.v:148`、`src/rtl/top/pl_video_top.v:432` |
| 11 | `BANK0` / `BANK1` | 32×2 | localparam | `eth_udp_video_top` | 入流写地址 | `src/rtl/eth/eth_udp_video_top.v:67-68` |
| 12 | `BASE_ADDR` / `PS_BASE_ADDR` | 32×2 | 参数 | 顶层 | `u_row` / `u_aw` | `src/rtl/top/pl_video_top.v:12`、`:16`、`src/rtl/top/system_top.v:139`、`:144` |
| 13 | `disp_quiet` | 1 | `clk_pix` | `y>=600 && (y<624 || x<=1279)` | `u_cmt .blank_safe()` | `src/rtl/top/pl_video_top.v:400-401`、`:434` |
| 14 | `allow_copy` → `allow_wr` | 1 | `axi_clk` | `frame_commit_lock` | `u_row` 的三个门 | `src/rtl/top/pl_video_top.v:438`、`:459`、`src/rtl/axi/axi_frame_writer_gated.v:81`、`:87`、`:89` |
| 15 | `row_start` / `row_base` | 1 / 32 | `axi_clk` | `u_cmt .start_copy/.copy_base` | `u_row .start/.base_addr` | `src/rtl/top/pl_video_top.v:377-378`、`:436`、`:457-458` |
| 16 | `row_busy` / `row_done` | 1×2 | `axi_clk` | `u_row` | `u_cmt .copy_busy/.copy_done` | `src/rtl/top/pl_video_top.v:377`、`:461`、`:435` |
| 17 | `copy_abort` → `abort_tgl` → `copy_abort_pix` | 1 | `axi_clk` → `clk_pix`（翻转同步） | `u_cmt` / `u_pl` | `u_row .abort()`、像素域 | `src/rtl/top/pl_video_top.v:460`、`:482-489` |
| 18 | `fb_wr_en` / `fb_wr_addr` / `fb_wr_data` | 1 / 19 / 64 | `axi_clk` | `u_row` | 顶层 `row_wr_*` → BRAM mux | `src/rtl/axi/axi_frame_writer_gated.v:22-24`、`src/rtl/top/pl_video_top.v:379-381`、`:462` |
| 19 | `m_axi_araddr/arlen/arvalid/arready` | 32 / 8 / 1 / 1 | `axi_clk` | `u_row`（`:149` 算地址） | HP0 | `src/rtl/axi/axi_frame_writer_gated.v:25-30`、`src/rtl/top/pl_video_top.v:463-465` |
| 20 | `m_axi_rdata/rlast/rvalid/rready` | 64 / 1 / 1 / 1 | `axi_clk` | HP0 | `u_row` | `src/rtl/axi/axi_frame_writer_gated.v:31-34`、`src/rtl/top/pl_video_top.v:466-467`、mux `:714` |
| 21 | `copy_cycles` / `row_copy_cycles` | 32 | `axi_clk` | `u_row` 锁存 `cyc` | `copy_overrun` | `src/rtl/axi/axi_frame_writer_gated.v:185`、`src/rtl/top/pl_video_top.v:445`、`:450` |
| 22 | `wr_words`（内部） | 32 | `axi_clk` | `fb_wr_en` 计数 | 完成条件 | `src/rtl/axi/axi_frame_writer_gated.v:113`、`:182` |
| 23 | `aw_wr_en/addr/data`（mux 后） | 1 / 19 / 64 | `axi_clk` | `eth_mode ? row_* : fill_*` | 显示帧缓存 | `src/rtl/top/pl_video_top.v:716-718` |
| 24 | `u_aw`（`axi_frame_writer64`） | 例化 | `axi_clk` | PS 片源搬运机 | 同上 mux | `src/rtl/top/pl_video_top.v:692-694` |
| 25 | `u_bilin`（`fb_bilin`）读口 | 例化 | `clk_pix` | 显示帧缓存唯一读口 | `proc_pipeline` | `src/rtl/top/pl_video_top.v:732-734`、链路口述 `:3` |
| 26 | `ps_hold` / `ps_ka_t` / `PS_HB_MS` | u8 / XTime / 100 | PS（无域） | `ps_publish()` | `ps_keepalive()` | `src/ps/main.c:201-202`、`:249-250`、`:260` |
| 27 | `pl_copy_hold` | 1 | `system_top` 线网 | `u_pl` 侧 | `u_eth` 侧 | `src/rtl/top/system_top.v:150`（本卷未追其两端连接，见 §7.6） |

表里两处需要说明的取舍：第 27 行只证明了这根线在 `system_top` 声明过，两端连接归 A1/A2 的端口表；第 8 行的 `fb_vis` 产生者本卷没有定位到具体行号，只引用它在顶层被使用的地方（来源：`src/rtl/top/pl_video_top.v:1014`）。
