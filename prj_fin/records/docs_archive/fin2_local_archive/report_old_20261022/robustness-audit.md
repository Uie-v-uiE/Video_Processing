# RTL / PS 代码审计（2026-10-22）

这份文档记录一次按模块做的只读审计，以及随后真正落地的修改。审计不是“看风格”，每条都要求能指到代码事实、说清失效方式；修改过的条目给出台架或构建证据，没改的写清为什么留。

## 1. 方法与范围

- 范围：`src/rtl/eth`、`src/rtl/video`、`src/rtl/process`（含 rotate/zoom/bilin）、`src/rtl/axi`、`src/rtl/clocks`、`src/rtl/top`、`src/rtl/util`、`src/constraints`、`src/ps/main.c`、`src/ps/sd_play.c`。
- 方式：按 ETH、视频/处理、AXI/时钟/顶层、PS 四块独立审查，再逐条回读代码核实；只读审查不直接改代码。
- 判断口径：优先看“会不会错、错了能不能看见”，其次才是风格；纯命名/排版不单独立项。

## 2. 已经修掉的（r169/r171 源）

### PS 串口可重入（高）

`uart_poll()` 原来把 `tk[]` 指向 `cmd_buf` 后直接 `dispatch()`。`sd_play` 的读循环会经 `uart_keepalive()` 再进 `rx_fill()`；如果这时新到的字节让 `cmd_buf` 溢出，`cmd_len` 会被改写，回到 `uart_poll` 后 `memmove(cmd_buf, cmd_buf+n, cmd_len-n)` 可能得到负长度（巨大 `size_t`），同时 `tk[]` 指向的参数也会在派发中途被覆盖。

修法：先把完整行复制到局部 `line[CMD_BUF]`，**在派发前**把这行从 `cmd_buf` 摘掉，再 `tokenize(line)`/`dispatch()`。`rx_fill` 之后只往剩余缓冲尾部追加，不再碰正在执行的参数；`n > cmd_len` 也做了防御。改动在 `src/ps/main.c` 的 `uart_poll()`。

### PS 命令状态与小输入边界（中）

- `temp th <n>` 的“失败保留旧阈值”改法试过又**回退**：105 条电池把“非法值 ⇒ 退回 85”当作合同（`temp th` / `temp th 999` 之后的 `th=85C`），保留旧值会让第 54 条起判红。当前行为仍是失败退回 85；这是“拒绝一条命令却改了阈值”的已知边界，与电池同口径，记录在 #504。
- `parse_gamma()` 的整数部分原来无上界，`gamma 4294967476` 会 u32 回绕成 180 并被接受；现在超过 1000000 直接拒绝。
- `cmd_fill()` 是 153600 次写加一次 300 KB flush，原来全程不搬串口 RX；现在每 16384 个像素调一次 `uart_keepalive()`，长命令期间不再把输入饿死。
- `autoplay` 的提示原来写“only affects the next boot”，但变量只在 RAM 里，下一次启动根本记不住；提示改为“session only; reset/re-download returns to 1”，不再承诺持久化。
- `sd_play.c` 的 FPS 小数解析不再无限乘 10：最多收三位小数，整数部分限 1..1000，避免 `scale` 回绕和 `fps_num == 0` 的除零路径。
- `open_at()` 的 `off * FRAME_BYTES` 改成 64 位，跳过簇数超 u32 时拒绝，卡上 META 写了离谱帧数也不会算出回绕后的错误 LBA。

### ETH 帧重组（高/中）

- **abort 后清帧状态**：原来 `last_pkt` 走 abort 时只打 `frame_abort`/`rows_missed`，`cov`、`rok*`、`rows_hit`、`bad_frame` 留到下一帧；下一帧若丢首包，两帧的账会拼在一起。现在 abort 同一拍清掉这些状态，下一帧从干净账开始。
- **OOB 包作废本帧**：`off >= FRAME_BYTES` 的字节原来只加 `stat_oob_off`，仍可能给 `cov` 记账；现在同时置 `bad_frame`，让 commit gate 拒绝这一帧，不让越界包把字节数凑满。
- 4 ms 预分频空闲超时（A9）保留：12 位预分频 + 7 位计数器 + 单 bit `gap_pending`，只在包头清零处消费；r168 实测 WNS 1.385，代价很小。

### UDP 接收畸形长度（中）

`udp_rx` 在 UDP 长度小于 8 时原来会 `data_byte_num <= udp_byte_num - 8` 下溢成 0xFFF8 一类的大数，随后在数据态等一个不存在的长度；现在长度 <8 记 0，`st_rx_data` 对零长/畸形包直接收尾，`gmii_rx_dv` 提前掉也退出数据态，不会把下一帧字节吞进来。

### AXI 行搬运器 abort 卡死（高；r170 尝试，WNS 1.268 否决）

`axi_frame_writer_gated` 的 `outstanding` 记的是“已发出、还没见 rlast”的 burst，而 abort 那一拍把 `m_axi_arvalid` 撤掉，且 drain 态把 `busy` 置 0。若 abort 正好撞上一个还没被接收的 AR，这个 burst 永远不会产生 rlast，`drain_left` 永远不归零；同时 `src_arb`/`frame_commit_lock` 看到 `busy=0`，会以为搬运器空闲。

修法与台架在 `build/r170/`：abort 不撤 pending AR、drain 保持 busy、位宽放宽。修复版台架 PASS，但 post-route WNS **1.268**（r169 是 1.341），退 73 ps；按 WNS 优先否决，源与台架已还原。

### PS/ETH 换手一拍竞争（高）

`ps_copy_start` 原来由组合条件 `ps_copy_pend && allow_copy_rise && !fill_busy && !row_busy && !eth_mode && src_sel` 直接驱动 `u_aw.frame_start`。`src_arb` 在同一个沿可以把 `owner_eth` 从 0 翻到 1：PS 写器已经在边沿置 `active`，但地址 mux 已切到 ETH，PS 的 AR 永远发不出去，`fill_busy` 永远为 1，显示端被锁死。

修法：先在允许窗口里把请求寄存成 `ps_copy_req`，下一拍再按**当时**的 `eth_mode` 放行；如果 ETH 抢到 owner，请求取消，`ps_copy_pend` 留到下一个 blank，不会起一个半截拷贝。改动在 `pl_video_top.v` 的 PS publish 路径。

### saver 满 FIFO + flush 的尾字（中；r171 修）

`axi_frame_saver64` 的 `flush` 分支原来在 `fifo_full` 时也清 `cur_dirty`，而同一拍 `pack_we` 被 `!fifo_full` 挡住，尾字永久丢失且 commit 仍可能成立。`tb_saver_tail_full` 把 AXI 从机按停、灌满 512 格、再送一条 flush：老代码写 513/514 个 beat、尾字为 0，加 `&& !fifo_full` 后 514/514 且逐字对。另把 `tb_eth_ingress_integrity` 的丢字计数从 `sav_en && full`（会把“同一字的后续 lane 送到”误当丢字）改成 `sv_push && occ==512`，并加 `+STALL`（0.3 ms 停口）；packer 峰值 512/512 时 `words exact` 仍为 38400/38400——所以没有加 skid/credit 这类更重的反压。见 #508。

### SD 选段后续播（中；r171 修）

`sd_play(1)` 原来无条件 `nxt = 0`，`sd file n` 选好的段一按 `play` 就被拉回第 0 帧。删掉这一行后从当前游标续播；同一串板上 A/B：老 ELF 回 108，新 ELF 回 621（`sd file 1` 的 `first=512`）。见 #507。

## 3. 审计发现但这次没改的

按“会造成什么后果”排序，不按代码好不好看。

1. **`dc_fifo` 读写两侧独立复位（#182）**：两侧复位源是 `eth_rst_async`（`system_top.v:141`，`eth_rst_n & mmcm_locked`）与 PS 的 `FCLK_RESET0_N`（`system_top.v:91`）。烧 PL / `rst -system` 时两者一起复位；只有"PS 单独拉 FCLK 复位、ETH 继续灌流"才会单侧复位，此时读侧指针归零后在几个字内重新追平，影响是短暂陈旧字，不是永久死锁（没有观察到，也不会由现有命令触发）。正确修法是系统级 reset controller 或双端 reset 握手，会碰 125 MHz FIFO 和 `u_lm/full_d` 那条 0.053 ns 的余量，不做。
2. **`axi_frame_writer_gated` abort 可能永久卡住**：`drain_left` 统计的是已发出的 burst，不是已握手的 AR；abort 时又撤掉 `arvalid`，一个没被接收的 burst 永远等不到 `rlast`，`busy` 却已清零。r170 的修法台架能红能绿，但 WNS 1.341 → 1.268，否决；源已还原。
3. ~~**`axi_frame_saver64` 满 FIFO 丢字没有计数**~~ **已修（#508）**：老台架用 `sav_en && full` 数丢字是**误判**——满时后续 lane 仍会送到，但它们只是并进当前 64bit 字，不需要空位。可达的洞只有一条：`flush` 撞满时老代码无条件清 `cur_dirty`，而同一拍 `pack_we` 被 `!fifo_full` 挡住，尾字永久丢失。`tb_saver_tail_full` 在 512/512 + flush 下老代码写 513/514 个 beat（尾字缺失），加 `&& !fifo_full` 后 514/514 且逐字对。`tb_eth_ingress_integrity +FULL +STALL` 把 AXI 停 0.3 ms、packer peak=512/512，仍 `words exact=38400/38400`——`idx_chg` 撞满在系统流里不可达（推送间隔 ≥4 像素、读流水 3 级），所以没有加 skid/credit。
4. **`arp_rx`/`icmp_rx` 不信 MAC 的 FCS-good，也不校验 IP/ICMP 校验和**：坏 FCS 的帧仍可更新 `src_mac`/`src_ip` 或触发回复。修法要接 `gmii_rx_mac` 的 good 标志并补校验和比较；这是协议安全边界，不是演示路径。
5. **`frame_reasm` 的行覆盖是行粒度，重复包可掩盖丢包**：字节数 + 行位图能挡住“整行没收到”，但挡不住“同一行里一段被重复包填上、另一段丢了”。要彻底闭合需要字级/块级覆盖或包偏移去重，代价明显；当前先把它写成已知边界。
6. **`angle` 是 9 位裸跨域，`zoom_fit` 的 `inv_fit` 比 `angle` 晚两拍**：换角沿落在帧中间时，前两列可能用新角度配旧 fit。修法是在 `frame_start` 快照 `{angle, inv_used}` 或把 angle 延迟两拍；这会碰旋转路径，用户之前明确不想动，留作边界。
7. **HDMI/TMDS 没有热插拔/EDID、没有 underrun 计数，`rst_pix_n` 的释放相对 `clk_pix` 是异步的**：演示够用；产品化要加 DDC/EDID、显示欠载计数和 pix 域复位同步器。
8. **PS 命令层仍是单文件 if 链**：`dispatch()` 约 500 行、20 多个动词、三个解析器混在一起；`ci_pre` 的前缀匹配和 `tk[0]+N` 偏移靠人维护。当前没有动词被前缀遮蔽（已逐条核对 `TH/SRC/ZOOM/BILIN/OSD/GAMMA/FRAME/ECHO/TEMP/AUTOPLAY`），但新增动词很容易撞前缀。最值得的拆分是 `console`（rx_fill/uart_poll/行提取）与 `dispatch` 表驱动，再给 `parse_gamma/tokenize/parse_bits` 加 host 单元测试；这是纯风格重排、零行为变化，却要让 105 条电池逐条重新基线，所以不做。
9. ~~**`sd_play` 的 `play` 会把 `nxt` 归零**~~ **已修（#507）**：删掉 `nxt = 0;`，`play` 从当前游标续播；板上 `sd file 1` + `play` + `stop` 回 **620**（>512），老固件会回 ~100。`src 0/1/auto` 不停 SD DMA 是另一件事（片源切换与播放状态分开），本轮不改。
10. **`tmp` 注释与硬编码**：`T_MAX` 还写着 `buf[48]`（现在是 128），`src_arb.v` 的 `2'd10` 是十进制十截成 2 位（碰巧等于 `2'b10`）。都不影响功能，但应在下一次正式构建时一起清掉，避免下一个人误读。

## 4. 测试与构建证据

- 19 支回归（r171 源）：17 支标准 + `eth_ingress_integrity` + `saver_tail_full`，`build/msim/r171_regression.txt`，`MSIM DONE fail=0`；另有 `tail_bank`/`fb_pingpong`/`bank`/`commit_strobe`/`full_done` 五支与 saver 相关的台架单独 PASS。
- 帧重组 OOB/abort 相关：`build/msim/r169_reasm_oob_abort.txt`，`rows`/`udp_reasm`/`reasm_bounds` 全 PASS。
- abort 清帧的定向判据：`tb_udp_reasm` 第 8/9 段（字节 256 但缺 row0 的帧先作废，下一帧再丢首包）；r169 通过（`build/msim/r169_abortclear_test2.txt`，`RESULT udp_reasm PASS`），临时删掉 abort 清帧后同一台架报 `FAIL no mix after aborted frame: got 4 exp 3`（`r169_abortclear_mutation.txt`），恢复后 PASS。
- UDP RX 畸形长度：`build/msim/r169_udp_rx_guard.txt`，`eth_top_rgmii`/`udp_telemetry`/`udp_reasm` 全 PASS。
- 分割台架：`build/msim/r169_seam_scan2.txt`，`RESULT seam_scan PASS`；顺手把 `tb_seam_scan` 里的任务名 `expect` 改成 `expect_`，它此前在 `-sv` 下根本编译不过，等于没进回归。
- 顶层 quick（ModelSim）：`build/msim/video_pipeline_top.log`，C17/C18/C19/C20/C21/C22/C25 均 PASS；C18 正是 PS/SD publish 与 blank 写门控那一条。
- r171 实现：`build/r171/timing_summary.rpt`，WNS **1.341 ns**（与 r169 相同，仍是复位恢复路径）、WHS **0.025 ns**、失败端点 0；LUT 14967、FF 9095、BRAM 98、DSP 19。r169 是 1.341/0.048；WHS 的 23 ps 差来自布局扰动，最差 hold 换到 `u_blur/dout_reg[15] → u_sharp/q22_reg[15]`，仍是正的。
- PS 固件：`build/ps_app_r171.elf`（md5 `9ff967573b32…`）随 r171 冷启动烧板；FLASH GREEN（`flash_20261022_1911.txt`）、health GREEN（`health_20261022_1912.txt`），105 条电池 98 s PASS（`build/uart_r171_battery_final.txt`），`sd file 1`+`play` 续播 A/B 回 621 / 108（`build/evidence_r171/uart_r171_play_final.txt` / `uart_r169b_play_resume.txt`），ping 后 1 Hz 遥测 13 秒 11 包（`build/telemetry_r171_final.txt`）。
- 满 FIFO 尾字：`sim/tb_saver_tail_full.v`，老代码 513/514 beat FAIL（`build/evidence_r171/r171_saver_tail_before.log`），修后 514/514 PASS（`r171_saver_tail_after.log`）。
- 满 FIFO 压测：`tb_eth_ingress_integrity +FULL +STALL`，AXI 停 0.3 ms、packer peak 512/512、words exact=38400/38400（`build/evidence_r171/r171_ingress_full_stall_after.log`）。

## 5. 工程化判断（简版）

流程和证据链是工程级的：可重编 ELF、位流/XSA/ELF 三元身份、台架、门禁、问题台账、文档引用都能落地。产品化还差：独立启动（BOOT.bin/QSPI）、PS 看门狗/OTA、SD 异常状态机、覆盖率/形式化、1080p 的 DDR 行/瓦片缓存、HDMI 热插拔/EDID。`dc_fifo`/HDMI 这种标准通路功能已够，不建议为了“看起来更稳”往数据/复位关键路径里加逻辑。

## 6. 亮点评估

按“换成别人能不能一眼看出差别”排序：

1. **同帧 A/B 的缝是测量尺，不是拼图**：左右两半从同一个帧缓存、同一套几何和固定 15 拍效果链出来，缝两侧可以逐像素对。大多数演示是两张截图或两帧拼在一起，错位/漏行在缝上根本藏不住。
2. **能被故障注入打红、再恢复的遥测**：不只报 FPS，还报帧数、坏包、作废、缺行、PL 时延、处理窗完整性；三段自检要求计数真的动、再回到基线。海报上第三点写“CALIBRATED BY FAULT INJECTION”，比“self-test goes red”更像一个工程能力。
3. **低端 7020 上的固定延迟全硬件链路**：1024×600、六级效果、旋转/双线性、A/B、OSD 都在 PL 里，PS 不碰像素；15 拍延迟不随效果配置变。这一条的含金量在“确定性”和“可解释”，不是算法新。

落到场景：工业检测/医疗影像的实时处理前后对照、广播的 confidence monitor、教学实验平台。最值钱的是第 1+2 条的组合——它让“处理有没有出错”变成可观测、可复现的问题；第 3 条是让它跑得稳的地基。
