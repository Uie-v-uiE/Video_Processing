# 上位机工具

`src/host/` 放 PC 侧工具：推流、遥测、仪表、自检、串口判据和 JTAG 读回。板上固件在 `src/ps/`，RTL 在 `src/rtl/`。

## 依赖

- Python 3.10+：只用标准库（`argparse`、`socket`、`struct`、`subprocess`），不需要 pyserial。
- Node.js 18+：只用内置模块（`node:dgram`、`node:child_process`），零第三方包。
- JTAG 读回需要 Vitis 的 `xsdb`，路径用环境变量 `VP_XSDB` 或 `--xsdb` 给。
- 串口命令判据调用 `hw/scripts/uart_cmd_script.ps1`，需要 PowerShell 与空闲的 COM6。

## 推流

```bash
python src/host/video_sender.py --demo --seconds 8
python src/host/video_sender.py --input clip.mp4
python src/host/udp_push.py --pattern edge --fps 15 --drop-every 100
```

- 目标板卡 `192.168.1.10`，UDP 5001；源画幅固定 512×300、RGB565。
- 每包不超过 1392 字节，载荷前 4 字节是帧内偏移。
- `--demo` 不需要 ffmpeg；`--input` 需要 ffmpeg。
- `udp_push.py --drop-every 100` 用于故障注入：每 100 包丢 1 包。

## 遥测与仪表

```bash
python src/host/telemetry_listen.py 13
python src/host/instrument_dashboard.py
```

- 遥测从 UDP 1234 发出，1 Hz，32 字节；发给最后一个 ARP 请求方。
- 先 `ping 192.168.1.10` 一次，再启动监听；Windows 防火墙要放行 UDP 1234。
- 字段包括帧数、包数、坏包、作废、缺行、PL 内部时延、处理窗完整性。

## 自检

```bash
python src/host/link_selftest.py 192.168.1.10 6
```

三阶段：干净流 → 每 100 包丢 1 包 → 干净流。判据取每秒变化量：

- 干净段：帧率 ≥ 8 fps，作废最多一次启动作废，至少一次有效时延 ≤ 200 ms；
- 故障段：作废 ≥ 5 次/秒，帧率 < 5 fps；
- 恢复段：回到干净流水平。

末尾打印 `PASS link_selftest` 或失败阶段。

## 串口判据

```bash
node src/host/uart_cmd_check.mjs --port COM6
```

105 条命令逐条对回声，末态必须回到初态。判据文件是 `hw/scripts/cmd_battery_v81.txt`，传输走 `hw/scripts/uart_cmd_script.ps1`。

## JTAG 读回

```bash
node src/host/health_read.mjs --gpio0 41200000 --gpio1 41210000
node src/host/health_read.mjs --gapclr
```

- 通过 AXI GPIO 读 PL 的 10 条 lane：丢字、坏包/作废、停滞、帧间隔、CDC、flags、包数、字节数。
- `--gapclr` 在读之前把帧间隔统计清零（lane3/4/5）。
- 需要 `VP_XSDB` 指向 `xsdb.bat`，并且 hw_server 在 `localhost:3121`。

## 几何与指标

```bash
node src/host/geom_check.mjs
node src/host/metrics.mjs --out hw/evidence --tag clean30
node src/host/metric_recheck.mjs
```

- `geom_check.mjs` 检查命令 → CFG_DATA0 → lane23 的几何最后一跳。
- `metrics.mjs` 采集帧率、包率、作废、时延和帧间隔。
- `metric_recheck.mjs` 把 `data/metrics.csv` 的数字对回实现报告。

## 一键测试

```bash
python src/host/one_click_test.py
node src/host/one_click_test.mjs
```

四步：ping、连接、发送、收集；每步末尾给 `PASS` / `FAIL` / `NOT_MEASURED`，最后一行是 `ONE-CLICK` 总结论。没有板子时加 `--dry-run`，不碰网络和板子。

## 参数

| 参数 | 含义 | 默认 |
|---|---|---|
| `--ip` | 板卡地址 | `192.168.1.10` |
| `--port` | UDP 目标端口 | `5001` |
| `--fps` | 推流帧率 | 30 |
| `--pace-mbps` | 发送限速 MB/s，0 = 不限速 | 20 |
| `--gpio0` / `--gpio1` | AXI GPIO 基址 | `41200000` / `41210000` |
| `--xsdb` | xsdb 可执行文件 | 环境变量 `VP_XSDB` |
| `--dry-run` | 只打印计划，不 ping、不连板、不发包 | 关 |
