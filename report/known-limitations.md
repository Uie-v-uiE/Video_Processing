# 已知限制与没做到的事（面向读者的一页）

这一页只写**已经量到的**和**明确做不到的**事。每条按四项读：**现象**、**已定位的原因**、**现在的处置（是否影响演示）**、**凭据**。
未决项集中登记在 `report/90-open-items.md`，这里不重复编号，只给指路。

名词先说一次：下面说的"发布前检查项"指 `build/gates.sh` 逐项打印判定那套检查；"检查脚本"指仓库 `src/host/`、`build/checks/` 里可独立复跑的只读核对工具。

## 1. HDMI 源端合规：能给的是"离散"，给不了"眼图"

- **现象**：HDMI CTS 的 Source 侧 TP1 判据是**眼图掩模 + 抖动 + 占空比 + 边沿速率**，正式表格文本只发给 HDMI Adopter（NDA）。
  公开能引用的只有规范正文与仪器厂商应用笔记的转述。
- **已定位的原因**：`skew ≤ 0.20 Tcharacter` 是**单边的离散上限**，`set_output_delay` 表达的是**双边捕获窗**，两者量纲不同。
  把前者当后者绑上去，实测直接把三条数据道判成 `−3.48 / −3.46 / −3.47 ns` 的"违反"——量纲用错，不是设计错
  （登记在 `report/log/issues.md` 第 335 条）。
- **现在的处置（是否影响演示）**：布线后逐脚实测 互对最差 **0.065 ns**（限 4.000 ns）、对内最差 **0.001 ns**（限 0.300 ns）；
  候选约束件默认**不进构建**（开关 `VP_R119_TMDS_WINDOW`）。出图与推流不依赖这组约束，演示路径不受影响。
  对外口径只到"离散量已测"，不含眼图那四项。
- **凭据**：`build/evidence/r119_window_check.txt`（含 5 份输入的现算 md5 头）；口径与边界见 `report/io/hdmi_tp1_sdc_measurement.md`。
  眼图、抖动、占空比、边沿速率需要示波器/探头与合规测试治具，这一维度是 `【未实测】`：没有做过眼图级量测，只量到离散参数。
  板级走线（连接器/线材）对离散的影响也没有单独量过。

## 2. PS 侧固件：能重建 ELF，重建那颗必须重新上板复验才算板上验证过

- **事实（实测）**：`src/ps/` 可以用一条命令编成可上板的 ELF——
  `PS_CC=<Vitis>/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe PS_BSP=<仓库根>/vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp node build/ps_app.mjs`，
  编译器自述 `arm-xilinx-eabi-gcc (GCC) 13.3.0`，跑完打印 `ENTRY _boot@0x000000cc` 与 `OK`。
  凭据 `build/evidence/1005_ps_app_rebuild.txt`（含逐条命令与两个 md5）。
- **边界（这一节要说的）**：重建产物的 md5 是 `4ed58740785c…`，与随包并在板上跑过验收的那颗 `d0b07f84a068…` **不同**
  （那颗更早、由 IDE 侧构建）。所以"`src/ps/` 改了"到"板上已修好"之间缺的是**重刷 + `board_verify` 复验**这一步，
  不是一次编译。
- **两个入口条件**：`PS_BSP` 要给**绝对路径**——Windows 侧 gcc 拿相对路径会去找 `vitis\platform\…\Xilinx.spec` 而读不到该文件；
  `build/ps_app.mjs` 里 `PS_CC` 的默认安装位置与实际安装位置不一致时会直接打印 `FATAL: arm-none-eabi-gcc 不存在`，
  这句只说明默认值没指对，按上面的写法显式给 `PS_CC` 就能编。
- **凭据**：上述重建记录件；`report/build.md` 的变量表（`PS_CC`/`PS_BSP`/`PS_OUT`）；
  板上那颗的身份与逐轮 `board_verify` 记录在 `build/evidence/`。

## 3. 时序与约束：三笔欠账

| 欠账 | 现象 | 已定位的原因 | 现在的处置（是否影响演示） | 凭据 |
| --- | --- | --- | --- | --- |
| 6 个 TMDS 输出端口的对外约束 | 只量了"离散"这一维度（第 1 节） | 发布前检查项不接受把 skew 当窗口绑进去（量纲不同，`report/log/issues.md` 第 335 条） | 绑之前要先定"对外声称符合到哪一档"；未绑，屏上出图照常 | `report/io/hdmi_cts_source_window.md` |
| `rgmii_rx` 捕获钟提前（BUFIO / MMCM 相移，`report/log/issues.md` 第 194、323 条） | 量过一轮，未采纳 | 收益假设 0.5/0.2 ns 还没有独立证据钉住 | 保持未采纳，收口 I/O 输入窗仍走下面复现路径那一节的口径 | `report/timing_global.md`、`report/log/issues.md` |
| 旋转角度的机读回（`report/log/issues.md` 第 185 条） | OSD 上能看，串口读不到 | 要占一条空闲 lane，属功能取舍，归队伍定 | 眼睛判读继续，`ROT:` 那一格不进机器判据 | `board/acceptance.md` |

另外：`build/gates.sh` 的 24 项里长期有 **1 条写明过的未通过项**（`C5c`），它是"已知且公开登记"的项，不是被忽略的失败；
本仓库的采纳口径是"除声明项外无未通过项"。

## 4. 复现演练：哪些命令是别人可跑的，哪些不是

- **现象（现算读数）**：`report/repro-check.md` 的判定分母是 **61 行**，判定列读数 **PASS=49 / FAIL=0 / 未测=12**，
  判定列不成词 **0 行**（先前那 14 行是表形问题：§8.1 把判定写在第 4 列、§9 那张第三轮表根本没有判定列；
  两处都改成了"判定在末列"，换列件是 `build/r124_repro_verdict_col.mjs`，只动列序与一个判定词的写法）。
  这一层由 `node build/checks/check_repo_consistency.mjs` 的 C9 打印，同一份件现在打印的末行是
  `C9 A/B/C 路径复现演练 判 9 项 判定列在内=61 行 PASS=49 FAIL=0 未测=12 判定列不成词=0`，判 PASS。
- **旧口径的读数留在这一条**：更早一版 C9 数的是整篇文本里 `PASS`/`FAIL`/`NOT_MEASURED` 的**出现次数**，读出
  `PASS=91 FAIL=30 未测=32` 并据此把 C9 判成未通过。那两个数与本件的条数分母不同源
  （`report/repro-check.md` §1：第一轮 43、第二轮 38、两轮相加 81），
  这条错位本身登记在 `report/claims-vs-evidence.md`。计数口径换成"只读每行判定列"之后 C9 的输入变了，数字随之变；
  保留旧数是为了让手上还拿着旧读数的人能对上账。
- **12 行未测的构成**：路径 B 的 9 行（`B1`/`B1b`/`B2`/`B3`/`B3b`/`B4`/`B4b`/`B5`/`B6`，都要真跑一次构建或全量仿真）、
  结果比对的 `M4`、换 ELF 对照的 `C3c`（见第 2 节：重建那颗与板上那颗 md5 不同），
  以及第三轮那张表的 `C4`：两跑健康计数的原件（`health_r118docround_a.json` 与 `_b.json`）已被记录在案的
  精简笔删掉、不随包 ⇒ 正文里那串读数是当时的转述，包内指不到件，所以它不能算成一条判定。
- **现在的处置（是否影响演示）**：交付口径是"环境自检与只读结果比对两类命令可由第三方在本机复跑，上板那一半（JTAG 三步、
  串口电池、推流）已实测跑过"；构建与全量仿真那 10 行需要在场的时间与一次完整构建，不声称第三方可以照抄复现全部结果。
  演示走的是复现说明里"接线、构建、三步上板、推流"那条最短路径。
- **凭据**：`report/repro-check.md` §1 与 §9（逐条命令、期望输出、实跑摘要、判定）。

## 5. 检查脚本自己的两处不足

1. `build/checks/check_repo_hygiene.sh` 的断链层每 token 派生 4 个进程 ⇒ 整脚本 >300 s 未返回，终审 C5 记 `NOT_MEASURED`
   （读数件 `build/evidence/r120_final_gate.txt`）。C1 层已用"一次 awk 替代逐成分派生"修掉
   （同样 400 条路径：266 s 降到 0.14 s，六个计数逐位相同）；C5 层照同一配方还没落地，
   登记在 `report/log/issues.md` 第 339 条末段。
2. 三处**判定口径错位**，未通过项报在检查脚本身上而不是设计上：C2 的取路径正则吞全角标点（6 条未通过 → 0 条）、
   C3 把行文碎片/运行期产物/被 `.gitignore` 排除的学习文档当成"指路"（66 → 3）、
   C1 把"别处引用版本号"当违规（改成只有取值不同才算未通过，并另放一个故意写错的文件来证明它仍会报未通过）。
   教训与规矩写在 `report/log/issues.md` 第 339 条。

## 6. 命名合规没做完

- **现象**：改名之前的那次快照是全仓跟踪文件 **3601 个**，其中 **308 个路径含大写字母**
  （末段含大写 266 + 中间段含大写 45 − 两段都含的 3 = 308），惯例名（README/LICENSE/NOTICE/Makefile/.git\*）
  点名豁免 22 个 ⇒ 检查脚本报 **违规=286**。改名波之后同一条命令读到 `跟踪文件=3666 违规=10 点名豁免=72`，
  判据是"违规=0 才算过" ⇒ 这一项仍未通过。
- **已定位的原因**：计数从 230 涨到 286 的增量在交付文档自身新增的路径——`git diff --name-status HEAD~2 HEAD` 现算得
  新增 61 条含大写段的路径、删掉 1 条。
- **现在的处置（是否影响演示）**：惯例名已点名豁免，其余要改名会断 `build/frozen_r*/MANIFEST` 的 md5 配对
  （目录名随构建轮次变化，属不可逆连带面）⇒ 待裁决，不挡演示。
  逐段核对方法与第一次对账的登记见 `report/log/issues.md` 第 337 条，裁决问题记在 `report/questions-for-team.md` Q-P21-2。
- **凭据**：`node build/checks/check_repo_consistency.mjs` 的 C4 那一行、`build/evidence/r120_final_gate.txt`。

## 7. 眼睛与手感那部分仍是人的判读

- **现象**：需要人眼/手感验收的项（屏上四角、碎影、按键手感、SD 拔卡观感）由队伍成员签字确认。
- **已定位的原因**：这类判读没有机器可读的输入口（旋转角度那一格见第 3 节的欠账表），检查脚本与文档写作侧不代签。
- **现在的处置（是否影响演示）**：已收到并如实登记的两条原话——**"现在屏幕没问题了四角都在屏幕内"**（E4）与
  **"0度"**（E6 冷上电读 0，件 `build/evidence/r118_eyes/`）。E6 的另一半（按住 KEY1 不放时应当读 1 度）**仍未判**，
  那一半不写进结论，登记在 `report/60-failure-analysis.md` 的 B4。
- **凭据**：`board/acceptance.md`、`board/signoff.md`。

## 8. 工具版本绑定的东西

- **现象**：全部时序/资源数字来自 **Vivado/Vitis 2025.2.1（build 6403652）** 与 **xc7z020clg484-2** 这一颗器件
  （权威声明：`report/declarations.md`）。
- **已定位的原因**：数字是那一版工具与那一颗器件算出来的，不是器件无关量。换版本或换器件 ⇒ `ps7_init`、BD 地址、
  实现策略与**全部发布前检查项的读数作废**。
- **现在的处置（是否影响演示）**：演示与复现步骤都按这一版工具走，本页各条读数不外推到别的版本；
  复现说明第一篇就是版本与器件的环境自检，跑一遍即可确认一致。
- **凭据**：`build/timing_summary.rpt`、`build/utilization.rpt`、`build/power.rpt`、`report/declarations.md`。
  7 系列原语（`IDDR/IDELAYE2/IDELAYCTRL/OSERDESE2/MMCME2_BASE`）在别的家族整段失效。

## 9. 行为层面的已知缺陷

| 现象 | 状态 | 凭据 |
| --- | --- | --- |
| 收侧 ARP/ICMP 没有错误源（判不了"收到的东西坏了"这条路） | **未修**。顶层把**原始** `gmii_rx_dv`/`gmii_rxd` 直接交给 `u_arp`（`src/rtl/eth/eth_udp_video_top.v:129-131`）与 `u_icmp`（`:142-144`），而同一份顶层 `:186-192` 已经产出带 FCS 判定的干净流给视频那条路 ⇒ ICMP 校验和只采不验（`src/rtl/eth/icmp_rx.v:240-241` 存下 `icmp_checksum`，全模块没有一处比较它）、ARP 学到的地址被误码帧钉死。正常链路下不触发 | `report/known_issues.md` §17、`report/60-failure-analysis.md` A8、`report/log/issues.md` 第 205 条 |

两条**曾经**登记在这一节、现在已修并有复验读数的，写在这里防止被念成未修：

- **SD 播放中拔卡画面永久冻帧、插回不恢复**（`report/log/issues.md` 第 94 条）：修法是给 PS 片源补心跳与清零条件
  （心跳在 `src/ps/main.c:253`，读失败那一拍停心跳在 `:271-277`，卡插回自动重挂在 `:1590`），
  复测原话"拔下 SD 卡已经可以重新播放画面，并且串口也回应了这个自动重挂的消息"登记在 `report/known_issues.md` §四。
- **一条 0 字节 `ping` 把 ICMP 应答器永久打死**（第 216、218 条）：根因在收侧 `src/rtl/eth/icmp_rx.v` 的
  `st_rx_data` 出口条件在 0 载荷时回绕，修法是把 `total_length == 28` 记成旗标（`src/rtl/eth/icmp_rx.v:210`）
  并让该状态当拍收束（`:261`）；台架 `sim/tb_icmp_rx_len.v` 钉住这一族。板级复验读数在 `build/r104_board_ping.txt`：
  普通 `ping -n 4` **4/4**、`ping -l 0` **3/3**、`ping -l 32` **4/4**，全部 0 % 丢失；
  同一族在 `build/r114_board_ping.txt` 重读过一次，同样 4/4、3/3、4/4。
