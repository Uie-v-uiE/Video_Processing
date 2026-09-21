# sim/probes — 综合行为对照实验（不是仿真 TB，不参与 run_sim.tcl）

这些文件回答的是「**Vivado 到底把这段写法综合成什么**」，只能靠 out-of-context 综合来判定，
写 TB 是测不出来的。它们是本仓库若干结论的证据来源，命令与数字记在
`report/OVERNIGHT_LOG.md` 的 R02 / R04。

| 文件 | 回答的问题 | 结论 |
|------|-----------|------|
| `ramtest.v` + `probe.tcl` | 512×100bit 的 FIFO 存储怎么写才会被推断成**分布式 RAM**而不是 5.1 万个触发器？ | 内存写必须独占一个不带异步复位的 always 块（task 封装 + 异步复位块 = FF 32904/推断失败；拆开 = FF 85/LUTRAM 864） |
| `fbtest.v` + `probe2.tcl` `probe3.tcl` | 512×300 RGB565 帧缓存为什么吃掉 128 个 RAMB36，怎么写能省？ | 与数组深度/位宽都无关，是地址空间被向上填到 2^16；按 2 的幂拆两块 → **80 个** |

跑法（会在本目录生成 Vivado 工程文件，**不要提交** `*.xpr/.runs/.Xil/*.log`）：

```bat
"D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat" -mode batch -nojournal ^
    -log sim\probes\probe.log -source sim\probes\probe.tcl
```
