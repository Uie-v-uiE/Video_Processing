# 登记卡 S04 · 文档工作区的 4 场会话（提示词的"写作现场"，不在本仓库工作区）

这四场导出**不在本仓库的工作区键下**（它们在 `projects/C--<本机用户>-Documents-Qoder-<日期>-<id>/`），
但本仓库里的两处文档**直接点名**了它们的产物，所以必须登记，否则 `prompts-used.md` 的对应关系接不上。
它们**不计入**本仓库会话分母（分母口径见 `../metrics.md` §1）。

## 1. 四场清点（同一支 `python` 一次跑完，命令见 §4）

| 登记号 | 工作区目录名（已脱去用户段） | 导出文件名 | 字节 | 行数 | SHA-256 前 12 | 时间范围（本地） | 人工轮次 | `tool_use` | `is_error` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| S04-a | `…-2026-09-20-a1c98296` | `a1c98296-…-b9b064b.jsonl` | 59,119 | 56 | `632c70a7efdd` | 09-20 12:08:05 → 12:09:02 | 1 | 8 | 0 |
| S04-b | `…-2026-10-01-cc03d7a4` | `cc03d7a4-…-99b4d437.jsonl` | 1,819,117 | 813 | `17e14bd65c6c` | 10-01 15:59:28 → 17:24:00 | 3 | 137 | 6 |
| S04-c | `…-2026-10-03-6c22b30a` | `6c22b30a-…-5174e29d18b3.jsonl` | 345,250 | 210 | `34cabeb405c3` | 10-03 20:21:41 → 20:31:38 | 1 | 30 | 1 |
| S04-d | `…-2026-10-04-3d601c82` | `3d601c82-…-edcbc3a26fa.jsonl` | 1,609,277 | 808 | `30cd5d2356d2` | 10-04 07:50:59 → 09:25:21 | 6 | 146 | 6 |

## 2. 为什么 S04-c 与 S04-d 与本仓库有硬关联

**S04-c = 时序轮次提示词的成文现场。** 它跑在 10-03 20:21:41 → 20:31:38，
而这份文件 `<文档工作区>/2026-10-03/6c22b30a/timing-global-round-prompt.md`
的 mtime 是 **10-03 20:30**（21,433 字节，SHA-256 前 12 `a90fb0ec7cfc`）——落在该窗口内。
本仓库直接点名它的地方：`仓库留档 r116_batch_plan.md（剪枝件，不随包）:5`（原文里写的是这台机器上的绝对路径，
开发台账 的 #307/#319 那一族故障就发生在这支 r116 批次里）。
⇒ r116/r117 那几轮的提示词原文**不在 S01 里**，在这个文件里；`../prompts-used.md` §C 按这个口径列。

**S04-d = 队伍任务提示词集（P00–P23）的成文现场。** 该目录下 `skill_prompts/` 共 **31** 个 `.md`
（24 个编号任务 + 拆分子任务 15a/15b/15c/16a/16b/16c/18a/18b/18c + `README.md`），
mtime 全落在 S04-d 的窗口内：最早 `00-charter.md` **07:59:46**（6,285 字节，SHA-256 前 12 `e19218989e16`），
最晚 `23-unattended-run-protocol.md` **09:24:43**（11,098 字节），本条规格
`22-collaboration-log-archive.md` 是 **09:16:57**（5,022 字节，SHA-256 前 12 `38b2e96217e4`）。
⇒ **这套提示词是被"事后成文"的**，S01 的 226 轮人工输入里一条都没有逐字出现过
（复算命令与 0 命中结果见 `../prompts-used.md` §D）；它们进入执行链的方式是
**主 agent 在派发子 agent 时按路径引用**（6 份子会话导出里点名了具体 `skill_prompts/NN-*.md`，见 `s05` 表的 `PROMPTFILE` 列）。

## 3. 任务号与是否随包

| 登记号 | 任务号 | 结论落点（本仓库内） | 是否随包 |
| --- | --- | --- | --- |
| S04-a | 前身工程（与 S03 同日同时刻段） | 无直接落点 | **不随包**（跨工作区 + 含本机绝对路径） |
| S04-b | 未映射（P0x 系列之前的技能/文档讨论段） | 无直接落点 | **不随包**（同上） |
| S04-c | 时序轮次 r116/r117 的轮次提示词写作 | `仓库留档 r116_batch_plan.md（剪枝件，不随包）`、时序全局记录、那一轮的逐轮页 | **不随包**（同上；但被点名的**那份提示词文件本身**是本仓库的引用对象，见 §2） |
| S04-d | P00–P23 提示词集的编写 | `skills/*`（经 S05 派发落地）、任务队列 | **不随包**（同上） |

## 4. 复算命令（四行一起出）

```bash
cd <本机 Qoder 目录>/projects
python - <<'PY'
import json,glob,os,hashlib
def ts(x): return x if isinstance(x,str) else ''
for fp in sorted(glob.glob('C--*-Documents-Qoder-*/*.jsonl')):
    n=0; h=hashlib.sha256(open(fp,'rb').read()).hexdigest()[:12]
    tmin=tmax=None; hum=0; tu=0; er=0
    for line in open(fp,encoding='utf-8',errors='replace'):
        s=line.strip()
        if not s: continue
        n+=1; d=json.loads(s); t=ts(d.get('timestamp'))
        if len(t)>=19:
            tmin=min(tmin or t,t); tmax=max(tmax or t,t)
        m=d.get('message'); c=m.get('content') if isinstance(m,dict) else None
        if d.get('type')=='user' and d.get('humanInput'): hum+=1
        if isinstance(c,list):
            for b in c:
                if isinstance(b,dict):
                    if b.get('type')=='tool_use': tu+=1
                    elif b.get('type')=='tool_result' and b.get('is_error'): er+=1
    print(os.path.basename(fp), os.path.getsize(fp), n, h, tmin, tmax, 'human=',hum,'tool_use=',tu,'is_error=',er)
PY
# 行数与提示词集的 mtime
find <本机 Qoder 目录>/projects/C--*-Documents-Qoder-* -name '*.jsonl' -exec wc -l {} +
stat -c '%y %s %n' <文档工作区>/2026-10-04-3d601c82/skill_prompts/*.md
sha256sum <文档工作区>/2026-10-03/6c22b30a/timing-global-round-prompt.md | cut -c1-12
```

> 注：`tmin/tmax` 打印的是**日志内的 UTC** 字符串，本卡表里已按 +8 折成北京时间。
> 换算式：`local = utc + 8h`（本机在东八区，无夏令时）。不换算就把 UTC 当日当本地当日，会把
> 09-21 晚上那批记录记到 09-21 白天——本档案的所有日期都是**北京时间**口径。
