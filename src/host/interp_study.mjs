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
 * 指标：同一映射位置上比五种取像素方式 vs "理想像"（解析图样在**源空间足迹 k×k** 上的面积平均，
 * k = inv/256；本项目只有缩小，所以足迹 ≥ 1×1）：
 *   nearest  现状 · bilinear 4 抽头加权 · hlerp 只用 fx（横向） · vlerp 只用 fy（纵向）
 *   hbox2 横向等权平均（一个加法，零乘法器） · box2 2×2 面积平均。
 *   hlerp/vlerp 的存在是为了回答"要不要为第二个读口冒险"：横向抽头落在同一个 64bit 字里＝免费，
 *   纵向要第二行＝要给读口提速。归因不清就不知道该付哪一笔代价。
 * 图样含单一方向（线/边）与各向同性（带限纹理）两类 —— 只对单方向图样说"纵向没收益"是不成立的。
 *
 *   node src/host/interp_study.mjs [--zstep 64] [--deg 5] [--sub 2]
 */
const arg = (n, d) => { const i = process.argv.indexOf('--' + n); return i < 0 ? d : process.argv[i + 1]; };
const ZSTEP = Number(arg('zstep', 64));
const DSTEP = Number(arg('deg', 5));
const SUB = Number(arg('sub', 2));            // 行方向抽样步长（控制运行时间）
const W = 512, H = 300;

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
// 前三种图样都只有**一个方向**：竖线 / 硬边沿 y 平移不变，45°线族沿自身方向不变。
// 对它们说"纵向插值没收益"是平凡的、不构成证据 —— 相机画面是各向同性的，
// 所以再加一个多方向多频率的和（λ 取 24/8/3 px，都在奈奎斯特以内，不是病理图样）。
const ISO = [];
for (let o = 0; o < 12; o++) for (const lam of [24, 8, 3])
  ISO.push([2 * Math.PI * Math.cos(o * Math.PI / 12) / lam,
            2 * Math.PI * Math.sin(o * Math.PI / 12) / lam]);
function patIso(x, y) {                                     // 各向同性带限纹理
  let s = 0;
  for (const [kx, ky] of ISO) s += Math.cos(kx * x + ky * y);
  return Math.round(128 + 120 * s / ISO.length);
}
const PATS = [['45度平行细线', patLine], ['竖线栅格', patV], ['2px棋盘', patChecker],
              ['竖直硬边', patStep], ['各向同性纹理', patIso]];

// 理想像：显示像素在**源空间**里占 k×k 面积（k = inv/256 ≥ 1，本项目只有缩小），
// 取该面积的平均。坐标约定必须和 makeSource 一致：`a[x] = pat(x)` ⇒ 源采样点就是整数坐标，
// 所以取样窗口以 (sx,sy) 为**中心**。早先版本按 [sx, sx+1] 积分，等于把理想像整体平移半个像素，
// 后果是"恒等映射 + 2×2 盒"能得满分 99 dB、而最近邻白白背了半像素的锅 —— 整张表都偏了。
function idealAt(sx, sy, pat, k) {
  const n = Math.max(4, Math.ceil(k * 4));    // 子采样密度随足迹放大，保持 ~0.5px 间距
  let s = 0;
  for (let j = 0; j < n; j++) for (let i = 0; i < n; i++)
    s += pat(sx - k / 2 + (i + 0.5) * k / n, sy - k / 2 + (j + 0.5) * k / n);
  return s / (n * n);
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
  // 只补一个方向，用来把增益归因到横 / 纵：
  //   hlerp 只用 fx —— 两个抽头落在同一个 64bit 字里，硬件**免费**
  //   vlerp 只用 fy —— 要第二行 ⇒ 需要 250 MHz 分时读口
  // 若 hlerp 已拿到大头，就不该为了 2D 去冒改读口/流水对齐的风险；反之必须做满。
  if (kind === 'hlerp') return a * (1 - fx) + b * fx;
  if (kind === 'vlerp') return a * (1 - fy) + c * fy;
  // hbox2 = 横向 1×2 **等权**平均：不要乘法器（一个加法 + 一个右移），
  // 抽头又落在同一个 64bit 字里 ⇒ 若它能吃掉 hlerp 的大部分收益，缩放端就有近乎零成本的方案。
  if (kind === 'hbox2') return (a + b) * 0.5;
  return (a + b + c + d) * 0.25;              // box2
}
const KINDS = ['nearest', 'bilinear', 'hlerp', 'vlerp', 'hbox2', 'box2'];

// ---------- 逆映射（与 RTL 同式，只是用浮点） ----------
// 返回 [sx, sy, fx, fy, k]，k = 源空间足迹边长 = inv/256
function mapZoom(x, y, inv) {
  const sx = (x - 256) * inv / 256 + 256, sy = (y - 150) * inv / 256 + 150;
  return [sx, sy, sx - Math.floor(sx), sy - Math.floor(sy), inv / 256];
}
function mapRot(x, y, deg, inv) {
  const t = deg * Math.PI / 180, c = Math.cos(t), si = Math.sin(t), k = inv / 256;
  const xp = x - 256, yp = 150 - y;
  const sx = (xp * c + yp * si) * k + 256, sy = 150 - (-xp * si + yp * c) * k;
  return [sx, sy, sx - Math.floor(sx), sy - Math.floor(sy), k];
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
  const err = {}, mx = {};
  for (const k of KINDS) { err[k] = 0; mx[k] = 0; }
  let cnt = 0;
  for (let y = 24; y < H - 24; y += SUB) for (let x = 48; x < W - 48; x += 1) {
    const q = mapf(x, y, a), sx = q[0], sy = q[1], fx = q[2], fy = q[3];
    if (sx < 0 || sx >= W - 1 || sy < 0 || sy >= H - 1) continue;
    const ideal = idealAt(sx, sy, pat, q[4]); cnt++;
    for (const k of KINDS) {
      const e = sample(k, src, sx, sy, fx, fy) - ideal;
      err[k] += e * e; const ae = Math.abs(e); if (ae > mx[k]) mx[k] = ae;
    }
  }
  const psnr = (v) => v <= 1e-12 ? 99 : Math.round(10 * Math.log10(255 * 255 / (v / cnt)) * 10) / 10;
  const r = { cnt };
  for (const k of KINDS) r[k] = psnr(err[k]);
  return r;
}

function header(title) {
  console.log('\n' + title);
  console.log('    参数   fx!=0%   最近邻  双线性  仅横向  仅纵向 横等权 2x2盒 | 双线性增益 横向占 纵向占   (PSNR dB)');
}
const row = (tag, pct, r) => {
  const gb = r.bilinear - r.nearest, gh = r.hlerp - r.nearest, gv = r.vlerp - r.nearest;
  const share = (g) => Math.abs(gb) < 0.05 ? '-' : (100 * g / gb).toFixed(0) + '%';
  console.log(tag.padStart(8) + String(pct).padStart(6) + '%' +
    String(r.nearest).padStart(8) + String(r.bilinear).padStart(8) +
    String(r.hlerp).padStart(8) + String(r.vlerp).padStart(8) +
    String(r.hbox2).padStart(8) + String(r.box2).padStart(8) + ' |' +
    gb.toFixed(1).padStart(10) + share(gh).padStart(7) + share(gv).padStart(7));
};

// ---------- 坐标约定锚点（这条表本身的正确性判据） ----------
// patIso 是带限图样（最短周期 3px），所以**恒等映射下最近邻必须几乎无误差**。
// 同时跑一遍"旧约定"（积分窗口取 [sx, sx+1]，等于整体平移半像素）当**反向对照**：
// 如果它也得高分，说明这条锚点没有牙，表里的数不可信。
function anchor() {
  const src = makeSource(patIso);
  const shifted = (sx, sy) => { let s = 0;
    for (let j = 0; j < 4; j++) for (let i = 0; i < 4; i++) s += patIso(sx + (i + 0.5) / 4, sy + (j + 0.5) / 4);
    return s / 16; };
  let e1 = 0, e2 = 0, n = 0;
  for (let y = 24; y < H - 24; y += 4) for (let x = 48; x < W - 48; x++) {
    const a = src[y * W + x], d1 = a - idealAt(x, y, patIso, 1), d2 = a - shifted(x, y);
    e1 += d1 * d1; e2 += d2 * d2; n++;
  }
  const p = (v) => v <= 1e-12 ? 99 : Math.round(10 * Math.log10(255 * 255 / (v / n)) * 10) / 10;
  return { ok: p(e1), bad: p(e2) };
}

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

  // ---- 锚点：带限图样在恒等映射下最近邻应几乎无误差，且半像素平移必须显著更差 ----
  const an = anchor();
  console.log('锚点 带限图样@恒等：中心约定 最近邻 PSNR=' + an.ok + ' dB（要求 ≥45），' +
              '旧约定/平移半像素 =' + an.bad + ' dB（要求比前者低 ≥10）');
  if (an.ok < 45) { console.log('<<< 中心约定不成立（恒等都有误差）——坐标约定错了，表不可用。'); process.exit(1); }
  if (an.ok - an.bad < 10) { console.log('<<< 锚点没有牙（错约定也得高分）——测量无分辨力，表不可用。'); process.exit(1); }
  console.log('锚点通过：坐标约定正确且测量对半像素错位敏感。');

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
