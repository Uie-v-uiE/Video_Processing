/**
 * PS control plane + SD 卡本地回放。UDP 视频数据通路仍然整个在 PL（rtl/eth 目录）。
 *
 * AXI GPIO @ 0x41200000（V7 的那条，位序不许动 —— 老工具按位读写它）
 *   [4:0]   effect_en（= 下面九位的一个投影）[15:8] threshold  [16] src_sel  [17] zoom_en
 *   [18]    ps_publish —— 翻转一次 = "DDR 里这一帧写完了，请在下一个 frame_start 搬走"
 *   [19]    bilin_en   [26] gapclr_sel   [31:27] 健康 lane 号
 * AXI GPIO @ 0x41220000（V8-2 新增，BD 里的 axi_gpio_2，双通道×32bit）
 *   ch1[8:0] stage_sel —— 效果链的真相，位定义的唯一出处是 src/rtl/process/proc_pipeline.v
 *   ch1[31:9] 与 ch2 留给 V8-3/Gamma、V8-4/分割线（现在一个字节都不写）
 * DDR frame @ 0x10100000（FILL 诊断帧 / SD 回放帧都落在这里；ETH 用 0x10000000/0x10080000）
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>                 /* V8-3 的 gamma 曲线；链接要 -lm（build/ps_app.mjs） */
#include "xparameters.h"
#include "xil_printf.h"
#include "xil_io.h"
#include "xil_cache.h"
#include "xil_exception.h"
#include "xuartps.h"
#include "sleep.h"
#include "sd_play.h"

#define FRAME_W     512
#define FRAME_H     300
#define FRAME_BYTES (FRAME_W * FRAME_H * 2)
/* PS 片源的帧落在 DDR 的**第三个 bank**：0x1010_0000。
 * 以前是 0x1000_0000，与 ETH 乒乓双 bank 的第 0 块重叠 ⇒ SD/FILL 一边写、ETH 一边读写同一块内存，
 * 屏幕上就是"两个片源打架、闪"（板级实测 2026-09-24）。仲裁只管谁用 DDR→帧缓存那台搬运机，
 * 管不到谁写 DDR（SD 的 DMA 走 PS 自己的 HP0，不经过 PL），所以只能靠地址分开。
 * 这个数必须等于 `system_top.v` 的 PS_DDR_BASE / `pl_video_top.v` 的 PS_BASE_ADDR。 */
#define FRAME_ADDR  0x10100000u

#define AXI_GPIO_BASE 0x41200000u
#define GPIO_DATA     (AXI_GPIO_BASE + 0x00u)
#define GPIO_TRI      (AXI_GPIO_BASE + 0x04u)
#define PUBLISH_BIT   18u
#define BILIN_BIT     19u     /* 右窗双线性插值开关：0 = 最近邻（同一条通路，小数钉 0） */

/* ---- V8-2：第二条控制字（BD 里的 axi_gpio_2，双通道 ×32bit 纯输出） ----
 * 基址 0x41220000 是 build/tcl/build_system_axigpio.tcl 里**钉死并回读校验过**的
 * （ADDR_LOG 三行 want/got 数值相等才让构建继续）。为什么硬编码：手工链接的 BSP 不会
 * 重新生成 xparameters.h，地址变了不会编译失败，只会"写了没反应"。
 * 通道 2（+0x08）留给 V8-3 的 Gamma 窗口与 V8-4 的分割线参数，现在一个字都不写。
 * ⚠ 这一条把 elf 与 bit 绑死了：**旧位流上没有这个从设备**。开机自检会写 0 再读回来，
 *    读不回 0 就大声报"位流/elf 不配套"（配套关系由 build/frozen_* 的 md5 清单管）。 */
#define AXI_GPIO_CFG_BASE 0x41220000u
#define CFG_DATA0         (AXI_GPIO_CFG_BASE + 0x00u)
/* 通道 2（+0x08）= V8-3 的 Gamma 窗口。位序与 `src/rtl/video/gamma_lut.v` / spec §6b 一致：
 * [31] en、[30] wr（**翻转位**，不是电平）、[29:22] data、[21:14] idx、
 * [13:8] gamma_disp = γ×10（V8-5 新加：只给 OSD 显示"1.8"这一格用，PL 不参与运算；
 *                     0 表示"gamma 关着"，屏上会看到 Gamma:0.0）。
 * ⚠ 这一组位与 gamma 协议在**同一个寄存器**里 ⇒ 所有写通道 2 的地方都必须从 `gm_w`
 *   这个影子出发整字写回（读-改-写会踩 #55 那个"PS 每帧重写把别的位抹掉"的同一个坑）。 */
#define CFG_DATA1         (AXI_GPIO_CFG_BASE + 0x08u)
#define GM_EN             (1u << 31)
#define GM_WR             (1u << 30)
#define GM_DATA(v)        ((((u32)(v)) & 0xFFu) << 22)
#define GM_IDX(i)         ((((u32)(i)) & 0xFFu) << 14)
#define GM_DISP_MASK      (0x3Fu << 8)
#define GM_DISP(v)        ((((u32)(v)) & 0x3Fu) << 8)

/* 九位算法选择字：位定义的唯一出处是 `src/rtl/process/proc_pipeline.v` 文件头，这里只是抄一份。 */
#define SEL_GRAY    (1u << 0)
#define SEL_INVERT  (1u << 1)
#define SEL_BLUR    (1u << 2)
#define SEL_SHARP   (1u << 3)
#define SEL_SOBEL   (1u << 4)
#define SEL_BIN     (1u << 5)
#define SEL_BIN_POL (1u << 6)
#define SEL_ERODE   (1u << 7)
#define SEL_DILATE  (1u << 8)

static u32 cur_sel = 0;        /* 效果选择的唯一真相（九位） */
static u32 cur_en = 0;         /* gpio_o[4:0] 上的老五位镜像，由 cur_sel 反推，不独立存在 */
static u8  cur_thr = 80;
static u8  cur_src = 0;
static u8  cur_zoom = 1;   /* GPIO bit17: 右屏无极缩放的"要不要呼吸" */
/* V8-8 手动缩放：档号 0..7 对应 0.25/0.33/0.50/0.75/1.00/1.33/1.50/2.00 倍，走 cfg1
 * （= CFG_DATA0 = 0x41220000，与 stage_sel **同一个字**）的 [28:26]，手动旗标在 [29]。
 * 位序的理由写在 PLAN_V8_SPEC §7a/§7c。 */
static u8  cur_zsel = 4;         /* 默认 1.00x —— 与 reset 时 RTL 的 INV_LO 同一档 */
static u8  cur_zman = 0;         /* 0 = 自动呼吸（上电默认，保持老观感） */
static const u8   ZOOM_X100[8] = { 25, 33, 50, 75, 100, 133, 150, 200 };
static const char *ZOOM_NAME[8] = { "0.25x", "0.33x", "0.50x", "0.75x",
                                    "1.00x", "1.33x", "1.50x", "2.00x" };
static u8  cur_bilin = 1;  /* GPIO bit19: 双线性/最近邻 A-B 对照，演示时现场切换用 */
static u32 pub_lvl = 0;

/* 老五位是"新九位的一个投影"，不是第二个控制源 —— 这样 RTL 的旁路优先级
 * （cfg != 0 用 cfg，否则用老位）在固件这边永远自洽：两边永远说同一件事。 */
static void sel_sync_legacy(void)
{
    cur_en = ((cur_sel & SEL_GRAY)   ? 1u  : 0u)
           | ((cur_sel & SEL_BIN)    ? 2u  : 0u)
           | ((cur_sel & SEL_BLUR)   ? 4u  : 0u)
           | ((cur_sel & SEL_SOBEL)  ? 8u  : 0u)
           | ((cur_sel & SEL_INVERT) ? 16u : 0u);
}


/* 只写寄存器、不打字，返回写进去的值。
 * 每帧一次的"发布"脉冲必须走这条：原来 ps_publish() 直接调 ctrl_apply()，于是 30 fps 的
 * 回放每秒往串口推约 2 KB（115200 只有 11.5 KB/s，而 xil_printf 是轮询等 TX 的阻塞实现），
 * 板上实测 PLAY 10 s 收回 28549 B 全是 [CTRL] 行 —— 刷屏之外还把发布时序压在打印上。 */
static u32 ctrl_write(void)
{
    u32 v;
    sel_sync_legacy();
    v = (cur_en & 0x1F) | ((u32)cur_thr << 8) | ((u32)cur_src << 16)
      | ((u32)(cur_zoom ? 1 : 0) << 17) | (pub_lvl << PUBLISH_BIT)
      | ((u32)(cur_bilin ? 1 : 0) << BILIN_BIT);
    Xil_Out32(GPIO_DATA, v);
    /* cfg1 一次写整个字：低 9 位是效果选择，[28:26] 是缩放档，[29] 是手动旗标。
     * ⚠ 这里的 CFG_DATA0 就是 RTL 的 gpio_cfg1_o；gamma 那个窗口是 CFG_DATA1(+0x08)。
     *   两个名字差一位，写错字的症状恰恰是"设了没反应"，最容易误判成 PL 坏了。 */
    Xil_Out32(CFG_DATA0, (cur_sel & 0x1FFu)
               | ((u32)(cur_zsel & 7u) << 26) | ((u32)(cur_zman ? 1u : 0u) << 29));
    return v;
}

static void ctrl_apply(void)
{
    u32 v = ctrl_write();
    xil_printf("[CTRL] AXI_GPIO=0x%08x sel=%03x thr=%d src=%d zoom=%d pub=%d bilin=%d\r\n",
               v, cur_sel & 0x1FF, cur_thr, cur_src, cur_zoom ? 1 : 0, (int)pub_lvl,
               cur_bilin ? 1 : 0);
    /* 缩放这一格把"设进去的档"和"现在是手动还是呼吸"分开报：自动时屏上那一格是活的，
     * 这里报的 step 只是"切回手动就会用哪一档"，别让它看起来像当前倍率。 */
    xil_printf("[CTRL]   zoom_step=%d %s (%s)\r\n", cur_zsel,
               ZOOM_NAME[cur_zsel & 7u], cur_zman ? "手动" : "自动呼吸");
}

/* sd_play.c 只被允许请求"发布"，不碰别人的控制字；每帧都调，所以不出声 */
void ps_publish(void)
{
    pub_lvl ^= 1u;
    (void)ctrl_write();
}

/* ---- V8-3：Gamma 表 ----
 * 曲线**在 PS 这边算**，PL 只负责"写进去什么就查什么" ⇒ "算错曲线"与"接错线"是两件事，
 * 各自的凭据也分开：算错的凭据是本函数自带的端点 + 单调自检（打 [GAMMA] 那行，板子上直接读），
 * 接错的凭据是 `sim/tb_v88_gamma`（八条，含"关着就必须一动不动"那条反例）。
 *
 * 两项之间必须 usleep：PL 看的是 `wr` 的**边沿**，而 AXI 连发的间隔可以短到一个像素拍都不到
 * （协议前提写在 gamma_lut.v 头部）。5 µs ⇒ 256 项约 2.6 ms，人看不出来，
 * 但它把"丢几项"从"看运气"变成"永远有余量"。这条约束是真实的，别删。 */
static u32 gm_w = 0;           /* 通道 2 当前电平：wr 位的唯一真相在这里（PL 那边只看边沿） */
static u32 cur_gamma = 0;      /* γ×100；0 = 关（en=0，PL 逐位旁路） */

static void gamma_put(u32 i, u32 v)
{
    Xil_Out32(CFG_DATA1, gm_w | GM_DATA(v) | GM_IDX(i));   /* 先摆地址与数据，wr 不动 */
    usleep(5);
    gm_w ^= GM_WR;                                         /* 翻 wr = 写这一项 */
    Xil_Out32(CFG_DATA1, gm_w | GM_DATA(v) | GM_IDX(i));
    usleep(5);
}

/* out = 255·(in/255)^(1/γ)，四舍五入。γ=1.00 ⇒ 表恒等 ⇒ 开了也逐位不动（台架 T2 的固件侧对照）。 */
static u8 gamma_curve(u32 g100, u32 i)
{
    float e = 100.0f / (float)g100;
    float y = pow((float)i / 255.0f, e) * 255.0f + 0.5f;
    if (y < 0.0f)   y = 0.0f;
    if (y > 255.0f) y = 255.0f;
    return (u8)y;
}

static void gamma_off(void)
{
    cur_gamma = 0;
    gm_w &= ~GM_EN;                       /* 只关使能，表留着：现场要在"开/关"之间来回切 */
    gm_w &= ~GM_DISP_MASK;                /* 屏上那一格跟着变成 0.0 = "没开"，不许留着旧值说谎 */
    Xil_Out32(CFG_DATA1, gm_w);
    xil_printf("[GAMMA] off（PL 逐位旁路，表保留）\r\n");
}

static void gamma_set(u32 g100)
{
    u32 i, v, prev = 0, bad = 0;
    u8 first, last;

    if (g100 < 100u || g100 > 300u) {
        xil_printf("[GAMMA] 只认 1.00..3.00（或写成 100..300），收到 %d.%02d\r\n",
                   (int)(g100 / 100u), (int)(g100 % 100u));
        return;
    }
    for (i = 0; i < 256u; i++) {
        v = gamma_curve(g100, i);
        if (v < prev) bad++;              /* 幂曲线对 in 单调不降，反过来就是算错了 */
        prev = v;
        if (i == 0u)   first = (u8)v;
        if (i == 255u) last  = (u8)v;
        gamma_put(i, v);
    }
    gm_w |= GM_EN;
    /* OSD 那一格与表**同一次提交**：γ×10 四舍五入（180→18 ⇒ 屏上 1.8）。
     * 分开两处写会出现"表已经换成 2.2、屏上还写着 1.8"，而这一格是观众唯一能看见的证据。 */
    gm_w = (gm_w & ~GM_DISP_MASK) | GM_DISP((g100 + 5u) / 10u);
    Xil_Out32(CFG_DATA1, gm_w);
    cur_gamma = g100;
    xil_printf("[GAMMA] g=%d.%02d mono_bad=%d first=%d last=%d\r\n",
               (int)(g100 / 100u), (int)(g100 % 100u), (int)bad, (int)first, (int)last);
    if (bad != 0u || first != 0u || last != 255u)
        xil_printf("[GAMMA!] 曲线自检没过（表已写入但**不要**用它演示）\r\n");
}

/* "1.8" → 180；"180" → 180；其余写法一律不猜。 */
static int parse_gamma(const char *s, u32 *g100)
{
    const char *p = s;
    u32 ip = 0, fp = 0, nd = 0;

    if (p == 0 || *p == 0) return 0;
    while (*p >= '0' && *p <= '9') { ip = ip * 10u + (u32)(*p - '0'); p++; }
    if (*p != '.') {
        if (*p) return 0;
        *g100 = ip;                       /* 不带小数点：按 γ×100 收 */
        return 1;
    }
    p++;
    while (*p >= '0' && *p <= '9') {
        if (nd < 2u) { fp = fp * 10u + (u32)(*p - '0'); nd++; }   /* 第三位小数只舍不进 */
        p++;
    }
    if (*p) return 0;
    while (nd < 2u) { fp *= 10u; nd++; }   /* "1.8" = 1.80 */
    *g100 = ip * 100u + fp;
    return 1;
}

static void ctrl_set_sel(u32 sel)
{
    cur_sel = sel & 0x1FFu;
    ctrl_apply();
}

/* 老五位 → 新九位：bit0 gray / bit1 binary / bit2 blur / bit3 sobel / bit4 invert */
static u32 legacy_to_sel(u32 e)
{
    return ((e & 1u)  ? SEL_GRAY   : 0u)
         | ((e & 2u)  ? SEL_BIN    : 0u)
         | ((e & 4u)  ? SEL_BLUR   : 0u)
         | ((e & 8u)  ? SEL_SOBEL  : 0u)
         | ((e & 16u) ? SEL_INVERT : 0u);
}

/* `pipe` 与裸位串：5 位是**老写法**（老位序），9 位是**新写法**（新位序）。
 * 两种都收是为了不断掉 HOST_GUIDE / DEMO_SCRIPT / set_src.tcl 里已经写好的例子，
 * 但它们的意思不同 —— 这条差异写在 HOST_GUIDE 的命令表里，串口电池的 6/7 两条各钉一边。 */
static void apply_pipe_bits(u32 b, int n)
{
    ctrl_set_sel(n == 5 ? legacy_to_sel(b) : (b & 0x1FFu));
}

static void ctrl_set_thr(u8 thr)
{
    cur_thr = thr;
    ctrl_apply();
}

static void ctrl_set_src(u8 src)
{
    cur_src = src ? 1 : 0;
    ctrl_apply();
}

static void ctrl_set_zoom(u8 on)
{
    cur_zoom = on ? 1 : 0;
    ctrl_apply();
}

/* "0.75" / "1.5" / "2" → 倍率×100（纯整数：不为一条串口命令拖进 libm，
 * 而且浮点比较在八档这种粗粒度上没有任何好处）。返回 -1 = 这个 token 不是倍率。 */
static int zoom_parse_x100(const char *t, int *out)
{
    int ip = 0, fp = 0, dig = 0, dot = 0;
    const char *c;
    if (!t || !*t || *t == '.') return -1;
    for (c = t; *c; c++) {
        if (*c == '.') { if (dot) return -1; dot = 1; continue; }
        if (*c < '0' || *c > '9') return -1;
        if (!dot) { if (ip > 999) return -1; ip = ip * 10 + (*c - '0'); }
        else      { if (dig >= 2)  return -1; fp = fp * 10 + (*c - '0'); dig++; }
    }
    while (dig < 2) { fp *= 10; dig++; }              /* "1.5" 的小数补齐成 50 */
    *out = ip * 100 + fp;
    return (*out > 0 && *out <= 400) ? 0 : -1;        /* 0.01x…4.00x 之外一律不认 */
}

/* 取最近一档：直接拿 ZOOM_X100 比距离，不再抄一份"中点表"。
 * 两个理由：① 少一张表就少一处会过期的地方；② 平局往哪边靠是**这张表**决定的，
 * 台架里改档值时判据跟着走，不会出现"命令侧与 RTL 侧各说一遍中点"。 */
static u8 zoom_step_near(int x100)
{
    u8 i, best = 0;
    int d, bd = -1;
    for (i = 0; i < 8; i++) {
        d = x100 - (int)ZOOM_X100[i];
        if (d < 0) d = -d;
        if (bd < 0 || d < bd) { bd = d; best = i; }
    }
    return best;
}

static void ctrl_set_bilin(u8 on)
{
    cur_bilin = on ? 1 : 0;
    ctrl_apply();
}

static int parse_bits(const char *s, u32 *out)
{
    u32 en = 0;
    int n = 0;
    for (; *s; ++s) {
        if (*s == '\r' || *s == '\n' || *s == ' ') break;
        if (*s != '0' && *s != '1') return -1;
        if (n >= 9) return -1;            /* 新写法最长 9 位（老写法 5 位，见 apply_pipe_bits） */
        en |= ((u32)(*s - '0')) << n;
        ++n;
    }
    if (n == 0) return -1;
    *out = en;
    return n;
}

/* ================= V8 spec §14：统一文本协议 =================
 * 一行 = 动词 + 至多 3 个参数，大小写不敏感。
 * 老写法（SRC0 / TH80 / ZOOM1 / BILIN0 / FRAME12 / 裸 00111）**继续有效**：
 * `src/host/HOST_GUIDE.md`、`report/DEMO_SCRIPT.md` 和 `build/tcl/set_src.tcl` 都在发它们，
 * 换语法不能把这些工具判成"命令没响应"。
 * 老写法是 `strncmp(buf,"TH",2)` 这种前缀匹配，参数是"粘在动词后面"的；新解析器把参数按空白
 * 切开单独取，顺带把 "THE" 也能当 TH 用的那个宽接受集关掉。
 */
#define T_MAX 4

static void cmd_help(void);
static void cmd_fill(void);

/* 上电自动挂载 + 自动播放（用户要的"上电就有画面"）。
 * 为什么默认开：PL 侧的片源仲裁（ISSUES #49）已经保证"ETH 有流时 PS 让位、停流后自动接回"，
 * 所以自动播放不会和推流抢屏幕 —— 两路可以同时插着。
 * 代价说清楚：`XSdPs_CfgInitialize` 每个上电周期只成功一次（ISSUES #45），把挂载提前到上电，
 * 就等于把"那一次"用在上电时刻；卡没插好时，后面手敲 `SD` 也会失败。今天不自动挂载、
 * 第一次 `SD` 失败之后再敲同样会失败（同一个 #45），所以这不是新引入的失效模式。
 * 位置：必须在 dispatch() 之前 —— `autoplay0/1` 两条命令要写它。 */
static int autoplay = 1;

static int ci_eq(const char *a, const char *b)
{
    for (;; ++a, ++b) {
        char x = (*a >= 'a' && *a <= 'z') ? (char)(*a - 'a' + 'A') : *a;
        char y = (*b >= 'a' && *b <= 'z') ? (char)(*b - 'a' + 'A') : *b;
        if (x != y) return 0;
        if (!x) return 1;
    }
}

static int ci_pre(const char *a, const char *pre)
{
    for (; *pre; ++a, ++pre) {
        char x = (*a >= 'a' && *a <= 'z') ? (char)(*a - 'a' + 'A') : *a;
        char y = (*pre >= 'a' && *pre <= 'z') ? (char)(*pre - 'a' + 'A') : *pre;
        if (x != y) return 0;
    }
    return 1;
}

/* 严格十进制：可带 +/-，必须整串吃完，不许有空白或字母。 */
static int strict_int(const char *s, int *out)
{
    int v = 0, neg = 0, n = 0;
    if (*s == '+') ++s;
    else if (*s == '-') { neg = 1; ++s; }
    for (; *s; ++s) {
        if (*s < '0' || *s > '9') return 0;
        if (v > 100000) return 0;        /* 本文件里最大合法值是帧号 4398，再长一律当错 */
        v = v * 10 + (*s - '0');
        ++n;
    }
    if (n == 0) return 0;
    *out = neg ? -v : v;
    return 1;
}

static int tokenize(char *line, char **tk)
{
    char *p = line;
    int n = 0;
    while (*p && n < T_MAX) {
        while (*p == ' ' || *p == '\t') ++p;
        if (!*p) break;
        tk[n++] = p;
        while (*p && *p != ' ' && *p != '\t') ++p;
        if (*p) *p++ = 0;
    }
    return n;
}

/* "语法收到了，但 PL 里还没有对应的入口"。四种待接命令都从这里出去，
 * 好处是不会有一天某条命令**悄悄**变成"看起来收了、其实没人接"。 */
static void not_wired(const char *verb, const char *missing, const char *step)
{
    xil_printf("[CMD] %s 语法已收，硬件未接：缺 %s（规划 %s，见 report/PLAN_V8_SPEC.md 第 3 节）\r\n",
               verb, missing, step);
}

/* 诊断帧：四象限 + 顶部绿条，故意用四种极端颜色，让"哪一通道丢了"在屏上一眼分得清 */
static void cmd_fill(void)
{
    volatile u16 *p = (volatile u16 *)FRAME_ADDR;
    int i;
    for (i = 0; i < FRAME_W * FRAME_H; i++) {
        int x = i % FRAME_W, y = i / FRAME_W;
        u16 c;
        if (y < 8)            c = 0x07E0;
        else if (x < 256 && y < 150)  c = 0xF800;
        else if (x >= 256 && y < 150) c = 0xFFE0;
        else if (x < 256)     c = 0x001F;
        else                  c = 0xFFFF;
        p[i] = c;
    }
    Xil_DCacheFlushRange(FRAME_ADDR, FRAME_BYTES);
    ctrl_set_src(1);
    ps_publish();       /* 新协议：PL 只在收到发布脉冲后才搬一次 */
    xil_printf("[CMD] FILL diagnostic via PS DDR\r\n");
}

static void cmd_src(int n)
{
    switch (n) {
    case 0: ctrl_set_src(0); break;               /* 图卡 */
    case 1: ctrl_set_src(1); break;               /* DDR：ETH 活着时仲裁给 ETH */
    case 2:                                             /* SD：也是 DDR，只是把回放踢起来 */
        ctrl_set_src(1);
        if (!sd_play(1)) xil_printf("[SD] play refused: %s\r\n", sd_err());
        break;
    default:
        xil_printf("[SRC] 只认 0=图卡 1=网络 2=SD\r\n");
        return;
    }
    /* 说不清就是埋坑：spec 的 src 0/1/2 是"独占这一路"，而 PS 写得动的只有 1 bit src_sel
     * （0=图卡 / 1=DDR）；"锁哪一路"是 PL 里 src_mode 的四态，目前只有 KEY1 长按能改。
     * 真正的三态锁 + spec 要求的"手动命令退出自动模式"在 V8-2 的控制字里一起给。 */
    xil_printf("[SRC] 已切 src_sel=%d；**独占**还要 mode 覆盖位（V8-2）——现在 AUTO 下仍由仲裁定屏幕\r\n",
               n ? 1 : 0);
}

static int dispatch(char **tk, int nt)
{
    u32 en;
    int v;
    int nb;

    nb = parse_bits(tk[0], &en);
    if (nt == 1 && nb > 0) { apply_pipe_bits(en, nb); return 0; }

    if (ci_eq(tk[0], "PIPE")) {
        nb = (nt >= 2) ? parse_bits(tk[1], &en) : -1;
        if (nb <= 0) { xil_printf("[PIPE] 要跟 5 位（老写法）或 9 位（新写法）0/1，例：pipe 11000\r\n"); return 0; }
        apply_pipe_bits(en, nb);
        return 0;
    }
    if (ci_pre(tk[0], "TH")) {
        /* TH80（老写法，参数粘着）与 th 80（spec 写法，参数分开）共用一条出口。
         * 粘着的那半必须整串是数字，否则当错命令报出去 —— 老的前缀匹配连 "THE" 都收，这个不收。 */
        const char *arg = (nt >= 2) ? tk[1] : tk[0] + 2;
        if (!strict_int(arg, &v)) { xil_printf("[TH] 要跟十进制 0..255\r\n"); return 0; }
        if (v < 0) v = 0;
        if (v > 255) v = 255;
        ctrl_set_thr((u8)v);
        return 0;
    }
    if (ci_pre(tk[0], "SRC")) {
        /* 一条出口同时吃 `src 2`（V8，参数分开）与 `SRC0/SRC1`（老写法，参数粘着）：
         * 老代码是两个 strncmp 分支，重构成"取尾字符"时数错过一位（BILIN1 那次），
         * 所以这里改成"整串交给 strict_int"，不再按下标取字符。 */
        const char *arg = (nt >= 2) ? tk[1] : tk[0] + 3;
        if (strict_int(arg, &v)) cmd_src(v);
        else xil_printf("[SRC] 只认 0=图卡 1=网络 2=SD\r\n");
        return 0;
    }
    if (ci_pre(tk[0], "ZOOM")) {
        /* `zoom on|off` 与老写法 `ZOOM1/ZOOM0`（粘着）共用一条出口；倍率走 `zoom <数>`。
         * ⚠ 有一处**语义重叠**：`zoom 1` / `zoom 0` 沿用 V7 的开关（ZOOM1=开呼吸），
         *   所以"1.00 倍"必须写 `zoom 1.0`（带小数点才是倍率）。这条在拒绝消息里也印出来了，
         *   因为 r53 第一次跑电池就是拿 `zoom 1` 当"回到 1.0x"用，结果把呼吸又打开了。 */
        const char *arg = (nt >= 2) ? tk[1] : tk[0] + 4;
        int b = -1;
        if (strict_int(arg, &v) && (v == 0 || v == 1)) b = v;
        if (ci_eq(arg, "ON")) b = 1;
        if (ci_eq(arg, "OFF")) b = 0;
        if (b >= 0) { ctrl_set_zoom((u8)b); return 0; }
        if (ci_eq(arg, "AUTO")) { cur_zman = 0; ctrl_apply(); return 0; }
        {
            int x100 = 0;
            if (zoom_parse_x100(arg, &x100) == 0) {
                u8 st = zoom_step_near(x100);
                /* 取最近档，并把"你写的"与"我用的"一起报出来：`zoom 0.9` 会被写成 1.00x，
                 * 沉默地换成别的数比拒绝更难查（gamma 那一处踩过同一类）。 */
                cur_zsel = st; cur_zman = 1;
                ctrl_apply();
                xil_printf("[ZOOM] %s → 最近档 %s（八档：%s %s %s %s %s %s %s %s；"
                           "回自动用 zoom auto）\r\n", arg, ZOOM_NAME[st],
                           ZOOM_NAME[0], ZOOM_NAME[1], ZOOM_NAME[2], ZOOM_NAME[3], ZOOM_NAME[4],
                           ZOOM_NAME[5], ZOOM_NAME[6], ZOOM_NAME[7]);
                return 0;
            }
        }
        xil_printf("[ZOOM] 不认的参数 `%s`：`zoom on|off`（呼吸开关）、`zoom auto`（回自动）"
                   "或 `zoom <倍率>`，如 0.75 / 1.5 / 2\r\n"
                   "       （注意：`zoom 1` / `zoom 0` 沿用 V7 的 `ZOOM1/ZOOM0`，是**开关**；"
                   "要 1.00 倍请写 `zoom 1.0`）\r\n", arg);
        return 0;
    }
    if (ci_pre(tk[0], "BILIN")) {
        const char *arg = (nt >= 2) ? tk[1] : tk[0] + 5;   /* BILIN 是 5 个字母 */
        int b = -1;
        if (strict_int(arg, &v) && (v == 0 || v == 1)) b = v;
        if (ci_eq(arg, "ON")) b = 1;
        if (ci_eq(arg, "OFF")) b = 0;
        if (b < 0) xil_printf("[BILIN] 只认 on/off（0/1）\r\n");
        else ctrl_set_bilin((u8)b);
        return 0;
    }
    /* —— 以下四个是 spec §14 里还没落地的动词：先把语法收住，出口只有一条 —— */
    if (ci_eq(tk[0], "ROT"))     { not_wired("rot", "PL 的角度写入口（angle_ctrl 现在只吃按键）", "V8-2/V8-8"); return 0; }
    if (ci_eq(tk[0], "SPLIT"))   { not_wired("split", "缝位的执行者（split_ctrl 已单独验完、尚未接线；"
                                                     "先要统一几何，见 ISSUES #62）", "V8-4"); return 0; }
    if (ci_pre(tk[0], "GAMMA")) {
        /* `gamma off` / `gamma 1.8` / `gamma 180`（γ×100）三种写法；参数粘着或分开都吃。 */
        const char *arg = (nt >= 2) ? tk[1] : tk[0] + 5;
        u32 g = 0;
        if (ci_eq(arg, "OFF") || ci_eq(arg, "0")) { gamma_off(); return 0; }
        if (ci_eq(arg, "ON"))  { gamma_set(cur_gamma ? cur_gamma : 220u); return 0; }
        if (!parse_gamma(arg, &g)) {
            xil_printf("[GAMMA] 要 off / 1.00..3.00（或 100..300），收到的是 \"%s\"\r\n", arg);
            return 0;
        }
        gamma_set(g);
        return 0;
    }
    if (ci_eq(tk[0], "OSD"))     { not_wired("osd", "OSD 行开关位（现在是常显）", "V8-5"); return 0; }

    if (ci_pre(tk[0], "FRAME")) {
        const char *arg = (nt >= 2) ? tk[1] : tk[0] + 5;   /* frame 12 / FRAME12 */
        if (!strict_int(arg, &v) || v < 0) { xil_printf("[SD] frame 要跟十进制帧号\r\n"); return 0; }
        if (sd_show((u32)v) != 0) { xil_printf("[SD] frame %d failed: %s\r\n", v, sd_err()); return 0; }
        ctrl_set_src(1);
        return 0;
    }
    if (ci_eq(tk[0], "SD"))  { if (sd_mount() == 0) sd_status(); else xil_printf("[SD] mount failed: %s\r\n", sd_err()); return 0; }
    if (ci_eq(tk[0], "PLAY")) {
        ctrl_set_src(1);
        if (!sd_play(1)) xil_printf("[SD] play refused: %s\r\n", sd_err());
        /* 旧文案写的是"cable must stay out"——那是 #49 之前没有仲裁时的规矩，
         * 现在停流会自动交回，留着这句话只会误导下一个操作的人。 */
        else xil_printf("[SD] playing (STOP to end; ETH 有流时会自动让位)\r\n");
        return 0;
    }
    if (ci_eq(tk[0], "STOP")) {
        (void)sd_play(0);
        xil_printf("[SD] stopped at frame %d\r\n", (int)sd_frame_now());
        return 0;
    }
    if (ci_eq(tk[0], "FILL")) { cmd_fill(); return 0; }
    if (ci_pre(tk[0], "AUTOPLAY")) {
        const char *arg = (nt >= 2) ? tk[1] : tk[0] + 8;   /* AUTOPLAY 是 8 个字母 */
        if (!strict_int(arg, &v) || (v != 0 && v != 1)) { xil_printf("[SD] autoplay 要跟 0 或 1\r\n"); return 0; }
        autoplay = v;
        xil_printf("[SD] autoplay %s (only affects the next boot)\r\n", v ? "on" : "off");
        return 0;
    }
    if (ci_eq(tk[0], "STAT") || ci_eq(tk[0], "STATUS")) {
        /* 字段顺序不许动：串口电池与 arb_handover_test.mjs 都按 "ctrl en=… thr=…" 的前缀解析，
         * 新加的 sel / gm 只能往后放。en 是老五位的投影，sel 才是效果链的真相，
         * gm=0.00 表示 gamma 关（PL 那一侧逐位旁路）。 */
        xil_printf("[STAT] ctrl en=%02x thr=%d src=%d zoom=%d bilin=%d zsel=%d zman=%d pub=%d"
                   " sd=%d frames=%d playing=%d sel=%03x gm=%d.%02d (PL owns UDP datapath)\r\n",
                   cur_en & 0x1F, cur_thr, cur_src, cur_zoom ? 1 : 0,
                   cur_bilin ? 1 : 0, cur_zsel, cur_zman, (int)pub_lvl,
                   sd_frame_total() ? 1 : 0, (int)sd_frame_total(), sd_is_playing(),
                   cur_sel & 0x1FF,
                   (int)(cur_gamma / 100u), (int)(cur_gamma % 100u));
        return 0;
    }
    if (ci_eq(tk[0], "HELP") || ci_eq(tk[0], "?")) { cmd_help(); return 0; }
    return -1;
}

static void cmd_help(void)
{
    xil_printf("  V8 语法: src 0|1|2 | pipe <5 或 9 位> | th 80 | zoom on|off|auto|<倍率> | bilin on|off |"
               " gamma off|1.8 | frame N | sd | play | stop | fill | autoplay 0|1 | stat | help\r\n");
    xil_printf("  pipe 五位=老位序(gray/binary/blur/sobel/invert)，九位=新位序"
               "(gray/invert/blur/sharpen/sobel/binary/bin_pol/erode/dilate)\r\n");
    xil_printf("  语法已收/硬件待接: rot ... | split ... | osd on|off\r\n");
    xil_printf("  旧写法仍可用: SRC0 SRC1 TH80 ZOOM0 ZOOM1 BILIN0 BILIN1 FRAME12 00111\r\n");
}


/* 一行输入 → 切 token → dispatch()。缓冲区从 32 扩到 48：spec §14 里最长的一条是
 * `split range 20 80`（含回车 18 字节），老尺寸装不下多参数命令。 */
static void uart_poll(void)
{
    static char buf[48];
    static int idx = 0;
    char *tk[T_MAX];
    int nt;

    while (XUartPs_IsReceiveData(STDIN_BASEADDRESS)) {
        u8 ch = XUartPs_RecvByte(STDIN_BASEADDRESS);
        if (ch != '\n' && ch != '\r') {
            if (idx < (int)sizeof(buf) - 1) buf[idx++] = (char)ch;
            continue;
        }
        buf[idx] = 0;
        idx = 0;
        nt = tokenize(buf, tk);
        if (nt == 0) continue;
        if (dispatch(tk, nt) < 0) {
            xil_printf("[CMD] 不认: %s\r\n", buf);
            cmd_help();
        }
    }
}

int main(void)
{
    u32 rb, rb2;

    Xil_ExceptionInit();
    Xil_DCacheEnable();
    Xil_ICacheEnable();
    Xil_ExceptionEnable();

    xil_printf("\r\n[BOOT] video_pipeline PL-UDP control plane\r\n");
    Xil_Out32(GPIO_TRI, 0x00000000u);
    ctrl_apply();

    /* elf 与 bit 配不配套，第一次碰新控制字就能验出来（写一个非零图案再读回来比对，
     * 而不是"读回 0 就算对"——不存在的从设备常常也返回 0，那种判据不会红）。
     * 为什么值得在开机做：地址是硬编码的，位流里没有 axi_gpio_2 时**不会**有编译错误，
     * 现象只是"效果命令全都没反应"，最容易被人当成 RTL 改坏了去查一晚上。 */
    Xil_Out32(CFG_DATA0, 0x1FFu);
    rb = Xil_In32(CFG_DATA0) & 0x1FFu;
    /* V8-8 之后这个字的高半段有人用了（[28:26] 档号、[29] 手动旗标），所以顺手再验一次
     * "这个通道真的是 32 位"。图案故意放在**保留段 [23:9]** 里：探针不许命令硬件 ——
     * 写 [29]=1 会让缩放真的跳一次档（gamma 那条自检同一规矩：图案只验地址，不动功能）。
     * 验到 [22:19] 就等价于验到 [29:26] 在，因为是同一个 GPIO 端口的位。 */
    Xil_Out32(CFG_DATA0, 0x00780000u);
    rb2 = Xil_In32(CFG_DATA0) & 0x00780000u;
    ctrl_write();                        /* 还原走**同一个合成式**：PS 与硬件不许有两套真相 */
    if (rb != 0x1FFu || rb2 != 0x00780000u)
        xil_printf("[CFG!] %08x 写 1ff/780000 读回 %03x/%06x —— 位流里没有新的 axi_gpio_2，"
                   "或它不是 32 位（缩放/分割那些高位会被吞），elf/bit 不配套"
                   "（配套关系见 build/frozen_*）\r\n", CFG_DATA0, rb, rb2 >> 12);
    else
        xil_printf("[CFG] axi_gpio_2 @%08x ok\r\n", CFG_DATA0);

    /* 通道 2（gamma 窗口）也要单独验一次：它是**另一个寄存器**，ch1 活着不代表 ch2 在。
     * 图案故意让 en=0、wr=0 —— 自检不许顺手把 gamma 打开或往表里灌垃圾。 */
    {
        u32 pat = GM_DATA(0x5A) | GM_IDX(0x3C);
        Xil_Out32(CFG_DATA1, pat);
        rb = Xil_In32(CFG_DATA1);
        Xil_Out32(CFG_DATA1, gm_w);       /* 收尾回影子值而不是回 0：这段以后若被挪到 gamma_set
                                             之后跑，回 0 会把 γ×10 那一格抹掉（屏上变 0.0）。 */
        if (rb != pat)
            xil_printf("[CFG!] %08x 写 %08x 读回 %08x —— gamma 窗口不在位流上（elf/bit 不配套）\r\n",
                       CFG_DATA1, pat, rb);
        else
            xil_printf("[CFG] gamma window @%08x ok\r\n", CFG_DATA1);
    }

    xil_printf("[BOOT] UDP RX is in PL (RGMII PHY2). PS is control + SD playback.\r\n");
    xil_printf("[BOOT] uart115200，V8 语法见 help；旧写法仍可用（SRC0/TH80/ZOOM1/00111…）\r\n");

    /* 上电自动挂载 + 起播：不需要任何人敲命令，屏幕就有画面。
     * 与仲裁的分工要写清：自动播放只让 PS 这一路"有货"；屏幕归谁仍是 PL 的 src_arb 决定，
     * 所以插着网线同时推流不会被打扰（ETH 活着时 PS 的发布只是挂起，停流后自动接回）。 */
    if (autoplay) {
        if (sd_mount() == 0) {
            sd_status();
            ctrl_set_src(1);
            if (sd_play(1)) xil_printf("[SD] autoplay: playing\r\n");
        } else {
            xil_printf("[SD] autoplay: mount failed: %s\r\n", sd_err());
        }
    }

    while (1) {
        uart_poll();
        sd_tick();
    }
    return 0;
}
