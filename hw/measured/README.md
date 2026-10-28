# 板上实测

| 文件 | 内容 | 性质 |
|---|---|---|
| `flash_jtag.txt` | JTAG 三步链与 GPIO 回读 | JTAG 路径证据 |
| `health.txt` | 串口、JTAG、异常向量快照 | 当前证据 |
| `qspi_program.txt` | QSPI 擦除、写入、回读校验 | 当前证据 |
| `telemetry_8s.txt` | 8 秒推流的 1 Hz 遥测 | 当前证据 |
| `link_selftest.txt` | 干净 → 丢包 → 恢复三阶段自检 | 当前证据 |
| `uart_battery.txt` | 串口命令电池 | 当前证据 |
| `sd_playback.txt` | SD 选段续播 | 支持性；link 改动不涉及 SD |
| `pane_integrity.txt` | 185° 处理窗完整性 | 支持性；同一 RTL 的显示侧证据 |
| `link_gap.txt` | 帧间隔统计（冷启动后实测） | 当前证据 |
| `cold_boot.txt` | QSPI 断电冷启动（实测） | 当前证据 |
| `uart_battery_capture.txt` | 105 条命令的原始串口捕获 | 原始捕获 |
