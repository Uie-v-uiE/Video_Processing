
### #475 一行注释的重导花 11 分 18 秒、真实增量只有 2 件；记录支第二次搬运量到 `M=0`；外加一条 Windows 260 字符的门

- **用户改了主意，就把上一笔写下的"不再重导"改口**：#474 末节写明"包保持现状、`records/20261007` 是快照不再追改"，
  当晚用户说"都提交上去吧"⇒ 两件事都要做，而且**那句声明必须跟着改**，否则文档与事实互相打脸。
  形状记下来：**"不再做 X"是一时有条件的决定，条件被撤销时要回到写它的那一行去改**，不是在后面补一句新的。
- **重导的账**：`build/make_submission.sh` 从 `main=eb5933b` 重导，日志 birth 20:21:51 → `MANIFEST.txt` 盖章 **20:33:09**
  （墙钟 **11 分 18 秒**），盘上 `find -type f` = **3142**、`du -sh` = **141M**，清单声明 3141 件 / 141M / 本次剪掉 532 条；
  五条自检读数照旧全过（死链 0／旧名残留 0／绝对路径甲+乙 0／未声明红 0／**MANIFEST 声明核对 核到 9 层 未点名=0**），
  随包台架 82／剔 1、板级凭据点名 136／盘上 99／搬进包 99（撞名 0）、入口脚本 glob 引用只核对到 1 条。
- **"改一行注释为什么要 11 分钟"现在有数了**：把这一版与上一版（`e805e6f`/18:25:43）逐件比 md5——
  两边各 3142 支、路径双向差集 **0**，**内容有变的只有 2 件**：`MANIFEST.txt`（盖章时间 + "来源提交"两行）与
  `src/ps/sd_play.c`（#474 那一行单位注释）。⇒ 那 11 分钟不是这笔改动的成本，是**整包重做的固定成本**（按包计、不按改动计）；
  旧版整目录留在 `pkg_archive/final_submission_e805e6f_1825`，与 `_4d398a3_1500`、`_cadb49a_1215` 并排，**没删**。
- **记录支第二次搬运把"这一支确实只是搬运"变成了一句可判的话**：在 `records_wt` 里 `git add -A -f` 之后
  `git diff --cached --name-status --no-renames origin/main` 读 **A 8204 / D 2443 / M 0**（9337 支被跟踪 = 盘上 9338 − `.git` 那支指针文件）。
  - `M 0` 才是这条判据的意义：**两边共有的 1133 支路径逐字相同**，含刚对齐到 `eb5933b` 的 `src/ps/sd_play.c`。
    先前那一版 README 写的是"应当只有 `report/` 里 `all` 独有的过程件与 `sd_play.c` 的版次差"，
    那是**没量过的推测**，而且自相矛盾（同一句里既说"有版次差"又说"该当为空"）——现在换成实测数。
  - `D 2443` 不是"少了东西"：那是 `main` 根下的 `vitis/`(2128) + `vivado_system/`(315)，这一支把它们放在包的同一层，
    **树摘要逐字相同**（`git rev-parse origin/main:vitis` = `HEAD:final_submission/board/vitis` = `a4ea409806c0…`；
    `origin/main:vivado_system` = `HEAD:final_submission/board/vivado_system` = `fa435e2d9d3d…`）⇒ 内容一件没少，
    git 按内容去重，不重复占体积。
  - `A 8204` 的分布也逐层数了：`tools/` 4796、包本身 3142（`main` 不跟踪 `final_submission/`）、`study_docs/` 141、
    `report/` 70、`ARCH/` 11 + `LEARNING/` 10、`build/` 10、`board/` 10、`PDF/` 5、`poster/` 3、`media/` 1、根下 5 份说明件。
- **新的一道门：Windows 的 260 字符路径让 `git add` 直接罢工**。第一次 `git add -A -f` 报
  `error: open("tools/pkg_archive/final_submission_e805e6f_1825/board/vitis/…/translation_table.S.obj"): Filename too long`
  然后 `fatal: adding files failed`——**这一条是原子的**：`git ls-files` 仍是 6188、`git diff --cached --name-status` 为空，
  一支都没进去（#470 那条"看着像没毛病"的空转在这里以另一种形状出现：如果只看 rc 会以为加了）。
  量了一下射程：整个工作树里**只有 3 支**超 260，最长 **263** 字符，全在那份额意留档的包里；
  把留档目录名从 `final_submission_e805e6f_1825` 缩成 `pkg_e805e6f_1825`（省 13 字符）后最长降到 **250**，`git add` 就 rc=0 全过了。
  **没有走 `core.longpaths=true` 那条路**：不改 git 配置是规矩，更因为推上去的路径如果本机默认设置 checkout 不出来，
  下次克隆会直接楔死——留档的名字在支内与本机不一致这件事写进 `RECORDS-README.md`，让它可查。
- **搬完就重跑尺子**（#472 那一课的第二次应用：任何新复制出来的树，先跑它的尺子再谈提交）：
  在这一支根上 `node build/learning_cite_check.mjs ARCH` = `判=3103 OK=3103 NO_FILE=0 OUT_OF_RANGE=0 EMPTY_LINE=0`、
  `… LEARNING` = `判=1092 OK=1092`；副本那侧同步判据仍是 `判据1 仓库半文件数=1223（= 1133 + 87 + 3）OK`、`RESULT=PASS`。
