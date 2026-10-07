#!/usr/bin/env node
// Prj/pro/tmpsub/review_patch.mjs —— 给本地复核件 REVIEW-20261007.md 打六处改口。
// 每条规则要求**恰好命中一次**：命中 0 次或 >1 次就整份不写（#465/#471 那一族的自我防护）。
import fs from 'node:fs';
const F = 'D:/Xilinx/Prj/Video_Processing/REVIEW-20261007.md';
let t = fs.readFileSync(F, 'utf8');
const before = t.split('\n').length;
const ops = [
  ['sd.mp4`（6.7 MB，盘上时间 2026-09-22',
   'sd.mp4`（**66 996 905 B ≈ 64 MiB**，盘上时间 2026-09-22'],
  ['README 目录导览的计数逐条现数：',
   'README 目录导览的计数逐条现数（`e805e6f` 那一版 18:3x 再数一遍，八格全不变：`src/rtl` .v 80／`sim` 顶层 .v 83／`tb_*.v` 82／`sim/prim` 2／`src/host` 26 .mjs + 3 .py／`SKILL.md` 49／`src/constraints` .xdc 9）：'],
  ['## 3. 这次查出来并改掉的十九条（',
   '## 3. 这次查出来并改掉的二十条（'],
  ['`MANIFEST.txt` 的目录对照里两层假话与一处漏说，并给导出器补一条',
   '`MANIFEST.txt` 的目录对照里两层假话与一处漏说，并给导出器补一条'],
  ['的自检）\n',
   '的自检；20 是 18:5x：`md2pdf_run.sh` 那句"重印过了"是假的——Edge 拿到相对路径时既不报错也不写文件，而判据读的是**旧产物**的字节数）\n'],
  ['## 4. 查出来但这次**不修**的四条代码注释债（理由写在下面）',
   '20. **`md2pdf_run.sh` 的"重印成功"是假绿，而 `host-guide.pdf` 已经落后源文档两笔**（18:5x 查到并当场修）。\n' +
   '   查法不是量 mtime，是**读 PDF 正文找记号**：`8eefc56`（17:17）把排错表那一格的 `--fps` 归属改成了\n' +
   '   "把**推流那支**的 `--fps` 降到 15（这一支 `health_read` 没有 `--fps`）"，而 `PDF/host-guide.pdf` 里\n' +
   '   pypdf 抽出来的正文含"推流那支"**0 次**、mtime 还停在 11:59 ⇒ 那份打印件是 `cadb49a`（11:58）那一版。\n' +
   '   第一次"重印"跑完打的是 `EDGE_RC=0 PDF字节=753067`——**与旧那份逐字节相同**（`md5sum` 两枚一样）：\n' +
   '   `--print-to-pdf=` 收的是相对路径，Edge 按它自己的 cwd 解，解不到就**什么都不做**、退出码仍是 0，\n' +
   '   而脚本下一行"PDF > 10 KB"读的是**上一版留下的那个文件** ⇒ 判据没牙。三条修法（已落进 `Prj/pro/md2pdf_run.sh`）：\n' +
   '   ① 入口把 `IN`/`OUT` 都绝对化（输出目录不存在直接 REFUSE）；② 跑前记 `md5`、跑后要求**摘要必须变**，\n' +
   '   没变就 `REFUSE 产物字节摘要没变 ⇒ Edge 其实没重写这一份，别念成"已重印"`（退出码 5，比"太小"更靠前）；\n' +
   '   ③ 中间 HTML 的名字跟着 PDF 输出走（`host-guide.pdf` ⇄ `host-guide.html`），不再跟着源文件名，\n' +
   '   免得一次重印在 `PDF/` 里长出第二种拼法（这次同时留下了 `host-guide.html` 与 `host_guide.html`）。\n' +
   '   重印后 `md5 650fd9179d8e → 5eb20d4d76de`、`PAGES=6 页面尺寸mm=209.9x297.0`、"推流那支"1 次、"19 条"1 次、\n' +
   '   `D:/Xilinx` 与 `D:\\Software` 各 0 次；旧那份没删，在 `Prj/pro/pkg_archive/host-guide_pre1850.pdf`。\n' +
   '   另一格顺带量正：`technical-document.pdf` 17:07 那份是**新的**（源 `report/technical-document.md` 最后一笔是 16:40 的 `d457b77`）。\n' +
   '   形状记下来：**"产物存在且够大"不等于"产物是这一跑写出来的"**——派生件要么比 md5/mtime，要么就读它的正文记号。\n' +
   '\n' +
   '## 4. 查出来但这次**不修**的四条代码注释债（理由写在下面）'],
  ['`host-guide.pdf` 与 11:58 那笔源码同步（含"19 条 lane"）',
   '`host-guide.pdf` 已在 18:59 重印、与 `8eefc56` 那笔同步（含"19 条"与"推流那支"；旧那份在 `Prj/pro/pkg_archive/host-guide_pre1850.pdf`，见 §3 第 20 条）'],
];
const counts = [];
for (const [a, b] of ops) {
  const n = t.split(a).length - 1;
  counts.push(n);
  if (n !== 1) { console.log('REFUSE 命中 ' + n + ' 次：' + a.slice(0, 40)); process.exit(1); }
  t = t.replace(a, b);
}
const after = t.split('\n').length;
if (after <= before) { console.log('REFUSE 结果没变长 ' + before + ' → ' + after); process.exit(2); }
fs.writeFileSync(F, t);
console.log('APPLIED ' + ops.length + ' 条，命中逐条=' + counts.join('/') + '；行数 ' + before + ' → ' + after);
