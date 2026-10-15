# 缓冲区与一致性：分配、释放、cache、漏量

本页管**谁持有内存**：`allocate` 的真实形状、释放的正确写法（`close()` 是废弃空操作）、缓存一致性的方向与判据、以及把“漏没漏”变成一个数。引擎那一半在 `dma-channels.md`。

## 1. `allocate` 的真实签名与默认 dtype

```text
def allocate(shape, dtype="u4", target=None, **kwargs)    # pynq/buffer.py:138（3.1 与 4.0.0 同）
```

- 默认 dtype 是 **`"u4"`**：源码 docstring 自己写着 "The default dtype is 32-bit unsigned int
   rather than float"。所以 `allocate((8, 1024))` 是 8×1024×4 = 32768 字节，不是 8192 字节。
   按 PL 的实际字宽显式给 dtype：字节流 `np.uint8`、32 位 `np.uint32`、64 位 `np.uint64`。
- 返回的是 `PynqBuffer`（`class PynqBuffer(np.ndarray)`，在 `pynq/buffer.py`；
   `from pynq import PynqBuffer` 是**取不到的**，见 `versions-and-apis.md` §2），**本身就是 ndarray**：
   可以直接 `buf[:] = arr`、`buf.reshape(...)`、切片；切片会跟着调整 `device_address/offset`
   （`__array_finalize__`，`buffer.py:50-57`：`self.device_address = obj.device_address + offset`，
   其中 `offset` 是**虚拟地址差**）。
   这条有个必须记住的后果：**切片的 `physical_address` 已经含了偏移**，所以要"从中间开始搬"就把
   切片对象本身交给 DMA（`v = buf[64:]; dma...transfer(v)`，对齐检查与 `transferred` 都按 `v` 记）。
   **手算 `buf.physical_address + 64` 并不会"绕过同步记账"，也不会让同步范围错位**：
   `flush()`/`invalidate()` 传的确实是 `self.offset` 与 `self.nbytes`（`buffer.py:104-114`，3.1.2 与 4.0.0 同形），
   而这两个量在切片视图上**就是视图自己的**——`__array_finalize__` 按
   `offset = self.virtual_address - obj.virtual_address`、`self.offset = obj.offset + offset` 重算
   （`:50-57`），而 `nbytes` 是 numpy 给视图的**元素数 × itemsize**。连续切片下它正好等于那段的字节数，
   所以"设备写的区间与被同步的区间不一致"这句对连续切片不成立（本页前一次就是这么写的，被源码反写）。
   **带步长的切片会反过来咬人**，本机直接用 `numpy` 量过：100 个 `u4` 的 `a`（`a.nbytes`=400），
   `a[64:]`→**144**、`a[10:20]`→**40**（都与区间一致），而 `a[::2]`→`offset=0`、`nbytes`=**200**，
   可这个视图真正碰到的字节铺满整个 400。`flush`/`invalidate` **在 Python 这一层交出去的是
   `(self.offset, self.nbytes)` 这一对连续区间**（`buffer.py:104-114` 那几行的原文，
   本机读到的是 `device.flush(self.bo, self.offset, self.virtual_address, self.nbytes)` 这一句）；
   **由此推"所以对 `a[::2]` 只覆盖前半段、尾部 200 字节没被 flush，而且不报错"——
   这一句是机理，不是读数**：再往下那层 C 绑定与驱动行为本机没打开过、也没板可测
   （要它在板上成为读数：分配一块、写一个跨距图案、`sync_from_device()` 之后看尾部是否还是旧值）。
   **注意可证的部分已经够用了**：numpy 那半边（`nbytes`/`offset`/`strides`）是本机量的，
   而"该同步的范围 ≠ 视图碰到的范围"这件事在 numpy 层就成立，所以不需要驱动那一层读数也足以
   得出"别拿带步长的视图去做同步"。
   可用判据（本机在同一份 numpy 上量过）：`a[64:]`、`a[10:20]` 的 `flags['C_CONTIGUOUS']` 是 `True` 且
   `__array_interface__['strides']` 为 `None`，而 `a[::2]` 是 `False`、`strides=(8,)`——**连续（无 stride）
   才意味着同步范围等于视图碰到的范围**。不连续时的两条出路：按**原始对象整段**做同步（牺牲一点带宽，
   最省事），或者重新申请一块连续的设备缓冲再把值拷进去。
   **别顺手写 `np.ascontiguousarray(v)` 当解法**，而且**先前这里写的理由也是错的**——
   原句"`subok` 默认为 `False`"当它有一个可以打开的开关；本机 numpy 2.5.3 上
   `np.ascontiguousarray.__text_signature__` 是 **(a, dtype=None, \*, like=None)**，
   **根本没有 `subok` 这个形参**（`"subok" in np.ascontiguousarray.__doc__` 也是 `False`），
   所以它不是"默认丢子类"，是**没有保留子类的选项**。
   用一份**照 4.0.0 `buffer.py:50-57` 逐行写**的桩（`offset = self.virtual_address - obj.virtual_address`、
   `device_address = obj.device_address + offset`、`self.bo = obj.bo`）在 `v = base[::2]` 上取四个读数，
   numpy 2.5.3、本机自己跑的：
   `np.ascontiguousarray(v)` → 类型 **`ndarray`**、连 `device_address` 这个属性都没有；
   `np.array(v, copy=True)` → 同样掉成 `ndarray`；
   **`v.copy()`** → 类型仍是子类，但 **`device_address` 变成 `268490416`、`offset` 变成 `54960`**
   （基址是 `268435456`，多出来的 `54960` = `0xD6B0` 就是那次拷贝相对基底的**主机指针差**，
   桩里基底的 `virtual_address` 打出来是 `0x249672490c0`）；
   **`np.require(v, requirements=['C'])`** → 类型仍是子类，`device_address` 是 **`650906928`**。
   **先前这里写"`v.copy()` 保留子类、`device_address` 两边同为 `268435456`"是错的**，
   错在我自己的桩没照 `:52-54` 那三行写（漏了 `offset = virtual_address 差` 这一步）——
   **真实的形状比"丢了属性"更坏**：副本**看起来 Still 是一个 buffer**，
   而它的 `device_address`（`physical_address` 由它派生）是**拿主机指针差拼出来的一个数**，
   它既不是那块设备缓冲的地址，也不会报错；拿这种对象去 `transfer()`
   或去读 `physical_address` 对表，得到的就是一个看着像样、实际指向别处的数。
   **所以"保留子类"的两条出路（`copy()` / `require()`）都不能当出路用**，
   唯一稳的是**回到原始对象**再做整段同步（本节上面那条）。
   自查三件套仍是那三个数，但第二个要**比数值不是比"有没有"**：
   `type(x).__name__`、`x.device_address` 与 `x.offset`（**`offset != 0` 而你以为它是 0，
   就说明你手上是一份副本而不是视图**）、以及 `x.__array_interface__['data'][0]`
   与原始 buffer 的那个指针是否相同。
   （以上全是 numpy 侧语义，**pynq 真缓冲区在板上的这组数本机没有读数**。）
   **另有一条与 numpy 版本相关的坑，本机是在这个桩上撞出来的**：numpy 2.1 起
   `ndarray` 自带一个**只读**的 `device` 属性（本机 2.5.3：`np.arange(4).device` → `'cpu'`，
   赋值报 `AttributeError: attribute 'device' of 'numpy.ndarray' objects is not writable`），
   而 `buffer.py:55` 那句是 **`self.device = obj.device`**——
   **照这段代码建子类视图时，本机在桩上得到的就是这个 AttributeError**。
   真实 `PynqBuffer` 在 numpy≥2.1 的板上会不会走到这一行，**本机没有板、没有读数**（标 机理/需板端）；
   要做的是在目标上现采一次：`python3 -c "import numpy as np; print(np.__version__)"` 与
   `python3 -c "from pynq import allocate; b=allocate((8,)); v=b[::2]; print(type(v), v.device_address)"`
   ——后者若抛 `AttributeError … 'device' … not writable`，就是这一条在真环境成立。
   手算仍然不该用，但危险在**释放**那一侧：`freebuffer()` 走
   `libc.munmap(self.virtual_address, self.nbytes)` 然后 `del self.bo`（**这一整套只在 3.1.2/4.0.0 成立**：
    函数在 `:65-82`；**3.0.1 只做前一半**——同一位置是 `libc.munmap(...)` 之后跟
    `xrt.xclFreeBO(self.device.handle, self.bo)`，**没有 `del self.bo`**，所以"句柄被丢掉"这个形状在
    3.0.1 上换成"BO 被还给 XRT"；2.5.1 与 2.7.0 的 `freebuffer` 在 `:82`，而且**那两版的 `buffer.py` 里
    `munmap` 出现 0 次**（同一条 `grep -c` 在 3.0.1/3.1.2/4.0.0 各给 3）——"局部解除映射"这个危险是
    3.x 那套分配器带来的，套到 2.x 上会连成因都不对——**但"那两版走 Xlnk 那一族"这半句是错的**：
    `grep -rln Xlnk pynq-2.7.0/pynq` 交出**空**（正向对照：同一条在 2.5.1 交出 **9** 个文件，
    含 `xlnk.py`），2.7.0 的 `allocate()` 已经走 XRT 那条链
    （`pl_server/device.py:293 return self.default_memory.allocate(...)` →
    `pl_server/xrt_device.py:171 buf.memory = self`），
    **只有 2.5.1 还带 Xlnk 那一层**）——
   拿视图去调它，**被解除映射的是视图那一段**（地址与长度都是视图的），
   而 `del self.bo` 丢的也只是**这个视图自己那一份引用**：`__array_finalize__` 在 `:57`
   做的是 `self.bo = obj.bo`，原始对象手里仍然握着同一个 `bo`。
   **所以症状不是"句柄没了"，是"原始对象还以为自己映射着"**——共享的那段映射被局部解除，
   之后任何还拿着 `bo` 的对象访问到被 unmap 的区间就是悬空访问，而 `munmap` 本身不会告诉谁。
   它自己的 docstring 就写着 "free the memory regardless of whether other objects may still be
   using the buffer"（`:68` 起）——这一句才是这条路的判据。
   所以规范写法是：切片对象本身交给 DMA，释放由**持有原始对象的那一层**做（退出 `with`），
   不要在视图上调 `freebuffer()`（本页 §3 第 2 条是同一件事的规范写法，改这里要同步那一处）。
   `reshape` 不改变地址，只改形状。
- `target=None` 用 `Device.active_device`；这就是"同一行代码在板端和在远程模式下分到不同内存"的入口。
- 物理地址属性名是 **`physical_address`**（`buffer.py:89-91`，DMA 内部用的就是它），
   不是 `phys_addr`（那是 `ip_dict` 里 IP 基址的键名）也不是 `phys_address`。
   别的手上：`virtual_address`、`cacheable`、`device`、`offset`、`bo`。

## 2. 释放：`close()` 是**废弃的空操作**，不是释放

这一段值得单独一节，因为按 2.x 习惯写 `finally: buf.close()` 的代码，**不会报错，也不会回收内存**。
各版给的信号不一样（逐棵读过）：2.5.1 `buffer.py:107-111` 是 `"""Unused - for backwards
compatibility only"""` 加一句 `pass`，**一条告警都不发**；从 2.7.0 起（`buffer.py:107-113`）
才有下面那段 `warnings.warn`，3.1/4.0 同形。
所以判“这行代码有没有在起作用”靠的是它到底释不释放，不是有没有看到 `DeprecationWarning`。

```python
def close(self):    # buffer.py:97-102，3.1 与 4.0.0 完全一样
    """Unused - for backwards compatibility only"""
    warnings.warn(".close no longer functional - use scopes to manage buffers",
    DeprecationWarning)
```

它只发一条 `DeprecationWarning` 就返回；`freebuffer()` 一个字节都没被调用。真正释放内存的是：

```python
with allocate((n,), dtype=np.uint8) as buf:    # __enter__/__exit__ 在 buffer.py:130-135
    ...    # __exit__ 调的是 freebuffer()
buf.freebuffer()    # 或者显式调用（buffer.py:65）
del buf    # 靠 __del__ -> freebuffer()，时机由解释器定
```

三条要记住的：

1. **`freebuffer()` 不看引用计数。** docstring 明写："This will free the memory regardless of
   whether other objects may still be using the buffer"。所以先 `got = np.array(buf)` 拷出来再释放；
   只要还持有 `buf` 的切片/视图，释放之后读它就是 UB。
2. `jupyter`/长跑脚本里 `close()` 的"没报错"会被当成"已经释放了"，于是有人把"池子越用越少、
   最后在某次无关的 `allocate` 上炸"当预期后果（**这是机理与常见叙事，不是本机的读数**——本机没有板子，
   也没量过池子曲线）。**但"有没有走到 `freebuffer()`"不是一条判据**——`with` 退出时它必然被
   调用（`__exit__` 就是调它），所以这个计数出生以来没红过，属于装饰性检查。
   真正的释放还有一道门：`freebuffer()` 的 unmap 主体整个包在 `if hasattr(self, "memory")` 里。
   `memory` 不是 `PynqBuffer` 自己设的，
   是**分配器设的**，链条在两版里完全一致（行号也一样）：
   `allocate() → Device.allocate()`（`pl_server/device.py:127` 是**签名行**；真正往下交的是同一函数体的
   `:145` `return self.default_memory.allocate(shape, dtype, **kwargs)`）`→ self.default_memory`
   （这是个 property：3.1.2 `pl_server/embedded_device.py:551`，4.0.0 `:566`）`→ XrtMemory.allocate`
   （`pl_server/xrt_device.py:113`）`→ buf.memory = self`（`:125`，紧跟在 `:124` 那句 `_xrt_allocate(...)` 之后）。
   `EmbeddedDevice` 就是 `XrtDevice` 的子类（3.1.2 `embedded_device.py:513`，4.0.0 `:528`），
   所以**代码层的结论只到这里**：走这条链分出来的缓冲确实带上 `memory`，那道 `hasattr` 门在这条路上是开的。
   `:124` 的 `_xrt_allocate` 是 C/XRT 绑定，本页没有打开过它，所以**"板上退出 `with` 之后确实把映射解掉了"
   这句本机没有读数**（没有板子）；要在板上确认就用 §2 那条能数的观测点，别把这条链当成结果。
   要当心的是另一种运行方式——**远程模式返回的类根本不是 `PynqBuffer`**：
   `RemoteDevice.allocate` 造的是 `RemoteBuffer(np.ndarray)`，它的 `__del__` 调 `self.freebuffer()`，
   而那个 `freebuffer` 是一次 **gRPC 调用**。**两组坐标按版本分开抄**（同一个文件在两版里行数差很多，
   3.1.2 那份只有 917 行，照 4.0.0 的行号去取会取到不存在的东西）：

   | 取的东西 | 4.0.0（1241 行） | 3.1.2（917 行） |
   |---|---|---|
   | `RemoteDevice.allocate` | `:498` | `:474` |
   | `class RemoteBuffer` | `:1058` | `:734` |
   | `__del__` → 调 `freebuffer()` | `:1134` → `:1137` | `:810` → `:813` |
   | `def freebuffer` | `:1142` | `:818` |
   | docstring "Always set to False for RemoteBuffer" | `:1079`（赋值在 `:1118`） | `:755`（赋值在 `:794`） |

   行号会漂，所以这张表只是本机这两版的**出处**，用法仍然是自己那份上
   `grep -n "class RemoteBuffer\|def freebuffer\|__del__" <安装路径>/pynq/pl_server/remote_device.py`。
   注意这条推论：主机进程崩掉/会话断掉时，板子那一侧的缓冲**没有人去释放**——
   于是**在板上**读 `/proc/meminfo` 会看到比预期小的可用量，而主机这边什么异常都没有
   （这个读数是板端的，别写成"主机重启后看到"）。所以远程模式下"板子内存不对"要按**残留**来查
   （重启板端会话，或在板上读），不是按主机的引用计数查。
   最后那行 docstring 是明写的：远程那侧的一致性语义与板子不同（`coherent` 恒为 `False`），别照搬。

   也就是说：本页关于 `cacheable`、`sync_to_device/sync_from_device`、`physical_address` 的推理
   是**板子那侧**的形状，不能整套搬到主机进程里。
   一行判别（比猜运行方式可靠）：

    ```python
    from pynq import allocate
    b = allocate((1024,), dtype="u4")
    print(type(b), hasattr(b, "memory"))    # 期望 <class 'pynq.buffer.PynqBuffer'> True
   ```

   打出来不是 `PynqBuffer` 就说明你在远程那套上，下面的章节要按 `versions-and-apis.md` §1
   重读一遍。`RemoteBuffer` 到底暴露哪些属性本包没有逐条核过（不编）；要用的话
   `dir(b)` 现场导一次。

   **所以唯一的释放证据是池子的读数**（下一节的 `CmaFree` 差值），不是调用痕迹。

3. 重复释放安全（`freebuffer` 里 `if not self.freed`），但那是安全网，不是让你省掉 `with`。

**要把"漏没漏"变成一个数**，别靠"跑久了会不会炸"来判：

先排掉三种"你没漏但看起来像漏"的来源，再去做差值实验：

1. **SG 的描述符表**（会挂住，但**不会每笔累积**）。`_SGDMAChannel.transfer` 每次自己 `allocate`
   一块 BD 表（`lib/dma.py:384`），回收只发生在 `wait()`/`wait_async()` 的**末尾**（`:519-521`），
   而 cyclic 与引擎错误都在它之前就 `raise` 了（`:473-474`）。
   但下一次 `transfer()` 会重新绑定 `_descr`，旧表随即由 `__del__ → freebuffer()` 释放，
   所以**每通道最多残留一张**：`_num_descr × 64 B`，普通传输就是 128 B。
   判据因此是数量级比对，不是"有没有涨"：观测差值若是 `k×128 B` 量级、且
   `stop()` 之后 `dma.sendchannel._descr is not None`，才是这条；差值大几个数量级就别说它解释得掉。
   细则在 `dma-channels.md` §1 第 2.5 条。

2. **远程模式**。`pynq.allocate` 在主机侧给你的是 `RemoteBuffer`，它的释放是一次 gRPC 调用；
   主机会话断了，板子上那块就没人还（见上面 §2 的远程分支）。
3. **`with` 的作用域真的很长的那些写法**（不是"notebook 里不退出"——cell 结束块就结束了，
   结束后 `b` 只是变成已释放的悬空句柄）。真会让内存在整轮跑完前一直占着的是：
   不带 `with` 的裸 `allocate()` 再赋值给变量、`with` 块里嵌着一个长期不返回的
   `wait()`（cyclic 下它甚至直接 `raise`，见第 1 条），以及把缓冲存进一个活到进程结束的对象里
   （例如某个全局的队列/环形缓冲列表）——最后这种最像"漏"，但它是**设计上的长生命周期**，
   差值实验只会告诉你"没还"，不会告诉你"该还"。



```python
import re
import numpy as np
from pynq import allocate

def cma_free_kb():
    try:
        t = open("/proc/meminfo").read()
    except OSError:
        return None    # 不在板上跑时直接走 NOT_RUN 那一支
    m = re.search(r"CmaFree:\s+(\d+)\s+kB", t)
    return int(m.group(1)) if m else None    # None = 这一版内核没导出 CMA 统计

start = cma_free_kb()
for i in range(50):
    with allocate((4*1024*1024,), dtype=np.uint8) as buf:    # 每轮 4 MiB
        pass
end = cma_free_kb()
if start is None or end is None:
    print("VERDICT: NOT_RUN -- 这一版没有 CmaFree 读数，既不能说没漏也不能说没回收")
elif start - end > 204800 // 2:                            # 半轮以上没还
    print("VERDICT: LEAK held_kb =", start - end)          # 全漏的话约 204800 kB（50×4 MiB）
else:
    print("VERDICT: ok held_kb =", start - end)            # 期望 ≈0；容差见下面第 4 条
```

**`start` 必须存下来**——这一段以前写成"打印 start、结尾再取一次当前值减去它自己"，
那**永远不会红**（两个数都是循环结束后的读数，差恒 ≈0），判据形同装饰。
现在的判据是**同一次会话里前后两个读数的差**：漏 = `CmaFree` 变少 = `start - end` 是**正**的。

判据是**两数之差**，不是"有没有 MemoryError"：50 轮之后 `CmaFree` 单调下降 ≈ `50×4 MiB` 就是漏。
三条限定要说在结论里，否则这个数会骗人：

- **`CmaFree` 只量 CMA 池，也就是 `allocate` 出来的那一族——**这句里的「同一池」本机**没有核实过**：
  3.1/4.0 的 `allocate` 走的是 `xrt_device.py` 那条路径（那个文件里不出现 CMA 字样），
  所以 `VERDICT: ok`（差 ≈0）在这两版上还有第三个解释：**量的不是同一池**。
  先做一次配对：板上 `grep -i cma /proc/meminfo` 在分配前、分配后各取一次，
  `CmaFree` 真的掉了你申请的量，才说明这个字段记的是你那批缓冲的账；不掉就先换读数来源，
  别把「量为 0」直接读成「没漏」。 反复 `Overlay(...)` 攒下来的是
   mmap 映射、`/dev/uio*` fd 与驱动实例，**不在这个池子里**——所以那个实验跑 20 次 Overlay
   会打出 `held_kb ≈ 0`（也就是 `VERDICT: ok`），这是"没量到"，不是"没漏"。要查那条路看
   `overlay-metadata.md` §3 的"引用还活着就不释放"（循环变量、异常 traceback、Jupyter 的 `In`/`_`）
   与 `overlay-metadata.md` §5 那份反复加载骨架，`lsof`/`fd` 计数比 `CmaFree` 诚实。
- **上面这个循环量的是"`with allocate` 这个写法漏不漏"，不是"你的代码漏不漏"。** 要审计的是你自己的
   那段：把循环体换成被怀疑的调用序列（含异常路径），否则全绿只证明标准库那条路是通的。
- `None` 要显式判：`None == None` 会打印成"没差值"，那是把"读不到"记成"没漏"。上面那行
   `VERDICT: NOT_RUN` 就是为这个存在的。若 `CmaFree` 根本没有（`cma=` 没写进 cmdline、或走
   reserved 区方案），改用 `grep -a Cma /proc/meminfo` 与 `dmesg | grep -a -i cma` 看这一版暴露了哪些字段名再决定。
- "在池的粒度内稳定"这句要给得出数：容差取**分配尺寸的量级**（这里是 4 MiB）或
   `/proc/meminfo` 里 `CmaTotal` 的 1%，两个都行但必须写明用的哪个，不然"稳定"是不可推翻的说法。

要让这条能红，破坏的必须是**作用域本身**，而且**不能靠"重绑变量"**：
`for i in range(50): b = allocate(...)` 这种写法每轮把上一块对象丢给 GC，
`__del__ → freebuffer()`（`buffer.py:62-63`）照样回收，测出来是绿的——那是变异没打到点子上。
打得着点的做法是**让引用真的活着**：

```python
hold = []
for i in range(50):
    hold.append(allocate((4 * 1024 * 1024,), dtype=np.uint8))    # 引用留在列表里，作用域不结束
```

这应该打出 `VERDICT: LEAK held_kb ≈ 204800`；跑完记得 `hold.clear()` 再看一次读数回落，
两边都观察到才算这条判据存在。**只在 `with` 外面补一句 `buf.close()` 不会红**——退出 `with` 时
`__exit__` 照样释放（`buffer.py:133-134` 那条路径），得到绿的变异对照不等于代码没漏。


## 3. 缓存一致性：方向、粒度、和"要不要你做"

```python
buf.cacheable    # 这块内存是不是走 cache 的映射（buffer.py:85-87 -> not self.coherent）
buf.sync_to_device()    # CPU 写过、给 PL 读之前
buf.sync_from_device()    # PL 写过、CPU 读之前
buf.flush(); buf.invalidate()
```

方向记成一句话：**给 PL 读的先 `sync_to_device`（把脏行写出去），PL 写过的读之前 `sync_from_device`
（把脏行丢掉重读）**。两个方向都漏或反了，症状不同：漏 → 半新半旧/首块尾块坏；反 → 第一次对、
第二次读到旧数据。

"半新半旧"这一句在 §1（手算地址）和这里（一致性）都出现过，所以给一条**有排除力的顺序**，
别两支同时试：

1. **先证明这一笔搬完了**：读 `dma-channels.md` §2 那四个口（`idle`/`error`/`transferred`/引擎状态）。
   没搬完的话，"半新半旧"是**没写完**而不是写完没同步——后面几步全是白做。
2. **再看地址是从哪来的**：交给 DMA 的是切片（`buf[K:]`）还是手算的 `physical_address + K`？
   机制被源码反写了一次，按反写后的说法查：视图上的 `self.offset`/`self.nbytes`
   是**视图的量**（`__array_finalize__` 在 `:50-57` 重算 offset、`nbytes` 取视图长度），
   所以 `flush`/`invalidate`（`:104-114`）**跟着切片走**——"另一段被无谓 invalidate"那种说法不成立。
   该查的是释放路径：`freebuffer()`（`:65-82`）拿视图调用时 `munmap` 只覆盖视图长度，
   而 `del self.bo` 只丢视图自己那一份引用（`:57` 是 `self.bo = obj.bo`，原始对象仍持有同一个 `bo`）——
   受损的是**共享映射被局部解除**，不是句柄消失。这一步只看代码就能定，代价最低。
3. **再看 `buf.cacheable` 与调用方向——但只在"驱动不替你同步"的那条路上看**（旧文把这一步当成
   通判据，是错的）：`cacheable`（= `not coherent`，`buffer.py:85-87`，两版同一行号）为真却没调
   `sync_to_device`/`sync_from_device`、或方向反了，症状是"第一次对、第二次旧"，
   与第 1 步的"永远缺一块"不一样，用它来分。
   **走 DMA 驱动时这一步永远不会红**：TX 通道构造时 `_flush_before=True`（3.1.2
   `lib/dma.py:60-63`），`transfer()` 里就 `array.flush()`（`:153-154`，SG `:430-431`），
   `wait()` 里再 `_active_buffer.invalidate()`——**但这一支只属于收侧**：那一段的原文是
   `:183 if not self._flush_before:` + `:184 self._active_buffer.invalidate()`，
   而 `_flush_before` 在构造时**RX 置 `False`（`:60`）、TX 置 `True`（`:63`）**，
   **所以发侧（TX）走的是 `:153 if self._flush_before:` 那支、在 `transfer()` 之前 flush，
   `wait()` 里那句 invalidate 对它根本不执行**（先前这里把两条通道混在一句里，
   写成"`wait()` 里再 invalidate"像是在说两条都是）。**忘了手动同步是不可见的**。
   所以这一格只适用于：自定义 master 直访 DDR、PL 自己写你手分配的缓冲、以及远程模式那侧
   （`coherent` 恒 `False`）。
4. **以上都排除，才轮到尾部粒度**：见下面那条——它排最后是因为它的证据最贵（要构造专用图案）。


粒度按 cache line，长度不足一行的尾部最容易只维护一半 —— 所以**别只同步一半长度**。
（cache line 粒度这个词来自实现侧，本包没有对应的 C 绑定，所以不能给你"一行多少字节"的数；
能落地的判据是行为侧的：构造一段**首/尾各差一点**的图案——只同步中间 `nbytes-K`、或从非对齐偏移
（`K` 这里只是**任意一个不是对齐倍数**的探针尺寸，不代表行宽是 64，别把它当常数搬）
开始同步——看坏的是不是总是两头。这一族的分诊在 `debug-triage.md` §2 树 C，端到端写法在 `dma-channels.md` §3。）

`cacheable` 为 False 时（非缓存映射或 reserved 区）`flush/invalidate` 内部 `if not self.coherent`
直接跳过，这些调用是空操作，此时问题不在这层。**但"先打印 `buf.cacheable`"这条判据
在本机的代码路径上永远不会红**（这一条被本机重做推翻）：`cacheable` 的定义是
`buffer.py:85-87` 的 `return not self.coherent`，而**每一版的 XRT 分配都把 `coherent` 硬写成
`False`**——2.5.1 `pl_server/xrt_device.py:135`、2.7.0 `:128`、3.1.2 与 4.0.0 都是 `:81` 的
`coherent=False,`（4.0.0 同一行也在 `buffer.py:39` 的默认参数里写着 `coherent=False`），
**所以 `allocate()` 出来的缓冲 `cacheable` 恒为 `True`**，
`False` 那一臂只在**2.5.1 的 Xlnk 路径**上可达（2.5.1 `xlnk.py:294` 的 `coherent=not cacheable`
是唯一由用户侧决定的写法）。**所以这一格的用法要反过来写**：读到 `True` 是常态，
不能据此说"同步层在工作"；读到 `False` 才是异常，而那基本等于"你不在 XRT 这条路上"。
判"驱动有没有替你同步"要靠上一层的分支（`_flush_before` 那两支，见上一条）
和端到端的字节比对，不是这个属性。
这一步很多"玄学旧数据"的案子能当场结案。（**这句先前说得过头了，按上面收窄**。）
