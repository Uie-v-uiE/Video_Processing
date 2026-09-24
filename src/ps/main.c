/**
 * PS control plane + SD 卡本地回放。UDP 视频数据通路仍然整个在 PL（rtl/eth 目录）。
 *
 * AXI GPIO @ 0x41200000
 *   [4:0]   effect_en    [15:8] threshold   [16] src_sel   [17] zoom_en
 *   [18]    ps_publish   —— 翻转一次 = "DDR 里这一帧写完了，请在下一个 frame_start 搬走"
 * DDR frame @ 0x10100000（FILL 诊断帧 / SD 回放帧都落在这里；ETH 用 0x10000000/0x10080000）
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
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

static u32 cur_en = 0;
static u8  cur_thr = 80;
static u8  cur_src = 0;
static u8  cur_zoom = 1;   /* GPIO bit17: 右屏无极缩放。当前 RTL 常开，此位预留给控制 */
static u8  cur_bilin = 1;  /* GPIO bit19: 双线性/最近邻 A-B 对照，演示时现场切换用 */
static u32 pub_lvl = 0;

/* 只写寄存器、不打字，返回写进去的值。
 * 每帧一次的"发布"脉冲必须走这条：原来 ps_publish() 直接调 ctrl_apply()，于是 30 fps 的
 * 回放每秒往串口推约 2 KB（115200 只有 11.5 KB/s，而 xil_printf 是轮询等 TX 的阻塞实现），
 * 板上实测 PLAY 10 s 收回 28549 B 全是 [CTRL] 行 —— 刷屏之外还把发布时序压在打印上。 */
static u32 ctrl_write(void)
{
    u32 v = (cur_en & 0x1F) | ((u32)cur_thr << 8) | ((u32)cur_src << 16)
          | ((u32)(cur_zoom ? 1 : 0) << 17) | (pub_lvl << PUBLISH_BIT)
          | ((u32)(cur_bilin ? 1 : 0) << BILIN_BIT);
    Xil_Out32(GPIO_DATA, v);
    return v;
}

static void ctrl_apply(void)
{
    u32 v = ctrl_write();
    xil_printf("[CTRL] AXI_GPIO=0x%08x en=%02x thr=%d src=%d zoom=%d pub=%d bilin=%d\r\n",
               v, cur_en & 0x1F, cur_thr, cur_src, cur_zoom ? 1 : 0, (int)pub_lvl,
               cur_bilin ? 1 : 0);
}

/* sd_play.c 只被允许请求"发布"，不碰别人的控制字；每帧都调，所以不出声 */
void ps_publish(void)
{
    pub_lvl ^= 1u;
    (void)ctrl_write();
}

static void ctrl_set_en(u32 en)
{
    cur_en = en & 0x1F;
    ctrl_apply();
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
        if (n >= 5) return -1;
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

    if (nt == 1 && parse_bits(tk[0], &en) > 0) { ctrl_set_en(en); return 0; }

    if (ci_eq(tk[0], "PIPE")) {
        if (nt < 2 || parse_bits(tk[1], &en) <= 0) { xil_printf("[PIPE] 要跟 5 位 0/1，例：pipe 11000\r\n"); return 0; }
        ctrl_set_en(en);
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
        /* `zoom on|off` 与老写法 `ZOOM1/ZOOM0`（粘着）共用一条出口；剩下的
         * `zoom 1.5` / `zoom auto` 要有 PL 的因子寄存器才行（V8-8），不能当 on/off 偷偷吃掉。 */
        const char *arg = (nt >= 2) ? tk[1] : tk[0] + 4;
        int b = -1;
        if (strict_int(arg, &v) && (v == 0 || v == 1)) b = v;
        if (ci_eq(arg, "ON")) b = 1;
        if (ci_eq(arg, "OFF")) b = 0;
        if (b < 0) not_wired("zoom <因子>/auto", "PL 的缩放因子寄存器（现在只有 on/off 一个位）", "V8-8");
        else ctrl_set_zoom((u8)b);
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
    if (ci_eq(tk[0], "SPLIT"))   { not_wired("split", "整个 split_ctrl（位置/自动扫描/range/speed/swap）", "V8-4"); return 0; }
    if (ci_eq(tk[0], "GAMMA"))   { not_wired("gamma", "gamma_lut 与它的 LUT 写窗口", "V8-3"); return 0; }
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
        xil_printf("[STAT] ctrl en=%02x thr=%d src=%d zoom=%d bilin=%d pub=%d"
                   " sd=%d frames=%d playing=%d (PL owns UDP datapath)\r\n",
                   cur_en & 0x1F, cur_thr, cur_src, cur_zoom ? 1 : 0,
                   cur_bilin ? 1 : 0, (int)pub_lvl,
                   sd_frame_total() ? 1 : 0, (int)sd_frame_total(), sd_is_playing());
        return 0;
    }
    if (ci_eq(tk[0], "HELP") || ci_eq(tk[0], "?")) { cmd_help(); return 0; }
    return -1;
}

static void cmd_help(void)
{
    xil_printf("  V8 语法: src 0|1|2 | pipe 11000 | th 80 | zoom on|off | bilin on|off |"
               " frame N | sd | play | stop | fill | autoplay0|1 | stat | help\r\n");
    xil_printf("  语法已收/硬件待接: rot ... | split ... | gamma ... | osd on|off\r\n");
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
    Xil_ExceptionInit();
    Xil_DCacheEnable();
    Xil_ICacheEnable();
    Xil_ExceptionEnable();

    xil_printf("\r\n[BOOT] video_pipeline PL-UDP control plane\r\n");
    Xil_Out32(GPIO_TRI, 0x00000000u);
    ctrl_apply();

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
