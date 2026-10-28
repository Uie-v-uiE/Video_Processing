# Data

`data/` holds three kinds of material: test inputs, software reference images and the metrics table.

## Test inputs

`inputs/` holds fixed vectors: a normal frame, all-zero, random, a truncated 299-row frame, an oversized 1.5-frame burst, a zero-byte packet and a one-pixel edge packet. They are produced by `generated/gen_inputs.mjs`; rerunning the command reproduces the same bytes:

```bash
node data/generated/gen_inputs.mjs --write
```

## Reference images

`golden/` holds software-rendered images: the source, several rotation angles, effect combinations and a side-by-side preview. They support human comparison and are not the only source of an automatic verdict; per-pixel comparison runs on the benches. The file list and purpose are in `golden/README.md`.

## Metrics table

`metrics.csv` is the delivered metrics table: one row per metric with value, unit, measurement condition and evidence path. Each number appears here and in the design report, nowhere else; a second table would drift on its own.

When an input cannot be read, write `NOT_MEASURED`, never "pass". Quantities that were not measured, such as end-to-end or glass-to-glass latency, stay explicitly unmeasured in the table.

## Evidence

Raw board logs are in `hw/measured/`, implementation reports in `hw/reports/`, and bench verdicts in `hw/reports/regression.txt` and `hw/reports/tb_video_pipeline_top_report.txt`. The metrics table only points at them and does not copy log bodies.
