connect
targets -set -filter {name =~ "*APU*"}
puts "GPIO = [mrd -force 0x41200000]"
puts "DDR  head:"
foreach l [mrd -force 0x10000000 8] { puts "  $l" }
exit
