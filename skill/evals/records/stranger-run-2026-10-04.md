# 陌生人演练记录（P09 第 3 步）

- 被测对象：`skill/` 技能包整体（演练前提：只允许读这一个目录）
- 执行方式：新会话子 agent（`subagent_type=general-purpose`，**看不到本次对话上下文**），只读权限，
  提示词里明确"不许写文件、不许跑构建、不许读仓库其它目录、答不出就明说不要编"
- 时间：2026-10-04 04:21（本机），工具：仓库工作树（未提交状态，条目数 25）
- 处置约定：**原话照存，不润色、不补解释**；答错/答不出/需追问的记成红项，并列出据此回改了哪个文件哪一节。
  禁止因为演练失败就删掉问题。

---

## 它收到的五个问题（原文）

1. 我要给一个新模块加寄存器，先看哪几个文件？按顺序说出文件名。
2. 板上跑不通、寄存器读回复 0，你的第一步检查动作是什么？依据来自哪一节？
3. 这里的校验脚本我怎么跑？跑之前要准备什么？
4. 哪几条技能明确写了"不适用于我们的场景"？说出条目名与失效条件原文。
5. 把这套东西搬到你自己的题目（它自己虚构一个）上，你需要改哪几处？

---

## 它的原样回答

### Q1

我按"先立判据 → 再立表 → 改表 → 跑校验 → 上板验"的顺序，只看 `skill/` 里的话，会依次开这些文件：

1. `SKILL.md`（包根，不占 S 号）——「工作循环」+「硬规则」1/2/3（量在改之前、单变量、新判据必须先能红），它决定我第一步不是改 RTL。
2. `runtime/register-map/SKILL.md` §5.1「真相源表：十个字段，缺一个就对应一类具体事故」→ §5.2「从真相源派生的四处，与"改表之后必须跑什么"」→ §3 第 3 条（位序不许重排）。
3. `templates/interface-contract/SKILL.md` §2（"当新增一个通道、一批状态窗口或一批 lane，需要同时改 RTL mux、主机访问层与文档三处时"）+ §5.1 步骤 1–6。
4. `templates/interface-contract/contract-table.md` §1 主表与逐列填写口径、§2「三类最容易漏的字段」（窗口式读回 / 反相位 / 只在静止窗口生效）、§4 一致性检查 C1–C4。
5. `scripts/regmap_check/axi_gpio_contract.tsv`（表头那 22 列 + 头部注释）与 `scripts/regmap_check/contract.tsv`（13 列那份），看现成的行形状。
6. `scripts/regmap_check/regmap_check.mjs` 头部 K1–K8 判据清单（改完表跑哪八条）。
7. `scripts/contract_gen/contract_gen.mjs` 头部（`REQUIRED` 十个必填字段，缺一格退 3）。
8. `runtime/host-bindings-and-reports/SKILL.md` §5.1「主机侧读数代码：三处读者 + 每处自带判据」及"改表时的三步"三条命令。
9. 如果这个新寄存器属于"先写索引、再读同一个数据口"那一族：`atomic_register_window_readback.md`「动作」第 5 条（新成员必须排在该组第一个字之后）与第 6 条（快照自带可信位）。
10. `runtime/pl-load-verify/SKILL.md` §5-A 表 5-A 的 L1/L2 + §5-C「校验闭环」（写图案读回那一层）。
11. `zynq-video-rtl-debug/SKILL.md` §4 那张表（"新模块上全流程前的结构预检"用 `build/tcl/ooc_newmods.tcl`，`OOC_ONLY` 一次一个，它的数字不是门禁）。
12. 若手上还没有能红的判据，先走 `prompts/criterion-before-code/SKILL.md`（我只抽读了它的 §3 与 §8，正文其余节没读）。

我需要更多信息，缺什么：`runtime/register-map/SKILL.md` §5.2 第 3 步明写"跑一致性判定（本仓的对应物，不是 scripts/regmap_check/ —— 那个目录在本仓不存在）"，§8 第④处又写"本仓没有 `scripts/regmap_check/`，别照抄成路径"；但本包里 `skill/scripts/regmap_check/` 实际存在（`ls` 到 `regmap_check.mjs` + 两份 tsv）。两处口径相反，而我这次不能读 `src/`、`build/`、`report/`，所以"改完寄存器表到底跑哪一层校验"我按哪一份执行判不了。另外 `axi_gpio_contract.tsv` 头注释把列口径指到 `skill/scripts/regmap_check/SKILL.md 第 5 节`，该文件在包内不存在 ⇒ 那 22 列的填写口径原文我找不到。

### Q2

我的第一检查动作：**把"0"当成待证的对象而不是一个值，立刻做一次纯调试器/纯固件侧的"往保留字段写一个非零图案 → 读回 → 逐位比对"**，同一次运行里顺带确认"是真读到 0 还是根本没读到"。依据原文与节号：

- `runtime/pl-load-verify/SKILL.md` **§6** 表里 L1 那一行：`挂住或无返回 ⇒ 回 5-C 查 DONE 行与地址段 assign；返回全 0 ⇒ 记下"这份位流里可能没有这个从设备"这个候选，进 L2 用图案证它`；同一行第三列：`拿不到调试器输出 ⇒ NOT_MEASURED，不许把"没读到"写成"读回 0"`。
- 同文件 **§5-A 表 5-A** L1/L2 两行 + 那句"L1 必须是第一层：它是这条链里唯一不依赖任何软件配合、也不需要应用先跑起来的判据"。
- `runtime/register-map/SKILL.md` **§5.3** 判读口径：`src/ps/main.c:1554-1557` 的注释写的是"**不存在的从设备常常也返回 0，那种判据不会红**"，所以必须写一个非零图案再读回来比对；图案落在保留段的理由是同节"探针故意放在**保留段**，因为'探针不许命令硬件'"。
- 同文件 **§5.5** 越界那一行：`期望调试器报总线错误；**静默返回 0 是最坏的一种**，因为它把"没有从设备"伪装成"值为 0"`。
- 如果这个 0 是经"先写 lane 号再读数据口"读回来的：`runtime/register-map/SKILL.md` **§6** `health_read` 行给出另一条优先分叉：`恒 0 且 lane 号未回读确认 ⇒ 很可能读到的是 lane0（ISSUES #55：PS 每帧整字重写会抹掉 lane 号）`；配合 `atomic_register_window_readback.md`「动作」第 2 条"判红后先怀疑读法"。
- 判据侧兜底：`bench_self_inflicted_reds.md` 十签名第 6 条：`几条问法都返回 0，看起来就是"没有"` ⇒ 修法"`"查不到"之前先放**阳性对照**：同一次运行里查一个明知存在的东西；对照没过，那个 0 是命令语法问题，不是事实`。
- 两种特殊情况它给了不同的第一步：只"读不回/挂住"而非回 0 ⇒ 按 §5-A L1 失败列先确认 DONE 与地址段 assign（不改 RTL）；若同时"串口一个字节不回、JTAG 里核仍显示 Running" ⇒ 按 `runtime/pl-load-verify/SKILL.md` **§5-D** 的恢复顺序（`rst -system` → 重初 PS → 重编 PL → 重载应用 → 再起流量）。

我需要更多信息，缺什么：①"读回复 0"是调试器 `mrd`、固件开机自检，还是上位机脚本 `health_read.mjs` 读到的？三者的第一动作分别是 §5-A L1、§5.3、§6 health_read 行。②是**恒 0**还是只低位/某几位 0——`§5-A` L2 失败列把这两种分开（恒 0/恒 F = 从设备不在位流上；只低位对 = 顶层线宽吞高位）。③核当前是不是 halt 态：`runtime/register-map/SKILL.md` §4 写"lane 窗口必须在 halt 态读"。这三条问题里没给，我按最常见的"mrd 直接回 0"答。

### Q3

分两类，因为包里只有第一类是真脚本。

**第一类：技能包自身的装配校验（`skill/scripts/` 里真实存在的脚本）**，跑法与前置照 `scripts/check/SKILL.md` **§4/§5** 与 `scripts/check/gen_index.mjs`、`gates.mjs`、`static_check.mjs`、`retire_flat.mjs` 的头部注释：

- `node skill/scripts/check/gen_index.mjs --check`（只比不写）→ `node skill/scripts/check/gen_index.mjs`（重写 `README.md` 生成区）→ `node skill/scripts/check/gates.mjs`（G1–G12 十二行 + 末行汇总）→ 排障用 `node skill/scripts/check/gates.mjs --only=G7,G8`。
- `node skill/scripts/check/static_check.mjs [--root skill/scripts] [--exe bash,node]`（T1 无网络 / T2 无工程目录写入 / T3 守卫在场且真的拒绝 / T4 违规样本必须被抓 / T5 阈值不许带默认值 / T6 `--help` 覆盖每个 flag）。
- `node skill/scripts/check/retire_flat.mjs`（默认只读，`--apply` 才删）。
- 契约类四支都要**显式给输入**，脚本自己写了"没有兜底默认值"：`node skill/scripts/regmap_check/regmap_check.mjs --contract skill/scripts/regmap_check/axi_gpio_contract.tsv --bd build/tcl/build_system_axigpio.tcl`；`node skill/scripts/contract_gen/contract_gen.mjs --contract skill/scripts/regmap_check/contract.tsv --out-dir skill/scripts/_out/gen`；`node skill/scripts/golden_compare/golden_compare.mjs --golden … --produced …`（头部给的复跑行点了 `build/CDC_BASELINE.txt`、`build/frozen_r23_srcseen/cdc.rpt`）；`node skill/scripts/report_metrics/report_metrics.mjs --timing … --utilization … --out-dir …`；`node skill/scripts/repro_check/repro_check.mjs capture|verify --root … --out-dir …`。
- 退出码一律四态：`0=PASS 1=FAIL 2=NOT_MEASURED 3=前置不满足`（各脚本头部与 `gates.mjs` 第 6 行、`scripts/check/SKILL.md` §6 都写了）。

**跑之前要准备**（逐条出处）：① 必须站在仓库根——`scripts/check/SKILL.md` §4「在仓库根目录（`pwd` 能看到 `skill/`、`build/`、`src/`）」+ §3 第三条"不在仓库根执行时（两条脚本都用 `process.cwd()` 定位）…不要在那种状态下念结论"（`retire_flat.mjs` 同样按 `process.cwd()`，并在缺 `skill/README.md` 时直接 NOT_MEASURED）。② `node` 可用（§4，无 node 即"直接不适用"）。③ bash 与 python 的实际情况：`_meta/naming-and-format.md` 开头"Windows 11 + Git Bash（MSYS），`node` 可用、`python` = 3.12（**没有** `python3`）"；`evals/runbook.md` §0 那四条探测命令（`pwd` / `node --version` / `python --version` / `bash --version | head -1`）+"任何一条不满足就停在这里"。④ `skill/_meta/team-names.txt` 必须在（G10 用；`gates.mjs` 缺它报 `NOT_MEASURED`）——包内存在。⑤ `skill/README.md` 的 `<!-- BEGIN/END GENERATED INDEX -->` 锚点必须在（`gen_index.mjs` 缺锚点退 3）——包内存在。⑥ `_meta/sources.md` 必须在（G8 用它核外链台账）。⑦ 产物目录不许指进工程目录：`regmap_check`/`contract_gen`/`golden_compare`/`report_metrics`/`repro_check` 各有 `PROTECTED = ['src/','sim/','build/','board/','data/','report/','docs/']` 并拒绝。⑧ 别把 stdout 直接重定向成判据自己要读的那份文件（`evals/runbook.md` §2 ⚠）；取退出码别走管道（`templates/script-template/SKILL.md` §5.1 步骤 2 ⚠：先 `> file 2>&1; echo "rc=$?"`）。

**跑不成 / 文件里找不到的部分**，如实写：G11 要的是 `skill/scripts/selftest/run_all.sh`（`gates.mjs` 第 252 行），这个文件在包内**不存在**——`ls skill/scripts/selftest/` 只有 `fixtures/`，也没有 `scripts/selftest/SKILL.md`。所以 `skill/scripts/selftest/fixtures/` 下那些反例目录（`regmap_negative_bad_cite`、`regmap_negative_missing_field`、`contract_gen_negative_bad_widest`、`golden_compare_positive|negative`、`report_metrics_negative`、`repro_negative`、`static_violation`、`static_negative_write`、`static_negative_net`）没有 runner 去串它们；唯一被脚本自己读到的 fixture 是 `static_check.mjs` T4 用的 `skill/scripts/selftest/fixtures/static_violation`。按 `scripts/check/SKILL.md` §6 的口径，G11 只能落 `NOT_MEASURED`。同理 `report_metrics.mjs` 头部点的 `skill/scripts/report_metrics/SKILL.md 第 8 节"量出来的形状"` 在包内不存在 ⇒ 那套列位/节标题的原始出处我找不到。`README.md`「C 校验脚本」那十几行（`build/gates.sh`、`build/check_skill_cards.py`、`sim/run_one.sh`、`src/host/*.mjs`…）都不在 `skill/` 里，这次不许读，我只抄得到 README 那张表给的命令列，跑前真不真、参数对不对我判不了。另外 `evals/README.md` §6 那四条计数命令指向 `skill/evals/records/*.md`，而 `evals/records/` 与 `evals/migration/` 是空目录（`ls` 结果）。

### Q4

先说我的取法：我把"不适用于我们的场景"理解成**条目在 §3 里明写"我们（本工程/本仓）没有 X，所以这条（的某一段）在这儿不成立/只能当通用做法"**。按这个口径，命中这几条（引原句）：

1. `runtime/dma-cache-coherency/SKILL.md` §3 第 1 条：**「本工程 PL 侧没有例化任何 DMA IP：BD 里只有 `processing_system7_0` + `axi_gp0_ic` + `axi_gpio_0/1/2` + `axi_mem_intercon`，PL 侧经 `S_AXI_HP0` 直接读写 PS DDR（`build/tcl/build_system_axigpio.tcl:160-173`），没有 AXI DMA / CDMA / VDMA。⇒ 本条凡是"描述符链、硬件描述符引擎的传输长度寄存器、SG 通道切换"的断言都是通用做法，在本工程一律 `【未实测】`，不得当作本仓结论引用。」**；同节第 3 条：**「不适用 PL 完全不碰 PS 内存的设计（只走寄存器窗口的场合）：本工程的数据面就是共享 DDR，控制面才走 GPIO 窗口，两者判据不同。」**
2. `runtime/host-bindings-and-reports/SKILL.md` §3 第 1 条：**「不适用"从契约表自动产出主机侧绑定代码"的生成器路线：本工程没有生成器，位图是手抄进 `src/ps/main.c` 与 `src/host/health_read.mjs` 两处、再由检查器对账的 ⇒ 本条第 5.1 节写的是"没有生成器时怎么保证一致"，生成器写法本身一律 `【未实测】`。」**
3. `runtime/register-map/SKILL.md` §3 第 5 条：**「本条不含中断类寄存器三级结构的实测结论：本工程控制面是纯 AXI GPIO，没有中断参与（`report/ARCHITECTURE.md:110` 写明"没有中断参与"）。」**；§3 第 3 条把本仓口径当边界：**「不适用"一次改到位序里"的破坏性改表：本仓口径是位序一旦发布就不许重排…」**。（同文件 frontmatter `description` 末句也写了同一件事，但那一行不在 §3：**「本工程没有 AXI 地址重映射、没有自定义 AXI 从设备，控制面只有 AXI GPIO。」**）
4. `references/build-report-field-map/SKILL.md` §3：**「不适用：本包没有收录的报告类型（如 `report_io`、`report_cips`、综合 utilization 的 `hst/` 文件）。」**（该页第一条是**「本层不是判据：任何结论都不能靠本页自称成立，只能靠 `evals/` 的记录或实测输出；本页只回答"是什么、去哪确认"。」**，`checker-convention-shapes`、`tool-version-drift` 三页第一条同此句式。）
5. `references/tool-version-drift/SKILL.md` §3：**「不适用：厂商官方文档号（UG901 / UG904 / UG1399 / UG949）——本包本轮没有打开过这四份的正文，`docs.amd.com` 抓取只返回"需要启用 JavaScript"，所以相关格写 `未核实`。」**
6. `references/checker-convention-shapes/SKILL.md` §3（方向相反的"不适用"，即约定只属于我们）：**「不适用：外队工程——本表的 token 与文件名是本仓约定（示例取值，需按自身工程替换），迁移时要整列重写。」**
7. `pitfalls/who-else-writes-this-artifact/SKILL.md` §3：**「失效：本仓 md5 绑定这套做法依赖脚本自己在编译之前写 `prov.txt`（`sim/run_one.sh:73-95`）；换工程若无等价出处记录，"认 md5"救不了你，见第 5 节步骤 5 的替代动作。」**
8. `pitfalls/report-field-parse-breaks/SKILL.md` §3 第 4 条是"我们已经做了 ⇒ 这条不再适用"：**「失效：你已经把形状定义抽成一份单一来源并对真实工件跑过对照（本仓做法是 `build/rtl_fingerprint.sh` 那种"定义只有一处"），此时应改判为"报告变了"而不是"解析器坏了"。」**
9. `scripts/check/SKILL.md` §3 第 1 条：**「想验设计（时序/资源/板级）：那是 `build/gates.sh` 与台架的射程，本目录只管文档与形状。」**
10. `zynq-video-rtl-debug/SKILL.md` §2 末尾与 §8：**「不适用：画质类判定的收敛…；布局不是 `src/rtl + sim + build/tcl` 的工程（下面每条路径都是仓库根相对路径，换布局就要全部重指）。」**／**「不再适用：非 Zynq 裸机流程（带 FSBL/FreeRTOS/PYNQ 的工程），或板上没有可读回的计数寄存器时——L3 那一层直接失能，只能退到示波器/抓包。」**
11. `_meta/naming-and-format.md` §1 条文依据表第三行：**「`通用 PYNQ Skill 单独加分` —— 本作品不用 PYNQ（裸机 + Vivado/Vitis 原生流程）」**（不在条目 §3，但在包里唯一明写"我们的场景不算"的表行）。
12. 扁平卡（六节格式）里最接近的：`board_eth_uart.md`「不适用」第 1、2 条：**「本页只在"点对点直连 + 静态地址 + 数据面走 PL 侧网口"这一种拓扑上量过」**、**「PS 侧跑协议栈收流的工程：速率与自协商那一格要重新量，别把这里的清单当依据」**；「失效边界」第 3 条：**「本设计完全不配置 PHY（管理接口悬空，复位由上电计数驱动）⇒ 收包依赖芯片上电默认的自协商结果…换板或换通路则整段作废」**。`atomic_register_window_readback.md`「不适用」第 3 条：**「只有 1 个字可读，或你本来就有真正的原子广播口（一次读全组）。」**

如果你那句"不适用于我们的场景"其实指"这条技能整套在本仓库根本不该用"（不是某一段），我只能给上面第 1、2、3、9、10 条那种整句断言；余下的是"某段不成立"。`runtime/dma-cache-coherency/SKILL.md` §6 还有一句自陈边界：**「本仓没有 `skill/pitfalls/axi-dma-and-memory/` 目录（写作时 `ls skill/` 只有平铺 `.md` 与一个 `zynq-video-rtl-debug/`）⇒ 编号对齐列一律 `【待对齐】`」**——它指的目录布局是重构前的，与现在包内实际结构不一致，这条我判不了该按哪版执行。

### Q5

**它虚构的题目**：《四通道心电（ECG）采集与心率异常报警装置》，平台 Zynq-7010（`xc7z010clg400-1`）、Vivado/Vitis **2024.2**（不是本包的 2025.2.1）、裸机 + JTAG 加载。信号链：AD7606C 四路同步采样 10 kS/s/通道 → PL 内 FIR 带通 + R 峰检测 + 心率计算 → 控制/观测面 = 一路 AXI GPIO（阈值、通道使能、片源选择）+ 一个自定义 AXI-Lite 从设备（带 pending/enable/ack 三级中断）→ PS 侧驱动 OLED 显示并在越限时经 USB-UART 出一帧报警 → 上位机 Node 脚本读数并出 `metrics.csv`；判据 = xsim 单元台架 + 一支 bash 门禁 + 板级串口/调试器回读，没有 HDMI、没有 UDP 大数据面、PL **不**碰 PS DDR。

它列的"要改哪几处"（原文按包根 / `_meta/` / `scripts/` / `runtime/` / `templates/` / `prompts/` / `pitfalls/` 分组，逐条指到文件与节）：

1. `SKILL.md`「硬规则」第 4 条（512×300 源 / 1024×600 显示 / 1344×625 @50 MHz / 1392 B 分包 → 换成 4×10 kS/s、每帧样本数、UART 帧长）；「环境事实」整节（`2025.2.1`、`xc7z020clg484-2`、`IDDR/IDELAYE2/…` 那份 7 系列原语清单、"换版本 ⇒ `ps7_init`、BD 地址、实现策略与全部门禁数字作废"）；「禁止」第 5 条点名的 `report/BOARD_PINS.md`；「工作循环」框里的"生产几何"那一格。
2. `README.md`：①"目录里现在有 28 项编号条目（S1…S30，空号 S3、S6…）"那一段和它给的数法命令；②「我现在这个症状该看哪一条」整表（18 行的症状措辞全指本仓现象与文件名）；③「C 校验脚本」表逐行（`build/gates.sh` 的"它检查什么"列写了 `tb_v98`、边缘条带、PS 心跳这些本仓专属项）；④「D 踩坑清单」四组条目清单；⑤末尾「改这个目录的规矩」里"S1…S23 是对外接口、`src/` `sim/` `report/` 已按号引用"那段（我的仓库没有这些引用者）。
3. `_meta/naming-and-format.md`：§1 条文依据表四行（含 `report/log/CONTEST_CHECKLIST.md:21/120/124/82` 与"PYNQ 加分"那行）；§2 R1/R10 命令里指向 `skill/` 外的部分（R10 = `node src/host/doc_enc_check.mjs`）；§4 版本声明（`Vivado/Vitis 2025.2.1 (build 6403652)` 与真相源 `report/BUILD.md`、`data/metrics.csv`）。
4. `_meta/entry-template.md`：只有 §8 那节的示例路径（`report/log/ISSUES.md #327`）与「规则来源」段里的本地章程路径要换；八节外壳本身与「长度与分层」我不动。
5. `_meta/team-names.txt`：整份名单 + 头两行生成说明。
6. `_meta/sources.md`：目录三段的结构与"一、本会话"台账表的每一行来源（全是本仓件与行号）；G8/G9 依赖它。
7. `scripts/check/gates.mjs`：`CATEGORIES`、G4 的 `HEADINGS`、G8 反引号路径前缀白名单、G10 的名单路径与豁免词、G11 的 `skill/scripts/selftest/run_all.sh` 路径。同时 `scripts/check/SKILL.md` §8 已自己写明"迁移要改两处：`CATEGORIES` 列表、G10 的名单生成命令"，§3 第 2 条（目录结构不是"条目=目录+SKILL.md"时 G2/G4 大面积红）。
8. `scripts/check/static_check.mjs`：`PROTECTED` 前缀清单、`--root` 默认值、T4 默认样本目录。
9. `scripts/regmap_check/regmap_check.mjs`：`COLS` 那 22 列（我的自定义从设备要加中断列并让它进判据）、K5 里两条硬编码地址正则、K6 的 BD 钉址行正则与 `--bd` 输入形状、头部"复跑"示例行。
10. `scripts/regmap_check/contract.tsv` 与 `axi_gpio_contract.tsv`：行内容整表重写；tsv 头注释指向的 `skill/scripts/regmap_check/SKILL.md` 我要新建或改写那行指路（包内现在没有）。
11. `scripts/contract_gen/contract_gen.mjs`：`REQUIRED` 十列名、`PROTECTED`。
12. `scripts/golden_compare/golden_compare.mjs`：头部复跑行点名的 `build/CDC_BASELINE.txt`、`build/frozen_r23_srcseen/cdc.rpt` 及列位、`--golden-where '$1=Critical'` 这类本仓 CDC 词、`PROTECTED`。
13. `scripts/report_metrics/report_metrics.mjs`：`HELP` 里的字段集与定位用的节标题字串、头部第 6 行指向的自身 `SKILL.md` 第 8 节。
14. `scripts/repro_check/repro_check.mjs`：`FPVER='norm2'` / `FPVER_COMPAT='norm1'` 两行（注释点名"仓库既有口径 `build/rtl_fingerprint.sh`"）与 `HELP` 里的 `--root src/rtl` 示例。
15. `scripts/_out/**`：上一题跑出来的产物，整目录重跑覆盖，不能当模板抄。
16. `runtime/register-map/SKILL.md`：§3 第 3、5 条（位序是否保留；"没有中断参与"整条作废——我有中断，§5.4 三级结构表要从 `【未核实】` 换成实测出处，§7 末条也写着要跑什么）；§4 前置（版本行 + 四个输入文件路径与行号）；§5.1 表格右列每一件本仓件名；§5.2 派生四处与改表三步命令；§5.3 的 `[CFG] axi_gpio_2 @… ok` 判据文字；§5.5 的 `64K` 段与 `0xDEAD_BEEF`；§5.6 PYNQ 对位表；§7 全部件路径；§8 自列的①–⑤。
17. `runtime/pl-load-verify/SKILL.md`：§3 第 4 条（`DONE` 文字、器件串）；§4 位流/`ps7_init`/elf 路径与 `VP_XSDB`/`VP_VIVADO_BIN`/`VP_BIT`/`PS7_INIT` 变量名；表 5-A 的 L3（"翻转一次发布位，屏上重画一帧"→"越限一次，串口出一帧报警"）、L4 档位 `15 → 30 → 60 fps`→`1/2/5/10 kS/s`、L5 的 `--pace-mbps 0 / 约 147 Mbps`；表 5-B 四条命令与期望 token；表 5-C 的 `[CFG] … ok`；表 5-E PYNQ 列；§7 件路径；§8 ①–⑤。
18. `runtime/host-bindings-and-reports/SKILL.md`：§3 第 1 条（我打算用 `contract_gen` 生成绑定 ⇒ 按 §8 第⑤处"若要引入生成器，先补'生成物 vs 原件'的判据行再删本节 §3 第一条"的顺序办）；§4 五组输入路径；§5.1 三处读者与三条命令；§5.2 的 `MONO`/`LIVE` lane 集合；§5.3/§5.5 命令与 `build/pre_readings.sh`；§8 ①–⑤。
19. `runtime/dma-cache-coherency/SKILL.md`：先按它 §3 第 3 条判定——我的 PL 完全不碰 PS 内存 ⇒ 整条对本题不适用，只在 §8 留一行"未采用，依据 §3 第 3 条"；若仍要用其缓存纪律，则 §5.1 表 5-A 两行、§5.2 的 `cacheline = 32U`、§5.4 示例宏、§6 表格九行、§8 ①–⑤ 都要重取。
20. `templates/interface-contract/contract-table.md`：§1 主表列不变、"读写属性"口径行要允许 `W1C/RC` 真用起来（本仓那版是轮询）、§2 第 1 类窗口读回那一族我可能不存在、§5「示例取值」那五条全是本仓件、§6 C1–C4。配套 `SKILL.md`：§5 槽位计数、§7 四条"本次实读"的本仓件与 mtime、§8「迁移要改的」——其中「"中断号"列在纯轮询系统里写"无（轮询）"并给依据」这句在我的题里要反过来（真中断号 + 谁清它）。
21. `templates/script-template/script-template.sh` 的 `SLOTS` 段 15 个槽位 + `STAGE` 旋钮；`SKILL.md` §5 槽位计数行、§5.1 三步、§8「迁移要改的四处」。
22. `templates/report-forms/SKILL.md` §8「迁移要改的」（测量条件六件、逐域列名里的时钟对象名、阈值与噪声底、验收表"由谁看"换成我队真实的人）与 §3 第 5 条；同目录四张表的表头本身——这四张正文我这次没打开，只从 `ls` 与上面 §8 得知其用途。
23. `templates/project-skeleton/SKILL.md` §8（第 3 节归档内容清单、`MANIFEST.md5` 的"三件套"具体件、第 6 节 A2 盘符写法）与 §3 第 3 条；同目录 `project-skeleton.md` 的目录树（我没打开正文，只有文件名）。
24. `prompts/hw-sw-partition/SKILL.md` §8 那三条平台相关句 + §5 的"器件与平台"槽；注意我这块有硬核 A9，所以 §3 第 4 条（"目标平台没有处理器硬核"）不适用但不必改。
25. `prompts/report-to-bottleneck/SKILL.md` §8 三条（家族相关读数、"阈值 80 % route 占比来自本仓库实测记录，换器件/换工具版本要重新取一条同类读数，不许照抄"、报告文件名）与 §3 第 4 条（单时钟时花名册那两步不产出信息）。
26. `prompts/criterion-before-code/SKILL.md` §8「迁移到新题目要改：机会计数的维度…下限数值、ASCII 标签长度限制、"门有几道"的冗余判定」。
27. `prompts/single-variable-ab/SKILL.md` §8「V3/V4/V5 的三个阈值都要由你自己的噪声底推出来；把"复制单元数"这一类机制计数换成你手段的对应可数读数」。
28. `pitfalls/console-codepage-verdict-shift/SKILL.md` §3 第 2 条（换 Linux + 码页 65001 ⇒ GBK/CP936 那半不适用）。
29. `pitfalls/win-bash-path-split/SKILL.md` §3 第 1、5 条（MSYS 三视图那半不适用；`tasklist` → `pgrep`）。
30. `pitfalls/who-else-writes-this-artifact/SKILL.md` §3 第 3、4 条（`tasklist`、`sim/run_one.sh:73-95` 的 `prov.txt` 依赖）。
31. `pitfalls/tcl-query-empty-means-broken-ruler/SKILL.md` §3 第 3、4 条（"本文只写本仓在 2025.2.1 上量到的那一条（`eq` 报语法错），别版本未测"——我是 2024.2，整条要重量）。
32. `pitfalls/report-field-parse-breaks/SKILL.md` §3 第 4 条（`build/rtl_fingerprint.sh`）。
33. `pitfalls/checker-ran-on-nothing/SKILL.md` §3 第 3 条（grep 词表要换成我这三态 token，指向 `references/checker-convention-shapes` 那张表）；`pitfalls/assertion-not-in-any-file/SKILL.md` §3 第 3 条（凭据若是截图/视频 ⇒ 判据换成哈希/时间戳——我的验收很多是 OLED 照片）；`pitfalls/exit-zero-nothing-written/SKILL.md` §3 第 4 条（改退出码语义不许）。

**三处它搬不动、必须回来问的**：
① 28 张扁平卡是六节（触发/不适用/动作/完成判据/失效边界/出处，`README.md` 第 16 行），而 `_meta/entry-template.md` 与 `gates.mjs` 的 G4 要求八节，两套并存，它不知道最终该按哪套重写这些卡。
② `runtime/register-map` 与本包 `skill/scripts/regmap_check/` 谁为真相源（见 Q1 末）。
③ `README.md`「C 校验脚本」整表与 `evals/runbook.md` §1–§5 的每一条命令都指 `skill/` 外（`build/`、`sim/`、`src/host/`、COM6、`/tmp`），这次不许读也不许跑 ⇒ 那些命令在新题里对应什么、包不包得住，它给不出来。

---

## 演练结论（红项清单与据此回改的位置）

三态统计：**能答 5 / 5 题，但 5 题里有 5 处暴露包内矛盾或缺件 ⇒ 记 5 条红项**。本轮不宣称"陌生人可独立使用"。

| 红项 | 它指出的原文位置 | 判定 | 已回改 / 待回改 |
| --- | --- | --- | --- |
| R1 `register-map` 说 `scripts/regmap_check/` "在本仓不存在"，而包里它已存在（两处自相矛盾） | `runtime/register-map/SKILL.md` §5.2 第 3 步、§8 第④处；`scripts/regmap_check/axi_gpio_contract.tsv` 头注释 | 成立（是重构后的**过期口径**） | 待改：该两处改为指 `skill/scripts/regmap_check/`，tsv 的列口径指到 `regmap_check/SKILL.md`（该文件由 P04 agent 正在写，见 G2） |
| R2 `dma-cache-coherency` 说本仓没有 `skill/pitfalls/axi-dma-and-memory/`，"编号对齐列一律【待对齐】" | 同文件 §6；G8 实测该路径是**死链**（死链=4 里的一条） | 成立 | 待改：把死链改成"本包未采用 P05 的类别目录布局"这一事实句，并进 `docs/run-queue.md` 的偏离登记 |
| R3 六节扁平卡与八节条目两套并存，读者不知道按哪套 | `README.md:16` 的"每条都是同六节" vs `_meta/entry-template.md` 八节 + G4 | 成立（迁移未完成所致） | 迁移中的 28 张卡完成后由 `retire_flat.mjs` 全绿才允许并存状态消失；本轮先修 README 措辞 |
| R4 `scripts/report_metrics/report_metrics.mjs:6` 指向自身尚不存在的 `SKILL.md` 第 8 节 | 它的 Q3 末段；G8 死链 | 成立 | 待 P04 agent 补该 `SKILL.md`（G2 红项里已含） |
| R5 `evals/records/` 与 `evals/migration/` 是空目录 ⇒ 全包没有任何条目级验证记录 | 它的 Q3 末段与 Q1 第 8 条 | 成立 | 本文件即为第一份 record；`migration/` 由 P08 后续补，`submit/07` 里"migration 里写的是…"那句属**过度声称**，本轮已改 |
