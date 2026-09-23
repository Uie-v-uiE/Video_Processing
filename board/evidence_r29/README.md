R29 板上取证时的串口原始抓包，四份，每份对应一条写进报告的结论：

| 文件 | 命令 | 支撑的结论 |
|---|---|---|
| `mount_with_warn.txt` | `SD` | 挂载打印 `FAT32 part_lba=2048 … frames=4398 files=5` + `WARN … playing 2099 frames only`（卡只拷了 5/9 个文件 ⇒ 固件取小值并出声，ISSUES #43） |
| `rate_12s_window.txt` | `SD,PLAY,STOP`，命令间隔 12 s | 一次干净会话里 `STOP` 回报 **360 帧 / 12 s = 30.0 fps**；`SENT 3/3` 同时自证"三条命令真的都发出去了" |
| `play_150s_windows.txt` | `SD,PLAY` 持续 150 s（build#22，屏幕上还看不到） | 46 个"100 帧窗口"全 29.999 ⇒ PS→DDR 这一跳早就在 30 fps 跑，"看不到"不是它的问题（这就是把矛头指向显示级的那条证据） |
| `play_on_build23.txt` | 只读 62 s（build#23，画面已在屏上） | 19 个窗口全 29.999（最低 29.495），且"自播放起平均"与"窗口值"这次一致（29.84 vs 29.999）⇒ 修复后回放速率没变、也不再靠帧号回绕骗人 |

抓包工具：`board/uart_cap_once.ps1`（只用 Windows 自带 SerialPort；`-CmdDelay` 是板子那侧真实经过的时间，
所以"帧数 ÷ 间隔"这种判据能自己成立）。
注：抓包里的中文注释被 `xil_printf` 打成 `?` 是已知行为（最小号 printf 只走 ASCII），报告引用的是数字部分。
