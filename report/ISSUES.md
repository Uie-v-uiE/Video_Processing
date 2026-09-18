# 问题与修复记录（含第三版）

按主题整理；新增条目标注 **[v3]**。

---

## 网络 / 协议

### 1. EMIO GPIO 读回恒 0
改用 AXI GPIO `@0x41200000`。

### 2. ping 通但 UDP 不到
PC 双网卡默认路由走 WLAN → `socket.bind(("192.168.1.100",0))`。

### 3. PL 网口 ARP 不通
参考 `13_UDP_STACK` 的 RGMII/ARP；前导码 FSM 7+1；修复 arp_tx 多驱动。

### 4. ICMP ping 不通
载荷 FIFO 接错 + 启动过早 → 专用 `sync_fifo` + 延迟 20 拍。

### 5. UDP 乱序错位
包头加 `[u32 LE offset]`，按 offset 写 BRAM。

### 6. **[v3] CDC FIFO 地址切片错误**（历史）
`dout[35:17]` 应为 `dout[34:16]`；打包加 `1'b0` 对齐 36-bit。

---

## 显示 / 图像

### 7. HDMI 窄条 / 4 幅画面
AXI 64-bit 拆包；CDC 地址切片（见上）。

### 8. 行地址左移溢出
`(row+1)<<10` 位宽不足 → 全 32-bit 运算。

### 9. 0° 旁路导致流水线错位
angle=0 时 cx/cy 同样延迟 3 拍。

### 10. 旋转时窗滤花屏（旧）
目标域 3×3 重构后任意角可用 blur/sobel。

### 11. OSD 缺 F / 尾部多 0
补 A–F 字模；空格用空白字模，不用「0」。

### 12. 拖影
ETH 边收边写 BRAM；双缓冲资源不够 → 接受或后续消隐期写。

---

## **[v3] 缩放 / 数据通路**

### 13. 流式 bicubic 无法直接并入本工程
Algorithm 工程依赖 divider/行推流，与本工程 FB 随机读模型不同 → 采用 **逆映射 + 连续 inv_scale**。

### 14. 缩放方向
需求：**原始尺寸为最大** → `inv_scale` 256→512 循环（缩小再回原始），OOB 黑边。

### 15. **[v3] inv_scale=256 在 9-bit 有符号下为 −256**
映射全错 → `zoom_mapper` 内 `inv` 改为 **10-bit 有符号**。

### 16. **[v3] 效果挂载位置**
原 line_cache（左扫右读）废弃；效果改挂 **右窗缩放后光栅**，左窗保持原图。

### 17. **[v3] FB 单口左右冲突**
左右窗时分复用同一读口：`left_d[2]` 选择 rotate/zoom 地址。

---

## **[v3] 时序 / 约束 / FIFO**

### 18. eth_rxc→clk_pix 假违例（WNS≈−6.7）
XDC `set_clock_groups` 未含 MMCM 生成钟 →  
`-group [get_clocks -include_generated_clocks sys_clk]`。

### 19. **[v3] icmp FIFO 寄存器堆导致 125M 域违例**
存储带异步复位无法推断 BRAM → `sync_fifo`/`dc_fifo` **写阵列去掉复位** + `ram_style=block`。

### 20. **[v3] rd_addr 组合路径**
`sy*W+x` → `{sy[8:0],9'b0}+sx` 后 **打一拍** 再进 BRAM，sideband 同步加长。

### 21. 增量综合忽略新约束
删 `utils_1/imports/synth_1/*.dcp` 或 `reset_run synth_1`。

### 22. TCL root 少一级 `..`
脚本在 `build/tcl` 时应用 `join dirname .. ..`。

---

## PS / 上位机 / 工程

### 23. 串口无效
bit 后 PS 复位 → 必须再 Run ELF。

### 24. **[v3] bat 路径 `sw\host`**
实际为 `src\host`；Python 优先 PATH。

### 25. 构建脚本覆盖 system_top.v
TCL 只 `add_files`，不生成顶层。

### 26. **[v3] CMD 中 git 未知**
Git 在 `D:\Git\Git\bin`，未进 PATH → 用全路径或改环境变量。

---

## 快速对照

| 症状 | 优先检查 |
|------|----------|
| 无 HDMI | bit、线、1024×600 |
| ping 不通 | 是否 **PL 口**、ARP 表 |
| ping 通无视频 | 端口 5001、offset 协议、src 绑定 |
| 4 幅/窄条 | CDC 切片、AXI 拆包 |
| 右屏不缩放 | `zoom_en`、`zoom_ctrl` 参数、inv 范围 |
| 缩放坐标乱 | inv 位宽是否 10-bit 有符号 |
| 效果只在错误窗 | 效果是否挂在右窗 de |
| 时序 WNS 为负 | 时钟组是否含 clkout*；FIFO 是否 BRAM |
| 串口无效 | bit 后是否 Run ELF |
| git push 失败 | 网络/代理；git 是否在 PATH |
