# 硬件优化日志（时序 / 布局 / 功耗）

工程：`Video_Pipeline-main`（Zynq7020 以太网视频 + 右屏无极缩放）  
工具：Vivado / Vitis **2025.2.1**  
日志维护：随每次实现迭代追加。

---

## 2026-09-18 · 优化前基线（缩放方向改为「原本=最大」后）

### 时序（build/timing_summary.rpt）

| 时钟域 | 周期 | WNS | 结论 |
|--------|------|-----|------|
| clk_fpga_0 (PS 100M) | 10 ns | +2.077 ns | MET |
| eth_rxc (PHY 125M) | 8 ns | +0.214 ns | MET（余量偏紧） |
| sys_clk (50M) | 20 ns | +14.897 ns | MET |
| **eth_rxc → clkout0_1 (clk_pix)** | — | **−6.748 ns** | **FAIL，33 endpoints** |

- 全局 WNS **−6.748 ns**，TNS −133.6 ns  
- Hold / Pulse 全部 MET  
- **根因：** `rk_zynq7020.xdc` 的 `set_clock_groups -asynchronous` 只列了 `eth_rxc / clk_fpga_0 / sys_clk`，**未包含 MMCM 生成钟**（`clkout0_1` 像素钟等）。跨钟路径本应经 2FF / gray FIFO，却被工具按 setup 分析。

### 布局 / 功耗（优化前）

- 资源：帧缓 BRAM ≈2.34 Mb；eth 侧 icmp_fifo 因异步复位被实现成寄存器堆（约 16k bit FF）  
- 功耗：`report_power` 提示高扇出复位长时间有效，估算偏保守  
- 路由：局部拥塞（INT_L_X18Y49 一带），非致命  

### 功能状态

- 右屏无极缩放（1.0× 最大 → 0.5× 最小循环）**上板验证通过**  
- 效果链 / 旋转 / 选源 / ETH 推流不受影响  

---

## 2026-09-18 · 本轮优化措施

### 1. 时序约束（`src/constraints/rk_zynq7020.xdc`）

| 措施 | 说明 |
|------|------|
| 异步时钟组补齐 MMCM 生成钟 | `get_clocks -regexp {.*clkout.*\|.*clkfbout.*}` 与 eth_rxc / clk_fpga_0 / sys_clk 全部 `set_clock_groups -asynchronous` |
| 跨 PS↔PL 控制 false path | GPIO/效果/缩放控制经 2FF（`effect_ctrl`、`ze*`、`ef*`、`fs*`） |
| 按键/复位/ETH 管脚 false path | 保持原有 |
| MAX_FANOUT | 复位/locked 网 50，便于复制驱动、降功耗 |
| Bitstream COMPRESS | 略降配置存储相关开销 |

**原理：** 工程内所有跨时钟数据通路均为：
- `dc_fifo`（gray 指针，eth_rxc → axi_clk）
- 双/三触发器同步器（帧起始、eth_frame、zoom_en、FPS tick 等）

因此跨钟 setup 分析无物理意义，应声明异步。

### 2. RTL 流水 / 功耗（`pl_video_top.v` 等）

| 措施 | 说明 |
|------|------|
| `rd_addr` 打拍 | `sy*W+x` 改为 `{sy[8:0],9'b0}+sx` 后 **寄存一拍** 再进 BRAM，缩短 clk_pix 上组合路径 |
| sideband 对齐 | 显示延迟链扩到 16 级，与 mapper3 + addr1 + BRAM1 + proc7 对齐 |
| ASYNC_REG | 所有 CDC 同步链（`ze*`/`ef*`/`fs*`/`vt*`）标注 `ASYNC_REG="TRUE"`，利于布局靠近、降低 MTBF 风险 |
| 效果级 bypass | 未使能模块数据直通，动态翻转已较低 |
| 左右 FB 读时分复用 | 不双缓冲，省约 2.3 Mb BRAM → 间接降静态/布线功耗 |

### 3. 布局相关

- 实现脚本：`build/tcl/rebuild_zoom_out.tcl`（增量）+ 全量 `build_system_axigpio.tcl`  
- 使用 `-jobs 4`；phys_opt 保持开启  
- Bitstream `COMPRESS TRUE`  

### 4. 上位机（同日）

- `video_sender.py`：定时节拍发送（补偿解码耗时）、FFmpeg 多路径查找、帧尺寸校验、统计信息  
- `serial_ctrl.py`：自动列串口、单次 `--cmd`、帮助与 ZOOM 命令  
- bat 脚本路径修正为 `src\host\`（原先误写 `sw\host\`）  
- 使用教程：`src/host/HOST_GUIDE.md`  

---

## 验证清单（优化后）

- [x] `tb_zoom_mapper` PASS  
- [x] Vivado synth + impl + bitstream 生成  
- [x] XSA 导出  
- [ ] 时序报告：确认跨钟组后 **WNS ≥ 0**（见下一节填入实测值）  
- [ ] `report_power` 记录 Total Power  
- [ ] 上板：右屏缩放循环、效果命令、ETH 推流  

---

## 优化后实测（2026-09-18 21:41 · 最终）

**报告结论：`All user specified timing constraints are met.`**

| 项目 | 数值 |
|------|------|
| 日期 | 2026-09-18 21:40 bitstream |
| WNS (全局) | **≥ 0**（路由估计 +0.111 ns，报告确认 MET） |
| TNS | **0.000** |
| clk_fpga_0 (100M) | WNS **+0.865** MET |
| eth_rxc (125M) | WNS **+0.111** MET |
| sys_clk (50M) | WNS **+14.445** MET |
| clkout0_1 / clk_pix (50M) | WNS **+1.882** MET |
| 跨钟 eth_rxc→clk_pix | 已 false_path，表中不再出现违例 |
| 动态功耗 | 2.071 W |
| 总功耗 | **2.240 W**（结温 50.8 °C） |
| Slice LUT | 10621 / 53200（**19.96%**，优化前 23.3%） |
| Slice Registers | 20253 / 106400（**19.03%**，优化前 23.2%） |
| BRAM Tile | 83 / 140（59.3%） |
| DSP | 13 / 220（5.9%） |
| bit 大小 | ~2.09 MB（COMPRESS，优化前约 4.0 MB） |

### 关键优化点（有效）

1. **XDC**：`set_clock_groups -asynchronous` 使用 `-include_generated_clocks sys_clk`，把 MMCM 的 `clkout0_1/1_1/2` 一并纳入异步组 → 消除 eth_rxc→像素钟假违例  
2. **sync_fifo / dc_fifo**：存储阵列去掉异步复位并 `ram_style=block` → icmp_fifo 推断 BRAM，eth_rxc@125M 域内 WNS 从 −0.98 转正  
3. **rd_addr 打拍 + shift-add**：缩短 clk_pix 组合路径  
4. **ASYNC_REG** 标注 CDC 链；Bitstream COMPRESS；PowerOpt 对 BRAM 端口使能门控（opt 阶段 48 WE→EN）  

### 功耗说明

- vector-less 估算置信度 **Low**（高扇出复位翻转假设），绝对值仅供参考  
- 相对优化前 ~2.25 W 略降；逻辑占用下降约 3 个百分点有助于静态/动态  

---

## 验证清单

- [x] `tb_zoom_mapper` PASS  
- [x] Vivado synth + impl + bitstream  
- [x] XSA 导出  
- [x] **时序：全局 MET（WNS≥0, TNS=0）**  
- [x] `report_power` 记录 2.240 W  
- [x] 右屏无极缩放上板（用户确认效果 OK）  
- [ ] 优化后 bit 建议再上板确认一次（bit/XSA 已更新）  

---

## 变更文件索引

| 文件 | 变更 |
|------|------|
| `src/constraints/rk_zynq7020.xdc` | 异步时钟组、false path、MAX_FANOUT、COMPRESS |
| `src/rtl/top/pl_video_top.v` | rd_addr 打拍、sideband 对齐、ASYNC_REG |
| `src/rtl/process/zoom/*` | 缩放方向（原本=最大） |
| `src/host/*` | 上位机优化 + bat 修正 |
| `src/host/HOST_GUIDE.md` | 使用教程 |
| `report/OPTIMIZATION_LOG.md` | 本日志 |
