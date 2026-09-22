#!/usr/bin/env node
// make_sd_video.mjs — 把任意视频转成开发板能直接顺序读的 512×300 RGB565 帧库
//
//   node src/host/make_sd_video.mjs --in D:/path/a.mp4 --out E: [--chunks 512] [--preview]
//
// 为什么是这种布局（都是为了 PS 端固件的简单与可验证）：
//   · 每帧 307200 B = 512*300*2，**行主序、小端 u16**，和上位机 UDP 推流的字节序完全一致
//     => 固件读到缓冲区后可以整块 memcpy 进 DDR bank，不需要任何转换。
//   · 文件名一律 8.3（VIDEO000.BIN / META.TXT）：FatFs 若未开 _USE_LFN，长文件名会读不到。
//   · 按 --chunks 帧切成多个文件：单文件小、顺序读友好，也避开 FAT32 的 4 GB 上限。
//   · META.TXT 是唯一需要解析的文件：宽高/帧字节数/总帧数/每块帧数/每块大小。
//   · 缩放用 force_original_aspect_ratio=increase + crop 居中裁切，保证几何不变形
//     （512:300 = 1.7067，和 16:9=1.7778 不同，直接 scale 会横向拉伸）。
//
// 校验：--preview 会把第 0 帧（和中间一帧）从 RGB565 反解成 PNG，
//       人眼直接看出「行序/字节序/裁切」对不对；不靠猜。
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

const W = 512, H = 300, PBPP = 2;                    // RGB565 = 2 B/像素
const FRAME_BYTES = W * H * PBPP;                    // 307200 B

function arg(name, dflt) {
  const i = process.argv.indexOf('--' + name);
  return i > 0 && process.argv[i + 1] ? process.argv[i + 1] : dflt;
}
const has = (name) => process.argv.includes('--' + name);

const inp = arg('in', 'D:/UserData/Downloads/upm.mp4');
const out = arg('out', './sd_stage');
const CHUNK = parseInt(arg('chunks', '512'), 10);
if (!fs.existsSync(inp)) { console.error('找不到输入视频: ' + inp); process.exit(1); }
fs.mkdirSync(out, { recursive: true });

function ffprobe() {
  const r = spawnSync('ffprobe', ['-v', 'error', '-select_streams', 'v:0',
    '-show_entries', 'stream=width,height,r_frame_rate,nb_frames',
    '-show_entries', 'format=duration', '-of', 'default=noprint_wrappers=1', inp],
    { encoding: 'utf8' });
  const o = {};
  for (const line of (r.stdout || '').split('\n')) {
    const k = line.indexOf('='); if (k < 0) continue;
    o[line.slice(0, k)] = line.slice(k + 1);
  }
  return o;
}

// 最小 PNG 写出（8bit RGB，无外部依赖）：IHDR + zlib(IDAT) + IEND
const CRC_T = (() => { const t = new Int32Array(256); for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1); t[n] = c; } return t; })();
function crc32(buf) { let c = ~0; for (const b of buf) c = (c >>> 8) ^ CRC_T[(c ^ b) & 0xFF]; return ~c >>> 0; }
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function writePng(file, w, h, rgb) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 3 + 1)] = 0;                                  // filter = None
    rgb.copy(raw, y * (w * 3 + 1) + 1, y * w * 3, (y + 1) * w * 3);
  }
  fs.writeFileSync(file, Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
    chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 6 })), chunk('IEND', Buffer.alloc(0)),
  ]));
}
// RGB565 小端 -> RGB888（MSB 复制扩展，与 split_display.v:45-47 同一套规则）
function rgb565to888(frame) {
  const o = Buffer.alloc(W * H * 3);
  for (let i = 0; i < W * H; i++) {
    const v = frame[i * 2] | (frame[i * 2 + 1] << 8);
    const r5 = (v >> 11) & 31, g6 = (v >> 5) & 63, b5 = v & 31;
    o[i * 3] = (r5 << 3) | (r5 >> 2);
    o[i * 3 + 1] = (g6 << 2) | (g6 >> 4);
    o[i * 3 + 2] = (b5 << 3) | (b5 >> 2);
  }
  return o;
}

const info = ffprobe();
const [num, den] = (info.r_frame_rate || '30/1').split('/').map(Number);
const fps = den ? (num / den) : 0;
const dur = parseFloat(info.duration || '0');
console.log(`[in] ${path.basename(inp)} ${info.width}x${info.height} ${fps.toFixed(2)}fps ${dur.toFixed(1)}s`);
console.log(`[out] ${out}  每帧 ${FRAME_BYTES} B，${CHUNK} 帧/文件`);

const vf = `scale=${W}:${H}:force_original_aspect_ratio=increase,crop=${W}:${H}`;
const ff = spawn('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-i', inp,
  '-vf', vf, '-pix_fmt', 'rgb565le', '-f', 'rawvideo', '-'], { stdio: ['ignore', 'pipe', 'inherit'] });

let pending = Buffer.alloc(0), frames = 0, fileIdx = 0, fd = null, inFile = 0;
const files = [];
function openNext() {
  const name = `VIDEO${String(fileIdx).padStart(3, '0')}.BIN`;
  files.push({ name, frames: 0, bytes: 0 });
  fd = fs.openSync(path.join(out, name), 'w');
  inFile = 0;
}
function closeCur() { if (fd !== null) { fs.closeSync(fd); fd = null; } }

function consume() {
  while (pending.length >= FRAME_BYTES) {
    const fr = pending.subarray(0, FRAME_BYTES);
    pending = pending.subarray(FRAME_BYTES);
    if (fd === null || inFile >= CHUNK) { closeCur(); openNext(); fileIdx++; }
    fs.writeSync(fd, fr);
    files[files.length - 1].frames++; files[files.length - 1].bytes += FRAME_BYTES;
    inFile++;
    frames++;
    if (has('preview') && (frames === 1 || frames === Math.max(1, Math.round(dur * fps / 2)))) {
      const png = path.join(out, `PREVIEW_F${String(frames).padStart(5, '0')}.PNG`);
      writePng(png, W, H, rgb565to888(fr));
      console.log(`[preview] ${path.basename(png)}`);
    }
    if (frames % 500 === 0) process.stdout.write(`  ${frames} 帧\r`);
  }
}
ff.stdout.on('data', (c) => { pending = Buffer.concat([pending, c]); consume(); });
ff.on('close', (code) => {
  closeCur();
  const tail = pending.length ? ` (尾部丢弃 ${pending.length} B，不足一帧)` : '';
  const meta = [
    `# RK-ZYNQ7020 SD 视频帧库（由 make_sd_video.mjs 生成，勿手工编辑）`,
    `FORMAT=RGB565LE_ROWMAJOR`,
    `WIDTH=${W}`, `HEIGHT=${H}`, `FRAME_BYTES=${FRAME_BYTES}`,
    `FRAMES=${frames}`, `FPS=${fps.toFixed(3)}`,
    `CHUNK_FRAMES=${CHUNK}`, `FILES=${files.length}`,
    `SOURCE=${path.basename(inp)}`,
    `SRC_WH=${info.width}x${info.height}`,
    `SCALE=${vf}`,
    ...files.map((f, i) => `FILE${i}=${f.name} FRAMES=${f.frames} BYTES=${f.bytes}`),
    ``,
  ].join('\n');
  fs.writeFileSync(path.join(out, 'META.TXT'), meta);
  console.log(`\n[done] ${frames} 帧 = ${(frames * FRAME_BYTES / 1048576).toFixed(1)} MiB，` +
    `${files.length} 个文件 + META.TXT${tail}`);
  if (code !== 0) console.log('ffmpeg 退出码 ' + code);
});
