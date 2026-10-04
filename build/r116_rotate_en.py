# 用途：r116 采纳轮的首页/指标表改口（英文行 + metrics.csv 三行）
# 输入：build/timing_summary.rpt
# 输出：stdout
# 退出码：脚本内无显式 exit ⇒ 随最后一条命令（正常跑完为 0）
# build/r116_rotate_en.py —— r116 采纳轮的首页/指标表改口（英文行 + metrics.csv 三行）。
# 为什么用脚本而不是手改：这三处的形状被 src/host/metric_recheck.mjs 的首页层正则判着，
# 手改一行少个括号就可能把"数对不上"换成"读不出来"；脚本按行首标签定位，改完整行，跑一遍尺子就收敛。
# 用法：python build/r116_rotate_en.py   （幂等：重复跑只是把同一批整行重写一遍）
import io

M = chr(8722)  # U+2212 减号，与中文首页一致

EN = [
    ('| Design-wide setup WNS |',
     '| Design-wide setup WNS | **{M}0.846 ns**, failing setup/hold endpoints **5 / 51140** '
     '(the board now runs r116, flashed 2026-10-04 01:37 through the three-step JTAG chain, bit `bb2fb707aebc`; '
     '`board_verify --geom --battery` PASS at 01:50 with 0 red steps; gate file `build/r116_gates.txt`). '
     '⚠ **All five failing endpoints are RGMII input pins that this round checked for the first time**: before the window '
     'was written down they reported `Slack: inf / Path Group: (none)` - "not checked", not "met" (exactly the reading rule H5 forbids) - '
     'while the 46,300 internal endpoints have **zero** violations. '
     '⚠ With the window in place this family is **proved to have no solution inside the legal tap range**: hold needs t >= 44.8, '
     'setup needs t <= 21.8 (measured slopes +63.0 / -92.0 ps per tap, crossing at t = 31.1, artifact '
     '`build/evidence/r115_window/probe3_console.txt`), and the root cause is the clock-network corner spread of **3.411 ns** '
     'against only **0.467 ns** on the data side. So this cell is stated as a **device/structure boundary**, not as '
     '"no point found yet" (per-domain audit `report/timing/limit_audit_r116.md`; the inequality lives in '
     '`report/timing/rgmii_window_model.md` section 7.5). On the board it costs nothing observable: under real traffic '
     '(512x300@60, ~147 Mbps, 50 s, 663,221 packets) `drop_words=0` and `pkt_err=0`, and an A/B against a re-flashed r114 '
     'gives four readings identical cell for cell (`build/evidence/r116_board/`, `report/log/issues.md` #318) | '
     '`build/timing_summary.rpt` (Design Timing Summary row), `build/evidence/r116/r116_io_hold.rpt`, '
     '`build/evidence/r116/r116_io_setup.rpt`, `build/r116_gates.txt` |'.replace('{M}', M)),
    ('| Per-clock setup slack |',
     '| Per-clock setup slack | 125 MHz receive domain `eth_rxc` **{M}0.846 ns** (of its 8 ns period that is {M}10.57 % - '
     'still both the design-worst absolute path and the tightest normalised margin, and that cell is one of the five newly '
     'checked I/O endpoints); 100 MHz `clk_fpga_0` **1.976 ns** (19.76 %); 50 MHz display domain `clkout0_1` **3.698 ns** (18.49 %); '
     '`sys_clk` **14.876 ns** (of its 20 ns period, 74.38 %, the widest). **Cell-by-cell roster diff** (same generator on both sides, '
     'artifact `build/evidence/r116_roster_diff.txt`, 6 pairs judged out of 8 compared): `clk_fpga_0` setup 1.850 -> 1.976 '
     '(relative margin 18.50 -> 19.76 %, +6.8 %), `clkout0_1` 3.630 -> 3.698 (18.15 -> 18.49 %, +1.9 %), `sys_clk` 14.876 -> 14.876 '
     'unchanged; the only value that got smaller is `eth_rxc` (0.739 -> {M}0.846), and that is **newly exposed debt, not slack moved '
     'out of another domain** - gate G1 reads it as RED by the letter and this page does not talk it out. The worst **internal** path '
     'also changed family: in r114 it was `u_icmp_tx/ip_head_reg[4][16]/C -> check_buffer_reg[19]/D` (11 levels, route 58.447 %); '
     'this round the four I/O paths rank ahead of it, so the internal worst falls back to the `u_rx_par -> rows_hit[*]/CE` family '
     '(`build/evidence/r116_after.txt` prints only the four I/O paths for `eth_rxc`). Per rule 35 an absolute WNS delta is neither '
     'gain nor loss. **Where this family is actually limited now has a number**: the clock network alone costs SCD 5.008 / DCD 4.493 ns '
     'out of an 8 ns period, and the control roll `build/evidence/r117_fb_pblock/a/roll_console.txt` reproduced the official roster cell '
     'for cell, so further RTL surgery in this family has close to zero headroom; the remaining lever is shortening the capture clock '
     '(`report/timing/round_r116.md` section 4, with the 4b numeric target and the 4c cost) | `build/timing_summary.rpt` (Intra Clock Table), '
     '`build/evidence/r116_after.txt`, `build/evidence/r116_roster_diff.txt` |'.replace('{M}', M)),
    ('| Hold time |',
     '| Hold time | the worst cell in the whole design is in `eth_rxc` (125 MHz receive domain; landing point '
     'u_eth/u_rgmii/u_rgmii_rx/u_iddr_rx_ctl/D, launched from the input port `eth_rx_ctl`) at **{M}0.870 ns**, and that cell has '
     '**2 levels (IBUF=1, IDELAYE2=1)** with **route 0.000 %** (the IO-tile path has no wire to optimise), '
     '`Path Type: Hold (Min at Slow Process Corner)`, `Input Delay: 1.200 ns` (artifact `build/evidence/r116/r116_io_hold.rpt`); '
     'the rest of the per-clock hold numbers: 100 MHz `clk_fpga_0` **0.053 ns**, 50 MHz display domain `clkout0_1` **0.059 ns**, '
     '`sys_clk` **0.222 ns** - and those three are **identical to r114 cell for cell**, so the worry that "adding a window squeezes '
     'hold thinner" did not materialise. ⚠ Two scope readings must be quoted: (1) those three positive numbers are what is left '
     '**after** the 0.8 ns hold uncertainty this repo imposes on itself, and only `eth_rxc` carries that band, so #265 says the four '
     'are **not comparable across domains**; the uniform-band experiment ran in r115 and turned the whole design red '
     '(-0.747 over 25,742 endpoints), which is why this round leaves the band alone. (2) the `eth_rxc` cell changed from r114\'s 0.052 - '
     'a number produced by the implicit assumption that RXD/RX_CTL arrive exactly with RXC - to {M}0.870, the first number produced with '
     'an arrival window; **the old 0.052 was never a design value**, and correcting that sentence is the real content of this round. '
     '⚠ Ownership moved, and rule 46 requires naming it: in r114 the design-worst hold cell belonged to the grey-code chain '
     '`u_cdc/rgray_s1_reg[10]/C -> u_lm/full_d_reg/D` (0.052, 3 levels, route 56.480 %); this round it is handed to the newly checked '
     'RGMII I/O endpoint ({M}0.870). That is a change in **what is checked**, not a degradation of that logic | '
     '`build/timing_summary.rpt` (Intra Clock Table, WHS column), `build/evidence/r116/r116_io_hold.rpt`, '
     '`build/evidence/r116_after.txt` |'.replace('{M}', M)),
]

CSV = [
    ('全局 setup WNS,',
     '全局 setup WNS,核心,{M}0.846,ns,'
     '失败端点 5 / 51140；这一格是 r116 第一次给 RGMII 输入绑窗（min 1.200 / max 2.800，出处 RTL8211F-CG 规格书 Table 60 的 '
     'TsetupT/TholdT）之后**新暴露的 5 个 I/O 端点**，绑窗前它们报 Slack: inf＝没检查不是满足；片内 46,300 端点零违例；'
     '这一族在合法 0…31 全档无解（hold 要 τ≥44.8、setup 要 τ≤21.8，件 build/evidence/r115_window/probe3_console.txt），'
     '根因是钟网络角间差 3.411 ns vs 数据 0.467 ns ⇒ 判定=器件/结构边界（report/timing/limit_audit_r116.md）。'
     '板侧 147 Mbps 真实流量 drop_words=0，与回刷 r114 的 A/B 逐格相同（ISSUES #318）,一次构建,build/timing_summary.rpt'.replace('{M}', M)),
    ('全局 setup 失败端点,',
     '全局 setup 失败端点,核心,5,个,'
     '本轮 5 / 51140 端点失败；五个全是本轮第一次被检查的 RGMII 输入端点（eth_rxd[3:0] 与 eth_rx_ctl 打到 IDDR 的 D 脚）；'
     '片内端点零违例；绑窗前这些路是 Slack: inf / Path Group: (none)，一次构建,build/timing_summary.rpt'),
    ('全局 hold WHS,',
     '全局 hold WHS,核心,{M}0.870,ns,'
     '同上（失败端点 5 / 51140；脉冲宽度 WPWS 0.264）；最薄那一格本轮换到 RGMII I/O 端点'
     '（落点 u_iddr_rx_ctl/D、route 0.000 %、Input Delay 1.200 ns，件 build/evidence/r116/r116_io_hold.rpt）；'
     '逐时钟 hold：`eth_rxc` {M}0.870／`clk_fpga_0` 0.053／`clkout0_1` 0.059／`sys_clk` 0.222——后三格与 r114 逐格相同。'
     '⚠ 口径：只有 eth_rxc 带 0.800 的 hold 不确定度（#265 说四域跨域不可比；统一带子的实验 r115 跑过、全设计红 '
     '-0.747/25,742 端点 ⇒ 本轮不动它）,一次构建,build/timing_summary.rpt'.replace('{M}', M)),
]


def rotate(path, table):
    lines = io.open(path, encoding='utf-8').read().split('\n')
    done = []
    for prefix, new in table:
        idx = [i for i, l in enumerate(lines) if l.startswith(prefix)]
        if len(idx) != 1:
            raise SystemExit('REFUSE %s: prefix %r matched %d lines (must be exactly 1)' % (path, prefix, len(idx)))
        lines[idx[0]] = new
        done.append((prefix, idx[0] + 1))
    io.open(path, 'w', encoding='utf-8', newline='\n').write('\n'.join(lines))
    return done


if __name__ == '__main__':
    print('readme.en.md', rotate('readme.en.md', EN))
    print('metrics.csv', rotate('data/metrics.csv', CSV))
