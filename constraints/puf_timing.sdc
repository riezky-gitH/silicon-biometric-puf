# ===========================================================================
# puf_timing.sdc — Timing Constraints
# Silicon-Biometric Secure Element | DE10-Nano (Cyclone V SE)
# ===========================================================================

# --- System clock: 50 MHz from onboard oscillator ---
create_clock -name {CLOCK_50} -period 20.000 [get_ports {clk}]

# --- Derive PLL uncertainties ---
derive_clock_uncertainty

# --- False paths: RO async counters → system domain ---
# Counters are only read after RO is disabled (static values),
# so this crossing is safe by design.
set_false_path -from [get_registers {*measure_unit*cnt_a[*]}] \
               -to   [get_registers {*measure_unit*lat_a[*]}]
set_false_path -from [get_registers {*measure_unit*cnt_b[*]}] \
               -to   [get_registers {*measure_unit*lat_b[*]}]

# --- False paths: RO combinational loops ---
# Ring oscillators are intentional combinational loops.
set_false_path -from [get_pins -hierarchical {*ro_cell*n[*]}]

# --- I/O constraints ---
set_input_delay  -clock CLOCK_50 -max 5.0 [get_ports {rst_n sw[*]}]
set_output_delay -clock CLOCK_50 -max 5.0 [get_ports {led[*]}]

# --- Avalon-MM interface timing (from Platform Designer) ---
set_input_delay  -clock CLOCK_50 -max 3.0 [get_ports {avs_*}]
set_output_delay -clock CLOCK_50 -max 3.0 [get_ports {avs_readdata[*]}]
