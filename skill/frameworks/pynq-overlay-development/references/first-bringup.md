# 第一次把自定义 IP 跑到板上：从 Vivado 导出到能报数

一次走到底的顺序，每一步都有"看到什么才算过"。跳步是这类工作最贵的错误 —— 后面每一步的读数都会
失去解释力。RTL/综合/约束侧的细节在 `fpga-board-development`。

## 0. 设计侧先埋三个东西（没有它们，第 3 步之后全是猜）

- **版本/构建号寄存器（只读），放在固定偏移 `0x00`**：`4'hX + 构建日期/计数`。
   偏移要写死并在 IP 的 address block 里就这么定，因为第 4 步按 `0x00` 读——
   两处不一致的话，这一页自己就会造出一个"读不到身份"的假故障。
   它回答两件事：**板上是哪一版**、**AXI-Lite 这条路通不通**。
   **它不回答"PL 的时钟在跑"**——寄存器读得回来只说明寄存器那一路时钟活着；数据通路那一路
   可能是另一个引脚、另一路钟（`debug-triage.md` §2 树 A 与
   `fpga-board-development/references/zynq-pynq.md` §1 就是这一层）。时钟的证据只来自下面那个计数器。
- **一个自由运行的计数器（只读），放在 `0x04`**（每 N 拍 +1，或每处理一个像素 +1）。
   有它才能区分"没时钟"与"没数据"。**设计里有几路时钟域就要几个这种计数器，各自接自己那一路钟**：
   共用一个只能证明"有某个钟在跑"，两路钟的 IP 上"寄存器全通、引擎一步不动"这种形状它分辨不出来
   （同一页 §0 的这一步因此要为每一路各留一个偏移，而不是只加 `0x04` 一个）。
- **一个纯回写的暂存寄存器（可读可写），放在 `0x08`**：写进去存住、读回原值，**不带任何副作用**。
   第 3 步的破坏性图案要写就写它，不要写带副作用的控制字（见第 3 步那条安全边界）。

没有暂存寄存器怎么办：照第 3 步，先读回原值、写完图案在同一个块里写回去，
并且只在确认过那一位段没有副作用时才这么做；做不到就回去补一个暂存寄存器再出比特流。

顺带：让中断真正接到 `xlconcat → pl_ps_irq0`（7 系列）或 `IRQ_F2P`/GIC（ZynqMP）。
不接也能跑——DMA 会退化成轮询——但你要知道**没接这件事不能用"`wait_async` 不见了"去验证**：
它是类上的 `async def`，接没接都在（`dma-channels.md` §2、`interrupts.md` §4）。
真正能读的判据是三行，各自分开一种坏法（`debug-triage.md` §3 第 7 条）：
**但第三行只在 2.7.0 起成立**——`dma.description` 这一格依赖驱动对象**自己存了** `description`，
而 2.5.1 的 `DefaultIP`/`DMA` 构造函数只在局部用 `description[...]` 建 `self.mmio`
（2.5.1 `overlay.py:634-639`，**没有 `self.description = …`**；那一版唯一存它的地方是
`DefaultHierarchy.__init__` 的 2.5.1 `overlay.py:968`），所以在 2.5.1 上这一行是
`AttributeError: 'DMA' object has no attribute 'description'`；
2.7.0/3.0.1/3.1.2/4.0.0 才有那份存储。⇒ 2.5.1 上想拿同一件事，读 `dma._interrupts` ——**它在五版都有，但住在 `DefaultIP` 上不是住在通道上**
（2.5.1 `overlay.py:641`/`:643`、2.7.0 `:670`/`:672`、3.0.1 `:698`/`:700`、3.1.2 `:702`/`:704`、
4.0.0 `:699`/`:701`，成对的两行就是"有 `interrupts` 键就存、没有就给空字典"；
而 `lib/dma.py` 全文 `grep _interrupts` 是 **0 处**，正向对照就是上面 `overlay.py` 里那一串命中），
`dma-channels.md`/`debug-triage.md` 那条判据用的就是它，**别把两页的写法当等价**。

```python
dma = getattr(ol, "axi_dma_0")    # 这一段假定 ol 已经存在（它是 §2 加载之后才有的对象）
ch = dma.sendchannel
print("sendchannel is None:", ch is None)
print("bool(_interrupt):", None if ch is None else bool(ch._interrupt))
print(sorted(dma.description.get("interrupts", {})))
```
**这三行只打印值，不打印结论**（原先这里印的是 `"中断已接"` 这种字样——被收回：
①②都真不等于"中断接好了"，本包 `SKILL.md` §1 第 9 条就是这条规矩；
板上还可能有第三种坏法：`_interrupt` 在、但事件那一路不对——分诊走 `debug-triage.md` §2
   的"中断不到"那棵树）。
**`print` 出来的第三个读数 `[]` 有两种成因，别只认第一种**：
`.hwh` 里这个 IP 确实没声明中断端口；**或者端口声明了、但没接到 `xlconcat → pl_ps_irq0`**——
`interrupt_pins` 这一族是解析器**从 PS 那根中断针往回走网络**建起来的
（4.0.0 `pl_server/hwh_parser.py:385-396` 走线、`:517-524` `assign_interrupts_gpio`
把 `interrupt_pins` 的条目分发给 `ip_dict[block]["interrupts"][pin]`），
**没接到那根针的端口连被枚举的机会都没有**。这正是本节上面让你去接的线，
所以 `[]` 出现时先回 BD 查接线，再怀疑 `.hwh`。


## 1. 导出与拷贝：整组一起走

Vivado 里 `Export Hardware`（含 bitstream）→ 得到 `.bit` + `.hwh`（或 `.xsa`）。把它们
**同一批、同名**拷到板上同一个目录，`.dtbo` 也在同一目录。默认查找规则与"缺 `.dtbo` 到底会不会报错"
由 `overlay-metadata.md` §1 那一页拥有（含 `devicetree.py` / `bitstream.py` 的出处），这里不重讲；
`print(ol.dtbo)` 那一句也**不在这一步做**——`ol` 要到第 2 步才存在。这一步能当场做的是两条 shell 读数：

```bash
ls -l --time-style=full-iso /home/xilinx/jupyter_notebooks/myip/    # .bit/.hwh/.dtbo 是否同一批
ls /sys/kernel/config/device-tree/overlays/    # 上一次加载留下的叠加条目
```

第二条**不是"里面必须是空的"**：按 configfs 的语义，跑过 PYNQ 镜像、启动时自载的 `design_1`、
或以前任何一次 overlay 都会在里面留下条目（**这一句是机理，本机没有板子、没读过任何一块板上的
这个目录**）；**"你的版本名第一次加载前不可能在"才是能用的那条判据**。
**并且"没有你的条目"有两种成因**：确实没挂过，**或者这个路径在这块板上根本没挂载**——
本机在主机上对着一个不存在/未挂载的目录跑同样的 `ls` 得到的是 **`rc=2`、stdout 0 字节**，
形状与"目录空"几乎一样；所以**判这条要连同返回码与 stderr 一起看**（`rc!=0` 时这一格写 `NOT_RUN`，
不要写成"没有残留，通过"）。
名字真的在、而你现在要换一版：**这不是可以在这一步顺手清的动作**——
`/sys/kernel/config/device-tree/overlays/<名字>` 往下删是 `SKILL.md` §5 列的危险动作之一
（同名 `.dtbo` 互相顶掉的机制见 `overlay-metadata.md` §1）。先记下这一格读到什么，
按那一页的处理路径走，别在这里 `rm`。

时间戳不同批 = 后面所有地址读数都不可信。通过标准：`.bit` 与元数据同批、同目录、文件名一致。


## 2. 加载后第一件只读的事：认身份

```python
from pynq import Overlay, PL
ol = Overlay("/home/xilinx/jupyter_notebooks/myip/design_1.bit")
print("dtbo =", ol.dtbo)    # None = 连文件都没找到；非 None 只证明路径被算出来，
    # 不证明内核装载了它——那要看 configfs 的 status
print(sorted(PL.ip_dict))    # 实例名从这里复制，不要手拼
print({k: (hex(v["phys_addr"]) if "phys_addr" in v else "NO-phys_addr")
       for k, v in PL.ip_dict.items()})
print(dict(PL.interrupt_pins))    # 空 = 这根针没被走到（两种成因见 §0 那三行）
```
**第二行为什么不能写成 `hex(PL.ip_dict[k]["phys_addr"])`**：`ip_dict` 里**PS 那一条压根没有
`phys_addr` 这个键**。解析器给 PS 条目写的只有 `gpio`/`interrupts`/`parameters`/`type`
（4.0.0 `pl_server/hwh_parser.py:243-249`；2.7.0 `:259-265`、3.0.1/3.1.2 `:236-242` 同形），
而 `PL.ip_dict` 是把这个字典原样交出去的（4.0.0 `pl.py:110-112`；**3.1.2 同一三行在 `:111-113`**，
差一行是因为那版的 docstring 多一行——裸行号在这里会串，所以两个号都要自带版本。
→ `device.py:120` 那一行 `self.ip_dict = self.parser.ip_dict`，两版同号）。
本机用一个照这个形状建的桩字典跑那句推导式，得到的就是
**`KeyError: 'phys_addr'`——整行一个读数都不打印**（同一次桩上换成 `"phys_addr" in v` 先判
就正常输出，这是本包 `overlay-metadata.md` §2 已有的写法）。
**2.5.1 还有一层差别**：那一版的解析器没有 PS 这条目，所以"KeyError"这个形状本身就随版本变——
**别把某个版本报错当"这条目应该存在"的证据**。

通过标准：目标 IP 在表里、`phys_addr` 与 Vivado Address Editor 里那一行一致；
`.dtbo` 非 `None` 时，`cat /sys/kernel/config/device-tree/overlays/<dtbo 基名>/status` 读到 `applied`
（这一条的出处与同名顶掉的后果在 `overlay-metadata.md` §1）。


## 3. 寄存器通路：破坏性图案 + 读回

```python
from pynq import MMIO, PL    # PL 是取 ip_dict 的那个入口，别只导入 MMIO
ent = PL.ip_dict["my_ip_0"]
base = ent["phys_addr"]
mm = MMIO(base, ent["addr_range"])    # 长度用这条条目里的实际范围；
    # 不要顺手写 0x1000：`debug-triage.md` §2 那条就是针对这个写法——映射超出实际范围之后，
    # 读到 0 与"这个偏移上没有寄存器"分不开：映射超出实际范围之后，越界那一段读到什么是
    # 由总线与 PL 的接线决定的（机理，需板端），所以"读出 0"不能当"寄存器值为 0"用。
    # 只有 `overlay-metadata.md` §5 那个"扫整段"的骨架才需要给一个比实际范围大的长度。
SCRATCH = 0x08    # 第 0 步埋的那个"无副作用回写"寄存器

# probe32 的唯一定义在 mmio-registers.md §4（写三式 + 读回 + finally 复原）；
# 那一页是规范出处，这里不重抄一遍——重抄就会漂移。用之前把那个函数贴进同一个 cell/脚本。
# 用之前先读它页面上那两条限制：① 图案里 0x00000000 那一行"读回 0 = OK"**不构成证据**
# （读到全 0 的东西——比如没接从设备的地址——它必然绿），判据只能是 0xA5A5A5A5 那一行；
# ② `finally` 里那次复原写会**顶掉你刚撞到的错误**：本机在主机上用一个照 `probe32` 形状写的桩
# 量过这条 Python 语义——里面先 `raise MemoryError("Unaligned write…")`、`finally` 再
# `raise RuntimeError("SLVERR on the restore write")`，交回来的是 **顶层 `RuntimeError`（复原那笔）、
# 原错误只在 `e.__context__` 里**（`__suppress_context__` 为 `False`）。
# 也就是说你读到的是"复原写失败"，而真正的第一现场被挪到下一层——
# 与本页 §7 表里"卡在第 3 步"那一行写的"别反复重试同一笔写"是同一路危险；
# 第一次上板建议先 `restore=False`（本包的 `probe32` 有这个形参），
# 要不要复原由你按读回来的值另起一次显式写。
probe32(mm, SCRATCH, "scratch", restore=False)
```

`off` 一律是**字节**偏移且必须 4 对齐（`ip.mmio.array[i]` 才是字索引，两者别混，
`mmio-registers.md` §2-§3）。

**图案只往你确认过没有副作用的偏移写。** 未核实的偏移（比如照网上抄 `0x10`）可能正是某个使能/复位/
模式字。下面这两句是**机理与要求，不是本机读数**（写这条时没有板子）：`0xFFFFFFFF` 写进去能让 PL 侧
进入一个你回不去的状态，甚至挂住那笔 AXI 事务；这不是"测试失败"，是制造新故障。
没有暂存寄存器就回第 0 步补，别拿控制字当试纸。

通过标准：可写位读回与写入一致；**恒 0 或恒 F 都算失败**（不存在的从设备也常返回 0）。
RO 状态位允许不等，但要在报告里点名哪一位允许。
若这一笔就把 Python 卡死：立刻停手，这是"PL 没时钟/没出复位/该地址无从设备"的通路问题
（`debug-triage.md` §2 树 A），不是值设错了。**卡住之后不要重试同一笔写，也不要指望"重启 kernel"
能恢复**——挂住的 GP 事务不在 Python 的状态里（`versions-and-apis.md` §4 最后一条）。


## 4. 身份确认（第 0 步埋的版本寄存器）

```python
print(hex(mm.read(0x00)))    # 期望值来自设计文档，不来自记忆
```

读到期望值 = 板上就是这一版、AXI-Lite 通；**但这个等号有一个设计侧前提，没验过就没有成立**：
它要求那位版本寄存器的值**真的随构建变化**。如果两版镜像写的是同一个常数（很常见：改 RTL 不改
`VERSION` 参数），这条判据在两者上**同样绿**，读到的"期望值"只证明"板上有人写了这个数"，
不证明"那是我刚构建的那一份"。⇒ 用之前先做一次红臂：把参数改一个 bit 重出一版，
确认读回值跟着变；这一步没做，就把"身份"这一格写 `NOT_RUN`，改用产物指纹 + 烧写记录那条弱证据。
**它也不证明 PL 的数据通路有时钟**（那要看 §0 那个
按时钟域各埋一个的自由运行计数器）。读不到就不要继续：**现在停下来比
后面给一份错结论便宜得多**。

## 5. 数据通路：先单字节图案，再真实数据

下面这段是 `dma-channels.md` §3 那节**规范骨架的镜像**，**但它不是逐字相同的那段**：
两边差别由那一页 §3 末尾按七条列全（导入与 `Overlay(...)` 那两行不在这里、
**通道判空的 `raise SystemExit` 守卫换成了打印**、`n` 取的数不同、这里多打一行 `max=`、
"先挂收侧"那句的免责只在那一页、`ref` 在 `with` 块外、比对式这里用 `mask` 且**不打第一处错位**）。
**其中两处是要命的**：① 这里没有那个守卫，所以"这一侧硬件没使能"在这一页要靠
`send=/recv=` 那行读出来；② 这里不打 `first=/got=/exp=`，出第一次错位时定位信息比规范版少。
两边的等待方式必须一致：改一处就改两处，否则本页的"通过标准"会指向一个
另一页并不推荐的收尾。


```python
from pynq import allocate
import numpy as np
n = 1024
dma = getattr(ol, "axi_dma_0")
print("max =", dma.buffer_max_size,
    "send =", dma.sendchannel is not None, "recv =", dma.recvchannel is not None)
with allocate((n,), dtype=np.uint8) as src, allocate((n,), dtype=np.uint8) as dst:
    src[:] = np.arange(n, dtype=np.uint8)
    src.sync_to_device()
    dma.recvchannel.transfer(dst)    # 先挂收侧
    dma.sendchannel.transfer(src)    # 再发起侧
    # wait() 没有 timeout 形参，第一次上板不要裸等。
    # 规范实现是 dma-channels.md §2 的 wait_with_timeout(ch, seconds)（返回 (done, err)），
    # 那里是唯一定义；用之前把那个函数贴进同一个脚本，本页不重抄——重抄就会漂移。
    for who, ch in (("recv", dma.recvchannel), ("send", dma.sendchannel)):
        done, err = wait_with_timeout(ch, 5)
        print(f"{who}: done={done} err={err!r} idle={ch.idle} error={ch.error} "
          f"transferred={getattr(ch, 'transferred', None)}")
    dst.sync_from_device()
    got = np.array(dst)    # 出了 with 就释放了，比对要在块内取快照
ref = np.arange(n, dtype=np.uint8)
mask = np.ones(n, dtype=bool)    # 透传阶段：PL 不改任何字节，所以要比的下标就是全体
checks = int(mask.sum())    # 见下面那条：透传阶段它恒等于 n，此时它不是判据
print("checks=%d mismatches=%d" % (checks, int(((got != ref) & mask).sum())))
```
**`checks` 这一格什么时候才算数，先前这里写反了**（原话是"这一格必须能算出 0"）。
按上面这句 `mask = np.ones(n)`，`checks` **恒等于 `n`**，`0` 这一支在这个骨架里永远到不了——
一条出生以来没红过的判据不构成证据（`SKILL.md` §1 那条）。它真正的用法是第二阶段：
**PL 只改写下标的一个子集时**（ROI、行有效窗、只处理奇数列那一类），
`mask` 必须由**设计里那个窗的口径**给出（例如 `mask[y0:y1, x0:x1] = True`），
这时 `checks=0` 才有意义，说的是"你的窗算空了"。**透传阶段这一格不是判据，是结构常数**：
骨架里 mask 就是上一行硬编的 `np.ones(n)`，所以 `checks` **恒等于 `n`**——
**先前写的"`checks != n` 才说明 mask 写错了"因此是一条永不红的判据，收回**（它在 mask=ones 时到不了，
在 mask 按窗给时数的又是"窗大小 != n"这种正常情况，两种都不构成信号）。
这一格能红的只有**它自己与"你打算比的元素数"是否一致**：把 `n`、`mask.sum()`、mask 的来历三个数
一起打印，读数才可解释；要让判据真的能红，用**下面的两臂对照**代替它——
同一份"后半段全错"的数组，`mask=ones` 那一臂报 `checks=1024 mismatches=510`，
只取前半的 mask 报 `checks=512 mismatches=0`——**后者看着是绿的**），
所以"只比 PL 改写的那部分"这件事要么按设计的窗严格给，要么一开始就全比。

`dma.buffer_max_size` 那个打印是**没有版本标签的**：2.5.1 那版**不减 1**
（2.5.1 `lib/dma.py:194-197`，两支都是 `1 << …` 就结束），3.0.1 起才有 `-= 1`
（3.0.1 `:624`、3.1.2 与 4.0.0 `:637`），而且 2.5.1 在缺键时**会发一条
`UserWarning`（`Failed to find parameter c_sg_length_width; users should really use
*.hwh files for overlays.`，`:198-200`）**，后来的版本改成静默退回常数 26。
同理上面那行打印里的 `ch.idle`/`ch.error`/`ch.transferred`：**2.5.1 的通道只有 `running`/`idle`**，
所以**只有 `ch.error` 那一句会 `AttributeError`**（分支表在 `dma-channels.md` §2 末）；
`transferred` 那一格写的是 `getattr(ch, 'transferred', None)`，在 2.5.1 上**不抛**，
它安静地打出 `transferred=None`——**这比抛异常更危险**：`None` 会被读成"搬了 0 字节"。
⇒ 这一行的正确读法是三种状态分开写：有值 / `None`（这一版没有这个口）/ 抛异常（属性名写错）。

别写成 `finally: src.close()`——`close()` 在 3.1 与 4.0.0 里只发一条 `DeprecationWarning`，
什么都不释放（`buffers-and-cache.md` §2）。通道判空写 `is not None`：构造函数在没使能那一侧时
就是把属性赋成 `None`（3.1.2 与 4.0.0 都是 `lib/dma.py:639-640`：`self.sendchannel = None`、
 `self.recvchannel = None`；**2.7.0 这一对整体前移到 `:617`，2.5.1 里根本没有这两行**——它的通道是直接在
 构造里建起来的，所以这句不能往 2.5.1 上抄），`is not None` 直接说出这件事；
`bool(x)` 在这一刻也能用（`bool(None)` 恒为 `False`，这是语言保证，不是巧合），
但它问的是"真值"而不是"有没有这一侧通道"，读代码的人要靠推断才能确认你的意图。


通过标准：`mismatches=0` 且**重复 ≥3 次**同样结果；`transferred`/长度与请求一致。
先用"透传"（PL 只搬运不改数据）验通路，再验算法 —— 两件事一起坏的时候无法归因。

## 6. 才加算法与性能

- 参考实现要与 PL 语义**独立**（不要照抄 RTL 的定点算式，否则同错永远一致），比对时打印
   `checks=/mismatches=`。`NOT_RUN` 的意思就一个：**这次没有任何样本进入比对**，所以它既不是通过
   也不是失败——`checks=0` 一律判 `NOT_RUN`，然后回去查形状/切片/dtype/mask。
   判绿行要带计数，不带计数的 PASS 不算说过话（`debug-triage.md` §3 第 11 条）。

- 计时按 `debug-triage.md` §4：`reps>=7`、报最差或中位并写明、把 `allocate`/`sync_*`
   是否计入说清楚、分块大小由 `buffer_max_size` 与数据位宽对齐推出来（不是抄上一次的常数）。

## 7. 每步的失败去向

| 卡在第步 | 先做的**动作**（不是名词） | 别做 |
|---|---|---|
| 1 | `ls /sys/kernel/config/device-tree/overlays/` 看上一版的条目有没有残留；再 `ls -l --time-style=full-iso` 比三个文件的时间戳 | 别在主机路径下加载；别让两个 overlay 的 `.dtbo` 同名（`overlay-metadata.md` §1） |
| 2 | `print(sorted(PL.ip_dict))` 把名字**复制**过去；再 `print(PL.ip_dict[name]["type"])` 与 `print(type(getattr(ol, name)).__name__)` 成对打印——**但"`DefaultIP` 就是 VLNV 对不上"这句收回**：两条路都落到 `DefaultIP`（4.0.0 `overlay.py:80` 与 `:82` 是两个不同的 `details["driver"] = DefaultIP`），**能分开的只有 warning**：版本对不上先走 `overlay.py:64-79` 发 `IP {0} is of type {1} and driver found for [{2}]. Use ignore_version=True to use this driver.`；而名字整个不在表里走 `:81-82`，**一声不响**——自研 IP 没有注册驱动时读到的就是这一支，所以它恒为此值、不是判据。要判"驱动为什么没绑上"，判据是**那条 warning 在不在**（配合 `overlay-metadata.md` §2 的驱动表），不是类名。**别拿 `MODTYPE` 当版本判据**：在两棵新版树里都还读到它（3.1.2 `pl_server/hwh_parser.py:163`、4.0.0 `:170` 的 `mod.get("MODTYPE")`），而按 VLNV 绑驱动从 2.5.1 就是这样（`for vlnv in cls.bindto`：2.5.1 `overlay.py:527-528`、3.1.2 `:561`/`:569`、4.0.0 `:558`/`:566`）——两层的逐行归属由 `overlay-metadata.md` §2 第 2 条拥有，这里不重抄 | 别按记忆猜实例名 |
| 3 | 先读一个**必然有值**的偏移（第 0 步的 `0x00` 版本寄存器）确认通路，再谈图案；单位（字节 vs 字）与 4 对齐照 `mmio-registers.md` §2 的式子算一遍并打印中间值 | 别反复重试同一笔写；别把 `0xFFFFFFFF` 写进没核实过的偏移 |
| 4 | 把读到的值和期望值**两个都打印**（只说"对不上"不算读数）；再核 `.bit` 的 md5 与这次构建的那份是否同一个 | 别用文件哈希代替身份——哈希对得上只证明文件没换，不证明 PL 里配的是它 |
| 5 | 先 `from pynq import Clocks`（本页前面没导入过它），再 `print([Clocks.fclk0_mhz, Clocks.fclk1_mhz, Clocks.fclk2_mhz, Clocks.fclk3_mhz])`——**属性写法是主读数**；`Clocks.get_pl_clk` 在 2.7.0/3.0.1/3.1.2 上恒为 `None`（丢 `return` 那段见 `debug-triage.md` §2 树 A），4.0.0 补回来了，但**别把"有值"读成"是 4.0.0"**：2.5.1 没有丢 `return` 这一层，同样给值。再读自由运行计数器两次取差；然后按 `dma-channels.md` §2 把四个状态口逐个打印 | 别只等一侧的 `wait()`；别用 `sleep()` 代替完成判定 |
| 6 | 打印 `checks=` 并确认它非 0；再把参考实现的一条算式与 RTL 的对照写进报告（两条独立来源） | 别拿"看起来对"的截图当证据 |

