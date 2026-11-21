// =============================================================================
// Project      : Motor-Control SoC - Quadrature Encoder Interface IP
// File         : enc_core.v
// Description  : Quadrature Encoder Interface core.
//
//                Instantiates:
//                  1. enc_input_cond  – 2-flop sync + glitch filter
//                  2. enc_quad_dec    – quadrature decoder (x1/x2/x4)
//                  3. enc_speed_calc  – window, scale, moving-average
//
//                Plus local logic for:
//                  - Signed 32-bit position counter (count_inc/count_dec,
//                    writable via count_load_i / count_load_val_i,
//                    self-clearing COUNT_RESET, index-clear when INDEX_CLR_EN)
//                  - Signed overflow / underflow detection (sticky)
//                  - Index (Z) handling: revolution counter, INDEX_POS capture,
//                    INDEX_CLR_EN, INDEX_SEEN sticky
//                  - Stall detection: STALL_TMO with drive_active gating
//                  - fault_o and inta_o level signals
//
//                Position-counter priority (highest first):
//                  1. COUNT_RESET strobe  → 0
//                  2. count_load_i strobe → count_load_val_i
//                  3. idx_rise & INDEX_CLR_EN → 0
//                  4. dec_inc             → +1 (ENABLE must be 1)
//                  5. dec_dec             → -1 (ENABLE must be 1)
//
//                inta_o uses only EVENT status bits (excludes DIR bit [1]):
//                  inta_o = |(STATUS_EVENTS & IRQ_EN)
//                  STATUS_EVENTS = {INDEX_SEEN[5], STALL[4], ILLEGAL[3],
//                                   OVERFLOW[2], VALID[0]}
//                  (bit 1 DIR is a state, not an event, and is never masked)
//
// Author       : Honours CBP Project
// Created      : 2026-10-06
// Revised      : 2026-10-06  v1.1  Fix index-clear in count; fix inta_o mask
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

module enc_core (
    // Clock and synchronous active-low reset
    input  wire         clk_i,             // system clock
    input  wire         rst_n_i,           // synchronous active-low reset

    // Raw asynchronous encoder inputs
    input  wire         enc_a_i,           // ENC_A (asynchronous)
    input  wire         enc_b_i,           // ENC_B (asynchronous)
    input  wire         enc_index_i,       // ENC_INDEX (asynchronous)

    // External control
    input  wire         drive_active_i,    // hardware drive-active signal

    // -----------------------------------------------------------------------
    // Register interface from enc_axi_slave
    // -----------------------------------------------------------------------
    // Control register bits
    input  wire         reg_enable_i,      // ENABLE
    input  wire         reg_count_rst_i,   // COUNT_RESET (self-clearing write-1)
    input  wire [1:0]   reg_mode_i,        // MODE [3:2]
    input  wire [1:0]   reg_avg_sel_i,     // AVG_SEL [5:4]
    input  wire         reg_swap_ab_i,     // SWAP_AB
    input  wire         reg_idx_clr_en_i,  // INDEX_CLR_EN
    input  wire         reg_drive_assert_i,// DRIVE_ASSERT
    input  wire         reg_fault_en_i,    // FAULT_EN

    // Writable registers
    input  wire [31:0]  reg_window_i,      // ENC_WINDOW
    input  wire [3:0]   reg_filter_i,      // ENC_FILTER [3:0]
    input  wire [31:0]  reg_scale_i,       // ENC_SCALE
    input  wire [31:0]  reg_stall_tmo_i,   // ENC_STALL_TMO
    input  wire [5:0]   reg_irq_en_i,      // ENC_IRQ_EN [5:0]

    // Count load (write to ENC_COUNT)
    input  wire         count_load_i,      // strobe: load count_load_val_i
    input  wire [31:0]  count_load_val_i,  // value to load into position counter

    // Status W1C strobes from AXI slave (clear sticky bits)
    input  wire         w1c_valid_i,       // clear VALID
    input  wire         w1c_overflow_i,    // clear OVERFLOW
    input  wire         w1c_illegal_i,     // clear ILLEGAL
    input  wire         w1c_stall_i,       // clear STALL
    input  wire         w1c_index_seen_i,  // clear INDEX_SEEN

    // -----------------------------------------------------------------------
    // Outputs to enc_axi_slave (register readbacks and status)
    // -----------------------------------------------------------------------
    output reg  [31:0]  count_o,           // ENC_COUNT (position)
    output wire [15:0]  speed_o,           // ENC_SPEED (filtered, from speed_calc)
    output reg  [31:0]  rev_count_o,       // ENC_REV_COUNT
    output reg  [31:0]  index_pos_o,       // ENC_INDEX_POS
    output reg  [31:0]  raw_delta_o,       // ENC_RAW_DELTA
    // Status bits
    output reg          stat_valid_o,      // VALID (sticky)
    output wire         stat_dir_o,        // DIR (live, from decoder)
    output reg          stat_overflow_o,   // OVERFLOW (sticky)
    output reg          stat_illegal_o,    // ILLEGAL (sticky)
    output reg          stat_stall_o,      // STALL (sticky)
    output reg          stat_index_seen_o, // INDEX_SEEN (sticky)
    // Pulse outputs to top level
    output wire         count_valid_o,     // one-cycle pulse: window complete
    output wire         speed_valid_o,     // one-cycle pulse: filtered speed ready
    // Fault and interrupt levels
    output wire         fault_o,           // (ILLEGAL | STALL) & FAULT_EN
    output wire         inta_o             // |(STATUS_EVENTS & IRQ_EN) level
);

// ---------------------------------------------------------------------------
// Internal wires: enc_input_cond outputs
// ---------------------------------------------------------------------------
wire  a_filt;     // conditioned ENC_A
wire  b_filt;     // conditioned ENC_B
wire  idx_filt;   // conditioned ENC_INDEX

enc_input_cond u_input_cond (
    .clk_i      (clk_i),
    .rst_n_i    (rst_n_i),
    .filter_i   (reg_filter_i),
    .a_raw_i    (enc_a_i),
    .b_raw_i    (enc_b_i),
    .idx_raw_i  (enc_index_i),
    .a_filt_o   (a_filt),
    .b_filt_o   (b_filt),
    .idx_filt_o (idx_filt)
);

// ---------------------------------------------------------------------------
// Internal wires: enc_quad_dec outputs
// ---------------------------------------------------------------------------
wire  dec_inc;       // +1 step pulse
wire  dec_dec;       // -1 step pulse
wire  dec_valid;     // legal edge pulse
wire  dec_dir_fwd;   // current direction (1=forward)
wire  dec_illegal;   // illegal transition pulse

enc_quad_dec u_quad_dec (
    .clk_i        (clk_i),
    .rst_n_i      (rst_n_i),
    .enable_i     (reg_enable_i),
    .mode_i       (reg_mode_i),
    .swap_ab_i    (reg_swap_ab_i),
    .a_i          (a_filt),
    .b_i          (b_filt),
    .count_inc_o  (dec_inc),
    .count_dec_o  (dec_dec),
    .edge_valid_o (dec_valid),
    .dir_fwd_o    (dec_dir_fwd),
    .illegal_o    (dec_illegal)
);

// ---------------------------------------------------------------------------
// count_reset strobe: self-clearing COUNT_RESET bit from AXI slave.
// Propagated directly; AXI slave clears it next cycle.
// ---------------------------------------------------------------------------
wire count_rst_strobe;
assign count_rst_strobe = reg_count_rst_i;

// ---------------------------------------------------------------------------
// Internal wires: enc_speed_calc outputs
// ---------------------------------------------------------------------------
wire         spd_count_valid;  // window complete pulse
wire [31:0]  spd_raw_delta;    // raw delta of last window
wire [15:0]  spd_speed;        // filtered speed
wire         spd_speed_valid;  // speed updated pulse

enc_speed_calc u_speed_calc (
    .clk_i          (clk_i),
    .rst_n_i        (rst_n_i),
    .enable_i       (reg_enable_i),
    .count_reset_i  (count_rst_strobe),
    .window_i       (reg_window_i),
    .scale_i        (reg_scale_i),
    .avg_sel_i      (reg_avg_sel_i),
    .count_inc_i    (dec_inc),
    .count_dec_i    (dec_dec),
    .count_valid_o  (spd_count_valid),
    .raw_delta_o    (spd_raw_delta),
    .speed_o        (spd_speed),
    .speed_valid_o  (spd_speed_valid)
);

// Connect pass-through outputs
assign count_valid_o = spd_count_valid;
assign speed_valid_o = spd_speed_valid;
assign speed_o       = spd_speed;
assign stat_dir_o    = dec_dir_fwd;

// ---------------------------------------------------------------------------
// Index rising-edge detection
// idx_rise is gated by reg_enable_i so index events are frozen when disabled.
// ---------------------------------------------------------------------------
reg  idx_prev;  // previous filtered index for edge detection

always @(posedge clk_i)
begin
    if (!rst_n_i)
        idx_prev <= 1'b0;
    else
        idx_prev <= idx_filt;
end

wire idx_rise;  // one-cycle pulse: rising edge of conditioned index, ENABLE=1
assign idx_rise = idx_filt & ~idx_prev & reg_enable_i;

// ---------------------------------------------------------------------------
// Signed 32-bit position counter
//
// Priority (highest to lowest):
//   1. count_rst_strobe             → load 0
//   2. count_load_i                 → load count_load_val_i
//   3. idx_rise & reg_idx_clr_en_i  → load 0  (index clears count)
//   4. dec_inc                      → +1  (only asserted when ENABLE=1)
//   5. dec_dec                      → -1  (only asserted when ENABLE=1)
//
// Signed overflow:
//   +1 overflow: count_o was 0x7FFF_FFFF
//   -1 underflow: count_o was 0x8000_0000
// ---------------------------------------------------------------------------
reg  [31:0]  count_next;     // combinatorial next-count
reg          overflow_this;  // combinatorial: overflow/underflow this cycle

always @(*)
begin
    count_next    = count_o;
    overflow_this = 1'b0;

    if (count_rst_strobe)
    begin
        count_next = 32'h0;
    end
    else if (count_load_i)
    begin
        count_next = count_load_val_i;
    end
    else if (idx_rise & reg_idx_clr_en_i)
    begin
        count_next = 32'h0;   // index clears position; revolution already captured
    end
    else if (dec_inc)
    begin
        count_next    = count_o + 32'h1;
        overflow_this = (count_o == 32'h7FFF_FFFF);
    end
    else if (dec_dec)
    begin
        count_next    = count_o - 32'h1;
        overflow_this = (count_o == 32'h8000_0000);
    end
end

always @(posedge clk_i)
begin
    if (!rst_n_i)
        count_o <= 32'h0;
    else
        count_o <= count_next;
end

// ---------------------------------------------------------------------------
// Raw-delta register: updated when window fires
// ---------------------------------------------------------------------------
always @(posedge clk_i)
begin
    if (!rst_n_i)
        raw_delta_o <= 32'h0;
    else if (spd_count_valid)
        raw_delta_o <= spd_raw_delta;
end

// ---------------------------------------------------------------------------
// Index (Z) handling
// On idx_rise: increment revolution counter and capture current count.
// The count captured is count_o (the value BEFORE any clear this cycle);
// the clear happens simultaneously in the count_next mux but count_o
// still holds the pre-edge value at the sampling edge, so index_pos_o
// captures the correct pre-clear position.
// ---------------------------------------------------------------------------
always @(posedge clk_i)
begin
    if (!rst_n_i)
    begin
        rev_count_o <= 32'h0;
        index_pos_o <= 32'h0;
    end
    else if (idx_rise)
    begin
        rev_count_o <= rev_count_o + 32'h1;
        index_pos_o <= count_o;   // position at the moment of index pulse
    end
end

// ---------------------------------------------------------------------------
// Stall detection
// When drive is active (drive_active_i OR DRIVE_ASSERT) and no valid
// quadrature edge occurs within STALL_TMO consecutive clocks, STALL fires.
// STALL_TMO=0 disables the detector.
// Timer restarts on every valid edge and while drive is inactive.
// ---------------------------------------------------------------------------
wire drive_active;
assign drive_active = drive_active_i | reg_drive_assert_i;

reg  [31:0]  stall_cnt;   // stall elapsed-time counter

// Fires when counter reaches STALL_TMO-1 (STALL_TMO clocks have elapsed)
// and STALL_TMO != 0 and drive is active.
wire stall_fire;
assign stall_fire = (reg_stall_tmo_i != 32'h0) &&
                    (stall_cnt == (reg_stall_tmo_i - 32'h1)) &&
                    drive_active;

always @(posedge clk_i)
begin
    if (!rst_n_i)
    begin
        stall_cnt <= 32'h0;
    end
    else if (!drive_active || dec_valid || count_rst_strobe)
    begin
        stall_cnt <= 32'h0;       // reset: drive gone, valid edge, or count reset
    end
    else if (stall_fire)
    begin
        stall_cnt <= stall_cnt;   // hold at expiry so sticky bit stays asserted
    end
    else
    begin
        stall_cnt <= stall_cnt + 32'h1;
    end
end

// ---------------------------------------------------------------------------
// Sticky status bits
// Rule: new_event wins over simultaneous software W1C clear.
//   sticky <= new_event | (sticky & ~w1c)
// ---------------------------------------------------------------------------

// VALID: new filtered speed sample ready
always @(posedge clk_i)
begin
    if (!rst_n_i)
        stat_valid_o <= 1'b0;
    else
        stat_valid_o <= spd_speed_valid | (stat_valid_o & ~w1c_valid_i);
end

// OVERFLOW: signed 32-bit count wrapped
always @(posedge clk_i)
begin
    if (!rst_n_i)
        stat_overflow_o <= 1'b0;
    else
        stat_overflow_o <= overflow_this | (stat_overflow_o & ~w1c_overflow_i);
end

// ILLEGAL: illegal quadrature transition; count NOT changed (handled in decoder)
always @(posedge clk_i)
begin
    if (!rst_n_i)
        stat_illegal_o <= 1'b0;
    else
        stat_illegal_o <= dec_illegal | (stat_illegal_o & ~w1c_illegal_i);
end

// STALL: drive active with no edges for STALL_TMO clocks
always @(posedge clk_i)
begin
    if (!rst_n_i)
        stat_stall_o <= 1'b0;
    else
        stat_stall_o <= stall_fire | (stat_stall_o & ~w1c_stall_i);
end

// INDEX_SEEN: rising edge of conditioned index detected
always @(posedge clk_i)
begin
    if (!rst_n_i)
        stat_index_seen_o <= 1'b0;
    else
        stat_index_seen_o <= idx_rise | (stat_index_seen_o & ~w1c_index_seen_i);
end

// ---------------------------------------------------------------------------
// Fault output (combinational level)
// fault_o = (ILLEGAL | STALL) & FAULT_EN
// ---------------------------------------------------------------------------
assign fault_o = (stat_illegal_o | stat_stall_o) & reg_fault_en_i;

// ---------------------------------------------------------------------------
// Interrupt output (combinational level)
//
// inta_o = |(STATUS_EVENTS & IRQ_EN)
//
// STATUS_EVENTS uses ONLY the five event bits; DIR (bit 1) is a state
// and is excluded from interrupt generation:
//   bit 5 = INDEX_SEEN
//   bit 4 = STALL
//   bit 3 = ILLEGAL
//   bit 2 = OVERFLOW
//   bit 1 = 1'b0  (DIR excluded)
//   bit 0 = VALID
//
// reg_irq_en_i[1] is accepted from the register but ORed against 1'b0,
// so DIR can never cause an interrupt.
// ---------------------------------------------------------------------------
wire [5:0]  status_events;
assign status_events = {stat_index_seen_o,  // [5]
                        stat_stall_o,        // [4]
                        stat_illegal_o,      // [3]
                        stat_overflow_o,     // [2]
                        1'b0,                // [1] DIR excluded
                        stat_valid_o};       // [0]

assign inta_o = |(status_events & reg_irq_en_i);

endmodule
