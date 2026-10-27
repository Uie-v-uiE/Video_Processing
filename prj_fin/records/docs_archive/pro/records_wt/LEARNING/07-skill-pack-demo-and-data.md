# 第 07 卷 · 技能包、演示面与数据面

> 本卷读的是仓库里另外三块材料：`skills/`（49 条做法条目）、`report/` 的演示与验收面、`data/` 的数据面。
> 前面八卷讲"这套系统是怎么造出来的"，本卷讲"造它的过程里哪一部分能被别人带走"。
> 所有数字都当场用只读命令数过，句末括号点名来源；数法命令见附录 A。

## 1. 技能包是什么、不是什么

**结论先说**：`skills/` 不是一套缩微版的工程文档，而是一份**去工程化**的操作卡片集。它和 `report/` 的分工写在
写作规范里：目录名与条目正文「不许出现具体工程/板子的名字（工程专有的事实属于 `report/` 与 `docs/`，不属于技能包）」
（来源：skills/_meta/authoring-standard.md 第 50–51 行），精简纪律再补一刀「不许写绝对路径、不许写"本工程的
rNN/某文件第几行"、不许把工程专属数字当普适结论」（来源：skills/_meta/authoring-standard.md 第 72 行）。
所以同一个事实会出现两次而口径不同：`report/05-timing.md` 说的是"这一轮的 WNS 是多少"，
`skills/timing/localise-worst-path/SKILL.md` 说的是"拿到一份时序报告先按哪几类原因分诊"。前者离了这题就没意义，
后者离了这题才有意义。

**为什么每条必须带"失效条件"**：一条做法如果没有边界，读它的人无法判断自己该不该用它，于是它退化成一句口号。
规范直接把这件事写成硬要求：`失效条件（边界）：什么情况下这条会失效或误导，失效前有什么征兆。这条最容易被写成
空话——空话就等于没写`（来源：skills/_meta/authoring-standard.md 第 60–61 行）。实测这一条被贯彻了：
49 条里 49 条有 `失效条件` 小节（数法：`grep -rl "失效条件" skills --include=SKILL.md | wc -l`）。

**为什么每条必须带"已验证的复用结果"**：因为技能包的唯一评价指标是可复用性——「一支从没做过这个题目的队伍，
拿到目录能不能直接用在自己的工程上」（来源：skills/_meta/authoring-standard.md 第 10–12 行）。而"验证过"这件事
本身要写数、件名或复跑命令，量不了就必须自报：`没有就写"未量过，属建议"`（来源：skills/_meta/authoring-standard.md
第 62 行）。这一条诚实得可以当本包的体检表：**49 条里 45 条正文含"未量过"**（数法：
`grep -rl "未量过" skills --include=SKILL.md | wc -l`），只有 4 条给出了量到的数——
`scripts/golden-compare-tool`、`scripts/metrics-collector`、`timing/global-timing-roster`、
`timing/localise-worst-path`（数法：对 49 个 `SKILL.md` 求"含未量过"集合的补集）。
换句话说这一包里**九成条目是"有边界、没量过"的建议**，这一点要主动讲，别等评委问。

**它和题解耦到什么程度（数出来的）**：用一条严格的正则去找"点名了本题某个具体文件"的条目——
`grep -rlE "(src/|build/|sim/|board/|report/|data/)[A-Za-z0-9_./-]*\.(v|c|mjs|sh|tcl|md|csv|txt|rpt)" skills --include=SKILL.md`
命中 **0 个文件**。放宽到不带路径的工程专有词（`main.c`、`pl_video_top`、`tb_v98`、`board_verify`、`gates.sh`、
`r1NN`、`Zynq`、`7020`）也只命中 **1 个文件**（同一条 grep 换成不带扩展名的专有词表），而那唯一一处是
`node scripts/collect.mjs <报告目录> [--out metrics.csv]`（来源：skills/scripts/metrics-collector/SKILL.md 第 20 行）——
那是它自己脚本的默认输出文件名，不是本题的 `data/metrics.csv`。**按"点名本题文件"这个口径，通用条目 = 49 条，
专有条目 = 0 条**。这不是巧合，是上面那两行禁令 + 一支检查器逼出来的形状。

**结构上还有第六块**：规范要求的不是四块而是六块——frontmatter、适用场景、使用方法、失效条件、已验证效果、来源
（来源：skills/_meta/authoring-standard.md 第 53 行「一条 SKILL.md 必须有六块」）。多出来的 `来源` 只允许写
"长自哪一类失败/观察"，不写轮次不写工程名（同文件 第 17–18 行）——这就是第 3 节那条路径能对上号的原因。

## 2. 按类别过一遍

`skills/` 下真实存在 10 个类别目录加一个 `_meta`，条目分布用 `find skills/<类别> -name SKILL.md | wc -l` 逐目录数：

| 类别 | 条数 | 这一类在沉淀什么 |
|---|---|---|
| `workflow` | 6 | 动手前的顺序与授权纪律 |
| `prompts` | 4 | 把题面变成可执行清单的大模型提示词范式 |
| `rtl` | 4 | 写结构时的四类判断 |
| `timing` | 6 | 时序从约束到收敛的读法与刀口 |
| `verify` | 5 | 判据本身怎么写才算判据 |
| `runtime` | 6 | 片上运行时的寄存器/搬运/存活范式 |
| `scripts` | 6 | 把重复劳动固化成可跑的检查 |
| `pitfalls` | 6 | 六类"错了不像错"的失效模式 |
| `templates` | 4 | 交付文档四种页的骨架 |
| `references` | 2 | 检索入口：按症状分派、按出处分级 |
| 合计 | **49** | 正文总计 4228 行，最短 54 行、最长 144 行（数法：`find skills -name SKILL.md \| xargs wc -l`） |

类别名不是赛题的四个分类，是赛题四类"再加两个工程实践中长出来的"，规范里逐条点了名
（来源：skills/_meta/authoring-standard.md 第 47–49 行）。

### workflow（6）与 prompts（4）：先决定"能不能做"，再决定"怎么做"

`before-touching-hardware`、`confirm-with-user-first`、`one-round-work-loop` 是代表，
`before-an-rtl-change`／`research-before-code`／`start-a-fpga-project` 只列名。
这一类值得沉淀的理由很实际——上板动作不可逆，而大模型倾向于把"能做"和"该做"混为一谈。
`confirm-with-user-first` 的触发条件是"要做不可逆或对板载存储有副作用的动作、要改动人会直接看到的画面与演示顺序"
（来源：skills/workflow/confirm-with-user-first/SKILL.md 的 description 行），它把"问人"写成前置步骤而不是礼貌动作；
`one-round-work-loop` 管可交接性：一轮要同时钉住"改了什么、拿什么证明、结论落在哪件上"。
prompts 类里 `review-adversarially` 是唯一以"另一个模型"为对象的，症状写得很具体——出现"看起来没问题"
"整体合理"这类无件结论时（来源：skills/prompts/review-adversarially/SKILL.md 的 description 行）。
另三条是 `algo-to-hw-sw-partition`、`spec-to-rtl-checklist`、`synthesis-report-bottleneck`。
这一类的失效方式也一致：提示词一旦写成"请你认真检查"就失去抓手，所以每条 `使用方法` 给的是
**输入清单 + 输出形状**，而不是措辞模板。

### rtl（4）与 timing（6）：判断类条目，故意不给流程

rtl 是 `cdc-and-async-discipline`（两个及以上时钟域、静态检查成串告警）、`width-and-overflow-audit`
（截断/越界/回绕/饱和）、`resource-vs-timing-tradeoffs`（想靠加资源换时序）加 `reset-and-clocking-plan`。
timing 六条是全包密度最高的一组：`global-timing-roster`（按域出名册再逐格差分）、`localise-worst-path`、
`constrain-io-and-clocks`（报告好看但流程里根本没有 input/output delay）、`fix-logic-depth`（先算这条路最多能抬
多少再插拍）、`reduce-fanout-and-congestion`、`clock-tree-changes-checklist`。
这一类为什么值得沉淀：**收益归因**是 FPGA 工作里最容易自欺的一环。`global-timing-roster` 给了理由的两层
——域周期不同时同一个 1 ns 在 8 ns 域是 12.5%、在 20 ns 域是 5%；而且一动之后最差那格常换族，
两个数不是同一条路的两个读数，不可归因（来源：skills/timing/global-timing-roster/SKILL.md 第 49 行）。
它的失效条件写得像体检：周期列取错一格就"整表自洽但整张全错"、拿一列 `NA` 当空、
差值两端不是两个有指纹的工件（来源：同文件 第 55–57 行）。注意它的"已验证效果"每条前面都冠一句
"以下读数来自某一次具体设计……不可当普适结论引用"（来源：同文件 第 64 行）——
这不是谦虚，是被检查器逼出来的（见第 3 节）。

### verify（5）与 scripts（6）：把"尺子"本身当被测对象

代表：`verify/three-state-verdicts`（判据要规定输出形状，"没扫到"不许记成通过）、`verify/checker-selftest`
（新写或收紧一条判据前先证明它自己真的能红）、`verify/mutation-controlled-coverage`（用变异自证射程），
另两条是 `bench-expectations-first`、`golden-reference-compare`。这一类是全包最"元"的一层：
它管的不是设计，是"你凭什么说设计对了"。`scripts/gate-runner` 讲多条判据怎么合成一个采纳门槛
（症状写的是"判据各自退出码打架、'没测到'被当成通过"），`scripts/evidence-ledger` 讲结论必须挂在落盘件上
且下一轮能逐条复核，`scripts/repro-drill` 讲文档点名的文件是否真在盘上（死链）；
`scripts/golden-compare-tool`、`scripts/metrics-collector` 是带真量级的两条脚本条目，
`scripts/contract-to-host` 讲同源生成。失效边界在这一组里反复出现同一个形状：**空集**——比较数为 0、
名册没扫到、目录被剪枝剪空，都会被"没测到"伪装成"通过"（参见 `pitfalls/ruler-fake-greens`）。

### runtime（6）与 pitfalls（6）：接口范式与"看起来正常"的病

runtime 六条按"寄存器→搬运→外存→加载→存活→绑定"排：`register-map-and-readback`（现场只靠读数自证行为）、
`dma-and-cache-coherency`（"数据半新半旧""上一帧残影"）、`external-memory-bandwidth-account`、
`overlay-load-and-verify`、`board-liveness-readback`、`host-bindings-from-contract`。
共同价值是把"软硬接口"写成可回读的东西；失效条件通常落在"文档写的默认值与硅里的初值不一致"。
pitfalls 六条是病历本，且六条都长自真实弯路：`constraint-coverage-loss`（改钟/改端口名之后约束静默失效，
144 行是最长的一条）、`package-integrity`（剪枝剪掉了文档点名的件）、`doc-rotation-damage`（措辞改动扫遍多文档
后漏改的那几处）、`build-artifact-races`（构建在飞时改源、0 字节日志被当成还在跑）、`ruler-fake-greens`、
`tcl-and-probe-traps`（取回空值分不清"没有"还是"我写坏了"）。这一类值得沉淀的理由：这些错**不报错**——
工具退出码 0、报告字面正常，人要几周后才发现约束从未生效。

### templates（4）与 references（2）：页的骨架与入口

`acceptance-and-eye-check`（验收判据，尤其"只能由人眼睛判"的那类）、`claims-vs-evidence`（写任何数字前先分清
"有件撑着"还是"只是我相信"）、`round-diary`、`project-skeleton`。references 只有两条但它们是路由：
`symptom-router`（只有症状、不知从哪条读起时的分派表）与 `where-to-search`（分不清规格与转述时的资料分级）。
这两条存在的原因是三级渐进加载——启动只读元数据、触发才读正文、请求才取 `references/`
（来源：skills/_meta/authoring-standard.md 第 21–22 行），所以"怎么找到条目"本身也要写成条目。
references 也是唯一的单层目录（`find skills -type d -name references` 只命中 `skills/references` 一处），
其余条目没拆子层。

## 3. 一条技能从立案到进门禁的路径

拿 `timing/global-timing-roster` 走一遍（73 行；它是第 1 节点名的"量到过"的 4 条里最长的一条，
数法：`wc -l skills/{scripts/golden-compare-tool,scripts/metrics-collector,timing/global-timing-roster,timing/localise-worst-path}/SKILL.md`）。

**它长自哪一类失败**。提炼过程那份文件把原始材料归成四类观察，这一条挂在第 ③ 类"改动的代价面看不见"下面——
只盯最差路径就会采纳"局部变好、别处变差"的改动（来源：skills/_meta/distillation-process.md 第 15–18 行）。
条目自己的 `来源` 节写的是同一句话的另一半：长自"只看 WNS 会采纳局部变好、别处变差的改动"这一类失败，
以及"相对余量比绝对值更适合跨周期比较"的观察（来源：skills/timing/global-timing-roster/SKILL.md 第 73 行）。
它没写轮次号、没写仓库路径——这是被禁止的，不是风格（来源：skills/_meta/distillation-process.md 第 55–58 行）。

**它被哪把尺子钉住**。包内检查器 `skills/_meta/check-skill-package.mjs` 逐条逐节判红，跟这一条直接相关的有四把：
`失效条件` 少于 12 字符或命中空话词表就报"失效条件是空话（该写征兆与边界）"（来源：该文件 第 65 行）；
`已验证效果` 既没数字也没"未量过"就红（同文件 第 67 行）；有测量标记却没声明"非普适"就红（同文件 第 74 行）——
这一条解释了为什么该条目第 64 行要先写一句"以下读数来自某一次具体设计……不可当普适结论引用"；
正文出现专有名词或本机绝对路径也红（同文件 第 78、80 行，汇总判定在 第 96 行 `G 通用性（无专有名词）`）。
再加 frontmatter 两把：`description` 必须以「用于」开头且含触发词（同文件 第 53–54 行），
`name` 必须等于目录名且是 hyphen-case（同文件 第 49–50 行）。

**四要素在门禁里怎么被要求**。交付侧 `build/deliver_spec_check.mjs` 的 C5 项（注释原话"四类目录齐 + skills/README
四要素 + report 章节齐"，来源：build/deliver_spec_check.mjs 第 389 行）把四个目录齐不齐和四要素一起判。
四要素按**字面**判：`适用范围`／`使用方法`／`失效条件`／`已验证的复用结果` 必须出现在 `skills/README.md` 里
（同文件 第 397–398 行）。它判的是 README 而不是 49 个条目正文——原因写在紧邻注释里：第一版用同义词放行
（`/适用场景|scope/`），结果 README 一个"适用范围"都没有也报绿，等于这把尺子量不到
（同文件 第 395–396 行）。于是"字面四词"落在 README，条目正文用的是另一套逐字标题
`适用场景`／`使用方法`／`失效条件`／`已验证效果`／`来源`，对应关系由 README 自己声明：
"适用范围＝`适用场景` 节……已验证的复用结果＝`已验证效果` 节"（来源：skills/README.md 第 23–26 行）；
条目级一致性由检查器逐条判那五节齐不齐（来源：skills/_meta/distillation-process.md 第 33 行门①）。

**"进门禁"和"算验证过"不是一回事**。四道门里只有第①道（格式）是完全机器化的，
第②道可检索性要人来问、第③道增益要在干净小工程上 A/B、第④道要陌生人演练
（来源：skills/_meta/distillation-process.md 第 29–36 行的表格，最后一列"机器化没有？"分别是有/半/否/否）。
本包的规矩写在第 38–39 行：**糊不过去——要么给可复跑的形式，要么明写未量过**（来源：同文件 第 38–39 行）。
第 07 卷第 1 节数到的"45/49 条写了未量过"就是这条规矩的落点：条目能过格式门，但绝大多数没通过第③道门。

## 4. 演示面与验收面

### 演示脚本的真实形状

`report/demo_script.md` 只有 157 行，结构是**第 0 步（开机到"能演"五步）+ 9 幕**（数法：
`grep -c "^## " report/demo_script.md` 得 10 个小节标题，编号 0–9）。每幕四件事顺序固定：前置（先确认哪一格）→
敲什么 → 看见什么算通过 → 每一种"没看到"分别说明什么、先看哪一格；全套约 6 分钟，时间不够只演第 1、2、3 幕
——"那三样就是项目名里的东西"（来源：report/demo_script.md 第 7–8 行）。顺序上唯一不许动的是第 9 幕（拔卡）
排在收尾 `stat` 之后，理由是它要一只手，而插回前那几秒屏上没有 SD 这一路（来源：同文件 第 9 行）。

**台上明确禁说两件事**："设成某个绝对角度"（`rot <数字>` 有意不做，指向 `main.c:1042`；要停角度只有板上
KEY1/KEY2 每按一次 ±1°）与任何"AI/识别/深度学习"字眼（来源：report/demo_script.md 第 10–11 行）。
这里要纠正一个常见误记：**演示里没有"长按切源"这个动作**。切源靠串口 `src auto`/`src 0`/`src 1`/`src 2`
和两处物理动作——第 1 幕拔网线与插回（≤0.5 s 回 `SD`、插回又回 `ETH`），第 9 幕直接拔 SD 卡
（"这一幕只有**手上动作、没有串口命令**……它不进 `--emit` 那份排练脚本"，来源：同文件 第 153 行）。
按键长按确实存在，但它是验收表里 E6 的**对照那一半**（"冷上电后按住 KEY1 到链子跑完再松手应当读 1 度"），
而且那一半**仍未做**（来源：report/08-limits.md 第 45 行）。

**图卡（TEST 那一路）在第几步**：第 2 幕把它当**前置**用——`src 0`（图卡，格子肉眼可数）
（来源：report/demo_script.md 第 47 行）；第 3 幕换回 `src 2`，理由是"在播的 SD 画面比图卡好看"（同文件 第 63 行）；
第 9 幕拔卡后 ≤0.5 s 自动落到 `SRC:TEST`，图卡自己在动（移动块 + 帧号格，同文件 第 155 行）。
所以图卡不是单独一幕，而是"没有片源时屏上仍然有活东西"这一件事的载体。
排练是脚本化的：`node src/host/demo_cmds.mjs --emit` 从讲稿自己的代码块**抽**出脚本，逐条发给板子，
再 `--check <回包>`（来源：report/demo_script.md 第 19 行）——这就是"讲稿=演示动作"的可复跑凭据，
也是第 9 幕被排除在排练之外的那一处例外。

### 眼睛判据配方长什么样

`report/acceptance-recipes.md` 有 **15 条配方**（R1–R15，数法：`grep -c "^## R" report/acceptance-recipes.md`）。
这份文件自我约束得很硬：**没有凭据的配方一条不写**——"所以这里没有'应该这样看'，只有'这样看过、留下了件、件在哪'"
（来源：report/acceptance-recipes.md 第 4–5 行），而形状是通用的：设态 → 读回前提 → 只看一件事 → 原话逐字入库
（来源：同文件 第 8 行）。照抄 R6 一条（命令 + 前置 + 每个"不"意味着什么）：
读 `drop_words` / `pkt_err` / `stall_ms` 这一类"0 就算好"的计数时，起流
`python src/host/video_sender.py --demo --seconds 50 --fps 60 --pace-mbps 0`（≈147 Mbps），
**流在跑的时候**读，且同一份回显里同时找 `src_state.eth_live`（或 `owner_eth`）与那个计数；
`eth_live=0` 时那个 0 记成"未测"不记成 0，判据表里数值填 `—`、类别填"未报"；
若这一路根本没有"活样本"出口（读不出非零值），"0"什么也不说，先做一条能把它顶非零的注入
（来源：report/acceptance-recipes.md 第 77–89 行，含凭据
`build/evidence/r118_board/board_verify_console.txt:18,21` 与 `build/evidence/r116_board/health_r118build_a.json`）。

### 串口命令面与演示动作的对应

命令表页 `report/commands.md`（391 行）声明权威出处是固件解析器 `src/ps/main.c` 的 `dispatch()`，
且"表里只写固件里真的实现了的写法；有意不做的与还缺那一位的，单独放在 §6"（来源：report/commands.md 第 4–6 行）。
演示里每一句敲的命令都回指到具体行号（`src auto` = `main.c:929-938`、`play` = `main.c:1343-1364`，
来源：report/demo_script.md 第 41 行）。板级那条电池跑的是 **105 条命令**
（`RESULT PASS uart_cmd_check (105 条命令, 97.9 s, …)`，来源：report/06-validation.md 第 119 行），
它是命令面的机器判据；演示动作面比它宽，多出来的正是无命令的那两处物理动作。

### 哪些判据只能由人眼判，为什么不能伪装

三处写得很直白。其一，屏上 OSD 的 `ROT:` 那一格：串口**没有任何"当前角度"读数**（`ROT SHOW` 只念
`auto/speed/deg/frame`，`STAT` 末尾 `geom=` 里只有位字段），出处是问题台账 #100 与 #274 两节
（来源：report/acceptance-recipes.md 第 37–38 行）——读数出口不存在，机器判据就没法写，硬写就是假绿。
其二，链路那一格：串口既没有 `[LINK]` 回包、也没有 `FPS` 的数字回读（`src/ps/main.c` 里没有任何 fps 读者，
该页注明是实测 grep）⇒ 演示时"这一格只能看屏，别把它当链路读数念"（来源：report/demo_script.md 第 41 行）。
其三，分工本身有条目：R12 的标题就是"眼睛只判『有没有 / 哪个档』，宽窄与稀疏度交给机器"
（来源：report/acceptance-recipes.md 第 191 行）。反面例子也留了档：R5 记的是"前提没锁住 ⇒ 这一轮的结论不许升"，
同一轮里两次否证因为没确认 `split marker 0` 而结论不升（同文件 第 72–74 行）。
眼睛判据的产物是"原话 + 谁看的 + 时间 + 当时是哪块 bit"，不是把观察伪装成一行 `PASS`；指标表那一行
`人眼判据,验收,36,行` 后面自己跟了一句"屏幕现象只能由人判，机器判据不冒充眼睛"
（来源：data/metrics.csv 第 21 行）。

## 5. 数据面

`data/` 下五个成员：`inputs/`、`golden/`、`measured/`、`generated/`、`metrics.csv`（另有 `README.md` 说口径）。

**`inputs/` 是怎么来的**。8 份向量只有一个生成器：`gen_inputs.mjs —— data/inputs/ 边界与非法输入向量的唯一生成器（P17）`
（来源：data/generated/gen_inputs.mjs 第 3 行），三条命令是无参数（只打印名单与摘要，不落盘）、`--selftest`
（证明"复现比对"这层有牙）、`--write`（写 `data/inputs/`）（同文件 第 10–12 行）；它为什么住在 `data/generated/`
而不是 `src/host/` 也有账——交付清单 P17 把这一格定义为"由脚本合成的数据：生成脚本、参数、随机种子、可复现命令"，
数据本体才落 `inputs/`（同文件 第 5–7 行）。尺寸对得上"边界"这两个字：`full_512x300.rgb565` 307200 B = 512×300×2、
`trunc_299rows.rgb565` 306176 B（少一行）、`overlong_1p5frame.rgb565` 460800 B（一帧半）、`empty_0b.bin` 0 B、
`udp_pkt_edge.bin` 62 B（数法：`ls -l data/inputs/`）。演示推流与卡上裸帧**不从这里来**，走
`src/host/video_sender.mjs` 与 `node src/host/make_sd_video.mjs --in <mp4> --out E:`
（来源：report/demo_script.md 第 36 行）。这一层自己也留了欠账：8 个向量目前只被生成脚本与个别仿真台架点名，
**没有一个统一入口一次跑完八个**（来源：data/README.md 第 63 行）。

**`golden/` 是谁算的——离线软件渲染，不是 RTL**。目录说明第一句就是"这个目录放的是**软件侧算出来的参考结果**，
用来跟屏上照片做人工比对"（来源：data/golden/README.md 第 3 行）。关键那笔记录在第 20–23 行：这批 PNG 是早期
host 侧预览工具的输出，那份工具**现在不在树里**，所以给不出"重新生成"的命令；要么补一个与 `src/rtl/process/`
定点算术一致（含同一套饱和/取整）的可复现渲染脚本，要么把 PNG 降级为"历史参照图"，而**"在补出来之前，
任何'与黄金参考逐像素一致'的说法都不成立"**（来源：同文件 第 23 行）。这就是"离线重算不能当判据"在仓库里的原话。
配套两条硬事实：全仓库对 `data/golden` 的引用只有 `report/log/contest_checklist.md` 提了一次目录名，
没有任何 `.v`、`.mjs`、`.sh` 读这里面的文件（`data/golden/README.md` 第 4–6 行给的就是那条 `grep -rn` 核实命令）；
`proc_00111.png` 这类文件名里的五位数字是**旧的效果位口径**，不要按字面读成当前的 `stage_sel`（同文件 第 15 行）。
清单 `manifest.md` 第 8 行按 2026-10-04 登记 13 个件（11 PNG + 1 个 `.mem` + 1 份 README），第 81 行又有一条
【2026-10-05 修订】写明那份 `frame_640x360.mem`"已从目录里去掉，不随包"；今天 `find data/golden -type f`
数到 13 个文件（含清单自身）——两处合起来才是当前形状。

**`metrics.csv` 每行怎么读**。表共 29 行：第 1 行是表头，往下 28 行是指标行（数法：`wc -l data/metrics.csv`）；
列序 `指标名称,类别,数值,单位,测量条件,测试次数或时长,证据文件`（来源：data/metrics.csv 第 1 行）。
"测量条件"是第 5 列，它决定这一格能不能被引用：全局 setup WNS 那一格写的是"失败 setup 端点 0 / 总端点 51135；
板上 r118 bit cd04907e1369；本版不带 RGMII 输入窗（窗退回候选件 `VP_R116_IO_WINDOW=1` 可复现）"
（来源：data/metrics.csv 第 5 行）——条件里的"本版不带输入窗"直接决定了第 6 行为什么要写
"收口 I/O 的 5 个端点当前无输入窗 = 未检查（H5：未检查不等于满足）"（来源：同文件 第 6 行）。
第 2 行整行是"共用条件"（器件与工具链），其余行不再重复。第 7 列证据文件指的是 `build/` 与 `board/` 的件，
**不指 `data/`**，所以 `measured/` 那一层是原始留档而不是指标表的证据层（来源：data/README.md 第 15 行）。

**刻意留"未报"的行是第 20 行**：`端到端时延,未报,—,—`，它自己写的理由是"这一格有读数出口（OSD 的 Latency lane
与 JTAG 回读），但**本表不填没有复核过的数**：读数方法与逐轮记录在 `board/verify_r87.md` 与 `build/evidence/`，
取到可信值之前不占权重也不宣称"（来源：data/metrics.csv 第 20 行）。同一类还有第 24 行的"入流过载点,未定"，
理由是"这一版没顶到丢字那一点，所以不给『PL 能扛多少 fps』的数字"（来源：data/metrics.csv 第 24 行）。
**这里曾经有一处真实的自相矛盾，2026-10-07 按凭据关掉了**：第 25 行原来写的是 `端到端时延,核心,33.34,ms`，
而 `report/perf_report.md:195` 第①条明写这个数只在 PL 内部、不许叫端到端时延；冲突被交付欠账清单钉住——
第 19 条标题就是"指标不同源（同表自相矛盾）"，点名 `data/metrics.csv:25`（来源：report/90-open-items.md 第 164 行）。
关掉它靠的是件内自报的数：`board/evidence_r41/metrics_r41_soak300.md` 里 `gap_sum/gap_segments` = 33.3434 ms、
8999 段，属于 9000 帧 / 300 s 那一轮，而 600 帧那轮自报的是 33.3255 ms ⇒ 第 25 行改名为
"入流帧间隔（PL 内）"、轮次一并写对，端到端那一格保持 `未报` 不动（来源：data/metrics.csv 第 20、25 行）。
先把"未报"与"33.34 ms"同时留在一张表里而不是删掉其一，是这套交付的记账方式：**欠账必须可见，
可见之后才有得对账**；对账这把尺子是 `src/host/metric_recheck.mjs`，
它在门禁里的身份是"第 21 项 = 数字对账（D6 `metric_recheck`）"（来源：data/metrics.csv 第 14 行；
该文件本身在 `src/host/metric_recheck.mjs`，已确认存在）。

## 6. 本卷小结

三块在交付里的权重不一样：`report/` 是判分主体（§5.3 点名的四个词、§5.4 要求的改前/改后对比与失败分析，
门禁脚本对这两节的地板值写在注释里，来源：build/deliver_spec_check.mjs 第 395、447–448 行）；
`skills/` 是"可复用"那一格的载体（四要素 + 通用性），`data/` 是"数从哪来"的地基，量最小但一旦缺就整个塌。
这个权重在 C5 上能读出来：它一次判"四类目录齐 + skills/README 四要素 + report 章节齐"三件事
（来源：build/deliver_spec_check.mjs 第 389 行）。

评委最可能追问的三个问题，正好由这三块各答一个——这三问在 `_meta/distillation-process.md` 第 3 行被明说
（"这份文件回答三个问题，也是评委最可能追问的三问"）：

1. **"这些条目从哪些失败里长出来"** → 技能面答：四类观察 → 条目的映射表（来源：skills/_meta/distillation-process.md 第 8–22 行）。
2. **"你凭什么说它是对的"** → 演示与验收面答：15 条配方，每条带命令、前置、每个"不"意味着什么与凭据件名；
   机器判据与人眼判据分列（来源：report/acceptance-recipes.md 第 4–5 行）。
3. **"这个数是谁量的"** → 数据面答：`metrics.csv` 每行自带测量条件与证据文件列，未复核的格留 `未报`
   （来源：data/metrics.csv 第 1、20 行）。

## 附录 A · 本卷所有"数法"的只读命令

```bash
find skills -name SKILL.md | wc -l                       # 49
for d in skills/*/; do echo -n "$d "; find "$d" -name SKILL.md | wc -l; done   # 各类条数
grep -rl "未量过" skills --include=SKILL.md | wc -l       # 45
grep -rlE "(src/|build/|sim/|board/|report/|data/)[A-Za-z0-9_./-]*\.(v|c|mjs|sh|tcl|md|csv|txt|rpt)" skills --include=SKILL.md | wc -l   # 0
grep -c "^## " report/demo_script.md ; grep -c "^## R" report/acceptance-recipes.md   # 10 幕标题 / 15 条配方
wc -l data/metrics.csv ; ls -l data/inputs/ ; find data/golden -type f   # 29 / 8 份向量 / 13 个件
```

这些命令都不写盘、不碰板，跑完仓库状态不变。
