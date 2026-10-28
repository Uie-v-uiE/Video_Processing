# Measured versus reference

This page maps delivered readings back to the implementation reports and the board logs. Each number appears once in `data/metrics.csv` and once in the design report; here we only give the reading-to-evidence mapping and never invent a second set of numbers.

| Metric | Delivered reading | Reference / evidence | Result |
|---|---|---|---|
| Global setup WNS | 1.341 ns | `hw/reports/build_timing_summary.rpt` | matches |
| Global hold WHS | 0.025 ns | `hw/reports/build_timing_summary.rpt` | matches |
| TNS / THS | 0 / 0 | `hw/reports/build_timing_summary.rpt` | matches |
| LUT / FF | 14,967 (28.13%) / 9,095 (8.55%) | `hw/reports/build_utilization.rpt` | matches |
| BRAM / DSP | 98 (70.00%) / 19 (8.64%) | `hw/reports/build_utilization.rpt` | matches |
| Dynamic power | 2.228 W | `hw/reports/power.rpt` | matches (tool estimate) |
| 8-second stream | 241 frames / 8.05 s / 29.95 fps | `hw/measured/telemetry_8s.txt` | matches the sender's 241 frames |
| Three-stage self-test | 22.0 / 0 / 18.9 fps; 14.3 aborts/s in the fault stage | `hw/measured/link_selftest.txt` | PASS |
| Frame gaps | streaming `gap_last=28 ms`, `gap_max=49 ms`; `gap_max=22,061 ms` after restart | `hw/measured/link_gap.txt` | pass |
| QSPI cold boot | `DONE=1`, `EOS=1`, no CRC/IDCODE error; ping 5/5 | `hw/measured/cold_boot.txt` | pass |
| Serial battery | 105 commands / 97.8 s / PASS | `hw/measured/uart_battery.txt`, `uart_battery_capture.txt` | pass |
| Processed-pane integrity | `pane_bad=0`, `pane_valid=1` | `hw/measured/pane_integrity.txt` | pass |

## Reconciliation rules

- Timing, resources and power: post-route reports under `hw/reports/` are authoritative; the power estimate is read for order of magnitude only.
- Board readings: raw logs under `hw/measured/` are authoritative, and the test conditions are recorded in the measurement-condition column of `data/metrics.csv`.
- Reference images: `data/golden/` is for human comparison, not an automatic golden reference; per-pixel correctness is covered by the benches and the on-board counters.
- The older `metric_recheck.mjs` depended on an earlier README table format and is no longer a final gate; this table is reconciled by hand against the delivered readings and reports.
