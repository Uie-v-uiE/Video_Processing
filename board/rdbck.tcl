connect
targets -set -filter {name =~ "*APU*"}
puts "GPIO@0x41200000 = [mrd -force 0x41200000]"
exit
