### #471 交付清单那页有两层假话、2443 支文件从没被声明过；给导出器补一条"每一层都要被声明过"，再把副本工具那句超射程的话改口

- **怎么发现的**：不是评委问出来的，是我把新包往可读副本里搬的那一步。#470 之后 `a9e5bf7` 把两棵工程副本搬进 `board/`，
  包从 698 支长到 **3141** 支（算式 `698 + 315 + 2128 = 3141`，加的就是这两棵），而 `MANIFEST.txt` 的"目录对照"那段还在写
  `docs/  度量、名册与逐轮台账` 与 `submit/  评审阅读路径`——这两层**早就不在仓库里**：`git ls-tree -r main --name-only` 现量
  `^docs/`=**0** 条、`^submit/`=**0** 条。同时包里占八成文件数的两棵工程副本在清单里一个字都没提。
  ⇒ 一句假话（说了不存在的东西）+ 一句漏说（存在的东西没说），方向相反、错法相同：**清单与货不对板**。
- **三条动作**（`e805e6f`）：① 删那两行，换成一句真话（逐轮台账与逐时钟名册在 `all` 那一支，不在包里）；
  ② `board/` 那行点名两棵副本，件数**现算**（`find board/vivado_system -type f | wc -l`），不是手抄；
  ③ 给导出器补第 §3.11d 条自检：遍历包根 `*/` 全部顶层 + 二级里 **≥300 支**的那些，逐个 `grep -qF` 回 MANIFEST；
  `$UNDECL` 非空 ⇒ REFUSE 且不写 `$OUT`；地板 `DECL_N -eq 0` 也 REFUSE（"扫到空集合而绿"是 #466/#467/#470 那一族）。
  本轮 `make_submission.sh` 的 numstat 是 **+29 / −5**。
- **这条自检有牙的证明**（不改判据语义，只把货换回改前那一版）：拿 `cfad421` 那棵树 + 新自检跑，读
  `核到 9 层；未点名=[ board/vitis/(2128 支) board/vivado_system/(315 支) ]` ⇒ 它抓的是真漏，不是永远绿。
- **本轮（`e805e6f`）落盘读数**：`MANIFEST 声明核对：核到 9 层（顶层全部 + 二级里 ≥300 支的），未点名=0`；
  `导出提交 e805e6f：3141 个文件 / 141M，剪掉 532 条，死链 0，旧名残留 0，绝对路径 0`；
  `包内自洽：入口脚本按 glob 找凭据的引用共核对 1 条（核对数为 0 时这一条是空的，别念成绿）`；
  `随包凭据内容判定：FAIL 行共 1，其中未声明的红 0（白名单只允许 '^[ ]*FAIL C5c'）`；
  `-> /d/Xilinx/Prj/pro/final_submission（3142 个文件，与 MANIFEST 的计数一致）`。
  独立复量（不信导出器自己）：`find -type f`=**3142**（=声明的 3141 + MANIFEST 自己）、`du -sh`=**141M**、
  `board/vivado_system`=**315** / `board/vitis`=**2128**，与 MANIFEST 那一行现算出来的两个数逐字相同。
  墙钟：`tmpsub` 那棵树 18:14 建、18:16 已在长件，MANIFEST 盖章 **18:25:43** ⇒ 这一跑约 **11 分钟**。
- **搬运与"没删旧货"**：副本里那一份是 `4d398a3`/15:00 的旧包（699 支 / 14M），整目录移到
  `Prj/pro/pkg_archive/final_submission_4d398a3_1500` 留档；新包 `cp -a` 进去，两边 `find -type f` 各 **3142**、
  `MANIFEST.txt` `diff -q` 为空。（`Prj/pro/final_submission` 里被覆盖掉的 `cfad421` 那一版是**导出器自己的输出目录**，
  按脚本设计"新包落盘 = 覆盖旧包"，源与提交都在 git 里可重出，不再另存一份 141 MB。）
- **另一句超射程的话（`Prj/pro/sync_bundle.sh:111`，git 之外的件）**：判据 7 打印的是
  「副本里没有 `vivado_system/` 与 `vitis/`（工程本体只在仓库与 GitHub）」，可它真正 `test -e` 的只有**副本根**那两层
  ——而现在交付包 `final_submission/board/` 里就带着这两棵。话本身不算错，**念起来会变成假话**。
  改口为「副本根下没有……（工程生成物不进仓库半）」，并补一行**只报数**的附带读数：
  `交付包里有 vivado_system=315 支 / vitis=2128 支（只报数——这一条不参与红绿）`（包的形状归仓库里导出器那几条判据管）。
  判据 7 本身不是空转：它守的是第 50 行 `git archive "$REF" | tar -x --exclude=vivado_system --exclude=vitis` 那个 exclude——
  `main` 确实跟踪这两棵（`git ls-tree -r main` 里 **2443** 支），把 exclude 删掉它们就会从根下长出来，而第 1 步的
  `rm -rf` 只在这一次展开之前起作用。同步重跑读数：`判据1 仓库半文件数=1219（= main 非厂商 1133 + all 叠加 83 + 本地尺子 3）OK`、
  七条全 OK、`RESULT=PASS`；逐件对账 `Prj/pro/r128_bundle_reconcile.mjs` 读 `判=1133 缺=0 内容不同=0 多余=86`。
- **包里的本机痕迹复核（人读一遍，不只看判据报 0）**：drive-letter 形状在**手写层**（`report/skills/src/board/data/sim/build` 的
  `.md/.sh/.tcl/.ps1/.mjs/.py`，剪掉 `report/log`、`build/reports`、`build/evidence`、`board/measured`、`board/output`、`board/compare`
  这几层证据件）真人读到 **7 条**，逐条归类：`board/signoff.md:45`（用户原话，一字不动）、`src/host/make_sd_video.mjs:8`
  用法行的 `--in D:/path/a.mp4 --out E:` 是**占位符**、`skills/_meta/check-selftest.mjs:35` 与
  `build/checks/check_repo_hygiene.sh:318` 是 abs-fixture 检查器自带的**反例内容**（同行已写明"与本机无关"）、
  `data/generated/gen_inputs.mjs:18` 写 `C:/Users/<用户>/AppData/…`（占位）、`build/tcl/crit_path.tcl:18`
  说的是"另一台机器、另一个工程"的历史、`build/make_submission.sh:882` 是判据在描述自己的射程
  ⇒ 没有一条是"在这台机器上可照敲"的路径。用户名 `wenqu` 在包里剩 **2** 份，都在 `board/output/` 的工具回显里（证据件逐字保留）。
- **尺子全套重跑（在 `e805e6f` 的树上、导出之前）**：`deliver_spec_check` 判 18 项 跟踪文件=3576 **红=0 未测=0**；
  `line_cite_check`(D5) 硬错 **0**（锚点命中 282、候选 134、回声待人看 1）；`metric_recheck`(D6) 判 117 个数 **红 0**；
  `doc_currency_check` CURRENCY 干净（D4c 那一层的射程=交付文档 **25 份**参与判红、其余 **547** 份点名凭据 832 条只报数；
  同行写了"不随包/不入库"而放行的指路 8 条，只降级为报数、条数照念）；
  `doc_enc_check` 扫 302 份手写件全干净；`pipe_len_check` PASS（26 条现编用例）。本地两套文档两层尺子：
  ARCH 第一层 `判=3101 OK=3101`、第二层五档与改前**逐字相同**（`判=906 = 逐字 605 + 折竖线 0 + 记号齐 183 + 同行他条 67 + 可疑待读 51`）；
  LEARNING 第一层 `判=1092 OK=1092`、第二层 `判=188 … 可疑待读 0`。
  我担心的是"`make_submission.sh` 长了 29 行会把指着它的行号挪走"——量下来**没发生**（两套文档引它的那些条目仍在 ±6 行内）。
- **我自己造的一次现场污染（记下来是因为下次还会犯）**：把板子从"灰度锁上"恢复回演示默认时，我在命令文件里多打了一条
  `th 50`，而那一格**原本读的是 80**（`pipe 000000000` 之后的 `[CTRL]` 回显 `sel=000 thr=80`）。
  立刻补发 `th 80`，回显 `AXI_GPIO=0x000E5000 sel=000 thr=80 src=0 zoom=1 pub=1 bilin=1 osd=1` ⇒ 净变化为零。
  规矩：**"恢复默认"只准发我确定改过的那几格**；不确定的格先走一条读态命令量，别顺手写一整组"我以为的默认"。
- **眼睛判据那一格现在的状态**：`pipe` 已回 `000000000`、`src auto`、`th 80`，所以"右半是否变黑白、左半仍彩色"这一问
  要么下次现场再钉一次（`pipe 100000000` 钉住、`pipe 000000000` 复原，两条串口命令），要么就此作废不写进交付。
  板侧其余读数仍是 14:21–14:35 那一套（`board_verify --geom --battery --round=r128` PASS、ping 3/3、
  bit `cd04907e1369` / xsa `934ebdbaa13b` / elf `57fa442a7eaf`）。
