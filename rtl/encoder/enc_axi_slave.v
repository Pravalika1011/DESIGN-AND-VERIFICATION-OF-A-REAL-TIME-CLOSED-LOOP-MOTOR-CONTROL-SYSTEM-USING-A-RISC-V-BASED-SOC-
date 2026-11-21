// =============================================================================
// Project      : Motor-Control SoC - Quadrature Encoder Interface IP
// File         : enc_axi_slave.v
// Description  : Full AXI4 Slave register interface for the QEI Encoder IP.
//
//                Key features (mirrors pid_axi_slave.v architecture):
//                  - Full AXI4 (NOT AXI4-Lite): independent AW / W channels
//                  - Correct ID tracking: BID = captured AWID, RID = ARID
//                  - WSTRB byte-enable support for every RW register
//                  - W1C sticky bits: VALID(0), OVERFLOW(2), ILLEGAL(3),
//                    STALL(4), INDEX_SEEN(5); new-event wins simultaneous clear
//                  - DIR(1) is RO (not W1C); write to STATUS bit[1] ignored
//                  - Self-clearing COUNT_RESET: one-cycle pulse, reads back 0
//                  - SLVERR for misaligned, out-of-map, or burst writes
//                  - Multi-beat write: drain to WLAST, SLVERR, no reg change
//                  - Multi-beat read: ARLEN+1 beats, RDATA=0, SLVERR,
//                    RLAST only on final beat
//                  - Invalid reads: RDATA=0, RRESP=SLVERR
//                  - BVALID held until BREADY; RVALID held until RREADY
//                  - No combinational VALID-to-READY paths
//
//                AXI sideband inputs accepted but not used:
//                  awburst, awlock, awcache, awprot,
//                  arburst, arlock, arcache, arprot
//
//                RO register write policy (same as pid_axi_slave):
//                  A write to a RO register (SPEED, STATUS[DIR], REV_COUNT,
//                  INDEX_POS, RAW_DELTA, VERSION) is decoded, accepted (OKAY),
//                  but the value is not stored.  STATUS is special: it is
//                  partly W1C (bits 0,2,3,4,5) and partly RO (bit 1, DIR).
//
// AXI4 widths  : DATA_WIDTH=32, ADDR_WIDTH=32, ID_WIDTH=8
//
// Reset        : Active-low synchronous (rst_n_i). No initial blocks.
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

module enc_axi_slave #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH   = 8,
    parameter STRB_WIDTH = (DATA_WIDTH/8)
) (
    // Clock and synchronous active-low reset
    input  wire                     clk_i,
    input  wire                     rst_n_i,

    // -------------------------------------------------------------------
    // AXI4 Write Address Channel
    // -------------------------------------------------------------------
    input  wire [ID_WIDTH-1:0]      s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire [7:0]               s_axi_awlen,
    input  wire [2:0]               s_axi_awsize,
    input  wire [1:0]               s_axi_awburst,  // accepted; not used
    input  wire                     s_axi_awlock,   // accepted; not used
    input  wire [3:0]               s_axi_awcache,  // accepted; not used
    input  wire [2:0]               s_axi_awprot,   // accepted; not used
    input  wire                     s_axi_awvalid,
    output reg                      s_axi_awready,

    // -------------------------------------------------------------------
    // AXI4 Write Data Channel
    // -------------------------------------------------------------------
    input  wire [DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [STRB_WIDTH-1:0]    s_axi_wstrb,
    input  wire                     s_axi_wlast,
    input  wire                     s_axi_wvalid,
    output reg                      s_axi_wready,

    // -------------------------------------------------------------------
    // AXI4 Write Response Channel
    // -------------------------------------------------------------------
    output reg  [ID_WIDTH-1:0]      s_axi_bid,
    output reg  [1:0]               s_axi_bresp,
    output reg                      s_axi_bvalid,
    input  wire                     s_axi_bready,

    // -------------------------------------------------------------------
    // AXI4 Read Address Channel
    // -------------------------------------------------------------------
    input  wire [ID_WIDTH-1:0]      s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire [7:0]               s_axi_arlen,
    input  wire [2:0]               s_axi_arsize,
    input  wire [1:0]               s_axi_arburst,  // accepted; not used
    input  wire                     s_axi_arlock,   // accepted; not used
    input  wire [3:0]               s_axi_arcache,  // accepted; not used
    input  wire [2:0]               s_axi_arprot,   // accepted; not used
    input  wire                     s_axi_arvalid,
    output reg                      s_axi_arready,

    // -------------------------------------------------------------------
    // AXI4 Read Data Channel
    // -------------------------------------------------------------------
    output reg  [ID_WIDTH-1:0]      s_axi_rid,
    output reg  [DATA_WIDTH-1:0]    s_axi_rdata,
    output reg  [1:0]               s_axi_rresp,
    output reg                      s_axi_rlast,
    output reg                      s_axi_rvalid,
    input  wire                     s_axi_rready,

    // -------------------------------------------------------------------
    // Register outputs to enc_core
    // -------------------------------------------------------------------
    output reg          reg_enable_o,
    output reg          reg_count_rst_o,      // COUNT_RESET: one-cycle self-clearing
    output reg  [1:0]   reg_mode_o,
    output reg  [1:0]   reg_avg_sel_o,
    output reg          reg_swap_ab_o,
    output reg          reg_idx_clr_en_o,
    output reg          reg_drive_assert_o,
    output reg          reg_fault_en_o,
    output reg  [31:0]  reg_window_o,
    output reg  [3:0]   reg_filter_o,
    output reg  [31:0]  reg_scale_o,
    output reg  [31:0]  reg_stall_tmo_o,
    output reg  [5:0]   reg_irq_en_o,
    output reg          count_load_o,         // one-cycle strobe: load count
    output reg  [31:0]  count_load_val_o,
    output reg          w1c_valid_o,
    output reg          w1c_overflow_o,
    output reg          w1c_illegal_o,
    output reg          w1c_stall_o,
    output reg          w1c_index_seen_o,

    // -------------------------------------------------------------------
    // Readback inputs from enc_core
    // -------------------------------------------------------------------
    input  wire [31:0]  count_i,
    input  wire [15:0]  speed_i,
    input  wire [31:0]  rev_count_i,
    input  wire [31:0]  index_pos_i,
    input  wire [31:0]  raw_delta_i,
    input  wire         stat_valid_i,
    input  wire         stat_dir_i,
    input  wire         stat_overflow_i,
    input  wire         stat_illegal_i,
    input  wire         stat_stall_i,
    input  wire         stat_index_seen_i
);

// ---------------------------------------------------------------------------
// AXI response codes
// ---------------------------------------------------------------------------
localparam RESP_OKAY   = 2'b00;
localparam RESP_SLVERR = 2'b10;

// ---------------------------------------------------------------------------
// Write FSM states
// ---------------------------------------------------------------------------
localparam WR_IDLE  = 3'b000;
localparam WR_WAIT  = 3'b001;
localparam WR_EXEC  = 3'b010;
localparam WR_RESP  = 3'b011;
localparam WR_DRAIN = 3'b100;

reg [2:0]            wr_state;
reg [ID_WIDTH-1:0]   wr_id;
reg [ADDR_WIDTH-1:0] wr_addr;
reg [7:0]            wr_len;
reg [2:0]            wr_size;
reg [DATA_WIDTH-1:0] wr_data;
reg [STRB_WIDTH-1:0] wr_strb;
reg                  wr_wlast;
reg                  aw_captured;
reg                  w_captured;
reg                  wr_is_burst;

// ---------------------------------------------------------------------------
// Read FSM states
// ---------------------------------------------------------------------------
localparam RD_IDLE = 2'b00;
localparam RD_BEAT = 2'b01;
localparam RD_WAIT = 2'b10;

reg [1:0]            rd_state;
reg [ID_WIDTH-1:0]   rd_id;
reg [ADDR_WIDTH-1:0] rd_addr;
reg [7:0]            rd_len;
reg [2:0]            rd_size;       // captured arsize (accepted, not decoded)
reg [7:0]            rd_beat_cnt;
reg                  rd_is_burst;

// ---------------------------------------------------------------------------
// Internal register storage
// ---------------------------------------------------------------------------
// CTRL stored bits
reg         ctrl_enable;
reg         ctrl_count_rst;   // self-clearing after one cycle
reg [1:0]   ctrl_mode;
reg [1:0]   ctrl_avg_sel;
reg         ctrl_swap_ab;
reg         ctrl_idx_clr_en;
reg         ctrl_drive_assert;
reg         ctrl_fault_en;

// Other RW registers
reg [31:0]  reg_window;
reg [3:0]   reg_filter;
reg [31:0]  reg_scale;
reg [31:0]  reg_stall_tmo;
reg [5:0]   reg_irq_en;

// ---------------------------------------------------------------------------
// Write validity decode (from captured wr_*)
// ---------------------------------------------------------------------------
wire [5:0]  wr_reg_idx;
wire        wr_aligned;
wire        wr_single;
wire        wr_valid_map;
wire        wr_accept;
wire        wr_do_write;

assign wr_reg_idx  = wr_addr[7:2];
assign wr_aligned  = (wr_addr[1:0] == 2'b00);
assign wr_single   = (wr_len == 8'h00);

// Valid map: upper address bits must be 0, offset must be in 0x00..0x30
assign wr_valid_map =
    (wr_addr[ADDR_WIDTH-1:8] == {(ADDR_WIDTH-8){1'b0}}) &&
    (wr_addr[7:0] <= `ENC_ADDR_MAX);

// Accept: aligned, single beat, in map
assign wr_accept   = wr_aligned && wr_single && wr_valid_map;

// Do write: accept AND WLAST = 1 (AXI4 requirement for single beat)
assign wr_do_write = wr_accept && wr_wlast;

// ---------------------------------------------------------------------------
// Read validity decode (from captured rd_*)
// ---------------------------------------------------------------------------
wire [5:0]  rd_reg_idx;
wire        rd_aligned;
wire        rd_single;
wire        rd_valid_map;
wire        rd_accept;

assign rd_reg_idx  = rd_addr[7:2];
assign rd_aligned  = (rd_addr[1:0] == 2'b00);
assign rd_single   = (rd_len == 8'h00);
assign rd_valid_map =
    (rd_addr[ADDR_WIDTH-1:8] == {(ADDR_WIDTH-8){1'b0}}) &&
    (rd_addr[7:0] <= `ENC_ADDR_MAX);
assign rd_accept   = rd_aligned && rd_single && rd_valid_map;

// ---------------------------------------------------------------------------
// AXI sideband inputs: accepted per spec but not used by register peripheral.
// Tied to suppress lint-UI. awsize and arsize are captured in wr_size/rd_size
// for protocol record but not decoded (all accesses treated as 32-bit words).
// ---------------------------------------------------------------------------
// VCS lint_off UI
wire [2:0]  unused_awsize  = wr_size;  // captured from s_axi_awsize
wire [2:0]  unused_arsize  = rd_size;  // captured from s_axi_arsize
wire [1:0]  unused_awburst = s_axi_awburst;
wire        unused_awlock  = s_axi_awlock;
wire [3:0]  unused_awcache = s_axi_awcache;
wire [2:0]  unused_awprot  = s_axi_awprot;
wire [1:0]  unused_arburst = s_axi_arburst;
wire        unused_arlock  = s_axi_arlock;
wire [3:0]  unused_arcache = s_axi_arcache;
wire [2:0]  unused_arprot  = s_axi_arprot;
// VCS lint_on UI

// ---------------------------------------------------------------------------
// ENC_COUNT byte-merge: combine current count with WDATA using WSTRB
// Used in reg_file_block for the count_load_val assignment.
// ---------------------------------------------------------------------------
wire [31:0] count_merge;
assign count_merge[7:0]   = wr_strb[0] ? wr_data[7:0]   : count_i[7:0];
assign count_merge[15:8]  = wr_strb[1] ? wr_data[15:8]  : count_i[15:8];
assign count_merge[23:16] = wr_strb[2] ? wr_data[23:16] : count_i[23:16];
assign count_merge[31:24] = wr_strb[3] ? wr_data[31:24] : count_i[31:24];

// ---------------------------------------------------------------------------
// Register file block
// All storage (RW regs, W1C outputs) driven from ONE always block.
// ---------------------------------------------------------------------------
always @(posedge clk_i)
begin : reg_file_block
    integer i;

    if (!rst_n_i)
    begin
        // RW registers – reset values from enc_defines.v
        ctrl_enable       <= 1'b0;
        ctrl_count_rst    <= 1'b0;
        ctrl_mode         <= 2'b00;
        ctrl_avg_sel      <= 2'b00;
        ctrl_swap_ab      <= 1'b0;
        ctrl_idx_clr_en   <= 1'b0;
        ctrl_drive_assert <= 1'b0;
        ctrl_fault_en     <= 1'b0;
        reg_window        <= `ENC_RST_WINDOW;
        reg_filter        <= 4'h2;
        reg_scale         <= `ENC_RST_SCALE;
        reg_stall_tmo     <= `ENC_RST_STALL_TMO;
        reg_irq_en        <= 6'h00;
        // W1C outputs
        w1c_valid_o       <= 1'b0;
        w1c_overflow_o    <= 1'b0;
        w1c_illegal_o     <= 1'b0;
        w1c_stall_o       <= 1'b0;
        w1c_index_seen_o  <= 1'b0;
        count_load_o      <= 1'b0;
        count_load_val_o  <= 32'h0;
    end
    else
    begin
        // -------------------------------------------------------------------
        // Self-clearing bits
        // -------------------------------------------------------------------
        if (ctrl_count_rst)
            ctrl_count_rst <= 1'b0;

        // W1C outputs default to 0 each cycle; set below if a STATUS write occurs
        w1c_valid_o      <= 1'b0;
        w1c_overflow_o   <= 1'b0;
        w1c_illegal_o    <= 1'b0;
        w1c_stall_o      <= 1'b0;
        w1c_index_seen_o <= 1'b0;

        // count_load is a one-cycle strobe
        count_load_o     <= 1'b0;

        // -------------------------------------------------------------------
        // Register writes (only in WR_EXEC with full acceptance)
        // -------------------------------------------------------------------
        if (wr_state == WR_EXEC && wr_do_write)
        begin
            case (wr_reg_idx) // synopsys parallel_case

                // 0x00 ENC_COUNT – write loads position counter
                // Per-byte-lane merge: use count_merge (computed below) as
                // the merged value so all NBAs resolve consistently.
                `ENC_REG_COUNT >> 2 :
                begin
                    count_load_val_o <= count_merge;
                    if (wr_strb != {STRB_WIDTH{1'b0}})
                        count_load_o <= 1'b1;
                end

                // 0x08 ENC_CTRL
                `ENC_REG_CTRL >> 2 :
                begin
                    if (wr_strb[0])
                    begin
                        ctrl_enable       <= wr_data[`ENC_CTRL_ENABLE];
                        if (wr_data[`ENC_CTRL_COUNT_RESET])
                            ctrl_count_rst <= 1'b1;
                        ctrl_mode         <= wr_data[`ENC_CTRL_MODE_HI:`ENC_CTRL_MODE_LO];
                        ctrl_avg_sel      <= wr_data[`ENC_CTRL_AVG_SEL_HI:`ENC_CTRL_AVG_SEL_LO];
                        ctrl_swap_ab      <= wr_data[`ENC_CTRL_SWAP_AB];
                        ctrl_idx_clr_en   <= wr_data[`ENC_CTRL_INDEX_CLR_EN];
                    end
                    if (wr_strb[1])
                    begin
                        ctrl_drive_assert <= wr_data[`ENC_CTRL_DRIVE_ASSERT];
                        ctrl_fault_en     <= wr_data[`ENC_CTRL_FAULT_EN];
                    end
                end

                // 0x0C ENC_STATUS – W1C for bits 0,2,3,4,5; bit 1 (DIR) is RO
                `ENC_REG_STATUS >> 2 :
                begin
                    if (wr_strb[0])
                    begin
                        if (wr_data[`ENC_STAT_VALID])
                            w1c_valid_o     <= 1'b1;
                        if (wr_data[`ENC_STAT_OVERFLOW])
                            w1c_overflow_o  <= 1'b1;
                        if (wr_data[`ENC_STAT_ILLEGAL])
                            w1c_illegal_o   <= 1'b1;
                        if (wr_data[`ENC_STAT_STALL])
                            w1c_stall_o     <= 1'b1;
                        if (wr_data[`ENC_STAT_INDEX_SEEN])
                            w1c_index_seen_o <= 1'b1;
                        // bit 1 DIR: ignored
                    end
                end

                // 0x10 ENC_WINDOW
                `ENC_REG_WINDOW >> 2 :
                begin
                    for (i = 0; i < STRB_WIDTH; i = i + 1)
                    begin
                        if (wr_strb[i])
                            reg_window[(i*8) +: 8] <= wr_data[(i*8) +: 8];
                    end
                end

                // 0x14 ENC_FILTER – only [3:0]
                `ENC_REG_FILTER >> 2 :
                begin
                    if (wr_strb[0])
                        reg_filter <= wr_data[3:0];
                end

                // 0x18 ENC_SCALE
                `ENC_REG_SCALE >> 2 :
                begin
                    for (i = 0; i < STRB_WIDTH; i = i + 1)
                    begin
                        if (wr_strb[i])
                            reg_scale[(i*8) +: 8] <= wr_data[(i*8) +: 8];
                    end
                end

                // 0x1C ENC_STALL_TMO
                `ENC_REG_STALL_TMO >> 2 :
                begin
                    for (i = 0; i < STRB_WIDTH; i = i + 1)
                    begin
                        if (wr_strb[i])
                            reg_stall_tmo[(i*8) +: 8] <= wr_data[(i*8) +: 8];
                    end
                end

                // 0x2C ENC_IRQ_EN – only [5:0]
                `ENC_REG_IRQ_EN >> 2 :
                begin
                    if (wr_strb[0])
                        reg_irq_en <= wr_data[5:0];
                end

                // 0x04 SPEED, 0x20 REV_COUNT, 0x24 INDEX_POS,
                // 0x28 RAW_DELTA, 0x30 VERSION: all RO – decode matches but
                // write is silently accepted with OKAY and no state change.
                default: begin end // RO or unimplemented
            endcase
        end
    end
end

// ---------------------------------------------------------------------------
// Write channel FSM
// ---------------------------------------------------------------------------
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

            WR_EXEC:
            begin
                aw_captured <= 1'b0;
                w_captured  <= 1'b0;

                if (wr_len != 8'h00)
                begin
                    // Multi-beat burst: SLVERR, drain remaining beats
                    wr_is_burst  <= 1'b1;
                    s_axi_bid    <= wr_id;
                    s_axi_bresp  <= RESP_SLVERR;
                    if (wr_wlast)
                    begin
                        s_axi_bvalid <= 1'b1;
                        wr_state     <= WR_RESP;
                    end
                    else
                    begin
                        wr_state <= WR_DRAIN;
                    end
                end
                else
                begin
                    // Single beat: WLAST must be 1; else SLVERR
                    wr_is_burst  <= 1'b0;
                    s_axi_bid    <= wr_id;
                    s_axi_bresp  <= (wr_accept && wr_wlast) ? RESP_OKAY : RESP_SLVERR;
                    s_axi_bvalid <= 1'b1;
                    wr_state     <= WR_RESP;
                end
            end

            WR_DRAIN:
            begin
                if (s_axi_wvalid)
                begin
                    s_axi_wready <= 1'b1;
                    if (s_axi_wlast)
                    begin
                        s_axi_bvalid <= 1'b1;
                        wr_state     <= WR_RESP;
                    end
                end
            end

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
// Read channel FSM
// ---------------------------------------------------------------------------
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

            RD_IDLE:
            begin
                if (s_axi_arvalid)
                begin
                    s_axi_arready <= 1'b1;
                    rd_id         <= s_axi_arid;
                    rd_addr       <= s_axi_araddr;
                    rd_len        <= s_axi_arlen;
                    rd_size       <= s_axi_arsize;
                    rd_beat_cnt   <= s_axi_arlen;
                    rd_is_burst   <= (s_axi_arlen != 8'h00);
                    rd_state      <= RD_BEAT;
                end
            end

            RD_BEAT:
            begin
                s_axi_rid   <= rd_id;
                s_axi_rlast <= (rd_beat_cnt == 8'h00);

                if (rd_is_burst)
                begin
                    s_axi_rdata <= 32'h0;
                    s_axi_rresp <= RESP_SLVERR;
                end
                else if (rd_accept)
                begin
                    s_axi_rresp <= RESP_OKAY;
                    case (rd_reg_idx) // synopsys parallel_case
                        `ENC_REG_COUNT >> 2:
                            s_axi_rdata <= count_i;
                        `ENC_REG_SPEED >> 2:
                            s_axi_rdata <= {{16{speed_i[15]}}, speed_i};
                        `ENC_REG_CTRL >> 2:
                            s_axi_rdata <= {22'b0,
                                            ctrl_fault_en,
                                            ctrl_drive_assert,
                                            ctrl_idx_clr_en,
                                            ctrl_swap_ab,
                                            ctrl_avg_sel,
                                            ctrl_mode,
                                            1'b0,         // COUNT_RESET reads 0
                                            ctrl_enable};
                        `ENC_REG_STATUS >> 2:
                            s_axi_rdata <= {26'b0,
                                            stat_index_seen_i,
                                            stat_stall_i,
                                            stat_illegal_i,
                                            stat_overflow_i,
                                            stat_dir_i,
                                            stat_valid_i};
                        `ENC_REG_WINDOW >> 2:
                            s_axi_rdata <= reg_window;
                        `ENC_REG_FILTER >> 2:
                            s_axi_rdata <= {28'b0, reg_filter};
                        `ENC_REG_SCALE >> 2:
                            s_axi_rdata <= reg_scale;
                        `ENC_REG_STALL_TMO >> 2:
                            s_axi_rdata <= reg_stall_tmo;
                        `ENC_REG_REV_COUNT >> 2:
                            s_axi_rdata <= rev_count_i;
                        `ENC_REG_INDEX_POS >> 2:
                            s_axi_rdata <= index_pos_i;
                        `ENC_REG_RAW_DELTA >> 2:
                            s_axi_rdata <= raw_delta_i;
                        `ENC_REG_IRQ_EN >> 2:
                            s_axi_rdata <= {26'b0, reg_irq_en};
                        `ENC_REG_VERSION >> 2:
                            s_axi_rdata <= `ENC_VERSION_ID;
                        default:
                            s_axi_rdata <= 32'h0;
                    endcase
                end
                else
                begin
                    s_axi_rdata <= 32'h0;
                    s_axi_rresp <= RESP_SLVERR;
                end

                s_axi_rvalid <= 1'b1;
                rd_state     <= RD_WAIT;
            end

            RD_WAIT:
            begin
                if (s_axi_rready)
                begin
                    s_axi_rvalid <= 1'b0;
                    s_axi_rlast  <= 1'b0;
                    if (rd_beat_cnt == 8'h00)
                    begin
                        rd_is_burst <= 1'b0;
                        rd_state    <= RD_IDLE;
                    end
                    else
                    begin
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
// Registered outputs to enc_core
// ---------------------------------------------------------------------------
always @(posedge clk_i)
begin
    if (!rst_n_i)
    begin
        reg_enable_o       <= 1'b0;
        reg_count_rst_o    <= 1'b0;
        reg_mode_o         <= 2'b00;
        reg_avg_sel_o      <= 2'b00;
        reg_swap_ab_o      <= 1'b0;
        reg_idx_clr_en_o   <= 1'b0;
        reg_drive_assert_o <= 1'b0;
        reg_fault_en_o     <= 1'b0;
        reg_window_o       <= `ENC_RST_WINDOW;
        reg_filter_o       <= 4'h2;
        reg_scale_o        <= `ENC_RST_SCALE;
        reg_stall_tmo_o    <= `ENC_RST_STALL_TMO;
        reg_irq_en_o       <= 6'h00;
    end
    else
    begin
        reg_enable_o       <= ctrl_enable;
        reg_count_rst_o    <= ctrl_count_rst;
        reg_mode_o         <= ctrl_mode;
        reg_avg_sel_o      <= ctrl_avg_sel;
        reg_swap_ab_o      <= ctrl_swap_ab;
        reg_idx_clr_en_o   <= ctrl_idx_clr_en;
        reg_drive_assert_o <= ctrl_drive_assert;
        reg_fault_en_o     <= ctrl_fault_en;
        reg_window_o       <= reg_window;
        reg_filter_o       <= reg_filter;
        reg_scale_o        <= reg_scale;
        reg_stall_tmo_o    <= reg_stall_tmo;
        reg_irq_en_o       <= reg_irq_en;
    end
end

endmodule
