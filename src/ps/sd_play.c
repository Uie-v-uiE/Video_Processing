/*
 * SD 卡本地视频回放：裸机 FAT32 只读 + XSdPs，不依赖 FatFs / 任何文件系统库。
 *
 * 为什么自己写 FAT32：BSP 的 libsrc 里没有 xilffs（只有 sdps），而卡上的文件布局
 * 是我们自己用 src/host/make_sd_video.mjs 生成的 —— 只有 8.3 名、只有簇链，
 * 一个只读目录扫描 200 行就够。引入 FatFs 反而多一层没人验过的代码。
 *
 * 卡上的内容（make_sd_video.mjs 生成，写卡时逐文件 md5 已核对）：
 *   VIDEO000.BIN .. VIDEO008.BIN   每个 512 帧 × 307200 B = 153.6 MiB
 *   META.TXT   WIDTH/HEIGHT/FRAME_BYTES/FRAMES/FPS/CHUNK_FRAMES/FILES/SOURCE + FILEi=名字 FRAMES=n BYTES=b
 *
 * 帧的落地路径刻意做成"零拷贝"：SD 控制器的 DMA 直接写 PL 要读的那块 DDR，
 * 写完只发一次发布脉冲 ⇒ PS 不需要 300 KB 的 memcpy，也不需要第二块 DDR 做双缓冲。
 *
 * 播放协议（与 pl_video_top.v 的改动配套，见 report/OVERNIGHT_LOG.md §P1）：
 *   PS 把一帧 DMA 进 DDR → 翻转 GPIO bit18 → PL 在下一个 frame_start 复制一次。
 *   "复制一次"而不是"每帧都复制"是关键：前者让 PS 有整个帧周期可以安全覆写 DDR；
 *   后者会在 PS 写到一半时把半张新图 + 半张旧图搬上屏（撕裂）。
 */

#include <string.h>
#include <stdlib.h>

#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xiltimer.h"
#include "xsdps.h"

#include "sd_play.h"

/* ---- 与 RTL 必须一致的数：改这里要同时改 pl_video_top.v 的 BASE_ADDR / IMG_W / IMG_H ---- */
#define FRAME_BYTES    (512u * 300u * 2u)        /* RGB565 = 307200 B = 600 扇区 */
#define FRAME_ADDR     0x10100000u               /* = pl_video_top 的 PS_BASE_ADDR（PS 专用第三个 bank） */

#define SD_BASE        XPAR_XSDPS_0_BASEADDR
#define MAX_FILES      16u
#define EOC            0x0FFFFFFFu               /* 链尾 / 错误的共同哨兵 */

static XSdPs Sd;
static u8  Sec[512] __attribute__((aligned(64)));    /* 扇区缓冲（MBR/BPB/目录/FAT 复用） */
static u8  Fat[512] __attribute__((aligned(64)));    /* FAT 扇区缓存 */
static u8  Meta[4096] __attribute__((aligned(64)));   /* META.TXT 的头几个扇区（见 sd_mount 里的读法） */
static u32 FatLba = 0xFFFFFFFFu;

static const char *err = "ok";
static const char *meta_warn;       /* 挂载成功但清单与读到的内容不一致时的提示 */
static u8 meta_trunc;               /* 1 = META.TXT 比缓冲区还长（清单真的放不下） */
static u32 found_size;              /* dir_lookup 顺带记下的文件大小（字节） */
static int mounted;

/* FAT32 卷参数 */
static u32 part_lba, part_sect, spc, fat_lba, data_lba, root_clus;
/* 最近一次失败读的参数（ISSUES #50 的定点坏点：只报 "SD read failed" 分不出
 * "簇号越界（FAT 坏）" 与 "LBA 合法但卡拒绝（物理坏点 / 控制器半途）"） */
static u32 last_lba, last_cnt, last_clus;

/* 帧库（来自 META.TXT） */
static char fname[MAX_FILES][13];
static u32  fframes[MAX_FILES];
static u32  nfiles, total_frames;
static u32  fps_num = 15u, fps_den = 1u;

/* 播放状态 */
static int  playing;
static u32  nxt;                    /* 下一帧索引 */
static u32  open_idx = 0xFFFFFFFFu; /* 当前打开的文件号 */
static u32  ff_clus, ff_blk;        /* 当前簇 / 簇内已用的扇区数 */
static u32  fed_cnt;
static XTime last_t, fed_t0, rpt_t;
static u32 rpt_cnt;               /* 上一次报速率时的 fed_cnt，用于"这 100 帧"的窗口 */

/* ============================ 基础工具 ============================ */

const char *sd_err(void) { return err; }

static u16 ld16(const u8 *p) { return (u16)(p[0] | ((u16)p[1] << 8)); }
static u32 ld32(const u8 *p)
{
    return (u32)p[0] | ((u32)p[1] << 8) | ((u32)p[2] << 16) | ((u32)p[3] << 24);
}

/*
 * 读 cnt 个扇区。
 * 分块：驱动一次能吃的块数受传输长度字段限制，64 扇区 = 32 KB 是稳妥值。
 * 读之前还要 flush：驱动读完会 invalidate 目标区间，但**进**去之前若那里有脏行
 * （例如刚跑过 FILL），invalidate 之后脏行仍会被写回，把刚 DMA 进来的数据盖掉。
 */
static int read_secs(u32 lba, u32 cnt, u8 *dst)
{
    while (cnt) {
        u32 n = (cnt > 64u) ? 64u : cnt;
        int try;
        Xil_DCacheFlushRange((INTPTR)dst, (s32)(n * 512u));
        /* 一次重试的由来（板上实测，ISSUES #50）：一边 30 fps 推流一边回放，第 3584 帧
         * 报 `XSdPs_ReadPolled` 超时。当时这里写的是"之后重放同一个位置又是好的"，
         * 于是归成"被挤到超时"—— 2026-09-24 把这个解释**推翻**了：
         *   · 两次独立长跑（一次并发、一次完全不碰 JTAG）都停在**同一帧号 3584**；
         *   · 定点跳帧：FRAME3583 好、FRAME3584 = SD read failed（3584 = 7×512，
         *     正好是第 8 个文件 VIDEO007.BIN 的**第一帧**）。
         * 所以这是**定点坏点**而不是竞态：重试对定点坏点没用（它只是让偶发的单点抖动
         * 不掐断演示，这个作用保留）。之后那串 "frame file not found" 是次生的：
         * 一次读失败会把控制器留在未完成的传输里，后面每次读（含目录扫描）都失败。
         * 根因（09-24 05:4x 结案）：`dir_lookup` 把 FAT32 目录项的高簇字按大端拼 ⇒
         * 首簇 ≥65536 的文件（= 起点在数据区 1 GiB 之后）簇号翻错、LBA 冲出分区。
         * 判据与凭据见 clus_of()/dir_selftest() 与 ISSUES #50。 */
        for (try = 0; try < 2; try++) {
            if (XSdPs_ReadPolled(&Sd, lba, n, dst) == XST_SUCCESS) break;
            err = "SD read failed";
        }
        if (try >= 2) {
            /* 一次失败就报全部几何量：判"簇号越界"还是"合法 LBA 被拒"只看这一个数就够 */
            last_lba = lba; last_cnt = n;
            xil_printf("[SDRD!] lba=%u n=%u clus=%u part_end=%u %s"
                       " (data_lba=%u spc=%u fat_lba=%u dst=0x%08x)\r\n",
                       (unsigned)lba, (unsigned)n, (unsigned)last_clus,
                       (unsigned)(part_lba + part_sect),
                       (part_sect && lba + n <= part_lba + part_sect) ? "IN-RANGE"
                                                                      : "OUT-OF-RANGE",
                       (unsigned)data_lba, (unsigned)spc, (unsigned)fat_lba,
                       (unsigned)(UINTPTR)dst);
            return -1;
        }
        lba += n;
        dst += n * 512u;
        cnt -= n;
    }
    return 0;
}

/* 簇 c 的下一个簇号（FAT32 只用低 28 bit），带一个扇区的缓存 */
static u32 fat_next(u32 c)
{
    u32 off = c * 4u;
    u32 lba = fat_lba + off / 512u;
    u32 v;

    if (c < 2u || c >= EOC) return EOC;
    if (lba != FatLba) {
        if (read_secs(lba, 1u, Fat) != 0) return EOC;
        FatLba = lba;
    }
    v = ld32(&Fat[off % 512u]) & 0x0FFFFFFFu;
    return (v >= 0x0FFFFFF8u) ? EOC : v;
}

/* 簇 c 内第 sblk 个扇区的绝对 LBA */
static u32 clus_lba(u32 c, u32 sblk) { return data_lba + (c - 2u) * spc + sblk; }

/* "VIDEO000.BIN" → 目录项里的 11 字节形式：前 8 大写、不足补空格，扩展名 3 字节 */
static void name83(const char *dotted, char out[11])
{
    const char *dot = strchr(dotted, '.');
    int base = dot ? (int)(dot - dotted) : (int)strlen(dotted);
    int i;

    if (base > 8) base = 8;
    for (i = 0; i < 8; i++) {
        char ch = (i < base) ? dotted[i] : ' ';
        out[i] = (ch >= 'a' && ch <= 'z') ? (char)(ch - 32) : ch;
    }
    for (i = 0; i < 3; i++) {
        char ch = (dot && dot[1 + i]) ? dot[1 + i] : ' ';
        out[8 + i] = (ch >= 'a' && ch <= 'z') ? (char)(ch - 32) : ch;
    }
}

/* "FILE" + 十进制序号，写进 dst（dst 至少 8 字节） */
static void mkkey(char *dst, const char *pre, u32 n)
{
    int i = 0;
    while (pre[i]) { dst[i] = pre[i]; i++; }
    if (n >= 10u) { dst[i++] = (char)('0' + n / 10u); n %= 10u; }
    dst[i++] = (char)('0' + n);
    dst[i] = 0;
}

/* 从"KEY=v1 KEY=v2 ..."里取某个 KEY 的整数值 */
static int kv_u32(const char *s0, const char *key, u32 *out)
{
    const char *s = s0;
    int kl = (int)strlen(key);

    while ((s = strstr(s, key)) != 0) {
        /* 命中处必须在串首或空格/换行之后，否则 "XFRAMES=" 也算数。
         * 原来这里写的是 `s == key` —— key 是被查找的**字面量**（"FRAMES" 在 .rodata 里），
         * 和指进 s0 里的指针永远不相等，于是"关键字出现在串首"这一种恰恰不成立；
         * 再巧的是调用方把空格换成了 '\0' 才传进来，s[-1] 读到的是那个 '\0'，
         * 三个字符一个都不匹配 ⇒ 板上实测 "FILE0=VIDEO000.BIN FRAMES=100 BYTES=…" 一律报
         * "META: FILE line without FRAMES"（ISSUES #43：判据要能被独立测试，见 report/ISSUES.md）。 */
        if (s[kl] == '=' && (s == s0 || s[-1] == ' ' || s[-1] == '\r' || s[-1] == '\n')) {
            *out = (u32)strtoul(s + kl + 1, 0, 10);
            return 1;
        }
        s += kl;
    }
    return 0;
}

/* ============================ 挂载 ============================ */

static int parse_bpb(void)
{
    u32 rsvd, nfat, fatsz;

    if (ld16(&Sec[510]) != 0xAA55u) { err = "MBR signature missing"; return -1; }
    if (Sec[446 + 4] != 0x0Bu && Sec[446 + 4] != 0x0Cu) {
        err = "partition 1 is not FAT32 (use the card made by make_sd_video.mjs)";
        return -1;
    }
    part_lba  = ld32(&Sec[446 + 8]);
    part_sect = ld32(&Sec[446 + 12]);
    if (read_secs(part_lba, 1u, Sec) != 0) return -1;
    if (Sec[510] != 0x55u || Sec[511] != 0xAAu) { err = "boot sector signature missing"; return -1; }
    if (ld16(&Sec[11]) != 512u) { err = "bytes/sector != 512 not supported"; return -1; }
    spc   = Sec[13];
    rsvd  = ld16(&Sec[14]);
    nfat  = Sec[16];
    fatsz = ld32(&Sec[36]);
    if (fatsz == 0u || spc == 0u) { err = "FATSz32 or SecPerClus is 0 → FAT16, not supported"; return -1; }
    root_clus = ld32(&Sec[44]) & 0x0FFFFFFFu;
    fat_lba   = part_lba + rsvd;
    data_lba  = fat_lba + nfat * fatsz;
    FatLba    = 0xFFFFFFFFu;
    if (root_clus < 2u) { err = "root cluster invalid"; return -1; }
    return 0;
}

/* FAT32 目录项里的首簇：偏移 26 是低 16 位、偏移 20 是**高 16 位小端字**。
 * 这两个字节原来按大端拼（d[20]<<24|d[21]<<16），于是"首簇 ≥ 65536"（= 文件起点在
 * 数据区 1 GiB 之后）的文件簇号被翻成天文数字 ⇒ ISSUES #50 的那个"定点坏点"。 */
static u32 clus_of(const u8 *d) { return ((u32)ld16(&d[20]) << 16) | (u32)ld16(&d[26]); }

/* 在根目录里找 8.3 名字，返回首簇；找不到返回 0 */
static u32 dir_lookup(const char *dotted)
{
    char key[11];
    u32 c = root_clus, guard = 0;

    name83(dotted, key);
    while (c >= 2u && c < EOC && guard++ < 4096u) {
        u32 b;
        for (b = 0; b < spc; b++) {
            int e;
            if (read_secs(clus_lba(c, b), 1u, Sec) != 0) return 0;
            for (e = 0; e < 16; e++) {
                const u8 *d = &Sec[e * 32];
                if (d[0] == 0x00u) return 0;             /* 目录到此为止 */
                if (d[0] == 0xE5u) continue;             /* 已删除 */
                if (d[11] == 0x0Fu) continue;            /* LFN：本项目不产生 */
                if (d[11] & 0x08u) continue;             /* 卷标 */
                if (memcmp(d, key, 11) != 0) continue;
                found_size = ld32(&d[28]);       /* DIR_Entry.FileSize（小端 4 字节） */
                return clus_of(d);
            }
        }
        c = fat_next(c);
    }
    return 0;
}

/* 目录项首簇解码的自我判据。用例就是 #50 的现场：真实卡上 VIDEO007.BIN 的高字是
 * 0x0001、低字是 0x0686 ⇒ 必须解出 67206。最后那条反例断言才是要害 ——
 * 它要求"旧写法（两个字节按大端拼）"确实给出 16778886，也就是**这条判据分得出对错**；
 * 否则它只是把实现照抄一遍。 */
static int dir_selftest(void)
{
    /* 小端：d[20] 是高字的**低**字节 */
    static const u8 v[3][4] = { { 0x00u, 0x00u, 0x05u, 0x00u },
                                { 0x01u, 0x00u, 0x86u, 0x06u },
                                { 0x00u, 0x01u, 0x86u, 0x06u } };
    static const u32 exp[3] = { 5u, 67206u, 16778886u };
    u8 d[32];
    u32 i, k, old_style;
    int ok = 1;

    for (i = 0; i < 3u; i++) {
        for (k = 0; k < 32u; k++) d[k] = 0u;
        d[20] = v[i][0]; d[21] = v[i][1]; d[26] = v[i][2]; d[27] = v[i][3];
        if (clus_of(d) != exp[i]) ok = 0;
    }
    old_style = ((u32)v[1][0] << 24) | ((u32)v[1][1] << 16)
              | (u32)(v[1][2] | ((u16)v[1][3] << 8));
    if (old_style != 16778886u) ok = 0;      /* 旧写法必须真的错，不然测了个空的 */
    d[20] = v[1][0]; d[21] = v[1][1]; d[26] = v[1][2]; d[27] = v[1][3];
    if (clus_of(d) == old_style) ok = 0;     /* 新旧必须给出不同答案 */
    return ok;
}

/* 按行扫 META.TXT：行首匹配 KEY= 才认，避免把 FILE 行里的 FRAMES= 当成全局帧数 */
static int meta_line(const char *key, char *val, int vsz)
{
    int kl = (int)strlen(key), n = 0;
    const char *p = (const char *)Meta, *e = (const char *)Meta + sizeof(Meta);

    while (p < e && *p) {
        const char *ls = p, *le = p;
        while (le < e && *le && *le != '\n') le++;
        if (!strncmp(ls, key, (size_t)kl) && ls[kl] == '=') {
            const char *v = ls + kl + 1;
            while (v < le && *v != '\r' && n < vsz - 1) val[n++] = *v++;
            val[n] = 0;
            return 1;
        }
        p = le + 1;
    }
    return 0;
}

static int parse_meta(void)
{
    char v[96];
    u32 i;

    total_frames = 0; nfiles = 0;
    Meta[sizeof(Meta) - 1] = 0;
    if (!meta_line("FRAMES", v, sizeof v)) { err = "META: no FRAMES line"; return -1; }
    total_frames = (u32)strtoul(v, 0, 10);
    if (meta_line("FPS", v, sizeof v)) {
        const char *dot = strchr(v, '.');
        fps_num = (u32)strtoul(v, 0, 10);
        fps_den = 1u;
        if (dot) {
            const char *q = dot + 1;
            u32 frac = 0u, scale = 1u;
            while (*q >= '0' && *q <= '9') { frac = frac * 10u + (u32)(*q - '0'); scale *= 10u; q++; }
            fps_num = fps_num * scale + frac;
            fps_den = scale;
        }
        if (fps_num == 0u) { fps_num = 15u; fps_den = 1u; }
    }
    if (meta_line("FRAME_BYTES", v, sizeof v) &&
        (u32)strtoul(v, 0, 10) != FRAME_BYTES) {
        err = "META FRAME_BYTES != compiled FRAME_BYTES (rebuild to match the card)";
        return -1;
    }
    if (meta_line("WIDTH", v, sizeof v) && (u32)strtoul(v, 0, 10) != 512u) {
        err = "META WIDTH != 512 (card is for another geometry)"; return -1;
    }
    for (i = 0; i < MAX_FILES; i++) {
        char key[8], *sp;
        u32 fr = 0u;

        mkkey(key, "FILE", i);
        if (!meta_line(key, v, sizeof v)) break;
        sp = strchr(v, ' ');
        if (!sp) { err = "META: FILE line malformed"; return -1; }
        *sp = 0;
        if (!kv_u32(sp + 1, "FRAMES", &fr) || fr == 0u) {
            err = "META: FILE line without FRAMES"; return -1;
        }
        if (strlen(v) >= sizeof(fname[nfiles])) { err = "META: file name too long"; return -1; }
        memcpy(fname[nfiles], v, strlen(v) + 1);
        fframes[nfiles] = fr;
        nfiles++;
    }
    if (nfiles == 0u) { err = "META: no FILEn lines parsed"; return -1; }

    /* 卡上的帧数 = 各 FILEn 之和；FRAMES= 是生成时声明的总数。两者不等通常意味着
     * **卡是拷贝中断/被删过的**（板上实测：一张声明 4398 帧的卡只有 5 个文件 = 2099 帧，
     * 播到 2099 就 "frame index out of range" 停在半路，现场看起来就是"没有画面在播放"）。
     * 所以取两者的小值当可播长度，并把差异说清楚 —— 宁可少播，不要演到一半停住。 */
    {
        u32 i, sum = 0u;
        for (i = 0; i < nfiles; i++) sum += fframes[i];
        if (meta_trunc) {
            /* 清单尾部被切断：最后一个 FILE 行的数字可能只读到一半（今晚实测：
             * "FRAMES=512" 被切成 "FRAMES=51"）⇒ 少算的帧数是**假缺口**，卡本身没坏。 */
            meta_warn = "META.TXT longer than the buffer read - file list truncated";
            if (sum < total_frames) total_frames = sum;
        } else if (sum != total_frames) {
            meta_warn = "FRAMES != sum of FILEn (card content and manifest disagree)";
            if (sum < total_frames) total_frames = sum;
        } else {
            meta_warn = 0;
        }
    }
    return 0;
}

/* ============================ 解析器自检（ISSUES #43） ============================
 * 今晚的真实代价：kv_u32 的"关键字必须在词首"判据写错了（拿 .rodata 里 key 字面量的指针
 * 和串内位置比，永远不等 ⇒ 恰恰漏掉"关键字在串首"这一种），症状却是"这张卡的 META.TXT
 * 不合格" —— 判据错和被判的对象都只能通过同一块板子观察，所以连着三次上板才定位到。
 * 规则「判据本身要有自己的测试」在这里的落法：三段内置样本，一段必须过、两段必须被拒，
 * 不碰卡、微秒级；从此 "mount failed" 这句话分得清是固件坏了还是卡不对。
 *   ok  ：FILE1 那行故意放一个 XFRAMES=7 在前 —— 防误匹配那条判据被真正执行到。
 *   b1  ：FILE0 行没有 FRAMES= ⇒ 必须被拒（否则自检本身是摆设）。
 *   b2  ：把 FRAMES= 写成 SFRAMES= ⇒ 必须被拒（证明 meta_line 是行首锚定，不是子串搜索）。 */
static u32 put_dec(char *b, u32 v)
{
    char t[12];
    int n = 0, k = 0;
    do { t[n++] = (char)('0' + (v % 10u)); v /= 10u; } while (v);
    while (n) b[k++] = t[--n];
    b[k] = 0;
    return (u32)k;
}

static int meta_try(const char *txt, u32 exp_frames, u32 exp_files)
{
    const char *saved = err;
    u32 n = 0u;
    int rc;

    while (txt[n] && n < sizeof(Meta) - 1u) { Meta[n] = (u8)txt[n]; n++; }
    Meta[n] = 0u;
    /* 每一段样本都在 NUL 之后塞一行假的 FILE 记录：真去读一个簇时，文件后面就是上一个
     * 文件留下的垃圾（今晚正是这个让我把"尾字节非 0"当成了截断信号）。解析必须在 NUL 处
     * 停住 —— 所以这不是多一个用例，而是所有用例的共同前提。 */
    {
        static const char junk[] = "FILE99=BOGUS.BIN FRAMES=7\n";
        u32 k = 0u;
        while (junk[k] && (n + 1u + k) < (sizeof(Meta) - 1u)) { Meta[n + 1u + k] = (u8)junk[k]; k++; }
        Meta[n + 1u + k] = 0u;
    }
    rc = parse_meta();
    err = saved;
    return (rc == 0) && (total_frames == exp_frames) && (nfiles == exp_files);
}

static int meta_selftest(void)
{
    char fb[12], ok[256], b1[256], b2[256], b3[256], lg[900], nb[4];
    u32 i;
    int pass;

    meta_trunc = 0u;
    put_dec(fb, FRAME_BYTES);
    /* ok：FRAMES 与 FILEn 之和一致（900+450=1350），且 FILE1 那行先放一个 XFRAMES=7 ——
     * 这条专门执行"关键字必须是独立词"那条判据（今晚它写错成指针比较，见 ISSUES #43）。 */
    strcpy(ok, "# selftest\nFRAMES=1350\nFILES=2\nFILE0=VIDEO000.BIN FRAMES=900 BYTES=");
    strcat(ok, fb);
    strcat(ok, "\nFILE1=A.BIN XFRAMES=7 FRAMES=450\n");
    strcpy(b1, "# selftest\nFRAMES=900\nFILES=1\nFILE0=VIDEO000.BIN 900 BYTES=");
    strcat(b1, fb);
    strcat(b1, "\n");
    strcpy(b2, "# selftest\nSFRAMES=900\nFILES=1\nFILE0=VIDEO000.BIN FRAMES=900\n");
    /* b3：声明 900 帧但文件里只有 450 ⇒ 必须**按 450 收**（可播长度取小值）。
     * 这条就是今晚板上撞到的那一幕：卡在 2099/4398 帧处停住，现场以为没在播放。 */
    strcpy(b3, "# selftest\nFRAMES=900\nFILES=1\nFILE0=VIDEO000.BIN FRAMES=450\n");
    /* long_ok：一份**超过一个扇区**的清单（12 个 FILE 行）。今晚真实踩的那刀就在这儿 ——
     * 固件只读 1 个扇区且 Meta 只有 512 B，于是尾行的数字被从中间切成 "FRAMES=51"，
     * 卡明明是完整的（PC 重生成后 md5 逐字节相同）。这条样本长度也是判据的一部分：
     * 不 >512 就等于没测到那件事，所以连 strlen 一起断言。 */
    strcpy(lg, "# selftest\nFRAMES=1200\nFILES=12\n");
    for (i = 0; i < 12u; i++) {
        strcat(lg, "FILE");
        put_dec(nb, i);
        strcat(lg, nb);
        strcat(lg, "=VIDEO000.BIN FRAMES=100 BYTES=");
        strcat(lg, fb);
        strcat(lg, "\n");
    }

    pass = meta_try(ok, 1350u, 2u) &&
           (fframes[0] == 900u) && (fframes[1] == 450u) && (strcmp(fname[1], "A.BIN") == 0) &&
           (meta_warn == 0) &&
           !meta_try(b1, 900u, 1u) && !meta_try(b2, 900u, 1u) &&
           meta_try(b3, 450u, 1u) && (meta_warn != 0) &&
           (strlen(lg) > 512u) && meta_try(lg, 1200u, 12u) && (meta_warn == 0);
    total_frames = 0u;              /* 别让样本留下的半截状态冒充"卡里有 900 帧" */
    nfiles = 0u;
    meta_warn = 0;
    return pass;
}

int sd_mount(void)
{
    XSdPs_Config *cfg;
    u32 clus;

    err = "ok";
    if (mounted) { return 0; }   /* 见 ISSUES #45 */
    if (!meta_selftest()) {
        err = "META parser SELF-TEST failed (firmware bug, not the card)";
        return -1;
    }
    if (!dir_selftest()) {
        err = "cluster decode SELF-TEST failed (firmware bug, not the card)";
        return -1;
    }
    cfg = XSdPs_LookupConfig(SD_BASE);
    if (!cfg) { err = "XSdPs_LookupConfig NULL (SD0 not in the hardware)"; return -1; }
    if (XSdPs_CfgInitialize(&Sd, cfg, cfg->BaseAddress) != XST_SUCCESS) {
        err = "XSdPs_CfgInitialize failed"; return -1;
    }
    if (XSdPs_CardInitialize(&Sd) != XST_SUCCESS) {
        err = "card absent or CMD sequence failed"; return -1;
    }
    if (read_secs(0u, 1u, Sec) != 0) return -1;
    if (parse_bpb() != 0) return -1;

    clus = dir_lookup("META.TXT");
    if (!clus) { err = "META.TXT not found in root dir"; return -1; }
    /* META.TXT 现在是 712 B（9 个 FILE 行），**不能再假定它装得进一个扇区**：
     * 原来这里读 1 个扇区、Meta 也只有 512 B，于是第 5 个 FILE 行的数字被从中间切断
     * （"FRAMES=512" 读成 "FRAMES=51"），板上就看到 files=5 / Σ=2099，而卡本身逐字节是好的
     * （PC 上重生成后 md5 与卡上完全一致，包括 META）。⇒ 改成"读满首簇、上限 = 缓冲区/512"，
     * 并且尾字节非 0 就明确报"清单比能读的还大"，不再靠"应该够吧"。 */
    {
        u32 cap = (u32)(sizeof(Meta) / 512u);
        u32 nsec = (found_size + 511u) / 512u;
        if (nsec == 0u) nsec = 1u;
        /* "放不下"要按**文件长度**判，不能按缓冲区尾字节是否非 0 判：
         * 簇里文件后面是上一个文件留下的垃圾，拿尾字节当信号会把完整的清单报成截断
         * （今晚第一版修完就是这么假阳的：files=9 全对，却照样打了 WARN）。 */
        meta_trunc = (found_size > (u32)sizeof(Meta)) ? 1u : 0u;
        if (nsec > cap) nsec = cap;
        if (nsec > spc) nsec = spc;               /* 不越过首簇边界（只有簇内是连续的） */
        if (read_secs(clus_lba(clus, 0u), nsec, Meta) != 0) return -1;
        if (!meta_trunc) Meta[found_size] = 0u;   /* 清单到此为止，簇尾垃圾不参与解析 */
    }
    if (parse_meta() != 0) return -1;

    /* 挂载时就把**每个**片源文件的首簇量一遍（#50 的教训：簇号翻错的时候挂载、META、
     * 前 7 个文件全都正常，直到播到第 8 个才在屏幕上冻住 —— 代价是整整两分钟的演示）。
     * 分区装不下的簇号一定是坏的，不需要等到读到 OUT-OF-RANGE 才知道。 */
    {
        u32 i, max_clus, bad = 0u, first_bad = 0u;
        max_clus = (part_lba + part_sect > data_lba)
                 ? (part_lba + part_sect - data_lba) / spc + 2u : 0u;
        for (i = 0; i < nfiles; i++) {
            u32 c = dir_lookup(fname[i]);
            if (!c || c >= max_clus) { if (!bad) first_bad = i; bad++; }
        }
        if (bad) {
            meta_warn = "a frame file has an out-of-range first cluster";
            xil_printf("[SD] WARN %u/%u file(s) have cluster >= %u (first: %s)\r\n",
                       (unsigned)bad, (unsigned)nfiles, (unsigned)max_clus, fname[first_bad]);
        } else {
            xil_printf("[SD] dir map ok: %u files, first clusters within %u\r\n",
                       (unsigned)nfiles, (unsigned)max_clus);
        }
        FatLba = 0xFFFFFFFFu;                 /* 探针读过的 FAT 扇区不算数（缓存要作废） */
    }

    mounted  = 1;
    open_idx = 0xFFFFFFFFu;
    fed_cnt  = 0;
    fed_t0   = 0;
    return 0;
}

void sd_status(void)
{
    u32 i;
    if (!mounted) { xil_printf("[SD] not mounted: %s\r\n", err); return; }
    xil_printf("[SD] FAT32 part_lba=%d spc=%d rootclus=%d data_lba=%d\r\n",
               (int)part_lba, (int)spc, (int)root_clus, (int)data_lba);
    xil_printf("[SD] frames=%d fps=%d.%03d files=%d frame=%dB\r\n",
               (int)total_frames, (int)(fps_num / fps_den),
               (int)(((fps_num % fps_den) * 1000u) / fps_den), (int)nfiles, (int)FRAME_BYTES);
    for (i = 0; i < nfiles; i++)
        xil_printf("[SD]   %s frames=%d\r\n", fname[i], (int)fframes[i]);
    if (meta_warn)
        xil_printf("[SD] WARN %s: playing %d frames only\r\n", meta_warn, (int)total_frames);
}

/* ============================ 取帧 ============================ */

/* 帧号 → (文件号, 文件内帧号) */
static int frame_map(u32 idx, u32 *fi, u32 *off)
{
    u32 i;
    for (i = 0; i < nfiles; i++) {
        if (idx < fframes[i]) { *fi = i; *off = idx; return 0; }
        idx -= fframes[i];
    }
    return -1;
}

/*
 * 失败时打一行现场（只花一条串口命令行，平时不响）。
 * 为什么需要：板级实测过一次"#50 的读超时之后，`SD` 重新挂载一切正常、
 * 但 `PLAY` 立刻报 frame file not found" —— 而"挂载正常"其实是**假象**：
 * 挂载阶段打印的文件列表来自 META.TXT 的内容，不是目录扫描；META.TXT 又恰好
 * 落在根目录第一个簇里，所以挂载从来不需要走 FAT 链。真正失败的那一步
 * 是找 VIDEO000.BIN，它在根目录的**第二个簇**，必须先 `fat_next(root_clus)`。
 * 这一行现场就是用来把"名字被踩坏 / FAT 那一跳读不出来 / 卷参数变了"三种可能分开的。
 */
static void dir_diag(const char *name)
{
    char key[11];
    const char *saved = err;    /* 见下面的注释：探针自己也会改 err */
    u32 meta, nxtc;

    /* 观察者效应（2026-09-24 自己踩的）：dir_lookup / fat_next 内部读失败会把 err 改成
     * "SD read failed"，于是这行诊断**把要报的错覆盖掉了**——第一次跑就打印出
     * "playback stopped ... : SD read failed" 而不是真正的 "frame file not found"。
     * 诊断必须先存后还：报出来的错才是调用者那一路的错。 */
    meta = dir_lookup("META.TXT");              /* 对照组：同一次调用里能否找到 META */
    nxtc = fat_next(root_clus);                 /* 根目录第二簇：VIDEO000.BIN 依赖这一跳 */
    err  = saved;

    name83(name, key);
    xil_printf("[SDDBG] name='%s' k83=%02x%02x%02x%02x%02x%02x%02x%02x_%02x%02x%02x\r\n"
               "        root_clus=%d fat_next=%d meta_clus=%d spc=%d fat_lba=%d data_lba=%d\r\n",
               name,
               (unsigned)key[0], (unsigned)key[1], (unsigned)key[2], (unsigned)key[3],
               (unsigned)key[4], (unsigned)key[5], (unsigned)key[6], (unsigned)key[7],
               (unsigned)key[8], (unsigned)key[9], (unsigned)key[10],
               (int)root_clus, (int)nxtc, (int)meta, (int)spc, (int)fat_lba, (int)data_lba);
}

/* 打开第 i 个文件，并把簇游标推到第 off 帧的开头 */
static int open_at(u32 i, u32 off)
{
    u32 clus, skip, bpc = spc * 512u;

    if (i >= nfiles) { err = "file index out of range"; return -1; }
    clus = dir_lookup(fname[i]);
    if (!clus) {
        err = "frame file not found on card";
        dir_diag(fname[i]);
        return -1;
    }
    skip = (off * FRAME_BYTES) / bpc;                   /* 整簇跳过：只走 FAT，不读数据 */
    while (skip--) {
        clus = fat_next(clus);
        if (clus >= EOC) { err = "cluster chain too short"; return -1; }
    }
    ff_clus  = clus;
    ff_blk   = ((off * FRAME_BYTES) % bpc) / 512u;
    open_idx = i;
    return 0;
}

/*
 * 从当前游标读一帧到 FRAME_ADDR。逐簇读，因为簇链可以不连续；
 * 帧内跨簇的边界用目标指针偏移接起来。
 */
static int feed_cur(void)
{
    u32 left = FRAME_BYTES, dst = FRAME_ADDR;

    while (left) {
        u32 nsec  = spc - ff_blk;
        u32 bytes;
        if (nsec * 512u > left) nsec = left / 512u;
        bytes = nsec * 512u;
        if (bytes == 0u || ff_clus < 2u || ff_clus >= EOC) {
            err = "cluster chain ended early";
            return -1;
        }
        last_clus = ff_clus;            /* 供 read_secs 失败时打印（见 #50） */
        if (read_secs(clus_lba(ff_clus, ff_blk), nsec, (u8 *)dst) != 0) return -1;
        left    -= bytes;
        dst     += bytes;
        ff_blk  += nsec;
        if (ff_blk == spc) { ff_blk = 0u; ff_clus = fat_next(ff_clus); }
    }
    return 0;
}

static int show_frame(u32 idx)
{
    u32 fi, off;

    if (!mounted) { err = "not mounted"; return -1; }
    if (frame_map(idx, &fi, &off) != 0) { err = "frame index out of range"; return -1; }
    if (open_at(fi, off) != 0) return -1;
    if (feed_cur() != 0) return -1;
    ps_publish();
    return 0;
}

int sd_show(u32 idx)
{
    if (idx >= total_frames) { err = "frame index out of range"; return -1; }
    nxt = idx;
    return show_frame(idx);
}

u32 sd_frame_now(void)   { return nxt; }
u32 sd_frame_total(void) { return mounted ? total_frames : 0u; }

int sd_play(int on)
{
    if (on && !mounted) { err = "not mounted"; return 0; }
    playing = on ? 1 : 0;
    if (playing) {
        nxt = 0;
        XTime_GetTime(&last_t);
        XTime_GetTime(&rpt_t);          /* 速率窗口从本次播放开始算，别把上一次会话的空闲算进来 */
        rpt_cnt = fed_cnt;
        if (!fed_t0) XTime_GetTime(&fed_t0);
    }
    return playing;
}
int sd_is_playing(void) { return playing; }

/* 已喂帧的平均帧率，单位 mfps（×1000）。xil_printf 没有 %f，所以用整数打印 */
static u64 avg_fps_milli(void)
{
    XTime now;
    u64 dt;

    if (fed_cnt == 0u || fed_t0 == 0u) return 0u;
    XTime_GetTime(&now);
    dt = (u64)(now - fed_t0);
    if (dt == 0u) return 0u;
    return (u64)fed_cnt * 1000u * (u64)COUNTS_PER_SECOND / dt;
}

/*
 * 主循环每次调用；到点就喂一帧。
 * 不用"usleep 到下一帧"：那样 UART 命令要等到睡完才被轮询，STOP 会明显发钝。
 * 喂帧本身最长就是一次 300 KB 的 SD 读取，那个时间同时决定了本项目的实际帧率上限。
 */
void sd_tick(void)
{
    XTime now;
    u64 need;

    if (!playing) return;
    need = ((u64)COUNTS_PER_SECOND * fps_den) / fps_num;
    XTime_GetTime(&now);
    if ((u64)(now - last_t) < need) return;

    if (nxt >= total_frames) nxt = 0;                   /* 循环播放 */
    if (show_frame(nxt) != 0) {
        playing = 0;
        /* 一次读失败之后卡/控制器多半还停在半途传输里（今晚实测：第 3584 帧超时，紧接着
         * 重放时 `dir_lookup` 找不到文件 —— 因为后续每一个读都会失败）。所以这里把游标
         * 清干净再报，操作者按一次 PLAY 就会从簇链头重新走；仍不行就是控制器要重初始化，
         * 见 ISSUES #45/#50（重下 elf 约 20 秒）。 */
        open_idx = 0xFFFFFFFFu;
        FatLba   = 0xFFFFFFFFu;
        xil_printf("[SD] playback stopped at frame %d: %s (PLAY retries; if it keeps failing, re-download the elf)\r\n",
                   (int)nxt, err);
        return;
    }
    nxt++;
    fed_cnt++;
    last_t = now;
    if ((fed_cnt % 100u) == 0u) {
        /* 两个数都要报，但含义必须分清：
         *   last N frames = 这 100 帧自己的耗时 ⇒ 板子当下的真实速率（受 SD 读带宽限制）；
         *   since play    = 自"上一次开始播放"起的平均 ⇒ 含停顿/换卡的时间，只能当占空比看。
         * 原来只报后者却写作 "avg fps"，读的人会当成帧率（今晚实测：同一时刻一个报 1.449、
         * 一个是 30，因为前者把两次播放会话之间的空闲也算进了分母）。 */
        u64 span = (u64)(now - rpt_t);
        u32 win = fed_cnt - rpt_cnt;
        u64 w = span ? (u64)win * 1000u * (u64)COUNTS_PER_SECOND / span : 0u;
        u64 f = avg_fps_milli();
        xil_printf("[SD] frame %d: last %u frames %d.%03d fps (since play %d.%03d)\r\n",
                   (int)nxt, win, (int)(w / 1000u), (int)(w % 1000u),
                   (int)(f / 1000u), (int)(f % 1000u));
        rpt_t = now;
        rpt_cnt = fed_cnt;
    }
}
