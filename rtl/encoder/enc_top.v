// =============================================================================
// Project      : Motor-Control SoC - Quadrature Encoder Interface IP
// File         : enc_top.v
// Description  : QEI Encoder IP – top-level integration module.
//
//                Instantiates:
//                  1. 2-flop asynchronous-assert / synchronous-deassert
//                     reset synchronizer
//                  2. enc_axi_slave  – Full AXI4 register file and interface
//                  3. enc_core       – input cond, decoder, speed calc, counters
//
//                External ports:
//                  - Full AXI4 slave interface (same list as pid_top.v)
//                  - Encoder inputs: enc_a_i, enc_b_i, enc_index_i
//                  - Drive monitor: drive_active_i
//                  - Sideband outputs: speed_o, speed_valid_o, count_valid_o,
//                    dir_o, fault_o, inta_o
//
//                Unused AXI sideband inputs (accepted, not decoded):
//                  awburst, awlock, awcache, awprot,
//                  arburst, arlock, arcache, arprot
//
//                Reset synchronizer:
//                  s_axi_aresetn asserts asynchronously and deasserts
//                  synchronously through two pipeline FFs; both sub-modules
//                  receive rst_n_sync.
//
// Author       : Honours CBP Project
// Created      : 2026-10-06
// Revised      : 2026-10-06  v1.0  Initial release
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

`include "enc_defines.v"

module enc_top #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH   = 8
) (
    // -------------------------------------------------------------------
    // Global AXI4 signals
    // -------------------------------------------------------------------
    input  wire                         s_axi_aclk,
    input  wire                         s_axi_aresetn,  // active-low, async assert

    // -------------------------------------------------------------------
    // AXI4 Write Address Channel
    // -------------------------------------------------------------------
    input  wire [ID_WIDTH-1:0]          s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]        s_axi_awaddr,
    input  wire [7:0]                   s_axi_awlen,
    input  wire [2:0]                   s_axi_awsize,
    input  wire [1:0]                   s_axi_awburst,  // accepted; not used
    input  wire                         s_axi_awlock,   // accepted; not used
    input  wire [3:0]                   s_axi_awcache,  // accepted; not used
    input  wire [2:0]                   s_axi_awprot,   // accepted; not used
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
    input  wire [1:0]                   s_axi_arburst,  // accepted; not used
    input  wire                         s_axi_arlock,   // accepted; not used
    input  wire [3:0]                   s_axi_arcache,  // accepted; not used
    input  wire [2:0]                   s_axi_arprot,   // accepted; not used
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
    // Encoder physical inputs
    // -------------------------------------------------------------------
    input  wire                         enc_a_i,         // ENC_A (asynchronous)
    input  wire                         enc_b_i,         // ENC_B (asynchronous)
    input  wire                         enc_index_i,     // ENC_INDEX (asynchronous)
    input  wire                         drive_active_i,  // hardware drive-active

    // -------------------------------------------------------------------
    // Sideband outputs
    // -------------------------------------------------------------------
    output wire [15:0]                  speed_o,         // signed filtered speed
    output wire                         speed_valid_o,   // one-cycle pulse
    output wire                         count_valid_o,   // one-cycle pulse
    output wire                         dir_o,           // current direction
    output wire                         fault_o,         // (ILLEGAL|STALL)&FAULT_EN
    output wire                         inta_o           // |(STATUS_EVENTS & IRQ_EN)
);

// ---------------------------------------------------------------------------
// Derived parameter
// ---------------------------------------------------------------------------
localparam STRB_WIDTH = DATA_WIDTH / 8;

// ---------------------------------------------------------------------------
// 2-flop reset synchronizer
// Async assert (negedge s_axi_aresetn), sync deassert (posedge s_axi_aclk).
// ---------------------------------------------------------------------------
reg rst_meta_n;  // first synchronizer FF
reg rst_n_sync;  // second synchronizer FF – distributed to sub-modules

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
// Internal wires: enc_axi_slave -> enc_core (register outputs)
// ---------------------------------------------------------------------------
wire         w_reg_enable;
wire         w_reg_count_rst;
wire [1:0]   w_reg_mode;
wire [1:0]   w_reg_avg_sel;
wire         w_reg_swap_ab;
wire         w_reg_idx_clr_en;
wire         w_reg_drive_assert;
wire         w_reg_fault_en;
wire [31:0]  w_reg_window;
wire [3:0]   w_reg_filter;
wire [31:0]  w_reg_scale;
wire [31:0]  w_reg_stall_tmo;
wire [5:0]   w_reg_irq_en;
wire         w_count_load;
wire [31:0]  w_count_load_val;
wire         w_w1c_valid;
wire         w_w1c_overflow;
wire         w_w1c_illegal;
wire         w_w1c_stall;
wire         w_w1c_index_seen;

// ---------------------------------------------------------------------------
// Internal wires: enc_core -> enc_axi_slave (readback)
// ---------------------------------------------------------------------------
wire [31:0]  w_count;
wire [15:0]  w_speed;
wire [31:0]  w_rev_count;
wire [31:0]  w_index_pos;
wire [31:0]  w_raw_delta;
wire         w_stat_valid;
wire         w_stat_dir;
wire         w_stat_overflow;
wire         w_stat_illegal;
wire         w_stat_stall;
wire         w_stat_index_seen;

// ---------------------------------------------------------------------------
// enc_axi_slave instance
// ---------------------------------------------------------------------------
enc_axi_slave #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH),
    .ID_WIDTH   (ID_WIDTH),
    .STRB_WIDTH (STRB_WIDTH)
) u_enc_axi_slave (
    .clk_i                (s_axi_aclk),
    .rst_n_i              (rst_n_sync),
    // Write Address
    .s_axi_awid           (s_axi_awid),
    .s_axi_awaddr         (s_axi_awaddr),
    .s_axi_awlen          (s_axi_awlen),
    .s_axi_awsize         (s_axi_awsize),
    .s_axi_awburst        (s_axi_awburst),
    .s_axi_awlock         (s_axi_awlock),
    .s_axi_awcache        (s_axi_awcache),
    .s_axi_awprot         (s_axi_awprot),
    .s_axi_awvalid        (s_axi_awvalid),
    .s_axi_awready        (s_axi_awready),
    // Write Data
    .s_axi_wdata          (s_axi_wdata),
    .s_axi_wstrb          (s_axi_wstrb),
    .s_axi_wlast          (s_axi_wlast),
    .s_axi_wvalid         (s_axi_wvalid),
    .s_axi_wready         (s_axi_wready),
    // Write Response
    .s_axi_bid            (s_axi_bid),
    .s_axi_bresp          (s_axi_bresp),
    .s_axi_bvalid         (s_axi_bvalid),
    .s_axi_bready         (s_axi_bready),
    // Read Address
    .s_axi_arid           (s_axi_arid),
    .s_axi_araddr         (s_axi_araddr),
    .s_axi_arlen          (s_axi_arlen),
    .s_axi_arsize         (s_axi_arsize),
    .s_axi_arburst        (s_axi_arburst),
    .s_axi_arlock         (s_axi_arlock),
    .s_axi_arcache        (s_axi_arcache),
    .s_axi_arprot         (s_axi_arprot),
    .s_axi_arvalid        (s_axi_arvalid),
    .s_axi_arready        (s_axi_arready),
    // Read Data
    .s_axi_rid            (s_axi_rid),
    .s_axi_rdata          (s_axi_rdata),
    .s_axi_rresp          (s_axi_rresp),
    .s_axi_rlast          (s_axi_rlast),
    .s_axi_rvalid         (s_axi_rvalid),
    .s_axi_rready         (s_axi_rready),
    // Register outputs to enc_core
    .reg_enable_o         (w_reg_enable),
    .reg_count_rst_o      (w_reg_count_rst),
    .reg_mode_o           (w_reg_mode),
    .reg_avg_sel_o        (w_reg_avg_sel),
    .reg_swap_ab_o        (w_reg_swap_ab),
    .reg_idx_clr_en_o     (w_reg_idx_clr_en),
    .reg_drive_assert_o   (w_reg_drive_assert),
    .reg_fault_en_o       (w_reg_fault_en),
    .reg_window_o         (w_reg_window),
    .reg_filter_o         (w_reg_filter),
    .reg_scale_o          (w_reg_scale),
    .reg_stall_tmo_o      (w_reg_stall_tmo),
    .reg_irq_en_o         (w_reg_irq_en),
    .count_load_o         (w_count_load),
    .count_load_val_o     (w_count_load_val),
    .w1c_valid_o          (w_w1c_valid),
    .w1c_overflow_o       (w_w1c_overflow),
    .w1c_illegal_o        (w_w1c_illegal),
    .w1c_stall_o          (w_w1c_stall),
    .w1c_index_seen_o     (w_w1c_index_seen),
    // Readback from enc_core
    .count_i              (w_count),
    .speed_i              (w_speed),
    .rev_count_i          (w_rev_count),
    .index_pos_i          (w_index_pos),
    .raw_delta_i          (w_raw_delta),
    .stat_valid_i         (w_stat_valid),
    .stat_dir_i           (w_stat_dir),
    .stat_overflow_i      (w_stat_overflow),
    .stat_illegal_i       (w_stat_illegal),
    .stat_stall_i         (w_stat_stall),
    .stat_index_seen_i    (w_stat_index_seen)
);

// ---------------------------------------------------------------------------
// enc_core instance
// ---------------------------------------------------------------------------
enc_core u_enc_core (
    .clk_i                (s_axi_aclk),
    .rst_n_i              (rst_n_sync),
    // Encoder inputs
    .enc_a_i              (enc_a_i),
    .enc_b_i              (enc_b_i),
    .enc_index_i          (enc_index_i),
    .drive_active_i       (drive_active_i),
    // Register interface
    .reg_enable_i         (w_reg_enable),
    .reg_count_rst_i      (w_reg_count_rst),
    .reg_mode_i           (w_reg_mode),
    .reg_avg_sel_i        (w_reg_avg_sel),
    .reg_swap_ab_i        (w_reg_swap_ab),
    .reg_idx_clr_en_i     (w_reg_idx_clr_en),
    .reg_drive_assert_i   (w_reg_drive_assert),
    .reg_fault_en_i       (w_reg_fault_en),
    .reg_window_i         (w_reg_window),
    .reg_filter_i         (w_reg_filter),
    .reg_scale_i          (w_reg_scale),
    .reg_stall_tmo_i      (w_reg_stall_tmo),
    .reg_irq_en_i         (w_reg_irq_en),
    .count_load_i         (w_count_load),
    .count_load_val_i     (w_count_load_val),
    .w1c_valid_i          (w_w1c_valid),
    .w1c_overflow_i       (w_w1c_overflow),
    .w1c_illegal_i        (w_w1c_illegal),
    .w1c_stall_i          (w_w1c_stall),
    .w1c_index_seen_i     (w_w1c_index_seen),
    // Outputs to AXI slave
    .count_o              (w_count),
    .speed_o              (w_speed),
    .rev_count_o          (w_rev_count),
    .index_pos_o          (w_index_pos),
    .raw_delta_o          (w_raw_delta),
    .stat_valid_o         (w_stat_valid),
    .stat_dir_o           (w_stat_dir),
    .stat_overflow_o      (w_stat_overflow),
    .stat_illegal_o       (w_stat_illegal),
    .stat_stall_o         (w_stat_stall),
    .stat_index_seen_o    (w_stat_index_seen),
    // Top-level sideband
    .count_valid_o        (count_valid_o),
    .speed_valid_o        (speed_valid_o),
    .fault_o              (fault_o),
    .inta_o               (inta_o)
);

// Direction and speed outputs driven from internal wires
assign dir_o   = w_stat_dir;
assign speed_o = w_speed;

endmodule
