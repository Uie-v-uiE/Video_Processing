# 现场演示

目标：三分钟内让评委看到“同一帧的原图与处理图”“链路读数”“仪表能被打红”“断电自启”四件事。

## 1 演示前

- 板卡通过 QSPI 冷启动，HDMI 接 1024×600 面板，网线接 PC，COM6 打开；
- PC 网卡 `192.168.1.100/24`，`ping 192.168.1.10` 通；
- 推流脚本、遥测监听、自检脚本已在 PC 上；
- 屏幕显示默认分割画面，OSD 打开。

## 2 顺序

### 2.1 冷启动与链路

断电重上，串口出现启动回显。执行：

```text
stat
```

看到 `[STAT]` 的帧计数、片源、效果选择和几何字。`ping 192.168.1.10` 通。

### 2.2 同帧对照

```bash
python src/host/video_sender.py --demo --seconds 60
```

屏幕上左半是原图，右半是同一帧经效果链处理后的结果。竖缝两侧的渐变、白线和红块应对齐；切 `split swap 1`，左右互换，缝位不动。

### 2.3 效果与几何

串口依次执行：

```text
pipe 000000100
pipe 000010000
zoom 1.5
rot auto 1
rot speed 2
```

观众应看到效果切换、画面放大、自动旋转；竖缝跟着画面列走。每一步后执行 `stat`，OSD 与串口读数一致。

### 2.4 帧间隔与故障

```text
link clr
```

推流 5 秒后：

```text
link
```

看到 `gap_last/min/max/sum` 和 `gap_valid=1`。停止推流 3 秒再 `link`，`gap_last` 和 `gap_max` 增大。

然后跑三阶段自检：

```bash
python src/host/link_selftest.py 192.168.1.10 6
```

干净流帧率正常；注入丢包段帧率掉到 0、作废计数上升；恢复段回到正常。仪表被当场打红再恢复。

### 2.5 SD 回放

```text
sd files
sd file 1
play
```

屏幕切到 SD 段；`stop` 后切回网络源：

```text
src 1
```

### 2.6 收尾

```text
pipe 000010000
zoom 1.0
rot auto 0
split video
split 50
osd on
```

回到演示默认状态，`stat` 与开场一致（`pub=` 除外）。

## 3 兜底

- 推流不通：先 `ping`，再检查 PC 网卡和防火墙；PL 的 ICMP 应答不依赖 PS。
- 串口无回显：确认 COM6 没被占用、波特率 115200；必要时断电重上。
- 画面停在最后一帧：`src 2` 重新钉住 SD，或 `src 1` 回网络。
- 自检收不到遥测：先 ping 一次板子，让板子记住 PC 的 MAC/IP。
- HDMI 无输出：确认面板输入源和分辨率；OSD 第一行应显示源画面 512×300。
