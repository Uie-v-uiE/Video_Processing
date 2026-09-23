# Skill：绕开 IDE 手工链接裸机 ARM 应用时，必须把"标准启动"整条链请回来

> 一句话：**改入口符号不是改一行名字，是在改启动链。** `ENTRY(_vector_table)` → `ENTRY(_start)`
> 这一行"看起来只是修 bug"的改动，会把向量表、各模式栈、CPACR/FPEXC、VBAR、MMU 与 L2 一起带走，
> 而且它带走的是一批**只会以"奇怪现象"出现**的东西，不会以"链接错误"出现。

## 一、适用场景

- 你在**不用 IDE** 的条件下产出裸机镜像（本仓库：`node build/ps_app.mjs` 直接调
  `arm-none-eabi-gcc` + BSP 的 `libxil*.a`，因为交付要求"从零可复现"，而"在 Vitis 里点 New
  Platform/Application"不是可复现步骤）。
- 链接脚本是从 FSBL/示例抄来的，里面出现过 `ENTRY(_vector_table)`、`*(.vectors)`、`*(.boot)`、
  `.mmu_tbl`、`__abort_stack`/`__undef_stack` 这一类符号 —— **看到这些名字就意味着脚本预期有人链
  `boot.S`/`asm_vectors.S`/`translation_table.S`**；它们没在镜像里，就是缺件。
- 症状长得"互不相干"：浮点指令陷 Undefined、板子"像自己重启了一遍"、`memcpy` 发对齐异常、
  一按复位就好了、MMU 关着才有的怪事。

## 二、使用方法（按这个顺序查，别按症状查）

1. **先问镜像里有没有标准启动**，三条命令就够（本仓库都写在 `build/ps_app.mjs` 的自检里）：

   ```bash
   arm-none-eabi-nm -n ps_app.elf | grep -E "_boot|_vector_table|MMUTable|_start|IRQHandler"
   arm-none-eabi-readelf -h ps_app.elf | grep Entry          # 必须等于 _boot
   arm-none-eabi-objdump -d --start-address=0 --stop-address=0x20 ps_app.elf
   #   0x0 必须是 b _boot，0x4/0x10 必须是 Undefined/DataAbortHandler —— 不是就是没链进来
   ```

2. **缺了就显式把三个 `.S` 编进来**（不是 `-Wl,-u`，也不是 KEEP —— 让它们成为"入口的下游"最干净）：

   ```js
   const BSP_ASM = ['asm_vectors.S', 'boot.S', 'translation_table.S'];   // 路径：
   // <BSP>/libsrc/standalone/src/arm/cortexa9/gcc/     编译开关必须与 BSP 自己一致（这里 -DSDT）
   ```

   然后入口写回链接脚本：`ENTRY(_boot)`。**不要用命令行 `-e`**：`-Wl,-e,_boot` 会被脚本里的
   `ENTRY()` 顶掉，`readelf` 的入口悄悄变成 `0x0`（＝`.text` 起始）而**一声不响** —— 这就是本条
   要记的第一课：链接器的"入口"有两个来源，覆盖关系不报错。

3. **加两道等值哨兵，而不是存在性哨兵**。只查"`_boot` 在不在符号表里"是不够的，因为真正会坏的是
   "从哪里开始跑"和"向量表在不在 CPU 会去找的地址上"：

   ```js
   if (entry !== sym('_boot')) die();      // ELF 入口必须 = _boot
   if (sym('_vector_table') !== 0) die();  // VBAR 复位值就是 0，表放别处等于没有表
   ```

   这两道哨兵是**当晚逼出来的**：我先把入口设成自己写的 `app_entry`，`--gc-sections` 把没人引用的
   `.vectors` 整段裁掉，`readelf` 显示入口 = 0x0 而 `nm` 显示 `app_vectors` 也在 0x0 ——
   看起来"全对"，实际上向量表根本不在镜像里（判据自己也得有测试：那条正则
   `Entry point address:\s+0*([0-9a-f]+)` 遇到 `0xcc` 会把 `0` 吃掉、捕获到空 ⇒ 永远读成 0）。

4. **别在 0x0 摆自己的代码**。任何"入口 + 向量区"的重写（比如只补一条 `MCR CPACR` 的土办法桩）都会
   落在 0x0–0x1C 上；`V=0` 时那正是异常向量，于是**每一次异常都变成一次看起来很干净的重启**。
   本仓库真的这样演过一次：发 `SD` 挂载回来的是整条 `[BOOT]` 横幅，我一度以为是板子复位。

5. 顺手一条同类约束：**MMU 关着时非对齐访问一定 fault**（`SCTLR.A=0` 的豁免只在 MMU 开着时成立）。
   标准启动回来之后 MMU 由 BSP 的恒等映射打开（DDR 可缓存、`0x4000_0000–0x7FFF_FFFF` 是
   device/uncached ⇒ PL 寄存器读写不绕过缓存）。若你选择不链标准启动，就得自己承担
   `-mno-unaligned-access` + 预编译库里 `memcpy` 半字快路径这一类雷。

## 三、已验证效果（2026-09-23，Zynq-7020，同一块板同一张卡，全部实测）

| 阶段 | 现象 |
|---|---|
| 只补 CPACR（土桩） | 串口出 `[BOOT]`，但发 `SD` 回来的是**整条横幅**（异常→0x0→桩→`b _start`） |
| 桩占了向量区 + MMU 仍关 | 挂载 data abort：`dfsr=0x801`（非对齐读）、出错指令在 `memcpy` 的半字路径里 |
| 请回标准启动（三个 `.S` + `ENTRY(_boot)`） | `PC_BEFORE_CON=0x0`、`cpsr` 模式 0x13/0x1f、串口 `[BOOT]`+`STAT` 正常；<br>`SD` 一次挂上：`FAT32 part_lba=2048 spc=32 … frames=4398 files=5`；<br>回放 46 个"100 帧窗口"全 `29.999 fps`，另一路 `STOP` 360 帧 ÷ 12 s = 30.0 fps |
| 同一张卡、同一个 elf、只 `rst -processor`+重下 | 挂载**每次**成功；不重下则第二次 `XSdPs_CfgInitialize` 必失败（那是另一笔账，ISSUES #45） |

净收益：PS 应用从"只能靠 FSBL/Vitis 才能跑"变成"纯 JTAG 就能跑"，P1（SD 本地回放）的
数据侧第一次拿到可核对的数字。

## 四、失效条件 / 不适用

- **平台库不是 SDT 流程生成的**：`boot.S` 里 `#include "bspconfig.h"` 依赖 `-DSDT` 与
  `xmem_config.h`；换成老 EDK 或改了编译开关，恒等映射/ errata 分支会不一致。
- **`USE_AMP`/多核**：`boot.S` 的 `_boot` 会按 CPU 亲和号决定谁往下跑，并在单核 efuse 上
  复位 CPU1；AMP 工程里这段要另配，不能照抄。
- **想要"跑在 DDR 里"**：`translation_table.S` 的 DDR 段属性来自 `xparameters` 里的
  `XPAR_PS7_DDR_*`；地址或容量与实机不符时，开 MMU 后第一笔访存就炸（表现为"一个字节都没打出来"，
  比缺启动更难查）。本仓库跑在 OCM（0x0，192 KB），这条没踩到，属于**未验证**。
- **不要顺手把 `Xil_ExceptionInit/Enable` 当成"异常已接管"**：standalone 的默认 handler 是在
  **库里**用 `xdbg_*` 打印的，库没开 `DEBUG` 就只剩 `while(1)`；所以现场可读的是
  `DataAbortAddr`/`PrefetchAbortAddr`/`UndefinedExceptionAddr` 三个全局（本仓库
  `board/pswhy.tcl` 就是采这个 + pc/cpsr）。想看到打印，得自己注册 handler，或者把这条写成
  "崩溃后 JTAG 读三个全局"的操作规程 —— 别声称"handler 会打印"。
