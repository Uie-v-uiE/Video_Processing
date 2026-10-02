import fs from 'node:fs';
const P = 'src/rtl/eth/frame_reasm.v';
const O = P;   // 原地打补丁：原文在 git 里，回退就是 git checkout 这一个文件
let t = fs.readFileSync(P, 'utf8');
if (t.includes('rok0')) { console.log('REFUSE: 这一版补丁已经打过了（文件里已有 rok0）'); process.exit(1); }
const before = t.length;
let n = 0;
function repRe(re, put, want) {
    const g = new RegExp(re.source, re.flags.includes('g') ? re.flags : re.flags + 'g');
    const c = [...t.matchAll(g)].length;
    if (c !== want) { console.log(`REFUSE: 正则命中 ${c} 次（要 ${want}）：${re.source}`); process.exit(1); }
    t = t.replace(re, put); n++;
}
repRe(/^    reg \[IMG_H-1:0\] row_ok;$/m,
 `    // per-row coverage this frame, stored in 5 x 64-bit banks (IMG_H=300 <= 320).
    // Why banks: the "this byte starts a new row" term used to be the CE driver of ALL 300
    // coverage FFs plus the 16 rows_hit FFs (r106 post-route report: fo=316, and that last hop
    // alone cost 1.980 ns of the 6.879 ns data path, route share 81.2 %). Each bank now takes
    // <= 64 loads and the row counter's enable takes 16. Bound: 5 x 64 = 320 rows -- a bigger
    // IMG_H must add banks AND widen rbank; the guard above endmodule says so in simulation.
    reg [63:0] rok0, rok1, rok2, rok3, rok4;`, 1);
repRe(/^    wire \[31:0\] row_idx = off \/ ROW_STRIDE;$/m,
 `    wire [31:0] row_idx = off / ROW_STRIDE;
    wire [8:0]  ridx  = row_idx[8:0];
    wire [2:0]  rbank = ridx[8:6];
    wire [5:0]  roff  = ridx[5:0];
    wire        row_covered =
          (rbank == 3'd0) ? rok0[roff]
        : (rbank == 3'd1) ? rok1[roff]
        : (rbank == 3'd2) ? rok2[roff]
        : (rbank == 3'd3) ? rok3[roff]
        :                    rok4[roff];`, 1);
repRe(/^( +)row_ok<=0; rows_hit<=0;$/m, '$1rok0<=0; rok1<=0; rok2<=0; rok3<=0; rok4<=0; rows_hit<=0;', 1);
repRe(/^( +)row_ok<=0;$/gm, '$1rok0<=0; rok1<=0; rok2<=0; rok3<=0; rok4<=0;', 2);
repRe(/!row_ok\[row_idx\[8:0\]\]/, '!row_covered', 1);
repRe(/^( +)row_ok\[row_idx\[8:0\]\] <= 1'b1;$/m,
 `$1if (rbank == 3'd0) rok0[roff] <= 1'b1;
$1if (rbank == 3'd1) rok1[roff] <= 1'b1;
$1if (rbank == 3'd2) rok2[roff] <= 1'b1;
$1if (rbank == 3'd3) rok3[roff] <= 1'b1;
$1if (rbank == 3'd4) rok4[roff] <= 1'b1;`, 1);
repRe(/只管 `row_ok\/rows_hit`/, '只管 `rok0..rok4/rows_hit`', 1);
repRe(/^endmodule$/m,
 `// 界（#146 那一族的写法）：bank 数写死在 5。IMG_H 一旦超过 5*64，行覆盖就记丢、
// frame_done 永不成立（画面是黑纹而不是报错）。台架里当场喊；综合忽略 initial。
initial begin
    if (IMG_H > 5 * 64)
        $error("frame_reasm: IMG_H=%0d exceeds 5 x 64 row-coverage banks (320); add banks and widen rbank", IMG_H);
end

endmodule`, 1);
if (/row_ok\s*<=|row_ok\[/.test(t)) { console.log('REFUSE: 代码里还有 row_ok 引用'); process.exit(1); }
if (t.length <= before) { console.log('REFUSE: 打完补丁反而变短，插入没生效'); process.exit(1); }
fs.writeFileSync(O, t);
console.log(`OK  替换 ${n} 处，${before} -> ${t.length} 字节，行数 ${t.split(/\r?\n/).length}`);
