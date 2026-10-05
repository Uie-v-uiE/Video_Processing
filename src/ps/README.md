# PS 侧固件（`main.c` / `sd_play.c` / `lscript_ocm.ld`）

## 重编 ELF 的步骤（本机不可跑，见末行）

1. Vivado：`build/tcl/create_project.tcl` 建工程 → `build/tcl/build_system_axigpio.tcl` 出
   `build/system.xsa`（要构建只认这一支；两条同族历史脚本 `add_files` 指错路径、报错后仍 exit 0）。
2. Vitis：File → New → Platform from XSA，选 `build/system.xsa`；BSP 需 `lwip`、`xuartps`、`xgpio`。
3. New Application，应用名 `video_ps`，源文件用本目录的 `main.c`、`sd_play.c`、`sd_play.h`，
   链接脚本换成本目录的 `lscript_ocm.ld`（OCM 启动版）。
4. DDR 分配：PS 帧缓冲在 `0x10100000`（`src/ps/main.c:46` 的 `FRAME_ADDR`，
   行 19 的注释同时写明 ETH 用 `0x10000000` 与 `0x10080000` 两块）。
5. 控制台：UART0 115200 8N1，走 FT2232 的第二通道；板上读回不走串口，读回用 JTAG（`micro_rd.tcl`）。
6. 下载顺序（bit → 应用）与三步命令见 `report/build.md` §3；日常刷板用
   `bash build/r116_bit_cycle.sh <标签> [位流路径]`，它自己会把三步跑掉。

## EMIO GPIO 位表（第一控制字，32 位）

| 位 | 含义 | 现值来源 |
|---|---|---|
| `[4:0]` | 老五位效果使能，已退役（读回恒 0） | `src/ps/main.c:55` |
| `[15:8]` | 阈值 | 同上 |
| `[16]` | `src_sel` 0=图卡 1=DDR | 同上 |
| `[17]` | `zoom_en` | 同上 |
| `[18]` | `publish` | 同上 |
| `[19]` | `bilin` | 同上 |
| `[20]` | OSD 关位 | `src/ps/main.c:57` |
| `[22]` | 模式翻转位 | `src/ps/main.c:63` |
| `[24:23]` | 模式码 00 自动 / 01 ETH / 11 SD / 10 TEST | `src/ps/main.c:59`（编码表）、`:64`（位起点） |
| `[26]` | `gapclr` | `src/ps/main.c:62` |
| `[31:27]` | lane 号 | 同上 |

第二控制字（BD 里的 `axi_gpio_2`，双通道 ×32 位纯输出）见 `src/ps/main.c` 的
`/* ---- V8-2：第二条控制字` 一节。

## 重建这颗 ELF

上面 1–3 步在本机就能跑：编译器在 `<Vitis>/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe`
（自述 `arm-xilinx-eabi-gcc (GCC) 13.3.0`，它不在 `PATH` 上，所以要显式给 `PS_CC`），
`PS_BSP` 要给**绝对路径**（给相对路径时 gcc 会去找 `vitis\platform\…\Xilinx.spec` 而读不到）。实跑记录在
`build/evidence/1005_ps_app_rebuild.txt`：编译与链接都成功，尾部打印 `ENTRY _boot@0x000000cc` 与 `OK`。
重建出来那颗 md5 = `4ed58740785c158c89c0fbc80a0e9d39`，**没有**替换随包这颗：仓库里 `build/ps_app.elf`
是 `d0b07f84a0683db203086fb816ac71d7`（`build/r118_gates_final.txt` 的 `ps_app.elf md5=d0b07f84a068`），
板上复验过的行为只绑这一颗；换 ELF 之后必须再跑一次 `bash build/board_verify.sh` 才谈得上等价。
另有一条本机事实：`python3` 这个别名不存在（`python` 是 3.12），宿主脚本一律写 `python`。
