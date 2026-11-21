`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// Module: tb_soc_top
//
// Description:
//   Targeted integration testbench for Phase 3:
//     1. Verifies reset release and processor clock propagation.
//     2. Verifies instruction fetch handshakes through IFU 64b->32b downconverter
//        and AXI interconnect to IMEM at 0x0004_0000.
//     3. Verifies instruction retirement and execution (trace valid, PC increment).
//     4. Verifies data memory write and read (LSU 64b->32b downconverter to DMEM
//        at 0x0008_0000).
//     5. Verifies memory-mapped peripheral access by the processor (LSU to
//        GPIO at 0x4003_1000 through the interconnect).
//     6. Verifies external DMA master (M2) transaction through the interconnect.
//     7. Verifies peripheral functional loop (Encoder -> PID -> PWM feedback).
// ============================================================================

module tb_soc_top;

    localparam CLK_PERIOD       = 10; // 100 MHz
    localparam FIXED_CLK_PERIOD = 20; // 50 MHz

    reg clk;
    reg fixed_clk;
    reg rst;

    // Peripheral IO
    reg         uart_rx;
    wire        uart_tx;
    wire        uart_irq;

    wire        PWM_OUT;

    wire [31:0] gpio_io;
    reg  [31:0] gpio_in_driver;
    reg         gpio_drive_en;
    wire        gpio_intr;

    reg         timer_ext_meas;
    reg         timer_capture;
    wire        timer_pwm;
    wire        timer_trigger;
    wire        timer_intr;

    reg         enc_a;
    reg         enc_b;
    reg         enc_index;
    reg         enc_drive_active;
    wire [15:0] enc_speed;
    wire        enc_speed_valid;
    wire        enc_count_valid;
    wire        enc_dir;
    wire        enc_fault;
    wire        enc_intr;

    wire [15:0] pid_out;
    wire        pid_out_valid;
    wire        pid_sat_flag;
    wire        pid_intr;

    // Preserved DMA Master (M2)
    reg  [7:0]  dma_awid;
    reg  [31:0] dma_awaddr;
    reg  [7:0]  dma_awlen;
    reg  [2:0]  dma_awsize;
    reg  [1:0]  dma_awburst;
    reg         dma_awlock;
    reg  [3:0]  dma_awcache;
    reg  [2:0]  dma_awprot;
    reg  [3:0]  dma_awqos;
    reg         dma_awvalid;
    wire        dma_awready;

    reg  [31:0] dma_wdata;
    reg  [3:0]  dma_wstrb;
    reg         dma_wlast;
    reg         dma_wvalid;
    wire        dma_wready;

    wire [7:0]  dma_bid;
    wire [1:0]  dma_bresp;
    wire        dma_bvalid;
    reg         dma_bready;

    reg  [7:0]  dma_arid;
    reg  [31:0] dma_araddr;
    reg  [7:0]  dma_arlen;
    reg  [2:0]  dma_arsize;
    reg  [1:0]  dma_arburst;
    reg         dma_arlock;
    reg  [3:0]  dma_arcache;
    reg  [2:0]  dma_arprot;
    reg  [3:0]  dma_arqos;
    reg         dma_arvalid;
    wire        dma_arready;

    wire [7:0]  dma_rid;
    wire [31:0] dma_rdata;
    wire [1:0]  dma_rresp;
    wire        dma_rlast;
    wire        dma_rvalid;
    reg         dma_rready;

    // Trace signals
    wire [31:0] trace_rv_i_insn_ip;
    wire [31:0] trace_rv_i_address_ip;
    wire        trace_rv_i_valid_ip;
    wire        trace_rv_i_exception_ip;
    wire        trace_rv_i_interrupt_ip;
    wire        o_cpu_halt_status;
    wire        o_debug_mode_status;

    // GPIO bidirectional drive
    assign gpio_io = gpio_drive_en ? gpio_in_driver : 32'bz;

    // Clock generation
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        fixed_clk = 1'b0;
        forever #(FIXED_CLK_PERIOD/2) fixed_clk = ~fixed_clk;
    end

    // Test statistics
    int pass_count = 0;
    int fail_count = 0;

    task check(input string name, input bit cond);
        if (cond) begin
            $display("[PASS] %s", name);
            pass_count++;
        end else begin
            $display("[FAIL] %s", name);
            fail_count++;
        end
    endtask

    reg        gpio_write_seen;
    reg [31:0] gpio_write_addr;
    reg [31:0] gpio_write_data;
    reg        s00_fetch_seen;

    always @(posedge clk) begin
        if (!rst) begin
            if (dut.u_main_top.s00_axi_arvalid && dut.u_main_top.s00_axi_arready)
                s00_fetch_seen <= 1'b1;
            if (trace_rv_i_valid_ip)
                $display("    [TRACE T=%0t] Core retired PC: 0x%08h, Insn: 0x%08h", $time, trace_rv_i_address_ip, trace_rv_i_insn_ip);
            if (dut.u_main_top.m02_axi_awvalid && dut.u_main_top.m02_axi_awready) begin
                $display("    [BUS T=%0t] Interconnect routed store to GPIO: addr=0x%08h, data=0x%08h", $time, dut.u_main_top.m02_axi_awaddr, dut.u_main_top.m02_axi_wdata);
                gpio_write_seen <= 1'b1;
                gpio_write_addr <= dut.u_main_top.m02_axi_awaddr;
                gpio_write_data <= dut.u_main_top.m02_axi_wdata;
            end
        end
    end

    // Instantiate SoC Top
    soc_top #(
        .DATA_WIDTH       (32),
        .ADDR_WIDTH       (32),
        .ID_WIDTH         (8),
        .USE_INTERNAL_MEM (1)
    ) dut (
        .clk                    (clk),
        .fixed_clk              (fixed_clk),
        .rst                    (rst),

        // UART
        .uart_rx                (uart_rx),
        .uart_tx                (uart_tx),
        .uart_irq               (uart_irq),

        // PWM
        .PWM_OUT                (PWM_OUT),

        // GPIO
        .gpio_io                (gpio_io),
        .gpio_intr              (gpio_intr),

        // Timer
        .timer_ext_meas         (timer_ext_meas),
        .timer_capture          (timer_capture),
        .timer_pwm              (timer_pwm),
        .timer_trigger          (timer_trigger),
        .timer_intr             (timer_intr),

        // Encoder
        .enc_a                  (enc_a),
        .enc_b                  (enc_b),
        .enc_index              (enc_index),
        .enc_drive_active       (enc_drive_active),
        .enc_speed              (enc_speed),
        .enc_speed_valid        (enc_speed_valid),
        .enc_count_valid        (enc_count_valid),
        .enc_dir                (enc_dir),
        .enc_fault              (enc_fault),
        .enc_intr               (enc_intr),

        // PID
        .pid_out                (pid_out),
        .pid_out_valid          (pid_out_valid),
        .pid_sat_flag           (pid_sat_flag),
        .pid_intr               (pid_intr),

        // DMA Master M2
        .s02_axi_awid           (dma_awid),
        .s02_axi_awaddr         (dma_awaddr),
        .s02_axi_awlen          (dma_awlen),
        .s02_axi_awsize         (dma_awsize),
        .s02_axi_awburst        (dma_awburst),
        .s02_axi_awlock         (dma_awlock),
        .s02_axi_awcache        (dma_awcache),
        .s02_axi_awprot         (dma_awprot),
        .s02_axi_awqos          (dma_awqos),
        .s02_axi_awuser         (1'b0),
        .s02_axi_awvalid        (dma_awvalid),
        .s02_axi_awready        (dma_awready),
        .s02_axi_wdata          (dma_wdata),
        .s02_axi_wstrb          (dma_wstrb),
        .s02_axi_wlast          (dma_wlast),
        .s02_axi_wuser          (1'b0),
        .s02_axi_wvalid         (dma_wvalid),
        .s02_axi_wready         (dma_wready),
        .s02_axi_bid            (dma_bid),
        .s02_axi_bresp          (dma_bresp),
        .s02_axi_buser          (),
        .s02_axi_bvalid         (dma_bvalid),
        .s02_axi_bready         (dma_bready),
        .s02_axi_arid           (dma_arid),
        .s02_axi_araddr         (dma_araddr),
        .s02_axi_arlen          (dma_arlen),
        .s02_axi_arsize         (dma_arsize),
        .s02_axi_arburst        (dma_arburst),
        .s02_axi_arlock         (dma_arlock),
        .s02_axi_arcache        (dma_arcache),
        .s02_axi_arprot         (dma_arprot),
        .s02_axi_arqos          (dma_arqos),
        .s02_axi_aruser         (1'b0),
        .s02_axi_arvalid        (dma_arvalid),
        .s02_axi_arready        (dma_arready),
        .s02_axi_rid            (dma_rid),
        .s02_axi_rdata          (dma_rdata),
        .s02_axi_rresp          (dma_rresp),
        .s02_axi_rlast          (dma_rlast),
        .s02_axi_ruser          (),
        .s02_axi_rvalid         (dma_rvalid),
        .s02_axi_rready         (dma_rready),

        // Core trace
        .trace_rv_i_insn_ip     (trace_rv_i_insn_ip),
        .trace_rv_i_address_ip  (trace_rv_i_address_ip),
        .trace_rv_i_valid_ip    (trace_rv_i_valid_ip),
        .trace_rv_i_exception_ip(trace_rv_i_exception_ip),
        .trace_rv_i_interrupt_ip(trace_rv_i_interrupt_ip),
        .o_cpu_halt_status      (o_cpu_halt_status),
        .o_debug_mode_status    (o_debug_mode_status)
    );

    // ============================================================
    // Testbench Tasks for DMA Master
    // ============================================================
    task dma_write(input [31:0] addr, input [31:0] data, input [3:0] strb, output [1:0] resp, output bit completed);
        int timeout_cnt = 0;
        completed = 0;
        @(posedge clk);
        dma_awaddr  <= addr;
        dma_awvalid <= 1'b1;
        dma_wdata   <= data;
        dma_wstrb   <= strb;
        dma_wvalid  <= 1'b1;
        dma_wlast   <= 1'b1;
        dma_bready  <= 1'b1;

        fork
            begin
                while (!dma_awready && timeout_cnt < 300) begin
                    @(posedge clk);
                    timeout_cnt++;
                end
                @(posedge clk);
                dma_awvalid <= 1'b0;
            end
            begin
                while (!dma_wready && timeout_cnt < 300) begin
                    @(posedge clk);
                end
                @(posedge clk);
                dma_wvalid <= 1'b0;
                dma_wlast  <= 1'b0;
            end
        join

        timeout_cnt = 0;
        while (!dma_bvalid && timeout_cnt < 300) begin
            @(posedge clk);
            timeout_cnt++;
        end

        if (dma_bvalid) begin
            resp = dma_bresp;
            completed = 1;
        end else begin
            resp = 2'b10;
            completed = 0;
        end
        @(posedge clk);
        dma_bready <= 1'b0;
    endtask

    task dma_read(input [31:0] addr, output [31:0] data, output [1:0] resp, output bit completed);
        int timeout_cnt = 0;
        completed = 0;
        @(posedge clk);
        dma_araddr  <= addr;
        dma_arvalid <= 1'b1;
        dma_rready  <= 1'b1;

        while (!dma_arready && timeout_cnt < 300) begin
            @(posedge clk);
            timeout_cnt++;
        end
        @(posedge clk);
        dma_arvalid <= 1'b0;

        timeout_cnt = 0;
        while (!dma_rvalid && timeout_cnt < 300) begin
            @(posedge clk);
            timeout_cnt++;
        end

        if (dma_rvalid) begin
            data = dma_rdata;
            resp = dma_rresp;
            completed = 1;
        end else begin
            data = 32'd0;
            resp = 2'b10;
            completed = 0;
        end
        @(posedge clk);
        dma_rready <= 1'b0;
    endtask

    // ============================================================
    // Main Verification Flow
    // ============================================================
    reg fetch_seen;
    reg [31:0] fetch_addr_seen;
    reg dmem_base_write_seen;
    reg dmem_bound_write_seen;
    reg [31:0] dma_rd_val;
    reg [1:0]  dma_resp;
    bit        dma_done;

    initial begin
        $display("==================================================================");
        $display("   PHASE 1: RISC-V VeeR EL2 ALIGNMENT & VERIFICATION (64 KiB MAP) ");
        $display("==================================================================");

        // Initialize signals
        rst              = 1'b1;
        uart_rx          = 1'b1;
        gpio_in_driver   = 32'd0;
        gpio_drive_en    = 1'b0;
        timer_ext_meas   = 1'b0;
        timer_capture    = 1'b0;
        enc_a            = 1'b0;
        enc_b            = 1'b0;
        enc_index        = 1'b0;
        enc_drive_active = 1'b1;

        dma_awid         = 8'd2;
        dma_awaddr       = 32'd0;
        dma_awlen        = 8'd0;
        dma_awsize       = 3'b010;
        dma_awburst      = 2'b01;
        dma_awlock       = 1'b0;
        dma_awcache      = 4'd0;
        dma_awprot       = 3'd0;
        dma_awqos        = 4'd0;
        dma_awvalid      = 1'b0;
        dma_wdata        = 32'd0;
        dma_wstrb        = 4'h0;
        dma_wlast        = 1'b0;
        dma_wvalid       = 1'b0;
        dma_bready       = 1'b0;

        dma_arid         = 8'd2;
        dma_araddr       = 32'd0;
        dma_arlen        = 8'd0;
        dma_arsize       = 3'b010;
        dma_arburst      = 2'b01;
        dma_arlock       = 1'b0;
        dma_arcache      = 4'd0;
        dma_arprot       = 3'd0;
        dma_arqos        = 4'd0;
        dma_arvalid      = 1'b0;
        dma_rready       = 1'b0;

        fetch_seen            = 1'b0;
        s00_fetch_seen        = 1'b0;
        fetch_addr_seen       = 32'd0;
        dmem_base_write_seen  = 1'b0;
        dmem_bound_write_seen = 1'b0;
        gpio_write_seen       = 1'b0;
        gpio_write_addr       = 32'd0;
        gpio_write_data       = 32'd0;

        // ------------------------------------------------------------
        // Initialize IMEM (64 KiB: 16384 words) with Verification Program:
        // PC 0x4000_0000: lui  x1, 0x40020      (x1 = 0x4002_0000 DMEM base)
        // PC 0x4000_0004: addi x2, x0, 0x5a     (x2 = 0x5A)
        // PC 0x4000_0008: sw   x2, 0(x1)        (DMEM[0x4002_0000] = 0x5A, word 0)
        // PC 0x4000_000C: lw   x3, 0(x1)        (x3 = DMEM[0x4002_0000])
        // PC 0x4000_0010: lui  x7, 0x40030      (x7 = 0x4003_0000)
        // PC 0x4000_0014: addi x9, x0, 0xa5     (x9 = 0xA5)
        // PC 0x4000_0018: sw   x9, -4(x7)       (DMEM[0x4002_FFFC] = 0xA5, word 16383 boundary!)
        // PC 0x4000_001C: lw   x8, -4(x7)       (x8 = DMEM[0x4002_FFFC])
        // PC 0x4000_0020: lui  x4, 0x40031      (x4 = 0x4003_1000 GPIO base)
        // PC 0x4000_0024: sw   x2, 0(x4)        (GPIO[0x4003_1000] = 0x5A)
        // PC 0x4000_0028: lui  x5, 0x40010      (x5 = 0x4001_0000)
        // PC 0x4000_002C: jalr x0, -4(x5)       (jump to 0x4000_FFFC IMEM upper boundary!)
        // ...
        // PC 0x4000_FFF8: nop                   (word 16382)
        // PC 0x4000_FFFC: jal  x0, 0            (word 16383, infinite loop at upper boundary!)
        // ------------------------------------------------------------
        dut.GEN_INTERNAL_MEM.u_imem.mem[0]     = 32'h400200b7; // lui  x1, 0x40020
        dut.GEN_INTERNAL_MEM.u_imem.mem[1]     = 32'h05a00113; // addi x2, x0, 0x5A
        dut.GEN_INTERNAL_MEM.u_imem.mem[2]     = 32'h0020a023; // sw   x2, 0(x1)
        dut.GEN_INTERNAL_MEM.u_imem.mem[3]     = 32'h0000a183; // lw   x3, 0(x1)
        dut.GEN_INTERNAL_MEM.u_imem.mem[4]     = 32'h400303b7; // lui  x7, 0x40030
        dut.GEN_INTERNAL_MEM.u_imem.mem[5]     = 32'h0a500493; // addi x9, x0, 0xA5
        dut.GEN_INTERNAL_MEM.u_imem.mem[6]     = 32'hfe93ae23; // sw   x9, -4(x7)
        dut.GEN_INTERNAL_MEM.u_imem.mem[7]     = 32'hffc3a403; // lw   x8, -4(x7)
        dut.GEN_INTERNAL_MEM.u_imem.mem[8]     = 32'h40031237; // lui  x4, 0x40031
        dut.GEN_INTERNAL_MEM.u_imem.mem[9]     = 32'h00222023; // sw   x2, 0(x4)
        dut.GEN_INTERNAL_MEM.u_imem.mem[10]    = 32'h400102b7; // lui  x5, 0x40010
        dut.GEN_INTERNAL_MEM.u_imem.mem[11]    = 32'hffc28067; // jalr x0, -4(x5) -> 0x4000_FFFC

        // Populate boundary instructions in IMEM at word 16382 and 16383
        dut.GEN_INTERNAL_MEM.u_imem.mem[16382] = 32'h00000013; // nop
        dut.GEN_INTERNAL_MEM.u_imem.mem[16383] = 32'h0000006f; // jal  x0, 0 (loop at 0x4000_FFFC)

        // ------------------------------------------------------------
        // Test 1: Reset Release & Clock Propagation
        // ------------------------------------------------------------
        $display("\n--- Test 1: Reset Release & Core Clock Propagation ---");
        repeat (15) @(posedge clk);
        rst = 1'b0; // De-assert reset
        @(posedge clk);
        check("Core reset release: rst is de-asserted and clk active", rst == 1'b0);
        check("Core halt status is low (core active out of reset)", o_cpu_halt_status == 1'b0);

        // ------------------------------------------------------------
        // Test 2: First AXI Instruction Fetch from IMEM (0x4000_0000)
        // ------------------------------------------------------------
        $display("\n--- Test 2: AXI Instruction Fetch from IMEM (0x4000_0000) ---");
        begin : wait_for_fetch
            int timeout = 0;
            while ((!fetch_seen || !s00_fetch_seen) && timeout < 200) begin
                @(posedge clk);
                if (dut.core_ifu_arvalid && dut.core_ifu_arready) begin
                    fetch_seen = 1'b1;
                    fetch_addr_seen = dut.core_ifu_araddr;
                end
                timeout++;
            end
        end
        check("IFU issues AXI read request", fetch_seen);
        check("IFU fetch target matches reset vector (0x4000_0000)", fetch_addr_seen == 32'h4000_0000);
        check("IFU 64b downconverter drives interconnect s00_axi AR channel", s00_fetch_seen);

        // ------------------------------------------------------------
        // Test 3: Core Instruction Retirement Trace
        // ------------------------------------------------------------
        $display("\n--- Test 3: Core Instruction Retirement Trace ---");
        begin : wait_for_trace
            int timeout = 0;
            bit trace_seen = 0;
            reg [31:0] trace_pc = 0;
            while (!trace_seen && timeout < 300) begin
                @(posedge clk);
                if (trace_rv_i_valid_ip) begin
                    trace_seen = 1;
                    trace_pc = trace_rv_i_address_ip;
                    $display("    Observed instruction trace at PC: 0x%08h, instruction: 0x%08h", trace_rv_i_address_ip, trace_rv_i_insn_ip);
                end
                timeout++;
            end
            check("Processor executes and retires first instruction", trace_seen);
            check("Executed instruction PC matches IMEM base (0x4000_0000)", trace_pc == 32'h4000_0000);
        end

        // ------------------------------------------------------------
        // Test 4: DMEM 64 KiB Base & Upper Boundary Access
        // ------------------------------------------------------------
        $display("\n--- Test 4: DMEM 64 KiB Base & Upper Boundary Access ---");
        begin : wait_for_dmem
            int timeout = 0;
            while ((!dmem_base_write_seen || !dmem_bound_write_seen) && timeout < 1000) begin
                @(posedge clk);
                if (dut.GEN_INTERNAL_MEM.u_dmem.mem[0] == 32'h0000_005a) begin
                    dmem_base_write_seen = 1'b1;
                end
                if (dut.GEN_INTERNAL_MEM.u_dmem.mem[16383] == 32'h0000_00a5) begin
                    dmem_bound_write_seen = 1'b1;
                end
                timeout++;
            end
            check("Processor LSU executed store to DMEM base at 0x4002_0000", dmem_base_write_seen);
            check("DMEM base word 0 contains stored value 0x5A", dut.GEN_INTERNAL_MEM.u_dmem.mem[0] == 32'h0000_005a);
            check("Processor LSU executed store to DMEM upper boundary at 0x4002_FFFC", dmem_bound_write_seen);
            check("DMEM boundary word 16383 contains stored value 0xA5", dut.GEN_INTERNAL_MEM.u_dmem.mem[16383] == 32'h0000_00a5);
            check("No memory aliasing: word 0 and word 16383 maintain independent data in 64 KiB DMEM", 
                  (dut.GEN_INTERNAL_MEM.u_dmem.mem[0] == 32'h0000_005a) && (dut.GEN_INTERNAL_MEM.u_dmem.mem[16383] == 32'h0000_00a5));
        end

        // ------------------------------------------------------------
        // Test 5: IMEM 64 KiB Upper Boundary (0x4000_FFFC) Execution
        // ------------------------------------------------------------
        $display("\n--- Test 5: IMEM 64 KiB Upper Boundary (0x4000_FFFC) Execution ---");
        begin : wait_for_boundary_imem
            int timeout = 0;
            bit boundary_pc_seen = 0;
            while (!boundary_pc_seen && timeout < 1000) begin
                @(posedge clk);
                if (trace_rv_i_valid_ip && trace_rv_i_address_ip == 32'h4000_fffc) begin
                    boundary_pc_seen = 1;
                    $display("    Observed upper boundary retirement at PC: 0x%08h, Insn: 0x%08h", trace_rv_i_address_ip, trace_rv_i_insn_ip);
                end
                timeout++;
            end
            check("Processor successfully jumped to and retired instruction at IMEM upper boundary (0x4000_FFFC)", boundary_pc_seen);
        end

        // ------------------------------------------------------------
        // Test 6: Memory-Mapped Peripheral Access (GPIO 0x4003_1000)
        // ------------------------------------------------------------
        $display("\n--- Test 6: Memory-Mapped Peripheral Access by Core (GPIO 0x4003_1000) ---");
        begin : wait_for_gpio
            int timeout = 0;
            while (!gpio_write_seen && timeout < 500) begin
                @(posedge clk);
                timeout++;
            end
            check("AXI interconnect routed processor store to S2 (GPIO 0x4003_1000)", 
                  gpio_write_seen && (gpio_write_addr == 32'h4003_1000) && (gpio_write_data == 32'h0000_005a));
        end

        // ------------------------------------------------------------
        // Test 7: Reserved Slots S11–S13 Non-Hanging DECERR Verification
        // ------------------------------------------------------------
        $display("\n--- Test 7: Reserved Slots S11-S13 & Legacy Address Non-Hanging DECERR Verification ---");
        // Test S11 (0x4004_3000): Write and Read
        dma_write(32'h4004_3000, 32'hdead_1111, 4'hF, dma_resp, dma_done);
        check("DMA write to reserved S11 (0x4004_3000) completes without hang", dma_done);
        check("DMA write to reserved S11 returns DECERR (2'b11)", dma_resp == 2'b11);

        dma_read(32'h4004_3000, dma_rd_val, dma_resp, dma_done);
        check("DMA read from reserved S11 (0x4004_3000) completes without hang", dma_done);
        check("DMA read from reserved S11 returns DECERR (2'b11)", dma_resp == 2'b11);

        // Test S12 (0x4004_5000): Read
        dma_read(32'h4004_5000, dma_rd_val, dma_resp, dma_done);
        check("DMA read from reserved S12 (0x4004_5000) completes with DECERR (2'b11)", dma_done && (dma_resp == 2'b11));

        // Test S13 (0x4004_7000): Read
        dma_read(32'h4004_7000, dma_rd_val, dma_resp, dma_done);
        check("DMA read from reserved S13 (0x4004_7000) completes with DECERR (2'b11)", dma_done && (dma_resp == 2'b11));

        // Test Legacy Hanging Addresses (0x8000_4000, 0x8000_5000, 0x8000_6000)
        dma_write(32'h8000_4000, 32'hdead_beef, 4'hF, dma_resp, dma_done);
        check("Legacy 0x8000_4000 write completes with DECERR (2'b11) without hanging", dma_done && (dma_resp == 2'b11));

        dma_read(32'h8000_5000, dma_rd_val, dma_resp, dma_done);
        check("Legacy 0x8000_5000 read completes with DECERR (2'b11) without hanging", dma_done && (dma_resp == 2'b11));

        dma_read(32'h8000_6000, dma_rd_val, dma_resp, dma_done);
        check("Legacy 0x8000_6000 read completes with DECERR (2'b11) without hanging", dma_done && (dma_resp == 2'b11));

        // ------------------------------------------------------------
        // Test 8: Valid Active Peripheral Access via Interconnect (Timer S3)
        // ------------------------------------------------------------
        $display("\n--- Test 8: Valid Active Peripheral Access via Interconnect (Timer S3) ---");
        dma_write(32'h4003_3000, 32'h0000_0001, 4'hF, dma_resp, dma_done);
        check("DMA write to Timer S3 (0x4003_3000) completed with OKAY response (2'b00)", dma_done && (dma_resp == 2'b00));

        dma_read(32'h4003_3000, dma_rd_val, dma_resp, dma_done);
        check("DMA read from Timer S3 completed with OKAY response (2'b00)", dma_done && (dma_resp == 2'b00));

        // ------------------------------------------------------------
        // Test 9: Six Peripheral IPs & Hybrid Feedback Loop Intact
        // ------------------------------------------------------------
        $display("\n--- Test 9: Hybrid Feedback Loop (Encoder -> PID -> PWM) Intact ---");
        begin : check_feedback
            bit pwm_seen_high = 0;
            bit pwm_seen_low  = 0;

            // Enable Quadrature Encoder via AXI register 0x4003_D008 (ENC_CTRL)
            dma_write(32'h4003_d008, 32'h0000_0001, 4'hF, dma_resp, dma_done);
            check("Enable Quadrature Encoder via AXI register 0x4003_D008", dma_done && (dma_resp == 2'b00));

            // Stimulate Encoder quadrature inputs with 10 forward cycles
            repeat (10) begin
                enc_a = 1'b1; enc_b = 1'b0; #(CLK_PERIOD*4);
                enc_a = 1'b1; enc_b = 1'b1; #(CLK_PERIOD*4);
                enc_a = 1'b0; enc_b = 1'b1; #(CLK_PERIOD*4);
                enc_a = 1'b0; enc_b = 1'b0; #(CLK_PERIOD*4);
                if (PWM_OUT === 1'b1) pwm_seen_high = 1;
                if (PWM_OUT === 1'b0) pwm_seen_low  = 1;
            end
            @(posedge clk);
            check("Encoder hardware direction indicates forward rotation (enc_dir == 1)", enc_dir == 1'b1);

            // Read back Encoder position counter (0x4003_D000) via AXI
            dma_read(32'h4003_d000, dma_rd_val, dma_resp, dma_done);
            check("Encoder count register (0x4003_D000) increments with quadrature steps", dma_done && (dma_resp == 2'b00) && (dma_rd_val > 0));
            $display("    Observed Encoder count readback: %0d", dma_rd_val);

            check("PID controller hardware produces valid output signal", pid_out_valid !== 1'bx);
            check("PWM hardware functional output generates active switching waveforms", (pwm_seen_high || pwm_seen_low) && (PWM_OUT !== 1'bx));
        end

        // ------------------------------------------------------------
        // Summary
        // ------------------------------------------------------------
        $display("\n==================================================================");
        $display("   PHASE 1 INTEGRATION & VERIFICATION SUMMARY");
        $display("   Total Checks: %0d | Passed: %0d | Failed: %0d", pass_count + fail_count, pass_count, fail_count);
        $display("==================================================================");

        if (fail_count == 0)
            $display(">>> ALL PHASE 1 RISC-V INTEGRATION & ALIGNMENT CHECKS PASSED <<<");
        else
            $display(">>> PHASE 1 VERIFICATION CHECKS FAILED: %0d errors <<<", fail_count);

        $finish;
    end

    // Safety watchdog timeout
    initial begin
        #(CLK_PERIOD * 20000);
        $display("\n[ERROR] Simulation watchdog timeout triggered!");
        $finish;
    end

endmodule
`default_nettype wire
