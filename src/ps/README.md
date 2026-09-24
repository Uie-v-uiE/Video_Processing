# Zynq PS application notes
#
# 1. Vivado: tcl/create_project.tcl system + build_bitstream.tcl system
#    -> output/system.xsa
# 2. Vitis: File > New > Platform from XSA
#    - BSP: lwip, xuartps, xgpio
# 3. New Application "video_ps", add main.c (this folder)
# 4. Linker: ensure DDR has space; PS frame at 0x10100000 (ETH owns 0x10000000/0x10080000)
# 5. UART0 115200 8N1 on FT2232
#
# EMIO GPIO map (PL):
#   [4:0]   effect_en  (bit0=leftmost of serial string)
#   [15:8]  threshold
#   [16]    src_sel 0=colorbar 1=DDR frames
#
# After first full UDP frame, software sets src_sel=1 automatically.
