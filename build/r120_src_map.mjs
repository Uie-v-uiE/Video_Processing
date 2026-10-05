#!/usr/bin/env node
// build/r120_src_map.mjs —— 生成 `report/src-map.md`（源码地图），只做"能从盘上直接读出来"的四列
//
// 用途：把 `src/rtl/**.v` 与 `src/ps/**.{c,h}` 逐个列成一张可对账的表，供接手的人定位文件。
// 前置条件：在仓库根运行；不需要工具链，纯读文件。
// 产出物：stdout 一份 markdown（重定向进 `report/src-map.md`）；不写任何文件。
// 失败时先看哪里：某行"头注"列为空 ⇒ 那个文件首行不是 `//` 注释，是文件本身没写头注（照实留空，不替它编）。
//
// 四列全部现算，不import任何人工汇总：路径 | 声明的 module/顶层符号 | 行数 | 文件头注第一行（逐字）
// 计数地板：文件数必须 = `git ls-files src/rtl src/ps` 里源码文件数，对不上直接 REFUSE。
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const ROOT = process.cwd();
const rel = p => path.relative(ROOT, p).split(path.sep).join('/');
function walk(dir, acc) {
  if (!fs.existsSync(dir)) return acc;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const abs = path.join(dir, e.name);
    if (e.isDirectory()) walk(abs, acc);
    else if (/\.(v|c|h)$/.test(e.name)) acc.push(abs);
  }
  return acc;
}
const files = walk(path.join(ROOT, 'src'), []).sort();
let tracked = [];
try {
  tracked = execFileSync('git', ['ls-files', '-z', 'src'], { cwd: ROOT, encoding: 'utf8' })
    .split('\u0000').filter(f => /\.(v|c|h)$/.test(f));
} catch { tracked = []; }
if (files.length !== tracked.length) {
  console.log(`REFUSE 盘上源码=${files.length} 与 git 跟踪=${tracked.length} 不一致 ⇒ 先搞清是谁没入库，不出地图 FAIL`);
  process.exit(3);
}
const rows = [];
let noHead = 0;
for (const abs of files) {
  const txt = fs.readFileSync(abs, 'utf8');
  const lines = txt.split(/\r?\n/);
  const syms = txt.match(/^\s*(module|function|procedure)\s+([A-Za-z_]\w*)/gm) || [];
  const names = syms.map(s => s.trim().split(/\s+/)[1]).filter(Boolean);
  let head = '';
  for (const l of lines.slice(0, 16)) {
    const m = l.match(/^\s*\/\/\s*(.+)$/) || l.match(/^\s*\/?\*+\s*(.+)$/);
    if (m && !/^\s*$/.test(m[1]) && !/^[!*/=\-]/.test(m[1].trim()) && /[A-Za-z0-9\u4e00-\u9fff]/.test(m[1])) { head = m[1].trim(); break; }
  }
  if (!head) noHead++;
  rows.push(`| \`${rel(abs)}\` | ${names.join(', ') || '`（无 module：C/H 或纯 include）`'} | ${lines.length} | ${head.replace(/\|/g, '\\|')} |`);
}
console.log('# 源码地图（`src/` 逐文件的四列现算表）');
console.log('');
console.log(`本文件由 \`node build/r120_src_map.mjs\` 生成，重定向进 \`report/src-map.md\`；` +
  `本次覆盖 **${rows.length} 个源文件**（` +
  '= git 跟踪的 src/ 下 *.v/*.c/*.h 数，两个数由脚本现算比对，不一致就 REFUSE 不出图）。');
console.log('');
console.log('## 这四列能回答什么、不能回答什么');
console.log('');
console.log('- **能**：某个模块在哪个文件、文件多大、作者自己在头注里写的第一句是什么（逐字搬运，不改写）。');
console.log('- **不能**：数据流顺序、时钟域归属、寄存器位序——那些分别在各文档里有权威口径，本表不复制，' +
  '复制就会有两份真相。指路：数据通路看 `report/architecture.md`，' +
  '时钟域看 `report/board_pins.md` 与 `report/build.md`，寄存器看 `skills/runtime/register-map/SKILL.md`，' +
  '台架对应关系看 `sim/README.md`。');
console.log(`- 头注列为空的有 ${noHead} 个文件（照实留空，不替它补句子）。`);
console.log('');
console.log('| 路径 | 声明的 module | 行数 | 文件头注第一行（逐字） |');
console.log('| --- | --- | --- | --- |');
for (const r of rows) console.log(r);
console.log('');
console.log(`MAP 生成 文件=${rows.length} 头注缺=${noHead} 判 ${rows.length} 项 ${rows.length > 0 ? 'PASS' : 'NOT_MEASURED'}`);
