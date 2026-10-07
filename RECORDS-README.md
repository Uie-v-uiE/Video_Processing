# `records/20261007` 这一支里放的是什么

这一支**不是提交物**，是"把这台机器上为这个项目产生的全部记录都放到网上"的一次归档，**会随台账往后跟账**。
交付树仍然是默认分支 `main`（评委看的那一份），逐轮过程账在 `all`；这一支把它们之外的那几层原样搬上来。

- 基点：第一笔是快照 `db55268`，之后每跟一次账/刷一次包就多一笔
  ⇒ **本支当前 HEAD 请用 `git ls-remote origin refs/heads/records/20261007` 现读**，这份说明件故意不写自己的提交号（写了就立刻是旧的）。
  树里的内容对齐到：交付分支 `main` = `eb5933b`（板上的位流 `cd04907e1369` / 工程 `934ebdbaa13b` / 固件 `57fa442a7eaf`，
  三枚 md5 与 `board/README.md` 逐字符对上）、过程分支 `all` = 台账 **#475** 那一笔（`4d37225`）。
- **树的内容**按可读副本 `D:\Xilinx\Prj\Video_Processing` 整棵搬（20:4x 第二次全量刷新，`cp -a`）：仓库半那
  **1223 件 = `main` 的非厂商跟踪件 1133 + `all` 独有的 87 支过程件 + 只住在副本里的三把尺子**，再加上本地六层、片源与 `tools/`。
  这里有个讲究：`ARCH/` 与 `LEARNING/` 里每一条 `文件:行号` 引的都是 **`main` 那一版**的交付文档，所以这一支必须铺 `main` 的文档层——
  第一次误从 `all` 起树时，第一层引用尺子当场报 `EMPTY_LINE`/`OUT_OF_RANGE`（同一份 `report/host_guide.md`：`main` 那版 `wc -l` 读 **234**，
  `all` 那版读 **188** ⇒ 引 `:197` 的那条直接越界），改铺之后重跑读 `ARCH 判=3103 OK=3103`、`LEARNING 判=1092 OK=1092`。
- 搬运之外只动三处：片源 `sd.mp4` 从根挪进 `media/`；git 之外那批工具与留档搬进 `tools/`；新写本说明件。
  **没有改写任何一份被搬文件的内容**（怎么复核见最后一节）。

## 各层是什么、多少件（20:4x 现量）

| 层 | 件数 | 是什么 |
|---|---|---|
| 仓库半（`src/`、`sim/`、`build/`、`report/`、`board/`、`data/`、`skills/`、两份 README、LICENSE、三支入口脚本、`.gitignore`/`.gitattributes`） | **1223** | `main` 的非厂商跟踪件 1133 + `all` 独有的 87 支过程件（`report/log/` 台账到 #475、`report/timing/` 各轮账、`board/measured/`、`build/evidence/` 等）+ 三把本地尺子 |
| `LEARNING/` | 10 份 `.md` / 4004 行 | 九卷 + 入口 README 的学习文档与经验总结（面向"从零开始"的读者） |
| `ARCH/` | 11 份 `.md` / 5616 行 | 十卷 + 入口 README 的架构拆解（假定读者已会 PL/PS 与 Verilog/C） |
| `study_docs/` | 141 件（138 份 `.md`）/ 4.1 M | 四套学习册：`main_report_study/`（含时序四份与**今天新写的 SD 卡准备一节**）、`branch_deep_course/`、两套 course+walkthrough |
| `poster/` | 3 件 | 决赛海报：`index.html` + 300 dpi A4 PNG + 单页 PDF |
| `PDF/` | 5 件 | 三份打印件（技术文档 11 页／上位机 6 页／海报 1 页）+ 两份中间 HTML；上位机那份是 18:59 从 `8eefc56` 重印的 |
| `final_submission/` | **3142** 件 / 141 M | 交付包本体（`main` 的 `eb5933b` 于 **20:33:09** 导出，`MANIFEST.txt` 声明 3141 条 + 它自己），按选题指南 §3.3.5.4 的形状；含包内两棵工程副本（`board/vivado_system` 315 支、`board/vitis` 2128 支） |
| 根下四份本地件 | 4 件 | `演示流程-3分钟.md`、`提交表-创新关键词与项目简介.md`、`REVIEW-20261007.md`、`BUNDLE-Contents.md`（与可读副本同名同内容） |
| `media/sd.mp4` | 1 件 / 66 996 905 B | SD 那一路的原始片源（两支分支都不跟踪它；`src/host/make_sd_video.mjs` 的输入） |
| `tools/` | **4796** 件 | git 之外的一切：`sync_bundle.sh`、`md2pdf_run.sh`+`md2pdf.mjs`、`r128_bundle_reconcile.mjs`、`dircount_claims.mjs`、`r120_tier_*.rpt` 四份逐时钟名册、`learning_tools_mirror/`、`tmpsub/`（一次性对照器、串口捕获、导出日志）、`doc_audit_20261005/`、`skill_v2/`、`deep_course_candidates/`、`pkg_archive/`（**三版留档旧包**：`cadb49a`/`4d398a3`/`e805e6f` 共 4538 件 + 两份改口前的 PDF + 一份中间 HTML） |

`tools/pkg_archive/` 里那一版 `e805e6f` 的包在这一支改叫 **`pkg_e805e6f_1825`**（本机原件仍叫 `final_submission_e805e6f_1825`）。
缩名不是整理癖：`git add` 在 Windows 上对超过 260 字符的路径直接报 `Filename too long` 并**整笔原子失败**（一支都进不去），
全树只有 **3 支**越界、最长 **263** 字符，都在这份留档包里；把目录名省 13 个字符后最长降到 **250**，添加才通过。
**没有开 `core.longpaths`**：那样推上去的路径在本机默认设置下 checkout 不出来，会楔死下一次克隆。
⇒ 这一支里这份留档的目录名与 `tools/` 脚本、`REVIEW-20261007.md`/`BUNDLE-Contents.md` 里写的本机绝对路径**指同一份东西**，映射写在这里。

`tools/tmpsub/` 里三件值得单看：`decl_check_ctl.sh`（把导出器 §3.11d 那段循环抄成可重跑的对照器，它的"有牙"读数
`未点名= board/vitis/(2128 支) board/vivado_system/(315 支)` 就是它打的）、`export_final_e805e6f.log` 与 `export_eb5933b.log`
（两跑导出器的完整 stdout，含五条自检原文）、`qspi_*` 那三件（QSPI 自启档的串口捕获、判据器 stdout、lane 快照 JSON，台账 #473 已把它们搬进 `board/measured/`）。

## 这一支**不保证**的事

1. **交付门禁不在这里跑**。`build/deliver_spec_check.mjs` 那 18 项与四把文本尺子管的是 `main` 那一棵树与提交包的形状；
   这一支多出来的九千来件（学习文档、留档旧包、工具、64 MiB 片源）按定义不在它们的射程里，在这里跑只会得到一堆与交付无关的红。
   要读判据读数：`main` 树上的尺子读数与包内的 `build/reports/`、`board/output/`、`board/measured/`。
2. **有本机路径是故意的**。`tools/` 里的脚本写着 `D:\Xilinx\Prj\pro\…`，因为它们本来就不随包、只在这台机器上跑；
   交付层那条"不许出现盘符"（导出器的"甲 可执行件 + 乙 复现入口件"）不适用于这一支。
   密钥面扫过：`password|api_key|secret_token|PRIVATE KEY|ghp_…` 这类形状命中的文件全是
   `build/checks/check_repo_hygiene.sh` 自带的**反例内容**与我自己写的扫描说明文字，不是凭据。
3. 单文件最大的是 `media/sd.mp4` 64 MiB，低于 GitHub 的 100 MB 硬门（`find -size +95M` 现量 0 支）；
   `final_submission/`、`tools/pkg_archive/` 里那几份包与 `main` 内容重叠的部分由 git 按内容去重，不重复占带宽。

## 为什么 `sd_stage/`、`c2_scratch_1003/`、旧的 `submission/` 没进来

| 没进来的东西 | 盘上体积 | 不进来的理由 |
|---|---|---|
| `Prj/pro/sd_stage/` | **1.3 G** | 往 SD 卡倒片源的分片中间物，可由 `src/host/make_sd_video.mjs` 从 `media/sd.mp4` 重出（制片步骤写在 `study_docs/…/09_SD卡本地回放.md` §10） |
| `Prj/pro/c2_scratch_1003/` | 99 M | Vivado 的临时工程树（策略扫描留下的），结论件都在 `main` 的 `build/evidence/` 与这一支的 `tools/` 里 |
| `Prj/pro/submission/` | 49 M | 早期那一版提交目录（r80 时代的形状），已被 `final_submission/` 整条取代 |
| `Prj/pro/{Video_Processing,delivery_review_20261005,records_wt,tmp_main_tree,edge_tmp}/` | — | 前两支是 git 工作树（内容就是 `main`/`all` 那两个提交），后三支是这棵树本身、临时展开树与浏览器 profile |
| `Prj/pro/dvi_tm_guide.pdf` | 244 K | 第三方芯片手册抄件，不适合推到公开仓库；需要它的人在本机 `D:\Xilinx\Resource\` 那一带能取到 |

## 想核对"这一支确实只是搬运、没改内容"

- 与 `main` 比（这一条是 20:5x 现量，读数存在 `tools/tmpsub/branch_vs_main.txt`）：
  `git -c core.quotePath=false diff --name-status --no-renames origin/main HEAD` 读 **A 8204 / D 2443 / M 0**。
  **`M 0` 才是"只是搬运"那句话的可判形式**：两边共有的 **1133** 支路径逐字相同，含刚对齐到 `eb5933b` 的 `src/ps/sd_play.c`。
  `D 2443` 不是缺东西——那是 `main` 根下的 `vitis/`(2128) + `vivado_system/`(315)，这一支把它们放在包的同一层，
  **树摘要逐字相同**（`git rev-parse origin/main:vitis` = `HEAD:final_submission/board/vitis` = `a4ea409806c0…`，
  `origin/main:vivado_system` = `HEAD:final_submission/board/vivado_system` = `fa435e2d9d3d…`）⇒ 内容一件没少，git 按内容去重。
  `A 8204` 的逐层分布：`tools/` 4796、包 3142（`main` 不跟踪 `final_submission/`）、`study_docs/` 141、`report/` 70、
  `ARCH/` 11 + `LEARNING/` 10、`build/` 10、`board/` 10、`PDF/` 5、`poster/` 3、`media/` 1、根下 5 份说明件。
- 被跟踪件数与盘上件数也对得上：`git ls-files | wc -l` = **9337** = `find -type f` 的 **9338** 减掉工作树指针文件 `.git` 那**一支**
  （它是 69 字节的文本指针，不是内容件；别把它读成"漏了一支"）。
- 与可读副本比（20:5x 现量）：`find . -type f -not -path './.git/*' -not -path './tools/*' -not -name RECORDS-README.md | wc -l`
  在这一支读 **4541**、在副本 `D:\Xilinx\Prj\Video_Processing` 那侧同一算式读 **4540**，**差的那一支就是工作树指针文件 `.git`**
  （这一支是 `git worktree`，根下 `.git` 是一支 69 字节的文本指针、会被 `find -type f` 数进去；副本那侧 `.git` 是目录，数不进去）。
  除此之外两侧同形：片源在副本根下、在这一支挪到了 `media/`，件数不变。
- 交付包：进 `final_submission/`，`find -type f | wc -l` 应读 **3142**，`MANIFEST.txt` 头三行应读
  `导出时间: 2026-10-07 20:33:09 / 来源提交: eb5933b（导出时工作区未提交改动 0 条） / 文件数: 3141，体积 141M，本次剪掉 532 条`。
  与上一版包（`e805e6f`/18:25:43，留档在本支的 `tools/pkg_archive/pkg_e805e6f_1825`，本机原件叫 `final_submission_e805e6f_1825`）逐件比过 md5：
  路径双向差集 0，**内容有变的只有 2 件**（`MANIFEST.txt` 与 `src/ps/sd_play.c` 那一行单位注释）⇒ 搬运没夹带别的改动，那一笔重导的真实增量也只有这两件。
- 学习文档两层尺子（在这一支的根上可以直接跑，尺子就住在 `build/`）：
  `node build/learning_cite_check.mjs ARCH` 应读 `判=3103 OK=3103`，`node build/learning_cite_check.mjs LEARNING` 应读 `判=1092 OK=1092`；
  第二层 `learning_anchor_spot.mjs` 的读数（含 ARCH 那 51 条"可疑待读"为什么不算红）写在
  `ARCH/README.md` 与根下 `REVIEW-20261007.md` §3 第 6、19 条。
- 逐轮账：`report/log/issues.md` 从 `all` 跟过来，条目号到最后一条应当连续（本支这次跟到 **#475**）。
