# Reference images

Software-rendered images for human comparison; they are not automatic bench inputs.

| File | Content |
|---|---|
| `src.png` | source image |
| `rot_000.png`, `rot_030.png`, `rot_045.png`, `rot_090.png`, `rot_180.png`, `rot_270.png` | software render of the same source at each angle |
| `proc_00111.png`, `proc_10000.png`, `proc_all.png` | software renders of several effect combinations |
| `dual_preview.png` | side-by-side preview of source and processed panes |

These images came from an early host-side preview tool whose render script is no longer in the tree, so they cannot be regenerated with one command. Their job is to give a human on site a reference for which way a rotated picture should face and what an effect chain should feel like. Per-pixel correctness is covered by the benches in `sim/` and by the on-board processed-pane count, not by these PNGs.

The digits in the `proc_*` names follow the old five-bit effect encoding, not the current nine-bit `pipe` control word; do not read them as the current `stage_sel`.
