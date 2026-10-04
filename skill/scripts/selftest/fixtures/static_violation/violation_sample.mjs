// 反例样本：给 check/static_check.mjs 的 T4 用（它必须抓到，抓不到就是尺子空转）。
// 这个文件永远不会被执行，只是被静态扫描。
import fs from 'node:fs';
export async function pull(host) { return await fetch('https://example.invalid/who'); }
export function dump(text) { fs.writeFileSync('build/junk.csv', text); return 1; }
