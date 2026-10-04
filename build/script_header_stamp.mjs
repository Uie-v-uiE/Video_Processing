// 用途：给缺三要素头注释的脚本补「用途/输入/输出/退出码」四行，四行都只写**该文件里能证明的东西**。
// 输入输出：读 git ls-files 里的 .mjs/.py/.tcl/.sh（不含 build/evidence/）；--apply 时写同名文件的注释块；
//          stdout 每文件一行推导结果，供人抽查。
// 退出码：0 无推导失败 1 有文件推不出用途（此时 --apply 也不动它） 2 环境错误（git 不可用）。
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..');
const args = process.argv.slice(2);
const APPLY = args.includes('--apply');
const only = args.filter((a) => !a.startsWith('--'));
const run = (c) => { try { return execSync(c, { cwd: ROOT, encoding: 'utf8', maxBuffer: 1 << 28 }); } catch { return null; } };

const EXT_RE = /\.(mjs|py|tcl|sh)$/;
const HAS_KEY = /(用途|作用|输入|输出|退出码|usage|purpose|exit code|outputs?)/i;
const list = (only.length ? only : (run('git ls-files') || '').split('\n'))
  .filter((f) => EXT_RE.test(f) && !f.startsWith('build/evidence'))
  // 夹具与期望产物**不盖章**：它们要被生成器逐字节比对，加四行注释就会让自测红
  .filter((f) => !/\/(fixtures?|expected)\//.test(f) || only.length > 0);
if (!only.length && list.length === 0) { console.log('STAMP 判 0 项 NOT_MEASURED git 不可用'); process.exit(2); }

const stripMarker = (l) => l.replace(/^\s*(#+|\/\/+|<!--|rem\s?|\*<?)\s?/i, '').trim();
// 取到第一个句子边界为止，不在逗号/顿号/冒号处收尾（避免写出半句话）
function firstSentence(t) {
  const cut = t.split(/[。！？]/)[0].trim();
  if (cut.length <= 96) return cut;
  const head = cut.slice(0, 96);
  const at = Math.max(head.lastIndexOf('；'), head.lastIndexOf(';'), head.lastIndexOf('，'), head.lastIndexOf(' '));
  return (at > 24 ? head.slice(0, at) : cut.slice(0, 96)).trim();
}
// 1) 用途：前 14 行里第一条"像描述"的行，逐字复用（去掉行首对自身的文件名/路径引用）
function derivePurpose(lines, self) {
  for (const raw of lines.slice(0, 14)) {
    const t = stripMarker(raw);
    if (!t || t.length < 10) continue;
    if (/^#!|\/-\*-|timescale|^@echo|^set\s+root|^\$\Id/i.test(t)) continue;
    const isDesc = /[一-龥]/.test(t) || /—/.test(t) || /^[\w./\-]+ (?:-|–|—) /.test(t) || /\b(create|build|read|probe|check|export|scan|patch|render|verify)\b/i.test(t);
    if (!isDesc) continue;
    const noSelf = t.replace(new RegExp(`^\\s*(?:${self.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}|${path.basename(self).replace(/[.*+?^${}()|[\]\\]/g, '\\$&')})\\s*[—\\-–:：]+\\s*`), '').trim();
    const s = firstSentence(noSelf || t);
    if (s.length >= 10) return s;
  }
  return '';
}
// 2) 输入/输出：路径字面量必须**紧跟**在写信号之后（≤12 字符）才算"它写这个文件"；读信号同理。
//    文中只是提到某个路径（注释、被调用的脚本名）不参与判定，避免把"引用"写成"产物"。
const WRITE_ADJ = /(?:writeFileSync|appendFileSync|createWriteStream|tee\s+-a|>\s*|>>\s*|-file\s+|--out(?:put)?[=\s])\s*['"`]?(?:\.\/)?((?:build|report|data|src|sim|board|skills)\/[\w.\-\/]*\w)/;
const READ_ADJ = /(?:readFileSync|readFile|open|<\s*|source\s+|\|\s*)\s*['"`]?(?:\.\/)?((?:build|report|data|src|sim|board|skills)\/[\w.\-\/]*\w)/;
function deriveIo(text, self) {
  const reads = new Set(), writes = new Set();
  for (const l of text.split(/\r?\n/)) {
    if (/^\s*(#|\/\/|\*)/.test(l)) continue;               // 注释行里的路径只是提及，不算 IO
    const w = l.match(new RegExp(WRITE_ADJ.source, 'g')) || [];
    for (const m of w) {
      const p = (m.match(WRITE_ADJ) || [])[1];
      if (p && p !== self && /[.\/]$|\w/.test(p) && /\./.test(p)) writes.add(p);
    }
    const r = l.match(new RegExp(READ_ADJ.source, 'g')) || [];
    for (const m of r) {
      const p = (m.match(READ_ADJ) || [])[1];
      if (p && p !== self && /\./.test(p)) reads.add(p);
    }
  }
  return { reads: [...reads].slice(0, 3), writes: [...writes].slice(0, 3) };
}
// 3) 退出码：只列文件里真的写了的 exit N；判定词取 exit 那一行里的现成 token
function deriveExit(text) {
  const codes = new Set();
  for (const m of text.matchAll(/(?:^|[^a-z_])(?:exit|sys\.exit|process\.exit)\s*\(?\s*(\d+)/g)) codes.add(m[1]);
  const named = [...codes].sort((a, b) => a - b).map((c) => {
    if (c === '0') return '0=跑完';
    const line = (text.split(/\r?\n/).find((l) => /(?:exit|sys\.exit|process\.exit)\s*\(?\s*0?\b/.test(l) && false) || '');
    const tok = (text.split(/\r?\n/).find((l) => new RegExp(`exit\\s*\\(?${c}\\b`).test(l)) || '');
    const w = (tok.match(/\b(REFUSE|FAIL|NOT_MEASURED|ERROR|拒|失败|错误|缺|不可用)\b/) || [])[1];
    return w ? `${c}=${w}` : `${c}=非 0 分支（该文件 exit ${c} 那一行）`;
  });
  return named.length ? named.join(' ') : '脚本内无显式 exit ⇒ 随最后一条命令（正常跑完为 0）';
}

const markerFor = (f) => (/\.mjs$/.test(f) ? '//' : '#');
let pending = 0, have = 0, bad = 0;
const rows = [];
for (const f of list) {
  const abs = path.join(ROOT, f);
  if (!fs.existsSync(abs)) { bad++; rows.push(`${f} 缺文件 FAIL`); continue; }
  const raw = fs.readFileSync(abs, 'utf8');
  const lines = raw.split(/\r?\n/);
  if (HAS_KEY.test(lines.slice(0, 12).join('\n'))) { have++; continue; }
  const purpose = derivePurpose(lines, f);
  if (!purpose) { bad++; rows.push(`${f} 用途推不出（前 14 行没有带中文的描述行） FAIL`); continue; }
  const io = deriveIo(raw, f);
  const mk = markerFor(f);
  const argv = /process\.argv|sys\.argv|argv\[\d|\$\{?\d+\}?|--[a-z-]+=['"]?|\bget\(['"]/.test(raw);
  const inp = [argv ? '命令行参数' : null, /process\.stdin|sys\.stdin|readFileSync\(0/.test(raw) ? '标准输入' : null, ...io.reads].filter(Boolean);
  const outp = io.writes.length ? io.writes : [/print\(|\$display|\bputs\b|console\.log|echo /.test(raw) ? 'stdout' : null].filter(Boolean);
  const block = [
    `${mk} 用途：${purpose}`,
    `${mk} 输入：${inp.length ? inp.join('、') : '无字面量输入路径；参数解析见本文件'}`,
    `${mk} 输出：${outp.length ? outp.join('、') : 'stdout（本文件没有仓库内的写盘路径字面量）'}`,
    `${mk} 退出码：${deriveExit(raw)}`,
  ];
  let at = 0;
  while (at < lines.length && /^#!|^\s*timescale|^-\*-|^\/\/\s*-\*-/.test(lines[at])) at++;
  rows.push(`${f} @${at + 1} | ${block.map((b) => b.replace(new RegExp(`^${mk} ?`), '')).join(' | ')}`);
  if (APPLY) {
    // 保持该文件自己的换行风格：CRLF 文件不能因为插四行就整篇变成 LF
    const eol = /\r\n/.test(raw) ? '\r\n' : '\n';
    const nl = [...lines.slice(0, at), ...block, ...lines.slice(at)].join(eol);
    if (nl.length <= raw.length) { bad++; rows.push(`${f} 结果没变长，拒绝写入 FAIL`); continue; }
    const crBefore = (raw.match(/\r/g) || []).length, crAfter = (nl.match(/\r/g) || []).length;
    const crWant = crBefore + (eol === '\r\n' ? block.length : 0);
    const linesAfter = nl.split(/\r?\n/).length;
    if (crAfter !== crWant || linesAfter !== lines.length + block.length) {
      bad++; rows.push(`${f} 换行或行数对不上（CR ${crBefore}→${crAfter} 应为 ${crWant}；行 ${lines.length}→${linesAfter} 应为 ${lines.length + block.length}），拒绝写入 FAIL`); continue;
    }
    fs.writeFileSync(abs, nl);
    const back = fs.readFileSync(abs, 'utf8').split(/\r?\n/).slice(0, at + 5).join('\n');
    if (!/用途/.test(back) || !/退出码/.test(back)) { bad++; rows.push(`${f} 写完读回缺要素 FAIL`); continue; }
  }
  pending++;
}
rows.forEach((r) => console.log(r));
console.log(`${APPLY ? 'APPLIED' : 'CHECK'} STAMP 判 ${pending + have + bad} 项 待写=${pending} 已有=${have} 推导失败=${bad} ${bad ? 'FAIL' : 'PASS'}`);
process.exit(bad ? 1 : 0);
