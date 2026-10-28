# scripts/

Reproducible build scripts plus the implementation reports they produce.

| Entry point | Purpose |
|---|---|
| `build.tcl` | Vivado entry, forwards to `tcl/build_system_axigpio.tcl`; accepts `-tclargs bd_only` |
| `tcl/build_system_axigpio.tcl` | project, block design, synthesis, implementation, bitstream, XSA and timing/resource/CDC/power reports |
| `tcl/stage_board_projects.tcl` | stages the project into `hw/vivado/` and verifies it |
| `vitis/rebuild_vitis.py` | rebuilds the Vitis platform and FSBL from the XSA |
| `ps/build_ps_app.py` | compiles the PS bare-metal application without the Vitis IDE |
| `sim/` | xsim entry points |
| `reports/` | timing, resource, CDC, power, regression and full-video verdicts |

Document generators (technical document DOCX/PDF, poster PPTX export) are local typesetting tools; they are not in this repository and are not part of the build chain.
