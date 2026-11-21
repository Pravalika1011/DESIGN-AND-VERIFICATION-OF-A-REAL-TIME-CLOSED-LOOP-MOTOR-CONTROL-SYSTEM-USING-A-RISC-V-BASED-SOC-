`timescale 1 ns / 1 ps
/*
================================================================================
 Module         : myip_v1_0_S00_AXI
 Description    : AXI4-Lite Slave – PWM Controller Register Interface

 FIX (STEP 2): Independent AW / W channel buffering.
 The original Xilinx template required AWVALID && WVALID to be asserted
 simultaneously before asserting AWREADY or WREADY.  That is non-compliant:
 AXI4-Lite Section A3.3 states that AW and W channels are independent.

 This implementation captures the address and data separately using two
 internal "pending" flags (aw_pending / w_pending) and a registered copy of
 the write address (aw_addr_buf).  The actual register write occurs once BOTH
 an address AND data beat have been accepted (write_commit).

 All three ordering cases are supported:
   Case A  – AWVALID arrives first  (aw_pending set, waits for W)
   Case B  – WVALID arrives first   (w_pending set, waits for AW)
   Case C  – AWVALID and WVALID together

 Write response (BVALID) is issued after write_commit exactly as before.
 Read path is unchanged.
 PWM counter / duty-cycle logic is unchanged.
================================================================================
*/

module myip_v1_0_S00_AXI #
(
    // Width of S_AXI data bus
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    // Width of S_AXI address bus
    parameter integer C_S_AXI_ADDR_WIDTH = 4
)
(
    // Users to add ports here
    output wire PWM_OUT,
    input  wire [7:0]                        hw_duty_i,
    input  wire                              hw_duty_valid_i,
    // User ports ends

    // Global Clock Signal
    input  wire                              S_AXI_ACLK,
    // Global Reset Signal. This Signal is Active LOW
    input  wire                              S_AXI_ARESETN,

    // Write address channel
    input  wire [C_S_AXI_ADDR_WIDTH-1 : 0]  S_AXI_AWADDR,
    input  wire [2 : 0]                      S_AXI_AWPROT,
    input  wire                              S_AXI_AWVALID,
    output wire                              S_AXI_AWREADY,

    // Write data channel
    input  wire [C_S_AXI_DATA_WIDTH-1 : 0]  S_AXI_WDATA,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input  wire                              S_AXI_WVALID,
    output wire                              S_AXI_WREADY,

    // Write response channel
    output wire [1 : 0]                      S_AXI_BRESP,
    output wire                              S_AXI_BVALID,
    input  wire                              S_AXI_BREADY,

    // Read address channel
    input  wire [C_S_AXI_ADDR_WIDTH-1 : 0]  S_AXI_ARADDR,
    input  wire [2 : 0]                      S_AXI_ARPROT,
    input  wire                              S_AXI_ARVALID,
    output wire                              S_AXI_ARREADY,

    // Read data channel
    output wire [C_S_AXI_DATA_WIDTH-1 : 0]  S_AXI_RDATA,
    output wire [1 : 0]                      S_AXI_RRESP,
    output wire                              S_AXI_RVALID,
    input  wire                              S_AXI_RREADY
);

    // ----------------------------------------------------------------
    // Address decoding constants (32-bit data, 4-byte aligned)
    // ADDR_LSB  = 2  (bits [1:0] are byte-select, ignored for reg index)
    // OPT_MEM_ADDR_BITS = 1  (gives 2 address bits -> 4 registers)
    // ----------------------------------------------------------------
    localparam integer ADDR_LSB          = (C_S_AXI_DATA_WIDTH/32) + 1; // = 2
    localparam integer OPT_MEM_ADDR_BITS = 1;

    // ----------------------------------------------------------------
    // Slave registers (preserved from original – do NOT rename)
    // ----------------------------------------------------------------
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg0;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg1;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg2;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg3;

    // ----------------------------------------------------------------
    // Write-path state
    //   aw_pending  – address beat has been accepted; data not yet
    //   w_pending   – data beat has been accepted; address not yet
    //   aw_addr_buf – registered write address (captured on AW handshake)
    //   wdata_buf   – registered write data  (captured on W  handshake)
    //   wstrb_buf   – registered write strobe (captured on W handshake)
    // ----------------------------------------------------------------
    reg                              aw_pending;   // AW accepted, waiting for W
    reg                              w_pending;    // W  accepted, waiting for AW
    reg [C_S_AXI_ADDR_WIDTH-1 : 0]  aw_addr_buf;
    reg [C_S_AXI_DATA_WIDTH-1 : 0]  wdata_buf;
    reg [(C_S_AXI_DATA_WIDTH/8)-1:0] wstrb_buf;

    // AWREADY: accept a new AW beat when:
    //   - not currently waiting for data to complete a previous AW
    //   - B response not pending (no outstanding write response)
    reg  axi_awready;
    // WREADY: accept a new W beat when:
    //   - not currently waiting for address to complete a previous W
    //   - B response not pending
    reg  axi_wready;

    // B channel
    reg        axi_bvalid;
    reg [1:0]  axi_bresp;

    // Read path (unchanged from original)
    reg [C_S_AXI_ADDR_WIDTH-1 : 0] axi_araddr;
    reg                             axi_arready;
    reg [C_S_AXI_DATA_WIDTH-1 : 0] axi_rdata;
    reg [1:0]                       axi_rresp;
    reg                             axi_rvalid;

    // write_commit: pulse that triggers the actual register update
    wire write_commit;

    // ----------------------------------------------------------------
    // Output assignments
    // ----------------------------------------------------------------
    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = axi_bresp;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = axi_rresp;
    assign S_AXI_RVALID  = axi_rvalid;

    // ================================================================
    // WRITE PATH – independent AW and W channel handling
    // ================================================================

    // ------------------------------------------------------------------
    // AWREADY generation
    // Accept an AW beat when there is no outstanding unmatched AW and
    // when there is no BVALID pending.
    // ------------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_awready  <= 1'b0;
            aw_pending   <= 1'b0;
            aw_addr_buf  <= '0;
        end else begin
            // Default: de-assert for one cycle (pulse)
            axi_awready <= 1'b0;

            if (S_AXI_AWVALID && !aw_pending && !axi_bvalid) begin
                // Accept the AW beat
                axi_awready  <= 1'b1;
                aw_addr_buf  <= S_AXI_AWADDR;

                if (!w_pending) begin
                    // Data beat has NOT arrived yet → stay pending
                    aw_pending <= 1'b1;
                end
                // else: w_pending is set, which means the W beat already
                // arrived → write_commit fires this cycle; aw_pending
                // stays 0 (no need to buffer the address further).
            end

            // Clear aw_pending once write_commit fires (data was waiting)
            if (write_commit && aw_pending) begin
                aw_pending <= 1'b0;
            end

            // Re-open for the next transaction after B handshake
            if (axi_bvalid && S_AXI_BREADY) begin
                aw_pending <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------
    // WREADY generation
    // Accept a W beat when there is no outstanding unmatched W and when
    // there is no BVALID pending.
    // ------------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_wready <= 1'b0;
            w_pending  <= 1'b0;
            wdata_buf  <= '0;
            wstrb_buf  <= '0;
        end else begin
            // Default: de-assert for one cycle (pulse)
            axi_wready <= 1'b0;

            if (S_AXI_WVALID && !w_pending && !axi_bvalid) begin
                // Accept the W beat
                axi_wready <= 1'b1;
                wdata_buf  <= S_AXI_WDATA;
                wstrb_buf  <= S_AXI_WSTRB;

                if (!S_AXI_AWVALID && !aw_pending) begin
                    // Address beat has NOT arrived yet → stay pending
                    w_pending <= 1'b1;
                end
                // else: AW is available (either arriving this cycle via
                // S_AXI_AWVALID or already buffered in aw_pending) →
                // write_commit fires; w_pending stays 0.
            end

            // Clear w_pending once write_commit fires (address was waiting)
            if (write_commit && w_pending) begin
                w_pending <= 1'b0;
            end

            // Re-open for the next transaction after B handshake
            if (axi_bvalid && S_AXI_BREADY) begin
                w_pending <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------
    // write_commit: fires when BOTH address and data have been accepted.
    // Four cases:
    //   (a) AW arrives and w_pending is already set (data buffered)
    //   (b) W arrives and aw_pending is already set (address buffered)
    //   (c) AW and W arrive together (simultaneous)
    //   The aw_addr_buf is valid for cases (b); S_AXI_AWADDR is live for (a)/(c).
    // ------------------------------------------------------------------
    assign write_commit =
        // Case A: AW just accepted, data was already waiting
        (S_AXI_AWVALID && !aw_pending && !axi_bvalid && w_pending) ||
        // Case B: W just accepted, address was already waiting
        (S_AXI_WVALID  && !w_pending  && !axi_bvalid && aw_pending) ||
        // Case C: both AW and W arrive in the same cycle
        (S_AXI_AWVALID && S_AXI_WVALID && !aw_pending && !w_pending && !axi_bvalid);

    // The write address to use: live AW address when AW present this cycle,
    // otherwise the buffered one.
    wire [C_S_AXI_ADDR_WIDTH-1:0] eff_awaddr =
        S_AXI_AWVALID ? S_AXI_AWADDR : aw_addr_buf;

    // The write data to use: live W data when W is accepted this cycle,
    // otherwise the buffered copy.
    wire [C_S_AXI_DATA_WIDTH-1:0] eff_wdata =
        (S_AXI_WVALID && !w_pending) ? S_AXI_WDATA : wdata_buf;

    wire [(C_S_AXI_DATA_WIDTH/8)-1:0] eff_wstrb =
        (S_AXI_WVALID && !w_pending) ? S_AXI_WSTRB : wstrb_buf;

    // ------------------------------------------------------------------
    // Slave register write
    // ------------------------------------------------------------------
    integer byte_index;
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            slv_reg0 <= 0;
            slv_reg1 <= 0;
            slv_reg2 <= 0;
            slv_reg3 <= 0;
        end else begin
            // Hardware closed-loop duty update from PID
            if (hw_duty_valid_i) begin
                slv_reg0[7:0] <= hw_duty_i;
            end

            // AXI write takes priority if addressing slv_reg0 this cycle
            if (write_commit) begin
                case (eff_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS : ADDR_LSB])
                    2'h0: for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1)
                              if (eff_wstrb[byte_index])
                                  slv_reg0[(byte_index*8) +: 8] <= eff_wdata[(byte_index*8) +: 8];
                    2'h1: for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1)
                              if (eff_wstrb[byte_index])
                                  slv_reg1[(byte_index*8) +: 8] <= eff_wdata[(byte_index*8) +: 8];
                    2'h2: for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1)
                              if (eff_wstrb[byte_index])
                                  slv_reg2[(byte_index*8) +: 8] <= eff_wdata[(byte_index*8) +: 8];
                    2'h3: for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1)
                              if (eff_wstrb[byte_index])
                                  slv_reg3[(byte_index*8) +: 8] <= eff_wdata[(byte_index*8) +: 8];
                    default: begin end
                endcase
            end
        end
    end

    // ------------------------------------------------------------------
    // Write response (B channel)
    // ------------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_bvalid <= 1'b0;
            axi_bresp  <= 2'b00;
        end else begin
            if (write_commit && !axi_bvalid) begin
                axi_bvalid <= 1'b1;
                axi_bresp  <= 2'b00; // OKAY
            end else if (axi_bvalid && S_AXI_BREADY) begin
                axi_bvalid <= 1'b0;
            end
        end
    end

    // ================================================================
    // READ PATH (unchanged from original Xilinx template)
    // ================================================================

    // AR channel: accept read address and latch it
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_arready <= 1'b0;
            axi_araddr  <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end else begin
            if (!axi_arready && S_AXI_ARVALID) begin
                axi_arready <= 1'b1;
                axi_araddr  <= S_AXI_ARADDR;
            end else begin
                axi_arready <= 1'b0;
            end
        end
    end

    // R channel: generate RVALID one cycle after AR handshake
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_rvalid <= 1'b0;
            axi_rresp  <= 2'b00;
        end else begin
            if (axi_arready && S_AXI_ARVALID && !axi_rvalid) begin
                axi_rvalid <= 1'b1;
                axi_rresp  <= 2'b00; // OKAY
            end else if (axi_rvalid && S_AXI_RREADY) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    // Read address decode (combinational)
    wire  slv_reg_rden;
    reg  [C_S_AXI_DATA_WIDTH-1:0] reg_data_out;

    assign slv_reg_rden = axi_arready & S_AXI_ARVALID & ~axi_rvalid;

    always @(*) begin
        case (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS : ADDR_LSB])
            2'h0:    reg_data_out = slv_reg0;
            2'h1:    reg_data_out = slv_reg1;
            2'h2:    reg_data_out = slv_reg2;
            2'h3:    reg_data_out = slv_reg3;
            default: reg_data_out = 32'h0;
        endcase
    end

    // Register read data on AR handshake
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_rdata <= 0;
        end else begin
            if (slv_reg_rden)
                axi_rdata <= reg_data_out;
        end
    end

    // ================================================================
    // PWM USER LOGIC (preserved unchanged)
    // ================================================================
    reg [7:0] pwm_counter;
    wire [7:0] duty_cycle;

    assign duty_cycle = slv_reg0[7:0];

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            pwm_counter <= 8'h00;
        else
            pwm_counter <= pwm_counter + 1;
    end

    assign PWM_OUT = (pwm_counter < duty_cycle) ? 1'b1 : 1'b0;

endmodule
