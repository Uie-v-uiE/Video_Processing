/*
 * SD 卡本地回放的 PS 侧接口（见 sd_play.c 与 report/OVERNIGHT_LOG.md §P1）。
 *
 * 数据流：SD(DMA) → DDR@BASE_ADDR →（PL 在 frame_start 拉一次 HP0 复制）→ 显示帧缓存。
 * PS 全程不做 memcpy：SD 控制器的 DMA 直接落到 PL 要读的那块 DDR，
 * 所以只需要一次"发布"动作告诉 PL：这块内容可以拷了。
 */
#ifndef SD_PLAY_H
#define SD_PLAY_H

#include "xil_types.h"

/* 挂载并解析卡上的视频帧库。返回 0=成功，其余为错误码（sd_err 里有文字说明） */
int sd_mount(void);

/* 打印卡/文件系统/帧库摘要，用于串口验收 */
void sd_status(void);

/* 起停回放（on=1 起，0 停）。返回当前是否在播 */
int sd_play(int on);
int sd_is_playing(void);

/* 主循环里每次调用；到点就喂一帧。不阻塞超过一帧的读取时间 */
void sd_tick(void);

/* 单帧跳转/播放（idx 越界返回 -1） */
int sd_show(u32 idx);
u32 sd_frame_now(void);
u32 sd_frame_total(void);

/* 错误原因（静态串，永不释放） */
const char *sd_err(void);

/*
 * 通知 PL "DDR 里这一帧已经完整了，请在下一个 frame_start 复制一次"。
 * 实现在 main.c —— 只有它拥有那根 AXI GPIO 控制字，回放模块不该去改别人的位。
 */
void ps_publish(void);

#endif
