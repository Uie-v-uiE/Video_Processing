# 取证与分诊：三层结论、假绿、性能口径

## 1. 三层结论，缺哪层就补哪层的读数

| 层 | 成立只说明 | 拿它当上一层的后果 |
|---|---|---|
| ① Python 没抛异常 | 调用被接受（写是 posted write；DMA `transfer()` 只到"请求已提交"） | 以为 PL 收到了、以为数据搬完了 |
| ② 元数据里有这个对象/地址 | 导出时连着 | 以为板上位流就是这一版、以为地址没漂 |
| ③ 硬件在做事 | 需要独立通路：读回比对、完成状态位、`transferred` 长度、中断到达、计数器差值 | —— |

写结论时把层级写出来。"DMA 跑通了"这种话要么给 ③ 的读数，要么改成"①：调用没报错"。

## 2. 挂住 / 不动 / 结果不对 / 中断不到 的四棵分诊树

四棵树**不是互斥分支**："没抛异常、读回也对、下游就是不动"这一族要连着跑 A 的第 1 步和 B 的第 5 步，
**先 A1 后 B5**，两个读数成对留在报告里——只跑 B 会把"根本没时钟"误判成"位段没对"。

**A. 一笔访问就卡住（CPU 停在那一行、整机僵住）**
1. PL 有没有时钟、有没有出复位？先把它变成一个读数，而不是"我觉得有"：

    ```python
    from pynq import Clocks
    print([Clocks.fclk0_mhz, Clocks.fclk1_mhz, Clocks.fclk2_mhz, Clocks.fclk3_mhz])
    print([Clocks.get_pl_clk(i) for i in range(4)])    # 2.7.0/3.0.1/3.1.2 上会是 [None, None, None, None]
   ```

   **属性写法是主读数**：`fclk0_mhz`…`fclk3_mhz` 是 `_ClocksMeta` 上的 property，四路在两版里都存在
   （3.1.2 `ps.py:153/180/207/234`；4.0.0 `ps.py:247/274/301/328`）。它们返回的是实例层算出来的
   `round(src_clk_mhz / (div0 * div1), 6)`（3.1.2 `ps.py:325-345`；源码里的形参名是
    `pl_clk_odiv0`/`pl_clk_odiv1`，别按本包这两个缩写去 grep）。**"两版同形"有平台边界**：
    4.0.0 另有 `class _ClocksVersal(_ClocksBase)`（`ps.py:779`）与它自己的 `get_pl_clk`（`:891`），
    那里的公式只除一个分频（`round(src_clk_mhz / pl_clk_odiv0, 6)`）——所以本条读数是
    Zynq-7000/ZynqMP 那条 `_ClocksBase` 路的；Versal 目标上别照抄这个算式（本机没有 Versal 可跑，
    这一格只到源码为止）。

   `Clocks.get_pl_clk(i)` 在 **2.7.0/3.0.1/3.1.2 上都恒为 `None`**：元类转发器把 `return` 写丢了
   （3.1.2 `ps.py:260-271`、3.0.1 `:258-269`、2.7.0 `:286-297`，末行都是裸的
   `cls._instance.get_pl_clk(clk_idx)`），4.0.0 补回来了
   （`ps.py:354-365`）。所以"四路全 None"在 3.1 上**不是**"时钟没开"的证据，而是版本读数——
   反过来它还是一个不用查版本文件的判别式——**但这个判别式只分得出"这三版之一 vs 4.0.0"，
   分不出 2.5.1**：2.5.1 没有元类转发那一层，`get_pl_clk` 是 `_ClocksBase` 上直接实现的
   `@classmethod`（2.5.1 `ps.py:188-209`，末行 `return round(src_clk_mhz / (pl_clk_odiv0 * pl_clk_odiv1), 6)`
   在 `:209`，第一个形参写作 `mcs` 而不是 `cls`），**照样返回值**。所以"四路都有值"这一臂
   同时对应 2.5.1 与 4.0.0，要分开还得读 `pynq.__version__` 或那条转发行的原文。
   把它当硬件读数用会直接把树 A 引向假红。

   判据：**你预期在跑的那一路必须是设计里配的频率，不是 0、也不是默认值**。
   两个边界要写进结论：① 它读的是 **PS 侧的时钟发生器**，证明不了 PL 里那路时钟真的被引到了
   你的 IP（BD 里 `FCLK_CLK0` 没接、`clk_wiz` 没锁定，这里照样显示正常频率）——所以它只能
   **排除**"FCLK 根本没开"，不能**证明**"IP 有时钟"；后者的证据只能是设计里那个自由运行计数器
   （`first-bringup.md` §0）。② 设置频率会改分频器，属于动硬件状态，排查时只读不写。

   ①那一层还有一个更具体的形状值得先排：**同一个 IP 的"寄存器时钟"与"搬运/引擎时钟"常常是两个引脚**，
   只给寄存器那一路钟时，症状恰好是"寄存器侧全通、搬运侧一步不动"。
   **本包不是没有能红的读数**——下面出口 (b) 那两个状态位（`idle`/`error`）在这种形状下就是红的
   （引擎不动 → `idle` 永远不来或永远挂着）；`transferred` 只能在 `wait()` 之后取，别算进这一格
   （本页 §3 第 3 条）；这一对只判"引擎动没动总线"，**判不出"引擎该由哪一路钟驱动"**。
   后一层在设计侧取，本包不重复：`fpga-board-development/references/zynq-pynq.md` §1 给了逐个时钟引脚的
   读法（`get_bd_pins <cell>/*CLK*` 数出几路，再读每个引脚自己的 `CONFIG.ASSOCIATED_BUSIF`——那是
   "这一路钟驱动哪些接口"的自述，**按 IP 自己给的清单算，不要按引脚名字的字面猜**：本机就在
   `axi_dma` 的 lite 那一路清单里读到 `M_AXI`），还给了两条**别用**的读法。
   交接带 `.tcl`/BD 的工程时这一步该在写软件之前做，但**别把 `validate_bd_design` 当门**：
   那一节实测它只点名"什么都没接"的时钟引脚，接到普通输入口或接到没给 `-freq_hz` 的钟口它都不报，
   判"接的是不是钟"要读驱动端口的 `TYPE`。
   板上的确认也要跟着换形状：**每一路钟各埋一个自由运行计数器**（`first-bringup.md` §0 现在就是这么要求的）。
   两路钟的设计共用一个计数器就只能证明"有某个钟在跑"，证不了两路都在跑——这一条与下面出口 (a) 的
   "换一个不经过被测逻辑的读数"是同一件事的两半。

   **但这条出口不能只靠那个计数器**：如果计数器正是你要查的东西，"证据只能是它"就是循环论证。
   非循环的第二个见证源，按代价从低到高：
   (a) 换一个**不经过被测逻辑**的读数——同一 IP 里另有一个由同一路时钟驱动、但不挂在你的
   数据通路上的计数器/状态位（很多 BD 模板里的 `probe`/`keep` 寄存器就是）；
   (b) 看 PS 侧能不能证明 PL 在**动总线**：一次 SG 传输的 `idle`/`error` 两位成对读
   （`dma-channels.md` §2；`transferred` 只能在 `wait()` 之后取，见本页 §3 第 3 条）
   ——引擎走到 `idle` 说明 AXI 侧有活动，与寄存器通路无关；
   (c) 设计里本来有的第二个时钟域对照（`clk_wiz` 输出那一路的锁定位），
   注意它证明的是"那一路在跑"，不证明引到了你的 IP；
   (d) 三者都没有时，**软件侧到此为止**：结论写成"无法区分 FCLK 未跑 / 时钟未引出 /
   逻辑被按住"，下一级观测是 ILA 或网表仿真，那一层在 `fpga-board-development`：
   插探针走 `fpga-board-development/references/onchip-debug.md`（§2.1 那条网表手术路，不要工程也能跑），
   网表仿真走 `fpga-board-development/references/verification.md` §8。
   不要靠"再换个值试试"或延长 `sleep` 来代替这条——那只会把假绿留得更久。


   还有一条只读的同源证据：`ol.clock_dict` 是 overlay 解析出来的那一层，两版的**键不一样**
   （3.1 `overlay.py:424-426` 用 `divisor0`/`divisor1`；4.0.0 `overlay.py:425` 用 `frequency`）。
   打印 `sorted(ol.clock_dict[0])` 既能看到设计里配了什么，也顺带告诉你手上是哪一版。

2. 这段地址上有从设备吗？`PL.ip_dict` 里查 `phys_addr`，与 `MMIO(base, len)` 用的 base 对得上吗
3. ZynqMP/RFSoC 上有没有 SMMU/地址翻译把物理地址改写了（PL 看到的不是这个号）
   → 这一格本包给不了配置层的做法，但**给得出一个可判的实验**：同一块缓冲区，
   PS 侧 `np.array(buf)` 读回正确、PL 侧报 `0x20/0x200` Slave Error，这个组合就把问题从
   "数据内容"移到"地址可达性"。引擎那一侧**只能取状态位**：`ch.idle` 不来、`ch.error` 挂着
   （`dma-channels.md` §2）。
   **别把 `dma.<ch>.transferred == 0` 写成"一笔都没进去"的证据**——它是 `wait()` 返回时才写的，
   而 Slave Error 这条分支上 `wait()` 在写它之前就 `raise`（4.0.0 `lib/dma.py:175-177`、`482-497`），
   于是这一句在真正的地址层故障上**必然成立**，判据永远红不了（本页 §3 第 3 条）。
   反过来：`wait()` 正常返回、`transferred` 与请求长度相等而**内容**错，就不是翻译层，回到树 C。
→ 这一支的结论是"通路不通"，**不是**"值设错了"。别再重试同一笔写。

**B. 不卡、但值不对（读回 0 / 恒 F / 与写无关）**
1. offset 单位对不对（`MMIO.read` 是**字节**偏移且必须 4 对齐；`ip.mmio.array[i]` 是**字**索引。
   注意 `ip.array[i]` 这个写法在两版里都不存在——它抛的是 `AttributeError`，属"名字写错"不是
   "寄存器不存在"，判法见 `mmio-registers.md` §3。
   **这一条的正对照在源码里，不是板子上**：`array` 这个属性是在 `MMIO` 构造函数里赋的
   （3.1.2 与 4.0.0 都在 `mmio.py:73`/`:78`/`:83` 三处，两版同形），
   而 `overlay.py` 里 `def array` 在两版都**一行也没有**——**同一次扫描内的正向对照**：
   同一句换成数方法定义行 `grep -c '    def ' pynq/overlay.py` 在 3.1.2 与 4.0.0 **各交回 37**，
   所以那个 0 不是"这把 grep 看不见这个文件"，是这个名字真的没定义在那里。
   `DefaultIP` 上没有这个名字，
   所以要写 `ip.mmio.array[i]`。（没板子也判得了：凭的是属性赋值的位置，不是运行时观察）
2. 位段与极性：反相位位（`1=关`）、标志塞低字节 vs 文档写 `[8]/[9]`
3. 8 字节读：`word_order` 是字序不是端序；小于 8 字节不做符号扩展
4. 收到之后有没有消费者、生效还要什么条件（门控/模式锁）
5. 单独扫位，别只按文档那个"启动值"整字写。整字 `0x11` 里可能同时含一个把你按住复位/使能反相的位，
   于是"写成功、读回也对、下游就是不动"：

    ```python
    import time
    from pynq import MMIO, PL    # PL 是读 ip_dict/interrupt_pins 的那个入口，别省掉导入
    base = PL.ip_dict["my_ip_0"]["phys_addr"]
    mm = MMIO(base, 0x40)    # 只映射你需要的这一段，别顺手给个 0x1000；本页的默认写法是按实际用到的寄存器范围给长度，只有 `overlay-metadata.md` §5 那个要扫整段的骨架才给 0x1000
    CTRL_OFF, CNT_OFF = 0x00, 0x04 # 这两个数必须来自这一版 IP 的寄存器表，不是记忆
    orig = mm.read(CTRL_OFF)
    try:
        for v in (0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x11, 0x100, 0x200):
            mm.write(CTRL_OFF, v)
            time.sleep(0.05)    # 0.05 s 只有在"计数器每 N 拍 +1"已知时才够；
            # N 从设计里来，按 2*N/clk_mhz 秒算，别沿用这里的数
            print(f"ctrl=0x{v:03x} counter={mm.read(CNT_OFF)}")
    finally:
        mm.write(CTRL_OFF, orig)    # 收尾回到已知状态，并把 orig 一起写进报告
   ```

   上面三个名字（`mm`/`CTRL_OFF`/`CNT_OFF`）在本页其它地方直接用，是没定义的引用——现在补齐：
   偏移一律从 `ip.register_map` 或这一版的寄存器表里取（`mmio-registers.md` §3），
   映射长度按实际用到的寄存器范围给。

   这一条与 `mmio-registers.md` §4 的 `probe32` 是**两种情形**，别混用：`probe32` 验的是
   "通路通不通"，所以只许往无副作用的暂存寄存器写；这里是**故意**去摸控制字，代价就是你改过了
   硬件状态——所以必须①先读原值、②扫完在 `finally` 里写回、③把原值留在读数里，
   否则中途异常就会把 PL 留在某个扫描值上，后面的读数不知道从哪个状态起算。
   扫位之前先想清楚哪一位是复位极/使能极，扫到它时 PL 会真的复位一次，这属于预期内而不是故障。

   判据是**哪个值让计数器动**，动的那个才是真的 enable；它和文档不一致时，不一致本身就是结论，
   要把 `ctrl=` 与 `counter=` 成对留在报告里。（这一条不需要 PL 侧配合，只需要计数器可读。）

   **如果没有任何一个值让它动**，这一支就走完了，不要继续换值试。剩下的可能性只有四类，
   按能不能在软件里排除排序：① 计数器本身不在你扫的那个地址（回去核 `ip.register_map` 与
   地址段，`mmio-registers.md` §3）；② 读回口根本没接（读到的恒 0/恒 F 就是这条的读数）；
   ③ 那一路时钟真的没跑（走 §2 树 A 第 1 步，注意它只能排除 FCLK 没开，不能证明 IP 拿到时钟）；
   ④ IP 被某个你扫不到的位按住复位/门控（要看 BD 里那个 `proc_en` 类的使能链）。
   这四类都排除不掉，就把它写成结论交出去：**"寄存器层无法区分'无时钟'与'逻辑被按住'"**
   是需要 ILA/网表级观测的信号，不是继续扫位的理由（设计侧那一层归 `fpga-board-development`：
   "使能链被常量按住"这类看 `fpga-board-development/references/rtl-pipeline-cdc.md` §5，
   插探针看 `fpga-board-development/references/onchip-debug.md`）。

→ 详见 `mmio-registers.md` §4-§5。

**C. 寄存器都对，但数据不对（半新半旧、首块/尾块坏、错位、偶发旧值）**
1. `buf.cacheable`？一致性调用方向对不对（`sync_to_device` / `sync_from_device`）
2. 对齐与长度：`(physical_address + start) % 数据位宽` 是否为 0（判的是**和**，不是基址 alone）、
   `nbytes` 是否超 `_max_size`。**注意 SG 不检查长度**：超限不报错，驱动自己拆描述符，
   所以"没报 exceeds maximum"在 SG 上不是读数（`dma-channels.md` §1 第 2 条）
3. 3.1 上的 SG `start` 缺陷：填描述符时低 32 位漏加 `start`、高 32 位却加了 → 常见表现是"从数组头搬"，
   跨 4 GiB 进位时表现成引擎报错。范围要说准：那段循环 **cyclic 与非 cyclic 共用**，
   所以是"SG 且 `start != 0`"全体，不是只有 cyclic；SDMA 两版都对，于是
   "同一块缓冲同一个 `start`，SDMA 对、SG 错"本身就是一条免仪器差分
   （`versions-and-apis.md` §4、`dma-channels.md` §1 第 2 条）

4. 完成判定太早：只 `sendchannel.wait()` 没等 `recvchannel`；或 cyclic 模式下等 `wait()`
5. 带宽/竞争：所有 master 列全再算账（显示扫描、其他 DMA、DDR 刷新）
→ 详见 `buffers-and-cache.md` §2-§3 与 `dma-channels.md` §1-2。

**D. 中断不到（"昨天还好，今天 `wait()` 永远不回"）** —— 先做差分，别先改代码：

1. `print(PL.interrupt_pins)` 与 `print(PL.interrupt_controllers)`：针还在、控制器为空 ⇒ 这一版的中断
   根本不走 `axi_intc`（见 `interrupts.md` §1.1 的适用范围），下面第 3 步不适用——**改走名字链**：
   针的 `raw_irq` → `/proc/interrupts` 里倒数第三列等于它的那一行 → 该行最后一列（设备名）→
   与 `/sys/class/uio/*/name` 整串相等（`interrupt.py:32-42` + `uio.py:27-32`）。
   这三段断在哪一段，就分别是"IRQ 没排上 / `.dtbo` 没声明 UIO 节点 / 名字不一致"，
   而 `Interrupt(pin)` 在这条路上的报错是 `Could not find UIO device for interrupt pin for IRQ number N`
   （`interrupt.py:145-147`），不是 `No Pin of name ... found`（那是名字写错，`:63-64`）。

2. 按 `Interrupt.__module__` 先确认这次是在板端还是远程模式（两者的交付路径不同）。
   两个取值是固定的，别只看"有没有值"：板端 `pynq.interrupt`，远程 `pynq.pl_server.remote_device`
   ——`__init__.py:18` 在远程环境里把 `RemoteInterrupt as Interrupt` 别名进来，`:22`(3.1.2)/`:26`(4.0.0)
   才是板端那条 `from .interrupt import Interrupt`。打出来是第三个值 ⇒ 你的 `pynq` 不是发行版那份。

3. 找 `/proc/interrupts` 里对应那一行，在触发前后各读一次计数（`sudo` 视镜像而定）：
   **计数没动** ⇒ PS 侧压根没收到 ⇒ 查源 IP 的中断使能与 `bool(channel._interrupt)`；
   **计数动了而 `wait()` 不回** ⇒ 交付/清位那一层 ⇒ 按 §3 第 9 条把通道停干净重来，
   不要靠加重试次数或延长超时——那只会把假绿留得更久。

   **"另一个脚本/进程一跑起来，这个脚本的中断就再也不来"有确定的机制**，不用猜：
   `_InterruptController` 的注册表是**类属性**，所以它是**每个 Python 进程一份**，
   不是每块板一份。
   第二个进程第一次碰到某个控制器时走 `get_controller()` → 构造 →
   **`self.mmio.write(0x08, 0)`**（`:174`，注释 "Disable Interrupt lines"）——
   它把 32 条线全部 disable 掉，而写的是**同一块硬件**的同一组寄存器。
   于是第一个进程那边"针还在、注册过、事件对象还活着"，但线已经被别人全局关了；
   而且第一个进程不会收到任何异常。判据（只读，不改状态）：
   在两个进程里分别打印 `os.getpid()` 与 `sorted(PL.interrupt_controllers)`，
   进程数 > 1 而控制器名相同，就是这一条。
   处理办法只有一个方向：**中断的注册与等待收在同一个进程里**；
   另一个进程要读状态就走寄存器/轮询（`dma-channels.md` §2 的四口），别在那边 `Interrupt(...)`。
   这条与 `SKILL.md` §4 里"两个进程/notebook 同时管同一块 PL"那一行是同一族，但那一行讲的是 mmap 所有权，
   讲的是**没有机制可查**；这一条讲的是 axi_intc 的使能位，**机制是确定的**。


## 3. 这个包里常见的十二种"假绿"

1. **`write()` 没报错就当写到了** → 必须做"破坏性图案 + 读回"（至少 0x0、0xA5A5A5A5、0xFFFFFFFF 三式），
   恒 0 / 恒 F 不算通过。两个限定，不然这条与 §2 树 B5 自相矛盾：
   ① **图案只写无副作用的暂存寄存器**，写完 `finally` 复原——规范实现就是
   `mmio-registers.md` §4 的 `probe32`（它带原值记录与复原），别在这里另起一套裸写；
   ② "部分位读不回来"是**常态而不是失败**：RO 位、被硬件强制的位都会让读回 ≠ 写值。
   所以判据不是"完全相等"，而是**逐位表**：对每一位记"写 0 读回 / 写 1 读回"，
   只有"两位都读不回、且文档说它可写"的那一位才算坏。报告里要留下这张表。

2. **只读一次相同地址** → 地址译码错、行冲突、容量不足全在单点之外。可执行的替换判据：
   同一 IP 内**至少取三个相距较远的偏移**（如 `0x00` / 中段 / 表里最后一个寄存器），每个都跑
   写-回读；只有单点通过 = 没排除"整段里只有那一个位置恰好对"。
3. **`transfer()` 返回就当搬完** → 没有完成判定等于没做完。可用的完成判定只有这三种，各自有出口：
   `wait()`/`wait_async()` 正常返回、`ch.idle` 为真**且** `ch.error` 为假、`ch.transferred`
   与请求长度相等（`dma-channels.md` §2 的四口与错误位表）。三者一个都没读到就打印"完成"，
   就是把①层当③层。
   **但第三口不是前两者的旁证**：`transferred` 是 `wait()`/`wait_async()` 返回时写进去的，
   而 `transfer()` 一开始就把它清 0——所以"等之前读到 0"结构上必然发生，既不能判"一笔都没进去"，
   也不能判"搬完了"。错误分支上更明显：`wait()` 在写它之前就 `raise`（4.0.0 `lib/dma.py:175-177`、
   `482-497`），此时手上能取到的独立证据只有 `idle`/`error` 那两个状态位。
4. **参考实现照抄 RTL 语义** → 模型与实现同源于同一个误解时永远"一致"；参考要么来自实测golden，
   要么用不同算法（如 numpy 向量化 vs 流水线逐像素）。
5. **切片视图当数据用** → `PynqBuffer` 是 ndarray，切片只是视图；`freebuffer()`（或退出 `with`）
   之后再读是 UB。要比对就 `np.array(buf)` 拷一份。
6. **`finally: buf.close()` 当成"释放了"** → `close()` 在**这两版都不释放**，但**留痕不同**：
   2.5.1 的 `close()` 函数体只有一句 `pass`（2.5.1 `buffer.py:107-111`，docstring 写着
   "Unused - for backwards compatibility only"），**连警告都没有**；
   2.7.0 起同一个位置改成发 `DeprecationWarning`
   （2.7.0 `buffer.py:107-113`，文本 `.close no longer functional - use scopes to manage buffers`）。
   两边都不调 `freebuffer()`（那一句在 `__del__` 里：`def __del__` 在 2.5.1/2.7.0 `buffer.py:79`、
   调用在 `:80`；3.1.2/4.0.0 分别是 `:62` 与 `:63`——**别把 `def freebuffer` 那一行（`:82`/`:65`）算进 `__del__` 的区间**）。它**没报错**恰恰是这条假绿的全部危险：
   长跑脚本的连续内存池一直在漏，直到某次无关的 `allocate` 报 `MemoryError`；
   **而在 2.5.1 上连那声警告都没有，日志里一个字都不会出现**（释放与作用域那一侧的口径见
   `buffers-and-cache.md`，它按 2.7.0 `buffer.py:107-113` 引的是同一件事的 warned 那一臂）。
7. **`hasattr(channel, 'wait_async')` 当成"中断接好了"** → 它是类上的 `async def`，
   永远为真（`lib/dma.py:189/525`）。这条判据出生以来没红过，所以它不是判据（`dma-channels.md` §2）。
   能红的替换判据是这三行，它们各自把一种"没接上"分开：

    ```python
    dma = getattr(ol, "axi_dma_0")   # ol 是你手里的 Overlay 对象；cell 名从 PL.ip_dict 现取，别硬编这个字面量
    ch = dma.sendchannel
    print(ch is None)    # True = 这一路在硬件里根本没开(c_include_mm2s=0)
    print(bool(ch._interrupt) if ch is not None else "no-channel")    # False = 通道在、但中断对象没进来
    print(sorted(dma._interrupts))    # [] = .hwh 里没有 mm2s_introut 这个针脚
   ```

   依据：`DMA.set_up_tx_channel` 只在 `"mm2s_introut" in description["interrupts"]` 时才把
   `self.mm2s_introut` 当参数传进去，否则建的是 `interrupt=None` 的通道（`lib/dma.py:671` 与其后的
   `else` 分支；SDMA/SG 两条分支同构）。而 `_interrupts` 在 `DefaultIP.__init__` 里是
   `description["interrupts"]`，缺这个键就是 `{}`。
   第三种组合最有信息量：`_interrupts` **非空**但 `ch._interrupt` 是 `None` → 元数据里有这根针，
   `Interrupt(details["fullpath"])` 构造时抛了 `ValueError`，驱动**打了个 warning 然后 `setattr(None)`**
   ——回去看加载时那条 `Interrupt ... not created`，它通常就是 `.dtbo` 与这一版 BD 对不上（§2 树 D）。
   **这条 warn/置空的路在 `overlay.py` 的 `DefaultIP.__init__` 里，不在 `lib/dma.py`**（本机按行取过：
   3.1.2 `:711-714`、4.0.0 `:708-711`，四行分别是 `setattr(... Interrupt(details["fullpath"]))` /
   `except ValueError as e:` / `warnings.warn("Interrupt {} not created: {}"...)` / `setattr(self, interrupt, None)`）。
   同一条 grep 在 `lib/dma.py` 里对 `"not created"` **命中 0 次**（正向对照就是上面 overlay.py 里那些行，
   所以那个 0 是"这条不在那个文件"，不是"没扫到"）。
   **版本边界**：2.5.1 的同一处（`overlay.py:649`）**没有 try/except**——那一版这个 `ValueError`
   会直接穿出来，既不会有 warning，也不会有那个值为 `None` 的属性；所以在 2.5.1 上"看见 `ch._interrupt`
   是 None"这条读数本身不存在。

8. **`import pynq` 成功当成"装对了"** → 一个空的/不含 `__init__.py` 的 `pynq/` 目录也会导入成功
   （namespace package），随后所有名字都解析不到，看着像版本不对。判据：`pynq.__file__` 不是 `None`。
9. **异常后继续跑** → 前一轮 DMA/中断状态没清，后面的读数全被污染。特别注意 cyclic：
   在 recvchannel 上传 `cyclic=True` 时源码**先赋值后检查**（`lib/dma.py:366→368`），
   抛了异常也把 `_cyclic` 留下了，而 `stop()` 不清它 → 之后 `wait()` 一直 `RuntimeError`。
   要么先用 `MMIO` 写 `RS=0`（cyclic 下再补 `0x0004`）——**别指望 `channel.stop()`：引擎没停下来时它会
   死在自己的 `while self.running: pass` 里**（`dma-channels.md` §2），要么再 `transfer()` 一次把 `_cyclic`
   覆盖回去（`dma-channels.md` §1 第 3 条）。
   **"重启 kernel"不是这一步的替代方案**：重启内核不会替你写 `RS=0`，一个还在跑的 cyclic MM2S
   会继续从已还给内存池的 CMA 页里搬数据——既污染 PL 消费者的输入，又去读别人的内存，
   状态比什么都不做更坏。要重启 kernel，先把通道停干净（`SKILL.md` §5 同一条规则）。
10. **notebook 里用 `In/_` 的历史结果当"这次跑出来的"** → 每次重跑都把关键读数打印出来，不要引用 cell 号。
11. **`checks=0` 的 PASS** → 比对循环一次没进（形状/切片/dtype 不对，或 mask 把全样本滤空）。
   判定行必须带计数：`checks=`、`mismatches=`。
12. **重下位流之后继续用旧句柄** → `ol.<ip>` 由 `_IPMap.__getattr__` 懒建后 `setattr` 缓存，
   缓存挂在 `ol._ip_map` 上；`download()`/`reset()` 都不清它，也不重建 `_ip_map`
   （`overlay.py` 里 `delattr` 0 次命中，同文件 `setattr` **8 次**命中——**但这两族不是同一个对象**：
   懒建缓存那 5 次在 `_IPMap.__getattr__` 里（4.0.0 `:797`/`:810`/`:814`/`:820`/`:826`），
   另外 3 次是 `DefaultIP.__init__` 绑中断与 GPIO（`:708`/`:711`/`:714`）。
   上面那条"旧句柄不刷新"只由**前 5 次**支撑；拿 8 这个总数当证据就是把两族混着数了。
   两处 `__dict__` 只做 `__dir__` 枚举）。
   所以老句柄会**安静地**按上一次的 mmap 继续写，直到某个读数解释不通。
   例外要知道：`pr_download` 那条路会整块替换 `_ip_map`，之后取到的是新对象——
   但**动手的不是 `pr_download` 自己**（它只是转到对应 region 上；那句赋值在
   `DefaultHierarchy.download` 里，逐行归属由 `overlay-metadata.md` §3.2 末段拥有，本页不重讲）。
   别把这条一律当成"重下必留旧句柄"。判据：改前改后各打印一次 `id(ol.axi_dma_0)`，
   再各打印一次 `hex(ol.axi_dma_0.mmio.base_addr)` 与 `hex(PL.ip_dict["axi_dma_0"]["phys_addr"])`
   （用 `mmio.base_addr` 而不是 `.description`：`DefaultIP` 不存 `description`，
   机制、行号与为什么 `del ol.axi_dma_0` 删不掉它在 `overlay-metadata.md` §3.2）。

   同族写法：**别用 `hasattr(ol, 名字)` 判存在**——名字存在时它会触发驱动构造（有副作用），
   overlay 没加载时它抛 `RuntimeError` 而不是给 `False`；用 `name in PL.ip_dict`。


## 4. 性能怎么量才不骗自己

```python
import time
def bench(fn, reps=7, warmup=2):
    for _ in range(warmup): fn()
    ts = []
    for _ in range(reps):
        t0 = time.perf_counter(); fn(); ts.append((time.perf_counter() - t0))
    ts.sort()
    return {"reps": reps, "min": ts[0], "median": ts[len(ts)//2], "max": ts[-1]}
```

- **报最差或报中位，写清楚是哪个**；取最好一次当结论是这一族最常见的错。
- 口径要一起报：缓冲区尺寸、是否一次 `allocate` 复用、`transfer` 是单次还是分块、有没有含
   `sync_*`/`allocate`/`freebuffer`、双向还是单向。"吞吐 420 MB/s"没有这些限定就是不可比的数。
- **测量进程里不许有遗留的忙轮询线程。** 用 `dma-channels.md` §2 那个 `wait_with_timeout` 之后，
   超时并不会杀掉线程，它还在 `while True` 读 MMIO，从此抢 GIL 与 AXI-Lite 带宽，
   把同进程后续所有吞吐读数压低（那次对照的具体毫秒数写在那页，且只适用于那一台主机）。
   开工先 `print(threading.enumerate())`。
- 上限有两处天花板，分开报：AXI DMA 的 `buffer_max_size`（长度寄存器位宽决定）与 DDR/HP 口带宽
   （把所有竞争 master 列全再算）。**micro 版 AXI DMA 的单次上限是 `数据位宽 × burst_size`，
   跟 `buffer_max_size` 不是一个数**（`lib/dma.py:664-666`），报上限前先确认你这版是不是 micro。
- 长度寄存器位宽是 IP 参数，不是常数：`(1 << C_..._LENGTH_WIDTH) - 1`（`lib/dma.py:631-637`）。
   换 IP 配置要重测，不要沿用上一版的分块大小。
- **HP/ACP 带宽上限要当场算，不要搬数字。** 算法只有两个输入，都能从你自己的设计里读到：

    ```python
    per_port_bytes_per_sec = fclk_mhz * 1e6 * (bus_width_bits / 8)    # 该口的位宽与那路时钟
   ```

   `fclk_mhz` 用 `Clocks.fclk0_mhz`…`fclk3_mhz` 现读（`debug-triage.md` §2 树 A；别用 2.7.0/3.0.1/3.1.2 上的
   `Clocks.get_pl_clk`，它返回 `None`），`bus_width` 从 Address
   Editor/`ip_dict[...]['parameters']` 里那个 `*_DATA_WIDTH` 读——**两者都不是常数**。
   然后：① 把同一时刻会并发用这块 DDR 的 master 全列出来（显示扫描、另一个 DMA、VCU、DDR 刷新
   本身），② 上限按最窄的那一段取，③ 实测吞吐超过算出来的数就先怀疑口径错了（帧率/字节数/是否含
   一致性维护），因为那意味着你的模型少算了什么或者多算了什么。
   实测侧：`transferred / elapsed` 是引擎自己报的字节数，比"我以为搬了多少"可靠一级。
- 时间测量的下限警告：单次操作若小于计时粒度，先把 reps 加大到总时长 ≫ 10 ms 再报。

## 5. 一份能贴进问题的取证包

出问题时按这个顺序采集，一次交齐（缺项就写 NOT_RUN，别空着）：

```text
1    pynq.__version__ / pynq.__file__ / python 版本 / sys.executable / 板型(compatible)
2    Interrupt.__module__（判断板端还是远程模式）
3    PL.ip_dict 的相关条目（名字、phys_addr、addr_range、type）
4    PL.interrupt_pins 的相关条目（**键就是 `<实例>/<端口>` 这一形**——解析器把针名按
     `block, _, pin = interrupt.rpartition("/")` 拆开分发给 `ip_dict[block]["interrupts"][pin]`
     （4.0.0 `pl_server/hwh_parser.py:519-524`），所以字典的键与 `fullpath` 同源；
     值的键实测是 `controller`/`index`/`fullpath`，3.x/4.0 多一个 `raw_irq`
     （逐版赋值行：2.5.1 `:387-389`（**没有 `raw_irq`**）、2.7.0 `:429-433`、
     3.0.1/3.1.2 `:433-436`、4.0.0 `:440-444`）；
     **`parent` 不在针的条目里，它在 `interrupt_controllers` 那本字典**（4.0.0 `:432-435`），
     先前这一格把两本字典混成一本，已改）
    连接键是**驱动自己在用的那一条**：
    针的 `raw_irq` ⇄ `/proc/interrupts` 里**倒数第三列等于它**的那一行（该行需 ≥7 列）⇄
    那一行的**最后一列**（设备名）⇄ 必须与某个 `/sys/class/uio/*/name` **整串相等**。
    三段里断在哪一段，结论就分别落在"位没排上 / 设备树没声明 / 名字对不上"。
5    目标寄存器的读回表：地址、写值、读回值（三种图案）
6    缓冲区：shape/dtype/nbytes/cacheable/physical_address 的低 32 位；用的是 with 还是 freebuffer
7    DMA：_max_size 与 buffer_max_size（micro 下两个数不同）、两个通道各自 is None 与否、
    bool(channel._interrupt)、最近一次 transferred
8    dmesg 尾部、/proc/interrupts 相关行、/sys/class/uio/*/name
    （先按 `dmesg -T 2>/dev/null | tail -40` 试：多数 PYNQ 镜像里 `xilinx` 用户能直接读，
    读不到再加 sudo；`/proc/interrupts` 与 `/sys/class/uio/*/name` 一般是世界可读的。
    实在拿不到就在清单里写 `NOT_RUN: 权限不足`，不要留空，也不要把它读成"没有相关记录"）
9    复现脚本本体 + "改前能复现 / 改后不复现" 的两份读数
```

前 4 项都是只读命令能直接打出来的（`cat /etc/pynq_release.txt`、`python3 -c 'import pynq; print(pynq.__version__)'`、`print(PL.ip_dict)`、`cat /proc/interrupts`）；5–7 是你这次测试的私有信息，只有你自己能填。
