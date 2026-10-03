# build/tcl/r116_jtag_health.tcl -- read-only: is the PS reachable over JTAG at all?
# Decides between "recover by JTAG system reset" and "needs a physical power cycle (user's hand)".
connect -host localhost -port 3121
puts "JTAG_TARGETS_BEGIN"
puts [targets]
puts "JTAG_TARGETS_END"
set sel [catch {targets -set -nocase -filter {name =~ "*APU*"}} err_apu]
puts "APU_SELECT rc=$sel err=$err_apu"
if {$sel == 0} {
    set r1 [catch {ctx -index 0} e1]
    puts "CTX0 rc=$r1 err=$e1"
    set r2 [catch {rr 0xF8F00218} e2]
    puts "SLCR_PSS_RST_CTRL(0xF8F00218) rc=$r2 val=$e2"
    set r3 [catch {rr 0xF8F00200} e3]
    puts "SLCR_DDR_RST_CTRL rc=$r3 val=$e3"
}
puts "JTAGHEALTHDONE"
