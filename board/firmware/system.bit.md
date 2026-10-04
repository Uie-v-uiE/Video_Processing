# 来源卡 · `build/system.bit`（PL 位流）

| 字段 | 值 | 怎么当场回读 |
|---|---|---|
| 权威路径 | `build/system.bit`（仓库内唯一实体；本目录**不放第二份拷贝**，理由见文末） | `ls -la build/system.bit` |
| 大小 | **2202122 B** | `stat -c %s build/system.bit` |
| MD5 | **`cd04907e1369da35d21c4090d552f5ee`** | `md5sum build/system.bit` |
| SHA-256 | `204f5498e091c98c58009fd299905657c1e63f89d172d6979e36f93f8f27303d` | `sha256sum build/system.bit` |
| 文件时间 | 2026-10-04 04:36:56 | `stat -c %y build/system.bit` |
| git 身份 | 已入库（`git ls-files build/system.bit` 命中）；最后一次把它写进 git 的提交 = `d420db6`（2026-10-04 08:05） | `git log -1 --format=%h_%ad -- build/system.bit` |
| 是否入库 | **是** | 口径：`report/build.md:194` 的规矩 1「冻结 = 拷贝工件」，而本仓库恰好把 `build/system.bit` 入库 |

## 1. 由哪一轮构建产生

**r118**（2026-10-04 那一轮，`build/r118_chain.sh`）。

| 项 | 值 / 件 |
|---|---|
| 源码指纹（起飞前打的） | `build/evidence/r118_tree_fp.txt`：`fpver=norm1`、`files=80`、`top=56c269602e18`、`rtl=07570b1ac1b4`；指纹的定义与算法在 `build/rtl_fingerprint.sh:1-25`（norm1 = 每份 `.v` 先 `tr -d '\r'` 再 md5，按 C 排序后合一次取 12 位） |
| 构建日志 | `build/r118_build_console.txt`（Vivado 2025.2.1，`SW Build 6403652`；结尾 `SYSTEM BUILD DONE`，退出时间 2026-10-04 04:37:57） |
| 轮次身份三件套（bit/xsa/elf 同一条） | `build/r118_gates.txt:3-5`：`system.bit md5=cd04907e1369` / `system.xsa md5=934ebdbaa13b` / `ps_app.elf md5=d0b07f84a068` |
| 门禁 | `build/r118_gates.txt`：`判定 24 项、未判 0`，末行 `GATES: 有红项（判定 24 项）—— 不采纳，保留上一版`；唯一红项是**已声明过**的 `C5c` 顶层台架那一项（口径见 `README.md:56`） |
| 采纳判读 | `build/r118_verdict.txt`、`build/evidence/r118_strict_b1.txt`（B1 严格名册 `pairs_compared=8 losses=0 verdict=GREEN`） |
| 采用工件存档 | `build/evidence/r118_bit/system.bit` + `build/evidence/r118_bit/md5.txt`（本轮实测两者与 `build/system.bit` 同一个 md5：`cd04907e1369da35d21c4090d552f5ee`） |
| 板上身份（最后一次记录） | `build/evidence/r118_board/board_now.txt`：「板上现在 = r118（刷入 2026-10-04 04:49:50，bit_cycle rc=0 board_verify rc=0）」；眼睛签收与刷入三步 rc 在 `build/evidence/r118_eyes/`（`step2_program_pl.txt` 的 `PROGRAMMED xc7z020_1 <- build/system.bit`） |

⚠ **`build/provenance.md`（P16a 质量判据 2 要求指过去的那一份）现在还不存在**
—— 它由 P15a 点名、`report/run-queue.md:25` 标"待开"。所以本卡把"哪一轮"指到**真实存在的轮次件**
（上表 8 行），而不是写一个指向缺失文件的链接。已进 `report/questions-for-team.md`（Q-P16a-4）。

## 2. 如何再生成（真实命令；本轮**没有跑**）

```bash
# 唯一规范入口（README.md:35 与 build/tcl/README.md §1 同一条）
vivado -mode batch -source build/tcl/build_system_axigpio.tcl
# 它会原地覆盖 build/system.bit、build/system.xsa 与 build/ 下那六份报告
# 起飞前先打指纹（链子里就是这么排的，build/r118_chain.sh:27）
bash build/rtl_fingerprint.sh > build/evidence/rXXX_tree_fp.txt
```

判定：**NOT_MEASURED（本轮禁跑构建）**。三条必须一起念的事实：

1. **位流不是逐字节可复现的**：`report/study/05_验证与上板/03_上板流程与踩坑.md:137-138` 原话
   「**bit 文件不会逐字节相同**（布线种子与时间戳不同）—— 所以「复现」的判据是**报告里的数字**，不是文件的 hash」。
   ⇒ 重跑构建得到的是"另一颗 bit"，本卡的 md5 只在**这一轮**成立；复现的验收要拿
   `build/timing_summary.rpt` / `build/utilization.rpt` 与 `bash build/gates.sh` 那一行去比。
2. **不要相信构建的退出码**：`build/tcl/README.md:22-26` 点名 `build_system.tcl`、`build_pl_full.tcl` 这类
   脚本"报错之后仍然 exit 0"，规矩是「要构建只认 `build_system_axigpio.tcl`；跑完必须自己去 `build/` 里核对报告的时间戳」。
3. 构建会覆盖**已入库文件** ⇒ 属于 P23 第 1 节"禁止自动做"的范围，**需队伍批准后才跑**。

## 3. 它怎么进板（加载方式与易失性）

```bash
vivado -mode batch -source build/tcl/program_pl.tcl        # README.md:40 的那一条
```

- 只走 **JTAG**：`build/tcl/program_pl.tcl:15-28`（`open_hw_manager` → `connect_hw_server` →
  在链上按 `PART =~ "xc7z020*"` 选器件 → `set_property PROGRAM.FILE` → `program_hw_devices`）。
  **不写 QSPI/SPI flash**（`README.md:38`、`report/demo_script.md:28`）。
- 可以指到别处的位流做 A/B 对照：`VP_BIT=<路径>`（`build/tcl/program_pl.tcl:10-12`；
  实例：`build/r117_board.sh:13` 那句 `VP_BIT=build/evidence/r116_bit/system.bit bash build/r116_bit_cycle.sh r116back`）。
- **易失**：断电就没了，重上电后 PL 是空的。⇒ 冷上电后必须重跑这一条。
  已记录的现场证据：`report/log/overnight_log.md:985-987`「本机设计只支持 JTAG 下载，没有 `BOOT.BIN`，
  所以**断电重上电后 DONE 常暗是预期行为**」。
- **成功判据（回读）**：stdout 出现 `PROGRAMMED <dev> <- build/system.bit`
  （样张 `build/evidence/r118_eyes/step2_program_pl.txt`，引文见 `board/acceptance.md:98`）。
  链身份回读：`vivado -mode batch -source build/tcl/scan_jtag.tcl` ⇒
  `xc7z020_1 PART=xc7z020 IDCODE=00100011011100100111000010010011`（样张 `build/r90_jtag_scan.log:53-54`）。

## 4. 违反顺序会看到什么（这块 bit 相关的那两条）

| 症状（原文报错） | 起因 | 出处 | 恢复 |
|---|---|---|---|
| 刷 PL 时 app 正在打 AXI ⇒ 之后 `DAP status 0xF0000021`、`pc: N/A`、串口 0 字节 | 应用卡在未完成的 AXI 访问上 | `report/log/issues.md:3211-3212`（症状原话 + 正解）、`report/log/overnight_log.md:2208-2214`、`build/tcl/r116_jtag_recover.tcl:1-8`（脚本头写明"为什么 JTAG 系统复位就够了"） | `xsdb.bat build/tcl/r116_jtag_recover.tcl`（`rst -system`）→ 再走三步链；`build/r116_bit_cycle.sh:22` 把 `rst -system` 固定成第 0 步 |
| `mrd 0x41200000` 报 `Timeout waiting for the Instruction Complete bit` | fabric 是空的（bit 没配上 / PS 复位过） | `report/log/overnight_log.md:2213`；现场件 `build/r109_jtag_probe_console.txt`（同一句在 `0x41220000` 上） | 先 `program_pl`，再读；别去怀疑 RTL |

## 5. 本目录为什么不放第二份 bit

P16a 交付物写的是"板上镜像 + 每个镜像一张来源卡"。仓库里已经有**两份**同一身份的实体
（`build/system.bit` 与 `build/evidence/r118_bit/system.bit`），再加第三份同名文件会撞上
`report/build.md:200-201` 记过的事故（「同名不同内容今晚发生过两次」、规矩 2「下板之前先 md5sum 对 MANIFEST」）。
⇒ 本目录只放来源卡 + 指回权威路径；提交包里二进制由导出器展平到 `board/project/`
（口径：`build/README.md:17-20`）。
**是否要改为在 `board/firmware/` 放实体拷贝**，进 `report/questions-for-team.md`（Q-P16a-6）等你定。
