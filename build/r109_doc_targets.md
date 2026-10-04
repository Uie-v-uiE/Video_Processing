# r109 采纳那笔的目标值（右侧值全部由尺子从当轮报告里读出来，不是抄的）
# 生成 2026-10-03 00:41:33；权威口径 = build/evidence/r109_metric_rotation.txt 里 44 条 RED 的「报告=」那侧
# 采纳前必做：重跑 node src/host/metric_recheck.mjs —— 件还是这一套（构建到采纳之间不再动 DCP），值应当逐条相同

## 一、待逐条改的 44 个数（左=首页/csv 现在的值，右=报告的值）
README.md 关键数字表中「全设计 setup WNS」那一行 WNS(ns) 首页=0.721 报告=0.605
README.md 关键数字表中「逐时钟 setup 余量」那一行 setup[eth_rxc] 首页=0.721 报告=0.605
README.md 关键数字表中「逐时钟 setup 余量」那一行 setup[clk_fpga_0] 首页=1.524 报告=1.238
README.md 关键数字表中「逐时钟 setup 余量」那一行 setup[clkout0_1] 首页=1.13 报告=4.094
README.md 关键数字表中「逐时钟 setup 余量」那一行 setup[sys_clk] 首页=14.324 报告=15.289
README.md 关键数字表中「逐时钟 setup 余量」那一行 余量%[eth_rxc] 首页=9 报告=7.563
README.md 关键数字表中「逐时钟 setup 余量」那一行 余量%[clk_fpga_0] 首页=15.2 报告=12.38
README.md 关键数字表中「逐时钟 setup 余量」那一行 余量%[clkout0_1] 首页=5.65 报告=20.47
README.md 关键数字表中「保持时间」那一行 whs[eth_rxc] 首页=0.035 报告=0.049
README.md 关键数字表中「保持时间」那一行 whs[clk_fpga_0] 首页=0.053 报告=0.052
README.md 关键数字表中「保持时间」那一行 whs[clkout0_1] 首页=0.06 报告=0.053
README.md 关键数字表中「保持时间」那一行 whs[sys_clk] 首页=0.159 报告=0.121
README.md 关键数字表中「BRAM / LUT / FF / DSP」那一行 BRAM tile 首页=95 报告=95.5
README.md 关键数字表中「BRAM / LUT / FF / DSP」那一行 BRAM 占比(%) 首页=67.86 报告=68.21
README.md 关键数字表中「BRAM / LUT / FF / DSP」那一行 LUT 首页=14360 报告=14362
README.md 关键数字表中「BRAM / LUT / FF / DSP」那一行 LUT 占比(%) 首页=26.99 报告=27
README.md 关键数字表中「BRAM / LUT / FF / DSP」那一行 FF 首页=8168 报告=8162
README.md 关键数字表中「BRAM / LUT / FF / DSP」那一行 FF 占比(%) 首页=7.68 报告=7.67
README.md 关键数字表中「功耗」那一行 动态功耗(W) 首页=2.212 报告=2.214
README_EN.md:70 Design-wide setup WNS/WNS(ns) 首页=0.721 报告=0.605
README_EN.md:71 Per-clock setup slack/setup[eth_rxc] 首页=0.721 报告=0.605
README_EN.md:71 Per-clock setup slack/setup[clk_fpga_0] 首页=1.524 报告=1.238
README_EN.md:71 Per-clock setup slack/setup[clkout0_1] 首页=1.13 报告=4.094
README_EN.md:71 Per-clock setup slack/setup[sys_clk] 首页=14.324 报告=15.289
README_EN.md:71 Per-clock setup slack/余量%[eth_rxc] 首页=9 报告=7.563
README_EN.md:71 Per-clock setup slack/余量%[clk_fpga_0] 首页=15.2 报告=12.38
README_EN.md:71 Per-clock setup slack/余量%[clkout0_1] 首页=5.65 报告=20.47
README_EN.md:72 Hold time/whs[eth_rxc] 首页=0.035 报告=0.049
README_EN.md:72 Hold time/whs[clk_fpga_0] 首页=0.053 报告=0.052
README_EN.md:72 Hold time/whs[clkout0_1] 首页=0.06 报告=0.053
README_EN.md:72 Hold time/whs[sys_clk] 首页=0.159 报告=0.121
README_EN.md:73 BRAM / LUT / FF / DSP/BRAM tile 首页=95 报告=95.5
README_EN.md:73 BRAM / LUT / FF / DSP/BRAM 占比(%) 首页=67.86 报告=68.21
README_EN.md:73 BRAM / LUT / FF / DSP/LUT 首页=14360 报告=14362
README_EN.md:73 BRAM / LUT / FF / DSP/LUT 占比(%) 首页=26.99 报告=27
README_EN.md:73 BRAM / LUT / FF / DSP/FF 首页=8168 报告=8162
README_EN.md:73 BRAM / LUT / FF / DSP/FF 占比(%) 首页=7.68 报告=7.67
README_EN.md:74 Power/动态功耗(W) 首页=2.212 报告=2.214
全局 setup WNS csv=0.721 report=0.605
全局 hold WHS csv=0.035 report=0.049
Slice LUT 占用 csv=14360（26.99 %） report=14362 | 占用百分数: csv=26.99 report=27
Slice 寄存器占用 csv=8168（7.68 %） report=8162 | 占用百分数: csv=7.68 report=7.67
Block RAM Tile 占用 csv=95 / 140（67.86 %） report=95.5 | 瓦片占用百分数: csv=67.86 report=68.21 | 可用瓦片数: csv=140 report=140
实现后动态功耗 csv=2.212 report=2.214

## 二、逐时钟相对余量（分母=该时钟自己的周期）
  clk_fpga_0   1.238 ns / 10.0 ns = 12.38 %
  eth_rxc      0.605 ns /  8.0 ns =  7.56 %
  sys_clk     15.289 ns / 20.0 ns = 76.44 %
  clkout0_1    4.094 ns / 20.0 ns = 20.47 %
  （这几行就是首页第 57 行与 README_EN.md:71 那三格的新值；D6 对 ns 与百分数**两头都判**，±0.05 容差）

## 三、身份句与门禁条数（同一笔提交，#229）
  板上这一版改成 r109 + 三步 JTAG 刷入时刻 + bit md5 前 12 位（**刷板之后**再取，不许提前写）；
  「门禁 22 项 21 绿 / 1 红」→ 按 r109_gates.txt 的真实条数与红项名重写，四处：README.md 的「限制与未通过项」一节、README_EN.md:70、
  report/background_and_novelty.md:31、:80；改完重跑 doc_currency 与 metric_recheck 各一次（D1c 有两跑自基准的形状）。

## 四、这一页不写功耗/资源的绝对值
  原因：metric_recheck 的 RED 行已经带着「报告=」的权威值（第一节），另抄一遍就是第二个真相源；
  而 power.rpt 的 dyn/total 拆分口径与尺子读的那一格不完全同名，抄了容易错（今天第一版就抓错过一次 1.1 W）。
