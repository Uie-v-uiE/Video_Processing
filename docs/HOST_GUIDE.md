# 上位机工具：推流与串口控制

这一层的活只有两件：**把画面灌进板子**、**把命令送进固件**。全部只依赖 Node.js 和
Windows 自带的 PowerShell，不需要 Python、不需要装任何依赖包。

| 需要 | 用来做 | 备注 |
|------|--------|------|
| Node.js 18+ | 所有 `src/host/*.mjs` | 实测 v24；只用 `node:` 内置模块 |
| PowerShell 5+ | 串口收发（`board/*.ps1`） | 用自带的 `SerialPort`，本机没有 pyserial |
| ffmpeg（可选） | 把 mp4 解成裸流 | 只有推真实视频才需要 |

## 1. 连接与准备

1. 网线接 **PL 侧网口**（PHY 是 RTL8211，挂在 PL，不是 PS 网口）。
2. PC 网卡静态地址：`192.168.1.100 / 255.255.255.0`；板卡固定 `192.168.1.10`，视频端口 `UDP 5001`。
3. `ping 192.168.1.10` 能通再推流 —— 通不通由 PL 里的 ICMP 应答决定，所以这一步同时验了位流。
4. 板侧下载顺序（JTAG，不写 QSPI）。前提是把 Vivado 与 Vitis 2025.2.1 的 `bin` 目录放进 PATH，
   下面用裸命令名（`vivado` / `xsdb`）：

```bat
xsdb build\tcl\ps_jtag_boot.tcl
vivado -mode batch -source build\tcl\program_pl.tcl
xsdb build\tcl\ps_app_reload.tcl
```

只想看 HDMI 出图、不需要命令的话，第三步可以省。串口是 COM6 / 115200 / 8N1。

## 2. 推流：两条发送端，一条零依赖

| 工具 | 要装什么 | 能做什么 | 什么时候用它 |
|---|---|---|---|
| `python3 src/host/udp_push.py` | **只要 Python 3（标准库）** | `--pattern edge` 整屏逐帧黑白交替（判"换帧是否原子"）、`--file F` 推裸 RGB565 帧流、`--pace-mbps` 限速、`--drop-every N` 确定性丢包 | 默认用它：评委/任何人拿到包就能推，不需要 Node；演示"坏帧不上屏"用 `--drop-every` |
| `node src/host/video_sender.mjs` | Node 18+（实测 v24，只用内置 `node:` 模块） | 上面那些 + 一整套**自带判据的图案**：`bars`（横条纹滚动 + 移动方块拖影 + 左缘奇偶行洋红标记，用于行序错乱）、`frameid`/`wordid`（每帧一个编号的 8 个二值格 ⇒ 拍照就能读出屏上这帧是第几帧）、`grad`、`hold`、`move`、`edge` | 做归因实验时用它；协议与上面完全一致（同一套 `[u32 LE 偏移][载荷]`） |

```bash
python3 src/host/udp_push.py --pattern edge --fps 15 --count 600
python3 src/host/udp_push.py --file frames.rgb --fps 30 --pace-mbps 15
python3 src/host/udp_push.py --pattern edge --count 300 --drop-every 500   # 板上必须整帧不上屏
node src\host\video_sender.mjs --test bars --fps 15
node src\host\video_sender.mjs --test frameid --fps 15 --count 200   :: 丢帧判据专用
node src\host\video_sender.mjs --file - < raw.rgb565                 :: 裸流从 stdin 进
```

```bat
node src\host\video_sender.mjs --test bars --fps 15 --ip 192.168.1.10
```

| 参数（下表是 `video_sender.mjs` 的；`udp_push.py` 的参数用 `--help` 看，命名一致但少几项） | 默认 | 说明 |
|------|------|------|
| `--ip` / `--port` | 192.168.1.10 / 5001 | 板卡地址 |
| `--src` | 192.168.1.100 | 本机绑定地址；传 `""` 走默认路由 |
| `--fps` | 15 | 帧率。线速附近请配合下面的匀速 |
| `--count N` | 0（一直发） | 发满 N 帧退出 |
| `--pace-mpbps` | 15 | **包内匀速**：一整帧 221 包若以线速倾泻会打爆板端入包 FIFO |
| `--no-pace` | 关 | 关掉匀速（做压力实验时才用） |
| `--mtu-payload` | 1392 | 必须 8 的倍数，见 §4 |
| `--drop-every N` | 0 | 每 N 包确定性丢一个（演示坏包恢复，不是随机） |
| `--dump FILE` | 关 | 把第一帧的字节落盘，供离线核对 |

`--test` 的图案各管一件事，选错了就看不出问题：

| 图案 | 看得出的现象 | 看不出的 |
|------|--------------|----------|
| `bars` | 横向黑纹（丢行）、黄块拖影（重复帧）、左缘奇偶行标记（行序错乱） | 逐帧丢字 |
| `grad` | 量化、色带 | 时序类 |
| `edge` | 换帧是否原子（非原子会看到灰行/残影） | 空间定位 |
| `move` | 谁在动 ⇒ 一眼分清屏幕上是哪一路源 | 位级错误 |
| `blocks` `hold` `wordid` | 地址映射、车道对齐 | 逐帧丢字 |
| `frameid` | **逐帧丢字 / 陈旧帧**（每个字写着自己来自第几帧） | —— |

推真实视频用根目录的 `stream_video.bat`（双击、或把文件拖到图标上、或
`stream_video.bat <你的视频.mp4> 30`）。它只做一件事：让 ffmpeg 把视频解成面板要的
512×300 RGB565 裸流，用管道喂给 `video_sender.mjs --file -`。解码不进 Node 是有意的：
发送端只按帧边界切片，末尾不足一帧的残片直接丢掉并报数 —— 半帧会让板端"这一帧少一行"
变成常态，`frames_bad` / `rows_miss_max` 从此没法对账。

## 3. UDP 协议（与 PL 端对齐）

```
每包   : [u32 小端 byte_offset][RGB565 载荷 ≤ 1392 B]
一帧   : 512 × 300 × 2 = 307200 B ≈ 221 包
```

- 板端 `frame_reasm` 按 offset 落位，**乱序可以拼对**；
- 坏包丢弃、不重传，下一帧自动恢复；
- 收到完整帧后 PL 自动把屏幕交给 ETH，不必先发 `src 1`。

## 4. 分包长度为什么钉在 8 的倍数

DDR 打包器一个字是 64bit（4 像素）。载荷取 1396 时包边界落在字中间，同一个字被分两次推送、
后一次覆盖前一次 ⇒ 每帧留下约每两个包一处的 4 字节洞，洞里是 `0x0000`，屏上就是均匀散布的黑点。
v6.4 起打包器按 16bit lane 驱动 `WSTRB`，这个坑已经被硬件堵掉（同一块板、同一版 bit 复测：
1396 → 命中率 100.0%、空洞 0）。默认仍建议 1392：少发约 0.3% 的重复 beat，而且"一个包不跨两个
64bit 字"这个性质让包内相位分析还能用。`--mtu-payload` 只为做这个对照实验而存在。

## 5. 串口：命令与捕获

| 脚本 | 作用 |
|------|------|
| `board/uart_cmd_script.ps1 -Port COM6 -File <清单> [-DelayMs 900] [-Out <捕获>]` | 按行发，每行前面 echo `>> <行>`，所以捕获能按命令切片 |
| `board/uart_cap_once.ps1 -Port COM6 -Seconds 14 -Out <文件>` | 只收不发，抓一段自发输出（心跳、`[STAT]`） |
| `node src/host/uart_cmd_check.mjs [--file board/cmd_battery_v81.txt] [--port COM6] [--dry]` | 命令层的验收判据：逐条对回声 + 该拒的必须拒 + 跑完 `STAT` 必须回到初态 |

命令的**权威表在 `docs/COMMANDS.md`**（动词、参数、回声、拒收条件都在那），命令之间的
**覆盖关系**（哪些组合会静默无效，例如 `zoom fit 1` 下的 `zoom 1.5`）在
`docs/COMMAND_PRECEDENCE.md`。这里只抄最常用的几条：

```
src auto | src 0 | src 1 | src 2     片源：0=图卡 1=DDR(网络) 2=DDR 并起播 SD
pipe <九位> | pipe show              效果链，一位一级：gray invert blur sharpen sobel binary bin_pol erode dilate
th 80                                二值化阈值
zoom on|off|auto|fit|1.5             缩放开关与倍率
rot auto [0|1] | rot 45 | rot show   旋转
split 50 | split swap 1 | split show 分割线位置、左右互换
bilin on|off                         双线性 / 最近邻
gamma 1.8 | gamma off | gamma auto   PS 算曲线写进 PL 的 256 项表
sd files | sd file 2 | play | stop | fill | autoplay 0|1
temp [th 70] | stat | help
```

V7 的老写法（`SRC0` `TH80` `ZOOM1` `BILIN1` `FRAME12`）仍然收；裸五位串只回一句等价的九位、
**一个位都不写**（五位控制字已从 RTL 删净）。

跑判据前的两件事，都是踩过坑的：

1. **确认板子在默认态**。判据要求"末态 == 初态"，如果之前手动改过缩放/效果，这条会红 ——
   红得对，要先把状态清回去，而不是把判据放宽。
2. **COM6 不能同时被别的终端占着**，否则 PowerShell 报 `UnauthorizedAccessException`。
   这个脚本会**重写** `board/uart_script_capture.txt`（已被 `.gitignore` 挡住，不再进库）。

## 6. 工具清单与被谁调用

`build/gates.sh` 与 `build/board_verify.sh` 会点名的，才是"必须有"的；其余是量测/复算工具。

| 脚本 | 一句话 | 被谁调用 |
|------|--------|----------|
| `src/host/udp_push.py` | 零依赖推流（协议、限速、确定性丢包）；`--pattern edge` 是"换帧原子性"的现场判据 | 手工；`docs/HOST_GUIDE.md` §2 的第一条 |
| `build/build_ps_app.py` | 不用 IDE 把 `src/ps` 编成 ELF，并做**成品自检**（入口 = `_boot`、`_vector_table` 必须在 0x0、`.text` 体积下界、七个符号必须在）；退出码 2/1/3 分别指"输入不在/编译失败/成品不可执行" | `docs/BUILD.md` §1；与 Node 版孪生工具（仓库里 `ps_app.mjs`）产出**逐字节相同**（md5 `d0b07f84a068…`，即板上那一版）|
| `doc_enc_check.mjs` | 手写文件（`.md .v .c .h .mjs .sh .ps1 .tcl`，范围 `docs/board/src/sim/tools/build/tcl` **与 `skill/`**——后者是 2026-09-29 补进来的，之前那 29 个给评委读的文件从没被扫过）必须 UTF-8 无 BOM、无 CR 混排、无替换符/私用区 | `build/gates.sh` |
| `doc_currency_check.mjs` | 文档里点名的 `build/frozen_rNN/` 必须盘上真有、旧编号不许写成"当前默认" | `build/gates.sh` |
| `line_cite_check.mjs` | 交付文档里的 `文件.v:NNN` 引用：硬错=文件不在树里 / 行号越过文件末尾（决定退出码）；"锚点不在那几行"只列候选不判红（`--self` 是 #122 那个真实事故） | **暂时不在门禁里**——注册之前要先给它一条能红的对照，见 `ISSUES #122` 收口段；今晚用它把 7 处硬错清零 |
| `demo_cmds.mjs` | 演示脚本里的命令块逐条对固件解析器（不碰板子） | `build/gates.sh` |
| `ps_hb_check.mjs` | 不碰板子：从固件源码原文抠出"PS 心跳/`ps_hold` 那一半"必须同时成立的事实逐条钉；`--self` 用四条变异证明它会红 | `build/gates.sh` |
| `uart_cmd_check.mjs` | §5 那条命令电池 | `build/board_verify.sh` |
| `pipe_len_check.mjs` | `pipe` 这一条命令的"唯一口径"离线核对：位号四份一致、五位一条都不写、退役不退半截（A/B/C/D 四组，不碰板子） | 作者留存，不随包发布 |
| `udp_sink_check.mjs` | 本机 UDP 环回自检：协议、切片、匀速这三件事对不对，不依赖板子 | 手工（改发送端后必跑） |
| `health_read.mjs` | JTAG 读健康快照 12 条 lane；`--json` 出机器可读对象，`--gapclr` 归零帧间隔统计 | `build/board_verify.sh`、`board/README.md` |
| `geom_check.mjs` | 缩放/旋转的几何读数与预期公式对账 | `build/board_verify.sh`、`board/README.md` |
| `arb_handover_test.mjs` | 无人值守的仲裁交接：静默→推流→停→再推，100 ms 密度采 lane30，七条 PASS/FAIL；`--selftest` 不打板子 | `build/board_verify.sh` |
| `video_sender.mjs` | 推流（§2） | `build/board_verify.sh`、演示 |
| `make_sd_video.mjs` | 把 mp4 转成 SD 播放要的裸帧序列（`--in a.mp4 --out E:`） | `board/README.md` |
| `metrics.mjs` | 两次 `health_read --json` 的差值算成抖动/丢包指标；`--selftest` 验算数本身 | `board/evidence_r41/` |
| `ddr_verify.mjs` | 只回读 DDR 两个 bank 并落盘 `data/measured/ddr_dump.out` | 作者留存，不随包发布 |
| `ddr_stale.mjs` | 反解每个 16bit 字来自第几帧 ⇒ 丢字率、游程分布、错帧计数 | 作者留存，不随包发布 |
| `ddr_holemap.mjs` | 把回读结果按行段画空洞分布 | 作者留存，不随包发布 |
| `ingress_probe.mjs` | 定点注入：只灌 K 个包（每像素写"字号+一个没用过的帧号"）再回读，报落位率与"从第几个字开始丢"⇒ 直接指出是哪一级缓冲不够 | 作者留存，不随包发布 |
| `measure_v63.mjs` | 一条命令走完"推 frameid → 发完 → 回读两 bank → 相位判据" | 作者留存，不随包发布 |
| `card_preview.mjs` | 把 `sim/tb_v83_card_render.v` 倒出的像素转储渲染成 PNG ⇒ 图卡观感一分钟能看到，不用等一轮构建+上板 | 作者留存，不随包发布 |
| `interp_study.mjs` | 动手写硬件之前先算清"插值在本项目的几何区间里值不值"（`inv=256/512` 两端小数位恒为 0 ⇒ 双线性逐像素等于最近邻） | 作者留存，不随包发布 |
| `lane30_watch.mjs` | 高频盯 lane30 那一位（`[秒=45] [间隔ms=150]`） | 作者留存，不随包发布 |
| `temp_formula_check.mjs` | XADC 温度公式与固件换算对账 | 作者留存，不随包发布 |
| `repo_path.mjs` | 公共路径/落盘函数，被上面几个 import | —— |

## 7. 故障排查

| 现象 | 先查 |
|------|------|
| ping 不通 | 是不是插了 PS 网口；PC IP；位流是否已下载（ICMP 在 PL 里） |
| 推流无画面 | `health_read.mjs` 看 `eth_live`/`owner_eth`；降 `--fps 15`；`stat` 看片源 |
| 屏上均匀黑点 | 分包长度（§4）；或 `--pace-mpbps` 太大把入包 FIFO 打满，看 `drop_words` |
| 画面花/错位 | 网线；关掉杀软的流量扫描；网卡强制全双工 1G |
| 串口无响应 | ELF 是否下载；COM 号；115200 8N1；有没有别的终端占着端口 |
| 判据脚本卡住 | `hw_server` 是否在跑；xsdb 与 vivado 的调用顺序；读 DDR 前要不要 `rst -processor` |
| `uart_cmd_check` 报"末态≠初态" | 板子之前被手动改过状态；先清回默认再跑 |
