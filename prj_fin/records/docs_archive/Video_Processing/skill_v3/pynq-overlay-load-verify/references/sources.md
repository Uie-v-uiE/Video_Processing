# PYNQ 接口出处表（本组条目引用的都在这张表里）

## 目录

- 为什么需要这张表
- 位流与 Overlay
- 寄存器与 MMIO
- DMA 与缓冲
- 视频流
- 版本差异速记
- 板卡与 BSP

## 为什么需要这张表

PYNQ 的 2.7 / 2.8 / 3.0 三处 API 有**实质差异且向后不兼容**：`pynq.bitstream.check_credentials` 与
`Bitstream` 类在 2.8.0 被删；`Buffer.__init__` 在 3.0.0 改了签名；`pynq.video` 的 `InValueError`/`OutValueError`
在 3.x 消失；`pynq-qpython` 从 2022-11-15（0.5.1）起没再跟进新栈。任何"照文档写代码"的建议，
不带版本就是空话。这张表把本组条目里每一句接口断言钉到可复查的位置。

引用规则：**版本号 + 可点击位置**。文档站没有逐行锚点，所以文档给到小节标题，源码给到
`blob/<sha>/<path>#L<行>`（blob 与 tree 对同一个提交内容返回同一 blob sha，可逐行核对）。

## 位流与 Overlay

| 断言 | 出处 |
| --- | --- |
| 2.7.1 有 `pynq.bitstream.check_credentials(...)`（返回 bool + 消息，校验镜像头而非硬件） | commit `45458c9` `pynq/bitstream.py#L49` |
| 2.8.0 删除 `check_credentials` 与 `Bitstream` 类，只留 `PROGRAM_DEVICE`/`DEVICE`/`download_bitstream` | commit `3e0d24c` `pynq/bitstream.py#L21`；发行说明 "Remove old APIs: Bitstream class" |
| 3.0.1 `pynq/bitstream.py` 里没有 `Bitstream`/`check_credentials` | blob `e45a0d1` `pynq/bitstream.py#L21` |
| `Overlay.__init__` 会做 `overlay_check()`，读回的是时钟状态不是位流身份 | blob `e45a0d1` `pynq/overlay.py#L142`（函数体 `#L41`） |
| "下载了但硬件没配置"的官方归因：设备树缺 `partial` 配置项 ⇒ BSP 问题，不是 Python API 能修的 | 官方 FAQ "Downloading a bitstream has no effect" |
| `hi/lo` 部分重载在旧栈需手工 `_peclib.overlay_bitstream_close(xh)`（私有 API） | 2.7.1 `pynq/overlay.py` |
| 官方下载路径只有两条：`.bit → /lib/firmware/pynq/ → Overlay()`，或 `bitstream_name` 直调 driver（板级支持随 BSP 变） | 官方文档 "Downloading Overlay Bitstreams" |

## 寄存器与 MMIO

| 断言 | 出处 |
| --- | --- |
| `MMIO(address, length)`：`read`/`write` 返回**字典**（按切片名），`read_bitfield`/`write_bitfield` 按描述符名读写 | 文档 API Reference → MMIO；实现 `pynq/mmio.py` |
| `register_map` 描述符类：`Scalar`/`Bits`/`Array`/`Struct`/`Union`（字段是 `struct`，不是 dataclass） | `pynq/regtools.py` |
| 数组读写 `read(index=)`/`write(values, index=)`；越界与位段重叠在**构造 `register_map` 时**就检查 | `pynq/_regmap.py` |
| `describe()` 返回**打印用字符串**，不是 dict ⇒ 不能拿它做程序化比对 | `pynq/_regdict.py` |
| 复位值不是运行时读出来的，而是写描述符时抄 IP 文档 | 文档 "Writing a Register Map" |
| 驱动寄存器地址由 tcl 生成器产出，官方提示"务必人工核对" | 文档 "Driver Hardware Register Map" |
| 天生一致端口（如 AXI Lite 走 APU 路径）不做缓存维护；非一致 DMA 才需要 `uncached` | AR 68466（经 PYNQ 源码与 Xilinx 知识库交叉） |

## DMA 与缓冲

| 断言 | 出处 |
| --- | --- |
| `Buffer` 默认可缓存；`uncached=1` 显式声明才走非缓存路径；`contiguous` 默认 0 | 文档 "Uncached Buffers"/"Contiguous Buffers"；`pynq/buffer.py` |
| `Buffer.__init__` 在 3.0.0 改了签名 ⇒ 位置参数在 2.7 能跑、在 3.0 报错 | blob `e45a0d1` `pynq/buffer.py#L57` |
| `pynq.allocate(size, flags, cached)` 第三个参数是缓存标志；`pynq.qalloc()` 不含该参数 | `pynq/xlnk.py` |
| 对齐规则在 C 层按 IP 类型分三族：MM 8 字节；S2MM 写指针 8 / 字节数 16；非缓存缓冲强制 `BUF_ALIGN` | `pynq/lib/axidmadma.c`；`pynq/xlnk.c` |
| Python 侧 `sendframe/recvframe` **不强制**这些对齐 ⇒ 违反时不报错，坏在数据上 | `pynq/_xlnk.c` 的 `PyMASetup` 等 |
| `wait()` 超时返回 `False`，不抛异常 ⇒ 不接返回值就是"静默丢包" | `pynq/_xlnk.c` |
| `transfer()` 只下发描述符、不等待完成 | `pynq/xlnk.py` |
| `TCircularity` / `Alignment` 两个异常只存在于 `pynq-dmadma` **2.7.x**；3.x 没有 | commit `a736927` `pynq/dmadma.py`；pypi.org/project/pynq-dmadma/ |
| Zynq 非一致 DMA ⇒ `dma_alloc_coherent` 不保证一致（读旧数据/残影的官方归因） | AR 752564（同 FAQ 交叉引用） |
| `pynq.xlnk.stat()` 只读；`cma_nr` 的 16 段各固定 64 MB；reserved 区通常 1 GB ⇒ 是配额不是可扩上限 | `pynq/xlnk.py`、`Documentation/reference/sdma.rst` |

## 视频流

| 断言 | 出处 |
| --- | --- |
| `pynq.video` 委托给独立包 `pynq-video`（1.x 配 PYNQ 2.x，2.x 配 3.x） | `pynq/video.py`；`pynq-video` PyPI |
| `Display.start()` 在帧数不为 8 的倍数时向上取整并"吃掉尾字节"，随后强制 `TLAST` | `pynq/lib/vvideo.c#L572`、`#L656`；`Display.start()` 文档 |
| `Display` 文档明写"输出侧对齐不保证"，要求用户自己保证 | 文档 API Reference → Display |
| `LineStrideError`（stride 非 4 的倍数）两版都有；`InValueError`/`OutValueError` 只在 2.7.x | commit `170d616`；blob `e45a0d1` |
| 末帧缺 `TLAST` ⇒ 接收端不出 `tlast` ⇒ `recvframe` 永不返回（不是数据错，是"永不结束"） | FAQ "End of Frame" |
| `set_length()` 文档原话：只设期望长度，不保证长度到了就停 | 文档 API Reference → VDMA |
| `pynq.lib.video` 与 `pynq.video` 都存在于 3.0.1 | blob `e45a0d1` |

## 版本差异速记

| 位置 | 2.7.1 | 3.0.1 |
| --- | --- | --- |
| `pynq.bitstream` | `Bitstream`、`check_credentials`、`PartialBitstream` | 只剩 `PROGRAM_DEVICE`/`DEVICE`/`download_bitstream` |
| `Overlay.download()` | 有（内部 `download_bitstream`） | 有（内部 `_download`） |
| `pynq.device.overlay.*` | 有 | 无 |
| `Buffer(4096, 1, 0)` 位置参数 | 可用 | 签名已变，不可用 |
| `pynq.video` 的 In/OutValueError | 有 | 无 |
| `pynq-qpython` | 0.5.1 依赖旧 `pynq.device.overlay` | 装不上/跑不通（包 2022-11-15 后未更新） |

## 板卡与 BSP

支持列表逐板给出（改板卡需自建 BSP 与设备树，不在本条射程）：官方文档 Getting Started → Downloading an Image，
以及 `<image>/boards` 目录。`PL.is_supported(platform)` 在 3.0.1 仍在（`pynq/pl.py`），可用于开机自检平台匹配。
`Overlay(bit)` 抛 `ValueError: No bitstream found for this platform` 时，第一解释是**板文件/平台不匹配**，
不是位流坏了——先核对 BSP 与 `DEVICE`，再怀疑产物。
