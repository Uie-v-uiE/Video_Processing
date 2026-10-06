// 修一处交付文档里的事实错：§2.1 时钟表的"用途"两行写反了。
// 盘上证据：build/report/clock_util.rpt 里 clk_fpga_0 的驱动脚是 PS7 的 FCLK_CLK0（10.000 ns），
//   clkout0_1 的驱动脚是 u_pl/u_clk/u_bufg_pix/O、net 是 u_pl/u_clk/clk_pix（20.000 ns）；
//   src/rtl/top/system_top.v 把 .axi_clk 接到 fclk0，src/rtl/top/pl_video_top.v 里
//   fb_bilin 的 .clk(clk_pix) 是显示读出、.wr_clk(axi_clk) 是写侧。
//   ⇒ 100 MHz 那档是 AXI/写侧，50 MHz 的 clk_pix 才是读出/几何/效果链/OSD。
// 用法：node build/fix_clock_roles.mjs --check | --apply
import fs from 'node:fs';
import path from 'node:path';

const APPLY = process.argv.includes('--apply');
const TREES = [
  'D:/Xilinx/Prj/pro/Video_Processing',
  'D:/Xilinx/Prj/pro/delivery_review_20261005',
  'D:/Xilinx/Prj/Video_Processing',
];
const SKIP = /(^|[\\/])(\.git|final_submission|node_modules)([\\/]|$)/;

// 只带"周期 + 用途"这段，足够定位且各表形状一致（交付表带 ns，时序卷的表不带）
const PAIRS = [
  ['10.000 ns | 显示读出、几何、效果链、OSD', '10.000 ns | AXI 全互连与帧缓存写侧（PS FCLK0）'],
  ['20.000 ns | 帧缓存写侧与 AXI 全互连', '20.000 ns | 显示读出、几何、效果链、OSD（`clk_pix`）'],
  ['10.000 | 显示读出、几何、效果链、OSD', '10.000 | AXI 全互连与帧缓存写侧（PS FCLK0）'],
  ['20.000 | 帧缓存写侧与 AXI 全互连', '20.000 | 显示读出、几何、效果链、OSD（`clk_pix`）'],
  ['20.000 ns | PS/AXI 侧、按键、慢速控制', '20.000 ns | 板载晶振输入、按键、慢速控制'],
  ['20.000 | PS/AXI 侧、按键、慢速控制', '20.000 | 板载晶振输入、按键、慢速控制'],
  // §6.1 第一行把两支 MMCM 都算到 PS 头上：clkout0_1/clkout1_1 其实是 PL 侧那只 MMCME2_BASE 的输出
  ['- 时钟全部由 PS 侧 MMCM 与 BUFG 树产生，`clk_fpga_0` 100 MHz、`clkout1_1` 250 MHz 同源；',
   '- 时钟树分两支：`clk_fpga_0` 100 MHz 由 PS7 的 FCLK_CLK0 给（`build/report/clock_util.rpt` 的 g0 行，驱动脚是 `…/FCLK_CLK_0_BUFG/O`）；' +
   '显示与算法那几支由 PL 侧一只 `MMCME2_BASE` 产生（`src/rtl/clocks/clk_gen.v:15`，喂进来的是 `sys_clk` 50 MHz，见 `src/rtl/top/pl_video_top.v:128`），' +
   '`clkout0_1` = `clk_pix` 50 MHz、`clkout1_1` = `clk_pix5x` 250 MHz 都出自这只 MMCM；'],
];

function walk(d, out) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (SKIP.test(p)) continue;
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.md')) out.push(p);
  }
  return out;
}

let files = 0, rules = 0, already = 0, hits = 0;
for (const tree of TREES) {
  if (!fs.existsSync(tree)) { console.log(`跳过（不在）：${tree}`); continue; }
  const md = walk(tree, []);
  const staged = new Map();
  for (const p of md) {
    let t = fs.readFileSync(p, 'utf8');
    const before = t;
    let n = 0;
    for (const [oldS, newS] of PAIRS) {
      const cNew = t.split(newS).length - 1;
      // 幂等三态：旧串在"挖掉新串之后"仍命中 ⇒ 该改口（首次）；不命中且新串在位 ⇒ 已改口；两边都 0 ⇒ 本文件没这一行
      const outside = t.split(newS).join('').split(oldS).length - 1;
      if (outside > 0) { t = t.split(oldS).join(newS); n += outside; rules++; }
      else if (outside === 0 && cNew >= 1) already += cNew;
    }
    if (n) { hits += n; staged.set(p, t); files++; }
    else { for (const [, newS] of PAIRS) { const c = before.split(newS).length - 1; if (c) already += c; } }
  }
  for (const [p, t] of staged) {
    const now = fs.readFileSync(p, 'utf8');
    if (t.split('\n').length !== now.split('\n').length) { console.log(`REFUSE 行数会变：${p}`); process.exit(1); }
    if (APPLY) fs.writeFileSync(p, t, 'utf8');
    console.log(`${APPLY ? '已改' : '待改'} ${p}`);
  }
}
console.log(`时钟表用途修正  树=${TREES.length}  命中文件=${files}  替换=${hits}  规则=${rules}  已在位=${already}  ${APPLY ? '已写盘' : '（--check 未写盘）'}`);
