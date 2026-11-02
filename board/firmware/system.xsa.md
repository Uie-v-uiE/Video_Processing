# 来源卡 · `build/system.xsa`（平台包：PS 配置 + 位流 + BD 硬件描述）

| 字段 | 值 | 怎么当场回读 |
|---|---|---|
| 权威路径 | `build/system.xsa`（zip 容器） | `ls -la build/system.xsa` |
| 大小 | **865533 B** | `stat -c %s build/system.xsa` |
| MD5 | **`934ebdbaa13b4ff6b63323a656453c52`** | `md5sum build/system.xsa` |
| SHA-256 | `ffc3eda9e35c6764de6d3b80e5c4ca4eff33ec6c5113159afa66abdbcaf45b88` | `sha256sum build/system.xsa` |
| 文件时间 | 2026-10-04 04:37:55 | `stat -c %y build/system.xsa` |
| git 身份 | 已入库；最后一次写进 git = `d420db6`（2026-10-04 08:05） | `git log -1 --format=%h_%ad -- build/system.xsa` |

## 1. 由哪一轮构建产生

**r118**，与 `build/system.bit` 同一轮同一次构建（`build/r118_build_console.txt` 结尾
`SYSTEM BUILD DONE` / 退出时间 2026-10-04 04:37:57；xsa 的 04:37:55 在它前面 2 秒）。

| 项 | 件 |
|---|---|
| 源码指纹 | `build/evidence/r118_tree_fp.txt`（`fpver=norm1 files=80 top=56c269602e18 rtl=07570b1ac1b4`） |
| 轮次身份行 | `build/r118_gates.txt:4` `system.xsa md5=934ebdbaa13b` |
| 独立第二次读数 | `build/evidence/r118_board/board_verify_console.txt:5`：`build/system.xsa  md5=934ebdba  2026-10-04 04:37`（与上面同一颗，由 `build/board_verify.sh:140-143` 打印） |
| 门禁/判读 | `build/r118_gates.txt`（判定 24 项、有红项 = 声明过的 `C5c`）、`build/evidence/r118_strict_b1.txt` |

警告：`build/provenance.md` 仍不存在（P15a 待开，`report/run-queue.md:25`）⇒ 本轮次指到上表的真实件。
见 `report/questions-for-team.md`（Q-P16a-4）。

## 2. 里面到底有什么（本轮实测，只读解压、不写盘）

用 python 读 zip 的条目表（命令在文末 §6）：

| 条目 | 大小 | MD5（本轮实测） |
|---|---|---|
| `ps7_init.tcl` | 34952 B | `142e477927219cf686a072d36f3f2801` |
| `ps7_init.c` | 531503 B | `b1f68a71afd044725540c40eeebf3bcf` |
| `ps7_init.h` | 3796 B | `8d960d509a98fa330ffe1d3da3661742` |
| `ps7_init.html` | 2906788 B | `2ffce196caf6383741f03765a4486184` |
| `ps7_init_gpl.c` / `.h` | 532120 / 4414 B | `4571a2cc13e2a50261eaa770e35a28bc` / `8e3ae4028bf88f3d80cbb3eed6965c43` |

## 3. **必须如实登记的一条不一致**：仓库里那份 `build/ps7_init.tcl（不随包）` 是旧的

`build/tcl/ps_jtag_boot.tcl:7-9,22-45` 的取文件顺序是：
① `PS7_INIT` 环境变量 / 命令行参数 → ② **已经在盘上的 `build/ps7_init.tcl（不随包）`** → ③ 从 `build/system.xsa` 自动解出。

本轮实测（只读比对，见 §6）：

| | 大小 | MD5 | 时间 |
|---|---|---|---|
| 盘上 `build/ps7_init.tcl（不随包）` | 31277 B | `b4591066ecb619393dbd7ec90dbbc250` | 2026-09-23 02:54:46 |
| 当前 xsa 里的 `ps7_init.tcl` | 34952 B | `142e477927219cf686a072d36f3f2801` | 随 r118 |

⇒ **两者不同**，而且 .gitignore 把 `build/ps7_init.tcl（不随包）` 当派生物排除（`.gitignore:88-89`
「从 build/system.xsa 里解出来的 PS 初始化脚本（派生物，ps_jtag_boot.tcl 会自动重建）」），
所以它不会随包、也不会在 clone 之后存在。两种后果要分开念：

- **在别人的干净克隆上**：盘上没有那份旧文件 ⇒ 走 ③ ⇒ 自动从 r118 的 xsa 解出当前版本 ⇒ 正确。
- **在本机这一份工作位上**：盘上有 2026-09-23 那份 ⇒ 走 ② ⇒ **PS 初始化用的是八天前的那份脚本**。
  这一步会不会真的改变板上行为，没有测（本轮不开板、不跑链），**判 NOT_MEASURED**，
  但它是一个可当场判定的不一致，不能写成"现在应该是当前 xsa 的那份"。

回读动作（任何人 5 秒判掉这一格，纯本地、不碰板）：

```bash
md5sum build/ps7_init.tcl（不随包）                 # 期望若与下一行相同 = 一致
python -c "import zipfile,hashlib;\
z=zipfile.ZipFile('build/system.xsa');\
print(hashlib.md5(z.read('ps7_init.tcl')).hexdigest())"
```

不一致时的处置（**属删除派生物，需队伍点头**；本轮没做）：删掉 `build/ps7_init.tcl（不随包）` 再跑
`xsdb.bat build/tcl/ps_jtag_boot.tcl`，让它按 ③ 自己重解（脚本会打印
`AUTO-EXTRACT ps7_init.tcl from system.xsa: OK` 与 `PS7_INIT_FILE: <路径>`，见
`build/tcl/ps_jtag_boot.tcl:42,51`）。或者干脆显式给：`PS7_INIT=<路径>`。
⇒ 已进 `report/questions-for-team.md`（Q-P16a-7）。

## 4. 如何再生成（真实命令；本轮**没有跑**）

```bash
vivado -mode batch -source build/tcl/build_system_axigpio.tcl   # bit 与 xsa 同一次构建产出
```

判定 **NOT_MEASURED**（本轮禁跑构建，且它会覆盖已入库文件 ⇒ 需批准）。
xsa 的复现判据同 `board/firmware/system.bit.md` §2 第 1 条：报告数字，不是文件 hash。

用途链（xsa 是 PS 侧一切的源头）：

- `ps_jtag_boot.tcl` 从它解 `ps7_init.tcl`（§3）。
- 重建裸机 BSP：Vitis → New Platform → 选 `build/system.xsa` → BSP 勾 `uartps/xsdps/xgpiops` → Generate，
  把 `standalone_ps7_cortexa9_0/bsp` 指给 `PS_BSP`（原文：`build/ps_app.mjs:15-17`、`build/build_ps_app.py:18-20`）。
  仓库内现成那份在 `vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/`
  （本轮实测 `lib/libxil.a` 存在；另有 `export/platform/sw/standalone_ps7_cortexa9_0/lib/libxil.a`）。

## 5. 它不进板

xsa 本身**不下载到板上**：它是工具侧的平台包（PS 配置 + BD 硬件描述）。板上跑的只有
`system.bit`（PL）与 `ps_app.elf`（PS），PS 初始化由 `ps7_init.tcl` 经 JTAG 执行。
⇒ 这条也是"别把 xsa 当固件刷"的防呆说明；出处 `build/tcl/ps_jtag_boot.tcl:6-14`
（那里还写明：`ps7_init` 的 tcl 版本**不含** FSBL 写的 `FPGA_FCM*`（HP 通道缓冲）一类寄存器，
所以正式启动仍应走 FSBL/ELF —— 本项目故意选了 JTAG 这条路）。

## 6. 本轮真实跑过的只读命令

```bash
stat -c %s build/system.xsa; md5sum build/system.xsa; sha256sum build/system.xsa; stat -c %y build/system.xsa
python -c "import zipfile,hashlib; z=zipfile.ZipFile('build/system.xsa'); \
[print(n,len(z.read(n)),hashlib.md5(z.read(n)).hexdigest()) for n in z.namelist() if 'ps7_init' in n]"
# 输出即 §2 的表；另外读了 build/ps7_init.tcl（不随包） 的 size/md5/mtime ⇒ §3 的对比
```
