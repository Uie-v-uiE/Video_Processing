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
这一层在设计侧就查得完。读数不是一次取的，别当成同一份 BD——**一共三份**，各自的形状是：
第 1 步"只点了完全没连的 `m_axi_sg_aclk`"与第 3 步的 `TYPE`/`CONFIG.FREQ_HZ` 那几对读数，来自
**三端口三连线、只漏 sg 那一路**的那份（本机那一次 `41-758` 的名单里只有 `m_axi_sg_aclk` 一个脚）；
把时钟引脚**两路都不连**的是另一份，同一条 `validate_bd_design` 在那一份上点的是
`m_axi_sg_aclk` **和** `m_axi_s2mm_aclk` 两个脚——所以"点几个脚"本身就是"哪份 BD"的指纹，
拿这份的名单去解释那份的现象必然错。第 2 步里 `axi_gpio` 与 `clk_wiz` 两处对照又是第三份
（只放了这三个 IP、一条线都没连）。引用上面任何一条读数时，连"哪一份"一起说。

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
  读前要 invalidate。对齐按 cache line，长度不足一行的尾部最容易只维护了一半。
  **下面两句症状是这一族的机理叙事，本机没有板、没有一条读数支撑**（要它在板上成为读数：
  同一份数据跑"维护对/反/漏"三臂，每臂都读回转存 + 记帧号/序号，别只看完成的返回值）——
  方向写反的症状是"第一次对、第二次旧"；漏了的症状是"半新半旧"或首块/尾块坏。
  cache line 到底是 32 还是 64 字节也属同一层：读自己那颗 ACP/PL 通道的平台手册或上板测，别抄本页。
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
（`grep -rl ip_dict <树>/pynq | wc -l`，**口径是 `<树>/pynq` 这个子树 + 子串匹配 + 计文件数**）在每棵树里都能命中
`ip_dict` 于 **19/18/22/23/22** 个文件；换三个口径里的任何一个，数就变：放宽到整棵树（含 `boards/`、
`tests/`、非 `.py` 文件）是 **22/24/29/30/26**；只走 `*.py` 且用词边界 `\bip_dict\b` 是
**19/18/21/21/19**（这三组都是本机同一批树上量出来的，差别全在口径，不在代码）——
**报数之前先把命令与口径一起写出来**，否则同一件事在两页里会写成两个"都对"的数（本页就吃过这一次亏）。
而 `dict_of_ipif` 在五棵树里**一个文件都没有**
（这组数字就是正向对照：它证明扫描看得见这些文件，所以 0 是"真的没有"，不是"扫不到"；
注意 `grep "class MM"` 会误命中 `MMIO`，判"某个名字存不存在"必须加词边界）。
导出面的迁移线（谁在 2.7 被删、谁搬了家）逐条在
`pynq-overlay-development/references/versions-and-apis.md` §2.1；`ip.baseaddr` 同理**在 IP 句柄这一层不存在**——
基址在 `ip.mmio.base_addr`（`MMIO.__init__(self, base_addr, length=4, …)` 里记 `self.base_addr`）。
**但别说成"`baseaddr` 这个词在任何副本里都不存在"**：它在每棵树里都有命中，本机按
`grep -rn baseaddr <树>/pynq | wc -l` 逐棵数过：2.5.1=**21**、2.7.0=**27**、3.0.1=**40**、
3.1.2=**43**、4.0.0=**26**（早先这里写的"21～39"没盖住 3.0.1 与 3.1.2 这两棵）。
**但这几行命中不是同一个东西，逐棵拆开看才知道该引哪一条**（本机按文件与语言过滤过）：
真正的 `baseaddr` 只在 `metadata/` 那两个视图里：3.1.2 `metadata/ip_dict_view.py:184` 是
`] = dst_port.baseaddr`，3.1.2 `metadata/mem_dict_view.py:63` 是 `subord_port.baseaddr`，
**而 `metadata/` 这个目录 2.5.1 与 2.7.0 根本没有**（3.0.1/3.1.2/4.0.0 才有），**但"才有"不等于"里面都有"：按词边界数 `grep -anrw baseaddr <树>/pynq/metadata` 是 0/0/2/2/0——`metadata/` 在 4.0.0 也在，只是里面一行 `baseaddr` 都没有，属性族只在 3.0.1/3.1.2**，
所以那两版的 21/27 行里**没有 `X.baseaddr` 这种属性访问**这句成立，但**"没有 `baseaddr` 这个词"不成立**：
按词边界数（`grep -anrw baseaddr <树>/pynq | wc -l`）是 **2.5.1=4、2.7.0=11、3.0.1=13、3.1.2=13、4.0.0=6**，
2.5.1/2.7.0 那些行出自 **IP 驱动 C 源码里的注释**（`grep -anrw baseaddr <树>/pynq` 的第一条就是）——
**把"属性族不在那两版"写成"这个词不在那两版"正是本段末尾要警告的那种限定错层次的全称否定，先前这里自己犯了**；剩下的命中主要是三样杂物（**还有第四样先前没列**：`lib/_pynq/embeddedsw/lib/bsp/standalone/src/common/intr/xinterrupt_wrap.c` 有 11 行 `baseaddress`，而这文件只在 3.0.1/3.1.2/4.0.0 存在，2.5.1/2.7.0 没有它）：IP 驱动的 C 源码/头里的
`baseaddr_p`（`*.c`/`*.h`；那条 `grep -rn VHDL *.vhd*` 的 **0 是空扫**——五棵树里**根本没有 `.vhd` 文件**
（`find <树>/pynq -name '*.vhd*' | wc -l` = 0），所以它既不能写成"VHDL 里也没有"，也别写成"C/VHDL"）、
`mmio.py:15-23`（**裸号按本包规矩是 3.0.1/3.1.2/4.0.0 的**：那三版都在 `:15` 起，
**而 2.5.1 的同一段在 `mmio.py:41` 起、2.7.0 在 `:42` 起**——`grep -anw baseaddress <树>/pynq/mmio.py`
第一条就是那个 `def __init__(self, baseaddress, device)`）与 `pl_server/remote_device.py:609-619`
（**这个文件只有 3.1.2/4.0.0 有**：2.5.1/2.7.0/3.0.1 三棵树里它不存在，`test -f` 直接失败）里的
**`baseaddress`**（多一个 `e`，
是被子串匹配捞进来的）、以及 `libxil.a` 这类二进制留下的 `Binary file ... matches` 占位行
（2.7.0/3.0.1/3.1.2 各 4 行、4.0.0 1 行、2.5.1 0 行——**它们各占一行计数**）。
⇒ 结论没变、但理由要按层次说：`ip.baseaddr` **在 IP 句柄这一层不存在**（基址在
`ip.mmio.base_addr`），"全树有命中"这件事不构成反证，因为命中的是别的对象、别的拼写、和二进制占位行。
限定错层次的全称否定，比不写更容易骗人。

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

- **4.0.0** `pynq/buffer.py:138` 是 `allocate(shape, dtype="u4", target=None, **kwargs)`（**2.5.1 的同一条在 `buffer.py:151`**；`dtype=` 后面的引号风格也变了，`physical_address` 那个 @property 在 4.0.0 是 `:90`、2.5.1 是 `:100`——裸号按本包规矩取 4.0.0，搬版本前先 `grep -n "def allocate"` 各树现取），**板端**返回 `PynqBuffer`
  （`np.ndarray` 子类，可直接当数组用）；**远程 target 走的不是这个类**——`RemoteDevice.allocate`
  造的是 `RemoteBuffer`（4.0.0 `pl_server/remote_device.py:498` → 类在 `:1058`；3.1.2 是
  `:474` → `:734`，**两份文件行数差很多，别把行号搬版本**：3.1.2 那份只有 917 行），它的 `freebuffer()`
  是一次 gRPC 调用而不是本地 unmap，判"我拿到的是哪一个"用 `type(buf).__name__` 与
  `buf.__module__`，别看有没有 `physical_address`（两边都有才奇怪）。
  细则与坑在 `pynq-overlay-development/references/buffers-and-cache.md` §2 那张两版对照表。**默认 dtype 是 `"u4"`（uint32）** —— 字节流/图像要显式
  给 `np.uint8`，否则 `(8,512)` 是 16 KiB 不是 4 KiB。物理地址属性名是 **`physical_address`**
  （`buffer.py:90`），不是 `ip_dict` 里那个 `phys_addr`。
- `MMIO.read(offset=0, length=4, word_order="little")`（`mmio.py:87`）：`length` 只收 1/2/4/8；
  `offset` 是**字节**地址且必须 4 对齐（否则 `MemoryError`）；**`word_order` 只在 `length=8` 时起作用，
  且是"两个 32 位字的先后"，不是字节端序**。`MMIO.write` 在 `__init__` 里按设备能力绑定
  （`mmio.py:70-85`，那条 `raise ValueError("Device does not have capabilities for MMIO")` 在 `:85`，
  **不在 70-84 这个区间里**）——所以"扫类定义说它不存在"是错的。
- `DMA` 驱动挂在实例上（`getattr(overlay, 'axi_dma_0')`），通道是 `sendchannel`/`recvchannel`，
  **单次上限不一定等于 `buffer_max_size`**：`axi_dma_micro` 是 `数据位宽 × burst_size`，
  而 `c_sg_length_width` 缺键时驱动退回的是**由一个命名常量算出来的 `2^26-1`**，不是字面量：
  `self.buffer_max_size = 1 << MAX_C_SG_LENGTH_WIDTH`（`lib/dma.py:635`）随后 `-= 1`（`:637`），
  而 `MAX_C_SG_LENGTH_WIDTH = 26` 就定义在同一份文件的 `:11`（3.1.2）；`:630-633` 是有键时
  按 IP 参数走的那一支。**要引用这个数就连 `:11` 一起引**，换版本时先看那一行还是不是 26
  （`axi_dma_micro` 在 `:664-667`）；**注意 `axi_dma_micro` 不是源码里的标识符**
  （五棵树 `grep -rIn axi_dma_micro` 全 0 命中，2.5.1 连 `c_micro_dma` 都没有；
  真读的是参数 `c_micro_dma` 与 `self._micro` 那一族，4.0.0 各 2/5 处，正向对照就是这两个数），
  本页用它只是给"micro DMA 这一档"起的名；
  另外只有 SDMA 会在超限时 `raise`（逐字是 `ValueError("Transfer size is {} bytes, which exceeds
  the maximum DMA buffer size {}.")`，4.0.0 `lib/dma.py:141-145`；**没有"exceeds maximum"这种短串**，
  按它 grep 五棵树 0 命中），SG 会**默默拆成多个描述符**，所以"没看到那句超限"
  在 SG 上不是证据。`transfer(array,
  start=0, nbytes=0)` 里 **`start` 按字节**算且参与对齐检查；cyclic 只在 sendchannel，且 cyclic
  下 `wait()` 直接 `RuntimeError`。细则归 `pynq-overlay-development/references/dma-channels.md`。
- `Interrupt(pinname)` 的 pinname 必须逐字来自 `PL.interrupt_pins`；`wait()` 是**协程、没有 timeout
  形参**（`interrupt.py:72`，本机 3.0.1/3.1.2/4.0.0 三棵树同一行都是 `async def wait(self):`），
  超时用 `asyncio.wait_for` 包；**2.7.0 上它是 `:101` 的协程、2.5.1 上 `:103` 是普通
  `def wait(self)`**——不是协程就没有 `await`/`wait_for` 可用。这一条的报错形状本机是在桩上量的
  （主机 Python 3.12 + `asyncio`，不是板上的 pynq 运行时）：普通 `def wait()` 交给
  `asyncio.wait_for(o.wait(), 1)` 得到 `TypeError: object int can't be used in 'await' expression`
  （消息里那个类型名就是 `wait()` 的返回类型，2.5.1 真返回什么本机没测），同一句喂给
  `async def wait()` 正常返回。**别把 3.x 的包法抄到 2.5.1 上**。重下 overlay 之后旧对象的正确说法是**"等待的结果未定义"**，
  不是"会报错"：类 docstring 原文 "this object is invalidated and waiting results in undefined
  behaviour"（4.0.0 `interrupt.py:48-50`），而 `:78-80` 的
  `RuntimeError("Interrupt invalidated by Overlay change")` **只在 `self.parent()` 已经是 `None` 时**才抛
  ——父对象还被别处攥着时它不抛，等到什么都有可能。所以修法是**重下之后重新构造对象**，不是加 `try`
  （与 `pynq-overlay-development/references/interrupts.md` §3 同一口径）。

存在性一律不能凭静态扫描断言 —— 上面 `MMIO.write` 就是运行时绑定的例子。板端现场采集与签名导出，
用只读命令现采：`python3 -c "import pynq; print(pynq.__version__, pynq.__file__)"`、
`python3 -c "import pynq; print([n for n in dir(pynq) if not n.startswith('_')])"`、
`python3 -c "import pynq; print(pynq.Interrupt.__module__)"`（板端与远程是两个类）、
`cat /proc/interrupts`、`ls /sys/class/uio`、`grep -a Cma /proc/meminfo`。

## 6. Overlay 与位流必须配套

`.bit` 与它的元数据（`.hwh`/`.xsa`/`.tcl`/`.dtbo`）必须同一次导出的同一版；混版**不一定报"版本不匹配"**，
而是按你走哪条访问口分三种错（先分流再动手，否则三条都会把你指向"重新导出"）：
`getattr(overlay, 名字)` 报 `AttributeError("Could not find IP or hierarchy <名字> in overlay")`、
位流根本不在板上时同一句报 `RuntimeError("Overlay not currently loaded")`、
只有你自己写 `ip_dict[名字]` 才是 `KeyError`——三条的出处与逐字文本在
`pynq-overlay-development/references/overlay-metadata.md` §3.1。或者更糟——加载成功但映射来自上一版。
检查方法：整组放在一起并落一次
哈希（`md5sum design_1.bit design_1.hwh > board/fp.txt`），
换位流就整组换、整组重记。

还有一条同族陷阱，与"整组同名"相反方向：**不同目录、同基名的两个 `.dtbo` 会在内核里互相顶掉**。
PYNQ 把叠加按 `.dtbo` 的**基名**登记进
`/sys/kernel/config/device-tree/overlays/<基名>`，每次加载都是先 `remove()` 再 `insert()`
（`pynq-3.1.2`/`pynq-4.0.0` 的 `pl_server/device.py:363-368` 逐字节相同）。所以
`overlays/a/design_1.dtbo` 与 `overlays/b/design_1.dtbo` 共用同一个条目——加载 B 会把 A 的中断/UIO
节点摘掉，A 的位流却可能还配在 PL 里。**"这一路不会报错"是错的**：`insert()` 写完自己会做两次检查
（读回 `dtbo` 比对 + 问 `status`），任一不过就抛
`RuntimeError("Device tree {} cannot be applied")`（3.x `devicetree.py:109-120`，2.5.1 是
`subprocess` 那套、比较式在 `:115-118`）；`remove()` 是**没有 `try` 的裸 `os.rmdir`**
（`:122-127`），目录还被内核占着时这里就抛 `OSError`。
**"摘掉之后上一个 overlay 的中断突然不来"这一句是本包的机理推断、没有板端读数**（没有板子），
要它在板上成为读数：加载 B 之前后各读一次 `/proc/interrupts` 与 `/sys/class/uio`，把两次名单放在一起。
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

- `DMA.transfer()` 不抛异常**不等于搬完了**，而且**两条通道的"不抛"含义不同**：SDMA 那一支
  `transfer()` 直接把 `0x18`/`0x1C`/`0x28` 写进寄存器就返回（4.0.0 `lib/dma.py:156-162`，
  **没有描述符可言**）；SG 那一支 `transfer()` 末尾就调了 `self.start()`（`:446`）并写 TAILDESC
  （`:461-468`，注释原文 "triggers the descriptor fetches"）——**所以 SG 不透明知"引擎有没有开始搬"，
  只说明请求已提交**。`ip_dict` 里有这个地址只到"元数据解析到了"。
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
