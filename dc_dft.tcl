#dft_drc
read_file -format ddc {/home/t112830022/ICC/CONV_syn.ddc}
create_port -dir in SCAN_IN
create_port -dir out SCAN_OUT
create_port -dir in SCAN_EN
set_dft_signal -view exist -type ScanClock -timing {45 55} -port clk
set_dft_signal -view exist -type Reset -active_state 1 -port reset
create_test_protocol
dft_drc

#compile -scan
compile -scan -map_effort high -area_effort high -boundary_optimization 
#insert_dft
set_scan_configuration -chain_count 1 -clock_mixing mix_clocks_not_edges -internal_clocks single -add_lockup false
set_dft_signal -view spec -port SCAN_IN -type ScanDataIn
set_dft_signal -view spec -port SCAN_OUT -type ScanDataOut
set_dft_signal -view spec -port SCAN_EN -type ScanEnable -active_state 1
set_scan_path chain1 -scan_data_in SCAN_IN -scan_data_out SCAN_OUT
preview_dft -show all
insert_dft
#report
dft_drc -coverage_estimate > coverage.log
report_scan_path -view existing_dft -chain all > chain.log
report_scan_path -view existing_dft -cell all > cell.log
#output
write -format verilog -hierarchy -output conv_scan.vg
write_test_protocol -output conv_scan.spf
