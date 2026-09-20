#!/usr/bin/env node
/**
 * ddr_holemap.mjs — 分析 host/ddr_verify.mjs 落盘的 DDR 转储
 * (build_v6/_ddr_dump.out)，把「哪些 16bit lane 没落位」的分布结构打出来：
 *   · 连续好/坏的游程长度
 *   · 坏点相对于 1392B 包边界的位置
 * 用来区分「FIFO 溢出成段丢」与「每包边界结构性丢」。
 *
 *   node ddr_holemap.mjs [--bank 10000000] [--payload 1392]
 */
import path from 'node:path';
import { readFileSync } from 'node:fs';

function get(n, d) {
  const i = process.argv.indexOf('--' + n);
  if (i < 0) return d;
  const v = process.argv[i + 1];
  return v && !v.startsWith('--') ? v : true;
}
const BASE = parseInt(String(get('bank', '10000000')), 16);
const PAYLOAD = Number(get('payload', 1392));

const text = readFileSync(process.argv[2] || path.join(MEASURED, 'ddr_dump.out'), 'utf8')
  .replace(/\r\n/g, '\n');
const seg = text.split(`BANK ${BASE.toString(16)}\n`)[1] || '';
const cut = /\nBANK [0-9a-f]+/.test(seg) ? seg.split(/\nBANK [0-9a-f]+/)[0] : seg;

const lanes = new Uint8Array(307200 / 2);   // 每个 16bit lane: 1=正确 0=错
const re = /^\s*([0-9a-fA-F]{8}):\s+([0-9a-fA-F]{8})\s*$/;
let n = 0;
for (const line of cut.split('\n')) {
  const m = re.exec(line);
  if (!m) continue;
  const addr = parseInt(m[1], 16), val = parseInt(m[2], 16);
  const u = (addr - BASE) >> 2;             // 32bit index
  if (u < 0 || u >= lanes.length / 2) continue;
  const w = (u >> 1) & 0xffff;
  const lo = val & 0xffff, hi = (val >> 16) & 0xffff;
  lanes[u * 2] = lo === w ? 1 : 0;
  lanes[u * 2 + 1] = hi === w ? 1 : 0;
  n++;
}
const total = lanes.length;
let good = 0, badRun = 0, badRuns = [], runStart = -1, curRun = 0;
for (let i = 0; i < total; i++) {
  if (lanes[i]) { good++; if (curRun) { badRuns.push(curRun); curRun = 0; } }
  else { badRun++; curRun++; }
}
if (curRun) badRuns.push(curRun);

console.log(`[MAP] bank=0x${BASE.toString(16)} u32=${n} lanes_good=${good}/${total} ` +
            `(${(100 * good / total).toFixed(1)}%)`);

const hist = new Map();
for (const r of badRuns) hist.set(r, (hist.get(r) || 0) + 1);
const hs = [...hist.entries()].sort((a, b) => b[1] - a[1]).slice(0, 10);
console.log('[MAP] bad-run length histogram (top10): ' +
            hs.map(([k, v]) => `${k}x${v}`).join(' '));
const longest = badRuns.length ? Math.max(...badRuns) : 0;
console.log(`[MAP] bad runs=${badRuns.length} longest=${longest} lanes ` +
            `(=${(longest * 2 / PAYLOAD * 100).toFixed(1)}% of a packet)`);

// 坏 lane 在包内的位置分布：16 个桶
const buckets = new Array(16).fill(0), bucketAll = new Array(16).fill(0);
for (let i = 0; i < total; i++) {
  const b = Math.floor((i % (PAYLOAD / 2)) / (PAYLOAD / 2 / 16));
  bucketAll[b]++;
  if (!lanes[i]) buckets[b]++;
}
console.log('[MAP] bad fraction by intra-packet position (16 buckets, packet=' +
            `${PAYLOAD}B): ` + buckets.map((c, b) => `${(100 * c / bucketAll[b]).toFixed(0)}%`).join(' '));
