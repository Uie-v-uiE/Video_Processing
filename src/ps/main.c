/**
 * PS control plane + SD 卡本地回放。UDP 视频数据通路仍然整个在 PL（rtl/eth 目录）。
 *
 * AXI GPIO @ 0x41200000
 *   [4:0]   effect_en    [15:8] threshold   [16] src_sel   [17] zoom_en
 *   [18]    ps_publish   —— 翻转一次 = "DDR 里这一帧写完了，请在下一个 frame_start 搬走"
 * DDR frame @ 0x10000000（FILL 诊断帧 / SD 回放帧都落在这里）
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
#define FRAME_ADDR  0x10000000u

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

static void ctrl_apply(void)
{
    u32 v = (cur_en & 0x1F) | ((u32)cur_thr << 8) | ((u32)cur_src << 16)
          | ((u32)(cur_zoom ? 1 : 0) << 17) | (pub_lvl << PUBLISH_BIT)
          | ((u32)(cur_bilin ? 1 : 0) << BILIN_BIT);
    Xil_Out32(GPIO_DATA, v);
    xil_printf("[CTRL] AXI_GPIO=0x%08x en=%02x thr=%d src=%d zoom=%d pub=%d bilin=%d\r\n",
               v, cur_en & 0x1F, cur_thr, cur_src, cur_zoom ? 1 : 0, (int)pub_lvl,
               cur_bilin ? 1 : 0);
}

/* sd_play.c 只被允许请求"发布"，不碰别人的控制字 */
void ps_publish(void)
{
    pub_lvl ^= 1u;
    ctrl_apply();
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

static void uart_poll(void)
{
    static char buf[32];
    static int idx = 0;
    while (XUartPs_IsReceiveData(STDIN_BASEADDRESS)) {
        u8 ch = XUartPs_RecvByte(STDIN_BASEADDRESS);
        if (ch == '\n' || ch == '\r') {
            buf[idx] = 0;
            if (idx > 0) {
                u32 en;
                if (parse_bits(buf, &en) > 0) {
                    ctrl_set_en(en);
                } else if (!strncmp(buf, "SRC0", 4)) {
                    ctrl_set_src(0);
                } else if (!strncmp(buf, "SRC1", 4)) {
                    ctrl_set_src(1);
                } else if (!strncmp(buf, "ZOOM0", 5)) {
                    ctrl_set_zoom(0);
                } else if (!strncmp(buf, "ZOOM1", 5)) {
                    ctrl_set_zoom(1);
                } else if (!strncmp(buf, "BILIN0", 6)) {
                    ctrl_set_bilin(0);
                } else if (!strncmp(buf, "BILIN1", 6)) {
                    ctrl_set_bilin(1);
                } else if (!strncmp(buf, "TH", 2) && idx > 2) {
                    int th = atoi(buf + 2);
                    if (th < 0) th = 0;
                    if (th > 255) th = 255;
                    ctrl_set_thr((u8)th);
                } else if (!strncmp(buf, "FILL", 4)) {
                    volatile u16 *p = (volatile u16 *)FRAME_ADDR;
                    int i;
                    for (i = 0; i < FRAME_W * FRAME_H; i++) {
                        int x = i % FRAME_W, y = i / FRAME_W;
                        u16 c;
                        if (y < 8)
                            c = 0x07E0;
                        else if (x < 256 && y < 150)
                            c = 0xF800;
                        else if (x >= 256 && y < 150)
                            c = 0xFFE0;
                        else if (x < 256)
                            c = 0x001F;
                        else
                            c = 0xFFFF;
                        p[i] = c;
                    }
                    Xil_DCacheFlushRange(FRAME_ADDR, FRAME_BYTES);
                    ctrl_set_src(1);
                    ps_publish();       /* 新协议：PL 只在收到发布脉冲后才搬一次 */
                    xil_printf("[CMD] FILL diagnostic via PS DDR\r\n");
                } else if (!strncmp(buf, "SD", 2)) {
                    if (sd_mount() == 0) sd_status();
                    else xil_printf("[SD] mount failed: %s\r\n", sd_err());
                } else if (!strncmp(buf, "PLAY", 4)) {
                    ctrl_set_src(1);
                    if (!sd_play(1)) xil_printf("[SD] play refused: %s\r\n", sd_err());
                    else xil_printf("[SD] playing (STOP to end; cable must stay out)\r\n");
                } else if (!strncmp(buf, "STOP", 4)) {
                    (void)sd_play(0);
                    xil_printf("[SD] stopped at frame %d\r\n", (int)sd_frame_now());
                } else if (!strncmp(buf, "FRAME", 5) && idx > 5) {
                    int n = atoi(buf + 5);
                    if (n < 0 || sd_show((u32)n) != 0)
                        xil_printf("[SD] frame %s failed: %s\r\n", buf + 5, sd_err());
                    else ctrl_set_src(1);
                } else if (!strncmp(buf, "STAT", 4)) {
                    xil_printf("[STAT] ctrl en=%02x thr=%d src=%d zoom=%d bilin=%d pub=%d"
                               " sd=%d frames=%d playing=%d (PL owns UDP datapath)\r\n",
                               cur_en & 0x1F, cur_thr, cur_src, cur_zoom ? 1 : 0,
                               cur_bilin ? 1 : 0, (int)pub_lvl,
                               sd_frame_total() ? 1 : 0, (int)sd_frame_total(), sd_is_playing());
                } else {
                    xil_printf("[CMD] %s\r\n  00111 SRC0 SRC1 TH80 ZOOM0 ZOOM1 BILIN0 BILIN1 FILL SD PLAY STOP FRAME0 STAT\r\n", buf);
                }
            }
            idx = 0;
        } else if (idx < (int)sizeof(buf) - 1) {
            buf[idx++] = (char)ch;
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
    xil_printf("[BOOT] uart115200: 00111 SRC0 SRC1 TH80 ZOOM0 ZOOM1 BILIN0 BILIN1 FILL SD PLAY STOP FRAME0 STAT\r\n");

    while (1) {
        uart_poll();
        sd_tick();
    }
    return 0;
}
