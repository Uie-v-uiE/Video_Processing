---
name: register-map
description: 给"在已有 AXI 从设备上开一个索引+数据窗口"这类 PS↔PL 寄存器契约立一张表。当出现"设了没反应"、回读值与写入不符、多段读数互相矛盾（恒等式不成立）、改一个位踩到相邻位、采样脚本读到别的通道、或需要判定读写属性/复位值/写副作用/时钟域该写在哪里时才用它；也用于改表之后要跑哪几层一致性校验。本工程没有 AXI 地址重映射、没有自定义 AXI 从设备，控制面只有 AXI GPIO。
---

## 1. 一句话用途

把 PS↔PL 控制面的位序、偏移、副作用立成一张可对账的表。

## 2. 适用场景

- 当"往某个地址写了值，硬件毫无反应"，而编译与工具链都没有报错时。
- 当同一次采样里两个读回的数违背一条恒等式（例如"分段之和 > 总时长"这类物理上不可能的形状）时。
- 当改一个控制位会踩到同一字里其它位，或工具"只改一位"的写法在下一帧被整字覆盖时。
- 当调试脚本读到的是错通道的数据（读到 0 被当成"该计数为零"）时。
- 当同一张位图需要被多处读者使用（固件、调试脚本、交付文档、生成器），要判断"改表要跑哪几层"时。
- 当观测口某一位恒为 0 或恒为 1，需要区分"硬件真是这样"与"读法错了"时。
- 当读回的值恰好等于复位默认值或全 0（一个不存在的从设备也常常返回 0）时。

## 3. 不适用 / 失效条件

- 不适用 Linux 用户态 `mmap`/`/dev/mem`/`uio` 与 UIO 中断那套读写语义：本条写的是裸机 `Xil_In32/Xil_Out32` 与调试器 `mrd/mwr` 两层。
- 不适用 AXI Stream-only 或 DDR-only 交换的数据面 —— 那张契约的字段是描述符与地址范围，不是位域。
- 不适用"一次改到位序里"的破坏性改表：本仓口径是位序一旦发布就不许重排（`src/ps/main.c:211-213` 明写"位序一改，`set_src.tcl`/`health_read.mjs` 这些按位写的工具就全错位；空位比'重排一遍再逐个改工具'诚实"）。
- 若工程里根本没有真相源（位序散落在 RTL、固件、文档三处各自表述），本条第 5 节的"改表三步"无法起步，要先做归并 —— 那种状态属于缺陷，不属于本条适用范围。
- 本条不含中断类寄存器三级结构的实测结论：本工程控制面是纯 AXI GPIO，没有中断参与（`report/ARCHITECTURE.md:110` 写明"没有中断参与"）。

## 4. 前置条件

- 工具与版本：Vivado / Vitis 2025.2.1，器件 `xc7z020clg484-2`（`report/BUILD.md:11`、`data/metrics.csv` 第 2 行）；本条的生成与校验层用 Node（`src/host/*.mjs`）与 Python 3（`build/check_ports.py`）。
- 需要的输入文件：
  - 真相源表本体：`report/ARCHITECTURE.md` 第 4 节"PS↔PL 控制面：寄存器映射"那一张表（偏移 + 位域 + 方向）。
  - 地址钉死与回读校验：`build/tcl/build_system_axigpio.tcl:210-244`。
  - 固件侧位序：`src/ps/main.c:48-160`（宏与 `ctrl_write()`）。
  - RTL 侧译码：`src/rtl/top/system_top.v:220-247`（lane mux）。 （本仓示例取值，迁移时按自身工程替换）
- 需要的权限或硬件连接状态：JTAG 可达（`hw_server` 3121）；核可 `stop`（lane 窗口必须在 halt 态读，见 §5 第 3 步）；`VP_XSDB` 指向 `xsdb.bat`（不设时 `build/board_verify.sh:113-114` 直接 `REFUSE` 退出码 2）。

## 5. 使用方法

### 5.1 真相源表：十个字段，缺一个就对应一类具体事故

| 字段 | 为什么必须显式 | 缺了会出哪类事故（本仓有件的） |
| --- | --- | --- |
| 偏移（含通道偏移） | 写错口的症状不是报错，是"设了没反应" | `CFG_DATA0`/`CFG_DATA1` 只差 `+0x08`，`src/ps/main.c:220-222` 注明"写错字的症状恰恰是'设了没反应'，最容易误判成 PL 坏了" |
| 位域（区间端点） | 区间端点错一位 = 读写到邻居 | `SPLIT_POS` 取 `[22:13]`；写 1024 时 `1024<<13 = bit23` 正是 `SPLIT_AUTO` ⇒ 缝跳到第 0 列且自动扫描**悄悄开起来**，回显还说"auto 仍开着"（`src/ps/main.c:125-136`，凭据 `build/probe_split100_old.txt` / `build/probe_split100b_old.txt`） |
| 读写属性（含只读/反相） | 反相位漏写"反相"就会被当成正相实现 | `OSD_OFF_BIT 20` 是**反相**（1 = 关叠层，复位 = 有 OSD，`src/ps/main.c:53-57`）；漏标一次就"默认观感随一次重构丢掉" |
| 复位值 | 复位值决定"app 还没起来时屏上是什么" | `temp_disp` 的同步链复位值是 `0xFF` ⇒ 屏上画 `--` 而不是 `00C`（`src/ps/main.c:90-93`）；不写复位值就无法判定"上电读 0"这一类判据的期望 |
| 写副作用 | 有些位是边沿不是电平，整字重写会重复发火 | `[18]` 发布位、`[22]` 模式翻转、gamma `wr` 都是**翻转位**；`build/tcl/set_src.tcl` 是整字覆盖，注释自己写明"bit18（发布脉冲）会被写成 0" |
| 读副作用 | 观测口的"读"本身能改状态 | `system_top.v:232-236`：指到 lane25 那一拍就把五个时延字**同时**抄进快照 ⇒ 读顺序必须是 25→26→27→28→29，写进注释里当契约 | （本仓示例取值，迁移时按自身工程替换）
| 中断号 | 本仓无中断，字段留空并注明 | `report/ARCHITECTURE.md:110`（"没有中断参与"）⇒ 本行不许被读者当成"有中断" |
| 单位与量程 | 单位换算的位置本身改变时序结论 | γ×10 与温度的十进制换算**在 PS 侧做**，因为 OSD 那五行字符是一整块组合逻辑、而 `u_pipe/xd_reg → u_osd/g_reg`（27 级）是全设计最差的那条链（`src/ps/main.c:83-93`） |
| 最宽输入 | 字段位宽的上限与业务上限往往不等 | 缝位字段 10 位 ⇒ `SPLIT_POS_MAX = 1023`，而屏宽是 1024；差的那 1/1024 被夹住并**在回显里明说夹了**（`src/ps/main.c:125-136,162-169`） |
| 时钟域 | 决定这个位要不要跨域、走哪条同步链 | V9 新加的 5 位挤进同一个字而不新开 GPIO，是因为"新开一条跨域路就要多一对 bus/toggle 同步器"，而"一个发射触发器扇出到两组目的域"正是 CDC-11 Critical 的签名（`src/ps/main.c:147-154`） |

### 5.2 从真相源派生的四处，与"改表之后必须跑什么"

派生四处（都必须由同一张表解释，不许各有第二套真相）：

1. RTL 地址/索引译码 —— `src/rtl/top/system_top.v:237-246` 的 lane mux。 （本仓示例取值，迁移时按自身工程替换）
2. 主机侧头文件 —— `src/ps/main.c:48-160` 的宏组（`GPIO_DATA`、`GM_*`、`SPLIT_*`、`ROT_*`）。
3. 调试脚本 —— `build/tcl/set_src.tcl`（整字写）、`build/tcl/r116_lane_read.tcl` / `r116_lane_read2.tcl`（只改 5 位并还原）。
4. 报告里的接口表 —— `report/ARCHITECTURE.md:100-108` 与 `report/COMMANDS.md:241-244`。

改表三步与对应校验（顺序不可交换）：

```bash
# 第 1 步：只改表（report/ARCHITECTURE.md 那一节 + 固件宏 + RTL 译码，同一次改动）
# 第 2 步：跑构建期的地址钉死回读（ADDR_LOG 三行 want/got 数值相等才让构建继续）
"$VP_VIVADO_BIN/vivado.bat" -mode batch -nojournal -source build/tcl/build_system_axigpio.tcl
# 完成后应看到：三行 ADDR_LOG，每行 num_ok=1；任何一行不等于 1 就 ADDRESS PINNING FAILED 并 exit 1
# 第 3 步：跑一致性判定（本仓的对应物，不是 scripts/regmap_check/ —— 那个目录在本仓不存在）
python3 build/check_ports.py            # 端口名/输入悬空/位宽三类，门禁第 14 项
node src/host/metric_recheck.mjs        # 把文档里的数字对回它自己点名的报告
node src/host/ps_hb_check.mjs --self    # 源码原文级约定（节拍/超时/调用点）+ 变异对照
bash build/gates.sh                     # 整套门禁，全绿才谈采纳
```

"怎么改表"的硬规矩（本仓口径）：位序**只增不改**；退役的位保留位置恒写 0（`[4:0]` 就是这么处理的）；一张位图的所有读者必须在同一次改动里全部改完 —— `src/ps/main.c:153-154` 明写"位图现在有三处读者，改任何一处必须同一次把三处改完"。

### 5.3 复位值与"配套性"的开机验法（只写一个非零图案，不许命令硬件）

本仓把它做进了固件 `main()`：写图案 → 读回 → 比对 → 打一行；图案故意放在**保留段**，因为"探针不许命令硬件"。

```bash
"$VP_XSDB" build/tcl/ps_app_reload.tcl          # 只复位核，不动位流
powershell -File board/uart_cap_once.ps1 -Seconds 20
# 完成后应看到：[CFG] axi_gpio_2 @<基址> ok  与  [CFG] gamma window @<基址+0x08> ok
```

判读口径（为什么不能"读回 0 就算对"）：`src/ps/main.c:1554-1557` 的注释写的是"**不存在的从设备常常也返回 0，那种判据不会红**"，所以必须写一个非零图案再读回来比对。

### 5.4 中断类寄存器的三级结构与读写语义陷阱

本工程没有中断参与（§3 第 5 条），本节全部为流程与只读验法，**没有任何一条是本工程实测结论**；`AMD 裸机驱动库` 与 `AMBA AXI` 协议细节本次未能打开官方页面（docs.amd.com 需 JS，WebFetch 只拿到 "Loading application..." 占位页）⇒ 标 `【未核实】`，不要当事实引用。

| 结构层 | 该显式写什么 | 陷阱 | 如何只读验证这个语义 |
| --- | --- | --- | --- |
| 状态（pending/ISR） | 是否读即清、是否写 1 清 | 调试器并发读取会吞掉事件：一次 `mrd` 就可能把 pending 清成 0 | 只读法：不改变使能位，先 `mrd` 一次记下值，再 `mrd` 第二次。若两次都非零 ⇒ 读不清；若第二次恒 0 而事件仍在发生（有可数的流量作旁证）⇒ 读即清。本仓无中断，此法 `【待验证】` |
| 使能（enable/IER） | 位与中断号一一对应、复位值 | 使能复位值为 0 时"事件发生了但没人知道" | 只读法：读使能寄存器回来自证它是 0/1，再对照状态寄存器；两者独立可读才谈得上判据 |
| 丢弃/屏蔽（acknowledge / disable） | 是"确认清零"还是"屏蔽后不再置位" | 把屏蔽当确认用，事件会永久消失而不是被消费 | 只读法：只读不写，观察被"屏蔽"的那一路是否仍能在状态寄存器里看到置位；看得到 = 屏蔽只挡发送，看不到 = 需要硬件确认 |

本仓可复用的**同类**判据是"读副作用"而不是中断：lane 窗口读一次会改变硬件快照内容（§5.1 读副作用行），所以 `build/tcl/r116_lane_read.tcl` 结尾必须把原值写回，`r116_lane_read2.tcl` 更保守 —— 不设 `VP_LOW25` 时只打印、一个字都不写（`LANEREAD_DONE_NO_WRITE`）。

### 5.5 地址解码粒度、别名与越界访问的期望行为

| 现象 | 期望被观察到什么 | 本仓的件 |
| --- | --- | --- |
| 段范围（解码粒度） | BD 里每路 GPIO 分 `64K`（`assign_bd_address -range 64K`），三路基址相隔 `0x10000` ⇒ 段内偏移 `[0x00,0x10000)` 之外的地址不应被别到段首 | `build/tcl/build_system_axigpio.tcl:213-221` |
| 别名（同段内不同偏移映射到同一物理寄存器） | 未定义的通道偏移（例如 GPIO 只有一路时读 `+0x08`）必须报出来而不是静静回 0 | 固件开机自检逐通道验：`src/ps/main.c:1574-1587`（"ch1 活着不代表 ch2 在"） |
| 越界（写了不存在的地址） | 期望调试器报总线错误；**静默返回 0 是最坏的一种**，因为它把"没有从设备"伪装成"值为 0" | `src/ps/main.c:1554-1557` 的判据就是为这一条写的 |
| 越界（字段值超出位宽） | 期望：被夹住 + 回显明说夹了 + 不许顺带改到邻居位 | `src/ps/main.c:125-136,162-169`，反例凭据 `build/probe_split100_old.txt`、`build/probe_split100b_old.txt` |
<!-- 本仓示例取值 --> | 越界（索引超出 lane 定义） | 期望返回一个"一眼看得出号写错了"的图案而不是 0 | `src/rtl/top/system_top.v:244` 给未定义 lane 返回 `32'hDEAD_BEEF`；`src/host/health_read.mjs` 文件头同样写明"其它 lane 号硬件返回 0xDEADBEEF" |
| 最宽输入随字段变化 | 字段位宽变化时必须重新推导"最大合法输入"，并把夹取位置与回显同源 | `SPLIT_POS_MAX` 由 10 位字段推得；`ZOOM_X100` 的 `inv_scale` 期望值由 `25600/倍率` 再夹到 10 位天花板 `1023`（`src/host/health_read.mjs:99-106`） |

### 5.6 PYNQ 对位写法

| 本条机制 | PYNQ 对位写法（API 名本次查到才写） | 本工程形态 | 版本相关列 |
| --- | --- | --- | --- |
| 真相源表 → 运行时按名取块 | `Overlay` 实例化后用 `add_ip.register_map.a = 3` 按**字段名**读写（名字来自硬件描述里的 C 参数） | 表是 `report/ARCHITECTURE.md` 那一张 + 固件宏；没有按名访问层 | `register_map` 字段名访问：PYNQ v2.5.1 Overlay Tutorial 页面本次打开；新版本是否同名 `【核对】` |
| 偏移读写 | `add_ip.write(0x10, 4)` / `add_ip.read(0x20)`；更底层用 `MMIO(baseaddr, highaddr)` 配 `write(offset, value)`/`read(offset)` | `Xil_Out32`/`Xil_In32`（固件）与 `mwr -force`/`mrd -force`（调试器） | `MMIO` 类：PYNQ v3.1 API 页面本次打开；v2.5.1 是否同名 `【核对】` |
| 按名找块（地址从设备树来） | `Overlay` 的 `ip_dict`（实例名 → 地址/参数），文档写"to use the overlay class, a `.bit` and `.tcl` must be provided" | 地址在 BD 里钉死后由构建脚本 `ADDR_LOG` 回读校验；固件侧硬编码并注明为什么不靠 `xparameters.h` | `ip_dict`：PYNQ v2.5.1 `pynq_libraries/overlay.html`（本次打开，取回内容含 `base.ip_dict`） |
| "写图案读回"配套自检 | PYNQ 没有对位物：它靠设备树里存在这个 IP 名来判"在不在位流上" | `main()` 开头的 `0x1FF` / `0x00780000` 双图案自检（§5.3） | 与版本无关（属工程自建） |
| 索引+数据窗口（本条 lane 机制） | 对位写法 = 一个带地址的 `IP_Intc`/`MMIO` 区：PYNQ 侧按偏移读，**没有"读一次会推进硬件快照"这种语义**；用它时必须自己保证读顺序，PYNQ 不提供 | `gpio_o[31:27]` 选 lane、`gpio1_i` 读数据，lane25 那一拍武装五字快照 | 与版本无关（本条机制是本工程自造的） |
| 中断三级结构 | 对位物是 `Interrupt` 类（`connect`/`disable`/`clear`）——**本次未能打开该页面**，故不写方法名 | 无中断参与 | `【未核实】` |

## 6. 判读与失败分叉

| 命令 / 观察 | 通过 | 失败 | 读不到输入 |
| --- | --- | --- | --- |
| `"$VP_VIVADO_BIN/vivado.bat" ... build_system_axigpio.tcl` 后的 `ADDR_LOG` | 三行 `num_ok=1` ⇒ 进固件自检 | `got=NOT_FOUND` ⇒ 段查询写错了（本仓注释指出要从地址空间取段，取接口定义会得到空 OFFSET）；`num_ok=0` ⇒ 地址没钉上，`ADDRESS PINNING FAILED` 退出 | 没有任何 `ADDR_LOG` 行 ⇒ `NOT_MEASURED`：脚本没跑到那一段，回日志开头看第一条 exit 原因 |
| 串口 `[CFG] ... ok` | 位流/elf 配套 ⇒ 可信后续读写 | `[CFG!] ...` ⇒ 位流里没有这个从设备或它不是 32 位；处理顺序见 `pl-load-verify` 的 L2 | 无 `[CFG]` 行 ⇒ `NOT_MEASURED`：核可能停在 halt 上（`ps_app_reload.tcl` 文件头记录的坑），先 `con` 再判 |
| `node src/host/health_read.mjs --json` | 单调 lane 第二遍 ≥ 第一遍 ⇒ 采到的是同一份快照 | 变小 ⇒ 采到了快照刷新那一拍；恒 0 且 lane 号未回读确认 ⇒ 很可能读到的是 lane0（`ISSUES #55`：PS 每帧整字重写会抹掉 lane 号） | `[HEALTH] 读不到 GPIO_0 的当前值，拒绝继续` ⇒ `NOT_MEASURED`，本仓实测件 `build/evidence/r116_board/health_live1.json` |
| `python3 build/check_ports.py` | violations=0 ⇒ 表与顶层接线一致 | 报"连了目标模块没有的端口名"/输入悬空/位宽不符 ⇒ 按报的 `file:line` 修接线 | 脚本读不到顶层文件 ⇒ `NOT_MEASURED`（它的设计口径就是"看不懂就整个跳过，不猜"） |
| `bash build/gates.sh` | 全绿才谈采纳 | 任一项红 ⇒ 不采纳，保留上一版（`report/BUILD.md` §7 规矩 3） | 报告文件缺 ⇒ `NOT_MEASURED`，不是绿 |

## 7. 已验证的效果

- 地址钉死与回读（§5.2 第 2 步）：`build/tcl/build_system_axigpio.tcl:210-244` 里"三行 want/got 数值相等才让构建继续"是**本仓现役构建脚本**，`report/ARCHITECTURE.md:102` 记载 `0x41220000` "是 `build/tcl/build_system_axigpio.tcl` 里钉死并回读校验过的"；`src/ps/main.c:71-72` 同样指认。但本仓未在 `build/evidence/` 留一份专门的 `ADDR_LOG` 快照件 ⇒ 单次运行的实际输出摘要 `【待验证】`（要跑的是 §5.2 第 2 步那条命令并把三行 `ADDR_LOG` 存档）。
- 开机配套自检：`build/frozen_r48_osdsrc/uart_r48_boot.txt:4` 起有 `[CFG] axi_gpio_2 @41220000 ok`，`build/frozen_r45_v8morph/uart_r45_banner.txt:5` 同一行（该冻结集日期 2026-09-24），`build/frozen_r50_lat/MANIFEST.txt:40` 与 `build/frozen_r51_align/MANIFEST.txt:48` 各自登记两份自检件 ⇒ 判定 PASS（复跑命令 = §5.3；输入 = 当轮 `build/ps_app.elf` + `build/system.bit`；期望 = 两行 `[CFG] ... ok`；实际 = 上述文件里的原文行）。
- 读法造成的假账（§5.1 读副作用、§5.5 lane0 那类）：`report/log/ISSUES.md` `#59` 登记 `build/lat_tearing_r50.txt` 实测"连续 8 组读数里 3 组 `tot < c1`、1 组 `tot < c1+c2`"，并在未换位流的板子上用新判据复现 `build/torn_criterion_on_r50.txt`（"5 组里 3 组 `torn=true`、2 组自洽"）⇒ 判定 PASS。`ISSUES #55` 登记同一族的另一面：第一版 `lane30_watch` 把"lane 号被整字重写抹掉"的样本当真实读数，凭据 `build/frozen_r46_keys/lane30_r46_concurrent.txt`（r46，2026-09-24）与 `build/frozen_r50_lat/lane30_r50.txt`（r50 重采，291 条被丢弃并计数）。
- 采样必须 halt：`report/log/ISSUES.md` `#55` 明写"采 lane 之前必须先 `STOP`"，并给出误判样本（第一次 300 次里"mode 变了 128 次"是假信号）。手工采样的原始件在 `data/measured/lane30_watch.out`（文件时间 2026-09-25 16:00，逐行 `S <序号> <lane读数> <GPIO_0 原值> <写入值>`）。⇒ 判定 PASS。
- 越界字段的两种症状分叉（§5.5 第 4 行）：凭据 `build/probe_split100_old.txt`、`build/probe_split100b_old.txt` 两份都在 ⇒ 判定 PASS。
- 中断三级结构（§5.4 全表）：`【待验证】` —— 本工程无中断，一次也没跑过；要跑的是"在带中断的从设备上按 §5.4 那三只读验法各采一次并存档"。
- 位宽静默吃掉高位（`#57`）：本仓把它变成了门禁第 14 项的位宽判据，反例件 `build/ports_check_width_ce.txt`；`【未在本队取证】` 的是"其他工具版本会不会同样只给一条警告"。

## 8. 提炼来源与边界

- 来源证据（点名文件与日志条目，不讲故事过程）：
  - `src/ps/main.c`（文件头位序注释 48-160；`ctrl_write()` 208-227；`main()` 开机自检 1550-1587；字段夹取 162-169）
  - `src/rtl/top/system_top.v:220-247`（lane mux、`lat_arm`、`0xDEAD_BEEF` 默认、线宽吞高位的注释） （本仓示例取值，迁移时按自身工程替换）
  - `src/rtl/axi/axi_frame_writer64.v` 头部（`localparam BEATS = 16`、`arsize = 3'b011`、`arburst = 2'b01`） （本仓示例取值，迁移时按自身工程替换）
  - `build/tcl/build_system_axigpio.tcl:210-244`（64K 段、三路基址钉死、`ADDR_LOG` 数值比较与为什么不能字符串比）
  - `build/tcl/set_src.tcl`（整字覆盖及其自述副作用）、`build/tcl/r116_lane_read.tcl` / `r116_lane_read2.tcl`（只改 5 位、读回原值、以及 `mrd` 不返回字符串的坑）
  - `src/host/health_read.mjs`（lane 表、两遍判据按单调/非单调分列、`0xDEADBEEF`、lane30/lane23 两份独立译码 + `--selfcheck`）
  - `report/log/ISSUES.md` `#55`、`#57`、`#59`、`#70 追加`；`report/ARCHITECTURE.md:100-110`；`report/COMMANDS.md:241-244`
- 恒成立 / 平台相关 / 版本相关：字段清单、"写非零图案才算验到地址"、"读顺序写进契约"、"位序只增不改"这三条恒成立；`64K` 段大小与 GPIO 通道偏移布局是平台相关（换 AXI 从设备种类要重推）；`ADDR_LOG`、`check_ports.py` 的判据形状是版本相关（随 Vivado 与本仓工具版本变）。
- 不再适用的条件：改用 AXI 地址重映射/自定义 AXI 从设备（那时"索引+数据窗口"应由从设备寄存器阵代替，本条的 lane mux 那套读副作用不再成立）；改用 Linux UIO + mmap（读写属性由驱动声明，位序不再出现在固件里）；改用 PYNQ（按名访问接管，见 §5.6）。
- 迁移到新题目/新板卡要改的几处：① 基址与段范围（本条 `0x412*` 三行全是示例取值）；② lane/索引窗口的位段与哨兵值（本条把 `0x41200000`/`[31:27]`/`0xDEADBEEF` 都标成示例取值，需按自身工程替换）；③ "保留段在哪几位"（探针图案必须落在保留段，这条约束本身不变）；④ 一致性校验层换成目标工程实际有的检查器（本仓没有 `scripts/regmap_check/`，别照抄成路径）；⑤ 中断三级结构那表若要启用，先补官方文档行号再删 `【未核实】`。
