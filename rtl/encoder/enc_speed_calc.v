// =============================================================================
// Project      : Motor-Control SoC - Quadrature Encoder Interface IP
// File         : enc_speed_calc.v
// Description  : Speed calculation module.
//
//                Functions:
//                  1. Window counter: counts clock cycles; at window end
//                     captures signed count delta, pulses count_valid_o.
//                  2. Scale multiply: speed = (delta * SCALE + 0x8000) >>> 16
//                     (Q16.16 multiply, rounded, no division). Saturated to
//                     signed 16-bit.
//                  3. Moving-average filter: AVG_SEL selects N = 1/2/4/8 taps.
//                     On the first sample after reset/enable/count-reset,
//                     all taps are preloaded with that sample (no ramp).
//                     Average ALWAYS includes the newest sample:
//                       N=1: avg = new_sample
//                       N=2: avg = (new + tap[oldest_1]) / 2
//                       N=4: avg = (new + tap[3 oldest]) / 4
//                       N=8: avg = (new + tap[7 oldest]) / 8
//                     Division by power-of-two = arithmetic right shift with
//                     round-half-up: avg = (sum + N/2) >>> log2(N).
//                     Sum is 19-bit signed to prevent overflow (8 × 16-bit).
//
//                Signed arithmetic:
//                  delta (32-bit signed) × SCALE (32-bit signed Q16.16)
//                  → 64-bit signed product; add 0x8000 for rounding;
//                  arithmetic right shift 16; saturate to signed 16 bits.
//
//                ENABLE=0: window counter frozen, outputs held 0.
//
// RTL Changes from v1.0:
//   v1.1 (2026-10-06): Fixed moving-average lag.  Previous version summed
//     taps BEFORE writing the new sample so the newest value was always
//     missing.  Now the sum uses the NEW sample directly plus the N-1
//     previously-stored oldest taps (read from the ring buffer BEFORE the
//     write pointer advances).  The combinatorial sum mux therefore uses
//     speed_scaled (new sample) as the first addend rather than tap[wr_ptr].
//     Sum widened to 19-bit signed (8 × 16-bit = 19 bits minimum).
//     Rounding constant corrected to N/2 per power-of-two: 0 / 1 / 2 / 4.
//     avg_result mux selects on avg_sel_i correctly.
//     speed_o on first_sample uses speed_scaled not avg_result.
//
// Author       : Honours CBP Project
// Created      : 2026-10-06
// Revised      : 2026-10-06  v1.1  Fixed avg lag; 19-bit sum; rounding fix
//              : 2026-10-06  v1.2  Fix TMBIN (19'shFF8000→19'sh78000),
//                                  WMIA (sign-extend to 64b before multiply),
//                                  CAWM (use prod_rounded[63:16] not >>>16)
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

module enc_speed_calc (
	// Clock and synchronous active-low reset
	input  wire         clk_i,           // system clock
	input  wire         rst_n_i,         // synchronous active-low reset

	// Control
	input  wire         enable_i,        // ENABLE: 0 = freeze
	input  wire         count_reset_i,   // count reset strobe (clears delta acc)

	// Configuration registers
	input  wire [31:0]  window_i,        // window length in clocks (reset=100000)
	input  wire [31:0]  scale_i,         // signed Q16.16 speed scale (reset=0x10000)
	input  wire [1:0]   avg_sel_i,       // moving-average selector (00=1,01=2,10=4,11=8)

	// Pulses from quadrature decoder
	input  wire         count_inc_i,     // +1 count pulse
	input  wire         count_dec_i,     // -1 count pulse

	// Outputs
	output reg          count_valid_o,   // one-cycle pulse: window complete, raw_delta updated
	output reg  [31:0]  raw_delta_o,     // signed 32-bit raw count delta of last window
	output reg  [15:0]  speed_o,         // signed 16-bit filtered speed (saturated)
	output reg          speed_valid_o    // one-cycle pulse: filtered speed updated
);

// ---------------------------------------------------------------------------
// Window counter and delta accumulator
// ---------------------------------------------------------------------------
reg  [31:0]  win_cnt;      // window clock-cycle counter (0 to window_i)
reg  [31:0]  delta_acc;    // signed running accumulator within the current window

// Signed delta step: +1 on inc, -1 on dec, 0 otherwise
// count_inc and count_dec are mutually exclusive (decoder guarantee)
wire [31:0]  delta_step;
assign delta_step = count_inc_i ? 32'h0000_0001 :
                    count_dec_i ? 32'hFFFF_FFFF :   // two's-complement -1
                                  32'h0000_0000;

// Window fires when counter equals window_i (so window = window_i+1 clocks).
// Spec: "programmable window length in clock cycles" – treat window_i as the
// number of clocks; counter runs 0..window_i-1 so compare at window_i-1.
// (window_i=0 → 1-clock window, fires every cycle – valid edge case.)
wire win_last;    // last clock of the current window
assign win_last = (win_cnt == (window_i - 32'h1)) || (window_i == 32'h0);

always @(posedge clk_i)
begin
	if (!rst_n_i)
	begin
		win_cnt       <= 32'h0;
		delta_acc     <= 32'h0;
		count_valid_o <= 1'b0;
		raw_delta_o   <= 32'h0;
	end
	else if (!enable_i || count_reset_i)
	begin
		win_cnt       <= 32'h0;
		delta_acc     <= 32'h0;
		count_valid_o <= 1'b0;
	end
	else if (win_last)
	begin
		// Capture delta (include the step that arrives this very clock)
		raw_delta_o   <= delta_acc + delta_step;
		count_valid_o <= 1'b1;
		win_cnt       <= 32'h0;
		delta_acc     <= 32'h0;
	end
	else
	begin
		win_cnt       <= win_cnt + 32'h1;
		delta_acc     <= delta_acc + delta_step;
		count_valid_o <= 1'b0;
	end
end

// ---------------------------------------------------------------------------
// Scale multiply pipeline
//   Stage 1 (clk 0): capture raw_delta_o and count_valid_o (registered above)
//   Stage 2 (clk 1): compute prod = delta * scale  (64-bit signed)
//   Stage 3 (clk 2): round + shift + saturate → speed_scaled
// The multiply is a pure registered datapath; no combinational paths.
// ---------------------------------------------------------------------------

// Stage 1 – latch delta and valid from the window block output
reg  [31:0]  delta_lat;     // latched delta for multiply
reg          mul_valid_1;   // valid travelling through pipeline stage 1

always @(posedge clk_i)
begin
	if (!rst_n_i)
	begin
		delta_lat   <= 32'h0;
		mul_valid_1 <= 1'b0;
	end
	else
	begin
		delta_lat   <= raw_delta_o;
		mul_valid_1 <= count_valid_o;
	end
end

// Stage 2 – 64-bit signed multiply
// $signed() on both operands ensures signed×signed = signed product
reg  [63:0]  prod_r;        // 64-bit signed product
reg          mul_valid_2;

always @(posedge clk_i)
begin
	if (!rst_n_i)
	begin
		prod_r      <= 64'h0;
		mul_valid_2 <= 1'b0;
	end
	else
	begin
		prod_r      <= $signed({{32{delta_lat[31]}}, delta_lat}) *
		               $signed({{32{scale_i[31]}},  scale_i});
		mul_valid_2 <= mul_valid_1;
	end
end

// Stage 3 – round, arithmetic-shift-right 16, saturate to signed 16 bits
// rounded = prod + 0x8000  (adds 0.5 ULP in Q16.16 before truncation)
// shifted = rounded[63:16] (48-bit arithmetic right shift by 16)
// saturate: if shifted > 0x7FFF → 0x7FFF; if shifted < -0x8000 → 0x8000
wire [63:0]  prod_rounded;
wire [47:0]  shifted_48;    // 48-bit arithmetic-shifted result
wire         sat_pos;       // result overflows positive
wire         sat_neg;       // result underflows negative
wire [15:0]  speed_raw;     // saturated 16-bit result

assign prod_rounded = prod_r + 64'h0000_0000_0000_8000;
// Arithmetic right shift by 16: for a 64-bit signed number, bits [63:16]
// are the sign-extended result, identical to $signed(prod_rounded)>>>16
// but without the width-mismatch warning on the 64→48-bit assignment.
assign shifted_48   = $signed(prod_rounded[63:16]);

// Saturation checks on 48-bit signed value
assign sat_pos = ($signed(shifted_48) > $signed(48'sh00007FFF));
assign sat_neg = ($signed(shifted_48) < $signed(48'shFFFF_FFFF_8000));

assign speed_raw = sat_pos ? 16'h7FFF :
                   sat_neg ? 16'h8000 :
                             shifted_48[15:0];

reg  [15:0]  speed_scaled;  // registered scaled & saturated speed
reg          scaled_valid;  // valid flag

always @(posedge clk_i)
begin
	if (!rst_n_i)
	begin
		speed_scaled <= 16'h0;
		scaled_valid <= 1'b0;
	end
	else
	begin
		speed_scaled <= speed_raw;
		scaled_valid <= mul_valid_2;
	end
end

// ---------------------------------------------------------------------------
// Moving-average filter – 8-tap ring buffer
//
// KEY FIX (v1.1): The average ALWAYS uses the new sample (speed_scaled) as
// the first term, plus the N-1 most-recently-stored-taps from the ring buffer.
// The ring buffer stores PREVIOUS samples; the new sample enters the sum
// combinatorially BEFORE being written to the buffer.
//
// Ring buffer layout (wr_ptr points to the slot to write the CURRENT sample):
//   N=1: just speed_scaled
//   N=2: speed_scaled + tap[(wr_ptr-1) & 7]    (1 old tap)
//   N=4: speed_scaled + tap[(wr_ptr-1)...(wr_ptr-3) & 7]   (3 old taps)
//   N=8: speed_scaled + all 7 stored taps  (7 old taps)
//
// After computing the average, write speed_scaled to tap[wr_ptr] and advance.
//
// Sum is 19-bit signed (8 × 16-bit max = 8 × 32767 = 262136 < 2^19).
// Rounding: avg = (sum + N/2) >>> log2(N)
//   N=1: avg = speed_scaled  (no shift)
//   N=2: avg = (sum + 1)  >>> 1   (round at bit 0)
//   N=4: avg = (sum + 2)  >>> 2   (round at bit 1)
//   N=8: avg = (sum + 4)  >>> 3   (round at bit 2)
// ---------------------------------------------------------------------------

reg [15:0]  tap [0:7];      // ring buffer: 8 × 16-bit signed taps
reg [2:0]   wr_ptr;         // pointer to next write slot
reg         first_sample;   // 1 = next sample is the first after reset/enable

// Helper: previous pointer values (combinatorial, wrap-safe)
wire [2:0]  wp_m1;  // wr_ptr - 1
wire [2:0]  wp_m2;  // wr_ptr - 2
wire [2:0]  wp_m3;  // wr_ptr - 3
wire [2:0]  wp_m4;  // wr_ptr - 4
wire [2:0]  wp_m5;  // wr_ptr - 5
wire [2:0]  wp_m6;  // wr_ptr - 6
wire [2:0]  wp_m7;  // wr_ptr - 7

assign wp_m1 = wr_ptr - 3'h1;
assign wp_m2 = wr_ptr - 3'h2;
assign wp_m3 = wr_ptr - 3'h3;
assign wp_m4 = wr_ptr - 3'h4;
assign wp_m5 = wr_ptr - 3'h5;
assign wp_m6 = wr_ptr - 3'h6;
assign wp_m7 = wr_ptr - 3'h7;

// 19-bit signed sum including the NEW sample as the first term
// Sign-extend each 16-bit tap to 19 bits: {{3{tap[n][15]}}, tap[n]}
wire [18:0]  sum_new;    // 19-bit sign-extension of new sample
wire [18:0]  sum_2;      // N=2: new + 1 old
wire [18:0]  sum_4;      // N=4: new + 3 old
wire [18:0]  sum_8;      // N=8: new + 7 old

assign sum_new = {{3{speed_scaled[15]}}, speed_scaled};

assign sum_2 = sum_new
             + {{3{tap[wp_m1][15]}}, tap[wp_m1]};

assign sum_4 = sum_new
             + {{3{tap[wp_m1][15]}}, tap[wp_m1]}
             + {{3{tap[wp_m2][15]}}, tap[wp_m2]}
             + {{3{tap[wp_m3][15]}}, tap[wp_m3]};

assign sum_8 = sum_new
             + {{3{tap[wp_m1][15]}}, tap[wp_m1]}
             + {{3{tap[wp_m2][15]}}, tap[wp_m2]}
             + {{3{tap[wp_m3][15]}}, tap[wp_m3]}
             + {{3{tap[wp_m4][15]}}, tap[wp_m4]}
             + {{3{tap[wp_m5][15]}}, tap[wp_m5]}
             + {{3{tap[wp_m6][15]}}, tap[wp_m6]}
             + {{3{tap[wp_m7][15]}}, tap[wp_m7]};

// Average with round-half-up (add N/2 before arithmetic right shift)
wire [18:0]  avg_result;   // 19-bit signed average

assign avg_result =
	(avg_sel_i == 2'b00) ? sum_new :
	(avg_sel_i == 2'b01) ? $signed($signed(sum_2 + 19'sh1) >>> 1) :
	(avg_sel_i == 2'b10) ? $signed($signed(sum_4 + 19'sh2) >>> 2) :
	                       $signed($signed(sum_8 + 19'sh4) >>> 3);

// Saturate avg_result (19-bit signed) to 16-bit signed
wire sat_avg_pos;
wire sat_avg_neg;
wire [15:0]  avg_sat;

assign sat_avg_pos = ($signed(avg_result) > $signed(19'sh7FFF));
assign sat_avg_neg = ($signed(avg_result) < $signed(19'sh78000));

assign avg_sat = sat_avg_pos ? 16'h7FFF :
                 sat_avg_neg ? 16'h8000 :
                               avg_result[15:0];

// Ring buffer write and output registration
always @(posedge clk_i)
begin
	if (!rst_n_i)
	begin
		wr_ptr        <= 3'h0;
		first_sample  <= 1'b1;
		speed_o       <= 16'h0;
		speed_valid_o <= 1'b0;
		tap[0] <= 16'h0;
		tap[1] <= 16'h0;
		tap[2] <= 16'h0;
		tap[3] <= 16'h0;
		tap[4] <= 16'h0;
		tap[5] <= 16'h0;
		tap[6] <= 16'h0;
		tap[7] <= 16'h0;
	end
	else if (!enable_i || count_reset_i)
	begin
		wr_ptr        <= 3'h0;
		first_sample  <= 1'b1;
		speed_valid_o <= 1'b0;
		tap[0] <= 16'h0;
		tap[1] <= 16'h0;
		tap[2] <= 16'h0;
		tap[3] <= 16'h0;
		tap[4] <= 16'h0;
		tap[5] <= 16'h0;
		tap[6] <= 16'h0;
		tap[7] <= 16'h0;
	end
	else if (scaled_valid)
	begin
		if (first_sample)
		begin
			// Preload all taps with the first sample → no ramp from zero
			tap[0] <= speed_scaled;
			tap[1] <= speed_scaled;
			tap[2] <= speed_scaled;
			tap[3] <= speed_scaled;
			tap[4] <= speed_scaled;
			tap[5] <= speed_scaled;
			tap[6] <= speed_scaled;
			tap[7] <= speed_scaled;
			wr_ptr        <= 3'h1;         // next write slot
			first_sample  <= 1'b0;
			// On first sample the output IS the scaled sample (avg of 1 identical value)
			speed_o       <= speed_scaled;
			speed_valid_o <= 1'b1;
		end
		else
		begin
			// Write new sample into ring; avg_result already uses it combinatorially
			tap[wr_ptr] <= speed_scaled;
			wr_ptr      <= wr_ptr + 3'h1;  // wraps naturally at 8
			speed_o       <= avg_sat;
			speed_valid_o <= 1'b1;
		end
	end
	else
	begin
		speed_valid_o <= 1'b0;
	end
end

endmodule
