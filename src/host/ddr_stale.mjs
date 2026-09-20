#!/usr/bin/env node
/**
 * ddr_stale.mjs — 解析 build_v6/_ddr_dump.out（ddr_verify.mjs 落的 JTAG 回读），
 * 把 --test frameid 图案（像素值 = 64bit字号 + 帧号）反解成「每个 16bit 字来自第几帧」，
 * 然后给出**丢字签名**，用来区分丢字发生在哪一级：
 *   · 丢字率对「包内字节偏移」强烈相关（包首好、包尾差）⇒ 下游**平均排空速率**跟不上
 *     （打包器/CDC 在每个包里被灌满，包间隔才排空 ⇒ 固定相位丢字）
 *   · 丢字集中在若干**连续地址长带** ⇒ 端口被长时间独占（显示拷贝窗口）
 *   · 半字(u32 内两个 16bit)不一致 ⇒ 丢在 16bit 粒度 = CDC 写侧门控
 *   · 整包(174 字)连续缺失 ⇒ 前端 udp_rx/reasm 丢包
 *
 * 用法：node host/ddr_stale.mjs [dumpFile]
 */
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { MEASURED, host, dump } from './repo_path.mjs';


const DUMP = process.argv[2] || path.join(MEASURED, 'ddr_dump.out');
const WORDS = 38400;            // 512x300 RGB565 / 8B
const LANES = WORDS * 4;        // 16bit 字个数
const PAYLOAD = 1392;           // 每包负载字节数
const BANDS = [[0, 48], [48, 96], [96, 192], [192, 384], [384, 768], [768, 1392]];

const txt = readFileSync(DUMP, 'latin1');
for (const seg of txt.split(/^BANK /m).slice(1)) {
  const head = seg.split('\n')[0].trim();
  const base = parseInt(head, 16);
  const u32 = new Uint32Array(LANES / 2);
  let lines = 0;
  for (const line of seg.split('\n')) {
    const m = /^([0-9A-Fa-f]{8}):\s+([0-9A-Fa-f]{8})/.exec(line.trim());
    if (!m) continue;
    const idx = (parseInt(m[1], 16) - base) >> 2;
    if (idx >= 0 && idx < u32.length) u32[idx] = parseInt(m[2], 16);
    lines++;
  }
  // 每个 16bit lane 的「值 - 所属 64bit 字号」= 帧号
  const fr = new Int32Array(LANES);
  for (let k = 0; k < LANES; k++) {
    const half = k & 1;
    fr[k] = (((u32[k >> 1] >>> (half ? 16 : 0)) & 0xffff) - (k >> 2)) & 0xffff;
  }
  const hist = new Map();
  for (let k = 0; k < LANES; k++) hist.set(fr[k], (hist.get(fr[k]) || 0) + 1);
  const top = [...hist.entries()].sort((a, b) => b[1] - a[1]).slice(0, 5);
  const NEW = top.length ? top[0][0] : -1;
  console.log(`\n=== BANK ${head}（${lines} 个 u32）===`);
  console.log('帧号占比 top5：' + top.map(([f, c]) => `#${f}:${(c * 100 / LANES).toFixed(1)}%`).join('  '));
  if (NEW < 0) { console.log('没有 frameid 图案：不是 frameid 测试，或帧根本没写进 DDR'); continue; }

  let u32mismatch = 0;
  for (let i = 0; i < u32.length; i++) if ((u32[i] & 0xffff) !== (u32[i] >>> 16)) u32mismatch++;
  console.log(`最新帧(#${NEW}) 16bit 命中率 ${(top[0][1] * 100 / LANES).toFixed(1)}%；` +
              `u32 内两个 16bit 不同帧的个数 ${u32mismatch}/${u32.length} ` +
              `(${(u32mismatch * 100 / u32.length).toFixed(1)}%)`);

  // 包内字节偏移分带丢字率
  const cells = BANDS.map(([a, b]) => ({ a, b, n: 0, bad: 0 }));
  for (let k = 0; k < LANES; k++) {
    const off = (k * 2) % PAYLOAD;                 // 该 16bit 字在包内的字节偏移
    const c = cells.find(x => off >= x.a && off < x.b);
    if (!c) continue;
    c.n++; if (fr[k] !== NEW) c.bad++;
  }
  console.log('包内字节偏移 → 丢字率（这一行是判据）：');
  console.log('  ' + cells.map(c => `${c.a}-${c.b}B:${(c.bad * 100 / c.n).toFixed(1)}%`).join('  '));

  // 连续丢字带（16bit 粒度）
  const runs = [];
  let s = -1;
  for (let k = 0; k <= LANES; k++) {
    const bad = k < LANES && fr[k] !== NEW;
    if (bad && s < 0) s = k;
    if (!bad && s >= 0) { runs.push(k - s); s = -1; }
  }
  runs.sort((a, b) => b - a);
  const n = runs.length || 1;
  const sum = runs.reduce((a, b) => a + b, 0);
  console.log(`连续丢字带：${n} 段，总 ${sum} 个 16bit 字，最长 ${runs[0] || 0}，` +
              `中位 ${runs[(n / 2) | 0] || 0}，≥696(整包) 的段数 ${runs.filter(r => r >= 696).length}`);
}
console.log('\n判读：' +
  '\n  · 「0-48B 很低、往后高」⇒ 排空速率跟不上（v6.3 之前的签名：打包器逐字等 B，20 MB/s 封顶）' +
  '\n  · 各带都低且总命中 ~100% ⇒ 入包链已无损' +
  '\n  · ≥696 字的长带成段 ⇒ 该窗口端口被完全占死 / 整包丢失' +
  '\n  · u32 内两个 16bit 不一致比例高 ⇒ 仍是 16bit 粒度丢（CDC 写侧门控）');
