# build/micro_rd —— 帧缓存读口的**布线探针**（不是交付件，也不当门禁）

## 它回答什么问题
双线性要把帧缓存的读口挪到 250 MHz（每像素周期发 4~5 次读）。2026-09-23 那三次红
（build#14 −1.277 / #15 −0.485 / #16 −0.327，见 tag `v7.8-bilinear-wip` 与 `docs/log/OVERNIGHT_LOG.md` R18/R19）
都红在同一条路：**地址 mux → RAMB36 地址脚**，而且报告说 84.7% 是布线 ⇒ 这是**布局**问题，
`build/tcl/ooc_newmods.tcl` 那种综合级 OOC 量不出来（它自己就写着"这里的数字不是门禁"），
必须真实 place+route。全流程一次 30+ 分钟，所以把这一条路单独 place+route。

## 跑法（一次一个 MODE；不要并行跑两个 vivado，内存只有 ~2.7 GB 空余）
```sh
MODE=1 "D:/Software/Vivado/2025.2.1/Vivado/bin/vivado.bat" -mode batch -nojournal \
     -log build/micro_rd/r2_m1.log -source build/tcl/micro_rd.tcl
```
三个 MODE 是**同一份骨架只差 mux 与地址寄存**（`micro_fb_rd.v` 头部写着差别）：
0=旧形状（5 选 1，左窗那一路慢域直线直进 mux）1=新形状（4 选 1，输入全是快域触发器）2=新形状+地址前一级寄存。

## 第二轮（`r2_m*.log` → 摘录在提交物里的是 **`verdict.txt`**，因为 `*.log` 被 `.gitignore` 挡着）
复现命令在本文件上面；`verdict.txt` 里每个 MODE 都带 `WNS/TNS/失败端点` 那一行与最差违例路径的起止 cell，
足够核对下面这张表（对不上就是有人改了探针却没更新这里）。
| MODE | 全设计 WNS | 失败端点 | 那几条路是什么 |
|---|---|---|---|
| 0 | −0.497 | 156 | **`u_fb/*/CLKBWRCLK → acc_q_reg/D`** ⇒ 还是探针自己的 sink（见下） |
| 1 | −0.064 | 4 | `b1_q_reg/a1_q_reg → u_fb/*/ADDRBWRADDR[n]` ⇒ **就是 mux→地址脚这一条** |
| 2 | −0.011 | 1 | `u_fb/lo_reg_0_17/CLKBWRCLK → w_b_reg[46]/D`，1 级 LUT3、"逻辑"占 2.240 ns ⇒ **RAMB36 自身的 clk→out** |

所以这一轮**只允许下这两个结论**：
1. 新几何（少掉左窗那一路、mux 输入全是快域触发器）把 mux→地址脚从"红"推到 **−0.064 ns / 4 个端点**；
   再加一级地址寄存之后，**这一条不再违例**（MODE 2 的 1 个失败端点不在地址路上）。
2. 但 250 MHz 读口的**另一头**（BRAM clk→out 到快域采集）在裸探针里就只剩 0.011 ns ⇒
   这条路即使走通也是**贴着器件下限**，全设计的拥挤度只会更差。
   ⇒ 与 `docs/log/ISSUES.md` #76 段二一致：**该走的是"每源像素 4 个 50 MHz 拍"那条路**，它根本不碰 250 MHz。

MODE 0 的数字**不能**当成"旧形状的地址路"：两轮里全设计 WNS 都被探针的 sink 占了
（第一轮是 32 位加法树，第二轮是 64 位异或折叠）。想看旧形状那条路的真实数字，得用
`report_timing -to [get_pins -hier -filter {NAME =~ *ADDRBWRADDR* || NAME =~ *ADDRARDADDR*}]`
单独点名列 —— 探针脚本末尾已经写了这一段，但**RAMB36 的读地址脚在这个映射下叫 ARDBWRADDR**，
只过 `ADDRARDADDR` 会得到 0 个引脚（第一轮就是这么空手而归的）。

## 这条探针的判据（下一轮改法之前先钉住）
1. **先确认最差路径是不是我要问的那一条**：读 `r2_m*.log` 的 `Source/Destination`，
   只要最差端点不指向 `*ADDR*`，这一轮的 WNS 就不作数。
2. sink 不许有算术：每个抽头各存各的触发器，需要吃掉就把**单个 bit** 直接连到输出脚，
   不要折叠、不要相加（"探针也要有自己的判据"这句写在 `micro_fb_rd.v` 文件头）。
4. **BRAM 数量要当场对**：`util_m*.rpt` 里这份探针的 `Block RAM Tile` 实测 **21**，而真实设计里
   `u_fb`(`frame_buffer_w64`) 是 **80 个 RAMB36**（`build/util_hier.rpt`）。⇒ **探针低估了地址扇出**，
   它的绝对数字只比真实设计**乐观**、不会更差；所以 MODE 1 的 −0.064 在真设计里更可能仍是红，
   这一层在读结论的时候必须带着（见 `docs/log/ISSUES.md` #76 段三与事实 3）。
   为什么探针只有 21：探针里读写地址的可达范围让工具把 `lo/hi` 对阵列裁小了 —— 这一条**没查到底**，
   要它变成可用的对照组，得让探针的 BRAM 数也落在 80（下一轮如果想让数字可比，这是第一个要修的）。
