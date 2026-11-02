#!/usr/bin/env node
// build/r120_rotate_skill_refs.mjs —— 扁平卡退役后的指路改口器（默认只读；--apply 才写）
//
// 用途：把仓库里指向旧扁平卡 `skills/<snake>.md` 的引用改成新条目路径 `skills/<类别>/<kebab>/SKILL.md`。
// 前置条件：在仓库根运行；分派表 `build/evidence/r120_migration_map.txt` 必须存在且每行含
//           `| 旧卡.md | 目标目录 | 类别 |`；未跑 `retire_flat.mjs --apply` 之前也可以先改口（两条形式都幂等）。
// 产出物：只打印；--apply 时逐文件写回并打印"行数变化"。
// 失败时先看哪里：脚本报 REFUSE 时先确认分派表行数=27、再确认被改文件里那条引用是不是"记录原文"
//           （report/log/ 与 report/repro-check.md 里的**逐字记录**不改，那是当时看到的原文）。
//
// 三条规则（每条都打印命中数，抓到 0 条就明说 0 条 —— 不静默）：
//   R1 反引号里的仓库根形式 `skills/<snake>.md` → `skills/<cat>/<kebab>/SKILL.md`
//   R2 只在 skills/ 根下那一份文件里：markdown 链接 ](<snake>.md) → ](<cat>/<kebab>/SKILL.md)
//   R3 技能包条目正文里的反引号裸卡片名 `<snake>.md` → 新条目名 `<cat>/<kebab>`（裸名没有白名单前缀，
//      G8/C3 本来就不判它，但留着就是把旧布局说成现状）
// 不改的对象：report/log/**（追加式台账，逐字记录）、report/repro-check.md 里的引文、report/study/**（不入库的学习文档）。
import fs from 'node:fs';
import path from 'node:path';

const ROOT = process.cwd();
const APPLY = process.argv.includes('--apply');
const MAPFILE = 'build/evidence/r120_migration_map.txt';
const SKIP = [/^report\/log\//, /^report\/study\//, /^docs\/repro-check\.md$/, /^build\/evidence\//, /^\.git/];
if (!fs.existsSync(path.join(ROOT, MAPFILE))) {
  console.log(`MAPFILE 分派表读不到 判 0 项 ${MAPFILE} 缺失 NOT_MEASURED`);
  process.exit(2);
}
const rows = fs.readFileSync(path.join(ROOT, MAPFILE), 'utf8').split(/\r?\n/);
const map = new Map();
for (const r of rows) {
  const m = r.match(/^\|\s*\d+\s*\|\s*([a-z0-9_]+\.md)\s*\|\s*([a-z]+\/[a-z0-9_-]+)\s*\|/);
  if (m) map.set(m[1], m[2]);
}
console.log(`MAP 分派表条目=${map.size} 判 ${map.size} 项 ${map.size === 27 ? 'PASS' : 'FAIL'}`);
if (map.size !== 27) { console.log('MAP 行数不是 27 ⇒ 拒绝改动（先修分派表） FAIL'); process.exit(1); }

function walk(dir, acc) {
  for (const e of fs.readdirSync(path.join(ROOT, dir), { withFileTypes: true })) {
    const rel = dir ? `${dir}/${e.name}` : e.name;
    if (SKIP.some(re => re.test(rel))) continue;
    if (e.isDirectory()) { if (e.name === 'node_modules' || e.name.startsWith('.')) continue; walk(rel, acc); }
    else if (/\.(md|mjs|sh|tcl|py|ps1|txt|csv)$/.test(e.name)) acc.push(rel);
  }
  return acc;
}
const files = walk('', []);
const hits = { R1: 0, R2: 0, R3: 0, R4: 0 };
const perFile = [];
for (const f of files) {
  let txt;
  try { txt = fs.readFileSync(path.join(ROOT, f), 'utf8'); } catch { continue; }
  const before = txt;
  // R1：反引号里的 skills/<snake>.md
  txt = txt.replace(/`skill\/([a-z0-9_]+)\.md`/g, (all, snake) => {
    const t = map.get(`${snake}.md`);
    if (!t) return all;
    hits.R1++;
    return `\`skills/${t}/SKILL.md\``;
  });
  // R2：skills/ 根下那一份文件的相对链接（README.md 是唯一一份，改完由 gen_index 重写生成区）
  // R2/R4 合并成一条"按解析结果改"的规则（老写法只匹配不带 `/` 的目标，漏掉 `../xxx.md` 这种相对链接，
  // 而条目里的交叉引用全是这种形式 ⇒ G8 在退役之后立刻抓到 4 条死链，就是这条规则的射程洞）。
  {
    const dir = path.dirname(f);
    const absSkill = path.join(ROOT, 'skill');
    txt = txt.replace(/\]\(([^)\s]+\.md)\)/g, (all, tgt) => {
      if (/^(https?:)?\/\//.test(tgt)) return all;
      const abs = path.resolve(ROOT, dir, tgt);
      const rel = path.relative(absSkill, abs).split(path.sep).join('/');
      let dest = null;
      if (rel === 'SKILL.md' && f !== 'skills/scripts/check/retire_flat.mjs') dest = path.join(absSkill, 'prompts/round-work-loop/SKILL.md');
      else if (!rel.includes('/') && map.has(rel)) dest = path.join(absSkill, map.get(rel), 'SKILL.md');
      if (!dest) return all;
      hits.R2++;
      return `](${path.relative(dir, dest).split(path.sep).join('/')})`;
    });
  }
  // R3：条目正文里的反引号裸卡片名（只在 skills/ 内判，别处的裸名是"文件名"而非"指路"）
  if (f.startsWith('skills/')) {
    txt = txt.replace(/`([a-z0-9_]+)\.md`/g, (all, snake) => {
      const t = map.get(`${snake}.md`);
      if (!t) return all;
      hits.R3++;
      return `\`${t}\``;
    });
  }
  // R4：整包旧外壳 `skills/prompts/round-work-loop/SKILL.md` 已转成条目 `skills/prompts/round-work-loop/SKILL.md`（2026-10-04）。
  //     反引号形式改成新路径；markdown 链接按"从本文件所在目录出发的相对路径"重算，不硬写层数。
  //     `skills/scripts/check/retire_flat.mjs` 自己除外——它的 C5 就是去查那个文件在不在，改掉就没判据了。
  if (f !== 'skills/scripts/check/retire_flat.mjs') {
    txt = txt.replace(/`skill\/SKILL\.md`/g, '`skills/prompts/round-work-loop/SKILL.md`');
    const dir = path.dirname(f);
    txt = txt.replace(/\]\(([^)/\\]*SKILL\.md)\)/g, (all, tgt) => {
      const abs = path.resolve(ROOT, dir, tgt);
      if (path.relative(path.join(ROOT, 'skill'), abs) !== 'SKILL.md') return all;
      hits.R4++;
      return `](${path.relative(dir, path.join(ROOT, 'skills/prompts/round-work-loop/SKILL.md')).split(path.sep).join('/')})`;
    });
  }
  if (txt !== before) {
    const lb = before.split('\n').length, la = txt.split('\n').length;
    perFile.push({ f, before, txt, lb, la });
  }
}
for (const p of perFile) {
  const d = (p.txt.match(/\b\w+\b/g) || []).length - (p.before.match(/\b\w+\b/g) || []).length;
  console.log(`FILE ${p.f} 行数 ${p.lb}->${p.la} 词数Δ=${d} R1..R3 命中在此文件`);
}
console.log(`RULE R1 反引号仓库根形式 抓到 ${hits.R1} 处`);
console.log(`RULE R2 skills/根相对链接 抓到 ${hits.R2} 处`);
console.log(`RULE R3 条目内裸卡片名 抓到 ${hits.R3} 处`);
console.log(`RULE R4 整包旧外壳 SKILL.md（反引号+相对链接）抓到 ${hits.R4} 处`);
if (!APPLY) { console.log(`CHECK 待改文件=${perFile.length} 判 ${hits.R1 + hits.R2 + hits.R3 + hits.R4} 处 只读模式 PASS`); process.exit(0); }
let bad = 0;
for (const p of perFile) {
  if (p.la !== p.lb) { console.log(`APPLY 拒绝 ${p.f} 行数变了 ${p.lb}->${p.la}（改口只允许同长度替换） FAIL`); bad++; continue; }
  fs.writeFileSync(path.join(ROOT, p.f), p.txt, 'utf8');
}
const left = files.filter(f => !SKIP.some(re => re.test(f)))
  .filter(f => { try { return new RegExp('`skills/(' + [...map.keys()].join('|') + ')`').test(fs.readFileSync(path.join(ROOT, f), 'utf8')); } catch { return false; } }).length;
console.log(`APPLY 写完=${perFile.length - bad} 个文件；R1 残留文件数=${left} 判 ${perFile.length} 项 ${(bad === 0 && left === 0) ? 'PASS' : 'FAIL'}`);
process.exit(bad === 0 && left === 0 ? 0 : 1);
