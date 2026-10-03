#!/usr/bin/env python3
# build/r94_geom_osd.py —— #93（旋转时把实际生效的倍率钳进 fit）+ #128（OSD 的 FPS 格改数"写进屏的新帧"）。
# 全部用**单行**正则替换：这个仓库的文件是 CRLF，多行 old_string 会静默匹配不上（#127-1 那一刀
# 我就是先试多行、AssertionError 才发现的）。每处替换都要求"恰好一次"，否则 SKIP 不动文件。
import io, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(ROOT, 'src', 'rtl', 'top', 'pl_video_top.v')
t = io.open(P, encoding='utf-8', newline='').read()
before = t

def one(pat, rep, label, count=1):
    global t
    m = re.findall(pat, t, re.M)
    if len(m) != count:
        print(f"SKIP {label}（匹配 {len(m)} 次，要求 {count}）")
        return False
    t = re.sub(pat, lambda mm: rep, t, count=count, flags=re.M)
    print(f"OK   {label}")
    return True

# ---------- #93：旋转态钳进 fit ----------
clamp = ("""    // #93：只要在读旋转，就把**实际生效**的倍率钳到 `zoom_fit` 那一档之内（inv 越大画面越小）。
    //   `zoom_fit` 早就算好了"这个角度刚好装得下"（W'=s(W|cos|+H|sin|)≤W），但 `fit_en` 只服务自动档，
    //   手动档可以任意放大 ⇒ 角点出屏，而演示口径写的是"旋转时倍率跟着角度自动收，整幅永远在屏内"。
    //   非旋转时一个字都不改（1.00x 就是 1.00x）；旋转时"再缩小"仍然有效，只是不能放大到画外。
    //   ⚠ 这一档必须同时喂给 `zoom_mapper`、`zoom_snap`(lane23) 和 `status` —— 屏上、回读、实际取样
    //   三处说同一个数，否则就是 #118 那一族"默认档各说各话"的翻版。
    wire [9:0] inv_eff = rot_on ? ((inv_used > inv_fit) ? inv_used : inv_fit) : inv_used;
    zoom_mapper #(.IMAGE_W(IMG_W), .IMAGE_H(IMG_H)) u_zmap (""")
ok1 = one(r'^    zoom_mapper #\(\.IMAGE_W\(IMG_W\), \.IMAGE_H\(IMG_H\)\) u_zmap \($', clamp, '#93 插入 inv_eff 钳制')
ok2 = one(r'^        \.inv_scale\(inv_used\), \.angle\(angle\), \.rotate_en\(rot_on\),$',
          '        .inv_scale(inv_eff), .angle(angle), .rotate_en(rot_on),', '#93 zoom_mapper 吃 inv_eff')
ok3 = one(r'^        \.zoom_active\(zoom_active\), \.zoom_dir\(zoom_dir\), \.inv_scale\(inv_used\),$',
          '        .zoom_active(zoom_active), .zoom_dir(zoom_dir), .inv_scale(inv_eff),', '#93 lane23 快照吃 inv_eff')
ok4 = one(r'assign status = \{zoom_dir, zoom_active, inv_used,',
          'assign status = {zoom_dir, zoom_active, inv_eff,', '#93 status 回读吃 inv_eff')

# ---------- #128：OSD 的 FPS 格改数"写进屏的新帧" ----------
old_cnt = r"""    reg [31:0] fps_acc;
    reg [25:0] sec_div;
    reg [7:0]  fps_q;"""
new_cnt = """    reg [31:0] fps_acc;
    reg [25:0] sec_div;
    reg [7:0]  fps_q;
    // #128：这一格原来数的是 `vs_tick`（**显示场同步**，本机 ≈59.5/s），可它挂在 `FPS:` 这个名字下面，
    //   推 25 fps 的流也念 60 ⇒ 名字与数是两回事（ISSUES #153/#157）。现在改成数
    //   "**真的写进屏的新帧**"：`row_done` 每发生一次 = 有一帧被整帧搬进显示缓存。
    //   `row_done` 在 axi 域 ⇒ 走仓库里既有的"翻转 + 3FF 边沿检测"（同 ddr_bank_commit / lat_hb_tog 那一族，
    //   总线一次一位、绝不拿 2FF 当总线用，见 #65 与 #88 的教训）。
    reg       cmt_tgl_axi;
    (* ASYNC_REG = "TRUE" *) reg [2:0] cmt_sync;"""
ok5 = one(old_cnt, new_cnt, '#128 声明翻转位与同步器')

old_blk = r"""    always @(posedge clk_pix) begin
        vs_pix_d0 <= vs_d11; vs_pix_d1 <= vs_pix_d0;
    end"""
new_blk = old_blk + """
    // axi 域：每提交一帧翻一次（这一拍只写这一个位，别的都不碰）
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) cmt_tgl_axi <= 1'b0;
        else if (row_done) cmt_tgl_axi <= ~cmt_tgl_axi;
    end"""
ok6 = one(old_blk, new_blk, '#128 axi 域翻转位')

old_acc = """    always @(posedge sys_clk or negedge rst_pix_n) begin
        if (!rst_pix_n) begin
            sec_div <= 0; fps_acc <= 0; fps_q <= 0;"""
new_acc = """    always @(posedge sys_clk or negedge rst_pix_n) begin
        if (!rst_pix_n) begin
            sec_div <= 0; fps_acc <= 0; fps_q <= 0; cmt_sync <= 3'b000;
        end else begin
            cmt_sync <= {cmt_sync[1:0], cmt_tgl_axi};"""
ok7 = one(old_acc, new_acc, '#128 同步器进复位清单 + 采样')

old_inc = """            sec_div <= sec_div + 1'b1;
            if (vs_sys) fps_acc <= fps_acc + 1'b1;"""
new_inc = """            sec_div <= sec_div + 1'b1;
            if (cmt_sync[1] & ~cmt_sync[2]) fps_acc <= fps_acc + 1'b1;"""
ok8 = one(old_inc, new_inc, '#128 累加改成"提交过一帧"')

io.open(P, 'w', encoding='utf-8', newline='').write(t)
print("文件 %d -> %d 字节（%s）" % (len(before), len(t), "变长=只加没删" if len(t) > len(before) else "注意：变短了"))
print("成功 %d/8 处" % sum([ok1, ok2, ok3, ok4, ok5, ok6, ok7, ok8]))
# vs_sys 现在没有读者了：留着会撞"没人用的信号"那类清理项，先报出来给人看，不偷偷删
print("vs_sys 还剩几处引用：%d（0 就说明 vs_pix_d*/vs_sys 整段变成死逻辑，要一起退役）"
      % len(re.findall(r'\bvs_sys\b', t)))
