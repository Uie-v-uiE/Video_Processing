# routing report

provenance: blind hold-out authored later by a session that never opened the entries, paraphrased to avoid the router's terminology.
cases: routing_heldout2.tsv
router rows parsed: 12
lexical scorer: bm25, background 12 files, pruned 25 terms: bash pynq python3 v3.1 一条 不是 使用 失效 已验 必须

## lexical (bm25) - lower bound, NOT the deployment path
positives=14 strict_top1=1.00 (14/14) acceptable_top1=1.00 (14/14) expected_in_top3=1.00 ambiguous_ties=0
negatives=2/2 refused
thresholds strict>=0.5 acceptable>=0.75 depth=3 -> PASS

- STRICT #0 `vivado 导出的 bit 和 hwh 拷到板上，jupyter 里按块设计的` want=`references/overlay-load-and-verify.md` got=`references/overlay-load-and-verify.md` lex_score=51.794 alt=references/pitfall-triage.md
  reason: 指南 3.3.2 通用 Skill 例「通用的 Overlay 加载与校验流程」；路由行「Overlay() 加载、.bit/.hwh 配对、ip_dict」的配对失败。ALT:references/pitfall-triage.md（该行含「no attribute、抄了不存在的 API、报错原文逐字定位」，报错原文两边都答得上）
- STRICT #1 `自造 IP 挂在 s_axi 上，上位机写寄存器想打开某个通道，偏移是 0x0 ` want=`references/register-map-from-hwh.md` got=`references/register-map-from-hwh.md` lex_score=44.764 alt=references/overlay-load-and-verify.md
  reason: 3.3.2「寄存器映射与 register_map 使用范式」；路由行「基址/偏移/位段从哪来、MMIO 边界」。ALT:references/overlay-load-and-verify.md（该行也写「写进去读回来全是 0」，若实为没加载成功则归它）
- STRICT #2 `hwh 那坨 xml 人肉读不动，能不能有个东西把里面每个外设的寄存器直接吐成上` want=`references/register-map-from-hwh.md` got=`references/register-map-from-hwh.md` lex_score=20.352 alt=references/design-to-bitstream-hwh.md
  reason: 3.3.2「从接口契约自动生成主机侧调用代码或测试骨架的脚本」；路由行「从接口契约（.hwh）自动生成主机侧调用代码、C 头文件与测试骨架（contract_gen.py）」。ALT:references/design-to-bitstream-hwh.md（先要导出件里的地址段与寄存器验收）
- STRICT #3 `dma 一次性搬一整帧 1080p 直接抛异常嫌太大，拆成五十几 K 又说要按倍` want=`references/dma-and-buffer-coherency.md` got=`references/dma-and-buffer-coherency.md` lex_score=38.381
  reason: 路由行「DMA 搬运、对齐、buffer_max_size、分块」；3.3.2「可复用的 DMA 搬运…含常见出错情形的定位方法」。以「嫌太大／按倍数对齐／尾巴那截」代替术语
- STRICT #4 `下位机那边算完了、标志位也置了，上位机拿回来的却还是上一次那批数，非得手动刷一道` want=`references/dma-and-buffer-coherency.md` got=`references/dma-and-buffer-coherency.md` lex_score=33.311
  reason: 路由行「allocate 与缓存一致性…读回旧帧/脏数据」；3.3.2「缓存一致性处理封装」。症状表述完全改写为「拿回来还是上一次那批数」
- STRICT #5 `流式接口最后一拍忘了拉那个「结束」信号，程序就死在那句等它传完上，界面整个卡住，` want=`references/dma-and-buffer-coherency.md` got=`references/dma-and-buffer-coherency.md` lex_score=22.618 alt=references/design-to-bitstream-hwh.md
  reason: 路由行「TLAST…wait() 挂死」；3.3.2 出错情形定位法。ALT:references/design-to-bitstream-hwh.md（该行也列「流接口 TLAST」，接线属设计侧、等死属主机侧，两侧都能答）
- STRICT #6 `到底哪块扔 PL 哪块留 PS 组里吵翻了：一边说卷积放里面，一边说还得跑网口往` want=`references/ps-pl-interface-choice.md` got=`references/ps-pl-interface-choice.md` lex_score=56.491
  reason: 3.3.2「可以把精力集中在软硬件划分」并鼓励软硬件协同；3.3.5.3 报告须含「软硬件划分依据与接口设计」；路由行「这段放 PS 还是 PL、HP/GP/ACP 选哪个、带宽账怎么写」
- STRICT #7 `想用 PL 上那几根口读一路开关，可配了读出来永远是高，说是有个方向的东西没设；` want=`references/gpio-iic-and-interrupt.md` got=`references/gpio-iic-and-interrupt.md` lex_score=81.587
  reason: 路由行「需要 PL 侧并行 IO、方向掩码、I2C 外设或 PL 中断通知 PS（控制/采集类题目）」；用「自己敲时钟」「让 ARM 收到、不轮询」代替 I2C／中断字样
- STRICT #8 `网线直连电脑 ssh 进去是板子上那个普通号，跑我们的脚本一路 permissi` want=`references/board-access-and-self-test.md` got=`references/board-access-and-self-test.md` lex_score=50.234
  reason: 路由行「上板登录、权限、无网、板上 pytest、实测数据留存」；3.3.3.2「作品须在板上跑通并提供实测输出」
- STRICT #9 `用例全写在 test_ 开头那几个 py 里，想在板子里自己跑一遍，用管理员那个` want=`references/board-access-and-self-test.md` got=`references/board-access-and-self-test.md` lex_score=23.205 alt=references/project-skeleton-and-metrics.md
  reason: 路由行「板上 pytest」；3.3.5.2 以「陌生队伍拿到能否直接用」为准。ALT:references/project-skeleton-and-metrics.md（该行「构建与上板留痕」也覆盖跑测留痕）
- STRICT #10 `把板上吐出来的结果存成一个文件，跟 matlab 那边算好的期望值对，有人说差三` want=`references/project-skeleton-and-metrics.md` got=`references/project-skeleton-and-metrics.md` lex_score=25.689 alt=references/offline-verification.md
  reason: 3.3.5.2「校验脚本：自动比对黄金参考」；3.3.5.1 提交含「实测输出与参考结果的比对数据」；路由行「黄金参考比对（golden_compare.py，容差/豁免/失效豁免）」。ALT:references/offline-verification.md（手上没板时先在桩件上比）
- STRICT #11 `报告里那张表要帧率、LUT 占了多少、还有最差那条负裕量，现在手抄进 word，` want=`references/project-skeleton-and-metrics.md` got=`references/project-skeleton-and-metrics.md` lex_score=41.581
  reason: 3.3.5.3「优化前后的性能与资源对比表」；路由行「性能与资源数据自动采集并成表（measure_report.py）」，其「占位值、缺失指标不会被当成通过」正对应画横杠
- STRICT #12 `第一次交东西，仓库里中文文件夹、带空格的文件名、「最终版(2)」全齐了，听说目录` want=`references/project-skeleton-and-metrics.md` got=`references/project-skeleton-and-metrics.md` lex_score=12.536
  reason: 3.3.5.4「所有目录名与文件名须使用纯英文…不得出现中文、空格或特殊字符」；路由行「工程目录骨架、构建与上板留痕、报告三段」；3.3.5.2「案例模板：可被下一个题目直接套用的工程骨架」
- STRICT #13 `跟着教程刷了 4.0 的卡，结果 jupyter 里连我们这块板型号的板级定义都` want=`references/design-to-bitstream-hwh.md` got=`references/design-to-bitstream-hwh.md` lex_score=29.322 alt=references/sources.md
  reason: 路由行「板文件与器件字符串」（Z2 在 4.0 被移除即落在板级定义/器件字符串上）；3.3.3.1 版本须说明并保证脚本可复现。ALT:references/sources.md（该行「文档与源码冲突、未证实项」是版本断言的出处）
- NEGATIVE #14 `我们用 f407 那块小板的硬件 i2c 读 mpu6050，HAL 那个读函数` top=`references/gpio-iic-and-interrupt.md` LEAKED (bad)
  reason: 3.3.2 只把 PYNQ/Zynq 的 Overlay、register_map、DMA 列为方向；路由行的 I2C 限定「PL 侧…I2C 外设」，STM32 HAL 属另一 MCU 生态，本包不答。i2c 词面最易被误路由到 gpio-iic-and-interrupt
- NEGATIVE #15 `实现完了时序没收住，最差 slack -0.3，报告里一堆 setup 违例，有` top=`references/sources.md` LEAKED (bad)
  reason: 本包自述不适用「Vivado 综合/实现的收敛技巧、约束写法本身（用 UG901/UG904/UG949）」；3.3.2 的设计任务是板级软硬件协同而非收敛。负例，易被「裕量／综合报告」词面误路由到 project-skeleton-and-metrics

