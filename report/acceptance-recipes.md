# 观察配方集（P16c）

**这份文件回答三个问题：怎么把板子/屏幕/台架摆成"能被判"的状态、怎么看、怎么把看到的记下来。**
每条配方都点名它的凭据（本仓库真实存在的件）；**没有凭据的配方一条不写**——
所以这里没有"应该这样看"，只有"这样看过、留下了件、件在哪"。

迁移到别的题目时把三处换成你自己的：串口工具与端口号、命令表、归档目录名。
配方本身的形状（设态 → 读回前提 → 只看一件事 → 原话逐字入库）是通用的。

约定：以下所有"发命令"的位置都在**串口**（COM6，115200-8N1）；`STAT` / `split show` / `rot show` 都是回读动作，不改状态。
警告 串口一次只能被一个程序占用：自己开着终端占着时脚本会拒绝，那不是板子坏了（`board/README.md` 第 2 节那两条使用注意点）。

---

## R1 同屏 50/50 分区 + 关掉辅助叠加层（把屏幕摆成"最好判"的样子）

- **什么时候用**：要判"处理后的画面与原画面对不对得上""缝两侧同一行有没有上下错开"这一类**两侧比较**。
- **怎么设置状态**：双击 `send_demo.bat` 推流（内置测试图每帧都动）→ 串口依次
  `src 1`（把 UDP 通路钉给 PL）→ `split manual` → `split 50` → `split marker 0` → `split show`。
- **怎么看**：**同屏一次看两侧**，不要分次切换（分次切换会把"两帧之间的差异"读成"两侧的差异"）。
  看之前先确认 `split show` 那一行里的 `marker=off` 与 `pos=512/1024`。
- **怎么记录**：五行回读原样入库（`[STAT]`、`[SPLIT] manual`、`[SPLIT] 50%`、`[SPLIT] marker=0`、`[SPLIT] show`），
  然后写"谁看的 + 时间 + 他的原话"。
- **凭据**：`build/evidence/r92_eye_setup.txt`（那五条命令的原文清单，一共 7 行）与
  `build/evidence/r92_eye_capture2.txt:3,12,15,17`（逐字回读，其中 `:17` = `[SPLIT] pos=512/1024（显示列） = 50% manual marker=off`）；
  用它判过的两格在 `board/acceptance.md:89,71`（E1/E3，队员 2026-09-30 06:2x 原话"现在都很正常"）。
- **失效条件**：`marker=` 读成 `on` 时**不许**用这条配方判"两侧几何一致"——那条 2 像素蓝线会被眼睛念成一条缺陷线（R5）。

## R2 看 OSD 的 `ROT:` 那一格，不要猜角度

- **什么时候用**：任何需要知道"现在几度"的观察——包括判四角、判左缘、判上电那一度。
- **怎么设置状态**：不用设；这一格一直在屏第二行。
- **怎么看**：读屏第二行 `ROT:` 那一格的**数字**（`src/rtl/video/osd_overlay.v:288-295`：那一格印的是十进制度数 0..359 带 `°`）。
  **不要**从"画面看起来转了多少"反推角度，也不要拿 `Zoom:` 那一格当倍率读数源（它只有八档标签 `0.25/0.33/0.50/0.75/1.00/1.33/1.50/2.00x`）。
- **怎么记录**：把那一格的读数原话写进记录（例：「0度」），并同时记"当时板上是哪块 bit"。
- **凭据**：`board/acceptance.md:98`（E6 那一判的原话就是"0度"，判法明写"只看屏第二行 `ROT:` 那一格"）；
  为什么不能靠串口：`report/log/issues.md:4693-4696`（#100：`ROT SHOW` 只念 `auto/speed/deg/frame`、`STAT` 末尾的 `geom=` 里也只有位字段，**串口没有任何"当前角度"读数**）；
  以及 `report/log/issues.md:11816-11818`（#274：串口读不到角度——`status` 口那 9 位在 `system_top` 没有读者）。
  误读实例：`board/acceptance.md:90` 里那句「1 rot 在走 zoom 是 0.52 没有 3 没有」——`0.52` 不是任何一格的标签，
  全树搜 `0.52x` 只在 `src/rtl/process/zoom/zoom_ctrl.v:59` 的一句**注释**里出现 ⇒ 已回问出处，未证实之前不当倍率读数用。
- **失效条件**：`osd=0`（OSD 关着）时这一格根本不存在；先读 `[STAT] … osd=1` 再谈看它（`build/evidence/r118_eyes/uart_stat.txt:1`）。

## R3 把旋转"冻"在当前角度，再 ±1° 走

- **什么时候用**：要判"某个固定角度下四角在不在屏内 / 左缘有没有彩条"。
- **怎么设置状态**：`src 2` + `bilin on` + 手动 `zoom 1.0` + **`zoom fit 0`**（钳制要在"拟合关着"时才看得见）+ `rot auto 1 speed 0`。
- **怎么看**：发 `rot auto 0` ⇒ 板子**冻在当前角度**（不是归零！），看屏 `ROT:` 那一格记下度数；要精调就按板上 **KEY1/KEY2** 走 ±1°。
  串口没有"把角度归零"的动词，所以别去命令表里找它。
- **怎么记录**：记三件：冻住后的度数（眼睛读）、`rot show` 的回读（`auto/speed`）、以及四角/左缘各答一句原话。
- **凭据**：`board/acceptance.md:72-75`（这套设态与"冻在当前角度"的写法）；
  `board/acceptance.md:56`（G3x 那条判据从"bit19 回 0"改成判同一个不变量，理由就是"命令表里**没有**把角度归零的动词"，见 `#200`）；
  末态回读件 `build/evidence/r104_rotfringe_state.txt`；屏已摆在 `build/r95_eye_park.txt` 记的末态 `geom=00400A00`。
- **失效条件**：`zoom fit 1` 时旋转钳会把倍率顶到别处，四角判据就不干净；`speed` 不为 0 时画面每帧都在换角，眼睛没法判固定角度（R12）。

## R4 写缝位不许清掉 marker 位（`split 50` 之后 marker 位不变）

- **什么时候用**：任何时候你刚发过 `split <百分比>`，又打算用屏幕上的"线"做判据。
- **怎么设置状态**：`split marker 0` → `split 50` → `split show` → `split marker 1`（这一组是电池里的四条，逐条判）。
- **怎么看**：只看 `split show` 回包的 `marker=` 那一栏。
- **怎么记录**：把 `split show` 那一行原样入库；电池里把它做成一条判据而不是散文。
- **凭据**：`report/log/issues.md:4690-4692`（#102 那一节记的毛病：`我第一次发过 SPLIT MARKER 0 之后，再发 SPLIT 20 用户就看到屏幕中间多出一条竖线`
  ⇒ **`SPLIT <百分比>` 会把标记线的使能位重新打开**；修法是"`split <n>` 只改位置，不碰 marker 位"，并在电池里补一条"`split 50` 之后 marker 位不变"）；
  落地成判据的那一组四条在 `report/log/issues.md:6803-6806`（#105，判"**写缝位不许清掉 marker 位**"，板上 105 条全绿，件 `build/r95_batt_from_default.txt`）。
- **失效条件**：如果你的命令表本来就把 marker 与缝位合在一个字里，这条配方要换成"读回控制字的**位**"而不是读回显。

## R5 前提没锁住 ⇒ 这一轮的结论不许升（"那条线是不是 2 像素蓝标记"）

- **什么时候用**：眼睛报回来一条线/一个影子，而你还没确认叠加层的开关状态。
- **怎么设置状态**：把要排除的叠加层显式关掉，然后**读回它关没关**（`split show` 的 `marker=`、`[STAT]` 的 `osd=`、`bilin=`）。
- **怎么看**：关之前看一次、关之后看一次；两次都在同一缩放档、同一缝位。
- **怎么记录**：如果前提没锁住，就按"**仍未定归属**"写，不许写"排除了某解释"。
- **凭据**：`report/log/issues.md:4823-4836`（同一轮里两次否证但因为没确认 `split marker 0` 而**结论不升**的完整过程；
  07:4x 前提锁住之后才写"不是那条 2 像素标记（它画的是深蓝 `8'h40/40/FF`，见 `split_display.v:64-65`）"）；
  `board/acceptance.md:90` 里那句"当时**标记线有没有关**我没问到，所以'缝两侧'那一判是在标记状态未证下给的"是同一个规矩的反面教材。
- **失效条件**：叠加层没有回读口的话这条走不通——只能把"读不到前提"记成 `NOT_MEASURED`（R2 的串口角度就是这种欠账）。

## R6 零样本地板：任何"计数器 = 0"的读数必须同一份读数里带 `eth_live=1`

- **什么时候用**：读 `drop_words` / `pkt_err` / `stall_ms` / 丢帧数这一类"0 就算好"的计数。
- **怎么设置状态**：起流（`python src/host/video_sender.py --demo --seconds 50 --fps 60 --pace-mbps 0` ≈147 Mbps），**流在跑的时候**读。
- **怎么看**：同一份 JSON/同一份回显里同时找两个字段：`src_state.eth_live`（或 `owner_eth`）与那个计数。
- **怎么记录**：`eth_live=0` 的时候那个 0 记成"未测"，不记成 0；判据表里数值填 `—`、类别填"未报"。
  警告 看寄存器就先停止推流是**另一条**规矩（`board/README.md`：流在跑时读到的计数是中间值）——两者别混：
  这条要求"曾经有过流量"，那条要求"读的瞬间要稳"。落地做法 = **同一会话里连读两次，两次包数在涨**（R11）。
- **凭据**：`report/log/issues.md:12782-12790`（#316 全文，含立的那两条规矩）；
  活标本两件：`build/evidence/r118_board/board_verify_console.txt:18,21`（同一份读数里 `"eth_live":0 … "why":"没有流"` + `drop_words → 0`）与
  `build/evidence/r116_board/health_r118build_a.json`（`"eth_live":1,"owner_eth":1` 与 `"drop_words":0` 同一份，另有 `pkt_err":0`、`"flags_bits":{"drop_seen":"0","stream_live":"1"}`）；
  用它写的两格在 `report/measurements.md` 第 1 节"ETH 入流零丢字"那两行。
- **失效条件**：如果这个计数器在你这一路根本没有"活样本"出口（读不出非零值），那"0"就什么也不说；先做一条能把它顶非零的注入。

## R7 冷上电三步链 + 全程不碰按键（把"上电那一度"做成可判的状态）

- **什么时候用**：任何"开机不许自己改状态"的判据；也用于确认"链子跑完了、板子活着"。
- **怎么设置状态**：板子断电 **≥10 s**（让 4.7 kΩ/100 nF 那两只脚彻底放掉）→ 上电 → **只跑**
  `build/tcl/ps_jtag_boot.tcl` → `program_pl.tcl` → `ps_app_reload.tcl`（顺序不能换，PL 没烧之前应用起不来）→ 全程不碰 KEY1/KEY2。
- **怎么看**：先读 `[STAT] … osd=1`（确认那一格会被画出来），再看屏 `ROT:`（R2）。
- **怎么记录**：三份 stdout 各存一份（`step1_boot.txt` / `step2_program_pl.txt` / `step3_app.txt`）+ 一份 `state.txt` 汇总 rc，
  并且把"刷进 PL 的位流 md5"写进同一份汇总（不是写在脑子里）。
- **凭据**：`build/evidence/r118_eyes/state.txt:8-10,16-17`（三步 rc 与 `md5sum build/system.bit` 逐条对回归档件）+
  同目录 `step1_boot.txt:3-6`、`step3_app.txt:4,11,22`、`uart_stat.txt`、`uart_stat2.txt`（两次 3 s 间隔的 `frames=4398` 不变）；
  **操作账**（很值钱）：`state.txt:13-16` 记 07:39 那一次死在 `targets -set 1`（`hw_server` 冷上电后还没重新枚举链路），
  等它枚举成 `1=APU / 2=ARM#0 / 3=ARM#1 / 4=xc7z020` 之后**原脚本一字未改就过了** ⇒ "冷上电后第一步就 REFUSE" ≠ 板子或脚本坏了，
  先重连一次看枚举表（只读探针 `build/tcl/probe_target_select.tcl`），再决定要不要动脚本（`report/log/issues.md:13095-13097`）。
- **失效条件**：需要按住按键的那一组（对照组）要**再断一次电**，不能在上一次会话里补做（`board/acceptance.md:98`）。

## R8 温度三方对账 + 原始回显必须是"被跟踪件"而不是手抄

- **什么时候用**：板上有多个"同一物理量的不同出口"（驱动读数 / 屏上三字符 / 写进 PL 的 gpio）时要交叉核对。
- **怎么设置状态**：跑一次带电池温度的板级校验：`VP_XSDB=<Vitis>/bin/xsdb.bat bash build/board_verify.sh --battery --geom`。
- **怎么看**：看电池输出的 `V9-6 温度格三方对账` 那一条；逐条数值去 grep 原始回显，不要抄控制台。
- **怎么记录**：脚本自己产出的**被跟踪**那份原始回显（`build/evidence/rNN_serial_raw.txt`）+ 一条"地板"计数（`[TEMP]=2 判定=绿（地板 2）`）。
  多轮的极值另 grep 成一份件（`build/evidence/r113_temp_lines.txt` 那种写法），逐字不改。
- **凭据**：`build/evidence/r118_board/board_verify_console.txt:15,61`；`build/evidence/r118_serial_raw.txt:1,3`（两条 `[TEMP]` 全文）；
  为什么必须是被跟踪件：`report/log/issues.md:11795-11808`（#273 那一节：以前靠手抄三条读数，这一轮改成脚本自己产出并被跟踪的回显）与
  `build/board_temp_r97.txt:6-7`（"原始捕获文件 `board/uart_script_capture.txt` 被 `.gitignore` 挡着……所以这里把那三条抄成随包件——指路必须指到一个真在包里的文件"）。
- **失效条件**：`board/uart_script_capture.txt` 此刻在盘上但**不随包**（`.gitignore:134` 命中 `board/uart_*.txt`）⇒ 只当"现场核对"用，别当交付凭据。
  另一条：不同工况（空载 / SD 在播 / 电池负载）的温度**不可比**（`build/board_temp_r97.txt:4` 就把"抓的时候 SD 在播"写进头注）。

## R9 凭据存在性清点（一条命令，指到目录 = 0 容忍）

- **什么时候用**：写完/改完任何"指标表 / 验收记录"之后，交出去之前。
- **怎么用（两段：先验"某一列"，再验"全文"）**：

```bash
cd <仓库根>
# ① 只验指标表那一列（这是 0 容忍真正管的东西）
awk -F'|' '/^\| /{ n=NF-1; if(n>=7) print $n }' report/measurements.md \
  | grep -oE '`(build|board|data|src|sim|report)/[^`、]+`' | tr -d '`' \
  | sed -E 's/:[0-9].*$//' | sort > /tmp/ev2.txt
tot=$(wc -l < /tmp/ev2.txt); miss=0
while read -r p; do [ -f "$p" ] || { miss=$((miss+1)); echo "MISS $p"; }; done < /tmp/ev2.txt
echo "逐格点名=$tot 缺=$miss 唯一=$(sort -u /tmp/ev2.txt | wc -l)"

# ② 全文清点，分三桶：A=真指路却不在盘上（必须 0）／B=通配或占位写法／C=目录句
for doc in report/measurements.md board/signoff.md report/acceptance-recipes.md board/signoff-questions.md; do
  A=0;B=0;C=0;T=0
  while read -r p; do T=$((T+1)); [ -f "$p" ] && continue
    case "$p" in *"("*|*"*"*|*"NN"*|*"<"*|*"（"*) B=$((B+1));; */) C=$((C+1));; *) A=$((A+1)); echo "A MISS $p";; esac
  done < <(grep -o '`[^`]*`' "$doc" | tr -d '`' | grep -E '^(build|board|data|src|sim|report)/' \
           | sed -E 's/:[0-9].*$//' | sort -u)
  echo "$doc 点名=$T 命中=$((T-A-B-C)) A=$A B=$B C=$C"
done
```

- **怎么记录**：把两段的输出都落进 `build/evidence/p16c/evidence_existence.txt`（或你这一轮的证据目录），
  并在文档里写"逐格点名 n / 缺 m / 唯一 k"，而不是只写"已核对"。
- **凭据**：实得 `逐格点名=122 缺=0 唯一=48`（`report/measurements.md` 的证据文件列，100 % 命中）；
  全文四份文档的分桶结果与逐条 B/C 清单在 `build/evidence/p16c/evidence_existence.txt`。
- **失效条件 1**：带通配符或占位的写法（`build/tb_edge_rim_r*.txt`、`build/evidence/rNN_serial_raw.txt`、`build/evidence/<本轮>/…`）
  会被判成 B 桶而不是 A 桶——那是**写法**，不是指路；但一份文档里 B 桶变多通常说明有人在用通配糊弄指路，要逐条看。
- **失效条件 2**：`report/log/` 那类追加式日记里点名的"当时存在、随后删掉"的中间件**不该**判红
  （判据范围见 `src/host/doc_currency_check.mjs:148-175` 那段：出处在交付文档里才判红，日记与注释只报数）。
- **失效条件 3（自指，本仓库真踩过，#333）**：这条清点**把这几份文档自己也算进射程**——
  往这几份文件里多写一条路径，下一次跑的"点名/命中"数就会变。所以表里的数是**这一跑的快照**，
  复跑得到不同数是正常的，别把它当成回归；要的是 A 桶恒为 0。


## R10 位流身份三处同源（工作区 md5 ↔ `git show HEAD` ↔ 归档件）

- **什么时候用**：每次你要说"这一格是在 rNN 上验的"之前。
- **怎么用**：

```bash
md5sum build/system.bit
git show HEAD:build/system.bit | md5sum          # 读回 HEAD，**不读工作区**
md5sum build/evidence/rNN_bit/system.bit
sed -n '1p' build/evidence/rNN_bit_md5.txt
```

- **怎么记录**：四个值写进同一份汇总件（`state.txt` 那种形状），并把"板上现在 = rNN"那句的来源点名到 `board_now.txt:1`。
- **凭据**：`report/log/issues.md:13075-13094`（#332 全文：r118 那支"采纳笔"**只带了文档没带 bit/报告**，
  是 `git show HEAD:build/system.bit | md5sum` 抓出来的 ⇒ 规矩改成"提交之后**读回 HEAD** 验身份"）；
  今天跑出来的四个值同源：`cd04907e1369da35d21c4090d552f5ee`（`board/signoff.md` S1 逐条引了出处）。
- **失效条件**：只做工作区 md5 的话，"文档写 r118、盘上是上一版"这种形状抓不住（#332 就是这么发生的）；
  只信 `board_now.txt` 的自述也不行——它自己那句刷入时间还和链子日志差 2 分钟（`board/signoff-questions.md` 第 1 轮 Q3）。

## R11 用"只改一个变量"的 A/B 把暂态与缺陷分开

- **什么时候用**：眼睛报回一条"看起来像缺陷"的现象，你怀疑它是切换瞬间的暂态，或者怀疑它属于上一版。
- **怎么用**：两种同族做法，都只动一个变量：
  ① **只改推流节奏**：25 fps 看一遍 → 29.76 fps 复推再看一遍 → 若两档现象相同，说明它不随节奏出现。
  ② **回刷上一版做对照**：把上一版的位流重新刷上板，同一判据读两遍，与本版两遍逐格对比 ⇒ 归属就落到"是不是这一版带来的"。
- **怎么记录**：把 A/B 四个读数（本版两次 + 上一版两次）都留件；写结论时只说"未复现"或"逐格相同 ⇒ 归属某版"，
  不要顺手写"所以是软件问题/硬件问题"。
- **凭据**：①的做法在 `board/acceptance.md:90`（`我用**只改推流节奏**做了对照（29.76 fps 一条、复推 25 fps 仍一条）⇒ **未复现**，判为切换瞬间的暂态，不记缺陷`）；
  ②的做法在 `report/log/issues.md:12803-12816`（#318：`frames_bad=1` 用**回刷 r114 做 A/B** 查清了归属，件
  `build/evidence/r116_board/cycle_r114back.log`、`health_r114back_a.json`）；两次读数包数在涨的那一份是 R6 要的活样本证据。
- **失效条件**：如果这个现象的发生率本来就低（例：`#189` 台架量到 ≈0.27 %，3726 个旋转态像素命中 10 个），
  **A/B 的"没看到"不等于"没有"** ⇒ 要换机器尺子（R12）。出处 `board/acceptance.md:90` 末尾那句限定。

## R12 眼睛只判"有没有 / 哪个档"，宽窄与稀疏度交给机器

- **什么时候用**：你正准备问队员"它是不是随速度变宽/变乱"这类**连续量**。
- **怎么用**：把问题降到眼睛分得开的档位——本仓库量过的唯一可分辨差分是"每帧换角 = 0 档 vs ≥1 档"。
  连续量（位移多少源像素、发生率百分之几）用台架量：只用 DUT 自己的输出，不在外面重算映射。
- **怎么记录**：问题原文与回答原文都逐字入库；预测被打脸的那一句要留着并写明"被打脸"。
- **凭据**：`report/known_issues.md` 第 1 节末尾（`我给的定量预测被眼睛判掉了一半 … **眼睛在"宽窄"这一档是饱和的**；
  它真正分辨得开的是"有没有每帧换角"`）；机器那一侧的读数 `build/r105_tb_head_rot_displace.txt`（`RESULT … PASS cells=49152 pairs=12`；
  45° k=1/2/7 最大 5/9/31 源像素，k=0 那一档三个角度各扫两遍逐位相同 ⇒ 台架自己不漂）；
  另一处同族教训 `report/log/issues.md:10080-10089`。
- **失效条件**：如果这个现象**只有**眼睛能看（例如 OSD 上那格数字，`src/host/ps/main.c` 里根本没有 fps 读者），
  就别硬造机器判据；那条永远不进门禁（`board/acceptance.md:84-85`）。

## R13 逐轮读数**不覆盖**，就地新开一节写这一版

- **什么时候用**：同一份验收表被新一轮构建重跑/重念时。
- **怎么用**：原行一个字不动，在下面加一节"rNN 重跑的那几行"，每行点名它自己的件；
  没重跑的那几行就写"没有被 rNN 盖章"，并说明为什么（本仓库那格的成因是"板子在自动旋转"）。
- **怎么记录**：表头写清本版位流 md5 与构建时刻；跨轮之差**既不记收益也不记损失**（规矩 35）。
- **凭据**：`board/acceptance.md:30-42`（r96 那一节，`:32` 那句就是原话：`上表的原行**不覆盖**（留作历史读数）`）与
  `board/acceptance.md:48-59`（r97 那一节同写法）；`:9-10` 那句"先看这一行有没有'r94'字样"是同一条规矩的读法侧。
- **失效条件**：`build/` 下那些**单文件**报告（`build/tb_v98_report.txt`、`build/timing_summary.rpt`）没有"另开一节"的保护，
  下一轮直接覆盖 ⇒ 所以指标表引用它们时必须同时引 provenance 行（`report/measurements.md` 第 5 节 G1 就是这么抓出来的）。

## R14 摘要行里出现 `?` = 尺子读不出来，判原始件而不是那行摘要

- **什么时候用**：脚本给你打了一行"漂亮摘要"（`a: eth_live=1 drop_words=0 pkt_err=?`），而你正要拿它当凭据。
- **怎么用**：把 `?` 当成"这个字段这次没读到"，回到脚本写的原始件（JSON / 报告全文）逐字段读；
  判据只写你真的读到的那几个字段。
- **怎么记录**：在记录里同时点名"摘要行说 ?、原始件里是什么"，否则下一轮没人知道那次到底读没读到。
- **凭据**：`build/evidence/r118_board/bitcycle_console.txt:31-32`（`pkt_err=? frames_bad=? drop_seen=?` 三个问号）对照
  `build/evidence/r116_board/health_r118build_a.json` 里的 `"pkt_err":0`、`"frames_bad":1`、`"flags_bits":{"drop_seen":"0"}`；
  把"读不出来的字段显式化"立成规矩的那一条是 `report/log/issues.md:12803`（#318 标题后半句）。
- **失效条件**：如果脚本只在摘要里落这些字段、原始件不存盘，那这次运行对这些字段就是 `NOT_MEASURED`，
  不许用摘要里"看起来对"的那几个字段代替。

## R15 "跑完必须回到默认档"要求"跑之前先把板子摆回默认档"

- **什么时候用**：任何带"初态 = 末态"判据的命令串。
- **怎么用**：先读 `STAT` 确认初态；不在默认档就先设回默认档，再跑那一串。
  如果某条中间判据的**前提**是上一条命令造成的（比如要先 `rot auto 0` 再看角度），就让**串自己构造那个前提**，
  而不是假设起点是干净的。
- **怎么记录**：把"起点是哪一档"写进输出（本仓库那种 `NOTE 初态 = 文档默认档（zsel=4 zman=1 mode=0 AUTO）⇒ 上面那条"回到初态"是在默认档上证的` 就是标准写法）。
- **凭据**：`report/log/issues.md:6795-6802`（#178 那一课：判据的 precondition 必须由串自己造出来，
  件 `build/r95_batt_before_178_verdict.txt`（离线复现第 83 条 FAIL）→ `build/r95_batt_from_parked.txt` → `build/r95_batt_from_default.txt`（`RESULT PASS`）；
  里面还有一句反面提醒："别把它读成'起点无关所以随便跑'"）；
  本版那条 NOTE 的原文在 `build/evidence/r118_board/board_verify_console.txt:60`。
- **失效条件**：如果这一串中途被看门狗/断电打断，"末态 = 默认档"这句作废，要从头再跑一次并留新件。

---

## 索引：哪一格用了哪条配方

| 观察格 | 用的配方 | 现状 |
|---|---|---|
| E1 / E3（两侧几何一致、无撕裂） | R1 + R5 | r92 签收过；r118 未重判 ⇒ 第 3 轮 Q8 |
| E2（缩放 + 自动旋转不错位） | R1 + R2 + R11 + R12 | r92/r93 与 r103 签收过，带两条限定 |
| E4a（四角在屏内） | R3 + R2 | r118 已判（原话「现在屏幕没问题了四角都在屏幕内」） |
| E4b（左缘沿对角的彩条） | R3 + R4 + R5 | 未判 ⇒ 第 1 轮 Q1 |
| E4c / E4r（屏顶碎影） | R3 + R12 + R14 | 归属已答；"几行"那一问未答 ⇒ 第 3 轮 Q7 |
| E5（OSD `FPS:` 那一格） | R2 + R12（只能看屏） | r101 签收过；三档射程待确认 ⇒ 第 1 轮 Q2 |
| E6 / E6b（上电那一度） | R7 + R2 | r118 读 0 已判；对照组未做 ⇒ 第 2 轮 Q6 |
| S6 / S7 / S8（默认档、带流零丢字、零样本） | R6 + R14 | 带流那半 PASS；空闲那半 NOT_MEASURED |
| S1（位流身份） | R10 | PASS；刷入时刻待澄清 ⇒ 第 1 轮 Q3 |
| 指标表每行的"证据文件"列 | R9 | 命中率与缺项见 `build/evidence/p16c/evidence_existence.txt` |
| 逐轮读数怎么不漂 | R13 + R14 | 三条不同源登记在 `report/measurements.md` 第 5 节 |
| 温度 / 三方对账 | R8 | PASS；"4 条逐条值没有单独被跟踪件"这条射程不足记在 `board/signoff.md` L12 |
