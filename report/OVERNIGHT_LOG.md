# OVERNIGHT_LOG — 无人值守自主迭代记录

工程：`D:\Xilinx\Prj\pro\Video_Processing`（Zynq7020 `xc7z020clg484-2`，以太网视频处理，自主选题·初级组）
记录人：MiMoCode Agent（过夜自主模式）
开始：2026-09-21 22:03（工作区 `pro` 初始化）

---

## 0. 环境与取源

| 项 | 值 |
|----|----|
| 取源 | `git clone https://github.com/Uie-v-uiE/Video_Processing.git` |
| 直连结果 | **失败**：`Recv failure: Connection was reset` |
| 代理结果 | **成功**：`HTTPS_PROXY=http://127.0.0.1:7897` |
| HEAD | `647160e` (v6.4 线，工作树干净) |
| 器件 | xc7z020clg484-2（硬约束，不改） |
| Vivado | `D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat` |
| xsdb | `D:\Software\Vivado\2025.2.1\Vitis\bin\xsdb.bat` |
| PC 侧 | 192.168.1.100/24、COM6、JTAG+UART 已接，HDMI 1024×600 |

`D:\Xilinx\Prj\Rebuild\Video_Processing` 只作为只读对照副本，本轮**未修改**（它有 7 个未提交的 build 产物差异，属于上一位操作者留下的更新的编译产物，与本次干净克隆的 HEAD 产物不同，不作为基线来源）。

---

## 1. 基线（BASELINE，v6.4 @ 647160e）

来源：仓库内 `build/*.rpt`（由「clean clone 可复现构建」提交 `647160e` 产出）。

### 1.1 时序
```
WNS +0.708 ns   TNS 0.000   TNS failing endpoints 0 / 115065
WHS +0.064 ns   THS 0.000   THS failing endpoints 0 / 115065
WPWS +0.264 ns  TPWS 0.000  TPWS failing endpoints 0 / 55225
"All user specified timing constraints are met."
```

### 1.2 资源
| 项 | 数量 | 可用 | 占比 |
|----|------|------|------|
| Slice LUTs | 19825 | 53200 | 37.27% |
| LUT as Memory | 305 | 17400 | **1.75%** |
| Slice Registers | 54588 | 106400 | **51.30%** |
| Slice | 13290 | 13300 | **99.92%** |
| Block RAM Tile | 138.5 | 140 | **98.93%** |
| RAMB36/FIFO* | 137 | 140 | 97.86% |
| RAMS64E（分布式 RAM） | 192 | — | — |
| DSPs | 13 | 220 | 5.91% |
| Bonded IOB | 27 | 200 | 13.50% |

### 1.3 功耗
仓库里 `build/power.rpt` 提交版：`Total 2.240 W`（Dynamic 2.071 / Static 0.169），`Tj 50.8 °C`，置信度 **Low**（无 switching activity 文件，仅供相对比较）。

**本夜重测（build #1，同一 v6.4 网表复现构建，23:13）**：
```
Dynamic 2.338 W   Static 0.187 W   Total 2.525 W   Tj 54.1 °C
```
差 +12.7%。原因：仓库提交版 `power.rpt` 是更早期版本留下的（`CHANGELOG_V6.md` 亦提示 power 与 v6 不同步），
**不是同一网表的产物**。因此本夜功耗基线改用重测值 **2.525 W**，后续所有轮次与它比。
留档：`build/v64_repro_power.rpt`、`v64_repro_timing.rpt`、`v64_repro_utilization.rpt`、`v64_repro_route.rpt`。

### 1.3b 布线状态基线（本夜首次纳入）
```
logical nets 92829 / routable 64604 / fully routed 64604 / nets with routing errors 0
```


### 1.4 方法学 / CDC
- `methodology.rpt`：170 checks，全部 Warning，**无 Critical**。明细：DPIR-1 36、SYNTH-5 48、SYNTH-6 76、TIMING-18 7、LUTAR-1 1、TIMING-9 1、TIMING-10 1。
- `cdc.rpt`：**4 条 Critical 行**（已存在问题，非本轮引入）
  | src→dst | Endpoints | Safe | Unsafe | Unknown | No ASYNC_REG |
  |---|---|---|---|---|---|
  | eth_rxc→clk_fpga_0 | 16 | 15 | 1 | 0 | 14 |
  | clk_fpga_0→clkout0_1 | 16 | 14 | 1 | 1 | 13 |
  | eth_rxc→clkout0_1 | 33 | 0 | 16 | 17 | 0 |
  | sys_clk→eth_rxc | 1498 | 1002 | 2 | 494 | 0 |

### 1.5 L1 仿真基线
```
命令: vivado -mode batch -nojournal -log sim/baseline_regression.log -source sim/run_sim.tcl
结果: SIM DONE pass=28 fail=0      （改动前干净 HEAD 全量回归）
```

### 1.6 基线门禁自评（重要）
| 门禁项 | 要求 | 基线 | 判定 |
|--------|------|------|------|
| WNS/WHS | ≥0，全约束满足 | +0.708 / +0.064，met | PASS |
| BRAM | ≤97%（目标≤95%） | **98.93%** | **FAIL（先于本夜即存在）** |
| Slice | ≤98% | **99.92%** | **FAIL（贴边）** |
| 功耗 | 相对基线不明显恶化 | 2.240 W | 基线即参照 |
| methodology/cdc | 无新增 Critical | 4 条既有 Critical | PASS（无新增即合格） |
| route | Failed Nets=0 | 未单独存档 | 本夜起纳入脚本 |

结论：**基线在「BRAM / Slice」两项上不合格**，而寄存器占用 51.3% 几乎全部来自一处被综合成触发器的 FIFO（见 R02）。因此本夜主线定为「先解开资源死结，再谈效果与时序」。

### 1.7 基线产物
| 文件 | md5(前8) |
|------|----------|
| `build/system.bit` | `155d73bc` |
| `build/system.xsa` | — |

---

## 2. 问题总表

| ID | 问题 | 证据 | 状态 | 处理轮次 |
|----|------|------|------|----------|
| P01 | 打包 FIFO 被综合成 ~5.1 万 FDRE（占整机寄存器 94%），Slice 99.92%、FW 无法加深 | `axi_frame_saver64.v:16-18` 原注释、`utilization.rpt` | **已修（R02：Reg 51.30%→9.02%，Slice 99.92%→34.99%）** | R02 |
| P01b | `axi_frame_writer_gated.v:115-116` 的 `sk_addr_reg/sk_data_reg` 同样掉进触发器（综合报 Synth 8-4767「Block RAM or DRAM implementation is not possible」），约 5.3k FDRE = 现存的 6 成 | build#2 综合日志、`utilization.rpt` Reg 9593 | 待评估（寄存器已无压力，优先级低；若做可再降到 ~4k） | 候选 |

| P02 | BRAM 98.93%，无余量做任何新缓冲/插值 | `utilization.rpt` | 依赖 P01 缓解 | R02+ |
| P03 | 帧尾最后 64bit 字高半 32bit（2 像素）偶发丢（板上 4/8 次），TB +FULL 复现不出 | `report/ISSUES.md`、`report/V6_BOARD_MEASUREMENT.md:70-73` | 分析中 | R03 |
| P04 | `--no-pace` 时 CDC 灌满、整包被丢，画面冻结（已接受但可改善） | `report/CHANGELOG_V6.md:202` | 待处理（依赖 P01 释放资源） | R04 |
| P05 | zoom/rotate 最近邻取整，图像有 1px 栅格闪烁，`frac_x/frac_y` 算了却没用 | `CHANGELOG_V6.md:201`、`V6_ROOT_CAUSE.md:278` | 未开始 | R05+ |
| P06 | `power.rpt` 无切换活动文件，置信度 Low | `build/power.rpt` | 未开始 | 待排 |
| P07 | 36 条 DPIR-1（异步复位寄存器驱动 DSP）+ 76 条 SYNTH-6 | `methodology.rpt` | 未开始 | 待排 |
| P08 | 门禁文件 `power.rpt` / `route_status.rpt` 不在构建脚本产出清单里 | `build/tcl/build_system_axigpio.tcl` | 已修 | R02 |
| P09 | 树内存在 10 个未综合/仅 TB 使用的死模块（`line_cache`、`frame_buffer_db`、`axi_frame_saver_burst` 等） | `src/rtl/**` | 待评估（删除有回滚风险，暂不动） | — |

---

## 3. 轮次记录

### R01 · 2026-09-21 22:03–22:46 · 初始化 + 基线固化

- **动机与证据**：工作区为空，需要可复现基线才能谈优化。
- **取源**：直连 GitHub 被重置 → 代理成功克隆 `647160e`。
- **外部检索**：本轮未联网检索（先把基线钉住）。
- **工具与子代理**：
  - `Explore` 子代理（very thorough）通读 `report/*.md` + `src/rtl`，产出「管线/瓶颈/验证资产/硬限制」摘要 → 直接决定了 R02 主线（其 Q2 表格给出 5 个候选并附文件行号）。
  - 主代理直读 `build/*.rpt` 与 `axi_frame_saver64.v`、`eth_udp_video_top.v:184-315`，数字自行核对，未采信子代理转述的数字。
- **决策与否决**：
  - 采用：以仓库内已提交的 v6.4 报告为基线，**不重跑**基线全量构建（省 40 分钟，报告可复现性由 `647160e` 的提交信息背书）。
  - 否决：不把 `Rebuild` 副本的未提交产物当基线（来源不可追溯）。
  - 主线优先级排序依据：正确性 > 报告门禁 > 功耗资源 > 效果 > 可讲性 —— 但 P01 同时命中「资源 + 功耗 + P&R + 为正确性解锁缓冲」，故选为第一刀。
- **改动清单**：无（仅建本文件）。
- **仿真**：`sim/baseline_regression.log` → **28 PASS / 0 FAIL**。
- **报告门禁**：见 §1.6，基线自身 BRAM/Slice 两项 FAIL，已如实记录。
- **L3/L4/commit**：无。
- **结论与下一步**：基线钉死 → R02 改打包 FIFO 存储实现。

---

### R02 · 2026-09-21 22:46– · 主线：打包 FIFO 由触发器改为分布式 RAM

- **动机与证据**：
  `axi_frame_saver64` 的 `q_addr[512]×32 + q_data[512]×64 + q_keep[512]×4 = 51200 bit`，全部被综合成触发器；整机 Slice Registers 54588 中约 5.1 万来自这一处（94%）。后果链：
  1. Slice 利用率 99.92% → 布局器无余量，是 WNS 只有 +0.708 的直接压力来源；
  2. 注释里写死「FW=11 直接 DRC UTLZ-1 FDRE 176092>107000」→ 打包级缓冲深度被寄存器数量锁死，这是 P04（`--no-pace` 冻结）的上游原因；
  3. 5 万个 FF 每拍翻转 → 动态功耗的主要贡献者之一；
  4. 而 `LUT as Memory` 只用了 1.75%（305/17400），**器件里 98% 的分布式 RAM 是空的**。
- **外部检索**：见 §7（UG901 RAM 推断规则；本轮先按「异步读 + 输出寄存器」模板自证）。
- **改动清单**：
  1. `src/rtl/eth/axi_frame_saver64.v`
     - 三个存储数组加 `(* ram_style = "distributed" *)`；
     - 读出改成显式异步读口 `ridx/rd_addr/rd_data/rd_keep`，`have` 分支锁存 `rd_*`（原来是 `q_*[rptr[FW-1:0]]` 内联读）；
     - 参数注释从「不可加深」改为说明必须用分布式 RAM 的原因。
     - 接口、AXI 行为、`idle/busy/fifo_full` 语义**未改**。
  2. `build/tcl/build_system_axigpio.tcl`：`open_run impl_1` 之后补 `report_power` / `report_route_status` / `report_clock_utilization`（P08），使门禁文件与门禁条款一一对应。
- **仿真（L1）**：见下（改动后全量回归）。
- **报告门禁（L2/L3，build #2，23:16–23:28）**：

  | 门禁项 | 要求 | v6.4 复现 | R02 | 判定 |
  |--------|------|-----------|-----|------|
  | WNS | ≥0 且全约束 met | +0.708 | **+0.677**，`All user specified timing constraints are met.` | PASS（略降 0.031 ns，LUTRAM 读口 mux 代价） |
  | WHS | ≥0 | +0.064 | **+0.048** | PASS |
  | 失败端点 | 0 | 0/115065 | 0/32796 | PASS |
  | Slice LUTs | ≤98%(隐含) | 19825 / 37.27% | **7858 / 14.77%** | −60.4% |
  | Slice Registers | — | 54588 / 51.30% | **9593 / 9.02%** | **−82.4%** |
  | Slice | ≤98% | 13290 / **99.92%** | **4654 / 34.99%** | **FAIL → PASS（本项因本夜修复而合格）** |
  | LUT as Memory | — | 305 / 1.75% | 1233 / 7.09%（RAMD64E 928 + RAMS64E 192） | 换用位置，余量仍 93% |
  | Block RAM Tile | ≤97% | 138.5 / 98.93% | 138.5 / 98.93% | **仍 FAIL（本夜无变化 → 转 R04）** |
  | Total Power | 不明显恶化 | 2.525 W（Dyn 2.338） | **2.412 W（Dyn 2.230）** | PASS，−4.5% |
  | Tj | — | 54.1 °C | 52.8 °C | 改善 |
  | route | Failed Nets=0 | 0/64604 | **0/16362** | PASS（可布线网表减少 75%） |
  | methodology | 无新增 Critical | 170 checks | **170 checks，逐条规则计数完全相同** | PASS |
  | cdc | 无新增 Critical | 4 条既有 Critical 行 | 同样 4 行；`sys_clk→eth_rxc` safe 1002→1003、Unknown 494→493 | PASS（微改善） |

- **L3 产物**：`build/system.bit` md5 `2dd5d1fc`（2120470 B，比基线小 403 KB）、`build/system.xsa`。
- **结论**：入包链行为等价（28/28 回归）+ 全约束仍 met 的前提下，
  **寄存器 −82%、LUT −60%、Slice 从 99.92% 崩到 35%、功耗 −4.5%、布线资源需求 −75%**。
  原注释里「FW 不可加深」的禁令现在解除（深度不再受 FDRE 上限约束），这是 R04/R05 的前提。
  唯一仍不合格项是 BRAM 98.93%（本夜未触碰）→ 立为 R04 主题。
- **下一步**：R03 帧尾 4 字节；R04 BRAM 门禁。

- **过程：第一次尝试失败并定位到综合器规则**
  1. 只加 `(* ram_style="distributed" *)` + 异步读口 → `synth_1` 报
     `WARNING [Synth 8-7186] Applying attribute ram_style = "distributed" is ignored, object 'q_addr[N]' is not inferred as ram due to incorrect usage`，即属性被忽略，仍是触发器。
  2. 为免瞎猜，建最小对照实验 `D:\Xilinx\Prj\pro\tmp_ramtest\`（`ramtest.v` + `probe.tcl`，5 个变体，逐个 `synth_design -mode out_of_context` 后统计单元类型）：

     | 变体 | 写法 | FF | LUTRAM | BRAM |
     |------|------|----|--------|------|
     | v1 | 写放在**带异步复位的控制块**里、经 `task` + `if(!full)` 调用（= 原 RTL 形状） | **32904** | 0 | 0 |
     | v2 | 内存写**独占一个无复位 always 块**，`full` 折进写使能 | **85** | **864** | 0 |
     | v3 | 同 v2 但不加 `ram_style` | 22 | 1 | **1** |
     | v4 | 二维数组 `[0:511][0:7]`（按字节拆） | 32911 | 0 | 0 |
     | v5 | 同 v2，属性写成 `/* synthesis ram_style="distributed" */` 注释式 | 85 | 864 | 0 |

     结论：**阻碍推断的是「内存写与异步复位控制逻辑同在一个 always 块」+ task 封装**，不是读口形状；v3 说明不加属性时综合器会把这块塞进 BRAM——而 BRAM 只剩 1.5 个 tile，所以属性必须显式写 `distributed`。
  3. 按 v2 重写：删掉 `push_word` task，两个调用点合并为一个写脉冲 `push_now`（两处推送内容本来完全相同，都是 `cur_*`），内存写独占 `always @(posedge clk)`，`wptr` 仍留在带异步复位的控制块里由同一 `pack_we` 驱动。
- **兼容性论证（L0）**：`push_now = enable && ((wr_en && idx_chg) || (flush && cur_dirty && !wr_en))` 与原 `if(wr_en)…else if(flush…)` 的优先级逐条件等价；`fifo_full` 时丢字、flush 分支仍清 `cur_dirty` 的既有语义**故意保留**（bug-for-bug，避免与 P03 混在一起）。读口 `rptr` 与写口 `wptr` 只在 `rptr != wptr` 时并发，无读改写竞争。
- **报告脚本（P08）**：`build_system_axigpio.tcl` 增加 `report_power` / `report_route_status` / `report_clock_utilization`，让门禁清单里的每一项都有对应产物。
- **仿真（L1）**：重构后全量回归 `sim/r02b_lutram_regression.log` → **28 PASS / 0 FAIL**（与基线一致，证明「合并推送 + 拆块」是行为等价重构）。
- **build #1（改读口、推断仍失败的那版网表）实为一次 v6.4 复现构建**：
  WNS +0.708 / 0 失败端点 / 全约束 met；LUT 19825、Reg 54588、BRAM 138.5、Slice 13290 —— **与仓库提交版逐项相同**，
  说明库里的报告确实可复现；同时补出了仓库缺的两项基线：
  `power 2.525 W (Dyn 2.338 / Stat 0.187, Tj 54.1 °C)`、`route errors 0 / fully routed 64604`（见 §1.3、§1.3b）。
  顺带确认一个仓库内既有事实：**`dc_fifo.v:46-49` 早就用了「内存写独占无复位 always 块」的正确写法**，
  `axi_frame_saver64` 是入包链里唯一没跟上的模块——这也是为什么 CDC 顺利进了 BRAM 而打包器掉进触发器。


- **结论与下一步**：待填。

---

### R03 · 2026-09-21 22:46–23:52 · 正确性：帧尾 4 字节偶发丢失（P03）定位并修复

- **动机与证据**：`report/ISSUES.md` 与 `report/V6_BOARD_MEASUREMENT.md:70-73` 记录：板上 512×300 帧
  的最后一个 64bit 字（DDR 偏移 `+0x4AFF8`，即第 38399 字）高半 32bit 读回为 0，8 次里见 4 次，
  与速率无关；既有 `tb_v6_ingress_integrity +FULL` 复现不出来。**根因夜之前未被定位**。
- **工具与子代理**：派 `general-purpose` 子代理做只读根因分析（禁止改文件、禁止跑仿真，避免和
  正在跑的构建抢 `sim_work`）。它给出候选机理并指名 `pack_base`/`saver_idle` 是关键。
  **主代理逐条核实**后采纳，未照单全收：
  - 核实为真：`frame_reasm.v:113-123` 里 `flush` 与 `frame_done` **同拍**产生 ⇒ 帧的 flush 标记
    一定排在 CDC 队列里、晚于本帧最后一个数据 lane；
  - 核实为真：`axi_frame_saver64.v:85` 的 `idle` 只含打包器自身 ⇒ 对 8192 深的 CDC 与两级读流水不可见；
  - 核实为真：`eth_udp_video_top.v:239` `fifo_rd <= !fifo_empty && !sv_full` ⇒ 打包器满会**在帧中间**截断读出；
  - **否决**子代理建议的 `saver64: else if (idle) pack_base <= base_addr;` 一行：
    现有条件 `if (!cur_dirty)` 在 idle 时必然已成立，加这行是死代码 ⇒ 不加；
  - **否决**「加超时兜底」：改用 CDC 排空本身作为兜底条件，不引入计数器与新状态。
- **根因（一句话）**：换页判据 `switch_req && saver_idle` **看不见 CDC 里还剩多少本帧数据**。
  打包器满过一次之后如果在帧的最后一个字中间放开，本帧最后 2 个 lane 仍在 CDC 里；
  此时 `frame_done` 已同步到 axi 域并拉起 `force_flush`，把已到的一半字推走 ⇒ 打包器排空 ⇒
  `saver_idle` ⇒ 翻 bank ⇒ 那 2 个 lane 随后进到**已经换过 bank 的 pack_base**，
  被写进下一帧的缓冲区 ⇒ 刚提交的 bank 帧尾 4 字节停在旧值/0。相位相关 ⇒ 板上 4/8 次、与速率无关。
- **工程化前置（这一步比补丁本身更重要）**：这段 glue 原本内联在 `eth_udp_video_top.v:251-298`，
  `tb_v6_pingpong` / `tb_v5_bank` 都是**手抄一份**来测——手抄的副本不会因为真代码改错而变红。
  故先把它抽成独立模块 `src/rtl/eth/ddr_bank_commit.v`（逐行搬移，逻辑不变），
  让 TB 例化**上板的实现**。参数 `TAIL_GUARD` 保留 v6.4 行为，只用于 A/B 对照复现。
- **改动清单**
  1. 新增 `src/rtl/eth/ddr_bank_commit.v`：`commit_ok = saver_idle && tail_drained`，
     `tail_drained = cdc_empty && !cdc_rd && !cdc_d1_v && !sav_en && !sav_flush`；
     `pack_flush = sav_flush | (force_flush && tail_drained)`。
  2. `eth_udp_video_top.v`：内联 glue → `u_commit` 例化；saver 的 `.flush()` 改接 `pack_flush`。
  3. `sim/tb_v6_pingpong.v`：删除手抄副本，改例化 `ddr_bank_commit`（诊断量走层次引用）。
  4. 新增 `sim/tb_v6_tail_bank.v`：两条完整入包链（各自 dc_fifo + axi_frame_saver64 + commit + AXI 从机）
     喂同一激励，`TAIL_GUARD` 一个 0 一个 1，做**双向判据**。
- **仿真（L1）**
  ```
  SIM_TB=tb_v6_tail_bank → sim/r03_tailbank_v3.log
     frame0: 完整 old=8/8 new=8/8                     （基线自洽）
     frame1: 完整 old=7/8 (first_bad_word=7)  new=8/8 （旧链复现帧尾丢 1 字=4 字节，新链完整）
     commits old=2 new=2                              （换页没有被过度延迟）
     RESULT tb_v6_tail_bank PASS
  全量回归 → sim/r03_full_regression.log：SIM DONE pass=29 fail=0（28 旧 + 1 新）
  ```
  TB 自身的两次踩坑也记录在这里，因为它们正是这个仓库反复强调的判据：
  ① AXI 从机用**寄存器版**地址会把 W 数据配到上一拍的地址上，症状「只有 word0 正确」；
  ② `wr_addr` 的单位是 **16bit 字索引**（`frame_reasm` 输出 `off[18:1]`），按字节地址激励会让
  每帧字数翻倍、编址整体错位。
- **报告门禁（L3 build #3）**：见 §5/§6（构建完成后填）。
- **风险与回滚**：改动落在 ETH 入包链（硬约束 4）。回滚 = `git revert` R03 提交；
  行为差异只在「打包器曾满 + 帧末半截字」这一窄窗口，正常限速流下 `tail_drained` 落在帧间隙，
  提交时刻与 v6.4 相同（回归 29/29 与 pingpong 提交次数=2 佐证）。
- **结论**：机理定位 + 双向判据的复现/回归 + 修复生效。待 L4 上板用
  `node src/host/ddr_holemap.mjs` / `ddr_stale.mjs` 的 frameid 判据看板上是否还剩帧尾那一处异常。



## 4. 验证矩阵

| 层 | 手段 | 覆盖 | 最近结果 |
|----|------|------|----------|
| L0 | 直读 RTL + diff 审查 + `git diff --stat` | 入包链、saver 全文、glue 抽取的逐行搬迁 | R03 抽取后人工核对端口/信号一一对应 |
| L1 | `sim/run_sim.tcl` **29** 个 TB（R03 起含 `tb_v6_tail_bank`） | 入包完整性/乒乓/覆盖门/V-blank 拷贝/**帧尾换页 A/B**/rotate/zoom/udp/arp/crc | R03 后 **29/29 PASS**（`sim/r03_full_regression.log`） |
| L2 | `build_system_axigpio.tcl` 的 synth+impl 报告 | 时序/资源/功耗/方法学/CDC/布线 | 见 R02 |
| L3 | bit + xsa | 上板前置 | 见 R02 |
| L4 | UART/ping/JTAG 回读 + `src/host/*.mjs` | 丢包签名、DDR 空洞图 | 未开始 |

## 5. 报告门禁历史表

| 轮次 | WNS | WHS | 失败端点 | BRAM | Slice | LUT | Reg | Total Power | Failed Nets | 新增 Critical | 判定 |
|------|-----|-----|----------|------|-------|-----|-----|-------------|-------------|---------------|------|
| 基线 v6.4（仓库提交版报告） | +0.708 | +0.064 | 0/115065 | 98.93% | 99.92% | 37.27% | 51.30% | 2.240 W(旧) | 未存档 | 0 | 部分 FAIL（BRAM/Slice） |
| build#1 = v6.4 网表复现 | +0.708 | +0.064 | 0/115065 | 98.93% | 99.92% | 37.27% | 51.30% | **2.525 W** | **0** | 0 | 复现成功；功耗/布线基线改为此值 |
| **R02** build#2（打包 FIFO→LUTRAM） | +0.677 | +0.048 | 0/32796 | 98.93% | **34.99%** | **14.77%** | **9.02%** | **2.412 W** | 0 | 0 | **PASS**（BRAM 项沿用基线未解 → R04） |

## 6. bit / xsa 版本表

| 版本 | commit | bit md5(8) | 大小 | WNS | 说明 |
|------|--------|-----------|------|-----|------|
| v6.4 基线 | `647160e` | `155d73bc` | 2523678 B | +0.708 | 仓库自带，可上板 |
| **R02** | 本夜提交 | `2dd5d1fc` | 2120470 B | +0.677 | 打包 FIFO 改分布式 RAM；功能与 v6.4 等价，可上板 |


## 7. 工具与子代理记录

| 轮次 | 工具 | 用途 | 产出 |
|------|------|------|------|
| R01 | `Explore` 子代理 | 通读 14 份报告 + RTL 目录，归纳瓶颈与候选 | 决定主线；数字由主代理复核 |
| R02 | `general-purpose` 子代理（后台） | 帧尾丢 4 字节根因分析（只读，禁改禁跑） | 见 R03 |
| R02 | Vivado xsim | L1 回归 | 见上 |

## 8. 参考与来源

| 来源 | 类型 | 取用 | 许可/声明 |
|------|------|------|-----------|
| AMD Xilinx UG901（7 Series FPGA Memory Solutions / RAM inference 模板） | 官方文档 | 分布式 RAM 的推断条件：单写口 + 异步读口；`ram_style` 属性 | 文档引用，未复制代码 |
| `D:\UserData\Downloads\Ultra-Vision-main\Algorithm`、`Image_Rotate-master` | 本地只读参考 | 待 R05 双三次/插值时引用 | 只读对照，未并入构建 |

（GitHub/Gitee 社区检索：本夜 R02 之前未做，R05 效果类改动前做定向检索。）

## 9. 竞赛叙事（草稿，收尾时定稿）

主线是「**自己定位并解开一处资源死结**」：上板现象（高速率冻结、黑点）→ 逐层量化（寄存器 51.3% 却几乎全是一处 FIFO）→ 用器件里闲置的 98% 分布式 RAM 换掉 5 万触发器 → 报告数字验证 → 再回头用释放的余量解决丢包与画质。

## 10. 未竟项

- P03 帧尾 4 字节：根因未定（子代理分析中）。
- P04 `--no-pace` 冻结：等待 P01 释放资源后加深打包 FIFO 再验。
- P05 插值画质、P06 功耗置信度、P07 方法学清理。
- L4 上板证据：需一次门禁合格的 bit 后再做。
