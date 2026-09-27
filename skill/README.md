# skill/ —— 这一套里能搬走的东西

这里放的是**方法**，不是 FPGA 教材，也不是本项目的说明书。判断一条要不要留下的标准只有一条：
另一支队伍、另一块板、另一个题目，明天就能照它做一遍，并且做完能省掉一次真实的错误。

目录里**没有**的东西，是故意的：
- 没有可复制的第二份脚本。`sim/` `build/` 下的脚本只有仓库根那一份是真的，本目录一律用相对路径指过去。
- 没有协议、原语、时序模型的科普。需要查那些请去 `report/ARCHITECTURE.md`、`report/MODULES.md`。
- 没有同一个结论的第三次复述。下面的每一行只是**路标**：适用场景 / 使用方法 / 失效条件 / 来源
  写在该条自己的文件里（那些文件还多一段"已验证效果"，因为**没有数字的经验不值得抄**）；
  一行放不下四条，就只给链接。

## 我现在这个症状该看哪一条（30 秒定位）

| 症状 / 处境 | 先看 |
|-------------|------|
| 我说"改好了"，但没有一条命令能证明 | [SKILL.md](SKILL.md) 的硬规则 1，再 [S5](llm_fpga_debug_workflow.md) |
| 新写的判据第一跑就**红**，而硬件看着是对的 | [S20 bench_self_inflicted_reds.md](bench_self_inflicted_reds.md) |
| 新写的判据第一跑就**绿**，而缺陷真的还在 | [S21 criterion_blind_spot.md](criterion_blind_spot.md) |
| 门禁全绿，但我不敢说这是哪一次构建的数 | [S15](artifact_freeze_and_freshness.md) + 下面 C 表的 `gates.sh` |
| CDC / 资源数字变了，不知道是谁 | [S16](cdc_pair_baseline_gate.md) + `build/tcl/cdc_who.tcl` |
| 上板没画面、没反应、ping 不通 | [S8 zynq-video-rtl-debug/SKILL.md](zynq-video-rtl-debug/SKILL.md)（L0–L4 分层），再 [S7](board_eth_uart.md) |
| 回读回来的一组数不自洽（"部分大于整体"） | [S18](atomic_register_window_readback.md) |
| 同一位置必失败，旁边的人往"超时/竞态"上解释 | [S17](failing_read_prints_geometry.md) |
| 台架日志里的中文变乱码、数字对错位 | [S22](bench_verilog_subset.md) |
| 仿真全绿、上板靠运气（跨域脉冲） | [S11](pulse_toggle_cdc.md) |
| 算出来的 fps / 带宽好得不像话 | [S14](metrics_gap_sum.md)，再 [S4](zynq_ddr_bandwidth.md) |
| 文档念的"当前版本"其实是上一版 | 门禁第 18 项 `src/host/doc_currency_check.mjs`，规矩在 [S15](artifact_freeze_and_freshness.md) |

编号 **S1…S22 是对外接口**：`src/`、`sim/`、`report/` 里已经按号引用（例如 `report/OVERNIGHT_LOG.md`
引"技能包 S9 / S20 / S21"，`sim/tb_v102_src_life.v` 引 S10/S11/S12）。**只许新增，不许改号、不许换文件名**，
否则那些引用一夜之间全指向别处。要合并条目，就把号一起带过去。
空号 **S3**（原 `axi_stream_verify.md`）是合并留下的：它的可迁移部分搬进了 S21（第 10–12 条）、
S22（第 13 类）与 S11（非整数比时钟的握手台架），**号不回收**，免得旧引用指向一个新内容。

---

## A 提示词工作流 —— 怎么把一个硬件问题变成大模型能执行、且骗不了人的指令

- **[SKILL.md](SKILL.md)**（本目录给智能体直接加载的那一份）
  什么时候用：开一轮"改 RTL / 定位上板现象 / 出交付材料"之前，整个文件贴进对话或放进工作区。
  怎么用：它给角色、六条硬规则、四步工作循环、四段提示词模板、禁止清单。
  会失效于：工程里没有任何跑得出数的判据（这套纪律靠"能红"才成立，没有判据时它只会拖慢你）；
  需要肉眼收敛的画质问题。来源：拿**上一版** `cdc.rpt` 宣布一条结论、以及连续两晚只生产
  "时间方向"的合理解释——两例都记在 `report/AI_COLLABORATION.md` 的自我纠错一节与
  `report/ISSUES.md` #50。
- **[S5 llm_fpga_debug_workflow.md](llm_fpga_debug_workflow.md)**
  什么时候用：要给模型下指令、或要验收它的结论时抄模板。怎么用：两条额外模板（交叉阅读、验收）
  加三条被验证过有用的习惯，每条后面挂着它抓出过的具体缺陷。
  会失效于：转述的数字没人直读复核（一律降级为假设）。来源：三次推翻模型/自己的结论，记录在
  `report/OVERNIGHT_LOG.md` §7、`report/CHANGELOG_V7.md` V7.7、`data/measured/board_measure_r09.md`。

## B 案例模板 —— 可以直接抄进自己仓库的骨架

- **[S20 bench_self_inflicted_reds.md](bench_self_inflicted_reds.md)** —— 台架/判据骨架。
  新台架第一跑之前的 30 秒自查清单，加十个"假红/假绿"签名（期望值差常数倍、极值在变而计数为 0、
  等待窗口比被测节拍短、半数组合错在同一个位、查不到当不存在、起点没复位、浮空 X 伪装成功能坏、
  解析器半个接受、日志回显当执行输出、X 与空集上的"通过"）。
  来源：一天之内三种假红同时出现在 `sim/tb_v94_zoom_sel.v`（`report/OVERNIGHT_LOG.md` §35）。
- **[S21 criterion_blind_spot.md](criterion_blind_spot.md)** —— 判据骨架的镜像面：结构性红不了。
  三条自查按代价排序（空位检查 / 把输入 force 成缺陷态看会不会红 / 扫描矩阵按现象原话补维）。
  来源：ISSUES #93 的形状尺子在 1.00x 四档全绿——那一档根本没有一列背景。
- **[S16 cdc_pair_baseline_gate.md](cdc_pair_baseline_gate.md)** —— 门禁脚本骨架。
  比"集合"而不是比行数、基线入库、判红项要自带**能红也能绿**的反例、"记录用不判红"的提示必须有人清账。
  来源：ISSUES #65；写死"4 行以内算过"吞掉两次真实退化（`report/CHANGELOG_V7.md` 门禁表）。
- **[S15 artifact_freeze_and_freshness.md](artifact_freeze_and_freshness.md)** —— 证据冻结/新鲜度骨架。
  交付单元是"一套"（bit/xsa/elf/报告按 md5 一起冻结），MANIFEST 必须写"验到哪条、哪几条没验"。
  来源：构建没跑完就念门禁，念到上一版的全绿（同一天还覆盖过一次同名回归日志）。
- **[S14 metrics_gap_sum.md](metrics_gap_sum.md)** —— 指标采集骨架。
  采集与算式分离、原始读数一起存档、分母 N−1、分子分母必须同一总体、给表加一条"自相矛盾检查"。
  来源：`src/host/metrics.mjs --selftest` 里那条反面对照；ISSUES 那一轮"平均值小于最小值"。
- **[S9 frameid_loss_signature.md](frameid_loss_signature.md)** —— 取证模板：自描述图案协议。
  图案必须逐帧变化；先停流再回读；把丢字按包内相位 / 空间连续性 / 粒度三个维度展开。
  来源：恒定图案 `--test wordid` 让三轮实验报"100% 命中"（`report/ISSUES.md` #34"测量工具自己会造假"）。
- **[S17 failing_read_prints_geometry.md](failing_read_prints_geometry.md)** —— 失败分支骨架：
  让失败自己报出"访问的位置 + 位置的来历 + 合法边界 + 当场分类"。
  来源：ISSUES #50，一行 `[SDRD!]` 把"读超时"翻案成 FAT32 高簇字字节序；两次误判都在往时间方向猜。
- **[S18 atomic_register_window_readback.md](atomic_register_window_readback.md)** —— 多字读回的原子快照骨架。
  先怀疑读法再怀疑硬件；武装信号取自读法本身；快照要带"这一组可不可信"位。
  来源：ISSUES #59（`c1 = 5.498 ms` 却 `tot = 5.324 ms`）与 #60（没判的判据报成 PASS）。

## C 校验脚本 —— 仓库里真实存在、可以直接跑的那些（本目录不含副本）

调用方式都从仓库根起算。**这一栏不是介绍，是使用说明**：红了先看"先看哪里"那一列，不要先改阈值。

| 脚本 | 一条命令 | 它检查什么 | 红了先看哪里 |
|------|----------|-----------|--------------|
| `build/gates.sh` | `bash build/gates.sh [某个冻结目录]` | 读现成报告出 PASS/FAIL：WNS/WHS 与两类失败端点、BRAM、Slice LUT/Reg、Dynamic、methodology Critical、布线错误网线、CDC 配对集合+unsafe、端口宽度 8-689、多驱动 8-685x、顶层接线、顶层台架 `tb_v98`、边缘条带、PS 心跳约定、手写件编码、文档时效、排练=讲稿。解析不到值就 FATAL 退出，**不拿空值当 0 判绿** | 它自己印的候选行（读不到时会把最像的三行原样打出来）；CDC 那行红 → `cdc_who.tcl` 点名；"WARN 相差 N 分钟" → 构建没跑完，见 S15 |
| `build/gates_cdc_test.sh` | `bash build/gates_cdc_test.sh` | 门禁 CDC 项**自己**的判据：真冻结件必须红、把 unsafe 改回 1 必须绿、新增配对、基线缺列、基线不存在 | 它红 = 你改了 `gates.sh` 的 CDC 解析而没带上这份测试 |
| `build/check_ports.py` | `python build/check_ports.py` | 顶层端口名对得上、输入没悬空、位宽两头一致（因为 `pl_video_top`/`system_top` 没有任何台架例化，这类错 L1 全量一条都不会红） | 它点名的那条 net 与两侧模块；`gates.sh` 第 14 项的凭据是 `build/ports_check.txt` |
| `sim/run_one.sh` | `bash sim/run_one.sh tb_xxx` | 单台架快跑（只编要编的文件）；编译**之前**把 `top_md5` / `tb_md5` / `rtl_md5` 写进 `prov.txt` | `exit 3` = 有别的 xsim 正在写同一份 `run.log`，先问是谁的那一跑；红了看 `/tmp/kx/<tb>.run/run.log` |
| `build/tb98_report.sh` | `bash build/tb98_report.sh [run.log]` | 把顶层台架的 console 收成门禁要的凭据，头部两枚 md5 | 报"不是同一次跑" = 报告比当前树旧 ⇒ 重跑台架，别改报告 |
| `build/board_verify.sh` | `bash build/board_verify.sh [--stream] [--battery] [--geom]` | 板上那一半的机器复验：健康读回、仲裁交接、几何最后一跳、串口命令电池。**不刷板**（刷板留给人确认） | 它末行的总判定；串口类红先确认 COM 号与"是不是刚回读过 DDR"（S18/S7 的失效条件） |
| `build/refresh_evidence.sh` | `bash build/refresh_evidence.sh <NN> [--skip-bench]` | "只改了台架/文档"时刷新同一号：先对账三件成品 md5 是否仍等于 `MANIFEST.md5` | `REFUSE` = 那是新构建，必须换新号；门禁输出先落 `/tmp` 再 `cp`，否则第 18 项读到自己被截空 |
| `build/freeze_evidence.sh` | `bash build/freeze_evidence.sh <NN>` | 收成套凭据并生成 `MANIFEST.md5`（认 md5 不认文件名） | 缺哪个文件就是哪一步没跑，不要手补 |
| `build/tcl/cdc_who.tcl` | `vivado -mode batch -source build/tcl/cdc_who.tcl` | 读**已布线** dcp 出 `report_cdc -details`：哪对寄存器跨域、同步器前有没有组合逻辑 | 只能在两次构建之间跑（下一次 `create_project -force` 会删掉那个 dcp） |
| `build/tcl/hold_paths.tcl` | `vivado -mode batch -source build/tcl/hold_paths.tcl` | 同一份 dcp 出最差 20 条 hold + 6 条 setup 的**路径级**报告 | 想换实现策略之前先看裕量压在谁身上；扫策略前先归档 dcp 派生件 |
| `build/orphan_rtl.sh` | `bash build/orphan_rtl.sh [--selftest]` | 拿综合日志当可达性 oracle，算出"声明了但没进这一版位流"的 RTL 并分类 | 它与 `grep` 的结果不一致时信它（grep 会漏行首直接例化） |
| `build/cleanup_wip.sh` | `bash build/cleanup_wip.sh`（默认干跑） | 清点临时目录：凡被 `report/ board/ skill/` 点过名的就不删 | 跑着 xsim/Vivado 时不要 `--yes`（锁目录） |
| `sim/top_check_ku5p.sh` | `bash sim/top_check_ku5p.sh` | 20 秒把没有台架例化的第二块板顶层 elaborate 一遍 | 三个不显然的开关（库/第二顶层/timescale）注在文件头 |
| `src/host/doc_enc_check.mjs` | `node src/host/doc_enc_check.mjs [--self]` | 手写件必须 UTF-8、无坏字；`--self` 造三条坏行必须抓到三条 | 坏行是编码问题不是内容问题；`*.txt` 原始回显一律不扫 |
| `src/host/doc_currency_check.mjs` | `node src/host/doc_currency_check.mjs [--self]` | D1 旧构建号不许念成"当前默认"、D2 点名的冻结目录必须在盘上、D3 首页"门禁全绿 = rNN"必须等于盘上编号最大且全绿的那套 | 红了改文档，不要改判据；日记类文件不在 D1 范围内 |
| `src/host/metrics.mjs` | `node src/host/metrics.mjs --fps 30 --seconds 20 --tag rNN --out …`；`--selftest` | 基线 → 推流 → 读回 → 出表，原始读数一起存档；反面对照"错用分母必须给出不同的 fps" | 表里每个结论都要能在同一次 JSON 里找到那几个数 |
| `src/host/health_read.mjs` | `node src/host/health_read.mjs [--json] [--gapclr]` | 从 PS 侧经 GPIO 读 PL 的链路健康快照 | 帧间隔类指标测之前必须先 `--gapclr`；`hb_slow=1` 时 ms 全是周期数不是毫秒（S7） |
| `src/host/arb_handover_test.mjs` | `node src/host/arb_handover_test.mjs [--selftest]` | 无人值守的仲裁交接：自己开关推流，输出七条 PASS/FAIL 与停流后交回用时 | 测前会 `STAT`、在放就先 `STOP`；它红而门禁绿 ⇒ 先看模式是不是被钉住（S20 第六签名） |
| `src/host/geom_check.mjs` · `ps_hb_check.mjs` · `uart_cmd_check.mjs` · `pipe_len_check.mjs` · `temp_formula_check.mjs` | 各自带 `--self` 或 `--selftest` | 分别钉：几何最后一跳、心跳约定、命令电池、控制字长度口径、定点换算 | 这些都不碰板子（`uart_cmd_check` 除外），红了不需要接硬件就能复现 |
| `src/host/ddr_verify.mjs` → `ddr_stale.mjs` | 先回读再分析；一站式用 `measure_v63.mjs --fps N` | 回读两个乒乓 bank、反解帧号、包内相位分带、最长连续丢字带 | 必须**停流之后**再读（边推边读统计全废，S9） |
| `src/host/ku5p_stats.mjs` · `demo_cmds.mjs` · `build/_scan_align.mjs` | `--selftest` / `--emit|--check` / 传镜像路径 | 第二块板遥测、讲稿抽命令与回包对账、扫 ELF 里非对齐字访问 | 与硬件无关的解析类红：先跑它们的 `--selftest` |

## D 踩坑清单 —— 技术类条目，四组

### D1 CDC / 时序 / 预算

- **[S11 pulse_toggle_cdc.md](pulse_toggle_cdc.md)** —— 一拍到两拍的脉冲跨域只能走翻转式同步器，电平型三级同步**不修**它。
  用法：文件里给可抄的最小形状 + 相位扫描判据。失效：目的域周期小于脉宽时裸采也碰巧对，别为它多花一轮构建。
  来源：ISSUES #36（判据 `sim/tb_v79_abort_toggle.v`，三行实测表）。同文件还留了一条硬规矩：
  **一个发射触发器只服务一组同步器**（CDC-11，ISSUES #54/#65 的现场）。
- **[S10 derived_clock_port_mux.md](derived_clock_port_mux.md)** —— 同相 N 倍时钟把单口存储器分时成 N 次读。
  用法：先算两道算术题再动手；"跨进快域"的 Setup 预算是一个快周期不是慢周期；延迟要**量**出来并钉住，
  再用旧值回代自检。失效：改了像素/快钟比例，整张槽位表与所有推导抽位一起作废。
  来源：本项目 build#14 的 −1.277 违例与第三次尝试的半夜间两个台架同时红。
- **[S4 zynq_ddr_bandwidth.md](zynq_ddr_bandwidth.md)** —— 带宽账的算法：吞吐 = 在途深度 ÷ 往返延迟；
  拷贝预算按**窗口**算而不是按平均速率算。失效：时钟/位宽/burst 语义任一与 BD 不符就整段重算。
  来源：ISSUES #30/#31——加深缓冲仿真 100%、板上仍 42~52%，根因是每写一字就等 B 响应。
- **[S2 rotate_window_target_domain.md](rotate_window_target_domain.md)** —— 邻域滤波必须做在逆映射**之后**的那条流上。
  失效：行缓存深度小于有效行宽；金标对比时金标也要先旋转再滤波。来源：ISSUES #10/#16，
  判据本身是反向的（不出现混叠值就说明滤波根本没跑）。

### D2 仿真与判据

- **[S19 combinatorial_block_misses_task_reads.md](combinational_block_misses_task_reads.md)** ——
  `always @(*)` 看不见只在 `task`/`function` 里读的信号：仿真少算一次更新、综合照建方程，屏上是真错标签。
  用法：信号当入参传进去；判据必须**差分**写。失效：只抽一个代表状态的判据抓不到。
  来源：ISSUES 记录于 `report/OVERNIGHT_LOG.md` §33（`sim/tb_osd_lines.v` T3 第一次跑就抓住）。
- **[S22 bench_verilog_subset.md](bench_verilog_subset.md)** —— xsim/`xvlog` 的 Verilog-2001 子集与
  `$display` 格式化子集会怎么骗你：`real'()`/`join_any`/无参 function、非 ASCII 经过定宽向量会掉 bit7、
  `%+d` 会把后面所有参数对位带歪、`integer` 与无符号 net 比较时 −1 哨兵永不成立。
  失效：换了仿真器/版本要重新量一遍——这些是**工具行为**不是语言规范。
  来源：ISSUES #68 的两条追加、`report/OVERNIGHT_LOG.md` §43（一天之内四类 SV 写法 + 两类格式符）。
  同族一条来自被合并的 S3：**层次名引用的 TB 在重写模块前必须 grep 确认**，否则会静默测错对象。
- **[S20](bench_self_inflicted_reds.md)** / **[S21](criterion_blind_spot.md)** —— 主条目在 B 组，这里只提一句
  它们共同的判据口径：**判据读不到 = 判据没跑**；"记录用"的打印要能回答"它一直涨谁会知道"。

### D3 上板与取证

- **[S8 zynq-video-rtl-debug/SKILL.md](zynq-video-rtl-debug/SKILL.md)** —— 上板不亮/画面异常的分层定位 L0–L4，
  每层给真实入口与判据。失效：无 JTAG、无第二网口、画质类问题。
- **[S7 board_eth_uart.md](board_eth_uart.md)** —— 双网口板的连线/绑源地址/COM 号重扫/下 bit 后 PS 必重起；
  两颗 FT2232 同序列号时只有一块可见。来源：`report/OVERNIGHT_LOG.md` §11 与 §"L4 尝试"（ping 失败被明确排除为判据）。
- **[S6 pl_rgmii_udp_offload.md](pl_rgmii_udp_offload.md)** —— 手写协议栈要检查的五处隐性假设：
  前导码 FSM 的一字节偏移、只缓存一个 ARP 对端、上板那条 RX 链不比对目的端口、
  未例化的检查逻辑不是功能、被硬接 1 的统计位。来源：ISSUES #38（`p_good` 是死的统计）。
- **[S13 baremetal_standard_startup.md](baremetal_standard_startup.md)** —— 改入口符号 = 改整条启动链；
  哨兵要写**等值**而不是"存在性"。失效：非 SDT 流程的平台库、`USE_AMP`、跑在 DDR 里（本条未验证）。
  来源：ISSUES #42/#44（"每次异常都长得像一次干净的重启"）。
- **[S12 arbiter_pending_pulse.md](arbiter_pending_pulse.md)** —— 共享介质的三查：`全部空闲 ≠ 任一空闲`、
  一拍宽请求要记账、跨 always 清标志晚一拍。失效：要公平性/配额、带 ready-valid 的总线不适用。
  来源：ISSUES #37，四变体对照表就是判据为什么必须三条一起写的证据。
- **[S1 udp_offset_reasm.md](udp_offset_reasm.md)** —— 上位机 bulk 推流的落位协议：按 offset 写而不是按到达顺序追加，
  提交要两条与门，载荷对齐是板级量出来的。失效：范围合法但错误的 offset 查不出来（整条链不验校验和）。
  来源：ISSUES #5/#27/#29。

### D4 文档与口径 —— 文档也会骗人，所以它需要判据

这四条没有自己的文件，因为它们的可执行部分就是 C 表里的脚本；写在这里是为了让下一个人在动手前读到。

1. **念给人看的每一页，都要有一个脚本在门禁里读它。** 手写件编码（`doc_enc_check`）与文档时效
   （`doc_currency_check`）是同一件事的两半：前者管"字还在不在"，后者管"这个编号还是不是当前"。
   来源：`report/COMMANDS.md` 第 5 节被 cp936 打坏一整段而位流/台架/门禁一个都没红；首页把 build#23
   念成"当前默认"念了五十版。
2. **回显 ≠ 执行。** 批处理工具会把源码逐行打印回去，所以读日志里的标记一律 `^` 锚行首；
   新看门狗第一次跑要先看见它自己打出的匹配行。来源：`report/OVERNIGHT_LOG.md` §43（r59a，
   看门狗在综合正常进行中就报 `BUILD_FAILED_ABORT`，而它的"成功"判据同样会被回显命中）。
3. **判据读的那个文件，不许正是判据自己刚要写的那个。** 门禁输出先落 `/tmp`，全绿之后再 `cp` 到位；
   退出码不许从管道里取。来源：`build/gates.sh` 头部注释（r74 自截空）、ISSUES #69。
4. **没写进报告的那条观测，就当它没发生。** 引用任何数字要给文件路径 + 当场直读复核；
   没跑过的写"未验证"，不靠沉默冒充结论。反面案例有名字：ISSUES #88（门禁不跑顶层台架，
   所以它连着红了好几版而没人知道）、#78（顶层台架的"内容级判据"其实一次都没跑）。
   本仓库为此把"文档时效"做成了门禁项（上面第 1 条）。

---

改这个目录的规矩：新增条目要在上面四组里选一组登记并给一个不重复的 S 号；删条目要先
`git grep -l <文件名>` 确认没人引用；一条经验只许出现在一个文件里，别处只给链接。

工程自身的入口是仓库根 `README.md`；判据与数字的流水在 `report/OVERNIGHT_LOG.md`、
`report/ISSUES.md`；协作轨迹与自我纠错在 `report/AI_COLLABORATION.md`。
