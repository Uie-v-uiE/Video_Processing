---
name: check
description: 装配与门禁类脚本所在的目录：把一览表从目录实际内容生成、把 G1–G12 十二项机器判据一次跑完并打印每条的分母。当条目增删/改名/移动过，或要在提交前证明技能包本身没有说谎时使用。
---

## 1. 一句话用途

生成索引并跑技能包的十二项装配门禁。

## 2. 适用场景

- 刚加/删/改过一个 `skill/**/SKILL.md`，需要确认 `skill/README.md` 的一览表没有手抄漂移时。
- 提交前需要一份"包自身"的机器证明（命名、frontmatter、八节、链接、编码、降级标记可见性）时。
- 陌生队伍把自己工程的条目塞进这个目录，想知道哪一条形状不合时。
- 当有人打算"改门禁让它变绿"时——本条给出该走的正确分叉（改文件，或明确请求批准改判据）。

## 3. 不适用 / 失效条件

- 想验**设计**（时序/资源/板级）：那是 `build/gates.sh` 与台架的射程，本目录只管文档与形状。
- 目录结构不是"一个条目=一个目录+`SKILL.md`"时，G2/G4 的判定没有意义（会大面积红，属于形状不匹配而非内容错）。
- 不在仓库根执行时（两条脚本都用 `process.cwd()` 定位）：会读不到东西并给出 `NOT_MEASURED`，不要在那种状态下念结论。
- 脚本用 `node`，没有 node 的环境直接不适用（改写成 bash 是另一个决定）。

## 4. 前置条件

- 在仓库根目录（`pwd` 能看到 `skill/`、`build/`、`src/`）。
- `node --version` 可用。
- 名单文件 `skill/_meta/team-names.txt` 存在（G10 要用；它由文件末尾注释里的两条命令现算）。
- 只读前提：两个脚本都不写工程源码；唯一会被写的是 `skill/README.md` 的生成区（`gen_index.mjs` 不带 `--check` 时）。

## 5. 使用方法

1. 只比较、不写：
   ```bash
   node skill/scripts/check/gen_index.mjs --check
   ```
   完成后应看到：`gen_index --check 条目=N 判 N 项 一致=yes PASS`（exit 0）。
2. 生成/更新索引（改过条目之后）：
   ```bash
   node skill/scripts/check/gen_index.mjs
   ```
   完成后应看到：`gen_index 写入 条目=N 行数 A->B 判 N 项 PASS`，且 `skill/README.md` 里
   `<!-- BEGIN GENERATED INDEX -->` 与 `END` 之间的表被替换，**其余正文一字未动**。
3. 跑十二项装配门禁：
   ```bash
   node skill/scripts/check/gates.mjs
   ```
   完成后应看到：十二行 `G<数字> <标签> 判 N 项 <细节> PASS|FAIL|NOT_MEASURED`，
   最后一行 `GATES 技能包：判定 12 项 绿=… 红=… 未测=…`。
4. 只看某几项（排障时）：`node skill/scripts/check/gates.mjs --only=G7,G8`。

## 6. 判读与失败分叉

| 命令 | 通过 | 失败 | 读不到输入 |
| --- | --- | --- | --- |
| `gen_index --check` | 一致 ⇒ 索引没漂 | `一致=no` ⇒ 有条目被加/删/改名而 README 没更新；**不要手改表**，跑第 2 步重写 | exit 3 + "缺生成区锚点/找不到 skill/" ⇒ `NOT_MEASURED`，先确认在仓库根 |
| `gen_index`（写入） | 行数只增不减且末行 `PASS` | 行数变少 = 覆盖式写入出错，立刻 `git checkout skill/README.md` 再查脚本 | 条目=0 时它会写出空表——**这不算通过**，说明扫描集错了 |
| `gates.mjs` | exit 0，全 PASS | 任一 `FAIL` ⇒ 按那一行的细节点名文件去改文件；**禁止**为了变绿删判据（判据要改必须先经批准，且改动要重跑 selftest） | 任一 `NOT_MEASURED` ⇒ 输入缺失（如缺 `team-names.txt`、缺 `selftest/run_all.sh`），等价于"没测"，不得提交时当它通过 |
| `--only=` | 只打印被点名的项 | 与全跑同一项不一致 ⇒ 判据之间互相依赖被破坏（例：G7 与 gen_index 的"条目"定义不同源） | 拼错 id ⇒ 什么都不打印，按 NOT_MEASURED 处理 |

## 7. 已验证的效果

- 基线（还没有这套脚本时）：本仓库出现过"文档里条目数与目录实际内容不一致"和"改了一行被尺子点名的句子导致尺子自己断掉"两类事故，
  记在 `report/log/ISSUES.md` #325 与 #331 两案（同一族：形状变了 = 判据静默失效）。
- 用它之后（2026-10-04 本次实测）：`gates.mjs` 第一次跑就打出 6 红，其中 4 条是**这套脚本自己的量纲错**
  （G1 把赛题规定的 `README.md`/`SKILL.md` 大写名判违规；G6 把生成区索引当"无目录的长文"；
  G7 与 `gen_index.mjs` 对"什么算条目"不同源；G8 把 `{a,b}.tcl` 简写与无扩展名裸台架名当路径）。
  逐条改对量纲后（不是降地板），**每轮的读数只对着那一份件念**：
  件 `build/evidence/r119_gates_now.txt` 末行 = `判定 12 项 绿=7 红=4 未测=1`（09:1x 那一轮，G1/G2/G6/G8 红）；
  件 `build/evidence/r120_gates_skill_a.txt` 与 `..._b.txt` 末行 = `判定 12 项 绿=8 红=3 未测=1`
  （10:40 那一轮，两跑逐字节一致；红 = G2 缺壳、G8 死链、G10 专有名未标注，未测 = G11 selftest 未落地）。
  两条红是真实的未完成（部分条目目录还缺 `SKILL.md`、一份参考页超长无目录），1 条未测是 `selftest/run_all.sh` 还没写。
  ⚠ 如实保留：首轮那 6 行的原文只在当次终端输出里，**没有单独留档**，所以现在无法逐字复核那一轮 ⇒ 这一条记 `【待验证】`；
  能复核的是改完之后这一轮：件 `build/evidence/r119_gates_now.txt`（十二行 + 末行汇总）。
- 阳性对照（本来就该变坏的用例）：删掉 `skill/_meta/team-names.txt` 后 G10 必须变 `NOT_MEASURED` 而不是 `PASS`；
  该对照**本次未执行** ⇒ 记 `【待验证】`。

## 8. 提炼来源与边界

- 来源证据：`build/evidence/r119_gates_now.txt`（现存这一轮的十二行原文）、`report/log/ISSUES.md` #325/#331（形状与射程）、
  `skill/_meta/naming-and-format.md`（G1–G12 每条的命令与条文依据）。
- 不再适用：换文档结构（例如取消"条目=目录+SKILL.md"）时，G2/G4 需要重写而不是放宽。
- 迁移要改两处：`CATEGORIES` 列表（四类以外的目录名）、以及 G10 的名单生成命令（别的仓库专有名来源不同）。
