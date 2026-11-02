# 实现与验证报告

| 文件 | 内容 |
|---|---|
| `timing_summary.rpt` | 最终版时序：WNS 1.368 ns、WHS 0.048 ns、TNS/THS 为 0、失败端点 0 |
| `utilization.rpt` | 最终版资源：LUT 14 965、FF 9 097、BRAM 98、DSP 19 |
| `build_timing_summary.rpt` | 优化前基线时序（WNS 1.341 ns、WHS 0.025 ns），用于 2.5 节前后对照 |
| `build_utilization.rpt` | 优化前基线资源（LUT 14 967、FF 9 095），用于 2.5 节前后对照 |
| `cdc.rpt` | 跨时钟域检查 |
| `methodology.rpt` | Vivado 方法学检查 |
| `power.rpt` | 功耗与结温估算 |
| `route_status.rpt` | 布线状态 |
| `clock_util.rpt` | 时钟资源使用 |
| `check_timing_verbose.rpt` | 未约束/恢复/移除检查 |
| `regression.txt` | 标准回归汇总 |
| `tb_video_pipeline_top_report.txt` | 完整视频台架 完整视频台架专项/完整视频专项/完整视频专项 判定 |
| `udp_checksum.txt` | UDP 校验和专项复验 |
| `c31_edge_rim.log` | 帧尾两行抽头专项复验 |
