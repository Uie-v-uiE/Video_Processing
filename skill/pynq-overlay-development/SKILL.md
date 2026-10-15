---
name: pynq-overlay-development
description: 用于在 PYNQ（Zynq-7000 的 Pynq-Z1/Z2、Ultra96、ZynqMP 的 ZCU102/104/K26、RFSoC 等）上做 Overlay 加载、寄存器访问、缓冲区与 DMA 搬运、中断等待、板端性能测量与问题定位的工作。触发场景：`Overlay(...)` 加载后拿不到 IP 或 `KeyError`、位流与 `.hwh/.xsa/.dtbo` 配套问题、`download=False` 之后哪些字段有值、部分位流只重配一块 PR 区域、`register_map` 与 `mmio.array` 的偏移与字/字节口径、`MMIO.read/write` 报未对齐或报「Device does not have capabilities」、`pynq.allocate` 的 dtype 与物理地址、缓冲区释放与 `close()`（2.5.1 是静默 `pass`、3.x/4.x 只发 DeprecationWarning）、DMA 报 unaligned/exceeds maximum、`wait()` 挂死或超时、`wait_async` 看起来永远存在、传输半新半旧或首块尾块坏、中断 `Interrupt(...)` 构造失败与没有 timeout 形参、反复换 overlay 之后结果不对、板端 Jupyter 与远程开发模式的行为差别、`DMA.transfer()` 不抛异常而 `transferred` 一直是 0、寄存器侧全通但搬运侧一步不动（这一层要回设计侧数时钟引脚）、`CmaFree` 这类计数口能看见什么、看不见什么（池身份本包未核实）、从 2.x 的 `Xlnk` 迁到 3.x/4.x、第一次把自定义 IP 从 Vivado 导出跑到板上验证。不用于 Vivado/Vitis 侧的 RTL、综合、约束与时序收敛（用 `fpga-board-development`），也不用于与 PL 无关的纯 Python。
license: MIT
---

# PYNQ Overlay 开发：寄存器、缓冲区、DMA、中断、分诊

## 用法

先查下面的路由表，只打开命中的**那一节**；不要一次读全部参考文件。表里每行只给一个入口小节，
进去之后再顺着它内部的引用往外走（`first-bringup.md` 那一行例外，它要整页按顺序读）。
行号会随版本漂移：正文里的 `文件:行` 只用来定位**符号**，跳行之前先确认那一行现在写的是什么；
**没写版本的行号一律取本机 4.0.0 那棵树**。这条不是凑合，是本机五版实测出来的：2.x 与 3.x 之间
不止漂行号，**有些段在 2.x 里压根是别的代码**——`uio.py:27-32`（UIO 名字扫描）与
`interrupt.py:63-64`（`pinname` 校验）在 2.5.1/2.7.0 分别落到文件头许可证注释与
`/proc/interrupts` 扫描函数里，同名代码在那两版是 `:56-61` 与 `:92-93`。
版本之间行为不一致的地方，正文都写成"3.x 这样 / 4.0 那样"，看到单一说法就是它本来就单一。

## 1. 十一条硬规则

1. **`Overlay(...)` 不报错不等于元数据进去了。** `print(ol.dtbo)` 只证明路径被算出来；
   设备树是否生效要问内核：`/sys/kernel/config/device-tree/overlays/<dtbo 基名>/status` 读到 `applied`。
   **库自己那条回读是"带尾换行的相等比较"，而两版的容错不一样**：3.0.1/3.1.2/4.0.0 走
   `open(..., 'r')` 文本模式 + `return f.read() == 'applied\n'`（4.0.0 `devicetree.py:88-89`），
   2.5.1 走 `subprocess.check_output('cat …')` 再 `status.decode('utf-8') == 'applied\n'`（`:115-118`）。
   主机上三种写法都比过（Python 3.12，RUN）：`applied\r\n` 在文本模式那支被归一化成 `applied\n`
   ⇒ **判 True**，在 `decode()` 那支不归一化 ⇒ 判 False；`applied\n` 两支都 True；
   **没有尾换行的 `applied` 两支都 False**。所以"人眼看是 `applied`、库说 False"能同时发生的
   真实成因是**少那个换行**（外加 2.5.1 遇上 CRLF）。还有一道门：目录不存在时
   `is_dtbo_applied()` 直接回 False（`:86-87`）⇒ **False 混着两种成因**（没落地 / 落地了但 status
   读法不对），要分开就自己 `cat -A` 看字节。
2. **`.dtbo` 的基名是它的身份。** 代码能证到的不止"同基名 → 同一个 configfs 条目"
   （4.0.0 `devicetree.py:74-75`：`self.dtbo_name = get_dtbo_base_name(dtbo_path)`，
   `self.sysfs_dir = os.path.join(SYSTEM_DEVICE_TREE_PATH, self.dtbo_name)`）：
   `insert()` 是 `os.makedirs(self.sysfs_dir, exist_ok=True)` 再往 `<该条目>/dtbo` 写字节
   （`:97-103`），**同名第二次插入就是往同一条目再写一次**，写完它还做两次检查
   （`:109-116` 把 `dtbo` 读回来比对、`:118-120` 再问 `is_dtbo_applied()`，
   任一不过抛 `RuntimeError("Device tree {} cannot be applied")`——**所以"插入失败一定不报错"是错的**）；
   `remove()` 是 `if os.path.exists(self.sysfs_dir): os.rmdir(self.sysfs_dir)`（`:126-127`）——
   **按目录名删、不认是谁插的，而且没有 `try`**：目录被内核占着（还有子节点/引用）时这里就抛 `OSError`。
   **2.5.1 不是这套形状**：它的 `insert()`/`remove()` 走 `subprocess` 的 `mkdir -p`、`cat <dtbo> > …`、
   `rmdir`（`:120-145`），那一版根本没有 `sysfs_dir` 属性，路径是每次现拼的——
   别把上面这些行号搬给 2.5.1。
   "加载后者会把前者的中断/UIO 节点静默摘掉"是**内核那一侧的机理，本包没有板、没量过**，
   只当"为什么要不同名"的理由，不当读数用。要共存就必须不同名。
3. **`write()` 不报错不等于写到了。** 至少三种图案 + 读回，恒 0 / 恒 F 不算通过；
   图案只往确认过没有副作用的偏移写，写完复原。
4. **`MMIO.read/write` 的 offset 是字节，`mmio.array[]` 的索引是字。** 混用的表现是"读到隔壁寄存器"。
5. **`pynq.allocate` 默认 `dtype="u4"`**，不是字节数组；`PynqBuffer` 要从 `pynq.buffer` 导入，
   顶层 `pynq` 只导出 `allocate`。
6. **`buf.close()` 是废弃的空操作**：3.1/4.0 里它发一条 `DeprecationWarning`（2.7.0 起就有），
   而 **2.5.1 里是空 `pass`、连告警都没有**——所以"没看到警告"不能反过来证明你没在用它。释放靠退出 `with` 或
   `freebuffer()`。**判"漏没漏"不能靠有没有报错**（它本来就什么都不做），也**不能只押 `CmaFree` 差值**：
   这一族的释放路径**分三档，别当成一条**（`grep -rn munmap pynq/buffer.py` = 2.5.1/2.7.0 **0** 处、
   3.0.1/3.1.2/4.0.0 各 3 处；同一批扫描里 `xclFreeBO` 全树 = 5/5/6/**0**/**0**）：
   3.0.1 的 `buffer.py:82` 直接 `xrt.xclFreeBO(...)`；3.1.2/4.0.0 的 `buffer.py:82` 是 `del self.bo`，
   **但这条链的下一环不在 Python 里**：`ExecBo` 这一类在 3.1.2/4.0.0 只有定义
   （`pl_server/xrt_device.py:154`）而**没有任何构造点**。证据要按真实命令写：
   `grep -an "ExecBo(" pynq-<版>/pynq/pl_server/xrt_device.py` 交回 **2.5.1 [529] / 2.7.0 [581] /
   3.0.1 [596] / 3.1.2 [] / 4.0.0 []**——**那两版是 0 行，不是"只回定义那一行"**（定义行是
   `class ExecBo:`，2.5.1/2.7.0/3.0.1/3.1.2/4.0.0 分别在 `:198`/`:197`/`:186`/`:154`/`:154`，
   带括号的模式匹配不到它；要数定义行得用 `grep -an ExecBo`），，所以**这两版**的 `ExecBo.__del__` 是**死码**；
   **先前写"3.0.1 才有 `:596` 那句构造"是错的，收回**：2.5.1 在 `xrt_device.py:529`、2.7.0 在 `:581`、
   3.0.1 在 `:596` 三处都真的构造它（同一条 grep 逐棵树各回一行），所以那三版的 `__del__` 不是死码，
   先前把它写成"归还靠 `ExecBo.__del__` → `_free_bo`"是错的，收回。
   真实形状是：`self.bo` 来自 `pyxrt.bo(...)`（`:345`，失败才是那条 `BO allocation failed:`），
   归还发生在 `pyxrt` 那一侧、引用归零时（**机理，本机读不到**：`pyxrt` 这个名字只在 3.1.2/4.0.0 的
   `pl_server/xrt_device.py` 里出现（各 1 个文件），2.5.1/2.7.0/3.0.1 是 **0 个文件**，五棵树里都没有它的
   源码或桩；正向对照就是同一条 `grep -rl pyxrt pynq-<版>/pynq` 在那两版能命中文件）——
   Python 树里**看不到显式释放**；唯一的显式出口是同文件
   `:84` 的 `weakref.finalize(buf, _free_bo, device, bo, ar.virtual_address, ar.nbytes)`——
   **而它只在 `pointer is not None` 时挂**（`:83`），`_free_bo` 本体是 `libc.munmap` + `del bo`（`:91-93`）。
   所以"退出 `with` 之后一定有人 unmap"这句要按那一档分开说：3.0.1 显式 `xclFreeBO`；
   **3.1.2/4.0.0 里普通 `allocate()` 出来的缓冲走的是另一支**：它有 `memory`、没有 `pointer` 属性，
   于是 `freebuffer()` 取 `buffer.py:78-82` 那一支——**同步 `libc.munmap`（`:81`）然后 `del self.bo`（`:82`）**；
   需要等引用归零的只是 **BO 对象本身**（`self.bo` 是个 `pyxrt.bo`，`del` 只解掉 Python 这一份绑定），
   **不是那块映射**。而 `weakref.finalize`（同文件 `:83-84`）挂在 `_xrt_allocate` 的 **`pointer` 形参**
   非 `None` 时（`:59` 的签名；传它的是 frame cache 复用旧缓冲那条路，4.0.0 `lib/video/dma.py:28-44`
   同时传 `pointer=` 与 `cache=`），**与 `ar.pointer` 那个属性（`:85-87` 才设）不是同一个东西**——
   先前这里写的"普通 `allocate()` 出来的缓冲依赖引用归零"把两样混成一句，**收回**；
   2.5.1/2.7.0 的 `buffer.py` 里既没有 `munmap` 也没有 `xclFreeBO`（BO 的归还那一步在
   `pl_server/xrt_device.py`：2.5.1 `:142`、2.7.0 `:140` 都是 `xrt.xclFreeBO(device.handle, bo)`），
   **`buffer.py` 里**没有 `munmap`（那段分析在 `buffer.py` 这一层不适用）——但**别说成"那两版不 munmap"**：
   2.5.1 `pl_server/xrt_device.py:140-142`、2.7.0 `:138-140` 的 `_free_bo` 就是
   `libc.munmap(...)` 之后接 `xrt.xclFreeBO(device.handle, bo)`，只是它挂在 `weakref.finalize`
   上（2.5.1 `:136` **无条件**；2.7.0 `:129-130` 只在 `pointer` 形参非 `None` 时挂）。
   而 `CmaFree` 是不是同一个池本包没核实（见路由表那格），
   一条永远不红的判据不算判据——**先给它做一次最小破坏**：故意留一份引用不释放（或反过来，跑一遍
   正常释放），看那个数真的会动，才说明这条判据看得见释放；两臂的口径要写在一起
   （`buffers-and-cache.md` §2）。**"退出 `with` 之后再读一次这个 buffer 会不会炸"不是判据**：
   `buffers-and-cache.md` 的 §2 第 1 条自己写了"释放之后读它就是 UB"——UB 不可复现（可能读到旧值、可能把进程打死），
   它当不了"能红"的那一次。
7. **切片交给 DMA，不要手算 `physical_address + 偏移`。** 手算**不会**绕过同步记账，也**不会**让范围错位：
   `flush()`/`invalidate()` 用的就是 `self.offset`/`self.nbytes`（4.0.0 `buffer.py:104-114`），而
   `__array_finalize__` 给视图算的是**视图自己**的 offset（`:50-57`：`offset = self.virtual_address -
   obj.virtual_address`，`self.offset = obj.offset + offset`），而 `nbytes` 是"元素数 × itemsize"：
   **连续切片**下同步范围正好等于视图碰到的那段，**步长切片（如 `a[::2]`）下它只盖住前半段，
   覆盖范围与视图碰到的字节不一致**（这一层在本机是可证的：判据是 `flags['C_CONTIGUOUS']` 与
   `__array_interface__['strides']`，`buffers-and-cache.md` §1 有实测的 `nbytes`/`offset` 对照；
   "尾部没被 flush 且不报错"是**机理**，驱动那层本机没打开，别当读数用；
   两条出路写在 `buffers-and-cache.md` §1）。
   **真正的危险在释放那一侧，形状要分三档**（先前这里与 `buffers-and-cache.md` §1、§3 第 2 条写的
   "视图上调 `freebuffer()` 会 `munmap` 视图那一段、映射被局部解除"**整段收回**）：
   **第一档 板端 3.0.1/3.1.2/4.0.0**：unmap 主体（4.0.0 `buffer.py:73-82`）整个被 `if hasattr(self, "memory"):`
   包住，`memory` 只有分配器会挂到原始对象上（`pl_server/xrt_device.py:125`），
   `__array_finalize__`（4.0.0 `buffer.py:50-57`）既不搬它也不搬 `freed`
   ⇒ **对切片视图调 `freebuffer()` 是完整 no-op**，连续切片与步长切片同形；主机桩的读数与它的
   两处偏离写在 `buffers-and-cache.md` §1（含"逐字照抄那份在 numpy 2.5.3 上构造不出来"那一条）。
   **第二档 板端 2.5.1/2.7.0**：同一个方法**没有 memory 门**，`buffer.py:90` 是这两版里唯一的判断，
   即 `if hasattr(self, 'pointer') and self.pointer:`——**但"谁带 `pointer`"这两版完全不同**：
   2.5.1 的 `allocate()` 交给 Xlnk（2.5.1 `pl_server/device.py:574 self.default_memory = Xlnk()`），
   而 `xlnk.py:296-297` **无条件**给每个原始对象挂 `pointer`（`:289` 是 `ffi.gc` 句柄）与〔`xlnk.py` 与 `lib/logictools/` 都不在 4.0.0 那棵树上：前者只在 2.5.1，后者整目录在 4.0.0 已删——本行的号取自 2.5.1 的副本外〕
   `return_to = cache`（默认 `None`）⇒ 在 2.5.1 上"带 pointer"是**常态**，`freebuffer()` 因此只把
   `pointer` 置 0，而 `:290` 用 `cma_get_buffer(pointer, length)` 造的数组把句柄挂在 `base` 上，
   **置 0 并不触发 `cma_free`**（主机桩同一形状实测：`sys.getrefcount` 出生就是 3，属性只是其中一份；
   数组连同它的所有视图一起消失才轮到 finalizer。这是引用语义，板上真实时机仍要现读 `CmaFree`）；
   **这一档还有前提**：2.5.1 只有把 `active_device` 落成 `XlnkDevice` 时才走 Xlnk
   （谁当选由 `_probe_`/`_probe_priority_` 决定，机制在 2.5.1 `pl_server/device.py:51-78`）——走 XRT 那条时
   2.5.1 的 `_xrt_allocate(shape, dtype, device, memidx)`（`pl_server/xrt_device.py:122`）**没有 pointer/cache 形参**，
   普通缓冲不带 `pointer`，`:90` 整段空转，归还靠 `:136` 那条**无条件**的 `weakref.finalize`。
   2.7.0 走 XRT，普通 `allocate()`
   不带 `pointer`，在 `:90` 那一关直接返回、什么都不做。
   **只属于 2.5.1 的一条**：它的 `__exit__`（`buffer.py:146-147`）调的是 `self.free_buffer()`，
   那个类上**没有这个名字**（全树 `def free_buffer` 只有 `lib/logictools/logictools_controller.py:456`，〔`xlnk.py` 与 `lib/logictools/` 都不在 4.0.0 那棵树上：前者只在 2.5.1，后者整目录在 4.0.0 已删——本行的号取自 2.5.1 的副本外〕
   另一个类、要一个参数），而 2.7.0 的 `__exit__` 在 `:148-149`、调的才是 `freebuffer()`
   ⇒ **`with allocate(...) as buf:` 在 2.5.1 上退出块当场 `AttributeError`**——本包把"退出 `with`"
   写成规范释放用法，那一版这个写法自己会炸（`xlnk.py:262-265` 的 docstring 还承诺 `with` 会自动释放，〔`xlnk.py` 与 `lib/logictools/` 都不在 4.0.0 那棵树上：前者只在 2.5.1，后者整目录在 4.0.0 已删——本行的号取自 2.5.1 的副本外〕
   这里 docstring 与行为不一致，以行为为准）。
   真会"退回缓存"的家族是 `lib/video/dma.py:28-44` 那种 `allocate(..., cache=self)`（它**同时**有
   `memory` 与 `pointer` 属性）；`lib/video/drm.py:186-189` 那个 `array.view(PynqBuffer)` + 手设
   `pointer`/`return_to` 的对象**没有 `memory`**，在 3.x/4.0.0 上它的 `freebuffer()` 连门都没进
   （先前把 drm 那一族当成"退回缓存"的通用例子，是选错了家族）。
   **第三档 远程模式**是另一个类：`RemoteBuffer.freebuffer`（4.0.0 `pl_server/remote_device.py:1142-1154`，
   `if not self.freed:` 在 `:1148`、gRPC 调用与 `raise RuntimeError(response.msg)` 在 `:1150-1154`）
   同样没有 memory 门，而它附近那段 `__array_finalize__` 不把 `freed` 交给视图 ⇒ 在远程的视图上调它是
   `AttributeError`（静态读来，未上板）。
   还有一条容易漏的顺序：**`pointer` 那支排在解映射之前**（4.0.0 `buffer.py:74-77` 对 `:78-82`），
   所以带指针的对象连**原始对象**调用都不会 `munmap`（桩 RUN）——"退出作用域就把内存还回去"对它不成立。
   真危险因此落在**引用侧**：原始对象释放之后（退出 `with`、`__del__`、显式调用）视图若还在你手上，
   读它是悬空且不可复现，别当判据（**只有这一条路**：`__del__` 走不到这里——`v = o[64:]` 之后 `v.base` 就是那个原始对象，视图活着就把它引用住了，桩与真 numpy 都实测过 `del o; gc.collect()` ⇒ `munmap` 0 次）；在原始对象上**显式**调用之后再切一片会当场
   `AttributeError: 'PynqBuffer' object has no attribute 'bo'`（`del self.bo` 是 4.0.0 那次调用的最后一句）。
   **也别给视图补一个 `memory` 去"修好"它**：没有 `pointer` 时它撞 `if not self.freed`
   ⇒ `AttributeError ... no attribute 'freed'`（桩 RUN），带 `pointer` 时它只退指针、既不 munmap 也不读
   `freed`（桩 RUN）——两臂都在，所以"补门必然炸"这句也不成立。
   释放由**持有原始对象的那一层**做，规范写法在 `buffers-and-cache.md` §3 第 2 条。
8. **`transfer()` 的长度上限：SDMA 与 SG 的失败方式不同**，所以判断"有没有超限"不能靠
   "有没有报错"这一件事（分支、算法与恢复见 `dma-channels.md` §1、`debug-triage.md` §2 树 C）。
9. **`wait_async` 是类上的协程，`hasattr` 永远为真。** 判断中断接没接要分**三样东西**看，别看方法
   存不存在：① 通道实例的 `_interrupt`（驱动侧握着的那个对象在不在）、② IP 元数据里的 `interrupts`
   （这一版设计有没有声明这根针）、③ 设备树里的 UIO 节点（`.dtbo` 那层有没有落地，
   `debug-triage.md` §2 树 D 第 1 步就是查它）。**"①② 全绿而 ③ 缺"这个组合在板端不存在**：③ 缺时
   `Interrupt(...)` 抛 `ValueError`，3.x/4.x 的 `DefaultIP.__init__` 把它吞成 `setattr(..., None)`
   加一条 UserWarning `Interrupt {} not created: {}`（4.0.0 `overlay.py:706-711`、3.1.2 `:709-714`、
   3.0.1 `:705-710`、2.7.0 `:677-683`），① 于是就是 `None`；**2.5.1 没有这层 `try`**，`overlay.py:649`
   直接把异常抛出构造函数。所以 ① 是"③ 有没有落地"的**结果**，不是并列的第三项。
   **远程模式是另一档，别把上面那句搬过去**：远程环境把 `Interrupt` 换成 `RemoteInterrupt`
   （4.0.0 `pl_server/remote_device.py:885`），它**从不抛 `ValueError`**，只在构造时
   `warnings.warn("Interrupts are not yet implemented for remote devices")`（`:899`）
   ⇒ 远程下 ① **恒不是 `None`**，问题要到 `:901 def wait(self, timeout=None)` 那一层才露头。
   所以"① 是不是 `None`"这条分流只在板端成立；先按 `Interrupt.__module__` 判自己在哪一档
   （`debug-triage.md` §2 树 D 第 2 步给的就是这个）。
   **但吞的只有 `ValueError`**（逐版都是 `except ValueError as e:`，4.0.0 `overlay.py:709`、
   3.1.2 `:712`、3.0.1 `:708`、2.7.0 `:680`）：UIO 节点**在**但打不开（`uio.py:73` 的
   `open(device, 'r+b', buffering=0)` ⇒ `FileNotFoundError`/`PermissionError`，非 root 就会走这一支）、
   或元数据里那个控制器名取不到（`interrupt.py:168` 的 `PL.ip_dict[name]['phys_addr']` ⇒ `KeyError`）
   **都不会被吞**，`Overlay(...)` 直接失败。别把"看到 `Interrupt ... not created`"当成中断问题的全部形状。
   **`wait()` 挂死与中断无关，但卡点不止一个**：五版的 `wait()`（4.0.0 SD `lib/dma.py:166-187`、
   SG `:470-523`；2.5.1 SD `:130-139`）一次都不读 `_interrupt`，是纯轮询 SR——它不回说的是"引擎没到 idle"。
   **SG 那一版 `wait()` 在等到 idle 之后还要 `self.stop()`（`:517`），而 `stop()` 的尾巴是
   `:310-311` 的 `while self.running: pass`**——所以 SG 的 `wait()` 有第二个卡点，位置在"已经搬完之后"。
   读 `_interrupt` 的有两个：`wait_async()`（SD `:189-199`、SG `:525-554`，① 是 `None` 时它抛
   `AttributeError: 'NoneType' object has no attribute 'wait'`——是异常，不是挂死；且**只有真去 `await`
   才抛**，`ch.wait_async()` 不 await 只是造出一个协程，什么都不发生），以及 **`start()`**
   （SD `:89`、SG `:290`/`:295`；2.5.1 `:85`、2.7.0 SD `:123`/SG `:327`、3.0.1 SD `:89`/SG `:286`/`:291`）：
   它按 ① 决定往 DMACR 写 `0x1001` 还是 `0x0001`（SG cyclic 那支是 `0x1011`/`0x0011`）——
   **源码能撑到的只是"0x1000 是这两组常量里唯一随 ① 变化的那一位"**；把它叫"中断使能位"是 PG021
   那一层的命名，本包不引手册，**属推断**。所以这块板端口的正确用法是差分而不是解释：
   同一个通道在"元数据说接了中断"与"没接"两种状态下各读回一次 DMACR，**看那一位是否随 ① 变**，
   变与不变都是读数；至于它叫什么，去查你自己那份 PG021 表格。
   所以不要把"①② 都对"写成"中断已接好"，也不要把"wait 不回"归到中断那一层。
10. **`wait()` 没有 timeout 形参。** 第一次上板不要裸等；超时自己包，并知道包起来的代价是
    后台线程与一个还在跑的引擎。异常之后先把引擎弄停再继续——但「弄停」只能用 `MMIO` 写 RS=0
   加自己轮询 SR：`stop()`/`transfer()`/`wait()`/`start()` 内部都有无上界的自旋（`dma-channels.md` §2 那条）。
11. **一次访问把 CPU 卡住，这类现象要按通路问题处理，不是按值设错处理。**
    "这笔 AXI 事务永远等不到响应、所以它不在 Python 的状态里、重启 kernel 也救不回来"属于
    **通路那一族的机理口径**（同族句子在 `mmio-registers.md` §4 第一条已经标明是手册口径、本包不引手册）：
    本包没有板，**没有一条读数支持"重启 kernel 无效"**，所以别把它写成验证过的结论。
    当场能做的只有：换一次探活读、按通路分诊（§2 第一条），并把"要不要断电"按不可逆动作对待（§5）。

## 2. 三条分诊顺序

- **卡住** → 先确认 PL 有没有时钟/复位，再确认地址上有没有从设备；这一支的结论是"通路不通"，
  不是"值设错了"，别再重试同一笔写。
- **不卡但值不对** → 先读一个必然有值的寄存器（设计里埋的版本号/自由运行计数器），
  再谈 offset 单位、位段极性、门控条件。
- **数据不对** → 先证明这一笔搬完了，再看地址来源（切片还是手算）、`cacheable` 与同步方向，
  最后才怀疑尾部粒度；按代价从低到高排，两支同时试是最常见的浪费。

判据的通用要求：**它必须能变红**。一条从来没有红过的判据不构成证据（例如"有没有调用释放函数"
在 `with` 写法下永远为真）。

## 3. 路由

每行只给**一个**入口小节（最能判别的那一节），进了那一节再顺着它内部的引用往外走。
唯一例外是第一行：`first-bringup.md` 是按顺序走的清单，指着任何单节都会诱导跳步，所以整页读。

| 症状 | 先读 |
|---|---|
| 第一次把某个 IP 从 Vivado 导出跑到板上验证（整页按顺序，别跳步） | `references/first-bringup.md` |
| 2.x 的教程/代码搬到 3.x/4.x 对不上，要知道**变在哪一版之间** | `references/versions-and-apis.md` §2.1 |
| `ImportError: cannot import name 'Xlnk'`（写成 `pynq.Xlnk` 时是 `AttributeError`，同一件事） | `references/versions-and-apis.md` §2.1 |
| `from pynq.ps import Register` 起不来——是被删了还是搬家了 | `references/versions-and-apis.md` §2 |
| 同一个名字在板端与主机远程模式指向不同的类，先判自己在哪种模式 | `references/versions-and-apis.md` §1 |
| 教程里写 `from pynq import MM`，自己的仓库也能 import，怀疑是官方 API | `references/versions-and-apis.md` §2.2 |
| 想查"这一版这个 API 到底怎么解释参数"——代码与 docstring 说法不一致（典型：`transfer(array, start=…)` 的 `start`，3.1.2 `lib/dma.py:130`/`:347` 两处 docstring 写 "Offset into array to start."，4.0.0 同两处改 "Byte offset into array to start."；**没有任何一版写"元素"**，单位最终由代码定） | `references/versions-and-apis.md` §4 |
| 想知道**我这一台**这一版到底导出了哪些名字 | `references/versions-and-apis.md` §3 |
| `Overlay(...)` 成功但拿不到 IP：`KeyError`、`AttributeError`、`RuntimeError` 三种文本长得不一样 | `references/overlay-metadata.md` §3.1 |
| 句柄拿得到但类型是 `DefaultIP`（驱动退回——它丢的是驱动类那层 API，**不会**把 `register_map` 变空） | `references/overlay-metadata.md` §2 |
| 重下之后旧句柄还活着（`ip_dict` 里有它，句柄却往老地址写） | `references/overlay-metadata.md` §3.2 |
| `ol.<ip名>` 读得到但 `del ol.<ip名>` 报 `AttributeError`；想"只刷新句柄" | `references/overlay-metadata.md` §3.2（`__delattr__` 不回落到 `__getattr__` 那两条） |
| partial 重下之后 `is_loaded()` 变成比名字、或某次 `ol.reset()` 之后别的对象全说"没加载" | `references/overlay-metadata.md` §3.2 末段与 §4（`if not bitstream.partial` 那道门） |
| 只想 `download=False` 看看这一版元数据里有什么 | `references/overlay-metadata.md` §2.1 |
| `.bit`/`.hwh`/`.dtbo`/`.xsa` 谁必须与谁同名同批 | `references/overlay-metadata.md` §1 |
| 只重配一块 PR 区域（partial 位流） | `references/overlay-metadata.md` §4 |
| `remove()` 不存在；`free()` / `reset()` / `remove_dtbo()` 各做什么 | `references/overlay-metadata.md` §3 |
| 要写一个反复加载/卸载的测试脚本 | `references/overlay-metadata.md` §5 |
| `ip.array[i]`、`ip.register_map.keys()` 这类写法抛 `AttributeError` | `references/mmio-registers.md` §3 |
| `register_map` 报 "only available if the .hwh is provided"（连同 `ip_dict['registers']` 一起没） | `references/mmio-registers.md` §3 |
| 寄存器写了没反应——先分清"没生效"还是"这笔写没返回" | `references/mmio-registers.md` §4 |
| `MMIO` 报 `Unaligned read: offset must be multiple of 4.`（写侧逐字是 `Unaligned write: offset must be multiple of 4.`，**没有 "a"**；五版同形指的是**文案**，4.0.0 `mmio.py:123`/`:155`，抛的类型是 `MemoryError`。**方法名不同形**：2.5.1 的 `MMIO` 类里没有 `read`/`write`，公开的是 `read_mm`/`write_mm`/`read_reg`/`write_reg`（`:110`/`:140`/`:178`/`:208`），那对 `read`/`write` 在 `_AccessHook` 上（`:45`/`:48`；4.0.0 同结构，`_AccessHook` `:14`、`MMIO` `:26` 起、`read` 在 `:87`））、想读第 N 个字、8 字节读回来顺序怪 | `references/mmio-registers.md` §2 |
| 报 `Device does not have capabilities for MMIO`——先弄懂 `mm.write` 是构造期按哪三条能力位绑的 | `references/mmio-registers.md` §1 |
| 读回恒 0 或恒 F（不是值不对，是根本没接上） | `references/mmio-registers.md` §4 |
| 板上跑的 **PL** 是哪一版——`md5sum` 对上了为什么还不够 | `references/mmio-registers.md` §5 |
| 改了控制字的位定义，固件与上位机没同步 | `references/mmio-registers.md` §6 |
| `allocate` 给的尺寸是元素还是字节、dtype 默认是什么 | `references/buffers-and-cache.md` §1 |
| 物理地址属性叫什么、`physical_address + 偏移` 这种手算为什么不行（同步范围本来就跟着视图走；释放那一侧的危险**不是**"在视图上调 `freebuffer()` 会解掉一段映射"——板端 3.0.1+ 上那一次调用是空转，2.5.1/2.7.0 上挂了 `pointer` 的视图会真的退回缓存，远程档直接 `AttributeError`——而是**原始对象被释放之后视图仍被拿着**） | `references/buffers-and-cache.md` §1 |
| `allocate` 的 buffer `close()` 没报错也没回收；`CmaFree` 前后差值能证"这个写法回收了"（但它与 `allocate` 是否同一池没核实） | `references/buffers-and-cache.md` §2 |
| 反复 `Overlay(...)` 之后东西不回收（引用还活着：循环变量、异常 traceback、Jupyter 的 `In`/`_`） | `references/overlay-metadata.md` §3 |
| cache 维护方向写反（第一次对、第二次读到旧的）、尾巴不足一行 | `references/buffers-and-cache.md` §3 |
| 基址明明是 4 对齐的，DMA 还报 `unaligned` | `references/dma-channels.md` §1 |
| 报 `Transfer size is {} bytes, which exceeds the maximum DMA buffer size {}.`（2.7.0 起逐字，SD 侧 4.0.0 `lib/dma.py:143-145`；**2.5.1 是另一种写法**：`Transferred array is {} bytes, which exceeds the maximum DMA buffer size {}.`，`:116-118`，而且它按 `array.nbytes` 判）；或"没报超限"却搬不动，想知道 SG 替你占了多少内存 | `references/dma-channels.md` §1 |
| cyclic 模式停不下来、误置之后 `wait()` 一直报错 | `references/dma-channels.md` §1 |
| `wait()` 挂住、想知道搬完了没有、`transferred` 能不能当判据 | `references/dma-channels.md` §2 |
| 要一份端到端最小正确写法（搬一次并证明它完成） | `references/dma-channels.md` §3 |
| `Interrupt(...)` 报 `No Pin of name`；或那张表本身是空的（不是名字错） | `references/interrupts.md` §1 |
| 报 `Could not find UIO device`；想自己写 `axi_intc` 的 enable/ack | `references/interrupts.md` §1.1 |
| `Interrupt.wait()` 是协程、`wait(2)` 报 `TypeError`（没有 timeout 这个参数） | `references/interrupts.md` §2 |
| 换 overlay 之后中断不来了 | `references/interrupts.md` §3 |
| 中断驱动的收尾循环该长什么样 | `references/interrupts.md` §4 |
| "挂住 / 不动 / 结果不对 / 中断不到"四类现象该从哪棵树下 | `references/debug-triage.md` §2 |
| **寄存器侧全通、搬运/引擎侧一步不动**（软件这边查完了，下一步回设计侧数那几路时钟引脚） | `references/debug-triage.md` §2 树 A 第 1 步 |
| 一切都绿但结论可疑——查自己踩了哪种"假绿" | `references/debug-triage.md` §3 |
| 性能数怎么量才不自骗（取最好一次、只跑一遍） | `references/debug-triage.md` §4 |
| 要一份能贴进问题单的取证包 | `references/debug-triage.md` §5 |
| 不知道现在这条结论属于哪一层（没报错 / 元数据里有 / 硬件真做了） | `references/debug-triage.md` §1 |
| 数据字节序、通道序、位宽截尾（PL 侧数据表示；本包只排除 dtype、尺寸与搬运量） | `fpga-board-development/references/zynq-pynq.md` §8 |

几组最容易互相抢读者的行，判别条件写在这里：

- **"这版有哪些名字" vs "我这版元数据里有没有这个 IP"**：`dir(pynq)` 那一族是**模块导出面**，
  走 `versions-and-apis.md` §3（它同时讲板端与远程两种环境各自导出什么）；
  "设计里那个 IP 在不在、`phys_addr` 是多少"是**这版比特流的元数据**，走
  `overlay-metadata.md` §2.1（`download=False` 那条就是为此开的，它也不动硬件）。
- **"中断不来"的三种成因分三行**：旧 `Interrupt` 对象被作废（换过 overlay）→`interrupts.md` §3；
  `free()` 在 3.1 上还多关了一次 device、下一版加载要重连 →`overlay-metadata.md` §3 那张生命周期表；
  两个同基名 `.dtbo` 互相把对方的中断节点摘掉 →`overlay-metadata.md` §1。
  先分清"是对象死了、连接死了，还是节点没了"，三者的修法互不通用。
- **"结果不对"分两层**：搬没搬完看 `dma-channels.md` §2（四个口一起看；`transferred` 的写点是
  `__init__` 与每次 `transfer()` 置 0（4.0.0 SD `lib/dma.py:65`/`:155`，SG `:252`/`:445`），
  只有 `wait()`/`wait_async()` 把它更新成引擎计数里的实际值（SD `:185`/`:198`）——所以"等之前读它
  必然是 0"成立，但"只有等待会写它"不成立）；
  搬完了但内容旧/尾巴坏看 `buffers-and-cache.md` §3（方向与行粒度）。顺序是先 §2 后 §3，反过来会把
  完成问题误判成缓存问题。
- **`MemoryError` 有两行**：缓冲池（CMA）那条走 `buffers-and-cache.md` §2 的 `CmaFree` 差值实验；
  反复加载 overlay 的那条走 `overlay-metadata.md` §3。这两族的释放路径**按版本不是一条**
  （见本节第 6 条那三档：3.0.1 显式 `xclFreeBO`；3.1.2/4.0.0 的普通 `allocate()` 缓冲在 `freebuffer()` 里
  **同步** `libc.munmap` 再 `del self.bo`（要等引用归零的是 BO 对象、不是那块映射），那条 `weakref.finalize`
  挂的是 `_xrt_allocate` 的 `pointer` **形参**非 `None`（frame cache 复用旧缓冲那条路）；2.5.1/2.7.0 走 XRT 那一步），
  **`CmaFree` 量不到 mmap/fd/驱动实例**是这一族的机理推断，本包没有板、没量过——所以
  "拿它当'没泄漏'的结论会一直读到一个不变的 0"是**待验证的预测**，不是读数：
  板上要用它做判据，先跑一次故意不释放的对照臂证明它会动。
- **同一句"地址不对"落在两行**：`.hwh`/`.bit` 不是同一次导出（元数据本身就是上一版）→
  `overlay-metadata.md` §1；对象是你手上之前的旧句柄 →`overlay-metadata.md` §3.2。
  区分办法是 §3.2 那三行 `print`（比对句柄与 `ip_dict` 的自洽），它判不出混批；混批要和 Vivado
  Address Editor 里的值逐字比（§1 给的判据）。
- **同一句"寄存器写了没反应"跨两个包**：判据是**你手上跑的是什么**——Python 里有 `MMIO`/`ip` 句柄、
  进程是 PYNQ 那一侧 → 本包 `mmio-registers.md` §4（它管的是 Python 到 `/dev/mem` 这条路，
  含"这笔写根本没返回"与"读回不等于生效"两种形状）；裸机 C / xsdb `mwr` / Vitis 应用里写
  `Xil_Out32` → 隔壁 `fpga-board-development/references/board-bringup.md` §4（那条五步分诊没有
  Python 层，第一步是"这笔写有没有返回"，读的是总线与地址译码）。两边给的**第一步动作不同**，
  所以选错包不是"多看一页"，是会照着错的命令敲。

## 4. 本包不覆盖的几件事（往哪里查）

| 事情 | 为什么不在这里 | 现在能做的 |
|---|---|---|
| `.dtbo`/`.bit` 的**生成与刷新**（设备树叠加怎么产、改名之后怎么重产） | **两个技能包都不给这一步**：本包只管运行时，隔壁包管到"BD 导出与整组配套"（`fpga-board-development/references/vivado-project-bd.md` §3），`.dtbo` 的生成那一格它也没核实过 | 板上先做两件能做的：比 `.bit`/`.hwh`/`.dtbo` 的时间戳是否同批；把 `PL.interrupt_pins` 的键与这一版 BD 应有的中断源逐个对，少一个就是叠加没进去。**不要靠删掉旧 `.dtbo` 来"强制重算"**——删除不触发任何重新生成，而该文件正是中断/UIO 绑定的载体。真要找生成方，看你用的镜像里那套叠加工具的文档，别在两包里搜 |
| 开机自动加载某个 overlay | 属于启动介质与镜像那一层；本包不管启动，隔壁包也只到"启动镜像产物"（`fpga-board-development/references/board-bringup.md` §2 与 §2.1） | 先在目标上看有什么（`ls /usr/bin/pynq-* /sbin/pynq-*`、`cat /etc/pynq_release.txt`），再读该工具自己的 `--help`；改动按不可逆动作对待。**断电之后板上跑的是哪一版**这一问可以答：`fpga-board-development/references/board-bringup.md` §2 那张表，加上它 §1 的身份读回 |
| VIDC / `axi_vdma` 的帧与行语义 | 与 AXI DMA 是两套东西，别套本包 DMA 页的完成判定 | 用当前版本的驱动属性现场导出一次再看；`ip_dict[name]['type']` 能区分 `axi_dma` 与 `axi_vdma` |
| HP/ACP 口**位宽与拓扑该不该这么接** | 位宽/连线是设计侧决定的 | 但"运行时这一路的位宽与上限从哪读"在**本包**：`references/debug-triage.md` §4 —— 从 `description["parameters"]` 里读 `*_DATA_WIDTH` 那一族参数（4.0.0 `lib/dma.py:661` 取的就是 `c_m_axi_mm2s_data_width` 再 `>> 3` 换成字节），再按竞争者列总需求。**`bus_width` 不是 API 名**，它只是本页举例用的变量名：`grep -rIn bus_width` 五版在**两种口径下都是 0**（`pynq/` 子树 0，整棵树 0）。正向对照 `c_m_axi_mm2s_data_width` 的命中数**取决于口径**：`pynq/` 子树里 2.5.1=0、其余四版各 1；整棵树是 8/9/9/9/1 个文件（2.5.1 那 8 个全在 `boards/` 下：5 个 `.hwh` + 3 个 `.tcl`，一个都不在 `pynq/` 里）⇒ 先写口径再谈命中数，否则"2.5.1 连它也没有"在两处说法里自相矛盾 |
| ZynqMP/RFSoC 上 SMMU 与地址翻译的**配置** | 平台配置层，两包都不给 | 症状识别在本包 `references/debug-triage.md` §2 树 A3（PL 报 Slave Error 而 PS 读回正常）；地址错误的分层判据在隔壁包 `fpga-board-development/references/zynq-pynq.md` §2.1；配置那一层查平台文档 |
| 一笔访问卡死之后怎么撤回 | 本包依的口径是"用户态没有撤回到达事务的接口"——**这是平台/内核那一层的机理，本包没有板、没有一条臂证明它，也没有一条反证**；同族的"重启 kernel 救不回来"见 §1 第 11 条的层级标注 | 按需要断电重启对待（断电属于不可逆动作，见 §5）；重启后第一件事读版本号寄存器确认板上是哪一版（`fpga-board-development/references/board-bringup.md` §1 的身份读回） |
| 两个进程/notebook 同时管同一块 PL | 没有所有权机制可依 | 按"PL 只有一个所有者"用：重下只在一个进程里做，另一个进程要读寄存器就自己 `MMIO(base, len)` |

## 5. 危险动作

- 往 `/sys/kernel/config/device-tree/overlays` 写、删那个目录下的条目 = 增删设备树叠加，会影响
  之后所有进程看到的中断/UIO；不要拿它当调试手段。
- `Overlay(...)` / `.download()` 会**重置 PL**：PS 侧握着旧句柄的在途 AXI 事务可能永不返回。
  反复重下之前先把会打 PL 的主停干净（各通道**用 `MMIO` 写 RS=0**，cyclic 下再补 `0x0004` 复位；
  `stop()` 在引擎异常时自己会自旋，见 `dma-channels.md` §2）。
- 擦 QSPI/SD 上的镜像、改启动模式、改启动介质属于**不可逆**动作，交给 `fpga-board-development`
  的"命令边界与不可逆动作"一节；两边的清单合起来看。
- 破坏性图案、扫位、改 FCLK 分频都会改硬件状态：先读原值、`finally` 复原、把原值留在记录里。

## 6. 参考文件（按需读，不要全载）

- `references/first-bringup.md` — 从 Vivado 导出到能报数的走查，每步"看到什么才算过"与失败去向。
- `references/overlay-metadata.md` — 一套 overlay 有哪些件、`download=False` 的字段形状、
  生命周期（`free`/`reset`/`remove_dtbo`/`pr_download`）、重下之后句柄为什么不新鲜、三种异常的区别。
- `references/mmio-registers.md` — 三条访问路径的真实名字、字节 vs 字、写了没反应的两种坏法、
  身份寄存器。
- `references/buffers-and-cache.md` — `allocate` 的真实形状、释放与 `close()`、一致性方向与粒度、
  把"漏没漏"变成一个数。
- `references/dma-channels.md` — 通道与 `None`、上限来源与对齐、SDMA/SG/micro 的差别、DMACR 的
  条件、完成判定四口、错误位与出错后的恢复、cyclic 的脏状态。
- `references/interrupts.md` — `Interrupt` 的校验方式、`axi_intc` 由驱动接管哪些寄存器、直连 PS 那支
  的 UIO 连接键、`wait()` 的协程性质与超时、重下之后对象失效。
- `references/versions-and-apis.md` — 导出面迁移线、远程模式换类、版本之间会咬人的口径。
- `references/debug-triage.md` — 三层结论的取证清单、常见假绿形态、分诊树、性能口径。
