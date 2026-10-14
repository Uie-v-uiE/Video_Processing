---
name: pynq-overlay-development
description: 用于在 PYNQ（Zynq-7000 的 Pynq-Z1/Z2、Ultra96、ZynqMP 的 ZCU102/104/K26、RFSoC 等）上做 Overlay 加载、寄存器访问、缓冲区与 DMA 搬运、中断等待、板端性能测量与问题定位的工作。触发场景：`Overlay(...)` 加载后拿不到 IP 或 `KeyError`、位流与 `.hwh/.xsa/.dtbo` 配套问题、`download=False` 之后哪些字段有值、部分位流只重配一块 PR 区域、`register_map` 与 `mmio.array` 的偏移和复位值、`MMIO.read/write` 报未对齐或报「Device does not have capabilities」、`pynq.allocate` 的 dtype 与物理地址、缓冲区释放与 `close()`（2.5.1 是静默 `pass`、3.x/4.x 只发 DeprecationWarning）、DMA 报 unaligned/exceeds maximum、`wait()` 挂死或超时、`wait_async` 看起来永远存在、传输半新半旧或首块尾块坏、中断 `Interrupt(...)` 构造失败与没有 timeout 形参、反复换 overlay 之后结果不对、板端 Jupyter 与远程开发模式的行为差别、`DMA.transfer()` 不抛异常而 `transferred` 一直是 0、寄存器侧全通但搬运侧一步不动（这一层要回设计侧数时钟引脚）、`CmaFree` 看不见 mmap 与 fd 泄漏、从 2.x 的 `Xlnk` 迁到 3.x/4.x、第一次把自定义 IP 从 Vivado 导出跑到板上验证。不用于 Vivado/Vitis 侧的 RTL、综合、约束与时序收敛（用 `fpga-board-development`），也不用于与 PL 无关的纯 Python。
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
2. **`.dtbo` 的基名是它的身份。** 两个不同目录、同基名的 `.dtbo` 会落到同一个 configfs 条目，
   加载后者会把前者的中断/UIO 节点静默摘掉。要共存就必须不同名。
3. **`write()` 不报错不等于写到了。** 至少三种图案 + 读回，恒 0 / 恒 F 不算通过；
   图案只往确认过没有副作用的偏移写，写完复原。
4. **`MMIO.read/write` 的 offset 是字节，`mmio.array[]` 的索引是字。** 混用的表现是"读到隔壁寄存器"。
5. **`pynq.allocate` 默认 `dtype="u4"`**，不是字节数组；`PynqBuffer` 要从 `pynq.buffer` 导入，
   顶层 `pynq` 只导出 `allocate`。
6. **`buf.close()` 是废弃的空操作**：3.1/4.0 里它发一条 `DeprecationWarning`（2.7.0 起就有），
   而 **2.5.1 里是空 `pass`、连告警都没有**——所以"没看到警告"不能反过来证明你没在用它。释放靠退出 `with` 或
   `freebuffer()`；漏没漏只看连续内存池的读数，不看有没有报错。
7. **切片交给 DMA，不要手算 `physical_address + 偏移`。** 手算**不会**绕过同步记账，也**不会**让范围错位：
   `flush()`/`invalidate()` 用的就是 `self.offset`/`self.nbytes`（4.0.0 `buffer.py:104-114`），而
   `__array_finalize__` 给视图算的是**视图自己**的 offset（`:50-56`：`offset = self.virtual_address -
   obj.virtual_address`，`self.offset = obj.offset + offset`），而 `nbytes` 是"元素数 × itemsize"：
   **连续切片**下同步范围正好等于视图碰到的那段，**步长切片（如 `a[::2]`）下它只盖住前半段，
   尾部静默漏同步**（判据是 `flags['C_CONTIGUOUS']` 与 `__array_interface__['strides']`；
   两条出路写在 `buffers-and-cache.md` §1）。
   **真正的危险在释放那一侧**：`freebuffer()`（3.1.2/4.0.0 `buffer.py:65-82`）走的是
   `libc.munmap(self.virtual_address, self.nbytes)` 加 `del self.bo`，对切片视图来说这两个量都只是视图的，
   于是视图上那一次调用只释放了一段地址、却把整个缓冲的句柄一起丢掉（它的 docstring 自己就声明
   不管别的引用还在不在），**全程不报错**。
   所以释放只能由**持有原始对象的那一层**做（退出 `with`、或在原始 buffer 上调 `freebuffer()`），
   在视图上调它不报错，坏的是后面（`buffers-and-cache.md` §3 第 2 条是规范写法）。
8. **`transfer()` 的长度上限：SDMA 与 SG 的失败方式不同**，所以判断"有没有超限"不能靠
   "有没有报错"这一件事（分支、算法与恢复见 `dma-channels.md` §1、`debug-triage.md` §2 树 C）。
9. **`wait_async` 是类上的协程，`hasattr` 永远为真。** 判断中断接没接要看通道实例的 `_interrupt`
   和 IP 元数据里的 `interrupts`，别看方法存不存在。
10. **`wait()` 没有 timeout 形参。** 第一次上板不要裸等；超时自己包，并知道包起来的代价是
    后台线程与一个还在跑的引擎。异常之后先把引擎弄停再继续——但「弄停」只能用 `MMIO` 写 RS=0
   加自己轮询 SR：`stop()`/`transfer()`/`wait()`/`start()` 内部都有无上界的自旋（`dma-channels.md` §2 那条）。
11. **一次访问把 CPU 卡住，说明这笔事务永远等不到响应。** 它不在 Python 的状态里，
    重启 kernel 救不回来；这类现象要按通路问题处理，不是按值设错处理。

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
| 想查"这一版这个 API 到底怎么解释参数"——代码与 docstring 说法不一致（典型：`transfer(array, start=…)` 的 `start` 是元素还是字节） | `references/versions-and-apis.md` §4 |
| 想知道**我这一台**这一版到底导出了哪些名字 | `references/versions-and-apis.md` §3 |
| `Overlay(...)` 成功但拿不到 IP：`KeyError`、`AttributeError`、`RuntimeError` 三种文本长得不一样 | `references/overlay-metadata.md` §3.1 |
| 句柄拿得到但类型是 `DefaultIP`（驱动退回——它丢的是驱动类那层 API，**不会**把 `register_map` 变空） | `references/overlay-metadata.md` §2 |
| 重下之后旧句柄还活着（`ip_dict` 里有它，句柄却往老地址写） | `references/overlay-metadata.md` §3.2 |
| 只想 `download=False` 看看这一版元数据里有什么 | `references/overlay-metadata.md` §2.1 |
| `.bit`/`.hwh`/`.dtbo`/`.xsa` 谁必须与谁同名同批 | `references/overlay-metadata.md` §1 |
| 只重配一块 PR 区域（partial 位流） | `references/overlay-metadata.md` §4 |
| `remove()` 不存在；`free()` / `reset()` / `remove_dtbo()` 各做什么 | `references/overlay-metadata.md` §3 |
| 要写一个反复加载/卸载的测试脚本 | `references/overlay-metadata.md` §5 |
| `ip.array[i]`、`ip.register_map.keys()` 这类写法抛 `AttributeError` | `references/mmio-registers.md` §3 |
| `register_map` 报 "only available if the .hwh is provided"（连同 `ip_dict['registers']` 一起没） | `references/mmio-registers.md` §3 |
| 寄存器写了没反应——先分清"没生效"还是"这笔写没返回" | `references/mmio-registers.md` §4 |
| `MMIO` 报 `offset must be a multiple of 4`、想读第 N 个字、8 字节读回来顺序怪 | `references/mmio-registers.md` §2 |
| 报 `Device does not have capabilities for MMIO`——先弄懂 `mm.write` 是构造期按哪三条能力位绑的 | `references/mmio-registers.md` §1 |
| 读回恒 0 或恒 F（不是值不对，是根本没接上） | `references/mmio-registers.md` §4 |
| 板上跑的 **PL** 是哪一版——`md5sum` 对上了为什么还不够 | `references/mmio-registers.md` §5 |
| 改了控制字的位定义，固件与上位机没同步 | `references/mmio-registers.md` §6 |
| `allocate` 给的尺寸是元素还是字节、dtype 默认是什么 | `references/buffers-and-cache.md` §1 |
| 物理地址属性叫什么、`physical_address + 偏移` 这种手算为什么不行（同步范围本来就跟着视图走，危险在 `freebuffer` 那一侧） | `references/buffers-and-cache.md` §1 |
| `allocate` 的 buffer `close()` 没报错也没回收；`CmaFree` 前后差值能证"这个写法回收了"（但它与 `allocate` 是否同一池没核实） | `references/buffers-and-cache.md` §2 |
| 反复 `Overlay(...)` 之后东西不回收（引用还活着：循环变量、异常 traceback、Jupyter 的 `In`/`_`） | `references/overlay-metadata.md` §3 |
| cache 维护方向写反（第一次对、第二次读到旧的）、尾巴不足一行 | `references/buffers-and-cache.md` §3 |
| 基址明明是 4 对齐的，DMA 还报 `unaligned` | `references/dma-channels.md` §1 |
| 报 `exceeds maximum`；或"没报超限"却搬不动，想知道 SG 替你占了多少内存 | `references/dma-channels.md` §1 |
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
- **"结果不对"分两层**：搬没搬完看 `dma-channels.md` §2（四个口一起看；注意 `transferred`
  只在 `wait()`/`wait_async()` 里才被写，等之前读它必然是 0）；
  搬完了但内容旧/尾巴坏看 `buffers-and-cache.md` §3（方向与行粒度）。顺序是先 §2 后 §3，反过来会把
  完成问题误判成缓存问题。
- **`MemoryError` 有两行**：缓冲池（CMA）那条走 `buffers-and-cache.md` §2 的 `CmaFree` 差值实验；
  反复加载 overlay 的那条走 `overlay-metadata.md` §3——`CmaFree` 量不到 mmap/fd/驱动实例，
  拿它当"没泄漏"的结论会一直读到一个不变的 0。
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
| HP/ACP 口**位宽与拓扑该不该这么接** | 位宽/连线是设计侧决定的 | 但"运行时这一路的位宽与上限从哪读"在**本包**：`references/debug-triage.md` §4 —— `bus_width` 从 `ip_dict[...]` 的参数（`*_DATA_WIDTH` 那一族）读，再按竞争者列总需求；只有"该不该这么接"要回设计侧 |
| ZynqMP/RFSoC 上 SMMU 与地址翻译的**配置** | 平台配置层，两包都不给 | 症状识别在本包 `references/debug-triage.md` §2 树 A3（PL 报 Slave Error 而 PS 读回正常）；地址错误的分层判据在隔壁包 `fpga-board-development/references/zynq-pynq.md` §2.1；配置那一层查平台文档 |
| 一笔访问卡死之后怎么撤回 | 用户态没有撤回到达事务的接口 | 按需要断电重启对待；重启后第一件事读版本号寄存器确认板上是哪一版 |
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
