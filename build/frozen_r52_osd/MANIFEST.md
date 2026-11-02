r52 冻结集（第二次构建，bit 5a64c680）—— 2026-09-25 02:5x
==================================================================

这一版做两件事：**V8-5 的四行 OSD**（用户原话那四行）与 **V8-6 时延读回口的第六口**。
两件事是绑在一起的：屏上 `Latency:` 那一格画的毫秒数，第一次可以由上位机**机器验证**它
与 `tot` 是同一轮 —— 见下面"板级凭据"第 1 条。

## 成套三件（md5 前 8 位）

| 文件 | md5 | 说明 |
|---|---|---|
| `system.bit` | **5a64c680** | 本冻结件的位流（build #32） |
| `system.xsa` | **10e65337** | 与 bit 同一次导出 |
| `ps_app.elf` | **223f8d1a** | 与 r52 第一次尝试同一份（本轮没改 PS 代码） |

⚠ 目录里同时留着 `gates_r52.txt`（02:1x 那一次构建的门禁，bit `53fbd56d`，**已被取代**）。
本冻结件的权威门禁是 **`gates_r52b.txt`**；留着旧那份只为对账"lane24 那一改花了多少资源"。

## 门禁十四项：ALL PASS（凭据 `gates_r52b.txt`，当场跑）

| 项 | 数 | 阈值 | 判 |
|---|---|---|---|
| WNS | **+0.243 ns** | ≥0 | PASS |
| 失败 setup 端点 | 0（总端点 29397） | =0 | PASS |
| WHS | **+0.019 ns** | ≥0 | PASS |
| 失败 hold 端点 | 0 | =0 | PASS |
| BRAM | 92 tile / 65.71 % | ≤97 % | PASS |
| Slice LUT | 11043 / 20.76 % | ≤98 % | PASS |
| Slice 寄存器 | 8342 | 记录 | PASS |
| 动态功耗 | 2.182 W | 与前次同量级 | PASS |
| methodology CRITICAL WARNING | 0 | =0 | PASS |
| 布线错误网线 | 0 | =0 | PASS |
| cdc.rpt Critical 行 | 3（基线 4） | 配对不新增 | PASS |
| 端口宽度 8-689 | 0 | =0（`width_warnings.txt`） | PASS |
| 多驱动 8-685x | 0 | =0（`multi_driven.txt`） | PASS |
| 顶层接线（名/悬空/**位宽**） | violations=0，宽度可比 526 条 | =0（当场跑） | PASS |

**两条不粉饰的退化/变化**（都绿，但要记账）：

1. **WHS 从 r51 的 +0.048 掉到 +0.019**。失败端点仍是 0，所以门禁绿；但这是"加功能顺手把保持
   裕量吃掉 60 %"，与用户定的深度优化次序（**WHS 优先**）直接相关 ⇒ 登记到优化阶段的第一批候选，
   不在这一轮偷偷做时钟树/实现策略上的找补。
2. **CDC 配对 `clk_fpga_0>clkout0_1` 端点 17→67**（门禁只记录、不判红）。是谁：**`cdc_details.rpt`
   逐行归因** —— 31 行 `axi_gpio_2/U0/gpio_core_1`（新的配置 GPIO 走 `effect_ctrl` 那条 18→24 位
   ASYNC_REG 链）、16 行 `axi_gpio_0/U0/gpio_core_1`（老控制字）、**18 行 `u_pl/u_lat*`（本轮新增的
   时延跨域）**、其余 2 行是既有的 `u_cmt/d1_reg` 与 `u_arb/owner_eth_reg`。
   规则构成：48 行 CDC-3 Info（带 ASYNC_REG 的单 bit 同步）+ 16 行 CDC-15 Warning（时钟使能型）
   + 3 行 Critical。那 3 行 Critical 里 **2 行是新的**，都是 `u_pl/u_lat/lat_tog_reg/C` 的
   CDC-11"发起触发器扇出到目的时钟"：**同一个翻转位被喂给了 `snap_cross` 的两条链**
   （`.bus_tog(lat_tog_axi)` 与 `.hb_tog(lat_tog_axi)`）。
   为什么可容忍：这个翻转位**一轮才变一次**（15 fps ⇒ 66 ms），两条 3 级链看见沿的时刻最差错开
   一个 20 ns 采样拍 ⇒ 对"数值快照"与"心跳计时"各自的判据都不构成误判；
   为什么仍然登记：它违反本仓自己写下的"**每个源字只共享一条同步链**"约定
   （`effect_ctrl` 那条注释就是为这件事写的），修法是把 hb 换成一根独立的慢速心跳、
   或让 `snap_cross` 内部只同步一次沿再分用 —— 归到优化阶段与 WHS 一起处理。
   基线里消失的 `eth_rxc>clk_fpga_0`（272 端点）不是"改进"也不是"退化"：
   **原因已查清**，是本轮删掉了 `u_lm_x`（链路监视器的跨域口），函数已并入 lane31 与 `frame_latency`。

## 台架（L1 全量，凭据 `l1_r52_console.txt`）

`SIM DONE pass=57 fail=0`。本轮新增/重写的三份：

- `tb_osd_lines`（重写）：四行逐格按整串比对，含"少一笔/多一格"的抓法、不可见字形检查、
  以及第二台 IMG_W=640/IMG_H=480 的实例证明分辨率那一格是**参数**不是常数。
- `tb_v794_osd_glyph`：64 项金表（空格在 63）+ `'b'`/`' '`/`'0'` 三个易混码点。
- `tb_v90_latency`：加了 `q_ms` 的 T11..T16c —— 商等于 `tot/100000`、真的产生过非零 ms、
  撕写检查、一轮一个翻转、钳位轮置 `lat_sticky` 后下一轮能清、会话粘滞位保持，
  以及 **T16b/T16c 要求"武装撞上除法那 32 拍"这件事在台架里真的发生过**（`npair>0` 且 `nskip>0`），
  否则同源判据就是空跑。
- `tb_v93_split_ctrl`（30 条）：`split_ctrl` 单独验完**但没接线**，原因见 ISSUES #62。

## 板级凭据（本目录内）

1. **屏上 Latency 与回读同源 —— 8/8 全中**（`lat_osd_r52.txt`）：推流 15 fps（`--test move`）下
   八次 `health_read --json`，每次 `torn=false`、`pair_ok=1`、`sticky=0`、`lanes_aligned=true`、
   `pairs_usable=2`，且 `osd_ms === min(floor(tot_cyc/100000), 9999)` 八次全真。
   实测跨度 `tot = 117106 … 1689898` 拍 = **1.17 … 16.9 ms**；人读那一遍印的是
   `屏上 Latency=13ms 回读 tot/100000=13 ⇒ 同源一致 ok`。
   `n_meas` 每次读之间前进约 170，与 15 fps × 读一次的墙钟时间自洽（口径复核，不是新判据）。
2. **37 条命令电池全过**（`battery_r52b.txt`）：`RESULT PASS uart_cmd_check (37 条命令, 37.4 s)`，
   跑完回到初态 `en=00 thr=80 src=1 zoom=1 bilin=1 gm=0.00`。
3. **上电横幅**（`uart_r52b_boot.txt`）：`[CFG] axi_gpio_2 @41220000 ok` +
   `[CFG] gamma window @41220008 ok` + `[CTRL] ... sel=000 thr=80 ... bilin=1`，
   SD 挂载并自动播（`[SD] dir map ok: 9 files`、`frame 1000: ... 29.634 fps`）。
   （横幅里那串 `???` 是捕获脚本按 ASCII 解中文帮助行，不是板子的问题。）
4. **门禁第 14 项的位宽判据自己有反例**（`ports_check_width_ce.txt`）：
   改窄 `dbg_lat` 声明 ⇒ 报 192 vs 160；改窄一处字面量 ⇒ 报 19 vs 18；不改 ⇒ violations=0。

## 还没做的（不藏着）

- 眼睛判据：`board/README.md` 第 12–17 行（含新加的第 17 行"四行逐格读屏"）——屏上的字只有人能验。
- `Split:` 那一格**不带** `(Auto)` 后缀：缝还没有执行者（V8-4b，任务 #44）。资源不是障碍
  （BRAM 65.71 %，余 48 tile），卡的是演示语义要用户拍板。
- 屏上分辨率那一格是 **512x300**（流水线真实几何），不是用户示例里的 1280x720；
  1 GbE 上裸 720p RGB565 装不下，要改口径由用户定（PLAN §7d）。
- V8-8（缩放因子寄存器）、V8-7（异常与温度）尚未做；施工图在 PLAN §7c 与任务 #42/#43。
