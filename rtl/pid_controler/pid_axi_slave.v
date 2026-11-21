// =============================================================================
// Project      : Motor-Control SoC - PID Controller IP
// File         : pid_axi_slave.v
// Description  : Full AXI4 Slave register interface for the PID Controller IP.
//
//                Key features:
//                  - Full AXI4 (NOT AXI4-Lite): independent AW / W channels
//                  - Correct ID tracking: BID = captured AWID, RID = captured ARID
//                  - WSTRB byte-enable support for every RW register
//                  - DONE and OVERRUN are sticky W1C; new-event priority over
//                    simultaneous W1C clear
//                  - SAT_HI, SAT_LO, INT_SAT are sticky READ-ONLY; writes
//                    to their bit positions are ignored
//                  - irq_o = (w1c_done | w1c_overrun) & ctrl_irq_en (level)
//                  - Self-clearing MANUAL_UPDATE (one clock after set)
//                  - SLVERR for misaligned, out-of-map, burst, or invalid
//                    16-bit-register writes with bad sign-extension
//                  - Multi-beat write bursts: first beat decides validity;
//                    remaining beats drained until WLAST; SLVERR returned;
//                    no register modified
//                  - Multi-beat read bursts: ARLEN+1 beats returned; all
//                    RDATA=0, RRESP=SLVERR; RLAST on final beat only
//                  - Invalid reads: RDATA=0, RRESP=SLVERR
//                  - BVALID held until BREADY; RVALID held until RREADY
//                  - No combinational VALID-to-READY paths
//
// AXI4 widths  :
//   DATA_WIDTH = 32, ADDR_WIDTH = 32, ID_WIDTH = 8
//
// Reset        : Active-low synchronous (rst_n_i).
//                No initial blocks.  No register initializers.
//
// Author       : Honours CBP Project
// Created      : 2026-10-03
// Revised      : 2026-10-03  v1.1  irq_o sticky, RO-sticky SAT bits, W1C
//                                   priority, burst drain/multi-beat read,
//                                   16-bit sign-ext validation, motor-control
//                                   header
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

module pid_axi_slave #(
	parameter DATA_WIDTH = 32,            // AXI data width
	parameter ADDR_WIDTH = 32,            // AXI address width
	parameter ID_WIDTH   = 8,             // AXI ID width
	parameter STRB_WIDTH = (DATA_WIDTH/8) // write strobe width = 4
) (
	// Clock and synchronous active-low reset
	input  wire                      clk_i,
	input  wire                      rst_n_i,

	// -----------------------------------------------------------------------
	// AXI4 Write Address Channel
	// -----------------------------------------------------------------------
	input  wire [ID_WIDTH-1:0]        s_axi_awid,
	input  wire [ADDR_WIDTH-1:0]      s_axi_awaddr,
	input  wire [7:0]                 s_axi_awlen,
	input  wire [2:0]                 s_axi_awsize,
	input  wire [1:0]                 s_axi_awburst,   // accepted; not used for register periph
	input  wire                       s_axi_awlock,    // accepted; not used
	input  wire [3:0]                 s_axi_awcache,   // accepted; not used
	input  wire [2:0]                 s_axi_awprot,    // accepted; not used
	input  wire                       s_axi_awvalid,
	output reg                        s_axi_awready,

	// -----------------------------------------------------------------------
	// AXI4 Write Data Channel
	// -----------------------------------------------------------------------
	input  wire [DATA_WIDTH-1:0]      s_axi_wdata,
	input  wire [STRB_WIDTH-1:0]      s_axi_wstrb,
	input  wire                       s_axi_wlast,     // used for burst drain termination
	input  wire                       s_axi_wvalid,
	output reg                        s_axi_wready,

	// -----------------------------------------------------------------------
	// AXI4 Write Response Channel
	// -----------------------------------------------------------------------
	output reg  [ID_WIDTH-1:0]        s_axi_bid,
	output reg  [1:0]                 s_axi_bresp,
	output reg                        s_axi_bvalid,
	input  wire                       s_axi_bready,

	// -----------------------------------------------------------------------
	// AXI4 Read Address Channel
	// -----------------------------------------------------------------------
	input  wire [ID_WIDTH-1:0]        s_axi_arid,
	input  wire [ADDR_WIDTH-1:0]      s_axi_araddr,
	input  wire [7:0]                 s_axi_arlen,
	input  wire [2:0]                 s_axi_arsize,
	input  wire [1:0]                 s_axi_arburst,   // accepted; not used
	input  wire                       s_axi_arlock,    // accepted; not used
	input  wire [3:0]                 s_axi_arcache,   // accepted; not used
	input  wire [2:0]                 s_axi_arprot,    // accepted; not used
	input  wire                       s_axi_arvalid,
	output reg                        s_axi_arready,

	// -----------------------------------------------------------------------
	// AXI4 Read Data Channel
	// -----------------------------------------------------------------------
	output reg  [ID_WIDTH-1:0]        s_axi_rid,
	output reg  [DATA_WIDTH-1:0]      s_axi_rdata,
	output reg  [1:0]                 s_axi_rresp,
	output reg                        s_axi_rlast,
	output reg                        s_axi_rvalid,
	input  wire                       s_axi_rready,

	// -----------------------------------------------------------------------
	// Register outputs to pid_core
	// -----------------------------------------------------------------------
	output reg  [15:0]                reg_setpoint_o,   // PID_SETPOINT
	output reg  [31:0]                reg_kp_o,         // PID_KP
	output reg  [31:0]                reg_ki_o,         // PID_KI
	output reg  [31:0]                reg_kd_o,         // PID_KD
	output reg                        reg_enable_o,     // CTRL[ENABLE]
	output reg                        reg_int_reset_o,  // CTRL[INT_RESET]
	output reg                        reg_manual_upd_o, // CTRL[MANUAL_UPDATE]
	output reg                        reg_d_on_meas_o,  // CTRL[D_ON_MEAS]
	output reg                        reg_aw_en_o,      // CTRL[AW_EN]
	output reg                        reg_irq_en_o,     // CTRL[IRQ_EN]
	output reg  [15:0]                reg_out_max_o,    // PID_OUT_MAX
	output reg  [15:0]                reg_out_min_o,    // PID_OUT_MIN
	output reg  [31:0]                reg_int_max_o,    // PID_INT_MAX (lower 32b)
	output reg  [31:0]                reg_int_min_o,    // PID_INT_MIN (lower 32b)

	// -----------------------------------------------------------------------
	// Status / readback inputs from pid_core
	// -----------------------------------------------------------------------
	input  wire [15:0]                core_out_i,       // PID_OUTPUT
	input  wire                       core_busy_i,      // STATUS[BUSY]
	input  wire                       core_done_i,      // one-cycle done pulse
	input  wire                       core_sat_hi_i,    // one-cycle sat_hi pulse
	input  wire                       core_sat_lo_i,    // one-cycle sat_lo pulse
	input  wire                       core_int_sat_i,   // one-cycle int_sat pulse
	input  wire                       core_overrun_i,   // one-cycle overrun pulse
	input  wire [16:0]                core_error_i,     // PID_ERROR (17-bit signed)
	input  wire [15:0]                core_actual_i,    // PID_ACTUAL

	// -----------------------------------------------------------------------
	// Interrupt output (level, from sticky status bits)
	// irq_o = (w1c_done | w1c_overrun) & ctrl_irq_en
	// -----------------------------------------------------------------------
	output wire                       irq_o
);

// ---------------------------------------------------------------------------
// AXI response codes
// ---------------------------------------------------------------------------
localparam RESP_OKAY   = 2'b00;
localparam RESP_SLVERR = 2'b10;

// ---------------------------------------------------------------------------
// Write channel state machine
// ---------------------------------------------------------------------------
localparam WR_IDLE  = 3'b000; // waiting for AW and/or W
localparam WR_WAIT  = 3'b001; // one channel captured; waiting for the other
localparam WR_EXEC  = 3'b010; // both captured; execute write + issue response
localparam WR_RESP  = 3'b011; // BVALID asserted; waiting for BREADY
localparam WR_DRAIN = 3'b100; // burst: draining remaining W beats until WLAST

reg [2:0]             wr_state;
reg [ID_WIDTH-1:0]    wr_id;
reg [ADDR_WIDTH-1:0]  wr_addr;
reg [7:0]             wr_len;
reg [2:0]             wr_size;
reg [DATA_WIDTH-1:0]  wr_data;
reg [STRB_WIDTH-1:0]  wr_strb;
reg                   wr_wlast;      // captured WLAST from the W beat
reg                   aw_captured;
reg                   w_captured;
reg                   wr_is_burst;   // 1 = unsupported burst (AWLEN > 0)

// ---------------------------------------------------------------------------
// Read channel state machine
// ---------------------------------------------------------------------------
localparam RD_IDLE  = 2'b00; // waiting for AR
localparam RD_BEAT  = 2'b01; // presenting beats (single or multi)
localparam RD_WAIT  = 2'b10; // RVALID asserted; waiting for RREADY

reg [1:0]             rd_state;
reg [ID_WIDTH-1:0]    rd_id;
reg [ADDR_WIDTH-1:0]  rd_addr;
reg [7:0]             rd_len;        // captured ARLEN
reg [2:0]             rd_size;
reg [7:0]             rd_beat_cnt;   // remaining beats to send (counts down)
reg                   rd_is_burst;   // 1 = unsupported burst (ARLEN > 0)

// ---------------------------------------------------------------------------
// Sticky status registers
// W1C: DONE (bit 1) and OVERRUN (bit 5)
// RO sticky: SAT_HI (bit 2), SAT_LO (bit 3), INT_SAT (bit 4)
// ---------------------------------------------------------------------------
reg w1c_done;     // sticky DONE   (RO/W1C)
reg w1c_overrun;  // sticky OVERRUN (RO/W1C)
reg ro_sat_hi;    // sticky SAT_HI  (RO only)
reg ro_sat_lo;    // sticky SAT_LO  (RO only)
reg ro_int_sat;   // sticky INT_SAT (RO only)

// ---------------------------------------------------------------------------
// CTRL register bits
// ---------------------------------------------------------------------------
reg ctrl_enable;
reg ctrl_int_reset;
reg ctrl_manual_upd;  // self-clearing
reg ctrl_d_on_meas;
reg ctrl_aw_en;
reg ctrl_irq_en;

// Interrupt: level driven from sticky DONE/OVERRUN bits gated by IRQ_EN
// Declared here after ctrl_irq_en to avoid forward reference.
assign irq_o = (w1c_done | w1c_overrun) & ctrl_irq_en;

// ---------------------------------------------------------------------------
// RW data registers
// ---------------------------------------------------------------------------
reg [15:0]  reg_setpoint; // signed 16-bit
reg [31:0]  reg_kp;
reg [31:0]  reg_ki;
reg [31:0]  reg_kd;
reg [15:0]  reg_out_max;  // signed 16-bit
reg [15:0]  reg_out_min;  // signed 16-bit
reg [31:0]  reg_int_max;
reg [31:0]  reg_int_min;

// ---------------------------------------------------------------------------
// Write validity decode (combinational, from captured wr_addr/wr_len/wr_size)
// ---------------------------------------------------------------------------
wire [5:0]  wr_reg_idx;
wire        wr_aligned;
wire        wr_single;
wire        wr_valid_map;
wire        wr_accept;

// 16-bit sign-extension validity for SETPOINT, OUT_MAX, OUT_MIN:
// bits[31:16] must equal the sign-extension of bit[15]
wire        wr_16b_valid;

assign wr_reg_idx   = wr_addr[7:2];
assign wr_aligned   = (wr_addr[1:0] == 2'b00);
assign wr_single    = (wr_len == 8'h00) && (wr_size == 3'b010);

assign wr_valid_map =
	(wr_addr[ADDR_WIDTH-1:8] == {(ADDR_WIDTH-8){1'b0}}) && (
	(wr_reg_idx == `PID_REG_SETPOINT) ||
	(wr_reg_idx == `PID_REG_KP      ) ||
	(wr_reg_idx == `PID_REG_KI      ) ||
	(wr_reg_idx == `PID_REG_KD      ) ||
	(wr_reg_idx == `PID_REG_CTRL    ) ||
	(wr_reg_idx == `PID_REG_STATUS  ) ||
	(wr_reg_idx == `PID_REG_OUT_MAX ) ||
	(wr_reg_idx == `PID_REG_OUT_MIN ) ||
	(wr_reg_idx == `PID_REG_INT_MAX ) ||
	(wr_reg_idx == `PID_REG_INT_MIN ));

// 16-bit sign-extension check:
//   Valid iff wr_data[31:16] == {16{wr_data[15]}}
//   (all-zero upper half means positive, all-ones means negative)
//   Applies only to SETPOINT, OUT_MAX, OUT_MIN.
//   For a full 4-byte strobe (WSTRB=4'hF) we require sign extension.
//   For a partial strobe (byte 0 only or bytes 0+1 only), only lower
//   bytes are written, so sign-extension of upper bytes is N/A.
//   We enforce sign-extension only when both bytes 2 and 3 are written
//   (WSTRB[3:2] != 2'b00) for a 16-bit register.
assign wr_16b_valid =
	// Upper 16 bits must be sign extension of bit[15]
	(wr_data[31:16] == {16{wr_data[15]}});

// A write is accepted for register modification only if:
//   - aligned, single-beat, mapped to writable register
//   - for 16-bit registers, when upper bytes (WSTRB[3:2]) are being
//     written the data must be a valid sign-extension; or upper bytes
//     not being written at all (partial byte-lane write)
//   Note: wr_accept is only evaluated in WR_EXEC; wr_is_burst is separate.
assign wr_accept = wr_aligned && wr_single && wr_valid_map;

// 16-bit register sign-ext check (only matters when upper bytes active)
wire wr_16b_upper_active;
assign wr_16b_upper_active = (wr_strb[2] | wr_strb[3]);

wire wr_16b_reg;
assign wr_16b_reg =
	(wr_reg_idx == `PID_REG_SETPOINT) ||
	(wr_reg_idx == `PID_REG_OUT_MAX ) ||
	(wr_reg_idx == `PID_REG_OUT_MIN );

// If it is a 16-bit register and upper bytes are active, sign-ext must hold
wire wr_16b_ok;
assign wr_16b_ok = !wr_16b_reg || !wr_16b_upper_active || wr_16b_valid;

// Final gated accept (also requires sign-extension OK)
wire wr_do_write;
assign wr_do_write = wr_accept && wr_16b_ok && wr_wlast;

// ---------------------------------------------------------------------------
// Read validity decode (combinational, from captured rd_addr/rd_len/rd_size)
// ---------------------------------------------------------------------------
wire [5:0]  rd_reg_idx;
wire        rd_aligned;
wire        rd_single;
wire        rd_valid_map;
wire        rd_accept;

assign rd_reg_idx  = rd_addr[7:2];
assign rd_aligned  = (rd_addr[1:0] == 2'b00);
assign rd_single   = (rd_len == 8'h00) && (rd_size == 3'b010);
assign rd_valid_map =
	(rd_addr[ADDR_WIDTH-1:8] == {(ADDR_WIDTH-8){1'b0}}) && (
	(rd_reg_idx == `PID_REG_SETPOINT) ||
	(rd_reg_idx == `PID_REG_KP      ) ||
	(rd_reg_idx == `PID_REG_KI      ) ||
	(rd_reg_idx == `PID_REG_KD      ) ||
	(rd_reg_idx == `PID_REG_OUTPUT  ) ||
	(rd_reg_idx == `PID_REG_CTRL    ) ||
	(rd_reg_idx == `PID_REG_STATUS  ) ||
	(rd_reg_idx == `PID_REG_ERROR   ) ||
	(rd_reg_idx == `PID_REG_ACTUAL  ) ||
	(rd_reg_idx == `PID_REG_OUT_MAX ) ||
	(rd_reg_idx == `PID_REG_OUT_MIN ) ||
	(rd_reg_idx == `PID_REG_INT_MAX ) ||
	(rd_reg_idx == `PID_REG_INT_MIN ) ||
	(rd_reg_idx == `PID_REG_VERSION ));
assign rd_accept = rd_aligned && rd_single && rd_valid_map;

// ---------------------------------------------------------------------------
// Register file + sticky status + self-clearing MANUAL_UPDATE
//
// All modifications to w1c_*, ro_*, ctrl_*, reg_* are in ONE always block
// to guarantee single-driver per register.
//
// W1C priority for DONE and OVERRUN:
//   New event from core takes priority over simultaneous W1C clear.
//   We compute the next value as: (current | new_event) & ~(clear & !new_event)
//   which simplifies to: new_event | (current & ~clear)
// ---------------------------------------------------------------------------
// generate register file, sticky status, and ctrl self-clear
always @(posedge clk_i)
begin : reg_file_block
	integer i;

	if (!rst_n_i)
	begin
		w1c_done    <= 1'b0;
		w1c_overrun <= 1'b0;
		ro_sat_hi   <= 1'b0;
		ro_sat_lo   <= 1'b0;
		ro_int_sat  <= 1'b0;
		ctrl_enable     <= 1'b0;
		ctrl_int_reset  <= 1'b0;
		ctrl_manual_upd <= 1'b0;
		ctrl_d_on_meas  <= 1'b0;
		ctrl_aw_en      <= 1'b0;
		ctrl_irq_en     <= 1'b0;
		reg_setpoint <= 16'h0000;
		reg_kp       <= 32'h0000_0000;
		reg_ki       <= 32'h0000_0000;
		reg_kd       <= 32'h0000_0000;
		reg_out_max  <= 16'h7FFF;
		reg_out_min  <= 16'h0000;
		reg_int_max  <= 32'h7FFF_FFFF;
		reg_int_min  <= 32'h8000_0000;
	end
	else
	begin
		// --- Self-clearing MANUAL_UPDATE and INT_RESET ---
		// INT_RESET is a one-cycle command pulse, not a stored level.
		// Both are cleared automatically one cycle after being set.
		if (ctrl_manual_upd)
			ctrl_manual_upd <= 1'b0;
		if (ctrl_int_reset)
			ctrl_int_reset  <= 1'b0;

		// --- SAT_HI, SAT_LO, INT_SAT: reflect result of LAST completed update ---
		// On each core_done_i pulse, overwrite with the current pulse value.
		// This means a non-saturated update clears a previously set flag.
		// Also cleared when ENABLE is low or INT_RESET fires (see below).
		if (core_done_i)
		begin
			ro_sat_hi  <= core_sat_hi_i;
			ro_sat_lo  <= core_sat_lo_i;
			ro_int_sat <= core_int_sat_i;
		end

		// --- W1C sticky bits: DONE and OVERRUN ---
		// New-event priority: new_event | (current & ~sw_clear)
		// (sw_clear is only valid when WR_EXEC fires on STATUS register)
		begin : blk_w1c
			// Determine if software is clearing DONE or OVERRUN this cycle
			reg sw_clr_done;
			reg sw_clr_overrun;
			sw_clr_done    = 1'b0;
			sw_clr_overrun = 1'b0;
			if (wr_state == WR_EXEC && wr_do_write &&
			    (wr_reg_idx == `PID_REG_STATUS) && wr_strb[0])
			begin
				if (wr_data[`PID_STAT_DONE   ]) sw_clr_done    = 1'b1;
				if (wr_data[`PID_STAT_OVERRUN]) sw_clr_overrun = 1'b1;
			end

			// New event wins: set regardless; clear only when no new event
			w1c_done    <= core_done_i    | (w1c_done    & ~sw_clr_done);
			w1c_overrun <= core_overrun_i | (w1c_overrun & ~sw_clr_overrun);
		end

		// --- Register writes (only when WR_EXEC and fully accepted) ---
		if (wr_state == WR_EXEC && wr_do_write)
		begin
			case (wr_reg_idx) // synopsys parallel_case

				`PID_REG_SETPOINT:
				begin
					// 16-bit signed; only bytes 0 and 1 meaningful
					for (i = 0; i < STRB_WIDTH; i = i + 1)
					begin
						if (wr_strb[i] && (i < 2))
							reg_setpoint[(i*8) +: 8] <= wr_data[(i*8) +: 8];
					end
				end

				`PID_REG_KP:
				begin
					for (i = 0; i < STRB_WIDTH; i = i + 1)
					begin
						if (wr_strb[i])
							reg_kp[(i*8) +: 8] <= wr_data[(i*8) +: 8];
					end
				end

				`PID_REG_KI:
				begin
					for (i = 0; i < STRB_WIDTH; i = i + 1)
					begin
						if (wr_strb[i])
							reg_ki[(i*8) +: 8] <= wr_data[(i*8) +: 8];
					end
				end

				`PID_REG_KD:
				begin
					for (i = 0; i < STRB_WIDTH; i = i + 1)
					begin
						if (wr_strb[i])
							reg_kd[(i*8) +: 8] <= wr_data[(i*8) +: 8];
					end
				end

				`PID_REG_CTRL:
				begin
					if (wr_strb[0])
					begin
						ctrl_enable    <= wr_data[`PID_CTRL_ENABLE];
						ctrl_int_reset <= wr_data[`PID_CTRL_INT_RESET];
						if (wr_data[`PID_CTRL_MANUAL_UPDATE])
							ctrl_manual_upd <= 1'b1;
						ctrl_d_on_meas <= wr_data[`PID_CTRL_D_ON_MEAS];
						ctrl_aw_en     <= wr_data[`PID_CTRL_AW_EN];
						ctrl_irq_en    <= wr_data[`PID_CTRL_IRQ_EN];
					end
				end

				`PID_REG_STATUS:
				begin
					// SAT_HI [2], SAT_LO [3], INT_SAT [4] are RO sticky:
					//   writes to these bit positions are ignored.
					// DONE [1] and OVERRUN [5] are W1C; handled in blk_w1c above.
					// BUSY [0] is RO; ignored.
					// Nothing to do here — all W1C logic is in blk_w1c.
					;
				end

				`PID_REG_OUT_MAX:
				begin
					// 16-bit signed; upper bytes ignored by wr_16b_ok check
					for (i = 0; i < STRB_WIDTH; i = i + 1)
					begin
						if (wr_strb[i] && (i < 2))
							reg_out_max[(i*8) +: 8] <= wr_data[(i*8) +: 8];
					end
				end

				`PID_REG_OUT_MIN:
				begin
					for (i = 0; i < STRB_WIDTH; i = i + 1)
					begin
						if (wr_strb[i] && (i < 2))
							reg_out_min[(i*8) +: 8] <= wr_data[(i*8) +: 8];
					end
				end

				`PID_REG_INT_MAX:
				begin
					for (i = 0; i < STRB_WIDTH; i = i + 1)
					begin
						if (wr_strb[i])
							reg_int_max[(i*8) +: 8] <= wr_data[(i*8) +: 8];
					end
				end

				`PID_REG_INT_MIN:
				begin
					for (i = 0; i < STRB_WIDTH; i = i + 1)
					begin
						if (wr_strb[i])
							reg_int_min[(i*8) +: 8] <= wr_data[(i*8) +: 8];
					end
				end

				default: ; // RO or unmapped
			endcase
		end
	end
end

// ---------------------------------------------------------------------------
// Write channel state machine
//
// WR_IDLE  : accept AW, W, or both
// WR_WAIT  : one half captured; wait for the other
// WR_EXEC  : both halves ready; execute write (reg_file_block acts here)
//            Issue BVALID; determine if it is a burst (wr_is_burst)
// WR_RESP  : hold BVALID until BREADY
// WR_DRAIN : multi-beat burst: drain W beats until WLAST; no register write
//
// For bursts (AWLEN > 0):
//   - The first W beat is already captured in WR_WAIT/WR_EXEC.
//   - wr_is_burst = 1 is set in WR_EXEC.
//   - If WLAST was set on the first beat, go directly to WR_RESP.
//   - Otherwise go to WR_DRAIN to consume remaining beats.
//   - BRESP = SLVERR issued regardless; no register modified.
// ---------------------------------------------------------------------------
// generate write channel state machine
always @(posedge clk_i)
begin
	if (!rst_n_i)
	begin
		wr_state      <= WR_IDLE;
		s_axi_awready <= 1'b0;
		s_axi_wready  <= 1'b0;
		s_axi_bvalid  <= 1'b0;
		s_axi_bid     <= {ID_WIDTH{1'b0}};
		s_axi_bresp   <= RESP_OKAY;
		aw_captured   <= 1'b0;
		w_captured    <= 1'b0;
		wr_is_burst   <= 1'b0;
		wr_id         <= {ID_WIDTH{1'b0}};
		wr_addr       <= {ADDR_WIDTH{1'b0}};
		wr_len        <= 8'h00;
		wr_size       <= 3'b000;
		wr_data       <= {DATA_WIDTH{1'b0}};
		wr_strb       <= {STRB_WIDTH{1'b0}};
		wr_wlast      <= 1'b0;
	end
	else
	begin
		s_axi_awready <= 1'b0;
		s_axi_wready  <= 1'b0;

		case (wr_state) // synopsys parallel_case

			// ---------------------------------------------------------------
			WR_IDLE:
			begin
				if (s_axi_awvalid && s_axi_wvalid)
				begin
					s_axi_awready <= 1'b1;
					s_axi_wready  <= 1'b1;
					wr_id         <= s_axi_awid;
					wr_addr       <= s_axi_awaddr;
					wr_len        <= s_axi_awlen;
					wr_size       <= s_axi_awsize;
					wr_data       <= s_axi_wdata;
					wr_strb       <= s_axi_wstrb;
					wr_wlast      <= s_axi_wlast;
					aw_captured   <= 1'b1;
					w_captured    <= 1'b1;
					wr_state      <= WR_EXEC;
				end
				else if (s_axi_awvalid)
				begin
					s_axi_awready <= 1'b1;
					wr_id         <= s_axi_awid;
					wr_addr       <= s_axi_awaddr;
					wr_len        <= s_axi_awlen;
					wr_size       <= s_axi_awsize;
					aw_captured   <= 1'b1;
					w_captured    <= 1'b0;
					wr_state      <= WR_WAIT;
				end
				else if (s_axi_wvalid)
				begin
					s_axi_wready  <= 1'b1;
					wr_data       <= s_axi_wdata;
					wr_strb       <= s_axi_wstrb;
					wr_wlast      <= s_axi_wlast;
					w_captured    <= 1'b1;
					aw_captured   <= 1'b0;
					wr_state      <= WR_WAIT;
				end
			end

			// ---------------------------------------------------------------
			WR_WAIT:
			begin
				if (aw_captured && !w_captured && s_axi_wvalid)
				begin
					s_axi_wready <= 1'b1;
					wr_data      <= s_axi_wdata;
					wr_strb      <= s_axi_wstrb;
					wr_wlast     <= s_axi_wlast;
					w_captured   <= 1'b1;
					wr_state     <= WR_EXEC;
				end
				else if (w_captured && !aw_captured && s_axi_awvalid)
				begin
					s_axi_awready <= 1'b1;
					wr_id         <= s_axi_awid;
					wr_addr       <= s_axi_awaddr;
					wr_len        <= s_axi_awlen;
					wr_size       <= s_axi_awsize;
					aw_captured   <= 1'b1;
					wr_state      <= WR_EXEC;
				end
			end

			// ---------------------------------------------------------------
			WR_EXEC:
			begin
				// Register write executed in reg_file_block (same clock edge).
				// Determine burst vs single.
				aw_captured <= 1'b0;
				w_captured  <= 1'b0;

				if (wr_len != 8'h00)
				begin
					// Multi-beat burst: mark as burst (SLVERR will be issued)
					wr_is_burst  <= 1'b1;
					s_axi_bid    <= wr_id;
					s_axi_bresp  <= RESP_SLVERR;
					// If WLAST was already received on the first beat, go to RESP
					if (wr_wlast)
					begin
						// The first (and apparently only) beat had WLAST set
						// even though AWLEN > 0 — malformed, but drain is done.
						s_axi_bvalid <= 1'b1;
						wr_state     <= WR_RESP;
					end
					else
					begin
						// Need to drain remaining beats
						wr_state <= WR_DRAIN;
					end
				end
				else
				begin
					// Single-beat transaction: WLAST must be 1 (AXI4 requirement).
					// If WLAST == 0, respond SLVERR and do not modify any register.
					wr_is_burst  <= 1'b0;
					s_axi_bid    <= wr_id;
					s_axi_bresp  <= (wr_accept && wr_16b_ok && wr_wlast) ? RESP_OKAY : RESP_SLVERR;
					s_axi_bvalid <= 1'b1;
					wr_state     <= WR_RESP;
				end
			end

			// ---------------------------------------------------------------
			WR_DRAIN:
			begin
				// Accept W beats one by one until WLAST is seen.
				// No register is written during drain.
				if (s_axi_wvalid)
				begin
					s_axi_wready <= 1'b1;
					if (s_axi_wlast)
					begin
						// Final beat consumed; issue SLVERR response
						s_axi_bvalid <= 1'b1;
						wr_state     <= WR_RESP;
					end
				end
			end

			// ---------------------------------------------------------------
			WR_RESP:
			begin
				if (s_axi_bready)
				begin
					s_axi_bvalid <= 1'b0;
					wr_is_burst  <= 1'b0;
					wr_state     <= WR_IDLE;
				end
			end

			default: wr_state <= WR_IDLE;
		endcase
	end
end

// ---------------------------------------------------------------------------
// Read channel state machine
//
// RD_IDLE : accept AR; capture address and ARLEN
// RD_BEAT : for each beat (ARLEN+1 total):
//              - if valid single read: return register data, RESP_OKAY
//              - if burst or invalid: return 0, RESP_SLVERR
//              - assert RVALID; set RLAST on final beat
// RD_WAIT : RVALID asserted; wait for RREADY; decrement counter
//
// rd_beat_cnt starts at rd_len (= ARLEN) and decrements to 0.
// When rd_beat_cnt == 0, the next beat is the last one (RLAST = 1).
// ---------------------------------------------------------------------------
// generate read channel state machine
always @(posedge clk_i)
begin
	if (!rst_n_i)
	begin
		rd_state      <= RD_IDLE;
		s_axi_arready <= 1'b0;
		s_axi_rvalid  <= 1'b0;
		s_axi_rlast   <= 1'b0;
		s_axi_rid     <= {ID_WIDTH{1'b0}};
		s_axi_rdata   <= {DATA_WIDTH{1'b0}};
		s_axi_rresp   <= RESP_OKAY;
		rd_id         <= {ID_WIDTH{1'b0}};
		rd_addr       <= {ADDR_WIDTH{1'b0}};
		rd_len        <= 8'h00;
		rd_size       <= 3'b000;
		rd_beat_cnt   <= 8'h00;
		rd_is_burst   <= 1'b0;
	end
	else
	begin
		s_axi_arready <= 1'b0;

		case (rd_state) // synopsys parallel_case

			// ---------------------------------------------------------------
			RD_IDLE:
			begin
				if (s_axi_arvalid)
				begin
					s_axi_arready <= 1'b1;
					rd_id         <= s_axi_arid;
					rd_addr       <= s_axi_araddr;
					rd_len        <= s_axi_arlen;
					rd_size       <= s_axi_arsize;
					rd_beat_cnt   <= s_axi_arlen; // remaining beats after first
					rd_is_burst   <= (s_axi_arlen != 8'h00);
					rd_state      <= RD_BEAT;
				end
			end

			// ---------------------------------------------------------------
			RD_BEAT:
			begin
				// Present the next read beat
				s_axi_rid   <= rd_id;
				s_axi_rlast <= (rd_beat_cnt == 8'h00); // last beat

				if (rd_is_burst)
				begin
					// Unsupported burst: return zero data, SLVERR, all beats
					s_axi_rdata  <= 32'h0000_0000;
					s_axi_rresp  <= RESP_SLVERR;
				end
				else
				begin
					// Single-beat read
					if (rd_accept)
					begin
						s_axi_rresp <= RESP_OKAY;
						// Register read decode
						case (rd_reg_idx) // synopsys parallel_case
							`PID_REG_SETPOINT:
								s_axi_rdata <= {{16{reg_setpoint[15]}}, reg_setpoint};
							`PID_REG_KP:
								s_axi_rdata <= reg_kp;
							`PID_REG_KI:
								s_axi_rdata <= reg_ki;
							`PID_REG_KD:
								s_axi_rdata <= reg_kd;
							`PID_REG_OUTPUT:
								s_axi_rdata <= {{16{core_out_i[15]}}, core_out_i};
							`PID_REG_CTRL:
								s_axi_rdata <= {26'b0,
								                ctrl_irq_en,
								                ctrl_aw_en,
								                ctrl_d_on_meas,
								                ctrl_manual_upd,
								                ctrl_int_reset,
								                ctrl_enable};
							`PID_REG_STATUS:
								s_axi_rdata <= {26'b0,
								                w1c_overrun,
								                ro_int_sat,
								                ro_sat_lo,
								                ro_sat_hi,
								                w1c_done,
								                core_busy_i};
							`PID_REG_ERROR:
								s_axi_rdata <= {{15{core_error_i[16]}}, core_error_i};
							`PID_REG_ACTUAL:
								s_axi_rdata <= {{16{core_actual_i[15]}}, core_actual_i};
							`PID_REG_OUT_MAX:
								s_axi_rdata <= {{16{reg_out_max[15]}}, reg_out_max};
							`PID_REG_OUT_MIN:
								s_axi_rdata <= {{16{reg_out_min[15]}}, reg_out_min};
							`PID_REG_INT_MAX:
								s_axi_rdata <= reg_int_max;
							`PID_REG_INT_MIN:
								s_axi_rdata <= reg_int_min;
							`PID_REG_VERSION:
								s_axi_rdata <= `PID_VERSION_ID;
							default:
								s_axi_rdata <= 32'h0000_0000;
						endcase
					end
					else
					begin
						// Invalid single-beat: return zero + SLVERR
						s_axi_rdata <= 32'h0000_0000;
						s_axi_rresp <= RESP_SLVERR;
					end
				end
				s_axi_rvalid <= 1'b1;
				rd_state     <= RD_WAIT;
			end

			// ---------------------------------------------------------------
			RD_WAIT:
			begin
				// Hold RVALID until master accepts the beat
				if (s_axi_rready)
				begin
					s_axi_rvalid <= 1'b0;
					s_axi_rlast  <= 1'b0;
					if (rd_beat_cnt == 8'h00)
					begin
						// All beats sent
						rd_is_burst <= 1'b0;
						rd_state    <= RD_IDLE;
					end
					else
					begin
						// More beats to send
						rd_beat_cnt <= rd_beat_cnt - 8'h01;
						rd_state    <= RD_BEAT;
					end
				end
			end

			default: rd_state <= RD_IDLE;
		endcase
	end
end

// ---------------------------------------------------------------------------
// Registered output assignments to pid_core
// ---------------------------------------------------------------------------
// generate register output assignments
always @(posedge clk_i)
begin
	if (!rst_n_i)
	begin
		reg_setpoint_o   <= 16'h0000;
		reg_kp_o         <= 32'h0000_0000;
		reg_ki_o         <= 32'h0000_0000;
		reg_kd_o         <= 32'h0000_0000;
		reg_enable_o     <= 1'b0;
		reg_int_reset_o  <= 1'b0;
		reg_manual_upd_o <= 1'b0;
		reg_d_on_meas_o  <= 1'b0;
		reg_aw_en_o      <= 1'b0;
		reg_irq_en_o     <= 1'b0;
		reg_out_max_o    <= 16'h7FFF;
		reg_out_min_o    <= 16'h0000;
		reg_int_max_o    <= 32'h7FFF_FFFF;
		reg_int_min_o    <= 32'h8000_0000;
	end
	else
	begin
		reg_setpoint_o   <= reg_setpoint;
		reg_kp_o         <= reg_kp;
		reg_ki_o         <= reg_ki;
		reg_kd_o         <= reg_kd;
		reg_enable_o     <= ctrl_enable;
		reg_int_reset_o  <= ctrl_int_reset;
		reg_manual_upd_o <= ctrl_manual_upd;
		reg_d_on_meas_o  <= ctrl_d_on_meas;
		reg_aw_en_o      <= ctrl_aw_en;
		reg_irq_en_o     <= ctrl_irq_en;
		reg_out_max_o    <= reg_out_max;
		reg_out_min_o    <= reg_out_min;
		reg_int_max_o    <= reg_int_max;
		reg_int_min_o    <= reg_int_min;
	end
end

endmodule
