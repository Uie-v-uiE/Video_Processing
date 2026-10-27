# 上板验证详细手册（JTAG + 测试集注入）

> 目的：证明「与 PC **同源**的测试集可在边缘 SoC 批处理，产出**同口径** EVAL 指标」。  
> 不是：射频全链路、FPGA 跑分、灯语表演。

---

## 0. 你要准备的硬件

| 项 | 说明 |
|----|------|
| 板卡 | RK-ZYNQ7020-F+ |
| 供电 | 按板卡说明（常见 12V） |
| JTAG | 板载 USB-JTAG（FT2232）或外置下载器 |
| 串口 | USB-UART（原理图：PS MIO10/11） |
| 线 | USB 线 ≥2 根（JTAG + UART，可能共用 Type-C） |
| PC | 已装 Vivado/Vitis 2025.2.1（路径已用） |

上电检查：电源灯亮；设备管理器出现 USB Serial / FTDI。

---

## 1. 软件产物核对（下载前）

```powershell
# 必须存在
fpga\fence_demo.xsa
fpga\vitis\fence_eval\Debug\fence_eval.elf
fpga\software\fence_testset.h
out\board_data\pc_golden.csv
```

- ELF 内已链入 4 场景 × 121 历元测试集  
- 若改过测试集：先 `export_fenceset.py`，再重编 ELF

---

## 2. JTAG 下载与运行

### 方式 A：xsct 脚本

```powershell
& "D:\Software\Vivado\2025.2.1\Vitis\bin\xsct.bat" `
  "<工程根目录>\fpga\run_classic_ok.tcl"
```

脚本逻辑：`connect` → 选 A9#0 → `dow -force <elf>` → `con`。

### 方式 B：Vitis GUI

1. 打开 workspace：`<工程根目录>\fpga\vitis`  
2. 右键 `fence_eval` → Run → Launch on Hardware  
3. 选择 **JTAG**（不要 SD boot，除非你已做 BOOT.BIN）

### 下载成功标志

- xsct/Vitis 无 target 错误  
- 控制台出现 `Download Progress ... 100%`  
- CPU 进入 running  

---

## 3. 串口监视（主证据）

| 参数 | 值 |
|------|-----|
| 波特率 | **115200** |
| 数据位 | 8 |
| 校验 | None |
| 停止位 | 1 |
| 流控 | None |
| 工具 | PuTTY / MobaXterm / minicom / 串口助手 |

打开后复位或重新 `con`，应看到：

```text
=== Fence Testset EVAL (Zynq PS / JTAG) ===
scenes=4
EVAL,fence_clean,epochs=121,true_in=...,naive_ff=...,trusted_ff=...,hold=...,p95=...
EVAL,fence_urban_mp,epochs=121,...
EVAL,fence_mp_spoof,...
EVAL,fence_denial,...
EVAL,ALL,DONE
See out/board_data/pc_golden.csv for PC reference
```

**注意：**

- 不要开多个串口抢同一 COM  
- 乱码先查波特率/USB 驱动  
- 若只有横线/无输出：JTAG 是否 `con`、UART 线是否接到 PS UART 口  

---

## 4. 要记录什么（对照表模板）

复制到 `out/board/uart_eval.md`：

```markdown
# 板端 EVAL 记录

- 日期：
- 板卡序列/备注：
- ELF 版本/哈希（可选）：
- 串口 COM：

| 场景 | epochs | naive_ff | trusted_ff | hold | p95 |
|------|--------|----------|------------|------|-----|
| fence_clean | | | | | |
| fence_urban_mp | | | | | |
| fence_mp_spoof | | | | | |
| fence_denial | | | | | |

## 对照 pc_golden.csv

| 场景 | PC naive_ff | 板 naive_ff | Δ | PC trusted_ff | 板 trusted_ff | Δ |
|------|-------------|-------------|---|---------------|---------------|---|

## 结论
- [ ] 四场景均有 EVAL 行
- [ ] urban_mp：naive 明显高于 trusted
- [ ] 板与 PC 同数量级（允许实现差异）
- [ ] 已截图 uart_eval.png
```

### 必须截的图

| 文件名 | 内容 |
|--------|------|
| `out/board/01_jtag_targets.png` | xsct/Vitis 连接 target |
| `out/board/02_download.png` | 下载完成 |
| `out/board/03_uart_eval.png` | **完整 EVAL 文本** |
| `out/board/04_golden_compare.png` | CSV 对照表（可再截 PC） |
| （可选）`05_vivado_bd.png` | Block Design |
| （可选）`06_util.png` | 资源利用率 |

---

## 5. 通过 / 不通过判据

| 级别 | 条件 |
|------|------|
| **通过** | 4 行 EVAL + ALL,DONE；urban_mp 上 naive_ff ≫ trusted_ff；数量级接近 golden |
| 有条件通过 | 数字有偏差但趋势正确 → 记录 Δ，写「实现差异」 |
| 不通过 | 无输出 / 崩溃 / naive 与 trusted 反了 → 停，带 log 排查 |

允许偏差说明（可写进报告）：

- 浮点与迭代次数不同  
- 剔野阈值实现细节  
- 以 **PC 金标准** 为算法正确性依据；板端证明「可部署同逻辑」

---

## 6. 常见故障

| 现象 | 处理 |
|------|------|
| `No target` | 上电、JTAG 线、驱动（FTDI）、`connect` 后 `targets` |
| 下载后无串口 | 确认 UART 接的是 **PS UART1**，不是 PL；115200 |
| 输出卡在第一行 | 看门狗/异常；用 Vitis 打断点看 `eval_scene` |
| EVAL 全是 1e9/异常 | 检查 `fence_testset.h` 是否与 ELF 同版本 |
| 与 golden 差很多 | 导出脚本是否重跑、sat_pos 是否写入头文件 |
| 想重跑 | xsct `stop` 再 `dow` / GUI Restart |

---

## 7. 操作流水（一次完整验证 15 分钟）

1. 上电，插 JTAG + UART  
2. 打开串口 115200  
3. 运行 `download_run.tcl` 或 Vitis Run on HW  
4. 观察 EVAL 全文，**复制到** `uart_eval.md`  
5. 打开 `pc_golden.csv` 填对照 Δ  
6. 截图 01～04  
7. 勾选通过清单  
8. 报告 4.7 写：「已在 Zynq PS 完成同源测试集批评估，指标见附件」

---

## 8. 和创意赛叙事的关系

| 有上板 | 无上板 |
|--------|--------|
| 证明边缘可跑同规则 | **仍然合法参赛** |
| 附件多一组 EVAL 对照 | 报告写「验证平台为 PC；边缘载体为后续」 |
| 答辩加分 | 不丢核心分（核心是规则+指标） |

**切勿**在答辩把上板说成「方案成立的前提」。

---

## 9. 建议你个人记录的「学习点」（上板过程）

- Zynq PS 与 PL 分工  
- standalone vs Linux 启动差异  
- JTAG `dow` 与 SD `BOOT.BIN` 差异  
- xil_printf 与 `%f` 限制（本工程 EVAL 用浮点打印，若板卡 printf 异常可改整数缩放）  
- 为何链接要 `-lm`、`lscript.ld` 作用  

详见 `LEARNING_CHECKLIST.md` F 章。
