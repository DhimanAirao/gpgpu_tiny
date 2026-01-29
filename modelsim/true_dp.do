#set AlteraLib {E:\intelFPGA_lite\18.1\modelsim_ase\altera\verilog\220model}
#set AlteraLib1 {E:\intelFPGA_lite\18.1\modelsim_ase\altera\verilog\altera_mf}
vlib work
vmap work work

#compilation for library file required by ecc_decoder and true_dp_ram
vlog -work work {E:\intelFPGA_lite\18.1\quartus\eda\sim_lib\220model.v}
vlog -work work {E:\intelFPGA_lite\18.1\quartus\eda\sim_lib\altera_mf.v}


vlog -work work {E:\intelFPGA_lite\gpgpu\modelsim\tb.sv}
vlog -work work {E:\intelFPGA_lite\gpgpu\alu.sv}
vlog -work work {E:\intelFPGA_lite\gpgpu\controller.sv}
vlog -work work {E:\intelFPGA_lite\gpgpu\core.sv}
vlog -work work {E:\intelFPGA_lite\gpgpu\dcr.sv}
vlog -work work {E:\intelFPGA_lite\gpgpu\de2_top.sv}
vlog -work work {E:\intelFPGA_lite\gpgpu\decoder.sv}
vlog -work work {E:\intelFPGA_lite\gpgpu\dispatch.sv}
vlog -work work {E:\intelFPGA_lite\gpgpu\fetcher.sv}
vlog -work work {E:\intelFPGA_lite\gpgpu\gpu.sv}
vlog -work work {E:\intelFPGA_lite\gpgpu\lsu.sv}
vlog -work work {E:\intelFPGA_lite\gpgpu\pc.sv}
vlog -work work {E:\intelFPGA_lite\gpgpu\registers.sv}
vlog -work work {E:\intelFPGA_lite\gpgpu\scheduler.sv}
vlog -work work {E:\intelFPGA_lite\gpgpu\global_memory\prog_mem\prog_mem.v}
vlog -work work {E:\intelFPGA_lite\gpgpu\global_memory\data_mem\data_mem.v}
vlog -work work {E:\intelFPGA_lite\gpgpu\global_memory\prog_mem\prog_mem_16A_32D.v}
vlog -work work {E:\intelFPGA_lite\gpgpu\global_memory\data_mem\data_mem_16A_16D.v}
