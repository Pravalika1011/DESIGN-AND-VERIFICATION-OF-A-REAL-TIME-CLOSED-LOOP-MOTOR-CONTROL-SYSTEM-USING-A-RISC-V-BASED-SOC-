// =============================================================================
// Project      : Motor-Control SoC - PID Controller IP
// File         : pid_core.v
// Description  : PID Controller Core.
//                Fixed-point Q16.16 PID datapath with FSM-sequenced shared
//                multiplier.
//
//                Features:
//                  - Output saturation clamp (OUT_MAX / OUT_MIN)
//                  - Integral saturation clamp (INT_MAX / INT_MIN)
//                  - Conditional-integration anti-windup: when output is
//                    clamped in the direction of the error, the integrator
//                    update is discarded for that cycle (not back-calculation)
//                  - Derivative-on-error or derivative-on-measurement
//                  - 18-bit derivative intermediate (prevents overflow on
//                    large setpoint steps)
//                  - Gain / limit shadowing (inputs latched at LATCH state;
//                    software writes cannot disturb an update in progress)
//                  - Signed motor-direction output
//                  - sat_flag_o: level output, asserted when most recent
//                    completed update was output-saturated
//                  - INT_RESET: one-cycle command; aborts any active
//                    calculation and clears integrator + previous values;
//                    has highest priority over all FSM states
//                  - ENABLE=0: zeros output and integrator, stays in IDLE;
//                    if ENABLE falls mid-calculation the result is aborted
//                  - OVERRUN detection: tick rising edge while BUSY
//
// FSM states   : IDLE -> LATCH -> MUL_P -> MUL_I -> MUL_D -> SUM
//                     -> CLAMP -> COMMIT -> IDLE
//                Latency from LATCH entry to COMMIT inclusive: 7 clock cycles.
//                Total latency from tick recognition to pid_out_valid_o: 8 cycles.
//
// Parameters   :
//   SPEED_W  = 16   speed / setpoint width
//   OUT_W    = 16   output width
//   GAIN_W   = 32   Q16.16 gain width
//   FRAC     = 16   fractional bits
//   ERR_W    = 17   SPEED_W + 1
//   DERIV_W  = 18   ERR_W + 1  (18-bit signed derivative, prevents overflow)
//   PROD_W   = 50   GAIN_W + DERIV_W = 32 + 18 = 50
//   ACC_W    = 54   PROD_W + 4
//
// Reset        : Active-low synchronous (rst_n_i).
//                No initial blocks.  No register initializers.
//
// Author       : Honours CBP Project
// Created      : 2026-10-03
// Revised      : 2026-10-03  v1.1  sat_flag_o, 18-bit deriv, INT_RESET
//                                   priority, ENABLE@COMMIT, shadow fix,
//                                   motor-control header
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

module pid_core #(
	parameter SPEED_W = 16,   // speed word width
	parameter OUT_W   = 16,   // output word width
	parameter GAIN_W  = 32,   // Q16.16 gain width
	parameter FRAC    = 16,   // fractional bits
	parameter ERR_W   = 17,   // SPEED_W + 1
	parameter DERIV_W = 18,   // ERR_W + 1  (18-bit signed derivative)
	parameter PROD_W  = 50,   // GAIN_W + DERIV_W = 32 + 18 = 50
	parameter ACC_W   = 54    // PROD_W + 4
) (
	// Clock and synchronous active-low reset
	input  wire                  clk_i,           // system clock
	input  wire                  rst_n_i,          // synchronous active-low reset

	// Control inputs from register file (registered outputs of pid_axi_slave)
	input  wire                  enable_i,         // ENABLE bit
	input  wire                  int_reset_i,       // INT_RESET command (one-cycle pulse)
	input  wire                  manual_upd_i,     // MANUAL_UPDATE pulse (self-clearing)
	input  wire                  d_on_meas_i,      // 0=d-on-error 1=d-on-measurement
	input  wire                  aw_en_i,          // anti-windup enable
	input  wire                  tick_i,            // external update tick

	// Setpoint and feedback
	input  wire [SPEED_W-1:0]    setpoint_i,       // desired speed (signed)
	input  wire [SPEED_W-1:0]    actual_i,          // measured speed (signed)

	// Gains (Q16.16 signed, from shadow registers via slave)
	input  wire [GAIN_W-1:0]     kp_i,
	input  wire [GAIN_W-1:0]     ki_i,
	input  wire [GAIN_W-1:0]     kd_i,

	// Output limits (signed, OUT_W bits)
	input  wire [OUT_W-1:0]      out_max_i,        // output upper clamp
	input  wire [OUT_W-1:0]      out_min_i,        // output lower clamp

	// Integrator limits (32-bit from register; sign-extended to ACC_W inside)
	input  wire [31:0]           int_max_i,        // integrator upper clamp
	input  wire [31:0]           int_min_i,        // integrator lower clamp

	// Outputs
	output reg  [OUT_W-1:0]      pid_out_o,        // PID output (signed)
	output reg                   pid_out_valid_o,  // one-cycle pulse on commit
	output reg  [ERR_W-1:0]      error_o,          // current error (signed)
	output reg  [SPEED_W-1:0]    actual_o,          // latched actual speed

	// Saturation level output
	output reg                   sat_flag_o,       // level: last update was sat'd

	// Status flags (one-cycle pulses; slave latches them into sticky registers)
	output reg                   busy_o,
	output reg                   done_o,           // one-cycle pulse on commit
	output reg                   sat_hi_o,         // one-cycle: output clamped HIGH
	output reg                   sat_lo_o,         // one-cycle: output clamped LOW
	output reg                   int_sat_o,        // one-cycle: integrator clamped
	output reg                   overrun_o         // one-cycle: tick while BUSY
);

// ---------------------------------------------------------------------------
// Local parameters
// ---------------------------------------------------------------------------
// ROUND_C = 1 << (FRAC-1), ACC_W bits wide
localparam [ACC_W-1:0] ROUND_C = {{(ACC_W-FRAC){1'b0}}, 1'b1, {(FRAC-1){1'b0}}};

// ---------------------------------------------------------------------------
// FSM state register
// ---------------------------------------------------------------------------
reg [3:0] state;     // current FSM state
reg [3:0] state_nx;  // next-state (combinational)

// ---------------------------------------------------------------------------
// Shadow registers – captured at LATCH, isolated during update
// ---------------------------------------------------------------------------
reg signed [SPEED_W-1:0]  sh_actual;     // latched actual speed
reg signed [GAIN_W-1:0]   sh_kp;         // latched Kp
reg signed [GAIN_W-1:0]   sh_ki;         // latched Ki
reg signed [GAIN_W-1:0]   sh_kd;         // latched Kd
reg signed [OUT_W-1:0]    sh_out_max;    // latched output max
reg signed [OUT_W-1:0]    sh_out_min;    // latched output min
reg signed [ACC_W-1:0]    sh_int_max;    // latched integrator max (sign-ext)
reg signed [ACC_W-1:0]    sh_int_min;    // latched integrator min (sign-ext)
reg                        sh_aw_en;      // latched AW_EN
// Note: sh_setpoint and sh_d_on_meas are intentionally absent.
// The LATCH state computes error and derivative using the live setpoint_i
// and d_on_meas_i inputs captured at the same clock edge as the other
// shadows, so separate shadow storage of those two signals is not needed.

// ---------------------------------------------------------------------------
// Persistent state (committed after each successful update)
// ---------------------------------------------------------------------------
reg signed [ACC_W-1:0]    integrator;    // accumulated integral
reg signed [ERR_W-1:0]    e_prev;        // previous error (for d-on-error)
reg signed [SPEED_W-1:0]  act_prev;      // previous actual (for d-on-meas)
reg                        first_update;  // 1 = suppress derivative kick

// ---------------------------------------------------------------------------
// Intermediate datapath registers
// ---------------------------------------------------------------------------
reg signed [ERR_W-1:0]    e;             // current error  (17-bit signed)
reg signed [DERIV_W-1:0]  d;             // derivative diff (18-bit signed)
reg signed [PROD_W-1:0]   p_term;        // Kp * e
reg signed [PROD_W-1:0]   ki_e;          // Ki * e
reg signed [PROD_W-1:0]   d_term;        // Kd * d
reg signed [ACC_W-1:0]    i_pre;         // integrator before clamp
reg signed [ACC_W-1:0]    i_new;         // integrator after clamp
reg signed [ACC_W+1:0]    sum_pd;        // partial P+D sum (ACC_W+2 wide)
reg signed [OUT_W-1:0]    u_out;         // rounded & clamped output
reg                        sat_hi_r;     // output clamped-high this update
reg                        sat_lo_r;     // output clamped-low this update
reg                        int_sat_r;    // integrator clamped this update

// Tick edge detection (for overrun and single-update trigger)
reg  tick_prev;
wire tick_rise; // rising edge of tick_i: triggers exactly one update per pulse
assign tick_rise = tick_i & ~tick_prev;

// ---------------------------------------------------------------------------
// FSM: sequential state register
// ---------------------------------------------------------------------------
// generate FSM state register
always @(posedge clk_i)
begin
	if (!rst_n_i)
		state <= `PID_ST_IDLE;
	else
		state <= state_nx;
end

// ---------------------------------------------------------------------------
// FSM: next-state logic (combinational)
// INT_RESET has highest priority: abort any active state back to IDLE.
// ENABLE=0 also causes abort (handled in next-state for LATCH..CLAMP).
// ---------------------------------------------------------------------------
always @(*)
begin
	state_nx = state;
	// INT_RESET always overrides – return to IDLE from any state
	if (int_reset_i)
	begin
		state_nx = `PID_ST_IDLE;
	end
	else
	begin
		case (state) // synopsys parallel_case
			`PID_ST_IDLE:
				begin
					if (enable_i && (tick_rise || manual_upd_i))
						state_nx = `PID_ST_LATCH;
				end
			`PID_ST_LATCH:   state_nx = enable_i ? `PID_ST_MUL_P  : `PID_ST_IDLE;
			`PID_ST_MUL_P:   state_nx = enable_i ? `PID_ST_MUL_I  : `PID_ST_IDLE;
			`PID_ST_MUL_I:   state_nx = enable_i ? `PID_ST_MUL_D  : `PID_ST_IDLE;
			`PID_ST_MUL_D:   state_nx = enable_i ? `PID_ST_SUM    : `PID_ST_IDLE;
			`PID_ST_SUM:     state_nx = enable_i ? `PID_ST_CLAMP  : `PID_ST_IDLE;
			`PID_ST_CLAMP:   state_nx = enable_i ? `PID_ST_COMMIT : `PID_ST_IDLE;
			`PID_ST_COMMIT:  state_nx = `PID_ST_IDLE;
			default:         state_nx = `PID_ST_IDLE;
		endcase
	end
end

// ---------------------------------------------------------------------------
// Tick edge tracker (for overrun detection)
// ---------------------------------------------------------------------------
// generate tick edge tracker
always @(posedge clk_i)
begin
	if (!rst_n_i)
		tick_prev <= 1'b0;
	else
		tick_prev <= tick_i;
end

// ---------------------------------------------------------------------------
// Main datapath sequential block
// ---------------------------------------------------------------------------
// generate main pid datapath
always @(posedge clk_i)
begin
	if (!rst_n_i)
	begin
		busy_o          <= 1'b0;
		done_o          <= 1'b0;
		sat_hi_o        <= 1'b0;
		sat_lo_o        <= 1'b0;
		int_sat_o       <= 1'b0;
		overrun_o       <= 1'b0;
		sat_flag_o      <= 1'b0;
		pid_out_o       <= {OUT_W{1'b0}};
		pid_out_valid_o <= 1'b0;
		error_o         <= {ERR_W{1'b0}};
		actual_o        <= {SPEED_W{1'b0}};
		integrator      <= {ACC_W{1'b0}};
		e_prev          <= {ERR_W{1'b0}};
		act_prev        <= {SPEED_W{1'b0}};
		first_update    <= 1'b1;
		sh_actual       <= {SPEED_W{1'b0}};
		sh_kp           <= {GAIN_W{1'b0}};
		sh_ki           <= {GAIN_W{1'b0}};
		sh_kd           <= {GAIN_W{1'b0}};
		sh_out_max      <= {OUT_W{1'b0}};
		sh_out_min      <= {OUT_W{1'b0}};
		sh_int_max      <= {ACC_W{1'b0}};
		sh_int_min      <= {ACC_W{1'b0}};
		sh_aw_en        <= 1'b0;
		e               <= {ERR_W{1'b0}};
		d               <= {DERIV_W{1'b0}};
		p_term          <= {PROD_W{1'b0}};
		ki_e            <= {PROD_W{1'b0}};
		d_term          <= {PROD_W{1'b0}};
		i_pre           <= {ACC_W{1'b0}};
		i_new           <= {ACC_W{1'b0}};
		sum_pd          <= {(ACC_W+2){1'b0}};
		u_out           <= {OUT_W{1'b0}};
		sat_hi_r        <= 1'b0;
		sat_lo_r        <= 1'b0;
		int_sat_r       <= 1'b0;
	end
	else
	begin
		// -------------------------------------------------------------------
		// Default: deassert one-cycle pulses every clock
		// -------------------------------------------------------------------
		pid_out_valid_o <= 1'b0;
		done_o          <= 1'b0;
		overrun_o       <= 1'b0;
		sat_hi_o        <= 1'b0;
		sat_lo_o        <= 1'b0;
		int_sat_o       <= 1'b0;

		// -------------------------------------------------------------------
		// INT_RESET (highest priority): one-cycle command.
		// Clears integrator, e_prev, act_prev regardless of FSM state.
		// Also aborts any active calculation (FSM returns to IDLE via
		// next-state logic above).  Does not affect gains or limits.
		// busy_o is cleared so the aborted cycle does not leave BUSY set.
		// -------------------------------------------------------------------
		if (int_reset_i)
		begin
			integrator   <= {ACC_W{1'b0}};
			e_prev       <= {ERR_W{1'b0}};
			act_prev     <= {SPEED_W{1'b0}};
			first_update <= 1'b1;
			busy_o       <= 1'b0;
			// Do NOT commit any in-progress result
		end
		else
		begin
			// ---------------------------------------------------------------
			// ENABLE = 0: zero output/integrator, return to clean state.
			// Checked AFTER INT_RESET so INT_RESET can clear even while
			// !enable_i without conflict.
			// ---------------------------------------------------------------
			if (!enable_i)
			begin
				pid_out_o    <= {OUT_W{1'b0}};
				integrator   <= {ACC_W{1'b0}};
				e_prev       <= {ERR_W{1'b0}};
				act_prev     <= {SPEED_W{1'b0}};
				first_update <= 1'b1;
				busy_o       <= 1'b0;
				sat_flag_o   <= 1'b0;
			end

			// ---------------------------------------------------------------
			// Overrun: tick rising edge while BUSY
			// ---------------------------------------------------------------
			if (busy_o && tick_rise)
				overrun_o <= 1'b1;

			// ---------------------------------------------------------------
			// FSM datapath
			// ---------------------------------------------------------------
			case (state) // synopsys parallel_case

				// -----------------------------------------------------------
				`PID_ST_IDLE:
				begin
					if (enable_i && (tick_rise || manual_upd_i))
						busy_o <= 1'b1;
				end

				// -----------------------------------------------------------
				// LATCH: capture all inputs into shadow registers.
				//        Compute error (17-bit) and derivative (18-bit signed)
				//        using live setpoint_i, actual_i, d_on_meas_i, e_prev,
				//        act_prev (all stable at the capture clock edge).
				// -----------------------------------------------------------
				`PID_ST_LATCH:
				begin
					if (!enable_i)
					begin
						busy_o <= 1'b0;
					end
					else
					begin
						// Capture all RW register values atomically
						sh_actual    <= $signed(actual_i);
						sh_kp        <= $signed(kp_i);
						sh_ki        <= $signed(ki_i);
						sh_kd        <= $signed(kd_i);
						sh_out_max   <= $signed(out_max_i);
						sh_out_min   <= $signed(out_min_i);
						sh_int_max   <= $signed({{(ACC_W-32){int_max_i[31]}}, int_max_i});
						sh_int_min   <= $signed({{(ACC_W-32){int_min_i[31]}}, int_min_i});
						sh_aw_en     <= aw_en_i;
						// setpoint_i and d_on_meas_i used directly below (same edge)

						// Error: sign-extend both operands to ERR_W (17 bits)
						// e = setpoint - actual
						e <= $signed({setpoint_i[SPEED_W-1], setpoint_i})
						   - $signed({actual_i[SPEED_W-1],  actual_i});

						// Derivative: 18-bit signed to prevent overflow.
						// Sign-extend ERR_W (17b) operands to DERIV_W (18b) before subtract.
						if (first_update)
						begin
							// First update after reset/enable/INT_RESET:
							// suppress derivative kick; d = 0
							d <= {DERIV_W{1'b0}};
						end
						else if (!d_on_meas_i)
						begin
							// d-on-error: (e_current - e_prev) in 18-bit signed
							// Both operands sign-extended from 17b to 18b
							d <= $signed({setpoint_i[SPEED_W-1], setpoint_i[SPEED_W-1], setpoint_i})
							   - $signed({actual_i[SPEED_W-1],   actual_i[SPEED_W-1],  actual_i})
							   - $signed({e_prev[ERR_W-1], e_prev});
						end
						else
						begin
							// d-on-measurement: -(actual - act_prev) in 18-bit signed
							d <= -($signed({actual_i[SPEED_W-1],  actual_i[SPEED_W-1],  actual_i})
							     - $signed({act_prev[SPEED_W-1],  act_prev[SPEED_W-1],  act_prev}));
						end
					end
				end

				// -----------------------------------------------------------
				// MUL_P: p_term = Kp * e
				//   sh_kp  : GAIN_W(32) signed, extended to PROD_W(50)
				//   e      : ERR_W(17)  signed, extended to PROD_W(50)
				//   product: PROD_W(50) bits
				// -----------------------------------------------------------
				`PID_ST_MUL_P:
				begin
					if (!enable_i)
						busy_o <= 1'b0;
					else
						p_term <= $signed({{(PROD_W-GAIN_W){sh_kp[GAIN_W-1]}}, sh_kp})
						        * $signed({{(PROD_W-ERR_W){e[ERR_W-1]}}, e});
				end

				// -----------------------------------------------------------
				// MUL_I: ki_e = Ki * e
				// -----------------------------------------------------------
				`PID_ST_MUL_I:
				begin
					if (!enable_i)
						busy_o <= 1'b0;
					else
						ki_e <= $signed({{(PROD_W-GAIN_W){sh_ki[GAIN_W-1]}}, sh_ki})
						      * $signed({{(PROD_W-ERR_W){e[ERR_W-1]}}, e});
				end

				// -----------------------------------------------------------
				// MUL_D: d_term = Kd * d
				//   sh_kd : GAIN_W(32) signed, extended to PROD_W(50)
				//   d     : DERIV_W(18) signed, extended to PROD_W(50)
				// -----------------------------------------------------------
				`PID_ST_MUL_D:
				begin
					if (!enable_i)
						busy_o <= 1'b0;
					else
						d_term <= $signed({{(PROD_W-GAIN_W){sh_kd[GAIN_W-1]}}, sh_kd})
						        * $signed({{(PROD_W-DERIV_W){d[DERIV_W-1]}}, d});
				end

				// -----------------------------------------------------------
				// SUM: integrator pre-accumulation + partial P+D sum
				//
				//   i_pre = integrator + ki_e
				//   Sign-extend ki_e (PROD_W=50) to ACC_W (54) before adding.
				//
				//   sum_pd = p_term + d_term (sign-extended to ACC_W+2)
				// -----------------------------------------------------------
				`PID_ST_SUM:
				begin
					if (!enable_i)
						busy_o <= 1'b0;
					else
					begin
						i_pre  <= $signed(integrator)
						        + $signed({{(ACC_W-PROD_W){ki_e[PROD_W-1]}}, ki_e});

						sum_pd <= $signed({{(ACC_W+2-PROD_W){p_term[PROD_W-1]}}, p_term})
						        + $signed({{(ACC_W+2-PROD_W){d_term[PROD_W-1]}}, d_term});
					end
				end

				// -----------------------------------------------------------
				// CLAMP: clamp integrator; complete sum; round; clamp output.
				//
				// i_new is written here (used in COMMIT).
				// i_clamped is computed inline (same cycle, before i_new is
				// registered) to allow the full_sum to use the clamped value
				// without waiting a clock cycle.
				// -----------------------------------------------------------
				`PID_ST_CLAMP:
				begin
					if (!enable_i)
						busy_o <= 1'b0;
					else
					begin
						// Integrator saturation
						int_sat_r <= 1'b0;
						if ($signed(i_pre) > $signed(sh_int_max))
						begin
							i_new     <= sh_int_max;
							int_sat_r <= 1'b1;
						end
						else if ($signed(i_pre) < $signed(sh_int_min))
						begin
							i_new     <= sh_int_min;
							int_sat_r <= 1'b1;
						end
						else
						begin
							i_new <= i_pre;
						end

						// Sum, round, output clamp using inline i_clamped
						begin : blk_clamp
							reg signed [ACC_W-1:0]  i_clamped;
							reg signed [ACC_W+1:0]  full_sum;
							reg signed [ACC_W+1:0]  rounded;

							// Inline re-compute of clamped integrator value
							if ($signed(i_pre) > $signed(sh_int_max))
								i_clamped = sh_int_max;
							else if ($signed(i_pre) < $signed(sh_int_min))
								i_clamped = sh_int_min;
							else
								i_clamped = i_pre;

							// full_sum = sum_pd + i_clamped  (ACC_W+2 wide)
							full_sum = $signed(sum_pd)
							         + $signed({{2{i_clamped[ACC_W-1]}}, i_clamped});

							// Round: (full_sum + ROUND_C) >>> FRAC
							rounded = ($signed(full_sum)
							         + $signed({{2{ROUND_C[ACC_W-1]}}, ROUND_C}))
							        >>> FRAC;

							// Output saturation clamp
							sat_hi_r <= 1'b0;
							sat_lo_r <= 1'b0;
							if ($signed(rounded) >
							    $signed({{(ACC_W+2-OUT_W){sh_out_max[OUT_W-1]}}, sh_out_max}))
							begin
								u_out    <= sh_out_max;
								sat_hi_r <= 1'b1;
							end
							else if ($signed(rounded) <
							         $signed({{(ACC_W+2-OUT_W){sh_out_min[OUT_W-1]}}, sh_out_min}))
							begin
								u_out    <= sh_out_min;
								sat_lo_r <= 1'b1;
							end
							else
							begin
								u_out <= rounded[OUT_W-1:0];
							end
						end
					end
				end

				// -----------------------------------------------------------
				// COMMIT: anti-windup decision, commit results.
				// Aborted if enable_i = 0 (ENABLE dropped before commit).
				// This is checked INSIDE the COMMIT case; if enable_i = 0
				// the general enable-drop code above has already zeroed
				// output/integrator, so we just clear busy here.
				// -----------------------------------------------------------
				`PID_ST_COMMIT:
				begin
					if (!enable_i)
					begin
						// ENABLE fell before COMMIT; result is discarded.
						// enable-drop code above already handled zeroing.
						busy_o <= 1'b0;
					end
					else
					begin
						// Conditional-integration anti-windup:
						// If output is clamped in the same direction as the
						// error, discard i_new and keep the old integrator.
						if (sh_aw_en)
						begin
							if (sat_hi_r && ($signed(e) > $signed({ERR_W{1'b0}})))
								integrator <= integrator; // discard – keep old
							else if (sat_lo_r && ($signed(e) < $signed({ERR_W{1'b0}})))
								integrator <= integrator; // discard – keep old
							else
								integrator <= i_new;
						end
						else
						begin
							integrator <= i_new;
						end

						// Update previous-value registers
						e_prev       <= e;
						act_prev     <= sh_actual;
						first_update <= 1'b0;

						// Commit output and observability registers
						pid_out_o       <= u_out;
						pid_out_valid_o <= 1'b1;
						error_o         <= e;
						actual_o        <= sh_actual;

						// sat_flag_o: level output reflecting latest saturation
						sat_flag_o <= sat_hi_r | sat_lo_r;

						// One-cycle status pulses (slave latches into sticky regs)
						done_o    <= 1'b1;
						sat_hi_o  <= sat_hi_r;
						sat_lo_o  <= sat_lo_r;
						int_sat_o <= int_sat_r;

						busy_o <= 1'b0;
					end
				end

				default: ; // no action
			endcase
		end // else (not int_reset_i)
	end // else (not reset)
end

endmodule
