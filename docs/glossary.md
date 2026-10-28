# Glossary

The same object appears in Chinese in the design notes and in English in these documents. This table fixes one English term per object so translations do not drift.

| Chinese | English used here | Notes |
|---|---|---|
| 台架 | testbench, bench | not "test rig" |
| 判据 | check | a condition that can turn red, not a "criterion" in the abstract |
| 判定行 | verdict line | the last line of a bench log |
| 帧提交三条件 | three-gate commit | byte gate, row-coverage bitmap, bad-packet gate |
| 字节门 | byte gate | total frame bytes present |
| 行覆盖位图 | row-coverage bitmap | one bit per source row |
| 坏包 | bad packet | FCS or length failure, counted separately from aborts |
| 作废帧 | aborted frame | a frame refused by any gate |
| 缺行 | missing rows | recorded per abort; the cause, not a rate |
| 同帧对照 | same-frame comparison | both panes from one frame and one coordinate set |
| 竖缝 | seam | the vertical split between the two panes |
| 处理窗 / 处理侧 | processed pane | the right-hand, effect-processed side |
| 原图 | source, source pane | the unprocessed side |
| 片源 | source | ETH stream, SD playback or test card |
| 图卡 | test card | drawn by the PL, never enters memory |
| 消隐 | blanking | vertical blanking window for the frame switch |
| 乒乓缓存 | ping-pong buffer | two DDR banks, one displayed while one fills |
| 帧间隔 | frame gap | `gap_last/min/max/sum`, in milliseconds |
| 停流 | stall | `stall`, time since the last valid frame |
| 遥测 | telemetry | 1 Hz UDP beacon, 32 bytes |
| 信标 | beacon | one telemetry packet |
| 仪表 | instrument | the counters plus their three outlets |
| 可证伪 | falsifiable | the instrument can be made to fail on demand |
| 三级同步器 | three-stage synchroniser | for single-bit levels and resets |
| 快照器 | snapshot | whole-beat hold plus synchronised toggle edge |
| 准静态总线 | quasi-static bus | changes at most once per frame |
| 异步 FIFO | asynchronous FIFO | gray-code pointers across clock domains |
| 原语 | primitive | MMCME2_BASE, BUFG, IDDR, ODDR, OSERDESE2 |
| 位流 | bitstream | `system.bit` |
| 约束 | constraints | XDC files |
| 布线后 | post-route | timing read after implementation |
| 时序收敛 | timing closure | zero failing endpoints |
| 复位恢复 | reset recovery | the check behind the worst WNS |
| 建立余量 / 保持余量 | setup margin / hold margin | WNS / WHS |
| 扇出 | fan-out | number of loads on a net |
| 复制 | replication | duplicating a driver to cut fan-out |
| 冷启动 | cold boot | power cycle, no host |
| 固化 | programming | writing the image to QSPI |
| 读口 | read port | frame-buffer read side |
| 行缓存 | line buffer | per-stage row storage |
| 尾字 | tail word | the last packed word of a frame |
| 满 FIFO + flush | full FIFO plus flush | the corner where the tail word used to be lost |
