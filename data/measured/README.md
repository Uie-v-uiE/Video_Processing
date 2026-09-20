# 实测输出留档

- `board_measure_15fps.txt`：`node src/host/measure_v63.mjs --fps 15 --count 200` 的完整输出
  （推 frameid 200 帧 → 停止 → JTAG 回读两个 bank → 逐 16bit 反解帧号 → 包内相位判据）。
- `ddr_dump_20260921_15fps.out.gz`：同一次测量的两个 bank 原始回读（76800×2 个 u32，文本格式
  `<addr>: <data>`），可用 `src/host/ddr_stale.mjs <解包后的文件>` 重新分析。

判读要点（与 `report/V6_BOARD_MEASUREMENT.md` §4.1 同一判据）：

| 指标 | 本次(15fps) | 30fps | 60fps(18.4MB/s) | 修复前 |
|---|---|---|---|---|
| 最新帧命中率 | 100.0% / 100.0% | 100.0% | 100.0% | 42~52% |
| 包内各字节带丢字率 | 全 0.0% | 全 0.0% | 全 0.0% | 6.7% → 54~64% |
| u32 内两 16bit 错帧 | 0/76800 | 0/76800 | 0/76800 | 18.6% |
| 已知残留 | 帧最后 4 字节偶发为 0（2/153600 lane） | 同 | 同 | — |

复算方法：

```bat
gunzip data/measured/ddr_dump_20260921_15fps.out.gz
node src/host/ddr_stale.mjs data/measured/ddr_dump_20260921_15fps.out
```
