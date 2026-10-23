# 指标

这份指标只记能从提交包重算的数量，不写 token、费用或“节省了多少时间”这类无法复核的数。

## 1 协作规模

| 项 | 读数 | 出处 |
|---|---:|---|
| 会话卡 | 6 | `sessions/s01.md` … `s06.md` |
| 关键 Issue | 20 | `report/issues/key-issues.md` |
| 技能条目 | 59 | `skill/` 下 59 个 `SKILL.md` |
| 标准回归 | 19 | `sim/results/regression.txt`，`fail=0` |
| 完整视频专项 | C17/C25/C26 | `sim/results/tb_video_pipeline_top_report.txt`，`nfail=0` |
| 串口命令电池 | 105 | `board/measured/uart_battery_capture.txt` |
| 提交树文件数 | 见 `build/make_release.py` 的构建输出 | release 构建日志 |

## 2 板上读数

| 项 | 读数 |
|---|---|
| QSPI 冷启动 | `DONE=1`、`EOS=1`、无 CRC/IDCODE 错误、ping 5/5 |
| 连续流 | 241 帧 / 8.05 s = 29.95 fps |
| 三阶段自检 | 22.0 / 0 / 18.9 fps |
| 帧间隔 | `gap_max=22 061 ms`，推流中 `gap_valid=1` |
| 健康 | `HEALTH: GREEN` |
| 温度 | XADC 61.8–63.8 °C，`sane=1` |

## 3 实现读数

| 项 | 读数 |
|---|---|
| WNS / WHS | 1.341 ns / 0.025 ns |
| TNS / THS | 0 / 0，失败端点 0 |
| LUT / FF | 14 967（28.13%）/ 9 095（8.55%） |
| BRAM / DSP | 98（70.00%）/ 19（8.64%） |
| 功耗 / 结温 | 2.228 W 动态、2.406 W 总功耗 / 52.8 °C（工具估算） |

## 4 没有测的项

- token 用量和费用：原始导出没有落 usage 字段，不估算。
- 端到端玻璃到玻璃时延：遥测只覆盖 PL 内部，不含编码、网线和显示器。
- 1080p、多路输入、压缩码流：不在当前器件和本题范围内。
- 板上功耗：只做了 XADC 温度，没有功耗计读数。

## 5 怎么复核

- 仿真：`sim/results/` 的判定行。
- 实现：`build/reports/` 的时序、资源、功耗报告。
- 板级：`board/measured/` 的原始日志。
- 文档：`report/verification.md` 的判据矩阵和 `report/limits.md` 的边界。
