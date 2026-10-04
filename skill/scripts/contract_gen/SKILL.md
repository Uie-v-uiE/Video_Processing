---
name: contract_gen
description: 从寄存器契约表（TSV）生成主机侧打包/解包骨架与一份自带断言的最宽输入回归：10 个必填字段缺一格就退出码 3 且不补默认值，最宽输入要从位域与量程重推对账，产物再用同一个 node 二进制过一遍解析器。当契约表刚改过量程/位域、需要在写固件与上位机之前把表变成可复跑断言，或当症状是"主机侧手写的偏移与位域和表漂了"时使用。不校验 RTL/文档/块图一致性（那是 regmap_check 的射程），表自身不自洽时它拒绝生成而不是生成一份近似件。
---

## 1. 一句话用途

把寄存器契约表生成成主机侧骨架 + 最宽输入回归。

## 2. 适用场景

- 契约表里某行的 `unit_range` / `widest_input` / `bits` 刚改过，想在写主机代码之前先有一条"能不能塞进位域"的可跑断言时。
- 主机侧（固件或上位机脚本）正在手写偏移、掩码、移位，需要一个由表派生的 `packWord/unpackWord` 作为单一真相源时。
- 有人往表里填了看起来合理的数（量程 0..255 却把最宽输入写成 300），需要一条**自己重推一遍再对账**的判据把它点名时。
- 交付要求"生成的代码不是看着像代码，而是真过了一遍解析器"时（C4 用 `process.execPath` 跑 `node --check`）。
- 需要一份能独立复跑的复位值/往返测试骨架（生成的 `<前缀>_stub.mjs` 自己就打印 `判 N 项`）。

## 3. 不适用 / 失效条件

- 要证明"表与 RTL、文档、块图钉址一致"：那是 `regmap_check` 的射程；本脚本只看表自己的 10 个必填字段与由它们重推的算术。
- **词表必须对得上**：本脚本读的是 10 列必填词表（`offset bits access reset w_side_effect r_side_effect interrupt unit_range widest_input clock_domain`）。同一目录里那张 22 列表是给 `regmap_check` 的，两把尺子各数各的——给错表会走"契约表缺列"分支（退出码 3），这是形状不匹配，不是内容错。
- 想让缺字段"先用空串占位、回头补"：本脚本明确拒绝（缺 ⇒ 退出 3 且不产出任何文件）。要临时放行只能自己复制表补格。
- 需要产物落进工程目录：`--out-dir` 指向 `src/`、`sim/`、`build/`、`board/`、`data/`、`report/`、`docs/` 会被拒绝（见第 6 节的实测：这一支目前是以异常的方式拒绝，见第 7 节末尾一条）。
- 表只有一行数据也要生成：可以；但表没有数据行（只有表头）⇒ `读不到输入` 退出 2，不产出。

## 4. 前置条件

- 工具探针：脚本自身不打印版本，但 C4 会**用自己的解释器**（`process.execPath`）对两份产物各跑一次 `node --check`；本仓 `run_all.sh` 的汇总行会念出 `node=v24.21.0`（2026-10-04 实测）。没有 node 的环境直接不适用。
- 在仓库根执行（`--contract` 与 `--out-dir` 都是相对 cwd 的路径）。
- 输入：一张 TSV（制表符分隔，`#` 开头行被丢弃）。上面 10 个必填字段必须**同名列存在**，另允许可选列（`name` 用来点出问题行；本仓示例表还带三列证据，本脚本不读它们）。
- 输入缺失的行为：缺 `--contract`、缺 `--out-dir`、路径不存在、文件为空、只有表头 ⇒ 打印两行 `GEN 读不到输入 … NOT_MEASURED` + `GEN 读不到输入 判 0 项 NOT_MEASURED` 并以 **2** 退出；无法识别的参数 ⇒ 以 **3** 退出。都不产出半截文件。
- 权限：`--out-dir` 需要可写（不存在会 `mkdir -p` 递归创建）。

## 5. 使用方法

1. 从契约表生成骨架 + 测试骨架：
   ```bash
   node <技能包>/skill/scripts/contract_gen/contract_gen.mjs \
     --contract <契约表>.tsv --out-dir <临时产物目录> [--prefix <前缀>]
   ```
   本仓示例取值，需按自身工程替换：`--contract skill/scripts/regmap_check/contract.tsv --out-dir` 指到临时目录。
   完成后应看到五行 `C1_required_fields / C3_widest_input_recheck / C2_emit_coverage / C4_generated_parses / C5_units_and_domain_in_code`，每行都带 `判 N 项`，末行 `GEN <骨架路径> <测试骨架路径> 判 N 项 未判 0 项 红 0 项 PASS`（exit 0）。
2. 跑生成的测试骨架（它自己也是判据脚本）：
   ```bash
   node <临时产物目录>/<前缀>_stub.mjs
   ```
   完成后应看到：逐寄存器三行 `PASS <名>_reset_in_range / _widest_fits_field / _roundtrip_widest`，末行 `GEN_STUB 判 N 项 未判 0 项 红 0 项 PASS`（exit 0）。
3. 反向自证（本仓自带反例，示例取值）：
   ```bash
   node ... --contract skill/scripts/selftest/fixtures/contract_gen_negative_bad_widest/contract.tsv --out-dir <临时目录>   # 期望 红 C3、exit 1、不产出
   node ... --contract skill/scripts/selftest/fixtures/regmap_negative_missing_field/contract.tsv --out-dir <临时目录>       # 期望 红 C1、exit 3、不产出
   ```
4. 在自己工程里第一次用：把表头复制成槽位（`name` + 10 必填列），逐列决定"谁负责填"；空着的格子会被 C1 点名到 `第N行(名字)缺 列名`。

## 6. 判读与失败分叉

| 命令 | 通过 | 失败 | 读不到输入 |
| --- | --- | --- | --- |
| 第 1 步（生成） | exit 0，`红 0 项`；产物两件都在盘上（`--check` 只证明能解析，不证明寄存器行为对） | 末行 `红 M 项 FAIL` ⇒ 打开被点名的 C 行，回到契约表那一格改表；**不许**改脚本让它过 | exit 2 `GEN 读不到输入 …` ⇒ 表路径/空文件/只有表头，等价"没生成"，别念成通过 |
| `C1_required_fields` 红 | — | 某行某格为空 ⇒ 脚本以 **3** 退出且不写任何文件（"缺就不生成、不补默认值"是这条判据的全部意义） | 表里没有那 10 列 ⇒ 走 `契约表缺列`，也是 exit 3 |
| `C3_widest_input_recheck` 红 | 每行三件事都对：量程上限 ≤ 位域上限、`widest_input` 是数、且等于量程上限 | 例 `threshold:表里写 300, 从量程重推是 255` ⇒ 表和算术只可能对错一处，先量位域再定量程单位；改表或改 RTL，别改判据 | 位域或量程解析不出（`判不了=N`）⇒ 该行 NOT_MEASURED，整跑 NOT_MEASURED |
| `C2_emit_coverage` 红 | 应生成 = 实际 = 行数、漏=0、多余=0 | 漏/多 ⇒ 生成器与表不同源（同名寄存器被去重或名字被改），先查 `name` 列有没有重复 | 表没有数据行 ⇒ 走 exit 2 |
| `C4_generated_parses` 红 | 两件都"语法过" | 产物解析不过 ⇒ 是生成器的 bug（值里带了未转义字符），把那一行贴回来，不要手改产物 | — |
| `C5_units_and_domain_in_code` 红 | 每行的单位/量程与时钟域**两条**都进了产物 | 缺一侧 ⇒ 产物丢了跨域信息，下游没法判断"这个数在哪个域" | — |
| 生成的 `_stub.mjs` 红 | — | `FAIL <名>_roundtrip_widest` ⇒ 写最宽再读回对不上，先怀疑掩码/移位而不是断言 | — |
| `--out-dir` 指工程目录 | —（没有"通过"这一态：必须拒绝） | 必须非 0 退出且**盘上没有新目录**；实测以异常退出（见第 7 节最后一条） | — |

## 7. 已验证的效果

- 正例（本仓 2026-10-04 实跑，表 = 上面点名的 14 列示例件，产物写临时目录）：
  `C1_required_fields 判 110 项 行=11 检查=110 缺=0 PASS` / `C3_widest_input_recheck 判 33 项 行=11 判=33 破=0 判不了=0 PASS` /
  `C2_emit_coverage 判 22 项 应生成=11 实际=11 漏=0 多余=0 PASS` / `C4_generated_parses 判 2 项 regmap_host.mjs:语法过 regmap_host_stub.mjs:语法过 PASS` /
  `C5_units_and_domain_in_code 判 22 项 行=11 判=22 缺=0 PASS`，末行 `… 判 189 项 未判 0 项 红 0 项 PASS`（exit 0）。
- 生成件复跑（同一次实跑）：`GEN_STUB 判 33 项 未判 0 项 红 0 项 PASS`（exit 0）——11 个寄存器 × 3 条断言。
- 反例 1（最宽输入与量程不符，`contract_gen_negative_bad_widest`）：`C3_widest_input_recheck 判 33 项 行=11 判=33 破=1 判不了=0 例:threshold:表里写 300, 从量程重推是 255 FAIL`，
  末行 `GEN 未生成 契约本身不自洽 ⇒ 不产出骨架 判 143 项 未判 0 项 红 1 项 FAIL`（exit 1，产物目录没被创建）。
- 反例 2（缺一格，`regmap_negative_missing_field`）：`C1_required_fields 判 110 项 行=11 检查=110 缺=1 例:第10行(gapclr)缺 interrupt FAIL`，
  末行 `GEN 契约缺字段 缺 1 处 ⇒ 不生成、不补默认值 判 110 项 FAIL`（exit 3，同样零产出）。
- 空输入：`GEN 读不到输入 --contract <空文件> 是空文件 NOT_MEASURED` + `GEN 读不到输入 判 0 项 NOT_MEASURED`（exit 2）。
- 以上五条都由 `skill/scripts/selftest/run_all.sh` 串跑成一行：`CGEN contract_gen 判 8 项 pos=ok pos_files=ok stub=ok negC3=ok negC1=ok guard=ok guard_no_write=ok empty=ok PASS`。
- ⚠ 实测到的自身缺陷（记在这里而不是删掉，本条不修脚本）：`--out-dir` 指向工程目录时，守卫确实拦住了（临时目录里没出现 `build/_selftest_scratch`），
  但退出方式不是设计里的 3 而是异常：`ReferenceError: Cannot access 'nMade' before initialization`（`contract_gen.mjs:42` 被 `:52` 的 `pre()` 调用，早于 `:54` 的 `let nMade`），exit 1、无判据行。
  ⇒ 迁移到别的工程时这一支仍算"拒绝"，但退出码要按非 0 判、不能按 3 判；已进本会话的待修清单。
- `--prefix` 改名、`--help` 文本、以及"同一张表在 CI 里连跑两次产物逐字节相同"：`【未实测】`（本次只跑了默认前缀，也没比对两次产物字节）。

## 8. 提炼来源与边界

- 来源证据：`skill/scripts/contract_gen/contract_gen.mjs` 的 C1–C5 实现（第 81–225 行）与文件头"缺字段 ⇒ 退出码 3、不臆造默认值"的设计约束；
  本目录的 `run_all.sh` 逐条对照（上面第 7 节全部来自本会话实跑）；`skill/evals/records/audit-2026-10-04.md` 已登记同族问题（`printed` 计数器不自增 ⇒ 退出 3 那行的分母只有 C1 的数，不是全跑数）。
- 边界：本条目管"表 → 可跑骨架 + 可跑断言"，不管表从哪来（`skill/templates/interface-contract/`）、不管表与 RTL/文档是否一致（`regmap_check`）、
  不管主机代码是否真的调用它（生成的骨架不认识总线：GPIO 整字 / AXI-Lite / 串口都由调用方注入）。
- 迁移要改三处：① `REQUIRED` 十列换成你自己的字段名；② `PROTECTED` 守卫表换成你工程的不可写目录前缀；③ 反例件（缺格 / 最宽输入与量程不符）各造一份，
  否则这条判据在新仓库里没有牙。
- 不再适用：契约改为 JSON/YAML（解析层要换，C1 的"缺一格就点名到行列"语义必须保留）；或寄存器位宽超过 32 位需要 64 位掩码
  （C3 用 `(1 << width) - 1`，JS 里超过 32 位会绕回去——本仓示例表最宽正好 32 位，所以这一支从没被刺激过）。
