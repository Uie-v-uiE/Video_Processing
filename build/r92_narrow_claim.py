#!/usr/bin/env python3
# build/r92_narrow_claim.py —— 把我自己写宽的一句话收窄，并把它钉在实测报告上。
# 事实（`build/clock_uncertainty.rpt`，开的是本轮已布线 dcp）：
#   * 全设计最差 min 路径：`u_pl/u_lat/t_commit_reg[0] → u_pl/u_lat/max_cyc_reg[4]`，域是 **clk_fpga_0**，
#     slack +0.037，`Requirement: 0.000ns`，报告里**没有** 0.800 那行 ⇒ 它不吃 `set_clock_uncertainty -hold`。
#   * `eth_rxc` 自己最差 min 路径：`u_eth/u_rx_mac/m_sof_reg → u_eth/u_rx_par/in_pay_reg`，
#     slack +0.049，路径表里明写 `clock uncertainty 0.800` ⇒ 那句约束**生效**。
# 所以"念 WHS 要带 0.8 口径"只对 `eth_rxc` 那个数成立，对**全设计 WHS**不成立——我原来写宽了。
import io, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def rw(p, pairs):
    fp = os.path.join(ROOT, p)
    t = io.open(fp, encoding='utf-8', newline='').read()
    for a, b in pairs:
        n = t.count(a)
        if n != 1:
            print(f"SKIP {p}：匹配 {n} 次 -> {a[:34]}")
            continue
        t = t.replace(a, b)
        print(f"OK   {p}：{a[:28]}…")
    io.open(fp, 'w', encoding='utf-8', newline='').write(t)

K = 'report/known_issues.md'
old = ('- **念 WHS 必须带口径**：本仓对 `eth_rxc` 故意加了 `set_clock_uncertainty -hold 0.800`（r79 起，只加严不放松），'
       '所以报告里 `+0.0x ns` 说的是"**按 0.8 ns 要求之后还剩这么多**"，不是"真实余量只有 0.0x"；'
       '跨版比 WHS 之前先确认这把尺子没动过（出处 `src/constraints/rk_zynq7020.xdc`）。'
       '#57 把两条时钟树并成一条之后（见 `docs/optimization_log.md` 的 r92），这句话更要用：偏斜已经不再是那个数的来源。')
new = ('- **念 WHS 要先问是哪一个数**：本仓对 `eth_rxc` 故意加了 `set_clock_uncertainty -hold 0.800`（r79 起，只加严不放松，'
       '`src/constraints/rk_zynq7020.xdc`），所以 **`eth_rxc` 那一格的 `+0.049 ns` 是"按 0.8 ns 要求之后还剩这么多"**，'
       '不是"真实余量只有 0.0x"——本轮实测那条路径（`u_eth/u_rx_mac/m_sof_reg → u_eth/u_rx_par/in_pay_reg`）的报告里'
       '明写 `clock uncertainty 0.800`，约束确实生效（凭据 `build/clock_uncertainty.rpt`）。'
       '**但全设计那一格 `+0.037 ns` 不吃这个口径**：#57 之后最差 min 路径换到了 `clk_fpga_0` 域'
       '（`u_pl/u_lat/t_commit_reg[0] → u_pl/u_lat/max_cyc_reg[4]`），同报告里它的 `Requirement: 0.000ns`、'
       '没有不确定度那一行。⇒ 跨版比 WHS 之前，先确认比的是**哪一格**、那一格的尺子有没有动过。')
rw(K, [(old, new)])

B = 'board/README.md'
old2 = ('⚠ 念这个数要带口径：它是**按 r79 加严的 0.8 ns hold 不确定度要求之后**剩下的量，不是"真实余量只有 0.0x"；')
new2 = ('⚠ 念这两个数要用两把尺子：**全设计最差那条 min 路径在 100 MHz 域（`clk_fpga_0`），`Requirement: 0.000ns`、'
        '不带自加不确定度**；`eth_rxc` 那一格（+0.049）才是"按 r79 加严的 0.8 ns hold 不确定度要求之后"剩下的量'
        '（实测凭据 `build/clock_uncertainty.rpt`：那一条的报告表里写着 `clock uncertainty 0.800`）。'
        '把 `+0.037` 念成"真实余量只有 0.037"或念成"被 0.8 扣过的"都不对 —— 它两个都不是，它是 100 MHz 域里一条'
        '同沿 min 检查的裸余量；')
rw(B, [(old2, new2)])

L = 'report/optimization_log.md'
old3 = ('**台架与门禁（05:0x–06:0x，`build/r92_gates.txt`，仓库里的件、不随包）**')
new3 = ('**顺带量出来的一件新事实（06:1x，`build/tcl/clock_uncertainty.tcl` → `build/clock_uncertainty.rpt`）**：'
        '#57 之后**全设计最差 min 路径换了域** —— 不再是 `eth_rxc`，而是 100 MHz 的 '
        '`u_pl/u_lat/t_commit_reg[0] → max_cyc_reg[4]`，slack +0.037、`Requirement: 0.000ns`（同沿检查，不带自加不确定度）；'
        '`eth_rxc` 那一格是 +0.049，而且它的报告表里明写 `clock uncertainty 0.800` ⇒ 那句约束**确认生效**（这是 #80 追加'
        '那段一直要求"确认生效再念"的事，现在有凭据了）。⇒ 下一刀如果还想动 hold，对象是 `clk_fpga_0` 那一族，'
        '不是收包域；而给 `clk_fpga_0` 加约束要小心 51-56 行那笔旧账（它在 XDC 读取时 `get_clocks` 取不到）。\n'
        '**台架与门禁（05:0x–06:0x，`build/r92_gates.txt`，仓库里的件、不随包）**')
rw(L, [(old3, new3)])
