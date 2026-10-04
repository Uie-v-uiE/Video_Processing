---
name: regmap_check
description: 寄存器契约一致性检查：以 22 列契约表为单一真相源，逐行把位域/复位值/最宽输入与 RTL 源文件、主机与固件代码、人读文档表、块图钉址脚本四方对账（K1–K8 八条判据，含文档基址的反向覆盖），stdout 全程 ASCII、每条打印分母并把判定放在最后一列。当改过寄存器表、RTL 或文档表格，或当症状是"表说 bit[15:8]、代码里挪了位""文档里出现一个没登记的基址"时使用。它不生成代码（contract_gen）、不比对读数（golden_compare）；表词表不对时会崩而不是判红。
---

## 1. 一句话用途

寄存器契约表与 RTL/代码/文档/块图的八条对账。

## 2. 适用场景

- 契约表某行的 `rtl_pattern` / `host_pattern` / `doc_pattern` 改了，要确认锚点字符串真的还在被点名的文件里。
- 同一个基址+偏移上塞了多位域，或用了"先写 index 再读数据口"的窗口式读回 ⇒ 要证明位域不重叠、RO 行的 index 区间不重叠（K2）。
- 块图脚本新钉了一个地址、或表里新增一行还没钉址 ⇒ 双向都要判红（K6）。
- 人读文档表里出现了一个基址（本仓示例：`0x412` 开头的地址，需按自身工程替换）却没登记进契约表 ⇒ 反向覆盖（K5）。
- 复位值声称有出处 ⇒ `reset_src` 必须写成 `path:line` 且那一行真的含数字（K8）。
- 最宽输入超出位域但被"声明夹住" ⇒ 必须写在 `overflow` 列里，两向都数（K7）。

## 3. 不适用 / 失效条件

- **词表必须是本脚本的 22 列**（`row object bits access index reset reset_src wse rse irq unit widest overflow cdc base addr_off rtl_file rtl_pattern host_file host_pattern doc_file doc_pattern`）。喂 10/14 列那版表（`contract_gen` 的词表）会在 K5 崩：`TypeError: Cannot read properties of undefined (reading 'toLowerCase')`（`regmap_check.mjs:184`），**一条判据行都不打印** ⇒ 这是形状不匹配，不是设计错，也不是"判过了"。
- 只想生成主机侧骨架：那是 `contract_gen`；只想比对两份读数：那是 `golden_compare`。
- 锚点是"意思对就行"：`contains()` 是逐字符 `includes`，改注释、换空白、换别名都会 miss；不要指望模糊匹配。
- `--contract` 与 `--bd` 都**没有兜底默认值**，缺一个就是 exit 3；空文件 exit 2。
- 想让它替你判断"这个位域该不该存在"：它只查自洽与在场，不查设计意图。
- 本仓当前状态提醒：直接全跑会被 K2/K4/K5 三条点名（见第 7 节），那是契约表与代码/文档的真实漂移，不是本脚本坏了。

## 4. 前置条件

- 工具探针：本脚本不探针外部工具、不起子进程，只用 `node:fs` 读文本；运行版本由 `skill/scripts/selftest/run_all.sh` 的汇总行念出（本会话实测 `node=v24.21.0`）。
- 在仓库根执行：表里的 `rtl_file`/`host_file`/`doc_file`/`reset_src` 都是**相对仓库根**的路径，必须在场（读不到 ⇒ 该条判据 `NOT_MEASURED`，不是判红也不是判绿）。
- 两个必需输入：`--contract`（TSV，`#` 行忽略）与 `--bd`（块图脚本；K6 只认 `<name> 0x8位十六进制` 这种行，本仓示例取值 `build/tcl/build_system_axigpio.tcl`，需按自身工程替换）。
- 输出：只打到 stdout，不写任何文件（因此也没有 `--out-dir` 守卫）。
- stdout 形状：全 ASCII（含 `判 N 项` 分母 token），这是刻意的——本机控制台 cp936 下 CJK 细节会让 grep 与台账失真。

## 5. 使用方法

1. 全跑（本仓示例取值，需按自身工程替换）：
   ```bash
   node skill/scripts/regmap_check/regmap_check.mjs \
     --contract skill/scripts/regmap_check/axi_gpio_contract.tsv \
     --bd build/tcl/build_system_axigpio.tcl
   ```
   完成后应看到：`K1 contract_columns … 判 N 项 … PASS|FAIL|NOT_MEASURED` 共八行 + 末行
   `REGMAP <表路径> 判 N 项 未判 K 项 红 M 项 PASS|FAIL|NOT_MEASURED`；exit 0/1/2/3。
2. 排障时只跑点名的判据：`--only K3,K4`（其余不打印也不计数；`--only` 拼错 ⇒ `REGMAP 判 0 项 NOT_MEASURED`，exit 2）。
3. 正向自证（本会话用的对照口径）：
   ```bash
   node ... --contract <22列表> --bd <块图脚本> --only K1,K3,K6,K7,K8   # 期望 exit 0、末行 PASS
   ```
4. 反向自证（合成一份"多钉一个地址"的 BD，临时目录里造，不碰交付树）：
   ```bash
   printf 'selftest/pin 0x41299999\n' > /tmp/bd_extra.tcl
   node ... --contract <22列表> --bd /tmp/bd_extra.tcl --only K6          # 期望 K6 行 FAIL
   ```
5. 在自己工程里第一次用：先只做 K1（列齐 + 每格非空），再逐条把 `rtl_file/rtl_pattern` 等锚点列填进表；空着的格子会被 K1 点名到 `行.列`。

## 6. 判读与失败分叉

| 判据 | 通过 | 失败（红） | 读不到输入 |
| --- | --- | --- | --- |
| K1 列齐且每格非空 | `empty=0 unknown_cols=0`，分母=行数×22 | `empty=N at:行.列` ⇒ 那一格没人负责，补表而不是删列 | 表头缺列 ⇒ 打 `header_lacks=…` 并 `NOT_MEASURED`（词表不对，别当通过） |
| K2 位域合法/不重叠 | `wellformed=行数 overlap_or_illegal=0` | `bad_bits=`（不是 `[h:l]` 且 h≥l、h>31）、`bits~overlaps~`、`index~overlaps~`（同一 base+off 上两条 RO 行的 index 区间相交）⇒ 一次读会被两条契约认领 | 行数为 0 ⇒ `NOT_MEASURED` |
| K3 表↔RTL 锚点 | `hit=compared miss=0` | `anchor not found in <rtl_file>` ⇒ 代码漂了或锚点写错，改**表或代码**，别改判据 | `unreadable_file>0` ⇒ `NOT_MEASURED`（源文件不在） |
| K4 表↔主机/固件锚点 | 同 K3 | 同 K3；注意 `host_file` 可以是固件也可以是上位机脚本，两者都是文本对账 | 同 K3 |
| K5 表↔人读文档（双向） | 每行 `doc_pattern` 在 `doc_file` 里，且文档里点名的基址都在表的 `base` 列 | `doc_missing_row=N`（表说文档有，文档没有）或 `base_not_in_table=1[0x…]`（文档冒出一个没登记的基址） | `doc_unreadable>0` ⇒ `NOT_MEASURED` |
| K6 表↔块图钉址（双向） | `in_table_not_pinned=0 pinned_not_in_table=0` | 任一侧非 0 ⇒ 表与块图各说各话 | BD 里一个地址都没钉时**设计意图是** `NOT_MEASURED`，但实测打 `FAIL`：`regmap_check.mjs:206` 用 `pinned.length` 判空集，而 `pinned` 是 Set（恒 `undefined`）⇒ 至少没判绿，已进待修清单 |
| K7 最宽输入 vs 位宽 | `fits` 或"越界但 `overflow` 列写明了行为" | `over_not_documented>0` ⇒ 越界却没写怎么夹 | `undecidable>0`（位域或 `widest` 解析不出）⇒ `NOT_MEASURED` |
| K8 复位值出处 | 数值行的 `reset_src` 是 `path:line` 且那一行含数字 | `bad_provenance>0` ⇒ 出处指错或指到没数字的行 | 复位值不是纯数（例如写 `na`）⇒ 计入 `no_number_or_unreadable` 并 `NOT_MEASURED` |
| 前置 | — | 缺 `--contract`/`--bd` ⇒ `REGMAP precondition … 判 0 项 FAIL`，exit 3 | 文件不存在/为空 ⇒ `REGMAP not_measured … NOT_MEASURED`，exit 2 |

## 7. 已验证的效果

本会话（2026-10-04）在仓库根实跑，输入是本仓示例取值，需按自身工程替换。

- 全跑（22 列表 + 块图脚本）：末行 `REGMAP skill/scripts/regmap_check/axi_gpio_contract.tsv 判 908 项 未判 0 项 红 3 项 FAIL`（exit 1），三条红是真实漂移：
  `K2 bits_range_overlap 判 34 项 rows=32 wellformed=31 overlap_or_illegal=2 at:gpio0.lane_sel:bad_index=lane,gpio1.lane_25_arm~index~overlaps~gpio1.lanes_24_29@0x41210000+0x00[25] FAIL`、
  `K4 vs_host_code 判 32 项 compared=32 hit=31 miss=1 unreadable_file=0 at:gpio1.lanes_0_9: anchor not found in src/host/health_read.mjs FAIL`、
  `K5 vs_docs 判 36 项 … doc_missing_row=4 … base_not_in_table=1[0x41220008] FAIL`；同时 `K1 判 704 PASS`、`K3 判 32 hit=32 PASS`、`K6 判 6 PASS`、`K7 判 32 PASS`、`K8 判 32 PASS`。
- 正向对照：`--only K1,K3,K6,K7,K8` ⇒ exit 0、末行 `判 … 项 未判 0 项 红 0 项 PASS`。
- 反向对照（多钉一个表里没有的地址）：`K6 vs_block_design 判 5 项 table_bases=3 bd_pinned=2 in_table_not_pinned=2[0x41220000,0x41210000] pinned_not_in_table=1[0x41299999] FAIL`（exit 1）。
- 空集对照（BD 里一个地址都没钉）：同一行打 `bd_pinned=0 … FAIL`（exit 1）⇒ 不判绿，但也不是 NOT_MEASURED（K6 的空集守卫写在 Set 上，见第 6 节）。
- 前置与读不到：`REGMAP precondition missing --bd (no built-in fallback path) FAIL` + `判 0 项 FAIL`（exit 3）；空表 ⇒ `REGMAP not_measured --contract … is empty NOT_MEASURED`（exit 2）；`--only K9` ⇒ `REGMAP no criterion matched by --only NOT_MEASURED` + `REGMAP 判 0 项 NOT_MEASURED`（exit 2）。
- 串跑：`skill/scripts/selftest/run_all.sh` 的 `RGMAP regmap_check 判 6 项 pos=ok negK6=ok emptyK6=ok precondition=ok empty_tsv=ok only_typo=ok PASS`。
- 已知未闭合：喂 10/14 列旧词表会在 K5 崩（第 3 节引的那条 `TypeError`，本会话实测 exit 1 且无判据行）——`fixtures/regmap_negative_missing_field` 与 `fixtures/regmap_negative_bad_cite` 两份件就是这个形状，现已改由 `contract_gen` 消费前者、后者无人消费；`【未实测】`：窗口式 RO 读回的 index 区间重叠（K2 的 `na` 分支与多段 `0-3,7` 写法）没被真件刺激过，只有合成件测到。

## 8. 提炼来源与边界

- 来源证据：`skill/scripts/regmap_check/regmap_check.mjs` 的 K1–K8 实现与文件头判据清单；表件 `skill/scripts/regmap_check/axi_gpio_contract.tsv`（本仓示例取值）与 `skill/scripts/regmap_check/contract.tsv`（10/14 列旧词表，说明"两把尺子两套词表"这件事在本仓真实存在）；
  `skill/evals/records/audit-2026-10-04.md` 已登记本脚本 K1/K7/K8 的"全 0 输入判绿"族问题（第 6 节 K6 那条是本会话新测到的同族）。
- 边界：只管"契约表 ↔ 四方文本"的一致，不管时序/资源读数，不管主机代码是否真的按表打包（那是 `contract_gen` 生成的骨架 + 台架）。
- 迁移要改三处：① `COLS` 22 列名（与你的表头逐字符一致）；② K5 反向基址的正则（本仓是 `0x4` 开头 + `0x412` 段，必须换成你的地址段）；
  ③ K6 的钉址行正则（本仓块图脚本的 `foreach` 行形状）。反例件要成对：一条"多钉"、一条"没钉"。
- 不再适用：RTL/文档改用结构化数据（JSON/HJSON）描述寄存器时，`contains()` 文本锚点这层要换成字段级比较，否则锚点判据会成片假红。
