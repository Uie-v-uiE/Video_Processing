# 描述符层能检查什么、检查不到什么

本表只列与"寄存器映射与回读"这一条做法直接相关的接口事实；版本差异的全表见
`pynq-overlay-load-verify` 条目的出处表（按条目名找，不在本机路径里）。

## 描述符层自带的检查（写对了就白拿）

| 事实 | 来源 |
| --- | --- |
| `register_map` 支持的类：`Scalar` / `Bits` / `Array` / `Struct` / `Union` | `pynq/regtools.py` |
| 字段定义是 `struct` 风格，不是 dataclass | `pynq/regtools.py` |
| 位段越界、位段重叠在**构造 `register_map` 时**报错 | `pynq/_regmap.py` |
| 数组读写：`read(index=)` / `write(values, index=)` | `pynq/_regmap.py` |
| `MMIO(address, length)`，`read`/`write` 收发**字典**（键=切片名） | `pynq/mmio.py` |
| 单个位段用 `read_bitfield(name)` / `write_bitfield(name, value)` | `pynq/mmio.py` |
| `describe()` 返回打印用字符串 | `pynq/_regdict.py` |
| 复位值不在运行时读，来自 IP 文档 | 文档 "Writing a Register Map" |
| 驱动寄存器映射可由 tcl 生成，官方要求人工核对 | 文档 "Driver Hardware Register Map" |

## 描述符层查不到的（必须另配判据）

1. **表与描述符是否同一份**：描述符只保证自身位段自洽，不保证它抄自当前版本的表。
   判别式：从表现生成一份描述符文本，与代码里那份逐行 diff；差异数应为 0，非 0 即漂移。
2. **写进去了没有**：描述符不知道硬件。判别式是回读三元组（可写位等值、只读位拒绝改变、邻位不受扰动）。
3. **地址对不对**：`MMIO` 用一个错地址同样能读写（读到的是别名或未映射区）。
   判别式：把地址与 IP 地址映射（xsa/hwh 的基址符号）做字符串级比对，取不到映射就判 `NOT_MEASURED`，
   不许"能读写就算对"。
4. **两侧漂移**：主机侧手写的常量。判别式见 `contract-to-host-bindings`——产物里出现表里没有的地址即红。

## 拼位与对齐的常见错形

| 症状 | 先查 |
| --- | --- |
| 读回值像对但差几位 | 描述符位段顺序与文档是否反了（大小端在**位段层**与**字节层**是两件事） |
| 写一位动了邻位 | 是否绕开描述符用了 `>>`/`&` 手工拼，或 `read-modify-write` 漏了 |
| 新增一格后测试数不变 | 表→描述符→测试三步里哪一步没跟着改 |
| 数组某一档读到 0 | `index` 越界被静默吞了，还是该格本来就 0——用非 0 图案分档写入再看 |
| 换个 PYNQ 版本整片红 | 打印 `describe()` 的措辞被拿来做比对了 |
