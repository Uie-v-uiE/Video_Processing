# 2026-10-05 午：board/ 与 build/ 的第二轮清理清单（决策矩阵 + 射程实测）

用户原话（两条仍然没做完的）：
- board/：「这个目录的东西全删了重新写…应该放的是上板工程、运行脚本与实测输出这三个」
- build/：「老实放 tcl 重构脚本和 README 说明…还有一些综合和实现报告…其他的全删了精简一些」

**本轮实测到的形状（2026-10-05 05:35，HEAD `c4d89de`）**：
- `board/` 顶层 34 项，其中三类之外的 **21 项**：`HANDS_ON.md boot27c.tcl cmd_battery_v81.txt
  cmd_overflow_probe.sh compare ddr_churn_probe.mjs demo_rehearsal.txt evidence_r29 evidence_r41
  hardware_setup.md pswhy.tcl raw-vs-golden.md rdbck.tcl rdddr.tcl serial_bytes.ps1
  signoff-questions.md uart_cap_once.ps1 uart_capture.txt uart_cmd_script.ps1
  uart_script_capture.txt verify_r87.md`
- `build/` 顶层 **`.txt` 155 份 / `.rpt` 27 份**（用户要的是"挑几个重要版本的综合/实现报告"）。

## 一、射程实测（删之前必须知道的数）

`grep -rl <名> --include=*.md --include=*.sh --include=*.mjs report board build sim data docs src` 的引用**文件数**：

    board/compare                    25   ← 最大射程
    board/hardware_setup.md          15
    board/uart_script_capture.txt    15   （注意：它是"盘上有、git 里无"的那颗，见 #383/①类）
    board/HANDS_ON.md                 7
    board/verify_r87.md               7
    board/evidence_r29                6
    board/evidence_r41                6
    board/raw-vs-golden.md            5
    board/rdddr.tcl                   5
    board/signoff-questions.md        4
    board/pswhy.tcl                   4
    board/boot27c.tcl                 3
    board/rdbck.tcl                   3
    board/uart_capture.txt            2

`build/*.txt` 里**被尺子或门禁当输入**读的（承重，不许删）：
`cdc_baseline.txt`（门禁第 6 项基准的姐妹件）、`multi_driven.txt`、`ports_check.txt`、
`ports_check_width_ce.txt`、`tb98_gate_ce.txt`、`tb_edge_r52*.txt`、`tb_v98_report.txt`、
以及仅剩的五份带 `ALL PASS` 的门禁件 `r74_gates.txt`/`r99_gates_nope.txt`/`r104_gates.txt`/
`r118_gates.txt`/`r75_gates.txt`（`gates.sh` 第 18 项 D3 的基准 = 编号最大的那份）。

被文档点名最多的一批（删要一并改口）：`board_temp_r97.txt`=6、`cdc_baseline.txt`=6、
`multi_driven.txt`=5、`crit_paths.txt`=4、`gates_r62.txt`=4、`ports_check.txt`=4。

## 二、决策矩阵（三类为尺）

| 现状 | 归类 | 处置 |
|---|---|---|
| `zynq_video_sys.xpr`、`zynq_video_sys.srcs/`、`vitis_platform/` | 上板工程 | 留（已是唯一工程入口） |
| `scripts/board_flash.sh`、`scripts/board_health.sh` | 运行脚本 | 留 |
| `measured/*.txt`、`measured/*.json` | 实测输出 | 留 |
| `acceptance.md`、`signoff.md` | 实测输出（人眼签收，用户原话+时刻） | 留，但**挪进 `measured/` 同级**或保留在顶层二选一——保留时 README 要说清算哪一类 |
| `uart_capture.txt`、`uart_script_capture.txt`、`cmd_battery_v81.txt`、`demo_rehearsal.txt` | 实测输出（原始串口回显） | 挪 `measured/raw/`，文档指路随挪动改口；`uart_script_capture.txt` 从未入库 ⇒ 改口时按"本机捕获不随包"声明 |
| `boot27c.tcl`、`pswhy.tcl`、`rdbck.tcl`、`rdddr.tcl`、`ddr_churn_probe.mjs`、`cmd_overflow_probe.sh`、`serial_bytes.ps1`、`uart_cap_once.ps1`、`uart_cmd_script.ps1` | 一次性探针 | 逐个问"README 的复现步骤里用不用得到"；用不到 ⇒ 删（它们的功能已被 `build/tcl/*` 与 `scripts/*` 覆盖）；用得到 ⇒ 挪 `scripts/` 并在 README 表一行 |
| `HANDS_ON.md`、`hardware_setup.md`、`raw-vs-golden.md`、`signoff-questions.md`、`verify_r87.md` | 文档卡 | 有内容 ⇒ 并进 `board/README.md` 对应小节；纯指路/复述 ⇒ 删；删后要改口的是上表那 7+15+5+4+7 个引用文件 |
| `compare/`、`evidence_r29/`、`evidence_r41/` | 实测比对/旧轮次凭据 | 二选一：① 挪进 `measured/`（承认它是实测输出，射程 25 要一并改口）② 删（射程大 ⇒ 必须先把 25 份引用改成节名指路，别留死链） |
| `build/*.txt` 非承重（≈140 份） | 过程留档 | 删；保留 §一 列出的承重件 + 被文档点名的 6 份（或改口后再删） |
| `build/*.rpt` 27 份 | 综合/实现报告 | 只留重要版本（r118 正式 + 一两个对照轮）；其余删并把文档"报告出处"逐条对回留下的那份 |

## 三、提交包为什么还没导出来（2026-10-05 13:37 实测，导出器 REFUSE）

`bash build/make_submission.sh` 这一轮跑到最后**自己拒绝交包**（`make_submission.sh:588`）：
`REFUSE：技能旧名降级这一层没吃完（包内仍有 45 个 skills 开头的引用落不到文件；规则 71 条／清单 497 行）`，
所以 `../final_submission/` **仍是 2026-10-04 08:13 那份（`MANIFEST.txt` 写着 来源提交 `ef68bb3`）**，
不是 `c4d89de`。别把它当成这一版的包。

根因不是导出器，是**交付文档里的技能引用还停在改结构之前的扁平卡名**（task #200 把 28 张扁平卡重建成
九类目录之后的名字没跟改）。实测两个数：

    文档点名的 `skills/**/SKILL.md` 形状引用：56 个不同写法，其中在盘上存在的只有 15 个
    真正在仓里的卡片：49 张（`skills/{pitfalls,verify,timing,runtime,workflow,rtl,build,references,templates,scripts,prompts}/<slug>/SKILL.md`）
    完全不存在、要按"不随包"声明或删除的：`skills/_meta/entry-template.md`、`naming-and-format.md`、
    `sources.md`、`team-names.txt`、`skills/evals/records/audit-2026-10-04.md`、
    `skills/evals/raw/doc_enc_pass1.txt` 等 —— 清单见本目录 `1005_skill_cite_unresolved.txt`（77 条）
    与 `1005_skill_cite_map.tsv`（45 条已给出新位置）

修法（下一轮，一次做完，别改 `skills/` 本身——用户说 skill 不用改）：
1. 拿 `1005_skill_cite_map.tsv` 里能定位的 45 条，把旧写法换成 `skills/<类>/<slug>/SKILL.md`；
   换完再数一次 `落不到文件` 必须降到 0，不许只降不零。
2. 定位不到的 32 条逐条三分：① 卡片真的被删了 ⇒ 文档改成指向承接它的那张卡；
   ② 那是"当时的记录、本来不随包" ⇒ 同行写声明（D4c/C3 认这套词表）；③ 那句是空指路 ⇒ 删这半句。
3. 之后 `bash build/make_submission.sh` 才会落新包；落完按**盘上文件数**验（`find final_submission -type f | wc -l`）
   并核 `MANIFEST.txt` 的来源提交 = 当前 HEAD，不看导出器自己的 stdout 说"成功"（rule 50）。


1. `tar -cf /tmp/board_build_pre_1005.tar board build`（删除前）；
2. 逐条 `git rm` 前先跑 `grep -rl` 出射程，**一张表驱动删除与改口**（不要两处手写名单）；
3. 删完跑：`build/gates.sh`（第 6/18 项会立刻告诉你承重件有没有删错）、
   `doc_currency_check.mjs`（D4b/D4c 死链）、`line_cite_check.mjs`（D5）、
   `deliver_spec_check.mjs`（C4 报告与脚本映射、C3 路径存活）、`metric_recheck.mjs`；
4. 全绿之后再 commit + push + 重导提交包（>25 min，按盘上文件数验）。


## 五、技能引用改口的分布实测与顺序（2026-10-05 13:43）

77 条落不到文件的 `skills/…` 引用，出自哪些文件（数字＝该文件里这类引用出现的条数，多到少）：

```
59 report/90-open-items.md
11 report/ai_collaboration.md
 7 report/unattended.md
 6 report/collaboration/corrections.md
 5 report/repro-check.md
 4 report/log/issues.md
 4 report/collaboration/README.md
 3 report/collaboration/workflow.md
 3 report/07-skill-distillation.md
 2 sim/tb_v98_top_seam.v
 2 sim/tb_v98_c8_edge_column.v
 2 report/questions-for-team.md
 2 report/collaboration/redaction.md
 2 report/70-reproduce.md
 2 report/60-failure-analysis.md
 1 src/host/metrics.mjs
```

**顺序结论（别顺手全局 sed）**
1. 59/77 集中在 `report/90-open-items.md` 的第 3 节（那是标记枚举表，每行"所在文件与行"逐字抄自技能卡）。
   改这 59 条必然动第 1 节的 Σ 不变式与 C8 的 `正文标记总数`（现值 874 = md 排除本文件 407 + 本文件 467），
   所以必须**同一个写者一次做完**，并按 `make_submission.sh:588` 那条判据自证到 **0**（不是"降到一些"）。
2. 次多的三份 `report/ai_collaboration.md`=11、`report/unattended.md`=7、`report/collaboration/corrections.md`=6
   **不参与 C8 的 Σ**，可以先改、先提交，风险最低。
3. `report/log/issues.md` 里的 4 条是台账历史记录，按规矩不回改（它记的是当时存在过的路径）。
4. `sim/tb_*.v` 与 `src/host/metrics.mjs` 里的 5 条是代码注释指路 ⇒ 改动会挪行号，
   动之前先 `grep -rn "该文件:[0-9]"` 数射程（这一条已经欠过一次：#383 之前的 main.c 教训）。
5. 旧名→新卡口的唯一权威对照是 `skills/_meta/entry-map.md`（106 行，约定 `类别/name/SKILL.md`，
   且 README↔索引双向一致本身是机器判据）；不要凭记忆拼路径。
