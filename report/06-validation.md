# 验证：四类检查各自的适用范围，互不替代

当前这一版验过什么、每条结论出自哪份文件、每种检查答得了什么又答不了什么，一并分开记。
检查分四类，彼此不能替代：

| 类别 | 是什么 | 跑它的命令 |
| --- | --- | --- |
| 仿真台架 | `sim/` 下的 testbench，在 xsim 里逐拍、逐像素判几何与协议行为 | `bash build/sim/run_one.sh <tb>` |
| 发布前检查 | 一条命令读回盘上已有的 Vivado 报告并与阈值逐项对账（不重跑构建） | `bash build/gates.sh` |
| 板级复验 | 在真板子上发命令、读回显、读回像素域真值 | `bash build/board_verify.sh --geom --battery` |
| 人眼签收 | 屏幕上某个现象有没有，只有在场的人能判 | 按 `board/acceptance.md` 的 E1–E6 逐条演示 |

每格的取值只有 PASS / FAIL / NOT_MEASURED 三种。"读不到输入"既不算通过也不算失败，只能写第三态；
这三支脚本自己就打印这三种（第 1 节是它们输出的原形）。
板上现在跑的是 r118，位流 md5 前 12 位 `cd04907e1369`；下文说"这一版""当前板上这一版"，
指的都是这一块位流。

## 1. 三态在脚本输出里的原形

| 层 | PASS 的输出 | FAIL 的输出 | NOT_MEASURED 的输出（同一支脚本自己给的） |
| --- | --- | --- | --- |
| 台架 | `RESULT <tb> PASS` / `VERDICT <tb>: …` | `RESULT <tb> FAIL nfail=N`，退出码 **3** | `VERDICT <tb>: NO-VERDICT-LINE（这支台架一条判定都没打，去数判据条数）`，退出码 **4** |
| 发布前检查 | `GATES: ALL PASS（$NSAY 项全部判定）` | `GATES: 有红项（判定 $NSAY 项）—— 不采纳，保留上一版` | `GATES: PARTIAL —— 判定 $NSAY 项全过，但有 $NNA 项因缺凭据未判（见上面 n/a 行），这一版不作"过门禁"` |
| 板级 | `RESULT board_verify PASS（判红的步骤：0）` | `RESULT board_verify FAIL nred=$NRED ⇒ 这一版不能采纳` | 摘要行里的 `pkt_err=? frames_bad=? drop_seen=?`（问号 = 没读出来） |

表里"判红"是脚本自己用的词，意思是这一项未通过；`$NSAY`、`$NNA`、`$NRED` 是脚本变量写在输出行里的原文，
分别指"判定了几项""因缺凭据没判几项""有几步未通过"。
三处原文的位置：`build/sim/run_one.sh:35-44`（`NO-VERDICT-LINE` 那一支与
"0 绿 / 1 编译或例化失败 / 2 REFUSE / 3 未通过 / 4 认不出判定"的退出码表）、
`build/gates.sh:582-586`（三条 `GATES:` 结尾）、
`build/board_verify.sh:263-265`（`RESULT board_verify PASS/FAIL` 两条）。
`build/sim/run_one.sh:41` 那句注释是四类检查共用的底线："红是结论，'没数'不是结论"。
退出码 3 与 4 因此分开：未通过与读不到输入，在机器侧就是两件事。

## 2. 仿真台架（`sim/`）：像素域与协议域自己判自己

`build/tb_v98_report.txt` 里的计数按文件实数数出来，不引用别的批次：`^PASS` 行 161 行、`^FAIL` 行 1 行，
判定行 `RESULT tb_v98_top_seam FAIL nfail=1`。判据名去掉重复是 47 个
（同文件 `grep "^PASS" | 取第 2 列 | sort -u`）。整屏台架之外，`sim/` 下 `tb_*.v` 共 81 支
（`ls sim/tb_*.v | wc -l`）。

`data/metrics.csv` 的"整屏逐像素判据 141 条"钉的是更早那一次全量台架：件自己写明
`141 = 该文件里 ^PASS 行数 140 加 ^FAIL 行数 1`，头部 `top_md5=2bf2ceeede07`。
现在盘上这份的头部是 `top_md5=56c269602e18`，与它不同源，所以不同批次之间的条数不可比，以当前件为准。
这条差异在 `40-optimization.md` §8 登记为 D2。

唯一那条 FAIL 是 `FAIL C5c frame head is not the previous frame's tail …`。
它是声明过、有意留下的未通过项，登记与复现方法在 问题清单 §一 第 1 条（`#98`）。

每条主判据前面挂一条空集守卫（`PASS C4a rows judged`、`PASS C5a judged rows`、`PASS C9pre rows judged`、
`PASS C11pre …`、`PASS C12pre …`），守卫行自己把"这一格判了几行"印出来。件里那些
`… else C4b below means nothing` / `a green on an empty set (#78)` 说的就是这件事：
没有样本的通过不许存在。

台架答不了的四件事，问题清单 §三那张表逐条点名：

1. 本机只有 xsim。早期能作第二意见的 ModelSim 已不在，所以任何"两家仿真都过"的说法今天不可复现。
2. `sim/prim/` 里是自建的行为级占位原语（`MMCME2_BASE`、`unisims_sim`），
   跑 xsim 看到的 OSERDESE2/BUFG 告警来自占位件，不是设计缺陷。
3. 非打包数组的越界写，xsim 丢弃、硬件按地址位宽截断（`#103` 就是这么来的）。
   这一类问题只用硬件读数收口，仿真通过不算收口。
4. 台架不判屏上观感（第 5 节），也不判 PHY→FPGA 那段片外时序窗口。
   时序章 第 6 节那 5 个收端点没有输入延迟约束，静态时序分析与台架都不在场。

## 3. 发布前检查（`build/gates.sh`）：一条命令读回报告并与阈值比

脚本自报的那一行，件 `build/r118_gates_final.txt` 末行原文：
`GATES: 有红项（判定 24 项）—— 不采纳，保留上一版`。同件倒数第二行连范围一起念：
"结尾必须把范围一起念出来：判定 24 项、未判 0 项"。
条数不写死在脚本里。`build/gates.sh` 头部明写"这里不再写死条数，以本文件里 `say` 的调用次数为准"，
`say` 是脚本里记一项判定的那个函数。24 这个数由这一轮打印，不是抄来的。

当前 24 项 = 23 绿 / 1 红，两跑逐字节一致。件 `build/evidence/r118_board/g2c.txt` 与
`build/evidence/r118_board/g3c.txt` 的末行是同一句 `GATES: 有红项（判定 24 项）……`，
汇总件 `build/evidence/r118_board/gatesc_summary.txt` 打 `GATESC done id=identical green=23 red=1`。

唯一那条红是 `顶层台架 tb_v98 top=56c269602e18 FAIL行=1 指纹(norm1):fresh fresh fresh … FAIL`。
脚本自己在下一行注了一句："报告里有 1 行 FAIL 没有 RESULT…PASS 汇总行
（台架跑完了、是它自己判红的，先读 FAIL 那几行的数）"。那条 FAIL 就是第 2 节声明过的 `C5c`。

检查全绿 ≠ 已验证，三条理由都能从件里指出来：

1. 脚本头部第 22 行写着"数字全部来自 Vivado 报告本身，不重新跑构建"。它判的是
   盘上报告与阈值的机械比较；防"念到上一版"靠自己打出来的新鲜度与三枚 md5
   （`身份：system.bit md5=cd04907e1369 / system.xsa md5=934ebdbaa13b / ps_app.elf md5=d0b07f84a068`），
   不靠"跑过就算验过"。
2. `build/tcl/README.md` §1 对构建侧说过"不要相信退出码"：有两支历史脚本 `add_files` 指向错路径、
   报错之后仍然 exit 0。检查脚本的 0/1 退出码同属"便利"，不是"标准"。
3. 这一版的采纳条件第 4 条写的是"发布门 24 项里红数 == 1（只有声明过的 `C5c`），且检查两跑逐字节一致"
   （那一轮的逐轮页 §二）。脚本结尾那句"不采纳，保留上一版"是另一套口径：前者是采纳规则，
   后者是脚本的默认动作，两句要一起念。

读不到输入也不等于通过，脚本自己留了三处证据：

1. `build/gates.sh:161-166` 的自检 `FATAL 解析不到 $v —— 报告格式变了？不要拿空值当 0 判绿` 然后
   `exit 2`。头部 §1 那段还记着更早那次第 60 批的教训："读不到把 WNS −0.482 换成一句'读不到'"，
   现在读不到时把候选行原样打出来。
2. 两项警告类的分支 `say "端口宽度警告 8-689" "NOLOG" "无凭据=未验" 0`
   与 `say "多驱动 net 8-685x" "NOLOG" "无凭据=未验" 0`：没有凭据直接判未通过，不判"没发现所以干净"。
3. `naa()` 那两支（`methodology CRIT —— … 这一项没门禁（#164：过去空结果被当合法的 0 念成 PASS）`
   与 `cdc.rpt Critical 行 —— … 空集合不是通过`）走第三态：计入 `未判`，结尾只能出 `GATES: PARTIAL`。
   `build/freeze_evidence.sh` 就 grep 那一行，自然拒绝把这一版成套留档。

## 4. 板级复验（`build/board_verify.sh` 的 geom + battery）

`build/evidence/r118_board/board_verify_console.txt` 里那几行原文照抄如下。
取证时刻留在原始记录件里，不进正文叙述：

```text
== board_verify 2026-10-04 04:47:07 ==
RESULT PASS geom_check（ok=10 fail=0）
RESULT PASS uart_cmd_check  (105 条命令, 97.9 s, 捕获 board/uart_script_capture.txt)
ok   V9-6 温度格三方对账：4 条 [TEMP] 的 degC↔osd↔gpio 全部自洽
[SERIAL] 落点=build/evidence/r118_serial_raw.txt 行数=4 [TEMP]=2 判定=绿（地板 2）
RESULT board_verify PASS（判红的步骤：0）
```

console 里的"地板 2"是脚本自己的说法，意思是这一项至少要抓到 2 条才算数。它末尾点名的
捕获件属于未随包的本地串口捕获（`.gitignore:134` 命中 `board/uart_*.txt`），交付包里没有它，
所以这条判定以这段 console 原文为准。geom 与 battery 是两条不同的证据链，脚本头部那行写着
"与电池分开取证：电池看回显，这一条看像素域真值"。

脚本头部也明写了它不做什么："不刷板子"，三件套的下载顺序留给人或别的脚本；
`--round=rNN` 不给就"判红而不写文件"（头部 §round 那段：默认值会把今天的数写成一份名字叫旧轮的假凭据）。

零样本那一格要连着念。同一次运行的"2) 读回口"打的是
`lane30 src_state → {… "eth_live":0 … "why":"没有流"}`，紧接着下一行是 `drop_words → 0`。
这两行不能拆开引用：开发台账 #316 记的就是"`drop_words=0` 第一次是零样本通过
（`eth_live=0`），带流重测才作数"。带流那一读的原文在
`build/evidence/r118_board/bitcycle_console.txt`：

```text
[r118build 04:46:17] 4) 起流 50 s（512x300@60 ≈ 147 Mbps，不限速）
[r118build 04:47:07] 5) 摘要
  a: eth_live=1 owner_eth=1 drop_words=0 pkt_err=? frames_bad=? drop_seen=?
  b: eth_live=1 owner_eth=1 drop_words=0 pkt_err=? frames_bad=? drop_seen=?
```

同一份摘要里还打着 `pkt_err=? frames_bad=? drop_seen=?`，三个字段没读出来；
开发台账 #318 把读不出来的字段显式化成 `?`。这三格是 NOT_MEASURED：不许写成 0，
也不许拿第 116 批那两次带流读数替它答（`board/acceptance.md` E6 那行明写那两句不给第 118 批借用，
件在 `build/evidence/r116_board/`）。

板级表那 10 行的版本归属，看 `board/acceptance.md` 的"怎么读这张表"一节自己怎么写：
"同一个检查项在不同版本上各跑过一次，所以下面按版本分三张表，版本用**位流的 md5 前 12 位**称呼，
不用内部轮次号。想核对'某一行的数属于哪一版'，看该版那张表的抬头"。
所以"机器那一半 10 条全部通过"这句不能整体算作当前这一版已验：其中一批行的读数属于更早那几版，
当前板上这一版重新取证的只有上面点名的 geom + battery + 串口留档。

板级复验答不了三件事：不判时序窗（那 5 个收端点没有约束，静态时序分析不参与，见 时序章 §6）、
不判屏上观感（第 5 节）、也不管刷板本身。`board/acceptance.md` 首页那句"验收那一路只走 JTAG"
说的就是最后一条；把版本固化进板载 QSPI 是 2026-10-05 按要求另做的一次，不在这套板级复验的范围内。

## 5. 人眼签收（`board/acceptance.md` E1–E6）

人眼这一类单列一节，依据在 问题清单 §三那张表的最后一行：
"人眼判据是外部输入——屏幕上'有没有那条线'由队员判，智能体没有看屏幕的能力。
凡是依赖人眼的结论，本仓库都记成'待眼睛'或'用户回报'，**不混进机器判据**"。

2026-10-04 在第 118 批位流上由队员点头的是两格（原话与条件按表里那一行引用，不概括）：

- **E6**（上电那一度，问题链 #247、#256、#260）：原话「**0度**」。条件按表里前置逐条满足：
  板子断电 ≥10 s 冷上电，之后按顺序只跑 `build/tcl/ps_jtag_boot.tcl`、`program_pl.tcl`、
  `ps_app_reload.tcl` 三步，全程没人碰 KEY1/KEY2，看的是屏第二行 `ROT:` 那一格。
  件 `build/evidence/r118_eyes/`：`state.txt` 汇总三步 rc=0 与逐条读数，
  `step1_boot.txt` 的 `DDR_ECHO: 10000000: 5A5AA5A5`、`step2_program_pl.txt` 的
  `PROGRAMMED xc7z020_1 <- build/system.bit`、`step3_app.txt` 的 `DOW: ok`、
  `uart_stat.txt` 的 `[STAT] … osd=1`。刷进 PL 的那块按 `md5sum build/system.bit`
  = `cd04907e1369da35d21c4090d552f5ee` 对回 `build/evidence/r118_board/board_now.txt` 点名的第 118 批身份。
  对照那一半仍未做。表里那行现在写的是"对照那一半仍未做（按住 KEY1 那一次）：
  它需要再断一次电，所以只登记'未判'，不写成过"。这里照抄那个"未判"。
- **E4**（旋转整幅在屏内、四角不戳出）：原话「**现在屏幕没问题了四角都在屏幕内**」，
  登记原文是 `2026-10-04 08:3x 由队员判完`（板上第 118 批，bit `cd04907e1369`），判法是那一行左列那一套：
  `src 2` 图卡 + `bilin on` + 手动 `zoom 1.0` + `zoom fit 0` + `rot auto`，走到 45°/60° 档看四角。

E1 / E2 / E3 的点头分别登记在 2026-09-30（第 92、93 批，原话"现在都很正常"、"现在画面正常只有一条"）
与 2026-10-01（第 103 批，登记原文 `2026-10-01 22:1x 在 r103 上重新点过一次`，原话"1 rot 在走 zoom 是
0.52 没有 3 没有"），那几行不给第 118 批借用；登记原文里的 `r103` 是件里的写法，照抄。
E4 的另外一半（顶部碎影随不随速度变宽）表里已经写了眼睛的回答，
也写了"当初给的定量预测被眼睛判掉一半"的处置，见 问题清单 §一 第 1 条。

眼睛不判逐行。E2 那一行自己写着 #189 的发生率台架量到 ≈0.27 %（3726 个旋转态像素命中 10 个），
"**这种稀疏度本来就不保证肉眼抓得到**，所以这一格'过'的意义是'没看到错位'，不是'逐行验过'"；
逐行那部分归 `sim/tb_zoom_frac.v` 的 S1/S2/S3。E5 那行还写着一条工具侧欠账：
串口既没有 `[LINK]` 回包也没有 `FPS` 的数字回读，那一格只能看屏，屏幕读数不属于机器判据也不进发布前检查。

## 6. 四类互不替代（谁也不能替谁答话）

| 检查 | 它答得了 | 它答不了 | 拿它替别人答会变成什么 |
| --- | --- | --- | --- |
| 仿真台架（`sim/`） | 像素域几何/内容、协议栈逐格、空集守卫下的计数 | 硬件截断类（#103）、占位原语之外的厂商行为、屏上观感、片外 I/O 窗 | "仿真全绿"写成"设计已验"——问题清单 §三第二行禁的就是这句 |
| 发布前检查（`build/gates.sh`） | 盘上报告 vs 阈值的 24 项机械对账 + 范围声明 | 任何"这一版是不是真跑过"之外的语义；它不重跑构建 | 检查 23 绿写成"23 项已验证"；未判写成通过（`#164`） |
| 板级复验（`build/board_verify.sh`） | 命令→回显、命令→像素域真值（geom）、链路计数、温度三方对账、串口留档 | 时序窗、屏上观感、刷板本身（脚本头明写"不做什么：不刷板子"） | 把 `drop_words → 0` 从 `eth_live=0` 那一次里单独摘出来当"零丢包已验"（#316 的形状） |
| 人眼（E1–E6） | 屏幕上有/没有、四角在不在屏内、上电那一格读几 | 逐行覆盖率、没有机读口的量（角度：开发台账 #185/#247） | 把眼睛的"没看到"写成"逐行验过"；把机器读不到的量写成机器判据 |

`board/acceptance.md` 结论第三行给的正是这套分工的边界：
"发布前检查（`bash build/gates.sh` 逐项读回报告并与阈值比）的项数与结果以它自己打印的那一行为准，
本表不复制它，以免两处漂"。

## 本章依据的产物
- `build/tb_v98_report.txt`
- `build/sim/run_one.sh`、`sim/`（`tb_*.v` 计数）、`sim/prim/`
- `build/gates.sh`
- `build/r118_gates_final.txt`、`build/evidence/r118_board/g2c.txt`、`g3c.txt`、`gatesc_summary.txt`
- `build/board_verify.sh`、`build/evidence/r118_board/board_verify_console.txt`、
  `build/evidence/r118_board/bitcycle_console.txt`
- `board/acceptance.md`、`build/evidence/r118_eyes/state.txt`（含 `step1_boot.txt`、
  `step2_program_pl.txt`、`step3_app.txt`、`uart_stat.txt`）、`build/evidence/r118_board/board_now.txt`
- 问题清单（§一 第 1 条 `C5c`、§三 验证边界那张表）
- 开发台账（#164 同族、#316、#318、#332）
- 那一轮的逐轮页（§二 采纳条件第 4 条）
- `data/metrics.csv`
- `build/tcl/README.md`
