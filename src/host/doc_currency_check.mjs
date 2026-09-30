// src/host/doc_currency_check.mjs —— "文档不许把旧构建念成当前"
//
// 为什么要有它（这一轮撞了两次，都是同一类）：
//   * `docs/PERF_REPORT.md` 的"当前值看这里"指到 `CHANGELOG_V7.md`，而那份日志最后一节是
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
// 用法：node src/host/doc_currency_check.mjs [--self|--probe|--list-adv]
//   --self       判据自己的反例（三条各造一条坏输入 + 一条正当的过去式不许误报）
//   --probe      只报数不判红（用来先看口径会不会咬到正当的历史句）
//   --list-adv   把"只报数"那一半逐条打出来（#121：口径必须可复现，纯打印不参与退出码）
import { readFileSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..', '..');
const EXT = new Set(['.md', '.mjs', '.sh', '.ps1', '.tcl']);
// **只扫"念给人看的那一份"**：首页、板上操作卡、性能报告、构建说明、比赛清单、演示脚本、命令表。
// 为什么把 `docs/log/OVERNIGHT_LOG.md`、`docs/log/CHANGELOG_V7.md`、`docs/log/ISSUES.md`、
// `docs/log/VERSION_LINEAGE.md` 排除在 D1 之外——它们是**日记**，里面的"当前默认 #23""下一步冻结
// frozen_r61_geom"写的是**当时**的当前与当时的计划。拿今天的盘去判昨天的日记，红的不是文档过期，
// 而是我逼着自己回头改日记（那是销毁过程凭据，比过期更糟）。要改的永远是"现在还会被念出来"的那几页。
const SCOPE_DOCS = ['README.md', 'README.en.md', 'board/README.md',
    'docs/PERF_REPORT.md', 'docs/BUILD.md', 'docs/log/CONTEST_CHECKLIST.md',
    'docs/DEMO_SCRIPT.md', 'docs/COMMANDS.md', 'docs/BACKGROUND_AND_NOVELTY.md'];
// 会被复制粘贴去跑的脚本：里面的指路同样要成立。
const SCOPE_DIRS = ['build/tcl', 'src/host'];
const SKIP_DIR = new Set(['.git', 'vivado_system', 'xsim.dir', 'node_modules', '.Xil', 'dist']);
const HOME = ['README.md', 'README.en.md'];          // D3 只看首页这两份
const SELF = 'src/host/doc_currency_check.mjs';      // 判据不看自己的例子（例子里就得写坏句）
// 导出器是**故意**要写 `report/` 的：仓库里叫 docs/，交出去必须是官方结构里的 report/，
// 它的整个职责就是这两个名字之间的映射。拿"旧目录不许出现"去判它，等于判翻译器"不许提目标语言"。
const MAPPER = 'build/make_submission.sh';

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
        // 首页有两种**都算诚实**的写法：① 念"门禁全绿 = rNN"，那 rNN 必须等于盘上最新且 ALL PASS 的那一套；
        // ② 干脆不念版本号，明写"不作门禁全绿声明"，让读者自己去跑 `build/gates.sh`（交付件口吻用的就是这条）。
        // 两种都没有才算红 —— 因为"沉默"既可能是有意的（②），也可能是忘了（那就是 #88 那一类：门禁绿不绿没人说）。
        const txt = (docLines['README.md'] || []).join('\n');
        const neutral = /不作门禁全绿声明|no gate-green claim/i.test(txt);
        if (!home.some(c => c.at.startsWith('README.md')) && !neutral)
            rows.push(`README.md D3 首页既没有"门禁全绿 = rNN"（最新那一套是 r${newestGreen}），`
                + '也没有明写"不作门禁全绿声明" ⇒ 两种诚实写法至少要有一种');
        for (const c of home)
            if (c.nn !== newestGreen)
                rows.push(`${c.at} D3 首页念的是 r${c.nn}，盘上最新且 ALL PASS 的那一套是 r${newestGreen}`);
    }
    return rows;
}

// D4：文档与脚本里**点名的路径必须成立**（这一条是给"搬目录"这件事兜底的）。
//   2026-09-28 把 `report/` 拆成交付物（`docs/`）与工作记录（`docs/log/）时，全仓有四百来处指路；
//   搬一半留一半是这类活最坏的收场——文件都在，评审照文档去翻却翻到一个不存在的目录，
//   而这件事**不改变任何行为**：位流照编、台架照跑、门禁照绿。所以判据必须自己跑。
//   口径收得很窄，两种情形：
//     D4a 带目录前缀、以 .md 结尾、且不是占位名的指路 ⇒ 目标必须在盘上（`docs/*.md`、
//         `frozen_rNN_*` 这种带星号/占位名的写法天然不匹配，正当的命名规则句不会被咬）。
//     D4b `report/` 这个旧目录名后面直接跟文件名字符 ⇒ 一律红（旧目录已经不存在了；
//         "当年那个 report/ 目录"这种**叙事**（斜杠后是空格）不算指路，放过）。
//   日记（docs/log/*.md）也在扫描范围内：里面那句"见 `report/ISSUES.md`"曾经是历史叙述，
//   但既然指路已经全部改写，留着就是半搬 —— 所以一视同仁。
const CITE_MD = /(?:^|[^/\w.:-])(docs\/log|docs|build|src|sim|board|skill)\/[\w./-]*?[\w-]+\.md\b/g;
const OLD_DIR = /(?:^|[^/\w.-])report\/[\w.*-]/g;
//     D4c 与 D4a 同一条路，只是尾缀换成**凭据类**文件（.txt/.rpt/.csv/.bit/.elf/…）：
//         r88 那一轮连着三次栽在"文档指的那份报告在交付目录里不存在"，而 D4a 只认 `.md` ⇒
//         指路修完了、凭据没人管。凭据比章节更容易搬丢：导出器会把 `build/*.rpt|txt` 摊进
//         `build/reports/`、把 `build/rNN_exp/` 整个丢掉 ⇒ 同一句话在仓里对、在包里错。
const ART_EXT = 'txt|rpt|csv|bit|elf|md5|xdc|py|mjs|sh|tcl|v|bat|log|wdb';
const CITE_ART = new RegExp(
    '(?:^|[^/\\w.:-])(build|data|sim|board|skill|docs)/[\\w./-]*?[\\w-]+\\.(?:' + ART_EXT + ')\\b', 'g');

//   D4c 的**范围**是这条尺子能不能留下来的关键，所以写死并念出来：
//     判红只认"交付文档"（首页两份、board/README.md、docs/*.md 非 log 的那些）——
//     它们是评审会照着翻的指路。日记（docs/log/）、RTL/脚本注释里点名的很多是
//     **当时生成又随后删掉**的中间件（`build/wip_*.sh`、`sim/xsim.log`、某次的 `.log`），
//     把它们判红等于逼人去改历史记录（#98 那条老规矩）；这一类只报数、不判红。
//   #121 补的就是"只报数"那一半的分类（2026-09-30 实测 126 条，`--list-adv` 可逐条复现）：
//     按**出处**分：docs/log/ 的追加式日记 92 条、build/ 与 src/ 与 sim/ 与 board/ 的脚本注释 33 条、
//                  skill/ 卡片 1 条 —— **交付文档（DELIVERY）里 0 条**，这正是 hard 层的判据范围；
//     按**被点名的东西**分（类间有重叠）：
//       ① `.log` 31 条：`.gitignore` 从一开始就把 `*.log` 挡在仓库外（#172 的同一个洞的另一半 ⇒
//          冻结件必须叫 `.txt`），这些句子指的是"跑完这一步会生成什么"，不是"去看这份凭据"；
//       ② 旧轮次凭据 `build/rNN_*` 37 条：rNN 收尾后按清理规则删掉的中间件（日记写的是当时的事实）；
//       ③ `board/sd_*` 14 条：SD 坏点调查期间的诊断留痕，结案时随 #89/#123 一起清；
//       ④ KU5P 残名 9 条：2026-09-28 KU5P 那棵树整体删除（任务 #89），脚本与日记里的名字是历史；
//       ⑤ `build/isolated_*` 6 条：隔离滚的产物目录，同样按轮次清理；
//       ⑥ `build/evidence/` 5 条：这一类要留个心眼 —— 它是**该在盘上的凭据目录**，若哪天指路指向一个
//          从未生成过的文件名，就该是红的；今天这 5 条都是"当时存在、后被移动"的日记句。
//     判"能不能删/能不能改名"的依据由此而来：**出处在交付文档里 ⇒ 判红；出处在日记或注释里 ⇒ 只报数**。
//     谁要复核这条口径，跑 `--list-adv` 数一遍两类出处即可，不必信上面这些数。
//     剩下没被上面六类盖住的 24 条也各有归属：退役台架与 wip 脚本的名字（P2 那轮 sim/ 剔除 #108、
//     `build/wip_*.sh` 清理 #123 删掉的）、`board/uart_*` 系列的调查留痕（与③同族，只是文件名不含 sd_），
//     以及**历史叙述里那句"当时找错了路径"**（如 `ISSUES.md:435` 讲的 `build/build/system.bit` ——
//     它点名的是"root 少一级"这个已修缺陷，不是让人去打开这个文件）。
//     逐条身份（谁指谁、属哪一类）的表在 `docs/log/D4C_POINTERS.md`，那份表自带"条数只对快照那一分钟负责"的声明。
//     （它故意留在日记区：那页的内容就是"盘上不存在的路径"清单，放进交付区会被导出器的死链自检整批拒发
//       —— 2026-09-30 r96 真的踩到过一次：56 条死链全部出自那页，导出器拒绝写包，行为正确，我们不改自检。）
const DELIVERY = (rel) => HOME.includes(rel) || rel === 'board/README.md'
    || /^docs\/(?!log\/)[\w.-]+\.md$/.test(rel);

function checkPaths(fileLines, exists) {
    const rows = [];
    const adv = [];
    for (const [rel, lines] of Object.entries(fileLines)) {
        if (rel === SELF || rel === MAPPER) continue;      // 见上面两条豁免的理由
        const hard = DELIVERY(rel);
        lines.forEach((l, i) => {
            const at = `${rel}:${i + 1}`;
            for (const m of l.matchAll(CITE_MD)) {
                const tok = m[0].replace(/^[^a-z]/, '');
                if (tok.includes('NN') || tok.includes('$')) continue;
                if (exists(tok)) continue;
                const row = `${at} D4a 点名的文档盘上没有：${tok}`;
                if (hard) rows.push(row); else adv.push(row);
            }
            for (const m of l.matchAll(CITE_ART)) {
                const tok = m[0].replace(/^[^a-z]/, '');
                if (tok.includes('NN') || tok.includes('$') || tok.includes('*')) continue;
                if (exists(tok)) continue;
                const line = `${at} D4c 点名的凭据盘上没有：${tok}`;
                if (hard) rows.push(line); else adv.push(line);
            }
            for (const m of l.matchAll(OLD_DIR)) {
                rows.push(`${at} D4b 还在指已经删掉的旧目录：${l.trim().slice(0, 70)}`);
            }
        });
    }
    return { rows, adv };
}

const HAND_EXT = new Set(['.md', '.mjs', '.sh', '.tcl', '.v', '.c', '.h', '.bat', '.ps1', '.xdc', '.py', '.csv']);
// 不扫的：生成物与器件库、以及**当时的凭据**（冻结集里那份文本指的路就是它冻结时的那条路，
// 改它等于伪造记录），还有本地学习材料（docs/study/，不入库，里面引用的是另一套路径）。
const HAND_SKIP_DIRS = new Set(['.git', 'vivado_system', 'vitis', 'xsim.dir', 'sim_work',
    'node_modules', '.Xil', 'study', 'learn', 'golden', 'build']);
const HAND_SKIP_PREFIX = ['build/frozen_', 'build/evidence_', 'build/failed_', 'docs/study/'];

function handWrittenFiles(dir, out, relBase) {
    for (const name of readdirSync(dir)) {
        const rel = relBase ? `${relBase}/${name}` : name;
        if (HAND_SKIP_DIRS.has(name) && rel !== 'build') continue;
        if (name === 'build') { handWrittenFiles(path.join(dir, name), out, rel); continue; }
        if (HAND_SKIP_PREFIX.some(p => (rel + '/').startsWith(p))) continue;
        const p = path.join(dir, name);
        const st = statSync(p);
        if (st.isDirectory()) handWrittenFiles(p, out, rel);
        else if (HAND_EXT.has(path.extname(name).toLowerCase())) out.push(rel);
    }
    return out;
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
    // D4 的扫描面比 D1/D2/D3 宽得多：凡是"人会抄去跑"的手写文件都算（.v/.c 里的注释也在内，
    // 因为那些注释就是"下一版该去看哪一份"的指路）。
    const allFiles = {};
    try {
        for (const rel of handWrittenFiles(ROOT, [], '')) {
            try { allFiles[rel] = readFileSync(path.join(ROOT, rel), 'utf8').split('\n'); }
            catch { /* 单个文件读不到就跳过，缺文件另有 D 项管 */ }
        }
    } catch { /* 整棵树读不到就只跑 D1/D2/D3 */ }
    const exists = (tok) => {
        try { return statSync(path.join(ROOT, tok)).isFile(); } catch { return false; }
    };
    const p = checkPaths(allFiles, exists);
    const nd = Object.keys(allFiles).filter(DELIVERY).length;
    return { rows: checkLines(docs, has, g.nn).concat(p.rows), adv: p.adv, nd,
        g, n: Object.keys(docs).length, m: Object.keys(allFiles).length };
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
        'docs/log/CHANGELOG_V6.md': ['第四版得到 WNS +0.708 / 寄存器 51.30%（`build/frozen_r13`）'],
        'README.md': ['最近一次门禁全绿的冻结集 = r71：WNS +0.346'],
    }, okDir, 71);
    console.log(`  ${good.length === 0 ? 'PASS' : 'FAIL'} 对照：过去式与点名最新全绿的那一套都不误报（实测 ${good.length} 条）`);
    for (const r of good) console.log('        ' + r);
    // 两个"别咬到正当文本"的边界：命名规则里的占位名、以及**带路径前缀**的那一种（不是仓库根的 build/）。
    const edges = checkLines({
        'docs/BUILD.md': ['冻结目录命名规则：`build/frozen_rNN_xxx/`（NN 是那一次构建的编号）',
            '备份包里的 `submission/build/frozen_r26/` 是复制品，不拿工作区判它存在与否'],
    }, () => false, 0);
    console.log(`  ${edges.length === 0 ? 'PASS' : 'FAIL'} 对照：占位名与带前缀的路径不误报（实测 ${edges.length} 条）`);
    for (const r of edges) console.log('        ' + r);
    // D3 的另一种诚实写法（首页明写"不作门禁全绿声明"）必须**不判红**；
    // 而"既没有 rNN 也没有这句话"仍然是红 —— 上面那条变异用例管的就是后者。
    const neutral = checkLines({ 'README.md': ['**本页不作门禁全绿声明**：以 `bash build/gates.sh` 打印的那一行为准。'] },
        okDir, 71).filter(r => /D3/.test(r));
    console.log(`  ${neutral.length === 0 ? 'PASS' : 'FAIL'} 对照：首页明写"不作门禁全绿声明"不误报 D3（实测 ${neutral.length} 条）`);
    for (const r of neutral) console.log('        ' + r);
    // D4 自己的反例：一条"点名的文档盘上没有"、一条"还在指已经删掉的旧目录"，两条都必须红；
    // 再加一条正当句（真的在盘上的 `docs/COMMANDS.md` + 一个占位名 `frozen_rNN_x`）不许红。
    const d4bad = checkPaths({ 'docs/ARCHITECTURE.md': ['详见 `docs/NO_SUCH_DOC.md` 的 §2'], }, () => false).rows;
    const d4old = checkPaths({ 'src/rtl/top/pl_video_top.v': ['// 口径见 `report/ISSUES.md` #66'], }, () => true).rows;
    const d4ok = checkPaths({ 'README.md': ['详见 `docs/COMMANDS.md`；凭据在 `build/frozen_rNN_x/`；',
        '当年那个 report/ 目录已经拆成 docs/ 与 docs/log/（这是叙事，不是指路）'], },
        (tok) => tok === 'docs/COMMANDS.md').rows;
    // D4c 的反例：点名一份盘上没有的报告必须红；对照是"通配/占位/变量"三种写法都不许咬
    // ——门禁那一句 `build/*gates*.txt` 是命名规则，不是指路（`build/gates.sh` 本身在盘上）。
    const d4art = checkPaths({ 'docs/PERF_REPORT.md': ['门禁读数见 `build/r99_gates_nope.txt`'], }, () => false).rows;
    const d4artok = checkPaths({ 'README.md': ['跑 `bash build/gates.sh`，认 `build/*gates*.txt` 里编号最大且',
        '`ALL PASS` 的那一份；`$OUT/build/system.bit` 由脚本决定；`build/frozen_rNN/MANIFEST.md5` 是命名规则'], },
        (tok) => tok === 'build/gates.sh').rows;
    // 范围对照（#141 那一类：尺子的作用范围会无声漂移）：同一句指路写在日记里**不许判红**，
    // 但必须进"只报数"那一堆 —— 两边都查，缺一边就是范围漂了。
    const sp = checkPaths({ 'docs/log/OVERNIGHT_LOG.md': ['当时那份 `build/r99_gates_nope.txt` 已经删了',
        '那份简介 `docs/PROJECT_BRIEF_NOPE.md` 后来也撤了'], }, () => false);
    const scope = sp.rows.length === 0 && sp.adv.length === 2;
    console.log(`  ${scope ? 'PASS' : 'FAIL'} 对照：同一句指路（.txt 与 .md 各一）在日记里只报数（判红 ${sp.rows.length} / 报数 ${sp.adv.length}）`);
    let d4 = 0;
    d4 += yes('D4a：点名的文档盘上没有', d4bad, /D4a/);
    d4 += yes('D4b：还在指旧目录 report/', d4old, /D4b/);
    d4 += yes('D4c：点名的凭据（.txt/.rpt/…）盘上没有', d4art, /D4c/);
    console.log(`  ${d4ok.length === 0 ? 'PASS' : 'FAIL'} 对照：真指路 + 占位名 + "旧目录"的叙事句不误报（实测 ${d4ok.length} 条）`);
    for (const r of d4ok) console.log('        ' + r);
    console.log(`  ${d4artok.length === 0 ? 'PASS' : 'FAIL'} 对照：通配/变量/占位名的凭据写法不误报（实测 ${d4artok.length} 条）`);
    for (const r of d4artok) console.log('        ' + r);

    const all = n === 3 && good.length === 0 && edges.length === 0 && d4 === 3
        && d4ok.length === 0 && d4artok.length === 0 && scope && neutral.length === 0;
    console.log(`${all ? 'SELF: 全绿' : 'SELF: 有红'}（变异 ${n} + D4 变异 ${d4} 条 + 对照 ${good.length + edges.length + d4ok.length + d4artok.length} 条，范围对照${scope ? '过' : '不过'}）`);
    process.exit(all ? 0 : 1);
}

const { rows, adv, nd, g, n, m } = scanTree();
console.log(`扫了 ${n} 个文档（D1/D2/D3）+ ${m} 个手写文件（D4）；最新且 ALL PASS 的冻结集 = ${g.name || '（没有）'}`);
// `--list-adv`：把"只报数不判红"那一半逐条打出来（#121：口径必须能说清，不能只留一句"不算指路错误"）。
// 纯打印，不参与退出码，也不改任何判据 —— 判据的红绿仍由 rows/hard 决定。
if (argv.includes('--list-adv')) {
    for (const a of adv) console.log('  ADV ' + a);
    console.log(`（adv ${adv.length} 条：以上只报数，不参与退出码）`);
    process.exit(0);
}
if (argv.includes('--probe')) {
    for (const r of rows) console.log('  ' + r);
    console.log(`（probe：以上 ${rows.length} 条只报数，不判红）`);
    process.exit(0);
}
for (const r of rows.slice(0, 40)) console.log('  ' + r);
if (rows.length > 40) console.log(`  …另外 ${rows.length - 40} 条`);
console.log(`D4c 范围：交付文档 ${nd} 份判红；其余 ${m - nd} 份点名凭据 ${adv.length} 条只报数`
    + '（日记与注释里那些"当时存在、随后删掉"的中间件不算指路错误 —— 见脚本头部）');
console.log(rows.length ? `CURRENCY: ${rows.length} 条过期指路` : 'CURRENCY: 干净');
process.exit(rows.length ? 1 : 0);
