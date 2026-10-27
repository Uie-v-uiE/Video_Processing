# 从 RTL/HLS 核心到可加载的 .bit + .hwh

## 适用范围

你有一个 Verilog 状态机或一个 Vitis HLS 核心，要把它变成 PYNQ 能 `Overlay()` 的设计。
初级组的“逻辑设计、状态机、时序约束、接口协议”在这里，运行时的一切（本包的其余条目）
都建立在这一层产物正确的前提上。

## 使用方法

按顺序做，每步都有可核查的产物：

1. **建工程时选对器件与引脚**。PYNQ-Z2 用官方板文件包与主 XDC `PYNQ-Z2 v1.0.xdc`，
   安装位置是 `<Vivado>/<version>/data/xhub/boards/XilinxBoardStore/boards/Xilinx/`；
   上游构建脚本实际使用的器件字符串是 `xc7z020clg400-1`
   （<https://pynq.readthedocs.io/en/v3.1/overlay_design_methodology/board_settings.html>、
   `boards/Pynq-Z2/petalinux_bsp/hardware_project/pynqz2.tcl`）。
2. **把处理系统放顶层**。ZYNQ7 Processing System 做顶层 PS，Run Block Automation 后
   使能需要的 GP/HP 端口（选型口径见 `references/ps-pl-interface-choice.md`；
   base overlay 只开 HP0/HP2，见 `base.tcl`）。
3. **加入你的核心并正确连时钟**。核心要用 PS 输出的 `FCLK_CLK*` 驱动：`Overlay` 在下载
   比特流前会从 `.hwh` 读取并设置 PL 时钟频率
   （<https://github.com/Xilinx/PYNQ/blob/v3.1/pynq/overlay.py#L422>）。用 PL 引脚晶振或
   内部 MMCM 产生时钟的设计不受这条机制管理，频率与约束要自己负责。
4. **HLS/流接口必须能结束包**。接 `axi_dma` 的 S2MM 时，流生产端要拉 `TLAST`；
   HLS 用 `hls::stream<ap_uint<32>>` 之类写法时要显式 `<< 1` 结束标记，否则
   “the DMA will never complete the transaction”
   （<https://pynq.readthedocs.io/en/v3.1/pynq_libraries/dma.html>）。
5. **按帧大小设置 DMA 长度位宽**。`axi_dma` 的 `C_SG_LENGTH_WIDTH` 默认 14 bit
   （单次最大 `2^14-1 = 16383` 字节）。大帧要么在设计里改宽，要么在软件里分块
   （`assets/templates/ps_app_skeleton.py` 给了对齐安全的分块写法）。
   数据位宽决定对齐要求：`align = C_M_AXI_MM2S_DATA_WIDTH / 8`
   （`pynq/lib/dma.py` 的对齐检查）。
6. **分配地址并导出双工件**。Address Editor 里给每个 AXI-Lite 窗口分配段；
   Generate Bitstream 后，`.hwh` 会随设计生成，**文件名必须与 `.bit` 相同且同目录**
   （<https://pynq.readthedocs.io/en/v3.1/overlay_design_methodology/overlay_design.html>）。
7. **在电脑上先验收产物，再上板**：

   ```bash
   python3 scripts/hwh_inspect.py build/design_1.hwh --format md \
     --require address --require registers --require dma
   python3 scripts/contract_gen.py --hwh build/design_1.hwh --ip <你的实例名> \
     --out-dir build/generated
   ```

   `--require` 是**整份设计**层面的判定；要只对某一个 IP 设门槛，用
   `--ip <实例名>` 把报告与判定一起限定到那个实例。

`hwh_inspect.py` 的读数规则（与 `scripts/hwh_inspect.py` 的 docstring 一致，改动必
要两边同步）：

- **进制看声明，不看位数**。`0x...` 才是十六进制，纯数字串一律按十进制读；只有地址类
  属性（`BASEVALUE / HIGHVALUE / BASEADDR / HIGHADDR / ADDRESS_OFFSET / OFFSET`）按
  PYNQ v3.1 自己的 `int(x, 16)` 口径声明为十六进制。所以 `FREQ="100000000"` 是一亿，
  不是 `0x100000000`（旧实现按“≥5 位就当十六进制”猜基数，把 100 MHz 报成 4294.967 MHz）。
- **频率单位由字段名声明，不由量级猜**。以 `MHZ` 结尾的字段（`PCW_ACT_FPGA*_PERIPHERAL_FREQMHZ`、
  `PSU__CRL_APB__PL*_REF_CTRL__FREQMHZ`）是 MHz；以 `HZ` 结尾的以及 `FREQ` / `CLKRATE`
  是 Hz——`.hwh` 对非 FCLK 的时钟源就是直接写 Hz，例如 `PORTNAME="clk" FREQ="100000000"`
  = 100 MHz。换算规则写在代码里：MHz 字段 `hz = 值 × 1e6`，Hz 字段 `mhz = 值 / 1e6`。
  若按声明单位算出的值落在本包认可的 PL 时钟带 1–1000 MHz 之外，就说明“量级与声明单位
  不一致”，工具**不选边**：该时钟报 `mhz: null`、`unit: "ambiguous"` 并附各候选读数
  （Hz/kHz/MHz 各等于多少 MHz），`problems` 里给一条 `FREQ-UNIT-AMBIGUOUS`，
  且 `--require clocks` 判 missing。
- **地址段的归属**。`MEMRANGE`/`SEGMENT` 的 `INSTANCE` 可能是总线路径写法
  （`video_kernel_0/S_AXI`、`/design_1_i/video_kernel_0/S_AXI`）；工具把它归到路径里
  提到的真实 IP 实例，并在每个地址段记录原始属性文面 `instance_attr` 与形式
  `instance_attr_form`（`plain` / `path` / `owner` / `path-unresolved` / `unresolved`）。
  归不到任何实例的路径不会被硬塞给某个实例：它带 `ADDRESS-PATH-UNRESOLVED` 进
  `problems`，`--require address` 对这种设计判 missing。
- **缺的就是缺的**。`<FIELD>` 没有 `BIT_OFFSET`/`BIT_WIDTH` 时报 `null/null`，寄存器标
  `field_ranges: "unresolved"`（md 报告里写 `fields: unresolved`）并给
  `FIELD-NO-BITRANGE`，绝不补 0/1 这类编造的位段；`contract_gen.py` 对这种寄存器仍出
  偏移常量，但不出位掩码。`memtype` 只认真正的 `MEMTYPE` 属性（本级或所属 `ADDRESSBLOCK`），
  否则为 `null`——`ISVALID` 不是内存类型。

## 失效条件

- `hwh_inspect.py --require registers` 报 `missing=registers`：说明 `.hwh` 里没有寄存器
  说明信息。常见于只有 AXI-Lite 地址段、但没有寄存器描述的 IP。此时**不要猜偏移**：
  以你的 IP 寄存器手册为唯一来源，把基址取自 `hwh_inspect` 的地址段，偏移与位段自己
  写成常量并在报告里注明来源；`register_map` 这条路径不可用是设计属性，不是 bug。
- 只有 `.bit` 拷到板上：`Overlay()` 会失败或 IP 驱动绑不上（见
  `references/overlay-load-and-verify.md`）。
- 用 Vivado 2025.2/2026.1 生成而板上镜像是 v3.1（2024.1 构建）：属性名可能改动，所以
  `hwh_inspect.py` 同时接受 `MEMRANGE / ADDRESSBLOCK / SEGMENT` 三种拼写；第 7 步在交作品
  之前必须对你的真实 `.hwh` 跑一次并让 `--require` 通过。
- 地址段重叠或偏移不是 4 的倍数：`hwh_inspect.py` 会在 `problems=` 里点名
  （`ADDRESS-OVERLAP`、`REG-UNALIGNED`），这类问题在上板前就能修，比现场便宜得多。
- `problems` 出现 `FREQ-UNIT-AMBIGUOUS`：这个时钟的量级配不上字段声明的单位，报出来的
  是 `mhz: null` 加候选读数。此时**不要挑一个看起来顺眼的**：回 Vivado 看该端口的实际
  时钟源（FCLK 就核对 `PCW_*_DIVISOR*`，外部晶振/MMCM 就在约束里自己写明），把它当常量
  写进文档并注明来源。
- `problems` 出现 `FIELD-NO-BITRANGE` 或 `ADDRESS-PATH-UNRESOLVED`：位段与归属都要人工
  核对，工具不会替你补。数组型寄存器（`REG_coef[0]` 这类名字）另见
  `references/register-map-from-hwh.md`。

## 已验证效果

```bash
python3 scripts/hwh_inspect.py assets/fixtures/hwh/z2_video.hwh --require address,registers --format json
python3 scripts/hwh_inspect.py assets/fixtures/hwh/z2_minimal.hwh --require address,registers --format json
python3 scripts/hwh_inspect.py assets/fixtures/hwh/alt_board.hwh --require address,registers --format json
python3 assets/fixtures/hwh/hwh_fixture_check.py
```

三份样本的判定行（逐字来自上面的命令，`missing=none` 即退出码 0）：

```
hwh_inspect: checked=36 instances=7 problems=5 ... missing=none
hwh_inspect: checked=23 instances=4 problems=3 ... missing=none
hwh_inspect: checked=29 instances=6 problems=4 ... missing=none
```

样本契约检查器对本条目的改动没有任何反应（`hwh_fixture_check.py` 依旧 87 项全绿）。
同一份工具对三份不同形态的设计给出各自事实：Z2 视频样本里 `axi_dma_0` 报
`align=4 max_transfer=16383`，Z2 精简样本报 `align=8 max_transfer=8388607`，非 Z2 样本报
`align=16 max_transfer=67108863`。三份的 `problems` 都只有 `DUPLICATE-RANGE-SPELLING`
（同一地址段被 `MEMRANGE` 与 `SEGMENT` 各写一遍，先去重再判重叠）与
`MEMORY-RANGE-PRESENT`（PS 的 DDR 段出现在地址图里，提醒它不是寄存器基址）。

读数规则的三条修改是用一个**不随包发布**的合成 `.hwh`（放在包外临时目录，避免样本数
变化让别处的 `checked=` 计数过期：它同时含 `PORTNAME="clk" FREQ="100000000"`、
`FREQ="10000"`、`INSTANCE="video_kernel_0/S_AXI"` 与一个没有 `BIT_OFFSET` 的 `FIELD`）
对照出来的：修改前它报 `mhz: 4294.967`、`mhz: 0.066`，地址段挂在孤立键
`video_kernel_0/S_AXI` 上，缺失的位段被编造为 offset 0 / width 1，而
`--require address,clocks` 照样退出码 0；修改后同一文件报 `clk = 100.0 MHz`
（`unit: "Hz"`）、`slow_clk` 为 `mhz: null` + `unit: "ambiguous"`（候选 `kHz -> 10.0 MHz`）、
地址段归到 `video_kernel_0` 并记 `instance_attr_form: "path"`、该寄存器
`field_ranges: "unresolved"`，`problems` 多出 `FREQ-UNIT-AMBIGUOUS`、
`FIELD-NO-BITRANGE` 与 `ADDRESS-PATH-UNRESOLVED`（归不到实例的
`INSTANCE="design_1_i/pipeline_0/S_AXI"`）三条点名；把该文件删到只剩这两个不可用的事实时，
`--require address,clocks` 退出码 1、`missing=address,clocks`。
**本条目不含 Vivado 操作步骤的实测**：这台机器上没有 Vivado，第 1-6 步是按官方文档
（UG901/UG904/UG1399 与 PYNQ v3.1 overlay 设计方法学页）写的流程约束，凡未跑过的都不写成
“已验证”。只有第 7 步的命令与本节的输出是实测过的。

## 来源

PYNQ v3.1 Overlay Design Methodology 与 Board Settings 页、`pynq/overlay.py`、
`pynq/lib/dma.py`（tag v3.1）；赛题指南推荐的 UG901 / UG904 / UG1399 / UG949；
AMD HLS 学习案例 <https://xilinx.github.io/xup_high_level_synthesis_design_flow/>。
