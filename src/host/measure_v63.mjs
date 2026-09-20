#!/usr/bin/env node
/**
 * measure_v63.mjs — 一条命令完成「推流 → 停止 → JTAG 回读 → 包内相位丢字签名」的复验。
 *
 * 关键：**必须等推流结束再回读**。回读要几秒，期间若还在推流，每个地址段读到的
 * 是不同时刻的帧（bank0 帧号跨度 130..152 就是这么来的），命中率统计全部作废。
 *
 * 用法：node host/measure_v63.mjs [--fps 15] [--count 60] [--pace-mpbps 15] [--live]
 *   --live  边推边读（只看 16bit 粒度探针，不看命中率）
 * 前置：板子已 ps7_init + program bit + set_src（GPIO=0x00010000），hw_server 在跑。
 */
import { spawn, spawnSync } from 'node:child_process';
import { MEASURED, host, dump } from './repo_path.mjs';


const arg = (n, d) => {
  const i = process.argv.indexOf('--' + n);
  return i < 0 ? d : process.argv[i + 1];
};
const FPS = arg('fps', '15');
const PACE = arg('pace-mpbps', '15');
const LIVE = process.argv.includes('--live');
const COUNT = arg('count', String(Math.ceil(Number(FPS) * 4) + 20));

const tx = [host('video_sender.mjs'), '--test', 'frameid', '--fps', FPS, '--count', COUNT,
            '--pace-mpbps', PACE];

if (LIVE) {
  const sender = spawn(process.execPath, tx, { stdio: 'inherit' });
  await new Promise(r => setTimeout(r, 6000));
  spawnSync(process.execPath, [host('ddr_verify.mjs'), '--frameid'], { stdio: 'inherit' });
  sender.kill();                       // 只杀自己起的 PID
  console.log(`[MEASURE] live 模式：推流 pid=${sender.pid} 已关闭`);
} else {
  console.log(`[MEASURE] 推流 ${COUNT} 帧 @${FPS}fps（pace=${PACE} MB/s），发完再回读`);
  const r = spawnSync(process.execPath, tx, { stdio: 'inherit' });
  console.log(`[MEASURE] 推流退出码 ${r.status}，等 500 ms 让最后一帧落位`);
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 500);
  spawnSync(process.execPath, [host('ddr_verify.mjs'), '--frameid'], { stdio: 'inherit' });
}

spawnSync(process.execPath, [host('ddr_stale.mjs')], { stdio: 'inherit' });
