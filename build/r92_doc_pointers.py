#!/usr/bin/env python3
# build/r92_doc_pointers.py —— #57 落了之后，把"描述现状"的文档改口（历史日志不动）。
# 关键规矩：行号引用一律**现场算**，不手数、不沿用旧行号（#122 警告的就是抄来的 file:line）。
# 跑法：python build/r92_doc_pointers.py
import io, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def lines(p):
    return io.open(os.path.join(ROOT, p), encoding='utf-8', newline='').read().split('\n')
def findone(p, pat):
    for i, l in enumerate(lines(p), 1):
        if re.search(pat, l):
            return i
    return None
def span(p, pat):
    """返回从 pat 那一行到该实例右括号收尾那一行的行号范围（只要第一段）。"""
    ls = lines(p)
    for i, l in enumerate(ls, 1):
        if re.search(pat, l):
            j = i
            while j < len(ls) and ')' not in ls[j - 1] or (j < len(ls) and not ls[j-1].rstrip().endswith(')')):
                j += 1
                if j - i > 20:
                    break
            return (i, j)
    return (None, None)

SYT = 'src/rtl/top/system_top.v'
RGX = 'src/rtl/eth/rgmii_rx.v'
ide = findone(SYT, r'\.IDELAY_VALUE\(26\)')
ctl = findone(RGX, r'\) u_iddr_rx_ctl \(')
dat = findone(RGX, r'\) u_iddr_rxd \(')
bufg = findone(RGX, r'BUFG BUFG_inst')
print(f"IDELAY_VALUE@{SYT}:{ide} | u_iddr_rx_ctl {ctl} | u_iddr_rxd {dat} | BUFG@{bufg}")

def sub(fname, old, new, label):
    t = io.open(os.path.join(ROOT, fname), encoding='utf-8', newline='').read()
    n = t.count(old)
    if n != 1:
        print(f"SKIP {fname:34s} {label}（匹配 {n} 次）")
        return
    io.open(os.path.join(ROOT, fname), 'w', encoding='utf-8', newline='').write(t.replace(old, new))
    print(f"OK   {fname:34s} {label}")

# 1) MODULES.md：rgmii_rx 那一行
sub('docs/MODULES.md', '| `rgmii_rx` | BUFIO/IDDR(`SAME_EDGE_PIPELINED`) + IDELAYE2(FIXED, 参考 200 MHz) |',
    f'| `rgmii_rx` | IDDR(`SAME_EDGE_PIPELINED`) **吃 BUFG**（#57 之后 IO 与 fabric 同一棵树）+ IDELAYE2(FIXED, 参考 200 MHz, `IDELAY_VALUE=26`) |',
    'rgmii_rx 行')
# 2) ARCHITECTURE.md：输入延迟那一行（值与行号都现取）
sub('docs/ARCHITECTURE.md', f'| RGMII 输入延迟 | `IDELAY_VALUE` = 15（FIXED 抽头，参考 200 MHz） | `system_top.v:160`、',
    f'| RGMII 输入延迟 | `IDELAY_VALUE` = **26**（FIXED 抽头，参考 200 MHz ⇒ 每拍 156 ps；#57 换树之后按 `4.854−3.171=1.683 ns` 补 +11 拍） | `{SYT}:{ide}`、',
    '输入延迟行')
# 3) PERF_REPORT.md：那句"结构修法仍未做"
sub('docs/PERF_REPORT.md', 'BUFIO→BUFG 偏斜，结构修法仍未做，需要用户在板前）',
    f'BUFIO→BUFG 偏斜；**结构修法已于 #57 落地**（`{RGX}:{bufg}` 一只 BUFG 同时喂 IDDR 与 fabric，'
    f'`{SYT}:{ide}` 补到 26 拍），最差那族 hold 的偏斜从 1.616 ns 变成同树内的 0.013~0.349 ns，'
    '数字本身仍在 0.8 ns 自加不确定度之下）',
    'PERF 那句"仍未做"')
# 4) learn/30：三处
sub('docs/study/learn/30_clocks_hdmi_soc.md', '| `eth_rxc` → `gmii_rx_clk` | 125 MHz | PHY（引脚 Y19），经 IBUF → BUFG + BUFIO 两棵树 |',
    '| `eth_rxc` → `gmii_rx_clk` | 125 MHz | PHY（引脚 Y19），经 IBUF → **一只 BUFG**（#57 之后解串器与 fabric 同一棵树）|',
    'learn/30 时钟表')
sub('docs/study/learn/30_clocks_hdmi_soc.md', '数据在 ILOGIC 里被 **BUFIO** 采',
    '数据在 ILOGIC 里被 **BUFG** 采（#57 之前是 BUFIO，那样 IO 与 fabric 分走两条树，偏斜 1.616 ns ⇒ 最差 hold 每次重建掷硬币）',
    'learn/30 采样句')
# 5) learn/01：项目地图里那条
sub('docs/study/learn/01_project_map.md', '| RGMII 输入延迟 | `IDELAY_VALUE=15`（FIXED 抽头，200 MHz 参考） | `system_top.v:156` |',
    f'| RGMII 输入延迟 | `IDELAY_VALUE=26`（FIXED 抽头，200 MHz 参考 ⇒ 156 ps/拍；#57 换树时按 1.683 ns 补 +11 拍） | `{SYT}:{ide}` |',
    'learn/01 地图行')
print("提示：learn/30 那条“BUFIO 只服务 IO 逻辑”是原理说明（7 系列的事实），不改。")
