# `board/raw-vs-golden.md` · 实测输出 vs 参考结果

登记日 2026-10-04。范围：只做"已有实测件的档案化 + 用脚本重跑能重跑的比对"。
**本轮没有驱动串口、没有上板、没有 xsdb、没有跑构建或全量台架**（P23 边界）。
所有比对表都在 `board/compare/`，日志/抓图的条件卡都在 `board/conditions/`，索引在 `board/logs/index.md`、`board/captures/index.md`。

## 0. 一句话结论（然后是难听的那半句）

能重跑的比对**全部重跑了**，12 张表（V01–V12）里 **8 绿、2 红、2 降级**；
但**"实测输出与 `data/golden/` 参考结果的逐元素比对"这一格现在依然是 0 行**——
原因不是我懒得做，是仓库里**没有板级抓帧件**、而 `data/golden/` 的 13 件参考**没有产生程序**（`data/golden/manifest.md` §8）。
⇒ 表 A 的每一行"对 manifest 的判定"都是 `NOT_MEASURED`，只有"对件内参考（自描述图案 / 工具报告 / 基线件）的判定"能给出绿或红。

## 1. 表 A · 硬件读出 ↔ 参考（两栏分开，混写即红）

口径列 = 起点/终点、分母、取样时长、时间基准来源（铁律 4）。判定列最后放。

| # | 指标 | 口径（先定义） | 硬件读出（来源文件:字段） | 参考侧（来源 + 精度口径） | 差值 | manifest 基准条目 | 对 manifest | 对件内参考 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| A1 | 片上结温 | 一次转换一码；时间基准 = 固件采样时刻；分母 = 单条 `[TEMP]` | `build/evidence/r118_serial_raw.txt:1` `degC=60.65 raw=0xA990 vccint=998mv` | `XAdcPs_RawToTemperature` 浮点参考式，经 `src/host/temp_formula_check.mjs` 全 65536 码核对；固件侧是**定点**（×1000 整数、右移 16 截断） | 最大 3 ‰°C（容差 5 ‰°C） | 无（manifest 只管 `data/golden/` 的 13 件图像/图卡） | `NOT_MEASURED`（缺"板级温度基准件"） | **PASS**（V09） |
| A2 | 缩放倍率落位 | 起点 = 串口命令；终点 = `lane23` 像素域回读；分母 = 8 条几何判据 | `board/compare` 无 ⇒ 读 `build/evidence/r118_board/board_verify_console.txt:20` `inv_scale=256 x100_actual=100 rule=manual_tier inv_expected=256 inv_ok=true` | 期望值 = 独立复算的最近档（`nearOf(259)=4`，同一件 `:29`）；16 bit 定点，256 = 1.00× | 0（同源自洽） | 无 | `NOT_MEASURED`（manifest 里没有"lane23 期望值表"） | **PASS**（`RESULT PASS geom_check（ok=10 fail=0）`，同件 `:36`） |
| A3 | 入包链丢字率 | 分母 = 153600 个 16 bit lane/bank；取样 = 推 200 帧后停 + 等 500 ms 读 | `board/compare/ddr-stale-15fps-dump.txt`（源自 `data/measured/ddr_dump_20260921_15fps.out.gz`）`最新帧(#198) 100.0 %`、六带 `0.0 %`、`连续丢字带 2 个 lane` | 参考 = 发送端自描述图案（frameid：值 = 64 bit 字号 + 帧号），逐 lane 反解 | 2/307200 lane（≈0.00065 %） | 无 | `NOT_MEASURED`（缺"图像内容基准"，图案自校验不算参考结果） | **PASS**，但只覆盖 15 fps 一轮（V06） |
| A4 | SD 本地播放帧率 | 时间基准 = 固件 100 帧滑窗；分母 = 滑窗帧数；**舍入 = 滑窗均值报 1 位小数**（无位宽概念，是"计数 ÷ 时长"） | `board/uart_script_capture.txt`（r118 电池内）+ `data/metrics.csv:12` 行 `29.8 – 30.0 fps`，凭据 `build/evidence/r87_boot_stat_drain.txt` | 参考 = 片源名义 30 fps（预转换帧序列，非解码）；整数名义值 | −0.2 … 0 fps | 无 | `NOT_MEASURED`（**缺独立时间仪器**；且 manifest 无帧率基准行） | **PASS（弱）**：只在"标称 30 fps"这一个口径下成立 |
| A5 | 以太推流帧率 | 时间基准 = 上位机墙钟；分母 = 发出的帧数；**fps 保留 2 位小数（发送端格式化），帧/包计数是整数** | `build/evidence/r116_board/sender_live.log:2` `3001 帧 / 50.03 s = 59.98 fps，663221 包`（汉字已坏、数字 ASCII 可读） | 参考 = 发送端设定 60 fps；另有 r94 那一次 25 fps 设定（`board/acceptance.md:20`） | −0.02 fps | 无 | `NOT_MEASURED`（同一指标换设定要另起一行；且这是**发送端**读数，不是板端帧率） | **PASS（发送端自证）** |
| A6 | 端到端时延 | 起点 = 上位机发送时刻、终点 = 屏上出现该帧；**这一对起点/终点没有任何可复核件**（仓库里没有示相机/采集卡导出，见 `board/captures/index.md` 第 4 节） | 无可用硬件读出。`board/acceptance.md:21`（r92）那对 `Latency=6ms` 与回读 `tot/100000=6` 只是**同一读数的两个出口一致**，不是时延绝对值 | 参考侧缺件；`data/metrics.csv:20` 那行自己写「不填没有复核过的数」 | 不可算 | 无 | `NOT_MEASURED`（时延本体） | **NOT_MEASURED** |
| A6b | 帧间隔（**换了指标就另起一行**，铁律 4） | 分母 = 8999 个间隔（`gap_segments`）；时间基准 = 板内 lane 自计的 ms | `board/compare/soak300-lane-delta.txt`（源 `board/evidence_r41/metrics_r41_soak300.json`）`gap_min/gap_max = 20/51 ms`、`gap_sum = 300057 ms` | 参考 = `report/perf_report.md:197-199` 那句 `min/avg/max = 20 / 33.34 / 51 ms`；件内自报 `avg_gap_ms = 33.3434` | 0.00 ms（我现算 33.340 与件内 33.343 都归到 33.34） | 无（golden 没有时延/抖动类基准） | `NOT_MEASURED` | **PASS**（V12） |
| A7 | 状态断言（逐条带回读） | 每条命令后读一次 `[STAT]` / lane；**回读是 32 bit 寄存器字段的十进制原字 + 逐位拆**（`lane23 raw=2147893504`），没有舍入这一维 | `src=1`（`r118_serial_raw.txt:2`）、`playing=1 sd=1 frames=4398`（同）、`osd=1`（同）、`drop_words → 0`（`board_verify_console.txt:21`）、lane30 `why_no_stream=1`（同 `:19`） | 参考 = 下发命令的期望态 | 0 | 无 | `NOT_MEASURED`（对 golden） | **PASS**：5 条状态断言 **5/5 有回读**，没有一条只写"我发过命令" |
| A8 | 上电角度 `ROT:` 读 0 | 屏上第二行那一格；无串口读者 | **无仪器读出**（`board/acceptance.md:98` 自己写"串口读不到角度"） | 参考 = r113 网表实测 `INIT=1'b1`（`build/evidence/r113_ff_init_probe.txt`） | 不可算 | 无 | `NOT_MEASURED` | **不进比对表** ⇒ 见第 4 节"人眼报告（无仪器证据）" |

## 2. 表 B · 软件算出 ↔ 参考（与表 A 分栏；这一栏的数**不是**板上读的）

| # | 指标 | 软件算出（来源 + 口径） | 参考侧（来源 + 口径） | 差值 | manifest 基准条目 | 判定 |
| --- | --- | --- | --- | --- | --- | --- |
| B1 | CDC Critical 配对/端点/unsafe | `build/frozen_r23_srcseen/cdc.rpt`（kv 抽取 `endpoints=@5`、`unsafe=@3`） | `build/cdc_baseline.txt`（`endpoints=@2,unsafe=@1`）；容差 0 | 0 | 无 | **PASS**（V01，判 18 项，红 0） |
| B2 | 全局 setup WNS / hold WHS / 失败端点 / LUT/FF/BRAM/DSP / 动态功耗 | `build/timing_summary.rpt`、`build/utilization.rpt`、`build/power.rpt` 现读 | `data/metrics.csv` + 根 README 首页那 60 个数 | 逐数 0 超差（114 个数） | 无 | **PASS（射程内）**；`data/metrics.csv` 另 18 行不在该尺射程 ⇒ `NOT_MEASURED`（V08） |
| B3 | 逐时钟相对余量（r116 相对冻结基线） | `build/evidence/r116_roster_e1.tsv` 的 `rel_margin_*` | `report/timing/roster_baseline.tsv`（B3 冻结基线） | `eth_rxc` −0.198125 / −0.115250 | 无 | **RED**（V02：comparisons_made=32、both_NA=8、red=2） |
| B4 | 顶层整屏台架条数 | `build/tb_v98_report.txt` 现数 161 + 1 = 162 | `data/metrics.csv:15` 声称的 141（点名 `top_md5=2bf2ceeede07`） | 无法比：该指纹的件盘上 **0 件** | 无 | **NOT_MEASURED**（V11；基准摘要不符 = 不许继续用） |
| B5 | `gapclr` 同拍竞争（F2e B） | `build/r97_180_before.txt` `FAIL F2e B lane5 kept pre-clear history: sum=518 > 2x130` | 判据定义 `sim/tb_link_monitor.v` 的 F2e（A 腿是控制：`sum=130 ≤ 2×130`） | 518 vs 260 上限 | 无 | **FAIL（长期红，已声明）**；预验显示 `base红=1 → cut红=0`（V: `build/evidence/r174_f2e_preverify.txt`），修复**未进真树** |
| B6 | 尺子能不能变红（变异/对照） | `temp_formula_check.mjs` 3 支变异 + `r115_roster_build.py --self` 5 条对照 | 各自的期望红点 | 全部命中唯一红点 | 无 | **PASS**（V04/V09） |

## 3. 表 C · `data/golden/` 13 件现在能不能当"参考结果"用

| 件（`manifest.md` 行） | 磁盘摘要与 manifest 相符? | 现在能比的部位 | 挡住它的是哪一格 | 判定 |
| --- | --- | --- | --- | --- |
| `src.png` / `rot_000.png` | OK / OK | 无 | 两件事：① 产生程序不在树里（manifest §8，13 件全含糊）；② `rot_000` 与 `src` **逐字节相同**（重复件，Q-P17-4 待队伍定） | `NOT_MEASURED` |
| `rot_030/045/090/180/270.png` | OK ×5 | 无 | 缺"板上同一帧旋转到该角度的抓帧"；且旋转插值的算术口径 `【未核实】` | `NOT_MEASURED` |
| `proc_00111/10000/all.png` | OK ×3 | 无 | 文件名那五位是**旧效果位口径**，现行 `pipe` 控制字是九位 ⇒ 连"对应哪一组开关"都对不上 | `NOT_MEASURED` |
| `dual_preview.png` | OK | 无 | manifest §3 原文：与 `split_display` 显示方式同类但**不是同一套算术**产出；且它是 1280×360 双窗 | `NOT_MEASURED` |
| `frame_640x360.mem` | OK | 无 | **口径不符**：参考是 640×360，板上处理画幅 512×300（`board/README.md` 第 1 节）⇒ 真要比要另起一行并说明放大关系 | `NOT_MEASURED` |
| `README.md` | OK | 不适用 | manifest §3 自己写"自产文档（不进任何比对表）" | 不列 |
| （全部 13 件） | **OK 13 / FAIL 0** | 参考件本身完好 | 缺的是**板级抓帧件**与**可复现渲染脚本**（Q-P04-1 / Q-P17-2） | 摘要核验 **PASS**（V10） |

⇒ 一句话：**基准没坏，坏的是"实测那一侧没有可对的东西"**。任何"与黄金参考逐像素一致"的写法在本仓库现在都不成立。

## 4. 失败分析（人眼所见不进表；这里只放观察与归因）

`board/acceptance.md` 我**只读未改**。下面每条给原话 + 时间 + 行号，并标明缺哪种仪器凭据。

1. **旋转顶部碎影（→ 已归到 `C5c`）**
   2026-10-02 07:5x 队员原话（`acceptance.md:76`）：
   「我看到旋转的视频四个角划过屏幕上面时角周围会有一些向左右分散的同视频角内容一样的颜色在顶部周围」
   三条补充原话（同处）：「bilinoff 还在，四个角都有，我是开始 rot auto 看到的现象」「停住的时候没有」「bilin on 的时候比较明显，off 的时候几乎看不到」。
   08:0x 两条回答（同处）：「角在顶部的时候才会有」「没有，跟速度看不出差」。
   **仪器凭据是有的、但不是这条观察的凭据**：`build/evidence/r104_c5head_band.txt:9` 量到
   `本体行 3564 格不符 0 ｜ 帧头窗 36 格 不符 24`，错的 8 格全在最上面 6 个显示行（`OFF_LINES` 4 + `BILIN_ROWS` 2）。
   ⇒ 归因顺序（铁律 8）：先排除①角点出屏（台架 6 档 4/4 命中）②`zoom_fit` 与 `angle` 差一帧（`zoom_fit.v:52-55` 晚两拍且落在消隐）
   ③`fb_bilin` 末行末列抽头（`:46-54`）；**眼睛那两句的作用是"缩小窗口"而不是"定案"**：
   "跟速度看不出差"否掉的是我给的那句**定量预测**（1°/帧在角点半径 ≈297 源像素处早已过可见阈），不是机制本身。
   E4 的另一半（45°/60° 四角在不在屏内）已由原话「现在屏幕没问题了四角都在屏幕内」（2026-10-04 08:3x，板上 r118，bit `cd04907e1369`）判过——**这一读仍是人眼，无仪器凭据**。
2. **屏上出现读数 `0.52`（找不到能显示它的格子）**
   2026-10-01 22:1x 原话「1 rot 在走 zoom 是 0.52 没有 3 没有」（`acceptance.md:70`）。
   `0.52` 在 OSD 的两格里都不存在（`Zoom:` 只有八档标签，`Rot:` 印 0..359°），全树 `0.52x` 只出现在 `zoom_ctrl.v:59` 的一句注释里。
   ⇒ 已回问出处，**未证实之前不当倍率读数用**；这条观察在表 A 里没有行。
3. **"隔一段距离的两条白线"未复现**
   2026-09-30 06:5x–07:0x 原话「现在画面正常只有一条」（`acceptance.md:70`）；对照实验只改推流节奏（29.76 与 25 fps 各一次）⇒ 判为切换暂态，**未复现、不记缺陷**。
4. **应答器几分钟后变哑（#216/#188）**
   真实异常：`64 × 32 字节 0/64`、`-l 32` 与 `-l 0` 交替各 4 次全 `0/4`（`report/log/issues.md:8931-8933`）。
   **我 14:59 写过"板上不过"，15:08 就地作废**（同节标题就是更正）：拿"长度 0"当变量其实比的是两个时刻 ⇒ 该格现在是"未验"，不是过也不是不过。
   复位救回：`4 发 1 收，RTT 3 ms`（`issues.md:8994`）；复位后连测 7 轮全 `4/4`（`:9012`）；r104 三档复测全绿（`build/r104_board_ping.txt`）。
   顺手量到的**尺子缺陷**：lane8/lane9 计数器在只发 ping 时一字未动 ⇒ 它们看不见 ICMP，"没收到 vs 收到没回"用现有 lane 分不开。
5. **SD 拔卡永久冻帧（#94）+ `sd remount` 失败（#45）**
   用户实测三步原样：拔网线立刻切 SD（对的）、拔 SD 卡在最后一帧、插回不恢复（`issues.md:3616`）。
   仪器侧回读：`[SD] remount failed: XSdPs_CfgInitialize failed` + `[STAT] sd=0 playing=0 frames=0`（`build/evidence/r75_sd_remount_before.txt:4,8`）。
   ⇒ 归因到固件状态（`mounted` 永不清零），并**修正了一条更早期的错话**：原写"只能断电重插"，实测完整三件套即可恢复（`issues.md:750`）——不用断电。
6. **`BYTES: 0` → AP 不可达 → 只能断电重上（#235）**
   `issues.md:10909-10916` 的时间线原样（串口零字节 00:13:13、`DOW: Memory write error … DAP status 0xF0000021` 00:14:50）。
   两次读数失误也留在账上（把 `tail -12` 当"没报错"；`issues.md:10911`、`:10932`）⇒ 本档案每张卡都把 token 原文抄进"异常前后"块。
7. **空捕获与"两种状态其实是同一次失败"（本轮我新登记的）**
   `build/evidence/r116_serial_raw.txt` 2 字节、`[TEMP]=0`（地板 2）；
   `build/evidence/r116_board/health_idle.json` 与 `health_live1.json` 的 **sha256 前 8 相同（`17f70555`）**，
   内容是同一次 xsdb 失败的同一个字符串 ⇒ "两种状态各读了一遍"这个说法不成立，只能记 `NOT_MEASURED`。
8. **F2e B 长期红**（不是本轮新增，本轮只是把它落到表 B5）：修复动作在拷贝树上验证过 `base红=1 → cut红=0`
   （`build/evidence/r174_f2e_preverify.txt:18`），但**没有进真树**，且它不在门禁射程内（`build/evidence/r109_lane_cost.txt:50`）。

**未观察到的失败**：本轮（只做档案化）没有新采一轮，所以无法回答"这一版跑 N 次里有几次崩"；
已有的取样覆盖是：串口原始回显 15 件（L01–L28 里 13 件同尺子）、DDR 回读 2 件、ping 3 档 + 历史 64 次、
冷上电 1 次（对照腿未做）。

## 5. 未解释项 / 等谁落地

| # | 事项 | 现状 | 需要谁 |
| --- | --- | --- | --- |
| U1 | 板级抓帧件（屏上/帧缓存的真实像素） | 仓库里没有 ⇒ 表 A 对 manifest 全 `NOT_MEASURED` | P16a 运行脚本 + 一支读帧缓存的尺子（`src/host/ddr_verify.mjs` 目前只吃图案） |
| U2 | `data/golden/` 13 件的可复现产生程序 | manifest §8 记 13 件全含糊 | Q-P04-1 / Q-P17-2（队伍定权威产生方式，我不替定） |
| U3 | `data/metrics.csv:15` 的 141 条 | 点名的指纹盘上 0 件 ⇒ 该行是**陈旧数**；`metric_recheck` 射程不含它（它只认 timing/utilization/power 三份报告） | 队伍决定：重跑台架落地新数，或把该行改成 `NOT_MEASURED`（我不改 `data/`） |
| U4 | `data/golden/manifest.md` §5 打印 `磁盘 N=14 表里 N=14`，本轮现算是 **13/13** | 差 1 件，我没有动 `data/`，只登记差异 | P17 复核（可能是登记日之后删过/改名，也可能是那一次的计数口径） |
| U5 | Zynq 功耗档/供电读数 | 全仓库无一件自报 ⇒ 每张条件卡的"功耗模式"格都是 `【待补】` | 队伍给硬件侧口径 |
| U6 | `r117_board/` 是空目录 | r117 那一轮没有板级实测件可登记 | 队伍确认那轮是否真的没上板 |
| U7 | `data/metrics.csv:25` 把 **33.34 ms 挂在「端到端时延」**那一行上，并写"终点 = 示相机位录到该帧上屏"；V12 证明这个数是**帧间隔**（`gap_sum/gap_segments`，件内自报 `avg_gap_ms=33.3434`），而仓库里**没有任何示相机/采集卡件**；`report/perf_report.md:190-192` 自己说真时延那一行"数字等那一轮读完再往这行填" | 已在表 A 拆成 A6（时延，`NOT_MEASURED`）与 A6b（帧间隔，`PASS`）两行；**我不改 `data/`**（禁区） | 队伍二选一：把那行改成「帧间隔/抖动」口径，或补一次带仪器凭据的真时延轮 |

## 6. 自证（P16b 质量判据 1–6，判定放最后一个字段）

核对命令（可整条复制跑；本轮 11:5x 实跑，输出贴在下面，不是我手写的）：

```bash
A=$(grep -rhoE "data/golden/[A-Za-z0-9_.-]+\.(png|mem|md)" \
      board/raw-vs-golden.md board/captures/index.md board/compare/index.md \
      | grep -v "manifest\.md" | sort -u)
M=$(awk '/^\|[ ]*data\/golden\//{split($0,a,"|");gsub(/^[ \t]+|[ \t]+$/,"",a[2]);print a[2]}' \
      data/golden/manifest.md | sort -u)
echo "锚点 N=$(printf '%s\n' "$A" | grep -c .)  manifest 行 N=$(printf '%s\n' "$M" | grep -c .)"
comm -23 <(printf '%s\n' "$A") <(printf '%s\n' "$M")      # 应为空 = 每个锚点都能在 manifest 找到
node -e 'const fs=require("fs");let n=0,f=0;for(const l of fs.readFileSync("board/compare/golden-digest-verify.txt","utf8").split(/\r?\n/)){if(/^OK /.test(l))n++;else if(/^FAIL /.test(l))f++;}console.log("摘要相符 "+n+" 行 / 不符 "+f+" 行");'
```

实跑输出（原样）：

```
锚点 N=13  manifest 行 N=13
摘要相符 13 行 / 不符 0 行
```

（`comm -23` 那一行**没有输出** = 0 个锚点在 manifest 里找不到；锚点分母 13 = 12 张 PNG + 1 个 `.mem`，
`README.md` 不计，因为 manifest §3 自己写明它"不进任何比对表"。）

| 判据 | 一行结论（分母写在括号里） | 判定 |
| --- | --- | --- |
| 1 `compare/` 每行基准条目在 manifest 里找得到且摘要相符 | 档案里出现的 `data/golden/` 锚点 **13 个**，13/13 在 manifest §3 找得到、规范化 sha256 13/13 相符；**静默引用了不存在/摘要不符基准的行 = 0**（表 A/B 那 15 行没有 golden 基准，全部显式写"manifest 里没有这一类基准"并降级，不静默） | **PASS** |
| 2 每条实测结论能区分"硬件读出/软件算出" | 表 A（硬件读出侧，含 A6b 帧间隔）9 行、表 B（软件算出）6 行；混写行数 **0**（A3/A5 的"发送端/上位机"属性都在口径列点明） | **PASS** |
| 3 每条状态断言配有回读值 | 状态断言 5 条（A7：`src`/`sd`/`playing`/`frames`/`osd` + `drop_words`）⇒ **5/5 有回读**；无回读被降级的 **3 条**（A6 时延、A8 屏上角度、E4 对照腿"按住 KEY1 应读 1"） | **PASS（降级项已列全）** |
| 4 至少一份失败/异常记录被保留并进入分析 | 第 4 节列了 **8 条**，其中进入归因链的 ≥10 行原样件 4 份（`r75_sd_remount_before.txt` 全件、`issues.md:10909-10916`、`issues.md:8928-8943`、`r118_eyes/state.txt:16-19`） | **PASS** |
| 5 精度口径一致性（位宽/舍入都写明） | 表 A/B 15 行里 **15/15** 都有"精度口径"或"容差/单位"字样（A1 定点×1000+±5 ‰°C、A2 16 bit 256=1.00×、A3 16 bit lane、B2 报告 3 位小数 ns、B3 名册 `rel_margin=wns/period`）；未写明的行数 **0** | **PASS** |
| 6 比对由脚本产出（贴出调用与输出行） | `board/compare/` 13 个件、**12 张表**（V01–V12），每个件头有 `# CMD:` 原文（V12 还把复跑脚本正文附在件尾）；本轮我**没有手工填任何一个判定格** | **PASS** |

三态计数（本轮产出的 12 张表行，不是"被判的原子数"）：**PASS 8**（V01、V04、V06、V07、V08 射程内、V09、V10、V12）、
**FAIL/RED 2**（V02 名册两条红、V03 换尺子的旁证红）、**NOT_MEASURED 2**（V05 输入形状错、V11 基准指纹不符）。
（原子数按各脚本自己打印的：V01 判 18 项、V02 comparisons_made=32（both_NA=8 ⇒ 实比 24 对）、V03 判 44 项、
V08 判 114 个数、V09 全 65536 码 + 4 锚点 + 3 变异、V10 判 13 行。）
