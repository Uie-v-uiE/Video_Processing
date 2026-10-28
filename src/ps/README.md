# PS 裸机固件

`src/ps/` 放 Zynq PS 侧裸机应用：

| 文件 | 作用 |
|---|---|
| `main.c` | 启动、UART 命令分派、AXI GPIO 控制/回读、XADC 温度、`link` 帧间隔统计 |
| `sd_play.c` / `sd_play.h` | FAT32 解析、目录查找、簇链读取、SD 帧序列播放 |
| `lscript_ocm.ld` | OCM 启动链接脚本 |

PS 不参与像素通路。它写控制字、读健康状态，并在 SD 回放时把帧写进 DDR；ETH 视频字节不经过 PS。

## 构建

```bash
PS_CC=<Vitis>/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe \
PS_BSP=<平台构建生成的 BSP 目录> \
PS_OUT=hw/project/ps_app.elf \
python scripts/ps/build_ps_app.py
```

`PS_BSP` 必须指向一个已经 generate 过的 Zynq standalone BSP（里面有 `include/` 与 `lib/libxil.a`）。没有平台时先按 `hw/vitis/README.md` 用 `scripts/vitis/rebuild_vitis.py` 重建。

编译脚本会检查 `_start`、`_boot`、`_vector_table`、`MMUTable`、`main` 和 `XSdPs_CardInitialize` 是否在 ELF 里，防止把空镜像下到板上。

## 启动

- JTAG：`hw/scripts/board_flash.sh` 做 `ps7_init` → PL → ELF → GPIO 回读；
- QSPI：`hw/scripts/make_boot_image.sh` 打 `BOOT.bin`，`hw/tcl/flash_qspi.tcl` 写入；
- 断电后从 QSPI 启动；JTAG 下载是易失的。

## 控制字

| 位 | 含义 |
|---|---|
| 8:0 | 效果链九位选择：灰度、反色、模糊、锐化、Sobel、二值化、判决反相、腐蚀、膨胀 |
| 18:9 | 几何控制：缝位、auto/follow/swap/marker、rot_auto、rot_speed、zoom_fit |
| 19 | 双线性开关 |
| 20 | OSD 开关 |
| 26 | 帧间隔统计清零 |
| 31:27 | AXI GPIO lane 号 |

新增控制位往高位加，不重排已有位；RTL 位定义、固件写出的字和上位机掩码三处保持同源。

## 命令

`stat`、`temp`、`link` / `link clr`、`src`、`pipe`、`zoom`、`rot`、`split`、`gamma`、`osd`、`sd`、`play`、`stop`、`fill`、`autoplay`、`th`、`echo`、`help`。

- `link` 从 PL `link_monitor` 读 `gap_last/min/max/sum`、`gap_valid`、`live`；
- `link clr` 在读之前清零；
- `sd file n` 选段后 `play` 从该段续播；
- `temp` 打印 XADC 温度、VCCINT、OSD 编码和 GPIO 回读。

命令表、帮助行和分派三处要一起改；只在源码里写函数、不接进 `dispatch`，板上会回“不认”。

## SD 回放

`sd_play.c` 自解析 FAT32 BPB、目录和簇链，不依赖文件系统库。卡必须是 FAT32，帧序列由 `src/host/make_sd_video.mjs` 生成。`sd files` 列出段，`sd file n` 选段，`play` 播放，`stop` 停止。

## 温度

XADC 读片上温度与 VCCINT；`[TEMP]` 行同时打印 `degC`、`raw`、`vccint`、`osd` 和 `gpio`，把驱动读数、OSD 编码和 PL 侧同步链回读三件事对在一起。
