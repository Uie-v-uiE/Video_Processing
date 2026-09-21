# v6 根因分析与改动（单变量清单见文末）

## 1. 症状 → 机理对照

| 症状 | v5.8 观察 | v6 判定 |
|------|-----------|---------|
| 随机黑横纹 | 停流后冻结帧仍脏，黑纹位置随机 | **入包侧溢出**：221 包以线速倾泻，CDC(1KB)+打包 FIFO(4KB) 装不下 → 丢包留下 DDR 空洞 |
| 提交了坏帧 | `frame_done` 只看 `rows_hit` | 只要每行碰到过一个像素就 commit，**丢一整包（2 行）照样 commit** → 黑条被当成"完整帧"锁进显示 |
| 拖影/固定黑缝 | 拷贝期覆盖整个消隐（含行消隐） | 行消隐期也在写显示 BRAM，写指针与光栅读指针错位 → **半新半旧的一行**，表现为固定位置的黑缝 |
|  marginal 带宽下卡死 | — | 拷贝在 `allow_rise` 之前被 vsync 边沿推迟，只用掉 25 行窗口里的 16 行 → 预算不足 → 拷贝跨窗 → 看门狗 abort → 帧被丢弃 → 永久冻结 |

## 2. 四处 RTL 改动

### 2.1 `rtl_fix/frame_reasm.v` — 覆盖门限（拒收空洞帧）

```verilog
wire [31:0] bytes_all = cover + pkt_pay + (p_valid ? 32'd1 : 32'd0);
wire [31:0] pkt_end   = pkt_start + pkt_pay + (p_valid ? 32'd1 : 32'd0);
wire        last_pkt  = pkt_end >= FRAME_BYTES;
...
if (rows_hit >= IMG_H[15:0] && bytes_all >= FRAME_BYTES) begin frame_done<=1; ... end
else begin cover <= bytes_all; if (last_pkt) stat_bad <= stat_bad + 1; end
```

* `cover` 只在帧内 offset<4 的包头清零 → 跨帧累计的老 bug 一并消除。
* **off-by-one**：末字节常与 `p_eof` 同拍，此时 `pkt_pay` 还没 +1。`bytes_all`/`pkt_end`
  都补上 `(p_valid?1:0)`，否则 `last_pkt` 永远不成立、`stat_bad` 不上报（仿真已验证）。
* `stat_bad` 每帧只加一次（判据是"这一帧的最后一包到了"），否则 OSD 上 net_bad 会按包暴涨。

### 2.2 `rtl_fix/pl_video_top.v` — 拷贝窗口只在 V-blank

```verilog
localparam [11:0] DISP_V_LINES = 12'd600;   // 1024x600 有效行
localparam [11:0] DISP_V_LAST  = 12'd624;   // V_TOTAL-1
localparam [11:0] VB_X_GUARD   = 12'd1279;  // H_TOTAL(1344) - 65
wire disp_quiet = (y >= DISP_V_LINES) && ((y < DISP_V_LAST) || (x <= VB_X_GUARD));
```

替换原 `~(de | de_d[11])`（全部消隐）。行消隐不再写 BRAM ⇒ 光栅读到的每一行要么全旧要么全新。
末尾 64 像素保护 `frame_commit_lock` 里 3 级同步 + 边沿检测的 CDC 余量。

### 2.3 `rtl_fix/frame_commit_lock.v` — 窗口一开就拷贝

```verilog
wire allow_rise = allow_copy_axi & ~al_d;
if ((allow_rise || vsync_req) && pending && !copy_active && ...) begin ... end
```

1024x600 的 vsync 在 V_FP=3 之后才上升，即 25 行窗口已过去 9 行（36%）。保留
`vsync_req` 兼容旧 TB，新增 `allow_rise` 让拷贝拿到完整 67200 个 axi 周期。

### 2.4 `rtl_fix/axi_frame_writer_gated.v` — `MAX_OUT` 2 → 4

4×16 拍突发 = 64 拍在途，才能在 DDR/HP0 延迟下维持 ≈1 拍/周期；2×16 时窗口后半段会空转。

## 3. 带宽预算（为什么 V-blank-only 够用）

```
窗口 = 25 行 × 1344 像素 = 33600 pix 周期 = 67200 axi 周期(100MHz, 实测 FCLK=100)
整帧 = 512×300×2 B / 8 B = 38400 拍
下限 = 38400 / 67200 = 0.571 拍/周期 ≈ 457 MB/s（HP0 峰值 800 MB/s 的 57%）
```

`tb_v6_vblank_copy`（生产几何 + 限速 AXI slave）实测：

| slave 速率 | copy_cycles | 结果 |
|-----------|-------------|------|
| 10/10 (800 MB/s) | 38441 | 一个 V-blank 内完成，38400 字各写一次，无越界 |
| 7/10 (560) | 54894 | 同上 |
| 6/10 (480) | 64036 | 同上（贴着 67200 预算） |
| 4/10 (320) | 1708873 | 溢出到后续 V-blank 才完成；**不写有效行、不重复、不越界**，看门狗(20ms)不误杀 |

## 4. 上位机限速（`host/video_sender.py`）

`Pacer` 按绝对时间匀速发出每包，默认 `--pace-mpbps 15`（`--no-pace` 复现旧行为）。
307 KB / 15 MB/s ≈ 20.5 ms，仍支持 30fps；板上排空能力约 25–50 MB/s，15 MB/s 留了余量。

## 5. 构建

`build_tcl/rebuild_v6.tcl`：打开
`ADD/Video_Pipeline-main/vivado_system/zynq_video_sys.xpr` → 删除失效的
`../../ghosting_fix_v5/rtl/*.v`（该目录在本机不存在）→ 加入本工作区 `rtl_fix/*.v`
→ top `system_top` → synth + impl(phys_opt/post-route-phys_opt) → bit +
`write_hw_platform` → 输出到 `build_v6/`（system.bit / system.xsa / 报告）。
脚本可重复执行（已换过的文件不再动）。

## 6. 仿真结论

```
全量回归 16/16 PASS（sim_work/reg3.log）
tb_v6_cover_gate         PASS  完整帧 commit / 丢 1 包拒收且只计一次 bad / 下一帧恢复
tb_v6_vblank_copy        PASS  见 §3 表
tb_v6_ingress_integrity  PASS  1392B 分包 + 15MB/s 间隔 + 20 拍写响应：0 丢字（修复前 46% 丢）
tb_v50_rows_prod         PASS  期望已按 v6 契约收紧（凑满 300 行但字节不足 → 不 commit）
```

## 7. v6.2：用「帧号回读」定量抓到真正的丢字机制

### 7.1 测量方法的两次自我纠错（重要，避免以后再踩）

1. **恒定图案会掩盖丢字**：`wordid` 每帧内容相同，某个字这一帧没写进去也看不出来
   （旧值==新值）。⇒ 改成 `frameid`：像素值 = 字号 + **帧号**，回读即可反解
   "每个字来自第几帧"，丢字/滞后/混合一目了然。
2. **xsdb 的 mrd 会读到 A9 缓存**：Vitis 应用里 `Xil_DCacheEnable()` 开了 D-Cache，
   回读同一块 DDR 三次得到三组不同数字（而期间根本没推流）。⇒ 回读前
   `rst -processor`（复位并暂停核心，MMU/Cache 随之关闭，DDR 控制器保持已初始化），
   并且**不能再 `con`**（否则 A9 从复位向量重跑，若启动引脚是 SD/QSPI，boot ROM
   会把卡里的旧 bitstream 重新刷进 PL，后续测量全部作废）。

### 7.2 板级实测：丢字随"提交次数"增长，而不是随字节速率

| 推流帧率 | 最新帧在自己 bank 的占比 |
|--------|------------------------|
| 1 fps  | 95.7% |
| 5 fps  | 66% |
| 15 fps | 52% |
| 30 fps | 47% |

四组实验的**字节速率完全相同**（上位机都限 15 MBps），只有提交次数不同 ⇒
每次提交固定毁掉约 7% 的帧（≈21 KB）。单帧（发完就停）任何速率都 100% 落位。

### 7.3 机理：显示拷贝与入包写共用 HP0，打包器 FIFO 只有 512 字

`axi_frame_writer_gated` 在 V-blank 用**同一条 HP0** 读整帧（38400 字，实测
`copy_cycles ≤ 67200`，即最多可占满整个消隐窗口）。这期间入包写拿不到端口，
`axi_frame_saver64` 的 512 字（4 KB）打包 FIFO 被 15 MBps 的流灌满后，
`push_word` 里 `if (!fifo_full)` 直接**整字丢弃**。

`sim/tb_v6_pingpong.v` 把提交/翻 bank glue 原样搬进仿真，并把显示拷贝等效成
"每次提交后端口被独占 COPY_CYC 拍"：

| COPY_CYC | 修复前 | 修复后 |
|----------|--------|--------|
| 0 | 100% | 100% |
| 20000 (200 µs) | 100% | 100% |
| 67200（一整个消隐窗口） | **95%，且 firstmiss=512** | **100%** |

`firstmiss=512` 正好等于打包器 FIFO 深度 —— 这是"前 512 个字写得进、之后整字丢"
的铁证。

### 7.4 修复（v6.2）

先试错一次：**打包器 FIFO 不能加深**。`axi_frame_saver64` 的 `q_addr/q_data` 被综合成
**触发器**（512×96bit ≈ 4.9 万 FDRE，已占 xc7z020 一半寄存器），`FW=11` 直接 DRC 报错：

```
ERROR: [DRC UTLZ-1] FDRE ... requires 176092 ... only 107000 compatible sites
```

所以缓冲放到**真正映射成 BRAM 的 CDC**（`dc_fifo` 带 `ram_style="block"`）：

```verilog
// rtl_fix/eth_udp_video_top.v
dc_fifo #(.DATA_W(36), .ADDR_W(13)) u_cdc ( ... );   // 512 → 8192 条 = 16 KB
wire sv_full;
fifo_rd <= !fifo_empty && !sv_full;                  // 打包器满 ⇒ 反压，取出即丢等于白读
... .fifo_full(sv_full) ...
```

预算：15 MBps × 672 µs（一整个消隐窗口）≈ 1260 个 64bit 字要缓冲；
8192 条 = 4096 字，再加打包器 512 字 ⇒ 约 3.6× 余量。
代价：+7 个 RAMB36（36bit×8192 ≈ 8 tile），寄存器数不变。
仿真（`tb_v6_pingpong`，COPY_CYC=67200）：修复后两帧各自 100% 落在自己的 bank。

> 可优化项：把打包器 FIFO 改成 BRAM 推断（1W1R、读打拍）可释放约 4.9 万 FDRE
> （≈46% 器件寄存器），之后才有空间继续加深度或做别的缓冲。
> 后续可选：入包写改突发（AWLEN=15，注意 4KB 边界与 idle 语义，历史上
> `axi_frame_saver_burst` 就是这两点挂死的）；或把显示拷贝挪到 HP1，彻底不抢端口。

### 7.5 v6.3：v6.2 上板**没有改善** ⇒ 瓶颈是平均排空速率，不是缓冲深度

v6.2（CDC 加深到 8192 + 反压）上板复测：最新帧占比仍然 42~52%，和修复前一样。
加深缓冲只能推迟溢出，改不了「排空速率 < 到达速率」这件事本身。

用 `host/ddr_stale.mjs` 把 22:36 那次回读按**包内字节偏移**分带统计（这才是判据）：

| 包内字节偏移 | 0–48 B | 48–96 | 96–192 | 192–384 | 384–768 | 768–1392 |
|---|---|---|---|---|---|---|
| bank0 丢字率 | **6.7%** | 54.8% | 59.5% | 59.5% | 59.9% | 60.3% |
| bank1 丢字率 | **5.7%** | 60.2% | 63.6% | 63.4% | 63.9% | 63.7% |

另外两个数：连续丢字带最长只有 15 个 16bit 字（中位 7，**没有** ≥696 字的整包段），
且 18.6% 的 u32 里两个 16bit 属于不同帧 ⇒

1. 丢的是**包尾**而不是整包 ⇒ 不是 udp_rx/reasm 前端丢包，也不是「一个长窗口把端口
   完全占死」（那样会得到一条几百字连续带，即 §7.3 的猜测）；
2. 粒度是 **16bit 字** ⇒ 丢在 `cdc_wr = ... && !fifo_full` 这个门上（CDC 写侧），
   也就是打包器排空不够快 ⇒ 每包前 48 字节（=24 个 16bit）写得进去，之后包内溢出。

算一下就闭合了：旧 `axi_frame_saver64` 的写状态机 `S_AW→S_W→S_B` **每写一个 64bit
字都要等 B 响应**，在途深度恒等于 1 ⇒ 吞吐 = 字长 / HP0 往返延迟 ≈ 100 MHz/40
= 2.5 M 字/s = **20 MB/s**。上位机给的是 15 MB/s，只有 1.3× 余量；一旦显示拷贝在
消隐窗口里抢端口（实测拷一帧要用掉 0.57~1 个消隐窗口），往返延迟涨到上百拍，
平均速率掉到 <15 MB/s，于是打包器 FIFO 长期满 → CDC 满 → **每个包的包尾按固定相位丢**。
1 fps 时窗口重叠概率低 ⇒ 95.7%；提交越密丢越多 ⇒ §7.2 那张表；单帧永远 100%。
这也解释了为什么 v6.1 看到的「每隔一个 16bit 空洞」黑纹会重新出现：同一粒度的丢字。

**修复（单变量：只改写通道时序，不动 AWLEN=0、不动深度）**

```verilog
// rtl_fix/axi_frame_saver64.v
localparam [3:0] OST = 4'd8;                     // 在途 beat 上限
wire beat = aw_wait || w_wait;
wire have = (rptr != wptr) && !beat && (outst < OST);
assign m_axi_awvalid = aw_wait;                  // AW/W 同拍挂出，各自保持到被接收
assign m_axi_wvalid  = w_wait;
// B 只做 outst 计数回收，m_axi_bready 恒 1，永远不阻塞数据通路
```

上限从「RTT 决定」变成「总线握手决定」：≤2 拍/字 = 50 M 字/s = **400 MB/s**，
对 15 MB/s 有 26× 余量；`idle` 现在要求 `outst==0`，换 bank 仍然安全。

仿真（`sim/tb_v6_pingpong.v`，把显示拷贝等效成「每次提交后端口被独占 CP_CYC 拍」）：

| 端口被独占 | v6.2（逐字等 B） | v6.3（流水化） |
|---|---|---|
| 0 | 100% | 100% |
| 67200（一个消隐窗口） | 95%，firstmiss=512 | **100%** |
| 134400（两个窗口） | — | **100%** |
| 268800（四个窗口） | — | 74%（缓冲 4608 字用满，符合预算） |

顺带修了两个从机模型的错误（它们会**伪装**成 DUT 的 bug）：
`tb_v6_ingress_integrity` 的从机在 W 到达时用的是上一拍的 AW 地址，且只有 1 个 B
寄存器；`tb_v6_pingpong` 用组合的 `svc` 而不是寄存器版 ready 做握手 ⇒ 同一个 beat
被数两次 ⇒ 多发一个 B ⇒ DUT 的 `outst` 反向回绕成 15 后死锁。现在都用标准握手 +
B 移位管道。**下次再看到「saver 卡住不排空」，先怀疑从机的 B 计数。**

### 7.6 v6.3 板级结果：入包链已经无损

`host/measure_v63.mjs`（发完再回读，避免「边推边读」把每个地址段读成不同时刻的帧）：
15 / 30 / 60 fps 三档，两个 bank 的最新帧 16bit 命中率都是 **100.0%**，包内六个字节带
丢字率全部 **0.0%**，`u32 内两个 16bit 不同帧 = 0/76800`，帧号跨度 = 相邻两帧。
对照修复前：42~52%、0–48 B 6.7% / 48 B 之后 54~64%、18.6%。数字与判据表见
`docs/RESULT_v6.md` §4.1。

唯一残留：偶发「帧最后一个 64bit 字的高半个 u32 = 0」（最后 4 字节，2 个像素），
8 次 bank 末帧读数里出现 4 次，15/30/60 fps 都会（不是速率专属）。给 `tb_v6_ingress_integrity` 加了 `+FULL`（221 包、最后一包只有
960 B）来复现它 —— **复现不出来**（38400/38400 全对，最后一字四路 lane 都是 0x95ff），
所以不是 reasm/CDC/打包器的确定性逻辑；剩下的怀疑对象是帧尾 flush 与 bank 翻转的竞争
（`pack_base` 只在 `!cur_dirty` 时锁存），但它不影响画质，先记账不动。

### 7.7 v6.4：分包 1396 时的「规律黑点」= 同一个字被覆盖（WSTRB）

v6.3 之后板级数据完整性已经 100%，但推视频时屏上仍有**均匀散布的黑点**。
用 frameid 回读做 A/B（同板同 bit 同会话）：

| 分包 | 最新帧命中率 | 每帧空洞（16bit 字） | 空洞内容 |
|---|---|---|---|
| 1396 B | 99.9% | **222（111 处 × 2）** | 0x0000 ⇒ 黑点 |
| 1392 B | 100.0% | 0 ~ 2 | — |

机理不在速率而在**写选通**：1396 不是 8 的倍数 ⇒ 包边界落在 64bit 字中间，
同一个字被相邻两包各推一次（打包器每次 `flush` 都把当时的部分字推出去），
而 `m_axi_wstrb` 恒为 `8'hFF` ⇒ 第二次推送把第一次刚写好的半字**覆盖成 0**。
每 221 包里约 111 个跨界边界 ⇒ 每帧约 111 处 4 字节黑洞，间距 ≈698 像素，
肉眼看到的就是"规律的黑点"。

**修法**：按 16bit lane 记有效掩码并驱动 `WSTRB`：
`cur_keep` → `q_keep`（512×4 FF）→ `keep_r` → `m_axi_wstrb = {{2{k[3]}},…}`。
这样部分字只写自己有效的字节。副作用是**入包链不再要求分包是 8 的倍数**。

**仿真证明这套判据真的能抓住它**（`sim/tb_v6_ingress_integrity.v` 新增 `+MISALIGN`，
并让从机按 `WSTRB` 做读-改-写，否则根本测不出覆盖）：

| 1396 B +FULL（221 包整帧） | 修复前 | 修复后 |
|---|---|---|
| `words exact` | **38290/38400（差 110）** | 38400/38400 |
| `lanes_bad` | **220/153600** | 0/153600 |
| `first bad word` | **174** = `00ae00ae_00000000`（应为 `00ae00ae_00ae00ae`） | — |
| `axi_wr` | 38510（= 38400 + 110 次重复推送） | 38510（同样多，但现在不互相覆盖） |

`first bad word=174` 正是 `1396/8 = 174.5` 的第一个跨界字，仿真里的 110/220 与板上的
111/222 一一对应。1392 与 PART 模式行为不变，17 个 TB 全量回归 17/17 PASS。

## 8. 右屏网格闪烁 = 缩放算法档次，不是数据问题

`zoom_mapper` 是截断式**最近邻**（`frac_x/frac_y` 算了但没人用）；1 像素细线在
1.0↔0.5 连续缩放中会周期性落到采样间隙 ⇒ 细线闪烁。把线宽改成 4 像素后闪烁消失，
只剩轻微位置偏移，符合最近邻走样。参考实现 `ADD/Algorithm/rtl/bicubic_interpolation.v`
（以及 `ADD/eth_video_workspace_w` 的说明）是 bicubic 插值 —— 属于独立的画质工作项。

验证手段（新工具，不用看屏幕）：`host/video_sender.mjs --test wordid` 发「每个 64bit
DDR 字填自己的字号」的自描述图案，再用 `host/ddr_verify.mjs` / `host/ddr_holemap.mjs`
通过 xsdb 把 `0x1000_0000`、`0x1008_0000` 两个 bank 整个读回来逐 16bit lane 比对。

## 9. v6.1 的两处早期发现（分包对齐、CDC 读侧节流）

### 9.1 分包长度必须是 8 的倍数（1396 → 1392）

1396 % 8 = 4，包尾正好把半个 64bit 字留在打包器里；`reasm_flush` 会把这个**半成品字**
推给 AXI（wstrb=0xFF），下一包再从头起字时把另外半字清零 → **每包必坏一个字**，
且与速率无关。已把上位机 `MTU_PAYLOAD` 改成 1392（`video_sender.py` / `video_sender.mjs`
都有注释说明这个约束）。

### 9.2 黑纹主因之一（单帧场景）：CDC 读侧被限成 1/3 吞吐

原读侧：`fifo_rd <= !fifo_empty && !fifo_rd && !fifo_rd_d` → 每 3 个 axi 周期只能取
1 条（1 条 = 2 字节）= 66 MB/s。而**一个 1392B 的包是 125 MHz 线速连续进来的**
（上位机限速只能拉开包与包之间的间隔），单包就要灌 698 条，CDC 只有 512 深 →
第一包几乎装得下，第二包起 `wr_full` 长期拉高 → 稳定丢掉约 46% 的 16bit 写。

回读结果与该推断完全吻合：坏 lane 的掩码几乎只有 `1010`/`0101`（每个 64bit 字里
隔一个 16bit 没落位），而且 **0.2 / 2 / 8 / 15 MB/s 四档限速的空洞数量几乎不变**
（约 6 万个 lane），说明与平均速率无关，是包内线速溢出。

修法（`rtl_fix/eth_udp_video_top.v`）：读侧改成 1 条/周期（200 MB/s > 125 MB/s 线速），
并且 flush 标记永远让路给真实数据写（原来 `flush_pend` 与数据同拍时会顶掉一个数据写）：

```verilog
fifo_rd  <= !fifo_empty;
cdc_d1   <= fifo_dout;   cdc_d1_v <= fifo_rd;
sav_en    <= cdc_d1_v && !cdc_d1[35];
sav_flush <= cdc_d1_v &&  cdc_d1[35];
if (cdc_d1_v) begin sav_a <= cdc_d1[34:16]; sav_d <= cdc_d1[15:0]; end
```

`tb_v6_ingress_integrity` 用与顶层**完全相同的胶水**串 `frame_reasm → dc_fifo →
axi_frame_saver64 → AXI 从机`，修复前 41760 个 lane 丢 142662…（早期版本因 TB 自身
每字节 2 拍而虚高，已修）→ 修复后 `words exact=10440/10440 lanes_bad=0`。

### 9.3 板上 PS 侧的一个坑（记录，避免误判）

只跑 `ps7_init` tcl（不跑 FSBL/ELF）时，`F8000204`（FPGA_FCM0，HP0 写 FIFO 深度）等
寄存器读回全 0，且用 xsdb 写不进去（SLCR unlock 对调试器通道无效）。这会让 HP0 的
实际吞吐远低于预期。上板复验时要么按正常流程 Vitis Run ELF（FSBL 会配好这些位），
要么在解读回读数据时把这一层考虑进去。
