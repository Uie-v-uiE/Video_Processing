# 怎么用这个包（给下一支队伍和他们的 agent）

## 30 秒接入

1. 把整个目录放进你的工程（常见位置：仓库根的 `skill/`，或 agent 的技能目录 `.qoder/skills/`）。
   它不依赖任何脚本被"安装"，纯文本 + 零依赖 Node 件。
2. 让 agent 先读 `README.md`（索引）与 `references/symptom-router/SKILL.md`（分派表）。
3. 之后按需加载：索引里挑一条 → 读它的 `SKILL.md` → 只有需要细节时才打开该条目下的
   `references/`（速查表）或运行 `scripts/`（工具）。**不要一次读整包**——
   三级渐进加载（元数据 → 正文 → 资源）就是为了让上下文花在正在干的活上。

## 人工用法（不看 agent 也能用）

- 立项阶段：`workflow/start-a-fpga-project` → `references/where-to-search`。
- 每一轮：`workflow/one-round-work-loop`（九步与产出物），记录用 `templates/round-diary`。
- 改 RTL 前：`workflow/before-an-rtl-change`；上板前：`workflow/before-touching-hardware`。
- 时序：`timing/global-timing-roster` 起步，其余按分派表。
- 交付前：`scripts/repro-drill`（点名的件在不在）、`scripts/gate-runner`（多判据跑批）、
  `pitfalls/package-integrity`（包自洽的判读口径）。

## 怎么改这个包（增/删/改条目）

1. 先在 `_meta/entry-map.md` 的对应类别里加一行（写清"解决什么"和"长自哪一类观察"）——
   地图先于条目，避免重复与空泛。
2. 按 `_meta/writer-contract.md` 写 `SKILL.md`（五节标题逐字、描述只写触发条件）。
3. 跑两道检查并**要求它们能动**：
   `node _meta/check-selftest.mjs`（尺子自己的能红对照）与
   `node _meta/check-skill-package.mjs <本包根>`（结构、四问、长度按字符、通用性、索引双向一致）。
4. 在 `README.md` 索引里补一行（机器会判"条目没列"和"索引死行"两个方向）。
5. 按 `_meta/authoring-standard.md` 的四道门验收：格式 → 可检索 → 增益 → 陌生人演练。

## 三条使用纪律

- **条目冲突时以条目为准**，分派表与索引只是入口；发现冲突就是"改口没改完"，按
  `pitfalls/doc-rotation-damage` 处理。
- **`已验证效果` 写「未量过，属建议」的条目**：用了要自己补读数，别当已证明的结论引用。
- **本包不含任何具体工程的事实**（器件上限、板卡引脚、某轮读数）。那些属于你自己的工程文档；
  如果你把工程专有内容写进本包，它就失去可复用性——检查器会把它判红。
