# r110 台架侧待落的小刀（判据补牙三条 + 两支 watchdog）—— 抄出来照做，`sim/` 空下来一次做完

写这份的理由：这三条都是自己**复算过**的（不是子代理的转述），而 `sim/` 现在被在飞的链子占着
—— 现在动它，`tb_edge_rim` 的编译指纹会和本轮位流不同源，门禁第 15 项就作废。所以先把刀口写成可照抄的形状。
落刀顺序也有讲究：**watchdog 先加**，因为一个挂死的台架会把后面所有的读数都变成"没有读数"。

## 1) 给 `tb_udp_reasm` 与 `tb_icmp_len_wrap` 补 watchdog（照 `tb_icmp_ping0.v:128-134` 的现成形状）
现成形状（`tb_icmp_ping0.v` 里就是这两段 initial 并存）：
```verilog
    initial begin
        #30_000_000;
        $display("FAIL tb_icmp_ping0 timeout");
        $display("RESULT tb_icmp_ping0 FAIL nfail=timeout");
        $finish;
    end
```
- `tb_udp_reasm.v`：收尾现在是 `PASS/FAIL tb_udp_reasm errors=%0d` + `$finish`（:130 附近），**没有超时支** ⇒ 楔死时整支挂住、
  `run_one.sh` 只能靠外层看门狗，读出来是"没结果"。补一个同形状的 `initial`，token 用 `RESULT tb_udp_reasm FAIL nfail=timeout`。
- `tb_icmp_len_wrap.v`：同样补；它比前者更要命，因为它的 `R1` 判据是"状态不等于 S_RX_DATA"那种手抄编码形状（:115），
  一旦状态机改了名，判据会**永不命中而静默变绿**——挂死至少比假绿诚实。
  `timescale` 必须是 `1ns/1ps`（这两支文件头已有；`#30_000_000` 在 1ns 单位下 = 30 ms 仿真时间，与 ping0 同一量级）。
- 判"加对了"的方式：把某一档激励故意改成永不收尾（例如去掉一次 `@(posedge done)` 的等待），
  跑 `bash build/sim/run_one.sh <tb>` 必须打出 **rc=3** 且 `VERDICT` 里带 `nfail=timeout`
  （`run_one.sh --verdict` 认 `^FAIL <tb> (errors=|timeout)` 这一族形状，见该文件 :30-38 的注释）。

## 2) `tb_udp_reasm.v:119-125` 的 duplicate-overwrite —— 现在是空转，改成能红的两条
现状（逐字）：
```verilog
        // 4) duplicate packet just overwrites
        send_pkt(0, 16'hAAAA, 16'h5555, 1);
        send_pkt(0, 16'hAAAA, 16'h5555, 1);
        repeat (3) @(posedge clk);
        if (capture[0] !== 16'hAAAA) begin ... FAIL dup ...
```
两包**载荷相同** ⇒ 第一包写完 `capture[0]` 就已满足，重复包被丢/被覆盖都绿；`ncap`（:28、:34 算了）从不参与判定。
改法（两条各打一行，别合成一条）：
```verilog
        // 4a) 重复包必须被**丢掉**（不是覆盖）：第二包换载荷，屏外内存必须还留着第一包的字
        send_pkt(0, 16'hAAAA, 16'h5555, 1);            // 第一包
        send_pkt(0, 16'h6666, 16'h7777, 1);            // 同偏移的重复包，载荷不同 ⇒ 覆盖就看得见
        repeat (3) @(posedge clk);
        if (capture[0] !== 16'hAAAA) begin
            $display("FAIL dup-packet overwrote the slot (capture[0]=%h, expected 1st packet AAAA)", capture[0]);
            errors = errors + 1;
        end else $display("PASS duplicate packet does NOT overwrite (first packet stands)");
        // 4b) 机会地板：这一档真的产生过"重复包被丢"这件事，否则上面那条是空集绿
        if (s_bad == 0) begin
            $display("FAIL no chance exercised: s_bad=0, the duplicate case never got a look");
            errors = errors + 1;
        end else $display("PASS duplicate chance: s_bad=%0d", s_bad);
```
（**计数器名字核对过**，别照这页的初稿写错：`tb_udp_reasm.v:14/:23` 给的是
   `s_frames / s_pkts / s_bytes / s_bad / s_oob`（`.stat_bad(s_bad)`、`.stat_oob_off(s_oob)`），
   **没有 `s_badc` 这个东西**；重复包这一档该用的是 `s_bad`（坏/被拒包计数）。
   `ncap`（:28/:34）是台架自己数的捕获次数，拿它当"DUT 给过机会"的地板是**自证**，不算地板。
   两文件的 `` `timescale 1ns/1ps `` 都核对过（`tb_udp_reasm.v:2`、`tb_icmp_len_wrap.v:12` 注释头之后），
   所以 `#30_000_000` 在 1 ns 单位下 = 30 ms 仿真时间，与 ping0 同一量级。）

## 3) `tb_udp_reasm.v:32` 的 `if (wr_addr < 128)` 静默丢越界写 —— 补"被拒且被数出来"
这是 #201 的同一盲区（台账 10382 记它在变异下 9 条全绿）。改法：保留丢弃行为（它是**激励侧**的捕获数组，不是 DUT），
但把"被丢掉"这件事数出来并设地板：`else oob_cap = oob_cap + 1;` ⇒ 新增一条 `PASS oob capture rejected & counted`
（判 `oob_cap == 0`；非 0 就是激励越界，红得清清楚楚），从此"捕获数组太小"不再可能伪装成"设计是对的"。

## 4) `tb_head_rot_displace.v` 的文件头主张与代码不符 —— 二选一，别两头都不动
代码事实：`inv_force` 只在 :40 声明成 `10'd256`，之后**没有一次赋值**；`inv_now/inv_prev` 在 :112/:117 从 DUT 的 `inv_fit` 取来，
只出现在 :133/:142 的 `$display` 里 ⇒ 这支**没有**判"倍率随角度同步换档"，但 :15 写着"`inv_fit` 也跟着换成 θ-k 那一档，与顶层一致"。
- 选 A（补牙）：第二遍把 `.inv_scale(inv_prev)` 真的接进 mapper（`inv_prev` 已经是 DUT 自己算的那一档），
  并加一条比较：`if (inv_now == inv_prev) FAIL "θ 与 θ-k 的 inv_fit 相同 ⇒ zoom_fit 这支没参与"` —— 这条同时是"zoom_fit 有没有真的进链"的机会计数；
- 选 B（改口）：把 :15 那句改成"`inv_fit` 只打印不比对（这一档与顶层的差别不在本台架射程内，见顶层 C5c）"。
倾向 A：它把巡检报的那条"空转"变成一条真判据，代价是 mapper 端口连接要动一行。

## 5) 共同的收尾纪律
每一条都各打一行 `PASS/FAIL`（rule 121），**并且**在改完之后跑：
`bash build/sim/run_one.sh tb_udp_reasm`、`bash build/sim/run_one.sh tb_icmp_len_wrap`、`bash build/sim/run_one.sh tb_head_rot_displace`
+ `bash build/timing_lane.sh`（约 9 分钟）与 r109 基线对照：**只允许变好，不许有第 21 支变红**；
再走一次变异对照（把改动的判据退回，必须只红该红的那条），才算落定。
