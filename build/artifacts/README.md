# `build/artifacts/` —— 归档命名规则与「规则 vs 现状」对照

这一页只回答两个问题：**每一轮构建的产物应该放哪、叫什么**；以及**现在实际放在哪**。
两份东西不一样，所以两份都写，不许只写规则把现状藏起来（现状见第 4 节对照表）。

本目录**不放二进制**。位流 / XSA / ELF 的字节都在 `build/` 与 `build/evidence/` 的既有路径上（第 4 节），
这里只放规则与本说明 ⇒ 谁照本目录找一个 2 MB 的 `.bit`，那个文件不存在，这是**故意的**。

## 1. 目录名规则

```
<日期>-<工具版本>-<指纹前8位>
```

| 段 | 取值口径 | 本次的例子 | 取不到时怎么办 |
|---|---|---|---|
| 日期 | `YYYYMMDD`，取**构建会话起**那一天的本机日期，不取拷贝/提交时间 | `20261004`（`build/r118_build_console.txt:6` 的 `Start of session at: Sun Oct  4 04:18:27 2026`） | 没有构建日志 ⇒ 这一轮不该有归档目录 |
| 工具版本 | 构建横幅第 1 行的 `vXXXX.Y.N`，去掉前导 `v` | `2025.2.1`（同文件 `:1`） | 横幅不在 ⇒ 版本未知，**不许沿用上一轮的版本号**；先补 `vivado -version` 原文 |
| 指纹前 8 位 | `bash build/rtl_fingerprint.sh` 输出的 `rtl=` 那串的前 8 位（尺子只有这一把，`fpver=norm1`） | `07570b1a`（来自 `rtl=07570b1ac1b4`，`build/evidence/r118_tree_fp.txt`） | 空指纹不许当名字的一部分（`build/r116_chain.sh:23` 就是这个 REFUSE）⇒ 不起目录 |

r118 若按本规则命名，目录名是：

```
build/artifacts/20261004-2025.2.1-07570b1a/          # 示例名：本轮没有落这个目录，所以它不在盘上、也不随包
```

**同名即停，不静默替换**：若目标目录已存在，脚本要打印两个目录里各文件的 md5 并退出非 0，
由人来判"这是同一份（那就不必再归档）"还是"同名不同物（那要改日期或补时刻段）"。
本轮没有任何一次这样的运行 ⇒ 这一条的行为**未验证**（`NOT_MEASURED`）。

## 2. 一个轮次目录里该放哪些件（成对，缺一就不算归档）

| 类别 | 件 | 为什么必须在 |
|---|---|---|
| 产物 | `system.bit`、`system.xsa` | 被采纳的就是这两件；`report/` 侧数字都从它们来 |
| 产物 | `ps_app.elf` | **只有本轮真的重编过才放**。沿用上一版 ELF 时放一份 `ELF-NOT-REBUILT.txt` 写清沿用的是哪一版、mtime、md5（否则会被误读成同一次生的） |
| 报告 | `timing_summary.rpt`、`utilization.rpt`、`power.rpt`、`route_status.rpt`、`methodology.rpt`、`cdc.rpt`、`clock_util.rpt` | 入口脚本本来就在 `build/` 落的那 7 份（`build/tcl/build_system_axigpio.tcl:343-351`） |
| 证据 | 构建会话日志（当轮 `rNN_build_console.txt`）、门禁件（当轮 `rNN_gates.txt`） | 与报告**成对**：只有报告没有日志 ⇒ 报告不可信（`build/provenance.md` 第 6 节的声明） |
| 证据 | 指纹记录（`rtl_fingerprint.sh` 的四行原文） | 目录名第三段就是它，必须能自证 |
| 证据 | `width_warnings.txt`、`multi_driven.txt` | 门禁第 8 项的凭据；单独一份报告配不上它 |
| 判读 | 名册与差分（`rNN_after_roster_probefmt.txt`、`rNN_roster_diff_vs_rNNbase.txt`、严格口径那份） | 采纳/否决的直接依据（`build/r118_chain.sh:38-45`） |
| 状态 | `ADOPTED` / `DECLINED` / `NOT-ADOPTED` 之一 + 一句为什么 | 只留产物不留判定，下一轮就会把被否决的位流当好的用 |
| 索引 | `MANIFEST.md5`（目录内每个文件的 md5） | 现成的写法照 `build/freeze_evidence.sh`；现场只认 md5 不认文件名 |

## 3. 现在实际放在哪（**这些路径本轮一个都没动**）

| 现状路径 | 是什么 | 摘要（本次实算，md5 前 12） |
|---|---|---|
| `build/system.bit` | 当前采纳位流（r118） | `cd04907e1369` |
| `build/evidence/r118_bit/system.bit` + 同目录 `md5.txt` | 采纳副本 + 身份条 | `cd04907e1369` |
| `build/system.xsa` | 当前硬件平台 | `934ebdbaa13b` |
| `build/ps_app.elf` | 当前固件（**非本轮所生**，mtime 2026-10-01 00:12） | `d0b07f84a068` |
| `build/{timing_summary,utilization,power,route_status,methodology,cdc,clock_util}.rpt` | 当前 7 份报告 | 见 `build/provenance.md` 第 5 节 |
| `build/evidence/r118_*.txt`、`build/r118_*` | r118 的判读与链上时间线 | 逐个指路在 `build/provenance.md` |
| `build/evidence_r63b … r75`、`build/frozen_r13 … r24_*` | 历史成套冻结目录（带 `MANIFEST.md5`） | 最后一次成套冻结在 r75 附近（盘上目录名序） |

## 4. 规则 vs 现状：差距逐条登记（不粉饰）

| # | 规则要求 | 现状 | 判定 | 处置建议（不由本目录决定） |
|---|---|---|---|---|
| A1 | 每轮一个 `<日期>-<版本>-<指纹8>` 目录 | **一个都没有**：`build/artifacts/` 今天才建，里面只有本页 | 规则未落地 | 下一轮构建时由脚本创建，别手工补 |
| A2 | 不覆盖既有产物 | 入口脚本对位流是 `file copy -force`（`build/tcl/build_system_axigpio.tcl:341`）、对工程是 `create_project … -force`（`:9`）、`write_hw_platform -force`（`:352`）⇒ 跑一次原地换一次 | **与规则相反** | 要满足就得改入口脚本；本轮不改（边界：不改已入库件） |
| A3 | 重名要提示并停 | 无此逻辑（没有任何一处比较归档目录名） | 缺 | 同上 |
| A4 | 构建脚本不写 `src/` | 现行入口与 r118 链都不写（链里只在 `build/r118_chain.sh:29` 读 `grep`）。但**这句不能笼统写**：历史开发轮脚本 `build/r90_phase2.sh:65` 有一次 `cp` 回滚写回 `src/rtl/eth/icmp_rx.v` | 现行合规，历史有先例 | 新脚本沿用"只读 src"，回滚走 `git checkout` 而不是 cp |
| A5 | 报告与证据成对 | 报告 + 位流已入库，构建日志与门禁件未入库（`build/provenance.md` 缺口 G3） | 不成对 | 下一轮一起 `git add` |
| A6 | ELF 与位流同源或写明沿用 | ELF 比位流旧 3 天且无人写明（`build/provenance.md` 缺口 G2） | 缺声明 | 放一份 `ELF-NOT-REBUILT.txt`（第 2 节那条） |
| A7 | 冻结前的门禁要求 | `build/freeze_evidence.sh:26-30` 只接 `GATES: ALL PASS`；r118 的门禁是 `有红项（判定 24 项）` | 现行尺子会把 r118 拒之门外 | 这是**口径冲突**不是 bug：要么按规矩不冻结，要么队伍改口径；本目录不擅自放宽 |

## 5. 通用性（换题目/换板卡要改哪几处）

- 三段名字里的"工具版本"与"指纹 8 位"是**取法**而不是值：换 Vivado 大版本、换成 Intel/ lattice 类工具时，
  第一段仍取会话起，第二段取该工具横幅的版本串，第三段取**该仓库唯一那把规范化行尾后的指纹尺子**（若没有，先造一把再造归档）。
- 第 2 节的报告清单是 Vivado 的 7 份；换流程时保留的是"产物 / 报告 / 证据 / 判读 / 状态 / 索引"这**六类**，件名可换。
- 第 4 节 A2/A3 这类"原地覆盖"问题与工具无关：**只要归档目录名不含时间或指纹，就会覆盖**——这一条迁移到任何题目都成立。
