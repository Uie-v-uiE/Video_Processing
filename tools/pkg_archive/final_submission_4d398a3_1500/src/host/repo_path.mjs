// repo_path.cjs — 仓库内工具脚本的统一路径解析（禁止写死绝对路径）。
// 目录约定：
//   ROOT     仓库根（本文件在 <repo>/src/host/）
//   HOST     <repo>/src/host
//   MEASURED <repo>/data/measured —— JTAG 回读落盘、实测输出都放这里
import { fileURLToPath } from 'node:url';
import { mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';

export const ROOT = fileURLToPath(new URL('../../', import.meta.url));
export const HOST = join(ROOT, 'src', 'host');
export const MEASURED = join(ROOT, 'data', 'measured');
mkdirSync(MEASURED, { recursive: true });
export const DUMP = join(MEASURED, 'ddr_dump.out');
export const host = (f) => join(HOST, f);
export const dump = (f) => join(MEASURED, f);
