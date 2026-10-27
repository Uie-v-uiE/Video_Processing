# DMA 搬运与缓存一致性

## 适用范围

PS 与 PL 之间搬图像、采样帧、点云等成块数据（Zynq-7000，PYNQ v3.1）。
`pynq.lib.dma.DMA` 对应 `xilinx.com:ip:axi_dma:7.1`
（`bindto`，<https://github.com/Xilinx/PYNQ/blob/v3.1/pynq/lib/dma.py#L557-L581>）。
视频类 `axi_vdma` 用 `pynq.lib.video.dma`，交换流向用 `pynq.lib.axiswitch`，都不是本条目。

## 使用方法

1. 缓冲区必须物理连续、地址已知：

   ```python
   from pynq import allocate
   buf = allocate(shape=(720, 1280, 3), dtype="u1", cacheable=True)   # 或 with 语句自动释放
   print(hex(buf.physical_address), buf.coherent, buf.nbytes)
   ```

   `allocate(shape, dtype='u4', target=None, **kwargs)`（`pynq/buffer.py` L138）。**追参数要追到叶子**：
   中间层 `Device.allocate(self, shape, dtype, **kwargs)` 把 `**kwargs` 原样透传、不按名字校验，但
   链条终止于固定形参的叶子 `_xrt_allocate(shape, dtype, device, memidx, cacheable=0, pointer=None,
   cache=None)`（`pl_server/xrt_device.py` L59）——叶子**没有 `**kwargs`**，所以写错或多余一个键会在
   叶子处 `TypeError: _xrt_allocate() got an unexpected keyword argument ...`，**不是**被静默忽略。
   能绑定的只有 `cacheable / pointer / cache`；**没有** `user_flags`，也没有 `user_kwargs`。
   缓冲区大小由 `shape` 决定，`count=` 这类 2.x 写法同样在叶子处 `TypeError`（`api_lint` 的 E016 拦它，
   理由正是「未知键在叶子抛异常」，不是「上游会静默忽略」）。
   **没有** `length`（那是 Alveo/XRT 的说法）。必须先加载比特流才能分配
   （<https://pynq.readthedocs.io/en/v3.1/pynq_libraries/allocate.html>）。
2. 搬运与等待：

   ```python
   dma = ol.axi_dma_0
   buf.sync_to_device()               # CPU 写完、PL 读之前
   dma.sendchannel.transfer(buf)
   dma.sendchannel.wait()
   ```

   签名：简单通道是 `transfer(array, start=0, nbytes=0)`（**不接受** `cyclic`），
   scatter-gather 通道才是 `transfer(array, start=0, nbytes=0, cyclic=False)`；
   两种形式都**没有** `length=`。用 2.x 的四位置参数构造 `DMA` 会被拒。
   `DMA` 对象上只有 `sendchannel / recvchannel / buffer_max_size`（以及继承来的
   `mmio/read/write`）；`running / idle / error / transferred / halted` 在**通道**上。**不存在** `pl_device_transfer`、
   `sendchannel.push_buffer()` 这类名字，它们出现在很多二手教程里。
3. 先查上限再搬：`buffer_max_size = (1 << C_SG_LENGTH_WIDTH) - 1`。Vivado IP 默认
   位宽 14 bit，即一次事务最多 16383 字节
   （<https://pynq.readthedocs.io/en/v3.1/pynq_libraries/dma.html>）。帧大于它就分块，
   或者在设计里调 `C_SG_LENGTH_WIDTH`（代码里的兜底值是 26）。
4. 一致性按端口而不是按习惯：Zynq-7000 的 HP 通路对 PS 缓存不保证一致。规则写成断言：
   - PL 写、CPU 读：`recvchannel.wait()` 之后读；`wait()` 内部会做 invalidate。
     **真正的事故形态是“自己轮询 done 位然后直接读缓冲区”**，因为绕过了 `wait()`。
   - 需要显式：`buf.sync_from_device()`（= `invalidate()`）/ `buf.sync_to_device()`（= `flush()`）。
   - 用 `cacheable=True`（即 `coherent=False`）的缓冲做验证，才看得出漏刷的症状。
5. 完成判定不用固定延时：`time.sleep()` 既不是延迟上界也不是完成证明；读状态寄存器或
   `wait()`/`wait_async()`。
6. 流式 IP 必须拉 `TLAST`：“If this is not set, the DMA will never complete the transaction”，
   HLS 出流时最容易漏（同上 DMA 页）。`wait()` 会停在无界的 `while True` 上，症状是“程序
   挂住、CPU 100%、没有任何报错”。

## 失效条件

- 未对齐：源码在没有 DRE 时按数据位宽字节数检查起始地址并抛
  `RuntimeError: DMA does not support unaligned transfers; Starting address must be aligned to {} bytes.`
  （<https://github.com/Xilinx/PYNQ/blob/v3.1/pynq/lib/dma.py#L147-L152>）。numpy 的 view /
  切片不连续，不能直接进 `transfer()`。
- 文档与代码冲突：DMA 库页写“supports simple mode only”，但 tag v3.1 的驱动实现了
  scatter-gather 与 `cyclic=True`（`cyclic` 只在 `sendchannel`，且 `wait()` 抛
  `'Cannot wait in cyclic BD mode'`）。写代码前以自己的板子实测为准，两处证据都要引用。
- 微通道（参数名 `c_micro_dma`）与 SG 同时开启 → `UnsupportedConfiguration`。
- `cyclic` 的判定分两层：`recvchannel.transfer(..., cyclic=True)` 无条件判红（上游
  `dma.py#L368-L370` 抛 `Cyclic BD mode only valid in sendchannel`，而简单通道连这个关键字
  都没有）；`sendchannel` 一侧只有当源码自己把 `c_include_sg` 写成 0 时才判红，否则给
  W006 并点名要看 `parameters.c_include_sg`——核心是否带 SG 不在源码里，检查器不猜。
- 一致性检查认通道身份，而身份只从赋值继承：`rc = dma.recvchannel` 之后的 `rc.transfer()`
  与 `rc.wait()` 都必须算在 `recvchannel` 名下，否则 `rc.transfer(buf); print(buf[0])`
  这种写法会躲过 E007。缓冲区别名同理（`b = buf`）。从函数返回值拿到的通道无法定型，
  那条缓冲不主张任何结论。
- PYNQ 4.0：Z2 已被移除，本条目的地址与驱动细节整体失效。

## 已验证效果

```bash
python3 scripts/harness/selftest_stub.py     # checked=28 red=0
checked=21 red=0
```

桩件按上游语义复现了本条目每一条可判定规则：未对齐起始地址抛出与源码逐字一致的错误串、
超过 `buffer_max_size` 的整帧被拒、没设 TLAST 时 `wait()` 不静默返回、`cyclic` 在接收通道
被拒；一致性是**演示出来的**——不调
`sync_from_device()` 时桩件故意返回旧数据，调用后才等于期望值。桩件还抓到本包模板自己的
两个真错（分块用 16383 导致第二个描述符未对齐；接收侧整帧一次 `transfer` 被拒），修正后
`assets/templates/ps_app_skeleton.py` 在桩件下 `checked=13 red=0`。

**桩件与上游同因，不是「比上游严」**：`allocate(user_flags=...)` 在桩件里抛
`TypeError: _xrt_allocate() got an unexpected keyword argument 'user_flags'`——桩件把上游那个固定形参的
叶子 `_xrt_allocate` 也一并复现了；中间层不校验键名不等于静默接受，未知键在叶子照样报错，与真机一致。
`api_surface.json` 的 `pynq.allocate.kwargs_enforcement` 记的就是这条教训：**追参数必须追到叶子**。
桩件不建模的部分列在 `scripts/harness/pynq_stub/pynq/__init__.py` 的 docstring。
静态召回数字见 `references/pitfall-triage.md`；其余命令输出见
`evals/results/tool_evidence.txt`。

## 来源

`pynq.lib.dma` 页与 `pynq/lib/dma.py`（tag v3.1）、`allocate.html`、
`pspl_interface.html`；内核侧连续内存：v3.1 镜像内核配置 `CONFIG_CMA_SIZE_MBYTES=128`
（<https://github.com/Xilinx/PYNQ/blob/v3.1/sdbuild/boot/meta-pynq/recipes-kernel/linux/linux-xlnx/pynq.cfg#L1>）。
