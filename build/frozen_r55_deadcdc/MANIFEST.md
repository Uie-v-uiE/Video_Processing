# r55 冻结集 —— 2026-09-25 05:5x · 源码级清理版（ISSUES #64 死代码删除）· build #36

这一版**没有新功能**：只做一件删代码的事 —— 把 #64 审计出来的"16 位 eth 计数器按单 bit 规矩做两级
触发器同步"那段死逻辑删干净（`pl_video_top` 两个入口 + 4 个寄存器 + `system_top`/`pl_demo_top` 的连线）。
删的动机不是省资源（下面门禁那一节会看到资源数字一位没动，这本身就是"它确实是死代码"的证据），
而是**不给下一位读者留一根"看起来像同步器、其实是假的"的线** —— 这类线本项目付过两次学费（#57 位宽、#61 多驱动）。

## 成套三件（md5 前 8 位，凭 `md5sum -c` 可核）

| 文件 | md5 | 说明 |
|---|---|---|
| `system.bit` | **1b5eff62** | build #36（`r55_build36.log`，`SYSTEM BUILD DONE`，`grep -c "^ERROR"` = 0） |
| `system.xsa` | **6d9cc73d** | 与 bit 同一次导出（RTL 动过 ⇒ 与 r54 的 662c0d5f 不同，符合预期） |
| `ps_app.elf` | **812790ec** | **与 r54 逐字节相同**：这一版 PS 侧零改动，故意沿用，便于把差异全部归到 PL |

⚠ 后台任务通知把 build #36 报成 "exit code 1" —— 那是 `grep -c` 找不到匹配时的返回码，不是构建失败。
判据看日志末行 `SYSTEM BUILD DONE` 与 `^ERROR` 计数（本仓库的老坑，见 `skill/`）。

## 门禁十四项：ALL PASS（凭据 `gates_r55.txt`，当场跑）

与 r54（`../frozen_r54_readback/gates_r54b.txt`）逐项对照，**只有一行变了**：

| 项 | r54 (#35) | r55 (#36) | 阈值 | 判 |
|---|---|---|---|---|
| WNS (ns) | 0.235 | **0.235** | ≥ 0 | PASS |
| 失败 setup 端点 | 0 | 0 | = 0 | PASS |
| WHS (ns) | 0.012 | **0.012** | ≥ 0 | PASS |
| 失败 hold 端点 | 0 | 0 | = 0 | PASS |
| BRAM (tile/%) | 92/65.71 | 92/65.71 | ≤ 97 | PASS |
| Slice LUT / 占比 | 11116/20.89 | 11116/20.89 | ≤ 98 | PASS |
| Slice 寄存器 | 8430 | 8430 | 记录用 | PASS |
| Dynamic (W) | 2.182 | 2.182 | 与前次同量级 | PASS |
| methodology CRIT | 0 | 0 | = 0 | PASS |
| 布线错误网线 | 0 | 0 | = 0 | PASS |
| cdc.rpt Critical 行 | 3 | 3 | 基线配对不新增 | PASS |
| 端口宽度警告 8-689 | 0 | 0 | = 0 | PASS |
| 多驱动 net 8-685x | 0 | 0 | = 0 | PASS |
| 顶层接线逐实例比对 | width_compared=**546** | width_compared=**544**，violations=0 | = 0 | PASS |

**资源与两端裕量一位没动，这是"删对了"的证据而不是"没删"**：综合器早就把那 4 个寄存器连同它们的输入
当无消费者逻辑剪掉了，所以网表本来就不含它们 —— 变的只有**源码**和**顶层接线**（第 14 项的
`width_compared` 少了 2 条：正是被删的两个入口的连接）。这也是 #64 值得删的理由：
门表面板上看不见的东西，不代表读源码的人不会被它骗。

顺带一条 CDC 的账（不判红所以必须手写下来）：门禁打印里"基线里有而本版没有 `eth_rxc>clk_fpga_0`"
是**已结案的旧账**（基线文件 5~13 行，U14），r55 后该行端点数仍是 271（`cdc.rpt` 第 21 行），
少的那 1 个 unsafe 是 #24 删的、不是这次删的。而另一行"同配对端点数增长 `clk_fpga_0>clkout0_1`(17→71)"
这次去查了，**查出新问题**：见 `report/ISSUES.md` #65（两个 unsafe 端点是 CDC-11 发射扇出，
V8-5 那条时延快照把 `bus_tog`/`hb_tog` 接了同一根线）。修法在 r56，凭据 `cdc_who_r55_console.txt`
与 `cdc_details.rpt`。**⇒ 这一版仍带着那 2 个 unsafe 端点上板**，功能侧无已知影响（见 #65 的"为什么值得修"）。

## 板级复验（凭据 `r55_board_verify_console.txt`，日志副本 `verify_0925_0549.txt`）

下载顺序与命令：`ps_jtag_boot.tcl` → `program_pl.tcl` → `ps_app_reload.tcl`（三份日志就在本目录）。

1. **读回口**：`lane30 src_state` = `{mode:AUTO, eth_live:0, why_no_stream:1, why:"没有流"}`、
   `lane23 zoom` = `{alive:1, zman:0, zsel:4, zcode:3, inv_scale:300, x100_actual:85.3, verdict:OK}`、
   `lat.osd_ms_matches_tot = true`、`drop_words = 0`。
2. **仲裁八条全绿**（`arb_handover_r55.json`）：V1 基线归 PS 0/5、V2 接管 **357 ms**、
   V3 稳占段 **29/29 零翻转**、V4 停流交回 **227 ms**、V5 交回后 0/39 不回跳、V6 再推 **238 ms** 可逆、
   V0 采样密度 101/117、V7 交回段 39 个样本原因位不可用 **0** 个。
3. **命令电池 51/51 PASS**（`battery_r55.txt`），末态与初态逐字段相同
   （`en=00 thr=80 src=1 zoom=1 bilin=1 zsel=4 zman=0 gm=0.00`）—— 含 8 条 `temp` 行（43~50）。
4. 测完 SD 回放已恢复到测前状态（PLAY），板子当前 = 无推流 + SD 在放。

## 还没做完的（诚实清单）

- 眼睛判据三条（停流后画面真的在动 / 并发不闪不抢 / 长按四态轮转且图卡会动）—— 见 `board/README.md` 行 12~20。
- ISSUES #65 的修法在 **r56**（一个 `lat_hb_tog` 触发器），以及把"unsafe 端点增长即判红"补进门禁第 6 项。
- V8-4b（#44）仍在等用户对演示语义拍板；#43 的"屏上画原因位"是**故意不做**的（PLAN_V8_SPEC §7f 末）。
