# GPIO、I2C 与中断（控制类题目常用通路）

## 适用范围

控制、采集、电机、传感器类题目：需要读写离散 IO、方向可变的 GPIO 组、I2C 外设，或让 PL
事件通知 PS。数据面（帧、大块采样）仍见 `references/dma-and-buffer-coherency.md`。

以下每一条都按 Xilinx/PYNQ tag v3.1 源码核对过；v3.1 **没有** 的写法在“失效条件”里列出，
不要从旧版教程照抄。

## 使用方法

### AXI GPIO（PL 侧并行 IO）

`pynq.lib.axigpio.AxiGPIO` 绑定 `xilinx.com:ip:axi_gpio:2.0`（注意是 2.0，不是 2.1），
由 `Overlay` 自动绑定成 `ol.<实例名>`
（<https://github.com/Xilinx/PYNQ/blob/v3.1/pynq/lib/axigpio.py>）。

```python
gpio = ol.axi_gpio_0             # AxiGPIO 驱动实例
chan = gpio.channel1             # 通道从 1 开始编号：channel1 / channel2，没有 channel0
chan.setlength(8)                # 有效位宽
chan.setdirection("in")          # 也接受 AxiGPIO.Input / Output / InOut
word = chan.read()               # 整通道读
chan.write(0x0F, 0xFF)           # write(value, mask)：两个参数，掩码必给
chan.trimask = 0x0F              # 方向掩码（InOut 才有意义），寄存器偏移 channel*8+4
bit = chan[0]                    # 单引脚对象：.read()/.write()/.on()/.off()/.toggle()
pair = chan[1:3]                 # 引脚切片；切片写法是 RTL 的 hi:lo
```

等待某个引脚值的方法是**切片对象**上的 `chan[0].wait_for_value(v)` /
`wait_for_value_async(v)`：二者定义在 `AxiGPIO.Input`（`axigpio.py#L61`、`#L51`），
`InOut` 继承之，`Output` 没有。`Channel` 本身只有异步的 `wait_for_interrupt_async`
（`axigpio.py#L246`），既没有 `wait_for_value` 也没有 `wait_for_interrupt`；把
`chan.wait_for_value(v)` 当作通道方法来写，上板即 `AttributeError`。
前提是 IP 的 `ip2intc_irpt` 已接到中断控制器：驱动在 `description["interrupts"]` 里
找 `ip2intc_irpt`，找到才置 `has_interrupts` 并写 `0x11C = 0x80000000`
（`axigpio.py#L281-L285`）。没接线时调用等待类方法会抛
`RuntimeError("Interrupts not available for this IP")`（`axigpio.py#L254-L255`）。

### PS 侧 GPIO（sysfs 包装）

```python
from pynq import GPIO
pin = GPIO(400, "out")           # 第一个参数是 Linux 绝对编号 gpio_index，不是板卡丝印号
pin.write(1)
value = pin.read()
pin.release()
```

`GPIO` 包装的是 Linux `/sys/class/gpio`，其文档原话：“This GPIO class does not handle PL
I/O without the use of device tree overlays”
（<https://github.com/Xilinx/PYNQ/blob/v3.1/pynq/gpio.py>）。要把 overlay 里的 GPIO 引脚
映射成用户号，用静态方法 `GPIO.get_gpio_pin(index, target_label)` /
`get_gpio_base(target_label)` / `get_gpio_npins(target_label)`，`target_label` 是设备树里
该 GPIO 驱动节点的 label。**PL 引脚走这条路需要设备树支持**，否则请改用上一节的
AXI GPIO，这也是控制类题目在 PYNQ 上更稳的做法。

### I2C（AXI IIC）

`pynq.lib.iic.AxiIIC` 绑定 `xilinx.com:ip:axi_iic:2.1`，只有
`send(address, data, length, option=0)` / `receive(address, data, length)` / `wait()`
（<https://github.com/Xilinx/PYNQ/blob/v3.1/pynq/lib/iic.py>）。模块名是 `iic` 不是 `i2c`。
`data` 传 `pynq.allocate` 出来的连续缓冲或 `bytes`/`bytearray`；`length` 要与之匹配。

### PL 中断通知 PS

v3.1 的中断入口是 `pynq.Interrupt(pinname)`，`pinname` 形如
`"axi_gpio_0/ip2intc_irpt"`，构造时会用 `pynq.PL.interrupt_pins` 校验；等待是异步的：

```python
import asyncio
from pynq import Interrupt

async def main():
    intr = Interrupt("video_kernel_0/interrupt")   # 名字必须出现在 PL.interrupt_pins
    await intr.wait()

asyncio.run(main())
```

（<https://github.com/Xilinx/PYNQ/blob/v3.1/pynq/interrupt.py>）驱动内部用一个 AXI
中断控制器的寄存器组（偏移 0x04/0x08/0x0C/0x10/0x14/0x1C）；直接连到 PS 的 IRQ 若没有
以 UIO 形式暴露给 Linux，会抛
`ValueError('Could not find UIO device for interrupt pin ... for IRQ number {}')`。
所以设计侧要么把中断接到 `axi_intc`，要么把该 IRQ 做成 UIO 设备。

### 用 `api_lint.py` 把住这些细节

```bash
python3 scripts/api_lint.py src/ps_app.py --allow <你自己镜像上取证过的新名字>
```

检查规则会拒绝 `gpio.channel0`、`from pynq import IntFile`、`pynq.lib.i2c`、
`pynq.lib.spi` 这类写法（`scripts/api_surface.json` 的 `refuted` 列表），并对
`AxiGPIO` / `Channel` / `AxiIIC` 的属性名做白名单校验。若你的镜像确实导出了表外名字，
先在本机取证再用 `--allow` 放行，而不是改动随包文件。

## 失效条件

- v3.1 **没有**：`pynq.lib.spi` / AXI-SPI 包装、`pynq.lib.uart`、`pynq.iop`、
  `pynq.lib.pwm` / AXI 定时器包装、`axi_i3c` / `axi_can` 驱动、`Pmod_SPI` / `Pmod_UART`。
  要 PWM/定时器，就自己做一个 AXI-Lite IP 用 `MMIO` 驱动；`pynq.lib.pmod` 里的
  `Pmod_PWM` / `Pmod_Timer` 是 MicroBlaze IOP 上的 Pmod，不是 AXI 外设。
- 旧版 API 混入：`IntFile`（v3.1 是 `Interrupt` + `await wait()`）、`pynq.iop`
  （现在是 `pynq.lib.pynqmicroblaze`）、`AxiGPIO.channel0`（通道从 1 起）。
- 通道方法写错：`chan.wait_for_value(v)` / `chan.wait_for_interrupt()`——`Channel` 没有
  这两个名字（`axigpio.py#L166-L274` 内不存在），上板 `AttributeError`；`wait_for_value`
  只在 `Input`/`InOut` 切片上，通道只有 `wait_for_interrupt_async`。
- 同一个错误换成链式写法也一样判：`ol.axi_gpio_0.channel1.halted`、
  `gpio.channel1.wait_for_value(v)` 与先赋值再写的 `chan.halted` 是同一个事实，检查器
  现在沿属性链解出宿主类型（`AxiGPIO.Channel` 的成员集合是闭合的：read/write/trimask/
  setlength/setdirection/wait_for_interrupt_async + length/slicetype）。但**切片**结果
  （`chan[0]`、`chan[1:3]`）的成员仍不白名单化，因为 `Input/Output/InOut` 三种切片的
  成员本就不同，静态层无法知道是哪一种；`halted` 是 DMA scatter-gather 通道的属性，
  GPIO 通道没有它。
- `AxiGPIO` 只绑 `axi_gpio:2.0`：若设计里是别的版本，驱动不会自动绑定，症状是
  `ol.axi_gpio_0` 退化成 dict 或没有 `channel1`。
- 中断类方法未接 `ip2intc_irpt`：等待会挂住。先用 `gpio.has_interrupts` 断言再等待。
- PYNQ 4.0 与 Versal 的名字集合不同，本条目的白名单只对 v3.1 成立（见
  `references/sources.md`）。

## 已验证效果

```bash
python3 scripts/harness/selftest_stub.py            # 含 GPIO/I2C/中断的阴性对照
python3 scripts/api_lint.py assets/examples/gpio_and_iic_probe.py   # 正确用法不误报
python3 scripts/run_offline.py --script assets/examples/gpio_and_iic_probe.py
```

桩件按 v3.1 源码语义实现了 `AxiGPIO`（通道从 1 起、`write(value, mask)` 两参、
`trimask` 落在 `channel*8+4`、引脚切片、未接中断时 `has_interrupts` 为假）、`AxiIIC`
（`send/receive/wait` 回环，长度不符即报错）与 `Interrupt`（名字不在
`PL.interrupt_pins` 里就拒绝，`await wait()` 走异步路径）。因此
`gpio.channel0`、`IntFile(...)`、`pynq.lib.i2c` 这些写法在离线阶段就能被判红，而不必等到
上板。板上真实电气行为（电平、时序、中断实际到达）本机无硬件，未验证。

## 来源

来源（本次核对逐行取自 <https://raw.githubusercontent.com/Xilinx/PYNQ/v3.1/pynq/lib/axigpio.py>）：
`AxiGPIO.Channel` 定义于 `#L166`，只有异步 `wait_for_interrupt_async`（`#L246`），无
`wait_for_value` / `wait_for_interrupt`；`wait_for_value` 在 `AxiGPIO.Input`（`#L61`，异步版
`wait_for_value_async` 在 `#L51`），`InOut`（`#L126`，继承 `Input`）有之，`Output`（`#L75`）无；
`has_interrupts` 与 `0x11C` 写好在 `AxiGPIO.__init__`（`#L281-L285`）。

`pynq/lib/axigpio.py`、`pynq/gpio.py`、`pynq/interrupt.py`、`pynq/lib/iic.py`、
`pynq/lib/__init__.py`（均取 tag v3.1）。v3.1 文档没有独立的中断页，故中断只按源码引用；
API 参考页在 <https://pynq.readthedocs.io/en/v3.1/pynq_package.html>。
