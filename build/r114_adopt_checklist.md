# r114 采纳清单（链子 18:43 起飞；数字留空，等件进来再填，不许先猜）

身份（构建前钉）：本轮只带两刀，都是**属性/初值级**——
① `dc_fifo` 四颗格雷码寄存器 `(* ASYNC_REG = "TRUE" *)`（#262）；
② `pl_demo_top` 树里 `snap_cross.hb_gone` 声明初值（#257 尾）。
**不进本轮**（口径与凭据在 `build/r114_batch_plan.md` §十二/§十三）：RGMII 窗那三份 XDC（#275/#282/#285）、
四条 `set_max_delay -datapath_only`（#276/#191）、复制驱动那一刀（#288：机制动了但 `eth_rxc/hold` 0.050→0.035 被名册差分判红）。

## 六步（顺序不许换）

- [ ] **① 两把静态尺子 pre/post + 网表侧探针**（链子已经把它们放在构建前后各一次）
      `build/evidence/r114_async_reg_{pre,post}.txt` 必须 `result=GREEN`（pairs=2 / missing=0 / ghosts=0 / edges=2）；
      `build/evidence/r114_dead_reset_{pre,post}.txt` 必须 `result=CLEAN`（init_miss_total=0）；
      `build/evidence/r114_async_netlist_pre_console.txt` 是**改前红**（`gray_ff=84 marked_true=0`、TIMING-10=1），
      post 那份必须念出 `marked_true` 离开 0、`METHROW check=TIMING-10` 的 count 离开 1。
      任一不成立 ⇒ 这一刀没打上，**不许采纳、不许上板**（后面 70–128 分钟的台架只是给一版"修没修都一样"的位流做公证）。
- [ ] **② 快车道 31 支**：`build/r114_lane_after.txt` 的 `LANE-SUMMARY ran=31/31`，绿 31、红 0、挡 0。
- [ ] **③ 顶层台架 + rim**：`build/tb_v98_report.txt`、`build/tb_edge_rim_r114.txt`。
      收益口径**不是**头条 WNS：这两刀的预期是"时序中性 + 结构账变干净"，
      所以判据是名册八对逐格差分（对照 `build/evidence/r114_before.txt` 与 `r113_setup_paths_baseline.rpt`）
      + 综合告警名册不新增类（`build/evidence/r114_synth_roster.txt`）。WNS 的绝对差既不算收益也不算损失（rule 35）。
      ⚠ **配对必须是同一把生成器**（#291 踩过）：B 侧要等 `xsim` 跑完再用 `build/tcl/probe_timing_roster.tcl`
      开 routed dcp 出 `build/evidence/r114_after_roster_rf.txt`，与 `build/evidence/r113_after_roster_rf.txt`
      （上板那版，同探针 + 同扇出名册）相减。**不许**拿 `roster_from_summary.sh` 那份只有 4 路钟的干净名册
      去减探针那份 8 路钟的名册——“少一路钟”会被数成代价（`D3 big_loss=8` 那份反例留在
      `build/evidence/r114_roster_diff_shape_mismatch_do_not_read_as_verdict.txt`）。
      `timing_roster_diff.sh` 现在自己会 REFUSE（`--self` 8/8），别绕过这道闸。
      0.445→0.739 是 `ASYNC_REG` 挪了放置的副产品（#290），不是这一刀的收益。
- [ ] **④ 门禁两跑逐字节一致** → `build/r114_gates.txt`（24 项，项数没变 ⇒ 不动"门禁 N 项"那四处句子）。
      预期：既存声明红 C5c + `doc_currency`/`metric_recheck` 在改口之前必然红 ⇒ 改口之后必须回到只剩 C5c。
- [ ] **⑤ 数字与凭据改口**：先 `node build/rotate_from_metric.mjs --check`（机械那半），
      ⚠ 资源三行**不用改**：r114 实测 LUT 14154 / FF 8188 / BRAM 95.5 与 r113 逐字相同（#292），
      要改的只有 WNS 0.445→0.739、WHS 0.050→0.052、位流身份、刷板时间、结温，以及下面四点。
      再手写那半——需要新建 `build/r114_rotate_docs.mjs`（`r113_rotate_docs.mjs` 的副本，改身份句 + 本轮数），
      `--check` 必须**每条命中 1、拒 0** 才 `--apply`。⚠ #270 那一课的口径：`--check` 只证明写下的规则都命中，
      不证明覆盖 ⇒ 拿"本轮变了哪些数"逐条反查文档里每一处。本轮已知必须动的四处：
      1) 首页身份句（中英各一份）+ `data/metrics.csv` 的 WNS/WHS/util/power/结温行；
      2) `report/timing_global.md` §4 表里 `TIMING-9 / TIMING-10` 那一行的读数（改前 1 / 1，件 `r113_methodology_baseline.rpt`）；
      3) **同一张表下面那行自闭合等式** `Checks found: 446 = 2+1+336+98+1+1+7`——
         加数与总数都要按新报告重算，等不上就是抄漏一类（这行最容易漏，它是**别人**的账）；
      4) §4 那句把 TIMING-10 归到"#256 这一域没复位"的解释——TIMING-10 说的是同步器少 `ASYNC_REG`，
         归因该指 #262；本轮把它修上了，句子要跟着改口（不许留着旧的因果）。
      改口完**写回盘上那份 `r114_gates.txt` 再跑一次门禁**才收敛（#242/D1c）。
- [ ] **⑥ 采纳笔（含 bit/xsa）→ 三步 JTAG 刷板 →
      `VP_XSDB="D:/Software/Vivado/2025.2.1/Vitis/bin/xsdb.bat" bash build/board_verify.sh --geom --battery --round=r114`
      → 眼睛判据**（归你）：这一版没有新功能，眼睛只判"无回归"三件事——
      (a) 冷上电不碰键 `ROT:` 显示 0（E6 复验）；(b) ETH 片源画面与 r113 一样干净、OSD 的 `bad`/`drop_words` 不涨；
      (c) 三个源切换与旋转照常。之后：试冻结 → `make_submission.sh`（按盘上文件数验收，不读它的 stdout）→ push。

## 七、排在链子后面的两笔（都不占构建，念法要老实）

* `build/uncertainty_uniform_ab.sh` 的**真件**还没跑（#265：只有 `eth_rxc` 有 `-hold 0.800`，四域 WHS 不可比）。
  跑完若出现"三域翻负"，那是 hold fixing 的**新范围**，需要单独决定；在那之前谁也不许把负数念成"板子 hold 坏了"。
* #194 捕获钟那一刀的设计、方向判据与否决条件已经写在 `build/r115_capture_clock_plan.md`
  （C1 回 BUFIO 预测仍差 ~0.9 ns、C2 走 MMCM 负相移才关得住 2.7 ns、C3 是不建窗的现状）。
