// src/host/doc_currency_check.mjs —— "文档不许把旧构建念成当前"
//
// 为什么要有它（这一轮撞了两次，都是同一类）：
//   * `report/PERF_REPORT.md` 的"当前值看这里"指到 `CHANGELOG_V7.md`，而那份日志最后一节是
//     V7.9（R22+R23）——照它念会念到五十多版之前。
//   * `README.md` / `README.en.md` 的实现结果行一直写着 `当前默认 bit（build#23）：WNS +0.740 …`，
//     而板上烧的是 r71；同一张命令表还把 `bilin` 写成"主线目前不含此项"，而它早就在主线上了。
//   这类错的讨厌之处和坏字一样：**它不改变任何行为**。位流照编、台架照跑、门禁照绿，
//   坏的是"念给评审听的那一句"。所以判据必须自己跑 ⇒ `build/gates.sh` 第 18 项。
//
// 三条判据（口径都在下面逐条写着，故意收得很窄——宽一寸就会把"历史上第 4 版得到 WNS +0.708"
// 这种正当的过去式念成红）：
//   D1 一行话既说"当前/默认"又点名一个带编号的构建（`build#NN` / `frozen_rNN`）⇒ 红。
//      编号的构建目录是历史凭据，只能以过去式出现；"当前"那一句必须点名**门禁全绿那一套**。
//   D2 文档里点名的 `build/frozen_*` / `build/evidence_*` 目录必须真的在盘上。
//      冻结件被移动或改名之后，文档里的"复核一条命令"就变成一条跑不通的命令。
//   D3 首页（README.md / README.en.md）里"门禁全绿 = rNN"这一句点名的那一套，必须等于
//      `build/*gates*.txt` 里**编号最大且写着 GATES: ALL PASS** 的那一套；并且 README.md 里
//      至少要有这么一句（没有就等于没说）。⇒ 下一次冻结成功时，这一条会自己变红，逼着改首页。
//
// 用法：node src/host/doc_currency_check.mjs [--self|--probe]
//   --self  判据自己的反例（三条各造一条坏输入 + 一条正当的过去式不许误报）
//   --probe 只报数不判红（用来先看口径会不会咬到正当的历史句）
import { readFileSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..', '..');
const EXT = new Set(['.md', '.mjs', '.sh', '.ps1', '.tcl']);
// **只扫"念给人看的那一份"**：首页、板上操作卡、性能报告、构建说明、比赛清单、演示脚本、命令表。
// 为什么把 `report/OVERNIGHT_LOG.md`、`report/CHANGELOG_V7.md`、`report/ISSUES.md`、
// `report/VERSION_LINEAGE.md` 排除在 D1 之外——它们是**日记**，里面的"当前默认 #23""下一步冻结
// frozen_r61_geom"写的是**当时**的当前与当时的计划。拿今天的盘去判昨天的日记，红的不是文档过期，
// 而是我逼着自己回头改日记（那是销毁过程凭据，比过期更糟）。要改的永远是"现在还会被念出来"的那几页。
const SCOPE_DOCS = ['README.md', 'README.en.md', 'board/README.md',
    'report/PERF_REPORT.md', 'report/BUILD.md', 'report/CONTEST_CHECKLIST.md',
    'report/DEMO_SCRIPT.md', 'report/COMMANDS.md', 'report/BACKGROUND_AND_NOVELTY.md'];
// 会被复制粘贴去跑的脚本：里面的指路同样要成立。
const SCOPE_DIRS = ['build/tcl', 'src/host'];
const SKIP_DIR = new Set(['.git', 'vivado_system', 'xsim.dir', 'node_modules', '.Xil', 'dist']);
const HOME = ['README.md', 'README.en.md'];          // D3 只看首页这两份
const SELF = 'src/host/doc_currency_check.mjs';      // 判据不看自己的例子（例子里就得写坏句）

function walk(dir, out) {
    for (const name of readdirSync(dir)) {
        const p = path.join(dir, name);
        const st = statSync(p);
        if (st.isDirectory()) { if (!SKIP_DIR.has(name)) walk(p, out); }
        else if (EXT.has(path.extname(name))) out.push(p);
    }
    return out;
}

function scopedFiles() {
    const out = [];
    for (const rel of SCOPE_DOCS) {
        try { if (statSync(path.join(ROOT, rel)).isFile()) out.push(path.join(ROOT, rel)); } catch { /* 缺文件另有 D 项管 */ }
    }
    for (const rel of SCOPE_DIRS) {
        let st;
        try { st = statSync(path.join(ROOT, rel)); } catch { continue; }
        if (st.isDirectory()) walk(path.join(ROOT, rel), out);
    }
    return out;
}

const NOW = /(当前默认|现在默认|默认 bit|current default|default bit)/;
const NUM = /(build#\d+|frozen_r\d)/;
// 只认**从仓库根起算**的那一种：前面有路径分隔符或名字（`submission/build/frozen_r26/`），
// 就不该拿工作区的盘去判它存在与否。
const CITED = /(^|[^/\w.-])build\/(frozen_[\w.-]+|evidence_[\w.-]+)/g;
const GREEN = /(门禁全绿|gate-?green)[^。\n]{0,40}?\br(\d+)/i;
// 目录名里必须有真实编号：`frozen_rNN_…`（BUILD.md 讲的是命名规则）与光秃秃的 `frozen_r`（glob）都不算引用。
function citable(tok) { return /_r\d{2,}(_|$)/.test(tok) && !tok.includes('NN'); }

// 纯函数：把"文件名 → 行"喂进来就能判，--self 因此不必真去改盘上的文件。
// `dirExists(tok)`：点名 `frozen_r23` 而盘上是 `frozen_r23_srcseen` 也算对上（文档里常省略后缀），
// 但一个编号都没有的（`frozen_r26`）就必须整名对上——省掉后缀只到"同一版"为止，不能跨省。
function checkLines(docLines, dirExists, newestGreen) {
    const rows = [];
    const claims = [];
    for (const [rel, lines] of Object.entries(docLines)) {
        if (rel === SELF) continue;
        lines.forEach((l, i) => {
            const at = `${rel}:${i + 1}`;
            if (NOW.test(l) && NUM.test(l))
                rows.push(`${at} D1 把带编号的旧构建说成"当前/默认"：${l.trim().slice(0, 80)}`);
            for (const m of l.matchAll(CITED)) {
                const tok = m[2];
                if (citable(tok) && !dirExists(tok))
                    rows.push(`${at} D2 点名的目录盘上没有：build/${tok}`);
            }
            const g = l.match(GREEN);
            if (g && HOME.includes(rel)) claims.push({ at, nn: Number(g[2]) });
        });
    }
    if (newestGreen > 0) {
        const home = claims.filter(c => c.at.startsWith('README.md') || c.at.startsWith('README.en.md'));
        if (!home.some(c => c.at.startsWith('README.md')))
            rows.push(`README.md D3 首页没有"门禁全绿 = rNN"这一句（最新那一套是 r${newestGreen}）`);
        for (const c of home)
            if (c.nn !== newestGreen)
                rows.push(`${c.at} D3 首页念的是 r${c.nn}，盘上最新且 ALL PASS 的那一套是 r${newestGreen}`);
    }
    return rows;
}

// `build/*gates*.txt` 两种命名都有（早期 gates_rNN.txt，后来 rNN_gates.txt），
// 取"编号最大且写着 GATES: ALL PASS"的那一套。文件名里的编号就是它判的那次构建。
function newestGreenSet() {
    let best = 0, name = '';
    const dir = path.join(ROOT, 'build');
    for (const f of readdirSync(dir)) {
        if (!/^gates_r(\d+)\.txt$|^r(\d+)_gates\.txt$/.test(f)) continue;
        let txt;
        try { txt = readFileSync(path.join(dir, f), 'utf8'); } catch { continue; }
        if (!/^GATES: ALL PASS/m.test(txt)) continue;
        const nn = Number(f.match(/(\d+)/)[1]);
        if (nn > best) { best = nn; name = f; }
    }
    return { nn: best, name };
}

function scanTree() {
    const docs = {};
    for (const p of scopedFiles()) {
        const rel = path.relative(ROOT, p).replace(/\\/g, '/');
        let txt;
        try { txt = readFileSync(p, 'utf8'); } catch { continue; }
        docs[rel] = txt.split('\n');
    }
    const dirs = [];
    try {
        for (const d of readdirSync(path.join(ROOT, 'build')))
            if (statSync(path.join(ROOT, 'build', d)).isDirectory()) dirs.push(d);
    } catch { /* build/ 一定在 */ }
    const has = (tok) => dirs.includes(tok) || dirs.some(d => d.startsWith(tok + '_'));
    const g = newestGreenSet();
    return { rows: checkLines(docs, has, g.nn), g, n: Object.keys(docs).length };
}

const argv = process.argv.slice(2);
if (argv.includes('--self')) {
    const yes = (tag, rows, want) => {
        const got = rows.filter(r => want.test(r)).length;
        console.log(`  ${got ? 'PASS' : 'FAIL'} ${tag}（该红的红了 ${got ? 1 : 0}，命中 ${got} 条）`);
        return got ? 1 : 0;
    };
    const okDir = () => true;
    let n = 0;
    n += yes('D1：把 build#23 写成"当前默认 bit"',
        checkLines({ 'X.md': ['当前默认 bit（build#23）：WNS +0.740'] }, okDir, 0), /D1/);
    n += yes('D2：引用一个盘上不存在的冻结目录',
        checkLines({ 'X.md': ['复核 `bash build/gates.sh build/evidence_r99_nope`'] }, () => false, 0), /D2/);
    n += yes('D3：首页念的那一套不是最新全绿的那一套',
        checkLines({ 'README.md': ['最近一次门禁全绿的冻结集 = r69：WNS +0.188'] }, okDir, 71), /D3/);
    // 正当句不许误报：过去式 + 编号目录真实存在 + 首页点的正是最新那套
    const good = checkLines({
        'report/CHANGELOG_V6.md': ['第四版得到 WNS +0.708 / 寄存器 51.30%（`build/frozen_r13`）'],
        'README.md': ['最近一次门禁全绿的冻结集 = r71：WNS +0.346'],
    }, okDir, 71);
    console.log(`  ${good.length === 0 ? 'PASS' : 'FAIL'} 对照：过去式与点名最新全绿的那一套都不误报（实测 ${good.length} 条）`);
    for (const r of good) console.log('        ' + r);
    // 两个"别咬到正当文本"的边界：命名规则里的占位名、以及**带路径前缀**的那一种（不是仓库根的 build/）。
    const edges = checkLines({
        'report/BUILD.md': ['冻结目录命名规则：`build/frozen_rNN_xxx/`（NN 是那一次构建的编号）',
            '备份包里的 `submission/build/frozen_r26/` 是复制品，不拿工作区判它存在与否'],
    }, () => false, 0);
    console.log(`  ${edges.length === 0 ? 'PASS' : 'FAIL'} 对照：占位名与带前缀的路径不误报（实测 ${edges.length} 条）`);
    for (const r of edges) console.log('        ' + r);
    const all = n === 3 && good.length === 0 && edges.length === 0;
    console.log(`${all ? 'SELF: 全绿' : 'SELF: 有红'}（变异 3 条 + 对照 2 条）`);
    process.exit(all ? 0 : 1);
}

const { rows, g, n } = scanTree();
console.log(`扫了 ${n} 个文档；最新且 ALL PASS 的冻结集 = ${g.name || '（没有）'}；判据 D1/D2/D3`);
if (argv.includes('--probe')) {
    for (const r of rows) console.log('  ' + r);
    console.log(`（probe：以上 ${rows.length} 条只报数，不判红）`);
    process.exit(0);
}
for (const r of rows.slice(0, 40)) console.log('  ' + r);
if (rows.length > 40) console.log(`  …另外 ${rows.length - 40} 条`);
console.log(rows.length ? `CURRENCY: ${rows.length} 条过期指路` : 'CURRENCY: 干净');
process.exit(rows.length ? 1 : 0);
