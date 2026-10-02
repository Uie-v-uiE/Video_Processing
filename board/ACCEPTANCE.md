# 板上验收表（交付这一版）

一张表说清"这一版在真板子上被验过什么"。每行都点名它的凭据；**没验到的写在最后一节，不打勾**。
上板方式只走 JTAG（`ps_jtag_boot → program_pl → ps_app_reload`），本工程不向 QSPI/SPI flash 写入。

## 机器判据（脚本读回来的）

本表**按行记版本**：第 1/2/3/5/9/10 行是 r94（板上那一份位流 `a1465f29c9e4`，源 `rtl_md5=526321488fed`）
重跑/重念的；第 4/6/7/8 行的读数还是 r92 那一次（同一棵树没变的那些行为，r94 没重跑），补跑排在
门禁落盘之后。把某一行的数当"这一版验过"之前，先看这一行有没有"r94"字样。
**r96（位流 `76d6442991e0`，源 `rtl_md5=fe573f9b2024`）已经把第 1/2/3/7/9/10 行重跑或重念过**，
逐条读数与凭据在下面"r96 重跑的那几行"一节；第 4 行**没有**被 r96 盖章，理由也写在那一节。

| # | 判据 | 读数 | 凭据 |
|---|---|---|---|
| 1 | PS 起来 + PL 烧写 + 应用重载三歩都成功（**r94 重跑**）| `DDR_ECHO: 10000000: 5A5AA5A5` / `PROGRAMMED xc7z020_1`（位流 md5 `a1465f29c9e4` = 树上 `build/system.bit`）/ `RESUME: ok` | `build/r94_flash.txt`（三段都在一份里）|
| 2 | 串口命令电池（100 条，含该拒的必须拒）（**r94 重跑**）| `RESULT PASS uart_cmd_check (100 条命令, 93.1 s)`；`RESULT PASS geom_check（ok=8 fail=0）`；`board_verify` 全量那一串**等 r94 门禁落盘后补跑** | `build/r94_batt.txt`、`build/r94_uart_cap.txt`、`build/r94_geom_check2.txt` |
| 3 | 几何"最后一跳"：命令 → 像素域真的用了它（**r94 重跑，树上带 #93 那一钳**）| `RESULT PASS geom_check（ok=8 fail=0）`，其中 G1b/G1c/G2 三条量的是"拟合/旋转钳下 `inv_used` 与屏上档号同源自洽"（例：`fit=1` 时 inv=433 ⇒ 屏上 0.50x 档 2）| `build/r94_geom_check2.txt` |
| 4 | 上电默认档位 | `lane23 zoom → zsel=4 zman=1 inv_scale=256 x100_actual=100`（屏上画 1.00×） | `build/evidence/verify_0930_0424.txt` 的开机回读段 |
| 5 | 以太推流期间链路健康（**r94 重跑**）| `--demo --fps 25`：**3001 帧 / 120.05 s = 25.00 fps、共发 663221 包**；推流**之中**读回 `drop_words=0`、`丢过字=0`、`stall_ms=0`、`CDC灌满过=0`、`流活着=1`、`eth_rxc 心跳：正常`（累计 pkts/bytes 见凭据第 8/9 行）| `build/r94_tx_console.txt`（发送端）、`build/r94_health_rotclamp.txt`（推流中读的）|
| 6 | 链路内时延同源一致 | 屏上 `Latency=6ms` 与回读 `tot/100000=6` 一致（ok） | `build/evidence/r92_health.txt` |
| 7 | 温度格三方对账 | `V9-6 温度格三方对账：4 条 [TEMP] 的 degC↔osd↔gpio 全部自洽` | `build/evidence/verify_0930_0424.txt` |
| 8 | SD 卡本地播放 | `sd=1 playing=1`，帧率 29.8 – 30.0 fps（100 帧滑窗） | `board/uart_script_capture.txt`、`data/metrics.csv` |
| 9 | 时序/资源读数与报告一致（r94 重念）| 全设计 setup WNS 0.553 ns、hold WHS 0.049 ns、失败端点 0 / 50883；BRAM 95 tile、LUT 14374、FF 8074、DSP 19、动态 2.206 W。绝对值与上一版之差**不记收益也不记损失**（规矩 35）| `build/timing_summary.rpt`、`build/utilization.rpt` |
| 10 | 收口只有一棵时钟树（#57 的结构判据，不靠 slack 碰运气）（**r94 重念：`build/clock_util.rpt` 是这一版构建产的**）| `build/clock_util.rpt`：**`BUFIO` 用量 0**（改前那一份是 1），`eth_rxc` 只经一只 `BUFG/O`（`g2`←`src2`=`IBUF/O @IOB_X1Y28`，fabric 负载 2478）；最差 20 条 hold 的时钟偏斜由 `build/hold_paths.rpt` 逐条读，实测 0.013~0.349 ns（改前那一条是 1.616 ns） | `build/clock_util.rpt`、`build/hold_paths.rpt`；改前对照是仓库里的 `build/r88_clock_util.rpt`（rNN 命名的对照件，不随包） |

第 5 行里有两个数要如实写出来：`作废过帧=1`、`缺行峰值=299` —— 那是推流起始那一帧没收齐被整帧丢掉
（三重提交门限的行为，不是丢字），所以"一个字都没丢"讲的是**字级**，不是"每帧都到齐"。

## r96 重跑的那几行（2026-09-30 17:07 构建、18:45 刷板与验收；位流 `76d6442991e0`，源 `rtl_md5=fe573f9b2024`）

上表的原行**不覆盖**（留作历史读数），这一节只记 r96 这一版被重新建立起来的部分：

| 行 | r96 的读数 | 凭据 |
|---|---|---|
| 1 | `RST_SYSTEM: ok` / `PS7_INIT: ok` / `PS7_POST_CONFIG: ok` → `PROGRAMMED xc7z020_1 <- build/system.bit` → `FLOW_DONE`（只走 JTAG，不写 QSPI）。**第一次跑第一步连不上**：`CONNECT:` 空 ⇒ 本机没有 hw_server 在听 3121，起了 `Vitis/bin/hw_server.bat` 之后拿到 `tcfchan#0` —— 复现时这一条要先做 | `build/evidence/r96_flash_1_ps_boot.txt`、`r96_flash_2_program_pl.txt`、`r96_flash_3_app_reload.txt` |
| 2 | `RESULT PASS uart_cmd_check（105 条命令, 97.7 s）`（比 r94 的 100 条多 5 条：#105/#177/#178 那几组新判据）；`RESULT board_verify PASS（判红的步骤：0）` | `build/evidence/verify_0930_1845.txt`、`verify_0930_1845.batt.txt`、`board/uart_script_capture.txt` |
| 3 | `RESULT PASS geom_check（ok=8 fail=0）`：`G1a zoom fit 1 ⇒ lane23.bit19=1`（`lane23=0x800e4909`）、`G3x` 收尾把 fit 关掉 ⇒ bit19 回 0（`0x800621f4`）、`G4` 跑完整串 19 个几何位回到演示默认档（`geom=00400000`） | `build/evidence/verify_0930_1845.geom.txt` |
| 4 | **没有盖章**：刷完之后开机读到的是 `zsel=4 zman=1` 而 `inv=265`（几分钟后同一位是 `inv=472`、`zcode=2`）—— 逐位拆开自洽，是 **#93 的旋转钳正在生效**（板子在自动旋转），不是默认档失灵。要补这一格得先把旋转钉住（`rot auto 0` 之后**读 OSD 的角度格**，不能只发命令就算，理由见账 #178/#175） | `build/evidence/verify_0930_1845.txt` 的开机回读段；账 `report/log/ISSUES.md` 的"#175 又抓到一份活标本" |
| 7 | `V9-6 温度格三方对账：4 条 [TEMP] 的 degC↔osd↔gpio 全部自洽`（在 105 条那一串里跑的） | `build/evidence/verify_0930_1845.batt.txt` |
| 9 | 全设计 setup WNS **0.749 ns**、hold WHS **0.049 ns**、失败端点 **0 / 50887**（脉冲 WPWS 0.264、失败 0 / 12524）；BRAM **95** tile(67.86 %)、Slice LUT **14388**(27.05 %)、FF **8077**、DSP **19**、动态 **2.206 W**。逐时钟：`eth_rxc 0.749/0.049`（WNS 归属）、`clk_fpga_0 1.755/0.051`、`clkout0_1 0.840/0.062`、`sys_clk 14.272/0.121`。绝对值与 r94 之差**既不记收益也不记损失**（规矩 35）；端点 +4 与 #170 排空态新增的位同量级，这是结构观察不是改进 | `build/timing_summary.rpt`、`build/utilization.rpt`、`build/r96_gates.txt` |
| 10 | `build/clock_util.rpt`（17:07 本版构建产）**重读到 `BUFIO = 0`**、`BUFGCTRL = 8`；本行原来那组"最差 20 条 hold 偏斜 0.013~0.349 ns"**这一轮没有逐条重读**（那是 r92 那一次的读法，文件也还在盘上） | `build/clock_util.rpt`、`build/hold_paths.rpt` |

**r96 这一版还欠两格，不打勾**：① #170/#171 的**板级**形态（拷贝中途被看门狗打断之后，撕裂帧不再显示、`eth_ready`
读 0）——今天的 `--stream` 是"干净停流交回"，不是 abort 注入，模块级凭据齐而板级这一格空着；
② #171 的**顶层**台架判据记为**未判**（守卫 `C11pre` 红，账 #187），要等下一次整屏。

## r97 重跑的那几行（2026-09-30 19:52 构建、22:15 刷板、22:15–22:24 机器验收；位流 `ef03eea4886e`，xsa `a50188e5f789`，elf `d0b07f84a068` 未变）

上表与 r96 那一节的原行**都不覆盖**（历史读数留着），这一节只记 r97 这一版重新建立起来的部分：

| 行 | r97 的读数 | 凭据 |
|---|---|---|
| 1 | `RST_SYSTEM: ok` / `PS7_INIT: ok` / `PS7_POST_CONFIG: ok` / `DDR_ECHO: 10000000: 5A5AA5A5` → `PROGRAMMED xc7z020_1 <- D:/…/build/system.bit` → `DOW: ok / CON: ok / RESUME: ok / FLOW_DONE`（只走 JTAG，**没碰 QSPI**） | `build/r97_flash_1_psboot.txt`、`build/r97_flash_2_program.txt`、`build/r97_flash_3_app.txt` |
| 2 | `RESULT PASS uart_cmd_check（105 条命令, 97.8 s）`，而且**第一次"初态=末态"是绿的**——它同时满足 #177 那条：末态 = 演示默认档 `zman=1 zsel=4 geom=00400000` | `build/evidence/r97_batt_recheck.txt` |
| 3 | `RESULT PASS geom_check（ok=10 fail=0）`：新增的 `G5`（`bit19 == (生效倍率偏离 256)`，样本 4 违例 0）与 `G5b`（**4/4 真钳住**）都在里面；`G3x` 从"bit19 回 0"改成判同一枚不变量（命令表里**没有把角度归零的动词** ⇒ 旧写法是判一个到不了的状态，见 `#200`） | `build/evidence/verify_0930_2215.txt`（第一次跑出 2 条红的那一份）与随后的 `geom_check` 复跑 |
| 4 | `#175` 这一格**从"读得到"升级为"能被判"**：屏上 `Zoom` 那格、串口 `[STAT]`、lane23 回读三处现在说的是同一件事；开机档位这一轮落在**文档默认档**（`zman=1 zsel=4`），所以 r96 那行"没有盖章"的口径可以推进到"默认档已盖章，呼吸/自动档另记" | 同上 + `build/board_temp_r97.txt` 里那两条 `[STAT]` |
| 7 | `V9-6 温度格三方对账：4 条 [TEMP] 的 degC↔osd↔gpio 全部自洽`；**并第一次把板读值抄进交付件**：`degC=63.38 / 63.17 / 63.13`（`raw 0xAAF2/0xAAD7/0xAAD2`、`vccint 997–998 mV`、屏上 `TEMP:63C`、`gpio=0x63`） | `build/board_temp_r97.txt`、`data/metrics.csv`（新增"片上结温（板读 XADC）"那一行） |
| 9 | 全设计 setup WNS **0.720 ns**、hold WHS **0.033 ns**（含自加的 0.8 ns 不确定度）、失败端点 **0 / 50890**、脉冲 WPWS 0.264 / 0 / 12526；资源 **14379 LUT / 8079 FF / 95 tile / 19 DSP** | `build/timing_summary.rpt`、`build/utilization.rpt` |

**r97 这一版还欠的格，明写着不打勾**：①`#170`/`#171` 的**板级 abort 注入**（拷贝中途被看门狗打断之后撕裂帧不再显示）仍是模块级凭据齐、板级空着；
②整屏台架的 `C11pre` 守卫——今天查出红因是**我的激励没把屏交给 ETH**（`eth_live/eth_tb_ok` 没钉，`pl_video_top.v:114-115` 是这两位进顶层的口、`:396` 是交给仲裁器的那一跳、`:402`/`:430` 才是"这一拍搬运机归谁"与行写使能），修完之后**复跑在飞**，
所以 r97 的门禁与冻结两行等那一份报告落地再补；③要肉眼与要手的三格（见下一节）仍归用户签。

## 要肉眼确认的（机器判不了，所以先空着）

| # | 看什么 | 怎么起 | 结果（谁点的头、什么时候） | 看不到时先看哪一格 |
|---|---|---|---|---|
| E1 | 分割线以左是原画面、以右是处理后的同一帧，两侧几何一致 | 双击 `send_demo.bat`，串口 `split 50` | **过（2026-09-30 06:2x，在场的人原话"现在都很正常"）**：右半的白线与红块和左半对得上 | 当时屏上：`--demo --fps 25` 推流中、`src=1`（PL 拥有 UDP 通路）、`split 50` ⇒ `pos=512/1024 manual`、`marker=off`、`zsel=4`（1.00×）、`bilin=1`。回读 `build/evidence/r92_eye_capture2.txt` |
| E2 | 缩放/旋转时不出现整行错位、画面不出屏 | `zoom 0.5` → `rot auto 1`（`split 50` + 关标记线最好判）| **过（2026-09-30 06:5x–07:0x，在场的人原话"现在画面正常只有一条"）**：0.50× + 自动旋转下无整行错位、无左右错开的水平界线；此前他报过一次"隔一段距离的两条白线"，我用**只改推流节奏**做了对照（29.76 fps 一条、复推 25 fps 仍一条）⇒ **未复现**，判为切换瞬间的暂态，不记缺陷；下次再看到要说清屏幕高度、以及是否随缩放档变化。<br>**2026-10-01 22:1x 在 r103 上重新点过一次（这一格现在验的是 #189 修完之后）**：在场的人原话"**1 rot 在走 zoom 是 0.52 没有 3 没有**"——即 `ROT:` 格在走，`0.52` 这个数字**我在屏上找不到能显示它的格子**（`src/rtl/video/osd_overlay.v:288-295`：`Rot:` 那格印的是十进制度数 0..359 带 `°`，`Zoom:` 那格只有八档标签 `0.25/0.33/0.50/0.75/1.00/1.33/1.50/2.00x`，全树搜 `0.52x` 只在 `src/rtl/process/zoom/zoom_ctrl.v:59` 的一句**注释**里出现（那句讲的正是"分区源拿错就会屏上写 1.00x、画面上是 0.52x"），不是任何一格的标签）⇒ **已回问出处，未证实之前不当倍率读数用**，也不写"这正是 #189 的工况"这种话；问"有没有整行错位/沿角度的细鬼影"答**没有**，问"`split 50` 缝两侧同一行有没有上下错开"答**没有** ⇒ **过**。⚠ 两点如实保留：① 当时**标记线有没有关**我没问到，所以"缝两侧"那一判是在标记状态未证下给的；② #189 的发生率台架量到 ≈ 0.27 %（3726 个旋转态像素命中 10 个），**这种稀疏度本来就不保证肉眼抓得到**，所以这一格"过"的意义是"没看到错位"，**不是**"逐行验过"——逐行那部分靠 `sim/tb_zoom_frac.v` 的 S1/S2/S3（本轮 21:1x 同族四份台架判定原文随件在 `build/r103_tb_*.txt`）。状态回读 `build/evidence/r93_e2b_capture.txt`、`build/evidence/r93_ab_state_capture.txt`（r93 那两次）；台架对应 `C2/C3/C9` 三段 + 旋转支小数位 `tb_zoom_frac` |
| E3 | 移动白线与红块连续、无撕裂 | `send_demo.bat`（内置测试图每帧都动） | **过（同上，原话"现在都很正常"）** | 当时屏上：`--demo --fps 25` 推流中、`src=1`（PL 拥有 UDP 通路）、`split 50` ⇒ `pos=512/1024 manual`、`marker=off`、`zsel=4`（1.00×）、`bilin=1`。回读 `build/evidence/r92_eye_capture2.txt` |
| E4 | **（r94/#93）** 旋转一开整幅就在屏内：45°/60° 时四个角都不戳出屏幕，左缘不再有沿对角的宽彩条与细线 |
     `src 2` + `bilin on` + 手动 `zoom 1.0` + **`zoom fit 0`** + `rot auto 1 speed 0`（钳制要在"拟合关着"时才看得见）——
     **屏已经摆在这一态**（`build/r95_eye_park.txt` 末态 `geom=00400A00` ⇒ rot auto=1、speed=2、fit=0，画面正在走）；
     要停住判四角：串口 `rot auto 0` 就冻在**当前角度**（串口读不到角度，看屏上 `ROT:` 那一格），再按 KEY1/KEY2 走 ±1° |
     *待队员判*（"四角在不在屏内"这一半仍未判。2026-10-02 早间新报的那条**顶部碎影不是出屏**，已归到 `#98` 的 `C5c`，见下面这段）<br>**2026-10-02 07:5x 顶部碎影——用户原话逐字**：「我看到旋转的视频四个角划过屏幕上面时角周围会有一些向左右分散的同视频角内容一样的颜色在顶部周围」；三条补充观测：「bilinoff 还在，四个角都有，我是开始 rot auto 看到的现象」「停住的时候没有」「bilin on 的时候比较明显，off 的时候几乎看不到」。<br>已排除的三条：① 角点出屏（`sim/tb_zoom_fit_corners.v` 在 0/30/45/60/90/270 六档 4/4 命中，`build/r104_tb_zoom_fit_corners_console.txt`）；② `zoom_fit` 与 `angle` 差一整帧（`zoom_fit.v:52-55`：输出晚两拍、且落在消隐里）；③ `fb_bilin` 末行末列抽头（`:46-54` 钉小数加折回，`#146` 已断言过）。<br>归到 `C5c` 帧头窗，逐格凭据 `build/evidence/r104_c5head_band.txt`：错的 8 格全在最上面 6 个显示行（`OFF_LINES` 4 加 `BILIN_ROWS` 2），顶部前 4 行显示源行 2 而定义要 0/0/1/1；本体行一格都不错。**bilin 那次 A/B 是可信的**：`gpio_o[19]` 经 `pl_video_top.v:255-266` 的三级同步进 `fb_bilin.bilin_en`（`#83` 已落地，`system_top.v:276` 是接线处）。板上做了速度扫描 1→2→4→6→7→6→4→2→1→0（07:52:53–07:54:38，每档约 7 秒）留给眼睛判"碎影随不随每帧角度步数变大"；`src 2` + `bilin on` + `zoom fit` 随 `rot auto 1` 一起开，末态 `rot show` 回读 `auto=1 speed=0`。<br>**08:0x 眼睛答回来了（两条原话）**：问"碎影是不是只贴在屏幕最上面那一条（约 6 行以内）、不管角转到屏上哪儿"⇒「角在顶部的时候才会有」；问我扫的那轮 `rot speed` 1→2→4→6→7→6→4→2→1→0 里它随不随速度变宽变乱 ⇒「没有，跟速度看不出差」。<br>这两条一起把成因**收窄**了：第一条与"错只发生在屏顶那 6 行"对得上（`build/evidence/r104_c5head_band.txt` 量的正是这个窗口，本体行一格都不错）；第二条否掉的不是机制，而是我给的那句**定量预测**——1°/帧在角点半径约 297 源像素处已经是约 5 个源像素的位移、早就过可见阈，所以"宽窄"这一档眼睛本来就分不出来；它真正分辨得开的是"有没有每帧换角"（0 与 ≥1 两档，正对应「停住的时候没有」与「角在顶部的时候才会有」）。⇒ 位移随角度步数这条关系交给机器量（任务表里那条「给 #98 补第二条尺子」），不该让眼睛判宽窄。<br>**这一格原本那半仍未判**（45°/60° 时四角在不在屏内、左缘有没有沿对角的宽彩条）。板子按你说的收回文档默认态：`rot auto 0` + `rot speed 0` + `zoom fit 0` + `zoom 1.0`，末态 `STAT` 回 `zsel=4 zman=1 bilin=1 geom=00400000`（今天接手时是 `geom=00400A00`，那时板子是转着的），回读落盘 `build/evidence/r104_rotfringe_state.txt` | 屏上 `ROT:` 那格在不在走、`(Fit)` 亮不亮（**屏上应当亮**：r94 把 OSD 的 `(Fit)` 接到了 `zoom_fit_en \| rot_forced`；
     而 lane23 的 bit19 在这一态仍报 0，那是回读口的口径欠账 #175，不是屏上错了）|
| E5 | **（r99/#128）** OSD 的 `FPS:` 这一格数的是**写进屏的新帧**，不再是显示场同步：同一块板上，
     15 fps 推流应读 ≈15、30 fps 应读 ≈30、图卡那一路应读 ≈59（旧那一版 r97 三档都读 59/60，
     这是改动**前**的实测基线，所以只有 15 与 30 两档能分辨改没改成）|
     串口 `src 1`（钉住网络那一路）→ 上位机 `python src/host/video_sender.py --demo --fps 15` → 看屏 L0；
     再把命令换成 `--fps 30` 看同一格；最后串口 `src 0`（钉图卡）看它回到 ≈59。
     ⚠ 串口既没有 `[LINK]` 回包也没有 `FPS` 的数字回读（`src/ps/main.c` 里没有任何 fps 读者，实测 grep）
     ⇒ 这一格**只能看屏**；屏幕读数不属于机器判据，也不进门禁 |
     **过**（用户 2026-10-01 15:3x 在 r101 上目视三档，原话"第一个我看了和你说的都符合"；| 每"不通"各意味着什么：15 与 30 两档**仍读 59/60** ⇒ #128 没落地（不是屏坏），
     回看 `src/rtl/util/shown_rate.v` 那三个源输入在这一态是不是真在跳（ETH 那一路是
     `frame_ready && eth_link_pix`）；只有图卡档不对 ⇒ `frame_start` 那条支线；三档都对但数字**跳得凶** ⇒
     1.000 s 窗口与源节奏的正常拍频，不是缺陷（面板 1344×625@50 MHz ⇒ 场频 59.5 Hz，见 `data/metrics.csv` 那行）。
     机器那一半的凭据：变异对照 `build/mut_shown_rate_r97.txt`；台架 `sim/tb_shown_rate.v` 的 S1..S7
     已在与 r99 同一棵树上重跑：`RESULT tb_shown_rate PASS`（13 条判据、0 FAIL，控制台 `build/r99_tb_shown_rate_console.txt`）|

这三条只有看的人点头之后才写"过"。**r92/r93：E1、E3 由在场的人口头确认（原话"现在都很正常"，06:2x）；E2 确认（原话"现在画面正常只有一条"，06:5x–07:0x，含 0.50× + 自动旋转与 25 / 29.76 两档推流的对照）⇒ 三条眼睛判据这一轮全部由人点头。**同一时间他还提了一句与判据无关的观感意见（测试图动画"太丑"）——记进任务，不当成红项，也不改动已经验完的那一块位流。
（本轮已把屏摆成最好判的样子：`split 50` + `split marker 0` + 片源 ETH，命令与板上回读在 `build/evidence/r92_eye_setup.txt` / `build/evidence/r92_eye_capture.txt`。）

## 结论

- 机器判据 10 条全部通过（第 10 条是 #57 的结构判据），凭据都在表里点名；
- 已知未修项（大角度旋转角点出屏、SD 播放中拔卡冻帧等）在 `report/KNOWN_ISSUES.md`，这里不重复；
- 门禁的**项数与红绿以 `bash build/gates.sh` 打印的那一行为准**，本表不复制它，以免两处漂。
