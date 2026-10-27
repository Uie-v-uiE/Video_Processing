# 寄存器映射：从 .hwh 来，不靠记忆

## 适用范围

需要读写自造 IP 的控制/状态寄存器时：确定基址、偏移、位段、访问权限，并生成主机侧
绑定（Python 与 C 头文件）与测试骨架。**任何硬编码 `0x40000000` 之前都应该先走这一条。**

## 使用方法

1. 从设计文件读事实，而不是猜：

   ```bash
   python3 scripts/hwh_inspect.py assets/fixtures/hwh/z2_video.hwh --format md
   ```

   v3.1 的寄存器映射本身就是运行期解析 `.hwh` 得到的
   （<https://github.com/Xilinx/PYNQ/blob/v3.1/pynq/pl_server/hwh_parser.py#L154>）：
   字段只有 `access / bit_offset / bit_width / description`。v3.1 **没有** register_map 的
   JSON 文件，也没有 `pynq_register_map.tcl` 这种 hook，网上大量教程里写的是旧版本流程。
2. 由检查结果生成绑定：

   ```bash
   python3 scripts/contract_gen.py --hwh assets/fixtures/hwh/z2_video.hwh \
     --ip <实例名> --out-dir build/generated
   ```

   产出 `<ip>_regs.py`（`MMIO` 包装 + 位段 get/set）、`<ip>_regs.h`（Vitis 裸机头文件）、
   `test_<ip>.py`（测试骨架）、`<ip>_contract.json`（含 `.hwh` 的 sha256，做工件绑定）。
   生成的代码会立刻被 `ast.parse` + `api_lint.py` 复检；契约不合法时脚本 **REFUSE**
   并给退出码 1，绝不生成带占位符的文件。
   `.hwh` 里没写 `BIT_OFFSET`/`BIT_WIDTH` 的位段，`hwh_inspect.py` 报
   `bit_offset: null`、`bit_width: null` 并把该寄存器标成 `field_ranges: "unresolved"`
   （md 报告写 `fields: unresolved`，`problems` 里有 `FIELD-NO-BITRANGE`）；
   `contract_gen.py` 仍然生成寄存器偏移常量，但**不生成**这个位段的掩码与 get/set，
   只在输出里打一行 `contract note`。位段自己从 IP 手册取，别照抄 0/1。
   地址段的归属同理：`INSTANCE="video_kernel_0/S_AXI"` 这种总线路径写法会归到真实实例
   `video_kernel_0`，并在报告里留下 `instance_attr` 原文与 `instance_attr_form`；
   归不到实例的路径带 `ADDRESS-PATH-UNRESOLVED`，`--require address` 对它判 missing。
   只想卡某一个 IP：`hwh_inspect.py --ip <实例名> --require address,registers`。
3. 板上的两条合法通路：

   ```python
   from pynq import MMIO
   mmio = MMIO(0x43c00000, 0x1000)          # 基址必须来自地址编辑器/ .hwh
   word = mmio.read(0x0)                     # 一次事务 32 bit
   mmio.write(0x0, (word & ~0xE) | (3 << 1)) # 读-改-写，别动别人的位
   ```

   有 IP 驱动时优先用 `ol.<ip>.register_map.CTRL.MODE = 3`；`register_map` 挂在
   **IP 驱动**上而不是裸 `MMIO` 上，数组型寄存器不生成映射（这是观察到的行为，v3.1 文档
   没有相应字面表述），切片写法是 RTL 的 `hi:lo` 含端点
   （<https://github.com/Xilinx/PYNQ/blob/v3.1/pynq/overlay.py#L738-L747>）。
4. 边界规则（都是可断言的，不是建议）：
   - 偏移不能为负：`Offset cannot be negative.`（`api_lint` 的 E018；注意 Python 里
     `-4 % 4 == 0`，所以「4 的倍数」这条检查抓不到负偏移，上游是先查负数再查对齐）；
   - 偏移必须是 4 的倍数，否则 `MemoryError: Unaligned read: offset must be multiple of 4.`
     （<https://github.com/Xilinx/PYNQ/blob/v3.1/pynq/mmio.py#L113>）；
   - `read(offset, length, word_order)` 的 `length` 只有 1/2/4/8；
   - `/dev/mem` 映射需要 root（板上 Jupyter 的 New ▸ Terminal 默认就是 root）：
     `EnvironmentError: Root permissions required.`
     （<https://github.com/Xilinx/PYNQ/blob/v3.1/pynq/pl_server/embedded_device.py>，
     文件内搜 `Root permissions required`；行号在两次独立读取中不一致，已改为按内容定位）
   - 一次 `MMIO` 读写是单个 32 bit 事务，**不支持 burst**，且只能访问接到 GP slave 端口的
     IP（<https://pynq.readthedocs.io/en/v3.1/overlay_design_methodology/pspl_interface.html>）。

## 失效条件

- IP 用数组型/向量型寄存器时 `register_map` 可能不覆盖它们（观察所得，非文档断言）→
  退回 `MMIO.array` 或 DMA，并自己核对 stride。
- Vivado 里没勾选 “Address Editor → Assign”，`.hwh` 里没有 `ADDRESSBLOCK`：
  `hwh_inspect.py` 报 `missing=address` 并退出 1，此时**不要**手写基址。
- `ADDRESSBLOCK` / `SEGMENT` 不带 `MEMTYPE` 时报告里的 `memtype` 是 `null`（旧实现误把
  `ISVALID` 当内存类型，已改掉）。判断它是不是寄存器窗口要看 base/high/size 与 IP 手册，
  不要拿这个空字段当依据。
- `.hwh` 与板上的 `.bit` 不是同一次实现产生的：生成的地址是错的。用
  `<ip>_contract.json` 里的 sha256 与板上 `.hwh` 比对（这就是工件绑定的用途）。
- 想靠 `MMIO` 搬一帧图像：这是把控制通路当数据通路，见
  `references/ps-pl-interface-choice.md`。

## 已验证效果

```bash
python3 scripts/contract_gen.py --self
```

三份 `.hwh` 样本各生成一遍绑定，生成结果再跑 `api_lint.py`（要求 0 红）。阴性对照：
删掉样本里的地址属性后必须解析不出地址，否则校验是假的。两份 Z2 样本的 DMA 参数不同
（长度域 14 与 23、数据宽 32 与 64），同一份代码报出不同上限与对齐——这就是“换板卡仍可用”。
`assets/fixtures/hwh/hwh_fixture_check.py` 断言样本对之间的这种差异真实存在。

## 来源

`pynq.MMIO` 页 <https://pynq.readthedocs.io/en/v3.1/pynq_package/pynq.mmio.html>，
MMIO 库页 <https://pynq.readthedocs.io/en/v3.1/pynq_libraries/mmio.html>，
`hwh_parser.py`/`overlay.py`/`registers.py`（tag v3.1）。
PYNQ-Z2 引脚与主 XDC：`PYNQ-Z2 v1.0.xdc`（板文件页给出的下载包）。
