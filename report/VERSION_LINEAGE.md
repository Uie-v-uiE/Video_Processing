# 版本谱系与问题处置记录（V1 → 现在）

本文是把**远程分支 + 三个本地快照目录 + 仓库内既有记录**对齐之后写成的唯一谱系表。
每条结论都给可核对的坐标：commit SHA、`文件:行`、或报告里的数字。
与其它文档的分工：机理细节在 `V6_ROOT_CAUSE.md`，板级数字在 `V6_BOARD_MEASUREMENT.md`，
本夜改动在 `OVERNIGHT_LOG.md`；**本文只回答「哪一版是什么、当时卡在哪、怎么解的」**。

---

## 1. 谱系总览

| 阶段 | 远程位置 | tip / 关键 SHA | 日期 | 一句话 |
|------|----------|----------------|------|--------|
| V1 初版 | 分支 `v1-ps-ethernet`（7 个提交） | `7588ecb` | 09-11 → 09-14 | **PS 以太网**（lwIP UDP→PS→DDR），PL 做特效/旋转，HDMI 双窗 |
| V2 第二版 | 分支 `v2-pl-ethernet`（9 个提交） | `4d6576f` | 09-14 | **以太网搬进 PL**（自研 RGMII/ARP/ICMP/UDP），修掉旋转×窗滤不兼容，自建 FIFO；**拖影出现并被"接受"** |
| V3 第三版 | `main` 的父提交链（**没有独立分支**） | `fc314bb`（缩放首现）/ `7cde28d`（v3 文档） | 09-18 | 增加**右屏连续（无极）缩放**；拖影**仍未修好**（见 §4） |
| V4 第四版 | `main` | `f911527`(V6.3) … `647160e`(V6.4) | 09-21 | 找到并修掉**真正根因**：入包写通道逐字等 B ⇒ 固定相位丢字；随后按 lane 生成 WSTRB 除黑点 |
| V5 本夜 | 仅本地（未推） | `8c30d9c` `242f6e7` `ff7c890` `a22a054` … | 09-22 | 三次综合行为改造（LUTRAM/BRAM 分块）+ 换页判据修帧尾残留；BRAM/寄存器/Slice 全部门禁转绿 |

分支间关系：`v1 ⊂ v2`（前 6 个提交相同，`c6f715a` 是分叉点）；`main` 与 v1/v2 **不同源**（是重新组织过的仓库，
`README.md` 的版本说明里写明 V1 来自 `Zynq_Video_Pipeline`、V2 来自 `Video_Pipeline` 两个旧仓库名）。

---

## 2. 逐阶段：问题 → 定位 → 方案 → 证据

### V1：旋转与窗口滤波不兼容（用户口中的"旋转时几个效果无法保持"）

- **问题**：`angle≠0` 时 blur/sobel 出错图甚至花屏。
- **当时的处置（V1 是"关功能"而不是"修功能"）**：旋转时**自动旁路** blur/sobel，
  灰度/二值/反色因为是点运算所以保留。证据：`origin/v1-ps-ethernet:docs/ROTATION_AND_EFFECTS.md`
  的表（1–359° 行里 gray✓ binary✓ **blur✗自动关 sobel✗自动关** invert✓），
  实现 `rtl/process/proc_pipeline.v:24-25`：`wire by2 = ~effect_en[2] | rotate_active;`。
- **根因（同文档写明）**：窗滤要的是**源图扫描顺序上的 3×3 邻域**，而旋转是**逆映射**
  （屏幕上每点反算 `(sx,sy)`），于是邻域像素在源图里不再连续 ⇒ 窗口不成立。
- **解法（V2 落地）**：把 3×3 窗口建在**目标域**（右窗光栅顺序）上，
  即"源像素(映射后) → 点运算 → 目标域 3×3 → 右窗输出"。
  证据：`origin/v2-pl-ethernet:src/rtl/process/proc_pipeline.v:12`
  `input wire rotate_active, // retained for status; window filters run in target domain`，
  且 `:26-27` 已**没有** `| rotate_active` 旁路；方案对比与"方案 B（多路 BRAM 口）7020 放不下"记在
  `report/PS_VS_PL.md` §2.1/2.2；测试 `sim/tb_rotate_window.v`。
- **V1 其它已入库问题**（`origin/v1-ps-ethernet:docs/ISSUES.md` 19 条，摘最相关的）：
  EMIO GPIO 读回恒 0 → 改 GP0 轴 GPIO `0x41200000`；PHY 自协商失败 → BSP 固定速率；
  AXI 每 beat 只写 1 像素导致 HDMI 窄条；行地址 12 位左移溢出；32bit 半字对调导致发糊；UDP 乱序导致帧错位。

### V2：以太网搬到 PL + 自建 FIFO；拖影出现

- **搬 PL 的实现**：`src/rtl/eth/` 下全手写 —— `rgmii_rx.v`(IDELAYE2)、`gmii_to_rgmii.v`、
  `arp_rx/arp_tx`、`icmp_rx/icmp_tx`、`udp_rx`、`crc32_d8.v`、`eth_ctrl.v`、`frame_reasm.v`；
  PS 侧退化为纯控制面（`src/ps/main.c`：`UDP video data path is handled entirely in PL`），
  无 lwIP/GEM 收包。判据文档 `report/PS_VS_PL.md:5` 「PS GEM0 + lwIP → PL RGMII PHY2」。
- **自建 FIFO**：`eth/sync_fifo.v`（指针式）+ `eth/dc_fifo.v:2,25-27`（格雷码双时钟），
  全仓 **零** `xpm_fifo`/FIFO Generator IP。
- **拖影（新问题）**：`origin/v2-pl-ethernet:report/ISSUES.md` #13 原文——
  现象「人走后原位置仍有颜色拖影」；原因「UDP 边收边写显示 BRAM，旧像素未被覆盖」；
  尝试「BRAM 双缓冲 `frame_buffer_db` —— **7020 BRAM/LUT 爆资源，实现失败**」；
  现状「恢复 ETH 直写 BRAM（画面正确）；**拖影可接受**」。
  ⇒ **V2 没有解决拖影**，只是把它记在账上。

### V3：无极缩放；拖影**没**修好（重要更正，见 §4）

- 缩放首现于 `fc314bb`（09-18）。`src/rtl/process/zoom/zoom_mapper.v` 用 **Q8 定点 `inv_scale`**
  （`256=1.0×，512=0.5×`）⇒ 256..512 连续可调，即"无极/连续缩放"，叠加在右窗旋转之后。
- 同期文档 `origin/main` 的 `report/ROTATION_AND_EFFECTS.md`（标题即"第三版"）：
  旋转 0–359° × 五级效果 × 右屏缩放可**同时开**，目标域窗滤已成事实。

### V4：拖影的真正根因与修复（V6.1 → V6.4）

- **量化起点**：`report/CHANGELOG_V6.md` §0 —— 用自描述图案 `frameid`（像素值 = 字号 + 帧号）回读，
  第三版**最新帧只占 42~52%**；`wordid` 恒定图案下"100% 命中"是假象。
- **根因**：`axi_frame_saver64` 每写一个 64bit 字都要等 AXI 写响应 B ⇒ 在途深度恒 1，
  吞吐被 HP0 往返延迟钉死在 ≈20 MB/s；显示拷贝一抢端口就低于主机速率 ⇒
  **每个包从第 48 字节起按 16bit 粒度丢弃**（表现为拖影/黑横纹/撕裂）。
- **V6.0–V6.2 是被证伪的方向**（提交门限、读侧节流、加深 CDC）——记录保留，明确标注"方向错误"。
- **V6.3 `f911527`**：写通道流水化（AW/W 同拍挂出、`OST=8`、B 只回收计数）⇒
  板级回读**最新帧 100.0%**，包内各字节带丢字率 0.0%（15/30/60 fps 三档）。
- **V6.4 `a91e83b`**：`WSTRB` 由恒 `0xFF` 改成按 16bit lane 生成 ⇒
  分包长度不再是 8 的倍数时不会互相覆盖（1396 B 实测每帧 111 处 4 字节黑洞 → 0；
  仿真 `+MISALIGN` 修复前 38290/38400）。

### V5（本夜，未推）：资源死结 + 一处新缺陷

- R02 打包 FIFO 触发器→分布式 RAM（`Reg 51.30%→9.02%`）；R04 帧缓存按 2 的幂分块
  （`BRAM 98.93%→64.64%`，元凶是地址空间被填充到 2^16）；R05 显示侧 skid 同样处理（`Reg→4.08%`）；
  R03 换页判据补上「等本帧数据穿过 CDC」（帧尾 4 字节残留）。
  数字、判据与否决项全在 `OVERNIGHT_LOG.md`。**板级 22 轮复验：15→36 MB/s 全程每 bank 恰好一帧、逐 lane 100%。**

---

## 3. 三个本地目录到底是什么（它们不是"版本"，是同一条拖影攻关链上的四次快照）

| 本地路径 | 对应阶段 | 判据 |
|----------|----------|------|
| `D:\Xilinx\Prj\video_pl\zynq_video_pipeline\` | **就是 V2 本体** | 是 git 仓库，remote `git@github.com:Uie-v-uiE/Video_Pipeline.git`，HEAD `4d6576f` = 远程分支 `v2-pl-ethernet` 的 tip（同 SHA，逐字节同一份）。bit 09-14 11:21，**WNS −6.158 / 32 失败端点**（当时时序没收敛），单活缓冲、无缩放 |
| `D:\Xilinx\Prj\video_pl\zynq_video_pipeline_noghost\` | **拖影攻关第 1 次尝试：DDR 三槽位管理器** | 无 `.git`；新增 `src/rtl/video/frame_buffer_manager.v`（`NUM_SLOTS=3`、`SLOT_BASE=0x1000_0000`、`SLOT_STRIDE=0x100_0000`、FREE/RX/READY/DISP/INVALID 五态）+ `tb_fbm/tb_pingpong/tb_ddr_roundtrip`；文档 `DDR_MULTI_SLOT_FBM.md`、`DDR_DUALBUF_ANALYSIS.md`。bit 09-15 18:14，**BRAM 134/140 = 95.71%**、WNS −6.403 ⇒ 撞资源墙 |
| `D:\Xilinx\Prj\noghost\Video_Pipeline-main\` | **第 2 次尝试：DDR 双 bank 乒乓（未完成即被搁下）** | 无 `.git`（GitHub zip 解包）。乒乓与"排空后才提交"确实在 `eth_udp_video_top.v:216,228-236`；**但 ETH 分支上读回被写死关闭**：`pl_video_top.v:190 wire writer_en = el1 ? 1'b0 : src_use_axi;`、`:238 assign kick_copy = el1 ? 1'b0 : src_use;`、`:315 fb_wr_en = eth_link ? eth_wr_axi : aw_wr_en;` ⇒ 显示 BRAM 仍是被 UDP 直写，**拖影不可能被这一版修好**。`report/CONSULT_BRIEF.md`（09-17 23:43）自述「上板表现为更严重的花屏卡顿」 |
| `D:\Xilinx\Prj\fix\Video_Pipeline-main\` | **同上的收口版（时序收敛）** | 内容与 `noghost` 同族（其 `CONSULT_BRIEF.md:13` 直接写的是 noghost 路径）；bit 09-18 23:34 **WNS +0.201、0 失败端点**、BRAM 回到 84/140=60%；saver 仍叫 `axi_frame_saver`（AWLEN=0、逐字等 B），**无缩放** ⇒ 这是 V3 打包（09-18 `fc314bb`）之前的最后一次攻关状态 |

**从未进入任何 git 历史的资产**（要做"历史分支补全"时必须知道）：
`frame_buffer_manager.v`（三槽位方案）、`DDR_MULTI_SLOT_FBM.md`、`DDR_DUALBUF_ANALYSIS.md`、
`CONSULT_BRIEF.md`、`tb_fbm/tb_pingpong/tb_ddr_roundtrip/tb_saver_writer/tb_seq_saver/tb_fbdb/tb_dma_latency`
（核验命令：`git log --all --diff-filter=A -- '*frame_buffer_manager*'` → 空）。

---

## 4. 与口头叙述的两处不一致（以仓库内证据为准）

1. **「第三版…修复了拖影」不成立。** 仓库自己的 `report/CHANGELOG_V6.md` §0 标题就是
   「起点：**第三版的状态与症状**」，表里列的正是「红块移动的地方有拖影」「静止时仍然撕裂」
   「冻结之后仍然是撕裂的」，并给出量化：第三版 frameid 判据下**最新帧仅 42~52%**。
   拖影是**第四版 V6.3**（`f911527`）修掉的，且修的不是显示侧切换而是入包链丢字。
2. **V1 的"效果保不住"不是 bug 被修，而是功能被旁路。** V1 的处理是旋转时强制关 blur/sobel；
   真正的修复（目标域窗滤）落在 **V2**。所以「修复滤波兼容」这件事属于第二版，与口头叙述一致 ✔。

（另外三处一致 ✔：V1=PS 以太网；V2=搬到 PL + 自建 FIFO + 修窗滤；V3=无极缩放。）
---

## 5. V7.8（双线性插值）在谱系里的位置 —— 2026-09-23 04:1x

**它不是一个发布版本，是一次未合入的开发。**

| 位置 | 内容 | 证据 |
|---|---|---|
| tag `v7.8-bilinear-wip` = 提交 `0d02c2e`（本地） | 双线性全套：`bilin_lerp` 算术核、`tap_sched` 五槽调度、`fb_rd5x` 端到端、顶层配准常数由 RD_LAT 推导、`zoom_mapper` 旋转分支小数、`BILIN0/1` 运行时开关 | L1 台架：`sim/results/regression_v78_r21.txt`（回退主线后仍 37/37，两个 bilin 台架在内） |
| 构建 `build/failed_r19b/`（WNS −1.277）与 `build/failed_r24/`（−0.327，**功能上就是 V7.8**） | 三版门禁数字的出处 | 各自 `MANIFEST.txt` + 本文表格 |
| 主线 `dev/night-2026-09-22` 的 HEAD | 顶层与几何 = **c9ab9a3（V7.7 / build#13）**，残留差异三条且均为惰性 | `git diff --name-status c9ab9a3 -- src/rtl` |

口径：**远程 `main` 与 GitHub 上没有 V7.8 的任何东西**（按用户要求今晚不推）；对外也不能写"板上已有双线性"。

---

## 6. V7.9（两笔 CDC 账 + KU5P 会说话）在谱系里的位置 —— 2026-09-23 05:5x

**它是一个真发布版本，但功能面零变化**：主线只多了三类正确性收紧（`eth_link` 同步、
`effect_ctrl` 的 `ASYNC_REG`、`copy_abort` 翻转式同步），KU5P 那半边多了一个新能力。

| 位置 | 内容 | 证据 |
|---|---|---|
| 分支 `dev/night-2026-09-22`（本地，**未推**） | V7.7 功能 + V7.9 的三笔正确性收紧 + KU5P 遥测/仲裁器 | `git log`；门禁数字唯一出处是 `report/CHANGELOG_V7.md` 的 V7.9 表（本文件**不重复抄数字**，避免两处漂移） |
| tag `v7.8-bilinear-wip` | V7.8 全套（未合入的开发） | 见 §5 |
| 主线默认 bit | 由本次夜间构建的**门禁结果**决定：全绿用最新一次（build#18），任何一条红就退回 `build/frozen_r17_cdc/`（md5 `11998af8`），再不行退回 `build/frozen_r13/`（`0f46ec91`） | `md5sum build/system.bit` 对 `build/frozen_*/MANIFEST.txt` |
| KU5P 子工程 | `ku5p/build/ku5p_eth.bit` + 报告成套冻结在 `ku5p/build/frozen_r23/`（含 bit 的 md5，二进制不入库） | `ku5p/README.md` §1 表 + `ku5p/build/frozen_r23/MANIFEST.txt` |

**"两套代码、一个顶层家族"这件事要说清**：`ku5p/src/rtl/` 下的 `gmii_to_rgmii/rgmii_rx/rgmii_tx`
与 `src/rtl/eth/` 下的同名文件是**同一层的两种器件写法**（7 系列 `IDELAYE2+IDDR` vs
UltraScale+ `IDDRE1+BUFIO`），不是副本也不是分叉 —— 所以它们不能出现在同一次 xvlog/综合里，
全量回归脚本只显式加入 KU5P 自研的那几个模块（R31 起是三个：`ku5p_telem` / `ku5p_tx_arb` /
`ku5p_cmd`；理由与"加新模块要两处清单一起改"的坑都写在 `sim/run_sim.tcl` 的注释里）。

**下一步（明天之后）在谱系里的落点**：`ISSUES.md` #37（厂商 mux 的 `||`→`&&` + `arp_pend` 记账位）
**已在 v7.9 走完整条链**（改 RTL → L1 全量 40/40 → L3 门禁 → 冻结 `frozen_r19_*`）；
#38（把自研 `gmii_rx_mac + udp_rx_parser` 换上顶层，顺带解决目的端口过滤）仍未做，
它要走的是同一条完整链 —— 不能借一次顺手改就带进主线。

## 7. V7.9 之后那三夜（R29–R31）在谱系里的位置 —— 2026-09-23 深夜

| 位置 | 内容 | 证据（数字的唯一出处仍是 `report/CHANGELOG_V7.md`） |
|---|---|---|
| 主线默认 bit **仍是 build#23**（`build/frozen_r23_srcseen/`，md5 `18443ffd`） | SD 卡本地回放**已经上屏**（用户眼睛确认）⇒ P1 板级完整；这一版是"能演示"的那一版 | `report/OVERNIGHT_LOG.md` §19；`board/evidence_r29/` |
| `build/frozen_r24_srcarb/`（`696a5271`）**留作反例**，不是候选 | 片源仲裁第一版：七项门禁全绿、L1 44/44，**板级判据红**（停流不交回画面） | 它的 `MANIFEST.txt` 里写清了哪一条红、为什么红 |
| `build/frozen_r25_arbfix/`（`ad4aa31c`）= **候选默认** | 仲裁修正版（判据要与时基健康相与，见 `ISSUES.md` #49）；**两条眼睛判据未过之前不改默认** | `board/README.md` "需要肉眼确认的项" 第 7/8 行 |
| KU5P 子工程（R31 命令通道） | 从"只会上报"变成**双向**：`ku5p_cmd.v`(端口 5002, `CLR/SNAP/SPD<n>`) + 遥测载荷 v0x01→**v0x02**（36→42 字节）。台架级，未上板 | `ku5p/README.md` §1/§8/§9；`sim/tb_v80_ku5p_cmd.v`；`src/host/ku5p_cmd.mjs --selftest` |

**版本声明里必须一起说的三件事**（避免"v7.9"被读成"全做完了"）：
① 主线双线性插值仍是 tag `v7.8-bilinear-wip`，**没有**进任何默认位流；
② KU5P 全部能力都还是台架级（这块板从没通过 JTAG 跑过一次）；
③ `build#24` 那一类"门禁全绿但板上不工作"的教训说明：**绿只覆盖它能覆盖的性质**，
   所以每一版都在 MANIFEST 里写清"这一版的判据是谁、还没验的是哪一条"。


## 8. 2026-09-24 00:00–01:30 这一批：**用 md5 认版，不叫我心里的编号**

这一段我犯了个值得写下来的错：为了赶进度，我在上一版构建还没结束时又起了新构建，
于是"build#30 / #31"这些口头编号和磁盘上的产物**对不上了**（`create_project -force`
会把 `*.runs` 删掉重建，先起的那个会被后起的顶掉并报 `SYNTH FAILED Scripts Generated`）。
所以下表**只认 md5 与报告里的 `Date` 行**，编号仅作参考。

| 产物 md5(system.bit) | 内容 | 门禁（新 CDC 判据） | 板级 |
|---|---|---|---|
| `dd9384b2`（#26） | lane30 六位（含像素域 mode/ps_src_seen 的第二对同步器）+ 图卡 + 长按 + 自动播固件 | 旧脚本判"ALL PASS"，**新脚本判红**（新增配对 `clkout0_1>clk_fpga_0`） | 交接判据未跑 |
| `a6108921`（#27） | 撤掉那两位（`dbg_src` 缩到三位） | **仍红**（同一配对，5 端点 / 2 unsafe）—— 说明元凶不是观测口 | 未跑 |
| `c65b547d`（#28） | 再加 `(* fsm_encoding = "none" *)` | **绿**（该配对降为 Warning、0 unsafe；Critical 回到 3 行）WNS +1.001 | **跑了：V1/V4/V5 红** ⇒ 定位到 ISSUES #52 |
| `bec90dd1`（00:54 写盘） | 再把格雷环下一状态写成按位式 `{mode[0], ~mode[1]}` | 绿（同上，端点 23836） | 未跑（被下一版取代） |
| `efc89779`（01:19 写盘，**= `build/frozen_r31_srcmode/`**） | 长按→模式搬进 `src/rtl/util/src_mode.v`（链复位 0 + 复位后 8 拍灌满期）+ 新台架 `tb_v82_src_mode`（12 条）+ `lane30` 从 3 位扩到 8 位（仲裁看到的模式与两个 busy，全在 axi 域 ⇒ 不交跨域税） | **绿**：WNS +0.764 / WHS +0.062 / 23840 端点 / LUT 7577 / Reg 6026 / 2.159 W / cdc Critical 3 行无新增配对 | **七条交接判据全绿**：接管 150 ms、**停流 285 ms 交回**、0 抖动、再推 180 ms 可逆（`arb_handover_green_r31.json`） |
| **bit 仍是 `efc89779`**，elf `c00b6553`（06:0x，**= `build/frozen_r32_sdfix/`**） | **只改 PS 固件**：`sd_play.c` 的 `dir_lookup` 高簇字改回小端（`clus_of()`）+ 失败行打印几何量 + `dir_selftest()` 与挂载时逐文件簇界核对 | 位流没动 ⇒ 门禁数字**全部继承上一行**，不重报一遍（免得同一份报告以两个 md5 存在两处） | ISSUES #50 结案：`FRAME3584` 由 `OUT-OF-RANGE` 变可播，**整卡 4398 帧第一次播完并回绕**；判据反例（把字节序改回去 → 挂载被拒）见本目录凭据 |

**为什么必须这样记账**：01:0x 那一段时间里有**两个构建在抢同一个工程目录**
（`create_project -force` 会删掉 `*.runs`，先起的会被后起的顶掉并报 `SYNTH FAILED Scripts Generated`），
于是"build#30/#31"这类口头编号和磁盘产物对不上了。
从这一版起的规矩：**报数字先报 md5**，编号只用来称呼 RTL 的修订；
并且 MANIFEST 里留一个"这块 bit 里确实是新逻辑"的可核对指纹
（`cdc_details.rpt` 里的实例名 `u_pl/u_mode/mode_reg` —— 旧写法是 `FSM_onehot_mode_reg`）。


**规矩补一条**（`build/gates.sh` 已实现，不用靠自觉）：门禁现在会额外检查
"**有没有 RTL 源文件比 `system.bit` 新**"，有就 WARN —— 专治"改完没重跑就念上一版产物"。
