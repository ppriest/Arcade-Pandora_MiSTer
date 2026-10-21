derive_pll_clocks
derive_clock_uncertainty

# core specific constraints

# TG68KdotC_Kernel steps on maincpu's clock enable, at most one clk in four (12 MHz of 48), and
# maincpu's bus logic gives the kernel's outputs two clk before acting on them.
set krn [get_registers {*TG68KdotC_Kernel:*|*}]
if {[get_collection_size $krn] > 0} {
    set_multicycle_path -setup -end 2 -from $krn -to [all_registers]
    set_multicycle_path -hold  -end 1 -from $krn -to [all_registers]
    set_multicycle_path -setup -end 3 -from $krn -to $krn
    set_multicycle_path -hold  -end 2 -from $krn -to $krn
} else {
    post_message -type critical_warning "Pandora.sdc: no TG68KdotC_Kernel registers matched -- CPU multicycle NOT applied"
}

# jt8052 and its memories step on cen, one clk in three
set m8051  [get_registers {*|snowbros_mcu:u_mcu|jt8052:u_mcu|*}]
set m8051m [get_keepers {*|snowbros_mcu:u_mcu|altsyncram:*|* *|snowbros_mcu:u_mcu|q_even[*] *|snowbros_mcu:u_mcu|q_odd[*] *|snowbros_mcu:u_mcu|rom_hi *|snowbros_mcu:u_mcu|ram_q[*]}]
if {[get_collection_size $m8051] > 0} {
    set_multicycle_path -setup -end 3 -from $m8051 -to $m8051
    set_multicycle_path -hold  -end 2 -from $m8051 -to $m8051
    if {[get_collection_size $m8051m] > 0} {
        set_multicycle_path -setup -end 3 -from $m8051 -to $m8051m
        set_multicycle_path -hold  -end 2 -from $m8051 -to $m8051m
        set_multicycle_path -setup -end 3 -from $m8051m -to $m8051
        set_multicycle_path -hold  -end 2 -from $m8051m -to $m8051
    }
} else {
    post_message -type critical_warning "Pandora.sdc: no jt8052 registers matched -- MCU multicycle NOT applied"
}
