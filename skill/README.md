# Skill Pack

Reusable engineering notes from this project. Each item lists scope, usage, verified effect, and failure conditions.

**每一项都是四段式**：适用场景（含**不适用**清单）/ 照抄可用的使用方法 / 已验证效果（带数字或明确标注"未验证"）/ 失效条件。
按比赛指南 3.3.5.2 的四类归纳见下表"类别"列。评价标准是**可复用性**：另一支队伍拿到本目录，
能不能不读本工程源码就用在自己的题目上 —— 所以每一项都写了"从哪次失败里总结出来的"。

## Index（12 项，与目录内容逐项对齐）

| ID | Topic | File | 类别 |
|----|-------|------|------|
| S1 | UDP offset reassembly protocol | `udp_offset_reasm.md` | 案例模板 |
| S2 | Rotation + window filter in target domain | `rotate_window_target_domain.md` | 踩坑清单 |
| S3 | AXI stream pipeline verification | `axi_stream_verify.md` | 校验脚本 / 案例模板 |
| S4 | Zynq DDR bandwidth and HP ports | `zynq_ddr_bandwidth.md` | 踩坑清单 |
| S5 | LLM-assisted FPGA debug prompts | `llm_fpga_debug_workflow.md` | **提示词工作流** |
| S6 | PL RGMII UDP offload minimal loop | `pl_rgmii_udp_offload.md` | 案例模板 |
| S7 | RTL8211 link and UART bring-up | `board_eth_uart.md` | 踩坑清单 |
| S8 | Zynq7020 Vivado/xsim RTL 调试与单变量修复工作流（含 `scripts/run_sim.tcl`） | `zynq-video-rtl-debug/SKILL.md` | **提示词工作流 + 校验脚本** |
| S9 | 用「逐字反解帧号 + 包内相位」定位丢字机理（`src/host/ddr_stale.mjs` 即其实现） | `frameid_loss_signature.md` | 校验脚本 |
| S10 | 同相 N 倍时钟把单口 BRAM 分时成 N 次读（4 ns 预算、成对采集、延迟要量出来钉住） | `derived_clock_port_mux.md` | 案例模板 |
| S11 | 跨域**脉冲**只能走翻转式同步器；电平型 3 级不能修它（附相位扫描判据与实测三行表） | `pulse_toggle_cdc.md` | 踩坑清单 + 校验脚本 |
| S12 | 共享介质的发送仲裁："全部空闲"≠"任一空闲"、一拍宽请求要记账、跨 always 清标志晚一拍 | `arbiter_pending_pulse.md` | 踩坑清单 + 校验脚本 |

## 配套的可执行脚本（判据不是文档，是跑得出数的东西）

| 脚本 | 干什么 | 换题目时要改什么 |
|------|--------|------------------|
| `build/gates.sh` | 一条命令把七项门禁（WNS/WHS/失败端点/BRAM/Slice/功耗/methodology/布线/CDC）读成 PASS-FAIL，可指向任一**成套冻结件**复核；解析不到值就 FATAL 退出，**绝不拿空值当 0 判绿** | 报告路径与阈值（阈值口径见 `report/BUILD.md` §7） |
| `sim/run_one.sh` | 只跑一个台架（几十秒），改完 RTL 的第一道关 | `SRC` 文件清单 |
| `src/host/ddr_stale.mjs` | S9 的实现：包内字节偏移→丢字率、连续丢字带分布、16bit 粒度错帧计数 | `WORDS / PAYLOAD` 两个常数 |
| `src/host/ku5p_stats.mjs` | 收 KU5P 遥测 UDP 包并打印硬件计数器（含 `--selftest` 用合成包自校解析器） | 目标 IP/端口 |

## 交付形态说明

- `zynq-video-rtl-debug/` 是**可直接放进智能体工作区的技能包**（`SKILL.md` + `scripts/`）：
  适用场景 = 本仓库这类「Vivado 批处理 + xsim + JTAG 上板」的 FPGA 工程；
  失效条件 = 无 JTAG / 无第二网口 / 需要肉眼判定的画质问题（详见
  `report/AI_COLLABORATION.md` §6）。
- S11/S12 的"已验证效果"列里有**负数**：两条都是从我自己写错的修法里量出来的
  （电平同步器并不修脉冲 CDC；`&&` 单独用会丢 ARP 请求）。**把失败形态写进技能包，
  比只写成功姿势更值钱** —— 下一个用的人能直接跳过那一坑。
- `SKILL.md` 是本目录的入口索引（含每条台架怎么跑、回归怎么收集），与上面的 S 编号一一对应。

Related docs: repo `README.md`, `report/ARCHITECTURE.md`, `report/BUILD.md`, `sim/run_sim.tcl`,
`build/tcl/build_system_axigpio.tcl`, `report/AI_COLLABORATION.md`（大模型协作轨迹与自我纠错记录）.

- `zynq-video-rtl-debug/` 是**可直接放进智能体工作区的技能包**（`SKILL.md` + `scripts/`）：
  适用场景 = 本仓库这类「Vivado 批处理 + xsim + JTAG 上板」的 FPGA 工程；
  失效条件 = 无 JTAG / 无第二网口 / 需要肉眼判定的画质问题（详见
  `report/AI_COLLABORATION.md` §6）。
- S9 的判据不是文档而是脚本：`src/host/ddr_stale.mjs` 直接输出
  「包内字节偏移 → 丢字率」「连续丢字带长度分布」「16bit 粒度错帧计数」三组数，
  换题目时只需改 `WORDS / PAYLOAD` 两个常数。

Related docs: repo `README.md`, `report/ARCHITECTURE.md`, `sim/run_sim.tcl`, `build/tcl/build_system_axigpio.tcl`.
