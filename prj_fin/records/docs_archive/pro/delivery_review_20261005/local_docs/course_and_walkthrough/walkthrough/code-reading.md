# code-reading.md · 本工程的写法逐行讲

读完这篇能回答哪三个问题：

1. 本工程里那五种关键形状（状态机 / 握手 / 跨时钟域 / 存储读写 / 计数器与边界）各自长在哪几行、逐行在干什么？
2. 把某一行删掉，从代码本身能推出什么后果（不是"会变差"，而是"哪一个条件恒真或恒假"）？
3. 拿到一份没见过的 Verilog，怎么用这 8 段的读法自己把它拆成这五种形状？

## 目录

- 第 1 节 这一篇的用法：读一段代码的固定六问
- 第 2 节 片段 1 · UDP 包头的四拍移位状态机（`src/rtl/eth/frame_reasm.v:121`）
- 第 3 节 片段 2 · 两个饱和计数与"末字节补偿"（`src/rtl/eth/frame_reasm.v:60`）
- 第 4 节 片段 3 · 格雷码指针与满/空判据（`src/rtl/eth/dc_fifo.v:45`）
- 第 5 节 片段 4 · 二进制指针不跨域、格雷码指针打两拍（`src/rtl/eth/dc_fifo.v:81`）
- 第 6 节 片段 5 · 单帧提交事件跨域（`src/rtl/eth/ddr_bank_commit.v:36`）
- 第 7 节 片段 6 · AXI 读通道的 valid/ready 与在途额度（`src/rtl/axi/axi_frame_writer_gated.v:75`）
- 第 8 节 片段 7 · 行环形缓存的读写与行消隐边界（`src/rtl/video/raw_line_delay.v:73`）
- 第 9 节 片段 8 · 扫描计数器与端点夹紧（`src/rtl/video/split_ctrl.v:67`）
- 第 10 节 辨认方法：这五种形状在陌生代码里怎么认
- 第 11 节 小结与下一步
- 第 12 节 自测题

## 第 1 节 这一篇的用法：读一段代码的固定六问

这一篇只讲**写法**：每段代码先原样抄出来（与源文件逐字一致，行号就是源文件的行号），再逐行说
"这行做什么 / 为什么这么写 / 删掉会怎样"。模块的职责与层次在 `subsystem-map.md`，
一次真实处理的时间顺序在 `one-pass-walk.md`，接口取值在 `interface-contract.md`，
跨域形态的完整清单在 `clocking-and-reset.md` 第 3 节 —— 那四篇的口径本篇不重复抄，
只把它们指过的行**逐行念一遍**。

通用原理（为什么格雷码能跨、为什么亚稳态消不掉）不在这一篇：讲机制的在 `mechanics.md`
（格雷码与亚稳是它的第 3 节、存储推断是第 4 节、握手是第 1 节），讲"下一层去哪儿补"的在 `next-layer.md`；
这一篇的每一句"为什么"都只允许指向**本仓库某一行代码或某一行注释**，指向处一律写成 `文件:行`。
读任何一段代码，按这六问走（六问的形状与 `subsystem-map.md` 第 7 节的模块六件套同源）：

| 问 | 在代码里看什么位置 |
|---|---|
| ① 这段跑在哪个时钟、被谁复位 | `always @(posedge …)` 的那一个时钟名 + `if (!rst_n)` 支路是否存在 |
| ② 它的输入必须是谁先给好的 | 端口注释 + 上游赋值的行号 |
| ③ 边界写在哪一行 | 比较式（`>=`、`<`、`== {W{1'b1}}`）与夹紧式（三目 `? :`） |
| ④ 计数会不会回卷 | 赋值右侧有没有 `if (!sat)` 这类门（片段 2、片段 8 都有） |
| ⑤ 状态寄存器与数据寄存器为什么分开 | 找有没有"带异步复位的块"和"不带复位的块"同时写同一组寄存器（本仓库的落点：`src/rtl/eth/dc_fifo.v:59-63`、`src/rtl/axi/axi_frame_writer_gated.v:50-54` 与 `:94-99`、`src/rtl/video/raw_line_delay.v:80-94`） |
| ⑥ 出错时它自己怎么暴露 | 找输出里有没有"只增不减"的统计位，或看它把哪一拍打给了观测模块 |

本行无信息量的行（空行、`end`）在这一篇里也会被点名，规则是"每行要么有说明、要么写本行无信息量"，
不许留空 —— 空行恰恰是"这段代码被切成几块"的分界线，念出来才知道块与块的边界。

小结 1：这一篇的判据是"每一句都能被 `文件:行` 复核"，读者用第 12 节那把尺子可以自己扫一遍。
小结 2：六问里最容易跳过的是第 ⑤ 问，而本工程为它付过的学费最多（片段 7、片段 3 各一处）。
下一步：片段 1，从"一包 UDP 的头四字节"开始。

## 第 2 节 片段 1 · UDP 包头的四拍移位状态机（`src/rtl/eth/frame_reasm.v:121`）

**这一段是什么**：收包链的重组状态机。上游给的是逐字节的载荷流（8 bit 宽、`p_valid` 表示这一拍有效），
每包的前 4 个字节是"这一字节落在帧内第几个字节"的小端偏移，第 5 个字节起才是像素。
包形与 `src/host/video_sender.py:4-6`、`src/rtl/eth/frame_reasm.v:104` 说的是同一件事。
形状：`S_OFF0..S_OFF3` 四拍装偏移 + `S_DATA` 装像素，`p_sof`（包首）能把状态机直接踢回 `S_OFF1`。

引用原文：`src/rtl/eth/frame_reasm.v:121-143`（23 行）

```verilog
                if (p_sof) begin
                    st<=S_OFF1; have_lo<=0; pkt_pay<=0; pkt_active<=1;
                    off<={24'd0,p_data};
                end else begin
                    case (st)
                        S_OFF0: begin off<={24'd0,p_data}; st<=S_OFF1; end
                        S_OFF1: begin off[15:8]<=p_data; st<=S_OFF2; end
                        S_OFF2: begin off[23:16]<=p_data; st<=S_OFF3; end
                        S_OFF3: begin
                            off[31:24]<=p_data; st<=S_DATA;
                            pkt_start <= hdr;
                            pend      <= (hdr >= FRAME_BYTES) ? SAT : hdr[CW-1:0];
                            if (hdr < 32'd4) begin
                                cov<=0;
                                rok0<=0; rok1<=0; rok2<=0; rok3<=0; rok4<=0;
                                rows_hit<=0;
                                bad_frame<=0;
                            end
                        end
                        S_DATA: begin
                            if (!have_lo) begin
                                pix_lo<=p_data; have_lo<=1;
                            end else begin
```

逐行（行号 = `src/rtl/eth/frame_reasm.v` 的行号）：

- `:121` `if (p_sof) begin` —— 做什么：这一拍是本包第一个字节，跳进"装偏移"的快路。
  为什么：偏移字段必须从包首开始对齐，而 `p_sof` 由上游剥头模块给（同文件端口 `:17`）。
  删掉：`off` 会从来随机 —— 载荷的第一个像素字节被当成偏移低 8 位，写地址整帧全错。
- `:122` `st<=S_OFF1; have_lo<=0; pkt_pay<=0; pkt_active<=1;` —— 做什么：一次做四件事：状态推到"偏移第 2 字节"、
  清掉半像素锁存、本包载荷字节数归零、把"本包正在进行"立起来。
  为什么 `have_lo<=0` 必须在这里：RGB565 是两个字节一个像素，上一包若落下奇数个字节，本包第一个字节
  就会被当低半字节存进 `pix_lo`（`:142`）—— 于是整帧从这一列起每个像素的两个字节互相串位。
  删掉 `pkt_active<=1`：`:174` 的 `if (p_eof && pkt_active)` 整块进不去，`flush`/统计/验收门一次都不执行。
- `:123` `off<={24'd0,p_data};` —— 做什么：偏移的 `[7:0]`。写成"高位补零 + 低位替换"而不是 `off[7:0]<=p_data`，
  是因为这一拍前面 4 个字节里只到了 1 个，高 24 位必须是干净的 0（`:126` 走的是同一个式子）。
  删掉：偏移高 24 位保留上一个包的残留 ⇒ 写地址落在上一帧的位置上。
- `:124` `end else begin` —— 做什么：没有 `p_sof` 时才按状态机逐拍走。
  删掉（把 if/else 拉平）：`p_sof` 与 `case` 会同时驱动 `st`，综合报多驱动，仿真里则是后写的赢。
- `:125` `case (st)` —— 做什么：五态分支（状态定义在 `:37`，`S_DATA=4` 是"收像素"）。
- `:126` `S_OFF0: begin off<={24'd0,p_data}; st<=S_OFF1; end` —— 做什么：这是**没有 `p_sof` 却处在 S_OFF0** 的那条路
  （上电后第一个字节、或异常退出后重新对齐的第一个字节）。
  为什么两条路都要写偏移低 8 位：`p_sof` 只标"包边界"，复位释放后的第一个字节没有 `p_sof` 可依。
  删掉：这一拍落进 `default`（`:169`），字节被丢、状态退回 `S_OFF0`，永远凑不齐偏移。
- `:127` `S_OFF1: begin off[15:8]<=p_data; st<=S_OFF2; end` —— 做什么：偏移第 2 字节写进 `[15:8]`。
  为什么用位选写入而不是移位再或：位选是纯接线，不占加法器/移位器。
  删掉：`off[15:8]` 停在 0 ⇒ 偏移最多只到 255（`:123` 的低 8 位），所有像素都写进帧头那一小段。
- `:128` `S_OFF2: begin off[23:16]<=p_data; st<=S_OFF3; end` —— 做什么/为什么/删掉：同 `:127`，缺一字节偏移就差 16 位。
- `:129` `S_OFF3: begin` —— 做什么：偏移的最后一个字节到的那一拍，这一段同时是本包的"记账点"。
- `:130` `off[31:24]<=p_data; st<=S_DATA;` —— 做什么：偏移齐了，状态进像素阶段。
- `:131` `pkt_start <= hdr;` —— 做什么：把整 4 字节拼出来的偏移值
  （`hdr` 定义在 `:105` = `{p_data, off[23:0]}`，因为 `off[31:24]` 要到非阻塞赋值之后才更新）锁成"本包起始偏移"。
  为什么需要单独锁：`:132` 与 `:174` 之后的判定都要用"本包第一个字节落在哪"，而那时 `off` 已经往前走了一位。
  删掉：`pkt_start` 停在旧值，`pend` 的起点错（见下一行）。
- `:132` `pend <= (hdr >= FRAME_BYTES) ? SAT : hdr[CW-1:0];` —— 做什么：本包"已到达的字节游标"从包起始偏移起算，
  越界的包直接钉在饱和值 `SAT`。
  为什么：`pend` 用来判"这一包是不是把帧凑满的那一包"（`:72` 的 `last_pkt`），
  如果越界包也进 `pend`，`hdr[CW-1:0]` 会把 32 位截成 `CW` 位、截出来的数恰好可能是合法帧内偏移
  —— 一个越界包会被误读成"帧末包"，把作废帧报成完成帧。
  删掉这一行：`pend` 不初始化，`last_pkt` 判据从第一帧起就不可信。
- `:133` `if (hdr < 32'd4) begin` —— 做什么：偏移 0～3 的包 = 这一帧的头一包 ⇒ 在这一拍重建整帧统计。
  为什么界是 `<4` 而不是 `==0`：上位机可以按任意对齐切包（切法见 `src/host/video_sender.py:35` 的
  `MAX_PAYLOAD`），真正属于新帧的包头一定在 0..3 这段里。
  删掉 `:134-137`：一帧被作废之后（`:189` 那一条分支不清统计），下一帧带着上一帧的 `cov`/`rows_hit` 进来，
  于是 `:182` 的三道门"行够 + 字节够 + 无坏包"可能凭残留值恒真 —— 缺包的帧照样提交。
- `:134` `cov<=0;` —— 做什么：整帧字节游标清零（`cov` 的语义写在 `:50-55` 的注释里：含在途包的本帧已收字节数）。
- `:135` `rok0<=0; rok1<=0; rok2<=0; rok3<=0; rok4<=0;` —— 做什么：逐行覆盖位图清零，五行一字节、5 块共 320 位（分块理由见 `:77-80` 的注释与片段 2）。
- `:136` `rows_hit<=0;` —— 做什么：本帧"已覆盖行数"清零，它就是 `:182` 里与 `IMG_H` 比的那个数。
- `:137` `bad_frame<=0;` —— 做什么：本帧的"有坏包"旗标清零（置位在 `:209`）。
- `:138` `end` —— 做什么：`:133` 那个 if 的收尾。
- `:139` `end` —— 做什么：`S_OFF3` 分支的收尾。
- `:140` `S_DATA: begin` —— 做什么：像素阶段的入口。
- `:141` `if (!have_lo) begin` —— 做什么：这一拍是像素的低字节还是高字节。
  为什么需要这一位：载荷长度可以是奇数（一帧 307200 B 被 1392 B 的包切成 220 包，最后一包 960 B，
  见 `src/host/video_sender.py:33-35` 的算术），奇偶配对不能假设"每包都从像素低字节开始"。
  删掉：`wr_data` 的高/低半字节随机互换 ⇒ 屏上表现为红蓝通道互换的脏色（`RGB565` 的位序见 `src/rtl/process/bilin_lerp.v:23-26`）。
- `:142` `pix_lo<=p_data; have_lo<=1;` —— 做什么：把低字节寄存在这里，下一拍再和高字节一起走。
- `:143` `end else begin` —— 做什么：本拍是高字节，下面（`:150-163`，本片段之外）就是一次 16 位写 + 行覆盖记账。
  读到这里可以直接对照 `src/rtl/eth/frame_reasm.v:150` 的 `wr_data<={p_data,pix_lo}` —— 后到的字节在高 8 位，
  这就是"小端"在这一层的落点。

**这一段能看到的代码事实**：偏移与像素之间没有 FIFO，只有一个 4 拍移位状态机加一个 `have_lo` 位；
所有"这一帧收没收到第 y 行"的判断都靠 `:129-139` 这一段在包头那一拍重建统计。
`subsystem-map.md` 第 7.1 节第 4 条列的失败暴露链（`frame_abort` → `link_monitor` → 快照 lane1/lane2）
起点就是这一段之后的 `:196-203`。

小结 1：读状态机先找"入口条件"与"每跳写哪几位"，本段的入口有两个（`p_sof` 与 `S_OFF0`），
两个入口写的是同一个式子 —— 少一个入口就会丢字节，这是双入口不是重复。
小结 2：`S_OFF3` 那一拍是本模块最挤的一拍：偏移齐、包起点锁存、帧统计重建三件事同拍发生，
看 `:129-139` 就知道为什么帧统计必须在包头清而不是在帧尾清。下一步：片段 2，字节预算怎么算。

## 第 3 节 片段 2 · 两个饱和计数与"末字节补偿"（`src/rtl/eth/frame_reasm.v:60`）

**这一段是什么**：同一个模块里的"计数器与边界处理"。`v5.1` 之前这里是
`cover + pkt_pay + 1 >= FRAME_BYTES` 这样的三项 32 位加法器，文件头 `:5-7` 记录它占了这一组 125 MHz 时钟的
全部十条最差路径。现在换成两个饱和游标 + 一次常数比较。

引用原文：`src/rtl/eth/frame_reasm.v:60-72`（13 行）

```verilog
    reg [CW-1:0] cov;
    reg [CW-1:0] pend;

    wire cov_sat  = (cov == SAT);
    wire cov_end  = (cov == SAT1);
    wire pend_sat = (pend == SAT);
    wire pend_end = (pend == SAT1);

    // The last byte of a packet shares its cycle with p_eof and the counters have not seen it
    // yet, so it is credited here (and only here) — same off-by-one guard v5.0 needed, one LUT deep.
    wire bytes_ok = cov_sat  | (cov_end  & p_valid);
    // the frame is over when a packet reaches FRAME_BYTES, whole or not
    wire last_pkt = pend_sat | (pend_end & p_valid);
```

逐行：

- `:60` `reg [CW-1:0] cov;` —— 做什么：本帧已收字节游标。位宽 `CW` 在 `:56` 由 `$clog2(FRAME_BYTES + 1)` 算出
  （= 19 位），刚好装得下 307200。
  为什么不留 32 位：`:50-55` 的注释写的口径是"只需要问够不够 FRAME_BYTES"，19 位比较比 32 位比较省一级。
  删掉：整个字节验收门消失（`:182` 的第二项 `bytes_ok` 没有原料）。
- `:61` `reg [CW-1:0] pend;` —— 做什么：只算"在途这一包"的游标（起点是 `pkt_start`，见 `:132`）。
  为什么要两个计数：`cov` 判"帧凑没凑满"，`pend` 判"这一包是不是帧末包"，两件事的清零时机不同
  （`cov` 在帧头清、`pend` 在每包首清）。删掉 `pend`：`:196` 的 `last_pkt` 只能用 `cov`，
  于是"帧已凑满之后又到的包"也会被报成帧末包，`stat_bad`/`frame_abort` 会重复计数。
- `:62` 本行无信息量（空行，作用是把寄存器组与译码组分开）。
- `:63` `wire cov_sat  = (cov == SAT);` —— 做什么：帧已凑满。`SAT` 在 `:57` = `FRAME_BYTES`。
  为什么写 `==` 而不是 `>=`：`cov` 被门成不可能越过 `SAT`（`:166` 的 `if (!cov_sat) cov<=cov+1;`），
  等号比较比大小比较浅一级。
- `:64` `wire cov_end  = (cov == SAT1);` —— 做什么：差一个字节就凑满（`SAT1` 在 `:58` = `FRAME_BYTES-1`）。
  为什么要单独一位：就是 `:70` 那条补偿用的。
- `:65` `wire pend_sat = (pend == SAT);` —— 做什么：在途包已经越过帧末。
- `:66` `wire pend_end = (pend == SAT1);` —— 做什么：在途包再收一字节就越过帧末。
- `:67` 本行无信息量（空行）。
- `:68` `// The last byte of a packet shares its cycle with p_eof and the counters have not seen it` —— 做什么：注释，
  说明这一拍的最后一个字节**还没进计数器**（`:166` 的 `cov<=cov+1` 是寄存器更新，下一拍才可见）。
- `:69` `// yet, so it is credited here (and only here) — same off-by-one guard v5.0 needed, one LUT deep.` ——
  做什么：注释，把补法与代价写在一起："只在这里补，且只补一个 LUT 的深度"。
  删掉这两行注释不影响功能，但会丢掉"为什么 `(cov_end & p_valid)` 不是多此一举"的唯一说明。
- `:70` `wire bytes_ok = cov_sat  | (cov_end  & p_valid);` —— 做什么：字节预算够不够，含本拍这个还没入账的字节。
  为什么必须 `& p_valid`：`p_eof`（包尾旗标）与最后一个字节同拍，而那一拍 `p_valid` 可能为 0
  （上游给 eof 时不一定同时给数据）；不加这一与，就会把"其实没到"的字节算进去，
  于是差一字节的不完整帧被判成完整。
  删掉整行：`:182` 的三门少一门，只要行覆盖齐了就提交 —— 帧尾缺数据时屏幕上留下上一帧的残影。
- `:71` `// the frame is over when a packet reaches FRAME_BYTES, whole or not` —— 做什么：注释，
  说明 `last_pkt` 判的是"这一包摸到了帧末"，不管这一包本身完不完整。
- `:72` `wire last_pkt = pend_sat | (pend_end & p_valid);` —— 做什么：帧末包判定，给 `:196-203` 用来决定
  "要不要报一次 `frame_abort` 并把缺行数记下来"。
  删掉：短帧/坏帧不再被数一次，`link_monitor` 的 `frames_bad` 会停在 0（观测口在 `src/rtl/eth/link_monitor.v:126-129`）。

**这一段的现象只从代码读得到**：`:63-66` 四个比较式的位宽都是 `CW`（19 位），
而 `SAT`/`SAT1` 是 `localparam [CW-1:0]` —— 若把 `FRAME_BYTES` 改大过 `2^CW-1`，`:56` 的 `$clog2` 会跟着变宽，
比较式仍然成立；但 `:217-220` 那个 `initial` 只检查行数上界（`IMG_H > 5*64`），不检查字节预算，
这一点写在这里供换题目时注意（换分辨率的必查项在 `next-layer.md` 第 3 节之外，属于 `hands-on.md` 实验 6 那一类改动）。

小结 1：饱和计数 + 等号比较 = 把"加法器 + 大小比较"换成"一位旗标 + 等号"，这是这一段的全部算术改动；
`:68-69` 那两行注释是这段改口的唯一留痕，删了代码还能跑，但下一个人会把它"改回更简单的那版"。
小结 2：`cov`/`pend` 两个游标配 `bytes_ok`/`last_pkt` 两个判据，是"帧级"与"包级"两个视角 ——
读任何一段计数逻辑，先问这两个视角各由谁负责。下一步：片段 3，跨域缓冲。

## 第 4 节 片段 3 · 格雷码指针与满/空判据（`src/rtl/eth/dc_fifo.v:45`）

**这一段是什么**：全设计唯一一条"数据必须跨时钟域"的通道（容量账与例化处见 `subsystem-map.md` 第 7.2 节：
`src/rtl/eth/eth_udp_video_top.v:295-298`，`DATA_W=36`、`ADDR_W=13` ⇒ 8192 条）。
这一段含两件事：写侧指针的推进与满判据、存储本体的一次写、读侧的空判据。

引用原文：`src/rtl/eth/dc_fifo.v:45-68`（24 行）

```verilog
    wire [ADDR_W:0] wbin_n  = wbin + 1'b1;
    wire [ADDR_W:0] wgray_n = bin2gray(wbin_n);
    assign wr_full = (wgray == {~rgray_s1[ADDR_W:ADDR_W-1], rgray_s1[ADDR_W-2:0]});

    // write pointer (async rst)
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wbin <= 0; wgray <= 0;
        end else if (wr_en && !wr_full) begin
            wbin  <= wbin_n;
            wgray <= wgray_n;
        end
    end

    // memory write: no reset → BRAM-friendly
    always @(posedge wr_clk) begin
        if (wr_en && !wr_full)
            mem[wbin[ADDR_W-1:0]] <= wr_data;
    end

    // read
    wire [ADDR_W:0] rbin_n  = rbin + 1'b1;
    wire [ADDR_W:0] rgray_n = bin2gray(rbin_n);
    assign rd_empty = (rgray == wgray_s1);
```

逐行：

- `:45` `wire [ADDR_W:0] wbin_n = wbin + 1'b1;` —— 做什么：下一个写指针（二进制）。
  为什么指针比地址宽一位（`ADDR_W+1` = 14 位而地址只有 13 位）：满与空要靠"最高位不同、其余相同"来区分，
  一位_wrap_计数不够用 —— 这一点在 `:36` 的注释里写的是同一件事（"full 用对端格雷码的最高两位取反、其余相等判"）。
- `:46` `wire [ADDR_W:0] wgray_n = bin2gray(wbin_n);` —— 做什么：把下一个写指针转成格雷码
  （转换式在 `:29-32`：`b ^ (b>>1)`，纯一位移位加异或）。
  为什么二进制指针不跨域而格雷码跨：相邻两个格雷码只有一位不同，对面打两拍之后最多读到"上一格或这一格"，
  不会出现半新半旧的第三个数 —— 这一句的通用口径不在本篇，见 `next-layer.md` 第 2 节。
- `:47` `assign wr_full = (wgray == {~rgray_s1[ADDR_W:ADDR_W-1], rgray_s1[ADDR_W-2:0]});` —— 做什么：满判据。
  把已经同步到写域的**读指针格雷码**的最高两位取反、低 12 位照抄，再与本地写指针格雷码比。
  为什么用"当前写指针 `wgray`"而不是"下一个 `wgray_n`"：`:40-44` 的注释记录了这一刀（r88）——
  原式把 14 位加法 + 二进制转格雷 + 比较整条锥体挂在 `wr_en → ENARDEN` 上，
  注释里给的实测是 r87 最差路径 8 级逻辑、0.152 ns（凭据名 `build/r87_timing_summary.rpt`，
  该件本次未打开核对，故按"注释记载"处理）；换成当前指针后锥体只剩一个比较，
  副作用是"少一格"的病一起没了（注释记载可用深度从 DEPTH−1 变成 DEPTH，尺子名 `sim/tb_cdc_capacity`）。
  删掉这一行：`wr_en && !wr_full` 恒真，写指针越过读指针 ⇒ 未读走的数据被覆盖，且没有任何统计位报出来
  （报出来的那一位是 `src/rtl/eth/eth_udp_video_top.v:283` 的 `cdc_wr_req`，它要的就是这一位挡不挡）。
- `:48` 本行无信息量（空行）。
- `:49` `// write pointer (async rst)` —— 做什么：注释，标明这一块带异步复位（与下面 `:59` 形成对照，那一块刻意不带）。
- `:50` `always @(posedge wr_clk or negedge wr_rst_n) begin` —— 做什么：写指针进程。
- `:51` `if (!wr_rst_n) begin` —— 做什么：复位支路。两侧复位各自独立（端口 `:8`、`:14`），
  这也是 `subsystem-map.md` 第 7.2 节第 3 件"上电必须两边都复位过"的落点。
- `:52` `wbin <= 0; wgray <= 0;` —— 做什么：两个指针同拍归零，初值一致才有"空"可言
  （`:68` 的空判据就是两个格雷码相等）。
  删掉：两侧上电值不同时（这一域的复位还有一条"名义复位"的背景，见 `clocking-and-reset.md` 第 2 节），
  空/满会一开始就判反，FIFO 永远读不出数据或永远被判定该停。
- `:53` `end else if (wr_en && !wr_full) begin` —— 做什么：只有"要写且没满"才推进 —— 这一拍就是"被挡掉"的判定，
  `link_monitor` 数的丢字就是这一式的否定形（`src/rtl/eth/link_monitor.v:105`）。
- `:54` `wbin <= wbin_n;` —— 做什么：推进二进制指针（同时也就推进了存储地址，见 `:62`）。
- `:55` `wgray <= wgray_n;` —— 做什么：推进对外发布的格雷码指针。
  为什么两个都要寄存：`wbin` 用来寻址和 +1，`wgray` 用来跨域；只留一个的话要么跨域的是二进制（错），
  要么每次寻址都要把格雷码转回二进制（多一个异或锥）。
- `:56` `end` —— 做什么：if 收尾。
- `:57` `end` —— 做什么：进程收尾。
- `:58` 本行无信息量（空行）。
- `:59` `// memory write: no reset → BRAM-friendly` —— 做什么：注释，说明这一块**故意不带复位**。
  原因不是风格：带异步复位的存储块综合器推不出 BRAM ——
  同一件事在 `src/rtl/axi/axi_frame_writer_gated.v:50-52` 留下了实测记录（报 `Synth 8-4767`，
  64×83 bit 全掉进触发器），在 `src/rtl/process/bilin/fb_bilin.v:145-148` 留下另一条
  （带异步复位报 `Synth 8-91 ambiguous clock in event control` 并整个模块作废）。
- `:60` `always @(posedge wr_clk) begin` —— 做什么：只关心时钟的进程（形状与上面两条记录对得上）。
- `:61` `if (wr_en && !wr_full)` —— 做什么：与 `:53` 同一个条件 —— 指针与数据必须同进同退，
  否则会出现"指针前进了但这一格没写"的空洞。删掉这一条而留 `:53`：满时仍写入，覆盖尚未读走的数据。
- `:62` `mem[wbin[ADDR_W-1:0]] <= wr_data;` —— 做什么：用二进制指针的低 13 位做地址写一格。
  为什么切掉最高位：那一位是"绕回了几次"的信息，寻址不需要（数组深度就是 `1<<ADDR_W`，`:19`）。
  `mem` 的声明在 `:20`，带 `(* ram_style = "block" *)` —— 强制走 BRAM 而不是 LUTRAM，
  这一位的取舍在 `design-choices.md` 第 5 节。
- `:63` `end` —— 做什么：进程收尾。
- `:64` 本行无信息量（空行）。
- `:65` `// read` —— 做什么：注释分节。
- `:66` `wire [ADDR_W:0] rbin_n = rbin + 1'b1;` —— 做什么：读指针的下一格，与 `:45` 对称。
- `:67` `wire [ADDR_W:0] rgray_n = bin2gray(rbin_n);` —— 做什么：读指针的格雷码形式，供 `:93` 那条链发布。
- `:68` `assign rd_empty = (rgray == wgray_s1);` —— 做什么：空判据 = 本侧读指针格雷码与同步过来的写指针格雷码相等。
  为什么这个式子比满判据简单得多：相等是"逐位相同"，不需要取反哪几位。
  删掉：读侧无条件取数 ⇒ `:74` 的保护消失，把没写过数据的格（BRAM 上电 0）当成有效字送进 AXI 打包器。

小结 1：这一段最值钱的三行是 `:47`、`:59`、`:68` —— 一行是"把加法器从关键路径里赶出去"的实测取舍，
一行是"存储块不许带异步复位"的形状约束，一行是"空与满为什么长得不一样"。
小结 2：满判据只用**当前**指针，于是 `wr_full` 与 `rd_empty` 在结构上对称，
两侧各自只依赖"对端发布过来的那一个寄存器"；这就是异步 FIFO 能把两个时钟彻底分开的写法原因。
下一步：片段 4，跨域的那两拍究竟打在哪。

## 第 5 节 片段 4 · 二进制指针不跨域、格雷码指针打两拍（`src/rtl/eth/dc_fifo.v:81`）

**这一段是什么**：把片段 3 里生成的两个格雷码指针**各自送到对方时钟域**的那两条两级同步链。
整个模块里只有这四颗寄存器跨域（`:27`），其余寄存器都待在自己的域。

引用原文：`src/rtl/eth/dc_fifo.v:81-95`（15 行）

```verilog
    // 格雷码指针跨域：各在**对方**时钟域打两拍（s0→s1），二进制指针永不跨域
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rgray_s0 <= 0; rgray_s1 <= 0;
        end else begin
            rgray_s0 <= rgray; rgray_s1 <= rgray_s0;
        end
    end
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wgray_s0 <= 0; wgray_s1 <= 0;
        end else begin
            wgray_s0 <= wgray; wgray_s1 <= wgray_s0;
        end
    end
```

逐行：

- `:81` —— 做什么：注释，一句话给出本段的规则：跨域的只有格雷码、而且只打两拍（`s0→s1`）。
  为什么值得单独写一行：同一文件里还有 `:22` 那四个"本地"指针，形状像但不跨域，读代码时容易混。
- `:82` `always @(posedge wr_clk or negedge wr_rst_n) begin` —— 做什么：读侧指针在**写侧时钟**里同步的进程。
  为什么用写侧时钟：这条链的输出（`rgray_s1`）只被写侧的比较式 `:47` 用，谁用它就在谁的域里打拍。
- `:83` `if (!wr_rst_n) begin` —— 做什么：复位入口。
- `:84` `rgray_s0 <= 0; rgray_s1 <= 0;` —— 做什么：两级都清零。
  为什么复位值必须是 0 而不是"读指针的真值"：`rgray` 的复位值也是 0（`:72`），
  两边都从 0 起，`:47` 的满判据在上电第一拍才成立。
- `:85` `end else begin` —— 做什么：无复位时每拍同步。
- `:86` `rgray_s0 <= rgray; rgray_s1 <= rgray_s0;` —— 做什么：两级串联，第一级专门用来"撞亚稳"，
  第二级给逻辑用。删掉第一级、让 `:47` 直接用 `rgray`：跨域线变成一级同步器 ——
  工具侧的可观察后果是 `build/report/methodology.rpt` 那一条 `TIMING-10 Missing property on synchronizer`
  所指的那类形状问题（该规则计数见片段 8 末尾的读法，`build/report/methodology.rpt:35`）。
- `:87` `end` —— 做什么：`if/else` 的收尾。本行无信息量（结构闭合）。
- `:88` `end` —— 做什么：进程收尾。本行无信息量（结构闭合）。
- `:89` `always @(posedge rd_clk or negedge rd_rst_n) begin` —— 做什么：镜像过来的另一条：写侧指针在**读侧时钟**里同步。
  为什么必须两条分开、不能共用一条链：两条链各自吃不同的时钟，一根触发器不能同时被两个时钟驱动。
- `:90` `if (!rd_rst_n) begin` —— 做什么：读侧复位入口。
- `:91` `wgray_s0 <= 0; wgray_s1 <= 0;` —— 做什么：清两级（与 `:84` 对称）。
- `:92` `end else begin` —— 做什么：正常支路。
- `:93` `wgray_s0 <= wgray; wgray_s1 <= wgray_s0;` —— 做什么：两级同步，输出 `wgray_s1` 给 `:68` 的空判据。
- `:94` `end` —— 做什么：`if/else` 的收尾。本行无信息量（结构闭合）。
- `:95` `end` —— 做什么：进程收尾。本行无信息量（结构闭合）。

**这四颗寄存器还有一个必须一起看的属性**：`:27` 的
`(* ASYNC_REG = "TRUE" *) reg [ADDR_W:0] wgray_s0, wgray_s1, rgray_s0, rgray_s1;`。
`:23-26` 的注释写的是打这个属性的理由（不打，工具会把它们挪位、复制、拆开），
并把尺子名点出来：`build/scan_async_reg_coverage.py`（该件本次 `ls` 确认在盘上，但没有运行）。这一条**本次没有运行过**，
所以"改前 A2 RED missing=2"那个读数按注释记载处理，不当作本目录实测。

**只从代码读得到的现象**：满与空各自只读**一对寄存器**（`:47` 读 `rgray_s1`、`:68` 读 `wgray_s1`），
因此两个判据的组合深度都只有一层比较 —— 这就是片段 3 里 `:40-44` 那一条时序账单能还清的结构前提。

小结 1：`s0` 与 `s1` 同域、按扫描器口径不算"跨域捕获"，但这里四颗一起标 `ASYNC_REG`（`:25-27` 的注释），
读代码时看到的形状是"一行四个同名不同下标的寄存器"。
小结 2：两条链的方向正好相反，`rgray` 往写域走、`wgray` 往读域走，谁都不共享 —— 这是异步 FIFO 的固定形状，
在陌生代码里看到这一对反向的 `*_s0/*_s1` 就是它（辨认法见第 10 节）。下一步：片段 5，脉冲怎么跨。

## 第 6 节 片段 5 · 单帧提交事件跨域（`src/rtl/eth/ddr_bank_commit.v:36`）

**这一段是什么**：把"这一帧被完整收下并验收通过"这一**拍**事件从 125 MHz 的收包域搬到 100 MHz 的 AXI 域。
同一个模块后半段（`:53-77`，本片段之外）用这个沿去换乒乓 bank。
形状就是 `clocking-and-reset.md` 第 4.2 节列的"翻转位 + 3 级 + 异拍出沿"。

引用原文：`src/rtl/eth/ddr_bank_commit.v:36-51`（16 行）

```verilog
    // ---- frame_done 跨域 ----
    reg frame_done_tog = 1'b0;
    always @(posedge gmii_clk or negedge rst_n) begin
        if (!rst_n) frame_done_tog <= 1'b0;
        else if (frame_done) frame_done_tog <= ~frame_done_tog;
    end
    (* ASYNC_REG = "TRUE" *) reg fd0, fd1, fd2;
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) {fd2, fd1, fd0} <= 3'b0;
        else {fd2, fd1, fd0} <= {fd1, fd0, frame_done_tog};
    end
    wire fd_axi = fd1 ^ fd2;

    // 本帧的数据是否已经全部穿过 CDC：队空 + 读地址已发 + 两级读流水都空。
    wire tail_drained = cdc_empty && !cdc_rd && !cdc_d1_v && !sav_en && !sav_flush;
    wire commit_ok    = TAIL_GUARD ? (saver_idle && tail_drained) : saver_idle;
```

逐行：

- `:36` —— 做什么：注释分节，标明从这一行开始是"跨域"段，之前是端口/参数。
- `:37` `reg frame_done_tog = 1'b0;` —— 做什么：声明翻转位并给**声明初值** 0。
  为什么写声明初值而不是只靠 `:39` 的复位支路：这一位还要在复位之前的那几拍里保持已知值，
  本工程里"复位是死支路时靠声明初值"是另一族病（`clocking-and-reset.md` 第 2 节那条 `sys_rst_n` 恒 1），
  这里两处都写上，等于同一件事不赌单一机制。
  删掉 `= 1'b0`：仿真里该位是 X，`:45` 那条移位链把 X 一路带进 `fd1/fd2`，`fd_axi` 变 X ⇒
  台架里表现为"提交沿时有时无"。
- `:38` `always @(posedge gmii_clk or negedge rst_n) begin` —— 做什么：源域（125 MHz）进程。
- `:39` `if (!rst_n) frame_done_tog <= 1'b0;` —— 做什么：复位清零。
- `:40` `else if (frame_done) frame_done_tog <= ~frame_done_tog;` —— 做什么：**每来一次事件就把这一位拧到反面**。
  为什么传翻转而不是传脉冲：脉冲只有一拍（8 ns），目的域若那一拍没采到就永远不知道发生过。
  删掉取反号（写成 `<= 1'b1`）：第一次之后再也看不到边沿，`fd_axi` 恒 0，提交这件事在对面根本不存在。
- `:41` `end` —— 做什么：进程收尾。本行无信息量（结构闭合）。
- `:42` `(* ASYNC_REG = "TRUE" *) reg fd0, fd1, fd2;` —— 做什么：声明三级同步器并打异步属性。
  为什么三级而不是片段 4 的两级：这里判的是"边沿"（`:47` 异或两个**相邻**级），
  相邻两级都可能处在亚稳后的过渡值，取到异或的那一拍必须是已经稳定过的那一对 ——
  `src/rtl/eth/snap_cross.v:3` 的注释用的是同一条口径（"边沿要 3 级同步才到目的域"）。
- `:43` `always @(posedge axi_clk or negedge axi_rst_n) begin` —— 做什么：目的域进程。
- `:44` `if (!axi_rst_n) {fd2, fd1, fd0} <= 3'b0;` —— 做什么：整条链清零。
  为什么三个一起清（不是只清 `fd2`）：清零值不一致时，第一拍就会造出一个假边沿。
  这一族的真实病史在 `src/rtl/top/pl_video_top.v:153-155` 的注释：源头复位 0、链复位 3'b111 的不一致
  让上电白送一次"长按"事件，判据红过。
- `:45` `else {fd2, fd1, fd0} <= {fd1, fd0, frame_done_tog};` —— 做什么：一次移位两格，写法是整向量拼接。
  为什么用 `{a,b,c} <= {b,c,in}` 而不是三条独立赋值：形状紧凑、且三级同名连写正是扫描器认的形状
  （`clocking-and-reset.md` 第 4.1 节第 5 层的辨认法就是这条）。
- `:46` `end` —— 做什么：进程收尾。本行无信息量（结构闭合）。
- `:47` `wire fd_axi = fd1 ^ fd2;` —— 做什么：异或相邻的后两级，得一个"恰好一拍"的沿。
  为什么取 `fd1^fd2` 而不是 `fd0^fd1`：`fd1` 已经是第二级，出沿时它的值已稳定两拍；
  `fd0` 可能正处在亚稳后的过渡，与它异或出的那一拍不可靠。
  删掉这一行：`switch_req` 永远不会置起（消费点在同文件 `:63-66`）。
- `:48` 本行无信息量（空行，隔开"跨域"与"提交门"两段逻辑）。
- `:49` —— 做什么：注释：给出"本帧数据是否全部穿过 CDC"由哪五个状态组成。
- `:50` `wire tail_drained = cdc_empty && !cdc_rd && !cdc_d1_v && !sav_en && !sav_flush;` ——
  做什么：队空 + 读使能已发未回 + 读流水第 2 级 + 第 3 级写字 + 第 3 级推 flush，五项全空才算排干。
  为什么五项都要，少一项都不算：`:6-7` 的文件头记录了少判的后果 ——
  旧判据只看 `saver_idle`，它对 8192 深的 CDC 与后面的读流水完全不可见，
  于是帧尾几个 16 bit 被写进**下一帧**的 bank（注释写的板上一眼可见的现象是"HDMI 右下角少 2 像素"）。
  删掉 `!sav_flush`：帧末那次 flush 落在换页之后，bank 号已经翻页，那一拍的数据进了下一帧。
- `:51` `wire commit_ok = TAIL_GUARD ? (saver_idle && tail_drained) : saver_idle;` ——
  做什么：把上面那一项做成参数门（`TAIL_GUARD` 在 `:11`，默认 1，`=0` 保留旧判据只供 A/B 对照复现）。
  为什么留一条旧路而不删：换题目时"这个门是不是必要"必须由对照实验回答，注释在 `:11` 写的就是这个用途。
  删掉这一行写成 `= saver_idle`：`TAIL_GUARD` 参数变成死参数，`:11` 那句"只供 A/B 对照"落空。

**只从代码读得到的现象**：`:63-66` 用 `fd_axi` 同时置 `switch_req` 与 `force_flush`，
而 `:67-73` 的提交要 `switch_req && commit_ok` 两项同时成立 —— 于是"事件来了"与"可以换页"是分开的两拍，
这解释了为什么这一模块要同时吃 `gmii_clk` 与 `axi_clk` 两个时钟（端口 `:13-14`）。

小结 1：本段是"单 bit 事件跨域"的标准形：翻转 → 三级 → 异或。它和片段 4 的区别就在 `:47` 那一记异或 ——
片段 4 传的是**电平**（格雷码整体值），这里传的是**次数**。
小结 2：`TAIL_GUARD` 那一行（`:51`）把"跨域同步"与"跨域之后还要等到数据真的走完"分开处理，
读任何一段提交逻辑都要问这两件事分别由哪一行负责。下一步：片段 6，AXI 的握手。

## 第 7 节 片段 6 · AXI 读通道的 valid/ready 与在途额度（`src/rtl/axi/axi_frame_writer_gated.v:75`）

**这一段是什么**：`u_row` 那台搬运机的握手核心 —— AR（读请求）什么时候可以再发一条、
R（读数据）这一拍算不算"收到了"、收到的字是直接落 BRAM 还是先进 skid 缓冲（`sk_*` 声明在 `:53-58`）。
这一层的时钟是 `axi_clk`（100 MHz），复位是真信号（端口 `:14`）。

引用原文：`src/rtl/axi/axi_frame_writer_gated.v:75-89`（15 行）

```verilog
    // 过去是 `active && !sk_full`：abort 一落，`rready` 直接掉 0。AXI 不许 master 撤回已经举起的
    // `rvalid` ⇒ 那些拍不会消失，它们会**等在下一帧门口**，下一帧收下的头几拍其实是上一帧的数据
    // （整帧平移 + 帧尾越界写；台架 `sim/tb_writer_abort.v` 的 B3/B5/B6 三条红钉的就是这个）。
    // 现在：排空期间照样接收，只是**丢掉不写**（`dropping` 把下面三个写口都关掉了）。
    assign m_axi_rready = (active && !sk_full) || dropping;

    wire can_issue = active && allow_wr && !m_axi_arvalid && !abort && !dropping
                     && (outstanding < MAX_OUT)
                     && (burst_idx < TOTAL_BURSTS)
                     && (sk_level <= ((1<<SK)-1-BEATS));

    wire r_hit     = m_axi_rvalid && m_axi_rready;
    wire do_direct = r_hit && allow_wr && sk_empty && !dropping;
    wire do_skid   = r_hit && !do_direct && !dropping;
    wire sk_drain  = active && allow_wr && !sk_empty && !do_direct && !dropping;
```

逐行：

- `:75` —— 做什么：注释，先写出**旧写法**（`active && !sk_full`）以及它的失效机理。
  这一行不是装饰：`:79` 里那个 `|| dropping` 的唯一理由就在这一段（旧写法在 abort 那一拍把 rready 撤回）。
- `:76` —— 做什么：注释，把协议侧的硬事实写下来："不许 master 撤回已经举起的 `rvalid`"。
  这一句是本模块接受排空义务的依据；协议原文的出处与核对状态见 `next-layer.md` 第 1 节（本目录未取到原文正文）。
- `:77` —— 做什么：注释，交代钉住这件事的台架名（`sim/tb_writer_abort.v` 的 B3/B5/B6）。
- `:78` —— 做什么：注释，写明"排空期间接收但丢掉不写"这一处置，并把关掉的对象指向下面三个写口。
- `:79` `assign m_axi_rready = (active && !sk_full) || dropping;` —— 做什么：读数据的 ready。
  为什么 ready 的组成里有 `dropping`：一旦 `dropping` 为 1，`:86` 的 `r_hit` 仍然会成立，
  但 `:87-89` 的三条写路径全被 `!dropping` 关住 —— 数据被接住然后丢掉，从机侧看不到"我方撤回 ready"。
  删掉 `|| dropping`：abort 之后在途突发收不完，`drain_left`（`:71-73`）永远清不回去，
  `:123`/`:125` 那两条入口都进不去 ⇒ 屏上从此不再刷新（这一段账在 `:115-121` 的注释里）。
  握手两式的方向要分清：`rvalid` 由从机举、`rready` 由本机举，二者互不等待（协议侧的"独立性"口径待核，
  见 `next-layer.md` 第 1 节；这里只描述代码里谁驱动哪一根）。
- `:80` 本行无信息量（空行）。
- `:81` `wire can_issue = active && allow_wr && !m_axi_arvalid && !abort && !dropping` —— 做什么：能不能发下一条 AR 的前四项。
  `allow_wr` 就是"消隐窗口开着"（顶层接法在 `src/rtl/top/pl_video_top.v:459`，窗口由
  `src/rtl/video/frame_commit_lock.v:71-76` 给）；`!m_axi_arvalid` 保证同一条 AR 不重复发。
- `:82` `&& (outstanding < MAX_OUT)` —— 做什么：在途突发数不超过 `MAX_OUT`（`:47` = 4）。
  为什么要有额度：`:45-46` 的注释写的是同一件事 —— 4 条 16 拍的突发 ≈ 64 拍在途，
  够盖住 HP0/DDR 的读延迟并在 25 行窗口里保持每拍一条。
  删掉：额度失效 ⇒ 一次性把所有突发全发出去，skid 被撑到 `sk_full`，`:84` 那条预算式反而更严。
- `:83` `&& (burst_idx < TOTAL_BURSTS)` —— 做什么：本帧的突发数发完就停（`TOTAL_BURSTS` 在 `:44` 由字数与 `BEATS` 推出来）。
- `:84` `&& (sk_level <= ((1<<SK)-1-BEATS));` —— 做什么：留够"一条完整突发的落点"再发新请求。
  为什么留一整条突发（16 拍）而不是 1 格：一条突发发出去就要有 16 个格接它，
  否则 `sk_full` 会在突发中途成立，从机侧的 `rvalid` 已经拉起而本机无法收 —— 那正是 `:76` 那句话不能违的形态。
  删掉：与 `:82` 一起等于没有预算，`:58` 的 `sk_full` 成为唯一保护，而它判的是"已经满了"，晚了。
- `:85` 本行无信息量（空行）。
- `:86` `wire r_hit = m_axi_rvalid && m_axi_rready;` —— 做什么：**握手成立的那一拍**才叫"收到一个字"。
  为什么不能只看 `rvalid`：`rvalid` 高而 `rready` 低时，从机要一直保持数据，这一拍并没有交付；
  代码里凡是要"数一拍"的地方用的都是 `r_hit`（`:121`、`:165`、`:173`、`:178`）。
  删掉改用 `m_axi_rvalid`：从机拖住 ready 时同一字被重复计数 ⇒ `wr_words` 越过 `TOTAL_WORDS`，
  `:182` 的完成判据提前成立，屏上出现"搬了一半就当搬完"的帧。
- `:87` `wire do_direct = r_hit && allow_wr && sk_empty && !dropping;` —— 做什么：快路 —— 直接写 BRAM，不进缓冲。
  为什么要 `sk_empty`：缓冲里只要还有旧字，新字就必须排在它后面，否则帧内字节顺序被打乱。
  这一式就是文件头 `:5-6` 那句"copy finishes inside one display frame"的执行处。
- `:88` `wire do_skid = r_hit && !do_direct && !dropping;` —— 做什么：慢路 —— 这一拍的字先进 skid 数组
  （数组写在 `:94-99`，那个 `always` 块没有复位支路，与片段 3 的 `:59` 同一条形状规矩，
  原因记录在 `:50-52`）。
- `:89` `wire sk_drain = active && allow_wr && !sk_empty && !do_direct && !dropping;` —— 做什么：排空 skid 的一拍。
  为什么和 `do_direct` 互斥（`!do_direct`）：同一拍只有一个 BRAM 写口（`:22-24` 的输出口只有一组），
  两条路必须在这一拍二选一；优先级由 `:157`/`:168`/`:175` 那一条 if-else 链决定，
  而 `do_direct` 的条件里已经含 `sk_empty`，所以三条式子彼此不可能同时为真。

**只从代码读得到的现象**：`:79` 与 `:86` 两式合起来决定"每一拍交付与否"，
`:81-84` 四式决定"还敢不敢再要"；这一段里没有一行是在等 `rdata` 的内容 —— 搬运机对数据内容完全无感，
它只数拍与地址（`:149` 的地址是 `base_r + burst_idx*(BEATS*8)`）。

小结 1：读任何一段总线握手，先把三行找出来：`X = valid && ready`（交付）、
`can_issue = …`（额度）、`互斥的几条路径`（落点）。这三行在本段分别是 `:86`、`:81-84`、`:87-89`。
小结 2：`dropping` 这一项出现在四条式子里（`:79`、`:81`、`:87-89`），这就是"一个状态要贯穿整个握手"的写法代价 ——
少改一处就会得到"排空期间还在写"的错。下一步：片段 7，行环。

## 第 8 节 片段 7 · 行环形缓存的读写与行消隐边界（`src/rtl/video/raw_line_delay.v:73`）

**这一段是什么**：把一路像素流整体延后 4 个显示行的行环形缓存（`u_raw`，
顶层接法与滞后量的唯一来源见 `src/rtl/top/pl_video_top.v:781-792`）。
它同时是"存储读写"与"边界处理"两段：同拍一写一读（1W1R RAM），
而多出的那 1 拍读延迟会跨过行消隐 —— 这一节讲的就是那一次跨界怎么被补回来的。

引用原文：`src/rtl/video/raw_line_delay.v:73-96`（24 行）

```verilog
        wire bl_head = (!de && v);                       // de 刚掉下去那一拍
        wire [RLOG-1:0]  rslot_rd = bl_head ? (rslot + 1'b1) : rslot;
        wire [CWID-1:0]   x_rd     = bl_head ? {CWID{1'b0}} : x[CWID-1:0];
        wire [RLOG+CWID-1:0] ridx  = {rslot_rd, x_rd};
        // ⚠ 两种"看起来更简单"的办法都是错的，别再试：把读出**再打一拍** ⇒ 每一列都推后一格，
        //   正是 #92 那族整列错位（C1c/C2b 立刻红）；消隐期读地址**一律钳到 0** ⇒ 帧头那一行仍错一行，
        //   因为 `V_TOTAL=625` 不是环深 8 的整数倍，竖消隐那 25 行把槽位相位挪走了。
        always @(posedge clk) begin
            if (de) mem[widx] <= d_in;          // 写：本行本列
            q <= mem[ridx];                     // 读：LINES 行之前的同一列（同拍 ⇒ 只多 1 拍、列不偏）
        end
        // ⚠ `look/head_q` 只许在这**一个** always 里写：上面那个块没有异步复位（RAM 与其读出
        //   本来就不复位），把同一根寄存器分给两个进程综合会直接报多驱动（#68 那一族的老账）。
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                v <= 1'b0; look <= 1'b0; head_q <= {DW{1'b0}};
            end else begin
                v    <= de;                     // de 链与数据链**等长**（都只 1 拍）
                look <= bl_head;                // 预读发出去的那一拍，晚一拍才回到 q
                if (look) head_q <= q;
            end
        end
        assign d_out  = (de && x[CWID-1:0] == {CWID{1'b0}}) ? head_q : q;
        assign de_out = v;
```

逐行：

- `:73` `wire bl_head = (!de && v);` —— 做什么：认出"`de` 刚掉下去"的那一拍（上一拍还有效、本拍无效）。
  为什么用 `v`（`de` 延一拍，`:90`）而不是 `de` 自己：`de` 为 0 时可能是行消隐、也可能是帧消隐的任意一拍，
  加一个"上一拍还在"才把它缩成"每行只有一次的行末那一拍"。
  删掉：下面三条式子失去触发条件，行首那一格没人补 ⇒ 屏上每行第 0 列摆的是消隐期读到的那格。
- `:74` `wire [RLOG-1:0] rslot_rd = bl_head ? (rslot + 1'b1) : rslot;` —— 做什么：预读那一拍把**读行槽**提前一行。
  为什么是 `+1`：那一拍的 `y` 还是刚结束的那一行（顶层栅格的次序在 `src/rtl/video/video_timing.v` 的行计数器写法里），
  要读的是"下一行的第 0 列"，`:70` 的注释写的就是这件事。
- `:75` `wire [CWID-1:0] x_rd = bl_head ? {CWID{1'b0}} : x[CWID-1:0];` —— 做什么：那一拍的**读列地址**钉到 0。
  为什么不能在消隐期一直钳 0（`:77-79` 的第二条"错办法"就是这个）：钳住之后帧头那一行仍然错一行，
  注释给的理由是 `V_TOTAL=625` 不是环深 8 的整数倍，竖消隐那 25 行会把槽位相位挪走。
- `:76` `wire [RLOG+CWID-1:0] ridx = {rslot_rd, x_rd};` —— 做什么：读地址 = {行槽 3 位, 列 9~10 位} 拼接。
  为什么用拼接而不是"行槽 × W + 列"的乘法：环深取的是 `2^RLOG ≥ LINES+1`（`:41`、`:37` 的注释），
  取模就变成切位，不留运行时除法/取模（这一条在 `:37` 写的是硬件规矩）。
- `:77` —— 做什么：注释，列出两个"看起来更简单"的错法之一（读出再打一拍 ⇒ 每一列推后一格）。
  删掉这行注释不会让设计变好，但下一个读代码的人会重新试它 —— 注释里连尺子名都给了（C1c/C2b）。
- `:78` —— 做什么：注释，错法之一的判据名与错法之二（消隐期读地址一律钳 0）的开头。
- `:79` —— 做什么：注释，错法之二为什么也不行（上面 `:75` 那句）。
- `:80` `always @(posedge clk) begin` —— 做什么：**不带复位**的存储进程。
  为什么不带：同文件 `:51` 声明的 `mem` 是 RAM，带异步复位的 RAM 推不出来 ——
  这条在 `src/rtl/process/bilin/fb_bilin.v:145-148` 有同族记录（报 `Synth 8-91` 且整个模块作废），
  在 `src/rtl/axi/axi_frame_writer_gated.v:50-52` 有另一条（报 `Synth 8-4767`，全掉进触发器）。
  删掉这一条而把读写塞进带复位的块：综合器给不出 BRAM/RAM 推断，这一路 8×1024×17 bit 变寄存器堆。
- `:81` `if (de) mem[widx] <= d_in;` —— 做什么：只有有效像素才落 RAM。
  为什么必须门 `de`：`:28` 的端口注释写的口径是"消隐期不许写任何 RAM（否则脏一个格子）"，
  同一个意思在 `src/rtl/process/bilin/fb_bilin.v:18` 的端口注释里也写了一遍。
- `:82` `q <= mem[ridx];` —— 做什么：同一拍发一次读，读 `LINES` 行之前的同一列。
  为什么读写同拍：延迟就正好等于 `LINES` 行 + 1 拍（文件头 `:5-7` 的口径），而"列不偏"靠的就是
  读地址的列部分与写地址的列部分同源。删掉：环不读 ⇒ 输出恒为上一拍的值，整块屏变成拖影。
- `:83` `end` —— 做什么：进程收尾。本行无信息量（结构闭合）。
- `:84` —— 做什么：注释，规定 `look/head_q` 只许在**一个** always 里写。
  为什么单独写出来：上面那个块没有异步复位，把同一根寄存器分给两个进程综合会直接报多驱动 ——
  这一族在 `src/rtl/top/pl_video_top.v:562-563` 也有留痕（端口先引用会造出隐式 net，再显式声明就是重定义）。
- `:85` —— 做什么：注释的后半（"老账"）。
- `:86` `always @(posedge clk or negedge rst_n) begin` —— 做什么：**控制寄存器**进程（带复位），与 `:80` 那个纯数据进程分开。
- `:87` `if (!rst_n) begin` —— 做什么：复位入口。
- `:88` `v <= 1'b0; look <= 1'b0; head_q <= {DW{1'b0}};` —— 做什么：三位一起清。
  为什么 `head_q` 也要清：它是数据缓冲的一部分，`:95` 那一记选择若在第 0 列选中它，
  未清的 X/旧值会直接出现在屏上第一个像素。
- `:89` `end else begin` —— 做什么：正常支路。
- `:90` `v <= de;` —— 做什么：`de` 延一拍，同时它就是 `de_out`（`:96`）。
  为什么"de 链与数据链等长"这么重要：数据只晚一拍（一次 RAM 读出），标签若晚两拍，
  下游就按上一格的有效位取这一格 —— 这一族的实测账在 `src/rtl/top/pl_video_top.v:819-824`（#92 第一笔）。
- `:91` `look <= bl_head;` —— 做什么：记下"上一拍刚发过一次预读"。
  为什么需要这一位：预读发出去到 `q` 摆出来正好晚一拍，没有这一位就不知道 `q` 里是预读值还是本拍值。
- `:92` `if (look) head_q <= q;` —— 做什么：把那一拍的 `q`（预读来的下一行第 0 列）锁进 `head_q`。
  删掉：`:95` 没有可选的对象 ⇒ 行首那一格还是消隐期的格子，屏上出现"贴在左边缘的一条线"，
  这一现象在 `:58-62` 的注释里被逐格量过（源列 160 = 显示列 320 那一格）。
- `:93` `end` —— 做什么：`if/else` 的收尾。本行无信息量（结构闭合）。
- `:94` `end` —— 做什么：进程收尾。本行无信息量（结构闭合）。
- `:95` `assign d_out = (de && x[CWID-1:0] == {CWID{1'b0}}) ? head_q : q;` —— 做什么：只在"有效且是第 0 列"那一拍取 `head_q`，
  其余列取 `q`。为什么中间列一个比特都不动（`:71-72` 的注释）：改动面越小，台架 T1/T3 的既有语义越不用重画。
- `:96` `assign de_out = v;` —— 做什么：有效位与数据同深输出（`:90` 那条等长约束的出口）。

**只从代码读得到的现象**：`:80` 与 `:86` 是两个进程、写两组互不重叠的寄存器
（前者只写 `mem` 与 `q`，后者只写 `v`/`look`/`head_q`）—— 这个切分不是排版偏好，`:84` 写的是它的综合后果。
`generate` 的另一枝 `:46-49`（`LINES==0` 直通）说明"环"这个形状只在真需要滞后时才推出来硬件。

小结 1：读任何一段行缓存，先找三样东西：环深怎么定（`:41`，2 的幂 ≥ LINES+1）、
读写地址怎么拼（`:57`、`:76`，切位代替取模）、跨界那一拍由谁补（`:73-75`、`:91-95`）。
小结 2：这一段的"边界"不是一次算术越界，而是**时序边界** —— 消隐期占了 320 拍而有效列只有 1024 拍，
任何按"每拍"数的逻辑都会在这里与按"有效像素"数的逻辑分手（片段 8 讲的是另一侧）。下一步：片段 8。

## 第 9 节 片段 8 · 扫描计数器与端点夹紧（`src/rtl/video/split_ctrl.v:67`）

**这一段是什么**：分割线位置发生器里的那只三角波计数器。
它同时给出三种边界处理：按有效像素计数（不按拍）、端点先减后比防下溢、手工模式跟住扫描值防跳位。
顶层例化在 `src/rtl/top/pl_video_top.v:885-891`；
该模块文件头 `:3-6` 写着"本模块目前没有被任何顶层例化"，
而 `src/rtl/top/pl_video_top.v:885` 就是它的例化处 —— 两处说法不一致这一件事**按代码为准**记录，
注释与现役接线的冲突另见 `myths.md`（未开写）。

引用原文：`src/rtl/video/split_ctrl.v:67-90`（24 行）

```verilog
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tcnt <= {TICK_BITS{1'b0}};
            swp  <= 13'd0;
            dir  <= 1'b0;
        end else if (de) begin
            if (!auto_en) begin
                // 手工模式下把扫描值**跟住**手工位置 ⇒ 打开 auto 的那一瞬间不跳位
                //（演示里"扫起来先跳一下"会被当成 bug）。夹到 [0,W]，端点由 eff 那一级管。
                swp <= ({5'd0, pos_px} > W) ? W[12:0] : {1'd0, pos_px};
            end else if (tcnt == {TICK_BITS{1'b1}}) begin
                tcnt <= {TICK_BITS{1'b0}};
                if (speed != 4'd0) begin
                    if (!dir) swp <= (swp > up_lim) ? hi13 : swp + step;
                    else      swp <= (swp < down_lim) ? lo13 : swp - step;
                    // 到端点的那一拍同时换向 ⇒ 波形在 lo/hi 各停一拍，绝不越界（T1/T2 判）
                    if (!dir && (swp >= up_lim))   dir <= 1'b1;
                    if ( dir && (swp <= down_lim)) dir <= 1'b0;
                end
            end else begin
                tcnt <= tcnt + 1'b1;
            end
        end
    end
```

逐行：

- `:67` `always @(posedge clk or negedge rst_n) begin` —— 做什么：像素域（`clk_pix` 50 MHz）单域进程。
- `:68` `if (!rst_n) begin` —— 做什么：复位入口。
- `:69` `tcnt <= {TICK_BITS{1'b0}};` —— 做什么：扫描节拍计数器清零，宽度是参数（`:11` 默认 16 ⇒ 一步 = 65536 个有效像素）。
  为什么复位要写这几行：本模块的 `rst_n` 在顶层接的是真像素复位
  （`src/rtl/top/pl_video_top.v:886` 的 `.rst_n(rst_pix_n)`，与 `src/rtl/top/pl_video_top.v:132` 的 `sys_rst_n & locked`），
  不像 `key_debounce` 那一族面对"名义复位"（`clocking-and-reset.md` 第 2 节），所以这里不需要声明初值兜底。
- `:70` `swp <= 13'd0;` —— 做什么：扫描值清零（13 位，`:49` 的注释给的理由是"够放 W≤4095 且加得下一步长不回绕"）。
- `:71` `dir <= 1'b0;` —— 做什么：方向清零（0 = 向 `hi`）。
- `:72` `end else if (de) begin` —— 做什么：**只有有效像素那一拍才动**。
  为什么这是这一段最重要的一行：`:64-66` 的注释记录了不按 `de` 数的后果 ——
  任何拿"每拍计数器"与"第 0/最后一列"比的判据，换一种消隐宽度就会挡住不同的列，
  于是台架与板子给出两个不一样的答案（该注释点名了两例：`tb_rotate_window` 的 `SLOT_LAG` 假红、
  "分割线旁边的颜色条"）。
  删掉 `de` 这一门：扫描速度变成"每拍"，与面板消隐结构耦合，`speed=1` 在不同消隐下走不同步。
- `:73` `if (!auto_en) begin` —— 做什么：手工模式分支。
- `:74` —— 做什么：注释，说明手工模式为什么还要写 `swp`（不写的话打开 auto 那一瞬间会跳位）。
- `:75` —— 做什么：注释后半：夹到 `[0,W]`，端点归下一级管。
- `:76` `swp <= ({5'd0, pos_px} > W) ? W[12:0] : {1'd0, pos_px};` —— 做什么：把 `swp` 跟住手工位置，并先夹一次。
  为什么要位宽补齐再比（`{5'd0, pos_px}` 与 17 位的 `W` 比）：`W` 是 17 位（`:33` 由 `follow` 选源），
  直接比会触发隐式扩展；比较结果决定取 `W[12:0]` 还是取 `pos_px`。
  删掉这一行（手工模式不跟住）：`split auto on` 那一拍 `swp` 从 0 起步 ⇒ 缝瞬间跳到最左，演示里像 bug。
- `:77` `end else if (tcnt == {TICK_BITS{1'b1}}) begin` —— 做什么：节拍计数到全 1 的那一拍才是"走一步"。
  为什么判全 1 而不是判一个常数：全 1 与位宽参数无关，`TICK_BITS` 改档不必改这里。
  删掉：一步都走不了（永远进不了 `:78` 分支），缝停在原位 —— 表现是"auto 设了没反应"。
- `:78` `tcnt <= {TICK_BITS{1'b0}};` —— 做什么：计数归零，开始数下一步。
- `:79` `if (speed != 4'd0) begin` —— 做什么：`speed=0` 是合法输入 ⇒ 钉住不动（端口注释 `:19`）。
  删掉：`step = {9'd0, speed}`（`:57`）为 0 时 `up_lim = hi13 - 0 = hi13`，
  `swp` 会每步加 0 —— 表面一样，但换向判据 `swp >= up_lim` 会在到达之前一直不成立，
  于是 `dir` 永不翻转，缝单向走到端点后停死（这一支的边界另见 `:59-61` 的注释）。
- `:80` `if (!dir) swp <= (swp > up_lim) ? hi13 : swp + step;` —— 做什么：上行：再过一步就越过 `hi` 时直接钉到 `hi13`，否则加一步。
  为什么先减后比（`up_lim = hi13 - step` 在 `:61`）：不把 `swp + step` 放进可能溢出的 13 位里算。
  为什么 `:61` 还要夹一次（`(hi13 >= step) ? … : 13'd0`）：`:59-60` 注释给的输入组合是
  `range 0 0 + speed 15` 这类合法组合 —— `hi13 - step` 会回绕成巨大数，判据"永远没到端点"，
  `swp` 一路涨出范围。删掉这个夹：越界的 `swp` 让下一拍的 `hi13` 选择失效，缝甩出屏幕。
- `:81` `else swp <= (swp < down_lim) ? lo13 : swp - step;` —— 做什么：下行，对称式（`down_lim = lo13 + step`，`:62`）。
  为什么下行不需要防回绕：`lo13 + step` 是加法，最大 13 位内不溢出（`:49` 的位宽账）。
- `:82` —— 做什么：注释：到端点那一拍同时换向，于是波形在两端**各停一拍**。
  "各停一拍"是 `:80-84` 这一组的直接算术结果（这一拍钉端点、同时把 `dir` 翻走，下一拍才真正往回走）。
- `:83` `if (!dir && (swp >= up_lim)) dir <= 1'b1;` —— 做什么：上行到端点 ⇒ 换向。
  为什么这里用 `>=` 而 `:80` 用 `>`：`:80` 要的是"再加一步就越界"，`:83` 要的是"这一拍之后该掉头"，
  两者的边界值相同但含义差一拍；写成同一个号会让换向晚一步（波形冲出端点）。
- `:84` `if ( dir && (swp <= down_lim)) dir <= 1'b0;` —— 做什么：下行到端点 ⇒ 换回。
  删掉 `:83` 或 `:84` 任一条：三角波变成单向锯齿，缝走到端点后不再回来（`hi13` 那一端会一直钉住或一直涨）。
- `:85` `end` —— 做什么：`:79` 那个 speed 判定的收尾。
- `:86` `end else begin` —— 做什么：既不是"走一步"也不是手工 ⇒ 普通的一拍，继续数节拍。
- `:87` `tcnt <= tcnt + 1'b1;` —— 做什么：节拍计数 +1。
- `:88` `end` —— 做什么：if-else 链收尾。本行无信息量（结构闭合）。
- `:89` `end` —— 做什么：`else if (de)` 收尾。本行无信息量（结构闭合）。
- `:90` `end` —— 做什么：进程收尾。本行无信息量（结构闭合）。

**这一段旁边还有两处数字值得一起读**（都在本片段之外，但解释了 `:80-84` 为什么这样写）：
`hi13/lo13` 取的是 `lo_use[12:0]`（`:45-47` 把 `hi < lo` 折成 `[min,max]`，注释明写这是**合法输入**，
`split range 80 20` 就会给出来）；`W` 是 `follow ? SRC_W : DISP_W`（`:33`），
两个分支都是 elaboration 常数，所以注释在 `:27-30` 特别写了"综合出来是 2:1 选线，
既不是除法器也不是桶形移位器"。

**只从代码读得到的现象**：`:96-103`（本片段外）把 `eff` 再夹一次并寄存一拍，注释 `:118-123` 写的是
这一级寄存器的用途 —— 全设计最差路径之一 `u_split_ctrl/swp_reg[7] → u_osd/r_reg[1]`（28 级、含一个 DSP48），
起点就是 `:116` 那条 `eff * pct_c` 乘法。`build/report/timing_summary.rpt:151` 的当前读数是
WNS 0.739 ns / 0 个失败端点 / 总端点 51135，即这一族账今天没有欠着。

小结 1：这一段是"计数器与边界"最密集的样板：三种边界（位宽回绕、端点下溢、输入反向）各由一行专门处理，
`:60-61`、`:45-47`、`:72` 是三把不同的锁。
小结 2：读计数器时先问三件事：它按拍还是按有效计数（`:72`）、它怎么知道自己到端点（`:77`、`:80`）、
端点之外还有谁在夹（`:96-103`）。这三问覆盖本工程所有计数器段。下一步：第 10 节，把辨认方法抽出来。

## 第 10 节 辨认方法：这五种形状在陌生代码里怎么认

| 形状 | 在代码里认什么 | grep 得到的关键字 | 本工程对应行 |
|---|---|---|---|
| 状态机装多字节字段 | 一组同名状态 + 逐位选写入的 `off[..]<=` | `case (st)`、`localparam [2:0] S_` | `src/rtl/eth/frame_reasm.v:37`、`:126-130` |
| 饱和计数 / 不回卷 | 递增前先比一个"到顶"旗标 | `if (!cov_sat)`、`? 16'hFFFF :` | `src/rtl/eth/frame_reasm.v:166-167`、`src/rtl/eth/link_monitor.v:90-92` |
| 格雷码异步 FIFO | 一对反向的两级链 + 只有格雷码跨域 | `bin2gray`、`(* ASYNC_REG` | `src/rtl/eth/dc_fifo.v:29-32`、`:82-95` |
| 翻转位脉冲跨域 | 源域取反赋值 + 目的域相邻两级异或 | `<= ~`、`^ `（异或相邻两级） | `src/rtl/eth/ddr_bank_commit.v:40`、`:47` |
| 总线握手（valid/ready） | 交付 = `valid && ready`，额度 = 一条 `can_issue` 长式 | `rready`、`outstanding` | `src/rtl/axi/axi_frame_writer_gated.v:79-86` |
| 1W1R 行环 / 行缓存 | 地址是 {槽位, 列} 拼接、读写同拍 | `widx`、`ridx`、`ram_style` | `src/rtl/video/raw_line_delay.v:57`、`:76`、`:80-82` |
| 端点夹紧的计数器 | 全 1 判据 + 先减后比 + 换向同拍 | `== {TICK_BITS{1'b1}}`、`up_lim` | `src/rtl/video/split_ctrl.v:61`、`:77-84` |

三条通用读法（只描述本仓库里看到的，不外推）：

1. **凡是"带复位的 always 里写数组"的形状都要停一下。** 本仓库三处存储都专门避开这个形状，
   三处都留了报错文本当理由（`src/rtl/eth/dc_fifo.v:59`、
   `src/rtl/axi/axi_frame_writer_gated.v:50-52`、`src/rtl/process/bilin/fb_bilin.v:145-148`）。
2. **凡是"有效位与数据分开走两条链"的地方都要数一遍级数。**
   级数差一拍的表现是"错一列"、差一行是"错一行"，
   `src/rtl/video/raw_line_delay.v:90` 与 `src/rtl/process/proc_pipeline.v:82-98`
   是同一件事的两种写法（后者给每一级单独取坐标抽头）。
3. **凡是一个数要跨时钟域，先看它是"值"还是"次数"。** 值走格雷码或准静态总线
   （`src/rtl/eth/dc_fifo.v:68`、`src/rtl/eth/snap_cross.v:69-72`），
   次数走翻转位（`src/rtl/eth/ddr_bank_commit.v:40-47`）；两者的同步级数在这两处也不同（2 级 / 3 级）。

小结 1：这三条都是"打开文件搜某个关键字就能看到是不是它"的形式，不依赖经验判断，因此可以被复核。
小结 2：本表右列的 13 个行号就是第 12 节自测题要用的样本 —— 随便挑一条去 Read 都能对上内容。
下一步：第 11 节收口，然后再读 `design-choices.md`。

## 第 11 节 小结与下一步

八段合起来说清了本工程写代码的四条硬规矩：**多字节字段用移位状态机装、饱和计数不许回卷、
跨域按"值/次数"分两条路、存储进程一律不带异步复位**（四条分别落回
`src/rtl/eth/frame_reasm.v:121-143`、`src/rtl/eth/frame_reasm.v:60-72`、
`src/rtl/eth/dc_fifo.v:81-95` 与 `src/rtl/eth/ddr_bank_commit.v:36-51`、
`src/rtl/eth/dc_fifo.v:59-63` 与 `src/rtl/video/raw_line_delay.v:80-83`）。
另外两条（握手要留额度与排空、计数器只按有效像素动）分别是
`src/rtl/axi/axi_frame_writer_gated.v:75-89` 与 `src/rtl/video/split_ctrl.v:67-90` 讲完的。

下一篇去 `design-choices.md`：这一篇回答"这行在做什么、删了会怎样"，
那一篇回答"为什么是这个方案而不是另一个、代价记在哪个文件"。
若只是想把手插进代码里，`hands-on.md` 实验 6（独立副本法改一处看现象）可以直接接着这一篇做。

## 第 12 节 自测题

题目 1：**片段 7 里 `:80-82` 三条式子（`do_direct`/`do_skid`/`sk_drain`）为什么不可能在同一拍同时为真？**
这一篇没有直接给出这条判据的答案（只在 `:89` 那行提到优先级由 `:157`/`:168`/`:175` 的 if-else 链决定）。
去查：`src/rtl/axi/axi_frame_writer_gated.v:87-89` 与 `:157-180`，把三条式子的每一项列成表，
再回答"哪一项让它们互斥"。

题目 2：**`src/rtl/eth/frame_reasm.v:133` 那个界为什么是 `hdr < 32'd4` 而不是 `hdr == 32'd0`？**
去查：`src/host/video_sender.py:33-35` 的包长算术，以及 `src/rtl/eth/frame_reasm.v:182-203` 那两道门的分工；
说出一条**发包方式**，它会让 `hdr == 32'd0` 这条判据失效。

题目 3：**`src/rtl/video/split_ctrl.v:61` 的夹 (`hi13 >= step) ? hi13 - step : 13'd0` 保护的是哪个输入组合？**
去查：`src/rtl/video/split_ctrl.v:59-62` 的注释与 `main.c` 里 `split range` 那条命令的解析处
（`src/ps/main.c` 搜 `range`），并说出这个组合从串口进来之后每一位走哪一行。
