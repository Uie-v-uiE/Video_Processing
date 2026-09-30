#!/usr/bin/env python3
# build/r92_doc_followon.py —— #57 落地之后，把"解释旧结构"与"上板命令"这两类文档补成现状。
# 规矩：只改**描述当前设计**的句子；历史日志与当时观测原样留着，但在后面追一句"现状是……"。
# 跑法：python build/r92_doc_followon.py
import io, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def rd(p): return io.open(os.path.join(ROOT, p), encoding='utf-8', newline='').read()
def wr(p, s): io.open(os.path.join(ROOT, p), 'w', encoding='utf-8', newline='').write(s)

def sub(p, old, new, label):
    t = rd(p); n = t.count(old)
    if n != 1:
        print(f"SKIP {p:34s} {label}（匹配 {n} 次）"); return
    wr(p, t.replace(old, new)); print(f"OK   {p:34s} {label}")

L = 'report/study/learn/30_clocks_hdmi_soc.md'
sub(L, '结构性解法要换 IDDR 的时钟源 + 重调 IDELAY',
    '**（r92 已落地：IDDR 改吃那只 BUFG、`IDELAY_VALUE` 15→26 把采样沿挪回去；最差 20 条 hold 的偏斜实测从 '
    '1.616 ns 变成 0.013~0.349 ns。但 WHS 的**数字**没跟着涨——现在压住它的是 r79 自加严的 0.8 ns hold '
    '不确定度和工具插延迟的粒度，见 `report/OPTIMIZATION_LOG.md` 的 r92 那一节）** 结构性解法要换 IDDR 的时钟源 + 重调 IDELAY',
    'learn/30 追记现状')
sub(L, '因为它的负载是 ILOGIC 而不是全局网络',
    '因为它的负载是 ILOGIC 而不是全局网络（**这一句是 #57 落地前的观测**）',
    'learn/30 观测加时间戳')

# 上板命令：program_pl 现在能接别的位流
sub('board/README.md', 'vivado -mode batch -source build/tcl/program_pl.tcl',
    'vivado -mode batch -source build/tcl/program_pl.tcl   # 想烧隔离滚出来的件：VP_BIT=build/isolated_xxx/system.bit（默认仍是 build/system.bit）',
    'board/README 上板那行')
sub('report/BUILD.md', '3. 下载 bit：`vivado -mode batch -source build/tcl/program_pl.tcl`（下 bit 前先 `md5sum` 对 MANIFEST）',
    '3. 下载 bit：`vivado -mode batch -source build/tcl/program_pl.tcl`（下 bit 前先 `md5sum` 对 MANIFEST）；'
    '拿隔离滚的产物做板上对照时可以 `VP_BIT=<那个目录>/system.bit`，**默认路径不变**，交付件身份仍由 md5 认',
    'BUILD 上板那行')

# KNOWN_ISSUES：给"念 WHS 要带口径"补一条（紧跟在念 WNS 那条后面）
K = 'report/KNOWN_ISSUES.md'
t = rd(K)
m = re.search(r'^.*WNS.*绝对.*$', t, re.M)
if m and '念 WHS' not in t:
    line = m.group(0)
    add = ('\n- **念 WHS 必须带口径**：本仓对 `eth_rxc` 故意加了 `set_clock_uncertainty -hold 0.800`（r79 起，只加严不放松），'
           '所以报告里 `+0.0x ns` 说的是"**按 0.8 ns 要求之后还剩这么多**"，不是"真实余量只有 0.0x"；'
           '跨版比 WHS 之前先确认这把尺子没动过（出处 `src/constraints/rk_zynq7020.xdc`）。')
    wr(K, t.replace(line, line + add, 1)); print(f"OK   {K:34s} 追一条 WHS 口径")
else:
    print(f"SKIP {K:34s} 找不到 WNS 绝对值那条或已追过（match={bool(m)}）")
