---
name: tcl-query-empty-means-broken-ruler
description: 在 Vivado Tcl 查询返回空集合时，先判"我的过滤器坏了"再判"设计里没有这个东西"；当探针打印出 0 个对象 / 0 颗单元 / COUNT=0，且同一条命令带了 -quiet，或错误被 catch 吞掉，或症状是 MF-REFUSE、名册没认出网、fanout 扫描 ge200=0 这类"太干净"的读数时使用。
---

## 1. 一句话用途

空集合先怀疑尺子，别当设计结论。

## 2. 适用场景

- 当探针/脚本打出 `*=0`、`COUNT=0`、`NO=0`、名册"没认出网"，而查询串里带 `-quiet` 时。
- 当 `catch {…}` 之后只看变量是否为空串，没有打印返回码时（本仓形状：`build/tcl/probe_r114_idelay_prop.tcl:27` 那类写法）。
- 当你用 `-filter {属性 eq 值}` 写查询时（本版本 `eq` 不是合法操作符）。
- 当对象名里带方括号（`wptr_reg[5]`、`rok4[51]_i_1_n_0` 这类 RTL 生成的名字，示例取值），而查询用的是裸 pattern/通配。
- 当你想拿 `get_nets -of [get_pins …]` 的单点结果当"就是报告里那一段"的证据时。
- 当"扫全设计"返回的总数小得可疑（本仓实测：不带 `-hier` 的 `get_nets -quiet *` 只回 1000 个顶层网）。

## 3. 不适用 / 失效条件

- 不适用：查询没有 `-quiet`、错误原文已经打在控制台上——那时直接读错误串，不必做对照实验。
- 不适用：结论本来就不是"没有对象"而是"对象存在但属性为空"——那要走 `get_property` 的存在性核对，本条只覆盖"集合基数"。
- 失效：换 Vivado 版本后 `-filter` 支持的操作符集合可能不同；本文只写本仓在 2025.2.1 上量到的那一条（`eq` 报语法错），别版本未测。
- 失效：非 Vivado 的 Tcl 环境（Vitis xsdb 的 Tcl、自写 `tclsh`）里没有 `get_nets`/`get_cells` 这套命令，本条的命令形状不适用。
- 不许越界：本条不判"这个对象该不该存在"，只判"你这次读数是不是可信"。

## 4. 前置条件

- 一个已存在的 DCP 或工程状态（本仓形状：`impl_1/system_top_opt.dcp`，示例取值，需按自身工程替换）。
- `vivado -mode batch -source <探针.tcl>`，批处理加 `-nojournal -log <路径>`，否则日志落在当前目录。
- 同一份探针里必须并排放：一个**正对照**（已知存在的对象，换一种写法查）与一个**负对照**（已知不存在的名字，必须为 0）。本仓真实形状见 `build/evidence/probe_mf114_netname_console.txt:106`（`NO_SUCH_NET_should_be_zero`）。
- 探针文件全文 ASCII（见 `console-codepage-verdict-shift`）。

## 5. 使用方法

1. 把可疑查询原样贴进批处理跑一次，**打印返回码而不是只看变量**：
   `catch {set s [get_cells -quiet -hier -filter {REF_NAME eq IDELAYE2}]} rc; puts "rc=($rc) n=[llength $s]"`。
   完成后应看到：`rc=` 非 0，且控制台带出错误原文（本仓实测原文见步骤 2）。
2. 找错误原文里的报错码：`grep -n "Common 17-263" build/evidence/r114_idelay_prop_console4.txt`。
   完成后应看到：一行 `ERROR: [Common 17-263] There was a syntax error while parsing filter expression: 'REF_NAME eq IDELAYE2' at position '9'`
   ——即"0 个对象"根本不是设计的答案，而是这条语法错被 `-quiet` 吞掉后的空集。
3. 换合法操作符重跑同一查询：`-filter {REF_NAME == IDELAYE2}`（字符串相等）或 `=~`（GLOB 匹配）。
   完成后应看到：非空计数（本仓实测 `build/evidence/r114_idelay_set_console.txt:55` 打出 `IDELAY_N=5`，同一份 DCP）。
4. 名字里含方括号的对象改用**分层路径直取**并回读 NAME 验证：
   `set n [get_nets -quiet u_a/u_b/some_reg[5]]` 然后 `puts [get_property NAME $n]`（示例取值）。
   完成后应看到：基数 1 且 NAME 打出的字符串正是你查的那个分层全名。
   本仓实测（`build/evidence/probe_mf114_netname_console.txt:94`）：四种写法里只有不带 `-hier` 的直取回 1，
   `-hier` 全名、`-filter "NAME == {全名}"`、`-filter "FULL_NAME == {全名}"` 四档都回 0。
5. 需要"全设计"基数时，显式加 `-hier` 并把总数与报告里的数对照（本仓实测：不带 `-hier` 的 `get_nets -quiet *` 只回 1000 个顶层网）。
   完成后应看到：一个与报告口径能对齐的总数；对不齐就把两个数都留在件里，不写结论。
6. 选目标对象时要求**两路独立取名同名**：一路来自报告文本自己打印的段名，一路来自对象查询；不一致就停。
   完成后应看到：两个来源给出同一个名字（本仓事故：驱动侧 `get_nets -of [get_pins …/Q]` 给出 7 引脚的另一根网，而报告段名是 239 引脚那根，`report/log/ISSUES.md` #320）。
7. 带选项的新命令先落 `help` 清单再用：`help phys_opt_design` 之类输出存进同一件目录，判定器把你用到的每个选项对回那份清单。
   完成后应看到：你用的选项在清单里（本仓实测 `build/evidence/r117_d0/nethelp_console.txt:395` 打出 `PO_OPTION_COUNT=31`，同文件第 404 行 `-skeleton_clustering present=0`）。

## 6. 判读与失败分叉

- 步骤 1：
  通过 = rc=0 且集合非空。
  失败 = rc≠0 ⇒ 尺子坏，按错误原文修语法，本次读数作废。
  读不到输入 = rc=0 且集合为空 ⇒ 判 `NOT_MEASURED`（不是"设计里没有"），必须去做步骤 3 或步骤 4 的对照。
- 步骤 2：
  通过 = 找到 17-263 这类明确报错码。
  失败 = 控制台没有错误原文而集合为空 ⇒ 十有八九是 `-quiet` 吞的，去掉 `-quiet` 重跑。
  读不到输入 = 你手上没有那份控制台落盘 ⇒ `NOT_MEASURED`，探针必须 `-log` 落盘再判。
- 步骤 3：
  通过 = 同一 DCP 上换写法后基数从 0 变成 N>0 ⇒ 结论只能写"上一版过滤器坏了"。
  失败 = 仍为 0 ⇒ 再试步骤 4 的直取写法；两条都空才允许写"这一版设计里可能没有"。
  读不到输入 = 报"no such object"级别的错 ⇒ 你的属性名不存在，用 `list_property` 取真名。
- 步骤 4：
  通过 = NAME 回读串 == 查询串。
  失败 = 回读为空但基数 1 ⇒ 属性选错（本仓实测 nets 的 `FULL_NAME` 是空），换 `NAME`。
  读不到输入 = 直取也 0 ⇒ `NOT_MEASURED`，先确认那份 DCP 是不是你要读的那一版。
- 步骤 5：
  通过 = 总数与报告口径同量级。
  失败 = 总数远小于报告 ⇒ 你扫的是顶层；补 `-hier` 重跑。
  读不到输入 = 两个口径都没数 ⇒ `NOT_MEASURED`，不许写"没有高扇出网"这类干净结论。
- 步骤 6：
  通过 = 两路同名。
  失败 = 两路不同名 ⇒ 停：`get_nets -of <引脚>` 单点取名不算证据（本仓 #320）。
  读不到输入 = 报告那一路读不到段名 ⇒ `NOT_MEASURED`，回 `report-field-parse-breaks` 修解析。
- 步骤 7：
  通过 = 用到的选项全部 present=1。
  失败 = 出现 `ERROR: [Common 17-170] Unknown option` ⇒ 本次这一滚根本没执行到位，读数作废（本仓 #319 两次 8 分钟空滚）。
  读不到输入 = 没有 help 清单落盘 ⇒ `NOT_MEASURED`，先探针 40 秒取清单。

## 7. 已验证的效果

- 基线（不用本条时得到的错结论）：`report/log/ISSUES.md` #279（2026-10-03 16:57）记下三处"0"被当成事实写进文档与计划
  （`ODDRCELL_COUNT=0`、`IDELAY_BY_REF=0`、`MF-REFUSE … 名册没认出网`）。本轮没有重跑那三支探针（要开 Vivado 批处理 + 有 DCP 现场），
  所以"换 `==` 之后 ODDR 到底有几颗"记 `【未实测】`。
- 用它之后（件里可查的实测对照，同一份 DCP）：
  坏写法报错原文 `build/evidence/r114_idelay_prop_console4.txt:63`；
  好写法计数 `build/evidence/r114_idelay_set_console.txt:55` = `IDELAY_N=5`（2026-10-03 16:55 落盘）。
- 四种查找形式的并排对照（本轮实跑 `grep -a` 读到的原文行号）：
  `build/evidence/probe_mf114_netname_console.txt:94 / :97 / :100 / :103` 四行都是 `F0_plain=1 F1_hier=0 F2_NAMEfull=0 F3_FULLNAME=0 F4_NAMEshort_hier=0`，
  负对照 `:106` 为全 0（探针落盘 2026-10-03 18:17）。
- 选项清单对照：`build/evidence/r117_d0/nethelp_console.txt:395` `PO_OPTION_COUNT=31`，`:404` `-skeleton_clustering present=0`（2026-10-04 02:52 落盘）。
- 本轮未做的事（如实）：我没有重新执行任何 `vivado -mode batch` 探针（需要 DCP 现场与许可证），因此本条的效果证据全部来自**已有件**而不是我这一轮的实跑；
  我这一轮实跑的只有对那几份件的 `grep -n` 直读。

## 8. 提炼来源与边界

- 证据：`report/log/ISSUES.md` #279（`-quiet` 吞语法错）、#286（三种 `-filter` 形式在网对象上恒空 + 射程三条）、#319（选项名凭记忆 ⇒ 空滚）、#320（`get_nets -of 引脚` 与报告段名不是同一对象）。
- 件：`build/evidence/r114_idelay_prop_console4.txt`、`build/evidence/r114_idelay_set_console.txt`、`build/evidence/probe_mf114_netname_console.txt`、`build/evidence/r117_d0/nethelp_console.txt`、`build/evidence/r115_window/console2.txt:177`。
- 代码形状：`build/tcl/probe_r114_idelay_prop.tcl:27`（仓库里**故意留着** `eq` 那一行当负对照，用于重现 17-263）。
- 工具行为断言的来源行见 `skill/pitfalls/_proposed-sources.md`。
- 停止适用的条件：如果你的流程完全不通过 Tcl 文本查询取对象（只用 GUI/波形或只用报告文件），本条降级为"空结果必须配正对照"这条通用纪律。
- 迁移到新题目/新板卡要改的地方：
  1. 操作符合法性绑定 Vivado 版本（本文只测 2025.2.1）；
  2. 对象名形状（`u_a/u_b/*_reg[N]` 是本仓 RTL 命名，示例取值，需按自身工程替换）；
  3. DCP 路径与 run 名（本仓 `impl_1/system_top_opt.dcp`）；
  4. 7 系列 ↔ UltraScale+ ↔ Versal：可查的属性/对象类不同（本仓实测 `get_property FANOUT [get_nets …]` 在 7 系列这一版返回空），换家族要重新量而不是套用。
