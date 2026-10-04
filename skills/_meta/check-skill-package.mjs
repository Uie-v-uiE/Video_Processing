// 用途：技能包的机器判据（写给人也用给机器；两条硬规矩：不静默、不空转）
// 输入：命令行参数
// 输出：stdout
// 退出码：脚本内无显式 exit ⇒ 随最后一条命令（正常跑完为 0）
// check-skill-package.mjs —— 技能包的机器判据（写给人也用给机器；两条硬规矩：不静默、不空转）
//
// 判什么（每条都能单独红，且结论行打印"判了几项"）：
//  E 结构/可发现性/精简/四问齐不齐/可移植（逐项，一个条目一行）
//  I1 索引指向的条目都存在；I2 条目都在索引里出现一次
//  F1 条目数地板（<20 ⇒ NOT_MEASURED，不判通过）
//  G 通用性：正文里不许出现专有名词（工程/板卡/轮次号）
// 长度维度按**字符数**：中文没有空格，按 wc -w 那种"词"数判等于没判。
// 用法：node _meta/check-skill-package.mjs [技能包根目录]   （缺省 = 本文件所在目录的上一级）
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(process.argv[2] || path.join(path.dirname(path.resolve(process.argv[2] || '.')), '..'));
const SKIP_DIR = /(^|\/)(_meta|node_modules|fixtures|_out)(\/|$)/;
const SECTIONS = ['适用场景', '使用方法', '失效条件', '已验证效果', '来源'];
const LINES_MAX = 500, CHARS_MAX = 6000;
// 专有名词黑名单：出现即判"这条不够通用"（赛题要求可复用性的直接判据）
const PROJ_RE = /(Video_Processing|ZYNQ7020|xc7z020|RK-|Pynq|Verilog[ _]?[Pp]rocessing|r1[0-9][0-9]\b|ISSUES ?#[0-9]|#[0-9]{2,3}\b)/;
const EMPTYISH = /^[（(]?\s*(无|暂无|不适用|待定|TBD|N\/A)[）)]?[，,。.、]?$/;
const rows = [];
let entriesChecked = 0, projHits = 0;
const say = (id, name, detail, verdict) => { rows.push(`${id} ${name} ${detail} ${verdict}`); };

function walk(d, acc) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    if (!e.isDirectory()) continue;
    const p = path.join(d, e.name);
    if (SKIP_DIR.test(p.replace(/\\/g, '/'))) continue;
    if (fs.existsSync(path.join(p, 'SKILL.md'))) acc.push(p); else walk(p, acc);
  }
  return acc;
}
const entries = fs.existsSync(ROOT) ? walk(ROOT, []) : [];

for (const dir of entries) {
  const rel = path.relative(ROOT, dir).replace(/\\/g, '/');
  const raw = fs.readFileSync(path.join(dir, 'SKILL.md'), 'utf8');
  const fmM = raw.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  const bad = [];
  entriesChecked++;
  if (!fmM) bad.push('缺 frontmatter');
  const fm = fmM ? fmM[1] : '';
  const name = (fm.match(/^name:\s*(.+)$/m) || [, ''])[1].trim();
  const desc = (fm.match(/^description:\s*(.+)$/m) || [, ''])[1].trim();
  if (name !== path.basename(dir)) bad.push(`name≠目录名(${name || '空'})`);
  if (!/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(name)) bad.push('name 不是 hyphen-case（禁首尾/连续连字符）');
  if (desc.length < 40) bad.push(`description 太短(${desc.length})`);
  if (desc.length > 1024) bad.push(`description ${desc.length} > 1024`);
  if (!/^(用于|Use when)/.test(desc)) bad.push('description 不以「用于…」开头');
  if (!/(时|当|若|需要|出现|场景)/.test(desc)) bad.push('description 没有触发条件（写症状，别写做法）');
  const body = raw.slice(fmM ? fmM[0].length : 0);
  const lines = body.split(/\r?\n/).length;
  const chars = body.replace(/\s/g, '').length;
  if (lines > LINES_MAX) bad.push(`body ${lines} 行 > ${LINES_MAX}`);
  if (chars > CHARS_MAX) bad.push(`正文 ${chars} 字符 > ${CHARS_MAX}（该拆 references/）`);
  for (const s of SECTIONS) {
    const sec = body.match(new RegExp(`##[^\\n]*${s}[^\\n]*\\r?\\n([\\s\\S]*?)(?=\\n##\\s|$)`));
    if (!sec) { bad.push(`缺节「${s}」`); continue; }
    const txt = sec[1].trim();
    if (!txt) bad.push(`节「${s}」是空的`);
    if (s === '失效条件' && (txt.length < 12 || EMPTYISH.test(txt))) bad.push('失效条件是空话（该写征兆与边界）');
    if (s === '已验证效果') {
      if (!/[0-9０-９]|未量过|属建议/.test(txt)) bad.push('已验证效果既没数也没「未量过」声明');
      // 有"测量形状"（带单位的量、千分位读数、"量到/实测"字样）达 3 处 ⇒ 必须声明非普适。
      // 只看数字会误伤"应为 1"这类处方，所以维度选"测量标记"而不是"数字个数"。
      const meas = ((txt.match(/\d+(?:\.\d+)?\s*(?:ns|ps|us|ms|MHz|GHz|%|℃|LUT|FF|条端点)/gi) || []).length)
        + ((txt.match(/\d,\d{3}/g) || []).length)
        + ((txt.match(/量到|实测/g) || []).length);
      if (meas >= 3 && !/(不可当普适|不是普适|普适|量级|随设计变|仅供形状|同一设计里|某一次)/.test(txt))
        bad.push(`已验证效果有 ${meas} 处测量标记却没声明"非普适"（工程专有读数不许当通用结论引用）`);
    }
  }
  if (/TODO:|待补|【填入】/.test(raw)) bad.push('留了 TODO/待补/【填入】');
  if (/[A-Za-z]:[\\/]|\/home\/\w|\/mnt\/[a-z]\/|\/d\//.test(raw)) bad.push('含本机绝对路径');
  const pm = raw.match(PROJ_RE);
  if (pm) { bad.push(`专有名词「${pm[0]}」`); projHits++; }
  const pf = fs.existsSync(path.join(dir, 'references')) ? fs.readdirSync(path.join(dir, 'references')).length : 0;
  const ps = fs.existsSync(path.join(dir, 'scripts')) ? fs.readdirSync(path.join(dir, 'scripts')).length : 0;
  say('E', rel, bad.length ? `问题=${bad.join('、')}` : `行=${lines} 字符=${chars} refs=${pf} scripts=${ps}`, bad.length ? 'FAIL' : 'PASS');
}

const idxPath = path.join(ROOT, 'README.md');
const idx = fs.existsSync(idxPath) ? fs.readFileSync(idxPath, 'utf8') : '';
const idxRows = [...idx.matchAll(/`([a-z0-9-]+(?:\/[a-z0-9-_]+)+)\/SKILL\.md`/g)].map(x => x[1]);
const setIdx = new Set(idxRows), setDir = new Set(entries.map(d => path.relative(ROOT, d).replace(/\\/g, '/')));
const missIdx = [...setDir].filter(x => !setIdx.has(x));
const deadIdx = [...setIdx].filter(x => !setDir.has(x));
say('I1', '索引指向的条目都存在', `索引行=${idxRows.length} 死行=${deadIdx.length}${deadIdx.length ? ' ' + deadIdx.slice(0, 3).join(',') : ''}`,
    idxRows.length === 0 ? 'NOT_MEASURED' : (deadIdx.length ? 'FAIL' : 'PASS'));
say('I2', '条目都在索引里出现一次', `条目=${setDir.size} 未列=${missIdx.length}${missIdx.length ? ' ' + missIdx.slice(0, 3).join(',') : ''}`,
    setDir.size === 0 ? 'NOT_MEASURED' : (missIdx.length ? 'FAIL' : 'PASS'));
say('G', '通用性（无专有名词）', `命中=${projHits} 黑名单=${PROJ_RE.source.slice(0, 28)}…`, entriesChecked === 0 ? 'NOT_MEASURED' : (projHits ? 'FAIL' : 'PASS'));
const floorVerdict = entriesChecked < 20 ? 'NOT_MEASURED' : 'PASS';
say('F1', '条目数地板', `实读=${entriesChecked} 地板=20${floorVerdict === 'NOT_MEASURED' ? ' ⇒ 这一层多半没扫成，不是包干净' : ''}`, floorVerdict);
// 判定行必须**全部打印**（有一条没打印就等于那条没判；只报数不打印的判据是本包自己记过的账）
for (const p of rows) console.log(p);

const red2 = rows.filter(r => r.endsWith('FAIL')).length;
const nm = rows.filter(r => r.endsWith('NOT_MEASURED')).length;
console.log(`判 ${rows.length} 项：条目=${entriesChecked} 索引=${idxRows.length} 红=${red2} 未测=${nm} ${red2 ? 'FAIL' : (nm ? 'NOT_MEASURED' : 'PASS')}`);
process.exit(red2 ? 1 : 0);
