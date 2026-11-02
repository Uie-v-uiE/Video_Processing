# System 构建与 PS 上板（Vivado 2025.2.1）

## 已生成
| 文件 | 说明 |
|------|------|
| `output/system.bit` | system_top 比特流（含 PS7 + HP0 + PL） |
| `output/system.xsa` | Vitis 平台描述 |

## 下载 bit（JTAG）
```bat
D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat -mode batch -source tcl\program_board.tcl
```
或用 `output/system.bit` 手动 program。

> **注意**：system bit 含 PS。仅 program bit 时 FCLK0 可能不跑；需再下载 elf（Vitis）或从 SD/QSPI 启动 FSBL+elf。

## Vitis 建应用
1. 打开 Vitis：`D:\Software\Vivado\2025.2.1\Vitis\bin\vitis.bat`
2. **File → New → Platform**，选 `output/system.xsa`
3. BSP 勾选：`xuartps`, `xgpio`（以太网阶段再加 `lwip`）
4. **New Application**，加入 `sw/ps/main.c`
5. Build → 得到 `.elf`
6. **Run → Launch** 下载到板（JTAG）

## 串口
- FT2232 Channel A，默认 115200
- 命令：
  - `00111` → 启用 blur+sobel+invert（右半屏应变化）
  - `10000` → 仅灰度
  - `SRC0` → 彩条
  - `FILL` → 往 DDR 写渐变并 `src_sel=1`（测 AXI 读）
  - `SRC1` → 切 DDR（需先 FILL 或 UDP 收帧）

## 以太网阶段（后续）
在现有 main 上合并 `sw/ps/main.c` 历史里的 lwIP UDP 版本：
- IP `192.168.1.10`，UDP `5001`
- `python sw/host/video_sender.py --ip 192.168.1.10 --image sim_out/src.png`

## 现象预期
| 操作 | HDMI |
|------|------|
| 上电 + 仅 bit + elf | 左彩条（可旋转），右按使能变化 |
| 串口 `FILL` | 左右变为彩色渐变（DDR 路径） |
| 串口 `00111` | 右半模糊+边缘+反色 |
| KEY1/2 | 旋转 |
