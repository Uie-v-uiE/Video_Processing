/**
 * UART + AXI GPIO + lwIP UDP video sink
 *
 * BSP: lwip, xuartps
 * UDP 5001 : RGB565 512x300 LE
 * AXI GPIO @ 0x41200000
 * DDR frame @ 0x10000000
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
#include "xemacps_hw.h"

#include "lwip/init.h"
#include "netif/xadapter.h"
#include "lwip/udp.h"
#include "lwip/ip_addr.h"
#include "lwip/pbuf.h"
#include "lwip/netif.h"
#include "netif/xemacpsif.h"

#define FRAME_W     512
#define FRAME_H     300
#define FRAME_BYTES (FRAME_W * FRAME_H * 2)
#define FRAME_ADDR  0x10000000u
#define UDP_PORT    5001

#define AXI_GPIO_BASE 0x41200000u
#define GPIO_DATA     (AXI_GPIO_BASE + 0x00u)
#define GPIO_TRI      (AXI_GPIO_BASE + 0x04u)
#define EMAC_BASE     XPAR_XEMACPS_0_BASEADDR

static struct netif server_netif;
static struct udp_pcb *upcb;
static volatile u32 rx_bytes;
static volatile u32 frames_done;
static volatile u32 udp_pkts;

/* Keep effect/threshold/src independent so UART cmds don't clobber each other */
static u32 cur_en = 0;
static u8  cur_thr = 80;
static u8  cur_src = 0;

static void ctrl_apply(void)
{
    u32 v = (cur_en & 0x1F) | ((u32)cur_thr << 8) | ((u32)cur_src << 16);
    Xil_Out32(GPIO_DATA, v);
    xil_printf("[CTRL] AXI_GPIO=0x%08x en=%02x thr=%d src=%d\r\n",
               v, cur_en & 0x1F, cur_thr, cur_src);
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

static void print_net_status(void)
{
    struct xemac_s *xemac;
    xemacpsif_s *xps;
    u32 nwctrl, nwcfg, nwsr, rxcnt, txcnt;
    u16 bmsr = 0, bmcr = 0;

    nwctrl = Xil_In32(EMAC_BASE + XEMACPS_NWCTRL_OFFSET);
    nwcfg  = Xil_In32(EMAC_BASE + XEMACPS_NWCFG_OFFSET);
    nwsr   = Xil_In32(EMAC_BASE + XEMACPS_NWSR_OFFSET);
    rxcnt  = Xil_In32(EMAC_BASE + XEMACPS_RXCNT_OFFSET);
    txcnt  = Xil_In32(EMAC_BASE + XEMACPS_TXCNT_OFFSET);

    if (server_netif.state) {
        xemac = (struct xemac_s *)server_netif.state;
        xps = (xemacpsif_s *)xemac->state;
        if (xps) {
            XEmacPs_PhyRead(&xps->emacps, 1, 1, &bmsr);
            XEmacPs_PhyRead(&xps->emacps, 1, 0, &bmcr);
        }
    }

    xil_printf("[STAT] frames=%u udp=%u en=%02x thr=%d src=%d\r\n",
               frames_done, udp_pkts, cur_en & 0x1F, cur_thr, cur_src);
    xil_printf("[STAT] nwctrl=0x%08x nwcfg=0x%08x nwsr=0x%08x\r\n",
               nwctrl, nwcfg, nwsr);
    xil_printf("[STAT] rxcnt=%u txcnt=%u BMSR=0x%04x BMCR=0x%04x link=%d\r\n",
               rxcnt, txcnt, bmsr, bmcr, (bmsr & 0x4) ? 1 : 0);
}

static void on_udp_frame(void *arg, struct udp_pcb *pcb, struct pbuf *p,
                         const ip_addr_t *addr, u16_t port)
{
    struct pbuf *q;
    (void)arg; (void)pcb; (void)addr; (void)port;
    if (!p)
        return;
    udp_pkts++;
    q = p;
    while (q) {
        u8 *pl = (u8 *)q->payload;
        u32 len = q->len;
        u32 off;
        /* packet: [u32 LE offset][data] — write at absolute offset in frame */
        if (len < 4) {
            q = q->next;
            continue;
        }
        off = (u32)pl[0] | ((u32)pl[1] << 8) | ((u32)pl[2] << 16) | ((u32)pl[3] << 24);
        pl += 4;
        len -= 4;
        if (off < FRAME_BYTES) {
            if (off + len > FRAME_BYTES)
                len = FRAME_BYTES - off;
            if (len)
                memcpy((void *)(UINTPTR)(FRAME_ADDR + off), pl, len);
            rx_bytes += len;
        }
        q = q->next;
    }
    pbuf_free(p);
    if (rx_bytes >= FRAME_BYTES) {
        Xil_DCacheFlushRange(FRAME_ADDR, FRAME_BYTES);
        rx_bytes = 0;
        frames_done++;
        if (frames_done == 1)
            ctrl_set_src(1);
    }
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
                } else if (!strncmp(buf, "TH", 2) && idx > 2) {
                    int th = atoi(buf + 2);
                    if (th < 0) th = 0;
                    if (th > 255) th = 255;
                    ctrl_set_thr((u8)th);
                } else if (!strncmp(buf, "FILL", 4)) {
                    /* 2x2 diagnostic: green top bar; red/yellow top; blue/white bottom */
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
                    xil_printf("[CMD] FILL 2x2 diagnostic\r\n");
                } else if (!strncmp(buf, "STAT", 4)) {
                    print_net_status();
                } else {
                    xil_printf("[CMD] %s\r\n  00111 SRC0 SRC1 TH80 FILL STAT\r\n", buf);
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
    ip_addr_t ipaddr, netmask, gw;
    static u8 mac[6] = {0x00, 0x0a, 0x35, 0x00, 0x01, 0x02};

    Xil_ExceptionInit();
    Xil_DCacheEnable();
    Xil_ICacheEnable();
    Xil_ExceptionEnable();

    xil_printf("\r\n[BOOT] video_pipeline ETH+UART\r\n");
    Xil_Out32(GPIO_TRI, 0x00000000u);
    ctrl_apply();

    IP4_ADDR(&ipaddr, 192, 168, 1, 10);
    IP4_ADDR(&netmask, 255, 255, 255, 0);
    IP4_ADDR(&gw, 192, 168, 1, 1);
    lwip_init();
    if (!xemac_add(&server_netif, &ipaddr, &netmask, &gw,
                   mac, XPAR_XEMACPS_0_BASEADDR)) {
        xil_printf("[ERR] xemac_add\r\n");
    } else {
        netif_set_default(&server_netif);
        netif_set_up(&server_netif);
        netif_set_link_up(&server_netif);
        upcb = udp_new();
        if (upcb) {
            udp_bind(upcb, IP_ADDR_ANY, UDP_PORT);
            udp_recv(upcb, on_udp_frame, NULL);
        }
        xil_printf("[NET] ip=192.168.1.10 mac=%02x:%02x:%02x:%02x:%02x:%02x\r\n",
                   mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
        xil_printf("[NET] udp=%d  (send STAT for link/rx counters)\r\n", UDP_PORT);
        print_net_status();
    }

    xil_printf("[BOOT] uart115200: 00111 SRC0 SRC1 TH80 FILL STAT\r\n");
    while (1) {
        uart_poll();
        xemacif_input(&server_netif);
    }
    return 0;
}
