# -*- coding: utf-8 -*-
"""Offline check of effect-enable bit mapping (same as PS/PL convention)."""
def parse_bits(s: str) -> int:
    en = 0
    for n, ch in enumerate(s.strip()[:5]):
        if ch not in "01":
            raise ValueError(ch)
        en |= (ord(ch) - 48) << n
    return en

cases = {
    "00111": 0b11100,  # blur, sobel, invert
    "10000": 0b00001,  # gray
    "11111": 0b11111,
    "00000": 0b00000,
    "01000": 0b00010,  # binary only
}
ok = True
for s, exp in cases.items():
    got = parse_bits(s)
    status = "OK" if got == exp else "FAIL"
    if got != exp:
        ok = False
    print(f"{status} {s} -> {got:05b} expect {exp:05b}")
print("ALL OK" if ok else "FAILED")
raise SystemExit(0 if ok else 1)
