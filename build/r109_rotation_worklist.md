# r109 采纳那笔的数字改口工作单（2026-10-03 01:5x 备好，采纳时一次改完、一次提交）

为什么现在不改首页：**首页六行讲的是"板上这一版"**，而板上今晚还是 r108（断电重上后把它恢复到文档态）。
只把数字换成 r109 的报告值、身份句仍写 r108，页面就自相矛盾（0.605 是 r109 的时序，r108 是 0.721）。
⇒ 数字与身份必须**同一笔**改，且身份那半句要等刷板之后才知道时刻与 bit md5。

下面每个"报告="都是 `node src/host/metric_recheck.mjs` 今天自己念的判据值（01:5x 那一次跑，44 条红），
不是另算的；原件在 `build/timing_summary.rpt` / `build/utilization.rpt` / `build/power.rpt` / `build/hold_paths.rpt`。

## 一、README.md（首页五行）

| 行 | 现在 | 改成 | 依据 |
|---|---|---|---|
| :56 | 全设计 setup WNS **0.721 ns** | **0.605 ns** | `timing_summary.rpt` 逐时钟表 eth_rxc 那行 WNS=0.605，且它是全设计最小 |
| :56 | 板上这一版 r108 / 2026-10-02 20:54 / `bit 25bf35a9900e` / 门禁 22 项 21 绿 / `build/r108_gates.txt` / `build/r108_board_verify_console.txt` | 板上这一版 **r109** / **刷入时刻（刷完再填）** / `bit **刷完后取 md5sum 前 12 位**` / 门禁 **24 项 23 绿** / `build/r109_gates.txt` / `build/r109_board_verify_console.txt` | #229/47：项数与被引用句子要同笔转；D1b 认"戳着这块 bit 的那份 rNN_gates.txt" |
| :57 | eth_rxc 0.721（9.0 %）；clk_fpga_0 1.524（15.2 %）；clkout0_1 1.130（5.65 %）；sys_clk 14.324 | eth_rxc **0.605（7.563 %）**；clk_fpga_0 **1.238（12.38 %）**；clkout0_1 **4.094（20.47 %）**；sys_clk **15.289** | 逐时钟表原值 |
| :58 | 全设计最差那一格在 `eth_rxc`（落点 `u_eth/u_cdc/rgray_s1_reg[7]/C → u_eth/u_lm/full_d_reg/D`）**0.035 ns**，**3 级逻辑（CARRY4=2 + LUT6=1）**，走线占 **60.7 %** | 域名 `eth_rxc` **不变**；落点改 **`u_eth/u_rx_mac/u_crc_rx/crc_data_reg[17]/C → crc_data_reg[25]/D`**；**0.049 ns**；**1 级逻辑（LUT6=1）**；走线占 **80.93 %** | `hold_paths.rpt` 第一条（Data Path Delay 0.975 = logic 0.186(19.070 %) + route 0.789(80.930 %)）。规矩 46：这是**归属判据**，整句重写不是只换数 |
| :59 | 95 tile（67.86 %）/ 14360（26.99 %）/ 8162 处写作 8168（7.68 %）/ 19（8.64 %）；"r108 那一刀的代价：比 r107 多 37 个 LUT、12 个寄存器" | **95.5 tile（68.21 %）/ 14362（27.00 %）/ 8162（7.67 %）/ 19（8.64 %）**；代价句改 **r109 这一刀的代价：比 r108 多 2 个 LUT、少 6 个寄存器**（OSD 读侧寄存一拍换掉的） | `utilization.rpt`：Slice LUTs 14362/27.00、Slice Registers 8162/7.67、Block RAM Tile 95.5/140/68.21 |
| :60 | 动态 2.212 W（片上合计 2.389 W）、结温估算 52.6 °C | 动态 **2.214 W**（片上合计 **2.391 W**）、结温估算 **52.6 °C（不变）** | `power.rpt`：Dynamic 2.214 / Total On-Chip 2.391 / Junction 52.6 |

## 二、README_EN.md（同六行的英文对照）
:70 同 :56（含 `the 22-item gate check reads 21 green` ⇒ **24-item / 23 green**）；:71 同 :57；:72 同 :58（落点半句同样要重写）；
:73 同 :59（`+37 LUT and +12 registers versus r107` ⇒ **`+2 LUT and -6 registers versus r108`**）；:74 同 :60。

## 三、data/metrics.csv（六行的值列 + 说明列里的版本标签）
| 行 | 值列改成 | 说明列里必须一起换的 |
|---|---|---|
| 5 全局 setup WNS | `0.605` | 「本轮（r107）」→ **r109**；端点总数 51029 / 失败 0 不变 |
| 7 全局 hold WHS | `0.049` | 「本轮（r107）」→ r109；那句"WHS 要先问是哪一格"里点名的格子换成 `crc_data_reg[17]→[25]` |
| 8 Slice LUT 占用 | `14362（27.00 %）` | 版本标签与"与上一轮逐字相同"那类旧话一起重读，不许留旧轮叙事 |
| 9 Slice 寄存器占用 | `8162（7.67 %）` | 同上 |
| 10 Block RAM Tile 占用 | `95.5 / 140（68.21 %）` | 可用瓦片 140 不变 |
| 27 实现后动态功耗 | `2.214` | 说明里"片上合计 2.389 W"→ **2.391 W** |
| 28 结温估算 | `52.6`（不变，本来就 OK） | — |
| 29 片上结温（板读 XADC） | 板上那一版换成 **r109 + 新 bit md5 + 刷入时刻**，读数**必须刷完重取**，不许沿用 61.3–61.4 | — |

## 四、数字之外必须同笔做的三件事（规矩 229/46/47）
1. **门禁项数**四处：`README.md:56`、`README_EN.md:70`、`report/background_and_novelty.md:31`、`:80` 全部 22→**24**、21→**23**。
2. **modules.md 的 8 条行号引用**重锚：r109 两处 RTL 改动造成行位移（`osd_overlay.v` 与 `pl_video_top.v`），
   按 `line_cite` 自己报的红单逐条改，改到它绿为止；不猜偏移量（#236 记过一次猜错方向）。
3. **位流落回交付位置**（#240）：`build/system.bit`/`build/system.xsa` 里现在是未采纳的 r109（`21227687e925`）⇒
   采纳那笔要把它们连同 r109 的 gates 件一起提交，之后才允许跑 `build/make_submission.sh`。

## 五、采纳之后怎么知道自己改对了（不靠眼看）
- `node src/host/metric_recheck.mjs`：44 条红必须降到 **0 条红**（判的条数会变，"判 N 个数"那一行要读出来核对）；
- `bash build/gates.sh` 连跑两遍逐字节一致，且第 24 项（`line_cite`）绿；
- 若任一条改完仍红 ⇒ 说明哪个数字被当成了"报告值"而它其实另有出处 —— 回到原件重读，不许放宽尺子。
