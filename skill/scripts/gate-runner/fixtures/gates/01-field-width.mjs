// 合成判据 1：字段值不得超出其位宽上界（做 2 次比较 ⇒ 真绿）
export const ID = 'width-bound';
const FIELDS = [
  { name: 'count', width: 12, value: 4095 },
  { name: 'gain', width: 8, value: 200 },
];

export function run(ctx) {
  let ok = true;
  for (const f of FIELDS) ok = ctx.cmp(`${f.name} ≤ 上界`, f.value, (1 << f.width) - 1, '<=') && ok;
  ctx.log(`逐字段算上界：${FIELDS.map(f => f.name).join('/')}`);
  return { id: ID, detail: `字段=${FIELDS.length} 全在上界内=${ok}`, verdict: ok ? 'PASS' : 'FAIL' };
}
