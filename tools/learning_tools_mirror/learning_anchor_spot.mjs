// 第二层：语义锚点抽查。第一层只证明"那一行存在且非空"，这一层证明
// "文中反引号里抄来的那段代码/原文，确实落在被点名的那一行附近"。
// 抓的是"文件对、行号错"这一类第一层看不见的错。
// 用法：node build/learning_anchor_spot.mjs [目录=LEARNING] [窗口=6]
import fs from 'node:fs';
import path from 'node:path';

const ROOT = process.argv[2] || 'LEARNING';
const WIN = Number(process.argv[3] || 6);
const HEADS = ['src/', 'sim/', 'build/', 'board/', 'data/', 'report/', 'skills/', 'study_docs/'];
const EXT = 'md|mjs|txt|rpt|csv|xdc|bif|bin|bit|elf|xsa|tcl|sh|out|log|py|ld|v|c|h';
// 行号区间允许 ASCII `-` 与破折号 `–` 两种写法。文件名允许只写基名（`pl_video_top.v:736`）——
// 这类简写在正文里很常见，若只认带目录的整路径，片段就会串到同行后一条整路径上去，造出成片假错。
const CITE = new RegExp('((?:[A-Za-z0-9_./-]+/)?[A-Za-z0-9_.+-]+\\.(?:' + EXT + '))(?![A-Za-z0-9._]):(\\d+)(?:[-\u2013](\\d+))?', 'g');
// 反引号里"像代码"的片段：含 ASCII 字母数字、长度 ≥8、不含空格以外的中文
const QUOT = /`([^`\n]{8,120})`/g;
const CODEISH = /^[A-Za-z0-9_./()[\]<>&|+\-*=#:,%'"{} ]+$/;

// 基名 → 仓库内路径。唯一命中才用；多份同名或找不到就跳过这一对，并计数印出来（不静默）。
const byBase = new Map();
for (const h of HEADS) {
  const walk = (d) => {
    let es;
    try { es = fs.readdirSync(d, { withFileTypes: true }); } catch { return; }
    for (const e of es) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p);
      else {
        if (!new RegExp('\\.(' + EXT + ')$').test(e.name)) continue;
        if (!byBase.has(e.name)) byBase.set(e.name, []);
        byBase.get(e.name).push(p.split(path.sep).join('/'));
      }
    }
  };
  walk(h.replace(/\/$/, ''));
}
let ambig = 0, unres = 0;
function resolve(rel) {
  if (rel.includes('/')) return fs.existsSync(rel) ? rel : null;
  const c = byBase.get(rel);
  if (!c) { unres++; return null; }
  if (c.length > 1) { ambig++; return null; }
  return c[0];
}


const cache = new Map();
function linesOf(p) {
  if (!cache.has(p)) { try { cache.set(p, fs.readFileSync(p, 'utf8').split(/\r?\n/)); } catch { cache.set(p, null); } }
  return cache.get(p);
}

let judged = 0, hit = 0, pipeHit = 0, coverHit = 0, sameLineHit = 0, miss = 0, skipped = 0, bareGot = 0, bareLoose = 0;
const soft = [];
// 折叠口径有两档：`flat` 只并空白，`pipe` 再把表格竖线也当空白——工具报告的表行长这样
// `| Total On-Chip Power (W)  | 2.391        |`，正文抄它时按书写习惯去掉了竖线。
const flat = (s) => s.replace(/\s+/g, ' ').trim();
const pipe = (s) => s.replace(/[|\s]+/g, ' ').trim();
/** 第三档（弱一档，单独计数并打印）：把抄文拆成记号（长度 ≥2 的字母数字下划线串），要求窗口里每一个都出现。
 *  正文习惯用 `IMG_W=512`、`.rd_clk(clk)` 这种省略写法抄代码，逐字子串会误伤；这一档只放弃"相邻与次序"，
 *  不放弃"点名的东西在那一行附近"——行号漂了照样掉进 miss 队列。 */
const covers = (qt, winP) => {
  const toks = pipe(qt).split(/[^A-Za-z0-9_]+/).filter((t) => t.length >= 2);
  return toks.length > 0 && toks.every((t) => winP.includes(t));
};
const bad = [];
for (const f of fs.readdirSync(ROOT).filter((x) => x.endsWith('.md')).sort()) {
  const txt = fs.readFileSync(path.join(ROOT, f), 'utf8').split(/\r?\n/);
  txt.forEach((line, i) => {
    const full = [...line.matchAll(CITE)];
    if (!full.length) return;
    // 「`:107-117`」这种只写行号不写文件的续接引用：文件取同行**在它前面**最近的那条整路径。
    // 不认它，前面那段抄文就会配到同一句里更靠后的另一条引用上，把证据挪到别的文件头上。
    const bare = [...line.matchAll(/`:(\d+)(?:[-\u2013](\d+))?`/g)];
    const cites = [...full, ...bare.map((m) => {
      let owner = null;
      for (const c of full) { if (c.index < m.index) owner = c; else break; }
      if (!owner) { bareLoose++; return null; }
      bareGot++;
      return { 0: m[0], 1: owner[1], 2: m[1], 3: m[2], index: m.index };
    }).filter(Boolean)].sort((a, b) => a.index - b.index);
    // 同行其他"路径:行号"本身也写成反引号，它们不是被抄来的代码片段；带 / 的整串一律不当片段
    const citeTokens = new Set(cites.map((c) => c[0]));
    // 只把"像从某一整行里抄下来的片段"当锚点：含代码运算符/括号，且不是裸文件名。
    // 散文里点名 `arp_rx.v` 这种不是抄文，配到同行别的 cite 上只会造出假错。
    const QUOTED_LINE = /[=&(){}[\]<>|]/;
    const BARE_NAME = /^[A-Za-z0-9_.-]+\.(?:v|md|mjs|py|c|h|tcl|xdc|sh|csv|txt|rpt|log|out|bit|bin|elf|xsa|ld|bif)$/;
    const quotes = [...line.matchAll(QUOT)].map((m) => ({ t: m[1].trim(), at: m.index }))
      .filter((q) => CODEISH.test(q.t) && /[A-Za-z]{3}/.test(q.t))
      .filter((q) => !q.t.includes('/') && !q.t.includes('\\'))
      .filter((q) => !citeTokens.has(q.t))
      .filter((q) => !BARE_NAME.test(q.t) && QUOTED_LINE.test(q.t));
    if (!quotes.length) return;
    // 配对规矩：一段抄文配的是**跟在它后面**的那个"路径:行号"（这些文档写的是 `片段`（来源：f:行））。
    // 配"最近的一个"会把同行另一段的证据挪到这一段头上，制造成片假错。
    const pairs = [];
    for (const q of quotes) {
      const after = cites.find((c) => c.index > q.at + q.t.length);
      if (after) pairs.push([q.t, after]);
    }
    if (!pairs.length) return;
    // 一档判定：0=不在窗口内，1=逐字，2=折竖线，3=记号齐
    const tierAt = (qt, L, n, hi) => {
      const lo = Math.max(0, n - 1 - WIN), up = Math.min(L.length, hi + WIN);
      const body = L.slice(lo, up).join('\n');
      if (flat(body).includes(flat(qt))) return 1;
      const bodyP = pipe(body);
      if (bodyP.includes(pipe(qt))) return 2;
      return covers(qt, bodyP) ? 3 : 0;
    };
    for (const [qt, c] of pairs) {
      const rel = resolve(c[1]);
      if (!rel) continue;
      if (!HEADS.some((h) => rel.startsWith(h))) continue;
      const L = linesOf(rel);
      if (!L) { skipped++; continue; }
      const n = Number(c[2]), hi = c[3] ? Math.max(Number(c[3]), n) : n;
      judged++;
      const t = tierAt(qt, L, n, hi);
      if (t === 1) hit++;
      else if (t === 2) pipeHit++;
      else if (t === 3) coverHit++;
      else {
        // 正文一句里并列多个来源时（`片段`（A:1；B:2）），"跟在后面的那条"可能不是这条抄文的出处。
        // 第四档：同行**任一**引用的窗口里能找到就算，单独计数打印——它只放弃"配到哪一条"，
        // 不放弃"点名的东西在不在被点名的地方"，所以行号真漂了仍然掉进 miss。
        let alt = 0, altAt = '';
        for (const o of cites) {
          if (o === c) continue;
          const oRel = resolve(o[1]);
          if (!oRel || !HEADS.some((h) => oRel.startsWith(h))) continue;
          const oL = linesOf(oRel);
          if (!oL) continue;
          const on = Number(o[2]), oh = o[3] ? Math.max(Number(o[3]), on) : on;
          const ot = tierAt(qt, oL, on, oh);
          if (ot) { alt = ot; altAt = `${oRel}:${on}`; break; }
        }
        if (alt) { sameLineHit++; soft.push(`${f}:${i + 1}  片段"${qt.slice(0, 30)}" 严格配到 ${rel}:${n} 不中，改由同行 ${altAt} 支撑（第${alt}档）`); continue; }
        const somewhere = L.findIndex((x) => pipe(x).includes(pipe(qt)));
        miss++;
        bad.push(`${f}:${i + 1}  ${rel}:${n}  片段"${qt.slice(0, 34)}" ${somewhere >= 0 ? `在该文件第 ${somewhere + 1} 行（行号可疑）` : '整份文件里没有'}`);
      }
    }
  });
}
console.log(`语义锚点抽查  判=${judged}（逐字=${hit} +折竖线=${pipeHit} +记号齐=${coverHit} +同行他条引用支撑=${sameLineHit} +可疑待读=${miss}，五档相加=${hit + pipeHit + coverHit + sameLineHit + miss}）  跳过(件不在)=${skipped}  基名多义未判=${ambig}  基名查无未判=${unres}  续接行号引用认了=${bareGot} 无同行整路径=${bareLoose}  窗口=±${WIN} 行`);
if (soft.length) {
  console.log(`--- 第四档明细（前 12 条：严格配对不中、由同行另一条引用支撑，读一眼确认没挪错证据）---`);
  for (const s of soft.slice(0, 12)) console.log(s);
}
if (bad.length) {
  console.log('--- 明细（最多 40 条）---');
  for (const b of bad.slice(0, 40)) console.log(b);
  if (bad.length > 40) console.log(`…另有 ${bad.length - 40} 条`);
}
process.exit(0);
