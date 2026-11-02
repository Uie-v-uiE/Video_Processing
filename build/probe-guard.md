# 残留进程防护（probe-guard）—— 现有脚本做到了哪一步 + 未触发的实验配方

对应 P15a 铁律 3（"自探测，失败即退"里"**是否有同名工具进程正在写同一目标目录**"那一项）
与质量判据 3（"人为开一个占用者，证明脚本会拒绝运行"）。
**本轮未执行该实验**（会与队伍正在占用的设备/会话冲突）⇒ 判据 3 记 `NOT_MEASURED`，
下面第 4 节是"谁来跑、怎么跑、跑完该看到什么"的配方，不是"已经看到过"。

## 1. 防的是什么（可判定的三条）

1. 残留的 Vivado/xsim 进程会继续写同一份 `runme.log`、`*_console.txt`、`build/system.bit`、
   门禁件 ⇒ 新读到的凭据是**上一轮**的，或两轮的字节混在一件里。
2. 一个还在跑的构建会占用 `vivado_system/` 工程目录；再起一次会撞 `-force`（入口脚本
   `build/tcl/build_system_axigpio.tcl:9` 无条件 `-force` 建工程）。
3. 判断"还在不在跑"**不能只看日志文件大小**：块缓冲下 stdout 可能满进程结束才落盘，
   0 字节日志既不证明开始也不证明没开始 ⇒ 要看工具自己的工作目录与进程表。

## 2. 现有脚本**实际**做了什么（逐条对回行号；没有的行就是没做）

进程探测这一族在本仓确实存在，但**全部集中在开发轮脚本里**，探测的都是**进程名**，
判语与退出码不统一：

| 脚本:行 | 探测语句（逐字要点） | 拒绝时的输出与退出码 |
|---|---|---|
| `build/r108_stage2.sh:13` | `tasklist //FI "IMAGENAME eq xsim.exe" \| grep -qi "xsim.exe"` | `断链：已经有 xsim 在跑（它会写同一份 run.log）` + `exit 1` |
| `build/r109_stage2.sh:16-18` | 同上（xsim.exe） | `STAGE2-REFUSE: …` + `exit 2` |
| `build/r110_apply_cuts.sh:35-36` | `tasklist \| grep -qi "vivado\.exe"` / `"xsim\.exe"` 两条分开 | `APPLY-REFUSE: …` + `exit 2`；**同文件 `:38` 还探了 `git status --porcelain` 的脏树** |
| `build/r113_chain2.sh:18-20` | `grep -qiE "^vivado\.exe"` | `REFUSE: 已有 Vivado 在飞（名册探针要独占）` + `exit 2` |
| `build/r113_roster_refanout.sh:22-27` | vivado.exe 与 xsim/xsimk 两条 | `exit 2` × 2 |
| `build/r113_step5_rotate.sh:18-20` | `^(xsim\|xsimk\|vivado)\.exe` | `exit 2` |
| `build/r114_replication_ab.sh:65-67` | `^vivado\.exe` | `exit 2` |
| `build/r115_c2_verdict.sh:22` | `^vivado\.exe` | `REFUSE 已有 Vivado 在飞` + `exit 2` |
| `build/r115_fanout_ab.sh:43` | `^vivado\.exe` | `REFUSE …（H4：不许在构建进行中动源）` + `exit 2` |
| `build/r113_after_chain_experiments.sh:29,36`；`build/r113_after_mf_uncertainty.sh:18,21-22` | 反向用法：**等**进程清干净再收口，超时 `exit 3` | `TIMEOUT: 没等到，不硬抢` |

## 3. 现行入口**缺**什么（这一节是本页的重点）

| 该探的 | 现行入口做了吗 | 缺，导致 |
|---|---|---|
| 起构建前有没有 `vivado.exe` 在飞 | **没有**。`build/r118_chain.sh` 全文不含 `tasklist`/`pgrep`（本次实跑 `grep -nE "tasklist\|pgrep" build/r118_chain.sh` 无命中） | 两个终端同时起链 ⇒ 第二次的 `create_project -force` 会拆掉第一次正在用的工程目录，而两边的 `> build/rNN_build_console.txt` 只有名字不同才不互覆；一旦 N 号相同就是**同一条凭据被两个进程写** |
| 目标目录（`build/`、`vivado_system/`）是否被别的进程持有 | **没有**。上表所有守卫都只看**进程名**，不看它的工作目录/命令行 ⇒ 探不到"另一个仓库的 Vivado 无关，但这个仓库的 Vivado 在飞"的区别 | 误挡（队友在跑别的 Vivado 时本仓不该停）与漏挡（进程改了名就看不见）双向都存在 |
| 工具版本是否等于声明值 | **没有**（任何一处都不做等值断言；版本串只是 Vivado 自己打进横幅，见 `build/r118_build_console.txt:1-4`） | 换到 2026.1 或别的 2025.2.x 后脚本照跑，产物照覆盖，**只有事后读报告才发现工具不是那一版** |
| 器件在不在设备库 | **没有**（靠 `create_project -part xc7z020clg484-2` 自己报错兜底） | 报错发生在建工程那一步，日志里像"工程打不开"而不是"器件缺" |
| 磁盘余量 | **没有**（`grep -rnE "df -|Avail" build/*.sh` 无相关命中） | 构建中途写满盘 ⇒ 位流半截、报告 0 字节，而门禁只看报告内容会读成"解析失败" |
| 归档不覆盖 | **没有**（见 `build/artifacts/README.md` 第 4 节 A2/A3） | 跑一次换一次已采纳产物 |
| 空指纹 REFUSE | **有**，但只在 r116 链里（`build/r116_chain.sh:23` 空指纹 ⇒ `exit 3`）；r118 链是"打印 rc 与值，不判空"（`build/r118_chain.sh:27-28`） | 尺子坏了（比如 `src/rtl` 被改名）时，r118 形链会带着空指纹继续跑完 19 分钟 |
| 退出码口径 0/1/2/3 | **不统一**：`exit 0` 通过、`exit 1` 红或没跑完、`exit 2` 既当"缺前置"又当"缺凭据"、`exit 3` 只在少数几处（含本应是"前置不满足=3"的 REFUSE 场景，如 `build/r116_chain.sh:23`） | 按退出码分支的外层脚本会判错；本轮先如实登记，不改判据 |

**当前机器的一次只读核对**（本会话实跑，用于证明"配方现在可跑、且此刻没有占用者"）：

```bash
tasklist 2>/dev/null | grep -ciE "^vivado\.exe"      # 实跑输出：0
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"name='vivado.exe'\" | Select-Object -ExpandProperty CommandLine"
                                                      # 实跑输出：空（无该进程）
df -h .                                               # 实跑输出：D: 330G 217G 113G 66% /d
```

第二条是**补上"同一目标目录"那一维**的现成手段：它回命令行，能从里面读 `-source` 与工程目录；
本仓现有守卫都还没用上它。（`wmic` 形态本次未验证可用，不写进配方。）

## 4. 未触发的实验配方（谁跑谁照抄，跑完必须清理）

P15a 判据 3 要的是"人为开一个占用者 ⇒ 证明脚本会拒绝运行"。分两步，**先甲后乙**：

**甲步（零风险，只测尺子，不碰任何脚本）**

1. 无占用者时判空：`tasklist 2>/dev/null | grep -qiE '^vivado\.exe' && echo BUSY || echo FREE` → 期望 `FREE`。
2. 另开一个终端，起一个**真会活着**的同类进程当占用者（例如 `"$VP_VIVADO_BIN/vivado.bat" -mode tcl`，
   或任一在跑的构建），回来重跑第 1 条 → 期望 `BUSY`。
3. 完成判据：同一条命令在两种状态下给出两种答案。甲步证的是 grep 与进程表，**不等于**证了脚本会拒绝。

**乙步（证明"脚本会拒绝运行"，有副作用，必须先读第 4 条再决定跑不跑）**

4. 风险声明：这些脚本的守卫只在**开头三行**，守卫一旦没触发（进程改名、编码把 `tasklist` 输出打成
   非 ASCII 导致 grep 落空、或该脚本本轮改过），脚本会**真的往下跑**——`r113_step5_rotate.sh` 会动文档、
   `r115_*` 会动源与证据目录。所以乙步必须选一个"往下跑也只是只读探针"的对象，或先把守卫三行
   单独粘出来跑；**不要**在队友在用板子/在跑构建的时候做乙步。
5. 期望看到（逐字形状，取自第 2 节表里的行）：首行 `REFUSE: 已有 Vivado 在飞`，退出码 `2`
   （`build/r113_chain2.sh:18-20` 这一支是最干净的样本），且**目标目录里没有新文件被创建**。
6. 证完清掉：关掉甲步那个占用者终端，`tasklist | grep -ciE "^vivado\.exe"` 回到 `0`，
   再确认第 5 条那支脚本没落下中间文件（它的 `mkdir -p` / `: > driver.log` 在守卫**之后**，
   正常拒绝时不该出现 ⇒ 出现了就是守卫没触发，属红项要当场记，不许当成"通过"）。
7. 记录：把甲/乙两跑的命令、原文输出、清理后的进程表，一并放进
   `build/artifacts/<日期>-<版本>-<指纹8>/`（`build/artifacts/README.md` 第 2 节的"证据"类）。

**本轮状态**：甲步第 1 条与第 3 节的只读核对已跑（结果如上）；甲步第 2 条与乙步**未执行** ⇒
判据 3 = `NOT_MEASURED`，被它挡住的"防护有效"这一句**不写**。
