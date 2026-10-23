# 仿真结果

`sim/results/` 保存交付版本直接引用的判定副本。原始日志中的版本号已去掉，判定行保持原样。

| 文件 | 内容 |
|---|---|
| `regression.txt` | 19 支标准回归汇总，`fail=0`；含各台架自己打印的 `RESULT ... PASS` 行 |
| `tb_video_pipeline_top_report.txt` | 完整视频台架 C17/C25/C26 专项判定，`nfail=0` |
| `udp_checksum.txt` | UDP/IP 校验和专项复验 |
| `c31_edge_rim.log` | C31 帧尾两行抽头复验，swap 两态全帧 0 格不符 |

判定读法：`PASS` 只在日志末尾有判定行时成立；没有判定行的日志只是过程记录，不算通过。
