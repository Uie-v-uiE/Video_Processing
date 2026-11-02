# Vitis 平台找不到 / 黑屏说明

## 「创建 Application 时找不到 platform」

必须先 **从 XSA 创建 Platform**，不能直接建 Application：

1. Vitis 菜单 **File → New → Platform Project...**
2. 选 `D:\Software\Xiaomi_MiMo\video\zynq_video_pipeline\output\system.xsa`
3. 名称如 `zynq_video_sys_platform`，Finish，等 Build 完
4. 再 **File → New → Application Project**
5. Platform 下拉里应出现刚建的 `zynq_video_sys_platform`
6. 源文件加入 `sw/ps/main.c`（替换自动生成的 helloworld.c）

若 XSA 过期：重新跑 `tcl/build_system.tcl` 或用 Vivado **File → Export → Export Hardware**。

## 「显示器全黑、中间一条蓝线」

原因：彩条原先写在 **axi_clk(FCLK)** 上，只下 bit、PS 未启动时 FCLK 不跑 → 帧缓冲全 0 → 黑；蓝线是分隔线仍在画。

**已修复**：彩条改为 **clk_pix 即时生成**，不依赖 FCLK/PS。

请重新生成并下载：

```bat
%VIVADO% -mode batch -source tcl\build_pl_full.tcl
%VIVADO% -mode batch -source tcl\program_board.tcl
```

（纯 PL demo 即可先看画面；system bit 同样受益。）

## 右半白底黑线 / 旋转后黑底白线

原因：OOB（旋转出界）像素先置 0 再走 invert → 黑变白。

**已修复**：OOB 在分屏前强制黑，不参与 invert。

## 分辨率

已改为 **1024×600**，像素时钟 **50 MHz**（规格 50.25MHz，误差 0.5% 一般可同步）：

| 项 | 值 |
|----|-----|
| H active/FP/Sync/BP | 1024 / 44 / 88 / 188 |
| V active/FP/Sync/BP | 600 / 3 / 6 / 16 |
| HSYNC / VSYNC | + / − |
| 源 | 512×300，竖直 2×，左右各 512 |
