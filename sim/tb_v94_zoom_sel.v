`timescale 1ns/1ps
// tb_v94_zoom_sel —— V8-8 手动缩放档的两件事：
//   ① 每一档**真的**落到那个 inv，并且 OSD 的 `zoom_code` 报回同一个档号（往返）；
//   ② 手动/自动之间切换**不瞬移**（呼吸被打断与恢复的那一帧都不许跳）。
// 为什么期望值不在 RTL 里抄一份：表值 `1023/776/512/341/256/192/171/128` 与
// `zoom_code` 的中点判据是**同一个约定的两端**，抄过来就等于"用被测代码验被测代码"。
// 这里改成从**倍率定义**算：inv 是 Q8 倒数尺度 ⇒ `inv = round(25600 / (倍率×100))`，
// 倍率用整数万分比写死（2500 = 0.25x … 20000 = 2.00x），再加 10 bit 的天花板。
// 于是 RTL 的表写错一位、或某档被改动而中点判据没跟上，这里就红 —— 而不是跟着一起错。
module tb_v94_zoom_sel;
    localparam [9:0] INV_LO = 10'd256, INV_HI = 10'd512, STEP = 10'd2;

    reg clk = 0, rst_n = 0, enable = 0, frame_start = 0, manual = 0;
    reg [2:0] zsel = 3'd0;
    // #93：把拟合值与旋转标志变成**可驱动的激励**（原来端口上是常量 1'b0/10'd256，钳制那一支永远走不到）
    reg       rotate_en = 1'b0;
    reg [9:0] inv_fit_sim = 10'd256;
    wire [9:0] inv_scale;
    wire [9:0] inv_used;
    wire       rot_forced;
    wire [2:0] zoom_code;
    wire zoom_active, dir;

    zoom_ctrl #(.INV_LO(INV_LO), .INV_HI(INV_HI), .STEP(STEP)) dut (
        .clk(clk), .rst_n(rst_n), .enable(enable),
        .zsel(zsel), .manual(manual), .frame_start(frame_start),
        .rotate_en(rotate_en), .fit_en(1'b0), .inv_fit(inv_fit_sim),   // V9-2 的第三种来源：这台架判的是八档，fit_en 钉成"不参与"
        .inv_scale(inv_scale), .inv_used(inv_used),   // #93：现在要读它 —— 屏上/lane23/mapper 必须说同一个数
        .rot_forced(rot_forced),
        .zoom_active(zoom_active), .zoom_code(zoom_code), .dir(dir)
    );

    always #5 clk = ~clk;

    // 帧节拍：每 40 拍一个 frame_start 脉冲（一拍宽）
    integer fcnt;
    initial fcnt = 0;
    always @(posedge clk) begin
        fcnt <= fcnt + 1;
        if (fcnt == 39) begin fcnt <= 0; frame_start <= 1; end
        else frame_start <= 0;
    end

    integer pass, fail, i, j;
    reg [9:0] before, after_v, max_inv, min_inv;
    integer nstep_ok, nstep_bad, t3_bad;

    initial begin
        pass = 0; fail = 0; t3_bad = 0;
        fcnt = 0; enable = 0; manual = 0; zsel = 3'd0;
    end

    task chk;
        input [8*100-1:0] name;
        input ok;
        begin
            if (ok) begin pass = pass + 1; $display("  PASS %0s", name); end
            else    begin fail = fail + 1; $display("  FAIL %0s", name); end
        end
    endtask

    // ---- 独立算出来的八档期望值（万分倍 → Q8 倒数尺度，四舍五入，夹到 10 bit 天花板）----
    function [9:0] exp_inv;
        input [2:0]    code;
        input [15:0]   x10000;         // 该档的倍率 ×10000
        reg   [31:0]   num, den, q;
        begin
            // inv = round(256 / 倍率) = round(256*10000 / x)；"加上半个除数"就是四舍五入
            num = 32'd5120000 + {16'd0, x10000};
            den = {16'd0, x10000} << 1;
            q   = num / den;
            exp_inv = (q > 32'd1023) ? 10'd1023 : q[9:0];
        end
    endfunction

    // 倍率万分比：档号与 OSD 那张表同一个约定
    function [15:0] x10k;
        input [2:0] code;
        begin
            case (code)
                3'd0:    x10k = 16'd2500;   // 0.25x
                3'd1:    x10k = 16'd3300;   // 0.33x
                3'd2:    x10k = 16'd5000;   // 0.50x
                3'd3:    x10k = 16'd7500;   // 0.75x
                3'd4:    x10k = 16'd10000;  // 1.00x
                3'd5:    x10k = 16'd13300;  // 1.33x
                3'd6:    x10k = 16'd15000;  // 1.50x
                default: x10k = 16'd20000;  // 2.00x
            endcase
        end
    endfunction

    // 等到 inv 真的换了一次（最多 60 拍）。结果放在 wc_ok：**不用参数回传**，
    // 免得调用方拿同一个整数既当"本轮结果"又当"累计器"，一条判据覆盖另一条。
    reg wc_ok;
    task wait_change;
        reg [9:0] v0;
        integer k;
        begin
            v0 = inv_scale; wc_ok = 0;
            for (k = 0; k < 60 && !wc_ok; k = k + 1) begin
                @(negedge clk);
                if (inv_scale !== v0) wc_ok = 1;
            end
        end
    endtask

    initial begin
        $display("[tb_v94_zoom_sel.v:109] == tb_v94_zoom_sel：八档往返 + 手动/自动交接不瞬移 ==");
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (3) @(posedge clk);

        // ---------- T1 复位形状 ----------
        chk("T1 复位后 inv=256(1.00x)、code=4、dir=0",
            inv_scale == 10'd256 && zoom_code == 3'd4 && dir == 1'b0);

        // ---------- T2 自动呼吸：步进恰好 STEP，且不越带 ----------
        enable = 1;
        nstep_ok = 0; nstep_bad = 0;
        max_inv = inv_scale; min_inv = inv_scale;
        // ⚠ **逐拍**看，不许"隔 N 拍比一次"：帧节拍是 40 拍，采样步长若是 40 的因子
        //   （第一版是 2 拍），变化永远落在两次采样之间 ⇒ steps_ok=0 而 inv 明明在走
        //   （第一版就把这条骗成了 T2c 的假红）。
        before = inv_scale;
        // 一整趟呼吸 = 上 128 步 + 下 128 步 = 256 个帧节拍 = 10240 拍 ⇒ 窗口要盖住**一整趟**，
        // 不然只看得见"在上升"，看不见"到边会翻向"（第一版跑 900 拍就是卡在 300 就收工，
        // 于是 T2b/T2c 一起红 —— 那是窗口不够长，不是硬件不呼吸）。
        for (j = 0; j < 11000; j = j + 1) begin
            @(negedge clk);
            after_v = inv_scale;
            if (after_v !== before) begin
                if (after_v == before + STEP || after_v == before - STEP ||
                    after_v == INV_HI       || after_v == INV_LO)
                    nstep_ok = nstep_ok + 1;
                else nstep_bad = nstep_bad + 1;
            end
            if (after_v > max_inv) max_inv = after_v;
            if (after_v < min_inv) min_inv = after_v;
            before = after_v;
        end
        chk("T2 自动呼吸每一步都是 STEP 或落在边界（没有跳步）", nstep_bad == 0);
        chk("T2b 呼吸真的走起来了（一整趟至少 200 次变化，否则这条是空跑）", nstep_ok >= 200);
        chk("T2c 自动范围就是带内 [256,512]", min_inv == INV_LO && max_inv == INV_HI);
        $display("  DBG T2 steps_ok=%0d bad=%0d min=%0d max=%0d", nstep_ok, nstep_bad, min_inv, max_inv);

        // ---------- T3 八档往返：设进去的档号 == 屏上报回的档号 ----------
        for (i = 0; i < 8; i = i + 1) begin
            @(negedge clk); manual = 1; zsel = i[2:0];
            wait_change;
            if (!wc_ok) begin
                $display("[tb_v94_zoom_sel.v:152] DBG T3 档 %0d 没等到 inv 变化", i);
                t3_bad = t3_bad + 1;
            end else begin
                repeat (2) @(negedge clk);            // code 比 inv 晚一拍
                if (inv_scale !== exp_inv(i[2:0], x10k(i[2:0])) || zoom_code !== i[2:0]) begin
                    t3_bad = t3_bad + 1;
                    $display("[tb_v94_zoom_sel.v:158] DBG T3 档 %0d: inv=%0d 期望=%0d code=%0d",
                             i, inv_scale, exp_inv(i[2:0], x10k(i[2:0])), zoom_code);
                end
            end
        end
        chk("T3 八档逐个：inv == 从倍率算出来的期望值，且 zoom_code 报回同一个档号", t3_bad == 0);

        // ---------- T4 手动期间 inv 钉住（呼吸被打断）----------
        @(negedge clk); zsel = 3'd3;                  // 0.75x
        wait_change;   // 换档要等一个帧节拍才落进 inv
        before = inv_scale;
        repeat (200) @(negedge clk);                  // 跨 5 个帧节拍
        chk("T4 手动期间 inv 一动不动（换了档号之外的 200 拍里没有任何帧节能改它）",
            inv_scale == before);

        // ---------- T5 手动→自动：交接那一帧不许瞬移 ----------
        // 最狠的一档是 0.25x（inv=1023，在呼吸带**外**）：老写法会一帧写回 512 ⇒ 画面弹半幅。
        @(negedge clk); zsel = 3'd0;
        wait_change;
        chk("T5a 先停在 0.25x（inv=1023，带外）", inv_scale == 10'd1023);
        @(negedge clk); manual = 0;
        before = inv_scale;
        wait_change;
        if (!wc_ok) chk("T5b 切回自动后确实动了（没等到变化=判据空跑）", 0);
        else begin
            after_v = inv_scale;
            chk("T5b 切回自动的第一帧只走一步（1023→1021，不是 512）", after_v == before - STEP);
            $display("  DBG T5 before=%0d after=%0d dir=%0b", before, after_v, dir);
        end

        // 从带内（0.75x=341）切回自动同样只能走一步
        @(negedge clk); manual = 1; zsel = 3'd3;
        wait_change;
        before = inv_scale;
        @(negedge clk); manual = 0;
        wait_change;
        if (!wc_ok) chk("T5c 从带内切回自动也动了（没等到=空跑）", 0);
        else begin
            after_v = inv_scale;
            chk("T5c 从带内 0.75x 切回自动也是走一步",
                after_v == before + STEP || after_v == before - STEP);
        end

        // ---------- T6 enable=0 优先于手动（关掉缩放就回 1.0x）----------
        @(negedge clk); manual = 1; zsel = 3'd7;      // 2.0x
        wait_change;
        chk("T6a 先停在 2.0x（inv=128）", inv_scale == 10'd128);
        @(negedge clk); enable = 0;
        repeat (8) @(negedge clk);
        chk("T6b enable=0 时手动档让位：回 INV_LO 且 zoom_active=0",
            inv_scale == INV_LO && zoom_active == 1'b0);

        // ---------- T7 带外走回带内：全程每帧只走一步 ----------
        @(negedge clk); enable = 1; manual = 1; zsel = 3'd0;
        wait_change;
        nstep_bad = 0; before = inv_scale;
        @(negedge clk); manual = 0;
        for (j = 0; j < 280 && before > INV_HI; j = j + 1) begin
            wait_change;
            if (wc_ok) begin
                after_v = inv_scale;
                if (after_v != before + STEP && after_v != before - STEP) nstep_bad = nstep_bad + 1;
                before = after_v;
            end
        end
        chk("T7 从 0.25x 走回呼吸带：每帧一步、280 帧内进带",
            nstep_bad == 0 && before <= INV_HI);
        $display("[tb_v94_zoom_sel.v:225] DBG T7 回到 inv=%0d 用了 %0d 步", before, j);

        // ---------- T8 #93：旋转态把生效倍率钳进 fit，而 OSD 的档号跟着**同一个数** ----------
        // a 是负对照（不旋转时一个字都不改，改前改后都必须绿）；b~f 是这一刀的正文，改前必须红。
        @(negedge clk); enable = 1; manual = 1; zsel = 3'd4; rotate_en = 0; inv_fit_sim = 10'd341;
        repeat (45) @(negedge clk);          // 手动档只在帧首换 ⇒ 至少跨一个帧节拍（40 拍）
        chk("T8a no-rotate: inv_scale=inv_used=256, rot_forced=0 (control)",
            inv_scale == 10'd256 && inv_used == 10'd256 && rot_forced == 1'b0);
        @(negedge clk); rotate_en = 1;
        repeat (6) @(negedge clk);
        chk("T8b rot+1.00x with fit=341: inv_used clamped to 341",
            inv_used == 10'd341 && rot_forced == 1'b1);
        chk("T8c OSD code follows the clamp: code(341)=3=0.75x",
            zoom_code == 3'd3);
        @(negedge clk); zsel = 3'd2;                  // 0.50x：inv=512，画面比 fit 还小 => 不该被拉回
        wait_change; repeat (6) @(negedge clk);
        chk("T8d rot+0.50x stays 512 (shrinking still works), rot_forced=0",
            inv_scale == 10'd512 && inv_used == 10'd512 && rot_forced == 1'b0);
        @(negedge clk); zsel = 3'd7;                  // 2.00x：inv=128，放大 => 旋转态让位
        wait_change; repeat (6) @(negedge clk);
        chk("T8e rot+2.00x yields to fit: inv_scale=128 kept, inv_used=341",
            inv_scale == 10'd128 && inv_used == 10'd341 && rot_forced == 1'b1);
        @(negedge clk); rotate_en = 0;
        repeat (6) @(negedge clk);
        chk("T8f rotate off restores 128 (reversible, no residue)",
            inv_used == 10'd128 && rot_forced == 1'b0 && inv_scale == 10'd128);

        $display("");
        $display("[tb_v94_zoom_sel.v:253] 口径提醒：这里判的是**档位选择与交接节拍**，画面上像素对不对是 zoom_mapper 的事");
        $display("[tb_v94_zoom_sel.v:254] （tb_zoom_* 那一套）。八档表与 zoom_code 的中点判据是同一个约定的两端，");
        $display("[tb_v94_zoom_sel.v:255] T3 就是把这两个约定钉在一起：任何一边被改而另一边没跟上，这一条就红。");
        $display("TB DONE pass=%0d fail=%0d", pass, fail);
        if (fail != 0) $display("TB RESULT FAIL");
        else $display("TB RESULT PASS");
        $finish;
    end
endmodule
