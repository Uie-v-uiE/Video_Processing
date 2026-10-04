// 用途：合成判据 1：字段值不得超出其位宽上界（做 2 次比较 ⇒ 真绿）
// 输入：无字面量输入路径；参数解析见本文件
// 输出：stdout（本文件没有仓库内的写盘路径字面量）
// 退出码：脚本内无显式 exit ⇒ 随最后一条命令（正常跑完为 0）
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
