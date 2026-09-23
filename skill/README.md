# Skill Pack

Reusable engineering notes from this project. Each item lists scope, usage, verified effect, and failure conditions.

**每一项都是四段式**：适用场景（含**不适用**清单）/ 照抄可用的使用方法 / 已验证效果（带数字或明确标注"未验证"）/ 失效条件。
按比赛指南 3.3.5.2 的四类归纳见下表"类别"列。评价标准是**可复用性**：另一支队伍拿到本目录，
能不能不读本工程源码就用在自己的题目上 —— 所以每一项都写了"从哪次失败里总结出来的"。

## Index（15 项，与目录内容逐项对齐）

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
| S13 | 绕开 IDE 手工链接裸机 ARM 应用：改了 ENTRY 就是把标准启动整条链删掉了（四症状一因 + 两道等值哨兵） | `baremetal_standard_startup.md` | 踩坑清单 + 校验脚本 |
| S14 | 性能指标采集：`gap_sum` 的分母是**段数 N−1**、累计量取差值 / 峰值取 max、采集与算式分离并自带反面对照（`src/host/metrics.mjs` 即其实现） | `metrics_gap_sum.md` | 校验脚本 + 案例模板 |
| S15 | 产物成套与门禁新鲜度：构建没跑完就念门禁，念到的是**上一版**的全绿；bit/xsa/elf/报告按 md5 一起冻结，MANIFEST 必须写"验到哪一条、哪几条没验" | `artifact_freeze_and_freshness.md` | 校验脚本 + 踩坑清单 |
| S16 | CDC 门禁要比**配对集合**而不是行数：写死的"4 行以内算过"吞掉了我两次真实的退化；`report_cdc -details` 才点得出是哪对寄存器（`build/gates.sh` 第 6 项 + `build/CDC_BASELINE.txt` + `build/tcl/cdc_who.tcl`） | `cdc_pair_baseline_gate.md` | 校验脚本 + 踩坑清单 |

## 配套的可执行脚本（判据不是文档，是跑得出数的东西）

| 脚本 | 干什么 | 换题目时要改什么 |
|------|--------|------------------|
| `src/host/metrics.mjs` | S14 的实现：基线(gapclr) → 推流 N 秒 → 读回 → 出表并把**原始读数**一起存档；`--selftest` 8 条含"错用分母必须给出不同 fps"的反面对照 | `FRAME_BYTES`（分辨率）与 lane 名 |
| `sim/top_check_ku5p.sh` | 20 秒把**没有任何台架例化**的顶层 elaborate 一遍（端口对不对只有综合会查）；三个不显然的开关（unisim 库 / `glbl` 当第二顶层 / `-timescale`）都注在文件头 | 顶层名、器件库、文件清单 |
| `build/gates.sh` | 一条命令把七项门禁（WNS/WHS/失败端点/BRAM/Slice/功耗/methodology/布线/CDC）读成 PASS-FAIL，可指向任一**成套冻结件**复核；解析不到值就 FATAL 退出，**绝不拿空值当 0 判绿** | 报告路径与阈值（阈值口径见 `report/BUILD.md` §7） |
| `src/host/arb_handover_test.mjs` | 无人值守的仲裁交接判据：自己开关推流、按 100 ms 采 lane30，输出 V1–V6 + V0 七条 PASS/FAIL 与**停流后交回用时的毫秒数**；`--selftest` 10 条含"正常交接不该算抖动""空样本不许判绿"两条反例 | lane 号与 GPIO 基址；两个门限 `--settle-ms` / `--handback-max-ms` |
| `build/tcl/cdc_who.tcl` | 读**已布线** dcp 出 `report_cdc -details`，把"哪对寄存器跨了域、同步器前面有没有组合逻辑"点到名字 | dcp 路径是 glob 的，换器件不用改；只能在两次构建之间跑 |
| `sim/run_one.sh` | 只跑一个台架（几十秒），改完 RTL 的第一道关 | `SRC` 文件清单 |
| `src/host/ddr_stale.mjs` | S9 的实现：包内字节偏移→丢字率、连续丢字带分布、16bit 粒度错帧计数 | `WORDS / PAYLOAD` 两个常数 |
| `src/host/ku5p_stats.mjs` | 收 KU5P 遥测 UDP 包并打印硬件计数器（含 `--selftest` 用合成包自校解析器） | 目标 IP/端口 |
| `build/_scan_align.mjs` | 扫整份 ELF 的反汇编，把 `[rN,#imm]` 里非对齐的字访问揪出来（MMU 关着时这类指令必发对齐异常）；当前 482 条、非对齐 0 条 | 镜像路径 |
| `board/uart_cap_once.ps1` | 只用 Windows 自带 SerialPort 的串口收发夹具（多命令 + 命令间隔 ⇒ 帧率这类判据能自己计时）；自带 `SENT n/n` 自证与三条 PowerShell 陷阱注释 | 串口号、命令表 |
| `board/pswhy.tcl` / `board/rdddr.tcl` | "板子没反应"时一次采出 pc/cpsr/lr/sp + `DataAbortAddr` 三个全局；以及 GPIO 回读 + `0x10000000` 头几字（判断 PS 有没有真写进 DDR） | 全局地址来自 `nm`，重建 elf 后要改 |

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
