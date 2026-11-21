`timescale 1ns / 1ps

// ============================================================================
// Module: tb_top
// Top-Level Testbench Module for SoC Overall UVM Verification
// ============================================================================

module tb_top;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import gpio_pkg::*;
  import uart_pkg::*;
  import encoder_pkg::*;
  import pwm_pkg::*;
  import soc_env_pkg::*;
  import soc_test_pkg::*;

  // Clock and Reset Signals
  logic clk;
  logic fixed_clk;
  logic rst;

  // 100 MHz System Clock (10ns period)
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  // 50 MHz UART Baud Clock (20ns period)
  initial begin
    fixed_clk = 1'b0;
    forever #10 fixed_clk = ~fixed_clk;
  end

  // Active-High Reset Generation
  initial begin
    rst = 1'b1;
    #100;
    @(posedge clk);
    rst = 1'b0;
  end

  // Waveform Dump Instrumentation for Verdi Visualization
  initial begin
    $dumpfile("soc_base_test.vcd");
    $dumpvars(0, tb_top);
`ifdef FSDB
    $fsdbDumpfile("soc_base_test.fsdb");
    $fsdbDumpvars(0, tb_top);
`endif
  end

  // Virtual Interfaces instantiation
  gpio_if    gpio_vif();
  uart_if    uart_vif();
  encoder_if encoder_vif();
  pwm_if     pwm_vif();

  // Connect clock and reset to interfaces
  assign gpio_vif.clk    = clk;
  assign gpio_vif.rst    = rst;

  assign uart_vif.clk    = clk;
  assign uart_vif.rst    = rst;

  assign encoder_vif.clk = clk;
  assign encoder_vif.rst = rst;

  assign pwm_vif.clk     = clk;
  assign pwm_vif.rst     = rst;

  // Exact UVM Configuration DB Registrations
  initial begin
    uvm_config_db #(virtual gpio_if)::set(
      null,
      "uvm_test_top.env.gpio_agent",
      "vif",
      gpio_vif
    );

    uvm_config_db #(virtual uart_if)::set(
      null,
      "uvm_test_top.env.uart_agent",
      "vif",
      uart_vif
    );

    uvm_config_db #(virtual encoder_if)::set(
      null,
      "uvm_test_top.env.encoder_agent",
      "vif",
      encoder_vif
    );

    uvm_config_db #(virtual pwm_if)::set(
      null,
      "uvm_test_top.env.pwm_agent",
      "vif",
      pwm_vif
    );

    run_test("soc_base_test");
  end

  // SoC DUT Instantiation
  soc_top #(
    .DATA_WIDTH       (32),
    .ADDR_WIDTH       (32),
    .ID_WIDTH         (8),
    .USE_INTERNAL_MEM (1)
  ) u_dut (
    .clk                    (clk),
    .fixed_clk              (fixed_clk),
    .rst                    (rst),

    // UART
    .uart_rx                (uart_vif.uart_rx),
    .uart_tx                (uart_vif.uart_tx),
    .uart_irq               (uart_vif.uart_irq),

    // PWM
    .PWM_OUT                (pwm_vif.PWM_OUT),

    // GPIO
    .gpio_io                (gpio_vif.gpio_io),
    .gpio_intr              (gpio_vif.gpio_intr),

    // Timer (Tied off for external peripheral VIP smoke test)
    .timer_ext_meas         (1'b0),
    .timer_capture          (1'b0),
    .timer_pwm              (),
    .timer_trigger          (),
    .timer_intr             (),

    // Quadrature Encoder
    .enc_a                  (encoder_vif.enc_a),
    .enc_b                  (encoder_vif.enc_b),
    .enc_index              (encoder_vif.enc_index),
    .enc_drive_active       (encoder_vif.enc_drive_active),
    .enc_speed              (encoder_vif.enc_speed),
    .enc_speed_valid        (encoder_vif.enc_speed_valid),
    .enc_count_valid        (encoder_vif.enc_count_valid),
    .enc_dir                (encoder_vif.enc_dir),
    .enc_fault              (encoder_vif.enc_fault),
    .enc_intr               (encoder_vif.enc_intr),

    // PID (Unconnected in peripheral VIP testbench)
    .pid_out                (),
    .pid_out_valid          (),
    .pid_sat_flag           (),
    .pid_intr               (),

    // Preserved DMA Master M2 (Tied off inactive)
    .s02_axi_awid           ('0),
    .s02_axi_awaddr         ('0),
    .s02_axi_awlen          ('0),
    .s02_axi_awsize         (3'b010),
    .s02_axi_awburst        (2'b01),
    .s02_axi_awlock         (1'b0),
    .s02_axi_awcache        ('0),
    .s02_axi_awprot         ('0),
    .s02_axi_awqos          ('0),
    .s02_axi_awuser         (1'b0),
    .s02_axi_awvalid        (1'b0),
    .s02_axi_awready        (),
    .s02_axi_wdata          ('0),
    .s02_axi_wstrb          ('0),
    .s02_axi_wlast          (1'b0),
    .s02_axi_wuser          (1'b0),
    .s02_axi_wvalid         (1'b0),
    .s02_axi_wready         (),
    .s02_axi_bid            (),
    .s02_axi_bresp          (),
    .s02_axi_buser          (),
    .s02_axi_bvalid         (),
    .s02_axi_bready         (1'b0),
    .s02_axi_arid           ('0),
    .s02_axi_araddr         ('0),
    .s02_axi_arlen          ('0),
    .s02_axi_arsize         (3'b010),
    .s02_axi_arburst        (2'b01),
    .s02_axi_arlock         (1'b0),
    .s02_axi_arcache        ('0),
    .s02_axi_arprot         ('0),
    .s02_axi_arqos          ('0),
    .s02_axi_aruser         (1'b0),
    .s02_axi_arvalid        (1'b0),
    .s02_axi_arready        (),
    .s02_axi_rid            (),
    .s02_axi_rdata          (),
    .s02_axi_rresp          (),
    .s02_axi_rlast          (),
    .s02_axi_ruser          (),
    .s02_axi_rvalid         (),
    .s02_axi_rready         (1'b0),

    // Core Trace
    .trace_rv_i_insn_ip     (),
    .trace_rv_i_address_ip  (),
    .trace_rv_i_valid_ip    (),
    .trace_rv_i_exception_ip(),
    .trace_rv_i_interrupt_ip(),
    .o_cpu_halt_status      (),
    .o_debug_mode_status    ()
  );

endmodule
