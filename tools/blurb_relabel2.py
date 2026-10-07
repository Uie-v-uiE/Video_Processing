import io

def fix(path, pairs):
    s = io.open(path, encoding="utf-8", newline="").read()
    for a, b in pairs:
        n = s.count(a)
        if n != 1:
            raise SystemExit("MISS %s :: %s :: %d" % (path, a[:44], n))
        s = s.replace(a, b)
    io.open(path, "w", encoding="utf-8", newline="").write(s)
    print("OK", path, "CR=", s.count("\r\n"), "ff=", s.count("\x0c"))

fix("REVIEW-20261007.md", [
    ("  **A（建议）非空白 496 / 含空白 499**，汉字 274；B（三路片源那版）非空白 499 / **含空白 550**。",
     "  **A（建议，三路片源 + 亮点式）非空白 496 / 含空白 499**，汉字 271；"
     "B（只走网口那一路）非空白 496 / 含空白 499，汉字 274；C（分段叙述的旧稿）非空白 499 / **含空白 550**。\n"
     "  一条口径纠错记在这儿：用户给的样例是**他最初版本作品的简介**，只借写法、不是内容来源 ⇒ "
     "我第一版把三路片源省掉是错的，A 已把网口 / SD / 内置图卡三路都写进去。"),
    ("  A 里每个数都有出处：`≤1392 B / 4 字节偏移头`＝`src/host/video_sender.mjs:9` 与 `udp_push.py:5`；",
     "  每个数都有出处：`≤1392 B`（B 版另把「4 字节偏移头」写全了）＝`src/host/video_sender.mjs:9` 与 `udp_push.py:5`；"),
    ('  A 末句"板级验收 PASS、丢字计数读回 0"的凭据就在包里：`board/output/verify_1007_1421.txt`（三条 `RESULT=PASS`、`drop_words → 0`）。',
     '  B 末句"板级验收 PASS、丢字计数读回 0"的凭据就在包里：`board/output/verify_1007_1421.txt`（三条 `RESULT=PASS`、`drop_words → 0`）；\n'
     "  A 的末句换成「82支testbench、24项构建门禁、断电自启」，凭据是包内 `build/reports/` 的门禁件与 `board/output/` 的板级件。"),
    ("并把 `main cadb49a` 的非厂商树逐件对账（读数在 §1 那一行：`判=1124 缺=0 内容不同=0`）。",
     "并把 `main cadb49a` 的非厂商树逐件对账（那是 12:4x 的读数 `判=1124 缺=0 内容不同=0`；"
     "**15:1x 又同步了一次**，终局读数在 §1 那一行 `判=1131 缺=0 内容不同=0`，中间红过一次、原因与修法见 §3 第 7 条续文）。"),
])

fix("BUNDLE-Contents.md", [
    ("（50 行，四个作品名称候选（各标实测字数）+ 报名表三个关键词 + **两版项目简介**"
     "（A 亮点式 非空白 496／含空白 499；B 三路片源式 非空白 499／含空白 550）+ 四条边界）",
     "（54 行，四个作品名称候选（各标实测字数）+ 报名表三个关键词 + **三版项目简介**"
     "（A 三路片源＋亮点式 非空白 496／含空白 499，建议；B 只走网口那一路 496／499；"
     "C 分段叙述旧稿 499／含空白 550 ⇒ 按含空白口径超线）+ 四条边界）"),
])
