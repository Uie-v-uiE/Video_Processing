r53 冻结集 —— 2026-09-25 03:5x · V8-8 手动缩放（八档 + 自动/手动交接不瞬移）

这一版只做一件事：把缩放从"只会呼吸"变成"能钉住，也能还回去"。
PL 侧新增一条同步链上的 4 个位与一张八档表，PS 侧新增解析与回声，
**没有新增任何跨域配对**（新增的位并进 `effect_ctrl` 已有的那条 sel 链，§7a 第三条规矩）。

## 成套三件（md5 前 8 位）

| 文件 | md5 | 说明 |
|---|---|---|
| `system.bit` | **096f976d** | build #33（`r53_build33_out.txt`，`SYSTEM BUILD DONE`，0 ERROR） |
| `system.xsa` | **7e5b39da** | 与 bit 同一次导出 |
| `ps_app.elf` | **bd42a2d4** | 含 `[STAT]` 的 `zsel=`/`zman=` 与 `[ZOOM]` 的语义重叠提示（见 ISSUES #63） |

## 门禁十四项：ALL PASS（凭据 `gates_r53.txt`，当场跑）

| 项 | 数 | 阈值 | 判 |
|---|---|---|---|
| WNS | **+0.487 ns** | ≥0 | PASS |
| 失败 setup 端点 | 0（总端点 29403） | =0 | PASS |
| WHS | **+0.054 ns** | ≥0 | PASS |
| 失败 hold 端点 | 0 | =0 | PASS |
| BRAM | 92 tile / 65.71 % | ≤97 % | PASS |
| Slice LUT | 11059 / 20.79 % | ≤98 % | PASS |
| Slice 寄存器 | 8351 | 记录 | PASS |
| 动态功耗 | 2.182 W | 与前次同量级 | PASS |
| methodology CRITICAL WARNING | 0 | =0 | PASS |
| 布线错误网线 | 0 | =0 | PASS |
| cdc.rpt Critical 行 | 3（基线 4） | 配对不新增 | PASS |
| 端口宽度 8-689 | 0 | =0（`width_warnings.txt`） | PASS |
| 多驱动 8-685x | 0 | =0（`multi_driven.txt`） | PASS |
| 顶层接线（名/悬空/位宽） | violations=0，宽度可比 534 条 | =0（当场跑） | PASS |

**WHS 这一笔要说清楚，不许当成"修好了"**：r52 是 +0.019（比 r51 的 +0.048 差），这一版 +0.054。
本版并没有针对保持裕量做任何找补动作 —— 数字变好是**这一次布局/布线自己的结果**，
两次构建之间 ±0.05 的摆动本来就在这块板子的量级里。所以它记在账上（"当前这版够用"），
**不记成"r52 的退化已被 V8-8 修复"**；WHS 仍然是深度优化阶段的第一优先项。

## CDC：配对集合没变，端点 67→71 —— 逐行归因（`cdc_details.rpt`，r53 重跑）

`clk_fpga_0 → clkout0_1` 共 71 行：
`axi_gpio_2/U0/gpio_core_1` **35**（r52 是 31，**+4 = 本次新增的 4 个位**：`zman` + `zsel[2:0]`）、
`axi_gpio_0/U0/gpio_core_1` 16、`u_pl/u_lat*` 18（与 r52 同）、`u_cmt/d2_reg` 1、`u_arb/owner_eth_reg` 1。
Critical 仍是 3 行，**形状与 r52 完全一样**：1 行 CDC-10（`u_cmt` 的同步器前组合逻辑）
+ 2 行 CDC-11（`u_lat/lat_tog_reg` 一个翻转位喂两条链）。
⇒ 本轮**没有引入新的跨域结构**；那 2 行 CDC-11 是 r52 就登记在案的那笔账，
  修法（独立慢心跳 / `snap_cross` 内部只同步一次沿）与 WHS 一起排在深度优化阶段。
基线里消失的 `eth_rxc>clk_fpga_0` 同 r52：本轮删掉 `u_lm_x` 的结果，原因已查清，不算改进。

## 台架（`l1_r53_console.txt`）

`SIM DONE pass=58 fail=0`（比 r52 多一条 = 新增的 `tb_v94_zoom_sel`）。
`tb_v94_zoom_sel` 12 条判据，要点两条：
① 期望值**从倍率定义算**（`inv = round(25600/(倍率×100))` 再夹到 10 bit 的天花板 1023），
   不从 `zoom_ctrl` 的表抄 ⇒ RTL 表被改动而中点判据没跟上时这一条会红；
② 八档往返（`zsel=i ⇒ inv=TBL[i] 且 zoom_code 报回 i`）+ 手动期间钉住 +
   **手动→自动只走一步**（1023→1021，不是 1023→512）+ 带外要 256 步走回呼吸带。

## 板级凭据（本目录内）

1. **上电横幅**（`uart_r53_boot.txt`）：`[CFG] axi_gpio_2 @41220000 ok` —— 这一条现在**同时**验到
   那个通道真的是 32 位（探针图案放在保留段 [23:9]，故意不碰 [29:26]，探针不许命令硬件）；
   `[CFG] gamma window @41220008 ok`；`[CTRL] ... bilin=1` + 新增的 `[CTRL] zoom_step=4 1.00x (自动呼吸)`；
   SD 自动播 29.999 fps。（横幅里中文帮助行的 `???` 是捕获脚本按 ASCII 解码，不是板子的问题。）
2. **43 条命令电池全过（r52 那一版是 37 条）**（`battery_r53.txt`）：`RESULT PASS uart_cmd_check (43 条命令, 42.6 s)`，
   收尾 `跑完回到初态：en=00 thr=80 src=1 zoom=1 bilin=1 zsel=4 zman=0 gm=0.00`。
   ⚠ 这一版**第一次跑是红的**，而且红得有价值：`zoom auto` 不改 `zsel`，末态停在 7 ⇒
   "初末态必须相等（含新加的两个位）"抓到电池自己留了痕迹。修的是电池（加一条 `zoom 1.0` 还原），
   **不是把判据放松**。同一跑还暴露 `zoom 1` = 开呼吸（V7 语义）而不是 1.0 倍 —— 见 ISSUES #63。
3. **屏上 Latency 与回读同源：8/8 全中**（`lat_osd_r53.txt`）：15 fps 推流下
   `torn=false`、`pair_ok=1`、`osd_ms === min(floor(tot/100000),9999)` 八次为真；
   实测 `tot = 406293 … 1574698` 拍 = **4.06 … 15.7 ms**，人读那一遍是
   `屏上 Latency=3ms 回读 tot/100000=3 ⇒ 同源一致 ok`；`drop_words` 全程 0。
4. **判据自己的自测**（`battery_selfcheck_r53.txt`、`ports_check_width_ce.txt`）：
   `--align` 正例（43/43 PASS）+ 反例（插一条命令 ⇒ 立刻 FAIL）；
   `--replay` 拿旧固件的捕获跑新判据 ⇒ 明确报"元组正则没抓到东西 —— 判据本身过期了"，
   而不是两个 `NO_MATCH` 相等混成绿。

## 还没做的（不藏着）

- 眼睛判据：`board/README.md` 第 12–18 行。**第 18 行是这一版新加的**（手动缩放四条），
  其中"寄存器里的三位真的走到了像素域"这一跳今天仍只有眼睛能验
  —— `system_top` 里打包 `inv_scale` 的 `status` 线没有任何读者；把它变成机器判据是任务 #45（lane23）。
- `Split:` 那一格仍不带 `(Auto)`（缝没有执行者，V8-4b / 任务 #44，等用户对演示语义拍板）。
- 屏上分辨率格是 512x300（流水线真实几何），不是示例里的 1280x720。
- V8-7（异常原因上屏 + XADC 温度）与 #45 排在下一批；两者都要加读回 lane，合成一次构建。
