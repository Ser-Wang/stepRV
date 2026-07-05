set clk_period 20.0

create_clock -name clk -period $clk_period [get_ports clk]

set_clock_uncertainty 0.2 [get_clocks clk]
set_input_delay  2.0 -clock clk [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay 2.0 -clock clk [all_outputs]

set_max_transition 1.0 [current_design]
