# Skill Pack

Reusable engineering notes from this project. Each item lists scope, usage, verified effect, and failure conditions.

## Index

| ID | Topic | File |
|----|-------|------|
| S1 | UDP offset reassembly protocol | `udp_offset_reasm.md` |
| S2 | Rotation + window filter in target domain | `rotate_window_target_domain.md` |
| S3 | AXI stream pipeline verification | `axi_stream_verify.md` |
| S4 | Zynq DDR bandwidth and HP ports | `zynq_ddr_bandwidth.md` |
| S5 | LLM-assisted FPGA debug prompts | `llm_fpga_debug_workflow.md` |
| S6 | PL RGMII UDP offload minimal loop | `pl_rgmii_udp_offload.md` |
| S7 | RTL8211 link and UART bring-up | `board_eth_uart.md` |
| S8 | Zynq7020 Vivado/xsim RTL 调试与单变量修复工作流（含 `scripts/run_sim.tcl`） | `zynq-video-rtl-debug/SKILL.md` |
| S9 | 用「逐字反解帧号 + 包内相位」定位丢字机理（`src/host/ddr_stale.mjs` 即其实现） | `frameid_loss_signature.md` |

## 交付形态说明

- `zynq-video-rtl-debug/` 是**可直接放进智能体工作区的技能包**（`SKILL.md` + `scripts/`）：
  适用场景 = 本仓库这类「Vivado 批处理 + xsim + JTAG 上板」的 FPGA 工程；
  失效条件 = 无 JTAG / 无第二网口 / 需要肉眼判定的画质问题（详见
  `report/AI_COLLABORATION.md` §6）。
- S9 的判据不是文档而是脚本：`src/host/ddr_stale.mjs` 直接输出
  「包内字节偏移 → 丢字率」「连续丢字带长度分布」「16bit 粒度错帧计数」三组数，
  换题目时只需改 `WORDS / PAYLOAD` 两个常数。

Related docs: repo `README.md`, `report/ARCHITECTURE.md`, `sim/run_sim.tcl`, `build/tcl/build_system_axigpio.tcl`.
