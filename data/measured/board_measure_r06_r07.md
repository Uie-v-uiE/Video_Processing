# R06/R07 板级复验（第五版时序专项之后）· 2026-09-22

被测 bit：`build/system.bit` md5 `7d2cf8ee`（1777758 B）
被测网表差异：`frame_reasm` v5.1（饱和累加改写）+ XDC 拆分（时钟组仅实现阶段生效）
上一版金样：`f5c69ca7`（R05）—— 其 22 轮结果见 `board/README.md` 与 `report/CHANGELOG_V7.md`

## 环境确认（每轮都重跑三件套，因为回读会让 A9 停在复位态）

```
xsdb build/tcl/ps_jtag_boot.tcl   → PS7_INIT 用 BD 生成的 ps7_init.tcl
                                    DDR_ECHO: 10000000: 5A5AA5A5  ✓
vivado -mode batch -source build/tcl/program_pl.tcl
                                    PROGRAMMED xc7z020_1 ← build/system.bit  ✓
xsdb build/tcl/set_src.tcl         GPIO 0x41200000 = 0x00010000  ✓
ping -n 4 192.168.1.10             有回包（TTL=128, 1 ms）⇒ ARP/ICMP 在新 bit 上正常
```

## 判据（`node src/host/measure_v63.mjs`，`--test frameid`，停流后 JTAG 逐 16bit 反解帧号）

| 激励 | bank | 帧号跨度 | 主导帧号占比 | 最新帧 16bit 命中率 | u32 内两 lane 异帧 | 包内六带丢字率 | 连续丢字带 |
|------|------|----------|--------------|---------------------|--------------------|----------------|------------|
| 15 fps × 200 帧（pace 15 MB/s） | 0x10000000 | **198..198** | f198 153600/153600 | **100.0%** | **0/76800** | 0-48 / 48-96 / 96-192 / 192-384 / 384-768 / 768-1392 B **全 0.0%** | 1 段、总 **0** 个 16bit 字、最长 **0**、≥696 段数 0 |
|  | 0x10080000 | **199..199** | f199 153600/153600 | **100.0%** | **0/76800** | 全 0.0% | 同上 |
| 30 fps × 300 帧（pace 15 MB/s） | 0x10000000 | 299..299 | #299 100.0% | 100.0% | 0/76800 | 全 0.0% | 1 段、总 0、最长 0 |
|  | 0x10080000 | 298..298 | #298 100.0% | 100.0% | 0/76800 | 全 0.0% | 同上 |
| **60 fps × 400 帧、`--pace-mpbps 100`（不限速）** | 0x10000000 | 399..399 | #399 100.0% | 100.0% | 0/76800 | 全 0.0% | 1 段、总 0、最长 0 |
|  | 0x10080000 | 398..398 | #398 100.0% | 100.0% | 0/76800 | 全 0.0% | 同上 |

补充读数（15 fps 那轮，逐段明细）：
`按字位置 10 段的新帧占比 w0-9%..w90-99% 全部 = 100`；
`含多个帧号的 16 行组 = 0/19`、`次要帧号占比>12% 的组 = 0`。

## 结论

1. **入包链零回归**：`frame_reasm` v5.1 只改判定量的组织方式，板级三档（含不限速洪水）
   命中率、相位分带、换帧原子性与 R05 金样完全同级（都是 100.0% / 0.0% / 每 bank 恰好一帧）。
2. **R07 的约束拆分为中性**：同一网表、同一实现策略下
   `build/system.bit` 与拆分前的 R06 bit **逐字节相同**（md5 均为 `7d2cf8ee`），
   且 WNS/WHS/端点数/资源/功耗与 R06 报告逐项一致 ⇒ 「综合阶段本来就没有这条约束」的
   预判被证真（若不同就会停下重查，见 `OVERNIGHT_LOG.md` R07 的判据）。
3. **本轮未观测到 #33 帧尾残留**：三档共 6 个 bank 读数的「连续丢字带」统计都是
   `总 0 个 16bit 字`，即上一版金样偶发的「末字高半个 u32 读 0」在这 6 次读数里没出现。
   **这不算"已修复"的证据**：该现象历史上 8 次读数见 4 次，6 次全不出现的概率并不低
   （约 0.5^6 ≈ 1.6% 若发生率真为 50%…，但样本太小且机理未复现），
   且 `tb_v6_ingress_integrity +FULL` 仍不复现 ⇒ 状态维持「已知残留、未修、无可见症状」，
   判据等级不变。
4. 已知工具假警报再次出现并可解释：`ddr_verify.mjs --frameid` 结尾固定打印
   「两个 bank 都没读到有效 wordid 图案」（`src/host/ddr_verify.mjs:249-261`），
   与上面两行的 100.0% 不矛盾 —— 判读要看判据表，不是看最后一行。

## 复算命令

```bat
set PS7_INIT=D:/Xilinx/Prj/pro/Video_Processing/vivado_system/zynq_video_sys.gen/sources_1/bd/design_1/ip/design_1_processing_system7_0_0/ps7_init.tcl
"%VITIS%\bin\xsdb.bat" build\tcl\ps_jtag_boot.tcl
"%VIVADO%\bin\vivado.bat" -mode batch -nojournal -source build\tcl\program_pl.tcl
"%VITIS%\bin\xsdb.bat" build\tcl\set_src.tcl
node src\host\measure_v63.mjs --fps 15 --count 200
node src\host\measure_v63.mjs --fps 30 --count 300
node src\host\measure_v63.mjs --fps 60 --count 400 --pace-mpbps 100
```
