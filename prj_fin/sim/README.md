# `sim/`：台架怎么跑、每支回答什么

台架只回答一个问题：这一支 RTL 在仿真里有没有按定义行事。它不看板子，也不看时序；时序在 `build/reports/` 的实现报告里，板上行为在 `board/` 的读数里。

## 最终交付结果

19 支标准回归 `fail=0`；完整视频台架的 C17/C25/C26 专项 PASS。判定副本在 `sim/results/`：`regression.txt`、`tb_video_pipeline_top_report.txt`、`udp_checksum.txt`、`c31_edge_rim.log`。

## 跑一支

在仓库根执行。用 ModelSim 时：

```bash
MSIM_BIN=<ModelSim>/win64 bash build/sim/run_msim.sh tb_crc32
```

`MSIM_BIN` 指到 ModelSim 的 `win64`（或 Linux）目录。脚本会先编译整棵 `src/rtl`、`sim/prim` 和指定的台架，再跑仿真，最后打印 `RESULT <tb> PASS` 或 `FAIL`。用 xsim 时入口是 `build/sim/run_one.sh <tb>`，判定行是 `VERDICT <tb>: ...`。

同一时刻只能有一个仿真器写同一个 work 目录。脚本会在门口检查，发现已有 xsim 或 ModelSim 在跑就拒绝启动，避免两跑的行混进同一份日志。

## 一次跑完 92 支

```bash
vivado -mode batch -nojournal -log sim/xsim.log -source build/sim/run_sim.tcl
# SIM_TB=tb_crc32,tb_timing 只跑点名的几支；SIM_ONLY=1 只编译；SIM_VERBOSE=1 打整段流水
```

每支台架出一行 `RESULT <tb> ...`。编译失败打 `XVLOG FAILED` 并以 1 退出；某支例化失败打 `RESULT <tb> ELAB_FAIL`，不中断其余。

## 判定怎么读

台架只有三种结局：通过、失败、没测到。判定行在末行，`FAIL` 行带具体数值。退出码分开：0 通过，1 编译或例化失败，2 拒绝启动，3 有判据没过，4 一条判定都没打。

“没测到”不是通过。台架没打印判定行、编译没找到模块、样本集为空，都算没测到；这类结果不能写成绿色。

## 三条口径

- 完整清单以 `sim/` 下 92 个 `tb_*.v` 文件头为准；本页按验证域给出索引，不复制每支台架的逐条判据。
- 文件名里的 `v98`、`v103` 是历史迭代编号，不承担信息；判据看的是“被测模块 + 覆盖点”，不是文件名里的轮次。
- 台架通过不等于板上通过。这一层证明的是 RTL 行为；板级读数和人眼验收在 `board/acceptance.md` 与 `report/verification.md`。

## 按验证域分组

### 顶层视频链

| 台架 | 回答什么 |
|---|---|
| `tb_video_pipeline_top.v` | 顶层坐标图判据链：几何、行标签、竖缝和越界填黑在同一帧里是否对齐 |
| `tb_pipe_bypass.v` | 全旁路链不凭空造黑格或 X 格，每个输入列在输出里恰好出现一次 |
| `tb_display_edge_rim.v` | 效果窗口级的上/下/左/右边界夹取和行标签是否同一拍 |
| `tb_edge_rim_bottom_wrap.v` | 绕回连续流下帧底最后一行的下邻是本行，不是下一帧第 0 行 |
| `tb_edge_rim_wrap_clamp.v` | 绕回流下图像上下边界的 3×3 夹取；带一个必须变红的旧行为对照 |
| `tb_edge_rim_wrap_diff.v` | 首行/末行窗口影响是否交叉污染；用负对照证明尺子能红 |
| `tb_c8_edge_column.v` | 每一行第 0 格的抽头与原图/处理图选择 |
| `tb_seam_scan.v` | 分屏蓝线列数、左右内容选择、de 透传、越界涂黑 |

### 网络、重组与遥测

| 台架 | 回答什么 |
|---|---|
| `tb_eth_top_rgmii.v` | RGMII 双沿、IDDR/IDELAY、CDC、ARP 应答和回发时钟的整链闭环 |
| `tb_udp_reasm.v` | 正序、乱序、重复包、坏包、断帧后再成帧是否互不污染 |
| `tb_rows.v` | 源行没写满不许提交，所有行到齐后只提交一次 |
| `tb_rows_prod.v` | 产线 512×300 下缺行、字节不足、300 行写满三种帧形的提交取舍 |
| `tb_cover_gate.v` | 丢过一包的帧不提交且计入坏包；完整帧和恢复帧正常提交 |
| `tb_eth_ingress_integrity.v` | 逐级计数定位丢字，并量 CDC/打包 FIFO 的峰值占用 |
| `tb_udp_telemetry.v` | 遥测帧从 GMII 口逐字节抓取，DA/SA/IP/UDP/载荷/校验和全部比对 |
| `tb_rx_fcs.v` | 收侧 FCS 的量具自校与标准帧校验 |
| `tb_gmii_rx_cdc.v` | 恢复时钟到逻辑时钟的 GMII 字节流不丢不重，帧间空隙保留 |

### DDR、帧缓存与提交

| 台架 | 回答什么 |
|---|---|
| `tb_fb_roundtrip.v` | 38400 个字写入/读回的地址和数据是否逐位一致 |
| `tb_fb_pingpong.v` | 提交后等 saver idle 再翻 bank，每帧落进自己的 commit 记录 |
| `tb_fb_rd5x.v` | 5 槽帧缓存读口的输出像素与请求配准 |
| `tb_tail_bank.v` | 帧尾最后两个 lane 在反压放开时不会被提前翻页甩进下一帧 |
| `tb_saver.v` | 64 个连续 16 位像素攒成 64 位 burst，尾部两拍能清空 |
| `tb_writer_abort.v` | abort 后在途的 R 读拍不串进下一帧，outstanding 计数能回落 |
| `tb_commit_strobe.v` | 帧提交脉冲与行标签/覆盖条件同拍 |
| `tb_allow_lead.v` | blank_safe 拉低到 de 起来之间，allow 是否提前落 0 |

### 几何、效果、OSD 与片源

| 台架 | 回答什么 |
|---|---|
| `tb_zoom_scan.v` | 缩放扫描行的 floor+frac 自洽、源列单调、中心格不动、左右 OOB 对称 |
| `tb_zoom_fit_corners.v` | 多个角度下拟合倍率能把源图四角留在屏内，钉 1.00x 的正对照会掉角 |
| `tb_zoom_frac.v` | 缩放支与旋转支的坐标和小数描述同一格 |
| `tb_rotate_mapper.v` | 0° 恒等映射与 90° 中心不越界、输出不出 X |
| `tb_rotate_window.v` | 旋转开启时效果链仍被施加，不被强制旁路 |
| `tb_bilinear_core.v` | 双线性四抽头的恒等、边界和系数组合 |
| `tb_osd_overlay.v` | 五行 OSD 整串逐字符、位宽饱和、片源标签、效果码和缩放档 |
| `tb_osd_glyph_rom.v` | 字形并行使能与串行区间比较的等价性 |
| `tb_gamma.v` | gamma LUT 的写协议和 en=0 透明 |
| `tb_test_card.v`、`tb_card_render.v` | 测试图卡的静止帧、跨帧变化和整卡逐像素落位 |
| `tb_src_life.v` | 复位无源、发布转有源、停发超时、重新发布解除 |
| `tb_src_arb.v`、`tb_src_arb_why.v` | 三路片源仲裁与换手判决那一拍的输入快照 |

### 控制、按键、时钟与底层

| 台架 | 回答什么 |
|---|---|
| `tb_link_monitor.v` | 丢字、坏包、断流后的快照和帧间隔 min/last/max/sum |
| `tb_split_ctrl.v` | 分屏位置、扫描方向和手自动切换 |
| `tb_zoom_sel.v`、`tb_zoom_snap.v` | 缩放档位选择与跨域快照 |
| `tb_key_boot.v`、`tb_key_powup.v`、`tb_key_long.v` | 上电初值、去抖窗、短按/长按阈值 |
| `tb_src_mode.v` | 长按翻转位到片源模式格雷码的映射 |
| `tb_timing.v` | x/y 计数、de 有效拍数、每帧一次 frame_done |
| `tb_cdc_capacity.v` | 异步 FIFO 的满/空边界和 8192 格容量 |
| `tb_crc32.v` | 以太网反射 CRC 的初值、单字节更新和清零 |
| `tb_uart_decode_bits.v` | 串口命令里 5 个 0/1 字符到位序的约定 |
| `tb_unisim_sim.v` | 三路输出时钟的频率、周期和 locked |

## 全部台架文件

`sim/` 下共 92 支 `tb_*.v`。完整文件名如下，逐支判据写在文件头注释里：

```text
tb_abort_toggle.v      tb_align.v             tb_allow_lead.v        tb_bank.v
tb_bilinear_core.v     tb_c8_edge_column.v    tb_card_render.v       tb_cdc_capacity.v
tb_commit_strobe.v     tb_copy.v              tb_cover_gate.v        tb_crc32.v
tb_ddr_line_locality.v tb_display_edge_rim.v  tb_edge_rim_bottom.v   tb_edge_rim_bottom_wrap.v
tb_edge_rim_wrap_clamp.v tb_edge_rim_wrap_diff.v tb_eth_ctrl_arb.v   tb_eth_ingress_integrity.v
tb_eth_top_rgmii.v     tb_eth_video.v         tb_fb_bilinear.v       tb_fb_pingpong.v
tb_fb_rd5x.v           tb_fb_roundtrip.v      tb_fb_vblank_copy.v    tb_first_ar.v
tb_fit_rot.v           tb_full_done.v         tb_gamma.v             tb_gated.v
tb_gmii_rx_cdc.v       tb_head_rot_displace.v tb_icmp_len_wrap.v     tb_icmp_ping0.v
tb_icmp_rx_len.v       tb_icmp_tx_cksum.v     tb_ip_csum.v           tb_key_boot.v
tb_key_long.v          tb_key_powup.v         tb_latency.v           tb_link_monitor.v
tb_lock.v              tb_morph.v             tb_osd_glyph_rom.v     tb_osd_overlay.v
tb_pipe_bypass.v       tb_pipe_sel.v          tb_proc_gray.v         tb_ps_publish.v
tb_raw_delay.v         tb_reasm_bounds.v      tb_rotate_mapper.v     tb_rotate_window.v
tb_rowmath.v           tb_rows.v              tb_rows_prod.v         tb_rx_chain.v
tb_rx_fcs.v            tb_saver.v             tb_saver_tail_full.v   tb_seam_bleed.v
tb_seam_scan.v         tb_sharpen.v           tb_shown_rate.v        tb_split_ctrl.v
tb_src_arb.v           tb_src_arb_why.v       tb_src_life.v          tb_src_mode.v
tb_sync_fifo.v         tb_tail_bank.v         tb_tap_sched.v         tb_test_card.v
tb_timing.v            tb_tx_bytes.v          tb_uart_decode_bits.v  tb_udp_parser.v
tb_udp_reasm.v         tb_udp_telemetry.v     tb_unisim_sim.v        tb_vblast.v
tb_video_pipeline_top.v tb_writer_abort.v     tb_zoom_fit_corners.v  tb_zoom_frac.v
tb_zoom_mapper.v       tb_zoom_scan.v         tb_zoom_sel.v          tb_zoom_snap.v
```

## 清单之外

清单之外没有别的口径：某支台架怎么判、判据几跳，写在该文件头注释里，与本页同一处来源。新增或修改台架时，先改文件头判据，再同步本页对应分组和 `sim/results/`。
