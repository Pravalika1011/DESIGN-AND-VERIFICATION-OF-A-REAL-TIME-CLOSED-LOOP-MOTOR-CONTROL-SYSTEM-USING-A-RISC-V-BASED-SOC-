// =============================================================================
// Project      : Motor-Control SoC - Quadrature Encoder Interface IP
// File         : enc_quad_dec.v
// Description  : Quadrature decoder with x1, x2, x4 modes, direction
//                detection, illegal-transition detection, and SWAP_AB support.
//
//                Inputs are the conditioned (synchronized + filtered) signals
//                from enc_input_cond.
//
//                Quadrature truth table (A leads B for forward motion):
//                  Previous  Current  Dir  Valid  Comment
//                  A B       A B
//                  0 0       0 1      R    x4     B rises
//                  0 0       1 0      F    x4     A rises
//                  0 1       0 0      F    x4     B falls
//                  0 1       1 1      R    x4     A rises while B=1
//                  1 0       0 0      R    x4     A falls
//                  1 0       1 1      F    x4     B rises while A=1
//                  1 1       0 1      F    x4     A falls while B=1
//                  1 1       1 0      R    x4     B falls
//                  Any       A!=B!=   --   no     ILLEGAL: both changed
//
//                Mode filtering on top of x4:
//                  x4: all 8 valid transitions count
//                  x2: only transitions where A changes (A edge)
//                  x1: only the rising edge of A counts
//
//                SWAP_AB reverses the notion of forward/reverse by
//                swapping the A and B signals before decoding.
//
//                On ILLEGAL: count unchanged, sticky bit set, decoder
//                state resynced to current A/B.
//
//                ENABLE=0: all outputs held 0, edge_valid_o deasserted.
//
// Outputs:
//   count_inc_o    – +1 step (to enc_core for signed count)
//   count_dec_o    – -1 step (to enc_core for signed count)
//   edge_valid_o   – one-cycle pulse: legal edge occurred
//   dir_fwd_o      – 1=forward, 0=reverse (registered, current direction)
//   illegal_o      – one-cycle pulse: illegal transition occurred
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

module enc_quad_dec (
	// Clock and synchronous active-low reset
	input  wire        clk_i,         // system clock
	input  wire        rst_n_i,       // synchronous active-low reset

	// Control
	input  wire        enable_i,      // ENABLE: 0 = freeze, outputs = 0
	input  wire [1:0]  mode_i,        // quadrature mode: 00=x1, 01=x2, 10/11=x4
	input  wire        swap_ab_i,     // 1 = swap A/B sense

	// Conditioned encoder inputs (from enc_input_cond)
	input  wire        a_i,           // conditioned ENC_A
	input  wire        b_i,           // conditioned ENC_B

	// Outputs
	output reg         count_inc_o,   // +1 step pulse (one clock wide)
	output reg         count_dec_o,   // -1 step pulse (one clock wide)
	output reg         edge_valid_o,  // one-cycle pulse: valid quadrature edge
	output reg         dir_fwd_o,     // registered direction (1=forward)
	output reg         illegal_o      // one-cycle pulse: illegal transition
);

// ---------------------------------------------------------------------------
// SWAP_AB mux – apply before all decoding
// ---------------------------------------------------------------------------
wire  a_eff;    // effective A after possible swap
wire  b_eff;    // effective B after possible swap

assign a_eff = swap_ab_i ? b_i : a_i;
assign b_eff = swap_ab_i ? a_i : b_i;

// ---------------------------------------------------------------------------
// Previous-state registers for edge detection
// ---------------------------------------------------------------------------
reg   a_prev;   // previous clock A value (effective)
reg   b_prev;   // previous clock B value (effective)

always @(posedge clk_i)
begin
	if (!rst_n_i)
	begin
		a_prev <= 1'b0;
		b_prev <= 1'b0;
	end
	else
	begin
		a_prev <= a_eff;
		b_prev <= b_eff;
	end
end

// ---------------------------------------------------------------------------
// Transition decode logic
//
// Encoding: {a_prev, b_prev, a_eff, b_eff}
//
// Only two bits changing at once is a valid quadrature transition.
// Both bits changing together is ILLEGAL.
// No change = no event.
//
// Forward (CW) transitions (A leads B):
//   {0,0 -> 1,0}  AB: 00->10  a_edge, a rising, b=0 -> fwd
//   {1,0 -> 1,1}  AB: 10->11  b_edge, b rising, a=1 -> fwd
//   {1,1 -> 0,1}  AB: 11->01  a_edge, a falling, b=1 -> fwd
//   {0,1 -> 0,0}  AB: 01->00  b_edge, b falling, a=0 -> fwd
//
// Reverse (CCW) transitions (B leads A):
//   {0,0 -> 0,1}  AB: 00->01  b_edge, b rising, a=0 -> rev
//   {0,1 -> 1,1}  AB: 01->11  a_edge, a rising, b=1 -> rev
//   {1,1 -> 1,0}  AB: 11->10  b_edge, b falling, a=1 -> rev
//   {1,0 -> 0,0}  AB: 10->00  a_edge, a falling, b=0 -> rev
// ---------------------------------------------------------------------------

wire a_changed;     // A changed this clock
wire b_changed;     // B changed this clock
wire a_rose;        // A had a rising edge
wire a_fell;        // A had a falling edge

assign a_changed = (a_eff != a_prev);
assign b_changed = (b_eff != b_prev);
assign a_rose    = a_changed & a_eff;
assign a_fell    = a_changed & ~a_eff;

// Decoded direction and edge type from x4 truth table
// fwd=1 for forward, using {a_prev, b_prev, a_eff, b_eff} encoding
wire x4_fwd;        // x4 forward transition
wire x4_rev;        // x4 reverse transition
wire x4_valid;      // exactly one signal changed (no illegal)
wire x4_illegal;    // both A and B changed simultaneously

assign x4_illegal = a_changed & b_changed;
assign x4_valid   = (a_changed ^ b_changed);  // exactly one changed

// Forward: a_rose&~b_prev | b_rose&a_prev | a_fell&b_prev | b_fell&~a_prev
// But simplify using the phase relationship:
// Forward: a leads b. The XOR of the previous B with the new A toggles fwd/rev.
// Standard quadrature direction formula: dir = a_prev XOR b_eff  (for b-edge)
//                                              a_eff  XOR b_prev  (for a-edge)
// Unified: when A changes: fwd = (a_eff XOR b_prev) == 1? fwd : rev
//          when B changes: fwd = (a_prev XOR b_eff) == 0? fwd : rev  (inverted)

// Checking with truth table:
// 00->10: a_changed, a_eff=1, b_prev=0. a_eff^b_prev = 1 -> FWD. Correct.
// 10->11: b_changed, a_prev=1, b_eff=1. a_prev^b_eff = 0 -> FWD (inverted). Correct.
// 11->01: a_changed, a_eff=0, b_prev=1. a_eff^b_prev = 1 -> FWD. Correct.
// 01->00: b_changed, a_prev=0, b_eff=0. a_prev^b_eff = 0 -> FWD (inverted). Correct.
// 00->01: b_changed, a_prev=0, b_eff=1. a_prev^b_eff = 1 -> REV (inverted). Correct.
// 01->11: a_changed, a_eff=1, b_prev=1. a_eff^b_prev = 0 -> REV. Correct.
// 11->10: b_changed, a_prev=1, b_eff=0. a_prev^b_eff = 1 -> REV (inverted). Correct.
// 10->00: a_changed, a_eff=0, b_prev=0. a_eff^b_prev = 0 -> REV. Correct.

// Direction formula:
//  when A changes: fwd = a_eff ^ b_prev   (1=fwd, 0=rev)
//  when B changes: fwd = ~(a_prev ^ b_eff) (1=fwd, 0=rev) = a_prev XNOR b_eff

wire a_edge_fwd;    // forward direction from an A edge
wire b_edge_fwd;    // forward direction from a B edge

assign a_edge_fwd = a_eff ^ b_prev;
assign b_edge_fwd = ~(a_prev ^ b_eff);

assign x4_fwd = x4_valid & (a_changed ? a_edge_fwd : b_edge_fwd);
assign x4_rev = x4_valid & ~(a_changed ? a_edge_fwd : b_edge_fwd);

// ---------------------------------------------------------------------------
// Mode filtering
// x1: only A rising edge
// x2: only A edges (rising and falling)
// x4: all edges
// ---------------------------------------------------------------------------
wire mode_valid;    // this transition is valid for the selected mode

assign mode_valid =
	(mode_i == `ENC_MODE_X4 || mode_i == `ENC_MODE_X4_RSV) ? x4_valid :
	(mode_i == `ENC_MODE_X2)                                ? (x4_valid & a_changed) :
	/* x1 */                                                  (x4_valid & a_rose);

wire mode_fwd;      // direction is forward after mode filter
wire mode_rev;      // direction is reverse after mode filter

assign mode_fwd = mode_valid & x4_fwd;
assign mode_rev = mode_valid & x4_rev;

// ---------------------------------------------------------------------------
// Output registration
// ---------------------------------------------------------------------------
always @(posedge clk_i)
begin
	if (!rst_n_i)
	begin
		count_inc_o  <= 1'b0;
		count_dec_o  <= 1'b0;
		edge_valid_o <= 1'b0;
		dir_fwd_o    <= 1'b0;
		illegal_o    <= 1'b0;
	end
	else if (!enable_i)
	begin
		// ENABLE=0: freeze all counting outputs
		count_inc_o  <= 1'b0;
		count_dec_o  <= 1'b0;
		edge_valid_o <= 1'b0;
		// dir_fwd_o retains last value but driven 0 by enc_core when disabled
		dir_fwd_o    <= dir_fwd_o;
		illegal_o    <= 1'b0;
	end
	else
	begin
		// Check for illegal transition first
		if (x4_illegal)
		begin
			count_inc_o  <= 1'b0;
			count_dec_o  <= 1'b0;
			edge_valid_o <= 1'b0;
			illegal_o    <= 1'b1;
			// dir_fwd_o keeps last value; decoder state (a_prev/b_prev) resyncs
			// automatically next cycle because they always capture a_eff/b_eff
		end
		else
		begin
			count_inc_o  <= mode_fwd;
			count_dec_o  <= mode_rev;
			edge_valid_o <= mode_valid;
			illegal_o    <= 1'b0;
			// Update direction only on valid transitions
			if (mode_valid)
				dir_fwd_o <= x4_fwd;
		end
	end
end

endmodule
