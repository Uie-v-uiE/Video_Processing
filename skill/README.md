# Skill Pack · Video_Processing

可复用技能目录（竞赛 3.3.5.2 技能包）。每项含：适用场景 / 使用方法 / 已验证效果 / 失效条件。

评价标准是**可复用性**：陌生队伍拿到后能否用在自己的 FPGA 题目上。

## 索引

| ID | 主题 | 文件 |
|----|------|------|
| S1 | UDP 乱序重组协议设计与验证 | `udp_offset_reasm.md` |
| S2 | 旋转与窗口滤波目标域重构 | `rotate_window_target_domain.md` |
| S3 | AXI4-Stream/AXI 流水线验证 | `axi_stream_verify.md` |
| S4 | Zynq DDR 带宽与 HP 口 | `zynq_ddr_bandwidth.md` |
| S5 | 大模型辅助 FPGA 调试提示词 | `llm_fpga_debug_workflow.md` |
| S6 | PL RGMII UDP 硬件卸载最小闭环 | `pl_rgmii_udp_offload.md` |
| S7 | RTL8211 / 链路与串口 | `board_eth_uart.md` |

## 通用性说明

- **S1/S6/S7**：换视频题、换板仍可用的网络/板级方法。  
- **S2**：任意「几何变换 + 3×3 滤波」题目可复用。  
- **S5**：与具体题目无关的协作流程。

复现入口：仓库根 `README.md`、`report/ARCHITECTURE.md`、`sim/run_sim.tcl`、`build/tcl/build_system_axigpio.tcl`。

