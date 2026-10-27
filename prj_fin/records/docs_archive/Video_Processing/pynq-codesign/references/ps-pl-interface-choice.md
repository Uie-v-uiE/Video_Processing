# 软硬件划分与 PS/PL 接口选择

## 适用范围

决定“这段算法放 PS 还是 PL”“PL 里的 IP 用什么端口接 PS”“要不要 DMA”。这是初级组
最常失分的地方：评委看的是**划分依据**，不是结果漂亮。换题目、换板卡都能用同一条
推理链，因为它是按端口与事务形状推的，不是按某个作品的模块名推的。

## 使用方法

1. 先列端口事实（Zynq-7000，PS↔PL 共 9 个 AXI 接口）：
   PL 侧 4×AXI Master HP、2×AXI GP（主）、2×AXI Slave GP（从）、1×AXI Master ACP，
   另有 64 根 PS→PL GPIO 线
   （<https://pynq.readthedocs.io/en/v3.1/overlay_design_methodology/pspl_interface.html>）。
   官方选型口径：控制与状态用 `MMIO`（GP 从端口，单 32 bit 事务、无 burst）；
   数据量大或性能关键时“用 HP 端口 + DMA IP + `pynq.lib.dma.DMA` 更合适”。
   PYNQ-Z2 base overlay 实际只开了 HP0 与 HP2（`base.tcl` 的
   `PCW_USE_S_AXI_HP0 {1} / HP2 {1} / HP1 {0} / HP3 {0}`），
   ACP 关；所以“我有 4 个 HP”在设计里没开就是没有。
2. 做一次带宽账再划分。初级组够用、且评委能一眼看懂的算法（全部量都要写明假设）：
   - 需求：`bytes_per_frame × frames_per_second × 方向数`。
     例：720×1280×3 B × 60 fps × (进+出) = 331 776 000 B/s ≈ **331 MB/s**（单向各 166 MB/s）。
   - 供给：单个 HP 端口 64 bit @ 100 MHz 理论 `8 B × 100 MHz = 800 MB/s`。
     base 设计的 `PCW_ACT_FPGA0..3_PERIPHERAL_FREQMHZ = 100 / 142.857132 /
     200 / 100` MHz（`base.tcl`）；板卡预设的 FCLK3 是 160 MHz，与 base 实际
     不同，取数一律以 `PCW_ACT_*` 为准。
     端口宽度不是系统带宽：800 MB/s 是 HP 端口的理论值，数据还要走
     S_AXI_HP→互联→DDR 控制器。本包**没有实测**这条通路（无板），也**不把**
     `PCW_UIPARAM_DDR_BUS_WIDTH` 当成 HP 带宽的折减系数——那是两个不同的量，
     写进同一个算式就是编数。要把它当证据，就在板上跑一次纯搬运的 DMA 吞吐测试
     （固定缓冲、`start()`/`wait()` 成对、计时 `nbytes/秒`），把命令与原始输出贴进报告。
   - 结论口径：41% 这个数是**把进出两向都挤在同一个 HP 端口**上的最坏假设（166 MB/s 单向
     时是 21%/端口）；写报告时必须把这条端口映射假设写明。它是理论峰值，未计 AXI 握手
     开销、突发长度上限与 DDR 刷新，实测另行测量；把 41% 当成“还有一倍余量”是常见误判。
   - 若需求超过单端口供给，先减数据量（PL 内部级联、只回传结果、位宽打包）而不是加端口。
3. 划分决策写成三段论，直接进设计报告：
   - 进 PL 的理由必须是**实时性、并行度、带宽、接口扩展或控制可靠性**之一
     （这五项就是评分口径）；写不出来就留在 PS。
   - 留在 PS 的理由：分支密集、数据结构不规则、需要文件/网络/协议栈、开发成本。
   - 边界写成契约：基址、偏移、位段、缓冲格式、完成判定方式、错误处理。契约由
     `scripts/contract_gen.py` 从 `.hwh` 生成，人和代码用同一份。
4. 检查自己有没有把控制通路当数据通路：

   ```bash
   python3 scripts/api_lint.py src/ps_app.py     # E005 = 寄存器循环写 / length>8
   ```

## 失效条件

- 端口在 Vivado 里没勾选、或地址编辑器没分配：`hwh_inspect.py` 读不到 `ADDRESSBLOCK`
  （`--require address` 退出 1），此时任何带宽数都是空谈。
- 时钟不在 `PCW_*FPGA*` 里（用了 PL 上独立晶振或 MMCM 输出）：按 FCLK 算的带宽与约束都
  不适用，需要按 `create_clock` 的周期重算，且跨时钟域要单独处理。
- 用 UltraScale+/Versal 时端口模型不同（NoC、HPM/HPS/LPM 命名），本条目的端口清单要换成
  对应器件手册；划分推理链仍可用。
- 数据量估算里含有未实测的“大概能跑”：这条目不允许把假设写成结论，必须标注为理论值。

## 已验证效果

```bash
python3 scripts/hwh_inspect.py assets/fixtures/hwh/z2_video.hwh --format md
python3 scripts/hwh_inspect.py assets/fixtures/hwh/z2_minimal.hwh --format md
python3 scripts/hwh_inspect.py assets/fixtures/hwh/alt_board.hwh --format md
```

同一份脚本对三份设计报出各自的地址段、寄存器与 DMA 上限（14/23 位长度域、
32/64 位数据宽得到不同对齐与单次上限），说明划分输入不绑定某一块板；`assets/fixtures/hwh/hwh_fixture_check.py` 把“两份设计的
限制必须不同”本身写成断言，防止样本被复制成同一个。
方法可复算（数值取自 `base.tcl` 与 `PYNQ-Z2 v1.0.tcl` 预设），但没有上板实测的 MB/s
一律是理论值。

## 来源

`pspl_interface.html`（v3.1）、`boards/Pynq-Z2/base/base.tcl`（HP/GP/ACP 勾选）、
`PYNQ-Z2 v1.0.tcl` 板卡预设（DDR 位宽、FCLK 频率、50 MHz 晶振）、
`mmio.html` 与 `dma.html` 的选型建议。
