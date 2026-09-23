# S16 · CDC 门禁要比"配对集合"，不要比行数：`report_cdc -details` 才点得出是谁

类别：**校验脚本 + 踩坑清单**（对应指南 §3.3.5.2 里"验证工程可复现性的脚本"）

## 适用场景

多时钟域、且把 `report_cdc` 当交付门禁的 FPGA 工程（Zynq / 纯 PL 都算）。
特别是"**已经**有一批被接受的跨域、之后每次改动都要求不新增"的场合 ——
本仓库的实现是 `build/gates.sh` 第 6 项 + `build/CDC_BASELINE.txt` + `build/tcl/cdc_who.tcl`。

**不适用**：单时钟设计；或者还没建立基线的第一版（那时先人工把每条跨域过一遍再冻基线）。

## 触发这条的真实事故

`cdc.rpt` 的门禁条款写着"Critical 行数不新增（对比上一版）"，而脚本里写的是**一个定死的数字 4**。
于是：

| 版本 | Critical 行 | 脚本说的 | 实际 |
|---|---|---|---|
| #25 | 3 | PASS | 基线 |
| #26 | 4（新增 `clkout0_1→clk_fpga_0`） | **PASS** | 我加了一对同步器，**门禁漏掉了** |
| #27 | 4 | **PASS** | 撤掉那对同步器，行还在 —— 元凶另有其人 |

两个版本都打印过 `GATES: ALL PASS`。**"行数 + 定值阈值"这种写法，只要上一版恰好低于阈值，
就能吞掉一次真实的退化。**

## 三条规矩（照抄可用）

### 规矩一：门禁比"配对集合"，基线入库

基线文件一行一条 `源钟>目的钟 端点数`（注释以 `#` 开头），门禁算三个集合：

```bash
rows() { awk '/^Critical/{print $2">"$3, $(NF-4)}' "$1" 2>/dev/null | sort; }   # 见下面的列坑
newrows=$(comm -13 <(基线配对) <(本版配对))     # 新增 ⇒ 判红
gone=$(comm -23 <(基线配对) <(本版配对))        # 少了 ⇒ 只提示"原因未查证，不算改进"
epgrow=$(join 基线 本版 | awk '$3>$2{...}')     # 同配对端点数增长 ⇒ 只提示，不判红
```

三个设计决定都有理由，别顺手简化：
- **新增配对判红**：多一条跨域才是真危险。
- **端点数增长只提示**：加一级仲裁寄存就会 +1，把它判红会让人去绕开门禁（红项一旦"必然红"，
  整个门禁就没人看了）。
- **变少也说出来**：本仓库 #23→#24 有一条 `eth_rxc→clk_fpga_0` 从 Critical 掉到 Warning，
  没人解释过原因。**不写下来就会被当成免费的性能改进念出去。**

### 规矩二：定位到人只能靠 `-details`

汇总表只给"钟对 + 端点数 + safe/unsafe"，改完 RTL 只知道数变了。
```tcl
# build/tcl/cdc_who.tcl：读**已布线** dcp，出带寄存器名的清单
open_checkpoint $dcp
report_cdc -details -file build/cdc_details.rpt
```
本次它给出的两行就是全部答案：

```
2  CDC-10  Critical  Combinational logic detected before a synchronizer   u_pl/FSM_onehot_mode_reg[2]/C  u_pl/ms0_reg[0]/D
3  CDC-10  Critical  Combinational logic detected before a synchronizer   u_pl/FSM_onehot_mode_reg[2]/C  u_pl/ms0_reg[1]/D
```

"`ms0 <= mode`"在 RTL 里看着就是打两拍 —— 是**综合把四状态寄存器重编成了 one-hot**，
于是跨域路径变成"3 个 one-hot 触发器经组合译码进 2 个目的触发器"。
**同步器之前不允许有组合逻辑**，格雷码的全部意义就是"每一位只依赖一个源触发器"。

### 规矩三：修法要从"让工具别改我"升级到"结构上就对"

两步，实测都有效（同一处改动）：

```verilog
(* fsm_encoding = "none" *) reg [1:0] mode;     // ① 不许 FSM 重编码：#28 实测该行 Critical→Warning、0 unsafe
always @(posedge clk_pix or negedge rst_pix_n)
    if (!rst_pix_n)      mode <= M_AUTO;
    else if (long_pix)   mode <= {mode[0], ~mode[1]};   // ② 下一状态按位写，#29 起
```

②用的是格雷码环 `00→01→11→10→00` 恰好等于 `{b0, ~b1}` 这个事实。
为什么还要写②：**①依赖工具的善意，②是结构事实**。而且式子是手推的，
所以配了台架项（`tb_v81_test_card` 的 T16/T16b/T16c：四步落在四个模式、每步只动一位、四态互不相同），
把"抄错编码"这种失败模式堵在仿真里。

## 已验证效果

- #28（只加①）：`clkout0_1→clk_fpga_0` **Critical(5 端点/2 unsafe) → Warning(5/0 unsafe)**，
  Critical 行数回到 3。**另**：同一次实现的全局 WNS 从 +0.733 变成 +1.001 ——
  这**不是**这条技巧能保证的收益（一次布局布线的结果，两版之间还有别的差异），
  念的时候只能说"#28 量到 +1.001"，不能说"改 CDC 让 WNS 涨了 0.27"。
- 重写后的门禁**当场把 #26、#27 判红**（它们此前都是 "ALL PASS"），
  并对 #25 给出正确的 PASS —— 检查器自己的两面对照测试。
- 反例测试也做了：同一份报告喂给旧脚本 → PASS，喂给新脚本 → FAIL。

## 失效条件 / 边界

1. **别用固定列号解析 `report_cdc`**：`CDC Type` 的 token 数会变
   （`No Common Primary Clock` 4 个、`Safely Timed` 2 个），按第 11 列取端点数会把
   Info 行读成 0。端点数 = **倒数第 5 个字段**。
2. **基线要跟着"采纳"走，不是跟着"最新"走**。本仓库默认演示 bit 是 #23，
   所以基线取 #23 的行集合（保守的超集），即使 #24/#25 更少。
3. `cdc_who.tcl` 读的是 `*.runs/impl_1/*routed.dcp`；**下一次 `create_project -force` 会把它删掉**，
   所以只能在构建刚结束后、下一次构建启动前跑（脚本里已改成 glob + 明确报错）。
4. 这套判据只看**结构性** CDC（配对、端点、unsafe）。它不判断"这条跨域上的数据是不是准静态"，
   也不判断**功能**正确性 —— 后者要靠台架（如 `tb_v796_src_arb`）与板级（`arb_handover_test.mjs`）。
5. 报告是**实现后**的产物：综合阶段的 `report_cdc` 会因为 `clk_fpga_0`（PS 生成）还不存在而漏行，
   别拿它当门禁。
