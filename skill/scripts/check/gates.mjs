#!/usr/bin/env node
/**
 * skill/scripts/check/gates.mjs — 技能包装配门禁 G1..G12（只读，不改任何文件）
 *
 * 用法：node skill/scripts/check/gates.mjs [--json] [--only G7,G9]
 * 退出码：0=全绿 1=有 FAIL 2=有 NOT_MEASURED（读不到输入不等于通过） 3=前置不满足（skill/ 不存在）
 *
 * 设计约束（这个仓库的规矩，写在 skill/_meta/naming-and-format.md）：
 *  - 一条判据一行输出，判定 token 放在最后一个字段；标签文字与列宽属于判据的一部分；
 *  - 计数器数的是"做了多少次比较"，不是"通过了多少次"，每条打印分母 `判 N 项`；
 *  - 硬判据与提示性检查分开：G3 的语言学部分只作提示（advisory），不判红；
 *  - 读不到输入 ⇒ NOT_MEASURED，绝不 ⇒ PASS。
 */
import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';

const ROOT = path.resolve(process.cwd());
const SKILL = path.join(ROOT, 'skill');
const args = process.argv.slice(2);
const only = (args.find(a => a.startsWith('--only=')) || '').replace('--only=', '').split(',').filter(Boolean);
const want = id => only.length === 0 || only.includes(id);

if (!fs.existsSync(SKILL)) { console.log('GATES 前置不满足：找不到 skill/ 目录 NOT_MEASURED'); process.exit(3); }

const CATEGORIES = ['prompts', 'templates', 'scripts', 'pitfalls', 'runtime', 'references'];
const HEADINGS = ['## 1. 一句话用途', '## 2. 适用场景', '## 3. 不适用 / 失效条件', '## 4. 前置条件',
                  '## 5. 使用方法', '## 6. 判读与失败分叉', '## 7. 已验证的效果', '## 8. 提炼来源与边界'];

function walk(dir, acc = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, acc); else acc.push(p);
  }
  return acc;
}
const rel = p => path.relative(ROOT, p).split(path.sep).join('/');
const read = p => fs.readFileSync(p, 'utf8');

const entryDirs = [];
for (const c of CATEGORIES) {
  const base = path.join(SKILL, c);
  if (!fs.existsSync(base)) continue;
  for (const e of fs.readdirSync(base, { withFileTypes: true })) {
    if (e.isDirectory() && !e.name.startsWith('_')) entryDirs.push(path.join(base, e.name));
  }
}
// 与 gen_index.mjs 用同一套"什么算条目"的定义：skill/ 根下的单目录条目也算（两把尺子各数各的 = #46 那一族）
// 范围修正（2026-10-04 第三方审计指出）：`skill/evals/` 是 P08 规定的"验证记录"目录、
// `skill/scripts/selftest/` 是 P04 规定的 fixture+runner 目录，两者都**不是技能条目**，
// 不该按"条目必须有 SKILL.md"来判红（G11 专门管 selftest 可跑，records 由 gen_index 与 P08 口径管）。
const NON_ENTRY_DIRS = new Set(['evals', '_meta']);
for (const e of fs.readdirSync(SKILL, { withFileTypes: true })) {
  if (!e.isDirectory() || e.name.startsWith('_') || CATEGORIES.includes(e.name) || NON_ENTRY_DIRS.has(e.name)) continue;
  entryDirs.push(path.join(SKILL, e.name));
}
// scripts/ 的六个脚本目录里，check/ 与 selftest/ 也是目录但不是技能条目 ⇒ 只有带 SKILL.md 的才算条目
const isNonEntry = d => NON_ENTRY_DIRS.has(path.basename(d))
  || /(^|[\\/])selftest$/.test(d) || /(^|[\\/])_out$/.test(d) || /(^|[\\/])out$/.test(d);
const entries = entryDirs.filter(d => !isNonEntry(d) && fs.existsSync(path.join(d, 'SKILL.md')));
const entrysWithoutSkill = entryDirs.filter(d => !isNonEntry(d) && !fs.existsSync(path.join(d, 'SKILL.md')));

const allFiles = walk(SKILL);
const mdFiles = allFiles.filter(f => f.endsWith('.md'));
const lines = [];
let fail = 0, notmeasured = 0, pass = 0;
function say(id, label, made, detail, verdict) {
  if (!want(id)) return;
  if (verdict === 'FAIL') fail++; else if (verdict === 'NOT_MEASURED') notmeasured++; else pass++;
  lines.push(`${id} ${label.padEnd(26)} 判 ${made} 项 ${detail} ${verdict}`);
}

// G1 命名：skill/ 下所有文件与目录必须是纯 ASCII 小写（字母数字 - _ .）
{
  let bad = [];
  for (const f of allFiles) {
    const parts = rel(f).split('/').slice(1);
    for (const p of parts) { if (p === 'README.md' || p === 'SKILL.md') continue; if (!/^[a-z0-9._-]+$/.test(p)) { bad.push(rel(f)); break; } }
  }
  const n = allFiles.length;
  say('G1', '命名纯 ASCII 小写', n, bad.length ? `违规=${bad.length} 例:${bad.slice(0, 3).join(' ')}` : `违规=0 扫=${n}`,
      n === 0 ? 'NOT_MEASURED' : (bad.length ? 'FAIL' : 'PASS'));
}

// G2 每个条目目录有 SKILL.md 且 frontmatter 的 name == 目录名
{
  const made = entryDirs.length;
  const bad = [];
  for (const d of entries) {
    const txt = read(path.join(d, 'SKILL.md'));
    const m = txt.match(/^---\n([\s\S]*?)\n---/);
    const dirName = path.basename(d);
    if (!m) { bad.push(`${dirName}:无 frontmatter`); continue; }
    const nm = (m[1].match(/^name:\s*(.+)$/m) || [, ''])[1].trim();
    if (nm !== dirName) bad.push(`${dirName}:name=${nm || '空'}`);
  }
  for (const d of entrysWithoutSkill) bad.push(`${rel(d)}:缺 SKILL.md`);
  say('G2', '条目外壳与 name', made,
      made === 0 ? '条目数=0（无法判定）' : (bad.length ? `不合=${bad.length} 例:${bad.slice(0, 3).join(' ')}` : `条目=${made} 全合`),
      made === 0 ? 'NOT_MEASURED' : (bad.length ? 'FAIL' : 'PASS'));
}

// G3 description：单行、≤1024、第三人称（语言学部分只提示，不判红）
{
  let made = 0; const bad = []; const advisory = [];
  for (const d of entries) {
    const m = read(path.join(d, 'SKILL.md')).match(/^description:\s*(.+)$/m);
    made++;
    if (!m) { bad.push(`${path.basename(d)}:无 description`); continue; }
    const v = m[1].trim();
    if (/\n/.test(v) || v.length > 1024) bad.push(`${path.basename(d)}:长度或换行=${v.length}`);
    if (/^(本技能|本文|我们|我)/.test(v)) advisory.push(path.basename(d));
  }
  say('G3', 'description 形状', made,
      made === 0 ? '条目数=0（无法判定）' : `硬错=${bad.length}${advisory.length ? ` 提示性(第一人称)=${advisory.length}` : ''}`,
      made === 0 ? 'NOT_MEASURED' : (bad.length ? 'FAIL' : 'PASS'));
}

// G4 八节齐全且顺序正确（按标题字符串核对，不按行号）
{
  let made = 0; const bad = [];
  for (const d of entries) {
    made++;
    const txt = read(path.join(d, 'SKILL.md'));
    const body = txt.replace(/^---[\s\S]*?---/, '');
    const idx = HEADINGS.map(h => body.indexOf(h));
    const missing = idx.filter(i => i < 0).length;
    const ordered = idx.every((v, i) => i === 0 || v > idx[i - 1]);
    if (missing || !ordered) bad.push(`${path.basename(d)} 缺${missing}节${ordered ? '' : '/顺序错'}`);
  }
  say('G4', '八节外壳', made,
      made === 0 ? '条目数=0（无法判定）' : (bad.length ? `不合=${bad.length} 例:${bad.slice(0, 3).join(' ')}` : `条目=${made} 八节齐且有序`),
      made === 0 ? 'NOT_MEASURED' : (bad.length ? 'FAIL' : 'PASS'));
}

// G5 无 TODO/FIXME，且条目目录内不得再放 README.md
{
  const bad = [];
  let exempt = 0;
  const selfPath = rel(path.join(SKILL, '_meta', 'naming-and-format.md'));
  for (const f of mdFiles) {
    const t = read(f);
    if (!/\bTODO\b|\bFIXME\b/.test(t)) continue;
    // 唯一的豁免：判据定义文件本身必须写出这两个词才能说明规则是什么。豁免必须随行念出来，
    // 且只在"这一行是在讲 G5 本身"时生效；别的文件里有 TODO 一律照判。
    if (rel(f) === selfPath && /G5/.test(t)) { exempt++; continue; }
    bad.push(rel(f));
  }
  const inner = entries.map(d => path.join(d, 'README.md')).filter(p => fs.existsSync(p));
  say('G5', '无 TODO/第二份 README', mdFiles.length,
      `残留=${bad.length}${exempt ? ` 念出豁免=${exempt}（_meta/naming-and-format.md 是判据定义处）` : ''}${inner.length ? ` 内层README=${inner.length}` : ''}`,
      mdFiles.length === 0 ? 'NOT_MEASURED' : ((bad.length || inner.length) ? 'FAIL' : 'PASS'));
}

// G6 长度分层：SKILL.md ≤500 行；>100 行的参考页要有目录
{
  let made = 0; const bad = [];
  for (const f of mdFiles) {
    const t = read(f); const n = t.split('\n').length; made++;
    if (f.endsWith('SKILL.md') && n > 500) bad.push(`${rel(f)} ${n} 行`);
    if (!f.endsWith('SKILL.md') && n > 100 && !/##\s*(目录|Contents|内容索引)|BEGIN GENERATED INDEX/.test(t)) bad.push(`${rel(f)} >100 行无目录`);
  }
  say('G6', '长度与按需分层', made, made === 0 ? '文件数=0（无法判定）' : `越界=${bad.length}${bad.length ? ' 例:' + bad.slice(0, 2).join(' ') : ''}`,
      made === 0 ? 'NOT_MEASURED' : (bad.length ? 'FAIL' : 'PASS'));
}

// G7 README 一览表 ↔ 实际条目 双向一致（孤儿=0）
{
  const rp = path.join(SKILL, 'README.md');
  if (!fs.existsSync(rp)) say('G7', '索引双向一致', 0, '缺 skill/README.md（由 gen_index.mjs 生成）', 'NOT_MEASURED');
  else {
    const t = read(rp);
    const rows = [...t.matchAll(/^\|\s*`(skill\/[^`]+\/SKILL\.md)`/gm)].map(m => m[1]);
    const listed = new Set(rows.map(r => path.resolve(ROOT, r).replace(/SKILL\.md$/, '')));
    const actual = new Set(entries.map(d => d + path.sep));
    const orphans = [...listed].filter(p => !fs.existsSync(path.join(p, 'SKILL.md')));
    const missing = [...entries].filter(d => !listed.has(d + path.sep));
    say('G7', '索引双向一致', rows.length + entries.length,
        `表列=${listed.size} 实际=${entries.length} 死行=${orphans.length} 漏条=${missing.length}`,
        // 审计指出的洞：表 0 行 + 条目 0 个时上面三个数全为 0，原来会判 PASS（空集上的真）。
        (rows.length === 0 || entries.length === 0)
          ? `条目或表为空（表=${rows.length} 条目=${entries.length}），空集不构成通过`
          : (orphans.length || missing.length) ? `死行=${orphans.length} 漏条=${missing.length}` : '双向一致',
        (rows.length === 0 || entries.length === 0) ? 'NOT_MEASURED' : ((orphans.length || missing.length) ? 'FAIL' : 'PASS'));
  }
}

// G8 链接：相对链接可解析；外部 URL 必须在 _meta/sources.md 有行
{
  let made = 0; const dead = []; const ext = [];
  const srcPath = path.join(SKILL, '_meta', 'sources.md');
  const srcTxt = fs.existsSync(srcPath) ? read(srcPath) : '';
  for (const f of mdFiles) {
    const txt = read(f);
    for (const m of txt.matchAll(/\[([^\]]+)\]\(([^)]+)\)/g)) {
      const url = m[2].trim();
      if (/^https?:/.test(url)) { made++; if (!srcTxt.includes(url)) ext.push(`${rel(f)} ${url}`); continue; }
      if (/^#|^mailto:/.test(url)) continue;
      made++;
      const clean = url.split('#')[0];
      if (!clean) continue;
      const target = path.resolve(path.dirname(f), clean);
      if (!fs.existsSync(target)) dead.push(`${rel(f)} → ${url}`);
    }
    // 反引号里的仓库内路径也要能解析（这一条抓的是"指路不存在"）
    // 审计指出的洞：前缀白名单原来不含 `skill/` ⇒ `README.md:318` 指向不存在的 `_MANIFEST.md`、
    // `report_metrics.mjs:6` 指向不存在的自身 SKILL.md 都检不出来。
    for (const m of txt.matchAll(/`((?:build|src|report|board|data|sim|docs|submit|skill)\/[^`\s]+)`/g)) {
      const p = m[1].replace(/[:@].*$/, '');
      if (/[*<>{}]|rNN|^report\/log\/ISSUES\.md$/.test(p)) continue;
      if (!/\.(md|v|sv|tcl|sh|py|ps1|bat|mjs|txt|rpt|csv|json|xdc|xsa|bit|elf|pdf|log|html|tsv)$/.test(p) && !p.endsWith('/')) continue;
      made++;
      if (!fs.existsSync(path.resolve(ROOT, p))) dead.push(`${rel(f)} → ${m[1]}`);
    }
  }
  say('G8', '链接与指路可解析', made,
      made === 0 ? '一条链接都没读到（无法判定）' : `死链=${dead.length}${dead.length ? ' 例:' + dead.slice(0, 3).join(' | ') : ''} 无台账外链=${ext.length}${ext.length ? ' 例:' + ext.slice(0, 2).join(' | ') : ''}`,
      made === 0 ? 'NOT_MEASURED' : ((dead.length || ext.length) ? 'FAIL' : 'PASS'));
}

// G9 降级标记可见：三类标记逐文件计数并汇总（计数不是错误，但必须可见）
{
  const marks = { '【填入】': 0, '【待验证】': 0, '【未核实】': 0, '【未实测】': 0 };
  let filesWith = 0;
  for (const f of mdFiles) {
    const t = read(f); let hit = 0;
    for (const k of Object.keys(marks)) {
      const c = (t.match(new RegExp(k.replace(/[\[\]]/g, '\\$&'), 'g')) || []).length;
      marks[k] += c; hit += c;
    }
    if (hit) filesWith++;
  }
  const sum = Object.values(marks).reduce((a, b) => a + b, 0);
  // 审计指出的洞：判定原来是硬编码 'PASS'，mdFiles 全空也报绿。计数本身不是错误（条文要求"必须可见"），
  // 但"一条都没读到"不能算这一项做过 ⇒ 无文件 = NOT_MEASURED。
  say('G9', '降级标记计数', mdFiles.length,
      `总${sum} 填入=${marks['【填入】']} 待验证=${marks['【待验证】']} 未核实=${marks['【未核实】']} 未实测=${marks['【未实测】']} 分布在 ${filesWith} 个文件`,
      mdFiles.length === 0 ? 'NOT_MEASURED' : 'PASS');
}

// G10 专有名不泄漏：命中必须为 0，或同行标注"示例取值"或【填入】
{
  const tnPath = path.join(SKILL, '_meta', 'team-names.txt');
  if (!fs.existsSync(tnPath)) say('G10', '本队专有名', 0, '缺 skill/_meta/team-names.txt', 'NOT_MEASURED');
  else {
    const names = read(tnPath).split('\n').filter(l => l && !l.startsWith('#'))
      .map(s => s.trim()).filter(s => s.length >= 5 && !s.includes('.'));
    const entriesTxt = entries.map(d => read(path.join(d, 'SKILL.md')));
    let made = 0; const hits = [];
    for (let i = 0; i < entriesTxt.length; i++) {
      for (const line of entriesTxt[i].split('\n')) {
        for (const n of names) {
          if (!line.includes(n)) continue;
          made++;
          if (!/示例取值|【填入】|本仓|仓库内|ISSUES|example/i.test(line)) hits.push(`${path.basename(entries[i])}/${n}`);   // 审计指出：原来这行是 `basename(entries[i] ? '' : '')` 恒为空串，命中项不带文件名，红了也找不到在哪
        }
      }
    }
    // 审计指出的洞：名单过滤后为空时原来判 PASS（空集上的真）。名单为空 = 这条判据没被喂过料，只能 NOT_MEASURED。
    say('G10', '本队专有名', made, `名单=${names.length} 命中=${made} 未标注=${hits.length}${hits.length ? ' 例:' + [...new Set(hits)].slice(0, 3).join(' ') : ''}`,
        names.length === 0 ? 'NOT_MEASURED' : (hits.length ? 'FAIL' : 'PASS'));
  }
}

// G11 判据/脚本可跑：selftest 全量串跑，逐条打印"判 N 项"
{
  const st = path.join(SKILL, 'scripts', 'selftest', 'run_all.sh');
  if (!fs.existsSync(st)) say('G11', '脚本 selftest 可跑', 0, `缺 ${rel(st)}`, 'NOT_MEASURED');
  else {
    let out = ''; let rc = 0;
    try { out = execSync(`bash "${st}"`, { cwd: ROOT, encoding: 'utf8' }); }
    catch (e) { out = String(e.stdout || '') + String(e.stderr || ''); rc = e.status === undefined ? 1 : e.status; }
    const denom = (out.match(/判 \d+ 项/g) || []).length;
    const badTok = (out.match(/NOT_MEASURED/g) || []).length;
    say('G11', '脚本 selftest 可跑', denom, `rc=${rc} 分母行=${denom} NOT_MEASURED 行=${badTok}`,
        rc === 0 && denom > 0 ? 'PASS' : 'FAIL');
  }
}

// G12 编码：UTF-8 无 BOM、无被截断的多字节字符（截断会让文件对 grep 呈二进制）
{
  let made = 0; const bad = [];
  for (const f of mdFiles) {
    made++;
    const buf = fs.readFileSync(f);
    if (buf[0] === 0xEF && buf[1] === 0xBB && buf[2] === 0xBF) bad.push(`${rel(f)}:BOM`);
    const t = buf.toString('utf8');
    if (t.includes('\uFFFD')) bad.push(`${rel(f)}:截断字节`);
  }
  say('G12', '编码与截断字节', made, made === 0 ? '文件数=0（无法判定）' : `坏=${bad.length}${bad.length ? ' 例:' + bad.slice(0, 3).join(' ') : ''}`,
      made === 0 ? 'NOT_MEASURED' : (bad.length ? 'FAIL' : 'PASS'));
}

for (const l of lines) console.log(l);
const total = pass + fail + notmeasured;
console.log(`GATES 技能包：判定 ${total} 项 绿=${pass} 红=${fail} 未测=${notmeasured} —— ` +
            (fail ? '有红项，不提交' : (notmeasured ? `还有 ${notmeasured} 项读不到输入，别念成绿` : '不采纳，保留上一版')) +
            ` ${fail ? 'FAIL' : (notmeasured ? 'NOT_MEASURED' : 'PASS')}`);
process.exit(fail ? 1 : (notmeasured ? 2 : 0));
