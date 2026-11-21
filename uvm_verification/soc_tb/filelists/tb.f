-sverilog
-timescale=1ns/1ps
+define+RV_OPENSOURCE
+libext+.v+.sv

+incdir+../rtl/Cores-VeeR-EL2/snapshots/default
+incdir+../rtl/Cores-VeeR-EL2/design/include
+incdir+../rtl/Cores-VeeR-EL2/testbench
+incdir+../rtl/UART/src/include
+incdir+../rtl/encoder
+incdir+../rtl/pid_controler
+incdir+../rtl/common
+incdir+VIP/gpio_uvm_tb
+incdir+VIP/uart_uvm_tb
+incdir+VIP/encoder_uvm_tb
+incdir+VIP/pwm_uvm_tb
+incdir+soc_tb/env
+incdir+soc_tb/tests

# VeeR EL2 Core
../rtl/Cores-VeeR-EL2/design/include/el2_def.sv
../rtl/Cores-VeeR-EL2/design/lib/el2_assert.sv
../rtl/Cores-VeeR-EL2/design/el2_mubi_pkg.sv
../rtl/Cores-VeeR-EL2/design/el2_veer_wrapper.sv
../rtl/Cores-VeeR-EL2/design/el2_mem.sv
../rtl/Cores-VeeR-EL2/design/el2_pic_ctrl.sv
../rtl/Cores-VeeR-EL2/design/el2_veer.sv
../rtl/Cores-VeeR-EL2/design/el2_dma_ctrl.sv
../rtl/Cores-VeeR-EL2/design/el2_pmp.sv
../rtl/Cores-VeeR-EL2/design/ifu/el2_ifu_aln_ctl.sv
../rtl/Cores-VeeR-EL2/design/ifu/el2_ifu_compress_ctl.sv
../rtl/Cores-VeeR-EL2/design/ifu/el2_ifu_ifc_ctl.sv
../rtl/Cores-VeeR-EL2/design/ifu/el2_ifu_bp_ctl.sv
../rtl/Cores-VeeR-EL2/design/ifu/el2_ifu_ic_mem.sv
../rtl/Cores-VeeR-EL2/design/ifu/el2_ifu_mem_ctl.sv
../rtl/Cores-VeeR-EL2/design/ifu/el2_ifu_iccm_mem.sv
../rtl/Cores-VeeR-EL2/design/ifu/el2_ifu.sv
../rtl/Cores-VeeR-EL2/design/dec/el2_dec_decode_ctl.sv
../rtl/Cores-VeeR-EL2/design/dec/el2_dec_gpr_ctl.sv
../rtl/Cores-VeeR-EL2/design/dec/el2_dec_ib_ctl.sv
../rtl/Cores-VeeR-EL2/design/dec/el2_dec_pmp_ctl.sv
../rtl/Cores-VeeR-EL2/design/dec/el2_dec_tlu_ctl.sv
../rtl/Cores-VeeR-EL2/design/dec/el2_dec_trigger.sv
../rtl/Cores-VeeR-EL2/design/dec/el2_dec.sv
../rtl/Cores-VeeR-EL2/design/exu/el2_exu_alu_ctl.sv
../rtl/Cores-VeeR-EL2/design/exu/el2_exu_mul_ctl.sv
../rtl/Cores-VeeR-EL2/design/exu/el2_exu_div_ctl.sv
../rtl/Cores-VeeR-EL2/design/exu/el2_exu.sv
../rtl/Cores-VeeR-EL2/design/lsu/el2_lsu.sv
../rtl/Cores-VeeR-EL2/design/lsu/el2_lsu_clkdomain.sv
../rtl/Cores-VeeR-EL2/design/lsu/el2_lsu_addrcheck.sv
../rtl/Cores-VeeR-EL2/design/lsu/el2_lsu_lsc_ctl.sv
../rtl/Cores-VeeR-EL2/design/lsu/el2_lsu_stbuf.sv
../rtl/Cores-VeeR-EL2/design/lsu/el2_lsu_bus_buffer.sv
../rtl/Cores-VeeR-EL2/design/lsu/el2_lsu_bus_intf.sv
../rtl/Cores-VeeR-EL2/design/lsu/el2_lsu_ecc.sv
../rtl/Cores-VeeR-EL2/design/lsu/el2_lsu_dccm_mem.sv
../rtl/Cores-VeeR-EL2/design/lsu/el2_lsu_dccm_ctl.sv
../rtl/Cores-VeeR-EL2/design/lsu/el2_lsu_trigger.sv
../rtl/Cores-VeeR-EL2/design/dbg/el2_dbg.sv
../rtl/Cores-VeeR-EL2/design/dmi/dmi_mux.v
../rtl/Cores-VeeR-EL2/design/dmi/dmi_wrapper.v
../rtl/Cores-VeeR-EL2/design/dmi/dmi_jtag_to_core_sync.v
../rtl/Cores-VeeR-EL2/design/dmi/rvjtag_tap.v
../rtl/Cores-VeeR-EL2/design/lib/el2_lib.sv
../rtl/Cores-VeeR-EL2/design/lib/el2_mem_if.sv
-v ../rtl/Cores-VeeR-EL2/design/lib/beh_lib.sv
-v ../rtl/Cores-VeeR-EL2/design/lib/mem_lib.sv
-y ../rtl/Cores-VeeR-EL2/design/lib
-v ../rtl/Cores-VeeR-EL2/testbench/user_cells.sv
../rtl/Cores-VeeR-EL2/testbench/veer_wrapper.sv

# SoC Interconnect
../rtl/interconnect/priority_encoder.v
../rtl/interconnect/arbiter.v
../rtl/interconnect/axi_interconnect.v
../rtl/interconnect/axi_interconnect_wrap_3x15.v

# Peripherals
../rtl/common/axi4lite_slave_adapter.sv

../rtl/gpio/gpio_bit.sv
../rtl/gpio/gpio_regs.sv
../rtl/gpio/gpio_wrapper.sv
../rtl/gpio/gpio_axi.sv

../rtl/timer/timer_core.sv
../rtl/timer/timer_regs.sv
../rtl/timer/timer_axi.sv

../rtl/UART/axi_internal_fifo.v
../rtl/UART/uart_parity_bit_compute.v
../rtl/UART/uart_transmitter.v
../rtl/UART/uart_receiver.v
../rtl/UART/uart_controller.v
../rtl/UART/axi_uart_top.v

../rtl/encoder/enc_defines.v
../rtl/encoder/enc_input_cond.v
../rtl/encoder/enc_quad_dec.v
../rtl/encoder/enc_speed_calc.v
../rtl/encoder/enc_core.v
../rtl/encoder/enc_axi_slave.v
../rtl/encoder/enc_top.v

../rtl/pid_controler/pid_defines.v
../rtl/pid_controler/pid_core.v
../rtl/pid_controler/pid_axi_slave.v
../rtl/pid_controler/pid_top.v

../rtl/PWM/myip_v1_0_S00_AXI.v
../rtl/PWM/myip_v1_0.v

# Main Subsystem
../rtl/main_top.v

# Bridges & Memory
../rtl/axi_width_downconverter_ifu.sv
../rtl/axi_width_downconverter_lsu.sv
../rtl/axi_sram_ctrl.sv

# Top SoC
../rtl/soc_top.sv

# UVM VIP Interfaces
VIP/gpio_uvm_tb/gpio_if.sv
VIP/uart_uvm_tb/uart_if.sv
VIP/encoder_uvm_tb/encoder_if.sv
VIP/pwm_uvm_tb/pwm_if.sv

# UVM VIP Packages
VIP/gpio_uvm_tb/gpio_pkg.sv
VIP/uart_uvm_tb/uart_pkg.sv
VIP/encoder_uvm_tb/encoder_pkg.sv
VIP/pwm_uvm_tb/pwm_pkg.sv

# SoC UVM Environment & Test Packages
soc_tb/env/soc_env_pkg.sv
soc_tb/tests/soc_test_pkg.sv

# SoC Top Testbench Module
soc_tb/top/tb_top.sv
