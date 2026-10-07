#!/usr/bin/env node
// build/r129_path_sanitize.mjs —— 把仓库里**非证据层**文件正文的本机绝对路径换成占位符。
//
// 为什么要有这一支：用户 2026-10-07 口径"本机路径改一下吧，交付看的是链接"。
// 但同一件事有两半：
//   · 改得：Vivado/Vitis 工程树里的生成件正文、手写源码注释里指向本机资料库的路径、脚本用法示例。
//   · 改不得：`build/`、`board/measured|evidence*`、`report/log/` 这些**证据与留档正文**——
//     它们记的是"当时读的是哪一台机器上的哪一份"，改掉等于改写证据（导出器的绝对路径判据
//     把这一层写成"只报数不判红"就是同一个道理）。这一支默认**不动**它们，并且把不动的条数念出来。
// 二进制（含 NUL 的 .obj/.a/.dcp/...）不改字节——改了就是损坏，只报数。
//
// 用法：node build/r129_path_sanitize.mjs [--apply]
// 退出码：0 = 跑完；1 = 射程判据红（一条都没扫到 ⇒ 这一层多半没接上）
'use strict';
import fs from 'fs';
import path from 'path';
import cp from 'child_process';

const REPO = cp.execSync('git rev-parse --show-toplevel', {encoding:'utf8'}).trim();
const APPLY = process.argv.includes('--apply');

// 最长优先，先具体后泛化。⚠ JS 字面量里反斜杠要写成 `\\`（一个真实反斜杠 = 源码里两个）：
// 第一版误写成 `\\\\`（= 两个反斜杠），于是所有 Windows 反向斜杠的形状一条都没替换，
// `--check` 打的"残留 …build.ninja 还剩 371 条"就是它——判据把假绿抓住了，别把这种残留当"映射表没覆盖的形状"忽略掉。
const MAP = [
  ['D:/Xilinx/Prj/pro/Video_Processing', '<repo>'],
  ['D:\\Xilinx\\Prj\\pro\\Video_Processing', '<repo>'],
  ['D:/Xilinx/Prj/pro/delivery_review_20261005', '<repo>'],
  ['D:\\Xilinx\\Prj\\pro\\delivery_review_20261005', '<repo>'],
  ['d:/Xilinx/Prj/pro/Video_Processing', '<repo>'],
  ['D:/Software/Vivado/2025.2.1', '<tools>'],
  ['D:\\Software\\Vivado\\2025.2.1', '<tools>'],
  ['d:/Software/Vivado/2025.2.1', '<tools>'],
  ['D:/Xilinx/Resource', '<board-docs>'],
  ['D:\\Xilinx\\Resource', '<board-docs>'],
  ['D:/Xilinx/Vitis', '<tools>/Vitis'],
  ['D:\\Xilinx\\Vitis', '<tools>\\Vitis'],
  ['D:/Xilinx', '<Xilinx>'],
  ['D:\\Xilinx', '<Xilinx>'],
  ['d:/Xilinx', '<Xilinx>'],
  ['D:/Software', '<tools>'],
  ['D:\\Software', '<tools>'],
];

// 证据与留档层：不改正文，只数还剩多少条
const EVIDENCE = /^(build\/|board\/measured\/|board\/evidence|board\/compare\/|report\/log\/|data\/metrics\.csv)/;
// 用户原话签收：一个字都不动
const VERBATIM = /^board\/signoff\.md$/;

const listed = cp.execSync(
  'git -c core.quotepath=false ls-files vivado_system vitis src board build report sim skills data',
  {cwd: REPO, encoding:'utf8'}).split('\n').filter(Boolean);

let touched = 0, hits = 0, binSkip = 0, evSkip = 0, verbSkip = 0, evHits = 0;
const perKind = {};
for (const rel of listed) {
  const abs = path.join(REPO, rel);
  let buf; try { buf = fs.readFileSync(abs); } catch (e) { continue; }
  if (buf.includes(0)) {                        // 二进制：只数不改
    const t = buf.toString('latin1');
    const n = (t.match(/[A-Za-z]:[\/\\]/g) || []).length;
    if (/[A-Za-z]:[\/\\](Xilinx|Software)/i.test(t)) { binSkip++; hits += 0; }
    continue;
  }
  const txt = buf.toString('utf8');
  const before = (txt.match(/[A-Za-z]:[\/\\](Xilinx|Software)/gi) || []).length;
  if (!before) continue;
  if (VERBATIM.test(rel)) { verbSkip++; evHits += before; continue; }
  if (EVIDENCE.test(rel)) { evSkip++; evHits += before; continue; }
  let out = txt;
  for (const [a, b] of MAP) out = out.split(a).join(b);
  // `.xpr` 的工程头属性另写：仓库自己的约定是**仓库相对落点名**（`board/tcl/stage_board_projects.tcl`
  // 第 66-75 行就是这么把 board 那份改回 `board/zynq_video_sys.xpr` 的，同处还有一条判据
  // "还有几行带盘符就 REFUSE"）。占位符 `<repo>/…` 对这一处不合适，按约定补成相对名。
  if (rel.endsWith('.xpr')) out = out.replace(/(<Project [^>]*?)Path="[^"]*"/, `$1Path="${rel}"`);
  const after = (out.match(/[A-Za-z]:[\/\\](Xilinx|Software)/gi) || []).length;
  const absAny = out.split('\n').filter(l => /[A-Za-z]:[/\\]/.test(l)).length;
  touched++; hits += before - after;
  if (rel.endsWith('.xpr') && absAny > 0) console.log(`REFUSE ${rel} 归一化之后还有 ${absAny} 行带盘符（与 stage_board_projects.tcl 的判据同一条）`);
  perKind[(path.extname(rel) || '(无扩展名)').toLowerCase()] = (perKind[(path.extname(rel) || '(无扩展名)').toLowerCase()] || 0) + (before - after);
  if (APPLY && out !== txt) fs.writeFileSync(abs, out);
  if (after > 0) console.log('残留 ' + rel + ' 还剩 ' + after + ' 条（映射表没盖住的形状，列出来给人看）');
}
console.log(`${APPLY ? 'APPLY' : 'CHECK'} 改动文件=${touched} 替换条数=${hits} 跳过证据/留档=${evSkip} 份(${evHits} 条，不动正文) 跳过签收原话=${verbSkip} 份 跳过二进制=${binSkip} 份`);
console.log('按扩展名：' + Object.entries(perKind).sort((a,b)=>b[1]-a[1]).slice(0,10).map(([k,v])=>`${k}=${v}`).join(' '));
// 判据要能区分"已经干净"和"这一层根本没接上"：
//   touched=0 而证据层/二进制确实扫到了 ⇒ 本来就是 ALREADY-CLEAN（改完再跑一次应当是这样）；
//   touched=0 且一份都没扫到 ⇒ 射程或模式没接上，那是 NOT_MEASURED，不许念成绿。
if (!APPLY && touched === 0) {
  if (evSkip + binSkip + verbSkip > 0) console.log('RESULT=ALREADY-CLEAN（非证据层文本件里已无可改形状；跳过证据/留档 ' + evSkip + ' 份、二进制 ' + binSkip + ' 份、签收原话 ' + verbSkip + ' 份）');
  else { console.log('RESULT=NOT_MEASURED 一条都没扫到 ⇒ 射程或模式没接上'); process.exit(1); }
} else console.log(touched ? 'RESULT=OK' : 'RESULT=NO_MATCH');
