set_input_delay -clock eth_rxc -min 1.200 [get_ports {eth_rxd[*] eth_rx_ctl}]
set_input_delay -clock eth_rxc -max 2.800 [get_ports {eth_rxd[*] eth_rx_ctl}]
set_input_delay -clock eth_rxc -clock_fall -min 1.200 -add_delay [get_ports {eth_rxd[*] eth_rx_ctl}]
set_input_delay -clock eth_rxc -clock_fall -max 2.800 -add_delay [get_ports {eth_rxd[*] eth_rx_ctl}]
