# STORY.md — 参赛PPT_共享单车北斗可信电子围栏

## ① 用户意图对齐

**目标受众**：第八届湖南省大学生智能导航科技创新大赛决赛评委（导航/测绘领域专家为主，含少量非本领域评委）。场合为**现场答辩评审**，评委手中已有《方案报告》，PPT 承担"3–5 分钟讲清方案 + 支撑追问"的职责。

**核心目标**：讲完后评委应当相信三件事——(1) "停在停车点却被扣费"是真实且可量化的民生痛点；(2) 本方案把"位置是否可信"前置到扣费之前，是有业务语义的创新，不是又一个围栏 App；(3) 指标经可复现的数字孪生验证，且规则不绑死任何硬件。最终希望评委记住一句话：**先判信不信，再判罚不罚**。

**PPT 长度**：25 页（Hero 配额 5 页，占 20%）。

**视觉调性**：学术严谨 / 证据驱动 / 蓝白克制 / 图表优先 / 克制留白。

**内容边界**：
- 必讲：六章目录结构（现状、目标、创新、内容与思路、前景、挑战）、三态规则、84%→11% 与 74%→0% 两个核心数字、四张证据图、Zynq 为**可选**验证载体。
- 不讲：FPGA 资源跑分、AXI/PL 流水线细节、射频前端与信道模拟、IMU 融合实现。
- 禁碰：任何"必须 FPGA / FPGA 加速 / 替代专业信道模拟仪"表述；编造未做的实测；把绝对定位误差当作卖点。

---

## ② 页面布局骨架

全篇 25 页，分 6 章 + 封面/目录/结束页。章节划分逐字对齐《方案报告》官方目录：01 国内外发展现状、02 研究目标、03 创新性、04 主要研究内容及实现思路、05 应用前景、06 挑战性和不确定性。

**目录↔章节扉页契约**：目录声明 6 章，全篇有且仅有 6 个 `type: section` 扉页，编号 01–06 连续，标题文字与目录条目逐字一致。映射如下：

| 目录条目 | 编号 | section 扉页页码 | 本章内容页 |
|---|---|---|---|
| 国内外发展现状 | 01 | P3 | P4–P6 |
| 研究目标 | 02 | P7 | P8–P9 |
| 创新性 | 03 | P10 | P11–P12 |
| 主要研究内容及实现思路 | 04 | P13 | P14–P19 |
| 应用前景 | 05 | P20 | P21 |
| 挑战性和不确定性 | 06 | P22 | P23 |

**Hero 页定位**：P1 封面（默认）、P5 痛点数字冲击、P8 三态规则、P17 实验结果、P25 结束页 —— 共 5 页，占 25 页的 20%，落在 20–30% 区间；P1/P5 间隔 3 页、P5/P8 间隔 2 页、P8/P17 间隔 8 页、P17/P25 间隔 7 页，任意两个 Hero 之间均至少间隔 1 个 Supporting 页。

**rhythm 曲线**：P1 peak → P2/P3 transition → P4 valley → P5 peak → P6 valley → P7 transition → P8 peak → P9 valley → P10 transition → P11/P12 valley → P13 transition → P14 peak → P15/P16 valley → P17 peak → P18/P19 valley → P20 transition → P21 valley → P22 transition → P23 valley → P24 peak。无连续 ≥3 页 valley（P15/P16 后接 P17 peak；P18/P19 后接 P20 transition）。

**非对称版式预算**：25 页中 21 页使用非对称版式，占 84%（≥40% 达标）。其中 `左大图+右侧文字`（P15、P20）与 `非对称双栏`（P4、P12、P16、P24）合计 6 页，占全篇 24%（≤40% 达标）。

**对称版式预算**：内容页仅 2 页使用对称版式 —— P11 `N卡片横排`、P17 `图表+洞察`；其余内容页一律非对称。封面 P1 与结束页 P24 用 `全屏视觉+大标题`，6 个 section 扉页统一用 `全幅图+骑线文字`（仪式页，样式全篇锁定）。

**相邻页版式不重复**：已逐页核对，25 页无任意相邻两页版式相同（section 扉页相隔 ≥2 页，不构成相邻重复）。

---

## ③ 页面大纲

### P1 封面
- `title`: 面向共享单车的北斗可信电子围栏
- `type`: cover ｜ `role`: hero ｜ `rhythm`: peak
- `layout`: 全屏视觉+大标题
- `visual`: L1: 深蓝顶条 + 标题层级（无位图）｜ L3: 赛事名称角标
- `visual_role`: anchor
- `density`: 字数约 60 / 图片 0 张 / 留白约 30%
- `anti_pattern`: 禁止党政红金与印章；禁止把赛事名做成比中文主标更抢眼的元素；禁止堆叠 3 个以上装饰几何形
- `description`: 中文主标 + 英文长 title + 副标"多径条件下的违停误判抑制与数字孪生验证" + 赛事与赛道信息。定位一句话：先判信不信，再判罚不罚。

### P2 目录
- `title`: 目录
- `type`: catalog ｜ `role`: supporting ｜ `rhythm`: transition
- `layout`: 左标题+右内容
- `visual`: L3: 深蓝编号方块 ×6
- `visual_role`: evidence
- `density`: 字数约 120 / 图片 0 张 / 留白约 35%
- `anti_pattern`: 禁止圆球编号；禁止英文比中文更抢眼；禁止条目少于 6 条或超过 6 条
- `description`: 六章编号导航，条目文字与《方案报告》官方目录逐字一致——01 国内外发展现状、02 研究目标、03 创新性、04 主要研究内容及实现思路、05 应用前景、06 挑战性和不确定性。

### P3 章节扉页 01
- `title`: 国内外发展现状
- `type`: section ｜ `role`: transition ｜ `rhythm`: transition
- `layout`: 全幅图+骑线文字
- `visual`: L3: 章节大数字 01（≥120px）
- `visual_role`: atmosphere
- `density`: 字数约 70 / 图片 0 张 / 留白约 35%
- `anti_pattern`: 禁止四卡片预览；禁止铺满正文段落；禁止出现 "PART 01" 字样
- `description`: 大数字 01 + 章节标题 + 2–4 个要点，宣告进入现状分析。

### P4 现状：电子围栏已普及，缺的是"可信度"
- `title`: 电子围栏已普及，缺的是位置可信度
- `type`: content ｜ `role`: supporting ｜ `rhythm`: valley
- `layout`: 非对称双栏（65:35）
- `visual`: L2: 深蓝数据条（围栏边界 1–3 m vs 城市峡谷误差数米至十余米）
- `visual_role`: evidence
- `density`: 字数约 260 / 图片 0 张 / 留白约 22%
- `anti_pattern`: 禁止左右等分双栏；禁止把"1–3 m"与"十余米"两个量级做成等宽卡片
- `description`: 国内主流平台普遍采用"解算坐标 + 多边形包含"二值策略，开阔环境有效，但围栏边界仅 1–3 m 量级而城市峡谷伪距误差可达数米至十余米——**误差量级与判定尺度同阶，边界误判不是偶发而是结构性缺陷**。国外研究已把完好性概念从航空导航向微出行渗透，核心是"风险超限时拒绝输出或降级服务"，本方案沿此方向把降级落成计费语义。

### P5 痛点：一次误扣是怎么发生的
- `title`: 停在框里，被判违停
- `type`: content ｜ `role`: hero ｜ `rhythm`: peak
- `layout`: 巨型数字+洞察
- `visual`: L1: 巨型数字 84.2%（≥96px，锚点）｜ L2: 5 步用户故事条
- `visual_role`: anchor
- `density`: 字数约 200 / 图片 0 张 / 留白约 25%
- `anti_pattern`: 禁止等宽卡片横排；禁止把 84.2% 塞进图表卡角落；禁止 L3 角标顶替 L1
- `description`: 城市多径场景下旧逻辑误扣费率 84.2% —— **这不是个别投诉，而是四分之三以上的边界停车都会被误判**；用户申诉、客服成本、平台口碑同时受损。运营侧真正缺的不是精度，而是"不可信、待复核"这个第三态。

### P6 现状对比与本方案定位
- `title`: 四条技术路线的定位差异
- `type`: content ｜ `role`: supporting ｜ `rhythm`: valley
- `layout`: 左标题+右内容
- `visual`: Chart(表格)：四条路线 × 四项维度
- `visual_role`: evidence
- `density`: 字数约 240 / 图片 0 张 / 表格 1 个 / 留白约 20%
- `anti_pattern`: 禁止用四张等宽卡片替代表格；禁止把对比做成营销式打勾表
- `description`: 纯多边形包含（现状，零成本但结构误判）、蓝牙信标/UWB（厘米级但部署密度与成本高）、多星座多频 RTK（提高精度但不解决欺骗、锁端成本高）、云端轨迹后处理（延迟与隐私）——**四条路线都在"提高精度"，没有一条回答"这次能不能信"**；本方案补的正是这个缺位。

### P7 章节扉页 02
- `title`: 研究目标
- `type`: section ｜ `role`: transition ｜ `rhythm`: transition
- `layout`: 全幅图+骑线文字
- `visual`: L3: 章节大数字 02（≥120px）
- `visual_role`: atmosphere
- `density`: 字数约 70 / 图片 0 张 / 留白约 35%
- `anti_pattern`: 禁止四卡片预览；禁止铺满正文段落；禁止出现 "PART 02" 字样
- `description`: 大数字 02 + 章节标题 + 2–4 个要点。

### P8 三态计费规则：核心业务语义
- `title`: 三态计费规则：先判可信，再判围栏
- `type`: content ｜ `role`: hero ｜ `rhythm`: peak
- `layout`: 上大图+下方卡片
- `visual`: L1: assets/fig3_three_states.png（占上 58%）
- `visual_role`: anchor
- `density`: 字数约 210 / 图片 1 张 / 留白约 18%
- `anti_pattern`: 禁止把三态图缩成 200×70 角标；禁止在下半区再放三张等宽卡片复述图片内容
- `description`: 三态规则图——合规（可信且框内，不扣费）、违停（可信且框外，扣调度费）、不可信（可疑/拒止，不扣费并进复核）。**判定的前提从"点在不在框里"换成"这个点能不能信"，误扣在这一步就被拦下**，而不是等到用户申诉才补救。

### P9 三层目标与验收口径
- `title`: 三层目标与验收口径
- `type`: content ｜ `role`: supporting ｜ `rhythm`: valley
- `layout`: 左标题+右内容
- `visual`: FAIcon 列表 + 底部结论条
- `visual_role`: evidence
- `density`: 字数约 250 / 图片 0 张 / 留白约 20%
- `anti_pattern`: 禁止三张等宽卡片横排；禁止只写目标不给验收指标
- `description`: 业务层——把"不可信→不扣费"写进计费流程，误扣率作为可交付指标；方法层——建立贴边停车 + 城市多径 + 慢拉欺骗 + 局部拒止的数字孪生测试集，不购外设即可复现；工程层——规则与载体解耦，MCU 可量产、Zynq 仅作研发验证。**三层各自的验收口径都落在同一个可测量上：误扣费率**。

### P10 章节扉页 03
- `title`: 创新性
- `type`: section ｜ `role`: transition ｜ `rhythm`: transition
- `layout`: 全幅图+骑线文字
- `visual`: L3: 章节大数字 03（≥120px）
- `visual_role`: atmosphere
- `density`: 字数约 70 / 图片 0 张 / 留白约 35%
- `anti_pattern`: 禁止四卡片预览；禁止铺满正文段落；禁止出现 "PART 03" 字样
- `description`: 大数字 03 + 章节标题 + 2–4 个要点。

### P11 四个创新点
- `title`: 四个创新点
- `type`: content ｜ `role`: supporting ｜ `rhythm`: valley
- `layout`: N卡片横排（全篇第 1 次，共 2 次）
- `visual`: L2: 四张浅蓝卡 + 深蓝编号方块
- `visual_role`: evidence
- `density`: 字数约 280 / 图片 0 张 / 留白约 18%
- `anti_pattern`: 禁止 Hero 级视觉投入；禁止四张卡内容长度失衡（兄弟卡高差须 ≤8px）；禁止全部使用深蓝实色卡
- `description`: 业务创新——完好性前置到扣费之前，用"不可信不扣费"保护用户；方法创新——以残差一致性等中间量驱动三态判决，与围栏几何解耦，阈值可标定、算法可替换；工程创新——规则与载体解耦，MCU/PC/Zynq 同一套逻辑同一套指标；验证创新——数字孪生测试集 + 业务可读指标（误扣率），而非只报坐标 RMSE。

### P12 与 RAIM / 竞品的方法学区别
- `title`: 新在哪：不是新检测理论，是新的计费语义
- `type`: content ｜ `role`: supporting ｜ `rhythm`: valley
- `layout`: 非对称双栏（60:40）
- `visual`: L2: 左右对照文字块 + 中央分隔线
- `visual_role`: evidence
- `density`: 字数约 260 / 图片 0 张 / 留白约 20%
- `anti_pattern`: 禁止左右等分双栏；禁止用"我们更先进"式空泛表述替代具体差异
- `description`: 基线确实使用残差一致性（RAIM 思想），**创新不在发明新检测理论，而在两处**：一是把完好性输出接到计费业务语义上（HOLD 是一个有业务后果的状态，不只是标志位）；二是把多径/欺骗/拒止的复合剧本做成可复现、可回归的评估集，让"相对改善"可被第三方复算。

### P13 章节扉页 04
- `title`: 主要研究内容及实现思路
- `type`: section ｜ `role`: transition ｜ `rhythm`: transition
- `layout`: 全幅图+骑线文字
- `visual`: L3: 章节大数字 04（≥120px）
- `visual_role`: atmosphere
- `density`: 字数约 70 / 图片 0 张 / 留白约 35%
- `anti_pattern`: 禁止四卡片预览；禁止铺满正文段落；禁止出现 "PART 04" 字样
- `description`: 大数字 04 + 章节标题 + 2–4 个要点。

### P14 系统框架与数据流
- `title`: 系统框架：四层解耦，载体可替换
- `type`: content ｜ `role`: supporting ｜ `rhythm`: peak
- `layout`: 上大图+下方卡片
- `visual`: L1: assets/fig4_pipeline.png（占上 56%）
- `visual_role`: evidence
- `density`: 字数约 230 / 图片 1 张 / 留白约 18%
- `anti_pattern`: 禁止把技术路线图缩小当装饰；禁止在下半区重复复述图中六个节点
- `description`: 技术路线图——场景库 → 真值+伪距注入 → WLS 定位/残差 RMS → 完好性三态 → 围栏决策 OK/FEE/HOLD → 业务指标误扣率。**L2–L4 是作品本体，L0 载体（MCU/PC/Zynq）可替换而指标不变**，这条解耦线是本方案区别于"绑硬件"作品的关键。

### P15 定位与完好性：伪距解算与残差判据
- `title`: 定位与完好性：从伪距到三态
- `type`: content ｜ `role`: supporting ｜ `rhythm`: valley
- `layout`: 左大图+右侧文字
- `visual`: L1: 公式块（伪距观测方程 + 残差 RMS）占左 55%
- `visual_role`: evidence
- `density`: 字数约 240 / 图片 0 张 / 公式 2 组 / 留白约 20%
- `anti_pattern`: 禁止 50:50 等分双栏；禁止用装饰图替代公式；禁止杜撰公式
- `description`: 伪距 ρᵢ ≈ |x_sat,i − x| + c·dt + εᵢ，未知数 x,y,z 与钟差共 4 个，用迭代加权最小二乘求解；去公共钟差后取残差 RMS 作为一致性判据——RMS 小则可信、中等则可疑、超上限或可用星不足 4 颗则拒止。**判据来自观测之间的自洽性，不依赖外部基准，因此锁端可独立运行**。

### P16 数字孪生测试集设计
- `title`: 数字孪生：不买外设的可复现验证
- `type`: content ｜ `role`: supporting ｜ `rhythm`: valley
- `layout`: 非对称双栏（60:40）
- `visual`: L2: 四场景参数表 + 干扰注入示意
- `visual_role`: evidence
- `density`: 字数约 250 / 图片 0 张 / 表格 1 个 / 留白约 20%
- `anti_pattern`: 禁止把"数字孪生"讲成 3D 动画；禁止只列场景名不给注入参数
- `description`: 四个剧本——清洁（仅噪声 σ=1.2 m）、城市多径（慢变正弦 + 高斯包络，幅值 12 m）、多径+慢拉欺骗（部分星公共慢变偏置 0.3 m/s）、局部拒止（35 s 后仅保留 3 颗星，其余注入大噪声）。轨迹沿停车框下沿平移 121 历元，模拟"找车位靠边停"。**场景参数写在代码里、指标输出成 CSV，任何人都能重跑复算**——这是"可复现"的具体含义，也是与硬件在环（HIL）的成本差异所在。

### P17 实验结果：误扣费率对比
- `title`: 实验结果：误扣费率 84.2% → 10.5%
- `type`: content ｜ `role`: hero ｜ `rhythm`: peak
- `layout`: 图表+洞察（全篇第 2 次也是最后一次对称版式）
- `visual`: L1: assets/fig1_false_fee.png（主图占 C 区 ≥50%）
- `visual_role`: anchor
- `density`: 字数约 190 / 图片 1 张 / 留白约 16%
- `anti_pattern`: 禁止把对比图缩成半栏配图；禁止只摆数字不给判断；禁止缺关键数字
- `description`: 四场景误扣率对比——清洁 5.3%→5.3%（不劣化）、城市多径 84.2%→10.5%、多径+欺骗 73.7%→0%、局部拒止 26.3%→5.3%。**代价是不可信占比升高（多径 43.8%、欺骗 79.3%、拒止 71.1%），即用"暂时不扣费 + 进复核"换取不冤枉用户**；清洁场景不变说明该机制不会无差别触发，阈值确实卡在干扰上。

### P18 空间证据：多径把解算坐标拉出框外
- `title`: 证据：多径把解算坐标拉出框外
- `type`: content ｜ `role`: supporting ｜ `rhythm`: valley
- `layout`: 整幅大图 + 底部指标条
- `visual`: L1: assets/fig2_v2.png（整幅 1200×446，俯视图）
- `visual_role`: evidence
- `density`: 字数约 90 / 图片 1 张 / 留白约 14%
- `anti_pattern`: 禁止把俯视图缩成半栏；禁止只放图不解释红点与紫点含义；禁止拉伸变形
- `description`: 绿框为 16 m × 12 m 合规停车区；蓝线为车辆真值轨迹（始终贴着框下沿，因为用户在框边找车位）；橙线为北斗解算轨迹，被多径拉出框外并来回抖动。红点 = 旧逻辑误扣风险点（8 个，车真在框内但解算点在框外）；紫点 = 本方案选择不扣费的 HOLD（18 个，集中在解算抖动最剧烈的区段）。**误扣的减少不是靠放宽阈值——阈值未动，而是把不确定的历元显式标出，而不是硬归入"框外"**。

### P19 时序证据：HOLD 覆盖不确定历元
- `title`: 证据：旧逻辑大面积误判，HOLD 覆盖不确定历元
- `type`: content ｜ `role`: supporting ｜ `rhythm`: valley
- `layout`: 整幅大图 + 底部结论条
- `visual`: L1: assets/fig5_fee_timeline.png（整幅 1200×480，三行决策时间线）
- `visual_role`: evidence
- `density`: 字数约 60 / 图片 1 张 / 留白约 20%
- `anti_pattern`: 禁止把时间线压缩成窄条；禁止不做真值/本方案/旧逻辑三行对照
- `description`: 同一段 121 历元的三行对照——行 1 真值（框内/框外）、行 2 本方案（合规/可疑/HOLD 不扣费）、行 3 旧逻辑（框内/框外二值）。旧逻辑在中间一大段大面积判"框外"，而真值那时仍在框内，这一整片红色就是误扣来源；本方案并未把红色改成绿色，而是把它变成紫色。**面对不确定的历元，旧逻辑被迫二选一，本方案多给了一个"先不判"的选项**。

### P20 边缘可部署性验证
- `title`: 边缘可部署性：同一套规则跑在 Zynq PS 上
- `type`: content ｜ `role`: supporting ｜ `rhythm`: valley
- `layout`: 左大图+右侧文字
- `visual`: L1: assets/fig6_vitis.png（占左 58%）
- `visual_role`: evidence
- `density`: 字数约 240 / 图片 1 张 / 留白约 20%
- `anti_pattern`: 禁止 50:50 等分双栏；禁止把"上板"写成方案成立的前提；禁止出现 FPGA 跑分表述
- `description`: 与 PC 同源的测试集（4 场景 × 121 历元）链入 ELF，经 JTAG 下载到 Zynq-7020 的 ARM Cortex-A9 批处理，结果写入结果邮箱后由调试接口回读，清洁场景误扣率与 PC 金标准一致（0.053）。**这一页证明的是"规则可在边缘 SoC 运行"，而非"必须用 FPGA"**——量产锁控主路径仍是低功耗 MCU / GNSS 模组，Zynq 只是研发验证与路侧 RSU 原型的一种形态。

### P21 章节扉页 05
- `title`: 应用前景
- `type`: section ｜ `role`: transition ｜ `rhythm`: transition
- `layout`: 全幅图+骑线文字
- `visual`: L3: 章节大数字 05（≥120px）
- `visual_role`: atmosphere
- `density`: 字数约 70 / 图片 0 张 / 留白约 35%
- `anti_pattern`: 禁止四卡片预览；禁止铺满正文段落；禁止出现 "PART 05" 字样
- `description`: 大数字 05 + 章节标题 + 2–4 个要点。

### P22 应用价值与落地路径
- `title`: 谁受益，怎么落地
- `type`: content ｜ `role`: supporting ｜ `rhythm`: valley
- `layout`: 左标题+右内容
- `visual`: FAIcon 列表 + 底部结论条
- `visual_role`: evidence
- `density`: 字数约 260 / 图片 0 张 / 留白约 20%
- `anti_pattern`: 禁止四张等宽卡片；禁止只讲价值不讲成本与部署
- `description`: 用户体验——显著减少"停在停车点仍被扣费"的纠纷；城市治理——在秩序与体验之间给出可量化平衡，便于向交管、城管展示数据；运营降本——减少人工申诉处理量，HOLD 样本可反哺信标补盲选址；教学科研——可复现场景库可直接用于课程与回归测试。落地成本上，算法运行在既有锁控/模组算力内，可选信标仅用于 HOLD 后的定点复核，部署密度可远低于全程定位。

### P23 章节扉页 06
- `title`: 挑战性和不确定性
- `type`: section ｜ `role`: transition ｜ `rhythm`: transition
- `layout`: 全幅图+骑线文字
- `visual`: L3: 章节大数字 06（≥120px）
- `visual_role`: atmosphere
- `density`: 字数约 70 / 图片 0 张 / 留白约 35%
- `anti_pattern`: 禁止四卡片预览；禁止铺满正文段落；禁止出现 "PART 06" 字样
- `description`: 大数字 06 + 章节标题 + 2–4 个要点。

### P24 边界、风险与后续工作
- `title`: 边界与不确定性（主动说明）
- `type`: content ｜ `role`: supporting ｜ `rhythm`: valley
- `layout`: 非对称双栏（65:35）
- `visual`: L2: 风险条目 + 缓解措施对照
- `visual_role`: evidence
- `density`: 字数约 270 / 图片 0 张 / 留白约 20%
- `anti_pattern`: 禁止左右等分双栏；禁止只列风险不给缓解路径；禁止把局限藏在小字里
- `description`: 科学层面——简化星座降低了几何真实性，绝对误差量级需结合实采数据再标定，因此结论强调相对改善而非绝对精度；技术层面——阈值过松则漏判违停增多、过严则大量进入不扣费，需按误扣/漏判权衡做 ROC 式运营标定；攻击层面——近公共偏差的慢拉欺骗可能被钟差吸收而漏检，需引入多特征或 INS 扩展；工程层面——板端数值与 PC 未完全对齐，金标准以 PC 为准；验证层面——尚未做实车与实采标定，当前阈值为演示值。

### P25 结束页
- `title`: 不可信，就不扣费
- `type`: ending ｜ `role`: hero ｜ `rhythm`: peak
- `layout`: 全屏视觉+大标题
- `visual`: L1: 巨型金句（≥60px）+ 核心数字 84%→11%
- `visual_role`: anchor
- `density`: 字数约 50 / 图片 0 张 / 留白约 35%
- `anti_pattern`: 禁止烟花、金装饰、印章；禁止出现"谢谢聆听"以外的冗余致谢堆砌
- `description`: 收束到一句话与一个数字：不可信，就不扣费；城市多径误扣费率 84% → 11%。谢谢各位评委。
