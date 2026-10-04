// 用途：采纳那笔的文档数字改口（规则表驱动，逐条断言"恰好命中一次"）
// 输入：命令行参数
// 输出：stdout
// 退出码：脚本内无显式 exit ⇒ 随最后一条命令（正常跑完为 0）
// build/r109_rotate_docs.mjs —— 采纳那笔的文档数字改口（规则表驱动，逐条断言"恰好命中一次"）
// 用法：node build/r109_rotate_docs.mjs          只看命中情况，不写盘
//      node build/r109_rotate_docs.mjs --apply  写盘
// 每个 from 必须在指定文件里**恰好出现一次**；MISS 或 MULTI 就报告并跳过（不猜、不放宽）。
// 值全部来自本轮原件：timing_summary.rpt / utilization.rpt / power.rpt / hold_paths.rpt /
// r109_gates.txt（身份行 md5）/ r109_flash_console.txt（刷入时刻 2026-10-03 02:10）。
import fs from "fs";
const APPLY = process.argv.includes("--apply");
const R = [];
const add=(file,from,to,why)=>R.push({file,from,to,why});

const CN="README.md", EN="readme.en.md", CSV="data/metrics.csv", BN="report/background_and_novelty.md";

/* ---------- README.md（首页） ---------- */
add(CN,"**0.721 ns**（板上这一版 r108，2026-10-02 20:54 三步 JTAG 刷入，`bit 25bf35a9900e`；门禁 22 项 21 绿 / 1 红",
        "**0.605 ns**（板上这一版 r109，2026-10-03 02:10 三步 JTAG 刷入，`bit 21227687e925`；门禁 24 项 23 绿 / 1 红","身份+WNS+门禁项数");
add(CN,"`build/r108_gates.txt`、`build/r108_board_verify_console.txt`","`build/r109_gates.txt`、`build/r109_board_verify_console.txt`","出处两件");
add(CN,"`eth_rxc` **0.721 ns**（占它 8 ns 周期的 9.0 %","`eth_rxc` **0.605 ns**（占它 8 ns 周期的 7.563 %","逐时钟 eth_rxc");
add(CN,"`clk_fpga_0` **1.524 ns**（15.2 %）","`clk_fpga_0` **1.238 ns**（12.38 %）","逐时钟 clk_fpga_0");
add(CN,"`clkout0_1` **1.130 ns**（5.65 %）","`clkout0_1` **4.094 ns**（20.47 %）","逐时钟 clkout0_1");
add(CN,"`sys_clk` **14.324 ns**","`sys_clk` **15.289 ns**","逐时钟 sys_clk");
add(CN,"相对余量最紧的是 `clkout0_1`（5.65 %）","相对余量最紧的是 `clkout0_1`（20.47 %，r109 把 OSD 读侧寄存一拍之后）","口径句里的百分数");
add(CN,"落点 u_eth/u_cdc/rgray_s1_reg[7]/C → u_eth/u_lm/full_d_reg/D）**0.035 ns**","落点 u_eth/u_rx_mac/u_crc_rx/crc_data_reg[17]/C → crc_data_reg[25]/D）**0.049 ns**","hold 归属半句+值");
add(CN,"这一格是 **3 级逻辑（CARRY4=2 + LUT6=1）**、走线占这条数据路径延迟的 **60.7 %**","这一格是 **1 级逻辑（LUT6=1）**、走线占这条数据路径延迟的 **80.93 %**","hold 形状");
add(CN,"（`build/hold_paths.rpt`，本轮 r108 布线后重生成）","（`build/hold_paths.rpt`，本轮 r109 布线后重生成）","hold 出处轮次");
add(CN,"`clk_fpga_0` **0.053 ns**、50 MHz 显示域 `clkout0_1` **0.060 ns**、`sys_clk` **0.159 ns**","`clk_fpga_0` **0.052 ns**、50 MHz 显示域 `clkout0_1` **0.053 ns**、`sys_clk` **0.121 ns**","逐时钟 WHS");
add(CN,"**95 tile（67.86 %）/ 14360（26.99 %）/ 8168（7.68 %）/ 19（8.64 %）**","**95.5 tile（68.21 %）/ 14362（27.00 %）/ 8162（7.67 %）/ 19（8.64 %）**","资源四格");
add(CN,"（r108 那一刀的代价：比 r107 多 37 个 LUT、12 个寄存器——把一拍 10 项加法摊成两拍各 5 项要额外的状态与选择逻辑）","（r109 这一刀的代价：比 r108 多 2 个 LUT、少 6 个寄存器——OSD 读侧寄存一拍，把那条 23 级的组合锥换成一级读 + 一级 mux）","代价句");
add(CN,"动态 **2.212 W**（片上合计 2.389 W）","动态 **2.214 W**（片上合计 2.391 W）","功耗两格");

/* ---------- readme.en.md（英文对照） ---------- */
add(EN,"**0.721 ns** (the board now runs r108, flashed at 20:54 on 2026-10-02 by the three-step JTAG chain, `bit 25bf35a9900e`; the 22-item gate check reads 21 green / 1 red",
        "**0.605 ns** (the board now runs r109, flashed at 02:10 on 2026-10-03 by the three-step JTAG chain, `bit 21227687e925`; the 24-item gate check reads 23 green / 1 red","EN 身份+WNS+门禁");
add(EN,"`build/r108_gates.txt`, `build/r108_board_verify_console.txt`","`build/r109_gates.txt`, `build/r109_board_verify_console.txt`","EN 出处两件");
add(EN,"`eth_rxc` **0.721 ns** (9.0 % of its 8 ns period","`eth_rxc` **0.605 ns** (7.563 % of its 8 ns period","EN eth_rxc");
add(EN,"`clk_fpga_0` **1.524 ns** (15.2 %)","`clk_fpga_0` **1.238 ns** (12.38 %)","EN clk_fpga_0");
add(EN,"`clkout0_1` **1.130 ns** (5.65 %)","`clkout0_1` **4.094 ns** (20.47 %)","EN clkout0_1");
add(EN,"`sys_clk` **14.324 ns**","`sys_clk` **15.289 ns**","EN sys_clk");
add(EN,"the tightest relative margin is `clkout0_1` at 5.65 %","the tightest relative margin is `clkout0_1` at 20.47 % after r109 registered the OSD read path","EN 口径句");
add(EN,"landing point u_eth/u_cdc/rgray_s1_reg[7]/C -> u_eth/u_lm/full_d_reg/D) at **0.035 ns**","landing point u_eth/u_rx_mac/u_crc_rx/crc_data_reg[17]/C -> crc_data_reg[25]/D) at **0.049 ns**","EN hold 归属");
add(EN,"that cell has **3 logic levels (CARRY4=2 + LUT6=1)** with routing taking **60.7 %**","that cell has **1 logic level (LUT6=1)** with routing taking **80.93 %**","EN hold 形状");
add(EN,"`clk_fpga_0` **0.053 ns**, 50 MHz display domain `clkout0_1` **0.060 ns**, `sys_clk` **0.159 ns**","`clk_fpga_0` **0.052 ns**, 50 MHz display domain `clkout0_1` **0.053 ns**, `sys_clk` **0.121 ns**","EN 逐时钟 WHS");
add(EN,"**95 tiles (67.86 %) / 14360 (26.99 %) / 8168 (7.68 %) / 19 (8.64 %)**","**95.5 tiles (68.21 %) / 14362 (27.00 %) / 8162 (7.67 %) / 19 (8.64 %)**","EN 资源");
add(EN,"(the price of the r108 split: +37 LUT and +12 registers versus r107, because two 5-term cycles need extra state and select logic)","(the price of the r109 cut: +2 LUT and -6 registers versus r108 - the OSD read side now costs one register stage instead of a 23-level combinational cone)","EN 代价句");
add(EN,"**2.212 W** dynamic (2.389 W total on-chip)","**2.214 W** dynamic (2.391 W total on-chip)","EN 功耗");

/* ---------- data/metrics.csv ---------- */
add(CSV,"全局 setup WNS,核心,0.721,ns,本轮（r107）","全局 setup WNS,核心,0.605,ns,本轮（r109）","csv WNS");
add(CSV,"全局 hold WHS,核心,0.035,ns","全局 hold WHS,核心,0.049,ns","csv WHS");
add(CSV,"Slice LUT 占用,资源,14360（26.99 %）,个,实现后报告（本轮 r107","Slice LUT 占用,资源,14362（27.00 %）,个,实现后报告（本轮 r109","csv LUT");
add(CSV,"Slice 寄存器占用,资源,8168（7.68 %）,个,实现后报告（本轮 r107 比 r106 多 7 个（位图分组的索引与选择逻辑）","Slice 寄存器占用,资源,8162（7.67 %）,个,实现后报告（本轮 r109 比 r108 少 6 个（OSD 读侧寄存一拍换来的）","csv FF");
add(CSV,"Block RAM Tile 占用,资源,95 / 140（67.86 %）","Block RAM Tile 占用,资源,95.5 / 140（68.21 %）","csv BRAM");
add(CSV,"实现后动态功耗,资源,2.212,W,本轮（r107）的实现后报告里 `Dynamic (W)` 那一行（片上合计 2.389 W","实现后动态功耗,资源,2.214,W,本轮（r109）的实现后报告里 `Dynamic (W)` 那一行（片上合计 2.391 W","csv 功耗");

/* ---------- report/background_and_novelty.md（门禁项数两处） ---------- */
add(BN,"22 项机器门禁","24 项机器门禁","BN 项数一");
add(BN,"一条命令跑 22 项门禁","一条命令跑 24 项门禁","BN 项数二");

/* ---------- 跑 ---------- */
const files={};
for(const r of R){ files[r.file]=files[r.file]??fs.readFileSync(r.file,"utf8"); }
const dirty={}; let miss=0, multi=0, done=0;
for(const r of R){
  let s=files[r.file];
  const n=s.split(r.from).length-1;
  if(n===0){ console.log("MISS  "+r.file+"  ["+r.why+"]  找不到：" + r.from.slice(0,52)); miss++; continue; }
  if(n>1){ console.log("MULTI "+r.file+"  ["+r.why+"]  命中 "+n+" 次，不猜：" + r.from.slice(0,52)); multi++; continue; }
  s=s.replace(r.from,r.to); files[r.file]=s; dirty[r.file]=1; done++;
  console.log("OK    "+r.file+"  ["+r.why+"]");
}
console.log("== 规则 "+R.length+" 条：OK "+done+"、MISS "+miss+"、MULTI "+multi+" ==");
if(APPLY){
  for(const f of Object.keys(dirty)){ fs.writeFileSync(f,files[f]); console.log("WROTE "+f); }
  console.log("APPLIED "+Object.keys(dirty).length+" 个文件（写盘）");
} else console.log("DRYRUN 未写盘（改完请用 metric_recheck / doc_currency 复核，别靠眼看）");
process.exit(miss+multi>0?1:0);
