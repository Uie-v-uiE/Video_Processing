# routing report

provenance: graded by an agent shown SKILL.md only; predictions bound by table sha256
cases: routing_heldout.tsv
router rows parsed: 12
lexical scorer: bm25, background 12 files, pruned 25 terms: bash pynq python3 v3.1 一条 不是 使用 失效 已验 必须

## semantic (LLM router shown SKILL.md only) - the deployment path
positives=12 strict_top1=0.92 (11/12) acceptable_top1=0.92 (11/12) expected_in_top3=1.00 ambiguous_ties=0
negatives=2/2 refused
thresholds strict>=0.5 acceptable>=0.75 depth=3 -> PASS

- STRICT #0 `加载overlay后怎么确认每个IP的驱动真的绑上了` want=`references/overlay-load-and-verify.md` got=`references/overlay-load-and-verify.md`
  reason: 指南3.3.2“Overlay加载与校验”；README该条目范围＝加载比特流并证明IP驱动真的绑定
- STRICT #1 `register_map的基址偏移位段怎么从hwh里对出来` want=`references/register-map-from-hwh.md` got=`references/register-map-from-hwh.md`
  reason: 指南“寄存器映射与register_map使用范式”；条目范围＝基址、偏移、位段的取证与绑定生成
- STRICT #2 `axi_dma做大块搬运，缓存一致性封装有现成的吗` want=`references/dma-and-buffer-coherency.md` got=`references/dma-and-buffer-coherency.md`
  reason: 指南“DMA搬运与缓存一致性处理封装”；条目范围＝大块数据搬运与缓存一致性
- STRICT #3 `能不能拿hwh自动生成PS侧调用代码和测试骨架` want=`references/register-map-from-hwh.md` got=`references/register-map-from-hwh.md`
  reason: 指南“从接口契约自动生成主机侧调用代码或测试骨架”；README只把contract_gen.py索引在该条目下，无独立契约条目
- STRICT #4 `跑完要跟numpy黄金参考比对，性能资源数据自动采集出报告` want=`references/project-skeleton-and-metrics.md` got=`references/project-skeleton-and-metrics.md`
  reason: 指南“黄金参考比对、性能与资源数据自动采集报告”；golden_compare.py+measure_report.py两条命令均索引于该条目
- STRICT #5 `代码报no attribute，是不是抄了不存在的API名字` want=`references/pitfall-triage.md` got=`references/pitfall-triage.md`
  reason: 症状型：按README“踩坑清单＝pitfall-triage（症状→嫌疑→命令→判据）＋10条名字不存在”定位
- STRICT #6 `DMA传完读回来的还是上一帧的旧数据` want=`references/dma-and-buffer-coherency.md` got=`references/dma-and-buffer-coherency.md`
  reason: 症状型：读回旧数据即缓存一致性问题，落在该条目范围；pitfall-triage为次选路由
- STRICT #7 `pr_download不报错但寄存器写进去读回来全是0` want=`references/overlay-load-and-verify.md` got=`references/overlay-load-and-verify.md`
  reason: 症状型：加载静默成功而驱动未真正绑定，正是该条目“证明IP驱动真的绑定”的适用场景
- MISS    #8 `程序跑到DMA wait就挂死，重启板子才好` want=`references/pitfall-triage.md` got=`references/dma-and-buffer-coherency.md`
  reason: 症状型：未定位成因的挂死，陌生队伍按README索引只会先查11行症状表；确认是缓存/wait问题后才转DMA条目
- STRICT #9 `不知道功能放PS还是PL，HP和GP口的带宽账怎么算` want=`references/ps-pl-interface-choice.md` got=`references/ps-pl-interface-choice.md`
  reason: 流程型：软硬件划分依据与端口选择、带宽账，条目范围逐字对应
- STRICT #10 `实验室没外网，ssh上板还没权限，想在板上跑pytest` want=`references/board-access-and-self-test.md` got=`references/board-access-and-self-test.md`
  reason: 流程型：上板登录、权限、无网、板上pytest，条目范围逐字对应
- STRICT #11 `技能包和工程目录结构怎么摆，报告里的留痕和对比表怎么写` want=`references/project-skeleton-and-metrics.md` got=`references/project-skeleton-and-metrics.md`
  reason: 流程型：目录骨架、留痕约定、报告三段，即指南3.3.5.3报告要求；与黄金比对条目同源
- NEGATIVE #12 `Processing里pynq这个库串口读不到数据是不是波特率错了` top=`NONE` refused (good)
  reason: NEGATIVE：pynq是Processing/py端串口库名误写，与PYNQ框架和Zynq无关，本包任何条目都不适用
- NEGATIVE #13 `Vivado实现完setup违例-0.3ns，时序收敛有什么套路` top=`NONE` refused (good)
  reason: NEGATIVE：属Vivado综合实现与时序收敛方法学，README“局限”里明确声明本包不含，不得路由进来

## lexical (bm25) - lower bound, NOT the deployment path
positives=12 strict_top1=0.83 (10/12) acceptable_top1=0.83 (10/12) expected_in_top3=0.92 ambiguous_ties=0
negatives=2/2 refused
thresholds strict>=0.5 acceptable>=0.75 depth=3 -> FAIL [1 outside the top-3 view]

- MISS    #0 `加载overlay后怎么确认每个IP的驱动真的绑上了` want=`references/overlay-load-and-verify.md` got=`references/prompts-for-llm-collaboration.md` lex_score=1.964
  reason: 指南3.3.2“Overlay加载与校验”；README该条目范围＝加载比特流并证明IP驱动真的绑定
- STRICT #1 `register_map的基址偏移位段怎么从hwh里对出来` want=`references/register-map-from-hwh.md` got=`references/register-map-from-hwh.md` lex_score=6.185
  reason: 指南“寄存器映射与register_map使用范式”；条目范围＝基址、偏移、位段的取证与绑定生成
- STRICT #2 `axi_dma做大块搬运，缓存一致性封装有现成的吗` want=`references/dma-and-buffer-coherency.md` got=`references/dma-and-buffer-coherency.md` lex_score=6.475
  reason: 指南“DMA搬运与缓存一致性处理封装”；条目范围＝大块数据搬运与缓存一致性
- STRICT #3 `能不能拿hwh自动生成PS侧调用代码和测试骨架` want=`references/register-map-from-hwh.md` got=`references/register-map-from-hwh.md` lex_score=16.798
  reason: 指南“从接口契约自动生成主机侧调用代码或测试骨架”；README只把contract_gen.py索引在该条目下，无独立契约条目
- STRICT #4 `跑完要跟numpy黄金参考比对，性能资源数据自动采集出报告` want=`references/project-skeleton-and-metrics.md` got=`references/project-skeleton-and-metrics.md` lex_score=23.506
  reason: 指南“黄金参考比对、性能与资源数据自动采集报告”；golden_compare.py+measure_report.py两条命令均索引于该条目
- STRICT #5 `代码报no attribute，是不是抄了不存在的API名字` want=`references/pitfall-triage.md` got=`references/pitfall-triage.md` lex_score=14.625
  reason: 症状型：按README“踩坑清单＝pitfall-triage（症状→嫌疑→命令→判据）＋10条名字不存在”定位
- STRICT #6 `DMA传完读回来的还是上一帧的旧数据` want=`references/dma-and-buffer-coherency.md` got=`references/dma-and-buffer-coherency.md` lex_score=12.600
  reason: 症状型：读回旧数据即缓存一致性问题，落在该条目范围；pitfall-triage为次选路由
- STRICT #7 `pr_download不报错但寄存器写进去读回来全是0` want=`references/overlay-load-and-verify.md` got=`references/overlay-load-and-verify.md` lex_score=19.004
  reason: 症状型：加载静默成功而驱动未真正绑定，正是该条目“证明IP驱动真的绑定”的适用场景
- ABSENT #8 `程序跑到DMA wait就挂死，重启板子才好` want=`references/pitfall-triage.md` got=`references/dma-and-buffer-coherency.md` lex_score=3.759
  reason: 症状型：未定位成因的挂死，陌生队伍按README索引只会先查11行症状表；确认是缓存/wait问题后才转DMA条目
- STRICT #9 `不知道功能放PS还是PL，HP和GP口的带宽账怎么算` want=`references/ps-pl-interface-choice.md` got=`references/ps-pl-interface-choice.md` lex_score=12.740
  reason: 流程型：软硬件划分依据与端口选择、带宽账，条目范围逐字对应
- STRICT #10 `实验室没外网，ssh上板还没权限，想在板上跑pytest` want=`references/board-access-and-self-test.md` got=`references/board-access-and-self-test.md` lex_score=6.150
  reason: 流程型：上板登录、权限、无网、板上pytest，条目范围逐字对应
- STRICT #11 `技能包和工程目录结构怎么摆，报告里的留痕和对比表怎么写` want=`references/project-skeleton-and-metrics.md` got=`references/project-skeleton-and-metrics.md` lex_score=6.112
  reason: 流程型：目录骨架、留痕约定、报告三段，即指南3.3.5.3报告要求；与黄金比对条目同源
- NEGATIVE #12 `Processing里pynq这个库串口读不到数据是不是波特率错了` top=`references/overlay-load-and-verify.md` LEAKED (bad)
  reason: NEGATIVE：pynq是Processing/py端串口库名误写，与PYNQ框架和Zynq无关，本包任何条目都不适用
- NEGATIVE #13 `Vivado实现完setup违例-0.3ns，时序收敛有什么套路` top=`references/offline-verification.md` LEAKED (bad)
  reason: NEGATIVE：属Vivado综合实现与时序收敛方法学，README“局限”里明确声明本包不含，不得路由进来

