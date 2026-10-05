# 实测输出留档

这一格放**板子与工具吐出来的原始读数**，不放判读结论（结论在 `report/` 与 `board/`），
也不放每次跑都会往上累加的运行台账。2026-10-05 目录精简后这里是 5 支：

| 件 | 是什么 | 怎么重跑 |
|---|---|---|
| `board_measure_15fps.txt` | `node src/host/measure_v63.mjs --fps 15 --count 200` 的完整输出（推 frameid 200 帧 → 停止 → JTAG 回读两个 bank → 逐 16bit 反解帧号 → 包内相位判据） | 上面那条命令，要板子 |
| `arb_handover_r28_red.json` | 仲裁交接那把尺子（`src/host/arb_handover_test.mjs`）**判红那一次**的原始样本，一条一例 | `node src/host/arb_handover_test.mjs`；注意它默认往自己的运行台账追加，那份台账不入库 |
| `interp_gain_attribution.txt` | 插值增益的逐档归属读数 | 读法与判据在 `report/` 的插值那一节 |
| `board_measure_r08.md` | r08 那一次板级测量的判读（三态、拔线可逆性、`gapclr` 对账） | 原始件在同目录的 `.txt`，判读口径与 `report/` 同源 |
| `README.md` | 本说明 | —— |

判读要点（与 `report/log/v6_board_measurement.md` §4.1 同一判据）：

| 指标 | 本次(15fps) | 30fps | 60fps(18.4MB/s) | 修复前 |
|---|---|---|---|---|
| 最新帧命中率 | 100.0% / 100.0% | 100.0% | 100.0% | 42~52% |
| 包内各字节带丢字率 | 全 0.0% | 全 0.0% | 全 0.0% | 6.7% → 54~64% |
| u32 内两 16bit 错帧 | 0/76800 | 0/76800 | 0/76800 | 18.6% |
| 已知残留 | 帧最后 4 字节偶发为 0（2/153600 lane） | 同 | 同 | — |

原来这里还有一份 460 KB 的 DDR 两个 bank 的原始抓取（`gunzip` 之后喂 `src/host/ddr_stale.mjs` 复算），
它属"一次测量的现场凭据"而不是输入数据或参考结果，按同一条口径已经清掉；
要重跑这条链是 `node src/host/ddr_verify.mjs` 落原始件、`node src/host/ddr_stale.mjs <件>` 复算，
上表那四行判读就是那一次跑出来的结论。

复算本目录的现量：

```bash
find data/measured -maxdepth 1 -type f | wc -l
ls data/measured
```
