#!/usr/bin/env node
// compare.mjs —— 文本黄金比对器：逐行比对 + 数值容差 + 按"期望内容"作键的白名单豁免 + 三态判定 + 自带 --self
// 依赖：只有 Node 标准库。无本机绝对路径常量、无工程/器件/板卡/工具名绑定；被比对的两侧都是普通文本文件。
//
// 判定纪律（与技能包的尺子口径一致）：
//   每条判据一行，最后一个字段是判定词 PASS / FAIL / NOT_MEASURED。
//   结论行 `判 N 项 …  <token>`，N = 做了多少次比较（打印出的判定行数），不是通过多少。
//   任一侧为空 ⇒ NOT_MEASURED，不算通过。有 FAIL ⇒ 退出码 1。
//   豁免命中 ⇒ 那一行"故意没裁"，记 NOT_MEASURED，不记 PASS。
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));   // <条目>/scripts
const ENTRY = path.resolve(HERE, '..');                      // <条目>
const FIXDIR = path.join(ENTRY, 'fixtures');
const VERDICTS = new Set(['PASS', 'FAIL', 'NOT_MEASURED']);

const USAGE = [
  '用法: node compare.mjs <actual.txt> <golden.txt> [--tol <num>] [--exempt <file>] [--self]',
  '',
  '  <actual.txt>    被测侧输出（逐行文本）',
  '  <golden.txt>    黄金参考（期望文本）',
  '  --tol <num>     数值字段的绝对容差，缺省 0（逐字相等）',
  '  --exempt <file> 白名单规则，一条一行；键 = 被豁免的"期望行原文"（*子串* 或整行），',
  '                  不许用被测对象名/实际侧独有的值作键 —— 那是买通',
  '  --self          在临时目录跑全部夹具并断言读数（含一条改期望值的变异对照）',
  '',
  '退出码：有 FAIL ⇒ 1；其余 ⇒ 0。退出码 0 不等于通过 —— 只认每行最后一个字段的判定词。',
].join('\n');

const NUM_RE = /^[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?$/;
const isNum = (s) => NUM_RE.test(s);
const tokens = (l) => (l.trim() === '' ? [] : l.trim().split(/\s+/));

function readText(p) {
  const raw = fs.readFileSync(p, 'utf8').replace(/\r\n/g, '\n');
  const lines = raw.split('\n');
  if (lines.length && lines[lines.length - 1] === '') lines.pop();
  return { raw, lines };
}

function loadRules(p) {
  const rules = [];
  readText(p).lines.forEach((l, i) => {
    const t = l.trim();
    if (!t || t.startsWith('#')) return;
    if (t.length > 2 && t.startsWith('*') && t.endsWith('*')) rules.push({ no: i + 1, key: t.slice(1, -1), sub: true });
    else rules.push({ no: i + 1, key: t, sub: false });
  });
  return rules;
}
const ruleHitsLine = (r, line) => (r.sub ? line.includes(r.key) : line.trim() === r.key);

// 核心：返回结构化读数 + 判定行数组
function compareFiles(o) {
  const st = {
    rows: [], comparisons: 0, red: 0, nm: 0, exempted: 0, keyHitLines: 0,
    tol: o.tol ?? 0, buyoff: [], unusedRules: [], token: 'NOT_MEASURED',
  };
  const emit = (id, name, detail, verdict) => {
    if (!VERDICTS.has(verdict)) throw new Error(`非法判定词 ${verdict}`);
    st.rows.push(`${id} ${name} ${detail} ${verdict}`);
    st.comparisons += 1;
    if (verdict === 'FAIL') st.red += 1;
    else if (verdict === 'NOT_MEASURED') st.nm += 1;
  };

  let A, G;
  try { A = readText(o.actual); G = readText(o.golden); }
  catch (e) { emit('F0', '读入两侧', `读取失败=${e.message.split('\n')[0]}`, 'NOT_MEASURED'); return finish(st); }

  // 空集地板：任一侧没有一行有内容 ⇒ 无从比较
  const aBlank = A.lines.filter((l) => l.trim() !== '').length;
  const gBlank = G.lines.filter((l) => l.trim() !== '').length;
  emit('F1', '样本非空', `实际有效行=${aBlank} 黄金有效行=${gBlank}`,
    (aBlank === 0 || gBlank === 0) ? 'NOT_MEASURED' : 'PASS');
  if (aBlank === 0 || gBlank === 0) {
    emit('F2', '逐行比对', '一侧为空，未做任何内容比较（真空通过即假绿）', 'NOT_MEASURED');
    if (o.exempt) emit('X0', '豁免规则', '未参与比较，命中无从谈起', 'NOT_MEASURED');
    return finish(st);
  }

  const rules = o.exempt ? loadRules(o.exempt) : [];
  if (rules.length) {
    // 键的归属：规则必须按"期望侧存在的内容"作键。只出现在实际侧的键 = 买通。
    for (const r of rules) {
      const inGolden = G.lines.some((l) => ruleHitsLine(r, l));
      const inActual = A.lines.some((l) => ruleHitsLine(r, l));
      if (!inGolden && inActual) st.buyoff.push(r);
      else if (!inGolden) st.unusedRules.push(r);
      else st.keyHitLines += G.lines.filter((l) => ruleHitsLine(r, l)).length;
    }
  }

  // 1) 行数
  const n = Math.min(A.lines.length, G.lines.length);
  const sameCount = A.lines.length === G.lines.length;
  emit('C1', '行数一致', `实际=${A.lines.length} 黄金=${G.lines.length} 差=${A.lines.length - G.lines.length}`,
    sameCount ? 'PASS' : 'FAIL');
  if (!sameCount) {
    const show = (arr, from) => (arr.length <= from ? '无' : arr.slice(from, from + 5).map((l, i) => `L${from + i + 1}「${l}」`).join(' | '));
    emit('C2', '多/少的行', `实际侧多出 ${A.lines.length - n} 行 [${show(A.lines, n)}] 黄金侧多出 ${G.lines.length - n} 行 [${show(G.lines, n)}]`, 'FAIL');
  }

  // 2) 公共前缀逐行比对
  let lineFail = 0, linePass = 0;
  for (let i = 0; i < n; i += 1) {
    const al = A.lines[i], gl = G.lines[i];
    const at = tokens(al), gt = tokens(gl);
    const bad = [];
    if (at.length !== gt.length) bad.push(`字段数 ${at.length}≠${gt.length}`);
    else {
      at.forEach((f, k) => {
        const g = gt[k];
        if (isNum(f) && isNum(g)) {
          const d = Math.abs(Number(f) - Number(g));
          if (!(d <= st.tol)) bad.push(`第${k + 1}列 ${g}→${f} 偏${d.toExponential(3)}`);
        } else if (f !== g) bad.push(`第${k + 1}列 ${g}→${f}`);
      });
    }
    if (bad.length === 0) { linePass += 1; emit(`L${i + 1}`, `第 ${i + 1} 行`, `一致`, 'PASS'); continue; }
    const covered = rules.some((r) => ruleHitsLine(r, gl));
    if (covered) {
      st.exempted += 1;
      emit(`L${i + 1}`, `第 ${i + 1} 行`, `差异[${bad.slice(0, 3).join('; ')}] 被白名单豁免=期望侧键命中，未裁决`, 'NOT_MEASURED');
    } else {
      lineFail += 1;
      emit(`L${i + 1}`, `第 ${i + 1} 行`, `差异 ${bad.length} 处 [${bad.slice(0, 3).join('; ')}]`, 'FAIL');
    }
  }

  // 3) 豁免审计（命中数必须打印；命中 0 要警告"豁免可能失效"）
  if (rules.length) {
    emit('X1', '豁免键归属', `规则=${rules.length} 键只在实际侧(买通)=${st.buyoff.length} 键两侧都无(空规则)=${st.unusedRules.length}` +
      (st.buyoff.length ? ` 买通键=${st.buyoff.map((r) => `「${r.key}」`).join('')}` : ''),
      st.buyoff.length ? 'FAIL' : 'PASS');
    emit('X2', '豁免命中数', `命中=${st.exempted} 期望侧键命中行=${st.keyHitLines} 规则=${rules.length}` +
      (st.exempted === 0 ? ' 警告：豁免可能失效（一次也没命中，键多半已随参考漂移）' : ''),
      st.exempted === 0 ? 'NOT_MEASURED' : 'PASS');
  }
  emit('S1', '差异汇总', `一致=${linePass} 失败=${lineFail} 豁免=${st.exempted} 未配对=${sameCount ? 0 : Math.abs(A.lines.length - G.lines.length)}`,
    (lineFail || !sameCount) ? 'FAIL' : (st.exempted ? 'NOT_MEASURED' : 'PASS'));
  return finish(st);
}

function finish(st) {
  st.token = st.red ? 'FAIL' : (st.nm ? 'NOT_MEASURED' : 'PASS');
  return st;
}

function printResult(st) {
  for (const r of st.rows) console.log(r);
  console.log(`判 ${st.comparisons} 项：红=${st.red} 未测=${st.nm} 豁免命中=${st.exempted} 容差=${st.tol} ${st.token}`);
}

// ---------------------------------------------------------------- self
function copyTree(src, dst) {
  fs.mkdirSync(dst, { recursive: true });
  for (const e of fs.readdirSync(src, { withFileTypes: true })) {
    const s = path.join(src, e.name), d = path.join(dst, e.name);
    if (e.isDirectory()) copyTree(s, d); else fs.copyFileSync(s, d);
  }
}

function selfTest() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'golden-compare-self-'));
  const fx = path.join(tmp, 'fixtures');
  copyTree(FIXDIR, fx);
  const F = (...p) => path.join(fx, ...p);
  const rows = [];
  let red = 0;
  const ck = (name, want, got) => {
    const ok = JSON.stringify(want) === JSON.stringify(got);
    rows.push(`S ${name} 期望=${JSON.stringify(want)} 实得=${JSON.stringify(got)} ${ok ? 'PASS' : 'FAIL'}`);
    if (!ok) red += 1;
  };

  const cases = [
    ['等值通过', ['exact', 'actual.txt'], ['exact', 'golden.txt'], null, null,
      { token: 'PASS', red: 0, nm: 0, exempted: 0, comparisons: 8 }],
    ['容差内通过', ['tol', 'actual.txt'], ['tol', 'golden.txt'], 0.001, null,
      { token: 'PASS', red: 0, nm: 0, exempted: 0, comparisons: 7 }],
    ['容差没设就红（证明容差真在干活）', ['tol', 'actual.txt'], ['tol', 'golden.txt'], 0, null,
      { token: 'FAIL', red: 4, nm: 0, exempted: 0, comparisons: 7 }],
    ['超容差失败', ['over-tol', 'actual.txt'], ['over-tol', 'golden.txt'], 0.001, null,
      { token: 'FAIL', red: 2, nm: 0, exempted: 0, comparisons: 6 }],
    ['行数不等要报出多/少哪几行', ['rowcount', 'actual.txt'], ['rowcount', 'golden.txt'], null, null,
      { token: 'FAIL', red: 3, nm: 0, exempted: 0, comparisons: 7 }],
    ['被豁免：命中数必须=2，且整条不许是 PASS', ['exempt', 'actual.txt'], ['exempt', 'golden.txt'], null, ['exempt', 'exempt.rules'],
      { token: 'NOT_MEASURED', red: 0, nm: 3, exempted: 2, comparisons: 9 }],
    ['一侧为空 ⇒ NOT_MEASURED，不是通过', ['empty', 'actual.txt'], ['empty', 'golden.txt'], null, null,
      { token: 'NOT_MEASURED', red: 0, nm: 2, exempted: 0, comparisons: 2 }],
    ['豁免键按被测对象作键 = 买通，必须红', ['buyoff', 'actual.txt'], ['buyoff', 'golden.txt'], null, ['buyoff', 'exempt.rules'],
      { token: 'FAIL', red: 3, nm: 1, exempted: 0, comparisons: 8 }],
    ['豁免一次没命中 = 警告并落 NOT_MEASURED', ['unused', 'actual.txt'], ['unused', 'golden.txt'], null, ['unused', 'exempt.rules'],
      { token: 'NOT_MEASURED', red: 0, nm: 1, exempted: 0, comparisons: 8 }],
  ];

  for (const [name, a, g, tol, ex, want] of cases) {
    const st = compareFiles({
      actual: F(...a), golden: F(...g), tol,
      exempt: ex ? F(...ex) : null,
    });
    ck(name, want, { token: st.token, red: st.red, nm: st.nm, exempted: st.exempted, comparisons: st.comparisons });
  }

  // 变异对照：只改期望值本身（被测侧一个字不动），原本绿的必须红
  const mut = path.join(tmp, 'mutated-golden.txt');
  const gsrc = readText(F('exact', 'golden.txt'));
  fs.writeFileSync(mut, `${gsrc.lines.map((l) => l.replace(' 1234', ' 1235')).join('\n')}\n`, 'utf8');
  const mv = compareFiles({ actual: F('exact', 'actual.txt'), golden: mut, tol: null, exempt: null });
  ck('变异对照（把期望的一个数改 1）', { token: 'FAIL', red: 2, exempted: 0 }, { token: mv.token, red: mv.red, exempted: mv.exempted });

  for (const r of rows) console.log(r);
  console.log(`判 ${rows.length} 项：红=${red} 未测=0 夹具=${fs.readdirSync(fx).length} 临时目录=${tmp} ${red ? 'FAIL' : 'PASS'}`);
  if (red) console.log(`保留临时目录以便复跑：${tmp}`);
  else fs.rmSync(tmp, { recursive: true, force: true });
  return red ? 1 : 0;
}

// ---------------------------------------------------------------- main
function main(argv) {
  const args = [];
  const opt = { tol: null, exempt: null };
  let self = false;
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--self') self = true;
    else if (a === '--tol') {
      i += 1;
      opt.tol = Number(argv[i]);
      if (!Number.isFinite(opt.tol)) { console.log(`判 1 项：--tol 取值不是数字(${argv[i]}) FAIL`); return 1; }
      // 负容差会让每一行都红，看着像"判据严"其实是把尺子掰断：直接拒
      if (opt.tol < 0) { console.log(`判 1 项：--tol 为负(${opt.tol}) 全表必红属误用 FAIL`); return 1; }
    }
    else if (a === '--exempt') { i += 1; opt.exempt = argv[i]; }
    else if (a === '-h' || a === '--help') { console.log(USAGE); return 0; }
    else if (a.startsWith('--')) { console.log(`判 1 项：未知选项 ${a} FAIL`); return 1; }
    else args.push(a);
  }
  if (self) return selfTest();
  if (args.length !== 2) { console.log(USAGE); return 1; }
  if (!fs.existsSync(FIXDIR)) console.log('W0 夹具目录 不在预期位置，--self 会红 NOT_MEASURED');
  const st = compareFiles({ actual: args[0], golden: args[1], tol: opt.tol, exempt: opt.exempt });
  printResult(st);
  return st.red ? 1 : 0;
}

process.exit(main(process.argv.slice(2)));
