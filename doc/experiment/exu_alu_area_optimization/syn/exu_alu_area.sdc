# Standalone combinational ALU constraint used by the area comparison.
set_input_transition 0.10 [all_inputs]
set_load 0.02 [all_outputs]
set_max_delay 16.0 -from [all_inputs] -to [all_outputs]
set_max_transition 1.0 [current_design]
