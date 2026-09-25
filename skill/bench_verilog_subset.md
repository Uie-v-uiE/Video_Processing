
## 2026-09-25 一天之内撞了四次的四类 SV 写法（都长得很像 Verilog）

`run_sim.tcl` / `run_one.sh` 用 `xvlog` 按 **Verilog-2001** 编 `sim/tb_*.v` 与 `src/rtl/**/*.v`，
所以下面这些"看着一样"的写法是**编译期错误**，不是风格问题：

| 我写的（SV） | 报的错 | Verilog-2001 写法 |
|---|---|---|
| `per_of = CLKIN1_PERIOD * real'(DIVCLK_DIVIDE) ...` | `syntax error near '` | 靠 `* 1.0` 把表达式拉成 real；别用 `real'()` |
| `q = int'(p * 500.0 + 0.5);` | 同上 | 直接赋给 `integer`（就近取整），**而且别自己 +0.5**：Verilog 的 real→integer 本来就四舍五入，加 0.5 等于取整两次，实测把 20 ns 顶成 20.002 ns（100 ppm 的假时钟） |
| `expq = {8'(row - LINES), k[7:0]};` | 同上 | 先 `rm8 = (row - LINES) % 256;` 再拼 |
| `fork ... join_any disable fork;` | elaboration 才报（更贵） | 用"固定时间窗 + 有界循环"，天然有上界 ⇒ 顺带解决了"台架挂死拖垮整轮回归" |
| `function integer sx_now;`（**无参数**） | `ERROR [VRFC 10-8982] function must have at least one input` | 无参函数在 Verilog 里根本不合法：把那段计算就地写在 `always` 里 |

⚠ 这一类错误的共同点是 **xvlog 不会提示"你用了 SV"**，只会说"syntax error near `'`"，
所以第一反应容易去改算术、改位宽，白绕一圈。判据：**看见 `xxx'(...)` 或 `join_any` 或无参 function，
先当语法问题砍掉，再谈算术**。

顺带一条同族前科（同一天）：`MMCME2_BASE` 占位件的端口名少了 `CLKFBIN` ⇒
`cannot find port`；`OSERDESE2` 少 `TCE/OB/TBYTEOUT/TFB`、端口用了 `D[7:0]` 而真实例化是 `D1..D8` ⇒
`cannot find port`。**做法**：把两处例化里出现过的端口名/参数名全列出来对一遍
（`grep -oE "\.[A-Z][A-Z0-9_]+\s*\(" | sort -u`），不要凭模块手册的印象写。

## 第 9 类（同日，凭据质量，`build/strprobe/tb_str.v` 实测）：非 ASCII 文本一旦经过向量就被逐字节砍掉第 7 位

台架里最常见的写法是 `task line(input [8*96-1:0] tag, input ok, input [8*170-1:0] txt)`，
然后 `$display("%s %0s | %0s", ok?"PASS":"FAIL", tag, txt)`。**这份仓库的判据文字全是中文**，
于是日志里出现的是这种形状（同一份 `build/tb_v98_console.txt`）：

```
PASS C????????? | px_val / ??? /???? 256...      ← 经由 task 参数
INFO C-tap 样本 1200000 格、偏 1200000 格          ← 直接 $display，完好
```

用一个小台架把四种写法并排量出来（`od -c` 的结论，不是猜的）：

| 写法 | 结果 |
|---|---|
| `$display("...甲乙 ASCII...")` 字面量直接打 | 字节原样（甲 = `347 224 262`）✓ |
| 同一段字面量作为 **task 实参**（形参是定宽向量） | `377 377 377 262 ...` ⇒ **每个字节的 bit7 被清**，中文变乱码，ASCII 幸存 |
| 字面量先赋给 `reg [8*N-1:0]` 再 `%0s` | 同上 ⇒ 病灶是**"字符串字面量→向量"这一步**，不是 task 本身 |
| `%0s` 打 `cond ? "是" : "否"` | 整个三元式被折成**较短操作数的位宽** ⇒ 只剩乱码 |

还有一条一起撞到：**定宽字段超长时保留的是尾部、丢掉的是头部**（向量右对齐），
所以 `tag` 里前面那几个字会无声消失。中文一个字 3 字节 ⇒ `[8*96-1:0]` 只放得下 32 个汉字。

**规则**：判据的**标签字段只写 ASCII**（`C0a RULER`、`S7c LAG9`），要解释的话在**同一条 `$display`
的字面量里**写中文（或紧跟一条直接 `$display("     中文说明...")`）；
`%0s` 的位置**不要放三元式**，要么两条 `if` 各打一条完整句子，要么用 `reg [7:0]` 单字符。
这条不是洁癖：报告与 `OVERNIGHT_LOG` 会直接引用这些 PASS/FAIL 行，乱码行等于没有凭据。
