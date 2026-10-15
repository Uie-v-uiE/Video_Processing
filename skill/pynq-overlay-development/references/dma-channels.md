# DMA 通道：形状、对齐、长度、完成判定、超时

本页管**谁驱动引擎**：`pynq.lib.dma.DMA` 的通道形状与两个长度上限来源、对齐与超限的不同反应、cyclic 及其脏状态、`start()/stop()` 与 DMACR、完成判定的四个读数与错误位表、超时代价与端到端骨架。内存与一致性那一半在 `buffers-and-cache.md`。

## 1. DMA 的通道与调用形状

`pynq.lib.dma.DMA` 是挂在 IP 实例上的驱动（用 `getattr(ol, 'axi_dma_0')`，不要自己 new；
传错参数会拿到 `RuntimeError: You appear to want the old DMA driver which has been deprecated...`）。

**一处文档与实现互相矛盾的地方，按实现走：**官方 `doc_dma.rst` 写着
"The *DMA* class supports simple mode only."，而 `lib/dma.py` 里明明白白有
`_SGDMAChannel`（`:202` 起，`transfer(..., cyclic=...)` 在 `:317`）并且 `DMA.set_up_tx_channel()`
会按 `self._sg` 选择构造它。所以"SG 不支持"这句话不能作为判据——它要么是文档过期，要么指的是
某个特定 IP 变体的支持范围。
**但那句 `doc_dma.rst` 的引文本包取不到出处**：`.rst` 不在 sdist 里（手上那几棵发行树都没有 `doc/`），
所以它的版本归属记 `NOT FETCHED`，别把它当"某一版的官方口径"来引用；
这一条真正的依据只有实现侧那几行——那部分是本包在 3.1.2/4.0.0 两棵树上读过的原文。**行为侧怎么办**：以 `getattr(ol, name)` 拿到的通道对象的类名为准
（`type(dma.sendchannel).__name__`），它决定你有没有 `cyclic` 这个形参、超限会不会报错
（本文 §1 第 2 条）、以及 `transferred` 是从寄存器读还是从描述符累加（§2）。

**通道对象总是在，但可能是 `None`。** `DMA.__init__` 先 `self.sendchannel = None;
self.recvchannel = None`（`lib/dma.py:639-641`），只有当 IP 的 `parameters` 里
`c_include_mm2s` / `c_include_s2mm` 为真才去构造对应通道。所以：

```python
dma.sendchannel is None    # 这版硬件没使能 MM2S —— 不是 bug，是配置
```

先判 `is None` 再谈"引擎不干活"，否则你会给一个不存在的方向调时序。

**长度上限有两个不同的来源**，别把 `buffer_max_size` 当唯一答案：

```python
# 源码原样（4.0.0 与 3.1.2 的 lib/dma.py 这一段逐行相同，行号 629-637）：
if "c_sg_length_width" in description["parameters"]:
    self.buffer_max_size = 1 << int(description["parameters"]["c_sg_length_width"])
else:
    self.buffer_max_size = 1 << MAX_C_SG_LENGTH_WIDTH
self.buffer_max_size -= 1
```

**判"有没有参数"用的是 `in`，不是取到值再判真值**——这一字之差有后果：键**存在但值为 0** 时走
第一条分支，`1 << 0` 再减 1 = **0**，而不是退回 26 位那个常数。早先这里写成
`w = parameters.get(...)` / `... if w else ...` 的转述**是错的**（那种写法会把 0 当成"没有键"），
照它推上限会在"IP 里把 `C_SG_LENGTH_WIDTH` 设成 0"这一格上给出完全不同的数。

`max_size`（每通道 `_max_size`）**不在这一段里**，它是**收发各一份**、且**用的 burst 键不同**
（4.0.0 `lib/dma.py`）：MM2S 在 `:664-669` 用 `c_mm2s_burst_size`，S2MM 在 `:718-726` 用
`c_s2mm_burst_size`，两处的形状都是

```python
if self._micro:
    max_size = data_width * int(self.description["parameters"]["c_mm2s_burst_size"])   # S2MM 那份是 c_s2mm_burst_size
else:
    max_size = self.buffer_max_size
```

`axi_dma_micro`（`self._micro`）下每个通道的 `_max_size` 是 **数据位宽 × burst size**，
跟长度寄存器位宽无关；这时 `buffer_max_size` 那个数会**远大于**真实单次上限。要哪个数，
看你这版 IP 是不是 micro，判据：`dma.description['parameters']` 里有没有 micro 相关键、
以及 `getattr(channel, '_max_size', None)`（实例属性，类上看不见）。
还有一条容易当成"永远跟着 IP 参数走"的：**`c_sg_length_width` 这个键不存在时，驱动退回一个
硬编码常数** `MAX_C_SG_LENGTH_WIDTH = 26`（`lib/dma.py:11` 与 `:634-635`），于是
`buffer_max_size = 2^26-1`，与你的 IP 实际能力无关。这条路径只在元数据缺键时触发，
而元数据缺键本身就是"这批 `.hwh/.xsa` 不配套"的读数——所以别拿这个数当设计上限。

```python
dma.sendchannel.transfer(in_buf)    # _SDMAChannel.transfer(array, start=0, nbytes=0)
dma.recvchannel.transfer(out_buf)    # SG 版多一个 cyclic=False
dma.sendchannel.wait()    # 这三行只说明签名形状；收尾别照抄，用 §2 的
    # wait_with_timeout（裸 wait() 没有 timeout 形参）
```

四条会直接报错的边界（都在源码里）：

1. **对齐**：`if not self._dre and ((array.physical_address + start) % self._align) != 0: raise`
   （`lib/dma.py:147`、SG 同形 `:359`）—— 对齐单位是**数据位宽**（`self._align = width`，来自 IP 的
   memory-map 数据宽度），而且判的是 **`physical_address + start` 这个和**。
   这两个数都能从元数据里算出来，不要猜、也不要默认 4：

    ```python
    p = dma.description["parameters"]
    align = int(p["c_m_axi_mm2s_data_width"]) >> 3    # S2MM 侧用 c_m_axi_s2mm_data_width
    dre    = bool(int(p.get("c_include_mm2s_dre", 0)))    # 键不存在 -> False（:655-663, :712-718）
   ```

   `dre`（datawidth converter）开着时这条检查整个跳过；`align` 是**字节**数，所以 32 位宽是 4、
   64 位宽是 8。"基址 4 对齐但报 unaligned"九成是那一路宽度是 8 或者你手写了偏移而没走切片。
2. **长度上限只由 SDMA 检查**：`_SDMAChannel.transfer` 有
   `if nbytes > self._max_size: raise ValueError("Transfer size is {} bytes, which exceeds the
   maximum DMA buffer size {}.")`（`lib/dma.py:141-145`）。**`_SGDMAChannel.transfer` 没有这条检查**：
   它把大传输**默默切成多个描述符**（`blk_size = self._max_size - (self._max_size % self._align)`，
   `:373`；`blk_size > remain` 时再对半取，`:376-378`）。
   后果：SG 上"没报 exceeds maximum"完全不能证明你没超限，只能证明驱动自己拆了；
   分块逻辑写在 Python 侧做（SDMA 必须自己分块）。
2.5 **SG 还会替你分配一块 CMA**（这一条最容易在算内存预算时漏掉，编号挂在第 2 条后面因为它同源）。
   先给结构证据，免得被读成"我只看了一个分支"：整个 `transfer()`（`lib/dma.py:317` 起到 `:468`（最后一条语句跨 `:465-468`），
   下一节 `wait()` 从 `:470` 开始）里
   **只有一次 `allocate`**（`:384`）与**一个描述符循环**（`for i in ...`，`:390`），
   cyclic 与非 cyclic 的差别只在循环**内部**——`:392` 让最后一张描述符指回第一张，`:398` 是
   非 cyclic 的正常链，没有第二条路径；而 `_descr` 在整个文件里只被**整体重新绑定**四次
   （这一句的数法要说清，否则对不上：**`grep -n 'self\._descr *=' lib/dma.py`** 交 4 行——
   `:254`（构造函数置 `None`）、`:384`（分配）、`:521` 与 `:552`（`wait()`/`wait_async()` 的收尾）；
   若改成 `grep -n 'self\._descr\[' lib/dma.py` 数的是**元素写**，本机 4.0.0 交到 **13 行**，
   那是往表里填字段，不是换表。两个数都对，别拿其中一个去否另一个）。
   "分配点只有一个、回收点只有两个"就是本节下面所有结论的依据：`stop()`（`:303-312`）不碰它、
   cyclic 走不到它，都不是推测而是穷举的结果。
   `_SGDMAChannel.transfer`
   里 `self._descr = allocate(shape=(self._num_descr, 16), dtype=uint32, target=self.device)`
   （`lib/dma.py:384`，注释明写每条描述符要 64 字节对齐，`:382-383`），
   `_num_descr = ceil(remain / blk_size)`（`:380`）。也就是说 **SG 的一次传输占用 =
   你的缓冲 + 描述符表**，两边都在同一块连续内存池里。
   清表这件事**在每个等待函数里都只发生在最后**（`wait()` 与 `wait_async()` 各一次，就是上面数到的
   `:521`/`:552` 那两处。别把它说成"全文件只有一个回收点"——那和 `:85` 的"回收点只有两个"数的不是
   同一个东西：`:85` 数的是 `_descr` 被赋值的位置，这里数的是"清表落在函数体的哪一段"）：
   `self.stop()` 之后才 `self._descr.close(); self._descr = None`（`:519-521`，
   `wait_async` 同理 `:550-552`）。前面任何一条 `raise` 都会跳过它——
   包括 cyclic 那句 `if self._cyclic: raise RuntimeError('Cannot wait in cyclic BD mode')`
   （`:473-474`，是函数**第一句**）和引擎错误分支。结论有两条，都是可核对的：
   ① **cyclic 或以 `raise` 收尾的流程会挂住一张 BD 表**——但要说清量级，别把它当成"一路涨的漏"：
   下一次 `transfer()` 在 `:384` 重新绑定 `self._descr`，旧表引用计数归零后由
   `__del__ → freebuffer()`（`buffer.py:62-63`）释放，所以**每通道最多残留一张**，不是每笔累积一张。
   一张的大小是 `_num_descr × 64 B`，而 `:376-378` 保证了至少 2 个描述符（`:375` 的注释原话是
   "We need to always have at least two descriptors!"，`:376-378` 的做法是把 `blk_size` 折半凑够两个）——
   所以**最小的"一块一次传完"也是 2 个描述符 = 128 B 起**；把它叫"单描述符传输"是把这个数
   挂到了错的对象上。所以"掉了 200 MB"**不该**归因到这里，
   这条能帮你排除它：`_num_descr × 64 B` 与观测差值差几个数量级时，去查 `buffers-and-cache.md` §2
   的另外两种来源（远程模式、真的长生命周期引用）。
   反过来，如果你的差值恰好是 `k × 128 B` 这种量级、且 `stop()` 之后
   `dma.sendchannel._descr is not None`（`:254` 置初值、`stop()` 不清），那就是这条；
   想让还表成为确定动作：收尾时补一次**非 cyclic** 的 `transfer()` 再 `wait()`，
   或者让驱动对象离开作用域。
   ② 清 `_active_buffer` 只有两处，且都在等待函数**末尾**（`wait()` 里 `:522` 是注释、
   真正赋值在 `:523`；`wait_async()` 在 `:554`），除此之外没有人替你清它——你在 `with` 退出之后
   驱动仍握着那个引用——下一次 `wait()` 会对它 `invalidate()`，而那块内存已经还回池子了。


   **但 micro 例外，而且例外得很干净**：`self._micro and self._sg` 直接
   `raise UnsupportedConfiguration("Micro and Scatter-gather modes not supported
   simultaneously.")`（`lib/dma.py:625-626`）——micro 的 AXI DMA **不可能**是 SG，
   所以它一定走上面那条带长度检查的 SDMA 路：超限会报，不会静默拆块。
   读 `ip_dict[name]['parameters']['c_micro_dma']` 与 `c_include_sg` 两个参数就能确定你在哪条路上，
   别靠"没报错"猜。micro 下 `_max_size` 是 `data_width × c_mm2s_burst_size`
   （`:664-666`/`:721-723`），与 `buffer_max_size` 是两个数，这是"上限到底问谁"最容易搞混的一处。

   还有一个**共用同一个循环**的坑要说在这里，因为它就长在拆块的那段代码里：描述符地址在
   `:390-428` 的循环里算，而这个循环 cyclic 与非 cyclic 都走。**这一族按版本分三档，别写成"3.1 一个版本"**：
   3.0.1 低 32 位在 `:413`、高 32 位在 `:415`，**两半都漏加 `start`**（最坏的一档）；
   3.1.2 低 32 位在 `:417` 漏加、高 32 位 `:419` 是加的；4.0.0 两半都补上了（`:417` 起）。
   所以 SG 上**任何 `start != 0` 的传输**在 3.0.1/3.1.2 上都受影响，不只是 cyclic 模式，
   而 3.0.1 上连"高字"都是错的（症状会更像整块地址跑到别的内存区域去）。
   对照面：SDMA 那一侧两版都正确（`:157` 与 `:160` 低字和高字都加了 `start`）。这正好给出一条
   不用仪器的差分实验——同一块缓冲、同一个 `start`，SDMA 搬对而 SG 搬错，就指到 `:417` 这一条；
   细节与两种症状的成因见 `versions-and-apis.md` §4。
3. **cyclic 只能用在 sendchannel，而且失败会留脏状态**：源码是先 `self._cyclic = cyclic`（`:366`）
   **再**判 `if self._cyclic and self._tx_rx != DMA_TYPE_TX: raise RuntimeError('Cyclic BD mode
   only valid in sendchannel')`（`:368`）。所以在 recvchannel 上传 `cyclic=True` 抛异常的同时
   已经把 `_cyclic` 置上了；`stop()` **不清** `_cyclic`（`:303-312`），于是之后每次 `wait()` 都会
   `RuntimeError('Cannot wait in cyclic BD mode')`，直到下一次 `transfer()` 把它覆盖回 False。
   正确收尾：cyclic 模式没有 `wait()`，用 `stop()` 结束（docstring 原话 "use the stop() function
   to terminate DMA operation"）；误置之后要么重建通道，要么显式再 `transfer(arr)` 一次。
   **注意 `stop()` 只停引擎、不还 BD 表**（`:303-312` 里没有 `close()`），所以按这条收尾之后
   还有一张表挂着，什么时候还的见第 2.5 条——两件事别混成一句"cyclic 用 stop() 就干净了"。

4. **`start()` / `stop()` 才是该用的口，不要手写 DMACR**。写进去的值由**两个**条件决定，不是一个常数：

   | 通道 | 条件 | DMACR 写入值 | 行 |
   |---|---|---|---|
   | SDMA | 有中断 / 无中断 | `0x1001` / `0x0001` | `lib/dma.py:87-92` |
   | SG | 非 cyclic：有 / 无中断 | `0x1001` / `0x0001` | `:289-293` |
   | SG | **cyclic**：有 / 无中断 | `0x1011` / `0x0011` | `:294-298` |

   `0x1000` 是 interrupt enable（跟着 `self._interrupt` 走），`0x0010` 是**只有 cyclic 才多置**的一位。
   所以"SG 的启动字是 `0x1011`"是错的——SG 在普通模式下写的和 SDMA 完全一样。
   中断那一位**驱动已经替你置好了**，判据是 `description["interrupts"]` 里有没有 `*_introut`
   （`:671`/`:728`）；`stop()` 先写 `0x0000`（RS=0），cyclic 下再补一次复位（`:303-312`）。
   手写 DMACR 就是绕过上面这张表。

## 2. 完成判定与超时

`transfer()` 只是把请求交给引擎；真正的完成是 `wait()` 返回或状态位置起。没有中断时 `wait()`
是轮询（读 `SR` 判 `idle`/`error`），可能永远不返回。

**引擎自己提供的读数：SDMA 那一族是下面这四个，SG 那一族多一个 `halted`**（所以"四个"数的是
`_SDMAChannel` 的口，不是两族共用的口），全部是 MMIO 位，不需要中断也不需要 Python 侧的运气
（**行号是 3.1.2 与 4.0.0 的 `lib/dma.py`**，两版这几处逐行相同；**同一对掩码在 3.0.1 是
`:85`（SDMA `0x70`）与 `:281`（SG `0x770`）**，2.7.0 是 `:117` 与 `:321`——掩码与写法四版一致，
只有位置漂；这三组行号本机都自己 `grep` 过。`_offset` 是 MM2S=0 / S2MM=0x30。
**2.5.1 不能套这张表**，它连类都只有一个，见下面那段版本线）：

| 口 | 判据 | 能排除什么 / 不能排除什么 |
|---|---|---|
| `ch.running` | `SR & 0x01 == 0`（`lib/dma.py:69-71`） | 说明引擎已启动。**不能**说明搬过东西 |
| `ch.idle` | `SR & 0x02 == 0x02`（`:74-80`） | 说明这一笔停了。**不能**区分"正常停"与"报错停" |
| `ch.error` | SDMA：`SR & 0x70 != 0`（`:83-85`）；**SG：`SR & 0x770 != 0`（`:283-285`）** | 这才是"出错了"的位；只看 `idle` 会把错误当完成。SG 的掩码比 SDMA **多出 `0x100/0x200/0x400` 三个描述符层面的位**，所以别把 SDMA 的 `0x70` 抄到 SG 通道上 |
| `ch.transferred` | SDMA 读 `SR+0x28`（`:185/198`）；SG 由各描述符状态累加 `_descr[i,7] & 0x03FFFFFF`（`:514/545`） | 与请求的 `nbytes` 比：**这是唯一能证明"搬了多少"的口** |
| `ch.halted`（**只有 SG 有这一族**） | `SR & 0x01 == 0x01`（`:264-271`，docstring 写 "transfer can only be called when the DMA is halted"） | 它和 `running` 是**同一个位（`0x01`）的两种读法**，不是第二条独立证据。真正要记住的是 SG 的 `wait()` 退出条件写着 `if self.idle or self.halted:`（`:502`）——**"halted 但没 idle"也算等完了**，所以 SG 侧只盯 `idle` 会漏掉这一支 |

**但这两个写法都只在 `wait()` / `wait_async()` 内部发生**（上面那四处行号全在这两个函数体里），
而 `transfer()` 会先把 `self.transferred` 清成 0（`:155`、`:445`）。
所以**"发起搬运之后、等之前"读它，结构上必然读到 0**——它不是"没搬"的证据，两种通道都一样。
正确的顺序是 `transfer()` → `wait_with_timeout()`（或 `wait()`）→ 再读这四个口；
如果 `wait()` 会挂住不能调，那就先看 `idle`/`error` 两位再决定，而不是拿 `transferred == 0` 当结论。

**而 `transferred` 这个口自身还有版本线，方向对旧镜像不利。** 在 `pynq/lib/dma.py` 里数
`grep -c "self\.transferred"`：2.5.1 是 **0** 处，2.7.0、3.0.1、3.1.2、4.0.0 各 **10** 处。
**2.5.1 的通道对象上不止没有这个口——连 `error` 都没有。** 那一版的类是 `_DMAChannel`
（`lib/dma.py:42`，SDMA/SG 还没分成两个类），整份文件里只有**两个** `@property`：
`:65-66` 的 `running` 与 `:72-73` 的 `idle`（`grep -n "def error"` 在 2.5.1 上打回 **0** 行；
`grep -n "0x70"` 也是 0 行）。上面那张四口表在 2.5.1 上只取到 `running`/`idle` 两个，
写 `ch.error` 与写 `ch.transferred` 得到的都是 `AttributeError`，不是 0、也不是 `False`。
**所以"先看 `idle`/`error` 两位再决定"那条在旧镜像上要退化成只看 `idle`**——
而 `idle` 分不清"正常停"与"报错停"，这正是这张表警告过的那件事。
两种替代：自己读完成长度那个寄存器（`SR+0x28`；2.5.1 的通道里握着 `self._mmio` 与 `self._offset`，
`:56-57`，读法按本页 §2 的显式 `MMIO` 口），或者
`getattr(ch, "transferred", None)` 把"这个版本没有这个口"与"这一笔搬了 0 字节"分开报——
**别把 `AttributeError` 或 `None` 读成"搬了 0"**，那是两个不同的结论，
前者是测量口不存在，后者才说明引擎没动。

`wait()` 会把 DMASR 的错误位翻成**逐通道不同数量**的句子，照抄下来当分诊表用：

SDMA（`lib/dma.py:170-181`）三条：

| 抛出的 | DMASR 位 | 通常的真实原因 |
|---|---|---|
| `RuntimeError: DMA Internal Error (transfer length 0?)` | `0x10` | 给了零长度 / `nbytes` 算成 0 / 切片后 `array.nbytes - start == 0` |
| `RuntimeError: DMA Slave Error (cannot access memory map interface)` | `0x20` | 目的/源地址上有从设备拒绝访问（缓冲区被释放后继续用、SMMU 没映射） |
| `RuntimeError: DMA Decode Error (invalid address)` | `0x40` | 地址段上根本没有从设备——**这一条最常被误读成"设计坏了"** |

SG（`lib/dma.py:477-501`）**另外还有一族描述符层面的**，位是 `0x100/0x200/0x400`，措辞也不同：

| 抛出的 | 位 | 含义 |
|---|---|---|
| `Scatter-Gather Internal Error (re-used completed descriptor)` | `0x100` | 复用了已经完成的描述符——通常是前一次没 `stop()` 就再 `transfer()` |
| `Scatter-Gather Slave Error` | `0x200` | 描述符指向的**内存**访问被拒 |
| `Scatter-Gather Decode Error (invalid descriptor address)` | `0x400` | 描述符**表本身**的地址不在段上（BD 基址/`_descr` 映射问题，不是数据缓冲区的地址问题） |
| `RuntimeError: DMA Error in descriptor` | 由 `wait()`/`wait_async()` 抛：条件是 `if self._descr[i, 7] & 0x30000000:`（`:512-513`、`:543-544`）——**那几位被置起来才抛**，不是"完成位缺失" | 引擎在描述符上报了错：长度、启动顺序或门控没对上。**注意这条出口不会先 `stop()`**（见下面那条），读 `error`/`idle` 再决定下一步 |

也就是说 SG 上"报的是数据地址错"还是"报的是描述符表地址错"是可分的，这两类的修法完全不同；
把它合并成一句"DMA 报错了"会浪费一小时。

所以"引擎到底停没停、为什么停"是有读数的，不要靠 `wait()` 有没有返回来猜：

```python
print(ch.running, ch.idle, ch.error, ch.transferred)    # 四个一起打，缺一个都可能误判
```

但这四个数是**引擎自己那一侧**的读数：它们能证明"DMA 搬了 N 字节、并且现在停下来了"
（这就是 `debug-triage.md` §1 那三层里的"驱动报完成"那一格），**不能**证明 PL 里的消费者用了这些数据——
那一格要 PL 侧自己的计数或端到端比对。两格分开报，别用前者冒充后者。

**`wait_async()` 不能作为"中断接好了"的读数。** 它是**类级**的 `async def`，
在两个通道类里各有一份（3.1.2 与 4.0.0 都在 `lib/dma.py:189`（`_SDMAChannel` 里）与 `:525`
（`_SGDMAChannel` 里）；这两个类自己的定义行是同文件 `:16` 与 `:202`），
跟中断有没有接上无关，`hasattr()` 永远为真。
`DMA` 类 docstring 里那句 "If interrupts have been enabled and connected for the DMA engine then
`wait_async` is also present"（`:564-565`）**与实现不符**——按它写判定，得到的是一条出生以来不会红的
判据。中断通路真正的凭据是实例状态与元数据：

```python
bool(dma.sendchannel._interrupt)    # 通道内部真正用的那个判断
dma.description.get("interrupts", {})    # 期望看到 'mm2s_introut' / 's2mm_introut'
```

`DMA` 构造时就是拿 `"mm2s_introut" in self.description["interrupts"]` 决定要不要把中断传进通道
（`:671`、`:728`）。没接中断却去 `await wait_async()`，`self._interrupt` 是 `None`——但**只在引擎
还没空闲时**才会走到 `await self._interrupt.wait()`（`:193-194` 先判 `while not self.idle:`）：
如果这时通道已经闲下来，它连 `_interrupt` 都不碰就正常返回。所以"没接中断的 `wait_async()`"既可能
抛 `AttributeError: 'NoneType' object has no attribute 'wait'`（`:532-533` 同理），也可能一声不响地
返回，取决于调用时机——**两种都不是"中断丢了"的证据**。要么先确认 `_interrupt` 不是 None，要么
根本别在没有中断的位流上用 `wait_async()`。

要超时就自己包，但**必须知道代价**：

```python
import threading

def wait_with_timeout(ch, seconds):
    box = {}
    def _w():
        try:
            ch.wait(); box["done"] = True
        except Exception as e:
            box["err"] = e
    t = threading.Thread(target=_w, daemon=True); t.start(); t.join(seconds)
    return box.get("done", False), box.get("err")
```

超时之后这个线程**不会被杀掉**：`ch.wait()` 里那个 `while True` 还在轮询 MMIO。
它从此持续抢 GIL 和 AXI-Lite 带宽。**这两半的证据层级不同，别合成一句**：
抢 GIL 这一半本机在主机上量过（桩 MMIO，Windows）：起一个忙轮询线程之后，主线程同类循环的耗时
从 2.7 ms 涨到 16.4 ms——那两个毫秒数是**这一台主机 + 这一个解释器**的读数，随机器与版本而变，
不要当事实搬运；可复现的是方向与机理。
**抢 AXI-Lite 带宽、"把这个进程之后所有吞吐读数都污染掉"是板上行为，本机没有板，未测**
（要它在板上变成读数：同一进程里先测一次吞吐基线，再挂一个忙轮询线程重测同一段，两次口径写在一起）。
所以规则是：**用它测量过的进程不要再用来测吞吐**；测吞吐的窗口要么开独立进程，
要么先确认没有遗留的等待线程（`threading.enumerate()` 打印一次）。

超时之后**不要**接着读缓冲区（那是"半成品"）。**"把通道停下来"在驱动这一族里不是安全动作——
两处自旋要一起避开**（下列行号 3.1.2 与 4.0.0 完全相同，逐条回读核对过）：

- `stop()` 写完 RS=0 之后是 `while self.running: pass`（SDMA `lib/dma.py:97-101`、SG `:303-312`；
  SG 在 cyclic 下还多两次复位写 `:308-309`（`:306` 那行是注释 "In Cyclic BD mode the DMA requires a reset if stopped"，别把它算进"两次写"）。
- `start()` 那侧对称地有 `while not self.running: pass`（SDMA `:93-94`、SG `:299-300`）。

更要紧的是**你自己不调也会进去**：`_SGDMAChannel.transfer()` 内部就 `self.stop()`（`:387`），
`__init__` 也调（`:257`）。**但 `wait()` / `wait_async()` 的报错分支不调它**——
`:517`、`:548` 那两次 `self.stop()` 前面都写着 `# Ensure engine is idled`，位置在
描述符循环**跑完之后**（`:516-517`、`:547-548`），而抛错的那些出口
（`:481-500` 那族 SR 位、`:513`/`:544` 的 `raise RuntimeError("DMA Error in descriptor")`）
都在到达那两行**之前**就离开函数了。所以"任何驱动调用都可能把你带进 `stop()`"这句要反过来读：
**发起过传输却报错的那条路不会替你停引擎**，`stop()` 只在 `transfer()`/`__init__`/正常收尾时发生；
而一旦你手动去调 `stop()`，卡住的是它里面那两个无界循环（上面两条）。
两种情形都要防，防法不同：报错之后先读 `error`/`idle` 决定要不要自己写 RS=0，
而不是指望库已经帮你停过。
源码撑得住的唯一手动动作是**自己动寄存器**：用 `MMIO` 写 DMACR 的 RS=0（cyclic 下再写 `0x0`←`0x0004`，
`:308-309` 正是驱动自己做的事），然后**自己带截止时间轮询 SR**。
边界要说清：源码能证的只有**这两个循环没有上界**；"引擎报了 Slave Error 之后是不是永不清 `running`"
是板端行为，本包没有那边的读数（需板端）。这条路也绕开了 §1 第 4 条那张表，且 overlay 复位 PL 时会一起冲掉。

**引擎报错之后怎么恢复到"能再用"**，按源码能确证的只有这几步：

1. **别用驱动调用去"停"**：`stop()`、`transfer()`、`wait()`/`wait_async()`、`start()` 内部都会走到那两个
   无上界的循环（上面刚写过）。第一步只能是 `MMIO` 写 DMACR 的 RS=0（cyclic 再 `0x0`←`0x0004`），
   自己带截止时间轮询 SR；**SR 平静之后**才谈后面几步。SG 的 `stop()` 即使能返回也**不重建描述符环**
   （`:303-312` 里没有 `close()`）。
2. 重建环只能靠 `transfer(...)`：`_SGDMAChannel.transfer()` 会重算条数并重新分配 `_descr`（`:373-386`），
   `_cyclic` 也被这次调用的实参覆盖回去（`:366`）——这也是"cyclic 误用之后必须再 `transfer()`
   或换别的通道"的原因。**但它开头就是 `self.stop()`（`:387`）**，所以这一步必须排在第 1 步之后，
   不然它就是新加的挂点。
3. `start()` 那侧同样有 `while not self.running: pass`（SDMA `:93-94`、SG `:299-300`）：
   要么先用 `MMIO` 写 RS=1 再自己轮询，要么确认引擎确实会响应。起来之后**重新读那四个状态口**
   （`error` 归零、`running` 为真）再决定发起传输。
4. 本包给不了的：DMASR 的粘滞错误位要不要显式清、"引擎卡在途事务"时用户态有没有撤回手段——
   这两条没有源码或读数支撑，把"卡住"当成需要复位 PL 的那一档
   （见 `SKILL.md` §4 边界表"一笔访问卡死之后怎么撤回"那一行，按行名找，别按"第几行"找）。
   顺带撤一条旧写法：**`write(DMACR, 0x4)` 不是"网上抄来的危险写法"**——驱动自己就这么写
   （`self._mmio.write(0x0, 0x0004)`，`:308`），cyclic 的复位正是它做的。本包先前那句"别照抄"说反了。


## 3. 一次端到端搬运的最小正确写法

**这一节是这段骨架的规范版本**；`first-bringup.md` §5 是它的镜像（只差在打印哪些读数）。
改这里的等待方式或比对方式时，**同步改那一页**——两边不一致时，本节的四条边界与
`debug-triage.md` §3 第 3 条的完成判定会失去同一个出处。


```python
import numpy as np
from pynq import Overlay, allocate

ol = Overlay("design_1.bit")
dma = getattr(ol, "axi_dma_0")
if dma.sendchannel is None or dma.recvchannel is None:
    raise SystemExit("channel not enabled in this bitstream")
n = 1024 * 768
with allocate((n,), dtype=np.uint8) as src, allocate((n,), dtype=np.uint8) as dst:
    src[:] = np.arange(n, dtype=np.uint8)    # 直接当 ndarray 用
    src.sync_to_device()    # CPU→PL
    dma.recvchannel.transfer(dst)    # 惯例上先挂收侧再发发起侧；驱动里两个通道是独立对象、
    dma.sendchannel.transfer(src)    # 源码没有任何先后耦合（先后是否有害是板上行为，本包未测）
    # 本页 §2 定义的 wait_with_timeout 才是这里该用的东西：裸 wait() 没有 timeout 形参，
    # 引擎不返回时这一行会把整个进程挂住，而且不会给你任何读数。
    for who, ch in (("recv", dma.recvchannel), ("send", dma.sendchannel)):
        done, err = wait_with_timeout(ch, 5)
        print(f"{who}: done={done} err={err!r} idle={ch.idle} error={ch.error} "
              f"transferred={getattr(ch, 'transferred', None)}")
    dst.sync_from_device()    # PL→CPU
    got = np.array(dst)    # 拷一份：出了 with 缓冲区就释放了
    ref = np.arange(n, dtype=np.uint8)    # 与 PL 语义一致的参考实现
    bad = np.nonzero(got != ref)[0]
    print(f"checks={n} mismatches={bad.size}" + ("" if bad.size == 0 else
          f" first={bad[0]} got={got[bad[0]]} exp={ref[bad[0]]}"))
```

注意 `got = np.array(dst)` 必须在 `with` 里面完成：出了块作用域 `freebuffer()` 已经执行，
再读 `dst` 是 `buffers-and-cache.md` §2 第 1 条说的 UB。这条不是风格问题。**下面两句是机理与告诫，
不是本机的读数**（没有板子，也没量过"什么时候开始读到脏值"）：释放后再读在实践中常常"看起来还对"，
而"对"本身不构成证据——页什么时候被下一次 `allocate` 复用不由驱动承诺，所以**判据只能是"你有没有在
释放之后再读"，不能是"读起来还对"**。
