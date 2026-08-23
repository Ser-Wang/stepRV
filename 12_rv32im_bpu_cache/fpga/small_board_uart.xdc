# xc7a35tfgg484-2
set_property PACKAGE_PIN V4 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property PACKAGE_PIN U7 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

create_clock -name sys_clk -period 20.000 [get_ports clk]

# uart
set_property PACKAGE_PIN W21 [get_ports o_uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports o_uart_tx]
set_property PACKAGE_PIN T20 [get_ports i_uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports i_uart_rx]

#set_property CFGBVS VCCO [current_design]
#set_property CONFIG_VOLTAGE 3.3 [current_design]
#set_property BITSTREAM.GENERAL.COMPRESS true [current_design]
#set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
#set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
#set_property BITSTREAM.CONFIG.SPI_FALL_EDGE Yes [current_design]

#set_property IOSTANDARD LVCMOS15 [get_ports {key[1]}]
#set_property IOSTANDARD LVCMOS15 [get_ports {key[0]}]
#set_property PACKAGE_PIN T3 [get_ports {key[1]}]
#set_property PACKAGE_PIN T4 [get_ports {key[0]}]





