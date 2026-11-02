# interface-contract.md · 寄存器与数据接口契约（人读版）

读完这篇你能回答哪三个问题：

1. PS 与 PL 之间到底约定了哪几个地址、每一位是什么意思、越界写会怎样？
2. 上位机与板子之间的包形是什么？哪几个数是"三处必须一致"的？
3. 这份人读表与机器可读表（代码里的宏、`report/commands.md`）冲突时，以谁为准、怎么发现冲突？

## 目录

- 第 1 节 口径与正本
- 第 2 节 地址映射（四个从设备 + 三块 DDR）
- 第 3 节 GPIO_0（`0x41200000`）位表
- 第 4 节 GPIO_1（`0x41210000`）lane 表
- 第 5 节 CFG_DATA0 / CFG_DATA1（`0x41220000` / `+0x08`）位表
- 第 6 节 UDP 包形与网络身份
- 第 7 节 握手与"没有中断"这件事
- 第 8 节 一致性的机器判据
- 第 9 节 小结与下一步
- 第 10 节 自测题

## 第 1 节 口径与正本

- **正本优先**：位序的唯一出处是代码里的宏定义与 RTL 端口注释。本文是**人读版**，
  与它们冲突时以它们为准（这条是本目录的硬口径，写在 `README.md` 的第 3 节）。
- **不复制命令表**：串口命令的表、语法与回显文案在 `report/commands.md`（正本），本文只登记
  "命令改的是哪一位"。理由：同一个设置抄在两处一定会漂 —— 本仓库为这类病记过账
  （`src/rtl/top/pl_video_top.v:221-226` 那段"抄两遍就是 #66 那一族的病"）。
- **三个层各有一处定义**：固件侧 `src/ps/main.c:38-107`；顶层侧
  `src/rtl/top/system_top.v:136-145` 与 `src/rtl/top/pl_video_top.v:48-57`；生成侧地址钉死在
  `build/tcl/build_system_axigpio.tcl:213-221`。

小结 1：本文的每一行都能回溯到上面四处之一；找不到出处的一律不写进这张表。
小结 2：想知道"命令怎么说"去看 `report/commands.md`；想知道"位真的接上没有"看本文第 3、5 节。下一步：第 2 节。

## 第 2 节 地址映射

| 地址 | 对象 | 方向 | 谁写 / 谁读 | 出处 |
|---|---|---|---|---|
| `0x41200000` | `axi_gpio_0`（32 位纯输出） | PS→PL | 固件 `ctrl_write()` 写（`src/ps/main.c:219`） | 钉址 `build/tcl/build_system_axigpio.tcl:214` |
| `0x41210000` | `axi_gpio_1`（32 位纯输入） | PL→PS | 固件/上位机读（`src/host/health_read.mjs:34-35`） | 同文件 `:215` |
| `0x41220000` | `axi_gpio_2` 通道 1 = `CFG_DATA0` | PS→PL | 固件写（`src/ps/main.c:223`） | 同文件 `:216` |
| `0x41220008` | `axi_gpio_2` 通道 2 = `CFG_DATA1`（gamma 窗口） | PS→PL | 固件写（`src/ps/main.c:96` 定义偏移） | 同文件 `:216`（一个 64K 段覆盖两个通道） |
| `0x1000_0000` | ETH 帧 bank0 | PL 写 / PL 读 | `u_saver` 写、`u_row` 读 | `src/rtl/top/system_top.v:139`、`src/rtl/eth/eth_udp_video_top.v:67` |
| `0x1008_0000` | ETH 帧 bank1（乒乓的另一块） | 同上 | 同上 | `src/rtl/eth/eth_udp_video_top.v:68` |
| `0x1010_0000` | PS 专用第三块 bank | PS 的 DMA 写 / PL 读 | `u_aw` 读 | `src/rtl/top/system_top.v:144`、`src/ps/sd_play.c:35`、`src/ps/main.c:46` |

**三处必须一致的数**：`0x1010_0000` 同时写在 RTL 与两份固件代码里，
不一致时**不会编译失败**，现象是"PS 片源在屏上不动"（原文警告：`src/rtl/top/system_top.v:142-144`）。

小结 1：PS 与 PL 之间的全部契约就是这 4 个寄存器加 3 块内存，没有第四种通道。
小结 2：地址是硬编码的，所以"写了没反应"要先怀疑地址而不是怀疑逻辑（理由见 `src/ps/main.c:70-76`）。下一步：第 3 节。

## 第 3 节 GPIO_0（`0x41200000`）位表

固件整字合成式在 `src/ps/main.c:214-219`，PL 侧取位在 `src/rtl/top/system_top.v:264-293`。

| 位 | 名字 | 语义 | PL 侧消费者 | 越界/非法写会怎样 |
|---|---|---|---|---|
| `[4:0]` | 保留 | V7 那五位效果使能已退役，固件**恒写 0** | 不接（`src/rtl/top/system_top.v:262-263`） | 无效果；位序留着是为了不打乱按位写的工具 |
| `[15:8]` | `threshold` | 二值化阈值 | `src/rtl/top/pl_video_top.v:31`、`:204` | 无"非法"：任何 8 位值都是一个阈值 |
| `[16]` | `src_sel` | 图卡 / 帧缓存二选一（AUTO 下才有效） | `src/rtl/top/pl_video_top.v:36`、`:476` | 只在 AUTO 模式被听，锁住时不生效 |
| `[17]` | `zoom_en` | 呼吸缩放开停 | `src/rtl/top/system_top.v:280` → `:212-221` 同步 | 复位默认 1（`ZOOM_DEFAULT_ON`，`src/rtl/top/pl_video_top.v:17`、`:215-217`） |
| `[18]` | `ps_publish` | **翻转位**：翻一次 = 请求搬一帧 | `src/rtl/top/pl_video_top.v:564-566` | 当电平连续写不会多搬（`src/rtl/util/ps_publish.v:6-8` 的合并语义） |
| `[19]` | `bilin_en` | 双线性 / 最近邻 | `src/rtl/top/system_top.v:286` | 复位默认 1（`src/rtl/top/pl_video_top.v:254-261`） |
| `[20]` | `osd_off` | **反相**：1 = 关叠层 | `src/rtl/top/system_top.v:287`、`src/ps/main.c:57` | 复位 0 = 有 OSD，所以"忘了写"不会变干净屏 |
| `[21]`、`[25]` | 保留 | 定表时留给以后 | — | — |
| `[22]` | `mode_tog` | 翻转位：翻一次 = 下面的码是新写的 | `src/rtl/top/pl_video_top.v:293` | 不翻位只改码 ⇒ 码不被采纳（顺序约定在 `src/rtl/top/pl_video_top.v:289-291`） |
| `[24:23]` | `mode_ovr` | 00 自动 / 01 ETH / 11 SD / 10 TEST | `src/rtl/util/src_mode.v:15-16` | 写 11 之外的组合按四态码解释；屏上只印三个词 |
| `[26]` | `gapclr_sel` | 测量前把帧间隔统计归零 | `src/rtl/top/system_top.v:203` → `src/rtl/eth/eth_udp_video_top.v:277-281` | 是**电平**不是脉冲（同文件 `:275-276`） |
| `[31:27]` | lane 号 | 选一条 32 位健康字给 GPIO_1 | `src/rtl/top/system_top.v:219` | 越界 lane 返回 `32'hDEAD_BEEF`（`:244`） |

⚠ 这一只 GPIO 被**两个方向**共用：`[31:27]` 是"写 lane 号"，而 GPIO_1 是"读那一条"。
所以 `health_read.mjs` 必须先把原值读回来、只改这 5 位、读完再写回去
（做法在 `src/host/health_read.mjs:6-8`）。

小结 1：这一只 32 位寄存器的位表有 12 行，其中三行是**翻转位**语义（`[18]`、`[22]`、`[26]` 里前两个）。
小结 2：写它必须整字写，读-改-写会踩"每帧重写把别的位抹掉"那个坑（`src/ps/main.c:94-95`）。下一步：第 4 节。

## 第 4 节 GPIO_1（`0x41210000`）lane 表

读法：先写 lane 号，再从这只只读 GPIO 取一条 32 位。mux 的组合式在
`src/rtl/top/system_top.v:237-246`。

| lane | 内容 | 单位 | 位序出处 |
|---|---|---|---|
| 0 | `drop_words` 被 FIFO 满吃掉的字 | 个 | `src/rtl/eth/link_monitor.v:187` |
| 1 | 高 16 = 坏包，低 16 = 作废帧 | 个 | `:188` |
| 2 | 高 16 = 最大缺行，低 16 = 已断流 ms | 个 / ms | `:189` |
| 3 | 最近一帧间隔 | ms | `:190` |
| 4 | 间隔 min（低 16）/ max（高 16） | ms | `:191` |
| 5 | Σ间隔 | ms | `:192` |
| 6 | CDC 灌满次数 | 次 | `:193` |
| 7 | 标志五位 `flag5` | 位 | `:158-162` |
| 8 / 9 | 收到的包数 / 有效字节数 | 个 / B | `:195-196` |
| 23 | 像素域真的在用的缩放状态 | 位 | `src/rtl/top/pl_video_top.v:679-688` |
| 24 | `q_ms`（与 lane27 同一轮） | ms | `src/rtl/top/pl_video_top.v:636-642` |
| 25 | `{n_meas, clamped}` | 次 / 位 | 同上 |
| 26..29 | `max` / `tot` / `c2` / `c1` | **拍数** | 同上；换算在 `src/host/health_read.mjs`（`src/rtl/top/pl_video_top.v:71`） |
| 30 | 仲裁状态 16 位（含 `why_ps`） | 位 | `src/rtl/top/pl_video_top.v:67`、`:603` |
| 31 | `{30'd0, hb_slow, hb_gone}` | 位 | `src/rtl/top/system_top.v:209-211`、`:238` |
| 10..22 | 未定义 | — | 返回 `32'hDEAD_BEEF`（`src/rtl/top/system_top.v:244`） |

三条使用纪律，全部来自代码里的警告：

1. **读 25..29 必须按 25→26→27→28→29 的顺序**：lane25 既给"轮次/钳位位"也是那组快照的武装位
   （`src/rtl/top/system_top.v:232-236`）。逐 lane 各读各的会读到不同轮，恒等式 `tot ≥ c1 + c2` 会破
   （`src/rtl/top/pl_video_top.v:79-82`）。
2. **16 位字段是饱和的、不回卷**（`src/rtl/eth/link_monitor.v:88-92`）：读到 `0xFFFF` 的含义是"至少 65535"，
   不是"绕回 0"。
3. **lane 里的 ms 只有在源时基准的时候才是 ms**（`src/rtl/eth/link_monitor.v:6-7`）：
   所以任何实时判断都要与 lane31 那两位相与（`src/rtl/top/system_top.v:255-256`）。

小结 1：lane 表有 16 行有效定义 + 一行"越界返回 `DEAD_BEEF`"，这就是 W10 要的"每行都能找到"。
小结 2：这一节与第 3 节合起来构成 PS↔PL 的全部观测面；没有第三种回读通道。下一步：第 5 节。

## 第 5 节 CFG_DATA0 / CFG_DATA1（`0x41220000` / `+0x08`）

### 5.1 `CFG_DATA0`（32 位，效果 + 几何 + 缩放）

固件侧拼字在 `src/ps/main.c:223-225` 与 `:120-159`；PL 侧取位在
`src/rtl/top/system_top.v:264-275`。⚠ **PL 内部编号与 PS 物理位号不是一套**：
19 位几何控制字 `split_ctl[18:0]` 是把下面这些物理位**重新拼序**得到的
（拼式在 `src/rtl/top/system_top.v:274-275`，两份编号的对照写在 `src/rtl/top/pl_video_top.v:49-51`）。

| PS 物理位 | 含义 | 进 PL 后叫什么 | 备注 |
|---|---|---|---|
| `[8:0]` | 九位效果选择 | `stage_sel[8:0]` | 位定义正本 `src/rtl/process/proc_pipeline.v:5-6` |
| `[9]` | `rot_auto` 自动旋转 | `split_ctl[14]` | `src/rtl/top/pl_video_top.v:176` |
| `[12:10]` | `rot_speed`（度/帧，0 = 开着但不走） | `split_ctl[17:15]` | 同上 `:177`、`src/rtl/process/rotate/angle_ctrl.v:14` |
| `[22:13]` | 缝位置 `pos_px`（显示列） | `split_ctl[9:0]` | 10 位 ⇒ 最大 1023，屏宽 1024，所以**夹得住但差一列**（`src/ps/main.c:125-136`） |
| `[23]` | `auto_en` 扫描 | `split_ctl[10]` | `src/rtl/top/pl_video_top.v:887` |
| `[24]` | `follow`（缝量在画面列里） | `split_ctl[11]` | 它同时管扫描坐标系与判据空间（`:896-899`） |
| `[25]` | `swap` 左右互换 | `split_ctl[12]` | `:889` |
| `[28:26]` | 缩放档号 0..7 | `zoom_sel_async[2:0]` | `src/rtl/top/system_top.v:268`；八档表 `src/ps/main.c:187` |
| `[29]` | 手动旗标 | `zoom_manual_async` | 同上；复位默认手动 1.00×（`src/ps/main.c:178-186`） |
| `[30]` | `marker_off` 关那条蓝线 | `split_ctl[13]`（取反用） | `src/rtl/top/pl_video_top.v:892-894` |
| `[31]` | `zoom_fit` 倍率跟着角度定 | `split_ctl[18]` | `:178` |

### 5.2 `CFG_DATA1`（gamma 窗口 + 两格显示值）

| 位 | 含义 | 消费处 |
|---|---|---|
| `[31]` | `gamma_en`，0 = 逐位旁路 | `src/rtl/process/proc_pipeline.v:33` |
| `[30]` | `wr` = **翻转位**（不是电平） | 同文件 `:34` |
| `[29:22]` | 表项数据 | 同文件 `:36` |
| `[21:14]` | 表项索引 | 同文件 `:35` |
| `[13:8]` | `gamma_disp` = γ×10，只给 OSD 那一格 | `src/rtl/top/pl_video_top.v:194` |
| `[7:0]` | 温度的两位十进制 BCD，只给 OSD 那一格 | `src/rtl/top/pl_video_top.v:195`；编码规则 `src/ps/main.c:83-93` |

两个"为什么这么放"的点：

- 十进制换算在固件做、不在 OSD 做：那五行字符是一整块组合逻辑，而它正是全设计最差路径之一
  （`src/ps/main.c:85-89`，读数出处 `build/timing_summary.rpt`）。
- 任何一个半字节 > 9 就等于"没有可信读数"，屏上画 `--`（`src/ps/main.c:90-93`）。

小结 1：这两只 32 位寄存器里，**只有 `wr` 与 `[18]`/`[22]` 那两个翻转位是事件语义**，其余全是准静态电平。
小结 2：所有写 `CFG_DATA1` 的地方都必须从影子值整字写回（`src/ps/main.c:94-95`、`src/rtl/process/effect_ctrl.v`）。下一步：第 6 节。

## 第 6 节 UDP 包形与网络身份

| 项 | 值 | 出处 |
|---|---|---|
| 目的端口 | 5001 | `src/rtl/top/system_top.v:145` |
| 板 IP | 192.168.1.10 | `src/rtl/top/system_top.v:159` |
| 板 MAC | `00:11:22:33:44:55` | `src/rtl/top/system_top.v:158` |
| ARP 侧对端 | 192.168.1.102 | `src/rtl/eth/eth_udp_video_top.v:128` |
| 包形 | `[u32 小端 帧内偏移][RGB565 载荷]` | `src/host/video_sender.py:4-6` |
| 载荷约束 | ≤1392 B 且必须是 8 的倍数 | `src/host/video_sender.py:6`、`:36` |
| 一帧预算 | 307200 B | `src/rtl/eth/frame_reasm.v:11` |

三条边界的后果：

- **不分片**：超过 1392 B 会触发 IP 分片，而收包链不分片 ⇒ 只能靠发送侧守住这个数
  （`src/host/video_sender.py:36` 那句就是这条约束的原文）。
- **偏移可乱序**：包可以乱序、可以重发（重组按偏移落位），但**不会重发** ——
  上位机丢包只能靠"下一帧凑不齐 ⇒ 整帧作废"体现（`src/rtl/eth/frame_reasm.v:26-30`）。
- **验收看行**：光凑满 307200 B 不提交，还要 300 行覆盖位图全 1（`src/rtl/eth/frame_reasm.v:81-96`）。

小结 1：这条契约是本项目**唯一**的对外数据面接口，且它是不可靠传输上的自定义协议：所有可靠性都在 PL 里自建。
小结 2：换题目时这一节整块可复用（改端口与 IP 两个常数即可），改的是载荷语义。下一步：第 7 节。

## 第 7 节 握手与"没有中断"这件事

- **没有中断**：BD 里三只 GPIO 全部 `C_INTERRUPT_PRESENT {0}`
  （`build/tcl/build_system_axigpio.tcl:95`、`:105`、`:124`），固件里也没有异常服务程序登记这条路径。
  ⇒ 所有"完成了没有"的判断都是**轮询 + 翻转位**，不是硬件通知。
- **AXI 读突发**：`AR` 的 `arsize = 3'b011`（8 字节）、`arburst = 2'b01`（INCR）
  （`src/rtl/axi/axi_frame_writer_gated.v:37-38`）；写侧同样走 INCR 突发
  （`src/rtl/eth/eth_udp_video_top.v:360-366` 的端口形状）。
- **反压**：唯一一处显式反压在 CDC 读侧 —— 打包器满就不取数（`src/rtl/eth/eth_udp_video_top.v:312`）。
- **超时**：两处看门狗。拷贝看门狗 20 ms（`src/rtl/video/frame_commit_lock.v:8`）；
  片源心跳 500 ms（`src/rtl/top/pl_video_top.v:586`），固件侧对应 100 ms 一跳
  （`src/ps/main.c:260`，两侧 1:5 的比例由台架钉住，同文件 `:256-259`）。

小结 1：这里没有"中断"这个概念，任何"等硬件通知我"的设想都要换成"轮询哪一位 + 它翻不翻"。
小结 2：两处超时是**一对**：改固件节拍就要改 PL 门限，这两件事不是一处定义。下一步：第 8 节。

## 第 8 节 一致性的机器判据

契约最容易漂的三个方向，本仓库各有一把尺子（都是只读检查，跑法见 `hands-on.md` 第 3、4 节）：

| 会漂什么 | 尺子 | 判什么 |
|---|---|---|
| 顶层接线（端口名、悬空输入、位宽） | `build/check_ports.py`（门禁第 14 项的调用点在 `build/gates.sh:252-260`） | `violations=0` 且扫描面不塌 |
| 文档里 `文件:行` 的引用 | `src/host/line_cite_check.mjs` | 硬错 0 条（锚点命中数进门禁第 20 项，`build/gates.sh:503-509`） |
| 命令长度口径（五位必须被拒） | `src/host/pipe_len_check.mjs` | 逐条 ok ≥ 26 且等于自报条数（`build/gates.sh:551-559`） |

一句诚实的口径：这三把尺子**都不检查**"固件宏定义与 RTL 位序是否一致"。本文第 3、5 节的两张表
就是这一缺口的**人读补偿**；把它做成机器判据是 `_progress.md` 里登记的一条待办。

小结 1：位表本身没有机器对账，这是本目录认定的一处风险，不是一处已完成。
小结 2：下次改位序时，必须同一次改三处（`src/ps/main.c:153-154` 就把这条警告写在了代码里）。下一步：第 9 节。

## 第 9 节 小结与下一步

契约就四页：三个地址 + 一张 lane 表 + 两张控制字位表 + 一种包形；没有中断、两处看门狗、三个跨层必须一致的数。
下一篇 `glossary.md` 收本目录全部名词的五层阶梯（本文用到的"翻转位、准静态、饱和、乒乓、突发"等都在里面）。

## 第 10 节 自测题

题目：**上位机只写 `CFG_DATA0[28:26] = 5`，但从来不写 `[29]`，屏上的缩放档会不会变？为什么？**
本文不答。要回答它，去查这三处的原文：`src/rtl/top/pl_video_top.v:328`（`zsel`/`manual` 怎么进 `zoom_ctrl`）、
`src/rtl/process/zoom/zoom_ctrl.v` 里那两位的用法，以及 `src/ps/main.c:183-186` 关于"哪一位是权威的"那句话。
