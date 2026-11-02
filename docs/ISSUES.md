# 开发问题与修复记录

按时间顺序记录本工程调试过程中遇到的问题、定位方法与最终修复。对复现和答辩都有用。

---

## 1. EMIO GPIO 读回恒 0

**现象：** 通过 PS EMIO 控制 PL 效果位，DIRM/DATA 读回一直是 0，控制无效。

**定位：** 扫描 GPIO bank 寄存器，只有部分偏移可写；官方 `XGpioPs_Write(bank=2)` 实际打到了 DATA1。

**修复：** 放弃 EMIO，改用 **GP0 上的 AXI GPIO**，基址 **0x41200000**。控制字经 AXI 总线写入 PL。

**教训：** 部分 Zynq 板卡 EMIO GPIO 未接到可观察 IO 或 bank 配置异常，外设控制优先走 AXI GPIO。

---

## 2. lwIP 函数名与 typedef 冲突

**现象：** 编译报 `udp_recv_fn` 重定义。

**原因：** 自定义回调名与 `lwip/udp.h` 中的 typedef 同名。

**修复：** 回调改名为 `on_udp_frame`。

---

## 3. platform.h 缺失导致编译失败

**现象：** `fatal error: platform.h: No such file or directory`。

**原因：** empty_application 模板不一定生成 platform.h；`__has_include` 在部分工具链下仍会尝试包含。

**修复：** 去掉 platform.h 依赖，直接：

```c
Xil_ExceptionInit();
Xil_DCacheEnable();
Xil_ICacheEnable();
Xil_ExceptionEnable();
```

---

## 4. PHY 自协商失败 `link_speed invalid`

**现象：**  
```
Start PHY autonegotiation
autonegotiation complete
Phy setup error : link_speed invalid
```

**原因：** RTL8211 在 `CONFIG_LINKSPEED_AUTODETECT` 下 `get_IEEE_phy_speed` 返回无效值。

**修复：**
1. BSP `lwipopts.h` 改为 `#define CONFIG_LINKSPEED1000 1`
2. `xemacpsif_physpeed.c` 失败路径强制 1000 Mbps + `SetUpSLCRDivisors`

**结果：** `link speed for phy address 1: 1000`

**注意：** Platform 重编会把 lwipopts 冲回默认，需在 Platform 工程里改库配置，或重编后再改一次。

---

## 5. ping 不通：PC 网卡 IP 错误

**现象：** 板端 PHY link=1，但 ping 超时。

**定位：** `ipconfig` 显示「以太网 2」为 `169.254.x.x`（APIPA），不是 192.168.1.100。

**修复：**

```powershell
New-NetIPAddress -InterfaceAlias "以太网 2" -IPAddress 192.168.1.100 -PrefixLength 24
```

**教训：** 双网卡机器上必须确认用的是接板子的那块网卡，并设静态 IP。

---

## 6. ping 通但 UDP 不到：源地址走错网卡

**现象：** ping 正常，`STAT` 里 `rxcnt=0`，UDP 无包。

**原因：** PC 同时有 WLAN + 以太网，默认路由可能从 WLAN 发出。

**修复：** 上位机 `socket.bind(("192.168.1.100", 0))`，强制从以太网源地址发送。

---

## 7. 串口「能收不能发」

**现象：** Vitis 终端可收打印；第三方串口助手发送命令无响应。

**原因：** 固件在收到 `\r` 或 `\n` 时才解析一行；部分助手默认无行尾或只发 LF。

**修复：** 助手设 **115200 8N1、无流控、发送 CR+LF**（勾选「发送新行」）。

---

## 8. 自动 STAT 刷屏干扰操作

**现象：** 主循环每秒打印 STAT，串口被刷满，发命令困难。

**修复：** 去掉自动打印，只保留手动 `STAT` 命令。

---

## 9. 发效果位时误清 src_sel

**现象：** 发 `00111` 后画面切回彩条；`SRC1` 又把效果清零。

**原因：** `ctrl_set(en, 80, 0)` 写死 src=0；`SRC1` 写死 en=0。

**修复：** 拆成 `cur_en / cur_thr / cur_src` 三个独立状态，各命令只改自己的字段。

---

## 10. HDMI 只有窄条：AXI 每 beat 只写 1 个像素

**现象：** `SRC0` 彩条满屏；`FILL`/视频只在每半屏左侧出现一条窄带。

**原因：** 64-bit beat 含 4 个 RGB565，旧逻辑每个 rvalid 只写 1 个像素且切片错位，每行只写了一部分列。

**修复：** 重写 `axi_frame_writer`：锁存整拍数据，再用 4 拍拆成 4 个像素顺序写入 BRAM。

---

## 11. 行地址 12 位左移溢出

**现象：** 修复拆包后画面仍异常。

**原因：** `(row+1) << 10` 在 12 位下，row≥4 时回绕到 0，后面行覆盖前面行。

**修复：** 全部改为 32 位运算：`(row + 1) * ROW_BYTES`，`row * IMG_W + xw` 用 32 位再截取 19 位地址。

---

## 12. 0° 旁路 mapper 导致流水线错位

**现象：** 为绕过旋转映射，在 angle=0 时 `enable=0` 直通，延迟从 3 拍变成 1 拍，与 sideband 4 拍不对齐。

**修复：** angle=0 时对 cx/cy/oob 做同样 **3 拍寄存器延迟**，再与 BRAM 读对齐；angle≠0 仍走 mapper。

---

## 13. 强制走 mapper 引入上下翻转

**现象：** 为统一流水线延迟，`enable=1'b1` 始终走旋转映射后，画面出现上下颠倒。

**原因：** mapper 内含 Y 翻转的定点运算，在边界/符号扩展下 0° 不是严格恒等。

**修复：** angle=0 **旁路 mapper**，只用延迟后的 cx/cy；angle≠0 才启用映射。

---

## 14. 误加水平翻转导致文字镜像

**现象：** 为「纠正」左右顺序，在每个半屏内做了 `PANE_W-1-x`，中文全部镜像。

**修复：** 去掉水平翻转，恢复 `cx = x 或 x-PANE_W`。

---

## 15. 32-bit 半字对调导致视频发糊

**现象：** FILL 四色块看起来正确；视频「34123412」错位。一度把 64-bit 的两个 32 位半字对调后，顺序「正常」但画面非常糊。

**分析：** FILL 是大色块，**看不出 4 像素组内错位**；视频细节一错位就表现为模糊/横纹。真正的问题是前面的地址溢出与拆包错误，修好后自然像素序就是 `[15:0],[31:16],[47:32],[63:48]`。

**修复：** 恢复标准小端拆包，去掉半字对调。

**教训：** 诊断图案要用**细线/棋盘/文字**，不能只用大色块。

---

## 16. UDP 乱序导致帧错位

**现象：** FILL 静态正确；流式视频出现块状错位、发糊。

**原因：** UDP 不保证顺序；按到达顺序 memcpy 会打乱帧布局。

**修复：** 包头增加 **u32 小端 offset**，板端写到 `FRAME_ADDR+offset`。

包格式：`[offset:4][rgb565 payload]`，payload ≤1396 B。

---

## 17. Vitis Run vs xsdb 下载

**现象：** 只用 xsdb `rst -processor` + `dow` 时 UART 无输出。

**原因：** 缺少 `ps7_init` / `ps7_post_config`，UART、时钟未初始化。

**修复：** 正式流程用 **Vitis Run**（含 FSBL + ps7_init + bit + ELF）。脚本下载须：

```
loadhw -hw system.xsa
source ps7_init.tcl
ps7_init
ps7_post_config
rst -processor
dow app.elf
con
```

---

## 18. 精简版 FFmpeg 无法解 H.264

**现象：** `D:\Software\Ghost\FFmpeg` 报 no decoder for h264 / rawvideo muxer 不存在。

**修复：** 使用 scoop 完整版  
`C:\Users\wenqu\scoop\apps\ffmpeg\9.0.1\bin\ffmpeg.exe`  
（含 H.264 解码）

---

## 19. Platform 重编冲掉 lwIP 配置

**现象：** 改完 lwipopts 后一 Build Platform 又变回 AUTODETECT。

**修复：** 在 Vitis Platform 的 BSP 库设置里把 `lwip220_temac_phy_link_speed` 设为 `CONFIG_LINKSPEED1000`，或重编后再次修改并只重编 lwip 库。

---

## 快速对照表

| 症状 | 优先检查 |
|------|----------|
| 无 HDMI | 时钟、bitstream、显示器 1024×600 |
| 彩条正常、视频窄条 | AXI 拆包、行地址位宽 |
| 视频镜像/翻转 | 0° 是否旁路 mapper、有无多余翻转 |
| 视频块状错位 | UDP offset、是否乱序 |
| FILL 对、视频糊 | 像素序是否被半字对调；片源是否过度缩小 |
| ping 不通 | PC IP、网线是否 PS ETH、防火墙 |
| ping 通无 UDP | bind 源 IP、STAT 的 rxcnt |
| 串口发命令无效 | CR+LF、波特率、是否 Vitis Run 后的固件 |
| PHY link_speed invalid | CONFIG_LINKSPEED1000 |
| 旋转丢 blur/sobel | 设计行为，见 ROTATION_AND_EFFECTS |
