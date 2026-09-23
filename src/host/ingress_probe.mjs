#!/usr/bin/env node
/**
 * ingress_probe.mjs — 定位「UDP→reasm→CDC→packer→AXI→DDR」在哪一级丢字。
 *
 * 做法：只发 K 个包（图案 = 每像素 (字号 + 固定帧号 N)，N 取一个没用过的值），
 * 等 1 s 让板端排空，然后用 JTAG 把前 K*174 个 64bit 字读回来，统计：
 *   · 落位率（等于本探针帧号的 lane 占比）
 *   · 从第几个字开始丢（=> 直接暴露缓冲深度/临界点）
 *   · 丢失是「连续尾部」还是「散布」
 *
 * 用法：node host/ingress_probe.mjs [--packets 8] [--pace 15] [--tag 200]
 */
import { execSync } from 'node:child_process';
import { writeFileSync, readFileSync, unlinkSync } from 'node:fs';
import { dump } from './repo_path.mjs';

const W = 512, H = 300, FRAME_BYTES = W * H * 2, HDR = 4, MTU = 1392;
const WORDS64 = FRAME_BYTES / 8;                 // 38400
const BANK = 0x10000000;
const XSDB = String(get('xsdb', 'D:\\Software\\Vivado\\2025.2.1\\Vitis\\bin\\xsdb.bat'));

function get(n, d) {
  const i = process.argv.indexOf('--' + n);
  if (i < 0) return d;
  const v = process.argv[i + 1];
  return v && !v.startsWith('--') ? v : true;
}
const K = Number(get('packets', 8));
const PACE = Number(get('pace', 15));            // MB/s，包间隔
const TAG = Number(get('tag', 200)) & 0xffff;    // 本探针的“帧号”

const buf = Buffer.alloc(FRAME_BYTES);
for (let w = 0; w < WORDS64; w++) {
  const v = (w + TAG) & 0xffff, o = w * 8;
  buf.writeUInt16LE(v, o); buf.writeUInt16LE(v, o + 2);
  buf.writeUInt16LE(v, o + 4); buf.writeUInt16LE(v, o + 6);
}

// --dry：只算不发不读。这台探针真跑时会 `rst -processor`（把 PS 应用复位），
// 而在一次 SD 传输中间复位会把 SDio 控制器留在未完成传输里（ISSUES #50 的次生现象）。
if (get('dry', false) === true) {
  const nU32 = K * (MTU / 4);
  console.log(`[PROBE] dry：将发 ${K} 包 = ${K * MTU} B @${PACE} MB/s，tag=${TAG}；`
            + `读回 0x10000000 / 0x10080000 各 ${nU32} 个 u32`);
  console.log('[PROBE] dry：不发包、不碰 JTAG');
  process.exit(0);
}
const dgram = (await import('node:dgram')).default;
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const sock = dgram.createSocket('udp4');
sock.on('error', (e) => console.log('[PROBE] sock error: ' + e.message));
await new Promise((res) => sock.bind({ address: '192.168.1.100', port: 0 }, res));
await sleep(80);                                 // 让绑定真正生效再发

const _sab = new Int32Array(new SharedArrayBuffer(4));
const nap = (ms) => Atomics.wait(_sab, 0, 0, ms);
const gapMs = (MTU / (PACE * 1e6)) * 1000;       // 包间隔（毫秒）
for (let i = 0; i < K; i++) {
  const off = i * MTU;
  const chunk = buf.subarray(off, Math.min(off + MTU, FRAME_BYTES));
  const p = Buffer.allocUnsafe(chunk.length + HDR);
  p.writeUInt32LE(off, 0); chunk.copy(p, HDR);
  sock.send(p, 0, p.length, 5001, '192.168.1.10');
  // 必须让事件循环真正跑起来，否则 sendto 只是排队、还没交给内核
  if (gapMs >= 0.5) await sleep(gapMs); else await sleep(0);
}
await sleep(1500);                               // 等内核把队列发完
sock.close();
console.log(`[PROBE] sent ${K} packets (${K * MTU} B) tag=${TAG} pace=${PACE} MB/s`);

// ---- JTAG 回读两个 bank 的前 K*174 个 64bit 字 ----
const nU32 = K * (MTU / 4);
for (const BANKX of [0x10000000, 0x10080000]) {
  const lines = [
    'catch {connect -host localhost -port 3121}',
    'targets -set -filter {name =~ "*#0"}',
    'catch {rst -processor}',
  ];
  for (let o = 0; o < nU32; o += 1000) {
    lines.push(`puts [mrd -force 0x${(BANKX + o * 4).toString(16)} ${Math.min(1000, nU32 - o)}]`);
  }
  lines.push('', '');
  const tmp = dump('_probe.tcl'), out = dump('_probe.out');
  writeFileSync(tmp, lines.join('\n'));
  try {
    execSync(`"${XSDB}" ${tmp} > "${out}" 2>&1`, { windowsVerbatimArguments: true, timeout: 300000 });
  } catch (e) { console.log('[PROBE] xsdb failed: ' + String(e.message).slice(0, 120)); }
  unlinkSync(tmp);

  const txt = readFileSync(out, 'utf8').replace(/\r\n/g, '\n');
  const re = /^\s*([0-9a-fA-F]{8}):\s+([0-9a-fA-F]{8})\s*$/;
  let hit = 0, tot = 0, firstMiss = -1, missList = [];
  for (const line of txt.split('\n')) {
    const m = re.exec(line);
    if (!m) continue;
    const addr = parseInt(m[1], 16), val = parseInt(m[2], 16);
    const u = (addr - BANKX) >> 2;
    if (u < 0 || u >= nU32) continue;
    const w64 = u >> 1, want = (w64 + TAG) & 0xffff;
    for (const lane of [val & 0xffff, (val >>> 16) & 0xffff]) {
      tot++;
      if (lane === want) hit++;
      else { if (firstMiss < 0) firstMiss = w64; missList.push(w64); }
    }
  }
  const uniqMiss = [...new Set(missList)].sort((a, b) => a - b);
  console.log(`[PROBE] bank 0x${BANKX.toString(16)}: lanes hit=${hit}/${tot} ` +
              `(${(100 * hit / Math.max(tot, 1)).toFixed(1)}%)`);
  if (hit < tot) {
    console.log(`         first missing word=${firstMiss} (byte ${firstMiss * 8}, ` +
                `packet ${(firstMiss * 8 / MTU).toFixed(2)})  distinct missing=${uniqMiss.length}`);
    if (uniqMiss.length > 1) {
      const gaps = new Map();
      for (let i = 1; i < uniqMiss.length; i++) {
        const d = uniqMiss[i] - uniqMiss[i - 1];
        gaps.set(d, (gaps.get(d) || 0) + 1);
      }
      console.log('         spacing(top6): ' + [...gaps.entries()].sort((a, b) => b[1] - a[1])
                  .slice(0, 6).map(([k, v]) => `${k}:${v}`).join(' '));
    }
  }
}
