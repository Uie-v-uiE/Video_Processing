# MMIO 与寄存器：语义、契约、身份

## 1. 构造，与 `write` 在构造期绑定的三条路

```python
from pynq import MMIO
mm = MMIO(base_addr, length=4, device=None, **kwargs)    # mmio.py:42（3.1.2/4.0.0；
#  2.5.1 的签名在 :67，是 def __init__(self, base_addr, length=4, debug=False, device=None)——没有 **kwargs；
#  2.7.0 在 :69）
```

`MMIO` 把 `self.array` 建成 32 位字数组，或直接拿到映射对象；**`self.write` 绑到哪个实现，
是 `__init__` 里按设备能力现绑的**（`mmio.py:70-85`——**注意那条 `raise` 在 `:85`，不在 70-84 里**）。
注意它是 `if / elif / elif`，所以能力同时
具备时**优先级就是代码顺序**：

| 顺序 | 能力判据 | 绑定 | `self.array` 从哪来 |
|---|---|---|---|
| ① | `has_capability("MEMORY_MAPPED")` | `self.write = self.write_mm` | `self.device.mmap(base_addr, length)` |
| ② | `elif has_capability("REGISTER_RW")` | `self.write = self.write_reg` | `tnp.ndarray(shape=(length//4,), dtype="u4", hook=_AccessHook(...))` |
| ③ | `elif has_capability("REMOTE")` | `self.read = map.read`、`self.write = map.write` | `map.array`（map 来自 `device.mmap`） |
| — | 都不满足 | `raise ValueError("Device does not have capabilities for MMIO")` | — |

**这张表只成立在 3.1.2/4.0.0**（两版这段逐字符相同）。**3.0.1 里没有 ③ 这一支**：
它的 `mmio.py` 是 `:70` MEMORY_MAPPED、`:74` REGISTER_RW、`:79` `else:`、`:80` 那条 `raise`，
整个文件 `has_capability("REMOTE")` **0 次命中**（同一次 grep 在前两版各命中 1 次，作正向对照）——
所以在 3.0.1 上"远程模式走 ③"这条路不存在。2.5.1/2.7.0 的能力块起点也不同
（`mmio.py:92` 与 `:97`）。**顺带一条扫描写法上的坑，本机自己就踩了**：那两版里这些能力名是用
**单引号**写的（`has_capability('MEMORY_MAPPED')`），照 4.0.0 的双引号写法去 grep，2.x 会整片 0 命中——
那不是"这一族不在"，是查询写法把射程收窄了；判"某版有没有"要两种引号都试一遍或按 `has_capability` 前缀数。

三条后果，都能在本机上指出依据：

1. 用 `dir(MMIO)` / 扫类定义判断"这台设备写寄存器走哪条路"是判不出来的——要问实例：
   `print(mm.write)` 打出来的函数名就是答案（绑的是 `write_mm` 还是 `write_reg`）。
2. 只有 ③ 会把 `self.read` 也换掉；①② 里 `self.read = self.read` 是自赋值（源码就这么写的），
   读路径仍是 `MMIO.read` 那个实现。别假设"远程模式下 read 的截断行为和本地一样"。
3. ②的数组长度是 `length // 4`，所以 `MMIO(base, 4)` 只有一个字：`array[1]` 越界。想按字扫一段
   寄存器，`length` 要给够（`length` 是**字节**数）。

`ValueError("Device does not have capabilities for MMIO")` 这一句在源码里就一处，看到它别去查
寄存器地址——查的是 `device` 与它的能力位（板端 `EmbeddedDevice` 与远程 `RemoteDevice` 能力不同）。

## 2. `read(offset=0, length=4, word_order="little")` 的四条硬事实

源码 `mmio.py:87-133`，3.1 与 4.0.0 一致：

1. `length` 只接受 **1/2/4/8**，其它值 `ValueError("MMIO currently only supports 1, 2, 4 and
   8-byte reads.")`。
2. `offset` 必须是 **4 的倍数**，否则 `MemoryError("Unaligned read: offset must be multiple of 4.")`。
   也就是说：offset 是**字节**地址偏移（内部 `idx = offset >> 2`），想读第 3 个字要写 `12` 不是 `3`。
3. `word_order` **只在 `length == 8` 时生效**，而且它决定的是"两个 32 位字的先后"，源码 docstring
   明写这不是字节端序：`little` = `[off+4..off+7]` 在高、`[off..off+3]` 在低；`big` 相反。
   把它当端序开关去修"数值怪"，会修出第二重错位。
   顺带两条越界/取值坑：`length=8` 时它会读 `array[idx]` 与 `array[idx+1]`，**`offset` 落在最后
   一个字上会 `IndexError`**（`length` 参数默认是 4，所以 `read(off, 8)` 必须显式给第二个参数，
   写成 `read(offset=off, length=8)` 更清楚）；`word_order` 传了非 `big/little` 的字符串会在
   `length=8` 时 `ValueError("MMIO only supports big and little endian.")`。
4. 小于 8 字节时返回值是 `lsb & ((2**(8*length)) - 1)` —— 高位截断，不做符号扩展。读一个被
   设计成"有符号"的 8/16 位字段要自己 `np.int8(val)` / 手动扩符号。

返回值类型：docstring 写着 `Returns list`，但代码路径返回的是 **int**（`return lsb & mask`、
`return (… << 32) + lsb`）。这是 docstring 过期，不是版本差别——按 int 用。

`write_reg/write_mm(offset, data)` 同样按字对齐；`register_map` 那层的 `offset` 也还是字节偏移。

## 3. 三条访问路径的**真实名字**（这里最容易写出根本不存在的 API）

```python
from pynq import Overlay
ol = Overlay("design_1.bit")   # 本页后面的 ol、ip、regs 都从这个对象往下取
ip = ol.my_ip_0    # 或 getattr(ol, 'my_ip_0')

ip.mmio.array[0]    # 字索引（第 0 个字）。注意：是 ip.mmio.array
v = ip.read(0x00)    # 字节偏移，整字读；DefaultIP.read(offset=0)
ip.write(0x00, 0x11)    # 字节偏移，整字写；DefaultIP.write(offset, value)
ip.mmio.read(0x04, 4)    # 显式 MMIO，length 必填语义同 §2
ip.register_map.ctrl.write(0x11)    # 名字来自 .hwh/.xsa 的元数据
```

- **`ip.array[i]` 不存在。** `DefaultIP.__init__` 只建了 `self.mmio`（4.0.0 `overlay.py:695-697`、3.1.2 `overlay.py:698-700`），
   它自己没有 `array`，也没有把属性转发给 mmio 的 `__getattr__`（`overlay.py` 里的 `__getattr__`
   挂在 `Overlay`（4.0.0 `:364`、3.1.2 `:363`）和 `_IPMap`（4.0.0 `:793`、3.1.2 `:796`）上，不是挂在 `DefaultIP` 上）。所以在板上写
   `ip.array[0]` 得到的是 `AttributeError`——这条**不是**"设计没做这个寄存器"，是名字写错了，
   两者要分开（见 `debug-triage.md` §2 树 B）。
- `DefaultIP` 自带的 `read/write` 是**整字**、按**字节偏移**的便捷口（4.0.0 `overlay.py:758` 与 `:769`；3.1.2 同两个句子在 `overlay.py:761` 与 `:772`，
   内部直接 `self.mmio.read(offset)` / `self.mmio.write(offset, value)`）。它不接受 `length`，
   所以 8 字节读、1/2 字节读都得回到 `ip.mmio.read(...)`。
- 字索引 vs 字节偏移混用是"读回值看着像隔壁寄存器"的头号来源：`array[i]` 的 `i` 要乘 4 才是
   `read()` 的 offset。
- **`register_map` 没有 `keys()`。** 它是 `RegisterMap.create_subclass(...)` 现造的子类，
   每个寄存器是一个 `property`，
   列名字有两条路，但**它们不是独立的备份**——两条都靠同一份元数据：

    ```python
    regs = ol.ip_dict['my_ip_0']['registers']    # {名字: {address_offset, size, access, fields}}
    for n, r in regs.items():
        print(n, hex(r['address_offset']), r.get('access'), list(r.get('fields', {})))
   ```

   `dir(ip.register_map)` 只有在 `register_map` 能构造出来时才可用，而它构造失败的标志正是
   `AttributeError("register_map only available if the .hwh is provided")`——同一种情况下
   `ip_dict[name]['registers']` 也是空的。所以**"元数据没跟上"时这两扇门一起关**：
   届时唯一还能读的东西是设计侧那份 `.hwh/.xsa` 文件本身（用文本方式打开它找 `PORT`/`address_offset`），
   不是任何 Python 口。别在两条都失败之后继续找第三个 Python 口——那说明缺的东西不在运行时。

- 整字写 vs 位段写：`register_map.<reg>.write(v)` 是整字，`.<reg>.<field>.write(v)` 走
   read-modify-write。带 RO 位（`ap_done`/`ap_idle`）的控制寄存器用 RMW 会把读到的状态位写回去，
   行为古怪；启动类寄存器一律整字写。
- `ip.register_map` 本身可能根本拿不到：4.0.0 `overlay.py:735-745`、3.1.2 `overlay.py:738-747`，当元数据里没有 `registers` 时它抛
   `AttributeError("register_map only available if the .hwh is provided")`。这句话是**元数据没跟上**
   的读数，不是 RTL 的读数 → `overlay-metadata.md` §2。

## 4. 写了没反应：先分清"没生效"和"没返回"

- **没返回**：PL 无时钟、被复位、或该地址段上没有从设备时，AXI-Lite 这笔写可能永远等不到
   `BRESP`；GP 口没有超时机制，于是 CPU 卡在这一行（整机僵住/看门狗复位）。*（"GP 无超时"是
   UG585 口径，本包不引用手册；现象侧的判据见下。）*
   所以分诊第一步是**先读一次探活**：能读到东西说明互联通路活着。时钟那一格有现成读数，
   在 `debug-triage.md` §2 树 A 第 1 条（`Clocks.fclk0_mhz`…`fclk3_mhz`，含它的适用边界；
   3.1 上不要用 `Clocks.get_pl_clk`，那里返回 `None`）。
   裸机/脚本侧给轮询加有界超时。
- **没生效**：写进去了但没人用（被常量传播裁掉、连出去没接、宽度截断）、位序/极性反了
   （`1=关` 这种反相位；标志塞低字节而文档写 `[8]/[9]`）、或被更高优先级的来源压制
   （模式锁、拟合开关这类"绝对优先"的门控）。这一类的判据是"回读 + 看消费者"，
   不是"再写一次试试"。

```python
def probe32(mm, off, name="", restore=True):
    """写-回读三式。off 必须是**你确认过没有副作用**的位置（暂存寄存器那一类）。"""
    orig = mm.read(off)    # 先记下原值
    try:
        for pat in (0x00000000, 0xA5A5A5A5, 0xFFFFFFFF):
            mm.write(off, pat)
            got = mm.read(off)
            ok = "OK" if got == pat else "<- 不等于"
            print(f"{name} off=0x{off:03x} 写 0x{pat:08x} 读回 0x{got:08x} {ok}")
    finally:
        if restore:
            mm.write(off, orig)    # 不复原就是往 PL 里留了一个没人知道的值
```

**不知道这个偏移是什么的时候，先只做读探针**：`read()` 三遍（同一偏移读三次打印出来），
值稳定且不是恒 0/恒 F，才谈得上"这里有个从设备"；写探针要等确认过位段是暂存/无副作用之后再做。
把 `0xFFFFFFFF` 写进一个未核实的偏移，可能正好按下了复位极、使能反相位或某个模式字，
症状是"之后怎么都不对"，而你已经把现场改坏了——这是制造故障不是采集证据。

**恒 0 与恒 F 都不算通过**（不存在的从设备也常返回 0），只有"写进去的值读得回来、且换个图案还读得回来"
才算这条通路可用。RO 位读回与写入不同是设计意图，要在报告里写明哪个字段允许不等。


上面这套 `probe32` 是**写-回读比较**，天生只适用于可写位；只读的身份/版本字与自由运行计数器
不能用它验（写进去本来就不回读）。那两类要换成：连读两次断言**相等**（版本字），或连读两次断言
**递增且不回绕**（计数器）——"恒 0 / 恒 F 不算通过"这一条对它们同样成立。

## 5. 身份寄存器：板子上跑哪一版的唯一硬凭据

在 RTL 里放一个只读的版本/构建号（或一个自由运行计数器）接进某个 GPIO/AXI-Lite 寄存器，
上板读回它。它回答的是两件事：**AXI-Lite 这条路通**，以及**接住这笔读写的这个时钟域在跑**
（读得回来就说明Slave 侧那一路 `s_axi_aclk` 活着）；再加上"值与这次构建的预期一致"时，
才第三件事——**PL 里是这一版**。
**"时钟在跑"这一件要按域写，不要写成整块 PL**：设计里另一路钟（例如数据通路自己那根引脚）
可以完全没起来而这里照常读回正确值——`first-bringup.md` §0 就是按"每一路钟各埋一个自由运行计数器"
来要求设计的，两页这里不能互相打脸。**分辨不出"哪个域在跑"这件事只有计数器能办**，
而且要读两次取差（见 `debug-triage.md` §2 树 A）。文件哈希回答不了这些。
每次交付都把这两个读数与一次烧写记录一起记：文件侧 `md5sum design_1.bit design_1.hwh > board/fp.txt`
只回答"这几个文件换过没有"，**板上跑的是哪一版只有这个寄存器能回答**——前者对得上而后者读回 0，
说明换过介质/重启回落到旧版，不是哈希在骗你（Vivado Tcl 里没有 `md5sum` 这条命令，取哈希要在 shell 里）。

## 6. 契约三处同源（改位定义时先读这段）

控制字的位定义同时存在于 ① RTL 的 `localparam`/`equ`、② 板端 Python 写出去的那个字、
③ 上位机脚本里的掩码。PYNQ 这一侧只给你"怎么把字写下去"，不给你"哪一位是什么"——
所以 `register_map` 让 ①② 通过元数据对上了（改设计重导出即可），但 ③ 不会自动跟着动。
新增位往高位加、不重排；只在一处改位，另外两处不报错，只会静错位。
