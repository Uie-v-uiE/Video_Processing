#!/usr/bin/env node
/**
 * pipe_len_check.mjs —— `pipe` 那条命令的"长度口径 + 位序 + 回显名字"离线核对（不碰板子）
 *
 * 为什么要有这一条（2026-09-25，用户坐在屏幕前问的两句话）：
 *   ① "为什么要发 8 位或者十位才读得到，五位读不到" —— 老代码只挡"超过 9 位"，
 *      于是 `pipe 00001100`（8 位）被**静默当成 9 位补零**收下：命令收了、意思变了，
 *      用户只能试到某个长度"看起来对了"。这种"半个接受"是最难自证的一类错。
 *   ② "怎么 2 都来了" —— 屏上 `Pipe:` 那五格每格是 0..3（"这一级选了第几个算法"，
 *      唯一出处 src/rtl/video/osd_overlay.v 第 114–125 行），与命令里那 9 个 0/1 不是同一个
 *      写法。这个事实改不了（九位是给第 5 级形态学腾地方），能改的是**让回显说人话**：
 *      `pipe show` 打印位 → 名字。于是名字表、SEL_* 位号、help 里那两句位序必须一致，
 *      错一处的症状恰恰是"屏上没变但串口说变了"。
 *
 * 一致性由**第四处**来钉：位号的事实来源是 RTL（proc_pipeline.v 文件头那张位定义表 +
 * effect_ctrl.v 的老五位翻译），不是固件里的那份抄件 ⇒ 本文件从 RTL 抠位号、从 main.c 抠
 * SEL_ 宏 / SEL_NAME / help 位序，四份两两比对。
 * 函数行为则**从 main.c 抠原文用宿主 gcc 现编**（沿用 temp_formula_check.mjs 的规矩）：
 * 在测试里重写一份实现，等于把"两处各说一遍"这个病搬进判据。
 * 每条判据都配变异对照：实现改坏了判据必须红；不会红的判据是假判据。
 *
 * 用法：node src/host/pipe_len_check.mjs
 */
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const C_SRC = 'src/ps/main.c';
const RTL_PIPE = 'src/rtl/process/proc_pipeline.v';
const RTL_CTRL = 'src/rtl/process/effect_ctrl.v';
const CC = process.env.CC || 'gcc';
const src = readFileSync(C_SRC, 'utf8').replace(/\r\n/g, '\n');
const rtlPipe = readFileSync(RTL_PIPE, 'utf8').replace(/\r\n/g, '\n');
const rtlCtrl = readFileSync(RTL_CTRL, 'utf8').replace(/\r\n/g, '\n');

/* ---- 1) RTL 侧的事实 ---- */
/* ZH2EN / MACRO2EN 是本文件里唯一两处"我把名字对起来"的地方：名字换了要改这里。
 * **位号不许在这里写**（位号一律从 RTL 抠，见下）。 */
const ZH2EN = {
  '灰度': 'gray', '反色': 'invert', '3×3 模糊': 'blur', '3×3 锐化': 'sharpen',
  'Sobel': 'sobel', '二值化': 'binary', '二值化判决反相': 'bin_pol', '腐蚀': 'erode', '膨胀': 'dilate',
};
const MACRO2EN = {
  SEL_GRAY: 'gray', SEL_INVERT: 'invert', SEL_BLUR: 'blur', SEL_SHARP: 'sharpen', SEL_SOBEL: 'sobel',
  SEL_BIN: 'binary', SEL_BIN_POL: 'bin_pol', SEL_ERODE: 'erode', SEL_DILATE: 'dilate',
};

/* proc_pipeline.v 文件头：`[0] 灰度  [1] 反色 …`。一格的名字后面常常跟着说明（"（只在 [5]=1 时有意义）"、
 * "—— [7] 与 [8] 同时为 1…"），所以按"最长前缀命中字典"取名字，而不是整段相等。 */
const ZH_KEYS = Object.keys(ZH2EN).sort((a, b) => b.length - a.length);
const rtlBit = {};
for (const m of rtlPipe.matchAll(/\[(\d)\]\s*([^\[\r\n]+)/g)) {
  const nm = m[2].trim();
  const hit = ZH_KEYS.find((k) => nm.startsWith(k));
  if (hit !== undefined && rtlBit[ZH2EN[hit]] === undefined) rtlBit[ZH2EN[hit]] = Number(m[1]);
}
if (Object.keys(rtlBit).length !== 9) {
  console.log(`FAIL 从 ${RTL_PIPE} 只抠到 ${Object.keys(rtlBit).length} 个位号（要 9 个）—— 位定义表改了写法？`);
  process.exit(1);
}
/* effect_ctrl.v：`legacy_sel[K] = en_sync[J]; // name` ⇒ 老五位的第 J 位翻成新九位的第 K 位 */
const legacyToBit = new Array(5).fill(-1);
for (const m of rtlCtrl.matchAll(/legacy_sel\[(\d)\]\s*=\s*en_sync\[(\d)\];\s*\/\/\s*(\w+)/g)) {
  legacyToBit[Number(m[2])] = Number(m[1]);
}
if (legacyToBit.some((b) => b < 0)) {
  console.log(`FAIL 从 ${RTL_CTRL} 抠到的老五位翻译不满 5 条：${JSON.stringify(legacyToBit)}`);
  process.exit(1);
}
const nameOfBit = (k) => Object.keys(rtlBit).find((n) => rtlBit[n] === k);
const legacyName = (j) => nameOfBit(legacyToBit[j]);
const byBit = Object.keys(rtlBit).sort((a, b) => rtlBit[a] - rtlBit[b]);
console.log(`RTL  ${RTL_PIPE}: ${byBit.map((n) => `${rtlBit[n]}=${n}`).join(' ')}`);
console.log(`RTL  ${RTL_CTRL}: 老五位→新九位 ${legacyToBit.map((k, j) => `${j}=${legacyName(j)}→位${k}`).join(' ')}`);

/* ---- 2) 固件侧的三份抄件：SEL_ 宏、SEL_NAME、help 里那两句位序 ---- */
const SEL_DEFS = [...src.matchAll(/^#define\s+(SEL_\w+)\s+\(1u\s*<<\s*(\d+)\)/gm)]
  .map((m) => ({ macro: m[1], bit: Number(m[2]) }));
const nameTab = src.match(/static const char \*SEL_NAME\[9\] = \{([^}]*)\}/);
const help5 = (src.match(/五位=老位序\(([^)]*)\)/) || [])[1];
/* help 那两句位序是**一个 xil_printf 里的两段相邻字符串**（C 会自动拼），所以九位那句在下一行的引号里 */
const help9 = (src.match(/九位=新位序"\s*\n\s*"\(([^)]*)\)/) || [])[1];
if (SEL_DEFS.length !== 9 || !nameTab || !help5 || !help9) {
  console.log(`FAIL 固件侧没读全：SEL_ 宏 ${SEL_DEFS.length}/9、SEL_NAME ${nameTab ? '有' : '无'}、` +
              `help 五位 ${help5 ? '有' : '无'}、help 九位 ${help9 ? '有' : '无'} ` +
              `（改了写法就同步改本文件，别把判据删掉）`);
  process.exit(1);
}
const names = [...nameTab[1].matchAll(/"([^"]*)"/g)].map((m) => m[1]);
const L5 = help5.split('/').map((s) => s.trim());
const L9 = help9.replace(/^\s*"?/, '').split('/').map((s) => s.trim());

let okA = true;
function eq(what, want, got, where) {
  if (want === got) return;
  console.log(`FAIL ${what}：RTL 是 ${want}，${where} 是 ${got}`);
  okA = false;
}
for (const d of SEL_DEFS) {
  const en = MACRO2EN[d.macro];
  if (en === undefined) { console.log(`FAIL 固件宏 ${d.macro} 不在 MACRO2EN 里（新增了一位？那 RTL 也得有它）`); okA = false; continue; }
  eq(`位号 ${en}`, rtlBit[en], d.bit, `main.c 的 ${d.macro}`);
}
names.forEach((n, i) => {
  if (rtlBit[n] === undefined) { console.log(`FAIL SEL_NAME[${i}]="${n}" 不是 RTL 里的算法名`); okA = false; return; }
  eq(`位号 ${n}`, rtlBit[n], i, `SEL_NAME 里的第 ${i} 格`);
});
eq('help 新位序项数', 9, L9.length, 'help');
L9.forEach((h, i) => { if (rtlBit[h] !== undefined) eq(`位号 ${h}`, rtlBit[h], i, `help 九位那句的第 ${i + 1} 项`);
                       else { console.log(`FAIL help 九位那句第 ${i + 1} 项 "${h}" 不在 RTL 名字里`); okA = false; } });
eq('help 老位序项数', 5, L5.length, 'help');
L5.forEach((h, j) => {
  if (h !== legacyName(j)) { console.log(`FAIL help 五位那句第 ${j + 1} 项 "${h}"，RTL 的 effect_ctrl 说第 ${j} 位是 "${legacyName(j)}"`); okA = false; }
});
console.log(`${okA ? 'PASS' : 'FAIL'} A 位号五份一致：RTL 位定义表 + RTL 老五位翻译 ↔ 固件 SEL_ 宏 ↔ SEL_NAME 下标 ↔ help 两句位序`);
console.log(`     （错一份的症状就是"屏上没变、串口却说变了"——名字表与位号差一格，回显就成了另一件事）`);

/* ---- 3) 函数原文抠出来现编（括号配对数出来的，不是正则截断） ---- */
function fnText(head) {
  const start = src.indexOf(head);
  if (start < 0) throw new Error(`读不到函数 ${head}（改了写法就同步改本文件，别把判据删掉）`);
  const open = src.indexOf('{', start);
  let depth = 0, i = open;
  for (; i < src.length; i++) {
    if (src[i] === '{') depth++;
    else if (src[i] === '}') { depth--; if (depth === 0) break; }
  }
  return src.slice(start, i + 1);
}
const F_PARSE = fnText('static int parse_bits(');
const F_LEGACY = fnText('static u32 legacy_to_sel(');
const F_APPLY = fnText('static void apply_pipe_bits(');

/* 期望值由 RTL 算，不抄固件实现：新九位 = 串第 i 个字符落在第 i 位；
 * 老五位 = 串第 j 个字符经 legacyToBit[j] 落到九位。 */
const newSel = (s) => [...s].reduce((a, c, i) => (c === '1' ? a | (1 << i) : a), 0);
const legacySel = (s) => [...s].reduce((a, c, j) => (c === '1' ? a | (1 << legacyToBit[j]) : a), 0);
const NO_WRITE = 0xDEAD;                 // g_sel 初值：被改过就说明"拒了还写寄存器"

const CASES = [
  ['11000', '五位老写法 gray+binary', legacySel],
  ['01010', '五位老写法 binary+blur', legacySel],
  ['00000', '五位全关', legacySel],
  ['11111', '五位全开', legacySel],
  ['000001010', '九位 binary+erode（与 uart_cmd_check 的 sel=0A0 同源）', newSel],
  ['000000001', '九位 dilate ⇒ 0x100', newSel],
  ['000100000', '九位 sharpen ⇒ 0x008', newSel],
  ['111111111', '九位全开 ⇒ 0x1FF', newSel],
  ['', '光杆 pipe：必须拒', null],
  ['1', '1 位：必须拒（用户那半边疑问）', null],
  ['11', '2 位：必须拒', null],
  ['1111', '4 位：必须拒（差一位也不许默认补零）', null],
  ['111111', '6 位：必须拒', null],
  ['00001100', '8 位：必须拒 —— 那次的根因就在这一条', null],
  ['0000000001', '10 位：必须拒', null],
  ['1111a', '夹一个字母：必须拒', null],
];

function harness(parseText, applyText) {
  return [
    '#include <stdio.h>',
    'typedef unsigned int u32;',
    ...SEL_DEFS.map((d) => `#define ${d.macro} (1u << ${d.bit})`),
    `static u32 g_sel = ${NO_WRITE}u;   /* 被改过就说明"拒了还写寄存器" */`,
    'static void ctrl_set_sel(u32 v) { g_sel = v & 0x1FFu; }',
    parseText,
    F_LEGACY,
    applyText,
    'int main(int argc, char **argv) {',
    '  u32 en = 0;',
    '  int n = parse_bits(argv[1], &en);',
    '  printf("%d ", n);',
    '  if (n > 0) apply_pipe_bits(en, n);  /* 与 dispatch() 同形：n<=0 只打印提示，不写寄存器 */',
    '  printf("%u\\n", g_sel);',
    '  return 0;',
    '}',
  ].join('\n') + '\n';
}

function run(tag, parseText, applyText, only, isMut) {
  const dir = mkdtempSync(join(tmpdir(), 'pipechk_'));
  const cfile = join(dir, 't.c'), exe = join(dir, process.platform === 'win32' ? 't.exe' : 't');
  writeFileSync(cfile, harness(parseText, applyText));
  execFileSync(CC, ['-O0', '-w', '-o', exe, cfile], { stdio: 'pipe' });
  const list = CASES.filter((c) => (only ? only(c[0]) : true));
  const rows = [];
  for (const [inp, what, exp] of list) {
    const out = execFileSync(exe, [inp], { encoding: 'utf8' }).trim().split(/\s+/);
    const n = Number(out[0]), sel = Number(out[1]);
    const wantN = exp === null ? -1 : inp.length;
    const wantSel = exp === null ? NO_WRITE : exp(inp);
    rows.push({ inp, n, sel, wantN, wantSel, ok: n === wantN && sel === wantSel });
  }
  const bad = rows.filter((r) => !r.ok);
  /* 变异那一行打的是 MUT 而不是 FAIL：这一行**应当**红，红了才是这条判据有效。
   * 打成 FAIL 会被"grep FAIL 看门禁"的人当成一次真红（这个混淆本仓库记过好几回）。 */
  console.log(`${isMut ? 'MUT ' : (bad.length ? 'FAIL' : 'PASS')} ${tag} ${rows.length - bad.length}/${rows.length}` +
    (bad.length && !isMut ? ' —— ' + bad.map((r) => `"${r.inp}" 得 n=${r.n} sel=${r.sel}，期望 n=${r.wantN} sel=${r.wantSel}`).join(' | ') : ''));
  return { pass: rows.length - bad.length, total: rows.length };
}

const base = run('B 真函数现编：长度只收 5/9，其余一个寄存器都不写；老五位按 RTL 的翻译落位', F_PARSE, F_APPLY);

/* 变异 1：回到"只挡超过 9 位"的老收法 ⇒ 1/2/4/6/8/10 位那一组必须红 */
const m1 = F_PARSE.replace('if (n != 5 && n != 9) return -1;', 'if (n == 0) return -1;');
if (m1 === F_PARSE) { console.log('FAIL 变异 1 没打上（parse_bits 里那句长度检查改了写法？）'); process.exit(1); }
const r1 = run('M1 变异体（长度口径删掉，这一行**应当**红）', m1, F_APPLY, (s) => [1, 2, 4, 6, 8, 10].includes(s.length), true);

/* 变异 2：五位老写法不再翻译，直接当九位用 ⇒ 五位那一组必须红 */
const m2 = F_APPLY.replace('n == 5 ? legacy_to_sel(b) : (b & 0x1FFu)', '(b & 0x1FFu)');
if (m2 === F_APPLY) { console.log('FAIL 变异 2 没打上（apply_pipe_bits 改了写法？）'); process.exit(1); }
const r2 = run('M2 变异体（"五位=老位序"这条契约删掉，这一行**应当**红）', F_PARSE, m2, (s) => s.length === 5, true);

const okB = base.pass === base.total;
const okM1 = r1.total > 0 && r1.pass < r1.total;
const okM2 = r2.total > 0 && r2.pass < r2.total;
console.log(`${okM1 ? 'PASS' : 'FAIL'} M1 对照：删掉长度口径后判据红 ${r1.total - r1.pass}/${r1.total}（必须 >0，否则它是假判据）`);
console.log(`${okM2 ? 'PASS' : 'FAIL'} M2 对照：删掉位序契约后判据红 ${r2.total - r2.pass}/${r2.total}（必须 >0）`);
const ok = okA && okB && okM1 && okM2;
console.log(ok ? `PIPE_LEN PASS（位号五份一致 + 用例 ${base.total} 条全过 + 两条变异各自变红）` : 'PIPE_LEN FAIL');
process.exit(ok ? 0 : 1);
