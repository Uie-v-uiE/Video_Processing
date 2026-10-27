# `corrections.md` · 自我纠错轨迹（P22 铁律 2：三件成对）

每条三件，**顺序固定**：

1. **错误断言原文**（带会话与位置指针，原样抄，不美化、不改写）
2. **把它否掉的判别实验或证据**（命令 / 文件:行，逐个打开确认存在）
3. **更正后的结论与影响范围**（含"这条更正还欠什么"）

取证范围：本仓库已入库的成文轨迹（开发台账、时序债务账）
+ 本次 P22 取证过程中**新发生**的两条（C7 grep 误读、C8 写下的锚点失效）。
会话侧指针一律用 `S01 + 北京时间段 + 人工轮次区间`（轮次表在 `sessions/s01…md` 与 `../metrics.md` §2；
人工轮次编号 `H01…H226` 由同一条命令按时间序生成，命令见 `../metrics.md` §2）。

> **本文件的写法本身受 C3 约束**：`report/` 在门禁的扫描射程内，所以
> ① 本文件不写任何"代码文件:超范围行号"形式的引用（C3 里那条把 D5 拖红的具体锚点，§C3 用文字描述而不复制其形式）；
> ② 写入前后各跑一次 `node src/host/doc_enc_check.mjs` 与 `node src/host/line_cite_check.mjs`（读数见 §5）。

---

## C1 · 负 slack 被读成 null ⇒ 一条判据同时给正例和反例同一个答案

**① 错误断言原文**（条目 #321，起于 开发台账；引文见 `:12859-12861`）

> 后果有两种，且**两种都长成红**，所以没有任何一条读数能把它们区分开：
> ① 首页把 −0.846 写对了 ⇒ 读成 null ⇒ 红；② 首页写 0.846（丢了负号）⇒ 也红。
> 这就是 rule 46 那一类："一条判据若正例与反例给同一个答案，它就没有射程。"

（同条目 `:12857` 给出坏掉的取数式：`src/host/metric_recheck.mjs` 首页那一层的四个式子全写成
`[0-9]+\.[0-9]+`，**没有符号位**。）

会话指针：`S01`，北京时间 2026-10-04 03:0x，人工轮次区间 H224（10-03 15:19）→ H225（10-04 07:38）之间，
即无人值守段；不是人指出来的，是**合成对照跑出来的**。

**② 判别实验**

```bash
node src/host/metric_recheck.mjs 2>&1 | grep -i SELFSIGN-SUMMARY
```

本次实跑输出：`SELFSIGN-SUMMARY 判 6 条（负数可读=绿、负数写错=红），红 0`。
六条 = `wns`/`clocks`/`whs` 各一对（已知绿的负数必须全绿、已知写错的负数必须仍红），
成对反例的存在正是"这条判据有射程"的证明（开发台账）。
修复的代码锚点：`src/host/metric_recheck.mjs:46`（`sgn()` 把 U+2212 折成 ASCII 减号再交 `Number()`）、
`:95` 与 `:138`（两处取数改走 `sgn()`）。

**③ 更正后的结论与影响范围**

- 结论：**"读不到 = null = 判红"这个防空转的规矩没有错，错在它的前提**——取数式必须能读全值域。
  值域里出现负数之后，"红"不再能区分"文档坏了"与"文档写对了但尺子看不见"。
- 影响范围：首页 headline slack 四处取数 + 所有引用首页数字的交付文档行。
  当晚一次正常跑给出 23 条 `RED` 清单（开发台账）；
  **本次复跑同一命令的 `^RED` 行数是 4**（`node src/host/metric_recheck.mjs 2>&1 | grep -c "^RED"` = 4）
  ⇒ 差额不是矛盾，是改口轮已经走完（那一轮的逐轮页 第六节是那 23 条的去处）。
- 由此产生的技能条目：`skills/pitfalls/report-field-parse-breaks/SKILL.md:70`、`:110`（`:110` 直接点名 #321）—— 这些行号是当时旧包平铺卡的读数，那些卡在 2026-10-04 c7b325f 重建后**现不存在**，本行只报数不指路。

---

## C2 · "位流已经提交了"是被脚本的打印骗的，`git show HEAD:` 一读回就翻

**① 错误断言原文**（条目 #332，起于 开发台账；`:13079`、`:13083-13084`）

> `git log --oneline -- build/system.bit` 的最后一支停在 `cd33367`（r116 收口），也就是说 r118 那两支提交
> （`1601548`/`5fb0740`）只带了文档，**没带 bit / xsa / `build/*.rpt` / `build/report/` / `build/tb_v98_report.txt`**
> ……`COMMIT staged=4` ⇒ `git add` 是原子的，一条路径不存在就整批不暂存……
> 脚本死在这里，**但它死之前那一步已经"看起来成功了"**，所以我把它当完成了。

会话指针：`S01`，北京时间 2026-10-04 07:4x–07:5x，人工轮次区间 H225（07:38「我现在已经重新上电了让我判什么」）
→ H226（07:51，内容只有两个字「0度」，见 `board/acceptance.md:92` 的 E6 格）。

**② 判别实验**

```bash
git show HEAD:build/system.bit | md5sum
md5sum build/system.bit
md5sum build/evidence/r118_bit/system.bit
git log --oneline -3 -- build/system.bit
```

本次实跑（三个 md5 **必须相等**才算这条更正落地）：

```
HEAD  build/system.bit md5 = cd04907e1369da35d21c4090d552f5ee
WORKTREE build/system.bit md5 = cd04907e1369da35d21c4090d552f5ee
evidence r118 bit md5      = cd04907e1369da35d21c4090d552f5ee
d420db6 r118 的位流与实现报告第一次真正进 git（#332），并补上 E6 的人眼签收与两条工具账
```

当年现场读数是 `bb2fb707aebc…`（HEAD 里还是 r116 那块）vs 工作区 `cd04907e1369…`（r118），
记在 开发台账；回读件本身入库为 `build/evidence/r118_eyes/head_bit_md5.txt:1-3`
（第一行原话就是 "read-back of the COMMITTED tree, not the worktree"，`commit=d420db6`）。

**③ 更正后的结论与影响范围**

- 结论：**"板上有 / 工作区有 / HEAD 里有"是三件事**；采纳笔必须读回 HEAD 验身份，不能读工作区。
  清单里每条路径先做存在性计数再 `git add`，缺一条 REFUSE 整批（开发台账）。
- 影响范围：所有"采纳笔"（位流、`.xsa`、`build/*.rpt`、`build/report/`、台架报告）。
  这是 rule 42 的**复发**（开发台账 自陈：我以为那条规矩已经变成了脚本，
  可是脚本对自己的产物只打印、不核对）⇒ 光有脚本不等于有判据。
- 由此产生的技能条目：`skills/pitfalls/exit-zero-nothing-written/SKILL.md:89`、`:109`（`:109` 点名 #332）—— 当时旧包平铺卡的行号，那些卡 c7b325f 重建后**现不存在**，只报数不指路。

---

## C3 · 为保险留的那份 `.md` 备份，把远端门禁自己拖红了

**① 错误断言原文**（条目 #333，起于 开发台账；`:13100`、`:13105-13106`）

> 07:5x 我要往 开发台账 追加 #332，先按纪律留了一份"改前快照"
> `build/evidence/r118_eyes/ISSUES_before332.md`（事后证明这份快照是**纯前缀**……所以它唯一的用处就是当对照，用完就该删）。
> ……归到已有规矩的那一半：射程自动扩大……D5 的扫描集是"仓库里所有 `.md`"，
> 所以我随手写在 `build/evidence/**` 的一份历史快照**就是**交付文档，它带着注定过期的行号，就一定会红。

（备份里那些"当时对的行号"随正文下移越过了目标文件末尾——指向 `pl_video_top.v` 的第 1067 行，
而该文件只有 1051 行。本行**故意不复制 `文件:行` 那种写法**，否则这份档案自己就会踩同一条坑。）

会话指针：`S01`，北京时间 2026-10-04 07:5x–08:0x，H226 之后的纯无人值守段。

**② 判别实验**

```bash
# (a) 它是纯前缀的三条等式（当年实跑，记在 开发台账）
git show HEAD:开发台账 > /tmp/head.md      # 与备份逐字符比 + cur.startswith(head)
git diff --numstat -- 开发台账             # 当时 = 23 0（只增不删）
# (b) 门禁两次读数
grep -n "GATES" build/evidence/r118_board/g1b.txt
cat build/evidence/r118_board/gatesc_summary.txt
# (c) 删掉备份之后，本次复跑那两把尺子
node src/host/line_cite_check.mjs | tail -2
ls build/evidence/r118_eyes/ISSUES_before332.md
```

本次实跑读数：

- `build/evidence/r118_board/g1b.txt:59` = `GATES: 有红项（判定 24 项）—— 不采纳，保留上一版`（这一轮 21 绿/3 红）
- `build/evidence/r118_board/gatesc_summary.txt:1` = `GATESC done id=identical green=23 red=1`（删备份并定版之后）
- `node src/host/line_cite_check.mjs` = `D5: CLEAN`、硬错 0 条
- `ls …/ISSUES_before332.md` = `No such file or directory` ⇒ 删除动作确实发生，且**已随 C2 的修法把 #332/#333 正文入库**

**③ 更正后的结论与影响范围**

- 结论：一个"只读保险"动作可以制造判红，而且**红的位置离动作很远**（备份在 `build/evidence/`，
  红在门禁第 14/18 项）。纪律改为：给会被扫描的文件留快照时落到 `*.txt`（不在 D5/D1 的扫描形状里）
  或直接靠 git（HEAD 本身就是那份快照），**不要在仓库里造一份带旧行号的 `.md`**（开发台账）。
- 连带面：D1c 会因为基准件恰好是这次 3 红的运行而**被拖着红第二项**（`:13103`）⇒ 脏数据能串两项。
- **对本次交付的直接约束**：我这 7 个文件全在 `report/collaboration/`（射程内），
  所以写入前基线 `扫了 534 个手写文件：全部干净` / `D5: CLEAN 硬错 0`，
  写入后复跑读数见 §5；两份读数的差值只允许来自"文件数变多"，不允许出现硬错。
- 由此产生的技能条目：`skills/pitfalls/assertion-not-in-any-file/SKILL.md:95`（点名 #333；旧包平铺卡的行号，该卡 c7b325f 重建后**现不存在**，只报数不指路）、
  `skills/pitfalls/checker-ran-on-nothing/SKILL.md:84`、`:95`（同上：重建前的旧包平铺卡名，**现不存在**）。

---

## C4 · 探针字段读空被当成"设计里没有"（工具的沉默不是证据）

**① 错误断言原文**（条目 #334，起于 开发台账；`:13122-13124`、`:13132-13134`）

> 同一个脚本读 `get_property CLOCK [get_ports tmds_*]` ⇒ **十个端口全部 `clock=` 空**。
> 这**不是**"TMDS 输出没有时钟"，而是 `CLOCK` 这个属性在 port 对象上不是"驱动时钟"的意思……
> 如果我就此写"输出脚无时钟 ⇒ 只能 set_max_delay 或干脆不管"，就是把工具的沉默当证据。
> ……探针**报错会把自己打死**，而打死之后留下的"缺行"看起来像"没有这个东西"。

会话指针：`S01`，北京时间 2026-10-04 09:0x，无人值守段（H226 之后）。

**② 判别实验**

```bash
grep -an "^CLK|"   build/evidence/r119_tmds_clock_probe.txt     # 8 条时钟，period 全读出来了
grep -an "^PORT|"  build/evidence/r119_tmds_clock_probe.txt     # 10 行 clock= 空
grep -an "^LAUNCH|" build/evidence/r119_tmds_launch_probe.txt   # 换问法之后的那份件
```

本次实跑：`build/evidence/r119_tmds_clock_probe.txt:50/52/54/56` 是
`CLK| clk_fpga_0 | period=10.000 | src=PROP_ERR:ERROR: [Common 17-54] …`（属性名改对后时钟读到，
`SRC_TYPE` 那一路仍然读失败但被 `catch` 成 `PROP_ERR` 原样打印）；
`:67-76` 是十行 `PORT| … | clock=` 全空；第二支探针 `build/tcl/probe_tmds_launch_clock.tcl`
的件 `build/evidence/r119_tmds_launch_probe.txt` 尾部打印 `LAUNCH| led[0] | {Path Group: (none)}`，
即"这颗输出被哪条时钟发出"要问 `report_timing`，不能问 `CLOCK` 属性。

**③ 更正后的结论与影响范围**

- 结论：**属性名/列序/字段位置都属于"工具的形状"，只能量不能记**；
  只读探针的规矩加一条：任何一次 `get_property` 都要 `catch` 住并把读失败原样打出来，
  宁可打印 `PROP_ERR:…` 也不许让整支脚本退出——退出 = 后面几层一个都没测 = `NOT_MEASURED`，
  而 `NOT_MEASURED` 与"没有"是两句完全不同的话（开发台账）。
- 影响范围：本仓库已为同族错过三次（`-filter` 在 net/cell `NAME` 上读空那一族，`:13124`）；
  约束文件里 `-clock` 的写法必须先有 `report_timing` 的 `Source Clock` 行作凭据。
- 落点：时序债务账（窗数到手、参考钟来自只读反证件）。
- **缺口（如实）**：`skills/` 里**没有任何条目引用 #334**（`grep -rIn "#334" skills/` 本次实跑 = 0 命中）；
  最接近的一条是 `skills/pitfalls/tcl-query-empty-means-broken-ruler/SKILL.md:104`（该卡是重建前的旧包名，**现不存在**；同一族现在的成文位置是 `skills/pitfalls/tcl-and-probe-traps/SKILL.md`），
  它的证据列表点名 #279/#286/#319/#320 而没有 #334 ⇒ 见 §6 未闭合项 U3。

---

## C5 · 把规范 skew 当采样窗挂进 SDC，是量纲错；而 `.xdc` 里的 Tcl 守卫根本没执行

**① 错误断言原文**（条目 #335，起于 开发台账；`:13140-13142`、`:13148-13150`）

> `src/constraints/r119_hdmi_source_window.xdc` 第一版在里面写了 `if {…} { error … }` 与 `puts`，
> `read_xdc` 报三行 `CRITICAL WARNING: [Designutils 20-1307] Command 'if'/'puts' is not supported in the xdc constraint file.`
> ——**但 rc=0，约束文件继续"加载成功"**，守卫根本没执行。
> ……HDMI 源端 TP1 那条 `Inter-Pair Skew … max | 0.20 Tcharacter` 是**两个输出脚到达时刻之差的上限**（单边离散量），
> 而 `set_output_delay` 的语义是"外部接收器在参考沿附近采样"的窗。

会话指针：`S01`，北京时间 2026-10-04 09:1x–09:4x，无人值守段。

**② 判别实验**

```bash
grep -an "20-1307" build/evidence/r119_xdc_loads_probe2.txt          # 三行 CRITICAL WARNING，rc 仍 0
grep -an "AFTER| tmds_data_p\[0\]" build/evidence/r119_xdc_loads_probe3.txt
grep -an "AFTER| tmds_data_p\[0\]" build/evidence/r119_xdc_loads_probe4_pinclk.txt
grep -an "GATES|CTRL" build/evidence/r119_window_check.txt           # 换同量纲问法之后
```

本次实跑：`_probe2.txt:50-52` 是三条 `20-1307`；`_probe3.txt:113/117/121` = `−3.482/−3.458/−3.474ns`
（`Path Group: clkout1_1`）；`_probe4_pinclk.txt:113/118/123` = `−4.897/−4.873/−4.890ns`
（`Path Group: r119b_tmclk`，工具自报 `Requirement: 4.000…`）；
换问法后的件 `build/evidence/r119_window_check.txt:11`（当前行数 11）=
`GATES r119 窗件：判定 10 项 红=0 未测=0 PASS`。

**这个件在写作期间被原地重写了一次，必须记下来**：
`11:5x` 我读它是 **24 行**，除 GATES 那行外还有 `:13`–`:22` 十条 `CTRL Wx 期望=FAIL 实读=FAIL`
与 `:24` 的 `对照总结：造 10 条畸形动红 10 条；缺输入 2 条报 NOT_MEASURED 2 条 PASS`；
`12:4x` 复跑 `wc -l` 得 **11 行**，那 13 行对照记录**已经不在这个件里**了（`grep -an "CTRL" …` 无输出）。
⇒ 我当时写下的 `:12`/`:13-22`/`:24` 三个锚点在收尾时已全部越界 ⇒ 本次改成 `:11` 并在 C8 里单独立条。
"十条畸形各自动红"这件事现在的可核出处是 时序债务账
（"件 `build/evidence/r119_window_check.txt`（`--self` 十条畸形各自动红；缺读数件报 `NOT_MEASURED`）"）
与 开发台账 里 #335 的记述，而**不是**那份已被改小的件本身。

**③ 更正后的结论与影响范围**

- 结论：`.xdc` 里写 Tcl 控制流会被解析器**整块跳过**且 rc=0 ⇒ 约束件只能是纯 SDC 子集；
  skew 是"两脚到达时刻之差的上限"，`set_output_delay` 是"采样窗"，**不同量纲** ⇒
  这是记在**约束侧**的量纲错，不是设计时序债，也**不许**靠放宽窗把它变绿。
- 影响范围：`src/constraints/r119_hdmi_source_window.xdc`、`src/constraints/r119b_hdmi_tp1_pinclk.xdc`
  两个候选件默认不加载（开关 `VP_R119_TMDS_WINDOW=1`），去留是**队伍裁决项**（时序债务账）。
  这笔债现在拆成两笔且都不能用"窗已过"来抵：① 板级走线/连接器离散未量（规范对象是 Source Connector，
  本表只覆盖 FPGA 内部到封装脚）；② 眼图/抖动/占空比/上升下降未量（SDC 无容器）。见 `:209-210`。
- **缺口（如实）**：`grep -rIn "#335" skills/` 本次实跑 = 0 命中 ⇒ 没有技能条目引用这条，见 §6 未闭合项 U3。

---

## C6 · "6 个输出脚查不到窗"这句话被推翻**两次**（第一次是人指路的，第二次是量出来的）

这一条是**同一个错误断言被两次更正**的完整形状，两节都要引，缺一个就成了"事后聪明"。

**① 错误断言原文**（时序债务账、`:121`（表格行）、`:131`（第 3 点））

> LED 是两个静态指示脚；TMDS 那 4 个（时钟 + 3 数据）是真的对外接口，需要面板/接收端的手册窗口数。（`:45`）
> `tmds_clk_p`、`tmds_data_p[0..2]`、`led[0..1]` | 无 `set_output_delay` | **仍然零声明** |
> 要接收端（面板/HDMI 接收器）或 DVI/HDMI 规范的窗口数；本机板级资料没有，两次在线取原文没拿到可引用的一页。（`:121`）

会话指针：`S01`，第一次推翻在北京时间 2026-10-04 08:5x（**人指路**，见 时序债务账
「上面写"需要面板/接收端的手册窗口数"这句**方向是错的**，用户指出并已改口」）；
第二次推翻在 09:4x（**机器量出来**，`:199-205`）。

**② 判别实验**

- 方向判别（角色关系）：本作品在 HDMI 链路里是 **Source** ⇒ 对应 HDMI CTS 的 **TP1 Source Eye Mask**，
  不是 Sink 侧 TP2 的接收窗；取证与逐条可引用性判定写在 屏侧窗口取证（文件已确认存在）。
  UG471 那条也复查过：整本按页抽文本扫过，TMDS 一节（正文第 95 页）只给电气属性，没有任何窗口时间数
  （时序债务账）⇒ "本机没有"从断言升级为**查过的否定**。
- 量纲判别（实测）：窗真挂上后两条数据道立刻判红，数值见 §C5 的 `_probe3.txt:113` 与 `_probe4_pinclk.txt:113`；
  换成同量纲的问法（在已布线成品逐脚量 clock-to-pin 到达时刻离散）后，
  互对最差 **0.065 ns**（上限 0.20 `Tcharacter` = 4.000 ns）、对内最差 **0.001 ns**（上限 0.15 `Tbit` = 0.300 ns），
  件 `build/evidence/r119_window_check.txt:11`（判 10 项红 0 未测 0；行号成因见 §C5 末与 §C8）。
- 本次复算：`grep -an "GATES" build/evidence/r119_window_check.txt` ⇒ 仍是 `判定 10 项 红=0 未测=0 PASS`。

**③ 更正后的结论与影响范围**

- 结论：**"查不到窗"其实是问错了对象**（拿接收窗约束发送脚）；纠正方向后窗数有了（0.20 Tcharacter），
  但**同一轮又证明不能把它写成 `set_output_delay`** ⇒ 最终形态是"源端离散上限"判据 + 两笔未量的债。
- 影响范围：那 6 个端口的账本（TMDS 4 组与 `led[0..1]` **分家**：LED 是 `LVCMOS33`，与 HDMI 合规无关，
  不能借 CTS 的数，要写"不查"必须先进放宽账本，而账本当前 0 条）。见 `:185-186`、`:197`。
- 本条里**哪一步是人做的**必须写明：方向纠正是**用户指出**的（`:174` 逐字这么写），不是模型自查出来的；
  量纲错才是探针量出来的。⇒ 写进 `workflow.md` §5 的"人手步骤清单"。

---

## C7 · 本次取证里我自己的一条：把 `grep` 的 0 命中当成"件里没有这些行"

**① 错误断言（我本次差点写下的话）**

> `build/evidence/r119_tmds_launch_probe.txt` 里查不到 `PORT| … | clock=` 行 ⇒ 第二支探针也没打出端口层读数。

现场（本档案写作过程中，2026-10-04 本地 11:5x）：我跑 `grep -c "PORT" build/evidence/r119_tmds_launch_probe.txt` 得 **0**，
并据此准备在 C4 里写"第二支探针同样读空"。

**② 判别实验**

```bash
grep -an "PORT" build/evidence/r119_tmds_launch_probe.txt   # 无匹配，但 grep 会先报 "Binary file … matches"
head -12 build/evidence/r119_tmds_launch_probe.txt          # 直接看文件
grep -an "^LAUNCH|" build/evidence/r119_tmds_launch_probe.txt
grep -an "^PORT|" build/evidence/r119_tmds_clock_probe.txt  # PORT| 行其实在**第一支**探针的件里
python -c "d=open('build/evidence/r119_tmds_launch_probe.txt','rb').read();
           print(len(d), d.decode('utf-8','strict') and 'ok')"
```

本次实跑读数：

- 该件里**根本没有 `PORT|` 这个前缀**（它的行前缀是 `LAUNCH|`，尾部实读 `LAUNCH| led[0] | {Path Group: (none)}`）；
- `grep` 判它为 binary 的真因：**字节 3779–3780 处 utf-8 解码失败**（`invalid continuation byte`），
  文件 5,737 字节、**无 NUL 字节**、无 U+FFFD 替换符 ⇒ 是一段被按字节截断的多字节中文；
- `PORT| … | clock=` 那十行在**另一份件**里：`build/evidence/r119_tmds_clock_probe.txt:67-76`。

**③ 更正后的结论与影响范围**

- 结论：0 命中有两种成因（前缀名记错 / 尺子把文件当二进制而吞掉匹配），**必须分开证**；
  只跑 `grep -c` 不能区分二者 ⇒ 凡"查不到"的断言，要么补 `grep -a` + `head`，要么补一次字节级解码检查。
- 影响范围：这条与本仓库 #307/#330/#316 那一族（中文按字节截断会让整份证据文件对 `grep` 呈"二进制"，
  看起来就像"没记录"）同因；本档案内所有"查不到"式断言都按这条补了判别命令（C4、C5、C6 各条都给了行号实读）。
- 落点：本条只落在这里（**没有**对应技能条目，也**不**新建 `skills/` 内容——本任务边界禁止改 `skills/`）。

---

## C8 · 我自己写下的三个锚点，在写作期间失效了（被引用的证据件被原地改小）

**① 错误断言原文**（本文件早先版本，§C5 与 §C6 的"判别实验"里写）

> 件 `build/evidence/r119_window_check.txt:12` = `GATES r119 窗件：判定 10 项 红=0 未测=0 PASS`，
> `:13-22` 是十条合成畸形对照（每条期望 FAIL 且实读 FAIL），`:24` = `对照总结：造 10 条畸形动红 10 条；缺输入 2 条报 NOT_MEASURED 2 条 PASS`

这三行锚点来自我 **11:5x** 那次 `head -20` + `grep -n` 的读数（当时该件确有 24 行）。

**② 判别实验**

```bash
wc -l build/evidence/r119_window_check.txt
grep -an "CTRL\|对照总结" build/evidence/r119_window_check.txt
sed -n '12p' build/evidence/r119_window_check.txt        # 空
sed -n '11p' build/evidence/r119_window_check.txt        # GATES 那一行在这里
```

本次实跑：`11 build/evidence/r119_window_check.txt`；`grep -an "CTRL"` **无输出**；`:12` 空行；
`:11` = `GATES r119 窗件：判定 10 项 红=0 未测=0 PASS`。⇒ 三个锚点**全部越界**。

**③ 更正后的结论与影响范围**

- 更正：本文件里该件的引用统一改为 `:11`（已改，见 §C5 末段与 §C6 第二条判别动作）；
  "十条畸形各自动红"这句话改由**已成文且没被改小**的出处承载：时序债务账
  与 开发台账 #335（`:13137` 起）。
- 成因不是我看错，而是**这份件在 11:5x→12:4x 之间被同一天的另一支子会话原地重写并改小了**
  （13 行对照记录从件里消失）。按 P22 铁律 7"已归档的记录不再原地修改；更正以追加条目形式写"，
  这件事在本仓库里是**一次真实的不可变性破坏**，而且它破坏的正是我引用的凭据。
  我没有去复原它（越界：不许改 `build/`），只做三件事：**换锚点、记下两次读数、把可核出处换成追加式档案**。
- 影响范围（可推广的规矩，不写"下次注意"）：
  ① 本档案凡引用 `build/evidence/**` 这类"会被同一批任务改写"的件，都必须带**复核时刻**；
  ② 优先引用**追加式**档案（开发台账、时序债务账）作主锚点，
     把件本身作辅证 —— 因为前者只增不删，实测 `issues.md` 从 13,165 行长到 13,269 行期间，
     我引用的 `:12854/:13075/:13098/:13111/:13137` 五个锚点**逐条仍然命中**（复核见 `README.md` §8）；
  ③ 引用之前必须**再跑一次**行号读取，而不是相信十分钟前的 `head`（这正是 #333"射程会漂"的同一族：
     这次漂的不是行号，是文件本身）。

---

## 5. 本文件对门禁的影响（写入前 / 写入后各一次，判 2 项）

| 尺子 | 写入前基线 | 写入后 | 判定 |
| --- | --- | --- | --- |
| `node src/host/doc_enc_check.mjs` | `扫了 534 个手写文件：全部干净` | 见本节末（同一命令重跑） | 硬错必须仍为 0 |
| `node src/host/line_cite_check.mjs` | `扫 226 份交付文档 … 硬错 0 条` / `D5: CLEAN` | 见本节末 | 硬错必须仍为 0 |

> 两次读数的**文件数不一致**（524→534→542，几分钟之内）不是尺子坏了：
> 同一时间窗内有**兄弟子会话正在往仓库里写文件**（本次 P22 批次就有 10 场在 `CUT` 之后）。
> 这条观察写进 `workflow.md` §3。

## 6. 未成对项清单（只有"后来发现不对"、没有判别动作的，全部单列在这里）

| # | 项 | 为什么没成对 | 需要谁补 |
| --- | --- | --- | --- |
| U1 | `report/ai_collaboration.md` §4 的 13 例（A–M，行 `:101`–`:224`）与 大模型协作记录 的 6 例（例 1–例 6，行 `:15`–`:194`） | 这 19 例各有"错误结论 + 更正"两半，但**本次没有逐条重跑其判别实验**（每条都要开它点名的件、有的还要重跑构建/仿真）。本档案不替它们背书 | 判 `NOT_MEASURED`，分母 19；要成对需逐条复算 |
| U2 | 任务派发词里"主 agent 批量派发子 agent，**批次过大曾导致中途丢文件**"这句话 | 只有断言，没有凭据。本次在冻结窗口内实算：`Agent` 调用 128 次 vs 子会话导出 127 份，差的那 **1** 条经定性是**参数校验失败即重发**（`Error: Agent tool parameter validation failed: params/mode …`，21 秒后重发成功），不是丢文件 | 判 FAIL（作为事实）；已在 `workflow.md` §4 标为**借用断言**。若队伍另有凭据（某轮 `git status` 少文件的现场记录），给出来我再成对 |
| U3 | #334、#335 与 `skills/` 的双向引用 | `grep -rIn "#334" skills/` 与 `"#335"` 本次实跑均为 **0 命中** ⇒ 协作记录→技能这一侧接不上；本任务边界禁止改 `skills/`，所以我只能点名缺口 | 判 FAIL（缺口，非我可闭合）；见 `README.md` §4 |
| U4 | `skills/evals/records/` 在我 11:5x 检查时是**空目录**（`ls` 实跑 0 份），12:3x 复跑已有 **2 份** | 那 2 份是 P09 的演练/审计表，**不带** `skills/evals/README.md` §3 的 9 字段（`被测条目` 命中 0），也**不引用任何会话登记号** ⇒ 所有"会话结论 → evals 记录"的引用仍然**无处可指**，本档案因此不能声称与 evals 双向闭合（`skills/evals/` 那一层连同 `README.md` 在 2026-10-04 c7b325f 重建技能包后**现不存在**，本行只报当时的检查读数不指路）| 判 `NOT_MEASURED`（读不到"双跑记录"这种输入）；逐条缺口在 `README.md` §4（G1/G2/G6） |

## 7. 本文件的成对计数（分母）

`判 8 条成对（C1–C8）`：C1 #321 · C2 #332 · C3 #333 · C4 #334 · C5 #335 · C6 debt_ledger 两节 ·
C7 本次现场的 grep 误读 · C8 我自己写下的锚点失效（件被原地改小）。
每条三件齐全，"判别实验"一节里的**每一个**文件与行号都在收尾时重跑过一次存在性核对
（43 个锚点、0 个越界，命令与读数见 `README.md` §8）。未成对另计 4 条（U1–U4），不与上面混入同一分母。
