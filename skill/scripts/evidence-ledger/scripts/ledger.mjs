#!/usr/bin/env node
// 用途：证据台账：add 盖章 / check 逐条核对 / render 出 Markdown 表
// 输入：命令行参数
// 输出：stdout
// 退出码：0=跑完 1=FAIL 2=FAIL
// ledger.mjs —— 证据台账：add 盖章 / check 逐条核对 / render 出 Markdown 表
//
// 依赖：只有 Node 标准库（node:fs、node:path、node:os、node:crypto、node:child_process、node:url）。
// 无本机绝对路径常量，无工程/器件/板卡/工具名绑定：件路径一律相对 --root，摘要按**内容**哈希
// （行尾 CRLF/LF、BOM、编码不参与；二进制件自动退回按字节口径并在摘要前缀标出 mode）。
//
// 判定纪律（本包尺子的共同语言）：
//   每条判据一行，最后一个字段才是判定词 PASS / FAIL / NOT_MEASURED。
//   结论行 `判 N 项：… <token>`，N = 打印出的判定行数 = 做了多少次比较，不是通过多少。
//   件读不到、台账 0 行、解析失败 ⇒ NOT_MEASURED（绝不当通过，也不写"无异常"）。
//   有 FAIL ⇒ exit 1；只有未测 ⇒ exit 2；全绿 ⇒ exit 0。
//   一个根因只红一条：上游判红后，依赖它的下游项记 NOT_MEASURED 并写明"未做比较的原因"。
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SELF = fileURLToPath(import.meta.url);
const HERE = path.dirname(SELF);
const ENTRY = path.resolve(HERE, '..');
const FIXDIR = path.join(ENTRY, 'fixtures');

// 台账列（制表符分隔，第一行是表头；改列名等于改口径，必须同处改这份常量）
const COLS = ['ts', 'round', 'claim', 'cmd', 'artifact', 'bytes', 'cbytes', 'digest', 'tool', 'verdict', 'note'];
const NONBLANK = ['round', 'claim', 'cmd', 'artifact', 'bytes', 'cbytes', 'digest']; // 空了就没法核对
const SENT = 'NOT_MEASURED';          // 显式的"没读到"，不是编出来的值
const VERDICTS = new Set(['PASS', 'FAIL', 'NOT_MEASURED']);
const HEX = 16;                        // 摘要存前 16 个十六进制位（64 位）
const DEF_LEDGER = 'evidence/ledger.tsv';

const USAGE = [
  '用法:',
  '  node ledger.mjs add   --round <标识> --claim <一句话结论> --cmd <产生该结论的命令> --artifact <件路径>',
  '                        [--verdict PASS|FAIL|NOT_MEASURED] [--note <文本>] [--root <目录>] [--ledger <路径>] [--force]',
  '  node ledger.mjs check [--root <目录>] [--ledger <路径>] [--require-round <标识>]',
  '  node ledger.mjs render [--out ledger.md] [--root <目录>] [--ledger <路径>]',
  '  node ledger.mjs --self                    # 在临时目录跑夹具 + 变异对照',
  '',
  '件路径必须是相对 --root 的路径（台账要随包走，绝对路径换台机器就成死引用）。',
  '台账默认落在 <root>/evidence/ledger.tsv；--ledger 可把它放到被核对树之外。',
  '盖章字段：ts(UTC) / bytes(盘上字节) / cbytes(内容口径字节) / digest(mode:16hex) / tool(件里声明的版本，读不到写 NOT_MEASURED)。',
  '退出码：1=有 FAIL，2=只有未测，0=全绿。退出码不是判定，判定只在每行最后一个字段。',
].join('\n');

// ---------------------------------------------------------------- 基础件
function mkState() {
  const st = {
    lines: [], cmp: 0, red: 0, nm: 0,
    rows: 0, deadRef: 0, digestMismatch: 0, missingVerdict: 0, dupRounds: 0,
    token: SENT,
  };
  st.emit = (id, name, detail, verdict) => {
    if (!VERDICTS.has(verdict)) throw new Error(`非法判定词: ${verdict}`);
    st.lines.push(`${id} ${name} ${String(detail).replace(/[\t\r\n]+/g, ' ')} ${verdict}`);
    st.cmp += 1;
    if (verdict === 'FAIL') st.red += 1; else if (verdict === 'NOT_MEASURED') st.nm += 1;
  };
  return st;
}
const finish = (st) => { st.token = st.red ? 'FAIL' : (st.nm ? 'NOT_MEASURED' : 'PASS'); return st; };
function printState(st, keys) {
  finish(st);                                        // 判定词由比较结果现算，不留初值那种"没判却是绿"的口子
  for (const l of st.lines) console.log(l);
  console.log(`判 ${st.cmp} 项：${keys.join(' ')} ${st.token}`);
  return st.token === 'FAIL' ? 1 : (st.token === 'NOT_MEASURED' ? 2 : 0);
}

function normText(buf) {
  let t = buf.toString('utf8');
  if (t.charCodeAt(0) === 0xFEFF) t = t.slice(1);          // BOM 不参与摘要
  return t.replace(/\r\n?/g, '\n');                        // 行尾不参与摘要
}
function looksBinary(buf) {
  if (buf.includes(0)) return true;
  return buf.toString('utf8').includes('\uFFFD');          // 解不出 UTF-8 ⇒ 别按文本口径归一化
}
function digestOf(buf, mode) {
  if (mode === 'raw') {
    return { hex: crypto.createHash('sha256').update(buf).digest('hex'), cbytes: buf.length };
  }
  const n = Buffer.from(normText(buf), 'utf8');
  return { hex: crypto.createHash('sha256').update(n).digest('hex'), cbytes: n.length };
}
const TOOL_RE = /^\s*(?:tool_version|tool|工具版本)\s*[:=]\s*(.+?)\s*$/i;
function readTool(buf, mode) {
  if (mode === 'raw') return SENT;
  const line = normText(buf).split('\n').find((l) => TOOL_RE.test(l));
  if (!line) return SENT;
  const v = line.match(TOOL_RE)[1].trim();
  return v ? v.replace(/\s+/g, ' ').slice(0, 80) : SENT;
}
// 相对路径判定：台账要能被别人在另一台机器上复跑
function pathProblem(p) {
  if (p === null) return 'artifact 列不存在';
  const s = String(p).trim();
  if (s === '') return 'artifact 字段为空';
  const n = s.replace(/\\/g, '/');
  if (/^[A-Za-z]:\//.test(n)) return '带盘符的绝对路径';
  if (n.startsWith('/')) return '根绝对路径';
  if (n === '~' || n.startsWith('~/')) return '家目录写法';
  if (n.split('/').includes('..')) return '用 .. 越出 root';
  return null;
}
const asRel = (root, p) => String(p).replace(/\\/g, '/').split('/').filter((x) => x && x !== '.').join('/');
function resolveIn(root, p) {
  const n = String(p).replace(/\\/g, '/');
  if (/^[A-Za-z]:\//.test(n) || n.startsWith('/')) return path.normalize(n);
  return path.resolve(root, n);
}
function isIsoTs(v) {
  return typeof v === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/.test(v.trim()) && !Number.isNaN(Date.parse(v));
}
const isInt = (v) => /^\d+$/.test(String(v).trim());

function loadLedger(absLedger) {
  const r = { abs: absLedger, exists: false, bytes: 0, headerOk: false, header: null, rows: [], blank: 0, problem: null };
  if (!fs.existsSync(absLedger)) { r.problem = '文件不存在（还没立案？还是被剪枝剪掉了？）'; return r; }
  r.exists = true;
  let buf;
  try { buf = fs.readFileSync(absLedger); } catch (e) { r.problem = `读取失败 ${e.code || e.message}`; return r; }
  r.bytes = buf.length;
  const lines = normText(buf).split('\n');
  if (lines.length && lines[lines.length - 1] === '') lines.pop();
  if (lines.length === 0) { r.problem = buf.length === 0 ? '空文件（0 字节 0 行）' : '没有行'; return r; }
  r.header = lines[0].split('\t').map((c) => c.trim());
  r.headerOk = r.header.length === COLS.length && r.header.every((c, i) => c === COLS[i]);
  for (const l of lines.slice(1)) { if (l.trim() === '') { r.blank += 1; continue; } r.rows.push(l.split('\t')); }
  return r;
}

// ---------------------------------------------------------------- 逐行判定（check 的心脏）
// 每行 7 条比较：F 字段完整 / P 路径相对 / D 件在盘上 / N 件非空 / I 内容一致 / V 判定词 / T 盖章可读
function evalRow(st, root, vals, i) {
  const tag = `E${i + 1}`;
  const at = (c) => { const k = COLS.indexOf(c); return (k >= 0 && k < vals.length) ? vals[k] : null; };
  const missCols = vals.length < COLS.length ? COLS.slice(vals.length) : [];
  const extra = Math.max(0, vals.length - COLS.length);
  const blank = NONBLANK.filter((c) => { const v = at(c); return v !== null && v.trim() === ''; });
  const shapeBad = missCols.length > 0 || extra > 0;

  const fBad = shapeBad || blank.length > 0;
  st.emit(`${tag}-F`, `第 ${i + 1} 行 字段完整性`,
    `列数=${vals.length}/${COLS.length}`
    + (missCols.length ? ` 缺列=${missCols.join(',')}（按表头位置推断）` : '')
    + (extra ? ` 多列=${extra}` : '')
    + (blank.length ? ` 空字段=${blank.join(',')}` : '')
    + (fBad ? ' ⇒ 台账行形状与列常量不一致' : ''),
    fBad ? 'FAIL' : 'PASS');

  const use = (c) => { const v = at(c); return v !== null && v.trim() !== ''; };
  const skip = (c) => (missCols.includes(c) ? `artifact/相关列 ${c} 不存在，上游 F 已判缺列，本项未做比较` : `${c} 为空字段，上游 F 已判红，本项未做比较`);

  // P 路径相对
  const art = at('artifact');
  const pp = pathProblem(art);
  if (art === null || (art !== null && art.trim() === '')) {
    st.emit(`${tag}-P`, `第 ${i + 1} 行 件路径相对`, skip('artifact'), SENT);
  } else {
    st.emit(`${tag}-P`, `第 ${i + 1} 行 件路径相对`, pp ? `路径=${art} 问题=${pp} ⇒ 换台机器/换个目录深度就找不到` : `路径=${art} 相对且不含 .. 且非绝对`, pp ? 'FAIL' : 'PASS');
  }

  // D 件在盘上（点名的凭据不在交付里 ⇒ 死引用）
  let abs = null;
  if (pp) { st.emit(`${tag}-D`, `第 ${i + 1} 行 件在盘上`, `路径不可用（${pp}），不判在不在盘上，避免一个根因红两条`, SENT); }
  else {
    abs = resolveIn(root, art);
    let onDisk = false; let why = '';
    try { const s2 = fs.statSync(abs); onDisk = s2.isFile(); if (!onDisk) why = '是个目录不是件'; }
    catch (e) { why = e.code === 'ENOENT' ? '盘上没有' : `stat 失败 ${e.code || e.message}`; }
    if (onDisk) st.emit(`${tag}-D`, `第 ${i + 1} 行 件在盘上`, `路径=${art} 存在`, 'PASS');
    else { st.deadRef += 1; st.emit(`${tag}-D`, `第 ${i + 1} 行 件在盘上`, `路径=${art} ${why} ⇒ 死引用：结论点名的凭据不在交付里`, 'FAIL'); }
  }

  // N 件非空（0 字节通常是"没落盘/还在写"，不是"读数为零"）
  let buf = null;
  if (abs === null) st.emit(`${tag}-N`, `第 ${i + 1} 行 件非空`, '件不可用，未读内容', SENT);
  else {
    try { buf = fs.readFileSync(abs); } catch (e) { buf = null; st.emit(`${tag}-N`, `第 ${i + 1} 行 件非空`, `读取失败 ${e.code || e.message}`, SENT); }
    if (buf !== null) st.emit(`${tag}-N`, `第 ${i + 1} 行 件非空`, `盘上字节=${buf.length}`
      + (buf.length === 0 ? ' ⇒ 0 字节日志不等于读数为零，先确认写完了没有' : ''), buf.length === 0 ? SENT : 'PASS');
  }

  // I 内容一致：字节数（内容口径）+ 摘要，合为一项（同一根因只红一条）；盘上字节数只作存档
  if (buf === null || !use('cbytes') || !use('digest')) {
    st.emit(`${tag}-I`, `第 ${i + 1} 行 内容一致`, (buf === null ? '件读不到' : 'cbytes/digest 未盖章') + '，无法比较摘要', SENT);
  } else {
    const recDigest = String(at('digest')).trim();
    const recCbytes = String(at('cbytes')).trim();
    const recBytes = String(at('bytes')).trim();
    const m = recDigest.match(/^(txt|raw):([0-9a-f]{1,64})$/i);
    const mode = m ? m[1] : (looksBinary(buf) ? 'raw' : 'txt');
    const cur = digestOf(buf, mode);
    const curDigest = `${mode}:${cur.hex.slice(0, HEX)}`;
    if (!m || !isInt(recCbytes)) {
      st.emit(`${tag}-I`, `第 ${i + 1} 行 内容一致`, `摘要/字节数字段形状不认识 digest=${recDigest || '(空)'} cbytes=${recCbytes || '(空)'} ⇒ 解析失败，不判改写也不判一致`, SENT);
    } else {
      const cbOk = Number(recCbytes) === cur.cbytes;
      const dgOk = recDigest === curDigest;
      const rawNote = isInt(recBytes) && Number(recBytes) !== buf.length
        ? ` 盘上字节 bytes ${recBytes}->${buf.length}（行尾/编码差异，不参与改写判定）` : '';
      if (cbOk && dgOk) st.emit(`${tag}-I`, `第 ${i + 1} 行 内容一致`, `cbytes=${cur.cbytes} 摘要=${curDigest} 与盖章时相同${rawNote}`, 'PASS');
      else {
        st.digestMismatch += 1;
        st.emit(`${tag}-I`, `第 ${i + 1} 行 内容一致`,
          `cbytes ${recCbytes}->${cur.cbytes} 摘要 ${recDigest}->${curDigest}${rawNote} ⇒ 件被改写过（或盖章时读的是另一份）`, 'FAIL');
      }
    }
  }

  // V 判定词：三态之外一律算缺判定
  const vcol = at('verdict');
  if (vcol === null) st.emit(`${tag}-V`, `第 ${i + 1} 行 判定词合法`, 'verdict 列不存在（上游 F 已判缺列），本项未做比较', SENT);
  else if (VERDICTS.has(vcol.trim())) st.emit(`${tag}-V`, `第 ${i + 1} 行 判定词合法`, `verdict=${vcol.trim()}`, 'PASS');
  else { st.missingVerdict += 1; st.emit(`${tag}-V`, `第 ${i + 1} 行 判定词合法`, `verdict 字段=[${vcol.trim() || '(空)'}] 不在三态集合内 ⇒ 这一行的结论没有判定`, 'FAIL'); }

  // T 盖章可读：时间戳可解析、tool 非空（tool 允许写 NOT_MEASURED 哨兵，但不许留空、不许编）
  const ts = at('ts'); const tool = at('tool');
  if (missCols.includes('ts') || missCols.includes('tool')) st.emit(`${tag}-T`, `第 ${i + 1} 行 盖章可读`, 'ts/tool 列不存在，本项未做比较', SENT);
  else {
    const bad = [];
    if (!isIsoTs(ts)) bad.push(`ts=[${(ts || '(空)').trim()}] 不是 UTC ISO`);
    if (!tool || tool.trim() === '') bad.push('tool 字段为空');
    st.emit(`${tag}-T`, `第 ${i + 1} 行 盖章可读`,
      bad.length ? bad.join('；') : `ts=${String(ts).trim()} tool=${String(tool).trim()}${String(tool).trim() === SENT ? '（件里没声明版本，按哨兵记录而不是编一个）' : ''}`,
      bad.length ? 'FAIL' : 'PASS');
  }
  return {
    round: use('round') ? String(at('round')).trim() : null,
    ts: use('ts') ? String(at('ts')).trim() : '',
    verdict: VERDICTS.has(String(vcol || '').trim()) ? String(vcol).trim() : null,
  };
}

// ---------------------------------------------------------------- check
function cmdCheck(o) {
  const st = mkState();
  const root = o.flags.root || '.';
  const ledger = o.flags.ledger || DEF_LEDGER;
  const req = o.flags['require-round'];
  const absLedger = resolveIn(root, ledger);
  const L = loadLedger(absLedger);
  const where = `台账=${ledger} root=${root}`;

  if (!L.headerOk) {
    const brokenHeader = L.exists && L.bytes > 0 && Array.isArray(L.header);
    st.emit('L', '台账可读', `${where} ${L.problem ? `问题=${L.problem}` : `字节=${L.bytes} 表头列=${L.header ? L.header.length : 0} 缺列=${L.header ? COLS.slice(L.header.length).join(',') : '?'} 多列=${L.header ? L.header.slice(COLS.length).join(',') : '?'}`} ⇒ ${brokenHeader ? '表头与列常量不符' : '台账无从解析'}，逐行判定没做（不能做，不是没问题）`,
      brokenHeader ? 'FAIL' : SENT);
    st.emit('U', '同轮单行', '无行可判', SENT);
    st.emit('A', '行内判定分布', '无行可判，不作"无异常"结论', SENT);
    return printState(st, summaryKeys(st, req));
  }
  st.rows = L.rows.length;
  st.emit('L', '台账可读', `${where} 字节=${L.bytes} 表头列=${L.header.length} 数据行=${L.rows.length} 空行=${L.blank}`, 'PASS');

  const seen = new Map();
  for (let i = 0; i < L.rows.length; i += 1) {
    const r = evalRow(st, root, L.rows[i], i);
    if (r.round) seen.set(r.round, [...(seen.get(r.round) || []), { i, round: r.round, ts: isIsoTs(r.ts) ? r.ts : '' }]);
  }

  const dups = [...seen.entries()].filter(([, a]) => a.length > 1);
  st.dupRounds = dups.length;
  const dupDesc = ([r, a]) => {
    const latest = a.reduce((m, x) => ((x.ts || '') > (m.ts || '') ? x : m), a[0]);
    return `${r} 共 ${a.length} 行，取最新=第 ${latest.i + 1} 行（ts=${latest.ts || '不可解析'}），其余 ${a.length - 1} 行按旧行核对`;
  };
  st.emit('U', '同轮单行',
    dups.length
      ? `重复轮: ${dups.map(dupDesc).join('；')} ⇒ 该轮当前判定按 ts 最新的一行取；谁算数得有人确认，所以这一项判未测而不是绿`
      : `轮数=${seen.size} 每轮各 1 行`,
    dups.length ? SENT : 'PASS');

  const legal = L.rows.map((v) => { const k = COLS.indexOf('verdict'); return (k < v.length ? String(v[k]).trim() : ''); }).filter((x) => VERDICTS.has(x));
  const cnt = { PASS: 0, FAIL: 0, NOT_MEASURED: 0 };
  for (const x of legal) cnt[x] += 1;
  const allNm = legal.length > 0 && cnt.PASS === 0 && cnt.FAIL === 0;
  st.emit('A', '行内判定分布',
    legal.length === 0 ? `可数的判定=0/${L.rows.length} 行（都在 V 项红了），这一项不替你裁决`
      : `PASS=${cnt.PASS} FAIL=${cnt.FAIL} NOT_MEASURED=${cnt.NOT_MEASURED}` + (allNm ? ' ⇒ 台账记了行但一条实测结论都没有' : '（台账自洽度量的分布，设计结论请读判定列）'),
    legal.length === 0 ? SENT : (allNm ? SENT : 'PASS'));

  if (req !== undefined) {
    const arr = seen.get(String(req).trim());
    const n = arr ? arr.length : 0;
    st.emit('R', '轮次覆盖', `require_round=${String(req).trim()} 命中行数=${n}` + (n === 0 ? ' ⇒ 这一轮在台账里根本没有行：没立案还是漏写？不许当通过' : ''), n === 0 ? SENT : 'PASS');
  }
  return finishAndCheck(st, req);
}
function summaryKeys(st, req) {
  return [`扫描行数 rows=${st.rows}`, `比较次数 cmp=${st.cmp}`, `死引用 dead_ref=${st.deadRef}`,
    `摘要不符 digest_mismatch=${st.digestMismatch}`, `缺判定 missing_verdict=${st.missingVerdict}`,
    `同轮多行 dup_rounds=${st.dupRounds}`, `require_round=${req === undefined ? 'none' : String(req).trim()}`];
}
function finishAndCheck(st, req) { return printState(st, summaryKeys(st, req)); }

// ---------------------------------------------------------------- add
function cmdAdd(o) {
  const st = mkState();
  const root = o.flags.root || '.';
  const ledger = o.flags.ledger || DEF_LEDGER;
  const absLedger = resolveIn(root, ledger);
  const where = `台账=${ledger} root=${root}`;
  const need = ['round', 'claim', 'cmd', 'artifact'];
  const absent = need.filter((k) => !o.flags[k]);
  st.emit('S0', '必填参数', absent.length ? `缺少 --${absent.join(' --')}（round/claim/cmd/artifact 四项是台账的骨架）` : `round=${o.flags.round} artifact=${o.flags.artifact}`, absent.length ? 'FAIL' : 'PASS');

  const dirty = ['round', 'claim', 'cmd', 'artifact', 'verdict', 'note']
    .filter((k) => typeof o.flags[k] === 'string' && /[\t\r\n]/.test(o.flags[k]));
  const roundShape = o.flags.round && !/^[A-Za-z0-9][A-Za-z0-9._:-]*$/.test(String(o.flags.round).trim()) ? ['round'] : [];
  const fBad = dirty.length + roundShape.length > 0;
  st.emit('S1', '字段干净', (dirty.length ? `含制表符/换行的字段=${dirty.join(',')} ⇒ 制表符会撕成两列、换行会撕成两行，拒收` : '')
    + (roundShape.length ? ` round 形状不认识(${o.flags.round})：用 ASCII 短标识，别带空格` : '')
    || '四个必填 + verdict/note 都不含制表符与换行', fBad ? 'FAIL' : 'PASS');

  const verdict = o.flags.verdict === undefined ? SENT : String(o.flags.verdict).trim();
  const vBad = !VERDICTS.has(verdict);
  st.emit('S2', '判定词', vBad ? `--verdict=[${verdict}] 不在三态之内，拒收（也不许缺省成 PASS：缺省记 ${SENT}）`
    : `verdict=${verdict}${o.flags.verdict === undefined ? '（未给 --verdict ⇒ 记 ' + SENT + '，不默认通过）' : ''}`, vBad ? 'FAIL' : 'PASS');

  const pp = o.flags.artifact ? pathProblem(o.flags.artifact) : 'artifact 缺失';
  st.emit('S3', '件路径相对', pp ? `路径=${o.flags.artifact || '(缺)'} 问题=${pp} ⇒ 台账里的件路径必须相对 --root` : `路径=${o.flags.artifact} 相对`, pp ? 'FAIL' : 'PASS');

  const rel = asRel(root, o.flags.artifact || '');
  const abs = resolveIn(root, o.flags.artifact || '');
  let buf = null; let readWhy = '';
  if (pp) { st.emit('S4', '件在盘上', '路径不合法，未去读盘', SENT); }
  else {
    try { const s = fs.statSync(abs); if (s.isFile()) buf = fs.readFileSync(abs); else readWhy = '是个目录不是件'; }
    catch (e) { readWhy = e.code === 'ENOENT' ? '盘上没有' : `读取失败 ${e.code || e.message}`; }
    if (buf !== null) st.emit('S4', '件在盘上', `相对=${rel} 字节=${buf.length}`, 'PASS');
    else if (o.flags.force) st.emit('S4', '件在盘上', `相对=${rel} ${readWhy} ⇒ 按 --force 落一行"未盖章"的行（摘要不许编）`, SENT);
    else st.emit('S4', '件在盘上', `相对=${rel} ${readWhy} ⇒ 你点名的凭据不在盘上：这条结论现在没有件，拒写（要么先把件落盘，要么 --force 记成未盖章）`, 'FAIL');
  }

  if (buf === null) st.emit('S5', '件非空', '件不可用，未判空', SENT);
  else st.emit('S5', '件非空', `盘上字节=${buf.length}` + (buf.length === 0 ? ' ⇒ 0 字节的读数件通常是没落盘/还在写；行照写，但别把它当证据' : ''), buf.length === 0 ? SENT : 'PASS');

  let stamp = null;
  if (buf === null) {
    stamp = { bytes: SENT, cbytes: SENT, digest: SENT, tool: SENT };
    st.emit('S6', '盖章', `bytes/cbytes/digest/tool 全部记 ${SENT}（不许凭记忆填一个数）`, SENT);
  } else {
    const mode = looksBinary(buf) ? 'raw' : 'txt';
    const d = digestOf(buf, mode);
    stamp = { bytes: buf.length, cbytes: d.cbytes, digest: `${mode}:${d.hex.slice(0, HEX)}`, tool: readTool(buf, mode) };
    st.emit('S6', '盖章', `mode=${mode} bytes=${stamp.bytes} cbytes=${stamp.cbytes} digest=${stamp.digest} tool=${stamp.tool}`
      + (mode === 'raw' ? '（二进制件：按字节口径哈希，行尾归一化对它不适用）' : '（文本件：行尾/BOM/编码不参与摘要）')
      + (stamp.tool === SENT ? ' 件里没有版本声明字段，记哨兵而不是编一个' : ''), 'PASS');
  }

  const blocked = st.red > 0;
  if (blocked) {
    st.emit('S7', '追加并回读', '上游已判红，台账没被写脏（本项未做）', SENT);
    return printState(st, [`比较次数 cmp=${st.cmp}`, `写入行数 added=0`, `台账=${ledger}`, `root=${root}`]);
  }
  const row = [new Date().toISOString(), String(o.flags.round).trim(), String(o.flags.claim).trim(), String(o.flags.cmd).trim(),
    rel, String(stamp.bytes), String(stamp.cbytes), stamp.digest, stamp.tool, verdict, o.flags.note ? String(o.flags.note).trim() : ''];
  const before = loadLedger(absLedger);
  if (before.exists && before.bytes > 0 && !before.headerOk) {
    st.emit('S7', '追加并回读', `${where} 已有台账的表头与列常量不符 ⇒ 拒绝往形状不认的台账里追加`, 'FAIL');
    return printState(st, [`比较次数 cmp=${st.cmp}`, '写入行数 added=0', `台账=${ledger}`, `root=${root}`]);
  }
  try {
    fs.mkdirSync(path.dirname(absLedger), { recursive: true });
    if (!before.exists || before.bytes === 0) fs.writeFileSync(absLedger, `${COLS.join('\t')}\n`, { encoding: 'utf8' });
    fs.appendFileSync(absLedger, `${row.join('\t')}\n`, { encoding: 'utf8' });
  } catch (e) { st.emit('S7', '追加并回读', `写入失败 ${e.code || e.message}`, 'FAIL'); return printState(st, [`比较次数 cmp=${st.cmp}`, '写入行数 added=0', `台账=${ledger}`, `root=${root}`]); }
  const after = loadLedger(absLedger);
  const expect = (before.rows.length + 1);
  const ok = after.headerOk && after.rows.length === expect;
  st.rows = after.rows.length;
  st.emit('S7', '追加并回读', `${where} 写前数据行=${before.rows.length} 写后=${after.rows.length} 期望=${expect} 本轮 round=${row[1]}（同轮重跑会留多行，check 按 ts 取最新）`, ok ? 'PASS' : 'FAIL');
  return printState(st, [`扫描行数 rows=${after.rows.length}`, `比较次数 cmp=${st.cmp}`, `写入行数 added=${ok ? 1 : 0}`, `件=${rel}`, `判定=${verdict}`, `台账=${ledger}`, `root=${root}`]);
}

// ---------------------------------------------------------------- render
const cell = (s) => {
  const v = String(s === null || s === undefined ? '' : s).replace(/[\t\r\n]+/g, ' ').replace(/\|/g, '\\|').trim();
  return v === '' ? '(空)' : (v.length > 120 ? `${v.slice(0, 117)}...` : v);
};
function cmdRender(o) {
  const st = mkState();
  const root = o.flags.root || '.';
  const ledger = o.flags.ledger || DEF_LEDGER;
  const out = o.flags.out || 'ledger.md';
  const L = loadLedger(resolveIn(root, ledger));
  const where = `台账=${ledger} root=${root}`;

  if (!L.headerOk) {
    st.emit('L', '台账可读', `${where} ${L.problem ? `问题=${L.problem}` : '表头列与列常量不符'} ⇒ 无表可渲染`,
      (L.exists && L.bytes > 0 && Array.isArray(L.header)) ? 'FAIL' : SENT);
  } else {
    st.rows = L.rows.length;
    st.emit('L', '台账可读', `${where} 字节=${L.bytes} 数据行=${L.rows.length}`, 'PASS');
  }

  const tbl = [];
  for (const v of (L.headerOk ? L.rows : [])) {
    const at = (c) => { const k = COLS.indexOf(c); return k < v.length ? v[k] : ''; };
    tbl.push(`| ${cell(at('round'))} | ${cell(at('claim'))} | ${cell(at('cmd'))} | ${cell(at('artifact'))} | ${cell(at('verdict'))} | ${cell(at('digest'))} |`);
  }
  const lines = [];
  lines.push('# 证据台账（由 ledger.mjs render 生成）', '');
  lines.push(`- 台账件：\`${cell(ledger)}\`（root=\`${cell(root)}\`）`);
  lines.push(`- 渲染时间：${new Date().toISOString()}`);
  if (tbl.length > 0) {
    lines.push('', '| 轮次 | 结论 | 命令 | 件 | 判定 | 摘要 |', '| --- | --- | --- | --- | --- | --- |', ...tbl, '');
    lines.push('> 本表是台账的**渲染**，不是放行判定：判定列写的是当轮结论（含 FAIL/未测），逐行可核对性请用 `check`。');
    lines.push('> 件路径都是相对 root 的；摘要是内容口径（行尾/编码不参与）。');
  } else {
    lines.push('', L.headerOk
      ? '**台账 0 行 ⇒ NOT_MEASURED。**这不是"无异常"，也不是"没发现问题"：没有任何一行被登记，就没有任何一条结论可核对。'
      : `**台账无从解析（问题=${L.problem || '表头列与列常量不符'}）⇒ NOT_MEASURED。**没有一行被渲染；这张空表不代表"没有异常"，只代表台账本身要先修。`);
  }
  const rendered = tbl.filter((l) => l.startsWith('| ')).length;
  const eq = rendered === L.rows.length;
  const why = eq ? '' : (L.problem ? `（台账无从解析：问题=${L.problem}）`
    : (!L.headerOk ? '（表头与列常量不符，没有一行被渲染）' : '（渲染器漏行——渲染件会骗人）'));
  st.emit('D', '行数等式', `渲染行数=${rendered} 台账行数=${L.rows.length} 等式=${eq ? '成立' : '不成立'}${why} 输出=${out}`
    + (eq && rendered > 0 ? '（等式不成立的分支只有台账解析坏或渲染器自己漏行才走到）' : ''),
    (!L.headerOk || rendered === 0) ? SENT : (eq ? 'PASS' : 'FAIL'));

  const vals = L.headerOk ? L.rows.map((v) => { const k = COLS.indexOf('verdict'); return (k < v.length ? String(v[k]).trim() : ''); }) : [];
  const legal = vals.filter((x) => VERDICTS.has(x));
  const bad = vals.length - legal.length;
  const cnt = { PASS: 0, FAIL: 0, NOT_MEASURED: 0 };
  for (const x of legal) cnt[x] += 1;
  st.emit('V', '判定列合法', vals.length === 0 ? `可数的行=0，分布无从谈起（不许写成"无异常"）`
    : `行=${vals.length} 非法=${bad} 分布 PASS=${cnt.PASS} FAIL=${cnt.FAIL} NOT_MEASURED=${cnt.NOT_MEASURED}`,
    vals.length === 0 ? SENT : (bad > 0 ? 'FAIL' : 'PASS'));

  let absOut = resolveIn('.', out);
  try {
    fs.mkdirSync(path.dirname(absOut), { recursive: true });
    fs.writeFileSync(absOut, `${lines.join('\n')}\n`, { encoding: 'utf8' });
  } catch (e) { st.emit('W', '渲染件落盘', `写入失败 ${e.code || e.message}`, 'FAIL'); return printState(st, [`比较次数 cmp=${st.cmp}`, `渲染行数 rendered=${rendered}`, `台账行数 ledger_rows=${L.rows.length}`, `输出=${out}`]); }
  const selfRef = insideRoot(root, absOut);
  st.emit('W', '渲染件落盘', `已写 ${out} 行数=${lines.length}` + (selfRef ? ' 提示：渲染件落在 root 之内，别在下一轮把它当证据件引用（自指）' : ''), 'PASS');
  return printState(st, [`比较次数 cmp=${st.cmp}`, `渲染行数 rendered=${rendered}`, `台账行数 ledger_rows=${L.rows.length}`, `等式 equality=${eq ? 'ok' : 'broken'}`, `输出 out=${out}`]);
}
function insideRoot(root, abs) {
  const rel = path.relative(path.resolve(root), abs);
  return rel !== '' && !rel.startsWith('..') && !path.isAbsolute(rel);
}

// ---------------------------------------------------------------- 参数
const ALLOWED = {
  add: ['round', 'claim', 'cmd', 'artifact', 'verdict', 'note', 'root', 'ledger', 'force'],
  check: ['root', 'ledger', 'require-round'],
  render: ['out', 'root', 'ledger'],
};
function parseArgs(argv) {
  const flags = {}; const pos = [];
  const BOOL = new Set(['force', 'self', 'help']);
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--help' || a === '-h') { flags.help = true; continue; }
    if (a === '--self') { flags.self = true; continue; }
    if (a.startsWith('--')) {
      const k = a.slice(2);
      if (BOOL.has(k) && (argv[i + 1] === undefined || String(argv[i + 1]).startsWith('--'))) { flags[k] = true; continue; }
      flags[k] = argv[i + 1]; i += 1; continue;
    }
    pos.push(a);
  }
  return { flags, pos };
}

// ---------------------------------------------------------------- --self
function copyTree(src, dst) {
  fs.mkdirSync(dst, { recursive: true });
  for (const e of fs.readdirSync(src, { withFileTypes: true })) {
    const s = path.join(src, e.name); const d = path.join(dst, e.name);
    if (e.isDirectory()) copyTree(s, d); else fs.copyFileSync(s, d);
  }
}
function runCli(args) {
  let out = ''; let code = 0;
  try { out = execFileSync(process.execPath, [SELF, ...args], { encoding: 'utf8' }); }
  catch (e) { out = `${(e.stdout || '')}${(e.stderr || '')}`; code = typeof e.status === 'number' ? e.status : 1; }
  if (!out) code = code || 1;
  return { out: out.replace(/\r\n/g, '\n'), code };
}
const concl = (out) => (out.split('\n').find((l) => l.startsWith('判 ')) || '').trim();
const token = (line) => (line ? line.split(/\s+/).pop() : 'MISSING');
function num(line, key) { const m = line.match(new RegExp(`${key}=(\\d+)`)); return m ? Number(m[1]) : null; }
// 只数"判据行的红"，结论行本身不参与（结论行末字段也写着 FAIL，数进去就成 2 条了）
const bodyLines = (out) => out.split('\n').filter((l) => l.trim() !== '' && !l.startsWith('判 '));
const reds = (out) => bodyLines(out).filter((l) => l.endsWith(' FAIL')).length;
const greens = (out) => bodyLines(out).filter((l) => l.endsWith(' PASS')).length;
const onlyRedId = (out) => (reds(out) === 1 ? (bodyLines(out).find((l) => l.endsWith(' FAIL')) || '').split(/\s+/)[0] : `红条数=${reds(out)}`);
function readRows(abs) {
  if (!fs.existsSync(abs)) return [];
  const lines = normText(fs.readFileSync(abs)).split('\n');
  if (lines.length && lines[lines.length - 1] === '') lines.pop();
  return lines.slice(1).filter((l) => l.trim() !== '').map((l) => l.split('\t'));
}
function colOf(rows, i, c) { const k = COLS.indexOf(c); return (rows[i] && k < rows[i].length) ? rows[i][k] : null; }
function writeRows(abs, header, rows) { fs.writeFileSync(abs, [header.join('\t'), ...rows.map((r) => r.join('\t'))].join('\n') + '\n', { encoding: 'utf8' }); }

function selfTest() {
  const out = [];
  let red = 0;
  const ck = (name, want, got) => {
    const ok = JSON.stringify(want) === JSON.stringify(got);
    out.push(`S ${name} 期望=${JSON.stringify(want)} 实得=${JSON.stringify(got)} ${ok ? 'PASS' : 'FAIL'}`);
    if (!ok) red += 1;
  };
  if (!fs.existsSync(FIXDIR)) {
    console.log(`S 夹具目录 期望=存在 实得=缺失(${FIXDIR}) FAIL`);
    console.log(`判 1 项：红=1 未测=0 夹具=缺失 FAIL`);
    return 1;
  }
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'evidence-ledger-self-'));
  const PKG = path.join(tmp, 'pkg');
  const EMPTY = path.join(tmp, 'empty');
  copyTree(path.join(FIXDIR, 'pkg'), PKG);
  copyTree(path.join(FIXDIR, 'empty'), EMPTY);
  const LEDGER = path.join(PKG, 'evidence', 'ledger.tsv');
  const FULL = path.join(PKG, 'evidence', 'read-full.txt');

  // 每个变异都在独立沙箱里跑：一个根因只该红一条
  const sandbox = (name) => { const d = path.join(tmp, `mut-${name}`); copyTree(path.join(FIXDIR, 'pkg'), d); return d; };
  const runCheck = (root, extra) => {
    const r = runCli(['check', '--root', root, ...(extra || [])]);
    const line = concl(r.out);
    return { code: r.code, token: token(line), rows: num(line, 'rows'), cmp: num(line, 'cmp'), dead: num(line, 'dead_ref'), dig: num(line, 'digest_mismatch'), miss: num(line, 'missing_verdict'), dup: num(line, 'dup_rounds'), out: r.out, line };
  };

  // ① 完整夹具：应当全绿
  const c1 = runCheck(PKG);
  ck('夹具 完整读数 check', { token: 'PASS', rows: 2, cmp: 17, dead: 0, dig: 0, miss: 0, dup: 0, code: 0 },
    { token: c1.token, rows: c1.rows, cmp: c1.cmp, dead: c1.dead, dig: c1.dig, miss: c1.miss, dup: c1.dup, code: c1.code });

  // ② 缺字段夹具：红，并且点名是哪个字段
  const fx2 = path.join(tmp, 'fx-missing-verdict.tsv');
  fs.copyFileSync(path.join(FIXDIR, 'pkg', 'evidence', 'ledger-missing-verdict.tsv'), fx2);
  const r2 = runCli(['check', '--root', PKG, '--ledger', fx2]);
  const l2 = concl(r2.out);
  ck('夹具 缺 verdict 字段 ⇒ 一条红', { token: 'FAIL', rows: 2, cmp: 17, miss: 1, code: 1, redAt: 'E2-V' },
    { token: token(l2), rows: num(l2, 'rows'), cmp: num(l2, 'cmp'), miss: num(l2, 'missing_verdict'), code: r2.code, redAt: onlyRedId(r2.out) });
  const vline2 = r2.out.split('\n').find((l) => l.includes('-V') && l.includes('第 2 行')) || '';
  ck('缺字段项点名了字段名 verdict', { names: true, onlyOneRed: true },
    { names: /verdict/.test(vline2), onlyOneRed: reds(r2.out) === 1 });

  const fx3 = path.join(tmp, 'fx-missing-column.tsv');
  fs.copyFileSync(path.join(FIXDIR, 'pkg', 'evidence', 'ledger-missing-column.tsv'), fx3);
  const r3 = runCli(['check', '--root', PKG, '--ledger', fx3]);
  const l3 = concl(r3.out);
  const fline3 = r3.out.split('\n').find((l) => l.includes('-F') && l.includes('第 2 行')) || '';
  ck('夹具 截断行 ⇒ 一条红并点名缺的列', { token: 'FAIL', cmp: 17, redLines: 1, redAt: 'E2-F' },
    { token: token(l3), cmp: num(l3, 'cmp'), redLines: reds(r3.out), redAt: onlyRedId(r3.out) });
  ck('截断行的红点是列名而不是"未知"', { has: true }, { has: /缺列=[^\s]/.test(fline3) });

  // ③ 空文件夹具：NOT_MEASURED，且不许写成"无异常"
  const c4 = runCheck(EMPTY);
  ck('夹具 空台账 ⇒ 未测而不是绿', { token: 'NOT_MEASURED', rows: 0, cmp: 3, code: 2 },
    { token: c4.token, rows: c4.rows, cmp: c4.cmp, code: c4.code });
  ck('空台账不判通过（一行都没有＝没比较过）', { token: 'NOT_MEASURED', greenLines: 0 }, { token: c4.token, greenLines: greens(c4.out) });

  // ④ 死引用：件路径改成不存在的 ⇒ 只红 D 一条
  const d1 = sandbox('deadref');
  const rows1 = readRows(path.join(d1, 'evidence', 'ledger.tsv'));
  rows1[0][COLS.indexOf('artifact')] = 'evidence/no-such-file.txt';
  writeRows(path.join(d1, 'evidence', 'ledger.tsv'), COLS.slice(), rows1);
  const c5 = runCheck(d1);
  const dline = c5.out.split('\n').find((l) => l.includes('E1-D')) || '';
  ck('变异 死引用 ⇒ 红=1 且红在 D', { token: 'FAIL', dead: 1, cmp: 17, redLines: 1, redAt: 'E1-D' },
    { token: c5.token, dead: c5.dead, cmp: c5.cmp, redLines: reds(c5.out), redAt: onlyRedId(c5.out) });
  ck('死引用那条说明了原因', { has: true }, { has: /死引用/.test(dline) });

  // ⑤ 内容被改写：追加一个字节 ⇒ 只红 I 一条，摘要不符=1
  const d2 = sandbox('rewrite');
  fs.appendFileSync(path.join(d2, 'evidence', 'read-full.txt'), 'x');
  const c6 = runCheck(d2);
  const iline = c6.out.split('\n').find((l) => l.includes('E1-I')) || '';
  ck('变异 追加一个字节 ⇒ 红=1 且红在 I', { token: 'FAIL', dig: 1, cmp: 17, redLines: 1, redAt: 'E1-I' },
    { token: c6.token, dig: c6.dig, cmp: c6.cmp, redLines: reds(c6.out), redAt: onlyRedId(c6.out) });
  ck('改写那条说了"件被改写过"', { has: true }, { has: /件被改写过/.test(iline) });

  // ⑥ 行尾/编码不参与：整件换成 CRLF ⇒ 一条都不该红（哈希口径的证据）
  const d3 = sandbox('crlf');
  const fbuf = fs.readFileSync(path.join(d3, 'evidence', 'read-full.txt'));
  fs.writeFileSync(path.join(d3, 'evidence', 'read-full.txt'), Buffer.from(normText(fbuf).replace(/\n/g, '\r\n'), 'utf8'));
  const c7 = runCheck(d3);
  ck('变异 只改行尾 ⇒ 全绿（内容口径）', { token: 'PASS', cmp: 17, code: 0 }, { token: c7.token, cmp: c7.cmp, code: c7.code });

  // ⑦ 绝对路径 / 越界路径 ⇒ 只红 P 一条
  const d4 = sandbox('abspath');
  const rows4 = readRows(path.join(d4, 'evidence', 'ledger.tsv'));
  rows4[0][COLS.indexOf('artifact')] = path.resolve(d4, 'evidence', 'read-full.txt');
  writeRows(path.join(d4, 'evidence', 'ledger.tsv'), COLS.slice(), rows4);
  const c8 = runCheck(d4);
  ck('变异 绝对路径 ⇒ 红=1 且红在 P', { token: 'FAIL', cmp: 17, redLines: 1, dead: 0, redAt: 'E1-P' },
    { token: c8.token, cmp: c8.cmp, redLines: reds(c8.out), dead: c8.dead, redAt: onlyRedId(c8.out) });
  const d5 = sandbox('escape');
  const rows5 = readRows(path.join(d5, 'evidence', 'ledger.tsv'));
  rows5[1][COLS.indexOf('artifact')] = '../outside/read-full.txt';
  writeRows(path.join(d5, 'evidence', 'ledger.tsv'), COLS.slice(), rows5);
  const c9 = runCheck(d5);
  ck('变异 越出 root ⇒ 红=1 且红在 P', { token: 'FAIL', redLines: 1, redAt: 'E2-P' },
    { token: c9.token, redLines: reds(c9.out), redAt: onlyRedId(c9.out) });

  // ⑧ 表头坏 ⇒ 只红 L 一条，且下游记未测而不是被跳过不打印
  const d6 = sandbox('header');
  const h = COLS.slice(); h.splice(COLS.indexOf('tool'), 1);
  const rows6 = readRows(path.join(d6, 'evidence', 'ledger.tsv'));
  writeRows(path.join(d6, 'evidence', 'ledger.tsv'), h, rows6.map((r) => r.filter((_, k) => k !== COLS.indexOf('tool'))));
  const c10 = runCheck(d6);
  ck('变异 表头少一列 ⇒ 红=1 且红在 L，下游未测不静默', { token: 'FAIL', cmp: 3, redLines: 1, redAt: 'L', nmLines: 2 },
    { token: c10.token, cmp: c10.cmp, redLines: reds(c10.out), redAt: onlyRedId(c10.out), nmLines: bodyLines(c10.out).filter((l) => l.endsWith(' NOT_MEASURED')).length });

  // ⑨ 同轮重跑：两行同轮次 ⇒ 未测（该按 ts 取最新，得有人确认）
  const d7 = sandbox('dupround');
  const rows7 = readRows(path.join(d7, 'evidence', 'ledger.tsv'));
  rows7[1][COLS.indexOf('round')] = colOf(rows7, 0, 'round');
  writeRows(path.join(d7, 'evidence', 'ledger.tsv'), COLS.slice(), rows7);
  const c11 = runCheck(d7);
  ck('变异 同轮两行 ⇒ 未测 且 dup_rounds=1', { token: 'NOT_MEASURED', dup: 1, cmp: 17, code: 2 },
    { token: c11.token, dup: c11.dup, cmp: c11.cmp, code: c11.code });

  // ⑩ require-round：缺这一轮 ⇒ 未测；命中 ⇒ 通过
  const c12 = runCheck(PKG, ['--require-round', 'round-01']);
  ck('require_round 命中 ⇒ PASS', { token: 'PASS', cmp: 18 }, { token: c12.token, cmp: c12.cmp });
  const c13 = runCheck(PKG, ['--require-round', 'round-99']);
  ck('require_round 缺该轮 ⇒ 未测（不当通过）', { token: 'NOT_MEASURED', cmp: 18, code: 2 }, { token: c13.token, cmp: c13.cmp, code: c13.code });

  // ⑪ add：真跑一遍 CLI，再 check 回来（盖章与核对必须自洽）
  const a1 = path.join(tmp, 'addcase');
  fs.mkdirSync(path.join(a1, 'evidence'), { recursive: true });
  fs.copyFileSync(FULL, path.join(a1, 'evidence', 'read-full.txt'));
  fs.copyFileSync(path.join(FIXDIR, 'pkg', 'evidence', 'read-no-tool.txt'), path.join(a1, 'evidence', 'read-no-tool.txt'));
  fs.copyFileSync(path.join(FIXDIR, 'pkg', 'evidence', 'read-empty.txt'), path.join(a1, 'evidence', 'read-empty.txt'));
  const al = path.join(a1, 'evidence', 'ledger.tsv');
  const r14 = runCli(['add', '--root', a1, '--round', 'round-01', '--claim', '某读数在阈值内', '--cmd', 'node demo.mjs --report r.txt', '--artifact', 'evidence/read-full.txt', '--verdict', 'PASS']);
  const l14 = concl(r14.out);
  ck('add 完整件 ⇒ 落 1 行', { token: 'PASS', cmp: 8, added: 1, code: 0 },
    { token: token(l14), cmp: num(l14, 'cmp'), added: num(l14, 'added'), code: r14.code });
  const c14 = runCheck(a1);
  ck('add 之后 check 回来自洽 ⇒ PASS', { token: 'PASS', rows: 1, cmp: 10, code: 0 }, { token: c14.token, rows: c14.rows, cmp: c14.cmp, code: c14.code });

  const r15 = runCli(['add', '--root', a1, '--round', 'round-02', '--claim', '件里没声明版本', '--cmd', 'node demo.mjs', '--artifact', 'evidence/read-no-tool.txt']);
  ck('add 不默认通过 ⇒ 判定记未测', { token: 'PASS', code: 0 }, { token: token(concl(r15.out)), code: r15.code });
  ck('版本读不到 ⇒ tool 写哨兵而不是编', { tool: SENT }, { tool: colOf(readRows(al), 1, 'tool') });
  ck('未给 --verdict ⇒ 落 NOT_MEASURED', { verdict: SENT }, { verdict: colOf(readRows(al), 1, 'verdict') });

  const r16 = runCli(['add', '--root', a1, '--round', 'round-03', '--claim', '空读数件', '--cmd', 'node demo.mjs', '--artifact', 'evidence/read-empty.txt', '--verdict', 'NOT_MEASURED']);
  ck('add 0 字节件 ⇒ 行照写但判未测', { token: 'NOT_MEASURED', added: 1, code: 2 },
    { token: token(concl(r16.out)), added: num(concl(r16.out), 'added'), code: r16.code });

  const before = readRows(al).length;
  const r17 = runCli(['add', '--root', a1, '--round', 'round-04', '--claim', '指向不存在的件', '--cmd', 'node demo.mjs', '--artifact', 'evidence/ghost.txt']);
  ck('add 件不在盘上 ⇒ 红且不写脏', { token: 'FAIL', code: 1, rows: before },
    { token: token(concl(r17.out)), code: r17.code, rows: readRows(al).length });
  const r18 = runCli(['add', '--root', a1, '--round', 'round-05', '--claim', '绝对路径', '--cmd', 'node demo.mjs', '--artifact', FULL]);
  ck('add 绝对件路径 ⇒ 红且不写脏', { token: 'FAIL', code: 1, rows: before },
    { token: token(concl(r18.out)), code: r18.code, rows: readRows(al).length });
  const r19 = runCli(['add', '--root', a1, '--round', 'round-06', '--claim', '带\t制表符', '--cmd', 'node demo.mjs', '--artifact', 'evidence/read-full.txt']);
  ck('add 字段含制表符 ⇒ 红且不写脏', { token: 'FAIL', code: 1, rows: before },
    { token: token(concl(r19.out)), code: r19.code, rows: readRows(al).length });
  const r20 = runCli(['add', '--root', a1, '--round', 'round-07', '--claim', '未盖章行', '--cmd', 'node demo.mjs', '--artifact', 'evidence/ghost.txt', '--force']);
  ck('add --force ⇒ 未盖章行 + 未测', { token: 'NOT_MEASURED', code: 2, digest: SENT },
    { token: token(concl(r20.out)), code: r20.code, digest: colOf(readRows(al), readRows(al).length - 1, 'digest') });

  // ⑪b 二进制件：摘要口径必须换成按字节，"行尾不参与"这句话对它不成立
  const b1 = path.join(tmp, 'bincase');
  fs.mkdirSync(path.join(b1, 'evidence'), { recursive: true });
  fs.copyFileSync(path.join(FIXDIR, 'pkg', 'evidence', 'read-binary.bin'), path.join(b1, 'evidence', 'read-binary.bin'));
  const bl = path.join(b1, 'evidence', 'ledger.tsv');
  runCli(['add', '--root', b1, '--round', 'round-01', '--claim', '二进制件也能量', '--cmd', 'node demo.mjs --blob', '--artifact', 'evidence/read-binary.bin', '--verdict', 'PASS']);
  ck('二进制件 ⇒ 摘要前缀 raw 且版本记哨兵', { mode: 'raw', tool: SENT },
    { mode: String(colOf(readRows(bl), 0, 'digest')).split(':')[0], tool: colOf(readRows(bl), 0, 'tool') });
  const c2b = runCheck(b1);
  ck('二进制件 check ⇒ 自洽 PASS', { token: 'PASS', rows: 1, cmp: 10, code: 0 },
    { token: c2b.token, rows: c2b.rows, cmp: c2b.cmp, code: c2b.code });
  fs.appendFileSync(path.join(b1, 'evidence', 'read-binary.bin'), Buffer.from([0x00]));
  const c3b = runCheck(b1);
  ck('二进制件被追加字节 ⇒ 只红一条且红在 I', { token: 'FAIL', redLines: 1, redAt: 'E1-I', dig: 1 },
    { token: c3b.token, redLines: reds(c3b.out), redAt: onlyRedId(c3b.out), dig: c3b.dig });

  // ⑫ render：等式 + 行数 0 ⇒ 未测 + 不洗白
  const md = path.join(tmp, 'out', 'ledger.md');
  const r21 = runCli(['render', '--root', PKG, '--out', md]);
  const l21 = concl(r21.out);
  ck('render 完整台账 ⇒ 等式成立', { token: 'PASS', rendered: 2, ledger_rows: 2, code: 0 },
    { token: token(l21), rendered: num(l21, 'rendered'), ledger_rows: num(l21, 'ledger_rows'), code: r21.code });
  const mdtxt = fs.existsSync(md) ? fs.readFileSync(md, 'utf8') : '';
  ck('渲染件含表头与两行数据', { head: true, rows: 2 },
    { head: /\| 轮次 \| 结论 \| 命令 \| 件 \| 判定 \| 摘要 \|/.test(mdtxt), rows: (mdtxt.split('\n').filter((l) => l.startsWith('| round-')).length) });
  const r22 = runCli(['render', '--root', EMPTY, '--out', path.join(tmp, 'out', 'empty.md')]);
  ck('render 空台账 ⇒ 未测且不写"无异常"', { token: 'NOT_MEASURED', code: 2, clean: true },
    { token: token(concl(r22.out)), code: r22.code, clean: !concl(r22.out).includes('无异常') });
  const r23 = runCli(['render', '--root', PKG, '--ledger', fx2, '--out', path.join(tmp, 'out', 'bad.md')]);
  ck('render 判定列非法 ⇒ 红（渲染不洗白）', { token: 'FAIL', code: 1 }, { token: token(concl(r23.out)), code: r23.code });
  const r24 = runCli(['render', '--root', d6, '--out', path.join(tmp, 'out', 'header-broken.md')]);
  const l24 = concl(r24.out);
  ck('render 表头坏 ⇒ 红一条在 L，等式那行不许静默成立', { token: 'FAIL', cmp: 4, redLines: 1, redAt: 'L', rendered: 0, ledger_rows: 2 },
    { token: token(l24), cmp: num(l24, 'cmp'), redLines: reds(r24.out), redAt: onlyRedId(r24.out), rendered: num(l24, 'rendered'), ledger_rows: num(l24, 'ledger_rows') });

  // ⑬ 形状自检：打印出的每一行判定词都必须在三态集合里（结论行也算）
  const sample = runCli(['check', '--root', PKG]).out.split('\n').filter((l) => l.trim() !== '');
  const badTok = sample.filter((l) => !/^(L|E\d+-[FPDNIVTAU]|U|A|R|判)\s/.test(l) || !VERDICTS.has(l.trim().split(/\s+/).pop()));
  ck('输出形状：每行末字段都是三态之一', { bad: 0 }, { bad: badTok.length });

  for (const l of out) console.log(l);
  const selfNm = out.filter((l) => l.endsWith(' NOT_MEASURED')).length;
  console.log(`判 ${out.length} 项：红=${red} 未测=${selfNm} 夹具 pkg=${fs.readdirSync(path.join(FIXDIR, 'pkg', 'evidence')).length} 件 沙箱=${red ? '保留（复跑用，别提交、别当证据）' : '已清理'} ${red ? 'FAIL' : 'PASS'}`);
  if (red) console.log('自测有红：临时沙箱留在系统临时目录里，用它复跑；这个目录不属于交付树。');
  else fs.rmSync(tmp, { recursive: true, force: true });
  return red ? 1 : 0;
}

// ---------------------------------------------------------------- main
function main(argv) {
  const { flags, pos } = parseArgs(argv);
  if (flags.self) return selfTest();
  if (flags.help || pos.length === 0) { console.log(USAGE); return pos.length === 0 && !flags.help ? 2 : 0; }
  const sub = pos[0];
  if (!ALLOWED[sub]) { console.log(`判 1 项：未知子命令 ${sub} FAIL`); return 1; }
  const unknown = Object.keys(flags).filter((k) => !ALLOWED[sub].includes(k) && !['help', 'self'].includes(k));
  if (unknown.length) { console.log(`判 1 项：${sub} 不接受的选项 --${unknown.join(' --')} FAIL`); return 1; }
  if (sub === 'add') return cmdAdd({ flags });
  if (sub === 'check') return cmdCheck({ flags });
  return cmdRender({ flags });
}
process.exit(main(process.argv.slice(2)));
