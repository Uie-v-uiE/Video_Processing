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

```python
dma = getattr(ol, "axi_dma_0")    # 这一段假定 ol 已经存在（它是 §2 加载之后才有的对象）
ch = dma.sendchannel
print("sendchannel:", "None(这一侧硬件没使能)" if ch is None
    else ("中断已接" if ch._interrupt else "通道在、中断对象是 None"))
print(sorted(dma.description.get("interrupts", {})))    # 期望 ['mm2s_introut','s2mm_introut']；[] = .hwh 里就没声明
```


## 1. 导出与拷贝：整组一起走

Vivado 里 `Export Hardware`（含 bitstream）→ 得到 `.bit` + `.hwh`（或 `.xsa`）。把它们
**同一批、同名**拷到板上同一个目录，`.dtbo` 也在同一目录。默认查找规则与"缺 `.dtbo` 到底会不会报错"
由 `overlay-metadata.md` §1 那一页拥有（含 `devicetree.py` / `bitstream.py` 的出处），这里不重讲；
`print(ol.dtbo)` 那一句也**不在这一步做**——`ol` 要到第 2 步才存在。这一步能当场做的是两条 shell 读数：

```bash
ls -l --time-style=full-iso /home/xilinx/jupyter_notebooks/myip/    # .bit/.hwh/.dtbo 是否同一批
ls /sys/kernel/config/device-tree/overlays/    # 上一次加载留下的叠加条目
```

第二条的期望值是**没有**你这一版的名字（第一次加载前它不可能在）；如果它在，说明前一个 overlay 还挂在
内核树上，`overlay-metadata.md` §1 讲了同名 `.dtbo` 会互相顶掉这件事，先处理干净再往下走。

时间戳不同批 = 后面所有地址读数都不可信。通过标准：`.bit` 与元数据同批、同目录、文件名一致。


## 2. 加载后第一件只读的事：认身份

```python
from pynq import Overlay, PL
ol = Overlay("/home/xilinx/jupyter_notebooks/myip/design_1.bit")
print("dtbo =", ol.dtbo)    # None = 连文件都没找到；非 None 只证明路径被算出来，
    # 不证明内核装载了它——那要看 configfs 的 status
print(sorted(PL.ip_dict))    # 实例名从这里复制，不要手拼
print({k: hex(PL.ip_dict[k]["phys_addr"]) for k in PL.ip_dict})
print(dict(PL.interrupt_pins))    # 空 = 中断没接进来，别再去试名字
```

通过标准：目标 IP 在表里、`phys_addr` 与 Vivado Address Editor 里那一行一致；
`.dtbo` 非 `None` 时，`cat /sys/kernel/config/device-tree/overlays/<dtbo 基名>/status` 读到 `applied`
（这一条的出处与同名顶掉的后果在 `overlay-metadata.md` §1）。


## 3. 寄存器通路：破坏性图案 + 读回

```python
from pynq import MMIO, PL    # PL 是取 ip_dict 的那个入口，别只导入 MMIO
base = PL.ip_dict["my_ip_0"]["phys_addr"]
mm = MMIO(base, 0x1000)
SCRATCH = 0x08    # 第 0 步埋的那个"无副作用回写"寄存器

# probe32 的唯一定义在 mmio-registers.md §4（写三式 + 读回 + finally 复原）；
# 那一页是规范出处，这里不重抄一遍——重抄就会漂移。用之前把那个函数贴进同一个 cell/脚本。
probe32(mm, SCRATCH, "scratch")
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

读到期望值 = 板上就是这一版、AXI-Lite 通；**它不证明 PL 的数据通路有时钟**（那要看 §0 那个
按时钟域各埋一个的自由运行计数器）。读不到就不要继续：**现在停下来比
后面给一份错结论便宜得多**。

## 5. 数据通路：先单字节图案，再真实数据

下面这段是 `dma-channels.md` §3 那节**规范骨架的镜像**（这里多打印每通道的完成读数，少一步
参考比对的细节）。两边的等待方式必须一致：改一处就改两处，否则本页的"通过标准"会指向一个
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
mask = np.ones(n, dtype=bool)    # 只比对 PL 真正改写的那些下标；透传这一版是全部
checks = int(mask.sum())    # 这一格必须能算出 0：形状/dtype 不对或 mask 全空
print("checks=%d mismatches=%d" % (checks, int(((got != ref) & mask).sum())))
```

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
| 2 | `print(sorted(PL.ip_dict))` 把名字**复制**过去；再 `print(PL.ip_dict[name]["type"])` 与 `print(type(getattr(ol, name)).__name__)` 成对打印——后者是 `DefaultIP` 就是驱动没绑上（VLNV 对不上），**别拿 `MODTYPE` 当版本判据**：在两棵新版树里都还读到它（3.1.2 `pl_server/hwh_parser.py:163`、4.0.0 `:170` 的 `mod.get("MODTYPE")`），而按 VLNV 绑驱动从 2.5.1 就是这样（`for vlnv in cls.bindto`：2.5.1 `overlay.py:527-528`、3.1.2 `:561`/`:569`、4.0.0 `:558`/`:566`）——两层的逐行归属由 `overlay-metadata.md` §2 第 2 条拥有，这里不重抄 | 别按记忆猜实例名 |
| 3 | 先读一个**必然有值**的偏移（第 0 步的 `0x00` 版本寄存器）确认通路，再谈图案；单位（字节 vs 字）与 4 对齐照 `mmio-registers.md` §2 的式子算一遍并打印中间值 | 别反复重试同一笔写；别把 `0xFFFFFFFF` 写进没核实过的偏移 |
| 4 | 把读到的值和期望值**两个都打印**（只说"对不上"不算读数）；再核 `.bit` 的 md5 与这次构建的那份是否同一个 | 别用文件哈希代替身份——哈希对得上只证明文件没换，不证明 PL 里配的是它 |
| 5 | 先 `from pynq import Clocks`（本页前面没导入过它），再 `print([Clocks.fclk0_mhz, Clocks.fclk1_mhz, Clocks.fclk2_mhz, Clocks.fclk3_mhz])`（2.7.0/3.0.1/3.1.2 上不要用 `Clocks.get_pl_clk`，那里返回 `None`；4.0.0 才修好），再读自由运行计数器两次取差；然后按 `dma-channels.md` §2 把四个状态口逐个打印 | 别只等一侧的 `wait()`；别用 `sleep()` 代替完成判定 |
| 6 | 打印 `checks=` 并确认它非 0；再把参考实现的一条算式与 RTL 的对照写进报告（两条独立来源） | 别拿"看起来对"的截图当证据 |

