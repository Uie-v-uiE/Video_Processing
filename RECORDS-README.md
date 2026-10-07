# `records/20261007` 这一支里放的是什么

这一支**不是提交物**，是"把这台机器上为这个项目产生的全部记录都放到网上"的一次归档。
交付树仍然是默认分支 `main`（评委看的那一份），逐轮过程账在 `all`；这一支把它们之外的那几层原样搬上来。

- 基点：`all` @ `2b89382`（台账 #471）。这一支的第一笔是快照 `db55268`（远端读回 `db55268cdf816360e5df3cdabdc190646ad5c050`），
  之后每跟一次过程账就再多一笔——**本支当前 HEAD 请以 `git ls-remote origin refs/heads/records/20261007` 现读为准**，
  这份说明件故意不写自己的提交号（写了就立刻是旧的）。交付分支 `main` @ `e805e6f`（板上的位流 `cd04907e1369` /
  工程 `934ebdbaa13b` / 固件 `57fa442a7eaf`，三枚 md5 与 `board/README.md` 逐字符对上）。
- **树的内容**按可读副本 `D:\Xilinx\Prj\Video_Processing` 原样搬（19:0x 整棵 `cp -a`）：仓库半那
  **1219 件 = `main` 的非厂商跟踪件 1133 + `all` 独有的 83 支过程件 + 只住在副本里的三把尺子**，
  再加上本地六层与片源。这一点有讲究：`ARCH/` 与 `LEARNING/` 里每一条 `文件:行号` 引的都是
  **`main` 那一版**的交付文档，所以这一支必须铺 `main` 的文档层——先前误铺 `all` 那一版时，
  第一层尺子当场报出 `EMPTY_LINE`/`OUT_OF_RANGE`（同一份 `report/host_guide.md`：`main` 那版 `wc -l` 读 **234**，
  `all` 那版读 **188** ⇒ 引用 `:197` 的那条直接越界），改回 `main` 那版之后重跑读 `ARCH 判=3101 OK=3101`、`LEARNING 判=1092 OK=1092`。
- 拷贝之外只动了两处：把片源 `sd.mp4` 从根挪进 `media/`（免得与根下那份 `.gitignore` 的形状规则纠缠），
  新写本说明件 `RECORDS-README.md`；git 之外那把工具整批搬进 `tools/`。全部 `cp -a`，没有改写任何一份文件的内容。

## 各层是什么、多少件

| 层 | 件数 | 是什么 |
|---|---|---|
| `LEARNING/` | 10 份 `.md` / 4004 行 | 九卷 + 入口 README 的学习文档与经验总结（面向"从零开始"的读者） |
| `ARCH/` | 11 份 `.md` / 5616 行 | 十卷 + 入口 README 的架构拆解（假定读者已会 PL/PS 与 Verilog/C） |
| `study_docs/` | 141 件（138 份 `.md`）/ 4.1 M | 工作区里全部四套学习册：`main_report_study/`（含时序四份）、`branch_deep_course/`、两套 course+walkthrough |
| `poster/` | 3 件 | 决赛海报：`index.html` + 300 dpi A4 PNG + 单页 PDF |
| `PDF/` | 5 件 | 三份打印交付件（技术文档 11 页／上位机 6 页／海报 1 页）+ 两份中间 HTML |
| `final_submission/` | **3142** 件 / 141 M | 交付包本体（`main` 的 `e805e6f` 于 18:25:43 导出，`MANIFEST.txt` 声明 3141 条 + 它自己），按选题指南 §3.3.5.4 的形状；含包内两棵工程副本（`board/vivado_system` 315 支、`board/vitis` 2128 支） |
| `notes`（在**根下**，不单独开一层） | 4 件 | `演示流程-3分钟.md`、`提交表-创新关键词与项目简介.md`、`REVIEW-20261007.md`（433 行）、副本自己的清单 `BUNDLE-Contents.md` —— 与可读副本里同名同内容，`build/learning_*` 那三把尺子也按这个形状指它们 |
| `media/sd.mp4` | 1 件 / 66 996 905 B | SD 那一路的原始片源（两支分支都没跟踪它；`src/host/make_sd_video.mjs` 的输入） |
| `build/learning_*.mjs` | 3 件 | 只住在副本里的那两把引用尺子与一支修引用脚本（`learning_cite_check`／`learning_anchor_spot`／`learning_fix_cites`） |
| `tools/` | 1638 件 | git 之外的一切工具与留档：`sync_bundle.sh`、`md2pdf_run.sh`+`md2pdf.mjs`、`r128_bundle_reconcile.mjs`、`dircount_claims.mjs`、`r120_tier_*.rpt` 四份逐时钟名册、`learning_tools_mirror/`、`tmpsub/`（本轮的一次性对照器与日志）、`doc_audit_20261005/`、`skill_v2/`、`deep_course_candidates/`、`pkg_archive/`（两份额意留档的旧包 + 两份改口前的 PDF） |

`tools/tmpsub/` 里两件值得单看：`decl_check_ctl.sh`（把导出器 §3.11d 那段循环抄成可重跑的对照器，
它的"有牙"读数 `未点名= board/vitis/(2128 支) board/vivado_system/(315 支)` 就是它打的）、
`export_final_e805e6f.log`（这一轮导出器的完整 stdout，含五条自检的原文）。

## 这一支**不保证**的事

1. **交付门禁不在这里跑**。`build/deliver_spec_check.mjs` 那 18 项与四把文本尺子管的是 `main` 那一棵树
   与提交包的形状；这一支多出来的六千来件（学习文档、留档旧包、工具、64 MiB 的片源）按定义不在它们的射程里，
   在这里跑会得到一堆与交付无关的红。要读判据读数请看 `main` 与 `final_submission/build/reports/`、`board/output/`。
2. **有本机路径是故意的**。`tools/` 里的脚本写着 `D:\Xilinx\Prj\pro\…`，因为它们本来就不随包、只在这台机器上跑；
   交付层里"不许出现盘符"那条判据（导出器的"甲 可执行件 + 乙 复现入口件"）不适用于这一支。
   密钥面扫过一遍：`password|api_key|secret_token|PRIVATE KEY|ghp_…` 这一类形状在文本层命中 3 份，
   全是 `build/checks/check_repo_hygiene.sh` 自带的**反例内容**（它就是要检查这类字符串），不是凭据。
3. 单文件最大的 `media/sd.mp4` 是 64 MiB，低于 GitHub 的 100 MB 硬门；`final_submission/` 那 141 MB 里
   有两千多支与 `main` 同内容，git 按内容去重，不会重复占带宽。

## 为什么 `sd_stage/`、`c2_scratch_1003/`、旧的 `submission/` 没进来

| 没进来的东西 | 盘上体积 | 不进来的理由 |
|---|---|---|
| `Prj/pro/sd_stage/` | **1.3 G** | 往 SD 卡倒片源的分片中间物，可由 `src/host/make_sd_video.mjs` 从 `media/sd.mp4` 重出；推上去只会长体积不会长信息 |
| `Prj/pro/c2_scratch_1003/` | 99 M | Vivado 的临时工程树（跑策略扫描时留下的），里面没有结论件，结论件都在 `main` 的 `build/evidence/` 与这一支的 `tools/` 里 |
| `Prj/pro/submission/` | 49 M | 早期那一版提交目录（r80 时代的形状），已被 `final_submission/` 整条取代；留档的两份旧包在 `tools/pkg_archive/` 里 |
| `Prj/pro/{Video_Processing,delivery_review_20261005,records_wt,tmp_main_tree,edge_tmp}/` | — | 前两支是 git 工作树（内容就是 `main`/`all` 那两个提交），后两支是临时展开树与浏览器 profile |
| `Prj/pro/dvi_tm_guide.pdf` | 244 K | 第三方芯片手册抄件，不适合推到公开仓库；需要它的人在本机 `D:\Xilinx\Resource\` 那一带能取到 |

## 想核对"这一支确实只是搬运、没改内容"

- 交付包：进 `final_submission/`，`find -type f | wc -l` 应读 **3142**，`MANIFEST.txt` 头三行应读
  `导出时间: 2026-10-07 18:25:43 / 来源提交: e805e6f（导出时工作区未提交改动 0 条） / 文件数: 3141，体积 141M，本次剪掉 532 条`。
- 学习文档两层尺子（在这一支的根上可以直接跑，尺子就住在 `build/`）：
  `node build/learning_cite_check.mjs ARCH` 应读 `判=3101 OK=3101`，
  `node build/learning_cite_check.mjs LEARNING` 应读 `判=1092 OK=1092`；
  第二层 `learning_anchor_spot.mjs` 的读数（含 ARCH 那 51 条"可疑待读"为什么不算红）写在
  `ARCH/README.md` 与 `notes/REVIEW-20261007.md` §3 第 6 与第 19 条。
- 逐轮账：`report/log/issues.md` 从 `all` 继承下来，这一支的 HEAD 是 #471，条目号到最后一条应当连续。
