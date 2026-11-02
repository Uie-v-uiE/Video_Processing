// 用途："文档不许把旧构建念成当前"
// 输入：命令行参数
// 输出：stdout
// 退出码：0=跑完
// src/host/doc_currency_check.mjs —— "文档不许把旧构建念成当前"
//
// 为什么要有它（这一轮撞了两次，都是同一类）：
//   * `report/perf_report.md` 的"当前值看这里"指到 `changelog_v7.md`，而那份日志最后一节是
//     V7.9（R22+R23）——照它念会念到五十多版之前。
//   * `README.md` / `README_EN.md` 的实现结果行一直写着 `当前默认 bit（build#23）：WNS +0.740 …`，
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
//   D3 首页（README.md / README_EN.md）里"门禁全绿 = rNN"这一句点名的那一套，必须等于
//      `build/*gates*.txt` 里**编号最大且写着 GATES: ALL PASS** 的那一套；并且 README.md 里
//      至少要有这么一句（没有就等于没说）。⇒ 下一次冻结成功时，这一条会自己变红，逼着改首页。
//
// 用法：node src/host/doc_currency_check.mjs [--self|--probe|--list-adv]
//   --self       判据自己的反例（三条各造一条坏输入 + 一条正当的过去式不许误报）
//   --probe      只报数不判红（用来先看口径会不会咬到正当的历史句）
//   --list-adv   把"只报数"那一半逐条打出来（#121：口径必须可复现，纯打印不参与退出码）
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';

const ROOT = path.resolve(import.meta.dirname, '..', '..');
const EXT = new Set(['.md', '.mjs', '.sh', '.ps1', '.tcl']);
// **只扫"念给人看的那一份"**：首页、板上操作卡、性能报告、构建说明、比赛清单、演示脚本、命令表。
// 为什么把 `report/log/overnight_log.md`、`report/log/changelog_v7.md`、`report/log/issues.md`、
// `report/log/version_lineage.md` 排除在 D1 之外——它们是**日记**，里面的"当前默认 #23""下一步冻结
// frozen_r61_geom"写的是**当时**的当前与当时的计划。拿今天的盘去判昨天的日记，红的不是文档过期，
// 而是我逼着自己回头改日记（那是销毁过程凭据，比过期更糟）。要改的永远是"现在还会被念出来"的那几页。
const SCOPE_DOCS = ['README.md', 'README_EN.md', 'board/README.md',
    'report/perf_report.md', 'report/build.md', 'report/log/contest_checklist.md',
    'report/demo_script.md', 'report/commands.md', 'report/background_and_novelty.md'];
// 会被复制粘贴去跑的脚本：里面的指路同样要成立。
const SCOPE_DIRS = ['build/tcl', 'src/host'];
const SKIP_DIR = new Set(['.git', 'vivado_system', 'xsim.dir', 'node_modules', '.Xil', 'dist']);
const HOME = ['README.md', 'README_EN.md'];          // D3 只看首页这两份
const SELF = 'src/host/doc_currency_check.mjs';      // 判据不看自己的例子（例子里就得写坏句）
// 导出器是**故意**要写 `report/` 的：仓库里叫 report/，交出去必须是官方结构里的 report/，
// 它的整个职责就是这两个名字之间的映射。拿"旧目录不许出现"去判它，等于判翻译器"不许提目标语言"。
const MAPPER = 'build/make_submission.sh';
// 改名工具也是"翻译器"：它的正文里必然同时出现旧名与新名（`git mv report/log report/log` 这种就是要它写出来）。
// 2026-09-30 今晚把 report/ 改成 report/ 时，这两份新工具第一次被 D4b 判了 6 条红 —— 判据没有错，
// 被豁免的对象名单少了一类：**凡是以"改名字"为职责的脚本，都在 MAPPER 这一族里**。
const MAPPERS = [MAPPER, 'build/rename_docs_to_report.sh', 'build/rename_tool_patch.mjs'];

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
// 目录名里必须有真实编号：`frozen_rNN_…`（build.md 讲的是命名规则）与光秃秃的 `frozen_r`（glob）都不算引用。
function citable(tok) { return /_r\d{2,}(_|$)/.test(tok) && !tok.includes('NN'); }

// 纯函数：把"文件名 → 行"喂进来就能判，--self 因此不必真去改盘上的文件。
// `dirExists(tok)`：点名 `frozen_r23` 而盘上是 `frozen_r23_srcseen` 也算对上（文档里常省略后缀），
// 但一个编号都没有的（`frozen_r26`）就必须整名对上——省掉后缀只到"同一版"为止，不能跨省。
function checkLines(docLines, dirExists, newestGreen) {
    const rows = [];
    const claims = [];
    for (const [rel, lines] of Object.entries(docLines)) {
        if (rel === SELF || MAPPERS.includes(rel)) continue;
        lines.forEach((l, i) => {
            const at = `${rel}:${i + 1}`;
            if (NOW.test(l) && NUM.test(l))
                rows.push(`${at} D1 把带编号的旧构建说成"当前/默认"：${l.trim().slice(0, 80)}`);
            for (const m of l.matchAll(CITED)) {
                const tok = m[2];
                // 占位/变量写法不咬（与 D4a/D4c 同一条豁免，#121 当年给 D4 补的那条这里一直缺着）：
                // `build/evidence_rNN` 是命名规则、不是指路——`bash build/gates.sh build/evidence_rNN`
                // 这种示例行若被咬红，下一轮就会被逼成"把示例改成真实轮号"那种假动作。
                if (/NN|\$/.test(tok)) continue;
                if (citable(tok) && !dirExists(tok)) {
                    const r = `${at} D2 点名的目录盘上没有：build/${tok}`;
                    if (noShip(l)) { nNOSHIP++; } else { rows.push(r); }
                }
            }
            const g = l.match(GREEN);
            if (g && HOME.includes(rel)) claims.push({ at, nn: Number(g[2]) });
        });
    }
    if (newestGreen > 0) {
        const home = claims.filter(c => c.at.startsWith('README.md') || c.at.startsWith('README_EN.md'));
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
//     D4a 带目录前缀、以 .md 结尾、且不是占位名的指路 ⇒ 目标必须在盘上（`report/*.md`、
//         `frozen_rNN_*` 这种带星号/占位名的写法天然不匹配，正当的命名规则句不会被咬）。
//     D4b `report/` 这个旧目录名后面直接跟文件名字符 ⇒ 一律红（旧目录已经不存在了；
//         "当年那个 report/ 目录"这种**叙事**（斜杠后是空格）不算指路，放过）。
//   日记（docs/log/*.md）也在扫描范围内：里面那句"见 `report/issues.md`"曾经是历史叙述，
//   但既然指路已经全部改写，留着就是半搬 —— 所以一视同仁。
const CITE_MD = /(?:^|[^/\w.:-])(report\/log|report|build|src|sim|board|skill)\/[\w./-]*?[\w-]+\.md\b/g;
const OLD_DIR = /(?:^|[^/\w.-])docs\/[\w.*-]/g;
//     D4c 与 D4a 同一条路，只是尾缀换成**凭据类**文件（.txt/.rpt/.csv/.bit/.elf/…）：
//         r88 那一轮连着三次栽在"文档指的那份报告在交付目录里不存在"，而 D4a 只认 `.md` ⇒
//         指路修完了、凭据没人管。凭据比章节更容易搬丢：导出器会把 `build/*.rpt|txt` 摊进
//         `build/reports/`、把 `build/rNN_exp/` 整个丢掉 ⇒ 同一句话在仓里对、在包里错。
const ART_EXT = 'txt|rpt|csv|bit|elf|md5|xdc|py|mjs|sh|tcl|v|bat|log|wdb';
// 尾缀可以再跟一段扩展名（**2026-10-05 补**）：`build/parsed/parsed_cdc.rpt.json` 与
// `board/firmware/ps_app.elf.md` 都是**真实存在的跟踪件**，而旧写法在第一个凭据扩展名处就收口
// （`.rpt` 后面是 `.` ⇒ `\b` 成立），于是拿"少了 `.json` 的那个名字"去查盘 ⇒ 查不到 ⇒ 判红。
// 这是尺子的**射程维度**错了，不是文档错了：整批 9 条 `build/parsed/` 与 2 条 `board/firmware/*.md`
// 都属这一类。现在把尾巴吃全，查的就是行面上那一个完整文件名。
const CITE_ART = new RegExp(
    '(?:^|[^/\\w.:-])(build|data|sim|board|skill|report)/[\\w./-]*?[\\w-]+\\.(?:' + ART_EXT + ')'
    + '(?:\\.(?:json|txt|rpt|csv|md|log|html))*(?:\\b|$)', 'g');

//   D4c 的**范围**是这条尺子能不能留下来的关键，所以写死并念出来：
//     判红只认"交付文档"（首页两份、board/README.md、report/*.md 非 log 的那些）——
//     它们是评审会照着翻的指路。日记（report/log/）、RTL/脚本注释里点名的很多是
//     **当时生成又随后删掉**的中间件（`build/wip_*.sh`、`sim/xsim.log`、某次的 `.log`），
//     把它们判红等于逼人去改历史记录（#98 那条老规矩）；这一类只报数、不判红。
//   #121 补的就是"只报数"那一半的分类（2026-09-30 实测 126 条，`--list-adv` 可逐条复现）：
//     按**出处**分：report/log/ 的追加式日记 92 条、build/ 与 src/ 与 sim/ 与 board/ 的脚本注释 33 条、
//                  skills/ 卡片 1 条 —— **交付文档（DELIVERY）里 0 条**，这正是 hard 层的判据范围；
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
//     以及**历史叙述里那句"当时找错了路径"**（如 `issues.md:435` 讲的 `build/board/project/system.bit` ——
//     它点名的是"root 少一级"这个已修缺陷，不是让人去打开这个文件）。
//     逐条身份（谁指谁、属哪一类）的表在 `report/log/d4c_pointers.md`，那份表自带"条数只对快照那一分钟负责"的声明。
//     （它故意留在日记区：那页的内容就是"盘上不存在的路径"清单，放进交付区会被导出器的死链自检整批拒发
//       —— 2026-09-30 r96 真的踩到过一次：56 条死链全部出自那页，导出器拒绝写包，行为正确，我们不改自检。）
const DELIVERY = (rel) => HOME.includes(rel) || rel === 'board/README.md'
    || /^report\/(?!log\/)[\w.-]+\.md$/.test(rel);

// #222 的路由二：**同一行自带"这件东西故意不随包"的声明**时，D2/D4a/D4c/D4b 把它降级为"只报数"。
// 为什么必须有这条豁免：交付文档会点两件真实存在、但**按设计不进口**的东西——
//   ① `board/uart_script_capture.txt`（`uart_cap_once.ps1`/`board_verify.sh` 每次重写的本机捕获，
//      被 `.gitignore` 挡住；随包的是它的被跟踪替身 `build/evidence/rNN_serial_raw.txt`），
//   ② 仓库里的历史冻结集目录（`build/frozen_rNN_*`，包内只带被采纳的那一份报告）。
// 不豁免的两种代价都更坏：要么把真话从文档里删掉（#122 警告过的那种"改文档迁就尺子"），
// 要么让包里那把尺子永远红着（评审看到的就只剩"红"这一个信号）。
// ⚠ 豁免的形状是**写死的短表**，并且必须与指路 token **同一行**——买通它的唯一办法是当着读者写下
//   "这东西不随包"，而那句话本身就是给人核对的真话；放行条数会打印出来，不许静默吞掉（#217 同族）。
// 2026-10-05 增两词：'不入库'、'本地留档' 取自导出器死链自检的词表（`build/make_submission.sh`
// 的 `SKIP_RE`），与 '不随包' 同一类意思。两把尺子各写一套话术会出现"导出器放行、这把还红"
// （#222 同族）。词表仍以**同一行**为唯一买通途径，放行条数照打。
const NOSHIP_MARK = ['不随包', '不在本包内', '已被 `.gitignore` 挡住', '不入库', '本地留档'];
const noShip = (l) => NOSHIP_MARK.some((k) => l.includes(k));
let nNOSHIP = 0;
// 围栏里是**工具原文回显**（例：`RESULT PASS uart_cmd_check (… 捕获 board/uart_script_capture.txt)`）。
// 作者不能往别人打印的那一行里塞声明，改抄件＝伪造记录 ⇒ 围栏内的 D4c（凭据存在性）降级为只报数，
// 条数打印成 nFENCE。D4b（旧目录名）与 D4a（文档落点）在围栏里**照旧判红**：照抄的命令踩进旧目录
// 或指到不存在的章节，是评审真会撞上的坑。--self 有一对钉住这件事：同一条写在围栏外必须红。
let nFENCE = 0;

function checkPaths(fileLines, exists) {
    const rows = [];
    const adv = [];
    for (const [rel, lines] of Object.entries(fileLines)) {
        if (rel === SELF || MAPPERS.includes(rel)) continue;      // 见上面几条豁免的理由
        const hard = DELIVERY(rel);
        let inFence = false;
        lines.forEach((l, i) => {
            if (/^\s*(?:`{3,}|~{3,})/.test(l)) { inFence = !inFence; return; }
            const at = `${rel}:${i + 1}`;
            const ns = noShip(l);                     // 这一行自带"不随包"声明吗（见 NOSHIP_MARK 那段）
            const put = (r) => {
                if (!hard) { adv.push(r); return; }
                if (ns) { nNOSHIP++; adv.push(r + '（同行已声明不随包 ⇒ 只报数）'); } else rows.push(r);
            };
            for (const m of l.matchAll(CITE_MD)) {
                const tok = m[0].replace(/^[^a-z]/, '');
                if (tok.includes('NN') || tok.includes('$')) continue;
                if (exists(tok)) continue;
                put(`${at} D4a 点名的文档盘上没有：${tok}`);
            }
            for (const m of l.matchAll(CITE_ART)) {
                const tok = m[0].replace(/^[^a-z]/, '');
                if (tok.includes('NN') || tok.includes('$') || tok.includes('*')) continue;
                if (exists(tok)) continue;
                if (inFence) { nFENCE++; adv.push(`${at} D4c 围栏内原文回显 ⇒ 只报数：${tok}`); continue; }
                put(`${at} D4c 点名的凭据盘上没有：${tok}`);
            }
            for (const m of l.matchAll(OLD_DIR)) {
                put(`${at} D4b 还在指已经删掉的旧目录：${l.trim().slice(0, 70)}`);
            }
        });
    }
    return { rows, adv };
}

const HAND_EXT = new Set(['.md', '.mjs', '.sh', '.tcl', '.v', '.c', '.h', '.bat', '.ps1', '.xdc', '.py', '.csv']);
// 不扫的：生成物与器件库、以及**当时的凭据**（冻结集里那份文本指的路就是它冻结时的那条路，
// 改它等于伪造记录），还有本地学习材料（report/study/，不入库，里面引用的是另一套路径）。
const HAND_SKIP_DIRS = new Set(['.git', 'vivado_system', 'vitis', 'xsim.dir', 'sim_work',
    'node_modules', '.Xil', 'study', 'learn', 'golden', 'build']);
const HAND_SKIP_PREFIX = ['build/frozen_', 'build/evidence_', 'build/failed_', 'report/study/'];

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
// ---- D1b：把"板上现在跑哪一轮"这句话念回**盘上的产物**（#221 的由来；起因是一句"现在是 r80"）----
// 基准的来历不是另一句文案，而是 `board/project/system.bit` 的 md5 → 哪一份 `build/rNN_gates.txt` 戳了同一个 md5
// （那一份是门禁件自己写的"身份："段，见 `build/gates.sh`）。
// ⚠ 基准**不能**复用 D3 的"最新且 ALL PASS 的冻结集"：本仓冻结停在 r75，而板上跑的是被采纳的 r104——
//   采纳与冻结本来就是两件事（`report/known_issues.md` §20），拿冻结集当"现在"会把每一句诚实的话集体误报。
// 形状要**相邻**：只说"这行里出现了 现在 也出现了 rNN"不够——正当的历史句长这样：
// "写这一节那天（2026-09-26）板上是 r80…板上现在跑哪一轮请看 README"，那句"现在"后面跟的是"跑哪一轮"
// 而不是编号；相邻判据不咬它，而"现在是 r80"咬得住。
const NOW_MARK = /(板上这一[套版]|板上现在|现在跑的是|当前跑的|the board (?:now )?runs|board currently)/i;
const ADJ_RNN = /^\s*(?:现在|当前)?\s*(?:是|为|跑的是|=|:)?\s*[（(]?\s*r(\d{2,3})/i;
function currentBoardRound() {
    let h = '';
    try { h = createHash('md5').update(readFileSync(path.join(ROOT, 'build', 'system.bit'))).digest('hex').slice(0, 12); }
    catch {
        // 分两种：**这棵树根本没有 bit 产物**（提交包就是这样：二进制不随包）⇒ 这一层不可判，明说而不是判红；
        // 而在仓库里（bit 在、却没有一份门禁件戳它）才是"基准读不到"，必须红——门禁在仓库里跑，牙留在那边。
        const noBit = !existsSync(path.join(ROOT, 'build', 'system.bit'));
        return { nn: 0, why: noBit ? '本目录没有 board/project/system.bit（多半是提交包，不是仓库）' : '读不到 board/project/system.bit', absent: noBit };
    }
    let best = 0, name = '';
    for (const f of readdirSync(path.join(ROOT, 'build'))) {
        if (!/^r\d+_gates\.txt$/.test(f)) continue;
        let t;
        try { t = readFileSync(path.join(ROOT, 'build', f), 'utf8'); } catch { continue; }
        if (!t.includes('system.bit md5=' + h)) continue;
        const nn = Number(f.match(/^r(\d+)/)[1]);
        if (nn > best) { best = nn; name = f; }
    }
    return best ? { nn: best, name, bit: h } : { nn: 0, bit: h, why: '没有一份 rNN_gates.txt 戳着这块 bit' };
}
// D1b 的扫描面**单独一份**：日记类（report/log/）与两份过程台账（KNOWN_ISSUES / OPTIMIZATION_LOG）不进——
// 那里成片的"板上已是这一版（rNN）"是带日期的凭据，把它们咬红等于逼人回去改凭据（D4c 那轮划过的同一条边界）。
const D1B_DOCS = ['README.md', 'README_EN.md', 'board/README.md', 'report/perf_report.md',
    'report/build.md', 'report/demo_script.md', 'report/commands.md', 'report/background_and_novelty.md',
    'report/ai_collaboration.md', 'report/llm_collab.md', 'report/architecture.md', 'report/host_guide.md'];
function d1bScan(docs, cur) {
    const rows = [];
    let claims = 0;
    for (const rel of D1B_DOCS) {
        const lines = docs[rel];
        if (!lines) continue;
        lines.forEach((l, i) => {
            const m = l.match(NOW_MARK);
            if (!m) return;
            const g = l.slice(m.index + m[0].length).match(ADJ_RNN);
            if (!g) return;                                  // 有标记但相邻处没编号：多半是"跑哪一轮请看…"那种指路句
            claims++;
            const nn = Number(g[1]);
            if (cur.nn > 0 && nn !== cur.nn)
                rows.push(`${rel}:${i + 1} D1b 说板上现在跑的是 r${nn}，而这块 bit（md5 ${cur.bit}）的门禁身份行指向 r${cur.nn}（${cur.name}）：${l.trim().slice(0, 64)}`);
        });
    }
    return { rows, claims };
}

// ---- D1c：首页/交付文档里那句"门禁 N 项 X 绿 / Y 红"必须对回**那一轮的门禁件本身**（#224 同族）----
// 为什么单独一层：D1b 只判"板上现在跑哪一轮"这个**轮号**，D6 只判**报告里的数**；
// 而"门禁 22 项 21 绿 / 1 红"这句既不在 timing_summary 里、也不是轮号，谁都管不到 ——
// 它偏偏是讲稿里会被念出来的一句。基准 = D1b 已经认出来的那一份 `build/rNN_gates.txt`
// （由 `board/project/system.bit` 的 md5 反查得到），读法是"行尾那个字段"，不是 grep 全文
// （同一行里 `FAIL行=0` 这种测量列会被 grep 数成红项——这仓库栽过第六次的那一族）。
// 只判**相邻**的那句：这一句里出现当前轮号、或带"板上这一版/现在"这类现在时标记；
// 否则算历史句（"写那一节那天板上是 r80…"），只数不判。
const GATES_CLAIM = /门禁\s*(\d{1,3})\s*项\s*(\d{1,3})\s*绿\s*\/\s*(\d{1,3})\s*红|the\s+(\d{1,3})-item gate check reads\s+(\d{1,3})\s+green\s*\/\s*(\d{1,3})\s+red/g;
function gatesTally(text) {
    const ls = String(text).replace(/\r/g, '').split('\n');
    let pass = 0, fail = 0, judged = 0, passOther = 0, failOther = 0, self = 'absent';
    for (const l of ls) {
        const t = l.trim().split(/\s+/).pop();
        const ok = t === 'PASS', bad = t === 'FAIL';
        if (!ok && !bad) continue;
        // #229：这一项自己就是被这句话描述的对象之一。把"文档时效"那一格算进绿/红数，
        // 这句话就有**两个自洽解**（21 绿/1 红 与 20 绿/2 红 互推彼此），连着跑两次会在两者之间跳。
        // 所以判据改成按"除本项外"的读数 + 本项假定为绿（唯一自洽点）；本项若因别的行而红，
        // 编码/行号/数字对账各自是**独立的门禁项**（第 19/20/21 项），不会在这里被藏住。
        const isSelf = /文档时效|doc_cur/.test(l);
        if (isSelf) { self = ok ? 'pass' : 'fail'; continue; }
        if (ok) { pass++; passOther++; } else { fail++; failOther++; }
    }
    const v = ls.map((l) => l.match(/判定\s*(\d+)\s*项/)).find((m) => m);
    if (v) judged = Number(v[1]);
    return { pass, fail, judged, passOther, failOther, self };
}
function d1cBasis(t) {
    return { judged: t.judged, pass: t.passOther + 1, fail: t.failOther };
}
function d1cScan(docs, cur, tally) {
    const rows = [];
    let claims = 0, skipped = 0;
    if (!tally || !tally.judged) return { rows, claims, skipped };
    for (const rel of D1B_DOCS) {
        const lines = docs[rel];
        if (!lines) continue;
        lines.forEach((l, i) => {
            for (const m of l.matchAll(GATES_CLAIM)) {
                // 一个正则两组分支：命中哪一组就取哪三个捕获（前三个属于中文式，后三个属于英文式）
                const items = m[1] || m[4], g = m[2] || m[5], r = m[3] || m[6];
                claims++;
                const adj = new RegExp('r' + cur.nn + '\\b').test(l) || NOW_MARK.test(l);
                if (!adj) { skipped++; continue; }
                const b = d1cBasis(tally), bad = [];
                if (Number(items) !== b.judged) bad.push(`判定项数首页=${items} 门禁件=${b.judged}`);
                if (Number(items) !== Number(g) + Number(r)) bad.push(`首页自相矛盾=${g}+${r}≠${items}`);
                if (Number(g) !== b.pass) bad.push(`绿首页=${g} 基准=${b.pass}（除本项外的 ${tally.passOther} 格 + 本项按绿算）`);
                if (Number(r) !== b.fail) bad.push(`红首页=${r} 基准=${b.fail}`);
                if (bad.length)
                    rows.push(`${rel}:${i + 1} D1c 那句门禁读数与 ${cur.name} 对不上（${bad.join('；')}）：${l.trim().slice(0, 60)}`);
            }
        });
    }
    // 射程地板（规矩 46 那一族）：基准件读到了、却一句都没抓到 ⇒ 这一层在空转，不是"没有可判的"。
    // 首页那一行必然写着"门禁 N 项 X 绿 / Y 红"，形状变了就该由这里说"这一层没接上"，
    // 而不是安静地报 0 条——"0 条"与"根本没跑"在输出上长得一模一样。
    if (tally && tally.judged && claims === 0)
        rows.push(`D1c 空转：基准件 ${cur.name} 读到了（判定 ${tally.judged} 项），但 12 份交付文档里一句"门禁 N 项 X 绿 / Y 红"都没抓到 ⇒ 那行的形状变了，这一层没接上`);
    return { rows, claims, skipped };
}

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
    // D1b：读基准（bit 的身份）→ 扫那 12 份交付文档里的"板态身份句"
    const d1bDocs = {};
    for (const rel of D1B_DOCS) {
        try { d1bDocs[rel] = readFileSync(path.join(ROOT, rel), 'utf8').split('\n'); }
        catch { /* 缺文件由 D4b 那一条管，这一层不重复报 */ }
    }
    const cur = currentBoardRound();
    const b = d1bScan(d1bDocs, cur);
    // 提交包里没有二进制（`board/project/system.bit` 不存在）⇒ 这一层**不可判**，明写在汇总里而不是判红；
    // 仓库里（bit 在、却没有门禁件戳它）仍然是红——牙留在门禁跑的那一侧。
    const brows = (cur.nn > 0 || cur.absent) ? b.rows
        : [`D1b 判不了：${cur.why}（bit md5=${cur.bit || '读不到'}）⇒ 板态身份句这一层没有基准，不许念成绿的`];
    // D1c：同一份基准件（那一轮的门禁清单）再念一句"门禁 N 项 X 绿 / Y 红"对不对得上。
    // 基准读不到（提交包没有 bit，或仓库里 bit 没有门禁件戳它）⇒ 这一层与 D1b 同进同退，不判也不假绿。
    let tally = null, c = { rows: [], claims: 0, skipped: 0 };
    if (cur.nn > 0) {
        try { tally = gatesTally(readFileSync(path.join(ROOT, 'build', cur.name), 'utf8')); }
        catch { tally = null; }
        c = d1cScan(d1bDocs, cur, tally);
    }
    const crows = (cur.nn > 0 && tally) ? c.rows
        : (cur.absent ? [] : ['D1c 判不了：基准门禁件读不到（' + (cur.why || '没有 ' + (cur.name || 'rNN_gates.txt')) + '）⇒ 那句"N 项 X 绿 / Y 红"没有凭据可比']);
    return { rows: checkLines(docs, has, g.nn).concat(p.rows, brows, crows), adv: p.adv, nd,
        g, n: Object.keys(docs).length, m: Object.keys(allFiles).length,
        d1b: { claims: b.claims, cur, docs: Object.keys(d1bDocs).length },
        d1c: { claims: c.claims, skipped: c.skipped, tally, file: cur.name || '' } };
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
        'report/log/changelog_v6.md': ['第四版得到 WNS +0.708 / 寄存器 51.30%（`build/frozen_r13`）'],
        'README.md': ['最近一次门禁全绿的冻结集 = r71：WNS +0.346'],
    }, okDir, 71);
    console.log(`  ${good.length === 0 ? 'PASS' : 'FAIL'} 对照：过去式与点名最新全绿的那一套都不误报（实测 ${good.length} 条）`);
    for (const r of good) console.log('        ' + r);
    // 两个"别咬到正当文本"的边界：命名规则里的占位名、以及**带路径前缀**的那一种（不是仓库根的 build/）。
    const edges = checkLines({
        'report/build.md': ['冻结目录命名规则：`build/frozen_rNN_xxx/`（NN 是那一次构建的编号）',
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
    // 再加一条正当句（真的在盘上的 `report/commands.md` + 一个占位名 `frozen_rNN_x`）不许红。
    const d4bad = checkPaths({ 'report/architecture.md': ['详见 `report/NO_SUCH_DOC.md` 的 §2'], }, () => false).rows;
    const d4old = checkPaths({ 'report/architecture.md': ['// 口径见 `docs/issues.md` #66'], }, () => true).rows;
    const d4ok = checkPaths({ 'README.md': ['详见 `report/commands.md`；凭据在 `build/frozen_rNN_x/`；',
        '当年那个 report/ 目录已经拆成 docs/  与 docs/ log/（这是叙事，不是指路）'], },
        (tok) => tok === 'report/commands.md').rows;
    // D4c 的反例：点名一份盘上没有的报告必须红；对照是"通配/占位/变量"三种写法都不许咬
    // ——门禁那一句 `build/*gates*.txt` 是命名规则，不是指路（`build/gates.sh` 本身在盘上）。
    const d4art = checkPaths({ 'report/perf_report.md': ['门禁读数见 `build/r99_gates_nope.txt`'], }, () => false).rows;
    const d4artok = checkPaths({ 'README.md': ['跑 `bash build/gates.sh`，认 `build/*gates*.txt` 里编号最大且',
        '`ALL PASS` 的那一份；`$OUT/board/project/system.bit` 由脚本决定；`build/frozen_rNN/MANIFEST.md5` 是命名规则'], },
        (tok) => tok === 'build/gates.sh').rows;
    // 范围对照（#141 那一类：尺子的作用范围会无声漂移）：同一句指路写在日记里**不许判红**，
    // 但必须进"只报数"那一堆 —— 两边都查，缺一边就是范围漂了。
    const sp = checkPaths({ 'report/log/overnight_log.md': ['当时那份 `build/r99_gates_nope.txt` 已经删了',
        '那份简介 `report/PROJECT_BRIEF_NOPE.md` 后来也撤了'], }, () => false);
    const scope = sp.rows.length === 0 && sp.adv.length === 2;
    console.log(`  ${scope ? 'PASS' : 'FAIL'} 对照：同一句指路（.txt 与 .md 各一）在日记里只报数（判红 ${sp.rows.length} / 报数 ${sp.adv.length}）`);
    // ---- D1b 的一对（#221）：造回来的必须是**真出过的那句错话**，正当句必须不红 ----
    // 这里的基准用写死的 104 是故意的：这条对照测的是**比较逻辑与相邻形状**，不是盘上的产物；
    // 而"盘上到底读不读得到基准"另立一条硬对照（cur0），因为基准读不到时这一层必须红而不是绿。
    const cur0 = currentBoardRound();
    const fakeCur = { nn: 104, bit: 'deadbeefcafe', name: 'r104_gates.txt' };
    n += yes('D1b：把板态身份句念成 r80（基准 r104）',
        d1bScan({ 'report/ai_collaboration.md': [
            '板上这一套现在是 r80（`board/project/system.bit` md5 `1906b6764ae4`，门禁 19/20，唯一红项 = 第 15 项的 `C5c`）'] },
            fakeCur).rows, /D1b/);
    n += yes('D1b：英文身份句念错轮号', d1bScan({ 'README_EN.md': [
        'Design-wide setup WNS (the board now runs r91, flashed at 04:10)'] }, fakeCur).rows, /D1b/);
    const d1bok = d1bScan({
        'report/ai_collaboration.md': ['写这一节那天（2026-09-26）板上是 r80（`board/project/system.bit` md5 `1906b6764ae4`）—— 这句**按日期读**，板上现在跑哪一轮请看 `README.md` 首页那一行'],
        'README.md': ['| 全设计 setup WNS | **0.812 ns**（板上这一版 r104，2026-10-02 01:18 三步 JTAG 刷入，`bit 680f38f5794c`）'],
        'README_EN.md': ['| Design-wide setup WNS | **0.812 ns** (the board now runs r104, flashed at 01:18 on 2026-10-02)'],
    }, fakeCur).rows;
    console.log(`  ${d1bok.length === 0 ? 'PASS' : 'FAIL'} 对照：带日期的历史句 + 念对轮号的中英身份句都不误报（实测 ${d1bok.length} 条）`);
    for (const r of d1bok) console.log('        ' + r);
    // 相邻性这条边界必须自己站住：光有"现在"而后面接的是指路话 ⇒ 不判（否则每一句"现在跑哪一轮请看…"都会红）
    const d1badj = d1bScan({ 'README.md': ['板上现在跑哪一轮请看下面那一行（r80 只是历史）'] }, fakeCur).rows;
    console.log(`  ${d1badj.length === 0 ? 'PASS' : 'FAIL'} 对照：指路句（"现在"后面不接编号）不误报（实测 ${d1badj.length} 条）`);
    for (const r of d1badj) console.log('        ' + r);
    // ---- D1c 的一对（#224 同族）：那句"门禁 N 项 X 绿 / Y 红"必须对回基准门禁件 ----
    // 三条都要有牙：改绿数能红、改项数能红（中英式各一次），而念对的与带日期的历史句都不许红。
    // #229：基准件的读数由**同一个 gatesTally** 解析，不在 fixture 里手搓数字——手搓的对象
    // 会绕过"除本项外"那一段，等于把新加的语义排除在自测之外（这一版自测就是这么当场抓到我的）。
    const fixtureGates = (judged, passOther, failOther, selfState) => {
        const ls = [];
        for (let i = 0; i < passOther; i++) ls.push('  设计项' + i + '  读数  期望 PASS');
        for (let i = 0; i < failOther; i++) ls.push('  设计项F' + i + '  读数  期望 FAIL');
        if (selfState !== 'absent') ls.push('  文档时效 doc_cur  读数  期望 ' + (selfState === 'pass' ? 'PASS' : 'FAIL'));
        ls.push('GATES: 有红项（判定 ' + judged + ' 项）');
        return gatesTally(ls.join('\n'));
    };
    const t104 = fixtureGates(22, 20, 1, 'pass');
    n += yes('D1c：把 21 绿念成 19 绿（基准 22 项／21 绿／1 红）',
        d1cScan({ 'README.md': ['| 全设计 setup WNS | **0.812 ns**（板上这一版 r104；门禁 22 项 19 绿 / 1 红，唯一红是 `C5c`）'] },
            fakeCur, t104).rows, /D1c/);
    n += yes('D1c：英文式把项数念成 23（基准 22）', d1cScan({ 'README_EN.md': [
        'the 23-item gate check reads 22 green / 1 red (the board now runs r104)'] }, fakeCur, t104).rows, /D1c/);
    const d1cok = d1cScan({
        'README.md': ['| 全设计 setup WNS | **0.812 ns**（板上这一版 r104；门禁 22 项 21 绿 / 1 红，唯一红是 `C5c`）'],
        'README_EN.md': ['(the board now runs r104; the 22-item gate check reads 21 green / 1 red)'],
        'report/ai_collaboration.md': ['写这一节那天（2026-09-26）板上是 r80，门禁 19 项 18 绿 / 1 红 —— 这句按日期读'],
    }, fakeCur, t104);
    const d1cokPass = d1cok.rows.length === 0 && d1cok.claims === 3 && d1cok.skipped === 1;
    console.log(`  ${d1cokPass ? 'PASS' : 'FAIL'} 对照：念对的中英句不误报、带日期的历史句只数不判`
        + `（判红 ${d1cok.rows.length} 期望 0｜命中 ${d1cok.claims} 期望 3｜历史豁免 ${d1cok.skipped} 期望 1）`);
    for (const r of d1cok.rows) console.log('        ' + r);
    // 固定点这一支（#229 的正身）：基准件里"文档时效"那一格是 FAIL（上一轮因为这句话没对上而红），
    // 只要**除本项外**是 20 绿/1 红，这句念 21 绿/1 红就不许再红——否则它会在 21/1 与 20/2 之间
    // 来回跳（连着跑两次门禁实测到的正是这个振荡，两个解各自自洽）。
    const fpScan = d1cScan({ 'README.md': ['板上这一版 r104，门禁 22 项 21 绿 / 1 红，唯一红是 `C5c`'] },
        fakeCur, fixtureGates(22, 20, 1, 'fail'));
    const fpOk = fpScan.rows.length === 0 && fpScan.claims === 1;
    console.log(`  ${fpOk ? 'PASS' : 'FAIL'} 对照·固定点：基准件本项那格 FAIL 也不把这句话判红（除本项外 20 绿/1 红 ⇒ 21 绿/1 红自洽）（实测判红 ${fpScan.rows.length} 期望 0｜命中 ${fpScan.claims} 期望 1）`);
    // 反买通：固定点不能变成"永远说绿"。除本项外多一个红，这句话就必须红。
    n += yes('D1c 反买通：除本项外多一个红（19 绿/2 红）而首页仍念 21 绿/1 红 ⇒ 必须红', d1cScan({
        'README.md': ['板上这一版 r104，门禁 22 项 21 绿 / 1 红'] }, fakeCur, fixtureGates(22, 19, 2, 'pass')).rows, /D1c/);
    // 自相矛盾的那一支单独测：项数 ≠ 绿+红 时必须红，哪怕绿红两个数都与门禁件对不上也无所谓（先报矛盾）
    n += yes('D1c：首页自己前后不一（22 项 / 21 绿 / 2 红）', d1cScan({ 'README.md': [
        '板上这一版 r104，门禁 22 项 21 绿 / 2 红'] }, fakeCur, fixtureGates(23, 20, 2, 'pass')).rows, /D1c/);
    // 地板对照：基准读得到、文档里一句"N 项 X 绿 / Y 红"都没有 ⇒ 必须报"这一层没接上"，不许静默 0 条
    n += yes('D1c：那一行改了形状（一句都没抓到）⇒ 报空转而不是 0 条', d1cScan({
        'README.md': ['| 全设计 setup WNS | **0.812 ns**（板上这一版 r104；门禁清单见 `build/reports/gates.txt`）'] },
        fakeCur, t104).rows, /D1c 空转/);
    const hasBase = cur0.nn > 0 || cur0.absent;   // 包里没有二进制 ⇒ 已声明为不可判，这条对照仍算过（仓库里必须有基准）
    console.log(`  ${hasBase ? 'PASS' : 'FAIL'} D1b 基准：`
        + (cur0.nn > 0 ? '读得到 r' + cur0.nn + '（' + cur0.name + '）'
          : cur0.absent ? '本目录无 bit 产物 ⇒ 这一层声明为不判（在仓库里跑时它是硬判据）' : '读不到'));
    if (!hasBase) console.log('        —— 基准读不到时真实扫描那一趟会把这一层判红（不许念成绿的），这里只是把原因打出来');
    let d4 = 0;
    d4 += yes('D4a：点名的文档盘上没有', d4bad, /D4a/);
    d4 += yes('D4b：还在指旧目录 docs/', d4old, /D4b/);
    d4 += yes('D4c：点名的凭据（.txt/.rpt/…）盘上没有', d4art, /D4c/);
    console.log(`  ${d4ok.length === 0 ? 'PASS' : 'FAIL'} 对照：真指路 + 占位名 + "旧目录"的叙事句不误报（实测 ${d4ok.length} 条）`);
    for (const r of d4ok) console.log('        ' + r);
    console.log(`  ${d4artok.length === 0 ? 'PASS' : 'FAIL'} 对照：通配/变量/占位名的凭据写法不误报（实测 ${d4artok.length} 条）`);
    for (const r of d4artok) console.log('        ' + r);
    // ---- #222 的三条对照：豁免只能由**同一行的声明**换来，隔行不行、没声明更不行 ----
    const nsOn = checkPaths({ 'board/README.md': ['凭据 `board/uart_script_capture.txt`（本机捕获，已被 `.gitignore` 挡住，不随包）'], }, () => false).rows;
    const nsOff = checkPaths({ 'board/README.md': ['凭据 `board/uart_script_capture.txt`'], }, () => false).rows;
    const nsFar = checkPaths({ 'board/README.md': ['凭据 `board/uart_script_capture.txt` 的读数见下一行', '下一行写着不随包'] }, () => false).rows;
    const nsPred = noShip('点名 `x`（不随包）') && !noShip('点名 `x`') && !/NN|\$/.test('evidence_r75') && /NN/.test('evidence_rNN');
    console.log(`  ${nsOn.length === 0 && nsOff.length === 1 && nsFar.length === 1 ? 'PASS' : 'FAIL'}`
        + ` 对照：同行声明才放行（有声明红 ${nsOn.length} 期望 0｜无声明红 ${nsOff.length} 期望 1｜隔行红 ${nsFar.length} 期望 1）`);
    for (const r of nsFar.concat(nsOff)) console.log('        ' + r);
    console.log(`  ${nsPred ? 'PASS' : 'FAIL'} 对照：谓词与 D2 的占位豁免都对（D2 用的就是这两个式子：noShip 命中/不命中各一次，NN 只咬占位名）`);
    // ---- 2026-10-05 两把新降级各配一对"能红/能绿"对照 ----
    // (a) 围栏内的原文回显：同一条死凭据写在围栏里只报数、写在围栏外必须红（少了后一半，这条降级
    //     就成了"把整段抄件划进围栏即可放行"的后门）。
    const fenOn = checkPaths({ 'report/x.md': ['说明：', '```text', 'RESULT PASS（捕获 board/uart_script_capture.txt）', '```'] }, () => false);
    const fenOff = checkPaths({ 'report/x.md': ['凭据 `board/uart_script_capture.txt`'] }, () => false);
    const fenOk = fenOn.rows.length === 0 && fenOn.adv.some(r => /D4c 围栏内/.test(r)) && fenOff.rows.length === 1;
    console.log(`  ${fenOk ? 'PASS' : 'FAIL'} 对照：围栏内只报数／围栏外照旧红（围栏内红 ${fenOn.rows.length} 期望 0｜报数 ${fenOn.adv.filter(r => /围栏内/.test(r)).length} 期望 1｜围栏外红 ${fenOff.rows.length} 期望 1）`);
    // (b) 链式扩展名：`…rpt.json` 要按**整名**查盘。对照=整名存在时不红；变异=整名不存在时必须红
    //     （少了变异那一半，这条改动等于把整批 `build/parsed/` 一律放行）。
    const FULL = 'build/parsed/parsed_cdc.rpt.json';
    const extOk = checkPaths({ 'report/y.md': ['名册读 `build/parsed/parsed_cdc.rpt.json`'] }, (t) => t === FULL).rows.length === 0;
    const extBad = checkPaths({ 'report/y.md': ['名册读 `build/parsed/parsed_cdc.rpt.json`'] }, () => false).rows;
    console.log(`  ${extOk && extBad.length === 1 ? 'PASS' : 'FAIL'} 对照：链式扩展名按整名查（存在时红 ${extOk ? 0 : 1} 期望 0｜不存在红 ${extBad.length} 期望 1）`);

    const all = n === 10 && good.length === 0 && edges.length === 0 && d4 === 3
        && d4ok.length === 0 && d4artok.length === 0 && scope && neutral.length === 0
        && d1bok.length === 0 && d1badj.length === 0 && hasBase && d1cokPass && fpOk
        && nsOn.length === 0 && nsOff.length === 1 && nsFar.length === 1 && nsPred
        && fenOk && extOk && extBad.length === 1;
    console.log(`${all ? 'SELF: 全绿' : 'SELF: 有红'}（变异 ${n}（含 D1b 身份句 2 条 + D1c 门禁读数句 5 条：改绿数／改项数／反买通／自相矛盾／形状空转）+ D4 变异 ${d4} 条 + 对照 ${good.length + edges.length + d4ok.length + d4artok.length + d1bok.length + d1badj.length} 条，范围对照${scope ? '过' : '不过'}，D1b 基准${hasBase ? '读得到 r' + cur0.nn : '读不到'}）`);
    process.exit(all ? 0 : 1);
}

const { rows, adv, nd, g, n, m, d1b, d1c } = scanTree();
console.log(`扫了 ${n} 个文档（D1/D2/D3）+ ${m} 个手写文件（D4）；最新且 ALL PASS 的冻结集 = ${g.name || '（没有）'}`);
console.log(`D1b 基准：bit md5=${d1b.cur.bit || '读不到'} → ${d1b.cur.name || d1b.cur.why || '（无）'}${d1b.cur.absent ? '（本目录没有 bit 产物 ⇒ 这一层不判；在仓库里跑时它是硬判据）' : ''}；扫 ${d1b.docs} 份交付文档，抓到 ${d1b.claims} 句"板态身份句"（只念相邻带编号的那种，历史句不进射程）`);
console.log(`D1c 基准：${d1c.file || '（没有基准件 ⇒ 这一层不判）'} 行尾 PASS=${d1c.tally ? d1c.tally.pass : '不判'} / FAIL=${d1c.tally ? d1c.tally.fail : '不判'} / 判定项数=${d1c.tally ? d1c.tally.judged : '不判'}；比对基准按"除本项外"算（除本项 PASS=${d1c.tally ? d1cBasis(d1c.tally).pass : '不判'} FAIL=${d1c.tally ? d1cBasis(d1c.tally).fail : '不判'}，本项在基准件里是 ${d1c.tally ? d1c.tally.self : '不判'}）；抓到 ${d1c.claims} 句"门禁 N 项 X 绿 / Y 红"（相邻才判，历史句 ${d1c.skipped} 句只数不判）`);
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
console.log(`  同行写了"不随包/已被 .gitignore 挡住/不入库/本地留档"这类声明而放行的指路：${nNOSHIP} 条`
    + '（豁免只降级为"只报数"，条数念出来，不许静默吞掉 —— #217 同族）');
console.log(rows.length ? `CURRENCY: ${rows.length} 条过期指路` : 'CURRENCY: 干净');
process.exit(rows.length ? 1 : 0);
