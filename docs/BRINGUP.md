# 上板验证清单（明天）

## 1. 硬件连接
- [ ] 12V 电源
- [ ] HDMI 线到显示器（建议支持 720p）
- [ ] USB-TYPEC（FT2232：JTAG + UART）
- [ ] PS 网口连接到 PC 网卡/路由器（同一网段）
- [ ] 拨码：JTAG / QSPI 按需（调试用 JTAG 启动即可）

## 2. 工具
- Vivado 2025.2.1：`D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat`
- Vitis 2025.2.1：`D:\Software\Vivado\2025.2.1\Vitis\bin\vitis.bat`

## 3. 一键建工程 + 比特流
```bat
cd /d D:\Software\Xiaomi_MiMo\video\zynq_video_pipeline
D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat -mode batch -source tcl\create_project.tcl
D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat -mode batch -source tcl\build_bitstream.tcl
```

## 4. 纯 PL 自测（不依赖 PS 软件，先看 HDMI）
1. 下载 bit：`tcl/program_board.tcl`
2. 上电，HDMI 应显示：
   - 左：彩条
   - 右：彩条经流水线（默认 en=00000 时应与左几乎相同）
3. 按 KEY1：旋转 0→90→180→270→0
4. PL_LED1 闪烁表示 timing 在跑

> 若无 PS elf，系统内置 `src_sel=0` 彩条模式，可完成 HDMI/按键/效果链路验证。

## 5. PS + 以太网路径
1. Vitis 建 platform（XSA 来自 build）并编译 `sw/ps`
2. 下载 elf（JTAG）或做成 boot.bin
3. 串口 115200，应看到 `[BOOT] eth up, ip=...`
4. PC 侧：
```bat
python sw\host\serial_ctrl.py --port COMx
python sw\host\video_sender.py --ip 192.168.1.10 --image assets\test_pattern.png
```
5. 串口发送 `00111` 观察右半屏：模糊+边缘+反色
6. 发送 `10000` 仅灰度；`00000` 恢复原图

## 6. 常见问题
| 现象 | 处理 |
|------|------|
| HDMI 无显示 | 查 HPD(Y18)、线材、显示器是否 720p；看 LED 是否闪 |
| 仅左有图 | 效果全关时右=左，正常；发 `11111` 应明显变化 |
| 以太网不通 | PC 关防火墙；`ping` 板 IP；确认 DHCP/静态一致 |
| 串口无回显 | 波特率 115200；确认 COM 是 FT2232 Channel A |
| 画面撕裂 | DDR 帧基址/缓存一致性：确保 PS 写后 `Xil_DCacheFlush` |
