# 中断：pinname、协程、超时、失效、谁在管控制器

## 1. `Interrupt(pinname)` 的校验是"字符串必须在表里"

```python
from pynq import Interrupt, PL
print(dict(PL.interrupt_pins))    # 唯一的合法名字来源
```

源码 `interrupt.py:63-64`（3.0.1/3.1.2/4.0.0；**2.5.1 与 2.7.0 的同一段在 `:92-93`**，那两版的
`:63-64` 是另一个函数在扫 `/proc/interrupts`）：`pinname` 不在 `PL.interrupt_pins` 里就直接
`ValueError("No Pin of name {} found")`。合法名字的形状是 block diagram 里的
**`${cell}/${pin}`**（docstring 原话），也就是"产生中断的那个 IP 的输出端口"，不是
`xlconcat` 的名字（它是拼线 glue，不是中断源）。这里有个真会绊人的地方：同一个"层次前缀"
有两种写法，一种能用一种不能用——

- **能用**：`design_1_i/axi_dma_0/s2mm_introut`、`design_1_i/axis_data_fifo_0/interrupt`
   （`design_1_i` 是 BD 例化进顶层后那个 cell 的名字，后面接 IP 名与端口名）
- **不能用**：`design_1_ips_0/...` 这类 BD **内部自动生成**的实例路径
   （`*_ips_0` / `*_bd_*` 是 Vivado 自己的容器名，不是 `cell/pin` 口径）
- **也不能用**：`pl_ps_irq0/IN1` 这种。`pl_ps_irq0` 是 `xlconcat` 合并之后接到 PS 的那条**线**的名字，
   下面那两条讲接线时也会写"`xlconcat → pl_ps_irq0`"，字面看着像个合法前缀，但它不是
   "产生中断的那个 IP 的端口"，所以**不在这张表里**，直接 `Interrupt("pl_ps_irq0/IN1")` 得到
   `No Pin of name`。PS 侧入口那一端的名字（`IRQ_F2P` 这一类）同样是**接线**不是键——
   别照抄接线图上的名字，要确认就在板上打 `print(list(PL.interrupt_pins.keys()))` 看这张表收录了什么。

两者的差别不在字符串形状上（都以 `design_1` 开头），所以**唯一可靠的办法是从
`PL.interrupt_pins` 里整条复制**——那才是实现用来查表的键。

1. 名字**从表里复制**，不要手拼（大小写、斜杠、下标都是判据）。
2. 表是空的 → 不是名字问题：中断没接进 PS（`xlconcat → pl_ps_irq0` / `axi_intc → IRQ_F2P`）、
   或者这版 PYNQ/这个平台要求设备树里有对应节点（`.dtbo`）。先解决通路，再谈 API。

### 1.1 不要手写 `axi_intc` 的 enable/ack——那是驱动在管的东西

**先划适用范围**：下面这张表说的是 `_InterruptController` 那一条路，即中断**经过 `axi_intc`** 的情况。
它是不是你的设计所走的那条路，当场判：`print(PL.interrupt_controllers)`（源码里控制器就是用
`PL.interrupt_pins` 的父级去取的）——非空 ⇒ 走这条路；为空而针却在 `PL.interrupt_pins` 里 ⇒
你的中断是直接进 PS（`xlconcat → pl_ps_irq0` / `IRQ_F2P`→GIC），**那种情况下没有这张表里的
MMIO 块可查**，别去读 `0x04`/`0x1C`：那条路走的是 UIO，机制在 `interrupt.py:140-150`。

**直连 PS 那一支到底在找什么**。`get_parent()` 看到针的 `parent == ""` 时走的是：

1. 取针的 `raw_irq`（针的字典里**实际被写进去的键**是 `controller`/`index`/`fullpath`，
   3.x/4.0 还多一个 `raw_irq`——逐版的赋值行：2.5.1 `pl_server/hwh_parser.py:387-389`（**没有 `raw_irq`**，
   那一版 `_add_interrupt_pins(self, net, parent, offset)` 的形参里就没有 `raw_map`）、
   2.7.0 `:429-431` 加 `:433` 的 `raw_irq`、3.0.1 与 3.1.2 `:433-436`、4.0.0 `:440-443`，
   `Interrupt(pinname)` 用的就是这个 `fullpath`）。
   **`parent` 这个键确实存在，但它不在针上——在控制器那本字典里**：
   4.0.0 `:432-435` 写的是 `interrupt_controllers[name] = {"parent": parent, "index": offset}`
   （`:437` 再补 `raw_irq`）。**先前这里说"`parent` 从来不是解析器写的键"是我把两本字典混成一本**，
   收回；正确的说法是：**针的条目里没有 `parent`，控制器的条目里才有**。
   于是 `entry['parent']`（`entry` 是针）取不到键时是 **`KeyError`，不是 `None`**；
   `interrupt.py:138` 那句 `parent = entry['parent'] if 'parent' in entry else entry['controller']`
   是一个**对针永远走不到前一支的兜底**，它存在的最早版本是 **2.7.0 `:167`**
   （3.0.1/4.0.0 都在 `:138`），2.5.1 `:95` 是直接 `entry['controller']`。
   所以从 2.x 搬代码时**不要**"顺手改成读 `parent`"——那才是把对的代码改坏。


2. `get_uio_irq(raw_irq)` 扫 `/proc/interrupts`，**判的是倒数第三列等于 `str(raw_irq)`、
   取最后一列当设备名**，而且要求这一行至少 7 列（3.0.1/3.1.2/4.0.0 `:32-42`；2.5.1/2.7.0 同一段在
   `:61-70`，函数从 `:44` 起）——注意它不 `break`，多行命中时
   留下的是**最后一条**；
3. 拿这个设备名去 `get_uio_device()`：逐个读 `/sys/class/uio/*/name`，**整串相等**才返回
   `/dev/uioN`，找不到返回 `None`（`uio.py:27-32`，3.0.1/3.1.2/4.0.0；2.5.1/2.7.0 同一段在 `:56-61`，
   那两版的 `:27-32` 还是文件头的许可证注释）；
4. `None` 就直接 `ValueError('Could not find UIO device for interrupt pin for IRQ number {}')`
   （3.x/4.0.0 `interrupt.py:145-147`；2.5.1 `:190`、2.7.0 `:175`）。

所以这一支的判据是一串**能对上的名字**，而不是"有没有 `/dev/uio*`"：
`PL.interrupt_pins[pin]` 里的 `raw_irq` → `/proc/interrupts` 那一行的最后一列 →
必须与某个 `/sys/class/uio/*/name` 的内容**完全相同**。这三段任何一段对不上，`Interrupt(pin)`
就是在第 4 步炸，而不是在"名字写错"那一步（名字写错的话 `Interrupt.__init__` 早两行就抛
`ValueError("No Pin of name {} found")`，`:63-64`——两句话不一样，别混）。
UIO 节点由 `.dtbo` 声明，所以这一支查不出来时回到 `overlay-metadata.md` §1 的 configfs `status` 判据。


旧写法会教你"用 axi_intc 时初始化一下中断控制器的 enable/ack 寄存器，否则 `wait()` 永远等不到"。
**这条在 3.1/4.0.0 上是错的，而且是有害的**：`_InterruptController` 已经全程接管这些寄存器，
你手动写一遍不会补上缺失的通路，只会把驱动的状态机搅乱。源码里看得见的动作（行号 `interrupt.py`）：

| 时机 | 驱动写的寄存器 | 作用 |
|---|---|---|
| 控制器单例构造时 | `write(0x08, 0)`（`:174`） | 先把 32 条线**全部 disable** |
| 有人开始等这条线（`add_event`） | `write(0x10, 1 << number)`（`:227`），随后 `write(0x1C, 0x00000003)`（`:233`） | enable 这一条 + 写全局使能寄存器 `0x1C` |
| 中断到来（`set()`） | `read(0x04)` 取 IVR（`:188`，注释 "Pull pending interrupts"）、对活跃线 `write(0x14, 1<<irq)`（`:195`，注释 "Disable the interrupt"）、最后 `write(0x0C, irqs)`（`:205`，注释 "Acknowledge the interrupts"） | 唤醒事件、**屏蔽该线直到下一次 `add_event` 重新 enable** |

这三行里的动词都直接抄自上游注释，不是本包给寄存器的命名。
**表里的行号按版本各数过一次**：`write(0x08, 0)`、`read(0x04)`、`write(0x14, …)`、`write(0x0C, irqs)`、
`write(0x10, …)`、`write(0x1C, 0x00000003)` 这六处在 3.0.1/3.1.2/4.0.0 **完全同位**
（`:174`/`:188`/`:195`/`:205`/`:227`/`:233`）；2.5.1 的对应行是 `:183`/`:207`/`:214`/`:224`/`:246`/`:252`，
**别按"整体后移多少行"去推**——本机这六个数与 4.0.0 的差是 `+9, +19, +19, +19, +19, +19`，
第一对与其余不是一个偏移量（2.7.0 又是另一组：`:203`/`:217`/`:224`/`:234`/`:256`/`:262`）。
**寄存器地址与写法一版都没变，变的只有行号**——
所以这张表的能力结论可以跨版搬，行号不能。

三条从这张表的**形状**里掉出来的结论，比表本身更常用于排查：

- **驱动只映射 32 字节**：控制器句柄是 `MMIO(PL.ip_dict[name]['phys_addr'], 32)`（`:168`）。
   想看这个窗口之外的寄存器（各家 axi_intc 的 status/version 常常在后面），得自己
   `MMIO(base, 更大)`，不要以为"驱动给的 mmio 就是这个 IP 的全貌"。
- **驱动只预备 32 条线**：`self.wait_handles = [[] for _ in range(32)]`（`:169`）。
   针的 `index` 来自元数据（`:139` `number = entry['index']`），只要有一根 `index ≥ 32`，
   出问题的是驱动的列表下标（`IndexError`）而不是硬件。**xlconcat 的宽度、axi_intc 的
   `C_NUM_INTERRUPTS`、`PL.interrupt_pins` 里的 `index` 是三个不同来源**，三者不一致时
   症状是"部分针永远不来"。先 `print({k: v.get('index') for k, v in PL.interrupt_pins.items()})`
   把 index 摊开看，比逐根试快。
- **enable 之后没有任何回读**：驱动写完 `0x10`/`0x1C` 就结束，不验证。所以"我注册过了"
   在这张表里不是状态，只能自己取证：等之前读一次 `mmio.read(0x04)`（IVR，驱动在 `set()` 里
   读的就是它，`:188`），触发之后再读一次；**IVR 动了而你的 `wait()` 不回**，问题在交付/清位这
   一层；**IVR 不动**，问题在源 IP 侧的使能或那根针根本没接上。

（控制器本身要能在 `PL.ip_dict` 里查到——`get_controller` 就是按名字去取它的
`phys_addr`；元数据里没有这个 IP 时，报的是字典层的 KeyError，别把它读成"中断没接"。）


控制器实例本身也是从 `PL.ip_dict[name]['phys_addr']` 建 `MMIO(..., 32)`（`:168`）——
所以"它认到的是哪个实例"可以用同一张 `ip_dict` 核对，而不是靠你猜地址。

**用户真正要做的是让中断源自己发中断**：绝大多数 AXI IP 的中断输出要由 IP 自己的控制位使能。
AXI DMA 就是现成的例子：`start()` 只在 `self._interrupt` 为真时才把 DMACR 的 `0x1000`
（interrupt enable）与 `RS` 一起写上——写入那一行在 **`lib/dma.py:90`（SDMA）与 `:291`/`:296`（SG，
cyclic 那支多 `0x10`）**，不是下面这两个连线处；`:671`、`:728` 是**决定 `_interrupt` 有没有被建起来**的地方
（`if "mm2s_introut" in self.description["interrupts"]:` / `s2mm_introut`），
`0.1001` 与 `0.0001` 的分支就是 `:89-92`、`:289-298` 那两组。
（**先前这里把 `:671`/`:728` 写成"把 DMACR 一并写上"的那一行**——归属错了：那两处一个 `set` 都没做，
只挑要不要建带中断的通道。）写入值的完整条件表
——含"只有 cyclic 模式才会多置的那一位"——在 `dma-channels.md` §1 第 4 条，本文不重讲。
**这条版本线也值得记住**：`0x1001` 这种"带中断使能"的写法在 2.5.1 只有 SDMA 一处（`:86`）、
2.7.0 两处（`:124`/`:328`）且**都还没有 cyclic 的 `0x1011`**（3.0.1 起才有 `:292`）。
所以"中断不来的五步分诊"是：

1. `PL.interrupt_pins` 里有没有这个针？
   - **没有，而你既没改接线、也只改过 BD 里 cell 的名字** → 不是"没接进 PS"，是**键的前缀
     `${cell}` 变了**（上面讲 `design_1_i` 那一段就是这件事）：回 Vivado 侧按
     `fpga-board-development/references/vivado-project-bd.md` §2 第 2 条走"改名之后必做的两件事"
     （整组重导 + 逐条重取约束命中），重导之后回到这一步重新 `print(dict(PL.interrupt_pins))` 再复制。
   - **没有，而且线也确实没连到 PS 的中断入口** → 才是设计侧没接进 PS，回硬件层。
   - 两种都"不报错、针不在"，区别只在你**动过什么**；所以这一问先问改动历史，再问硬件。
2. 有针，但 `Interrupt(pin)` 构造完仍等不到 → 看**源 IP** 的中断使能有没有开
   （DMA 走 `start()`；自定义 IP 要在你的控制寄存器里找那个 enable 位，读回确认）。
3. 源使能了、`ip_dict[name]['interrupts']` 是空的 → 元数据里这个 IP 就没声明中断，
   DMA 就不等中断、改成在 `wait()` 里反复读状态位（这一条的细节在 `dma-channels.md` §2）。
4. 全都对但仍不来 → 读控制器的 ISR（`0x04`）看有没有挂起：**控制器在构造时就把 32 条线全关了**
   （`_InterruptController.__init__` 里的 `write(0x08, 0)`，`:174`；不是 `Interrupt` 干的，是它父对象），
   只有 `add_event` 之后那条线才 enable，所以**在第一次 `await wait()` 之前发生的中断会被丢掉**。
   这是"第一次传输完成的中断读不到、之后都能读到"的机理。
   对策是把顺序反过来，让等待先就位再触发源——不是"多等一会儿"：

    ```python
    import asyncio    # wait_or_timeout 的定义在下面的 §2（它闭包用的就是那里那个 intr）

    async def arm_then_run(run, seconds=2.0):
        waiter = asyncio.ensure_future(wait_or_timeout(seconds))    # 先注册 event
        await asyncio.sleep(0)    # 让上面那行真的跑到 add_event
        run()    # 再去启动/发起那笔会产中断的事
        return await waiter
   ```

   `sleep(0)` 不是保险丝而是必要的让步：`wait()` 里真正注册事件的是 `parent.add_event(...)`
   （`interrupt.py:81-84`），协程不被调度一次它就还没发生。**这条只保证"这一次不丢"，
   不保证"重复等待安全"**——同一对象的并发 `wait()` 仍然不要写（§2）。
5. 上面四条都过了还不动 → 才是中断控制器/设备树/uio 节点那一层（`ls /sys/class/uio` 与 `cat /sys/class/uio/*/name` 就是那份列表）。

## 2. `wait()` 是协程，而且没有 `timeout` 形参

```text
async def wait(self)    # interrupt.py:72（3.0.1/3.1.2/4.0.0；2.7.0 在 :101）
```

- `intr.wait(2)` / `intr.wait(timeout=2)` 都会 `TypeError` —— 不是用法问题，是这个参数不存在。
- 正确等待：`await intr.wait()`（在 notebook 的 cell 顶层 `await` 可用；在普通脚本里
   `import asyncio; asyncio.run(producer())`）。
- **不要并发对同一个 `Interrupt` 调 `wait()`。** 机理是这样的：实现用 `self.waiting` 挡住
   "重复向控制器注册事件"（`:81-84`，3.x/4.0.0；2.7.0 同一段在 `:110-113`），但所有调用者 `await` 的是**同一个** `asyncio.Event`，
   而最先醒的那个会把 `self.waiting` 清成 False（`:86`；2.7.0 `:115`）。于是"注册保护"与"谁在等"并不是同一件事——
   并发等不报错，但之后的行为没有保证。**这是建议，不是被机制强制的约束**，所以别靠"它没报错"
   认定自己用对了。
- notebook 里裸等一个不会来的中断会把 kernel 挂住到进程被杀。

超时要自己做（把协程包起来）：

```python
import asyncio
from pynq import Interrupt

intr = Interrupt("design_1_i/axis_data_fifo_0/interrupt")    # 名字照抄 PL.interrupt_pins

async def wait_or_timeout(seconds):
    try:
        await asyncio.wait_for(intr.wait(), timeout=seconds)
        return True
    except asyncio.TimeoutError:
        return False

# 怎么把上面那个协程跑起来，分两种场合，写错会得到 "event loop is already running"：
#    A) 普通脚本 / xsdb 之外的 python3 进程：
print("got interrupt:", asyncio.run(wait_or_timeout(2)))
#    B) Jupyter 的 cell 顶层（kernel 里已经有一个跑着的事件循环）：**不要再调 asyncio.run**，
#       直接 await —— 这一行只在 cell 顶层用，别与上一行同时留在一个脚本里：
#          print("got interrupt:", await wait_or_timeout(2))
```

**远程开发模式下这一族还有三件额外的事**（别名与别名机制归 `versions-and-apis.md` §1 讲；
这里只讲对中断的影响）：① `PL.interrupt_pins` 与 `ip_dict` 是从**板子**取回来的，所以你打印的
表是板端那一版的形状，不是你主机装的那版；② `wait_for` 超时只撤掉**本地**那个协程，
板端的事件仍挂在控制器的 `wait_handles` 上、那条线仍是 enable 的，所以下一次 `wait()`
会立刻返回——这不奇怪，是必然；③ 超时时长是**跨消息通道**量的，比板端本地等要留出余量，
别拿本地测出来的"2 ms 够了"当阈值。

`asyncio.wait_for` 只是不再等它，**不会取消 PL 侧那一次中断**：下一次 `wait()` 仍可能立刻返回。
所以要判断"这次到底来没来"，得有独立的计数依据（PL 里的中断计数寄存器，或 DMA 的 `transferred`
字节数），不能只靠这次 await 的返回值。

## 3. 换 overlay 之后中断对象必须重取

`Interrupt` 的 docstring 明写：Overlay 被改动或重下载后**这个对象失效，等待的结果是未定义**；
实现上它持的是中断控制器的**弱引用**（`self.parent = weakref.ref(parent)`，`:68`），父对象没了
就 `RuntimeError("Interrupt invalidated by Overlay change")`（`:79-80`）。因此：

- `Interrupt(...)` 与 `Overlay(...)` 同生命周期：每次重下都重新构造，绝不跨轮复用。
- 捕获 `RuntimeError` 当作"需要重建"的信号，而不是当偶发异常重试同一个对象。
- 远程模式下 `wait()` 走消息通道，**不要假设可以 `select`/拿 fd**（远程模式到底把 `Interrupt`
   绑成了哪个类、为什么同名不同实现，由 `versions-and-apis.md` §1 拥有，本页不重述）。

## 4. 中断驱动的收尾长什么样

**先分清两个名字很像、管的不是同一件事的辅助函数**：
本页 §2 定义的 `wait_or_timeout(seconds)` 等的是**中断事件**（`asyncio.Event`），
而它闭包的是 §2 那个**模块级全局** `intr`——那里建的是 `axis_data_fifo_0` 的引脚，
**不是**下面 `run_once` 要等的 DMA 引脚。所以复用它的唯一正确做法是**先把全局 `intr` 重新绑到
本次那根线**（或改成把 `Interrupt` 对象当参数传进去再 `await obj.wait()`）；直接拿来包住 DMA 那一拍，
你等到的是 FIFO 那根线，或上一个 overlay 留下的那根线（§3 讲的就是"换 overlay 之后对象必须重取"）。
`dma-channels.md` §2 的 `wait_with_timeout(ch, seconds)` 包的是**通道 `wait()`**。
换掉任何一个都不会让另一个变得更正确：中断到了不等于引擎报了完成，
引擎 `idle` 也不等于你的事件被置位——所以下面这段是**两条独立凭据都要读**的写法，
不是"用中断代替 `wait()`"。下面那段**不用** `wait_or_timeout`，用的是收 `pin` 参数的 `wait_obj`，
理由就是上面那条闭包。


```python
async def wait_obj(irq_obj, seconds):
    # 这一版把**要等的中断对象当参数收**，不借用 §2 那个模块级 `intr`。
    # （§2 的 `wait_or_timeout(seconds)` 闭包的是它自己那根 `axis_data_fifo_0` 的线；
    #  直接拿它包住下面这段 DMA 的拍子，`got_irq` 量到的就是另一根线——那是本页最常见的一次错接。）
    try:
        await asyncio.wait_for(irq_obj.wait(), timeout=seconds)
        return True
    except asyncio.TimeoutError:
        return False


async def run_once(dma, src, dst, irq_obj, seconds=2.0):
    # 两条独立凭据：中断到了 + 引擎自己报完成。任选其一都不算充分。
    irq = asyncio.ensure_future(wait_obj(irq_obj, seconds))        # §1 分诊第 4 步的规矩：等待先就位
    await asyncio.sleep(0)                                     # 让它真的走到 add_event
    dma.recvchannel.transfer(dst)                              # 这一步才是事件源
    dma.sendchannel.transfer(src)
    # `transferred` 只在 `wait()`/`wait_async()` **内部**被写（4.0.0 `lib/dma.py:185/198`，
    # SG 路径 `:514`），而 `transfer()` 把它清 0（`:155`/`:445`）。
    # 不叫这两个之一就直接读它，拿到的**永远是 0**——那是"没读到的口"，不是"没搬完"。
    got_irq = await irq
    # 引擎这一路**必须排在 transfer 之后**：`wait()`/`wait_async()` 开头就是
    # `if not self.running: raise RuntimeError("DMA channel not started")`
    # （SDMA：3.1.2/4.0.0 `lib/dma.py:168-169` 与 `:191-192`）——提前 arm 不是保险，是直接抛。
    # SG 那一路开头多一条：`if self._cyclic: raise RuntimeError('Cannot wait in cyclic BD mode')`
    # （`:473-474` 与 `:528-529`），cyclic 下根本等不了。
    # `irq_obj` 要**单独 `Interrupt(...)` 构造**：别把 `dma.recvchannel._interrupt` 传进来——
    # 通道自己的 `wait_async()` 也在等同一个对象，而同一对象的并发 `wait()` 是本页 §2 禁止的那件事。
    # 起了几条通道就**几条都要等**：这里两笔都发起了，只等 recvchannel 那一条时，
    # sendchannel 还在跑；下一轮再 `transfer()` 会撞上"通道没停"（SDMA `lib/dma.py:138`
    # `DMA channel not idle`、SG `:356` `not halted`，3.1.2 与 4.0.0 同一行号）——
    # 而这条 raise 报在**下一轮**，读起来像"第二次不知为何就坏了"。
    # 两侧各等一次这件事不归本页发明：`first-bringup.md` §7 表第 5 行与 `dma-channels.md` §2 的骨架都是两侧等。
    await asyncio.wait_for(dma.recvchannel.wait_async(), timeout=seconds)
    await asyncio.wait_for(dma.sendchannel.wait_async(), timeout=seconds)
    return got_irq, dma.recvchannel.transferred, dma.sendchannel.transferred
```

**两个等待的"就位时机"不一样，这不是自相矛盾**：`Interrupt` 那一路要**在事件产生之前**注册
（否则丢一次，就是 §1 分诊第 4 步讲的那件事）；DMA 通道那一路要**在 `transfer()` 之后**才允许等
（`self.running` 还没真）。把两条都往前提会得到一个 `RuntimeError`，把中断那条推到后面
会得到一次丢事件——顺序按上面这样才是两边都不丢。

`wait_async()` 内部等的是**这个通道自己的** `_interrupt.wait()`（`:193-194`），所以这条路要求通道
确实绑到了中断线上；没绑就先用下面的 `bool(dma.recvchannel._interrupt)` 判，别让它抛在循环里。

能用哪几个名字，以目标上 `print(...)` 出来的结果为准。
`transfer()` 与 `wait()` / `wait_async()` 三个都是**类上就存在**的方法
（`lib/dma.py:106/166/189/317/470/525`）——这句话在这里是警告不是许可：

- `wait_async` 是类级 `async def`，**接没接中断它都在**，所以
   `hasattr(dma.sendchannel, 'wait_async')` 永远为真，被它判出来的"通路"是假的绿。
   真正的通路读数：`bool(dma.sendchannel._interrupt)` 与
   `dma.description.get("interrupts", {})`（详见 `dma-channels.md` §2）。
- 同理别用"能不能 import 到某个驱动名"当"这块 IP 有驱动"的判据——驱动是**按 VLNV 字符串**绑的：
   `bindto = ["xilinx.com:ip:axi_dma:7.1"]`（`lib/dma.py:758`），**退回 `DefaultIP` 有两条臂，
   一条响一条不响**（4.0.0 `overlay.py:58-82`，`_complete_description` 之前那一段）：
   **名字对得上、版本号对不上**（`no_version_ip in _ip_drivers` 那一支）走 `:72-79`，
   发一条 `warnings.warn(message, UserWarning)`（原文形状
   `IP {fullpath} is of type {type} and driver found for [{其它版本列表}]. Use ignore_version=True to use this driver.`）
   然后在 `:80` 设 `DefaultIP`；**连名字（去掉版本之后）都不在表里**的那支是 `:81-82`，
   **一句都不发**、直接 `DefaultIP`。所以"悄悄"只成立于后一支，**先前这里把两条都写成静默是错的**；
   两支都不报 ImportError。判据用
   `type(getattr(ol, 'axi_dma_0')).__name__` 打一次，或查 `overlay.ip_dict[name]['type']`
   与 `bindto` 的字符串是否完全相等。
