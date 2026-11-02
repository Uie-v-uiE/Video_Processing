# 时序优化分析（待你补充）

> 此文件占位。请用 Vivado 打开工程后导出数据填入。**报告/答辩必用。**

## 1. 工程时钟

| 时钟 | 目标频率 | 来源 |
|------|----------|------|
| clk_pix | 50 MHz | MMCM OUT0 |
| clk_pix5x | 250 MHz | MMCM OUT1 |
| axi_clk (FCLK_CLK0) | 50 MHz | PS |
| sys_clk | 50 MHz | 板载 |

## 2. 导出命令

```tcl
open_project <your>.xpr
report_timing_summary -delay_type min_max -report_unconstrained \
  -check_timing_verbose -max_paths 10 -input_pins \
  -file output/timing_summary.rpt
report_utilization -file output/utilization.rpt
report_clock_utilization -file output/clock_util.rpt
```

## 3. 结果表（自行填）

| 指标 | 值 |
|------|-----|
| WNS (setup) | |
| TNS | |
| WHS (hold) | |
| 失败端点数 | |

## 4. 关键路径说明（自行填）

路径 1：  
- 起点 / 终点：  
- 延迟构成：  
- 优化手段：插拍 / 改约束 / 降频 / 逻辑重构  

## 5. 本工程已做过的优化（可写进报告）

1. **720p@75 MHz 时代** WNS 约 −1.3 ns，主要卡在旋转坐标运算。  
2. **`rotate_mapper` 流水线化**：把乘加与加法拆拍，缩短组合逻辑。  
3. **改用 1024×600@50 MHz**：像素钟下降，VCO 750 MHz，时序余量充足（系统工程 WNS≥0）。  
4. 效果链各模块独立 `bypass`，避免长组合串。

## 6. 资源占用（导出后填）

| 资源 | Used | Available | % |
|------|------|-----------|---|
| LUT | | | |
| FF | | | |
| BRAM | | | |
| DSP | | | |

## 7. 结论（自行写）

- 是否满足 50 MHz 收敛  
- 若提分辨率/提频，瓶颈在哪  
- 下一步若做 720p/1080p 的计划  
