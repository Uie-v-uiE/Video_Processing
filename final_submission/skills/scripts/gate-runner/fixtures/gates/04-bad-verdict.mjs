// 合成判据 4（对照件）：用了包外判定词 ⇒ 归 NOT_MEASURED，不许被当成通过
export const ID = 'bad-verdict';

export function run(ctx) {
  const ok = ctx.cmp('样本数 > 0', 3 > 0, true);
  return { id: ID, detail: `比较做了 1 次（结果=${ok}），但判定词写成 OK`, verdict: 'OK' };
}
