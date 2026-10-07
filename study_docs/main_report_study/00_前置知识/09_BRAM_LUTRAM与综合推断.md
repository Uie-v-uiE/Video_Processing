# 09 · 存储器推断：BRAM / LUTRAM / 触发器，以及"怎么知道综合器做了什么"

> 这一篇是本工程第五版全部收益的来源。
> 更重要的是它教一个方法：**"综合器会把我这段代码变成什么"是问不出来的，只能测出来。**

---

## 1. 一个数组的三种命运

```verilog
reg [63:0] mem [0:511];
```

| 命运 | 物理形态 | 代价 | 读延迟 | 什么时候必须用它 |
|------|----------|------|--------|------------------|
| **触发器阵列** | 512×64 = 32768 个 FF + 512 选 1 mux 树 | **最贵**（本工程实测 3.3 万 FDRE） | 0 拍（组合读） | 深度极小（≤32）、需要异步读 |
| **LUTRAM（分布式 RAM）** | ~864 个 LUT-RAM 单元 | 便宜（约 1/40 的 FF 代价） | 0 拍（异步读） | 中等深度、需要异步读、BRAM 不够 |
| **BRAM（块存储）** | 1~2 个 tile | 最省逻辑，但**占块资源** | **1 拍（同步读）** | 深度大、能接受同步读 |

综合器的选择规则（7 系列 + Vivado）大致是：

1. **读是不是同步的**（`dout <= mem[addr]` 写在时钟块里）⇒ 同步读优先给 BRAM；
2. 读是异步的（`assign dout = mem[addr]`）⇒ 只能 LUTRAM 或 FF；
3. 数组的写端口/读端口结构不满足原语要求 ⇒ **退回 FF**（这就是本工程的坑）；
4. `(* ram_style = "block" | "distributed" | "registers" *)` 可以指定，但**指定错了会被忽略并告警**。

---

## 2. 本工程的真实事故：属性加了，但被拒绝

`axi_frame_saver64` 里那个 512×100 bit 的打包 FIFO 原本是这么写的（简化）：

```verilog
task automatic push_word; input [18:0] widx; input [63:0] data; ...
    begin
        if (!fifo_full) begin
            q_addr[wptr[FW-1:0]] <= ...;      // ← 数组写
            q_data[wptr[FW-1:0]] <= data;
            q_keep[wptr[FW-1:0]] <= keep;
            wptr <= wptr + 1'b1;              // ← 指针写在同一个块里
        end
    end
endtask

always @(posedge clk or negedge rst_n) begin  // ← 带异步复位的控制块
    if (!rst_n) ...
    else if (enable) begin
        if (wr_en) ... if (idx_chg) push_word(...);
        else if (flush && cur_dirty) push_word(...);
    end
end
```

只加属性：

```verilog
(* ram_style = "distributed" *) reg [63:0] q_data [0:511];
```

综合直接告诉你它不听：

```
WARNING: [Synth 8-7186] Applying attribute ram_style = "distributed" is ignored,
         object 'q_data[N]' is not inferred as ram due to incorrect usage
```

**为什么？** 因为数组的写发生在**带异步复位的 always 块**里、还包在 `task` 中、
并且和指针更新混在同一段过程代码里。存储器原语没有"异步复位"这个引脚，
综合器无法把这段过程映射到 RAM 原语上，只能老实摆一堆 FF。

---

## 3. 不靠猜：五个变体的最小对照实验

我建了一个只用来问"综合器会怎么实现"的实验（`sim/probes/ramtest.v` + `probe.tcl`）。
五个变体是**同一份 FIFO 语义**，只差写法。跑法：

```bat
vivado -mode batch -nojournal -log probe.log -source sim/probes/probe.tcl
:: 脚本内部对每个变体单独：
::   synth_design -top fifo_vN -mode out_of_context
::   然后统计 REF_NAME =~ FD* / RAM* / RAMB* 的单元数
```

实测结果（这就是"证据"）：

| 变体 | 写法 | FF | LUTRAM | BRAM |
|------|------|----|--------|------|
| v1 | 写在带异步复位的控制块里、经 `task` 调用（= 原 RTL） | **32904** | 0 | 0 |
| **v2** | **数组写独占一个无复位的 always 块**，`full` 折进写使能 | **85** | **864** | 0 |
| v3 | 同 v2，但**不加** `ram_style` | 22 | 1 | **1** |
| v4 | 二维数组 `[0:511][0:7]` 按字节拆 | 32911 | 0 | 0 |
| v5 | 同 v2，属性写成 `/* synthesis ram_style="distributed" */` 注释式 | 85 | 864 | 0 |

三条结论，每条都能直接背下来：

1. **阻碍推断的是"数组写 + 异步复位控制逻辑同块 + task 封装"**，不是读口形状；
2. **不加属性时综合器会把它塞进 BRAM**（v3）—— 而本工程 BRAM 只剩 1.5 个 tile，
   所以必须**显式**写 `distributed`；
3. 属性写法（`(* *)` 与 `/* synthesis */`）等价，都可以。

于是正确的形状是（这就是现在仓库里的代码）：

```verilog
(* ram_style = "distributed" *) reg [63:0] q_data [0:(1<<FW)-1];

// 读：异步口
wire [FW-1:0] ridx   = rptr[FW-1:0];
wire [63:0]   rd_data = q_data[ridx];

// 写：独占一个不带复位的块
always @(posedge clk) begin
    if (pack_we) q_data[wptr[FW-1:0]] <= cur_data;
end

// 指针：留在带异步复位的控制块里，由同一个 we 驱动
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) wptr <= 0;
    else if (pack_we) wptr <= wptr + 1'b1;
end
```

> 讽刺而有用的一点：**同一个仓库里 `dc_fifo.v` 早就写对了**
> （它的数组写就是独立的 `always @(posedge wr_clk)` 块，见 `dc_fifo.v:46-49`），
> 所以它顺利进了 BRAM。也就是说这个坑不是"知识缺失"，而是"没有全仓一致地执行"。
> **代码风格的一致性本身就是可靠性。**

---

## 4. BRAM 的深度填充：另一个只能测出来的规则

`04` 篇给过结论，这里给方法。同一份 512×300 帧缓存，六种写法（`sim/probes/fbtest.v`）：

| 变体 | 写法 | RAMB36 |
|------|------|--------|
| v0 | `[0:38400-1]`，64 bit 宽 | 128 |
| v1 | `[0:65535]`（声明成真正的 2 的幂） | 128 |
| v2 | `[0:38911]`（1024 的整数倍） | 128 |
| v3 | 4 个 16 bit bank 交织（每块仍 38400 深） | 128 |
| v4 | `[0:38400-1]`，32 bit 宽 | 64 |
| **v5** | **地址空间拆成两个 2 的幂：32768 + 8192** | **80** |

判读方式（这套读法比结论更有价值）：
- v0 = v1 ⇒ **不是"声明得不够整"的问题**（声明 65536 也一样）；
- v0 = v2 ⇒ **不是"没对齐到 1024"的问题**；
- v0 = v3 ⇒ **拆位宽也不解决问题**（因为每个 bank 的地址空间还是 38400）；
- v4 = 64 = 128/2 ⇒ **用量与位宽成正比 ⇒ 决定量的是"地址空间 × 位宽"**；
- v5 = 80 ⇒ **只有让每块地址空间本身是 2 的幂，才不被填充。**

⇒ 唯一自洽的解释：**综合器把非 2 的幂的地址空间向上取到 2^n**（38400 → 65536）。

---

## 5. 怎么自己复现这套实验（值得练一次）

```tcl
# 关键就这几行
create_project probe <dir> -part xc7z020clg484-2 -force
add_files variant.v
foreach v {v1 v2 v3} {
    synth_design -top $v -part xc7z020clg484-2 -mode out_of_context
    puts "$v FF=[llength [get_cells -hier -filter {REF_NAME =~ FD*}]] \
          LUTRAM=[llength [get_cells -hier -filter {REF_NAME =~ RAM*}]] \
          BRAM=[llength [get_cells -hier -filter {REF_NAME =~ RAMB*}]]"
}
```

三个坑：
1. **消息默认 100 条后静默**（`Message 'Synth 8-7186' appears 100 times and further
   instances ... will be disabled`）⇒ 不要靠"数告警条数"判断，要靠**单元计数**；
2. `get_cells -filter {PARENT =~ ...}` 这类写法慢且不稳 ⇒ 用 `REF_NAME` 过滤最可靠；
3. out-of-context 综合不看约束，正合适（我们只想问"这段代码变成什么"）。

---

## 6. 顺带：DSP48 的推断也会被复位破坏

同一份报告里还有 36 条 `DPIR-1`：

```
DSP u_pl/u_zmap/raw_xs input pin ... is connected to registers with an asynchronous reset.
This is preventing the possibility of merging these registers into the DSP Block
since the DSP block registers only possess synchronous reset capability.
```

**同一个道理**：DSP48 原语里的流水线寄存器没有异步复位引脚，
所以你那一级"带异步复位的乘法输入寄存器"**永远塞不进 DSP**，
只能留在逻辑区里，白白多花 FF 和走线。
想要 DSP 里的寄存器，就得让那一级是**同步复位或无复位**。

> 这一类问题的通用形态是：**"原语没有的功能，你的代码写了，综合器就只能用通用资源模拟它。"**
> 复位、初始化、读使能、字节写使能，都是这个模式的重灾区。

---

## 7. 收益清单（本工程实际拿到的）

| 改动 | 手段 | 收益 |
|------|------|------|
| 入包打包 FIFO | FF → LUTRAM（拆写块 + 指定 distributed） | **−51200 FDRE**，Slice 99.92%→34.99% |
| 显示帧缓存 | 地址空间拆 2 的幂 | **−48 RAMB36 tile**，BRAM 98.93%→64.64% |
| 显示拷贝 skid 缓冲 | 同第一条 | **−5215 FDRE**，Reg →4.08% |
| 合计 | 功能零变化 | 功耗 2.525→2.350 W；可布线网表 64604→10462；时序全程满足 |

---

## 8. 自测

1. 同一段数组代码，什么写法会进 BRAM、什么进 LUTRAM、什么退化成 FF？各给一条判据。
2. `Synth 8-7186` 是什么意思？你会怎么改代码而不是"再试试别的属性"？
3. 为什么"把数组声明成 1024 的整数倍"救不了 BRAM 填充？用 v0/v1/v2/v5 的实测数据论证。
4. 为什么带异步复位的寄存器挡住了 DSP48 的寄存器合并？给出两种解法及其代价。
5. 你如何在 10 分钟内验证"我新写的这个缓冲会不会吃掉 30 个 BRAM"？（写出命令级别的步骤）
