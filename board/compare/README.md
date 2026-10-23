# 实测与参考结果比对

这一页把交付读数对回实现报告和板上日志。数字只在 `data/metrics.csv` 和设计报告里各出现一次；这里给“读数 ↔ 证据”的对照，不另造一套数。

| 指标 | 交付读数 | 参考/证据 | 比对结果 |
|---|---|---|---|
| 全局 setup WNS | 1.341 ns | `build/reports/build_timing_summary.rpt` | 一致 |
| 全局 hold WHS | 0.025 ns | `build/reports/build_timing_summary.rpt` | 一致 |
| TNS / THS | 0 / 0 | `build/reports/build_timing_summary.rpt` | 一致 |
| LUT / FF | 14 967（28.13%）/ 9 095（8.55%） | `build/reports/build_utilization.rpt` | 一致 |
| BRAM / DSP | 98（70.00%）/ 19（8.64%） | `build/reports/build_utilization.rpt` | 一致 |
| 动态功耗 | 2.228 W | `build/reports/power.rpt` | 一致（工具估算） |
| 8 秒推流 | 241 帧 / 8.05 s / 29.95 fps | `board/measured/telemetry_8s.txt` | 与发送端 241 帧一致 |
| 三阶段自检 | 22.0 / 0 / 18.9 fps；故障段 14.3 次作废/秒 | `board/measured/link_selftest.txt` | PASS |
| 帧间隔 | 推流 `gap_last=28 ms`、`gap_max=49 ms`；重启后 `gap_max=22 061 ms` | `board/measured/link_gap.txt` | 通过 |
| QSPI 冷启动 | `DONE=1`、`EOS=1`、无 CRC/IDCODE 错误；ping 5/5 | `board/measured/cold_boot.txt` | 通过 |
| 串口电池 | 105 条 / 97.8 s / PASS | `board/measured/uart_battery.txt`、`uart_battery_capture.txt` | 通过 |
| 处理窗完整性 | `pane_bad=0`、`pane_valid=1` | `board/measured/pane_integrity.txt` | 通过 |

## 对账口径

- 时序/资源/功耗：以 `build/reports/` 的布线后报告为准；工具估算功耗只看量级。
- 板上读数：以 `board/measured/` 的原始日志为准；测试条件写在 `data/metrics.csv` 的“测量条件”列。
- 参考图：`data/golden/` 是人眼比对参照，不是自动黄金参考；逐像素正确性由台架和板上计数负责。
- 旧版 `metric_recheck.mjs` 依赖旧的 README 表格式，不再作为最终门禁；本页的表由交付读数与报告逐项人工对照。
