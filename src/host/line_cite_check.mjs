// src/host/line_cite_check.mjs —— D5：交付文档里的 `文件.扩展名:行号` 引用，判"语义锚点在不在附近"
//
// 为什么要有它（ISSUES #122）：README/report/skill 里有 200+ 处 `pl_video_top.v:834` 这种引用，
// 而 `doc_currency_check.mjs` 的 D4 只管**路径存在性**，**行号漂了什么都不会红**：
// 位流编得出来、台架全过、门禁全绿，文档却指着另一个地方。今晚给 16 个模块头补定位那一批
// 就实地把若干引用平移了 1~4 行（同一批里还有早就漂了、一直没人核对的老错）。
//
// 判据为什么不是"行号对不对"：没有第二份真值能告诉我"对的行号"是多少。
// 能判的是**这句话里必然出现的标识符**（`SPLIT_SPEED`、`osd_en`、`u_pipe`…）有没有落在被引的那几行里
// （区间引用 0 容忍、单点 ±2，理由写在 nearHit 上面）。
// 锚点在 ⇒ 引用至少没有指到十万八千里外；锚点取不出来 ⇒ **单独列成"需人看"清单**，绝不静默通过
// （"空判据恒绿"那一族，见 skill/criterion_blind_spot.md）。
//
// 跑法：
//   node src/host/line_cite_check.mjs          # 扫全交付文档
//   node src/host/line_cite_check.mjs --self    # 反向对照： planted 的坏引用必须红、好的不许误报
//   node src/host/line_cite_check.mjs --list-soft --list-soft=50   # 锚点候选（不判红，给人排队）
//   node src/host/line_cite_check.mjs --list-need 50               # 取不出锚点，需人看
//   node src/host/line_cite_check.mjs --list-echo 20               # D5d 的"转述"那一支（不判红）
//
// 判红的三类（退出码只看这些）：引的文件不在树里、行号越过文件末尾、
// D5b「例化者」列指错、D5d 逐字抄的固件回声与所引那几行对不上（#208 补的两条硬判据）。
//
// 范围只管**代码/脚本**行号（.v .c .h .mjs .sh .tcl .ps1）。`.md` 之间的行号引用故意不收：
// 那是追加式档案（ISSUES/OVERNIGHT_LOG），把过去的记录改成迎合检查器等于销毁证据，
// 而且散文里取不出"必然出现的标识符"，判据会退化成猜。
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..', '..');
const DOC_DIRS = ['.', 'report', 'report/log', 'skill', 'board'];
// **追加式档案不参与核对**（`report/log/` 的四本日记）：与 `doc_currency_check.mjs` 同一口径——
// 把过去的记录改成迎合检查器，等于销毁证据；而档案里的假路径（`tb_x.v:123` 那一类是**举例子**）
// 会被硬错判据抓住，制造一批根本不该存在的"文档 bug"。
const SKIP_DOCS = ['report/log/', 'report/study/'];
const CODE_EXT = new Set(['.v', '.c', '.h', '.mjs', '.sh', '.tcl', '.ps1']);
// 被引文件在这些目录里不存在（生成的、厂商树），引用它们本来就不该判红
const SKIP_DIR = new Set(['.git', 'vivado_system', 'xsim.dir', 'node_modules', '.Xil', 'dist', 'study', 'report/study']);
// 锚点里不算数的词：文件名、常见英文、工具名——它们出现在任何地方都不证明"指对了地方"
const STOP = new Set(['the', 'and', 'for', 'with', 'this', 'that', 'from', 'then', 'else', 'wire', 'reg',
                      'input', 'output', 'module', 'begin', 'end', 'node', 'bash', 'git', 'docs', 'src',
                      'skill', 'build', 'sim', 'report', 'true', 'false', 'md5', 'tcl', 'sh', 'mjs', 'ps1']);

const CITE = /([A-Za-z0-9_./-]+\.(?:v|c|h|mjs|sh|tcl|ps1)):(\d+)(?:-(\d+))?/g;
const IDENT = /[A-Za-z_][A-Za-z0-9_]{3,}/g;

function mdFiles() {
  const out = [];
  const seen = new Set();
  for (const rel of DOC_DIRS) {
    const dir = path.join(ROOT, rel);
    if (!existsSync(dir)) continue;
    const walk = (d) => {
      for (const name of readdirSync(d)) {
        const p = path.join(d, name);
        if (statSync(p).isDirectory()) { if (!SKIP_DIR.has(name)) walk(p); }
        else if (name.endsWith('.md')) { const k = path.relative(ROOT, p).replaceAll('\\', '/');
          if (SKIP_DOCS.some((s) => k.startsWith(s))) continue;
          if (!seen.has(k)) { seen.add(k); out.push(p); } }
      }
    };
    walk(dir);
  }
  return out;
}

// 从"引用所在的那句话"里取锚点：优先反引号里的标识符，其次整行里出现的大写常量/带下划线的名字。
// 取不到就返回空数组（调用方据此进"需人看"清单，而不是放行）。
function anchorsOf(text, citedFile) {
  const base = path.basename(citedFile);
  const cand = new Set();
  for (const m of text.matchAll(/`([^`]+)`/g)) {
    for (const t of m[1].match(IDENT) || []) if (!STOP.has(t.toLowerCase())) cand.add(t);
  }
  // 没有反引号时也认整行里的"代码味"词：必须含下划线、或全大写、或以 u_/_reg/_inst 结尾
  for (const t of text.match(IDENT) || []) {
    if (STOP.has(t.toLowerCase())) continue;
    if (/^[A-Z][A-Z0-9_]{3,}$/.test(t) || /_/.test(t)) cand.add(t);
  }
  const drop = new Set([base, base.replace(/\.[^.]+$/, ''), ...CITE_FLAGS]);
  // 锚点必须"长得像代码符号"：≥5 个字符、或含下划线、或全大写常量。
  // 为什么：交付文档里大量引用指的是**命令名**（`show`/`auto`/`zoom`/`fill`），它们在 main.c 里
  // 是字符串字面量、离被引那一行十万八千里，却"文件认识"——短词当锚点会把判据变成噪声发生器
  // （第一版实测：330 条红里绝大多数是这一类）。宁可少判（进"需人看"），也不要误判成"文档错了"。
  const shaped = (t) => t.length >= 5 || t.includes('_') || /^[A-Z][A-Z0-9]{2,}$/.test(t);
  return [...cand].filter((t) => !drop.has(t) && t !== citedFile && shaped(t));
}
const CITE_FLAGS = ['git', 'grep', 'sed', 'awk', 'http', 'https'];

// 容忍度是判据的**力度**，不是风格：区间引用（`:16-18`）就是"那三行本身"，给 0 行容忍——
// 因为 #122 那个真实事故的错位恰好只有 3 行（16-18 ↔ 19-21），给 ±3 就等于**判不住它要判的那件事**
// （self 里 bad 那一条就是拿它做的，改窗口的那一刻它从"漏过"变成"抓住"）。
// 单点引用（`:834`）给 ±2：指"某一处"时那一两行注释上下文是正常写法。
function nearHit(fileLines, from, to, anchors) {
  const tol = from === to ? 2 : 0;
  const lo = Math.max(1, from - tol), hi = Math.min(fileLines.length, to + tol);
  const winTxt = fileLines.slice(lo - 1, hi).join('\n');
  for (const a of anchors) if (winTxt.includes(a)) return { ok: true, anchor: a, lo, hi };
  return { ok: false, lo, hi };
}

// D5d（ISSUES #208 的第二半，标本来自 2026-10-02 那批引用核对）：**文档把固件回声逐字抄下来时，
// 那个回声必须就在被引的那几行里**。为什么这一条可以是硬错而普通锚点不命中只能算 soft：
// 引号里有 `[TAG]` 形状 ⇒ 这句话主张的是"串口打出来的就是这一串"，逐字抄写不存在
// "指的是所在函数开头"那种合理解释；而软判据靠的是标识符，回声句里全是命令名与中文，取不出锚点。
// 两个方向都要能红：抄的句子在这个文件里**别处**找得到 ⇒ 行号指错（硬错）；
// 整个文件都找不到 ⇒ 可能是转述、也可能来自另一个文件 ⇒ 只列"需人看"，不冒充成"文档错了"。
// 归一化去掉空白与中英标点：C 里的字符串常量常被硬拆成两行续接，全角半角括号也混着用，
// 不剥标点就会把"真的抄对了"判成错。
const ECHO_TAG = /\[[A-Z][A-Z0-9_]{1,7}\]/;
const QUOTED = [/“([^”]{6,})”/g, /「([^」]{6,})」/g, /`([^`]{6,})`/g];
// 归一化后至少 12 个字符才算"逐字抄下来的一串"。为什么：`[STAT]` 这种六个字符的是**提到标签**，
// 不是抄整句（它在文件里出现的位置比引用点远得多，会把好句子判成红）；真回声都带格式串与中文。
const ECHO_MIN = 12;

// 带列位地取出这一行里"逐字抄的回声"（引号内、含 `[TAG]`、够长）。end = 右引号之后的位置。
function echoQuoteSpans(line) {
  const out = [];
  for (const re of QUOTED) {
    for (const m of line.matchAll(re)) {
      if (ECHO_TAG.test(m[1]) && normEcho(m[1]).length >= ECHO_MIN) out.push({ text: m[1], end: m.index + m[0].length });
    }
  }
  return out;
}

// **配对**：一句"回声写着「…」"只与**紧跟在它后面**的那个引用配对（间隔 ≤4 个字符，容得下 `（` 与空格），
// 也就是文档的实际写法 `…「回声」`（`main.c:998`）`。为什么不做"最近引用"：表格一行里几列各说各话，
// 第三列抄的回声会配上第一列的引用，造出假红（第一版实测：6 条"硬错"里 5 条是这个形状，真错只有 1 条）。
// 配不上就是不判——这条要的是"红一次就是一件真事"，不是覆盖率。
function assignEchoes(line) {
  const out = new Map();
  const cites = [...line.matchAll(CITE)].map((m) => m.index);
  if (!cites.length) return out;
  for (const q of echoQuoteSpans(line)) {
    const nxt = cites.find((c) => c >= q.end && c - q.end <= 4);
    if (nxt === undefined) continue;
    if (!out.has(nxt)) out.set(nxt, []);
    out.get(nxt).push(q.text);
  }
  return out;
}

const normEcho = (s) => s.replace(/[\s（）()〈〉《》「」“”‘’"'`;:.、，。！？—…·\-/]+/g, '');

// 返回 null（抄对了）/ 'wrong-line'（这个文件别处才是它说的地方）/ 'absent'（文件里根本没这句）
function echoVerdict(fileText, quote, winText) {
  const q = normEcho(quote);
  if (!q) return null;
  if (normEcho(winText).includes(q)) return null;
  return normEcho(fileText).includes(q) ? 'wrong-line' : 'absent';
}

function check(linesByFile, wordsByFile, docs) {
  // hard = 机器能单独判定的那两类（引的文件不在树里 / 行号越过文件末尾）——这些**必定**是坏引用。
  // soft = "锚点不在那几行里"：它**不能**单独判"文档错了"，因为文档常指向"那一处所在的函数开头"
  //   而不是语句本身（第一版实测：把 soft 当红报出 341 条，逐条抽读后大部分是这个形状，不是 341 个文档 bug）。
  //   所以 soft 只作为**排好序的候选清单**输出，不决定退出码，也不进门禁（#122 自己写的警告：
  //   "把本来就已经错的引用改成另一个错的数字，比不动更坏"）。
  const fails = [], soft = [], needs = [], oks = [], echoNeed = [];
  let skipped = 0;
  for (const doc of docs) {
    const text = readFileSync(doc, 'utf8');
    const rel = path.relative(ROOT, doc).replaceAll('\\', '/');
    const docLines = text.split(/\r?\n/);
    docLines.forEach((line, idx) => {
      for (const m of line.matchAll(CITE)) {
        const [, file, a, b] = m;
        const from = Number(a), to = Number(b || a);
        // 引用可能写 `pl_video_top.v:16-18`，也可能写完整路径；都按"树里能不能找到这个文件"解析
        const key = resolveTarget(file, linesByFile);
        if (!key) {
          if (VENDOR.has(path.basename(file))) { skipped++; continue; }
          fails.push(`${rel}:${idx + 1}  引的文件在树里找不到：${m[0]}`); continue;
        }
        // 句子的上下文：本行 + 下一行（Markdown 里一句常被硬换行劈开）
        const ctx = line + ' ' + (docLines[idx + 1] || '');
        const anch = anchorsOf(ctx, file);
        if (anch.length === 0) { needs.push(`${rel}:${idx + 1}  ${m[0]}  （取不出锚点，需人看）`); continue; }
        const tgt = linesByFile.get(key);
        // 锚点必须是**那个文件认识的符号**：文档句子里常带命令名、工具名、别的模块的信号名
        // （`HANDS_ON.md` 里一句 "`frame 50` 之后 `stop`" 引 `main.c:1227`，`frame` 是字符串字面量、
        // `stop` 也在文件里，可它们不一定落在被引那两行）。文件里根本不出现的词没有资格判红——
        // 它只能说明这句话没给代码线索，于是进"需人看"，不冒充成"引用错了"。
        const live = anch.filter((t) => (wordsByFile.get(key) || new Set()).has(t));
        if (live.length === 0) { needs.push(`${rel}:${idx + 1}  ${m[0]}  （句子里没有任何被引文件认识的符号，需人看）`); continue; }
        if (to > tgt.length) { fails.push(`${rel}:${idx + 1}  ${m[0]}  超出文件长度（${tgt.length} 行）`); continue; }
        const iv = instViol(docLines, idx, m[0], linesByFile);
        if (iv) {
          fails.push(`${rel}:${idx + 1}  D5b「例化者」列指错：${m[0]} 第 1 列模块是 ${iv.mod}，`
            + `被引那一行写的是「${iv.text}」——不是它的例化行`);
          continue;
        }
        // D5d：这一句里逐字抄的固件回声（引号内带 `[TAG]`）必须落在被引的那几行里。
        //   只看本行，不拼下一行——下一行的引号属于下一句话，跨句配对会造出假红。
        const tol = from === to ? 2 : 0;
        const wLo = Math.max(1, from - tol), wHi = Math.min(tgt.length, to + tol);
        const winTxt = tgt.slice(wLo - 1, wHi).join('\n'), allTxt = tgt.join('\n');
        for (const q of (assignEchoes(line).get(m.index) || [])) {
          const v = echoVerdict(allTxt, q, winTxt);
          if (v === 'wrong-line') {
            // 提示行优先按**整句**找；退而求其次才按前缀（前缀会在帮助文本里撞词，所以标"约"）
            const fullQ = normEcho(q);
            let at = tgt.findIndex((L) => normEcho(L).includes(fullQ)) + 1, approx = '';
            if (!at) {
              const head = fullQ.slice(0, 12);
              at = tgt.findIndex((L) => normEcho(L).includes(head)) + 1;
              approx = '约';
            }
            fails.push(`${rel}:${idx + 1}  D5d 抄的回声不在被引那几行：${m[0]} 引「${q.trim().slice(0, 34)}」`
              + `，这个文件里它在第 ${at || '?'} 行${approx ? approx + '（按前缀匹配）' : ''}附近`);
          } else if (v === 'absent') {
            echoNeed.push(`${rel}:${idx + 1}  ${m[0]}  引号里那句「${q.trim().slice(0, 34)}」在这个文件里找不到`
              + `（转述？引错了文件？）`);
          }
        }
        const r = nearHit(tgt, from, to, live);
        if (r.ok) oks.push(`${rel}:${idx + 1}  ${m[0]}  锚点 ${r.anchor}`);
        else soft.push(`${rel}:${idx + 1}  ${m[0]}  锚点 ${live.slice(0, 3).join('/')}… 不在 ${r.lo}-${r.hi} 行里`);
      }
    });
  }
  return { fails, soft, needs, oks, skipped, echoNeed };
}

function resolveTarget(cited, linesByFile) {
  if (linesByFile.has(cited)) return cited;
  const base = path.basename(cited);
  let hit = null, n = 0;
  for (const k of linesByFile.keys()) if (k === base || k.endsWith('/' + base)) { hit = k; n++; }
  return n === 1 ? hit : (hit || (linesByFile.has(cited) ? cited : null));
}

// D5b（ISSUES #208 补的那条硬判据）：交付文档里表头写着「例化者」的那一列，
// 被引行必须以本行第 1 列的模块名打头 —— 那一列的语义就是"它在哪里被例化"，
// 指到别的代码上就是死引用。为什么这条可以是**硬错**而普通锚点不命中只能算 soft：
// 列名把语义钉死了（不存在"指的是所在函数开头"那种合理解释），
// 而它的"改前红"标本就是今晚 `report/modules.md` 那 28 条（命中 0 条）。
function instColOf(docLines, idx) {
  for (let j = idx; j >= 0 && j > idx - 400; j--) {
    const l = docLines[j] || '';
    if (/^\|\s*模块\s*\|/.test(l)) return l.split('|').findIndex((c) => c.trim() === '例化者');
  }
  return -1;
}

function instViol(docLines, idx, citeText, linesByFile) {
  const line = docLines[idx] || '';
  if (!line.startsWith('|')) return null;
  const col = instColOf(docLines, idx);
  if (col <= 0) return null;
  const cols = line.split('|');
  if (cols.length <= col || !cols[col] || cols[col].indexOf(citeText) < 0) return null;
  const idents = (cols[1] || '').match(/[A-Za-z_][A-Za-z0-9_]*/g) || [];
  const mod = idents[0];
  const p = citeText.match(/:(\d+)/);
  if (!mod || !p) return null;
  const key = resolveTarget(citeText.split(':')[0], linesByFile);
  if (!key) return null;
  const tgt = linesByFile.get(key);
  const ln = Number(p[1]);
  if (!tgt || ln > tgt.length) return null;
  const text = (tgt[ln - 1] || '').trim();
  // 「例化者」列里带 `→` 的写法是另一种主张："这个包装模块在它自己的文件里例化了哪些子模块"
  // （`arp` → `arp_rx`/`arp_tx`、`icmp` → `icmp_rx`/`icmp_tx`）。那一半按**前缀**判，
  // 不然一个正确的行号（`arp.v:46` 正是 `arp_rx #(`）会被我说成错引用；不带箭头的仍按整词判死。
  const loose = (cols[col] || '').includes('→');
  const re = new RegExp('^' + mod + (loose ? '' : '\\b'));
  if (re.test(text)) return null;
  return { mod, from: ln, text: text.slice(0, 46) };
}

// 厂商树里的文件名：文档会引 `xsdps.c:156-159` 这种驱动行号，那些文件不在"我写的东西"范围，
// 但也不该被判成"文件在树里找不到"——那是我的扫描范围，不是文档的错。
// ⚠ 只靠"从 `vitis/` 现派生"是有条件的：**提交包里没有 `vitis/`**，于是包内跑 D5 会把这句正当的厂商引用
//   判成硬错（03:4x 实测：包内 `report/commands.md:267` 红，而仓库里同一行被跳过、硬错 0）。
//   ⇒ 下面这份小名单是**交付文档真正点名过的厂商文件**（不是整棵 BSP 的 700 个名字），随判据同文件走，
//     包内也成立。它不是免检通道：`vendorBuyoff()` 会判红"名单里出现了我自己写的文件"，
//     所以往里塞 `zoom_mapper.v` 这类第一方文件不会让引用变绿，只会让判据变红（#172 那次 `*.log` 被整类放掉的教训）。
const VENDOR_SEED = ['xsdps.c'];
const VENDOR = new Set(VENDOR_SEED);

// 豁免名单的反买通检查：名单里的名字如果能在第一方树里解析到，就是有人在拿豁免通道盖真引用 ⇒ 硬错。
function vendorBuyoff(code) {
  const rows = [];
  const firstParty = new Set();
  for (const rel of code.keys()) firstParty.add(path.basename(rel));
  for (const name of VENDOR_SEED) {
    if (firstParty.has(name))
      rows.push(`VENDOR_SEED  名单里的 ${name} 在第一方树里存在（src/ 或 sim/ 之类）⇒ 厂商豁免不许盖住我自己写的文件，把它从名单里删掉`);
  }
  return rows;
}

function loadCode() {
  const map = new Map();
  const walk = (d) => {
    for (const name of readdirSync(d)) {
      if (SKIP_DIR.has(name)) continue;
      const p = path.join(d, name);
      const st = statSync(p);
      if (st.isDirectory()) walk(p);
      else if (CODE_EXT.has(path.extname(name))) {
        const rel = path.relative(ROOT, p).replaceAll('\\', '/');
        if (rel.startsWith('vitis/')) { VENDOR.add(name); continue; }
        map.set(rel, readFileSync(p, 'utf8').split(/\r?\n/));
      }
    }
  };
  walk(ROOT);
  return map;
}

// 反向对照（D5 自己的牙）：一条**故意错**的引用必须被抓住，一条对的不许误报。
// 用 #122 里那个真实事故当 fixture：`pl_video_top.v:16-18` 配锚点 SPLIT_SPEED（真实参数在 19-21）。
function selfTest(code) {
  const top = 'src/rtl/top/pl_video_top.v';
  if (!code.has(top)) { console.log('SELF SKIP: 读不到 ' + top); return 1; }
  const probe = [{ bad: '端点是构建参数（pl_video_top.v:16-18）里 `SPLIT_SPEED` 那一组',
                    good: '端点是构建参数（pl_video_top.v:19-21）里 `SPLIT_SPEED` 那一组' }];
  let pass = 0;
  for (const one of probe) {
    for (const [k, line] of Object.entries({ bad: one.bad, good: one.good })) {
      const m = [...line.matchAll(CITE)][0];
      const [, file, a, b] = m;
      const key = resolveTarget(file, code);
      const r = nearHit(code.get(key), Number(a), Number(b || a), anchorsOf(line, file));
      const want = k === 'good';
      console.log(`  ${r.ok === want ? 'PASS' : 'FAIL'} ${k}: ${line} ⇒ ${r.ok ? '锚点命中' : '锚点不命中'}`);
      if (r.ok === want) pass++;
    }
  }
  // D5b 自己的对照（#208）：一个真实标本 —— `report/modules.md` 的"例化者"列曾经指着 axi 域那一段。
  // ⚠ 行号**按内容现算**，不许写死（规矩 43）：今晚 r109 在 pl_video_top.v 里插了 26 行，
  //   原来那个"对号 :859"的固定标本就自己过期了 —— 尺子的 fixture 跟着源码漂，是它自己红、不是设计红。
  const pvTop = readFileSync('src/rtl/top/pl_video_top.v', 'utf8').split(/\r?\n/);
  const GOOD = pvTop.findIndex(l => /^\s*split_ctrl\s+([A-Za-z_]\w*\s*\(|#\()/.test(l)) + 1;
  const BAD = GOOD + 1;                        // 例化的下一行是端口映射，必定不是"第 1 列=模块名"那行
  if (GOOD <= 1) { console.log('  FAIL D5b 对照找不到 split_ctrl 的例化行 —— fixture 失效，停手'); }
  const d5b = ['| 模块 | 职责 | 例化者 |', '|------|------|--------|',
    `| \`split_ctrl\` | 分割线位置发生器 | \`pl_video_top.v:${BAD}\` |`,
    `| \`split_ctrl\` | 分割线位置发生器 | \`pl_video_top.v:${GOOD}\` |`,
    // 带箭头的列允许"父 → 子"前缀匹配，但它**仍然要有牙**：指到一个不是 `arp*` 的行必须照样红。
    '| `arp` → `arp_rx` / `arp_tx` | 包装层 | `arp.v:15` |'];
  let b5 = 0;
  for (const [row, wantRed, tag] of [[2, true, `错号 :${BAD} 必须红`], [3, false, `对号 :${GOOD} 必须绿`],
                                      [4, true, '箭头列指到非 arp* 行 :15 必须红']]) {
    const cite = [...d5b[row].matchAll(CITE)][0][0];
    const isRed = instViol(d5b, row, cite, code) !== null;
    console.log(`  ${isRed === wantRed ? 'PASS' : 'FAIL'} D5b ${tag}：实测${isRed ? '红' : '绿'}`);
    if (isRed === wantRed) b5++;
  }
  // 硬错那一层也要能红：两条必定坏的必须被认出来，一条"越过 200 但在长文件里合法"的不许误报。
  // 说清楚强度差别：这里证明的是**判据还在跑**（以及被引文件真的被读进来了）；
  // 它真正的红→绿凭据是今晚那一次——修之前全树报 7 条硬错、逐条改对之后报 0 条（ISSUES #122 收口段）。
  const lm = code.get('src/rtl/eth/link_monitor.v');
  const hardCases = [
    ['越过 EOF', resolveTarget('link_monitor.v', code) !== null && 9999 > lm.length, true],
    ['文件不在树里', resolveTarget('no_such_file_zzz.v', code) === null && !VENDOR.has('no_such_file_zzz.v'), true],
    ['同一行号在长文件里合法（不许误报）', 900 > code.get('src/rtl/top/pl_video_top.v').length, false],
    // 包内没有 `vitis/` 树时，`xsdps.c` 依然必须被认成厂商引用（不判硬错）——
    // 这一条测的正是提交包那种环境：文件在第一方树里解析不到，而名单里有它。
    ['厂商兜底：树里没有 xsdps.c 也不算硬错',
      resolveTarget('xsdps.c', code) === null && VENDOR.has('xsdps.c'), true],
    // 反买通：名单里出现第一方文件必须当场红（不然谁都能靠加一行把真引用洗绿，同 #172）
    ['厂商名单不许盖住第一方文件（反买通）',
      vendorBuyoff(new Map([['src/rtl/eth/xsdps.c', ['// x']]])).length === 1, true],
  ];
  for (const [name, got, want] of hardCases) {
    console.log(`  ${got === want ? 'PASS' : 'FAIL'} 硬错判据 ${name}：${got === want ? '符合预期' : '不符合预期'}`);
    if (got === want) pass++;
  }
  // D5d 自己的对照（#208 第二半）：标本就是 2026-10-02 那批里的一条真错——文档逐字抄了
  // `[GAMMA] auto 的 step …` 那句回声，却把行号写成 1186（那里是 split 的掩码运算）。
  // 行号**在运行时按内容找回**，不写死：写死的 fixture 会像文档一样漂掉，那时这条对照就成了假绿。
  const mc = code.get('src/ps/main.c');
  let e5d = 0, d5dRun = 0;
  if (mc) {
    const Q = '[GAMMA] auto 的 step 要的是 γ×100 的正整数（20 = 0.20）';   // 引号**内**的那串，与 check() 取到的形状一致
    const QF = '`[GAMMA] 固件从来不打印这一串中文`';
    // 用**整句**归一化去找，不用前缀：前缀（`[GAMMA]auto的`）在帮助文本里也出现，会把"唯一"判成不唯一
    const full = normEcho(Q);
    const hits = mc.map((L, i) => (normEcho(L).includes(full) ? i + 1 : 0)).filter((n) => n > 0);
    const at = hits[0] || 0;
    const far = at + 57 <= mc.length ? at + 57 : 0;
    if (hits.length === 1 && at && far && !normEcho(mc.slice(far - 3, far + 2).join('\n')).includes(full)) {
      const win = (n) => mc.slice(Math.max(0, n - 3), n + 2).join('\n');   // 单点引用给 ±2
      const all = mc.join('\n');
      const cases = [[`抄对了 + 行号对（main.c:${at}）`, echoVerdict(all, Q, win(at)), null, false],
                     [`抄对了 + 行号指到 ${far}（真错形状）`, echoVerdict(all, Q, win(far)), 'wrong-line', false],
                     // 第三条顺带测**取引号**这一步：取不出来的话 fake 是 undefined，脚本会直接崩，
                     // 而不是悄悄少一条对照（"计数地板"那一族）。
                     ['文件里没有这句（转述，不许判红）',
                      echoVerdict(all, echoQuoteSpans('回声写着 ' + QF)[0].text, win(at)), 'absent', false]];
      for (const [name, got, want] of cases) {
        d5dRun++;
        console.log(`  ${got === want ? 'PASS' : 'FAIL'} D5d ${name}：实测 ${got === null ? '放行' : got}`);
        if (got === want) e5d++;
      }
      // 配对本身也要有牙：文档的实际写法是"回声紧跟引用"，配错就等于判错。
      // A 行 = 应当配上；B 行 = 表格分列写法，**不许**配（第一版的假红全出自这一形状）。
      const rowA = `必须拒：\`${Q}\`（\`main.c:${at}\`）`;
      const rowB = `| 5 | \`stop\` → \`play\` | 看到 \`${Q}\` | 出口在 \`main.c:${at}\` |`;
      const pairA = (() => { const m = assignEchoes(rowA); return m.size === 1 && [...m.values()][0][0] === Q; })();
      const pairB = assignEchoes(rowB).size === 0;
      for (const [name, got, want] of [['引用紧跟回声 ⇒ 配对成功', pairA, true],
                                       ['回声与引用分处两列 ⇒ 不配对（不判）', pairB, true]]) {
        d5dRun++;
        console.log(`  ${got === want ? 'PASS' : 'FAIL'} D5d 配对 ${name}`);
        if (got === want) e5d++;
      }
    } else {
      console.log('  FAIL D5d 对照没跑起来（回声行不唯一或找不到 ⇒ 判据失效要当场暴露）');
      d5dRun = 1;
    }
  } else {
    console.log('  FAIL D5d 读不到 src/ps/main.c ⇒ 对照不作数');
    d5dRun = 1;
  }
  // 计数地板：8 = 锚点 2 + D5b 3 + 硬错 3；D5d 五条（判 3 + 配对 2）一条都不能少跑。
  // 8 → 10：本轮给厂商豁免加了两条对照（包内兜底 + 反买通），条数涨了就改这里，
  //  否则新增的对照会被"够数就行"的旧期望静默放过（#194 那一族的计数地板）。
  return pass + b5 + e5d === 10 + 5 && d5dRun === 5 ? 0 : 1;
}

// 每个被引文件"认识的符号"全集：锚点必须先过这一关，才有资格判红（理由见 check 里那段注释）。
function buildWords(linesByFile) {
  const m = new Map();
  for (const [k, ls] of linesByFile) m.set(k, new Set(ls.join('\n').match(IDENT) || []));
  return m;
}

const args = new Set(process.argv.slice(2));
if (args.has('--self')) process.exit(selfTest(loadCode()));

const code = loadCode();
const docs = mdFiles();
const res = check(code, buildWords(code), docs);
// 反买通那条**必须进硬错集合**（否则"名单被污染"只会打印一行而退出码还是 0）
res.fails.push(...vendorBuyoff(code));
const { fails, soft, needs, oks, skipped, echoNeed } = res;
const listN = 20;
const optVal = (name, dflt) => {
  const a = process.argv.find((x) => x.startsWith(name + '='));
  return a ? (Number(a.split('=')[1]) || dflt) : dflt;
};
console.log(`D5 引用核对：扫 ${docs.length} 份交付文档（report/log 与 report/study 的追加式/笔记档案不参与）⇒ 硬错 ${fails.length} 条（文件不在树里 / 行号越过文件末尾 / D5b 例化者列指错 / D5d 逐字抄的回声对不上）`
  + `；锚点命中 ${oks.length} 条；锚点候选 ${soft.length} 条；取不出代码锚点 ${needs.length} 条；回声转述待人看 ${echoNeed.length} 条；厂商树引用 ${skipped} 条不参与`);
if (fails.length) { console.log('\n--- 硬错（必定是坏引用）---'); fails.slice(0, listN).forEach((f) => console.log('  ' + f)); if (fails.length > listN) console.log(`  …还有 ${fails.length - listN} 条`); }
if (args.has('--list-soft')) {
  const n = optVal('--list-soft', 20);
  console.log('\n--- 锚点候选（**不判红**：文档常指向"那一处所在的函数开头"，逐条要人读）---');
  soft.slice(0, n).forEach((f) => console.log('  ' + f));
  if (soft.length > n) console.log(`  …还有 ${soft.length - n} 条`);
}
if (args.has('--list-need')) {
  const n = optVal('--list-need', 20);
  console.log('\n--- 需人看（句子里没有任何被引文件认识的符号）---');
  needs.slice(0, n).forEach((f) => console.log('  ' + f));
  if (needs.length > n) console.log(`  …还有 ${needs.length - n} 条`);
}
if (args.has('--list-echo')) {
  const n = optVal('--list-echo', 20);
  console.log('\n--- 回声转述（D5d 里"这个文件根本没有这一句"那一支，**不判红**：可能是转述，也可能引错了文件）---');
  echoNeed.slice(0, n).forEach((f) => console.log('  ' + f));
  if (echoNeed.length > n) console.log(`  …还有 ${echoNeed.length - n} 条`);
}
console.log('\nD5: ' + (fails.length ? 'RED' : 'CLEAN')
  + `（退出码只由硬错决定；soft ${soft.length} 条是给人排队的候选，拿它批量改行号 = #122 警告的那种坏主意）`);
process.exit(fails.length ? 1 : 0);
