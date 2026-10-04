---
name: host-bindings-and-reports
description: 从寄存器/接口契约表把主机侧读数代码立起来，并让性能与资源数字进表而不是进手抄。当出现"文档里的数与报告里的数不一致"、"读数被两个实现各译一遍还互相打脸"、"演示命令表与固件各说各话"、需要给黄金参考/性能资源报告配机器判据、或要为一次采纳把改前/改后读数成套留档时使用。本工程的主机侧是 Node/Python 脚本 + JTAG，不是 PYNQ。
---

## 1. 一句话用途

主机侧读数按契约表建，报告数字按原件进表。

## 2. 适用场景

- 当同一份位图/协议需要被"设备侧 + 台架 + 主机脚本"三个读者各自解释，而三者已经开始不一致时。
- 当交付文档里的某个数字（WNS、资源占用、吞吐）与最新一份工具报告不符，需要一条命令抓出这种漂移时。
- 当主机脚本把读不到的键打成 `?` 或 `0`，看起来像"硬件没有这个计数器"时。
- 当"计数=0"的判据在系统没在跑的时候也会绿（零样本通过）时。
- 当演示/验收清单里的命令是手抄进文档的，需要证明"文档里没有一条命令是设备不认的"时。
- 当采纳一笔改动之前需要把"改前读数"成套问回来（否则工件会被下一次构建原地覆盖）时。

## 3. 不适用 / 失效条件

- 不适用"从契约表自动产出主机侧绑定代码"的生成器路线：**本工程没有生成器**，位图是手抄进 `src/ps/main.c` 与 `src/host/health_read.mjs` 两处、再由检查器对账的 ⇒ 本条第 5.1 节写的是"没有生成器时怎么保证一致"，生成器写法本身一律 `【未实测】`。
- 不适用 Linux 用户态驱动 + `/dev/mem`/UIO 的绑定生成（字段名、字节序、并发语义与调试器 `mrd` 不同）。
- 不适用只有软件、没有硬件读数出口的项目：本条一半判据是围绕"读数出口"建的。
- 若报告文件名或字段名换了（换 Vivado 主版本、换报告模板），本条列出的解析形状会失效，必须先重核解析行而不是先信绿。
- 不适合作为"性能声明"的来源：表里 `未报`/`未定` 那几行是刻意留空的（`data/metrics.csv` 第 20、24 行的口径就是"没有复核过的数不填"）。

## 4. 前置条件

- 工具与版本：Node 24（`src/host/*.mjs` 上位机取证类工具，`report/BUILD.md` §1 表"需要 Node 24，**不在演示主链路上**"）；Python 3 + `VP_VIVADO_BIN`（仿真/构建侧脚本）；Vivado/Vitis 2025.2.1（本条写作版本）。
- 需要的输入文件（本仓真实存在的路径）：
  - 契约表：`report/ARCHITECTURE.md` 第 4 节（寄存器映射）与 `report/COMMANDS.md`（命令表）。
  - 读数脚本：`src/host/health_read.mjs`、`src/host/ddr_verify.mjs`、`src/host/lane30_watch.mjs`、`src/host/metrics.mjs`。
  - 对账脚本：`src/host/metric_recheck.mjs`、`src/host/line_cite_check.mjs`、`src/host/doc_currency_check.mjs`、`src/host/uart_cmd_check.mjs`、`src/host/pipe_len_check.mjs`。
  - 原件报告：`build/timing_summary.rpt`、`build/utilization.rpt`、`build/power.rpt`、`build/cdc.rpt`、`build/methodology.rpt`、`build/route_status.rpt`。
  - 指标表：`data/metrics.csv`（列顺序：指标名称,类别,数值,单位,测量条件,测试次数或时长,证据文件）。
- 需要的权限或硬件连接状态：读数类需要 JTAG 可达与 `VP_XSDB`；纯对账类不需要板子（`metric_recheck`/`line_cite_check` 只读盘上文件）。

## 5. 使用方法

### 5.1 主机侧读数代码：三处读者 + 每处自带判据（本仓路线，无生成器）

契约表被三个读者解释，本仓的规矩是"每个读者都要能自己变红"：

1. 设备侧（位定义唯一出处）：`src/rtl/process/proc_pipeline.v` 文件头 → 固件 `src/ps/main.c` 抄一份宏，并在注释里点名"这里只是抄一份"。 （本仓示例取值，迁移时按自身工程替换）
2. 台架（证明硬件里那位的内容）：`sim/` 下对应台架，例如 lane23 由 `tb_v95_zoom_snap.v` 的 Z2 段逐字段钉住。 （本仓示例取值，迁移时按自身工程替换）
3. 主机脚本（第二个独立实现）：`src/host/health_read.mjs` 里 `decodeSrc()` / `decodeZoom()` 各自是一份独立译码，**它自己也要有判据**（`--selfcheck`；文件头原话："否则'读回 0x310'被译成'没有流'而其实位挪了一格，板级报告就会把一句译码错误写成结论"）。

改表时的三步（顺序不可交换）：

```bash
node src/host/pipe_len_check.mjs        # 命令/位图口径离线核对（不碰板子）
node src/host/ps_hb_check.mjs --self    # 源码原文级约定 + 变异对照（检查器自己必须能红）
node src/host/health_read.mjs --selfcheck  # 主机侧那份独立译码的自判据
```

"生成器"这一路线本仓未实现 ⇒ 若要照搬，需要自建契约表→绑定的生成脚本并补一层"生成物与原件一致"的判据，`【未实测】`。

### 5.2 读数出口的形状决定判据能不能用（三条硬规矩）

- 读不到必须说读不到：把读不到的键打成 `ABSENT` 而不是 `?`/`0`。这条来自实测——内联 `node -e` 里的正则被 shell 吃掉一层转义，三个计数器全打成 `?`，"看着像'板子没这个计数器'，其实是尺子坏了"（`report/log/ISSUES.md` `#318`）。
- 单调性按 lane 分列，不一刀切：`src/host/health_read.mjs` 里 `MONO = new Set([0,1,5,6,8,9])` 与 `LIVE = new Set([2,3,4,7])` 两集分开——单调 lane 只有"第二遍比第一遍小"才是撕烈，非单调 lane 两遍不等是正常的，只标注不报错。
- 零样本不算通过：凡是"计数=0"的板侧判据，必须同一份读数里带上"流量活着"那一位，否则判红（`report/log/ISSUES.md` `#316` 立的规矩，并写进 `build/r116_bit_cycle.sh` 文件头："为什么必须带流读数"）。

一条可复跑的读数命令（`--json` 供机器判据消费）：

```bash
node src/host/health_read.mjs --json
# 前置：板子已 ps7_init、位流已下、hw_server 在跑，VP_XSDB 已设
# 完成后应看到：一份 JSON，含 10 条 lane 的译码结果与两遍读的比对结论
```

### 5.3 性能与资源报告：数字只从原件抄，抄完立刻对账

一条命令做完"推流 N 秒 → 读回硬件计数器 → 算成指标 → 原始读数一起存档"：

```bash
node src/host/metrics.mjs --fps 30 --seconds 20 --tag rNN
node src/host/metrics.mjs --selftest          # 不打板子，只验算式本身
# 完成后应看到：算好的指标 + 原始 JSON 一起入库（任何结论都能回查到最初那几个数）
```

为什么采集与计算必须同一条命令：`src/host/metrics.mjs` 文件头记着第一版把"平均帧间隔"的分母写成帧数，而硬件里 `gap_sum` 是 N−1 段 ⇒ fps 被低估约 1/N；这条现在由 `--selftest` 钉住（同族记录另见 `skill/metrics_gap_sum.md`）。

数字进表之后的对账（不需要板子，只读盘上文件）：

```bash
node src/host/metric_recheck.mjs              # 把 CSV/首页的每个数对回它自己点名的那份报告
node src/host/metric_recheck.mjs --self        # 自检：塞一条故意写错的行必须变红
node src/host/line_cite_check.mjs             # 文档里的行号锚点是否还指着那件事
node src/host/doc_currency_check.mjs          # 文档念的是不是当前这一版工件
# 完成后应看到：`红 0` 与 `CURRENCY: 干净`；认不出的行数会被打印条数，不静默放过
```

改口（把过期的数换回报告值）用两步而不是手抄：

```bash
node build/rotate_from_metric.mjs --check     # 第一遍：只搬"那一行里这个数恰好出现一次"的机械行
node build/rotate_from_metric.mjs --apply     # 落盘；剩下认不出的形状逐条列规则
node src/host/metric_recheck.mjs              # 收尾必须红 0，否则不许宣称改完
```

它自己的限度已实测并写进脚本头：把首页退回采纳前那一版再让它自动改，"31 条改对、**52 条拒绝**、四轮没收敛"⇒ 它是第一遍，不是"一条命令搞定改口"。

### 5.4 黄金参考：本仓的真实状态与可用判据

- 软件侧参考图在 `data/golden/`，但该目录自己的说明就写着它们是**人眼比对的参照物**、不是任何台架的输入，并且"在补出来之前，任何'与黄金参考逐像素一致'的说法都不成立"（`data/golden/README.md`）⇒ 逐像素黄金参考在本仓 `【待验证】`。
- 机器可判的"黄金"在本仓是另外两种形状：① 由定义式**推导**期望值而不是抄表 —— `src/host/health_read.mjs` 的 `inv_exp_of(i) = min(1023, round(25600 / ZOOM_X100[i]))`，注释写明这样"表被谁改了一个数"是推导出来的红，而不是两边一起改的假绿；② 检查器自带变异对照 —— `sim/mut_control.sh` 5 条分支，规矩是"一次变异只许红它声称红的那一条"（`data/metrics.csv` 第 16 行）。
- 顶层整屏逐像素判据走的是台架件而不是 golden 目录：`build/tb_v98_report.txt` 头部带 provenance 指纹，表里那一格的数值直接由该文件的 `^PASS`/`^FAIL` 行数相加得来（`data/metrics.csv` 第 15 行）。

### 5.5 改前/改后读数：成套留档

```bash
bash build/pre_readings.sh rNN_before        # 构建之前把改前读数问回来，落 build/evidence/rNN_before.txt
bash build/gates.sh                          # 构建之后读当前这套报告，判据逐条打结果
bash build/gates.sh build/frozen_rNN_<短名>   # 复核某一组成套冻结件
# 完成后应看到：pre_readings 三份时钟都打到（退出码 0）；gates 全绿才可采纳
```

退出码口径写在脚本里：`2` = 前置坏了（没有 DCP / 没有 Vivado / 没给标签）、`3` = 有一腿一条路径都没打到（"空读数不许当读数用"）。

### 5.6 PYNQ 对位写法

| 本条机制 | PYNQ 对位写法（本次打开到的原文） | 本工程形态 | 版本相关列 |
| --- | --- | --- | --- |
| 契约表 → 主机侧读数 | 按名取块后按字段读写：`add_ip.register_map.a = 3` / `add_ip.write(0x10, 4)` / `add_ip.read(0x20)`；底层 `MMIO(IP_BASE_ADDRESS, ADDRESS_RANGE)` 配 `mmio.write(ADDRESS_OFFSET, data)` | 手写两份独立译码 + 检查器对账 | 字段名访问：PYNQ v2.5.1；`MMIO`：v3.1 页面。两版之外 `【核对】` |
| 缓冲区的"物理连续/对齐"要求 | `pynq.allocate`："allocates memory which is physically contiguous and returns a `pynq.Buffer`"；属性文档写 "`coherent` is True if the buffer is cache-coherent between the PS and PL" | PS 侧直接用固定 DDR 地址（`0x10100000` 等）+ 显式 flush | `allocate`：PYNQ v2.5.1；v3.x 的 Buffer API `【核对】` |
| 读数进指标表 | 无对位物：PYNQ 文档没有指标表这一层，需自建 | `data/metrics.csv` + `metric_recheck.mjs` 对账 | 与版本无关 |
| 演示命令表与设备核对 | 对位写法是把清单写成可执行 notebook 并逐格 assert 输出；本仓没做 notebook 形态 | `node src/host/demo_cmds.mjs --emit/--check`（从 `report/DEMO_SCRIPT.md` 的代码块抽命令，再对着串口回包判"没有一条是板子不认的/硬件待接"） | 与版本无关 |
| 主机侧代码由契约生成 | PYNQ 的自动对位物是"从硬件手递文件生成设备树，再按名解析"这条链（overlay 必须成对提供 `.bit` 与硬件描述文件）；它生成的是**访问能力**，不是校验代码 | 无生成器 | PYNQ v2.5.1 原文那句"to use the overlay class, a `.bit` and `.tcl` must be provided for an overlay"；新版本是否仍要求 `.tcl` `【核对】` |

## 6. 判读与失败分叉

| 命令 | 通过 | 失败 | 读不到输入 |
| --- | --- | --- | --- |
| `node src/host/metric_recheck.mjs` | `红 0` ⇒ 数字与原件一致 | 出现 `RED row=<文件:行号> … 首页=… 报告=…` ⇒ 按 `--check` 跑 `build/rotate_from_metric.mjs` 搬机械的那批，剩下的逐条列规则 | 报告文件缺 ⇒ `NOT_MEASURED`；脚本明写"认不出的行算作未判并打印条数，不静默放过"，所以"没报红"≠"判过了" |
| `node src/host/metric_recheck.mjs --self` | 塞进去的错行变红 ⇒ 尺子有牙 | 错行没红 ⇒ 尺子失效，先修尺子再谈数字（本仓同族教训见 `report/log/ISSUES.md` `#321`：负 slack 读成 null 导致"写对也红"） | 无法构造样例 ⇒ `NOT_MEASURED` |
| `node src/host/health_read.mjs --json` | 两遍读单调 lane 不减、译码字段齐全 | 变小 ⇒ 采到快照刷新那一拍；`?`/缺键 ⇒ 先怀疑尺子（§5.2 第一条） | `[HEALTH] 读不到 GPIO_0 的当前值，拒绝继续` ⇒ `NOT_MEASURED`，本仓实测件 `build/evidence/r116_board/health_live1.json` |
| `node src/host/uart_cmd_check.mjs --dry` | 每条命令的正判据与 `!` 反判据都能列出来 | 电池里某条命令的正则永不匹配 ⇒ 该条从没判过（`report/log/ISSUES.md` `#74`：`pipe` 那 8 条一直是死的） | 板子不在 ⇒ 用 `--dry`，它不依赖板子 |
| `bash build/pre_readings.sh <标签>` | 退出码 0，三份时钟都打到 | 退出码 3 ⇒ 有一腿零路径，"空读数不许当读数用" | 退出码 2（没有 DCP / 没设 `VP_VIVADO_BIN`）⇒ `NOT_MEASURED`：连临时件都不该被创建 |
| `bash build/gates.sh` | 全绿 ⇒ 可采纳 | 任一项红 ⇒ 保留上一版，本轮挪去 `build/failed_rNN/` | 报告缺 ⇒ `NOT_MEASURED`。⚠ 不许把本脚本输出直接重定向成它自己要读的那份留档件（截断发生在第一项判据之前） |

## 7. 已验证的效果

- 数字对账确实能抓到手抄漂移（§5.3）
  - 复跑命令：`bash build/gates.sh`（内含 `metric_recheck` / `doc_currency_check` / `line_cite_check` 那三把尺子）
  - 输入路径：`data/metrics.csv`、`README.md` 首页表、`build/*.rpt`
  - 期望输出：`红 0` + `CURRENCY: 干净` + `D5: CLEAN`
  - 实际输出摘要：`build/evidence/r113_step5_gates3_console.txt`（2026-10-03 14:53:39–14:53:41）打出 `== 数字对账：判 68 个数（首页层 58 个／解析到 10/10 行；红 0）／csv 认领 10/10 行／其余 18 行不点名这三份报告 ==`、`CURRENCY: 干净`、`D5: CLEAN（退出码只由硬错决定…）`、`扫了 397 个手写文件：全部干净`，同一次还打出"门禁现状：24 项 23 绿 / 1 红"与"两跑逐字节一致 rc=1/1" ⇒ 判定 PASS。
  - 该尺子接入前抓到的真实漂移（基线对照）：`data/metrics.csv` 第 14 行记载 D6 接上"第一次就抓到首页四格还是 r103 的数"；同族的三次成因写在 `src/host/metric_recheck.mjs` 文件头（`#145`/`#138` 与"50 MHz 显示域 12 % 实为 5.9 %"的除错分母）。⇒ 判定 PASS（有件、有日期、有对照）。
- 零样本判据在坏样本上确实会红（§5.2 第三条）
  - 复跑命令：`node src/host/health_read.mjs --json`（对照 `report/log/ISSUES.md` `#316` 的两步）
  - 输入路径：板上 `build/system.bit`（本仓 r116/r118 各一轮）+ `src/host/video_sender.mjs` 图案流
  - 期望输出：`计数=0` 必须与 `eth_live=1` 同现
  - 实际输出摘要：`build/evidence/r118_board/bitcycle_console.txt`（2026-10-04 04:47:07）两次带流读数 `eth_live=1 owner_eth=1 drop_words=0`；同一次里 `pkt_err=?`、`frames_bad=?`、`drop_seen=?` 三个键是 `?` ⇒ 正是 §5.2 第一条的成因（内联正则被吃掉转义），落成 `build/r116_ab_summary.mjs` 之后才打成 `ABSENT`。⇒ 判定 PASS（两半都有件）。
- 检查器自己能红（§5.4）
  - 复跑命令：`python3 build/check_ports.py` 的三条反例 + `node src/host/metric_recheck.mjs --self`
  - 输入路径：`build/ports_check_width_ce.txt`（反例件，存在）
  - 期望输出：两条形状各覆盖一半（声明位宽 vs 端口位宽、字面量位宽 vs 端口位宽），未改动整棵树 `violations=0`
  - 实际输出摘要：判据与期望写在 `build/check_ports.py:22-27`，件 `build/ports_check_width_ce.txt` 在树里；本次没有重跑 ⇒ 单次运行输出摘要 `【待验证】`（要跑的是上面那条命令并把 stdout 存进 `build/evidence/`）。
- 黄金参考逐像素对账：`【待验证】` —— `data/golden/README.md` 自己声明这批 PNG 无法一键重跑、且全仓库没有任何脚本读它；本仓的逐像素判定实际发生在台架（`build/tb_v98_report.txt`），不是"与黄金参考比对"。
- 契约表 → 主机侧代码生成器：`【未实测】`，本工程不存在生成器（§3 第一条）。
- PYNQ 侧同类工作流：`【未实测】`，本仓无 PYNQ 运行件。

## 8. 提炼来源与边界

- 来源证据（点名文件与日志条目）：`src/host/metrics.mjs`、`src/host/metric_recheck.mjs`、`src/host/rotate_from_metric`（即 `build/rotate_from_metric.mjs`）、`src/host/health_read.mjs`、`src/host/uart_cmd_check.mjs`、`src/host/ps_hb_check.mjs`、`src/host/pipe_len_check.mjs`、`src/host/demo_cmds.mjs`、`src/host/ddr_stale.mjs`、`build/check_ports.py`、`build/pre_readings.sh`、`build/gates.sh`、`build/make_submission.sh`、`data/metrics.csv`（第 14/15/16/20/24 行的口径）、`data/golden/README.md`、`build/evidence/r113_step5_gates3_console.txt`、`build/evidence/r118_board/bitcycle_console.txt`、`build/evidence/r116_board/health_live1.json`、`report/log/ISSUES.md` 的 `#57`/`#59`/`#66`/`#74`/`#316`/`#318`/`#321`、`report/ARCHITECTURE.md:117-123`、`report/HOST_GUIDE.md`、`skill/metrics_gap_sum.md`。
- 恒成立 / 平台相关 / 版本相关：三处读者各自带判据、零样本不算通过、数字只从原件抄、改前读数成套留档 —— 恒成立；JTAG `mrd` 这种读数出口、GPIO lane 窗口、串口命令电池是平台相关（换 Linux/UIO 要整套换掉）；`metric_recheck` 认得的三份报告文件名与 CSV 列顺序、`check_ports.py` 能解析的端口表形状是版本相关（换工具主版本或换报告模板要先重核解析行）。
- 不再适用的条件：目标工程有真正的绑定生成器（§5.1 那套"手写两份 + 对账"就变成冗余）；读数出口变成寄存器映射文件（`/dev/mem` 之外还有 mmap 语义）；指标表没有点名原件报告（`metric_recheck` 会打印"未判"条数，等于没有这条判据）；无人复核的 PNG 参照图（本仓状态）。
- 迁移到新题目/新板卡要改的几处：① `data/metrics.csv` 的列与"点名哪三份报告"的白名单；② lane/读数出口的编号与单调性分组（`MONO`/`LIVE` 两个集合要重列）；③ 检查器认得的路径与文件名（本仓把 `build/`、`data/measured/`、`report/` 写死在脚本里，换目录结构要改）；④ 演示清单里"不算命令"的两类（PC 侧动作、需要手指的按键）按自身交互重列；⑤ 若要引入生成器，先补"生成物 vs 原件"的判据行再删本节 §3 第一条。
