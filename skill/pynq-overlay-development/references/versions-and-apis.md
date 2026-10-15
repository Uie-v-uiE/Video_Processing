# 版本面与在目标上重导 API

PYNQ 的公开面在 **2.4→2.5.1** 与 **2.5.1→2.7** 各换过一次实现（不是一条 2.7 线，逐项见 §2.1），**同一份 import 在板端与主机远程模式
下拿到的类不是同一个**。所以签名要按"你这台板子、这个模式"取，不按记忆写。

## 1. 先固定三件事再写任何一行代码

```python
import sys, pynq, inspect
print(pynq.__version__, pynq.__file__)    # 版本与装在哪
print(sys.executable)    # 板端 python 还是主机 venv（远程模式）
from pynq import Interrupt; print(Interrupt.__module__)
```

第三行不是客套：`pynq/__init__.py` 里 `Interrupt` 是**按环境二选一的别名**——源码写的是
`if os.environ.get("PYNQ_REMOTE_DEVICES", False):` 这一支导 `pl_server.remote_device.RemoteInterrupt`，
否则导 `interrupt.Interrupt`（`__init__.py:16` 起的那个 `if`；同一个 `if` 在 3.1 里到 24 行结束，
在 4.0.0 里到 28 行结束，因为远程分支多了 4 行，见下）。同名不同实现，`wait()` 的行为、
超时怎么加，全都跟着变。远程那一支在 4.0.0 里多这 4 行：`:20` `import sys`、`:21` 从 `.remote`
导入 `xrfdc/xrfclk`、`:22-23` 把它们塞进 `sys.modules`（3.1 没有），所以"射频时钟库怎么用"
也随模式与版本变。反过来，`DataRecorder`/`get_rails` 只在**非远程**那一支导入
（4.0.0 `__init__.py:28`、3.1.2 `:24`——**行号随版本漂，名字别按行号找**），
远程模式下这两个名字根本不存在——列导出面时它们是"板端专属"，不是通用面。
同类的事在 `PL`、`Device` 上也有：`pynq.pl_server.Device.active_device` 决定缓冲区实际分配在哪一侧。

**这一节只回答"我此刻在哪种模式、这个名字指向哪个类"**；两种模式的**行为差别**不在这里，按症状去
这两处取：缓冲区别名与释放路径 → `buffers-and-cache.md` §1 里 `target=None` 走 `active_device` 那一条
与 `buffers-and-cache.md` §2 第 2 条（远程那侧给你的是 `RemoteBuffer`，释放是一次 gRPC 调用，主机会话断了就在板上留残留；
它的 `coherent` 按其 docstring 恒为 `False`，别照搬板端的一致性假设）；
中断那侧 → `interrupts.md` §2 末尾"远程开发模式下这一族还有三件额外的事"。

## 2. 导出面：这一版到底把名字给了你什么

3.1 与 4.0.0 的 `pynq/__init__.py` 完整导出列表（照抄 import 语句，不是"主要的几个"；
下面这份列的是**能 `from pynq import X` 的那个 X**，不含两条模块级导入
`import os`（`:4`）与 `from . import pl_server`（`:5`）——`pynq.pl_server` 作为模块是可用的，
它不在列表里只是因为它是模块不是名字）：

```
Bitstream, allocate, DeviceTreeSegment, MMIO, DefaultHierarchy, DefaultIP, Overlay,
UnsupportedConfiguration, PL, Device, Clocks, Register, GPIO, Interrupt, UioController,
DataRecorder, get_rails    # GPIO/Interrupt/UioController 随模式换实现；DataRecorder/get_rails
    # 只在非远程那一支导入 —— 远程模式下这两个名字不存在
```

**`PynqBuffer` 不在里面**——`__init__.py` 从 `.buffer` 只取了 `allocate`。类在 `pynq.buffer.PynqBuffer`，
要用 `from pynq.buffer import PynqBuffer`。这条最容易踩，因为 2.x 教程里那个分配器返回的东西
（教程常写作 `xlnk.cma_alloc(...)` 的结果，2.5.1 `xlnk.py:169` 就是它本身）常被笼统叫作 "buffer"，
于是没人写过它从哪个模块来。


还有一条会被误读成"模块没了"：`pynq.ps` 在 3.x/4.x **仍然存在**，只是从它这里导出的是 `Clocks`
（`from .ps import Clocks`），`Register` 搬到 `pynq.registers` 了。所以
`from pynq.ps import Clocks` 能过、`from pynq.ps import Register` 不能过——报的是 `ImportError`，
但根因是搬家不是删除。`Clocks` 用来读 PL 侧时钟频率，见 `debug-triage.md` §2 树 A。

### 2.1 2.x → 2.7 的迁移线（2.5.1 起各列都按源码 `__init__.py` 逐条对过；
**2.0/2.4 那一列对不了**——现存语料没有那两版的树，那一列是早先抄下的原文，标「射程外」用）

| 现象 | 2.0 / 2.4 | 2.5.1（整树） | 2.7.0（整树） | 3.1.2 / 4.0.0 |
|---|---|---|---|---|
| `from pynq import Xlnk` | 有 | **有**（2.5.1 `__init__.py:32`） | 没了 | 没有。**替代品是同一格就已经存在的 `pynq.allocate`**（2.5.1 `__init__.py:45` 是转发行，见下面那条注）加上下文管理器。别指望改名就能跑：3.x/4.x 的**公开面里没有 `cma_*`**——3.1.2 只剩 `lib/logictools/trace_analyzer.py` 里的私有属性 `self._cma_array`，4.0.0 连这个也归零；2.x 那套成员名在 2.5.1 `xlnk.py` 里逐个查得到（`cma_alloc` 2.5.1 `xlnk.py:169`、`cma_array` 2.5.1 `xlnk.py:255`、`cma_get_phy_addr` 2.5.1 `xlnk.py:300`、`cma_free` 2.5.1 `xlnk.py:367`、`cma_stats` 2.5.1 `xlnk.py:388`，五处都是该文件的 `def` 行；**每个号都要自带版本**，3.x/4.x 已经没有 `xlnk.py`，只标一次会被读成后面几条也归那两版），那是**旧版的参照**不是新版的能力 |
| `Register` 从哪来 | `from .ps import Register` | 同左（2.5.1 `ps.py:34` 自己 `from .registers import Register`，所以 `pynq.ps` 里确实有这个名字） | 改成 `from .registers import Register`（2.7.0 `__init__.py:30`），`ps.py` 不再转进来 → `from pynq.ps import Register` 从这一版起 `ImportError` | 同 2.7 |
| `Bitstream` 从哪来 | `from .pl import Bitstream` | **已经是** `from .bitstream import Bitstream`（2.5.1 `__init__.py:39`） | 同 2.5.1 | 同 2.7 |
| `allocate` / `DeviceTreeSegment` / `Device` | 都没有 | **三者都已存在**（2.5.1 `__init__.py:45/37/46`） | 同 | 都有 |
| `PL_SERVER_FILE` | 原文是 2.0/2.4 的 `__init__.py` 里 `from .pl import PL_SERVER_FILE`（**本包现存语料只到 2.5.1**，这一格是早先抄下的原文，现在重验不了，别当读数用） | **全名 0 命中，但这一族还在**：同前缀的 `PL_SERVER_TEMPLATE` 就在 `pl_server/server.py:47`，值 `'/tmp/pynq.{}.socket'`，`:102` 与 `:520` 用它拼 socket 路径（这三个行号出自 2.5.1 那棵树；本包判定用的副本是 3.1/4.0.0，这两格都**射程外**——要引它得回到同一版重新取行号） | 同 2.5.1：`pl_server/server.py:46` 有 `PL_SERVER_TEMPLATE`（同一句射程外声明） | **连前缀都是 0 命中**：`grep -rn "PL_SERVER"` 在 3.0.1/3.1.2/4.0.0 三棵整树里一行没有，而同一条命令在上面两棵 2.x 树里各命中数行——这就是证明"扫描看得见文件"的正向对照。所以迁移线是**先改名、后消失**，不是一步消失 |

**这张表有两处按行号引用会把结论搬错，分开钉一下**：

- `__init__.py:45`（2.5.1）指的是 `from .buffer import allocate` 这一行——**一条 re-export**：
  名字确实能从这里 `from pynq import allocate` 引到，但干活的是 `buffer.py` 里的 `allocate`。
  同表 `Register` 那格是同一个意思（2.5.1 `ps.py:34` 也是转发）——**引用能力时要引实现那一行，
  或者两处都标出来**，只标转发行会被读成"能力在这里"。
- "公开面里没有 `cma_*`"与"`self._cma_array` 有 8 处命中"**数的不是同一个对象**：前者是能
  `from pynq import X` 的名字，后者是 `grep -rc 'cma_'` 的文本命中。后者本机按版本各数一次：
  2.7.0 给 **8**、3.0.1 给 **8**、3.1.2 给 **8**（三处都只在 `lib/logictools/trace_analyzer.py` 这一个文件里）、
  4.0.0 给 **0**。所以那 8 处**不是 3.1.2 特有的残留**，写成"只剩 3.1.2 还有"就把一次跨版本读数
  压缩成了一版。

判"这一族还有没有替代物"要**按前缀扫，不按全名**：只搜 `PL_SERVER_FILE` 得 0 只能写"这个拼法不在"，
把它写成"这个能力没了"就把一次范围不足的扫描当成了事实。正确顺序是先 `grep -rn "<前缀>"` 拿到全部
候选、再逐个读它的位置与用途；候选里出现别的拼法（上面那一格就是这么找到的）。



所以分界不是一条，是两条：**`Xlnk` 死在 2.5.1→2.7 之间**，其余四项（`Register` 的来源、
`Bitstream`、三件新导出、`PL_SERVER_FILE`）**都在 2.4→2.5.1 之间就变完了**。
手上是 2.5 的板子照着"2.x 教程"改代码，会比照 2.0 的教程踩更多坑——这一列是实测补进来的，
之前这张表把 2.5.1 归到了 2.0/2.4 那一侧。


所以"我的代码在旧板上跑过"不等于能在新板上跑；反过来，**把 2.x 教程整体搬进 3.x 之前先按这张表
逐项查名字**，比查教程快。

### 2.2 关于 `from pynq import MM`：这个名字不存在，别去找它的替代品

这条单列出来，因为它在若干教程与旧工程里当作"2.x 的 MMIO 口"流传。两个互相独立的视图都看不见它：


1. **导出清单本身**：3.1 的 `__init__.py:9` 那一行是 `from .mmio import MMIO`——同一张清单里有
   `MMIO`、没有 `MM`。这一条同时是另一次扫描的正向对照：**清单看得见 `MMIO`，所以它不列 `MM`
   是"没有"，不是"没扫到"**。
2. 同一批（含各版本的 `mmio.py`）里搜 `^class MM\b` 是 0 个结果——注意 `grep "class MM"` 会命中
   `class MMIO`，**必须用词边界**，否则你会以为自己找到了。

如果你在某个仓库里看到 `MM(...)` 被
import 成功，那它是**那个仓库自己的封装**（或某个非本包覆盖的分支），不是 PYNQ 的 API；要替代它，
用 `MMIO(base_addr, length).write(offset, data)`，基址从 `ip_dict` 取（`mmio-registers.md` §1、§3）。

## 3. 在目标上重导一次形状（命令在这段里，跑出来的读数只对你这一台成立）

`pynq` 的导出面随版本与运行位置变，所以形状要在**你这一台**上现导，不要照抄任何文档
（包括本文）：

```bash
python3 -c "import pynq, sys; print(pynq.__version__, pynq.__file__); print([n for n in dir(pynq) if not n.startswith('_')])"
python3 -c "import pynq; print(pynq.Interrupt.__module__)"    # 板端/远程是两个不同的类
python3 -c "import pynq; print([a for a in dir(pynq.MMIO) if not a.startswith('_')])"
```


```python
import sys, pynq

if getattr(pynq, "__file__", None) is None:
    print("NOT_RUN  pynq 是 namespace package：sys.path 上有个同名目录，装的根本不是它")
    sys.exit(3)

def resolve(dotted):        # 名字写全路径（pynq.MMIO.read，不是 MMIO.read）：从 pynq 往下走
    cur = pynq
    for part in dotted.split(".")[1:]:
        if part not in dir(cur):        # 不用 hasattr：`pynq.PL` 是实例，它走 `__getattr__`，
                                        # 有副作用还可能直接抛（见 overlay-metadata.md §3 末条）
            return "ABSENT"
        try:
            cur = getattr(cur, part)
        except Exception as e:           # 取它本身就做事/抛——这是第五种状态，不是 ABSENT
            return "RAISED %s: %s" % (type(e).__name__, e)
    return "OK" if cur is not None else "NONE"

for n in ["pynq.MMIO.read", "pynq.PL.ip_dict", "pynq.Xlnk"]:
    print(n, resolve(n))
```

`RAISED` 这一态要单独有：本机把 `PL.ip_dict` 做成一个会抛 `RuntimeError("Overlay not currently
loaded")` 的属性再跑同一段，未加 `try` 之前脚本在第二个名字上直接崩（退 1，第三个名字根本没打到），
加了 `try` 之后三行都打完。**"没打到最后一条"不是"后面两条都不存在"**——这正是这一族最常见的假结论。

一次要查多个名字就把列表加长，别只查一个就下结论。
**这段代码给的读数是 `OK`/`NONE`/`ABSENT`/`RAISED` 四种**；表里的 `EXPECTED-ABSENT` 是**你拿着这张表判的**，
不是脚本判的——脚本对 2.x 专属名与被绑到实例上的属性同样报 `ABSENT`。

五种读数的含义。**上面那段只在"装的根本不是 pynq"时给非 0 退出码（`sys.exit(3)`），其余一律退 0**——
所以退出码只携带那一个信号，红绿要由你自己从打印出来的状态里取。
**接进 CI 时不能直接 `grep -q '^pynq\..* ABSENT'`**：脚本对"这版本就没有"的名字（2.x 专属名、
绑在实例上的属性）同样打 `ABSENT`，所以这条 grep 在一台**健康的 3.x/4.x** 上就是红的——
把它调绿只有一个办法（把名字从清单里删掉），而那之后它再也红不了，等于没装门禁。
能同时做到"好安装为绿、真出问题为红"的写法是把清单分成两份，只对第一份判：

```bash
python probe_names.py > names.txt          # 每行 "<名字> <状态>"
# must_have.txt = 这一版应当解析得到的名字；expected_absent.txt = §2.1 迁移表能解释"为什么没有"的名字
grep -F -f must_have.txt names.txt | grep -q ' ABSENT' \
  && echo "VERDICT: FAIL missing_api" || echo "VERDICT: ok"
```

这条判据要按老规矩自证能红：在同一台机器上往 `must_have.txt` 里塞一个**故意写错的名字**
（`pynq.MMIO.raed`），它必须打出 `VERDICT: FAIL`；把同一个名字改对之后它回到 `ok`。
只跑一次绿不算这条门禁存在。

| 状态 | 含义 | 拿它当什么 |
|---|---|---|
| `OK` | 这版这台上解析得到 | 可以用 |
| `NONE` | 名字**在**，当前值是 `None`（典型：还没 download 任何 overlay 时 `pynq.PL.ip_dict` 会走到 `pl.py` 里那条"什么都不 return"的分支） | 不是缺 API，是**没加载**；先去加载或换 `download=False` 那条路 |
| `EXPECTED-ABSENT` | 这版本就没有，且原因已知：2.x 专属名、或在 `__init__` 里绑到实例上的属性（`MMIO.write`、`MMIO.array`、`DMA.buffer_max_size`） | 换写法，不是换版本 |
| `ABSENT` | 解析不到且没解释 → 你的代码到这儿会 `AttributeError` | 这一条才该让流水线红 |
| `RAISED <类型>: <消息>` | 名字在表里，但**取它的值本身**在做事/抛（`__getattr__` 那一族） | 它同时告诉你"存在"与"要先满足的前置条件"；**不能并入 `ABSENT`** |

两个坑：

- **`import pynq` 成功不等于装对了。** 只要 `sys.path` 上有一个叫 `pynq` 的**目录**，Python 就把它当 namespace package 导入成功，
   然后所有名字全部解析不到，看起来像"版本不对"。脚本对这种情况单独报 `NOT_RUN` 并退出 3
   （判据是 `pynq.__file__ is None`）。本机实测：`PYTHONPATH` 指到含 `pynq/` 文档目录的一层，
   旧版本脚本就是这么被骗的。
- 判断一个方法**在这台设备的实例上**能不能用，用 `print(obj.write)`（要么给你 bound method，要么
   当场抛，两种都是读数）或 `'write' in dir(obj)`——**`dir` 要用在实例上**，不要用在类上
   （`MMIO.write` 是 `__init__` 里现绑的，`mmio.py:70-84`，类目录天生看不见）。
   **`hasattr` 不要用**：被 `__getattr__` 接住的对象上它会触发驱动构造（有副作用），而且只吞
   `AttributeError`，别种异常直接往外抛（见 `overlay-metadata.md` §3 末条）。

同理 `pynq.Overlay.remove`：3.1 与 4.0.0 的 `overlay.py` 里**没有** `def remove`（有
`bitstream.py:174` 的 `remove_dtbo()`、`overlay.py:394` 的 `free()`）。网上"换 overlay 就 `ov.remove()`"
写法在这两版上直接 `AttributeError`。正确的生命周期动作见 `overlay-metadata.md` §3。

## 4. 四个"教程没写但会咬人"的口径

- **`transfer(array, start=0, nbytes=0)` 的 `start` 是字节偏移。** 两版的 docstring 措辞不一样，
   这条差别本身就是线索：3.1.2 `lib/dma.py:130` 与 `:347` 写的是 "Offset into array to start"
   （没说单位），4.0.0 同一行改成 "Byte offset into array to start"。单位由代码定：`nbytes`
   用 `array.nbytes - start` 算（`:358`），对齐检查判的是 `physical_address + start`（`:359`）。
   而 3.1 的 SG 通道填描述符时**低 32 位漏加了 `start`**：3.1.2 `lib/dma.py:417` 是
   `(array.physical_address + i*blk_size) & 0xFFFFFFFF`，4.0.0 同一行是
   `(array.physical_address + start + i*blk_size) & 0xFFFFFFFF`（**尾巴上的掩码不要漏抄**）。更准确地说 3.1 交出去的是一个**混合地址**——
   低字用不带 `start` 的、高字 `(… + start + …) >> 32` 是带的（`:419` 两版相同）。所以当高位两边都是 0
   （低地址板的常态）时，症状是"长度对、内容从数组头开始搬、不报错"；一旦 `base+start` 跨了 4 GiB
   进位而 `base` 没跨，描述符地址就落到完全不同的区域，表现为引擎报错/DECERR 而不是静默错值。
   两种症状同一个根因，别按"哪个能复现"来判断版本。
   **这两句"症状"是从地址算式推出来的推断，不是读数**：本机没有板、没有跑过一次真实搬运，
   能给的只有代码层那两行（低字确实不带 `start`、高字带）。
   还有第三档要说全：**3.0.1 比 3.1.2 更坏**——3.0.1 的 `lib/dma.py:413`（低字）与
   3.0.1 的 `lib/dma.py:415`（高字）**都不加 `start`**，所以"高字带着 start"这个缓解条件在 3.0.1 上不成立
   （三档对照见 `dma-channels.md` §1）。
   **但"不报错"这句要说窄一点**：对齐检查判的是 `physical_address + start` 这个**和**
   （3.1.2 与 4.0.0 的 `lib/dma.py:359` **内容相同**——这两个文件只差 `:130`、`:347`、`:417` 三行，
   其余逐行对齐），而 3.1 交出去的描述符用的是**不含 `start` 的低字**——

   所以 `start` 让那个和变得未对齐时，3.1 上先在 `:359` 抛 `RuntimeError("DMA does not support
   unaligned transfers...")`，根本走不到静默错值；只有 `base` 与 `base+start` 都对齐（例如
   `start` 是位宽整数倍、或那一侧开了 DRE 跳过检查）才是"不报错但搬错"。
   差分实验要有开关才行：**这条走 SDMA 还是 SG 由元数据里的 `c_include_sg` 决定**
   （`:620-623` 读它；`c_micro_dma` 在 `:615-616`——注意它在读 SG 的那几行**之前**，
    互斥抛错另在 `:625-627`，micro 必是 SDMA），
   所以"同一块缓冲、同一个 `start`，SDMA 对而 SG 错"要拿**两个不同配置的 IP**（或同一工程
   改一次 SG 选项重新导出）来做，不是在同一个 overlay 上换个调用方式。
   两条范围要说清：`:417` 在 `:390-428` 那个描述符循环里，**cyclic 与非 cyclic 都走它**，
   所以中招的是"SG + `start != 0`"全体，不是只有 cyclic；SDMA 那一侧两版都对
   （`:157` 与 `:160` 低字和高字都加了 `start`）。这给出一条不用仪器的差分——同一块缓冲、同一个
   `start`，SDMA 搬对而 SG 搬错就指到这一条。用切片/带偏移的缓冲区前先确认版本。
- **`Clocks.get_pl_clk(i)` 在 3.1 上恒为 `None`。** 元类转发器把 `return` 写丢了
   （3.1.2 `ps.py:260-271`），4.0.0 补回来（`ps.py:354-365`）。所以"FCLK 全 None"**不是**时钟没开，
   是版本读数；要读频率用 `Clocks.fclk0_mhz`…`fclk3_mhz` 那四个 property（两版都有，
   3.1.2 `ps.py:153/180/207/234`，4.0.0 `ps.py:247/274/301/328`，走的是会 return 的实例方法
   `_ClocksBase.get_pl_clk`，3.1.2 `ps.py:325-345`）。反过来这也是一个不用查版本文件的判别式。
   设计侧那一路看 `ol.clock_dict`，两版的键不同：3.1.2 `overlay.py:424-426` 是 `divisor0`/`divisor1`，
   4.0.0 `overlay.py:425` 是 `frequency`。

- **远程模式下路径解析发生在板端。** `.bit`、`.hwh`、`.xsa`、`.dtbo` 必须存在于**板子**能解析到的
   目录；从主机传一个主机路径进去，`FileNotFoundError` 是板端抛的、回传到你的终端，容易误读成
   "我的文件不见了"。判据：先在板端 `python3 -c "import os; print(os.path.abspath(...))"`。



- **Jupyter 会钉住对象。** notebook 的 `In/_/异常 traceback` 都持有旧 `Overlay`，
   旧对象不被回收 → 它的 mmap、UIO fd、驱动实例一直附着，与新 overlay 抢同一批地址。
   换 overlay 之前 `%xdel old_overlay` 并重启 kernel，能把"软件状态没清"和"硬件真坏了"分开。
   **但这一招只管软件侧**：如果卡住的是一笔已经发出去、永远等不到响应的 AXI 事务，那已经烧进内核
   上下文里了，重启 kernel 救不回来（`SKILL.md` §4 边界表里"一笔访问卡死之后怎么撤回"那一行）。先用"能不能读到东西"把这两种
   分开，再决定要不要断电。
