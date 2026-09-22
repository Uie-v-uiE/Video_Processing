# OVERNIGHT_LOG — 无人值守自主迭代记录

工程：`D:\Xilinx\Prj\pro\Video_Processing`（Zynq7020 `xc7z020clg484-2`，以太网视频处理工程）
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
| P01b | `axi_frame_writer_gated.v` 的 `sk_addr_reg/sk_data_reg` 同样掉进触发器（综合报 Synth 8-4767「Block RAM or DRAM implementation is not possible」），约 5.3k FDRE = 剩余寄存器的 55% | build#4 综合日志、`utilization.rpt` Reg 9560 | **已修（R05：Reg 9.02%→4.08%，Slice 36.05%→18.03%）** | R05 |

| P02 | BRAM 98.93%，无余量做任何新缓冲/插值 | `utilization.rpt`、`util_hier.rpt`（u_fb 独占 128 tile） | **已修（R04：90.5/140 = 64.64%，剩 49.5 tile）** | R04 |
| P03 | 帧尾最后 64bit 字高半 32bit（2 像素）偶发丢（板上 4/8 次），TB +FULL 复现不出 | `report/ISSUES.md`、`report/V6_BOARD_MEASUREMENT.md:70-73` | **已定位并修复（R03：换页未等 CDC 交付完）；证据等级=机理三段论+仿真双向判据。板上 8 轮 A/B 未能复现原现象 ⇒ 无区分力，不宣称板级证实** | R03 / U9 |
| P04 | `--no-pace` 时 CDC 灌满、整包被丢，画面冻结（文档记为已接受） | `report/CHANGELOG_V6.md:202` | **板上未复现**：v6.4 与 R05 两份 bit 在 60/120 fps 不限速下都是 100% 命中；原触发条件需重建（很可能是非 8 倍数载荷） | U9 |
| P05 | zoom/rotate 最近邻取整，图像有 1px 栅格闪烁，`frac_x/frac_y` 算了却没用 | `CHANGELOG_V6.md:201`、`V6_ROOT_CAUSE.md:278` | 未开始 | R06 |
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
  原注释里「FW 不可加深」的禁令现在解除（深度不再受 FDRE 上限约束），这是 R04（BRAM 那一步）的前提。
  唯一仍不合格项是 BRAM 98.93%（本夜未触碰）→ 立为 R04 主题。
- **下一步**：R03 帧尾 4 字节；R04 BRAM 门禁。

- **过程：第一次尝试失败并定位到综合器规则**
  1. 只加 `(* ram_style="distributed" *)` + 异步读口 → `synth_1` 报
     `WARNING [Synth 8-7186] Applying attribute ram_style = "distributed" is ignored, object 'q_addr[N]' is not inferred as ram due to incorrect usage`，即属性被忽略，仍是触发器。
  2. 为免瞎猜，建最小对照实验 `sim/probes/ramtest.v` + `sim/probes/probe.tcl`（5 个变体，逐个 `synth_design -mode out_of_context` 后统计单元类型）：

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



### R04 · 2026-09-22 00:05– · 门禁项：BRAM 98.93% → 定位到「一个模块吃掉 128/140 个 tile」

- **动机与证据**：BRAM 98.93% 是基线就存在、本夜唯一仍未合格的大门禁项。
  新写的 `build/tcl/report_mem_hier.tcl` 给出层次化归属（`build/util_hier.rpt`）：

  | 实例 | 模块 | RAMB36 | LUT | FF |
  |------|------|--------|-----|----|
  | `u_fb` | frame_buffer_w64 | **128.03** | 266 | 2 |
  | `u_cdc` | dc_fifo | 9.03 | 51 | 126 |
  | `u_pipe` | proc_pipeline（blur/sobel 行缓存） | 2×RAMB18 | 732 | 288 |
  | 其余 | — | ≈0 | — | — |

  也就是说 **92% 的 BRAM 被一个显示帧缓存占掉**，而 512×300×16bit = 2.4576 Mb 的理论下限只要 67 个 tile —— 1.9 倍浪费。
- **外部检索**：UG901/UG473 关于 BRAM 深度级联与非 2 的幂深度的处理，但结论没有靠文档，直接用最小实验判定（见下）。
- **对照实验 `sim/probes/fbtest.v` + `probe2/probe3`（同一 512×300 数据量，只改写法）**：

  | 变体 | 写法 | RAMB36 |
  |------|------|--------|
  | v0 | 现状：`reg [63:0] mem [0:38400-1]` | **128** |
  | v1 | 声明深度改成 65536（真 2 的幂） | 128 |
  | v2 | 深度取 1024 的整数倍 38912 | 128 |
  | v3 | 4 个 16bit 宽 bank 交织（仍是单块 38400 深） | 128 |
  | v4 | 32bit 宽、38400 深 | 64 |
  | **v5** | **按 2 的幂拆两块：32768 + 8192** | **80** |

  判读：v0/v1/v2/v3 全部 128 ⇒ 浪费与「数组声明深度」「宽度」「位宽」都无关，
  是**地址空间被向上取到 2^16 个字**这一条决定的（38400 → 65536，填充率 58.6%）；
  v4（32bit 宽）同样填充但总位数减半所以是 64；
  真正能解的是 v5 —— 把地址空间拆成两个 2 的幂块，让每块都不需要填充。
  38400 = 32768 + 5632，第二块再填充到 8192，总利用率 93.75%。
- **改动清单**
  1. `src/rtl/video/frame_buffer_w64.v`：单阵列 → `lo[0:32767]` + `hi[0:8191]` 两块；
     写侧 1bit 块选择，读侧两块同拍都读、用打一拍后的 `sel_hi` 做 2:1 选择，
     **读延迟仍是 1 拍**（v6.4 契约，`pl_video_top` 的读出走数依赖它）；
     越界读仍回黑、越界写仍忽略（行为保持）。分块大小由常量函数 `bitsof()` 从 W/H 推导，
     不硬编码 512×300。
  2. 新增 `sim/tb_fb_roundtrip.v`：此前**没有任何 TB 覆盖这个帧缓存**，改地址映射属于「报告看不出来、
     上屏立刻错位」一类改动，必须先有逐像素回读。实测 153600 像素全比对 + 块边界 ±2 字 +
     帧尾最后一个字 + 越界读黑 + 越界写不污染 ⇒ PASS。
- **过程踩的坑（值得记）**：TB 第一版「超时且一行输出都没有」。原因是**未标位宽的延时常量被截成 32 位**：
  `#20_000_000_000` 实际只有 2.82 ms、`#400_000_000_000` 只有 ~3.4 ms，`initial` 看门狗提前放枪。
  大延时必须写 `#(64'd400_000_000_000)`。第二版还顺手把回读改成**流水式一拍一像素**，
  反而把「延迟=1 拍」的契约变成了可判据（延迟变 2 拍会整体错位立刻全红）。
- **仿真（L1）**：`sim/r04_full_regression.log` → **30 PASS / 0 FAIL**（29 旧 + 新增 `tb_fb_roundtrip`）。
  `tb_fb_roundtrip` 单独跑：`写入完成 38400 字 + 2 次越界写` → 流水回读 153672 次 + 块边界/帧尾定点 16 次 →
  `比对 153688 次，错 0 次` → **PASS**。这同时钉住了「读延迟仍是 1 拍」这条 v6.4 契约。
- **报告门禁（L3 build #4）**：

  > 墙钟说明：build#4 从启动到出 bit 的跨度异常长（而结构相同的 build#5 实测 08:00→08:12 约 12 分钟），
  > 判断是无人值守期间机器休眠/挂起后又恢复；报告内的时间戳与 DCP 自洽，数字不受影响，但**复现时长请以 build#5 为准**。

  | 门禁项 | 要求 | R03 | **R04** | 判定 |
  |--------|------|-----|---------|------|
  | WNS | ≥0 且全约束 met | +0.596 | **+0.819** | PASS（比 v6.4 基线 +0.708 还好） |
  | WHS | ≥0 | +0.078 | **+0.066** | PASS |
  | 失败端点 | 0 | 0/32798 | 0/30846 | PASS |
  | **Block RAM Tile** | **≤97%（目标≤95%）** | 138.5 / 98.93% | **90.5 / 64.64%（RAMB36 89）** | **FAIL → PASS，本夜大门禁项解除** |
  | Slice LUTs | — | 7850 / 14.76% | 7755 / 14.58% | 略降 |
  | Slice Registers | — | 9594 / 9.02% | 9560 / 8.98% | 略降 |
  | Slice | ≤98% | 4679 / 35.18% | 4795 / 36.05% | PASS |
  | LUT as Memory | — | 1233 / 7.09% | 1233 / 7.09% | 不变 |
  | Total Power | 不明显恶化 | 2.411 W（Dyn 2.229） | **2.362 W（Dyn 2.188）** | PASS |
  | Tj | — | 52.8 °C | 52.2 °C | 改善 |
  | route | Failed Nets = 0 | 0/16368 | **0/16139** | PASS |
  | methodology | 无新增 Critical | 170 | **186** | 见下论证 |
  | cdc | 无新增 Critical | 同基线 4 行 | 同基线 4 行 | PASS |

  **methodology +16 的处理（论证而非忽略）**：全部落在 SYNTH-6（76 → 92），逐条查看新增实例名
  均为 `u_pl/u_fb/hi_reg_*`——就是帧缓存新第二块的 16 个 RAMB36 **被逐个报告**，
  内容是「no output register was merged into the block」这一类**提示级 Warning，不是 Critical**。
  代价确实是多了一级 bank 选择 mux（在读出寄存器之后），但实测 WNS 反而从 +0.596 升到 +0.819、
  显示时钟域 50 MHz 余量充足，故接受；若日后要把这级 mux 拿掉，办法是把 `sel_hi` 并进
   lane mux 的选择端（同一个 8:1 mux 出 16bit），留作待办。
- **L3 产物**：`build/system.bit` md5 `ff18beb7`（1994722 B）、`build/system.xsa`。
- **结论**：BRAM 门禁解除，器件剩 49.5 个 BRAM tile 余量 —— 这才让 R06（缩放插值需要行缓存）
  和 P04（加深 CDC）第一次变成「有资源可做」的选项。




### L4 尝试 · 2026-09-22 07:55 · **板卡当前不可访问，L4 未执行（如实记录）**

按 `report/V6_BOARD_MEASUREMENT.md` §7 的规程先做在位检查，结论是**硬件拿不到**，不是脚本问题：

| 检查 | 命令 | 结果 |
|------|------|------|
| JTAG 链 | `vivado -source build/tcl/scan_jtag.tcl` → `build/scan_l4.log` | `ERROR: [Labtools 27-2269] No devices detected on target localhost:3121/xilinx_tcf/Xilinx/0ABC01A`，`open_hw_target` 失败 |
| hw_server | `tasklist` | 进程在跑（PID 24120），目标能枚举出来 ⇒ 适配器（FT4232 通道 A，序列号 0ABC01A）本身是好的 |
| USB 侧 | `Get-PnpDevice` | `USB Serial Converter A/B` OK、`USB Serial Port (COM6)` 存在 ⇒ 线缆/驱动正常 |
| PL 网口 | `ping -n 2 192.168.1.10` | `已发送=2 已接收=0`（PL 未加载 bit 时本就不应答，不能作为判据） |

（收尾前 08:40 又复查一次 `scan_jtag.tcl`，仍是同一句 `No devices detected`。）

判读：**USB 适配器在位、JTAG 链上无器件** ⇒ 最可能是**板卡 12V 未上电**（或 JTAG 排线被拔开）。
无人值守下没有可控手段给板子上电，因此不强行尝试（重启 hw_server、反复 program 都可能把
状态弄得更糟，且对一条不通的链没有意义）。

**产物完整性已核**：`build/system.xsa` 解包内含 `system.bit`（1887418 B，与 `build/system.bit` 同尺寸）
以及 `ps7_init.tcl`（31277 B）——也就是说补做 L4 时，ps7_init 既可以取
`vivado_system/.../design_1_processing_system7_0_0/ps7_init.tcl`，也可以直接从 xsa 里解出来用。

**因此本夜的完成定义按「实现类以报告门禁为准」执行**：R02/R03/R04/R05 都有 L1 仿真 + L2/L3 报告门禁证据；
R03 的帧尾修复额外有双向判据仿真（旧逻辑必须复现、新逻辑必须完整）。
L4 待有人给板子上电后按下面这条已验证过的命令序列补做（脚本已在本仓库内）：

```bat
:: 1) 起 PS（ps7_init.tcl 由构建生成在 vivado_system 里）
"D:\Software\Vivado\2025.2.1\Vitis\bin\xsdb.bat" build\tcl\ps_jtag_boot.tcl ^
  vivado_system\zynq_video_sys.gen\sources_1\bd\design_1\ip\design_1_processing_system7_0_0\ps7_init.tcl
:: 2) 配 PL，再选源
"D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat" -mode batch -nojournal -source build\tcl\program_pl.tcl
"D:\Software\Vivado\2025.2.1\Vitis\bin\xsdb.bat" build\tcl\set_src.tcl
:: 3) 自描述图案推流，再停流回读（先看屏不动，读 DDR 时不要在推流）
node src\host\video_sender.mjs --fps 15 --count 60 --test frameid --pace-mpbps 15
node src\host\ddr_verify.mjs --frameid
node src\host\ddr_stale.mjs
node src\host\ddr_holemap.mjs
```
补做时要看的两个数：① `ddr_stale` 的分带丢字率应每带≈0 且最新帧 100%；
② **帧尾那一处**（`+0x4AFF8` 的字高半 32bit）应当不再出现 v6.4 的 4/8 次异常 —— 这是 R03 的板级判据。

---

### L4 执行 · 2026-09-22 09:05–09:45 · 板级复验（板卡接好后补做）

板卡接好后 JTAG 链出现 `xc7z020_1 PART=xc7z020`，按 §「L4 尝试」的命令序列执行：

```
xsdb build/tcl/ps_jtag_boot.tcl   → PS7_INIT: ok / PS7_POST_CONFIG: ok / DDR_ECHO: 10000000: 5A5AA5A5
vivado  -source build/tcl/program_pl.tcl → PROGRAMMED xc7z020_1 <- build/system.bit
xsdb build/tcl/set_src.tcl        → GPIO 0x41200000 = 00010000   (SRC1=视频，特效关)
ping 192.168.1.10                 → 发送=3 接收=3 丢失=0，RTT 1-2 ms   ← PL 内 ARP/ICMP 栈活着
```

**判据数据（`--test frameid`，图案 = 64bit 字号 + 帧号；回读前一定停流）**：

| 轮次 | bit | 速率 | 每 bank 帧号跨度 | u32 内两 lane 异帧数 | 最新帧 16bit 命中率 | 包内分带丢字率 | 最长连续丢字带 | 帧尾分带 w90-99 |
|------|-----|------|------------------|----------------------|----------------------|----------------|----------------|------------------|
| 1 | R05 `f5c69ca7` | 15 MB/s @15fps | 28..28 / 29..29（各恰好一帧） | 0/76800 | **100.0%** | 六带全 0.0% | 0 | 100 |
| 2-5 | R05 | 15 MB/s @30fps | 单一帧（43/44 交替） | 0 | 100.0% | 0.0% | 0 | 100 |
| 6-7 | R05 | **30 MB/s** @30fps | 单一帧 | 0 | 100.0% | 0.0% | 0 | 100 |
| 8 | R05 | **不限速 60fps**（400 帧） | 单一帧（398/399） | 0 | 100.0% | 0.0% | 0 | 100 |
| 9 | R05 | **不限速 120fps→实测 116fps（≈36 MB/s，900 帧）** | 单一帧（898/899） | 0 | 100.0% | 0.0% | 0 | 100 |
| A1-A6 | **v6.4 基线 `155d73bc`** | 15 MB/s @30fps ×6 轮 | 单一帧 | 0 | 100.0% | 0.0% | 0 | 100 |
| A7 | v6.4 | 不限速 60fps | 单一帧（398/399） | 0 | 100.0% | 0.0% | 0 | 100 |
| A8 | v6.4 | 不限速 120→**106.6fps（≈33 MB/s）** | 单一帧（898/899） | 0 | 100.0% | 0.0% | 0 | 100 |

**能下的结论**：
1. **零回归**：R02（打包 FIFO→LUTRAM）、R04（帧缓存分块）、R05（skid→LUTRAM）三次综合行为改造
   之后，整条 UDP→reasm→CDC→AXI→DDR 链在 15 MB/s 到 ≈36 MB/s（900 帧连发）范围内
   仍然做到「每 bank 恰好一帧、逐 lane 100% 命中、无任何连续丢字带」——
   这是本夜最重要的板级事实，因为这三处改动的风险面正是入包链。
2. **换帧原子性成立**（技能包 S9 的判据：每个 bank 的帧号跨度=1）。
3. 上板 bit 与仓库 `build/system.bit`（md5 `f5c69ca7`）逐字节同一份，报告门禁与板级数据指向同一实现。

**补充：1396 字节载荷（包边界落进 64bit 字内部）3 轮，金样 `f5c69ca7`**

| 轮次 | 激励 | 结果 |
|------|------|------|
| 10-12 | `--fps 30 --count 60 --mtu-payload 1396` ×3 轮（180 帧） | 每 bank 100.0% 命中、`u32 内两 lane 异帧 0/76800`、最长丢字带 0 |

这一条的价值不在 A/B（1396 的黑点本来就是 v6.4 修的，拿 v6.4 做对照不会有差异），而在于：
**非 8 倍数载荷会让每个包边界都在打包器里留下"半截字"**，也就是 R02 这次重写的
`cur_keep / push_now / pack_we` 合并逻辑在硬件上被真正跑到了（180 帧 × 220 包 = 3.96 万次
半截字推送），结果逐 lane 100% 正确。R02 改的是打包器的推送/存储结构，
此前只有 xsim 覆盖；这一条是它的板级旁证。

**为什么停止继续追复现**：为把 `sv_full` 逼到帧尾，已试过 15/30 MB/s、60 fps 不限速、
120 fps 不限速（≈36 MB/s、900 帧连发）、非 8 倍数载荷四档激励，v6.4 基线全部 100% 干净。
剩下的手段是改 RTL 拉长显示拷贝对 HP0 的占用窗口（`axi_frame_writer_gated` 的 `SK/BEATS/MAX_OUT`）
——那是**为了复现一个老 bug 而去改上板实现**，收益与风险不对称（会引入一次非必要的 L3 构建与一次
不在主线上的硬件改动），故改为记成 U9 的待办条件，不在这里做。


**不能下的结论（写清楚，别让它长成战果）**：
- **R03 的板级 A/B 没有区分力**：在 15 MB/s、30 MB/s、60 fps 不限速、120 fps 不限速
  四档激励下，v6.4 基线 bit **6 轮 + 洪水 2 轮全部干净**，没有出现当年记录的
  「帧尾 +0x4aff8 高半个 u32 读 0、8 次见 4 次」。所以**我无法用板上数据证明 R03 修好了那个现象**。
  仓库自身其实早有同样记录：`report/V6_BOARD_MEASUREMENT.md:99` 写明某次复测
  「连 §4.1 的帧尾残留都没出现」⇒ 该现象条件极窄/极稀有，当年的触发条件（载荷是否 8 的倍数、
  上位机分片对齐、网卡 offload 状态）在本机已不可照搬。
- 因此 R03 的证据等级保持为：**机理三段论（flush 与 frame_done 同拍、idle 看不见 CDC、sv_full 会在帧中间截断读出）
  + `tb_v6_tail_bank` 的双向判据仿真**。板上数据只能说明「新版没有把它变坏」。
- 顺带纠正我自己中途的一个过度推论：曾在 R05 洪水轮后写下「文档里已接受的 P04 洪水丢包消失了」——
  随后对 v6.4 基线做同样洪水（60fps、120fps 不限速）也是 100% 干净，
  说明 **P04 在手头激励下根本没被触发**，不存在"消失"。该条已按实测改回未复现状态。

**留下的可执行线索**（要真做板上 A/B，得先造出 `sv_full` 落在帧尾的条件）：
`tb_v6_tail_bank` 里触发机理用的是「读到最后一个字的 lane1 之后停读」；板上等效手段是
把显示拷贝对 HP0 的占用窗口拉长（`axi_frame_writer_gated` 的 `SK/BEATS/MAX_OUT`）或让
上位机按 **非 8 的倍数载荷**（如 1396 B）分包，使包边界落在帧最后一个字内部 ——
`src/host/video_sender.mjs` 目前把载荷固定为 1392（8 的倍数），要加 `--mtu-payload` 才能试。

### R05 · 2026-09-22 07:58– · 资源：把 R02 的结论复用到显示侧 skid 缓冲（P01b）

- **动机与证据**：R02 之后整机寄存器从 54588 降到 9594，但 build#4 的综合日志里仍有
  `WARNING [Synth 8-4767] Trying to implement RAM 'sk_addr_reg' / 'sk_data_reg' in registers.
  Block RAM or DRAM implementation is not possible` —— 即 `axi_frame_writer_gated` 的
  显示拷贝 skid 缓冲（64 × (19+64)bit = 5312bit）**至今仍然是触发器**，
  占剩余 9594 个寄存器的约 55%。原因与 R02 完全同型：数组写和带异步复位的控制逻辑在同一个 always 块里。
- **改动清单**（`src/rtl/axi/axi_frame_writer_gated.v`）
  1. 两个数组加 `(* ram_style = "distributed" *)`，读口改成异步 `sk_rid/sk_addr_q/sk_data_q`；
  2. 原来两处数组写（`sk_drain` 分支内嵌套的 `if (do_skid)`，和 `else if (do_skid)` 分支）
     条件并集恒等于 `do_skid`（`A&&do_skid | !A&&do_skid`），合并成一个独立写块；
  3. 指针 `sk_w/sk_r` 留在原来的异步复位块里，由同一个 `do_skid` 驱动。
- **等价性论证（L0）**：合并前后写条件恒等；读写同地址时分布式 RAM 读出**旧值**，
  与原来「同一个非阻塞块里 RHS 先取旧值」语义一致；复位期间 `m_axi_rready = active && !sk_full`
  且 `active=0` ⇒ `r_hit=0` ⇒ `do_skid=0`，所以新写块不带复位不改变行为。
- **踩的坑**：新写块第一次放在 `wire do_skid` 声明**之前**，xvlog 直接报
  `VRFC 10-3380 identifier 'do_skid' is used before its declaration` —— 数组写块必须在 `do_skid/sk_drain` 声明之后。
- **仿真（L1）**：`sim/r05_full_regression.log` → **30 PASS / 0 FAIL**（含显示拷贝侧的
  `tb_v5_gated` / `tb_v5_copy` / `tb_v57_rdw_copy` / `tb_v5_vblast` / `tb_v6_vblank_copy`）。
- **报告门禁（L3 build #5，08:00–08:12）**：

  | 门禁项 | 要求 | R04 | **R05** | 判定 |
  |--------|------|-----|---------|------|
  | WNS | ≥0 且全约束 met | +0.819 | **+0.499** | PASS（**代价：余量 −0.320 ns**） |
  | WHS | ≥0 | +0.066 | +0.060 | PASS |
  | 失败端点 | 0 | 0/30846 | 0/**21253** | PASS（端点数再降 31%） |
  | Slice Registers | — | 9560 / 8.98% | **4345 / 4.08%** | −54.5% |
  | Slice LUTs | — | 7755 / 14.58% | **6313 / 11.87%** | −18.6% |
  | Slice | ≤98% | 4795 / 36.05% | **2398 / 18.03%** | PASS |
  | LUT as Memory | — | 1233 / 7.09% | 1341 / 7.71% | 换用位置 |
  | Block RAM Tile | ≤97% | 90.5 / 64.64% | 90.5 / 64.64% | PASS（不变） |
  | Total Power | 不明显恶化 | 2.362 W | **2.350 W**（Dyn 2.176 / Stat 0.174，Tj 52.1 °C） | PASS |
  | route | Failed Nets = 0 | 0/16139 | **0/10462** | PASS（可布线网表再降 35%） |
  | methodology | 无新增 Critical | 186 | **186（逐条规则计数完全相同）** | PASS |
  | cdc | 无新增 Critical | 同基线 4 行 | 同基线 4 行 | PASS |

  **这一轮的取舍写明白**：省掉 5215 个寄存器的代价是 WNS 从 +0.819 掉到 +0.499 ——
  分布式 RAM 的异步读口在 100 MHz 的 axi_clk 域里多了一级读选择逻辑。仍然
  `All user specified timing constraints are met`、0 失败端点，故接受。
  若要把这点余量拿回来，路子是把 skid 读口改成「提前一拍预取」（地址在 sk_drain
  之前一拍就确定），属可选项，不在本夜顺手改。
- **L3 产物**：`build/system.bit` md5 `f5c69ca7`（1887418 B）、`build/system.xsa`。
- **累计效果（R02+R04+R05 三轮资源改造）**：
  Slice Register 51.30% → **4.08%**；Slice 99.92% → **18.03%**；BRAM 98.93% → **64.64%**；
  Total Power 2.525 W → **2.350 W**；WNS 始终 ≥0 且全约束满足。
  器件现在同时剩约 49 个 BRAM tile、约 1.6 万个 LUT 与 92% 的分布式 RAM 余量。



### R06 · 2026-09-22 12:40–13:20 · 时序专项：`eth_rxc` 域那条 24 位进位链

- **取证先于改动**。`report_timing` 的逐网线段显示：最差 10 条 `eth_rxc` 路径**全部同构**，
  都是 `u_udp/u_udp_rx/rec_en_reg/Q → u_reasm/rows_hit_reg[*]/CE`，
  `Data Path Delay 7.159 ns（logic 2.314 / route 4.845）、Logic Levels 11（CARRY4=6）`，
  其中**单根网线 `u_eth/u_reasm/udp_rec_en`（fo=50）就占 1.947 ns**，
  发起切片 X79Y41、终点切片 X20Y22（横向 59 列）。
  ⇒ 结论：瓶颈是 `frame_reasm` 的 `cover + pkt_pay + 1 >= FRAME_BYTES`
  这个三操作数加法的进位链，而且它挂在一条很长的跨模块网线之后。
- **先量策略，再改 RTL（结论：策略不是出路）**。
  新增 `build/tcl/sweep_impl_strategy.tcl` 扫 5 个实现策略。两次自爆后重写：
  ① `Flow_PerfOptimized_high` / `Performance_RetimingTDM` 等名字**不被本流程支持**；
  ② `report_timing_summary -check_summary_only` 在 2025.2.1 **不是合法选项**（未捕获即中断）。
  实测把 `impl_1` 显式设成 `Performance_Explore` 得到 **WNS 0.499 / WHS 0.060，与基线（未指定策略）逐位相同**
  ⇒ 这一档策略不是出路，必须动 RTL。脚本与**部分结果**一并入库
  （`build/tcl/sweep_impl_strategy.tcl`、`build/sweep_summary.txt`），
  文件里写明扫描只完成 1/5 个策略就中断 ⇒ 结论只建立在「这一档 = 基线」+「最差 10 条同构」两条事实上。
- **改法**（`src/rtl/eth/frame_reasm.v` → v5.1）：
  把「现场求和 + 与常量比大小」换成「**饱和累加 + 等值比较**」。
  ```verilog
  localparam integer CW = $clog2(FRAME_BYTES + 1);           // 19
  reg [CW-1:0] cov, pend;                                    // 到 SAT 就停
  wire bytes_ok = cov_sat  | (cov_end  & p_valid);
  wire last_pkt = pend_sat | (pend_end & p_valid);
  ```
  等价性三条依据：① `cov` 的新语义就是旧代码每拍现算的 `cover+pkt_pay`；
  ② 计数单调递增 ⇒ `>= FRAME_BYTES` 与 `== FRAME_BYTES` 同问；
  ③ 帧起点（`hdr<4`）与提交两处都清零，饱和值不会跨帧继承。
  EOF 那一拍的最后一个字节仍单独记一笔，且靠 Verilog「后赋值生效」不与 S_DATA 自增重复。
- **一处有意的语义差异（必须写清）**：旧实现靠"坏包字节不计入 cover"来废帧，
  饱和累加无法退账 ⇒ 新增粘滞位 `bad_frame`，提交判据改三条件与门。
  两版判决集合仅在「零载荷坏包」这一退化情形不同，且新实现**只会更严格**
  （不可能出现"以前不提交、现在提交"的危险方向）。
- **踩到**：`cover` 是 SystemVerilog 保留字，任何文件以 `-sv` 编译即报 `VRFC 10-8549`
  ⇒ 寄存器改名 `cov`。改前先 `grep` 确认没有 TB 用层次名引用 `cover/bytes_all/last_pkt`
  （只有 `stat_*` 端口被引用），否则重写会静默让 TB 测错对象。
- **验证**：L1 `tb_v6_cover_gate` 6/6 PASS；**全量回归 30/30 PASS**（`sim/r06_regression.log`）；
  L3 全新构建 `build/r06_build.log`。
- **结果（vs R05）**：WNS **+0.499 → +0.974**（`eth_rxc`）、失败端点 0/21166、
  WHS +0.066、BRAM 64.64%、Reg 4.04%、LUT(逻辑) 9.24%、
  Dynamic **2.338 → 2.176 W**、Failed Nets 0、methodology Critical 0。
- **未预料但无害**：像素域 `clkout0_1` 的 WNS 由 +3.084 落到 +1.729（布局随网表变化，
  仍远高于 0）；全设计 WNS 改由 `eth_rxc` 决定。记录以免下次被当成"退化"。

### R07 · 2026-09-22 13:25– · 约束质量：时钟组挪到只在实现阶段生效

- **动机**：构建日志长期有 2 条 `CRITICAL WARNING [Vivado 12-4739] set_clock_groups:
  No valid object(s) found for '-group [get_clocks -quiet clk_fpga_0]'`。
  `clk_fpga_0` 由 PS7 IP 自己的 XDC 创建，综合阶段还不存在；
  **`-quiet` 只压住 `get_clocks` 的报错、压不住命令本身** ⇒ 整条命令失效
  （连 `eth_rxc`/`sys_clk` 两组一起废掉）。
- **第一次尝试失败并留下一条重要事实**：在 XDC 里写 `if {[llength [get_clocks ...]]}` 保护，
  立刻得到 `CRITICAL WARNING [Designutils 20-1307] Command 'if' is not supported
  in the xdc constraint file`，并且**因为整段解析失败，实现阶段也拿不到时钟组**了。
  ⇒ XDC 文件不是普通 Tcl 脚本，控制流不受支持。该构建被中止。
- **采用**：拆出 `src/constraints/clock_groups_impl.xdc`，在
  `build/tcl/build_system_axigpio.tcl` 里 `used_in_synthesis false` /
  `used_in_implementation true`（"按时机分约束文件"）。
- **为什么这是零风险**：综合阶段这条约束**本来就因命令失败而不存在**，
  拆分只是把"静默失败"变成"明确不施加"。若拆分后实现阶段时序数字发生变化，
  就说明原先假定的"synth 阶段无约束"是错的 ⇒ 停下重查（判据写明，便于证伪）。
- **同轮附带**：R06 之前已删除空约束 `set_false_path -from [get_ports eth_rst_n]`
  （`eth_rst_n` 是输出，`system_top.v:41`），它每轮综合制造 1 条 `Constraints 18-513`。
- **一次误操作，如实记录**：中止 R07 第一次构建后，其子进程 `vivado.exe`（PID 19832，
  `-mode batch -source system_top.tcl`，13:25:35 启动）仍在运行并占住
  `vivado_system/zynq_video_sys.runs`，导致重跑报 `ERROR: [Project 1-161] Failed to remove
  the directory ... might be in use by some other process`。
  处置：先按 `CommandLine/CreationDate` 确认它确属本轮被我停掉的批处理 worker，
  再 `taskkill /PID 19832 /F`；随后把 R06 的 7 份报告与 bit 快照到
  `build/r06_snapshot/`，避免被下一轮覆盖后才想起取证。
- **结果（回填，含预设的证伪判据）**：构建 `build/r07_build.log` 通过，综合/实现/各报告阶段小结行
  均为 `0 Critical Warnings and 0 Errors`；**构建日志里的 CRITICAL WARNING 从 9 条降到 7 条，
  剩下 7 条全是既有的 `BD 41-1348`**（异步复位接到 intercon/GPIO 的 ARESETN，属 BD 结构既有事实）。
  门禁数字与 R06 **逐项相同**（WNS +0.974 / WHS +0.066 / 0 失败端点 / BRAM 64.64% /
  `All user specified timing constraints are met.` / Failed Nets 0 / methodology Critical 0），
  并且 **`build/system.bit` 的 md5 与 R06 完全一致（`7d2cf8ee`）** ——
  bit 逐字节相同 ⇒ 拆分没有改变任何被实际施加的约束效果，风险为零（若不同就会停下重查）。
  `build/cdc.rpt` 的跨域统计与 R06 一致（9 行、同样 3 行 Critical 级条目）。

### R08 · 2026-09-22 17:55–19:55 · P0-A 链路健康自诊断引擎（新子系统）

- **起点**：台架排查（§11）确认两块板的板载 FT2232 共用序列号 `0ABC01`，一台电脑一次只能烧一块
  ⇒ 板级验证此刻做不了。按"禁止空等用户指示"转入不需要板子的 P0-A。
- **动机（一句话）**：`p_good` 在 `eth_udp_video_top.v:188` 被硬接 `1'b1` ⇒ `stat_bad` 上板恒 0，
  而唯一真实的丢数据通道是 `cdc_wr` 被 `fifo_full` 挡住的那一拍。此前它的唯一证据是"屏幕有黑纹"。
- **交付**：`link_monitor.v`（eth_rxc 域统计，10 个 32bit lane）、`snap_cross.v`
  （准静态总线 + 跳变沿 + 心跳超时的跨域器）、`frame_reasm` 只加 `frame_abort`/`rows_missed`
  两个观测口（验收判据一字未改）、OSD 增 `DROP=`/`STALL=` 两行、
  `system_top` 第二路跨域 + 10 选 1 lane 窗口 + BD 加一条 32bit 只读 AXI GPIO、
  `src/host/health_read.mjs`（JTAG 读回，读-改-写并归还 GPIO_0）。
- **本轮真正的产出是三个"仿真全绿、只有综合才暴露"的缺陷**（详见 CHANGELOG V7.6）：
  1. `ms_last16` 被两个 always 块驱动 → `[Synth 8-6858] ... other driver is ignored`，板上会变常量；
  2. 1 ms 分频器写死 `[15:0]` 装不下 `TC=125000` → `ms_tick` 恒假，取证是
     `[Synth 8-6014] Unused sequential element ms_div_reg was removed`；
     **TB 为了跑得动把 `CLK_HZ` 改成 1000，恰好把它掩盖了** ⇒ 新增"生产参数守门"例化；
  3. OSD 里 32bit 十进制除法在 50 MHz 像素域拉出 **45 级 / 26.647 ns** 的链，
     第一次 L3 直接 `WNS −6.765 / 19 个违例端点` → DROP 改十六进制、STALL 饱和到 14bit 并分两拍。
- **新增工具**：`build/tcl/ooc_newmods.tcl` —— 新模块 OOC 综合 + 带 I/O 延迟的时序预检，
  1~2 分钟抓到的问题等于一次 15 分钟全流程。它自己踩的坑也记下来：本流程没有
  `remove_from_collection` 也没有 `get_object_name`；不给 `set_input_delay` 则 OOC 全是
  IN2REG、slack 恒 `inf` 等于没测。
- **判据**（写代码前先定，逐条实现）：
  ① **反例判据**——拉住 `fifo_full` ⇒ `drop_words` 必须非 0；反向：没有 full 必须恒 0；
  ② 缺一个中间包 ⇒ `frame_abort` 恰好一次且 `rows_missed=1` 并进入快照；
  ③ 断流后快照必须继续刷新（否则 stall 冻在好看的值上）；
  ④ 第一个 frame_done 不得把"上电到现在"当帧间隔（TB 里节奏恒定 ⇒ `max-min≤2` 才算对）；
  ⑤ `snap_cross` 100 次捕获必须 100 次不撕烈；⑥ 心跳停 50 ms 内必须报 `hb_gone`。
- **结果**：L1 **32/32 PASS**（`sim/results/regression_v76.txt`，含新增 `tb_link_monitor`
  26 条断言与 `tb_osd_lines`）；L3 门禁全项 PASS ——
  WNS **+0.527** / WHS **+0.048** / 失败端点 0/23635 / BRAM 64.64%（一个 tile 没加）/
  Slice 22.13% / LUT 13.68% / Reg 5.44% / Total 2.361 W / Failed Nets 0 /
  `All user specified timing constraints are met.` / methodology Critical 0 / cdc Critical 行 4→4。
  构建日志 CRITICAL WARNING 7→9：新增两条都是 `BD 41-1348`，即两个新 BD 单元继承既有结构。
- **L4 补做（20:15–20:55，板子已可访问）**：只连 Z7 ⇒ 链路 `arm_dap_0 + xc7z020_1` 出现，
  这也把 §11 的"同一 URL 在两块板之间漂移"钉死了。`ps_jtag_boot`（DDR_ECHO 正确）→
  `program_pl`（`d7e385b6`）→ `set_src`（0x00010000）→ `ping 192.168.1.10` 0% 丢失 →
  `node src/host/health_read.mjs` 读回十个 lane。完整数据表在
  **`data/measured/board_measure_r08.md`**，三条值得单独说的：
  1. **`stall_ms` 空闲时能涨到 0xFFFF、停流后 4946→12142 ms 线性增长** —— 这一条同时是
     CHANGELOG V7.6 里那个"分频器装不下 125000"缺陷已修好的**板级**证据（它只会由 `ms_tick` 推进）；
  2. **两遍读回 22 次采样里没有任何单调 lane 变小** ⇒ 320bit 快照跨域在板上不撕烈；
  3. **反例在板上够不到**：`--no-pace` 洪水后 `drop_words`/`cdc_episodes` 仍然为 0，
     因为排空侧 ~200 MB/s 高于入包上限 125 MB/s，上位机压不满 CDC。
     所以"drop_words 与黑纹同时出现"**没有板级战果**，只有 L1 的强制判据 —— 已如实写进记录。
- **本轮又修了一个自己工具的 bug**：`health_read.mjs` 用 Tcl `split` 解析 `mrd` 的
  `41200000:   00010000` 形式取不到值，而**解析失败后它继续写 GPIO_0**，把 `src_sel`、
  `effect_en`、`threshold` 全清零了 —— 诊断工具自己改掉了被诊断的工况。
  改成 Node 侧解析 + 读不到原值就直接退出。（现场用 `set_src.tcl` 恢复了显示源。）
- **还欠两件人工的**：肉眼确认 OSD 的 `DROP=`/`STALL=` 两行；拔网线验证 `hb_gone`（lane31 bit0）。
  另欠一项小改：`video_sender --drop-packet` 才能定向丢中间包，从而在板上验
  `frames_bad`/`rows_miss_max`（同一改动也能把 R03 的帧尾缺陷推到板级，见 U9）。
- **余量被吃掉这件事**：WNS 从 +0.974 降到 +0.527（−0.447 ns）。仍 ≥0 所以门禁通过，
  但这是本轮的代价，记进 §5 而不是删掉；下一轮若要再动 `eth_rxc` 域要先看这个数。

### R09 · 2026-09-22 20:40–21:2x · 拔线实验推翻假设，于是加 `hb_slow`（V7.6b）

- **触发**：用户肉眼确认 OSD 五行（含新的 `DROP=`/`STALL=`）显示正确，随后做拔线实验。
- **采样设计**：为了避开"每次重开 xsdb 要 3~5 秒"的开销，改成**一条 xsdb 会话里循环 110 次、
  每秒读 lane2/lane8/lane31**（临时脚本 /tmp/hb_watch.tcl，未入库）。这个决定直接产出了结论：
  逐秒的 `stall_ms` 序列才能看出时基被拉慢，隔 20 秒读一次只会看到"数字在涨"。
- **推翻了什么**：R08 的设计假设"拔线后 PHY 停供 RXC ⇒ 心跳超时"。板上 `hb_gone` 始终为 0，
  而硬证据是断流那 13 秒 `stall_ms` 只从 831 走到 1117（**+20.5 计数/秒**，不是 1000/秒），
  而它的唯一时基是 `ms_tick = (ms_div == 124999)` ⇒ 当时 **eth_rxc 实际只有约 2.5 MHz**。
  RTL8211F 没关时钟，是把它拉慢约 48 倍 ⇒ "有没有沿"检不到，能检的是"沿够不够快"。
- **改了什么**：`snap_cross` 加 `hb_slow`（心跳间隔 > SLOW_MS=5 ms 判定时基被拉慢；
  正常 1 ms、退化 ~50 ms，两侧余量 5× 与 10×）；`osd_stall = (hb_gone | hb_slow) ? 9999 : stall_ms`
  （断链时 stall_ms 已无"毫秒"含义，屏上不再假装是）；lane31 → `{30'd0, hb_slow, hb_gone}`；
  `health_read.mjs` 分开报两个位。**比较方向一开始写反**，代入真实数字
  （LIM=10_000_000、1 ms 心跳 ⇒ to_cnt=9_950_000）才发现会把健康的 1 ms 判成退化。
- **门禁（build/v76b_build.log）**：WNS **+0.669**（比 R08 的 +0.527 还好，网表几乎相同 ⇒ 差异是
  布局布线抖动）/ WHS +0.048 / 失败端点 0 / BRAM 64.64% / LUT 13.70% / Reg 5.44% /
  2.361 W / Failed Nets 0 / methodology Critical 0 / cdc Critical 行 4（与 R08 同）/
  构建日志 CRITICAL WARNING 9（与 R08 同）。L1 **32/32 一次进程跑完**（新增 3 条 hb 断言）。
- **板级新证据（bit `3ddde196`，见 `data/measured/board_measure_r09.md`）**：
  ① 健康链路 200 次逐秒采样里 `hb_slow` **零误报**，且 `Δpkts/s = 3315 = 15fps×221 包` 恒定；
  ② 拔线后 `lane31 = 0x2`（slow=1、gone=0）⇒ **这次新加的位真的会亮，而旧的那个不会**；
  ③ 同一次读数里 `frames_bad 0→1`、`rows_miss_max = 299`、`flags.bit1=1`，而 `drop_words` 与
  `cdc_episodes` 仍是 0 —— 说明 lane1/lane2 在**真实故障**下自己动了（原本记在"板上够不到"），
  同时证明两类计数没有互相冒名：断链的缺失不是 CDC 溢出。
- **不夸大**：③ 只观测到"发生"，没隔离机理（要出现 frame_abort 必须"末包到了、中间有洞"，
  拔线瞬间两端都有排队，形状合理但没做可控重复）。stall 的 0xFFFF 当时是"流已结束"造成的，
  与"RXC 被拉慢"两件事不能混着引用。
- **待补**：插回后确认 `hb_slow` 回 0（可逆性）；再做一次"推流中拔 5 秒"把 abort 次数与
  缺行数变成可归因的定量数据（后台已在采样）。

## 4. 验证矩阵

| 层 | 手段 | 覆盖 | 最近结果 |
|----|------|------|----------|
| L0 | 直读 RTL + diff 审查 + `git diff --stat` | 入包链、saver 全文、glue 抽取的逐行搬迁 | R03 抽取后人工核对端口/信号一一对应 |
| L1 | `sim/run_sim.tcl` **32** 个 TB（R08 加 `tb_link_monitor`、`tb_osd_lines`） | 入包完整性/乒乓/覆盖门/V-blank 拷贝/帧尾换页 A/B/帧缓存逐像素回读/**CDC 丢字反例判据**/**生产时基守门**/**跨域不撕烈**/**OSD 字形与饱和** | **R08 后 32/32**，留档 `sim/results/regression_v76.txt`（一次进程跑不完 32 个，记录由两段拼成，每段都是逐字 RESULT 行） |
| L2 | `build_system_axigpio.tcl` 的 synth+impl 报告 | 时序/资源/功耗/方法学/CDC/布线 | **R07 全项合格，WNS 由 +0.499 提到 +0.974**（见 §5） |
| L3 | bit + xsa | 上板前置 | **`7d2cf8ee`（R06=R07，1777758 B）**已出并已上板 |
| L4 | `ps_jtag_boot` → `program_pl` → `set_src` → `video_sender` → 停流 → `ddr_verify`/`ddr_stale`/**`health_read`** | 丢包签名、换帧原子性、帧尾落位、洪水与限速多档、**链路健康数字的板级一致性** | 已执行 19+3 轮（R05 金样）；**R06/R07 新 bit 上再跑 3 轮**：15 fps×200 / 30 fps×300 / 不限速 60 fps×400，每 bank 恰好一帧、命中率 100.0%、六带 0.0%、丢字带 0 字（`data/measured/board_measure_r06_r07.md`）；**R08 新 bit：① 入包链 `--test frameid` 15 fps×200 与 R05 金样逐项同级（每 bank 恰好一帧、命中率 100.0%、六带 0.0%、丢字带 0 字）⇒ 本轮三处 RTL 改动零回归；② JTAG 读回十个健康 lane，空闲/推流/停流三态全部符合设计，22 次两遍读零撕烈，`stall_ms` 线性到 12142 ms（`data/measured/board_measure_r08.md`）** |

## 5. 报告门禁历史表

| 轮次 | WNS | WHS | 失败端点 | BRAM | Slice | LUT | Reg | Total Power | Failed Nets | 新增 Critical | 判定 |
|------|-----|-----|----------|------|-------|-----|-----|-------------|-------------|---------------|------|
| 基线 v6.4（仓库提交版报告） | +0.708 | +0.064 | 0/115065 | 98.93% | 99.92% | 37.27% | 51.30% | 2.240 W(旧) | 未存档 | 0 | 部分 FAIL（BRAM/Slice） |
| build#1 = v6.4 网表复现 | +0.708 | +0.064 | 0/115065 | 98.93% | 99.92% | 37.27% | 51.30% | **2.525 W** | **0** | 0 | 复现成功；功耗/布线基线改为此值 |
| **R02** build#2（打包 FIFO→LUTRAM） | +0.677 | +0.048 | 0/32796 | 98.93% | **34.99%** | **14.77%** | **9.02%** | **2.412 W** | 0 | 0 | **PASS**（BRAM 项沿用基线未解 → R04） |
| R03 build#3（换页等 CDC 排空） | +0.596 | +0.078 | 0/32798 | 98.93% | 35.18% | 14.76% | 9.02% | 2.411 W | 0 | 0 | PASS（BRAM 仍未解） |
| **R04** build#4（帧缓存按 2 的幂分块） | **+0.819** | +0.066 | 0/30846 | **64.64%** | 36.05% | 14.58% | 8.98% | **2.362 W** | 0 | 0（+16 条 SYNTH-6 Warning 已论证） | **PASS，全部大门禁项首次合格** |
| **R05** build#5（显示侧 skid → LUTRAM） | +0.499 | +0.060 | 0/21253 | 64.64% | **18.03%** | **11.87%** | **4.08%** | **2.350 W** | 0 | 0（186 条与 R04 完全相同） | **PASS** |
| **R06** build#6（`frame_reasm` v5.1 饱和累加） | **+0.974** | +0.066 | 0/21166 | 64.64% | 18.09% | 11.77% | 4.04% | 2.350 W（Dynamic **2.176**） | 0 | 0 | **PASS**（`eth_rxc` 0.499→0.974；像素域 +3.084→+1.729，仍宽裕） |
| **R07** build#7（时钟组挪到 impl-only XDC） | +0.974 | +0.066 | 0/21166 | 64.64% | 18.09% | 11.77% | 4.04% | 2.350 W | 0 | 0 | **PASS**，且 **bit 与 R06 逐字节相同**（`7d2cf8ee`）⇒ 改动中性被证明；构建日志 CRITICAL WARNING 从 9 条（6×BD+2×12-4739+1×18-513）降到 **7 条（全部为既有 BD 41-1348）** |

| **R13** build#13（V7.7 发布握手 + ZOOM 解绑） | +0.426 | +0.025 | 0/23422 | 64.64%（未增） | 21.94% | 13.53% | 5.45% | 2.359 W | **0**（12500/12500 全布通） | 0（cdc 仍 4 行 Critical；`clk_fpga_0→clkout0_1` 的 **Unknown 1→0**、Safe 14→16 ⇒ 新增的 `ps_publish` 同步链被工具判为 Safe，正是本次要的效果） | **PASS**。约束全满足、CRITICAL WARNING 9 条与 build#12 逐条相同。WHS 从 +0.042 降到 +0.025 是本轮唯一的负向变化（仍为 0 违例，但这是目前最低的保持余量，明天上板后如果再降要回头看 `ps_publish` 的 3 级链落点）。DSP 保持 9 |
| **R12** build#12（旋转只留右窗） | **+0.540** | +0.042 | 0/23419 | 64.64%（未增） | 21.94% | **13.52%** | 5.45% | **2.357 W** | **0**（12500/12500 全布通） | 0（cdc 仍 4 行 Critical；`sys_clk→eth_rxc` 端点 1858→1859 属既有类抖动，`sys_clk→clkout0_1` Safe 端点 347→152 = 删掉的 `rotate_mapper`） | **PASS**。删 `u_rmap` 换回 **DSP 13→9（−4）**、LUT −182、Reg −24、端点 −279，WNS 反而从 +0.408 提到 +0.540。省下的 4 个 DSP48 正好是 P0-B 插值要用的那类资源 |
| **R10** build#10（V7.6c 时基加宽+饱和+gapclr） | +0.408 | +0.035 | 0/23698 | 64.64% | 21.73% | 13.86% | 5.47% | 2.361 W | 0 | 0（cdc 仍 4 行） | **PASS**。抓出并修掉仪表自身的「量程」缺陷：gap_ms 16bit 回卷（板级实测到 34066 的假数）。WNS 轨迹 +0.527→+0.669→+0.408 属布局布线抖动，但该域余量已从 V7.5 的 +0.974 收缩一半，如实记 |
| **R09** build#9（V7.6b `hb_slow`） | **+0.669** | +0.048 | 0/23637 | 64.64% | —— | **13.70%** | **5.44%** | **2.361 W** | **0** | 0（cdc 仍 4 行；构建日志 CRITICAL WARNING 9 条与 R08 同） | **PASS**。拔线实验推翻「心跳=有没有沿」的假设 ⇒ 改判「沿够不够快」；hb_slow 在 200 次健康采样里零误报、拔线时确实变 1 |
| **R08** build#8（P0-A 链路健康自诊断） | **+0.527** | **+0.048** | 0/23635 | **64.64%**（未增） | **22.13%** | **13.68%** | **5.44%** | **2.361 W**（Dynamic 2.187） | **0** | 0 行（cdc 仍 4 行 Critical；新增 50 个跨域端点全部落在 Safe 列） | **PASS**。代价是 `eth_rxc` 域余量 −0.447 ns。构建日志 CRITICAL WARNING 7→9（两条新 `BD 41-1348` 属既有结构继承）。第一次 L3 曾 **FAIL（WNS −6.765/19 端点）**，根因是 OSD 的 32bit 十进制除法 45 级链，见 CHANGELOG V7.6 |

口径说明：`Slice` 取 `report_utilization` §2「Slice Logic Distribution」的 `Slice` 行（2406/13300），
`LUT` 取 §1 的 `Slice LUTs` 行（6262/53200），`Reg` 取 `Slice Registers`（4303/106400）。

## 6. bit / xsa 版本表

| 版本 | commit | bit md5(8) | 大小 | WNS | 说明 |
|------|--------|-----------|------|-----|------|
| v6.4 基线 | `647160e` | `155d73bc` | 2523678 B | +0.708 | 仓库自带，可上板 |
| **R02** | `8c30d9c` | `2dd5d1fc` | 2120470 B | +0.677 | 打包 FIFO 改分布式 RAM；功能与 v6.4 等价，可上板 |
| R03 | `242f6e7` | `faab6ab3` | 2310718 B | +0.596 | 换页等 CDC 排空；帧尾丢 4 字节修复 |
| **R04** | `ff7c890` | `ff18beb7` | 1994722 B | **+0.819** | 帧缓存分块省 48 个 BRAM tile；金样（被 R05 取代） |
| **R05** | `a22a054` | `f5c69ca7` | 1887418 B | +0.499 | 显示拷贝 skid 缓冲改分布式 RAM；**R06 之前的金样，已上板复验（19+3 轮全绿）** |
| **R06** | 本轮提交 | `7d2cf8ee` | 1777758 B | **+0.974** | `frame_reasm` v5.1（饱和累加 + `bad_frame`）；L1 30/30、L4 三档全绿 |
| **R07** | 本轮提交 | **`7d2cf8ee`（与 R06 逐字节相同）** | 1777758 B | +0.974 | 时钟组挪进 impl-only XDC + 删空约束；**bit 不变即证明改动中性**。R08 之前的金样 |
| **R13** | 本轮提交 | **`0f46ec91`** | 1886314 B | +0.426 | V7.7：PS 发布握手（`util/ps_publish.v`，台架 60/60 相位扫描）+ `ZOOM0/1` 解绑生效 + `set_src.tcl` 改 0x00030000 + 修掉 `fs_tog` 采未同步 `src_sel`。**L1 34/34、L3 全门禁 PASS**。**当前金样候选**（明天上板验 SD 回放与左右窗旋转行为后再定） |
| **R12** | 本轮提交 | **`166f4b94`** | 1938494 B | **+0.540** | 旋转只保留右半窗（删 `u_rmap`）。L1 33/33、L3 全门禁 PASS，DSP 13→9。**明天上板待看**：左窗不转、右窗转。**当前金样候选** |
| **R10** | 本轮提交 | **`69b84310`** | 1986090 B | +0.408 | V7.6c：时基加宽 32bit + gap 饱和 + `gapclr` 归零入口。**已上板对账**：`--gapclr` 生效，gap_sum 增速实测与 15fps×66ms 差 0.1% |
| **R09** | 本轮提交 | **`3ddde196`** | 1977718 B | **+0.669** | V7.6b：拔线时 RXC 被拉慢 ~48×（不是关掉），故加 `hb_slow`。**已上板**：健康链路 200 次采样零误报、拔线 `lane31=0x2`、并首次观测到 `frames_bad`/`rows_miss_max` 在真实故障下自己触发。**当前金样候选** |
| **R08** | 本轮提交 | **`d7e385b6`** | 2042730 B | +0.527 | P0-A 链路健康自诊断（link_monitor + snap_cross + OSD 两行 + GPIO_1 读回）。L1 32/32、L3 全门禁 PASS。**L4 已跑**（三态读回 + 22 次两遍零撕烈），但它只覆盖“仪表读数”，
`drop_words` 的真值判据与 `hb_gone` 仍未在板上触发 ⇒ **暂不当金样**，R07 仍是最后一块全流程验证过的 bit |


## 7. 工具与子代理记录

| 轮次 | 工具 / 子代理 | 为什么用它 | 产出与是否被采信 |
|------|--------------|------------|------------------|
| R01 | `Explore` 子代理（very thorough） | 14 份报告 + 8 个 RTL 目录一次读完，避免主上下文被文件倾倒 | 给出 5 个候选优化点（附文件行号）→ 直接决定 R02 主线；**数字全部由主代理重新直读 `build/*.rpt` 复核**，未采信转述 |
| R02 | `general-purpose` 子代理（后台、只读、禁改文件禁跑仿真） | 帧尾 bug 需要在 `frame_reasm` / `eth_udp_video_top` / 上位机三处交叉阅读 | 给出候选机理；主代理逐条核实：3 条为真（flush 与 frame_done 同拍、`idle` 对 CDC 不可见、`sv_full` 会在帧中间截断读出），**1 条建议被否决**（`else if (idle) pack_base <= ...` 在 `!cur_dirty` 已成立时是死代码），它担心的"换页被饿死"经分析不适用于最终实现 |
| R02 | `sim/probes/ramtest.v` + `probe.tcl`（自建） | 「为什么 `ram_style` 不生效」只有综合器自己能回答；写 5 个变体逐个 out-of-context 综合并统计单元类型 | 结论进 `axi_frame_saver64.v` 注释 + `sim/probes/README.md` |
| R04 | `sim/probes/fbtest.v` + `probe2/3.tcl`（自建） | BRAM 用量无法靠读代码判定 | 6 变体计数（128/128/128/128/64/**80**）⇒ 证明浪费来自地址空间填充而非深度写法 |
| R03/R04 | `build/tcl/report_mem_hier.tcl`（自建） | 「BRAM 被谁吃掉」需要层次化归属 | `build/util_hier.rpt`：`u_fb` 独占 128.03 tile |
| 全程 | `sim/run_sim.tcl`（xsim） | L1 门禁 | 基线 28 → R03 29 → R04/R05 30，每轮回归全绿 |
| 全程 | L3 构建脚本报告段（自建） | 门禁要求 power/route 有对应文件 | 现在自动出 `power.rpt`/`route_status.rpt`/`clock_util.rpt` |
| L4 | `build/tcl/scan_jtag.tcl` + `Get-PnpDevice` + ping | 上板前先确认硬件在位，别对着不通的链反复 program | 第一次判定板卡未上电（如实记录在「L4 尝试」）；板卡接好后同一套检查通过，改判为可执行，19 轮测量见「L4 执行」 |
| 未用 | 其它可用 MCP（browser-use / node-repl / qmind / sites） | 本夜的瓶颈是综合器行为与周期级时序，浏览器检索不是关键路径 | —— |

## 8. 参考与来源

规则：借鉴思路/公式可以，大段复制要标明；外部方法进主线前必须过本工程的仿真与报告门禁。
**本夜没有引入任何第三方源码进入构建路径。**

| 来源 | 类型 | 取用了什么 | 是否落地 | 许可 |
|------|------|-----------|----------|------|
| AMD-Xilinx UG901（7 系列存储器资源）/ UG473 | 官方文档 | 分布式 RAM 的推断条件（单写口 + 异步读）、BRAM 宽度/深度展开 | 是，但**结论以 `sim/probes` 实测为准**，不按文档措辞下判断 | 文档引用 |
| arXiv 2009.09622《Low-Cost Implementation of Bilinear and Bicubic Image Interpolation on FPGAs》 | 论文（检索命中，PDF 正文抓取失败） | 方向性参考：低 BRAM 插值的行缓存/通道共享思路 | 否。只写进 U2 的问题界定，未据此改一行代码 | 论文，仅读 |
| GitHub `delhatch/Zynq_UDP`、`lastweek/source-verilog-ethernet`、`embedded-explorer/Zynq7000-Video-Interfacing` | 同类工程（检索命中） | 确认"PL 侧 RGMII + UDP 卸载"是社区通行结构，本工程与之同构 | 否，未复制任何文件；入包链为自研（v5→v6.4 自有版本记录） | 各仓库许可，未引入 |
| 本仓库 `skill/*.md`（尤其 `frameid_loss_signature.md`） | 自研技能包 | L4 判据（逐字反解帧号；看每个 bank 的帧号跨度判"换帧是否原子"）直接构成 R03 的板级判据 | 是 | 本工程自有 |
| `report/ISSUES.md`、`report/V6_BOARD_MEASUREMENT.md`、`report/V6_ROOT_CAUSE.md` | 工程自身记录 | 帧尾现象的原始观测（4/8 次、`+0x4AFF8`）与"深度无用"的既有结论 ⇒ 用于**否决 U3** | 是 | 本工程自有 |
| 本地只读参考 `D:\UserData\Downloads\Ultra-Vision-main\Algorithm`、`Image_Rotate-master` | 外部工程 | 本夜未使用（R06 做插值时可作对照） | 否 | 未引入 |

**诚信说明**：R02/R04 的两个关键结论（推断被拒的真正原因、BRAM 填充的机制）都是
**先用最小实验自证、再写进代码注释**；外部检索在本夜的作用是"确认自己没走偏"和给 U2 指方向，
真正改变设计决策的是探针数字。社区方案进主线必须走完「来源 + 适配 + 验证」闭环，本夜没有东西越过这一步。

## 9. 对外表述口径（从工程记录里提炼的三张图）

一句话：**把「上板看到的黑点、拖影、冻结」三件事，各自定位到三个不同的真实根因，
并且每修一处都用报告或仿真数字把它钉住。**

本夜的三级证据链（全部可复现，命令在对应轮次里）：

1. **资源死结**（R02/R04/R05）——不是"抠资源"，而是发现器件的资源结构被综合行为扭曲了：
   - 51.3% 的寄存器其实是一个 512×100bit 的 FIFO 被综合成触发器（`task`+异步复位块 ⇒ 拒绝推断），
     器件里 98% 的分布式 RAM 在闲着；
   - 98.93% 的 BRAM 里 92% 被一块显示帧缓存吃掉，原因是**地址空间被填充到 2^16 个字**，
     与数组声明深度、位宽、分 bank 都无关（6 个变体逐个 out-of-context 综合实测出来的）；
   - 累计：寄存器 51.30%→**4.08%**，Slice 99.92%→**18.03%**，BRAM 98.93%→**64.64%**，
     功耗 2.525 W→**2.350 W**，WNS 全程 ≥0 且全约束满足。
2. **一处真正的功能缺陷被定位到周期级**（R03）——帧尾 4 字节偶发丢失。
   根因是「乒乓换页的判据看不见 CDC 里还有本帧的数据」；
   修复前既有 TB 复现不出来，修复方法不是"猜一个然后看屏"，而是
   **先证明激励能复现（旧逻辑必须坏）、再证明修复有效（新逻辑必须好）**的双向判据。
3. **验证资产本身也是交付物**——把只能"手抄一份"的提交/换页 glue 抽成模块，
   让 TB 测的是真正会上板的代码；补上此前完全没人覆盖的帧缓存逐像素回读；
   两次综合对照实验收进 `sim/probes/`。

对外最值得展示的三张图：`utilization.rpt` 的前后对照表（§5）、
`tb_v6_tail_bank` 的 old=7/8 与 new=8/8（R03）、`sim/probes` 的 6 变体 BRAM 计数表（R04）。
诚实边界（板卡接好后已补做 L4，共 19 轮）：入包链在 15→36 MB/s、60/120 fps 不限速下
做到每 bank 恰好一帧、逐 lane 100% 命中、零连续丢字带 —— 这是"三次综合改造没有把入包链改坏"的板级证明。
但**帧尾那个缺陷在 v6.4 基线 bit 上也一次都没复现**（6 轮 + 两轮洪水），
所以 R03 的证据等级只到「机理 + 仿真双向判据」，我没有板级战果可以吹。

### R14 · 2026-09-23 00:0x–00:3x · KU5P：同一套自研以太网栈在 UltraScale+ 上综合 + 实现收敛

**做了什么**：新增 `ku5p/`（顶层 `ku5p_eth_top.v` / 约束 / 构建脚本 / README）。
构建脚本用 `add_files` 直接引主工程 `src/rtl/eth/` 里那 19 个文件（**不复制、不改写**），
只有 RGMII 物理层换成厂商 UltraScale+ 版本并注明出处：7 系列的 `IDELAYE2/IDELAYCTRL`
在 UltraScale+ 上不存在，`IDDR` 也没有 `SAME_EDGE_PIPELINED` 档，正确组合是
`BUFG + BUFIO + IDDRE1`（发送侧 `ODDRE1`）。没有 PS、没有 BD、**没有任何厂商 IP**，
也因此没有 DDR、没有 MMCM：`eth_rxc` 一根 125 MHz 从头喂到尾
（没有像素域消费者 ⇒ 单时钟域；当初最难对的那整套 CDC 在这里不需要）。

**结果（构建口径，不是上板口径）**：WNS **+1.840** / WHS +0.012，0 失败端点 / 9343，
约束全满足；LUT 2268、FF 2002、BRAM **72 tile**、DSP 0；5954 根线全布通 0 错误；
methodology 0 条 Critical Warning；`ku5p_eth.bit` 15.4 MB 已生成。

**BRAM 那个数字我算错过一次**（值得留在记录里）：先写"72 tile 远高于信息量下界 7~8"，
实为把 RAMB36 记成 368,640 bit（真值 **36,864 bit** = 32 Kb 数据 + 4 Kb 校验）。
按 `40960 字 × 64 bit = 2,621,440 bit` 重除：`2,621,440 / 36,864 = 71.1` ⇒ 下界就是 72 块，
实测 71×RAMB36E2 + 2×RAMB18E2 **正好等于下界**；Zynq 的 80 块同样是它自己的下界
（64 bit 宽度时每块只有 32,768 bit 可用）。⇒ 80 vs 72 的差来自器件 RAM 组织方式（E2 为
72 bit 宽），既不是浪费、也不能说成"UltraScale 更省"。教训：资源结论必须"块数 × 每块 bit"实算。

**两次"绿色但无意义"的抓取**：
① 第一版综合通过但 `Block RAM Tile = 0.5` —— 读回累加器只喂给 `_unused_ok`，没有可观测终点，
   于是整块帧缓存连同写路径被剪；② 修它时把 `rd_xor/data_alive` 声明了两次，而重复声明在
   Vivado 里只是 **CRITICAL WARNING 不是 error** ⇒ 标志位成了无驱动隐式网 ⇒ 又被剪。
   最终把 led[1] 定义成"帧完成 **且** 缓存内容 XOR 变过"，缓存才真留在设计里（72 tile）。

**还抓到一处流程缺陷**：`ku5p_build.tcl` 把综合与实现放在同一个批处理进程里跑完就退出，
**没有 `write_checkpoint`** ⇒ 想回头看那条 WHS = +0.012 的路径时 `open_run impl_1` 直接失败，
只能整轮重跑。已补 `write_checkpoint` + 最坏 4 条 min/max 路径明细报告。

**仍未证明**：ping 通、ARP、收流统计、要不要补 IDELAY —— 全部要白天人在线（清单见 §9.5 第 8 步）。
另：`WHS = +0.012 ns` 是"刚好为正"，换个温度/电压就可能翻，**不能当通过用**。

### R15 · 2026-09-23 00:4x–00:5x · KU5P 重构 + 打包器台架 + 一次"我自己的判据没牙"

**改了什么**：把 KU5P 顶层里唯一新写的数据通路逻辑（16bit 像素 → 64bit 字 + 帧末不满一格的落盘）
从顶层抽成共用模块 `src/rtl/video/fb_pack.v`，并给它配了 `sim/tb_fb_pack.v`（12 条判据，
黄金模型按车道下标取 `img[w*4+k]`，刻意不复刻 DUT 的 case 语句）。
重构后重跑实现：**WNS +2.081 / WHS +0.013、0 失败端点 / 9600、LUT 2415、FF 2087、布线 0 错**。

**台架抓到一个真 bug（DUT 的）**：换字时若新字的第一个到达像素正好是车道 3，
整字路径会用**上一个字残留**的低 48 bit 一起写出 ⇒ 修成先算 `base`（换字即清零）再合并。
这类错在屏幕上就是"偶发一列花像素"，只有逐字比对能抓。

**台架自己的两个错，也如实记**（否则明天会以为是 DUT 的问题）：
① 判据 task 内部 `settle` 无效 —— task 实参在**调用点**就求值了，
   于是"每段最后一个字"永远来不及计分，现象却像 DUT 少写一次；正确写法是在调用点之前 settle。
② 我把一个字面量的车道位置写反（`{0,0,img51,img50}`，实际 lane2=[47:32]、lane3=[63:48]）。
⇒ 教训：**判据变红时先问"这个数是台架算的还是被测者算的"**。已写进
`study/05_验证与上板/01_怎样写出能抓bug的testbench.md` 第九、十节。

**还抓到我自己一次"无牙的 PASS"**：给 `video_sender.mjs` 加 `--drop-every N` 后，
我写了个回环脚本验证，baseline 收到 **0** 个包 ⇒ `0 == 0` 让脚本高高兴兴打了 `PASS`。
判据在零证据上通过，等于没有判据。**所以 #15 现在的真实状态是"已实现、未验证"**：
明天要验的话，先把收包数打印出来、再要求 `missing == floor(baseline/N)`，
而不是让"相等"在 0 上成立。`node --check` 只证明语法，不证明行为。

**KU5P 时序侧的下一步（已定位，故意今晚不动）**：最坏保持路径是
`u_icmp/u_crc32_d8/crc_data_reg[11] → crc_data_reg[19]`，**+13 ps** 是"满足但没有余量"。
三个办法按代价列在 `ku5p/README.md §10`；动它要重跑一次实现（约 15 min），
不适合放在上板演示前的最后时刻 —— 现在设计是干净的，先保住这个状态。

## 9.5 明早的板上清单（按顺序做，每条都写了"判据"与"看到什么算过"）

| 步 | 做什么 | 判据 / 期望 |
|----|--------|-------------|
| 1 | 只连 Z7，重启 `hw_server`，下 `build/system.bit`（R13，md5 前缀 `0f46ec91`） | `program_system.tcl` 成功；LED0 心跳 |
| 2 | `xsdb build/tcl/ps_jtag_boot.tcl` → 下 `build/ps_app.elf` → `con` | 串口出现 `[BOOT] ... SD PLAY STOP FRAME0 STAT` |
| 3 | 敲 `SD` | 打印 `FAT32 part_lba=... frames=4398 fps=15.000 files=9`；若报 `card absent` 说明 SD 不在 BSP 的 SDIO0 上，先查 PS 配置 |
| 4 | 网线**拔掉**，敲 `SRC1` 再 `PLAY` | 右半窗动、左半窗不动；每 100 帧打印 `avg x.xxx fps`；**无撕裂**（这是发布协议的目的） |
| 5 | 插回网线，按 key1/key2 | **左窗不转、右窗转**（R12 判据）；OSD 角度行跟着变 |
| 6 | `ZOOM0` / `ZOOM1` | 右窗呼吸缩放停/起（V7.7 前是死命令，这条就是它的回归判据） |
| 7 | `node src/host/health_read.mjs --gapclr` → 推流 30 s → 再读 | `DROP` 为 0 或极小；`STALL` 合理；lane31 两个标志为 0 |
| 8 | 换 KU5P（**只插一块板**，两板 FT2232 同序列号会抢）：下 `ku5p/build/ku5p_eth.bit` → `ping 192.168.1.11` | 通 = 移植成立；不通先看 LED0（有没有 GMII RX_DV），再决定要不要补 `IDELAYE3` |

**先别在板上等的**：UDP 状态回包（KU5P 下一步里最值钱的一件）、Z7 的 `PROC_LAT` 列配准、
`FRAME_BYTES` 参数化、双线性插值的 `clk_pix5x` 分时读口（判据已定，见 §R11 追加 2）。

## 10. 未竟项

按「下一位（或下一夜）可以直接接手」的粒度写：

| # | 事项 | 已有什么 | 缺什么 | 备注 |
|---|------|----------|--------|------|
| U1 | ~~L4 板级复验~~ **19 轮（R05 金样）+ 3 轮（R06/R07 新 bit）已完成** | 数据表见「L4 执行」与 `data/measured/board_measure_r06_r07.md` | —— | 结论：V7.0~V7.5 全程入包链零回归、换帧原子；R03 的板级 A/B 仍无区分力 |
| U2 | **R06 缩放双线性插值**（P05，`frac_x/frac_y` 现在算了不用） | 器件剩 ~49 个 BRAM tile、~1.6 万 LUT；一行的行缓存 = 512×16bit = **1 个 tile** | 读侧要 4 抽头，而帧缓存是 1 读口 1 拍延迟 | 可行路子：水平邻点**大概率在同一个 64bit 字内**（现在读完 64bit 再 mux 一个 lane，另外 3 个 lane 本来就在那里）⇒ 横向插值几乎免费；纵向用 1~2 个行缓存 + 第二读流对齐。判据建议：TB 里建一个 Node/软件黄金模型算 PSNR，别只看"报告绿" |
| U3 | P04 `--no-pace` 冻结 | 已知机理 | —— | **本夜明确否决"加深 CDC"这条路**：V-blank 拷贝窗口 67200 axi 拍 ≈ 672 µs，线速 125 MHz×2B = 250 MB/s ⇒ 要吸收它需 ~168 KB 即 ~84000 条 ×36bit ≈ **84 个 BRAM tile**，全片才 140 个，不可能；与 `CHANGELOG_V6.md` v6.3 的结论（瓶颈是平均排空速率不是深度）一致。真要改善只能改**拷贝调度**（把整帧拷贝摊到整个帧周期而不是 V-blank 窗口） |
| U4 | P06 功耗置信度 Low | 有 `report_power` 基线 2.350 W | 需要 SAIF/开关活动文件 | 要做就是 `xsim` 导 SAIF → Vivado `read_saif`，代价是又一轮全流程；收益只是把"相对比较"变成"绝对估计"，优先级排最后 |
| U5 | P07 36 条 DPIR-1（异步复位寄存器喂 DSP 输入，挡住 DSP 输出寄存器合并） | 定位在 `u_pl/u_zmap/raw_xs` 等 | 改同步复位要重跑入包/显示两侧回归 | 中等收益，低-中风险 |
| U6 | P09 树内 10 个未综合的死模块 | 名单在 R01 摘要里 | 删除前要确认没有 TB 还引用它们 | 纯清洁工作，建议单独一轮，别和功能改动混在一起 |
| U7 | ~~WNS 余量回收（+0.819→+0.499 是 R05 的代价）~~ **已由 R06 解决并超过：WNS +0.974** | R05 的代价来自 skid 多一级读 mux；R06 砍掉的是 `eth_rxc` 域 11 级进位链 | 若要再挖：skid 读口提前一拍预取（未做） | 瓶颈已从「逻辑深度」变成「布线距离 / 高扇出」（`clk_fpga_0` 最差路径 route 占 92.6%、`fo=330` 网线 2.751 ns）⇒ 下一步是 Pblock / 高扇出处理，不是再砍级数 |
| U8 | 一次性诊断脚本已删除；`build/v64_baseline.bit`、`build/r05_golden.bit` 是 A/B 期间的临时副本（未跟踪），收尾删除 | —— | —— | v6.4 bit 随时可用 `git show 647160e:build/system.bit` 取出 |
| U10 | **片外接口时序未被约束**：全仓库 XDC 只有 2 条 `create_clock`，`set_input_delay` / `set_output_delay` **各 0 条**，RGMII TX 由 3 条 `-to`（`rk_zynq7020.xdc:42-44` 的 tx_clk / tx_ctl / txd[*]）整条豁免输出时序检查，RX 侧靠固定抽头的 `IDELAYE2`（`system_top.v:129` 传 `IDELAY_VALUE(15)`，`rgmii_rx.v:29` 默认为 0）而没有把这段延迟写进约束 | `check_timing` 在 `build/timing_summary.rpt` 里自己列出无输入/输出延迟约束的端口；`methodology.rpt` 的 TIMING-18 逐条点名 | 补 RGMII DDR 输入约束（`-add_delay -clock_fall`）+ TX 相位（或 ODELAY / BUFIO 移相） | 预期是**暴露**出真实违例而不是消灭它们 ⇒ 要先决定收不收这笔债：收了报告就不再全绿，但结论更硬。至少口径必须区分「片内满足」与「片外靠板级证据」
| U11 | **三处低成本 CDC 清洁**：`effect_ctrl` 的 3 级捕获链漏标 `ASYNC_REG`、`copy_abort` 被像素域裸采样（同文件里 `allow_copy` 却走了 2FF）、`eth_link` 在像素域裸用 4 处 | 位置 `effect_ctrl.v:12-13`、`pl_video_top.v:283` vs `:294-301`、`pl_video_top.v:282,288,307,486`；`eth_mode`（`:225-230`）已是一份正确的 3FF 版本可直接改用 | 加属性 / 换信号后重跑 L3，看 `cdc.rpt` 与 `methodology.rpt`（TIMING-10）条目变化 | 现况实测：`cdc.rpt` 有 **4 行 Critical**（类型均为 `Asynch Clock Groups`，即时钟组豁免掉的跨域），其中 `eth_rxc→clkout0_1` 33 端点里 **16 unsafe / 17 unknown**、`clk_fpga_0→clkout0_1` 16 端点里 **13 无 ASYNC_REG** ⇒ 这两行正好对应上面两个问题点。三处都不动功能逻辑，风险极低，是下一夜最划算的一笔
| U12 | `frame_reasm` 的 `FRAME_BYTES` 未被例化覆盖（`eth_udp_video_top.v:185` 只传 IMG_W/IMG_H） | 默认值恰好 = 512×300×2，所以现在是对的 | 例化时传 `.FRAME_BYTES(IMG_W*IMG_H*2)`，并同步检查 `pl_video_top.v:363` 写死的行距 `{sy[8:0],9b0}` | 不改就是「改分辨率会静默失配」的地雷；本夜不动（要连带重跑入包链全回归）
| U9 | **重建 R03/P04 的板上触发条件**：给 `src/host/video_sender.mjs` 加 `--mtu-payload`（非 8 倍数，如 1396），使包边界落在帧最后一个字内；或拉长 `axi_frame_writer_gated` 的 HP0 占用窗口以逼出 `sv_full` | `tb_v6_tail_bank` 已给出等效激励形状（读到最后一字 lane1 后停读） | 需要一次上位机小改 + 重测 | 这是把 R03 从「仿真级证据」提升到「板级证据」的唯一路子 |


## 11. 台架：两块板抢同一个 JTAG 名字（2026-09-22 17:5x 实测）

**现象**：Z7 与 KU5P 的 Type-C 同时插电脑时，`hw_server` 只给出**一个** target
`localhost:3121/xilinx_tcf/Xilinx/0ABC01A`；`TARGET_COUNT=1` 恒定，与拔插顺序有关。

**证据（全部本机可复现）**：

| 探针 | 结果 |
|------|------|
| `Get-PnpDevice -PresentOnly`，`USB\VID_0403&PID_6010\*` | **两个** FT2232 复合设备都在总线上：`\0ABC01`（Port_#0003.Hub_#0004）与 `\6&9358AC4&0&2`（Port_#0002.Hub_#0004），同一个父 hub `USB\VID_35D6&PID_2510\5&2ec48346&0&1` |
| 两者的 `BusReportedDeviceDesc` | 都是 **`my product desc`** —— FTDI 出厂模板串，说明 EEPROM 只用同一份模板写过 |
| 两者的 `DEVPKEY_Device_SerialNumber` | 都为空（Windows 只在 instance id 里体现）|
| COM 口归属 | `COM6` ← `FTDIBUS\VID_0403+PID_6010+0ABC01B`（通道 B，即 `\0ABC01` 那个 instance）；`COM4` ← `...+6&9358AC4&0&2&2`（另一个 instance）|
| 重启 `hw_server`（杀进程→等 8 s→重扫）后 | 仍然只有 `0ABC01A` 一个 target；`open_hw_target` 报 `[Labtools 27-2269] No devices detected` |

**判读**：这不是驱动问题、不是线不好、也不需要动 EEPROM。机制是**两颗 FT2232 的序列号被
写成了同一个值**：Windows 只能给序列号冲突的设备中的一个保留 `0ABC01` 实例名、另一个退回
总线位置名；`hw_server` 用串口号拼 cable URL，于是同名的第二根线**根本不产生第二个 target**。
谁先枚举谁拿到名字 ⇒ 表现为「两块板互相抢端口」。今天早些时候同一个 URL `0ABC01A` 里出现过
`arm_dap_0 + xc7z020_1`，17:4x 出现的是 `xcku5p_0` —— 名字在两块板之间漂移，是这条结论的正证据。

**DONE 灯**：本机设计只支持 JTAG 下载，没有 `BOOT.BIN`，所以**断电重上电后 DONE 常暗是预期行为**
（`DONE = FCFG_*_0 = H 1`）。之前上电即亮，最可能是那张被清掉的卡是 **PYNQ 启动卡**，SD 自启动把
FPGA 配置了。不是故障；要把这个行为拿回来，就是我们自己写 SD/QSPI 自启动（见未竟项与 P1）。

**待用户做的 10 秒判别实验**（软件侧无法区分两块板谁拿到了名字）：一次只拔一根 Type-C，
看消失的是 `\0ABC01` 还是 `\6&9358AC4&0&2`，即可确定当前 `0ABC01` 属于哪块板。
另外请确认 Z7 的 **PWR** 灯是否亮（`27-2269 No devices detected` 的第一嫌疑是板子没电）。

## 12. P0-B 架构判定（2026-09-22 22:1x，先量再动）

双线性插值要同时拿到源的第 `r` 行和第 `r+1` 行。最省事的想法是"再要一个读口"，
但**这是可以直接测的**，所以先测了（`sim/probes/dpfb.v` + `probe4.tcl`，OOC 综合数 tile）：

| 变体 | 写法 | RAMB36 |
|------|------|--------|
| `dp_v0` | 与生产版 `frame_buffer_w64` 同形：1 写 64bit + 1 读 16bit | **80**（对上已知的 80 ⇒ 探针可信） |
| `dp_v1` | 1 写 + **2 读**，各自带 lane mux | **160**（正好翻倍） |
| `dp_v2` | 1 写 + 2 读，两口都读 64bit 整字 | 128（对照组，见下方说明） |
| `dp_v3` | 整帧复制两份、各给一个读口（明知是坏主意的对照） | 128 |

⇒ **7 系列 RAMB36 只有 A/B 两个口，第三个逻辑读口只能靠复制阵列实现**：
90.5 + 80 = 170.5 > 140，**双读口方案出局**，而且是实测出局，不是拿架构常识搪塞。

（`dp_v2`/`dp_v3` 的 128 不能当成"第三个口只要 48 个 tile"的证据：它们的读侧只覆盖
`lo` 一侧、`hi` 的复制被部分剪掉，是**不完美的对照**，我没有据此下任何结论。真正决定性的
是 v0=80 与 v1=160 这一对。）

于是只剩两条路，都**不需要额外 BRAM**：

1. **同一个读口在 250 MHz 上分时读两次**（`clk_pix5x` 已由同一个 MMCM 产生，
   TMDS 串行器在用）。每 20 ns 像素周期有 5 个读槽，只需 2 个 ⇒ 通用，任意角度都行。
   代价是地址/数据的节拍对齐与一段匹配延迟。
2. **行缓存**：缩放态 `sy` 在一行内恒定、逐行单调 ⇒ 把两行搬进 2×(512×16) = 2 个 tile
   的行缓存即可，读口压力反而**减半**。但旋转态 `sy` 沿着一行就在变 ⇒ 不适用。

选 1 为主（旋转是本项目卖点，不能只给缩放做插值），把 2 留作缩放态的省带宽路径。
横向的两个抽头**本来就是免费的**：现有读口每拍交出一个 64bit 字 = 4 个 RGB565 像素，
而 `frame_buffer_w64.v:74-82` 只用掉其中 1 个 lane —— 唯一的边界情形是 `sx%4==3`
时 `sx+1` 落在下一个字，靠"多留一个字的前向窗口"解决（128 个 FF，器件只剩 4.5 万个 LUT）。
判据先行：插值的算术与"抽头怎么取"无关，所以先给 `bilin_lerp` 建**行为黄金模型**做逐位对照，
再用 Node 渲染同一定义域的最近邻 vs 双线性，给 PSNR / 最大误差 —— 不拿"报告绿"当结论。

### R11 · 2026-09-22 22:2x– · P0-B 第一步：插值算术核（判据先行，还没接读口）

- **为什么不先动读口**：抽头怎么取（250 MHz 分时调度）是高风险改动，会动帧缓存和流水对齐；
  而"给定 4 个抽头 + 两个小数位怎么算出一个 RGB565"与它**完全解耦**。所以先把算术核
  `src/rtl/process/bilin_lerp.v` 单独钉死，再去碰 plumbing。第一版我写成了一堆占位表达式和
  死逻辑（边想边写），已重写干净 —— 这类半成品不该留在树里。
- **判据（6 条，写 TB 之前先列）**：恒等端点、四角同色对全部 (fx,fy) 恒等、端点色不漂移、
  单调、左右镜像、对**另一种结合顺序**（先纵后横）的黄金模型逐通道比较。
  黄金模型故意不按 RTL 的式子写，否则等于自证。
- **结果**：6 条全过；判据 5 的"最差偏差"是 **0**（不是我给的容差 ±1）——
  横先算和纵先算在整数域是同一个分子、只在最后舍入一次，所以必然逐位相同，
  这个 0 是比 ±1 强得多的结论，也是这次拆分的价值所在。
- **两次失败都是测试台自己的错，不是 DUT 的**，记下来免得以后把这类当战果：
  ① 判据 1 我写成 `fx = k[7:0]^8'd0`，等于让 fx 跟着循环变量走，测出来的 ±1 是我自己造的；
  ② 判据 5 我在 **8bit 域**比较，可 DUT 输出只有 5/6bit 精度，低 3 位早被量化掉 ——
     比较必须落在**输出码域**（5/6bit 场），容差 1 个码才成立。
- **门禁**：L1 **33/33**（`xvlog rtl=62 tb=33`，`SIM DONE pass=33 fail=0`）。
  本增量不碰任何现有模块 ⇒ 没有 L3 必要（`bilin_lerp` 还没被例化，综合不会碰到它）。
- **下一步**：读口调度。`clk_pix5x`（250 MHz，同一 MMCM 已在用）每像素周期给 5 个读槽，
  双线性只需 2 个 ⇒ 不需要额外 BRAM（§12 已实测排除双读口）。要做的是地址预取
  （`sx%4==3` 时要前向多取一个字）、250→50 的采样对齐，以及在 `zoom_mapper` 里
  **把 `frac_x/frac_y` 在旋转态也输出**（现在被 `rot_s1 ? 8'h00` 强制清 0，见 §3.3）。

### R11 追加 · 做硬件之前先算"插值值不值"（`src/host/interp_study.mjs`）

本来打算直接去改读口，但先花十几分钟把"受益面"算了出来 —— 结果**改写了 P0-B 的前提**。

指标定义（必须先说清，否则数字会被过度解读）：拿同一套逆映射，比三种取像素方式
（最近邻 / 双线性 / 2×2 面积平均）对"**理想像**"的 PSNR，而理想像是解析图样在每个
1×1 像素面积上做 4×4 超采样的平均。**这个定义天然奖励平滑**：1px 细线在整数步长下
其"真实反锯齿值"就是 50% 灰，所以 2×2 平均在 inv=256 处能拿 99 dB 而最近邻只有 18 dB。
这不是"糊更好"，是指标口径。写在这里防止以后拿那 99 dB 当战果。

**缩放：增益集中在中段，两个端点严格为 0。** 因为
`fx = ((x−256)·inv mod 256)/256`，inv=256 与 inv=512 时恒为 0 ⇒ **双线性逐像素等于最近邻**。

| 图样 | inv=256 (1.0x) | inv=384 (0.667x) | inv=512 (0.5x) |
|------|------------------|-------------------|------------------|
| 45°细线 | +0.0 dB | **+4.5 dB** | +0.0 dB |
| 竖线栅格 | +0.0 dB | **+4.0 dB** | +0.0 dB |

**旋转：这才是双线性真正有肉的地方**（源坐标除 0/90/180/270 外处处带小数）：

| 图样 | 15° | 30° | 45° | 60° | 75° | 90° |
|------|-----|-----|-----|-----|-----|-----|
| 45°细线 @1.0x | +5.3 | +5.3 | +2.5 | +5.2 | +5.3 | +0.3 |
| 竖线栅格 @1.0x | +5.6 | +5.6 | +5.6 | +5.7 | +5.6 | 0.0（fx≠0 只 5%） |
| 竖线栅格 @0.70x | +5.6 | +5.6 | +5.6 | +5.6 | +5.6 | **+7.6** |

⇒ **P0-B 重新定范围**：插值优先服务**旋转路径**（稳定 +5~+7.6 dB），缩放态作为附带收益
（中段 +4 dB，两端为 0，不是白做但也别指望它改善 0.5x）。0.5x 那端的真正解药是
**面积平均**而不是双线性 —— 那是另一个特性，不混进这一轮。

顺带一个使能的发现：旋转分支的 `frac_x/frac_y` 被 `rot_s1 ? 8'h00` 强制清 0
（`zoom_mapper.v:73-74`），但其实 `rot_xs = xr_m*inv` 的**低 16 位就是小数**，
`fx = rot_xs[15:8]` 直接可取 ⇒ 接上插值不需要额外定点，只是把现在丢掉的那几位留下。

自检也写进脚本了：`inv=256/0°` 的映射必须严格回到原坐标且 fx=fy=0，不成立就
`process.exit(1)`，后面所有表都不许引用 —— 这张表第一版就是因为映射多除了两次 256
而给出 0° 也有 +19.5 dB 的假结论，自检没过就不会被误用。

### R11 追加 2 · 2026-09-22 23:0x · **上一节那张表作废**：理想像的坐标约定错了半个像素

准备按上一节的结论去排读口时，为了把"要不要做纵向"这个代价算清楚，给脚本加了
`hlerp`（只用 fx）/`vlerp`（只用 fy）/`hbox2`（横向等权平均，一个加法零乘法器）三种取法。
加完第一件事就是**再看一眼恒等行** —— 于是看到 `2x2盒 = 99 dB`：

`99` 是 `err ≤ 1e-12` 的显示值，也就是"逐像素零误差"。硬边缘图样上任何滤波都不可能零误差，
所以这不是"盒式更好"，是**测量自己的错**。根因：`makeSource` 把解析图样采在**整数坐标**上
（`a[x] = pat(x)` ⇒ 第 x 个像素代表连续坐标 x），而 `idealAt` 却在 `[sx, sx+1]` 上积分 ——
理想像因此整体平移了半个像素。后果有两层，都不是小数：
① 最近邻白白背了半像素的错位；② **1×1 的"面积平均"在数学上退化成对源栅格做 1×2 盒**，
所以盒式滤波器必然命中满分的假理想 —— 上一节那段"这个指标天然奖励平滑、99 dB 是口径问题"
的解释是**错的**，真实原因就是这半像素。

修法与判据（`idealAt` + `anchor()`）：
- 理想像改为**以 (sx,sy) 为中心、边长 k=inv/256 的面积平均**（本项目只有缩小 ⇒ k≥1，
  子采样密度 `max(4, ⌈4k⌉)` 保持 ~0.5 px 间距）。
- 新增**锚点 + 反向对照**：带限图样在恒等映射下最近邻必须近乎无误差（实测 **45.4 dB**），
  同时故意跑一遍旧的"平移半像素"约定，必须显著更差（实测 **30.0 dB**，低 15.4 dB）。
  两个条件任一不满足就 `exit(1)`，整张表不许引用。这条锚点的作用是**证明测量有牙** ——
  只有正向"应该很好"的自检，换个错约定也可能照样通过。
- 图样补一个**各向同性带限纹理**（12 个方向 × λ=24/8/3 px 的余弦和）。原来四种图样全是
  单一方向的（竖线/硬边沿 y 平移不变，45°线族沿自身方向不变），对它们说"纵向插值没收益"
  是**平凡成立**的，不构成证据。

修正后的归因（完整表：`data/measured/interp_gain_attribution.txt`）：

| 图样 | 缩放 inv=384 | 旋转 15°@1.0x | 旋转@0.70x | 横向占 | 纵向占 |
|------|-------------|---------------|------------|--------|--------|
| 各向同性纹理（最接近真实相机画面） | 34.5→**40.7** (+6.2) | 29.1→**43.3** (+14.2) | 29.4→**46.4** (+17.0) | 22% | 20% |
| 竖线栅格 | 20.0→26.0 (+6.0) | 16.7→34.9 (+18.2) | 17.5→29.6 (+12.1) | 100% | 0% |
| 45°细线 | 18.6→22.2 (+3.6) | 18.6→23.9 (+5.3) | 18.3→24.8 (+6.5) | ~0% | ~0% |
| 竖直硬边 | 0.0 | 36.3→**32.6 (−3.7)** | −1.6 | 100% | 0% |
| 2px 棋盘 | −1.0 | 12.4→**10.9 (−1.5)** | +0.8 | 73% | 73% |

三条能直接改变架构结论的话：

1. **缩放端：增益 100% 来自横向，纵向精确为 0**（所有图样一致）。所以缩放只要横向抽头。
2. **旋转端：横向、纵向各只占 ~20%，剩下 ~60% 只有 2D 组合才拿得到**（各向同性图样）。
   45°细线更极端：单方向抽头甚至比最近邻还差一点。**⇒ 想改善旋转就必须读两行源数据，
   没有"只做横向"这条捷径**（这一条是本次修正换来的，上一节的表看不出来）。
3. 诚实的坏消息：对**硬边缘**和 **2px 棋盘**这两类图样，双线性比最近邻**更差**（−3.7 / −1.5 dB）。
   原因就是 §R11追加 里那个半像素：面积平均的理想边缘在 `sx±0.5`，而双线性在
   `floor(sx)..floor(sx)+1` 之间插 ⇒ 它的过渡带整整晚半像素。屏幕上看不出来，
   但 PSNR 会记账 ⇒ 对外表述只能说"对纹理/细线类内容 +14 dB"，**不要说"全面优于最近邻"**。

**读口账（这条决定了"免费"这个词能不能用）**：`pl_video_top.v:357-379` 现在两窗共用一个
16 bit 读口，每个像素周期恰好一次读（`rd_addr_q <= sy*512 + sx`，`rd_clk = clk_pix`）
⇒ **端口是满的，没有余量**。所以哪怕只做横向（每像素 2 个抽头）也**不免费**，
"横向免费、纵向要钱"这个直觉在**当前 16bit 端口**下是错的。
但 `clk_pix5x`（250 MHz，同一 MMCM，`pl_video_top.v:65-69` 已经在用）每个像素周期给 5 个槽，
双线性需要 4 次读（2 行 × 2 列）⇒ **4 ≤ 5，够**；而且 §12 已经实测过"第三个逻辑读口"会把
帧缓存从 80 个 RAMB36 顶到 160 个（出局），而"同一个口跑快 5 倍"不加任何 BRAM。
两时钟同源同 MMCM、整数 5:1 关系 ⇒ 不是异步 CDC，不需要 FIFO，但读延迟从 1 拍 clk_pix
变成 1 拍 clk_pix5x，**流水配准要按 5 个槽重排**，这是这一轮真正的风险所在。

⇒ **P0-B 最终范围**（配合 §R12 的"旋转只留右窗"）：**只在右半窗做完整 4 抽头双线性**，
读口改跑 `clk_pix5x`；`zoom_mapper` 旋转分支补出 `frac_x/frac_y`（`fx = rot_xs[15:8]`）；
`bilin_lerp` 已单独验过（L1 33/33，判据 5 逐位相同）。**不做**横向-only 的版本来冒充双线性 ——
数字说它只能拿到旋转收益的两成。

### R12 · 2026-09-22 23:1x · 旋转只保留在右半窗（用户新增要求）

**改了什么**：`pl_video_top.v` 删掉左路的 `rotate_mapper` 实例（`u_rmap`）与 `sx_l/sy_l/oob_l`
里的旋转分支，左半窗固定用 `cx_q3/cy_q3`；`rot_on` 只剩两个下游 —— `zoom_mapper.rotate_en`
（右窗内部旋转）与 `proc_pipeline.rotate_active`/`status` 状态位。

**为什么这个改动几乎零风险**：左窗现在走的就是 `rot_on ? sx_map : cx_q3`，而 `rot_on=0`
（angle=0）那条分支今天就在板上跑着、并且是逐像素正确的。本改动只是**把 angle≠0 时左窗的
旋转去掉**，没有引入任何新数据通路、没有动流水深度（`cx_q3` 三级链原样保留 ⇒ 列配准不变），
也没有动读口仲裁。所以 L1 回归的判据是"不新增失败"，而不是"某条新路径通过"。

**顺带的收益**：省掉一整个 `rotate_mapper`（3 级寄存器 + 2 个 512×10 查表 ROM + 2 条
13×10 DSP 路径），以及它带来的 `angle` 跨模块扇出。具体数字等 L3 报告，不猜。

**`rotate_mapper.v` 留在树里**：它仍是 `zoom_mapper` 旋转分支那份数学的参考实现和学习文档
[模块详解 06](../study/03_模块详解/06_旋转与缩放.md) 的讲解对象；未被例化的模块不会进综合。

**待明天上板确认**：按 key1/key2 转角度时，左窗**不动**、右窗转；OSD 角度行仍跟着变。

### R13 · 2026-09-22 23:3x– · SD 卡本地回放（P1）+ PS 发布握手 + 三条解绑/脚本的账

**固件半边**（`src/ps/sd_play.c` + `build/ps_app.mjs`）：裸机只读 FAT32 直接架在 `XSdPs` 上
（BSP 的 libsrc 里没有 xilffs，卡上又是我们自己生成的 8.3 名 + 纯簇链 ⇒ 不需要 FatFs）。
SD 控制器的 DMA **直接写 PL 要读的那块 DDR**（`BASE_ADDR=0x10000000`），PS 全程零 memcpy、
不需要第二块 DDR 双缓冲。命令：`SD` 挂载打印、`PLAY/STOP` 循环回放、`FRAME<n>` 单帧、
`STAT` 一并报 sd/playing/pub。

**RTL 半边（发布握手）**：原来 PL 是"`src_sel=1` 且无链路时每个 frame_start 都搬一次"。
放 FILL 诊断图没问题（DDR 不变），但 SD 回放要 30~60 ms 才写完一帧、PL 16.8 ms 搬一次
⇒ 必然搬到"上半新、下半旧"。改成 **PS 翻转 `gpio_o[18]` 一次 = PL 搬一次**。
握手单独抽成 `src/rtl/util/ps_publish.v`：塞在顶层就只能靠上板看有没有撕裂，
而"偶尔多刷/少刷一帧"和 SD 速度抖动在屏幕上分不开。
台架把两时钟做成 **7 ns / 20 ns 非整数比** + 每次发布加 0~5.9 ns 伪随机相位（LFSR，可复现），
扫 60 次的判据是三次计数相等：`rises=falls=consumes=60` ⇒ **60/60 通过**。
`pend` 是电平不是计数器：两次快速发布会合并成一次 —— 这是**写明的取舍**
（PS 两帧之间至少 30 ms，真合并也只是少刷一帧，不会撕裂），TB 判据 5 就是钉这条的。

**顺手修掉一个真实亚稳态**：`fs_tog` 的触发条件用的是**未同步**的 `src_sel`
（`axi_clk` 域电平被 `clk_pix` 域采样），而同一个文件里 `src_sel_pix`/`src_use` 早就存在。

**三条"错过一次就会留成谜"的账**：

1. `ZOOM0/ZOOM1` 解绑生效（`zoom_en` 从硬绑 `1'b1` 改接 `gpio_o[17]`）⇒
   `set_src.tcl` 原来只写 `0x00010000`，解绑后"上电即呼吸缩放"会**静默消失** ⇒ 改写成 `0x00030000`。
   通则：**解开一个硬绑的常数之前，先查谁在依赖它**（这里依赖者是那条上电脚本）。
2. `build/ps_app.mjs` 第一次"链接成功"产出的镜像 `.text` 只有 **80 字节**。
   根因：抄来的 FSBL `lscript.ld` 用 `ENTRY(_vector_table)`，而那是 standalone 库里的
   绝对/调试符号、不绑定任何输入段 ⇒ `--gc-sections` 认为无人可达，把 `main` 和整个 `XSdPs` 裁光。
   另半个根因：2025.2 的 BSP 把 `_start` 放进 `libxilstandalone.a`、`XTime_GetTime` 放进
   `libxiltimer.a`，都不在 `libxil.a`。⇒ 脚本现在强制检查 `_start`/`main`/`XSdPs_CardInitialize`
   在不在、`.text` 是否 ≥20 KB。**"退出码 0"不等于"能跑的镜像"。**
3. `sim/run_sim.tcl` 以前把 `NO_ASSERT`（一个 PASS/FAIL 都没打印的台架）计入 pass。
   这次写 tb_ps_publish 时正好撞上它 —— 一个什么都不断言的测试可以永远绿。
   现在 `NO_ASSERT` 与 `FAIL` 同等对待。同时记两条工具链事实：
   `xvlog` 对 `.v` **不开 SystemVerilog**（`int`/`++`/`$urandom_range` 全不认），
   `edge` 是 Verilog 保留字不能当端口名（`VRFC 10-8549`），
   以及激励在 `@(posedge clk)` 同一时间步赋值会和被测逻辑抢读 ⇒ 一律沿后 `#1` 再给。

**关于"目的端口过滤"的两秒钟自信，和一次自我更正**：我先在 `udp_rx_parser.v:119` 看到
`{dport[15:8], 当前字节} != UDP_PORT ⇒ 丢弃`，就下结论说记忆里"没有端口检查"是错的并改了记忆。
后来给 skill 文档核对引用时发现：**这个模块除了自己的 tb 之外没有任何例化点**
（`grep udp_rx_parser src/rtl` 零命中），设计真正用的是 `udp_rx.v`，而它里面根本没有端口比对。
⇒ 原记忆是对的，我那一小时的"更正"才是错的，已把记忆改回并补上证据。
教训写进 skill：**看到一个参数化/检查逻辑，先问"它被例化了吗"**；
`grep 模块名` 的命中数比读源码正文更能决定一句话能不能说出口。

**L1**：34/34（新增 `tb_ps_publish`）。**L3 build#13 在跑**，门禁数字见 §5 表格下一行。
**明天上板待看**：SD 是不是 BSP 里那个 SDIO0、实测平均帧率、撕裂是否消失、`ZOOM0/1` 是否真的停得住。


