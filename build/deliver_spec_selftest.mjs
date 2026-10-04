// deliver_spec_selftest.mjs —— 交付要求检查器自己的测试（夹具 + 能红变异 + 未测分支）
//
// 为什么必须有：没有夹具就分不清"仓库不合格"与"检查器读不到东西"。
// 这里先证明**合规树能让全部判据绿**（正对照能动），再逐条构造坏输入，断言红的正是那一条。
// 用法：node build/deliver_spec_selftest.mjs
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const CHECKER = path.join(ROOT_DIR(), 'build', 'deliver_spec_check.mjs');
function ROOT_DIR() { return path.resolve(path.dirname(path.resolve(process.argv[1] || '.')), '..'); }

const HDR = '# 用途: 演示件  输入: 无  输出: 无  退出码: 0\n';
const TCLHDR = '# 作用: 演示  前置条件: 无  产出物: 无  关键参数: 无\n';
const FILES = {
  'README.md': [
    '<a href="README_EN.md">English</a>', '', '# 无极缩放视频处理', '',
    '## 项目简介', '',
    '数据流：上位机经 UDP 推流到 PS，PS 写入 DDR，PL 侧做缩放与处理，经 HDMI 输出，25 fps。', '',
    '- 1000M 实流量下 bad 计数为 0，drop_words 为 0',
    '- 主时钟 100 MHz，WNS 0.445 ns，TNS 0.000 ns，已收敛',
    '- 资源占用 LUT 62.1 %、FF 21.4 %、BRAM 96.9 %、DSP 12 个', '',
    '目录说明：',
    'src/ —— RTL、约束与上位机源码',
    'sim/ —— 关键链路仿真',
    'build/ —— 构建脚本与报告',
    'board/ —— 上板工程与实测输出',
    'data/ —— 测试数据与参考结果',
    'skills/ —— 可复用技能包',
    'report/ —— 设计报告与协作记录', '',
    '## 复现步骤', '',
    '环境：Vivado 2025.2.1，器件 xc7z020clg484-2，Node 24，Python 3.12。',
    '构建：vivado -mode batch -source build/build.tcl，产出 build/report/ 下的报告与比特流。',
    '上板与验证：运行 run_test.bat，预期屏幕显示测试图卡且 ping 往返 4 次全通。', '',
    '时序说明：主时钟 100 MHz，约束含 create_clock 与 I/O 窗，WNS 0.445 ns、TNS 0.000 ns，已收敛。',
  ].join('\n'),
  'README_EN.md': '<a href="README.md">中文</a>\n\n# Project\n\n## Overview\n\nData flows from host over UDP to PS, PL scales, HDMI outputs at 25 fps.\n\n## Reproduce\n\nVivado 2025.2.1, part xc7z020clg484-2, WNS 0.445 ns, TNS 0.000 ns.\n',
  'LICENSE': 'MIT License\n\nPermission is hereby granted, free of charge, to any person obtaining a copy.\n',
  'run_test.bat': '@echo off\r\nnode src/host/one_click_test.mjs\r\n',
  'run_test.sh': HDR + 'node src/host/one_click_test.mjs\n',
  'src/constraints/top.xdc': '# 用途: 引脚与时钟约束\ncreate_clock -period 10.000 -name clk [get_ports clk]\n',
  'src/rtl/top.v': '// 顶层\nmodule top; endmodule\n',
  'src/host/README.md': ['# 环境依赖', '', 'Node 24（无第三方包），Python 3.12（标准库）。', '', '# 使用方法', '', 'run_test.bat 或 node src/host/one_click_test.mjs。', '', '# 命令行语法', '', '| 参数名 | 含义 | 默认值 | 示例 |', '| --- | --- | --- | --- |', '| --host | 板卡地址 | 192.168.1.10 | --host 192.168.1.20 |'].join('\n'),
  'src/host/one_click_test.py': HDR + 'print("ok")\n',
  'src/host/one_click_test.mjs': HDR + 'console.log("ok");\n',
  'src/host/video_sender.py': HDR + 'print("send")\n',
  'src/host/video_sender.mjs': HDR + 'console.log("send");\n',
  'sim/tb_top.v': '// 功能: 被测模块 top，覆盖握手与溢出\n// 激励与检查: 复位 10 拍后灌 64 拍数据，期望 o_ok=1 且第 64 拍 o_vld=1\n// 预期结果: 通过时 RESULT PASS；失败时 o_ok 保持 0 并打印 FAIL\nmodule tb_top; endmodule\n',
  'sim/README.md': '| 文件 | 被测模块 | 功能 | 预期结果 |\n| --- | --- | --- | --- |\n| `tb_top.v` | top | 握手与溢出 | RESULT PASS |\n\n```bash\nxsim -R tb_top\n```\n',
  'build/create_project.tcl': TCLHDR + 'puts ok\n',
  'build/add_sources.tcl': TCLHDR + 'puts ok\n',
  'build/build.tcl': TCLHDR + 'puts ok\n',
  'build/synth.tcl': TCLHDR + 'puts ok\n',
  'build/impl.tcl': TCLHDR + 'puts ok\n',
  'build/report.tcl': TCLHDR + 'puts ok\n',
  'build/gen_bit.tcl': TCLHDR + 'puts ok\n',
  'build/README.md': '# 构建\n\n| 脚本名 | 作用 | 产出 |\n| --- | --- | --- |\n| create_project.tcl | 建工程 | .xpr |\n\n## 详细步骤\n\nvivado -mode batch -source build/build.tcl，耗时约 120 分钟。\n',
  'build/report/utilization.rpt': 'LUT 62.1%\nFF 21.4%\nBRAM 96.9%\nDSP 12\nIO 48\n',
  'build/report/timing_summary.rpt': 'WNS 0.445 TNS 0.000 Clock Summary 100.000 MHz\n',
  'board/flash.sh': HDR + 'echo flash\n',
  'board/output/board_verify.txt': 'RESULT PASS geom 10/0\n',
  'data/test_pattern.bin': 'pattern\n',
  'skills/README.md': '# 技能包\n\n## 适用范围\n\n大模型协作做 FPGA 开发的通用流程。\n\n## 使用方法\n\n按症状查索引取单条。\n\n## 失效条件\n\n工具版本差异使字段名变化时结论不可迁移。\n\n## 已验证的复用结果\n\n复用检查器判 14 项，红 0。\n',
  'report/design.md': '# 设计报告\n\n## 选题背景与创新点\n\n缩放与处理链路合并到一级流水。\n\n## 设计原理与功能框图\n\n框图见 report/figure.txt。\n\n## 软硬件划分与接口设计\n\nPS 负责协议与调度，PL 负责逐像素运算，接口为 AXI Lite 与 FIFO。\n\n## 优化前后性能与资源对比\n\n优化前 WNS 0.192 ns，优化后 0.445 ns。\n\n## 失败分析\n\n一次复制驱动改动令别域余量下降，判负回退。\n\n## 复现说明\n\n执行 build/build.tcl 后比对 build/report/ 的报告。\n',
  'report/collab.md': '# 大模型协作记录\n\n提示词、模型回答、自我纠错轨迹逐条留档。\n',
  'report/figure.txt': 'frame: PS -> PL -> HDMI\n',
};

function build(root, extra = {}, del = []) {
  fs.rmSync(root, { recursive: true, force: true });
  fs.mkdirSync(root, { recursive: true });
  const all = { ...FILES, ...extra };
  for (const d of del) delete all[d];
  for (const [rel, body] of Object.entries(all)) {
    const p = path.join(root, rel);
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, body);
  }
  fs.writeFileSync(path.join(root, '.files'), Object.keys(all).join('\n') + '\n');
  return root;
}
function run(root) {
  const list = path.join(root, '.files');
  if (!fs.existsSync(list)) { console.log(`DBG 清单不在盘上 ${list} FAIL`); }
  let out = '';
  try { out = execFileSync(process.execPath, [CHECKER, root, `--files=${list}`], { encoding: 'utf8', cwd: root }); }
  catch (e) { out = String(e.stdout || ''); }
  const rows = out.split(/\r?\n/).filter(l => /^C\d/.test(l));
  const fails = rows.filter(l => / FAIL$/.test(l)).map(l => l.split(' ')[0]);
  const nms = rows.filter(l => / NOT_MEASURED$/.test(l)).map(l => l.split(' ')[0]);
  return { fails, nms, text: out };
}

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'delivspec-'));
const out = [];
let bad = 0;
// ① 正对照：合规树必须全绿（红=0 且 未测=0）
const g = run(build(root));
const green = g.fails.length === 0 && g.nms.length === 0;
if (!green) bad++;
out.push(`R1 合规树全绿(正对照能动) 红=[${g.fails.join(',')}] 未测=[${g.nms.join(',')}] ${green ? 'PASS' : 'FAIL'}`);
if (!green) console.log(g.text);
// ② 每条变异只该红指定那一条（一个根因带连带时列出来，不削弱判据）
const MUT = [
  ['M1 大写目录名 src/RTL/top.v', { 'src/RTL/top.v': '// x\n' }, [], ['C0-3']],
  ['M2 多一个顶层目录 tools/', { 'tools/x.py': HDR + 'print(1)\n' }, [], ['C0-4']],
  ['M3 一键测试缺 Python 侧', {}, ['src/host/one_click_test.py'], ['C1-3']],
  ['M4 sim 里有非 .v 件', { 'sim/notes.txt': 'x\n' }, [], ['C2-1']],
  ['M5 报告里出现自称', { 'report/design.md': FILES['report/design.md'] + '\n我们做了取舍。\n' }, [], ['C7']],
  ['M6 build/report.txt 只剩一份报告', {}, ['build/report/timing_summary.rpt'], ['C4']],
];
for (const [name, extra, del, expect] of MUT) {
  const r = run(build(root, extra, del));
  const okSet = JSON.stringify(r.fails.slice().sort()) === JSON.stringify(expect.slice().sort());
  if (!okSet) bad++;
  out.push(`R2 ${name} 期望红=${expect.join(',')} 实红=${r.fails.join(',') || '无'} ${okSet ? 'PASS' : 'FAIL'}`);
}
// ③ 未测分支：文件缺失要落 NOT_MEASURED，不许念成通过
const u = run(build(root, {}, ['src/host/README.md']));
const nmOk = u.nms.includes('C1-4') && !u.fails.includes('C1-4');
if (!nmOk) bad++;
out.push(`R3 缺 src/host/README 落未测 未测=[${u.nms.join(',')}] 红=[${u.fails.join(',')}] ${nmOk ? 'PASS' : 'FAIL'}`);
// ④ 夹具形状自检：文件数与 .v 数要大于 0（防止夹具自己空转）
const shapeOk = Object.keys(FILES).length >= 25 && Object.keys(FILES).filter(k => k.endsWith('.v') && k.startsWith('sim/')).length >= 1;
if (!shapeOk) bad++;
out.push(`R4 夹具形状 文件=${Object.keys(FILES).length} sim/.v=${Object.keys(FILES).filter(k => k.startsWith('sim/') && k.endsWith('.v')).length} ${shapeOk ? 'PASS' : 'FAIL'}`);
for (const l of out) console.log(l);
console.log(`SPEC-SELFTEST 判 ${out.length} 项 不符=${bad} ${bad ? 'FAIL' : 'PASS'}`);
fs.rmSync(root, { recursive: true, force: true });
process.exit(bad ? 1 : 0);
