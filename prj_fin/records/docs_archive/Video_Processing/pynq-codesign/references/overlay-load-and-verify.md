# Overlay 加载与加载校验

## 适用范围

把 Vivado Block Design（或 HLS 封装后的 IP）产出的比特流放到 PYNQ 板上，并确认它
**真的被编程、驱动真的绑定**。适用于 PYNQ-Z2 / Zynq-7000 的全比特流加载，也适用于
UltraScale+ 板卡（同一套 `Overlay` API）。换题目不用改：只换 `.bit/.hwh` 路径。

版本钉在 PYNQ v3.1，文档只用 `en/v3.1/...`；原因与逐字出处见
`references/sources.md` 的“版本钉扎”。

## 使用方法

1. 成对拷文件。`.bit` 与**同名** `.hwh` 必须在同一目录：
   v3.1 要求 `.hwh` 与 `.bit` **同名同目录**（约束见
   <https://github.com/Xilinx/PYNQ/blob/v3.1/pynq/overlay.py#L289> 与 Overlay 库页）。只拷 `.bit`
   是现场最难查的错：板子能加载、`is_loaded()` 为真，但 IP 驱动绑不上。
2. 先在电脑上读设计，再上板：

   ```bash
   python3 scripts/hwh_inspect.py assets/fixtures/hwh/z2_video.hwh \
     --require address --require registers --require clocks --require dma
   ```

   `--require` 让“读不到”变成退出码 1，而不是打印一片空白当成成功。
3. 上板只做一次“先不编程”的实例化，确认设计形状，再真下载：

   ```python
   from pynq import Overlay
   probe = Overlay("/home/xilinx/design/bitstream/design.bit", download=False)  # 不写 PL
   ol = Overlay("/home/xilinx/design/bitstream/design.bit")                      # 真正编程
   ```

4. 用**可数的断言**校验，而不是“没报错就行”：

   ```bash
   python3 assets/examples/overlay_load_and_verify.py /home/xilinx/design/bitstream/design
   ```

   它检查 `is_loaded()` → `ip_dict` 条目数 → `reset()` 后加载记录仍在（v3.1 的 `reset()`
   只重置驱动字典，`device.reset` 会重新存时间戳，所以 `is_loaded()` 仍为真）→
   依据是 v3.1 源码两处（按内容定位，不押行号：`pynq/overlay.py` 内搜 `def is_loaded`
   看到 `return self.timestamp == self.device.timestamp`；搜 `def reset` 看到它结尾调
   `self.device.reset(self.parser, self.timestamp, self.bitfile_name)`）。文档页只列方法、
   不保证行为，所以这条**不写成板上实测**，是源码推断：示例里断言
   `reset-keeps-loaded-record` 的人应当先在自己的镜像上 `grep -n` 复核一次。
   重新 `download()`，
   每条打印一行 `OFFLINE-ASSERT`，最后一行给 `red=` 计数。
5. 换 overlay 时按官方语义收尾：`Overlay.free()`（移除 device-tree 段并关闭 device），
   新驱动“只有重新加载 overlay 才会绑定”
   （<https://pynq.readthedocs.io/en/v3.1/overlay_design_methodology/python_overlay_api.html>）。
6. 局部重配用 `Overlay.pr_download(region, partial_bit, dtbo=None, program=True)`；
   文档同时说明“不会检查该区域是否真的可部分重配”，所以必须自己比对部分比特流的
   sha256 与生成它的宿主设计
   （<https://pynq.readthedocs.io/en/v3.1/overlay_design_methodology/partial_reconfiguration.html>）。

## 失效条件

- 只有 `.bit`、`.hwh` 名字不一致或版本不匹配：`download=False` 也可能失败，因为地址
  与 FCLK 都取自 `.hwh`。
- `.hwh` 由 Vivado 2025.2/2026.1 生成而镜像是 v3.1（2024.1 构建）时，属性名可能改动：
  `hwh_inspect.py --require` 会红，这是**设计**，不是脚本坏。
- PYNQ 4.0 及以后：见 `references/sources.md`（Z2 支持已移除）。
- 想在 Jupyter 里反复 `Overlay(...)` 而不 `free()`：device-tree 段会互相顶掉，症状是
  IP 名字还在、寄存器读到 0。

## 已验证效果

```bash
python3 scripts/harness/selftest_stub.py           # checked=28 red=0
python3 scripts/run_offline.py --script assets/examples/overlay_load_and_verify.py
                                                   # checked=7 pass=7 fail=0 PASS
```

桩件在缺少同名 `.hwh` 时抛 `FileNotFoundError`（已断言）。真实 PL 编程结果只能上板确认，
本条目不声称验证过。其余命令输出见 `evals/results/tool_evidence.txt`。

## 来源

PYNQ v3.1 `overlay.py`/`bitstream.py`/`pl_server/embedded_device.py`（`.bit`→`.bin` 经
fpga_manager 写 `/sys/class/fpga_manager/fpga0/firmware`，full=0 partial=1），v3.1 Overlay
库页 <https://pynq.readthedocs.io/en/v3.1/pynq_libraries/overlay.html>，
板卡设置页 <https://pynq.readthedocs.io/en/v3.1/overlay_design_methodology/board_settings.html>
（PYNQ-Z2 板文件与主 XDC `PYNQ-Z2 v1.0.xdc`；上游构建实际用 `-part xc7z020clg400-1`）。
