// build/r124_readme_clause_index.mjs —— 动作 A0 + A4：把 report/README.md 的导航表与赛题条款对上号
// 依赖：node（本机 v24.x）；以仓库根为当前工作目录；不联网、不调 Vivado/xsim，只读写仓库内的文本文件。
// 用法：node build/r124_readme_clause_index.mjs --check   （默认，只报每条规则的命中数，不写盘）
//       node build/r124_readme_clause_index.mjs --apply  （命中数与期望全对才写；任何一条不匹配就整批 REFUSE，不留半改状态）
// 参数：
//   | 参数 | 作用 |
//   | --- | --- |
//   | --check | 逐条打印命中数与不命中项，不写盘 |
//   | --apply | 全部命中才落盘，并打印每个文件的行数变化（行数只许增不减） |

// A0：§1 那张表本来就一行一格对着官方 §3.3.5.3 的七条，只是**没写条款号** ⇒ 评委照条款找会以为缺。
// A4：两份"只判断不动手"的判断件（`timing/eth_rxc_partition_options.md`、`timing/eth_tx_decoupling_inventory.md`）
//     在 §3 里没有一格 ⇒ 现在只有 `report/timing_global.md` 提到它们，翻目录才找得到。
import fs from 'node:fs';

const F = 'report/README.md';
const MODE = process.argv.includes('--apply') ? 'apply' : 'check';
const E = [
  ['| 选题背景与创新点：解决什么实际问题、前人做过什么 |', '| §3.3.5.3 第 1 条·选题背景与创新点：解决什么实际问题、前人做过什么 |', 1],
  ['| 设计原理与功能框图 |', '| §3.3.5.3 第 2 条·设计原理与功能框图 |', 1],
  ['| 软硬件划分依据与接口设计 |', '| §3.3.5.3 第 3 条·软硬件划分依据与接口设计 |', 1],
  ['| 优化过程，含优化前后的性能与资源对比 |', '| §3.3.5.3 第 4 条（也是 §3.3.4 第 1、2 条）·优化过程，含优化前后的性能与资源对比 |', 1],
  ['| 大模型协作记录：提示词、模型回答、自我纠错轨迹、智能体工作流 |', '| §3.3.5.2 与 §3.3.5.3 第 5 条·大模型协作记录：提示词、模型回答、自我纠错轨迹、智能体工作流 |', 1],
  ['| 技能包的提炼过程：从哪些失败总结、如何验证有效、边界在哪 |', '| §3.3.5.2 与 §3.3.5.3 第 6 条·技能包的提炼过程：从哪些失败总结、如何验证有效、边界在哪 |', 1],
  ['| 复现说明：他人可从零执行的步骤 |', '| §3.3.5.3 第 7 条（也是 §3.3.4 第 4 条）·复现说明：他人可从零执行的步骤 |', 1],
  ['| 失败分析：哪些场景仍然做不好、原因是什么 |', '| 失败分析（本仓库自加的一格，对应 §3.3.4 第 5 条"稳定性与可演示性"）：哪些场景仍然做不好、原因是什么 |', 1],
  // 表头说明：把这八行与条款的关系写在表前，而不是让读者猜行序
  ['## 1. 交付要回答的每一格 → 由哪份文件负责\n',
   '## 1. 交付要回答的每一格 → 由哪份文件负责\n\n' +
   '下面八行的**行序就是赛题 §3.3.5.3 那七条的顺序**（每条已把条款号写在第一格），最后一格是本仓库自加的。\n' +
   '这样排的目的只有一个：拿官方条款当检查表的人，逐条都能指到盘上一份文件，不需要在目录里翻。\n', 1],
  // A4：在"哪里还不行"那一节后面补一节"判断依据"
  ['### 大模型协作与技能包\n',
   '### 判断依据（只判断、不动手的那两件）\n\n' +
   '| 文档 | 它替谁把账算清楚 | 结论落在哪 |\n|---|---|---|\n' +
   '| `timing/eth_rxc_partition_options.md` | 收侧那条 0.739 ns 的 `eth_rxc` 路：还想买到余量，四条候选各值多少 | 四条逐一给判定（A 前提为假、B 要一整轮、C 先量才能判、D 不买余量但不补就是失实）；第 6 节把 D1 那一轮的逐时钟名册差分记成 `result=RED`（窗本身管用、代价在别的域），并说明为什么"没量过"不等于"到极限" |\n' +
   '| `timing/eth_tx_decoupling_inventory.md` | 发侧要不要从 125 MHz 域里独立出来：这是唯一还可能买到余量的结构性改法 | 前置清单 **35 条** RX↔TX 信号级跨域、其中 **33 条完全没有同步器** ⇒ 判定"这是一整轮，不是半轮"，收益**未量**，立案与否交回给人 |\n\n' +
   '§3.3.4 第 4 条要的是"判断依据看得见"。这两件没有写 RTL、没有跑构建，它们的用处是让下一轮不重复试错；\n' +
   '读它们时注意：每节末尾都写了"未量"，未量的地方没有被写成结论。\n\n' +
   '### 大模型协作与技能包\n', 1],
];

let bad = 0;
let text = fs.readFileSync(F, 'utf8');
const before = text.split(/\r?\n/).length;
for (const [old, neu, want] of E) {
  const n = text.split(old).length - 1;
  if (n !== want) { console.log(`MISS 命中=${n} 期望=${want} :: ${old.slice(0, 52).replace(/\n/g, '\\n')}`); bad++; continue; }
  text = text.split(old).join(neu);
  console.log(`OK   :: ${old.slice(0, 46).replace(/\n/g, '\\n')}`);
}
const after = text.split(/\r?\n/).length;
console.log(`规则 ${E.length} 条 不符=${bad} 行数 ${before}→${after}`);
if (bad) { console.log('REFUSE：有不命中，不写盘'); process.exit(1); }
if (MODE === 'check') { console.log('CHECK-ONLY（没写盘）'); process.exit(0); }
fs.writeFileSync(F, text);
console.log('APPLY DONE ' + F);
