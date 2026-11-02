
## #169–#174（2026-09-30 13:3x，r94 第三轮只读巡检：AXI 写口 / 冻结导出链 / 仲裁快照）

第三只见没扫过的面（`src/rtl/axi/`、`src/rtl/video|util/`、`build/freeze_evidence.sh` 与导出器）。
**六条都不在账本里**。两条高severity是"能让凭据失真"与"abort 之后整帧错位"，四条中低是导出链与读数口径。
本轮只记账 + 给配方，两条脚本洞（#172/#173）与 #169 属于"改脚本不用重跑构建"，排在 r94 门禁落盘之后动；
#170/#171 是 RTL 设计缺陷，要单独一轮"先加能红的台架再改"（本项目规矩）。

- **#169【高，凭据】`build/sim/run_one.sh` 在编译**之前**就写 `prov.txt`，而 `run.log` 只在跑到时才截断。**
  于是"xvlog/xelab 失败"这一支（`:49/:52` 直接 exit）留下的是**新树的 `rtl_md5` + 上一跑的正文**；
  `build/tb98_report.sh:22-26` 会把这对新指纹盖到旧正文上，`build/freeze_evidence.sh:32` 那条
  "报告必须与当前树同一次跑"的门禁②就此形同虚设。
  配方（可当场证伪）：一次绿跑之后随便改一个 `src/rtl/*.v` 再**故意制造一次编译失败**，
  然后跑 `bash build/tb98_report.sh`，看头两枚 md5 变了而正文与旧报告逐字相同 ⇒ 中。
  日常自查一行：`stat -c '%Y %n' /tmp/kx/<tb>.run/prov.txt /tmp/kx/<tb>.run/run.log`，**prov 比 run.log 新就是脏**。
  修法：失败分支里删掉刚写的 `prov.txt`（宁可"没凭据"也不要"错凭据"），并在 `tb98_report.sh` 里
  加一条"prov 比 run.log 新 ⇒ 拒绝出报告"的第二把锁。
- **#170【高，设计】`axi_frame_writer_gated.v` abort 之后，在途的读拍会串进下一帧。**
  `:119-122` abort 清 `outstanding/r_pix/sk_*`，但 `:70` 的 `m_axi_rready = active && !sk_full` 随 `active` 掉 0
  ⇒ 最多 `4×16` 拍已被 HP0 接收的数据滞留在接口里；`:107-118` 重启时用**同一个 ARID**（`pl_video_top.v:654`）
  重新发 AR，旧尾巴先到 ⇒ 新帧从 `r_pix=0` 起被旧数据写入（画面上是整帧平移 + 顶部花），
  而旧那一拍的 `RLAST` 会扣掉一个**从未起过**的突发 ⇒ `outstanding` 从此永久失配。
  abort 不是理论态：`copy_overrun` 会触发它（`:422-426`），`abort_tgl` 的存在本身就是证据。
  配方：模块级台架收到约 10 拍时把 abort 拉高一拍（`rvalid` 继续给），再拉 `copy_start`，
  比对 `fb_wr_addr==0` 那一拍的 64 bit 与内存模型第 0 字。期望：改前红（拿到旧尾巴），改后绿。
  改法方向（待量过再定）：abort 时不许 `rready` 直接掉 0，而是**排空到 RLAST** 再让 `active` 掉，
  或重启前先把 `outstanding` 与 `r_pix` 一起对齐到一个"接口空闲"的状态。
- **#171【中，设计】abort 清"帧已就绪"那一位的路径不可达。**
  `pl_video_top.v:500-501` 的 else-if 链里 `frame_ready` 排在 `copy_abort_pix` **前面**，而 `frame_commit_lock.v:136`
  只置 1、只有异步复位清零 ⇒ 链路活着的时候 `:501` 永远轮不到 ⇒ abort 之后那张撕裂帧照样显示，
  `status` 里的 `eth_ready`（`:1055`/`:1010`）也继续读 1（上位机会以为换帧成功了）。
  配方：台架里 `frame_ready=1` 后打一次 abort，等 5 个像素拍断言 `eth_has_frame==0`；现树读到 1。
- **#172【中，交付】冻结件里那份逐列原始读数**进不了 git：`freeze_evidence.sh:53` 产的是
  `r${NN}_tb_v98_run.log`，被 `.gitignore` 的 `*.log` 挡掉（`:58` 的形状判据 `c2_shape.txt` 全靠它）。
  实测 `build/evidence_r{63c,64_rejected,74,75,78wip}/*.log` 都在盘上、`git ls-files` 数为 0。
  更糟的是 `make_submission.sh:483` 把 `*.log` 写进了死链**免检名单** ⇒ 自检恒绿。
  与今天刚撞的 `build/r94_flash.log` 同族，区别是它长在**每轮都会跑的冻结脚本里** ⇒ 每轮复发。
  配方：`git check-ignore -v build/evidence_r75/r75_tb_v98_run.log` 命中 `.gitignore` 即中。
  改法：冻结产物一律 `.txt`（或 `runlog.txt`），并把 `*.log` 从导出器免检名单里去掉、改成"点名要求存在就得存在"。
- **#173【中，交付】导出器那条"被交付文档点名 ⇒ 保留"是死规则。**
  `make_submission.sh:124-131` 对被点名的 `build/evidence_rNN/` 写一行"保留（交付文档点名要它）"进 `_pruned.txt`，
  但 `:263-266` 无条件 prune 所有 `build/evidence_*` ⇒ 目录还是被整删，包里的 `_pruned.txt` 留着那行**假的保留声明**。
  配方：`--dry` 之后在临时包里同时看 `grep -c '保留（交付文档点名' _pruned.txt`（>0）与
  `find . -maxdepth 2 -type d -name 'evidence_*'`（空）⇒ 两条同时成立就是自相矛盾。
- **#174【低，读数口径】`why_ps` 不是判决快照。** `src_arb.v:62` 每拍跟输入刷新，而 `owner_eth` 只在
  `both_idle`（`:69`）才换 ⇒ 拷贝期间 `eth_live` 翻转时，屏上"为什么 PS 拿着"会跟着改，可主人一次都没换。
  `:32-38` 的注释与 #55 定的口径不符。配方：台架里 `row_busy=1` 冻住 owner，再翻 `eth_live`，看 `why_ps[1]` 是否变。

## #164 收口（2026-09-30 13:3x，r94 当场落地）：门禁在报告缺席时不再念 PASS，改念 n/a 并把范围念出来

- **机理复核（不是猜的）**：`build/gates.sh` 的 `pick()` 只给 T/U/P/R 四份做了"缺文件就 FATAL"，
  `methodology.rpt` 与 `cdc.rpt` **不在名单里**；而 `rows()`/`grep -ac` 都带着 `2>/dev/null`，
  空结果经 `${crit:-0}` 变成**合法的 0** ⇒ 那两项**在文件缺席时报 PASS**。
- **改前对照（可复现）**：`build/gates_probe_164b/sub/` 只放那四份报告，跑 `bash build/gates.sh 那个目录` ⇒
  `build/r94_gates164_before.txt` 第 14/16 行：`methodology CRIT 0 … PASS`、`cdc.rpt Critical 行 0 … PASS`。
- **改后同一目录**：`build/r94_gates164_after.txt` 打的是两行 `n/a … 这一项没门禁（#164：空集合不是通过）`，
  结尾因 NNA≠0 变成 `GATES: PARTIAL`，`freeze_evidence.sh` 那句 grep 自然拒绝冻结这一版。
- **负对照（不许把好行为改坏）**：`bash build/gates.sh`（默认目录 = `build/`，两份报告都在）⇒
  `build/r94_gates164_normal.txt` 仍然按数判：`methodology CRIT 0 PASS`、`cdc.rpt Critical 行 2 … PASS`，
  判定项数不变（20 项）。**阈值一个都没动**，动的只是"没数据时不许冒充有数据"。
- 顺带记一条**同族的既有行为**（不是这轮改的）：`pick()` 的回落是 `$D/../<file>`，
  所以判一份历史冻结件时，如果它自己缺某份报告，会**借上层目录里那一份实时文件**来判 ——
  数是真的，出处不是那一套。这轮加的两行 n/a 恰好把这种借用**说出来了**（消息里带的是回落后的路径）。
