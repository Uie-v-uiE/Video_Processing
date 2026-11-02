#!/usr/bin/env python3
# 用途：r94_rotfit.py 的后半（前面三个文件已落盘，这里只补剩下的两个台架）
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：脚本内无显式 exit ⇒ 随最后一条命令（正常跑完为 0）
# build/r94_rotfit_b.py —— r94_rotfit.py 的后半（前面三个文件已落盘，这里只补剩下的两个台架）。
# 单行正则 + 行尾 `\r?$`；每处"恰好一次"，否则 SKIP。
import io, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class Ed:
    def __init__(self, rel):
        self.rel = rel
        self.path = os.path.join(ROOT, rel.replace('/', os.sep))
        self.t = io.open(self.path, encoding='utf-8', newline='').read()
        self.NL = '\r\n' if '\r\n' in self.t else '\n'
        self.n = 0

    def one(self, pat, rep, label, count=1):
        if pat.endswith('$'):
            pat = pat[:-1] + r'\r?$'
        rep = rep.replace('\n', self.NL)
        k = len(re.findall(pat, self.t, re.M))
        if k != count:
            print("SKIP %s（匹配 %d 次，要求 %d）" % (label, k, count))
            return False
        self.t = re.sub(pat, lambda m: rep, self.t, count=count, flags=re.M)
        self.n += 1
        print("OK   %s" % label)
        return True

    def save(self, need):
        assert self.n == need, "%s：改了 %d 处，要求 %d 处" % (self.rel, self.n, need)
        io.open(self.path, 'w', encoding='utf-8', newline='').write(self.t)
        print("WROTE %s（%d 处）" % (self.rel, self.n))


c = Ed('sim/tb_v100_fit_rot.v')
c.one(r'^        \.zsel\(zsel\), \.manual\(manual\), \.fit_en\(fit_en\), \.inv_fit\(inv_fit\),.*$',
      "        .zsel(zsel), .manual(manual), .rotate_en(1'b0),   // #93 不参与：这台架判的是 V9-2 的拟合来源\n"
      "        .fit_en(fit_en), .inv_fit(inv_fit),", 'tb_v100 接 rotate_en')
c.one(r'^        \.zoom_active\(zact\), \.zoom_code\(zcode\), \.dir\(zdir\)$',
      '        .zoom_active(zact), .zoom_code(zcode), .dir(zdir), .rot_forced(),', 'tb_v100 接 rot_forced')
c.save(2)

m = Ed('sim/tb_zoom_mapper.v')
m.one(r'^        \.inv_scale\(inv_scale\), \.inv_used\(\), \.zoom_active\(zoom_active\), \.dir\(dir\)$',
      '        .inv_scale(inv_scale), .inv_used(), .zoom_active(zoom_active), .dir(dir), .rot_forced(),',
      'tb_zoom_mapper 接 rot_forced')
m.save(1)

t = Ed('sim/tb_v94_zoom_sel.v')
t.one(r"^    reg \[2:0\] zsel = 3'd0;$",
      """    reg [2:0] zsel = 3'd0;
    // #93：把拟合值与旋转标志变成**可驱动的激励**（原来端口上是常量 1'b0/10'd256，钳制那一支永远走不到）
    reg       rotate_en = 1'b0;
    reg [9:0] inv_fit_sim = 10'd256;""", 'tb_v94 新增激励')
t.one(r'^    wire \[9:0\] inv_scale;$',
      '    wire [9:0] inv_scale;\n    wire [9:0] inv_used;\n    wire       rot_forced;', 'tb_v94 新增探针')
t.one(r"^        \.fit_en\(1'b0\), \.inv_fit\(10'd256\),.*$",
      '        .rotate_en(rotate_en), .fit_en(1\'b0), .inv_fit(inv_fit_sim),   // V9-2 的第三种来源：这台架判的是八档，fit_en 钉成"不参与"',
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

# 台架自报行号跟着真实行号走（插了 20 多行，尾部那三条 $display 的标号必然漂）
rel = 'sim/tb_v94_zoom_sel.v'
path = os.path.join(ROOT, rel.replace('/', os.sep))
data = io.open(path, encoding='utf-8', newline='').read()
lines = data.split('\n')
out, moved = [], 0
for i, ln in enumerate(lines, 1):
    cr = ln.endswith('\r')
    body = ln[:-1] if cr else ln
    mch = re.match(r'^(\s*\$display\(")\[(tb_v94_zoom_sel\.v):(\d+)\](.*)$', body)
    if mch and int(mch.group(3)) != i:
        body = mch.group(1) + '[' + mch.group(2) + '.v:' + str(i) + ']' + mch.group(4)
        moved += 1
    out.append(body + ('\r' if cr else ''))
io.open(path, 'w', encoding='utf-8', newline='').write('\n'.join(out))
print("自报行号纠正 %d 处" % moved)
print("done")
