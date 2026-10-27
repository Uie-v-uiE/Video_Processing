# 症状分诊表（踩坑清单）

## 适用范围

板子行为不对、但不知道从哪查。按症状进表，每条给“先查什么 + 用什么命令 + 什么算查到了”。
表中的缺陷种类来自一份错误样本集：样本由独立会话按“LLM 最容易写错的 PYNQ 代码”
写出，且作者当时看不到检查规则与 API 面，所以这张表是被复算过的，不是凭印象列的。

## 使用方法

分诊表：

| 症状 | 第一位嫌疑 | 一条命令 / 一个断言 | 查到的判据 |
|---|---|---|---|
| `Overlay(...)` 抛异常或 IP 名字读不到 | `.hwh` 缺失/改名 | `ls -l design.bit design.hwh` | 两者同名同目录，缺一即错 |
| 加载“成功”但寄存器全读 0 | 地址没从设计来 | `python3 scripts/hwh_inspect.py design.hwh --require address` | 报 `missing=address` 即错 |
| overlay 加载成功、寄存器写得进去，但轮询自造 RTL 核的 `status.done` 永远不等 | 核的时钟不是 FCLK（或被地址编辑器漏分配），或 `enable` 位段从没真正置起来 | `python3 scripts/hwh_inspect.py design.hwh --ip <核名> --require address,clocks,registers` 再 `print(hex(mmio.read(STAT)))` | 时钟列没有一条落在 FCLK 频率表里，或 `missing=address/clocks`；写 `ctrl.enable` 后回读该位仍为 0 |
| `transfer()`/`wait()` 抛 `DMA channel not started` | 忘了 `channel.start()`：v3.1 的通道方法要求先启动（上游 `dma.py` 的 `if not self.running: raise RuntimeError("DMA channel not started")`） | `python3 scripts/api_lint.py app.py` | 通道上有 `transfer/wait` 却没有同一通道的 `start` |
| 读寄存器抛 `Unaligned read` | 把 bit 位当成字节偏移 | `python3 scripts/api_lint.py app.py`（E010） | 偏移不是 4 的倍数 |
| `transfer()` 抛 `DMA does not support unaligned transfers` | numpy view/切片、`start` 非对齐 | `python3 scripts/api_lint.py app.py`（E011） | 实参是切片或非常规缓冲 |
| `wait()` 永久挂住、CPU 满 | 流 IP 没拉 `TLAST` | 桩件复现：见 `references/dma-and-buffer-coherency.md` | 静态查不出来，只能行为验证 |
| 输出图像偶发旧帧/下半幅是脏的 | 绕过 `wait()` 自己轮询 done，未 invalidate | `python3 scripts/api_lint.py app.py`（E007） | 读点早于 `sync_from_device()`/`wait()` |
| 一帧数据要几秒才“发完” | 用 `MMIO` 循环当数据通路 | `python3 scripts/api_lint.py app.py`（E005） | 循环里出现寄存器写或 `length>8` |
| 大帧直接抛错或被截断 | 超过 `C_SG_LENGTH_WIDTH` 默认 16383 | `python3 scripts/api_lint.py app.py`（E008） | 缓冲大于上限且未读 `buffer_max_size` |
| “跑通了”但换个板就不行 | 常量、时钟、地址写死 | `python3 scripts/contract_gen.py --hwh ... --ip ...` | 基址/偏移来自生成物而非源码常量 |
| 帧率不达标但综合报告正常 | 时序违例被忽略或 oversize 端口 | `python3 scripts/measure_report.py metrics.csv --require wns,fps` | `wns` 为负或不在 spec 区间 |
| `ModuleNotFoundError: pynq.lib.xxx` | 镜像版本与 API 面不符 | 对照 `scripts/api_surface.json` | 名字不在 v3.1 列表里 |

复算这张表：

```bash
python3 scripts/api_lint.py assets/fixtures/bad --ignore sanity_run.py
python3 scripts/api_lint.py --self        # 用 expected.tsv 复算召回率
```

`assets/fixtures/bad/expected.tsv` 是样本集的标准答案表（含每条的证据 URL），检查器与
标准答案表由两个彼此看不到对方内容的会话产生，这就是召回率数字可信的原因。

### 检查码表（`api_lint.py` 的输出如何解读）

| 码 | 含义 | 典型修法 |
|---|---|---|
| E001 | `pynq`/`pynq.lib` 下没有这个模块或名字 | 对照 `scripts/api_surface.json` 的 v3.1 名字表 |
| E002 | 已知对象上没有这个属性/方法（桩件也会抛同名错） | 用文档里的真实属性名 |
| E003 | 命中“网上常见但不存在”的名字 | 换成本条目“已否定”表里的替代写法 |
| E005 | 把寄存器通路当数据通路（循环写、或 `length` 非 1/2/4/8） | 走 HP 端口 + AXI DMA |
| E006 | 用 `sleep()` 当完成判定 | `wait()` 或轮询状态位后再读 |
| E007 | 接收后未同步就读（且中间没有 `wait()`） | `sync_from_device()` 或用 `wait()` |
| E008 | 单次搬运超过 14 bit 长度域默认上限 | 读 `buffer_max_size` 分块，或改 IP 参数 |
| E009 | `Overlay()` 被 `except: pass` 吞掉错误 | 去掉裸异常，先补 `.hwh` |
| E010 | 寄存器偏移不是 4 的倍数（含把位号当偏移） | 用位段掩码 + 4 字节对齐偏移 |
| E011 | 传入切片/普通 numpy 数组 | 用 `pynq.allocate()` 的物理连续缓冲 |
| E012 | `transfer()` 用了不存在的关键字（如 `length=`） | 按签名 `transfer(array, start, nbytes, cyclic)` |
| S000 | 文件本身不能解析 | 先修语法，检查规则不判半截代码 |
| E013 | AXI GPIO 通道 `write()` 少了 mask，或 `read()` 传了参数 | 写成 `write(value, mask)` |
| E014 | `AxiIIC.send/receive` 少了 length | 补成 `(address, data, length)` |
| E015 | 往寄存器写 list/tuple/dict | 一次一个 32 bit 整数；成块数据走 DMA |
| W005 | `MMIO` 的 `length=` 不是可判定常量 | 换成字面量 1/2/4/8 或直接用默认 |
| E019 | `DMA(...)` 用了 2.x 旧驱动的形状（多于一个位置参数、任何关键字、或首参不是 ip_dict 条目） | 写 `DMA(ol.ip_dict['axi_dma_0'])`，或直接用 `ol.axi_dma_0`；错误串取自 `api_surface.json` |
| E020 | 用本包 `hwh_inspect.py` 报告的字形去读 `Overlay.ip_dict`（`address_blocks`/`base`/`offset`、`registers[0]`、把 `fields` 当列表遍历） | 上游是 `phys_addr`/`addr_range`，`registers`/`fields` 都是「名字→描述」的 dict，用名字取或 `.items()`；仅当 `api_surface.json` 带 `ip_dict_keys` 一节时生效 |
| E021 | 位置参数放错槽：`MMIO.read` 第 3 槽是 `word_order`，`MMIO.write` 只有 `(offset, data)` | 长度写第 2 槽或 `length=`；一个字一次写 |
| E022 | `cyclic=` 落在不支持的通道上（`recvchannel`，或本文件已把 `c_include_sg` 写成 0 的 sendchannel） | `cyclic` 只属于 scatter-gather 的 sendchannel，且循环模式下不能 `wait()` |
| W006 | `cyclic=True` 的核心是不是 SG 无法静态判定 | 点名判不了的是 `parameters.c_include_sg`，用 `hwh_inspect.py --require dma` 确认 |

`Overlay` 与 IP 实例的属性名是**开放集合**（每台设计自己命名 IP），所以 E002 只对成员闭合的
对象生效：`MMIO`、`PynqBuffer`、`DMA`、通道、`AxiGPIO`、`AxiIIC`。这条边界写在
`api_lint.CLOSED_KINDS`。

## 失效条件

- 表里的 `pynq` 名字只对 v3.1 成立；v4.0 的名字集合不同（Z2 支持已取消）。
- 非 AXI-Stream 的设计（纯 AXI4-Full、`axi_vdma`、`AXI DMA` 的 memory-mapped 形态）
  不适用 `TLAST` 那一行。
- 样本集里的脚本写的是板上绝对路径（`/home/xilinx/...`），因此在笔记本上**不可离线判定**：
  `run_offline --self` 会把它们报成 `NOT-EVALUABLE`（不参与召回分母），只有静态层适用。
  行为层的证据来自 `scripts/harness/selftest_stub.py` 自己的阴性对照（含 TLAST 永不出结果、
  未对齐、漏 `sync_from_device()` 读到脏数据、`cyclic` 拒等）。
- Windows 控制台上直接看脚本输出可能有代码页问题：本包所有工具的判定行都用 ASCII
  （`checked= red= PASS|FAIL`），中文只出现在文档正文；跨平台复现请优先看退出码。
- 这张表不覆盖 Vivado 综合/实现阶段的问题（时序违例、约束覆盖）——那属于设计侧，
  用 UG901/UG904/UG949 的方法，以及 `measure_report.py` 把数字钉住。
- 通道/缓冲区身份只认**赋值**这一种别名（`rc = dma.recvchannel`、`b = buf`）。从函数返回值
  拿到的通道（`get_dma(ol).recvchannel`）在这里无法定型，E007 对那条缓冲不做任何主张：
  没报不等于同步过。
- E020 只拒绝下标形态的取键。`entry.get("address_blocks") or entry["phys_addr"]` 这种
  「先按一种形状、拿不到再退回去」的双形状读法（本包示例与骨架就这么写）不判红；
  经过辅助函数返回值拿到的 dict 也无法定型。
- E022 只在能静态证伪时才判红：`recvchannel` 的 `cyclic`（上游无条件拒绝），以及本文件
  自己把 `c_include_sg` 写成 0。核心到底带不带 scatter-gather 由设计决定，源码里没有
  那条描述字典时只给 W006，并同时点名要跑 `hwh_inspect.py --require dma` 看哪个参数。
- GPIO 切片的成员不在白名单里：`chan[0]` 的结果类型是开放的（`Input`/`Output`/`InOut`
  成员不同），所以 `gpio.channel[1].halted` 只可能报在 `channel1.halted` 这一层；
  切片上的错名要由 `api_surface.json` 的 `slice_attrs` 那类数据支撑后才可能收紧。

## 已验证效果

```text
# 复算：python3 scripts/api_lint.py --self && python3 scripts/run_all.py
checked=21 red=0
checked=21 red=0
checked=21 red=0
selftest_stub: checked=28 red=0                  # 行为层阴性对照，能红
checked=21 red=0
```

五条命令都在 `scripts/run_all.py` 生成的 `evals/results/tool_evidence.txt` 里可复现。
唯一漏检的 TLAST 被明确写成“静态不可判定，由行为层覆盖”，而不是假装覆盖：这是本表与
“通用注意事项清单”的差别。

## 来源

样本集：`assets/fixtures/bad/bad_01..bad_10` 与标准答案表 `expected.tsv`（全部由未看到检查器
的会话写出）。API 判据：`dma.py`/`mmio.py`/`buffer.py`/`overlay.py`（tag v3.1）与对应
v3.1 文档页。两条被样本作者**推翻的我方前提**也记录在案：`recvchannel.wait()` 自身会做
invalidate；`Overlay.pr_download` 在 v3.1 确实存在（不是旧版残留）。
