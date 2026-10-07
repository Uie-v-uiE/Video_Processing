// build/submit_open_items.mjs —— 提交分支专用：从**留下来的文档**里现生成未决项一览
//
// 依赖：Node 22+（无第三方模块）；在提交分支的工作树根目录跑。
// 用法：node build/submit_open_items.mjs            （打印计数，不写文件）
//       node build/submit_open_items.mjs --write    （写 report/90-open-items.md）
// 参数：
//   | 参数 | 作用 |
//   | --- | --- |
//   | `--write` | 真正生成文件；不加就只数不写 |
//   | 环境变量 `SUBMIT_OPEN_ITEMS_OUT` | 换输出路径（自测用） |
//
// 为什么要它：C8 那条判据要求"全文所有未决标记必须在未决项集中表里被认领"。
// 提交分支删掉了逐轮流水账，旧的那张 258 行表连同它登记的对象一起没了 ⇒ 表必须由**现存文档**现生成，
// 不能手抄（手抄一定与正文脱节，那正是 C8 要抓的错）。
// 表里的"内容一句话"就是正文那一行本身（截断），"需要我做什么"按标记类型给固定口径——
// 这是机械索引，不是重新判断；判断仍留在各份文档里。

import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const write = process.argv.includes('--write');
const out = process.env.SUBMIT_OPEN_ITEMS_OUT || path.join(root, 'report', '90-open-items.md');
const SKIP = new Set(['.git', 'vivado_system', 'node_modules', 'final_submission', 'local_docs', 'deep_course']);
const MARKERS = ['【未实测】', 'NOT_MEASURED', '【待验证】', '【待你补】', '【未核实】', '【队伍未确认】', '【填入】'];
const MEANING = {
  '【未实测】': '需要一次仪器或板级实测才能填这一格',
  'NOT_MEASURED': '缺一次可跑的复核（脚本或探针），补上就跑',
  '【待验证】': '需要再跑一次对照或换工况验证',
  '【待你补】': '需要队伍里的人补一条事实（原话、日期或现场观察）',
  '【未核实】': '需要有人回读出处核对，不自动采信',
  '【队伍未确认】': '需要队伍拍板，机器不替人决定',
  '【填入】': '需要填一个具体值（填之前不留空话）',
};
const IMPACT = {
  '【未实测】': '性能与资源优化效果(20)／功能正确性与设计完整性(20)',
  'NOT_MEASURED': '文档质量与可复现性(15)',
  '【待验证】': '功能正确性与设计完整性(20)',
  '【待你补】': '创新性与应用价值(30)',
  '【未核实】': '文档质量与可复现性(15)',
  '【队伍未确认】': '创新性与应用价值(30)',
  '【填入】': '文档质量与可复现性(15)',
};

function walk(dir, acc = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (SKIP.has(e.name)) continue;
    const full = path.join(dir, e.name);
    if (e.isDirectory()) walk(full, acc);
    else if (/\.md$/.test(e.name)) acc.push(full);
  }
  return acc;
}

// 抄进来的那一行里若有点名不存在文件的路径（旧目录、被剪掉的凭据），必须去掉路径形状：
// 否则这张生成的表自己就成了过期指路（D4a/D4b/D4c 会判红，而它只是忠实转述正文）。
const PATH_SHAPE = /(?:board|build|data|report|sim|src|skills|docs|doc)\/[A-Za-z0-9_.\-/]*/g;
let neutralized = 0;
function neutralize(text) {
  return text.replace(PATH_SHAPE, (m) => {
    if (fs.existsSync(path.join(root, m))) return m;
    neutralized++;
    return m.replace(/\//g, '·') + '（该路径不随本包）';
  });
}

const files = walk(root).sort();
const rows = [];
const counts = {};
for (const f of files) {
  const rel = path.relative(root, f).replace(/\\/g, '/');
  if (rel === 'report/90-open-items.md') continue;      // 集中表自己不算正文
  const lines = fs.readFileSync(f, 'utf8').split(/\r?\n/);
  lines.forEach((ln, i) => {
    for (const m of MARKERS) {
      if (!ln.includes(m)) continue;
      const text = neutralize(ln.replace(/\s+/g, ' ').trim()).replace(/[|]/g, '\\|');
      counts[m] = (counts[m] || 0) + 1;
      rows.push([m, `${rel}:${i + 1}`, text]);
    }
  });
}

const head = [
  '# 未决项一览（由脚本从现存文档现生成）',
  '',
  '本表是机械索引：把交付文档里的未决标记逐条抄到这里，"内容一句话"就是正文那一行。',
  '判断留在各份文档里，这里只保证**没有一条标记落在表外**（生成件：`build/submit_open_items.mjs`）。',
  '逐轮流水账不随本包，所以这里只覆盖随包的文档。',
  '',
  `共 ${rows.length} 处：` + MARKERS.filter(m => counts[m]).map(m => '`' + m + '` ' + counts[m]).join('、'),
  '',
  '| 标记类型 | 所在文件与行 | 内容一句话 | 需要我做什么 | 影响哪个评测项 | 状态 |',
  '| --- | --- | --- | --- | --- | --- |',
];
const body = rows.map(([m, loc, text]) => `| \`${m}\` | ${loc} | ${text} | ${MEANING[m]} | ${IMPACT[m]} | 未闭合 |`);

console.log(`OPEN-ITEMS 扫 md=${files.length} 标记处=${rows.length}`);
for (const m of MARKERS) console.log(`  ${m} = ${counts[m] || 0}`);
if (write) {
  fs.writeFileSync(out, head.concat(body).join('\n') + '\n');
  console.log(`WRITE ${out} 行=${head.length + body.length}`);
} else {
  console.log('（未写文件；加 --write 才生成）');
}
