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
//   node src/host/line_cite_check.mjs --list-need 50
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

function check(linesByFile, wordsByFile, docs) {
  // hard = 机器能单独判定的那两类（引的文件不在树里 / 行号越过文件末尾）——这些**必定**是坏引用。
  // soft = "锚点不在那几行里"：它**不能**单独判"文档错了"，因为文档常指向"那一处所在的函数开头"
  //   而不是语句本身（第一版实测：把 soft 当红报出 341 条，逐条抽读后大部分是这个形状，不是 341 个文档 bug）。
  //   所以 soft 只作为**排好序的候选清单**输出，不决定退出码，也不进门禁（#122 自己写的警告：
  //   "把本来就已经错的引用改成另一个错的数字，比不动更坏"）。
  const fails = [], soft = [], needs = [], oks = [];
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
        const r = nearHit(tgt, from, to, live);
        if (r.ok) oks.push(`${rel}:${idx + 1}  ${m[0]}  锚点 ${r.anchor}`);
        else soft.push(`${rel}:${idx + 1}  ${m[0]}  锚点 ${live.slice(0, 3).join('/')}… 不在 ${r.lo}-${r.hi} 行里`);
      }
    });
  }
  return { fails, soft, needs, oks, skipped };
}

function resolveTarget(cited, linesByFile) {
  if (linesByFile.has(cited)) return cited;
  const base = path.basename(cited);
  let hit = null, n = 0;
  for (const k of linesByFile.keys()) if (k === base || k.endsWith('/' + base)) { hit = k; n++; }
  return n === 1 ? hit : (hit || (linesByFile.has(cited) ? cited : null));
}

// 厂商树里的文件名：文档会引 `xsdps.c:156-159` 这种驱动行号，那些文件不在"我写的东西"范围，
// 但也不该被判成"文件在树里找不到"——那是我的扫描范围，不是文档的错。
const VENDOR = new Set();

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
  // 硬错那一层也要能红：两条必定坏的必须被认出来，一条"越过 200 但在长文件里合法"的不许误报。
  // 说清楚强度差别：这里证明的是**判据还在跑**（以及被引文件真的被读进来了）；
  // 它真正的红→绿凭据是今晚那一次——修之前全树报 7 条硬错、逐条改对之后报 0 条（ISSUES #122 收口段）。
  const lm = code.get('src/rtl/eth/link_monitor.v');
  const hardCases = [
    ['越过 EOF', resolveTarget('link_monitor.v', code) !== null && 9999 > lm.length, true],
    ['文件不在树里', resolveTarget('no_such_file_zzz.v', code) === null && !VENDOR.has('no_such_file_zzz.v'), true],
    ['同一行号在长文件里合法（不许误报）', 900 > code.get('src/rtl/top/pl_video_top.v').length, false],
  ];
  for (const [name, got, want] of hardCases) {
    console.log(`  ${got === want ? 'PASS' : 'FAIL'} 硬错判据 ${name}：${got === want ? '符合预期' : '不符合预期'}`);
    if (got === want) pass++;
  }
  return pass === 5 ? 0 : 1;
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
const { fails, soft, needs, oks, skipped } = check(code, buildWords(code), docs);
const listN = 20;
const optVal = (name, dflt) => {
  const a = process.argv.find((x) => x.startsWith(name + '='));
  return a ? (Number(a.split('=')[1]) || dflt) : dflt;
};
console.log(`D5 引用核对：扫 ${docs.length} 份交付文档（report/log/ 那四本追加式档案不参与）⇒ 硬错 ${fails.length} 条（文件不在树里 / 行号越过文件末尾）`
  + `；锚点命中 ${oks.length} 条；锚点候选 ${soft.length} 条；取不出代码锚点 ${needs.length} 条；厂商树引用 ${skipped} 条不参与`);
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
console.log('\nD5: ' + (fails.length ? 'RED' : 'CLEAN')
  + `（退出码只由硬错决定；soft ${soft.length} 条是给人排队的候选，拿它批量改行号 = #122 警告的那种坏主意）`);
process.exit(fails.length ? 1 : 0);
