# r113 采纳清单（链子在飞，起飞 11:37，本文只写"到哪一步做什么"，数字留空等件）

身份（构建前钉的，`build/evidence/r113_precompile_fp.txt`）：fpver=norm1 files=80 top=56c269602e18 **rtl=42d47b9f771d**
改的东西（三件一起，一轮只付一次台架的钱）：
1. **#256 的根因修复**：`key_debounce` 的 `key_stable`/`key_sync0`/`key_sync1`/`key_prev` 加**声明初值**
   （这一域没有复位 ⇒ 复位分支是死支 ⇒ 上电值只有声明初值能带进位流 INIT）。
2. 刀 A（r112 的上电武装门）：留着，但**不许再写成"上电那一度"的解药**（#256 已证它没打中）。
3. 刀 B（r112 的 icmp_tx 校验和累加器 32→20）：留着（#255 记的取舍："同族抓手成立、余量未抬"）。

## 六步（顺序不许换）
- [ ] **① 上电值对账（链子已把它放在构建后第一步）**——`build/evidence/r113_powup_init_check.txt`
      五条 W1..W5 必须全 GREEN；任一 RED ⇒ 链子已自断，**不许采纳、不许上板**（这一版没修上，
      后面 100 分钟的台架只是给一版"修没修都一样"的位流做公证）。
- [ ] **② 快车道**：`build/r113_lane_after.txt` 的 `LANE-SUMMARY ran=31/31`，绿 31、红 0、挡 0。
      已知例外：C5c 那条既存红不在车道里，在门禁。
- [ ] **③ 顶层台架 + rim**：`build/tb_v98_report.txt`、`build/tb_edge_rim_r113.txt`；
      收益口径 = 那条 0.445 ns / 6×CARRY4 的族自己动没动（对照 `build/evidence/r112_setup_paths_baseline.rpt`），
      全局 WNS 的绝对差**不算收益也不算损失**（rule 35）。
- [ ] **④ 门禁两跑逐字节一致** → `build/r113_gates.txt`。预期：C5c（声明过的既存红）+
      `doc_currency`/`metric_recheck`（改口之前必然红）⇒ 改口之后必须回到只剩 C5c。
- [ ] **⑤ 数字与凭据改口**：`node build/rotate_from_metric.mjs --apply` +
      预跑（12:49，`--check`，未写盘）：机械那半**可改 33 条 / 拒 9 条**，读到的就是 r113 的报告
      （WNS 0.445、端点 51135、LUT 14154/26.61 %、FF 8188/7.7 %、Dynamic 2.213 W）；
      那 9 条被拒的是首页四行的复合物理形状（`认不出的红行形状`），由手写那 35 条覆盖
      （`node build/r113_rotate_docs.mjs --check` 已验：35 条各命中 1 次、拒 0）。**两条都要在门禁之后跑**。
      `node build/r113_rotate_docs.mjs --apply`（这支是 r112 那把的副本，已为 r113 改好身份句；再补两条规则：
      门禁条数那句、刷板时间那句），然后 `metric_recheck`/`doc_currency`/`line_cite_check` 红 0。
      ⚠ 改口完必须**写回盘上那份 `rNN_gates.txt` 再跑一次门禁**才收敛（#242/D1c 那一课）。
      ⚠ 同一笔还要做两件首页的事（做了就必须同步改 `r113_rotate_docs.mjs` 里对应规则，否则 `--check` 会拒）：
      (a) 首页"逐时钟 setup 余量"那一行现在**只念 setup**，采纳时要补四域 **WHS 与相对余量**
          （数据源 `build/evidence/r113_after_roster.txt`，八对读数：eth_rxc 0.445/0.050、clk_fpga_0 1.135/0.056、
          clkout0_1 4.467/0.059、sys_clk 14.463/0.133），并把"绝对 WNS 差不算收益"那句留在旁边；
      (b) 本轮新落的四把尺子要在 README 的"怎么量的"段点名：名册差分 `build/timing_roster_diff.sh`（D1..D6）、
          I/O 欠账 `build/check_io_timing_coverage.py`（I1..I9，其中 I7/I3 仍红）、
          `ASYNC_REG` 扫描 `build/scan_async_reg_coverage.py`（A2 仍红）、
          hold 同口径体检 `build/uncertainty_uniform_ab.sh`（真件还没跑，念"没测过"不许念"违例"）。
- [ ] **⑥ 采纳笔（含 bit/xsa）→ 三步 JTAG 刷板 → `board_verify --geom --battery --round=r113` → 眼睛判据 E6**
      （E6 = 冷上电、不碰任何键，`ROT:` 必须显示 **0**；这一条是你的眼睛，我念不了）。
      之后：试冻结 → `make_submission.sh`（按盘上文件数验收，不读它的 stdout）→ push。
- [ ] **⑦ 排在链子后面的两支全局实验**（`build/r113_after_chain_experiments.sh`，13:12 起飞等待，
      等的是"出口件 `build/r113_gates.txt` 出现" **且**"没有 xsim/vivado 在飞"两条同时成立；
      理由与活着的证据写在脚本头部）：
      1) `build/r113_roster_refanout.sh` → `build/evidence/r113_roster_diff_rf.txt`：
         把 D6 那根**工具红**换成有凭据的读数（根因见 #263：本工具没有 `report_design_analysis -fanout` 模式）。
      2) `build/r114_replication_ab.sh`（旧路径 `build/r114_maxfanout_ab.sh` 现在是转接，因为排期脚本按旧名调用）
         → `build/evidence/r114_mf/verdict.txt`：
         同一份 `opt.dcp` 滚两遍，两滚都 `place → phys_opt → route`，**唯一变量**是 B 的 phys_opt 多带
         `-force_replication_on_nets {那几根广播网}`（实测：`set_max_fanout` 在本工具不存在，#264）。
         判据顺序是"先证机制能动再看收益"：V2b 复制对象数（`_replica`）必须 B>A、V2c 名册里至少一根网的扇出下降
         （两个不同来源），之后才由 V3 目标族收益 + V4 逐时钟名册差分全绿 + V5 资源代价决定
         `ADOPT_CANDIDATE` / `DECLINE` / `MECHANISM_INERT`。
      这两支**不阻塞 ⑥**：⑥ 采纳的是已经量完的 r113；⑦ 产出的是 r114 的下一刀该不该切扇出复制。

## 这一轮还欠的（别当成已完成）
- `pl_demo_top` 那棵树里 `snap_cross.hb_gone` 还是"想要 1 而没初值"（#257 第 2 条）⇒ r114 补一颗声明初值；
  当前位流不受影响（system_top 那棵树里它的复位是活的）。
- I/O 约束欠账已点名、判据 I3 现在是红的（#259：TMDS/LED/MDIO 对外零声明）⇒ r114 补约束或写明理由。
- `check_powup_init.sh` / `scan_dead_reset_init.py` / `check_io_timing_coverage.py` / 名册三把
  **都还没进门禁**：接进去会改"门禁 N 项"那四处句子的条数，必须同一笔改（#242/D1c）。
- 角度机读口（#185）：板上 `ROT:` 仍只能靠眼睛，`rot auto 0` ≠ 0°。
