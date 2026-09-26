#!/usr/bin/env node
/**
 * pipe_len_check.mjs —— `pipe` 这一条命令的"唯一口径"离线核对（不碰板子、不碰串口）
 *
 * 2026-09-26（#66）之后这件事的**依据换了**，所以本文件也换了地基：
 *   V7 那五位（`gpio_o[4:0]`，gray/binary/blur/sobel/invert）在 RTL 里已经整个删掉 ——
 *   `effect_ctrl.v` 的兜底合流、`pl_video_top.v` / `system_top.v` / `pl_demo_top.v` 的入口一起退，
 *   九级控制字 `stage_sel` 成了唯一的一套效果口径。PS 侧现在只认**九位串**：
 *   给五位就**一个位都不写**，只回一句"等价的九位是 pipe ……"。
 *   ⇒ 上一版判据赖以成立的那张"RTL 里的五位→九位翻译表"不复存在。再拿正则去
 *     `effect_ctrl.v` 里找 `legacy_sel[K] = en_sync[J];` 就是一条永远红的死判据，
 *     所以这里删掉的是**那张表**，不是判据：位号的事实来源改成一份（proc_pipeline.v），
 *     其余三份抄件（固件宏 / 名字表 / 串口句子）与它两两对。
 *
 * 四组判据（A/B/C/D），**没有一个位号写在本文件里** —— 位号从 RTL 抠、顺序句从固件抠、
 * 行为由现编的真函数给：
 *   A 位号四份一致：`proc_pipeline.v` 文件头那张 `stage_sel[k]` 位定义表（唯一事实来源）
 *     ↔ main.c 的 `SEL_*` 宏 ↔ `SEL_NAME[9]` 的下标 ↔ 串口那两句"九位一位一级"顺序句子
 *     （`cmd_help` 与 `apply_pipe_bits` 的拒绝消息各一句）。名字对名字、位号对位号。
 *   B 长度与写口：把 `parse_bits` / `legacy_to_sel` / `apply_pipe_bits` **原文抠出来用宿主 gcc
 *     现编**（沿用本文件旧版与 `temp_formula_check.mjs` 的规矩：在测试里重写一份实现，等于把
 *     "两处各说一遍"这个病搬进判据）。跑出来必须是"只有九位那一条路写寄存器；五位一条一个位
 *     都不写、只打印一串正好 9 个字符的等价写法；其余长度 parse 就 -1"。再加一条结构账：
 *     `apply_pipe_bits` 里唯一那个 `ctrl_set_sel` 的守卫条件必须只比 `n` 与 9，
 *     并且 `legacy_to_sel` 到 `return` 之间不许出现 `ctrl_set_sel`（= 五位分支真的不写）。
 *   C 口径同一句：`pipe` 动词的拒绝消息与 `cmd_help` 那一句必须说**同一条长度规则**
 *     （九位生效 / 五位只给翻译 / 其余一律拒 / 不许再出现"只收 5 或 9"那种旧口径）。
 *   D 退役不退半截：`effect_ctrl.v` 的**代码**（先把注释剥掉再找）里不许还有五位宽的输入端口、
 *     不许还有 `effect_en` 这个名字、不许还有"新字为 0 时顶上"那种合流写法；并且九位那一份
 *     必须还在（不然这条判据就是在空集上过）。
 *     注释里写"五位删了"是**正当的过去式**，不许误报（--self 里就有这条对照）；
 *     反过来"仍然在用那五位"这种现在时的注释只报 WARN —— 那是文档账，判红会把真红埋掉。
 *
 * 每条判据都配反例：`--self` 拿合成输入喂**同一批**判据函数，要求"造的坏必须被抓、
 * 正当输入不许被咬"（形状见 `doc_currency_check.mjs` 的 --self 块）。
 *
 * 用法：
 *   node src/host/pipe_len_check.mjs            判真树
 *   node src/host/pipe_len_check.mjs --self     判据自己的反例（该红的红了才算真判据）
 */
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const C_SRC = 'src/ps/main.c';
const RTL_PIPE = 'src/rtl/process/proc_pipeline.v';
const RTL_CTRL = 'src/rtl/process/effect_ctrl.v';
const RTL_TOPS = ['src/rtl/top/pl_video_top.v', 'src/rtl/top/system_top.v', 'src/rtl/top/pl_demo_top.v'];
const CC = process.env.CC || 'gcc';
const NO_WRITE = 0xDEAD;            // 被改过就说明"拒了还写寄存器"

/* ZH2EN / MACRO2EN 是本文件里唯一两处"我把名字对上"的地方 —— **只许写名字，不许写位号**
 * （位号一律从 RTL 抠，见 A 组）。RTL 换中文名或固件换宏名就改这里；改错了会由 A 组报出来。 */
const ZH2EN = {
  '灰度': 'gray', '反色': 'invert', '3×3 模糊': 'blur', '3×3 锐化': 'sharpen',
  'Sobel': 'sobel', '二值化': 'binary', '二值化判决反相': 'bin_pol', '腐蚀': 'erode', '膨胀': 'dilate',
};
const MACRO2EN = {
  SEL_GRAY: 'gray', SEL_INVERT: 'invert', SEL_BLUR: 'blur', SEL_SHARP: 'sharpen', SEL_SOBEL: 'sobel',
  SEL_BIN: 'binary', SEL_BIN_POL: 'bin_pol', SEL_ERODE: 'erode', SEL_DILATE: 'dilate',
};

const read = (p) => readFileSync(p, 'utf8').replace(/^\ufeff/, '').replace(/\r\n/g, '\n');

/* ============================ 抠（纯函数：吃文本，吐结构） ============================ */

/* proc_pipeline.v 文件头：`[0] 灰度  [1] 反色 …`。一格后面常跟着说明（"（只在 [5]=1 时有意义）"、
 * "—— [7] 与 [8] 同时为 1 …"），所以按"最长前缀命中字典"取名字，并且只扫那一段连续的注释行。 */
const ZH_KEYS = Object.keys(ZH2EN).sort((a, b) => b.length - a.length);
function rtlBitTable(rtlText) {
  const lines = rtlText.split('\n');
  const i0 = lines.findIndex((l) => /stage_sel\s*位定义/.test(l));
  if (i0 < 0) return null;
  const block = [];
  for (let i = i0; i < lines.length; i++) {
    const l = lines[i].trim();
    if (i > i0 && !l.startsWith('//')) break;
    block.push(l);
  }
  const map = {};
  for (const m of block.join('\n').matchAll(/\[(\d)\]\s*([^\[\r\n]+)/g)) {
    const nm = m[2].trim();
    const hit = ZH_KEYS.find((k) => nm.startsWith(k));
    if (hit !== undefined && map[ZH2EN[hit]] === undefined) map[ZH2EN[hit]] = { bit: Number(m[1]), zh: hit };
  }
  return map;
}

/* 固件里的三份抄件 */
const selMacros = (src) => [...src.matchAll(/^#define\s+(SEL_\w+)\s+\(1u\s*<<\s*(\d+)\)/gm)]
  .map((m) => ({ macro: m[1], bit: Number(m[2]) }));
function selNameTable(src) {
  const t = src.match(/static const char \*SEL_NAME\[(\d+)\]\s*=\s*\{([^}]*)\}/);
  return t ? { size: Number(t[1]), names: [...t[2].matchAll(/"([^"]*)"/g)].map((x) => x[1]) } : null;
}
/* 一条 xil_printf 可能写成好几段相邻字符串（C 会自动拼），所以按"整个调用"取字面量再拼起来 */
function printfLines(text) {
  const out = [];
  for (const m of text.matchAll(/xil_printf\s*\(/g)) {
    let i = m.index + m[0].length, depth = 1, inStr = false;
    while (i < text.length && depth > 0) {
      const c = text[i];
      if (inStr) { if (c === '\\') i++; else if (c === '"') inStr = false; }
      else if (c === '"') inStr = true;
      else if (c === '(') depth++;
      else if (c === ')') depth--;
      i++;
    }
    const call = text.slice(m.index, i);
    const lit = [...call.matchAll(/"((?:[^"\\]|\\.)*)"/g)].map((x) => x[1].replace(/\\"/g, '"'));
    if (lit.length) out.push(lit.join(''));
  }
  return out;
}
/* "gray/invert/…/dilate" 这种斜杠顺序句：每一项都必须是已知算法名，否则不认（防抓到大段文字） */
function orderSentences(text, known) {
  const out = [];
  for (const line of printfLines(text)) {
    for (const m of line.matchAll(/([a-z_]+(?:\/[a-z_]+){3,})/g)) {
      const items = m[1].split('/');
      if (items.every((s) => known.has(s))) out.push(items);
    }
  }
  return out;
}
/* 函数原文（括号配对数出来的，不是正则截断的）；跳过前向声明与调用点 */
function fnText(text, sig) {
  let from = 0;
  for (;;) {
    const start = text.indexOf(sig, from);
    if (start < 0) return null;
    const open = text.indexOf('{', start + sig.length);
    from = start + 1;
    if (open < 0) continue;
    if (/\S/.test(text.slice(start + sig.length, open))) continue;
    let depth = 0, i = open;
    for (; i < text.length; i++) {
      if (text[i] === '{') depth++;
      else if (text[i] === '}') { depth--; if (depth === 0) break; }
    }
    return text.slice(text.lastIndexOf('\n', start) + 1, i + 1);
  }
}
/* `pipe` 动词那一段（含它的拒绝消息） */
function pipeVerbText(src) {
  const m = src.match(/if\s*\(\s*ci_eq\s*\(\s*tk\[0\]\s*,\s*"PIPE"\s*\)\s*\)\s*\{/);
  if (!m) return null;
  let depth = 0, i = src.indexOf('{', m.index);
  for (; i < src.length; i++) {
    if (src[i] === '{') depth++;
    else if (src[i] === '}') { depth--; if (depth === 0) break; }
  }
  return src.slice(m.index, i + 1);
}
const stripVComments = (t) => t.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/\/\/[^\n]*/g, ' ');

/* ============================ 判（纯函数：吃结构/文本，吐行） ============================
 * 行 = { sev: 'FAIL' | 'WARN', text }。FAIL 进退出码，WARN 只报不判（见文件头 D 组那条）。 */
const F = (text) => ({ sev: 'FAIL', text });
const W = (text) => ({ sev: 'WARN', text });
const bad = (rows) => rows.filter((r) => r.sev === 'FAIL');

/* ---- A：位号四份一致 ---- */
function judgeA(rtl, macros, nameTab, orders, where) {
  const rows = [];
  const rtlN = rtl ? Object.keys(rtl).length : 0;
  if (!rtl || rtlN !== 9)
    return [F(`A 位定义表没读全：从 ${RTL_PIPE} 的 stage_sel 位定义那一段只抠到 ${rtlN} 个（要 9 个）` +
              ` —— 表改了写法就同步改本文件，别把判据删掉`)];
  if (new Set(Object.values(rtl).map((v) => v.bit)).size !== 9) rows.push(F('A RTL 位定义表里两位撞在同一个 bit 上'));
  if (macros.length !== 9)
    rows.push(F(`A ${C_SRC} 的 SEL_* 宏抠到 ${macros.length} 个（要 9 个）—— 改了写法就同步改本文件`));
  if (!nameTab || nameTab.size !== 9 || nameTab.names.length !== 9)
    rows.push(F(`A SEL_NAME 不是 9 项（声明 ${nameTab ? nameTab.size : '读不到'} 项、字面量 ${nameTab ? nameTab.names.length : 0} 个）`));
  for (const m of macros) {
    const en = MACRO2EN[m.macro];
    if (en === undefined) { rows.push(F(`A 固件宏 ${m.macro} 不在 MACRO2EN 里（新增了一位？那 RTL 也得有它）`)); continue; }
    if (rtl[en] === undefined) { rows.push(F(`A ${m.macro}→${en}，但 RTL 位定义表里没有 ${en} 这一位`)); continue; }
    if (rtl[en].bit !== m.bit) rows.push(F(`A 位号 ${en}：RTL 是 bit${rtl[en].bit}（[${rtl[en].zh}]），${C_SRC} 的 ${m.macro} 是 bit${m.bit}`));
    if (nameTab && nameTab.names[m.bit] !== undefined && nameTab.names[m.bit] !== en)
      rows.push(F(`A bit${m.bit}：${m.macro} 说的是 ${en}，SEL_NAME[${m.bit}] 却写着 "${nameTab.names[m.bit]}"`));
  }
  if (nameTab) nameTab.names.forEach((n, i) => {
    if (rtl[n] === undefined) rows.push(F(`A SEL_NAME[${i}]="${n}" 不是 RTL 位定义表里的算法名`));
    else if (rtl[n].bit !== i) rows.push(F(`A 位号 ${n}：RTL 是 bit${rtl[n].bit}，SEL_NAME 却把它放在第 ${i} 格`));
  });
  /* 串口那两句顺序句子：一句都不许少（少一句 = 少一处抄件没被对过） */
  for (const [tag, items] of Object.entries(orders)) {
    const w = where[tag] || tag;
    if (!items) { rows.push(F(`A ${w} 里没找到九位顺序句子（改了写法就同步改本文件，别把判据删掉）`)); continue; }
    if (items.length !== 9) { rows.push(F(`A ${w} 的顺序句子只有 ${items.length} 项：${items.join('/')}`)); continue; }
    items.forEach((h, i) => {
      if (rtl[h] === undefined) rows.push(F(`A ${w} 第 ${i + 1} 项 "${h}" 不在 RTL 名字里`));
      else if (rtl[h].bit !== i) rows.push(F(`A 位号 ${h}：RTL 是 bit${rtl[h].bit}，${w} 却把它念成第 ${i + 1} 位`));
      if (nameTab && nameTab.names[i] !== h) rows.push(F(`A ${w} 第 ${i + 1} 项 "${h}" ≠ SEL_NAME[${i}]="${nameTab.names[i]}"`));
    });
  }
  return rows;
}

/* ---- B：行为（现编的真函数跑出来的行）+ 一条结构账 ---- */
/* 用例表由"从文件里抠到的顺序 + RTL 位号"生成，期望值同样算出来 —— 本文件不写位号。 */
function buildCases(order, rtl) {
  const bit = (nm) => rtl[nm].bit;
  const cases = [];
  order.forEach((nm, i) => {
    const s = order.map((_, j) => (j === i ? '1' : '0')).join('');
    cases.push({ inp: s, kind: 'apply', wantSel: 1 << bit(nm), what: `九位只点 ${nm}（串第 ${i + 1} 个字符 ⇒ bit${bit(nm)}）` });
  });
  const idx2sel = (idx) => idx.reduce((a, i) => a | (1 << bit(order[i])), 0);
  cases.push({ inp: '0'.repeat(9), kind: 'apply', wantSel: 0, what: '九位全旁路' });
  cases.push({ inp: '1'.repeat(9), kind: 'apply', wantSel: (1 << 9) - 1, what: '九位全开（PS 只管写位，形态学互斥是 PL 的事）' });
  const two = order.map((_, j) => (j === 0 || j === 7 ? '1' : '0')).join('');
  cases.push({ inp: two, kind: 'apply', wantSel: idx2sel([0, 7]), what: '跨级两位同点' });
  for (const s of ['11000', '01010', '00000', '10101'])
    cases.push({ inp: s, kind: 'five', what: '五位老写法：一个位都不许写，只许回一串等价九位' });
  for (const s of ['', '1', '11', '111', '1111', '111111', '00001100', '01010101', '1'.repeat(10), '1111a'])
    cases.push({ inp: s, kind: 'refuse', what: `长度 ${s.length}：parse 就 -1（不许被当成补零）` });
  return cases;
}
const wantNOf = (kind) => (kind === 'apply' ? 9 : kind === 'five' ? 5 : -1);
/* runs：[{c, n, applied, writes, sel, legacy, echo}] */
function judgeB(runs, guard, rtl, order) {
  const rows = [];
  const bitrev = (v) => { let r = 0; for (let i = 0; i < 9; i++) if (v & (1 << i)) r |= 1 << (8 - i); return r; };
  for (const r of runs) {
    const k = r.c.kind, wantN = wantNOf(k);
    if (r.n !== wantN) rows.push(F(`B "${r.c.inp}"（${r.c.what}）：parse_bits 给 n=${r.n}，期望 ${wantN}`));
    if (k === 'apply') {
      if (r.applied !== 1) rows.push(F(`B "${r.c.inp}"：九位是唯一的生效路径，apply_pipe_bits 却回 ${r.applied}`));
      if (r.writes !== 1 || r.sel !== r.c.wantSel)
        rows.push(F(`B "${r.c.inp}"（${r.c.what}）：写了 ${r.writes} 次、sel=${r.sel}，期望 sel=${r.c.wantSel}` +
                    `（期望是按 RTL 位定义表算的，不是抄固件实现）`));
    } else {
      if (r.applied === 1) rows.push(F(`B "${r.c.inp}"（${r.c.what}）：不该生效却生效了`));
      if (r.writes !== 0) rows.push(F(`B "${r.c.inp}"（${r.c.what}）：拒了还写寄存器（${r.writes} 次，sel=${r.sel}）`));
      if (k === 'five') {
        const g = [...r.echo.matchAll(/pipe\s+([01]+)(?![01])/g)].map((m) => m[1]);
        if (g.length !== 1) rows.push(F(`B "${r.c.inp}"：五位这条必须恰好打印**一串**等价九位，实际 ${g.length} 串（${g.join(' , ')}）`));
        else if (g[0].length !== order.length)
          rows.push(F(`B "${r.c.inp}"：提示串是 ${g[0].length} 个字符，不是 ${order.length} 个 ⇒ 照着敲还是错的（"${g[0]}"）`));
        else {
          /* 把提示串照着敲回去，应当得到固件自己说的那个等价字。对不上分两种：
           * 镜像 ⇒ 打印方向与命令读法反了；其余 ⇒ 翻译本身错了。
           * 这一条今天只报 WARN 不判红：**该修的是 main.c 的打印方向**，不是放松判据。
           * （apply_pipe_bits 现在 `for (i = 8; i >= 0; --i)` 打的是 MSB 左起，而 parse_bits
           *   读串是"第 i 个字符落第 i 位"= LSB 左起，见 COMMANDS.md 那张 000000000/100000000 表。） */
          const asInput = [...g[0]].reduce((a, ch, i) => (ch === '1' && rtl[order[i]] ? a | (1 << rtl[order[i]].bit) : a), 0);
          if (asInput !== r.legacy)
            rows.push(W(`B "${r.c.inp}" 的等价提示 "${g[0]}" 照着敲得到 ${asInput}，固件自己说的是 ${r.legacy}` +
                        `${asInput === bitrev(r.legacy) ? '（正好互为**镜像** ⇒ 提示的打印方向与 pipe 的读法相反）' : ''}` +
                        ` —— 修 main.c 之后请把这条从 WARN 升成 FAIL`));
        }
      }
    }
  }
  /* 结构账：唯一那个 ctrl_set_sel 的守卫只许比 n 与 9 */
  if (guard.nCalls !== 1) rows.push(F(`B apply_pipe_bits 里有 ${guard.nCalls} 处 ctrl_set_sel（要正好 1 处）—— 多一处就多一条没人记账的写入口`));
  for (const g of guard.guards) {
    const nums = (g.match(/\d+/g) || []).map(Number);
    if (!/\bn\b/.test(g) || nums.length !== 1 || nums[0] !== 9)
      rows.push(F(`B 生效那条路的守卫是「${g || '没有守卫，无条件写'}」：只许 n == 9，五位也不许混进来`));
  }
  if (guard.legacyMissing) rows.push(F('B apply_pipe_bits 里没有 legacy_to_sel 那一步：五位就没人告诉他该敲什么'));
  if (guard.legacyWrites) rows.push(F('B 五位那条分支里出现了 ctrl_set_sel ⇒ "只回一句等价九位"是假的'));
  return rows;
}
function applyGuard(applyText) {
  const t = String(applyText || '').replace(/\s+/g, ' ');
  const calls = [...t.matchAll(/ctrl_set_sel\s*\(/g)];
  const guards = [];
  for (const c of calls) {
    const before = t.slice(Math.max(0, c.index - 160), c.index);
    const ifs = [...before.matchAll(/if\s*\(([^)]*)\)/g)];
    for (let k = ifs.length - 1; k >= 0; k--) {
      const at = before.lastIndexOf(ifs[k][0]);
      if (!/}/.test(before.slice(at + ifs[k][0].length))) { guards.push(ifs[k][1].trim()); break; }
    }
    if (ifs.length === 0) guards.push('');
  }
  const li = t.indexOf('legacy_to_sel');
  const ret = li < 0 ? -1 : t.indexOf('return', li);
  return {
    nCalls: calls.length, guards,
    legacyMissing: li < 0,
    legacyWrites: li >= 0 && ret >= 0 && /ctrl_set_sel/.test(t.slice(li, ret)),
  };
}

/* ---- C：拒绝消息与 help 必须说同一条长度规则 ---- */
/* help 那一侧不是一行而是**好几行**（语法摘要、长度规则、屏上那一格的口径、旧写法清单），
 * 所以把 cmd_help 里所有谈到 pipe/位数的句子拼成一段再判 —— 拼的时候用句号隔开，
 * 免得判据的 [^。；] 窗口跨句抓到另一条命令里的字样。 */
const helpRuleText = (helpText) => printfLines(helpText).filter((s) => /pipe|Pipe|九位|五位/.test(s)).join('。');
function lengthClaims(text) {
  const t = text.replace(/\*\*/g, '').replace(/[\r\n]+/g, ' ');
  return {
    mentionsNine: /九位/.test(t),
    mentionsFive: /(五位|5 位)/.test(t),
    nineApplies: /只收\s*九位|只认\s*九位|九位[^。；]{0,16}(一位一级|生效)/.test(t),
    fiveIsTranslationOnly: /五位[^。；]{0,44}(等价|不生效|只回|老写法)/.test(t),
    /* 旧口径（"只收 5 或 9"）与任何"五位也生效"式的说法都算红 */
    fiveAlsoApplies: /只[收认]\s*[5五]/.test(t) || /[5五]\s*[或和与]\s*9/.test(t) ||
                     /长度只收[^。；]{0,10}[5五]/.test(t) || /也生效|同样生效|一样生效/.test(t),
    refusesTheRest: /(一律\s*(拒|不认)|其余[^。；]{0,8}一律)/.test(t),
  };
}
const CLAIM_KEYS = ['mentionsNine', 'mentionsFive', 'nineApplies', 'fiveIsTranslationOnly', 'fiveAlsoApplies', 'refusesTheRest'];
const WANT_CLAIMS = { mentionsNine: true, mentionsFive: true, nineApplies: true, fiveIsTranslationOnly: true, fiveAlsoApplies: false, refusesTheRest: true };
function judgeC(rejectMsg, helpMsg) {
  if (!rejectMsg || !helpMsg)
    return [F('C 没读到 pipe 动词的拒绝消息或 cmd_help 那一句（改了写法就同步改本文件，别把判据删掉）')];
  const a = lengthClaims(rejectMsg), b = lengthClaims(helpMsg);
  const rows = [];
  for (const [k, v] of Object.entries(WANT_CLAIMS)) {
    if (a[k] !== v) rows.push(F(`C pipe 的拒绝消息没满足「${k} = ${v}」：${rejectMsg.slice(0, 96)}`));
    if (b[k] !== v) rows.push(F(`C cmd_help 没满足「${k} = ${v}」：${helpMsg.slice(0, 96)}`));
  }
  for (const k of CLAIM_KEYS) if (a[k] !== b[k]) rows.push(F(`C 两处口径不同：「${k}」拒绝消息是 ${a[k]}，help 是 ${b[k]}`));
  return rows;
}

/* ---- D：五位那条路真的退干净了吗（抓"退了一半"） ---- */
function judgeD(ctrlText) {
  const code = stripVComments(String(ctrlText || ''));
  if (!/\bstage_sel\b/.test(code) || !/\[\s*8\s*:\s*0\s*\]/.test(code))
    return [F(`D ${RTL_CTRL} 的代码里找不到 [8:0] stage_sel —— 九级那一份唯一口径不见了（这一条不许在空集上过）`)];
  const rows = [];
  for (const p of [...code.matchAll(/\binput\b[^;]*;/g)].map((m) => m[0].replace(/\s+/g, ' ')))
    if (/\[\s*4\s*:\s*0\s*\]/.test(p)) rows.push(F(`D 还有五位宽的输入端口：${p}`));
  if (/\beffect_en/i.test(code)) rows.push(F('D 代码里还出现 effect_en（五位那个入口没删干净）'));
  if (/\blegacy/i.test(code)) rows.push(F('D 代码里还出现 legacy_* 这个名字（老五位的那条路还在？）'));
  /* "新字为 0 时顶上"那道合流：任何形式的合流/二选一都算没退 —— 唯一口径应当逐位直连 */
  const asg = code.match(/assign\s+stage_sel[^;]*;/);
  if (!asg) rows.push(F('D 读不到 `assign stage_sel = …` 那一行（改写了就去同步本文件）'));
  else if (/\|/.test(asg[0]) || /\?/.test(asg[0]))
    rows.push(F(`D stage_sel 那一行还是合流/条件式：${asg[0].replace(/\s+/g, ' ')}`));
  return rows;
}
/* 现在时的"还在用五位"注释 —— 只报，不判红（那是文档账）；过去式（"…一起删了"）不许被咬 */
const LIVE = /(仍然|还是|依旧|仍在|还有效|还在用|依然|都按|才是)/;
const PAST = /(删了|已删|删掉|退役|不再是|不再参与|不留|曾经|以前是)/;
const LEGACY_WORD = /(五位|5 个使能|effect_en|兜底|合流|en=)/;
function staleComments(namedTexts) {
  const rows = [];
  for (const [file, text] of Object.entries(namedTexts)) {
    String(text).split('\n').forEach((l, i) => {
      if (!/^\s*(\/\/|\*|\/\*)/.test(l)) return;                    // 只看注释行
      if (!LEGACY_WORD.test(l) || !LIVE.test(l) || PAST.test(l)) return;
      rows.push(W(`${file}:${i + 1} 注释还在用现在时说五位：${l.trim().slice(0, 92)}`));
    });
  }
  return rows;
}

/* ============================ 现编（B 组的真值来自这里） ============================ */
function harnessC(macros, fns) {
  return [
    '#include <stdio.h>',
    'typedef unsigned int u32;',
    '#define xil_printf printf',
    `static u32 g_sel = ${NO_WRITE}u;   /* 被改过就说明"拒了还写寄存器" */`,
    'static int g_writes = 0;',
    'static void ctrl_set_sel(u32 v) { g_sel = v & 0x1FFu; g_writes++; }',
    ...macros.map((d) => `#define ${d.macro} (1u << ${d.bit})`),
    fns.parse,
    fns.legacy,
    fns.apply,
    'int main(int argc, char **argv) {',
    '  u32 en = 0;',
    '  const char *in = (argc > 1) ? argv[1] : "";',
    '  int n = parse_bits(in, &en);',
    '  printf("@N %d %u\\n", n, en);',
    '  if (n > 0) { printf("@L %u\\n", legacy_to_sel(en)); printf("@A %d\\n", apply_pipe_bits(en, n)); }',
    '  else printf("@A -1\\n");',
    '  printf("@S %d %u\\n", g_writes, g_sel);',
    '  return 0;',
    '}',
  ].join('\n') + '\n';
}
function runHarness(macros, fns, cases) {
  const dir = mkdtempSync(join(tmpdir(), 'pipechk_'));
  const cfile = join(dir, 't.c'), exe = join(dir, process.platform === 'win32' ? 't.exe' : 't');
  writeFileSync(cfile, harnessC(macros, fns));
  execFileSync(CC, ['-O0', '-w', '-finput-charset=UTF-8', '-o', exe, cfile], { stdio: 'pipe' });
  return cases.map((c) => {
    const out = execFileSync(exe, [c.inp], { encoding: 'utf8', maxBuffer: 1 << 20 });
    let n = NaN, applied = NaN, writes = -1, sel = NO_WRITE, legacy = -1;
    const echo = [];
    for (const l of out.split(/\r?\n/)) {
      const t = l.trim();
      if (!t) continue;
      if (t.startsWith('@N ')) n = Number(t.split(/\s+/)[1]);
      else if (t.startsWith('@L ')) legacy = Number(t.split(/\s+/)[1]);
      else if (t.startsWith('@A ')) applied = Number(t.split(/\s+/)[1]);
      else if (t.startsWith('@S ')) { const a = t.split(/\s+/); writes = Number(a[1]); sel = Number(a[2]); }
      else echo.push(t);
    }
    return { c, n, applied, writes, sel, legacy, echo: echo.join(' ') };
  });
}

/* ============================ --self：判据自己的反例 ============================ */
const argv = process.argv.slice(2);
if (argv.includes('--self')) {
  const clone = (o) => JSON.parse(JSON.stringify(o));
  const say = (tag, rows, re = /FAIL/) => {
    const got = rows.filter((r) => re.test(r.sev)).length;
    console.log(`  ${got ? 'PASS' : 'FAIL'} ${tag}（命中 ${got} 条）`);
    for (const r of rows) console.log(`        ${r.sev} ${r.text.slice(0, 150)}`);
    return got ? 1 : 0;
  };
  const sayClean = (tag, rows) => {
    const got = bad(rows).length;
    console.log(`  ${got === 0 ? 'PASS' : 'FAIL'} ${tag}（误报 ${got} 条）`);
    for (const r of rows) console.log(`        ${r.sev} ${r.text.slice(0, 150)}`);
    return got === 0 ? 1 : 0;
  };
  const sayEmpty = (tag, rows) => {
    console.log(`  ${rows.length === 0 ? 'PASS' : 'FAIL'} ${tag}（多报 ${rows.length} 条）`);
    for (const r of rows) console.log(`        ${r.sev} ${r.text.slice(0, 150)}`);
    return rows.length === 0 ? 1 : 0;
  };
  const src = read(C_SRC), rtlText = read(RTL_PIPE), ctrlText = read(RTL_CTRL);
  const RT = rtlBitTable(rtlText), MD = selMacros(src), NT = selNameTable(src);
  const KNOWN = new Set(NT ? NT.names : []);
  const helpT = fnText(src, 'cmd_help(void)') || '', applyT = fnText(src, 'apply_pipe_bits(u32 b, int n)') || '';
  const parseT = fnText(src, 'parse_bits(const char *s, u32 *out)') || '';
  const legacyT = fnText(src, 'legacy_to_sel(u32 e)') || '';
  const ordHelp = orderSentences(helpT, KNOWN)[0] || null;
  const ordApply = orderSentences(applyT, KNOWN)[0] || null;
  const ORD = { help: ordHelp, apply: ordApply };
  const WH = { help: 'cmd_help', apply: 'apply_pipe_bits' };
  let n = 0;
  /* --self 的每一个反例都要拿这些当底子：抠不全就直接红，不许"少了几条对照也算全绿" */
  if (!RT || Object.keys(RT).length !== 9 || !NT || NT.names.length !== 9 || !ordHelp || !ordApply || !applyT || !parseT || !legacyT) {
    console.log(`  FAIL 输入没抠全：RTL ${RT ? Object.keys(RT).length : 0}/9、SEL_NAME ${NT ? NT.names.length : 0}/9、` +
                `顺序句 help=${ordHelp ? 1 : 0} apply=${ordApply ? 1 : 0}、函数 parse=${!!parseT} legacy=${!!legacyT} apply=${!!applyT}`);
    console.log('SELF: 有红（0 条） —— 植入反例全靠这些输入，抠不全时不许假绿');
    process.exit(1);
  }

  /* A：五种植入的坏 + 真树这一份当"不许误报"的对照 */
  const a1 = clone(RT); { const t = a1.blur.bit; a1.blur.bit = a1.sharpen.bit; a1.sharpen.bit = t; }
  n += say('A：RTL 把 blur/sharpen 两位对调 ⇒ 必须红', judgeA(a1, MD, NT, ORD, WH));
  const a2 = clone(NT); [a2.names[1], a2.names[2]] = [a2.names[2], a2.names[1]];
  n += say('A：SEL_NAME 把 invert/blur 两格对调 ⇒ 必须红', judgeA(RT, MD, a2, ORD, WH));
  n += say('A：help 那句少念一位（只剩八项）⇒ 必须红', judgeA(RT, MD, NT, { help: ordHelp.slice(0, 8), apply: ordApply }, WH));
  const a4 = clone(RT); a4.dilate = { bit: RT.gray.bit, zh: '膨胀' };
  n += say('A：RTL 里两位撞在同一个 bit ⇒ 必须红', judgeA(a4, MD, NT, ORD, WH));
  const a5 = MD.map((m) => (m.macro === 'SEL_SHARP' ? { macro: m.macro, bit: m.bit + 1 } : { ...m }));
  n += say('A：SEL_SHARP 宏挪一位（与 SEL_NAME / RTL 都不符）⇒ 必须红', judgeA(RT, a5, NT, ORD, WH));
  n += sayEmpty('对照：真树这一份 A 必须 0 条', judgeA(RT, MD, NT, ORD, WH));

  /* B：坏行为 + 坏守卫（期望值同样是算出来的，不是抄固件实现） */
  const order = ordHelp;
  const cs = buildCases(order, RT);
  const mk = (c, over) => ({ c, n: over.n !== undefined ? over.n : wantNOf(c.kind),
    applied: over.applied !== undefined ? over.applied : (c.kind === 'apply' ? 1 : 0),
    writes: over.writes !== undefined ? over.writes : (c.kind === 'apply' ? 1 : 0),
    sel: over.sel !== undefined ? over.sel : (c.kind === 'apply' ? c.wantSel : NO_WRITE),
    legacy: over.legacy !== undefined ? over.legacy : 0, echo: over.echo !== undefined ? over.echo : '' });
  const fiveCase = cs.find((c) => c.kind === 'five'), nineCase = cs.find((c) => c.kind === 'apply');
  const G0 = applyGuard(applyT);
  n += say('B：五位那条偷偷写了寄存器 ⇒ 必须红', judgeB([mk(fiveCase, { writes: 1, sel: 0x21, echo: '等价的九位是：pipe 000100001', legacy: 0x21 })], G0, RT, order));
  n += say('B：九位那条落到了别的位置上 ⇒ 必须红', judgeB([mk(nineCase, { sel: nineCase.wantSel << 1 })], G0, RT, order));
  n += say('B：等价提示只给了 5 个字符 ⇒ 必须红', judgeB([mk(fiveCase, { echo: '等价的九位是：pipe 11000' })], G0, RT, order));
  n += say('B：等价提示给了两串 ⇒ 必须红', judgeB([mk(fiveCase, { echo: 'pipe 000100001 pipe 000100001', legacy: 0x21 })], G0, RT, order));
  n += say('B：守卫写成 n == 5 || n == 9 ⇒ 必须红', judgeB([], applyGuard(applyT.replace('n == 9', 'n == 5 || n == 9')), RT, order));
  n += say('B：把守卫整个删掉（无条件写）⇒ 必须红', judgeB([], applyGuard(applyT.replace('if (n == 9) { ctrl_set_sel(b); return 1; }', 'ctrl_set_sel(b); return 1;')), RT, order));
  n += say('B：五位分支里也写寄存器（合流式实现）⇒ 必须红', judgeB([], applyGuard(applyT.replace('s = legacy_to_sel(b);', 's = legacy_to_sel(b); ctrl_set_sel(s);')), RT, order));
  n += sayEmpty('对照：真 apply_pipe_bits 的结构账必须 0 条', judgeB([], G0, RT, order));
  let realB;
  try {
    realB = judgeB(runHarness(MD, { parse: parseT, legacy: legacyT, apply: applyT }, cs), G0, RT, order);
  } catch (e) {
    realB = [F(`B 现编没跑成（${String(e && e.message).split('\n')[0].slice(0, 160)}）—— 编不过不算过`)];
  }
  n += sayClean('对照：真行为那 ' + cs.length + ' 条用例必须 0 条红（WARN 允许，见文件头）', realB);

  /* C：四种坏口径 + 真那一对 */
  const rej = printfLines(pipeVerbText(src) || '').find((s) => /长度/.test(s)) || '';
  const help = helpRuleText(helpT);
  n += say('C：拒绝消息退回旧口径「只收 5 或 9」⇒ 必须红', judgeC(rej.replace(/长度只收 \*\*九位\*\*/, '长度只收 **5 或 9**'), help));
  n += say('C：help 不说"其余长度一律拒"⇒ 必须红', judgeC(rej, help.replace(/其余长度一律拒/, '其余长度也行')));
  n += say('C：help 说五位也生效 ⇒ 必须红', judgeC(rej, help.replace('、不生效', '、也生效')));
  n += say('C：两处只剩一处（拒绝消息读不到）⇒ 必须红', judgeC('', help));
  n += sayEmpty('对照：真树那两句的 C 必须 0 条', judgeC(rej, help));

  /* D：四种"退了一半"+ 过去式注释不许误报 */
  n += say('D：effect_ctrl 加回一个五位输入端口 ⇒ 必须红',
    judgeD(ctrlText.replace(/module effect_ctrl \(/, 'module effect_ctrl (\n    input  wire [4:0] effect_en_async,')));
  n += say('D：加回"新字为 0 时顶上"那道合流 ⇒ 必须红',
    judgeD(ctrlText.replace('assign stage_sel   = sel_pix;', "assign stage_sel   = sel_pix | {4'd0, en_five};")));
  n += say('D：留一个 legacy_* 信号名当第二条路 ⇒ 必须红',
    judgeD(ctrlText.replace('wire [8:0] sel_pix', 'wire [8:0] legacy_pix;\n    wire [8:0] sel_pix')));
  n += say('D：把九位那一份唯一口径整个删掉（防"空集上判绿"）⇒ 必须红',
    judgeD('module effect_ctrl (input wire clk, input wire [7:0] t); endmodule'));
  n += sayEmpty('对照：真 effect_ctrl.v（注释里全是"五位删了"的过去式）必须 0 条', judgeD(ctrlText));
  n += say('D：现在时的"仍然用那五位"注释 ⇒ 必须被 staleComments 点名',
    staleComments({ fake: '//   stage_sel = 0  ⇒ effect_ctrl 的合流规则 ⇒ 仍然用上面那五位老使能' }), /WARN/);
  n += sayEmpty('对照：过去式的退役说明不许被 staleComments 咬',
    staleComments({ fake: '// V7 那五位 `effect_en` 的兜底合流与第二个出口在 2026-09-26 一起删了' }));
  const TOTAL = 27;
  const all = n === TOTAL;
  console.log(`${all ? `SELF: 全绿（${n} 条）` : `SELF: 有红（${n}/${TOTAL} 过）`} —— A 6 / B 9 / C 5 / D 7：该红的都红了、该干净的都是 0 条`);
  process.exit(all ? 0 : 1);
}

/* ============================ 判真树 ============================ */
const src = read(C_SRC), rtlText = read(RTL_PIPE), ctrlText = read(RTL_CTRL);
const RT = rtlBitTable(rtlText), MD = selMacros(src), NT = selNameTable(src);
const KNOWN = new Set(NT ? NT.names : []);
const helpT = fnText(src, 'cmd_help(void)') || '';
const applyT = fnText(src, 'apply_pipe_bits(u32 b, int n)') || '';
const verbT = pipeVerbText(src) || '';
const parseT = fnText(src, 'parse_bits(const char *s, u32 *out)') || '';
const legacyT = fnText(src, 'legacy_to_sel(u32 e)') || '';
const ORD = { help: orderSentences(helpT, KNOWN)[0] || null, apply: orderSentences(applyT, KNOWN)[0] || null };
const order = ORD.help || ORD.apply || (NT ? NT.names : null);

const rtlN = RT ? Object.keys(RT).length : 0;
console.log(`RTL  ${RTL_PIPE}: stage_sel 位定义 ${rtlN} 位：` +
            (RT ? Object.keys(RT).sort((a, b) => RT[a].bit - RT[b].bit).map((nm) => `${RT[nm].bit}=${nm}`).join(' ') : '（没读到）'));
console.log(`固件 ${C_SRC}: SEL_* ${MD.length} 个、SEL_NAME ${NT ? NT.names.length : 0} 项、串口顺序句子 ${orderSentences(src, KNOWN).length} 句` +
            `（cmd_help ${ORD.help ? 1 : 0} + apply_pipe_bits 的拒绝消息 ${ORD.apply ? 1 : 0}）`);

const rowsA = judgeA(RT, MD, NT, ORD, { help: 'cmd_help', apply: 'apply_pipe_bits 的拒绝消息' });
for (const r of rowsA) console.log(`  ${r.sev} ${r.text}`);
console.log(`${rowsA.length ? 'FAIL' : 'PASS'} A 位号四份一致：RTL 位定义表 ↔ SEL_* 宏 ↔ SEL_NAME 下标 ↔ 串口那两句顺序句子`);
console.log(`     （错一份的症状就是"屏上没变、串口却说变了"——名字表与位号差一格，回显念的是另一件事）`);

const rowsD = judgeD(ctrlText);
for (const r of rowsD) console.log(`  ${r.sev} ${r.text}`);
console.log(`${rowsD.length ? 'FAIL' : 'PASS'} D 五位那条路退干净了：${RTL_CTRL} 的代码里没有五位端口 / effect_en / 兜底合流，而九位那一份仍在`);

const rowsC = judgeC(printfLines(verbT).find((s) => /长度/.test(s)) || '', helpRuleText(helpT));
for (const r of rowsC) console.log(`  ${r.sev} ${r.text}`);
console.log(`${rowsC.length ? 'FAIL' : 'PASS'} C pipe 的拒绝消息与 cmd_help 说的是同一条长度规则（九位生效 / 五位只给翻译 / 其余一律拒）`);

let rowsB = [], nCases = 0;
if (!RT || !order || order.length !== 9) {
  console.log('FAIL B 组没跑：A 组的输入都没抠全，位号期望无从算起（不能跳过，跳过了就是空集上判绿）');
  rowsB = [F('B 依赖 A 的输入（RTL 位定义表 + 九位顺序句子）')];
} else if (!parseT || !legacyT || !applyT) {
  console.log(`FAIL B 现编没跑成：${[!parseT && 'parse_bits', !legacyT && 'legacy_to_sel', !applyT && 'apply_pipe_bits'].filter(Boolean).join(' / ')} 抠不出来（改了写法就同步改本文件）`);
  rowsB = [F('B 函数原文没读全')];
} else {
  const cases = buildCases(order, RT);
  nCases = cases.length;
  try {
    const runs = runHarness(MD, { parse: parseT, legacy: legacyT, apply: applyT }, cases);
    for (const r of runs)
      console.log(`  ${r.n === wantNOf(r.c.kind) ? 'ok  ' : 'BAD '} "${r.c.inp}" n=${r.n} applied=${r.applied} ` +
                  `writes=${r.writes} sel=${r.sel === NO_WRITE ? '没写' : r.sel}` +
                  `（期望 ${r.c.kind === 'apply' ? 'sel=' + r.c.wantSel : '一个位都不写'}）`);
    rowsB = judgeB(runs, applyGuard(applyT), RT, order);
  } catch (e) {
    console.log(`FAIL B 现编没跑成（${String(e && e.message).split('\n')[0].slice(0, 200)}）—— 编不过不能算过`);
    rowsB = [F('B 现编失败')];
  }
}
const redB = bad(rowsB).length;
for (const r of rowsB) console.log(`  ${r.sev} ${r.text}`);
console.log(`${redB ? 'FAIL' : 'PASS'} B 长度与写口：${nCases} 条现编用例，生效的只有九位那一条路（五位一个位都不写）` +
            `${rowsB.length - redB ? ` + ${rowsB.length - redB} 条 WARN（只报不判）` : ''}`);

/* 现在时的"还在用五位"注释：只报，不改退出码（见文件头 D 组那一段） */
const stale = staleComments(Object.fromEntries([[RTL_CTRL, ctrlText], [RTL_PIPE, rtlText],
  ...RTL_TOPS.map((f) => [f, read(f)]), [C_SRC, src]]));
if (stale.length) {
  console.log(`WARN  注释账（不判红，下一版该改掉）：${stale.length} 处还在用现在时说五位`);
  for (const r of stale) console.log(`      ${r.text}`);
}

const nf = bad(rowsA).length + redB + bad(rowsC).length + bad(rowsD).length;
console.log(nf ? `PIPE_LEN FAIL（${nf} 条）`
               : `PIPE_LEN PASS（位号四份一致 + ${nCases} 条现编用例只有九位那条写寄存器 + 两处口径同一句 + RTL 里没有五位残留）`);
process.exit(nf ? 1 : 0);
