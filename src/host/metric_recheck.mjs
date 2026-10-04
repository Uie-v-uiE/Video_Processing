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

function num(s) { const m = String(s).split(MINUS).join('-').match(/-?\d+(?:\.\d+)?/); return m ? Number(m[0]) : null; }

// r116 起，首页那几行的 slack 可能是**负**的（第一次给 RGMII 输入绑窗之后，`eth_rxc` 的 setup/hold
// 两格就是负的，而且这是本轮唯一真实的红）。旧写法只认 `[0-9]+\\.[0-9]+` ⇒ 负数一律读成 null，
// 而 null 在这个尺子里是"判红"——于是**文档写对了也红**，这是尺子的射程缺了符号这一维（#321）。
// 中文文档里用的是 U+2212（−），英文文档里可能用 ASCII hyphen，两者都要能吃进去再交给 Number()，
// 否则 `Number('−0.846')` 是 NaN，会比读不到更难查。
const MINUS = '−';
function sgn(s) { return s === null || s === undefined ? null : Number(String(s).split(MINUS).join('-')); }

// ---- 报告侧的读数（每个提取器都说清它读的是哪一行，判红时要能指着看）
function fromTiming(p) {
    const t = fs.readFileSync(p, 'utf8');
    const blk = t.split('Design Timing Summary')[1] || '';
    const m = blk.match(/WNS\(ns\)[^\n]*\n[^\n]*\n\s*(-?[0-9.]+)\s+(-?[0-9.]+)\s+(\d+)\s+(\d+)\s+(-?[0-9.]+)/);
    if (!m) throw new Error('timing_summary.rpt 里读不到 Design Timing Summary 那一行');
    // 逐时钟 WNS/WHS 也一起读：百分数的分母必须来自报告，不能由人脑补（今天那个 12 % 就是这么来的）。
    // 报告里这张 `Intra Clock Table` 的**数据行没有竖线**，是空格对齐的 ⇒ 按块切（Intra→Inter）再按
    // 字段数判：一行要有 时钟名 WNS TNS 失败数 总数 WHS 六个字段才收，只有 WPWS 的那几行（clkfbout…）
    // 天然被拒。（此前这里用的是一条要求行首有 `|` 的正则，对这份报告**命中 0 次**、四个时钟全读成 null。）
    const intra = (t.split('| Intra Clock Table')[1] || '').split('Inter Clock Table')[0];
    const periods = {};
    for (const line of intra.split('\n')) {
        const r = line.match(/^\s*(\S+)\s+(-?[0-9.]+)\s+(-?[0-9.]+)\s+(\d+)\s+(\d+)\s+(-?[0-9.]+)/);
        if (r) periods[r[1]] = { wns: Number(r[2]), whs: Number(r[6]) };
    }
    const per = {};
    const cs = (t.split('| Clock Summary')[1] || '').split('Clock Groups')[0].split('Intra Clock Table')[0];
    for (const line of cs.split('\n')) {
        const p = line.match(/^\s*(\S+)\s+\{[^}]*\}\s+([0-9.]+)\s+([0-9.]+)/);
        if (p) per[p[1]] = { period: Number(p[2]), freq: Number(p[3]) };
    }
    return { wns: Number(m[1]), failSetup: Number(m[3]), totalEp: Number(m[4]), whs: Number(m[5]), periods, per };
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

// ---- 首页那一层的取数器（#213 只判 WNS 一格，#159 扩到四行，本轮再扩到**每份首页五行**：
//      WNS / 逐时钟 setup / 逐时钟 hold / 占用 / 功耗。逐时钟两行是 2026-10-02 补的，见 KINDS.clocks|whs）----
// 与 RULES 共用**同一批报告读数**（fromTiming/fromUtil/fromPower），不另起第二份真值。
function one(cell, re, g = 1) { const m = cell.match(re); return m ? sgn(m[g]) : null; }
function file_line(e, hit) { return `${e.file}:${hit + 1}`; }
function grabPairs(cell) {                    // `14333（26.94 %）` 与 `14333 (26.94 %)` 两种括号都认
    const out = [];
    for (const m of cell.matchAll(/(\d+)\s*[（(]\s*([\d.]+)\s*%[）)]/g)) out.push([Number(m[1]), Number(m[2])]);
    return out;
}
// 每个 kind 返回 [判点名, 首页读数, 报告读数]；读数抓不到 = null，**null 一律判红**（不许"抓不到就跳过"）
const KINDS = {
    wns: (c, s) => [
        ['WNS(ns)', one(c, new RegExp('\\*\\*([' + '[-' + MINUS + ']?[0-9]+\\.[0-9]+)\\s*ns\\*\\*')), s.wns],
        ['失败 setup/hold 端点', one(c, /\*\*([0-9]+)\s*\/\s*[0-9]{4,}\*\*/), s.failSetup],
        ['端点总数', one(c, /\*\*[0-9]+\s*\/\s*([0-9]{4,})\*\*/), s.totalEp],
    ],
    util: (c, s) => {
        const rows = [
            ['BRAM tile', one(c, /([0-9]+(?:\.[0-9]+)?)\s*tiles?\s*[（(]/), s.bram ? s.bram.use : null],
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
    // 逐时钟 setup 余量那一行（2026-10-02 加，起因是 r104 采纳时首页只换了 WNS 行，
    // 这一行整行留着 r103 的四个数、自相矛盾了两天而没人抓住 ⇒ 这一行进尺子的射程）。
    // 报告侧的数就是 fromTiming 里那张 `periods`（Intra Clock Table 每行的 WNS 列），不另起第二份真值。
    clocks: (c, s) => {
        const names = ['eth_rxc', 'clk_fpga_0', 'clkout0_1', 'sys_clk'];
        const rows = [];
        for (const n of names) {
            const m = c.match(new RegExp('`' + n + '`[^*]*\\*\\*(' + '[-' + MINUS + ']?[0-9]+\\.[0-9]+)\\s*ns\\*\\*'));
            const p = s.periods && s.periods[n] ? s.periods[n].wns : null;
            rows.push(['setup[' + n + ']', m ? sgn(m[1]) : null, p]);
        }
        // 形状也要判：首页点名的时钟个数要对回**报告里真有 WNS 的那几个**，不是对回这份硬编码名单。
        // （前一版写成 `names.filter(...).length` 对 `names.length`，两边是同一个数组 ⇒ 永远 4 比 4、
        //  这一行根本动不了；报告新增一个有时序的时钟域、或首页少点一个名，它都抓不住。）
        const inReport = Object.keys(s.periods || {}).length;
        rows.push(['时钟名个数', names.filter((n) => c.includes('`' + n + '`')).length, inReport]);
        // 首页这一行还写了**百分数**（"占它 8 ns 周期的 10.2 %"），以前没人回读它：
        // 分子是逐时钟 slack、分母是那个时钟的周期，两个数报告里都有（Intra Clock Table + Clock Summary），
        // 所以这句话完全可判。这正是 #12 那条注释警告过的形状——百分数的分母不许人脑补。
        // 判法：允许四舍五入到一位小数的误差（±0.05），超出就是红，红的时候念出真值。
        for (const n of names) {
            // 取"这个时钟名到下一个时钟名之间"那段，而不是按分隔符切：中文首页用「；」，英文那行用「;」，
            // 第一版按「；」切 ⇒ 英文整格是一整段，`sys_clk` 吃到了 eth_rxc 的 10.2 %、`clk_fpga_0` 也吃到
            // 10.2 %，**凭空造出两条红**（#8 那一课：先怀疑尺子，别先怀疑被测物）。
            const i = c.indexOf('`' + n + '`');
            let j = c.length;
            for (const m of names) { const k = c.indexOf('`' + m + '`'); if (k > i && k < j) j = k; }
            const seg = i < 0 ? '' : c.slice(i, j);
            const slack = s.periods && s.periods[n] ? s.periods[n].wns : null;
            const per = s.per && s.per[n] ? s.per[n].period : null;
            const qm = seg.match(/(?:占它|of its)\s*([0-9]+(?:\.[0-9]+)?)\s*ns/);
            if (qm) rows.push(['周期[' + n + ']', Number(qm[1]), per]);
            const pm = seg.match(new RegExp('\\*\\*[-' + MINUS + ']?[0-9.]+\\s*ns\\*\\*[^%]{0,24}?([-' + MINUS + ']?[0-9]+(?:\\.[0-9]+)?)\\s*%'));
            if (pm) {
                const ratio = (slack !== null && per) ? (slack / per) * 100 : null;
                const claimed = sgn(pm[1]);
                const exp = ratio === null ? null
                    : (Math.abs(ratio - claimed) <= 0.05 ? claimed : Number(ratio.toFixed(3)));
                rows.push(['余量%[' + n + ']', claimed, exp]);
            }
        }
        return rows;
    },
    // 逐时钟 hold（WHS）那一行（2026-10-02 加）：与上一行同族，r104 采纳时同样漏了同步，而它比 setup
    // 那一行更阴——全设计 WHS 的绝对值（0.053）恰好等于 r103 里 `eth_rxc` 那一格的数，所以"首页与
    // `metrics.csv` 的 WHS 对得上"这条直觉**完全掩盖**了"最差那一格已经换到 `clk_fpga_0`"。
    // 所以除了四个数各自对回报告，还要判**归属**：点名那一格的报告 WHS 必须等于报告里的最小 WHS。
    whs: (c, s) => {
        const names = ['eth_rxc', 'clk_fpga_0', 'clkout0_1', 'sys_clk'];
        const rows = [];
        for (const n of names) {
            const m = c.match(new RegExp('`' + n + '`[^*]*\\*\\*(' + '[-' + MINUS + ']?[0-9]+\\.[0-9]+)\\s*ns\\*\\*'));
            const p = s.periods && s.periods[n] ? s.periods[n].whs : null;
            rows.push(['whs[' + n + ']', m ? sgn(m[1]) : null, p]);
        }
        rows.push(['时钟名个数', names.filter((n) => c.includes('`' + n + '`')).length, Object.keys(s.periods || {}).length]);
        const w = c.match(/(?:最差|worst)[^`]*`([A-Za-z0-9_]+)`/);
        const claimed = w && s.periods && s.periods[w[1]] ? s.periods[w[1]].whs : null;
        const vals = Object.values(s.periods || {}).map((o) => o.whs).filter((v) => typeof v === 'number');
        rows.push(['最差那一格的 WHS', claimed, vals.length ? Math.min(...vals) : null]);
        return rows;
    },
};

const RULES = [
    { name: '显示像素时钟', src: 'timing', get: r => (r.per && r.per.clkout0_1) ? r.per.clkout0_1.freq : null, note: 'Clock Summary 里 MMCM 那一输出的 Frequency' },
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
    // 第二条 fixture 测的是"点了报告、却没人认领"这一格（旧写法只 other++，静默）：
    // 删掉下面那个 orphan 判红，这条 fixture 就不红了 ⇒ 它就是那一格的"改前必须红"。
    if (self) rows.push(['自检：没有规则认领的一行', '核心', '+1.000', 'MHz', '自检：故意写错的一条', '一次构建', 'build/timing_summary.rpt']);
    let red = 0, judged = 0, other = 0;

    // 首页那五行也一起判（#213 起了这个头，#159 扩到"四行 26 个数"，本轮 #224 补到每份五行：
    //   逐时钟 setup 与逐时钟 hold 是刚被抓出来的两行 stale；现在的条数由脚本自己念，不在注释里钉死）：
    // README 的表格里写着 WNS、逐资源占用与功耗，并点名 `build/timing_summary.rpt` /
    // `build/utilization.rpt` / `build/power.rpt`，可**没有任何检查器回去读那三份报告**——
    // metrics.csv 有 D6 管，首页没有。于是"首页引用的是哪份报告"与"那份报告现在说什么"之间的
    // 账是空的，跨版一定会烂。⚠ 这条判据的"改前必须红"不用我造：第一次跑就抓到首页功耗行
    // 写 2.212 W / 52.6 °C 而报告是 2.211 / 52.5，占用行写 14333 / 8079 而报告是 14334 / 8127
    //（r103→r104 那一轮只同步了 metrics.csv，首页漏了四格）。
    // 复用同一批报告读数，不另起口径；行找不到、数抓不到、括号对数不对 ⇒ 一律判红（不许空转）。
    // ---- 符号这一维的自带对照（G10「每条新增门禁自己也要有一个测试」+ rule 46「必须有能红的对照」）----
    // r116 之前这份尺子只认 `[0-9]+\\.[0-9]+`，负 slack 一律读成 null；而 null 在这里是"判红"，
    // 于是**首页把 −0.846 写对了也照样红**、写错了也是同样红——符号这一维根本没有射程（#321）。
    // 这里用一份合成读数（不是真实报告）跑两遍：已知绿的负数必须解析成对的数、已知红的负数必须仍然红。
    // 任何一边失效 ⇒ 这一层就是空转，直接算红并计数（不许"对照跑不过就跳过"）。
    {
        const rep = {
            wns: -0.846, failSetup: 5, totalEp: 51140, whs: -0.870,
            periods: {
                eth_rxc: { wns: -0.846, whs: -0.870 }, clk_fpga_0: { wns: 2.009, whs: 0.053 },
                clkout0_1: { wns: 3.885, whs: 0.059 }, sys_clk: { wns: 15.174, whs: 0.222 },
            },
            per: { eth_rxc: { period: 8 }, clk_fpga_0: { period: 10 }, clkout0_1: { period: 20 }, sys_clk: { period: 20 } },
        };
        const clockCell = (vEth, vFpga, vPix, vSys, pEth, pFpga, pPix, pSys) =>
            '125 MHz 收包域 `eth_rxc` **' + vEth + ' ns**（占它 8 ns 周期的 ' + pEth + ' %）；'
            + '100 MHz `clk_fpga_0` **' + vFpga + ' ns**（占它 10 ns 周期的 ' + pFpga + ' %）；'
            + '50 MHz 显示域 `clkout0_1` **' + vPix + ' ns**（占它 20 ns 周期的 ' + pPix + ' %）；'
            + '`sys_clk` **' + vSys + ' ns**（占它 20 ns 周期的 ' + pSys + ' %）';
        const holdCell = '全设计最差那一格在 `eth_rxc`，**' + MINUS + '0.870 ns**；'
            + '`clk_fpga_0` **0.053 ns**；`clkout0_1` **0.059 ns**；`sys_clk` **0.222 ns**';
        const fixtures = [
            ['wns/good', KINDS.wns('| x | **' + MINUS + '0.846 ns**（失败 setup/hold 端点 **5 / 51140**） | r |', rep), true],
            ['wns/bad', KINDS.wns('| x | **' + MINUS + '9.999 ns**（失败 setup/hold 端点 **5 / 51140**） | r |', rep), false],
            ['clocks/good', KINDS.clocks(clockCell(MINUS + '0.846', '2.009', '3.885', '15.174', MINUS + '10.57', '20.09', '19.43', '75.87'), rep), true],
            ['clocks/bad', KINDS.clocks(clockCell(MINUS + '0.846', '2.009', '3.885', '15.174', '10.57', '20.09', '19.43', '75.87'), rep), false],
            ['whs/good', KINDS.whs(holdCell, rep), true],
            ['whs/bad', KINDS.whs(holdCell.replace(MINUS + '0.870', MINUS + '0.871'), rep), false],
        ];
        let signChecked = 0, signBad = 0;
        for (const [tag, rows, shouldBeGreen] of fixtures) {
            if (!rows.length) { console.log(`SELFSIGN-RED ${tag} 一行都没判出来（fixture 形状与取数器脱钩）`); signChecked++; signBad++; continue; }
            const greens = rows.filter(([, g, e]) => g !== null && e !== null && Math.abs(g - e) < 1e-6).length;
            const allGreen = greens === rows.length;
            const ok = shouldBeGreen ? allGreen : !allGreen;
            console.log(`SELFSIGN ${tag} rows=${rows.length} green=${greens}/${rows.length} expect=${shouldBeGreen ? 'all-green' : 'some-red'} verdict=${ok ? 'OK' : 'RED'}`);
            signChecked++;
            if (!ok) signBad++;
            judged += rows.length;
        }
        if (signChecked !== fixtures.length) { console.log(`SELFSIGN-RED 只跑了 ${signChecked}/${fixtures.length} 条符号对照`); red++; }
        if (signBad) { console.log(`SELFSIGN-COVERAGE 符号对照有 ${signBad} 条不达预期 ⇒ 这一层没有射程`); red += signBad; }
        else console.log(`SELFSIGN-SUMMARY 判 ${signChecked} 条（负数可读=绿、负数写错=红），红 0`);
    }

    const FRONT = [
        { file: 'README.md', key: '全设计 setup WNS', want: 'timing_summary.rpt', src: 'timing', kind: 'wns' },
        { file: 'README.md', key: '逐时钟 setup 余量', want: 'timing_summary.rpt', src: 'timing', kind: 'clocks' },
        { file: 'README.md', key: '保持时间', want: 'timing_summary.rpt', src: 'timing', kind: 'whs' },
        { file: 'README.md', key: 'BRAM / LUT / FF / DSP', want: 'utilization.rpt', src: 'util', kind: 'util' },
        { file: 'README.md', key: '功耗', want: 'power.rpt', src: 'power', kind: 'power' },
        { file: 'README_EN.md', key: 'Design-wide setup WNS', want: 'timing_summary.rpt', src: 'timing', kind: 'wns' },
        { file: 'README_EN.md', key: 'Per-clock setup slack', want: 'timing_summary.rpt', src: 'timing', kind: 'clocks' },
        { file: 'README_EN.md', key: 'Hold time', want: 'timing_summary.rpt', src: 'timing', kind: 'whs' },
        { file: 'README_EN.md', key: 'BRAM / LUT / FF / DSP', want: 'utilization.rpt', src: 'util', kind: 'util' },
        { file: 'README_EN.md', key: 'Power', want: 'power.rpt', src: 'power', kind: 'power' },
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

    // 三条把这一层的"射程"自己念出来（#194/#219 同族：计数不落地，尺子就能空转）：
    //   ① `judged` 以前只在绿行累加 ⇒ 一轮构建把 csv 判红 7 条，汇总行就"少了 7 个被判的数"，
    //      看起来像射程缩了、其实是红了。判过就计数，红绿都算。
    //   ② 报告里取不到数以前是 `SKIP` + 静默计入"未覆盖" ⇒ 解析断一行等于把那行的账抹掉，
    //      现在它是红（并且点名是哪一个规则断了）。
    //   ③ csv 里点了三份报告之一、却没有任何规则认领 ⇒ 以前只是 `other++`。这种行**就是**
    //      "首页/指标表引用了报告但没人回头读"的那个洞（#213 立案的原因），现在逐行判红。
    const NAMED = /timing_summary\.rpt|utilization\.rpt|power\.rpt/;
    let csvNamed = 0, csvClaimed = 0;
    for (const f of rows) {
        const name = (f[0] || '').trim();
        const art = (f[6] || '');
        const named = NAMED.test(art);
        if (named) csvNamed++;
        const rule = RULES.find(r => r.name === name);
        if (rule) csvClaimed++;
        if (!rule) {
            if (named) {
                console.log(`RED  row=${name}  引用了 ${art}，但没有任何规则认领这一行 ⇒ 这个数没人对账`);
                red++; judged++;
                if (String(f[4] || '').includes('自检：故意写错')) fixtureRed++;
            } else other++;
            continue;
        }
        const wantFile = { timing: 'timing_summary.rpt', util: 'utilization.rpt', power: 'power.rpt' }[rule.src];
        if (!art.includes(wantFile)) {
            console.log(`RED  row=${name}  点名的是 ${art}，不是 ${wantFile} —— 判据与凭据脱钩`);
            red++; judged++; continue;
        }
        const got = num(f[2]);
        const exp = rule.get(SRC[rule.src]);
        if (exp === null || exp === undefined) {
            console.log(`RED  row=${name}  报告里取不到数（规则「${rule.name}」的取数断了）—— 不许 SKIP`);
            red++; judged++; continue;
        }
        judged++;
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
        if (!ok) { red++; if (String(f[4] || '').includes('自检：故意写错')) fixtureRed++; }
        console.log(`${ok ? 'OK ' : 'RED'} row=${name} ${detail}`);
    }
    // 认领地板：点名三份报告的 csv 行必须**全部**有规则认领，且这一层至少判到 8 行。
    // 没有这条地板，"删掉一个规则"或"改了一个指标名"都会让射程缩掉而没人喊。
    if (csvNamed !== csvClaimed) {
        console.log(`RED  csv 点名三份报告 ${csvNamed} 行，规则只认领 ${csvClaimed} 行 ⇒ 有引用没人对账`);
        red++;
    }
    if (csvClaimed < 8) { console.log(`RED  csv 侧只认领到 ${csvClaimed} 行（地板 8）⇒ 这一层在空转`); red++; }
    console.log(`== 数字对账：判 ${judged} 个数（首页层 ${frontNums} 个／解析到 ${frontParsed}/${FRONT.length} 行；红 ${red}）／csv 认领 ${csvClaimed}/${csvNamed} 行／其余 ${other} 行不点名这三份报告 ==`);
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
        // 逐时钟那一行是这一层新加的形状，它不在 csv 里、没法用上面那条 fixture 测牙，
        // 所以就地用两段假首页 + 三份假报告读数验它"能红也能绿"（规矩：检查器自己带对照）。
        const fakeSrc = { periods: { eth_rxc: { wns: 0.812 }, clk_fpga_0: { wns: 1.358 }, clkout0_1: { wns: 2.674 }, sys_clk: { wns: 15.036 } } };
        const goodCell = '`eth_rxc` **0.812 ns**；`clk_fpga_0` **1.358 ns**；`clkout0_1` **2.674 ns**；`sys_clk` **15.036 ns**';
        const badCell = goodCell.replace('**2.674 ns**', '**1.061 ns**');          // 就是 r103 那一版留在首页的错数
        const shortCell = goodCell.replace('；`sys_clk` **15.036 ns**', '');         // 首页少点一个名 = 形状变了
        // 报告侧能动的对照：假报告少一个时钟域（新增/删除时钟域是构建侧的事，不该只由首页一侧决定）
        const threeSrc = { periods: { eth_rxc: { wns: 0.812 }, clk_fpga_0: { wns: 1.358 }, clkout0_1: { wns: 2.674 } } };
        const diff = (cell, src) => KINDS.clocks(cell, src).filter(([, g, e]) => g !== e).length;
        const badN = diff(badCell, fakeSrc), shortN = diff(shortCell, fakeSrc), goodN = diff(goodCell, fakeSrc);
        const repShortN = diff(goodCell, threeSrc);
        // 逐时钟 hold 那一行的对照，重点是**归属**这一维：四个数都对、只把"最差那一格"指错域，
        // 正是今天首页那条 stale 行的形状（它指 `eth_rxc`，而 r104 最小 WHS 在 `clk_fpga_0`）。
        const whsSrc = { periods: { clk_fpga_0: { whs: 0.053 }, eth_rxc: { whs: 0.056 }, clkout0_1: { whs: 0.068 }, sys_clk: { whs: 0.121 } } };
        const whsGood = '最差那一格在 `clk_fpga_0`；`clk_fpga_0` **0.053 ns**；`eth_rxc` **0.056 ns**；`clkout0_1` **0.068 ns**；`sys_clk` **0.121 ns**';
        const whsWrongOwner = whsGood.replace('最差那一格在 `clk_fpga_0`', '最差那一格在 `eth_rxc`');
        const wdiff = (cell) => KINDS.whs(cell, whsSrc).filter(([, g, e]) => g !== e).length;
        const whsGoodN = wdiff(whsGood), whsOwnN = wdiff(whsWrongOwner);
        // 解析器自己要有地板：真实报告读不出逐时钟数（今天命中 0 次那一版）就是这一层在空转。
        const nRep = Object.keys(SRC.timing.periods || {}).length;
        // 百分数那一半的对照：正常 0 红、改错一个数能红、报告读不到周期时必须红
        // （分母没了这句就没有凭据，绝不许"抓不到就不判"——#12 注释里那个 12 % 的教训）。
        const pctSrc = { periods: fakeSrc.periods, per: { eth_rxc: { period: 8 }, clk_fpga_0: { period: 10 }, clkout0_1: { period: 20 } } };
        const pctCell = '`eth_rxc` **0.812 ns**（占它 8 ns 周期的 10.2 %）；`clk_fpga_0` **1.358 ns**（13.6 %）；`clkout0_1` **2.674 ns**（13.4 %）；`sys_clk` **15.036 ns**';
        const pctBadCell = pctCell.replace('13.4 %', '10.0 %');
        const okRow = ([, g, e]) => g !== null && e !== null && Math.abs(g - e) < 1e-6;
        const pctN = KINDS.clocks(pctCell, pctSrc).filter((r) => !okRow(r)).length;
        const pctBadN = KINDS.clocks(pctBadCell, pctSrc).filter((r) => !okRow(r)).length;
        const pctNoPerN = KINDS.clocks(pctCell, { periods: fakeSrc.periods }).filter((r) => !okRow(r)).length;
        // 形状对照：英文版那行用 ASCII 分号，必须**照样**按时钟归位（第一版就是在这里凭空造出两条红）。
        const pctEnCell = '`eth_rxc` **0.812 ns** (10.2 % of its 8 ns period, the design worst); `clk_fpga_0` **1.358 ns** (13.6 %); `clkout0_1` **2.674 ns** (13.4 %); `sys_clk` **15.036 ns**';
        const pctEnN = KINDS.clocks(pctEnCell, pctSrc).filter((r) => !okRow(r)).length;
        const pctEnBadN = KINDS.clocks(pctEnCell.replace('13.6 %', '19.9 %'), pctSrc).filter((r) => !okRow(r)).length;
        // 本轮新加的两格射程都要有牙（#194：死分支与"没有计数的判据"都算检查器缺陷）：
        //   · Clock Summary 解析地板：真实报告里至少读到 4 个时钟的周期，否则"显示像素时钟"那行是空转。
        //   · 取数断掉要**能**红：如果规则在缺数据的报告上返回不了 null，那"不许 SKIP"那一格就是死代码。
        const nPer = Object.keys(SRC.timing.per || {}).length;
        const pixRule = RULES.find((r) => r.name === '显示像素时钟');
        const pixReal = pixRule ? pixRule.get(SRC.timing) : null;
        const nullReachable = !pixRule || pixRule.get({ per: {} }) === null;
        const unitOk = goodN === 0 && badN >= 1 && shortN >= 1 && repShortN >= 1 && nRep >= 4
            && whsGoodN === 0 && whsOwnN >= 1
            && nPer >= 4 && pixReal === 50 && nullReachable
            && pctN === 0 && pctBadN >= 1 && pctNoPerN >= 1 && pctEnN === 0 && pctEnBadN >= 1;
        console.log(`  ${unitOk ? 'PASS' : 'FAIL'} 自检·余量百分数：中文行正常 0 不符（实得 ${pctN}）｜改错一个能红（${pctBadN}）｜读不到周期能红（${pctNoPerN}，分母没有就不许判绿）｜英文分号行正常 0 不符（实得 ${pctEnN}）｜英文行改错能红（实得 ${pctEnBadN}）`);
        console.log(`  ${unitOk ? 'PASS' : 'FAIL'} 自检·逐时钟行：正常 0 不符（实得 ${goodN}）｜首页改回 r103 那个数能红（实得 ${badN}）｜首页少一个名能红（实得 ${shortN}）｜报告少一个时钟域能红（实得 ${repShortN}）｜真实报告解析到 ${nRep} 个逐时钟数（地板 4）`);
        console.log(`  ${unitOk ? 'PASS' : 'FAIL'} 自检·逐时钟 hold 行：正常 0 不符（实得 ${whsGoodN}）｜四个数全对但"最差那一格"指错域能红（实得 ${whsOwnN}）`);
        console.log(`  ${unitOk ? 'PASS' : 'FAIL'} 自检·Clock Summary 行：真实报告解析到 ${nPer} 个时钟周期（地板 4）｜显示像素时钟对回 ${pixReal}（期望 50）｜报告缺数据时取数能返回 null（否则"不许 SKIP"是死代码）${nullReachable ? '' : ' —— 不成立'}`);
        if (want === 2 && got === want && unitOk) console.log(`SELF: 过 —— 两条 fixture（写错的数 / 没人认领的引用）正好被抓到 ${got} 次（全树另有 ${red - got} 条真实红，其中首页层 ${frontRed}）`);
        else { console.log(`SELF: 不过 —— fixture 期望 2 红，实得 ${got}（表里 fixture 行数 ${want}）；逐时钟行自检 ${unitOk ? '过' : '不过'}`); process.exit(1); }
        return;
    }
    if (red) process.exit(1);
}

run(process.argv.includes('--self'));
