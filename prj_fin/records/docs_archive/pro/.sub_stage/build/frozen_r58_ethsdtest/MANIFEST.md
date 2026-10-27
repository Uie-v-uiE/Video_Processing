# r58 冻结集 —— 2026-09-25 11:54 · 用户坐在屏幕前报上来的五条一起修（含片源词表定稿 ETH / SD / TEST）

这一版的**功能差**全在"看得见的词"和"命令进得去的路"上：
`src_mode` 多了串口覆盖入口（GPIO_0 `[24:23]` 码 + `[22]` 翻转位）、
OSD 第一行 `Src:` 只印 **ETH / SD / TEST** 三个词、第二行收成单空格不再压分割线、
字模 `c`/`p` 重画、串口 `pipe` 长度只收 5 或 9 并新增 `pipe show`。
PL 的**编号一个都没动**（AUTO=0、ETH=1、TEST=2、SD=3，格雷码性质保持 ⇒ 适配器与 #52/#55 两条教训不受影响）。

## 成套三件（md5 前 8 位）

| 文件 | md5 | 说明 |
|---|---|---|
| `system.bit` | **e88f6431** | build **#42**（`../r58b_build42.log` 末行 `SYSTEM BUILD DONE`、策略 `ExploreWithRemap`）——**板上现在跑的就是这一颗** |
| `system.xsa` | **8410e0a9** | 与 bit 同一次导出 |
| `ps_app.elf` | **9144bb40** | `main.c` 改了 `cmd_src` / `ctrl_publish_mode` / `parse_bits` / `pipe show`，所以这一颗与 r57 **不**相同 |

> ⚠ 同一条链上还留着一个**没采纳**的构建 **#41**（`build/gates_r58b.txt`，WNS 0.329 / WHS 0.052）：
> 它的 RTL 与 #42 只差在词表（`put_src` 的三个字符串 + 台架期望），数字也说明这一点。
> 记账为什么留两份：#41 是"我上一笔造的红被我自己关掉"的凭据（见下"门禁"那节），
> 交付件是 #42 —— **只有 #42 被刷上板并做过机器复验**。

## 门禁（14 项，`gates_r58c.txt`）

| 项 | #42（本冻结集） | #41（同一轮的上一颗） | r57（对照） |
|---|---|---|---|
| WNS / WHS (ns) | 0.321 / 0.028 | 0.329 / 0.052 | 0.518 / 0.028 |
| 失败 setup / hold 端点 | 0 / 0 | 0 / 0 | 0 / 0 |
| BRAM / LUT / 寄存器 | 92 (65.71 %) / 11126 / 8446 | 同左 | 92 / 11121 / 8444 |
| Dynamic | 2.185 W（工具低置信度估算） | 2.185 W | 2.185 W |
| **cdc.rpt Critical 配对** | **与基线集合一致，不新增、unsafe 不增长** | 同左 | 基线出处 |
| 端口宽度 8-689 / 多驱动 8-685x | 0 / 0 | 0 / 0 | 0 / 0 |
| `check_ports.py` | instances=81 width_compared=**548** violations=0 | 同左 | 546（新增两个 `mode_ovr*` 端口 ⇒ 多比 2 处） |

**这一轮门禁真的抓了我自己一次**（这是它该干的活）：为了让串口能钉模式，我把 `src_mode` 的
`mode` 写成组合选择 `ov_en ? ov_act : ring` ⇒ 它变成一根跨到 axi 域的组合作用，
`clkout0_1>clk_fpga_0` 那一对从 0 涨到 27 端点 / 2 unsafe，**build #40 当场判红**，
而且红在与 #34 完全相同的那组数字上（那一次也是"模式变成组合线"）。
修法不是放宽门禁，而是回到"每个跨域起点必须是一级触发器"：新增 `mode_q`（**唯一驱动**、
单独一个 always 块 —— 两个块都赋它就是 #61 那个多驱动 net）。#41/#42 都因此回到绿。
⇒ 门禁第 6 项自己的反例测试这一轮也重跑过：`build/gates_cdc_test.sh` **5/5 PASS**
（T1 的证据行就是"Unsafe 端点增长：clk_fpga_0>clkout0_1(unsafe 1→3)"）。

## 台架（行为仿真）

| 台架 | 结果 | 这一版它钉住了什么 |
|---|---|---|
| `tb_v82_src_mode` | PASS | 覆盖路径 T8–T12：命令优先、**覆盖期间长按只交还控制权**、`src auto` 连环也清回 AUTO、"沿之后才改码"的反例（T9 顺序故意写错要能被抓）、`ov_tog` 必须是实 0/1 才认边沿 |
| `tb_osd_lines` | PASS（13 段） | T3 三个词各归哪一态 + `*` 只在锁住时出现；T13 逐行量 `X0+k*CW ≤ 511`，**最宽激励换成 `TEST*`**（用词从 CARD 改成 SD 之后如果还拿 SD 当"最宽"，这一行会凭空短 3 格 ⇒ 判据没牙）；T14 字模 c/p 逐像素对**台架里独立手写**的金表 |
| `tb_v99_unisim_sim`（新增） | PASS | 见下面"顶层台架的门槛"：占位时钟件必须自己被量一遍，比例判据 5×/4× + 空窗反例 C4 |
| 全量 L1 | **62 份 62/0**（`l1_r58_62of62_console.txt`，末行 `SIM DONE pass=62 fail=0`；61 份是老账 + 新增 tb_v99） | 这一版除了顶层零改动，还动了 `src_mode`/`osd_overlay`/`src_arb`/`key_long` 与四份台架的字面期望 ⇒ 整棵树一遍 |

## 板级（`r58c_board_console.txt`，`board_verify.sh --stream --battery`）

```
V1..V7 仲裁八条全过：接管 371 ms / 稳占 27/27 翻转 0 / 停流交回 216 ms /
                    交回后 0/37 不回跳 / 再推 269 ms 可逆 / 原因位不可用 0 / 采样 95 点
lane30 片源状态     {"mode":"TEST","why":"没有流","why_no_stream":1,"why_force_ps":0,…}   ← 新词表已经在机器上
lane23 缩放         verdict=OK（zsel=4=屏上档、inv_ok、code_ok）
Latency 同源        lat.osd_ms_matches_tot → true        丢字 drop_words → 0
SD 回放             last 100 frames 29.982 fps
串口命令电池        RESULT PASS（59 条 / 57.6 s）⇒ 含新增 3 条：
                    `pipe 00001100`（8 位必须拒且 !sel=）、`pipe 1`（同上）、`pipe show`（按名字念）
                    末态 = 初态：en=00 thr=80 src=1 zoom=1 bilin=1 zsel=4 zman=0 gm=0.00 mode=0
                                                    ↑ mode 回到 0 = 串口钉模式这一圈自己收干净
```

## 顶层台架的门槛（这一版的副产品，省掉下一次半天）

`pl_video_top` 里例化了 MMCM / BUFG / OBUFDS / OSERDESE2，而**本机 xsim 没有 UNISIM 库**
（实测 `ERROR [VRFC 10-2063] Module <MMCME2_BASE> not found`）⇒ 这就是 ISSUES #62 风险②
（"没有任何台架例化顶层，所以缝差一拍看不见"）的**物理原因**：不是没人想写，是时钟起不来。
现在有了 `sim/prim/MMCME2_BASE.v` + `sim/prim/unisims_sim.v`（分频比全部从例化参数读回来，
占位件里一个数都不写）并把它们加进 `run_sim.tcl` 与 `run_one.sh` **两处**清单
（只加一处是 2026-09-23 的老坑：单台架绿、全量判 ELAB_FAIL）。
`tb_v99` 量到 pix/5x/200m 在 1 µs 窗口里 50/250/200 拍 ⇒ 50 / 250 / 200 MHz 精确成立。
⚠ 第一版 `tb_v99` 用"等事件"量周期，**挂死**（xsim 跑 4 分钟不退出，被我 kill）——
挂死的台架比红的台架糟（`run_sim.tcl` 顺序跑，一个卡住整轮没有结论），所以现在是
固定时间窗 + 计数器 + 看门狗。

## 怎么复现这一版

```bash
IMPL_STRATEGY="Performance_ExploreWithRemap" \
  cmd //c "D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat" -mode batch -nojournal \
  -source build/tcl/build_system_axigpio.tcl
bash build/gates.sh > build/gates_r58.txt            # 14 项
node build/ps_app.mjs                                # PS elf（main.c 改了，必须重下）
cmd //c "D:\Software\Vivado\2025.2.1\Vitis\bin\xsdb.bat" build/tcl/ps_jtag_boot.tcl
cmd //c "D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat" -mode batch -nojournal -source build/tcl/program_pl.tcl
cmd //c "D:\Software\Vivado\2025.2.1\Vitis\bin\xsdb.bat" build/tcl/ps_app_reload.tcl
bash build/board_verify.sh --stream --battery        # 仲裁八条 + 59 条电池
bash sim/run_sim.tcl                                 # 全量 L1（含 tb_v99）
```

## 还欠什么（不要当成"已验"）

- **眼睛**：`board/README.md` 第 21 / 21b 行 —— 三个词是不是真的印成 `ETH/SD/TEST`、
  `Src`/`Split` 的字形像不像、第二行有没有压线、`src 0/1/2/auto` 与"钉住态长按一次只交还"。
- **未做的功能**（用户已经说"都做"，排在 r59/r60）：V8-4b 几何统一（缝 0~100 % 真可动、
  消掉缝边色带的另一半）、双线性（"缩放时线会移位"的唯一解药）。方案定稿在 ISSUES #62。
- 演示默认 bit 仍然是 #23（`frozen_r23_srcseen`）——换默认是用户的决定。
