# Zynq / PYNQ — PS 与 PL 之间的通路、缓冲区、Overlay、色彩与位置

## 1. 先分清 PS 能走哪几条路

| 通路 | 用途 | 证明它 work 的东西 |
|---|---|---|
| GP + AXI-Lite（MMIO / GPIO） | 控制字、状态读回 | 写下去的字被读回，且 PL 侧确实用了它（`board-bringup.md` §4 五步） |
| HP / ACP + AXI（DMA、VDMA、自定义 master 直访 DDR） | 大块像素/样本搬运 | 端到端数据比对 + 长度一致 + 完成判据成立 |
| AXI-Stream | **PL 内部**的流式接口；PS 侧没有直接接流的路径 | 握手不丢不重、`TLAST` 边界正确、无反压下的吞吐数 |

第三条常被误当成"PS 可以直接收发的流"：流要进 PS，得先由 DMA/VDMA 把它落到 DDR（走 HP），
所以流的吞吐上限要按 DMA + DDR 带宽算，不是按 PS 主频算。

**第一条全通、第二条一步不动，最省时间的怀疑不是软件，是"这个 IP 其实有两路钟"**。
AXI-Lite 那一路管寄存器，引擎那一路管搬运，它们在 BD 里是**不同的引脚、常常接不同的钟源**；
只给前者上钟，症状正是"寄存器写得进、读得回、`ip_dict` 里也有这个地址，但引擎永远不动"。
这一层在设计侧就查得完。读数不是一次取的，别当成同一份 BD：第 1、3 步与第 2 步里 `axi_dma` 那几个值
来自同一份只连了两路钟的 DMA BD；第 2 步里 `axi_gpio` 与 `clk_wiz` 两处对照是另一份只放了这三个 IP、
一条线都没连的 BD。

1. 先 `validate_bd_design`：**什么都没接**的时钟引脚会被逐个点名（消息原文形状、以及它套在外层命令上的
   那个 `[Common 17-39]` 外壳，都记在 `vivado-project-bd.md` §2 第 1 条——那一节是这一族的规范位置）。
   **但它的能力就到"没接"为止**（本机专门做过三个反例）：把 `m_axi_mm2s_aclk` 接到一个**普通输入口**
   （`create_bd_port -dir I`，没有 `-type clk`）、把 `m_axi_s2mm_aclk` 接到一个**没给 `-freq_hz` 的钟口**，
   这两条都不进 `41-758` 的名单——那一次它只点了完全没连的 `m_axi_sg_aclk`。
   所以 "validate 过了" 既不说明接的是钟，也不说明那一路有频率；下面第 2、3 步不是"更细"，是**唯一**做这件事的。
   同一份 BD 里 `create_bd_port -dir I -type clk` 漏了 `-freq_hz` 会当场来一条 `WARNING: [BD 5-670]`，
   消息里把该给的参数写法直接写了出来——这类"自带用法"的告警不要压掉。
2. 列这个 IP 的时钟引脚，再读**每个时钟引脚自己的 `CONFIG.ASSOCIATED_BUSIF`**：它就是"这一路钟驱动
   哪些接口"的自述，比名字可靠。本机在 `axi_dma` 上读回（冒号分隔，逐条实测）

   ```tcl
   get_bd_pins dma0/*CLK*   ;# 4 条：s_axi_lite_aclk m_axi_mm2s_aclk m_axi_s2mm_aclk m_axi_sg_aclk
   get_property CONFIG.ASSOCIATED_BUSIF [get_bd_pins dma0/s_axi_lite_aclk]
   ;# S_AXI_LITE:M_AXI
   get_property CONFIG.ASSOCIATED_BUSIF [get_bd_pins dma0/m_axi_mm2s_aclk]
   ;# M_AXI_MM2S:M_AXIS_MM2S:M_AXIS_CNTRL
   ```

   这个名字**确实在 `list_property` 的清单里**（本机对 `dma0`/`gpio0`/`cw0` 的每一个时钟引脚都列到它），
   所以"先 `list_property` 证明名字在、再取值"这条在这里也是可执行的。
   而且它是 **IP 自带的元数据、与连线无关**：本机在一份什么都没连的 BD 上读到的 DMA 四个值，
   与上面那份连了两路钟的 BD 一字不差——所以 BD 没连完也能读，不必等到验证通过。
   **`*CLK*` 数出几条本身就是读数**：本机 `axi_dma` 4 条、`axi_gpio` **只有 1 条**
   （`s_axi_aclk` → `S_AXI`）、`clk_wiz` 2 条（`clk_in1`/`clk_out1`）。只有一条钟的 IP 不会有
   "两路钟"这个症状，别把时间花在它身上；两条以上的才逐路对下去。
   **但"名字在清单里"不等于"有值"**：`clk_wiz` 那两个引脚都读回**空**——它不服务任何 AXI 接口。
   空读数不是报错，却也什么都不告诉你，这种引脚的归属只能回到第 3 步去问"谁驱动它"。
   **清单里出现什么由 IP 自己定**（本机就在 lite 那一路的清单里读到一个 `M_AXI`），
   所以"哪一路钟管哪个接口"只能按读到的清单算，不能按引脚名字的字面猜；换 IP 要重新列一遍。
3. 再看每一路钟实际连到谁：`get_bd_nets -quiet` 逐条取，对每条用 `get_bd_pins -quiet -of_objects <net>`
   列挂在同一根线上的引脚。本机这样读出 `clk0_1 shares=<s_axi_lite_aclk>`、
   `clk1_1 shares=<m_axi_mm2s_aclk>`——**连线后的 net 名会自动补 `_1`**，按端口名去找 net 会 0 命中。
   两个别用的读法（本机核过）：`CONNECTED_BD_PINS` 不在 BD 引脚的属性清单里，而对**已经连好**的引脚读它
   返回**空且不报错**——拿它判"连没连"必然假阴性（正对照是同一个引脚对象上的 `DIR`=`I` 与
   `ASSOCIATED_BUSIF`，都有值）；`get_bd_pin_relations` 这版没有这个名字（`invalid command name`）。
   **"接的是不是一路钟"要读驱动端口的 `TYPE`**：本机 `create_bd_port -dir I -type clk` 出来的两条读
   `TYPE=clk`，而 `create_bd_port -dir I`（普通输入）读 `TYPE=undef`——把它接到 `m_axi_mm2s_aclk` 上
   就是第 1 步那个 validate 不报的洞，只有这一条读数能看见。
   **`CONFIG.FREQ_HZ` 在这里不能当证据**：那份 BD 里三个已连的时钟引脚**全部读回 `100000000`**，
   包括接在非钟口上的那一路、也包括接在"没给频率的钟口"上的那一路（那两个端口自己的读数分别是空与
   `100000000`）。也就是说引脚这一层的频率是**推出来的默认值**，不反映源头有没有被声明成钟、
   有没有频率——要判"这一路到底跑多快"仍然只能回到板上那个自由运行计数器的读数。

板上确认这一层的做法是**每一路钟埋一个自己的自由运行计数器**（不是共用一个）：只有"这一路的计数器在涨"
才证明这一路活着。只埋一个，它涨只能证明"有某个钟在跑"，证不了两路都在跑——这是
`board-bringup.md` §6 那条"每道门要有自己的可数读数"在时钟这一层的版本。

## 2. 地址不是常数，offset 是字节

地址、位宽、复位值都从设计导出（Address Editor 的导出、`.xsa`、`.hwh`、BD 摘要），不要抄进代码
变成第二个真源。改一次 BD 重综合，映射就会变。

两个具体陷阱：

- **MMIO 的 offset 是字节地址**，不是字索引：`write(0x10, v)` 是第 4 个字。按字索引写的代码会
  命中相邻寄存器，症状是"设 A 结果 B 变了"。
- `CFG_DATA0` / `CFG_DATA1`、`GPIO_DATA` / 状态读回口这类**只差一位**的名字，写错字的症状恰恰是
  "设了没反应"——先把"写哪个地址、从哪读回"这两行打印出来核对，再怀疑 PL。

### 2.1 两种总线错误码：先定位"这笔访问走到哪一层"

- **`DECERR`**：互连里**没有**对应这个地址段的 slave。等于"地址没分配，或分配表与软件用的不是
  同一份"。常见成因：BD 改过之后没重新导出（手里的 `.xsa/.hwh` 还是旧映射）、访问经过的口其地址
  范围不含这段、两个 master 用了不同基址。
- **`SLVERR`**：地址**到了** slave，是 slave 自己拒的。常见成因：拿 AXI4-Lite 去做它不支持的
  访问（Lite 只有单拍、按寄存器对齐，没有 burst、没有窄传输）、写到只读位置、IP 内部判非法。

分层判据（都不需要示波器）：

1. 换一个**已知存在**的地址读一次作正向对照。目标失败而对照成功 → 地址层/权限层问题；
   两个都失败 → 通路本身（时钟没给、复位没释放、根本没连、位宽不匹配）。
2. 把地址按 4 对齐再试，长度按字给。
3. 软件侧的读数口径不同：Linux/PYNQ 下这类问题常表现为一次 oops/`SIGBUS`，或这一笔根本不返回；
   裸机下看响应码或 CPU 异常向量。**"设了没反应"和"这笔把总线挂住"是两类**，后者走
   `board-bringup.md` §4 第 0 步。
4. 回到设计侧核对映射：重导出之后把两份地址表逐段 diff；
   `validate_bd_design` 通过不代表 `assign_bd_address` 过了（`vivado-project-bd.md` §2 第 1 条）。

## 3. 裸机（standalone / baremetal）侧的规矩

- **写完就读回**，并把读到的值打出来；回显写进去的值，不回显你想写的值。
- 控制字里有"数据 + 选通"这种成对语义时（准静态字配一个 toggle/strobe），**顺序就是全部风险**：
  第一笔只更新数据、选通保持原值；第二笔才翻选通。一次写同时改两者，对端可能读到"新码 + 还没认的
  沿"或"旧码 + 已认的沿"，覆盖白丢，症状是"串口回显成功、屏上没变"。
- **cache 维护的方向与对齐**要按平台查：CPU 写出去给 PL 读，写后要 flush；PL 写进来给 CPU 读，
  读前要 invalidate。对齐按 cache line，长度不足一行的尾部最容易只维护了一半。方向写反的症状是
  "第一次对、第二次旧"；漏了的症状是"半新半旧"或首块/尾块坏。
- 轮询要有界：带超时读数（轮了多少次、什么时候放弃），不要用固定 `sleep` 或循环次数当完成判据。
  `sleep` 用来"造一个脉冲宽度"是另一用途，两者不许混。
- 中断路径：先初始化中断控制器，再使能设备侧，最后清一次挂起状态；顺序错了会一进来就丢。

## 4. 共享内存的提交点

双缓冲/乒乓的显示侧必须按**整帧完整**才换页；数据不全就不换，屏上保持上一帧（"宁缺勿残"）。
完成判据只看搬运器 `idle` 是不够的——在途的读流水、跨时钟域队列里还压着几个字节时换页，症状很具体：
**帧尾几个像素跑到下一帧去了**（右下角少 2 像素这类）。判据要连"队空 + 读地址已发完 + 两级读流水
都空"一起看，并把这条做成一个 bench 用例。

丢一个包/一段数据就整帧不提交时，要有可读回的计数（收齐几帧、丢弃几次），否则"缺包被正确拦下"与
"根本没接数据"在现象上完全一样。

## 5. PYNQ 侧：任何 API 面都在目标上重新导出

不同大版本的签名差别是真的，而且**差别会直接把你打到不存在的名字上**：在本包能查到的 Python
包树里（2.5.1/2.7.0/3.0.1/3.1.2/4.0.0 五棵），IP 字典这个属性**只叫 `ip_dict`**——同一条命令
在每棵树里都能命中 `ip_dict` 于 18～23 个文件，而 `dict_of_ipif` 在五棵树里**一个文件都没有**
（这组数字就是正向对照：它证明扫描看得见这些文件，所以 0 是"真的没有"，不是"扫不到"；
注意 `grep "class MM"` 会误命中 `MMIO`，判"某个名字存不存在"必须加词边界）。
导出面的迁移线（谁在 2.7 被删、谁搬了家）逐条在
`pynq-overlay-development/references/versions-and-apis.md` §2.1；`ip.baseaddr` 同理**在 IP 句柄这一层不存在**——
基址在 `ip.mmio.base_addr`（`MMIO.__init__(self, base_addr, length=4, …)` 里记 `self.base_addr`）。
**但别说成"`baseaddr` 这个词在任何副本里都不存在"**：它在每棵树里都有 21～39 处命中，只是不在
IP 句柄那一层——`metadata/ip_dict_view.py` 里 port 对象的 `dst_port.baseaddr`、`mem_dict_view.py` 的
`subord_port.baseaddr`，以及 IP 驱动 C/VHDL 源码里的 `baseaddr_p`。限定错层次的全称否定，
比不写更容易骗人。

先采集现场事实，再写代码：

```python
import pynq, inspect
print(pynq.__version__)
ol = pynq.Overlay("design_1.bit")        # 参数形态（带不带扩展名）按本机版本试一次
print(sorted(pynq.PL.ip_dict.keys()))     # IP 实例名来自元数据，不是猜
ip = getattr(ol, "<实例名>")   # 名字来自上面打印的 PL.ip_dict
print(type(ip), hex(ip.mmio.base_addr))   # 基址在 ip.mmio 上；
                                          # IP 句柄自己没有 baseaddr（层次见上面那段）
print(inspect.signature(pynq.allocate))
buf = pynq.allocate((8, 512), dtype="u4")
print(buf.dtype, buf.shape, hex(buf.physical_address))
```

**PYNQ 这一层的深度内容在 `pynq-overlay-development` 技能里**（Overlay 生命周期、MMIO 语义、
缓冲区与 DMA、中断、取证）。这里只留与 PS/PL 协同直接相关的、已按上游 v3.1 与 v4.0.0 源码核对过的几条：

- `pynq/buffer.py:138` 是 `allocate(shape, dtype="u4", target=None, **kwargs)`，返回 `PynqBuffer`
  （`np.ndarray` 子类，可直接当数组用）。**默认 dtype 是 `"u4"`（uint32）** —— 字节流/图像要显式
  给 `np.uint8`，否则 `(8,512)` 是 16 KiB 不是 4 KiB。物理地址属性名是 **`physical_address`**
  （`buffer.py:90`），不是 `ip_dict` 里那个 `phys_addr`。
- `MMIO.read(offset=0, length=4, word_order="little")`（`mmio.py:87`）：`length` 只收 1/2/4/8；
  `offset` 是**字节**地址且必须 4 对齐（否则 `MemoryError`）；**`word_order` 只在 `length=8` 时起作用，
  且是"两个 32 位字的先后"，不是字节端序**。`MMIO.write` 在 `__init__` 里按设备能力绑定
  （`mmio.py:70-84`）——所以"扫类定义说它不存在"是错的。
- `DMA` 驱动挂在实例上（`getattr(overlay, 'axi_dma_0')`），通道是 `sendchannel`/`recvchannel`，
  **单次上限不一定等于 `buffer_max_size`**：`axi_dma_micro` 是 `数据位宽 × burst_size`，
  而 `c_sg_length_width` 缺键时驱动退回硬编码 `2^26-1`（`lib/dma.py:630-637`、`:664-666`）；
  另外只有 SDMA 会在超限时 `raise`，SG 会**默默拆成多个描述符**，所以"没报 exceeds maximum"
  在 SG 上不是证据。`transfer(array,
  start=0, nbytes=0)` 里 **`start` 按字节**算且参与对齐检查；cyclic 只在 sendchannel，且 cyclic
  下 `wait()` 直接 `RuntimeError`。细则归 `pynq-overlay-development/references/dma-channels.md`。
- `Interrupt(pinname)` 的 pinname 必须逐字来自 `PL.interrupt_pins`；`wait()` 是**协程、没有 timeout
  形参**（`interrupt.py:72`），超时用 `asyncio.wait_for` 包；重下 overlay 之后该对象明确失效。

存在性一律不能凭静态扫描断言 —— 上面 `MMIO.write` 就是运行时绑定的例子。板端现场采集与签名导出，
用只读命令现采：`python3 -c "import pynq; print(pynq.__version__, pynq.__file__)"`、
`python3 -c "import pynq; print([n for n in dir(pynq) if not n.startswith('_')])"`、
`python3 -c "import pynq; print(pynq.Interrupt.__module__)"`（板端与远程是两个类）、
`cat /proc/interrupts`、`ls /sys/class/uio`、`grep -a Cma /proc/meminfo`。

## 6. Overlay 与位流必须配套

`.bit` 与它的元数据（`.hwh`/`.xsa`/`.tcl`/`.dtbo`）必须同一次导出的同一版；混版会报 `KeyError`、
找不到 IP 实例、地址对不上，或者更糟——加载成功但映射来自上一版。检查方法：整组放在一起并落一次
哈希（`md5sum design_1.bit design_1.hwh > board/fp.txt`），
换位流就整组换、整组重记。

还有一条同族陷阱，与"整组同名"相反方向：**不同目录、同基名的两个 `.dtbo` 会在内核里互相顶掉**。
PYNQ 把叠加按 `.dtbo` 的**基名**登记进
`/sys/kernel/config/device-tree/overlays/<基名>`，每次加载都是先 `remove()` 再 `insert()`
（`pynq-3.1.2`/`pynq-4.0.0` 的 `pl_server/device.py:363-368` 逐字节相同）。所以
`overlays/a/design_1.dtbo` 与 `overlays/b/design_1.dtbo` 共用同一个条目——加载 B 会把 A 的中断/UIO
节点静默摘掉，A 的位流却可能还配在 PL 里。症状是"上一个 overlay 的中断突然不来"，而不是任何报错。
两个 overlay 要想共存，`.dtbo` 基名必须不同（顺带 `.bit` 也各自同名同批最省事）。
判据与非破坏性检查在 `pynq-overlay-development/references/overlay-metadata.md` §1。


重下载位流之后，之前拿到的 Python 对象/句柄可能失效（旧对象还在，但底下的硬件被重置了）；更坏的
形态是 PS 还握着旧句柄时有在途事务（见 `board-bringup.md` §2 那一行）。每次重下载之后重新取实例、
重配寄存器、重挂中断，并把"重下载后不重取对象"当成一个必测用例。运行时加载的 overlay 断电后是否
还在，取决于它有没有被登记成开机重放，与 JTAG/Flash 那两条规则都不同。

还有一条只在 Zynq 上才有的失效方式：**改了 FCLK 频率或重下 BD 之后，`ps7_init` 与已链接 ELF 里
关于时钟、DDR、地址段的假设一起失效**。症状常常是"首帧坏/偶发一拍错值/换个 FCLK 全红"，而 PL 侧
逻辑一行没动。换 FCLK、换 BD、换 bit 之后的回归要重跑，不要沿用上一版的"通过"结论。

## 7. 三层结论：这一节不再重讲一遍

分层（调用没报错 / 元数据里有 / 硬件真做了）的**真源在本包（Vivado 侧）`SKILL.md` §1**——
那一节是"九条硬规则：每条把一句结论与能支撑它的那条读数配在一起"（第 9 条给"读不到就写 `NOT RUN`"，
第 3 条给"只认实现之后那一次"），**它不是一张表，别按表头去找**；PS↔PL 运行时的展开版在
`pynq-overlay-development` 的 `SKILL.md`「十一条硬规则」与
`pynq-overlay-development/references/debug-triage.md` §1。这里只留一条 Zynq 专属的后果：

- `DMA.transfer()` 不抛异常通常只到"描述符入队"；`ip_dict` 里有这个地址只到"元数据解析到了"。
  这两条**都不算**"位流是这一版"或"那一路时钟活着"——后者要设计里预留的读回口（§6 与 `board-bringup.md` §1）。

## 8. 现象分诊：位置偏 ≠ 颜色偏

**位置/时间偏**按偏的形状分三门（每行只给一节，别按范围翻）：错列/错行/慢一帧 →
`rtl-pipeline-cdc.md` §3（用探针实测深度）；整帧偏、画面滚动 → 同页 §6（消隐预算）；
撕裂、偶发一拍错位 → `verification.md` §6（扫相位的 CDC bench）。
"这一帧到底在哪一刻交给硬件"是**本页 §4**（共享内存的提交点），不在那三页；
"带宽够不够"是运行时包 `pynq-overlay-development/references/debug-triage.md` §4。

**数据表示不对**（整体偏色、红蓝互换、16 位成对调、缺一个通道、发灰或削顶、渐变出台阶）→
按这四条依次查，都在数据表示层，不在几何层。**"DMA 搬回来的长度对、内容却成对调/整体错位"
也算这一类**——不要因为它没有"颜色"字样就绕开这张表：

| 嫌疑 | 一眼判据 |
|---|---|
| 字节序 / byte lane / `word_order` | 同一像素换个字节序读，R 与 B 是否互换；读回一个已知 pattern 看字节落位 |
| RGB↔BGR 或 YUV 4:2:2 的奇偶像素打包 | 只有一半像素的色度对、或水平方向色度错位 |
| limited(16..235) 与 full(0..255) range | 黑不黑、白不白，灰阶被压缩或削顶 |
| 位宽截尾（8/10 bit、拼接里漏位） | 低位消失、渐变出现规则台阶 |

**`word_order` 不在这张表的射程里，别拿它修颜色**：它是 `MMIO.read` 在 `length=8` 时对**两个 32 位字
先后顺序**的参数（口径见 `pynq-overlay-development/references/mmio-registers.md` §2 第 3 条），
管不到帧缓冲里像素的字节序——帧缓冲是 `np.array(buf)` 读出来的，那个参数根本不在路径上。
把它当端序开关试，结果是"修出第二重错位"。

第四条（位宽截尾/拼接漏位）改完之后怎么验不在本页：那是**设计侧的向量比对**，
去 `verification.md` §2（参考模型要与 RTL 不同源）与 §4（判据要能红——
故意把拼接里的一位改成常量，bench 必须因此红）。只做"看着顺眼了"不算改好。

几何类症状也可能来自 stride/pitch 与实际行宽不匹配、行缓冲深度吸收不了两侧速率差；带宽类症状要把
所有竞争者列全（显示扫描、PL 写入、PL 读出、DDR 刷新、其他 master、PS 外设）再算总需求与上限之比，
并注明口径（突发效率按长度非线性，短 burst 会明显吃掉上限）。没量过就别给数字，把口径列出来即可。
