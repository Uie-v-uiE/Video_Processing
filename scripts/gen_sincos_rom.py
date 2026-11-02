# -*- coding: utf-8 -*-
"""Generate sin/cos ROM tables. Q8: round(sin(deg)*256). Range -256..256 fits signed 10-bit."""
from pathlib import Path
import math

out_dir = Path(r"D:\Software\Xiaomi_MiMo\video\zynq_video_pipeline\rtl\process\rotate")


def gen(name, fn):
    lines = [
        "`timescale 1ns/1ps",
        f"// Auto-generated {name}: round(fn(angle_deg)*256), signed 10-bit",
        f"module {name} (",
        "    input  wire [8:0] angle, // 0..359",
        "    output reg signed [9:0] value",
        ");",
        "    always @(*) begin",
        "        case (angle)",
    ]
    for a in range(360):
        v = int(round(fn(math.radians(a)) * 256))
        if v > 256:
            v = 256
        if v < -256:
            v = -256
        # legal Verilog: -10'sd88 or 10'sd181
        if v < 0:
            lit = f"-10'sd{-v}"
        else:
            lit = f"10'sd{v}"
        lines.append(f"            9'd{a}: value = {lit};")
    lines += [
        "            default: value = 10'sd0;",
        "        endcase",
        "    end",
        "endmodule",
        "",
    ]
    path = out_dir / f"{name}.v"
    path.write_text("\n".join(lines), encoding="utf-8")
    # sanity
    assert "10'sd256" in path.read_text(encoding="utf-8") or name != "cos_rom"
    print("wrote", name)


gen("sin_rom", math.sin)
gen("cos_rom", math.cos)

# verify cos(0)
text = (out_dir / "cos_rom.v").read_text(encoding="utf-8")
assert "9'd0: value = 10'sd256;" in text, text.splitlines()[10]
print("cos(0)=256 OK")
