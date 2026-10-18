# 项目完整说明书（写给冷读的 AI —— 可直接整份粘贴）

> ⚠ 版本戳（2026-10-17 加）：本文件里的具体数字取自**第 118 批那一次构建**（bit `cd04907e1369`），是推导用的样本，**不是当前板上这一版**（r132，bit `cb907d3e4898`）。现读口径看根 `README.md` 的「关键数字与出处」一节与 `data/metrics.csv`；两处的差别与为什么不重写这份教案，登记在 `report/log/issues.md` #479 末段。
> **这份文档的用途**：把它整份发给任何一个 AI（网页版即可），让它在不看仓库的情况下正确回答关于这个
> 项目的实现问题。因此它的写法是：**每条事实带 `路径:行号`**，凡是取舍都写"为什么"，凡是没做/没有的
> 都显式写 `未找到` 并给检索式。**文档宁可长，不要留白**——留白处就会被猜。
>
> **写作纪律（本文自我约束）**
> - `实测` = 有原始日志/报告/台架输出可对；`机理` = 只从源码读出、没有真板或仪器读数；
>   `未找到` = 搜过且确实不存在。没有板子在场，所以任何"板子上的行为"一律标 `机理`。
> - 行号会漂，命令不会。每节末尾给"重取这些数"的命令；与仓库有冲突时以命令输出为准。
> - **第 21 节是"常见误答纠正表"**，如果你只来得及读一节，读那一节。
>
> 仓库根：`D:\Xilinx\Prj\pro\Video_Processing`。下文所有路径相对该根。RTL 总量 84 个 `.v` / 11768 行；
> PS 裸机 C 2477 行；上位机零第三方依赖脚本 29 支；门禁 **24 条判定项**（条目编号到 23）。

## 目录

| 节 | 标题 |
|---|---|
| 0 | 30 秒定位 |
| 1 | 这个项目是什么：端到端数据流逐跳 |
| 2 | 硬件、引脚、外部器件与它们的取舍 |
| 3 | 层级树与实例清单（网表级） |
| 4 | 时钟架构（两颗 MMCM、参数、命名、派生） |
| 5 | 复位链与上电次序 |
| 6 | 跨时钟域（CDC）全表 |
| 7 | 网络接收通路：RGMII → DDR，按级讲原理 |
| 7.0 | 一条结构事实：ETH 逻辑是单时钟域 |
| 7.1 | 物理层：IDDR / IDELAYE2 / ODDR 与 tap 的四个口径 |
| 7.2 | GMII MAC：前导、CRC32 残值、脉冲契约、有没有 DA 过滤 |
| 7.3 | UDP / ARP / ICMP：按字节索引的解析器、ARP 不是表、发送侧被常量关掉 |
| 7.4 | 帧重组：4 字节小端偏移、行号用除法、三门判帧 |
| 7.5 | CDC 缓冲：为什么是 36 bit × 8192 |
| 7.6 | AXI 写侧：三代打包器与为什么用 64 位那版 |
| 7.7 | 乒乓 bank 提交协议 |
| 7.8 | 健康与观测计数器语义表 |
| 8 | 显示与处理通路：DDR → HDMI，按级讲原理 |
| 8.1 | 光栅产生 |
| 8.2 | 片源仲裁（没有 FSM，以及 20 ms 滞回） |
| 8.3 | 两条 DDR→显示 BRAM 的搬运引擎 |
| 8.4 | 帧提交锁与消隐窗 |
| 8.5 | 显示帧缓存：为什么拆两块 BRAM 阵列 |
| 8.6 | 缩放/旋转地址生成：逆映射、Q8、无运行时除法 |
| 8.7 | 双线性读侧 |
| 8.8 | 效果链七级（逐个算子的数学与硬件） |
| 8.9 | 原图路与处理路（差一整拍） |
| 8.10 | 分屏与接缝 |
| 8.11 | OSD（5×7 字库、为什么折算放在写侧） |
| 8.12 | 延迟测量与 lane25 武装协议 |
| 8.13 | TMDS 编码与串化（2×OSERDESE2 10:1） |
| 9 | 流水线深度唯一真源与"门控与数据同拍" |
| 10 | 约束逐条（每条的作用与理由） |
| 11 | 时序优化：做过什么、量到什么、为什么 |
| 12 | 实现后的真实读数（时序 / 资源 / 功耗 / DRC） |
| 13 | 寄存器与观测面完整位表 |
| 14 | PS 裸机固件 |
| 15 | 上位机工具与协议 |
| 16 | 构建、仿真、烧写：可照抄的命令序列 |
| 17 | 机械门禁逐条（24 条判定） |
| 18 | 已知缺陷、边界与开放项 |
| 19 | "我要改 X，该看哪几行" |
| 20 | 术语与编号约定 |
| 21 | 常见误答纠正（先读这节） |
| 22 | 这份文档没写的东西（诚实清单） |

---

## 0. 30 秒定位

| 问 | 答 |
|---|---|
| 一句话 | Zynq-7020（Pynq-Z1 类板，**裸机不是 Linux**）上的视频通路：千兆 UDP 收图 → DDR 乒乓帧缓存 → 三种片源仲裁 → 缩放/旋转/七级效果 → 自研 TMDS HDMI 输出；PS 侧跑串口命令与 SD 回放 |
| 顶层 | `src/rtl/top/system_top.v:4`（Vivado 的 top 由 `build/tcl/build_system_axigpio.tcl:288` 设定） |
| 显示 | 1024×600@50 MHz 像素钟（算得 59.53 Hz），RGB565 → TMDS 24bit RGB888 编码 |
| 素材 | 512×300 RGB565，一帧 307200 B |
| 判定"对" | `bash build/gates.sh`（24 条判定项）任一红即不采纳 |
| 跑起来 | JTAG：`bash board/scripts/board_flash.sh`（易失）；固化：`make_boot_image.sh` + `board/tcl/flash_qspi.tcl` |
| 三处手写 DDR 基址 | `src/rtl/top/system_top.v:139,144`、`src/rtl/eth/eth_udp_video_top.v:67-68`、`src/ps/sd_play.c:35`（**BD 不回读这三个**） |
| 最容易答错的三件事 | ① 乒乓在 **DDR** 不在 BRAM；② 时序收敛只看 routed 报告；③ RGMII 输入窗**根本没写**，是已知债不是回归 |

---

## 1. 这个项目是什么：端到端数据流逐跳

一条图像数据的完整旅程（每一跳都在本文后面有专门小节，这里只给"谁交给谁"）：

```
PC --UDP/1392B--> RTL8211F PHY --RGMII--> FPGA 引脚 eth_rxc/rxd/rx_ctl
  ├─[7.1] rgmii_rx.v：IDELAYE2(固定 31 档) + IDDR(SAME_EDGE_PIPELINED) 双沿解串 → gmii_rxd[7:0] @125 MHz
  ├─[7.2] gmii_rx_mac.v：前导/SFD 找界 → CRC32 残值判好帧 → m_valid/m_sof/m_eof/m_good/m_bad 脉冲流
  ├─[7.3] udp_rx_parser.v：按字节索引比 0x0800 / ihl / proto=17 / dport=5001 → p_* 载荷流
  ├─[7.4] frame_reasm.v：吃 4 字节小端"帧内偏移" → row=off/1024、wr_addr=off[18:1] → 16bit 写 + 行覆盖位图
  │        └ 三门同时满足才发 frame_done（187 行的 rows_hit、字节饱和累加器、无 bad_frame）
  ├─[7.5] dc_fifo.v：36bit×8192 异步 FIFO（地址+数据+flush 装在同一个条目里原子跨域）
  ├─[7.6] axi_frame_saver64.v：两个 16bit 写拼一个 64bit 字 → AXI3 AW/W（AWLEN=0，outstanding 8）
  └─[7.7] ddr_bank_commit.v：frame_done 转翻转位 → 3FF 边沿 → bank 翻转 → 把"这一帧的基址"提交
                     ↓  DDR3（PS 的存储器控制器，PL 通过 HP0 口写）
  ├─[8.2] src_arb.v：ETH / PS / 图卡 三方抢同一条 HP0，只在"两个引擎都空闲"时换手
  ├─[8.4] frame_commit_lock.v：等到消隐窗（disp_quiet）才允许把 DDR 里那一帧搬进显示 BRAM
  ├─[8.3] axi_frame_writer_gated.v：ARLEN=15 INCR、outstanding 4、64bit 直写 BRAM
  ├─[8.5] frame_buffer_w64.v：显示帧缓存（两块 BRAM 阵列 32768+8192 个 64bit 字）
  ├─[8.6] zoom_mapper.v：**逆映射** 显示(x,y)→源(sx,sy)，Q8 三角表 + Q8 倒数尺度，含旋转
  ├─[8.7] fb_bilin.v：一个源像素用 4 拍读 4 个 64bit 字，取 4 邻域 → bilin_lerp 双线性
  ├─[8.8] proc_pipeline.v：gamma→gray→invert→blur→sharpen→sobel→binary→morph，固定 15 拍
  ├─[8.9] 原图走 raw_line_delay(4 行环) + 15 级 skid，与处理路在同一个抽头上混合
  ├─[8.10] split_display.v：左原图右处理图，接缝由 seam_src 提前算好
  ├─[8.11] osd_overlay.v：叠角度/FPS/阈值/缩放码/延迟/温度等状态字
  └─[8.13] rgb2dvi.v：3×tmds_encoder(8b→10b) + 4×tmds_serializer(OSERDESE2 10:1 DDR) → 差分对
                     ↓
                 HDMI 面板 / 采集卡
```

同时存在的第二条源：PS 固件从 SD 卡（自研只读 FAT32）把 512×300 帧 **直接 DMA/写进 DDR 的第三个
bank** `0x1010_0000`，然后翻转 `gpio_o[18]` 请求 PL 拷贝一次（`src/ps/sd_play.c:786`、
`src/rtl/util/ps_publish.v`）。第三条源是 PL 自己生成的图卡（`test_card.v`，TEST 模式）。
**"片源"之争的实质是同一条 HP0 AXI 口的所有权**，不是"谁有数据"（`src/rtl/util/src_arb.v:4` 原文：
"这件事的正确答案**不是**'哪边有数据'，而是'哪边活着 + 现在能不能安全换手'"）。

重取本节骨架：
```bash
grep -n "^\s*\w\+ #(\|^\s*\w\+ u_\w* *(" src/rtl/top/pl_video_top.v | head -40
grep -n "frame_done\|commit\|owner_eth" src/rtl/eth/eth_udp_video_top.v | head
```

---

## 2. 硬件、引脚、外部器件与它们的取舍

| 项 | 值 | 出处 / 为什么 |
|---|---|---|
| 器件 | **`xc7z020clg484-2`**（Zynq-7020，速度等级 2）| `data/metrics.csv` 第 2 行"器件与工具链"；资源上限见 §12 的 Available 列 |
| 系统钟 | `sys_clk` 50 MHz，引脚 **W17**，LVCMOS33 | `src/constraints/rk_zynq7020.xdc:5`；`create_clock -period 20.000` 在 `:6` |
| RGMII 收钟 | `eth_rxc` 125 MHz，引脚 **Y19**（PHY 恢复出来的） | `:20` 引脚、`:36` `create_clock -period 8.000 -name eth_rxc` |
| RGMII 收数据 | `eth_rx_ctl` V19、`eth_rxd[0..3]` = W20/W21/U20/V20 | `:21-25` |
| RGMII 发口 | `eth_tx_clk` **AB22**、`eth_tx_ctl` AB21、`eth_txd[0..3]` = T21/U21/AA22/AA21 | `:26-31`；⚠ 注意 `eth_tx_clk` 是 **FPGA 输出给 PHY** 的，见 §7.1 |
| MDIO/MDC | `eth_mdc` AB20、`eth_mdio` AB19，但**功能上不用** | `:32-33`；驱动见 §5/`:112-117` |
| PHY 复位 | `eth_rst_n` **Y21，是输出**，由 24 位上电计数器最高位驱动 | `:34`；`src/rtl/top/system_top.v:42,108-112` |
| HDMI | 三对数据 + 一对钟，`IOSTANDARD TMDS_33`；p/n 必须同真差分对：W16+Y16（钟）、AA17+AB17（[0]=蓝）、U17+V17（[1]=绿）、U15+U16（[2]=红） | `:12-19`；通道顺序 `src/rtl/hdmi/rgb2dvi.v:21` |
| 按键 | `key1_n` W18、`key2_n` V14，异步 | `:8-9`，false path `:59-60` |
| LED | `led[0]` V15、`led[1]` V13 | `:10-11` |
| 配置 bank | `CFGBVS VCCO`、`CONFIG_VOLTAGE 3.3` | `:2-3` |
| 位流压缩 | `BITSTREAM.GENERAL.COMPRESS TRUE` | `:77` |
| PHY | RTL8211F-CG。**RXDLY 由原理图 p8 的 R57/R59 4.7 K 上拉打开** ⇒ 2 ns 额外延迟加在 **RXC** 上而不是数据上 | `src/constraints/r116_rgmii_input_window.xdc:8-17`（这段是本工程唯一记录 PHY 窗来源的地方） |
| PHY 工作模式 | **靠板上 strap**，本工程数据面完全不碰 MDIO | `src/rtl/top/system_top.v:113-117` 原文："综合报 `Synth 8-3917 port eth_mdc driven by constant 0` 是**陈述而不是缺陷**；要真做 PHY 寄存器读写得另起一个位时序机" |
| QSPI Flash | 工具侧写 `mx25l25645g-qspi-x4-single`（板丝印是 W25Q256FV，但 `w25q256jw*` 的 `COMPATIBLE_PARTS` 只列 zynquplus ⇒ 换它得 `[Labtoolstcl 44-655]`） | `board/tcl/flash_qspi.tcl:12,22-26,68-73` |
| 网络身份 | MAC `00:11:22:33:44:55`、IP `192.168.1.10`、UDP 端口 `5001` | `src/rtl/top/system_top.v:145,157-159`（**手写常量，无回读校验**） |

**关键取舍（为什么是这样，代码注释里的原话）**
- 为什么不用 Soft-EM/PYNQ 网络栈：数据面全在 PL，PS 不参与收包。`src/ps/main.c:1571` 注释原文
  "UDP RX is in PL"；PL 侧收包链是 `src/rtl/eth/`（4505 行）。
- 为什么几何常量集中在顶层：`src/rtl/top/system_top.v:134-135` 原文——"原来 512/300/0x1000_0000 在下面
  两个例化上各写一遍字面量……没有任何东西阻止两边不一致 ⇒ 现象是'写进去的帧几何与读出来的显示几何
  对不上'（整幅错位/撕裂），既不是综合错误也不是仿真必红。换分辨率因此从'全文搜字面量'变成'改这四行'"。
- 为什么 DDR 第三个 bank 要单列：`system_top.v:142-143` 原文——"这个数**必须与固件里的 FRAME_ADDR
  一致**：`src/ps/sd_play.c` 与 `src/ps/main.c` 各有一处，改这里不改那边 ⇒ 现象是'PS 片源在屏上不动'"。

重取：`grep -n "create_clock\|set_false_path\|set_clock_uncertainty\|IOSTANDARD" src/constraints/rk_zynq7020.xdc`

---

## 3. 层级树与实例清单（网表级）

```
system_top                              src/rtl/top/system_top.v:4
├─ u_bd   design_1_wrapper              system_top.v:75    PS7 + 3×AXI GPIO + HP0 + FCLK_CLK0
├─ u_idelay_clkgen   clk_gen            system_top.v:121   只取 clk_200m + locked
├─ u_lm_axi  snap_cross W=320           system_top.v:214   健康快照 → fclk0 给 PS 读
├─ phy_rst_cnt (内联 24b)               system_top.v:108-112
├─ u_eth  eth_udp_video_top             system_top.v:173   src/rtl/eth/eth_udp_video_top.v:7
│  ├─ u_rgmii  gmii_to_rgmii            eth_udp_video_top.v:73
│  │   ├─ u_rgmii_rx  → 5×IDDR + 5×IDELAYE2 + 1×IDELAYCTRL + BUFG   rgmii_rx.v:47-140
│  │   └─ u_rgmii_tx  → 5×ODDR                                      rgmii_tx.v:19-49
│  ├─ u_rx_mac   gmii_rx_mac            :186   前导/CRC/脉冲流
│  ├─ u_rx       udp_rx_parser          :193   主线解析器（不是厂商 udp_rx）
│  ├─ u_arp / u_icmp                     :126 / :140   监听同一束 gmii_rxd
│  ├─ u_ctrl     eth_ctrl               :210ish  发送侧仲裁（当前发送被常量关掉）
│  ├─ u_icmp_fifo sync_fifo 8b×2048      :119   full/empty/level 三口全部空接
│  ├─ u_reasm    frame_reasm             :235   偏移→行地址、三门判帧
│  ├─ u_cdc      dc_fifo 36b×8192        :298   gmii_rx_clk → axi_clk
│  ├─ u_saver    axi_frame_saver64       :354   打包 64bit + AXI3 写
│  └─ u_commit   ddr_bank_commit         :330   乒乓提交
└─ u_pl   pl_video_top                  system_top.v:258   src/rtl/top/pl_video_top.v:8
   ├─ u_clk  clk_gen                     :128   clk_pix / clk_pix5x 的真出处
   ├─ u_k1/u_k2 key_debounce             :136/:139   CNT_MAX=1_000_000
   ├─ u_k1l  key_long                    :148   HOLD 30M / ARM 10M（0.6 s / 0.2 s）
   ├─ u_mode src_mode                    :157   四态格雷码环
   ├─ u_ang  angle_ctrl                  :183   ⚠ 跑在 sys_clk 不是像素钟
   ├─ u_eff  effect_ctrl                 :198   PS→像素域的准静态控制字同步
   ├─ u_t    video_timing_1024x600       :226
   ├─ u_zfit/u_zctrl/u_zmap              :322/:325/:343   缩放/旋转地址生成
   ├─ u_arb  src_arb                     :421   T_OFF_CYC=2_000_000（=20 ms @100 MHz）
   ├─ u_cmt  frame_commit_lock           :430   消隐窗 + CDC
   ├─ u_row  axi_frame_writer_gated      :454   ETH 帧 → 显示 BRAM
   ├─ u_pub  ps_publish                  :564   bit18 翻转协议
   ├─ u_life src_life                    :588   500 ms / 30 帧看门狗
   ├─ u_lat  frame_latency               :624   延迟测量（6 个字一组）
   ├─ u_zsnap zoom_snap                  :652   20bit 快照 + 晚 8 拍发沿
   ├─ u_zoom_axi / u_split_x / u_lat_x  snap_cross  :674 / :876 / :980
   ├─ u_aw   axi_frame_writer64          :692   PS 帧 → 显示 BRAM
   ├─ u_bilin fb_bilin                   :732   （内部 u_fb = frame_buffer_w64，fb_bilin.v:65）
   ├─ u_bar  test_card                   :759
   ├─ u_raw  raw_line_delay              :788   LINES=4、W=1024、DW=17
   ├─ u_pipe proc_pipeline               :800   H_ACTIVE=2*IMG_W=1024
   ├─ u_split_ctrl/u_seam_src/u_split     :885 / :904 / :911
   ├─ u_fpsr shown_rate                  :941   WIN_LAST=49_999_999
   ├─ u_osd  osd_overlay                 :999   OUT_W=1024、OUT_H=600
   └─ u_dvi  rgb2dvi                     :1026  3×tmds_encoder + 4×tmds_serializer（各含 OSERDESE2×2 + OBUFDS）
```

**不在位流里的东西（别当现役件引用）**
- `src/rtl/top/pl_demo_top.v:4` —— 纯 PL 顶层演示，`src/rtl/eth/snap_cross.v:27` 明示。
- `src/rtl/process/rotate/rotate_mapper.v:5` —— **未被任何文件例化**（`grep -rn rotate_mapper src/rtl/` 只命中它自己的
  `module` 行）。现役旋转折叠在 `zoom_mapper.v` 里（`pl_video_top.v:343-349`）。它**不代表**现役算法的
  参数默认值（它默认 `IMAGE_W=640, IMAGE_H=360 @:6-7`，现役是 512/300）。
- `src/rtl/video/frame_buffer.v`、`frame_buffer_db.v`、`src/rtl/axi/axi_frame_writer.v`、
  `src/rtl/process/bilin/fb_rd5x.v`、`tap_sched.v` —— 文件头各自写"本树无人例化 / 只剩 sim 在驱动"
  （`frame_buffer.v:2-3`、`frame_buffer_db.v:2-3`、`axi_frame_writer.v:2-3`、`fb_rd5x.v:4-5`、`tap_sched.v:5-6`）。
  ⚠ `fb_rd5x`/`tap_sched` 注释里明说"**别当死代码删**"：它们记录了"为什么 5× 时钟方案被放弃"的实测数
  （见 §11.4）。
- `src/rtl/eth/udp_rx.v` —— 厂商风格三段 FSM，主线已换成 `udp_rx_parser.v`；只有 `sim/tb_eth_video.v`
  还例化它（`udp_rx.v:4-5`）。

**顶层声明了但没有读者的线（引用它们会得到错误结论）**
- `system_top.v:130-133`：`eth_pkts/eth_bytes/eth_bad/eth_frames` 四个统计口**故意不接**（原文：那个同步值
  没有读者；计数的正路是 `link_monitor → snap_cross → lane1/8/9`，ISSUES #64）。端口留着是对的，因为
  一批台架直接读它们。
- `pl_video_top.v:225,229` 的 `frame_done`（timing 模块输出的那一版）、`:613-617` 的 `lat_*` live 口、
  `:147` 的 `p1`、`:591` 的 `ps_src_now`/`ps_no_pub`、`:701` 的 `fill_done`、`:672` 的 `hb_slow()`。
- `eth_udp_video_top.v:21` 的 `copy_hold`（且 `pl_video_top.v:538` `assign copy_hold = 1'b0;` 反向确认 PL
  永不拉住 ETH 搬运）。
- `pl_video_top.v:356-371` 的 `left_d[]` 与 `cx_d[]` 两条链（21×若干 FF 写了没人抽）。
- `system_top.v:45,319` 的 `status[31:0]` —— **只有驱动没有负载**，详见 §13 末。

重取实例清单：
```bash
grep -n "^  [a-z_]\+ \+#\?(\?[^\n]*u_[a-z]" src/rtl/top/pl_video_top.v
grep -rn "rotate_mapper\|frame_buffer_db\|udp_rx " src/rtl/ | grep -v "^src/rtl/process/rotate/rotate_mapper.v:5"
```

---

## 4. 时钟架构（两颗 MMCM、参数、命名、派生）

### 4.1 全部时钟网络

| 时钟 | 频率 / 周期 | 谁产生 | 驱动什么 | 出处 |
|---|---|---|---|---|
| `sys_clk` | 50 MHz / 20.000 ns | 板上晶振，引脚 W17 | ⚠ **不进 BD**（`system_top.v:26,109,122,260` 四处用途，PS 走 `FIXED_IO_ps_clk` `:23,81`）；BD 里 `PCW_CRYSTAL_PERIPHERAL_FREQMHZ=33.333333` ⇒ "PS 参考"这一说作废。**两颗** MMCM 的输入；按键去抖；`angle_ctrl`；心跳 | `rk_zynq7020.xdc:5-6` |
| `clk_fpga_0` = `fclk0` | 100 MHz / 10.000 ns | PS7 的 FCLK_CLK0 | 全部 AXI 事务（顶层名叫 `axi_clk`）、GPIO、lane mux | `build/tcl/build_system_axigpio.tcl:97,162,206-207`；`system_top.v:83,176` |
| `clk_pix` | 50 MHz / 20.000 ns | **MMCM#2** `pl_video_top.u_clk` 的 CLKOUT0（÷20.0） | 显示光栅、效果链、OSD、TMDS 编码器（routed 报告里 `clkout0_1` 有 **30179** 个端点） | `src/rtl/clocks/clk_gen.v:21-23,54`；`pl_video_top.v:128-131` |
| `clk_pix5x` | 250 MHz / 4.000 ns | MMCM#2 CLKOUT1（÷4） | 仅 `OSERDESE2.CLK`（TMDS 串化的快钟） | `clk_gen.v:24-26,55`；`tmds_serializer.v:31,69` |
| `clk_200m` | 200 MHz / 5.000 ns | **MMCM#1** `system_top.u_idelay_clkgen` CLKOUT2（÷5） | 只喂 `IDELAYCTRL.REFCLK` | `clk_gen.v:27-29,56`；`system_top.v:121-125,178`；`rgmii_rx.v:58-63` |
| `eth_rxc` | 125 MHz / 8.000 ns | PHY 恢复，输入 Y19 | RGMII 解串 + 整个收包协议栈 + `frame_reasm` + `link_monitor` | `rk_zynq7020.xdc:20,36` |
| `eth_tx_clk` | 输出给 PHY | `gmii_to_rgmii`（就是 `gmii_rx_clk`） | **无 create_clock**，`:56-58` 三条 false path | `src/rtl/eth/gmii_to_rgmii.v:25`；`rk_zynq7020.xdc:56-58` |

**只有三处真正的时钟源**：晶振、PHY、PS 的 FCLK。其它全是 MMCM 派生。

### 4.2 MMCM 的完整参数（`src/rtl/clocks/clk_gen.v`，57 行）

原语是 **`MMCME2_BASE`**（`:15`）—— BASE 变体**不含内置 BUFG**，所以四路输出每路都要自己挂 BUFG（`:53-56`）。
`.BANDWIDTH("OPTIMIZED")`（`:16`）、`.CLKIN1_PERIOD(20.000)`（`:17`，对应 50 MHz 晶振）、
`.DIVCLK_DIVIDE(1)`（`:18`）、**`.CLKFBOUT_MULT_F(20.000)`**（`:19`）⇒ **VCO = 50/1 × 20 = 1000 MHz**
（算式写在 `:3`）；`.CLKFBOUT_PHASE(0.0)`（`:20`）。

| 输出 | 分频 | 算得 | 相位 / 占空 | 行号 |
|---|---|---|---|---|
| CLKOUT0 → `clk_pix` | `CLKOUT0_DIVIDE_F = 20.000` | 1000/20.0 = **50 MHz** | 0.0 / 0.5 | `:21-23` |
| CLKOUT1 → `clk_pix5x` | `CLKOUT1_DIVIDE = 4` | 1000/4 = **250 MHz** | 0.0 / 0.5 | `:24-26` |
| CLKOUT2 → `clk_200m` | `CLKOUT2_DIVIDE = 5` | 1000/5 = **200 MHz** | 0.0 / 0.5 | `:27-29` |

其余：`.REF_JITTER1(0.010)`（`:30`）、`.STARTUP_WAIT("FALSE")`（`:31`）、外部反馈
`.CLKFBOUT(clkfbout)/.CLKFBIN(clkfbout_buf)`（`:33-35`，反馈必须先过 `BUFG u_bufg_fb`）、
`.PWRDWN(1'b0)`（`:48`）、**`.RST(~rst_n)`（`:49`，MMCM 复位是高有效）**、`.LOCKED(locked)`（`:50`）。
CLKFBOUTB/CLKOUT0B/1B/2B 与 CLKOUT3-6 全部悬空（`:36-47`）。
CLKOUT3/4/5/6 与所有 B 输出悬空 ⇒ **`未找到`** 任何"用第二路相位做时钟域交叠"的设计。

**两颗 MMCM 是同一 module 的两次例化 ⇒ 参数完全相同 ⇒ 两颗 VCO 都是 1000 MHz。**
- MMCM#2（显示）：`pl_video_top.v:128-131`，输出接 `clk_pix`/`clk_pix5x`，`clk_200m` 接 `clk_200m_unused`（`:127`）。
- MMCM#1（IDELAY 参考）：`system_top.v:121-125`，`.rst_n(1'b1)`（不复位），只取 `clk_200m` 与 `mmcm_locked`，
  它的 `clk_pix`/`clk_pix5x` 挂 `clk_pix_unused, clk_pix5x_unused`（`:119,123`）。
  ⚠ **显示通路用的像素钟来自 MMCM#2，不是来自这颗**——这是最常被答错的一条。
- 资源报告印证：`MMCME2_ADV 2 / 4`、`BUFGCTRL 8 / 32`、`BUFIO 0 / 16`
  （`vivado_system/zynq_video_sys.runs/impl_1/system_top_utilization_placed.rpt:161-164`）。

### 4.3 报告里的时钟名与 RTL 名的对应（引用报告字段必查这张表）

routed 时序报告不叫 `clk_pix`，叫 **`clkout0_1`**（50 MHz）、**`clkout1_1`**（250 MHz）、**`clkout2`**
（200 MHz），另有 `clkfbout`/`clkfbout_1`（20 MHz）。这个对应**不是**有人写了 `create_generated_clock`
得到的——全仓 `create_generated_clock` **未找到**（`grep -rn create_generated_clock src/constraints/` 0 命中），
它是**工具自动推导**的派生钟。约束之所以还能把它们并回 `sys_clk` 组，靠的是
`clock_groups_impl.xdc:31` 的 `-include_generated_clocks sys_clk`（`clock_groups_impl.xdc:14-17` 原文点名了
`clkout0_1/clkout1_1/clkout2` 这三个名字）。少了这个后缀，`clk_pix` 会被当作独立钟与 `eth_rxc` 做 setup
分析，历史上是 **WNS ≈ −6.7 的假违例**（issues.md #18）。

### 4.4 光栅相关的一个派生量

像素钟 50 MHz ÷ (1344 × 625) = **59.53 Hz**（场）；行率 = 50e6/1344 = 37205 行/s；有效像素率
1024×600×59.53 = 36.6 Mpix/s（工程文档里常写成"有效 38.4 Mpix/s"，那是按 62.5 Hz 估的，两口径并存，
引用前说明用的是哪个）。TMDS 线速率 = 10 × 50 MHz = **500 Mbps** 每对（机理，算式来自
`tmds_serializer.v:2-3` 的 10:1 DDR 约束）。

---

## 5. 复位链与上电次序

| 复位 | 怎么产生 | 谁吃它 | 出处 |
|---|---|---|---|
| `sys_rst_n` | 板上/PS 给出的系统复位（顶层输入侧由 BD 的 `FCLK_RESET0_N` 与 POR 链决定） | `key_debounce`、`u_clk`(MMCM 的 `RST=~rst_n`)、`pl_video_top` 的 `sys_clk` 域逻辑 | `system_top.v:121-125`、`pl_video_top.v:132` |
| `rst_pix_n` | **`sys_rst_n & locked`**（MMCM#2 锁定后才放） | 全部像素域、`rgb2dvi`（转成 OSERDESE2 的 `RST=~rst_n`） | `pl_video_top.v:132`；`tmds_serializer.v:42,80` |
| `eth_rst_n` | `phy_rst_cnt[23]`——`reg [23:0] phy_rst_cnt` 每 `sys_clk` 加一到全 1 停住 ⇒ 低有效断言 **2^23/50 MHz ≈ 167.8 ms** | 顶层输出脚（PHY 复位）；同时参与 `u_eth` 的复位 | `system_top.v:108-112,34`；引脚 `rk_zynq7020.xdc:34` |
| `u_eth` 内部 `rst_n` | **`eth_rst_n & mmcm_locked`**（MMCM#1 的 locked） | RGMII/协议栈/`frame_reasm`（`gmii_rx_clk` 域） | `system_top.v:175` |
| `axi_rst_n` | BD 的 `FCLK_RESET0_N` | 全部 AXI 域（saver、writer、arb、commit、lat） | `system_top.v:83,177` |

PS 固件侧的初始化次序（`src/ps/main.c:1519` 起）：Exception Table → `DCache_Invalid` → `ICache_Enable`
（`:1523-1526`）→ `GPIO_TRI=0`（`:1529`）→ `ctrl_apply()`（`:1530`）→ 两段 GPIO 自检（`:1536-1550`、
`:1554-1565`）→ `xadc_init()`（`:1569`）→ `sd_mount`/`sd_play`（`:1577-1585`）→ 主循环（`:1587`）。
PS 的时钟、DDR 控制器、网口 MAC 都**不在 C 代码里**初始化——由 `ps7_init` 做，本工程通过 JTAG 跑
`build/tcl/ps_jtag_boot.tcl`（内含 `rst -system`），或 QSPI 自启时由 FSBL 跑。

---

## 6. 跨时钟域（CDC）全表

设计原则（`eth_udp_video_top.v:6` 原文 + `clock_groups_impl.xdc:19-23`）：
**跨域一律靠结构（异步 FIFO / 翻转位同步 / 准静态电平同步），不靠时序约束**——两个 XDC 文件里
现役加载的两份 XDC 里 `set_max_delay`、`set_bus_skew`、`create_generated_clock`、`set_multicycle_path`
均 **0 命令命中**（检索式：`grep -rn "set_max_delay\|set_bus_skew\|create_generated_clock\|set_multicycle_path" src/constraints/rk_zynq7020.xdc src/constraints/clock_groups_impl.xdc`）。
⚠ **口径**：若把检索面扩大到整个 `src/constraints/`，**禁用集会命中四条真 `set_max_delay -datapath_only`**
（`r114_io_async.xdc:57,59,61,63`；`:50-51` 给 UG949 的理由，`:64` 自我交代 `set_bus_skew` 还没写）
⇒ 那是一条**没被采纳的替代路线**，不是遗漏；说"未找到"时永远要带上文件清单。

| # | 源域 → 宿域 | 内容 | 机制 | 级数 / 深度 | 出处 |
|---|---|---|---|---|---|
| C1 | `gmii_rx_clk`(125M) → `axi_clk`(100M) | 视频写令牌（地址+数据+flush） | **格雷码异步 FIFO** | 36 bit × 8192；写两侧各 2FF | `eth_udp_video_top.v:298-305`；`dc_fifo.v:20,22,27,29-32,47,68,82-95` |
| C2 | `gmii_rx_clk` → `axi_clk` | 帧完成事件 | **翻转位 + 3FF + 异拍出沿** | 1+3 | `ddr_bank_commit.v:37-47` |
| C3 | `eth_rxc` → `fclk0`(PS) | 10 个 32bit 健康计数器打包成的 320bit 总线 | **总线快照 + 翻转位**（`snap_cross`） | 3 级捕获 + 异拍 | `system_top.v:214-218`；`snap_cross.v:36-46` |
| C4 | `fclk0`(axi) → `clk_pix` | 片源模式 `mode` 结果 | 3 级 `ASYNC_REG`（`ms0/ms1/ms2`） | 3 | `pl_video_top.v:165-169` |
| C5 | `axi_clk` → `clk_pix` | 仲裁结果 `owner_eth`（ms 级慢变量） | 3 级 `op0/op1/op2` | 3 | `pl_video_top.v:517-522` |
| C6 | `axi_clk` → `clk_pix` | 准静态控制位（`zoom_en`/`bilin_en`/`osd_off`/`src_sel`/`eth_link`/`eth_live`） | 各自独立 3 级电平链（**不做异拍**） | 3 | `pl_video_top.v:212-221,254-261,267-274,471-476,491-496,502-507`；`effect_ctrl.v` 内部 |
| C7 | `axi_clk` → `clk_pix` | 分割几何 19 bit | `snap_cross` W=19，整字抄写 + 翻转 | 3 | `pl_video_top.v:876-880`；`split_ctl` 发射器 `:859-875` |
| C8 | `clk_pix` → `axi_clk` | 缩放状态 20 bit（带"必须原子"契约） | `zoom_snap` 帧首整拍换 + 晚 8 拍发沿 → `snap_cross` W=20 | 3 | `pl_video_top.v:652-658,674-678`；`zoom_snap.v:5-7,27,37-42` |
| C9 | `axi_clk` → `clk_pix` | 延迟测量 18 bit | `snap_cross` W=18，`HB_TO_MS(1000)` | 3 | `pl_video_top.v:980-985` |
| C10 | `clk_pix` → `axi_clk` | 拷贝完成/中止/消隐窗 | `frame_commit_lock` 内 3 像素拍 + 3 axi 拍 | 3+3 | `frame_commit_lock.v:46-53,71-76` |
| C11 | `axi_clk` → `clk_pix` | PS 发布请求（bit18 翻转） | 3 级 + 异拍出沿（`ps_publish`） | 3 | `ps_publish.v:18-25` |
| C12 | `clk_pix` → `axi_clk` | 帧消费事件（`fs_tog`） | 翻转 + 3FF 异拍 | 3 | `pl_video_top.v:568-578` |
| C13 | `gmii_rx_clk` → 同域 | `gapclr_sel`（fclk0 域电平进 125M 域） | **3FF**（准静态，不需握手） | 3 | `eth_udp_video_top.v:275-281` |
| C14 | 显示 BRAM | 写 `axi_clk` / 读 `clk_pix` | **双时钟 BRAM**（推断），读侧另有 `fb_pix_hold` | — | `frame_buffer_w64.v:12,17`；`pl_video_top.v:542-553` |

**三条判据级细节（答错就等于答错）**
1. `dc_fifo` 的 full 判据用的是**当前**写指针而不是下一个：
   `assign wr_full = (wgray == {~rgray_s1[ADDR_W:ADDR_W-1], rgray_s1[ADDR_W-2:0]});`（`dc_fifo.v:47`），
   empty 是 `assign rd_empty = (rgray == wgray_s1);`（`:68`）。`:40-44` 原文记录 r88 那一刀：把
   "14 位加法 + 二进制转格雷 + 比较"整条锥体从 `wr_en → ENARDEN` 上摘下来，代价是可用深度从
   `DEPTH−1` 变成 `DEPTH`，由 `sim/tb_cdc_capacity` 的 C1 钉住（改前 8191、改后 8192）。
2. `dc_fifo` 的存储写块**故意不带复位**（`:59-63` "memory write: no reset → BRAM-friendly"），
   而指针块各带自己域的异步复位（`:50` 用 `wr_rst_n`、`:70` 用 `rd_rst_n`）⇒ **读写两侧各归各的复位**
   （ISSUES #182）。`sync_fifo` 同形（`sync_fifo.v:30-33` vs `:36-49`）。
3. `link_active` 在跨进 axi 域之前多打一拍（`eth_udp_video_top.v:381-386`，`:384`
   `link_active_r <= |s_pkts[15:0]`）。`:373-380` 原文强调"判据是**结构判据**，台架判不了这一条：
   RTL 仿真没有门延迟"（#209 CDC-10）。**这句话在本文里有普适意义**：CDC 的正确性不能靠功能仿真证明。

`ASYNC_REG = "TRUE"` 的属性覆盖由 `dc_fifo.v:23-26` 注释点名的一把专用扫描尺子负责，但那支脚本
在本仓**未找到**（`find . -iname '*scan_async_reg*'` → 0 命中）⇒ **别把它当可执行入口**；能跑的是
门禁第 6 项（§17）。CDC 整体基线在 `build/cdc_baseline.txt`，门禁第 6 项做**配对集合**比对（见 §17）。

重取：
```bash
grep -rn "ASYNC_REG" src/rtl/ | wc -l
grep -rn "ram_style\|(* .*)" src/rtl/eth/dc_fifo.v
```

---

## 7. 网络接收通路：RGMII → DDR，按级讲原理

### 7.0 一条最重要的结构事实：**ETH 逻辑是单时钟域**

`src/rtl/eth/gmii_to_rgmii.v:1-3` 文件头原文：

> "gmii_to_rgmii — 纯连线壳：把厂商的 rgmii_rx / rgmii_tx 拼在一起，并让 `gmii_tx_clk = gmii_rx_clk`
> （RGMII 只有 RXC/TXC 两根时钟，这里 TX 侧沿用的是收侧恢复出来的那一路 125 MHz ⇒ 整个 ETH 逻辑
> 实际是**单时钟域**，各模块里的"tx 域"就是 rx 域）"

实现就是 `gmii_to_rgmii.v:25` 一行 `assign gmii_tx_clk = gmii_rx_clk;`。
**推论（答错就会答错的地方）**：
- 本工程里不存在"发送域 vs 接收域"的 CDC；所有 `*_tx` 逻辑与 `*_rx` 同在 `gmii_rx_clk`。
- `eth_tx_clk` 是**输出给 PHY 的 125 MHz**，来源是 PHY 自己恢复出来的 `eth_rxc`。因此它没有
  `create_clock`，只有 `set_false_path -to`（`rk_zynq7020.xdc:56-58`）。
- 顶层真正跨域的只有两条路：`dc_fifo`（C1）与 `ddr_bank_commit`（C2）；其余一律禁止组合跨域
  （`eth_udp_video_top.v:6`）。

### 7.1 物理层：RGMII ↔ GMII（`src/rtl/eth/rgmii_rx.v` 144 行 / `rgmii_tx.v`）

**收侧器件清单（可数）**：5 个 `IDDR` + 5 个 `IDELAYE2` + 1 个 `IDELAYCTRL` + 1 个 `BUFG`
（1 根 `RX_CTL` + 4 根 `RXD`）。资源报告印证：`IDDR 5`、`IDELAYE2 5`、`IDELAYCTRL 1/4`、`BUFIO 0`
（`system_top_utilization_placed.rpt:141-146,161-162,216-224`）。

**IDDR 的原语形状**（`rgmii_rx.v:87-100` 控制路、`:127-140` 数据路，两者参数同档）：
```verilog
IDDR #(.DDR_CLK_EDGE("SAME_EDGE_PIPELINED"), .INIT_Q1(1'b0), .INIT_Q2(1'b0), .SRTYPE("SYNC"))
     u_iddr_rxd (.Q1(gmii_rxd[i]), .Q2(gmii_rxd[4+i]), .C(rgmii_rxc_bufg), .CE(1'b1),
                 .D(rgmii_rxd_delay[i]), .R(1'b0), .S(1'b0));
```
- `SAME_EDGE_PIPELINED` ⇒ Q1 = **上升沿**采样值、Q2 = **下降沿**采样值，两颗都从同一个时钟沿读出。
- **位段映射**：`Q1 → gmii_rxd[i]`（字节低 4 位）、`Q2 → gmii_rxd[4+i]`（高 4 位）——即
  **RGMII 上升沿传低半字节、下降沿传高半字节**（`rgmii_rx.v:2` 与 `rgmii_tx.v:1-3` 都写了这条）。
- `gmii_rx_dv = gmii_rxdv_t[0] & gmii_rxdv_t[1]`（`:48`）：**两个沿都看到 1 才算有效**，这是抗噪写法。
- `gmii_rx_clk = rgmii_rxc_bufg`（`:47`）—— 直接把打了 BUFG 的 RXC 当 GMII 时钟输出。
- ⚠ `RX_CTL` 在 RGMII 上**只承担 GMII 的 `RX_DV`**，交不出 `RX_ER`。`rgmii_rx.v:6` 原文"RGMII 没有
  GMII 的 RX_ER 通道，本模块交不出错误标志"，同一句在 `eth_udp_video_top.v:156-157`、`udp_rx.v:3-5`、
  `arp_rx.v:4-5`、`icmp_rx.v:5` 各重复一次 ⇒ 顶层因此把 `.gmii_rx_er(1'b0)` 硬接（`eth_udp_video_top.v:189`），
  `gmii_rx_mac` 里的 `er_seen` 恒 0。

**IDELAYE2**（`:67-84` 控制路、`:108-125` 数据路）：`.IDELAY_TYPE("FIXED")`、`.IDELAY_VALUE(IDELAY_VALUE)`，
`C/CE/CINVCTRL/CNTVALUEIN/DATAIN/INC/LD/LDPIPEEN/REGRST` 全部静态 tie ⇒ **板上不可动态调，改 tap
只能重新综合**。`.REFCLK_FREQUENCY(200.0)` 出现在 `:70` 与 `:111`，是硬编码的字面量，与 `clk_gen.v:27`
的 1000/5=200 MHz 是**隐式联动**（没有任何检查保证两者一致）。`IDELAYCTRL` 的 `.RDY()` 悬空、`.RST(1'b0)`
（`:58-63`），并挂 `(* IODELAY_GROUP = "rgmii_rx_delay" *)` 让工具把 5 颗 IDELAYE2 与这顆 CTRL 分到同一
IO 组（否则 DRC 报缺参考）。

**`IDELAY_VALUE` 的四个口径互不相同（引用时必须说清是哪一个）**

| 值 | 在哪 | 说明 |
|---|---|---|
| 0 | `rgmii_rx.v:39`、`gmii_to_rgmii.v:23` | 模块默认 |
| 15 | `eth_udp_video_top.v:14` | 中间层默认（顶层覆盖它） |
| **31** | `system_top.v:172` | **实际生效值**（顶层覆盖） |
| 26 | `rgmii_rx.v:9` 注释、`system_top.v:160` 注释 | 历史值（15 + 11 补 BUFIO→BUFG 之差算出来的） |

**每拍斜率有四个互不一致的数**（这条是文档的诚实性要求，不是缺陷列表）：
- 78 ps/tap —— `gmii_to_rgmii.v:23` 行尾注释"(如果为 n，表示延时 n*78ps)"。
- 156 ps/tap —— `rgmii_rx.v:8` 的算术：`1/(32 × 200 MHz) = 156 ps`（同式在 `system_top.v:161` 复述）。
- ≈ **63 ps/tap** —— `rgmii_rx.v:19-20` 记的实测斜率（tap 26→31 只买到 0.43 ns）。
- ≈ **88 ps/tap** —— 从时序报告里 IDELAYE2 的 `2.292 ns / 26 档` 反推。
`rgmii_rx.v:21-23` 原文把这件事写成"**还有一处对不上、我没有解释、只登记不圆场**……谁要再按
'拍数 = 1.683 ns / 156 ps'推采样点，先把这条量清楚（未定，不当结论用）"。

**发送侧**（`rgmii_tx.v`）：5 个 `ODDR`，`.DDR_CLK_EDGE("SAME_EDGE")`；TX_CTL 的 `D1=D2=gmii_tx_en`
（两沿同送，`:19-31`），数据 `D1=gmii_txd[i]`/`D2=gmii_txd[4+i]`（`:37-49`）；
`rgmii_txc = gmii_tx_clk`（`:16`）。**没有 ODELAY**（全文件 0 命中）。⇒ 输出侧的建立/保持余量完全靠
ODDR 的对齐与 PHY 那边的窗，本工程故意不写 `set_output_delay`（§10.4）。

**为什么 5 个 IDDR 与下游 fabric 吃同一只 BUFG**（`rgmii_rx.v:3-5` 原文，这是本工程最贵的一课之一）：
原来 IDDR 吃 **BUFIO**（SCD = 3.171 ns）、fabric 吃 **BUFG**（DCD = 4.854 ns），两棵钟树差 **1.616 ns**
而那条数据路径只有 1.855 ns ⇒ 综合器插 hold buffer 硬补，"每次重建在 ±1 ps 上掷硬币"（r62 量到
+0.001、r63b 量到 +0.052）。改成同吃 BUFG 后偏差变成设计值，但**采样沿被往后推了 1.683 ns**，
于是数据侧必须补同样的量（这就是 `IDELAY_VALUE` 从 15 变 26 的由来，后来 r116 又按实测曲线推到 31，
见 §11.5）。资源报告里 `BUFIO = 0` 是这条改动的直接证据。

### 7.2 GMII MAC 层（`src/rtl/eth/gmii_rx_mac.v`，118 行）

- 3 态 FSM：`S_WAIT=2'd0 / S_PRE=2'd1 / S_DATA=2'd2`（`:25-27`），配 `cnt[15:0]`、`saw_sfd`、`er_seen`
  （`:29-32`）。
- 前导码：`S_WAIT` 只等**一个** `8'h55`（`:89-92`）就进 `S_PRE`，`S_PRE` 数连续 `0x55`（`:99-100`），遇
  `8'hD5`（SFD）进 `S_DATA` 并清 `cnt`（`:95-98`），遇其它字节退回 `S_WAIT`（`:101-104`）。
  ⚠ **不校验 7×0x55 的个数**——这与厂商版 `udp_rx.v:126-133` 的硬校验形成对比。答"前导码检查了几个字节"
  时必须先说是哪一版。
- 帧长：**只在帧尾比 `cnt >= 16'd64`**（`:76`）。**没有最大帧长校验**（`cnt` 是 16 位；`saw_sfd` 只置不用，
  全文件仅 `:31/:84/:98` 三处）。
- CRC32：内建一份 `crc32_d8`（`:37-47`），`crc_en = (state==S_DATA) && gmii_rx_dv`（`:35`）⇒ 覆盖
  **整帧含 4 字节 FCS**；`crc_clr` 打在 `S_PRE` 且字节==`8'hD5` 那一拍（`:42`），`:43-44` 原文解释为什么
  不能打在第一个数据字节当拍（"`crc_clr` 优先级会吞掉第 0 字节"）。
  判据是**残值比较**：`wire fcs_ok = (crc_q == FCS_RESIDUE);`（`:48`），
  `localparam [31:0] FCS_RESIDUE = 32'hC7_04_DD_7B;`（`:23`）。`:21-22` 原文：**"实测值、不是推算值……
  不要凭记忆改"**。（这一条是专门核对过的：常数逐字取自 `gmii_rx_mac.v:23`。）
- **地址过滤在这个模块里完全没有**（`grep -n "BOARD_MAC\|ff_ff_ff\|des_mac" gmii_rx_mac.v` → 0 命中）。
  DA 过滤只存在于厂商路径（`udp_rx.v:145-146`、`arp_rx.v:126-127`、`icmp_rx.v:182-183`，判据都是
  "本机 MAC 或 `48'hff_ff_ff_ff_ff_ff`"两选一，**不认多播位**）。而主线用的 `udp_rx_parser.v`
  **一行 DA 都不看** ⇒ **任何目的 MAC 的 UDP 包，只要 IPv4 + UDP + 端口 5001 对得上就会被接受**。
- 输出契约：`m_valid / m_sof / m_eof / m_good / m_bad`，**每拍先清 0 的单拍脉冲**（`:63-67`），数据
  `m_data` 与 valid 一起寄存输出（`:107-109`）⇒ 相对输入晚 1 拍。`m_sof` 在 `cnt==0` 那拍 = DA[0]
  （`:109`）；`m_eof` 在 `gmii_rx_dv` 掉下来那拍且 `state==S_DATA`（`:69-75`）。
  `:71-74` 原文（时序契约的凭据）："**m_eof 与 m_good/m_bad 同拍**，表示'上一个 m_valid 的字节就是帧的
  最后一个字节'……V7.9.5 之前 `m_eof` 声明了、复位清了、却没有任何一处写 1"。
  ⚠ 下游必须接受"eof 比最后一个字节晚一拍"这一族，`udp_rx_parser.v:191-195` 明确写了两种时序都认。

### 7.3 UDP / ARP / ICMP 解析

**主线解析器是 `udp_rx_parser.v`（217 行），不是厂商风格的 `udp_rx.v`。**
`udp_rx_parser.v:1-3` 自述结构："**Byte-index state machine** (easier to verify)"——它没有
`cur_state/next_state`，全部判定是 `bcnt == 常数` 的比较式：

| 字段 | 采样时刻（`bcnt`） | 行号 |
|---|---|---|
| `proto_chk[15:8]`（EtherType 高） | 12 | `:117` |
| `proto_chk[7:0]` | 13 | `:118` |
| `b14` + `ihl <= s_data[3:0]` | 14 | `:119-122` |
| `b20/b21`（分片偏移两字节） | 20 / 21 | `:123-124` |
| `b23`（protocol） | 23 | `:125` |
| UDP 目的端口高/低 | `udp_off+2` / `+3` | `:158` / `:151-157` |
| UDP length 高/低 | `+4` / `+5` | `:159-160` |
| 载荷尾界 `pay_end` | 提前一拍算出 | `:161-162` |

接受条件（`:137-143`，在 `ihl != 0 && bcnt == 14 + {10'd0, ihl, 2'b00}` 那一拍决策）：
`proto_chk == 16'h0800`（IPv4）`&& b14[7:4] == 4'h4`（版本 4）`&& b23 == 8'd17`（UDP）
`&& {b20,b21} == 16'h0000`（**无分片偏移**）；端口不符就丢（`:153`）。
`:133-136` 记录 V7.9.6 修掉的一个统计假阳性：`ihl` 同拍还是旧值 0 ⇒ `bcnt==14` 也成立 ⇒ 每帧误发一次
`stat_drop_filt`。

**两个必须知道的"没做"**：
- **UDP 校验和完全不校验**（`grep -n "checksum\|csum" udp_rx_parser.v udp_rx.v` → 0 命中）。
  只有 **IPv4 首部**校验和是错的才会被 `b20/b21` 之外…（注意：`udp_rx_parser` 连 IP header checksum
  也不验）。数据完整性只靠 §7.2 的 CRC32 残值。
- 坏帧的丢弃路径**不产生下游错误口**：`:92-106` 直接把帧闭合，`:144-147`/`:153-156` 过滤后静默丢弃；
  顶层的 `st_drop_bad/st_drop_filt/st_udp_ok`（`eth_udp_video_top.v:196,203`）**接出来但没有读者**。

**尾字节为什么要"记账"而不是当场发 `p_eof`**：`:179-181` 原文——"因为 FCS 的判定要等帧结束那一拍
（`m_good/m_bad` 与 `m_eof` 同拍）才知道。早发就得猜，**猜错就是'把坏包当好包提交'**"。实现是
`eof_pend`/`pay_len_q`（`:179-185`），收尾分支在 `:196-213`；若声明长度与实际不符，判畸形包
`p_good <= 0`（`:202-207`）。

**ARP 不是表**：`arp_rx.v` 里**没有缓存数组、没有老化定时器**（`grep -n "aging\|timeout\|cache\|mem\["
arp_rx.v` → 0 命中）。它只有两个寄存器 `src_mac[47:0]`/`src_ip[31:0]`（`:19-20`），在 `cnt==28` 且
目的 IP == BOARD_IP 且 op ∈ {1,2} 那一拍整拍写入并同拍发 `arp_rx_done`（`:151-160`，写入时把影子
寄存器清 0）。取的是**发送方** SHA/SPA（`:145-148`）。顶层把这对寄存器直接当"唯一邻居"回给
`arp_tx`/`icmp_tx`/`udp_tx` 的 `des_mac/des_ip`（`eth_udp_video_top.v:136-137,150,169-170`）
⇒ **谁最后发过 ARP，回包就给谁**；没有并发邻居的概念。

**ICMP 回显的缓冲 = 一根 8bit×2048 同步 FIFO**（`sync_fifo #(.DATA_W(8), .ADDR_W(11)) u_icmp_fifo`，
`eth_udp_video_top.v:119-124`），且 `full/empty/level` 三口**全部空接** ⇒ 满了静默丢、无告警。
回显节流：`icmp_dly[5:0]` 在收完包时装 `6'd20`、倒数到 1 时发 `icmp_tx_start_en`
（`:94-109`，`:102` 装 20、`:106` 发使能）⇒ 等 **20 个 `gmii_rx_clk` 周期（160 ns）** 再启动应答。
`icmp_rx.v:196-203` 有 `total_length < 28` 的长度守卫，防 16 位减法回绕（凭据 `tb_icmp_len_wrap.v`
R1/R1b/R2）；`:104-110` 是"一条 0 字节请求让应答器永久变哑"的逃生口（凭据
`build/r101_216_deathpoint.txt`）。ICMP 的 reply checksum 是**增量**算的（奇偶配对
`reply_checksum_add <= {icmp_rx_data_d0, gmii_rxd} + reply_checksum_add`，`:292-294`）。

**发送侧当前是关着的**：`eth_udp_video_top.v:166-168` 把 `tx_start_en(1'b0)`、`tx_data(8'd0)`、
`tx_byte_num(16'd0)` 钉死，注释原文"与今天一致：Z7 不发 UDP"。所以 `udp_tx.v`(378 行)/`arp_tx.v`(308 行)
/`icmp_tx.v`(455 行) 是**在位流里但不被激励**的逻辑。它们内部的实现事实（回答"这套代码怎么发 ARP"时
才需要）：帧布局存在三个数组 `preamble[7:0]`/`eth_head[13:0]`/`ip_head[6:0]`
（`udp_tx.v:52-54`，32bit 一项）；IP 首部校验和**非增量、4 拍**（`:234-249`：一次加 10 个 16 位项 →
折叠 → 再折叠 → 取反写进 `ip_head[2][15:0]`）；`icmp_tx.v:272-292` 把它拆成 5 拍，`:274-276` 原文记录
原因："原来 10 项一拍 ⇒ 5 级 CARRY4、0.741 ns 最差路径"；`check_buffer` 位宽砍到 20 bit
（`:75-80`，上界 `10×65535 = 655350 < 2^20`）。`udp_tx.v` 里源/目的端口硬编码 1234、UDP 校验和恒 0
（`:220`），**与收侧过滤的 5001 无关**。
发送仲裁在 `eth_ctrl.v`：`protocol_sw[1:0]`，`2'b00=ARP / 2'b01=UDP / 2'b10=ICMP`（`:94-108`），优先级
`udp > icmp > arp_pend`（`:151-160`）。`:137-141` 原文记了两件事：把 `arp_rx_flag` 的单拍脉冲改成记账位
`arp_pend`（否则"另一路正在发"那一拍请求就丢了，PC 要等 ARP 超时），以及**记账与兑现必须在同一个
always 块里**（否则 `arp_tx_en` 连高两拍、ARP 帧第 0 字节被重发一次）。

### 7.4 帧重组：UDP 载荷的自定义头（`src/rtl/eth/frame_reasm.v`，222 行）

**协议头（本设计的私有约定，唯一硬件权威就是这个文件）**：UDP 载荷 =
`[u32 小端 帧内字节偏移][RGB565 字节流 …]`。

- 4 字节偏移的收集式在 `:126-130`，逐拍移位：`S_OFF0: off<={24'd0,p_data}`、`S_OFF1: off[15:8]<=p_data`、
  `S_OFF2: off[23:16]<=p_data`、`S_OFF3: off[31:24]<=p_data`（状态定义 `:37`）。
- 完整头的拼接表达式 `:105`：`wire [31:0] hdr = {p_data, off[23:0]};`，`:104` 原文
  "4-byte **little-endian** offset, complete in the S_OFF3 cycle"。⇒ **低地址=低字节**，与小端主机一致。
- 几何参数：`parameter IMG_W=512 :9`、`IMG_H=300 :10`、`FRAME_BYTES=307200 :11`、
  `localparam integer ROW_STRIDE = IMG_W * 2 = 1024 :86`。
- **行号用除法不用移位**（`:84-85` 原文）：
  ```
  // byte_off → row: row = byte_off / (IMG_W*2). Must NOT use off[16:1] (a 16-bit pixel index
  // truncates ~172/300 rows → frame_done never → SRC1 black).
  ```
  实现 `:87-90`：`row_idx = off / ROW_STRIDE`、`ridx = row_idx[8:0]`、`rbank = ridx[8:6]`、`roff = ridx[5:0]`。
  行覆盖位图是 **5 个 64bit 寄存器**（`rok0..rok4`），`:91-96` 用 5 选 1 mux 查。
  为什么分 5 bank：`:76-80` 原文——一条大比较器的扇入会把本 125 MHz 组的最差路径拖住（`fo=316`、
  最后一级跳吃掉 1.980/6.879 ns、route 81.2%）。编译期守卫 `:217-220`：
  `if (IMG_H > 5*64) $error(...)`，`:215-216` 原文"IMG_H 一旦超过 5*64，行覆盖就记丢、`frame_done`
  永不成立（**画面是黑纹而不是报错**）。台架里当场喊；综合忽略 initial"。
- **写地址** `:151`：`wr_addr <= off[18:1]`（19 位字下标，单位 = 16bit 像素），
  `wr_en <= (off < FRAME_BYTES)`（`:152`）。数据由相邻两个载荷字节拼成：`:141-142` 存低字节
  `pix_lo` + `have_lo<=1`，`:150` `wr_data <= {p_data, pix_lo}` ⇒ **线上是低字节在前**（LE 像素）。
- **越界** 走 `:152-161`：`wr_en` 拉 0，并把 `stat_oob_off` +1（`:161`）。`:144-149`（ISSUES #201）原文记录
  改前症状："发包方选的偏移能把字写到帧缓存之外（`off[18:1]` 最大 131071，帧只有 153600 字节 = 76800 个
  字，越界后落在谁身上由下游 `axi_frame_saver64` 的乘法决定，而**它自己没有上界检查**）"，凭据
  `build/r98_201_before.txt`，尺子 `sim/tb_reasm_bounds.v` 的 R1。
- **重叠没有任何保护**：`:154-158` 的位图写是幂等的（写 1），`rows_hit` 只在**该行首次被写**时 +1
  （`:100` `new_row_w = (row_idx < IMG_H) && !row_covered`）。同一行被两个包各写一次只会覆盖数据，
  **不产生任何计数**。⇒ "重传安全"只是"数据被重写一遍"，不是被检测出来的特性。
- **包序倒退没有专门分支**（这是已知缺陷，见 §18：偏移倒退时不清零 ⇒ 上一帧残字写进刚清零的 bank）。
  唯一的清零条件是 `:133-138` 的 `if (hdr < 32'd4)`（即偏移回到帧开头附近）。
- **非对齐尾字节**：`have_lo` 是"攒了一半"的旗（`:41`），载荷奇数字节时最后那个高字节永远凑不成第二个字，
  帧尾 `p_eof` 分支 `:211` 直接 `have_lo<=0` 丢掉，**既不报错也不计数**。偏移头本身 4 字节，但若发送方给的
  `off` 是奇数，`off[0]` 会一直保留（`:163` `off<=off+2`），导致 `off[18:1]` 与真实字节位置差半个字 ⇒
  **RTL 里对 `off[0]` 没有任何检查**（检索式 `off\[0\]`、`odd`，0 命中）。这就是上位机文档要求
  "载荷长度必须是 8 的倍数"的根因之一（另一半见 §7.6）。
- **帧完成三门**（`:182`，逐字）：
  `if (rows_hit >= IMG_H[15:0] && bytes_ok && !bad_frame)` ⇒ `frame_done<=1`（`:183`），同拍清
  `cov`/`rok0..4`/`rows_hit`/`bad_frame` 并 `stat_frames+1`（`:184-188`）。
  `bytes_ok = cov_sat | (cov_end & p_valid)`（`:70`）。`cov`/`pend` 是**饱和累加器**（`:56-66`：
  `CW=$clog2(FRAME_BYTES+1)`、`SAT=FRAME_BYTES`、`SAT1=FRAME_BYTES-1`），`:5-7` 原文记录为什么：v5.1 之前
  是一条三操作数 32 位加法，**它占了本 125 MHz 组十条最差路径的全部**（WNS +0.499）；改成两个饱和累加器 +
  在 EOF 拍补最后一字节（`:68-69`、`:192-195`）。
- **帧作废**：走 else 支时，只有 `last_pkt = pend_sat | (pend_end & p_valid)`（`:72`）为真才
  `stat_bad+1` + `frame_abort<=1`（`:196-199`）并算 `rows_missed`（`:201-202`）。`:26-28` 原文：
  "`frame_abort` 只在'本帧字节预算已用完但验收门没过'的那一拍脉冲一次；**连 `FRAME_BYTES` 都没凑够的
  短帧不脉冲 `frame_abort`，由 `stall_ms` 抓到**"。坏包支 `:206-210`：`stat_bad+1; frame_err<=1;
  bad_frame<=1`。
- 输出全部寄存、每拍默认清 0（`:118`）；`flush` 在**每个结束包**（不论好坏）都拉一拍（`:175`），
  顶层用它推打包器里半截的字。

### 7.5 CDC 缓冲：为什么是 36 bit × 8192（`dc_fifo`）

写令牌打包式（`eth_udp_video_top.v:263-265`）：
```verilog
cdc_data = {1'b0, fb_wr_addr, fb_wr_data};   // 正常写：1 个 flush 位 + 19 位地址 + 16 位数据 = 36
cdc_wr   = (fb_wr_en || reasm_flush || flush_pend) && !fifo_full;
```
- **为什么 36 位**：把"一个写令牌"的**地址、数据、flush 位装在同一个条目里原子过跨域**，读侧再拆
  （`:315-320`）⇒ **不存在地址与数据被撕开的窗口**。若拆成两条 18/19 位通道，就得自己造握手。
  第 36 位是 flush 标记，读侧解码：`sav_en <= cdc_d1_v && !cdc_d1[35]`（`:315`）、
  `sav_flush <= cdc_d1_v && cdc_d1[35]`（`:316`）。
- **为什么 8192 深**：`:296-297` 原文"8192 条 = 4096 个 64bit 字 = 16 KB，足以吸收'显示拷贝独占 HP0
  一整个 V-blank'期间到达的入包数据（15 MBps × 672 µs ≈ 1260 字）"。
- **为什么读侧是 1 条/axi 拍**：`:258-262` 原文记 v6.1 的丢包算术——"一个 1392 B 的包在 125 MHz 下是连续
  线速进来的……每包 698 个 16bit 写。原来读侧限成'每 3 个 axi 周期取 1 条' = 66 MB/s < 125 MB/s，
  **单包就能把 512 深的 CDC 灌满 → 稳定丢 ~46% 的字**，表现为板上'每隔一个 16bit 空洞'的黑纹……
  现在 1 条/周期（200 MB/s）"。实现是 `:312` `fifo_rd <= !fifo_empty && !sv_full;`。
- **溢出丢弃的唯一路径**：`:263-265` 里的 `&& !fifo_full` ⇒ 满时那一拍的写**凭空消失，FIFO 自己不发
  溢出标志**（`dc_fifo.v:53,61` 两处都是 `if (wr_en && !wr_full)`）。被丢的字由 `link_monitor` 的
  `drop_words` 计数（见 §7.8），那是"**板上唯一真实的丢数据通道**"（`link_monitor.v:69` 原文）。
- `flush_pend` 一位缓冲（`:267-271`）：同拍既来 flush 又来数据时把 flush 押后一拍，只在
  `!fb_wr_en && !fifo_full` 时释放。
- 反压：`sv_full`（打包器内部 FIFO 满，`:256`）让 `:312` **停止取数**而不是取出来丢掉；`:353` 原文
  "v6.2: 打包器满时停止从 CDC 取数（反压），否则取出来就丢，等于白读"。

### 7.6 AXI 写侧：三代打包器与为什么用 64 位那版

`src/rtl/eth/` 里有三个"16bit 写 → AXI 写 DDR"的实现，**上板的是 `axi_frame_saver64.v`**
（`eth_udp_video_top.v:352` 注释原文 "v5.0: use saver64 so idle/commit/frame_ready can complete
(**burst hung → red**)"）。

| 项 | `axi_frame_saver.v`（98 行） | `axi_frame_saver_burst.v`（205 行） | **`axi_frame_saver64.v`（176 行，现役）** |
|---|---|---|---|
| `AWLEN` / `AWSIZE` | 0 / `3'b001`(2 B) `:29-30` | `b_cnt-1`（≤16）/ `3'b011` `:32,168` | **`8'd0` / `3'b011`(8 B)** `:40-41` |
| `AWBURST` | `2'b01` INCR `:31` | `2'b01` `:33` | `2'b01` `:42` |
| `WLAST` | 恒 1 `:33` | 逐 beat 算 `:183,192,196` | **恒 1** `:44` |
| `WSTRB` | 恒 `8'h03` `:32` | 恒 `8'hFF` `:34` | **按 16bit lane 动态生成** `:83-84` |
| 前端缓冲 | 128 项寄存器数组 `:35-38` | 512 项（未标 ram_style）`:36-38` | 512 项**显式 `ram_style="distributed"`** `:48-50` |
| outstanding | 恒 1（`S_AW→S_W→S_B` 串行 `:51,67-93`） | `b_outstanding[3:0]` `:58,145-148` | `outst[3:0]`，`localparam OST = 4'd8` `:66` |
| `BREADY` | 只在 S_W 后拉高 `:84,90` | `(b_outstanding > 1)` `:147` | **恒 1，永不反压** `:156` |
| 地址生成 | `BASE_ADDR + {12'd0, amem, 1'b0}` `:71`（**固定基址、无 bank 概念**） | `base + {10'd0,widx,3'b000}`（经 `task push_word`）`:78` | `pack_base + {10'd0, cur_widx, 3'b000}` `:110` |
| `idle` 口 | 无（只有 `busy`） | 6 个条件 `:60-62` | `enable && !cur_dirty && fifo_empty && !beat && outst==0` `:86` |

**为什么 `WSTRB` 必须动态**（`:80-82` 原文，逐字值得抄）："旧实现恒为 `8'hFF`，'同一个 64bit 字被相邻两包
分两次写'时后一次会把前一次的半字覆盖成 0：分包长度不是 8 的倍数（如 1396）时**每帧 111 处 = 222 个
16bit 黑洞**，屏上均匀散布的黑点"。表达式 `:83-84`：
`m_axi_wstrb = {{{2{keep_r[3]}},{2{keep_r[2]}},{2{keep_r[1]}},{2{keep_r[0]}}}`。
⇒ **上位机侧"载荷长度必须是 8 的倍数"这条规矩，根因就在这三行。**

**为什么要流水化**（`:2-3` + `:5-7`，ISSUES #31）："v6.2 之前每字走完 `S_AW→S_W→S_B`，在途深度恒 1
⇒ HP0 写延迟（~40 拍，被显示拷贝抢端口时上百拍）直接成为吞吐上限 ≈ **20 MB/s** ⇒ 板上'每包固定从第
48 字节起丢字'"。`:7-8`（ISSUES #32）紧接着警告："**加深缓冲治不了它：瓶颈是平均排空速率不是深度**，
v6.2 把 CDC 做到 8192 时上板毫无改善。"——这是"用缓冲区掩盖带宽不足"这个常见错误答案的直接否定。

**为什么缓冲只有 512 项**（`:10-13` 原文）："早先版本让它被综合成触发器（512×100 bit ≈ 5.1 万 FDRE），
占整机 Slice Register 的 94%，FW=11 直接 DRC `UTLZ-1`。深缓冲在 `eth_udp_video_top` 里 BRAM 实现的 CDC
（8192 条）。"

⚠ **这段原文里的 94 % 今天复算不出来**：按 `build/utilization.rpt:41`，可用 FF = 106400，
`51200 / 106400 = 48 %`。⇒ 本文对外只 publish 能复算的 **48 %**；94 % 只能作为"源码注释当时的声称"引用，
不能当读数搬运（学习文档 §3.5 与 v25 修订记录第 ⑤ 条记着同一件事与同一处理口径）。

**一条被实测钉死的 Verilog 写法**（`:104-107`，原文值得整段搬）："存储写必须**独占一个不带异步复位的
always 块**……写成 task + 和指针同在异步复位块里时，Vivado 报 `Synth 8-7186` 拒绝把数组推断成 RAM，
512×64bit 直接退化成 3.29 万个 FDRE（**实测：task 写法 FF=32904/LUTRAM=0，本写法 FF=85/LUTRAM=864**）。"
——这正是 `axi_frame_saver_burst.v:72-83` 那个 `task automatic push_word` 的死因。

**outstanding 只减不回绕**：`:158-160` 原文"只减不回绕：万一上游偶尔多回一个 B，回绕成 15 会让 `have`
永远不成立（整条入包链就此卡死 = 板上'冻结'类症状），**宁可少计也不要锁死**"。

`axi_frame_saver_burst.v:3` 文件头自陈问题清单："Issues on: flush, address gap, burst full, or quiet-idle
drain."（所以它没上板）。

### 7.7 乒乓 bank 提交（`src/rtl/eth/ddr_bank_commit.v`）

**乒乓在 DDR，不在 BRAM。** 这是本工程最常见的误答。基址与间隔：

| 常量 | 值 | 行号 |
|---|---|---|
| `BASE_ADDR`（默认） | `32'h1000_0000` | `eth_udp_video_top.v:10`（顶层传 `system_top.v:139` `DDR_BASE=32'h1000_0000`） |
| `BANK0` | `BASE_ADDR` = `0x1000_0000` | `eth_udp_video_top.v:67`；`ddr_bank_commit.v:9`（模块默认同值） |
| `BANK1` | `BASE_ADDR + 32'h0008_0000` = `0x1008_0000` | `:68`；`ddr_bank_commit.v:10` |
| 间隔 | 0x80000 = **512 KB** ≥ 一帧 307200 B | `system_top.v:140-141` 注释 |
| PS 第三 bank | `0x1010_0000`（= +1 MB） | `system_top.v:144`；固件侧 `src/ps/sd_play.c:35` |

**提交协议（两级，逐行）**
1. `gmii_rx_clk` 域把单拍脉冲 `frame_done` 转成**电平翻转位**：`reg frame_done_tog = 1'b0;`（`:37`，
   **带声明初值**），`:38-41` `always @(posedge gmii_clk or negedge rst_n) … else if (frame_done)
   frame_done_tog <= ~frame_done_tog;`。
2. `axi_clk` 域 3 级同步 + 异拍出沿：`(* ASYNC_REG = "TRUE" *) reg fd0, fd1, fd2;`（`:42`）、
   `{fd2,fd1,fd0} <= {fd1,fd0,frame_done_tog}`（`:44-45`）、`wire fd_axi = fd1 ^ fd2;`（`:47`）。
3. `fd_axi` 那一拍只置**请求**：`switch_req<=1; force_flush<=1;`（`:63-66`）。
4. 真正换页要过提交门：`commit_ok = TAIL_GUARD ? (saver_idle && tail_drained) : saver_idle`（`:51`），其中
   `tail_drained = cdc_empty && !cdc_rd && !cdc_d1_v && !sav_en && !sav_flush`（`:50`，`:49` 原文
   "队空 + 读地址已发 + 两级读流水都空"）。满足时 `:67-73`：
   `completed_base <= sav_base; bank <= ~bank; commit_pulse <= 1'b1;`。
5. 输出：`assign sav_base = bank ? BANK1 : BANK0;`（`:79`）给写侧；`assign pack_flush = sav_flush |
   (force_flush && (TAIL_GUARD ? tail_drained : 1'b1));`（`:80`）；兜底 `:74-75` 在
   `saver_idle && !switch_req` 时清 `force_flush`。
6. 复位初值：`:55-60` ⇒ `bank<=1'b0; completed_base<=BANK0; commit_pulse<=0;` ⇒
   **上电第一个可显示的 bank 是 BANK0**。

**`TAIL_GUARD` 为什么存在**（`:6-7` 原文）：`=1` 修 v6.4 的"帧尾 4 字节偶发丢失"——"旧判据只看
`saver_idle`，它对 8192 深的 CDC 和后面的读流水**完全不可见** ⇒ 帧尾几个 16bit 被写进**下一帧**的 bank
（板上 HDMI 右下角少 2 像素）"。参数默认 `1'b0`（`:11`），顶层传 **`1'b1`**（`eth_udp_video_top.v:331`）。

**为什么它要单独成模块**（`:4-5` 原文）："抄的那份永远不会因真代码改错而变红"——这是本项目对
"判据必须能红"这条纪律在 RTL 层的落地方式之一。

提交之后谁消费：`ddr_commit_base`/`ddr_commit_pulse` 出顶层（`eth_udp_video_top.v:330-350`），
`system_top.v:191-192` 接出去，进 `pl_video_top` 的 `eth_commit` → `frame_commit_lock`（§8.4）与
`frame_latency`（§8.12）。

### 7.8 健康与观测（`src/rtl/eth/link_monitor.v`，207 行）

全部在 `gmii_rx_clk`/`eth_rxc` 125 MHz 域。时基：`localparam integer TC = CLK_HZ/1000 = 125000`（`:36`）、
`DW = $clog2(TC+1)`（`:41`）。`:38-40` 原文记录一条**类型宽度事故**：原来把分频寄存器写成 `[15:0]`，
装不下 125000 ⇒ `ms_div == TC-1` 恒假 ⇒ **ms_tick / stall / gap / 心跳在板上全死**，取证是
`WARNING [Synth 8-6014] Unused sequential element ms_div_reg was removed`。每 1 ms：`ms_tick<=1`（`:60`）
并 `lm_hb <= ~lm_hb`（`:61`）⇒ **心跳位每 1 ms 翻转一次**。

| 计数器 | 语义 | 位宽 | 清零 | 赋值行 |
|---|---|---|---|---|
| `drop_words` | **被 `fifo_full` 吃掉的字**（`:69` 原文"板上唯一真实的丢数据通道"） | 32 | **永不清零** | `:105` 打拍、`:122` 入账 |
| `frames_bad` | 作废帧数（`frame_abort` 触发） | 32 | 不清零 | `:127` |
| `pkt_err` | 坏包数（`frame_err` 触发） | 32 | 不清零 | `:130` |
| `cdc_ep` | CDC **进入"满"状态的次数**（不是拍数） | 32 | 不清零 | `:81` 上升沿、`:106` 打拍、`:123` 入账 |
| `rows_miss_max` | 历次作废帧里缺行最多的一次 | 16 | 复位 0，只增不减、**不受 gapclr 影响** | `:128` |
| `stall_ms` | "距上一个 `frame_done` 过了多少 ms"（活看门狗） | 16 | `frame_done` 清 `:136` | `:151-153`，**饱和在 `0xFFFF` 不回卷** |
| `gap_cnt` | 帧间隔的直接计数 | 17 | 见下 | `:110-112`，优先序 `gapclr > frame_done > ms_tick && !gap_cnt[16]` |
| `gap_last/min/max`、`gap_sum` | 上一次 / 最小 / 最大 / 累计间隔 | 16/16/16/32 | `gapclr` 清 `:116-119` | 在 `frame_done` 那拍一次性记账 `:135-150` |

- **gap 量的到底是什么**：`frame_done → frame_done`，即**两次完整帧提交之间过了多少个 ms tick**。
  不是包间隔，也不是帧起始间隔。第一个 `frame_done` 只建立 `have_base`（`:137`、`:150`），从第二个起才
  产 min/max ⇒ `gap_valid` 需要 ≥2 帧（`:78`）。`:133-134` 原文记了一个**已知偏差不修**："ms tick 与
  `frame_done` 同拍时这一条间隔少计 1 ms……记下，不修"。
- **为什么改成"直接数"**：`:46-51` 原文——原来是"两个 32 位毫秒计相减"，那是**全设计最差 setup 路径**
  （ISSUES #95）。位宽不换的理由同段："宁可饱和也不许绕回（16 位回卷曾把 `gap_max` 永久污染，且之后更大
  的间隔读起来反而更小 ⇒ **两个方向都说谎**），但不需要 32 位：数到 `0x1FFFF` 钉住，`gap_new` 见 `bit[16]`
  报 `0xFFFF`"。读数式 `:87`：`wire [15:0] gap_new = gap_cnt[16] ? 16'hFFFF : gap_cnt[15:0];`
- **为什么 `drop_words` 必须延迟"事件谓词本身"**：`:82-85` 原文——"`(req_d && full_d)` 与
  `(req && full)` 延一拍**不等价**……台架 E1 实测 DUT 31 / 参考 32"。⇒ 正确写法是把
  `drop_ev_d <= cdc_wr_req && cdc_full`（`:105`）整体打一拍。
- **16 位字段一律饱和不回卷**：`:88-92`（`bad16/err16/ep16`），原文"健康数字回卷到 0 会被读成'没问题'，
  **这是比少报更坏的错**"。
- 快照总线 `lm_bus[319:0]`：`:187-196` 十个 lane 显式 `[31:0]`，`:202-203` 拼接顺序
  `{lane9,…,lane0}`（**lane0 在最低 32 位**）。lane0=`drop_words`；**lane1=`{err16, bad16}`**（`:188`，
  高 16 位坏包 / 低 16 位作废帧）；lane2=`{rows_miss_max, stall_ms}`；lane3=`gap_last`；lane4=`{max,min}`；
  lane5=`gap_sum`；lane6=`cdc_ep`；lane7=标志位组（bit3 = `stall_ms < 200` = "流活着"）；lane8/9=in_pkts/in_bytes。
  完整 lane 表（含 10-31）在 §13。

`eth_ctrl.v`(167 行) 的职责是**发送侧协议仲裁**（见 §7.3 末），与观测面无关。
`snap_cross.v` 的字段布局与 3 级同步链见 §6 C3；它的 `hb_gone`/`hb_slow` 是"**源时钟没了 / 源时钟被拉慢**"
两个独立旗标（`system_top.v:238` 把它们编进 lane31，注释原文："板级实测拔线时 RXC≈2.5 MHz ⇒ 只有 bit1
会亮"）——这正是 `src_arb` 的 `eth_tb_ok` 判据来源（§8.2）。

重取：
```bash
grep -n "drop_words\|stall_ms\|gap_new\|lm_bus\[" src/rtl/eth/link_monitor.v
grep -n "IDDR\|IDELAYE2\|ODDR\|REFCLK_FREQUENCY\|IDELAY_VALUE" src/rtl/eth/rgmii_rx.v src/rtl/eth/rgmii_tx.v
```

---

## 8. 显示与处理通路：DDR → HDMI，按级讲原理

顶层文件 `src/rtl/top/pl_video_top.v`（1050 行）。`:2-4` 的文件头就是这条链的目录：
"video_timing_1024x600 出时序 → `axi_frame_writer_gated`/`64` 把 DDR 里刚提交的一帧搬进显示帧缓存 →
`fb_bilin` 读口 → `proc_pipeline` 效果链 → `split_display` 原图/处理图逐像素混合 → `osd_overlay` 叠状态字 →
同一份 RGB888+同步走 `u_dvi`"。`:6-7` 另写一条硬规矩：**显示 BRAM 只在消隐期写**。

### 8.1 光栅产生（`src/rtl/video/video_timing.v` 72 行 + `video_timing_1024x600.v` 27 行）

结构：**单个 `h_cnt` 行内计数 + 行尾进位 `v_cnt` 场计数**，都 12 bit（`:37-45`）。
`h_cnt == H_TOTAL-1` 时回零并让 `v_cnt` 加一，`v_cnt == V_TOTAL-1` 时回零。复位把两个计数钉 0（`:33-35`）。
段次序是"**有效在最前**"：`0..H_ACTIVE-1` 是有效列，`[H_ACTIVE, H_ACTIVE+H_FP)` 前沿，
同步在 `[H_ACTIVE+H_FP, +H_SYNC)`，H_BP 是剩下尾巴（`:49-51`）。
`H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP`（`:26`）、`V_TOTAL` 同式（`:27`）。

极性在**输出寄存器**里翻转：`hs <= H_POL ? hs_act : ~hs_act`（`:65`）、`vs` 同（`:66`）、`de <= de_act`（`:67`）。
`x <= h_cnt`、`y <= v_cnt`（`:63-64`）与 `de` 同拍对齐（都晚计数一拍）。

| 量 | 通用默认（`video_timing.v:5-14`） | **1024x600（现役）** | 720p（无人例化） |
|---|---|---|---|
| H_ACTIVE / V_ACTIVE | 640 / 360 | **1024 / 600** | 1280 / 720 |
| H_FP / H_SYNC / H_BP | 16 / 64 / 80 | **44 / 88 / 188** | 110 / 40 / 220 |
| V_FP / V_SYNC / V_BP | 4 / 6 / 12 | **3 / 6 / 16** | 5 / 5 / 20 |
| H_TOTAL / V_TOTAL | 800 / 382 | **1344 / 625** | 1650 / 750 |
| H_POL / V_POL | 0 / 1 | **1 / 0**（"`HSYNC +, VSYNC −`"） | 1 / 1 |
| 像素钟 | — | 50 MHz（spec 50.25，0.5 % 可接受） | 75 MHz |

行号：现役四段参数在 `video_timing_1024x600.v:19-20`，极性与注释在 `:5,21`，H_TOTAL/V_TOTAL 的算式在
包装文件的 `:22` 与文件头 `:3-4`。`video_timing_720p.v:2` 自陈"**本树无人例化**"。

两个场事件脉冲：`frame_start = de_act && h_cnt==0 && v_cnt==0` 寄存一拍 ⇒ **落在第一个有效像素那一拍**
（`x=0,y=0` 同拍，`:68`）；`frame_done = h_cnt==H_TOTAL-1 && v_cnt==V_TOTAL-1` 寄存 ⇒ 落在场消隐末拍（`:69`）。
"行尾才加 `v_cnt`"这个次序被 `raw_line_delay.v:70` 显式引用为依赖项。

派生的顶层常数：消隐行数 `625-600 = 25`（`pl_video_top.v:397-398` `DISP_V_LINES=600`/`DISP_V_LAST=624`）、
行消隐 `1344-1024 = 320` 拍（`:294-295` 与 `raw_line_delay.v:59`）、
`VB_X_GUARD = 1279`（`:399`，注释原文"H_TOTAL(1344) − 65：早关 64 个消隐像点"）。

### 8.2 片源仲裁 `src_arb`（455 行的顶层里最容易被答错的一块）

**先纠正结构前提：这里没有状态机。** `grep -n "case (\|localparam S_\|reg \[.*:.*\] st" src/rtl/util/src_arb.v`
→ 0 命中。全部时序行为由 **一个 1 bit 主人位 `owner_eth`（`:31`）+ 一个 32 bit 静默计数器 `quiet`（`:47`）**
构成（`:53-78` 一个 always 块）。回答"仲裁 FSM 有哪些状态"的正确答案是"**没有 FSM**"。

判据与转移（逐行）：
- `force_eth = (sel == 2'd01)`、`force_ps = (sel == 2'd10)`（`:44-45`）。
- `both_idle = ~row_busy & ~fill_busy`（`:48`）——`row_busy` 是 ETH 拷贝引擎在忙、`fill_busy` 是 PS 拷贝引擎在忙。
- `eth_wanted = force_eth ? 1 : force_ps ? 0 : (eth_live & eth_tb_ok)`（`:51`）。`:49-50` 原文：
  "时基不准时一律当作'没有流'：宁可让 PS 接管（它至少能立刻出画面），也不要在一个无法证实的电平上锁死显示端"。
- `quiet` 只服务**一个方向**：`:61-64`——`!eth_wanted` 时递增并**饱和在 `32'hFFFF_FFFF`**；`eth_wanted`
  一到立刻清零（原文"ETH 一活就清零（**回抢不等**）"）。
- **唯一的主人赋值点在 `if (both_idle)` 之内**（`:66-76`）：`if (eth_wanted) owner_eth <= 1;
  else if (quiet >= T_OFF_CYC) owner_eth <= 0;`。除 `both_idle` 之外没有任何路径能改主人 ⇒
  **不会切断任何一次拷贝**。
- 复位：`owner_eth <= 1'b0`（注释"配置完成时两边都没东西，先给 PS"）、`quiet <= 0`、
  **`why_ps <= 3'b011`**（`:57-59` 原文："复位值取'没有流 + 时基还没验'（011），不取 000：000 的意思是
  '一切正常、是被人钉住的'，那是刚上电时最不该撒的谎"）。

`T_OFF_CYC = 2_000_000` 量的是**哪个钟**：`:18` 原文"AXI 域 100 MHz ⇒ 2_000_000 = **20 ms**"，
`:19`"这是**第二级**滞回：第一级是 `stall_ms > LIVE_MS`（默认 200 ms）"；时钟就是 `clk = axi_clk`（`:22`，
顶层 `pl_video_top.v:421-422` 递 fclk0）。

`sel` 编码**不是** `src_mode` 的四态码（`:26-28` 原文点名）：这里 `00=AUTO 01=强制ETH 10=强制看 fb(=SD) 11=按 AUTO`；
适配器是 `pl_video_top.v:171` 一行
`arb_sel = (ms2==M_ETH)?2'd1 : (ms2==M_SD)?2'd2 : 2'd0;`，`:170` 说明"图卡模式不参与仲裁（保持 AUTO）：
它只是'显示什么'，不是'谁在搬'"。`M_AUTO=0/M_ETH=1/M_SD=3/M_TEST=2` 在 `pl_video_top.v:152` 与
`src_mode.v:24`。

`why_ps[2:0] = {force_ps, ~eth_live, ~eth_tb_ok}`（`:35-37,73`）：`[2]`=被人用 `src 1` 钉住（不是故障）、
`[1]`=时基准但没有流、`[0]`=时基本身不可信。**#174 这一刀**（`:68-72`）：`why_ps` 必须与 `owner_eth`
写在**同一个决定点**（即 `both_idle` 之内）。挂在无条件那一支会导致"拷贝期间（主人被互锁冻住）翻
`eth_live`，屏上/上位机读到的'为什么 PS 拿着'会跟着变，而主人一次都没换"。台架
`sim/tb_src_arb_why.v` 的 `W5` 钉这件事、`W7` 是反配对（"真换手那一拍必须重新快照 ⇒ 不许修成'再也不更新'"）。
⇒ **拷贝期间 `why_ps` 是冻住的**，这是可观测行为，不是 bug。

`eth_tb_ok` 的物理来源（`:11-14`，板级实测 2026-09-23）：断链时 RTL8211 **不停 RXC 而是拉到 ≈2.5 MHz**，
`stall_ms` 以约 1/48 速度爬，`stall_ms < 200` 会连着骗人十几秒。取法在
`system_top.v:255-256`：`eth_live = lm_axi[7*32+3]`、`eth_tb_ok = !(lm_clk_slow || lm_clk_gone)`，
其中两个旗标来自 `snap_cross` 的 `hb_gone`/`hb_slow`（§13 lane31）。

**"手递手交接"（handover）的逐跳**（回答"切片源会不会撕裂"要看这段）：
1. `:41-43` 原文：手动锁**只改"谁想要总线"，不改"什么时候能换手"**——"直接在输出上加一个 mux 是最容易
   想到的写法，也是错的 —— 那会在一次拷贝中途把选择位翻掉，留下**半开的 AXI 读突发**"。
2. 旧写法有两个病（`:4-8`）：`eth_mode = 3FF(|s_pkts)` ⇒ ARP 就触发；拔线不回 0 ⇒ PS 被永久锁死（ISSUES #47）。
3. `owner_eth` 一变，顶层 `eth_mode`（`pl_video_top.v:428`）同拍切换**14 处 mux**：AXI AR `:709-713`、
   R `:714,465-467,703-705`、帧缓存写源 `:716-718`、`start`/`allow_wr`/`abort` 三处 `eth_mode?…:1'b0`
   （`:457,459,460`）。两个引擎同在 `axi_clk` ⇒ 这一位**不跨域、不需要 CDC**，安全性全靠 `both_idle` 互锁。
4. 显示侧**不切**：像素域只把**结果**跨过来（`op0/op1/op2` 3 级，`:517-522`）。`:512-513` 原文：
   "这里再复制一份'活着'就会出现'ETH 那一位还在说谎、SD 帧却永远不被消费'的死锁 —— 板上的 STALL 钉在
   9999 正是它"。（⚠ `:513` 提到的 STALL=9999 是 OSD 的**显示钉值**，不是 9999 ms，见 `system_top.v:252-254`。）
5. 消隐窗由 `frame_commit_lock` 给（不是仲裁器）：`disp_quiet`（`:400-401`）→ `blank_safe`（`:434`）→
   `bs_d0/1/2`（`frame_commit_lock.v:46-53`）→ axi 域 `d0/d1/d2`（`:71-75`）→ `allow_copy_axi = d1 & d2`
   （`:76`）。`VB_X_GUARD` 那 64 个像点余量就是为这条链的延迟留的（`pl_video_top.v:399` 原文
   "allow_copy_axi 过 CDC 要晚这个窗口约 5 个像素拍"）。
6. PS 的发布不被消费时**不丢**：`pl_video_top.v:514-515` 原文"ETH 拥有搬运机时 PS 的发布不被消费
   （pend 留着，等轮到 PS 那一帧再消费），否则 pend 会在没人搬运的时候被清掉"；实现
   `pub_consume = frame_start && src_use && !owner_eth_pix`（`:559`）。
7. 机器判据在板上做（**需板端**）：`dbg_src` → lane30（`system_top.v:239`），解码脚本
   `src/host/arb_handover_test.mjs:67-75`（`OWN=(v>>>2)&1`、`LIV=(v>>>1)&1`、`TBK=v&1`、`FILL=(v>>>3)&1`、
   `ROW=(v>>>4)&1`、`MODEG=(v>>>5)&3`、`WHY=(v>>>8)&7`、`WHY_PS=(v>>>10)&1`），门限 `SETTLE_MS=2000`、
   `HBACK_MS=1500`（`:63-64`），判据 V0-V7 见 `:162-211`（V7 原文："AUTO 模式下 PS 占着屏只有两种正当理由：
   没流（bit1）或时基不可信（bit0）"）。

`src_arb` 位宽红线：`dbg_src` 在 `system_top.v:221-227` 声明 `wire [15:0] dbg_src;`，原文警告——
"位宽必须与 `pl_video_top.dbg_src` 一模一样（r54 起是 16 bit）。这里以前写过 `[5:0]` ⇒ 综合只给一条
`Synth 8-689` 警告就把模式高位**静默丢掉**：TEST(10) 读起来像自动(00)、SD(11) 像 ETH(01)（ISSUES #57）"。
⇒ 门禁第 14 项专门量这个（§17）。

### 8.3 两条 DDR→显示 BRAM 的搬运引擎（同口分时，两代实现）

| 引擎 | 实例 | 文件 | 谁用它 | 关键结构 |
|---|---|---|---|---|
| ETH 拷贝 | `u_row` `axi_frame_writer_gated` | `src/rtl/axi/axi_frame_writer_gated.v`（190 行） | `pl_video_top.v:454-469` | `MAX_OUT=3'd4`（`:47`）、skid 分布式 RAM `SK=6`（`:48,53-54`）、`ARLEN=15` INCR（`:38,132,150`）、**只在 allow 那几拍落 BRAM**（`:2-4,81,87-89`）、abort 排空 `drain_left=outstanding`（`:144`，#170）、完成判据 6 条件（`:182-186`） |
| PS 拷贝 | `u_aw` `axi_frame_writer64` | `src/rtl/axi/axi_frame_writer64.v`（115 行） | `pl_video_top.v:692-707` | `arlen=15`（`:50,72,101`）、`arsize=3'b011`（`:33`）、`arburst=2'b01` INCR（`:34`）、`fb_wr_data <= m_axi_rdata` **64bit 原生直写不拼接**（`:86`）、`fb_wr_addr = waddr_pix[18:2]`（`:85`）、`waddr_pix += 4`（`:87`）、跨行 `base_r+(row+1)*ROW_BYTES`（`:100`）、`BURSTS_ROW = IMG_W/64 = 8`（`:39`）、`ROW_BYTES = IMG_W*2 = 1024`（`:40`）、单发不并发（等 `rlast` 才发下一 AR，`:88-109`） |
| （遗留） | — | `src/rtl/axi/axi_frame_writer.v` | 无 | 把 64bit R 拍**拆成 4 拍 16bit** 写旧帧缓存（`S_UNPACK :114-128`）、6 态 FSM `:40-45`；文件头 `:2-3` "本树无人例化" |

`MAX_OUT=4` 的理由写在 `axi_frame_writer_gated.v:45-46`："4×16-beat in flight ≈ 64 beats 覆盖 HP0/DDR 延迟"。
skid 必须显式分布式 RAM 的理由在 `:50-52`（Synth 8-4767 掉触发器事故）。

⚠ `u_aw` 的 `enable` 吃的是**未同步的 `src_sel`**（`pl_video_top.v:696`），而同一信号的像素域消费者吃
`src_sel_pix`（`:537`）。`:556-558` 有自述"这里原来用 `src_sel`（axi_clk 域的未同步电平）……帧起始那拍采它会
采到亚稳态"——**那句话讲的是 `pub_consume` 那一处**，不要把它当成"`u_aw` 已经修好了"。两处是不是同一个
问题，本文没有结论（`未找到` 明确针对 `u_aw.enable` 的讨论）。

### 8.4 帧提交锁与消隐窗（`src/rtl/video/frame_commit_lock.v`）

它锁的是**"什么时候允许把 DDR 里那一帧写进显示 BRAM"**，物理理由（`pl_video_top.v:6-7`）：
显示 BRAM 的读口正被光栅逐像素扫描，写口在有效期内改内容 = 屏幕上同一条扫描线前后半不同帧 ⇒ **撕裂**。
所以写只准在 V 消隐的 25 行窗口里发生。

实现（逐行）：
- 像素侧：`bs_d0/1/2` 三级打 `blank_safe`（`:46,53`），`blank_pix = bs_d2`（`:57`）；
  `vs_d0/vs_d1` 抓 `vsync` 上升沿 `vs_rise`（`:45,52,56`）；`blank_tog` 在 `vs_rise` 翻转（`:59-63`）。
- AXI 侧两条独立 3FF：`(* ASYNC_REG="TRUE" *) b0,b1,b2` 打 `blank_tog` ⇒ `vsync_req = b1 ^ b2`
  （`:64-69`，**用翻转位而不是电平**是为了给出"场开始"这一事件）；`d0,d1,d2` 打 `blank_pix` ⇒
  `assign allow_copy_axi = d1 & d2;`（`:71-76`，**两级与而不是异拍**——它是电平窗，不是事件）。
- 拷贝起点：`:78-80` 原文（v6 那次改动）"start the copy at the **OPENING** of the allow window, not at the
  vsync edge. With 1024x600 (V_FP=3, V_SYNC=6) vsync only rises 9 blank lines into a 25-line window, which
  **throws away a third of the copy budget**." ⇒ 预算账：窗口 25 行 = 25×1344 = 33600 像素拍，
  顶层 `VBLANK_AXI_AXI_CYC = 67200`（`pl_video_top.v:446`，axi 100 MHz 拍）；超窗观测位
  `copy_overrun`（`:448-452`）挂在 `led[0]` 的 mux 上（`:1039`，正常 1.5 Hz、越窗 6 Hz）。
- `pending` 位（`:40-42`）：提交来了但窗口没开，先记着，窗口开时补发。
- ⚠ 参数 `IMG_H=300`（`:6`）、`DISP_H=600`（`:7`）在**本文件内声明后没有任何使用点**
  （`grep -n "IMG_H\|DISP_H" frame_commit_lock.v` 只命中 `:6,:7`）——顶层例化时传了值（`pl_video_top.v:431-432`）
  但不生效。**别把这个模块当成会按行数校验拷贝量的门**。

### 8.5 显示帧缓存（`src/rtl/video/frame_buffer_w64.v`）—— 为什么拆两块阵列

```verilog
(* ram_style = "block" *) reg [63:0] lo [0:D_LO-1];   // :37
(* ram_style = "block" *) reg [63:0] hi [0:D_HI-1];   // :38
```
- 需要 `WORDS = (W*H+3)/4 = 38400` 个 64bit 字（`:32`，`W=512,H=300 @:9-10`）。
- **为什么不是一整块 65536 深**：`:4-7` 原文——非 2 幂深度会被向上填到 `2^16`，**吃 128 块 RAMB36，
  而全片才 140 块**；拆成 `D_LO = 2^15 = 32768` + `D_HI = 8192`（`:33-35`，用 `bitsof()` 函数 `:23-30`
  算出来）实测 **80 块**（对照实验在 `tmp_ramtest/fbtest.v`，v0=128 / v5=80）。
- 端口：写 64bit（`wr_data = {p3,p2,p1,p0}` `:15`）在 `wr_clk`，读是**16bit 随机地址 + 原始 64bit 字**
  两个逻辑口共用**一个物理读口**（`rd_data`/`rd_data64` `:19-20`）在 `rd_clk`（`:12,17`）⇒ 双时钟 BRAM。
- **读延迟 1 拍**（`:3,62-68`）：`q_lo/q_hi/sel_hi/sel_lane/blank` 全部寄存一级；两块**每拍都读**、
  用 `sel_hi` 选（`:70`）；车道 mux `:72-79`；越界**夹回黑**而不是产 X（`blank :67,80`，`:63-64` 原文
  "地址用掩码夹住不产 X"）。

### 8.6 缩放/旋转地址生成：**逆映射**，Q8 定点，无运行时除法

四件套（顶层 `pl_video_top.v:322,325,343,652`）：`zoom_fit`（算 fit 值）、`zoom_ctrl`（倍率唯一出处）、
`zoom_mapper`（真正的地址映射）、`zoom_snap`（跨域快照）。

**方向：逆映射。** `zoom_mapper.v:2` 原文"右屏无极缩放**逆映射**：屏幕 (x,y) → 源图 (sx,sy)"。
⚠ 关于"为什么不用正向散写"，两文件**没有成文注释**（`未找到`；检索式
`forward|scatter|正向|散写|hole|空洞`）。可陈述的实现事实是：逐输出像素算源坐标
（`zoom_mapper.v:96-116`），因此不需要原子写、不会留空洞、也不会重叠覆盖——**别把这条说成"文档里写了的理由"**。

- **流水**：3 级（`:3`）。s0 中心偏移 `:29-36`：`xp = x_in - IMAGE_W/2`；注意 **Y 轴两套口径并存**——
  数学系 `yp_math = IMAGE_H/2 - y_in`，显示系 `yp_disp = y_in - IMAGE_H/2`（`rotate_mapper.v:26-27` 同形）。
  s1 旋转 `:42-55`（Q8 三角表），s2 乘 `inv_scale` `:58-66`：旋转支 `>>>16`（Q8×Q8=Q16），
  非旋转支 `>>>8`。
- **越界填什么**：`:103-108`——`sx_c<0 || >=IMAGE_W` 等 ⇒ `x_out/y_out = 0`、`oob = 1`、`frac = 0`。
  ⇒ 填的是**图内第 0 像素 + 一个越界旗标**，不是直接填黑；"黑"是后面 `fb_bilin`/`pix_raw` 用 `oob` 决定的。
- **小数与旋转的纵向翻转**（`:70-94`，#104/#189）：`rot_fx = rot_xs[15:8]`（`:75`）；
  `rot_fy` 需要 `256 - ceil(f·256)`，且 `rot_y_has_frac` **必须看完整 16 bit**（`:81-86`，`:76-80` 原文
  "只看高字节会把 (0,1/256) 读成没有小数 ⇒ 沿角度方向稀疏错一行鬼影，**实测 0.27 %**"）。
  floor/frac 自洽靠 `>>>8` 朝 −∞ 取整（`:90-94`）。
- **倍率唯一出处在 `zoom_ctrl` 不在顶层**：`:16-21` 原文给出理由——否则"屏上那格与真正在用的 `inv`
  不是一回事"（#52/#59/#66 那一族），lane23 是判据。八档表（Q8 倒数尺度，**数越大倍率越小**）`:44-53`：

  | 档 | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
  |---|---|---|---|---|---|---|---|---|
  | `inv` | 1023 | 776 | 512 | 341 | 256 | 192 | 171 | 128 |
  | 倍率 | 0.25× | 0.33× | 0.50× | 0.75× | **1.00×** | 1.33× | 1.50× | 2.00× |

  `:44-46` 原文解释 1023 而不是 1024：**10 bit 天花板**。呼吸带参数 `INV_LO=256`、`INV_HI=512`、`STEP=2`
  （`:6-8`），呼吸只在 `[256,512]` 走（`:38-39`），手动档允许越界到 2.0×/0.25×（逆映射 inv 变小 = 采样窗
  内收不越界；inv 变大 = 四周填黑）。`!enable` ⇒ `inv_scale <= INV_LO(=256=1.0×)`、`zoom_active <= 0`（`:101-104`）。
- **`zoom_code`（OSD 上那一格）不做除法**：`:57-62` 原文强调不能做运行时除法（**#58 组合除法器 −5.014 ns**），
  改成与相邻档中点比大小的 7 级比较（`:76-83`，阈值 900/644/427/299/224/182/150），寄存一拍（`:95`），
  且 `:93-94` 要求它"只跟上一拍的 `inv_scale`，不进组合链"（V7.9.4 教训）。
- **旋转钳制**：`:64-74`——`inv_raw = fit_en ? inv_fit : inv_scale`（`:64`）、
  `rot_clamp = rotate_en && (inv_raw < inv_fit)`（`:72`）、`inv_used = rot_clamp ? inv_fit : inv_raw`（`:73`）。
  ⇒ 旋转时画面**不会大于刚好装得下**那一档；取较大 `inv` = 画面较小。`rotate_active` 的定义是
  `angle != 0`（`angle_ctrl.v:18`），`:66-71` 注释明确 **0° 不参与钳**。
- **`zoom_fit` 的几何式**（`:2-7`）：`W' = s(W·|cos| + H·|sin|)`，要求装得下 ⇒
  `inv_x = (W·C + H·S)/W`、`inv_y = (W·S + H·C)/H`，取较大者。**除法折成乘 elaborate 期常数 + 定长移位**：
  `REC_W = (2^NSHIFT + W/2)/W`、`NSHIFT = 20`（`:11,26-30`，`:26` 原文又点了 #58 那一课），
  `ix = (nx*REC_W) >> NSHIFT`（`:44-45`），余量 `fit_raw = imax + (imax>>8) + 2`（`:48-51`，
  覆盖 ±0.5 LSB 表误差）。两拍流水（`:34-43`，`:35-36` 记下 slack +1.843 ns 的实测）。
  `IMAGE_W=512, IMAGE_H=300`（`:9-10`）。
- **三角表**：`src/rtl/process/rotate/sin_rom.v` / `cos_rom.v`，**表深 360、角度步长 1°**，
  输出 `reg signed [9:0] value`（`sin_rom.v:5`），格式 **Q8（256 = 1.0）**（`:2` 原文
  `round(fn(angle_deg)*256)`），内容**硬编码 auto-generated**（不是固件下发），`cos(0°)=256`（`cos_rom.v:9`）。
- **角度不是 24 bit 累加器，是 9 bit 十进制度 0..359**：`output reg [8:0] angle`（`angle_ctrl.v:15`）。
  自动步进 `:33-34` `up = {1'b0,angle} + {7'd0,speed}`（10 bit 加），取模**用减 360**而不是到 359 回 0
  （`:31-32` 原文"360 = 7·51 + 3"）。`speed[2:0]` ⇒ 每帧最多走 **7°**（`:14,31`）。
  帧边界步进吃的 `frame_tgl` 是**翻转位**（不是脉冲），3 级 `ASYNC_REG` 同步（`:24-29`）；
  `:4-6` 原文给理由："帧中换角 = 上半下半两个角，那一行错开"，`:20-23` 记 CDC-11 事故（#65 / r54 构建 #34）。
  发射点在 `pl_video_top.v:304-314`（`rot_fs_tog` 由 `fs_de_d` + `wrap_row_next/now` 决定），
  ISSUES #167 的"换角翻拍点"事故与判据 `sim/tb_head_rot_displace.v`（ACCEPTANCE.md E4r）挂在 `:286-309`。
- **快照防撕裂（`zoom_snap`）**：`:5-7` 两条不变量——① `bus` 只在**帧首整拍**换、保持一帧（≈16.7 ms），
  满足 `snap_cross` 的准静态前提（`:37-39`）；② `bus_tog` 每次真实变化**恰好翻一次且晚 8 个像素周期**
  （≈318 ns），落在总线稳定**之后**（`:41-42`，`dly[7:0]` 移位 `:30,36`）。打包式 `:27`：
  `in_bus = {rot_forced, zman, zsel, zoom_code, zoom_active, zoom_dir, inv_scale}`（20 bit，
  `rot_forced` 放最高位使低 19 位不动，`:25-26`）。
  撕裂反例写在 `pl_video_top.v:649`："对照是'19 位各自打两拍 ⇒ 读到半新一半旧'（#52/#59）"；判据 tb_v95。
  `:6-7` 还写明**晚一拍会发上一帧值**（目的域永久落后一档，tb_v95 末态检查红）。

### 8.7 双线性读侧（`src/rtl/process/bilin/fb_bilin.v` + `bilin_lerp.v`）

**为什么是"每源像素 4 拍"**：`fb_bilin.v:4-5,39-40`——一个源像素要覆盖 **2 个显示列 × 2 个显示行**
（因为 `OUT_W = 2*IMG_W`，源图放在右半屏），而单读口 BRAM 每拍只能读 1 次 ⇒ 4 个 `clk_pix` 拍刚好用完，
**没有多余的读带宽**。这就是历史上那版"5× 快时钟"方案被放弃的背景（§11.4）。

- 地址生成 `:42-45`：`pxl = sy*IMG_W + sx`，`w_a = pxl[18:2]`（64bit 字下标），`lane = pxl[1:0]`，
  `w_b = w_a + ROW_WORDS`，`ROW_WORDS = IMG_W/4 = 128`（`:34`）。
  `:41` 原文点出选型理由：**`IMG_W` 是 2 幂 ⇒ `sy*IMG_W` 综合成连线（不要乘法器）**，是 4 倍 ⇒ 整除。
- 四相位调度 `:37-38,56`：`col0 = ~x[0]`、`row0 = ~y[0]` 组成 (row0,col0) 四种相位，依次发 A、A+1、B、B+1。
- 越界折回 `:51-54`：末列/末行把小数钉 0 **且抽头折回图内**（`kx_use/ky_use`）。`:49-50` 原文：
  若只做"小数钉 0"会读到填充区（**硬件 0 / xsim X，而 X×0 = X ⇒ 污染整行**）。
- 抽头暂存：A 行凑齐时把 `{p10,p00}` 写进 `tap_hold[0:IMG_W-1]`（**512×32，block RAM** `:142,153`），
  B 行到达时喂 lerp（`:157-162`）；读的是 2 拍前的 `j`：`tap_r <= tap_hold[j_d1]`（`:152`）。
- 结果缓冲乒乓：`res[0:2*IMG_W-1]`（**1024×17，正好一块 RAMB36** `:180-184`），写
  `res[{h_d4,j_d4}]`、读 `res_q <= res[{~h_d1,j_d1}]`（`:188,191`），乒乓半号 = `pair_odd = y[1]`。
  `:194-195` 原文：本模块**不声明 LAT**，由 `sim/tb_v101_fb_bilin.v` 用"唯一平移量搜索"量出并钉住；
  乒乓极性错了的症状是"每一行前半新后半旧的撕裂"。
- 标签链纪律 `:83-85` 原文：**"不许给标签另开一条延迟链：标签与内容不同级就是错"**（四级 d1..d4 `:86-117`）。
- 内容整体晚 **1 对显示行 = 2 个显示行** ⇒ 顶层喂给 mapper 的行号必须再加 `BILIN_ROWS`
  （`:182` 原文；顶层 `pl_video_top.v:276` `y_right_adv = y + pipe_off_rows + BILIN_ROWS`）。
- **`BILIN_ROWS` 必须是偶数**（顶层 `pl_video_top.v:249` 原文）："`row0 = ~y[0]` 定成对奇偶，奇数会让一对
  分属两个源行 ⇒ A/B 错行。凭据 **tb_v89 T1、tb_v101 L3/L6、tb_v98 C1c/C1d/C1h**"；定义 `:250 = 2`。

**算术核 `bilin_lerp.v`**（两级，横向→纵向）：
- 权重格式 **Q8**（`fx/fy` 8 bit 表示 [0,1)，`:15-16`），`:6` 原文"**两两权重之和恒为 256**"。
- 位扩展用**复制低位**：`rep5 = {v, v[2:0]}`、`rep6 = {v, v[1:0]}`（`:20-21`）。`:4-5` 原文：
  "**全 1 展开正好 255 ⇒ 纯白不因展开变灰**"。⚠ 这与效果链的"复制高位 `{r5,r5[4:2]}`"是**两种不同口径**
  （见 §8.8 末）。
- 横向 `:29-30,39-44`：`wx0 = 256 - fx`、`wx1 = fx`，`tr = r00*wx0 + r10*wx1`（寄存一拍，17 bit 封顶）。
- 纵向 `:51-55`：`wy0 = 256 - fy1`、`wy1 = fy1`，`or_r = tr*wy0 + br*wy1 + 26'd32768`
  ⇒ **一次 `+2^15` 再 `>>16` 四舍五入**（`:7` 原文）。
- 取位 `:59-61` `vr = or_r[24:16]`，回 565 `:67` `{vr[7:3], vg[7:2], vb[7:3]}`。
  `:6,57` 结论：**不需要饱和**（权重和恒 256 保证 ≤255，由 tb 判据 2 强制）。

### 8.8 效果链七级（`src/rtl/process/proc_pipeline.v` 与各算子）

链序与逐级拍数（`proc_pipeline.v:18` 原文逐字："灰度1 + 反色1 + 模糊3 + 锐化3 + Sobel3 + 阈值1 + 形态学3 = 15"）：

| 级 | 模块 | 例化行 | 拍 | 旁路接法 |
|---|---|---|---|---|
| 0 | `gamma_lut` | `:102-106` | **0**（组合读出） | 自己的 `en` |
| 1 | `proc_gray` | `:109-112` | 1 | `.bypass(~w_gray)` `:110` |
| 1 | `proc_invert` | `:113-116` | 1 | `.bypass(~w_inv)` `:114` |
| 2 | `proc_box_blur` | `:119-124` | 3 | `:120` |
| 2 | `proc_sharpen` | `:125-129` | 3 | `:126` |
| 3 | `proc_sobel` | `:132-137` | 3 | `:133` |
| 4 | `proc_binary` | `:140-143` | 1 | `:141` |
| 5 | `proc_morph` | `:146-150` | 3 | `.mode(morph_mode)` `:147` |

控制字 `stage_sel[8:0]` 位定义（`:5-6` 原文，**唯一定义处**）：
`[0]灰度 [1]反色 [2]3×3 模糊 [3]3×3 锐化 [4]Sobel [5]二值化 [6]判决反相(仅 [5]=1 有意义) [7]腐蚀 [8]膨胀`。
逐位直取 `:52-61`；**腐蚀/膨胀互斥**：`w_erode = stage_sel[7] & ~stage_sel[8]`、
`w_dilate = stage_sel[8] & ~stage_sel[7]`（`:59-60`，**同时为 1 两个都不做**）；`morph_mode` 编码 `:61`
（erode→`2'd1`，dilate→`2'd2`，否则 0）。
**旁路不在 pipeline 里做 mux**，而是把 `~w_x` 接进每个算子的 `.bypass`，真正的透传在算子自己的输出寄存器里
（如 `proc_gray.v:32` `dout <= bypass ? din : gray`）。⚠ **de 链不受 bypass 影响**（`:17` 原文）⇒ 延迟恒 15。

`H_ACTIVE` 语义警告（`:9-12` 原文，答错"模糊半径"就是这里）："`H_ACTIVE` 是一行有多少个**有效拍**，不是显示
屏有多宽。顶层现在传 `#(.H_ACTIVE(2*IMG_W))` = 1024 个有效拍 ⇒ **3×3 窗口的空间尺度现在就是按 1024 列算的**……
横向模糊/锐化/Sobel 的半径因此是**半个源像素**"。顶层例化确在 `pl_video_top.v:800`。
（各算子文件头的默认值 640/512 **一律不生效**：`proc_box_blur.v:5`、`proc_sharpen.v:8`、`proc_sobel.v:7`、
`proc_morph.v:9`。）

**逐个算子的数学（含定点口径）**
- **`gamma_lut.v`——为什么占 0 拍（这条要在硬件里自证）**：
  `(* ram_style="distributed" *) reg [7:0] tr/tg/tb [0:255]`（`:27-29`，256 项 × 8 bit × 3 通道，
  `:3-4` 原文说三张读表**复制三份**）。组合读出的直接证据：
  `:51` `wire [15:0] y16 = {tr[r8][7:3], tg[g8][7:2], tb[b8][7:3]};`（地址就是**当拍输入**）+
  `:52` `assign dout = en ? y16 : din;`，且 `output wire [15:0] dout`（`:16`）——**全模块没有 dout 寄存器**
  ⇒ 0 拍。`:4` 原文给出取舍："**用表不用幂函数**：PL 里做 `in^(1/γ)` 要堆 DSP 或做对数/指数近似"。
  ⇒ **γ→曲线的数学不在 RTL 树里**（`未找到`；检索式 `pow|exp|gamma` 于 `gamma_lut.v` 只命中存储与边沿写）。
  曲线由 **PS 固件算好后逐项写入表项**（`:1-2` 原文"256 项 8-bit 表，PS 通过第二个控制字的通道 2 逐项写入"；
  固件侧 `src/ps/main.c:379` 用 `pow`，链接要 `-lm`）。写口只在 **`wr` 翻转沿**写（`:34-39` prev/do_wr 边沿检测，
  `:31-33` 记 ISSUES #52"上电那一拍被当成一次写"的事故）。
- **`proc_gray.v`**：BT.601 用**整数乘加**不用移位近似——`:21` 原文
  "ITU-R BT.601 approx 0.299R+0.587G+0.114B => *77 + *150 + *29 >> 8"；
  `:22` `y16 = r8*8'd77 + g8*8'd150 + b8*8'd29`，`:23` `y8 = y16[15:8]`；回 565 `:24`
  `gray = {y8[7:3], y8[7:2], y8[7:3]}`（三通道同值 = 去色）。位扩展 `:18-20` **复制高位**
  `r8 = {r5, r5[4:2]}`、`g8 = {g6, g6[5:4]}`、`b8 = {b5, b5[4:2]}`。
- **`proc_box_blur.v`：3×3 均值，不可分离**——`:104-112` 三个通道各**在 9 个抽头上直接相加**。
  **除法 = 累加后乘倒数再右移**：`:114` 原文 "*57 >> 9 ≈ /9 (57/512 ≈ 0.1113)"，`:115-117` `rp = rs*17'd57`，
  `:118-120` 取 `rp[13:9]`。位宽：R/B 用 9 bit 和、G 用 10 bit 和（`:104,107,110`）。
  行缓存：`lb0/lb1` 各 `H_ACTIVE` 项 16 bit，`ram_style="distributed"`（`:19-20`）。
  **边界 = clamp-to-edge（复制中心）**：缺左邻复制 `p01/p11/p21`、缺右邻复制中心列（`:89-91`），
  缺上邻复制中心行、**陈旧行**用当前行三行替换（`:95-101`）。⇒ **"边界补零/补黑"是错的**。
  3 拍：`de_d1<=de_in; de_d2<=de_d1; de_out<=de_d2`（`:144-146`）。
  行尾补跳一拍：`shift_w = de_in || line_end`（`:38`），`run/owed/line_end` `:31-37`（`:25-30` 记 #92 第四笔；
  `:33` 原文警告"拿 `de_d1 && !de_in` 当行尾会在**每个 de 断点**多跳一次"）；读地址钉末列 `x_rd` clamp `:42`；
  四个边界旗标链 `no_left_r/no_right_r/no_above_r/stale_row_r` 各 3 级且**必须与中心链同拍移位**
  （`:70-85`，`:71-72` 原文"否则边界位与内容差一格——那正是 #54 (A') 记过的'比的是发出去之后第几拍'那一族"）；
  复位只准在一个 always 块里（`:66`，Synth 8-6859 事故）。
- **`proc_sharpen.v`：核 `[0,-1,0; -1,5,-1; 0,-1,0]`（四邻是上/下/左/右）**（`:2`）。
  ⚠ **不是 unsharp mask**，不与 blur 组合；`:2-3` 原文说 blur 与 sharp 是"**同一级的两个选项**、不是串联：
  先模糊再锐化几乎等于什么都没做，所以控制字里这两个占同一个字段"。
  中心×5 拆成 `×4 + ×1`（`:92,95,98`，移位相加）；4 邻相加 `:93-94`。
  **先比较再相减**（`:4-5` 原文"Verilog 的无符号减法会回绕，直接 `a-b` 然后判负是错的（表现是
  '暗边变成一圈亮边'）"），`:102-104` `r_d = (r_c > r_n) ? (r_c - r_n) : 0`；饱和 `:105-107` 夹到 R/B 31、G 63。
  ⚠ **文件头 `:5` 写"延迟与 blur 一致（固定 2 拍）"是陈旧措辞**：它的 de 链实际是三个寄存器
  （`de_d1, de_d2, de_out` @`:124-126`），`proc_pipeline` 也按 3 拍记账。LATENCY 只有一处出处
  （`proc_pipeline.v:22`），所以这个措辞不一致**不影响硬件**，但引用"锐化几拍"时要以 3 拍为准。
- **`proc_sobel.v`**：亮度同款 77/150/29 `:30-37`，行缓存存 **8 bit 亮度**（`:20-21`），另有一条 `mc1`
  存**原色**专供旁路（`:27,43`，`:22-26` 原文解释：旁路要搬 16 bit RGB565 且**取同一中心抽头**，是 tb_v84
  的差分判据）。`Gx = -p00 -2*p10 -p20 +p02 +2*p12 +p22`（`:111-112`，11 bit signed）、
  `Gy = -p00 -2*p01 -p02 +p20 +2*p21 +p22`（`:113-114`）。
  **幅值 = `|Gx| + |Gy|`，不是真开方**：`:115-117` `agx = gx[10] ? -gx : gx` 等、`mag = agx + agy`（12 bit）；
  钳制 `:118` `m8 = (mag > 255) ? 255 : mag[7:0]`；回 565 `:119`。3 拍 `:142-144`。
  旁路式 `:150` `dout <= stale_row ? d21 : c11`，`:145-149` 原文记录以前写 `din` 的后果：
  "**开 Sobel 画面跳一行 + tb_v89 量到的 +2 列**"，并把这类错误命名为"**本级自洽凌驾全链一致**"。
- **`proc_binary.v`**：`y8 = (77R+150G+29B)>>8`（`:22`），`cmp = (y16[15:8] >= threshold)`（`:23`，
  **大于等于阈值算亮**），`bin = pol ? ~cmp : cmp`（`:24`，`pol = stage_sel[6]`）。`:4` 原文
  "pol=0 亮于阈值算白（V7 行为）；pol=1 暗于阈值算白"。输出**只有满量程两值**：`:25` `16'hFFFF` / `16'h0000`。
  **没有滞回**（文件里没有上一帧参考量）。1 拍 `:32-33`。
- **`proc_morph.v`：单遍，只做腐蚀**或**只做膨胀**，**不支持开/闭**。`:13` `mode`：`0/3 旁路 1 腐蚀 2 膨胀`；
  `:22-24` 原文"mode 3 是'开/闭运算'的位置，但那是**两遍**窗口……一遍做不出来……显式当旁路"。
  结构元 = 全 3×3 方形：`all1 = m00 & … & m22`、`any1 = m00 | … | m22`（`:115-116`），`res = (mode==1)?all1:any1`
  （`:119`）。掩码在**输入处**由亮度判定 `:34` `bin = (y16[15:8] >= threshold)`（与 `proc_binary` 同式）。
  行缓存：两条 **1 bit** 掩码行缓存 `mb0/mb1`（`:40-41`，`:6-7` 原文"两条掩码行缓存 = 512 bit × 2"）
  + 一条 16 bit 原色行缓存 `mc1` 仅供旁路（`:44`）。`:36-39` 记 `Synth 8-7186`：写成
  `reg [0:H_ACTIVE-1]` 向量会退化 2×H_ACTIVE 个触发器。3 拍 `:137-139`（`:139` 原文"三拍，不是两拍 ——
  见文件头与 ISSUES #54"）；边界 clamp-to-edge `:104-113`；旁路 `:142`。

**同一工程里并存的三种位扩展口径**（引用任何"5→8 bit"公式前先说是哪一处）：
1. 复制**高**位：`{r5, r5[4:2]}` —— `proc_gray.v:18`、`gamma_lut.v:20-25`、`proc_binary.v:16-22` 等效果链。
2. 复制**低**位：`{v, v[2:0]}` / `{v, v[1:0]}` —— `bilin_lerp.v:20-21`（`:4-5` 说这条是为了"全 1 展开正好 255"）。
3. **截高**位：`{r[7:3], g[7:2], b[7:3]}` —— `test_card.v:198` 的图卡输出打包。

**坐标延迟线（proc_pipeline 内部）**：`:82-98` 用 `reg [11:0] xd[1:12] / yd[1:12]`，纯寄存器每拍一跳
（`:82` 注释"288 个触发器（Slice 寄存器 7936 的 3.6 %）"），`xd[1] <= x_in` 起跳（`:89`），抽头
`x_blur = xd[2] :95`、`x_sharp = xd[5] :96`、`x_sobel = xd[8] :97`、`x_morph = xd[12] :98`
（`:74` 原文：抽头号 = 该级 de_in 之前累积拍数）。`:75-81` 记 **#103 根因**：旧版写 `xd[0] <= x_in`
使 `xd[k]` 其实是 k+1 拍 ⇒ 列标签比数据晚一拍 ⇒ ①末列槽 `H_ACTIVE-1` 永不写、②行首消隐值
`1343 mod 1024 = 319` 越界写黑线。判据 `sim/tb_v103_pipe_bypass.v` C10d/C10f。

### 8.9 原图路与处理路（差一整拍这件事）

- 延迟链本体：`pl_video_top.v:359-374`，`de_d/hs_d/vs_d/left_d/x_d/y_d/cx_d/cy_d[0:SB-1]`，
  `SB = 21`（`:355`）。`:366-367` 装入，`:369-371` 逐级移位。**控制与数据走同一条链**——这是全项目第一
  不变量（"门控与数据同拍"）的落地形式。
- 混合抽头：`:919-920` `.x(x_d[MIX_D]) .de(de_d[MIX_D]) .hs/vs(…[MIX_D])`；OSD 标签束一起提到 `MIX_D`
  （`:1001-1005`），`de_o` 是 `de_d[MIX_D]` 再打一拍（`:925`）。
- **原图路的延迟构成**（`:820-829`）：`raw_line_delay`（含 1 拍 RAM 读出）+ `orig_skid[0:14]`（`LEFT_TAIL =
  PROC_LAT = 15` 拍，`:817,826-849`）= **`PROC_LAT + 1`**，而链子本身只有 `PROC_LAT` 拍
  ⇒ **处理抽头比原图早一整拍**，对照显示必须按这条补偿。
- 历史错位 **#92**：`r59b` 只把 `x_sel` 提到 `MIX_D`，而 `x/y/de/hs/vs` 停在**第 11 级** ⇒ 屏上 `de` 比同拍
  像素**早 9 列**（`:913-914` 原文与凭据）；同类：`u_split` 曾用 `x_d[11]` ⇒ 判定比内容旧 9 列，被
  `sim/tb_v98_top_seam.v` 的 C-tap 钉住（`split_display.v:11`）。
- 环外地址补偿：`:725`（`BILIN_ROWS` 补偿）、`:741,743-748`（`x_d[2]/y_d[2]/de_d[2]`；第一版错接 `[3]`
  ⇒ k=4/5 全错，`sx` 站在第 2 级）。右窗提前量 `:276` `y_right_adv = y + pipe_off_rows + BILIN_ROWS`；
  `:277` 有 `>>1`；`:346` mapper 入口 `cy_r` 提前 `OFF_LINES`。
- `raw_line_delay`：**延 LINES 行 + 1 拍，列不偏**（`src/rtl/video/raw_line_delay.v:5-7`）。第一版实现把
  `line_cache` 串起来，"延 N 行又多 N 拍 ⇒ 列偏 N 格"，被 `tb_v100_raw_delay` 当场打掉（`:6-7`）——
  **模块级台架看不见这个错**，这是本项目"延迟必须按行环形"这条规矩的凭据来源。
  `DW = 17` 的理由（`:16-21`）：`oob` 标签必须与像素过**同一条环**，绕环只走等长 skid 会差
  (4 行, 1 列)，右沿最后一列被别的格子的越界位按黑（症状原文"上边缘有东西闪"）。
  `:38-42`：`LINES` **刻意不给默认值**（唯一合法出处是顶层 `RAW_LINES = u_pipe.OFF_LINES`）；17 位仍在
  RAMB36 的 18 位宽度模式内，**但要在 utilization 上核对**（LINES=4 ⇒ RLOG=3 ⇒ 8 行 ≈ 4 块 RAMB36，
  级联要 8 块）。
- 顶层例化：`u_raw #(.LINES(RAW_LINES), .W(2*IMG_W=1024), .DW(17))`（`:788-792`），
  `de/x/y` 取 `*_d[5]`（`:789-791`），输出 `raw_ring[16:0] = {oob_raw, pix_raw}` → `orig_skid[0]`（`:840-841`）。
  `raw_ring_v`（`de_out`）**无读者**。

### 8.10 分屏与接缝（`split_ctrl` + `seam_src` + `split_display`）

- 分工：`split_ctrl`（`:885-891`）算**接缝位置**（含自动扫描与跟随）、`seam_src`（`:904-909`）把接缝**换算到
  源图坐标**并提前若干拍算好、`split_display`（`:911-928`）做**逐像素二选一**。
- `split_ctrl` 参数：`DISP_W = 2*PANE_W = 1024`、`SRC_W = IMG_W = 512`、`TICK_BITS = 16`（`:885-886`）。
  输入：`pos_px = {2'd0, gp[9:0]}`（**只有 10 位**）、`auto_en = gp[10]`、`follow = gp[11]`、`swap = gp[12]`、
  `speed = SPLIT_SPEED`、`lo16/hi16 = SPLIT_LO16/hi`。输出 `split_eff`（接缝，源坐标）、
  `raw_on_left`、`shown_pct[11:0]`（OSD 取 `[7:0]`，`:1012`）。
- `SEAM_TAPS = MIX_D + 1 − 3 = 18`（`:902`）。`:899-901` 原文："不抄字面量"（#68）——接缝的提前量必须由
  混合深度导出，而不是各写一个数。**这就是"流水线深度只有一个真源"在分屏上的形式。**
- `split_display` 的输入全部从 `*_d[MIX_D]` 抽（`:919-920`），`angle_idx = angle[1:0]`（`:925`，给旋转标签格），
  `oob_l = oob_r = oob_out`（**同一位喂两口**，`:924`）。输出 `r/g/b` 只给 `u_osd`（`:1020`）。
- 10 位 pos 与 1024 列的关系：见 §13/§18 —— **`split pos` 在寄存器上只有 10 位，PS 侧夹到 1023 且必须明说夹了**。
- 跨域：19 位的 `split_ctl` 在 axi 域**每 ~1.3 ms 整字抄一次并发翻转**（`:859-875`，`sp_ref` 到
  `17'h1FFFF` 翻转 ⇒ 131072 个 axi 拍 = 1.31072 ms），再由 `snap_cross #(.W(19))` 打进像素域（`:876-880`）。
  `:858` 原文"每 ~1.3 ms 整字抄一次"。

### 8.11 OSD（`src/rtl/video/osd_overlay.v`，525 行）

**几何参数**（`:9-24`）：`X0=16`、`Y0=12`、`SCALE=3`、`CHAR_W=18`（注释 `5*3 + 3 gap`）、
`CHAR_H=21`（`7*3`）、`LINE_GAP=10`、`MAX_CHARS=32`、**`N_LINES=5`**、`OUT_W=1024`、`OUT_H=600`。
派生：`LINE_H = CHAR_H + LINE_GAP`（`:71`）、`BOX_W = MAX_CHARS*CHAR_W`（`:72`）、
`BOX_H = N_LINES*LINE_H`（`:73`）。
**字符发生器**：`reg [4:0] font [0:63][0:6]`（`:333`）——**5×7 点阵、64 个字形、硬编码逐行写入**
（`:342-…` 每个字形 7 条赋值语句；`:331` 原文警告"**索引 0..27 是历史插入序，不是字母序**，金表钉的就是
那一段"）。字符格阵列 `reg [7:0] chars [0:N_LINES*MAX_CHARS-1]`（`:180`），行定位用 task `at`（`:186`）。
**屏上没有小写**：`:187-189` 原文——"小写一律在 `put` 里折成大写。折算放在**写这一侧**而不是读那一侧：
读侧 `ch→gi→font→b_reg` 是**全设计最差路径的主体**，在这里折一次只多一句比较 + 一次减法，换来译码表少
17 个分支"。实现 `:193-195`：`if (u >= 8'h61 && u <= 8'h7A) u = u - 8'h20;`。
`:92` 另有一条位宽纪律："行号位宽必须跟着 `N_LINES` 走：写死 `[1:0]` 时加到第 5/6 行屏幕上永远取不到"。
数值显示的处理：`fps` 先夹到 99（`:129`，OSD 侧的十进制转换在 `putd3`），延迟显示用 `/10` 与 `%10` 拆位
（`:306`，`putd3(lt_h, (lt_rem / 8'd10), (lt_rem % 8'd10))`），`zoom_code` 用 4 级 case 译成档位文字
（`:147-158`，`:156` 原文"没点出来的那一支就是 4，省一格 case 深度"）。
输入束（顶层 `:999-1024`）：`x/y = *_d[MIX_D]`、`de = de_o`（**注意是 `de_o` 不是 `de_d[MIX_D]`**）、
`angle`、`fps=fps_q`、`stage_sel=sel_sync`、`threshold=th_sync`、`gamma_disp`、`zoom_code`、
`zoom_auto = zoom_run && !zman_pix && !zoom_fit_en`、`zoom_fit = zoom_fit_en | rot_forced`、`split_pct`、
`split_auto = gp[10]`、`lat_ms`、`lat_ok`、`src_eff = {fb_vis, owner_eth_pix}`、`mode`、`no_sig`、
`temp_disp`、`bg_pix = 16'h0`、`osd_en = ~oo2`（**反相**）。
输出 `r_osd/g_osd/b_osd` + `de_osd/hs_osd/vs_osd` **只喂 `u_dvi`**（`:1028-1029`）。
⚠ `:4` 的文件头说"同时走面板与 `u_dvi`"，但在本文件里**没有第二份负载**（`未找到` 第二个消费者）——
也就是说 **HDMI 看到的内容与"面板直驱"是同一份**，本工程只有 HDMI 一路物理输出。

### 8.12 延迟测量 `frame_latency`（lane24-29 的来源）

- 实例 `u_lat`（`pl_video_top.v:624-635`），跑在 **`axi_clk`** 域。测的是**同一次帧提交上的两个时间点之差**：
  `commit`（ETH 提交那一拍）与 `disp_sof_tgl`（显示帧首的翻转位，来自像素域 `sof_tog` `:607-611`），
  中间还有 `copy_start`/`copy_done` 用于分类"这时间花在拷贝还是在等窗口"。
- 六个字一组：`lq_c1/lq_c2/lq_tot/lq_max/lq_stat/lq_ms` → `dbg_lat`（`:642`）。live 口
  `lat_c1/c2/tot/max/lat_n/lat_clamp`（`:613-617`）**在顶层无读者**（`:640-641` 原文：留给台架 tb_v90）。
- **武装协议**：`lat_arm = (lm_lane == 5'd25)`（`system_top.v:236`）⇒ **指到 lane25 就把这一组五个字同时抄进
  快照**。`:232-234` 原文给理由（#59）："逐 lane 各读各的会读到不同轮，于是板级 11 组读数里 **4 组破坏了
  恒等式 `tot ≥ c1 + c2`**。读的顺序必须是 25→26→27→28→29，因为 25 既是'轮次/钳位位'也是武装位
  （`health_read.mjs` 的 want 列表就是这个顺序，改那里的时候记得一起看）"。
  域说明同段：`gpio_o` 由 axi 写更新、`frame_latency` 也在 axi 域 ⇒ **这不是跨域信号**。
- lane24 = `dbg_lat[5*32 +: 32]` = `q_ms = {14'd0, pair_ok, 本轮 sticky, ms[15:0]}`
  （`system_top.v:229-231` 原文："与 `q_tot` 同一轮的 ms —— 屏上 Latency 那一格的机器对照"）。
- 跨到像素域给 OSD：`lat_ms/lat_valid/lat_sticky/lat_tog` → `snap_cross #(.W(18), .HB_TO_MS(1000),
  .SLOW_MS(200))`（`pl_video_top.v:980-985`），心跳 `lat_hb_tog` **另起一个 FF**（`:975-979`，理由 `:971-974`）。
- **"钳制"发生在什么条件**：`lat_clamp` 位（lane25 的 `{n_meas, clamped}` 里那位）。本文**没有**独立验证
  `clamped` 的精确谓词（`未找到` 逐条展开），只知道它是"本轮读数被上限夹住"的旗标；引用时说
  "clamped 的具体条件要看 `frame_latency.v` 的 `lat_clamp` 赋值式"，不要凭 OSD 那一格猜。

### 8.13 TMDS 编码与串化（`src/rtl/hdmi/`）

**8b/10b 编码器 `tmds_encoder.v`（76 行）** —— 单通道，`output reg [9:0] dout`（`:11`），
即**编码器本身就是输出寄存器，不再额外打拍**；一个符号 = 1 个 `clk_pix` 周期。
1. 1→9 的 xor/xnor 选择是**算出来的，不是查表**：
   `:20` `wire [3:0] n1 = ones(din)`（`:13-18` 是内联 `function`，结构化展开成 LUT）；
   `:21` `wire use_xnor = (n1 > 4'd4) || (n1 == 4'd4 && din[0] == 1'b0);`
   ⇒ **1 多（>4）走 XNOR；正好 4 个 1 用 LSB `din[0]` 做 tie-break；<4 走 XOR**。
   `:25-36` 的 `always @(*)`：`q_m[0] = din[0]`（递归种子），XNOR 支 `q_m[i] = ~(q_m[i-1] ^ din[i])` 且
   `q_m[8] = 1'b0`；XOR 支 `q_m[i] = q_m[i-1] ^ din[i]` 且 `q_m[8] = 1'b1`。
   ⇒ **`q_m[8]` 就是 xor/xnor 标志位（1=XOR、0=XNOR）**，它不参与后续 1 计数（`:39` 只切 `q_m[7:0]`）。
2. DCS 平衡：`cnt` 是 `reg signed [5:0]`（`:38`，范围 −32…+31，**代码里没有任何饱和/钳位逻辑**，注释也未
   讨论溢出——引用时别说"计数器有保护"）。三条优先分支：
   - `:54-62` **第一优先**：`if (cnt == 0 || n1q == n0q)` ⇒ `dout[9] = ~q_m[8]`、`dout[8] = q_m[8]`、
     `dout[7:0] = q_m[8] ? q_m[7:0] : ~q_m[7:0]`；`cnt += q_m[8] ? (n1q-n0q) : (n0q-n1q)`。
   - `:63-67` **同向修正**：`else if ((cnt>0 && n1q>n0q) || (cnt<0 && n0q>n1q))` ⇒ `dout[9]=1`、
     `dout[7:0]=~q_m[7:0]`、`cnt += {2'b00,q_m[8],1'b0} + (n0q-n1q)`（**那个拼接就是 ±2 的修正项**）。
   - `:68-72` **反向**：`dout[9]=0`、`dout[7:0]=q_m[7:0]`、`cnt -= {2'b00,~q_m[8],1'b0} + …`。
   ⚠ 有符号算术口径（值得写进文档，因为它"看起来会算错"）：`cnt + (n0q - n1q)` 里 `n0q/n1q` 是 4 bit
   无符号，但整个表达式因 `cnt` 为 signed 而具有 signed 类型，操作数先扩展到 6 bit 再相减 ⇒ 负差值正确
   （括号**不构成** self-determined 上下文）。
3. 消隐期（`de == 0`）`:46-53`：`cnt` 清零，按 `{c1,c0}` 直接输出 4 条 ID 码（**硬编码字面量**）：
   `2'b00 → 10'b1101010100`（`:49`）、`2'b01 → 10'b0010101011`（`:50`）、`2'b10 → 10'b0101010100`（`:51`）、
   `2'b11 → 10'b1010101011`（`:52`）。⚠ `:49` 与 `:51` **只差最高两位**（`11…` vs `01…`），抄写时极易写成同一个。
   复位值 `dout <= 10'b1101010100`、`cnt <= 6'sd0`（`:44-45`），复位是**异步低有效**（`:42`）。

**串化器 `tmds_serializer.v`（92 行）—— 10:1 用两颗 OSERDESE2 级联，不是 8:1+2**：
`:2-3` 原文"10:1 OSERDESE2 cascade (UG471): `DATA_WIDTH=10` requires `DATA_RATE_OQ=DDR` /
Master D1-D8 + Slave D3/D4, Slave SHIFTOUT → Master SHIFTIN"。
- MASTER `:15-22`：`.DATA_RATE_OQ("DDR")`、`.DATA_RATE_TQ("SDR")`、`.DATA_WIDTH(10)`、
  `.SERDES_MODE("MASTER")`、`.TRISTATE_WIDTH(1)`、`.TBYTE_CTL("FALSE")`、`.TBYTE_SRC("FALSE")`；
  SLAVE `:53-60` **参数完全同档，只有 `SERDES_MODE` 不同**。
- 分工：MASTER `D1..D8 = din[0..7]`（`:33-40`）；SLAVE **只喂 `D3=din[8]`、`D4=din[9]`**（`:73-74`），
  其余 `D1/D2/D5..D8` 一律 `1'b0`（`:71-72,75-78`）。
- 级联环：`wire shift1, shift2;`（`:12`），SLAVE `.SHIFTOUT1/2`（`:64-65`）接 MASTER `.SHIFTIN1/2`
  （`:43-44`）；SLAVE 自己的 SHIFTIN 钉 `1'b0`（`:81-82`），MASTER 的 SHIFTOUT 悬空（`:26-27`）。
- 时钟配对：`:31-32,69-70` **`.CLK(clk_pix5x)`（250 MHz = FCLK）、`.CLKDIV(clk_pix)`（50 MHz）**，
  严格 5:1 且同 MMCM 同相位。算术（这就是"为什么是 5×"）：DDR 每个 FCLK 周期出 2 bit ⇒ 一个 10 bit 符号
  要 **5 个 FCLK 周期** ⇒ `FCLK = (10/2) × CLKDIV = 5 × CLKDIV`；线速率 50 MHz × 10 = **500 Mbps**。
- 三态整体旁路 ⇒ **输出常开**：`OCE = 1'b1`（`:41,:79`）、`T1..T4 = 1'b0`、`TCE = 1'b0`（`:50,:88`）、
  `TBYTEIN = 1'b0`，`TQ/TFB/TBYTEOUT/OFB` 全悬空（`:24,28-30,:62-67`）。
- 只有 MASTER 出脚：`.OQ(serq)`（`:25`），SLAVE 的 `.OQ()` 悬空（`:63`）。差分由
  `OBUFDS u_obuf (.I(serq), .O(data_p), .OB(data_n));`（`:91`）生成。复位 `RST = ~rst_n`（`:42,:80`，两颗同时）。
- `未找到`：`SERDESTODDR` 之类额外属性（检索式 `SERDESTODDR|(* .*_TO_DDR`）；也**没有任何关于 OSERDESE2
  需要 `SYSRESET`/`INIT` 的注释**（检索式 `SYSRESET|OSERDESE2.*INIT` 覆盖 `src/`、`report/`、`docs/`）
  ⇒ 若要引用那条约束，**必须另找 UG471/DS 原文并注明"仓库内无出处"**。

**顶层 `rgb2dvi.v`（53 行）**：`:21` 通道映射"DVI: **channel0=Blue+HS/VS, channel1=Green, channel2=Red**"。
3 个编码器并行同 `clk_pix` 域：`u_enc_b` 带 `.c0(hs) .c1(vs)`（`:22-25`），`u_enc_g`/`u_enc_r` 的
`.c0/.c1` 钉 `1'b0`（`:26-33`）⇒ **HS/VS 只随蓝通道走**，另两路消隐期恒输出 `2'b00` 那条 ID 码。
**串化器是四颗**（`:35-46,49-52`）：`u_ser0/1/2` 对应 data[0]/[1]/[2]，`u_ser_clk` 的 `din` 是
**常量 `10'b1111100000`**（=0x3E0，5 个 1 + 5 个 0，TMDS 时钟通道标准字）——**时钟通道没有编码器实例**。
⚠ `:48` 的注释写"constant **0x3FF** pattern = pixel clock"，**这句注释是错的**，以 `:51` 的代码为准。
上游复位已经过 MMCM 锁定门控（`pl_video_top.v:132` `rst_pix_n = sys_rst_n & locked`）。

**彩条与图卡**：`src/rtl/video/color_bar.v` 与 `src/rtl/video/test_card.v`。现役 TEST 模式用
`u_bar = test_card #(.H_ACTIVE(IMG_W), .V_ACTIVE(IMG_H))`（`pl_video_top.v:759-762`），输入是**源坐标**
`x=sx, y=sy`（不是显示坐标！）与 `de = de_d[2]`，输出 `bar0 → bar_d1 → bar_d2`（`:763-765`）后进 `pix_raw`
的图卡支（`:772`）。`test_card.v` 画的是**动画**：`:38` `RAD = Y/14 (≥12)`（球半径）、`:46-47` `AX/AY` 中心，
`:35-37` 原文"球半径必须小于每帧位移量的量级"，`:43-45`"先比较再取，避 12 bit 回绕"，
打包 `:198` `{r[7:3], g[7:2], b[7:3]}`。`color_bar.v` 在本链路里**未被 `pl_video_top` 例化**
（`grep -n color_bar src/rtl/top/pl_video_top.v` → 0 命中）。

重取：
```bash
grep -n "LATENCY\|OFF_LINES\|stage_sel" src/rtl/process/proc_pipeline.v
grep -n "font \[\|CHAR_H\|N_LINES" src/rtl/video/osd_overlay.v
grep -n "OSERDESE2\|DATA_WIDTH\|CLKDIV\|OBUFDS" src/rtl/hdmi/tmds_serializer.v
```

---

## 9. 流水线深度唯一真源与"门控与数据同拍"

这一节是本项目的**第一不变量**。任何回答"改一级流水会怎样"的问题都必须引用本节。

### 9.1 传播图（改一个数会带动哪些数）

```
proc_pipeline.v:22   LATENCY   = 15        ← 唯一真源（parameter，声明处原文："不许由外部覆盖"）
proc_pipeline.v:27   OFF_LINES = 4         ← 第二个真源
   │
   ├─ pl_video_top.v:835   PROC_LAT  = u_pipe.LATENCY            = 15
   ├─ pl_video_top.v:836   LEFT_TAIL = PROC_LAT                  = 15   （orig_skid / oob_skid 的级数）
   ├─ pl_video_top.v:354   MIX_D     = 3 + 1 + 1 + u_pipe.LATENCY = 20
   │        └ :352 注释：3 = 打拍，1 = addr_q，1 = BRAM 读出
   ├─ pl_video_top.v:355   SB        = (MIX_D > 16) ? MIX_D + 1 : 16 = 21   （延迟链数组宽度）
   ├─ pl_video_top.v:902   SEAM_TAPS = MIX_D + 1 − 3              = 18   （:899-901 原文"不抄字面量"，#68）
   ├─ pl_video_top.v:781   RAW_LINES = u_pipe.OFF_LINES            = 4   （raw_line_delay 的行数）
   └─ pl_video_top.v:276   y_right_adv = y + pipe_off_rows + BILIN_ROWS   （pipe_off_rows 由 u_pipe.off_rows 输出，:807）
```
另有两处**必须与 LATENCY 同改**但不能自动导出的账：`proc_pipeline.v:18` 的逐级拍数注释（1+1+3+3+3+1+3）、
`:21` 的"谁把 gamma 改成寄存读出，LATENCY 必须同时改 16"。

`OFF_LINES = 4` 的物理含义（`:23-26` 原文，逐句）：
> "内容偏移（以'喂进来的流的一行'为单位）：**四个窗口级各贡献 −1 行**，点运算级不贡献 ⇒ 整链固定
> −4 行、0 列。这不是笔误：行缓存式 3×3 滤波在收到第 y 行时才算得出第 y−1 行的窗口，因果性决定它必然
> 滞后一行。顶层能补：帧缓存是随机地址的，把右窗读坐标对应的**显示行**提前 OFF_LINES 行，链子
> 自己的滞后正好把它抵消（零 BRAM，见 pl_video_top 的 `cy_r`）。"

**把同一个数字硬编码在别处的地方**（改深度时必查，这是本项目的"耦合扫描"清单）：
`proc_pipeline.v:22`、`raw_line_delay.v:9`（`LINES` **有默认值 4**，而 `:38-40` 的注释口径是"只有一个合法出处
`u_pipe.OFF_LINES`、刻意不给猜出来的默认值"——**参数行与注释互相打脸**；RAM 块数账在 `:38`）、
`split_display.v:11`（注释里写 `+15`，那是**历史记录不是定义**）、`tb_v86_pipe_sel.v:8`（`LAT_EXPECT`）、
`proc_box_blur.v:26-31` 与 `proc_sharpen.v`/`proc_sobel.v`/`proc_morph.v` 的同形段。
自检脚本：`node src/host/pipe_len_check.mjs`（门禁第 21 项，§17）。

### 9.2 门控与数据同拍：三类必须并排读的抽头

| 类别 | 抽头 | 为什么是这个数 |
|---|---|---|
| 显示/混合 | `x_d/y_d/de_d/hs_d/vs_d[MIX_D=20]`（`pl_video_top.v:975-976`） | 内容与标签走同一条链（`:359-374`），MIX_D 由 LATENCY 导出 |
| 环外地址 | `x_d[2]/y_d[2]/de_d[2]`（`:741,743-748`） | `addr_q` 1 拍 + BRAM 1 拍 = 2；第一版错接 `[3]` ⇒ k=4/5 全错 |
| 各级算子坐标 | `xd[2]/xd[5]/xd[8]/xd[12]`（`proc_pipeline.v:98-101`） | 该级 de_in 之前**累积**拍数（`:74` 原文） |

`#92` 事故的完整形状（一次改动制造了三个判据）：`:913-914` 记录"只把 `x_sel` 提到 `MIX_D`，
`x/y/de/hs/vs` 停在第 11 级 ⇒ 屏上 `de` 比同拍像素**早 9 列**"；`split_display.v:11` 记录同类
"曾用 `x_d[11]` ⇒ 判定比内容旧 9 列，被 `tb_v98_top_seam` C-tap 钉住"。
**症状命名法**（值得原样传给下一个 AI）："边界偏了几列/几行"永远是"控制链与数据链不同深"，
不是"数据算错了"。

### 9.3 原图路 vs 处理路：一整拍的差

```
处理路： fb_bilin → u_pipe(15 拍) → pipe_dout_q(1 拍)            抽头 = de_d[MIX_D]
原图路： pix_raw → u_raw(raw_line_delay, 含 1 拍 RAM 读出)
              → orig_skid[0..14]（LEFT_TAIL = PROC_LAT = 15 拍）  抽头 = orig_skid[14]
```
⇒ 原图路总延迟 = `PROC_LAT + 1`，比处理抽头**多一拍**（`pl_video_top.v:820-829`）。
`oob_skid[0:14]` 与 `orig_skid` 并行同深（`:826-849`），`oob_out = oob_skid[14]`（`:849`）。
任何"屏上左右两半对齐/接缝对齐"的问题，先问这两条链的级数是否一致。

---

## 10. 约束逐条（每条的作用与理由）

### 10.1 加载状态：先问"这条今天到底进没进构建"

| 文件 | 状态 | 开关 / 出处 |
|---|---|---|
| `src/constraints/rk_zynq7020.xdc`（77 行） | **加载**（综合 + 实现都用） | `build/tcl/build_system_axigpio.tcl:31`；分步脚本 `build_pl_full.tcl:22` |
| `src/constraints/clock_groups_impl.xdc`（31 行） | **加载，但只在实现阶段生效** | `build_system_axigpio.tcl:36`（`add_files` + `set_property used_in_synthesis false`） |
| `src/constraints/r116_rgmii_input_window.xdc`（40 行） | **默认关** | 开关 `VP_R116_IO_WINDOW=1` 才加（`build_system_axigpio.tcl:58,63`） |
| `src/constraints/r119_hdmi_source_window.xdc`（52 行） | **默认关** | 开关 `VP_R119_TMDS_WINDOW`（`:76,81`） |
| `r114_io_async.xdc`、`r114_io_varianta_rise_only.xdc`、`r114_io_variantb_phy_delay.xdc`、`r115_io_window_candidate.xdc`、`r119b_hdmi_tp1_pinclk.xdc` | **禁用集**：出现在约束集里即判红 | `build/tcl/r124_tiers_probe.tcl:43-45` 的 `banned` 名单 |

⚠ **默认构建的时序数字是在"RGMII 输入不被检查"的前提下得到的**（`build_system_axigpio.tcl:44-64`）。
说"时序收敛"必须带上这句前提。

### 10.2 `rk_zynq7020.xdc` 逐条

| 行 | 内容 | 作用 / 为什么 |
|---|---|---|
| 2-3 | `CFGBVS VCCO`、`CONFIG_VOLTAGE 3.3` | 配置 bank 参考电平取 VCCO、3.3 V |
| 5 | `sys_clk` → **W17 LVCMOS33** | 50 MHz 晶振 |
| 6 | `create_clock -period 20.000 -name sys_clk` | 唯一的主钟声明；与 `clk_gen.v:17` 的 `CLKIN1_PERIOD(20.000)` 配对 |
| 8-11 | `key1_n` W18、`key2_n` V14、`led[0]` V15、`led[1]` V13 | LVCMOS33 |
| 12-19 | TMDS 8 脚 **IOSTANDARD TMDS_33** | p/n 必须同真差分对：W16+Y16 / AA17+AB17 / U17+V17 / U15+U16；对应 `OBUFDS`（`tmds_serializer.v:91`）与通道顺序（`rgb2dvi.v:21`） |
| 20-25 | `eth_rxc` Y19、`eth_rx_ctl` V19、`eth_rxd[0..3]` W20/W21/U20/V20 | RGMII 收口（**这 5 个是 §5.7 债账里被 `check_timing` 点名的 5 个口**） |
| 26-31 | `eth_tx_clk` AB22、`eth_tx_ctl` AB21、`eth_txd[0..3]` T21/U21/AA22/AA21 | RGMII 发口 |
| 32-33 | `eth_mdc` AB20、`eth_mdio` AB19 | 引脚存在但功能不用（§2） |
| 34 | `eth_rst_n` Y21 | **输出**（决定了 `:55` 必须是 `-to`） |
| 36 | `create_clock -period 8.000 -name eth_rxc` | PHY 恢复钟 125 MHz |
| 50 | `set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]` | 见 §11.3 完整推导 |
| 55 | `set_false_path -to [get_ports eth_rst_n]` | 原来是 `-from`，每次都报 `CRITICAL WARNING [Constraints 18-513] … contains no valid startpoints`，是**空约束**，已删（`:51-54` 原文） |
| 56-58 | `set_false_path -to eth_tx_clk / eth_tx_ctl / eth_txd[*]` | 这三组是**输出且无对应 create_clock**（TX 钟沿用 RX 钟），不做窗分析 |
| 59-60 | `set_false_path -from key1_n / key2_n` | 异步按键，后面 `key_debounce` 自己打拍 |
| 77 | `BITSTREAM.GENERAL.COMPRESS TRUE` | 压缩位流（下载时间与 Flash 占用都受影响） |
| 62-75 | 一段注释，**不再是约束** | 解释为什么 `set_clock_groups` 不写在主 XDC（见 §10.3） |

`:43-45` 有一条**通用教训**（原文）："⚠ 只写 `eth_rxc` 一个对象：本文件下面那段旧账（51-56 行）证明，
把 `get_clocks` **取不到的名字**（例如 PS7 IP 自己 create 的 `clk_fpga_0`）并进同一条命令，会让**整条命令
空转**、连带把 `eth_rxc`/`sys_clk` 那几组一起废掉，而且现场只留下一句 warning。"

### 10.3 `clock_groups_impl.xdc`（三组异步）

```tcl
set_clock_groups -asynchronous \
  -group [get_clocks eth_rxc] \
  -group [get_clocks -quiet clk_fpga_0] \
  -group [get_clocks -include_generated_clocks sys_clk]
```
逐条理由（文件头原文，`:3-8` 与 `:19-26`）：
1. **为什么要拆文件**：`clk_fpga_0` 由 PS7 IP 自己的 XDC 创建（`FCLKCLK[0]`），**综合阶段还不存在**；
   `-quiet` 只能压住 `get_clocks` 的报错、压不住命令本身 ⇒ 每个 run 都吃一条
   `CRITICAL WARNING [Vivado 12-4739] set_clock_groups: No valid object(s) found for
   '-group [get_clocks -quiet clk_fpga_0]'`，而且**整条命令不生效**（`eth_rxc`/`sys_clk` 两组一起废掉）。
   XDC 里又不允许写控制流（`if` 会报 `[Designutils 20-1307] Command 'if' is not supported in the xdc
   constraint file`）⇒ 唯一正规解法是"按时机分文件"。
   ⇒ **拆分不改变任何时序数字**（综合阶段这条约束在拆分前也是失败的，等于不存在）。
2. **`-include_generated_clocks` 不能少**：否则 `clk_pix` 被当独立钟与 `eth_rxc` 做 setup ⇒
   历史上 **WNS ≈ −6.7 的假违例**（`:14-17`，issues #18）。它抓的是工具自动推导的
   `clkout0_1`(50 M)/`clkout1_1`(250 M)/`clkout2`(200 M)。
3. **`clk_pix` 与 `clk_pix5x` 有意同组**（`:25-26` 原文）："同 MMCM、5:1、0° 相位，让 TMDS 并串转换按
   同步路径做 setup 分析；**声明成异步反而会漏检**"。
4. `:19-23` 逐条列出"跨域数据由结构保证，不靠时序分析"：C1 `dc_fifo`、C2 翻转+3FF、C10 消隐窗 3+3、
   C6 控制字 3FF。

### 10.4 故意**没有**的约束（每一条都是决定，不是遗漏）

| 没写什么 | 为什么 | 债账出处 |
|---|---|---|
| `eth_rxd/rx_ctl` 的 `set_input_delay` | **缺的是"有出处的窗"，不是窗本身**。绑上窗之后 hold 与 setup 在 tap 0…31 全范围内都关不掉（§11.5），于是先用候选件 + 开关，默认不加载 | `r116_rgmii_input_window.xdc:32-35`、`report/timing/debt_ledger.md §2`、`build/check_timing_verbose.rpt` §5（`:57-61` 点名 5 个口，级别 **HIGH**） |
| TMDS 的 `set_output_delay` | **接收端 / HDMI 规范的窗口数值在本仓没有出处**，写进去等于**假判据**；`:37-40` 另加一句：LED 是 LVCMOS33 直驱、HDMI 连接器引脚表里没有这类信号 ⇒ 没有可引用的对外窗 | `r116_rgmii_input_window.xdc:37-40`、`r119_hdmi_source_window.xdc:45-47`、`debt_ledger.md §2` |
| `create_generated_clock` | 一个都没有——派生钟完全交给工具推导 | `grep -rn create_generated_clock src/constraints/` → 0 命中 |
| `set_max_delay` / `set_multicycle_path` / `set_bus_skew` | 跨域一律用结构（FIFO / 翻转 / 3FF）而不是时序约束 | `clock_groups_impl.xdc:19-23`；现役两份 XDC grep 0 命中。⚠ 禁用集 `r114_io_async.xdc:57-63` 有**四条真 `set_max_delay -datapath_only`**，是一条未采纳的替代路线（`:50-51` 引 UG949 给理由，`:64` 自我交代 `set_bus_skew` 未写） |
| PHY 寄存器读写（MDIO 时序机） | strap 已固定工作模式；写这条要另起位时序机 | `system_top.v:113-117` |

### 10.5 `check_timing` 的实际读数

`build/check_timing_verbose.rpt`：
- §5 `checking no_input_delay (7)`：**5 个输入口没有 input delay（HIGH）** —— 逐字列出
  `eth_rx_ctl`、`eth_rxd[0]`、`eth_rxd[1]`、`eth_rxd[2]`、`eth_rxd[3]`（`:57-61`）。
  另有 **2 个**输入口无 input delay 但被 false path 覆盖（**MEDIUM**）：`key1_n`、`key2_n`。
- §4 `checking unconstrained_internal_endpoints (0)`：0 个引脚未被最大延迟约束。
⇒ **"约束真的作用在对象上"这句话在本项目有一个明确的例外**：RGMII 那 5 个口。引用"全约束满足"
（routed 报告 `:154` 的 `All user specified timing constraints are met.`，`:155` 是空行）时必须带上这条口径。

---

## 11. 时序优化：做过什么、量到什么、为什么

### 11.1 策略与 directive：实测"没有收益"

`build/sweep_summary.txt`（2026-09-22 R06 取证，逐字）：

| strategy | WNS | WHS | fail_endpoints | all_constraints_met | note |
|---|---|---|---|---|---|
| `Performance_Explore` | **0.499** | **0.060** | 0/21253 | YES | 与"未指定策略"的 R05 基线**逐位相同** ⇒ 该档无收益 |
| `Performance_ExplorePostRoutePhysOpt` | NOT_RUN | — | — | — | 脚本在该轮之前因**非法选项**退出 |
| `Performance_ExploreWithRemap` / `ExtraTimingOpt` / `BalanceSLRs` | NOT_RUN | — | — | — | （xc7z020 无 SLR，最后一项本就意义有限） |

三条必须一起说的限定（文件头原文）：
1. 扫描只完成一个策略就中断——`report_timing_summary` 的 **`-check_summary_only` 在 Vivado 2025.2.1 不是
   合法选项**，命令报错且未被 `catch` ⇒ 脚本退出。**所以这份文件是部分结果，不足以支撑"所有策略都无收益"**。
2. "这里只证明「`Performance_Explore` 这一档 = 未指定策略的结果」，**不对 Vivado 的默认策略名做任何断言**
   （工程里没留下该字符串，且报告未记录）"。
3. 支撑当时决策（转去改 RTL，即 V7.4）的实际证据只有两条：①这一档 = 基线；②最差 10 条 `eth_rxc` 路径
   **同构且逻辑深度 11 级**。
⇒ **结论：本工程不靠换策略救时序，靠改 RTL。** 引用时不要说"试过所有策略都不行"。

### 11.2 真正换来时序的六次 RTL 改写（每次都带凭据）

| # | 改动 | 病因（症状/读数） | 出处 |
|---|---|---|---|
| 1 | 把 `cov`/`pend` 从一条三操作数 32 位加法改成**两个饱和累加器 + EOF 拍补账** | 那条加法占了本 125 MHz 组**十条最差路径全部**（当时 WNS +0.499） | `frame_reasm.v:5-7,50-69` |
| 2 | 帧间隔从"两个 32 位 ms 计相减"改成**直接数 tick** | 减法是全设计**最差 setup 路径**（ISSUES #95） | `link_monitor.v:46-51` |
| 3 | `wr_full` 从 `wgray_n` 组合链改成用**当前** `wgray` 比较 | 原来把"14 位加法 + 二进制转格雷 + 比较"整条锥体挂在 `wr_en → ENARDEN` 上（r87 最差路径 **8 级逻辑、0.152 ns**）；代价：可用深度 `DEPTH-1 → DEPTH`，由 tb 钉住 | `dc_fifo.v:40-44,47` |
| 4 | 行覆盖位图拆成 **5 个 64 位 bank + 5 选 1 mux** | 一条大比较器扇入 `fo=316`，最后一级跳吃掉 1.980/6.879 ns，route 81.2 % | `frame_reasm.v:76-80,91-96` |
| 5 | 所有运行时**除法换成"乘 elaborate 期倒数常数 + 定长移位"** | #58：组合除法器把最差路径拉到 **−5.014 ns** | `zoom_fit.v:26-30,35-36`；`zoom_ctrl.v:57-62` |
| 6 | 校验和等宽累加**拆拍** | `icmp_tx.v:274-276`：10 项一拍 ⇒ **5 级 CARRY4、0.741 ns**；改成 5 拍各加 5 项 | `icmp_tx.v:272-292`；`udp_tx.v:234-249` |
| 7 | 显示侧小写折算**从读侧挪到写侧** | 读侧 `ch→gi→font→b_reg` 是全设计最差路径主体；挪过去换来译码表少 17 个分支 | `osd_overlay.v:187-189` |
| 8 | 非 2 幂深度帧缓存**拆成 32768 + 8192 两块** | 单块会被向上填到 `2^16` ⇒ 128 块 RAMB36（全片 140）；拆后实测 80 | `frame_buffer_w64.v:4-7,23-35` |
| 9 | 打包器数组**显式 `ram_style="distributed"` + 存储写独占无复位 always 块** | `Synth 8-7186` 拒绝推断成 RAM ⇒ 512×64bit 退化成 **32904 个 FDRE**（实测对照 FF=32904/LUTRAM=0 vs FF=85/LUTRAM=864）；另一版 `FW=11` 直接 DRC `UTLZ-1`（占整机 Slice Register 94 %） | `axi_frame_saver64.v:10-13,48-50,104-107`；`sync_fifo.v:2-4`（同族：大深度 icmp_fifo 落寄存器堆导致 `eth_rxc@125 MHz` 域 WNS 为负）；`proc_morph.v:37-40` |
| 10 | IDDR 与 fabric **同吃一只 BUFG**（放弃 BUFIO 采样） | 两棵钟树 SCD 3.171 vs DCD 4.854 差 1.616 ns 而数据路径只 1.855 ns ⇒ 工具每次布线垫随机量，WHS 在 ±1 ps 掷硬币（r62 +0.001 / r63b +0.052） | `rgmii_rx.v:3-5,12-20`；`rk_zynq7020.xdc:37-49` |

**一条失败并被回滚的优化（必须留在文档里，否则下一个 AI 会推荐它）**：
`dc_fifo.v:37-39` 记 `#105 第一刀已回滚`——给 `wr_full` 加 `max_fanout=12` 之后 WNS 从 −0.062 掉到
−0.192、失败端点 28→34（注释点名那一轮的门禁件与 `build/timing_summary.rpt`；轮次中间件按本仓清理规则
**盘上已无**，同族现存件如 `build/gates_r62.txt`），结论原文
"**扇出不是瓶颈**"。

### 11.3 `set_clock_uncertainty -hold 0.800`：一条"方向与放松判据相反"的约束

完整推理链（`rk_zynq7020.xdc:37-49`，逐句可引）：
1. 机制：起点 IDDR 走 BUFIO（SCD 3.171 ns），终点 fabric FF 走 BUFG（DCD 4.854 ns）⇒ 两棵钟树差
   **1.616 ns**，而那条数据路径只有 **1.855 ns**（预算 8.000 ns）⇒ 工具**垫得出来**，但每次布线垫多少是随机的：
   r62 只剩 `WHS +0.001`、r63b 是 `+0.052` —— 同一份 RTL 的两个数是"掷硬币"的直接证据。
2. 做法：**给 hold 加 0.5 → 0.8 ns 的要求**（不是放松），逼工具把余量做成设计值。
   `:41-42` 原文："这一行方向与'放松判据'相反……（Setup 不受影响，`-hold` 的不确定性不参与 setup 检查；
   数据路径还有 6 ns 的 setup 余量，垫得起）"。
3. 加严到 0.8 的过程（`:47`）：r79 试验（2026-09-27）"0.5 那一档工具只做到 WHS +0.051（<0.4 的自定验收）
   ⇒ 再加严到 0.8"。
4. ⚠⚠ **`WHS ≥ 0.4` 是这条实验自己给自己定的验收线，不是发布门禁。** 发布门禁第 3 条是
   `WHS >= 0`（`build/gates.sh:199`），本设计 routed 实际 WHS = **0.052**。**别拿 0.4 判构建红**
   （这是上一版里出现过的危险误述，特此钉死）。
5. 退路（`:48-49` 原文）："若这一版关不住时序（出现失败端点），就带着两个数字**退回 0.500**，并把
   '工具在这个布局下垫不到 0.4'记成 #46 的实测结论，**而不是悄悄把验收改掉**"。

### 11.4 被放弃的"5× 快时钟"读口方案（`fb_rd5x` + `tap_sched` 留档）

`src/rtl/process/bilin/fb_rd5x.v:2-8` 与 `tap_sched.v:9-11,43-47` 记录了两个数：
- "右窗 4 抽头 + 左窗 1 字恰好占满 ⇒ **不新增任何 BRAM**；⚠ 不许在同一组阵列上再加一个逻辑读口：
  实测把帧缓存从 80 块 RAMB36 **顶到 160 块，全片才 140**"（`tap_sched.v:9-10`）。
- "**快域做 `base+ROWW` 加法再进 5:1 mux** 实测需约 **5.3 ns（−1.277 ns / 1400 个失败端点）** ⇒ 整条读口
  判红"，所以纪律是"四抽头字号 + 左窗字号**全在慢域算好打一拍**，快域只做一次 5 选 1 mux"
  （`tap_sched.v:43-47`、`fb_rd5x.v:38-47`）。
⇒ 现役 `fb_bilin` 用"**一个源像素吃满 4 个 50 MHz 拍**"换掉了这套东西
（`fb_bilin.v:4-5,39-40`，见 §8.7）。回答"为什么不用快时钟多留读带宽"应当引这两个实测数。

### 11.5 IDELAY tap 扫描：一次"只读实验"和它的极限

`system_top.v:162-171`（原文要点，全部来自**已布线 DCP 上的只读 `set_property`**，
件 `build/evidence/r115_window/probe3_console.txt`）：
- 窗 = `r116_rgmii_input_window.xdc:32-35`（RTL8211F RXDLY 开着 ⇒ 数据沿落在它自己的捕获沿前
  **[1.2, 2.8] ns**）；
- `IDELAY_VALUE` 从 0 扫到 31：**hold −2.822 → −0.870（+63 ps/拍）**、**setup +2.005 → −0.846（−92 ps/拍）**
  ⇒ 两条曲线的**交点在 tap 31**（用 0.155 ns/拍的斜率差解出 31.1），也就是 `min(hold, setup)` 的最大值；
  tap 26 的 min 是 −1.185，tap 31 是 −0.870 ⇒ **顶层取 31**。
- ⚠ 极限陈述（`:169-171` 原文）："这一族**在 0…31 全范围内都关不掉**：hold 查慢角（钟网络 5.008）、
  setup 查快角（1.597），钟网络的角间差 **3.4 ns 远大于数据路径的 0.47 ns** ⇒ 需要 `D_slow/D_fast ≥ 1.45`
  而 IDELAY 主导的路径只有 **1.15**。这是'极限判据'的内容，**不是'再找个点'**。"
- ⚠ **tap 31 是"报告里最好"，不是"硅片最好"**（`report/timing/rgmii_window_model.md:376-377,393,406`）。
- 斜率四个口径互不一致（78 / 156 / ~63 / ~88 ps/tap），见 §7.1 —— 引用前先说用哪个。

### 11.6 观测面/统计侧的时序纪律（少见的"为可数性做的设计"）

- **饱和不回卷**：`stall_ms` 饱和 `0xFFFF`（`link_monitor.v:151-153`）、`gap_cnt` 数到 `0x1FFFF` 钉住
  （`:50-51,87`）、16 bit 健康字段饱和（`:88-92`）。理由原文："回卷到 0 会被读成'没问题'"。
- **观测位必须与判决同拍**：`why_ps` 与 `owner_eth` 写在同一决定点（`src_arb.v:68-73`，#174）。
- **计数器的位宽是契约**：`DW = $clog2(TC+1)`（`link_monitor.v:41`）而不是写死 `[15:0]`（`Synth 8-6014` 事故）；
  `dbg_src` 两端必须同宽（`system_top.v:221-227`，`Synth 8-689` 事故）。
- **判据"永不红"就是没有判据**：本项目把这类句子挑出来重写过多次，例如 `shown_rate.v:41`
  `shown_rate.v:41` 给"一行一个谓词"的理由是那支反例脚本能一行 sed 掉它，脚本在 `build/sim/mut_control.sh`；
  `ddr_bank_commit.v:4-5` "抄的那份永远不会因真代码改错而变红"。

---

## 12. 实现后的真实读数（照抄原文，未四舍五入）

来源目录：`vivado_system/zynq_video_sys.runs/impl_1/`。

### 12.1 时序（`system_top_timing_summary_routed.rpt`，routed，本文写作时 1316099 B / 2026-10-05 18:14）

| 口径 | 值 | 行 |
|---|---|---|
| Design（WNS/TNS/失败端点/总端点 · WHS/THS/失败/总 · WPWS/TPWS/失败/总） | **0.739** / 0.000 / **0** / 51135 · **0.052** / 0.000 / **0** / 51135 · 0.264 / 0.000 / 0 / 12634 | `:149-152` |
| 判定行 | `All user specified timing constraints are met.` | `:154`（`:155` 是空行） |
| Clock Summary | `clk_fpga_0` 10.000、`eth_rxc` 8.000、`sys_clk` 20.000、`clkfbout`/`clkfbout_1` 20.000、`clkout0_1` 20.000（50 MHz）、`clkout1_1` 4.000（250）、`clkout2` 5.000（200） | `:159-168` |
| 逐钟 intra | `clk_fpga_0` WNS 1.850 / WHS 0.053（15721 ep）；`eth_rxc` **0.739 / 0.052**（4835）；`sys_clk` 14.876 / 0.222（323）；`clkout0_1` 3.630 / 0.059（**30179** ep）；`clkout1_1` 仅 WPWS 2.408（10）；`clkout2` 仅 WPWS 0.264（3） | `:181-187` |
| inter | `clkout0_1 → sys_clk` 14.757 / 0.165（19 ep）；`sys_clk → clkout0_1` 3.695 / 0.200（231 ep） | `:198-199` |
| User Ignored | **10 条**跨组（`eth_rxc` / `sys_clk` / `clk_fpga_0` 双向 / →`clkout0_1` / `(none)`→`sys_clk` …） | 表体 `:218-227`（`:217` 是分隔线，数进去就成 11 了） |

### 12.2 资源（`system_top_utilization_placed.rpt`，**placed** 版；目录里只有这一份 utilization）

| 项 | Used | Available | Util % | 行 |
|---|---|---|---|---|
| **Slice LUTs** | **14154** | 53200 | **26.61** | `:35`（`:34` 是表头分隔线） |
| LUT as Logic | 9969 | 53200 | 18.74 | `:36` |
| LUT as Memory | 4185 | 17400 | 24.05 | `:37` |
| └ as Distributed RAM | 4044 | — | — | `:38` |
| └ as Shift Register | 141 | — | — | `:39` |
| **Slice Registers** | **8188** | 106400 | **7.70** | `:40`（Flip Flop 8188 / Latch **0** `:41-42`） |
| F7 / F8 Muxes | 1164 / 85 | 26600 / 13300 | 4.38 / 0.64 | `:43-44` |
| Unique Control Sets | 335 | 13300 | 2.52 | `:45` |
| **Block RAM Tile** | **95.5** | 140 | **68.21** | `:106`（RAMB36/FIFO 93 `:107`、RAMB18 5 `:109`） |
| **DSPs** | **19** | 220 | **8.64** | `:121`（全部 `DSP48E1` `:122`） |
| IDELAYCTRL | 1 | 4 | 25.00 | `:141` |
| IDELAYE2 | 5 | 200 | 2.50 | `:145-146`（`IFF_IDDR_Register 5` `:148`、`OUTFF_ODDR_Register 5` `:150`） |
| BUFGCTRL | 8 | 32 | 25.00 | `:161` |
| **BUFIO** | **0** | 16 | **0.00** | `:162` ← §11.2 第 10 条改动的直接证据 |
| **MMCME2_ADV** | **2** | 4 | 50.00 | `:163` |
| PLLE2_ADV | 0 | 4 | 0.00 | `:164` |

（IO 汇总里 `ODDR 5`、`IDDR 5`、`IDELAYE2 5`、`IDELAYCTRL 1`，`:218-224`；
`I/O 27 / 200 = 13.50 %` 见 power 报告 `:69`。）

### 12.3 功耗（`system_top_power_routed.rpt`）

| 项 | 值 (W) | 行 |
|---|---|---|
| **Total On-Chip Power** | **2.391** | `:33` |
| Device Static | 0.178 | `:37`（同值在 `:70`） |
| Signals | 0.054（20734 nets） | `:64` |
| Block RAM | 0.174 | `:65` |
| MMCM | 0.212（2 个） | `:66` |
| DSPs | 0.008 | `:67` |
| I/O | 0.156 | `:68` |
| **PS7** | **1.533** | `:69`（**总功耗的 64 % 来自 PS**） |
| Register / F7-F8 / LUT-SR / Others | <0.001 / <0.001 / <0.001 / 0.000 | `:60-63` |

⚠ **这份读数的口径**：它是 Vivado 的**估算**（默认翻转率 + 无激励活动），不是量到的电流。
文档里凡是"功耗"都指这份文件；要说"板上电流"需要外部测量（`未找到` 任何板级电流读数）。

### 12.4 布线与规则检查

- `system_top_route_status.rpt`：逻辑网线 **32330**、不需布线 11448（内部 10725 / **无负载 723**）、
  可布线 **20882**、**全部布完 20882**、**布线错误网线 0**。
- `system_top_drc_opted.rpt` / `system_top_drc_routed.rpt`：`Checks found: 97`，**无 CRITICAL**
  （`grep -c CRITICAL` → 0）；两条 `CHECK-3 Report rule limit reached`（`REQP-1839`、`REQP-1840`
  各数到 20 条就停）与 `DPIP-1 Input pipelining 26`。
  ⚠ 所以"0 violations"这句话**不成立**——成立的是"0 critical warning + 门禁只看 CRITICAL"
  （`build/gates.sh:98` 的判据是 `grep -ac "CRITICAL WARNING" "$M"`）。
- `system_top_methodology_drc_routed.rpt`：`Checks found: 446`，`DPIR-1 Asynchronous driver check 2` 等
  全是 **Warning** 级（门禁第 4 项要 `CRITICAL WARNING` 计数 = 0，`build/gates.sh:205`）。
- `grep -n "VIOLATION" system_top_drc_routed.rpt` → 0 命中（正向对照：同一次 `grep -n "Checks found"` 命中
  `:27`）⇒ 本报告里没有 VIOLATION 段落。

### 12.5 构建耗时：三处口径互不一致，引用前现读

"约 20 分钟"（`build/README.md:89`）、"25 分钟"（`build/gates.sh:256` 注释）、
"约 40 分钟一轮完整构建"（`src/host/card_preview.mjs:5`）。
**日志里没有整轮 elapsed 行**（检索式 `grep -rn "elapsed" build/ | grep -v "Time (s)"` 只命中工具单步行，
如 `build/r106_critpath_console.txt:59,65`）⇒ 要准确数字就读 run 的 `STATS.ELAPSED`：
```tcl
puts [get_property STATS.ELAPSED [get_runs impl_1]]
```

重取全部读数：
```bash
sed -n '149,152p;155p;159,168p' vivado_system/zynq_video_sys.runs/impl_1/system_top_timing_summary_routed.rpt
sed -n '34,45p;106,110p;121,122p;141,164p' vivado_system/zynq_video_sys.runs/impl_1/system_top_utilization_placed.rpt
grep -n "Total On-Chip\|Static\|PS7" vivado_system/zynq_video_sys.runs/impl_1/system_top_power_routed.rpt
```

---

## 13. 寄存器与观测面完整位表（最容易被引用错的一节）

### 13.1 三个 AXI GPIO 从设备

| 从设备 | 基址 | 位宽/通道 | 顶层信号 | 校验 |
|---|---|---|---|---|
| `axi_gpio_0` | `0x4120_0000` | 32b 全输出 | `GPIO_0_tri_o` → `gpio_o` | `assign_bd_address` + 构建期回读比对（`build/tcl/build_system_axigpio.tcl:121-126,243-274`，不符 `exit 1`） |
| `axi_gpio_1` | `0x4121_0000` | 32b **全输入** | `GPIO_1_tri_i` ← `gpio1_i`（lane mux 的结果） | 同上 `:131-136` |
| `axi_gpio_2` | `0x4122_0000`（ch2 = +`0x08`） | dual 32 + 32 输出 | `GPIO_2_tri_o` → `gpio_cfg1_o`、`GPIO_3_tri_o` → `gpio_cfg2_o` | 同上 `:147-155` |

⚠ **`xparameters.h` 里没有这些基址**（BSP 不重新生成）——固件里硬编码，`src/ps/main.c:71-73` 明说为什么。
⚠ `system_top.v:47-51` 的注释解释了为什么 `cfg1`/`cfg2` 的剩余位**故意不接**：
"地址与通道布局一次定好，后面两步就不用再动 BD（**动一次 BD = 全套门禁重来**）"。

### 13.2 `gpio_o[31:0]`（控制 + lane 选择共用一个整字）

| 位 | 含义 | RTL 解码 | 固件拼字 |
|---|---|---|---|
| `[4:0]` | **保留恒写 0**（V7 五位效果使能随 #66 退役） | `system_top.v:262-263` 原文 | `main.c:211-213` |
| `[15:8]` | `threshold` | `:264` | `main.c:214` |
| `[16]` | `src_sel`（PS/SD 片源开关） | `:264` | `main.c:214` |
| `[17]` | `zoom_en` | `:280` | `main.c:215` |
| `[18]` | **`ps_publish` 翻转位**（不是电平） | `:288` | `main.c:215`（`PUBLISH_BIT 18` `:51`） |
| `[19]` | `bilin_en` | `:286` | `main.c:216`（`BILIN_BIT 19` `:52`） |
| `[20]` | `osd_off` —— **反相，1 = 关掉 OSD** | `:287` | `main.c:217`（`cur_osd ? 0 : 1`） |
| `[21]` | 保留 | — | — |
| `[22]` | `mode_ovr_tog` 翻转位 | `:293` | `main.c:218`（`MODE_TOG_BIT 22`） |
| `[24:23]` | `mode` 码：`00` 自动 / `01` ETH / `11` SD / `10` TEST | `:293` | `main.c:218`、编码表 `:65-68` |
| `[25]` | 保留 | — | — |
| `[26]` | `gapclr_sel`（把帧间隔统计归零） | `:203` | **固件从不写**，只由上位机经 JTAG 写（`health_read.mjs:44-45,271-278`） |
| `[31:27]` | **健康 lane 号** | `:219` `wire [4:0] lm_lane = gpio_o[31:27];` | 固件也从不写 |

**位序三处同源**：RTL 解码 `system_top.v:262-293` + 固件拼字 `main.c:214-218` + 表头注释 `main.c:4-15`。
**这是 ABI**：只准往高位加，不许重排（`pl_video_top.v:1104` 里 `status` 的注释给了理由：
"不重排，JTAG 侧的读法就不会错位"）。

### 13.3 `gpio_cfg1_o[31:0]`（效果九位 + 几何 19 位）

| 位 | 含义 | 出处 |
|---|---|---|
| `[8:0]` | `stage_sel` 九位效果选择（**唯一定义** `proc_pipeline.v:5,31`） | `system_top.v:264`；固件抄表 `main.c:110-118,223` |
| `[9]` | `rot_auto` | `main.c:155`；`system_top.v:274-275` 拼进 `split_ctl` |
| `[12:10]` | `rot_speed`（0-7 度/帧） | `main.c:156-157` |
| `[22:13]` | `split pos`（**只有 10 位而屏宽 1024**） | `main.c:123-124,165-169` |
| `[23]` | `split auto` | `main.c:137` |
| `[24]` | `split follow` | `main.c:138` |
| `[25]` | `split swap` | `main.c:139` |
| `[28:26]` | `zoom_sel` 档号（0-7，八档表见 §8.6） | `system_top.v:268`；`main.c:187-189,224` |
| `[29]` | `zoom_manual` | `system_top.v:268`；`main.c:224` |
| `[30]` | `marker_off`（蓝线关） | `main.c:140` |
| `[31]` | `zoom_fit` | `main.c:158` |

拼接顺序（`system_top.v:274-275`，MSB→LSB，共 19 bit）：
```verilog
.split_ctl({gpio_cfg1_o[31], gpio_cfg1_o[12:10], gpio_cfg1_o[9], gpio_cfg1_o[30],
            gpio_cfg1_o[25:23], gpio_cfg1_o[22:13]})
```
`system_top.v:265-267` 有一条**踩过的坑**（原文）："⚠ 别写成 `gpio_cfg2_o`：那是 PS 侧 +0x08 的 gamma 窗口
（**命名差一位是这里的坑**）"。

⚠ **`split pos` 只有 10 位** ⇒ PS 侧必须夹到 1023，**而且必须回显"夹了"**（`main.c:125-136,165-169`）。
回答"能不能用 `split px 1500`"的正确答案是：会被夹，且固件明说夹了。

### 13.4 `gpio_cfg2_o[31:0]`（gamma 表 + 温度）

| 位 | 含义 | 出处 |
|---|---|---|
| `[31]` | `GM_EN`（gamma 使能） | `main.c:97` |
| `[30]` | `GM_WR` —— **翻转位，不是电平** | `main.c:98` + 注释 `:80` |
| `[29:22]` | `GM_DATA`（表值） | `main.c:99` |
| `[21:14]` | `GM_IDX`（表下标 0-255） | `main.c:100` |
| `[13:8]` | `GM_DISP` = γ×10（**只给 OSD 显示用**） | `main.c:101-102` |
| `[7:0]` | 温度，**两位十进制 BCD** | `main.c:103-106` |

整字从影子 `gm_w` 写回（`main.c:288-290`），**禁止读-改-写**（`:94-95`，#55 的坑）。
为什么温度在 PS 侧算：`main.c:84-93`——WNS 路径 `u_pipe/xd_reg → u_osd/g_reg` 有 **27 级**，
把除法/换算塞进像素域会吃掉当时全部的时序余量。

### 13.5 lane 读法（**整字写 ⇒ 必须先读回**）

`[31:27]` 与其余位共享同一个 32bit 寄存器口，所以**必须**：
```python
keep = v & 0x07FFFFFF          # 清掉 lane 号
keep |= n << 27                # 或上目标 lane
mwr GPIO_0 keep                # 写
after 20                       # 20 ms 稳定（唯一判据就是这段纯延时）
mrd GPIO_1                     # 读
# 用完原值写回 + con
```
现成实现：`src/host/one_click_test.py:189,192-194`、`src/host/health_read.mjs:314-324,283-286`
（`:315-317` 记第一版没这保护、**踩掉了 threshold/src_sel/zoom 工况**的教训）。
**没有硬件回读校验**——稳定判据只有那 20 ms。

| lane | 内容 | lane | 内容 |
|---|---|---|---|
| 0 | `drop_words` | 16–22 | `0xDEADBEEF`（未接） |
| 1 | `{16=坏包 pkt_err, 16=作废帧 frames_bad}` | 23 | `dbg_zoom`（`pl_video_top.v:674-688` + `zoom_snap.v:27` 的 20bit 打包式） |
| 2 | `{16=rows_miss_max, 16=stall_ms}` | 24 | `q_ms = {14'd0, pair_ok, 本轮 sticky, ms[15:0]}` |
| 3 | `gap_last` (ms) | 25 | `{n_meas, clamped}` —— **写 25 武装整组快照** |
| 4 | `{gap_max, gap_min}` | 26/27/28/29 | `dbg_lat` 的 `max` / `tot` / `c2` / `c1` |
| 5 | `gap_sum` | 30 | `{16'd0, dbg_src[15:0]}`，`[10:8]=why_ps`（位序唯一出处 `src_arb.v:35-39`；`dbg_src` 位图 `pl_video_top.v:62-79`） |
| 6 | `cdc_episodes` | 31 | `{30'd0, hb_slow, hb_gone}`（bit0=源钟没有，bit1=源钟被拉慢；**拔线时只有 bit1 会亮**） |
| 7 | `{27'd0, flag5}`：bit0 丢字 / 1 废帧 / 2 灌满 / **3 流活着** / 4 间隔可用 | | |
| 8 / 9 | `in_pkts` / `in_bytes` | | |

mux 实现：`system_top.v:237-247`（**if/else-if 组合链，没有 case、没有寄存器**）。特别注意
`:244` `lm_lane > 5'd9` → `32'hDEAD_BEEF` ⇒ **lane10-22 全部落这一条**，而 lane23-31 在前面已被逐条截走。
计数器出处：`src/rtl/eth/link_monitor.v:187-196,202-203`（flag5 在 `:158`）。

### 13.6 `status[31:0]`：**没有读者，别当观测面**

位组成（`pl_video_top.v:1102-1105`，逐字）：
```verilog
assign status = {zoom_dir, zoom_active, inv_used, eth_ready, locked, rotate_active, angle,
                 5'b0 /* 原 en_sync：随 #66 五位控制一起退役，位保留填 0（与 gpio_o[4:0] 同样处理：
                        不重排，JTAG 侧的读法就不会错位） */, src_use, 2'b00};
```
它在 `system_top.v:45` 声明、`:319` 连接，然后**没有任何外部口** ⇒ 综合当死逻辑剪掉。
要状态就读上面的 lane。`:1044-1045` 还有一条口径说明：这里给的是 **`inv_used`**（拟合模式下"屏上到底是什么
倍率"），不是 `inv_scale`。

### 13.7 运行期配套自检（固件里，不是 PL）

- 第一段（`main.c:1536-1550`）：向 `CFG_DATA0` 写 `0x1FF` 回读比低 9 位，再写 `0x00780000` 回读比 `[22:19]`；
  图案**故意放在保留段**（`:1538-1541` "探针不许命令硬件"）；失败打
  `[CFG!] …位流里没有新的 axi_gpio_2…elf/bit 不配套`。为什么值得开机做：`:1532-1535`
  （硬编码地址**不会编译失败**，症状只有"写了没反应"）。
- 第二段（`:1554-1565`）：gamma 窗口图案 `GM_DATA(0x5A)|GM_IDX(0x3C)`，**`en=0/wr=0`**
  （自检不许打开 gamma 或灌垃圾），整字读回必须全等，收尾回影子 `gm_w` 而不是 0。
- 运行期第二入口：每次 `sd`/`sd remount` 先跑 `meta_selftest()`（`sd_play.c:423-467`，调用点 `:476`）
  与 `dir_selftest()`（`:267-289`，调用点 `:480`），失败报 "**firmware bug, not the card**"。

重取：
```bash
grep -n "gpio_o\[\|gpio_cfg1_o\[\|lm_lane\|DEAD" src/rtl/top/system_top.v
grep -n "_BIT\|GEOM_MASK\|GM_" src/ps/main.c | head -40
```

---

## 14. PS 裸机固件（`src/ps/`，2477 行）

### 14.1 骨架

- 入口 `main.c:1519`；初始化次序见 §5 末。主循环 `:1587-1594` 每轮六个调用：
  `uart_poll()`（`:1426`）→ `sd_tick()` → `sd_recover_tick()` → `ps_keepalive()`（`:261`）→
  `gamma_tick()`（`:347`）→ `temp_poll()`（`:806`）。
- **`main.c:1571` 注释："UDP RX is in PL"** —— PS 完全不碰网络数据面。PS 的时钟/DDR/网口初始化
  由 `ps7_init` 做（JTAG 走 `build/tcl/ps_jtag_boot.tcl`，自启走 FSBL）。
- 串口：**115200 只出现在注释/提示串**（`:206,305,1572`）。全文件**没有**
  `XUartPs_CfgInitialize` / `SetBaudRate` 调用（检索式 `grep -n "XUartPs_CfgInitialize\|SetBaudRate" main.c`
  → 未找到），字符走 `STDIN_BASEADDRESS` 轮询（`:1480-1481,1500`）。
  行缓冲 `CMD_BUF 128`（`:311-313`，旧值 48 静默截断的账在 `:1423-1425`），半行残包超时
  `RX_IDLE_MS 3000`（`:315-319`），CR 折 LF（`:1483`），超长一行只报一条（`:1501-1505`）。
- **为什么发布不走 `ctrl_apply()`**：`main.c:204-207` 原文——30 fps 每秒往串口推约 2 KB，而 115200 只有
  11.5 KB/s、`xil_printf` 是轮询阻塞实现，板上 PLAY 10 s 收回 28549 B 全是 `[CTRL]` 行 ⇒
  `ps_publish()` 调**不出声**的 `ctrl_write()`（`:242-251`）。

### 14.2 心跳与"PS 片源为什么不会被判死"

`ps_keepalive()`（`main.c:261-269`）：`ps_hold==1` 时每满 `PS_HB_MS = 100u`（`:260`）就再调一次
`ps_publish()`（`:268`）⇒ **keep 的是"翻转位心跳"，不是硬件看门狗**。它撑的是 PL 侧
`src_life` 的 500 ms 活判据（`src_life.v:10-12` 原文给出比例账：30 fps 每帧 33 ms ⇒ 15 帧余量；
固件 100 ms ⇒ 5 帧余量；"短到拔卡半秒回图卡、长到不误判一次 SD 读超时"）。
`100 ms : 500 ms = 1:5` 由 `sim/tb_v102_src_life.v` 的 **S12** 钉住（`main.c:257-258` 明写这条对应关系）。
停心跳的**唯一入口**是 `ps_source_lost()`（`main.c:273-278`，由 `sd_play` 读失败时调用）。

PL 侧换算（`src_life.v:31-32`）：`HB_CYCLES = (CLK_HZ/1000)*HB_TIMEOUT_MS = 25_000_000`、
`HB_FRAMES = HB_CYCLES/840_000 + 1 = 29+1 = 30` 帧 ≈ **504 ms**（一帧 = 1344×625 = 840_000 拍）。
`:29-30` 原文记第一版的算术事故："**先除后乘**……而 `HB_TIMEOUT_MS*CLK_HZ` = 2.5e10 会在 32 位 integer 里
回绕 ⇒ 500 ms 变成一帧"（`src_life.v:12-14`）。
`have_src = mode_ps ? ps_src_now : ((mode_eth || eth_owner) || ps_src_now)`（`:56-57`）——
`:22-23,52-54` 说明"锁 ETH 按语义保留最后一帧，**不参与看门狗**"。这个模块修的原始病（`:5-7`）：
原来 `have_src = eth_link_pix | ps_src_seen` 两位都**只会被置 1** ⇒ "AUTO 下拔掉 SD 卡，画面永久冻在最后
一帧、插回也不恢复"。

### 14.3 gamma 下发协议（逐点，不是批量口）

`gamma_put()`（`main.c:366-373`）五步：① 第一笔摆 `data + idx`、**`wr` 不动**（`:368`）；② `usleep(5)`；
③ `gm_w ^= GM_WR` 翻转（`:370`）；④ 第二笔整字（`:371`）；⑤ `usleep(5)`。
`gamma_set()` 循环 **256 项**逐项写（`:405-413`），期间每步 `rx_fill()` 防串口丢字节（`:412`；
FIFO 16 字节 ≈ 1.4 ms 的账在 `:303-310`）；写完**一次性** `gm_w |= GM_EN` 并同字提交 γ×10 显示格
（`:414-418`，`:415-416` 原文"表与屏同一笔"）。总时长 **≈2.6 ms**（`:286-287`）。
**掉 `wr` 沿的后果**：PL 只看边沿（`main.c:80,284-286` 原文"PL 看的是 `wr` 的边沿……**这条约束是真实的，
别删**"）⇒ 两次写之间没翻转 = 那一项**根本没进 LUT**，表残缺但不报错。
`gamma_tick()`（`:348-364`）是 Auto 呼吸：每 `gm_ms`（默认 2000 ms，下限 200，`:323,329`）走一步
`gm_step`，在 `lo..hi` 之间来回（`:357-362`）。

### 14.4 温度换算（有专职尺子）

`main.c:754`：`temp_mc_of(raw) = ((u64)raw * 503975) >> 16 - 273150`（**℃×1000 的定点**）；
等价式 `℃ = raw × 503.975/65536 − 273.15`，常数源自 BSP 宏 `XAdcPs_RawToTemperature`
（`:750-753`）。电压 `:755` `(raw * 3000) >> 16` mV。
**`temp_formula_check.mjs` 校验的就是同一条**：它从 `main.c` 源码里抠出三个常数（`:25-37`），与逐字抄 BSP 宏
的浮点参考式（`:41`）在**全 65536 码段**比对（`:47-52`），容差由推导给出（`:53-61`），另有三锚点（`:68-72`）
与三个**变异反例**（`:84-88`）。⇒ 回答"温度对不对"有机械答案，不需要板子。

### 14.5 命令全集（派发器 `dispatch()` `main.c:890-1394`）

先做两件前置：`parse_bits(tk[0])`（`:896-897`：`nt==1` 且是 5 或 9 个 `0/1` 字符则当 pipe 位串；
**5 位只翻译不生效** `:478-489`，6/7/8 位一律拒 `:573-590`）；`tokenize` 上限 `T_MAX 8`（`:626,677-689`）。
匹配实现：`ci_eq`（`:640-648`，大小写不敏感全等）与 `ci_pre`（`:650-658`，**前缀匹配、先到先赢**），
整数解析 `strict_int`（`:661-675`，>100000 判溢）。

| 命令 | 派发行 | 语法 / 范围 | 副作用 |
|---|---|---|---|
| `PIPE` | `:899-910` | `pipe <9位>` / `pipe show`；**只收 9 位** | 写 `cfg1[8:0]`（`ctrl_set_sel` `:454-458`）；回声 `[CTRL]×2` + `[PIPE] sel=… 生效:` |
| `TH` | `:911-920` | 0..255，越界**夹**（`:916-917`） | 写 `gpio_o[15:8]` |
| `SRC` | `:921-931` → `cmd_src:711-736` | `auto`/`0`/`1`/`2`（码 auto=0 ETH=1 SD=3 TEST=2） | **改片源** `bit16` + 两笔写 `[24:23]`/`[22]`（`:508-515`）；`src 2` 还 `sd_play(1)` |
| `ZOOM` | `:932-982` | `on`/`off`/`0`/`1`/`auto`/`fit [0|1]`/`<倍率>`；倍率只在 **0.01..4.00** 解析（`:538`），取最近八档（`:544-554`） | `on/off`→`bit17`；`auto` 清 `zman`→`cfg1[29]`；`fit`→`bit31`；倍率→`cfg1[28:26]`+`[29]` |
| `BILIN` | `:983-1004` | `on/off/0/1/show` | 写 `gpio_o[19]`；`show` 说明"何时才看得出差别"（#86） |
| `OSD` | `:1005-1027` | `on/off/show` | 写 `gpio_o[20]` **反相** |
| `ROT` | `:1029-1094` | `rot auto [0|1]`、`rot speed 0..7`、`rot show` | 写 `cfg1[9]`、`[12:10]`；`rot auto 1` **顺带**把 speed 0→2 并开 `zoom_fit`，且明说（`:1064-1083`）；**有意没有绝对角度命令**（`:1034-1036`） |
| `SPLIT` | `:1095-1203` | `split <0..100>`、`px <0..w>`、`auto`、`manual`、`swap`、`follow`、`marker`、`screen`、`video`、`show` | 全写 `cfg1` 几何；`marker` 语义**取反**到 `marker_off`；`screen/video` 换坐标系（`:1155-1171`）；`range`/`speed` **待接、明确拒**（`:1199-1201,1406`） |
| `GAMMA` | `:1204-1252` | `off`/`on`/`<1.00..3.00>`/`<100..300>`/`auto [lo hi [step [ms]]]`/`manual`/`show`；`GAMMA1.8` 粘着也吃 | 写 `cfg2` 全 256 项 + `EN` + `DISP`；**手动指定先停 Auto**（`:1249`） |
| `FRAME` | `:1258-1264` | `frame N` | **成功才** `ctrl_set_src(1)`（`:1262`）；失败只报错 |
| `SD` | `:1265-1320` | `sd`/`sd files`/`sd file n`/`sd remount` | 裸 `sd`→`sd_mount()`；`file n`→跳帧+换源；`remount`→重初始化 |
| `PLAY` | `:1321-1343` | `play`/`play 0|off|stop`/`play 1|on`；其它参数明确拒 | 开播分支 **先 `ctrl_set_src(1)` 再 `sd_play(1)`**（`:1337-1338`）⇒ 见 §18 的 #197 |
| `STOP` | `:1344-1348` | 无参 | `sd_play(0)`；**不停心跳、不丢画面**（`:1344-1346` + `:271-278`） |
| `FILL` | `:1349` → `cmd_fill:692-709` | 无参 | 往 `0x1010_0000` 写诊断图（`:694-705`）+ **`DCacheFlushRange`**（`:706`）+ `ctrl_set_src(1)` + `ps_publish()` |
| `ECHO` | `:1350-1362` | `echo [0|1]` | 会话内回显开关；`echo 0` 必须回一句 |
| `AUTOPLAY` | `:1363-1369` | `0|1` | **只改 RAM 变量**，原文 "only affects the next boot"（`:1367`） |
| `TEMP` | `:1370` → `cmd_temp:834-888` | `temp`、`temp th <0..200>`（`th60` 粘着亦可） | 读 XADC、必要时写 `cfg2` 低字节；回显 degC/raw/vccint/th/over/**sane**/osd/gpio 三段账 |
| `STAT`/`STATUS` | `:1371-1391` | 无参 | 只回显；**字段顺序是合同**（`:1372-1375`），`geom=%08x` 是 19 位整字指纹（`:1376-1380`） |
| `HELP`/`?` | `:1392` → `:1396-1420` | — | 打印；"待接"清单只剩 `split range/speed` |
| 未知 | `:1393` 返 −1 | — | `uart_poll` 打 `[CMD] 不认:` + help（`:1466-1468`） |

**两条真实的歧义（必须写进文档否则 AI 会编）**
1. **`zoom 1` / `zoom 0` 是开关，不是倍率**（`main.c:934-943`：`strict_int` 得 0/1 先当开关），
   `:977-981` 的拒绝消息里明说"要 1.00 倍请写 `zoom 1.0`"。上位机侧实测翻车记录在
   `src/host/uart_cmd_check.mjs:107-111`（r53 电池拿 `zoom 1` 当"回到 1.0x"，结果把呼吸又打开）。
2. **粘着写法对 `show` 无效**：`bilin show` 只认分开参数（`:986` 判 `tk[1]`），而开/关认 `tk[0]+5`
   （`:984`）；`osd show` 同理（`:1013` vs `:1011`）。
   （已关闭的历史歧义：老实现 `strncmp(buf,"TH",2)` 连 `THE` 都当 TH，`main.c:617-618,913-915`，
   反例判据 `uart_cmd_check.mjs:64`。）

### 14.6 SD 播放：自研只读 FAT32（`src/ps/sd_play.c`，881 行）

**为什么自己写**（`:4-6` 原文）：BSP 里没有 `xilffs`；卡上布局自家生成；只读目录扫描 200 行够用。
**不支持长文件名的真正原因**：生成器只产 8.3 名（`:5-6`；`src/host/make_sd_video.mjs:13`），
固件侧对 LFN 属性 `0x0F` 项直接跳过（`:251`）。⇒ **任意工具拷进去的长名素材读不到**。

| 项 | 内容 | 行号 |
|---|---|---|
| MBR/分区 | 签名偏移 510 = `0xAA55`；分区 1 类型字节 `446+4` 必须 `0x0B`/`0x0C`；分区 LBA `446+8`；扇区数 `446+12` | `:207-213` |
| BPB | 引导扇区签名 510/511；**bytes/sector 偏移 11 必须 512**；`SecPerClus` 偏移 13；保留扇区 14；FAT 数 16；`FATSz32` 偏移 36；`RootClus` 偏移 44 **掩 28 位** | `:215-222` |
| 判定 | `FATSz32 == 0` 或 `spc == 0` 直接拒 ⇒ **FAT16 不支持** | `:221` |
| 派生 | `fat_lba = part_lba + rsvd`；`data_lba = fat_lba + nfat*fatsz` | `:223-224` |
| 簇→扇区 | `clus_lba(c,sblk) = data_lba + (c-2)*spc + sblk` | `:149` |
| FAT 链 | 低 28 位掩码；`>= 0x0FFFFFF8` 视作链尾；**一个扇区的缓存**（`FatLba`） | `:133-146` |
| 8.3 名 | 前 8 大写补空格 + 扩展名 3 字节；每扇区 16 项；`0x00` 终止、`0xE5` 跳过、卷标跳过；`memcmp 11` 全等 | `:151-167,247-253` |
| 首簇 | `clus_of = ld16(&d[20])<<16 \| ld16(&d[26])`（**小端**） | `:233` |
| 读 | 每次最多 **64 扇区**；读前 `DCacheFlushRange`（脏行回写会盖 DMA，`:86-89`）；`XSdPs_ReadPolled` 一次重试 | `:90-130` |
| 零拷贝 | DMA 直接落 PL 要读的 DDR，**无 memcpy 无二级缓冲** | `:12-13,744,756` |

**#50 那次 bug 的形状**（`:230-232` 与 `:96-107`）：`dir_lookup` 的高簇字曾按**大端**拼 ⇒
首簇 ≥ 65536 的文件簇号翻成天文数字 ⇒ 症状是"3584 帧定点坏点"。
`dir_selftest`（`:267-289`）不只是正例：它带**两条反例断言**——旧大端写法必须真给出 16777218 那个样本值
（`:283-285`）、新旧必须**给出不同答案**（`:286-287`），否则"判据是照抄实现"。

**帧时序**：META 里 `FPS=x.xxx` → `fps_num/fps_den`（`:320-332`，为 0 时兜底 15）；
`sd_tick` 比较 `(now - last_t) >= COUNTS_PER_SECOND*fps_den/fps_num`（`:852-854`）；到 `total_frames`
回绕循环（`:856`）。**不用 usleep 睡到下一帧**的理由在 `:842-844`（UART 会钝）。

**META.TXT 校验**：行首锚定（`:292-309`）；`FRAME_BYTES` 必须等于编译值（`:333-337`）、`WIDTH` 必须 512
（`:338-340`）、每个 `FILEn` 行必须带 `FRAMES`（`:350-352`）；`kv_u32` 的词首判据曾出错（ISSUES #43，
`:185-192`）；内置 `meta_selftest` 五段样本（ok/b1/b2/b3/long，`:401-467`）。

**分卷与容量**：`VIDEO%03d.BIN`（`make_sd_video.mjs:104`），默认 `--chunks 512` 帧/卷
= 512 × 307200 B = **153.6 MiB/卷**，现役 9 卷 `VIDEO000..008`（`sd_play.c:9`）；帧数取
`min(FRAMES=, ΣFILEn)` 并置 `meta_warn`（`:360-378`，`:360-363` 讲了 2099/4398 那张卡的实测故事）。

**与 bank 的交接**：SD 素材**永远写第三个 bank `0x1010_0000`**（`sd_play.c:35`、`main.c:41-46` 记了
"与 ETH 乒乓 `0x1000_0000`/`0x1008_0000` 分开的打架实录 `:42-45`"）；写完一帧 `show_frame` 调
`ps_publish()`（`sd_play.c:786`）翻 `bit18`；**commit 由 PL 做**——PL 在下一个 `frame_start` 复制**一次**
（不是每帧都拷），防撕裂协议见 `sd_play.c:15-18`。

### 14.7 热插拔是**实现边界**，不是可修项

- `sd_recover_tick()`（`sd_play.c:607-639`）：每 2 s 才动一次（`:622`）、**最多 30 次**（`:625-628`，约 1 分钟），
  且 `if (mounted) return` 早退；资格条件：本上电周期挂载过 `seen_mounted` **且**丢卡瞬间正在播
  `want_play`（`:612-619`，`want_play` 只在 mounted 时跟随 playing ⇒ **`stop` 后插卡不会自动开播**）。
- 为什么不复用 `sd_mount`：`sd_mount` 第一行就是 `if (mounted) return 0;`（`:475`），而拔出卡没有任何路径
  清 `mounted` ⇒ 插回去是"假挂载"，每次读都失败（`:547-550,577-579`）。
- 为什么必须清驱动的 `IsReady`：`:555-563` 原文引驱动 `xsdps.c:156-159`
  （`if (InstancePtr->IsReady == XIL_COMPONENT_IS_READY) return XST_DEVICE_IS_STARTED;`，
  "If this API is getting called twice, return value accordingly"），并写
  "**我们的代码里没有任何一处清 `IsReady` ⇒ 第二次初始化永远在第一步就被挡回**"；
  手工修法在 `sd_remount()`（`:565-574`，**`:572` 那一行清 `Sd.IsReady`**）。
  ⚠ `:555` 还有一句更正："#45 那句归因是错的"——**旧文档把病因记成"每上电周期只成功一次"，
  真相是守卫没被清**。引用 #45 时以 `sd_play.c:555-563` 为准。
- 30 次用尽后的**两条退路**（`:625-628` 逐字）："自动重挂 30 次没成功，停手：插上卡后敲 `sd remount`，
  或重下 elf（JTAG 三件套第三条）"。读失败的停播路径另见 `:865`。**没有断电以外的第三个键**。

重取：
```bash
grep -n "dispatch\|ci_pre(\|ci_eq(\|_BIT\b" src/ps/main.c | head -60
grep -n "0x1FF\|IsReady\|clus_of\|64\|CLUS" src/ps/sd_play.c | head -30
```

---

## 15. 上位机工具与协议（`src/host/`，29 支，零第三方依赖）

依赖口径：Node 24 只用内置模块、Python 3.12 只用标准库、**不需要 pyserial**（`src/host/README.md:19-22`）。

### 15.1 UDP 投送协议（与 §7.4 的硬件解码必须成对读）

- 包：`[u32 小端 帧内偏移][RGB565 载荷]`。Python 侧 `udp_push.py:4-6`（打包式
  `struct.pack("<I", off) + chunk` `:69`），Node 侧 `video_sender.mjs:9`（`p.writeUInt32LE(off,0)` `:198`）。
- **载荷长度必须是 8 的倍数且 ≤ 1392 B**（`udp_push.py:6-8`）。理由原文：非 8 倍数时包边界落在 64bit DDR 字
  中间，打包器分两次推同一字**互相覆盖** ⇒ 规律黑点；`--mtu-payload` 给非 8 倍数是**复现缺陷**的对照，
  不是用法（`:6-7,96-97`）。
- 1392 + 4 头 = 1396；> 1472 会被 IP 分片而**收包链不分片** ⇒ 会警告（`:98-100`）。
- 每帧包数 **221 = ceil(307200 / 1392)**（`one_click_test.py:25`、`video_sender.mjs:220`）。
  对账式：`exp_pkts = frames × 221`、`exp_bytes = frames × 307200`（`:110-111`）。
- 限速：Python 侧按**累计字节数推时间戳**而不是叠加 sleep（`udp_push.py:74-90`，`:75-76` 原文理由
  "sleep 抖动会污染帧间隔测量"，`:133` 把包头字节也计入）；Node 侧 `paceSpend` 绝对时间目标 +
  `Atomics.wait` + 尾自旋（`video_sender.mjs:171-186`，每包预算 ~93 µs）。
  `--no-pace` 是过载观察模式（`metrics.mjs:177-179`）。
- **确定性丢包**："每 N 包丢第几包"必须可复现（`udp_push.py:13-16,66-68`；
  `video_sender.mjs:188-204`，原文"随机丢等于没有判据"）。

### 15.2 各工具的职责与判据（按用途挑）

| 要做什么 | 用哪支 | 判据/关键实现 |
|---|---|---|
| 造 SD 帧库 | `make_sd_video.mjs` | `--in --out --chunks 512 --preview`；需外部 `ffmpeg/ffprobe`（`:40-44`）；命名 `VIDEO%03d.BIN`（`:104`） |
| 造边界输入 | `data/generated/gen_inputs.mjs` | `--write/--selftest/--check --seed 20261004`；几何取自 `video_sender.mjs` 的 `W/H/FRAME_BYTES`（`:26-30`） |
| 受控推流 | `udp_push.py` | `--ip --port --fps --pace-mbps --count --file --mtu-payload` |
| 板级一键 | `one_click_test.py`（`.mjs` 同义）/ `run_test.sh` | 四步见下 |
| 吞吐 | `metrics.mjs`、`measure_v63.mjs`（含包内相位丢字签名） | 文件头 |
| DDR 图像比对 | `ddr_verify.mjs`（`--bank-only 0|1`、`--ref`、`--frameid`） | 图案生成 `video_sender.mjs:132-143`；校验 `ddr_verify.mjs:81-84`：`v = ((w>>1)+ADD)&0xffff`、`want = v|(v<<16)`；失败按 `never/stalePattern/other` **三类**分（`:87-92`）；`rst -processor` 是为了关 MMU/Cache 读到 DDR 真值（副作用是停 ELF，`:40-44`），**故意不 `con`**（`:53`） |
| 陈旧度 / 洞图 | `ddr_stale.mjs`、`ddr_holemap.mjs` | `:9` |
| 定位丢字在哪一级 | `ingress_probe.mjs` | 文件头 `:7` 定义六级 **UDP→reasm→CDC→packer→AXI→DDR**；实现是"发 K 个带相位标签的包 → 等 1.5 s 排空 → JTAG 回读两个 bank 的前 **K×174** 个 64bit 字（174 = 1392/8）→ 落位率 / 首个缺失字（换算回包号 `:114-115`）/ 缺失间距分布（`:117-124`）"。⚠ **它不是"每级读一个计数器"**（`未找到` 分级计数器读取实现；按级计数器的读取属于 `health_read.mjs` 的 lane0/1/6/8/9） |
| lane 全表回读 | `health_read.mjs`、`lane30_watch.mjs`、`arb_handover_test.mjs` | `--gpio0 41200000 --gpio1 41210000 --once --gapclr`；两遍比对：单调集合 `MONO={0,1,5,6,8,9}`（`:51`）**只有第二遍比第一遍小才报撕烈**（`:487-496`），非单调 `{2,3,4,7}` 不等只标注不报错；读取顺序 `25→26..29→24→23→30→31` **是判据的一部分**（`:326-334`）；lane30/23/31 译码器自带 `--selfcheck` S1-S5f（`:66-252`） |
| 命令电池 | `uart_cmd_check.mjs --file board/cmd_battery_v81.txt --port COM6 --dry` | `:7`；歧义反例 `:64,107-111` |
| 交接判据 | `arb_handover_test.mjs` | V0-V7 `:162-211`，门限 `:63-64` |
| 文档/数字尺子 | `line_cite_check.mjs`、`doc_currency_check.mjs`、`metric_recheck.mjs`、`doc_enc_check.mjs`、`pipe_len_check.mjs`、`temp_formula_check.mjs`、`geom_check.mjs`、`ps_hb_check.mjs`、`demo_cmds.mjs`、`card_preview.mjs` | **每支都自带 `--self` 反例**（= "判据能红"的机械证明） |

### 15.3 `one_click_test.py` 四步（能脱离板子跑到哪一步）

1. **PING**：两种 `ping` 写法各试一次（Windows `-n/-w` 与 POSIX `-c/-W`），`:143-156`。
2. **CONNECT**：起 xsdb 会话头 `connect -host localhost -port 3121` / `targets -set -filter {name =~ "*#0"}` /
   `catch {stop}` / `after 100`（`:160-165`）；`read_lanes` 先 `mrd GPIO_0` 取原值（`:185-188`）、
   `keep = cur & 0x07FFFFFF`（`:189`）、逐 lane `mwr`+`after 20`+`mrd GPIO_1`（`:192-194`）、
   结束原值写回 + `catch {con}`（`:195`）。基线取 lane0/1/8/9（`:212-221`）。
3. **SEND**：转 `udp_push.py` 发 frames 帧，用正则读它自己打印的
   `[TX] …发包含丢共 M 包，主动丢了 D 包`（`:224-242`），判据 `sent_pkts == exp_pkts`（`:239`）。
4. **COLLECT**：再读一次，增量对账 `d(8)==exp_pkts && d(9)==exp_bytes`，顺带报
   `drop_words`/`frames_bad`/`bad_pkts` 增量（`:249-255`）。片源不足时重复补足后截帧（`:112-123`）。
**`--dry-run` 免板**：跳过 xsdb 与 COLLECT，只跑 PING/SEND 的参数装配 ⇒ 可以在无板环境证明"脚本能跑"，
**但不能证明板上行为**（这是本文多处 `需板端` 的原因）。

---

## 16. 构建、仿真、烧写（可照抄的命令序列）

```bash
# —— BD 快检（不出位流）：改 BD/地址后先跑这个
vivado -mode batch -source build/tcl/build_system_axigpio.tcl -tclargs bd_only     # :278 BD_ONLY_DONE
# —— 全流程：建工程→综合→实现→位流 + 7 份报告 + XSA
vivado -mode batch -source build/tcl/build_system_axigpio.tcl                      # :306 synth_1、:353 impl_1→write_bitstream、:371 write_hw_platform
# —— 分步
vivado -mode batch -source build/create_project.tcl   # 建工程
                    build/synth.tcl                   # 只综合
                    build/gen_bit.tcl                 # 只出位流
                    build/report.tcl                  # 只重出报告
# —— 固件（需要三个环境变量 + 绝对路径）
PS_CC=<arm-none-eabi-gcc 绝对路径> PS_BSP=<BSP 目录> node build/ps_app.mjs
# —— 仿真
bash build/sim/run_one.sh tb_crc32
VP_VIVADO_BIN=<…> vivado -mode batch -nojournal -log sim/xsim.log -source build/sim/run_sim.tcl
#   可用环境变量：SIM_TB / SIM_ONLY / SIM_VERBOSE / SIM_ARGS
# —— 门禁（报告必须在同目录）
bash build/gates.sh [冻结目录]
# —— JTAG（易失，重启就回启动介质）
VP_VIVADO_BIN=<…> VP_XSDB=<…> bash board/scripts/board_flash.sh
# —— QSPI 固化（约 3–6 min，含擦除与回读）
VP_VIVADO_BIN="D:/…/Vivado/bin" bash board/scripts/make_boot_image.sh
"<Vivado>/bin/vivado.bat" -mode batch -nojournal -log flash_qspi.log -source board/tcl/flash_qspi.tcl
# —— 板级一键
bash run_test.sh           # → python src/host/one_click_test.py "$@"
```

### 16.1 前置件与固定顺序

- 环境变量：`PS_CC`（**绝对路径**的 `arm-none-eabi-gcc.exe`，缺则 FATAL，`build/ps_app.mjs:26,42`）、
  `PS_BSP`（默认**仓库内** `vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp`，`:27-30`，
  挪进仓库的理由原文"换机器不再断"；必须绝对路径，`src/ps/README.md:37-39`）、`VP_VIVADO_BIN`、`VP_XSDB`；
  仿真侧不指 `VP_VIVADO_BIN` 就 `exit 2`（`sim/README.md:9-10`）。
- 必需文件校验：`BSP/include/xparameters.h`、`BSP/lib/libxil.a`（`:43-44`）。
- 编译档：`-mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard -mno-unaligned-access -DSDT
  -ffunction-sections -fdata-sections -Wall -Wextra -Wno-unused-parameter -O2
  -I<BSP>/include -specs=<BSP>/Xilinx.spec`（`:46-57`）；
  **`-mno-unaligned-access` 的 data abort 双根因写在 `:47-54`**。
- BSP 启动三件**必链**：`asm_vectors.S` / `boot.S` / `translation_table.S`（`:100-109`，
  少链的三个症状 CPACR/VBAR/MMU 写在 `:85-99`）。
- 链接：`-Wl,--gc-sections -Wl,-n -Wl,--no-warn-mismatch -T src/ps/lscript_ocm.ld -lxil -lxilstandalone
  -lxiltimer -lgcc -lc -lm`（`:117-125`）。三归档拆分的理由（`_start` 只在 `libxilstandalone.a`）在
  `:112-116`；**`-lm` 是 V8-3 的 gamma 曲线（`pow`）要的，放在 group 里是因为 newlib 的 libm 反过来依赖 libc**
  （`:123-124` + `main.c:24`）。
- 链接脚本 `src/ps/lscript_ocm.ld`：**MEMORY 基址已挪到 DDR `0x0020_0000`**（`:19-33`，
  "FSBL 加载地址 0 不交接"的机制写在 `:19-24`）；`ENTRY(_boot)`（`:49`，两次改错的历史 `:37-47`）。
- 成品硬校验：`nm` 必含 `_start/_boot/_vector_table/MMUTable/main/XSdPs_CardInitialize` 且
  `.text >= 20000 B`（`:135-149`，原文症状"**空 ELF 看起来成功**"）。
- 顺序固定：**先 `node build/ps_app.mjs` 出 ELF → 再 `make_boot_image.sh` 打镜像（`bootgen -arch zynq
  -image boot.bif -w -o BOOT.bin`）→ 最后 `flash_qspi.tcl` 写片**。镜像路径由 `VP_BOOT_IMAGE` 给，默认
  flash 目录里的 `BOOT.bin`（构建产物，不随包）；文件不在就直接 `REFUSE: no boot image` + `exit 1`（`board/tcl/flash_qspi.tcl:11,20,32`）。

### 16.2 烧写：两种"跑起来"完全不是一回事

| 方式 | 命令 | 持久性 | 关键内部步骤 |
|---|---|---|---|
| JTAG | `board/scripts/board_flash.sh` | **易失**，重启回启动介质 | STEP1 `ps_jtag_boot.tcl` 内含 **`rst -system`（会冲掉位流）** → STEP2 `program_pl.tcl` 用 `program_hw_devices` → STEP3 下 ELF（`board_flash.sh:19-20,83-94`；`program_pl.tcl:20-34`） |
| QSPI | `flash_qspi.tcl` | 掉电保留 | `create_hw_cfgmem` + `program_hw_cfgmem`（`:75,114`），部件名 `:12`，擦除/回读步骤 `:86-103` |

- **全仓没有** `write_cfgmem` / `program_cfgmem` / `program_hw_targets`
  （`grep -rn "write_cfgmem\|program_cfgmem\|program_hw_targets" .` → 0 命中）。
- ⚠ **喂法红线**（`flash_qspi.tcl:33-40,86-103` 原文）：已打好的 `BOOT.bin` 走 `PROGRAM.FILES` 且**不给**
  `PROGRAM.ZYNQ_FSBL`；给 `.bit`/`.mcs` 才单给 FSBL 让工具打镜像。**否则镜像套镜像** ⇒ flash 开头的分区表
  成垃圾、报 `INVALID_LOAD_ADDRESS_FAIL, FSBL Status=0xE0000000`（`flash_qspi.tcl:38` 逐字——**这是状态码，不是跳址**）；
  ⚠ "板上完全不出串口输出"这一句**出处不在这里**：有凭据的那条是
  `board/scripts/make_boot_image.sh:17,43`（镜像把 IHT 的分区表偏移三字段留成 0 ⇒ 启动 ROM 读不懂，
  实测"DONE 不亮、串口零字节"），那是**另一种坏法**；"JTAG 手工下 ELF 仍能跑"则是**机理（推断）**，
  仓库里没有把两件事成对记录的同一次凭据。
  而 JTAG 手工下 ELF 仍能跑——**这两件同时成立就是镜像包错了**。
- 不可逆动作（要现场人员确认）：擦 QSPI、改 FT2232 EEPROM、擦 SD 镜像/引导区、复位正在被别人用的板卡。
  **本次交付没有任何板端验证**——上面所有"板上会看到什么"都标 `机理`。

### 16.3 仿真机制

- 单支：`bash build/sim/run_one.sh <tb>`。原始输出在 **`/tmp/kx/<tb>.run/run.log`**
  （`sim/README.md:26`；目录由 `build/sim/run_one.sh:49` 建，`:120` 警告"已 `cd` 进去、自调必须用绝对路径"）。
  ⚠ 那是 **Git Bash** 视角的路径，PowerShell 里换 `$env:TEMP\kx\...`。
- 屏幕只回放含 `FAIL/PASS/INFO/PROBE/DIAG` 的前 80 行 ⇒ **回放里没有的东西不等于没发生**，
  判据要读 `run.log` 原件。
- 判定行以 `VERDICT <tb>:` 开头（`sim/README.md:24`），退出码含义 `:25`，原始输出与**源树指纹** `:26-27`。
- 全量：`build/sim/run_sim.tcl`（82 支），可用 `SIM_TB`/`SIM_ONLY`/`SIM_VERBOSE`/`SIM_ARGS`。
- **第二家仿真器（2026-10-15 实测，`实测`）**：本机 ModelSim SE-64 2020.4 可用；82 支台架已全部一次 `vlog -f`（164 份，rc=0），
  其中 **80 支跑到收尾**、2 支超单支 240 s 上限（`tb_v98_c8_edge_column`、`tb_v98_top_seam`；后者另已单独跑完整支 20 分 39 秒）。
  **已发现 2 条真·跨工具判定不同**：`tb_v100_fit_rot`（ModelSim `checks=373 errors=2` / xsim `errors=0`）、
  `tb_rotate_mapper`（ModelSim `errors=1`，红在 `FAIL 90 center oob` / xsim 绿）。嫌疑写法（`机理`，未定位）：
  在时钟沿的同一时间步用**阻塞赋值**驱动 DUT 输入（`sim/tb_v100_fit_rot.v:166,170`、`sim/tb_rotate_mapper.v:55-59`）。
  关于 timescale 的实测边界：三条嫌疑 DUT（`src/rtl/process/rotate/rotate_mapper.v:1`、`src/rtl/process/zoom/zoom_ctrl.v:1`、
  `src/rtl/util/key_debounce.v:1`）**本来就写了** ``timescale 1ns/1ps``，所以"差异来自 DUT 缺 timescale"这个问法当时就问错了对象；
  真正缺 directive 的是 `src/rtl` 80 支里的 **13 支，全部在 `src/rtl/eth/`**。测量层面留着的事实是：整清单强制
  `vlog -timescale 1ns/1ps` 重编后，那五支的判定计数一字不变 ⇒ 只能主张"统一 timescale 不改变这五支的判定"。
- `tb_v112_ip_csum` **两家都红** `errors=7`，但**这不是新 bug**：`report/log/issues.md:11232-11237` 记它是"一次失败的尺子……
  文件留着、**不进车道**"（抓取时机理解错了，等价性改由发出字节的差分承担）。
- ⚠ **口径**：门禁 24 项只显式引用 `tb_v98_top_seam`（`build/gates.sh:307-375`）与 `tb_edge_rim`（`:388-418`）两支台架的**凭据件**，
  外加 `build/run_one_ce.sh`（判定解析器的合成对照，不跑真台架）⇒ **"GATES: ALL PASS" 不等于"82 支台架全绿"**；
  问"这件事有没有判据守着"要先问**它在不在车道里**。详见 `report/study/学习文档_合订本.md` §6.13"扩到整仓"小节。
- 门禁另有 `build/run_one_ce.sh`（CDC 专项台架）与 `rtl_fingerprint`（同源指纹）。

---

## 17. 机械门禁逐条（24 条判定，`build/gates.sh`）

调用：`bash build/gates.sh [冻结目录]`。四道"检查器自己也要有判据"的守卫：
- **缺报告即 `exit 2`**：缺 `timing_summary/utilization/power/route_status.rpt` 时（`:43-45`）。
- **解析不到即 `exit 2`**：`for v in wns whs tnsfail whsfail eps bram bramp lut lutp reg dyn crit rerr cdcc`
  逐项查空/`NA`（`:173-177`），外加一行数字形状检查
  `[[ "$wns$whs$bramp$lutp" =~ ^[0-9.+\-]+$ ]]`（`:178`）。
  `:72-77` 记录了为什么要有这一段：r60 时 TNS 在违例时是**负数**（−6.457），旧 awk 只给 WNS/WHS 留符号位 ⇒
  脚本打印"读不到"然后 `exit 2`——**停下来是对的，但它把最该看见的数字（WNS −0.482 / 19 个失败端点）
  换成了"读不到"这句话**。现在四列都允许带符号，且**读不到时把候选行原样打出来**（"尺子读不懂被测对象，
  必须说'我读的是这一行'，不许只说'读不到'"）。
- **`n/a` 不判红但计入结尾范围声明**：`naa()`（`:186-189`）与 `:180-185` 的说明——以前一条 `n/a` 会跟着
  `GATES: ALL PASS` 一起念出去，于是"两支主台架都没跑"的一版也能拿 ALL PASS，而 `freeze_evidence.sh`
  只 grep 这一行（同一个坑本仓记过五次）。
- **不许把它的输出重定向成它自己要读的 `rNN_gates.txt`**（自指，`:18-22`）。
- 另有一段**产物身份/新鲜度**检查：打印 `system.bit` 与 `ps_app.elf` 的 md5、两者相差 >600 s 时 `WARN`、
  并且**只对 `build/` 这份活目录**检查"有 RTL 源比 bit 新"（`:60-68`，
  原文事故："2026-09-24 构建还在跑，我先跑了一次门禁，全套报告都是 30 分钟前的、七项全绿"）。

| 项 | 判据 | 阈值 / 表达式 | 行 |
|---|---|---|---|
| 1 | WNS | `>= 0` | `:197` |
| 1 | 失败 setup 端点 | `== 0` | `:198` |
| 1 | WHS | `>= 0`（**注意：不是 0.4**，§11.3） | `:199` |
| 1 | 失败 hold 端点 | `== 0` | `:200` |
| 2 | BRAM | `<= 97 %`（实测 68.21 %） | `:201` |
| 2 | Slice LUT | `<= 98 %`（实测 26.61 %） | `:202` |
| 2 | Slice 寄存器 | **记录用，无阈值** | `:203` |
| 3 | Dynamic (W) | **与前次同量级（无硬阈值）** | `:204` |
| 4 | methodology CRIT | `grep -ac "CRITICAL WARNING" == 0`（解析 `:98`） | `:205`；无文件→`naa` `:206` |
| 5 | 布线错误网线 | `== 0`（从 `route_status.rpt` 取数 `:100`） | `:207` |
| 6 | CDC | 与 `build/cdc_baseline.txt` 比 **unsafe 不增长**，再与"上一版采纳 `CDCADOPT`"比 **Critical 配对集合不新增**；两者取不到都判红/记 n/a | `:108-171,208-209,160-171` |
| 8 | 端口宽度警告 | `Synth 8-689` 计数 `== 0`；**优先认与本报告同一次构建的凭据 `width_warnings.txt`**，回落用最新日志时必须点名"回落" | `:218-231` |
| 13 | 多驱动 net | `Synth 8-6859 / 8-6858` 计数 `== 0`。理由原文（`:233-237`）："一个 reg 的复位被我同时写进两个 always 块 ⇒ 综合**保留常量那一侧、忽略逻辑那一侧**，bit 里那根旗标恒为 0；而仿真按'进程后写覆盖'，**台架 56 条全绿**。这类'仿真绿、硬件不动'的差别不会出现在任何时序/资源报告里" | `:238-251` |
| 14 | 顶层接线 | `check_ports.py --dup` 的 `violations=0` **且** `ports_floor.sh` 扫描面不塌；r52 起加第三条**位宽**判据。理由（`:262-269`）：`pl_video_top`/`system_top` **没有任何台架例化** ⇒"改了子模块端口、顶层忘了连"这类错全量仿真一条都不会红，只能等 25 分钟构建 | `:264-282` |
| 15 | 顶层台架 `tb_v98` | 报告与当前 RTL **同源**（md5 指纹 `norm1`）+ 无 `^FAIL ` 行 + 判定枚数达标 | `:319-379`（`say` `:371`；历史冻结件不带 md5 → `naa` `:378`） |
| 15b | 边缘条带 `tb_edge_rim` | 同一次跑、无 FAIL、**四条圈齐** | `:387-424`（`say` `:414`；`naa` `:423`） |
| 16 | PS 心跳约定 | `ps_hb_check.mjs --self` 全绿 | `:431` |
| 17 | 手写件编码 | `doc_enc_check.mjs`：`self` 抓到 **3/3** 且全树干净 | `:447` |
| 18 | 文档时效 | `doc_currency_check.mjs`：红行 + **身份句 / 门禁读数句** 必须在位 | `:472` |
| 19 | 排练脚本=讲稿抽取 | 差异行 + **变异对照必须"能红"**（否则该判据恒真） | `:503` |
| 20 | 文档行号锚点 | `line_cite_check.mjs`：`self` 15 条对照全过（含厂商豁免 2 条）、**硬错 0**、命中 `>= 300` | `:520` |
| 21 | 数字对账 | `metric_recheck.mjs`：`self`（csv 两条 fixture + 首页假数 + 逐时钟/归属/百分数/Clock Summary 对照）全过、红 0、判 `>= 30` 个数、首页 `>= 20`、逐时钟 setup 与 hold 归属各 `>= 2`、余量百分数 `>= 6`、csv 认领两半相等且 `>= 8` | `:549` |
| 22 | 命令长度口径 | `pipe_len_check.mjs`：逐条 ok + 自报条数 + 收尾 PASS + `self` 全绿 + 两个 rc | `:569` |
| 23 | 结温公式 | `temp_formula_check.mjs`：`PASS` + **变异对照** + FAIL 行 + rc | `:584` |
| 收尾 | 汇总 | `GATES: ALL PASS` 只在 `pass==1` 且把 `NSAY`/`NNA` 一起念出 | `:593-599` |

（条目号沿用项目自己的编号：**第 1/2 项各含多个 `say` 判定行**，所以"编号到 23"与实际
**24 条判定**不是一回事；`grep -o 'say "[^"]*"' build/gates.sh | sort -u | wc -l` = 24，
门禁件结尾自报"判定 24 项、未判 0 项"。另 `data/metrics.csv` "门禁自检项"行填的是 **22**
（那是更旧的"自检项"口径）⇒ **引用条数前先说清口径**。）

重取：`grep -n 'say "\|naa "' build/gates.sh`

---

## 18. 已知缺陷、边界与开放项

**A. 行为缺陷（有编号、有出处，未修）**

| 项 | 症状 | 出处 |
|---|---|---|
| #196 | 卡里的数据能决定**往数组尾后多写一个字节** | `report/known_issues.md:486` |
| #197 | 被拒绝的 `play` **不中性**：开播分支先 `ctrl_set_src(1)` 再判断 | `known_issues.md:493`；代码 `main.c:1337-1338`（**注意 ISSUES 里记的 `main.c:1359` 是旧行号，已漂移**） |
| #205 | 收侧 ARP/ICMP 这一支**没有错误源**（坏包计数 `pkt_err` 上板恒 0 的历史原因） | `known_issues.md:596`；`link_monitor.v:4-5` |
| #200 | 命令表没有把旋转角归零的动词，`rot auto 0` 回显自相矛盾 | `known_issues.md:508` |
| — | **包偏移倒退不清零** ⇒ 上一帧残字写进刚清零的 bank（修法形状已给，不动验收门） | `known_issues.md:290,293`；代码上 `frame_reasm.v:133-138` 是唯一清零条件 |
| — | 两处"网口/AXI 输入不可信"的**钳制缺失**（候选，未修） | `known_issues.md:121` |
| — | `frame_commit_lock` 的 `IMG_H`/`DISP_H` 两个参数**声明后未使用** ⇒ 它不按行数校验拷贝量 | `frame_commit_lock.v:6-7`（grep 只命中声明） |
| — | `rgb2dvi.v:48` 注释写 `0x3FF` 而代码是 `10'b1111100000`（=0x3E0） | `rgb2dvi.v:48,51` |
| — | `ps_publish.v:17` 的注释"保证 `new_tog` **两拍内**稳定"读起来像"高两拍"；实际异拍输出每次**跳变**只高 **1 拍**（我把 `:20-25` 的移位式逐拍展开算过：`tog` 0→1 后第 3 拍 `new_tog=1`、第 4 拍即回 0；下降沿同样出一拍）⇒ **是措辞含糊，不是代码缺陷**；真正防丢的是 `:28` 的"`new_tog` 优先于 `consume`" | `ps_publish.v:17,20-25,28-31` |
| — | `proc_sharpen.v:5` 说"固定 2 拍"，实际 de 链三个寄存器（3 拍） | `:5` vs `:124-126` |
| #167/#168 | `cmd_buf[128]` 在"≥127 字符 + CRLF"下的边界（**需上板注入**） | `known_issues.md:171`；`main.c:311,1493,1496` |
| #164-#166,#169 | 检查与构建工具**自身**的洞（空结果被当合法 0 念成 PASS 那一族） | `known_issues.md:147`；`gates.sh:206,209,280,297` |

**B. 边界（设计事实，不是 bug）**

| 边界 | 陈述 | 出处 |
|---|---|---|
| RGMII 输入窗 | 5 个口无 `set_input_delay`，且**绑上窗后 tap 0…31 全范围关不掉**（钟网络角间差 3.4 ns ≫ 数据 0.47 ns） | §10.5、§11.5 |
| TMDS 源端窗 | 一个 `set_output_delay` 都没有：**规范数值在本仓没有出处** | §10.4 |
| `status[31:0]` | 有驱动无负载，综合会剪 | §13.6 |
| `split pos` | 10 位（屏宽 1024）⇒ PS 夹到 1023 并明说夹了 | §13.3 |
| `eth_mdc` | 恒 0、`eth_mdio` 恒 z（strap 定模式），`Synth 8-3917` 是陈述 | §2 |
| morph | **不支持开/闭**（两遍），`mode==3` 显式当旁路 | `proc_morph.v:23-25` |
| binary | **无滞回** | `proc_binary.v:23-25` |
| UDP | **不校验 UDP 校验和**，也不校验 IP 首部校验和；只靠帧 CRC32 | §7.3 |
| DA 过滤 | 主线解析器**一行 DA 都不看** ⇒ 任何目的 MAC 的单播/多播都收 | §7.2、§7.3 |
| ARP | 没有表、没有老化：只有一对寄存器，**谁最后发过 ARP 回包就给谁** | §7.3 |
| 帧长 | 只有下限 64，**没有上限校验** | §7.2 |
| ICMP 缓冲 | 8bit×2048，`full/empty/level` 空接 ⇒ 满了静默丢 | §7.3 |
| SD 卡 | 必须 FAT32、必须 8.3 名、必须由 `make_sd_video.mjs` 生成布局；热插拔有 30 次上限，用尽后报文给两条退路：`sd remount` 或重下 ELF（`sd_play.c:625-628`） | §14.6、§14.7 |
| DDR 基址 | 三处手写常量，**BD 不回读** | §7.7 |
| 构建耗时 | 文档三处口径不一致，无整轮 elapsed 行 | §12.5 |

**C. 未决汇总**：编号 201-402、501-507；状态列只允许 6 个值 —— `report/90-open-items.md:10-12,32-43`。
**缺陷册与工作日志是两个文件**：`report/known_issues.md`（按编号的缺陷册）与
`report/log/issues.md`（追加式工作日志）；另 `report/known-limitations.md`。RTL 注释里写作
`report/log/ISSUES.md`、`OVERNIGHT_LOG.md` 的是历史大写名，盘上实为 `issues.md`/`overnight_log.md`
（`system_top.v:271`、`sd_play.c:15`）⇒ **照抄打不开**。

---

## 19. "我要改 X，该看哪几行"

| 想改 | 看 | 注意 |
|---|---|---|
| 加/改一个控制位 | `system_top.v:262-293` + `main.c:4-15,214-218` + `one_click_test.py:189-192` | 三处同改；**位序只往后加** |
| 效果链加一级 | `proc_pipeline.v:22`（LATENCY）→ 自动带动 `MIX_D/SB/SEAM_TAPS/RAW_LINES`（§9.1）→ 跑 `tb_v86_pipe_sel` | 同时要改 `:18` 的逐级账；若把 gamma 改成寄存读出，LATENCY 必须 16（`:21`） |
| 换显示分辨率 | `video_timing_1024x600.v:19-22`、`clk_gen.v:21-29` 分频、`rk_zynq7020.xdc:12-19` TMDS 引脚与窗 | 派生量 `VBLANK_AXI_CYC`、`VB_X_GUARD`、`HB_FRAMES` 的 `840_000` 都要跟着算（§14.2） |
| 改网络包格式 | `frame_reasm.v:105,126-130`（头解码）+ `udp_push.py` 文件头 + `video_sender.mjs:198` + CDC 宽度 `eth_udp_video_top.v:264,298` | 4 字节头是**硬约束**：状态机 `S_OFF0..3` 与 `off[18:1]` 都建立在它上面 |
| 改 DDR 布局 | `eth_udp_video_top.v:67-68`、`system_top.v:139-144`、`sd_play.c:35` | **三处、手写、无回读校验** |
| 改 PHY 采样点 | `system_top.v:172`（`IDELAY_VALUE=31`）+ §11.5 的扫描件 | 改它要**重新综合**（`IDELAY_TYPE="FIXED"`） |
| 加一条约束 | 先回答"这条的出处是什么"；实现期专用 `clock_groups_impl.xdc`；实验变体不要进约束集（`r124_tiers_probe.tcl:43-45` 有 banned 名单） | 不要在 XDC 里写 `if`；不要把 `get_clocks` 取不到的名字并进同一条命令 |
| 查时序 | `build/tcl/read_run_result.tcl:24-30`；逐时钟用 `-delay_type all -to [get_clocks …]`（`r115_baseline_probe.tcl:65,77`） | `report_timing_summary` **不支持 `-clock`**，`-check_summary_only` 在 2025.2.1 **非法** |
| 判"收敛" | `build/gates.sh:197-200` + §10.5 的 `check_timing` 口径 | 综合后的数字不算；只有 routed 算 |
| 跑仿真 | `bash build/sim/run_one.sh <tb>` | 判据读 `/tmp/kx/<tb>.run/run.log` 原件，不是屏幕回放 |
| 加一级 OSD 行 | `osd_overlay.v:19`（`N_LINES`）、`:92`（行号位宽）、`:333`（font 索引历史插入序） | `:92` 原文警告写死位宽会让第 5/6 行永远取不到 |
| 改 γ 曲线 | **不在 RTL**：`main.c:379`（`pow`）+ `gamma_lut.v:27-29,41-51` | PL 侧只有表；`γ×10` 只影响 OSD 那一格 |

---

## 20. 术语与编号约定

`ETH`/`SD`/`TEST` = 三种片源模式（`src_mode.v:3`：档名与屏上那三个词同源，编码是**格雷码环**
`00→01→11→10`）；`bank` = **DDR 里的整帧区**（不是 BRAM）；`lane` = §13.5 的健康选道；
`tap` = IDELAY 档（0-31）；`inv` = Q8 **倒数**尺度（数越大倍率越小，256 = 1.0×）；
`seam` = 分屏接缝（源坐标）；`skid` = 等长补偿移位链；`stale_row` = 帧首行窗口上一行落在上一帧的情况；
`#NNN` = `report/log/issues.md` 里的条目号；`rNNN` = 一次构建/实验轮次，产物在 `build/evidence/rNNN_*/`；
`实测` 只用于有原始日志/报告可读的情况，其余写 `机理`；`未找到` 必须附检索式。
`LATENCY`/`OFF_LINES`/`MIX_D`/`SB`/`SEAM_TAPS`/`RAW_LINES`/`BILIN_ROWS`/`LEFT_TAIL` 的关系图在 §9.1。

---

## 21. 常见误答纠正（**如果只读一节，读这一节**）

| 容易被问的问题 | 错误答案（别的 AI 常给的） | 本项目的实情 | 证据 |
|---|---|---|---|
| 帧缓存乒乓在哪里？ | "在两块 BRAM 里乒乓" | **乒乓在 DDR**（`0x1000_0000`/`0x1008_0000`）；显示侧 BRAM 是**一块双阵列**，靠消隐窗整帧拷贝 | §7.7、§8.5 |
| 用 PYNQ / Linux 吗？ | "跑 PYNQ 镜像，用 `Overlay()`" | **裸机**：`main.c` + `ps7_init`，JTAG 或 QSPI 自启；仓库里没有 Python 板端代码 | §14 |
| HDMI 怎么来的？ | "AXI UHD-PHY / TMDS IP" | **自研**：`tmds_encoder`(8b/10b) + `tmds_serializer`(2×OSERDESE2 10:1 DDR) + OBUFDS | §8.13 |
| TMDS 时钟通道有编码器吗？ | "有，和数据一样编码" | **没有**：`u_ser_clk` 的 `din` 是常量 `10'b1111100000`（且 `:48` 注释把它写成 `0x3FF` 是错的） | `rgb2dvi.v:48-51` |
| 为什么需要 5× 时钟？ | "5 倍是为了过采样" | `OSERDESE2 DATA_WIDTH=10` 在 DDR 下要 **5 个 FCLK 周期/符号** ⇒ `FCLK = 5×CLKDIV` 是**必然**，不是选择 | §8.13 |
| PHY 怎么配？ | "MDIO 读 ID、配模式" | **strap 配死**，`eth_mdio=z`、`eth_mdc=0`，数据面完全不碰 MDIO | `system_top.v:113-117` |
| RGMII 有输入延迟约束吗？ | "一般有 `set_input_delay`" | **一个都没有**（被 `check_timing` 点名 5 个口，HIGH）；这是**已知债** | §10.5 |
| WHS 的门禁是多少？ | 0.4 | **`WHS >= 0`**（`gates.sh:199`）；0.4 只是 `set_clock_uncertainty` 那条实验**自己给自己**的验收线 | §11.3 |
| 时钟源几颗 MMCM？ | 一颗 | **两颗**（同 module 两次例化，VCO 都 1000 MHz）；`system_top` 那颗**只出 200 MHz**给 IDELAYCTRL | §4.2 |
| 像素钟是哪颗给的？ | "顶层 `u_idelay_clkgen`" | `pl_video_top.u_clk`（MMCM#2）；顶层那颗的 `clk_pix/clk_pix5x` 接 `*_unused` | `system_top.v:119-125` |
| 灰度公式？ | `0.299R+0.587G+0.114B` 浮点，或 `>>8` 移位近似 | **整数乘加**：`r8*77 + g8*150 + b8*29`，取 `y16[15:8]` | `proc_gray.v:21-23` |
| box blur 怎么除 9？ | "除法器"或"可分离两趟" | **不可分离**（9 抽头直接相加），且用 **`*57 >> 9`**（57/512 ≈ 0.1113） | `proc_box_blur.v:116-132` |
| 卷积边界怎么补？ | 补零/补黑/环绕 | **clamp-to-edge：复制中心行/列**；帧首行"陈旧行"用当前行三行替换 | `proc_box_blur.v:101-113` |
| Sobel 幅值？ | `sqrt(gx²+gy²)` | **`|Gx|+|Gy|`**，然后夹到 255 | `proc_sobel.v:117-120` |
| gamma 怎么做？ | "PL 里算 `pow`" | **256 项表**（3 张分布式 RAM），曲线由 **PS 固件算好逐项下发**；PL 里 0 拍（组合读出） | `gamma_lut.v:1-7,27-29,51-52` |
| 旋转怎么做？ | "正向映射散写 + 24 位角度累加" | **逆映射**（屏幕→源）；角度是 **9 bit 十进制度 0..359**，三角表 360 项 Q8 硬编码 | `zoom_mapper.v:2`、`angle_ctrl.v:15`、`sin_rom.v:2-6` |
| 缩放倍率怎么存？ | 浮点倍率 | **Q8 倒数 `inv`**，八档表 1023/776/512/341/256/192/171/128；**运行时不做除法**（乘倒数常数） | `zoom_ctrl.v:44-53`、`zoom_fit.v:26-30` |
| 形态学支持开/闭？ | 支持 | **不支持**（单遍；`mode==3` 显式当旁路） | `proc_morph.v:23-25` |
| `set_clock_groups` 写主 XDC 行不行？ | 行 | **不行**：综合期 `clk_fpga_0` 不存在 ⇒ `Vivado 12-4739` + **整条命令空转**，连带废掉另两组；XDC 里又不准 `if` | `rk_zynq7020.xdc:62-75` |
| `-quiet` 能救 `get_clocks` 取不到的名字吗？ | 能 | **不能**：`-quiet` 只压报错、不救命令本身 | 同上 |
| 跨域靠 `set_max_delay` 吗？ | 一般这么做 | **现役不靠**：加载的两份 XDC 无 `set_max_delay`/`set_multicycle_path`/`create_generated_clock`；跨域一律 FIFO/翻转/3FF。⚠ 但禁用集 `r114_io_async.xdc:57-63` 写了四条 `set_max_delay -datapath_only` 作为**未采纳的替代方案** | §6、§10.4 |
| 仲裁是不是"哪边有数据就给哪边"？ | 是 | **不是**：判据是"哪边**活着** + 现在能不能**安全换手**"，换手只在 `both_idle` 发生 | `src_arb.v:4,66-76` |
| 仲裁是状态机吗？ | 通常有 FSM | **没有 FSM**：1 bit 主人位 + 一个 32 bit 饱和计数器 | `src_arb.v:31,47,53-78` |
| 切到 SD 会立刻生效吗？ | 立刻 | 要等 **ETH 静默 20 ms**（`T_OFF_CYC` @100 MHz）**且**两个引擎都空闲；第一级滞回是 `stall_ms > 200 ms` | `src_arb.v:18-19` |
| 拔网线会回图卡吗？ | 会/不会都行 | 需要 `eth_tb_ok`：**断链时 RTL8211 不停 RXC 而是拉到 ≈2.5 MHz**，只看 `stall_ms` 会连着骗人十几秒 | `src_arb.v:11-14`、`system_top.v:252-256` |
| 位流哈希相同能证明什么？ | 能证明同一版 RTL | 反过来才对：**哈希相同能证明是同一次写的，哈希不同什么都证明不了**（同一份布线隔 3 秒连写两次长度都相同、md5 不同，逐字节只差 3 处 = 头里的日期与时刻） | 本仓 §哈希条目 |
| 板子上读回走串口吗？ | 走 | **不走**：lane 读回用 JTAG（`mrd/mwr`），固件从不写 `[31:27]` | `src/ps/README.md:12`、§13.5 |
| 能读 `status[31:0]` 吗？ | 能 | **不能**：有驱动无负载，综合剪掉 | §13.6 |
| 加大 CDC 缓冲能治丢字吗？ | 能 | **不能**：瓶颈是平均排空速率（≈20 MB/s），"把 CDC 做到 8192 时上板毫无改善" | `axi_frame_saver64.v:7-8` |
| 换实现策略能救时序吗？ | 通常可以 | 实测 `Performance_Explore` 与未指定策略**逐位相同**（0.499/0.060/0-21253），而且扫描因非法选项**只跑了一档** | §11.1 |
| 综合出来的时序数字算收敛吗？ | 算 | **不算**：只有 routed 之后算；两者数字不同是常态 | §17 第 1 项 |
| 仿真全绿能证明 CDC 对吗？ | 能 | **不能**："RTL 仿真没有门延迟"，CDC 判据是**结构判据** | `eth_udp_video_top.v:373-380` |

---

## 22. 这份文档没写的东西（诚实清单）

被问到以下任一项，正确答案是"**仓库里没有可支持的读数**"，而不是推测：

1. **任何真板上的现象/读数**：无板在场。本文所有"板上会看到"都标 `机理`。需要板子的具体项：
   SD 热插拔的 30 次是否够、`[SD] remount failed` 的真实复现率、γ 表掉沿的实际可见性、
   IDELAY tap 31 在硅片上是否真的最好（§11.5 明确"那是报告里最好"）、#167/#168 的 ≥127 字符注入、
   `ddr_verify`/`health_read`/`arb_handover_test` 的实跑结果（`data/measured/one_click_*.out` 需真板跑，
   **仓库里没有**）。
2. **板级功耗/电流实测值**：只有 Vivado 估算（§12.3）。
3. **HDMI 接收端时序窗的数值出处**：本仓 `未找到`，所以故意没写 `set_output_delay`（§10.4）。
4. **"为什么选逆映射"、"为什么用 MMCM 不用 PLL"的成文理由**：两处都是 `未找到` 注释
   （检索式 `forward|scatter|hole`、`PLLE2|为什么.*MMCM`）。可以陈述实现事实与代价，不能声称"文档里写了理由"。
5. **Vivado 默认实现策略的名字**：工程里没留下该字符串、报告也没记录（`sweep_summary.txt` 原文）。
6. **`lat_clamp` 的精确谓词**、**`dbg_zoom` 的逐位含义**（只给到 20 bit 打包式与 `:688` 的组合点）、
   **`ingress_probe` 的"每级一个计数器"读法**（不存在）——引用前先读源码，别按本文推。
7. **本文行号的时效**：它们对应 2026-10-15 的工作树。任何"行号找不到"都应先用每节末的命令重取，
   而不是改写结论。

—— 全文完。文档自身由 `build/gates.sh` 第 20 项（`line_cite_check.mjs`，命中 `>= 300`、硬错 0）
与第 17/18 项（编码、时效）覆盖；改这份文件后请重跑那两支。




