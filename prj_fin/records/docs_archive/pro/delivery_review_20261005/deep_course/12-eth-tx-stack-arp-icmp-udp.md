# 12 以太发送协议栈：ARP / ICMP / UDP 怎么拼出一帧，以及它为什么住在收侧的钟上

这一章讲发侧四件事：**报文怎么逐字节拼出来**、**两种校验和怎么算**、**三路发送口怎么被仲裁**、
**发送为什么由收侧事件触发**。每个数都来自我打开过的文件，标 `文件:行`；
我做过的算术会写出算式，我做不到的地方直接写"未量/未定"。

## 0 名字对照，以及"MAC 发送器"到底在哪个文件

| 任务里点的名字 | 仓里真实的位置 | 依据 |
| --- | --- | --- |
| `arp_tx.v` / `icmp_tx.v` / `udp_tx.v` | 同名，都在 `src/rtl/eth/` | — |
| `eth_mac_tx.v` | **没有这个文件**。MAC 发送职责被拆在两处：字节流装配在 `arp_tx.v`/`icmp_tx.v`/`udp_tx.v` 自己的 `gmii_tx_en`/`gmii_txd` 里，GMII→RGMII 的电气转换在 `src/rtl/eth/rgmii_tx.v:4`，三选一复用器在 `src/rtl/eth/eth_ctrl.v:43-44` | `rgmii_tx.v:1-3`、`eth_ctrl.v:1-2` |
| `eth_ctrl.v` | 同名：仲裁 + 双工转发 | `src/rtl/eth/eth_ctrl.v:1-2` |
| FCS 生成 | `src/rtl/eth/crc32_d8.v:1`（与收侧同一个核，约定见第 11 章 §3.4） | `arp.v:85-93`、`icmp.v:105-113`、`eth_udp_video_top.v:180-182` |

一个结构上的事实先摆出来：**本工程没有"独立 MAC 发送器"**。每个协议模块自己数自己的头部长度的常数
（`st_preamble` 数到 `cnt == 6'd7`、`st_eth_head` 数到 `cnt == 6'd13`、`st_ip_head` 数到 `cnt == 5'd6`），
自己把 FCS 拼在最后。`rgmii_tx.v` 只做 8→4 位双沿转换。
⇒ "MAC 层与协议层解耦"在这里不成立，这是本章所有取舍的前提。

---

## 1 前置知识

### 1.1 一帧的字节构成与最小帧约束

```
| 前导码 7×0x55 + SFD 0xD5 | DA 6 | SA 6 | Type 2 | 上层报文 … | FCS 4 |
        8 字节                 └─ 以太网头 14 字节 ─┘
```

最小帧 64 字节（含 FCS）⇒ **以太网头之后的部分至少 46 字节**。这条约束在本工程以两种形态出现：

- ARP：ARP 报文本身 28 字节 ⇒ 补到 46（`arp_tx.v:43` 的 `MIN_DATA_NUM = 16'd46`，
  计数到 `cnt == MIN_DATA_NUM - 1'b1` 才走 `st_crc`，`:230-238`）。
- ICMP/UDP：上层头占掉 20(IP) + 8(ICMP 或 UDP) = 28 ⇒ **数据段至少 46 − 28 = 18 字节**，
  这就是两处同名常量 `MIN_DATA_NUM = 16'd18` 的来历（`icmp_tx.v:53-55`、`udp_tx.v:45-47`）。

补位的内容不是 0：ICMP/UDP 填的是**最后一次发送的有效数据字节**（`icmp_tx.v:372-373` 的注释、
`tb_icmp_ping0.v` 的 T5 判据 `pad_first == last_data_byte`）。ARP 填的才是 0（`arp_tx.v:238`）。
两种都对——以太网只要求补齐到 64 字节，没规定填什么。

### 1.2 三种上层报文的字段（只列本设计真的写进字节流的那些）

**ARP（28 字节，`arp_tx.v:149-176` 的 `arp_data[0..27]`）**：
硬件类型 `0x0001`、协议类型 `0x0800`、HLEN=6、PLEN=4、OP（`0x0001` 请求 / `0x0002` 应答，
`:205-206` 按 `arp_tx_type` 写 `arp_data[7]`）、SHA/SPA/THA/TPA。
**注意所有多字节字段是大端**（数组 `[0]` 装最高字节，`:149-152`），
而 `BOARD_IP` 这个参数本身就是按字节拼的：`{8'd192, 8'd168, 8'd1, 8'd10}`（`arp_tx.v:27`）。

**IPv4 头（20 字节，装在 `ip_head[0..4]` + `ip_head[5][31:16]` 之前，`icmp_tx.v:242-254`）**：

| 字 | 内容 | 值（ICMP 应答 / UDP 发） | 行 |
| --- | --- | --- | --- |
| `ip_head[0][31:16]` | 版本 + IHL + TOS | `0x4500`（版本 4、IHL 5=20 B、TOS 0） | `icmp_tx.v:242` / `udp_tx.v:206` |
| `ip_head[0][15:0]` | 总长 | `total_num` = 载荷 + 28 | 同上（`:129` / `:100`） |
| `ip_head[1][31:16]` | 标识 | 每次发送 +1（自增寄存器） | `icmp_tx.v:244` / `udp_tx.v:208` |
| `ip_head[1][15:0]` | 标志 + 片偏移 | `0x4000` = bit15:13 = `010` = **不分片(DF)** | `icmp_tx.v:246` / `udp_tx.v:210` |
| `ip_head[2][31:24]` | TTL | **0x80 = 128**（ICMP） / **0x40 = 64**（UDP） | `icmp_tx.v:249` / `udp_tx.v:212` |
| `ip_head[2][23:16]` | 协议号 | **1 = ICMP**（`8'd01`） / **17 = UDP**（`8'd17`） | 同上 |
| `ip_head[2][15:0]` | 首部校验和 | 先写 `16'h0000` 占位，算完在 `st_check_sum` 末拍回填 | `icmp_tx.v:290` / `udp_tx.v:247` |
| `ip_head[3]` / `ip_head[4]` | 源 / 目的 IP | `BOARD_IP` / `des_ip`（为 0 时退回参数 `DES_IP`） | `icmp_tx.v:251-254` |

UDP 再往 `ip_head[5]`、`ip_head[6]` 塞 8 字节头：源/目的端口都写 **1234**（`udp_tx.v:219`）、
UDP 长度 = 载荷 + 8、**UDP 校验和写 `16'h0000`**（`udp_tx.v:220-221`）。
后者的语义要在协议层钉住才不会被读成"校验和算出来正好是 0"：IPv4 下 UDP 校验和字段为 0 表示
**不计算校验和**（`udp_tx.v:4` 的口径就是这个，`:220` 的注释写的也是这个）。

**ICMP 头（8 字节，装在 `ip_head[5][31:16]` 与 `ip_head[6]`，`icmp_tx.v:256-258`）**：
`{ECHO_REPLY, 8'h00}` = 类型 0 + 代码 0（`ECHO_REPLY = 8'h00` 在 `:59`），
`{icmp_id, icmp_seq}` 是从收侧原样回填的（`icmp.v:99-101` 把 `icmp_rx` 的两个输出直连给 `icmp_tx`），
校验和字段 `ip_head[5][15:0]` 由 `st_check_icmp` 回填（`icmp_tx.v:306`）。

⇒ `ip_head` 是一个 **7×32 位的数组**（`reg [31:0] ip_head[6:0]`，`icmp_tx.v:66`、`udp_tx.v:54`），
共 28 字节 = IPv4 头 + 上层头。**发的时候按 `tx_bit_sel` 把每个 32 位字拆成 4 个字节依次上线**，
这个拆法在第 3 节讲。

### 1.3 一补数校验和的数学（IPv4 首部与 ICMP 都用它）

定义：把参与校验的字节按 **16 位大端**两两配对，全部相加，每产生一次超出 16 位的进位就把进位
再加回低 16 位（"回卷加法"，end-around carry），最后**按位取反**写进字段。

为什么"折叠两次一定够"（这不是经验，是可证的界）：

- IPv4 首部固定 20 字节 ⇒ 10 个 16 位项 ⇒ 单项最大 65535 ⇒ 总和 ≤ **655350 = 0x9FFF6 < 2²⁰ = 1048576**。
  这一条界就写在寄存器注释里（`icmp_tx.v:75-79`，r112 那次把累加器从 32 位削到 20 位的依据），
  并且有判据把它钉住：`sim/tb_v112_ip_csum.v` 的 K2 判 `maxsum < 1048576`（"十项理论上限 655350"）。
  折叠 1：`hi + lo`，`hi ≤ 0x9F`、`lo ≤ 0xFFFF` ⇒ 结果 ≤ **0x10008**（17 位）；
  折叠 2：`hi ≤ 1` ⇒ 结果 ≤ **0xFFFF**，此后不会再有进位 ⇒ **两次是充分的**。
  RTL 正好折两次（`icmp_tx.v:283-286`；`udp_tx.v:240-243`），然后取反（`icmp_tx.v:290`）。
- ICMP 校验和的输入里有一个 **32 位、未折叠**的量 `reply_checksum`（见 §1.5），
  它的累加器是 32 位（`icmp_tx.v:81`）。任意 32 位值折叠一次 ≤ `0xFFFF + 0xFFFF = 0x1FFFE`，
  再折叠一次 ≤ `1 + 0xFFFE = 0xFFFF` ⇒ **同样两次够用**（`icmp_tx.v:298-301`）。

`st_check_icmp` 覆盖的范围也要说清：**ICMP 头 + 数据，不含 IPv4 头**（`icmp_tx.v:4-5`），
而 IPv4 头自己的 20 字节由 `st_check_sum` 负责。两把校验和、两个累加器、两个回填时刻。

一个常见误读要先堵掉：`ip_head[2][15:0]` 在求和时是 `0x0000`（占位），这**不是疏忽**，
而是一补数校验和的定义要求"被算的字段本身按 0 参与"。这条在 `sim/tb_icmp_tx_cksum.v` 的
判据 A1 里被独立复算了一次："把发出的 20 字节 IP 首部里校验和那两字节当作 0，
按 16 位大端拼字做反码求和（进位回卷），取反必须等于帧里那两字节"（`sim/tb_icmp_tx_cksum.v:14-15`）。

### 1.4 CRC-32 的反射，与发送侧那个"下一拍"的问题

第 11 章 §1.6 已经钉住 `crc32_d8` 的寄存器值 = 标准反射 CRC 的 **32 位逐位镜像**
（`src/rtl/eth/crc32_d8.v:18` 的先验位反转 + `:23-81` 的异或式）。发侧要的是"把 FCS 按线上顺序摆好"，
于是每个 FCS 字节都要再做一次**字节内位反转**再取反——RTL 里那四段八行的
`{~crc_next[0], ~crc_next[1], …, ~crc_next[7]}`（`arp_tx.v:244-253`、`icmp_tx.v:392-401`）
看着啰嗦，其实就是 `~rev8(byte)`，写不开是因为综合器对下标反转更直白。

另一半才是真难点：**FCS 的第一个字节不能用 `crc_data`，必须用 `crc_next`**。
原因是节拍差一拍。逐拍摆一遍（`clk` = 8 ns，寄存器语义）：

```
周期 K   ：FSM 在 st_tx_data 的最后一拍赋值 gmii_txd <= 最后一个数据字节、crc_en <= 1
周期 K+1 ：线上 = 最后一个数据字节；crc_en=1 ⇒ 这个字节在 K+1 结束时才被 crc_data 吸收
           同拍 FSM（next_state 已是 st_crc，tx_bit_sel==0）要给出 FCS[0]
           此刻 crc_data 还没含最后一个字节 ⇒ 只能用 crc_next = f(crc_data, 线上那个字节)
周期 K+2 ：crc_data 已含全部数据；FCS[1] 用 crc_data[23:16]
周期 K+3 ：FCS[2] 用 crc_data[15:8]
周期 K+4 ：FCS[3] 用 crc_data[7:0]
```

而且 `crc_en` 在这四个周期都是 0（每个 always 分支开头默认清零，`icmp_tx.v:234`），
所以 `crc_data` 从 K+2 起就**静止**，后三个字节读的是同一份状态（`:402-434`）。

端口宽度也值得注意：发给协议模块的 `crc_next` 只有 8 位，
顶层与两个包装层给的都写着 **`crc_next[31:24]`**（`src/rtl/eth/arp.v:76`、
`src/rtl/eth/icmp.v:92`、`src/rtl/eth/eth_udp_video_top.v:172`）。
于是 `~crc_next[0..7]` 反转的是"下一拍状态的最高字节"。`crc_data[31:24]` 在整个 FCS 序列里
**一次都没出现**（`:402-434` 只有 23:16 / 15:8 / 7:0）。

我把这条链算过一遍（用一份独立实现：JS 的 `0xEDB88320` 表算法 + 逐位复抄 `crc32_d8.v:23-81` 的
32 个异或式，按上面的节拍模型算出四字节的 FCS）：两帧的结果都是
**发出的四字节 == 标准算法要求的四字节**，且把"消息 + 这 4 字节"再过一遍本核得到的末态是
`32'hC7_04_DD_7B`——正是收侧 `gmii_rx_mac.v:23` 那个常数。⇒ 发出去的 FCS 是真的合规，
而且收发两侧在这一处**互为对照**：本设计的收侧能验自己的发侧。

### 1.5 因果：发侧为什么要和收侧同一颗钟

发侧三样东西**直接来自收侧寄存器的电平**，没有任何一手跨域：

| 量 | 宽度 | 谁写的 | 谁在什么时候读 |
| --- | --- | --- | --- |
| `src_mac` / `src_ip` | 48 / 32 | `arp_rx` 命中 ARP 时（`src/rtl/eth/arp_rx.v:157-158`） | `st_idle` 装配那一刻读（`icmp_tx.v:253`、`arp_tx.v:187-203`） |
| `icmp_id` / `icmp_seq` | 16 / 16 | `icmp_rx` 在 ICMP 头第 4..7 字节采（`src/rtl/eth/icmp_rx.v:242-246`） | `st_idle` 写进 `ip_head[6]`（`icmp_tx.v:258`） |
| `reply_checksum` | **32 位未折叠** | `icmp_rx` 把请求载荷按 16 位成对累加（`icmp_rx.v:285-295`，收满一帧在 `st_rx_end` 落到输出口 `:310`） | `st_check_icmp` 第一拍作为一个加数（`icmp_tx.v:296-297`） |

外加一条数据面：请求的**字节本身**存在 `sync_fifo`（`eth_udp_video_top.v:119-124`），
读使能就是 `icmp_tx` 的 `tx_req`。`sync_fifo` 只有一个 `clk` 口（`sync_fifo.v:9`），是同时钟 FIFO——
它能被这么用的唯一前提就是收发同域。
⇒ **这三样都跨不了域**：48 位/32 位的准静态总线要跨域得配握手或快照（第 11 章 §3.7 那两套），
`reply_checksum` 是 32 位总线不能靠"打两拍"。这是"发侧在 RXC 域"这件事的功能性理由，
不是图省事（代价见 §4.1）。

---

## 2 原理拆解：把节拍、算术与延迟算出来

### 2.1 一次 ping 应答占多少拍、多少纳秒

`icmp_tx` 的 8 个状态（`icmp_tx.v:41-48`，one-hot，`cur_state` 是 8 位寄存器 `:62`）逐个数拍：

| 状态 | 拍数 | 依据 |
| --- | --- | --- |
| `st_idle` 命中 `trig_tx_en` | 1 | 单拍置 `skip_en` 并把首部装配进数组（`:239-270`） |
| `st_check_sum` | 5 | `cnt` 0..4 五个分支：两拍求和 + 两拍折叠 + 一拍回填（`:277-291`） |
| `st_check_icmp` | 4 | `cnt` 0..3：一拍求和 + 两拍折叠 + 一拍回填（`:295-307`） |
| `st_preamble` | 8 | `cnt == 5'd7` 才走（`:312-315`） |
| `st_eth_head` | 14 | `cnt == 5'd13`（`:321-324`） |
| `st_ip_head` | 28 | 7 个 32 位字 × 4 个 `tx_bit_sel` 相位（`:330-343`） |
| `st_tx_data` | `max(tx_byte_num, 18)` | 有效数据 + 补位（`:359-382`） |
| `st_crc` | 4 | `tx_bit_sel` 0..3（`:391-437`） |

请求 8 字节载荷的 ping（`sim/tb_icmp_ping0.v` 的 T2 用的就是这一档）：
数据段 = `max(8, 18) = 18` ⇒ 总拍数 `1+5+4+8+14+28+18+4 = 82 拍 = 656 ns`；
上线字节数 `8 + 14 + 28 + 18 + 4 = 72 字节`。
56 字节载荷：数据段 = 56 ⇒ `120 拍 = 960 ns`、`110 字节`。

**72 / 110 这两个数不是我的推算独证**：台架也采到同样的长度——
`sim/tb_v112_tx_bytes.v` 把"发出去的 72 个字节逐字节打全"当等价凭据（`icmp_tx.v:78-79`），
`tb_icmp_tx_cksum` 的四个场景整帧字节流记的是 `72/110/72/72`
（`docs/course/04-rgmii-rx-frame-reassembly.md:169`）。三条对上 ⇒ 节拍表可信。

ARP 应答：`1 + 8 + 14 + 46 + 4 = 73 拍 = 584 ns`、上线 `8+14+46+4 = 72 字节`
（`arp_tx.v` 的 `st_idle`/`st_preamble`/`st_eth_head`/`st_arp_data`/`st_crc`，`:183-291`）。
注意 ARP **没有** `st_check_sum`/`st_check_icmp`：ARP 不经 IP，没有一补数校验和（`arp.v:2-3` 明写）。

### 2.2 校验和锥现在是全设计 `eth_rxc` 组最差那条路

实现后报告的原文（`build/timing_summary.rpt:365-374`）：

| 项 | 读数 |
| --- | --- |
| Slack | 0.739 ns（**MET**，本族最差） |
| Source | `u_eth/u_icmp/u_icmp_tx/ip_head_reg[4][16]/C` |
| Destination | `u_eth/u_icmp/u_icmp_tx/check_buffer_reg[19]/D` |
| Data Path Delay | 7.066 ns = 逻辑 2.936 ns（**41.553 %**）+ 布线 4.130 ns（**58.447 %**） |
| Logic Levels | **11**（`CARRY4=6` `LUT3=2` `LUT4=2` `LUT5=1`） |
| 该域端点 | setup 4835 / WNS 0.739 / WHS 0.052 / 失败端点 0（`build/timing_summary.rpt:182`） |

起点是"装配好的 IP 首部寄存器"，终点是"校验和累加器"。
⇒ **发侧协议栈里那把 10 项加法，此刻正是这颗 125 MHz 时钟上最紧的一条路**。
为什么紧：十个 16 位项**分散在 5 个不同的 `ip_head` 字寄存器里**（`icmp_tx.v:278-282`），
要先把它们从各自的位置布线到一处，再进 6 级进位链。逻辑 2.936 ns 是加法本身，
布线 4.130 ns 是"读一整排分散各处的寄存器"的代价——这条读法在
`docs/course/04-rgmii-rx-frame-reassembly.md:120-124` 有对照分析（与 `verilog-ethernet` 的
`udp_checksum_gen` 相比，真正的差别不在加法宽度，而在要不要临发前重读整份首部）。

### 2.3 为什么 `st_check_sum` 现在占 5 拍而不是 3 拍

`:274-276` 的注释记录了 r108 那一刀：原来这一拍要加 10 个 16 位项，综合摆出 5 级 CARRY4，
是 r106 报告里那条 10 级 / 0.741 ns 的路的形状来源；于是**摊成两拍各 5 项**，
理由写得清楚："和不截断（10 项 ≤ 655350，20 位够，目标寄存器 32 位），
折叠次序一字不改，代价是这个状态多占一拍"。

对照 `udp_tx`：同一个和**仍然一拍算完 10 项**（`udp_tx.v:236-239`），
`st_check_sum` 只有 4 拍（`:236-248`）。⇒ 同一族算术在两个模块里有两种节拍分配，
这就是 §4.2 那条对照的实物。

`icmp_tx` 的分配细节（`:277-291`）：
```verilog
if (cnt == 5'd0) check_buffer <= ip_head[0][31:16] + ip_head[0][15:0] + ip_head[1][31:16] +
                               ip_head[1][15:0] + ip_head[2][31:16];                     // 5 项
else if (cnt == 5'd1) check_buffer <= check_buffer + ip_head[2][15:0] + ip_head[3][31:16] +
                                    ip_head[3][15:0] + ip_head[4][31:16] + ip_head[4][15:0];  // 5 项
else if (cnt == 5'd2) check_buffer <= check_buffer[19:16] + check_buffer[15:0];          // 折叠 1
else if (cnt == 5'd3) check_buffer <= check_buffer[19:16] + check_buffer[15:0];          // 折叠 2
else if (cnt == 5'd4) begin skip_en<=1; cnt<=0; ip_head[2][15:0] <= ~check_buffer[15:0]; end  // 回填
```
第二拍的被加数 `check_buffer` 已经含前 5 项——**依赖是真的**，所以两拍不可交换。
折叠那两拍读的都是 `check_buffer[19:16]` 与 `[15:0]`，第二拍的输入是第一拍的输出。
回填取 `[15:0]`：折叠 2 之后高 4 位必为 0（§1.3 的界），所以取低 16 位就是最终和。

### 2.4 20 拍的回程延迟与三条边沿检测

`icmp_rec_pkt_done` 不直接触发发送，而是装一个倒计数器：
```verilog
if (icmp_rec_pkt_done) begin icmp_dly <= 6'd20; icmp_tx_byte_num <= icmp_rec_byte_num; end
else if (icmp_dly != 0) begin icmp_dly <= icmp_dly - 1'b1; if (icmp_dly == 6'd1) icmp_tx_start_en <= 1'b1; end
```
（`src/rtl/eth/eth_udp_video_top.v:101-107`，时钟是 `gmii_rx_clk`，`:96`）
⇒ `icmp_tx_start_en` 恰好在请求收完后 **20 拍 = 160 ns** 出现，**宽度正好 1 拍**。

`icmp_tx` 那侧还要过一层三拍移位（`start_en_d0/d1/d2`，`icmp_tx.v:103-113`）：
`pos_start_en = (~start_en_d2) & start_en_d1`（`:99`）是**上升沿脉冲**；
再一拍变 `trig_tx_en`（`:139-143`）才用于状态机。
⇒ 从 `rec_pkt_done` 那一拍到 `st_idle` 分支真的执行 `trig_tx_en` 那一拍，逐级数是
`1`（装 `icmp_dly`）`+ 20`（倒数）`+ 2`（移位后出 `pos_start_en`）`+ 1`（`trig_tx_en` 生效）= **24 拍 ≈ 192 ns**；
再下一拍 `skip_en` 才把状态推走。
三拍移位存在的理由和 ARP 那侧一样：**把外部使能当异步电平处理之前先在本域打两拍**，
即便同域也保留了这套写法（`arp_tx.v:63` 与 `:66-76` 是同一手法）。

ARP 那条链上没有倒计数器，只有一张账：
`arp_rx_flag` 单拍（`eth_ctrl.v:131-135`）→ `arp_pend` 记账（`:142-163`）→
等 `udp_tx_busy==0 && icmp_tx_busy==0` 才兑现（`:155-160`）。
⇒ 兑现时刻是**不确定的**，取决于在途帧什么时候结束；这是刻意的（§4.6）。

### 2.5 "发侧在收侧的钟上"的三条物证

1. 连线：`assign gmii_tx_clk = gmii_rx_clk;`（`src/rtl/eth/gmii_to_rgmii.v:25`）。
2. 布线后网表里的时钟网名：全设计最差那条路的起点 `u_icmp_tx` 的 C 脚吃的时钟网叫
   **`u_eth/u_icmp/u_icmp_tx/gmii_rx_clk`**，扇出 `fo=2546`（`build/timing_summary.rpt:393`），
   驱动者是 `u_eth/u_rgmii/u_rgmii_rx/BUFG_inst/O`（`:392`，`src/rtl/eth/rgmii_rx.v:51` 那一只）。
   ⇒ 这不是"文档这么说"，是实现后报告里写着的名字。
3. `eth_ctrl` 的文件头把它讲成一条纪律而非疏漏：
   "这不是漏了同步——RGMII 下 `gmii_tx_clk` 就是 `gmii_rx_clk` 本身（见 `gmii_to_rgmii` 的 assign），
   所以三路发送字节与本域同拍，全 ETH 逻辑实际是**单时钟域**"（`src/rtl/eth/eth_ctrl.v:3-4`）。

发出去的时钟 `rgmii_txc` 同样直接等于 `gmii_tx_clk`（`src/rtl/eth/rgmii_tx.v:16`），
而顶层把它接到引脚 `eth_tx_clk`（`eth_udp_video_top.v:78` 的 `.rgmii_txc(rgmii_tx_clk)` 与
`system_top.v:182`）。⇒ **本板送给 PHY 的 TXC 就是 PHY 收回来的 RXC**。
这条的工程含义：只要链路断到没有 RXC，发侧连同 TXC 一起停摆——
今天唯一能声明"TXC 与 5 根发线没有时序关系"的，是约束本身：
`set_false_path -to` 打在 `eth_tx_clk`、`eth_tx_ctl`、`eth_txd[*]` 上
（`src/constraints/rk_zynq7020.xdc:56-58`），而这三行"当初理由"在仓里**没有写**，
已被登记为待复核债务（`时序债务账` §3 表里那行"警告 待复核债务"）。

---

## 3 代码逐段分析

### 3.1 `eth_ctrl.v`：三选一的复用器与一条会丢请求的老写法

**输出复用**（`:89-110`）：`protocol_sw` 是 2 位寄存器，选 `arp_gmii_*` / `udp_gmii_*` / `icmp_gmii_*`
之一，并且**再寄存一拍**才出 `gmii_tx_en`/`gmii_txd`（`:94-107`）。
`2'b00` = ARP、`2'b01` = UDP、`2'b10` = ICMP（`:1-2`）。

**仲裁**（`:142-165`），三条分支的优先级是 UDP > ICMP > ARP-记账：
```verilog
arp_tx_en <= 1'b0;
if (udp_tx_start_en)                protocol_sw <= 2'b01;
else if (icmp_tx_start_en)          protocol_sw <= 2'b10;
else if (arp_pend && !udp_tx_busy && !icmp_tx_busy) begin
    protocol_sw <= 2'b0; arp_tx_en <= 1'b1; arp_pend <= 1'b0;
end
if (arp_rx_flag) arp_pend <= 1'b1;      // 记账放在最后
```
两处细节各钉一个真实缺陷：
- `:156-157` 记的是原来两个 busy 用 `||` 连（"任一空闲"）⇒ 会在**帧中间**把 mux 切给 ARP，
  正在发的那帧剩下的字节就地作废。要的是"全部空闲"。
- `:139-141` 记的是"记账与兑现必须在同一个 always 里"：`arp_pend` 单独一块、用
  `else if (arp_tx_en)` 清账时读到的是**上一拍**的 `arp_tx_en`（非阻塞赋值），
  结果 `arp_tx_en` 连高两拍、ARP 帧第 0 字节被**重发一次**。
  同一条注释还提醒"修 bug 不能只改符号"：原来只有一拍宽的 `arp_rx_flag`，
  把那条 OR 改成 `&&` 之后请求会在"另一路正在发"的那一拍被**丢掉**（PC 要等 ARP 超时重发）。
- `:162-163` 的"记账放最后"处理同拍"兑现旧账 + 又来新请求"：新请求不会被这次授权吃掉。

**忙标志**（`:112-128`）：`*_tx_start_en` 置忙、`*_tx_done` 清忙。二者都是单拍 ⇒ 靠的是
`st_crc` 末尾那拍（`:287-289` 之类）产生的 `tx_done`。

**收侧转发**（`:71-86`）：`icmp_rec_en` 优先于 `udp_rec_en` 决定 `rec_en`/`rec_data`。
**读法要精确**：这是 `else if`，两个源**同时**有效时 UDP 那字节这一拍被丢掉；
而 UDP 分支的 `else` 是 `rec_data <= rec_data`（保持旧值），只把 `rec_en` 清 0（`:82-85`）。
本设计里这条转发**无人消费**——顶层的 `fifo_rec_en`/`fifo_rec_data` 是两条死线
（`eth_udp_video_top.v:114-116` 声明、`:219-220` 连出，再没有第二处使用）。

**数据回读**（`:55-58`）：`tx_req = udp_tx_req ? 1 : icmp_tx_req`；
`icmp_tx_data = icmp_tx_req_d0 ? tx_data : 8'd0`（UDP 同形）。`*_tx_req_d0` 是请求的**一拍延迟**
（`:60-69`），配合同步 FIFO"这拍打请求、下一拍 `rd_data` 才有效"的节拍。
⚠ 但顶层**没有把 FIFO 接到这两个口**：`icmp_tx` 的 `tx_data` 直接吃
`u_icmp_fifo` 的 `rd_data`（`eth_udp_video_top.v:148` 的 `.tx_data(icmp_fifo_q)`），
所以 `icmp_tx_data`/`udp_tx_data` 这两个口在板上是空转的（`:214` `.icmp_tx_data()`、
`:218` `.udp_tx_data()` 都悬空）。**读 `eth_ctrl` 时别把这条当成数据通路。**

### 3.2 `arp_tx.v`：数组装配 + 五个 one-hot 状态

状态定义是 5 位 one-hot（`arp_tx.v:34-38`：`st_idle`/`st_preamble`/`st_eth_head`/`st_arp_data`/`st_crc`），
三段式：`cur_state <= next_state`（`:79-82`）、组合 `next_state`（`:85-110`，每态只认 `skip_en`）、
输出级用 `case (next_state)`（`:182`）。

**`case (next_state)` 这个写法要读明白**，否则会以为少了一拍：输出级用的是**下一态**，
所以某态的动作在"`cur_state` 还是上一态"的那一拍就执行，赋的值在该态真正生效的那个周期上线。
`st_preamble` 那 8 拍里，第一个字节在 `cur_state` 还是 `st_idle` 的下一拍就已被赋值。
效果是每个状态的动作恰好执行一次、每个状态占满自己该有的拍数（§2.1 的拍数表就是按这个读法数的）。

**默认清零**（`:178-181`）：`skip_en`/`crc_en`/`gmii_tx_en`/`tx_done_t` 每拍先清 0，
分支里再置 1 ⇒ 它们都是单拍脉冲。这一条把"帧间空隙"变成物理必然——
`gmii_tx_en` 在 `st_crc` 之后必然落下，收侧 `gmii_rx_mac` 那种"`dv` 掉下来算帧尾"的判据才成立。

**数组**（`:48-50`）：`preamble[7:0]`、`eth_head[13:0]`、`arp_data[27:0]` 全是 `reg [7:0]` 数组，
复位分支里一次性写死（`:124-176`）。**这些是触发器，不是 ROM**：
8+14+28 = 50 字节 = 400 只 FF。之所以必须是可写的 FF，是因为发送前要改
目的 MAC/IP/OP 三处（`:188-206`）。

**只在 `pos_tx_en` 那一拍装配**（`:184-207`）：
`if ((des_mac != 48'b0) || (des_ip != 32'd0))` 才更新 `eth_head[0..5]`、`arp_data[18..23]`、
`arp_data[24..27]`；`arp_data[7] <= arp_tx_type ? 8'h02 : 8'h01`。
装配发生在真正发送前的若干拍（中间隔着 `st_preamble` 的 8 拍），所以**没有读写冲突**。

**补齐到 46**（`:226-239`）：
```verilog
if (cnt == MIN_DATA_NUM - 1'b1) begin skip_en<=1; cnt<=0; data_cnt<=0; end else cnt <= cnt + 1'b1;
if (data_cnt <= 6'd27) begin data_cnt <= data_cnt + 1'b1; gmii_txd <= arp_data[data_cnt]; end
else gmii_txd <= 8'd0;
```
`data_cnt` 是 5 位（`:56`），到 28 之后条件恒假、**自己就不涨了**，
所以不会绕回 0 重发 `arp_data[0]`。这一处值得盯一眼是因为比较写成了
`data_cnt <= 6'd27`（5 位对 6 位常量），靠的是工具把短操作数零扩展——
功能正确但可读性差，`arp_data` 28 项这个事实应该由 `localparam` 说而不是由魔法数 27 说。

**FCS 四拍**（`:240-291`）与 §1.4 的节拍模型一致，只是 `st_crc` 用的是 6 位 `cnt`
（ICMP/UDP 用的是 `tx_bit_sel` 的 2 位，`icmp_tx.v:391-437`）；`cnt==3` 那拍同时
置 `tx_done_t` 与 `skip_en` 并把 `cnt` 归 0（`:287-289`）。

**`tx_done` 与 `crc_clr` 同生**（`:298-306`）：`tx_done <= tx_done_t; crc_clr <= tx_done_t;`
⇒ CRC 核在最后一字节发完的**下一拍**清成 `0xFFFFFFFF`（`crc32_d8.v:85-86` 里 `crc_clr`
优先于 `crc_en`）。这一拍序不能换：先发完再清，否则上一帧的尾巴会串进下一帧的 CRC。

### 3.3 `icmp_tx.v`：多出来的两个校验和状态，与三条计数

**`st_idle` 装配**（`:238-271`）：把 §1.2 那张表逐字写进 `ip_head[0..6]` 与 `eth_head[0..5]`。
两处细节：
- `ip_head[1][31:16] <= ip_head[1][31:16] + 1'b1;`（`:244`）——标识字段自增，
  而复位分支只清了 `ip_head[1][31:16] <= 16'd0`（`:196`）。
- `des_ip`/`des_mac` 为全 0 时**退回参数默认值**（`:253-254`、`:261-269`）。
  这个退路是有理由的：`src_ip`/`src_mac` 在收到第一个 ARP 之前就是 0
  （`arp_rx.v:96-97` 复位为 0），而第一帧应答很可能就在这个窗口里。

**`st_tx_data` 的三条计数**（`:346-386`）——这一段的正确性全靠"减一/减二"的错位配合，
必须一条条读：
```verilog
if (tx_data_num == 16'd0) begin … 补位/收束 … end                 // :359  #188 的零载荷支
else if (data_cnt < tx_data_num_m1) data_cnt <= data_cnt + 1;      // :370  数到 len-1
else if (data_cnt == tx_data_num_m1) begin                        // :371  进补位
    if (data_cnt + real_add_cnt < real_tx_m1) real_add_cnt <= real_add_cnt + 1;
    else begin skip_en<=1; data_cnt<=0; real_add_cnt<=0; tx_bit_sel<=0; end
end
if (data_cnt == tx_data_num_m2) tx_req <= 1'b0;                   // :384  提前停读
```
- `tx_data_num_m1 = len-1`、`tx_data_num_m2 = len-2`、`real_tx_m1 = max(len,18)-1`
  都在 `pos_start_en && cur_state==st_idle` 那一拍**预先算好**（`:125-134`）。
  这就是 #141 那次"隔离测量"的内容：把 `st_tx_data` 里三条 16 位减法挪到写入 `tx_data_num` 的那一拍
  （`:87-93` 的注释写明等价性靠两件事担保：`tx_data_num` 只在复位与那一拍被写；
  而 `st_tx_data` 最早也在几十拍之后才进），并且"合法路径一字未动"由
  `sim/tb_icmp_ping0.v` 的 T2/T3/T5 钉住。
  复位值不是 0 而是 `16'hFFFF`/`16'hFFFE`/`MIN_DATA_NUM-1`（`:120-123`），
  注释解释这是"把 `tx_data_num = 0` 代回那三条减法（16 位里回绕），与改前逐位同值"。
- `tx_req <= 1'b0` 提前**一拍**停读：请求拉高一拍、FIFO 输出晚一拍，
  所以最后一个字节仍然被发出去。节拍我在 §1.4 之外再走一遍（4 字节载荷）：
  `st_ip_head` 里 `cnt==6 && tx_bit_sel==2` 那拍置 `tx_req <= 1'b1`（`:332-337`，
  注释"提前读请求数据，等待数据有效时发送"）⇒ 请求在 `st_ip_head` 最后一拍为高，
  该拍 FIFO 弹出 byte0，于是 `st_tx_data` 第一拍 `gmii_txd <= tx_data` 拿到的正是 byte0；
  之后 `data_cnt` 走到 `len-2` 的那拍把 `tx_req` 清掉，最后一个字节因为那一拍又弹了一次而不丢。

**零载荷支（#188，板上真踩过）**（`:351-369`）：
```verilog
if (tx_data_num == 16'd0) begin
    tx_req <= 1'b0;
    if (real_add_cnt < real_tx_m1) real_add_cnt <= real_add_cnt + 5'd1;
    else begin skip_en<=1; data_cnt<=0; real_add_cnt<=0; tx_bit_sel<=0; end
end
```
`:351-358` 把病因写全了：`tx_data_num == 0` 时（`ping -l 0` 的回复就是这个），
`tx_data_num - 16'd1` 在 16 位里回绕成 65535 ⇒ 第一个条件对 `0..65534` **恒真**，
机器一路发 **65536** 个数据字节，而 `total_num` 自己声明的是 28 字节 ⇒
一个自相矛盾的畸形巨帧，还把 TX mux 占住约 0.52 ms。
（0.52 ms 的来源：65536 拍 × 8 ns ≈ 0.524 ms，与注释同量级。）
修法只加这一支、**下面那一串一个字没动**，判据是 `sim/tb_icmp_ping0.v` 的 T1（`cyc_data == 18`，
改前是 65536）、T4a（反空转：必须真的进过 `st_tx_data` 且 `tx_done` 恰好一次）、
T2/T5（8 字节仍补到 18 且补位值 == 最后一个载荷字节）、T3（56 字节不补位也不少发）。
改前红凭据 `build/r98_188_before.txt`（在盘上，我确认过存在）。

**同一族的收侧半边（#218）**要放在一起看才有意义：`ping -l 0` 在收侧同样是合法的 28 字节 IP 总长，
`icmp_rx` 用一个旗标接住它：`data_len_zero <= (total_length == 16'd28);`（`src/rtl/eth/icmp_rx.v:210`，
声明在 `:51-52`），`st_rx_data` 进来就当拍收束（`:261-274`）。
`:104-109` 又补了另一条出路：`else if (!gmii_rx_dv) next_state = st_rx_end;`——
线在数满之前空下来（**截断帧**，或声明长度比实到大）就作废这一包并回 idle。
`:105-107` 写的后果是板上实测的：这一态原来只有 `skip_en` 一条出路 ⇒
**一条 0 字节请求让应答器永久变哑**，直到重配 PL（逐轮曲线 `build/r101_216_deathpoint.txt`，
改前红凭据 `build/r102_218_before.txt` 的 K1..K4，两支件我都在盘上确认存在）。
下界守卫也在同一处：`if (total_length < 16'd28) error_en <= 1'b1`（`:201-203`，#206），
拦的是 `< 28` 那一族回绕（`65516` 那种），与 `== 28` 是**两个不同的洞**，
分别由 `sim/tb_icmp_len_wrap.v` 与 `sim/tb_icmp_ping0.v` / `sim/tb_icmp_rx_len.v` 的 K/L 族钉住。

**`st_crc`**（`:387-438`）与 §1.4 的节拍模型一致；`tx_bit_sel` 在这里继续 +1（`:389`），
所以四拍正好走完 0..3，第四拍置 `tx_done_t` 与 `skip_en`。`tx_req` 在这一态被强制清 0（`:390`）。

### 3.4 `udp_tx.v`：形状与 ICMP 同源，两处不同

七个状态（`:36-42`，比 ICMP 少 `st_check_icmp`），`st_check_sum` 是**一拍十项**（`:236-239`）
+ 两拍折叠（32 位口径 `[31:16] + [15:0]`，`:240-243`）+ 一拍回填。
`ip_head[5]`/`ip_head[6]` 装 UDP 头（`:219-221`）。

**同一族的零长度缺陷在这里没有被修**：`st_tx_data` 用的还是
`if (data_cnt < tx_data_num - 16'd1)` / `else if (data_cnt == tx_data_num - 16'd1)` /
`if (data_cnt == tx_data_num - 16'd2) tx_req <= 1'b0;`（`:292-306`），
没有 `icmp_tx.v:359` 那条 `tx_data_num == 16'd0` 的分支。
⇒ `tx_data_num == 0` 在这份代码里同样会数到 65535。今天它不可达，因为顶层把
`.tx_start_en(1'b0)` 硬接（`eth_udp_video_top.v:166`，注释 `:158` 写的就是
"发侧维持今天的状态（`tx_start_en` 恒 0，Z7 上 UDP 发送接着但没人启动）"），
`pos_start_en` 恒 0（`udp_tx.v:73`）⇒ `tx_data_num` 恒 0 且 FSM 永远停在 `st_idle`。
**但只要有人把 `tx_start_en` 接上，这个洞就是现成的**——这条要写下来，
因为"`udp_tx` 没被启动"和"`udp_tx` 是安全的"不是同一句话。

### 3.5 三处 `crc32_d8` 的发送侧接法

| 例化 | 时钟 | `data` 从哪来 | `crc_en`/`crc_clr` 从哪来 | FCS 口 |
| --- | --- | --- | --- | --- |
| `arp.v:85-93` | `gmii_tx_clk` | `crc_d8 = gmii_txd`（`:43`，就是本模块吐出去的字节） | `arp_tx` 的 `crc_en`/`crc_clr`（`:80-81`） | `crc_next[31:24]` 给 `arp_tx`（`:76`） |
| `icmp.v:105-113` | `gmii_tx_clk` | `crc_d8 = gmii_txd`（`:53`） | `icmp_tx` | `crc_next[31:24]`（`:92`） |
| `eth_udp_video_top.v:180-182` | `gmii_tx_clk` | `crc_d8 = udp_gmii_txd`（`:161`） | `udp_tx` | `crc_next[31:24]`（`:172`） |

**每条发路有自己的 CRC 核，输入就是"线上正在出的那一路字节"**。
这是 V7.9.6 的口径（`eth_udp_video_top.v:113` 的注释与 `arp.v:2-3`）：
FCS 覆盖"该源自己发出的字节"，因此 `eth_ctrl` 的三选一 mux 怎么切都不会让 CRC 与字节错位。

覆盖范围由 `crc_en` 的位置决定：只在 `st_eth_head` 起置 1
（`arp_tx.v:219`、`icmp_tx.v:319`、`udp_tx.v:260`）⇒ **前导码与 SFD 不进 CRC**，
这正是 §1.1 那个"以太网头之后"的覆盖定义。
`st_preamble` 那 8 拍里 `crc_en` 一直是默认 0。

`udp.v` 这个包装层**在收侧改造时被拆掉了**（`eth_udp_video_top.v:154-158`：
原来例化厂商 `udp` 包装，`udp_rx` 不看帧长也没有错误标志 ⇒ `p_good` 只能硬接 1），
只剩 `udp_tx` 直接例化 + 顶层自己挂一份 CRC 核。

### 3.6 `rgmii_tx.v`：GMII → RGMII 的电气转换

`rgmii_txc` 直出（`rgmii_tx.v:16`）；`rgmii_tx_ctl` 由一只 ODDR 送（`:19-31`），
`D1` 和 `D2` **接同一个 `gmii_tx_en`** ⇒ 两个沿同送一个有效标志（`:27-28`，
这正是 RGMII 的要求：DV 在两个沿上都必须有效）。
四根数据各一只 ODDR（`:41-49`）：`.D1(gmii_txd[i])`（正沿，字节低位）、
`.D2(gmii_txd[4+i])`（负沿，字节高位）——与收侧 `rgmii_rx.v:133-134` 的映射**严格互逆**。
`DDR_CLK_EDGE` 用 `"SAME_EDGE"`（`:20`、`:38`）而不是收侧那种 `_PIPELINED`，
因为发送侧要的是"两个沿各拿一个 nibble、无额外流水"。

### 3.7 两条因果链走到底

**ping**（全部在 `eth_rxc`/`gmii_rx_clk` 这一颗 125 MHz 上，一拍不差）：

```
PC 发 echo request
  → rgmii_rx → gmii_rx_mac（算 FCS 出 m_good）
  → icmp_rx：采 icmp_id/icmp_seq（:242-246）、按对累加 reply_checksum（:285-295）、
              rec_byte_num = icmp_data_length（:303）、rec_en 逐字节把请求载荷写进 u_icmp_fifo
              （eth_udp_video_top.v:119-124）
  → rec_pkt_done（:269 或 :302）
  → top：icmp_dly <= 20；icmp_tx_byte_num <= icmp_rec_byte_num（:101-103）
  → 20 拍后 icmp_tx_start_en 一拍（:106）
  → eth_ctrl：protocol_sw <= 2'b10；icmp_tx_busy <= 1（:116、:153-154）
  → icmp_tx：三拍边沿检测 → 装配 → 两把校验和 → 8+14+28+data+4 上线
  → tx_done → icmp_tx_busy 清 0（:117）
  → eth_ctrl 的 mux 交还，gmii_tx_en 落下 → rgmii_tx → 引脚
```

ARP 的目的地址**不是从 ping 包里来的**：`icmp` 例化的 `des_mac/des_ip` 接的是
`src_mac/src_ip`（`eth_udp_video_top.v:150`），而那两个寄存器只有 `arp_rx` 会写
（`arp_rx.v:157-158`）。⇒ **是 PC 先发的那条 ARP 请求教会了板子"回给谁"**。
这也解释了 `arp_tx` 与 `icmp_tx` 里那些 `des_mac != 0` / `des_ip != 0` 的退路（`arp_tx.v:187`、
`icmp_tx.v:253`、`:261`），以及 `ping` 之前必须先 ARP 可达这条验收顺序
（`board/hardware_setup.md:53`：C9 那一格说"`ping 192.168.1.10` 能通再推流——
通不通由 PL 里的 ICMP 应答决定，所以这一步同时验了位流"）。

**ARP 请求**：`arp_rx_done && arp_rx_type==0` → `arp_rx_flag`（`eth_ctrl.v:133`）→ `arp_pend`（`:163`）
→ 等两路 busy 都是 0 → `arp_tx_en` 恰好一拍（`:155-160`）→ `arp_tx` 的 `pos_tx_en`
→ 应答里 `arp_data[7] = 8'h02`（`arp_tx.v:205-206`，`arp_tx_type` 由
`eth_ctrl.v:55` 的 `assign arp_tx_type = 1'b1` 固定为"应答"）。
⚠ 顶层还有一处同一个决定的第二份写法：`.arp_tx_type(1'b1)` 直接硬连在
`arp` 的端口上（`eth_udp_video_top.v:135`），而 `eth_ctrl` 的那条 `arp_tx_type` 输出悬空
（`:209` `.arp_tx_type()`）。⇒ "只应答不请求"这件事今天由**顶层**说，不由仲裁说。

### 3.8 边界：谁不消费、谁不在位流里

- `udp_tx` 永不被启动（§3.4）。它的 `protocol_sw==2'b01` 分支只能由 `udp_tx_start_en` 进入，
  而顶层给的是 `1'b0`（`eth_udp_video_top.v:215`）。
- `eth_ctrl` 的通用 `tx_data/tx_req/rec_en/rec_data` 四口接死线（§3.1）。
- 三路 `arp_rx_done`/`src_mac`/`src_ip` 只喂 `arp_tx`+`icmp_tx`+`eth_ctrl` 三处，没有地址表老化：
  `src_mac/src_ip` 一旦被写就一直挂着，直到下一个 ARP 包改写（`arp_rx.v:157-158`）。
  ⇒ 对端换网卡/IP 时，若不发新的 ARP，回复会继续发向旧地址。**本设计没有 ARP 老化机制**，
  这是"单接口管理面"这一层的已知简化，仓里没有对应的判据。

---

## 4 为什么这样选

### 4.1 发侧留在 RXC 域 vs 由 PL 另生一颗 125 MHz

**留在 RXC 的代价**（这是有名字的）：`eth_rxc` 一个域里装着收侧链 + 发侧协议栈 + `link_monitor`，
2544 只寄存器（`build/clock_util.rpt:174`）、4835 个 setup 端点
（`build/timing_summary.rpt:182`），最差那条路的**布线占 58.447 %**（`:373`）。
域里每一条路径都要先付 4 ns 量级的布线——这是"装得多"的真实价格。

**解耦那一条（候选 B）为什么不做**：`域划分候选评估` 给了完整清单。
可行性是现成的：`rgmii_tx_clk` 本来就是 PL 的输出端口，可以由 MMCM 另生一颗 125 MHz 驱动发侧。
代价是三笔：
1. **每一处"发侧由收侧事件触发"都要缓冲**——就是 §3.7 那张表：
   `src_mac` 48 位、`src_ip` 32 位、`icmp_id`/`icmp_seq` 各 16 位、
   `reply_checksum` 32 位未折叠和、`rec_byte_num` 16 位、`rec_pkt_done`/`rec_en`/`rec_data` 的字节流、
   `arp_rx_flag` 单拍。宽总线要快照/握手，字节流要异步 FIFO。
2. 新增跨域要重新过 CDC 判据（`:51-52` 点名 `report_methodology` 的 CDC-10/CDC-11 计数会动）。
3. 台架 + 上板复验全跑（`:53`：顶层 `tb_v98` + 单元 `tb_icmp_rx_len`/`tb_link_monitor` + `board_verify`）。

**判断**：`:56` 明写"预期收益**未量**"，只登记代价与判据。
⇒ 现在的选择不是"解耦不好"，而是"它的收益要一整轮才能量，而主片源就是网络、
`ping` 应答在验收清单上"（同一判断在 `docs/course/04-rgmii-rx-frame-reassembly.md:193-194`）。

⚠ 顺带把第 11 章也提过的那条错账钉死：**512×100 位的 LUTRAM 打包器不在这个域里**。
`src/rtl/eth/eth_udp_video_top.v:355` 写的是 `.clk(axi_clk)`、`.rst_n(axi_rst_n)`，
`axi_clk` 是 HP0 的 100 MHz（`clk_fpga_0`，3338 只寄存器，`build/clock_util.rpt:128`）。
"把打包器移出 `eth_rxc`"这条候选的前提为假，已作废（`域划分候选评估`）。

### 4.2 校验和的三种节拍分配，与两次实测否决

| 写法 | 谁在用 | 拍数 | 结果 |
| --- | --- | --- | --- |
| 一拍 10 项 | `udp_tx.v:236-239` | `st_check_sum` 占 4 拍 | 锥最深；但该模块不在关键路径上（发 UDP 的使能恒 0） |
| 两拍各 5 项（现状） | `icmp_tx.v:277-291`（r108） | `st_check_sum` 占 5 拍 | `eth_rxc` WNS 0.739，仍为本族最差，但 10 项锥被拆断 |
| 每拍 1 项（摊平） | 试过 | 更多拍 | **判负**：`eth_rxc` WNS 0.739 → **0.691（更差）**，本族最差换成 `frame_reasm/rows_hit_reg[12]/CE`，5 级、**布线 87.3 %**（`docs/course/04-rgmii-rx-frame-reassembly.md:131-134`，凭据 `build/isolated_1005_icmpck1/timing_summary.rpt`） |
| 编译期常量抽出发一拍 | 试过 | — | **判负并回退**：逐字节等价过了台架（四场景 `72/110/72/72` diff=0），但名册差分 `eth_rxc/setup` 0.739→0.692、`clk_fpga_0/setup` 1.850→1.776、`sys_clk/hold` 0.222→0.092（`docs/course/04-rgmii-rx-frame-reassembly.md:161-180`，件 `build/evidence/1006_roster_diff_vs_r118.txt`） |

**两笔实测的启示不是"别改"，而是"这一族的瓶颈不是加法树的项数"**：
折叠会把常数并进同一拍，第一拍的加法**变深**而不是变浅，端点数只从 4835 降到 4819
（网表几乎没瘦，布线换了另一副分布）。⇒ 剩下的债是**域划分**（§4.1），不是继续削算术。

### 4.3 `check_buffer` 是 20 位而不是 32 位

`icmp_tx.v:75-79`（r112）给的推理是：这个累加器只装"十个 16 位项之和"，上界 655350 < 2²⁰，
所以 `bit31:20` 恒 0——**宽度不参与任何一位信息，但参与进位链**。
最差那条路 10 级 / 6 个 CARRY4、route 61.3 %，32 位进位链里有 12 位在给恒零的半截买单。
等价凭据是"发出去的 72 个字节逐字节相同"（`sim/tb_v112_tx_bytes.v`，
件 `build/evidence/r112_tx_bytes_{base,cut}.txt`）。
⚠ 诚实记录：**这两件今天不在盘上**（我按路径查过，只有 `build/r112_verdict.txt`、
`build/evidence/r112_bit` 在），所以这条收益是**账上的历史读数**，不是我复量到的。
对照 `udp_tx.v:64` 的 `check_buffer` 仍是 32 位——同一算法在两个模块里位宽不同，
差别就是"有没有为它跑过一轮名册差分"。

### 4.4 复用 RX 的 `reply_checksum`，而不是发侧重算

选择：`st_check_icmp` 只加 4 项，其中数据段的和直接取收侧算好的 32 位 `reply_checksum`
（`icmp_tx.v:296-297`）。收益：**发侧不必把出向的每个数据字节再累加一次**——
那会在 `st_tx_data` 那条已经在关键路径附近的锥上再加一个 16 位累加。
代价与边界条件（都成立才安全，值得逐条核）：
1. **回复载荷必须与请求逐字节相同**。成立：字节是从 `u_icmp_fifo` 原样读出的
   （`eth_udp_video_top.v:148`），`icmp_tx` 不做任何改写。
2. **补位字节不能进校验和**。成立：`total_num = tx_byte_num + 28`（`:129`）声明的是
   IP 总长，ICMP 的数据段长度由它推出；补到 46/64 字节是**以太网层的填充**，
   在接收方按 `total_num` 截断之后，填充字节不属于 ICMP 报文 ⇒ 不参与校验和。
   这条是"补位会不会算错校验和"这个直觉问题的正确解答。
3. 奇数长度请求的尾字节处理由收侧决定：`icmp_rx.v:284-288` 把奇数尾巴按
   `{8'h00, pay[N-1]}` 放进**低半字**再累加，`sim/tb_icmp_rx_len.v` 的 D 判据
   就是这个式子（"成对 `{pay[2k],pay[2k+1]}` 相加、奇数尾字节放低半、32 位不折叠"）。
   发侧原样折叠这个和 ⇒ 与请求里的校验和在数学上一致。
   `icmp_rx` 不看请求的校验和字段本身（`:240-241` 采进 `icmp_checksum` 之后没有第二处使用），
   所以"请求里校验和写错"这件事不会传染到回复，也不会被拦下。

### 4.5 数组装配首部 vs 边发边算

现状是"先把首部**存**进 `ip_head` 数组，临发前重读一遍算校验和"。
它的代价已经在 §2.2 的读数里显形（起点是首部寄存器、布线 58 %）。
另一种是"边装配边累加"（`verilog-ethernet` 的 `udp_checksum_gen` 形状），
仓里对此的评价很明确：**代价是要在 `st_idle` 之前多排几拍，动的面比常数折叠大，
而折叠这条已经量到负数，同方向的更贵版本不再排队**
（`docs/course/04-rgmii-rx-frame-reassembly.md:181-185`）。

`arp_tx` 用同样的数组手法（`arp_tx.v:48-50`），但它不需要校验和状态，
所以数组只服务"改三处字段"这件事，代价是 400 只 FF。

### 4.6 记账式授权 vs 抢一拍

§3.1 已经写了两种坏形状（帧中间切 mux / 请求被丢）。第三种解法是排队（多请求一个 FIFO），
本设计不需要：ARP 请求不会在同一时刻有两个未答（对端超时重发之间至少隔秒级），
所以一张 1 位的账 + "全空闲才兑现"就是最小正确解（`eth_ctrl.v:137-141` 把这条推理留在了注释里）。

### 4.7 20 拍延迟买的是什么

`:101-107` 那段没有写理由（顶层只写"收到 → 倒计数 → 发"）。
能确定的是它**不是功能必需**：`icmp_tx` 在 `st_check_sum`/`st_check_icmp` 的 9 拍里根本不去读 FIFO，
第一个字节的请求最早也在 `st_ip_head` 尾部才发出（`:332-337`）。
⇒ 我的读法：这 20 拍（160 ns）是给"收侧把最后几个字节与 `reply_checksum` 落定"留的余量，
其中 `st_rx_end` 要等 `gmii_rx_dv == 0 && skip_en == 0` 才把
`reply_checksum_add` 搬到输出口（`icmp_rx.v:309-313`）——**这是一个电平，不是流水对齐的握手**，
所以任何"过早启动"都可能读到旧值。但我**没有量过把 20 改小会怎样**：
仓里没有这条扫描，也没有对应的台架。⇒ 记为**未量**，不许当设计裕度引用。

---

## 5 怎么验：命令、判据、以及每条在测什么

```bash
VP_VIVADO_BIN=<Vivado>/bin bash build/sim/run_one.sh tb_icmp_tx_cksum   # 单支台架（仓里只有 build/sim/run_one.sh）
bash build/tb98_report.sh                                              # 顶层台架的凭据整理
node src/host/health_read.mjs                                          # 板侧读回（lane0..9 + 23..31）
bash build/board_verify.sh                                             # 板上验证，含 ping 与 health
```

**先说工件可见性**（两份树不一样，照着敲之前要看一眼）：本章引用的 RTL/台架/脚本都以工作树
`D:/Xilinx/Prj/pro/Video_Processing`（分支 `main`）为准；这份交付副本是分支 `review/20261005`，它的
`sim/` **没有带 `tb_icmp_tx_cksum.v`**（我按 `ls` 查过），`docs/course/` 那一族在这里改放在
`local_docs/course_and_walkthrough/`。凡是我引到这两个位置的地方，正文都写明"包内改用哪两支"。

| 工件 | 测本章的哪件事 | 判据（写成"比较的是什么"） |
| --- | --- | --- |
| `sim/tb_icmp_tx_cksum.v`（这一支在 `main` 工作树里；**这份 review 分支的 `sim/` 没带它**，包内改用 `tb_icmp_ping0` + `tb_v112_ip_csum` 那两支） | §1.3 的校验和数学与整帧字节流 | **A1 按定义算**：发出的 20 字节 IP 首部里把校验和那两字节当 0，16 位大端拼字做反码求和（进位回卷）、取反，必须等于帧里那两字节；A2 反空转：每场必须真的采到 ≥40 字节并走到 `tx_done`；A3 能红的对照：只改 `reply_checksum` 的最低一位 ⇒ 帧里的 ICMP 校验和字段必须**不同**；A4 整帧 `BYTES` 行 + `SUM32` 滚动摘要是改前/改后的比对面 |
| `sim/tb_v112_tx_bytes.v` | §4.3 那把"32→20 位"刀的等价尺子 | 六个矢量（`tx_byte_num` 含 28 与 `16'hFFF0` 两端）各采 72 字节逐字节打全；T1 字节里出现过 `8'h45`；T2 `cnt >= 40`；T3 只改 `reply_checksum` 一位 ⇒ 指纹必须变。**等价凭据是 base/cut 两次跑的 `BYTES` 行逐字相同**（那两件现在不在盘上，见 §4.3） |
| `sim/tb_v112_ip_csum.v` | §1.3 的界与折叠 | 抓 `cur_state==st_check_sum && cnt<=1` 时的十个 16 位项，按定义现算 `fold1=(sum>>16)+(sum&0xFFFF)`、再折一次、取反；K1 `got === exp16`；K3 影子期望 `exp16^1 !== got`（**判据必须能红**）；K2 `maxsum < 1048576`；K4 至少一矢量 `fold1 > 65535`（真的发生过进位） |
| `sim/tb_icmp_ping0.v` | §3.3 的零载荷支与补位 | T1 `cyc_data == 18`（改前 65536）；T4a `cyc_data>0 && dones==1`；T2 `tx_byte_num=8` ⇒ `cyc_data==18`；T5 `pad_seen==10` 且 `pad_first == last_data_byte`（§1.1 的"填最后一个有效字节"）；T3 `tx_byte_num=56` ⇒ `cyc_data==56`（不补位也不少发）。改前红凭据 `build/r98_188_before.txt` |
| `sim/tb_icmp_rx_len.v` | §4.4 的 `reply_checksum` 定义 | D 判据 `reply_checksum === exp_sum(N)`：成对 `{pay[2k],pay[2k+1]}` 相加、奇数尾字节放低半 `{8'h00,pay[N-1]}`、**32 位不折叠**。G 判据 `icmp_id===16'h1234 && icmp_seq===16'h5678`（回填正确）；K/L 族钉 0 长度与截断包之后仍不楔死 |
| `sim/tb_icmp_len_wrap.v` | §3.3 那条 `<28` 下界守卫 | R1 `(dut.cur_state == S_RX_DATA)` 在帧间隙后必须为假；R1b 跨两帧数 `rec_en` ⇒ `en_bytes==8`；R2 紧跟的合法 ping 仍被应答（`icmp_id`/`icmp_seq` 对得上）；R3 合法包先自证激励为真。**激励必须留真帧间隙**，否则"畸形包已被吃完"根本没被演到（`sim/tb_icmp_len_wrap.v:9-11`） |
| `bash build/sim/run_one.sh tb_v795_rx_chain` | 收侧半边（本章的输入） | 见第 11 章 §5 的 C1..C5 |
| `bash build/tb98_report.sh` | 顶层（唯一例化顶层的台架 `sim/tb_v98_top_seam.v`） | 报告头部钉 `pl_video_top.v` 与本台架的 md5，对不上就判"这份不算数"（`build/tb98_report.sh:10-16`；由来是 #88：gates 14/14 与顶层台架同红可以同时成立） |
| `node src/host/health_read.mjs` | 板侧读回，含发侧健康 | lane0..9 = `link_monitor` 快照；lane31 bit0=源时钟消失、bit1=源时钟被拉慢（拔线）；其它 lane 号硬件返回 `0xDEADBEEF`，一眼看出号写错（`src/host/health_read.mjs:13-14`）。默认把 10 条 lane 读两遍，单调 lane 第二次变小 = 采到快照刷新那一拍（`:22-23`） |
| `bash build/board_verify.sh` | 板上 ping 与读回 | 第 2) 步跑 `health_read.mjs --json` 并对 `drop_words` 做判定（`build/board_verify.sh:204-216`）；管理面 C9 用 `ping 192.168.1.10`（`board/hardware_setup.md:53`，它同时验位流，因为应答由 PL 的 ICMP 决定） |

### 5.1 三个盲区（发侧比收侧更容易被"绿"骗）

1. **没有任何台架把发出去的 FCS 与独立实现比过**。`tb_v112_tx_bytes` 与 `tb_icmp_tx_cksum`
   比的是**同一实现改前改后的字节流是否相同**（等价尺子），不是"字节流对不对"；
   `tb_icmp_tx_cksum` 明确说 `crc_data`/`crc_next` 恒 0、"FCS 由外部 `crc32_d8` 算，本台架不判它"
   （`sim/tb_icmp_tx_cksum.v:11`）。⇒ FCS 的正确性今天只有两条支撑：
   本章 §1.4 那次交叉复算（**我做的，不是仓里的判据**），
   以及板上 `ping` 通（对端网卡会直接丢弃 FCS 错的帧 ⇒ 它其实是一条很强的隐式判据，
   只是**没有把它写成可回归的判据**）。要把这条补成硬判据，最省的做法是让
   `tb_icmp_tx_cksum` 采下 4 个 FCS 字节、用 TB 里那套独立 CRC 实现算一遍对照。
2. **仲裁的正确性只有台架间接覆盖**。`eth_ctrl` 没有自己的单元台架
   （`sim/` 下没有 `tb_eth_ctrl.v`，我列过目录）；#28/#37 那两条修的是"帧中间换源"和
   "ARP 第 0 字节重发"，现在的防线是：顶层台架跑过 + 板上 ARP 一次通。
   ⇒ 想复现这两条坏形状需要专门造一个"在途帧 + 同拍 ARP 请求"的激励，仓里没有。
3. **`udp_tx` 的路径不可达但代码在树里**。§3.4 那条零长度缺陷今天踩不到
   （`eth_udp_video_top.v:166` 的 `1'b0`），所以任何"发侧已经验过"的话都只覆盖
   `arp_tx`/`icmp_tx`。要把 UDP 发接上，先补 `tb_icmp_ping0` 同形的 `udp_tx` 长度边界台架。

发侧小结三条：
**帧是逐字节拼出来的，节拍就是状态表**（§2.1 那张表可以直接当波形读）；
**两种校验和一个是本地算的、一个是收侧送来的**（§1.3 与 §4.4）；
**发侧住在收侧恢复的 125 MHz 上，因为因果量都是收侧寄存器的电平**（§1.5、§2.5），
而这件事的账单现在写在 `eth_rxc` 的 0.739 ns 与 58.4 % 布线占比上（§2.2、§4.1）。
