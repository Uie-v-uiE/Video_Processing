# S9 · 用「逐字反解帧号 + 包内相位」定位丢字机理

## 适用场景
- 数据流写进内存/DDR，肉眼只看到「花屏 / 拖影 / 黑纹」，但**不知道是不是在丢数据、丢在哪一级**。
- 任何「PC → 板卡 → 内存 → 显示/计算」链路都适用（视频、点云、ADC 流、DMA 采集）。
- 只判**数据完整性**；画质类问题（缩放走样、色彩、抖动）不适用（`report/AI_COLLABORATION.md` §6）。

## 使用方法
1. **图案必须逐帧变化**。本项目用 `frameid`：第 `w` 个 64bit 字的每个 16bit lane 写
   `value = (w + n) & 0xffff`（`w`=字序号、`n`=帧号，`src/host/video_sender.mjs:73`）。
   回读反解 `n_implied = (value - w) & 0xffff` ⇒ 每个字「来自第几帧」直接可读。
   恒定图案（`--test wordid`，值=字号）只能验地址映射，**结构上发现不了逐帧丢字**
   ——本工程就是这样误判过一轮（`report/AI_COLLABORATION.md` §2.1）。
2. **先停流再回读**。一次回读要几秒，边推边读会让每个地址段读到不同时刻的帧，统计全废
   （症状：反解出的帧号跨度达几十帧，实测 130..152，`report/AI_COLLABORATION.md` §2.3）。
   现成的一站式脚本已按「发完再读」写：`node src/host/measure_v63.mjs --fps 15 --count 200`。
3. 手工分步（同一判据的三个出口）：
   ```
   node src/host/video_sender.mjs --fps 15 --count 200 --test frameid --pace-mpbps 15
   node src/host/ddr_verify.mjs --frameid      :: 回读两个 bank 并落盘 data/measured/ddr_dump.out
   node src/host/ddr_stale.mjs                 :: 包内相位分带 + 最长连续丢字带 + 半字错帧
   node src/host/ddr_holemap.mjs --bank 10000000 --payload 1392
   ```
4. 把丢字按**三个维度**展开（`src/host/ddr_stale.mjs` 直接输出）：

   | 维度 | 指标 | 指向的机理 |
   |------|------|-----------|
   | 包内相位 | 丢字率 vs 字节偏移分带（0–48 / 48–96 / … / 768–1392 B） | 呈**固定台阶** ⇒ 下游**平均排空速率**跟不上（加深缓冲无用） |
   | 空间连续性 | 连续丢字带长度分布、最长带 | 一条几百字长带 ⇒ 某窗口端口被完全占死；≥696 字（整包）⇒ 前端整包丢失 |
   | 粒度 | 同一 32bit 内两个 16bit 是否属于不同帧 | 高比例 ⇒ 丢在 16bit 粒度（写侧门控/CDC），不是整字丢弃 |
5. 判「换帧是否原子」：看每个 bank 的**帧号跨度**。健康 = 每个 bank 恰好一帧
   （乒乓下相邻两帧分属两 bank，`0x10000000` / `0x10080000`）；混十几帧 = 提交/切换逻辑有问题。

## 已验证效果
- 这套判据把「红块撕裂 + 拖影 + 黑横纹」从显示侧问题改判为入包链丢字。
  修复前实测：最新帧只占 **42~52%**、包内 0–48 B 丢 **6.7%** / 48 B 之后丢 **54~64%**、
  u32 半字错帧 **14296/76800 = 18.6%**（`report/V6_BOARD_MEASUREMENT.md` §4.1 末行）。
- 定位到根因 = `axi_frame_saver64` 逐字等 B 响应，在途深度 1 ⇒ HP0 RTT≈40 拍时上限
  **20 MB/s**（`report/MODULES.md` §「为什么根因在 axi_frame_saver64 的写通道」）。
  流水化（`OST=8`）后 15/30/60 fps 全部 **100.0%**、各带 **0.0%**、半字错帧 **0/76800**
  （`report/ISSUES.md` §31）。
- 「深度无用」不是观点而是两次失败：CDC 512→8192 + 反压，仿真 100%、板上仍 **42~52%**
  （`report/ISSUES.md` §30）。本夜的定量版：要吃下 V-blank 拷贝窗口的 672 µs 需要 ≈84 个
  BRAM tile，全片才 140 ⇒ 结构上不可能（`report/OVERNIGHT_LOG.md` U3）。
- 同一套判据在仿真里可复现：`sim/tb_v6_pingpong.v` 里端口被独占 N 拍 ⇒ 丢字起始位置恰好等于
  打包器 FIFO 深度 **512**（`report/AI_COLLABORATION.md` §3 第 1 轮）；
  `sim/tb_v6_ingress_integrity.v +FULL` 221 包整帧 `38400/38400`（`sim/results/regression_v6.txt` 头部说明）。
- 判据落地成三个可持续复用的脚本，换题目只改 `WORDS / PAYLOAD` 两个常数
  （`src/host/ddr_stale.mjs:20-22`、`src/host/ddr_holemap.mjs:21`）。

## 失效条件
1. 无法回读内存的平台（无 JTAG、无调试端口）：判据失效，只能退化为板内自检 + 计数寄存器
   （需另造可观测出口）。
2. **D-Cache 会污染回读**：`mrd` 走 A9 端口，开着缓存时同一块 DDR 三次读出三组数
   （`report/AI_COLLABORATION.md` §2.2）。必须先 `rst -processor` 且**绝不再 `con`**
   （A9 从复位向量重跑会经 boot ROM 把卡里的旧 bitstream 刷回 PL）。
3. 回读会把 PS 停住 ⇒ 之后任何复测前必须重跑
   `build/tcl/ps_jtag_boot.tcl` → `build/tcl/program_pl.tcl` → `build/tcl/set_src.tcl` 三件套，
   否则量的是「PS 不跑」的工况（`data/measured/board_measure_r06_r07.md` §环境确认）。
4. 载荷不是 8 字节整数倍时，「包内相位」会与打包器的部分字状态混在一起 ⇒ 先解决对齐再用本判据
   （1396 B 的签名见 `report/ISSUES.md` §29）。
5. `node src/host/ddr_verify.mjs` 结尾固定打一行「两个 bank 都没读到有效 wordid 图案」
   （`src/host/ddr_verify.mjs:260`），它与同一轮统计行里的 100.0% **不矛盾**，是文案位置错的假警报
   （`data/measured/board_measure_r06_r07.md` §结论 4）⇒ 判读看判据表，不看最后一行。
6. 这套判据会「看不见自己不覆盖的工况」：帧尾那处残留（`+0x4AFF8` 高半个 u32 读 0）历史上
   8 次读数见 4 次，但 19 轮 + 6 轮基线回读一次没出现 ⇒ 本判据**没能**给出板级区分力，
   相关修复的证据等级只到「机理 + 仿真双向判据」（`report/OVERNIGHT_LOG.md` §「L4 执行」）。
