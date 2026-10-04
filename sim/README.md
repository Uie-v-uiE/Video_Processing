| 文件名 | 被测模块 | 功能 | 预期结果 |
| --- | --- | --- | --- |
| `tb_bilin_lerp.v` | bilin_lerp | 被测模块 `bilin_lerp`（RGB565 四抽头双线性插值算术核）；覆盖点＝fx/fy 全零与四角同色的恒等… | 逐段打印 `[tb_bilin_lerp.v:<行号>] PASS…；失败时 对应段打印 `FAIL 判据N ...` 并附 pix/期望值或… |
| `tb_cdc_capacity.v` | dc_fifo | 被测模块 `dc_fifo`（参数 DATA_W=36、ADDR_W=13，深度 DEPTH=8192）；覆盖点＝跨域… | 打印 `PASS C1 boundary: all 8192 slots…；失败时 对应判据打印 `FAIL C1 wr_full fires one slot… |
| `tb_commit_strobe.v` | frame_commit_lock | 被测模块 `frame_commit_lock`（参数 IMG_H=300、DISP_H=600、WD_CYC=40）… | 每条判据打印 ` PASS <A1..A8/B1..B4 的名字> / <说明> /…；失败时 对应条目打印 ` FAIL <名字> / <说明> / <量值>` 并把… |
| `tb_crc32.v` | crc32_d8 | 被测模块 `crc32_d8`（以太网反射 CRC 的逐字节累加器）；覆盖点＝复位初值、单字节更新、 crc_clr 清零… | 依次打印 PASS init / PASS crc updates / PASS…；失败时 对应段打印 FAIL init <crc 值>、 FAIL crc did… |
| `tb_edge_rim.v` | proc_box_blur / proc_sharpen /… | 被测模块 `proc_box_blur / proc_sharpen / proc_sobel /… | 打印 `GOLDEN gmode=<0/1>: latency = (<列平移>…；失败时 打印对应 `FAIL R0/R0b/R1/R2…/R7/R8/R9 或… |
| `tb_eth_video.v` | udp_tx + crc32_d8 + udp_rx + frame_reasm | 被测模块 `udp_tx + crc32_d8 + udp_rx + frame_reasm`（GMII 直环：u_tx 的… | 依次打印 `PASS udp payload len`、`PASS frame…；失败时 打印 `FAIL timeout tx`、`FAIL n_rec=<n>… |
| `tb_fb_rd5x.v` | fb_rd5x | 被测模块 `fb_rd5x`（5 槽帧缓存读口，IMG_W=512、IMG_H=300）；覆盖点＝输出像素与请求的配准… | 逐条打印 `[CHK] <判据名> : OK`，并带 `[INFO]…；失败时 对应条目打 `: BAD` 并 errors 加一（错值处有 `[DIAG]… |
| `tb_fb_roundtrip.v` | frame_buffer_w64 | 被测模块 `frame_buffer_w64`（W=512、H=300，PX=153600 像素 / WORDS=38400… | 打印 `写入完成 38400 字 + 2 次越界写，t=<时刻>`…；失败时 打印错位处 `MISMATCH(流水) p=<n> got=<h>… |
| `tb_head_rot_displace.v` | zoom_fit + zoom_mapper | 被测模块 `zoom_fit + zoom_mapper`（IMAGE_W=512、IMAGE_H=300，mapper 的… | 打印 `PASS D1 k=0 对照 ang=<角> inv=<inv_fit>…；失败时 打印 `FAIL D1 same-angle sweeps differ… |
| `tb_icmp_len_wrap.v` | icmp_rx | 被测模块 `icmp_rx`（BOARD_MAC=00:11:22:33:44:55… | 打印 `PASS R3 legit frame completes / ...`…；失败时 对应条目改打 `FAIL <名字> / <说明>` 并把 nfail 加一… |
| `tb_icmp_ping0.v` | icmp_tx | 被测模块 `icmp_tx`（ICMP 回应的 GMII 发送器）；覆盖点＝tx_byte_num=0（`ping -l 0`… | 逐条打印 `PASS T1 zero-byte ping reply must…；失败时 对应条目改打 `FAIL <条目名>` 且 errors 加一（T1 红 =… |
| `tb_icmp_rx_len.v` | icmp_rx | echo request 载荷长度的边界逐字节收取—— rec_byte_num、rec_en 次数、字节顺序、校验和成对累加… | 每条打 `[tb_icmp_rx_len.v] PASS <标签> /…；失败时 对应条打 `[tb_icmp_rx_len.v] FAIL <标签> /… |
| `tb_link_monitor.v` | link_monitor | 链路健康自诊断不误报平安——丢字与参考计数逐字相等、断帧与坏包、断流后快照继续刷新、 帧间隔 min/last/max/sum… | 每段各打一条 PASS（`PASS drop_words starts at 0`…；失败时 红话自带读数，如 `FAIL FALSIFIER: CDC port… |
| `tb_osd_lines.v` | osd_overlay | T1..T18 的五行整串逐字符等于期望、边界位宽与饱和、片源 标签与星号、PIPE 五位码与缩放八档与 gamma… | 每段各打一条 `[tb_osd_lines.v:...] PASS…；失败时 打 `FAIL <标签> L<行> cell<列> got %h want… |
| `tb_proc_gray.v` | proc_gray | RGB565 灰度化在纯红 与纯白两个极端像素上的输出亮度方向，以及 de 是否跟着输入走。 | 三条判据都不红，errors==0 打印 `PASS tb_proc_gray`；失败时 对应判据打 `FAIL: de_out not set` / `FAIL:… |
| `tb_ps_publish.v` | ps_publish | tog 跨域同步成 pend 的建立/保持/清除， 以及"一次发布对应一次消费"在两个非整数比时钟下的相位扫描。 | 每条打 `[tb_ps_publish.v:39] <判据名>…；失败时 对应判据打 `... <<< 不成立`，某次发布没被同步到还打 `<<< 第… |
| `tb_reasm_bounds.v` | frame_reasm | #201 —— 偏移越出帧缓存的包不许发 wr_en 但 必须被 stat_oob_off 数到，同时边界与正常路径不许被收紧。 | 逐条打 `PASS R1..R4a <判据名>`，每段前带一条 INFO 现场行 （如…；失败时 对应条打 `FAIL <判据名>`（R1 是 改前必红的那条，R2… |
| `tb_rotate_mapper.v` | rotate_mapper | 0° 恒等 映射在左上角/中心/右下角三点的逐位相等，与 90° 时中心不被判越界、输出不出现 X 态。 | 每笔恒等检查各打一条 `PASS id (%0d,%0d)`，errors==0…；失败时 对应判据红在 `FAIL id (%0d,%0d)->(%0d,%0d)… |
| `tb_rotate_window.v` | proc_pipeline | rotate_active=1 与 =0 两种状态下模糊都仍被施加——旋转不许把效果链强制旁路。 | 打印 `PASS blur active with rotate_active=1`…；失败时 对应判据红在 `FAIL no intermediate blur value… |
| `tb_shown_rate.v` | shown_rate | #128 —— OSD 的 `FPS:` 格数的是"写进屏的新帧" 而不是场数，ETH/PS/无新内容/图卡四种片源态… | 逐条打 `PASS <判据名>`、每条前带一行 INFO 现场读数，errors==0…；失败时 对应条打 `FAIL <判据名>`（数成场数会读到 20 红在 S1… |
| `tb_src_arb_why.v` | src_arb | #174 —— why_ps 必须是"换手判决那一拍的输入快照"，互锁冻住主人… | 每条打 ` PASS <标签> / <说明> / <读数>`，随后打…；失败时 该条打 ` FAIL <标签> / <说明> / <读数>`（W5 红就是… |
| `tb_sync_fifo.v` | sync_fifo | 8 位宽、 16 格深同步 FIFO 的 level/empty 旗标与"先连写后连读"两条路径上的数据一一对应。 | 逐段打印 `PASS level`、`PASS empty…；失败时 对应判据红在 `FAIL not empty after rst` /… |
| `tb_tap_sched.v` | tap_sched | lane=0..3 四种车道、跨行、 行首（sx=0）与行尾（sx=508/511 ⇒ 需要读下一个字）的请求，四个抽头… | 五条 [CHK] 行全部以 : OK 结尾，[INFO] requests=60…；失败时 错在哪条就 BAD 在那条，并先打出对应 明细 [DIAG] taps… |
| `tb_timing.v` | video_timing | 小光栅下 x/y 计数、de 有效拍数、frame_done 每帧只来一次这三件事同时成立。 | 打印 PASS tb_timing（errors==0）；失败时 先打印 FAIL de_cnt=<实测值> expected… |
| `tb_uart_decode_bits.v` | tb_uart_decode_bits.try_cmd | 串口命令里 5 个 "0"/"1" 字符到 使能位的位序约定——字符串最左那个字符落 en[0]，右移一位落… | 四组都不输出、只打印末行 PASS tb_uart_decode_bits；失败时 每条错配打印 FAIL cmd <字符串> got <实测 5 位> exp… |
| `tb_udp_parser.v` | udp_rx_parser | 一条合法 IPv4/UDP 帧 （52 字节 = 14 以太网头 + 20 IPv4 + 8 UDP + 10… | 打印 PASS payload extracted、PASS wrong port…；失败时 对应段打印 FAIL pay_bytes=<n> exp 10 或 FAIL… |
| `tb_udp_reasm.v` | frame_reasm | 正序拼满一帧、乱序（先高偏移后低偏移）、s_good=0 的坏包计数、 重复包覆盖、第二次成帧，以及… | 逐条打印 PASS normal full frame / PASS pixel0 /…；失败时 对应条打印 FAIL <判据名>: got <实测> exp <期望> 或… |
| `tb_v100_fit_rot.v` | zoom_fit | 360 个角度逐个的"装得下"与"不白缩"、 0° 回到 1.0x 附近、自动旋转只在帧沿推进且步长=speed、±1° 按键… | 逐条打印 ok T2b a=0 inv_fit=<n> ~= 1.0x / ok…；失败时 红在对应判据上： FAIL T1 a=<角度> fits-X/Y NO（带… |
| `tb_v100_raw_delay.v` | raw_line_delay | 行环形缓存的逐格语义——输出第 (row,k) 格 等于第 row−LINES 行的同一列 k、de 链与数据链等长、跨过… | 七条判据各打印 PASS <标签> / <说明>（T1 稳态逐格对齐、T5…；失败时 对应条打印 FAIL <标签> / <说明> 并… |
| `tb_v101_fb_bilin.v` | fb_bilin | 双线性结果逐位等于"先纵后 横"黄金值、oob_out 标签与像素同字同拍、bilin_en=0 时逐位等于最近邻… | 十条 line 各打 [tb_v101.v] PASS <ASCII 标签> /…；失败时 错在哪条 就打 [tb_v101.v] FAIL <标签> 并… |
| `tb_v102_src_life.v` | src_life | 复位即"无 片源且未发布是已知状态"、发布一拍后转有源、停发后看门狗判超时、超时恰好落在第 30 个 帧节拍、重新发布自动解除… | 每条 line 打印 PASS <ASCII 判据名>（S1 reset means…；失败时 对应条打印 FAIL <判据名> (t=<仿真时刻>) 并… |
| `tb_v103_pipe_bypass.v` | proc_pipeline | 全旁路链不凭空造出黑格或 X 格、每个输入列在输出 burst 里恰好出现一次、四个 窗口级九条行缓存数组的槽位都被写过… | 逐条打印 PASS <ASCII 判据名> / <说明>（C0r ruler…；失败时 对应条打印 FAIL <判据名> / <说明> 并 nfail+1，末行… |
| `tb_v111_key_boot.v` | key_debounce | 复位释放后线松着时的上电角度、去抖窗内外的按下、武装门开后的真人短按、跨过长按阈值。 | 末行打印 `PASS tb_v111_key_boot` 且 errors==0，各腿…；失败时 该条判据打印一行 ` FAIL <判据名>`、errors 加一，末行变… |
| `tb_v112_ip_csum.v` | icmp_tx | 应答帧 IP 首部校验和的十项求和、两次进位折叠、 写回 ip_head[2][15:0] 的那一拍，以及"累加器 20… | 逐矢量打印 ` ok <判据名>` 与 INFO vec<n>…；失败时 打印 ` FAIL <判据名>` 或 ` FAIL vec<n>… |
| `tb_v112_tx_bytes.v` | icmp_tx | 发出去的 gmii_txd 字节流指纹（前导码 + 以太头 + IP 头 + ICMP），用作"IP 校验和累加器 32→20… | 每矢量打印一行 `BYTES v<n> n=<cnt> <逐字节 hex>` 和一行…；失败时 打印 ` FAIL T1 v<n> 字节流里没有 IP 首部的 0x45`… |
| `tb_v113_key_powup.v` | key_debounce | 上电初值本身——不拉复位、不碰键时 key_stable 与两级同步寄存器立不立得起来，以及立不起来时白送的那一枚短按。 | 八条判据各打印一行 `PASS <ASCII 判据名>`，另有 INFO PWRUP…；失败时 对应判据打印 `FAIL <判据名>`、 条数不足打印 `FAIL FLOOR… |
| `tb_v50_rowmath.v` | 被测模块 无（本 tb 不例化… | 产线尺寸 512×300（ROW_STRIDE=1024）下行号算式的两条路：byte_off / 1024 与… | 打印 `PASS basic correct formula`、`INFO…；失败时 按条打印 `FAIL off0` / `FAIL off1024` /… |
| `tb_v50_rows.v` | frame_reasm | 源行没写满时不许发 frame_done，四行全部到齐之后才提交一次。 | 打印 `PASS no commit on 2/4 rows` 与 `PASS…；失败时 打印 `FAIL frame_done on incomplete rows… |
| `tb_v50_rows_prod.v` | frame_reasm | 产线尺寸下三种帧形的提交取舍——缺行、行行沾到但字节数远远不够、300 整行写满。 | 打印 `PASS no commit when only 10/300 rows`…；失败时 打印 `FAIL commit with only 10 rows`… |
| `tb_v571_allow_lead.v` | 被测模块 无（本 tb 不例化 RTL，在 TB… | blank_safe 拉低之后、de 起来之前那段导前量够不够让 allow 先落 0， 以及导前只有 3 个像素拍时… | 打印 `PASS allow high in stable blanking` 与…；失败时 打印 `FAIL allow should be 1 when… |
| `tb_v57_first_ar.v` | frame_commit_lock | commit 请求落在 de=1 的有效视区里（allow=0）时先一个字都不写， 等后面消隐窗开了把这一次拷贝补完。 | 打印 `PASS no write while de=1` 与 `PASS copy…；失败时 打印 `FAIL wrote during active wr=<n>`… |
| `tb_v58_full_done.v` | axi_frame_writer_gated | 64 个字全部写进 fb 才许 done 打一拍；半途 abort 之后不许再发 done。 | 打印 `PASS clean full copy done wr=<n>` 与…；失败时 打印 `FAIL clean copy done=<b> wr=<n>/64`… |
| `tb_v5_bank.v` | axi_frame_saver64 | frame_done 当拍 写 bank 翻到 BANK1、completed_base 锁住刚写完的 BANK0、排空期间… | 依次打印 PASS completed_base locked to bank0…；失败时 对应判据红并打 FAIL completed_base=<值>… |
| `tb_v5_copy.v` | axi_frame_writer_gated | 拷贝只在 blank_safe 消隐窗口内推进，整帧 320 个 64bit 字全部落位且 done 自己走到… | 打印 INFO wr_cnt=<n> (expect 320) ar=<n>…；失败时 打 FAIL timeout wr=<n> ar=<n>… |
| `tb_v5_gated.v` | axi_frame_writer_gated | allow/wr_en 只在消隐期成立——没有 allow 不许有写，allow 不许在 de 或 de_pipe[15]… | 打印 INFO wr_cnt=<n> wr_bad=0…；失败时 打 FAIL no writes、FAIL BRAM write… |
| `tb_v5_lock.v` | frame_commit_lock | copy_base 在 start_copy 那一拍锁存、拷贝途中不随 新 commit_base 改变、copy_done… | 打印 INFO first start base=10000000、PASS…；失败时 打 FAIL no first start（首启超时直接 $finish）… |
| `tb_v5_saver.v` | axi_frame_saver_burst | 64 个连续 16bit 像素在内部攒成 64bit burst 写出去，两拍 flush 能把尾巴挤出打包器并回到 idle。 | 打印 INFO aw_cnt=<n> w_cnt=<n> b_cnt=<n>…；失败时 打 FAIL w_cnt=<n> expected>=16 或 FAIL… |
| `tb_v5_vblast.v` | axi_frame_writer_gated | 整帧写吞吐能否压在有限几个 V-blank allow 窗口内跑完。 | 打印 INFO wr_cnt=<n> expect=2560…；失败时 打 FAIL timeout wr=<n> allow_cyc=<n>… |
| `tb_v6_cover_gate.v` | frame_reasm | 覆盖率门控——丢过一包（留黑洞）的帧必须不提交且计入 stat_bad；完整帧与恢复帧各提交 一次，干净帧不许被记成 bad。 | 依次打印 PASS complete 512x300 frame commits…；失败时 打 FAIL complete frame did not commit… |
| `tb_v6_ingress_integrity.v` | frame_reasm | 逐级计数把丢字定位到某一级，并量 CDC 与打包器 FIFO 的峰值占用（#105/#120 的深度证据）。 | 打印 mode=... words=<TB_WORDS>、drain: waited…；失败时 打 FAIL ingress loses data、FAIL cdc peak… |
| `tb_v6_pingpong.v` | ddr_bank_commit | 连续推帧时「提交→等 saver_idle→翻 bank」这段链是否让每帧整帧落进它自己那笔 commit 记录的 bank。 | 逐帧打印 COMMIT <n> completed_base=<值> (bank…；失败时 打 FAIL commits=<n> expected=2 或 FAIL… |
| `tb_v6_tail_bank.v` | ddr_bank_commit | 帧尾最后 2 个 lane 在反压放开那一刻会不会被提前翻页甩进下一帧。 | 打印 frame0 ... 完整 old=8/8 new=8/8、frame1: 完整…；失败时 打 FAIL frame0 基线就没落位（old=<n> new=<n>）… |
| `tb_v6_vblank_copy.v` | axi_frame_writer_gated | 被测模块 `axi_frame_writer_gated` 与 `frame_commit_lock`（配… | 每档打 `PASS rate=<r>/10 swap <inside one…；失败时 按判据分别打 `FAIL rate=<r>/10 no swap… |
| `tb_v794_osd_glyph.v` | osd_overlay | 被测模块 `osd_overlay`；覆盖点＝glyph 并行 case 译码与 V7.9.3 串行区间比较的等价性，即… | 全程不出 FAIL 行、只打末行 `PASS…；失败时 打 `FAIL code=<码点> rtl_gi=<n> gold=<m>`… |
| `tb_v795_rx_chain.v` | gmii_rx_mac | 被测模块 `gmii_rx_mac` 与 `udp_rx_parser`（UDP_PORT=16'd5001）；覆盖点＝从… | 打 `INFO C1 pay_len=<n>`、`INFO C5 got[0]=a0… |
| `tb_v795_rx_fcs.v` | gmii_rx_mac | 被测模块 `gmii_rx_mac`；覆盖点＝收侧自算 FCS 的四件事——量具自校（TB 造的帧真是标准以太网帧）… | 打 `INFO T0 量具自校通过（debb20e3 == ~2144df1c）`…；失败时 打 `FAIL T0 台架自校：造出来的帧不是标准 FCS（校验值=<c0>… |
| `tb_v796_src_arb.v` | src_arb | 被测模块 `src_arb`（三份实例：u_a 取 T_OFF_CYC=200、u_b 取 T_OFF_CYC=0 作反面对照… | 每条 expect 各打一行 `PASS <段名>`，末行 `PASS…；失败时 对应条打 `FAIL <段名> (t=<时刻>)` 并 errors… |
| `tb_v79_abort_toggle.v` | frame_commit_lock | 被测模块 `frame_commit_lock`（IMG_H=300、DISP_H=600… | 每个相位打一行 `phase=<p>ns aborts=<n> raw=<n>…；失败时 按判据打 `FAIL A1 toggle 在 <n> 个相位上数目不对`（同时… |
| `tb_v81_test_card.v` | test_card | 被测模块 `test_card`（H_ACTIVE=256、V_ACTIVE=150），同参数静止对照 `color_bar`… | 每条 expect 各打一行 `PASS <条名>`，收尾打 `INFO 跨帧变化像素…；失败时 对应条打 `FAIL <条名> (t=<时刻>)`（T11 另逐格打 `格… |
| `tb_v82_src_mode.v` | src_mode | 被测模块 `src_mode`；覆盖点＝长按翻转位到片源模式格雷码的映射：一次没按不许动、一次长按恰好 一格、四态环闭合… | 每条 expect 各打一行 `PASS <条名>`，中间打 INFO 行（复位后…；失败时 对应条打 `FAIL <条名> (t=<时刻>)`、errors… |
| `tb_v83_card_render.v` | test_card | 被测模块 `test_card`（H_ACTIVE=512、V_ACTIVE=300）；覆盖点＝整卡逐像素落到… | 打 `INFO 每帧像素=<n> 白点=<n>/<n>/<n> 跨帧变化=<n>…；失败时 按条打 `FAIL 帧 <i> 只写了 <n> 像素（应 153600）`… |
| `tb_v84_morph.v` | proc_morph | 被测模块 `proc_morph`（H_ACTIVE=24，帧高 H=16），同帧并跑 `proc_box_blur`… | 只打末行 `PASS tb_v84_morph`（errors==0；chk…；失败时 先打带两格缩进的 ` FAIL <条名>`，T1 另把整帧逐行 $write… |
| `tb_v85_sharpen.v` | proc_sharpen | 被测模块 `proc_sharpen`（对照参考实例 `proc_box_blur`，其 bypass 恒 1）… | 末行打印 PASS tb_v85_sharpen，且 got 与各段手算值逐位重合…；失败时 对应判据前打印 " FAIL <判据名>"，T1 附 "T1… |
| `tb_v86_pipe_sel.v` | proc_pipeline | 被测模块 `proc_pipeline`（实例 up）与 `effect_ctrl`（实例 u_eff）… | 末行打印 PASS tb_v86_pipe_sel，波形上首个 de_out 与首个…；失败时 对应判据前打 " FAIL #<序号> <判据名>"，T1 附八行 got 的… |
| `tb_v87_key_long.v` | key_long | 被测模块 `key_long`（实例 u_dut，HOLD_CYC=30_000、ARM_CYC=10_000）… | 每次 hold_n 打一行 "INFO <段名>：按住期间 short_pulse…；失败时 对应判据前打 " FAIL <判据名>"，末行变 FAIL… |
| `tb_v88_gamma.v` | gamma_lut | 被测模块 `gamma_lut`（实例 dut）；覆盖点＝en=0 的逐位透明、wr 翻转位写协议（电平不变不重写… | 末行打印 PASS tb_v88_gamma，波形上 en=0 段 dout 与…；失败时 对应判据前打印 " FAIL <判据名>"，末行变 FAIL… |
| `tb_v89_align.v` | proc_box_blur | 被测模块 `proc_box_blur`(u_blur)、`proc_sharpen`(u_shp)… | 每条 expect 打 "[…] PASS <判据名>"，五个被测各有一行"整帧…；失败时 打 " FAIL <判据名>" 或 "FAIL… |
| `tb_v90_latency.v` | frame_latency | 被测模块 `frame_latency`（实例 dut）；覆盖点＝读数精确等于台架数出来的拍差、事件配对缺步或晚到 时不出数… | 末行打印 PASS tb_v90_latency，读数满足 tot>=c1+c2…；失败时 对应判据 前打印 " FAIL… |
| `tb_v92_seam_bleed.v` | proc_box_blur | 被测模块 `proc_box_blur`(u_blu)、`proc_sharpen`(u_shp)… | 末行打印 PASS tb_v92_seam_bleed，波形上四路 de_out…；失败时 按 " FAIL C<n> <模块名> <判据名>" 打行并让 末行变… |
| `tb_v93_split_ctrl.v` | split_ctrl | 被测模块 `split_ctrl`（两台：dut 取 .TICK_BITS(6)，dut16 用默认档，均… | 每条 chk 打一行 " PASS <判据名>"、末行 PASS…；失败时 对应判据前打 " FAIL <判据名>" （watch 的 DBG 行先给出… |
| `tb_v94_zoom_sel.v` | zoom_ctrl | 被测模块 `zoom_ctrl`（实例 dut，INV_LO=256、INV_HI=512、STEP=2）… | 每条 chk 打 " PASS <判据名>"，末两行为 "TB DONE…；失败时 对应 判据打 " FAIL <判据名>"，档不匹配处打 "DBG T3 档… |
| `tb_v95_zoom_snap.v` | zoom_snap | 被测模块 `zoom_snap`（实例 u_dut）与下游 `snap_cross`（实例 u_x，.W(20)… | 每条 expect 打 "PASS <判据名>"，中间一行 " stats:…；失败时 对应判据打 "FAIL <判据名> (t=<时刻>)"，撕烈由探测器打前 3… |
| `tb_v96_zoom_scan.v` | zoom_mapper | 一条过屏幕 中心的扫描行上逐像素的 floor+frac 自洽、源列单调性、中心格不动、左右 OOB 对称、90° 的… | 每条判据各打一行 `PASS <M0..M6 标签>`，另打流水线延迟与…；失败时 对应那条打 `FAIL <标签> (t=<时刻>)` 并 errors… |
| `tb_v97_seam_scan.v` | split_display | 标记蓝线占的列数与落点、左右两窗内容选择、de 透传、越界涂黑、 消隐期不新画线、x_sel 落后 9… | S1..S8 各打一行 `PASS <标签>`，末行 `PASS…；失败时 对应那条打 `FAIL <标签> (t=<时刻>)` 并 errors… |
| `tb_v98_c8_edge_column.v` | pl_video_top | 顶层坐标图判据链（C0a..C12）中与"每一行第 0 格" 有关的那一族：C8a 原图抽头、C8b 处理抽头的行首格，以及… | 每条判据各打一行 `PASS <C 标签> / <说明>`，C8 与 C8c…；失败时 那条打 `FAIL <C 标签>`、nfail 加一， 不符格另打反例行… |
| `tb_v98_top_seam.v` | pl_video_top | 顶层坐标图判据链（C0a..C12）加 C8cself（期望 函数自证）与 C12… | 每条判据各打一行 `PASS <C 标签> / <说明>`，C12 另打 `C12…；失败时 那条打 `FAIL <C 标签>`、nfail 加一， C8/C8c… |
| `tb_v99_unisim_sim.v` | clk_gen | 三路输出时钟的 频率比例、绝对周期与 locked 起没起来，钉住"用它搭的顶层台架时钟可信"这一前提。 | 每判据打一行 `PASS <C1a/C1b/C3/C2 标签> / <说明>`…；失败时 对应那条打 `FAIL <标签> / …` 并 nfail 加一，末行改打… |
| `tb_writer_abort.v` | axi_frame_writer_gated | abort 那一拍之后仍在途的 R 读拍会不会串进下一帧的头几拍、outstanding 计数 会不会被旧拍的 rlast… | A1..C2 各打一行 ` PASS <判据名> / <说明> / <计数值>`，随后…；失败时 对应那条打 ` FAIL <判据名> / …` 并 fails 加一，失序的头… |
| `tb_zoom_fit_corners.v` | zoom_fit | 六个角度下拟合倍率能不能把源图四个角都留在屏内（A），以及钉 1.00x 的正对照必须 掉角（B），只用这两个 DUT… | 每个角度一行 `PASS cov angle=<a> inv_fit=<v>…；失败时 对应那条打 `FAIL A_clipped angle=<a>… |
| `tb_zoom_frac.v` | zoom_mapper | 缩放支与旋转支的 x_out/y_out 与 frac_x/frac_y 是否描述同一格、旋转态到底有没有非零小数，以及… | 打 `PASS H0 reference_table_fresh / angle=30…；失败时 逐点打 `FAIL D<n>… |
| `tb_zoom_mapper.v` | zoom_ctrl | mapper 的恒等与 0.5x 边界格及其 oob 旗标、rot_en=1 且 angle=0 的 恒等，ctrl… | expect_xy 静默（它只在失配时打印），末行 `PASS…；失败时 失配的 那个点打 `FAIL <tag> got (<xo>,<yo>)… |

```bash
bash build/sim/run_one.sh tb_crc32        # 单支台架：xvlog → xelab → xsim，判定词在末行
```
