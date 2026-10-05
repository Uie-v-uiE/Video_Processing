#!/usr/bin/env node
// build/r125_normalize_platform_json.mjs —— 把 Vitis 平台描述件里的本机绝对路径改写成仓库相对的
//
// 作用：把 Vitis 平台描述件里的本机绝对路径改写成仓库相对的（用途：交付形状归一化）
//
// 为什么单独一支：`board/vitis_platform/vitis-comp.json` 入库那一版把 `configuration.xsa`
// 写成 `build/system.xsa`；从 `vitis/platform` 整份复制过来会带出 `D:/…/build/system.xsa`。
// 这一步是交付形状的一部分，交给 `board/scripts/stage_vitis_platform.sh` 在复制之后立刻跑。
//
// 用法：node build/r125_normalize_platform_json.mjs <vitis-comp.json 的绝对路径>
// 判定：改成了打印 NORMALIZE，本来就对打印 already；文件里没有 xsa 字段则 REFUSE 并退 2（不静默放行）。
import fs from 'node:fs';

const p = process.argv[2];
if (!p) { console.log('REFUSE: 没给文件路径'); process.exit(2); }
if (!fs.existsSync(p)) { console.log(`REFUSE: 没有 ${p}`); process.exit(2); }
const txt = fs.readFileSync(p, 'utf8');
const re = /("xsa"\s*:\s*)"[^"]*"/;
if (!re.test(txt)) { console.log('REFUSE: 文件里找不到 "xsa" 字段，改写规则与这版平台对不上'); process.exit(2); }
const out = txt.replace(re, '$1"build/system.xsa"');
if (out !== txt) fs.writeFileSync(p, out);
console.log(out === txt ? 'NORMALIZE already' : 'NORMALIZE vitis-comp xsa=build/system.xsa');
