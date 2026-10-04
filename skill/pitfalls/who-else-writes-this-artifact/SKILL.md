---
name: who-else-writes-this-artifact
description: 判"这份产物是谁、在什么时候、被谁写的"：当两个进程写同一份日志（头部 md5 全对而正文来自两跑）、当后台任务输出文件一直是 0 字节、当同名产物被下一次构建原地覆盖、当在飞构建期间跑文本尺子导致分母自己变化，或当在 MSYS 下用 ps -W 判 Windows 进程活性得出假"已经停了"时使用。
---

## 1. 一句话用途

先问这份件是谁写的，再读它的结论。

## 2. 适用场景

- 当一份 `run.log` / 控制台文件里出现两个时间段的行、或"上一跑的 C5c"与"这一跑的 C5c"拼在一起时。
- 当你用 `bash <脚本> | tail -45` 起后台任务，输出文件一直是 **0 字节**时。
- 当报告与位流同名（`build/system.bit`、`build/*.rpt`）而内容会被下一次构建原地覆盖，你正要引用"上一版"的读数时。
- 当聚合判据的"判 N 个数"在两次读数之间自己变小，你怀疑解析器射程缩了时。
- 当你写的看守/重试逻辑用 `ps -W | grep <name>.exe` 判"还在跑吗"时。
- 当 `ls -l --time-style=+…` 给的时间和 `git status`/`stat` 不一致时。

## 3. 不适用 / 失效条件

- 不适用：产物由带锁的单写者工具生成（例如每次跑新建一个带时间戳的运行目录）——那时本条只剩"同名覆盖"那一半。
- 不适用：报错来自设计/工具本身（先按报错原文判对象）。
- 失效：`tasklist` 是 Windows 命令；Linux/WSL 主机改用 `pgrep -a` 之类，本条的进程探针形状要整段替换。
- 失效：本仓 md5 绑定这套做法依赖脚本自己在编译**之前**写 `prov.txt`（`sim/run_one.sh:73-95`）；换工程若无等价出处记录，"认 md5"救不了你，见第 5 节步骤 5 的替代动作。
- 不许越界：本条不授权你去杀别人的进程；它只要求"先问是谁的那一跑"。

## 4. 前置条件

- `stat`、`md5sum`、`find -newer`、（Windows）`tasklist`；本仓形状 `tasklist //FI "IMAGENAME eq xsim.exe"`（双斜杠是 MSYS 的参数换算，见 `win-bash-path-split`）。
- 各脚本的运行目录约定：本仓单台架跑在 `/tmp/kx/<tb>.run/`（`sim/run_one.sh:49`），同一时刻只允许一个 xsim 写它。
- 一份"本轮产物清单"（本仓：`build/evidence/<本轮>/` 与冻结目录 `MANIFEST.md5`）。
- 长流程在飞期间**不动** `src/`、`sim/`（本仓纪律，事故见 `report/log/ISSUES.md` #225 与第 11416 行"今天构建在飞 ⇒ 不动 `src/rtl`"）。

## 5. 使用方法

1. 读任何产物前先问它是谁写的：`stat -c '%y %n' build/timing_summary.rpt`（示例取值）。
   完成后应看到：一个精确到秒的 mtime；**不要**用 `ls --time-style=+…` 当凭据（本仓实测这台机上它不可信，`report/log/ISSUES.md` 2026-10-02 00:46 一节）。
2. 判有没有别的进程正在写同一类产物：
   `tasklist //FI "IMAGENAME eq xsim.exe"`（Windows）/ `pgrep -a xsim`（Linux）。
   完成后应看到：0 行或明确的 PID 列表；本仓形状是门口先数、非空就 `REFUSE: 已经有 xsim 在跑（它会把行写进同一份 run.log）` 并 `exit 3`（`sim/run_one.sh:58-60`）。
3. 后台任务的输出改成"直接重定向到文件"，不要过管道：
   `bash sim/run_one.sh <tb> > /tmp/kx/<tb>_console_rNN.txt 2>&1`（示例取值）。
   完成后应看到：文件持续增长；轮询的是这份文件与 `run.log`，而不是 `| tail` 的那个 0 字节结果。
4. 混版本判别：把时间戳排在一起看是否属于一次构建
   （本仓形状 `build/gates.sh:38-50`：bit 与报告 mtime 相差 > 600 秒就打印 `WARN 两者相差 …`）。
   完成后应看到：要么相差在阈值内，要么你换成一组成套冻结件再读。
5. 用身份而不是文件名绑定一跑：读产物头部记录的指纹（本仓 `build/tb_v98_report.txt` 头部
   `# provenance fpver=norm1 top_md5=… tb_md5=… rtl_md5=… date=…`），再与树里现值比
   （本仓由 `build/rtl_fingerprint.sh --match` 给 `fresh`/`bridge`/`no` 三态答案）。
   完成后应看到：明确的 `fresh`；若 `no`，说明这份报告不算当前树。
6. 分母漂移检查：把"判 N 个数 / 判定 N 项"这类汇总行**连同红数**一起记；红数变化时 N 也可能合法变化。
   完成后应看到：你写下的结论区分"红变多所以绿变少"与"解析器读不到了"（本仓形状见 `report/log/ISSUES.md` #225）。
7. 需要拿旧版做 A/B 时，回刷旧位流再读，而不是读同名文件里"以为还是旧的"那一份
   （本仓形状：`VP_BIT=build/evidence/<旧轮>/system.bit` 那条回刷链，四个读数逐格相同，`report/log/ISSUES.md` #318）。
   完成后应看到：两组读数各自点名自己的 bit md5。

## 6. 判读与失败分叉

- 步骤 1：
  通过 = mtime 落在你预期的那一次运行窗口内。
  失败 = mtime 比你以为的更早/更晚 ⇒ `FAIL`，产物被别的动作覆盖过（本仓 2026-10-02 00:46 那节记的正是"我把『仍是 r103』写进三处档案，而 bit 早在 23:26 被覆盖"）。
  读不到输入 = stat 报错 ⇒ `NOT_MEASURED`，先确认路径与目录（冻结目录缺文件会回落到 `build/`，见 `build/gates.sh:26`）。
- 步骤 2：
  通过 = 没有活的写者。
  失败 = 有 ⇒ `FAIL`（阻塞而非结论）：先问那一跑是谁要的，本仓明确不自动杀（`sim/run_one.sh:55-56` 注释）。
  读不到输入 = `tasklist` 不可用（换主机）⇒ `NOT_MEASURED`，改 `pgrep`；`ps -W` 不算可用（看不到 Windows 映像名，`report/log/ISSUES.md` #244）。
- 步骤 3：
  通过 = 文件有内容且在长。
  失败 = 0 字节 ⇒ 先分两种：管道未刷（本仓 #225 同段的流程账记的就是这个形状）或进程没跑；按步骤 2 判。
  读不到输入 = 文件不存在 ⇒ `NOT_MEASURED`，路径拼错或被清理脚本删（本仓 `build/cleanup_wip.sh` 会保护被文档点过名的目录）。
- 步骤 4：
  通过 = 相差在阈值内且 md5 成套。
  失败 = 相差大 ⇒ `FAIL`，改用冻结件目录重跑聚合判据。
  读不到输入 = 位流不在该目录（本仓会回落到 `build/system.bit` 再判）⇒ `NOT_MEASURED`，别把回落读成"是同一套"。
- 步骤 5：
  通过 = `fresh`。
  失败 = `no`/`ERR`/空 ⇒ `FAIL`：报告与当前树不是同一次跑（本仓 `build/gates.sh:335-345` 把"尺子没答"也算红）。
  读不到输入 = 头部没有 provenance 行（历史冻结件本来就没有）⇒ `NOT_MEASURED`，本仓做法是把这一项打成 `n/a` 而不是判红（`build/gates.sh:366`）。
- 步骤 6：
  通过 = N 的变化能用红数变化解释。
  失败 = 解释不了 ⇒ `FAIL`，先跑那把尺子的 `--self` 对照再下"射程缩了"的结论。
  读不到输入 = 汇总行没有数字 ⇒ `NOT_MEASURED`，回到 `checker-ran-on-nothing` 步骤 3。
- 步骤 7：
  通过 = 两组读数各自有 bit 身份。
  失败 = 只有当前 bit 一组 ⇒ `FAIL`（无对照），不许写"这版没问题"。
  读不到输入 = 旧 bit 实体不在（只留了校验和）⇒ `NOT_MEASURED`，本仓 `report/BUILD.md` §7 规矩 1 就是为这种情况写的（冻结必须是实体拷贝）。

## 7. 已验证的效果

- 本轮实跑（2026-10-04，只读）：
  `grep -a "provenance" build/tb_v98_report.txt` 打出头部
  `# provenance fpver=norm1 top_md5=56c269602e18 tb_md5=1c918c92200f rtl_md5=07570b1ac1b4 date=2026-10-04T01:47:53+08:00 src=/tmp/kx/tb_v98_top_seam.run/run.log`；
  而 `data/metrics.csv` 第 15 行点名的同一文件名头像是 `top_md5=2bf2ceeede07 … 日期 2026-10-02 01:15`，计数 140 PASS/1 FAIL。
  本轮实测该文件当前是 161 个 `^PASS` + 1 个 `^FAIL` ⇒ **同名文件已被原地覆盖**，引用它的文档行需要按本轮身份改写（这正是本条要防的形状；改文档本身不在本轮范围内，因为我不被允许改 `data/`）。
- 本轮实跑（2026-10-04）：`md5sum build/system.bit` 与 `git show HEAD:build/system.bit | md5sum` 都是 `cd04907e1369`
  ⇒ 位流身份当前自洽（对照件 `board/ACCEPTANCE.md` E6 行点名的 r118 身份）。
- 基线（不用本条，历史件）：`report/log/ISSUES.md` 2026-09-27 12:48 一节（现抄在 `sim/run_one.sh:50-54`）——第二次 `run_one.sh` 不会让第一次停下，两个 xsim 往同一份 `run.log` 写，`tb98_report.sh` 把"上一跑的 C5c"与"这一跑的 C5c"拼成一份报告，而它头部 md5 全对。
- 基线（进程探针）：`report/log/ISSUES.md` #244（2026-10-03 02:55）——`ps -W | grep -qi "vivado.exe"` 恒不匹配（这台 MSYS 把映像名截成 `D:\Sof` 这种路径前缀），看守因此报假警；真值由 `tasklist //FI "IMAGENAME eq vivado.exe"` 数到 2 个。
- 基线（在飞混读）：`report/log/ISSUES.md` #225（2026-10-02 12:4x）——构建在飞时跑文本尺子，`metric_recheck` 汇总从「判 59 个数」掉到「判 52 个数」，真因是计数口径只对绿行 `judged++`。
- 未验证：本轮没有并发起重复跑来做"两写者"判别实验（会污染现场），所以步骤 2/3 的当前可复现性记 `【待验证】`。

## 8. 提炼来源与边界

- 证据：`sim/run_one.sh:49-61`、`sim/run_one.sh:73-95`（编译前记指纹）、`sim/run_one.sh:101`（编译成功才发布 prov 并删旧 run.log，#169）；
  `build/gates.sh:26`（回落）、`build/gates.sh:38-57`（新鲜度与"有 RTL 比 bit 新"）、`build/gates.sh:335-345`、`build/gates.sh:366`；
  `report/log/ISSUES.md` #169/#225/#244/#318 与 2026-09-27、2026-10-02 两个日期小节；`report/BUILD.md` §7（同名覆盖与实体冻结）。
- 件：`build/tb_v98_report.txt`、`data/metrics.csv`、`build/system.bit`、`build/r109_lane_before.txt`（坏尺子活标本，台账点名）。
- 工具行为断言的来源行见 `skill/pitfalls/_proposed-sources.md`。
- 停止适用的条件：每跑一个独占运行目录 + 每版产物独立命名 + 聚合判据自带身份行时，本条降级为"读身份行"一步。
- 迁移到新题目/新板卡要改的地方：
  1. 进程名与探针（`xsim.exe`/`vivado.exe`/`xsdb` 是本仓工具栈，示例取值）；
  2. 运行目录约定（本仓 `/tmp/kx/<tb>.run`；在 Windows 上还要记住工具的 `/tmp` 是另一处，见 `win-bash-path-split`）；
  3. 新鲜度阈值（本仓 600 秒是"一次构建里 bit 先写、报告后写只差几十秒"量出来的，换构建时长必须重推）；
  4. 指纹定义处（本仓集中在 `build/rtl_fingerprint.sh` 的 `norm1`，去 CR 后再算；换语言/换行规范要重定义）。
