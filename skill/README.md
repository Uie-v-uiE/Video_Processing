# skill/ —— 这一套里能搬走的东西

这里放的是**方法**，不是 FPGA 教材，也不是本项目的说明书。留下它的标准只有一条：
另一支队伍、另一块板、另一个题目，明天就能照它做一遍，并且做完能省掉一次真实的错误。

**目录里现在有 28 项编号条目**（S1…S30，空号 S3、S6；S8 住在 `zynq-video-rtl-debug/` 里），
加一份给智能体直接加载的 `SKILL.md`。
数法（别抄数，跑这条）：`grep -h -m1 '^# S' skill/*.md skill/zynq-video-rtl-debug/*.md | grep -c '^# S[0-9]'`。
分四组：A 工作流 / B 可抄的骨架 / C 校验脚本（**C 组不占条目，它只有脚本**）/ D 技术踩坑。
**这一句是全仓库唯一写条目数的地方**，别处（README、清单、文档地图）只指路、不抄数——抄了就会漂。

目录里**没有**的东西，是故意的：
- 没有可复制的第二份脚本。`sim/` `build/` 下的脚本只有仓库根那一份是真的，本目录一律用相对路径指过去。
- 没有协议、原语、时序模型的科普。要查那些请去 `docs/ARCHITECTURE.md`、`docs/MODULES.md`。
- 没有同一个结论的第三次复述。下面的每一行只是**路标**，正文在该条自己的文件里，
  而且**每条都是同六节**：触发 / 不适用 / 动作 / 完成判据 / 失效边界 / 出处。
  六节是这次定下来的形式：前五节只回答「下次遇到这个症状该怎么办」，最后一节「出处」
  一行指回 `docs/log/` 里那次真实失败——**过程留在记录里，方法留在这里**。
  一行放不下六节，就只给链接。
- 没有"本项目已经做到多少分"之类的话。这里的每一项都只回答"下次遇到这个症状该怎么办"。

## 我现在这个症状该看哪一条（30 秒定位）

| 症状 / 处境 | 先看 |
|-------------|------|
| 我说"改好了"，但没有一条命令能证明 | [SKILL.md](SKILL.md) 的硬规则 1，再 [S5](llm_fpga_debug_workflow.md) |
| 新写的判据第一跑就**红**，而硬件看着是对的 | [S20 bench_self_inflicted_reds.md](bench_self_inflicted_reds.md) |
| 新写的判据第一跑就**绿**，而缺陷真的还在 | [S21 criterion_blind_spot.md](criterion_blind_spot.md) |
| 需要人看一眼，可是我不能自己看 | [S23 eye_acceptance_loop.md](eye_acceptance_loop.md) |
| 门禁全绿，但我不敢说这是哪一次构建的数 | [S15](artifact_freeze_and_freshness.md) + 下面 C 表的 `gates.sh` |
| CDC / 资源数字变了，不知道是谁 | [S16](cdc_pair_baseline_gate.md) + `build/tcl/cdc_who.tcl` |
| WNS 是负的，不知道该动算术、动扇出还是动物理 | [S28 wns_logic_vs_route_lever.md](wns_logic_vs_route_lever.md)（先读 `logic/route` 分配，`build/tcl/crit_path.tcl` 就是那个口子） |
| 想证明这次改动是"免费的"，可再滚一轮会把证据盖掉 | [S27 prove_change_is_free_by_bitstream_header.md](prove_change_is_free_by_bitstream_header.md)（隔离构建 `build/roll_isolated.sh` + 位流包头比对） |
| 有一段不能碰 RTL 的空档，想让代理通读找坑 | [S29 read_only_review_agent.md](read_only_review_agent.md)（边界写死"禁改/禁跑碰 COM6 的脚本"，**只有能指出 `file:line` 的才算发现**） |
| 门禁/CI 打了"全绿"，而你怀疑有几项今天根本没判 | [S30 verdict_line_must_print_scope.md](verdict_line_must_print_scope.md)（结论行必须带"判定 N 项 / 未判 M 项"，未判那一档行首要换词好让下游 grep 自然拒绝） |
| 上板没画面、没反应、ping 不通 | [S8 zynq-video-rtl-debug/SKILL.md](zynq-video-rtl-debug/SKILL.md)（L0–L4 分层），再 [S7](board_eth_uart.md) |
| 回读回来的一组数不自洽（"部分大于整体"） | [S18](atomic_register_window_readback.md) |
| 同一位置必失败，旁边的人往"超时/竞态"上解释 | [S17](failing_read_prints_geometry.md) |
| 台架日志里的中文变乱码、数字对错位 | [S22](bench_verilog_subset.md) |
| 仿真全绿、上板靠运气（跨域脉冲） | [S11](pulse_toggle_cdc.md) |
| 算出来的 fps / 带宽好得不像话 | [S14](metrics_gap_sum.md)，再 [S4](zynq_ddr_bandwidth.md) |
| 文档念的"当前版本"其实是上一版 | 门禁里那条文档时效判据（`src/host/doc_currency_check.mjs`），规矩在 [S15](artifact_freeze_and_freshness.md) |

编号 **S1…S23 是对外接口**：`src/`、`sim/`、`docs/` 里已经按号或按文件名引用
（例如 `docs/log/OVERNIGHT_LOG.md` 引"技能包 S9 / S17 / S20 / S21"，`src/host/metrics.mjs` 引
`metrics_gap_sum.md`）。**只许新增，不许改号、不许换文件名**，
否则那些引用一夜之间全指向别处。要合并条目：先 `git grep -l <文件名>` 确认没有别处在引它，
把内容与出处一起搬进留下的那一份，删掉被合并的文件，并在**留下的那一份顶上写明合入了哪个号**；
腾出来的号登记成空号，**不回收、不再给别人用**。两个空号都是这样留下的：
- **S3**（原 `axi_stream_verify.md`）：可迁移部分搬进 S21（第 10–12 条）、S22（第 13、14 类）与
  S11（非整数比时钟的握手台架）。
- **S6**（原 `pl_rgmii_udp_offload.md`）：与 S1 是同一条接收链，两处失效条件写得几乎一模一样，
  现在合并进 [S1](udp_offset_reasm.md)（那五处隐性假设在 S1 的「动作」一节里）。

---

## A 工作流 —— 怎么把一个硬件问题变成智能体能执行、且骗不了人的指令

- **[SKILL.md](SKILL.md)**（本目录给智能体直接加载的那一份，不占 S 号）
  什么时候用：开一轮"改 RTL / 定位上板现象 / 出交付材料"之前，整个文件贴进对话或放进工作区。
  怎么用：它给角色、六条硬规则、四步工作循环、四段提示词模板、禁止清单。
  会失效于：工程里没有任何跑得出数的判据（这套纪律靠"能红"才成立，没有判据时它只会拖慢你）；
  需要肉眼收敛的画质问题（那一半在 S23）。
  凭据：拿**上一版** `cdc.rpt` 宣布一条结论、以及连续两晚只生产"时间方向"的合理解释——
  两例都记在 `docs/AI_COLLABORATION.md` 的自我纠错一节与 `docs/log/ISSUES.md` #50。
- **[S5 llm_fpga_debug_workflow.md](llm_fpga_debug_workflow.md)**
  什么时候用：要给模型下指令、或要验收它的结论时抄模板。
  怎么用：两条额外模板（交叉阅读、验收）加三条被验证过有用的习惯，每条后面挂着它抓出过的具体缺陷。
  凭据：这套纪律**推翻过 3 次模型与自己的结论**，每次都留下数字
  （`docs/log/OVERNIGHT_LOG.md` §7、`docs/log/CHANGELOG_V7.md` V7.7、`data/measured/board_measure_r09.md`）。
  会失效于：转述的数字没人直读复核（一律降级为假设）；跨模型/跨工程的可比性没做过实验，本页不外推。
- **[S23 eye_acceptance_loop.md](eye_acceptance_loop.md)**
  什么时候用：症状只有眼睛能判，而分工是"智能体发命令、人看屏"。
  怎么用：配方（前置状态 → 一次一条命令 → 每个"不"指向哪个病灶）+ 用能切换归属的旋钮做二分
  （本工程是 `split 0/50/100`）+ 状态断言只从捕获文件里读。
  凭据：`docs/log/OVERNIGHT_LOG.md` §80 一（一次二分把"那条带属于哪一路"钉死）、§80 三
  （一句没发出去的"已发"让人去查不存在的 bug）、§81 五 与 §82（#102 的最后一半由眼睛关闭）、
  `docs/log/ISSUES.md` #102 的五档观察矩阵、#104 的"看不出差别就是还没修好"。
  会失效于：那一路其实有面板级判据（先去补判据）；没有 A/B 通道；放大后画面碰不到被判的那条边。
- **[S29 read_only_review_agent.md](read_only_review_agent.md)**
  什么时候用：有一段不能碰 `src/rtl`、也不能再开一个仿真的空档（构建/长台架正占着机器），
  而你要的是"整批代码里还有什么坑"。
  怎么用：边界写死（禁改文件、禁跑仿真、**禁跑 `src/host` 下任何会碰 COM6/JTAG 的脚本**）+
  把缺陷分成五类去问 + 每条必须带 `file:line` + 主代理逐条回读，**指不出行号的降级为"下一步该量什么"**。
  凭据：`docs/log/ISSUES.md` #125（代理交回 16 条 ⇒ 8 条进正文、4 条降为 CANDIDATE、其余不采信；
  当场修掉的两条都是"会说谎的那一行"：`[TEMP]` 的负号、`gpio_o[20]` 的三张过期位表）。
  会失效于：需要测量的判断（时序收敛、板级观感、上位机协议）——代理给不出这些，只有判据与眼睛能给。

- **[S30 verdict_line_must_print_scope.md](verdict_line_must_print_scope.md)**
  什么时候用：你有一把把 N 项小判据合成一句结论的聚合判据，而里面有"这条今天没法判"的分支。
  怎么用：给"未判"加计数器（`NSAY`/`NNA` + 一个会自增的 `naa()`，不是散落的 `echo "n/a"`），
  结论行分**三态**且携带范围（有红项 / `PARTIAL —— 判定 N 项全过，但有 M 项未判` / `ALL PASS（N 项全部判定）`），
  并且未判那一档的**行首必须换词**，让下游 `grep '^ALL PASS'` 自然拒绝（本仓下游是 `freeze_evidence.sh`）。
  凭据：`docs/log/ISSUES.md` #141 —— 同一份 r88 报告集，改前打 `ALL PASS` rc=0（`build/r88_gates_naive.txt`）、
  改后打 `PARTIAL … 判定 18 项 / 2 项未判` rc=1（`build/r88_gates_partial.txt`），而那两项正是两把主台架。
  会失效于："未判"若是长期状态 ⇒ 每次都 PARTIAL，很快被忽略，该删那一项或改成硬要求；
  退出码变严会把历史目录的重放也判红（先跑旧目录，分清"真缺凭据"与"读错文件名"）。

## B 案例模板 —— 可以直接抄进自己仓库的骨架

- **[S20 bench_self_inflicted_reds.md](bench_self_inflicted_reds.md)** —— 台架/判据骨架。
  新台架第一跑之前的 30 秒自查清单，加十个"假红/假绿"签名（期望值差常数倍、极值在变而计数为 0、
  等待窗口比被测节拍短、半数组合错在同一个位、查不到当不存在、起点没复位、浮空 X 伪装成功能坏、
  解析器半个接受、日志回显当执行输出、X 与空集上的"通过"）。
  凭据：一天之内三种假红同时出现在 `sim/tb_v94_zoom_sel.v`（`docs/log/OVERNIGHT_LOG.md` §35）；
  Z4 那一组两次变异的读数在 `build/mutation_zoom_snap_r54.txt`。
- **[S21 criterion_blind_spot.md](criterion_blind_spot.md)** —— 判据骨架的镜像面：结构性红不了。
  三条自查按代价排序（空位检查 / 把输入 force 成缺陷态看会不会红 / 扫描矩阵按现象原话补维），
  外加十二条"绿着错"的登记。
  凭据：`docs/log/ISSUES.md` #93 的形状尺子在 1.00× 四档全绿——那一档根本没有一列背景。
- **[S16 cdc_pair_baseline_gate.md](cdc_pair_baseline_gate.md)** —— 门禁脚本骨架。
  比"集合"而不是比行数、基线入库、判红项要自带**能红也能绿**的反例、"记录用不判红"的提示必须有人清账。
  凭据：`docs/log/ISSUES.md` #65；写死"4 行以内算过"吞掉两次真实退化（`docs/log/CHANGELOG_V7.md` 门禁表）。
- **[S15 artifact_freeze_and_freshness.md](artifact_freeze_and_freshness.md)** —— 证据冻结/新鲜度骨架。
  交付单元是"一套"（bit/xsa/elf/报告按 md5 一起冻结），MANIFEST 必须写"验到哪条、哪几条没验"。
  凭据：构建没跑完就念门禁，念到上一版的全绿；同一天还覆盖过一次同名回归日志。
- **[S14 metrics_gap_sum.md](metrics_gap_sum.md)** —— 指标采集骨架。
  采集与算式分离、原始读数一起存档、分母 N−1、分子分母必须同一总体、给表加一条"自相矛盾检查"。
  凭据：`src/host/metrics.mjs --selftest` 里那条反面对照；那一轮"平均值小于最小值"（`docs/log/ISSUES.md` #34 族）。
- **[S9 frameid_loss_signature.md](frameid_loss_signature.md)** —— 取证模板：自描述图案协议。
  图案必须逐帧变化；先停流再回读；把丢字按包内相位 / 空间连续性 / 粒度三个维度展开。
  凭据：恒定图案 `--test wordid` 让三轮实验报"100% 命中"（`docs/log/ISSUES.md` #34"测量工具自己会造假"）。
- **[S17 failing_read_prints_geometry.md](failing_read_prints_geometry.md)** —— 失败分支骨架：
  让失败自己报出"访问的位置 + 位置的来历 + 合法边界 + 当场分类"。
  凭据：`docs/log/ISSUES.md` #50，一行 `[SDRD!]` 把"读超时"翻案成 FAT32 高簇字字节序；两次误判都在往时间方向猜。
- **[S18 atomic_register_window_readback.md](atomic_register_window_readback.md)** —— 多字读回的原子快照骨架。
  先怀疑读法再怀疑硬件；武装信号取自读法本身；快照要带"这一组可不可信"位。
  凭据：`docs/log/ISSUES.md` #59（`c1 = 5.498 ms` 却 `tot = 5.324 ms`）与 #60（没判的判据报成 PASS）。

## C 校验脚本 —— 仓库里真实存在、可以直接跑的那些（本目录不含副本）

调用方式都从仓库根起算。**这一栏不是介绍，是使用说明**：红了先看"先看哪里"那一列，不要先改阈值。
`build/gates.sh` 的**项数会随教训增长**，所以下面一律用"那一项"称呼它，不写序号。

| 脚本 | 一条命令 | 它检查什么 | 红了先看哪里 |
|------|----------|-----------|--------------|
| `build/gates.sh` | `bash build/gates.sh [某个冻结目录]` | 读现成报告出 PASS/FAIL：WNS/WHS 与两类失败端点、BRAM、Slice LUT/Reg、Dynamic、methodology Critical、布线错误网线、CDC 配对集合+unsafe、端口宽度 8-689、多驱动 8-685x、顶层接线、顶层台架 `tb_v98`、边缘条带、PS 心跳约定、手写件编码、文档时效、排练=讲稿。解析不到值就 FATAL 退出，**不拿空值当 0 判绿** | 它自己印的候选行（读不到时会把最像的三行原样打出来）；CDC 那行红 → `cdc_who.tcl` 点名；"WARN 相差 N 分钟" → 构建没跑完，见 S15 |
| `build/gates_cdc_test.sh` | `bash build/gates_cdc_test.sh` | 门禁 CDC 项**自己**的判据：真冻结件必须红、把 unsafe 改回 1 必须绿、新增配对、基线缺列、基线不存在 | 它红 = 你改了 `gates.sh` 的 CDC 解析而没带上这份测试 |
| `build/check_skill_cards.py` | `python build/check_skill_cards.py [--self]` | **本目录自己的**判据：每张卡片六节齐不齐（同义词表认得两种历史形式）、卡片是否超长、README 里那行条目数是否等于盘上实际数。**这是全仓库唯一写条目数的那一行的守卫** | `--self` 先跑：它自带两条反例（缺节的卡、写错的计数），反例不红就说明这把尺子没牙；正文红 → 补那一节，不是把卡片删掉 |
| `build/check_ports.py` | `python build/check_ports.py` | 顶层端口名对得上、输入没悬空、位宽两头一致（因为顶层没有任何台架例化它，这类错全量仿真一条都不会红） | 它点名的那条 net 与两侧模块；凭据文件是 `build/ports_check.txt` |
| `sim/run_one.sh` | `bash sim/run_one.sh tb_xxx` | 单台架快跑（只编要编的文件）；编译**之前**把 `top_md5` / `tb_md5` / `rtl_md5` 写进 `prov.txt` | `exit 3` = 有别的 xsim 正在写同一份 `run.log`，先问是谁的那一跑；红了看 `/tmp/kx/<tb>.run/run.log` |
| `build/tb98_report.sh` · `build/tb98_gate_ce.sh` · `build/rim_gate_ce.sh` | `bash build/tb98_report.sh [run.log]` | 把顶层台架的 console 收成门禁要的凭据（头部两枚 md5）；后两个是这两份凭据各自的反例判据 | 报"不是同一次跑" = 报告比当前树旧 ⇒ 重跑台架，别改报告 |
| `build/board_verify.sh` | `bash build/board_verify.sh [--stream] [--battery] [--geom]` | 板上那一半的机器复验：健康读回、仲裁交接、几何最后一跳、串口命令电池。**不刷板**（刷板留给人确认） | 它末行的总判定；串口类红先确认 COM 号与"是不是刚回读过 DDR"（S18/S7 的失效条件） |
| `build/refresh_evidence.sh` | `bash build/refresh_evidence.sh <NN> [--skip-bench]` | "只改了台架/文档"时刷新同一号：先对账三件成品 md5 是否仍等于 `MANIFEST.md5` | `REFUSE` = 那是新构建，必须换新号；门禁输出先落 `/tmp` 再 `cp`，否则时效那一项读到自己被截空 |
| `build/freeze_evidence.sh` | `bash build/freeze_evidence.sh <NN>` | 收成套凭据并生成 `MANIFEST.md5`（认 md5 不认文件名） | 缺哪个文件就是哪一步没跑，不要手补 |
| `build/tcl/cdc_who.tcl` | `vivado -mode batch -source build/tcl/cdc_who.tcl` | 读**已布线** dcp 出 `report_cdc -details`：哪对寄存器跨域、同步器前有没有组合逻辑 | 只能在两次构建之间跑（下一次 `create_project -force` 会删掉那个 dcp） |
| `build/tcl/hold_paths.tcl` | `vivado -mode batch -source build/tcl/hold_paths.tcl` | 同一份 dcp 出最差 20 条 hold + 6 条 setup 的**路径级**报告 | 想换实现策略之前先看裕量压在谁身上；扫策略前先归档 dcp 派生件 |
| `build/orphan_rtl.sh` | `bash build/orphan_rtl.sh [--selftest]` | 拿综合日志当可达性 oracle，算出"声明了但没进这一版位流"的 RTL 并分类 | 它与 `grep` 的结果不一致时信它（grep 会漏行首直接例化）；"树里有代码 ≠ 板上有功能"见 S1 |
| `build/trim_comments.py` | `python build/trim_comments.py --check` | 批量注释手术的**代码不变性**判据：工作树与 HEAD 各剥掉注释再逐字比，动了一个字节就红 | 它红 = 那一轮不只是注释（`docs/log/ISSUES.md` #106；做法在 S22 第 14 类） |
| `build/cleanup_wip.sh` | `bash build/cleanup_wip.sh`（默认干跑） | 清点临时目录：凡被 `docs/ board/ skill/` 点过名的就不删 | 跑着 xsim/Vivado 时不要 `--yes`（锁目录） |
| `src/host/doc_enc_check.mjs` | `node src/host/doc_enc_check.mjs [--self]` | 手写件必须 UTF-8、无坏字；`--self` 造三条坏行必须抓到三条 | 坏行是编码问题不是内容问题；`*.txt` 原始回显一律不扫 |
| `src/host/doc_currency_check.mjs` | `node src/host/doc_currency_check.mjs [--self]` | D1 旧构建号不许念成"当前默认"、D2 点名的冻结目录必须在盘上、D3 首页"门禁全绿 = rNN"必须等于盘上编号最大且全绿的那套 | 红了改文档，不要改判据；日记类文件不在 D1 范围内 |
| `src/host/metrics.mjs` | `node src/host/metrics.mjs --fps 30 --seconds 20 --tag rNN --out …`；`--selftest` | 基线 → 推流 → 读回 → 出表，原始读数一起存档；反面对照"错用分母必须给出不同的 fps" | 表里每个结论都要能在同一次 JSON 里找到那几个数 |
| `src/host/health_read.mjs` | `node src/host/health_read.mjs [--json] [--gapclr]` | 从 PS 侧经 GPIO 读 PL 的链路健康快照 | 帧间隔类指标测之前必须先 `--gapclr`；`hb_slow=1` 时 ms 全是周期数不是毫秒（S7） |
| `src/host/arb_handover_test.mjs` | `node src/host/arb_handover_test.mjs [--selftest]` | 无人值守的仲裁交接：自己开关推流，输出七条 PASS/FAIL 与停流后交回用时 | 测前会 `STAT`、在放就先 `STOP`；它红而门禁绿 ⇒ 先看模式是不是被钉住（S20 第六签名） |
| `src/host/geom_check.mjs` · `ps_hb_check.mjs` · `uart_cmd_check.mjs` · `pipe_len_check.mjs` · `temp_formula_check.mjs` | 各自带 `--self` 或 `--selftest` | 分别钉：几何最后一跳、心跳约定、命令电池、控制字长度口径、定点换算 | 这些都不碰板子（`uart_cmd_check` 除外），红了不需要接硬件就能复现 |
| `ddr_verify.mjs` → `ddr_stale.mjs` · `ddr_holemap.mjs` | 先回读再分析；一站式用 `measure_v63.mjs --fps N` | 回读两个乒乓 bank、反解帧号、包内相位分带、最长连续丢字带 | 必须**停流之后**再读（边推边读统计全废，S9） |
| `src/host/demo_cmds.mjs` · `build/_scan_align.mjs` | `--emit` 或 `--check` / 传镜像路径 | 讲稿抽命令与回包对账、扫 ELF 里非对齐字访问 | 与硬件无关的解析类红：先跑它们的自检 |

## D 踩坑清单 —— 技术类条目，四组

### D1 CDC / 时序 / 预算

- **[S11 pulse_toggle_cdc.md](pulse_toggle_cdc.md)** —— 一拍到两拍的脉冲跨域只能走翻转式同步器，电平型三级同步**不修**它。
  用法：文件里给可抄的最小形状 + 相位扫描判据。凭据：`docs/log/ISSUES.md` #36，判据 `sim/tb_v79_abort_toggle.v`
  三行实测表（裸采与电平型都是 27/30，翻转式 30/30）。失效：目的域周期小于脉宽时裸采也碰巧对，别为它多花一轮构建。
  同文件还有一条硬规矩：**一个发射触发器只服务一组同步器**（CDC-11，#54/#65 的现场）。
- **[S10 derived_clock_port_mux.md](derived_clock_port_mux.md)** —— 同相 N 倍时钟把单口存储器分时成 N 次读。
  用法：先算两道算术题再动手；"跨进快域"的 Setup 预算是一个快周期不是慢周期；延迟要**量**出来并钉住，
  再用旧值回代自检。凭据：build#14 的 −1.277 违例与第三次尝试的半夜间两个台架同时红；
  r81 三滚全红读穿了模块头的注释口径（`docs/log/ISSUES.md` #105）。
  失效：改了像素/快钟比例，整张槽位表与所有推导抽位一起作废。
- **[S4 zynq_ddr_bandwidth.md](zynq_ddr_bandwidth.md)** —— 带宽账的算法：吞吐 = 在途深度 ÷ 往返延迟；
  拷贝预算按**窗口**算而不是按平均速率算。凭据：`docs/log/ISSUES.md` #30/#31 —— 加深缓冲仿真 100%、
  板上仍 42~52%，根因是每写一字就等 B 响应。失效：时钟/位宽/burst 语义任一与 BD 不符就整段重算。
- **[S2 rotate_window_target_domain.md](rotate_window_target_domain.md)** —— 邻域滤波必须做在逆映射**之后**的那条流上。
  失效：行缓存深度小于有效行宽；金标对比时金标也要先旋转再滤波。
  凭据：`docs/log/ISSUES.md` #10/#16，判据本身是反向的（不出现混叠值就说明滤波根本没跑）。
- **[S28 wns_logic_vs_route_lever.md](wns_logic_vs_route_lever.md)** —— 负 WNS 先读 `logic/route` 分配再选杠杆：
  动算术、动扇出、还是动物理（Pblock / 压端点族 / 疏解绕线）。凭据：`docs/log/ISSUES.md` #105/#121 ——
  我先猜扇出（`max_fanout` 把 WNS 从 −0.062 拖到 −0.192，回滚），再写下"瓶颈是锥体本身"，
  等 `crit_path.tcl` 修到能跑时实测 **6 级逻辑 / route 71 %**，那句结论也被推翻。
  失效：违例属 async/CDC 组，或换角后分配本身会变。

### D2 仿真与判据

- **[S19 combinational_block_misses_task_reads.md](combinational_block_misses_task_reads.md)** ——
  `always @(*)` 看不见只在 `task`/`function` 里读的信号：仿真少算一次更新、综合照建方程，屏上是真错标签。
  用法：信号当入参传进去；判据必须**差分**写。凭据：`docs/log/OVERNIGHT_LOG.md` §33
  （`sim/tb_osd_lines.v` T3 第一次跑就抓住）。失效：只抽一个代表状态的判据抓不到。
- **[S24 sim_hw_divergence_array_writes.md](sim_hw_divergence_array_writes.md)** —— 屏上一根钉死在固定列的黑线、内容无关、仿真全绿：查“越界的数组写在 xsim 被丢掉、在硬件里按地址位截断”与“从没写过的槽”，两条判据都要配复位时的对照。
- **[S25 ab_revert_control_run.md](ab_revert_control_run.md)** —— 改完红了一批、而上一份冻结报告是绿的：把改动存补丁退回未改状态，用**同一版台架**再跑一遍比红名单，再下“是不是我改坏的”的结论。
- **[S26 switch_feature_two_level_evidence.md](switch_feature_two_level_evidence.md)** —— 加“开关”类功能要两级证据：模块内关掉逐位等于背景（背景不许取全黑），顶层在引脚上数一个只有这条链能产生的特征（证明接线真的通）。
- **[S22 bench_verilog_subset.md](bench_verilog_subset.md)** —— xsim/`xvlog` 的 Verilog-2001 子集与
  `$display` 格式化子集会怎么骗你：`real'()`/`join_any`/无参 function、非 ASCII 经过定宽向量会掉 bit7、
  `%+d` 会把后面所有参数对位带歪、`integer` 与无符号 net 比较时 −1 哨兵永不成立，
  以及批量改注释会把代码里的硬编码行号改谎（第 14 类，`docs/log/ISSUES.md` #106）。
  失效：换了仿真器/版本要重新量一遍——这些是**工具行为**不是语言规范。
  凭据：#68 的两条追加、`docs/log/OVERNIGHT_LOG.md` §43（一天之内四类 SV 写法 + 两类格式符）。
  同族一条来自被合并的 S3：**层次名引用的 TB 在重写模块前必须 grep 确认**，否则会静默测错对象。
- **[S20](bench_self_inflicted_reds.md)** / **[S21](criterion_blind_spot.md)** —— 主条目在 B 组，这里只提一句
  它们共同的判据口径：**判据读不到 = 判据没跑**；"记录用"的打印要能回答"它一直涨谁会知道"。

### D3 上板与取证

- **[S8 zynq-video-rtl-debug/SKILL.md](zynq-video-rtl-debug/SKILL.md)** —— 上板不亮/画面异常的分层定位 L0–L4，
  每层给真实入口与判据。凭据：`build/evidence/verify_0927_2309.txt`
  （`board_verify.sh` 退出码 0）。失效：无 JTAG、无第二网口、画质类问题（那一半在 S23）。
- **[S7 board_eth_uart.md](board_eth_uart.md)** —— 双网口板的连线/绑源地址/COM 号重扫/下 bit 后 PS 必重起；
  两颗 FT2232 同序列号时只有一块可见。凭据：`docs/log/OVERNIGHT_LOG.md` §11 与 §「L4 尝试」
  （ping 失败被明确排除为判据）。
- **[S1 udp_offset_reasm.md](udp_offset_reasm.md)**（含原 S6）—— 上位机 bulk 推流的落位协议：
  按 offset 写而不是按到达顺序追加，提交要两条与门，载荷对齐是板级量出来的；
  外加手写 RX 链的五处隐性假设（前导码计数、ARP 单对端、"有代码≠有功能"、被硬接的统计位、地址写死多处）。
  凭据：`docs/log/ISSUES.md` #5/#27/#29/#38。失效：范围合法但错误的 offset 查不出来（UDP 头 checksum 不验）；
  换到 UltraScale+ 整段作废。
- **[S13 baremetal_standard_startup.md](baremetal_standard_startup.md)** —— 改入口符号 = 改整条启动链；
  哨兵要写**等值**而不是"存在性"。凭据：`docs/log/ISSUES.md` #42/#44（"每次异常都长得像一次干净的重启"），
  那张四行阶段表是同一块板同一张卡的实测。失效：非 SDT 流程的平台库、`USE_AMP`、跑在 DDR 里（本条未验证）。
- **[S12 arbiter_pending_pulse.md](arbiter_pending_pulse.md)** —— 共享介质的三查：`全部空闲 ≠ 任一空闲`、
  一拍宽请求要记账、跨 always 清标志晚一拍。凭据：`docs/log/ISSUES.md` #37，
  那张"四个 eth_ctrl 变体各挂一条判据"的对照表就是判据为什么必须三条一起写的证据。
  失效：要公平性/配额、带 ready-valid 的总线不适用。
- **[S27 prove_change_is_free_by_bitstream_header.md](prove_change_is_free_by_bitstream_header.md)** —— 想证明一次
  改动是"免费的"，用隔离构建（`build/roll_isolated.sh`：只 sed 一行 outdir，替换不生效就拒绝跑）把产物写到旁边，
  再 `cmp -l` 两块位流：差异全落在包头 `d` 那个**构建时刻** ⇒ 配置逐位相同。凭据：`docs/OPTIMIZATION_LOG.md` r85 一节
  （同为 2 222 010 B、只差 4 个字节、位置 126/128/129/132）。
  失效：改了 XDC/器件速度/IP 版本时位流必然动；`rtl_md5` 变了仍要重跑钉它的那两份台架报告。

### D4 口径（**不是条目**，是 C 表那几支脚本的使用说明；正文各自的住处已写出，这里只指路）

| 口径 | 唯一住处 |
|------|----------|
| 念给人看的每一页都要有一个脚本在门禁里读它（编码与时效是同一件事的两半） | `src/host/doc_enc_check.mjs` + `doc_currency_check.mjs`，事故见 [S15](artifact_freeze_and_freshness.md) |
| **回显 ≠ 执行**：读日志里的标记一律 `^` 锚行首 | [S20](bench_self_inflicted_reds.md) 第九签名（`docs/log/OVERNIGHT_LOG.md` §43） |
| 判据读的那个文件，不许正是判据自己刚要写的那个；退出码不许从管道里取 | `build/gates.sh` 头部注释（r74 自截空）、[S21](criterion_blind_spot.md) 第 8 条（ISSUES #69） |
| 没写进报告的那条观测就当它没发生；没跑过的写"未验证" | [SKILL.md](SKILL.md) 硬规则 1 与 3，反面案例 `docs/log/ISSUES.md` #78/#88 |
| "我发了什么"从捕获文件里读；那一眼由人签，不由代理签 | [S23](eye_acceptance_loop.md)（`docs/log/OVERNIGHT_LOG.md` §80 三） |

---

改这个目录的规矩：新增条目要在上面四组里选一组登记并给一个**不重复的新 S 号**；
删条目要先 `git grep -l <文件名>` 确认没人引用，并把那个号留成空号（不回收）；
一条经验只许出现在一个文件里，别处只给链接；**项数、门禁第几项、回归条数这类会漂的数，
不写进任何一页**，要写就写"以脚本自己的输出为准"。

工程自身的入口是仓库根 `README.md`；判据与数字的流水在 `docs/log/OVERNIGHT_LOG.md`、
`docs/log/ISSUES.md`；协作轨迹与自我纠错在 `docs/AI_COLLABORATION.md`。
