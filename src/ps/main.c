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
#include "xadcps.h"               /* V8-7 片上温度：PS 侧 XADC，PL 零改动 */
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
/* V8-2 欠到现在的"mode 覆盖位"（2026-09-25 接上）：bit22 = 翻转位，[24:23] = 模式码。
 * 码的取值与 PL 里 src_mode 的编码**必须一致**：00 自动 / 01 ETH / 11 SD / 10 TEST
 * （屏上那三个词就是这一张表，2026-09-25 用户定稿；旧文档里的"锁 PS / 锁图卡"= SD / TEST。）
 * 为什么是 22~24：[4:0] 老五位、[15:8] 阈值、16 src_sel、17 zoom_en、18 publish、19 bilin，
 * [26] gapclr、[31:27] lane 号 ⇒ 20~25 是唯一成片的空位，留 20/21/25 给以后。 */
#define MODE_TOG_BIT  22u
#define MODE_CODE_BIT 23u
#define MODE_AUTO 0u
#define MODE_ETH  1u
#define MODE_SD   3u
#define MODE_TEST 2u

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
/* V8-10（#70 追加）：gamma 只用通道 2 的 [31:8] ⇒ 低 10 位整块空着，rot/osd 就住这里。
 * 便宜在两点：PL 侧不必加输入端口（effect_ctrl 本来就收着整字），也不必新开一对跨域同步器
 * ——只把那条 gm 链从 24 位加宽到 34 位，cdc.rpt 的配对集合一字不动。 */
#define GM_CODE(v)        ((((u32)(v)) & 0xFFu) << 0)      /* 串口角度码：2 度步进 */
#define GM_ROT_OVR        (1u << 8)                        /* 1 = 串口覆盖按键角度 */
#define GM_OSD_OFF        (1u << 9)                        /* 取反放：复位/没写过 = OSD 仍然开 */
#define GM_ROT_MASK       (GM_CODE(0xFFu) | GM_ROT_OVR)
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
static u32 cur_mode_ovr = MODE_AUTO;   /* 0 = 不覆盖（听按键环）；非 0 = 钉住这一路 */
static u32 mode_tog_lvl = 0;

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
      | ((u32)(cur_bilin ? 1 : 0) << BILIN_BIT)
      | ((cur_mode_ovr & 3u) << MODE_CODE_BIT) | (mode_tog_lvl << MODE_TOG_BIT);
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

/* 把片源模式钉到 PL：两次寄存器写，顺序**就是这条改动的全部风险**。
 * 像素域那边（src_mode）看到的是一根翻转位 + 一个两位码，它在翻转沿走到 3 级链的末尾
 * 那一刻才采码 ⇒ 码必须在沿之前就已经稳定。一次 Xil_Out32 同时改码和翻位，对面读到的
 * 可能是"新码 + 还没认的沿"或"旧码 + 已认的沿"，覆盖就白丢了（现象：串口回显成功、屏上没变）。
 * 所以：第一次写只更新码、沿保持原值；第二次写只翻沿。与 ps_publish 的"先写数据再翻发布位"同一课。 */
static void ctrl_publish_mode(u32 code, const char *name)
{
    cur_mode_ovr = code & 3u;
    (void)ctrl_write();            /* 第一笔：码就位，翻转位不动 */
    mode_tog_lvl ^= 1u;
    (void)ctrl_write();            /* 第二笔：翻位 ⇒ 像素域采到的必是上面那个码 */
    xil_printf("[SRC] 已钉住 %s（mode=%u；长按 KEY1 一次即交还给按键环）\r\n", name, code & 3u);
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

/* 长度只认 5 与 9，**6/7/8 一律拒**（2026-09-25 用户报"必须发 8 位才读得到"）。
 * 老写法在这里是有害的：`pipe 00001100`（8 位）过去被当成"9 位前面补一个 0"，
 * 于是用户以为自己设的和屏上显示的是两件事。宁可拒，也不要"看着收了、意思变了"。 */
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
    if (n != 5 && n != 9) return -1;
    *out = en;
    return n;
}

/* 位 → 名字：**只用于串口回显**，位定义的唯一出处仍是 proc_pipeline.v（文件头那条注释）。
 * 之所以要有这一行：屏上 `Pipe:` 那一格是"这一级选中了第几个算法"（0..3，见 osd_overlay.v），
 * 与命令里那 9 个 0/1 不是一一对应的字符串 —— 用户拿命令串去对屏上五位必然对不上。 */
static const char *SEL_NAME[9] = {
    "gray", "invert", "blur", "sharpen", "sobel",
    "binary", "bin_pol", "erode", "dilate"
};

static void print_sel_names(u32 sel)
{
    int i, n = 0;
    xil_printf("[PIPE] sel=%03x 生效:", sel & 0x1FFu);
    for (i = 0; i < 9; i++) {
        if (sel & (1u << i)) { xil_printf(" %s", SEL_NAME[i]); n++; }
    }
    if (n == 0) xil_printf(" none");
    xil_printf("\r\n[PIPE] 屏上那五是**每一级选了第几个算法**（0=无,1/2=该级的两个算法,"
               "3=两位都设了）⇒ 与命令串不是同一个写法，看这一行的名字\r\n");
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
    /* V8-2 的"独占"这一半今天才真的接上：以前这里只动 1 bit src_sel（0=图卡/1=DDR），
     * 然后打印一句"还要 mode 覆盖位"就完事 —— 用户按了没反应、我的脚本也没法保证起点，
     * 2026-09-25 的三条投诉（"切不到 SD""长按要按几次""屏上写的和放的对不上"）根子都在这。
     * 消息里的三个词**就是屏上那三个词**（ETH / SD / TEST，2026-09-25 用户定稿）：
     * 以前这里刻意躲开 CARD/PS，因为屏上那两个词的归属和他念的不一样。歧义已经从源头去掉了。 */
    switch (n) {
    case 0:
        ctrl_set_src(0);
        ctrl_publish_mode(MODE_TEST, "TEST = 片内自绘测试图卡");
        break;
    case 1:
        ctrl_set_src(1);
        ctrl_publish_mode(MODE_ETH, "ETH = 网络推流");
        break;
    case 2:                                             /* SD：也是 DDR，只是把回放踢起来 */
        ctrl_set_src(1);
        if (!sd_play(1)) xil_printf("[SD] play refused: %s\r\n", sd_err());
        ctrl_publish_mode(MODE_SD, "SD = 卡里回放（帧缓存走 DDR）");
        break;
    default:
        xil_printf("[SRC] 只认 auto / 0=TEST 图卡 / 1=ETH 网络 / 2=SD 卡回放（屏上印的就是这三个词）\r\n");
        return;
    }
}

/* ============================ V8-7：片上温度（PS 侧 XADC）============================
 * 为什么读 PS 的 XADC 而不是在 PL 里例化一个 XADC IP：后者会破掉本项目"零厂商 IP"这条
 * 主张（spec §91 把那笔账单独留给 D7 决定），而 PS 侧只是几个寄存器 + BSP 里已有的
 * xadcps 驱动 ⇒ PL 一个 LUT 都不加、CDC 一个触发器都不加。
 * 上电后 XADC 停在 safe mode，TEMP/VCCINT/VCCAUX 本来就在转换 ⇒ 这里只做
 * XAdcPs_CfgInitialize（它干三件事：解锁、置 PS 访问使能位、释放复位），
 * 故意不去改序列器/掉电位：那两位都得走命令/读数据 FIFO 的读-改-写握手，
 * 多一次握手就多一次把 FIFO 弄失步的机会，而这一条只需要"读得出、读得对"。 */
static XAdcPs xadc_inst;
static int    xadc_ok = 0;
static int    temp_th_deg = 85;      /* 告警阈值，°C —— spec 第 3 节 V8-7 写的就是 85 */

/* 不许用 float：xil_printf 不是 libc 的 printf，**不认 %f**（会把 "%f" 原样吐出来）。
 * 所以全程 °C×1000 定点。常数取自驱动宏 XAdcPs_RawToTemperature 的等价式
 *   °C = raw16 × 503.975 / 65536 − 273.15        （raw16 = 内部温度寄存器那个 16 位左对齐字）
 * 65536 = 2^16 ⇒ 乘完只需右移，没有除法；u64 装得下最大乘积 65535×503975 = 3.30e10。 */
static s32 temp_mc_of(u16 raw) { return (s32)((((u64)raw) * 503975ULL) >> 16) - 273150; }
static s32 volt_mv_of(u16 raw) { return (s32)((((u64)raw) * 3000ULL) >> 16); }  /* 满量程 3.0 V */

static void xadc_init(void)
{
#ifdef XPAR_XXADCPS_0_BASEADDR
    XAdcPs_Config *cfg = XAdcPs_LookupConfig(XPAR_XXADCPS_0_BASEADDR);
    if (cfg == NULL) {
        xil_printf("[TEMP] LookupConfig(0x%x) 返回空 ⇒ BSP 的 xadcps 配置表里没有这颗"
                   "（elf 与 BSP 不配套）\r\n", (u32)XPAR_XXADCPS_0_BASEADDR);
        return;
    }
    (void)XAdcPs_CfgInitialize(&xadc_inst, cfg, cfg->BaseAddress);
    xadc_ok = 1;
    xil_printf("[TEMP] PS-XADC @%08x ok\r\n", cfg->BaseAddress);
#else
    xil_printf("[TEMP] BSP 的 xparameters.h 里没有 PS-XADC ⇒ 这颗平台的 PS 配置没开 ADC，"
               "`temp` 只能报读不到\r\n");
#endif
}

/* temp [th <°C>] —— 读一次片上温度；`temp th <n>` 改告警阈值。
 * 阈值为什么可改、而不是钉死 85：判据必须能**人为造红**。室温下的板子永远到不了 85 °C，
 * 于是"接了 XADC 但告警从没亮过"和"根本没接"在串口上长得一模一样。把阈值压到环境以下
 * ⇒ over 必须=1；抬到 200 ⇒ 必须=0 —— 这两条都进了串口电池。
 * sane 是防"看着对其实是常数"的那一条：raw 全 0 会译成 −273.15 °C（永远不会告警、
 * 也不会告第二次），全 F 会译成 230 °C；两个都被 sane 挡下。同时要求 VCCINT 落在
 * 0.8..1.3 V（PS 核标称 1.0 V）—— 读数错位一般先体现在这一路，而不是温度那一格。 */
static void cmd_temp(int n, char **tk)
{
    u16 rt, rv;
    s32 mc, mv, th, a;
    int over, sane;

    if (n >= 2 && ci_eq(tk[1], "TH")) {
        const char *arg = (n >= 3) ? tk[2] : tk[1] + 2;    /* `temp th 60` 与 `temp th60` */
        if (!strict_int(arg, &temp_th_deg) || temp_th_deg < 0 || temp_th_deg > 200) {
            temp_th_deg = 85;
            xil_printf("[TEMP] th 要跟十进制 0..200（°C），已退回 85\r\n");
            return;
        }
        xil_printf("[TEMP] th=%dC\r\n", temp_th_deg);
        return;
    }
    if (n >= 2) { xil_printf("[TEMP] 只认 `temp` 或 `temp th <0..200>`\r\n"); return; }
    if (!xadc_ok) { xil_printf("[TEMP] 读不到（开机那行 [TEMP] 说了为什么）raw=NA\r\n"); return; }

    rt = XAdcPs_GetAdcData(&xadc_inst, XADCPS_CH_TEMP);
    rv = XAdcPs_GetAdcData(&xadc_inst, XADCPS_CH_VCCINT);
    mc = temp_mc_of(rt);
    mv = volt_mv_of(rv);
    th = (s32)temp_th_deg * 1000;
    over = (mc >= th) ? 1 : 0;
    sane = (mc > 0 && mc < 80000 && mv > 800 && mv < 1300) ? 1 : 0;
    a = (mc < 0) ? -mc : mc;
    xil_printf("[TEMP] degC=%d.%02d raw=0x%04x vccint=%dmv th=%dC over=%d sane=%d\r\n",
               (int)(mc / 1000), (int)((a / 10) % 100), rt, mv, temp_th_deg, over, sane);
    if (!sane)
        xil_printf("[TEMP!] raw=%04x 译出来 %d.%02d °C 不像一次真实转换 ⇒ "
                   "FIFO 握手或 XADC 复位有问题，这一格的数不许写进报告\r\n", rt, (int)(mc / 1000),
                   (int)((a / 10) % 100));
}

static int dispatch(char **tk, int nt)
{
    u32 en;
    int v;
    int nb;

    nb = parse_bits(tk[0], &en);
    if (nt == 1 && nb > 0) { apply_pipe_bits(en, nb); print_sel_names(cur_sel); return 0; }

    if (ci_eq(tk[0], "PIPE")) {
        if (nt >= 2 && ci_eq(tk[1], "SHOW")) { print_sel_names(cur_sel); return 0; }
        nb = (nt >= 2) ? parse_bits(tk[1], &en) : -1;
        if (nb <= 0) {
            xil_printf("[PIPE] 长度只收 **5（老位序）或 9（新位序）**，其余一律不认"
                       "（6/7/8 位过去被当成 9 位补零，屏上就对不上）。例：pipe 000000100 /"
                       " pipe show\r\n");
            return 0;
        }
        apply_pipe_bits(en, nb);
        print_sel_names(cur_sel);
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
         * 所以这里改成"整串交给 strict_int"，不再按下标取字符。
         * `auto` 是 2026-09-25 新加的：用户报"锁住之后只能长按三次才出来"，需要一个出口。 */
        const char *arg = (nt >= 2) ? tk[1] : tk[0] + 3;
        if (ci_eq(arg, "AUTO")) ctrl_publish_mode(MODE_AUTO, "自动（控制权交还按键环）");
        else if (strict_int(arg, &v)) cmd_src(v);
        else xil_printf("[SRC] 只认 auto / 0=图卡 1=网络 2=SD\r\n");
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
    if (ci_eq(tk[0], "ROT")) {
        /* V8-10：串口覆盖按键角度。2 度步进是**位宽换简单**（#70 追加），不是硬件只能 2 度
         * （sin/cos ROM 是 0..359 全表）。所以奇数度不许静默向下取整（#67 那族"半个接受"）：
         * 这里收，但把"实际生效值"念回来，并说明 1 度这一步仍要走按键（`rot auto` 交还）。 */
        u32 eff, code;
        if (nt >= 2 && ci_eq(tk[1], "AUTO")) {
            gm_w &= ~GM_ROT_MASK;
            Xil_Out32(CFG_DATA1, gm_w);
            xil_printf("[ROT] auto：覆盖关闭，角度交还按键（KEY1/KEY2 仍是 1 度一步）\r\n");
            return 0;
        }
        if (nt >= 2 && strict_int(tk[1], &v) && v >= 0 && v <= 359) {
            eff  = ((u32)v) & ~1u;
            code = eff >> 1;
            gm_w = (gm_w & ~GM_ROT_MASK) | GM_CODE(code) | GM_ROT_OVR;
            Xil_Out32(CFG_DATA1, gm_w);
            if (eff != (u32)v)
                xil_printf("[ROT] %d -> %u（串口步进 2 度；要 1 度先 rot auto 交给按键）覆盖=开\r\n",
                           v, (unsigned)eff);
            else
                xil_printf("[ROT] %u 覆盖=开（2 度步进；rot auto 交还按键）\r\n", (unsigned)eff);
            return 0;
        }
        xil_printf("[ROT] 只认 `rot <0..359>` 或 `rot auto`；当前覆盖=%s\r\n",
                   (gm_w & GM_ROT_OVR) ? "已开" : "未开（按键说了算）");
        return 0;
    }
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
    if (ci_eq(tk[0], "OSD")) {
        /* V8-10：关的是"画不画字"这一件事。PL 里 `en` 只挡 in_char，de/hs/vs 的节拍一字不变，
         * 所以关掉之后画面不会跟着错位——这也是当初不在顶层另接一条旁路的原因。 */
        if (nt >= 2 && strict_int(tk[1], &v) && (v == 0 || v == 1)) {
            if (v) gm_w &= ~(u32)GM_OSD_OFF; else gm_w |= (u32)GM_OSD_OFF;
            Xil_Out32(CFG_DATA1, gm_w);
            xil_printf("[OSD] %s（off = 四行字都不画，画面与同步一个字都不动）\r\n",
                       v ? "on" : "off");
            return 0;
        }
        xil_printf("[OSD] 只认 `osd 0` 或 `osd 1`；当前 %s\r\n",
                   (gm_w & GM_OSD_OFF) ? "off" : "on");
        return 0;
    }

    if (ci_pre(tk[0], "FRAME")) {
        const char *arg = (nt >= 2) ? tk[1] : tk[0] + 5;   /* frame 12 / FRAME12 */
        if (!strict_int(arg, &v) || v < 0) { xil_printf("[SD] frame 要跟十进制帧号\r\n"); return 0; }
        if (sd_show((u32)v) != 0) { xil_printf("[SD] frame %d failed: %s\r\n", v, sd_err()); return 0; }
        ctrl_set_src(1);
        return 0;
    }
    if (ci_eq(tk[0], "SD")) {
        /* V8-9：`sd files` 列出卡上每段（名字/帧数/首帧全局号），`sd file <n>` 跳到那段的第一帧。
         * 为什么不该让人算 `frame 900`：段表本来就在固件里（META.TXT 解析出来的），
         * 把"每段多少帧"背在操作者身上，等于把我算错的账转到演示现场。
         * 不认识的子命令、越界的段号一律明确拒绝且不改任何状态（#67）。
         */
        if (nt >= 2 && ci_eq(tk[1], "FILES")) {
            u32 i, nf = sd_file_count();
            if (nf == 0u) { xil_printf("[SD] files: 卡还没挂载（先敲 sd）\r\n"); return 0; }
            xil_printf("[SD] %u file(s), %u frame(s) total\r\n",
                       (unsigned)nf, (unsigned)sd_frame_total());
            for (i = 0; i < nf; i++)
                xil_printf("  #%u %s %u frame(s) first=%u\r\n",
                           (unsigned)i, sd_file_name(i), (unsigned)sd_file_frames(i),
                           (unsigned)sd_file_first(i));
            return 0;
        }
        if (nt >= 2 && ci_eq(tk[1], "FILE")) {
            u32 nf = sd_file_count();
            if (nt < 3 || !strict_int(tk[2], &v) || v < 0 || (u32)v >= nf) {
                xil_printf("[SD] file 只认 0..%u（不认的写法不改任何状态；先看 sd files）\r\n",
                           nf ? (unsigned)(nf - 1u) : 0u);
                return 0;
            }
            if (sd_show(sd_file_first((u32)v)) != 0) {
                xil_printf("[SD] file %u 跳帧失败: %s\r\n", (unsigned)v, sd_err());
                return 0;
            }
            ctrl_set_src(1);
            xil_printf("[SD] file #%u %s (%u frame(s)) first=%u\r\n", (unsigned)v,
                       sd_file_name((u32)v), (unsigned)sd_file_frames((u32)v),
                       (unsigned)sd_file_first((u32)v));
            return 0;
        }
        if (nt >= 2) {
            xil_printf("[SD] sd 只认：（裸=挂载并打摘要）/ files / file n；其余 play stop frame autoplay\r\n");
            return 0;
        }
        if (sd_mount() == 0) sd_status();
        else xil_printf("[SD] mount failed: %s\r\n", sd_err());
        return 0;
    }
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
    if (ci_pre(tk[0], "TEMP")) { cmd_temp(nt, tk); return 0; }
    if (ci_eq(tk[0], "STAT") || ci_eq(tk[0], "STATUS")) {
        /* 字段顺序不许动：串口电池与 arb_handover_test.mjs 都按 "ctrl en=… thr=…" 的前缀解析，
         * 新加的 sel / gm 只能往后放。en 是老五位的投影，sel 才是效果链的真相，
         * gm=0.00 表示 gamma 关（PL 那一侧逐位旁路）。 */
        xil_printf("[STAT] ctrl en=%02x thr=%d src=%d zoom=%d bilin=%d zsel=%d zman=%d pub=%d"
                   " sd=%d frames=%d playing=%d sel=%03x gm=%d.%02d (PL owns UDP datapath)"
                   " mode=%d\r\n",
                   cur_en & 0x1F, cur_thr, cur_src, cur_zoom ? 1 : 0,
                   cur_bilin ? 1 : 0, cur_zsel, cur_zman, (int)pub_lvl,
                   sd_frame_total() ? 1 : 0, (int)sd_frame_total(), sd_is_playing(),
                   cur_sel & 0x1FF,
                   (int)(cur_gamma / 100u), (int)(cur_gamma % 100u), (int)cur_mode_ovr);
        return 0;
    }
    if (ci_eq(tk[0], "HELP") || ci_eq(tk[0], "?")) { cmd_help(); return 0; }
    return -1;
}

static void cmd_help(void)
{
    xil_printf("  V8 语法: src auto|0|1|2 | pipe <5 或 9 位>|pipe show | th 80 | zoom on|off|auto|<倍率> | bilin on|off |"
               " gamma off|1.8 | frame N | sd | play | stop | fill | autoplay 0|1 | temp [th <°C>] |"
               " stat | help\r\n");
    xil_printf("  pipe 五位=老位序(gray/binary/blur/sobel/invert)，九位=新位序"
               "(gray/invert/blur/sharpen/sobel/binary/bin_pol/erode/dilate)，**其余长度一律拒**\r\n");
    xil_printf("  屏上 Pipe 那一格不是这串 0/1：它是五位、每位的 0..3 表示\"这一级选了第几个算法\"，"
               "想知道现在开着什么就敲 pipe show\r\n");
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

    /* V8-7：把 PS-XADC 拉起来放在自动播片之前 —— 它只做解锁+使能+释放复位，
     * 不碰 DDR 也不碰 SD；失败一定要在开机就看得见，而不是等谁敲 `temp` 才发现"读不到"。 */
    xadc_init();

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
