// metric_recheck.mjs —— 把 `data/metrics.csv` 里每个数对回它**自己点名的那份报告**（ISSUES #120 的 D6）。
//
//   node src/host/metric_recheck.mjs          # 判红就退出码非 0
//   node src/host/metric_recheck.mjs --self    # 自检：塞一条故意写错的行必须变红
//
// 为什么要有它（不是"再多一把尺子"，是这一族错误第三次发生）：
//   #145 —— 表里写"128 条逐像素判定"，留档那份报告数出来是 138；
//   #138/#145 —— 凭据换过一轮，表里的数还是上一轮的；
//   今天 —— "50 MHz 显示域 +1.177 ns（12 %）"：1.177 是对的，12 % 是把它按 10 ns 周期除了
//   （报告里 `clkout0_1` 的 Requirement 明写 20.000ns），真正是 5.9 %。
//   三次的共同点：**数是从报告里抄出来的，抄完报告又变了 / 除错了分母**。
//   人去复核一个百分数不会发现"除错周期"，脚本会 —— 因为它把分母也一起从同一份报告读。
//
// 只判"点名了这三份报告"的行：timing_summary / utilization / power。
// 认不出的行**算作未判并打印条数**，不静默放过，也不冒充判据（一条判据不许靠"没人反对"变绿）。
import fs from 'node:fs';

const ROOT = process.cwd();
const CSV = 'data/metrics.csv';

function readRows(txt) {                     // 只处理我认识的行名，所以拆字段用引号敏感的浅解析
    const rows = [];
    for (const line of txt.split(/\r?\n/)) {
        if (!line.trim()) continue;
        const f = [];
        let cur = '', q = false;
        for (const ch of line) {
            if (ch === '"') { q = !q; continue; }
            if (ch === ',' && !q) { f.push(cur); cur = ''; continue; }
            cur += ch;
        }
        f.push(cur);
        rows.push(f);
    }
    return rows;
}

function num(s) { const m = String(s).match(/-?\d+(?:\.\d+)?/); return m ? Number(m[0]) : null; }

// ---- 报告侧的读数（每个提取器都说清它读的是哪一行，判红时要能指着看）
function fromTiming(p) {
    const t = fs.readFileSync(p, 'utf8');
    const blk = t.split('Design Timing Summary')[1] || '';
    const m = blk.match(/WNS\(ns\)[^\n]*\n[^\n]*\n\s*(-?[0-9.]+)\s+(-?[0-9.]+)\s+(\d+)\s+(\d+)\s+(-?[0-9.]+)/);
    if (!m) throw new Error('timing_summary.rpt 里读不到 Design Timing Summary 那一行');
    // 周期也一起读：百分数的分母必须来自报告，不能由人脑补（今天那个 12 % 就是这么来的）
    const periods = {};
    for (const r of t.matchAll(/\|\s*(\S+)\s+(-?[0-9.]+)\s+0\.000\s+\d+\s+\d+\s+(-?[0-9.]+)/g)) {
        periods[r[1]] = { wns: Number(r[2]), whs: Number(r[3]) };
    }
    return { wns: Number(m[1]), failSetup: Number(m[3]), totalEp: Number(m[4]), whs: Number(m[5]), periods };
}
function fromUtil(p) {
    const t = fs.readFileSync(p, 'utf8');
    const grab = (label) => {
        const m = t.match(new RegExp('^\\|\\s*' + label + '\\s*\\|\\s*([0-9.]+)\\s*\\|[^|]*\\|[^|]*\\|\\s*([0-9]+)\\s*\\|\\s*([0-9.]+)\\s*\\|', 'm'));
        return m ? { use: Number(m[1]), avail: Number(m[2]), pct: Number(m[3]) } : null;
    };
    return {
        lut: grab('Slice LUTs'), reg: grab('Slice Registers'), bram: grab('Block RAM Tile'),
        // 这份报告里 DSP 那行就叫 `| DSPs | 19 | 0 | 0 | 220 | 8.64 |`（不是 DSP48E1/FIFO*，
        // 那是另一份报告里的写法）：分母与百分数都在里面，所以三个数都能判。
        dsp: grab('DSPs'),
    };
}
function fromPower(p) {
    const t = fs.readFileSync(p, 'utf8');
    const dyn = t.match(/^\|\s*Dynamic \(W\)\s*\|\s*([0-9.]+)/m);
    const tj = t.match(/^\|\s*Junction Temperature \(C\)\s*\|\s*([0-9.]+)/m);
    return { dyn: dyn ? Number(dyn[1]) : null, tj: tj ? Number(tj[1]) : null };
}

// ---- 首页那一层的取数器（#213 只判 WNS 一格，本轮 #159 扩到四行；见 run() 里的 FRONT）----
// 与 RULES 共用**同一批报告读数**（fromTiming/fromUtil/fromPower），不另起第二份真值。
function one(cell, re, g = 1) { const m = cell.match(re); return m ? Number(m[g]) : null; }
function file_line(e, hit) { return `${e.file}:${hit + 1}`; }
function grabPairs(cell) {                    // `14333（26.94 %）` 与 `14333 (26.94 %)` 两种括号都认
    const out = [];
    for (const m of cell.matchAll(/(\d+)\s*[（(]\s*([\d.]+)\s*%[）)]/g)) out.push([Number(m[1]), Number(m[2])]);
    return out;
}
// 每个 kind 返回 [判点名, 首页读数, 报告读数]；读数抓不到 = null，**null 一律判红**（不许"抓不到就跳过"）
const KINDS = {
    wns: (c, s) => [
        ['WNS(ns)', one(c, /\*\*([0-9]+\.[0-9]+)\s*ns\*\*/), s.wns],
        ['失败 setup/hold 端点', one(c, /\*\*([0-9]+)\s*\/\s*[0-9]{4,}\*\*/), s.failSetup],
        ['端点总数', one(c, /\*\*[0-9]+\s*\/\s*([0-9]{4,})\*\*/), s.totalEp],
    ],
    util: (c, s) => {
        const rows = [
            ['BRAM tile', one(c, /(\d+)\s*tiles?\s*[（(]/), s.bram ? s.bram.use : null],
            ['BRAM 占比(%)', one(c, /tiles?\s*[（(]\s*([\d.]+)\s*%/, 1), s.bram ? s.bram.pct : null],
        ];
        const p = grabPairs(c);               // 括号对里带 tile 那一对已被上面的式子排除
        const order = [['LUT', 'lut'], ['FF', 'reg'], ['DSP', 'dsp']];
        for (let i = 0; i < order.length; i++) {
            const got = p[i] || [null, null];
            const src = s[order[i][1]];
            rows.push([order[i][0], got[0], src ? src.use : null]);
            rows.push([order[i][0] + ' 占比(%)', got[1], src ? src.pct : null]);
        }
        rows.push(['括号对数(LUT/FF/DSP)', p.length, order.length]);   // 少一对 = 首页那行的形状变了
        return rows;
    },
    power: (c, s) => [
        ['动态功耗(W)', one(c, /\*\*([0-9]+\.[0-9]+)\s*W\*\*/), s.dyn],
        ['估算结温(°C)', one(c, /\*\*([0-9]+\.[0-9]+)\s*(?:°C|degC|℃)\*\*/), s.tj],
    ],
};

const RULES = [
    { name: '全局 setup WNS', src: 'timing', get: r => r.wns, note: 'WNS 第一列' },
    { name: '全局 setup 失败端点', src: 'timing', get: r => r.failSetup, also: { in: '测量条件', re: /\/\s*(\d{4,6})/, get: r => r.totalEp, what: '端点总数' } },
    { name: '全局 hold WHS', src: 'timing', get: r => r.whs, note: 'WHS 第一列' },
    { name: 'Slice LUT 占用', src: 'util', get: r => r.lut.use, also: { in: '数值', re: /(\d+\.\d+)\s*%/, get: r => r.lut.pct, what: '占用百分数' } },
    { name: 'Slice 寄存器占用', src: 'util', get: r => r.reg.use, also: { in: '数值', re: /(\d+\.\d+)\s*%/, get: r => r.reg.pct, what: '占用百分数' } },
    { name: 'Block RAM Tile 占用', src: 'util', get: r => r.bram.use, also: { in: '数值', re: /(\d+\.\d+)\s*%/, get: r => r.bram.pct, what: '瓦片占用百分数' }, also2: { in: '数值', re: /\d+\s*\/\s*(\d+)/, get: r => r.bram.avail, what: '可用瓦片数' } },
    { name: 'DSP48 占用', src: 'util', get: r => r.dsp.use, also: { in: '数值', re: /(\d+\.\d+)\s*%/, get: r => r.dsp.pct, what: 'DSP 占用百分数' } },
    { name: '实现后动态功耗', src: 'power', get: r => r.dyn },
    { name: '结温估算', src: 'power', get: r => r.tj },
];

function run(self) {
    const T = fromTiming('build/timing_summary.rpt');
    const U = fromUtil('build/utilization.rpt');
    const P = fromPower('build/power.rpt');
    const SRC = { timing: T, util: U, power: P };
    let rows = readRows(fs.readFileSync(CSV, 'utf8'));
    rows.shift();                                            // 表头
    if (self) rows.push(['全局 setup WNS', '核心', '+9.999', 'ns', '自检：故意写错的一条', '一次构建', 'build/timing_summary.rpt']);
    const known = new Set(RULES.map(r => r.name));
    let red = 0, judged = 0, other = 0;

    // 首页那四行也一起判（#213 起了这个头，本轮 #159 从"两行一个数"扩到"四行 26 个数"）：
    // README 的表格里写着 WNS、逐资源占用与功耗，并点名 `build/timing_summary.rpt` /
    // `build/utilization.rpt` / `build/power.rpt`，可**没有任何检查器回去读那三份报告**——
    // metrics.csv 有 D6 管，首页没有。于是"首页引用的是哪份报告"与"那份报告现在说什么"之间的
    // 账是空的，跨版一定会烂。⚠ 这条判据的"改前必须红"不用我造：第一次跑就抓到首页功耗行
    // 写 2.212 W / 52.6 °C 而报告是 2.211 / 52.5，占用行写 14333 / 8079 而报告是 14334 / 8127
    //（r103→r104 那一轮只同步了 metrics.csv，首页漏了四格）。
    // 复用同一批报告读数，不另起口径；行找不到、数抓不到、括号对数不对 ⇒ 一律判红（不许空转）。
    const FRONT = [
        { file: 'README.md', key: '全设计 setup WNS', want: 'timing_summary.rpt', src: 'timing', kind: 'wns' },
        { file: 'README.md', key: 'BRAM / LUT / FF / DSP', want: 'utilization.rpt', src: 'util', kind: 'util' },
        { file: 'README.md', key: '功耗', want: 'power.rpt', src: 'power', kind: 'power' },
        { file: 'README.en.md', key: 'Design-wide setup WNS', want: 'timing_summary.rpt', src: 'timing', kind: 'wns' },
        { file: 'README.en.md', key: 'BRAM / LUT / FF / DSP', want: 'utilization.rpt', src: 'util', kind: 'util' },
        { file: 'README.en.md', key: 'Power', want: 'power.rpt', src: 'power', kind: 'power' },
    ];
    let frontRows = 0, frontParsed = 0, frontRed = 0, frontNums = 0, fixtureRed = 0;
    for (const e of FRONT) {
        if (!fs.existsSync(e.file)) { console.log(`RED row=${e.file} 找不到这份首页`); red++; frontRed++; continue; }
        frontRows++;
        const ls = fs.readFileSync(e.file, 'utf8').split(/\r?\n/);
        let hit = -1;
        for (let i = 0; i < ls.length; i++) if (ls[i].startsWith('|') && ls[i].includes(e.key)) { hit = i; break; }
        if (hit < 0) { console.log(`RED row=${e.file} 里找不到「${e.key}」这一行 ⇒ 首页与指标表脱钩`); red++; frontRed++; continue; }
        const cells = ls[hit].split('|').map((s) => s.trim());
        const art = cells[cells.length - 2] || '';
        frontParsed++;
        if (!art.includes(e.want)) {
            console.log(`RED row=${file_line(e, hit)} 「${e.key}」点名的是 ${art}，不是 ${e.want} —— 判据与凭据脱钩`);
            red++; frontRed++; judged++; continue;
        }
        for (const [what, got, exp] of KINDS[e.kind](cells[2], SRC[e.src])) {
            frontNums++;
            const ok = got !== null && got !== undefined && exp !== null && exp !== undefined
                && Math.abs(got - exp) < 1e-6;
            console.log(`${ok ? 'OK ' : 'RED'} row=${file_line(e, hit)} ${e.key}/${what} 首页=${got} 报告=${exp}`);
            if (!ok) { red++; frontRed++; }
            judged++;
        }
    }
    // 计数地板：六行必须**都**找到并解析（少了就是首页改了形状，而这一层正在空转）
    if (frontRows !== FRONT.length) { console.log(`RED 首页对账只找到 ${frontRows}/${FRONT.length} 份首页行层 ⇒ 这一层不完整`); red++; }
    if (frontParsed === 0) { console.log('RED 首页对账一行都没解析到 ⇒ 这一层是空转'); red++; frontRed++; }

    for (const f of rows) {
        const name = (f[0] || '').trim();
        const rule = RULES.find(r => r.name === name);
        if (!rule) { if (name && known.has(name)) { /* 不会到这里 */ } other++; continue; }
        const art = (f[6] || '');
        const wantFile = { timing: 'timing_summary.rpt', util: 'utilization.rpt', power: 'power.rpt' }[rule.src];
        if (!art.includes(wantFile)) {
            console.log(`RED  row=${name}  点名的是 ${art}，不是 ${wantFile} —— 判据与凭据脱钩`);
            red++; judged++; continue;
        }
        const got = num(f[2]);
        const exp = rule.get(SRC[rule.src]);
        if (exp === null || exp === undefined) { console.log(`SKIP row=${name} 报告里取不到数`); other++; continue; }
        let ok = got !== null && Math.abs(got - exp) < 1e-6;
        let detail = `csv=${f[2]} report=${exp}`;
        for (const a of [rule.also, rule.also2]) {
            if (!a) continue;
            const fieldIdx = { '测量条件': 4, '数值': 2 }[a.in];
            const m = String(f[fieldIdx] || '').match(a.re);
            if (m) {
                const exp2 = a.get(SRC[rule.src]);
                detail += ` | ${a.what}: csv=${m[1]} report=${exp2}`;
                if (exp2 === null || exp2 === undefined || Math.abs(Number(m[1]) - exp2) > 1e-6) ok = false;
            }
        }
        if (ok) judged++; else { red++; if (String(f[4] || '').includes('自检：故意写错')) fixtureRed++; }
        console.log(`${ok ? 'OK ' : 'RED'} row=${name} ${detail}`);
    }
    console.log(`== 数字对账：判 ${judged} 个数（首页层 ${frontNums} 个／解析到 ${frontParsed}/${FRONT.length} 行；红 ${red}）／csv 未覆盖 ${other} 行（只报点名 timing/utilization/power 三份报告的行） ==`);
    if (self) {
        // 首页层的反例：把 WNS 那一格的三个数全换成不可能值，三条都必须不认。
        // 有一条"认了"就说明这一层是靠正则抓不到然后跳过的空转，而不是判据。
        const fake = KINDS.wns('**9.999 ns**（…），失败 setup/hold 端点 **9 / 999999**', SRC.timing);
        const caught = fake.filter(([, g, e]) => g !== e).length;
        if (caught !== fake.length) {
            console.log(`SELF-front: 不过 —— 造的 ${fake.length} 个首页假数应全被抓到，实得 ${caught}（这一层在空转）`);
            process.exit(1);
        }
        console.log(`SELF-front: 过 —— 造的 ${fake.length} 个首页假数全被抓到`);
        // 自检只问"我注入的那一条 fixture 有没有被抓到"：全树其余行本来就跟着新一轮报告走，
        // 构建一变它们就集体变红（那是正确的红），不该拿"恰好 1 条"当自检期望。
        const want = rows.filter((r) => String(r[4] || '').includes('自检：故意写错')).length;
        const got = fixtureRed;
        if (want === 1 && got === 1) console.log(`SELF: 过 —— 故意写错的那一条正好被抓到 1 次（全树另有 ${red - got} 条真实红，其中首页层 ${frontRed}）`);
        else { console.log(`SELF: 不过 —— fixture 期望 1 红，实得 ${got}（表里 fixture 行数 ${want}）`); process.exit(1); }
        return;
    }
    if (red) process.exit(1);
}

run(process.argv.includes('--self'));
