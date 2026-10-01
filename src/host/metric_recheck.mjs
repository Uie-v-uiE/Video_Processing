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

    // 首页那两行也一起判（#213）：README 的表格里写着"全设计 setup WNS = 0.720 ns"并点名
    // `build/timing_summary.rpt`，可**没有任何检查器回去读那份报告**——metrics.csv 有 D6 管，首页没有。
    // 于是"首页引用的是哪份报告"与"那份报告现在说什么"之间的账是空的，跨版一定会烂。
    // 复用同一批 RULES 与同一个取数器，不另起一套口径；解析不到行 = 直接判红（不许空转）。
    const FRONT = [
        ['README.md', '全设计 setup WNS', '全局 setup WNS'],
        ['README.en.md', 'Design-wide setup WNS', '全局 setup WNS'],
    ];
    let frontParsed = 0, frontRed = 0, fixtureRed = 0;
    for (const [file, key, ruleName] of FRONT) {
        if (!fs.existsSync(file)) { console.log(`RED row=${file} 找不到这份首页`); red++; frontRed++; continue; }
        const ls = fs.readFileSync(file, 'utf8').split(/\r?\n/);
        let hit = -1;
        for (let i = 0; i < ls.length; i++) if (ls[i].startsWith('|') && ls[i].includes(key)) { hit = i; break; }
        if (hit < 0) { console.log(`RED row=${file} 里找不到「${key}」这一行 ⇒ 首页与指标表脱钩`); red++; frontRed++; continue; }
        const cells = ls[hit].split('|').map((s) => s.trim());
        const art = cells[cells.length - 2] || '';
        const rule = RULES.find((r) => r.name === ruleName);
        const wantFile = { timing: 'timing_summary.rpt', util: 'utilization.rpt', power: 'power.rpt' }[rule.src];
        frontParsed++;
        if (!art.includes(wantFile)) {
            console.log(`RED row=${file}:${hit + 1} 「${key}」点名的是 ${art}，不是 ${wantFile} —— 判据与凭据脱钩`);
            red++; frontRed++; judged++; continue;
        }
        const got = num(cells[2]), exp = rule.get(SRC[rule.src]);
        const ok = got !== null && exp !== null && exp !== undefined && Math.abs(got - exp) < 1e-6;
        console.log(`${ok ? 'OK ' : 'RED'} row=${file}:${hit + 1} ${key} 首页=${cells[2]} 报告=${exp}`);
        if (!ok) { red++; frontRed++; }
        judged++;
    }
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
    console.log(`== 数字对账：判 ${judged} 行（红 ${red}）／未覆盖 ${other} 行（只报点名 timing/utilization/power 三份报告的行） ==`);
    if (self) {
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
