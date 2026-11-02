# Vitis：建了 Platform 但 Application 里看不到

画面（左彩条 / 右灰度）已验证 OK。下面是 Application 找不到 platform 的排查。

## 正确顺序（Vitis 2025.2）

```
1. File → New → Platform Project
   - XSA: D:\Software\Xiaomi_MiMo\video\zynq_video_pipeline\output\system.xsa
   - 名称例如: zynq_plat
   - 勾选 Generate boot components（可选）
   - Finish 后等左下角 Build 全部结束（Platform 变成 ✓）

2. 确认 Platform 已生成
   - Explorer 里应有 zynq_plat
   - 展开应有 platform.spr / ps7_cortexa9_0 等

3. File → New → Application Project
   - Platform 页：下拉列表应有 zynq_plat
   - 若列表空：见下面「仍看不到」
```

## 仍看不到 Platform 时

| 检查 | 做法 |
|------|------|
| Platform 是否 Build 成功 | Explorer 右键 Platform → **Build Platform**；有红叉则失败 |
| 是否同一 Workspace | File → Switch Workspace，确认和建 Platform 时一致 |
| 是否关掉了 Platform 视图 | Application 向导里 Platform 下拉旁有时有 filter，改成 **All** |
| XSA 是否过期/损坏 | 重新 Export：Vivado `write_hw_platform` 或重新跑 `tcl\build_system.tcl` |
| 直接指定 XSA | Application 向导若允许 **Create a new platform from hardware (XSA)**，选同一 XSA 再建一次 |

## 最省事的做法

1. 关掉当前 Vitis  
2. 新建空 workspace，例如 `D:\vitis_ws_video`  
3. 只做一次：Platform ← `output\system.xsa` → Build  
4. 再 Application，选该 platform  
5. 源文件删掉 helloworld.c，加入：

```
D:\Software\Xiaomi_MiMo\video\zynq_video_pipeline\sw\ps\main.c
```

6. BSP：`xuartps`、`xgpio`  
7. Build → Run As → Launch Hardware  

## 若 system.xsa 有问题

用 Vivado 手工导出：

```bat
D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat
# GUI: 打开 vivado_system/zynq_video_sys.xpr
# File → Export → Export Hardware → Include bitstream → 输出 output/system.xsa
```

或批处理：

```tcl
open_project .../vivado_system/zynq_video_sys.xpr
open_run impl_1
write_hw_platform -fixed -include_bit -force -file output/system.xsa
```

## 下载 elf 后串口自测

```
00111   → 右半应变（模糊+边缘+反色）
FILL    → 左右变渐变（DDR 路径，需 PS+FCLK）
SRC0    → 回彩条
```
