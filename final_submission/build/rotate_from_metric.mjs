// 用途：把首页/CSV 里的数字**对回尺子自己念出来的报告值**，逐条限定在那一行
// 输入：命令行参数
// 输出：stdout
// 退出码：1=非 0 分支（该文件 exit 1 那一行）
// build/rotate_from_metric.mjs —— 把首页/CSV 里的数字**对回尺子自己念出来的报告值**，逐条限定在那一行
//
// 为什么写它：采纳那一夜我手工列了 35 条 old→new（`r109_rotate_docs.mjs`）。那是能做的，但每一步都在抄数字，
// 而抄数字正是本仓记过多次的错源（规矩：一句"现在/本轮"的数必须来自原件）。这个工具改成**不抄**：
// 读 `node src/host/metric_recheck.mjs` 自己打的 RED 行（`RED row=README.md:56 名称 首页=0.721 报告=0.605`），
// 拿着"文件:行号 + 首页值 + 报告值"三件事，只在**那一行**里把那个值换掉，然后重跑尺子，直到红 0（最多 4 轮）。
//
// 三条自带的限度（都在 --self 里能红）：
//   1) 只动报告值与首页值都是**纯数字**的行；CSV 行没有行号 ⇒ 按行首的名字定位，定位到多行就拒绝；
//   2) 一行里同一个数字出现多次 ⇒ 拒绝（不知道改哪个，宁可可疑也不猜）；
//   3) 换完还红 ⇒ 停下报告，不循环到把尺子改宽（放宽判据是另一码事，归人）。
//
// 用法：node build/rotate_from_metric.mjs [--self|--check]     默认 --check（只念不改）；--apply 才写盘
//
// ⚠ 实测限度（2026-10-03 02:48 用它自己的差分测试测出来的，别念成"一条命令搞定改口"）：
//   把首页退回采纳前那一版再让它自动改：31 条改对、**52 条拒绝**、四轮没收敛。
//   原因不是它算错，而是它能处理的红行形状只有"那一行里这个数恰好出现一次"这一种——
//   首页大量格是 `0.721 ns` 与 `（占它 8 ns 周期的 9.0 %）` 混在一行、百分数的文档写法（9.0）与
//   尺子念的数（9）不同式、tile/占比成对出现，这些都属"拒绝"而不是"猜"。
//   ⇒ 正确用法：先跑它做**第一遍**（把机械的那 31 条搬掉），剩下的按 `build/r109_rotate_docs.mjs` 那样
//   一条一条列规则改；两遍都要以 `metric_recheck` 红 0 收尾。**回退用 `git status`，不要用 md5**
//   （这个仓库里有 CRLF 归一，checkout 之后字节数会与快照不同，我今晚就被这个假信号绊了一次）。
import { execSync } from 'node:child_process';
import fs from 'node:fs';

const MODE = process.argv.includes('--apply') ? 'apply' : (process.argv.includes('--self') ? 'self' : 'check');

// ---------- 自测：给一条 RED 行 + 一行原文，替换必须正好动那一个数 ----------
function selfTest() {
    let n = 0;
    const yes = (label, cond) => { console.log(`  ${cond ? 'PASS' : 'FAIL'} ${label}`); if (cond) n++; };
    const lineCN = '| 全设计 setup WNS | **0.721 ns**（板上这一版 r109；失败端点 **0 / 51029**） | x |';
    yes('A 首页层：行内唯一 0.721 ⇒ 换成 0.605', applyToLine(lineCN, '0.721', '0.605') === lineCN.replace('0.721', '0.605'));
    const dup = '| 功耗 | 动态 **2.212 W**（合计 2.212 W） |';
    yes('B 同一数字出现两次 ⇒ 拒绝（返回 null）', applyToLine(dup, '2.212', '2.214') === null);
    const csv = '全局 setup WNS,核心,0.721,ns,说明里有 0.721 也不算';
    yes('C CSV 行：值列在第 3 列 ⇒ 只换第 3 列', applyToCsv(csv, '0.721', '0.605') === '全局 setup WNS,核心,0.605,ns,说明里有 0.721 也不算');
    yes('D 行里根本没有那个数 ⇒ 拒绝，不乱换', applyToLine('| x | y |', '0.721', '0.605') === null);
    console.log(`SELF: ${n}/4`);
    process.exit(n === 4 ? 0 : 1);
}

// 行内替换：目标值必须在该行**恰好出现一次**，否则 null（拒绝猜测）
function applyToLine(text, from, to) {
    const c = text.split(from).length - 1;
    if (c !== 1) return null;
    return text.replace(from, to);
}
// CSV 行：只认第 3 列（值列）里的这个数，别的列里出现同值不算
function applyToCsv(text, from, to) {
    const f = text.split(',');
    if (f.length < 3 || f[2].trim() !== from) return null;
    f[2] = to;
    return f.join(',');
}

if (MODE === 'self') selfTest();

// ---------- 正式：读尺子的红单，按文件分组应用 ----------
const RED = /^RED\s+row=(\S+)\s+(.*?)\s+首页=([0-9][0-9.]*)\s+报告=([0-9][0-9.]*)/;
const REDCSV = /^RED\s+row=(\S+?)\s+csv=([0-9][0-9.]*)/;

function runMetric() {
    let out = '';
    try { out = execSync('node src/host/metric_recheck.mjs', { encoding: 'utf8', maxBuffer: 1 << 26 }); }
    catch (e) { out = (e.stdout || '') + (e.stderr || ''); }
    return out.split(/\r?\n/);
}

let rounds = 0, refused = 0, applied = 0;
for (rounds = 1; rounds <= 4; rounds++) {
    const lines = runMetric();
    const reds = lines.filter(l => l.startsWith('RED'));
    const summary = lines.find(l => l.startsWith('== 数字对账')) || '';
    console.log(`ROUND ${rounds} 尺子红 ${reds.length} 条  ${summary.slice(0, 80)}`);
    if (reds.length === 0) { console.log('CLEAN 数字全部对回报告值（本工具不改判据，只把文档搬到尺子念的那一侧）'); break; }
    const docs = {};
    for (const rl of reds) {
        let m = rl.match(RED);
        if (m) {
            const [, loc, , home, rep] = m;
            const mm = loc.match(/^(.+?):(\d+)$/);
            if (!mm) { console.log(`REFUSE 红行没有 文件:行号：${rl.slice(0, 70)}`); refused++; continue; }
            const file = mm[1], ln = Number(mm[2]);
            docs[file] = docs[file] ?? fs.readFileSync(file, 'utf8').split(/\r?\n/);
            const before = docs[file][ln - 1];
            const after = applyToLine(before, home, rep);
            if (after === null) { console.log(`REFUSE ${file}:${ln} 里 ${home} 不是恰好一次（或写法不同）`); refused++; continue; }
            docs[file][ln - 1] = after; applied++;
            console.log(`  ${file}:${ln}  ${home} -> ${rep}`);
            continue;
        }
        m = rl.match(REDCSV);
        if (m) {
            const [, name, home] = m;
            const rep = (rl.match(/report=([0-9][0-9.]*)/) || [])[1];
            if (!rep) { console.log(`REFUSE csv 红行读不到报告值：${rl.slice(0, 70)}`); refused++; continue; }
            const csv = fs.readFileSync('data/metrics.csv', 'utf8').split(/\r?\n/);
            const hits = csv.map((l, i) => l.startsWith(name + ',') ? i : -1).filter(i => i >= 0);
            if (hits.length !== 1) { console.log(`REFUSE csv 行首 "${name}" 命中 ${hits.length} 行`); refused++; continue; }
            const after = applyToCsv(csv[hits[0]], home, rep);
            if (after === null) { console.log(`REFUSE csv 第 ${hits[0] + 1} 行的值列不是 ${home}`); refused++; continue; }
            csv[hits[0]] = after; docs['data/metrics.csv'] = csv; applied++;
            console.log(`  data/metrics.csv:${hits[0] + 1}  ${home} -> ${rep}`);
            continue;
        }
        console.log(`SKIP 认不出的红行形状：${rl.slice(0, 90)}`); refused++;
    }
    if (applied === 0) { console.log(`STUCK 这一轮 0 条可改、${refused} 条被拒 ⇒ 回去读尺子的报错形状，别改判据`); process.exit(1); }
    if (MODE === 'apply') { for (const f of Object.keys(docs)) { fs.writeFileSync(f, docs[f].join('\n')); console.log(`WROTE ${f}`); } }
    else { console.log(`CHECK 本轮本可改 ${applied} 条（未写盘）`); break; }
}
if (rounds > 4) console.log('LOOP-END 四轮没收敛 ⇒ 停手，红单里可能有真不一致');
console.log(`== 改动 ${applied} 条、拒绝 ${refused} 条、模式 ${MODE} ==`);
process.exit(refused > 0 ? 1 : 0);
