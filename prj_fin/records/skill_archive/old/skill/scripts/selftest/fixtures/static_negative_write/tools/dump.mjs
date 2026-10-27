// 往 build/ 写东西，而且没有 PROTECTED 守卫表。
import fs from 'node:fs';
export function go(t) { fs.writeFileSync('build/oops.csv', t); return 7; }
