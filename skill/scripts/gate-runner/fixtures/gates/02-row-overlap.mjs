// 合成判据 2：相邻区间不得相交（第 1 条比较就不满足 ⇒ 真红，跑批器应退出码 1）
export const ID = 'row-overlap';
const ROWS = [
  { name: 'A', start: 0, end: 4 },
  { name: 'B', start: 2, end: 6 },
];

export function run(ctx) {
  let ok = true;
  for (let i = 1; i < ROWS.length; i++) ok = ctx.cmp(`${ROWS[i - 1].name}/${ROWS[i].name} 不相交`, ROWS[i].start >= ROWS[i - 1].end, true) && ok;
  ok = ctx.cmp('行数 ≥ 2（少于两行就没法比）', ROWS.length >= 2, true) && ok;
  return { id: ID, detail: `区间数=${ROWS.length}`, verdict: ok ? 'PASS' : 'FAIL' };
}
