// build/r110_rotate_docs.mjs —— r110 采纳那一笔的"手写规则"数字改口（机械的那 30 条由
// build/rotate_from_metric.mjs 搬过，这里只补它形状认不出、或需要连句子一起改口的）。
// 规矩：每条规则必须**恰好命中一次**，否则整条不改并报错退出（`REFUSE`）——
// 命中 0 次 = 这句话已经不在了；命中 2 次 = 我改的是别处。两种都不能靠"看起来对"放过。
// 用法：node build/r110_rotate_docs.mjs [--check]（默认 --check，加 --apply 才写盘）
import { readFileSync, writeFileSync } from 'node:fs';

const APPLY = process.argv.includes('--apply');
// 每条：[文件, 名字, 正则源, 替换, 期望命中数]
const RULES = [
  ['README.md', '资源行里 rotator 写坏的百分数', '26\\.54\\.00 %', '26.54 %', 1],
  ['README.md', '逐时钟 clkout0_1 余量%', '\\*\\*3\\.799 ns\\*\\*（20\\.47 %）', '**3.799 ns**（18.995 %）', 1],
  ['README.md', 'hold/归属段里那句 20.47 %', '（20\\.47 %，r109 把 OSD 读侧寄存一拍之后）',
     '（18.995 %，r110 把行覆盖使能独热化之后）', 1],
  ['README.md', '身份句（板=哪一版/bit/门禁读数）',
     '板上这一版 r109，2026-10-03 02:10 三步 JTAG 刷入，`bit 21227687e925`',
     '板上这一版 r110（bit `2bf95588978f`，刷板时刻待回填）', 1],
  ['README.md', '资源行的代价句（整段括弧重写）',
     '（[^（）]*这一刀的代价[^（）]*）',
     '（r110 这一刀的代价与收益：行覆盖使能独热化让 `u_reasm` 自己少 66 个 LUT／18 个寄存器'
     + '（OOC 两腿实测，`build/evidence/r110_attrib.txt`），全设计 14362→14119／8162→8154；'
     + '差额里归不到这把刀的那部分不写成收益）', 1],
  ['README.en.md', '资源行里 rotator 写坏的百分数', '26\\.54\\.00 %', '26.54 %', 1],
  ['README.en.md', '逐时钟 clkout0_1 余量%', '20\\.47 %\\)', '18.995 %)', 1],
  ['README.en.md', '归属段里那句 20.47 %', '20\\.47 % after r109 registered the OSD read path',
     '18.995 % after r110 one-hot-ised the row-set enable', 1],
  ['README.en.md', '身份句里的 bit md5', '21227687e925', '2bf95588978f', 1],
  ['data/metrics.csv', '全局 setup WNS', ',0\\.605,ns,', ',0.713,ns,', 1],
  ['data/metrics.csv', 'WNS 行的轮次与端点数', '本轮（r109）实现完成后 Vivado 报的 Design Timing Summary 第一列；端点总数 51029',
     '本轮（r110）实现完成后 Vivado 报的 Design Timing Summary 第一列；端点总数 51013', 1],
  ['data/metrics.csv', '失败端点行的端点数', '（0 / 51029）', '（0 / 51013）', 1],
  ['data/metrics.csv', '全局 hold WHS', ',0\\.049,ns,', ',0.042,ns,', 1],
  ['data/metrics.csv', 'WHS 行的端点数', '失败端点 0 / 51005', '失败端点 0 / 51013', 1],
  ['data/metrics.csv', 'LUT 占用数与百分数', ',14362（27\\.00 %）,', ',14119（26.54 %）,', 1],
  ['data/metrics.csv', 'LUT 行的本轮账', '实现后报告（本轮 r109 与 r106 逐字相同：',
     '实现后报告（本轮 r110 比 r109 少 243 个（其中 −66 能归到行覆盖那一刀，其余没有归属，不念成收益）；上一轮 r109 与 r106 逐字相同：', 1],
  ['data/metrics.csv', 'FF 占用数与百分数', ',8162（7\\.67 %）,', ',8154（7.66 %）,', 1],
  ['data/metrics.csv', 'FF 行的本轮账', '实现后报告（本轮 r109 比 r108 少 6 个（OSD 读侧寄存一拍换来的）',
     '实现后报告（本轮 r110 比 r109 少 8 个；再往前 r109 比 r108 少 6 个（OSD 读侧寄存一拍换来的）', 1],
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
console.log(APPLY ? `== 模式 apply：可改 ${hit} 条 / 拒 ${bad} 条 ==` : `== 模式 check：可改 ${hit} 条 / 拒 ${bad} 条（没写盘）==`);
process.exit(bad ? 1 : 0);
