#!/usr/bin/env node
// 用途：r108 那一刀的补丁：把 icmp_tx 的 IP 头校验和从"一拍 10 项加"摊成"两拍各 5 项"
// 输入：命令行参数、src/rtl/eth/icmp_tx.v
// 输出：stdout
// 退出码：0=跑完 1=非 0 分支（该文件 exit 1 那一行）
// build/r108_apply_csum.mjs —— r108 那一刀的补丁：把 icmp_tx 的 IP 头校验和从"一拍 10 项加"摊成"两拍各 5 项"。
//
// 依据（r106 布线后的报告，build/setup_paths.rpt / build/crit_paths.txt）：
//   0.741ns | eth_rxc | 7.187ns | 10 级（CARRY4=5 LUT2=1 LUT3=2 LUT5=1 LUT6=1）| 逻辑 2.943ns = 40.95 %
//   起点 u_eth/u_icmp/u_icmp_tx/ip_head_reg[2][31]/C、终点 check_buffer_reg[17]/D
//   ⇒ 就是 icmp_tx.v 里 st_check_sum 那**一条** 10 项加法摆出来的 5 级进位链（这条锥是逻辑限制的，
//   不是 r107 那条走线限制的——所以两刀手法不同，也分两轮做，#172 的单变量纪律）。
// 手法（路线图 §7.2：多操作数的大锥摊到相邻拍，别在一拍里全算完）：
//   cnt==0 前 5 项、cnt==1 后 5 项、cnt==2/3 两次"高低 16 位折叠"、cnt==4 取反写回。
//   算术上等价的理由（但**不拿它当凭据**）：10 个 16 位项之和 ≤ 655350，20 位放得下，赋值目标是
//   32 位寄存器 ⇒ 中间不截断；折叠次序一字不改。代价：这个状态多占一拍。
// 凭据必须是台架：等价性与"判据能动"的变异对照写在 build/evidence/r108_csum_split_equiv.txt
//   （tb_diff_icmp：同一激励喂两枚 DUT，比发出字节序列的计数与滚动哈希 + 每场真的发过字节）。
// 用法：node build/r108_apply_csum.mjs [--check] [目标文件]
//   默认目标 src/rtl/eth/icmp_tx.v；--check 只验锚点、不落盘。回退 = git checkout 这一个文件。
import fs from 'node:fs';

const argv = process.argv.slice(2);
const check = argv.includes('--check');
const P = argv.find((a) => !a.startsWith('--')) || 'src/rtl/eth/icmp_tx.v';
const src = fs.readFileSync(P, 'utf8');
const L = src.split('\n');

function oneLine(re, what) {
    const hits = [];
    for (let i = 0; i < L.length; i++) if (re.test(L[i])) hits.push(i);
    if (hits.length !== 1) {
        console.log(`REFUSE: 「${what}」命中 ${hits.length} 行（要正好 1 行）`);
        process.exit(1);
    }
    return hits[0];
}
if (L.some((s) => /cnt == 5'd4/.test(s))) { console.log("REFUSE: 已有 cnt == 5'd4，这一版补丁打过了"); process.exit(1); }

// 区间左端：那条 10 项加法的首行（本文件里唯一），它上面一行必须正是 if (cnt == 5'd0) begin
const ea = oneLine(/check_buffer <= ip_head\[0\]\[31:16\]/, 'IP 校验和那条 10 项加法的首行');
const a = ea - 1;
if (!/^\s*if \(cnt == 5'd0\) begin\s*$/.test(L[a])) {
    console.log('REFUSE: 10 项加法上面不是 if (cnt == 5\'d0) begin，实为 ' + JSON.stringify(L[a]));
    process.exit(1);
}
// 区间右端：取反写回那一行（ip_head[2][15:0] 是 IP 头校验和独有的），它上面第三行必须是 cnt==5'd3 那档
const ib = oneLine(/ip_head\[2\]\[15:0\] <= ~check_buffer\[15:0\];/, '取反写回那一行');
const b = ib - 3;
if (!/cnt == 5'd3/.test(L[b]) || !/按位取反/.test(L[b])) {
    console.log('REFUSE: 取反档的位置推算不是那三行，实为 ' + JSON.stringify(L[b]));
    process.exit(1);
}

// 区间内容复核：少任何一条就说明锚点圈错了（折叠段必须恰好两处，两拍摊分前只有 10 项加法那一处）
const seg = L.slice(a, b + 1).join('\n');
const folds = (seg.match(/check_buffer\[31:16\] \+ check_buffer\[15:0\];/g) || []).length;
if (folds !== 2) { console.log(`REFUSE: 区间内折叠段应有 2 处，实得 ${folds}`); process.exit(1); }
for (const [re, what] of [[/ip_head\[4\]\[15:0\];/, '10 项加法的收尾'], [/cnt == 5'd1/, '第一档折叠'],
    [/cnt == 5'd2/, '第二档折叠'], [/cnt == 5'd3/, '取反档']]) {
    if (!re.test(seg)) { console.log(`REFUSE: 区间里缺「${what}」`); process.exit(1); }
}

const IND = L[a].match(/^\s*/)[0];
const NEW = [
    IND + '// r108（路线图 §7.2）：原来这一拍要加 10 个 16 位项，综合摆出 5 级 CARRY4——r106 报告里',
    IND + '// 那条 10 级 / 0.741 ns 的路就是这个锥。摊成两拍各 5 项：和不截断（10 项 ≤ 655350，20 位',
    IND + '// 够，目标寄存器 32 位），折叠次序一字不改，代价是这个状态多占一拍。',
    IND + "if (cnt == 5'd0) begin",
    IND + '    check_buffer <= ip_head[0][31:16] + ip_head[0][15:0] + ip_head[1][31:16] +',
    IND + '        ip_head[1][15:0] + ip_head[2][31:16];',
    IND + "end else if (cnt == 5'd1) begin",
    IND + '    check_buffer <= check_buffer + ip_head[2][15:0] + ip_head[3][31:16] +',
    IND + '        ip_head[3][15:0] + ip_head[4][31:16] + ip_head[4][15:0];',
    IND + "end else if (cnt == 5'd2)  //可能出现进位,累加一次",
    IND + '    check_buffer <= check_buffer[31:16] + check_buffer[15:0];',
    IND + "else if (cnt == 5'd3) begin  //可能再次出现进位,累加一次",
    IND + '    check_buffer <= check_buffer[31:16] + check_buffer[15:0];',
    IND + "end else if (cnt == 5'd4) begin  //按位取反",
];
const out = L.slice(0, a).concat(NEW, L.slice(b + 1));
const t = out.join('\n');
if (t.length <= src.length) { console.log('REFUSE: 打完反而没变长，插入没生效'); process.exit(1); }
const nfolds = (t.match(/check_buffer\[31:16\] \+ check_buffer\[15:0\];/g) || []).length;
if (nfolds !== folds) { console.log(`REFUSE: 折叠段数量从 ${folds} 变成了 ${nfolds}`); process.exit(1); }
if (check) { console.log(`CHECK：锚点全对（区间 ${a + 1}..${b + 1}，折叠段 2 处不变），未写盘`); process.exit(0); }
fs.writeFileSync(P, t);
console.log(`OK  替换区间 ${a + 1}..${b + 1}，${src.length} -> ${t.length} 字节（${P}）`);
