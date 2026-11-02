// 作用：把一份 Markdown 转成打印友好的 HTML（A4），供 headless Edge 再转 PDF。
//       只做交付文档实际用到的语法：#/##/### 标题、段落、无序/有序列表、围栏代码、
//       表格（含对齐行）、引用块、行内代码、粗体/斜体、水平线。链接渲染成"文字（url）"。
// 输入：node md2pdf.mjs <in.md> <out.html> [标题]
// 输出：out.html；stdout 打印一行统计（行数/表格数/代码块数）。
// 退出码：0 = 成功；1 = 参数或读文件失败。
import fs from 'node:fs';

const [inF, outF, title] = process.argv.slice(2);
if (!inF || !outF) { console.log('用法: node md2pdf.mjs <in.md> <out.html> [标题]'); process.exit(1); }
let src;
try { src = fs.readFileSync(inF, 'utf8'); } catch { console.log('读不到 ' + inF); process.exit(1); }

const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const inline = (s) => esc(s)
  .replace(/`([^`]+)`/g, '<code>$1</code>')
  .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
  .replace(/(^|[^*\w])\*([^*\n]+)\*(?![*\w])/g, '$1<em>$2</em>')
  .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '$1（<span class="url">$2</span>）');

const out = [];
const lines = src.split(/\r?\n/);
let i = 0, tables = 0, fences = 0, inUl = false, inOl = false;
const closeLists = () => { if (inUl) { out.push('</ul>'); inUl = false; } if (inOl) { out.push('</ol>'); inOl = false; } };

while (i < lines.length) {
  const L = lines[i];
  if (/^```/.test(L)) {
    closeLists();
    const buf = []; i++;
    while (i < lines.length && !/^```/.test(lines[i])) { buf.push(lines[i]); i++; }
    i++; fences++;
    out.push('<pre><code>' + esc(buf.join('\n')) + '</code></pre>');
    continue;
  }
  if (/^\s*\|/.test(L) && i + 1 < lines.length && /^\s*\|[\s:|-]+\|\s*$/.test(lines[i + 1])) {
    closeLists();
    const head = L; const align = lines[i + 1];
    const cells = (r) => r.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map((c) => c.trim());
    const ac = cells(align).map((a) => /:-+$/.test(a.replace(/\s/g, '')) && /^:/.test(a.trim()) ? ' class="c"' : /^-+:$/.test(a.trim()) ? ' class="r"' : '');
    const rows = [head, ...(() => { const r = []; i += 2; while (i < lines.length && /^\s*\|/.test(lines[i])) { r.push(lines[i]); i++; } return r; })()];
    tables++;
    out.push('<table>');
    out.push('<thead><tr>' + cells(rows[0]).map((c, k) => `<th${ac[k] || ''}>${inline(c)}</th>`).join('') + '</tr></thead><tbody>');
    for (const r of rows.slice(1)) out.push('<tr>' + cells(r).map((c, k) => `<td${ac[k] || ''}>${inline(c)}</td>`).join('') + '</tr>');
    out.push('</tbody></table>');
    continue;
  }
  let m;
  if ((m = L.match(/^(#{1,4})\s+(.*)$/))) { closeLists(); out.push(`<h${m[1].length}>${inline(m[2])}</h${m[1].length}>`); i++; continue; }
  if (/^\s*[-*]\s+/.test(L)) { if (!inUl) { closeLists(); out.push('<ul>'); inUl = true; } out.push('<li>' + inline(L.replace(/^\s*[-*]\s+/, '')) + '</li>'); i++; continue; }
  if (/^\s*\d+[.)]\s+/.test(L)) { if (!inOl) { closeLists(); out.push('<ol>'); inOl = true; } out.push('<li>' + inline(L.replace(/^\s*\d+[.)]\s+/, '')) + '</li>'); i++; continue; }
  if (/^\s*>\s?/.test(L)) { closeLists(); out.push('<blockquote>' + inline(L.replace(/^\s*>\s?/, '')) + '</blockquote>'); i++; continue; }
  if (/^\s*(---|\*\*\*)\s*$/.test(L)) { closeLists(); out.push('<hr>'); i++; continue; }
  if (L.trim() === '') { closeLists(); i++; continue; }
  closeLists(); out.push('<p>' + inline(L) + '</p>'); i++;
}
closeLists();

const html = `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8"><title>${esc(title || outF)}</title><style>
@page { size: A4; margin: 16mm 14mm; }
body { font-family: "Segoe UI","Microsoft YaHei",sans-serif; font-size: 9.6pt; line-height: 1.5; color: #16181d; }
h1 { font-size: 17pt; border-bottom: 2px solid #2b5fd9; padding-bottom: 4pt; }
h2 { font-size: 13pt; margin-top: 14pt; border-left: 4px solid #2b5fd9; padding-left: 6pt; }
h3 { font-size: 11pt; margin-top: 11pt; color: #23324a; }
h4 { font-size: 10pt; color: #3a4658; }
p, li { text-align: justify; }
code { font-family: "Cascadia Mono",Consolas,monospace; font-size: 8.8pt; background: #f2f4f8; padding: 0 2pt; border-radius: 2pt; }
pre { background: #f7f8fa; border: 1px solid #dfe3ea; padding: 6pt; page-break-inside: avoid; }
pre code { background: none; padding: 0; font-size: 8.4pt; }
table { border-collapse: collapse; width: 100%; margin: 6pt 0; font-size: 8.6pt; page-break-inside: auto; }
th, td { border: 1px solid #c9d0dc; padding: 2.5pt 4pt; vertical-align: top; }
th { background: #eef2f8; }
td.c, th.c { text-align: center; } td.r, th.r { text-align: right; }
blockquote { margin: 5pt 0; padding: 3pt 8pt; border-left: 3px solid #9fb2cc; background: #f6f8fb; color: #33404f; }
.url { color: #6b7686; font-size: 8pt; word-break: break-all; }
hr { border: none; border-top: 1px solid #d8dee8; margin: 10pt 0; }
</style></head><body>
${out.join('\n')}
</body></html>\n`;
fs.writeFileSync(outF, html);
console.log(`md2pdf 行=${lines.length} 表格=${tables} 代码块=${fences} → ${outF}`);
