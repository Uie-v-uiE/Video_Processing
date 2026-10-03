# r114 批次计划（全局口径：每一刀都带自己的尺子与代价面，一轮只付一次台架的钱）

写在前面：这份清单是"别只追最差那条"的执行版。每一刀都写四件事——
① 动什么；② 谁来判（尺子 + **改前必须红**的凭据）；③ 代价面（逐时钟名册差分 D1..D6，不看头条 WNS 的绝对差）；
④ 走哪条车道（快车道 = 同一份 `opt.dcp` 重跑 place/route ≈ 7–9 分钟/滚；正式一轮 = 构建 + 31 支车道 + 顶层台架 70–128 分钟）。

## 一、先量的两刀（不动 RTL，只动约束/属性；同一笔构建）

| # | 动什么 | 谁来判（改前必须红） | 代价面 | 车道 |
|---|---|---|---|---|
| 1 | `dc_fifo` 四颗格雷码捕获寄存器打 `ASYNC_REG`（`rgray_s0/s1`、`wgray_s0/s1`，#262） | `build/scan_async_reg_coverage.py`：现在 A2 RED，只点这两处（件 `build/evidence/r113_async_reg_scan.txt`）；打完必须 A2 GREEN 且 A1/A5 计数与名字钉住 | 属性不改网表，但要念 `report_methodology` 的 TIMING-10 计数（当前 1）与名册差分 | 正式一轮（要综合） |
| 2 | 异步组间四条跨域路补 `set_max_delay -datapath_only`（#266：`dc_fifo`、`ddr_bank_commit`、`frame_commit_lock`、`effect_ctrl`） | 尺子**还没写**（写时按 `build/` 命名规矩起，别在此文件提前点名不存在的路径）；判据必须"条数地板 ≥4 + 两维同现（ASYNC_REG 与 max_delay）"，且自带能红的对照 | 组排除下的路径不进 WNS ⇒ **"WNS 没动"是预期不是证据**（rule 35 反面）；要看的是名册里别的域没被挤 | 与 1 同笔构建 |

## 二、I/O 约束这一捆（#259/#267/#268，三个来源三种单位，先对口径再写数）

1. **先问工具**：`check_timing -verbose` 出权威端口名单，把三个现数对到同一套名字上——
   `check_timing` 念 5 输入 + 6 输出（HIGH）、`check_io_timing_coverage.py` 念 2/7 个端口（= 5/12 引脚）、
   `report_methodology` 念 TIMING-18 = 7 条。谁也不许替谁解释（#267/#268）。
2. 然后按 `report/TIMING_GLOBAL.md` 第 4b 节的分组配方落约束：TMDS 一路先量面板/走线窗再写 `set_output_delay`，
   数值**必须**有出处（手册或实测），写不出出处就在 XDC 注释里标成估计并给区间；LED/MDIO 各一条**带理由**的声明。
3. 判据收口口径：**I3 与 I7 都要由 RED 转 GREEN，且有 -verbose 名单支撑**；只改绿 I3、把 I7 的期望值改掉 = 假收口。

## 三、物理那一刀（先做单变量 A/B，再谈进不进正式轮）

* 入口 `build/r114_replication_ab.sh`（旧名 `r114_maxfanout_ab.sh` 已是转接）：同一份 `opt.dcp` 滚两遍，
  两遍都 `place → phys_opt → route`，**唯一变量**是 B 多带 `phys_opt_design -force_replication_on_nets`。
* 判据顺序已改成"先证机制能动再谈收益"：V2b `_replica` 对象数 B>A、V2c 名册里至少一根网扇出下降（两个不同来源），
  任一红 ⇒ `MECHANISM_INERT`（这一刀没打到东西），**不许**写成"时序收益不成立"；机制绿后才看 V3 目标族 / V4 名册差分 / V5 资源。
* 尺子自带 `--self` 三条对照，实测 3/3（件 `build/evidence/r114_mf/` 与 `verdict.txt`，跑完回填）。
* ⚠ 杠杆的名字是量出来的：`set_max_fanout` 在本工具不存在（#264）；`MAX_FANOUT` **属性**那条路还没验过（要开设计 `list_property`），
  所以不许提前写成"已按官方 MAX_FANOUT 做"。

## 四、结构那一刀（fo=305 的 CE 广播，#187 尾）

先配能红的尺子再落刀：目标是 `rok4[51]_i_1_n_0`（fo=305，route 84 %）这根广播的扇出**读数离开 305**，
并同时念 `route_status`/`utilization` 与其余三域（名册差分）。上一版这把"没真降"过（#238），所以判据必须是**计数**而不是"看起来好一些"。

## 五、还欠着的两小笔（同一轮顺手带走，各自带尺子）

* `pl_demo_top` 那棵树里 `snap_cross.hb_gone` 补声明初值（#257 第 2 条；尺子 `build/scan_dead_reset_init.py` 现在念 init_miss=1）。
* 角度机读口（#185）：`ROT:` 现在只能靠眼睛；方案在 `build/r113_angle_lane_plan.md`，落地后 E6 可自动化。

## 六、需要用户点头的一项（测量之后再决定，不是现在猜）

**hold 不确定度要不要给到全部时钟**。现状只 `eth_rxc` 有 `-hold 0.800`，其余三域裸数（#265），
所以四域 WHS 不可比；把同一条带给每个时钟的体检尺子已落地（`build/uncertainty_uniform_ab.sh`，六条判据、`--self` 7 条对照全过），
**但真件还没跑**。跑完若出现"三域翻负"，那是要不要做 hold fixing 的**新范围**，需要单独一次决定——
在那之前谁也不许把负数念成"板子 hold 坏了"（那只是同一悲观带下的 what-if，没重跑布线）。

## 七、纪律（这一轮不许破的）

* 一次构建带多刀，但每刀**各自的判据先红后绿**，红绿凭据都进 `build/evidence/`；
* 不改正在被后台实例执行的脚本（要改就复制新名字）；构建在飞时不动 `src/rtl`、`src/constraints`；
* 门禁项数一旦变（把上面任何尺子接进门禁），必须与"门禁 N 项"那四处句子**同一笔**改（#242/D1c）；
* 采纳笔要含 bit/xsa，刷板后跑 `board_verify --geom --battery --round=r114`，眼睛判据仍归用户。
