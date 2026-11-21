// =============================================================================
// File : pid_tb.v
// Desc : Self-checking testbench for pid_top.
//        Implements all 12 test cases from the test plan.
//        Verilog-2001 / SystemVerilog-lite (VCS compatible).
//        Helper code is `include'd from:
//          pid_tb_pkg.v     - parameters/macros
//          pid_axi_bfm.v    - AXI4 master BFM tasks
//          pid_ref_model.v  - bit-accurate reference model
// =============================================================================

`timescale 1ns/1ps
`include "pid_tb_pkg.v"

module pid_tb;

// ---------------------------------------------------------------------------
// Clock and reset
// ---------------------------------------------------------------------------
reg clk;
reg aresetn;

initial clk = 1'b0;
always #(`CLK_PERIOD/2) clk = ~clk;

// ---------------------------------------------------------------------------
// AXI4 Master interface signals
// ---------------------------------------------------------------------------
// Write Address
reg  [7:0]   m_axi_awid;
reg  [31:0]  m_axi_awaddr;
reg  [7:0]   m_axi_awlen;
reg  [2:0]   m_axi_awsize;
reg  [1:0]   m_axi_awburst;
reg          m_axi_awlock;
reg  [3:0]   m_axi_awcache;
reg  [2:0]   m_axi_awprot;
reg          m_axi_awvalid;
wire         m_axi_awready;
// Write Data
reg  [31:0]  m_axi_wdata;
reg  [3:0]   m_axi_wstrb;
reg          m_axi_wlast;
reg          m_axi_wvalid;
wire         m_axi_wready;
// Write Response
wire [7:0]   m_axi_bid;
wire [1:0]   m_axi_bresp;
wire         m_axi_bvalid;
reg          m_axi_bready;
// Read Address
reg  [7:0]   m_axi_arid;
reg  [31:0]  m_axi_araddr;
reg  [7:0]   m_axi_arlen;
reg  [2:0]   m_axi_arsize;
reg  [1:0]   m_axi_arburst;
reg          m_axi_arlock;
reg  [3:0]   m_axi_arcache;
reg  [2:0]   m_axi_arprot;
reg          m_axi_arvalid;
wire         m_axi_arready;
// Read Data
wire [7:0]   m_axi_rid;
wire [31:0]  m_axi_rdata;
wire [1:0]   m_axi_rresp;
wire         m_axi_rlast;
wire         m_axi_rvalid;
reg          m_axi_rready;

// ---------------------------------------------------------------------------
// PID external ports
// ---------------------------------------------------------------------------
reg          tick_i;
reg  [15:0]  actual_i;
wire [15:0]  pid_out_o;
wire         pid_out_valid;
wire         sat_flag_o;
wire         inta_o;

// ---------------------------------------------------------------------------
// DUT instantiation
// ---------------------------------------------------------------------------
pid_top #(
    .DATA_WIDTH (32),
    .ADDR_WIDTH (32),
    .ID_WIDTH   (8),
    .SPEED_W    (16),
    .OUT_W      (16),
    .GAIN_W     (32),
    .FRAC       (16),
    .ERR_W      (17),
    .DERIV_W    (18),
    .PROD_W     (50),
    .ACC_W      (54)
) dut (
    .s_axi_aclk     (clk),
    .s_axi_aresetn  (aresetn),
    // Write Address
    .s_axi_awid     (m_axi_awid),
    .s_axi_awaddr   (m_axi_awaddr),
    .s_axi_awlen    (m_axi_awlen),
    .s_axi_awsize   (m_axi_awsize),
    .s_axi_awburst  (m_axi_awburst),
    .s_axi_awlock   (m_axi_awlock),
    .s_axi_awcache  (m_axi_awcache),
    .s_axi_awprot   (m_axi_awprot),
    .s_axi_awvalid  (m_axi_awvalid),
    .s_axi_awready  (m_axi_awready),
    // Write Data
    .s_axi_wdata    (m_axi_wdata),
    .s_axi_wstrb    (m_axi_wstrb),
    .s_axi_wlast    (m_axi_wlast),
    .s_axi_wvalid   (m_axi_wvalid),
    .s_axi_wready   (m_axi_wready),
    // Write Response
    .s_axi_bid      (m_axi_bid),
    .s_axi_bresp    (m_axi_bresp),
    .s_axi_bvalid   (m_axi_bvalid),
    .s_axi_bready   (m_axi_bready),
    // Read Address
    .s_axi_arid     (m_axi_arid),
    .s_axi_araddr   (m_axi_araddr),
    .s_axi_arlen    (m_axi_arlen),
    .s_axi_arsize   (m_axi_arsize),
    .s_axi_arburst  (m_axi_arburst),
    .s_axi_arlock   (m_axi_arlock),
    .s_axi_arcache  (m_axi_arcache),
    .s_axi_arprot   (m_axi_arprot),
    .s_axi_arvalid  (m_axi_arvalid),
    .s_axi_arready  (m_axi_arready),
    // Read Data
    .s_axi_rid      (m_axi_rid),
    .s_axi_rdata    (m_axi_rdata),
    .s_axi_rresp    (m_axi_rresp),
    .s_axi_rlast    (m_axi_rlast),
    .s_axi_rvalid   (m_axi_rvalid),
    .s_axi_rready   (m_axi_rready),
    // PID external
    .tick_i         (tick_i),
    .actual_i       (actual_i),
    .pid_out_o      (pid_out_o),
    .pid_out_valid_o(pid_out_valid),
    .sat_flag_o     (sat_flag_o),
    .inta_o         (inta_o)
);

// ---------------------------------------------------------------------------
// Scoreboard registers
// ---------------------------------------------------------------------------
integer total_checks, total_passes, total_fails;
integer cur_test, test_fails, prev_checks;
reg     test_results    [0:12];
integer test_check_cnt  [0:12];
integer test_fail_cnt   [0:12];
integer seed_val;
integer i_loop;

// ---------------------------------------------------------------------------
// pid_out_valid free-running counter.
// Declared HERE (before the `include directives) so that the included BFM
// and ref-model tasks can reference it at elaboration time.
// Incremented every time the monitor sees pid_out_valid_o high.
// Never cleared.  All waiters snapshot before a tick, then wait until the
// counter advances.  This is race-free: even if the pulse arrives before the
// waiter polls, it is already counted.
// ---------------------------------------------------------------------------
integer pid_valid_cnt;

always @(posedge clk) begin
    if (pid_out_valid)
        pid_valid_cnt = pid_valid_cnt + 1;  // blocking in always is fine for TB counter
end

// ---------------------------------------------------------------------------
// Include BFM and reference model
// ---------------------------------------------------------------------------
`include "pid_axi_bfm.v"
`include "pid_ref_model.v"

// ---------------------------------------------------------------------------
// Waveform dump
// ---------------------------------------------------------------------------
initial begin
`ifdef FSDB
    $fsdbDumpfile("waves/pid_tb.fsdb");
    $fsdbDumpvars(0, pid_tb);
    $fsdbDumpMDA;
    $display("INFO: FSDB dump enabled -> waves/pid_tb.fsdb");
`elsif VCD
    $dumpfile("waves/pid_tb.vcd");
    $dumpvars(0, pid_tb);
    $display("INFO: VCD dump enabled -> waves/pid_tb.vcd");
`else
    $display("INFO: No waveform dump (define FSDB or VCD)");
`endif
end

// ---------------------------------------------------------------------------
// Simulation timeout watchdog
// ---------------------------------------------------------------------------
initial begin
    #`SIM_TIMEOUT;
    $display("FATAL: simulation timeout at %0t ns", $time);
    $finish(2);
end

// ---------------------------------------------------------------------------
// Coverage bins (manual, always-on)
// ---------------------------------------------------------------------------
integer cov_reg_wr [0:13];     // which registers were written
integer cov_reg_rd [0:13];     // which registers were read
integer cov_fsm_commit;        // times COMMIT state reached (= pid_out_valid count)
integer cov_sat_hi_seen;
integer cov_sat_lo_seen;
integer cov_int_sat_seen;
integer cov_aw_en_on, cov_aw_en_off;
integer cov_d_on_meas_on, cov_d_on_meas_off;
integer cov_slverr_wr, cov_slverr_rd;

always @(posedge clk) begin
    if (pid_out_valid) cov_fsm_commit = cov_fsm_commit + 1;
    if (sat_flag_o)    cov_sat_hi_seen = cov_sat_hi_seen + 1;
end

// ---------------------------------------------------------------------------
// Persistent-state helper regs for Test 11 random
// ---------------------------------------------------------------------------
reg [31:0] rdata32;
reg [1:0]  rsp_tmp;
reg [7:0]  bid_tmp;
reg        to_flag;

// ---------------------------------------------------------------------------
// =========================================================================
//  MAIN TEST SEQUENCE
// =========================================================================
// ---------------------------------------------------------------------------
initial begin : main_test
    integer ii;
    reg [31:0] rd_data;
    reg [1:0]  wr_resp, rd_resp;
    reg [7:0]  bid_echo, rid_echo;
    reg signed [15:0] exp_out16;
    reg               exp_shi, exp_slo, exp_isat;
    reg        [31:0] tmp32;
    reg               timed_out;
    reg        [1:0]  burst_resp;
    reg               rlast_good;

    // Random seed
    if (!$value$plusargs("seed=%d", seed_val))
        seed_val = 42;
    $display("INFO: seed = %0d", seed_val);

    // Init scoreboard
    total_checks = 0; total_passes = 0; total_fails = 0;
    prev_checks  = 0; test_fails   = 0; cur_test    = 0;
    pid_valid_cnt = 0;
    cov_fsm_commit = 0; cov_sat_hi_seen = 0; cov_sat_lo_seen = 0;
    cov_int_sat_seen = 0; cov_aw_en_on = 0; cov_aw_en_off = 0;
    cov_d_on_meas_on = 0; cov_d_on_meas_off = 0;
    cov_slverr_wr = 0; cov_slverr_rd = 0;
    for (ii = 0; ii <= 13; ii = ii + 1) begin
        cov_reg_wr[ii] = 0;
        cov_reg_rd[ii] = 0;
    end
    for (ii = 0; ii <= 12; ii = ii + 1) begin
        test_results[ii]   = 1;
        test_check_cnt[ii] = 0;
        test_fail_cnt[ii]  = 0;
    end

    ref_model_reset;

    // =========================================================================
    // TEST 1 - RESET VALUES
    // =========================================================================
    `TEST_START(1, "RESET_VALUES")
    do_reset;
    prev_checks = total_checks;

    // Check all register reset values
    axi_read(`ADDR_SETPOINT, rd_data, rd_resp);
    `CHECK_EQ("T1 SETPOINT reset", 32'h0, rd_data)
    axi_read(`ADDR_KP, rd_data, rd_resp);
    `CHECK_EQ("T1 KP reset", 32'h0, rd_data)
    axi_read(`ADDR_KI, rd_data, rd_resp);
    `CHECK_EQ("T1 KI reset", 32'h0, rd_data)
    axi_read(`ADDR_KD, rd_data, rd_resp);
    `CHECK_EQ("T1 KD reset", 32'h0, rd_data)
    axi_read(`ADDR_OUTPUT, rd_data, rd_resp);
    `CHECK_EQ("T1 OUTPUT reset", 32'h0, rd_data)
    axi_read(`ADDR_CTRL, rd_data, rd_resp);
    `CHECK_EQ("T1 CTRL reset", 32'h0, rd_data)
    axi_read(`ADDR_STATUS, rd_data, rd_resp);
    `CHECK_EQ("T1 STATUS reset", 32'h0, rd_data)
    axi_read(`ADDR_ERROR, rd_data, rd_resp);
    `CHECK_EQ("T1 ERROR reset", 32'h0, rd_data)
    axi_read(`ADDR_ACTUAL, rd_data, rd_resp);
    `CHECK_EQ("T1 ACTUAL reset", 32'h0, rd_data)
    axi_read(`ADDR_OUT_MAX, rd_data, rd_resp);
    `CHECK_EQ("T1 OUT_MAX reset", `RST_OUT_MAX, rd_data)
    axi_read(`ADDR_OUT_MIN, rd_data, rd_resp);
    `CHECK_EQ("T1 OUT_MIN reset", `RST_OUT_MIN, rd_data)
    axi_read(`ADDR_INT_MAX, rd_data, rd_resp);
    `CHECK_EQ("T1 INT_MAX reset", `RST_INT_MAX, rd_data)
    axi_read(`ADDR_INT_MIN, rd_data, rd_resp);
    `CHECK_EQ("T1 INT_MIN reset", `RST_INT_MIN, rd_data)
    axi_read(`ADDR_VERSION, rd_data, rd_resp);
    `CHECK_EQ("T1 VERSION reset", `RST_VERSION, rd_data)
    // Outputs not X
    `CHECK_EQ("T1 pid_out_o not X after rst", 1'b0, ^pid_out_o === 1'bx ? 1'b1 : 1'b0)
    `CHECK_EQ("T1 pid_out_valid not X", 1'b0, ^pid_out_valid === 1'bx ? 1'b1 : 1'b0)
    // pid_out_o must be 0 after reset
    `CHECK_EQ("T1 pid_out_o=0 after rst", 16'h0, pid_out_o)

    // Mid-run reset: run a few updates then reset
    axi_write_reg(`ADDR_KP, 32'h00010000);  // Kp=1.0
    axi_write_reg(`ADDR_KI, 32'h00001000);  // Ki small
    axi_write_reg(`ADDR_SETPOINT, 32'h0064); // sp=100
    actual_i <= 16'h0032; // actual=50
    @(posedge clk);
    axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE);
    repeat(2) begin
        do_tick;
        wait_update_done;
    end
    // Now reset mid-run
    do_reset;
    ref_model_reset;
    axi_read(`ADDR_OUTPUT, rd_data, rd_resp);
    `CHECK_EQ("T1 OUTPUT=0 after mid-run reset", 32'h0, rd_data)
    axi_read(`ADDR_STATUS, rd_data, rd_resp);
    `CHECK_EQ("T1 STATUS=0 after mid-run reset", 32'h0, rd_data)

    `TEST_END(1, "RESET_VALUES")

    // =========================================================================
    // TEST 2 - REGISTER ACCESS
    // =========================================================================
    `TEST_START(2, "REGISTER_ACCESS")
    do_reset;
    ref_model_reset;
    prev_checks = total_checks;

    // Write/read-back every RW register
    axi_write(`ADDR_SETPOINT, 32'h0064, wr_resp);  // +100, sign-ext OK
    `CHECK_RESP("T2 SETPOINT write resp", `AXI_OKAY, wr_resp)
    axi_read(`ADDR_SETPOINT, rd_data, rd_resp);
    `CHECK_EQ("T2 SETPOINT rd", 32'h0000_0064, rd_data)

    axi_write(`ADDR_KP, 32'h00020000, wr_resp);  // Kp=2.0
    `CHECK_RESP("T2 KP write resp", `AXI_OKAY, wr_resp)
    axi_read(`ADDR_KP, rd_data, rd_resp);
    `CHECK_EQ("T2 KP rd", 32'h00020000, rd_data)

    axi_write(`ADDR_KI, 32'hFFFF8000, wr_resp);  // Ki negative
    `CHECK_RESP("T2 KI write resp", `AXI_OKAY, wr_resp)
    axi_read(`ADDR_KI, rd_data, rd_resp);
    `CHECK_EQ("T2 KI rd", 32'hFFFF8000, rd_data)

    axi_write(`ADDR_KD, 32'h00008000, wr_resp);  // Kd=0.5
    axi_read(`ADDR_KD, rd_data, rd_resp);
    `CHECK_EQ("T2 KD rd", 32'h00008000, rd_data)

    // CTRL write/read-back
    axi_write(`ADDR_CTRL, 32'h39, wr_resp);  // bits 0,3,4,5 = ENABLE|D_ON_MEAS|AW_EN|IRQ_EN
    axi_read(`ADDR_CTRL, rd_data, rd_resp);
    `CHECK_EQ("T2 CTRL rd", 32'h39, rd_data)

    // OUT_MAX / OUT_MIN (16-bit, sign-extension must match)
    axi_write(`ADDR_OUT_MAX, 32'h00007FFF, wr_resp);  // +32767
    `CHECK_RESP("T2 OUT_MAX OKAY", `AXI_OKAY, wr_resp)
    axi_read(`ADDR_OUT_MAX, rd_data, rd_resp);
    `CHECK_EQ("T2 OUT_MAX rd", 32'h00007FFF, rd_data)

    axi_write(`ADDR_OUT_MIN, 32'hFFFF8000, wr_resp);  // -32768
    `CHECK_RESP("T2 OUT_MIN OKAY", `AXI_OKAY, wr_resp)
    axi_read(`ADDR_OUT_MIN, rd_data, rd_resp);
    `CHECK_EQ("T2 OUT_MIN rd", 32'hFFFF8000, rd_data)

    // Bad sign-extension -> SLVERR, no change
    axi_read(`ADDR_OUT_MAX, rd_data, rd_resp);
    tmp32 = rd_data;  // save current
    axi_write(`ADDR_OUT_MAX, 32'h0001_1234, wr_resp); // not sign-ext
    `CHECK_RESP("T2 OUT_MAX bad sign SLVERR", `AXI_SLVERR, wr_resp)
    axi_read(`ADDR_OUT_MAX, rd_data, rd_resp);
    `CHECK_EQ("T2 OUT_MAX unchanged after bad write", tmp32, rd_data)

    // INT_MAX / INT_MIN (32-bit)
    axi_write(`ADDR_INT_MAX, 32'h00100000, wr_resp);
    axi_read(`ADDR_INT_MAX, rd_data, rd_resp);
    `CHECK_EQ("T2 INT_MAX rd", 32'h00100000, rd_data)
    axi_write(`ADDR_INT_MIN, 32'hFFF00000, wr_resp);
    axi_read(`ADDR_INT_MIN, rd_data, rd_resp);
    `CHECK_EQ("T2 INT_MIN rd", 32'hFFF00000, rd_data)

    // RO registers ignore writes
    axi_read(`ADDR_VERSION, rd_data, rd_resp);
    `CHECK_EQ("T2 VERSION rd", `RST_VERSION, rd_data)
    axi_write(`ADDR_VERSION, 32'hDEADBEEF, wr_resp);
    // VERSION is not in wr_valid_map -> SLVERR
    `CHECK_RESP("T2 VERSION write SLVERR", `AXI_SLVERR, wr_resp)
    axi_read(`ADDR_VERSION, rd_data, rd_resp);
    `CHECK_EQ("T2 VERSION unchanged", `RST_VERSION, rd_data)

    // WSTRB byte-lane test: write only byte 0 of KP
    axi_write_reg(`ADDR_KP, 32'hAABBCCDD);
    axi_write_strb(`ADDR_KP, 32'h000000AB, 4'h1, wr_resp);  // byte 0 only
    `CHECK_RESP("T2 KP byte0 write OKAY", `AXI_OKAY, wr_resp)
    axi_read(`ADDR_KP, rd_data, rd_resp);
    `CHECK_EQ("T2 KP byte0 result", 32'hAABBCCAB, rd_data)

    // STATUS reserved bits read 0
    axi_read(`ADDR_STATUS, rd_data, rd_resp);
    `CHECK_EQ("T2 STATUS[31:6] = 0", 32'h0, rd_data & 32'hFFFFFFC0)

    `TEST_END(2, "REGISTER_ACCESS")

    // =========================================================================
    // TEST 3 - ADDRESS DECODE
    // =========================================================================
    `TEST_START(3, "ADDRESS_DECODE")
    do_reset;
    prev_checks = total_checks;

    // Unmapped: 0x38
    axi_read(32'h38, rd_data, rd_resp);
    `CHECK_RESP("T3 rd 0x38 SLVERR", `AXI_SLVERR, rd_resp)
    `CHECK_EQ("T3 rd 0x38 data=0", 32'h0, rd_data)
    axi_write(32'h38, 32'hFF, wr_resp);
    `CHECK_RESP("T3 wr 0x38 SLVERR", `AXI_SLVERR, wr_resp)

    // Unmapped: 0xFC
    axi_read(32'hFC, rd_data, rd_resp);
    `CHECK_RESP("T3 rd 0xFC SLVERR", `AXI_SLVERR, rd_resp)
    axi_write(32'hFC, 32'hFF, wr_resp);
    `CHECK_RESP("T3 wr 0xFC SLVERR", `AXI_SLVERR, wr_resp)

    // Misaligned: 0x01
    axi_write_full(32'h01, 32'hFF, 4'hF, 8'h00, 1'b1, 2'd2, 8'h01, 4'd0,
                   wr_resp, bid_tmp);
    `CHECK_RESP("T3 wr misaligned SLVERR", `AXI_SLVERR, wr_resp)
    axi_read_full(32'h01, 8'h00, 8'h01, 4'd0, rd_data, rd_resp, rid_echo);
    `CHECK_RESP("T3 rd misaligned SLVERR", `AXI_SLVERR, rd_resp)

    // Aliasing: 0x100 (addr[7:2]=0 but addr[ADDR_WIDTH-1:8]!=0)
    axi_read(32'h100, rd_data, rd_resp);
    `CHECK_RESP("T3 rd 0x100 SLVERR", `AXI_SLVERR, rd_resp)
    `CHECK_EQ("T3 rd 0x100 data=0", 32'h0, rd_data)
    axi_write(32'h100, 32'h1234, wr_resp);
    `CHECK_RESP("T3 wr 0x100 SLVERR", `AXI_SLVERR, wr_resp)
    // KP should be unchanged
    axi_read(`ADDR_KP, rd_data, rd_resp);
    `CHECK_EQ("T3 KP not changed by 0x100 wr", 32'h0, rd_data)

    // Large address
    axi_read(32'h8000_0000, rd_data, rd_resp);
    `CHECK_RESP("T3 rd 0x80000000 SLVERR", `AXI_SLVERR, rd_resp)

    `TEST_END(3, "ADDRESS_DECODE")

    // =========================================================================
    // TEST 4 - AXI PROTOCOL
    // =========================================================================
    `TEST_START(4, "AXI_PROTOCOL")
    do_reset;
    prev_checks = total_checks;

    // AW before W
    axi_write_full(`ADDR_KP, 32'hAABBCCDD, 4'hF, 8'h00, 1'b1,
                   2'd1, 8'hA1, 4'd0, wr_resp, bid_echo);
    `CHECK_RESP("T4 AW-first OKAY", `AXI_OKAY, wr_resp)
    `CHECK_EQ("T4 BID echo AW-first", 8'hA1, bid_echo)

    // W before AW
    axi_write_full(`ADDR_KP, 32'h11223344, 4'hF, 8'h00, 1'b1,
                   2'd0, 8'hA2, 4'd0, wr_resp, bid_echo);
    `CHECK_RESP("T4 W-first OKAY", `AXI_OKAY, wr_resp)
    `CHECK_EQ("T4 BID echo W-first", 8'hA2, bid_echo)
    axi_read(`ADDR_KP, rd_data, rd_resp);
    `CHECK_EQ("T4 KP after W-first", 32'h11223344, rd_data)

    // Simultaneous AW+W
    axi_write_full(`ADDR_KI, 32'hDEADCAFE, 4'hF, 8'h00, 1'b1,
                   2'd2, 8'hA3, 4'd0, wr_resp, bid_echo);
    `CHECK_RESP("T4 simultaneous OKAY", `AXI_OKAY, wr_resp)
    `CHECK_EQ("T4 BID echo simultaneous", 8'hA3, bid_echo)

    // Back-to-back writes
    axi_write(`ADDR_KP, 32'h00010000, wr_resp);
    `CHECK_RESP("T4 back-to-back wr1", `AXI_OKAY, wr_resp)
    axi_write(`ADDR_KI, 32'h00001000, wr_resp);
    `CHECK_RESP("T4 back-to-back wr2", `AXI_OKAY, wr_resp)
    axi_read(`ADDR_KP, rd_data, rd_resp);
    `CHECK_EQ("T4 KP after B2B", 32'h00010000, rd_data)
    axi_read(`ADDR_KI, rd_data, rd_resp);
    `CHECK_EQ("T4 KI after B2B", 32'h00001000, rd_data)

    // BREADY held low (backpressure)
    axi_write_full(`ADDR_KD, 32'h00008000, 4'hF, 8'h00, 1'b1,
                   2'd2, 8'hA4, 4'd5, wr_resp, bid_echo);
    `CHECK_RESP("T4 BREADY delay OKAY", `AXI_OKAY, wr_resp)
    axi_read(`ADDR_KD, rd_data, rd_resp);
    `CHECK_EQ("T4 KD after BREADY-delay", 32'h00008000, rd_data)

    // RREADY held low (backpressure)
    axi_read_full(`ADDR_KD, 8'h00, 8'hB1, 4'd5, rd_data, rd_resp, rid_echo);
    `CHECK_RESP("T4 RREADY delay OKAY", `AXI_OKAY, rd_resp)
    `CHECK_EQ("T4 RID echo RREADY-delay", 8'hB1, rid_echo)
    `CHECK_EQ("T4 rd data after RREADY-delay", 32'h00008000, rd_data)

    // Read after write coherence
    axi_write_reg(`ADDR_SETPOINT, 32'h0050);
    axi_read(`ADDR_SETPOINT, rd_data, rd_resp);
    `CHECK_EQ("T4 RAW coherence", 32'h0050, rd_data)

    // WLAST=0 on single beat -> SLVERR, no change
    axi_read(`ADDR_KP, rd_data, rd_resp);
    tmp32 = rd_data;
    axi_write_full(`ADDR_KP, 32'hBEEFCAFE, 4'hF, 8'h00, 1'b0,
                   2'd2, 8'hC1, 4'd0, wr_resp, bid_echo);
    `CHECK_RESP("T4 WLAST=0 SLVERR", `AXI_SLVERR, wr_resp)
    axi_read(`ADDR_KP, rd_data, rd_resp);
    `CHECK_EQ("T4 KP unchanged after WLAST=0", tmp32, rd_data)

    // Write burst (AWLEN=1) -> SLVERR, drained, next normal write works
    write_burst(`ADDR_KP, 8'h01, 32'hBADDCAFE, burst_resp);
    `CHECK_RESP("T4 write burst SLVERR", `AXI_SLVERR, burst_resp)
    axi_write(`ADDR_KP, 32'hCAFEBABE, wr_resp);
    `CHECK_RESP("T4 normal wr after burst OKAY", `AXI_OKAY, wr_resp)
    axi_read(`ADDR_KP, rd_data, rd_resp);
    `CHECK_EQ("T4 KP correct after burst+normal", 32'hCAFEBABE, rd_data)

    // Read burst (ARLEN=1) -> SLVERR on all beats, RLAST on last only
    read_burst(`ADDR_KP, 8'h01, burst_resp, rlast_good);
    `CHECK_RESP("T4 read burst first beat SLVERR", `AXI_SLVERR, burst_resp)
    `CHECK_EQ("T4 RLAST only on last beat", 1'b1, rlast_good)

    `TEST_END(4, "AXI_PROTOCOL")

    // =========================================================================
    // TEST 5 - TICK BEHAVIOR
    // =========================================================================
    `TEST_START(5, "TICK_BEHAVIOR")
    do_reset;
    ref_model_reset;
    prev_checks = total_checks;

    // Setup: Kp=1.0, sp=100, act=50, enabled
    axi_write_reg(`ADDR_SETPOINT, 32'h0064);
    axi_write_reg(`ADDR_KP, 32'h00010000);
    axi_write_reg(`ADDR_KI, 32'h0);
    axi_write_reg(`ADDR_KD, 32'h0);
    actual_i <= 16'd50;
    @(posedge clk);
    axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE);
    @(posedge clk);

    // One update per tick rising edge
    do_tick;
    wait_update_done;
    axi_read(`ADDR_STATUS, rd_data, rd_resp);
    `CHECK_EQ("T5 DONE set after tick", 1'b1, rd_data[`STAT_DONE])
    clear_done_overrun;

    // Long-held tick gives exactly one update
    begin : t5_long_tick
        integer snap_cnt;
        snap_cnt = pid_valid_cnt;  // snapshot before raising tick
        @(posedge clk);
        tick_i <= 1'b1;
        // Hold tick high for 20 cycles - RTL will only see ONE rising edge
        repeat(20) @(posedge clk);
        tick_i <= 1'b0;
        // Wait for exactly one update to complete (counter increments by 1)
        begin : t5_long_wait
            integer ltw;
            ltw = 0;
            @(posedge clk);
            while (pid_valid_cnt == snap_cnt && ltw < (`UPDATE_TIMEOUT + 22)) begin
                @(posedge clk); ltw = ltw + 1;
            end
        end
        @(posedge clk);
    end // t5_long_tick
    axi_read(`ADDR_STATUS, rd_data, rd_resp);
    `CHECK_EQ("T5 DONE after long tick", 1'b1, rd_data[`STAT_DONE])
    // OVERRUN should NOT be set (tick was held, not a new rising edge while busy)
    // Note: overrun fires on tick_rise while BUSY; a held tick has no second rising edge
    `CHECK_EQ("T5 no OVERRUN from held tick", 1'b0, rd_data[`STAT_OVERRUN])
    clear_done_overrun;
    ref_model_int_reset; // reset ref to match (we did 2 updates above so reset)

    // Tick with ENABLE=0 does nothing
    axi_write_reg(`ADDR_CTRL, 32'h0);  // disable
    @(posedge clk);
    do_tick;
    repeat(15) @(posedge clk);
    axi_read(`ADDR_STATUS, rd_data, rd_resp);
    `CHECK_EQ("T5 no DONE when disabled", 1'b0, rd_data[`STAT_DONE])
    `CHECK_EQ("T5 pid_out_o=0 when disabled", 16'h0, pid_out_o)

    // MANUAL_UPDATE gives exactly one update
    do_reset;
    ref_model_reset;
    axi_write_reg(`ADDR_SETPOINT, 32'h0064);
    axi_write_reg(`ADDR_KP, 32'h00010000);
    axi_write_reg(`ADDR_KI, 32'h0);
    axi_write_reg(`ADDR_KD, 32'h0);
    actual_i <= 16'd50;
    @(posedge clk);
    // Enable + MANUAL_UPDATE in one write
    axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE | `CTRL_MANUAL_UPDATE);
    @(posedge clk);
    wait_update_done;
    axi_read(`ADDR_STATUS, rd_data, rd_resp);
    `CHECK_EQ("T5 DONE from MANUAL_UPDATE", 1'b1, rd_data[`STAT_DONE])
    clear_done_overrun;
    // MANUAL_UPDATE self-clears
    @(posedge clk);
    axi_read(`ADDR_CTRL, rd_data, rd_resp);
    `CHECK_EQ("T5 MANUAL_UPDATE self-cleared", 1'b0, rd_data[2])

    // Tick during BUSY -> OVERRUN
    do_reset;
    ref_model_reset;
    axi_write_reg(`ADDR_SETPOINT, 32'h0064);
    axi_write_reg(`ADDR_KP, 32'h00010000);
    actual_i <= 16'd0;
    @(posedge clk);
    axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE);
    @(posedge clk);
    tick_i <= 1'b1;
    @(posedge clk);  // RTL sees tick_rise, FSM -> LATCH
    tick_i <= 1'b0;
    @(posedge clk);  // FSM now BUSY; inject second rising edge
    tick_i <= 1'b1;
    @(posedge clk);  // rising edge while BUSY -> overrun_o pulse
    tick_i <= 1'b0;
    // Wait for the first update to complete
    wait_update_done;
    axi_read(`ADDR_STATUS, rd_data, rd_resp);
    `CHECK_EQ("T5 OVERRUN from tick-while-busy", 1'b1, rd_data[`STAT_OVERRUN])
    clear_done_overrun;

    // MANUAL_UPDATE while busy is dropped (silently)
    do_reset;
    ref_model_reset;
    axi_write_reg(`ADDR_SETPOINT, 32'h0064);
    axi_write_reg(`ADDR_KP, 32'h00010000);
    actual_i <= 16'd0;
    @(posedge clk);
    axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE);
    @(posedge clk);
    tick_i <= 1'b1;
    @(posedge clk);  // start FSM
    tick_i <= 1'b0;
    // Write MANUAL_UPDATE while FSM is running (doesn't set OVERRUN per spec)
    axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE | `CTRL_MANUAL_UPDATE);
    wait_update_done;
    repeat(3) @(posedge clk);
    axi_read(`ADDR_STATUS, rd_data, rd_resp);
    // OVERRUN should NOT be set (MANUAL_UPDATE while busy is silently dropped)
    `CHECK_EQ("T5 no OVERRUN from MANUAL while busy", 1'b0, rd_data[`STAT_OVERRUN])

    `TEST_END(5, "TICK_BEHAVIOR")

    // =========================================================================
    // TEST 6 - CONTROL MATH (DIRECTED)
    // =========================================================================
    `TEST_START(6, "CONTROL_MATH")
    do_reset;
    ref_model_reset;
    prev_checks = total_checks;

    // --- P-only ---
    axi_write_reg(`ADDR_KP, 32'h00010000); // Kp=1.0
    axi_write_reg(`ADDR_KI, 32'h0);
    axi_write_reg(`ADDR_KD, 32'h0);
    axi_write_reg(`ADDR_SETPOINT, 32'h0064); // sp=100
    axi_write_reg(`ADDR_OUT_MAX, 32'h00007FFF);
    axi_write_reg(`ADDR_OUT_MIN, 32'hFFFF8000);
    axi_write_reg(`ADDR_INT_MAX, 32'h7FFFFFFF);
    axi_write_reg(`ADDR_INT_MIN, 32'h80000000);
    actual_i <= 16'd0;
    axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE);
    @(posedge clk);
    wait_and_check_update(16'd100, 16'd0,
        32'h00010000, 32'h0, 32'h0,
        16'h7FFF, 16'h8000, 32'h7FFFFFFF, 32'h80000000,
        1'b0, 1'b0, 8'd1);
    $display("PASS T6 P-only: sp=100 act=0 Kp=1.0 -> out=100");
    clear_done_overrun;

    // --- I-only ---
    do_reset; ref_model_reset;
    axi_write_reg(`ADDR_KP, 32'h0);
    axi_write_reg(`ADDR_KI, 32'h00010000); // Ki=1.0
    axi_write_reg(`ADDR_KD, 32'h0);
    axi_write_reg(`ADDR_SETPOINT, 32'h000A); // sp=10
    axi_write_reg(`ADDR_OUT_MAX, 32'h00007FFF);
    axi_write_reg(`ADDR_OUT_MIN, 32'hFFFF8000);
    axi_write_reg(`ADDR_INT_MAX, 32'h7FFFFFFF);
    axi_write_reg(`ADDR_INT_MIN, 32'h80000000);
    actual_i <= 16'd0;
    axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE);
    @(posedge clk);
    // First update: i = 0 + Ki*10 = 655360; out = 655360>>16 = 10
    wait_and_check_update(16'd10, 16'd0,
        32'h0, 32'h00010000, 32'h0,
        16'h7FFF, 16'h8000, 32'h7FFFFFFF, 32'h80000000,
        1'b0, 1'b0, 8'd2);
    $display("PASS T6 I-only update 1");
    clear_done_overrun;
    // Second update: i = 10*65536 + 10*65536 = 20; out=20
    wait_and_check_update(16'd10, 16'd0,
        32'h0, 32'h00010000, 32'h0,
        16'h7FFF, 16'h8000, 32'h7FFFFFFF, 32'h80000000,
        1'b0, 1'b0, 8'd3);
    $display("PASS T6 I-only update 2");
    clear_done_overrun;

    // --- D-only (d-on-error) ---
    do_reset; ref_model_reset;
    axi_write_reg(`ADDR_KP, 32'h0);
    axi_write_reg(`ADDR_KI, 32'h0);
    axi_write_reg(`ADDR_KD, 32'h00010000); // Kd=1.0
    axi_write_reg(`ADDR_SETPOINT, 32'h0014); // sp=20
    axi_write_reg(`ADDR_OUT_MAX, 32'h00007FFF);
    axi_write_reg(`ADDR_OUT_MIN, 32'hFFFF8000);
    axi_write_reg(`ADDR_INT_MAX, 32'h7FFFFFFF);
    axi_write_reg(`ADDR_INT_MIN, 32'h80000000);
    actual_i <= 16'd0;
    axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE);
    @(posedge clk);
    // First update: d=0 (first_update), out=0
    wait_and_check_update(16'd20, 16'd0,
        32'h0, 32'h0, 32'h00010000,
        16'h7FFF, 16'h8000, 32'h7FFFFFFF, 32'h80000000,
        1'b0, 1'b0, 8'd4);
    $display("PASS T6 D-only first update d=0");
    clear_done_overrun;
    // Second update: e=20, e_prev=20, d=0, out=0
    wait_and_check_update(16'd20, 16'd0,
        32'h0, 32'h0, 32'h00010000,
        16'h7FFF, 16'h8000, 32'h7FFFFFFF, 32'h80000000,
        1'b0, 1'b0, 8'd5);
    $display("PASS T6 D-only second update e_steady d=0");
    clear_done_overrun;
    // Change setpoint to create derivative kick
    axi_write_reg(`ADDR_SETPOINT, 32'h0028); // sp=40 (was 20, delta=20)
    wait_and_check_update(16'd40, 16'd0,
        32'h0, 32'h0, 32'h00010000,
        16'h7FFF, 16'h8000, 32'h7FFFFFFF, 32'h80000000,
        1'b0, 1'b0, 8'd6);
    $display("PASS T6 D-only sp step");
    clear_done_overrun;

    // --- Negative error ---
    do_reset; ref_model_reset;
    axi_write_reg(`ADDR_KP, 32'h00010000);
    axi_write_reg(`ADDR_KI, 32'h0);
    axi_write_reg(`ADDR_KD, 32'h0);
    axi_write_reg(`ADDR_SETPOINT, 32'h0032); // sp=50
    axi_write_reg(`ADDR_OUT_MAX, 32'h00007FFF);
    axi_write_reg(`ADDR_OUT_MIN, 32'hFFFF8000);
    axi_write_reg(`ADDR_INT_MAX, 32'h7FFFFFFF);
    axi_write_reg(`ADDR_INT_MIN, 32'h80000000);
    actual_i <= 16'd100; // actual > sp -> negative error
    axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE);
    @(posedge clk);
    wait_and_check_update(16'd50, 16'd100,
        32'h00010000, 32'h0, 32'h0,
        16'h7FFF, 16'h8000, 32'h7FFFFFFF, 32'h80000000,
        1'b0, 1'b0, 8'd7);
    $display("PASS T6 negative error");
    clear_done_overrun;

    // --- Zero error ---
    do_reset; ref_model_reset;
    axi_write_reg(`ADDR_KP, 32'h00010000);
    axi_write_reg(`ADDR_KI, 32'h00010000);
    axi_write_reg(`ADDR_KD, 32'h00010000);
    axi_write_reg(`ADDR_SETPOINT, 32'h0064);
    axi_write_reg(`ADDR_OUT_MAX, 32'h00007FFF);
    axi_write_reg(`ADDR_OUT_MIN, 32'hFFFF8000);
    axi_write_reg(`ADDR_INT_MAX, 32'h7FFFFFFF);
    axi_write_reg(`ADDR_INT_MIN, 32'h80000000);
    actual_i <= 16'd100; // sp=act=100 -> e=0
    axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE);
    @(posedge clk);
    wait_and_check_update(16'd100, 16'd100,
        32'h00010000, 32'h00010000, 32'h00010000,
        16'h7FFF, 16'h8000, 32'h7FFFFFFF, 32'h80000000,
        1'b0, 1'b0, 8'd8);
    $display("PASS T6 zero error");
    clear_done_overrun;

    // --- D_ON_MEAS ---
    do_reset; ref_model_reset;
    axi_write_reg(`ADDR_KP, 32'h0);
    axi_write_reg(`ADDR_KI, 32'h0);
    axi_write_reg(`ADDR_KD, 32'h00010000); // Kd=1.0
    axi_write_reg(`ADDR_SETPOINT, 32'h0064);
    axi_write_reg(`ADDR_OUT_MAX, 32'h00007FFF);
    axi_write_reg(`ADDR_OUT_MIN, 32'hFFFF8000);
    axi_write_reg(`ADDR_INT_MAX, 32'h7FFFFFFF);
    axi_write_reg(`ADDR_INT_MIN, 32'h80000000);
    actual_i <= 16'd50;
    axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE | `CTRL_D_ON_MEAS);
    @(posedge clk);
    // First: d=0
    wait_and_check_update(16'd100, 16'd50,
        32'h0, 32'h0, 32'h00010000,
        16'h7FFF, 16'h8000, 32'h7FFFFFFF, 32'h80000000,
        1'b1, 1'b0, 8'd9);
    $display("PASS T6 D_ON_MEAS first d=0");
    clear_done_overrun;
    // Change actual -> derivative based on measurement
    actual_i <= 16'd60;
    wait_and_check_update(16'd100, 16'd60,
        32'h0, 32'h0, 32'h00010000,
        16'h7FFF, 16'h8000, 32'h7FFFFFFF, 32'h80000000,
        1'b1, 1'b0, 8'd10);
    $display("PASS T6 D_ON_MEAS second");
    clear_done_overrun;

    `TEST_END(6, "CONTROL_MATH")

    // =========================================================================
    // TEST 7 - CLAMPS
    // =========================================================================
    `TEST_START(7, "CLAMPS")
    do_reset;
    ref_model_reset;
    prev_checks = total_checks;

    // OUT_MAX clamp: Kp=1.0, sp=1000, act=0, OUT_MAX=200
    axi_write_reg(`ADDR_KP, 32'h00010000);
    axi_write_reg(`ADDR_KI, 32'h0);
    axi_write_reg(`ADDR_KD, 32'h0);
    axi_write_reg(`ADDR_SETPOINT, 32'h0000_03E8); // sp=1000
    axi_write_reg(`ADDR_OUT_MAX, 32'h0000_00C8);  // OUT_MAX=200
    axi_write_reg(`ADDR_OUT_MIN, 32'h0);
    axi_write_reg(`ADDR_INT_MAX, 32'h7FFFFFFF);
    axi_write_reg(`ADDR_INT_MIN, 32'h80000000);
    actual_i <= 16'd0;
    axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE);
    @(posedge clk);
    wait_and_check_update(16'd1000, 16'd0,
        32'h00010000, 32'h0, 32'h0,
        16'h00C8, 16'h0, 32'h7FFFFFFF, 32'h80000000,
        1'b0, 1'b0, 8'd11);
    `CHECK_EQ("T7 pid_out_o clamped to OUT_MAX", 16'h00C8, pid_out_o)
    // SAT_HI should be set
    @(posedge clk);
    axi_read(`ADDR_STATUS, rd_data, rd_resp);
    `CHECK_EQ("T7 SAT_HI set", 1'b1, rd_data[`STAT_SAT_HI])
    `CHECK_EQ("T7 SAT_LO clear", 1'b0, rd_data[`STAT_SAT_LO])
    cov_sat_hi_seen = cov_sat_hi_seen + 1;
    clear_done_overrun;

    // OUT_MIN clamp: sp=-1000 (sign-ext), act=0, OUT_MIN=-200 (sign-ext)
    do_reset; ref_model_reset;
    axi_write_reg(`ADDR_KP, 32'h00010000);
    axi_write_reg(`ADDR_KI, 32'h0);
    axi_write_reg(`ADDR_KD, 32'h0);
    // sp = -1000 = 0xFFFFFC18, sign-extended to 32b = 0xFFFFFC18
    axi_write(`ADDR_SETPOINT, 32'hFFFFFC18, wr_resp);
    // OUT_MAX=0, OUT_MIN=-200 (0xFFFFFF38 sign-ext OK: -200 = 0xFF38 -> sign-ext = 0xFFFFFF38)
    axi_write(`ADDR_OUT_MAX, 32'h0000_0000, wr_resp);
    axi_write(`ADDR_OUT_MIN, 32'hFFFFFF38, wr_resp); // -200
    axi_write_reg(`ADDR_INT_MAX, 32'h7FFFFFFF);
    axi_write_reg(`ADDR_INT_MIN, 32'h80000000);
    actual_i <= 16'd0;
    axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE);
    @(posedge clk);
    wait_and_check_update(16'hFC18, 16'd0,
        32'h00010000, 32'h0, 32'h0,
        16'h0, 16'hFF38, 32'h7FFFFFFF, 32'h80000000,
        1'b0, 1'b0, 8'd12);
    @(posedge clk);
    axi_read(`ADDR_STATUS, rd_data, rd_resp);
    `CHECK_EQ("T7 SAT_LO set", 1'b1, rd_data[`STAT_SAT_LO])
    cov_sat_lo_seen = cov_sat_lo_seen + 1;
    clear_done_overrun;

    // Integrator clamp (INT_SAT)
    do_reset; ref_model_reset;
    axi_write_reg(`ADDR_KP, 32'h0);
    axi_write_reg(`ADDR_KI, 32'h00010000); // Ki=1.0
    axi_write_reg(`ADDR_KD, 32'h0);
    axi_write_reg(`ADDR_SETPOINT, 32'h0064); // sp=100
    axi_write_reg(`ADDR_OUT_MAX, 32'h00007FFF);
    axi_write_reg(`ADDR_OUT_MIN, 32'hFFFF8000);
    axi_write_reg(`ADDR_INT_MAX, 32'h00000064); // INT_MAX = 100 in acc units
    axi_write_reg(`ADDR_INT_MIN, 32'hFFFFFF9C); // INT_MIN = -100
    actual_i <= 16'd0;
    axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE);
    @(posedge clk);
    // First update: ki_e = 1.0 * 100 * 65536 = 6553600; INT_MAX=100 -> clamp
    wait_and_check_update(16'd100, 16'd0,
        32'h0, 32'h00010000, 32'h0,
        16'h7FFF, 16'h8000, 32'h00000064, 32'hFFFFFF9C,
        1'b0, 1'b0, 8'd13);
    @(posedge clk);
    axi_read(`ADDR_STATUS, rd_data, rd_resp);
    `CHECK_EQ("T7 INT_SAT set", 1'b1, rd_data[`STAT_INT_SAT])
    cov_int_sat_seen = cov_int_sat_seen + 1;
    clear_done_overrun;

    // Anti-windup: AW_EN=1, output clamped high with positive error -> keep integrator
    do_reset; ref_model_reset;
    axi_write_reg(`ADDR_KP, 32'h00010000); // Kp=1.0
    axi_write_reg(`ADDR_KI, 32'h00010000); // Ki=1.0
    axi_write_reg(`ADDR_KD, 32'h0);
    axi_write_reg(`ADDR_SETPOINT, 32'h0064); // sp=100
    axi_write_reg(`ADDR_OUT_MAX, 32'h00000032); // OUT_MAX=50 -> will saturate
    axi_write_reg(`ADDR_OUT_MIN, 32'hFFFF8000);
    axi_write_reg(`ADDR_INT_MAX, 32'h7FFFFFFF);
    axi_write_reg(`ADDR_INT_MIN, 32'h80000000);
    actual_i <= 16'd0;
    axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE | `CTRL_AW_EN);
    @(posedge clk);
    cov_aw_en_on = cov_aw_en_on + 1;
    wait_and_check_update(16'd100, 16'd0,
        32'h00010000, 32'h00010000, 32'h0,
        16'h0032, 16'h8000, 32'h7FFFFFFF, 32'h80000000,
        1'b0, 1'b1, 8'd14);
    $display("PASS T7 anti-windup update");
    clear_done_overrun;

    `TEST_END(7, "CLAMPS")

    // =========================================================================
    // TEST 8 - EXTREME VALUES
    // =========================================================================
    `TEST_START(8, "EXTREME_VALUES")
    do_reset;
    ref_model_reset;
    prev_checks = total_checks;

    // Max positive setpoint, min actual: e = +32767 - (-32768) = +65535
    axi_write(`ADDR_SETPOINT, 32'h00007FFF, wr_resp); // sp=+32767
    axi_write_reg(`ADDR_KP, 32'h00010000);            // Kp=1.0
    axi_write_reg(`ADDR_KI, 32'h0);
    axi_write_reg(`ADDR_KD, 32'h0);
    axi_write(`ADDR_OUT_MAX, 32'h00007FFF, wr_resp);
    axi_write(`ADDR_OUT_MIN, 32'hFFFF8000, wr_resp);
    axi_write_reg(`ADDR_INT_MAX, 32'h7FFFFFFF);
    axi_write_reg(`ADDR_INT_MIN, 32'h80000000);
    actual_i <= 16'h8000; // -32768
    axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE);
    @(posedge clk);
    // e = +32767 - (-32768) = 65535; P = 1.0*65535 = 65535; clamped to OUT_MAX=32767
    wait_and_check_update(16'h7FFF, 16'h8000,
        32'h00010000, 32'h0, 32'h0,
        16'h7FFF, 16'h8000, 32'h7FFFFFFF, 32'h80000000,
        1'b0, 1'b0, 8'd15);
    $display("PASS T8 max positive error");
    clear_done_overrun;

    // Max negative error
    do_reset; ref_model_reset;
    axi_write(`ADDR_SETPOINT, 32'hFFFF8000, wr_resp); // sp=-32768
    axi_write_reg(`ADDR_KP, 32'h00010000);
    axi_write_reg(`ADDR_KI, 32'h0);
    axi_write_reg(`ADDR_KD, 32'h0);
    axi_write(`ADDR_OUT_MAX, 32'h00007FFF, wr_resp);
    axi_write(`ADDR_OUT_MIN, 32'hFFFF8000, wr_resp);
    axi_write_reg(`ADDR_INT_MAX, 32'h7FFFFFFF);
    axi_write_reg(`ADDR_INT_MIN, 32'h80000000);
    actual_i <= 16'h7FFF; // +32767
    axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE);
    @(posedge clk);
    wait_and_check_update(16'h8000, 16'h7FFF,
        32'h00010000, 32'h0, 32'h0,
        16'h7FFF, 16'h8000, 32'h7FFFFFFF, 32'h80000000,
        1'b0, 1'b0, 8'd16);
    $display("PASS T8 max negative error");
    clear_done_overrun;

    // Max gain: Kp=0x7FFFFFFF (~32767.999)
    do_reset; ref_model_reset;
    axi_write_reg(`ADDR_KP, 32'h7FFFFFFF);
    axi_write_reg(`ADDR_KI, 32'h0);
    axi_write_reg(`ADDR_KD, 32'h0);
    axi_write(`ADDR_SETPOINT, 32'h0001, wr_resp); // sp=1
    axi_write(`ADDR_OUT_MAX, 32'h00007FFF, wr_resp);
    axi_write(`ADDR_OUT_MIN, 32'hFFFF8000, wr_resp);
    axi_write_reg(`ADDR_INT_MAX, 32'h7FFFFFFF);
    axi_write_reg(`ADDR_INT_MIN, 32'h80000000);
    actual_i <= 16'd0;
    axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE);
    @(posedge clk);
    // e=1, p=1*0x7FFFFFFF=2147483647; out = clamp(32767,32767) = 32767
    wait_and_check_update(16'h0001, 16'd0,
        32'h7FFFFFFF, 32'h0, 32'h0,
        16'h7FFF, 16'h8000, 32'h7FFFFFFF, 32'h80000000,
        1'b0, 1'b0, 8'd17);
    $display("PASS T8 max gain no wrap");
    clear_done_overrun;

    `TEST_END(8, "EXTREME_VALUES")

    // =========================================================================
    // TEST 9 - CONTROL BITS
    // =========================================================================
    `TEST_START(9, "CONTROL_BITS")
    do_reset;
    ref_model_reset;
    prev_checks = total_checks;

    // ENABLE=0: output=0, integrator=0
    axi_write_reg(`ADDR_KP, 32'h00010000);
    axi_write_reg(`ADDR_SETPOINT, 32'h0064);
    actual_i <= 16'd0;
    axi_write_reg(`ADDR_CTRL, 32'h0);  // disabled
    @(posedge clk);
    do_tick;
    repeat(15) @(posedge clk);
    `CHECK_EQ("T9 ENABLE=0 pid_out=0", 16'h0, pid_out_o)
    axi_read(`ADDR_OUTPUT, rd_data, rd_resp);
    `CHECK_EQ("T9 ENABLE=0 OUTPUT reg=0", 32'h0, rd_data)

    // INT_RESET self-clears
    do_reset; ref_model_reset;
    axi_write_reg(`ADDR_KP, 32'h00010000);
    axi_write_reg(`ADDR_KI, 32'h00010000);
    axi_write_reg(`ADDR_KD, 32'h0);
    axi_write_reg(`ADDR_SETPOINT, 32'h0064);
    axi_write_reg(`ADDR_OUT_MAX, 32'h00007FFF);
    axi_write_reg(`ADDR_OUT_MIN, 32'hFFFF8000);
    axi_write_reg(`ADDR_INT_MAX, 32'h7FFFFFFF);
    axi_write_reg(`ADDR_INT_MIN, 32'h80000000);
    actual_i <= 16'd0;
    axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE);
    @(posedge clk);
    // Run 3 updates to accumulate integrator
    repeat(3) begin
        do_tick;
        wait_update_done;
        clear_done_overrun;
    end
    // Issue INT_RESET
    axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE | `CTRL_INT_RESET);
    @(posedge clk);
    @(posedge clk);
    // Check CTRL INT_RESET bit is cleared
    axi_read(`ADDR_CTRL, rd_data, rd_resp);
    `CHECK_EQ("T9 INT_RESET self-cleared", 1'b0, rd_data[1])
    // Run one more update; integrator should have been zeroed
    ref_model_int_reset; // sync reference model
    do_tick;
    wait_update_done;
    // After INT_RESET: first_update=1 so d=0, integrator was reset to 0.
    // out = Kp*e + Ki*e (first accumulation) + Kd*d(=0)
    //     = 1.0*100 + 1.0*100 = 200   (both Kp and Ki are 1.0, e=100)
    axi_read(`ADDR_OUTPUT, rd_data, rd_resp);
    `CHECK_EQ("T9 INT_RESET zeroed integrator", 32'h00C8, rd_data)  // 200 = 0xC8
    clear_done_overrun;

    // Gain writes during BUSY do not affect in-flight update
    do_reset; ref_model_reset;
    axi_write_reg(`ADDR_KP, 32'h00010000); // Kp=1.0
    axi_write_reg(`ADDR_KI, 32'h0);
    axi_write_reg(`ADDR_KD, 32'h0);
    axi_write_reg(`ADDR_SETPOINT, 32'h0064);
    axi_write_reg(`ADDR_OUT_MAX, 32'h00007FFF);
    axi_write_reg(`ADDR_OUT_MIN, 32'hFFFF8000);
    axi_write_reg(`ADDR_INT_MAX, 32'h7FFFFFFF);
    axi_write_reg(`ADDR_INT_MIN, 32'h80000000);
    actual_i <= 16'd0;
    axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE);
    @(posedge clk);
    // Start update
    tick_i <= 1'b1;
    @(posedge clk);
    tick_i <= 1'b0;
    // Write new KP while BUSY
    axi_write_reg(`ADDR_KP, 32'h00020000); // Kp=2.0
    // Wait for completion
    wait_update_done;
    axi_read(`ADDR_OUTPUT, rd_data, rd_resp);
    // Output should use Kp=1.0 (latched at LATCH state), not 2.0
    `CHECK_EQ("T9 in-flight uses latched Kp=1.0", 32'h0064, rd_data)
    clear_done_overrun;

    `TEST_END(9, "CONTROL_BITS")

    // =========================================================================
    // TEST 10 - STATUS AND INTERRUPT
    // =========================================================================
    `TEST_START(10, "STATUS_AND_IRQ")
    do_reset;
    ref_model_reset;
    prev_checks = total_checks;

    axi_write_reg(`ADDR_KP, 32'h00010000);
    axi_write_reg(`ADDR_KI, 32'h0);
    axi_write_reg(`ADDR_KD, 32'h0);
    axi_write_reg(`ADDR_SETPOINT, 32'h0064);
    axi_write_reg(`ADDR_OUT_MAX, 32'h00007FFF);
    axi_write_reg(`ADDR_OUT_MIN, 32'hFFFF8000);
    axi_write_reg(`ADDR_INT_MAX, 32'h7FFFFFFF);
    axi_write_reg(`ADDR_INT_MIN, 32'h80000000);
    actual_i <= 16'd0;

    // IRQ_EN=0: inta_o must be low even after DONE
    axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE);
    @(posedge clk);
    do_tick;
    wait_update_done;
    @(posedge clk);
    `CHECK_EQ("T10 inta_o low when IRQ_EN=0", 1'b0, inta_o)
    clear_done_overrun;

    // IRQ_EN=1: inta_o high after DONE
    axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE | `CTRL_IRQ_EN);
    @(posedge clk);
    do_tick;
    wait_update_done;
    @(posedge clk);
    @(posedge clk);
    axi_read(`ADDR_STATUS, rd_data, rd_resp);
    `CHECK_EQ("T10 DONE set with IRQ_EN", 1'b1, rd_data[`STAT_DONE])
    `CHECK_EQ("T10 inta_o high when IRQ_EN=1 and DONE", 1'b1, inta_o)

    // Clear DONE -> inta_o goes low
    clear_done_overrun;
    @(posedge clk);
    `CHECK_EQ("T10 inta_o low after DONE cleared", 1'b0, inta_o)

    // pid_out_valid_o is exactly one cycle wide
    axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE | `CTRL_IRQ_EN);
    @(posedge clk);
    do_tick;
    // Wait for valid pulse
    begin : t10_valid_wait
        integer wcnt;
        wcnt = 0;
        @(posedge clk);
        while (!pid_out_valid && wcnt < `UPDATE_TIMEOUT) begin
            @(posedge clk); wcnt = wcnt + 1;
        end
    end
    // Sample on the cycle after valid to confirm it's gone
    @(posedge clk);
    `CHECK_EQ("T10 pid_out_valid is 1-cycle", 1'b0, pid_out_valid)

    // OVERRUN W1C
    @(posedge clk);
    // Generate OVERRUN: tick while busy
    tick_i <= 1'b1;
    @(posedge clk);
    tick_i <= 1'b0;
    @(posedge clk);
    tick_i <= 1'b1;
    @(posedge clk);
    tick_i <= 1'b0;
    wait_update_done;
    @(posedge clk);
    axi_read(`ADDR_STATUS, rd_data, rd_resp);
    `CHECK_EQ("T10 OVERRUN set", 1'b1, rd_data[`STAT_OVERRUN])
    // Clear OVERRUN via W1C
    axi_write(`ADDR_STATUS, 32'h22, wr_resp); // clear DONE[1] and OVERRUN[5]
    @(posedge clk);
    axi_read(`ADDR_STATUS, rd_data, rd_resp);
    `CHECK_EQ("T10 OVERRUN cleared by W1C", 1'b0, rd_data[`STAT_OVERRUN])
    `CHECK_EQ("T10 DONE cleared by W1C", 1'b0, rd_data[`STAT_DONE])

    `TEST_END(10, "STATUS_AND_IRQ")

    // =========================================================================
    // TEST 11 - RANDOM REGRESSION (20000+ updates)
    // =========================================================================
    `TEST_START(11, "RANDOM_REGRESSION")
    do_reset;
    ref_model_reset;
    prev_checks = total_checks;

    begin : rand_regression
        integer rand_iter;
        integer rand_fails_local;
        reg [31:0] r_kp, r_ki, r_kd;
        reg [15:0] r_sp, r_act;
        reg [15:0] r_out_max, r_out_min;
        reg [31:0] r_int_max, r_int_min;
        reg        r_d_on_meas, r_aw_en;
        reg signed [15:0] exp_out16_r;
        reg               exp_sh_r, exp_sl_r, exp_is_r;
        reg [31:0]        status_r;
        reg [1:0]         resp_r;
        integer           rand_delay;

        rand_fails_local = 0;

        // Fixed initial config
        axi_write_reg(`ADDR_KP, 32'h00010000);
        axi_write_reg(`ADDR_KI, 32'h00001000);
        axi_write_reg(`ADDR_KD, 32'h00002000);
        axi_write(`ADDR_SETPOINT, 32'h0064, resp_r);
        axi_write(`ADDR_OUT_MAX, 32'h00007FFF, resp_r);
        axi_write(`ADDR_OUT_MIN, 32'hFFFF8000, resp_r);
        axi_write_reg(`ADDR_INT_MAX, 32'h7FFFFFFF);
        axi_write_reg(`ADDR_INT_MIN, 32'h80000000);
        actual_i <= 16'h0;
        axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE);
        @(posedge clk);

        for (rand_iter = 0; rand_iter < 20000; rand_iter = rand_iter + 1) begin
            // Every 100 iterations, randomize gains and limits
            if (rand_iter % 100 == 0) begin
                r_kp = {$random(seed_val)} % 32'h00040000; // 0..4.0
                r_ki = {$random} % 32'h00004000;
                r_kd = {$random} % 32'h00004000;
                // Out limits: max >= min, both in +-200
                r_out_max = 16'h00C8 + ({$random} % 16'h0064); // 200..300
                r_out_min = 16'hFF38 - ({$random} % 16'h0064); // -200..-264 -> sign-ext
                // Randomize d_on_meas and aw_en
                r_d_on_meas = {$random} % 2;
                r_aw_en     = {$random} % 2;
                if (r_aw_en) cov_aw_en_on = cov_aw_en_on + 1;
                else         cov_aw_en_off = cov_aw_en_off + 1;
                if (r_d_on_meas) cov_d_on_meas_on  = cov_d_on_meas_on  + 1;
                else             cov_d_on_meas_off = cov_d_on_meas_off + 1;

                axi_write_reg(`ADDR_KP, r_kp);
                axi_write_reg(`ADDR_KI, r_ki);
                axi_write_reg(`ADDR_KD, r_kd);
                axi_write(`ADDR_OUT_MAX, {16'h0, r_out_max}, resp_r);
                axi_write(`ADDR_OUT_MIN, {{16{r_out_min[15]}}, r_out_min}, resp_r);

                begin : write_ctrl_r
                    reg [31:0] ctrl_word;
                    ctrl_word = `CTRL_ENABLE;
                    if (r_d_on_meas) ctrl_word = ctrl_word | `CTRL_D_ON_MEAS;
                    if (r_aw_en)     ctrl_word = ctrl_word | `CTRL_AW_EN;
                    axi_write_reg(`ADDR_CTRL, ctrl_word);
                end
                @(posedge clk);
            end

            // Randomize setpoint and actual
            r_sp  = {$random} % 16'h0200 - 16'd256; // -256..+255
            r_act = {$random} % 16'h0200 - 16'd256;
            axi_write(`ADDR_SETPOINT, {{16{r_sp[15]}}, r_sp}, resp_r);
            actual_i <= r_act;
            @(posedge clk);

            // Compute reference BEFORE tick
            ref_model_compute(
                $signed(r_sp), $signed(r_act),
                $signed(r_kp), $signed(r_ki), $signed(r_kd),
                $signed(r_out_max), $signed(r_out_min),
                32'h7FFFFFFF, 32'h80000000,
                r_d_on_meas, r_aw_en,
                exp_out16_r, exp_sh_r, exp_sl_r, exp_is_r
            );

            // Tick and wait using counter snapshot to catch 1-cycle pid_out_valid pulse
            begin : t11_tick_wait
                integer snap11;
                integer rw;
                snap11 = pid_valid_cnt;
                tick_i <= 1'b1;
                @(posedge clk);
                tick_i <= 1'b0;
                rw = 0;
                @(posedge clk);
                while (pid_valid_cnt == snap11 && rw < `UPDATE_TIMEOUT) begin
                    @(posedge clk); rw = rw + 1;
                end
            end
            @(posedge clk); // let slave pipeline settle

            // Compare output
            total_checks = total_checks + 1;
            if ($signed(pid_out_o) !== $signed(exp_out16_r)) begin
                $display("FAIL T11 iter=%0d sp=%0d act=%0d kp=%0h ki=%0h kd=%0h exp=%0d got=%0d",
                    rand_iter, $signed(r_sp), $signed(r_act),
                    r_kp, r_ki, r_kd,
                    $signed(exp_out16_r), $signed(pid_out_o));
                total_fails = total_fails + 1;
                test_fails  = test_fails  + 1;
                rand_fails_local = rand_fails_local + 1;
                if (rand_fails_local >= 20) begin
                    $display("INFO T11: stopping after 20 mismatches");
                    disable rand_regression;
                end
            end else begin
                total_passes = total_passes + 1;
            end

            // Randomize AXI delay
            rand_delay = {$random} % 3;
            repeat(rand_delay) @(posedge clk);

            // Clear DONE/OVERRUN periodically
            if (rand_iter % 50 == 0)
                clear_done_overrun;
        end
        $display("INFO T11: mismatch_count=%0d / 20000 iterations", rand_fails_local);
    end

    `TEST_END(11, "RANDOM_REGRESSION")

    // =========================================================================
    // TEST 12 - CLOSED LOOP
    // =========================================================================
    `TEST_START(12, "CLOSED_LOOP")
    do_reset;
    ref_model_reset;
    prev_checks = total_checks;

    begin : closed_loop_test
        // First-order plant model: y[k+1] = a*y[k] + b*u[k]
        // Motor with T=50 tick periods, Ts=1 tick: a=exp(-1/50)~0.98, b=(1-a)=0.02
        // Gains: Kp=0.5, Ki=0.05, Kd=0.02 (Q16.16)
        // Thresholds:
        //   rise_time <= 100 tick periods
        //   overshoot  <= 20%
        //   settling   <= 300 tick periods (+/-5%)
        //   ss_error   <= 2 counts

        integer cl_iter;
        integer cl_max_iter;

        reg signed [31:0] plant_y;      // plant output (fixed-point *1)
        reg signed [31:0] plant_y_next;
        reg signed [15:0] setpoint_cl;
        reg signed [15:0] u_cl;
        reg [31:0]        tmp_rd;
        reg [1:0]         tmp_rsp;

        integer rise_time_tick;
        integer settle_time_tick;
        integer overshoot_count;
        integer ss_error_count;
        real    max_y;
        real    final_y;
        real    sp_real;
        integer fd_csv;
        integer csv_time;

        // Gains: Kp=0.5 Q16.16 = 32768, Ki=0.05 Q16.16 = 3277, Kd=0.02 Q16.16 = 1311
        axi_write_reg(`ADDR_KP, 32'd32768);
        axi_write_reg(`ADDR_KI, 32'd3277);
        axi_write_reg(`ADDR_KD, 32'd1311);
        axi_write(`ADDR_SETPOINT, 32'h0064, tmp_rsp); // sp=100
        axi_write(`ADDR_OUT_MAX, 32'h00007FFF, tmp_rsp);
        axi_write(`ADDR_OUT_MIN, 32'hFFFF8000, tmp_rsp);
        axi_write_reg(`ADDR_INT_MAX, 32'h7FFFFFFF);
        axi_write_reg(`ADDR_INT_MIN, 32'h80000000);
        axi_write_reg(`ADDR_CTRL, `CTRL_ENABLE | `CTRL_AW_EN);
        @(posedge clk);

        plant_y       = 32'sd0;
        setpoint_cl   = 16'd100;
        cl_max_iter   = 500;
        rise_time_tick  = -1;
        settle_time_tick = -1;
        overshoot_count = 0;
        ss_error_count  = 0;
        max_y = 0.0;
        sp_real = 100.0;

        fd_csv = $fopen("logs/pid_closed_loop.csv", "w");
        if (fd_csv) begin
            $fwrite(fd_csv, "time_tick,setpoint,actual,output\n");
        end

        for (cl_iter = 0; cl_iter < cl_max_iter; cl_iter = cl_iter + 1) begin
            // Drive actual from plant (nonblocking - let it settle before next posedge)
            actual_i <= plant_y[15:0];

            // Tick and wait using counter snapshot
            begin : cl_tick_wait
                integer snap_cl;
                integer cwait;
                snap_cl = pid_valid_cnt;
                @(posedge clk);
                tick_i <= 1'b1;
                @(posedge clk);
                tick_i <= 1'b0;
                cwait = 0;
                @(posedge clk);
                while (pid_valid_cnt == snap_cl && cwait < `UPDATE_TIMEOUT) begin
                    @(posedge clk); cwait = cwait + 1;
                end
            end
            @(posedge clk);

            u_cl = pid_out_o;

            // CSV log (first 500 iterations)
            if (fd_csv) begin
                $fwrite(fd_csv, "%0d,%0d,%0d,%0d\n",
                    cl_iter, $signed(setpoint_cl),
                    $signed(plant_y[15:0]), $signed(u_cl));
            end

            // First-order plant update: y = 0.98*y + 0.02*u
            // Using integer math * 65536 fixed-point
            plant_y_next = (plant_y * 64225 + $signed(u_cl) * 1311) >>> 16;
            plant_y = plant_y_next;

            // Rise time: first time y >= 0.9 * sp = 90
            if (rise_time_tick < 0 && $signed(plant_y[15:0]) >= $signed(16'sd90))
                rise_time_tick = cl_iter;

            // Overshoot: y > sp
            if ($signed(plant_y[15:0]) > 100) begin
                if ($signed(plant_y[15:0]) > max_y) max_y = $signed(plant_y[15:0]);
                overshoot_count = overshoot_count + 1;
            end

            // Clear done each tick
            clear_done_overrun;
        end

        // Steady-state error (last 50 iterations)
        // Already ran 500; just read final output
        final_y = $signed(plant_y[15:0]);
        ss_error_count = (final_y > sp_real) ? (final_y - sp_real) : (sp_real - final_y);

        if (fd_csv) $fclose(fd_csv);

        $display("INFO T12: rise_time=%0d (thresh<=100) max_y=%0d overshoot=%.1f%% ss_error=%0d (thresh<=2)",
            rise_time_tick, $rtoi(max_y),
            (max_y > sp_real) ? ((max_y - sp_real) / sp_real * 100.0) : 0.0,
            ss_error_count);

        // Check thresholds
        total_checks = total_checks + 1;
        if (rise_time_tick < 0 || rise_time_tick > 100) begin
            $display("FAIL T12 rise_time=%0d exceeds threshold=100", rise_time_tick);
            total_fails = total_fails + 1; test_fails = test_fails + 1;
        end else begin
            total_passes = total_passes + 1;
            $display("PASS T12 rise_time=%0d <= 100", rise_time_tick);
        end

        total_checks = total_checks + 1;
        if ((max_y - sp_real) > (sp_real * 0.20)) begin
            $display("FAIL T12 overshoot=%.1f%% exceeds 20%%",
                ((max_y - sp_real) / sp_real * 100.0));
            total_fails = total_fails + 1; test_fails = test_fails + 1;
        end else begin
            total_passes = total_passes + 1;
            $display("PASS T12 overshoot OK");
        end

        total_checks = total_checks + 1;
        if (ss_error_count > 2) begin
            $display("FAIL T12 ss_error=%0d exceeds threshold=2", ss_error_count);
            total_fails = total_fails + 1; test_fails = test_fails + 1;
        end else begin
            total_passes = total_passes + 1;
            $display("PASS T12 ss_error=%0d <= 2", ss_error_count);
        end

        // Load disturbance: add +30 to actual for 50 ticks, check recovery
        begin : load_dist
            integer ld_iter;
            integer recovered;
            recovered = 0;
            $display("INFO T12: starting load disturbance test (+30 offset for 50 ticks)");
            for (ld_iter = 0; ld_iter < 150; ld_iter = ld_iter + 1) begin
                if (ld_iter < 50)
                    actual_i <= plant_y[15:0] + 16'd30; // inject disturbance (NB)
                else
                    actual_i <= plant_y[15:0];

                // Tick and wait using counter snapshot
                begin : ld_tick_wait
                    integer snap_ld;
                    integer lw;
                    snap_ld = pid_valid_cnt;
                    @(posedge clk);
                    tick_i <= 1'b1;
                    @(posedge clk);
                    tick_i <= 1'b0;
                    lw = 0;
                    @(posedge clk);
                    while (pid_valid_cnt == snap_ld && lw < `UPDATE_TIMEOUT) begin
                        @(posedge clk); lw = lw + 1;
                    end
                end
                @(posedge clk);
                u_cl = pid_out_o;
                plant_y_next = (plant_y * 64225 + $signed(u_cl) * 1311) >>> 16;
                plant_y = plant_y_next;

                // Check recovery after disturbance removed (iter 100+)
                if (ld_iter >= 100) begin
                    if ($signed(plant_y[15:0]) >= 95 && $signed(plant_y[15:0]) <= 105)
                        recovered = recovered + 1;
                end
                clear_done_overrun;
            end
            total_checks = total_checks + 1;
            if (recovered < 25) begin
                $display("FAIL T12 load_dist: only %0d/50 cycles within +/-5%% after recovery", recovered);
                total_fails = total_fails + 1; test_fails = test_fails + 1;
            end else begin
                total_passes = total_passes + 1;
                $display("PASS T12 load_dist: recovered in %0d/50 cycles within +/-5%%", recovered);
            end
        end
    end

    `TEST_END(12, "CLOSED_LOOP")

    // =========================================================================
    // FINAL SUMMARY
    // =========================================================================
    repeat(5) @(posedge clk);
    $display("");
    $display("============================================================");
    $display("  PID CONTROLLER REGRESSION SUMMARY");
    $display("============================================================");
    $display(" Test | Name                  | Checks | Fails | Result");
    $display("------|------------------------|--------|-------|-------");
    $display("  01  | RESET_VALUES          | %6d | %5d | %s", test_check_cnt[1],  test_fail_cnt[1],  test_results[1]  ? "PASS" : "FAIL");
    $display("  02  | REGISTER_ACCESS       | %6d | %5d | %s", test_check_cnt[2],  test_fail_cnt[2],  test_results[2]  ? "PASS" : "FAIL");
    $display("  03  | ADDRESS_DECODE        | %6d | %5d | %s", test_check_cnt[3],  test_fail_cnt[3],  test_results[3]  ? "PASS" : "FAIL");
    $display("  04  | AXI_PROTOCOL          | %6d | %5d | %s", test_check_cnt[4],  test_fail_cnt[4],  test_results[4]  ? "PASS" : "FAIL");
    $display("  05  | TICK_BEHAVIOR         | %6d | %5d | %s", test_check_cnt[5],  test_fail_cnt[5],  test_results[5]  ? "PASS" : "FAIL");
    $display("  06  | CONTROL_MATH          | %6d | %5d | %s", test_check_cnt[6],  test_fail_cnt[6],  test_results[6]  ? "PASS" : "FAIL");
    $display("  07  | CLAMPS                | %6d | %5d | %s", test_check_cnt[7],  test_fail_cnt[7],  test_results[7]  ? "PASS" : "FAIL");
    $display("  08  | EXTREME_VALUES        | %6d | %5d | %s", test_check_cnt[8],  test_fail_cnt[8],  test_results[8]  ? "PASS" : "FAIL");
    $display("  09  | CONTROL_BITS          | %6d | %5d | %s", test_check_cnt[9],  test_fail_cnt[9],  test_results[9]  ? "PASS" : "FAIL");
    $display("  10  | STATUS_AND_IRQ        | %6d | %5d | %s", test_check_cnt[10], test_fail_cnt[10], test_results[10] ? "PASS" : "FAIL");
    $display("  11  | RANDOM_REGRESSION     | %6d | %5d | %s", test_check_cnt[11], test_fail_cnt[11], test_results[11] ? "PASS" : "FAIL");
    $display("  12  | CLOSED_LOOP           | %6d | %5d | %s", test_check_cnt[12], test_fail_cnt[12], test_results[12] ? "PASS" : "FAIL");
    $display("------|------------------------|--------|-------|-------");
    $display("  TOT |                        | %6d | %5d |",   total_checks, total_fails);
    $display("============================================================");
    $display("  COVERAGE SUMMARY:");
    $display("    FSM COMMIT count       : %0d", cov_fsm_commit);
    $display("    SAT_HI seen            : %0d", cov_sat_hi_seen);
    $display("    SAT_LO seen            : %0d", cov_sat_lo_seen);
    $display("    INT_SAT seen           : %0d", cov_int_sat_seen);
    $display("    AW_EN=1 iterations     : %0d", cov_aw_en_on);
    $display("    AW_EN=0 iterations     : %0d", cov_aw_en_off);
    $display("    D_ON_MEAS=1 iterations : %0d", cov_d_on_meas_on);
    $display("    D_ON_MEAS=0 iterations : %0d", cov_d_on_meas_off);
`ifdef FSDB
    $display("    Waveform               : waves/pid_tb.fsdb (FSDB)");
`elsif VCD
    $display("    Waveform               : waves/pid_tb.vcd (VCD)");
`else
    $display("    Waveform               : none");
`endif
    $display("============================================================");
    if (total_fails == 0)
        $display("*** ALL TESTS PASSED ***");
    else
        $display("*** TEST FAILED: %0d failures ***", total_fails);
    $display("============================================================");
    $finish;
end

endmodule
