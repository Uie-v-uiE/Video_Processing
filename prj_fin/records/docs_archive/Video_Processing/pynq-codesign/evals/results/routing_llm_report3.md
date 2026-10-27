# routing report

provenance: graded by an agent shown SKILL.md only
cases: routing_heldout3.tsv
router rows parsed: 12
lexical scorer: bm25, background 12 files, pruned 25 terms: bash pynq python3 v3.1 一条 不是 使用 失效 已验 必须

## semantic (LLM router shown SKILL.md only) - the deployment path
positives=18 strict_top1=0.89 (16/18) acceptable_top1=0.94 (17/18) expected_in_top3=1.00 ambiguous_ties=0
negatives=2/2 refused
thresholds strict>=0.5 acceptable>=0.75 depth=3 -> PASS

- STRICT #0 `板子上两半各干各的活，我这边明明先把一批数写进那块共用的内存了，逻辑跑完打印出来` want=`references/dma-and-buffer-coherency.md` got=`references/dma-and-buffer-coherency.md`
  reason: 对应 3.3.2「可复用的 DMA 搬运与缓存一致性处理封装，含常见出错情形的定位方法」：PS 侧写入后可编程逻辑读到旧数据，是共享缓冲区一侧未回写、另一侧仍用留底的典型症状，归搬运与缓冲区这条链；不涉及装载或地址推导，故不选装载校验与地址表两条。
- STRICT #1 `这次交上去的那份硬件成品跟上礼拜的不是一版了，我还按老步骤装载，装完第一个读参数` want=`references/overlay-load-and-verify.md` got=`references/overlay-load-and-verify.md` alt=references/design-to-bitstream-hwh.md
  reason: 对应 3.3.2「通用的 Overlay 加载与校验流程」：诉求是不与题目绑定的装载后确认步骤。ALT:references/design-to-bitstream-hwh.md（症状也可能出在产出那份成品时版本没导对，先排产线也讲得通）。
- STRICT #2 `换了实验室那台机器连板子，网页端打得开但终端里一路 permission den` want=`references/board-access-and-self-test.md` got=`references/board-access-and-self-test.md`
  reason: 对应 3.3.3.2「作品须在板上跑通并提供实测输出」与 3.3.5.4 的 board/ 上板环节：先把账号权限和硬件故障分开，属上板准入自检，早于任何搬运与地址逻辑，因此优于通用排查清单那条。
- STRICT #3 `我照连线图里那个方框的名字去取模块，程序偏说没这个名字，可我明明看见它有；地址还` want=`references/register-map-from-hwh.md` got=`references/register-map-from-hwh.md` alt=references/design-to-bitstream-hwh.md
  reason: 对应 3.3.2「寄存器映射与 register_map 使用范式」：按块设计里的实例名去拿、以及各段起始偏移，都应由工具导出的连接描述推得而非手算。ALT:references/design-to-bitstream-hwh.md（那份描述本身怎么产出也是本题缺的一环）。
- STRICT #4 `板子这礼拜被隔壁组整个借走了，我报告不能空着，想先在电脑上把可编程逻辑那半边的行` want=`references/offline-verification.md` got=`references/offline-verification.md` alt=references/project-skeleton-and-metrics.md
  reason: 对应 3.3.5.1「仿真或验证结果，说明功能正确性是如何确认的」，同时受 3.3.3.2「须在板上跑通并提供实测输出」约束：问的正是无板条件下的离线验证与其证据边界。ALT:references/project-skeleton-and-metrics.md（结论如何落进报告与目录也要那条支撑）。
- STRICT #5 `要把仓库整一遍交上去，同学把测试数据丢进了一个名字带中文还带空格的文件夹，我这头` want=`references/project-skeleton-and-metrics.md` got=`references/project-skeleton-and-metrics.md`
  reason: 对应 3.3.5.4「所有目录名与文件名须使用纯英文……不得出现中文、空格或特殊字符」与 3.3.5.3「优化过程，含优化前后的性能与资源对比表」：命名禁忌加表格模板两条要求都落在骨架与指标这一条目上，别人只会更窄。
- ALT     #6 `一上板就停在等传输结束那一句，永远等不到，上回改了下地址对齐就通了，这回同样的改` want=`references/pitfall-triage.md` got=`references/dma-and-buffer-coherency.md` alt=references/dma-and-buffer-coherency.md
  reason: 对应 3.3.5.2「踩坑清单：结构化整理的常见错误与定位方法，含触发条件与排查步骤」：要的对象是排查顺序本身而非某一具体机制。ALT:references/dma-and-buffer-coherency.md（同一句等待也常被直接归到搬运机制里讲，根因大概率在那）。
- STRICT #7 `我让大模型帮我写调那块硬件的代码，它给的函数名我查不到还特别自信，有没有一种固定` want=`references/prompts-for-llm-collaboration.md` got=`references/prompts-for-llm-collaboration.md` alt=references/sources.md
  reason: 对应 3.3.5.3「大模型协作记录：提示词、模型回答、自我纠错轨迹」与 3.3.5.2「提示词工作流」：要的是一套能稳定抑制编造接口的提问模板并留下可提交轨迹。ALT:references/sources.md（先报出处这一半与主张来源登记那条确有重叠）。
- STRICT #8 `我挂在可编程逻辑那半边的二线串行口，示波器上时钟是有的，就是等不到应答，旁边那根` want=`references/gpio-iic-and-interrupt.md` got=`references/gpio-iic-and-interrupt.md`
  reason: 对应 3.3.1「综合运用……接口协议与软硬件协同」：有波形无应答加事件线不跳变，属可编程逻辑侧串行外设与中断引出的联合判断，比通用清单更具体，故归此条。
- STRICT #9 `图形界面里模块连完也综合过了，可要把这份硬件的东西交给上面那半边用的时候，我手上` want=`references/design-to-bitstream-hwh.md` got=`references/design-to-bitstream-hwh.md` alt=references/register-map-from-hwh.md
  reason: 对应 3.3.2 软硬件协同与 3.3.5.1「完整的工程文件与源码」：从设计走完综合实现并一并导出连接描述，是这条流水线的终点问题。ALT:references/register-map-from-hwh.md（拿到那文件之后读地址表是另一条的活）。
- STRICT #10 `算法切哪一半我一直拿不定主意，想留在可编程逻辑里，可每秒要过的数据太多，不确定那` want=`references/ps-pl-interface-choice.md` got=`references/ps-pl-interface-choice.md` alt=references/project-skeleton-and-metrics.md
  reason: 对应 3.3.5.3「软硬件划分依据与接口设计」与 3.3.4「取得可测量的性能表现，并给出与基线的对比」：核心是切分点与通道带宽的量化取舍。ALT:references/project-skeleton-and-metrics.md（算出的数要落成报告对比表还得靠那条模板）。
- STRICT #11 `一整幅画面一次性递过去，工具说共用区的起始地址和每回递的长度都得按倍数摆整齐，不` want=`references/dma-and-buffer-coherency.md` got=`references/dma-and-buffer-coherency.md`
  reason: 对应 3.3.2「可复用的 DMA 搬运与缓存一致性处理封装」：对齐要求、结束标志、缓冲区申请三点同属搬运封装的约束，收在这条最完整；地址推导只是它的输入，所以不归寄存器映射。
- STRICT #12 `同一份东西第一次在网页本子里跑得好好的，重开一下再跑第二遍就说那玩意儿已经被占着` want=`references/overlay-load-and-verify.md` got=`references/overlay-load-and-verify.md`
  reason: 对应 3.3.2「通用的 Overlay 加载与校验流程」：反复装载需先释放再重载并校验，是装载流程本身；板卡自检那条讲的是登录与权限，不涉及占用与释放，故不选。
- STRICT #13 `队友说他有块外设的起始位置跟手册上印的对不上，我把那张连接图导出来一看，地址段全` want=`references/register-map-from-hwh.md` got=`references/register-map-from-hwh.md`
  reason: 对应 3.3.2「寄存器映射与 register_map 使用范式」加 3.3.5.2「校验脚本」：地址由工具分配，必须由导出描述取表并自动核对，而不是照手册硬写；产表过程属另一条，本题已假设有表。
- STRICT #14 `板子连不上我们校园网那个认证，装东西的命令全在超时，我只能从自己电脑上往外塞依赖` want=`references/board-access-and-self-test.md` got=`references/board-access-and-self-test.md` alt=references/project-skeleton-and-metrics.md
  reason: 对应 3.3.3.2 板级验证与 3.3.4「保证工程可由他人从零复现」：无网环境下的登录、依赖投递与离线可用属板卡访问与自检范围。ALT:references/project-skeleton-and-metrics.md（离线复现步骤最终要落进 README 与目录对照那条）。
- STRICT #15 `每次跑完的数我都手抄进文档，抄三回错了两回，评委肯定不信手抄的，有没有办法让占用` want=`references/project-skeleton-and-metrics.md` got=`references/project-skeleton-and-metrics.md`
  reason: 对应 3.3.5.2「性能与资源数据自动采集并生成报告的工具」与 3.3.5.3「优化前后对比表」：自动采集、成表、留痕三项要求都归骨架与指标条目；数据来源可信度问题不是版本主张，故不选出处那条。
- MISS    #16 `算法这边我另写了一份独立的实现当标准答案，想在不接板子的情况下把回头采到的结果跟` want=`references/offline-verification.md` got=`references/project-skeleton-and-metrics.md` alt=references/dma-and-buffer-coherency.md
  reason: 对应 3.3.5.2「校验脚本：自动比对黄金参考」与 3.3.5.1「仿真或验证结果」：黄金参考在无板条件下的比对规则。ALT:references/dma-and-buffer-coherency.md（长度飘也可能是搬运分段没收尾的症状，两条都站得住）。
- STRICT #17 `我在文档里写我们用的是新版接口，队友装的环境跑出来却不一样，评委要是追问我凭什么` want=`references/sources.md` got=`references/sources.md`
  reason: 对应 3.3.3.1「如使用其他版本需在报告中说明并保证脚本可复现」与 3.3.4「将设计过程中的判断依据写进报告」：主张与版本出处的登记归此条；协作过程的提问模板属提示词那条，本题问的是凭据不是问法。
- NEGATIVE #18 `我们另有一块小单片机是别家的片子，库里那个两线主机初始化完老是不产生起始条件，逻` top=`NONE` refused (good)
  reason: 超范围：3.3.1.1 与 3.3.3.2 把器件限定在 AMD 7 系列、Zynq-7000、UltraScale 及以上，且 3.3.2、3.3.5.2 的通用 Skill 明确面向 PYNQ 框架；非 AMD 单片机自带外设库的初始化与硬件上拉不在本目录覆盖内。表面同样带『二线串行』『应答』等词，容易误路由，正解应留空。
- NEGATIVE #19 `综合完出来一堆时序违例，最长那条路径还差零点三纳秒，我想知道那个多周期约束在约束` top=`NONE` refused (good)
  reason: 超范围：初级组虽把时序约束列为考察侧重（3.3.1.1），但 3.3.2 列举的通用 PYNQ Skill 类别是装载校验、寄存器映射、DMA 封装与主机侧代码生成，不含 Vivado 静态时序收敛方法与约束文件语法；3.3.7 把这类内容指向 UG901、UG904、UG949 外部文档。含『综合』『报告』等词易被过度热心地误配到本目录。

## lexical (bm25) - lower bound, NOT the deployment path
positives=18 strict_top1=0.50 (9/18) acceptable_top1=0.56 (10/18) expected_in_top3=0.67 ambiguous_ties=0
negatives=1/2 refused
thresholds strict>=0.5 acceptable>=0.75 depth=3 -> FAIL [acceptable 0.56<0.75; 6 outside the top-3 view; 1 negative leaked into an answer]

- STRICT #0 `板子上两半各干各的活，我这边明明先把一批数写进那块共用的内存了，逻辑跑完打印出来` want=`references/dma-and-buffer-coherency.md` got=`references/dma-and-buffer-coherency.md` lex_score=13.368
  reason: 对应 3.3.2「可复用的 DMA 搬运与缓存一致性处理封装，含常见出错情形的定位方法」：PS 侧写入后可编程逻辑读到旧数据，是共享缓冲区一侧未回写、另一侧仍用留底的典型症状，归搬运与缓冲区这条链；不涉及装载或地址推导，故不选装载校验与地址表两条。
- MISS    #1 `这次交上去的那份硬件成品跟上礼拜的不是一版了，我还按老步骤装载，装完第一个读参数` want=`references/overlay-load-and-verify.md` got=`references/gpio-iic-and-interrupt.md` lex_score=2.029 alt=references/design-to-bitstream-hwh.md
  reason: 对应 3.3.2「通用的 Overlay 加载与校验流程」：诉求是不与题目绑定的装载后确认步骤。ALT:references/design-to-bitstream-hwh.md（症状也可能出在产出那份成品时版本没导对，先排产线也讲得通）。
- STRICT #2 `换了实验室那台机器连板子，网页端打得开但终端里一路 permission den` want=`references/board-access-and-self-test.md` got=`references/board-access-and-self-test.md` lex_score=9.255
  reason: 对应 3.3.3.2「作品须在板上跑通并提供实测输出」与 3.3.5.4 的 board/ 上板环节：先把账号权限和硬件故障分开，属上板准入自检，早于任何搬运与地址逻辑，因此优于通用排查清单那条。
- ABSENT #3 `我照连线图里那个方框的名字去取模块，程序偏说没这个名字，可我明明看见它有；地址还` want=`references/register-map-from-hwh.md` got=`references/gpio-iic-and-interrupt.md` lex_score=2.681 alt=references/design-to-bitstream-hwh.md
  reason: 对应 3.3.2「寄存器映射与 register_map 使用范式」：按块设计里的实例名去拿、以及各段起始偏移，都应由工具导出的连接描述推得而非手算。ALT:references/design-to-bitstream-hwh.md（那份描述本身怎么产出也是本题缺的一环）。
- STRICT #4 `板子这礼拜被隔壁组整个借走了，我报告不能空着，想先在电脑上把可编程逻辑那半边的行` want=`references/offline-verification.md` got=`references/offline-verification.md` lex_score=3.170 alt=references/project-skeleton-and-metrics.md
  reason: 对应 3.3.5.1「仿真或验证结果，说明功能正确性是如何确认的」，同时受 3.3.3.2「须在板上跑通并提供实测输出」约束：问的正是无板条件下的离线验证与其证据边界。ALT:references/project-skeleton-and-metrics.md（结论如何落进报告与目录也要那条支撑）。
- ABSENT #5 `要把仓库整一遍交上去，同学把测试数据丢进了一个名字带中文还带空格的文件夹，我这头` want=`references/project-skeleton-and-metrics.md` got=`references/board-access-and-self-test.md` lex_score=4.105
  reason: 对应 3.3.5.4「所有目录名与文件名须使用纯英文……不得出现中文、空格或特殊字符」与 3.3.5.3「优化过程，含优化前后的性能与资源对比表」：命名禁忌加表格模板两条要求都落在骨架与指标这一条目上，别人只会更窄。
- ABSENT #6 `一上板就停在等传输结束那一句，永远等不到，上回改了下地址对齐就通了，这回同样的改` want=`references/pitfall-triage.md` got=`references/dma-and-buffer-coherency.md` lex_score=2.243 alt=references/dma-and-buffer-coherency.md
  reason: 对应 3.3.5.2「踩坑清单：结构化整理的常见错误与定位方法，含触发条件与排查步骤」：要的对象是排查顺序本身而非某一具体机制。ALT:references/dma-and-buffer-coherency.md（同一句等待也常被直接归到搬运机制里讲，根因大概率在那）。
- STRICT #7 `我让大模型帮我写调那块硬件的代码，它给的函数名我查不到还特别自信，有没有一种固定` want=`references/prompts-for-llm-collaboration.md` got=`references/prompts-for-llm-collaboration.md` lex_score=9.979 alt=references/sources.md
  reason: 对应 3.3.5.3「大模型协作记录：提示词、模型回答、自我纠错轨迹」与 3.3.5.2「提示词工作流」：要的是一套能稳定抑制编造接口的提问模板并留下可提交轨迹。ALT:references/sources.md（先报出处这一半与主张来源登记那条确有重叠）。
- STRICT #8 `我挂在可编程逻辑那半边的二线串行口，示波器上时钟是有的，就是等不到应答，旁边那根` want=`references/gpio-iic-and-interrupt.md` got=`references/gpio-iic-and-interrupt.md` lex_score=4.710
  reason: 对应 3.3.1「综合运用……接口协议与软硬件协同」：有波形无应答加事件线不跳变，属可编程逻辑侧串行外设与中断引出的联合判断，比通用清单更具体，故归此条。
- STRICT #9 `图形界面里模块连完也综合过了，可要把这份硬件的东西交给上面那半边用的时候，我手上` want=`references/design-to-bitstream-hwh.md` got=`references/design-to-bitstream-hwh.md` lex_score=10.442 alt=references/register-map-from-hwh.md
  reason: 对应 3.3.2 软硬件协同与 3.3.5.1「完整的工程文件与源码」：从设计走完综合实现并一并导出连接描述，是这条流水线的终点问题。ALT:references/register-map-from-hwh.md（拿到那文件之后读地址表是另一条的活）。
- STRICT #10 `算法切哪一半我一直拿不定主意，想留在可编程逻辑里，可每秒要过的数据太多，不确定那` want=`references/ps-pl-interface-choice.md` got=`references/ps-pl-interface-choice.md` lex_score=5.292 alt=references/project-skeleton-and-metrics.md
  reason: 对应 3.3.5.3「软硬件划分依据与接口设计」与 3.3.4「取得可测量的性能表现，并给出与基线的对比」：核心是切分点与通道带宽的量化取舍。ALT:references/project-skeleton-and-metrics.md（算出的数要落成报告对比表还得靠那条模板）。
- STRICT #11 `一整幅画面一次性递过去，工具说共用区的起始地址和每回递的长度都得按倍数摆整齐，不` want=`references/dma-and-buffer-coherency.md` got=`references/dma-and-buffer-coherency.md` lex_score=6.760
  reason: 对应 3.3.2「可复用的 DMA 搬运与缓存一致性处理封装」：对齐要求、结束标志、缓冲区申请三点同属搬运封装的约束，收在这条最完整；地址推导只是它的输入，所以不归寄存器映射。
- ABSENT #12 `同一份东西第一次在网页本子里跑得好好的，重开一下再跑第二遍就说那玩意儿已经被占着` want=`references/overlay-load-and-verify.md` got=`references/gpio-iic-and-interrupt.md` lex_score=3.062
  reason: 对应 3.3.2「通用的 Overlay 加载与校验流程」：反复装载需先释放再重载并校验，是装载流程本身；板卡自检那条讲的是登录与权限，不涉及占用与释放，故不选。
- ABSENT #13 `队友说他有块外设的起始位置跟手册上印的对不上，我把那张连接图导出来一看，地址段全` want=`references/register-map-from-hwh.md` got=`references/overlay-load-and-verify.md` lex_score=3.366
  reason: 对应 3.3.2「寄存器映射与 register_map 使用范式」加 3.3.5.2「校验脚本」：地址由工具分配，必须由导出描述取表并自动核对，而不是照手册硬写；产表过程属另一条，本题已假设有表。
- MISS    #14 `板子连不上我们校园网那个认证，装东西的命令全在超时，我只能从自己电脑上往外塞依赖` want=`references/board-access-and-self-test.md` got=`references/design-to-bitstream-hwh.md` lex_score=9.293 alt=references/project-skeleton-and-metrics.md
  reason: 对应 3.3.3.2 板级验证与 3.3.4「保证工程可由他人从零复现」：无网环境下的登录、依赖投递与离线可用属板卡访问与自检范围。ALT:references/project-skeleton-and-metrics.md（离线复现步骤最终要落进 README 与目录对照那条）。
- MISS    #15 `每次跑完的数我都手抄进文档，抄三回错了两回，评委肯定不信手抄的，有没有办法让占用` want=`references/project-skeleton-and-metrics.md` got=`references/offline-verification.md` lex_score=6.044
  reason: 对应 3.3.5.2「性能与资源数据自动采集并生成报告的工具」与 3.3.5.3「优化前后对比表」：自动采集、成表、留痕三项要求都归骨架与指标条目；数据来源可信度问题不是版本主张，故不选出处那条。
- ABSENT #16 `算法这边我另写了一份独立的实现当标准答案，想在不接板子的情况下把回头采到的结果跟` want=`references/offline-verification.md` got=`references/overlay-load-and-verify.md` lex_score=8.436 alt=references/dma-and-buffer-coherency.md
  reason: 对应 3.3.5.2「校验脚本：自动比对黄金参考」与 3.3.5.1「仿真或验证结果」：黄金参考在无板条件下的比对规则。ALT:references/dma-and-buffer-coherency.md（长度飘也可能是搬运分段没收尾的症状，两条都站得住）。
- STRICT #17 `我在文档里写我们用的是新版接口，队友装的环境跑出来却不一样，评委要是追问我凭什么` want=`references/sources.md` got=`references/sources.md` lex_score=8.932
  reason: 对应 3.3.3.1「如使用其他版本需在报告中说明并保证脚本可复现」与 3.3.4「将设计过程中的判断依据写进报告」：主张与版本出处的登记归此条；协作过程的提问模板属提示词那条，本题问的是凭据不是问法。
- NEGATIVE #18 `我们另有一块小单片机是别家的片子，库里那个两线主机初始化完老是不产生起始条件，逻` top=`references/board-access-and-self-test.md` LEAKED (bad)
  reason: 超范围：3.3.1.1 与 3.3.3.2 把器件限定在 AMD 7 系列、Zynq-7000、UltraScale 及以上，且 3.3.2、3.3.5.2 的通用 Skill 明确面向 PYNQ 框架；非 AMD 单片机自带外设库的初始化与硬件上拉不在本目录覆盖内。表面同样带『二线串行』『应答』等词，容易误路由，正解应留空。
- NEGATIVE #19 `综合完出来一堆时序违例，最长那条路径还差零点三纳秒，我想知道那个多周期约束在约束` top=`references/ps-pl-interface-choice.md` LEAKED (bad)
  reason: 超范围：初级组虽把时序约束列为考察侧重（3.3.1.1），但 3.3.2 列举的通用 PYNQ Skill 类别是装载校验、寄存器映射、DMA 封装与主机侧代码生成，不含 Vivado 静态时序收敛方法与约束文件语法；3.3.7 把这类内容指向 UG901、UG904、UG949 外部文档。含『综合』『报告』等词易被过度热心地误配到本目录。

