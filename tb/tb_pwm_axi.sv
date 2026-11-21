`timescale 1ns/1ps

module tb_pwm_axi;

    // ============================================================
    // Parameters
    // ============================================================
    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 4;

    // ============================================================
    // Clock and Reset
    // ============================================================
    reg clk;
    reg resetn;

    // ============================================================
    // AXI4-Lite Write Address Channel
    // ============================================================
    reg  [ADDR_WIDTH-1:0] awaddr;
    reg  [2:0]            awprot;
    reg                   awvalid;
    wire                  awready;

    // ============================================================
    // AXI4-Lite Write Data Channel
    // ============================================================
    reg  [DATA_WIDTH-1:0] wdata;
    reg  [DATA_WIDTH/8-1:0] wstrb;
    reg                   wvalid;
    wire                  wready;

    // ============================================================
    // AXI4-Lite Write Response Channel
    // ============================================================
    wire [1:0] bresp;
    wire       bvalid;
    reg        bready;

    // ============================================================
    // AXI4-Lite Read Address Channel
    // ============================================================
    reg  [ADDR_WIDTH-1:0] araddr;
    reg  [2:0]            arprot;
    reg                   arvalid;
    wire                  arready;

    // ============================================================
    // AXI4-Lite Read Data Channel
    // ============================================================
    wire [DATA_WIDTH-1:0] rdata;
    wire [1:0]            rresp;
    wire                  rvalid;
    reg                   rready;

    // ============================================================
    // PWM Output
    // ============================================================
    wire PWM_OUT;

    // ============================================================
    // DUT
    // ============================================================
    myip_v1_0 #(
        .C_S00_AXI_DATA_WIDTH(DATA_WIDTH),
        .C_S00_AXI_ADDR_WIDTH(ADDR_WIDTH)
    ) DUT (
        .PWM_OUT(PWM_OUT),
        .hw_duty_i(8'h00),
        .hw_duty_valid_i(1'b0),

        .s00_axi_aclk(clk),
        .s00_axi_aresetn(resetn),

        .s00_axi_awaddr(awaddr),
        .s00_axi_awprot(awprot),
        .s00_axi_awvalid(awvalid),
        .s00_axi_awready(awready),

        .s00_axi_wdata(wdata),
        .s00_axi_wstrb(wstrb),
        .s00_axi_wvalid(wvalid),
        .s00_axi_wready(wready),

        .s00_axi_bresp(bresp),
        .s00_axi_bvalid(bvalid),
        .s00_axi_bready(bready),

        .s00_axi_araddr(araddr),
        .s00_axi_arprot(arprot),
        .s00_axi_arvalid(arvalid),
        .s00_axi_arready(arready),

        .s00_axi_rdata(rdata),
        .s00_axi_rresp(rresp),
        .s00_axi_rvalid(rvalid),
        .s00_axi_rready(rready)
    );

    // ============================================================
    // Clock Generation
    // 10 ns clock period = 100 MHz
    // ============================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ============================================================
    // Test Statistics
    // ============================================================
    integer total_tests;
    integer passed_tests;
    integer failed_tests;

    // ============================================================
    // AXI4-Lite WRITE TASK
    // ============================================================
    task axi_write(
        input [ADDR_WIDTH-1:0] addr,
        input [DATA_WIDTH-1:0] data
    );
    begin

        @(posedge clk);

        awaddr  <= addr;
        awprot  <= 3'b000;
        awvalid <= 1'b1;

        wdata   <= data;
        wstrb   <= 4'b1111;
        wvalid  <= 1'b1;

        bready  <= 1'b1;

        // Wait until address and data are accepted
        wait (awready && wready);

        @(posedge clk);

        awvalid <= 1'b0;
        wvalid  <= 1'b0;

        // Wait for write response
        wait (bvalid);

        if (bresp == 2'b00)
            $display("[%0t ns] AXI WRITE PASS : ADDR = 0x%02h DATA = 0x%08h",
                     $time, addr, data);
        else
            $display("[%0t ns] AXI WRITE FAIL : BRESP = %b",
                     $time, bresp);

        @(posedge clk);

        bready <= 1'b0;

    end
    endtask

    // ============================================================
    // AXI4-Lite READ TASK
    // ============================================================
    task axi_read(
        input  [ADDR_WIDTH-1:0] addr,
        output [DATA_WIDTH-1:0] data
    );
    begin

        @(posedge clk);

        araddr  <= addr;
        arprot  <= 3'b000;
        arvalid <= 1'b1;

        rready  <= 1'b1;

        // Wait for address acceptance
        wait (arready);

        @(posedge clk);

        arvalid <= 1'b0;

        // Wait for read response
        wait (rvalid);

        data = rdata;

        if (rresp == 2'b00)
            $display("[%0t ns] AXI READ  PASS : ADDR = 0x%02h DATA = 0x%08h",
                     $time, addr, data);
        else
            $display("[%0t ns] AXI READ  FAIL : RRESP = %b",
                     $time, rresp);

        @(posedge clk);

        rready <= 1'b0;

    end
    endtask

    // ============================================================
    // PWM DUTY-CYCLE MEASUREMENT
    //
    // Since PWM counter is 8-bit:
    //
    // duty = 0   -> 0%
    // duty = 64  -> ~25%
    // duty = 128 -> ~50%
    // duty = 192 -> ~75%
    // duty = 255 -> ~99.6%
    //
    // ============================================================
    task measure_pwm;

        input [7:0] duty;
        integer high_count;
        integer low_count;
        integer total_count;
        integer expected_high;
        integer tolerance;
        integer i;

        begin

            total_tests = total_tests + 1;

            axi_write(4'h0, {24'h0, duty});

            // Allow the new duty value to take effect
            repeat(2) @(posedge clk);

            high_count = 0;
            low_count  = 0;

            // Measure exactly 256 PWM clock cycles
            for (i = 0; i < 256; i = i + 1) begin

                @(posedge clk);

                if (PWM_OUT)
                    high_count = high_count + 1;
                else
                    low_count = low_count + 1;

            end

            total_count = high_count + low_count;

            expected_high = duty;

            // Small tolerance for sampling boundary
            tolerance = 2;

            $display("");
            $display("--------------------------------------------------");
            $display("PWM DUTY TEST");
            $display("Requested Duty Value : %0d", duty);
            $display("Measured HIGH Cycles : %0d", high_count);
            $display("Measured LOW Cycles  : %0d", low_count);
            $display("Total Cycles         : %0d", total_count);
            $display("Expected HIGH Cycles : %0d", expected_high);

            if ((high_count >= expected_high - tolerance) &&
                (high_count <= expected_high + tolerance)) begin

                $display("RESULT               : PASS");
                passed_tests = passed_tests + 1;

            end
            else begin

                $display("RESULT               : FAIL");
                failed_tests = failed_tests + 1;

            end

            $display("--------------------------------------------------");
            $display("");

        end

    endtask


    // ============================================================
    // MAIN TEST
    // ============================================================
    reg [31:0] read_data;

    initial begin

        // Initialize signals
        resetn  = 1'b0;

        awaddr  = 0;
        awprot  = 0;
        awvalid = 0;

        wdata   = 0;
        wstrb   = 0;
        wvalid  = 0;

        bready  = 0;

        araddr  = 0;
        arprot  = 0;
        arvalid = 0;

        rready  = 0;

        total_tests  = 0;
        passed_tests = 0;
        failed_tests = 0;

        // --------------------------------------------------------
        // RESET
        // --------------------------------------------------------
        $display("");
        $display("==================================================");
        $display("       AXI4-LITE PWM GENERATOR TEST");
        $display("==================================================");
        $display("");

        $display("[%0t ns] Applying reset...", $time);

        repeat(5) @(posedge clk);

        resetn = 1'b1;

        repeat(2) @(posedge clk);

        $display("[%0t ns] Reset released.", $time);
        $display("");

        // --------------------------------------------------------
        // TEST 1 : REGISTER WRITE / READ
        // --------------------------------------------------------
        $display("==================================================");
        $display("TEST 1 : REGISTER WRITE / READ");
        $display("==================================================");

        axi_write(4'h0, 32'h00000080);

        axi_read(4'h0, read_data);

        total_tests = total_tests + 1;

        if (read_data == 32'h00000080) begin
            $display("REGISTER READBACK : PASS");
            passed_tests = passed_tests + 1;
        end
        else begin
            $display("REGISTER READBACK : FAIL");
            $display("Expected          : 0x00000080");
            $display("Actual            : 0x%08h", read_data);
            failed_tests = failed_tests + 1;
        end

        // --------------------------------------------------------
        // TEST 2 : 0% DUTY
        // --------------------------------------------------------
        $display("");
        $display("==================================================");
        $display("TEST 2 : 0%% DUTY CYCLE");
        $display("==================================================");

        measure_pwm(8'd0);

        // --------------------------------------------------------
        // TEST 3 : 25% DUTY
        // --------------------------------------------------------
        $display("");
        $display("==================================================");
        $display("TEST 3 : 25%% DUTY CYCLE");
        $display("==================================================");

        measure_pwm(8'd64);

        // --------------------------------------------------------
        // TEST 4 : 50% DUTY
        // --------------------------------------------------------
        $display("");
        $display("==================================================");
        $display("TEST 4 : 50%% DUTY CYCLE");
        $display("==================================================");

        measure_pwm(8'd128);

        // --------------------------------------------------------
        // TEST 5 : 75% DUTY
        // --------------------------------------------------------
        $display("");
        $display("==================================================");
        $display("TEST 5 : 75%% DUTY CYCLE");
        $display("==================================================");

        measure_pwm(8'd192);

        // --------------------------------------------------------
        // TEST 6 : MAX DUTY
        // --------------------------------------------------------
        $display("");
        $display("==================================================");
        $display("TEST 6 : MAXIMUM DUTY");
        $display("==================================================");

        measure_pwm(8'd255);

        // --------------------------------------------------------
        // FINAL SUMMARY
        // --------------------------------------------------------
        $display("");
        $display("");
        $display("==================================================");
        $display("       PWM VERIFICATION SUMMARY");
        $display("==================================================");
        $display("TOTAL TESTS  : %0d", total_tests);
        $display("PASSED       : %0d", passed_tests);
        $display("FAILED       : %0d", failed_tests);
        $display("==================================================");

        if (failed_tests == 0)
            $display("FINAL RESULT : *** ALL TESTS PASSED ***");
        else
            $display("FINAL RESULT : *** VERIFICATION FAILED ***");

        $display("==================================================");
        $display("");

        #100;

        $finish;

    end

    // ============================================================
    // FSDB WAVEFORM DUMP
    // ============================================================
`ifdef FSDB
    initial begin
        $fsdbDumpfile("pwm_axi.fsdb");
        $fsdbDumpvars(0, tb_pwm_axi);
    end
`endif

endmodule
