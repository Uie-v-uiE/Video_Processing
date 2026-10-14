# Overlay 与元数据：加载、配套、切换、失效

## 1. 一套 overlay 有哪些件，谁必须同名同批

| 件 | 作用 | 漂了的后果 |
|---|---|---|
| `.bit`（全）/ `.bin`（部分） | 配置 PL | 与元数据不同批 → 地址打到别的从设备，读回像"随机数" |
| `.hwh` / `.xsa` | IP 实例名、`phys_addr`、`addr_range`、寄存器与中断信息 | 地址与实例名来自上一版 → `KeyError` 或写飞 |
| 解析后的视图（`ol.ip_dict` 等） | Python 侧看到的那一份：构造时从 `self.device.parser` 深拷贝进来（4.0.0 `overlay.py:324` 与 `:331`；3.1.2 同两句在 `:323` 与 `:330`） | 视图与这批 `.hwh/.xsa` 不一致 → 名字或地址对不上。**判据**：把要用的实例名与 `phys_addr` 从 `ol.ip_dict` 里打出来，与 Vivado Address Editor 那一行逐字比，别比"我记得叫什么" |
| `.dtbo` | 设备树 fragment（中断、UIO 绑定等） | 没有/不匹配 → 没有 `/dev/uio*`，`Interrupt` 起不来 |

`Bitstream.__init__(bitfile_name, dtbo=None, partial=False, device=None)`（`bitstream.py:60`）与
`Overlay.__init__(bitfile_name, dtbo=None, download=True, ignore_version=False, device=None,
gen_cache=False)`（`overlay.py:290-291`）说明三件事：Overlay 本身就是 Bitstream 的子类
（`class Overlay(Bitstream)`，`overlay.py:203`）、下载在构造里默认发生、dtbo 可以被显式指定。

`.dtbo` 的默认查找规则是能算出来的：`get_dtbo_path(bitfile)` = `splitext(bitfile)[0] + '.dtbo'`
，`Bitstream` 在 `dtbo=None` 时
就试这一个（`bitstream.py:136-139`）。

但**缺 `.dtbo` 是静默的**：走默认路径且文件不存在时 `self.dtbo` 就留在 `None`，不报错也不警告；
只有你**显式传**一个找不到的路径才 `IOError("DTBO file {} does not exist.")`（`:141-143`）。

读数方向要写准，反了就是一条假绿（`ol.dtbo` 只是**构造时算出来的路径**，见 §2.1）：

```python
import os
print("dtbo =", ol.dtbo, "存在吗 =", bool(ol.dtbo and os.path.exists(ol.dtbo)))
# None    -> 连文件都没找到：设备树那一层肯定没进去
# 路径且存在    -> 只证明"文件在"，**不证明内核已经装载了它**，更不证明里面声明了中断
```

要把"设备树到底进没进去"变成**非破坏性**的判据，问板子的口子就是驱动自己用的那一个。
`SYSTEM_DEVICE_TREE_PATH = '/sys/kernel/config/device-tree/overlays'`，每个叠加是它下面的一个目录，目录名就是 `.dtbo` 的**基名**
（`get_dtbo_base_name` 的实现是 `dtbo_path.split('/')[-1].split('.')[0]`——**在第一个点就截断**，`devicetree.py:44-48`；所以不止 `a.dtbo` 与 `a.bak.dtbo` 会撞同一个键，任何多点名字都归到第一段。「先 `.remove()` 再 `.insert()`」那两步在 `pl_server/device.py:363-368`，不在 `devicetree.py`），目录里有两个文件：

```bash
ls /sys/kernel/config/device-tree/overlays/    # 期望看到 design_1（= .dtbo 基名）
cat /sys/kernel/config/device-tree/overlays/design_1/status    # 期望 applied
```

`is_dtbo_applied()` 读的就是这个 `status`（`devicetree.py:77-89`），目录不存在它直接返回 False。
所以"叠加名在不在 + `status` 是不是 `applied`"才是带期望值的判据，`ls /sys/firmware/devicetree/`
那种"看一眼"不是。**再配一条只读差分**：`PL.interrupt_pins` 少一个键、而这个目录在且 `applied`，
说明设备树进去了但那一根针没声明（回到 BD/`.hwh` 与生成侧）；目录不在，才是叠加这一层没进去。

**同名 `.dtbo` 会互相顶掉**——这是上面那条命名规则的直接后果，也是"中断上周还好这周不来"的一个
真实成因。`insert_dtbo` 每次都是先 `.remove()` 再 `.insert()`，而字典的键是**基名**：`overlays/a/design_1.dtbo` 与
`overlays/b/design_1.dtbo` 落到**同一个** configfs 目录。加载 B 会先把 A 的叠加 rmdir
（`devicetree.py:122-127`，驱动注释写的是 "Remove the dtbo file from the device tree"），
A 的位流可能还配在 PL 里，但它的中断/UIO 节点已经没了。反方向也成立：`remove_dtbo()` 按
`self.dtbo` 的基名删（`bitstream.py:183`），所以**释放 A 会把 B 的设备树摘掉**。
两个 overlay 的 `.dtbo` 因此必须**基名互不相同**——注意这与本节开头那条不是一回事：
"各自跟自己的 `.bit` 同名同批"是**配套**要求（谁与谁必须同一批导出），它**不区分**两个 overlay；
上面那对反例 `overlays/a/design_1.dtbo` 与 `overlays/b/design_1.dtbo` 恰恰**都满足**配套要求，
却撞在同一个基名上。所以要让基名不同，得改**设计/top 名**（`design_a`/`design_b`），
目录名 `a`/`b` 不参与键。也可以显式传 `Overlay(bitfile_name, dtbo=...)`（4.0.0 `overlay.py:290-291` 的签名里有 `dtbo`），但**它只换文件、不换键的算法**——键仍按同一条 `split('.')[0]` 规则算，所以照样会撞。

**不要用"删掉旧的 `.dtbo` 再重载"来"强制重算"**——删除不会让任何东西重新生成它（生成本领在
本包与隔壁技能的射程之外），而那个文件正是中断/UIO 绑定的唯一载体：删了之后 `interrupt_pins`
变空、`/dev/uio*` 没有，包里没有任何恢复步骤。要重生成就回到生成它的那条工具链，按你自己镜像
文档做。

## 2. 加载后先做三件只读的事

```python
from pynq import Overlay, PL
ol = Overlay("/home/xilinx/designs/my/design_1.bit")

print(sorted(PL.ip_dict.keys()))    # 实例名 + fullpath：后面所有名字都从这里取
print({k: v.get("phys_addr") and hex(v["phys_addr"]) for k, v in PL.ip_dict.items()})
print(dict(PL.interrupt_pins))    # 中断针的合法字符串（见 interrupts.md）
print("dtbo =", ol.dtbo, "| loaded =", ol.is_loaded())
```

`is_loaded()` 不能当身份判据，原因在源码里：它先比 `timestamp`，而 **`self.timestamp == ""` 时
退化成比文件名**。
换个内容不同但同名的 `.bit`、或者 timestamp 没被填上的那条路，都会让它返回 `True`。
所以这一行只打印、不作判据；身份只看第 4 步那个版本寄存器的读回。


`ip_dict` 的条目形状：`overlay.py:257-264` 的 docstring 写的是

```
{str: {'phys_addr': int, 'addr_range': int, 'type': str,
    'parameters': dict, 'registers': dict, 'state': str}}
```

三个提醒：

1. docstring 里**没有** `config` 这个键（有些旧资料会列它）。别把 docstring 当实测——想知道你这版
   有什么，就 `print(sorted(ol.ip_dict['<ip>'].keys()))`。完整键集由 `pynqmetadata` 生成，
   不在本文范围内。
2. `type` 是 **VLNV 串**（形如 `xilinx.com:ip:axi_dma:7.1`），驱动就是按它和驱动类的 `bindto`
   做字符串相等来挑的。**别把"`MODTYPE` 这个键没了"当成版本判据**：`ip_dict` 里的键确实叫 `type`，
   但解析器那一侧两版都还在读 `mod.get("MODTYPE")`（两个号各属一版：3.1.2 `pl_server/hwh_parser.py:163`、4.0.0 `pl_server/hwh_parser.py:170`）——
   **"解析器读 MODTYPE"与"驱动按 VLNV 匹配"是两层，不是一层替换了另一层**
   （按 VLNV 绑驱动从 2.5.1 就是这样：2.5.1 `overlay.py:527-528`、3.1.2 `:561`/`:569`、4.0.0 `:558`/`:566`）。这一条与 `first-bringup.md` §7 表第 2 行同口径。
3. `state` 不是硬件状态，是软件记的加载状态，别把它当"PL 在跑这一版"的证据——
   那个证据只能是设计里的版本寄存器读回（`mmio-registers.md` §4/§5）。

**两件"东西在但用不了"必须分开判**，它们症状像、原因不同：

- **`register_map` 抛 "only available if the .hwh is provided"** 的成因只有一个：`_registers` 是空的
  （4.0.0 `overlay.py:734-745`——它判的是 `self._registers` 有没有，**不是驱动是谁**）。
  这一条的路由在 `mmio-registers.md` §3，本节不重讲。
- **驱动退回（`DefaultIP`）不会把 `register_map` 变空**——`DefaultIP` 自己就带这个 property，
  寄存器表在就照样给得出。驱动退回丢的是**驱动类那一层的 API**（DMA 的 `start()`/通道那些名字）。

`_assign_drivers`（4.0.0 `overlay.py:46-80`、3.1.2 `:45-81`）的逻辑是：`type` 完全命中 `bindto` → 用该驱动；只差版本号且
`ignore_version=False` → 打一条 `UserWarning`
`"IP {fullpath} is of type {type} and driver found for [{其他版本}]. Use ignore_version=True to use
this driver."` 然后 **`driver = DefaultIP`**；`ignore_version=True` → 用那个近似版本的驱动。
所以驱动退回的症状是"没报错、IP 对象也在，但 `getattr(ol,'axi_dma_0')` 不是 DMA 驱动"。三步判据（前两行各判上面一件）：

```python
print(type(getattr(ol, 'axi_dma_0')).__name__)    # 'DMA' 还是 'DefaultIP'？→ 驱动有没有退回
print(sorted(ol.ip_dict['axi_dma_0'].get('registers', {})))    # 空 = .hwh 没带寄存器表
print(ol.ip_dict['axi_dma_0']['type'])    # 与 bindto 逐字符比
```

### 2.1 `download=False` 的时候，哪些东西有值、哪些没有

`Overlay.__init__` 的顺序决定了这件事（`overlay.py:319-354`）：解析元数据、深拷贝各字典、
绑定驱动、建 `_IPMap` 全都在 `if download: self.download()`（`:354`）**之前**就发生了。所以
"`download=False`"不等于"什么都没发生"：

| 你要的东西 | `download=False` 时 | 依据 |
|---|---|---|
| `ol.ip_dict` / `hierarchy_dict` / `gpio_dict` | **有值**（来自 `self.device.parser`） | `:324`、`:326-331` |
| `ol.interrupt_pins` / `PL.interrupt_pins` | 同上，有值（但它是**这张表**，不代表中断已经接通） | 同上 |
| `getattr(ol, 'my_ip_0')`、`ol.my_ip_0`、`ol.<任何IP>` | **`RuntimeError("Overlay not currently loaded")`** —— `Overlay.__getattr__` 先问 `is_loaded()` | `:364-372` |
| `ol.register_map` / `ip.*` | 拿不到（上一条门挡在前面） | 同上 |
| 手写 `MMIO(base, len)` 打寄存器 | 对象能建，但 PL 没配置：读回恒 0，或者**这一笔把 CPU 卡住** | 见 `mmio-registers.md` §4 与 `debug-triage.md` §2 树 A |
| `ol.dtbo` | 仍是构造时算出来的那个值（与是否下载无关） | `bitstream.py:135-143` |

用法上就一句话：**`download=False` 是"先问我这版元数据里有什么"的口，不是"安全的只读探测"口**；
碰任何 IP 之前必须 `ol.download()`，否则报的是那个 `RuntimeError`，不是"设计里没有这个 IP"。

## 3. 换 overlay：没有 `remove()`，有 `free()` / `reset()` / `remove_dtbo()`

3.1 与 4.0.0 的 `overlay.py` 里都没有 `def remove`。**确认的方法要自带正向对照**：
`print(pynq.__version__, "remove" in dir(pynq.Overlay), "free" in dir(pynq.Overlay))` —
第三项必须是 `True`，否则这次扫描/这一次 `dir()` 没看见这个类，前一项的 `False` 不算数
（单条 `hasattr(...)` 的 `False` 尤其不能当"不存在"，理由见本页 §3 末尾那条"`hasattr` 不是无副作用的查询"
与 `debug-triage.md` §3 的同族写法）。真实的生命周期口是这几个：

| 口 | 位置 | 做什么 | 版本差别 |
|---|---|---|---|
| `ol.free()` | `overlay.py:394` | `if self.dtbo: self.remove_dtbo()` —— **只撤设备树，不重载位流** | **3.1 的 `free()` 还多一句 `self.device.close()`**（`v3.1:393-396`），4.0.0 去掉了。这就是"3.1 上 free 之后连 PL server 都关了、下一版加载要先重连"的来源 |
| `ol.remove_dtbo()` | `bitstream.py:174` | 从系统里移除这个 dtbo | — |
| `ol.insert_dtbo(dtbo=None)` | `bitstream.py:185` | 挂上 dtbo | — |
| `ol.download(dtbo=None)` | `overlay.py:402` | 按 `clock_dict` 重配 FCLK（`:422-427`）+ `super().download(self.parser)` + 挂 `.dtbo`。**函数体里没有任何字典赋值**；docstring 说的"字典自动重置"发生在 device 层（`bitstream.py:168` → `pl.py:233`）。它也不重绑 `_ip_map`（§3.2） | 会动硬件：只读排查期间不要调用 |
| `ol.reset()` | `overlay.py:482` | 重新从 parser 取 `ip_dict/gpio_dict/interrupt_*`，且**只在 `is_loaded()` 为真时**才 `device.reset(...)` | 位流没在跑的时候调它，字典刷新了但 PL 没重置——两件事别混着记 |
| `ol.is_loaded()` | `overlay.py:465` | 比对 `self.timestamp == device.timestamp`，**`timestamp` 为空时退化成比 `bitfile_name` 字符串**（`:477-480`） | 它回答的是"这个对象与 device 记的那份是不是同一个"，**不是**"板上跑的功能是不是这一版"：同名 `.bit` 重下之后它照样 `True`，而那时你手上的驱动对象已经是旧的（§3.2）。与 §2 那条"只打印、不作判据"是同一个意思，身份只看版本寄存器读回 |

反复切换时的现实约束：

1. **先把会打到 PL 的主停掉**（两个通道各**用 `MMIO` 写 RS=0**，cyclic 下补 `0x0004`；
   不要用 `stop()` 收尾——它在引擎异常里自旋，见 `dma-channels.md` §2），再下载下一版。
   否则 PS 侧在途事务在 PL 被重置的窗口里等不到响应，表现是"下一次开始一路坏"。
2. **旧对象的引用要断掉**。`Overlay` 持有 mmap、fd、每个 IP 的驱动实例；只要还有一个引用活着
   （循环变量、异常 traceback、Jupyter 的 `In/_`），底层映射就不释放。`del` + 显式断引用 +
   重启 kernel 是三种能立刻区分"软件没清"与"硬件真坏"的手段。
3. **每次切换都重新取句柄**：`getattr(new_overlay, ip_name)`，不要把前一次的 ip 对象留着用；
   `Interrupt` 对象在重下之后明确失效（`interrupt.py` 的 docstring 与 `RuntimeError` 分支）。
4. **下载后第一件事是读回身份**（设计里那个版本/构建号寄存器；为什么 JTAG 侧的 IDCODE 不算身份
   ——它认的是**芯片**不是**设计**——见 `fpga-board-development/references/board-bringup.md` §1）。
   读不回期望值就停在这里。

### 3.1 三种"拿不到"的异常长得不一样，认它们能省一小时

| 你看到的 | 抛出点 | 真正的问题 |
|---|---|---|
| `RuntimeError("Overlay not currently loaded")` | `overlay.py:364-372`（`Overlay.__getattr__`） | 位流**当前不在板上**（`is_loaded()` 为假）——先确认加载与是否被别的 overlay 顶掉 |
| `AttributeError("Could not find IP or hierarchy <name> in overlay")` | `overlay.py:829-830`（`_IPMap.__getattr__`） | 位流在、**这个名字不在这份元数据里**——实例名拼错、或元数据是上一批 |
| `KeyError: 'my_ip_0'` | 你自己写的 `ip_dict['my_ip_0']` | 键不存在；先 `print(sorted(PL.ip_dict))` 再谈别的 |

`getattr(ol, name)` 走前两行，`ol.ip_dict[name]` 走第三行。**同一个"名字不对"在三处报三种错**，
把 `AttributeError` 读成"设计里没这个寄存器"就会去改 RTL——那是在改没有病的地方。

### 3.2 重下位流之后，你手上的驱动对象**还是老的**

机制要先归对地方：`ol.<ip名>` **不是 Overlay 上的属性**。`Overlay.__getattr__`
只做两件事——`if self.is_loaded(): return getattr(self._ip_map, key)`，否则
`raise RuntimeError("Overlay not currently loaded")`（4.0.0 `overlay.py:364-372`，3.1.2 `:363-372`）。
真正懒建并缓存的是 `_IPMap.__getattr__`（类在 4.0.0 `:783`、方法 `:793`、`setattr(self, key, driver)` `:810`），
**缓存挂在 `ol._ip_map` 的 `__dict__` 上**。`download()` 与 `reset()` 都**不会作废这些缓存**。`reset()` 只是把那四个字典重新指向 parser
（`:493-498`：`ip_dict`/`gpio_dict`/`interrupt_controllers`/`interrupt_pins`，`hierarchy_dict`、
`mem_dict`、`clock_dict` 都不在其中），`download()` 的函数体里连字典赋值都没有
（`:402-433` 只有时钟那一段 + `super().download(self.parser)` + `insert_dtbo`）——
docstring 说的"所有字典会自动重置"是**在 device 那一层**发生的：
`Bitstream.download` 只有一句 `self.device.download(self, parser)`（`bitstream.py:168`），
再由 `PL.reset(parser)`（`pl.py:233`，它的 docstring 原话是 "This method must be called after a
bitstream download"）去换 PL 侧的东西。全文件 `delattr` 0 次命中，`_ip_map` 只在两处被赋值。

- `download()` 之前取过的 `dma = ol.axi_dma_0`，重下之后**还是同一个对象**：它的 `MMIO` 仍按老地址
   映射，驱动实例里的 buffer/UIO fd 也都还在。
- 因为缓存不在 overlay 上，**`del ol.axi_dma_0` 删不掉它**（overlay 自己没有这个属性，`del` 走
   `__getattribute__` 找不到就 `AttributeError`）。想"刷新句柄"没有公开的口子，只能换对象。
- 但 **PR 那条路是反的**：缓存被整块换新。要说准归属——`Overlay.pr_download()`
   （4.0.0 `overlay.py:435`）自己只做两件事：`pr_block = self.__getattr__(partial_region)`，
   然后 `pr_block.download(bitfile_name=partial_bit, dtbo=dtbo, program=program)`（3.1.2 `:465-466`）。
   真正换 `_ip_map` 的那句 `self._overlay._ip_map = _IPMap(description)` 在
   **`DefaultHierarchy.download`**（`:946` 起，赋值在 `:989`/3.1.2 `:992`）里面，
   紧挨着它还有一句 `self._overlay._deepcopy_dict_from(self.device)`（`:976`）。
   所以结论是"**走层次对象的 `download()` 会换新缓存与换新字典**"，
   把它记成"`pr_download` 换的"是错的归属（这一条被独立复核抓出来并改正）。
   判新旧仍然用 `id()`：全 bitstream `download()` 之后它必然打印同一个值（没有东西作废缓存），
   **这本身是确认而不是判别**；要判别就拿两条路对比——同一段代码在 `download()` 与
   在层次对象 `download()` 之后各打印一次 `id(ol.<ip>)`，两者应当**不同**。
   **不要反过来把"相同"解释成"bitstream 没下"**：换缓存那句（`:989`/3.1.2 `:992`）排在
   `_load_bitstream(bitfile_name, program)`（`:968`）之后，而 `_load_bitstream` 只在 `program` 为真时
   才 `download()`（4.0.0 `:1024-1027`）——**`program=False` 一样换缓存、`id()` 一样变**。
   所以打印相同值只剩一个解释：那段代码根本没走到层次对象的 `download()`
   （名字没解析到层次对象，或者用的是另一个入口）。


`_description` 那一侧还有一层要分清，而且**顺序决定谁和谁共享**：
`Overlay.__init__` 先 `_deepcopy_dict_from(self.parser)`（4.0.0 `:331`，把 `ip_dict` 等换成 parser 的
**深拷贝**），再用它去 `_complete_description(...)`（`:335-342`）——而
`starting_dict["ip"] = {k: v for k, v in ip_dict.items()}`（`:93`）是**浅拷贝**。
所以刚构造完，`_ip_map._description["ip"][k]` 与 `self.ip_dict[k]` 是**同一批对象**，
`ol.my_ip.description` 之类的"两边不一致"还不会发生。
真正分叉是在之后：`reset()` 把 `self.ip_dict` 直接改指 `self.parser.ip_dict`
（`:493-498`，不是深拷贝），而 PR 那条路会再调一次 `_deepcopy_dict_from`（`:976`）——
两条都把 `ip_dict` 换成了**另一批对象**，而 `_description` 里那份是构造时的旧对象。
从这一刻起"改一边不动另一边"才成立。注意 `ol.ip_dict` 与 `PL.ip_dict` 是两个入口
（前者是 Overlay 实例上的字段，后者走 `PL` 的代理），它们**是不是同一个对象这一包不替你断定**——
一条 print 就能定：`print(ol.ip_dict is PL.ip_dict)`。要比较的永远是"我手上这份"与"我从字典里取的那一份"。
另外 `["interrupts"]` 与 `["gpio"]` 在 `:95-96` 直接写成空字典，
之后没有任何地方填它们，所以 `__getattr__` 的中断/gpio 那两条分支实际取不到东西——
**中断对象不能用 `ol.<中断名>` 拿**，只能 `Interrupt(PL.interrupt_pins[...])` 自己构造
（`interrupts.md` §1 走的就是这条路）。

当场能跑的判据（改前/改后各一次，三行都要打印）：

```python
print("before:", id(ol.axi_dma_0), hex(ol.axi_dma_0.mmio.base_addr))
ol.download()
print("after :", id(ol.axi_dma_0), hex(ol.axi_dma_0.mmio.base_addr))
print("ip_dict now says:", hex(PL.ip_dict["axi_dma_0"]["phys_addr"]))
```

`id` 前后相同 = 拿到的是老句柄（全 bitstream 重下的常态）。用 `mmio.base_addr` 与
`PL.ip_dict[...]["phys_addr"]` 做对照，是因为这两个读数**在所有 IP 上都必然存在**
（`DefaultIP.__init__` 会建 `self.mmio`）。
别写成 `ol.<ip>.description`：`DefaultIP` **不存** `description` 这个属性
（4.0.0 `overlay.py:688-720` 里只赋 `device`/`mmio`（`:695`）/`_interrupts`/`_gpio`/`_registers`，
末行 `:720` 是缺 `registers` 时的 `self._registers = None`），
只有自己做这件事的驱动才有——`DMA` 在 `lib/dma.py:602` 存了，层次对象在 `overlay.py:926` 存了。
对不存它的 IP 用 `.description`，你会得到 `AttributeError`，那是探针写错不是硬件问题。

**唯一自带失效检测的是 `Interrupt`**：它持的是父控制器的 weakref，父级没了就
`RuntimeError("Interrupt invalidated by Overlay change")`。
`MMIO` 支撑的驱动**没有**这种检测，所以它们不会报错，只会安静地往旧地址写。
这正是"重下 overlay 之后画面全 0 / 半新半旧 / 时好时坏"这一类问题的机制来源
（`debug-triage.md` §3 第 12 条"重下位流之后继续用旧句柄"就是它）


正确做法：重下之后就当作换了一个 overlay——**丢掉全部旧引用**，重新 `Overlay(...)`
（或按上表 `free()` 之后重建）。另记一条：`download()` 本身**会动硬件**——它按 `clock_dict`
写 FCLK 分频（4.0.0 `overlay.py:422-427`），所以只读排查期间不要顺手调用它。


两个补充，都是这一节的直接推论：

- **"没有 `delattr`、也没有重建 `_ip_map`" 是靠两个独立视图看出来的，不是一次 grep**：
   3.1.2/4.0.0 的 `overlay.py` 里 `delattr` 各 0 次命中（同文件 `setattr` 有 8 次命中，说明扫描
   看得见这个文件），`__dict__` 的 2 处命中（4.0.0 `:529`、`:845`）都在 `__dir__` 里做名字枚举；
   `_ip_map` 的赋值只有两处——构造时 `:343` 与 PR 路径 `:989`。
- **`hasattr(ol, 名字)` 不是无副作用的查询，而且它可能直接抛错。** 名字存在时 `__getattr__`
   会**当场构造驱动**（`_IPMap.__getattr__`，4.0.0 `:793-810`）——打开 mmap、可能注册驱动实例，
   驱动不支持时吞一条 `UnsupportedConfiguration` 警告退化成 `DefaultIP`。名字不存在时才走
   `AttributeError`（`:829-831`），`hasattr` 才会返回 `False`。**但如果 overlay 根本没加载**，
   `Overlay.__getattr__` 抛的是 `RuntimeError("Overlay not currently loaded")`（`:369-372`），
   而 `hasattr` 只吞 `AttributeError` —— 于是它把异常原样抛出来，不会给你 `False`。
   要判"这个名字存不存在"用 `name in PL.ip_dict`；别用 `hasattr` 探句柄。

## 4. 部分位流（partial）


两个入口，别混：

- `Overlay.pr_download(partial_region, partial_bit, dtbo=None, program=True)`（`overlay.py:435`）
   —— 整块 overlay 对象上的口，`partial_region` 是 PR 块名。
- `DefaultHierarchy.download(bitfile_name, dtbo=None, program=True)`（`overlay.py:946`）
   —— 拿到那个 PR **层次对象**之后的口。层次对象本身由 `_hierarchy_drivers` 注册队列与
   `RegisterHierarchy` 元类绑定（三处行号**按版本各取一次**：4.0.0 是 `overlay.py:545` 建队列、
   `:893` 在元类 `__init__` 里 `appendleft`、`:901` 是
   `class DefaultHierarchy(_IPMap, metaclass=RegisterHierarchy)`；3.1.2 同样三处都在，行号是
   `:548`、`:896`、`:904`；2.7.0 把它们排在 `:531`、`:961`、`:969`），判据是元数据里那一层的 `driver`。

`partial=True` 告诉底层这是部分配置：它只对**生成它的那个全镜像**有效——板上现状不是那个
static 镜像时，下 partial 的结果是配置寄存器被按错位的方式改，症状通常是"某一块从此不动"而
AXI-Lite 一侧仍然活着。所以每次出 partial 都要同时记下它对应的全镜像（连同两者指纹），
切换顺序写成"全 → partial"，不要在未知状态下直接下 partial。

**这一节给的是归属，不是可抄的走法**：上面两个入口的签名归属、"partial 绑定全镜像"这条后果，
加上下面这三条（前两条读源码核实过，第三条在设计侧那一包）。

- **块名**：`partial_region` 要的是元数据里的**层名**，从 `ol.hierarchy_dict` 的键现取
  （§3.1 那张表里 `hierarchy_dict` 的"什么时候有值"就是它的取法时机）；`PL.ip_dict` 里只有 IP 项，
  拿它当层名清单会取到不存在的关键字。
- **`program` 的确切语义**（读到源码，不再标"没核实"）：它**只**决定这一下要不要真的去配置 PL。
  `_load_bitstream` 里是 `if program: self.bitstreams[...].download()`，
  **紧跟一句无条件的 `self.pr_loaded = ...bitfile_name`**（4.0.0 `:1024-1027`、3.1.2 `:1027-1030`、
  3.0.1 `:1126-1129`），而换缓存那句 `_ip_map = _IPMap(description)`（`:989`/3.1.2 `:992`）排在它后面。
  三条后果：① `program=False` 是"**只看元数据、不动 PL**"的合法走法，与本包一贯的"先读再写"一致；
  ② 但它照样把 `pr_loaded` 推进到那个从未生效的 partial，于是 Python 侧认为已经下过了，
  下一次 `download()` 会先对那个位流做 `remove_dtbo()`（`:964-965`）；
  ③ **2.5.1 与 2.7.0 没有这个参数**（`_load_bitstream(self, bitfile_name)`，2.5.1 `:1047`、
  2.7.0 `:1086`），把带 `program=` 的写法抄到那两版会 `TypeError`。
- **"只有那一块被重配"怎么证明**：这是**设计侧的预留要求**，不是运行时能补出来的读数。
  每块各一个只读构建号只能回答"板上是哪一份镜像"，**证不了"只换了那一片"**——
  要每块再有一个重配后会**重新开始计数**的易失标记（自由运行计数器），重配后成对取读数。
  原文见 `fpga-board-development/references/board-bringup.md` §1 里"每块各自一个易失标记"那一段。

## 5. 反复加载的测试脚本骨架

```python
import gc, sys, time
from pynq import Overlay, PL, MMIO

def load_and_verify(bit, expect_id, id_off=0x0, tries=20, delay=0.05):
    """下载 -> 读回身份；身份不对就不要往下跑。返回 (overlay, ip_name)。"""
    ov = Overlay(bit)
    name = next(k for k in PL.ip_dict if k.endswith(expect_id[0]))
    mm = MMIO(PL.ip_dict[name]["phys_addr"], 0x1000)
    for _ in range(tries):
        if mm.read(id_off) == expect_id[1]:
            return ov, name
        time.sleep(delay)
    raise RuntimeError(f"{bit}: 版本寄存器读到 0x{mm.read(id_off):08x}，期望 0x{expect_id[1]:08x} "
                       "—— 位流与元数据不配套，或上一版还没被真正覆盖")

for bit, want in [("a.bit", ("axi_gpio_0", 0x0A000000)), ("b.bit", ("axi_gpio_0", 0x0B000000))]:
    ov = None
    try:
        ov, name = load_and_verify(bit, want)
        ...    # 用 getattr(ov, name) 做本层的测试
    finally:
        ov = None
        gc.collect()    # 断掉引用，让 mmap/fd 真的释放
```

关键不是 `gc.collect()`，是**每轮的身份读数**：它把"软件状态残留"与"设计/元数据不配套"分开，
后者靠重试是永远过不去的。`load_and_verify` 里那句 `next(...)` 在找不到时会抛
`StopIteration`——那是"实例名不在这版元数据里"的读数，给它一个明确的报错比让它穿出去好。
