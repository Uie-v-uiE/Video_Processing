# 晨读指南 · 2026-10-05 夜间文档轮

一句话：**这一轮只动文档与尺子，没动 RTL、没跑构建、没碰板子、没有 push**。
整理好的交付文档在 `D:/Xilinx/Prj/pro/delivery_review_20261005/`（git worktree，分支 `review/20261005`），
仓库目录形状与 `Video_Processing/` 一致，可以直接按目录对比。

## 1. 先看这三处（五分钟）

```bash
cd /d/Xilinx/Prj/pro/delivery_review_20261005
git log --oneline b65a191..HEAD          # 本轮 7 笔，逐笔写的都是"改了哪一类、为什么"
git diff --stat b65a191..HEAD | tail -3  # 规模：约 66 份文件、4150 增 / 3081 删
node build/deliver_spec_check.mjs        # 判 18 项 红=0 未测=0 PASS（赛题形状）
```

然后读首页两份：`README.md`（项目是什么、怎么复现）与 `report/README.md`（哪一格落在哪个文件）。
这两份是评委真正会读完的，也是我这轮改得最狠的。

## 2. 你这轮要求的事，各自的结果

| 你要的 | 做到的 | 没做到的 |
|---|---|---|
| 以评委角度审整份文档，找"不像人/不合适"的地方 | 220 份叙事文档逐份过；抽出 7 条风格红线写进 `doc_audit_20261005/STYLE_CONTRACT.md`（钟点叙事、rNN 当叙述、自我 hedge、内部黑话、跟指南吵架、凭据堆叠、顺序） | 箭头符号密度（`⇒` 2,695 / `→` 1,632）与 `#NNN` 台账编号（2,009 处）留给你定，见第 4 节 |
| 单独建文件夹、按目录整理 | worktree 就是那个文件夹：`src/ sim/ build/ board/ data/ skills/ report/` 全形状，66 份改写件各归其位 | 提交包本身**还没重导**（`bash build/make_submission.sh` > 25 min，且要等你先合并） |
| 不要推到 GitHub | 7 笔只落在本地分支 `review/20261005`；`origin/main` 仍是 `b65a191`，一个字节都没出去 | — |
| 按附件那份规格写学习资料 | `docs/walkthrough/` 15 篇全在盘上（新增 `code-reading.md` 811 行、`myths.md` 935、`mechanics.md` 1652、`design-choices.md` 743、`next-layer.md` 631；`glossary.md` 348→1070 词条 25~53；`prerequisites.md` 85→282 含"第 0 层"）。回述测试跑了两位读者，存档 `_feedback/recall-run-a.md`、`recall-run-b.md` | 学习文档**不入库**（`.gitignore` + 导出器硬剪），也不会随包 |

## 3. 本轮量到的数字（都是这棵树上现跑的）

```
bash build/gates.sh                      判 24 项：23 绿 / 1 红（唯一红 = 声明过的 C5c，与 r118 官方件同形状）
node build/deliver_spec_check.mjs        判 18 项 红=0 未测=0 PASS
node src/host/doc_currency_check.mjs     CURRENCY: 干净（本轮从 29 条过期指路做到 0）
node src/host/line_cite_check.mjs        D5: CLEAN（硬错 0，soft 279 条是排队用的候选）
node src/host/metric_recheck.mjs         判 117 个数 红 0
node skills/_meta/check-skill-package.mjs 判 53 项 红=0
bash doc_audit_20261005/verify_all.sh    改前/改后差分逐份打，回归红 0
```

## 4. 等你点头的 9 件事（我按能判的都判了，剩下的都需要你的信息或授权）

1. **器件与工具那段怎么写**：你给的原话是"指南初级组给 `xc7z020clg400-1`，两者封装与管脚数不同，本工程按实际板子约束"。
   现在首页写的是 `xc7z020clg484-2` + 一句中性说明。要不要保留"指南推荐 2026.1 / 本工程在 2025.2.1 复现"这两句对照，请定。
2. **钟点全部删除**这件事的边界：正文里的 `04:18:27` 那类都清了（保留时长与公历日期）；
   工具原文回显里的钟点（如 `board_verify 2026-10-04 04:47:07`）留着当记录。同意这个分法就照此合并。
3. **`report/log/`（22,643 行过程台账）随不随包**：现在是随包。它最能证明"是自己做的"，也最占篇幅。
4. **`⇒`/`→` 密度**：2,695 / 1,632 处。要不要在交付文档里换成"所以/于是/改成"这类词，我可以做一轮，但会碰 ~90 份文件。
5. **章节与原件两套数字**：8 处分章版数字与原件不同源（`data/metrics.csv` 4 处已登记）。要么"只留原件、分章版只指路"，要么"重算一次指标表"，请选一边。
6. **两份从未入库的板级凭据**（`board/uart_script_capture.txt`、`build/evidence/r116_board/cycle_r114back.log`）：
   现在按导出器口径就地声明"不入库/本地留档"放行。要真入库就得改 `.gitignore`，那是你的决定。
7. **`#NNN` 裸编号（2,009 处 / 52 份）**：现在只在 `report/known_issues.md` 开头解释了一次"这是过程台账的条目号"。
   要不要批量改成"过程台账第 N 条"的中文写法。
8. **导出器那行假话**（`build/make_submission.sh:163` 写 "docs/ 与 report/ 两层都随包"）：这轮没动它。要我改掉就说一声。
9. **新发现的一条 AXI 协议形状**（mechanics 取证时提出的）：`src/rtl/axi/axi_frame_writer_gated.v:138-146`
   在 abort 时把已举起、尚未被 `arready` 接受的 `m_axi_arvalid` 直接清 0。按 ARM IHI 0022 Issue J
   §A3.2（p.39）/§A3.3.1（p.41）的字面，这与"VALID 拉起到握手之间不许撤回"冲突；本仓互联没报错、
   也没有判据盖住它。**要不要立案成一条债**（并配一支先压 `arready` 再落 abort 的台架），
   还是确认这条路上 PS7/SmartConnect 不会采样、把"字面不符但无后果"写进文档？—— 这一条我没替你决定，
   也没动 RTL。

## 5. 我这轮自己犯过又改回来的两处（写在这里免得你以为是工具在报喜）

- 台账一度把 `report/known_issues.md` 记成"回归 FAIL"。现跑：`死链 1→0 钟点 3→0 丢数 0 → PASS`。
  那条"回归"其实是死凭据 `build/r103_program_pl.log`（盘上是 `.txt`）——既存缺陷，本轮顺手改掉。
- 门禁第 18 项（文档时效）一进来就红。逐条读下来 **29 条里有 11 条是尺子自己看错了**：
  `build/parsed/parsed_cdc.rpt.json`、`board/firmware/ps_app.elf.md` 都是真实跟踪件，旧的取路经的
  正则在第一个扩展名处就收口，拿"少了尾巴的名字"去查盘当然查不到；另有 1 条是围栏里的工具原文回显。
  ⇒ 改的是尺子的射程（两处各配一对能红/能绿对照），不是把文档改到让机器闭嘴。剩下的 17 条才是真指路错。

## 6. 合并与推送（等你看完再做，我不会替你做）

```bash
cd /d/Xilinx/Prj/pro/Video_Processing
git log --oneline b65a191..review/20261005      # 先读这 7 笔的说明
git diff b65a191..review/20261005 -- README.md   # 首页单独看一眼，这是门面
git merge review/20261005                        # 认可后再合
bash build/make_submission.sh                    # 合并后重导提交包（>25 min，包才会绑到新 HEAD）
git push                                         # 你说推，我才推
```

`doc_audit_20261005/` 里是这轮的全部工具与账（`STYLE_CONTRACT.md` 规则、`check_docs.sh` 改前/改后差分、
`AUDIT.md` 21 节审计正文、`CHANGES.md` 逐份清单、`fix_pointers.mjs`/`fix_learn_paths.mjs` 两轮指路修正）。
这些都不随包。

## 7. 一条读法警告（我这轮自己踩过）

`node skills/_meta/check-skill-package.mjs` **不带参数会走错射程**（它把当前目录的上一层当技能包根，
于是判起 `Prj/` 下的兄弟目录）。交付文档教的调用法是带参数那一条：

```bash
node skills/_meta/check-skill-package.mjs skills    # 判 53 项：条目=49 索引=50 红=0 未测=0 PASS
```

要不要把这个工具的无参默认改成"缺参就 REFUSE"，是第 4 节之外的第 10 件可定项（本轮没动工具）。

## 8. 又收掉的一条既存红（本轮第 8 笔 `1fbf2f8`）

技能包门禁 C12 里那条 **S1 黄金一致**在干净检出判红（主工作树判绿）：原因是夹具
`skills/scripts/contract-to-host/fixtures/contract.csv` 的换行没被 `.gitattributes` 钉住，
`core.autocrlf=true` 下 checkout 写成 CRLF，而契约 digest 按磁盘字节算 ⇒ 三份产物逐字节全不符。
现在只给 `skills/**/fixtures/*.csv` 加了 `text eol=lf`（不动 `data/*.csv`，理由写在属性文件尾注）。
改后干净 worktree 实测 `S1 相符=3/3 PASS`、`run-all-checks 判 9 项 红=0`。
⇒ 这条绿以前**只在你这台机器的工作树里存在**，评委 fresh clone 会红；现在两边一致。

## 9. 还剩两条红，都不是本轮改坏的（含我建议的下一步）

干净检出里 `check_repo_consistency` 的 C3 报 `死引用=7`，而 `doc_currency` 报干净——同一批行、两把尺子、
两套豁免话术（C3 只有"碎片/运行期/台账"三个分支，没有"同行声明不随包"这一支）。我没在收尾时段给 C3
加豁免（那要连它自己的三条能红对照一起做）。**下一轮最小做法**：C3 从 `doc_currency_check.mjs` 源码读
`NOSHIP_MARK`（读不到就 REFUSE），命中同行就计入 `skipShip` 并打印条数，另加"有声明不红／无声明必须红／
隔行不算"三条对照。

另一条红是 C9（A/B/C 路径复现演练：PASS=92 FAIL=31 未测=33）——它要一次**真构建 + 真板**才收得掉，
不是文档能修的；主工作树同一把尺子是 `红=1`（只剩 C9）。两条 未测：C5 许可机检 300 s 超时、C7 `对=0` 空集。

## 10. 早上补的：那个红收掉了（板子实测 + 两条尺子的量纲/词表）

- **C9（复现演练）以前是数整篇的 `FAIL` 字样**，所以"把已知缺陷如实写进期望值"就永久判红。
  现在只读每行的判定列，并配五支能红/能绿对照。
- **C3（文档内路径存活）与 `doc_currency` 的豁免话术合成一套**（词表从对面源码现读，读不到就整项不判），
  那 7 条"真实存在但按设计不入库"的指路不再一边放行一边判红；配两支对照。
- **板子实测**：JTAG 三步 + 推流 50 s + `board_verify --battery --geom` 全过
  （geom ok=10/fail=0，电池 105 条 97.7 s，末行 `RESULT board_verify PASS（判红的步骤：0）`），
  已写进 `report/repro-check.md` §9 并带凭据文件名。`frames_bad=1` 是读到的数，本轮没下结论。
- **顺手修了自己工具的一处假 `?`**（`build/r116_bit_cycle.sh` 的摘要行），并记下第三次同类教训。
- **演示稿（不上传）**：`report/study/demo_video_3min_20261005.md` —— 三分钟一条过的顺序、逐字命令、
  三条必配字幕、机位与重录规则；它与完整版 `report/demo_script.md` 的九幕一一对照，砍掉的三幕写明为什么砍。
