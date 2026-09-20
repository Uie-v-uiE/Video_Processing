---
name: zynq-video-rtl-debug
description: Debug and fix RTL bugs in the Zynq7020 UDP→DDR→HDMI video pipeline in this workspace (rtl_base/rtl_fix, ghosting 拖影, black stripes 黑横纹, freeze 卡死, SRC0/SRC1 switching). Use when editing any .v under rtl_*, running xsim testbenches in sim/, rebuilding the Vivado bitstream, or interpreting board/Vitis results in docs/. Enforces the single-variable change protocol and the verified no-ghosting v5 strategy.
---

# Zynq7020 Video Pipeline RTL Debug

## Overview

Work loop for the display-path bugs (拖影 / 黑横纹 / 卡死 / SRC 切不动): diagnose with the
4-case matrix → change ONE architecture variable → xsim at production geometry → rebuild bit
→ board → record in `docs/`. Read `README.md` §3/§8 and `docs/LEARNINGS.md` before touching RTL.

## Environment (verified on this machine)

| Need | Fact |
|------|------|
| Vivado/Vitis | `D:/Software/Vivado/2025.2.1/` — exists, 2025.2.1, device `xc7z020clg484-2` |
| BD project | `D:/Xilinx/Prj/ADD/Video_Pipeline-main/vivado_system/zynq_video_sys.xpr` exists — **no BD rebuild needed** |
| `xvlog/xelab/xsim` | only on PATH **inside** `vivado.bat -mode batch -source`; calling them from Git Bash fails |
| Python / iverilog / verilator / slang | **not on PATH** — host `video_sender.py` must run in a terminal that has Python; no non-Vivado simulator is available |
| Log noise | always pass `-nojournal -log <path>`, else `vivado.jou`/`vivado.log` land in cwd |

Two copies of this handoff exist: `D:/Xilinx/Prj/project_handoff` (this workspace) and
`D:/Xilinx/Prj/ADD/project_handoff`. `sim/run_sim_v5.tcl` hardcodes the **ADD** copy. Always
`pwd` before editing, and prefer the workspace-relative runner below.

## Run xsim

```bash
cd /d/Xilinx/Prj/project_handoff && mkdir -p sim_work
SIM_TB=tb_v50_rowmath "D:/Software/Vivado/2025.2.1/Vivado/bin/vivado.bat" \
  -mode batch -nojournal -log sim_work/xsim.log \
  -source .qoder/skills/zynq-video-rtl-debug/scripts/run_sim.tcl
```

The script derives the workspace root from its own location, compiles `rtl_base/*` +
`rtl_fix/*.v` + `sim/tb_*.v`, and prints `RESULT <tb> PASS|FAIL|NO_ASSERT|ELAB_FAIL` per TB.
`SIM_ONLY=1` = compile check only. Work dir: `sim_work/` (safe to delete).

RTL merge rule the script encodes (same as `BUILD.md` §1): `rtl_fix/` overrides base
`system_top`, `pl_video_top`, `eth_udp_video_top`, `frame_reasm`, `axi_frame_saver`;
`rtl_fix_v4/` is analysis-only and must never be compiled together with `rtl_fix`.

TBs that matter for the current bug set: `tb_v50_rowmath` / `tb_v50_rows_prod` (行号公式 + commit),
`tb_v57_rdw_copy` (读写同址), `tb_v5_gated` / `tb_v5_lock` (allow 窗口与 commit 锁), `tb_v58_full_done` (写满才 done).

**Always use production geometry** (512×300 source, 1024×600 display, H=1344 V=625 @50 MHz).
Small-parameter sims have repeatedly passed while the board failed (README §8 "不要再踩" #5).

## Rebuild bitstream

Reuse the existing project rather than recreating it: `open_project <...>/zynq_video_sys.xpr`,
remove base files whose module names `rtl_fix/` redefines, add `rtl_fix/*.v`, `set_property top
system_top`. `build_tcl/*.tcl` hardcodes `D:/Xilinx/Prj/ADD/Video_Pipeline-main` paths — edit the
`root`/`fix` variables at the top instead of rewriting the flow.

Delete the stale incremental checkpoint before re-synth (`build_tcl/rebuild_cdc_fix.tcl` does
this) — otherwise an edit can silently produce an identical netlist and waste a board cycle.
Record from `timing_summary.rpt`: WNS/TNS, plus BRAM/FIFO utilization (7z020 ≈ 4.9 Mb;
single frame 2.46 Mb; **dual-frame BRAM has already failed**).

## Board loop (all four steps required)

1. `vivado.bat -mode batch -source build_tcl/program_system.tcl` (bit path inside points at the ADD project's `build/system.bit`)
2. Vitis: **new XSA** from this build → rebuild app → **Run** — bit download resets the PS, so the ELF must be re-run every time or GPIO/UART stay dead
3. Host: `python video_sender.py --ip 192.168.1.10 --src 192.168.1.100 --fps 15 --anim` (effects `00000`, SRC1)
4. Observe in this order: 拖影 → 黑纹 → 卡死 → 能否切回 SRC0

## Diagnosis matrix (measure before changing code)

| Case | Tells you |
|------|-----------|
| SRC0, no stream | HDMI/timing health — SRC0 color bar is known clean |
| SRC0, streaming | whether ETH/DDR write path disturbs display |
| SRC1 @15fps | normal display of copied frame |
| **SRC1, stop streaming (frozen frame)** | static bad data in BRAM/DDR vs. dynamic read/write conflict |

The frozen-frame test is what separated 黑影 root causes in v5.8 (`docs/LEARNINGS.md`): dirt that
survives a stopped stream is un-written BRAM words (value 0 = black), not a read/write collision.
Black stripes → check whether writes intrude into active lines. Ghosting → check whether a full
frame copies within one display frame's blanking (~4.5 ms total vs ~0.67 ms V-blank only).

## Change protocol

- One architecture variable per build. Never bundle allow-window + writer-engine + saver changes.
- Keep the v5 no-ghosting strategy intact: write display BRAM **only during blanking**, latch the
  DDR base at commit, DDR ping-pong, `src_use = src_sel` (never `| eth_ready`).
- Banned without new proof: V-blank-only allow, mute as primary fix, burst saver (4 KB/idle →
  red screen/freeze), dual display BRAM.
- Append hypothesis / change / sim result / board result / rolled-back? to `docs/` on every
  iteration; name them `ANALYSIS_vN.md` + `RESULT_vN.md` as the existing files do.

## Resources

- `scripts/run_sim.tcl` — workspace-relative xsim runner (see flags above).
- `references/*.md` — domain notes carried over from the original project:
  `udp_offset_reasm.md` (offset reassembly protocol), `zynq_ddr_bandwidth.md` (HP0 bandwidth /
  cache flush), `pl_rgmii_udp_offload.md` (RGMII/preamble/port pitfalls),
  `axi_stream_verify.md` (TB method, 64-bit beat unpacking), `board_eth_uart.md` (PHY/serial setup),
  `rotate_window_target_domain.md` (why effects must run in screen domain),
  `llm_fpga_debug_workflow.md` (falsifiable-hypothesis prompting).
  These reference `ISSUES#n` numbers and paths from the pre-handoff repo
  (`D:/Xilinx/Prj/ADD/Video_Pipeline-main`), which is not part of this workspace.
