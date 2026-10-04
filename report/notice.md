# NOTICE — 第三方件与许可声明（随包材料清单）

核对日期：2026-10-04。本文件回答一件事：**这个交付包里哪些东西不是本包自写的、从哪儿来、有没有跟着包一起发出去、按什么条款可以发。**
每行给四件：**(a) 是什么 → (b) 来源 + 仓内能证明"本包碰过它"的路径 → (c) 随包 / 不随包（只引用） → (d) 许可或授权状态。**

术语约定（避免把"随包"念成"已在最终包内"）：

- **随包** = 该件在本仓库 `git ls-files` 的**跟踪集**内，也就是导出器 `build/make_submission.sh` 的取物范围。
  本轮**没有运行导出器**（另有进程在跑它），所以"跟踪集内 ≠ 一定落进最终包"；最终取舍以导出器自己的判据为准。
- **不随包（只引用）** = 件本身不在跟踪集里，仓库里只有它的名字、页码或若干条从它读出的结论。
- **未核** = 本轮没有打开过任何能证明其分发条款的文件。写"未核"就是"未核"，**不等于"可以自由再分发"**。

| # | 项目 | 来源与仓内凭据（证明本包碰过它） | 随包性 | 许可 / 授权状态 |
|---|---|---|---|---|
| 1 | Vivado / Vitis **2025.2.1**（build 6403652）工具本体 | 版本与器件的唯一权威源 `report/declarations.md`（权威块 `vivado: 2025.2.1`）；`report/build.md:11` | 不随包（只引用；工具需评委自装） | **未核**——本轮没有打开任何 AMD 安装许可/EULA 文本。要定死：打开安装随附的许可文件并在此登记其名称与版本 |
| 2 | Vivado 生成的综合/实现报告（`*.rpt`、`*.txt`，第一行为 Xilinx／AMD 版权横幅） | 件本身在跟踪集内，例：`build/utilization.rpt` 第 1 行、`build/timing_summary.rpt` 第 1 行、`build/evidence/r114_bit/` 成套件 | 随包（跟踪集内命中 **1010** 个文件，见 §3 命令 C） | **未核**——横幅只声明版权，没有给出输出报告的使用条款。这是本包里数量最大的一类第三方件 |
| 3 | `src/ps/lscript_ocm.ld`（链接脚本，**手改过的厂商件**） | 文件头 `src/ps/lscript_ocm.ld:2-4`；原件 `vitis/platform/zynq_fsbl/lscript.ld:2-4`（该目录被 `.gitignore:8` 排除，**不随包**）；改动理由写在同文件 :27 起的注释里 | 随包 | 文件自带 `SPDX-License-Identifier: MIT`（**本表唯一一格是从件本身读到的许可标识**，不是我的推断）。分发时须连同其版权头一起保留 |
| 4 | AMD IP 核：`processing_system7:5.5`、`axi_gpio:2.0` ×3、`axi_interconnect:2.1` ×2 | 实例化命令在跟踪集内的 `build/tcl/build_system_axigpio.tcl:109` 等行；生成目录 `vivado_system/`（被 `.gitignore:2` 排除） | IP 源码/`.xci` 不随包（只引用）；**其硬件交接产物 `.xsa` 随包，实测 17 份** | **未核**——未见任何 AMD IP 的交付条款文本。要定死：核对所装工具的 IP 许可说明 |
| 5 | PS 侧二进制 `ps_app.elf`（静态链接 Vitis standalone BSP：`libxil.a` ＋ `asm_vectors.S`／`boot.S`／`translation_table.S`） | 链接清单与"少喂会产出看似成功的空 ELF"的后果写在 `report/build.md` §3.1（:111-116）；BSP 目录由 `build/build_ps_app.py` 取用 | 随包，实测 **4** 份 `.elf` | **未核**——二进制里含厂商库与厂商启动码，但其许可未在包内随附声明。本作品**不随包发 BSP 源码**，只发已链接成品，这一格风险更高 |
| 6 | AMD 文档 UG903／906／949／904／901／382／482 | 逐条状态登记在 `report/timing/a1_sources.md`:10-15 与 :40 —— 全部标 **未读／未取到** | 不随包 | **未核**，而且**本包没有引用它们的任何正文**（同文件 :18 明写"本轮没有任何一句官方建议"）。文档号与标题的对应关系也没核 |
| 7 | AMD 文档 UG471（7-series SelectIO，188 页）、UG472／UG473／UG585 等 | 原件在**仓库外**本机 `D:/Xilinx/Resource/Reference Material/6-Xilinx Zynq系列部分官方手册/`（`ug471_7Series_SelectIO.pdf` 实测存在）；整本按页扫过的脚本与结论：`build/tmds_source_scan.py`、`report/timing/debt_ledger.md`:147-152 | 不随包（只引用） | **未核**。只引用了一条否定式结论（UG471 第 95 页只给 `TMDS_33` 的 I/O 标准与属性、**没有**任何收／发窗口数），没有转载其表格 |
| 8 | HDMI Specification 1.1／1.3／1.4（三份公开镜像 PDF） | 逐个 URL、字节数、页数、命中页与原文行都在 `report/io/hdmi_cts_source_window.md` §5（:181-183） | 不随包——实测 `git ls-files "*.pdf"` = **0**，包内没有任何规范 PDF | **未核**：镜像 PDF 页脚自标 `HDMI Licensing, LLC Confidential`（该文 :16、:163 原文记录）。包内只引用了 Table 4-24 等**若干条时序量的数值与表名**，未转载整表 |
| 9 | HDMI **CTS**（Compliance Test Specification，对口版本 1.4b；另见 1.2a／1.3c／1.4a／2.0） | 同一文件 §4（:148-165）：**CTS 只经 HDMI Adopter Extranet 分发，本队非 Adopter，未获取其任何一页** | 不随包（且**从未取得**） | **属受限材料，明确不适用任何随包分发**。边界照 §4 原话：包内凡属 CTS 的部分**全部是仪器厂商／公开实测报告的转述（代理）**；逐频点限值表、`HDMI-TP1.msk` 掩码几何、Pass／Fail 余量规则**不可公开引用**。本文件**不重述**该文标为 NDA 派生的数值 |
| 10 | 仪器与实测类第三方文档：Keysight D9021HDMC 编程手册、Tektronix TDS／HT3 物理层合规应用笔记、Diodes PI3HDX1204B1 的 HDMI 2.0 CTS 2.0 报告、Sony HDMI ATC 深圳出具的 CTS 1.4b 报告 | 每份的 URL、打开成功／失败、取到了哪几句原文：`report/io/hdmi_cts_source_window.md` §5（:184-189） | 不随包（只引用 URL 与摘句） | **未核**——未打开过这四份的任何许可页。引用形式是"逐句摘录＋标出处"，摘录范围见该文判定列 |
| 11 | DVI Test ＆ Measurement Guide Rev.1（26 页，educypedia 镜像） | 原件在**仓库外** `D:/Xilinx/Prj/pro/dvi_tm_guide.pdf`（实测存在）；其**文本抽取件在跟踪集内**：`build/evidence/r117/dvi_guide_scan.txt`；扫过它的脚本 `build/tmds_source_scan.py`；结论 `report/timing/debt_ledger.md`:155-159 | PDF 不随包；**派生的抽取件在跟踪集内** | **未核**。只用于一条否定式结论（26 页里没有接收端 setup／hold 的 UI 数），未转载其内容 |
| 12 | 板厂资料三件：Realtek **RTL8211F-CG 规格书**（69 页，Track ID JATR-8275-15 Rev 1.4）、**ZYNQ7020-F+V1.1 原理图**、**RK-ZYNQ7020-F+V1.0 开发板用户手册** | 原件均在**仓库外** `D:/Xilinx/Resource/ZYNQ7020/Board_Resource/`（三个路径逐一 `test -e` 通过，含 `芯片手册/` 子目录）；碰过它们的凭据：`build/evidence/r115_rtl8211f_delay_source.txt`（**规格书整页原文抄件**）、`build/evidence/r115_board_manual_ethernet_excerpt.txt`（**手册 7／36 页摘录**）、`build/evidence/r115_sch_p8/` 内 **4 张原理图第 8 页裁图**；裁图脚本 `build/render_sch_crop.py`；登记页 `board/hardware_setup.md`:100、`report/timing/rgmii_window_model.md`:87-88、:262-263 | 原件不随包；**派生的抄件与裁图在跟踪集内 = 候选随包** | **未核／待决——本表风险最高的一行**。厂商样例目录里没有许可证文件；抄件是"整页不筛不改"的原文、裁图是图纸像素。**在核清之前这几份不应随包分发**，若要发需要权利人书面许可或改为只留"页码＋读数"的引用形式 |
| 13 | 开发板厂商例程 RTL：以太网协议栈一层（点名范围 `arp／icmp／udp／eth_ctrl`；另记"RGMII 文件被逐字复制进本仓库"；原始例程名为"正点原子 eth_udp"） | 范围声明 `report/background_and_novelty.md:32-34`；"逐字复制"一句 `report/study/02_架构/04_跨器件移植_Zynq到UltraScale.md:216`；例程名称与"本仓库未改"的一处残留 `report/study/03_模块详解/01_以太网入包链.md:350`；件本身 `src/rtl/eth/`（跟踪集内 **25** 个文件，含 `rgmii_rx.v`、`rgmii_tx.v`、`gmii_to_rgmii.v`、`eth_ctrl.v`、`arp*.v`、`icmp*.v`、`udp*.v`） | 随包 | **未核**。两点导致它只能挂在"待决"：① 这些 `.v` 里**没有任何版权头**（`grep -rn "Copyright" src` 全仓只命中 `src/ps/lscript_ocm.ld` 一份），无法从件本身判定条款；② **逐文件的"哪些逐字／哪些改造"没有登记表**——`report/README.md:18` 与 `report/log/contest_checklist.md:17` 都把这份登记表指给 `report/log/version_lineage.md`，而该文件里没有逐模块表（同一件事记为 README §9 的 Q-P12-5）。要定死：拿到厂商例程原件做逐文件 diff 并登记 |
| 14 | 运行时与取证用外部库：Node.js **v24.21.0**、Python 3、`pypdfium2`、`pypdf`、poppler `pdftotext` | Node 版本 `report/declarations.md`；`.mjs` 实测**只 `import` `node:` 内置模块与本地 `src/host/repo_path.mjs`**（无 `node_modules`、无 `package.json`、无第三方 `require`）；PDF 抽取依赖出现在 `build/clock_io_delay_scan.py`、`build/render_sch_crop.py`、`build/tmds_source_scan.py` 的 `import pypdfium2`；`pypdf`／`pdftotext` 的用法记录在 `report/timing/a1_sources.md:41`、`report/io/hdmi_cts_source_window.md:4` | 不随包（包内没有它们的任何代码） | **未核**——本轮没打开过这几个库的许可文本。要定死：若要给评委"环境自检"清单，需逐个登记其许可证名称（不得凭记忆填） |
| 15 | 演示片源（SD 回放与推流用的视频） | 转换工具 `src/host/make_sd_video.mjs`（`--in <mp4>`）、`src/host/video_sender.py`；用法 `report/host_guide.md`:32、`report/demo_script.md`:33 | **不随包**——实测 `git ls-files` 对 `*.mp4 *.avi *.mkv *.mov *.wmv *.mp3` = **0**；推流器在无 ffmpeg 时改发**自生成测试图卡**（`report/host_guide.md`:32 原文） | 不适用（片源由使用者自备，其版权责任不在本包） |
| 16 | ModelSim／Questa（曾作为第二意见的仿真器） | `report/log/contest_checklist.md:62`：已不在本机，许可证由新版 FlexNet 签发且自带客户端判 inconsistent ⇒ "两家仿真都过"不可复现；仓库内可复现路径只有 xsim（`build/gates.sh`、`sim/`） | 不随包 | 不适用（本包不含其任何产物）；登记在此只为解释"为什么只有 xsim 一家" |

## 2. 边界声明（本文件不管什么）

1. **不授权**。本文件不授予任何许可，也不改变任何条款。根目录 `LICENSE` 的 MIT 只覆盖**本包自写**的那部分（`LICENSE:3` 的版权人是本队），**不覆盖**上表任何一行。
2. **凡标 `未核` 的行，在核实之前都不得随包分发**。第 12 行（厂商资料抄件与裁图）与第 13 行（厂商例程 RTL）是当前最该先解决的两行；第 5 行（含厂商库的 `.elf`）次之。
3. **`随包` 一列的口径**只到"在 git 跟踪集内"为止（术语约定见本文件开头）。本轮未运行 `build/make_submission.sh`，因此本表不声明最终包内有没有某件；上一轮导出的自我报告在 `build/evidence/r120_export.txt`，它记的是**那一次**的取舍。
4. **不含**：器件／工具版本声明（`report/declarations.md`；`docs/` 自 2026-10-04 起**随包**——导出器第 1 步那段把 `docs/` 并入 `report/` 的迁移是一段两次都退回的改名轮半成品，现已删掉，包与仓库同形状）、性能与资源数字、`report/` 全部叙述文档、以及 `data/` 的自产件清单（`data/golden/manifest.md` 管）。顺带记一条**非第三方但来历含糊**的自产件：`data/golden/src.png` 由一个**已不在树里**的 host 工具产出（`data/golden/manifest.md:70`），故它属"自研但复算链断"，不在本表许可范围里。
5. **不含任何 NDA 派生数值**。HDMI CTS 的可引用性边界以 `report/io/hdmi_cts_source_window.md` §4 为唯一权威，本文件只指过去，不重述其数值、不复制其表格。

## 3. 复核命令（2026-10-04 实跑，每条**连跑两次**同值）

```bash
git ls-files | wc -l                                                        # A  3607  跟踪集总数（本表核对后又提交了一笔 ⇒ 这一格读的是命令不是这个数）
grep -rln "Copyright" src build/tcl | sort | wc -l                          # B  7     其中只有 1 份在跟踪集内：src/ps/lscript_ocm.ld（其余 6 份是未跟踪的 vivado*.log）
git ls-files -z | xargs -0 grep -l "Copyright 1986-2022 Xilinx" | wc -l      # C  1010  跟踪集内含 Vivado 版权横幅的文件（第 2 行的量）
grep -rl "^Copyright 1986-2022 Xilinx" build --include=*.rpt | wc -l         # D  623   build/ 下带横幅的 .rpt（含未跟踪件，故与 C 不等价）
git ls-files "*.elf" | wc -l                                                # E  4
git ls-files "*.bit" | wc -l                                                # F  18
git ls-files "*.xsa" | wc -l                                                # G  17
git ls-files src/rtl/eth | wc -l                                            # H  25
git ls-files "*.pdf" | wc -l                                                # I  0      ⇒ 第 8/11/12 行的原件确实没进包
git ls-files "*.mp4" "*.avi" "*.mkv" "*.mov" "*.wmv" "*.mp3" | wc -l         # J  0      ⇒ 第 15 行成立
```

B 与 C 的差是刻意的：B 只扫 `src` 与 `build/tcl`，C 扫整个跟踪集（综合/实现报告落在 `build/` 与 `skills/` 的留档里）。
外部资料原件的三条路径（第 7、11、12 行）逐条 `test -e` 通过，它们都在仓库之外，所以**评委按本表复现不了它们**——这是有意的事实，不是遗漏。

## 4. 复核归属（作者另跑一遍，不抄子代理回执）

A=3607、B=7（其中被跟踪 1）、C=1010、D=623、E=4、F=18、G=17、H=25、I=0、J=0，
`build/evidence/r115_sch_p8/` 被跟踪裁图=4，逐格与上表相符。A 与初稿报的 3606 差 1，
差的正是这一轮新提交的那份导出留档 ⇒ 这一格该读命令而不是读这个数。
第 12、13 行是随包风险最高的两行（厂商资料抄件／厂商例程 RTL），
处置（撤下、改成"页码＋读数"的引用形式、或取得书面许可）属队伍的决定，已登记为待决项。

