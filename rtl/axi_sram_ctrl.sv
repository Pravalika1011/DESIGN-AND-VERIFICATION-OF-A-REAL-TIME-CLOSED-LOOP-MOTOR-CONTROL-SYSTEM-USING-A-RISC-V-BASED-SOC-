`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// Module: axi_sram_ctrl
//
// Description:
//   Synchronous 32-bit AXI4 single-port memory controller for IMEM and DMEM.
//   Supports standard single-beat and sequential AXI4 transactions.
//   Default memory contents are initialized to RISC-V NOP (32'h0000_0013).
//   No $readmemh is used, complying strictly with Phase 3 scope restrictions.
// ============================================================================

module axi_sram_ctrl #(
    parameter ADDR_WIDTH = 12,          // 4 KiB address space (4096 bytes)
    parameter DATA_WIDTH = 32,
    parameter STRB_WIDTH = DATA_WIDTH / 8,
    parameter ID_WIDTH   = 8,
    parameter INIT_NOP   = 1           // If 1, initialize array with NOPs
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // AXI4 Slave Interface
    input  wire [ID_WIDTH-1:0]      s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire [7:0]               s_axi_awlen,
    input  wire [2:0]               s_axi_awsize,
    input  wire [1:0]               s_axi_awburst,
    input  wire                     s_axi_awvalid,
    output reg                      s_axi_awready,

    input  wire [DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [STRB_WIDTH-1:0]    s_axi_wstrb,
    input  wire                     s_axi_wlast,
    input  wire                     s_axi_wvalid,
    output reg                      s_axi_wready,

    output reg  [ID_WIDTH-1:0]      s_axi_bid,
    output reg  [1:0]               s_axi_bresp,
    output reg                      s_axi_bvalid,
    input  wire                     s_axi_bready,

    input  wire [ID_WIDTH-1:0]      s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire [7:0]               s_axi_arlen,
    input  wire [2:0]               s_axi_arsize,
    input  wire [1:0]               s_axi_arburst,
    input  wire                     s_axi_arvalid,
    output reg                      s_axi_arready,

    output reg  [ID_WIDTH-1:0]      s_axi_rid,
    output reg  [DATA_WIDTH-1:0]    s_axi_rdata,
    output reg  [1:0]               s_axi_rresp,
    output reg                      s_axi_rlast,
    output reg                      s_axi_rvalid,
    input  wire                     s_axi_rready
);

    localparam WORDS = (1 << ADDR_WIDTH) / 4;
    reg [31:0] mem [0:WORDS-1];

    // Initialization loop (no $readmemh)
    integer idx;
    initial begin
        for (idx = 0; idx < WORDS; idx = idx + 1) begin
            if (INIT_NOP)
                mem[idx] = 32'h0000_0013; // RISC-V NOP (addi x0, x0, 0)
            else
                mem[idx] = 32'h0000_0000;
        end
    end

    // Write path
    reg [ID_WIDTH-1:0]   awid_reg;
    reg [ADDR_WIDTH-3:0] awaddr_reg;
    reg                  aw_captured;
    reg                  w_captured;
    reg [31:0]           wdata_reg;
    reg [3:0]            wstrb_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bid     <= {ID_WIDTH{1'b0}};
            s_axi_bresp   <= 2'b00;
            awid_reg      <= {ID_WIDTH{1'b0}};
            awaddr_reg    <= '0;
            aw_captured   <= 1'b0;
            w_captured    <= 1'b0;
            wdata_reg     <= 32'd0;
            wstrb_reg     <= 4'd0;
        end else begin
            // Clear bvalid on handshake
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            // Address capture
            if (s_axi_awvalid && !aw_captured && !s_axi_awready) begin
                s_axi_awready <= 1'b1;
            end else if (s_axi_awready) begin
                s_axi_awready <= 1'b0;
                aw_captured   <= 1'b1;
                awid_reg      <= s_axi_awid;
                awaddr_reg    <= s_axi_awaddr[ADDR_WIDTH-1:2];
            end

            // Data capture
            if (s_axi_wvalid && !w_captured && !s_axi_wready) begin
                s_axi_wready <= 1'b1;
            end else if (s_axi_wready) begin
                s_axi_wready <= 1'b0;
                w_captured   <= 1'b1;
                wdata_reg    <= s_axi_wdata;
                wstrb_reg    <= s_axi_wstrb;
            end

            // Perform memory write when both address and data are captured
            if ((aw_captured || s_axi_awready) && (w_captured || s_axi_wready) && (!s_axi_bvalid || s_axi_bready)) begin
                if (w_captured ? wstrb_reg[0] : s_axi_wstrb[0])
                    mem[aw_captured ? awaddr_reg : s_axi_awaddr[ADDR_WIDTH-1:2]][7:0]   <= w_captured ? wdata_reg[7:0]   : s_axi_wdata[7:0];
                if (w_captured ? wstrb_reg[1] : s_axi_wstrb[1])
                    mem[aw_captured ? awaddr_reg : s_axi_awaddr[ADDR_WIDTH-1:2]][15:8]  <= w_captured ? wdata_reg[15:8]  : s_axi_wdata[15:8];
                if (w_captured ? wstrb_reg[2] : s_axi_wstrb[2])
                    mem[aw_captured ? awaddr_reg : s_axi_awaddr[ADDR_WIDTH-1:2]][23:16] <= w_captured ? wdata_reg[23:16] : s_axi_wdata[23:16];
                if (w_captured ? wstrb_reg[3] : s_axi_wstrb[3])
                    mem[aw_captured ? awaddr_reg : s_axi_awaddr[ADDR_WIDTH-1:2]][31:24] <= w_captured ? wdata_reg[31:24] : s_axi_wdata[31:24];

                aw_captured  <= 1'b0;
                w_captured   <= 1'b0;
                s_axi_bvalid <= 1'b1;
                s_axi_bid    <= aw_captured ? awid_reg : s_axi_awid;
                s_axi_bresp  <= 2'b00;
            end
        end
    end

    // Read path
    reg read_active;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rid     <= {ID_WIDTH{1'b0}};
            s_axi_rdata   <= 32'd0;
            s_axi_rresp   <= 2'b00;
            s_axi_rlast   <= 1'b0;
            read_active   <= 1'b0;
        end else begin
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
                s_axi_rlast  <= 1'b0;
                read_active  <= 1'b0;
            end

            if (s_axi_arvalid && !read_active && !s_axi_arready) begin
                s_axi_arready <= 1'b1;
            end else if (s_axi_arready) begin
                s_axi_arready <= 1'b0;
                s_axi_rvalid  <= 1'b1;
                s_axi_rlast   <= 1'b1;
                s_axi_rid     <= s_axi_arid;
                s_axi_rdata   <= mem[s_axi_araddr[ADDR_WIDTH-1:2]];
                s_axi_rresp   <= 2'b00;
                read_active   <= 1'b1;
            end
        end
    end

endmodule
`default_nettype wire
