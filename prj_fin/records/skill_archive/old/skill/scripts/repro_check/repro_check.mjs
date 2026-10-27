#!/usr/bin/env node
/**
 * skill/scripts/repro_check/repro_check.mjs
 * 可复现性：规范化源码指纹 + 工具版本 + 报告头 ⇒ 同源/同版判定，并落一份可核对的证据文件
 *
 * 两种模式：
 *   capture  编译**之前**跑：node skill/scripts/repro_check/repro_check.mjs capture \
 *              --root src/rtl --out-dir skill/scripts/_out --stamp 2026-10-04T04:00:00+08:00
 *   verify   跑现成的报告与证据文件：node skill/scripts/repro_check/repro_check.mjs verify \
 *              --root src/rtl --evidence F --report build/timing_summary.rpt --declare report/BUILD.md
 *
 * 指纹绑内容不绑行尾：先去掉 CR、再去掉每行行尾空白，然后才取摘要（铁律 8）。
 * 证据文件与报告必须成对提交：只有一份时另一份不可信 ⇒ NOT_MEASURED（exit 2），绝不 PASS。
 * 退出码：0=PASS 1=FAIL 2=NOT_MEASURED 3=环境或前置不满足
 */
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';

const HELP = `用法:
  node repro_check.mjs capture --root DIR [...] --out-dir DIR [--stamp ISO] [--tool STR]
  node repro_check.mjs verify  --root DIR [...] --evidence FILE --report FILE
         [--declare FILE [--declare-key STR]] [--recorded FILE] [--manifest FILE]
         [--strict-set] [--out-dir DIR]
--root 只能指向工程源码目录（src/…、sim/…）；本脚本只读它们，绝不写。
产物只写到 --out-dir，且拒绝 src/ sim/ build/ 等工程目录。
退出码: 0=PASS 1=FAIL 2=NOT_MEASURED 3=前置不满足`;

const PROTECTED = ['src/', 'sim/', 'build/', 'board/', 'data/', 'report/', 'docs/'];
const FPVER = 'norm2';            // 本脚本的口径：去 CR + 去行尾空白
const FPVER_COMPAT = 'norm1';     // 仓库既有口径（build/rtl_fingerprint.sh）：只去 CR

const argv = process.argv.slice(2);
const mode = argv[0];
const opt = { root: [], declare: [] };
for (let i = 1; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--help' || a === '-h') { console.log(HELP); process.exit(0); }
  if (a === '--root' || a === '--declare') { opt[a.slice(2)].push(argv[++i]); continue; }
  if (a.startsWith('--')) { opt[a.slice(2)] = argv[++i]; continue; }
  out(`前置不满足 无法识别的参数 ${a} NOT_MEASURED`); out('前置不满足 判 0 项 FAIL'); process.exit(3);
}
function out(s) { console.log(s); }
function pre(msg) { out(`REPRO 前置不满足 ${msg} NOT_MEASURED`); out('REPRO 前置不满足 判 0 项 FAIL'); process.exit(3); }
function nm(msg) { out(`REPRO 读不到输入 ${msg} NOT_MEASURED`); out('REPRO 读不到输入 判 0 项 NOT_MEASURED'); process.exit(2); }
function guardOutDir(p) {
  const q = String(p).split(path.sep).join('/');
  if (PROTECTED.some(x => q === x.replace(/\/$/, '') || q.startsWith(x))) pre(`输出目录指向工程目录 ${q}`);
  return q;
}
if (!['capture', 'verify'].includes(mode)) pre(`模式只能是 capture/verify，给的是 ${mode || '空'}`);
if (!opt.root.length) pre('至少一个 --root');
for (const r of opt.root) if (!fs.existsSync(r)) nm(`--root ${r} 不存在`);
if (opt['out-dir']) guardOutDir(opt['out-dir']);

const results = [];
let nMade = 0, nFail = 0, nNm = 0, nPass = 0;
function say(name, made, detail, verdict) {
  nMade += made;
  if (verdict === 'FAIL') nFail++; else if (verdict === 'NOT_MEASURED') nNm++; else nPass++;
  results.push(`${name.padEnd(30)} 判 ${made} 项 ${detail} ${verdict}`);
}

const md5 = b => crypto.createHash('md5').update(b).digest('hex');
const stripCr = buf => Uint8Array.from(buf).filter(b => b !== 0x0d);
function perFile(buf, ver) {
  const lf = Buffer.from(stripCr(buf));
  if (ver === FPVER_COMPAT) return md5(lf);
  const s = lf.toString('binary').split('\n').map(l => l.replace(/[ \t]+$/, '')).join('\n');
  return md5(Buffer.from(s, 'binary'));
}
const byteSort = (a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0);   // 与 LC_ALL=C sort 同序
function listFiles(root, mode) {
  // mode='rootrel' 路径相对于 --root：同一份内容换到临时树里也算同一个合指纹（V2 用）
  // mode='cwdrel'  路径相对于当前目录：与仓库既有尺子 build/rtl_fingerprint.sh 的 `find src/rtl` 行形状同构（V6 用）
  const acc = [];
  const walk = d => {
    for (const e of fs.readdirSync(d, { withFileTypes: true }).sort(byteSort)) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p);
      else acc.push((mode === 'cwdrel' ? path.relative(process.cwd(), p) : path.relative(root, p)).split(path.sep).join('/'));
    }
  };
  if (fs.statSync(root).isFile()) return [mode === 'cwdrel' ? path.relative(process.cwd(), root).split(path.sep).join('/') : path.basename(root)];
  walk(root); return acc;
}
const INCLUDE = (opt.include || '\\.v$|\\.c$|\\.h$|\\.mjs$|\\.py$|\\.xdc$|\\.tcl$').split('|');
function scanRoot(root, ver, pathMode) {
  const files = listFiles(root, pathMode).filter(f => INCLUDE.some(re => new RegExp(re).test(f)));
  const base = pathMode === 'cwdrel' ? process.cwd() : root;
  const rows = files.map(f => `${perFile(fs.readFileSync(path.join(base, f)), ver)}  ${f}`);
  return { files, rows, agg: md5(Buffer.from(rows.join('\n') + '\n', 'binary')).slice(0, 12), count: files.length };
}

// 报告头（Vivado 的 | Key : Value 形状，实测 build/timing_summary.rpt:3-11）
function parseReportHead(file) {
  if (!fs.existsSync(file)) return null;
  const txt = fs.readFileSync(file, 'utf8');
  const g = k => { const m = txt.match(new RegExp(`^\\|\\s*${k}\\s*:\\s*(.*)$`, 'm')); return m ? m[1].trim() : null; };
  const tool = g('Tool Version');
  const date = g('Date');
  const vm = tool && tool.match(/v\.([0-9.]+)/);
  const bm = tool && tool.match(/Build\s+(\d+)/);
  return { tool, date, design: g('Design'), device: g('Device'), command: g('Command'),
           version: vm ? vm[1] : null, build: bm ? bm[1] : null, txt };
}
// 时刻一律换算成 epoch：带 Z 或 ±hh:mm 的 ISO 按标注的时区读；不带时区的按**本机本地时间**读。
// Vivado 报告头的 Date 是本地时间（实测 build/timing_summary.rpt:4 "Sun Oct  4 04:37:30 2026"），
// 若把它当 UTC 就会差掉一个时区（本机 +08:00 ⇒ 8 小时），先后关系会判反。
function toEpoch(s) {
  if (!s) return null;
  const str = String(s).trim();
  if (/(Z|[+-]\d{2}:?\d{2})$/i.test(str)) { const t = Date.parse(str); return Number.isNaN(t) ? null : t; }
  const m = str.match(/(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})/);
  if (!m) return null;
  return new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]).getTime();
}
function vivadoDate(s) {
  if (!s) return null;
  const m = String(s).match(/^(\w{3}) (\w{3})\s+(\d{1,2}) (\d{2}):(\d{2}):(\d{2}) (\d{4})/);
  if (!m) return null;
  const MON = { Jan: 0, Feb: 1, Mar: 2, Apr: 3, May: 4, Jun: 5, Jul: 6, Aug: 7, Sep: 8, Oct: 9, Nov: 10, Dec: 11 };
  if (MON[m[2]] === undefined) return null;
  return new Date(+m[7], MON[m[2]], +m[3], +m[4], +m[5], +m[6]).getTime();
}

const tree = scanRoot(opt.root[0], FPVER, 'rootrel');
const treeCompat = scanRoot(opt.root[0], FPVER_COMPAT, 'rootrel');
const treeRepoShape = scanRoot(opt.root[0], FPVER_COMPAT, 'cwdrel');  // 与 build/rtl_fingerprint.sh 的合指纹同形，供 V6 对账
const differ = tree.files.filter((f, i) => treeCompat.rows[i].slice(0, 32) !== tree.rows[i].slice(0, 32)).length;

if (mode === 'capture') {
  const odir = guardOutDir(opt['out-dir'] || pre('capture 需要 --out-dir'));
  const stamp = opt.stamp || new Date().toISOString();
  const tool = opt.tool || 'not-run (capture 只采源码指纹，不调工具)';
  const man = [
    `# repro_check 证据文件（编译前采集）`,
    `fpver=${FPVER}`,
    `captured_at=${stamp}`,
    `tool=${tool}`,
    `root=${opt.root.join(',')}`,
    `files=${tree.count}`,
    `aggregate=${tree.agg}`,
    `aggregate_${FPVER_COMPAT}=${treeCompat.agg}`,
    `aggregate_${FPVER_COMPAT}_findshape=${treeRepoShape.agg}`,
    `files_where_${FPVER_COMPAT}_ne_${FPVER}=${differ}`,
    `# 声明：本文件与报告必须成对提交；只有一份时另一份不可信。`,
    ...tree.rows,
  ].join('\n') + '\n';
  fs.mkdirSync(odir, { recursive: true });
  const manPath = path.join(odir, 'fingerprint_manifest.txt');
  fs.writeFileSync(manPath, man, 'utf8');
  const again = fs.readFileSync(manPath, 'utf8');
  say('CAP_written', 1, `${manPath} 行数=${man.split('\n').length} 回读一致=${again === man ? 'yes' : 'no'}`,
      again === man ? 'PASS' : 'FAIL');
  say('CAP_surface', 1, `root=${opt.root[0]} 文件=${tree.count} 聚合=${tree.agg}（${FPVER}） 与仓库尺子同形=${treeRepoShape.agg}（${FPVER_COMPAT}） 两种口径下不同的文件数=${differ}`,
      tree.count > 0 ? 'PASS' : 'NOT_MEASURED');
} else {
  const ev = opt.evidence, rep = opt.report;
  if (!ev) pre('verify 需要 --evidence');
  if (!rep) pre('verify 需要 --report');
  const evExists = fs.existsSync(ev), repExists = fs.existsSync(rep);

  // V4 成对提交：证据文件与报告缺一份 ⇒ NOT_MEASURED（缺输入 ≠ 通过）
  say('V4_pair_required', 1,
      `evidence=${evExists ? '在' : '缺'} report=${repExists ? '在' : '缺'}（声明：两者必须成对提交，只有一份时另一份不可信）`,
      evExists && repExists ? 'PASS' : 'NOT_MEASURED');
  if (!evExists) { say('V1_same_source', 0, `--evidence ${ev} 不存在（报告单独一份不可信）`, 'NOT_MEASURED'); }
  const head = parseReportHead(rep);
  if (!repExists) { say('V3_same_tool_version', 0, `--report ${rep} 不存在（证据文件单独一份不可信）`, 'NOT_MEASURED'); }

  const evTxt = evExists ? fs.readFileSync(ev, 'utf8') : '';
  const evGet = k => { const m = evTxt.match(new RegExp(`^${k}=(.*)$`, 'm')); return m ? m[1].trim() : null; };
  const evAgg = evGet('aggregate');
  const evFiles = Number(evGet('files') || '0');
  // V1 同源：证据里记的聚合指纹与文件数，必须和当场重算的两件都对上（两维同条）
  {
    if (evExists && !evAgg) {
      say('V1_same_source', 0, `证据文件 ${ev} 里没有 aggregate= 行`, 'NOT_MEASURED');
    } else {
      const made = 2;
      const same = evAgg === tree.agg;
      const cover = evFiles === tree.count;
      say('V1_same_source', made,
          `证据 aggregate=${evAgg || '空'} 现算=${tree.agg} 同=${same ? 'yes' : 'no'}；证据 files=${evFiles} 现扫=${tree.count} 同=${cover ? 'yes' : 'no'}`,
          (same && cover) ? 'PASS' : 'FAIL');
    }
  }
  // V2 行尾不敏感（成对：换行/尾随空白不许动指纹，改内容必须动）
  {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'repro_v2_'));
    try {
      const src = tree.files.slice();
      const mk = (dir, mode2) => {
        fs.mkdirSync(dir, { recursive: true });
        for (const f of src) {
          const buf = fs.readFileSync(path.join(opt.root[0], f));
          let s = Buffer.from(stripCr(buf)).toString('binary').split('\n');
          if (mode2 === 'crlf') s = s.map(l => l + '\r');
          if (mode2 === 'tailws') s = s.map(l => l + '   ');
          if (mode2 === 'content') s = s.map((l, i2) => (i2 === 0 ? l + ' //x' : l));
          const target = path.join(dir, f);
          fs.mkdirSync(path.dirname(target), { recursive: true });
          fs.writeFileSync(target, Buffer.from(s.join('\n'), 'binary'));
        }
        return scanRoot(dir, FPVER, 'rootrel').agg;
      };
      const base = mk(path.join(tmp, 'lf'), 'lf');
      const crlf = mk(path.join(tmp, 'crlf'), 'crlf');
      const tail = mk(path.join(tmp, 'tail'), 'tailws');
      const mut = mk(path.join(tmp, 'mut'), 'content');
      const made = 4;
      const bad = [];
      if (base !== crlf) bad.push('CRLF 翻了却指纹不同');
      if (base !== tail) bad.push('行尾空白加了却指纹不同');
      if (base === mut) bad.push('改了一个字符指纹仍然不动');
      if (base !== tree.agg) bad.push('临时树重算与主扫描不符');
      say('V2_fingerprint_binds_content', made,
          `LF=${base} CRLF=${crlf} 加尾随空白=${tail} 改内容=${mut} ${bad.length ? '破:' + bad.join(',') : '三项行尾/空白不变 + 改内容必须变'}`,
          bad.length ? 'FAIL' : 'PASS');
    } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
  }
  // V3 同版：报告头的版本号 vs 声明文件念的版本号，外加报告头必须有 Date（两维同条：版本 + 时间戳在场）
  {
    const decl = opt.declare[0];
    if (!head) {
      say('V3_same_tool_version', 0, `报告 ${rep} 读不到 | Tool Version : … 这种表头行`, 'NOT_MEASURED');
    } else {
      let made = 0, bad = 0, undec = 0; const det = [];
      if (!decl) { undec++; det.push('没给 --declare ⇒ 版本号没得对'); }
      else if (!fs.existsSync(decl)) { undec++; det.push(`--declare ${decl} 不存在`); }
      else {
        const key = opt['declare-key'] || 'Vivado';
        const dTxt = fs.readFileSync(decl, 'utf8');
        const line = dTxt.split(/\r?\n/).find(l => l.includes(key) && /\d{4}\.\d/.test(l)) || '';
        const dm = line.match(/(\d{4}\.\d+(?:\.\d+)?)/);
        made++;
        if (!head.version || !dm) { bad++; det.push(`报告版本=${head.version || '空'} 声明=${dm ? dm[1] : '读不到'}`); }
        else if (head.version !== dm[1]) { bad++; det.push(`报告版本=${head.version} 声明=${dm[1]} 不符`); }
        else det.push(`报告版本=${head.version} 声明=${dm[1]} 一致（取自 ${decl}）`);
      }
      made++;
      if (!head.date) { bad++; det.push('报告头没有 Date 行'); } else det.push(`报告头 Date=${head.date}`);
      say('V3_same_tool_version', made, det.join(' ') + (undec ? ` 未判=${undec}` : ''),
          (made === 0 || undec) ? 'NOT_MEASURED' : (bad ? 'FAIL' : 'PASS'));
    }
  }
  // V5 采集先后：证据时间必须不晚于报告时间（编译后采的指纹不能证明这份报告出自这棵树）
  {
    const evT = toEpoch(evGet('captured_at'));
    const rpT = head ? vivadoDate(head.date) : null;
    if (evT === null || rpT === null) say('V5_captured_before_build', 0,
        `证据 captured_at=${evGet('captured_at') || '空'} 报告 Date=${head && head.date ? head.date : '空'} ⇒ 先后关系判不了（历史报告只能靠编译前采集）`,
        'NOT_MEASURED');
    else {
      const ok = evT <= rpT;
      say('V5_captured_before_build', 1, `证据=${evGet('captured_at')} 报告=${head.date} 先后${ok ? '成立' : '不成立（编译后采集的指纹不能证明同源）'}`,
          ok ? 'PASS' : 'FAIL');
    }
  }
  // V6 与既有尺子对账：我的 norm1 重算必须等于真实记录里的 rtl= 值，同时念出两种口径的差异面
  {
    const rec = opt.recorded;
    if (!rec) say('V6_compat_with_repo_ruler', 0, '没给 --recorded ⇒ 不与仓库既有指纹对账', 'NOT_MEASURED');
    else if (!fs.existsSync(rec)) say('V6_compat_with_repo_ruler', 0, `--recorded ${rec} 不存在`, 'NOT_MEASURED');
    else {
      const txt = fs.readFileSync(rec, 'utf8');
      const m = txt.match(/rtl=([0-9a-f]{12})/);
      const made = 2;
      const vEq = !!m && m[1] === treeRepoShape.agg;
      const seen = tree.count > 0;
      let bad = 0;
      if (!m) { bad++; }
      else if (!vEq) bad++;
      if (!seen) bad++;
      say('V6_compat_with_repo_ruler', made,
          `记录文件 ${rec} 里 rtl=${m ? m[1] : '读不到'} 我用 ${FPVER_COMPAT} 口径(与 build/rtl_fingerprint.sh 同形)算=${treeRepoShape.agg} 同=${vEq ? 'yes' : 'no'}；${FPVER} 口径=${tree.agg}，两种口径下取值不同的文件=${differ}/${tree.count}`,
          bad ? (seen && m ? 'FAIL' : 'NOT_MEASURED') : 'PASS');
    }
  }
  // V7 产物清单：清单点名的必须存在且 md5 对得上（--strict-set 时反向的"盘上有而清单没有"也判）
  {
    const mf = opt.manifest;
    if (!mf) say('V7_manifest_parity', 0, '没给 --manifest ⇒ 不对账成套产物', 'NOT_MEASURED');
    else if (!fs.existsSync(mf)) say('V7_manifest_parity', 0, `--manifest ${mf} 不存在`, 'NOT_MEASURED');
    else {
      const rows = fs.readFileSync(mf, 'utf8').split(/\r?\n/).filter(l => /^[0-9a-f]{32}\s[* ]\S/.test(l));
      let made = 0, bad = 0, miss = 0; const det = [];
      const listed = [];
      for (const l of rows) {
        const mm = l.match(/^([0-9a-f]{32})\s[* ](.+)$/);
        if (!mm) continue;
        const name = mm[2].trim().replace(/^[*]/, '');
        const p = path.join(path.dirname(mf), name);
        listed.push(path.resolve(p).split(path.sep).join('/'));
        made++;
        if (!fs.existsSync(p)) { miss++; det.push(`${name}:文件不在`); continue; }
        const got = md5(fs.readFileSync(p));
        if (got !== mm[1]) { bad++; det.push(`${name}:md5 不符`); }
      }
      if (miss) { bad += 0; }
      let extra = 0;
      if (opt['strict-set'] !== undefined && fs.existsSync(mf)) {
        const dir = path.dirname(mf);
        const onDisk = fs.readdirSync(dir).filter(f => f !== path.basename(mf))
          .map(f => path.resolve(dir, f).split(path.sep).join('/'));
        extra = onDisk.filter(f => !listed.includes(f)).length;
        made += 1;
        if (extra) { bad++; det.push(`盘上有而清单没点名的=${extra}`); }
      }
      say('V7_manifest_parity', made,
          `清单=${rows.length} 核对=${made} md5 不符=${bad} 缺文件=${miss} 未登记的额外文件=${extra ? extra : (opt['strict-set'] !== undefined ? 0 : '未判')}${det.length ? ' 例:' + det.slice(0, 3).join(' ') : ''}`,
          made === 0 ? 'NOT_MEASURED' : (bad || miss ? 'FAIL' : (opt['strict-set'] === undefined ? 'PASS' : 'PASS')));
    }
  }
}

for (const l of results) console.log(l);
const verdict = nFail ? 'FAIL' : (nNm ? 'NOT_MEASURED' : (nMade === 0 ? 'NOT_MEASURED' : 'PASS'));
console.log(`REPRO ${mode} root=${opt.root[0]} 判 ${nMade} 项 未判 ${nNm} 项 红 ${nFail} 项 ${verdict}`);
process.exit(verdict === 'PASS' ? 0 : verdict === 'FAIL' ? 1 : 2);
