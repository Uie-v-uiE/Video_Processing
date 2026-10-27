# 取证清单：每条断言的出处、冲突与未证实项

## 适用范围

需要核对本包任何一条事实性断言时；写设计报告的“技能包提炼过程”一节时；评委或陌生队伍质疑某个 API/地址/性能说法时。本文件也是“哪些还没证实”的清单，避免把未取证的内容当结论使用。

取证日期 2026-10-10。除注明外，文档一律取 PYNQ **v3.1 “Carlisle”** 分支，源码取
`Xilinx/PYNQ` 的 tag `v3.1`。评委或陌生队伍可逐条打开核对。

### 行号锚点的可靠性（本包的一处自我修正）

本文件多数源码引用带 `#L123`。行号是最脆的一种引用：换 tag、换统计口径、甚至同一文件在
不同抓取方式下的行数差异，都会让它指到错误的位置——而**指错行的引用比没有引用更糟**，
因为读者落到不相干的代码上就会开始怀疑整张表。

2026-10-10 复核时，两处行号在两次独立读取中不一致，已改为「文件 + 文件内搜索串」的形式，
并在 `scripts/api_surface.json` 的 `anchor_policy` 里留了同一说明：

- `Root permissions required.`（`pl_server/embedded_device.py`，异常类型是
  `EnvironmentError`）：旧引用 `#L582` / `#L583` 两个都留过，互相矛盾，现按内容定位。
- 2.x 风格 `DMA(...)` 四位置参数的报错（`lib/dma.py`）：旧引用 `#L583`，另一读取给出 287。

同一次复核还纠正了一条**自称逐字、其实被截断**的错误串：完整文本是
`You appear to want the old DMA driver which has been deprecated and moved to pynq.lib.deprecated`，
后半句正好指出旧驱动的去向，省略号把它抹掉了，属于会把人带偏的引用。桩件、`api_surface.json`
与本文件现在都写全串。

其余未复核出矛盾的行号保留原样，但**默认按“搜索串优先”的方式使用**：打开文件后请用
`grep -n` 或页面搜索定位，不要把行号当承诺。取数通路本身两条都走得通（代理的网页抓取与
`curl` 直取 raw.githubusercontent 都返回过 200/404），所以早前写的“开发机无外网、无法再核”
是错的，已在此更正——行号的问题不是取不到，而是换 tag 或改统计口径就会漂。板上第一条命令
仍建议是 `python3 -c "import pynq, inspect; print(inspect.getsourcefile(pynq.MPUtil))"`
之类，用你自己镜像里的真实行号替换这里的引用。

### 版本钉扎

- v3.1 镜像发行含 `pynq_z2_v3.1.0`：<https://pynq.readthedocs.io/en/v3.1/changelog.html>
- **PYNQ 4.0 的支持矩阵未在本包取证。** `SKILL.md` 范围声明里的“不适用 PYNQ 4.0”是
  划边界用的说法（本包所有断言都钉在 v3.1 tag 上），不是“已查证 4.0 去掉了哪些板卡”的
  结论。要用在 4.0 上，就按 `scripts/surface_dump.py` 在你自己的镜像上重取一次面，
  把本文件的行号锚点换成你镜像里的真实行号，再逐条判定。
- 4.0 明确移除 Z1/Z2（“Support for Pynq-Z1 and Pynq-Z2 boards is removed”）：
  <https://pynq.readthedocs.io/en/latest/changelog.html>
- 4.0 还删除 `pynq.lib.arduino / logictools / rpi`：同上页
- v3.1 镜像构建用 Vivado / Vitis / PetaLinux 2024.1、Ubuntu 22.04：
  <https://pynq.readthedocs.io/en/v3.1/pynq_sd_card.html>
  （注意：这与赛题要求的 Vivado 2025.2/2026.1 **不同版本**，见“冲突与影响”）

### Overlay 与寄存器

- `Overlay(bitfile_name, dtbo=None, download=True, ignore_version=False, device=None, gen_cache=False)`
  与“`.hwh` 必须与 `.bit` 同名同目录”这一约束（约束本身在源码与文档里都有，逐字措辞
  以打开页面为准，本包不复述引号）：
  <https://github.com/Xilinx/PYNQ/blob/v3.1/pynq/overlay.py#L289>、
  <https://pynq.readthedocs.io/en/v3.1/pynq_libraries/overlay.html>
- `download=False` / `is_loaded()` / `reset()` / `free()` / `load_ip_data()`：
  <https://pynq.readthedocs.io/en/v3.1/pynq_libraries/overlay.html>
- “New drivers will only be bound when the overlay is reloaded”：
  <https://pynq.readthedocs.io/en/v3.1/overlay_design_methodology/python_overlay_api.html>
- FCLK 由 `.hwh` 在下载时写入：`<https://github.com/Xilinx/PYNQ/blob/v3.1/pynq/overlay.py#L422>`
- 局部重配 `Overlay.pr_download(partial_region, partial_bit, dtbo=None, program=True)`
  （参数名以官方 docstring 为准，见本文件末「文档与源码冲突」条），且文档写明
  不检查区域是否真可部分重配：
  <https://pynq.readthedocs.io/en/v3.1/overlay_design_methodology/partial_reconfiguration.html>
- `MMIO(base_addr, length=4, device=None, **kwargs)`、`read(offset=0, length=4, word_order)`；
  成员只有 `read/write/write_mm/write_reg/array/base_addr/length/device`；
  `length ∈ {1,2,4,8}` 的检查在 mmio.py L113，偏移非 4 倍数抛
  `Unaligned read: offset must be multiple of 4.` 在 L123：
  <https://github.com/Xilinx/PYNQ/blob/v3.1/pynq/mmio.py>、
  <https://pynq.readthedocs.io/en/v3.1/pynq_package/pynq.mmio.html>
- “一次事务只搬 32 bit、不支持 burst、只能访问 GP slave 端口的 IP”：
  <https://pynq.readthedocs.io/en/v3.1/overlay_design_methodology/pspl_interface.html>
- `register_map` 挂在 IP 驱动实例上而不是裸 `MMIO`；切片写法 `hi:lo` 含端点；需要随
  比特流分发 `.hwh`。**“只支持标量寄存器”是观察行为**（v3.1 文档与源码里没有 scalar
  字样），数组型寄存器请以实测为准：
  <https://github.com/Xilinx/PYNQ/blob/v3.1/pynq/overlay.py#L738-L747>
- 寄存器映射由 `.hwh` 运行期解析生成（不是 JSON、没有 tcl hook）：
  <https://github.com/Xilinx/PYNQ/blob/v3.1/pynq/pl_server/hwh_parser.py#L154>

### DMA 与缓冲

- `DMA` 的 `bindto = ["xilinx.com:ip:axi_dma:7.1"]`（L758）、`sendchannel/recvchannel/
  buffer_max_size`（L557-L581），构造签名是 `DMA(description, *args, **kwargs)`；用 2.x 的
  四位置参数会抛（逐字，不要省略后半句，它指出了旧驱动的去向）：
  `RuntimeError('You appear to want the old DMA driver which has been deprecated and moved to pynq.lib.deprecated')`
  <https://github.com/Xilinx/PYNQ/blob/v3.1/pynq/lib/dma.py>
- `transfer(array, start=0, nbytes=0)` 为简单通道（L106，**不接受** `cyclic`）；
  带 `cyclic` 的是 scatter-gather 通道（L317）。微通道参数名是 `c_micro_dma`（L615）：
  <https://github.com/Xilinx/PYNQ/blob/v3.1/pynq/lib/dma.py>
- 未对齐抛 `DMA does not support unaligned transfers; Starting address must be aligned to {} bytes.`：
  <https://github.com/Xilinx/PYNQ/blob/v3.1/pynq/lib/dma.py#L147-L152>
- “默认最大事务长度 14 bit（2^14=16KB），要在 Vivado IPI 里调大”、
  “流 IP 必须拉 TLAST，否则事务永不完成（HLS 常见）”：
  <https://pynq.readthedocs.io/en/v3.1/pynq_libraries/dma.html>
- `buffer_max_size = (1 << C_SG_LENGTH_WIDTH) - 1`、`cyclic` 仅发送通道、
  `'Cannot wait in cyclic BD mode'`：<https://github.com/Xilinx/PYNQ/blob/v3.1/pynq/lib/dma.py>
- `allocate(shape, dtype='u4', target=None, **kwargs)`（`buffer.py#L138`，L158 `return target.allocate(shape, dtype, **kwargs)` 转发）：
  中间层 `Device.allocate(self, shape, dtype, **kwargs)`（`pl_server/device.py#L127`，L145 转 `default_memory.allocate`）
  与 `XrtMemory.allocate(self, shape, dtype, **kwargs)`（`pl_server/xrt_device.py#L113`，L124 调叶子）都**原样透传**
  `**kwargs`、不按名字校验，但链条终止于固定形参的叶子 `_xrt_allocate(shape, dtype, device, memidx,
  cacheable=0, pointer=None, cache=None)`（`pl_server/xrt_device.py#L59`）——叶子没有 `**kwargs`，
  所以未知/写错的键在叶子处 `TypeError: _xrt_allocate() got an unexpected keyword argument ...`，**不是**被静默忽略；
  能绑定的只有 `cacheable / pointer / cache`。顶层 `pynq.allocate` 即由此导出（`pynq/__init__.py#L7 from .buffer import allocate`）；
  Zynq-7000 走 `EmbeddedXrtMemory(XrtMemory)`（`pl_server/embedded_device.py#L493`，`default_memory` L551）继承同一叶子。
  `PynqBuffer` 暴露 `device_address / physical_address / coherent / cacheable / nbytes / flush / invalidate /
  sync_to_device / sync_from_device / freebuffer`：
  <https://pynq.readthedocs.io/en/v3.1/pynq_libraries/allocate.html>、
  <https://github.com/Xilinx/PYNQ/blob/v3.1/pynq/buffer.py#L138>、
  <https://github.com/Xilinx/PYNQ/blob/v3.1/pynq/pl_server/device.py#L127>、
  <https://github.com/Xilinx/PYNQ/blob/v3.1/pynq/pl_server/xrt_device.py#L59>、
  <https://github.com/Xilinx/PYNQ/blob/v3.1/pynq/pl_server/embedded_device.py#L493>
- Zynq-7000 端口清点（4×HP、2×GP 主、2×GP 从、1×ACP、64 根 PS→PL GPIO）：
  <https://pynq.readthedocs.io/en/v3.1/overlay_design_methodology/pspl_interface.html>
- 连续内存：v3.1 内核配置 `CONFIG_CMA_SIZE_MBYTES=128`：
  <https://github.com/Xilinx/PYNQ/blob/v3.1/sdbuild/boot/meta-pynq/recipes-kernel/linux/linux-xlnx/pynq.cfg#L1>

### 板卡与上板

- PYNQ-Z2 板文件与主 XDC 下载、安装目录：
  <https://pynq.readthedocs.io/en/v3.1/overlay_design_methodology/board_settings.html>
  （XDC 包 `PYNQ-Z2 v1.0.xdc.zip`；上游构建脚本实际用 `-part xc7z020clg400-1`）
- HDMI 输入**存在**（base overlay 的 `video` 是 `HDMIWrapper`，文档写“HDMI-In block,
  HDMI-Out block, and a Video DMA”）：<https://pynq.readthedocs.io/en/v3.1/pynq_libraries/video.html>
- PS 侧晶振参数是 50 MHz（`PCW_CRYSTAL_PERIPHERAL_FREQMHZ {50}`，`base.tcl`）；
  板卡 125 MHz 参考时钟在 H16（`sysclk`）来自**板卡主 XDC** `PYNQ-Z2 v1.0.xdc` 与官方
  用户手册，不是 `base.xdc`。`base.xdc` 里能看到的是 HDMI 输入时钟：
  `create_clock -period 8.334 [get_ports hdmi_in_clk_p]`（N18 是 `hdmi_in_clk_p`）：
  <https://github.com/Xilinx/PYNQ/blob/v3.1/boards/Pynq-Z2/base/vivado/constraints/base.xdc>、
  用户手册 <https://www.mouser.com/pdfDocs/pynqz2_user_manual_v1_0.pdf>
- `PCW_ACT_FPGA0..3_PERIPHERAL_FREQMHZ = 100 / 142.857132 / 200 / 100`（`base.tcl` L3586-3589）；
  板卡预设的 FCLK3 是 160 MHz，与 base 实际不同，取数以 `PCW_ACT_*` 为准
- base overlay 只开 HP0/HP2、ACP 关、两个 GP 主开：
  <https://github.com/Xilinx/PYNQ/blob/v3.1/boards/Pynq-Z2/base/base.tcl#L4111-L4121>
- 板上需先下载比特流才能分配缓冲：由代码强制
  （`RuntimeError('Overlay is not downloaded')`，`pynq/pl_server/embedded_device.py`），
  **不是** allocate.html 的原话。
- 局部重配“不检查该区域是否真的可部分重配”出自
  `pr_download` 的 docstring（<https://pynq.readthedocs.io/en/v3.1/pynq_package/pynq.overlay.html>），
  参数名是 `partial_region`；`partial_reconfiguration.html` 没有这句话。
- 登录：`http://192.168.2.99`、`xilinx/xilinx`、Jupyter 终端为 root、串口 115200 8N1、
  Samba `\\192.168.2.99\xilinx`：
  <https://pynq.readthedocs.io/en/v3.1/getting_started/pynq_sdcard_getting_started.html>、
  <https://pynq.readthedocs.io/en/v3.1/getting_started/terminal.html>
- 默认无外网：<https://pynq.readthedocs.io/en/v3.1/getting_started/network_connection.html>
- 板上自测：`cd /home/xilinx/pynq && sudo py.test -vsrw`（需 root，部分用例要交互确认）：
  <https://pynq.readthedocs.io/en/v3.1/appendix/verification.html>
- 上游测试目录：<https://github.com/Xilinx/PYNQ/tree/v3.1/tests>

## 失效条件（冲突、影响与未证实项）

1. **DMA 模式**：文档页写“supports simple mode only”，tag v3.1 源码实现了 SG 与
   `cyclic`。本包以源码为准，并在条目里并列两处证据。
2. **`.tcl` 的角色**：`pynq_libraries/pl.html` 仍说“overlay Tcl file is parsed by the Device
   class”，而 v3.1 的 `pl_server/` 只有 `hwh_parser.py` / `xclbin_parser.py`。本包按
   `.bit + .hwh` 组合处理。
3. **工具版本**：镜像用 2024.1 构建，赛题要求 2025.2/2026.1。`.hwh` 属性名可能随版本改动，
   所以 `hwh_inspect.py` 同时支持 `MEMRANGE / ADDRESSBLOCK / SEGMENT` 三种拼写，并用
   `--require` 把“读不到”变成退出码 1；用真实 `.hwh` 跑一遍是交作品前的必做步骤。
   数值与单位的读法按“声明优先”固定下来（地址类属性按 v3.1 的 `int(x, 16)` 口径、其余纯
   数字串按十进制；`*FREQMHZ` 是 MHz、`FREQ`/`CLKRATE`/`*HZ` 是 Hz，量级与声明冲突就报
   ambiguous），规则与本表逐字抄录的源码语句一起写在 `scripts/hwh_inspect.py` 的 docstring
   和 `references/design-to-bitstream-hwh.md` 里。

### 已否定（网上常见但 v3.1 不存在，检查器会判红）

`pynq.bitstream.File`、`PartialBitstream`、`PartialOverlayMap`、`pl_device_transfer`、
`Overlay.remap`、`Overlay.graph`、`MMIO.register_map`、`pynq.lib.i2c`、`PynqBuffer.length`、
`allocate(user_flags=...)`、`pynq_register_map.tcl`。机器可读版本见
`scripts/api_surface.json` 的 `refuted` 数组（含逐条 URL）。

## 使用方法

### 复算这份清单

```bash
python3 scripts/api_lint.py --self        # 检查器仍能在独立样本上召回，且不把正确示例判红
python3 scripts/api_lint.py assets/examples
python3 scripts/hwh_inspect.py assets/fixtures/hwh/z2_video.hwh --require address,registers \
  --require clocks,dma                    # 逐条与本文件的取证对照
```

把本文件里任一 URL 打开、把引用的原文与条目正文对照，是评委最快的核查路径。

## 已验证效果

本清单里每条 URL 都是 2026-10-10 实际打开并逐字抄录的；由清单派生的可执行结论有两条：

```bash
checked=21 red=0
checked=21 red=0
```

`scripts/api_surface.json` 是本文件的机器可读版本：13 组 API 面、27 条“名字不存在”、1 处文档与源码冲突、3 条逐字错误串。

## 未证实项（不写进结论）

- UG585 里 GP0/GP1 的地址窗口数值：docs.amd.com 为 JS 渲染，本次无法逐字取证。因此本包
  **不声称** `0x4000_0000` 是 PS→PL 的固定窗口，只说明它在官方示例里作为例子出现。
- v3.1 镜像内 Python 具体小版本：文档自相一处（FAQ 说 3.6，changelog 3.0 说升到 3.10），
  故不写死。
- `board_part`/preset 字符串（`tulip.com:part:pynq-z2:1.0` 之类）未在 v3.1 文档中给出，
  未采用。
- `assets/fixtures/hwh/*.hwh` 是合成样本：见 `assets/fixtures/hwh/provenance.md` 的
  U1–U13 未确认属性名清单。**不可**把这些文件当成 Vivado 输出。
- 板上真实吞吐、时延、抖动：本机无板，本包全部性能数字均为“理论值或未测”，凡写入
  `metrics.csv` 的真实数字必须来自使用者实测。
