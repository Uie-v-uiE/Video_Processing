# `workflow.md` · 智能体工作流：**设计**与**实际执行**的差异（P22 铁律 5）

写法：每一节先给"设计原文在哪（文件:行）"，再给"实际发生的实测数字/件"，最后给差异判定。
**实际是人手做的就写人手做的**（§5 整节就是这件事）。
所有"我算出来的"数字都在 `metrics.md` 有对应命令；所有指向的会话都在 `sessions/` 有登记卡。

---

## 1. 设计的形状（成文于何处）

| 设计条目 | 设计原文位置 |
| --- | --- |
| 单条任务八步闭环（取证→产出→自测→自审→处置→记录→提交→继续） | `prompts-used.md` §D 栏点名的 `skill_prompts/23-unattended-run-protocol.md`（第 2 节，本机文档目录，**不随包**） |
| 自审必须换身份（作者不许给自己放行；审计子代理只读） | 同上第 4 节；技能包侧成文为 `skill/prompts/read-only-review-agent/SKILL.md`（44 行） |
| 一次批量最多 4–5 个文件 | 同上第 3 节末段；本任务的派发词写的是"4–6 个文件为宜" |
| 后台链跑着时不许编辑它正在执行的脚本 | 同上第 5 节第一条 |
| 四件运行交付物（`RUN_REPORT/UNATTENDED/questions-for-team/run-queue`） | 同上第 6 节；本仓库落地口径写在 `report/unattended.md:1-6`（改名声明） |

**时间顺序必须先立正**：这份设计是 **2026-10-04 07:59–09:24** 成文的（31 个文件的 mtime，见
`sessions/s04-2026-10-04-docs-workspace.md` §2），而实际执行从 **2026-09-21 22:34** 就开始了
（`H01` 里已经写着"# 总目标（过夜无人值守 · 高自主）……禁止空等用户指示"，摘录见 `prompts-used.md` §A1）。
⇒ **规矩是事后补的**。本档案不许把这条顺序倒过来写。

## 2. 实际的形状（实测）

| 项 | 实测值 | 出处 |
| --- | --- | --- |
| 主 agent 派发子 agent 的总次数（冻结窗口） | **128** | `metrics.md` §3、S05 §3 |
| 落盘的子会话份数 | **127** | `sessions/s05-2026-10-04-subagents.md` 表（127 行） |
| 子会话类型分布 | `general-purpose` 98 · `Explore` 29 | S05 §2 |
| 子会话工具调用合计 | 9,093（人均 71.6） | `metrics.md` §3 |
| 单日派发最多的一天 | 26 场（UTC 2026-10-04）；其次 23 场（09-27）、20 场（09-28）、19 场（09-30） | S05 §8 末的分布行 |
| 一分钟内的并发派发峰值 | 6 场（`2026-09-27T15:55` 与 `2026-10-04T01:23`） | 本次复算（脚本见 §4 命令块） |
| 上下文压缩 | 主会话 75 次 `compact_boundary` | `metrics.md` §2 |
| 人工介入的形态 | 226 轮，其中大量是**板前肉眼判读**与**物理动作**（§5） | `sessions/s01…md` §6 |

## 3. 差异表（设计与实际不一致的地方，逐条判定）

| # | 设计说 | 实际发生 | 证据（可打开） | 判定 |
| --- | --- | --- | --- | --- |
| W1 | "一次批量最多 4–5 个文件（再多会中途耗尽轮次，留下半成品比没做完更糟）"；派发词写 4–6 | 每场子会话写过的**不同文件数**：`min 0 / 中位 1 / 均值 2.54 / 最大 23`；落在 4–6 区间的只有 **17/127 = 13.4 %**；**>8 个的有 11 场** | §4 的复算命令 + S05 表行 32/41/42/43/44/45（`0e6a6362e4b0` 17 个、`ef003d373d42` 16 个、`d276041bcceb` 21 个、`b0d4543a64fd` 23 个、`bad13a56ecf8` 18 个，派发时间集中在 2026-09-27T17:39–18:00Z） | **FAIL（设计与实际不一致）**：批量约束没有被遵守过，且大批次集中在同一天同一分钟 |
| W2 | "批次过大**曾导致**中途丢文件"（派发词里的因果句） | 冻结窗口内 128 派发 vs 127 导出，缺的那 1 条经定性是**参数校验失败即重发**（`Error: Agent tool parameter validation failed: params/mode must be equal to one of the allowed values`，00:41:19 失败，00:41:40 重发成功）；那 11 场 >8 文件的批次**没有一场**留下"少文件"的凭据 | S05 §3；`corrections.md` §6 U2 | **FAIL（断言无凭据，标为借用）**：不许把它当实测结论写进任何交付正文 |
| W3 | 八步闭环的第 6/7 步（更新 `run-queue` + `RUN_REPORT.md` + `git add` 本任务文件 + commit/push） | 本仓库把 `UNATTENDED.md` 落地成 `report/unattended.md`（存在，65 行，第 1–6 行逐字声明了改名理由），`run-queue.md`/`questions-for-team.md` 存在；**`RUN_REPORT.md` 与其改名版都本次未见** | `report/unattended.md:1-6`、`report/run-queue.md:3-5`、`report/questions-for-team.md` | **PARTIAL**：四件里落地三件；第四件（逐任务门禁摘要）在本次未核实到文件 ⇒ 记为**设计未完全落地**，不是"已完成" |
| W4 | 第 4 节"自审必须换身份……审计员只读不改" | `Explore` 类子会话 29 场；但**"Explore 是否一律零写入"我没有按类型分组复算**（只复算了全体分布） | §4 命令块第 3 行标注"未做" | **NOT_MEASURED**（缺按 `agentType` 分组的写入计数）；不许写成"已按设计分离" |
| W5 | 第 5 节"不要编辑正在被某个后台实例运行的脚本" | 本次取证期间**同一支尺子在几分钟内读数变化**：`node src/host/doc_enc_check.mjs` 先后给 `扫了 524 / 534 / 542 个手写文件`，`line_cite_check` 给 `扫 212 / 226 份交付文档` ⇒ 兄弟子会话当时正在往仓库里写文件（`docs/` 下 `unattended.md` 等文件在我第一次 `ls docs/` 之后才出现） | 本档案 §6 的读数表；`report/log/issues.md` #330/#333（同族：脚本死之前"看起来成功了"、我造的文件自己进了扫描射程） | **成立且被我复现**（不是靠记忆引用）：分母会漂，所以本档案所有数字带 `CUT` |
| W6 | P22 第 2 步"向我确认（然后 STOP）" | 无人值守（P23 第 0 节覆盖 STOP）⇒ 未确认项进问题清单 + 正文标【队伍未确认】 | `README.md` §6 | **按覆盖关系执行**（不是跳过） |
| W7 | P23 第 6 节要求写 `RUN_REPORT.md`/`UNATTENDED.md`/`report/run-queue.md` | 本任务的边界**只允许在 `report/collaboration/` 下新建文件** ⇒ 我没动 `docs/`，把等价内容写进 `README.md` §6（未确认项）与 §7（本次实际执行过的动作） | `README.md` §6/§7 | **冲突已就地声明**：`【队伍未确认】`是否接受这个替代 |

## 4. 复算命令（本档案里"批次大小"与"并发峰值"的唯一出处）

```bash
cd <本机 Qoder 目录>/projects/D--Xilinx-Prj-pro/<S01 会话目录>/subagents
python - <<'PY'
import json,glob,os,collections,statistics
CUT='2026-10-04T03:44:00'          # 与 metrics.md §0 同一常数
files=[]; zero=0; band=0; over8=0
for fp in sorted(glob.glob('*.jsonl')):
    mid=os.path.basename(fp)[:-6]; sid=mid.split('-')[-1][-12:]   # 与登记卡同规则的 SUB_ID
    got=set(); tmin=None
    for line in open(fp,encoding='utf-8',errors='replace'):
        s=line.strip()
        if not s: continue
        d=json.loads(s); ts=d.get('timestamp')
        if isinstance(ts,str) and len(ts)>=19 and tmin is None: tmin=ts
        m=d.get('message'); c=m.get('content') if isinstance(m,dict) else None
        if isinstance(c,list):
            for b in c:
                if isinstance(b,dict) and b.get('type')=='tool_use' and b.get('name') in ('Write','Edit'):
                    p=str((b.get('input') or {}).get('file_path',''))
                    if p: got.add(p.lower())
    if (tmin or '9')>=CUT: continue
    files.append((sid,len(got))); zero+= not got; band+= 4<=len(got)<=6; over8+= len(got)>8
cnt=[n for _,n in files]
print('SUBSESSIONS',len(cnt),'min',min(cnt),'median',statistics.median(cnt),
      'mean',round(sum(cnt)/len(cnt),2),'max',max(cnt))
print('ZERO_WRITE',zero,'IN_4_TO_6',band,'OVER_8',over8)
PY
# 并发峰值：对 S01 导出里每条 Agent tool_use 的 timestamp 取分钟桶计数
#   实测：2026-09-27T15:55 -> 6   2026-10-04T01:23 -> 6   2026-10-01T15:42 -> 4
# 按 agentType 分组的写入计数（W4 要的那一条）：本次未做
```

实测输出（本次跑）：

```
SUBSESSIONS 127 min 0 median 1.0 mean 2.54 max 23
ZERO_WRITE 60 IN_4_TO_6 17 (=13.4 %) OVER_8 11
```

## 5. 哪一步实际是**人手**做的（不许画成自动；每条给会话指针）

| 动作 | 为什么机器做不了 | 会话指针（S01 人工轮次） |
| --- | --- | --- |
| 断电 ≥10 秒后重新上电（E6 的前置条件） | 物理电源 | `H222` 10-03 01:46「我已经断电重启了然后你继续没完成的任务吧我睡了」；`H225` 10-04 07:38「我现在已经重新上电了让我判什么」；`H73` 09-26 08:01「我刚刚把那个板子断电了 现在接上了」 |
| 插 / 拔 SD 卡、插 / 拔网线 | 物理介质 | `H15`/`H17`（09-22 15:43/16:08）；`H28` 21:19「拔好了」、`H29` 21:27「插好了」、`H30`「已经插拔结束了」 |
| 按住 KEY1 做对照组 | 板上按键 | `report/log/issues.md:13093` 明写"对照组仍未做，需要再断一次电"⇒ 那一格只登记"未判" |
| **看屏幕判读**（黑线/细线/条带/角度） | 人眼是量测仪器 | `H108`–`H138`（09-27 那一大批，例如 `H132` 17:32「左边和上面的白线现在是看不到」）；终点是 `H226` 07:51 的两个字「0度」 |
| 让出串口/关掉终端窗口 | 独占资源 | `H106` 09-27 14:07「串口我关了 你试试吧」；`H158` 09-28 08:18「我把窗口关了 你自己看吧」；`H83` 09-26 10:03「发这个命令也停不掉…你直接发吧 我把窗口关了」 |
| 换线、判断"是线的问题" | 物理排障 | `H21` 09-22 16:58「不用找了…是因为我刚刚那根线有问题，换了一根线之后，它就能读到了」 |
| 指出方向性错误（C6 的第一次推翻） | 领域判断 | `report/timing/debt_ledger.md:174` 逐字写着"用户指出并已改口" |
| 报名/选题/截止日这类决策 | 队伍意志 | `H9`–`H12`（09-22 15:02–15:13）、`H178` 09-28 21:03「截止日11.4初级组不用pynq…」 |

> 反向清单（**不是**人手做的）：r115–r119 的探针与门禁、位流刷写三步 JTAG 链、名册差分、
> 文档尺子（`build/gates.sh`、`src/host/*.mjs`）都由 agent 跑；件在 `build/evidence/`。

## 6. 尺子读数漂移的实测（W5 的证据表）

| 命令 | 第一次（本地 11:5x） | 第二次（12:0x） | 第三次（写完档案后） |
| --- | --- | --- | --- |
| `node src/host/doc_enc_check.mjs` | `扫了 524 个手写文件：全部干净` | `扫了 534 个手写文件：全部干净` | 见 `README.md` §3 |
| `node src/host/line_cite_check.mjs` | `扫 212 份交付文档…硬错 0 条` | `扫 226 份交付文档…硬错 0 条` | 见 `README.md` §3 |

⇒ 结论写成两句：**硬错始终 0**（尺子没被我写坏）；**分母在漂**（别的子会话正在写同一个仓库）。
所以本档案规定：任何"共几条/几个"的断言都必须现跑现数，并且带上运行时刻。

**漂到极限的那一例（必须点名，因为它动了我的交付物本身）**：
`12:39` 兄弟子会话的装配提交 `1c4e26b` 把 `report/collaboration/` 里当时已存在的 10 个文件
**连同未定稿版本一起**提交了（`README.md` 反倒没进那次提交），我在那之后的修订（新增 C8、改锚点）
于是变成工作区里的 5 个 `M`。⇒ 三条规矩从这里出来：
① 并发链里"谁提交了什么"要按 `git log -- <我的目录>` 现查，不能假定只有自己在写；
② 交付物被连带提交 ≠ 自己越权提交，两者都要如实分开写（见 `README.md` §3 末）；
③ 以 `HEAD` 为入口读这份档案会读到旧版 ⇒ 队伍收尾需要再提交一次本目录。
另两例同类：`skill/evals/records/` 在我写作期间 0 → 2 份（§7 第 2 条）；
`build/evidence/r119_window_check.txt` 24 行 → 11 行，把我引用的三个锚点漂没了（`corrections.md` C8）。

## 7. 子 agent 的"这条没问题"必须被复算（本档案里三条实例）

1. **128 vs 127**：派发明细若照抄子 agent 的自报会漏掉那一条失败重发；本次靠 `toolUseId` 与
   `meta.json` 做外连接才暴露（命令在 `sessions/s05…md` §7）。
2. **`skill/evals/records/` 的份数在我写作期间从 0 变成 2**：11:5x 我 `ls` 得空目录，
   12:3x 复跑得 `audit-2026-10-04.md`、`stranger-run-2026-10-04.md` 两份（P09 第 3/4 步的演练/审计表）。
   复算之后仍然成立的那半句是：**这两份都不带 `skill/evals/README.md` §3 规定的 9 个字段**
   （`grep -c "被测条目"` 对两份都 = 0），也**没有一处引用会话登记号**（`grep -rIn "S0[1-5]\|sessionId\|jsonl"` = 0）。
   另外技能索引生成器 `skill/scripts/check/gen_index.mjs:72-74` 会把"已复跑(见 evals/records/…)"写成状态值
   ⇒ 凡是走到那一支的条目，其引用的记录必须逐条存在，否则"已复跑"就是空指。
   **这条是"照抄子 agent 自报会漏"的直接样本**：如果我沿用 11:5x 的读数写"目录为空"，现在就是假话；
   所以 `README.md` §4 把两次读数都记下（缺口 G6）。
3. **技能包成品未入库**：`git ls-files skill` = 32 个已跟踪，`git ls-files --others` = **96 个未跟踪**
   ⇒ "技能条目已经交付"这句话在当前工作树里只能说到"写到盘上"，说不到"已提交"。

## 8. 质量判据 5 的对照表（workflow 的每一步能否找到对应记录）

| 本节步骤 | 对应记录 | 找到? |
| --- | --- | --- |
| §1 五条设计原文 | `skill_prompts/23…md`（本地）+ `report/unattended.md:1-6`（随包） | 找到（原件不随包，见 §3 W3） |
| §2 八行实测数字 | S05 表 127 行 / `metrics.md` §2–§3 | 找到 |
| W1–W7 | 每条都有 S05 行号或仓库文件:行 | 找到 |
| §4 命令 | 本次实跑，输出抄在 §4 末 | 找到 |
| §5 人手步骤 | 全部给 `H##` + 时间戳；两处给 `ISSUES`/`debt_ledger` 行 | 找到 |
| 设计未落地项 | W3 的第四件、W4 的分组复算 | 已标（找不到数 = **0**，未落地项 2 条已显式命名） |
