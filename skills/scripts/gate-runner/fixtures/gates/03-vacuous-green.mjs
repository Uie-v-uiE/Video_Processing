// 合成判据 3（对照件）：一条比较都没做却自称通过 ⇒ 跑批器必须把它降级成 NOT_MEASURED
export const ID = 'vacuous-green';

export function run() {
  return { id: ID, detail: '恒绿、且一次 ctx.cmp 都没调（真空通过的样子）', verdict: 'PASS' };
}
