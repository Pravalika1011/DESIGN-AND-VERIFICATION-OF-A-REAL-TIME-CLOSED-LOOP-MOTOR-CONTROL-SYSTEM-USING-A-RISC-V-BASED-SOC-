`timescale 1ns / 1ps
`default_nettype none

/*
================================================================================
 Project        : Fail-Safe Railway Level-Crossing Control System (Honours CBP)
 Module         : tb_hybrid_feedback
 Description    : Dedicated Verification Testbench for Phase 2 Hardware Hybrid
                  Closed-Loop Feedback:
                    - Timer S3 (trigger_o) -> PID S9 (tick_i)
                    - Encoder S8 (speed_o) -> PID S9 (actual_i)
                    - PID S9 (pid_out_o)   -> PWM S10 (hw_duty_i) with saturation
                    - PWM S10 (PWM_OUT)    -> Behavioral Motor Plant -> enc_a/enc_b
================================================================================
*/

module tb_hybrid_feedback;

    // ============================================================
    // 1. PARAMETERS & BASE ADDRESSES
    // ============================================================
    localparam integer DATA_WIDTH    = 32;
    localparam integer ADDR_WIDTH    = 32;
    localparam integer STRB_WIDTH    = (DATA_WIDTH/8);
    localparam integer ID_WIDTH      = 8;
    localparam integer AWUSER_WIDTH  = 1;
    localparam integer WUSER_WIDTH   = 1;
    localparam integer BUSER_WIDTH   = 1;
    localparam integer ARUSER_WIDTH  = 1;
    localparam integer RUSER_WIDTH   = 1;

    // Slave Base Addresses
    localparam logic [31:0] ADDR_S0_IMEM     = 32'h0004_0000;
    localparam logic [31:0] ADDR_S1_DMEM     = 32'h0008_0000;
    localparam logic [31:0] ADDR_S2_GPIO     = 32'h4003_1000;
    localparam logic [31:0] ADDR_S3_TIMER    = 32'h4003_3000;
    localparam logic [31:0] ADDR_S4_UART     = 32'h4003_5000;
    localparam logic [31:0] ADDR_S8_ENC      = 32'h4003_D000;
    localparam logic [31:0] ADDR_S9_PID      = 32'h4003_F000;
    localparam logic [31:0] ADDR_S10_PWM     = 32'h4004_1000;

    // Peripheral Register Offsets
    localparam logic [31:0] TIMER_CTRL       = 32'h4003_3000;
    localparam logic [31:0] TIMER_LOAD       = 32'h4003_3004;
    localparam logic [31:0] TIMER_VAL        = 32'h4003_3008;

    localparam logic [31:0] GPIO_DATA_I      = 32'h4003_1000;
    localparam logic [31:0] GPIO_DATA_O      = 32'h4003_1004;
    localparam logic [31:0] GPIO_DIR         = 32'h4003_1008;

    localparam logic [31:0] UART_RBR_THR     = 32'h4003_5000;
    localparam logic [31:0] UART_LSR         = 32'h4003_5014;

    localparam logic [31:0] ENC_COUNT        = 32'h4003_D000;
    localparam logic [31:0] ENC_SPEED        = 32'h4003_D004;
    localparam logic [31:0] ENC_CTRL         = 32'h4003_D008;
    localparam logic [31:0] ENC_WINDOW       = 32'h4003_D010;
    localparam logic [31:0] ENC_SCALE        = 32'h4003_D018;

    localparam logic [31:0] PID_SETPOINT     = 32'h4003_F000;
    localparam logic [31:0] PID_KP           = 32'h4003_F004;
    localparam logic [31:0] PID_KI           = 32'h4003_F008;
    localparam logic [31:0] PID_KD           = 32'h4003_F00C;
    localparam logic [31:0] PID_OUT          = 32'h4003_F010;
    localparam logic [31:0] PID_CTRL         = 32'h4003_F014;
    localparam logic [31:0] PID_STATUS       = 32'h4003_F018;
    localparam logic [31:0] PID_ACTUAL       = 32'h4003_F020;
    localparam logic [31:0] PID_OUT_MAX      = 32'h4003_F024;
    localparam logic [31:0] PID_OUT_MIN      = 32'h4003_F028;

    localparam logic [31:0] PWM_REG0         = 32'h4004_1000; // Duty cycle
    localparam logic [31:0] PWM_REG1         = 32'h4004_1004;

    // ============================================================
    // 2. SIGNALS & INTERFACES
    // ============================================================
    logic clk;
    logic fixed_clk;
    logic rst;

    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz
    end

    initial begin
        fixed_clk = 0;
        forever #25 fixed_clk = ~fixed_clk; // 20 MHz
    end

    // Master 1 signals (LSU / Software interface)
    logic [ID_WIDTH-1:0]      m1_awid;
    logic [ADDR_WIDTH-1:0]    m1_awaddr;
    logic [7:0]               m1_awlen;
    logic [2:0]               m1_awsize;
    logic [1:0]               m1_awburst;
    logic                     m1_awlock;
    logic [3:0]               m1_awcache;
    logic [2:0]               m1_awprot;
    logic [3:0]               m1_awqos;
    logic [AWUSER_WIDTH-1:0]  m1_awuser;
    logic                     m1_awvalid;
    wire                      m1_awready;

    logic [DATA_WIDTH-1:0]    m1_wdata;
    logic [STRB_WIDTH-1:0]    m1_wstrb;
    logic                     m1_wlast;
    logic [WUSER_WIDTH-1:0]   m1_wuser;
    logic                     m1_wvalid;
    wire                      m1_wready;

    wire  [ID_WIDTH-1:0]      m1_bid;
    wire  [1:0]               m1_bresp;
    wire  [BUSER_WIDTH-1:0]   m1_buser;
    wire                      m1_bvalid;
    logic                     m1_bready;

    logic [ID_WIDTH-1:0]      m1_arid;
    logic [ADDR_WIDTH-1:0]    m1_araddr;
    logic [7:0]               m1_arlen;
    logic [2:0]               m1_arsize;
    logic [1:0]               m1_arburst;
    logic                     m1_arlock;
    logic [3:0]               m1_arcache;
    logic [2:0]               m1_arprot;
    logic [3:0]               m1_arqos;
    logic [ARUSER_WIDTH-1:0]  m1_aruser;
    logic                     m1_arvalid;
    wire                      m1_arready;

    wire  [ID_WIDTH-1:0]      m1_rid;
    wire  [DATA_WIDTH-1:0]    m1_rdata;
    wire  [1:0]               m1_rresp;
    wire                      m1_rlast;
    wire  [RUSER_WIDTH-1:0]   m1_ruser;
    wire                      m1_rvalid;
    logic                     m1_rready;

    // Masters 0 & 2 tied off
    logic [ID_WIDTH-1:0]      m0_awid;
    logic [ADDR_WIDTH-1:0]    m0_awaddr;
    logic [7:0]               m0_awlen;
    logic [2:0]               m0_awsize;
    logic [1:0]               m0_awburst;
    logic                     m0_awlock;
    logic [3:0]               m0_awcache;
    logic [2:0]               m0_awprot;
    logic [3:0]               m0_awqos;
    logic [AWUSER_WIDTH-1:0]  m0_awuser;
    logic                     m0_awvalid;
    wire                      m0_awready;
    logic [DATA_WIDTH-1:0]    m0_wdata;
    logic [STRB_WIDTH-1:0]    m0_wstrb;
    logic                     m0_wlast;
    logic [WUSER_WIDTH-1:0]   m0_wuser;
    logic                     m0_wvalid;
    wire                      m0_wready;
    wire  [ID_WIDTH-1:0]      m0_bid;
    wire  [1:0]               m0_bresp;
    wire  [BUSER_WIDTH-1:0]   m0_buser;
    wire                      m0_bvalid;
    logic                     m0_bready;
    logic [ID_WIDTH-1:0]      m0_arid;
    logic [ADDR_WIDTH-1:0]    m0_araddr;
    logic [7:0]               m0_arlen;
    logic [2:0]               m0_arsize;
    logic [1:0]               m0_arburst;
    logic                     m0_arlock;
    logic [3:0]               m0_arcache;
    logic [2:0]               m0_arprot;
    logic [3:0]               m0_arqos;
    logic [ARUSER_WIDTH-1:0]  m0_aruser;
    logic                     m0_arvalid;
    wire                      m0_arready;
    wire  [ID_WIDTH-1:0]      m0_rid;
    wire  [DATA_WIDTH-1:0]    m0_rdata;
    wire  [1:0]               m0_rresp;
    wire                      m0_rlast;
    wire  [RUSER_WIDTH-1:0]   m0_ruser;
    wire                      m0_rvalid;
    logic                     m0_rready;

    logic [ID_WIDTH-1:0]      m2_awid;
    logic [ADDR_WIDTH-1:0]    m2_awaddr;
    logic [7:0]               m2_awlen;
    logic [2:0]               m2_awsize;
    logic [1:0]               m2_awburst;
    logic                     m2_awlock;
    logic [3:0]               m2_awcache;
    logic [2:0]               m2_awprot;
    logic [3:0]               m2_awqos;
    logic [AWUSER_WIDTH-1:0]  m2_awuser;
    logic                     m2_awvalid;
    wire                      m2_awready;
    logic [DATA_WIDTH-1:0]    m2_wdata;
    logic [STRB_WIDTH-1:0]    m2_wstrb;
    logic                     m2_wlast;
    logic [WUSER_WIDTH-1:0]   m2_wuser;
    logic                     m2_wvalid;
    wire                      m2_wready;
    wire  [ID_WIDTH-1:0]      m2_bid;
    wire  [1:0]               m2_bresp;
    wire  [BUSER_WIDTH-1:0]   m2_buser;
    wire                      m2_bvalid;
    logic                     m2_bready;
    logic [ID_WIDTH-1:0]      m2_arid;
    logic [ADDR_WIDTH-1:0]    m2_araddr;
    logic [7:0]               m2_arlen;
    logic [2:0]               m2_arsize;
    logic [1:0]               m2_arburst;
    logic                     m2_arlock;
    logic [3:0]               m2_arcache;
    logic [2:0]               m2_arprot;
    logic [3:0]               m2_arqos;
    logic [ARUSER_WIDTH-1:0]  m2_aruser;
    logic                     m2_arvalid;
    wire                      m2_arready;
    wire  [ID_WIDTH-1:0]      m2_rid;
    wire  [DATA_WIDTH-1:0]    m2_rdata;
    wire  [1:0]               m2_rresp;
    wire                      m2_rlast;
    wire  [RUSER_WIDTH-1:0]   m2_ruser;
    wire                      m2_rvalid;
    logic                     m2_rready;

    // External dummy responders for S0, S1, S5, S6, S7, S11, S12, S13, S14
    wire [ID_WIDTH-1:0]      slv_awid     [0:14];
    wire [ADDR_WIDTH-1:0]    slv_awaddr   [0:14];
    wire [7:0]               slv_awlen    [0:14];
    wire [2:0]               slv_awsize   [0:14];
    wire [1:0]               slv_awburst  [0:14];
    wire                     slv_awlock   [0:14];
    wire [3:0]               slv_awcache  [0:14];
    wire [2:0]               slv_awprot   [0:14];
    wire [3:0]               slv_awqos    [0:14];
    wire [3:0]               slv_awregion [0:14];
    wire [AWUSER_WIDTH-1:0]  slv_awuser   [0:14];
    wire                     slv_awvalid  [0:14];
    logic                    slv_awready  [0:14];

    wire [DATA_WIDTH-1:0]    slv_wdata    [0:14];
    wire [STRB_WIDTH-1:0]    slv_wstrb    [0:14];
    wire                     slv_wlast    [0:14];
    wire [WUSER_WIDTH-1:0]   slv_wuser    [0:14];
    wire                     slv_wvalid   [0:14];
    logic                    slv_wready   [0:14];

    logic [ID_WIDTH-1:0]     slv_bid      [0:14];
    logic [1:0]              slv_bresp    [0:14];
    logic [BUSER_WIDTH-1:0]  slv_buser    [0:14];
    logic                    slv_bvalid   [0:14];
    wire                     slv_bready   [0:14];

    wire [ID_WIDTH-1:0]      slv_arid     [0:14];
    wire [ADDR_WIDTH-1:0]    slv_araddr   [0:14];
    wire [7:0]               slv_arlen    [0:14];
    wire [2:0]               slv_arsize   [0:14];
    wire [1:0]               slv_arburst  [0:14];
    wire                     slv_arlock   [0:14];
    wire [3:0]               slv_arcache  [0:14];
    wire [2:0]               slv_arprot   [0:14];
    wire [3:0]               slv_arqos    [0:14];
    wire [3:0]               slv_arregion [0:14];
    wire [ARUSER_WIDTH-1:0]  slv_aruser   [0:14];
    wire                     slv_arvalid  [0:14];
    logic                    slv_arready  [0:14];

    logic [ID_WIDTH-1:0]     slv_rid      [0:14];
    logic [DATA_WIDTH-1:0]   slv_rdata    [0:14];
    logic [1:0]              slv_rresp    [0:14];
    logic                    slv_rlast    [0:14];
    logic [RUSER_WIDTH-1:0]  slv_ruser    [0:14];
    logic                    slv_rvalid   [0:14];
    wire                     slv_rready   [0:14];

    // Dummy responder loop for S0, S1, S5, S6, S7, S11, S12, S13, S14
    genvar g;
    generate
        for (g = 0; g < 15; g = g + 1) begin : GEN_DUMMY_SLAVES
            if (g == 0 || g == 1 || (g >= 5 && g <= 7) || (g >= 11 && g <= 14)) begin : EXT_SLAVE
                always_ff @(posedge clk or posedge rst) begin
                    if (rst) begin
                        slv_awready[g] <= 1'b0;
                        slv_wready[g]  <= 1'b0;
                        slv_bvalid[g]  <= 1'b0;
                        slv_bresp[g]   <= 2'b00;
                        slv_bid[g]     <= '0;
                        slv_arready[g] <= 1'b0;
                        slv_rvalid[g]  <= 1'b0;
                        slv_rresp[g]   <= 2'b00;
                        slv_rdata[g]   <= '0;
                        slv_rid[g]     <= '0;
                        slv_rlast[g]   <= 1'b0;
                    end else begin
                        slv_awready[g] <= 1'b1;
                        slv_wready[g]  <= 1'b1;
                        slv_arready[g] <= 1'b1;
                        if (slv_awvalid[g] && slv_wvalid[g] && !slv_bvalid[g]) begin
                            slv_bvalid[g] <= 1'b1;
                            slv_bid[g]    <= slv_awid[g];
                            slv_bresp[g]  <= 2'b00;
                        end else if (slv_bready[g]) begin
                            slv_bvalid[g] <= 1'b0;
                        end

                        if (slv_arvalid[g] && !slv_rvalid[g]) begin
                            slv_rvalid[g] <= 1'b1;
                            slv_rid[g]    <= slv_arid[g];
                            slv_rresp[g]  <= 2'b00;
                            slv_rdata[g]  <= 32'hA5A5_0000 | g;
                            slv_rlast[g]  <= 1'b1;
                        end else if (slv_rready[g]) begin
                            slv_rvalid[g] <= 1'b0;
                            slv_rlast[g]  <= 1'b0;
                        end
                    end
                end
            end else begin : INT_SLAVE_TIE
                always_comb begin
                    slv_awready[g] = 1'b0;
                    slv_wready[g]  = 1'b0;
                    slv_bvalid[g]  = 1'b0;
                    slv_bid[g]     = '0;
                    slv_bresp[g]   = 2'b00;
                    slv_buser[g]   = '0;
                    slv_arready[g] = 1'b0;
                    slv_rvalid[g]  = 1'b0;
                    slv_rid[g]     = '0;
                    slv_rdata[g]   = '0;
                    slv_rresp[g]   = 2'b00;
                    slv_rlast[g]   = 1'b0;
                    slv_ruser[g]   = '0;
                end
            end
        end
    endgenerate

    // Peripheral IO wires
    wire        PWM_OUT_tb;
    wire [31:0] gpio_io_tb;
    wire        gpio_intr_tb;
    logic       timer_ext_meas_tb;
    logic       timer_capture_tb;
    wire        timer_pwm_tb;
    wire        timer_trigger_tb;
    wire        timer_intr_tb;

    logic       enc_a_tb;
    logic       enc_b_tb;
    logic       enc_index_tb;
    logic       enc_drive_active_tb;
    wire [15:0] enc_speed_tb;
    wire        enc_speed_valid_tb;
    wire        enc_count_valid_tb;
    wire        enc_dir_tb;
    wire        enc_fault_tb;
    wire        enc_intr_tb;

    wire [15:0] pid_out_tb;
    wire        pid_out_valid_tb;
    wire        pid_sat_flag_tb;
    wire        pid_intr_tb;

    logic       uart_rx_tb;
    wire        uart_tx_tb;
    wire        uart_irq_tb;

    // ============================================================
    // 3. BEHAVIORAL MOTOR PLANT MODEL
    // ============================================================
    // Integrates PWM_OUT to derive angular position and produces
    // quadrature pulses (enc_a, enc_b) in real-time.
    reg [23:0] motor_pos_accum;
    reg [1:0]  quad_phase;
    reg [15:0] sim_motor_speed; // in arbitrary pulse units
    reg        plant_enable;
    reg        plant_reverse;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            motor_pos_accum <= 24'd0;
            quad_phase      <= 2'b00;
            sim_motor_speed <= 16'd0;
            enc_a_tb        <= 1'b0;
            enc_b_tb        <= 1'b0;
            enc_index_tb    <= 1'b0;
        end else if (plant_enable) begin
            // Motor velocity low-pass filter tracking PWM_OUT
            // When PWM_OUT is high, motor accelerates toward 16'h0200
            // When PWM_OUT is low, friction decelerates motor toward 0
            if (PWM_OUT_tb) begin
                if (sim_motor_speed < 16'd400)
                    sim_motor_speed <= sim_motor_speed + 16'd4;
            end else begin
                if (sim_motor_speed > 16'd2)
                    sim_motor_speed <= sim_motor_speed - 16'd2;
                else
                    sim_motor_speed <= 16'd0;
            end

            // Accumulate angular position
            motor_pos_accum <= motor_pos_accum + {8'h00, sim_motor_speed};

            // Quadrature phase generator (Gray code sequence)
            quad_phase <= motor_pos_accum[14:13];
            if (!plant_reverse) begin
                case (quad_phase)
                    2'b00: begin enc_a_tb <= 1'b0; enc_b_tb <= 1'b0; end
                    2'b01: begin enc_a_tb <= 1'b0; enc_b_tb <= 1'b1; end
                    2'b10: begin enc_a_tb <= 1'b1; enc_b_tb <= 1'b1; end
                    2'b11: begin enc_a_tb <= 1'b1; enc_b_tb <= 1'b0; end
                endcase
            end else begin
                // Reverse direction Gray code
                case (quad_phase)
                    2'b00: begin enc_a_tb <= 1'b0; enc_b_tb <= 1'b0; end
                    2'b01: begin enc_a_tb <= 1'b1; enc_b_tb <= 1'b0; end
                    2'b10: begin enc_a_tb <= 1'b1; enc_b_tb <= 1'b1; end
                    2'b11: begin enc_a_tb <= 1'b0; enc_b_tb <= 1'b1; end
                endcase
            end

            // Periodic index pulse every 64k accumulator steps
            enc_index_tb <= (motor_pos_accum[15:0] < 16'd10);
        end else begin
            // Plant disabled
            sim_motor_speed <= 16'd0;
            enc_a_tb        <= 1'b0;
            enc_b_tb        <= 1'b0;
            enc_index_tb    <= 1'b0;
        end
    end

    // ============================================================
    // 4. DUT INSTANTIATION (main_top)
    // ============================================================
    main_top #(
        .DATA_WIDTH      (DATA_WIDTH),
        .ADDR_WIDTH      (ADDR_WIDTH),
        .STRB_WIDTH      (STRB_WIDTH),
        .ID_WIDTH        (ID_WIDTH)
    ) dut (
        .clk             (clk),
        .fixed_clk       (fixed_clk),
        .rst             (rst),

        .uart_rx         (uart_rx_tb),
        .uart_tx         (uart_tx_tb),
        .uart_irq        (uart_irq_tb),

        .PWM_OUT         (PWM_OUT_tb),

        .gpio_io         (gpio_io_tb),
        .gpio_intr       (gpio_intr_tb),

        .timer_ext_meas  (timer_ext_meas_tb),
        .timer_capture   (timer_capture_tb),
        .timer_pwm       (timer_pwm_tb),
        .timer_trigger   (timer_trigger_tb),
        .timer_intr      (timer_intr_tb),

        .enc_a           (enc_a_tb),
        .enc_b           (enc_b_tb),
        .enc_index       (enc_index_tb),
        .enc_drive_active(enc_drive_active_tb),
        .enc_speed       (enc_speed_tb),
        .enc_speed_valid (enc_speed_valid_tb),
        .enc_count_valid (enc_count_valid_tb),
        .enc_dir         (enc_dir_tb),
        .enc_fault       (enc_fault_tb),
        .enc_intr        (enc_intr_tb),

        .pid_out         (pid_out_tb),
        .pid_out_valid   (pid_out_valid_tb),
        .pid_sat_flag    (pid_sat_flag_tb),
        .pid_intr        (pid_intr_tb),

        // M0 tied off
        .s00_axi_awid    (m0_awid),
        .s00_axi_awaddr  (m0_awaddr),
        .s00_axi_awlen   (m0_awlen),
        .s00_axi_awsize  (m0_awsize),
        .s00_axi_awburst (m0_awburst),
        .s00_axi_awlock  (m0_awlock),
        .s00_axi_awcache (m0_awcache),
        .s00_axi_awprot  (m0_awprot),
        .s00_axi_awqos   (m0_awqos),
        .s00_axi_awuser  (m0_awuser),
        .s00_axi_awvalid (m0_awvalid),
        .s00_axi_awready (m0_awready),
        .s00_axi_wdata   (m0_wdata),
        .s00_axi_wstrb   (m0_wstrb),
        .s00_axi_wlast   (m0_wlast),
        .s00_axi_wuser   (m0_wuser),
        .s00_axi_wvalid  (m0_wvalid),
        .s00_axi_wready  (m0_wready),
        .s00_axi_bid     (m0_bid),
        .s00_axi_bresp   (m0_bresp),
        .s00_axi_buser   (m0_buser),
        .s00_axi_bvalid  (m0_bvalid),
        .s00_axi_bready  (m0_bready),
        .s00_axi_arid    (m0_arid),
        .s00_axi_araddr  (m0_araddr),
        .s00_axi_arlen   (m0_arlen),
        .s00_axi_arsize  (m0_arsize),
        .s00_axi_arburst (m0_arburst),
        .s00_axi_arlock  (m0_arlock),
        .s00_axi_arcache (m0_arcache),
        .s00_axi_arprot  (m0_arprot),
        .s00_axi_arqos   (m0_arqos),
        .s00_axi_aruser  (m0_aruser),
        .s00_axi_arvalid (m0_arvalid),
        .s00_axi_arready (m0_arready),
        .s00_axi_rid     (m0_rid),
        .s00_axi_rdata   (m0_rdata),
        .s00_axi_rresp   (m0_rresp),
        .s00_axi_rlast   (m0_rlast),
        .s00_axi_ruser   (m0_ruser),
        .s00_axi_rvalid  (m0_rvalid),
        .s00_axi_rready  (m0_rready),

        // M1 Active
        .s01_axi_awid    (m1_awid),
        .s01_axi_awaddr  (m1_awaddr),
        .s01_axi_awlen   (m1_awlen),
        .s01_axi_awsize  (m1_awsize),
        .s01_axi_awburst (m1_awburst),
        .s01_axi_awlock  (m1_awlock),
        .s01_axi_awcache (m1_awcache),
        .s01_axi_awprot  (m1_awprot),
        .s01_axi_awqos   (m1_awqos),
        .s01_axi_awuser  (m1_awuser),
        .s01_axi_awvalid (m1_awvalid),
        .s01_axi_awready (m1_awready),
        .s01_axi_wdata   (m1_wdata),
        .s01_axi_wstrb   (m1_wstrb),
        .s01_axi_wlast   (m1_wlast),
        .s01_axi_wuser   (m1_wuser),
        .s01_axi_wvalid  (m1_wvalid),
        .s01_axi_wready  (m1_wready),
        .s01_axi_bid     (m1_bid),
        .s01_axi_bresp   (m1_bresp),
        .s01_axi_buser   (m1_buser),
        .s01_axi_bvalid  (m1_bvalid),
        .s01_axi_bready  (m1_bready),
        .s01_axi_arid    (m1_arid),
        .s01_axi_araddr  (m1_araddr),
        .s01_axi_arlen   (m1_arlen),
        .s01_axi_arsize  (m1_arsize),
        .s01_axi_arburst (m1_arburst),
        .s01_axi_arlock  (m1_arlock),
        .s01_axi_arcache (m1_arcache),
        .s01_axi_arprot  (m1_arprot),
        .s01_axi_arqos   (m1_arqos),
        .s01_axi_aruser  (m1_aruser),
        .s01_axi_arvalid (m1_arvalid),
        .s01_axi_arready (m1_arready),
        .s01_axi_rid     (m1_rid),
        .s01_axi_rdata   (m1_rdata),
        .s01_axi_rresp   (m1_rresp),
        .s01_axi_rlast   (m1_rlast),
        .s01_axi_ruser   (m1_ruser),
        .s01_axi_rvalid  (m1_rvalid),
        .s01_axi_rready  (m1_rready),

        // M2 tied off
        .s02_axi_awid    (m2_awid),
        .s02_axi_awaddr  (m2_awaddr),
        .s02_axi_awlen   (m2_awlen),
        .s02_axi_awsize  (m2_awsize),
        .s02_axi_awburst (m2_awburst),
        .s02_axi_awlock  (m2_awlock),
        .s02_axi_awcache (m2_awcache),
        .s02_axi_awprot  (m2_awprot),
        .s02_axi_awqos   (m2_awqos),
        .s02_axi_awuser  (m2_awuser),
        .s02_axi_awvalid (m2_awvalid),
        .s02_axi_awready (m2_awready),
        .s02_axi_wdata   (m2_wdata),
        .s02_axi_wstrb   (m2_wstrb),
        .s02_axi_wlast   (m2_wlast),
        .s02_axi_wuser   (m2_wuser),
        .s02_axi_wvalid  (m2_wvalid),
        .s02_axi_wready  (m2_wready),
        .s02_axi_bid     (m2_bid),
        .s02_axi_bresp   (m2_bresp),
        .s02_axi_buser   (m2_buser),
        .s02_axi_bvalid  (m2_bvalid),
        .s02_axi_bready  (m2_bready),
        .s02_axi_arid    (m2_arid),
        .s02_axi_araddr  (m2_araddr),
        .s02_axi_arlen   (m2_arlen),
        .s02_axi_arsize  (m2_arsize),
        .s02_axi_arburst (m2_arburst),
        .s02_axi_arlock  (m2_arlock),
        .s02_axi_arcache (m2_arcache),
        .s02_axi_arprot  (m2_arprot),
        .s02_axi_arqos   (m2_arqos),
        .s02_axi_aruser  (m2_aruser),
        .s02_axi_arvalid (m2_arvalid),
        .s02_axi_arready (m2_arready),
        .s02_axi_rid     (m2_rid),
        .s02_axi_rdata   (m2_rdata),
        .s02_axi_rresp   (m2_rresp),
        .s02_axi_rlast   (m2_rlast),
        .s02_axi_ruser   (m2_ruser),
        .s02_axi_rvalid  (m2_rvalid),
        .s02_axi_rready  (m2_rready),

        // Slaves connected to responders
        .m00_axi_awid(slv_awid[0]), .m00_axi_awaddr(slv_awaddr[0]), .m00_axi_awlen(slv_awlen[0]),
        .m00_axi_awsize(slv_awsize[0]), .m00_axi_awburst(slv_awburst[0]), .m00_axi_awlock(slv_awlock[0]),
        .m00_axi_awcache(slv_awcache[0]), .m00_axi_awprot(slv_awprot[0]), .m00_axi_awqos(slv_awqos[0]),
        .m00_axi_awregion(slv_awregion[0]), .m00_axi_awuser(slv_awuser[0]), .m00_axi_awvalid(slv_awvalid[0]),
        .m00_axi_awready(slv_awready[0]), .m00_axi_wdata(slv_wdata[0]), .m00_axi_wstrb(slv_wstrb[0]),
        .m00_axi_wlast(slv_wlast[0]), .m00_axi_wuser(slv_wuser[0]), .m00_axi_wvalid(slv_wvalid[0]),
        .m00_axi_wready(slv_wready[0]), .m00_axi_bid(slv_bid[0]), .m00_axi_bresp(slv_bresp[0]),
        .m00_axi_buser(slv_buser[0]), .m00_axi_bvalid(slv_bvalid[0]), .m00_axi_bready(slv_bready[0]),
        .m00_axi_arid(slv_arid[0]), .m00_axi_araddr(slv_araddr[0]), .m00_axi_arlen(slv_arlen[0]),
        .m00_axi_arsize(slv_arsize[0]), .m00_axi_arburst(slv_arburst[0]), .m00_axi_arlock(slv_arlock[0]),
        .m00_axi_arcache(slv_arcache[0]), .m00_axi_arprot(slv_arprot[0]), .m00_axi_arqos(slv_arqos[0]),
        .m00_axi_arregion(slv_arregion[0]), .m00_axi_aruser(slv_aruser[0]), .m00_axi_arvalid(slv_arvalid[0]),
        .m00_axi_arready(slv_arready[0]), .m00_axi_rid(slv_rid[0]), .m00_axi_rdata(slv_rdata[0]),
        .m00_axi_rresp(slv_rresp[0]), .m00_axi_rlast(slv_rlast[0]), .m00_axi_ruser(slv_ruser[0]),
        .m00_axi_rvalid(slv_rvalid[0]), .m00_axi_rready(slv_rready[0]),

        .m01_axi_awid(slv_awid[1]), .m01_axi_awaddr(slv_awaddr[1]), .m01_axi_awlen(slv_awlen[1]),
        .m01_axi_awsize(slv_awsize[1]), .m01_axi_awburst(slv_awburst[1]), .m01_axi_awlock(slv_awlock[1]),
        .m01_axi_awcache(slv_awcache[1]), .m01_axi_awprot(slv_awprot[1]), .m01_axi_awqos(slv_awqos[1]),
        .m01_axi_awregion(slv_awregion[1]), .m01_axi_awuser(slv_awuser[1]), .m01_axi_awvalid(slv_awvalid[1]),
        .m01_axi_awready(slv_awready[1]), .m01_axi_wdata(slv_wdata[1]), .m01_axi_wstrb(slv_wstrb[1]),
        .m01_axi_wlast(slv_wlast[1]), .m01_axi_wuser(slv_wuser[1]), .m01_axi_wvalid(slv_wvalid[1]),
        .m01_axi_wready(slv_wready[1]), .m01_axi_bid(slv_bid[1]), .m01_axi_bresp(slv_bresp[1]),
        .m01_axi_buser(slv_buser[1]), .m01_axi_bvalid(slv_bvalid[1]), .m01_axi_bready(slv_bready[1]),
        .m01_axi_arid(slv_arid[1]), .m01_axi_araddr(slv_araddr[1]), .m01_axi_arlen(slv_arlen[1]),
        .m01_axi_arsize(slv_arsize[1]), .m01_axi_arburst(slv_arburst[1]), .m01_axi_arlock(slv_arlock[1]),
        .m01_axi_arcache(slv_arcache[1]), .m01_axi_arprot(slv_arprot[1]), .m01_axi_arqos(slv_arqos[1]),
        .m01_axi_arregion(slv_arregion[1]), .m01_axi_aruser(slv_aruser[1]), .m01_axi_arvalid(slv_arvalid[1]),
        .m01_axi_arready(slv_arready[1]), .m01_axi_rid(slv_rid[1]), .m01_axi_rdata(slv_rdata[1]),
        .m01_axi_rresp(slv_rresp[1]), .m01_axi_rlast(slv_rlast[1]), .m01_axi_ruser(slv_ruser[1]),
        .m01_axi_rvalid(slv_rvalid[1]), .m01_axi_rready(slv_rready[1]),

        .m05_axi_awid(slv_awid[5]), .m05_axi_awaddr(slv_awaddr[5]), .m05_axi_awlen(slv_awlen[5]),
        .m05_axi_awsize(slv_awsize[5]), .m05_axi_awburst(slv_awburst[5]), .m05_axi_awlock(slv_awlock[5]),
        .m05_axi_awcache(slv_awcache[5]), .m05_axi_awprot(slv_awprot[5]), .m05_axi_awqos(slv_awqos[5]),
        .m05_axi_awregion(slv_awregion[5]), .m05_axi_awuser(slv_awuser[5]), .m05_axi_awvalid(slv_awvalid[5]),
        .m05_axi_awready(slv_awready[5]), .m05_axi_wdata(slv_wdata[5]), .m05_axi_wstrb(slv_wstrb[5]),
        .m05_axi_wlast(slv_wlast[5]), .m05_axi_wuser(slv_wuser[5]), .m05_axi_wvalid(slv_wvalid[5]),
        .m05_axi_wready(slv_wready[5]), .m05_axi_bid(slv_bid[5]), .m05_axi_bresp(slv_bresp[5]),
        .m05_axi_buser(slv_buser[5]), .m05_axi_bvalid(slv_bvalid[5]), .m05_axi_bready(slv_bready[5]),
        .m05_axi_arid(slv_arid[5]), .m05_axi_araddr(slv_araddr[5]), .m05_axi_arlen(slv_arlen[5]),
        .m05_axi_arsize(slv_arsize[5]), .m05_axi_arburst(slv_arburst[5]), .m05_axi_arlock(slv_arlock[5]),
        .m05_axi_arcache(slv_arcache[5]), .m05_axi_arprot(slv_arprot[5]), .m05_axi_arqos(slv_arqos[5]),
        .m05_axi_arregion(slv_arregion[5]), .m05_axi_aruser(slv_aruser[5]), .m05_axi_arvalid(slv_arvalid[5]),
        .m05_axi_arready(slv_arready[5]), .m05_axi_rid(slv_rid[5]), .m05_axi_rdata(slv_rdata[5]),
        .m05_axi_rresp(slv_rresp[5]), .m05_axi_rlast(slv_rlast[5]), .m05_axi_ruser(slv_ruser[5]),
        .m05_axi_rvalid(slv_rvalid[5]), .m05_axi_rready(slv_rready[5]),

        .m06_axi_awid(slv_awid[6]), .m06_axi_awaddr(slv_awaddr[6]), .m06_axi_awlen(slv_awlen[6]),
        .m06_axi_awsize(slv_awsize[6]), .m06_axi_awburst(slv_awburst[6]), .m06_axi_awlock(slv_awlock[6]),
        .m06_axi_awcache(slv_awcache[6]), .m06_axi_awprot(slv_awprot[6]), .m06_axi_awqos(slv_awqos[6]),
        .m06_axi_awregion(slv_awregion[6]), .m06_axi_awuser(slv_awuser[6]), .m06_axi_awvalid(slv_awvalid[6]),
        .m06_axi_awready(slv_awready[6]), .m06_axi_wdata(slv_wdata[6]), .m06_axi_wstrb(slv_wstrb[6]),
        .m06_axi_wlast(slv_wlast[6]), .m06_axi_wuser(slv_wuser[6]), .m06_axi_wvalid(slv_wvalid[6]),
        .m06_axi_wready(slv_wready[6]), .m06_axi_bid(slv_bid[6]), .m06_axi_bresp(slv_bresp[6]),
        .m06_axi_buser(slv_buser[6]), .m06_axi_bvalid(slv_bvalid[6]), .m06_axi_bready(slv_bready[6]),
        .m06_axi_arid(slv_arid[6]), .m06_axi_araddr(slv_araddr[6]), .m06_axi_arlen(slv_arlen[6]),
        .m06_axi_arsize(slv_arsize[6]), .m06_axi_arburst(slv_arburst[6]), .m06_axi_arlock(slv_arlock[6]),
        .m06_axi_arcache(slv_arcache[6]), .m06_axi_arprot(slv_arprot[6]), .m06_axi_arqos(slv_arqos[6]),
        .m06_axi_arregion(slv_arregion[6]), .m06_axi_aruser(slv_aruser[6]), .m06_axi_arvalid(slv_arvalid[6]),
        .m06_axi_arready(slv_arready[6]), .m06_axi_rid(slv_rid[6]), .m06_axi_rdata(slv_rdata[6]),
        .m06_axi_rresp(slv_rresp[6]), .m06_axi_rlast(slv_rlast[6]), .m06_axi_ruser(slv_ruser[6]),
        .m06_axi_rvalid(slv_rvalid[6]), .m06_axi_rready(slv_rready[6]),

        .m07_axi_awid(slv_awid[7]), .m07_axi_awaddr(slv_awaddr[7]), .m07_axi_awlen(slv_awlen[7]),
        .m07_axi_awsize(slv_awsize[7]), .m07_axi_awburst(slv_awburst[7]), .m07_axi_awlock(slv_awlock[7]),
        .m07_axi_awcache(slv_awcache[7]), .m07_axi_awprot(slv_awprot[7]), .m07_axi_awqos(slv_awqos[7]),
        .m07_axi_awregion(slv_awregion[7]), .m07_axi_awuser(slv_awuser[7]), .m07_axi_awvalid(slv_awvalid[7]),
        .m07_axi_awready(slv_awready[7]), .m07_axi_wdata(slv_wdata[7]), .m07_axi_wstrb(slv_wstrb[7]),
        .m07_axi_wlast(slv_wlast[7]), .m07_axi_wuser(slv_wuser[7]), .m07_axi_wvalid(slv_wvalid[7]),
        .m07_axi_wready(slv_wready[7]), .m07_axi_bid(slv_bid[7]), .m07_axi_bresp(slv_bresp[7]),
        .m07_axi_buser(slv_buser[7]), .m07_axi_bvalid(slv_bvalid[7]), .m07_axi_bready(slv_bready[7]),
        .m07_axi_arid(slv_arid[7]), .m07_axi_araddr(slv_araddr[7]), .m07_axi_arlen(slv_arlen[7]),
        .m07_axi_arsize(slv_arsize[7]), .m07_axi_arburst(slv_arburst[7]), .m07_axi_arlock(slv_arlock[7]),
        .m07_axi_arcache(slv_arcache[7]), .m07_axi_arprot(slv_arprot[7]), .m07_axi_arqos(slv_arqos[7]),
        .m07_axi_arregion(slv_arregion[7]), .m07_axi_aruser(slv_aruser[7]), .m07_axi_arvalid(slv_arvalid[7]),
        .m07_axi_arready(slv_arready[7]), .m07_axi_rid(slv_rid[7]), .m07_axi_rdata(slv_rdata[7]),
        .m07_axi_rresp(slv_rresp[7]), .m07_axi_rlast(slv_rlast[7]), .m07_axi_ruser(slv_ruser[7]),
        .m07_axi_rvalid(slv_rvalid[7]), .m07_axi_rready(slv_rready[7]),

        .m11_axi_awid(slv_awid[11]), .m11_axi_awaddr(slv_awaddr[11]), .m11_axi_awlen(slv_awlen[11]),
        .m11_axi_awsize(slv_awsize[11]), .m11_axi_awburst(slv_awburst[11]), .m11_axi_awlock(slv_awlock[11]),
        .m11_axi_awcache(slv_awcache[11]), .m11_axi_awprot(slv_awprot[11]), .m11_axi_awqos(slv_awqos[11]),
        .m11_axi_awregion(slv_awregion[11]), .m11_axi_awuser(slv_awuser[11]), .m11_axi_awvalid(slv_awvalid[11]),
        .m11_axi_awready(slv_awready[11]), .m11_axi_wdata(slv_wdata[11]), .m11_axi_wstrb(slv_wstrb[11]),
        .m11_axi_wlast(slv_wlast[11]), .m11_axi_wuser(slv_wuser[11]), .m11_axi_wvalid(slv_wvalid[11]),
        .m11_axi_wready(slv_wready[11]), .m11_axi_bid(slv_bid[11]), .m11_axi_bresp(slv_bresp[11]),
        .m11_axi_buser(slv_buser[11]), .m11_axi_bvalid(slv_bvalid[11]), .m11_axi_bready(slv_bready[11]),
        .m11_axi_arid(slv_arid[11]), .m11_axi_araddr(slv_araddr[11]), .m11_axi_arlen(slv_arlen[11]),
        .m11_axi_arsize(slv_arsize[11]), .m11_axi_arburst(slv_arburst[11]), .m11_axi_arlock(slv_arlock[11]),
        .m11_axi_arcache(slv_arcache[11]), .m11_axi_arprot(slv_arprot[11]), .m11_axi_arqos(slv_arqos[11]),
        .m11_axi_arregion(slv_arregion[11]), .m11_axi_aruser(slv_aruser[11]), .m11_axi_arvalid(slv_arvalid[11]),
        .m11_axi_arready(slv_arready[11]), .m11_axi_rid(slv_rid[11]), .m11_axi_rdata(slv_rdata[11]),
        .m11_axi_rresp(slv_rresp[11]), .m11_axi_rlast(slv_rlast[11]), .m11_axi_ruser(slv_ruser[11]),
        .m11_axi_rvalid(slv_rvalid[11]), .m11_axi_rready(slv_rready[11]),

        .m12_axi_awid(slv_awid[12]), .m12_axi_awaddr(slv_awaddr[12]), .m12_axi_awlen(slv_awlen[12]),
        .m12_axi_awsize(slv_awsize[12]), .m12_axi_awburst(slv_awburst[12]), .m12_axi_awlock(slv_awlock[12]),
        .m12_axi_awcache(slv_awcache[12]), .m12_axi_awprot(slv_awprot[12]), .m12_axi_awqos(slv_awqos[12]),
        .m12_axi_awregion(slv_awregion[12]), .m12_axi_awuser(slv_awuser[12]), .m12_axi_awvalid(slv_awvalid[12]),
        .m12_axi_awready(slv_awready[12]), .m12_axi_wdata(slv_wdata[12]), .m12_axi_wstrb(slv_wstrb[12]),
        .m12_axi_wlast(slv_wlast[12]), .m12_axi_wuser(slv_wuser[12]), .m12_axi_wvalid(slv_wvalid[12]),
        .m12_axi_wready(slv_wready[12]), .m12_axi_bid(slv_bid[12]), .m12_axi_bresp(slv_bresp[12]),
        .m12_axi_buser(slv_buser[12]), .m12_axi_bvalid(slv_bvalid[12]), .m12_axi_bready(slv_bready[12]),
        .m12_axi_arid(slv_arid[12]), .m12_axi_araddr(slv_araddr[12]), .m12_axi_arlen(slv_arlen[12]),
        .m12_axi_arsize(slv_arsize[12]), .m12_axi_arburst(slv_arburst[12]), .m12_axi_arlock(slv_arlock[12]),
        .m12_axi_arcache(slv_arcache[12]), .m12_axi_arprot(slv_arprot[12]), .m12_axi_arqos(slv_arqos[12]),
        .m12_axi_arregion(slv_arregion[12]), .m12_axi_aruser(slv_aruser[12]), .m12_axi_arvalid(slv_arvalid[12]),
        .m12_axi_arready(slv_arready[12]), .m12_axi_rid(slv_rid[12]), .m12_axi_rdata(slv_rdata[12]),
        .m12_axi_rresp(slv_rresp[12]), .m12_axi_rlast(slv_rlast[12]), .m12_axi_ruser(slv_ruser[12]),
        .m12_axi_rvalid(slv_rvalid[12]), .m12_axi_rready(slv_rready[12]),

        .m13_axi_awid(slv_awid[13]), .m13_axi_awaddr(slv_awaddr[13]), .m13_axi_awlen(slv_awlen[13]),
        .m13_axi_awsize(slv_awsize[13]), .m13_axi_awburst(slv_awburst[13]), .m13_axi_awlock(slv_awlock[13]),
        .m13_axi_awcache(slv_awcache[13]), .m13_axi_awprot(slv_awprot[13]), .m13_axi_awqos(slv_awqos[13]),
        .m13_axi_awregion(slv_awregion[13]), .m13_axi_awuser(slv_awuser[13]), .m13_axi_awvalid(slv_awvalid[13]),
        .m13_axi_awready(slv_awready[13]), .m13_axi_wdata(slv_wdata[13]), .m13_axi_wstrb(slv_wstrb[13]),
        .m13_axi_wlast(slv_wlast[13]), .m13_axi_wuser(slv_wuser[13]), .m13_axi_wvalid(slv_wvalid[13]),
        .m13_axi_wready(slv_wready[13]), .m13_axi_bid(slv_bid[13]), .m13_axi_bresp(slv_bresp[13]),
        .m13_axi_buser(slv_buser[13]), .m13_axi_bvalid(slv_bvalid[13]), .m13_axi_bready(slv_bready[13]),
        .m13_axi_arid(slv_arid[13]), .m13_axi_araddr(slv_araddr[13]), .m13_axi_arlen(slv_arlen[13]),
        .m13_axi_arsize(slv_arsize[13]), .m13_axi_arburst(slv_arburst[13]), .m13_axi_arlock(slv_arlock[13]),
        .m13_axi_arcache(slv_arcache[13]), .m13_axi_arprot(slv_arprot[13]), .m13_axi_arqos(slv_arqos[13]),
        .m13_axi_arregion(slv_arregion[13]), .m13_axi_aruser(slv_aruser[13]), .m13_axi_arvalid(slv_arvalid[13]),
        .m13_axi_arready(slv_arready[13]), .m13_axi_rid(slv_rid[13]), .m13_axi_rdata(slv_rdata[13]),
        .m13_axi_rresp(slv_rresp[13]), .m13_axi_rlast(slv_rlast[13]), .m13_axi_ruser(slv_ruser[13]),
        .m13_axi_rvalid(slv_rvalid[13]), .m13_axi_rready(slv_rready[13]),

        .m14_axi_awid(slv_awid[14]), .m14_axi_awaddr(slv_awaddr[14]), .m14_axi_awlen(slv_awlen[14]),
        .m14_axi_awsize(slv_awsize[14]), .m14_axi_awburst(slv_awburst[14]), .m14_axi_awlock(slv_awlock[14]),
        .m14_axi_awcache(slv_awcache[14]), .m14_axi_awprot(slv_awprot[14]), .m14_axi_awqos(slv_awqos[14]),
        .m14_axi_awregion(slv_awregion[14]), .m14_axi_awuser(slv_awuser[14]), .m14_axi_awvalid(slv_awvalid[14]),
        .m14_axi_awready(slv_awready[14]), .m14_axi_wdata(slv_wdata[14]), .m14_axi_wstrb(slv_wstrb[14]),
        .m14_axi_wlast(slv_wlast[14]), .m14_axi_wuser(slv_wuser[14]), .m14_axi_wvalid(slv_wvalid[14]),
        .m14_axi_wready(slv_wready[14]), .m14_axi_bid(slv_bid[14]), .m14_axi_bresp(slv_bresp[14]),
        .m14_axi_buser(slv_buser[14]), .m14_axi_bvalid(slv_bvalid[14]), .m14_axi_bready(slv_bready[14]),
        .m14_axi_arid(slv_arid[14]), .m14_axi_araddr(slv_araddr[14]), .m14_axi_arlen(slv_arlen[14]),
        .m14_axi_arsize(slv_arsize[14]), .m14_axi_arburst(slv_arburst[14]), .m14_axi_arlock(slv_arlock[14]),
        .m14_axi_arcache(slv_arcache[14]), .m14_axi_arprot(slv_arprot[14]), .m14_axi_arqos(slv_arqos[14]),
        .m14_axi_arregion(slv_arregion[14]), .m14_axi_aruser(slv_aruser[14]), .m14_axi_arvalid(slv_arvalid[14]),
        .m14_axi_arready(slv_arready[14]), .m14_axi_rid(slv_rid[14]), .m14_axi_rdata(slv_rdata[14]),
        .m14_axi_rresp(slv_rresp[14]), .m14_axi_rlast(slv_rlast[14]), .m14_axi_ruser(slv_ruser[14]),
        .m14_axi_rvalid(slv_rvalid[14]), .m14_axi_rready(slv_rready[14])
    );

    // ============================================================
    // 5. SCOREBOARD & ASSERTION HELPERS
    // ============================================================
    integer total_tests  = 0;
    integer passed_tests = 0;
    integer failed_tests = 0;

    task automatic check_assert(
        input string test_name,
        input logic  condition,
        input string failure_msg = ""
    );
        total_tests++;
        if (condition) begin
            $display("[PASS] %s", test_name);
            passed_tests++;
        end else begin
            $display("--------------------------------------------------");
            $display("[FAIL] %s", test_name);
            if (failure_msg != "")
                $display("       Detail: %s", failure_msg);
            $display("--------------------------------------------------");
            failed_tests++;
        end
    endtask

    // ============================================================
    // 6. MASTER 1 AXI DRIVER TASKS
    // ============================================================
    task automatic init_m1();
        begin
            m1_awid    = '0; m1_awaddr  = '0; m1_awlen   = '0;
            m1_awsize  = 3'b010; m1_awburst = 2'b01; m1_awlock = 1'b0;
            m1_awcache = 4'b0000; m1_awprot = 3'b000; m1_awqos = 4'b0000;
            m1_awuser  = '0; m1_awvalid = 1'b0;
            m1_wdata   = '0; m1_wstrb   = 4'b0000; m1_wlast = 1'b0;
            m1_wuser   = '0; m1_wvalid  = 1'b0; m1_bready = 1'b0;
            m1_arid    = '0; m1_araddr  = '0; m1_arlen   = '0;
            m1_arsize  = 3'b010; m1_arburst = 2'b01; m1_arlock = 1'b0;
            m1_arcache = 4'b0000; m1_arprot = 3'b000; m1_arqos = 4'b0000;
            m1_aruser  = '0; m1_arvalid = 1'b0; m1_rready = 1'b0;

            m0_awvalid = 1'b0; m0_wvalid = 1'b0; m0_bready = 1'b0; m0_arvalid = 1'b0; m0_rready = 1'b0;
            m2_awvalid = 1'b0; m2_wvalid = 1'b0; m2_bready = 1'b0; m2_arvalid = 1'b0; m2_rready = 1'b0;

            uart_rx_tb = 1'b1;
            timer_ext_meas_tb = 1'b0;
            timer_capture_tb  = 1'b0;
            enc_drive_active_tb = 1'b1;
            plant_enable = 1'b0;
            plant_reverse = 1'b0;
        end
    endtask

    task automatic axi_write(
        input  logic [31:0] addr,
        input  logic [31:0] data,
        input  logic [7:0]  id,
        output logic [1:0]  resp
    );
        begin
            @(posedge clk);
            m1_awid    <= id;
            m1_awaddr  <= addr;
            m1_awlen   <= 8'h00;
            m1_awsize  <= 3'b010;
            m1_awburst <= 2'b01;
            m1_awvalid <= 1'b1;

            m1_wdata   <= data;
            m1_wstrb   <= 4'hF;
            m1_wlast   <= 1'b1;
            m1_wvalid  <= 1'b1;
            m1_bready  <= 1'b1;

            fork
                begin
                    @(posedge clk);
                    while (!m1_awready) @(posedge clk);
                    m1_awvalid <= 1'b0;
                end
                begin
                    @(posedge clk);
                    while (!m1_wready) @(posedge clk);
                    m1_wvalid <= 1'b0;
                    m1_wlast  <= 1'b0;
                end
            join

            while (!m1_bvalid) @(posedge clk);
            resp = m1_bresp;
            @(posedge clk);
            m1_bready <= 1'b0;
            @(posedge clk);
        end
    endtask

    task automatic axi_read(
        input  logic [31:0] addr,
        input  logic [7:0]  id,
        output logic [31:0] data,
        output logic [1:0]  resp
    );
        begin
            @(posedge clk);
            m1_arid    <= id;
            m1_araddr  <= addr;
            m1_arlen   <= 8'h00;
            m1_arsize  <= 3'b010;
            m1_arburst <= 2'b01;
            m1_arvalid <= 1'b1;
            m1_rready  <= 1'b1;

            @(posedge clk);
            while (!m1_arready) @(posedge clk);
            m1_arvalid <= 1'b0;

            while (!m1_rvalid) @(posedge clk);
            data = m1_rdata;
            resp = m1_rresp;
            @(posedge clk);
            m1_rready <= 1'b0;
            @(posedge clk);
        end
    endtask

    // ============================================================
    // 7. MAIN VERIFICATION SEQUENCE
    // ============================================================
    logic [31:0] rd_data;
    logic [1:0]  resp;
    integer tick_count;
    integer update_count;
    integer i;

    initial begin
        $display("\n================================================================================");
        $display("  STARTING PHASE 2 HARDWARE HYBRID CLOSED-LOOP FEEDBACK VERIFICATION           ");
        $display("================================================================================\n");

        init_m1();
        rst = 1'b1;
        repeat (20) @(posedge clk);
        rst = 1'b0;
        repeat (10) @(posedge clk);

        // ------------------------------------------------------------
        // TEST 1: SAFE POWER-ON RESET DEFAULTS
        // ------------------------------------------------------------
        $display("[TEST 1] Verifying Safe Power-On Reset State...");
        check_assert("Test1: PWM_OUT is inactive at reset", PWM_OUT_tb === 1'b0, $sformatf("Got PWM_OUT=%b", PWM_OUT_tb));
        check_assert("Test1: timer_trigger is inactive at reset", timer_trigger_tb === 1'b0, $sformatf("Got timer_trigger=%b", timer_trigger_tb));
        check_assert("Test1: pid_out is zero at reset", pid_out_tb === 16'h0000, $sformatf("Got pid_out=0x%04h", pid_out_tb));
        check_assert("Test1: pid_out_valid is deasserted at reset", pid_out_valid_tb === 1'b0, $sformatf("Got pid_out_valid=%b", pid_out_valid_tb));
        check_assert("Test1: enc_speed is zero at reset", enc_speed_tb === 16'h0000, $sformatf("Got enc_speed=0x%04h", enc_speed_tb));

        axi_read(PWM_REG0, 8'h01, rd_data, resp);
        check_assert("Test1: Read PWM_REG0 returns OKAY", resp === 2'b00, $sformatf("Got resp=%b", resp));
        check_assert("Test1: PWM duty register defaults to 0", rd_data[7:0] === 8'h00, $sformatf("Got duty=0x%02h", rd_data[7:0]));

        // ------------------------------------------------------------
        // TEST 2: CONFIGURE TIMER S3 AS AUTONOMOUS PERIODIC TICK GENERATOR
        // ------------------------------------------------------------
        $display("\n[TEST 2] Configuring Timer S3 periodic triggers...");
        // Set load value to 50 cycles
        axi_write(TIMER_LOAD, 32'd50, 8'h10, resp);
        check_assert("Test2: Write TIMER_LOAD completes OKAY", resp === 2'b00);

        // Enable periodic down-counting timer (mode=1, en=1 -> ctrl=3)
        axi_write(TIMER_CTRL, 32'h0000_0003, 8'h11, resp);
        check_assert("Test2: Write TIMER_CTRL completes OKAY", resp === 2'b00);

        // Observe multiple periodic trigger pulses
        tick_count = 0;
        for (i = 0; i < 300; i = i + 1) begin
            @(posedge clk);
            if (timer_trigger_tb)
                tick_count = tick_count + 1;
        end
        $display("[INFO] Observed %0d timer triggers in 300 cycles (expected ~5)", tick_count);
        check_assert("Test2: Timer generates periodic triggers (tick_count >= 4)", tick_count >= 4, $sformatf("Observed %0d ticks", tick_count));

        // ------------------------------------------------------------
        // TEST 3: CONFIGURE ENCODER S8
        // ------------------------------------------------------------
        $display("\n[TEST 3] Configuring Encoder S8...");
        axi_write(ENC_WINDOW, 32'd20, 8'h20, resp);
        check_assert("Test3: Write ENC_WINDOW (20 cycles) completes OKAY", resp === 2'b00);

        axi_write(ENC_SCALE, 32'h0001_0000, 8'h21, resp); // Scale = 1.0 (Q16.16)
        check_assert("Test3: Write ENC_SCALE (1.0 Q16.16) completes OKAY", resp === 2'b00);

        axi_write(ENC_CTRL, 32'h0000_0001, 8'h22, resp); // Enable
        check_assert("Test3: Write ENC_CTRL (Enable) completes OKAY", resp === 2'b00);

        // ------------------------------------------------------------
        // TEST 4: CONFIGURE PID S9 & VERIFY AUTONOMOUS CLOSED-LOOP UPDATE
        // ------------------------------------------------------------
        $display("\n[TEST 4] Configuring PID S9 and verifying autonomous loop execution...");
        axi_write(PID_SETPOINT, 32'h0000_0080, 8'h30, resp); // Setpoint = +128
        check_assert("Test4: Write PID_SETPOINT (+128) completes OKAY", resp === 2'b00);

        axi_write(PID_KP, 32'h0001_0000, 8'h31, resp); // Kp = 1.0 (Q16.16)
        check_assert("Test4: Write PID_KP (1.0 Q16.16) completes OKAY", resp === 2'b00);

        axi_write(PID_KI, 32'h0000_0000, 8'h32, resp); // Ki = 0
        axi_write(PID_KD, 32'h0000_0000, 8'h33, resp); // Kd = 0
        axi_write(PID_OUT_MAX, 32'h0000_00FF, 8'h34, resp); // Out Max = 255
        axi_write(PID_OUT_MIN, 32'h0000_0000, 8'h35, resp); // Out Min = 0

        // Enable PID controller
        axi_write(PID_CTRL, 32'h0000_0001, 8'h36, resp);
        check_assert("Test4: Write PID_CTRL (Enable) completes OKAY", resp === 2'b00);

        // Enable behavioral motor plant
        plant_enable = 1'b1;

        // Monitor autonomous PID calculation and autonomous PWM duty update
        update_count = 0;
        for (i = 0; i < 400; i = i + 1) begin
            @(posedge clk);
            if (pid_out_valid_tb) begin
                update_count = update_count + 1;
                $display("[HARDWARE EVENT] PID update #%0d: pid_out=0x%04h (%0d), sat_flag=%b",
                         update_count, pid_out_tb, $signed(pid_out_tb), pid_sat_flag_tb);
            end
        end

        check_assert("Test4: PID updates autonomously triggered by Timer (update_count >= 5)",
                     update_count >= 5, $sformatf("Observed %0d updates", update_count));

        // Read PWM duty cycle via AXI to verify autonomous hardware commit into slv_reg0
        axi_read(PWM_REG0, 8'h37, rd_data, resp);
        check_assert("Test4: AXI read PWM_REG0 returns OKAY", resp === 2'b00);
        $display("[INFO] Current PWM duty register via AXI: 0x%02h (%0d)", rd_data[7:0], rd_data[7:0]);
        check_assert("Test4: PWM duty register autonomously updated by PID (duty > 0)",
                     rd_data[7:0] > 8'h00, $sformatf("Duty is %0d", rd_data[7:0]));

        // Verify PWM_OUT is active and pulsing
        check_assert("Test4: Motor plant accelerated (sim_motor_speed > 0)",
                     sim_motor_speed > 16'd0, $sformatf("sim_motor_speed=%0d", sim_motor_speed));

        // ------------------------------------------------------------
        // TEST 5: CONCURRENT AXI ACCESS DURING ACTIVE CLOSED LOOP
        // ------------------------------------------------------------
        $display("\n[TEST 5] Concurrent AXI transactions during autonomous feedback loop...");
        // Read Timer current value
        axi_read(TIMER_VAL, 8'h40, rd_data, resp);
        check_assert("Test5: Read TIMER_VAL concurrent with loop returns OKAY", resp === 2'b00);

        // Read Encoder speed
        axi_read(ENC_SPEED, 8'h41, rd_data, resp);
        check_assert("Test5: Read ENC_SPEED concurrent with loop returns OKAY", resp === 2'b00);

        // Read PID actual speed
        axi_read(PID_ACTUAL, 8'h42, rd_data, resp);
        check_assert("Test5: Read PID_ACTUAL concurrent with loop returns OKAY", resp === 2'b00);

        // Read PID status
        axi_read(PID_STATUS, 8'h43, rd_data, resp);
        check_assert("Test5: Read PID_STATUS concurrent with loop returns OKAY", resp === 2'b00);

        // Write & read GPIO
        axi_write(GPIO_DATA_O, 32'h5A5A_A5A5, 8'h44, resp);
        check_assert("Test5: Write GPIO_DATA_O concurrent with loop returns OKAY", resp === 2'b00);
        axi_read(GPIO_DATA_O, 8'h45, rd_data, resp);
        check_assert("Test5: Read GPIO_DATA_O returns matching data", rd_data === 32'h5A5A_A5A5);

        // Read UART LSR
        axi_read(UART_LSR, 8'h46, rd_data, resp);
        check_assert("Test5: Read UART_LSR concurrent with loop returns OKAY", resp === 2'b00);

        // ------------------------------------------------------------
        // TEST 6: SATURATION LIMITING & HIGH SETPOINT CLAMP
        // ------------------------------------------------------------
        $display("\n[TEST 6] Saturation limiting with large positive setpoint...");
        // Temporarily stop motor plant to maximize positive error
        plant_enable = 1'b0;
        axi_write(PID_SETPOINT, 32'h0000_0500, 8'h50, resp); // Setpoint = 1280 (much larger than max 8-bit duty)
        check_assert("Test6: Write PID_SETPOINT (1280) completes OKAY", resp === 2'b00);

        // Wait for next PID update
        @(posedge pid_out_valid_tb);
        @(posedge clk);
        $display("[INFO] Saturated PID output: pid_out=0x%04h, sat_flag=%b", pid_out_tb, pid_sat_flag_tb);

        // Check PWM duty readback: must clamp at 0xFF
        axi_read(PWM_REG0, 8'h51, rd_data, resp);
        check_assert("Test6: Read PWM_REG0 returns OKAY", resp === 2'b00);
        check_assert("Test6: Hardware duty cycle clamped to 0xFF (255)",
                     rd_data[7:0] === 8'hFF, $sformatf("Got duty=0x%02h", rd_data[7:0]));

        // ------------------------------------------------------------
        // TEST 7: ZERO / NEGATIVE ERROR & LOW SETPOINT CLAMP
        // ------------------------------------------------------------
        $display("\n[TEST 7] Zero/Negative error with setpoint lower than speed...");
        // Set setpoint to 0
        axi_write(PID_SETPOINT, 32'h0000_0000, 8'h60, resp);
        check_assert("Test7: Write PID_SETPOINT (0) completes OKAY", resp === 2'b00);

        // Wait for next PID update
        @(posedge pid_out_valid_tb);
        @(posedge clk);
        $display("[INFO] Zero-setpoint PID output: pid_out=0x%04h", pid_out_tb);

        // Duty must clamp to 0x00
        axi_read(PWM_REG0, 8'h61, rd_data, resp);
        check_assert("Test7: Read PWM_REG0 returns OKAY", resp === 2'b00);
        check_assert("Test7: Hardware duty cycle clamped to 0x00",
                     rd_data[7:0] === 8'h00, $sformatf("Got duty=0x%02h", rd_data[7:0]));

        // ------------------------------------------------------------
        // TEST 8: PID CONTROLLER DISABLE TRANSITION
        // ------------------------------------------------------------
        $display("\n[TEST 8] Loop disable behavior...");
        // Write manual duty to PWM
        axi_write(PWM_REG0, 32'h0000_0077, 8'h70, resp);
        check_assert("Test8: Manual write to PWM_REG0 (0x77) completes OKAY", resp === 2'b00);

        // Disable PID controller
        axi_write(PID_CTRL, 32'h0000_0000, 8'h71, resp);
        check_assert("Test8: Disable PID_CTRL completes OKAY", resp === 2'b00);

        // Wait for several timer ticks and verify pid_out_valid remains 0
        update_count = 0;
        for (i = 0; i < 200; i = i + 1) begin
            @(posedge clk);
            if (pid_out_valid_tb)
                update_count = update_count + 1;
        end
        check_assert("Test8: No PID updates occur while PID is disabled",
                     update_count === 0, $sformatf("Observed %0d updates while disabled", update_count));

        // Verify PWM duty was not modified
        axi_read(PWM_REG0, 8'h72, rd_data, resp);
        check_assert("Test8: PWM duty maintained manual value (0x77)",
                     rd_data[7:0] === 8'h77, $sformatf("Got duty=0x%02h", rd_data[7:0]));

        // ------------------------------------------------------------
        // TEST 9: AXI CONCURRENT OVERRIDE PRECEDENCE
        // ------------------------------------------------------------
        $display("\n[TEST 9] AXI software write priority over hardware duty update...");
        // Re-enable PID with setpoint 50
        axi_write(PID_SETPOINT, 32'h0000_0050, 8'h80, resp);
        axi_write(PID_CTRL, 32'h0000_0001, 8'h81, resp);

        // Perform AXI write to PWM_REG0
        axi_write(PWM_REG0, 32'h0000_00AA, 8'h82, resp);
        check_assert("Test9: AXI write to PWM_REG0 returns OKAY", resp === 2'b00);
        axi_read(PWM_REG0, 8'h83, rd_data, resp);
        check_assert("Test9: PWM_REG0 accepted software value (0xAA)",
                     rd_data[7:0] === 8'hAA, $sformatf("Got duty=0x%02h", rd_data[7:0]));

        // ------------------------------------------------------------
        // TEST 10: RESET RECOVERY
        // ------------------------------------------------------------
        $display("\n[TEST 10] Dynamic reset recovery during active closed loop...");
        plant_enable = 1'b1;
        repeat (50) @(posedge clk);

        // Assert reset while active
        rst = 1'b1;
        repeat (15) @(posedge clk);
        check_assert("Test10: PWM_OUT is forced low during reset", PWM_OUT_tb === 1'b0);
        check_assert("Test10: timer_trigger is forced low during reset", timer_trigger_tb === 1'b0);
        check_assert("Test10: pid_out_valid is forced low during reset", pid_out_valid_tb === 1'b0);

        // Deassert reset
        rst = 1'b0;
        repeat (15) @(posedge clk);

        // Reconfigure and verify clean recovery
        axi_write(TIMER_LOAD, 32'd40, 8'h90, resp);
        axi_write(TIMER_CTRL, 32'h0000_0003, 8'h91, resp);
        axi_write(PID_SETPOINT, 32'h0000_0060, 8'h92, resp);
        axi_write(PID_KP, 32'h0001_0000, 8'h93, resp);
        axi_write(PID_CTRL, 32'h0000_0001, 8'h94, resp);

        // Wait for update
        update_count = 0;
        for (i = 0; i < 200; i = i + 1) begin
            @(posedge clk);
            if (pid_out_valid_tb)
                update_count = update_count + 1;
        end
        check_assert("Test10: Loop cleanly resumes autonomous execution after reset (update_count > 0)",
                     update_count > 0, $sformatf("Observed %0d updates after reset", update_count));

        // ------------------------------------------------------------
        // FINAL VERIFICATION SUMMARY SCOREBOARD
        // ------------------------------------------------------------
        repeat (50) @(posedge clk);
        $display("\n================================================================================");
        $display("             HYBRID FEEDBACK VERIFICATION SCOREBOARD SUMMARY                    ");
        $display("================================================================================");
        $display("  TOTAL CHECKS  : %0d", total_tests);
        $display("  PASSED CHECKS : %0d", passed_tests);
        $display("  FAILED CHECKS : %0d", failed_tests);
        $display("--------------------------------------------------------------------------------");
        if (failed_tests == 0) begin
            $display("  >>> STATUS: ALL HYBRID FEEDBACK TESTS PASSED SUCCESSFULLY! 100%% VERIFIED. <<<");
        end else begin
            $display("  >>> STATUS: VERIFICATION FAILED WITH %0d ERRORS! <<<", failed_tests);
        end
        $display("================================================================================\n");

        $finish;
    end

    // Safety simulation watchdog timer (1 ms)
    initial begin
        #1_000_000;
        $display("\n[FATAL ERROR] Simulation Watchdog Timeout reached in tb_hybrid_feedback!");
        $finish;
    end

endmodule

`default_nettype wire
