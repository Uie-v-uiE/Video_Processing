# ILA 抓波形步骤（Vivado Hardware Manager）

## 产物

| 文件 | 路径 |
|------|------|
| Bitstream（含 ILA） | `<工程根目录>\fpga\vivado_proj\fence_demo.runs\impl_1\system_wrapper.bit` |
| XSA | `<工程根目录>\fpga\fence_demo_ila.xsa` |
| 软件源码 | `fpga/software/fence_eval.c`（GPIO 翻转，便于 ILA 看边沿） |

## 步骤

1. **关掉** Vitis 里所有 Run/Debug 会话（避免抢 JTAG）  
2. 打开 **Vivado** → **Open Hardware Manager**  
3. **Open Target → Auto Connect**  
4. **Program Device** → 选上面的 `system_wrapper.bit`  
5. Hardware Manager 应出现 **ILA (ila_0)** → 打开 **Dashboard**  
6. 设置触发：`probe0 == 1` 或 `probe0 != 0`（边沿）  
7. **Run Trigger**  
8. 在另一个终端用 xsct 下载运行程序：

```powershell
& "D:\Software\Vivado\2025.2.1\Vitis\bin\xsct.bat" "<工程根目录>\fpga\read_classic_mailbox.tcl"
```

   或先 `ps7_init` 再 `dow` 新版带 GPIO 的 ELF。

9. 程序会连续翻转 EMIO GPIO → ILA 捕获波形  
10. **Export** 波形截图，存 `out/board/ila_waveform.png`

## 编码（若 probe 宽度为 8）

- bit0：状态 0/1/2  
- bit2-3：场景号  

当前 bitstream 里 probe 为 **1 bit**（只看 GPIO bit0 翻转）：  
程序里 `gpio_blink()` 会大量产生边沿，**足够截图证明 PL 侧 ILA 在工作**。

## 与创意赛关系

- ILA 是**可视化加分**，不是算法核心  
- 答辩主线仍是误扣率 84%→11% + 邮箱 EVAL  
- 可说：「状态经 EMIO 进入 PL，ILA 实时采样，证明 PS/PL 数据通路」

## 常见问题

| 问题 | 处理 |
|------|------|
| 看不到 ILA | bitstream 必须是**含 ILA 的这一版** |
| JTAG 冲突 | 只留 Hardware Manager **或** xsct 一个 |
| 无边沿 | 确认程序在跑；触发改成立即触发再 Run |
| probe 只有 1 bit | 已知；用 blink 看跳变即可 |
