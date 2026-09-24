#!/usr/bin/env node
/*
 * card_preview.mjs —— 把 test_card 的像素转储渲染成 PNG。
 *
 * 为什么要有：图卡"好不好看"以前只有一轮完整构建 + 上板看屏幕才能回答（约 40 分钟）。
 * 这里用 RTL 仿真倒出来的像素（`sim/tb_v83_card_render.v` 产出的 card_dump.txt）直接出图，
 * 一分钟就能看到最终效果，**顺带把"颜色对不对"这类判读也提前**。
 *
 * 用法：node src/host/card_preview.mjs <card_dump.txt 路径> [输出前缀]
 *   产出 <前缀>_strip.png（几帧竖排，便于看运动）与 <前缀>_fN.png
 */
import fs from 'node:fs';
import zlib from 'node:zlib';

const src = process.argv[2];
const outPrefix = process.argv[3] || 'card';
if (!src || !fs.existsSync(src)) {
  console.error('用法：node src/host/card_preview.mjs <card_dump.txt> [前缀]');
  process.exit(2);
}

const W = 512, H = 300;
const frames = new Map();          // frame -> Uint8Array(W*H*3)
let maxX = 0, maxY = 0;
for (const line of fs.readFileSync(src, 'utf8').split('\n')) {
  if (!line) continue;
  const [f, x, y, r, g, b] = line.split(/\s+/).map(Number);
  if (!(x >= 0) || !(y >= 0) || Number.isNaN(r)) continue;
  if (!frames.has(f)) frames.set(f, new Uint8Array(W * H * 3));
  const p = (y * W + x) * 3;
  const buf = frames.get(f);
  buf[p] = r; buf[p + 1] = g; buf[p + 2] = b;
  if (x > maxX) maxX = x;
  if (y > maxY) maxY = y;
}

const ids = [...frames.keys()].sort((a, b) => a - b);
console.log(`[PREVIEW] 帧数 ${ids.length}，覆盖 x≤${maxX} y≤${maxY}`);

// 第一帧的 (0,0) 是流水线错拍留下的空洞（tb 只采"上一像素"），用邻居补上，别当成黑点
for (const id of ids) {
  const buf = frames.get(id);
  if (buf[0] === 0 && buf[1] === 0 && buf[2] === 0) {
    buf[0] = buf[W * 3]; buf[1] = buf[W * 3 + 1]; buf[2] = buf[W * 3 + 2];   // 取 (0,1)
  }
}

function png(width, height, rgb) {
  const raw = Buffer.alloc((width * 3 + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (width * 3 + 1)] = 0;                                 // filter: none
    rgb.copy ? rgb.copy(raw, y * (width * 3 + 1) + 1, y * width * 3, (y + 1) * width * 3)
             : Buffer.from(rgb.subarray(y * width * 3, (y + 1) * width * 3)).copy(raw, y * (width * 3 + 1) + 1);
  }
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(body) >>> 0);
    return Buffer.concat([len, body, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0); ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0)),
  ]);
}
let CRC_T = null;
function crc32(buf) {
  if (!CRC_T) {
    CRC_T = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      CRC_T[n] = c;
    }
  }
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = CRC_T[(c ^ buf[i]) & 0xFF] ^ (c >>> 8);
  return ~c;
}

for (const id of ids) {
  fs.writeFileSync(`${outPrefix}_f${id}.png`, png(W, H, Buffer.from(frames.get(id).buffer)));
}
const strip = Buffer.alloc(W * ids.length * H * 3);   // 竖排：每帧一条，看球与拖影怎么动
ids.forEach((id, i) => {
  const b = frames.get(id);
  for (let y = 0; y < H; y++) {
    Buffer.from(b.buffer, y * W * 3, W * 3)
      .copy(strip, (i * H * W + y * W) * 3);
  }
});
fs.writeFileSync(`${outPrefix}_strip.png`, png(W, H * ids.length, strip));
console.log(`[PREVIEW] 写了 ${outPrefix}_f*.png 与 ${outPrefix}_strip.png`);
