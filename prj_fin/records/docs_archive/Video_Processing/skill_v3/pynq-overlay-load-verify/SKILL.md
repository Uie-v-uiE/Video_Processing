---
name: pynq-overlay-load-verify
description: 用于在 PYNQ 里加载 Overlay 之后需要证明"板上跑的确实是这份产物"时；也用于出现 `ValueError: No bitstream found for this platform`、换板卡后同名 IP 取不到、`hi/lo` 部分重载后行为仍是旧的那份、或要判断某个 IP 天生不暴露在 Python 侧这类症状的时候。
compatibility: PYNQ 2.7.1 与 3.0.1（两处 API 有实质差异，逐条标注）；需要板上跑着 pynq 镜像与 `pynq.bitstream` 后端；未在自家板卡实跑，凡引用请先按"已验证效果"一节的配方重做
metadata:
  kind: 提示词工作流
  topic: PYNQ
---

# Overlay 加载与身份校验

## 适用场景

- 换了一次位流、换了板卡、或从版本库重新拉了工程，需要一句话证明板上跑的就是这一份。
- 出现：`No bitstream found for this platform`（板文件/器件平台不匹配）；`hi/lo` 重载之后行为仍是旧的；
  `Overlay` 里某个 IP 在 Python 侧根本取不到名字。
- 需要在没有 JTAG、只能 SSH 进板卡的场合自证 PL 侧状态。
- 不适用：整片位流的启动（那不是 Overlay，是 boot 介质与身份问题，见 `artifact-provenance-binding`）。

## 使用方法

**动手前先查**（一手资料优先：官方文档与源码 ＞ 发行说明 ＞ 教程 ＞ 记忆）——三件事必须查到出处再写代码：
本 PYNQ 版本的 `pynq.bitstream` 模块里到底还有什么（2.8.0 起 `Bitstream`/`check_credentials` 被删）、
`Overlay.__init__` 是否真的读回硬件状态、以及这块板卡的 BSP 是否提供 `partial` 配置项。

1. **把"加载"拆成三段，各自要有读数**，不要写成一步：
   选件（`bit` 文件在盘上、md5 与文档一致）→ 下发（`Overlay(bit)` 不抛）→ 回读（板上状态与期望一致）。
   缺"回读"这一段，前两段合起来只证明了"Python 没报错"。
2. **身份校验的接口在两代之间换了位置**（这是本条最容易写成假判据的地方）：
   - 新栈（3.x/4.0）有 `Overlay.is_loaded()`，比较的是覆盖层与 PL 的**时间戳/位流名**——
     这才是"板上跑的是不是这一份"的可回读口。
   - 旧栈教程里的 `pynq.bitstream.Bitstream(...).download()` 与 `check_credentials()` 在较新版本被移除，
     **本包在 3.1 与 master 源码中未能核到 `check_credentials`**（`pynq.bitstream` 只剩下载常量与
     `download_bitstream`）。所以代码要先探测：取到校验口就用它，取不到 ⇒ 判 `NOT_MEASURED`，
     绝不用 `except: pass` 把这一段变成真空通过。
   - `Overlay.__init__` 里的 `overlay_check` 读回的是**时钟状态**，不是位流身份——别把它当"证明加载了这份 bit"。
3. **回读用可移动的量**。没有身份口时，退而求其次：读一个会随配置改变的寄存器/计数器
   （见 `pynq-register-map-readback`、`board-liveness-readback`），或比对下发前后同一读的差值。
4. **先跟用户确认**：是否允许写 PL 侧（部分重载会打断正在跑的数据通路）、
   是否允许为了校验多读一次硬件状态（读状态可能带动 FIFO/握手）、
   以及"这一版不作全绿说法"能不能接受——身份口取不到时诚实的结果是 `NOT_MEASURED`。

形状（低自由度，按版本分叉）：

```python
try:
    from pynq.bitstream import check_credentials      # 旧栈才有
    ok, msg = check_credentials("/path/to/x.bit")     # 校验的是镜像头，不是硬件
except (ImportError, AttributeError):
    ok, msg = None, "这一版没有身份校验口"            # None ⇒ NOT_MEASURED，绝不是 True
if ok is None:
    log(f"加载前校验 NOT_MEASURED：{msg}")
overlay = Overlay(bit)                                # 下发；只证明 Python 没抛
```

## 失效条件

- **把 `Overlay()` 不抛异常当成"位流已生效"**：它校验的是时钟状态；PL 侧内容仍是上一份时也能成功。
  征兆：换了 bit、行为与读数一起不动。
- **用 `except: pass` 兜住校验口缺失**：全绿假象，且下一次升级栈时症状才出现。
- **照旧栈教程写 `Bitstream("x.bit").download()`**：新版本 `pynq.bitstream` 只剩 `PROGRAM_DEVICE`/`DEVICE`/`download_bitstream`，
  旧写法直接 `ImportError`。征兆：文档里的命令在自己板上跑不通，先怀疑版本再怀疑板卡。
- **`hi/lo` 部分重载的"生效"判定**：旧版本要手工 `_peclib.overlay_bitstream_close(xh)` 才真正下发。
  该接口是私有 API，跨版本不稳定——依赖它就等于把技能绑在某个构建上。征兆：重载函数返回成功但内容未变。
- **通用 Zynq 板卡没有现成 BSP**：官方支持列表逐板给出，非列表板卡要自建 BSP/hw_name，成本高且不在本条射程内。
- **同一份文档里既有 2.x 又有 3.x 写法**：`pynq.device.overlay.*` 这类路径只存在于旧版（例如 `pynq-qpython` 0.5.1 之后没跟进，
  在新栈上直接 ImportError）。征兆：Import 错误的模块路径在文档里能找到、在板上不存在。

## 已验证效果

未量过，属建议：本条按官方文档与源码逐条核对接口形状，**没有在本队板卡上实跑过 PYNQ**，
所以不给任何"板上量到的读数"。可复跑的形式（有 PYNQ 镜像的板卡才允许跑）：
在 Python 3.10 + 目标版本下依次执行
`import pynq, pynq.bitstream` 并打印 `pynq.__version__`、`dir(pynq.bitstream)`，
再跑一次 `Overlay(bit)` 前后各读一次同一个会动的寄存器——三条读数分别证明"栈版本与本文一致"、
"校验口存在与否"、"下发确实改变了硬件"。任一条取不到 ⇒ 该格写 `NOT_MEASURED`，不许推断。

## 来源

长自一类反复出现的观察：加载类流程把"没有报错"写成"已经生效"，而真正能证伪的那一步（回读身份）
要么被 `except: pass` 吞掉、要么在该版本里根本不存在；以及照旧栈文档写新栈代码导致的 ImportError 空转。
外部出处：官方文档 `pynq.bitstream`/`pynq.Overlay` 页、源码 blob `e45a0d1`（3.0.1）、
commit `3e0d24c`（2.8.0 移除旧校验与 `Bitstream`）、commit `45458c9`（2.7.1 仍有）、发行说明 2.7→2.8、
`pynq-qpython` PyPI 最后发布 0.5.1（2022-11-15）。位置见 `references/sources.md`。
