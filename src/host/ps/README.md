# PS 侧固件（`main.c` / `sd_play.c` / `lscript_ocm.ld`）

## 重编 ELF 的步骤（本机不可跑，见末行）

1. Vivado：`build/tcl/create_project.tcl` 建工程 → `build/tcl/build_system_axigpio.tcl` 出
   `build/system.xsa`（要构建只认这一支；两条同族历史脚本 `add_files` 指错路径、报错后仍 exit 0）。
2. Vitis：File → New → Platform from XSA，选 `build/system.xsa`；BSP 需 `lwip`、`xuartps`、`xgpio`。
3. New Application，应用名 `video_ps`，源文件用本目录的 `main.c`、`sd_play.c`、`sd_play.h`，
   链接脚本换成本目录的 `lscript_ocm.ld`（OCM 启动版）。
4. DDR 分配：PS 帧缓冲在 `0x10100000`（`src/host/ps/main.c:46` 的 `FRAME_ADDR`，
   行 19 的注释同时写明 ETH 用 `0x10000000` 与 `0x10080000` 两块）。
5. 控制台：UART0 115200 8N1，走 FT2232 的第二通道；板上读回不走串口，读回用 JTAG（`micro_rd.tcl`）。
6. 下载顺序（bit → 应用）与三步命令见 `report/build.md` §3；日常刷板用
   `bash build/r116_bit_cycle.sh <标签> [位流路径]`，它自己会把三步跑掉。

## EMIO GPIO 位表（第一控制字，32 位）

| 位 | 含义 | 现值来源 |
|---|---|---|
| `[4:0]` | 老五位效果使能，已退役（读回恒 0） | `src/host/ps/main.c:55` |
| `[15:8]` | 阈值 | 同上 |
| `[16]` | `src_sel` 0=图卡 1=DDR | 同上 |
| `[17]` | `zoom_en` | 同上 |
| `[18]` | `publish` | 同上 |
| `[19]` | `bilin` | 同上 |
| `[20]` | OSD 关位 | `src/host/ps/main.c:57` |
| `[22]` | 模式翻转位 | `src/host/ps/main.c:63` |
| `[24:23]` | 模式码 00 自动 / 01 ETH / 11 SD / 10 TEST | `src/host/ps/main.c:59`（编码表）、`:64`（位起点） |
| `[26]` | `gapclr` | `src/host/ps/main.c:62` |
| `[31:27]` | lane 号 | 同上 |

第二控制字（BD 里的 `axi_gpio_2`，双通道 ×32 位纯输出）见 `src/host/ps/main.c` 的
`/* ---- V8-2：第二条控制字` 一节。

## 本机限制

本机没有 `arm-none-eabi-gcc`（也没有 `python3`），所以上面 1–3 步只能在装有 Vitis 的机器上跑；
仓库里随包的 `build/ps_app.elf` 是 2026-10-04 之前编好的那一份，本轮未重编
（凭据：`build/r118_gates_final.txt` 的 `ps_app.elf md5=d0b07f84a068` 与上一版同一枚）。
