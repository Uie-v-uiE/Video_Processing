#!/usr/bin/env node
/**
 * interp_study.mjs —— 动手做硬件之前，先算清"插值在**本项目的几何区间**里到底值不值"。
 *
 * 动机（跑出来的，不是猜的）：`zoom_ctrl` 的 Q8 `inv_scale` 只在 256(=1.0x)..512(=0.5x)
 * 之间变，而缩放逆映射是 `sx = 256 + (x−256)·inv/256` ⇒ 小数位
 * `fx = ((x−256)·inv mod 256)/256`。于是 inv=256 与 inv=512 两处 **fx 恒为 0**，
 * 那两端双线性**逐像素等于最近邻**，一个像素都不会变好 —— 而 0.5x 恰是最糊的一端。
 * 旋转端相反：除 0/90/180/270 外每个像素都带小数 ⇒ 插值该有肉。
 * 两边都要用数字确认，别做完了才发现受益面搞错。
 *
 * 指标：同一映射位置上比三种取像素方式 vs "理想像"（解析图样做 4×4 面积超采样）：
 *   nearest —— 现状；bilinear —— 4 抽头加权；box2 —— 2×2 面积平均（另一种候选）。
 * 图样全是硬边缘（插值只在硬边缘上才有差别）。
 *
 *   node src/host/interp_study.mjs [--zstep 64] [--deg 5] [--sub 2]
 */
const arg = (n, d) => { const i = process.argv.indexOf('--' + n); return i < 0 ? d : process.argv[i + 1]; };
const ZSTEP = Number(arg('zstep', 64));
const DSTEP = Number(arg('deg', 5));
const SUB = Number(arg('sub', 2));            // 行方向抽样步长（控制运行时间）
const W = 512, H = 300, SS = 4;

// ---------- 解析图样：对**实数**坐标返回灰度 0..255 ----------
function patLine(x, y) {                      // 一族 45°平行细线：线宽 1px（垂直距离），间距 24
  const t = (x - y) / Math.SQRT2;
  const k = Math.round(t);
  return (Math.abs(t - k) <= 0.5 && (((k % 24) + 24) % 24) === 0) ? 255 : 0;
}
function patV(x, y) {                         // 竖线：每 32 列一条 1px 亮线（按实数距离判）
  const k = Math.round(x);
  return (Math.abs(x - k) <= 0.5 && (((k % 32) + 32) % 32) === 0) ? 255 : 0;
}
function patChecker(x, y) {                   // 2px 棋盘：奈奎斯特极限，最容易暴露采样错位
  return ((Math.floor(x / 2) + Math.floor(y / 2)) & 1) ? 232 : 24;
}
function patStep(x, y) { return x < 256 ? 0 : 255; }        // 一条竖直硬边
const PATS = [['45度平行细线', patLine], ['竖线栅格', patV], ['2px棋盘', patChecker], ['竖直硬边', patStep]];

function idealAt(sx, sy, pat) {               // 理想像 = 解析图样在 1x1 像素面积上的平均
  let s = 0;
  for (let j = 0; j < SS; j++) for (let i = 0; i < SS; i++)
    s += pat(sx + (i + 0.5) / SS, sy + (j + 0.5) / SS);
  return s / (SS * SS);
}
function makeSource(pat) {                    // 源栅格：图样先被"拍到"成 512x300 整数像素
  const a = new Float64Array(W * H);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) a[y * W + x] = Math.round(pat(x, y));
  return a;
}
const tl = (src, x, y) => src[Math.min(H - 1, Math.max(0, y)) * W + Math.min(W - 1, Math.max(0, x))];

function sample(kind, src, sx, sy, fx, fy) {
  const x0 = Math.floor(sx), y0 = Math.floor(sy);
  if (kind === 'nearest') return tl(src, x0, y0);
  const a = tl(src, x0, y0), b = tl(src, x0 + 1, y0);
  const c = tl(src, x0, y0 + 1), d = tl(src, x0 + 1, y0 + 1);
  if (kind === 'bilinear') return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy;
  return (a + b + c + d) * 0.25;              // box2
}
const KINDS = ['nearest', 'bilinear', 'box2'];

// ---------- 逆映射（与 RTL 同式，只是用浮点） ----------
function mapZoom(x, y, inv) {
  const sx = (x - 256) * inv / 256 + 256, sy = (y - 150) * inv / 256 + 150;
  return [sx, sy, sx - Math.floor(sx), sy - Math.floor(sy)];
}
function mapRot(x, y, deg, inv) {
  const t = deg * Math.PI / 180, c = Math.cos(t), si = Math.sin(t), k = inv / 256;
  const xp = x - 256, yp = 150 - y;
  const sx = (xp * c + yp * si) * k + 256, sy = 150 - (-xp * si + yp * c) * k;
  return [sx, sy, sx - Math.floor(sx), sy - Math.floor(sy)];
}
const fZoom = (x, y, a) => mapZoom(x, y, a);
const fR256 = (x, y, a) => mapRot(x, y, a, 256);
const fR365 = (x, y, a) => mapRot(x, y, a, 365);

function fxNonZero(mapf, a) {
  let nz = 0;
  for (let x = 0; x < W; x++) if (mapf(x, 150, a)[2] > 1e-9) nz++;
  return Math.round(100 * nz / W);
}

function evaluate(src, pat, mapf, a) {
  const err = { nearest: 0, bilinear: 0, box2: 0 };
  const mx = { nearest: 0, bilinear: 0, box2: 0 };
  let cnt = 0;
  for (let y = 24; y < H - 24; y += SUB) for (let x = 48; x < W - 48; x += 1) {
    const q = mapf(x, y, a), sx = q[0], sy = q[1], fx = q[2], fy = q[3];
    if (sx < 0 || sx >= W - 1 || sy < 0 || sy >= H - 1) continue;
    const ideal = idealAt(sx, sy, pat); cnt++;
    for (const k of KINDS) {
      const e = sample(k, src, sx, sy, fx, fy) - ideal;
      err[k] += e * e; const ae = Math.abs(e); if (ae > mx[k]) mx[k] = ae;
    }
  }
  const psnr = (v) => v <= 1e-12 ? 99 : Math.round(10 * Math.log10(255 * 255 / (v / cnt)) * 10) / 10;
  return { n: psnr(err.nearest), bi: psnr(err.bilinear), bx: psnr(err.box2),
           mn: Math.round(mx.nearest), mb: Math.round(mx.bilinear) };
}

function header(title) {
  console.log('\n' + title);
  console.log('    参数   fx!=0%     最近邻    双线性   双线性增益    2x2盒   盒增益      (PSNR dB)');
}
const row = (tag, pct, r) => console.log(
  tag.padStart(8) + String(pct).padStart(6) + '%' +
  String(r.n).padStart(9) + String(r.bi).padStart(9) + (r.bi - r.n).toFixed(1).padStart(11) +
  String(r.bx).padStart(8) + (r.bx - r.n).toFixed(1).padStart(9));

function main() {
  // ---- 自检：两张表都建立在"恒等映射回到原地"上，不成立就不要引用任何结论 ----
  const q = mapRot(300, 120, 0, 256), a = mapZoom(300, 120, 256);
  const okQ = Math.abs(q[0] - 300) < 1e-9 && Math.abs(q[1] - 120) < 1e-9 && q[2] < 1e-9 && q[3] < 1e-9;
  const okA = Math.abs(a[0] - 300) < 1e-9 && Math.abs(a[1] - 120) < 1e-9 && a[2] < 1e-9 && a[3] < 1e-9;
  console.log('自检 旋转(0deg, inv=256) 应回 (300,120) 且 fx=fy=0 -> (' +
              q[0].toFixed(2) + ',' + q[1].toFixed(2) + ', fx=' + q[2].toFixed(3) + ') ' + (okQ ? 'OK' : '<<< 不成立'));
  console.log('自检 缩放(inv=256)       应回 (300,120) 且 fx=fy=0 -> (' +
              a[0].toFixed(2) + ',' + a[1].toFixed(2) + ', fx=' + a[2].toFixed(3) + ') ' + (okA ? 'OK' : '<<< 不成立'));
  if (!okQ || !okA) { console.log('映射自检没过，后面所有表都不要引用。'); process.exit(1); }

  for (const [name, pat] of PATS) {
    const src = makeSource(pat);
    header('【缩放】图样 ' + name);
    for (let inv = 256; inv <= 512; inv += ZSTEP)
      row('inv=' + inv, fxNonZero(fZoom, inv), evaluate(src, pat, fZoom, inv));
    header('【旋转 inv=256（1.0x，纯旋转）】图样 ' + name);
    for (let deg = 0; deg <= 90; deg += DSTEP)
      row(deg + 'deg', fxNonZero(fR256, deg), evaluate(src, pat, fR256, deg));
    header('【旋转 inv=365（0.70x）】图样 ' + name);
    for (let deg = 0; deg <= 90; deg += Math.max(DSTEP, 15))
      row(deg + 'deg', fxNonZero(fR365, deg), evaluate(src, pat, fR365, deg));
  }
}
main();
