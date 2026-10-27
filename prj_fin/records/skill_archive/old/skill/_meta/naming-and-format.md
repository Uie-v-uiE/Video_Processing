---
name: naming-and-format
description: 技能包的命名、编码、长度、frontmatter 与索引规则，以及每条规则对应的自检命令与条文依据。改任何条目格式前先读这一页。
---

# 命名与格式规则（含可复制自检命令）

环境事实（2026-10-04 实测）：Windows 11 + Git Bash（MSYS），`node` 可用、`python` = 3.12（**没有** `python3`）。
下面每条命令都从仓库根目录跑，路径用 `/`。

## 目录

- 1. 条文依据（逐字摘录，不转述）
- 2. 规则与自检命令（R1 命名 / R2 条目外壳与 name / R3 description / R4 八节 / R5 残留与第二份索引 /
  R6 长度分层 / R7 索引一致性 / R8 链接 / R9 降级标记 / R10 编码）
- 3. 冲突裁决与术语统一
- 4. 版本声明（版本漂移影响哪些条目）

## 1. 条文依据（逐字摘录，不转述）

本仓库把赛题原文的关键句存在 `report/log/CONTEST_CHECKLIST.md` 里，下面三条逐字取自那里的摘录行，
判定"为什么要有这条门禁"时以这些句子为准；赛题 PDF 原件不在本仓库内，所以这里**只引用已存在的摘录**，
不假装读过原文其余段落。

| 门禁 | 条文关键句（逐字） | 摘录位置（2026-10-04 打开核对） |
| --- | --- | --- |
| G1 命名 | `目录/文件名纯英文（§3.3.5.4 原文：小写字母、数字、下划线或连字符，"不得出现中文、空格或特殊字符"）` | `report/log/CONTEST_CHECKLIST.md:21` |
| 目录组织可自定 | `上表为推荐结构，非强制。**采用其他组织方式的队伍须在 `README.md` 中给出目录对照说明**` | 同文件 `:120` |
| PYNQ 加分口径 | `通用 PYNQ Skill 单独加分` —— 本作品不用 PYNQ（裸机 + Vivado/Vitis 原生流程） | 同文件 `:124` |
| 技能包四类内容与四要素 | 技能包条目 = §3.3.5.2；`skill/` 是赛题点名的目录 | 同文件 `:82`（那一行同时纠正过一次编号记错：文件名要求是 §3.3.5.4，工具版本是 §3.3.3.1，技能包是 §3.3.5.2） |

## 2. 规则与自检命令

### R1 纯 ASCII 小写命名（G1）

```bash
# 期望：无输出（有输出就是违规）
find skill -type f -o -type d | LC_ALL=C grep -nE '[^ -~]|[^a-zA-Z0-9._/ -]| [A-Z]|/.*[A-Z]'  | head
```

判定写法：文件名与目录名只允许 `a-z 0-9 - _ .` 与路径分隔符 `/`；空格、大写、中文、`\` 一律违规。

### R2 每个条目目录都有 `SKILL.md`，且 `name` == 目录名（G2）

```bash
for d in $(find skill -mindepth 2 -maxdepth 2 -type d ! -path 'skill/_meta*'); do
  n=$(basename "$d"); f="$d/SKILL.md"
  [ -f "$f" ] || { echo "MISSING_SKILL $f NOT_MEASURED"; continue; }
  got=$(awk '/^name:/{print $2; exit}' "$f")
  [ "$got" = "$n" ] || echo "NAME_MISMATCH $d got=$got want=$n FAIL"
done
```

### R3 `description` 单行、第三人称、≤1024 字符（G3）

```bash
find skill -name SKILL.md | while read f; do
  d=$(awk '/^description:/{sub(/^description: */,"");print;exit}' "$f")
  L=${#d}; c=$(printf '%s' "$d" | wc -c)
  [ "$L" -gt 0 ] && [ "$c" -le 1024 ] || echo "DESC_BAD $f len=$c FAIL"
done
```

### R4 八节齐全且顺序正确（G4：按标题字符串核对，不按行号）

```bash
sed -n '1,20p' skill/_meta/entry-template.md   # 八节标题的唯一真相源在这里，脚本也从那里取
```

### R5 无 `TODO` / `FIXME` / 未点名的额外文件（G5）

```bash
grep -rn "TODO\|FIXME" skill --include="*.md" | head          # 期望：无输出
find skill -name README.md | LC_ALL=C sort                     # 期望：只有 skill/README.md 与（被点名的）scripts/README.md
```

### R6 长度分层（G6）

```bash
for f in $(find skill -name "SKILL.md"); do
  n=$(grep -c '' "$f"); [ "$n" -le 500 ] || echo "TOO_LONG $f $n FAIL"
done
```

### R7 索引一致性（G7）：一览表由目录生成，不手维护

```bash
node skill/scripts/check/gen_index.mjs --check    # 不一致就 FAIL 并打印孤儿数；条目增删后必须重跑
```

### R8 链接可解析（G8）

```bash
node skill/scripts/check/gates.mjs --only G8      # 相对链接断链数必须为 0；外链都要在 _meta/sources.md 有行
```

### R9 降级标记可见（G9）

```bash
node skill/scripts/check/gates.mjs --only G9      # 【填入】/【待验证】/【未核实】逐文件计数并汇总；计数不是错误，但必须可见
```

### R10 编码与截断字节（G12）

```bash
node src/host/doc_enc_check.mjs                   # 本仓库现成的尺子：UTF-8 无 BOM 异常、无被截断的多字节字符
```

## 3. 冲突裁决与术语统一

- **条目内不放 `README.md`**。Anthropic/superpowers 的"技能内不建第二份索引"与我们必须交付
  `skill/README.md` 不矛盾：根 `README.md` 是给人和评委的索引，条目正文一律 `SKILL.md`。
  后来的 agent 不要再建第二个索引文件。
- 术语一律用一个词：`检查点`（不用"中间产物/快照"混称）、`黄金参考`（不用"参考实现"混称）、
  `三态判定`（PASS / FAIL / NOT_MEASURED）。判据文字若改动，引用它的验证记录按 `evals/` 的规矩标 `需重跑`。
- 交叉引用只允许两种形态：`skill/` 内的相对路径，或 `_meta/sources.md` 里有对应行的外部链接。
- 专有名（本队的模块名/网名/脚本名/板卡昵称）出现在条目里时，必须写成 `【填入】` 或同行标注
  "示例取值，需按自身工程替换"。清单与 grep 由 `skill/scripts/check/gates.mjs` 的 G10 执行。

## 4. 版本声明（版本漂移影响哪些条目）

本包在 `Vivado/Vitis 2025.2.1 (build 6403652)` 下写成（真相源：`report/BUILD.md` 与 `data/metrics.csv`
的工具版本行，2026-10-04 打开核对）。受版本影响的条目以各条目自己的 `## 3. 不适用 / 失效条件` 为准，
本文件不重复列细节，避免两处漂。
