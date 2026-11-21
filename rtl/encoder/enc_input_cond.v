// =============================================================================
// Project      : Motor-Control SoC - Quadrature Encoder Interface IP
// File         : enc_input_cond.v
// Description  : Input conditioning for ENC_A, ENC_B, and ENC_INDEX.
//
//                Each channel passes through:
//                  1. 2-flop synchronizer (eliminates metastability)
//                  2. Glitch filter: a change is accepted only after the new
//                     value has been stable for FILTER_CYCLES clock cycles.
//                     FILTER_CYCLES = 0 bypasses the filter (pure 2-flop sync).
//                     Maximum filter depth: 15 (4-bit field).
//
//                The module is purely structural/RTL with no latches.
//                All outputs are registered and valid one clock after the
//                filtered value stabilises.
//
// Parameters   : none (FILTER_CYCLES is a runtime register input)
//
// Ports:
//   clk_i           – system clock
//   rst_n_i         – synchronous active-low reset
//   filter_i [3:0]  – glitch filter depth (0 = bypass; max 15)
//   a_raw_i         – asynchronous ENC_A input
//   b_raw_i         – asynchronous ENC_B input
//   idx_raw_i       – asynchronous ENC_INDEX input
//   a_filt_o        – conditioned ENC_A output
//   b_filt_o        – conditioned ENC_B output
//   idx_filt_o      – conditioned ENC_INDEX output
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

module enc_input_cond (
	// Clock and synchronous active-low reset
	input  wire        clk_i,         // system clock
	input  wire        rst_n_i,       // synchronous active-low reset

	// Glitch filter depth (from ENC_FILTER register bits [3:0])
	input  wire [3:0]  filter_i,      // 0 = bypass, 1-15 = stable cycles required

	// Raw asynchronous encoder inputs
	input  wire        a_raw_i,       // ENC_A (asynchronous)
	input  wire        b_raw_i,       // ENC_B (asynchronous)
	input  wire        idx_raw_i,     // ENC_INDEX (asynchronous)

	// Conditioned (synchronized + filtered) outputs
	output reg         a_filt_o,      // conditioned ENC_A
	output reg         b_filt_o,      // conditioned ENC_B
	output reg         idx_filt_o     // conditioned ENC_INDEX
);

// ---------------------------------------------------------------------------
// 2-flop synchronizer for each channel
// ---------------------------------------------------------------------------
reg a_meta;     // ENC_A metastability FF1
reg a_sync;     // ENC_A metastability FF2
reg b_meta;     // ENC_B metastability FF1
reg b_sync;     // ENC_B metastability FF2
reg idx_meta;   // INDEX metastability FF1
reg idx_sync;   // INDEX metastability FF2

// ENC_A 2-flop synchronizer
always @(posedge clk_i)
begin
	if (!rst_n_i)
	begin
		a_meta <= 1'b0;
		a_sync <= 1'b0;
	end
	else
	begin
		a_meta <= a_raw_i;
		a_sync <= a_meta;
	end
end

// ENC_B 2-flop synchronizer
always @(posedge clk_i)
begin
	if (!rst_n_i)
	begin
		b_meta <= 1'b0;
		b_sync <= 1'b0;
	end
	else
	begin
		b_meta <= b_raw_i;
		b_sync <= b_meta;
	end
end

// ENC_INDEX 2-flop synchronizer
always @(posedge clk_i)
begin
	if (!rst_n_i)
	begin
		idx_meta <= 1'b0;
		idx_sync <= 1'b0;
	end
	else
	begin
		idx_meta <= idx_raw_i;
		idx_sync <= idx_meta;
	end
end

// ---------------------------------------------------------------------------
// Glitch filter – one counter per channel.
// When filter_i == 0 the filtered output is just the sync output (bypass).
// Otherwise the output changes only after the synchronized input has held
// the new value for filter_i consecutive clock cycles.
// ---------------------------------------------------------------------------

// -- ENC_A glitch filter --
reg [3:0]  a_cnt;      // stable-cycles counter for ENC_A
reg        a_stable;   // last accepted (stable) value of ENC_A

always @(posedge clk_i)
begin
	if (!rst_n_i)
	begin
		a_cnt    <= 4'h0;
		a_stable <= 1'b0;
		a_filt_o <= 1'b0;
	end
	else if (filter_i == 4'h0)
	begin
		// bypass mode: output follows sync directly
		a_cnt    <= 4'h0;
		a_stable <= a_sync;
		a_filt_o <= a_sync;
	end
	else if (a_sync != a_stable)
	begin
		// input differs from current accepted value – count stable time
		if (a_cnt >= (filter_i - 4'h1))
		begin
			// stable long enough – accept new value
			a_stable <= a_sync;
			a_filt_o <= a_sync;
			a_cnt    <= 4'h0;
		end
		else
		begin
			a_cnt <= a_cnt + 4'h1;
		end
	end
	else
	begin
		// input matches current accepted value – hold and clear counter
		a_cnt <= 4'h0;
	end
end

// -- ENC_B glitch filter --
reg [3:0]  b_cnt;      // stable-cycles counter for ENC_B
reg        b_stable;   // last accepted (stable) value of ENC_B

always @(posedge clk_i)
begin
	if (!rst_n_i)
	begin
		b_cnt    <= 4'h0;
		b_stable <= 1'b0;
		b_filt_o <= 1'b0;
	end
	else if (filter_i == 4'h0)
	begin
		b_cnt    <= 4'h0;
		b_stable <= b_sync;
		b_filt_o <= b_sync;
	end
	else if (b_sync != b_stable)
	begin
		if (b_cnt >= (filter_i - 4'h1))
		begin
			b_stable <= b_sync;
			b_filt_o <= b_sync;
			b_cnt    <= 4'h0;
		end
		else
		begin
			b_cnt <= b_cnt + 4'h1;
		end
	end
	else
	begin
		b_cnt <= 4'h0;
	end
end

// -- ENC_INDEX glitch filter --
reg [3:0]  idx_cnt;    // stable-cycles counter for ENC_INDEX
reg        idx_stable; // last accepted (stable) value of ENC_INDEX

always @(posedge clk_i)
begin
	if (!rst_n_i)
	begin
		idx_cnt    <= 4'h0;
		idx_stable <= 1'b0;
		idx_filt_o <= 1'b0;
	end
	else if (filter_i == 4'h0)
	begin
		idx_cnt    <= 4'h0;
		idx_stable <= idx_sync;
		idx_filt_o <= idx_sync;
	end
	else if (idx_sync != idx_stable)
	begin
		if (idx_cnt >= (filter_i - 4'h1))
		begin
			idx_stable <= idx_sync;
			idx_filt_o <= idx_sync;
			idx_cnt    <= 4'h0;
		end
		else
		begin
			idx_cnt <= idx_cnt + 4'h1;
		end
	end
	else
	begin
		idx_cnt <= 4'h0;
	end
end

endmodule
