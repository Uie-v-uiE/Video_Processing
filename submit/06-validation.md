# 验证：四类判据各自的射程，互不替代

本章把"这一版被验过什么"拆成四类判据，每一类只写它**答得了**的问题、点名它的件，
并写明它**答不了**的那一半。三态贯穿全章：**PASS / FAIL / NOT_MEASURED**——
"读不到输入"在本仓库里不是通过，也不是失败，它必须被写成第三种状态。

## 1. 三态在脚本里的原形（不是我加的口径，是它们自己打印的）

| 层 | PASS 的 token | FAIL 的 token | NOT_MEASURED 的 token（同一支脚本自己给的） |
| --- | --- | --- | --- |
| 台架 | `RESULT <tb> PASS` / `VERDICT <tb>: …` | `RESULT <tb> FAIL nfail=N`，退出码 **3** | `VERDICT <tb>: NO-VERDICT-LINE（这支台架一条判定都没打，去数判据条数）`，退出码 **4** |
| 门禁 | `GATES: ALL PASS（$NSAY 项全部判定）` | `GATES: 有红项（判定 $NSAY 项）—— 不采纳，保留上一版` | `GATES: PARTIAL —— 判定 $NSAY 项全过，但有 $NNA 项因缺凭据未判（见上面 n/a 行），这一版不作"过门禁"` |
| 板级 | `RESULT board_verify PASS（判红的步骤：0）` | `RESULT board_verify FAIL nred=$NRED ⇒ 这一版不能采纳` | 摘要行里的 `pkt_err=? frames_bad=? drop_seen=?`（问号 = 没读出来） |

三条出处的原文：`sim/run_one.sh:35-44`（`NO-VERDICT-LINE` 那一支与"0 绿 / 1 编译或例化失败 /
2 REFUSE / 3 **判红** / 4 认不出判定"的退出码表）、`build/gates.sh:582-586`（三条 `GATES:` 结尾）、
`build/board_verify.sh:263-265`（`RESULT board_verify PASS/FAIL` 两条）。
`sim/run_one.sh:41` 那句是这一节的骨架：**"红是结论，'没数'不是结论"**。

## 2. 台架判据（`sim/`）：像素域与协议域的自己判自己

- 件 `build/tb_v98_report.txt` 自己打印的计数（本次按文件实数，不是引用别的轮）：
  `^PASS` 行 **161** 行、`^FAIL` 行 **1** 行、判定行
  `RESULT tb_v98_top_seam FAIL nfail=1`；判据名去掉重复之后是 **47** 个
  （同文件 `grep "^PASS" | 取第 2 列 | sort -u`）。整屏台架之外，`sim/` 下 `tb_*.v` 共 **81** 支
  （本次 `ls sim/tb_*.v | wc -l` 数出）。
  ⚠ `data/metrics.csv` 的"整屏逐像素判据 141 条"钉的是 r104 那一跑（它自己写明
  `141 = 该文件里 ^PASS 行数 140 加 ^FAIL 行数 1`，头部 `top_md5=2bf2ceeede07`），
  与本轮那一份头部 `top_md5=56c269602e18` 不同源 ⇒ **计数跨轮不可比**，以当前件为准。
- 唯一那条 FAIL 是 `FAIL C5c frame head is not the previous frame's tail …`，
  它是**公开声明保留**的红，登记与复现方法在 `report/KNOWN_ISSUES.md` §一 第 1 条（`#98`）。
- 这些判据的形状值得念一句：一条主判据前面都挂一条**空集守卫**
  （`PASS C4a rows judged`、`PASS C5a judged rows`、`PASS C9pre rows judged`、`PASS C11pre …`、
  `PASS C12pre …`），守卫行自己把"这一格判了几行"印出来。件里那些
  `… else C4b below means nothing` / `a green on an empty set (#78)` 就是这个意思：
  **没有样本的绿不许存在**。
- **射程之外**（`report/KNOWN_ISSUES.md` §三那张表逐条点名）：
  ① 本机只有 **xsim**，早期能作第二意见的 ModelSim 已不在 ⇒ 任何"两家仿真都过"的说法今天不可复现；
  ② `sim/prim/` 里是自建的行为级**占位原语**（`MMCME2_BASE`、`unisims_sim`），
  跑 xsim 看到的 OSERDESE2/BUFG 相关告警来自占位件而不是设计缺陷；
  ③ 非打包数组的越界写，xsim 丢弃、硬件按地址位宽截断（`#103` 就是这么来的）⇒ 这一类问题
  **只用硬件读数收口，不用仿真通过收口**。
  ④ 台架不判屏上观感（第 5 节），也不判 PHY→FPGA 那段片外窗
  （`submit/05-timing.md` 第 6 节那 5 个收端点：没有约束 ⇒ STA 与台架都不在场）。

## 3. 发布门禁（`build/gates.sh`）：一条命令读回报告并与阈值比

- **它自报的那一行**（件 `build/r118_gates_final.txt` 末行原文）：
  `GATES: 有红项（判定 24 项）—— 不采纳，保留上一版`；同件倒数第二行把范围一起念出来：
  "结尾必须把**范围**一起念出来：判定 24 项、未判 0 项"。
  形状核对：`build/gates.sh` 里 `say` 的调用共 24 处（`grep -c` 数出），脚本头部因此明写
  "这里**不再写死条数**，以本文件里 `say` 的调用次数为准"。
- **当前 24 项 = 23 绿 / 1 红**，两跑逐字节一致：件
  `build/evidence/r118_board/g2c.txt` 与 `g3c.txt` 的末行是同一句 `GATES: 有红项（判定 24 项）……`，
  汇总件 `build/evidence/r118_board/gatesc_summary.txt` 打的是
  `GATESC done id=identical green=23 red=1`。
- **唯一那条红**是 `顶层台架 tb_v98 top=56c269602e18 FAIL行=1 指纹(norm1):fresh fresh fresh … FAIL`，
  脚本自己在下一行注了一句："报告里有 1 行 FAIL 没有 RESULT…PASS 汇总行
  （台架跑完了、是它自己判红的，先读 FAIL 那几行的数）"。那条 FAIL 就是第 2 节声明过的 `C5c`。
- **门禁绿 ≠ 已验证**，三条能从件里指出来的理由：
  ① 脚本头部第 22 行写着"**数字全部来自 Vivado 报告本身，不重新跑构建**"⇒ 它判的是
  盘上报告与阈值的机械比较；它防"念到上一版"靠的是自己打出来的新鲜度与三枚 md5
  （`身份：system.bit md5=cd04907e1369 / system.xsa md5=934ebdbaa13b / ps_app.elf md5=d0b07f84a068`），
  不是靠"跑过就算验过"。
  ② `build/tcl/README.md` §1 对着构建侧说的那句"**不要相信退出码**"——有两支历史脚本
  `add_files` 指向错路径、报错之后仍然 exit 0。门禁的 0/1 退出码同属"便利"，不是"标准"。
  ③ 本轮的采纳判据 B4 写的是"发布门 24 项里红数 **== 1**（只有声明过的 `C5c`），且门禁两跑逐字节一致"
  （`docs/timing/ROUND_r118.md` §二）。这与脚本结尾那句机械的"不采纳，保留上一版"
  是**两条不同口径的句子**，必须一起念。只念对自己有利的那一句，就是把门禁当装饰。
- **读不到输入不等于通过**，脚本自己的三处证据：
  ① `build/gates.sh:161-166` 的自检 `FATAL 解析不到 $v —— 报告格式变了？不要拿空值当 0 判绿` 然后
  `exit 2`（头部 §1 那段还记了 r60 那次"读不到把 WNS −0.482 换成一句'读不到'"的教训，
  现在读不到时**把候选行原样打出来**）；
  ② 两项警告类的分支 `say "端口宽度警告 8-689" "NOLOG" "无凭据=未验" 0`
  与 `say "多驱动 net 8-685x" "NOLOG" "无凭据=未验" 0`——**没有凭据直接判红**，不判"没发现所以干净"；
  ③ `naa()` 那两支（`methodology CRIT —— … 这一项没门禁（#164：过去空结果被当合法的 0 念成 PASS）`
  与 `cdc.rpt Critical 行 —— … 空集合不是通过`）走的是第三态：计入 `未判`，
  于是结尾只能出 `GATES: PARTIAL`，而 `build/freeze_evidence.sh` 就 grep 那一行、自然拒绝冻结。

## 4. 板级复验（`build/board_verify.sh` 的 geom + battery）

- 件 `build/evidence/r118_board/board_verify_console.txt`（2026-10-04 04:47:07 那一跑）自己打印的：
  `RESULT PASS geom_check（ok=10 fail=0）`、
  `RESULT PASS uart_cmd_check  (105 条命令, 97.9 s, 捕获 board/uart_script_capture.txt)`、
  `RESULT board_verify PASS（判红的步骤：0）`，
  以及电池里那条 `ok   V9-6 温度格三方对账：4 条 [TEMP] 的 degC↔osd↔gpio 全部自洽`
  和留档判定 `[SERIAL] 落点=build/evidence/r118_serial_raw.txt 行数=4 [TEMP]=2 判定=绿（地板 2）`。
  geom 与 battery 是**两条不同的证据链**：脚本头部那行写着
  "与电池分开取证：电池看**回显**，这一条看**像素域真值**"。
- 它不做什么（脚本头部明写）："**不刷板子**"，三件套的下载顺序留给人或别的脚本；
  `--round=rNN` 不给 ⇒ "判红而不写文件"（头部 §round 那段：默认值会把今天的数写成一份名字叫旧轮的假凭据）。
- **零样本那一格必须原样念**：同一次运行的"2) 读回口"打的是
  `lane30 src_state → {… "eth_live":0 … "why":"没有流"}`，紧接着下一行是 `drop_words → 0`。
  这两行不能拆开引用：`report/log/ISSUES.md` #316 记的就是"`drop_words=0` 第一次是**零样本通过**
  （`eth_live=0`），带流重测才作数"。带流那一读在
  `build/evidence/r118_board/bitcycle_console.txt`（04:46:17 起流 50 s）：
  摘要两行 `a: eth_live=1 owner_eth=1 drop_words=0` / `b: eth_live=1 owner_eth=1 drop_words=0`，
  而**同一份摘要里** `pkt_err=? frames_bad=? drop_seen=?`——三个字段没读出来，
  `report/log/ISSUES.md` #318 把"读不出来的字段"显式化成 `?`。⇒ 这三格是 NOT_MEASURED，
  不许写成 0，也不许拿上一版 r116 那两次带流读数替它答（`board/ACCEPTANCE.md` E6 那行
  明写那两句不给 r118 借用，件 `build/evidence/r116_board/`）。
- **板级表里那 10 行的版本戳**：`board/ACCEPTANCE.md` "机器判据"一节开头自己写着
  "本表**按行记版本**……把某一行的数当'这一版验过'之前，先看这一行有没有'rNN'字样"，
  结论那句"机器判据 10 条全部通过"因此**不能整体算作 r118 已验**：那 10 行的读数分属
  r92 / r94 / r96 / r97 那几跑，r118 本轮被重新盖章的是上面点名的 geom + battery + 串口留档。
- 射程之外：板级复验不判时序窗（那 5 个收端点没有约束，STA 不参与，见 `submit/05-timing.md` §6）、
  不判屏上观感（第 5 节）、不写 QSPI/SPI flash（`board/ACCEPTANCE.md` 首页那句"上板方式只走 JTAG"）。

## 5. 人眼签收（`board/ACCEPTANCE.md` E1–E6）

这一节的存在理由在 `report/KNOWN_ISSUES.md` §三那张表的最后一行：
"人眼判据是外部输入——屏幕上'有没有那条线'由队员判，智能体没有看屏幕的能力。
凡是依赖人眼的结论，本仓库都记成'待眼睛'或'用户回报'，**不混进机器判据**"。

**2026-10-04 在 r118 上由队员点头的两格**（原话与条件按表里那一行引用，不概括）：

- **E6**（上电那一度，`#247`→`#256`→`#260` 那条链）：原话「**0度**」，条件按表里前置逐条满足——
  板子断电 ≥10 s 冷上电、之后只跑 `build/tcl/ps_jtag_boot.tcl`→`program_pl.tcl`→`ps_app_reload.tcl`
  三步、**全程没人碰 KEY1/KEY2**，看的就是屏第二行 `ROT:` 那一格。
  件 `build/evidence/r118_eyes/`：`STATE.txt` 汇总三步 rc=0 与逐条读数，
  `step1_boot.txt` 的 `DDR_ECHO: 10000000: 5A5AA5A5`、`step2_program_pl.txt` 的
  `PROGRAMMED xc7z020_1 <- build/system.bit`、`step3_app.txt` 的 `DOW: ok`、
  `uart_stat.txt` 的 `[STAT] … osd=1`；刷进 PL 的那块按 `md5sum build/system.bit`
  = `cd04907e1369da35d21c4090d552f5ee` 对回 `build/evidence/r118_board/BOARD_NOW.txt` 点名的 r118 身份。
  **对照那一半仍未做**：表里那行写的是"上电后按住 KEY1 到链子跑完再松手、那一读应当是 1 度——
  它需要你再断一次电，所以这一条只登记'未判'，不写成过"。本章照抄这个"未判"。
- **E4**（旋转整幅在屏内、四角不戳出）：原话「**现在屏幕没问题了四角都在屏幕内**」
  （2026-10-04 08:3x，板上 r118，bit `cd04907e1369`），判法就是那一行左列那一套：
  `src 2` 图卡 + `bilin on` + 手动 `zoom 1.0` + `zoom fit 0` + `rot auto`，走到 45°/60° 档看四角。
- E1 / E2 / E3 的点头分别是 2026-09-30（r92/r93，原话"现在都很正常"、"现在画面正常只有一条"）
  与 2026-10-01 22:1x（r103，原话"1 rot 在走 zoom 是 0.52 没有 3 没有"）⇒
  那几行不给 r118 借用。E4 的另外一半（顶部碎影随不随速度变宽）表里已经写了眼睛的回答
  与"我给的定量预测被眼睛判掉一半"的处置，见 `report/KNOWN_ISSUES.md` §一 第 1 条。
- 眼睛也**不判逐行**：E2 那一行自己写着 #189 的发生率台架量到 ≈0.27 %（3726 个旋转态像素命中 10 个），
  "**这种稀疏度本来就不保证肉眼抓得到**，所以这一格'过'的意义是'没看到错位'，不是'逐行验过'"；
  逐行那部分归 `sim/tb_zoom_frac.v` 的 S1/S2/S3。E5 那行还写着一条**工具形状的欠账**：
  串口既没有 `[LINK]` 回包也没有 `FPS` 的数字回读 ⇒ 那一格只能看屏，屏幕读数不属于机器判据也不进门禁。

## 6. 四类互不替代（谁也不能替谁答话）

| 判据 | 它答得了 | 它答不了 | 拿它替别人答会变成什么 |
| --- | --- | --- | --- |
| 台架（`sim/`） | 像素域几何/内容、协议栈逐格、空集守卫下的计数 | 硬件截断类（#103）、占位原语之外的厂商行为、屏上观感、片外 I/O 窗 | "仿真全绿"写成"设计已验"——`report/KNOWN_ISSUES.md` §三第二行禁的就是这句 |
| 发布门禁（`build/gates.sh`） | 盘上报告 vs 阈值的 24 项机械对账 + 范围声明 | 任何"这一版是不是真跑过"之外的语义；它不重跑构建 | 门禁 23 绿写成"23 项已验证"；n/a 写成绿（`#164`） |
| 板级复验（`build/board_verify.sh`） | 命令→回显、命令→像素域真值（geom）、链路计数、温度三方对账、串口留档 | 时序窗、屏上观感、刷板本身（脚本头明写"不做什么：不刷板子"） | 把 `drop_words → 0` 从 `eth_live=0` 那一次里单独摘出来当"零丢包已验"（#316 的形状） |
| 人眼（E1–E6） | 屏幕上有/没有、四角在不在屏内、上电那一格读几 | 逐行覆盖率、没有机读口的量（角度：`report/log/ISSUES.md` #185/#247） | 把眼睛的"没看到"写成"逐行验过"；把机器读不到的量写成机器判据 |

`board/ACCEPTANCE.md` 结论第三行给的正是这套分工的最后一句：
"门禁的**项数与红绿以 `bash build/gates.sh` 打印的那一行为准**，本表不复制它，以免两处漂"。

## 本章依据的产物
- `build/tb_v98_report.txt`
- `sim/run_one.sh`、`sim/`（`tb_*.v` 计数）、`sim/prim/`
- `build/gates.sh`
- `build/r118_gates_final.txt`、`build/evidence/r118_board/g2c.txt`、`g3c.txt`、`gatesc_summary.txt`
- `build/board_verify.sh`、`build/evidence/r118_board/board_verify_console.txt`、
  `build/evidence/r118_board/bitcycle_console.txt`
- `board/ACCEPTANCE.md`、`build/evidence/r118_eyes/STATE.txt`（含 `step1_boot.txt`、
  `step2_program_pl.txt`、`step3_app.txt`、`uart_stat.txt`）、`build/evidence/r118_board/BOARD_NOW.txt`
- `report/KNOWN_ISSUES.md`（§一 第 1 条 `C5c`、§三 验证边界那张表）
- `report/log/ISSUES.md`（#164 同族、#316、#318、#332）
- `docs/timing/ROUND_r118.md`（§二 判据 B4）
- `data/metrics.csv`
- `build/tcl/README.md`
