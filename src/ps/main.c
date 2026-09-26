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
#include "xiltimer.h"             /* V9-5 的 gamma Auto：XTime / XTime_GetTime / COUNTS_PER_SECOND
                                   * —— 与 sd_play.c 用的是同一个入口（`xtime_l.h` 不在这套手搓
                                   * app 的 -I 列表里，今天第一次编译就报 No such file） */
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

/* #51：分割线控制位。位图唯一出处 = ISSUES #70 追加；PL 侧对应 pl_video_top 的 split_ctl。
 *   [22:13] pos_px（显示列 0..1024）、[23] auto_en、[24] follow、[25] swap、[30] marker_off
 *   这 14 位在 PL 里一起过 snap_cross（#71：不许并进 effect_ctrl 那条已批准的同步链） */
#define SPLIT_POS_SHIFT   13u
#define SPLIT_POS_MASK    (0x3FFu << SPLIT_POS_SHIFT)
#define SPLIT_POS_MAX     1023u   /* 字段只有 10 位，而**屏幕宽是 1024** ⇒ 见下面这两条 ⚠（都在板上复现过）
                                   *  1024 << 13 = 0x800000 = bit23 = SPLIT_AUTO_BIT，症状按写口分两种：
                                   *   ① `split 100` / `split px 1024`：紧接着的 `&= ~SPLIT_AUTO_BIT` 把误置的
                                   *      auto 清掉了，留下的是**缝位变成 0** —— 要"整屏处理图"得到"整屏原图"，
                                   *      而回显写着 pos=1024/1024 100%（build/probe_split100_old.txt）。
                                   *   ② `split video` + `split px 512` 再 `split screen`：这条写口**不清 auto**，
                                   *      于是缝跳到第 0 列 + 自动扫描**悄悄开起来**，回显还说"auto 仍开着"
                                   *      （build/probe_split100b_old.txt）。
                                   *  cfg1 三十二位已经排满（[8:0] 效果、[12:9] 旋转、[22:13] 缝位、
                                   *  [25:23] 三个旗标、[28:26] 缩放档、[29] 手动、[30] 蓝线、[31] 拟合），
                                   *  塞不进第 11 位 ⇒ 在 PS 侧夹住并**明说夹了**：
                                   *  差的这一列是 1/1024，比"用户没要求却开了扫描"轻得多。 */
#define SPLIT_AUTO_BIT    (1u << 23)
#define SPLIT_FOLLOW_BIT  (1u << 24)
#define SPLIT_SWAP_BIT    (1u << 25)
#define SPLIT_MARKOFF_BIT (1u << 30)
#define SPLIT_MASK        (SPLIT_POS_MASK | SPLIT_AUTO_BIT | SPLIT_FOLLOW_BIT | SPLIT_SWAP_BIT | SPLIT_MARKOFF_BIT)
#define SPLIT_DISP_W      1024u            /* 整屏一个视口（r59b-1）：缝位单位 = 显示列 */
#define SPLIT_LO16_DEF    2u               /* 扫描端点与速度是构建参数（顶层 SPLIT_LO16/HI16/SPEED） */
#define SPLIT_HI16_DEF    14u
static u32 cur_split = (512u << SPLIT_POS_SHIFT);   /* 默认缝在正中 = 旧行为 */

/* V9（2026-09-25）：几何控制字里**新加的 5 位** —— 自动旋转 + "按角度定缩放"。
 *   cfg1[9] = rot_auto，cfg1[12:10] = rot_speed（每帧几个度），cfg1[31] = zoom_fit
 * 为什么挤进同一个字，而不是新开一个 GPIO 通道或第二个寄存器：PL 侧这 19 位走的是
 * **同一条** snap_cross（#71 的预算账）。新开一条跨域路就要多一对 bus/toggle 同步器，
 * 而"一个发射触发器扇出到两组目的域"正是 CDC-11 Critical 的签名（#65 与 r54 构建 #34
 * 各为它红过一次门禁）。
 * ⚠ 位图现在有三处读者，改任何一处必须同一次把三处改完：这里的宏、
 *   pl_video_top 的 split_ctl 端口注释、report/ISSUES.md #70 追加。 */
#define ROT_AUTO_BIT    (1u << 9)
#define ROT_SPEED_SHIFT 10u
#define ROT_SPEED_MASK  (7u << ROT_SPEED_SHIFT)
#define ZOOM_FIT_BIT    (1u << 31)
#define GEOM_MASK       (SPLIT_MASK | ROT_AUTO_BIT | ROT_SPEED_MASK | ZOOM_FIT_BIT)
#define SPLIT_SRC_W     512u   /* follow=1 时缝位与百分比量的都是**画面宽**，不是屏宽 */

/* 缝位写进寄存器之前夹一道，返回 1 = 夹过（调用方**必须**在回显里说出来）。
 * 为什么由调用方打印而不是这里打印：三处写口的文案各自不同，而"夹了"必须与
 * 那一处报出的百分比同源（#66：回声与执行值不同源是这一族病的签名）。 */
static u32 split_pos_clamp(u32 *px) {
    if (*px <= SPLIT_POS_MAX) return 0;
    *px = SPLIT_POS_MAX;
    return 1;
}
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
               | ((u32)(cur_zsel & 7u) << 26) | ((u32)(cur_zman ? 1u : 0u) << 29)
               | (cur_split & GEOM_MASK));  /* #51 的 14 位 + V9 的 5 位，同一个字、同一条 snap_cross */
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

/* ---- V9-5：gamma 的 Auto ----
 * 用户 2026-09-25：「Gamma 设置：我们可以给它做一个 Auto 模式，让它在一段数值里面自动来回
 * 切换；或者我们也可以通过窗口命令去发送来指定它。」后半句本来就是 `gamma 1.8`，这一条补前半句。
 * 为什么在 PS 扫、不在 PL 扫：γ 表是 PS 通过 GPIO 的 idx/data 窗口一项一项灌进去的（V8-3 的
 * 设计），PL 那边只有一张表和一个写口，没有第二条曲线发生器 ⇒ 在 PS 扫 = 零新增硬件、
 * 零时序风险（本项目的教训 #58：往 100 MHz/50 MHz 域里塞算术之前先问一句值不值）。
 * 代价说清楚：它只在主循环转到 gamma_tick() 时推进，而 gamma_set 一次要写 256 项（约 5 ms，
 * 还打一行日志），所以节奏门限卡在 200 ms，默认 2 s 一步。 */
static void gamma_set(u32 g100);       /* 前向声明，真正的定义在下面 */

/* ---- 串口命令的"保命缓冲"：收字节与切派发分开 ----
 * 为什么要拆开：`gamma_set` 一次要写 256 项、每项两次 usleep(5) ⇒ 约 2.6 ms **不回主循环**，
 * 而 115200 波特下 Zynq 的 RX FIFO 只有 16 字节（≈1.4 ms 的量）。人把一整行**粘**进来时，
 * 这 2.6 ms 里到的字节就从 FIFO 漏掉了 —— 用户报的"命令要发好几次才有反应"，真会丢字符的是这一段
 * （另一个原因是老实现不回显，看不见自己敲了什么，那是错觉不是丢包）。
 * ⇒ `rx_fill()` 只把人来的字节搬进 cmd_buf（顺手回显），**不切不派发**；长流程里反复调它，
 *   主循环的 uart_poll() 再把攒下的整行按顺序派发。这样既不在 gamma 的中途改参数（那是重入），
 *   也不丢字符。 */
#define CMD_BUF 128                     /* 旧值 48 且**静默截断**：超长行会被啃掉尾巴还当正常行派发 */
static char cmd_buf[CMD_BUF];
static int  cmd_len = 0;                /* 已收字节数（含行尾 '\n'） */
static u8   cmd_toolong = 0;            /* 一次超长只报一条，不许刷屏 */
static void rx_fill(void);              /* 只搬运不派发 */
static u8  gm_auto = 0;
static u32 gm_lo = 100u, gm_hi = 300u, gm_step = 20u, gm_ms = 2000u;
static int gm_dir = 1;
static XTime gm_t0;

static void gamma_auto_start(u32 lo, u32 hi, u32 step, u32 ms)
{
    if (lo < 100u || hi > 300u || hi <= lo || step == 0u || step > (hi - lo) || ms < 200u) {
        xil_printf("[GAMMA] auto 的账：100<=lo<hi<=300、0<step<=hi-lo、ms>=200"
                   "（收到 lo=%d hi=%d step=%d ms=%d）\r\n",
                   (int)lo, (int)hi, (int)step, (int)ms);
        return;
    }
    gm_lo = lo; gm_hi = hi; gm_step = step; gm_ms = ms; gm_dir = 1;
    gamma_set(lo);
    XTime_GetTime(&gm_t0);
    gm_auto = 1;
    xil_printf("[GAMMA] auto：%d.%02d..%d.%02d，每 %d ms 走 %d.%02d"
               "（停：gamma manual，或直接 gamma <数>）\r\n",
               (int)(lo / 100u), (int)(lo % 100u),
               (int)(hi / 100u), (int)(hi % 100u), (int)ms,
               (int)(step / 100u), (int)(step % 100u));
}

/* 主循环里每圈问一次；没到时间就立刻返回，不挡 uart_poll / sd_tick。 */
static void gamma_tick(void)
{
    XTime now;
    u32   g;
    if (!gm_auto) return;
    XTime_GetTime(&now);
    if ((u64)(now - gm_t0) * 1000u < (u64)gm_ms * (u64)COUNTS_PER_SECOND) return;
    XTime_GetTime(&gm_t0);
    g = cur_gamma ? cur_gamma : gm_lo;
    if (gm_dir > 0) {
        if (g + gm_step >= gm_hi) { g = gm_hi; gm_dir = -1; }
        else                      { g = g + gm_step; }
    } else {
        if (g <= gm_lo + gm_step) { g = gm_lo; gm_dir = 1; }
        else                      { g = g - gm_step; }
    }
    gamma_set(g);
}

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
    gm_auto = 0;                        /* 手动出口永远先把 Auto 停掉：不许"关了还在扫" */
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
        rx_fill();      /* 这 256 项要写约 2.6 ms：中途只搬 UART 字节不派发，否则粘进来的行会丢字 */
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
/* T_MAX：一条命令最多切成几个 token。
 * V9-5 之前是 4 —— 那时最长的命令是 `split range 20 80` 这种"动词 + 2 参数"。
 * 现在 `gamma auto 1.20 2.60 20 1500` 要 6 个 token，而 tokenize 是**静默截断**的：
 * 超出的参数不会被看见，于是"我明明设了步长，它却按默认步长走"——那正是 #67 禁止的
 * "收了但什么都不做"。所以抬到 8（留两个余量），并且真正的上限其实由 `buf[48]` 管：
 * 48 字节里塞不下 9 个有内容的 token。 */
#define T_MAX 8

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
        if (ci_eq(arg, "FIT")) {
            /* V9-2：把倍率交给**角度**定（zoom_fit.v：转多少就缩多少，画面永远整幅在屏内）。
             * 与 `zoom auto`（呼吸）/`zoom <倍率>`（手动）是并列的第三种来源，屏上那一格
             * 分别标 (Auto) / 什么都不标 / (Fit) ⇒ 观众看见的后缀就是此刻真的那一路。 */
            int on = 1, iv;
            if (nt >= 3) {
                if (!strict_int(tk[2], &iv) || (iv != 0 && iv != 1)) {
                    xil_printf("[ZOOM] fit 只认 0 或 1（1 = 倍率跟着角度走）\r\n"); return 0;
                }
                on = iv;
            }
            if (on) cur_split |= ZOOM_FIT_BIT; else cur_split &= ~ZOOM_FIT_BIT;
            ctrl_apply();
            xil_printf("[ZOOM] fit=%d（%s；关掉之后回到%s）\r\n", on,
                       on ? "此刻真的在用的 inv 由角度算出来，屏上 Zoom 格标 (Fit)" : "不再由角度定",
                       cur_zman ? "手动档" : "呼吸自动档");
            return 0;
        }
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
        if (nt >= 2 && ci_eq(tk[1], "SHOW")) {
            /* 为什么要把"什么时候才看得出差别"一起印出来：这个开关在**旋转态**与**1.00 倍**下
             * 按构造都不改变任何一个像素（`zoom_mapper.v:73-74` 旋转通路把 frac 钉 0；1:1 时 frac 天生 0），
             * 所以只说"bilin=1"会让人以为开关坏了 —— 那是 ISSUES #86，不是这条命令坏了。 */
            xil_printf("[BILIN] bilin=%s（gpio_o[19]）；看得出的条件：角度=0 且倍率非整数，"
                       "例：src 0 → zoom 1.5 → bilin off/on（旋转态与本档 1.00 按构造无差别）\r\n",
                       cur_bilin ? "on" : "off");
            return 0;
        }
        if (strict_int(arg, &v) && (v == 0 || v == 1)) b = v;
        if (ci_eq(arg, "ON")) b = 1;
        if (ci_eq(arg, "OFF")) b = 0;
        if (b < 0) xil_printf("[BILIN] 只认 on/off（0/1）或 show\r\n");
        else {
            ctrl_set_bilin((u8)b);
            xil_printf("[BILIN] bilin=%s\r\n", cur_bilin ? "on" : "off");
        }
        return 0;
    }
    /* —— 以下四个是 spec §14 里还没落地的动词：先把语法收住，出口只有一条 —— */
    if (ci_eq(tk[0], "ROT")) {
        /* V9-3（2026-09-25）：rot 从"语法已收、硬件待接"变成真的动词。
         * 用户要的是「增加一个 Auto 旋转模式，让它自己在那转」+「我们人可以控制的是旋转的
         * 速度或角度」。角度本身仍然只活在 PL 的 angle_ctrl 里（按键 ±1° 那条路一个字没动），
         * 这里发出去的是"要不要自动转 / 每帧几个度"两个控制位。
         * ⚠ 有意**没有** `rot 37` 这种"设成某个绝对角度"：那需要一个 9 位写窗口 + 一次跨域
         *   同步（新硬件、新时序账），而 ±1° 的按键已经能把角度带到 0..359 的任何一格；
         *   真要"从 0 开始转一整圈"用 rot auto + 看着它转回去就够了。 */
        int iv;
        if (nt >= 2 && ci_eq(tk[1], "SHOW")) {
            xil_printf("[ROT] auto=%u speed=%u deg/frame %s（KEY1/KEY2 的 ±1° 一直有效）\r\n",
                       (unsigned)((cur_split & ROT_AUTO_BIT) ? 1u : 0u),
                       (unsigned)((cur_split & ROT_SPEED_MASK) >> ROT_SPEED_SHIFT),
                       (cur_split & ZOOM_FIT_BIT) ? "zoom=fit" : "zoom=now");
            return 0;
        }
        if (nt >= 3 && ci_eq(tk[1], "SPEED")) {
            if (!strict_int(tk[2], &iv) || iv < 0 || iv > 7) {
                xil_printf("[ROT] speed 只认 0..7（每帧几个度：60 fps 下 1≈6 s 一圈，7≈0.9 s 一圈；"
                           "0 = 自动开着但不走）\r\n");
                return 0;
            }
            cur_split = (cur_split & ~ROT_SPEED_MASK) | (((u32)iv) << ROT_SPEED_SHIFT);
            ctrl_apply();
            xil_printf("[ROT] speed=%d 度/帧\r\n", iv);
            return 0;
        }
        if (nt >= 2 && (ci_eq(tk[1], "AUTO") || ci_eq(tk[1], "ON") || ci_eq(tk[1], "OFF")
                        || ci_eq(tk[1], "0") || ci_eq(tk[1], "1"))) {
            int on = (ci_eq(tk[1], "OFF") || ci_eq(tk[1], "0")) ? 0 : 1;
            if (nt >= 3 && (!strict_int(tk[2], &iv) || (iv != 0 && iv != 1))) {
                xil_printf("[ROT] auto 只认 0 或 1\r\n"); return 0;
            }
            if (nt >= 3) on = iv;
            if (on) {
                cur_split |= ROT_AUTO_BIT;
                if (!(cur_split & ROT_SPEED_MASK))
                    cur_split = (cur_split & ~ROT_SPEED_MASK) | (2u << ROT_SPEED_SHIFT);
                if (!(cur_split & ZOOM_FIT_BIT)) {
                    /* 用户指定的成对语义：「在这个模式下，缩放就一直设为 Auto，根据旋转的角度
                     * 来自动控制缩放的比例」⇒ 开自动旋转就同时把缩放交给拟合，一次命令到位。 */
                    cur_split |= ZOOM_FIT_BIT;
                    xil_printf("[ROT] auto=1：顺带把缩放切到 fit（屏上 Zoom 格标 (Fit)）；"
                               "不想这样就先 zoom fit 0 再 rot auto 1\r\n");
                } else {
                    xil_printf("[ROT] auto=1\r\n");
                }
            } else {
                cur_split &= ~ROT_AUTO_BIT;
                xil_printf("[ROT] auto=0（停在当前角度；缩放那一路不变）\r\n");
            }
            ctrl_apply();
            return 0;
        }
        xil_printf("[ROT] 只认：rot auto [0|1] | rot speed <0..7> | rot show\r\n"
                   "       （角度仍然用 KEY1/KEY2 ±1°；`rot auto 1` 会同时开缩放拟合）\r\n");
        return 0;
    }
    if (ci_eq(tk[0], "SPLIT")) {
        /* #51：分割线真的可动了。单位是**显示列**（整屏 1024，r59b-1），屏上第四行 `Split:`
         * 印的就是同一位换算出来的百分比 —— 发的、执行的、屏上写的三处同源（#66 那一族的病）。 */
        u32 pos = (cur_split & SPLIT_POS_MASK) >> SPLIT_POS_SHIFT;
        /* V9-1：`follow 1` 之后缝位量的是**画面**的列（PL 里 split_ctrl 的 W 跟着换成 SRC_W），
         * 所以 PS 这一侧的百分比与 px 必须一起换坐标空间。不换的症状很具体：
         * `split 60` 在 follow 下算出 px=614，而 PL 把 eff 夹进 [0,512] ⇒ 缝钉死在画面右端，
         * 屏上 Split 格却印 60% —— 那就是"发的、执行的、屏上写的"三处不同源（#66 那一族的病）。 */
        u32 w      = (cur_split & SPLIT_FOLLOW_BIT) ? SPLIT_SRC_W : SPLIT_DISP_W;
        int b, pct;
        if (nt >= 2 && ci_eq(tk[1], "SHOW")) {
            xil_printf("[SPLIT] pos=%u/%u（%s） = %u%% %s%s%s marker=%s\r\n",
                       (unsigned)pos, (unsigned)w,
                       (cur_split & SPLIT_FOLLOW_BIT) ? "画面列" : "显示列",
                       (unsigned)((pos * 100u) / w),
                       (cur_split & SPLIT_AUTO_BIT) ? "auto" : "manual",
                       (cur_split & SPLIT_FOLLOW_BIT) ? "follow " : "",
                       (cur_split & SPLIT_SWAP_BIT) ? "swap(原图在右) " : "",
                       (cur_split & SPLIT_MARKOFF_BIT) ? "off" : "on");
            return 0;
        }
        if (nt >= 2 && ci_eq(tk[1], "AUTO")) {
            cur_split |= SPLIT_AUTO_BIT; ctrl_apply();
            xil_printf("[SPLIT] auto：缝在 [%u..%u]/16 宽度之间自动扫（%s；速度与端点是构建参数；"
                       "`split range`/`speed` 仍待接）\r\n",
                       (unsigned)SPLIT_LO16_DEF, (unsigned)SPLIT_HI16_DEF,
                       (cur_split & SPLIT_FOLLOW_BIT) ? "follow=1 ⇒ 扫的是画面的两端，线跟着画面转"
                                                      : "follow=0 ⇒ 扫的是屏幕的左右");
            return 0;
        }
        if (nt >= 2 && ci_eq(tk[1], "MANUAL")) {
            cur_split &= ~SPLIT_AUTO_BIT; ctrl_apply();
            xil_printf("[SPLIT] manual：停在 pos=%u（屏上 Split 格不再标 Auto）\r\n", (unsigned)pos);
            return 0;
        }
        if (nt >= 3 && (ci_eq(tk[1], "SWAP") || ci_eq(tk[1], "FOLLOW") || ci_eq(tk[1], "MARKER"))) {
            u32 bit = ci_eq(tk[1], "SWAP") ? SPLIT_SWAP_BIT
                      : ci_eq(tk[1], "FOLLOW") ? SPLIT_FOLLOW_BIT : SPLIT_MARKOFF_BIT;
            if (!strict_int(tk[2], &b) || (b != 0 && b != 1)) {
                xil_printf("[SPLIT] %s 只认 0 或 1\r\n", tk[1]); return 0;
            }
            if (ci_eq(tk[1], "MARKER")) {           /* marker 语义是"画不画"，位是 marker_off：取反 */
                if (b) cur_split &= ~bit; else cur_split |= bit;
            } else {
                if (b) cur_split |= bit; else cur_split &= ~bit;
            }
            ctrl_apply();
            /* V9-1 起 follow 是**真的**换判据空间（seam_src 在图像列里分类），不再只是换扫描坐标系 */
            xil_printf("[SPLIT] %s=%d（%s）\r\n", tk[1], b,
                       ci_eq(tk[1], "SWAP") ? "只换内容，不换缝位"
                       : ci_eq(tk[1], "FOLLOW") ? "1 = 缝量在画面列里：线长在画面上、跟着旋转一起转"
                                                : "那条 2 像素蓝线");
            return 0;
        }
        /* V9-1b（用户 2026-09-25 晚的用语：「蓝线在屏幕上扫和在视频里面扫这两种效果，
         * 可以通过串口命令来控制它进行切换」）：给这一位两个说人话的入口 ——
         *   `split screen` = 缝在**屏幕**里左右扫；`split video` = 缝在**画面**里扫、跟着转。
         * 与 `split follow 0|1` 是**同一个位**，不新增编码、不改硬件行为。
         * 换空间时把缝位按百分比搬过去（614/1024 → 307/512）：老空间那个绝对列号
         * 在新空间没有意义，PL 会把它夹到边界 ⇒ 症状是"一切换线就贴边"。 */
        if (nt >= 2 && (ci_eq(tk[1], "SCREEN") || ci_eq(tk[1], "VIDEO"))) {
            u32 video = ci_eq(tk[1], "VIDEO") ? 1u : 0u;
            u32 w_old = (cur_split & SPLIT_FOLLOW_BIT) ? SPLIT_SRC_W : SPLIT_DISP_W;
            u32 w_new = video ? SPLIT_SRC_W : SPLIT_DISP_W;
            u32 pct   = ((pos * 100u) / w_old) * w_new / 100u;
            if (pct > w_new) pct = w_new;
            u32 cl3 = split_pos_clamp(&pct);
            cur_split = (cur_split & ~SPLIT_POS_MASK) | (pct << SPLIT_POS_SHIFT);
            if (video) cur_split |= SPLIT_FOLLOW_BIT; else cur_split &= ~SPLIT_FOLLOW_BIT;
            ctrl_apply();
            xil_printf("[SPLIT] %s：缝在%s里扫，pos=%u/%u = %u%%%s%s\r\n", tk[1],
                       video ? "**画面**列（线跟着旋转走，端点是画面的两端）" : "显示列（屏幕左右扫）",
                       (unsigned)pct, (unsigned)w_new, (unsigned)((pct * 100u) / w_new),
                       (cur_split & SPLIT_AUTO_BIT) ? "，auto 仍开着" : "",
                       cl3 ? "（缝位已夹到 10 位上限 1023）" : "");
            return 0;
        }
        if (nt >= 3 && ci_eq(tk[1], "PX")) {
            if (!strict_int(tk[2], &pct) || pct < 0 || (u32)pct > w) {
                xil_printf("[SPLIT] px 只认 0..%u（当前是%s空间）\r\n", (unsigned)w,
                           (cur_split & SPLIT_FOLLOW_BIT) ? "画面列" : "显示列"); return 0;
            }
            u32 px2 = (u32)pct, cl2 = split_pos_clamp(&px2);
            cur_split = (cur_split & ~SPLIT_POS_MASK) | (px2 << SPLIT_POS_SHIFT);
            cur_split &= ~SPLIT_AUTO_BIT; ctrl_apply();
            xil_printf("[SPLIT] pos=%u px = %u%%%s（manual）\r\n", (unsigned)px2,
                       (unsigned)(((u32)px2 * 100u) / w),
                       cl2 ? "（已夹到 10 位上限 1023）" : "");
            return 0;
        }
        if (nt >= 2 && strict_int(tk[1], &pct) && pct >= 0 && pct <= 100) {
            u32 px = ((u32)pct * w) / 100u;                /* 除法只在 PS 做一次，PL 无除法器（#58） */
            u32 cl = split_pos_clamp(&px);                 /* 100% 在屏幕空间会算出 1024 ⇒ 见 SPLIT_POS_MAX */
            cur_split = (cur_split & ~SPLIT_POS_MASK) | (px << SPLIT_POS_SHIFT);
            cur_split &= ~SPLIT_AUTO_BIT; ctrl_apply();
            /* 最后那个百分比由**存进去的值**反算，不再回显用户输入的 pct：
             * 夹过的时候屏上那一格印的就是 99，回显 100 就是"发的与执行的不同源"。 */
            xil_printf("[SPLIT] %d%% -> pos=%u/%u（%s；manual；屏上 Split 格应显示 %u%%%s）\r\n",
                       pct, (unsigned)px, (unsigned)w,
                       (cur_split & SPLIT_FOLLOW_BIT) ? "画面列" : "显示列",
                       (unsigned)((px * 100u) / w), cl ? "；已夹到 10 位上限" : "");
            return 0;
        }
        /* 不认的写法一律明确拒绝、不改任何状态（#67）；`split range` 这类还没接的说法也在这里拒掉 */
        xil_printf("[SPLIT] 只认：split screen | split video | split <0..100> | px <0..1024 或 0..512>"
                   " | auto | manual | swap 0|1 | follow 0|1 | marker 0|1 | show"
                   "（range/speed 仍是构建参数，待接）\r\n");
        return 0;
    }
    if (ci_pre(tk[0], "GAMMA")) {
        /* `gamma off` / `gamma 1.8` / `gamma 180`（γ×100）三种写法；参数粘着或分开都吃。 */
        const char *arg = (nt >= 2) ? tk[1] : tk[0] + 5;
        u32 g = 0;
        if (ci_eq(arg, "OFF") || ci_eq(arg, "0")) { gamma_off(); return 0; }
        if (ci_eq(arg, "ON"))  { gamma_set(cur_gamma ? cur_gamma : 220u); return 0; }
        if (ci_eq(arg, "SHOW")) {
            xil_printf("[GAMMA] %s g=%d.%02d auto=%u（区间 %d.%02d..%d.%02d，步长 %d.%02d，每 %d ms 一步）\r\n",
                       cur_gamma ? "on" : "off",
                       (int)(cur_gamma / 100u), (int)(cur_gamma % 100u), (unsigned)gm_auto,
                       (int)(gm_lo / 100u), (int)(gm_lo % 100u),
                       (int)(gm_hi / 100u), (int)(gm_hi % 100u),
                       (int)(gm_step / 100u), (int)(gm_step % 100u), (int)gm_ms);
            return 0;
        }
        if (ci_eq(arg, "MANUAL")) {
            gm_auto = 0;
            xil_printf("[GAMMA] auto 停了，停在 g=%d.%02d\r\n",
                       (int)(cur_gamma / 100u), (int)(cur_gamma % 100u));
            return 0;
        }
        if (ci_eq(arg, "AUTO")) {
            /* `gamma auto [lo hi [step [ms]]]`：不带参数就用上一次的区间（默认 1.00..3.00，
             * 2.0 s 一步 0.20）。lo/hi 认 `1.20` 也认 `120`（与 gamma <数> 同一个解析器）。 */
            u32  lo = gm_lo, hi = gm_hi, st = gm_step, ms = gm_ms;
            int  ib;
            if (nt >= 3 && !parse_gamma(tk[2], &lo)) {
                xil_printf("[GAMMA] auto 的 lo 要写成 1.20 或 120，收到 \"%s\"\r\n", tk[2]); return 0; }
            if (nt >= 4 && !parse_gamma(tk[3], &hi)) {
                xil_printf("[GAMMA] auto 的 hi 要写成 2.60 或 260，收到 \"%s\"\r\n", tk[3]); return 0; }
            if (nt >= 5 && (!strict_int(tk[4], &ib) || ib <= 0)) {
                xil_printf("[GAMMA] auto 的 step 要的是 γ×100 的正整数（20 = 0.20）\r\n"); return 0; }
            if (nt >= 5) st = (u32)ib;
            if (nt >= 6 && (!strict_int(tk[5], &ib) || ib < 200)) {
                xil_printf("[GAMMA] auto 的 ms 要 >=200（一次要写 256 项表，见 main.c 里那段注释）\r\n");
                return 0; }
            if (nt >= 6) ms = (u32)ib;
            gamma_auto_start(lo, hi, st, ms);
            return 0;
        }
        if (!parse_gamma(arg, &g)) {
            xil_printf("[GAMMA] 要 off / 1.00..3.00（或 100..300），收到的是 \"%s\"\r\n", arg);
            return 0;
        }
        /* 手动指定一个数就**先停 Auto**：否则"我明明设了 1.8，画面怎么还在自己变"。 */
        gm_auto = 0;
        gamma_set(g);
        return 0;
    }
    if (ci_eq(tk[0], "OSD"))     { not_wired("osd", "OSD 行开关位（现在是常显）", "V8-5"); return 0; }
    /* （这里原来放了一条 `bilin` 的"待接"提示 —— 撤掉，两个理由：
     *   ① 它永远不会被执行：上面 801 行 `ci_pre(tk[0], "BILIN")` 是前缀匹配，先到先赢；
     *   ② 它说的是错的活。04:03 查过：PS 侧 `bilin on/off` 一直是**完整实现**的
     *      （`BILIN_BIT 19` 写进 gpio_o、`STAT` 回显 `bilin=`、电池第 18/19/50 条覆盖），
     *      缺的是 **PL 侧没人读 `gpio_o[19]`**（`system_top.v` 用到的位是
     *      [4:0]/[15:8]/[16]/[17]/[18]/[22]/[24:23]/[26]/[31:27]，19/20/21/25 悬空）。
     *      ⇒ 症状不是"命令没实现"而是"命令答应了但硬件没动"，这比报"待接"更糟，
     *      所以正确处置是**去 PL 侧加那一级同步**（见 ISSUES #83），不是在这里加提示。 */
    /* r63/#52：双线性的**读口已经在板上跑起来了**（默认开），缺的只是"能不能用串口关回去"。
     *   为什么现在还不许接：cfg1 三十二位已满（[8:0] 效果、[9] 旋转自动、[12:10] 转速、
     *   [22:13] 缝位、[25:23] 三个旗标、[28:26] 缩放档、[29] 手动、[30] 蓝线、[31] 拟合），
     *   塞不进第 33 位 ⇒ 只能走 gpio_cfg2[7:0] 或 gpio_o 的空位，而那是一次**新的 axi→像素跨域**：
     *   按 #71 的预算账与 #65/r54 的两次 CDC-11 教训，它必须单独一次改动 + 单独一次构建 +
     *   给 build/CDC_BASELINE.txt 写出新增那一行的理由，不能顺手挂在双线性这次改动里。
     *   所以现在明说"待接"，而不是让用户敲了没反应（#41 定的规矩）。 */
    if (ci_eq(tk[0], "BILIN"))   { not_wired("bilin", "双线性 on/off 的控制位（PL 读口已就位且默认开着，缺 1 个 GPIO 位 + 一条新跨域）", "ISSUES #79 第 5 节"); return 0; }

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
        /* V9：末尾再挂一个 `geom=%05x` —— 那是 19 位几何控制字（缝位 + auto/follow/swap/marker
         * + rot_auto/rot_speed/zoom_fit）的**整字**回显。为什么要它：串口电池的"跑完必须回到初态"
         * 是比 STAT 元组的，而元组里以前看不见这些位 ⇒ 电池可以把板子留在"自动旋转还开着、
         * 缩放还在 fit、缝贴着右边缘"而判绿。V8-8 给 zsel/zman 补过同一次账（uart_cmd_check 的
         * 注释里记着），这次是同一课的第二遍。新字段照老规矩**只往后加**，不动前面的位序。 */
        xil_printf("[STAT] ctrl en=%02x thr=%d src=%d zoom=%d bilin=%d zsel=%d zman=%d pub=%d"
                   " sd=%d frames=%d playing=%d sel=%03x gm=%d.%02d (PL owns UDP datapath)"
                   " mode=%d geom=%08x\r\n",
                   cur_en & 0x1F, cur_thr, cur_src, cur_zoom ? 1 : 0,
                   cur_bilin ? 1 : 0, cur_zsel, cur_zman, (int)pub_lvl,
                   sd_frame_total() ? 1 : 0, (int)sd_frame_total(), sd_is_playing(),
                   cur_sel & 0x1FF,
                   (int)(cur_gamma / 100u), (int)(cur_gamma % 100u), (int)cur_mode_ovr,
                   (unsigned)(cur_split & GEOM_MASK));
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
    xil_printf("  语法已收/硬件待接: osd on|off | split 的 range/speed\r\n");
    /* V9-3/V9-2：rot 已经接到硬件了（自动旋转的两个控制位），从上面那半行摘下来；
     * 留着不说就是"有功能没入口"，说了不说新的又是"帮助与屏不符"（#67 同族）。 */
    xil_printf("  几何(V9): rot auto [0|1] | rot speed 0..7（度/帧）| rot show\r\n");
    xil_printf("  缩放(V9): zoom fit [0|1]（1 = 倍率跟着角度定，旋转时整幅画面永远在屏内）\r\n");
    xil_printf("  Gamma:  gamma <1.00..3.00> | off | on | auto [lo hi [step [ms]]] | manual | show\r\n");
    /* #51：缝位本身已经可动了（`split <0..100>` / px / auto / manual / swap / follow / marker / show），
     * 所以 split 从上面那半行里摘出来 —— 继续留着"待接"就是说谎（#67 同族）。 */
    xil_printf("  分割线: split screen（屏幕里扫）| split video（画面里扫、跟着转）| split 0..100 |"
               " split px | auto | manual | swap 0|1 | follow 0|1 | marker 0|1 | show\r\n");
    xil_printf("  旧写法仍可用: SRC0 SRC1 TH80 ZOOM0 ZOOM1 BILIN0 BILIN1 FRAME12 00111\r\n");
}


/* 一行输入 → 切 token → dispatch()。缓冲区从 32 扩到 48：spec §14 里最长的一条是
 * `split range 20 80`（含回车 18 字节），老尺寸装不下多参数命令。 */
static void uart_poll(void)
{
    char *tk[T_MAX];
    int nt;

    rx_fill();

    /* 一次可能攒下好几行（粘贴、或长流程里连发），所以按行首的 '\n' 一条条切出来派发。
     * 行分隔认 CR 也认 LF（两者都存成 '\n'）⇒ 终端发 LF / CR / CRLF 都能用，这条一直没变。 */
    for (;;) {
        int i, n = 0;
        for (i = 0; i < cmd_len; i++) {
            if (cmd_buf[i] == '\n') { n = i + 1; break; }
        }
        if (n == 0) break;                       /* 没有完整行 */
        cmd_buf[n - 1] = 0;                      /* 行尾换成语义上的 0 */
        nt = tokenize(cmd_buf, tk);
        if (nt > 0 && dispatch(tk, nt) < 0) {
            xil_printf("[CMD] 不认: %s\r\n", cmd_buf);
            cmd_help();
        }
        memmove(cmd_buf, cmd_buf + n, (size_t)(cmd_len - n));
        cmd_len -= n;
        cmd_toolong = 0;                         /* 新的一行重新允许报一次超长 */
    }
}

/* 把 RX 里的字节搬进 cmd_buf：只搬运、只回显，绝不切词派发（派发在 uart_poll）。
 * 存进缓冲时 CR/LF 都归一成 '\n' ⇒ 上面那条"按行切"的逻辑与终端的换行风格无关。 */
static void rx_fill(void)
{
    while (XUartPs_IsReceiveData(STDIN_BASEADDRESS)) {
        u8 ch = XUartPs_RecvByte(STDIN_BASEADDRESS);
        if (ch == '\r') ch = '\n';               /* CR 与 CRLF 都只留一个行尾 */
        if (ch == '\n') {
            if (cmd_len > 0) { cmd_buf[cmd_len++] = '\n'; }
            xil_printf("\r\n");                  /* 回显一个行尾，看不见回车也算一种"没反应" */
        } else {
            if (cmd_len < CMD_BUF - 1) {
                cmd_buf[cmd_len++] = (char)ch;
                XUartPs_SendByte(STDIN_BASEADDRESS, ch);   /* 本地回显：老实现一个字都不回， */
            } else if (!cmd_toolong) {                     /* 用户只能靠"再发一次"猜有没有收到 */
                cmd_toolong = 1;
                xil_printf("\r\n[CMD!] 这行超过 %d 字节，多出来的丢掉（不是没收到，是太长）\r\n",
                           CMD_BUF - 1);
            }
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
        gamma_tick();      /* V9-5：gamma Auto 的推进（没开 Auto 时它立刻返回） */
    }
    return 0;
}
