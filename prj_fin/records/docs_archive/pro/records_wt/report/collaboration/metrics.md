# `metrics.md` · 协作成本统计（全部从会话导出现算，无一条来自回忆）

**输入文件**（都在本机，不随包；身份核对靠登记卡里的 SHA-256）：

| 代号 | 文件 | 登记卡 |
| --- | --- | --- |
| `LOG-MAIN` | `b20eed02-764d-4c48-b7a8-2791ce120863.jsonl` | `sessions/s01-2026-09-21-b20eed02.md` |
| `LOG-STRAY` | `658cc4e8-4373-47c3-83c5-93ab50cab5de.jsonl` | `sessions/s02-2026-10-01-658cc4e8.md` |
| `LOG-HANDOFF` | `179d559b-638d-4185-96bf-ab467d23a233.jsonl` | `sessions/s03-2026-09-20-handoff-179d559b.md` |
| `LOG-DOCS-4` | `a1c98296…/cc03d7a4…/6c22b30a…/3d601c82…` 四份 | `sessions/s04-2026-10-04-docs-workspace.md` |
| `LOG-SUB-127` | `…/subagents/agent-*.jsonl`（127 份，逐行见 S05 表） | `sessions/s05-2026-10-04-subagents.md` |

## 0. 口径（先读这段，否则下面每个数字都会被读错）

- **冻结时刻 `CUT = 2026-10-04T03:44:00Z`（本地 11:44:00）**。除"文件级"三件套（字节/行数/哈希）外，
  所有计数只算 `timestamp < CUT` 的记录。原因见 `sessions/s01…md` §2：导出在我取证期间仍在被写。
- **轮次 = 一次人工输入 = 一轮**（记录里带 `humanInput=true` 的 `user` 记录）。
  agent 内部循环、工具返回、`active-leaf` 心跳**都不算轮次**。
  ⇒ 派发给子 agent 的那条正文，在子会话导出里也被标成 `humanInput=true`（S05 §2 实测每份恰好 1 条），
  所以子会话的 127 条**不与主会话的 226 轮相加**；相加会得到 353 这个错数。
- **重试 = 同一次人工输入（同 `promptId`）内，同一工具、同一输入文本（`json.dumps(sort_keys=True)` 规范化、截 400 字符）
  的第 2 次及以后出现**。一次重试**不另算一轮**（口径已在上一条写明：重试是调用级计数，不是轮次级）。
- **失败 = `tool_result` 块里 `is_error=true` 的返回数**。这是"这一刀没砍动"的下限口径：
  工具正常返回但内容判红的（例如门禁红项）**不计入**，那种红在 `report/log/issues.md` 里逐条成文。
- **工具调用 = `tool_use` 块数**。`LOG-MAIN` 里 `isSidechain=true` 的记录数为 **0**（实测），
  所以主会话的调用数**不含**子 agent 的调用，两个 scope 必须分开报。
- **墙钟**：日志时间戳是 UTC，本档案一律折成北京时间（+8h，本机无夏令时）。
  "活跃时长"= 把 `assistant`/`user`/`system` 三类记录的时间戳排序后，累加**相邻间隔 ≤ 20 分钟**的部分；
  间隔 > 20 分钟视为离开（睡觉、等构建、断电重上电）。"跨度"= 首末时间戳之差，**不是**工时。

## 1. 会话数

```bash
cd <本机 Qoder 目录>/projects
ls -1d */ | wc -l                                      # 工作区目录数
for d in */; do echo "$d $(ls -1 "$d"*.jsonl 2>/dev/null | wc -l)"; done
find . -maxdepth 2 -name '*.jsonl' | wc -l             # 导出总份数
```

| 项 | 值 | 判定 |
| --- | --- | --- |
| 本机工作区目录数 | 10 | PASS |
| 含 `*.jsonl` 的目录数 | 6 | PASS |
| 导出总份数（不含子会话目录里的） | **7** | PASS |
| 其中属于本仓库工作区键 `D--Xilinx-Prj-pro` | **2**（S01、S02） | PASS |
| 邻仓（`D--Xilinx-Prj-project-handoff`） | 1（S03，不计入本仓库分母） | PASS |
| 文档工作区（`C--…-Documents-Qoder-…`） | 4（S04-a…d，不计入本仓库分母） | PASS |

⇒ **本仓库会话数 = 2**；带子会话后 = **2 + 127 = 129**（口径：冻结窗口内首条记录）。
盘上子会话导出实数 **137** 份，被 `CUT` 排除 **10** 份（= 本次 P22 运行自己触发的批次）。

## 2. 轮次 / 工具调用 / 失败 / 重试 / 压缩（`LOG-MAIN`）

```bash
python - <<'PY'          # 输入：LOG-MAIN；CUT 见 §0
import json
CUT='2026-10-04T03:44:00'
def tstr(x): return x if isinstance(x,str) else ''
def norm(o):
    try: return json.dumps(o,sort_keys=True,ensure_ascii=True)[:400]
    except Exception: return str(o)[:400]
import collections
pairs=collections.Counter(); id2k={}; errkey=set()
hum=tool_use=tool_res=errs=0; comp=0; tss=[]
for line in open('b20eed02-764d-4c48-b7a8-2791ce120863.jsonl',encoding='utf-8',errors='replace'):
    s=line.strip()
    if not s: continue
    d=json.loads(s); ts=tstr(d.get('timestamp'))
    if not ts or ts>=CUT: continue
    if d.get('type')=='system' and d.get('subtype')=='compact_boundary': comp+=1
    if d.get('type') in ('assistant','user','system'): tss.append(ts[:19])
    m=d.get('message'); c=m.get('content') if isinstance(m,dict) else None
    if d.get('type')=='user' and d.get('humanInput'): hum+=1
    if isinstance(c,list):
        for b in c:
            if not isinstance(b,dict): continue
            if b.get('type')=='tool_use':
                tool_use+=1
                k=(str(d.get('promptId') or d.get('requestSetId') or ''),str(b.get('name')),norm(b.get('input')))
                pairs[k]+=1; id2k[str(b.get('id'))]=k
            elif b.get('type')=='tool_result':
                tool_res+=1
                if b.get('is_error'):
                    errs+=1; k=id2k.get(str(b.get('tool_use_id')))
                    if k: errkey.add(k)
import datetime
tss.sort(); act=0
prev=datetime.datetime.strptime(tss[0],'%Y-%m-%dT%H:%M:%S')
for x in tss[1:]:
    dt=datetime.datetime.strptime(x,'%Y-%m-%dT%H:%M:%S'); g=(dt-prev).total_seconds()
    if g<=1200: act+=g
    prev=dt
print('LINES_WITH_TS_BEFORE_CUT',hum,tool_use,tool_res,errs,comp)
print('REPEAT_CALLS',sum(v-1 for v in pairs.values() if v>1),
      'GROUPS',sum(1 for v in pairs.values() if v>1),
      'GROUPS_AFTER_ERROR',sum(1 for k,v in pairs.items() if v>1 and k in errkey))
print('ACTIVITY_RECORDS',len(tss),'SPAN',tss[0],tss[-1],'ACTIVE_MIN',round(act/60,1))
PY
```

实际输出（**下面两块是我真跑两次分开的脚本得到的原样终端输出**；上面那段合并脚本是我把它们并成一次
的可复跑版本，**我没有把它当成已执行过**——复跑它应当重现这两块的每一个数字）。

```
# 跑 A（轮次 / 工具调用 / 失败 / 重试 / 墙钟 / 冻结记录数）
CUTOFF 2026-10-04T03:44:00
LINES_BEFORE_CUT 99531
HUMAN_TURNS 226 first 2026-09-21T14:34:44 last 2026-10-03T23:51:22
TOOL_USE 25053 TOOL_RESULT 25053 IS_ERROR_RESULTS 760
REPEAT_CALLS_TOTAL(重试口径A: 同 promptId 同工具同输入的第2次及以后) 397
REPEAT_GROUPS(口径A 去重后组数) 255
REPEAT_GROUPS_AFTER_ERROR(失败后重试组数) 60
ACTIVE_RECORDS 78416 SPAN 2026-09-21T14:34:44 -> 2026-10-04T03:43:38
ACTIVE_MINUTES_gap20min 13847.5 = 230.79 h

# 跑 B（上下文压缩边界，同一输入文件、同一 CUT）
COMPACT_BOUNDARY_before_cutoff 75 ALL 75
```


| 指标 | 值 | 分母/口径 |
| --- | --- | --- |
| 人工轮次 | **226** | 首条 `09-21 22:34:44`，末条 `10-04 07:51:22`（本地） |
| 工具调用 | **25,053** | `tool_use` 块；`tool_result` 同为 25,053 ⇒ 无悬挂调用（差值 0） |
| 失败（`is_error`） | **760** | 占调用数 **3.03 %**（760/25,053） |
| 重试 | **397** 次重复调用，分布在 **255** 组 | 组数分母 = 255；其中 **60 组**（23.5 %）发生在首次即失败之后 |
| 上下文压缩边界 | **75** 次 | `system/compact_boundary`；判 75 项，冻结前后同值 |
| 带时间戳记录（冻结内） | 99,531 | 快照 `wc -l` 174,969 − 无时间戳记录 ⇒ 心跳类占 4 成 |
| 活跃时长 | **13,847.5 min = 230.79 h ≈ 9.62 天** | gap ≤ 20 min，`assistant`/`user`/`system` 三类，共 78,416 条 |
| 跨度 | 2026-09-21 22:34:44 → 2026-10-04 11:43:38（本地）= **12.55 天** | **不是**工时，含全部离开时段 |

## 3. 子会话侧（`LOG-SUB-127`）

```bash
# 输入 = LOG-MAIN（取 128 条 Agent 派发的 toolUseId/时刻/正文）+ 127 份 agent-*.jsonl
# 冻结常数 CUT 同 §0；列口径同 sessions/s05-…md §4
# S05 那张 127 行表格由同一段口径的脚本生成（脚本本体未入库，原因见 s05 §7）
# 输出（本次实测，原样）：
#   SUBAGENT_FILES_TOTAL_ON_DISK 137
#   SUBAGENT_FILES_STARTED_BEFORE_CUTOFF 127 STARTED_AFTER_CUTOFF_EXCLUDED 10
#   SUM bytes=110853285 lines=28227 tooluse=9093 iserr=190
#   BY_AGENTTYPE {'Explore': 29, 'general-purpose': 98}
#   ROWS_WITH_EXPLICIT_P_TOKEN 10  ROWS_WITH_PROMPTFILE_REF 6  ROWS_WITHOUT_DISPATCH_MATCH 0
```

| 指标 | 值 | 口径 |
| --- | --- | --- |
| 子会话数 | **127** | 首条记录 `< CUT` |
| 子会话工具调用 | **9,093** | 与主会话 25,053 **相加** = 34,146（两 scope 只在"合计"一行相加） |
| 子会话失败 | **190** | 占 **2.09 %**（190/9,093） |
| 子会话合计行数 | 28,227 | 非空行 |
| 子会话字节 | 110,853,285 | ≈ 105.7 MiB |
| 派发失败即重发（无导出） | **1** 条 | `tool_use_id = call_4106533be23141b1a2ebcd3f`，128 派发 − 127 导出 = 1，定性见 S05 §3 |

**合计口径行**（只在两 scope 各自成立后才相加）：工具调用 **34,146**、失败 **950**（占 2.78 %）、
会话 **129**、人工轮次 **226**（**不**加子会话的 127 条派发消息）。

## 4. 其它三场（同一命令换输入文件名）

| 会话 | 人工轮次 | `tool_use` | `is_error` | 行数 |
| --- | --- | --- | --- | --- |
| S03（邻仓 handoff） | 39 | 1,836 | 77 | 10,782 |
| S04-a | 1 | 8 | 0 | 56 |
| S04-b | 3 | 137 | 6 | 813 |
| S04-c | 1 | 30 | 1 | 210 |
| S04-d | 6 | 146 | 6 | 808 |
| S02 | 1 | 0 | 0 | 17 |

> S03/S04 的数字**不计入**本仓库分母（§1 的口径），列在这里只为了让"本机一共跑过多少场"可核。

## 5. 算不出的项（逐条写"缺什么"，不许用估算填）

| # | 想要什么 | 状态 | 缺的东西 |
| --- | --- | --- | --- |
| 1 | token 用量 / 费用 | `NOT_MEASURED` | 导出里 `message.usage` 的 `input_tokens`/`output_tokens`/`cache_read_input_tokens` 逐条求和 = **0 / 0**（实跑）⇒ 这份导出没落 usage 字段，任何"花了多少 token"的说法都无从算起 |
| 2 | 阈值敏感性（gap 取 15/60 分钟时活跃时长怎么变） | `NOT_MEASURED` | 缺"同口径（`assistant`/`user`/`system` + `CUT`）下的第二组读数"；我早先跑过的 13,621.8 / 14,080.3 / 14,607.0 min 是**另一个口径**（含 `active-leaf` 心跳、且未加 `CUT`），两者不可并列比较，故不写进 §2 |
| 3 | 逐轮"这一轮改了哪些文件"的归属表 | `NOT_MEASURED`（可算，未做） | 记录里有 `promptId` + `Edit`/`Write` 的 `file_path`，把两者关联一次即可得出；本任务未排期这条脚本 ⇒ 不做，`README.md` §2 的"结论落点"因此用的是 `report/log/issues.md` 与 `report/run-queue.md` 已成文的对应关系，而不是会话侧自算 |
| 4 | 子会话并发峰值（同一秒最多几场） | `NOT_MEASURED`（口径未定） | 缺"并发"的定义：按 `Agent` 调用同秒、还是按 `toolUseId` 批次号；定义未定就出数会是假数 |
| 5 | 760 次失败 / 397 次重试的**动机分类**（语法错 / 路径错 / 判据红 / 权限） | `NOT_MEASURED` | 缺人工标注；`is_error` 的正文确实带报错文本，但自动分类要立分类表并逐条核，本任务不立表 |
| 6 | S02、S04-a、S04-b 的任务号 | 未映射 | S02 工具调用为 0 ⇒ 盘上无落点；另两场的正文我没有逐条读（隐私最小必要），缺"与仓库文件的对应凭据" |
| 7 | 模型/客户端版本切分的时长与调用数 | 借用（口径不同） | `version` 字段实测分布 `1.1.64:57,919 / 1.1.62:23,492 / 1.1.57:12,248 / 1.1.61:5,923`（合计 99,582 = 全文件带时间戳记录数，**不是**冻结口径）⇒ 只登记，不参与 §2 的任何分母 |
