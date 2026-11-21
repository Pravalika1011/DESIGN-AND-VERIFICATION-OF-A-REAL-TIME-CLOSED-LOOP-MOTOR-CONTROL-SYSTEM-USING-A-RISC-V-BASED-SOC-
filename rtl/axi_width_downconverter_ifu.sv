`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// Module: axi_width_downconverter_ifu
//
// Description:
//   Bridges VeeR EL2 Instruction Fetch Unit (IFU) 64-bit AXI4 read-only
//   master interface to the SoC 32-bit AXI4 interconnect slave port.
//
//   - Input (Slave port from Core IFU):
//       DATA_WIDTH = 64, TAG_WIDTH = pt.IFU_BUS_TAG (3 bits), ADDR_WIDTH = 32
//   - Output (Master port to Interconnect):
//       DATA_WIDTH = 32, ID_WIDTH = 8, ADDR_WIDTH = 32
//
//   Operation:
//     - Translates single-beat 64-bit reads (arsize=3, arlen=0) into two
//       sequential 32-bit single-beat reads (arsize=2, arlen=0) for word0
//       (addr[2]=0) and word1 (addr[2]=1).
//     - Combines the two 32-bit read data words into a 64-bit response
//       presented back to VeeR EL2 IFU.
//     - Supports sub-word / 32-bit reads directly in a single access if requested.
// ============================================================================

module axi_width_downconverter_ifu #(
    parameter TAG_WIDTH  = 3,
    parameter ID_WIDTH   = 8,
    parameter ADDR_WIDTH = 32
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // ------------------------------------------------------------
    // Slave Interface: from VeeR EL2 IFU (64-bit data)
    // ------------------------------------------------------------
    input  wire [TAG_WIDTH-1:0]     s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire [7:0]               s_axi_arlen,
    input  wire [2:0]               s_axi_arsize,
    input  wire [1:0]               s_axi_arburst,
    input  wire                     s_axi_arlock,
    input  wire [3:0]               s_axi_arcache,
    input  wire [2:0]               s_axi_arprot,
    input  wire [3:0]               s_axi_arqos,
    input  wire [3:0]               s_axi_arregion,
    input  wire                     s_axi_arvalid,
    output reg                      s_axi_arready,

    output reg  [TAG_WIDTH-1:0]     s_axi_rid,
    output reg  [63:0]              s_axi_rdata,
    output reg  [1:0]               s_axi_rresp,
    output reg                      s_axi_rlast,
    output reg                      s_axi_rvalid,
    input  wire                     s_axi_rready,

    // ------------------------------------------------------------
    // Master Interface: to 32-bit Interconnect (s00_axi)
    // ------------------------------------------------------------
    output reg  [ID_WIDTH-1:0]      m_axi_arid,
    output reg  [ADDR_WIDTH-1:0]    m_axi_araddr,
    output reg  [7:0]               m_axi_arlen,
    output reg  [2:0]               m_axi_arsize,
    output reg  [1:0]               m_axi_arburst,
    output reg                      m_axi_arlock,
    output reg  [3:0]               m_axi_arcache,
    output reg  [2:0]               m_axi_arprot,
    output reg  [3:0]               m_axi_arqos,
    output reg  [3:0]               m_axi_arregion,
    output reg                      m_axi_arvalid,
    input  wire                     m_axi_arready,

    input  wire [ID_WIDTH-1:0]      m_axi_rid,
    input  wire [31:0]              m_axi_rdata,
    input  wire [1:0]               m_axi_rresp,
    input  wire                     m_axi_rlast,
    input  wire                     m_axi_rvalid,
    output reg                      m_axi_rready
);

    // FSM states
    localparam [2:0]
        S_IDLE       = 3'd0,
        S_AR_WORD0   = 3'd1,
        S_R_WORD0    = 3'd2,
        S_AR_WORD1   = 3'd3,
        S_R_WORD1    = 3'd4,
        S_RSP_DUAL   = 3'd5,
        S_AR_SINGLE  = 3'd6,
        S_R_SINGLE   = 3'd7;

    reg [2:0] state;

    // Latched request registers
    reg [TAG_WIDTH-1:0]  req_id;
    reg [ADDR_WIDTH-1:0] req_addr;
    reg [2:0]            req_prot;
    reg [3:0]            req_cache;
    reg [3:0]            req_region;
    reg [3:0]            req_qos;
    reg [2:0]            req_size;
    reg                  req_lock;
    reg [1:0]            req_burst;

    // Data buffers
    reg [31:0] data_low;
    reg [31:0] data_high;
    reg [1:0]  resp_low;
    reg [1:0]  resp_high;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            s_axi_arready  <= 1'b0;
            s_axi_rvalid   <= 1'b0;
            s_axi_rid      <= {TAG_WIDTH{1'b0}};
            s_axi_rdata    <= 64'd0;
            s_axi_rresp    <= 2'b00;
            s_axi_rlast    <= 1'b0;

            m_axi_arvalid  <= 1'b0;
            m_axi_arid     <= {ID_WIDTH{1'b0}};
            m_axi_araddr   <= {ADDR_WIDTH{1'b0}};
            m_axi_arlen    <= 8'd0;
            m_axi_arsize   <= 3'd0;
            m_axi_arburst  <= 2'd0;
            m_axi_arlock   <= 1'b0;
            m_axi_arcache  <= 4'd0;
            m_axi_arprot   <= 3'd0;
            m_axi_arqos    <= 4'd0;
            m_axi_arregion <= 4'd0;
            m_axi_rready   <= 1'b0;

            req_id         <= {TAG_WIDTH{1'b0}};
            req_addr       <= {ADDR_WIDTH{1'b0}};
            req_prot       <= 3'd0;
            req_cache      <= 4'd0;
            req_region     <= 4'd0;
            req_qos        <= 4'd0;
            req_size       <= 3'd0;
            req_lock       <= 1'b0;
            req_burst      <= 2'd0;
            data_low       <= 32'd0;
            data_high      <= 32'd0;
            resp_low       <= 2'b00;
            resp_high      <= 2'b00;
        end else begin
            case (state)
                S_IDLE: begin
                    s_axi_rvalid <= 1'b0;
                    s_axi_rlast  <= 1'b0;
                    if (s_axi_arvalid) begin
                        s_axi_arready  <= 1'b1;
                        req_id         <= s_axi_arid;
                        req_addr       <= s_axi_araddr;
                        req_prot       <= s_axi_arprot;
                        req_cache      <= s_axi_arcache;
                        req_region     <= s_axi_arregion;
                        req_qos        <= s_axi_arqos;
                        req_size       <= s_axi_arsize;
                        req_lock       <= s_axi_arlock;
                        req_burst      <= s_axi_arburst;

                        if (s_axi_arsize >= 3'b011) begin
                            // 64-bit access: need 2 sequential 32-bit reads
                            state <= S_AR_WORD0;
                        end else begin
                            // 32-bit or sub-word access
                            state <= S_AR_SINGLE;
                        end
                    end else begin
                        s_axi_arready <= 1'b0;
                    end
                end

                // --------------------------------------------------------
                // Word 0 (Low 32-bit word, addr[2] = 0)
                // --------------------------------------------------------
                S_AR_WORD0: begin
                    s_axi_arready  <= 1'b0;
                    m_axi_arvalid  <= 1'b1;
                    m_axi_arid     <= {{(ID_WIDTH-TAG_WIDTH){1'b0}}, req_id};
                    m_axi_araddr   <= {req_addr[31:3], 3'b000};
                    m_axi_arlen    <= 8'd0;     // 1 beat
                    m_axi_arsize   <= 3'b010;   // 4 bytes = 32-bit
                    m_axi_arburst  <= 2'b01;   // INCR
                    m_axi_arlock   <= req_lock;
                    m_axi_arcache  <= req_cache;
                    m_axi_arprot   <= req_prot;
                    m_axi_arqos    <= req_qos;
                    m_axi_arregion <= req_region;

                    if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        state         <= S_R_WORD0;
                    end
                end

                S_R_WORD0: begin
                    m_axi_rready <= 1'b1;
                    if (m_axi_rvalid) begin
                        data_low     <= m_axi_rdata;
                        resp_low     <= m_axi_rresp;
                        m_axi_rready <= 1'b0;
                        state        <= S_AR_WORD1;
                    end
                end

                // --------------------------------------------------------
                // Word 1 (High 32-bit word, addr[2] = 1)
                // --------------------------------------------------------
                S_AR_WORD1: begin
                    m_axi_arvalid  <= 1'b1;
                    m_axi_arid     <= {{(ID_WIDTH-TAG_WIDTH){1'b0}}, req_id};
                    m_axi_araddr   <= {req_addr[31:3], 3'b100};
                    m_axi_arlen    <= 8'd0;
                    m_axi_arsize   <= 3'b010;
                    m_axi_arburst  <= 2'b01;
                    m_axi_arlock   <= req_lock;
                    m_axi_arcache  <= req_cache;
                    m_axi_arprot   <= req_prot;
                    m_axi_arqos    <= req_qos;
                    m_axi_arregion <= req_region;

                    if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        state         <= S_R_WORD1;
                    end
                end

                S_R_WORD1: begin
                    m_axi_rready <= 1'b1;
                    if (m_axi_rvalid) begin
                        data_high    <= m_axi_rdata;
                        resp_high    <= m_axi_rresp;
                        m_axi_rready <= 1'b0;
                        s_axi_rvalid <= 1'b1;
                        s_axi_rid    <= req_id;
                        s_axi_rdata  <= {m_axi_rdata, data_low};
                        s_axi_rresp  <= resp_low | m_axi_rresp;
                        s_axi_rlast  <= 1'b1;
                        state        <= S_RSP_DUAL;
                    end
                end

                // --------------------------------------------------------
                // Dual-word response back to VeeR IFU
                // --------------------------------------------------------
                S_RSP_DUAL: begin
                    if (s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        s_axi_rlast  <= 1'b0;
                        state        <= S_IDLE;
                    end
                end

                // --------------------------------------------------------
                // Single-word path (sub-64-bit read)
                // --------------------------------------------------------
                S_AR_SINGLE: begin
                    s_axi_arready  <= 1'b0;
                    m_axi_arvalid  <= 1'b1;
                    m_axi_arid     <= {{(ID_WIDTH-TAG_WIDTH){1'b0}}, req_id};
                    m_axi_araddr   <= req_addr;
                    m_axi_arlen    <= 8'd0;
                    m_axi_arsize   <= req_size;
                    m_axi_arburst  <= req_burst;
                    m_axi_arlock   <= req_lock;
                    m_axi_arcache  <= req_cache;
                    m_axi_arprot   <= req_prot;
                    m_axi_arqos    <= req_qos;
                    m_axi_arregion <= req_region;

                    if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        state         <= S_R_SINGLE;
                    end
                end

                S_R_SINGLE: begin
                    m_axi_rready <= 1'b1;
                    if (m_axi_rvalid) begin
                        data_low     <= m_axi_rdata;
                        resp_low     <= m_axi_rresp;
                        m_axi_rready <= 1'b0;
                        // Return response to core replicating across both 32-bit words
                        s_axi_rvalid <= 1'b1;
                        s_axi_rid    <= req_id;
                        s_axi_rdata  <= {m_axi_rdata, m_axi_rdata};
                        s_axi_rresp  <= m_axi_rresp;
                        s_axi_rlast  <= 1'b1;
                        state        <= S_RSP_DUAL;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
`default_nettype wire
