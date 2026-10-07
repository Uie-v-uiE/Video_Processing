# A5 六级效果链与控制字（实现级拆解）

> 卷次说明：本卷是 `LEARNING/03-geometry-effects-osd-and-hdmi.md` 第 7–10 节的下钻版。那一卷给的是"有哪几级、每级几拍、位宽多少"的账本（来源：LEARNING/README.md:15）；本卷给的是**数据在这一站 literally 长成什么样、代码对它做了哪几步算术、哪一步失败会在屏上留下什么形状**。两边同引一份 RTL 时，本卷的引用一律落到具体行。

## 0 本卷的读法与量尺约定

| 约定 | 内容 |
| --- | --- |
| 数字来源 | 每个数字后面括号里点名的 `文件:行号` 都是本卷实际打开过的那一行；路径按仓库根算 |
| 自算的数 | 凡是本卷自己算出来的，式子与两个操作数各自的出处都要写全，见第 14 节汇总 |
| RTL 名大小写 | 一律照源文件自己的拼写（模块名、端口名全小写），不"规范化" |
| 反引号 | 反引号里的代码片段紧跟其出处，且确实落在那一行或其 ±6 行内 |
| 每节末 | 「这一站的输入/输出格式 + 出错时屏上表现」；判不明的写"未证" |

整条效果链的物理位置在 `src/rtl/top/pl_video_top.v` 的显示通路里：时序发生器出栅格 → 帧缓存读口出像素 → `proc_pipeline` 做效果 → `split_display` 逐像素混合 → `osd_overlay` 叠字 → `rgb2dvi` 串化输出（来源：src/rtl/top/pl_video_top.v:2-4）。本卷只管其中的效果链、控制字与"同帧左右对照"三块。

---

## 1 控制字：九位选择字 + 阈值 + 旋转字段 + 缝 + gamma 窗口

### 1.1 九位选择字 `stage_sel[8:0]` 的位定义

端口声明是 `input  wire [8:0]  stage_sel,`（来源：src/rtl/process/proc_pipeline.v:31），位定义的唯一出处写在同一文件头部注释第 6 行（来源：src/rtl/process/proc_pipeline.v:6），逐位落点如下。

| 位 | RTL 译码线 | PS 侧宏 | 驱动的端口 | 语义 |
| --- | --- | --- | --- | --- |
| `[0]` | `wire w_gray  = stage_sel[0];`（来源：src/rtl/process/proc_pipeline.v:52） | `#define SEL_GRAY    (1u << 0)`（来源：src/ps/main.c:110） | `.bypass(~w_gray)`（来源：src/rtl/process/proc_pipeline.v:110） | 级 1 第一路：灰度 |
| `[1]` | `wire w_inv   = stage_sel[1];`（来源：src/rtl/process/proc_pipeline.v:53） | `#define SEL_INVERT  (1u << 1)`（来源：src/ps/main.c:111） | `.bypass(~w_inv)`（来源：src/rtl/process/proc_pipeline.v:114） | 级 1 第二路：反色 |
| `[2]` | `wire w_blur  = stage_sel[2];`（来源：src/rtl/process/proc_pipeline.v:54） | `#define SEL_BLUR    (1u << 2)`（来源：src/ps/main.c:112） | `.bypass(~w_blur)`（来源：src/rtl/process/proc_pipeline.v:120） | 级 2 第一路：3×3 均值模糊 |
| `[3]` | `wire w_sharp = stage_sel[3];`（来源：src/rtl/process/proc_pipeline.v:55） | `#define SEL_SHARP   (1u << 3)`（来源：src/ps/main.c:113） | `.bypass(~w_sharp)`（来源：src/rtl/process/proc_pipeline.v:126） | 级 2 第二路：3×3 锐化 |
| `[4]` | `wire w_sobel = stage_sel[4];`（来源：src/rtl/process/proc_pipeline.v:56） | `#define SEL_SOBEL   (1u << 4)`（来源：src/ps/main.c:114） | `.bypass(~w_sobel)`（来源：src/rtl/process/proc_pipeline.v:133） | 级 3：Sobel 边缘 |
| `[5]` | `wire w_bin   = stage_sel[5];`（来源：src/rtl/process/proc_pipeline.v:57） | `#define SEL_BIN     (1u << 5)`（来源：src/ps/main.c:115） | `.bypass(~w_bin)`（来源：src/rtl/process/proc_pipeline.v:141） | 级 4：二值化使能 |
| `[6]` | `wire bin_pol = stage_sel[6];`（来源：src/rtl/process/proc_pipeline.v:58） | `#define SEL_BIN_POL (1u << 6)`（来源：src/ps/main.c:116） | `.pol(bin_pol)`（来源：src/rtl/process/proc_pipeline.v:141） | 级 4 的判决反相位 |
| `[7]` | `wire w_erode = stage_sel[7] & ~stage_sel[8];`（来源：src/rtl/process/proc_pipeline.v:59） | `#define SEL_ERODE   (1u << 7)`（来源：src/ps/main.c:117） | 折进 `morph_mode`（来源：src/rtl/process/proc_pipeline.v:61） | 级 5：腐蚀 |
| `[8]` | `wire w_dilate = stage_sel[8] & ~stage_sel[7];`（来源：src/rtl/process/proc_pipeline.v:60） | `#define SEL_DILATE  (1u << 8)`（来源：src/ps/main.c:118） | 折进 `morph_mode`（来源：src/rtl/process/proc_pipeline.v:61） | 级 5：膨胀 |

三点要盯住：

1. **`[7]`/`[8]` 是互斥而不是可叠加**：两位的译码各自带 `& ~` 另一位的条件（来源：src/rtl/process/proc_pipeline.v:59-60），所以两位同时写 1 时 `morph_mode` 取 `2'd0`（来源：src/rtl/process/proc_pipeline.v:61），级 5 整级旁路。这一条不是"没实现"，是显式旁路：级 5 的 `mode` 只有 2 bit，编码 0/1/2/3 里 3 被留着（来源：src/rtl/process/proc_morph.v:13），而模块内把 `by = (mode == 2'd0) || (mode == 2'd3);`（来源：src/rtl/process/proc_morph.v:24）——3 与 0 走同一条旁路。
2. **`[6]` 不是"第六级"**：它是级 4 判决的比较极性，接到 `proc_binary` 的 `pol` 口（来源：src/rtl/process/proc_binary.v:10），在模块里只做一次取反选择 `wire bin = pol ? ~cmp : cmp;`（来源：src/rtl/process/proc_binary.v:24）。位定义注释自己写了"仅 [5]=1 有意义"（来源：src/rtl/process/proc_pipeline.v:6）。
3. **不存在"开运算/闭运算"这两级，也不存在"亮度/对比"这一级**。本卷在 `src/rtl` 下按 `contrast`、`bright`、"开运算"三个词做过全文检索，唯一命中的字样在 `src/rtl/process/proc_morph.v:22-23`（来源：src/rtl/process/proc_morph.v:22-23），而那一行写的恰恰是"一遍做不出来、显式当旁路"。唯一改变明暗关系的数据级是级 0 的 gamma 表（来源：src/rtl/process/proc_pipeline.v:100）。本卷因此只写代码里真实存在的级。

### 1.2 阈值 `threshold[7:0]` 的完整位路

| 站 | 落点 | 内容 |
| --- | --- | --- |
| PS 影子 | `static u8  cur_thr = 80;`（来源：src/ps/main.c:171） | 默认值 80 |
| PS 写口 | `v = ((u32)cur_thr << 8) | ((u32)cur_src << 16)`（来源：src/ps/main.c:214） | 落在 `gpio_o[15:8]` |
| PL 取位 | `.threshold(gpio_o[15:8])`（来源：src/rtl/top/system_top.v:264） | 与 `stage_sel` 不是同一个 GPIO 设备 |
| 跨域 | `(* ASYNC_REG = "TRUE" *) reg [7:0] th_meta, th_sync;`（来源：src/rtl/process/effect_ctrl.v:35） | 8 位、两跳、单独一条链 |
| 复位值 | `th_meta <= 8'd80; th_sync  <= 8'd80;`（来源：src/rtl/process/effect_ctrl.v:44） | 与 PS 影子同值 |
| 出链 | `threshold = th_sync;`（来源：src/rtl/process/effect_ctrl.v:78） | 组合转出 |
| 进链 | `input  wire [7:0]  threshold,`（来源：src/rtl/process/proc_pipeline.v:32） | 顶层接 `th_sync`（来源：src/rtl/top/pl_video_top.v:802） |
| 用在哪 | 级 4 `.threshold(threshold)`（来源：src/rtl/process/proc_pipeline.v:141）与级 5 `.threshold(threshold)`（来源：src/rtl/process/proc_pipeline.v:147） | 同一个数喂两级 |

两级用的是**同一个亮度式子**：级 4 里 `wire [15:0] y16 = r8 * 8'd77 + g8 * 8'd150 + b8 * 8'd29;`（来源：src/rtl/process/proc_binary.v:22），级 5 里同一行原样再写一遍（来源：src/rtl/process/proc_morph.v:33）。所以"级 4 → 级 5 视觉上只有形状在变"这句话的机械依据就是这两行同式（来源：src/rtl/process/proc_morph.v:26）。

### 1.3 旋转相关的字段

链上能被称为"旋转的两位字段"的只有一处：顶层把 9 bit 角度的最低两位接到混合级的 `angle_idx` 口——`.angle_idx(angle[1:0]),`（来源：src/rtl/top/pl_video_top.v:925），端口声明在 `input  wire [1:0]  angle_idx,`（来源：src/rtl/video/split_display.v:33）。**这个口在本卷核对的模块体内没有任何消费者**：`split_display.v` 全文里 `angle_idx` 只出现在声明那一行（来源：src/rtl/video/split_display.v:33），后面 `left`/`oob`/`take_orig`/`sep` 四条式子都不读它（来源：src/rtl/video/split_display.v:43-53）。它是一片留在端口表上的历史接口，本卷不解释它当初要干什么——文件里没有写。

真正管旋转的是另外两处：

- 角度本体 `wire [8:0] angle;`（来源：src/rtl/top/pl_video_top.v:181），单位是十进制度 0..359，按键 ±1°、自动档每帧走 `speed` 度（来源：src/rtl/process/rotate/angle_ctrl.v:14）；`rotate_active = (angle != 9'd0)`（来源：src/rtl/process/rotate/angle_ctrl.v:18）。
- 自动旋转的速率是**三位**：`wire [2:0]  rot_speed   = gp[17:15];`（来源：src/rtl/top/pl_video_top.v:177），PS 侧宏 `#define ROT_SPEED_SHIFT 10u`（来源：src/ps/main.c:156）与 `#define ROT_SPEED_MASK  (7u << ROT_SPEED_SHIFT)`（来源：src/ps/main.c:157），开关位 `#define ROT_AUTO_BIT    (1u << 9)`（来源：src/ps/main.c:155）。自动旋转时"一帧最多走 7°"这条上界由 `360 = 7·51 + 3` 决定，所以取模用"减 360"而不是"到 359 就回 0"（来源：src/rtl/process/rotate/angle_ctrl.v:31-34）。

### 1.4 缝：10 位位置 + 三个旗标（再加一个反相的标记位）

| 字段 | PL 落点 | PS 宏 | 物理位（`gpio_cfg1`，= CFG_DATA0） |
| --- | --- | --- | --- |
| `pos_px` 10 位 | `.pos_px({2'd0, gp[9:0]}),`（来源：src/rtl/top/pl_video_top.v:887） | `#define SPLIT_POS_SHIFT   13u`（来源：src/ps/main.c:123） | `[22:13]`（来源：src/rtl/top/system_top.v:275） |
| `auto_en` | `.auto_en(gp[10]), .follow(gp[11]),`（来源：src/rtl/top/pl_video_top.v:888） | `#define SPLIT_AUTO_BIT    (1u << 23)`（来源：src/ps/main.c:137） | `[23]`（来源：src/rtl/top/system_top.v:275） |
| `follow` | 同上那一行（来源：src/rtl/top/pl_video_top.v:888） | `#define SPLIT_FOLLOW_BIT  (1u << 24)`（来源：src/ps/main.c:138） | `[24]` |
| `swap` | `.swap(gp[12])`（来源：src/rtl/top/pl_video_top.v:889） | `#define SPLIT_SWAP_BIT    (1u << 25)`（来源：src/ps/main.c:139） | `[25]` |
| `marker_off` | `wire split_marker_on = ~gp[13];`（来源：src/rtl/top/pl_video_top.v:894） | `#define SPLIT_MARKOFF_BIT (1u << 30)`（来源：src/ps/main.c:140） | `[30]` |

拼接那一行是整个几何字的唯一形状：`.split_ctl({gpio_cfg1_o[31], gpio_cfg1_o[12:10], gpio_cfg1_o[9], gpio_cfg1_o[30], gpio_cfg1_o[25:23], gpio_cfg1_o[22:13]})`（来源：src/rtl/top/system_top.v:274-275）——19 位一次成形（来源：src/rtl/top/pl_video_top.v:54）。

`marker_off` 是**反相语义**：写 1 才是关，所以复位（19 位全 0）时 `gp[13]` 为 0、`split_marker_on` 为 1，屏上仍画那条线（来源：src/rtl/top/pl_video_top.v:892-894）。OSD 的叠层总开关走同一口径（1 = 关掉，来源：src/rtl/top/system_top.v:287）。

**10 位的后果是 100 % 这一格手工打不到**：字段最大 `10'h3FF` = 1023（来源：src/ps/main.c:124 的掩码 `0x3FFu << SPLIT_POS_SHIFT`），而显示域宽是 1024（来源：src/rtl/top/pl_video_top.v:885 传的 `.DISP_W(2*PANE_W)`，`PANE_W` = 512 来源：src/rtl/top/pl_video_top.v:11）。百分比那一级见第 12.3 节，本卷按式子算：`1023 × 1600 >> 14 = 99`（`PCT` 的 1600 出自来源：src/rtl/video/split_ctrl.v:112，`>>14` 出自来源：src/rtl/video/split_ctrl.v:117）。PS 侧还登记了一个更凶的写法事故：把 1024 直接左移 13 位得到 `0x800000`，恰好撞上 `SPLIT_AUTO_BIT`（bit23）（来源：src/ps/main.c:126-127）。

### 1.5 gamma 的索引/数据窗口（第二个控制字的通道 2）

32 位窗口的一次跨域搬 6 个字段（来源：src/rtl/process/effect_ctrl.v:15），位序正本写在两处且必须一致：

| 位 | 字段 | RTL 拆位线 | PS 宏 |
| --- | --- | --- | --- |
| `[31]` | `en` | `gamma_async[31]`（来源：src/rtl/process/effect_ctrl.v:54） | `#define GM_EN             (1u << 31)`（来源：src/ps/main.c:97） |
| `[30]` | `wr`（**翻转位**） | `gamma_async[30]`（来源：src/rtl/process/effect_ctrl.v:54） | `#define GM_WR             (1u << 30)`（来源：src/ps/main.c:98） |
| `[29:22]` | `data` 8 位 | `gamma_async[29:22]`（来源：src/rtl/process/effect_ctrl.v:54） | `#define GM_DATA(v)        ((((u32)(v)) & 0xFFu) << 22)`（来源：src/ps/main.c:99） |
| `[21:14]` | `idx` 8 位 | `gamma_async[21:14]`（来源：src/rtl/process/effect_ctrl.v:55） | `#define GM_IDX(i)         ((((u32)(i)) & 0xFFu) << 14)`（来源：src/ps/main.c:100） |
| `[13:8]` | `gamma_disp`（γ×10，6 位，只给屏） | `gamma_async[13:8]`（来源：src/rtl/process/effect_ctrl.v:55） | `#define GM_DISP(v)        ((((u32)(v)) & 0x3Fu) << 8)`（来源：src/ps/main.c:102） |
| `[7:0]` | `temp_disp`（两位 BCD，只给屏） | `gamma_async[7:0]`（来源：src/rtl/process/effect_ctrl.v:55） | `#define GM_TEMP(v)        (((u32)(v)) & 0xFFu)`（来源：src/ps/main.c:105） |

六个字段过**同一对** ASYNC_REG（来源：src/rtl/process/effect_ctrl.v:39），解包是一句整体赋值 `{gamma_en, gamma_wr, gamma_data, gamma_idx, gamma_disp, temp_disp} = gm_sync;`（来源：src/rtl/process/effect_ctrl.v:67）。为什么必须成一条链：协议要求"idx/data 在 wr 翻转之前已经稳定"，分组同步就会出现"边沿到了、数据还是上一次的"（来源：src/rtl/process/effect_ctrl.v:36-38）。

写入协议是"先摆地址与数据、下一次写翻 `wr`"：PS 侧 `gamma_put()` 里先 `Xil_Out32(CFG_DATA1, gm_w | GM_DATA(v) | GM_IDX(i));` 再 `gm_w ^= GM_WR;` 后重同一字（来源：src/ps/main.c:368-371）；PL 侧边沿检测 `wire do_wr = rst_n && (wr !== prev);`（来源：src/rtl/video/gamma_lut.v:39），复位时把 `prev` 与 `wr` 一起置 0，否则上电本身会被当成一次写事件（来源：src/rtl/video/gamma_lut.v:31-37）。表项落进三张表：`tr[idx] <= data;` 同拍写 `tg`、`tb`（来源：src/rtl/video/gamma_lut.v:43-45）。

**这一站的输入/输出格式 + 出错时屏上表现**

| 项 | 内容 |
| --- | --- |
| 输入 | PS 的一次 32 位寄存器写（`CFG_DATA0` 效果/几何字，来源：src/ps/main.c:78；`CFG_DATA1` gamma 窗口，来源：src/ps/main.c:96） |
| 输出 | `clk_pix` 域里稳定的 `stage_sel[8:0]`、`threshold[7:0]`、gamma 的 4 个字段 + 2 个显示字段（来源：src/rtl/process/effect_ctrl.v:16-25） |
| 出错样子 | 控制字错位时屏上第一处可见的是 OSD 第 2 行 `Pipe:` 那五位（它是九位的投影，来源：src/rtl/video/osd_overlay.v:133-142）；`wr` 被当电平用的表现是"整表反复重写"，`tb_v88_gamma` 的 `T5 只改 idx/data 不翻 wr ⇒ 整张表不变` 判的就是它（来源：sim/tb_v88_gamma.v:162）。复位值没接上时的屏上表现（`Temp:--` 与有蓝线）是**预期行为**，不是错 |

---

## 2 级 0：gamma 查找表（唯一的明暗级）

**算法定义**。这一级不是乘加，是三次查表再截回 5/6/5：`wire [15:0] y16 = {tr[r8][7:3], tg[g8][7:2], tb[b8][7:3]};`（来源：src/rtl/video/gamma_lut.v:51），出口 `assign dout = en ? y16 : din;`（来源：src/rtl/video/gamma_lut.v:52）。曲线本体不在 PL：PS 侧 `float y = pow((float)i / 255.0f, e) * 255.0f + 0.5f;`（来源：src/ps/main.c:379），指数 `float e = 100.0f / (float)g100;`（来源：src/ps/main.c:378），随后夹到 `[0,255]`（来源：src/ps/main.c:380-381）——γ=1.00 时 `e = 1`（由来源：src/ps/main.c:378 那条式子本卷代入 g100=100 算得），表退化成恒等，这一条写在该函数头的注释里（来源：src/ps/main.c:375）。PL 只照画，所以屏上 `Gamma:` 那一格与串口 `[GAMMA]` 打印必然同源（来源：src/rtl/process/effect_ctrl.v:67 那条注释）。

**3×3 窗口怎么组织**：不适用。这一级是点运算，`gamma_lut` 全文没有任何存储器阵列形式的邻域（来源：src/rtl/video/gamma_lut.v:18-29 只有扩展式子与三张表）。存储的是**表**而不是行：三张 `(* ram_style = "distributed" *) reg [7:0] tr [0:255];` 同形状的 `tg`/`tb`（来源：src/rtl/video/gamma_lut.v:27-29）。三通道共用一份内容、复制三份 RAM，理由是"一份三读"要多两个读口，复制三份则由同一个写口保证一致（来源：src/rtl/video/gamma_lut.v:2-3）。

**卷积系数与定点化**：无系数；定点化发生在两处——写入时 PS 做 `+0.5f` 的四舍五入（来源：src/ps/main.c:379），读出时 PL 做纯截断 `{tr[r8][7:3], tg[g8][7:2], tb[b8][7:3]}`（来源：src/rtl/video/gamma_lut.v:51）。截断丢掉低 3 bit（来源：src/rtl/video/gamma_lut.v:51 的 `[7:3]` 切片），本卷按式子算最大误差：8 bit 域里丢的值域是 0..7 ⇒ 上界 7/255 = 2.745 %。索引侧还有第二个事实：`wire [7:0] r8 = {r5, r5[4:2]};`（来源：src/rtl/video/gamma_lut.v:23）只有 2^5 = 32 个不同取值（`r5` 是 5 bit，来源：src/rtl/video/gamma_lut.v:20），`g8` 由 6 bit 的 `g6` 复制而来（来源：src/rtl/video/gamma_lut.v:24）有 64 个 ⇒ **256 项的表红/蓝通道实际只被索引到 32 个位置**。

**边界像素**：不适用（不越界、不回绕，每个像素只看自己）。唯一"边界"意义上的东西是表的下标边界，台架用 `r5=0 ⇒ 索引 0x00、r5=31 ⇒ 索引 0xFF` 两端各查一次（来源：sim/tb_v88_gamma.v:183）。

**bypass 怎么走通**：`en` 是组合二选一（来源：src/rtl/video/gamma_lut.v:52），旁路时数据不碰表；顶层把 `gm_en` 直连过来（来源：src/rtl/top/pl_video_top.v:803），链内是 `.en(gamma_en)`（来源：src/rtl/process/proc_pipeline.v:104）。关使能**不清表**（来源：src/ps/main.c:389-391 只 `&= ~GM_EN`），所以现场能在开/关之间来回切。

**几拍**：0 拍。表是分布式 RAM 的组合读出，模块头自己声明"它**不加拍数**（分布式 RAM 非同步读出）⇒ LATENCY 常数不动"（来源：src/rtl/video/gamma_lut.v:7），链侧同一口径写在 `// 级 0 明暗：gamma。**组合读出，不占拍数**`（来源：src/rtl/process/proc_pipeline.v:100）。挂在第 0 级而不是最后一级，是为了让"左窗原图 / 右窗处理图"的对照语义对 gamma 也成立（来源：src/rtl/video/gamma_lut.v:6）。

**资源**：`u_gamma` 一行给 Total LUTs 191、Logic LUTs 95、LUTRAMs 96、FFs 1（来源：build/util_hier_probe.rpt:70）。LUTRAMs 96 与本卷按表形状算的一致：3 × 256 × 8 / 64 = 96（一个分布式 RAM 单元 64 bit 是本卷的假设，**未在本仓库文档里核到**，因此这一条只能当"数对得上"的旁证而不是凭据；RAMB36/RAMB18 两列该行为 0 才是"没落 BRAM"的直接凭据，来源：build/util_hier_probe.rpt:70）。整条链 DSP 只有 1 颗且归 `u_blur`（来源：build/util_hier_probe.rpt:66 与 :69）。

| 这一站的输入/输出格式 | |
| --- | --- |
| 输入 | 16 bit RGB565 一路 + `de` 同拍；无邻域、无坐标（来源：src/rtl/video/gamma_lut.v:15） |
| 输出 | 16 bit RGB565，同一拍（组合），`de` 不经过本级（来源：src/rtl/video/gamma_lut.v:16） |
| 出错时屏上表现 | 位序接错的形状由台架钉：`T3 表=0xFF-i 时三路各按自己展开后的索引查表`、`T4 表=i^0x5A 时输出等于查表结果（不是透传、也不是别的位序）`（来源：sim/tb_v88_gamma.v:138 与 :143）；若有人把它改成寄存读出而不改 `LATENCY`，`tb_v86` 的 T2「实测 de 延迟 == 模块声明的 LATENCY」当场红（来源：sim/tb_v86_pipe_sel.v:164）。板级具体错色形状：未证 |

## 3 级 1 第一路：灰度（去色）

**算法定义**。`proc_gray` 是"展宽 → 加权和 → 取高 8 位 → 折回 565"四步：展开 `wire [7:0] r8 = {r5, r5[4:2]};` 同形 `g8`/`b8`（来源：src/rtl/process/proc_gray.v:18-20），加权 `wire [15:0] y16 = r8 * 8'd77 + g8 * 8'd150 + b8 * 8'd29;`（来源：src/rtl/process/proc_gray.v:22），取高 8 位 `wire [7:0]  y8  = y16[15:8];`（来源：src/rtl/process/proc_gray.v:23），折回 `wire [15:0] gray = {y8[7:3], y8[7:2], y8[7:3]};`（来源：src/rtl/process/proc_gray.v:24）。

**系数与定点化**。系数是 77/150/29，本卷求和：77 + 150 + 29 = 256，所以取 `y16[15:8]` 就是除 256 的归一化（式子来源：src/rtl/process/proc_gray.v:22-23）；注释把这条写成 BT.601 的 0.299/0.587/0.114 定点近似（来源：src/rtl/process/proc_gray.v:21）。最大中间值本卷按式子算：255 × 256 = 65280 < 2^16 = 65536 ⇒ 16 bit 容器装得下、不需要饱和（`wire [15:0] y16` 声明来源：src/rtl/process/proc_gray.v:22）。

**3×3 窗口**：不适用，本级无存储器（模块体内只有线网与一个 always 块，来源：src/rtl/process/proc_gray.v:14-34）。
**边界像素**：不适用。
**几拍**：1 拍，`de_out <= de_in;` 与 `dout   <= bypass ? din : gray;`（来源：src/rtl/process/proc_gray.v:31-32）。
**bypass**：链里以反相形式接进来 `.bypass(~w_gray)`（来源：src/rtl/process/proc_pipeline.v:110），旁路那一支就是 `din` 原样过一级寄存器。

**资源**：本卷在实现级名册里找不到 `u_gray` 单独一行（来源：build/util_hier_probe.rpt:66-73 列出的是 `(u_pipe)`/`u_bin`/`u_blur`/`u_gamma`/`u_morph`/`u_sharp`/`u_sobel` 七个子实例）⇒ **未单列**，本卷不解释缺失原因，只登记"这份报告里没有它"。

| 这一站的输入/输出格式 | |
| --- | --- |
| 输入 | 16 bit RGB565 + `de_in`（来源：src/rtl/process/proc_gray.v:9-10） |
| 输出 | 16 bit RGB565 + `de_out`，晚 1 拍；有效色只剩 R=G=B 的灰阶形状（因 `gray` 的三路都取 `y8` 的高位，来源：src/rtl/process/proc_gray.v:24） |
| 出错时屏上表现 | 方向接反（偏亮/偏暗）由 `tb_proc_gray` 两条极性判据拦：红输入不许出亮灰、白输入不许出暗灰（来源：sim/tb_proc_gray.v:46 与 :56）；`de` 丢了由同文件第一条拦（来源：sim/tb_proc_gray.v:41）。台架 T7 另判"灰度后 `v[15:11]===v[4:0]`"（来源：sim/tb_v86_pipe_sel.v:10 的判据说明） |

## 4 级 1 第二路：反色

**算法定义**。三段各自取反再拼回：`wire [4:0] r5 = ~din[15:11];`、`wire [5:0] g6 = ~din[10:5];`、`wire [4:0] b5 = ~din[4:0];`（来源：src/rtl/process/proc_invert.v:14-16），拼回 `wire [15:0] inv = {r5, g6, b5};`（来源：src/rtl/process/proc_invert.v:17）。分段取反与整字取反在位宽上等价（本卷按 5+6+5=16 位全覆盖算，声明来源：src/rtl/process/proc_invert.v:10），所以它没有"低 16 位之外的位被反掉"的坑。

**3×3 窗口 / 系数 / 边界**：全部不适用——本级既没有存储器也没有算术（模块体只有三条取反与一条寄存器输出，来源：src/rtl/process/proc_invert.v:14-27）。
**几拍**：1 拍（来源：src/rtl/process/proc_invert.v:24-25）。
**bypass**：`.bypass(~w_inv)`（来源：src/rtl/process/proc_pipeline.v:114），旁路是 `dout   <= bypass ? din : inv;` 的那一支（来源：src/rtl/process/proc_invert.v:25）。

**为什么它和灰度各占 1 拍**：两者是**串接**的，不是二选一的并行 mux——`u_gray` 的输出 `de1a/d1a` 直接是 `u_inv` 的输入（来源：src/rtl/process/proc_pipeline.v:111-115）。链头的延迟账因此写的是"灰度1+反色1"（来源：src/rtl/process/proc_pipeline.v:18），文件头也把这条讲成"与 proc_gray **串接**（所以两个各占自己的 1 拍）"（来源：src/rtl/process/proc_invert.v:2）。同级两个选项串联这件事在锐化/模糊那一对上同样成立（来源：src/rtl/process/proc_sharpen.v:2-3）。

**资源**：同 `u_gray`，实现级名册里未单列（来源：build/util_hier_probe.rpt:66-73）。

| 这一站的输入/输出格式 | |
| --- | --- |
| 输入 | 上一级出来的 16 bit RGB565 + `de`（来源：src/rtl/process/proc_invert.v:9-10） |
| 输出 | 同格式，晚 1 拍（来源：src/rtl/process/proc_invert.v:24-25） |
| 出错时屏上表现 | "旁路不干净"的形状是屏上多出输入里没有的颜色，`tb_v86` 的 T1 判"sel=0 输出只含输入里出现过的颜色（旁路不做任何运算）"（来源：sim/tb_v86_pipe_sel.v:154）。板级反色错位的可见形状：未证 |

---

## 5 级 2 第一路：3×3 均值模糊

**算法定义**。逐通道取九点算术平均，用"乘 57 右移 9"代替除 9：`wire [16:0] rp = rs * 17'd57;`（来源：src/rtl/process/proc_box_blur.v:115），取位 `wire [4:0] r_avg = rp[13:9];`（来源：src/rtl/process/proc_box_blur.v:118），文件头把这一招写成 `*57 >> 9 ≈ /9  (57/512 ≈ 0.1113)`（来源：src/rtl/process/proc_box_blur.v:114）。本卷按这两个数算相对误差：57/512 = 0.111328125，1/9 = 0.111111…，相对偏差 (0.111328125 − 0.111111…)/0.111111… = **+0.195 %**（两个操作数各来自来源：src/rtl/process/proc_box_blur.v:115 与 :114）。

**3×3 窗口怎么组织**。两条整宽行缓存 + 一套 3 级移位寄存器，没有第三种存储：

| 存储 | 声明 | 宽度 | 装什么 |
| --- | --- | --- | --- |
| 上上行缓存 | `(* ram_style = "distributed" *) reg [15:0] lb0 [0:H_ACTIVE-1];`（来源：src/rtl/process/proc_box_blur.v:19） | 16 bit × H_ACTIVE | 上上行的原色 |
| 上一行缓存 | 同形状的 `lb1`（来源：src/rtl/process/proc_box_blur.v:20） | 16 bit × H_ACTIVE | 上一行的原色 |
| 窗口 | `reg [15:0] p00, p01, p02, p10, p11, p12, p20, p21, p22;`（来源：src/rtl/process/proc_box_blur.v:22） | 9 × 16 bit | 移位后的 3×3，中心是 `p11` |

`H_ACTIVE` 是"一行有多少个有效拍"而不是屏宽（来源：src/rtl/process/proc_pipeline.v:9），顶层递进去的是 `.H_ACTIVE(2*IMG_W)`（来源：src/rtl/top/pl_video_top.v:800）而 `IMG_W = 512`（来源：src/rtl/top/pl_video_top.v:9）⇒ 本级的"一行"实际是 **1024 个有效拍**，于是 3×3 的空间尺度按 1024 列算、同级相邻两列在源上只差半格（来源：src/rtl/process/proc_pipeline.v:11）。写侧只有一道门：`if (de_in)` 里 `lb0[x_in] <= lb1[x_in]; lb1[x_in] <= din;`（来源：src/rtl/process/proc_box_blur.v:45-48）——同一拍把上一行"晋升"成上上行、把当拍数据写进上一行。读侧 `wire [15:0] r0 = lb0[x_rd]; wire [15:0] r1 = lb1[x_rd];`（来源：src/rtl/process/proc_box_blur.v:51-52），`x_rd` 见第 10.2 节。

**卷积系数与定点化**。九点等权：R/B 每点 5 bit、G 每点 6 bit（切片 `[15:11]` 与 `[10:5]`，来源：src/rtl/process/proc_box_blur.v:104-112），三个和式分别声明 `wire [9:0] rs`、`wire [10:0] gs`、`wire [9:0] bs`（来源：src/rtl/process/proc_box_blur.v:104/107/110）。注释里的位宽账写的是 `(5b*9=9b, 6b*9=10b)`（来源：src/rtl/process/proc_box_blur.v:103），本卷按满量程算上界：R/B 最大 31×9 = 279 需 9 bit，G 最大 63×9 = 567 需 10 bit ⇒ 声明比这个账各多 1 bit（更宽不是错，但注释与声明不同口径这一条登记在此）。乘积容器 `rp`/`gp`/`bp` 分别是 `[16:0]`/`[17:0]`/`[16:0]`（来源：src/rtl/process/proc_box_blur.v:115-117）；本卷代入满量程：279×57 = 15903 < 2^15，567×57 = 32319 < 2^16 ⇒ 都装得下。取位 `gp[14:9]`（来源：src/rtl/process/proc_box_blur.v:119）与 `rp[13:9]`（来源：src/rtl/process/proc_box_blur.v:118）都是**截断、不加舍入**。平场自检（本卷按式子算）：R 满量程 31 的九点和 = 279，279×57 = 15903，15903 >> 9 = 31.06 → 截断得 31 ⇒ 纯白平面过这一级仍是纯白。

**边界像素怎么处理**。两级 clamp-to-edge：水平方向缺左邻就复制中心列 `wire [15:0] h00 = no_left ? p01 : p00;` 同形 h02/h10/h12/h20/h22（来源：src/rtl/process/proc_box_blur.v:89-91），垂直方向"只缺上邻 ⇒ 上行复制中心行、整行陈旧 ⇒ 上行与中心行都复制当前行"（来源：src/rtl/process/proc_box_blur.v:95-101）。旧写法是"最外圈直出原图"，那条断层就是用户报的左边/上边一条带（来源：src/rtl/process/proc_box_blur.v:87-88 与 :56-59）。

**bypass 怎么走通**。旁路取的是**窗口中心抽头**而不是输入：`wire [15:0] center = stale_row ? e21 : p11;`（来源：src/rtl/process/proc_box_blur.v:125）然后 `if (bypass) dout <= center;`（来源：src/rtl/process/proc_box_blur.v:147-148）。理由写在文件里：中心抽头在陈旧行上是上一帧的尾巴，旁路不跟着换的话"关掉效果"时上边缘那条陈旧带原样还在（来源：src/rtl/process/proc_box_blur.v:123-124）。

**这一级几拍**。3 拍，`de_d1 <= de_in; de_d2 <= de_d1; de_out <= de_d2;`（来源：src/rtl/process/proc_box_blur.v:144-146），链头特意警告"窗口级是**三拍**不是两拍"（来源：src/rtl/process/proc_pipeline.v:19-20）。

**资源**：`u_blur` 一行 Total LUTs 441、Logic LUTs 441、LUTRAMs 0、SRLs 0、FFs 199、DSP Blocks 1（来源：build/util_hier_probe.rpt:69）。这一颗 DSP 是整条链唯一的 DSP（链合计 DSP = 1，来源：build/util_hier_probe.rpt:66）。LUTRAMs 列为 0 而两条 16×1024 的行缓存仍然存在——本卷不解释它落成了什么结构，报告只给到这一列（该文件深度限制见来源：build/util_hier_probe.rpt:6 那条命令行）。

| 这一站的输入/输出格式 | |
| --- | --- |
| 输入 | 16 bit RGB565 + `de` + 与本级同拍的 `x_in/y_in`（坐标抽头号 `xd[2]`，来源：src/rtl/process/proc_pipeline.v:95）+ `hs_in/vs_in`（来源：src/rtl/process/proc_pipeline.v:121-122） |
| 输出 | 同格式，晚 3 拍；每个输出格的值是它自己那 3×3 邻域的平均，横向覆盖 1.5 个源列（因 1024 拍/行，来源：src/rtl/top/pl_video_top.v:797-799） |
| 出错时屏上表现 | 行尾少发一样本 → 每行最后一格重复前一列，`tb_v89_align` 的 `ID 旁路必须逐列恒等（含每行最后一列，偏移只有一个值）` 判它（来源：sim/tb_v89_align.v:265）；边界旁路成原图 → 左/上一条锐利的带，`PASS R2/D1 left column is processed, not passed through`（来源：sim/tb_edge_rim.v:300 与 :441）；缝边被上一行末尾污染 → `C2 主判据` 那三条（来源：sim/tb_v92_seam_bleed.v:237-240） |

## 6 级 2 第二路：3×3 锐化（四邻拉普拉斯）

**算法定义**。核写成 `[0,-1,0 ; -1,5,-1 ; 0,-1,0]`（来源：src/rtl/process/proc_sharpen.v:2），四邻是上/下/左/右而不是八邻（来源：src/rtl/process/proc_sharpen.v:90）。实现里没有负数：`r_c` 是 5 倍中心（由"左移 2 加自己"得到 4 倍再加 1 倍，来源：src/rtl/process/proc_sharpen.v:92），`r_n` 是四邻之和（来源：src/rtl/process/proc_sharpen.v:93-94），差值走比较后再减 `wire [8:0] r_d = (r_c > r_n) ? (r_c - r_n) : 9'd0;`（来源：src/rtl/process/proc_sharpen.v:102），最后夹到满量程 `wire [4:0] r_o = (r_d > 9'd31)  ? 5'd31 : r_d[4:0];`（来源：src/rtl/process/proc_sharpen.v:105）与 6 bit 的 `g_o`（来源：src/rtl/process/proc_sharpen.v:106）。

**为什么要先比较再相减**：Verilog 的无符号减法会回绕，直接 `a-b` 再判负是错的，表现是"暗边变成一圈亮边"（来源：src/rtl/process/proc_sharpen.v:4-5）。台架把这条钉成 `T3c 暗侧贴边 x=7 被压到 0（不减成负数回绕）`（来源：sim/tb_v85_sharpen.v:149）。

**窗口组织**：与模糊同形——两条 16 bit 分布式行缓存 `lb0`/`lb1`（来源：src/rtl/process/proc_sharpen.v:20-21）、九个 16 bit 抽头寄存器改叫 `q00..q22`（来源：src/rtl/process/proc_sharpen.v:23）、同一套 `run/owed/line_end/shift_w`（来源：src/rtl/process/proc_sharpen.v:35-42）、同一个 `x_rd`（来源：src/rtl/process/proc_sharpen.v:43）。抽头约定被特意写成与模糊一模一样：**移位之前**的 `p00..p22` 就以 `p11` 为中心（来源：src/rtl/process/proc_sharpen.v:89-90），顺手用 `up2/up1`（还没移进窗口的新值）会把整幅图错一行（来源：src/rtl/process/proc_sharpen.v:91）。

**算术上界**（本卷代入满量程）：R/B 的 `r_c` 最大 31×5 = 155、`r_n` 最大 4×31 = 124，两者都声明 9 bit（来源：src/rtl/process/proc_sharpen.v:92-94），155 < 2^8 装得下；G 的 `g_c` 最大 63×5 = 315 < 2^9，声明 10 bit（来源：src/rtl/process/proc_sharpen.v:95）。差值容器 `r_d` 9 bit 而最大值 155 ⇒ 夹位这一步是必需的而不是保险（来源：src/rtl/process/proc_sharpen.v:102-105）。

**边界像素**：与模糊**逐字同形**的四套旗标 + clamp-to-edge（来源：src/rtl/process/proc_sharpen.v:74-86）；"逐字同形"不是审美要求，它是差分台架 `S4`/`tb_v92` 能成立的前提（来源：src/rtl/process/proc_sharpen.v:48-50）。

**bypass**：`dout   <= bypass ? p11 : sharp;`（来源：src/rtl/process/proc_sharpen.v:128），注释说明取 `p11` 是为了与模糊同一约定（来源：src/rtl/process/proc_sharpen.v:127）。差分判据是 `T1 旁路与 blur 的旁路逐位相同`（来源：sim/tb_v85_sharpen.v:120）。

**这一级几拍**：3 拍（`de_d1 <= de_in; de_d2 <= de_d1; de_out <= de_d2;`，来源：src/rtl/process/proc_sharpen.v:124-126）。**注意一处文档/代码分歧**：本模块文件头写"延迟与 blur 一致（固定 2 拍，与 bypass 无关）"（来源：src/rtl/process/proc_sharpen.v:5），而它自己的 `de` 链是 `de_in → de_d1 → de_d2 → de_out` 三跳（来源：src/rtl/process/proc_sharpen.v:124-126），链头记的账也是"锐化3"（来源：src/rtl/process/proc_pipeline.v:18）。本卷按后者（3 拍）记账，并把这行旧注释登记为未修的口径残留。

**资源**：`u_sharp` Total LUTs 383、FFs 183、DSP 0（来源：build/util_hier_probe.rpt:72）。

| 这一站的输入/输出格式 | |
| --- | --- |
| 输入 | 16 bit RGB565 + `de` + 坐标抽头 `xd[5]`/`yd[5]`（来源：src/rtl/process/proc_pipeline.v:96/127） |
| 输出 | 同格式，晚 3 拍；每通道独立，值域被夹在 `[0,31]/[0,63]/[0,31]`（来源：src/rtl/process/proc_sharpen.v:105-107） |
| 出错时屏上表现 | 平场被改动 = 数学错了：`T2 平场锐化后逐位不变（5c-4c=c，且没有溢出）`（来源：sim/tb_v85_sharpen.v:131）；只钳 R/B 忘钳 G：`T5 G 过冲钳到 6 bit 的满量程 63（不是 31）`（来源：sim/tb_v85_sharpen.v:167）；脉冲数不对：`T7 de_out 脉冲数等于像素数（延迟与 bypass 无关）`（来源：sim/tb_v85_sharpen.v:178）。板级"暗边一圈亮边"的具体照片读数：未证 |

## 7 级 3：Sobel 边缘（白边黑底）

**算法定义**。两块 3×3 分别算 Gx/Gy：`wire signed [10:0] gx = -$signed({3'b0,p00}) - $signed({2'b0,p10,1'b0}) - $signed({3'b0,p20}) + $signed({3'b0,p02}) + $signed({2'b0,p12,1'b0}) + $signed({3'b0,p22});`（来源：src/rtl/process/proc_sobel.v:111-112），`gy` 是同形状的纵向版本（来源：src/rtl/process/proc_sobel.v:113-114）。中列权重是 2，靠 `{2'b0,p10,1'b0}` 这种"尾附 0"的拼接实现（来源：src/rtl/process/proc_sobel.v:111）。

**位宽与截断**（本卷按式子推导）：Gx 的负项系数和 = 1+2+1 = 4、正项同样 4，输入是 8 bit 亮度（`wire [7:0]  y8  = y16[15:8];`，来源：src/rtl/process/proc_sobel.v:37）⇒ 取值区间 ±(4×255) = ±1020，11 bit 有符号刚好装下（声明 `signed [10:0]`，来源：src/rtl/process/proc_sobel.v:111）。幅度取 `mag = agx + agy`（来源：src/rtl/process/proc_sobel.v:117），上界 2×1020 = 2040 ⇒ 12 bit 容器（同处声明 `[11:0]`）；随后 `wire [7:0]  m8  = (mag > 12'd255) ? 8'd255 : mag[7:0];`（来源：src/rtl/process/proc_sobel.v:118）**先夹再截**——`mag[7:0]` 是低 8 位直取，所以夹位不是装饰：不夹的话 256 会变成 0。折回 565 用的是 `wire [15:0] sobel_out = {m8[7:3], m8[7:2], m8[7:3]};`（来源：src/rtl/process/proc_sobel.v:119），即又截一次低 3 bit。取绝对值是 `wire [10:0] agx = gx[10] ? -gx : gx;`（来源：src/rtl/process/proc_sobel.v:115）——符号位单独判、不做比较运算。

**窗口组织**。这一级存的是**亮度**而不是原色，所以两条行缓存只有 8 bit：`(* ram_style = "distributed" *) reg [7:0] lb0 [0:H_ACTIVE-1];` 与 `lb1`（来源：src/rtl/process/proc_sobel.v:20-21），写侧把当拍算出的 `y8` 写进 `lb1`、把 `lb1` 晋升进 `lb0`（来源：src/rtl/process/proc_sobel.v:41-42）。**另外一条 16 bit 的原色缓存**只为旁路存在：`(* ram_style = "distributed" *) reg [15:0] mc1 [0:H_ACTIVE-1];`（来源：src/rtl/process/proc_sobel.v:27），原因写得很直白——本级窗口链存 8 bit 亮度，而"旁路 = 只搬运不运算"要求搬的是原来那 16 bit，并且必须与其它三级取同一个中心抽头（来源：src/rtl/process/proc_sobel.v:23-26）。

**边界像素**。与模糊/锐化同一套四旗标 + clamp-to-edge（来源：src/rtl/process/proc_sobel.v:94-104）。文件里保留了这条历史：本级**以前完全没有**边界判据，`y_in` 端口甚至从没被用过，后果是"每行第 0 列的左邻 = 上一行末尾的像素、每帧第 0 行的上一行 = 上一帧最后一行"，右窗分割线旁边因此糊出一竖一横两条错色（来源：src/rtl/process/proc_sobel.v:106-109）。今天 `y_in` 有两处消费者：`no_above_r [0] <= de_in && (y_in == 12'd1) && row_first;`（来源：src/rtl/process/proc_sobel.v:84）与 `stale_row_r[0] <= de_in && (y_in == 12'd0);`（来源：src/rtl/process/proc_sobel.v:85）。

**bypass**。`dout <= stale_row ? d21 : c11;`（来源：src/rtl/process/proc_sobel.v:150）——`c11` 是与 `p11` 同步搬的原色中心（来源：src/rtl/process/proc_sobel.v:138），`d21` 是当前行那一路的原色（来源：src/rtl/process/proc_sobel.v:140）。以前这里写 `dout <= din`，本级自洽但整链里只有它不跟随行约定，代价是"开 Sobel 时画面跳一行 + 比标签快 2 列"（来源：src/rtl/process/proc_sobel.v:145-147）。

**这一级几拍**：3 拍（来源：src/rtl/process/proc_sobel.v:142-144）。
**资源**：`u_sobel` Total LUTs 411、FFs 191、DSP 0（来源：build/util_hier_probe.rpt:73）。

| 这一站的输入/输出格式 | |
| --- | --- |
| 输入 | 16 bit RGB565（亮度在本级内部重算，来源：src/rtl/process/proc_sobel.v:30-37）+ 坐标抽头 `xd[8]`/`yd[8]`（来源：src/rtl/process/proc_pipeline.v:97）+ `vs_in`（来源：src/rtl/process/proc_pipeline.v:134） |
| 输出 | 16 bit RGB565，晚 3 拍；有效内容只剩"灰阶的边缘"这一种形状（三路同值，来源：src/rtl/process/proc_sobel.v:119） |
| 出错时屏上表现 | 中心取错 → 输出与标签差一行/两列，`tb_v89_align` 的 T0/T1 两条钉死（来源：sim/tb_v89_align.v:334 与 :312）；缝边污染 → `tb_v92` 的 C2/C3，而该文件末尾说明把这两条的红登记为在册缺陷"blur 只挡首行、sobel 两个都不挡"（来源：sim/tb_v92_seam_bleed.v:294）；本卷**没有重跑**这条台架，因此不写它今天的红绿 |

---

## 8 级 4：二值化（阈值 + 判决反相位）

**算法定义**。一条比较加一条极性选择：`wire        cmp = (y16[15:8] >= threshold);`（来源：src/rtl/process/proc_binary.v:23）、`wire bin = pol ? ~cmp : cmp;`（来源：src/rtl/process/proc_binary.v:24）、`wire [15:0] bw = bin ? 16'hFFFF : 16'h0000;`（来源：src/rtl/process/proc_binary.v:25）。文件头把两级语义写成"pol=0 亮于阈值算白（V7 的行为）；pol=1 暗于阈值算白（同一级的第二个算法，不额外占硬件）"（来源：src/rtl/process/proc_binary.v:4）。

**亮度从哪来**：与级 5、与级 1 的灰度是**同一个式子第三次抄写**——`wire [15:0] y16 = r8 * 8'd77 + g8 * 8'd150 + b8 * 8'd29;`（来源：src/rtl/process/proc_binary.v:22），展开式同形（来源：src/rtl/process/proc_binary.v:19-21）。为什么故意不共用一份逻辑：三处公式必须能被独立核对，谁改了另一处会在"灰度图与 gamma 图对不上"时暴露（来源：src/rtl/video/gamma_lut.v:18-19）。

**阈值这个数的形状**：8 bit 无符号，与 `y16[15:8]` 直接按 ≥ 比较（来源：src/rtl/process/proc_binary.v:23）⇒ 写 0 恒白、写 255 只有满亮度点才白。复位默认 `8'd80`（来源：src/rtl/process/effect_ctrl.v:44），PS 影子同值（来源：src/ps/main.c:171）。

**3×3 窗口 / 边界**：不适用（点运算，模块体内没有存储器，来源：src/rtl/process/proc_binary.v:16-25）。
**几拍**：1 拍，`de_out <= de_in;` 与 `dout   <= bypass ? din : bw;`（来源：src/rtl/process/proc_binary.v:32-33）。
**bypass**：`.bypass(~w_bin)` 与 `.pol(bin_pol)` 在同一个例化语句里进（来源：src/rtl/process/proc_pipeline.v:141）。

**资源**：`u_bin` Total LUTs 120、FFs 17、DSP 0（来源：build/util_hier_probe.rpt:68）。

| 这一站的输入/输出格式 | |
| --- | --- |
| 输入 | 16 bit RGB565 + `de` + 8 bit `threshold` + 1 bit `pol`（来源：src/rtl/process/proc_binary.v:9-12） |
| 输出 | **只有两个码点**：`16'hFFFF` 与 `16'h0000`（来源：src/rtl/process/proc_binary.v:25），晚 1 拍；`de` 逐拍原样透传 |
| 出错时屏上表现 | 出现第三个码点就是这一级漏了：`T8 二值化输出只有 16'hFFFF/16'h0000`（来源：sim/tb_v86_pipe_sel.v:10 的判据条目）。`pol` 接反的屏上形状 = 黑白整片互换，本卷未找到把它单独钉死的台架条目（未证） |

## 9 级 5：形态学腐蚀 / 膨胀（以及"开/闭为什么不在这里"）

**算法定义**。掩码先由同一条亮度比较生成：`wire        bin = (y16[15:8] >= threshold);`（来源：src/rtl/process/proc_morph.v:34，式子来源：src/rtl/process/proc_morph.v:33）。九点归约两条：`wire all1 = m00 & m01 & m02 & m10 & m11 & m12 & m20 & m21 & m22;`（来源：src/rtl/process/proc_morph.v:115）与 `wire any1 = m00 | m01 | m02 | m10 | m11 | m12 | m20 | m21 | m22;`（来源：src/rtl/process/proc_morph.v:116），选择 `wire res = (mode == 2'd1) ? all1 : any1;`（来源：src/rtl/process/proc_morph.v:119）。定义依据写在文件头："邻域内全 1 才 1 / 有 1 就 1，本来就是对面具图的操作（放在灰度图上做 min/max 也能写，但那不是形态学，是另一种局部对比度）"（来源：src/rtl/process/proc_morph.v:2-3）。

**开运算 / 闭运算：这一级明确不做**。`mode` 端口是 2 bit，注释给出编码 `0/3 旁路  1 腐蚀  2 膨胀`（来源：src/rtl/process/proc_morph.v:13），而 `wire by = (mode == 2'd0) || (mode == 2'd3);`（来源：src/rtl/process/proc_morph.v:24）把 3 与 0 合成同一条旁路。理由写在紧邻的三行里：开/闭要**两遍** 3×3 窗口（先腐蚀再膨胀，或反之），这里只有一遍，做不出来，也不许偷偷当成其中一种，所以显式当旁路，代价写在注释里而不是藏在 mux 里（来源：src/rtl/process/proc_morph.v:22-23）。链侧对应的是"两位同时为 1 时两个都不做"（来源：src/rtl/process/proc_pipeline.v:59-60）。台架这条判据是 `T10 mode3 与 mode0 逐位相同（开/闭运算要两遍窗口，这里显式不吃）`（来源：sim/tb_v84_morph.v:301）。

**3×3 窗口怎么组织**（这一级是三块存储器，容量与前几级不同）：

| 存储 | 声明 | 元素位宽 | 只为什么存在 |
| --- | --- | --- | --- |
| 上上行掩码 | `(* ram_style = "distributed" *) reg mb0 [0:H_ACTIVE-1];`（来源：src/rtl/process/proc_morph.v:40） | 1 bit | 腐蚀/膨胀 |
| 上一行掩码 | 同形状的 `mb1`（来源：src/rtl/process/proc_morph.v:41） | 1 bit | 腐蚀/膨胀 |
| 上一行原色 | `(* ram_style = "distributed" *) reg [15:0] mc1 [0:H_ACTIVE-1];`（来源：src/rtl/process/proc_morph.v:44） | 16 bit | **只为旁路能还原原色**（来源：src/rtl/process/proc_morph.v:7） |

掩码只存 1 bit/像素，亮度判定在输入处做一次，所以两条掩码行缓存 = 512 bit × 2（按参数默认 `H_ACTIVE = 512` 算，来源：src/rtl/process/proc_morph.v:5-9；顶层实参是 1024，来源：src/rtl/top/pl_video_top.v:800，因此上板容量是这段注释的两倍，来源：src/rtl/process/proc_pipeline.v:11）。写侧三行：`mb0[x_in] <= mb1[x_in]; mb1[x_in] <= bin; mc1[x_in] <= din;`（来源：src/rtl/process/proc_morph.v:48-50）。窗口侧存的是 9 个 1 bit 掩码 + 5 个 16 bit 原色：`reg k00, k01, k02, k10, k11, k12, k20, k21, k22;`（来源：src/rtl/process/proc_morph.v:60）与 `reg [15:0] p12, p11;` / `reg [15:0] c20, c21, c22;`（来源：src/rtl/process/proc_morph.v:61-62）。

**两个写法陷阱**（都是综合级会静默出事的）：
1. 存储器必须写成"每元素一格"的 `reg mb0 [0:H_ACTIVE-1]`，写成一根 1024 位向量的话综合器推断不出 RAM、报 `Synth 8-7186 ... using registers`，两条掩码行缓存变成 2×H_ACTIVE 个触发器、两个异步读口各变成一棵 1024:1 的 LUT 树（来源：src/rtl/process/proc_morph.v:36-39）。
2. `mc1` 的读是组合读出，BRAM 做不到，所以原来写 `ram_style="block"` 只会被判 `Synth 8-6849 infeasible` 再自己退回 LUTRAM（来源：src/rtl/process/proc_morph.v:42-43）。

**边界像素**。与前两级同一套四旗标 + clamp-to-edge（来源：src/rtl/process/proc_morph.v:104-113）。复制的动机写得很具体：腐蚀在左沿不会因为"外面算 0"而被啃掉一圈，膨胀也不会因为行缓存里是上一帧的尾巴而凭空鼓一圈——这两种都是"条带"（来源：src/rtl/process/proc_morph.v:102-103）。旧写法那一根合并旗标 `border_r` 同时错两处（第 0 列被旁路、真正的末列没人管），文件里把它连同"中心行 = 输入行 − 1"一起记为"左边与上边那两条带"的成因（来源：src/rtl/process/proc_morph.v:75-78）。

**输出与旁路**。`dout   <= by ? (stale_row ? c21 : p11) : (res ? 16'hFFFF : 16'h0000);`（来源：src/rtl/process/proc_morph.v:142）——生效时输出同样只有两个码点（与级 4 一致，来源：src/rtl/process/proc_binary.v:25），旁路时走中心抽头的原色。
**几拍**：3 拍（来源：src/rtl/process/proc_morph.v:137-139）。
**资源**：`u_morph` Total LUTs 151、FFs 126、DSP 0（来源：build/util_hier_probe.rpt:71）。

**这一级的语义台架**（本卷只列它主张什么，不列红绿）：

| 判据 | 主张 | 行 |
| --- | --- | --- |
| T1 | morph 的旁路与 blur 的旁路逐位相同 | 来源：sim/tb_v84_morph.v:203 |
| T3/T4 | 腐蚀：方块中心仍白、边角被啃；孤立点连同邻域一起没 | 来源：sim/tb_v84_morph.v:257 与 :259 |
| T5 | 膨胀：孤立点长成 3×3（`dot_lit == 9`） | 来源：sim/tb_v84_morph.v:261 |
| T6 | 同一位置两者相反（没接反） | 来源：sim/tb_v84_morph.v:263 |
| T7/T8 | 逐像素等于定义（邻域全 1 / 邻域有 1） | 来源：sim/tb_v84_morph.v:274 与 :281 |
| T9 | 腐蚀把 8×6 缩成 6×4（`cnt == 24`） | 来源：sim/tb_v84_morph.v:289 |
| T11 | 全黑输入膨胀后仍全黑 | 来源：sim/tb_v84_morph.v:311 |
| T12 | 两帧脉冲数都是 W×H（延迟固定，不随 mode 变） | 来源：sim/tb_v84_morph.v:314 |

| 这一站的输入/输出格式 | |
| --- | --- |
| 输入 | 级 4 出来的 16 bit（多半只有两个码点）+ `de` + 坐标抽头 `xd[12]`/`yd[12]`（来源：src/rtl/process/proc_pipeline.v:98/148）+ 2 bit `mode` + 8 bit `threshold`（来源：src/rtl/process/proc_pipeline.v:147） |
| 输出 | 16 bit，生效时仍是两个码点（来源：src/rtl/process/proc_morph.v:142），晚 3 拍 |
| 出错时屏上表现 | 腐蚀/膨胀接反：`T6 同一位置 (x=7,y=8) 两者相反：腐蚀黑 / 膨胀白（没接反）`（来源：sim/tb_v84_morph.v:263）；开关那一级时画面跳一行：T1 的差分（来源：sim/tb_v84_morph.v:203）；屏上 `Pipe:` 第五位与画面不符（两位都置 1 却画 3）由 OSD 的投影规则防住（来源：src/rtl/video/osd_overlay.v:139-142） |

---

## 10 四个窗口级共用的一台机器：行尾多跳、读地址、四条旗标

blur / sharpen / sobel / morph 四级的"邻域的"部分写法逐字同形（来源：src/rtl/process/proc_sharpen.v:48-50 明写"逐字同形是 S4/tb_v92 能差分验证的前提"）。正本在 `proc_box_blur.v`，另外三处指回来（来源：src/rtl/process/proc_box_blur.v:55）。

### 10.1 行尾为什么要多跳一拍，以及为什么只能"数连续有效像素"

症状与机理：中心抽头是 `p11 <= p12 <= 行缓存读` 这么一条链，**当拍读到的那一格要再跳一拍才成为中心**，而移位整个被 `de_in` 钉住 ⇒ 行内最后一个有效像素读完、下一拍就是消隐，那一跳永远不来 ⇒ 每行少发一个样本，而输出流仍按 `de_out` 数够格子 ⇒ 最后一格只能重复前一列（来源：src/rtl/process/proc_box_blur.v:25-28）。台架把这条量成"旁路下每一列都必须落在同一个偏移上，含每行最后一列"，读数形如 `first col=31 dc=-1`（来源：src/rtl/process/proc_box_blur.v:26）。

补跳的判据三行：

```verilog
wire owed     = (run == H_ACTIVE[11:0]); // 本行正好 H_ACTIVE 个有效像素 = 刚吃完的是末列
wire line_end = owed && de_d1 && !de_in; // 只有一拍：就是现在欠那一跳
wire shift_w  = de_in || line_end;
```
（来源：src/rtl/process/proc_box_blur.v:36-38）

`run` 是"本行已连续吃进的有效像素数"，`de` 一断就清而不是等第二拍——因为行间隙只有一拍的激励里晚一拍清等于永远不清；而同一拍里非阻塞更新的旧值仍然看得见，所以 `de` 落下那一拍 `run` 正好是本行的宽度（来源：src/rtl/process/proc_box_blur.v:31-35）。**为什么不用 `>=`、不用 `x_in` 标签**：`de_d1 && !de_in` 在一拍一像素的激励下每个像素后面都算行尾；再加 `x_in == H_ACTIVE-1` 那一版模块级全绿、顶层却一次都没武装（顶层的 `x_d[3]` 与 `de_d[3]` 不同级）⇒ 依赖标签的判据不可用（来源：src/rtl/process/proc_box_blur.v:29-30）。同一条纪律在锐化那一级留下了实测红：拿 `de_d1 && !de_in` 当行尾会让 `tb_rotate_window` 那种一拍一像素的激励把模糊整个坏掉（来源：src/rtl/process/proc_sharpen.v:33-34）。

多跳那一拍上**当前行那一路也必须跳**，且跳的时候重复末列而不是采总线值：`p20<=p21; p21<=p22; p22<=de_in ? din : p22;`（来源：src/rtl/process/proc_box_blur.v:142）。不这么写的后果由台架量出来：末列那一格的"下面一行"还停在倒数第二列 ⇒ 窗口整体错位，`tb_edge_rim` R4 实测 `got=8c51` 而 clamp=`b596`、raw=`d69a`、下一行折回=`83f0`，四个候选全不是（来源：src/rtl/process/proc_box_blur.v:137-141）。

### 10.2 读地址钉末列

```verilog
wire [11:0] x_rd = (x_in >= H_ACTIVE[11:0]) ? (H_ACTIVE[11:0] - 12'd1) : x_in;
```
（来源：src/rtl/process/proc_box_blur.v:42）

多跳那一拍 `x_in` 已经走到 porch（顶层一屏 1344 计数，来源：src/rtl/video/video_timing_1024x600.v:3），而行缓存只有 `H_ACTIVE` 深：直接拿它当读地址，仿真越界给 X、硬件按位截断读到别的列（来源：src/rtl/process/proc_box_blur.v:39-41）。这一钉同时充当 clamp-to-edge，让这一拍移进窗口的两个邻居与末列的中心一格不差（来源：src/rtl/process/proc_box_blur.v:41）。同一式子在另外三级各写一遍：来源：src/rtl/process/proc_sharpen.v:43、src/rtl/process/proc_sobel.v:48、src/rtl/process/proc_morph.v:54。

### 10.3 四条旗标：`no_left` / `no_right` / `no_above` / `stale_row`

一台 3 深的移位链，只在 `shift_w` 那一拍走：

| 旗标 | 武装条件 | 落点 |
| --- | --- | --- |
| `no_left` | `no_left_r  [0] <= ~de_in;`（来源：src/rtl/process/proc_box_blur.v:73） | 行尾补跳那一拍 = 下一行第 0 槽 |
| `no_right` | `no_right_r [0] <= de_in && (x_in == H_ACTIVE[11:0] - 12'd1);`（来源：src/rtl/process/proc_box_blur.v:74） | 末列那一拍武装 ⇒ 落进行尾多跳那一格的中心 |
| `no_above` | `de_in && (y_in == 12'd1) && row_first`（来源：src/rtl/process/proc_box_blur.v:75） | 中心行 0，上面那一行不存在 |
| `stale_row` | `de_in && (y_in == 12'd0)`（来源：src/rtl/process/proc_box_blur.v:76） | 中心行 −1：整行都是旧的 |

消费的是第 3 位：`wire no_left = no_left_r[2];`（来源：src/rtl/process/proc_box_blur.v:82-85）。三条"由台架量、不由推"的事实写在正本段首：① 拍 k 武装的旗标落在**槽位 k+1** ⇒ 旧写法 `x_in==0` 管的是第 1 列、真正的第 0 列没人管；② 行尾补跳那一拍落在**下一行的第 0 槽**，旧代码在这里塞 `1'b1` ⇒ 第 0 列被旁路成原图直出（实测 `got==raw`）⇒ **左边一条带**；③ 中心行 = 输入行 − 1（mode=1 实测行平移 +1）⇒ 每帧第一个输出槽吃的中心是上一帧的末行 ⇒ **上边缘那条带**：不是位置错、不是没裁黑，是内容陈旧（来源：src/rtl/process/proc_box_blur.v:54-59）。

`row_first` 是 ×2 栅格逼出来的：`wire row_first = (y_in != y_row_d);`（来源：src/rtl/process/proc_box_blur.v:64），`y_row_d` 在本行行尾那一跳锁存 `y_in`、复位值是 `12'h0FFF`（来源：src/rtl/process/proc_box_blur.v:61-63）。注释口径是"只有源行的**第一个显示行**才可能缺上一行"（来源：src/rtl/process/proc_box_blur.v:64-65）——因为两个显示行共享一个源行。

**复位只能写在一个块里**：这四根旗标的复位分支就在 `else if (shift_w)` 那个块的同一进程里（来源：src/rtl/process/proc_box_blur.v:67-69），注释写明"写进主 always 的复位分支就是两个驱动源 ⇒ 综合报 `Synth 8-6859/8-6858 multi-driven net` 并把逻辑那一侧**忽略**（恒 0），而仿真看不出来（xsim 按进程后写覆盖）"（来源：src/rtl/process/proc_box_blur.v:66）。

| 这一站的输入/输出格式 | |
| --- | --- |
| 输入 | 每级各自那一拍的 `x_in/y_in`（12 bit）+ `de_in` + 16 bit 像素（来源：src/rtl/process/proc_box_blur.v:12-16） |
| 输出 | 同一格式、晚 3 拍；此外内部多出一套与内容同拍的边界旗标（来源：src/rtl/process/proc_box_blur.v:82-85） |
| 出错时屏上表现 | 旗标链与中心链不同拍 ⇒ 边界位与内容差一格（来源：src/rtl/process/proc_box_blur.v:71-72）；复位被双驱动 ⇒ 位流里恒 0、仿真看不出来，屏上表现是"边界条带在板上一直在而台架全绿"（同处来源：src/rtl/process/proc_box_blur.v:66） |

---

## 11 固定延迟：15 拍、−4 行，以及为什么"恒定"本身就是约束

### 11.1 声明与算式

```verilog
parameter integer LATENCY = 15,     // 声明的是本模块的固有延迟，**不许由外部覆盖**
```
（来源：src/rtl/process/proc_pipeline.v:22）

算式在同一个文件的注释里逐拍记：`灰度1+反色1+模糊3+锐化3+Sobel3+阈值1+形态学3=15`（来源：src/rtl/process/proc_pipeline.v:18）。本卷把加法摊开核对：1 + 1 + 3 + 3 + 3 + 1 + 3 = 15，与声明的 15 相等（各项来源：src/rtl/process/proc_gray.v:31、src/rtl/process/proc_invert.v:24、src/rtl/process/proc_box_blur.v:144-146、src/rtl/process/proc_sharpen.v:124-126、src/rtl/process/proc_sobel.v:142-144、src/rtl/process/proc_binary.v:32、src/rtl/process/proc_morph.v:137-139）。两条容易被忽略的口径：窗口级是三拍不是两拍（来源：src/rtl/process/proc_pipeline.v:19-20）；同级两个选项是**串联**的，所以两个都占自己的拍数（来源：src/rtl/process/proc_pipeline.v:17-18）——级 2 只开锐化时那 3 拍模糊照走，只是数据在模糊里走旁路支（来源：src/rtl/process/proc_box_blur.v:147-148）。

级 0 的 gamma 不在这串账里：它是分布式 RAM 的组合读出、不占拍（来源：src/rtl/process/proc_pipeline.v:20-21），谁改成寄存读出 `LATENCY` 必须同时改成 16（来源：src/rtl/process/proc_pipeline.v:21）。

内容偏移是另一个常数：`parameter integer OFF_LINES = 4`（来源：src/rtl/process/proc_pipeline.v:27），因果是"行缓存式 3×3 滤波在收到第 y 行时才算得出第 y−1 行的窗口，因果性决定它必然滞后一行"，四个窗口级各贡献 −1 行、点运算级不贡献 ⇒ 整链固定 −4 行、0 列（来源：src/rtl/process/proc_pipeline.v:23-26）。这个数从模块里输出给顶层用：`assign off_rows = OFF_LINES[7:0];`（来源：src/rtl/process/proc_pipeline.v:48）。

### 11.2 自校验：三层，一层比一层贵

| 层 | 判据 | 红的时候说明什么 |
| --- | --- | --- |
| 参数层 | `T3 LATENCY 参数与手算的逐级和一致`，`up.LATENCY == LAT_EXPECT`，`LAT_EXPECT = 15`（来源：sim/tb_v86_pipe_sel.v:167 与 :27） | RTL 改了拍数没改声明 |
| 实测层 | `T2 实测 de 延迟 == 模块声明的 LATENCY`（来源：sim/tb_v86_pipe_sel.v:164），实测式 `if (de_o && first_lat < 0) first_lat = cyc - t_in;`（来源：sim/tb_v86_pipe_sel.v:78） | 声明与行为脱节；失败行还会并排打三个数（来源：sim/tb_v86_pipe_sel.v:166） |
| 档位层 | `T5 六种组合下延迟都还是 15 拍`，跑 `sel = 9'h001/004/008/010/020/080`（来源：sim/tb_v86_pipe_sel.v:172-178） | "换效果就换延迟"——顶层的 skid 是按常数定的，一换档就错位 |

顶层侧还有一条**结构**保证：所有跟"内容站在第几拍"有关的地方都只取 `u_pipe.LATENCY` 而不是自己写数——`localparam MIX_D = 3 + 1 + 1 + u_pipe.LATENCY;`（来源：src/rtl/top/pl_video_top.v:354）、`localparam PROC_LAT = u_pipe.LATENCY;` 与 `localparam LEFT_TAIL = PROC_LAT;`（来源：src/rtl/top/pl_video_top.v:816-817）、`localparam integer RAW_LINES = u_pipe.OFF_LINES;`（来源：src/rtl/top/pl_video_top.v:781）、`localparam integer SEAM_TAPS = MIX_D + 1 - 3;`（来源：src/rtl/top/pl_video_top.v:902）。

### 11.3 为什么"延迟恒定"是设计约束而不是实现风格

一句话理由写在顶层：以前这里是字面量 7，于是"链上加一级"必须同时记得改它——忘了**不是编译错**，而是左窗与右窗错开 N 个像素（来源：src/rtl/top/pl_video_top.v:813-815）。左窗那一路的补偿长度直接取链子的值：`orig_skid[0] <= raw_ring[15:0];` 之后串 `LEFT_TAIL` 拍（来源：src/rtl/top/pl_video_top.v:840-845），抽头 `wire [15:0] orig_disp = orig_skid[LEFT_TAIL-1];`（来源：src/rtl/top/pl_video_top.v:848）。两个抽头必须**同深**这件事本身也是量出来的：原图那一路 = 行环 1 拍读出 + `orig_skid` 的 `PROC_LAT` 拍 = `PROC_LAT+1`，而链子自己只有 `PROC_LAT` ⇒ 处理抽头比原图早一整拍 = 混色级早一整列（来源：src/rtl/top/pl_video_top.v:819-824），补这一拍的就是那个单独寄存器 `pipe_dout_q`（来源：src/rtl/top/pl_video_top.v:825-829）。

对同帧左右对照的含义：屏上任何一格里，"左边那份"与"右边那份"必须是**同一次光栅扫描的同一格**，否则缝两侧会各画各的行。因此延迟一旦随档位变化，缝就成了一条内容错行的线；台架侧对应的两条正是 `T12 两帧脉冲数都是 W*H（延迟固定，不随 mode 变）`（来源：sim/tb_v84_morph.v:314）与 `T7 de_out 脉冲数等于像素数（延迟与 bypass 无关）`（来源：sim/tb_v85_sharpen.v:178）。

### 11.4 −4 行怎么在顶层补掉：把地址提前，不是把数据提前

帧缓存在 DDR 侧是随机地址的，所以补偿是改地址：提前量必须加在 mapper 的**显示行输入**上而不是输出的源行上——链子的滞后发生在显示栅格上，缩放/旋转之后"源行差 4"不等于"显示行差 4"（来源：src/rtl/process/proc_pipeline.v:24-26 与 src/rtl/top/pl_video_top.v:244-249）。实现三行：

```verilog
wire [12:0] y_right_adv = {1'b0, y} + {5'b0, pipe_off_rows} + BILIN_ROWS[12:0];
wire [11:0] y_req_row = y_right_adv[11:0] >> 1;
wire [11:0] cy_r = (y_req_row >= IMG_H) ? (y_req_row - IMG_H) : y_req_row;
```
（来源：src/rtl/top/pl_video_top.v:276-277 与 :284）

`pipe_off_rows` 就是链子自己报出来的 `OFF_LINES`（来源：src/rtl/top/pl_video_top.v:808），`BILIN_ROWS = 2` 是双线性读口那对乒乓缓冲的 2 行（来源：src/rtl/top/pl_video_top.v:250）。本卷代入满量程核对"减一次就够"：`y` 最大 599（有效行 600，来源：src/rtl/video/video_timing_1024x600.v:18），599 + 4 + 2 = 605，右移 1 得 302，而 `IMG_H = 300`（来源：src/rtl/top/pl_video_top.v:10）⇒ 302 − 300 = 2，减一次确实够，不需要除法器/取模（这一条与该注释的说法一致，来源：src/rtl/top/pl_video_top.v:283）。`BILIN_ROWS` 必须**偶数**，因为 `row0 = ~y[0]` 定成对奇偶，奇数会让一对分属两个源行 ⇒ A/B 错行（来源：src/rtl/top/pl_video_top.v:249）。

### 11.5 坐标也得跟着级走：12 级自由运行延迟线

四个窗口级不能共用顶层那一份 `x_in/y_in`：第 k 级拿到像素那一刻，顶层 `x_in` 已经在说"第 (n+累积延迟) 个像素"，而行缓存按列号写 ⇒ 写进去的列号与数据差着累积延迟，且消隐越长差得越多（来源：src/rtl/process/proc_pipeline.v:71-73）。修法是给坐标装一条与 `de` 同节奏的自由运行延迟线，抽头号 = 该级 `de_in` 之前累积的拍数：**2→blur、5→sharp、8→sobel、12→morph**（来源：src/rtl/process/proc_pipeline.v:74，落地为 :95-98 那四行 `wire`）。

链的声明与代价：`reg [11:0] xd [1:12];`（来源：src/rtl/process/proc_pipeline.v:82），同形状 `yd`（来源：src/rtl/process/proc_pipeline.v:83）；该行注释自算 2×12×12 = **288 个触发器**（来源：src/rtl/process/proc_pipeline.v:82）。本卷核对这个式子：两条链 × 12 跳 × 12 bit = 288 个 DFF；实现报里 `(u_pipe)` 本体那一行给的是 FFs 240、SRLs 13（来源：build/util_hier_probe.rpt:67）。**288 与 240 之间的差额本卷不解释**——这一层的分解不在报告里（同一处读数来源：build/util_hier_probe.rpt:67）。

口径"`xd[k]` 必须恰好 k 拍"是怎么红过一次：第一跳曾写成 `xd[0] <= x_in`，于是 `xd[k]` 其实是 k+1 拍 ⇒ 四个窗口级的列标签比它自己的数据晚一整拍，后果两条都在硬件上——每行最后一个有效拍 `x_in` 只到 `H_ACTIVE-2` ⇒ 槽位 `H_ACTIVE-1` 永远没人写（上电读 0）；每行第一个有效拍 `x_in` 还停在消隐末尾（顶层一屏数到 1343）⇒ 写地址越界，xsim 丢掉这一笔、硬件按地址位截断（来源：src/rtl/process/proc_pipeline.v:75-80）。本卷按该注释复算截断：1343 mod 1024 = 319 ⇒ 每行往 319 号槽写进消隐期的 0x0000，读回它的是真实列 320 那一拍 ⇒ 板上一根钉死在显示列 320（源列 160，由 ×2 关系来源：src/rtl/top/pl_video_top.v:242 得）的 1 像素纯黑竖线（形状出处：src/rtl/process/proc_pipeline.v:80）。判据是 `C10d every line-cache slot was written at least once`（来源：sim/tb_v103_pipe_bypass.v:354）与 `C10f no window stage writes outside its own line cache`（来源：sim/tb_v103_pipe_bypass.v:361），改前两条都红（来源：src/rtl/process/proc_pipeline.v:81）。

| 这一站的输入/输出格式 | |
| --- | --- |
| 输入 | 16 bit + `de`/`hs`/`vs` + 12 bit `x`/12 bit `y`（顶层第 3 抽头，来源：src/rtl/top/pl_video_top.v:805-807），一行 1024 个有效拍（来源：src/rtl/top/pl_video_top.v:800） |
| 输出 | 同格式，恒晚 15 拍；内容恒滞后 4 个**喂进来的流的**行（来源：src/rtl/process/proc_pipeline.v:4、:22、:27），并由 `off_rows` 把这个数交给顶层（来源：src/rtl/top/pl_video_top.v:808） |
| 出错时屏上表现 | 延迟数与顶层不一致 ⇒ 左右两窗错开 N 个像素（来源：src/rtl/top/pl_video_top.v:813-815）；坐标抽头错一拍 ⇒ 一根钉死的纯黑竖列（来源：src/rtl/process/proc_pipeline.v:75-80）；两条都有台架（来源：sim/tb_v86_pipe_sel.v:164、sim/tb_v103_pipe_bypass.v:354） |

---

## 12 同帧左右对照：混合条件、百分比数学、蓝线、以及"为什么缝是竖直的"

### 12.1 `split_display` 的逐像素混合：五条组合式 + 一级寄存器

这一级收到的已经是两份对齐好的 16 bit 流：`orig_pix`（原图抽头）与 `proc_pix`（链子输出再打一拍 `pipe_dout_q`，来源：src/rtl/top/pl_video_top.v:825-829 与 :923）。混合本身没有算术，只有选择：

```verilog
wire        left = seam_in_src ? ~src_orig : (x_sel < seam);
wire        oob  = left ? oob_l : oob_r;
wire        take_orig = seam_in_src ? src_orig : (raw_left ? left : ~left);
wire [15:0] sel  = oob ? 16'h0000 : (take_orig ? orig_pix : proc_pix);
wire        sep  = marker && (seam_in_src ? src_mark : ((x_sel == (seam - 12'd1)) || (x_sel == seam)));
```
（来源：src/rtl/video/split_display.v:43、:46、:47、:48、:52-53）

逐条读：

| 式子 | 说的是什么 | 注意 |
| --- | --- | --- |
| `left`（来源：src/rtl/video/split_display.v:43） | 这一格在缝的哪一边。两种坐标空间：显示列比 `x_sel < seam`，图像列直接采用源头算好的 `~src_orig` | 缝位是**输入**而不是写死的半屏参数（来源：src/rtl/video/split_display.v:16-17） |
| `oob`（来源：src/rtl/video/split_display.v:46） | 选哪一路的"画面外" | 顶层把同一个 `oob_out` 同时喂 `oob_l` 与 `oob_r`（来源：src/rtl/top/pl_video_top.v:924），因为单流之后两个抽头共享同一份源坐标（来源：src/rtl/video/split_display.v:44-45） |
| `take_orig`（来源：src/rtl/video/split_display.v:47） | 这一格给原图还是处理图。`raw_left` 决定"缝左边是不是原图"，`swap` 只翻这一位（来源：src/rtl/video/split_display.v:19） | 图像域路径不在这里再过一遍 `raw_left`，过两遍就是反的（来源：src/rtl/video/split_display.v:45） |
| `sel`（来源：src/rtl/video/split_display.v:48） | 越界强制黑 `16'h0000`，否则二选一 | 这是**唯一**的涂黑点 |
| `sep`（来源：src/rtl/video/split_display.v:52-53） | 蓝线：`marker` 为真且落在 `seam-1` 或 `seam` 这两列 ⇒ 宽 2 个**显示列** | `follow` 时改用 `src_mark`，那是 2 个**图像列**（来源：src/rtl/video/seam_src.v:26） |

拆位与上色：`wire [4:0]  r5   = sel[15:11];`（来源：src/rtl/video/split_display.v:49），随后一路寄存器输出——`if (sep && de)` 时钉成 `r <= 8'h40; g <= 8'h40; b <= 8'hFF;`（来源：src/rtl/video/split_display.v:63-64），否则位复制展宽 `r <= {r5, r5[4:2]};`（来源：src/rtl/video/split_display.v:66-68）。`de/hs/vs` 各打一拍同拍出来（来源：src/rtl/video/split_display.v:60-62）⇒ 本级是**1 拍**延迟。

条件里为什么必须带 `&& de`：消隐期没有新像素，若还画线就会把上一行的末格涂蓝；台架 S5 主张的正是"`de=0` 时缝不新画标记线、保留上一个像素"（来源：sim/tb_v97_seam_scan.v:178）。

**判定用的坐标必须与内容同级**：`x_sel` 这个口的注释把账算全了——以前直接用 `x` 判左右、也用它画那条 2 px 线，而顶层的 `x` 是第 11 级标签、两个像素抽头却是第 20 级的内容（3 拍打地址 + 1 拍读地址寄存 + 1 拍 BRAM + `u_pipe.LATENCY` = 15），判定比内容旧 **MIX_D − 11 = 20 − 11 = 9 列**（本卷代入来源：src/rtl/top/pl_video_top.v:354），后果是缝左边约 9 列里"标签说左窗、内容其实是右窗那一路被强制清 0"⇒ 一条近黑的竖带（来源：src/rtl/video/split_display.v:9-14）。顶层因此把整束标签提到 `MIX_D`：`.x(x_d[MIX_D]), .y(y_d[MIX_D]), .de(de_d[MIX_D])` 与 `.x_sel(x_d[MIX_D])`（来源：src/rtl/top/pl_video_top.v:919-920）。

### 12.2 三个模式：auto / follow / swap 各自管什么

| 位 | PL 落点 | 管的事 | 不管的事 |
| --- | --- | --- | --- |
| `auto_en`（`gp[10]`） | `.auto_en(gp[10])`（来源：src/rtl/top/pl_video_top.v:888） | 缝位是三角波自己扫出来的还是手工给的（来源：src/rtl/video/split_ctrl.v:73-89） | 不改坐标空间、不改左右归属 |
| `follow`（`gp[11]`） | `.follow(gp[11])`（来源：src/rtl/top/pl_video_top.v:888）+ `.seam_in_src(gp[11])`（来源：src/rtl/top/pl_video_top.v:922） | 同时管两件事：扫描坐标系的宽度（来源：src/rtl/video/split_ctrl.v:33）与"线长在画面里"这条判据空间（来源：src/rtl/top/pl_video_top.v:897-898） | — |
| `swap`（`gp[12]`） | `.swap(gp[12])`（来源：src/rtl/top/pl_video_top.v:889）→ `raw_on_left = ~swap`（来源：src/rtl/video/split_ctrl.v:105） | 只换内容归属：原图在左还是在右 | **不换缝位**（来源：src/rtl/video/split_display.v:19；台架 `T2a swap=1 时 split_eff / shown_pct 一个像素都不动` 来源：sim/tb_v93_split_ctrl.v:158） |

### 12.3 `split_ctrl` 的百分比数学

**宽度选择不是除法**：`wire [16:0] W = follow ? SRC_W17 : DISP_W17;`（来源：src/rtl/video/split_ctrl.v:33），两个分支都是 elaboration 常数，所以综合出来是 2:1 选线，既不是除法器也不是桶形移位器（来源：src/rtl/video/split_ctrl.v:27-28）。实参来自顶层：`.DISP_W(2*PANE_W)` 与 `.SRC_W(IMG_W)`（来源：src/rtl/top/pl_video_top.v:885）⇒ 代入 `PANE_W = 512`（来源：src/rtl/top/pl_video_top.v:11）得 1024，`IMG_W = 512`（来源：src/rtl/top/pl_video_top.v:9）得 512。

**端点用 1/16 宽度作单位**：`lo16`/`hi16` 各 5 bit、取值 0..16（来源：src/rtl/video/split_ctrl.v:20-21），先夹 `wire [4:0] lo_c = (lo16 > 5'd16) ? 5'd16 : lo16;`（来源：src/rtl/video/split_ctrl.v:37-38），再乘移 `wire [20:0] lo_full = {16'd0, lo_c} * W;` 与 `wire [16:0] lo_px = lo_full[20:4];`（来源：src/rtl/video/split_ctrl.v:39-42）——换算成像素就是 `(u*W)>>4`，写成一次乘一次接线（来源：src/rtl/video/split_ctrl.v:35-36）。本卷代入构建默认值 `SPLIT_LO16 = 5'd2`、`SPLIT_HI16 = 5'd14`（来源：src/rtl/top/pl_video_top.v:20-21）与 W=1024：2×1024 = 2048 >> 4 = **128**，14×1024 = 14336 >> 4 = **896** ⇒ 自动扫描在屏上扫的是第 128 到第 896 列。

**`hi < lo` 是合法输入**：`split range 80 20` 就会这样，所以这里把两个端点折成 [min,max] 而不是拒收（来源：src/rtl/video/split_ctrl.v:43-47），台架 `T11 range 写成 80 20 时：仍夹在 [256,768]`（来源：sim/tb_v93_split_ctrl.v:249）。

**扫描计数按 `de` 走**：整个三角波状态机只在 `else if (de)` 分支里动（来源：src/rtl/video/split_ctrl.v:72），理由是"任何拿每拍计数器与第 0 列/末列比的判据，换一种消隐宽度或占空比就会挡住不同的列 ⇒ 台架与板子给出两个不一样的答案"（来源：src/rtl/video/split_ctrl.v:64-66）。一步的像素数是 `2^TICK_BITS`（来源：src/rtl/video/split_ctrl.v:11 的参数注释）× `speed`：`wire [12:0] step = {9'd0, speed};`（来源：src/rtl/video/split_ctrl.v:57）而 `tcnt` 数到 `{TICK_BITS{1'b1}}` 才走一步（来源：src/rtl/video/split_ctrl.v:77）；顶层传 `.TICK_BITS(16)`（来源：src/rtl/top/pl_video_top.v:885）、`SPLIT_SPEED = 4'd1`（来源：src/rtl/top/pl_video_top.v:19）⇒ 每 2^16 = 65536 个有效像素走 1 列，而一行有 1024 个有效拍（来源：src/rtl/top/pl_video_top.v:800）⇒ 65536/1024 = **64 个显示行一步**（本卷除法，两操作数来源同上）；台架 `T12 默认档（TICK_BITS=16）一步恰好 65536 个有效像素 = 64 行`（来源：sim/tb_v93_split_ctrl.v:271）。`speed = 0` 时那一拍什么都不加 ⇒ 钉住不动（来源：src/rtl/video/split_ctrl.v:79，判据 `T9  speed=0 ⇒ 扫描值钉住不动` 来源：sim/tb_v93_split_ctrl.v:233）。

**两级夹紧**：手工位置 `raw_sel = auto_en ? {4'd0, swp} : {5'd0, pos_px};` 先夹到 `[0, W]` 而不是 `[0, W−1]`，因为"缝推到最右"= 整屏都是缝左侧那一半（来源：src/rtl/video/split_ctrl.v:92-99）；`eff` 再夹一次到 `[lo,hi]`，这一道是给"中途改 range"用的（来源：src/rtl/video/split_ctrl.v:100-103）。出口 `assign split_eff = {1'b0, eff[11:0]};`（来源：src/rtl/video/split_ctrl.v:104）把 13 bit 的内部值截成 12 bit 输出。

**百分比链**：

```verilog
localparam [13:0] PCT_DISP = (100 * 16384) / DISP_W;
localparam [13:0] PCT_SRC  = (100 * 16384) / SRC_W;
wire [13:0] pct_c     = follow ? PCT_SRC : PCT_DISP;
wire [26:0] prod      = eff * pct_c;
wire [7:0]  pct       = prod >> 14;
```
（来源：src/rtl/video/split_ctrl.v:112-117）

`PCT = 100·16384/W` 是 elaboration 常数，两个宽度都是 2 的幂所以精确：代入 1024 得 100×16384/1024 = **1600**，代入 512 得 **3200**（来源：src/rtl/video/split_ctrl.v:109-113）。先选常数再乘，只留一个乘子，两枝逐位等价（来源：src/rtl/video/split_ctrl.v:114）。`prod` 给足 27 bit 是因为"否则乘法在 14 bit 里截断"（来源：src/rtl/video/split_ctrl.v:116 行内注释）。`>>14` 是**向下取整**（来源：src/rtl/video/split_ctrl.v:117），所以屏上的百分数是地板值：本卷代入满量程 1023×1600 = 1 636 800，除以 16384 = 99.9 → **99**；而 `eff = W = 1024` 时 1024×1600 = 1 638 400 / 16384 = 100 整（台架 `T3b eff = 屏宽 ⇒ 100 %` 来源：sim/tb_v93_split_ctrl.v:176）。结合 1.4 节那条 10 bit 上限 ⇒ 手工缝最多打到 99 %，100 % 只有自动扫描（`hi16 = 16` 时 `hi_px = 16×1024>>4 = 1024`）能到（来源：src/rtl/video/split_ctrl.v:41-42）。

**`pct_q` 那一拍不能删**：`reg [11:0] pct_q;` 单独寄存百分比（来源：src/rtl/video/split_ctrl.v:124-128），注释写明它是给 r60 那条最差路径准备的——`u_split_ctrl/swp_reg[7] → u_osd/r_reg[1]`、28 级、里面有一个 DSP48，起点就是这里的 `eff × PCT`（来源：src/rtl/video/split_ctrl.v:118-121）。本卷核对该 DSP 的存在：`u_split_ctrl` 那一行 DSP Blocks = 1（来源：build/util_hier_probe.rpt:75）。这一格只是屏上给人读的，晚一拍不可见（来源：src/rtl/video/split_ctrl.v:122-123）。

**一处文档/代码分歧（登记，不裁决）**：`split_ctrl` 文件头写"⚠ **本模块目前没有被任何顶层例化**"（来源：src/rtl/video/split_ctrl.v:3-4），而顶层确实例化了它：`split_ctrl #(.DISP_W(2*PANE_W), .SRC_W(IMG_W), .TICK_BITS(16)) u_split_ctrl (`（来源：src/rtl/top/pl_video_top.v:885），OSD 那一格也由它的 `shown_pct` 真驱动（来源：src/rtl/top/pl_video_top.v:990 与 :1012）。本卷按后者（已接上）写通路，把前者当作未更新的告警文字。

### 12.4 那条蓝线由哪一位控制

`marker` 端口（来源：src/rtl/video/split_display.v:27）在顶层由 `wire split_marker_on = ~gp[13];`（来源：src/rtl/top/pl_video_top.v:894）驱动，`gp[13]` 来自 `gpio_cfg1_o[30]`（来源：src/rtl/top/system_top.v:275），PS 侧宏 `#define SPLIT_MARKOFF_BIT (1u << 30)`（来源：src/ps/main.c:140）。所以**写 1 才是关**，复位或 PS 从没写过时屏上仍有那条线（来源：src/rtl/top/pl_video_top.v:892-893）。它同时被送进图像域那一路 `.marker_on(split_marker_on)`（来源：src/rtl/top/pl_video_top.v:907）。线宽与颜色：显示域 2 列（来源：src/rtl/video/split_display.v:52-53）、图像域 2 个图像列（来源：src/rtl/video/seam_src.v:26）、颜色 `8'h40/8'h40/8'hFF`（来源：src/rtl/video/split_display.v:64）。

### 12.5 为什么"缝是一条竖直的线"

`follow = 0` 时判据是 `x_sel < seam`（来源：src/rtl/video/split_display.v:43）——它**不含 `y`**，所以对同一列的所有行给出同一个答案，几何上必然是一条竖线，且贴的是屏幕两端（来源：src/rtl/video/seam_src.v:2-4 把这条写成"永远竖直、贴的是**屏幕**的左右两端"）。`follow = 1` 时线被搬到图像列空间：`seam_src` 在源头那一拍算 `wire in_band = (sx == seam) || (sx == (seam - 12'd1));`（来源：src/rtl/video/seam_src.v:26）与 `wire orig_n = (sx < seam) ? raw_left : ~raw_left;`（来源：src/rtl/video/seam_src.v:30），于是"画到屏上跟着旋转/缩放一起走、端点天然在画面两端（画面外是 oob，蓝线在那里不画）"（来源：src/rtl/video/seam_src.v:5-6）。分类放在源头还省掉把 12 bit 的 `sx` 打 18 级：结果只有一个位要跟着内容走（来源：src/rtl/video/seam_src.v:24-25，`TAPS = 18` 见 :9 与来源：src/rtl/top/pl_video_top.v:902，本卷算 MIX_D + 1 − 3 = 20 + 1 − 3 = 18）。两条链各自 3 深不行、必须同级：`reg [1:0] sh;  // {mark, orig}，两级一起走同一条链 ⇒ 不会各自新旧`（来源：src/rtl/video/seam_src.v:32），复位值 `sh <= 2'b01` 给"原图、不画线"（来源：src/rtl/video/seam_src.v:35），而标记线只画在画面内是 `wire mark_n = marker_on && in_band && !oob;` 里那个 `!oob`（来源：src/rtl/video/seam_src.v:28）。

| 这一站的输入/输出格式 | |
| --- | --- |
| 输入 | 两份 16 bit 流 + 两份越界位 + 与内容同级的 12 bit `x_sel` + 12 bit 缝位 + 3 个模式位 + 1 个标记位（来源：src/rtl/video/split_display.v:7-36） |
| 输出 | 8 bit R/G/B ×3 + `de_out/hs_out/vs_out`，本级晚 1 拍（来源：src/rtl/video/split_display.v:36-41、:60-69）；另有一份 12 bit 的 `shown_pct` 走 OSD 那条支路（来源：src/rtl/video/split_ctrl.v:25） |
| 出错时屏上表现 | 标签与内容不同级 ⇒ 缝左/右约 9 列一条近黑的竖带（来源：src/rtl/video/split_display.v:9-14）；标记线关不掉或整行被涂蓝 ⇒ 台架 `S6b PANE_W=0 must not paint the whole line`（来源：sim/tb_v97_seam_scan.v:197）与 `S7a marker=0 时一列蓝都没有`（来源：sim/tb_v97_seam_scan.v:214）；缝位置跳变 ⇒ `T10 打开 auto 的第一次变化是 +1（从手工位置 300 续扫，不回 0）`（来源：sim/tb_v93_split_ctrl.v:240） |

---

## 13 台架：效果链与几何两族判据清单

跑法各文件头都写成同一句（`bash` 加台架名，来源：sim/tb_edge_rim.v:25）——**里面那个 `sim/run_one.sh` 是旧路径**，
脚本现在在 `build/sim/run_one.sh`（它的头两行写着"快速单台架回归（绕开全量 run_sim.tcl 的两分钟编译），用法：run_one.sh <tb_name>"，
`build/sim/run_one.sh:2`），照注释里那句敲会找不到文件。下表只列**本卷覆盖的模块**对应的台架与判据行，不重跑、不写红绿。

### 13.1 效果链

| 台架（行数） | 被测 | 它主张什么 | 判据行 |
| --- | --- | --- | --- |
| `sim/tb_v86_pipe_sel.v`（被测与覆盖点写在文件头，来源：sim/tb_v86_pipe_sel.v:2） | `proc_pipeline` + `effect_ctrl` | 全旁路逐位不动、实测延迟 == 声明 LATENCY、LATENCY == 15、六种档位下都 15 拍、九位与阈值同步、gamma 四字段位序 | T1 来源：sim/tb_v86_pipe_sel.v:154；T2 :164；T3 :167；T5 :178；T15/T16 见头段 :14-15 |
| `sim/tb_v84_morph.v` | `proc_morph` 与 blur 的差分 | morph 旁路 = blur 旁路（同一中心抽头约定）、腐蚀/膨胀逐像素等于定义、面积变化、mode3 == mode0、延迟不随 mode 变 | :203 :227 :238 :257 :259 :261 :263 :274 :281 :289 :301 :311 :314 |
| `sim/tb_v85_sharpen.v` | `proc_sharpen` | 旁路差分、平场不动、台阶过冲/压零、R/B 与 G 分别钳位、脉冲守恒 | :120 :131 :147 :148 :149 :155 :166 :167 :175 :178 |
| `sim/tb_proc_gray.v` | `proc_gray` | `de` 传下去、红输入不出亮灰、白输入不出暗灰（三条 FAIL 行即判据） | 来源：sim/tb_proc_gray.v:41 :46 :56 |
| `sim/tb_v88_gamma.v` | `gamma_lut` | en=0 逐位透明、identity 表下 96 个通道值不动、三路按各自展开索引查表、翻转位写协议、复位不产生写、两端索引、单调 | :126 :133 :138 :143 :153 :162 :166 :172 :183 :198 |
| `sim/tb_edge_rim.v` | 四个窗口级并行例化 | 左/上/右 rim 的**值**等于 clamp-to-edge 定义、rim 随圈内邻居变而不随圈外回绕与上一帧末行变、×2 行/列复制几何、四家 `de_out` 同根、被判格子无 X | 索引段来源：sim/tb_edge_rim.v:24-25；R0 :439；R1 :440/:241；R2 :441；R3 :443；R4 :445；R5 :447；D1 :300；D1w :319；D2 :338；D2w :357；D3 :374；R7 :404；R8 :397；R9 :434 |
| `sim/tb_v89_align.v` | 四个窗口级 + 整链 | 旁路下"像素里带的坐标"与"台架数出的输出位置"之差恒定、四级偏移之和 == 整链偏移、补偿后整链内部偏移 = (0,0) | ID 来源：sim/tb_v89_align.v:265；T1 :312；T0 :334 |
| `sim/tb_v92_seam_bleed.v` | 四个窗口级 | 右窗缝边第 0/1/2 列不受上一行末尾影响、首行不受上一帧末行影响、九点抽头图九格全亮（3×3 完整、中心 = 标签像素），全部差分写法 | C0 来源：sim/tb_v92_seam_bleed.v:219；C1 :232；C2 :237/:239/:240；C3 :256；C4 :290；缺陷登记说明 :294 |
| `sim/tb_v103_pipe_bypass.v` | 整链全旁路 + 九个行缓存探针 | 槽位完整性、越界写、每列恰好发一次、探测器自己能红 | C0r 来源：sim/tb_v103_pipe_bypass.v:288；C10dpre :293；C10pre :332；C10a :335；C10c :352；C10d :354；C10fs :358；C10f :361；C10b :385 |

### 13.2 几何与缝

| 台架（行数） | 被测 | 它主张什么 | 判据行 |
| --- | --- | --- | --- |
| `sim/tb_v98_top_seam.v`（1893 行，唯一例化顶层的那把尺子） | `pl_video_top` | 尺子自证、读口相位、视口列/行定义、内容列 = 显示列>>1、八档列几何、面板坐标系、旋转形状、帧头、行首第 0 格、行匹配、两抽头行首、缝旁黑列（成对：探测器必须能红）、每帧换角、OSD 关掉后一格玫瑰都没有 | C0a 来源：sim/tb_v98_top_seam.v:1312；C1i :1410；C1g :1412；C1h :1416；C1c :1448；C1d :1454；C4a/C4b :1547/:1549；C5a/C5b/C5c :1555/:1557/:1563；C6a :1567；C8a/C8b :1572/:1575；C9a/C9c :1622/:1624；C9b :1650；C9e :1685；C7 :1756；C3a/C3b/C3c :1762/:1764/:1799；C2a/C2b/C2c :1767/:1769/:1771；C8c/C8cself :1786/:1793；C11/C11b :1851/:1853；C12a/C12b/C12c :1712/:1887/:1883 |
| `sim/tb_v98_c8_edge_column.v`（C8 一族拆出来的单独件） | `pl_video_top` | 同上的 C0/C1/C4/C5 段（同一批判据名在这一份里各写一遍） | 来源：sim/tb_v98_c8_edge_column.v:1275、:1373、:1375、:1379、:1411、:1417、:1526 |
| `sim/tb_v93_split_ctrl.v` | `split_ctrl` 两台（`TICK_BITS=6` 与默认 16） | 手工透传与越界夹紧、swap 只换内容不换缝位、百分比与整数除法逐点对账、源域折算、端点与步长、节拍按有效像素计（连续栅格与带消隐栅格各量一遍）、speed=0 钉住、手工转自动不跳位、range 写反折成 [min,max]、默认档一步像素数、样本地板 | :143 :148 :150 :152 :154 :158 :160 :162 :174 :176 :178 :182 :184 :187 :189 :196 :197 :198 :199 :206 :208 :211 :217 :222 :224 :233 :240 :249 :271 :276 |
| `sim/tb_v97_seam_scan.v` | `split_display` 四台（seam = 512/1/0/1024） | 标记线列数与落点、左右内容选择、`de` 透传、越界涂黑、消隐期不新画线、`x_sel` 落后 9 列时缝与线一起走、极端缝位不整行染蓝 | :147 :150 :153 :164 :178 :196 :197 :199 :200 :214 :215 :225 :242 |
| `sim/tb_rotate_window.v` | blur 与旋转的关系 | 旋转开着时模糊必须真的在算（不许把效果链强制旁路）、角度 0 时必须不生效 | 来源：sim/tb_rotate_window.v:113、:132（两条 PASS 各在 :115 与 :134） |
| `sim/tb_head_rot_displace.v` | 帧顶带内两帧角度之间的位移 | D1 k=0 同角度两遍逐位相同（台架自己不漂）、D2 k≥1 必须有 ≥1 格 ≥1 px 位移、D3 采样地板不许空判 | 判据索引来源：sim/tb_head_rot_displace.v:27-33；读数行 :136 :143 :147 :152 |

| 这一站的输入/输出格式 | |
| --- | --- |
| 输入 | 各台架自己的激励协议（例如 `tb_v86` 的 W=16×H=8 图、每帧 128 像素加每行 1 拍 `de=0`、帧尾 `repeat(LAT_EXPECT+4)` 排空，来源：sim/tb_v86_pipe_sel.v:7-8） |
| 输出 | 文本判据行：PASS/FAIL 加计数，`tb_v103` 那族还带 `first offender x_in / HW slot / din` 这类定位读数（来源：sim/tb_v103_pipe_bypass.v:356） |
| 出错时屏上表现 | 台架的红**不直接**等于屏上的形状；本卷第 2–12 节里每一条"屏上表现"都单独点了 RTL 行或台架行，两者不能互换使用。没有点名台架的那些屏上形状（例如 `pol` 接反）本卷写"未证" |

---

## 14 本卷自己算过的数 + 明写不出的东西

### 14.1 自算表（每行都是一个式子与两个操作数的出处）

| 数 | 式子 | 操作数出处 |
| --- | --- | --- |
| 整链 15 拍 | 1+1+3+3+3+1+3 | 逐项来源见 11.1（来源：src/rtl/process/proc_pipeline.v:18） |
| 模糊 57/512 对 1/9 的偏差 +0.195 % | (0.111328125 − 0.111111)/0.111111 | 来源：src/rtl/process/proc_box_blur.v:114-115 |
| 模糊平场恒等 31→31 | 31×9 = 279；279×57 = 15903；15903>>9 = 31.06 | 来源：src/rtl/process/proc_box_blur.v:104/115/118 |
| G 通道平场 63→63 | 63×9 = 567；567×57 = 32319；>>9 = 63.1 | 来源：src/rtl/process/proc_box_blur.v:107/116/119 |
| Sobel ±1020 与 2040 | 4×255；2×1020 | 来源：src/rtl/process/proc_sobel.v:111-117 |
| 锐化中间值上界 155 / 315 | 31×5；63×5 | 来源：src/rtl/process/proc_sharpen.v:92/95 |
| 灰度归一 256、最大 65280 | 77+150+29；255×256 | 来源：src/rtl/process/proc_gray.v:22 |
| gamma 截断误差上界 7/255 = 2.745 % | 丢掉 8 bit 的低 3 位 | 来源：src/rtl/video/gamma_lut.v:51 |
| MIX_D = 20；SB = 21；SEAM_TAPS = 18 | 3+1+1+15；MIX_D>16 ⇒ 20+1；20+1−3 | 来源：src/rtl/top/pl_video_top.v:354-355、:902 |
| 缝判定旧了 9 列 | MIX_D − 11 = 20 − 11 | 来源：src/rtl/top/pl_video_top.v:354、:919-920 与 src/rtl/video/split_display.v:9-14 |
| 扫描端点 128 / 896 列 | 2×1024>>4；14×1024>>4 | 来源：src/rtl/top/pl_video_top.v:20-21、:885 与 src/rtl/video/split_ctrl.v:39-42 |
| 64 个显示行一步 | 2^16 / 1024 | 来源：src/rtl/video/split_ctrl.v:11/77、src/rtl/top/pl_video_top.v:800 |
| PCT 常数 1600 / 3200 | 100×16384/1024；/512 | 来源：src/rtl/video/split_ctrl.v:112-113 |
| 手工缝最大 99 % | 1023×1600 = 1636800；/16384 = 99.9 | 来源：src/rtl/video/split_ctrl.v:116-117、src/ps/main.c:124 |
| 帧头提前量满量程 302 | 599+4+2 = 605；>>1 = 302；302−300 = 2 | 来源：src/rtl/video/video_timing_1024x600.v:18、src/rtl/top/pl_video_top.v:276-277/:284、:10 |
| 越界写落到的槽位 319 | 1343 mod 1024 | 来源：src/rtl/process/proc_pipeline.v:78-80、src/rtl/video/video_timing_1024x600.v:3 |
| 坐标链 288 个 DFF | 2 链 × 12 跳 × 12 bit | 来源：src/rtl/process/proc_pipeline.v:82-83（注释自算同值） |

### 14.2 本卷**不**解释的事（因为报告里没有那一层）

1. **注释自算的 288 个触发器**与实现报 `(u_pipe)` 本体的 **240 FF + 13 SRL** 之间的差额（来源：build/util_hier_probe.rpt:67）：这一层的分解不在该文件里，本卷只把两个数各摆在各处。
2. **`u_gray` / `u_inv` / `split_display` / `seam_src` / `rgb2dvi` 在实现级名册里没有单独一行**（名册列出的子实例见来源：build/util_hier_probe.rpt:66-76）：本卷写"未单列"，不推测原因。
3. **模糊那两条 16 bit 行缓存落成的结构**：`u_blur` 那行 LUTRAMs = 0 而 LUTs = 441（来源：build/util_hier_probe.rpt:69），这份报告只到列，本卷不解释它与 `ram_style = "distributed"`（来源：src/rtl/process/proc_box_blur.v:19）之间的关系。
4. **本卷不引用任何板级读数**：屏上形状一律引 RTL 行为注释或台架判据名；`sim/tb_v92_seam_bleed.v:294` 那条"现在的红"是该文件自己的说明文字，本卷未重跑（来源：sim/tb_v92_seam_bleed.v:294）。
5. **`angle_idx` 为什么存在**：`split_display` 的端口表里有它（来源：src/rtl/video/split_display.v:33）、顶层也接了（来源：src/rtl/top/pl_video_top.v:925），但模块体不读它，源文件里没有写它的用途（全文检索该标识符仅命中声明那一行）。
6. **`split_ctrl` 文件头与顶层例化状态矛盾**（来源：src/rtl/video/split_ctrl.v:3-4 对 src/rtl/top/pl_video_top.v:885）：本卷登记分歧，按代码写通路，不裁决哪份该改。
7. **`proc_sharpen` 文件头"固定 2 拍"与它自己三拍 `de` 链矛盾**（来源：src/rtl/process/proc_sharpen.v:5 对 :124-126）：链上记账以 `proc_pipeline.v:18` 的"锐化3"为准（来源：src/rtl/process/proc_pipeline.v:18）。
