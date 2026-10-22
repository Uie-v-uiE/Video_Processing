`timescale 1ns/1ps
// Analysis-only: how much source-row / source-tile locality does the display
// request stream have under rotation? Decides whether a DDR line cache can
// replace the BRAM frame buffer, or whether rotation needs a tile cache.
// No pass/fail: prints request count, line-cache hit rate (8 rows) and
// tile-cache hit rate (16 8x8 tiles) for a few angle/zoom arms.
`default_nettype none
module tb_ddr_line_locality;
    localparam integer W = 1024, H = 600, SW = 512, SH = 300;

    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    reg [9:0]  inv = 10'd256;
    reg [8:0]  ang = 9'd0;
    reg        rot = 1'b0;
    reg [11:0] xin = 0, yin = 0;
    wire [11:0] sx, sy;
    wire        oob;
    wire [7:0]  fx, fy;

    zoom_mapper #(.IMAGE_W(SW), .IMAGE_H(SH)) u (
        .clk(clk), .rst_n(rst_n), .inv_scale(inv), .angle(ang), .rotate_en(rot),
        .x_in(xin), .y_in(yin), .x_out(sx), .y_out(sy), .oob(oob),
        .frac_x(fx), .frac_y(fy)
    );

    reg [11:0] xd0, xd1, xd2, yd0, yd1, yd2;
    always @(posedge clk) begin
        xd0 <= xin; xd1 <= xd0; xd2 <= xd1;
        yd0 <= yin; yd1 <= yd0; yd2 <= yd1;
    end

    integer lc [0:7];       // cached source rows
    integer lage [0:7];
    integer tc [0:15];      // cached tile ids
    integer tage [0:15];
    integer t4 [0:15];      // 4-tap tile cache (same 8x8 tiles)
    integer t4age [0:15];
    integer req, lhit, thit, t4req, t4hit, t4fetch, i, j, tick;
    integer fd, dump_arm;
    integer t4tile [0:3];
    integer row, col, tile;

    task reset_model;
        begin
            for (i = 0; i < 8; i = i + 1) begin lc[i] = -1; lage[i] = 0; end
            for (i = 0; i < 16; i = i + 1) begin tc[i] = -1; tage[i] = 0; t4[i] = -1; t4age[i] = 0; end
            req = 0; lhit = 0; thit = 0; t4req = 0; t4hit = 0; t4fetch = 0; tick = 0;
        end
    endtask

    // LRU hit/miss for an 8-row line cache and a 16-tile 8x8 cache.
    always @(posedge clk) begin
        if (rst_n && !oob && sx < SW && sy < SH) begin
            req = req + 1;
            tick = tick + 1;
            // line cache
            begin : line_lookup
                integer hit;
                hit = 0;
                for (i = 0; i < 8; i = i + 1) begin
                    if (lc[i] == sy) begin
                        hit = 1;
                        lage[i] = tick;
                    end
                end
                if (hit) lhit = lhit + 1;
                else begin
                    j = 0;
                    for (i = 1; i < 8; i = i + 1) if (lage[i] < lage[j]) j = i;
                    lc[j] = sy; lage[j] = tick;
                end
            end
            // tile cache (8x8)
            tile = (sy >> 3) * (SW / 8) + (sx >> 3);
            begin : tile_lookup
                integer hit;
                hit = 0;
                for (i = 0; i < 16; i = i + 1) begin
                    if (tc[i] == tile) begin
                        hit = 1;
                        tage[i] = tick;
                    end
                end
                if (hit) thit = thit + 1;
                else begin
                    j = 0;
                    for (i = 1; i < 16; i = i + 1) if (tage[i] < tage[j]) j = i;
                    tc[j] = tile; tage[j] = tick;
                end
            end
            // 4-tap bilinear view: each request needs (sx,sy),(sx+1,sy),(sx,sy+1),(sx+1,sy+1),
            // clamped at the image edge. Count tile-cache hits/fetches for the same 16-entry cache.
            begin : tap_lookup
                integer tap, tsx, tsy, tile4, hit4;
                for (tap = 0; tap < 4; tap = tap + 1) begin
                    tsx = sx + (tap & 1);
                    tsy = sy + (tap >> 1);
                    if (tsx >= SW) tsx = SW - 1;
                    if (tsy >= SH) tsy = SH - 1;
                    tile4 = (tsy >> 3) * (SW / 8) + (tsx >> 3);
                            t4tile[tap] = tile4;
                    t4req = t4req + 1;
                    hit4 = 0;
                    for (i = 0; i < 16; i = i + 1) begin
                        if (t4[i] == tile4) begin hit4 = 1; t4age[i] = tick; end
                    end
                    if (hit4) t4hit = t4hit + 1;
                    else begin
                        j = 0;
                        for (i = 1; i < 16; i = i + 1) if (t4age[i] < t4age[j]) j = i;
                        t4[j] = tile4; t4age[j] = tick; t4fetch = t4fetch + 1;
                    end
                end
                if (dump_arm) $fwrite(fd, "%0d %0d %0d %0d %0d %0d\n", yd2, yd2*W + xd2, t4tile[0], t4tile[1], t4tile[2], t4tile[3]);
            end
        end
    end

    task run_arm;
        input integer a;
        input integer iv;
        begin
            ang = a[8:0]; inv = iv[9:0]; rot = (a != 0);
            dump_arm = (a == 45 && iv == 256);
            reset_model;
            // two frames: first warms the ROM/pipeline and the model, count second
            for (row = 0; row < H; row = row + 1) begin
                for (col = 0; col < W; col = col + 1) begin
                    @(negedge clk);
                    xin <= col[11:0];
                    yin <= row[11:0];
                end
            end
            repeat (16) @(negedge clk);
            $display("LOC ang=%0d inv=%0d req=%0d line_hit=%0d/%0d tile_hit=%0d/%0d t4_hit=%0d/%0d t4_fetch=%0d bytes=%0d",
                     a, iv, req, lhit, req, thit, req, t4hit, t4req, t4fetch, t4fetch*128);
        end
    endtask

    initial begin
        rst_n = 0;
        fd = $fopen("tile_req.csv", "w");
        repeat (8) @(negedge clk);
        rst_n = 1;
        repeat (8) @(negedge clk);
        run_arm(0,   256);
        run_arm(0,   512);
        run_arm(45,  256);
        run_arm(45,  512);
        run_arm(90,  256);
        run_arm(90,  512);
        run_arm(168, 256);
        run_arm(315, 256);
        $fclose(fd);
        $finish;
    end
endmodule
`default_nettype wire
