`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// Module: axi_width_downconverter_lsu
//
// Description:
//   Bridges VeeR EL2 Load-Store Unit (LSU) 64-bit AXI4 master interface
//   to the SoC 32-bit AXI4 interconnect slave port.
//
//   - Input (Slave port from Core LSU):
//       DATA_WIDTH = 64, TAG_WIDTH = pt.LSU_BUS_TAG (3 bits), ADDR_WIDTH = 32
//   - Output (Master port to Interconnect):
//       DATA_WIDTH = 32, ID_WIDTH = 8, ADDR_WIDTH = 32
//
//   Operation:
//     - Read path:
//         * Translates 64-bit reads (arsize=3) into two sequential 32-bit
//           reads (word0 at addr[2]=0 and word1 at addr[2]=1).
//         * Sub-64-bit reads (arsize<=2, e.g. 32-bit word, 16-bit, 8-bit)
//           are issued as a single 32-bit read, and the returned data is
//           replicated across both 32-bit halves of the 64-bit response so
//           the core receives the data regardless of word alignment.
//     - Write path:
//         * Inspects write strobes (wstrb[7:0]).
//         * If only lower strobes are active (wstrb[7:4]==0), executes a single
//           32-bit write at word0.
//         * If only upper strobes are active (wstrb[3:0]==0), executes a single
//           32-bit write at word1 (addr | 32'h4).
//         * If both are active (full 64-bit write), executes two sequential
//           32-bit writes and returns a combined write response.
// ============================================================================

module axi_width_downconverter_lsu #(
    parameter TAG_WIDTH  = 3,
    parameter ID_WIDTH   = 8,
    parameter ADDR_WIDTH = 32
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // ============================================================
    // Slave Interface: from VeeR EL2 LSU (64-bit data)
    // ============================================================
    // Write Address Channel
    input  wire [TAG_WIDTH-1:0]     s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire [7:0]               s_axi_awlen,
    input  wire [2:0]               s_axi_awsize,
    input  wire [1:0]               s_axi_awburst,
    input  wire                     s_axi_awlock,
    input  wire [3:0]               s_axi_awcache,
    input  wire [2:0]               s_axi_awprot,
    input  wire [3:0]               s_axi_awqos,
    input  wire [3:0]               s_axi_awregion,
    input  wire                     s_axi_awvalid,
    output reg                      s_axi_awready,

    // Write Data Channel
    input  wire [63:0]              s_axi_wdata,
    input  wire [7:0]               s_axi_wstrb,
    input  wire                     s_axi_wlast,
    input  wire                     s_axi_wvalid,
    output reg                      s_axi_wready,

    // Write Response Channel
    output reg  [TAG_WIDTH-1:0]     s_axi_bid,
    output reg  [1:0]               s_axi_bresp,
    output reg                      s_axi_bvalid,
    input  wire                     s_axi_bready,

    // Read Address Channel
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

    // Read Data Channel
    output reg  [TAG_WIDTH-1:0]     s_axi_rid,
    output reg  [63:0]              s_axi_rdata,
    output reg  [1:0]               s_axi_rresp,
    output reg                      s_axi_rlast,
    output reg                      s_axi_rvalid,
    input  wire                     s_axi_rready,

    // ============================================================
    // Master Interface: to 32-bit Interconnect (s01_axi)
    // ============================================================
    // Write Address Channel
    output reg  [ID_WIDTH-1:0]      m_axi_awid,
    output reg  [ADDR_WIDTH-1:0]    m_axi_awaddr,
    output reg  [7:0]               m_axi_awlen,
    output reg  [2:0]               m_axi_awsize,
    output reg  [1:0]               m_axi_awburst,
    output reg                      m_axi_awlock,
    output reg  [3:0]               m_axi_awcache,
    output reg  [2:0]               m_axi_awprot,
    output reg  [3:0]               m_axi_awqos,
    output reg  [3:0]               m_axi_awregion,
    output reg                      m_axi_awvalid,
    input  wire                     m_axi_awready,

    // Write Data Channel
    output reg  [31:0]              m_axi_wdata,
    output reg  [3:0]               m_axi_wstrb,
    output reg                      m_axi_wlast,
    output reg                      m_axi_wvalid,
    input  wire                     m_axi_wready,

    // Write Response Channel
    input  wire [ID_WIDTH-1:0]      m_axi_bid,
    input  wire [1:0]               m_axi_bresp,
    input  wire                     m_axi_bvalid,
    output reg                      m_axi_bready,

    // Read Address Channel
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

    // Read Data Channel
    input  wire [ID_WIDTH-1:0]      m_axi_rid,
    input  wire [31:0]              m_axi_rdata,
    input  wire [1:0]               m_axi_rresp,
    input  wire                     m_axi_rlast,
    input  wire                     m_axi_rvalid,
    output reg                      m_axi_rready
);

    // ============================================================
    // WRITE PATH FSM
    // ============================================================
    localparam [2:0]
        W_IDLE          = 3'd0,
        W_ISSUE_SINGLE  = 3'd1,
        W_WAIT_BRESP    = 3'd2,
        W_DUAL_W0       = 3'd3,
        W_DUAL_W1       = 3'd4,
        W_RSP           = 3'd5;

    reg [2:0] w_state;

    reg [TAG_WIDTH-1:0]  w_req_id;
    reg [ADDR_WIDTH-1:0] w_req_addr;
    reg [2:0]            w_req_size;
    reg [1:0]            w_req_burst;
    reg                  w_req_lock;
    reg [3:0]            w_req_cache;
    reg [2:0]            w_req_prot;
    reg [3:0]            w_req_qos;
    reg [3:0]            w_req_region;
    reg [63:0]           w_req_data;
    reg [7:0]            w_req_strb;

    reg [1:0]            w_bresp0;
    reg [1:0]            w_bresp1;
    reg                  w_is_dual;

    reg aw_done;
    reg w_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_state       <= W_IDLE;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bid     <= {TAG_WIDTH{1'b0}};
            s_axi_bresp   <= 2'b00;

            m_axi_awvalid <= 1'b0;
            m_axi_awid    <= {ID_WIDTH{1'b0}};
            m_axi_awaddr  <= {ADDR_WIDTH{1'b0}};
            m_axi_awlen   <= 8'd0;
            m_axi_awsize  <= 3'd0;
            m_axi_awburst <= 2'd0;
            m_axi_awlock  <= 1'b0;
            m_axi_awcache <= 4'd0;
            m_axi_awprot  <= 3'd0;
            m_axi_awqos   <= 4'd0;
            m_axi_awregion<= 4'd0;

            m_axi_wvalid  <= 1'b0;
            m_axi_wdata   <= 32'd0;
            m_axi_wstrb   <= 4'd0;
            m_axi_wlast   <= 1'b0;
            m_axi_bready  <= 1'b0;

            w_req_id      <= {TAG_WIDTH{1'b0}};
            w_req_addr    <= {ADDR_WIDTH{1'b0}};
            w_req_size    <= 3'd0;
            w_req_burst   <= 2'd0;
            w_req_lock    <= 1'b0;
            w_req_cache   <= 4'd0;
            w_req_prot    <= 3'd0;
            w_req_qos     <= 4'd0;
            w_req_region  <= 4'd0;
            w_req_data    <= 64'd0;
            w_req_strb    <= 8'd0;
            w_bresp0      <= 2'b00;
            w_bresp1      <= 2'b00;
            w_is_dual     <= 1'b0;
            aw_done       <= 1'b0;
            w_done        <= 1'b0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    s_axi_bvalid <= 1'b0;
                    aw_done      <= 1'b0;
                    w_done       <= 1'b0;

                    // Handshake input channels (they can arrive together)
                    if (s_axi_awvalid && s_axi_wvalid) begin
                        s_axi_awready <= 1'b1;
                        s_axi_wready  <= 1'b1;

                        w_req_id      <= s_axi_awid;
                        w_req_addr    <= s_axi_awaddr;
                        w_req_size    <= s_axi_awsize;
                        w_req_burst   <= s_axi_awburst;
                        w_req_lock    <= s_axi_awlock;
                        w_req_cache   <= s_axi_awcache;
                        w_req_prot    <= s_axi_awprot;
                        w_req_qos     <= s_axi_awqos;
                        w_req_region  <= s_axi_awregion;
                        w_req_data    <= s_axi_wdata;
                        w_req_strb    <= s_axi_wstrb;

                        if ((|s_axi_wstrb[3:0]) && (|s_axi_wstrb[7:4])) begin
                            // Both words active: dual-word write
                            w_is_dual <= 1'b1;
                            w_state   <= W_DUAL_W0;
                        end else begin
                            // Single word write
                            w_is_dual <= 1'b0;
                            w_state   <= W_ISSUE_SINGLE;
                        end
                    end else begin
                        s_axi_awready <= 1'b0;
                        s_axi_wready  <= 1'b0;
                    end
                end

                // --------------------------------------------------------
                // Single 32-bit write
                // --------------------------------------------------------
                W_ISSUE_SINGLE: begin
                    s_axi_awready <= 1'b0;
                    s_axi_wready  <= 1'b0;

                    if (!aw_done) begin
                        m_axi_awvalid <= 1'b1;
                        m_axi_awid    <= {{(ID_WIDTH-TAG_WIDTH){1'b0}}, w_req_id};
                        m_axi_awlen   <= 8'd0;
                        m_axi_awsize  <= (w_req_size > 3'b010) ? 3'b010 : w_req_size;
                        m_axi_awburst <= 2'b01;
                        m_axi_awlock  <= w_req_lock;
                        m_axi_awcache <= w_req_cache;
                        m_axi_awprot  <= w_req_prot;
                        m_axi_awqos   <= w_req_qos;
                        m_axi_awregion<= w_req_region;

                        if (|w_req_strb[7:4]) begin
                            // Upper word write (addr[2]=1)
                            m_axi_awaddr <= {w_req_addr[31:3], 3'b100};
                        end else begin
                            // Lower word write (addr[2]=0)
                            m_axi_awaddr <= {w_req_addr[31:3], 3'b000};
                        end
                    end

                    if (!w_done) begin
                        m_axi_wvalid <= 1'b1;
                        m_axi_wlast  <= 1'b1;
                        if (|w_req_strb[7:4]) begin
                            m_axi_wdata <= w_req_data[63:32];
                            m_axi_wstrb <= w_req_strb[7:4];
                        end else begin
                            m_axi_wdata <= w_req_data[31:0];
                            m_axi_wstrb <= w_req_strb[3:0];
                        end
                    end

                    if (m_axi_awvalid && m_axi_awready) begin
                        aw_done       <= 1'b1;
                        m_axi_awvalid <= 1'b0;
                    end
                    if (m_axi_wvalid && m_axi_wready) begin
                        w_done       <= 1'b1;
                        m_axi_wvalid <= 1'b0;
                    end

                    if ((aw_done || (m_axi_awvalid && m_axi_awready)) &&
                        (w_done  || (m_axi_wvalid  && m_axi_wready))) begin
                        m_axi_bready <= 1'b1;
                        w_state      <= W_WAIT_BRESP;
                    end
                end

                W_WAIT_BRESP: begin
                    m_axi_bready <= 1'b1;
                    if (m_axi_bvalid) begin
                        w_bresp0     <= m_axi_bresp;
                        m_axi_bready <= 1'b0;
                        s_axi_bvalid <= 1'b1;
                        s_axi_bid    <= w_req_id;
                        s_axi_bresp  <= m_axi_bresp;
                        w_state      <= W_RSP;
                    end
                end

                // --------------------------------------------------------
                // Dual 32-bit write: Word 0 then Word 1
                // --------------------------------------------------------
                W_DUAL_W0: begin
                    s_axi_awready <= 1'b0;
                    s_axi_wready  <= 1'b0;

                    if (!aw_done) begin
                        m_axi_awvalid  <= 1'b1;
                        m_axi_awid     <= {{(ID_WIDTH-TAG_WIDTH){1'b0}}, w_req_id};
                        m_axi_awaddr   <= {w_req_addr[31:3], 3'b000};
                        m_axi_awlen    <= 8'd0;
                        m_axi_awsize   <= 3'b010;
                        m_axi_awburst  <= 2'b01;
                        m_axi_awlock   <= w_req_lock;
                        m_axi_awcache  <= w_req_cache;
                        m_axi_awprot   <= w_req_prot;
                        m_axi_awqos    <= w_req_qos;
                        m_axi_awregion <= w_req_region;
                    end

                    if (!w_done) begin
                        m_axi_wvalid   <= 1'b1;
                        m_axi_wdata    <= w_req_data[31:0];
                        m_axi_wstrb    <= w_req_strb[3:0];
                        m_axi_wlast    <= 1'b1;
                    end

                    if (m_axi_awvalid && m_axi_awready) begin
                        aw_done       <= 1'b1;
                        m_axi_awvalid <= 1'b0;
                    end
                    if (m_axi_wvalid && m_axi_wready) begin
                        w_done       <= 1'b1;
                        m_axi_wvalid <= 1'b0;
                    end

                    if ((aw_done || (m_axi_awvalid && m_axi_awready)) &&
                        (w_done  || (m_axi_wvalid  && m_axi_wready))) begin
                        m_axi_bready <= 1'b1;
                        // Wait for bresp0
                        if (m_axi_bvalid) begin
                            w_bresp0     <= m_axi_bresp;
                            m_axi_bready <= 1'b0;
                            aw_done      <= 1'b0;
                            w_done       <= 1'b0;
                            w_state      <= W_DUAL_W1;
                        end
                    end
                end

                W_DUAL_W1: begin
                    if (!aw_done) begin
                        m_axi_awvalid  <= 1'b1;
                        m_axi_awid     <= {{(ID_WIDTH-TAG_WIDTH){1'b0}}, w_req_id};
                        m_axi_awaddr   <= {w_req_addr[31:3], 3'b100};
                        m_axi_awlen    <= 8'd0;
                        m_axi_awsize   <= 3'b010;
                        m_axi_awburst  <= 2'b01;
                        m_axi_awlock   <= w_req_lock;
                        m_axi_awcache  <= w_req_cache;
                        m_axi_awprot   <= w_req_prot;
                        m_axi_awqos    <= w_req_qos;
                        m_axi_awregion <= w_req_region;
                    end

                    if (!w_done) begin
                        m_axi_wvalid   <= 1'b1;
                        m_axi_wdata    <= w_req_data[63:32];
                        m_axi_wstrb    <= w_req_strb[7:4];
                        m_axi_wlast    <= 1'b1;
                    end

                    if (m_axi_awvalid && m_axi_awready) begin
                        aw_done       <= 1'b1;
                        m_axi_awvalid <= 1'b0;
                    end
                    if (m_axi_wvalid && m_axi_wready) begin
                        w_done       <= 1'b1;
                        m_axi_wvalid <= 1'b0;
                    end

                    if ((aw_done || (m_axi_awvalid && m_axi_awready)) &&
                        (w_done  || (m_axi_wvalid  && m_axi_wready))) begin
                        m_axi_bready <= 1'b1;
                        if (m_axi_bvalid) begin
                            w_bresp1     <= m_axi_bresp;
                            m_axi_bready <= 1'b0;
                            s_axi_bvalid <= 1'b1;
                            s_axi_bid    <= w_req_id;
                            s_axi_bresp  <= w_bresp0 | m_axi_bresp;
                            w_state      <= W_RSP;
                        end
                    end
                end

                // --------------------------------------------------------
                // Return Write Response to Core LSU
                // --------------------------------------------------------
                W_RSP: begin
                    if (s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        w_state      <= W_IDLE;
                    end
                end

                default: w_state <= W_IDLE;
            endcase
        end
    end

    // ============================================================
    // READ PATH FSM
    // ============================================================
    localparam [2:0]
        R_IDLE          = 3'd0,
        R_AR_WORD0      = 3'd1,
        R_WAIT_WORD0    = 3'd2,
        R_AR_WORD1      = 3'd3,
        R_WAIT_WORD1    = 3'd4,
        R_RSP_DUAL      = 3'd5,
        R_AR_SINGLE     = 3'd6,
        R_WAIT_SINGLE   = 3'd7;

    reg [2:0] r_state;

    reg [TAG_WIDTH-1:0]  r_req_id;
    reg [ADDR_WIDTH-1:0] r_req_addr;
    reg [2:0]            r_req_size;
    reg [1:0]            r_req_burst;
    reg                  r_req_lock;
    reg [3:0]            r_req_cache;
    reg [2:0]            r_req_prot;
    reg [3:0]            r_req_qos;
    reg [3:0]            r_req_region;

    reg [31:0]           r_data_low;
    reg [31:0]           r_data_high;
    reg [1:0]            r_resp_low;
    reg [1:0]            r_resp_high;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state       <= R_IDLE;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rid     <= {TAG_WIDTH{1'b0}};
            s_axi_rdata   <= 64'd0;
            s_axi_rresp   <= 2'b00;
            s_axi_rlast   <= 1'b0;

            m_axi_arvalid <= 1'b0;
            m_axi_arid    <= {ID_WIDTH{1'b0}};
            m_axi_araddr  <= {ADDR_WIDTH{1'b0}};
            m_axi_arlen   <= 8'd0;
            m_axi_arsize  <= 3'd0;
            m_axi_arburst <= 2'd0;
            m_axi_arlock  <= 1'b0;
            m_axi_arcache <= 4'd0;
            m_axi_arprot  <= 3'd0;
            m_axi_arqos   <= 4'd0;
            m_axi_arregion<= 4'd0;
            m_axi_rready  <= 1'b0;

            r_req_id      <= {TAG_WIDTH{1'b0}};
            r_req_addr    <= {ADDR_WIDTH{1'b0}};
            r_req_size    <= 3'd0;
            r_req_burst   <= 2'd0;
            r_req_lock    <= 1'b0;
            r_req_cache   <= 4'd0;
            r_req_prot    <= 3'd0;
            r_req_qos     <= 4'd0;
            r_req_region  <= 4'd0;
            r_data_low    <= 32'd0;
            r_data_high   <= 32'd0;
            r_resp_low    <= 2'b00;
            r_resp_high   <= 2'b00;
        end else begin
            case (r_state)
                R_IDLE: begin
                    s_axi_rvalid <= 1'b0;
                    s_axi_rlast  <= 1'b0;

                    if (s_axi_arvalid) begin
                        s_axi_arready <= 1'b1;
                        r_req_id      <= s_axi_arid;
                        r_req_addr    <= s_axi_araddr;
                        r_req_size    <= s_axi_arsize;
                        r_req_burst   <= s_axi_arburst;
                        r_req_lock    <= s_axi_arlock;
                        r_req_cache   <= s_axi_arcache;
                        r_req_prot    <= s_axi_arprot;
                        r_req_qos     <= s_axi_arqos;
                        r_req_region  <= s_axi_arregion;

                        if (s_axi_arsize >= 3'b011) begin
                            // 64-bit read: 2 beats required
                            r_state <= R_AR_WORD0;
                        end else begin
                            // 32-bit or sub-word read: 1 beat
                            r_state <= R_AR_SINGLE;
                        end
                    end else begin
                        s_axi_arready <= 1'b0;
                    end
                end

                // --------------------------------------------------------
                // Single 32-bit read path
                // --------------------------------------------------------
                R_AR_SINGLE: begin
                    s_axi_arready  <= 1'b0;
                    m_axi_arvalid  <= 1'b1;
                    m_axi_arid     <= {{(ID_WIDTH-TAG_WIDTH){1'b0}}, r_req_id};
                    m_axi_araddr   <= r_req_addr;
                    m_axi_arlen    <= 8'd0;
                    m_axi_arsize   <= r_req_size;
                    m_axi_arburst  <= r_req_burst;
                    m_axi_arlock   <= r_req_lock;
                    m_axi_arcache  <= r_req_cache;
                    m_axi_arprot   <= r_req_prot;
                    m_axi_arqos    <= r_req_qos;
                    m_axi_arregion <= r_req_region;

                    if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        r_state       <= R_WAIT_SINGLE;
                    end
                end

                R_WAIT_SINGLE: begin
                    m_axi_rready <= 1'b1;
                    if (m_axi_rvalid) begin
                        m_axi_rready <= 1'b0;
                        s_axi_rvalid <= 1'b1;
                        s_axi_rid    <= r_req_id;
                        // Replicate across low and high 32 bits
                        s_axi_rdata  <= {m_axi_rdata, m_axi_rdata};
                        s_axi_rresp  <= m_axi_rresp;
                        s_axi_rlast  <= 1'b1;
                        r_state      <= R_RSP_DUAL;
                    end
                end

                // --------------------------------------------------------
                // Dual 32-bit read path: Word 0 then Word 1
                // --------------------------------------------------------
                R_AR_WORD0: begin
                    s_axi_arready  <= 1'b0;
                    m_axi_arvalid  <= 1'b1;
                    m_axi_arid     <= {{(ID_WIDTH-TAG_WIDTH){1'b0}}, r_req_id};
                    m_axi_araddr   <= {r_req_addr[31:3], 3'b000};
                    m_axi_arlen    <= 8'd0;
                    m_axi_arsize   <= 3'b010;
                    m_axi_arburst  <= 2'b01;
                    m_axi_arlock   <= r_req_lock;
                    m_axi_arcache  <= r_req_cache;
                    m_axi_arprot   <= r_req_prot;
                    m_axi_arqos    <= r_req_qos;
                    m_axi_arregion <= r_req_region;

                    if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        r_state       <= R_WAIT_WORD0;
                    end
                end

                R_WAIT_WORD0: begin
                    m_axi_rready <= 1'b1;
                    if (m_axi_rvalid) begin
                        r_data_low   <= m_axi_rdata;
                        r_resp_low   <= m_axi_rresp;
                        m_axi_rready <= 1'b0;
                        r_state      <= R_AR_WORD1;
                    end
                end

                R_AR_WORD1: begin
                    m_axi_arvalid  <= 1'b1;
                    m_axi_arid     <= {{(ID_WIDTH-TAG_WIDTH){1'b0}}, r_req_id};
                    m_axi_araddr   <= {r_req_addr[31:3], 3'b100};
                    m_axi_arlen    <= 8'd0;
                    m_axi_arsize   <= 3'b010;
                    m_axi_arburst  <= 2'b01;
                    m_axi_arlock   <= r_req_lock;
                    m_axi_arcache  <= r_req_cache;
                    m_axi_arprot   <= r_req_prot;
                    m_axi_arqos    <= r_req_qos;
                    m_axi_arregion <= r_req_region;

                    if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        r_state       <= R_WAIT_WORD1;
                    end
                end

                R_WAIT_WORD1: begin
                    m_axi_rready <= 1'b1;
                    if (m_axi_rvalid) begin
                        r_data_high  <= m_axi_rdata;
                        r_resp_high  <= m_axi_rresp;
                        m_axi_rready <= 1'b0;
                        s_axi_rvalid <= 1'b1;
                        s_axi_rid    <= r_req_id;
                        s_axi_rdata  <= {m_axi_rdata, r_data_low};
                        s_axi_rresp  <= r_resp_low | m_axi_rresp;
                        s_axi_rlast  <= 1'b1;
                        r_state      <= R_RSP_DUAL;
                    end
                end

                R_RSP_DUAL: begin
                    if (s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        s_axi_rlast  <= 1'b0;
                        r_state      <= R_IDLE;
                    end
                end

                default: r_state <= R_IDLE;
            endcase
        end
    end

endmodule
`default_nettype wire
