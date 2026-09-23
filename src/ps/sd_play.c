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
#define FRAME_ADDR     0x10000000u               /* = pl_video_top 的 BASE_ADDR */

#define SD_BASE        XPAR_XSDPS_0_BASEADDR
#define MAX_FILES      16u
#define EOC            0x0FFFFFFFu               /* 链尾 / 错误的共同哨兵 */

static XSdPs Sd;
static u8  Sec[512] __attribute__((aligned(64)));    /* 扇区缓冲（MBR/BPB/目录/FAT 复用） */
static u8  Fat[512] __attribute__((aligned(64)));    /* FAT 扇区缓存 */
static u8  Meta[512] __attribute__((aligned(64)));   /* META.TXT 的第一扇区 */
static u32 FatLba = 0xFFFFFFFFu;

static const char *err = "ok";
static int mounted;

/* FAT32 卷参数 */
static u32 part_lba, spc, fat_lba, data_lba, root_clus;

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
static XTime last_t, fed_t0;

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
        Xil_DCacheFlushRange((INTPTR)dst, (s32)(n * 512u));
        if (XSdPs_ReadPolled(&Sd, lba, n, dst) != XST_SUCCESS) {
            err = "SD read failed";
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
    part_lba = ld32(&Sec[446 + 8]);
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
                return ((u32)d[20] << 24) | ((u32)d[21] << 16) | (u32)ld16(&d[26]);
            }
        }
        c = fat_next(c);
    }
    return 0;
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
    rc = parse_meta();
    err = saved;
    return (rc == 0) && (total_frames == exp_frames) && (nfiles == exp_files);
}

static int meta_selftest(void)
{
    char fb[12], ok[256], b1[256], b2[256];
    int pass;

    put_dec(fb, FRAME_BYTES);
    strcpy(ok, "# selftest\nFRAMES=900\nFILES=2\nFILE0=VIDEO000.BIN FRAMES=900 BYTES=");
    strcat(ok, fb);
    strcat(ok, "\nFILE1=A.BIN XFRAMES=7 FRAMES=450\n");
    strcpy(b1, "# selftest\nFRAMES=900\nFILES=1\nFILE0=VIDEO000.BIN 900 BYTES=");
    strcat(b1, fb);
    strcat(b1, "\n");
    strcpy(b2, "# selftest\nSFRAMES=900\nFILES=1\nFILE0=VIDEO000.BIN FRAMES=900\n");

    pass = meta_try(ok, 900u, 2u) &&
           (fframes[0] == 900u) && (fframes[1] == 450u) && (strcmp(fname[1], "A.BIN") == 0) &&
           !meta_try(b1, 900u, 1u) && !meta_try(b2, 900u, 1u);
    total_frames = 0u;              /* 别让样本留下的半截状态冒充"卡里有 900 帧" */
    nfiles = 0u;
    return pass;
}

int sd_mount(void)
{
    XSdPs_Config *cfg;
    u32 clus;

    err = "ok";
    if (!meta_selftest()) {
        err = "META parser SELF-TEST failed (firmware bug, not the card)";
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

    /* META.TXT 只有一百多字节，读它首簇的第一个扇区就够 */
    clus = dir_lookup("META.TXT");
    if (!clus) { err = "META.TXT not found in root dir"; return -1; }
    if (read_secs(clus_lba(clus, 0u), 1u, Meta) != 0) return -1;
    if (parse_meta() != 0) return -1;

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

/* 打开第 i 个文件，并把簇游标推到第 off 帧的开头 */
static int open_at(u32 i, u32 off)
{
    u32 clus, skip, bpc = spc * 512u;

    if (i >= nfiles) { err = "file index out of range"; return -1; }
    clus = dir_lookup(fname[i]);
    if (!clus) { err = "frame file not found on card"; return -1; }
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
        xil_printf("[SD] playback stopped at frame %d: %s\r\n", (int)nxt, err);
        return;
    }
    nxt++;
    fed_cnt++;
    last_t = now;
    if ((fed_cnt % 100u) == 0u) {
        u64 f = avg_fps_milli();
        xil_printf("[SD] %d frames fed, avg %d.%03d fps\r\n",
                   (int)fed_cnt, (int)(f / 1000u), (int)(f % 1000u));
    }
}
