// 功能：被测模块 `icmp_rx`（例化 `dut`，.BOARD_MAC(48'h00_11_22_33_44_55)、
// .BOARD_IP({8'd192,8'd168,8'd1,8'd10})）；覆盖点：echo request 载荷长度的边界逐字节收取——
// rec_byte_num、rec_en 次数、字节顺序、校验和成对累加、每包一次 rec_pkt_done 与状态机
// 收尾，加上 #218 的"声明长度 0"与截断包不再楔死。
// 激励与检查：#4 翻转时钟（8 ns = 125 MHz，与 eth_rxc 同频）；rst_n 复位 5 拍后放开再等
// 3 拍；一包按 7 个 8'h55 + 8'hD5 前导、14 字节以太网头、20 字节 IP 头（total_length 声明
// 28+dl，dl 可与实到 n 不同）、8 字节 ICMP 头（identifier=16'h1234、sequence=16'h5678）
// 加 N 个载荷字节逐拍喂 dv/rxd，载荷取 pay[i]=8'hA0+i；14 轮 N 依次 1,2,3,4,5,6,7,8,15,16,
// 55,56,63,64（奇偶都有、1/2 最能暴露"边界差一个"），每轮喂完最多等 60 拍让 dut.cur_state
// 回到 S_IDLE(7'b000_0001)；随后喂 send_packet(4,0)（声明 0 而线上仍流 4 字节）、
// send_packet(2,10)（只到 2 字节而声明 10），并各跟一个正常包（32 与 20 字节）。
// 判定条件（写各条实际比较的表达式）：A rec_byte_num===N[15:0]；B en_cnt===N；
// C badidx<0（第 k 个 rec_en 上的 rec_data 必须 ===pay[k]）；D reply_checksum===exp_sum(N)
// （成对 {pay[2k],pay[2k+1]} 相加、奇数尾字节放低半 {8'h00,pay[N-1]}、32 位不折叠）；
// E done_cnt===1；F dut.cur_state===S_IDLE && idle_wait<60；G icmp_id===16'h1234 &&
// icmp_seq===16'h5678；K1 done_cnt===1；K2 回 idle；K3 rec_en===1'b0；K4 done_cnt===1 &&
// rec_byte_num===16'd32 && badidx<0；L1 回 idle；L2 done_cnt===1 && rec_byte_num===16'd20；
// L3 rec_byte_num===16'd20（长度属于最后一个合法包，不属于被声明 0 的那一个）。
// 预期结果：通过时每条打 `[tb_icmp_rx_len.v] PASS <标签> | <说明>`，errors==0 收尾打
// `[tb_icmp_rx_len.v] RESULT tb_icmp_rx_len PASS errors=0`；失败时对应条打
// `[tb_icmp_rx_len.v] FAIL <标签> | <说明>`（A/B/C/D 红=最后一个字节的判拍挪了，
// K/L 族同源于 #218 那一个下溢根因），收尾打 `RESULT tb_icmp_rx_len FAIL errors=%0d`，
// 600 us 看门狗到点打 `[tb_icmp_rx_len.v] RESULT tb_icmp_rx_len FAIL timeout`。
// tb_icmp_rx_len —— `icmp_rx` 的载荷长度尺子：把"最后一个字节判在哪一拍"变成可判红的数。
//
// 为什么现在要有它（此前这块 RTL 一条台架判据都没有）：r90 那一轮要把最坏 setup 路径上的
// `icmp_rx_cnt == icmp_data_length - 1`（16 位减法+比较，实测 9 级）换成"把 len-1 提前寄存"
// + 一根"数据窗"旗标（16+1 个 FF），从使能锥上**去掉两条借位链** —— 这就是"资源换时序"。
// 而"看起来等价的改写"动的正是收包链的边界：差一个字节就让应答少/多一个字节、校验和加错一对。
// `tb_video_pipeline_top`（顶层台架）不看 ICMP，`board_verify.sh` 的 ping 只说"通没通"，
// 两者都不足以证明"逐字节仍然一样"。
//
// 判据的期望值全部按**现有 RTL 的语义**写死（成对累加、奇数尾字节放低半、32 位不折叠），
// 所以第一次跑必须在**未修改的树上全绿**（等价性的锚），改完仍全绿才算改对了；
// 最后一条（H/I/J）钉的是厂商码在"声明长度 0"这个畸形包上的既有行为：静默 + 出不去状态机。
// 改动前后这两条都必须一样，所以它既是回归锚，也是"这轮没有顺手改语义"的证明。
//
//   bash sim/run_one.sh tb_icmp_rx_len            # 需要 VP_VIVADO_BIN=<Vivado>/bin
//
// 时钟 125 MHz（与硬件上的 gmii_rx_clk 同频），一包一包地喂：前导 7×55 + D5、
// 以太网头 14、IP 头 20、ICMP 头 8、载荷 N 字节，然后 dv 落回 0 等状态机回 idle。
module tb_icmp_rx_len;

    localparam [47:0] BMAC   = 48'h00_11_22_33_44_55;
    localparam [31:0] BIP    = {8'd192, 8'd168, 8'd1, 8'd10};
    localparam [6:0]  S_IDLE = 7'b000_0001;   // 与 icmp_rx 里的状态编码一致（改编码要一起改）

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #4 clk = ~clk;          // 8 ns = 125 MHz，与 eth_rxc 同频

    reg       dv  = 1'b0;
    reg [7:0] rxd = 8'h00;

    wire        rec_pkt_done;
    wire        rec_en;
    wire [7:0]  rec_data;
    wire [15:0] rec_byte_num;
    wire [15:0] icmp_id;
    wire [15:0] icmp_seq;
    wire [31:0] reply_checksum;

    icmp_rx #(
        .BOARD_MAC(BMAC),
        .BOARD_IP (BIP)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .gmii_rx_dv     (dv),
        .gmii_rxd       (rxd),
        .rec_pkt_done   (rec_pkt_done),
        .rec_en         (rec_en),
        .rec_data       (rec_data),
        .rec_byte_num   (rec_byte_num),
        .icmp_id        (icmp_id),
        .icmp_seq       (icmp_seq),
        .reply_checksum (reply_checksum)
    );

    integer errors = 0;
    task line;                     // 判据标签/说明一律 ASCII（xsim 会截 CJK 的 bit7）
        input [8*44-1:0]  tag;
        input integer     ok;
        input [8*100-1:0] note;
        begin
            if (ok) $display("[tb_icmp_rx_len.v] PASS %0s | %0s", tag, note);
            else    begin $display("[tb_icmp_rx_len.v] FAIL %0s | %0s", tag, note); errors = errors + 1; end
        end
    endtask

    // 一包 = 头 50 字节 + 载荷 n 个字节，IP total_length 里声明 28+dl（dl 可以与 n 不同 = 畸形包）
    reg [7:0] pkt[0:191];
    reg [7:0] pay[0:63];           // 期望的载荷字节（同时也是喂进去的字节）
    integer   N;                   // 本包载荷字节数 = total_length - 28
    integer   nlen;                // 本包总字节数
    integer   i, j, k, m, s32;
    integer   done_cnt, en_cnt, idle_wait, badidx;
    integer   dl;                  // 本包在 IP 头里声明的长度（正常时 = n）
    integer   bn_before;

    task build_packet;
        input integer n;           // 实际驱动的载荷字节数
        input integer d;           // 声明的载荷字节数
        begin
            dl = d;
            for (i = 0; i < n; i = i + 1) pay[i] = 8'hA0 + i[7:0];
            j = 0;
            pkt[j] = 8'h55; j = j + 1;          // st_idle 认到的第一个字节
            for (i = 0; i < 6; i = i + 1) begin pkt[j] = 8'h55; j = j + 1; end
            pkt[j] = 8'hD5;  j = j + 1;         // 帧起始 delimiter
            pkt[j] = BMAC[47:40]; j = j + 1;    // 以太网头 14：目的 MAC(6)
            pkt[j] = BMAC[39:32]; j = j + 1;
            pkt[j] = BMAC[31:24]; j = j + 1;
            pkt[j] = BMAC[23:16]; j = j + 1;
            pkt[j] = BMAC[15:8];  j = j + 1;
            pkt[j] = BMAC[7:0];   j = j + 1;
            pkt[j] = 8'hDE; j = j + 1;          // 源 MAC(6)
            pkt[j] = 8'hAD; j = j + 1;
            pkt[j] = 8'hBE; j = j + 1;
            pkt[j] = 8'hEF; j = j + 1;
            pkt[j] = 8'h00; j = j + 1;
            pkt[j] = 8'h11; j = j + 1;
            pkt[j] = 8'h08; j = j + 1;          // 类型 0x0800
            pkt[j] = 8'h00; j = j + 1;
            pkt[j] = 8'h45; j = j + 1;          // IP 头 20：cnt0 IHL=20
            pkt[j] = 8'h00; j = j + 1;          // cnt1 TOS
            pkt[j] = ((28 + dl) >> 8) & 8'hFF; j = j + 1;   // cnt2 total_length 高
            pkt[j] = (28 + dl) & 8'hFF;        j = j + 1;   // cnt3 total_length 低
            pkt[j] = 8'h00; j = j + 1;          // cnt4 就在这一拍寄存 icmp_data_length
            pkt[j] = 8'h00; j = j + 1;          // cnt5
            pkt[j] = 8'h00; j = j + 1;          // cnt6
            pkt[j] = 8'h40; j = j + 1;          // cnt7 TTL
            pkt[j] = 8'h00; j = j + 1;          // cnt8
            pkt[j] = 8'h01; j = j + 1;          // cnt9 protocol = ICMP
            pkt[j] = 8'h70; j = j + 1;          // cnt10 头校验和
            pkt[j] = 8'h00; j = j + 1;          // cnt11
            pkt[j] = 8'h0A; j = j + 1;          // cnt12 源 IP
            pkt[j] = 8'h00; j = j + 1;
            pkt[j] = 8'h00; j = j + 1;
            pkt[j] = 8'h01; j = j + 1;
            pkt[j] = 8'hC0; j = j + 1;          // cnt16 目的 IP 前 3 字节进 des_ip[23:0]
            pkt[j] = 8'hA8; j = j + 1;
            pkt[j] = 8'h01; j = j + 1;
            pkt[j] = 8'h0A; j = j + 1;          // cnt19 第 4 字节 = 10
            pkt[j] = 8'h08; j = j + 1;          // ICMP 头 8：type = echo request
            pkt[j] = 8'h00; j = j + 1;          // code
            pkt[j] = 8'h00; j = j + 1;          // checksum
            pkt[j] = 8'h00; j = j + 1;
            pkt[j] = 8'h12; j = j + 1;          // identifier = 0x1234
            pkt[j] = 8'h34; j = j + 1;
            pkt[j] = 8'h56; j = j + 1;          // sequence   = 0x5678
            pkt[j] = 8'h78; j = j + 1;
            for (i = 0; i < n; i = i + 1) begin pkt[j] = pay[i]; j = j + 1; end
            nlen = j;
        end
    endtask

    // 现有 RTL 的累加语义：成对 {b[2k],b[2k+1]}，奇数尾字节放低半 {8'h00,b[N-1]}，32 位不折叠
    function [31:0] exp_sum;
        input integer n;
        begin
            s32 = 0;
            for (m = 0; m + 1 < n; m = m + 2) s32 = s32 + {pay[m], pay[m+1]};
            if ((n % 2) == 1) s32 = s32 + {8'h00, pay[n-1]};
            exp_sum = s32[31:0];
        end
    endfunction

    task send_packet;
        input integer n;
        input integer d;
        begin
            build_packet(n, d);
            dv = 1'b0;
            @(posedge clk); #1;
            for (i = 0; i < nlen; i = i + 1) begin
                dv  = 1'b1;
                rxd = pkt[i];
                @(posedge clk); #1;
            end
            dv  = 1'b0;
            rxd = 8'h00;
        end
    endtask

    // 监视：rec_en 每一拍收一个字节，顺序必须与 pay[] 一致
    reg [7:0] cap0, cap3;
    always @(posedge clk) begin
        if (rec_en === 1'b1) begin
            if (en_cnt == 0) cap0 = rec_data;
            if (en_cnt == 3) cap3 = rec_data;
            if (en_cnt < 64 && rec_data !== pay[en_cnt]) begin
                if (badidx < 0) badidx = en_cnt;
            end
            en_cnt = en_cnt + 1;
        end
        if (rec_pkt_done === 1'b1) done_cnt = done_cnt + 1;
    end

    // ================================================================= 主流程
    initial begin
        errors = 0;
        for (i = 0; i < 192; i = i + 1) pkt[i] = 8'h00;
        for (i = 0; i < 64;  i = i + 1) pay[i] = 8'h00;
        rst_n = 1'b0;
        repeat (5) @(posedge clk); #1;
        rst_n = 1'b1;
        repeat (3) @(posedge clk); #1;

        // 奇偶都要有，且 1/2 是最能暴露"边界差一个"的两档
        for (k = 0; k < 14; k = k + 1) begin
            case (k)
                0 : N = 1;   1 : N = 2;   2 : N = 3;   3 : N = 4;
                4 : N = 5;   5 : N = 6;   6 : N = 7;   7 : N = 8;
                8 : N = 15;  9 : N = 16; 10 : N = 55; 11 : N = 56;
                default: N = 63 + (k == 12 ? 0 : 1);
            endcase
            en_cnt = 0; done_cnt = 0; badidx = -1;
            send_packet(N, N);
            // 等状态机回到 idle（改坏了会永远出不来，所以给一个上限并把它做成一条判据）
            idle_wait = 0;
            while (dut.cur_state !== S_IDLE && idle_wait < 60) begin
                @(posedge clk); #1;
                idle_wait = idle_wait + 1;
            end
            line("A_byte_num",       (rec_byte_num === N[15:0]),
                 "rec_byte_num must equal THIS packet's payload length; a length off-by-one lands here");
            line("B_rec_en_count",   (en_cnt === N),
                 "exactly N rec_en pulses; too few or too many = the last-byte window moved");
            line("C_rec_data_order", (badidx < 0),
                 "each rec_data equals the byte in order; a one-byte shift corrupts the reply payload");
            line("D_checksum_pairs", (reply_checksum === exp_sum(N)),
                 "16-bit pair accumulate with odd tail in the low half, no fold, must match bit for bit");
            line("E_done_one_pulse", (done_cnt === 1),
                 "rec_pkt_done fires exactly once per packet (it is what triggers the reply)");
            line("F_back_to_idle",   (dut.cur_state === S_IDLE && idle_wait < 60),
                 "FSM returns to st_idle; a stuck FSM means the last byte was never recognised");
            line("G_id_seq_latched", (icmp_id === 16'h1234 && icmp_seq === 16'h5678),
                 "identifier/sequence from the ICMP header: proves the header parse still lines up");
        end

        // ————— 2026-10-01 #218 把这一段从"钉住厂商楔死"改成"必须走干净" —————
        // 原来 H3/H4/I/J 四条钉的是**读出来的**楔死行为（见 #151：那时只登记、不修）。
        // 今天板上量到它的真实代价：一条 `ping -l 0` 之后**所有**后续包都不再应答，直到重配 PL
        //   （逐轮曲线 build/r101_216_deathpoint.txt）。所以这不再是一个可以"记录在案"的怪癖，是缺陷。
        // 期望值全部由**定义**推出来，不由当前代码推：声明的数据字节数 = IP 总长 − 28 = 0 ⇒
        //   这一包没有数据段 ⇒ 必须照样收尾（一次 rec_pkt_done）、必须回到 st_idle、并且不许影响下一个包。
        // 改前的红：build/r102_218_before.txt（K1/K2/K3/L1/L2 同源于这一个根因，属于连带红，不是五件事）。
        bn_before = rec_byte_num;
        en_cnt = 0; done_cnt = 0; badidx = -1; cap0 = 8'hxx; cap3 = 8'hxx;
        send_packet(4, 0);                       // 声明 0 字节、线上却还流着 4 个字节（-l 0 之后就是 FCS）
        idle_wait = 0;
        while (dut.cur_state !== S_IDLE && idle_wait < 60) begin @(posedge clk); #1; idle_wait = idle_wait + 1; end
        line("K1_decl0_one_done",  (done_cnt === 1),
                 "declared-0 payload must still complete the packet exactly once (that pulse is the reply trigger)");
        line("K2_decl0_back_to_idle", (dut.cur_state === S_IDLE && idle_wait < 60),
                 "FSM must leave st_rx_data when the declared data section is empty (was: wedged forever)");
        line("K3_decl0_en_not_gated_high", (rec_en === 1'b0),
                 "rec_en must not hang high: it is a window, and the window has to close");

        // 端到端的那一条 = 板上症状本身：楔死之后，下一个正常包永远解析不出来
        en_cnt = 0; done_cnt = 0; badidx = -1;
        send_packet(32, 32);
        idle_wait = 0;
        while (dut.cur_state !== S_IDLE && idle_wait < 60) begin @(posedge clk); #1; idle_wait = idle_wait + 1; end
        line("K4_next_ping_still_works", (done_cnt === 1 && rec_byte_num === 16'd32 && badidx < 0),
                 "a 0-byte request must not poison the FOLLOWING 32-byte request (board: all later pings went silent)");

        // 声明比实到多（截断包）：数不到 `len-1`，也必须有尽头 —— 这是 K2 的另一半，红得同一个根
        en_cnt = 0; done_cnt = 0;
        send_packet(2, 10);                      // 只到 2 个字节，声明 10
        idle_wait = 0;
        while (dut.cur_state !== S_IDLE && idle_wait < 60) begin @(posedge clk); #1; idle_wait = idle_wait + 1; end
        line("L1_truncated_back_to_idle", (dut.cur_state === S_IDLE && idle_wait < 60),
                 "when the line goes idle before the declared count, the FSM must still escape st_rx_data");
        en_cnt = 0; done_cnt = 0; badidx = -1;
        send_packet(20, 20);
        idle_wait = 0;
        while (dut.cur_state !== S_IDLE && idle_wait < 60) begin @(posedge clk); #1; idle_wait = idle_wait + 1; end
        line("L2_after_truncated_next_works", (done_cnt === 1 && rec_byte_num === 16'd20),
                 "and the next packet must parse — a truncated frame is not a licence to wedge the receiver");
        // 原来那些"畸形包不写 rec_byte_num"的观察仍然留着，但它不再期望"永远出不去"
        line("L3_decl0_did_not_fake_a_length", (rec_byte_num === 16'd20),
                 "rec_byte_num now belongs to the LAST well-formed packet, not to the wedged declared-0 one");

        if (errors == 0) $display("[tb_icmp_rx_len.v] RESULT tb_icmp_rx_len PASS errors=0");
        else             $display("[tb_icmp_rx_len.v] RESULT tb_icmp_rx_len FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #600000;
        $display("[tb_icmp_rx_len.v] RESULT tb_icmp_rx_len FAIL timeout");
        $finish;
    end

endmodule
