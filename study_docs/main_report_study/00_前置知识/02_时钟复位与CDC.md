# 02 · 时钟、复位与跨时钟域（CDC）

> 本工程有 4 个互相异步的时钟域，视频数据要一路穿过它们。
> 第五版修的那个"帧尾丢 4 字节"缺陷，根因正是**跨时钟域的可见性问题**——
> 所以这一篇不是背景知识，是理解本项目的钥匙。

---

## 1. 为什么会存在多个时钟

一个视频链路里，每个环节的天然节拍都不一样：

| 时钟 | 频率 | 从哪来 | 管什么 |
|------|------|--------|--------|
| `sys_clk` | 板载晶振（本工程 50 MHz 输入 MMCM） | 板上 OSC | 给 MMCM 当参考 |
| `eth_rxc` | **125 MHz** | **PHY 芯片随 RGMII 一起送过来** | 收包侧全部逻辑（RGMII 解串、ARP/ICMP/UDP、拼帧） |
| `clk_fpga_0` = `axi_clk` | **100 MHz** | PS 的 FCLK_CLK0 | AXI HP0 写 DDR、乒乓与提交 |
| `clk_pix` | **50 MHz** | PL 侧 MMCM（`clk_gen.v`） | HDMI 像素时钟（1024×600@约 50 MHz） |
| `clkout0_1` | MMCM 另一路输出 | 同上 | IDELAY 参考 / 串行化相关 |

关键点：**`eth_rxc` 是外部世界给的**，它和 `axi_clk` 之间没有任何相位关系；
`clk_pix` 是显示需要，也独立。所以数据必须"跨域"。

> 约束文件里这些时钟被声明成**异步时钟组**（`set_clock_groups -asynchronous`），
> 意思是"我不要求它们之间的路径满足时序，因为根本不可能"。
> 于是这些路径的正确性**完全靠电路结构保证**，工具不会帮你检查——这就是 CDC 的全部风险来源。

---

## 2. 亚稳态：为什么"直接连"会随机出错

一个 D 触发器要求在时钟沿前 `Tsu`、后 `Th` 这段时间里数据是稳定的。
如果数据在窗口内变化，触发器输出会进入**中间电平**（亚稳态），
并在接下来若干拍内以概率逐渐衰减的方式"决断"成 0 或 1。

后果不是"算错"，而是：
- 决断值可能是 0 也可能是 1，**且与你的输入无关**；
- 同一个决断值还会被下游复制、参与组合逻辑，导致**两个本该相同的信号分叉**；
- 表现为"板子上偶尔抽一下，重启就好，仿真永远复现不出来"。

对策不是消除（消除不了），而是**给它时间决断**：

```
源域寄存器 ──► 目标域第一级 FF ──► 第二级 FF ──► 后面才使用
                  （允许亚稳)        （到这里已稳定）
```

这就是**两级同步器**。第三级是奢侈但便宜的保险。
本工程对 `frame_done` 就用了三级：

```verilog
// src/rtl/eth/ddr_bank_commit.v（第五版抽取出来的模块）
(* ASYNC_REG = "TRUE" *) reg fd0, fd1, fd2;
always @(posedge axi_clk or negedge axi_rst_n)
    if (!axi_rst_n) {fd2,fd1,fd0} <= 3'b0;
    else            {fd2,fd1,fd0} <= {fd1,fd0,frame_done_tog};
wire fd_axi = fd1 ^ fd2;          // 边沿检测：把"电平翻转"变成"目标域单拍脉冲"
```

三个要点都在这里：
1. `ASYNC_REG` 属性告诉工具"这两个 FF 是刻意挨着放的同步器"，别把它们拆开布局；
2. 跨域传的是**翻转标志（toggle）而不是脉冲**——脉冲可能整个被错过，翻转不会；
3. 在目标域用 `fd1 ^ fd2` **重新生成**一个单拍脉冲。这是"跨域传事件"的标准做法。

---

## 3. 三类跨域问题与对应解法

| 要传的东西 | 错误做法 | 正确做法 | 本工程在哪用 |
|------------|----------|----------|--------------|
| 单 bit 电平 | 直接用 | 2~3 级同步 | 链路状态、按键 |
| 单 bit 事件（脉冲） | 直接把脉冲接到对方时钟 | 翻转 + 对端边沿检测 | `frame_done_tog` → `fd_axi` |
| **多 bit 数据** | 每个 bit 各自同步（**绝对禁止**） | 握手 + 保持、或异步 FIFO、或格雷码 | `dc_fifo`（数据）、`frame_commit_lock`（地址/基址） |

### 为什么多 bit 不能各同步各的

每个 bit 的亚稳态决断时刻不同，于是"32 位一次跳变"可能被采样成
"高 16 位是新值、低 16 位是旧值"的**根本不存在的中间值**。
两条出路：

1. **格雷码**：相邻计数值只有 1 bit 变化 ⇒ 即使采到"半新半旧"，也是两个合法值之一。
   适合指针。本工程 `dc_fifo.v` 就是这么写的：

```verilog
// src/rtl/eth/dc_fifo.v
function [ADDR_W:0] bin2gray; input [ADDR_W:0] b; bin2gray = b ^ (b >> 1); endfunction
// 写指针格雷码 → 读域两级同步；读指针反向同理
always @(posedge rd_clk or negedge rd_rst_n)
    if (!rd_rst_n) begin wgray_s0<=0; wgray_s1<=0; end
    else begin wgray_s0 <= wgray; wgray_s1 <= wgray_s0; end
assign rd_empty = (rgray == wgray_s1);
```

2. **握手（req/ack）**：数据保持稳定直到对方确认。适合慢速控制字。
   本工程"把 DDR 基址交给显示侧"就是这一类：`ddr_commit_base` 在提交脉冲之前就已经稳定，
   显示域用 `frame_commit_lock` 在**消隐窗口**这个安全时刻锁存它。

---

## 4. 复位也要跨域

`rst_n`（随 `eth_rxc` 域有效）与 `axi_rst_n`（PS FCLK 域）是两个不同的复位。
异步 FIFO 的两边各自用自己的复位。这里最常见的坑是：

- **只复位一边**：写域指针清零、读域指针没清 ⇒ `empty/full` 判定永久错；
- **复位释放不同步**：某个域的 FF 在复位释放瞬间处于亚稳态 ⇒ 需要"异步复位、同步释放"。

本工程的写法是"每个域各自异步复位自己的指针"，并且 `dc_fifo` 的两组指针分别在
`wr_clk`/`rd_clk` 下复位（见 `dc_fifo.v:36-43, 56-65`）。

---

## 5. 本工程的跨域地图

```
网线 → PHY → RGMII(DDR, 125 MHz)
        │
   [eth_rxc 域]  rgmii_rx → gmii_to_rgmii → arp/icmp/udp_rx → frame_reasm
        │                                              │
        │                                    fb_wr_en / fb_wr_addr / fb_wr_data
        ▼                                              ▼
   16bit 像素写 + flush 标记  ──────►  dc_fifo（36bit×8192，格雷码异步 FIFO）  ◄── CDC 点 ①
                                                       │
                                        [axi_clk = clk_fpga_0 100 MHz 域]
                                                       ▼
                            axi_frame_saver64（4×16bit 拼 64bit + keep 掩码）
                                                       ▼
                                        AXI HP0 → PS DDR 乒乓 bank 0x1000_0000 / 0x1008_0000
                                                       │
        frame_done（eth_rxc 域脉冲）── toggle + 3FF ──►│  ◄── CDC 点 ②
                                                       ▼
                            ddr_bank_commit：决定"何时把哪个 bank 交给显示"
                                                       │
                            ddr_commit_base / ddr_commit_pulse
                                                       ▼
        [clk_pix 50 MHz 域]  frame_commit_lock ──► axi_frame_writer_gated 整帧拷进显示 BRAM  ◄── CDC 点 ③
                                                       ▼
                            显示读 → 旋转/缩放 → 效果 → OSD → TMDS → HDMI
```

**三个 CDC 点，三种不同机制**：① 数据流用异步 FIFO；② 事件用翻转+同步；
③ 大块数据用"基址稳定 + 在安全窗口（消隐期）锁存"的隐式握手。

---

## 6. 第五版修的缺陷：CDC 的"可见性"问题（不是同步器写错）

这个 bug 特别值得学，因为它**不是任何教科书意义上的 CDC 错误**：
同步器是对的、FIFO 是对的、约束也没漏。错的是**一个判断条件看不见另一段管线**。

- 乒乓换页的判据是 `saver_idle`（打包器空了）。
- 但"打包器空"只说明**它自己和在途 AXI 事务**空了；
  它上游那个 8192 深的 `dc_fifo` 里可能还压着本帧最后几个 16 bit lane，
  而且 `dc_fifo` 后面还有两级读流水（`cdc_d1`、`sav_en/sav_flush`）。
- 于是：打包器恰好排空 → 换 bank → 那几 lane 到了 → 按**新** bank 地址写下去 →
  刚提交的那个 bank 的帧尾 4 字节永远停在旧值。

修复就是把判据补全（`src/rtl/eth/ddr_bank_commit.v`）：

```verilog
wire tail_drained = cdc_empty && !cdc_rd && !cdc_d1_v && !sav_en && !sav_flush;
wire commit_ok    = saver_idle && tail_drained;
```

> **可迁移的教训**：任何"我以为数据已经流完了"的判断，都必须把**整条通路上的每一级缓冲**
> 都算进去——FIFO 深度、寄存器打拍、在途总线事务，一个都不能漏。
> 这类错误在纯功能仿真里也难暴露，因为 TB 常常在帧之间人为排空。
> 本工程的复现 TB（`sim/tb_v6_tail_bank.v`）之所以有效，就是因为它**故意不排空**，
> 并且在最后一个字中间掐住读出。详见 [05_验证与上板](../05_验证与上板/01_怎样写出能抓bug的testbench.md)。

---

## 7. 工具能帮多少：`report_cdc` 的真实读法

本工程 `build/cdc.rpt`（第五版，与第四版逐行相同）：

| 严重级 | 源时钟 | 目标时钟 | 端点数 | Safe | Unsafe | Unknown |
|--------|--------|----------|--------|------|--------|---------|
| Critical | sys_clk | eth_rxc | 1498 | 1003 | 2 | 493 |
| Critical | eth_rxc | clk_fpga_0 | 16 | 15 | 1 | 0（14 个无 ASYNC_REG） |
| Critical | clk_fpga_0 | clkout0_1 | 16 | 14 | 1 | 1 |
| Critical | eth_rxc | clkout0_1 | 33 | 0 | 16 | 17 |

怎么读这张表（很多人读错）：

- **"Critical" 不等于"错"**。它表示"这里发生了异步跨域，工具无法自动判定安全性"，需要**人**去确认。
- `Unknown` 多，通常是"跨域 FF 没打 `ASYNC_REG` 属性"或结构太绕；
  `Unsafe` 才是要盯的数（本工程 sys_clk→eth_rxc 有 2 个、两条 16 端点路径各 1 个）。
- 工程实践的正确姿势：**把基线记下来，要求每次改动"不新增 Unsafe / 不新增 Critical 行"**，
  而不是幻想把它清零。本项目的门禁就是这条（见 [10_报告怎么读](10_报告与门禁指标怎么读.md)）。

---

## 8. 自测

1. 为什么跨域传"单拍脉冲"不可靠，而传"电平翻转"可靠？
2. `dc_fifo` 的 `rd_empty` 为什么用格雷码比较而不是二进制计数比较？
3. 一个 32 位配置字从 100 MHz 域交给 50 MHz 域，给出两种可接受的方案，并说明各自的代价。
4. 第五版的帧尾 bug 属于"同步器写错"吗？它属于哪一类错误？用一句话概括可迁移教训。
5. `report_cdc` 里 493 个 `Unknown` 端点意味着什么？你会怎么处理（改代码 / 加属性 / 记录论证 / 忽略）？
