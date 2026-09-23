#!/usr/bin/env node
/**
 * metrics.mjs —— 一条命令做完"推流 N 秒 → 读回硬件计数器 → 算成指标"，并把原始读数一起存档。
 *
 * 用法：
 *   node src/host/metrics.mjs --fps 30 --seconds 20 [--drop-every 0] [--tag r32] [--out board/evidence_r32]
 *   node src/host/metrics.mjs --selftest                 不打板子，验算式本身
 *
 * 为什么要这么一条命令（而不是手敲两遍 health_read）：
 *   ① 指标必须**可复跑**，评委拿到仓库能自己跑出一样的数；
 *   ② 采集与计算分不开就会出错 —— 本工具的第一版就把"平均帧间隔"的分母写成帧数，
 *      而硬件里 `gap_sum` 是 **N−1 段**（第一帧只建基准），于是 fps 被低估约 1/N；
 *      这条现在由 `--selftest` 钉住（判据与踩坑见 skill/metrics_gap_sum.md）；
 *   ③ 原始 JSON 与算出来的表一起入库，任何结论都能回查到最初那几个数。
 *
 * 数据来源（不加任何硬件）：`link_monitor` 的 10 条快照 lane + lane31 的时基标志，
 * 经 `health_read.mjs --json` 从 AXI GPIO 读回。基线用 `--gapclr` 把**帧间隔统计**归零，
 * 其余计数器是"自启动以来"的，所以全部按差值算。
 */
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));

function get(name, def) {
  const i = process.argv.indexOf('--' + name);
  if (i < 0) return def;
  const nxt = process.argv[i + 1];
  return nxt && !nxt.startsWith('--') ? nxt : true;
}

const FRAME_BYTES = 307200;          // 512×300 RGB565，与 system_top 的分辨率一致

/**
 * 把前后两次快照算成指标。
 * b = 基线（gapclr 之后），a = 推流结束后；wall_s = 推流真实耗时（秒）。
 * 只认差值：lane0/1/2/6/8/9 是自启动以来的累计量，lane3/4/5 已被 gapclr 归零。
 */
export function compute(b, a, wall_s, frames_sent) {
  const d = (k) => (a[k] - b[k]);
  const frames_recv = d('bytes') / FRAME_BYTES;              // 交付的完整载荷字节 → 帧
  // 分母不能是 frames_recv：**被验收门作废的帧照样交付字节**，但硬件的 gap_sum 只累加
  // 真正被接收的那些帧的间隔。干净推流时两者相等（frames_bad=0），一旦有丢包就会算出
  // 一个"平均间隔小于最小间隔"的荒谬数（2026-09-24 用 --drop-every 200 实测撞上：
  // 597 帧全部作废，工具却报 avg=22.4 ms / 44.7 fps，而 gap_min 是 6667 ms）。
  // 所以先扣掉作废的：接收帧数 = 交付帧数 − 作废帧数。
  const frames_ok = frames_recv - d('frames_bad');
  // gap_sum 是 **N−1 段** 间隔之和（第一帧只建立基准，量不出间隔）—— 分母必须是段数
  const segs = Math.max(0, Math.round(frames_ok) - 1);
  const avg_gap_ms = segs > 0 ? d('gap_sum') / segs : NaN;
  const fps_from_gap = avg_gap_ms > 0 ? 1000 / avg_gap_ms : NaN;
  // 自相矛盾检查（这条是救过我的）：平均间隔必然落在 [min, max] 里。
  // 第一次跑 --drop-every 200 时打出来 avg=22.39 ms 而 gap_min=6667 ms —— 平均值小于最小值
  // 在算术上不可能 ⇒ 分母/分子口径错了（当时分母用了"交付帧数"，而硬件只记被接收的帧）。
  // 现在直接把矛盾印出来，而不是等人肉眼发现。
  const impossible = segs > 0 && Number.isFinite(avg_gap_ms) &&
    ((a.gap_min > 0 && avg_gap_ms < a.gap_min - 1) || (a.gap_max > 0 && avg_gap_ms > a.gap_max + 1));
  if (impossible)
    console.log(`[M][自相矛盾] 平均间隔 ${avg_gap_ms.toFixed(2)} ms 不在 [${a.gap_min}, ${a.gap_max}] 之内 ⇒ `
      + `分母（段数 ${segs}）与 gap_sum 不是同一总体，这张表不能用`);
  return {
    drop_words: d('drop_words'),
    frames_bad: d('frames_bad'),
    pkt_err: d('pkt_err'),
    cdc_episodes: d('cdc_episodes'),
    // rows_miss_max 是终身保持的（gapclr 不清它），所以只能取前后较大值，不能算差值
    rows_miss_max: Math.max(a.rows_miss_max | 0, b.rows_miss_max | 0),
    pkts_delta: d('pkts'),
    bytes_delta: d('bytes'),
    frames_sent,
    frames_recv,
    frames_ok,                 // 真正被接收的帧（作废的已扣掉）= gap_sum 的分母来源
    gap_min_ms: a.gap_min,
    gap_max_ms: a.gap_max,
    gap_sum_ms: d('gap_sum'),
    gap_segments: segs,
    avg_gap_ms,
    fps_from_gap,
    fps_wall: frames_recv / wall_s,
    gap_avg_impossible: impossible,   // true ⇒ 这张表的时延指标作废
    hb_slow_a: a.hb_slow, hb_gone_a: a.hb_gone,
    stream_live_a: a.flags_bits.stream_live,
    // 判据：一个字都没丢 = drop_words 增量为 0 且 CDC 从未灌满
    verdict_no_word_lost: d('drop_words') === 0 && d('cdc_episodes') === 0,
  };
}

function readHealth(extra) {
  const out = execFileSync('node', [join(HERE, 'health_read.mjs'), '--json', ...extra],
                           { encoding: 'utf8', maxBuffer: 1 << 22 });
  const line = out.trim().split('\n').filter((l) => l.trim().startsWith('{')).pop();
  if (!line) throw new Error('health_read 没吐出 JSON：' + out.slice(0, 200));
  return JSON.parse(line);
}

// ---------------------------------------------------------------- selftest
if (get('selftest', false) === true) {
  let bad = 0;
  const t = (name, cond, info) => {
    if (!cond) { bad++; console.log('FAIL ' + name + (info ? '  ' + info : '')); }
    else console.log('PASS ' + name);
  };
  const mk = (o) => Object.assign({
    drop_words: 0, frames_bad: 0, pkt_err: 0, cdc_episodes: 0, rows_miss_max: 0,
    pkts: 0, bytes: 0, gap_min: 0, gap_max: 0, gap_sum: 0, hb_slow: 0, hb_gone: 0,
    flags_bits: { stream_live: '0' },
  }, o);

  // 30 帧、每帧 307200 B：收满 9,216,000 B；间隔统计 29 段 × 33 ms = 957 ms
  const b = mk({});
  const a = mk({ pkts: 30 * 221, bytes: 30 * FRAME_BYTES, gap_sum: 957, gap_min: 32, gap_max: 35 });
  const r = compute(b, a, 1.0, 30);
  t('帧数按载荷字节算 = 30', Math.abs(r.frames_recv - 30) < 1e-9, JSON.stringify(r.frames_recv));
  t('gap_sum 的分母是段数 N−1（=29）', r.gap_segments === 29 && Math.abs(r.avg_gap_ms - 957 / 29) < 1e-9,
    `avg=${r.avg_gap_ms}`);
  t('由间隔推出的 fps ≈ 30', Math.abs(r.fps_from_gap - 1000 / (957 / 29)) < 1e-6);
  t('墙钟 fps 用真实耗时', Math.abs(r.fps_wall - 30) < 1e-9);
  t('没丢字判据成立', r.verdict_no_word_lost === true);
  t('丢 3 个字时判据必须翻红', compute(b, mk({ bytes: 30 * FRAME_BYTES, drop_words: 3 }), 1, 30)
        .verdict_no_word_lost === false);
  // 反面对照：如果分母错用 N（30），avg 会变小、fps 会偏高 —— 这条钉住"曾经算错的那一版"
  const wrong = 1000 / (957 / 30);
  t('错用 N 作分母会得到不同的 fps（证明上一条判据不是恒真）',
    Math.abs(wrong - r.fps_from_gap) > 0.3, `wrong=${wrong.toFixed(3)} right=${r.fps_from_gap.toFixed(3)}`);
  // 只有一帧时没有间隔可算：必须是 NaN 而不是"0 ms ⇒ Infinity fps"
  const one = compute(b, mk({ bytes: FRAME_BYTES, gap_sum: 0 }), 0.1, 1);
  t('单帧时段数为 0 ⇒ 平均间隔是 NaN 而不是 0', Number.isNaN(one.avg_gap_ms) && Number.isNaN(one.fps_from_gap));
  // ---- 下面三条钉住 2026-09-24 撞到的那个"分母用错总体"的错 ----
  // 场景：400 帧的字节全部交付，但验收门作废了 3 帧 ⇒ 真正被接收的是 397 帧、396 段。
  // 旧写法会用 399 段去除，算出偏小的平均间隔与偏高的 fps。
  const lost3 = compute(b, mk({ bytes: 400 * FRAME_BYTES, frames_bad: 3,
                                gap_sum: 396 * 33, gap_min: 32, gap_max: 35 }), 14, 400);
  t('有作废帧时分母用"接收帧数−1"（=396）', lost3.gap_segments === 396, `segs=${lost3.gap_segments}`);
  t('有作废帧时平均间隔仍是 33 ms（不是被摊薄的 32.7）',
    Math.abs(lost3.avg_gap_ms - 33) < 1e-9, `avg=${lost3.avg_gap_ms}`);
  // 极端：每一帧都被作废 ⇒ 没有一段间隔被硬件记下来，必须给 NaN 而不是"看起来像 44 fps"
  const allbad = compute(b, mk({ bytes: 597 * FRAME_BYTES, frames_bad: 597,
                                 gap_sum: 13334, gap_min: 6667, gap_max: 6675 }), 22, 600);
  t('整轮都被作废 ⇒ 平均间隔/fps 必须是 NaN（不许报出 44.7 fps）',
    Number.isNaN(allbad.avg_gap_ms) && Number.isNaN(allbad.fps_from_gap) && allbad.frames_ok === 0,
    `avg=${allbad.avg_gap_ms} fps=${allbad.fps_from_gap} ok=${allbad.frames_ok}`);
  // frames_ok 也要能进 JSON（结论回查时要能对上分母是谁）
  t('frames_ok 进了指标表', typeof lost3.frames_ok === 'number');
  // 自相矛盾检查本身也要有测试：给一个"平均小于最小值"的输入，必须标出来
  const self_contra = compute(b, mk({ bytes: 30 * FRAME_BYTES, gap_sum: 100,
                                      gap_min: 32, gap_max: 35 }), 1, 30);
  t('avg 落在 [min,max] 之外时必须自曝', self_contra.gap_avg_impossible === true);
  t('正常输入不许误报自相矛盾', r.gap_avg_impossible === false && lost3.gap_avg_impossible === false);
  console.log(bad ? `FAIL metrics selftest (${bad})` : 'PASS metrics selftest');
  process.exit(bad ? 1 : 0);
}

// ---------------------------------------------------------------- 正常路径
const FPS     = Number(get('fps', 15));
const SECONDS = Number(get('seconds', 15));
const DROP    = Number(get('drop-every', 0));
const TAG     = String(get('tag', 'run'));
const OUT     = String(get('out', 'board/evidence_metrics'));
const IP      = String(get('ip', '192.168.1.10'));
const NO_PACE = get('no-pace', false) === true;
const COUNT   = Math.max(1, Math.round(FPS * SECONDS));

mkdirSync(OUT, { recursive: true });
console.log(`[M] 基线（含 gapclr）…`);
const base = readHealth(['--gapclr']);
console.log(`[M] 推流 ${COUNT} 帧 @${FPS}fps${DROP ? `，每 ${DROP} 包丢 1 个` : ''} …`);
const t0 = Date.now();
const args = [join(HERE, 'video_sender.mjs'), '--ip', IP, '--fps', String(FPS),
              '--count', String(COUNT)];
if (DROP > 0) args.push('--drop-every', String(DROP));
// --no-pace：让上位机**尽最大能力发**，用来量"链路+入包链在过载下怎么样"。
// 这跟"限速 15 MB/s 的正常演示"是两个不同的问题，别把两者的数字混着念。
if (get('no-pace', false) === true) args.push('--no-pace');
const s = spawnSync('node', args, { encoding: 'utf8', maxBuffer: 1 << 24 });
const wall = (Date.now() - t0) / 1000;
if (s.status !== 0) console.log('[M] 发送器退出码 ' + s.status + '：' + (s.stderr || '').slice(0, 200));
console.log(`[M] 发送结束，用时 ${wall.toFixed(2)} s；读回计数器…`);
const after = readHealth(['--once']);
const m = compute(base, after, wall, COUNT);

const md = [
  `# 指标采集 ${TAG}（${new Date().toISOString()}）`,
  ``,
  `命令：\`node src/host/metrics.mjs --fps ${FPS} --seconds ${SECONDS}${DROP ? ` --drop-every ${DROP}` : ''}${NO_PACE ? ' --no-pace' : ''} --tag ${TAG}\``,
  `bit：见同目录 \`MANIFEST.txt\` 或 \`build/gates.sh\` 当时的报告；板子为 Zynq7020。`,
  ``,
  `| 项 | 值 |`,
  `|---|---|`,
  `| 发送帧数 / 用时 | ${COUNT} / ${wall.toFixed(2)} s |`,
  `| 交付载荷字节增量 | ${m.bytes_delta} → 折合 ${m.frames_recv.toFixed(2)} 帧 |`,
  `| 收到包数增量 | ${m.pkts_delta} |`,
  `| **drop_words 增量** | **${m.drop_words}**（CDC 灌满次数 +${m.cdc_episodes}） |`,
  `| 验收门作废帧 frames_bad 增量 | ${m.frames_bad}（坏包 ${m.pkt_err}，缺行峰值 ${after.rows_miss_max}） |`,
  `| 帧间隔 min/avg/max (ms) | ${m.gap_min_ms} / ${Number.isNaN(m.avg_gap_ms) ? '—' : m.avg_gap_ms.toFixed(2)} / ${m.gap_max_ms}（${m.gap_segments} 段） |`,
  `| 由间隔算的 fps | ${Number.isNaN(m.fps_from_gap) ? '—' : m.fps_from_gap.toFixed(3)} |`,
  `| 由墙钟算的 fps | ${m.fps_wall.toFixed(3)} |`,
  `| 时基标志（结束后） | hb_slow=${m.hb_slow_a} hb_gone=${m.hb_gone_a} stream_live=${m.stream_live_a} |`,
  `| 判据 | ${m.verdict_no_word_lost ? '✅ 入包链一个字都没丢' : '❌ 丢了 ' + m.drop_words + ' 个字'} |`,
  ``,
  `原始读数（JSON，可直接复核）：`,
  ``,
  '```json', JSON.stringify({ before: base, after, metrics: m }, null, 2), '```',
].join('\n');
writeFileSync(join(OUT, `metrics_${TAG}.md`), md);
writeFileSync(join(OUT, `metrics_${TAG}.json`), JSON.stringify({ before: base, after, metrics: m, wall_s: wall }, null, 2));
console.log(md.replace(/```json[\s\S]*```/, '（原始 JSON 已写入文件）'));
console.log(`[M] 存档：${join(OUT, `metrics_${TAG}.md`)} / .json`);
