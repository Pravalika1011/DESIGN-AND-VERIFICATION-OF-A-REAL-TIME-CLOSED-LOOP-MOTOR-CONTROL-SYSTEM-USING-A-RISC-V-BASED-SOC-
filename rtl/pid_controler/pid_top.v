// =============================================================================
// Project      : Motor-Control SoC - PID Controller IP
// File         : pid_top.v
// Description  : PID Controller IP – top-level integration module.
//
//                Instantiates:
//                  1. 2-flop asynchronous-assert / synchronous-deassert
//                     reset synchronizer
//                  2. pid_core    – fixed-point PID datapath and FSM
//                  3. pid_axi_slave – Full AXI4 register file and interface
//
//                Exposes:
//                  - Full AXI4 slave bus interface (all 5 channels)
//                  - PID external ports: tick_i, actual_i, pid_out_o,
//                    pid_out_valid_o, sat_flag_o
//                  - Level interrupt output: inta_o
//
//                Interrupt source:
//                  inta_o is driven from pid_axi_slave's irq_o output,
//                  which is: (w1c_done | w1c_overrun) & ctrl_irq_en.
//                  The interrupt remains asserted until software clears the
//                  sticky DONE and/or OVERRUN bits via W1C writes.
//
//                Reset synchronizer:
//                  s_axi_aresetn asserts asynchronously (immediately clears
//                  FFs on the falling edge) and deasserts synchronously
//                  through two pipeline FFs.  Both pid_core and pid_axi_slave
//                  receive the synchronized rst_n_sync.
//
// Parameters   :
//   DATA_WIDTH = 32, ADDR_WIDTH = 32, ID_WIDTH = 8
//   SPEED_W = 16, OUT_W = 16, GAIN_W = 32, FRAC = 16
//   ERR_W = 17, DERIV_W = 18, PROD_W = 50, ACC_W = 54
//
// DO NOT INTEGRATE INTO SoC YET.
// Base address assignment will be provided separately.
//
// Author       : Honours CBP Project
// Created      : 2026-10-03
// Revised      : 2026-10-03  v1.1  inta_o from sticky irq_o, sat_flag_o port,
//                                   motor-control header, MIT license
//
// License (MIT):
//   Copyright (c) 2026 Honours CBP Project
//   Permission is hereby granted, free of charge, to any person obtaining a
//   copy of this software and associated documentation files (the "Software"),
//   to deal in the Software without restriction, including without limitation
//   the rights to use, copy, modify, merge, publish, distribute, sublicense,
//   and/or sell copies of the Software, and to permit persons to whom the
//   Software is furnished to do so, subject to the following conditions:
//   The above copyright notice and this permission notice shall be included in
//   all copies or substantial portions of the Software.
//   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
// =============================================================================

`include "pid_defines.v"

module pid_top #(
	parameter DATA_WIDTH = 32,   // AXI data width
	parameter ADDR_WIDTH = 32,   // AXI address width
	parameter ID_WIDTH   = 8,    // AXI ID width
	parameter SPEED_W    = 16,   // speed / setpoint width
	parameter OUT_W      = 16,   // PID output width
	parameter GAIN_W     = 32,   // Q16.16 gain width
	parameter FRAC       = 16,   // fractional bits
	parameter ERR_W      = 17,   // SPEED_W + 1
	parameter DERIV_W    = 18,   // ERR_W + 1  (18-bit derivative)
	parameter PROD_W     = 50,   // GAIN_W + DERIV_W
	parameter ACC_W      = 54    // PROD_W + 4
) (
	// -------------------------------------------------------------------
	// Global AXI4 signals
	// -------------------------------------------------------------------
	input  wire                        s_axi_aclk,     // AXI clock
	input  wire                        s_axi_aresetn,  // AXI reset, active-low async

	// -------------------------------------------------------------------
	// AXI4 Write Address Channel
	// -------------------------------------------------------------------
	input  wire [ID_WIDTH-1:0]          s_axi_awid,
	input  wire [ADDR_WIDTH-1:0]        s_axi_awaddr,
	input  wire [7:0]                   s_axi_awlen,
	input  wire [2:0]                   s_axi_awsize,
	input  wire [1:0]                   s_axi_awburst,
	input  wire                         s_axi_awlock,
	input  wire [3:0]                   s_axi_awcache,
	input  wire [2:0]                   s_axi_awprot,
	input  wire                         s_axi_awvalid,
	output wire                         s_axi_awready,

	// -------------------------------------------------------------------
	// AXI4 Write Data Channel
	// -------------------------------------------------------------------
	input  wire [DATA_WIDTH-1:0]        s_axi_wdata,
	input  wire [(DATA_WIDTH/8)-1:0]    s_axi_wstrb,
	input  wire                         s_axi_wlast,
	input  wire                         s_axi_wvalid,
	output wire                         s_axi_wready,

	// -------------------------------------------------------------------
	// AXI4 Write Response Channel
	// -------------------------------------------------------------------
	output wire [ID_WIDTH-1:0]          s_axi_bid,
	output wire [1:0]                   s_axi_bresp,
	output wire                         s_axi_bvalid,
	input  wire                         s_axi_bready,

	// -------------------------------------------------------------------
	// AXI4 Read Address Channel
	// -------------------------------------------------------------------
	input  wire [ID_WIDTH-1:0]          s_axi_arid,
	input  wire [ADDR_WIDTH-1:0]        s_axi_araddr,
	input  wire [7:0]                   s_axi_arlen,
	input  wire [2:0]                   s_axi_arsize,
	input  wire [1:0]                   s_axi_arburst,
	input  wire                         s_axi_arlock,
	input  wire [3:0]                   s_axi_arcache,
	input  wire [2:0]                   s_axi_arprot,
	input  wire                         s_axi_arvalid,
	output wire                         s_axi_arready,

	// -------------------------------------------------------------------
	// AXI4 Read Data Channel
	// -------------------------------------------------------------------
	output wire [ID_WIDTH-1:0]          s_axi_rid,
	output wire [DATA_WIDTH-1:0]        s_axi_rdata,
	output wire [1:0]                   s_axi_rresp,
	output wire                         s_axi_rlast,
	output wire                         s_axi_rvalid,
	input  wire                         s_axi_rready,

	// -------------------------------------------------------------------
	// PID external ports
	// -------------------------------------------------------------------
	input  wire                         tick_i,          // periodic update tick
	input  wire [SPEED_W-1:0]           actual_i,         // measured speed (signed)
	output wire [OUT_W-1:0]             pid_out_o,        // PID output (signed)
	output wire                         pid_out_valid_o,  // one-cycle valid pulse
	output wire                         sat_flag_o,       // level: last update saturated

	// -------------------------------------------------------------------
	// Interrupt output
	// inta_o = (sticky_DONE | sticky_OVERRUN) & IRQ_EN (level)
	// Driven from pid_axi_slave.irq_o.  Deasserts when software clears
	// the sticky DONE/OVERRUN bits or when IRQ_EN = 0.
	// -------------------------------------------------------------------
	output wire                         inta_o
);

// ---------------------------------------------------------------------------
// Derived parameters
// ---------------------------------------------------------------------------
localparam STRB_WIDTH = DATA_WIDTH / 8; // = 4

// ---------------------------------------------------------------------------
// 2-flop reset synchronizer
// Async assert (negedge s_axi_aresetn), sync deassert (posedge s_axi_aclk).
// ---------------------------------------------------------------------------
reg rst_meta_n;  // first synchronizer FF
reg rst_n_sync;  // second synchronizer FF – distributed to all submodules

// generate 2-flop reset synchronizer
always @(posedge s_axi_aclk or negedge s_axi_aresetn)
begin
	if (!s_axi_aresetn)
	begin
		rst_meta_n <= 1'b0;
		rst_n_sync <= 1'b0;
	end
	else
	begin
		rst_meta_n <= 1'b1;
		rst_n_sync <= rst_meta_n;
	end
end

// ---------------------------------------------------------------------------
// Internal wires: pid_axi_slave -> pid_core (register values)
// ---------------------------------------------------------------------------
wire [SPEED_W-1:0]  w_setpoint;
wire [GAIN_W-1:0]   w_kp;
wire [GAIN_W-1:0]   w_ki;
wire [GAIN_W-1:0]   w_kd;
wire                w_enable;
wire                w_int_reset;
wire                w_manual_upd;
wire                w_d_on_meas;
wire                w_aw_en;
wire                w_reg_irq_en;
wire [OUT_W-1:0]    w_out_max;
wire [OUT_W-1:0]    w_out_min;
wire [31:0]         w_int_max;
wire [31:0]         w_int_min;

// ---------------------------------------------------------------------------
// Internal wires: pid_core -> pid_axi_slave (status / readback)
// ---------------------------------------------------------------------------
wire [OUT_W-1:0]    w_core_out;     // PID output readback
wire                w_core_busy;    // BUSY status
wire                w_core_done;    // DONE one-cycle pulse
wire                w_core_sat_hi;  // SAT_HI one-cycle pulse
wire                w_core_sat_lo;  // SAT_LO one-cycle pulse
wire                w_core_int_sat; // INT_SAT one-cycle pulse
wire                w_core_overrun; // OVERRUN one-cycle pulse
wire [ERR_W-1:0]    w_core_error;   // error readback
wire [SPEED_W-1:0]  w_core_actual;  // latched actual readback

// irq_o from slave drives inta_o at the top level
wire                w_irq;          // (sticky_DONE | sticky_OVERRUN) & IRQ_EN

assign inta_o    = w_irq;
assign w_core_out = pid_out_o;  // pid_out_o is driven by pid_core directly

// ---------------------------------------------------------------------------
// pid_core instance
// ---------------------------------------------------------------------------
pid_core #(
	.SPEED_W (SPEED_W),
	.OUT_W   (OUT_W),
	.GAIN_W  (GAIN_W),
	.FRAC    (FRAC),
	.ERR_W   (ERR_W),
	.DERIV_W (DERIV_W),
	.PROD_W  (PROD_W),
	.ACC_W   (ACC_W)
) u_pid_core (
	.clk_i           (s_axi_aclk),
	.rst_n_i         (rst_n_sync),
	// Control
	.enable_i        (w_enable),
	.int_reset_i     (w_int_reset),
	.manual_upd_i    (w_manual_upd),
	.d_on_meas_i     (w_d_on_meas),
	.aw_en_i         (w_aw_en),
	.tick_i          (tick_i),
	// Setpoint and feedback
	.setpoint_i      (w_setpoint),
	.actual_i        (actual_i),
	// Gains
	.kp_i            (w_kp),
	.ki_i            (w_ki),
	.kd_i            (w_kd),
	// Limits
	.out_max_i       (w_out_max),
	.out_min_i       (w_out_min),
	.int_max_i       (w_int_max),
	.int_min_i       (w_int_min),
	// Outputs
	.pid_out_o       (pid_out_o),
	.pid_out_valid_o (pid_out_valid_o),
	.error_o         (w_core_error),
	.actual_o        (w_core_actual),
	.sat_flag_o      (sat_flag_o),
	// Status pulses
	.busy_o          (w_core_busy),
	.done_o          (w_core_done),
	.sat_hi_o        (w_core_sat_hi),
	.sat_lo_o        (w_core_sat_lo),
	.int_sat_o       (w_core_int_sat),
	.overrun_o       (w_core_overrun)
);

// ---------------------------------------------------------------------------
// pid_axi_slave instance
// ---------------------------------------------------------------------------
pid_axi_slave #(
	.DATA_WIDTH (DATA_WIDTH),
	.ADDR_WIDTH (ADDR_WIDTH),
	.ID_WIDTH   (ID_WIDTH),
	.STRB_WIDTH (STRB_WIDTH)
) u_pid_axi_slave (
	.clk_i              (s_axi_aclk),
	.rst_n_i            (rst_n_sync),
	// Write Address
	.s_axi_awid         (s_axi_awid),
	.s_axi_awaddr       (s_axi_awaddr),
	.s_axi_awlen        (s_axi_awlen),
	.s_axi_awsize       (s_axi_awsize),
	.s_axi_awburst      (s_axi_awburst),
	.s_axi_awlock       (s_axi_awlock),
	.s_axi_awcache      (s_axi_awcache),
	.s_axi_awprot       (s_axi_awprot),
	.s_axi_awvalid      (s_axi_awvalid),
	.s_axi_awready      (s_axi_awready),
	// Write Data
	.s_axi_wdata        (s_axi_wdata),
	.s_axi_wstrb        (s_axi_wstrb),
	.s_axi_wlast        (s_axi_wlast),
	.s_axi_wvalid       (s_axi_wvalid),
	.s_axi_wready       (s_axi_wready),
	// Write Response
	.s_axi_bid          (s_axi_bid),
	.s_axi_bresp        (s_axi_bresp),
	.s_axi_bvalid       (s_axi_bvalid),
	.s_axi_bready       (s_axi_bready),
	// Read Address
	.s_axi_arid         (s_axi_arid),
	.s_axi_araddr       (s_axi_araddr),
	.s_axi_arlen        (s_axi_arlen),
	.s_axi_arsize       (s_axi_arsize),
	.s_axi_arburst      (s_axi_arburst),
	.s_axi_arlock       (s_axi_arlock),
	.s_axi_arcache      (s_axi_arcache),
	.s_axi_arprot       (s_axi_arprot),
	.s_axi_arvalid      (s_axi_arvalid),
	.s_axi_arready      (s_axi_arready),
	// Read Data
	.s_axi_rid          (s_axi_rid),
	.s_axi_rdata        (s_axi_rdata),
	.s_axi_rresp        (s_axi_rresp),
	.s_axi_rlast        (s_axi_rlast),
	.s_axi_rvalid       (s_axi_rvalid),
	.s_axi_rready       (s_axi_rready),
	// Register outputs to core
	.reg_setpoint_o     (w_setpoint),
	.reg_kp_o           (w_kp),
	.reg_ki_o           (w_ki),
	.reg_kd_o           (w_kd),
	.reg_enable_o       (w_enable),
	.reg_int_reset_o    (w_int_reset),
	.reg_manual_upd_o   (w_manual_upd),
	.reg_d_on_meas_o    (w_d_on_meas),
	.reg_aw_en_o        (w_aw_en),
	.reg_irq_en_o       (w_reg_irq_en),
	.reg_out_max_o      (w_out_max),
	.reg_out_min_o      (w_out_min),
	.reg_int_max_o      (w_int_max),
	.reg_int_min_o      (w_int_min),
	// Status / readback from core
	.core_out_i         (w_core_out),
	.core_busy_i        (w_core_busy),
	.core_done_i        (w_core_done),
	.core_sat_hi_i      (w_core_sat_hi),
	.core_sat_lo_i      (w_core_sat_lo),
	.core_int_sat_i     (w_core_int_sat),
	.core_overrun_i     (w_core_overrun),
	.core_error_i       (w_core_error),
	.core_actual_i      (w_core_actual),
	// Interrupt output
	.irq_o              (w_irq)
);

endmodule
