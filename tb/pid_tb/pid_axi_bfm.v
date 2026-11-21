// =============================================================================
// File : pid_axi_bfm.v
// Desc : AXI4 Master BFM tasks.  Included (via `include) inside pid_tb module.
//        Drives the AXI4 master interface towards pid_top.
//        Supports: single write/read, AW-first, W-first, simultaneous,
//        configurable WSTRB, AWLEN/ARLEN (burst), WLAST control,
//        bready/rready backpressure, IDs, BID/RID echo-check.
//
//  RACE-FIX (v2): All DUT input drives use nonblocking assignments (<=).
//                 Signals are driven AFTER @(posedge clk) so the RTL sees
//                 the new value on the NEXT rising edge - no same-cycle race.
//                 DUT outputs are sampled just before the next drive edge
//                 (i.e., after @(posedge clk) and before any <= drive).
// =============================================================================

// ---------------------------------------------------------------------------
// Sticky valid flag – set by the always-block monitor in pid_tb.v,
// cleared here before starting a transaction that needs it.
// ---------------------------------------------------------------------------
// (Declaration is in pid_tb.v)

// ---------------------------------------------------------------------------
// Low-level: wait for rising edge of clock
// ---------------------------------------------------------------------------
task axi_clk;
    begin @(posedge clk); end
endtask

// ---------------------------------------------------------------------------
// axi_write_full
//   addr     : byte address
//   data     : write data
//   strb     : WSTRB (4 bits)
//   awlen    : AWLEN (0 = single beat)
//   wlast    : WLAST value to drive on the W beat
//   aw_first : 1=AW before W, 0=W before AW, 2=simultaneous
//   id       : AWID
//   delay_b  : extra cycles to hold BREADY low after BVALID seen
//   resp_out : output response code
//   bid_out  : captured BID
// ---------------------------------------------------------------------------
task axi_write_full;
    input  [31:0]  addr;
    input  [31:0]  data;
    input  [3:0]   strb;
    input  [7:0]   awlen;
    input          wlast;
    input  [1:0]   aw_first;   // 0=W first, 1=AW first, 2=simultaneous
    input  [7:0]   id;
    input  [3:0]   delay_b;
    output [1:0]   resp_out;
    output [7:0]   bid_out;

    integer tout;
    begin
        // ------------------------------------------------------------------
        // Pre-load channel fields (driven after posedge so safe)
        // ------------------------------------------------------------------
        @(posedge clk);
        m_axi_awid    <= id;
        m_axi_awaddr  <= addr;
        m_axi_awlen   <= awlen;
        m_axi_awsize  <= 3'b010;   // 4 bytes
        m_axi_awburst <= 2'b01;    // INCR
        m_axi_awlock  <= 1'b0;
        m_axi_awcache <= 4'b0000;
        m_axi_awprot  <= 3'b000;
        m_axi_wdata   <= data;
        m_axi_wstrb   <= strb;
        m_axi_wlast   <= wlast;

        // ------------------------------------------------------------------
        // Present channels according to aw_first ordering
        // ------------------------------------------------------------------
        if (aw_first == 2'd2) begin
            // Simultaneous: both valids on next posedge
            m_axi_awvalid <= 1'b1;
            m_axi_wvalid  <= 1'b1;
            @(posedge clk);
            tout = 0;
            // Wait for both readies to be asserted on the same or later cycle
            while (!(m_axi_awready && m_axi_wready) && tout < `AXI_TIMEOUT) begin
                // If one ready came but not the other, deassert its valid
                if (m_axi_awready && !m_axi_wready)
                    m_axi_awvalid <= 1'b0;
                if (m_axi_wready && !m_axi_awready)
                    m_axi_wvalid <= 1'b0;
                @(posedge clk);
                tout = tout + 1;
            end
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid  <= 1'b0;
        end else if (aw_first == 2'd1) begin
            // AW first
            m_axi_awvalid <= 1'b1;
            m_axi_wvalid  <= 1'b0;
            @(posedge clk);
            tout = 0;
            while (!m_axi_awready && tout < `AXI_TIMEOUT) begin
                @(posedge clk); tout = tout + 1;
            end
            m_axi_awvalid <= 1'b0;
            // Now drive W
            @(posedge clk);
            m_axi_wvalid <= 1'b1;
            @(posedge clk);
            tout = 0;
            while (!m_axi_wready && tout < `AXI_TIMEOUT) begin
                @(posedge clk); tout = tout + 1;
            end
            m_axi_wvalid <= 1'b0;
        end else begin
            // W first
            m_axi_wvalid  <= 1'b1;
            m_axi_awvalid <= 1'b0;
            @(posedge clk);
            tout = 0;
            while (!m_axi_wready && tout < `AXI_TIMEOUT) begin
                @(posedge clk); tout = tout + 1;
            end
            m_axi_wvalid <= 1'b0;
            // Now drive AW
            @(posedge clk);
            m_axi_awvalid <= 1'b1;
            @(posedge clk);
            tout = 0;
            while (!m_axi_awready && tout < `AXI_TIMEOUT) begin
                @(posedge clk); tout = tout + 1;
            end
            m_axi_awvalid <= 1'b0;
        end

        // ------------------------------------------------------------------
        // Wait for BVALID, optionally apply backpressure, then accept
        // ------------------------------------------------------------------
        @(posedge clk);
        tout = 0;
        while (!m_axi_bvalid && tout < `AXI_TIMEOUT) begin
            @(posedge clk); tout = tout + 1;
        end
        // Apply backpressure delay (hold BREADY low)
        repeat (delay_b) @(posedge clk);
        // Sample outputs BEFORE asserting BREADY (same posedge, before <=)
        resp_out = m_axi_bresp;
        bid_out  = m_axi_bid;
        m_axi_bready <= 1'b1;
        @(posedge clk);
        m_axi_bready <= 1'b0;
        @(posedge clk);
    end
endtask

// ---------------------------------------------------------------------------
// axi_write - simplified single-beat simultaneous write
// ---------------------------------------------------------------------------
task axi_write;
    input  [31:0]  addr;
    input  [31:0]  data;
    output [1:0]   resp_out;
    reg    [7:0]   bid_tmp;
    begin
        axi_write_full(addr, data, 4'hF, 8'h00, 1'b1, 2'd2, 8'h01, 4'd0,
                       resp_out, bid_tmp);
    end
endtask

// ---------------------------------------------------------------------------
// axi_write_strb - single beat with specific WSTRB
// ---------------------------------------------------------------------------
task axi_write_strb;
    input  [31:0]  addr;
    input  [31:0]  data;
    input  [3:0]   strb;
    output [1:0]   resp_out;
    reg    [7:0]   bid_tmp;
    begin
        axi_write_full(addr, data, strb, 8'h00, 1'b1, 2'd2, 8'h02, 4'd0,
                       resp_out, bid_tmp);
    end
endtask

// ---------------------------------------------------------------------------
// axi_read_full
//   addr     : byte address
//   arlen    : ARLEN (0 = single beat)
//   id       : ARID
//   delay_r  : cycles to hold RREADY low after RVALID seen (first beat)
//   data_out : first beat data
//   resp_out : first beat response
//   rid_out  : returned RID
// ---------------------------------------------------------------------------
task axi_read_full;
    input  [31:0]  addr;
    input  [7:0]   arlen;
    input  [7:0]   id;
    input  [3:0]   delay_r;
    output [31:0]  data_out;
    output [1:0]   resp_out;
    output [7:0]   rid_out;

    integer tout;
    integer beats_left;
    begin
        @(posedge clk);
        m_axi_arid    <= id;
        m_axi_araddr  <= addr;
        m_axi_arlen   <= arlen;
        m_axi_arsize  <= 3'b010;
        m_axi_arburst <= 2'b01;
        m_axi_arlock  <= 1'b0;
        m_axi_arcache <= 4'b0000;
        m_axi_arprot  <= 3'b000;
        m_axi_arvalid <= 1'b1;
        @(posedge clk);
        tout = 0;
        while (!m_axi_arready && tout < `AXI_TIMEOUT) begin
            @(posedge clk); tout = tout + 1;
        end
        m_axi_arvalid <= 1'b0;

        // Receive beats
        beats_left = arlen + 1;
        data_out = 32'hDEAD_BEEF;
        resp_out = 2'b11;
        rid_out  = 8'hFF;

        while (beats_left > 0) begin
            // Wait for RVALID
            @(posedge clk);
            tout = 0;
            while (!m_axi_rvalid && tout < `AXI_TIMEOUT) begin
                @(posedge clk); tout = tout + 1;
            end
            // Apply backpressure on first beat only
            if (beats_left == (arlen + 1))
                repeat (delay_r) @(posedge clk);
            // Sample outputs at this posedge (before any <=)
            if (beats_left == (arlen + 1)) begin
                data_out = m_axi_rdata;
                resp_out = m_axi_rresp;
                rid_out  = m_axi_rid;
            end
            // Accept the beat
            m_axi_rready <= 1'b1;
            @(posedge clk);
            m_axi_rready <= 1'b0;
            beats_left = beats_left - 1;
        end
        @(posedge clk);
    end
endtask

// ---------------------------------------------------------------------------
// axi_read - simplified single-beat read
// ---------------------------------------------------------------------------
task axi_read;
    input  [31:0]  addr;
    output [31:0]  data_out;
    output [1:0]   resp_out;
    reg    [7:0]   rid_tmp;
    begin
        axi_read_full(addr, 8'h00, 8'h01, 4'd0, data_out, resp_out, rid_tmp);
    end
endtask

// ---------------------------------------------------------------------------
// axi_write_reg - write and expect OKAY; no response capture
// ---------------------------------------------------------------------------
task axi_write_reg;
    input [31:0] addr;
    input [31:0] data;
    reg   [1:0]  rsp;
    begin
        axi_write(addr, data, rsp);
    end
endtask

// ---------------------------------------------------------------------------
// axi_read_reg - read and return data only
// ---------------------------------------------------------------------------
task axi_read_reg;
    input  [31:0] addr;
    output [31:0] data_out;
    reg    [1:0]  rsp;
    begin
        axi_read(addr, data_out, rsp);
    end
endtask

// ---------------------------------------------------------------------------
// do_reset - assert/deassert the AXI reset
// All DUT inputs initialised with nonblocking at time-0 is done in the
// main initial block; here we drive with <= after @(posedge clk).
// ---------------------------------------------------------------------------
task do_reset;
    begin
        // Drive reset and all inputs at time-0 / before first edge
        aresetn       <= 1'b0;
        tick_i        <= 1'b0;
        m_axi_awid    <= 8'h00;
        m_axi_awaddr  <= 32'h0;
        m_axi_awlen   <= 8'h00;
        m_axi_awsize  <= 3'b010;
        m_axi_awburst <= 2'b01;
        m_axi_awlock  <= 1'b0;
        m_axi_awcache <= 4'b0;
        m_axi_awprot  <= 3'b0;
        m_axi_awvalid <= 1'b0;
        m_axi_wdata   <= 32'h0;
        m_axi_wstrb   <= 4'hF;
        m_axi_wlast   <= 1'b1;
        m_axi_wvalid  <= 1'b0;
        m_axi_bready  <= 1'b0;
        m_axi_arid    <= 8'h00;
        m_axi_araddr  <= 32'h0;
        m_axi_arlen   <= 8'h00;
        m_axi_arsize  <= 3'b010;
        m_axi_arburst <= 2'b01;
        m_axi_arlock  <= 1'b0;
        m_axi_arcache <= 4'b0;
        m_axi_arprot  <= 3'b0;
        m_axi_arvalid <= 1'b0;
        m_axi_rready  <= 1'b0;
        actual_i      <= 16'h0;
        repeat (`RESET_CYCLES) @(posedge clk);
        aresetn <= 1'b1;
        // Extra delay for 2-flop synchronizer to propagate rst_n_sync
        repeat (4) @(posedge clk);
    end
endtask

// ---------------------------------------------------------------------------
// enable_pid - enable PID with basic settings
// ---------------------------------------------------------------------------
task enable_pid;
    reg [1:0] rsp;
    begin
        axi_write(`ADDR_CTRL, `CTRL_ENABLE, rsp);
        @(posedge clk);
    end
endtask

// ---------------------------------------------------------------------------
// disable_pid
// ---------------------------------------------------------------------------
task disable_pid;
    reg [1:0] rsp;
    begin
        axi_write(`ADDR_CTRL, 32'h0, rsp);
        @(posedge clk);
    end
endtask

// ---------------------------------------------------------------------------
// do_tick - generate a one-cycle tick pulse.
// Drives tick_i HIGH with nonblocking after a posedge, then LOW after the
// next posedge.  The RTL samples tick_i at each rising edge; tick_prev is
// updated there too.  Rising edge detected = tick_i & ~tick_prev.
//
// Timeline:
//   posedge N  : <= 1'b1  (RTL sees tick_i=0 this cycle; prev=0; rise=0)
//   posedge N+1: RTL sees tick_i=1, tick_prev=0 -> tick_rise=1 -> FSM starts
//                BFM drives <= 1'b0
//   posedge N+2: RTL sees tick_i=0, tick_prev=1 -> tick_rise=0
// ---------------------------------------------------------------------------
task do_tick;
    begin
        @(posedge clk);
        tick_i <= 1'b1;
        @(posedge clk);
        tick_i <= 1'b0;
    end
endtask

// ---------------------------------------------------------------------------
// wait_update_done - wait for the next pid_out_valid_o pulse after a tick.
// Uses the free-running pid_valid_cnt counter (declared in pid_tb.v).
// Snapshots the counter at call time; waits until the counter advances.
// This is immune to the pulse arriving before the task starts polling.
// ---------------------------------------------------------------------------
task wait_update_done;
    integer tout;
    integer snap;
    begin
        snap = pid_valid_cnt;   // capture count before waiting
        tout = 0;
        @(posedge clk);
        while (pid_valid_cnt == snap && tout < `UPDATE_TIMEOUT) begin
            @(posedge clk);
            tout = tout + 1;
        end
        // One extra cycle for slave pipeline to update OUTPUT/ERROR/ACTUAL
        @(posedge clk);
    end
endtask

// ---------------------------------------------------------------------------
// clear_done_overrun - W1C clear DONE and OVERRUN
// ---------------------------------------------------------------------------
task clear_done_overrun;
    reg [1:0] rsp;
    begin
        // Write 1 to DONE[1] and OVERRUN[5]
        axi_write(`ADDR_STATUS, 32'h22, rsp);
        @(posedge clk);
    end
endtask

// ---------------------------------------------------------------------------
// write_burst - send a multi-beat AXI4 write burst (AWLEN+1 beats)
//   Returns response code (expected SLVERR per spec)
// ---------------------------------------------------------------------------
task write_burst;
    input [31:0] addr;
    input [7:0]  awlen;        // ARLEN: total beats = awlen+1
    input [31:0] first_data;
    output [1:0] resp_out;

    integer tout, beat;
    begin
        @(posedge clk);
        // Send AW
        m_axi_awid    <= 8'hBB;
        m_axi_awaddr  <= addr;
        m_axi_awlen   <= awlen;
        m_axi_awsize  <= 3'b010;
        m_axi_awburst <= 2'b01;
        m_axi_awvalid <= 1'b1;
        @(posedge clk);
        tout = 0;
        while (!m_axi_awready && tout < `AXI_TIMEOUT) begin
            @(posedge clk); tout = tout + 1;
        end
        m_axi_awvalid <= 1'b0;

        // Send W beats
        for (beat = 0; beat <= awlen; beat = beat + 1) begin
            @(posedge clk);
            m_axi_wdata  <= first_data + beat;
            m_axi_wstrb  <= 4'hF;
            m_axi_wlast  <= (beat == awlen) ? 1'b1 : 1'b0;
            m_axi_wvalid <= 1'b1;
            @(posedge clk);
            tout = 0;
            while (!m_axi_wready && tout < `AXI_TIMEOUT) begin
                @(posedge clk); tout = tout + 1;
            end
            m_axi_wvalid <= 1'b0;
        end

        // Get B response
        @(posedge clk);
        tout = 0;
        while (!m_axi_bvalid && tout < `AXI_TIMEOUT) begin
            @(posedge clk); tout = tout + 1;
        end
        resp_out = m_axi_bresp;
        m_axi_bready <= 1'b1;
        @(posedge clk);
        m_axi_bready <= 1'b0;
        @(posedge clk);
    end
endtask

// ---------------------------------------------------------------------------
// read_burst - send a multi-beat AXI4 read burst
//   Checks that RLAST is asserted on the last accepted beat and NOT on
//   earlier beats.  Samples RLAST at the cycle when rvalid && rready.
// ---------------------------------------------------------------------------
task read_burst;
    input  [31:0] addr;
    input  [7:0]  arlen;
    output [1:0]  resp_first;
    output        rlast_ok;   // 1 if RLAST seen only on last beat

    integer tout, beat;
    reg     last_seen_early;
    reg     last_seen_on_last;
    begin
        last_seen_early   = 1'b0;
        last_seen_on_last = 1'b0;
        resp_first = 2'b11;
        rlast_ok   = 1'b0;

        @(posedge clk);
        m_axi_arid    <= 8'hCC;
        m_axi_araddr  <= addr;
        m_axi_arlen   <= arlen;
        m_axi_arsize  <= 3'b010;
        m_axi_arburst <= 2'b01;
        m_axi_arvalid <= 1'b1;
        @(posedge clk);
        tout = 0;
        while (!m_axi_arready && tout < `AXI_TIMEOUT) begin
            @(posedge clk); tout = tout + 1;
        end
        m_axi_arvalid <= 1'b0;

        for (beat = 0; beat <= arlen; beat = beat + 1) begin
            // Wait for RVALID
            @(posedge clk);
            tout = 0;
            while (!m_axi_rvalid && tout < `AXI_TIMEOUT) begin
                @(posedge clk); tout = tout + 1;
            end
            // At this posedge: rvalid is high; sample outputs before accepting
            if (beat == 0)
                resp_first = m_axi_rresp;
            // Check RLAST on the accepted beat (rvalid is asserted here)
            if (beat < arlen && m_axi_rlast)
                last_seen_early = 1'b1;
            if (beat == arlen && m_axi_rlast)
                last_seen_on_last = 1'b1;
            // Accept the beat
            m_axi_rready <= 1'b1;
            @(posedge clk);
            m_axi_rready <= 1'b0;
        end

        rlast_ok = last_seen_on_last && !last_seen_early;
        @(posedge clk);
    end
endtask
