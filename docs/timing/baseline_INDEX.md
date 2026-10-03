# B1 基线工件索引 — r114 树（未修改的树 = 最便宜的对照）

跑探针的时间：2026-10-03 22:20–22:22（件里每份都有 `| Date :` 行）。
被打开的设计：`vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp`（正式构建的已布线 DCP；
路径写在探针脚本 `build/tcl/r115_baseline_probe.tcl:12`，件内 `Floorplan: checkpoint_system_top_routed` 与
`Design State : Routed / Fully Routed` 两行互相印证），**只读出报告，没有改任何东西**。
设计身份（每份报告自己的头部，不是我抄的）：Device `xc7z020clg484-2` / Speed File `-2 PRODUCTION 1.12 2019-11-22` / Tool `Vivado v.2025.2.1 (win64) Build 6403652`。

树指纹（`bash build/rtl_fingerprint.sh`，fpver=norm1 对 CR 不敏感）：
`files=80 top=56c269602e18 rtl=3969247aaf7f`
同一棵树上的 `system_top_opt.dcp` md5 前 12 位 = **`4c895816c4f2`**（快车道两滚的输入，也是噪声标定的输入）。

| 工件（`build/evidence/r115_base/`） | MD5（整份文件） | producing command（取自件内 `| Command :` 行） |
| --- | --- | --- |
| `timing_summary.txt` | ecb8b2fbc1f63aa7f2a3b60853dd9b92 | `report_timing_summary -quiet` |
| `timing_summary_setup.txt` | 8e455009f4e7fb6456f51f04e486705e | `report_timing_summary -setup` |
| `timing_summary_hold.txt` | 66a8089d2ee972bc46b1f6d03043636b | `report_timing_summary -hold` |
| `timing_summary_verbose.txt` | d43135520fd351d7c930a7fd868ab700 | `report_timing_summary -verbose` |
| `check_timing_verbose.txt` | 550b45d95449e31ac6465cd0f7fc68be | `check_timing -verbose`（**I/O 债务的权威名单就这一份**） |
| `check_timing.txt` ⚠ | ff0582cd7cd3e1a6165a59ef6889ef37 | 件内 Command 行写的是 **`report_timing`**，不是 `check_timing` ⇒ **文件名与内容不符**（工具侧的账，见 debt_ledger §6 与 ISSUES） |
| `setup_nworst.txt` | 227c29b99e085b08419e2081d996a36c | `report_timing -nworst … -unique_pins`（setup） |
| `hold_nworst.txt` | 91e7c265d4c206c53e8b4805097c46fc | 同上（hold） |
| `methodology.txt` | 795ae11a98e6b20e0d7f558022d3af4e | `report_methodology` |
| `high_fanout.txt` | 64b8b91fa3e8ccf5951f7244dd467136 | `report_high_fanout_nets` |
| `clock_interaction.txt` | d64ac3556b058584f5d2d5891065c0d8 | `report_clock_interaction` |
| `clock_networks.txt` | 2b840bc2aa629c3bd34d29f75013d652 | `report_clock_networks` |
| `clock_utilization.txt` | 7cb463018a2a8a4551c94298eb12cc48 | `report_clock_utilization` |
| `exceptions.txt` | b4ea86f34890783dea51781f117f55a2 | `report_exceptions` |
| `route_status.txt` | a6d3822c92d7634e4e5a77362a9f34e4 | `report_route_status` |
| `utilization.txt` | 90f100b697588f26d41736a002e9eb0d | `report_utilization` |
| `da_timing.txt` | 40be176911844bde97b7e00ad193d529 | `report_design_analysis -timing` |
| `da_levels.txt` | c0a0e65865716a4a9891bbe4f9878e03 | `report_design_analysis -logic_level_distribution` |
| `da_routes.txt` | 07546b183ffb14bcff0dd17f02c0a3a2 | `report_design_analysis -routes` |
| `da_routed_vs_est.txt` | cbd67e1d8d1f32fcc9fe3e3ad5d17f86 | `report_design_analysis -routed_vs_estimated` |
| `da_qor.txt` | 0076ca20f218c0e72468fac4dd4c28fd | `report_design_analysis -qor_summary` |
| `da_congestion.txt` | fea9b13dba14a7c250b5b69d7fb8387b | `report_design_analysis -congestion` |
| `da_complexity.txt` | cfde5a326537452287f55e92b47e8233 | `report_design_analysis -complexity` |

## B2/B3 名册（基线工件，此后所有差值只许引用这一份）

`docs/timing/roster_baseline.tsv` — md5 **`039c16e373e562016b2edbea02925efc`**，2026-10-03 22:45:09 由
`python build/r115_roster_build.py build/evidence/r115_base/timing_summary.txt build/evidence/r115_base/check_timing_verbose.txt docs/timing/roster_baseline.tsv baseline` 生成（8 行 = 8 个时钟域）。
判定器的对照端是它，**不是"我记得基线是多少"**；也不许把"当前值"换成刚生成的集合（B3）。

- 尺子自己的测试：`python build/r115_roster_build.py --self` → **5 条对照全 PASS、SELFRESULT GREEN**
  （绿对照 / 注入 hold 变差 / 注入 I/O 债变大 / 丢一个时钟 / both-NA 计数；后四条必须能红）。
- 附加列 `intra_endpoint_total` 是 §4 D 打分用的端点数，放在 13 列**之后**，B2 点名的 13 个列名与顺序没动。

## B4 噪声底（这个项目只做一次）

`/tmp/kx/r115_noise/noise.txt`（驱动日志 `build/evidence/r115_noise_cal_console.txt`）：
同一份 `4c895816c4f2` 的 `system_top_opt.dcp`，mode=none 连滚两遍（n1 22:31→22:38 = 6.4 min；n2 22:38→22:43），
五个读数 **N1 两滚都完成 / N2 输入一致 / N3 头条四个数逐位相等 / N4 最差路径身份相等** 全绿 ⇒

```
NOISE-SUMMARY noise_ns=0.000 cmp=equal identity=equal dcp_md5=4c895816c4f2 fp=…rtl=3969247aaf7f
```

N5 与正式构建对表（roll=[0.739 0.052 0 0] vs official_r114=[0.739 0.052 0 0]）**只念不判**——那是跨构建，H3 不许拿它当收益。
之后任何"收益"必须**严格大于 0.000 ns** 才许叫收益；这条地板只对"同一份 DCP 的快车道滚"成立，
换 DCP（例如重新综合）就重新变成跨构建比较。
