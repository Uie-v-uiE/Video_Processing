# Simulation results

`sim/results/` keeps the verdict copies the deliverable cites directly. Build identifiers have been removed from the original logs; the verdict lines are unchanged.

| File | Content |
|---|---|
| `regression.txt` | summary of the 19-bench standard regression, `fail=0`, including each bench's own `RESULT ... PASS` line |
| `tb_video_pipeline_top_report.txt` | full-video bench C17/C25/C26 verdicts, `nfail=0` |
| `udp_checksum.txt` | UDP/IP checksum re-verification |
| `c31_edge_rim.log` | C31 re-verification of the last two rows' taps; zero mismatching cells across the whole frame in both swap states |

How to read a verdict: `PASS` holds only when a verdict line sits at the end of the log. A log without one is a process record, not a pass.
