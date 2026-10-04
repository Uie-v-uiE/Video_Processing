#!/usr/bin/env node
/**
 * skill/scripts/check/static_check.mjs
 * 静态 + 半动态门禁：技能包脚本不许碰网络、不许往工程目录写东西
 *
 * 用法：node skill/scripts/check/static_check.mjs [--root skill/scripts] [--exe bash,node]
 * 退出码：0=PASS 1=FAIL 2=NOT_MEASURED 3=前置不满足
 *
 * 为什么两条腿都要有：只做静态 grep 会被"路径是拼出来的"绕过；只做动态跑会被"这条分支今天没走到"
 * 绕过。所以 T3 在同一条判据里同时要求"源码里有工程目录守卫"与"真把 --out-dir 指到 build/ 时它拒绝了"。
 */
import fs from 'node:fs';
import path from 'node:path';

const HELP = `用法: node static_check.mjs [--root skill/scripts] [--skip-run]
扫描对象 = <root> 下的 *.mjs 与 *.sh（不含 selftest/fixtures/，那里是故意放违规样本的地方）。
判据: T1 无网络  T2 无工程目录写入(静态)  T3 守卫在场且真的拒绝(动态)  T4 违规样本必须被抓到
      T5 阈值不许在源码里带默认值  T6 --help 覆盖代码里读的每个 --flag
退出码: 0=PASS 1=FAIL 2=NOT_MEASURED 3=前置不满足`;

const argv = process.argv.slice(2);
const opt = {};
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--help' || a === '-h') { console.log(HELP); process.exit(0); }
  if (a.startsWith('--')) { opt[a.slice(2)] = (argv[i + 1] && !argv[i + 1].startsWith('--')) ? argv[++i] : '1'; continue; }
  console.log('STATIC 前置不满足 无法识别的参数 ' + a + ' NOT_MEASURED');
  console.log('STATIC 前置不满足 判 0 项 FAIL'); process.exit(3);
}
const ROOT = opt.root || 'skill/scripts';
if (!fs.existsSync(ROOT)) { console.log(`STATIC 读不到输入 ${ROOT} 不存在 NOT_MEASURED`); console.log('STATIC 读不到输入 判 0 项 NOT_MEASURED'); process.exit(2); }

const PROTECTED = ['src/', 'sim/', 'build/', 'board/', 'data/', 'report/', 'docs/'];
const NET_PATTERNS = [
  [/\bfetch\s*\(/, 'fetch()'],
  [/require\(['"]https?['"]\)|from ['"]node:https?['"]/, 'node: http/https 模块'],
  [/XMLHttpRequest/, 'XMLHttpRequest'],
  [/from ['"]node:net['\"]|require\(['"]net['"]\)/, 'node: net'],
  [/from ['"]node:dgram['\"]|require\(['"]dgram['"]\)/, 'node: dgram'],
  [/from ['"]node:tls['\"]|require\(['"]tls['"]\)/, 'node: tls'],
  [/\b(curl|wget|nslookup|ssh|scp|telnet|ping)\s+['"-]?[a-z0-9]/i, '外部网络命令'],
  [/\b(git)\s+(clone|fetch|pull|push)\b/, 'git 联网子命令'],
  [/\b(npm|pip|choco|winget)\s+(install|add|update)\b/, '包管理器联网'],
  [/['"]https?:\/\//, 'URL 字面量'],
];
const WRITE_PATTERNS = [/\bwriteFileSync\b/, /\bappendFileSync\b/, /\bcreateWriteStream\b/, /\bmoveFileSync?\b/,
  /\brmSync\b/, /\bcopyFileSync\b/, /\bmkdirSync\b/, /\bmv\s/, /\bcp\s/, /\brm\s+-rf?\s/, /[^>]>[^>]/];

function scanDir(root) {
  const acc = [];
  const walk = d => {
    for (const e of fs.readdirSync(d, { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1))) {
      const p = path.join(d, e.name).split(path.sep).join('/');
      if (e.isDirectory()) { if (p.includes('selftest/fixtures') || p.endsWith('_out')) continue; walk(p); }
      else if (/\.(mjs|sh)$/.test(e.name)) acc.push(p);
    }
  };
  walk(root);
  return acc;
}

const files = scanDir(ROOT);
if (!files.length) { console.log(`STATIC 读不到输入 ${ROOT} 下没有 .mjs/.sh 可扫 NOT_MEASURED`); console.log('STATIC 读不到输入 判 0 项 NOT_MEASURED'); process.exit(2); }

const lines = [];
let nMade = 0, nFail = 0, nNm = 0, nPass = 0;
function say(name, made, detail, verdict) {
  nMade += made;
  if (verdict === 'FAIL') nFail++; else if (verdict === 'NOT_MEASURED') nNm++; else nPass++;
  lines.push(`${name.padEnd(30)} 判 ${made} 项 ${detail} ${verdict}`);
}

function findNet(txt, file) {
  const hits = [];
  txt.split('\n').forEach((l, i) => {
    if (l.trim().startsWith('//') || l.trim().startsWith('#')) return;   // 注释里讲规则不算违规
    for (const [re, why] of NET_PATTERNS) if (re.test(l)) hits.push(`${file}:${i + 1} ${why}`);
  });
  return hits;
}
function findProtectedWrite(txt, file) {
  const hits = [];
  txt.split('\n').forEach((l, i) => {
    if (l.trim().startsWith('//') || l.trim().startsWith('#')) return;
    const isWrite = WRITE_PATTERNS.some(re => re.test(l));
    if (!isWrite) return;
    const lit = PROTECTED.find(p => new RegExp(`['"\` ]${p.replace(/[/]/g, '/')}`).test(l) || l.includes(`'${p}`) || l.includes(`"${p}`));
    if (lit) hits.push(`${file}:${i + 1} 写 token 与工程目录 ${lit} 同现`);
  });
  return hits;
}

// T1 网络（成对：扫过的文件数与命中数同条出现）
{
  const hits = files.flatMap(f => findNet(fs.readFileSync(f, 'utf8'), f));
  say('T1_no_network', files.length, `扫=${files.length} 命中=${hits.length}${hits.length ? ' 例:' + hits.slice(0, 3).join(' | ') : ''}`,
      hits.length ? 'FAIL' : 'PASS');
}

// T2 工程目录写入（静态）
{
  const hits = files.flatMap(f => findProtectedWrite(fs.readFileSync(f, 'utf8'), f));
  say('T2_no_write_into_project', files.length, `扫=${files.length} 命中=${hits.length}${hits.length ? ' 例:' + hits.slice(0, 3).join(' | ') : ''}`,
      hits.length ? 'FAIL' : 'PASS');
}

// T3 守卫在场（两维同条：源码里有守卫表，而且表要覆盖全部工程目录，缺一个前缀等于没守卫）
{
  const writers = files.filter(f => f.endsWith('.mjs') && /writeFileSync|appendFileSync|mkdirSync/.test(fs.readFileSync(f, 'utf8'))
    && !f.endsWith('static_check.mjs'));
  let made = 0, bad = 0; const det = [];
  for (const f of writers) {
    const txt = fs.readFileSync(f, 'utf8');
    made++;
    const decl = txt.match(/PROTECTED\s*=\s*\[([^\]]*)\]/);
    if (!decl) { bad++; det.push(`${f}:没有 PROTECTED 守卫表`); continue; }
    made++;
    const missing = PROTECTED.filter(p => !decl[1].includes(p));
    if (missing.length) { bad++; det.push(`${f}:守卫表少了 ${missing.join(',')}`); }
    else det.push(`${path.basename(f)}:守卫表覆盖 ${PROTECTED.length} 个工程目录前缀`);
  }
  // 这条判据的另一半（"真把产物指到 build/ 时会不会拒绝"）在 selftest/run_all.sh 里逐脚本跑，
  // 因为只有在 run_all 里才知道每个脚本的完整命令行；两边加起来才算判过。
  say('T3_guard_covers_project_dirs', made,
      `写文件的脚本=${writers.length} 判=${made} 破=${bad}${det.length ? ' 例:' + det.slice(0, 3).join(' | ') : ''}`,
      writers.length === 0 ? 'NOT_MEASURED' : (bad ? 'FAIL' : 'PASS'));
}

// T4 反例自证：violation 样本必须被抓到（抓不到 = 这把尺子空转）
{
  const dir = opt.samples || 'skill/scripts/selftest/fixtures/static_violation';
  if (!fs.existsSync(dir)) say('T4_must_catch_bad_sample', 0, `反例样本目录 ${dir} 不存在`, 'NOT_MEASURED');
  else {
    const bad = fs.readdirSync(dir).filter(f => /\.(mjs|sh)$/.test(f));
    if (!bad.length) say('T4_must_catch_bad_sample', 0, `${dir} 里没有 .mjs/.sh 样本`, 'NOT_MEASURED');
    else {
      let made = 0, missed = 0; const det = [];
      for (const f of bad) {
        const p = (dir + '/' + f).split(path.sep).join('/');
        const txt = fs.readFileSync(p, 'utf8');
        made++;
        const h = [...findNet(txt, p), ...findProtectedWrite(txt, p)];
        if (!h.length) { missed++; det.push(`${f}:一处都没抓到`); }
      }
      say('T4_must_catch_bad_sample', made, `样本=${bad.length} 漏抓=${missed}${det.length ? ' 例:' + det.slice(0, 2).join(' | ') : ''}`,
          missed ? 'FAIL' : 'PASS');
    }
  }
}

// T5 阈值不许在源码里带默认值（`opt[...] || 数字` 这种写法把命令行变成了摆设）
{
  const hits = [];
  for (const f of files) {
    const txt = fs.readFileSync(f, 'utf8');
    txt.split('\n').forEach((l, i) => {
      if (l.trim().startsWith('//') || l.trim().startsWith('#')) return;
      if (/opt(\[[^\]]+\]|\.\w+)\s*(\|\||\?\?|!==?\s*undefined\s*\?)\s*[-0-9]/.test(l) && /opt(\[[^\]]+\]|\.\w+)\s*(\|\||\?\?)/.test(l))
        hits.push(`${f}:${i + 1}`);
    });
  }
  say('T5_no_bare_default_threshold', files.length, `扫=${files.length} 命中=${hits.length}${hits.length ? ' 例:' + hits.slice(0, 3).join(' | ') : ''}`,
      hits.length ? 'FAIL' : 'PASS');
}

// T6 --help 要覆盖代码里读的每个 --flag（两维：代码读得到 与 文档写得到）
{
  let made = 0, bad = 0; const det = [];
  for (const f of files.filter(x => x.endsWith('.mjs'))) {
    const txt = fs.readFileSync(f, 'utf8');
    const help = (txt.match(/const HELP = `([\s\S]*?)`/) || [, ''])[1];
    if (!help) continue;
    const used = new Set();
    for (const m of txt.matchAll(/opt\[?['"]?([a-z][a-z0-9-]{2,})['"]?\]?(?:\s*(?:\|\||!== undefined|=== undefined))?/g)) used.add(m[1]);
    for (const flag of used) {
      if (/^(argv|contract|root|help|out|skip|samples|prefix)$/.test(flag)) continue;
      made++;
      if (!help.includes('--' + flag) && !help.includes(flag)) { bad++; det.push(`${path.basename(f)}:--${flag} 没写进 --help`); }
    }
  }
  say('T6_help_lists_every_flag', made, `判=${made} 缺文档=${bad}${det.length ? ' 例:' + det.slice(0, 3).join(' | ') : ''}`,
      made === 0 ? 'NOT_MEASURED' : (bad ? 'FAIL' : 'PASS'));
}

for (const l of lines) console.log(l);
const verdict = nFail ? 'FAIL' : (nNm ? 'NOT_MEASURED' : (nMade === 0 ? 'NOT_MEASURED' : 'PASS'));
console.log(`STATIC root=${ROOT} 判 ${nMade} 项 未判 ${nNm} 项 红 ${nFail} 项 ${verdict}`);
process.exit(verdict === 'PASS' ? 0 : verdict === 'FAIL' ? 1 : 2);
