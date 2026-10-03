// build/r113_rotate_docs.mjs —— r112 采纳那一笔的数字与归属改口（手写规则；机械那半仍由
// build/rotate_from_metric.mjs 先跑，这里补它形状认不出的、以及必须**连句子主语一起改**的）。
// 规矩：每条规则必须**恰好命中期望次数**，否则整条不改并 REFUSE（命中 0 = 那句话已经不在了；
// 命中 2 = 我改的是别处）。任一被拒 ⇒ 整批不落盘（半套改口比不改更坏，r110 撞过）。
// 规矩 46：归属句要整句重写，不许只换数字——r112 的 setup/hold 两条主语都换了族。
// 用法：node build/r113_rotate_docs.mjs --check | --apply
// r113 的身份换法：这一轮相对 r112 只改了 FF 的 INIT 属性 —— 实测两份报告的差别只有 Date 行
//   （`build/evidence/r113_vs_r112_timing_diff.txt` 98 字节 / `..._util_diff.txt` 96 字节），
//   名册八个 (域,类型) 逐位相同（`build/evidence/r113_roster_diff.txt`）⇒ 除 bit md5 与刷板时刻以外，
//   时序/资源那些句子**沿用 r112 那批数字**（它们本来就等于 r113 的实测值）。
import { readFileSync, writeFileSync } from 'node:fs';

const APPLY = process.argv.includes('--apply');
// 每条：[文件, 名字, 正则源, 替换, 期望命中数]
const RULES = [
  // ---------- README.md ----------
  ['README.md', '身份句（板=哪一版/bit）',
    '板上这一版 r110，2026-10-03 07:51 三步 JTAG 刷入，`bit 2bf95588978f`',
    '板上这一版 r113（bit `b94f4da6cdff`，刷板时刻待回填）', 1],
  ['README.md', '全设计 setup WNS',
    '\\| 全设计 setup WNS \\| \\*\\*0\\.713 ns\\*\\*', '\\| 全设计 setup WNS \\| **0.445 ns**', 1],
  ['README.md', '端点总数（WNS 行）', '失败 setup/hold 端点 \\*\\*0 / 51013\\*\\*',
    '失败 setup/hold 端点 **0 / 51135**', 1],
  ['README.md', '逐时钟 eth_rxc 数与百分数',
    '`eth_rxc` \\*\\*0\\.713 ns\\*\\*（占它 8 ns 周期的 8\\.912 %，\\*\\*绝对 WNS 全设计最差就是它\\*\\*）',
    '`eth_rxc` **0.445 ns**（占它 8 ns 周期的 5.5625 %，**绝对 WNS 与按周期归一后的最紧余量都是它**）', 1],
  ['README.md', '逐时钟 clk_fpga_0', '\\*\\*1\\.186 ns\\*\\*（11\\.86 %）', '**1.135 ns**（11.35 %）', 1],
  ['README.md', '逐时钟 clkout0_1', '\\*\\*3\\.799 ns\\*\\*（18\\.995 %）', '**4.467 ns**（22.335 %）', 1],
  ['README.md', '逐时钟 sys_clk', '`sys_clk` \\*\\*15\\.157 ns\\*\\*', '`sys_clk` **14.463 ns**', 1],
  ['README.md', '那句"相对最紧是 clkout0_1"（算错，本轮更正）',
    '\\*\\*绝对 WNS 看 `eth_rxc`，相对余量最紧的是 `clkout0_1`（18\\.995 %，r110 把行覆盖使能独热化之后）\\*\\*',
    '**两个口径这一轮合成一个：绝对 WNS 与按各自周期归一后的最紧余量都是 `eth_rxc`（0.445 / 8 ns = 5.5625 %）**；'
    + 'r110 那行写"相对最紧是 `clkout0_1`（18.995 %）"当时就算错了（0.713 / 8 = 8.912 % 比它紧），本轮一并更正', 1],
  ['README.md', 'setup 归属句整句重写（规矩 46）',
    '全设计最差换成了 `u_rgmii_rx/u_iddr_rx_ctl → u_icmp_rx/des_mac_reg\\[\\*\\]/CE` 那条 4 级路——'
    + '它 logic 只占 15\\.7 %、route 占 84\\.3 %',
    'r112 之后全设计最差是 `u_rx_par/p_eof_reg/C → u_reasm/rows_hit_reg[12..15]/CE` 那条 4 级路——'
    + 'logic 15.724 % vs route 84.276 %。三滚判读（`build/evidence/r113_roll_ABC_verdict.txt`）：'
    + '同一份 opt.dcp 重跑 place+route **逐位复现 0.445**，换 `place_design -directive` 一格不差，'
    + '那块把 rx_par+reasm 收进一个矩形的 Pblock 因进位链半内半外没做成实验', 1],
  ['README.md', '资源行四数',
    '\\*\\*95\\.5 tile（68\\.21 %）/ 14119（26\\.54 %）/ 8154（7\\.66 %）/ 19（8\\.64 %）\\*\\*',
    '**95.5 tile（68.21 %）/ 14154（26.61 %）/ 8188（7.70 %）/ 19（8.64 %）**', 1],
  ['README.md', '资源行代价括弧整段重写',
    '（r110 这一刀的代价与收益：[\\s\\S]*?不写成收益）',
    '（r112 这一刀的代价：按键上电武装门 **+66 LUT / +46 FF**（两只 key_debounce，综合把它们展平进 `u_pl` 的桶，'
    + '逐层表里没有 u_k1/u_k2 行），ICMP 校验和累加器 32→20 位 **−31 LUT / −12 FF**，'
    + '全设计净 **+35 LUT / +34 FF**——净账由两份逐层件相减**闭合到个位**（`build/evidence/r112_util_attrib.txt`）。'
    + '⚠ 刀 B 记为"同族抓手成立、设计余量未抬"：它那条 `ip_head → check_buffer` 真的从最差报告里消失了，'
    + '但设计的绑定约束换成了上面那条 `rows_hit` 的 CE 广播，见 ISSUES #253/#254/#255）', 1],
  // ---------- README.en.md ----------
  ['README.en.md', 'identity sentence',
    'the board now runs r110, flashed at 07:51 on 2026-10-03 by the three-step JTAG chain, `bit 2bf95588978f`',
    'the board now runs r113 (bit `b94f4da6cdff`, flash time to be filled)', 1],
  ['README.en.md', 'design-wide setup WNS',
    '\\| Design-wide setup WNS \\| \\*\\*0\\.713 ns\\*\\*', '\\| Design-wide setup WNS \\| **0.445 ns**', 1],
  ['README.en.md', 'endpoint count (WNS row)', 'failing setup/hold endpoints \\*\\*0 / 51013\\*\\*',
    'failing setup/hold endpoints **0 / 51135**', 1],
  ['README.en.md', 'per-clock eth_rxc',
    '`eth_rxc` \\*\\*0\\.713 ns\\*\\* \\(8\\.912 % of its 8 ns period, and the design-worst absolute path\\)',
    '`eth_rxc` **0.445 ns** (5.5625 % of its 8 ns period - both the design-worst absolute path and the '
    + 'tightest period-normalised margin)', 1],
  ['README.en.md', 'per-clock clk_fpga_0', '\\*\\*1\\.186 ns\\*\\* \\(11\\.86 %\\)', '**1.135 ns** (11.35 %)', 1],
  ['README.en.md', 'per-clock clkout0_1', '\\*\\*3\\.799 ns\\*\\* \\(18\\.995 %\\)', '**4.467 ns** (22.335 %)', 1],
  ['README.en.md', 'per-clock sys_clk', '`sys_clk` \\*\\*15\\.157 ns\\*\\*', '`sys_clk` **14.463 ns**', 1],
  ['README.en.md', 'the wrong "tightest relative is clkout0_1" claim',
    'the tightest relative margin is `clkout0_1` at 18\\.995 % after r110 one-hot-ised the row-set enable',
    'from r112 the two readings coincide: `eth_rxc` is both the design-worst absolute path and the tightest '
    + 'relative margin at 5.5625 %; the r110 sentence that called `clkout0_1` tightest was an arithmetic mistake '
    + '(0.713/8 = 8.912 % is tighter) and is corrected here', 1],
  ['README.en.md', 'setup ownership sentence (rule 46)',
    'the design-worst is now `u_rgmii_rx/u_iddr_rx_ctl -> u_icmp_rx/des_mac_reg\\[\\*\\]/CE`: 4 levels, '
    + 'logic only 15\\.7 % vs route 84\\.3 %',
    'from r112 the design-worst is `u_rx_par/p_eof_reg/C -> u_reasm/rows_hit_reg[12..15]/CE`: 4 levels, '
    + 'logic 15.724 % vs route 84.276 %. Three rolls (`build/evidence/r113_roll_ABC_verdict.txt`): re-running '
    + 'place+route from the same opt.dcp reproduces 0.445 digit for digit, a different `place_design -directive` '
    + 'changes nothing, and the Pblock that would pull rx_par and reasm into one rectangle could not be made a '
    + 'single-variable experiment (carry chains straddled its border)', 1],
  ['README.en.md', 'resource row four numbers',
    '\\*\\*95\\.5 tiles \\(68\\.21 %\\) / 14119 \\(26\\.54 %\\) / 8154 \\(7\\.66 %\\) / 19 \\(8\\.64 %\\)\\*\\*',
    '**95.5 tiles (68.21 %) / 14154 (26.61 %) / 8188 (7.70 %) / 19 (8.64 %)**', 1],
  ['README.en.md', 'resource-row cost parenthetical',
    '\\(the price of the r109 cut:[^)]*\\)',
    '(the price of the r112 cut: the power-on arming gate on the two key-debounce instances costs '
    + '+66 LUT / +46 FF, the ICMP checksum accumulator 32->20 gives back -31 LUT / -12 FF, so the design net is '
    + '+35 LUT / +34 FF - closed to the unit by differencing two hierarchical reports '
    + '(`build/evidence/r112_util_attrib.txt`))', 1],
  // ---------- data/metrics.csv ----------
  ['data/metrics.csv', '全局 setup WNS 数', ',0\\.713,ns,', ',0.445,ns,', 1],
  ['data/metrics.csv', 'WNS 行的轮次与端点数',
    '本轮（r110）实现完成后 Vivado 报的 Design Timing Summary 第一列；端点总数 51013',
    '本轮（r112）实现完成后 Vivado 报的 Design Timing Summary 第一列；端点总数 51135', 1],
  ['data/metrics.csv', 'WNS 行的逐时钟括弧',
    '（逐时钟表：收包 0\\.723 = 它 8 ns 周期的 9\\.0 %／100 MHz `clk_fpga_0` 1\\.387 = 13\\.9 %／'
    + '50 MHz 显示域 `clkout0_1` 1\\.264 = 6\\.3 %／`sys_clk` 13\\.196）',
    '（逐时钟表：收包 0.445 = 它 8 ns 周期的 5.5625 %／100 MHz `clk_fpga_0` 1.135 = 11.35 %／'
    + '50 MHz 显示域 `clkout0_1` 4.467 = 22.335 %／`sys_clk` 14.463）', 1],
  ['data/metrics.csv', 'WNS 行那句"归一后最紧"',
    '\\*\\*按各自周期归一后最紧的是显示域 6\\.3 %\\*\\*（那条是 23 级 OSD 读侧锥，见 report/KNOWN_ISSUES\\.md）',
    '**按各自周期归一后最紧的就是收包域（5.5625 %）**；显示域这一轮宽到 22.335 %'
    + '（r109 那把 OSD 读侧寄存一拍的效果留在它身上）', 1],
  ['data/metrics.csv', '失败端点行的端点数', '（0 / 51013）', '（0 / 51135）', 1],
  ['data/metrics.csv', '全局 hold WHS 数', ',0\\.042,ns,', ',0.050,ns,', 1],
  ['data/metrics.csv', 'WHS 行的端点数', '失败端点 0 / 51013；脉冲宽度 WPWS 0\\.264',
    '失败端点 0 / 51135；脉冲宽度 WPWS 0.264', 1],
  ['data/metrics.csv', 'WHS 行的逐时钟括弧',
    '（逐时钟 hold：`eth_rxc` 0\\.051／显示域 `clkout0_1` 0\\.052／`clk_fpga_0` 0\\.053／`sys_clk` 0\\.121）',
    '（逐时钟 hold：`eth_rxc` 0.050／显示域 `clkout0_1` 0.059／`clk_fpga_0` 0.056／`sys_clk` 0.133）', 1],
  ['data/metrics.csv', 'WHS 行的落点整句（规矩 46）',
    '落点 `u_eth/u_ctrl/arp_rx_flag_reg → arp_pend_reg`，只有 \\*\\*1 级逻辑（LUT4）\\*\\*、'
    + '走线占这条数据路径延迟的 \\*\\*80\\.9 %\\*\\*',
    '落点 `u_eth/u_cdc/rgray_s1_reg[1]/C → u_eth/u_lm/full_d_reg/D`，**3 级逻辑（CARRY4=2、LUT6=1）**、'
    + '走线占这条数据路径延迟的 **56.165 %**（这一格又回到灰码→链路监测那一路：r107 是它、0.050，'
    + 'r108/r110 在 crc_data，r112 仍是 0.050）', 1],
  ['data/metrics.csv', 'LUT 数与百分数', ',14119（26\\.54 %）,', ',14154（26.61 %）,', 1],
  ['data/metrics.csv', 'LUT 行的本轮账',
    '实现后报告（本轮 r110 比 r109 少 243 个（其中 −66 能归到行覆盖那一刀，其余没有归属，不念成收益）；',
    '实现后报告（本轮 r112 比 r110 多 35 个：武装门 +66（两只 key_debounce）与校验和累加器 32→20 的 −31 相减得来，'
    + '净账由两份逐层件相减闭合（build/evidence/r112_util_attrib.txt）；再往前 r110 比 r109 少 243 个'
    + '（其中 −66 能归到行覆盖那一刀，其余没有归属，不念成收益）；', 1],
  ['data/metrics.csv', 'FF 数与百分数', ',8154（7\\.66 %）,', ',8188（7.70 %）,', 1],
  ['data/metrics.csv', 'FF 行的本轮账', '实现后报告（本轮 r110 比 r109 少 8 个；',
    '实现后报告（本轮 r112 比 r110 多 34 个（+46 来自两只 key_debounce 的武装门、−12 来自累加器位宽，'
    + '−12 与 32→20 逐位对得上）；再往前 r110 比 r109 少 8 个；', 1],
];

let bad = 0, hit = 0;
const cache = {};
for (const [f, name, src, rep, want] of RULES) {
    if (!(f in cache)) cache[f] = readFileSync(f, 'utf8');
    const re = new RegExp(src, 'g');
    const n = (cache[f].match(re) || []).length;
    if (n !== want) { console.log(`REFUSE ${name}：${f} 命中 ${n} 次（期望 ${want}）`); bad++; continue; }
    if (APPLY) cache[f] = cache[f].replace(re, rep);
    hit++;
    console.log(`OK   ${name}  ×${n}`);
}
if (APPLY && bad === 0) for (const f of Object.keys(cache)) { writeFileSync(f, cache[f]); console.log(`WROTE ${f}`); }
else if (APPLY) console.log('NO-WRITE 有规则被拒，整批不落盘（半套改口比不改更坏）');
console.log(APPLY ? `== 模式 apply：可改 ${hit} 条 / 拒 ${bad} 条 ==`
                  : `== 模式 check：可改 ${hit} 条 / 拒 ${bad} 条（没写盘）==`);
process.exit(bad ? 1 : 0);
