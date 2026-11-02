// check-selftest.mjs —— 检查器自己的测试（本包的规矩：每个尺子都得有能红的对照，包括这把尺子本身）
//
// 为什么必须有：`--self` 全绿而真实运行是红，通常意味着夹具绕过了提取层。
// 所以这里不复制"理想条目"，而是**逐条构造会让某个判据红的输入**，断言红的正是那一条。
//
// 用法：node _meta/check-selftest.mjs       （只在临时目录里活动，不写被检查的树）
// 退出码：0=全部符合预期；1=有预期不符（尺子坏了）
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const CHECKER = path.join(path.dirname(path.resolve(process.argv[1] || '.')), 'check-skill-package.mjs');
const SECTION_RE = /^## (适用场景|使用方法|失效条件|已验证效果|来源)$/;

function entry(name, body) {
  return {
    rel: `demo/${name}`,
    md: `---\nname: ${name}\ndescription: 用于某类活需要判断该怎么走时；出现【症状】、当结论无法由读数支撑、或需要在动手前先确认边界的场景。\n---\n\n# 标题\n\n${body}\n`,
  };
}
const GOOD = `## 适用场景\n\n症状级描述：说不清这一轮赢在哪。\n\n## 使用方法\n\n1. 先查一手资料（厂商用户指南与数据手册优先）。\n2. 先跟用户确认不可逆动作。\n3. 跑 \`node scripts/compare.mjs --self\`，应看到"判 N 项 … PASS"。\n\n## 失效条件\n\n工具版本不同则字段形状不同，正则射程会静默变窄；征兆是抓到 0 条却报绿。\n\n## 已验证效果\n\n某一次同一设计里的形状（量级仅供参照，不可当普适结论）：夹具 4 条，红 1 条且只红那一条（比较数 4）。复跑命令见使用方法。\n\n## 来源\n\n长自"把没比较当通过"这一类观察（见 pitfalls/ruler-fake-greens）。`;

const CASES = [
  { id: 'C01', want: 'PASS', name: 'good-one', md: GOOD },
  { id: 'C02', want: 'FAIL', wantSub: '缺节「失效条件」', name: 'no-boundary',
    md: GOOD.replace(/## 失效条件[\s\S]*?\n\n## 已验证效果/, '## 已验证效果') },
  { id: 'C03', want: 'FAIL', wantSub: '失效条件是空话', name: 'empty-boundary',
    md: GOOD.replace('工具版本不同则字段形状不同，正则射程会静默变窄；征兆是抓到 0 条却报绿。', '无') },
  { id: 'C04', want: 'FAIL', wantSub: '已验证效果既没数也没', name: 'no-effect',
    md: GOOD.replace(/## 已验证效果[\s\S]*?\n\n## 来源/, '## 已验证效果\n\n效果很好，用过都说好。\n\n## 来源') },
  { id: 'C05', want: 'FAIL', wantSub: 'description 没有触发条件', name: 'bad-desc',
    md: GOOD, descFix: 'description: 用于把九步节拍写成清单再照抄的做法说明，一步一步怎么做都在这条里。' },
  { id: 'C06', want: 'FAIL', wantSub: '含本机绝对路径', name: 'abs-path',
    md: GOOD + '\n参考 C:/Users/someone/Tool/docs/README.md 这一份。\n' },   // abs-fixture 检查器自带的反例内容（与本机无关的通用路径形状），不是指令
  { id: 'C07', want: 'FAIL', wantSub: '专有名词', name: 'proj-name',
    md: GOOD + '\n这条在 r118 那轮量过。\n' },
  { id: 'C08', want: 'FAIL', wantSub: 'name≠目录名', name: 'bad-name', md: GOOD, rawFix: e => e.replace('name: bad-name', 'name: other-name') },
  { id: 'C09', want: 'FAIL', wantSub: '留了 TODO', name: 'todo-left', md: GOOD + '\nTODO: 补一个数。\n' },
  { id: 'C10', want: 'FAIL', wantSub: '却没声明"非普适"', name: 'numbers-without-disclaimer',
    md: GOOD.replace('某一次同一设计里的形状（量级仅供参照，不可当普适结论）：夹具 4 条，红 1 条且只红那一条（比较数 4）。复跑命令见使用方法。',
      '实测：hold 余量 0.050 ns、setup 余量 0.445 ns、失败端点 25,742 个（量到 3 处）。') },
  { id: 'C11', want: 'PASS', name: 'effect-declared-unmeasured',
    md: GOOD.replace('某一次同一设计里的形状（量级仅供参照，不可当普适结论）：夹具 4 条，红 1 条且只红那一条（比较数 4）。复跑命令见使用方法。', '未量过，属建议。') },
];

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'skillpack-selftest-'));
const written = [];
function build(entries, withIndex) {
  fs.rmSync(root, { recursive: true, force: true });
  fs.mkdirSync(root, { recursive: true });
  const made = [];
  for (const e of entries) {
    const dir = path.join(root, 'demo', e.name);
    fs.mkdirSync(dir, { recursive: true });
    let md = e.md;
    let head = `---\nname: ${e.name}\ndescription: 用于某类活需要判断该怎么走时；出现【症状】、当结论无法由读数支撑、或需要在动手前先确认边界的场景。\n---\n\n# 标题\n\n`;
    if (e.descFix) head = `---\nname: ${e.name}\n${e.descFix}\n---\n\n# 标题\n\n`;
    let doc = head + md;
    if (e.rawFix) doc = e.rawFix(doc);
    fs.writeFileSync(path.join(dir, 'SKILL.md'), doc);
    made.push(`demo/${e.name}`);
  }
  let idx = made.map(p => `| \`${p}/SKILL.md\` | 什么时候用 |`).join('\n');
  if (!withIndex) idx = '';
  fs.writeFileSync(path.join(root, 'README.md'), `# 索引\n\n${idx}\n`);
  return made;
}

const out = [];
let bad = 0;
function run(label, entries, withIndex) {
  build(entries, withIndex);
  let stdout = '';
  let code = 0;
  try { stdout = execFileSync(process.execPath, [CHECKER, root], { encoding: 'utf8' }); }
  catch (e) { stdout = (e.stdout || '') + ''; code = e.status ?? 1; if (!stdout) console.log(`DIAG ${label} status=${code} err=${String(e.message).slice(0, 160)} stderr=${String(e.stderr || '').slice(0, 400)}`); }
  return { stdout, code, label };
}

// ① 逐条构造坏输入：断言"红的正是那一条"，其余必须绿
const r1 = run('mutations', CASES.filter(c => c.id !== 'C01').concat([CASES[0]]), true);
for (const c of CASES) {
  const line = r1.stdout.split(/\r?\n/).find(l => l.startsWith('E ') && l.includes(`demo/${c.name} `));
  const got = line ? line.trim().split(/\s+/).pop() : 'MISSING';
  const detail = line || '(这一行根本没被打印)';
  const subOk = !c.wantSub || detail.includes(c.wantSub);
  const ok = got === c.want && subOk && (c.want === 'PASS' || r1.code === 1);
  if (!ok) bad++;
  out.push(`R1 ${c.id} ${c.name} 期望=${c.want}${c.wantSub ? '/' + c.wantSub : ''} 实读=${got} 细节符合=${subOk ? 'yes' : 'no'} ${ok ? 'PASS' : 'FAIL'}`);
}

// ② 正对照必须能动：条目数从 2 → 21，地板判据应从 NOT_MEASURED 变 PASS
const many = Array.from({ length: 20 }, (_, i) => ({ ...CASES[0], name: `good-${i}` }));
const r2a = run('floor-red', [CASES[0], { ...CASES[0], name: 'good-b' }], true);
const r2b = run('floor-green', many, true);
const f = s => (s.split(/\r?\n/).find(l => l.startsWith('F1 ')) || '').trim().split(/\s+/).pop();
const fa = f(r2a.stdout), fb = f(r2b.stdout);
const floorOk = fa === 'NOT_MEASURED' && fb === 'PASS';
if (!floorOk) bad++;
out.push(`R2 F1 地板可动 2条=${fa} 20条=${fb} ${floorOk ? 'PASS' : 'FAIL'}`);

// ③ 索引双向：漏列一条 ⇒ I2 红；多列一条不存在的 ⇒ I1 红
const r3 = run('index-missing', [CASES[0]], false);
const i2 = (r3.stdout.split(/\r?\n/).find(l => l.startsWith('I2 ')) || '').trim();
const i2ok = /FAIL|NOT_MEASURED/.test(i2);
if (!i2ok) bad++;
out.push(`R3 I2 条目未列入索引 该行="${i2.replace(/\s+/g, ' ')}" ${i2ok ? 'PASS' : 'FAIL'}`);
build([CASES[0]], true);
fs.writeFileSync(path.join(root, 'README.md'),
  fs.readFileSync(path.join(root, 'README.md'), 'utf8') + '\n| `demo/not-there/SKILL.md` | 假行 | 什么时候用 |\n');
let r4out = '';
try { r4out = execFileSync(process.execPath, [CHECKER, root], { encoding: 'utf8' }); }
catch (e) { r4out = (e.stdout || '') + ''; }
const i1 = (r4out.split(/\r?\n/).find(l => l.startsWith('I1 ')) || '').trim();
const i1ok = /FAIL/.test(i1) && /not-there/.test(i1);
if (!i1ok) bad++;
out.push(`R4 I1 索引死行能红 该行="${i1.replace(/\s+/g, ' ')}" ${i1ok ? 'PASS' : 'FAIL'}`);

// ④ 形状自检：五节标题在 GOOD 夹具里确实齐（防止夹具自己写歪而使 C01 的绿是假绿）
const secFound = (GOOD.match(new RegExp(SECTION_RE.source, 'gm')) || []).length;
const secOk = secFound === 5;
if (!secOk) bad++;
out.push(`R5 夹具五节齐全 抓到=${secFound}/5 ${secOk ? 'PASS' : 'FAIL'}`);

// ⑥ 每条变异必须**真的改到了文本**：replace 的锚点不存在时静默不改，C04 就是这么漏判的
const stuck = CASES.filter(c => c.want === 'FAIL' && !c.descFix && !c.rawFix && c.md === GOOD);
const mutOk = stuck.length === 0;
if (!mutOk) bad++;
out.push(`R6 变异都改到了文本 未改动=${stuck.length}${stuck.length ? ' ' + stuck.map(c => c.id).join(',') : ''} ${mutOk ? 'PASS' : 'FAIL'}`);

for (const l of out) console.log(l);
console.log(`SKILL-SELFTEST 判 ${out.length} 项 不符=${bad} ${bad ? 'FAIL' : 'PASS'}`);
fs.rmSync(root, { recursive: true, force: true });
process.exit(bad ? 1 : 0);
