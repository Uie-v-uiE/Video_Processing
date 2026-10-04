---
name: repro_check
description: 可复现性双向检查：编译前 capture 源码树指纹（去 CR 与行尾空白后才取摘要，绑内容不绑行尾），编译后 verify 把证据与报告头对账（同源、同工具版本、采集必须早于构建、与仓库既有尺子口径可互算、成套产物 md5 清单），并成对提交——只给一件的另一件一律 NOT_MEASURED。当症状是"报告说的源码树和盘上不是同一棵""换台机器指纹全漂""CRLF 改了 md5 也跟着变"时使用。不调 Vivado、不起子进程、不写工程目录；也不证明设计正确性，只证明同源同版。
---

## 1. 一句话用途

证明"这份报告出自这棵树、这个工具版本"。

## 2. 适用场景

- 编译**之前**要留一份源码树身份（`capture`），编译**之后**用现成报告回对（`verify`）时。
- 怀疑"编译后才补采指纹"（那样任何报告都能被事后匹配）⇒ V5 用时间先后卡住。
- 跨机器/跨 checkout 比对指纹：行尾（CRLF/LF）与每行行尾空白不许动指纹，改一个字符必须动指纹 ⇒ V2 四条一起判。
- 与仓库既有尺子（本仓示例：`build/rtl_fingerprint.sh` 的 `norm1` 口径，需按自身工程替换）对账 ⇒ V6 要求它记的 `rtl=<12位摘要>` 能被本脚本同形重算出来。
- 交付要一份成套产物的 md5 清单 ⇒ V7 正向核对每个条目存在且摘要对得上；`--strict-set` 时反向的"盘上有而清单没点名"也判。

## 3. 不适用 / 失效条件

- 想证明"设计是对的"：本脚本只证同源同版，时序/资源结论各有自己的判据件。
- `--root` 指向 cwd 之外的目录（跨盘符尤其）：V6 的 `cwdrel` 扫描会抛 `ENOENT`（`repro_check.mjs:93`），整跑 exit 1 且**不打印任何判据行**。约定是"`--root` 只能是工程源码目录（`src/…`、`sim/…`）且与 cwd 同树"；要在别处跑就把 cwd 一起换掉（本仓 `run_all.sh` 的 REPRO 段就是在临时目录里当 cwd 跑）。
- 只交一份：证据文件或报告缺一份 ⇒ V4 `NOT_MEASURED`，另一份因此不可信（这是设计，不是缺陷）。
- 工具版本对不上或报告头没有 `| Tool Version :` / `| Date :` 行 ⇒ V3 判红或 `NOT_MEASURED`；`--declare` 不给或点名的键那行没有版本号 ⇒ 不判（`NOT_MEASURED`），不默认放行。
- 时区：`captured_at` 带 `Z` 或 `±hh:mm` 按标注换算，**不带时区按本机本地时间**读；Vivado 报告头的 Date 是本地时间。跨时区机器上把 `--stamp` 显式写成带偏移的形式，否则先后关系会判反。
- 不许写工程目录：`--out-dir` 落在 `src/`、`sim/`、`build/`、`board/`、`data/`、`report/`、`docs/` ⇒ exit 3。`--root` 只读。

## 4. 前置条件

- 工具探针：**本脚本不调任何外部工具**（源码 `import` 了 `execFileSync` 但没有任何调用点——本会话 grep 过，只有一行 import；V2 只在自己的临时目录里读写）。它写进证据文件的 `tool=` 行来自 `--tool` 字符串，不给就写 `not-run (capture 只采源码指纹，不调工具)`；"版本对账"是把报告头里的 `v.<版本>`/`Build <号>` 与 `--declare` 点名的声明文本相比，**不是**去问工具本身。解释器版本由 `skill/scripts/selftest/run_all.sh` 念出（本会话实测 `node=v24.21.0`）。
- `capture` 需要：至少一个 `--root`、一个可写且非工程目录的 `--out-dir`、建议显式 `--stamp <ISO>`（不给就用当前时间，那样必然晚于既有报告 ⇒ V5 会红）。
- `verify` 需要：`--root`（同一棵树）+ `--evidence` + `--report`；可选 `--declare`（默认按 `Vivado` 这个键找版本号，可用 `--declare-key` 换）、`--recorded`、`--manifest`、`--strict-set`。
- 文件缺失的行为：`--evidence`/`--report` 不存在 ⇒ V4 `NOT_MEASURED`（同时 V1/V3 各有一条读不到的行；见第 7 节记录的重复 V1 行缺陷）；`--root` 不存在 ⇒ `REPRO 读不到输入 --root … 不存在 NOT_MEASURED` + `判 0 项 NOT_MEASURED`（exit 2）；模式不是 `capture|verify`、缺 `--root`、缺 `--out-dir`、参数无法识别 ⇒ exit 3。
- 口径常量：`FPVER=norm2`（去 CR + 去行尾空白）、`FPVER_COMPAT=norm1`（只去 CR，与既有仓库尺子同形）；纳入扩展名由 `--include` 覆盖，默认 `\.v$|\.c$|\.h$|\.mjs$|\.py$|\.xdc$|\.tcl$`。

## 5. 使用方法

1. 编译前采集身份（本仓示例取值，需按自身工程替换）：
   ```bash
   node skill/scripts/repro_check/repro_check.mjs capture \
     --root src/rtl --out-dir <临时产物目录> --stamp <编译前那一刻的 ISO 时刻>
   ```
   完成后应看到：`CAP_written 判 1 项 <证据文件> 行数=N 回读一致=yes PASS`、`CAP_surface 判 1 项 root=… 文件=N 聚合=<12位>（norm2） 与仓库尺子同形=<12位>（norm1） 两种口径下不同的文件数=D PASS`，末行 `REPRO capture … 判 2 项 未判 0 项 红 0 项 PASS`（exit 0）；证据文件里有 `fpver=/captured_at=/tool=/root=/files=/aggregate=/aggregate_norm1=/aggregate_norm1_findshape=` 与逐文件 `<md5>  <相对路径>` 行。
2. 编译后用现成报告回对：
   ```bash
   node ... verify --root src/rtl --evidence <上一步的证据文件> --report <timing_summary 报告> \
     --declare <写着工具版本的声明件> [--recorded <记过 rtl=<12位> 的件>] \
     [--manifest <md5 清单>] [--strict-set]
   ```
   完成后应看到七行 `V4_pair_required / V1_same_source / V2_fingerprint_binds_content / V3_same_tool_version / V5_captured_before_build / V6_compat_with_repo_ruler / V7_manifest_parity`，每行带分母，末行 `REPRO verify … 判 N 项 未判 K 项 红 M 项 <判定>`。
   没给 `--recorded` 或 `--manifest` 时对应条打 `判 0 项 … NOT_MEASURED` ⇒ 末行不会是 PASS（这是"判过要真判"的口径）。
3. `--manifest` 的行形状：`md5sum` 的输出（`<32位十六进制>[ ]?文件名`），路径相对清单文件所在目录；`--strict-set` 会把"同目录里没被清单点名的文件"也算红。
4. 反例自证（本仓 fixture，示例取值）：`--report` 换成 `skill/scripts/selftest/fixtures/repro_negative/report_head.rpt`（它的 `Date` 早于证据的 `captured_at`）⇒ V5 必须红。

## 6. 判读与失败分叉

| 判据 | 通过 | 失败（红） | 读不到输入 |
| --- | --- | --- | --- |
| V4 成对 | `evidence=在 report=在` | —（这条不判红，只判有没有） | 任一侧缺 ⇒ `NOT_MEASURED`，另一份读数全部不可信 |
| V1 同源 | `证据 aggregate=… 现算=… 同=yes；证据 files=N 现扫=N 同=yes`（两维同条） | `同=no` ⇒ 树被改过、或证据不是这棵树的；先确认 capture 是否在编译前跑 | 证据文件里没有 `aggregate=` 行 ⇒ `判 0 项 NOT_MEASURED` |
| V2 指纹绑内容 | 四条一起：LF/CRLF/加尾随空白 三种形状同摘要，改一个字符必须换摘要，且临时树重算 == 主扫描 | 任一条不符 ⇒ 口径不再是"绑内容"（例如又有人加了 `strip` 之外的处理） | 这条自己造件（`os.tmpdir()`）：按源码 `mkdtempSync` 没有兜底 ⇒ 临时目录建不了会抛异常整跑退出（无判据行）`【未实测】` |
| V3 同版 | `报告版本=X 声明=X 一致（取自 <声明件>）` + `报告头 Date=…` | 版本不符或报告头没 Date ⇒ 报告与声明不同版；`--declare-key` 选错键也会红 | 报告头读不到 `\| Tool Version :` 行、或没给 `--declare` ⇒ `NOT_MEASURED` |
| V5 采集先后 | `证据=<ISO> 报告=<Date> 先后成立` | `不成立（编译后采集的指纹不能证明同源）` ⇒ 这份证据作废，重采必须在编译前 | 任一侧时间解析不出 ⇒ `判 0 项 NOT_MEASURED`（历史报告只能靠编译前采集补） |
| V6 与既有尺子对账 | 记录件里的 `rtl=<12位>` == 本脚本 `norm1` 同形算值，并念出两种口径下取值不同的文件数 | 值不等 ⇒ 两把尺子不同形或树变了；`--recorded` 没有 `rtl=` 行也红 | 没给 `--recorded` / 文件不存在 ⇒ `判 0 项 NOT_MEASURED` |
| V7 清单一致 | 每个条目存在且 md5 对得上（`--strict-set` 时还要求"未登记的额外文件=0"） | `md5 不符` / `缺文件` / `未登记的额外文件=N` | 没给 `--manifest` 或清单不存在 ⇒ `NOT_MEASURED` |
| 前置 | — | 模式写错、缺 `--root`、`--out-dir` 指工程目录 ⇒ `REPRO 前置不满足 … 判 0 项 FAIL`（exit 3），发生在任何写动作之前 | `--root`/`--evidence` 读不到 ⇒ exit 2 |

## 7. 已验证的效果

本会话（2026-10-04）实跑：capture/verify 都在 `mktemp -d` 的临时树里跑（`--root` 指临时树、cwd 也切到临时树），`--report`/`--declare` 用的是本仓真件（示例取值，需按自身工程替换）。

- capture：`CAP_written 判 1 项 <临时目录>/ev/fingerprint_manifest.txt 行数=14 回读一致=yes PASS` + `CAP_surface 判 1 项 root=… 文件=2 聚合=84dfdefebec1（norm2） 与仓库尺子同形=fda32463591b（norm1） 两种口径下不同的文件数=1 PASS`，末行 `判 2 项 未判 0 项 红 0 项 PASS`（exit 0）。
- verify 全判（`--recorded` 用 capture 念出的 `aggregate_norm1_findshape`、`--manifest` 是临时目录里 `md5sum` 造的清单 + `--strict-set`）：
  `V2_fingerprint_binds_content 判 4 项 LF=84dfdefebec1 CRLF=84dfdefebec1 加尾随空白=84dfdefebec1 改内容=4f69f4c5ab0f 三项行尾/空白不变 + 改内容必须变 PASS`、
  `V3_same_tool_version 判 2 项 报告版本=2025.2.1 声明=2025.2.1 一致（取自 …/report/BUILD.md） 报告头 Date=Sun Oct  4 04:37:30 2026 PASS`、
  `V5_captured_before_build 判 1 项 证据=2026-10-04T04:00:00+08:00 报告=Sun Oct  4 04:37:30 2026 先后成立 PASS`、
  `V6_compat_with_repo_ruler 判 2 项 记录文件 … 里 rtl=fda32463591b 我用 norm1 口径(与 build/rtl_fingerprint.sh 同形)算=fda32463591b 同=yes；norm2 口径=84dfdefebec1，两种口径下取值不同的文件=1/2 PASS`、
  `V7_manifest_parity 判 2 项 清单=2 核对=2 md5 不符=0 缺文件=0 …  PASS`，末行 `判 14 项 未判 0 项 红 0 项 PASS`（exit 0）。
- 反例 V5（报告头 Date 早于 captured_at，用本仓反例件）：`V5_captured_before_build 判 1 项 证据=2026-10-04T04:00:00+08:00 报告=Sun Sep 27 03:00:42 2026 先后不成立（编译后采集的指纹不能证明同源） FAIL`（exit 1）。
- 反例 V1（把证据文件副本里的 `aggregate=` 改一个字符）：`V1_same_source 判 2 项 证据 aggregate=94dfdefebec1 现算=84dfdefebec1 同=no；证据 files=2 现扫=2 同=yes FAIL`（exit 1）。
- 成对提交对照（`--evidence` 指向不存在的文件）：`V4_pair_required 判 1 项 evidence=缺 report=在（声明：两者必须成对提交，只有一份时另一份不可信） NOT_MEASURED`，末行 `判 8 项 未判 6 项 红 1 项 FAIL`（exit 1）。
  ⚠ 同一次实跑还暴露一个缺陷：`V1_same_source` 被打了**两行**（一行 `判 0 项 …不存在 NOT_MEASURED`，紧接一行 `判 2 项 证据 aggregate=空 … FAIL`），所以"缺输入"在这一支里同时是未测与红 ⇒ 判读要以 V4 行为准，已进待修清单。
- 守卫与跨盘：`capture --out-dir build/_selftest_scratch` ⇒ `REPRO 前置不满足 输出目录指向工程目录 build/_selftest_scratch NOT_MEASURED` + `判 0 项 FAIL`（exit 3，目录未创建）；`--root` 指到与 cwd 不同盘的临时目录 ⇒ `Error: ENOENT … open 'D:\…\C:\Users\…\src\a.v'`（exit 1、无判据行），这就是第 3 节那条限制的现实来源。
- 串跑：`skill/scripts/selftest/run_all.sh` 的 `REPRO repro_check 判 7 项 capture=ok verify=ok negV5=ok negV1=ok pair_required=ok guard=ok guard_no_write=ok PASS`。
- `--declare-key`、`--include` 改扩展名集合、真件（`--root src/rtl` 全树）跑一次完整 capture→编译→verify 的仓库内闭环：`【未实测】`——本会话为了"不往交付树写东西"只在临时树里跑，没在 `src/rtl` 上留证据件。

## 8. 提炼来源与边界

- 来源证据：`skill/scripts/repro_check/repro_check.mjs` 的 V1–V7 与文件头"指纹绑内容不绑行尾""证据与报告必须成对提交"两条约束；
  口径 `norm1` 的对账对象是仓库既有尺子 `build/rtl_fingerprint.sh`（本仓示例取值，需按自身工程替换）；反例件 `skill/scripts/selftest/fixtures/repro_negative/report_head.rpt`；
  `skill/evals/records/audit-2026-10-04.md` 登记了 V7 的死三元（`(… ? 'PASS' : 'PASS')`）与 `bad += 0` 空操作——本会话第 7 节的"重复 V1 行"是同一族（看起来有判据、其实没牙/没分家）。
- 边界：capture 只采源码身份，不调工具、不采二进制；verify 只读现成报告，不重新生成报告。两者之间发生的任何源码改动都会被 V1 抓到（这正是设计）。
- 迁移要改四处：① `FPVER_COMPAT` 与你仓库既有尺子的口径（不一致就别指望 V6）；② `INCLUDE` 扩展名集合；③ V3 的版本声明件与键名（`--declare-key`）；
  ④ 时间基准（Vivado Date 用本地时间，别的工具未必）+ 两条反例件（一份"Date 早于 captured_at"、一份"改一个字符"）。
- 不再适用：源码树被别的进程并发改写时（V1/V2 会把并发写当成漂移）；或产物按内容寻址存放（此时 md5 清单那层要换成清单服务）。
