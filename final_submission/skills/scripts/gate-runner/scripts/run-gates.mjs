#!/usr/bin/env node
// run-gates.mjs —— 多判据门禁跑批器：三态、判 N 项 = 比较次数、红即非 0 退出、比较数为 0 自动降级。
//
//   node scripts/run-gates.mjs --dir <判据目录> [--only <id 或文件名>] [--set key=value]...
//   node scripts/run-gates.mjs --self
//
// 判据件形状：`export const ID = '…'`（可选）+ `export function run(ctx)`（可 async），
// 返回 { id, detail, verdict }；verdict ∈ PASS / FAIL / NOT_MEASURED。
// ctx.cmp(标签, 实得, 期望, op) 每调一次记一次比较；ctx.cmpTrue(标签, cond) 同理。
// 约定：判据件顶层不许有副作用（跑批器会 import 全部件）；只用 Node 标准库。
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { pathToFileURL, fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ENTRY = path.resolve(HERE, '..');
const FIX = path.join(ENTRY, 'fixtures', 'gates');
const VERDICTS = ['PASS', 'FAIL', 'NOT_MEASURED'];
const toPosix = (p) => String(p).replace(/\\/g, '/');

function listGates(dir) {
  if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) return { err: `判据目录读不到：${toPosix(dir)}`, mods: [] };
  const names = fs.readdirSync(dir).filter(f => /\.(mjs|js)$/.test(f)).sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  return { err: null, mods: names.map(n => path.join(dir, n)) };
}

async function loadGate(file, opts) {
  const stem = path.basename(file).replace(/\.(mjs|js)$/, '');
  const rec = { file, stem, id: stem, cmp: 0, verdict: 'NOT_MEASURED', detail: '', log: [], bad: [] };
  let mod;
  try { mod = await import(pathToFileURL(file).href); }
  catch (e) { rec.detail = '导入失败：' + e.message; return rec; }
  if (typeof mod.ID === 'string' && mod.ID) rec.id = mod.ID;
  if (typeof mod.run !== 'function') { rec.detail = '没导出 run(ctx) ⇒ 这条根本没法判'; return rec; }
  const ctx = {
    opts, file, stem, gateId: rec.id,
    log(m) { rec.log.push(String(m)); },
    cmp(label, got, exp, op = '===') {
      const ok = op === '>=' ? Number(got) >= Number(exp) : op === '<=' ? Number(got) <= Number(exp)
        : op === '>' ? Number(got) > Number(exp) : op === '<' ? Number(got) < Number(exp)
          : op === '!=' ? got !== exp : got === exp;
      rec.cmp++;
      if (!ok) rec.bad.push(`${label}：实得=${String(got)} 期望 ${op === '===' ? '==' : op === '!==' ? '!=' : op} ${String(exp)}`);
      return ok;
    },
    cmpTrue(label, cond) { rec.cmp++; if (!cond) rec.bad.push(`${label}：条件不成立`); return !!cond; },
  };
  let ret;
  try { ret = await mod.run(ctx); }
  catch (e) { rec.verdict = 'NOT_MEASURED'; rec.detail = '抛异常（没跑出判定）：' + e.message; return rec; }
  if (!ret || typeof ret !== 'object') { rec.detail = 'run() 没返回对象 ⇒ 无法判定'; return rec; }
  if (typeof ret.id === 'string' && ret.id) rec.id = ret.id;
  rec.detail = String(ret.detail === undefined ? '' : ret.detail);
  const v = String(ret.verdict === undefined ? '' : ret.verdict).trim().toUpperCase();
  if (v === 'PASS' || ret.verdict === true) rec.verdict = 'PASS';
  else if (v === 'FAIL' || ret.verdict === false) rec.verdict = 'FAIL';
  else if (VERDICTS.includes(v)) rec.verdict = v;
  else { rec.verdict = 'NOT_MEASURED'; rec.detail = `判定词「${ret.verdict}」不在 ${VERDICTS.join('/')} ｜ ${rec.detail || '无说明'}`; }
  if (rec.verdict === 'PASS' && rec.cmp === 0) {
    rec.verdict = 'NOT_MEASURED';
    rec.detail = `比较数=0 的"通过"不作数（真空通过防护）｜ 原说明：${rec.detail || '无'}`;
  }
  if (rec.verdict === 'FAIL' && rec.bad.length) rec.detail = rec.bad.join('；') + ' ｜ ' + (rec.detail || '无说明');
  return rec;
}

async function runGates(dir, only, opts) {
  const found = listGates(dir);
  const bail = (why) => { console.log(why); console.log('判 0 项 红=0 未测=1 NOT_MEASURED'); return { exit: 2, cmp: 0, red: 0, nm: 1, rows: [] }; };
  if (found.err) return bail(found.err + '（不猜目录、不退回上一级）');
  const loaded = [];
  for (const f of found.mods) loaded.push(await loadGate(f, opts));   // 先 import 才拿得到 ID，过滤要有依据
  const picked = only ? loaded.filter(r => r.id === only || r.stem === only) : loaded;
  console.log(`判据目录 ${path.basename(dir)}：件=${loaded.length} 跑=${picked.length}${only ? `（--only ${only}）` : ''} 顺序=文件名字典序`);
  if (only && picked.length === 0) return bail(`--only ${only} 命中 0 条 ⇒ 没跑等于没测（可选：${loaded.map(r => r.id).join(', ')}）`);
  if (picked.length === 0) return bail('目录里一个判据件都没有 ⇒ 空门禁不等于通过');
  let cmp = 0, red = 0, nm = 0;
  const rows = [];
  for (const r of picked) {
    for (const l of r.log) console.log(`    · ${r.id}: ${l}`);
    cmp += r.cmp;
    if (r.verdict === 'FAIL') red++; else if (r.verdict !== 'PASS') nm++;
    rows.push(r.id);
    console.log(`${r.id.padEnd(16)} 比较数=${String(r.cmp).padStart(2)} ${r.verdict.padEnd(13)} ${r.detail || '（无说明）'}`);
  }
  const token = red ? 'FAIL' : (nm ? 'NOT_MEASURED' : 'PASS');
  console.log(`判 ${cmp} 项 红=${red} 未测=${nm} ${token}`);
  return { exit: red ? 1 : (nm ? 2 : 0), cmp, red, nm, rows, token };
}

function selfTest() {
  const out = []; let cmp = 0, red = 0, nm = 0;
  const say = (id, detail, verdict, done) => { out.push(`${id} ${detail} ${verdict}`); cmp += done || 0; if (verdict === 'FAIL') red++; else if (verdict === 'NOT_MEASURED') nm++; };
  const me = fileURLToPath(import.meta.url);
  const run = (args) => {
    const r = spawnSync(process.execPath, [me, ...args], { encoding: 'utf8' });
    return { text: (r.stdout || '') + (r.stderr || ''), status: r.status };
  };
  const num = (t, re) => parseInt((t.match(re) || [, '-1'])[1], 10);

  const all = run(['--dir', FIX]);
  const a = all.text;
  const vacDown = /vacuous-green\s+比较数=\s*0\s+NOT_MEASURED/.test(a) && /真空通过防护/.test(a);
  const rows = a.split('\n').filter(l => /比较数=/.test(l) && !l.startsWith('判')).map(l => l.trim().split(' ')[0]);
  say('S1 全量跑批：三态齐、红优先 ⇒ 退出码 1', `退出码=${all.status} 判=${num(a, /判 (\d+) 项/)} 红=${num(a, /红=(\d+)/)} 未测=${num(a, /未测=(\d+)/)} 空转降级=${vacDown ? '是' : '否'}`,
    (all.status === 1 && num(a, /判 (\d+) 项/) === 5 && num(a, /红=(\d+)/) === 1 && num(a, /未测=(\d+)/) === 3 && vacDown) ? 'PASS' : 'FAIL', 5);
  say('S2 执行顺序=文件名字典序（跑批顺序可复算）', `顺序=${rows.join(',')}`,
    rows.join(',') === 'width-bound,row-overlap,vacuous-green,bad-verdict,crash-gate' ? 'PASS' : 'FAIL', 1);

  const one = run(['--dir', FIX, '--only', 'width-bound']);
  const o = one.text;
  say('S3 --only 命中 1 条 ⇒ 判 2 项 红=0 未测=0 PASS 且退出码 0', `退出码=${one.status} 判=${num(o, /判 (\d+) 项/)} 结论=${(o.match(/判 \d+ 项 红=\d+ 未测=\d+ (\w+)/) || [, '?'])[1]}`,
    (one.status === 0 && num(o, /判 (\d+) 项/) === 2 && /PASS/.test(o)) ? 'PASS' : 'FAIL', 3);

  const v = run(['--dir', FIX, '--only', 'vacuous-green']);
  const vt = v.text;
  say('S4 恒绿但比较数=0 ⇒ 降级 NOT_MEASURED 且退出码 2', `退出码=${v.status} 判=${num(vt, /判 (\d+) 项/)} 未测=${num(vt, /未测=(\d+)/)}`,
    (v.status === 2 && num(vt, /判 (\d+) 项/) === 0 && num(vt, /未测=(\d+)/) === 1) ? 'PASS' : 'FAIL', 3);

  const m = run(['--dir', FIX, '--only', 'no-such-gate']);
  say('S5 --only 命中 0 条 ⇒ NOT_MEASURED（不许"没匹配上就算过"）', `退出码=${m.status} 结论=${(m.text.match(/判 \d+ 项 红=\d+ 未测=\d+ (\w+)/) || [, '?'])[1]}`,
    (m.status === 2 && /NOT_MEASURED/.test(m.text)) ? 'PASS' : 'FAIL', 2);

  const T = fs.mkdtempSync(path.join(os.tmpdir(), 'gates-empty-'));
  const e = run(['--dir', T]);
  say('S6 空判据目录 ⇒ NOT_MEASURED（空门禁不等于绿）', `退出码=${e.status} 件=${(e.text.match(/件=(\d+)/) || [, '?'])[1]}`,
    (e.status === 2 && /NOT_MEASURED/.test(e.text)) ? 'PASS' : 'FAIL', 2);
  fs.rmSync(T, { recursive: true, force: true });

  const c = run(['--dir', FIX, '--only', 'crash-gate']);
  say('S7 判据抛异常 ⇒ NOT_MEASURED 并带异常文本', `退出码=${c.status} 未测=${num(c.text, /未测=(\d+)/)} 说明=${/抛异常/.test(c.text) ? '有' : '无'}`,
    (c.status === 2 && num(c.text, /未测=(\d+)/) === 1 && /抛异常/.test(c.text)) ? 'PASS' : 'FAIL', 3);

  const byStem = run(['--dir', FIX, '--only', '02-row-overlap']);
  say('S8 --only 也认文件名（不逼你记 ID）', `退出码=${byStem.status} 红=${num(byStem.text, /红=(\d+)/)}`,
    (byStem.status === 1 && num(byStem.text, /红=(\d+)/) === 1) ? 'PASS' : 'FAIL', 2);

  for (const l of out) console.log(l);
  const token = red ? 'FAIL' : (nm ? 'NOT_MEASURED' : 'PASS');
  console.log(`判 ${cmp} 项 红=${red} 未测=${nm} ${token}`);
  process.exit(red ? 1 : 0);
}

async function main() {
  const argv = process.argv.slice(2);
  const get = (k, d) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : d; };
  const opts = {};
  argv.forEach((a, i) => { if (a === '--set' && argv[i + 1]) { const j = argv[i + 1].indexOf('='); opts[argv[i + 1].slice(0, j)] = argv[i + 1].slice(j + 1); } });
  if (argv.includes('--help') || argv.includes('-h')) {
    console.log('用法: node run-gates.mjs --dir <判据目录> [--only <id 或文件名>] [--set key=value] | node run-gates.mjs --self');
    console.log("判据件: export const ID = '...'; export function run(ctx) { ctx.cmp('标签', 实得, 期望, '<='); return { id, detail, verdict: 'PASS' }; }");
    console.log(`退出码：0 全绿 / 1 有红 / 2 有未测（红优先）；verdict ∈ ${VERDICTS.join('/')}`);
    return 0;
  }
  if (argv.includes('--self')) { selfTest(); return 0; }
  if (!argv.includes('--dir')) {
    console.log('缺 --dir：不猜判据目录在哪');
    console.log('判 0 项 红=0 未测=1 NOT_MEASURED');
    process.exit(2);
  }
  const res = await runGates(path.resolve(get('--dir', '.')), get('--only', null), opts);
  process.exit(res.exit);
  return 0;
}
await main();
