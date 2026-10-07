#!/usr/bin/env node
// 学习目录（docs/walkthrough/，不入库）里"改名波之前"的三种旧路径改到现役落点。
// 只动读者会照着打开的文件名，不动 _sources*.md / _progress.md 这类**当时的观察记录**
// （那里的 "ls skill/pitfalls 不存在" 是历史事实，改它等于伪造记录）。
// 用法：node doc_audit_20261005/fix_learn_paths.mjs --check | --apply
import fs from 'node:fs';
import path from 'node:path';

const ROOT = 'D:/Xilinx/Prj/pro/Video_Processing/';
const DIR = 'docs/walkthrough';
const SKIP = new Set(['_sources.md', '_sources_20261005.md', '_progress.md', '_STATUS_20261005.md']);
const files = fs.readdirSync(ROOT + DIR).filter(f => f.endsWith('.md') && !SKIP.has(f));

// ① report/ 层的小写化（只改**盘上确实存在小写版**的那些）
function lowerReport(txt) {
    let n = 0;
    const out = txt.replace(/report\/([A-Z][A-Za-z0-9_-]*)\.md/g, (m, base) => {
        const low = 'report/' + base.toLowerCase() + '.md';
        if (fs.existsSync(ROOT + low)) { n++; return low; }
        return m;
    });
    return [out, n];
}
// ② src/ps/ → src/host/ps/（同样只在目标存在时改）
function movePs(txt) {
    let n = 0;
    const out = txt.replace(/src\/ps\/([A-Za-z0-9_.-]+)/g, (m, f) => {
        if (fs.existsSync(ROOT + 'src/host/ps/' + f)) { n++; return 'src/host/ps/' + f; }
        return m;
    });
    return [out, n];
}
// ③ skill/ → skills/（技能包整目录改名；卡片现在住在 skills/<类别>/<条目>/SKILL.md，
//    所以只把**目录名**改对，具体卡片路径由人工逐条核（本脚本改完会列出仍查不到的 skills/ 串）
function moveSkill(txt) {
    let n = 0;
    const out = txt.replace(/(^|[^s])skill\/(?=[A-Za-z0-9_.-])/g, (m, p) => { n++; return p + 'skills/'; });
    return [out, n];
}
// ④ gates.sh 的身份行行号：改名波之后 :46 是注释，打三件 md5 的是 :50-52
const GATES_RULES = [
    ['build/gates.sh:46-49', 'build/gates.sh:50-52'],
    ['build/gates.sh:46', 'build/gates.sh:50'],
];

const mode = process.argv[2] === '--apply' ? 'apply' : 'check';
let tot = { r: 0, p: 0, s: 0, g: 0 };
for (const f of files) {
    const p = path.join(ROOT + DIR, f);
    let txt = fs.readFileSync(p, 'utf8'), hits = [], o, n;
    [o, n] = lowerReport(txt); if (n) hits.push(`report 小写 ${n}`); txt = o;
    [o, n] = movePs(txt); if (n) hits.push(`src/ps→src/host/ps ${n}`); txt = o;
    [o, n] = moveSkill(txt); if (n) hits.push(`skill→skills ${n}`); txt = o;
    for (const [a, b] of GATES_RULES) {
        const c = txt.split(a).length - 1;
        if (c) { txt = txt.split(a).join(b); hits.push(`${a}→${b} ${c}`); tot.g += c; }
    }
    if (hits.length) {
        console.log(`${f}: ${hits.join(' / ')}`);
        tot.r += 1;
        if (mode === 'apply') fs.writeFileSync(p, txt);
    }
}
// 复核：读者件里不该再有这三种旧写法
const resid = {};
for (const key of ['大写 report 名', 'src/ps/', 'skill/ 旧目录名']) resid[key] = 0;
for (const f of files) {
    const txt = fs.readFileSync(path.join(ROOT + DIR, f), 'utf8');
    resid['大写 report 名'] += (txt.match(/report\/[A-Z][A-Za-z0-9_-]*\.md/g) || []).length;
    resid['src/ps/'] += (txt.match(/src\/ps\//g) || []).length;
    resid['skill/ 旧目录名'] += (txt.match(/(^|[^s])skill\//g) || []).length;
}
console.log(`改了 ${tot.r} 份文件（${mode}）；残留：大写 report ${resid['大写 report 名']}｜src/ps ${resid['src/ps/']}｜skill/ ${resid['skill/ 旧目录名']}  ${resid['大写 report 名'] + resid['src/ps/'] + resid['skill/ 旧目录名'] === 0 || mode === 'check' ? 'PASS' : 'FAIL'}`);
