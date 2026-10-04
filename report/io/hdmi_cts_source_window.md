# HDMI **源端（Source / TP1）** 时序量：可公开引用的原始出处与本工程的约束用法

核查日期：2026-10-04（本文所有"核对日期"均为该日）。
核查方式：把候选 PDF 全部下载到本地，用 `pdftotext -layout` 与 `pypdf` 两种独立抽取器取文，再对同一数字要求**至少两份独立文档**命中；只有一份命中的，在"判定"列降级标注。
本轮**没有改动任何代码或约束文件**。

> 先说结论的诚实边界：**HDMI CTS（Compliance Test Specification）本身不公开**，它挂在 HDMI Adopter Extranet 上（见第四节原文引用）。
> 但是——**源端 TP1 的这些时序量并不是只存在于 CTS 里**：它们同时印在 HDMI 规范本体的 **§4.2.4 "HDMI Source TMDS Characteristics" / Table 4-24 "Source AC Characteristics at TP1" / Figure 4-30 "Eye Diagram Mask at TP1 for Source Requirements"**，而 HDMI 1.1 / 1.3 / 1.4 三份规范都有公开可取的镜像 PDF；Keysight 与 Tektronix 两份公开的仪器文档又**逐句复述了 CTS 的源端测试项与限值句**。
> 所以本轮的收获是：前一次"UG471 第 95 页只有电气属性、查不到窗"的判断是对的（那是 I/O standard 的 DC 属性，不是时序窗），但"**查不到**"是错的——**查得到，而且查到了三份规范 + 两份仪器文档互相印证**。

---

## 一、结论表

约定：`Tbit` = TMDS 位周期；`Tcharacter` = 一个 10/8b/10b 字符周期 = 像素周期（HDMI 1.x 在 TMDS 钟 = 像素钟的模式下）；`TP1` = 源端 HDMI 插座连接点。
出处里的 URL 就是**我这次实际取到内容的那一个**（镜像站，非 HDMI 官方发布页；该镜像 PDF 页脚自标 `Confidential`，见第四节）。

| # | 量（名称） | 数值 + 单位 | 适用 TMDS 速率 | 出处（文档 + 章节/表号 + URL + 核对日期 2026-10-04） | 判定 |
|---|---|---|---|---|---|
| 1 | **TMDS 钟–数据 / 数据–数据 互对偏斜**（Source inter-pair skew at TP1，max） | **0.20 `Tcharacter`**（= 0.20 × 像素周期 = 20% UI×10；50 MHz→4.000 ns；74.25 MHz→2.6936 ns） | HDMI 1.x 全部（25–340 MHz 像素钟 = 0.25–3.4 Gbps） | ①《HDMI Specification Version 1.4》§4.2.4 **Table 4-24 "Source AC Characteristics at TP1"** 行 `Inter-Pair Skew at Source Connector, max | 0.20 T character`，[镜像 PDF](https://file-host.wiki-power.com/circuit-design/%E8%AE%BE%E8%AE%A1%E8%A7%84%E8%8C%83/%E5%90%84%E7%B1%BB%E9%80%9A%E4%BF%A1%E4%B8%8E%E6%8E%A5%E5%8F%A3%E5%8D%8F%E8%AE%AE%E6%A0%87%E5%87%86/HDMI1.4%E6%A0%87%E5%87%86.pdf) 第 59 页（PDF 第 74 页）②《HDMI 1.3》**Table 4-16**，[MIT 镜像](https://fpga.mit.edu/6205/_static/F23/common_files/week04/CEC_HDMI_Specification.pdf) 第 43 页 ③《HDMI 1.1》**Table 4-13** 写作 `0.20 T pixel`，[dianyuan 镜像](https://u.dianyuan.com/bbs/u/37/1137460350.pdf) 第 34 页 ④Keysight《D9021HDMC HDMI HEAC Compliance Application Programmer's Reference》§3 Table 4，测试项 `7-6: Inter-Pair Skew - D0/Clock … Inter-pair skew must not exceed 0.20*Tpixel. The Source shall meet the AC specifications in Table 4-13…`，[PDF](https://www.keysight.com/bf/en/assets/9924-01437/programming-guides/D9021HDMC-HDMI-Test-Software-Remote-Prog-Ref-2-40-2024-0.pdf) 第 46 页 ⑤Tektronix 应用笔记 `…skew between clock and any of the data pairs are within limits. The standard prescribes a limit on skew not to exceed 20% of the pixel-time (TPIXEL).`，[页面](https://www.tek.com/en/documents/application-note/physical-layer-compliance-testing-hdmi-using-tdsht3-hdmi-compliance-test-s) | **公开规范原文**（三版规范一致）＋ **CTS 测试项的第三方逐句复述**（Keysight/Tektronix）。这是**唯一可直接当作"钟↔数据对齐窗"**引用的量 |
| 2 | **对内偏斜**（Source intra-pair skew at TP1，max，P 与 N 之间） | **0.15 `Tbit`**（50 MHz→0.300 ns；74.25 MHz→0.202 ns） | 同上；CTS 侧标注 **Frequency > 165 MHz** 时才按 0.15 `Tbit` 判 | ①HDMI 1.4 Table 4-24 `Intra-Pair Skew at Source Connector, max | 0.15 T bit`（第 59 页）②HDMI 1.3 Table 4-16（第 43 页）③HDMI 1.1 Table 4-13（第 34 页）④Keysight `7-7: Intra-Pair Skew - Clock 600 Frequency > 165 MHz : Intra-Pair Skew must not exceed 0.15*Tbit.`（第 46 页）⑤Tektronix `the standards specify a limit of 15% of the bit time (TBIT)`⑥Diodes 公开实测报告行 `HF1-4: Intra-Pair Skew - Data Lane 2 … Pass Limits: -150 mTbit <= VALUE <= 150 mTbit`，[PDF](https://www.diodes.com/assets/Part-Support-Files/PI3HDX1204B1/PI3HDX1204B1_App_HDMI2.0-CTS2.0-compliance-test-report.pdf) 第 2/14/17 页 | **公开规范原文**＋**公开实测报告里的 CTS Pass Limits 行**（±150 mTbit 与 0.15 Tbit 同值） |
| 3 | **数据上升/下降时间**（20%–80% 定义，TP1） | **75 ps ≤ rise/fall ≤ 0.4 `Tbit`**（下界固定；上界 50 MHz→0.800 ns，74.25 MHz→0.5387 ns，165 MHz→0.2424 ns） | 0.25–3.4 Gbps（≥187.5 Mbps 时 0.4Tbit 才大于 75 ps，下界才不起反） | ①HDMI 1.1 Table 4-13 原文行：`Rise time / fall time (20%-80%) | 75psec ≤ Rise time / fall time ≤ 0.4 Tbit`（第 34 页）②HDMI 1.3 Table 4-16 **同一行逐字相同**（第 43 页）③HDMI 1.4 Table 4-24 该行**只印了下界**：`75psec ≤ Rise time / fall time`（第 59 页；上界在该镜像该格中未出现——我没有把它当成 1.4 删掉了，因为④⑤都还在）④Tektronix：`The CTS specifies the rise or fall times should be higher than 75 ps and lower than 0.4 * TBIT value.`⑤Keysight 测试项 `7-4: Clock Rise Time 200 … The transition time is defined as the time interval between the normalized 20% and 80% amplitude levels. For compliance, the DUT should output the highest supported pixel clock frequency during the test.`⑥旁证：Tektronix `At 165 MHz clock rate, the rise times can be between 75 ps to 250 ps.`（我按 0.4×Tbit 在 165 MHz 算得 242.4 ps，与"250 ps"吻合，说明公式读法正确） | 下界＝**公开规范原文**；上界＝**公开规范原文（1.1/1.3 逐字）＋ 第三方复述**，在 1.4 镜像该格只读到下界，故**上界按 1.3 原文 + Tektronix 复述引用**，不写成"1.4 Table 4-24 明写" |
| 4 | **TMDS 钟抖动**（Differential Clock Jitter，max，TP1，相对 Ideal Recovery Clock） | **0.25 `Tbit`**（50 MHz→0.500 ns；74.25 MHz→0.3367 ns；3.4 Gbps→73.5 ps） | ≤340 MHz 像素钟（≤3.4 Gbps） | ①HDMI 1.4 Table 4-24 `TMDS Differential Clock Jitter, max | 0.25 T bit (relative to Ideal Recovery Clock as defined in Section 4.2.3)`②HDMI 1.3 Table 4-16、HDMI 1.1 Table 4-13 同值同注③Keysight `7-9: Clock Jitter 12 … TMDS differential clock jitter must not exceed 0.25*Tbit, relative to the ideal Recovery Clock. For compliance, the DUT should output 27MHz(or 25MHz), 74.25MHz, 148.5MHz, and 222.75MHz for testing.`（第 47 页）④Tektronix `The measured jitter should be less than 0.25*TBIT for compliance.` | **公开规范原文**＋CTS 测试项逐句复述。**74.25 MHz 被点名是测试频点之一** |
| 5 | **TMDS 钟占空比**（min / average / max） | **40% / 50% / 60%** | 全速率（规范表未按速率分档） | ①HDMI 1.4 Table 4-24 `Clock duty cycle, min / average / max | 40% / 50% / 60%`②HDMI 1.3 / 1.1 同③Keysight `7-8: Clock Duty Cycle(Maximum) 502 … Clock duty cycle must be at least 40% and not more than 60%.`④Tektronix `The CTS defines the margin to be +10% from the nominal 50% duty cycle. Thus, the TDUTY measured should fall within 40% and 60%.`⑤Diodes 报告行 `HF1-6: Clock Duty Cycle(Minimum) … >=40%` / `(Maximum) … <=60%` | **公开规范原文**＋实测报告 Pass Limits 行 |
| 6 | **源端眼图掩码 @TP1（HDMI 1.4 版）** | 禁入区：归一化时间 **0.25–0.75 UI**（宽 0.5 UI）、差分幅度 **−200…+200 mV**；绝对上下限 **±780 mV** | 时间轴"normalized to the bit time at the operating frequency"，故宽度按 UI 折算与速率无关；50 MHz→±0.500 ns，74.25 MHz→±0.3367 ns（半宽 0.25 UI） | HDMI 1.4 §4.2.4 **Figure 4-30 "Eye Diagram Mask at TP1 for Source Requirements"**，坐标标注原文：`Absolute Differential Amplitude (mV) 780 / 200 / 0 / -200 / -780`、`0.0 0.15 0.25 0.75 0.85 1.0 Normalized Time`（镜像第 59 页）；配套正文：`This requirement specifies the minimum eye opening as well as the absolute maximum and minimum voltages. The time axis is normalized to the bit time at the operating frequency.` 与 `Overshoot limits are imposed only by the absolute max/min voltages of ±780mV…` | **公开规范原文（图形坐标读数）**。⚠️"宽 0.5 UI = 0.75−0.25"是我对坐标的算术，**不是原文句子**；CTS 实际加载的掩码文件几何（Keysight 配置项 `MaskFile = HDMI-TP1.msk`）**未公开**，故掩码的逐顶点坐标=**无法公开引用** |
| 7 | **源端眼图掩码 @TP1（HDMI 1.1 / 1.3 旧版，归一化幅度）** | 禁入区时间 **0.31666…–0.68333… UI**（宽 0.36667 UI）；幅度 **±0.25**（归一化到平均差分摆幅，逻辑电平在 ±0.50，过冲/欠冲界 ±0.65）；1.3 另加绝对 ±780 mV | 同上（时间轴归一化到位周期） | ①HDMI 1.1 **Figure 4-12 "Normalized Eye Diagram Mask at TP1 for Source Requirements"** 坐标 `0.0 0.15 0.31666... 0.68333... 0.85 1.0` / `0.25 0.50 0.65 -0.25 -0.50 -0.65 Normalized Differential Amplitude`（镜像第 35 页）②HDMI 1.3 **Figure 4-18 "Eye Diagram Mask at TP1 for Source Requirements"** 坐标同上并把绝对界标成 `780mV / -780mV`（镜像第 44 页） | **公开规范原文（图形坐标读数）**；同上，宽度 0.36667 UI 是我做的减法 |
| 8 | **眼最小垂直开度 @TP1** | **400 mV**（差分最小开度） | 全速率 | HDMI 1.4 §4.2.4 正文逐字：`Minimum opening at Source = Vhigh (min) - Vlow (min) = 400 mV`（第 59 页）；旁证 Keysight/Diodes：`…the differential voltage swing at TP1 must be > 400mV and < 1200mV.`（测试项 `HF1-7`） | **公开规范原文** |
| 9 | **单端输出摆幅 / 电平（DC，非时序）** | `400mVolts ≤ Vswing ≤ 600mVolts`（单端）；`VL = (AVcc−600mV)…(AVcc−400mV)`（≤165 MHz 档）；`VOFF = AVcc ±10mVolts` | ≤165 MHz 档与 >165 MHz 档不同（1.4 Table 4-23 分两档） | HDMI 1.4 **Table 4-23 "Source DC Characteristics at TP1"**（第 58 页）；HDMI 1.3 Table 4-15、HDMI 1.1 Table 4-12；Tektronix `The CTS specifies that the voltage of the low-levels should fall within 2.7 V and 2.9 V.`；Diodes 报告 `HF1-1: VL D2- … 2.300 V <= VALUE <= 2.900 V` | **公开规范原文**（电气量，与 UG471 那类 I/O standard 属性同类用途，**不能当时序窗**） |
| 10 | **过冲 / 欠冲** | overshoot **15%**、undershoot **25%** of full differential amplitude | 全速率（按摆幅百分比） | HDMI 1.1 Table 4-13 两行原文 `Overshoot, max 15% of full differential amplitude (V swing/2)` / `Undershoot, max 25% …`；HDMI 1.3 Table 4-16 `Undershoot, max 25% of full differential amplitude`；HDMI 1.4 移到正文（`…allow 25% … maximum undershoot…`）；Tektronix `The CTS standard defines the limit for overshoot as 15% and undershoot as 25% of the entire steady-state voltage swing.` | **公开规范原文**＋第三方复述 |
| 11 | **抖动的参考基准 = Ideal Recovery Clock**（决定"钟–数据对齐"到底怎么量） | 一阶低通，**20 dB/decade 滚降，−3 dB 点 = 4 MHz**（`F0 = 4.0 MHz`） | 全速率 | HDMI 1.4 §4.2.3.1 "Jitter and Eye Measurements: Ideal Recovery Clock" 原文：`All TMDS Clock and Data signal jitter specifications are specified relative to an Ideal Recovery Clock defined below. The Data jitter is not specified numerically, but instead, an HDMI device or cable shall adhere to the appropriate eye diagram(s)…` 与 `…a low pass filter with 20dB/decade roll-off and with a −3dB point of 4MHz.` / `Equation 4-1 Jitter Transfer Function of Ideal CRU…`（第 55 页） | **公开规范原文** |
| 12 | **数据抖动有没有独立数值？** | **没有。**规范只说"数据抖动不单独给数，改用眼图掩码约束" | — | 同上 HDMI 1.4 §4.2.3.1 那句 `The Data jitter is not specified numerically…` | **公开规范原文（否定式结论）** |
| 13 | **"钟到数据"是否有独立的 setup/hold 窗？** | **没有独立参数名**。钟↔数据的关系只通过 ①互对偏斜 0.20 `Tcharacter` ②眼掩码 间接给出 | — | HDMI 1.3 第 45 页逐字：`Source eye diagram test procedures are defined in the HDMI Compliance Test Specification. The Source eye diagram mask of Figure 4-18 is not used for response time and clock jitter specifications, but specifies the clock to data jitter indirectly.` | **公开规范原文（否定式结论）**——这条直接回答了"找 HDMI 规范里的 clock-to-data 窗"这个问题：**它不存在为一个数** |
| 14 | **抖动/眼测试的采集要求**（影响我们声称"满足窗"时的可信度） | 眼图至少累计 **400,000 UI**；占空比/电平类至少 **10,000** 条波形；示波器最短记录长度 **16 M** | 全速率 | Tektronix 应用笔记原文：`the CTS specifies a minimum oscilloscope record length to acquire the data signal. This ensures that at least 400,000 unit intervals (or TBIT) are accumulated for building the eye diagram.` / `As per CTS, minimum 10,000-triggered waveforms are required for test purposes.` / `The eye-diagram and clock jitter tests require a minimum of 16 Meg record length.` | **第三方实测代理**（CTS 复述，非 CTS 表） |
| 15 | **CTS 版本间的差异（同一量、不同限值）** | 钟抖动：≤340 MHz 档 **0.25 Tbit**；HDMI 2.0（CTS 2.0）档 **0.3 Tbit**；>340 MHz 档 **0.27 Tbit**。互对偏斜：CTS 1.4a/1.3c **不再要求**做钟–数据互对偏斜与最大 rise/fall，CTS 1.2a 才要求 | 0.25 / 0.3 / 0.27 分档 | ①Diodes 报告 `HF1-7: Clock Jitter … must not exceed 0.3*Tbit`、`Pass Limits: <= 300 mTbit`②Keysight `1-6: Clock Jitter … must not exceed 0.27*Tbit … the DUT should output > 340MHz for testing.`③Tektronix `This test is not required as per CTS 1.3c but is needed if tested as per CTS 1.2a.`（钟–数据互对偏斜）与 `The maximum rise and fall time is not required to be performed as per CTS 1.4a. However if the devices are tested as per CTS 1.2a then this is required.` | **第三方实测/仪器文档**（**这就是 CTS 逐版本表不公开的后果**：我只能引用别人复述的分档，不能引用 CTS 原表） |
| 16 | **线缆侧（非源端）互对/对内偏斜预算**（做端到端余量时要用，别和源端混） | Category 1（74.25 MHz）：intra **151 psec**、inter **2.42 nsec**；Category 2（>74.25 MHz）：intra **111 psec**、inter **1.78 nsec** | 分两档，以 74.25 MHz 为界 | HDMI 1.3 **Table 4-21 "Cable Assembly TMDS Parameters"**（镜像第 49 页）；Keysight `Cable Inter-Pair Skew 86 Cable Assembly Inter-Pair Skew should be no more than 2.42ns.`；HDMI 1.4 Table 4-29/4-30（第 64/66 页，同族） | **公开规范原文**（线缆规范，不是 TP1 源端量） |
| 17 | **接收端（TP2）量——本轮明确不用** | Sink max intra-pair skew：`≤225 MHz → 0.4 Tbit`；`>225 MHz → 0.15 Tbit + 111 psecs`；inter-pair `0.2 T character + 1.78 nsecs`；Sink TMDS Clock Jitter `0.30 Tbit` | 分档 | HDMI 1.3 **Table 4-19 "Sink AC Input Characteristics at TP2"**（镜像第 46 页） | **公开规范原文**——但**这正是前一次误用/本次排除掉的那一侧**，写在这里只为防止再被拿来当输出窗 |
| 18 | LED（`led[0]` / `led[1]`）的对外时序窗 | **不存在** | — | HDMI 1.4 §4.2 Table 4-2/4-5 连接器引脚表里只有 `TMDS Data0/1/2 ±`、`TMDS Clock ±`、DDC、+5V、HPD、CEC——**没有 LED 这类指示脚**；本工程原理图/用户手册也没有"谁在采样这颗 LED"的条款 | **无法公开引用（因为该要求在业界不存在）** |

### 1.1 由第 1 节公式代入的速率折算表（**本节是算术，不是任何文档里的原表**）

公式全部来自表行：`intra = 0.15×Tbit`、`inter(含钟↔数据) = 0.20×Tcharacter`、`rise/fall ≤ 0.4×Tbit`（下界 75 ps 固定）、`jitter ≤ 0.25×Tbit`。
在 HDMI 1.x 的 8b/10b 且 TMDS 钟 = 像素钟模式下 `Tcharacter = 像素周期`、`TMDS 位速率 = 10 × 像素钟`（HDMI 1.4 §4.2.1 原文：`TMDS encoding converts the 8 bits per TMDS data channel into the 10 bit… rate of 10 bits per TMDS clock period`）。

| 像素钟 (MHz) | TMDS 位速率 (Gbps) | Tbit (ns) | Tcharacter=Tpixel (ns) | 对内偏斜 ≤0.15Tbit (ns) | **互对/钟↔数据 ≤0.20Tchar (ns)** | 上升下降 ≤0.4Tbit (ns) | 钟抖动 ≤0.25Tbit (ns) |
|---|---|---|---|---|---|---|---|
| 25 | 0.250 | 4.0000 | 40.0000 | 0.6000 | **8.0000** | 1.6000 | 1.0000 |
| **50** | **0.500** | **2.0000** | **20.0000** | **0.3000** | **4.0000** | **0.8000** | **0.5000** |
| **74.25** | **0.7425** | **1.3468** | **13.4680** | **0.2020** | **2.6936** | **0.5387** | **0.3367** |
| 148.5 | 1.485 | 0.6734 | 6.7340 | 0.1010 | 1.3468 | 0.2694 | 0.1684 |
| 165 | 1.650 | 0.6061 | 6.0606 | 0.0909 | 1.2121 | 0.2424 | 0.1515 |
| 222.75 | 2.2275 | 0.4489 | 4.4893 | 0.0673 | 0.8979 | 0.1796 | 0.1122 |
| 297 | 2.970 | 0.3367 | 3.3670 | 0.0505 | 0.6734 | 0.1347 | 0.0842 |
| 340 | 3.400 | 0.2941 | 2.9412 | 0.0441 | 0.5882 | 0.1176 | 0.0735 |

我们用的两档加粗。交叉验证：340 MHz 的 Tbit = 0.294 ns，与 Tektronix 原文 `the bit times, popularly referred as TBIT, can go down to 294 ps` 一致；165 MHz 的 0.4Tbit = 242 ps，与原文"75 ps to 250 ps"一致。
注意 `0.4 Tbit` 与 75 ps 的相对关系：像素钟 ≥ 187.5 MHz（位速率 ≥ 1.875 Gbps）后上界才超过下界；在我们 0.5/0.7425 Gbps 这两档，**下界 75 ps 才是真正的约束**（0.4Tbit 分别有 800 ps / 539 ps 的富余）。

---

## 二、这 6 个端口各自该用哪个量、为什么

先纠正一处事实（可回查，不影响到场结论）：本工程 `src/constraints/rk_zynq7020.xdc` 第 10–11 行写的是
`set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports {led[0]}]` / `{PACKAGE_PIN V13 IOSTANDARD LVCMOS33} [get_ports {led[1]}]`
——**这两颗 LED 不是 `TMDS_33`，是 `LVCMOS33`**；`TMDS_33` 只出现在 W16/Y16、AA17/AB17、U17/V17、U15/U16 这 8 个 TMDS 脚上。所以"6 个端口 + IOSTANDARD 是 TMDS_33"这个前提对 4 个 TMDS 脚成立、对 2 颗 LED 不成立。另外 `tmds_*_n` 是**真实存在并单独出脚的端口**（`report/BOARD_PINS.md`），所以对内偏斜这条量在本板是有物理意义的，不是纸上条目。

### 2.1 4 对 TMDS 差分（`tmds_clk_p` 与 `tmds_data_p[0..2]`，各自连同 `_n`）

| 端口 | 该用的量 | 为什么 |
|---|---|---|
| `tmds_data_p[0] / [1] / [2]`（连同各自 `_n`） | **①对外/互对：0.20 `Tcharacter`（表 #1）——即相对 `tmds_clk` 的对齐窗**；②对内：0.15 `Tbit`（#2）；③上升下降 75 ps ≤ t ≤ 0.4 `Tbit`（#3）；④眼掩码（#6，1.4 版 0.25–0.75 UI × ±200 mV，绝对 ±780 mV，最小开度 400 mV #8） | HDMI 1.3 第 45 页原文（#13）明说眼掩码"specifies the clock to data jitter indirectly"，即**数据相对钟的正确性 = 掩码 + 互对偏斜**，规范里没有第三种"clock-to-data setup/hold"数；`set_output_delay` 在 EDA 侧能表达的正是"到达时刻相对参考沿的偏移"，所以 #1 是唯一能原样搬进约束的时钟↔数据量。#3/#4 属于波形/眼域，只能在仿真与实测里判（见 3.3） |
| `tmds_clk_p`（连同 `_n`） | **①对内：0.15 `Tbit`（#2）；②占空比 40/50/60%（#5）；③钟抖动 ≤0.25 `Tbit`（#4，且必须按 #11 的 4 MHz −3 dB Ideal Recovery Clock 来理解）**；④上升下降（#3） | 钟道**自己就是参考**，所以不存在"钟相对谁"的输出窗；对它要求的是**质量参数**（占空比、抖动、沿、P/N 对称）。抖动是相对恢复钟的统计量，`set_output_delay`/`set_max_delay` 都没有表达"抖动"的语义（SDC 只约束沿的到达时刻，不约束抖动与转换时间），所以**这几条不该被写成对外窗**，应作为 MMCM 配置 + 实测判据。Keysight 还点名 74.25 MHz 是钟抖动的法定测试频点之一（#4） |
| 所有 4 对（DC 侧，供对照） | #9/#10（`Vswing` 400–600 mV 单端、`VL` 档、过/欠冲 15%/25%） | 这些是电气量，与 `report/io` 之前查到的 UG471 第 95 页 TMDS_33 属性同层，**不是时序窗**；写出来是为了明确"电气对、时序对"分家 |

关键概念，别在文档里含糊过去：**TP1 的量全都是"相对理想恢复钟"的**。源端并没有一个"引脚上的对齐规格"给 EDA 抄；EDA 能给的是"钟道与数据道之间的相对偏斜上限"，因为规范自己就把这件事交给 #1 与 #4 两个上限联合表达。所以对我们的 4 对差分，正确的说法是"**按 HDMI 规范源端互对偏斜上限 0.20 `Tcharacter` 建窗**"，而不是"按 HDMI 接收窗建窗"。接收窗（#17）是 TP2，明确不用。

### 2.2 那 2 颗 LED（`led[0]` = 心跳、`led[1]` = 状态）

它们**不接 HDMI 连接器**，`report/BOARD_PINS.md` 与约束文件里它们是 `LVCMOS33` 直驱 LED；HDMI 规范的连接器引脚表里也没有这类信号（#18）。
所以：**没有任何 HDMI/CTS 侧的窗可以套**。能引用的只有板级/内部依据：无接收端采样、人眼判读（几十 ms 量级），以及"它由哪个时钟域输出、Tco 是否已被内部路径分析覆盖"。
正确的处理是把它们登记成"对外无窗，理由 = 无采样器"，而不是从 TMDS 那 4 对借一个 0.20 `Tcharacter` 的数字过来——借了就等于伪造依据。具体建议见 3.4。

---

## 三、能转成 Vivado 约束的形式

下面每条都标了数从哪一行回来。**没有一条是 CTS 表**（CTS 表不可公开，见第四节）；凡"代理值"我都写代理。
本工程的真实钟名（`src/constraints/clock_groups_impl.xdc` 注释）：`clk_pix`（像素 50 MHz）、`clk_pix5x`（TMDS 串行 250 MHz）、`sys_clk`（W17，20 ns）、MMCM 输出 `clkout0_1 / clkout1_1 / clkout2`。落约束前请先用 `get_clocks` 确认当前实现里到底哪个名字存在——**这一句是工具事实核对提示，不是规范内容**。

### 3.1 钟↔数据窗（`tmds_data_*` 对 `tmds_clk_p`）——**有规范原文，可写**

形状（**50 MHz 档，窗 ±4.000 ns**；**74.25 MHz 档，窗 ±2.6936 ns**）：

```tcl
## 参考钟：转发出去的 TMDS 钟道，周期 = 像素周期 = Tcharacter
##   50 MHz   -> period 20.000 ；74.25 MHz -> period 13.468
## 用 create_clock 打在自己的输出脚上只是"建参照"，Vivado 允许在带驱动的输出脚上建钟；
## 若工具在这个用法上不给路径，就改用 create_generated_clock -source <MMCM 钟脚> -divide_by 1 挂到 tmds_clk_p。
create_clock -period 20.000 -name tmds_clk_ref [get_ports tmds_clk_p]

## 窗 = 0.20 × Tcharacter，出处：HDMI 1.4 Table 4-24 行
##   "Inter-Pair Skew at Source Connector, max | 0.20 T character"
##   同句在 Keysight 文档的 CTS 测试项 7-6 里写作 "Inter-pair skew must not exceed 0.20*Tpixel"
##   50 MHz   : 0.20 × 20.000 ns = 4.000 ns
##   74.25 MHz: 0.20 × 13.468 ns = 2.694 ns
set_output_delay -clock tmds_clk_ref -max  4.000 [get_ports {tmds_data_p[*] tmds_data_n[*]}]
set_output_delay -clock tmds_clk_ref -min -4.000 [get_ports {tmds_data_p[*] tmds_data_n[*]}]
```

要点与诚实声明：
- **窗是对称的**（±0.20 Tpixel），因为规范只给"两路单端信号之间的最大时间差"（HDMI 1.4 §4.2.4 正文定义），**没有给偏向哪一侧**；把不对称性当成规范要求的，就是编数。
- `set_output_delay` 的 `±` 语义：Vivado 会把输出路径的 Tco 计入到达时刻，所以这个窗**已经包含**片内偏斜，板级走线失配必须自己从 4.000 / 2.694 ns 里减；本板 4 对走线等长，减项≈0（这句是板级判断，非引用）。
- 若只约束 `tmds_data_p[*]`（把 `_n` 视为严格互补、由 OBUFDS 保证），窗值不变，但要在文档里写明"对内偏斜由器件互补驱动保证，未列入本窗"，并另立 #2（0.15 `Tbit`）为布线/器件规则，**不要**把它写成 `set_output_delay`——SDC 里没有"同一差分对 P/N 相对彼此"的窗语义。

### 3.2 备选形式：`set_max_delay`——**能写，但它不是同一个量，交付文档里别混称**

```tcl
## 数值同 3.1（4.000 / 2.694 ns），但语义不同：这条约束的是"从钟道寄存器/钟网络到数据引脚的绝对路径时延"，
## 而规范量的是"两条单端信号之间的最大时间差"。用它做替代要在旁边写清"近似"。
set_max_delay -from [get_pins <tmds_clk 输出寄存器/CBU>] -to [get_ports {tmds_data_p[*]}] 4.000
```
诚实边界：这条**只在** `set_output_delay` 因参考钟建不出来而不可用时当替代品，且它会把 Tco 绝对值（而非偏斜）一起吃掉，容易过约束。写成"已按 HDMI 互对偏斜约束"是不准确的；只能写"用 4.000 ns 上界近似 HDMI 源端互对偏斜 0.20 Tcharacter 的要求"。

### 3.3 上升/下降、眼掩码、占空比、钟抖动——**不要伪装成约束语句**

- **#3（75 ps ≤ t ≤ 0.4 `Tbit`）** 与 **#4/#5/#6**：SDC 的 `set_output_delay`/`set_max_delay` 只约束沿的到达时刻，不约束转换时间、抖动、占空比、眼图。工程上正确落法是：
  1. 器件侧：`TMDS_33` + 固定驱动/`SLEW` 相关属性，由 XDC 注释指回 #3 的两界（值可写进注释，不可当 delay 数）；
  2. 判据侧：留作**仿真（IBIS/眼图）与示波器实测**条目，并在 `docs/timing/debt_ledger.md` 里点名"此项无 EDA 窗，依据 HDMI 1.4 Table 4-24 + Keysight 7-4"；
  3. 若一定要在 Vivado 里留痕，用 `set_clock_uncertainty` 把 **#4 的 0.500 / 0.3367 ns** 作为钟道抖动预算"吃掉"是常见做法，但这是**设计余量**、不是对外合规声明——必须这样标注，写成"CTS 校验"就错了（代理性质：抖动的 4 MHz −3 dB 参考由 #11 定义，EDA 里根本不复现这个 CRU）。
- **#6/#7 眼掩码**：可以给出"可用时间窗半宽"的形式值——1.4 版半宽 0.25 UI = **500 ps @0.5 Gbps / 336.7 ps @0.7425 Gbps**，1.3 版半宽 0.18333 UI = 366.7 / 246.9 ps——**但这不是我建议直接进 XDC 的窗**：它的参考沿是"理想恢复钟"而不是我们自己发出去的钟道，把它和 #1 叠加会重复计费。写文档时建议只作为实测判据（并列出 #14 的 400,000 UI / 10,000 波形 / 16 M 记录长度这个"必须采多少才说得准"的门槛，出处是 Tektronix，属第三方代理）。

### 3.4 LED 那 2 个脚——**建议的写法是"不建窗 + 写明理由"**

```tcl
## 不给 set_output_delay：HDMI 规范/CTS 的连接器信号里没有这类指示脚（见第一节 #18），
## 板上也没有任何东西对这两脚建立采样关系 ⇒ 外部窗不存在，硬套 TMDS 的 4.000/2.694 ns 属于伪造依据。
## 若要过"未约束端口"这一关，二选一并写清是哪一种：
## (a) 工程约定窗（数值由我们自己定，出处=无）：
set_output_delay -clock clk_pix -max  10.000 [get_ports {led[0] led[1]}]
set_output_delay -clock clk_pix -min -10.000 [get_ports {led[0] led[1]}]
##     ↑ 10.000 = 0.5×Tpixel，纯为让工具不再报"对外无窗"的人为值，**不是**任何规范数；
       交付文档里必须写成"工程约定值，无外部依据"。
## (b) 或者干脆不写，登记为"对外无采样器，无需窗"。
```
我推荐 (b)，因为 (a) 一旦被读者当成有来源的数，性质就变了。

---

## 四、公开可引用性边界（不许含糊）

**必须等 HDMI Adopter 授权文件才能定死的部分：**

1. **CTS 本体**。HDMI Forum 官方页原文（我这次取到，[https://hdmiforum.org/specifications/](https://hdmiforum.org/specifications/)）：
   > "All products must comply with Version 2.2 of the HDMI Specification and the current Compliance Test Specification (CTS). HDMI Adopters should check the notices on current testing policies and **access the test specifications on the HDMI Adopter Extranet**."
   > "Companies must be an HDMI Adopter to implement the HDMI standard."
   以及 [https://www.hdmi.org/resource/testing](https://www.hdmi.org/resource/testing)：
   > "The HDMI Compliance Test Specifications represent the minimum compliance testing required for Licensed Products."
   → 即 **CTS 挂在 Adopter Extranet（需资质+登录）之后**，其**逐测试频点的限值表**（例如 Diodes 报告里出现的 `HDMIAutomationConfig / Timing 101` 那一档档配置）、**Pass/Fail 余量规则**（同报告里 `Warning < 2 % / Critical < 0 %` 这类阈值是测试系统配置项而非 CTS 公开表）、**测试图案/EDID/夹具设置**，都不是公开可引用的。
2. **TP1 掩码文件的顶点坐标**。Keysight 文档只暴露了"存在这个文件"这一事实——配置项 `MaskFile` 的取值是 `HDMI-TP1.msk, HDMI-TP2.msk, HDMI-TP5.msk, HDMI-DP++.msk`（"Select type of mask to use in HDMI 1.4b Eye Test"）。掩码的逐段坐标在规范插图里能读到（第一节 #6/#7），但**仪器真正加载的 `.msk` 内容不公开**，因此我不能声称"我的窗 = CTS 掩码"。
3. **CTS 版本号要点名，别含混**。这次从公开材料里读到的版本号有：**CTS 1.2a / 1.3c / 1.4a**（Tektronix 文中逐个点名哪一项在哪版不再要求）、**HDMI CTS 1.4b**（Sony HDMI ATC 深圳出具的公开报告封面 `CTS Ver: HDMI CTS 1.4b`）、**CTS 2.0 / HDMI 2.0**（Diodes 报告文件名 `HDMI2.0-CTS2.0-compliance-test-report.pdf`，正文写 `HDMI Specification 2.0`）。**我们板子的 0.5–0.7425 Gbps 落在 HDMI 1.x/1.4b 的量程里**，所以对口版本应是 **HDMI CTS 1.4b**（或 1.4a），**而我没有 1.4b 的任何一页**——只有关于它的第三方复述。

**交付文档应该怎么写（建议原话，别写成"已按 CTS 校验"）：**

> 本工程对 `tmds_clk_p` / `tmds_data_p[0..2]` 的输出窗依据 **HDMI Specification 1.4 §4.2.4 "HDMI Source TMDS Characteristics"、Table 4-24 "Source AC Characteristics at TP1"、Figure 4-30 "Eye Diagram Mask at TP1 for Source Requirements"**（公开镜像可取，页脚自标 `HDMI Licensing, LLC Confidential`）中的 **Inter-Pair Skew ≤ 0.20 `Tcharacter`**、**Intra-Pair Skew ≤ 0.15 `Tbit`**、**Rise/Fall 75 ps ~ 0.4 `Tbit`**、**Clock duty 40/50/60%**、**Clock Jitter ≤ 0.25 `Tbit`（相对 §4.2.3.1 Ideal Recovery Clock）** 建立；测试项编号与限值句另经 Keysight D9021HDMC 编程手册（CTS 项 7-4/7-6/7-7/7-8/7-9/7-10）与 Tektronix HT3 物理层合规应用笔记交叉印证。
> **未做 HDMI CTS 合规验证**：CTS（对口版本 **HDMI CTS 1.4b**）仅通过 HDMI Adopter Extranet 分发，本工程非 Adopter、未获取其任何一页；上述引用中属于 CTS 的部分**全部是仪器厂商/公开实测报告的转述（代理）**，包含但不限于：采集量门槛（≥400,000 UI、≥10,000 波形、≥16 M 记录）、`HDMI-TP1.msk` 的几何内容、逐频点限值表。
> 另注：眼图与抖动类量**无法用 SDC 表达**，SDC 里只落了互对偏斜窗；`led[0]/led[1]` 不属于 HDMI 连接器信号，**不套用任何 HDMI 窗**。

三条红线（我在本文里已遵守）：没有把 0.20 Tcharacter 写成"CTS 表值"（它同时是规范原文，所以引规范）；没有把 400,000 UI / 10,000 波形说成规范条款（它们只有 Tektronix 转述，判代理）；没有给 LED 编一个 HDMI 依据。

**仍然"无法核实"的具体条目**（试过、拿不到，别在别处当已知引用）：
- HDMI 1.4 Table 4-24 中 rise/fall 那一格的**上界是否被 1.4 删掉**：我在这份镜像里只读到 `75psec ≤ Rise time / fall time`，两份旧版（1.1/1.3）与 Tektronix 都仍是双界。→ 无法核实 1.4 的意图，本文只按"1.1/1.3 原文 + Tektronix 复述"引上界。
- HDMI 1.4 里 CTS 是否**仍测**钟↔数据互对偏斜：Tektronix 说 CTS 1.3c/1.4a 不再要求、CTS 1.2a 要求；而 Keysight 文档仍列有 7-6 项。→ 两者不能同时"核实到 CTS 原文"，只能并列引用并标明各自出处。
- Diodes 的 HDMI 2.0 CTS 2.0 源端报告里**没有** inter-pair skew（HF1-3）这一项（该报告只出现 `HF1-1/2/4/5/6/7/8`）。→ 我不据此推断"CTS 2.0 没有此项"，只能说这份公开报告没测。
- UG471 第 95 页（TMDS_33）本轮**未重新打开**（前一次的结论按题设沿用，不作为本文引用条目）。

---

## 五、我实际打开过的 URL 清单

| URL | 状态 | 取到了什么（或没取到什么） |
|---|---|---|
| <https://file-host.wiki-power.com/circuit-design/.../HDMI1.4%E6%A0%87%E5%87%86.pdf>（《HDMI Specification Version 1.4》镜像，4,074,806 B，PDF 1.6，197 页） | **打开成功**（先 `WebFetch`：失败，返回原始 PDF 结构/FlateDecode 流，读不出文字；改 `curl` 下载 + 本地 `pdftotext -layout` 与 `pypdf` 双抽取） | §4.2.2 Table 4-22（AVcc 3.3 V ±5%、RT 50 Ω ±10%）；§4.2.3.1 Ideal Recovery Clock 全文与 Eq. 4-1（20 dB/dec、−3 dB @4 MHz）；§4.2.4 全文 + **Table 4-23 / Table 4-24 / Figure 4-30**（第 58–59 页，PDF 第 73–74 页）；`Minimum opening at Source = 400 mV`；`Source eye diagram test procedures are defined in the HDMI Compliance Test Specification.`；§4.2.5 Sink 侧 Table 4-25（明确排除不用） |
| <https://fpga.mit.edu/6205/_static/F23/common_files/week04/CEC_HDMI_Specification.pdf>（《HDMI 1.3》镜像，2,015,882 B，237 页） | **打开成功**（同上：`WebFetch` 只回原始流，`curl`+`pypdf` 出文） | **Table 4-15 / Table 4-16 "Source AC Characteristics at TP1"** 完整行（第 43 页），含 `75psec ≤ Rise time / fall time ≤ 0.4 Tbit`、`Undershoot, max 25%…`；**Figure 4-18** 掩码坐标（第 44 页）；第 45 页 `…the Source eye diagram mask of Figure 4-18 is not used for response time and clock jitter specifications, but specifies the clock to data jitter indirectly.`；Table 4-19 Sink TP2（用于对照）；Table 4-21 线缆 151/111 psec、2.42/1.78 nsec |
| <https://u.dianyuan.com/bbs/u/37/1137460350.pdf>（《HDMI 1.1》镜像，1,908,528 B，206 页） | **打开成功**（`curl`+`pypdf`） | **Table 4-12 / Table 4-13** 全部行（第 34 页）：`75psec ≤ Rise time / fall time ≤ 0.4 Tbit`、`Overshoot 15%`、`Undershoot 25%`、`0.15 Tbit`、**`Inter-Pair Skew … max | 0.20 T pixel`**、`40% / 50% / 60%`、`0.25 Tbit`；**Figure 4-12** 掩码坐标（第 35 页，`0.15 / 0.31666... / 0.68333... / 0.85`、`±0.25 / ±0.50 / ±0.65`）。作为 Table 4-24 的第三份独立印证 |
| <https://www.tek.com/en/documents/application-note/physical-layer-compliance-testing-hdmi-using-tdsht3-hdmi-compliance-test-s> | **打开成功**（214,730 B HTML，本地剥标签出 50,700 字符纯文） | "Source signals are characterized at TP1 while the sink devices are tested at TP2"；CTS 源端全套限值句：`higher than 75 ps and lower than 0.4 * TBIT`、`not to exceed 20% of the pixel-time (TPIXEL)`、`a limit of 15% of the bit time (TBIT)`、`less than 0.25*TBIT`、`within 40% and 60%`、`overshoot as 15% and undershoot as 25%`、`VL … within 2.7 V and 2.9 V`；采集门槛 `400,000 unit intervals` / `10,000-triggered waveforms` / `16 Meg record length`；版本差异句 `not required as per CTS 1.4a … required … as per CTS 1.2a`、`not required as per CTS 1.3c`；量程句 `25 Mpps to 340 Mpps … TBIT can go down to 294 ps`；旁证 `At 165 MHz clock rate, the rise times can be between 75 ps to 250 ps` |
| <https://download.tek.com/manual/TDSHT3SourceTestReference.pdf> | **打开成功**（635,483 B，但**只有 2 页**，是 Quick Reference Card） | 只拿到**源端测试项名录**：`eye diagram, duty cycle, rise time, fall time, clock jitter, over/undershoot v-h, over/undershoot v-l, and inter-pair skew test simultaneously`；**没有任何数值**。第一页读到，第二页因 GBK 控制台编码报错未打印（已改用 UTF-8 输出，第二页内容为菜单树，无数值） |
| <https://www.keysight.com/bf/en/assets/9924-01437/programming-guides/D9021HDMC-HDMI-Test-Software-Remote-Prog-Ref-2-40-2024-0.pdf> | **打开成功**（383,981 B，74 页） | **CTS 测试项编号 + 限值句逐字**：`7-6: Inter-Pair Skew - D0/Clock … must not exceed 0.20*Tpixel. The Source shall meet the AC specifications in Table 4-13…`；`7-7: Intra-Pair Skew - Clock … Frequency > 165 MHz: … 0.15*Tbit`；`7-8: … at least 40% and not more than 60%`；`7-9: Clock Jitter … 0.25*Tbit … DUT should output 27MHz(or 25MHz), 74.25MHz, 148.5MHz, and 222.75MHz for testing`；`1-6: Clock Jitter … 0.27*Tbit … > 340MHz`；`7-10: D0 Mask Test … The Source shall have output levels at TP1, which meet the normalized eye diagram requirements`；`Cable Inter-Pair Skew … no more than 2.42ns`、`… no more than 151ps`；`MaskFile HDMI-TP1.msk, HDMI-TP2.msk, …`（掩码是文件、内容不公开）；TTC 沿时间按频点分档表（`Model 1 1200ps ≤27MHz / Model 2 450ps =74.25MHz / Model 3 220ps =148.5MHz / Model 4 200ps =165MHz / Model 5 150ps =222.25MHz / Model 6 60ps >222.75MHz`）。**注：表格第二列是 TestID（如 330/300/600/9005），我确认过它不是 ps 限值，未误用** |
| <https://www.keysight.com/us/en/assets/9925-01577/programming-guides/D9021HDMC-HDMI-Test-Software-Remote-Prog-Ref-2-41-1005-0.pdf> | **打开失败/内容不符** | `curl` 拿回 654,831 B 但是 **HTML（`<!ht…`），不是 PDF**（`file` 判为 HTML；`pypdf` 报 `Stream has ended unexpectedly`）。换上一行的 `keysight.com/bf/...` 版本才拿到 PDF |
| <https://www.diodes.com/assets/Part-Support-Files/PI3HDX1204B1/PI3HDX1204B1_App_HDMI2.0-CTS2.0-compliance-test-report.pdf> | **打开成功**（8,277,653 B，35 页；抽取时有 `/Im37` 等重复字典项告警，文字仍完整可取） | **公开实测报告里的 CTS "Pass Limits" 原文行**：`HF1-2: Clock Rise Time 127.210 ps … VALUE >= 75.000 ps`；`HF1-6 … >=40% / <=60%`；`HF1-6: Clock Rate 148.4563 MHz … 85.000000 MHz <= VALUE <= 150.000000 MHz`；`HF1-7: Differential Clock Voltage Swing, Vs (TP1) … 400 mV < VALUE < 1.200 V`；`HF1-7: Clock Jitter … VALUE <= 300 mTbit` + `must not exceed 0.3*Tbit`；`HF1-5 … <= 780 m`；`HF1-2: D0 Rise Time … VALUE >= 42.500 ps`；`HF1-4: Intra-Pair Skew - Data Lane 2 … -150 mTbit <= VALUE <= 150 mTbit`；`HF1-1 … 2.300 V <= VALUE <= 2.900 V`；`HF1-8: D0 Mask Test (TP2_EQ with Worst Case Positive/Negative Skew) … No Mask Failures`；配置 `HDMI Specification 2.0`、`Timing 101`、`Tbit(ps) 168.400`、仪器 Keysight DSOX92504A。**两个重要"没有"**：整份报告**不含 inter-pair skew（无 HF1-3 项）**；眼/掩码与抖动是**在 TP2_EQ（套最坏线缆模型+均衡）后判**，不是 TP1 直接判——这决定了"CTS 2.0 时代的源眼"与规范 Figure 4-30 的 TP1 眼不是同一测点 |
| <https://e2echina.ti.com/cfs-file/__key/communityserver-discussions-components-files/59/SZ16013_5F00_HDMI_5F00_Protech_5F00_PETHC_5F00_1.4b_5F00_P_5F00_0509_5F00_chk.pdf> | **打开成功但内容不符**（184,290 B，7 页） | 这是一份 **Sony HDMI ATC 深圳** 出的 **CTS 1.4b** 报告，但 **DUT 是接收端**（`Product Type: Other sink (Adapter)`，测试项是 8-x 段 Sink 系列：`TMDS - Termination Voltage / Minimum Differential Sensitivity / Intra-Pair Skew / Jitter Tolerance (D_JITTER = 500kHz, C_JITTER = 10MHz …)`，297.00/222.75 MHz）。**没有任何源端 TP1 限值**，所以第一节的数一条都不能从它取；它只用于两件事：证明 **CTS 版本号写法 `CTS Ver: HDMI CTS 1.4b`** 与 ATC 送测流程真实存在 |
| <https://www.hdmi.org/resource/testing> | **打开成功**（`WebFetch`） | `Each Adopter must test a representative sample for HDMI® compliance.`、`The HDMI Compliance Test Specifications represent the minimum compliance testing required for Licensed Products.`、`For more information, or to facilitate testing exercises, the following documents are available for download.`（该页本身未写 NDA 字样，我不夸大） |
| <https://hdmiforum.org/specifications/> | **打开成功**（`curl` HTTP 200 + 本地剥标签核对，并用 `WebFetch` 二次确认） | 决定性一句：`HDMI Adopters should check the notices on current testing policies and access the test specifications on the HDMI Adopter Extranet.`；另有 `Companies must be an HDMI Adopter to implement the HDMI standard.`、`All products must comply with Version 2.2 of the HDMI Specification and the current Compliance Test Specification (CTS).`、`HDMI 2.2 Specification … is available to all HDMI 2.1 Adopters.` |
| <https://www.hdmi.org/adopters> | **打开失败** | `WebFetch` 返回 **HTTP 405 Method Not Allowed**，未取到内容（按规则未重试同一 URL） |
| <https://dokumen.pub/high-definition-multimedia-interface-specification-version-14-14anbsped.html> | **打开失败** | `fetch failed`（搜索命中，试图作为 1.4 Table 4-24 的第四份镜像互校，未成功；互校已由 1.1/1.3/1.4 三份 PDF 完成） |
| <https://download.tek.com/datasheet/HDMI-Compliance-Test-Software-Datasheet-61W282962_0.pdf>、<https://download.tek.com/datasheet/TekExpress_HDMI-Datasheet_61W616961.pdf>、<https://cdn.teledynelecroy.com/files/pdf/qphy-hdmi21-datasheet.pdf>、<https://incompliancemag.com/eye-diagram-part2/> | **本次未打开** | 仅是搜索命中列在这里备查；我**没有**从这些地址取任何数字，因此正文不引用它们 |

---

### 本次实际支撑住的可引用要点（一句话版）

钟↔数据对齐：**0.20 `Tcharacter`（= 20% 像素时间）**，HDMI 1.4 Table 4-24 原文行，另有 1.3/1.1 同值 + Keysight CTS 项 7-6 + Tektronix 逐句复述；对内偏斜 **0.15 `Tbit`**；上升下降 **75 ps ~ 0.4 `Tbit`**；占空比 **40/50/60%**；钟抖动 **0.25 `Tbit`**（相对 4 MHz −3 dB 的理想恢复钟）；TP1 眼掩码 **0.25–0.75 UI × ±200 mV、绝对 ±780 mV、最小开度 400 mV**。
拿不到的：**CTS 原表本身**（`HDMI-TP1.msk` 几何、逐频点限值、Pass/Fail 余量规则），只能在交付文档里写成"规范原文 + 仪器厂商/公开实测报告的转述（代理）"，并明说"未做 CTS 合规验证"。
