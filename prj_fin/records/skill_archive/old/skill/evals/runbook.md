# 复跑手册（陌生人照着做就能重跑那些"已验证"）

这一页只写**在当前这台机器上今天实际跑过**的命令。凡是没有跑过的，不在这里出现；
条目里想引用它的地方必须写 `【待验证】`（口径见 `README.md` 第 4 节）。

## 0. 环境探测（先跑这四条，任何一条不满足就停在这里）

```bash
pwd                       # 必须是仓库根（命令全部用相对路径）
node --version            # 文本尺子是 .mjs，需要 node
python --version          # 注意：本机没有 python3，只有 python
bash --version | head -1  # MSYS/Git Bash 与 GNU bash 的路径语义不同（[ -s 目录 ] 在 MSYS 恒假）
```

工具版本真相源：`report/BUILD.md` 的 Vivado / Vitis 行与 `data/metrics.csv` 的"器件与工具链"行。

## 1. 四条便宜的只读复跑（每条 ≤ 2 分钟，不动工程）

| 目的 | 命令 | 跑完应看到（脚本自己打印的 token） |
| --- | --- | --- |
| 交付文档时效与指路 | `node src/host/doc_currency_check.mjs` | 末行 `CURRENCY: 干净`（不干净会打印 `N 条过期指路`） |
| 行号引用锚点 | `node src/host/line_cite_check.mjs` | `D5: CLEAN（退出码只由硬错决定…）` 与 `硬错 0 条` |
| 指标数字对回报告 | `node src/host/metric_recheck.mjs` | `== 数字对账：判 N 个数（… 红 0）…` |
| 编码与截断字节 | `node src/host/doc_enc_check.mjs` | `扫了 N 个手写文件：全部干净` |

三态口径：这四把尺子都只认自己读到的东西——被解析的文件缺失时它们报红或 `NOT_MEASURED`，
不会因为没有输入而判绿。反例怎么造见 `skill/scripts/selftest/`。

## 2. 一条完整的发布门禁（约 1 分钟一次）

```bash
bash build/gates.sh > /tmp/g1.txt 2>&1; grep -c ' PASS$' /tmp/g1.txt; grep -c ' FAIL$' /tmp/g1.txt
```

期望：判定项数由脚本自己打印（`GATES: …（判定 N 项）`），本仓库当前的基线是
**23 绿 / 1 红**，唯一红是**声明过的**台架项 `C5c`（原件 `build/tb_v98_report.txt` 里的
`FAIL C5c …` 与 `RESULT tb_v98_top_seam FAIL nfail=1`）。
⚠ 不要把输出直接重定向成它自己要读的那份 `build/rNN_gates.txt`（会在第一项之前截断基准件，
这条规矩写在 `build/gates.sh` 头部注释里）。红项集合要与上一跑逐条比对，不是比"绿的数量"。

## 3. 单个台架的双跑（先锚后改，15–21 秒级）

```bash
bash sim/run_one.sh tb_v98_top_seam        # 顶层台架（长，几十分钟级，需批准）
bash sim/run_one.sh <某个单元台架名>        # 单元台架才是便宜的那一类
```

判定 token 由 `sim/run_one.sh --verdict` 定义：`RESULT <tb> PASS` / `RESULT <tb> FAIL nfail=…`；
退出码 `3` = 台架判红、`1` = 编译失败、`4` = 认不出判定（这三件事不能混着念）。
双跑的正确做法：**先在未修改的树上跑绿**（旧设计是最便宜的对照），再改代码跑第二遍；
改了代码但没有锚绿 = 这条记录作废。

## 4. 指纹与"绑内容不绑行尾"

```bash
bash build/rtl_fingerprint.sh sim/tb_v98_top_seam.v | cut -c1-12
```

这是仓库自己的尺子（fpver=norm1，对 CR/LF 不敏感）。反例已经付过学费：
`find | xargs md5sum` 那一行曾经因为一次纯行尾差异把一轮正当采纳拦死（记在 `report/log/ISSUES.md`），
所以凡"证明这份报告出自这棵树"的判据，摘要必须在**编译之前**采集，且必须规范化后再取。

## 5. 需要批准才能跑的那两类（本手册不自动执行）

- 官方整构建（综合 + 实现 + 位流）：以分钟计的长任务，产物会覆盖 `build/*.rpt`；
  跑之前确认没有在飞的链子（`build/*.rpt` 不能两版混读）。
- 快车道（从 `impl_1/*_opt.dcp` 重跑 place+route）：约 7–9 分钟，是判定"跨构建的 WNS 移动是真的还是骰子"
  的廉价反事实；这台机器上放置是确定性的（同一份 dcp 重跑逐位复现正式构建的读数）。
- 上板与串口：`build/board_verify.sh`、`build/r116_bit_cycle.sh` 会驱动 COM6 并重写被跟踪的凭据；
  COM6 被别的终端占用时会 `UnauthorizedAccessException`——那是环境占用，不是回归。

以上三类没跑之前，引用它们的条目状态一律是 `【待验证】`。
