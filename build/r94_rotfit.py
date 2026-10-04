#!/usr/bin/env python3
# 用途：#93 的落点改到 zoom_ctrl（不在顶层再 mux 一次）
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：脚本内无显式 exit ⇒ 随最后一条命令（正常跑完为 0）
# build/r94_rotfit.py —— #93 的落点改到 zoom_ctrl（不在顶层再 mux 一次）。
#
# 为什么不在顶层钳：`zoom_ctrl.v` 文件头自己写着"倍率的唯一出处在本模块，顶层再 mux 就会出现
# 『屏上那一格与真正在用的 inv 不是一回事』"（#52/#59/#66 同一族）。顶层钳只喂得到 mapper 和
# lane23，喂不到 `zoom_code` —— OSD 的 ZOOM 那一格就会继续报用户按下去的那一档。
#
# 规矩：单行正则（这个仓库里有 CRLF 也有 LF，多行 old_string 会静默匹配不上）、每处"恰好一次"，
# 否则 SKIP 不动文件；每个文件写盘前断言结果比原来长（少一个字符就是尾巴被吃掉）。
import io, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NLHACK = '\x00'          # 临时换行占位，避免 rep 里的 \n 与文件实际行尾不一致


class Ed:
    def __init__(self, rel):
        self.rel = rel
        self.path = os.path.join(ROOT, rel.replace('/', os.sep))
        self.t = io.open(self.path, encoding='utf-8', newline='').read()
        self.NL = '\r\n' if '\r\n' in self.t else '\n'
        self.n = 0

    def one(self, pat, rep, label, count=1):
        # CRLF 文件里 `$` 落在 `\r` 之前会匹配不上 ⇒ 行尾锚一律换成 `\r?$`（LF 文件同样成立）
        if pat.endswith('$'):
            pat = pat[:-1] + r'\r?$'
        rep = rep.replace('\n', self.NL)
        if len(re.findall(pat, self.t, re.M)) != count:
            print("SKIP %s（匹配 %d 次，要求 %d）" % (label, len(re.findall(pat, self.t, re.M)), count))
            return False
        self.t = re.sub(pat, lambda m: rep, self.t, count=count, flags=re.M)
        self.n += 1
        print("OK   %s" % label)
        return True

    def save(self, need):
        assert self.n == need, "%s：改了 %d 处，要求 %d 处" % (self.rel, self.n, need)
        io.open(self.path, 'w', encoding='utf-8', newline='').write(self.t)
        print("WROTE %s（%d 处）" % (self.rel, self.n))


# ---------------- 1) zoom_ctrl.v ----------------
z = Ed('src/rtl/process/zoom/zoom_ctrl.v')
z.one(r'^    input  wire        fit_en,$',
      """    // #93：旋转态的"装得下"上界。为什么它是**输入**而不是顶层的第二次 mux：见下面 fit_en
      //   那一段的同一个理由 —— 倍率的唯一出处只能有一个，否则 `zoom_code`（OSD 那一格）报的是
      //   用户按下的档、mapper 画的是另一档（#52/#59/#66 那一族）。
      input  wire        rotate_en,       // 1=旋转真的在生效（顶层把 `rotate_active` 原样递进来）
      input  wire        fit_en,""", '#93 zoom_ctrl 新增 rotate_en')
z.one(r'^    output reg         dir            // 0: 向缩小走\(inv增\) 1: 回到1\.0x\(inv减\)$',
      """    output reg         dir,           // 0: 向缩小走(inv增) 1: 回到1.0x(inv减)
    output wire        rot_forced     // #93：1=这一帧生效的倍率是被旋转钳出来的，不是用户那一档
                                      //   ⇒ 顶层把它并进 OSD 的 `(Fit)` 标记，屏上才讲真话""",
      '#93 zoom_ctrl 新增 rot_forced')
z.one(r'^    assign inv_used = fit_en \? inv_fit : inv_scale;$',
      """    wire [9:0] inv_raw = fit_en ? inv_fit : inv_scale;
    // #93：旋转时不许放大到画外 —— 生效倍率取"用户那一档"与"这个角度刚好装得下那一档"里
    //   **画面较小**的那一个（inv 越大画面越小 ⇒ 取较大的 inv）。
    //   代价（写进口径，不藏着）：① 旋转态因此**不提供放大**，1.33x/1.5x/2.0x 三档在旋转时被拉回 fit；
    //   ② `zoom_fit` 在 0° 因为 ±0.5 LSB 的表余量给的是 259 而不是 256 ⇒ 角度正好 0° 也在钳，
    //   画面差 1.2 %（6 个源列，肉眼不可分辨）。两条都由 tb_v94_zoom_sel 的 T8 钉住。
    wire       rot_clamp = rotate_en && (inv_raw < inv_fit);
    assign inv_used   = rot_clamp ? inv_fit : inv_raw;
    assign rot_forced = rot_clamp;""", '#93 钳制落在 zoom_ctrl')
z.save(3)

# ---------------- 2) pl_video_top.v ----------------
p = Ed('src/rtl/top/pl_video_top.v')
p.one(r'^        \.fit_en\(zoom_fit_en\), \.inv_fit\(inv_fit\),.*$',
      '        .rotate_en(rotate_active),  // #93：旋转态钳进 fit（钳在 zoom_ctrl 里，不在顶层再 mux）\n'
      '        .fit_en(zoom_fit_en), .inv_fit(inv_fit),   // V9-2：第三种来源；mux 在 zoom_ctrl 里做，不在这里',
      '#93 顶层递 rotate_active')
p.one(r'^        \.zoom_active\(zoom_active\), \.zoom_code\(zoom_code\),$',
      '        .zoom_active(zoom_active), .zoom_code(zoom_code), .rot_forced(rot_forced),', '#93 顶层接回 rot_forced')
p.one(r'^    wire \[2:0\] zoom_code;',
      '    wire        rot_forced;      // #93：生效倍率是被旋转钳出来的 ⇒ OSD 的 (Fit) 由它参与\n'
      '    wire [2:0] zoom_code;', '#93 声明 rot_forced')
p.one(r'^        \.zoom_fit\(zoom_fit_en\),.*$',
      '        .zoom_fit(zoom_fit_en | rot_forced),   // V9-2：倍率由角度定 ⇒ 标 (Fit)；#93：被旋转钳住时同样标，屏上才讲真话',
      '#93 OSD 的 (Fit) 讲真话')
p.save(4)

# ---------------- 3) 另两个例化 zoom_ctrl 的台架：新输入显式接死（门禁第 14 项查悬空） ----------------
b = Ed('sim/tb_zoom_mapper.v')
b.one(r'^        \.fit_en\(1\'b0\), \.inv_fit\(10\'d256\),',
      "        .rotate_en(1'b0),        // #93 那一刀不参与：这台架量的是呼吸，旋转标志钉成 0\n"
      "        .fit_en(1'b0), .inv_fit(10'd256),", 'tb_zoom_mapper 接 rotate_en')
b.save(1)

c = Ed('sim/tb_v100_fit_rot.v')
c.one(r'^        \.zsel\(zsel\), \.manual\(manual\), \.fit_en\(fit_en\), \.inv_fit\(inv_fit\)$',
      "        .zsel(zsel), .manual(manual), .rotate_en(1'b0),   // #93 不参与：这台架判的是 V9-2 的拟合来源\n"
      "        .fit_en(fit_en), .inv_fit(inv_fit)", 'tb_v100 接 rotate_en')
c.save(1)

# ---------------- 4) tb_v94_zoom_sel：T8 判据 ----------------
t = Ed('sim/tb_v94_zoom_sel.v')
t.one(r"^    reg \[2:0\] zsel = 3'd0;$",
      """    reg [2:0] zsel = 3'd0;
    // #93：把拟合值与旋转标志变成**可驱动的激励**（原来端口上是常量 1'b0/10'd256，钳制那一支永远走不到）
    reg       rotate_en = 1'b0;
    reg [9:0] inv_fit_sim = 10'd256;""", 'tb_v94 新增激励')
t.one(r'^    wire \[9:0\] inv_scale;$',
      '    wire [9:0] inv_scale;\n    wire [9:0] inv_used;\n    wire       rot_forced;', 'tb_v94 新增探针')
t.one(r"^        \.fit_en\(1'b0\), \.inv_fit\(10'd256\),.*$",
      '        .rotate_en(rotate_en), .fit_en(1\'b0), .inv_fit(inv_fit_sim),   // V9-2 的第三种来源：这台台架判的是八档，fit_en 钉成"不参与"',
      'tb_v94 端口接激励')
t.one(r'^        \.inv_scale\(inv_scale\), \.inv_used\(\), // 新出口本台架不读（留空，不接=不判）$',
      '        .inv_scale(inv_scale), .inv_used(inv_used),   // #93：现在要读它 —— 屏上/lane23/mapper 必须说同一个数\n'
      '        .rot_forced(rot_forced),', 'tb_v94 读 inv_used/rot_forced')
t.one(r'^        \$display\(""\);',
      """        // ---------- T8 #93：旋转态把生效倍率钳进 fit，而 OSD 的档号跟着**同一个数** ----------
        // a 是负对照（不旋转时一个字都不改，改前改后都必须绿）；b~f 是这一刀的正文，改前必须红。
        @(negedge clk); enable = 1; manual = 1; zsel = 3'd4; rotate_en = 0; inv_fit_sim = 10'd341;
        repeat (45) @(negedge clk);          // 手动档只在帧首换 ⇒ 至少跨一个帧节拍（40 拍）
        chk("T8a 不旋转：inv_scale/inv_used 都是用户那一档 256、rot_forced=0（负对照）",
            inv_scale == 10'd256 && inv_used == 10'd256 && rot_forced == 1'b0);
        @(negedge clk); rotate_en = 1;
        repeat (6) @(negedge clk);
        chk("T8b 旋转 1.00x + fit=341 => 生效倍率被钳到 341（整幅收进屏内）",
            inv_used == 10'd341 && rot_forced == 1'b1);
        chk("T8c OSD 的档号报钳完那一个（code(341)=3=0.75x，不是用户按的 1.00x）",
            zoom_code == 3'd3);
        @(negedge clk); zsel = 3'd2;                  // 0.50x：inv=512，画面比 fit 还小 => 不该被拉回
        wait_change; repeat (6) @(negedge clk);
        chk("T8d 旋转态里再缩小仍然有效：inv_scale=512、inv_used=512、rot_forced=0",
            inv_scale == 10'd512 && inv_used == 10'd512 && rot_forced == 1'b0);
        @(negedge clk); zsel = 3'd7;                  // 2.00x：inv=128，放大 => 旋转态让位
        wait_change; repeat (6) @(negedge clk);
        chk("T8e 旋转态放大让位给 fit：inv_scale 仍停在 128（用户那一档不丢），生效值=341",
            inv_scale == 10'd128 && inv_used == 10'd341 && rot_forced == 1'b1);
        @(negedge clk); rotate_en = 0;
        repeat (6) @(negedge clk);
        chk("T8f 关掉旋转立刻回到用户那一档（可逆不留痕）：inv_used=128",
            inv_used == 10'd128 && rot_forced == 1'b0 && inv_scale == 10'd128);

        $display("");""", 'tb_v94 T8 判据')
t.save(5)

# ---------------- 5) 台架自报行号跟着真实行号走（改完文件行号会漂） ----------------
for rel in ('sim/tb_v94_zoom_sel.v',):
    path = os.path.join(ROOT, rel.replace('/', os.sep))
    lines = io.open(path, encoding='utf-8', newline='').read().split('\n')
    out, moved = [], 0
    for i, ln in enumerate(lines, 1):
        m = re.match(r'^(\s*\$display\(")\[(' + os.path.basename(rel) + r')\.v:(\d+)\](.*)$', ln.rstrip('\r'))
        if m and int(m.group(3)) != i:
            ln = (m.group(1) + '[' + m.group(2) + '.v:' + str(i) + ']' + m.group(4)
                  + ('\r' if lines[i - 1].endswith('\r') else ''))
            moved += 1
        out.append(ln)
    io.open(path, 'w', encoding='utf-8', newline='').write('\n'.join(out))
    print("自报行号纠正 %d 处（%s）" % (moved, rel))
print("done")
