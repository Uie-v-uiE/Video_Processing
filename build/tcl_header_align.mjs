// 用途：把脚本头注释里的「用途/输出」两行在 .tcl 上换成 §4.2 的词表「作用/产出物」，只动注释行的词头。
// 输入输出：读 git ls-files 里的 .tcl（前 12 行缺 §4.2 要素词的那些）；--apply 时写同名文件；stdout 每文件一行 + 汇总行。
// 退出码：0 全部改到或有基线豁免 1 有用量词头找不到（需手写）或写后不变量破 2 git 不可用。
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..');
const APPLY = process.argv.includes('--apply');
const run = (c) => { try { return execSync(c, { cwd: ROOT, encoding: 'utf8', maxBuffer: 1 << 28 }); } catch { return null; } };
const tcl = (run('git ls-files') || '').split('\n').filter((f) => f.endsWith('.tcl'));
if (tcl.length === 0) { console.log('TCL-ALIGN 判 0 项 NOT_MEASURED 名单为空'); process.exit(2); }
const NEED = /(作用|前置|产出|参数|purpose|inputs?|outputs?)/i;
const codeOnly = (t) => t.split(/\r?\n/).filter((l) => l.trim() !== '' && !/^\s*#/.test(l)).join('\n');
let cmp = 0, red = 0, changed = 0, exempt = 0;
for (const f of tcl) {
  cmp++;
  const abs = path.join(ROOT, f);
  const raw = fs.readFileSync(abs, 'utf8');
  const lines = raw.split(/\r?\n/);
  const head = lines.slice(0, 12).join('\n');
  if (NEED.test(head)) { exempt++; continue; }               // 本来就有 §4.2 的词，不动
  const out = lines.map((l, i) => {
    if (i >= 12) return l;
    return l.replace(/^(\s*#\s*)用途：/, '$1作用：').replace(/^(\s*#\s*)输出：/, '$1产出物：');
  });
  const gotAct = out.slice(0, 12).some((l) => /^\s*#\s*作用：/.test(l));
  const gotOut = out.slice(0, 12).some((l) => /^\s*#\s*产出物：/.test(l));
  if (!gotAct || !gotOut) { red++; console.log(`${f} 缺词头（作用=${gotAct ? '有' : '无'} 产出物=${gotOut ? '有' : '无'}）FAIL`); continue; }
  if (out.length !== lines.length) { red++; console.log(`${f} 行数变了 ${lines.length}→${out.length} FAIL`); continue; }
  const nl = out.join(/\r\n/.test(raw) ? '\r\n' : '\n');
  if (codeOnly(nl) !== codeOnly(raw)) { red++; console.log(`${f} 非注释行被改动 FAIL`); continue; }
  if (!NEED.test(nl.split(/\r?\n/).slice(0, 12).join('\n'))) { red++; console.log(`${f} 换词后仍读不到 §4.2 要素 FAIL`); continue; }
  if (APPLY) {
    fs.writeFileSync(abs, nl);
    if (codeOnly(fs.readFileSync(abs, 'utf8')) !== codeOnly(raw)) { red++; console.log(`${f} 写后读回非注释行不一致 FAIL`); continue; }
  }
  changed++;
  console.log(`${f} 用途→作用 ${gotAct ? 'OK' : 'X'}，输出→产出物 ${gotAct ? 'OK' : 'X'} ${APPLY ? 'APPLIED' : 'CHECK'} PASS`);
}
console.log(`${APPLY ? 'APPLIED' : 'CHECK'} TCL-ALIGN 判 ${cmp} 项 tcl=${tcl.length} 基线已有=${exempt} 待换=${changed} 红=${red} ${red ? 'FAIL' : 'PASS'}`);
process.exit(red ? 1 : 0);
