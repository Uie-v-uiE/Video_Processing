# src/host 上位机（PC 侧）

## 这个目录现在只放什么

**只放 PC 侧的上位机工具**：推流/发送（`video_sender.mjs` / `video_sender.py` / `udp_push.py`）、
一键测试（`one_click_test.*`）、各把读回与判据尺子（`health_read.mjs`、`ps_hb_check.mjs`、
`uart_cmd_check.mjs`、`geom_check.mjs`…）。**板上裸机固件不在这里** —— `main.c` / `sd_play.c` /
`sd_play.h` / `lscript_ocm.ld` 在 `src/ps/`，与 `src/rtl/`、`src/constraints/` 同级
（口径改过两次：r122 曾把固件收进 `src/host/ps/`，本轮搬回 `src/ps/`）。
`build/deliver_spec_check.mjs` 的 C1-2 现在按扩展名分家判（固件必须在 `src/ps/`、
PC 侧必须在 `src/host/`），`--c1-2-self` 那六条对照钉着它会判红。
本目录的 `ps_hb_check.mjs` 文件名恰好以 `ps_` 开头，它是 PC 侧尺子，
不要因为名字里有 `ps` 就把它跟着固件一起搬走。

## 环境依赖

- Node 24（本机实测 v24.21.0）：`.mjs` 只用内置模块（`node:dgram`/`node:child_process`），零第三方包。
- Python 3.12（本机实测 3.12.10）：`.py` 只用标准库（`argparse`/`socket`/`struct`/`subprocess`），零第三方包，**不需要 pyserial**（读回不走串口）。
- 一键测试的第 ②④ 步走 JTAG：需要 Vitis 的 `xsdb` 与正在运行的 `hw_server`，路径由环境变量 `VP_XSDB` 或 `--xsdb` 给；没有板子时加 `--dry-run`（不碰网络与板子）。

## 使用方法

- 双击入口：仓库根 `run_test.bat`（调 Node 侧）。跨平台入口：`bash run_test.sh`（调 Python 侧，参数原样转给脚本）。
- 命令行：`node src/host/one_click_test.mjs` 或 `python src/host/one_click_test.py`；通用发送工具是 `src/host/video_sender.mjs` / `video_sender.py` / `udp_push.py`。
- 跑完应看到：`[1/4] PING`、`[2/4] CONNECT`、`[3/4] SEND`、`[4/4] COLLECT` 四行读数（判定词 `PASS`/`FAIL`/`NOT_MEASURED` 在每行末尾）+ 一行 `ONE-CLICK` 总结论，退出码 0；`xsdb` 的原始回读留在 `data/measured/one_click_*.out`（该件要板上真跑一轮才生成，仓库里没有这一件）。
- 通路口径（不是网络读回）：板侧固件没有 UDP 回包，"连接"与"回收"读的都是 AXI GPIO 的 lane —— lane 号写 GPIO_0 的 bit[31:27]、值从 GPIO_1 读，与 `health_read.mjs` 同一套；lane8=收到的 UDP 包数、lane9=有效字节数、lane0=drop_words、lane1=frames_bad|bad_pkts。

## 命令行语法参数表

| 参数名 | 含义 | 默认值 | 示例 |
| --- | --- | --- | --- |
| `--ip` | 板卡地址：第 ① 步 ping、第 ③ 步发送目标 | `192.168.1.10` | `--ip 192.168.1.20` |
| `--port` | UDP 目标端口，转给发送脚本 | `5001` | `--port 5001` |
| `--clip` | 内置测试片源，相对仓库根（两实现读同一份） | `data/inputs/wordid_512x300.rgb565` | `--clip data/inputs/rand64_512x300.rgb565`（这两份是生成件，不随包：`node data/generated/gen_inputs.mjs` 现出） |
| `--frames` | 发多少帧；片源整帧数不足则重复补足后截到该帧数 | `5` | `--frames 2` |
| `--fps` | 转给发送脚本的帧率：Python 侧 `udp_push.py` 按它分帧停，Node 侧 `video_sender.mjs` 的 stdin 模式只按 `--pace-mbps` 匀速 | `15` | `--fps 30` |
| `--pace-mbps` | 发送限速 MB/s（保护板端入包 FIFO），0 = 不限速 | `15` | `--pace-mbps 0` |
| `--gpio0` | 写 lane 号的 GPIO_0 基址，十六进制不带 0x | `41200000` | `--gpio0 41200000` |
| `--gpio1` | 读 lane 值的 GPIO_1 基址，十六进制不带 0x | `41210000` | `--gpio1 41210000` |
| `--hw-port` | hw_server 端口 | `3121` | `--hw-port 3121` |
| `--xsdb` | xsdb 可执行文件 | 环境变量 `VP_XSDB`，没给则 `xsdb.bat` | `--xsdb <Vitis>/bin/xsdb.bat` |
| `--dry-run` | 只打印将要做什么：不 ping、不连板、不发包 | 关 | `--dry-run` |
| `--help` | 打印参数全表 | 关 | `--help` |
