`timescale 1ns / 1ps
`default_nettype none

/*
================================================================================
 Project        : Fail-Safe Railway Level-Crossing Control System (Honours CBP)
 Module         : tb_main_top
 Description    : Exhaustive SystemVerilog Testbench for 3-Master x 15-Slave
                  AXI4 Interconnect with direct S4 UART (axi_uart_top) integration.
================================================================================
*/

module tb_main_top;

    // ============================================================
    // 1. PARAMETERS
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

    // Documented Base Addresses
    localparam logic [31:0] ADDR_S0_IMEM     = 32'h0004_0000;
    localparam logic [31:0] ADDR_S1_DMEM     = 32'h0008_0000;
    localparam logic [31:0] ADDR_S2_GPIO     = 32'h4003_1000;
    localparam logic [31:0] ADDR_S3_TIMER    = 32'h4003_3000;
    localparam logic [31:0] ADDR_S4_UART     = 32'h4003_5000;
    localparam logic [31:0] ADDR_S8_ENC      = 32'h4003_D000;
    localparam logic [31:0] ADDR_S9_PID      = 32'h4003_F000;
    localparam logic [31:0] ADDR_S10_PWM     = 32'h4004_1000;
    localparam logic [31:0] ADDR_S11_WDT     = 32'h8000_4000;
    localparam logic [31:0] ADDR_S12_ADC     = 32'h8000_5000;
    localparam logic [31:0] ADDR_S13_DMA     = 32'h8000_6000;
    localparam logic [31:0] ADDR_UNMAPPED    = 32'h9000_0000;
    localparam logic [31:0] ADDR_UNMAPPED_LO = 32'h0001_0000;

    // UART Offsets (Base: 0x4003_5000)
    localparam logic [31:0] UART_RBR_THR     = 32'h4003_5000;
    localparam logic [31:0] UART_IER         = 32'h4003_5004;
    localparam logic [31:0] UART_BAUD_DIV    = 32'h4003_5008; // when DLAB=1
    localparam logic [31:0] UART_LCR         = 32'h4003_500C; // bit 7 = DLAB
    localparam logic [31:0] UART_LSR         = 32'h4003_5014;

    // GPIO Offsets (Base: 0x4003_1000)
    localparam logic [31:0] GPIO_DATA_I      = 32'h4003_1000;
    localparam logic [31:0] GPIO_DATA_O      = 32'h4003_1004;
    localparam logic [31:0] GPIO_DIR         = 32'h4003_1008;
    localparam logic [31:0] GPIO_DEB_TH      = 32'h4003_102C;

    // Timer Offsets (Base: 0x4003_3000)
    localparam logic [31:0] TIMER_CTRL       = 32'h4003_3000;
    localparam logic [31:0] TIMER_LOAD       = 32'h4003_3004;
    localparam logic [31:0] TIMER_VAL        = 32'h4003_3008;
    localparam logic [31:0] TIMER_PRE        = 32'h4003_300C;
    localparam logic [31:0] TIMER_CMP        = 32'h4003_3018;

    // Encoder Offsets (Base: 0x4003_D000)
    localparam logic [31:0] ENC_COUNT        = 32'h4003_D000;
    localparam logic [31:0] ENC_SPEED        = 32'h4003_D004;
    localparam logic [31:0] ENC_CTRL         = 32'h4003_D008;
    localparam logic [31:0] ENC_WINDOW       = 32'h4003_D010;
    localparam logic [31:0] ENC_SCALE        = 32'h4003_D018;
    localparam logic [31:0] ENC_VERSION      = 32'h4003_D030;

    // PID Offsets (Base: 0x4003_F000)
    localparam logic [31:0] PID_SETPOINT     = 32'h4003_F000;
    localparam logic [31:0] PID_KP           = 32'h4003_F004;
    localparam logic [31:0] PID_KI           = 32'h4003_F008;
    localparam logic [31:0] PID_KD           = 32'h4003_F00C;
    localparam logic [31:0] PID_OUT          = 32'h4003_F010;
    localparam logic [31:0] PID_CTRL         = 32'h4003_F014;
    localparam logic [31:0] PID_VERSION      = 32'h4003_F034;

    // PWM Offsets (Base: 0x4004_1000)
    localparam logic [31:0] PWM_REG0         = 32'h4004_1000;
    localparam logic [31:0] PWM_REG1         = 32'h4004_1004;
    localparam logic [31:0] PWM_REG2         = 32'h4004_1008;
    localparam logic [31:0] PWM_REG3         = 32'h4004_100C;

    // UART Baud divisor for 115200 baud with fixed_clk = 40 MHz (25 ns period)
    // 40,000,000 / 115,200 = 347.22 -> 347
    localparam integer BAUD_DIV_115200       = 347;
    localparam integer TX_CYCLES_115200      = BAUD_DIV_115200 + 1; // 348 cycles
    localparam integer RX_CYCLES_115200      = BAUD_DIV_115200;     // 347 cycles

    // Fast simulation baud divisor
    localparam integer BAUD_DIV_FAST         = 32;
    localparam integer TX_CYCLES_FAST        = BAUD_DIV_FAST + 1;  // 33 cycles
    localparam integer RX_CYCLES_FAST        = BAUD_DIV_FAST;      // 32 cycles

    // ============================================================
    // 2. CLOCKS AND RESETS
    // ============================================================
    logic clk;
    logic fixed_clk;
    logic rst;

    // AXI system clock: 100 MHz (period = 10 ns)
    initial begin
        clk = 1'b0;
        forever #5.0 clk = ~clk;
    end

    // Dedicated UART baud clock: 40 MHz (period = 25 ns) with phase shift
    initial begin
        fixed_clk = 1'b0;
        #3.125;
        forever #12.5 fixed_clk = ~fixed_clk;
    end

    // UART External Pins
    logic uart_rx;
    wire  uart_tx;
    wire  uart_irq;

    // ============================================================
    // 3. MASTER INTERFACE SIGNALS (M0, M1, M2)
    // ============================================================
    // Master 0 (VeeR IFU)
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

    // Master 1 (VeeR LSU) - Primary Test Master
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

    // Master 2 (DMA Data Transfer Master)
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

    // ============================================================
    // 4. EXPOSED SLAVE INTERFACE SIGNALS (S0..S3, S5..S14)
    // S4 is internal to main_top.
    // ============================================================
    // Arrays for connecting to dummy slave responders
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

    // Dummy slave state registers
    logic                  dummy_aw_seen  [0:14];
    logic                  dummy_w_seen   [0:14];
    logic [ID_WIDTH-1:0]   dummy_awid_reg [0:14];
    logic [ADDR_WIDTH-1:0] dummy_addr_reg [0:14];
    logic [DATA_WIDTH-1:0] dummy_mem      [0:14][0:63]; // 64 words storage per slave

    // ============================================================
    // 5. DUT INSTANTIATION
    // ============================================================
    // S10 PWM observable wire
    wire PWM_OUT_tb;

    // S2 GPIO testbench wires
    wire [31:0] gpio_io_tb;
    wire        gpio_intr_tb;

    // S3 Timer testbench wires
    logic       timer_ext_meas_tb;
    logic       timer_capture_tb;
    wire        timer_pwm_tb;
    wire        timer_trigger_tb;
    wire        timer_intr_tb;

    // S8 Quadrature Encoder testbench wires
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

    // S9 PID Controller testbench wires
    logic       pid_tick_tb;
    logic [15:0] pid_actual_tb;
    wire [15:0]  pid_out_tb;
    wire         pid_out_valid_tb;
    wire         pid_sat_flag_tb;
    wire         pid_intr_tb;

    main_top #(
        .DATA_WIDTH      (DATA_WIDTH),
        .ADDR_WIDTH      (ADDR_WIDTH),
        .STRB_WIDTH      (STRB_WIDTH),
        .ID_WIDTH        (ID_WIDTH)
    ) dut (
        .clk             (clk),
        .fixed_clk       (fixed_clk),
        .rst             (rst),

        .uart_rx         (uart_rx),
        .uart_tx         (uart_tx),
        .uart_irq        (uart_irq),

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

        // Master 0 (VeeR IFU)
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

        // Master 1 (VeeR LSU)
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

        // Master 2 (DMA)
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

        // Slave S0: IMEM
        .m00_axi_awid    (slv_awid[0]),
        .m00_axi_awaddr  (slv_awaddr[0]),
        .m00_axi_awlen   (slv_awlen[0]),
        .m00_axi_awsize  (slv_awsize[0]),
        .m00_axi_awburst (slv_awburst[0]),
        .m00_axi_awlock  (slv_awlock[0]),
        .m00_axi_awcache (slv_awcache[0]),
        .m00_axi_awprot  (slv_awprot[0]),
        .m00_axi_awqos   (slv_awqos[0]),
        .m00_axi_awregion(slv_awregion[0]),
        .m00_axi_awuser  (slv_awuser[0]),
        .m00_axi_awvalid (slv_awvalid[0]),
        .m00_axi_awready (slv_awready[0]),
        .m00_axi_wdata   (slv_wdata[0]),
        .m00_axi_wstrb   (slv_wstrb[0]),
        .m00_axi_wlast   (slv_wlast[0]),
        .m00_axi_wuser   (slv_wuser[0]),
        .m00_axi_wvalid  (slv_wvalid[0]),
        .m00_axi_wready  (slv_wready[0]),
        .m00_axi_bid     (slv_bid[0]),
        .m00_axi_bresp   (slv_bresp[0]),
        .m00_axi_buser   (slv_buser[0]),
        .m00_axi_bvalid  (slv_bvalid[0]),
        .m00_axi_bready  (slv_bready[0]),
        .m00_axi_arid    (slv_arid[0]),
        .m00_axi_araddr  (slv_araddr[0]),
        .m00_axi_arlen   (slv_arlen[0]),
        .m00_axi_arsize  (slv_arsize[0]),
        .m00_axi_arburst (slv_arburst[0]),
        .m00_axi_arlock  (slv_arlock[0]),
        .m00_axi_arcache (slv_arcache[0]),
        .m00_axi_arprot  (slv_arprot[0]),
        .m00_axi_arqos   (slv_arqos[0]),
        .m00_axi_arregion(slv_arregion[0]),
        .m00_axi_aruser  (slv_aruser[0]),
        .m00_axi_arvalid (slv_arvalid[0]),
        .m00_axi_arready (slv_arready[0]),
        .m00_axi_rid     (slv_rid[0]),
        .m00_axi_rdata   (slv_rdata[0]),
        .m00_axi_rresp   (slv_rresp[0]),
        .m00_axi_rlast   (slv_rlast[0]),
        .m00_axi_ruser   (slv_ruser[0]),
        .m00_axi_rvalid  (slv_rvalid[0]),
        .m00_axi_rready  (slv_rready[0]),

        // Slave S1: DMEM
        .m01_axi_awid    (slv_awid[1]),
        .m01_axi_awaddr  (slv_awaddr[1]),
        .m01_axi_awlen   (slv_awlen[1]),
        .m01_axi_awsize  (slv_awsize[1]),
        .m01_axi_awburst (slv_awburst[1]),
        .m01_axi_awlock  (slv_awlock[1]),
        .m01_axi_awcache (slv_awcache[1]),
        .m01_axi_awprot  (slv_awprot[1]),
        .m01_axi_awqos   (slv_awqos[1]),
        .m01_axi_awregion(slv_awregion[1]),
        .m01_axi_awuser  (slv_awuser[1]),
        .m01_axi_awvalid (slv_awvalid[1]),
        .m01_axi_awready (slv_awready[1]),
        .m01_axi_wdata   (slv_wdata[1]),
        .m01_axi_wstrb   (slv_wstrb[1]),
        .m01_axi_wlast   (slv_wlast[1]),
        .m01_axi_wuser   (slv_wuser[1]),
        .m01_axi_wvalid  (slv_wvalid[1]),
        .m01_axi_wready  (slv_wready[1]),
        .m01_axi_bid     (slv_bid[1]),
        .m01_axi_bresp   (slv_bresp[1]),
        .m01_axi_buser   (slv_buser[1]),
        .m01_axi_bvalid  (slv_bvalid[1]),
        .m01_axi_bready  (slv_bready[1]),
        .m01_axi_arid    (slv_arid[1]),
        .m01_axi_araddr  (slv_araddr[1]),
        .m01_axi_arlen   (slv_arlen[1]),
        .m01_axi_arsize  (slv_arsize[1]),
        .m01_axi_arburst (slv_arburst[1]),
        .m01_axi_arlock  (slv_arlock[1]),
        .m01_axi_arcache (slv_arcache[1]),
        .m01_axi_arprot  (slv_arprot[1]),
        .m01_axi_arqos   (slv_arqos[1]),
        .m01_axi_arregion(slv_arregion[1]),
        .m01_axi_aruser  (slv_aruser[1]),
        .m01_axi_arvalid (slv_arvalid[1]),
        .m01_axi_arready (slv_arready[1]),
        .m01_axi_rid     (slv_rid[1]),
        .m01_axi_rdata   (slv_rdata[1]),
        .m01_axi_rresp   (slv_rresp[1]),
        .m01_axi_rlast   (slv_rlast[1]),
        .m01_axi_ruser   (slv_ruser[1]),
        .m01_axi_rvalid  (slv_rvalid[1]),
        .m01_axi_rready  (slv_rready[1]),

        // Slaves S5..S14
        .m05_axi_awid    (slv_awid[5]),   .m05_axi_awaddr  (slv_awaddr[5]),   .m05_axi_awlen   (slv_awlen[5]),   .m05_axi_awsize  (slv_awsize[5]),   .m05_axi_awburst (slv_awburst[5]),   .m05_axi_awlock  (slv_awlock[5]),   .m05_axi_awcache (slv_awcache[5]),   .m05_axi_awprot  (slv_awprot[5]),   .m05_axi_awqos   (slv_awqos[5]),   .m05_axi_awregion(slv_awregion[5]), .m05_axi_awuser  (slv_awuser[5]),   .m05_axi_awvalid (slv_awvalid[5]),   .m05_axi_awready (slv_awready[5]), .m05_axi_wdata   (slv_wdata[5]),   .m05_axi_wstrb   (slv_wstrb[5]),   .m05_axi_wlast   (slv_wlast[5]),   .m05_axi_wuser   (slv_wuser[5]),   .m05_axi_wvalid  (slv_wvalid[5]),   .m05_axi_wready  (slv_wready[5]),   .m05_axi_bid     (slv_bid[5]),     .m05_axi_bresp   (slv_bresp[5]),   .m05_axi_buser   (slv_buser[5]),   .m05_axi_bvalid  (slv_bvalid[5]),   .m05_axi_bready  (slv_bready[5]),   .m05_axi_arid    (slv_arid[5]),   .m05_axi_araddr  (slv_araddr[5]),   .m05_axi_arlen   (slv_arlen[5]),   .m05_axi_arsize  (slv_arsize[5]),   .m05_axi_arburst (slv_arburst[5]),   .m05_axi_arlock  (slv_arlock[5]),   .m05_axi_arcache (slv_arcache[5]),   .m05_axi_arprot  (slv_arprot[5]),   .m05_axi_arqos   (slv_arqos[5]),   .m05_axi_arregion(slv_arregion[5]), .m05_axi_aruser  (slv_aruser[5]),   .m05_axi_arvalid (slv_arvalid[5]),   .m05_axi_arready (slv_arready[5]), .m05_axi_rid     (slv_rid[5]),     .m05_axi_rdata   (slv_rdata[5]),   .m05_axi_rresp   (slv_rresp[5]),   .m05_axi_rlast   (slv_rlast[5]),   .m05_axi_ruser   (slv_ruser[5]),   .m05_axi_rvalid  (slv_rvalid[5]),   .m05_axi_rready  (slv_rready[5]),
        .m06_axi_awid    (slv_awid[6]),   .m06_axi_awaddr  (slv_awaddr[6]),   .m06_axi_awlen   (slv_awlen[6]),   .m06_axi_awsize  (slv_awsize[6]),   .m06_axi_awburst (slv_awburst[6]),   .m06_axi_awlock  (slv_awlock[6]),   .m06_axi_awcache (slv_awcache[6]),   .m06_axi_awprot  (slv_awprot[6]),   .m06_axi_awqos   (slv_awqos[6]),   .m06_axi_awregion(slv_awregion[6]), .m06_axi_awuser  (slv_awuser[6]),   .m06_axi_awvalid (slv_awvalid[6]),   .m06_axi_awready (slv_awready[6]), .m06_axi_wdata   (slv_wdata[6]),   .m06_axi_wstrb   (slv_wstrb[6]),   .m06_axi_wlast   (slv_wlast[6]),   .m06_axi_wuser   (slv_wuser[6]),   .m06_axi_wvalid  (slv_wvalid[6]),   .m06_axi_wready  (slv_wready[6]),   .m06_axi_bid     (slv_bid[6]),     .m06_axi_bresp   (slv_bresp[6]),   .m06_axi_buser   (slv_buser[6]),   .m06_axi_bvalid  (slv_bvalid[6]),   .m06_axi_bready  (slv_bready[6]),   .m06_axi_arid    (slv_arid[6]),   .m06_axi_araddr  (slv_araddr[6]),   .m06_axi_arlen   (slv_arlen[6]),   .m06_axi_arsize  (slv_arsize[6]),   .m06_axi_arburst (slv_arburst[6]),   .m06_axi_arlock  (slv_arlock[6]),   .m06_axi_arcache (slv_arcache[6]),   .m06_axi_arprot  (slv_arprot[6]),   .m06_axi_arqos   (slv_arqos[6]),   .m06_axi_arregion(slv_arregion[6]), .m06_axi_aruser  (slv_aruser[6]),   .m06_axi_arvalid (slv_arvalid[6]),   .m06_axi_arready (slv_arready[6]), .m06_axi_rid     (slv_rid[6]),     .m06_axi_rdata   (slv_rdata[6]),   .m06_axi_rresp   (slv_rresp[6]),   .m06_axi_rlast   (slv_rlast[6]),   .m06_axi_ruser   (slv_ruser[6]),   .m06_axi_rvalid  (slv_rvalid[6]),   .m06_axi_rready  (slv_rready[6]),
        .m07_axi_awid    (slv_awid[7]),   .m07_axi_awaddr  (slv_awaddr[7]),   .m07_axi_awlen   (slv_awlen[7]),   .m07_axi_awsize  (slv_awsize[7]),   .m07_axi_awburst (slv_awburst[7]),   .m07_axi_awlock  (slv_awlock[7]),   .m07_axi_awcache (slv_awcache[7]),   .m07_axi_awprot  (slv_awprot[7]),   .m07_axi_awqos   (slv_awqos[7]),   .m07_axi_awregion(slv_awregion[7]), .m07_axi_awuser  (slv_awuser[7]),   .m07_axi_awvalid (slv_awvalid[7]),   .m07_axi_awready (slv_awready[7]), .m07_axi_wdata   (slv_wdata[7]),   .m07_axi_wstrb   (slv_wstrb[7]),   .m07_axi_wlast   (slv_wlast[7]),   .m07_axi_wuser   (slv_wuser[7]),   .m07_axi_wvalid  (slv_wvalid[7]),   .m07_axi_wready  (slv_wready[7]),   .m07_axi_bid     (slv_bid[7]),     .m07_axi_bresp   (slv_bresp[7]),   .m07_axi_buser   (slv_buser[7]),   .m07_axi_bvalid  (slv_bvalid[7]),   .m07_axi_bready  (slv_bready[7]),   .m07_axi_arid    (slv_arid[7]),   .m07_axi_araddr  (slv_araddr[7]),   .m07_axi_arlen   (slv_arlen[7]),   .m07_axi_arsize  (slv_arsize[7]),   .m07_axi_arburst (slv_arburst[7]),   .m07_axi_arlock  (slv_arlock[7]),   .m07_axi_arcache (slv_arcache[7]),   .m07_axi_arprot  (slv_arprot[7]),   .m07_axi_arqos   (slv_arqos[7]),   .m07_axi_arregion(slv_arregion[7]), .m07_axi_aruser  (slv_aruser[7]),   .m07_axi_arvalid (slv_arvalid[7]),   .m07_axi_arready (slv_arready[7]), .m07_axi_rid     (slv_rid[7]),     .m07_axi_rdata   (slv_rdata[7]),   .m07_axi_rresp   (slv_rresp[7]),   .m07_axi_rlast   (slv_rlast[7]),   .m07_axi_ruser   (slv_ruser[7]),   .m07_axi_rvalid  (slv_rvalid[7]),   .m07_axi_rready  (slv_rready[7]),
        .m11_axi_awid    (slv_awid[11]),  .m11_axi_awaddr  (slv_awaddr[11]),  .m11_axi_awlen   (slv_awlen[11]),  .m11_axi_awsize  (slv_awsize[11]),  .m11_axi_awburst (slv_awburst[11]),  .m11_axi_awlock  (slv_awlock[11]),  .m11_axi_awcache (slv_awcache[11]),  .m11_axi_awprot  (slv_awprot[11]),  .m11_axi_awqos   (slv_awqos[11]),  .m11_axi_awregion(slv_awregion[11]),.m11_axi_awuser  (slv_awuser[11]),  .m11_axi_awvalid (slv_awvalid[11]),  .m11_axi_awready (slv_awready[11]),.m11_axi_wdata   (slv_wdata[11]),  .m11_axi_wstrb   (slv_wstrb[11]),  .m11_axi_wlast   (slv_wlast[11]),  .m11_axi_wuser   (slv_wuser[11]),  .m11_axi_wvalid  (slv_wvalid[11]),  .m11_axi_wready  (slv_wready[11]),  .m11_axi_bid     (slv_bid[11]),    .m11_axi_bresp   (slv_bresp[11]),  .m11_axi_buser   (slv_buser[11]),  .m11_axi_bvalid  (slv_bvalid[11]),  .m11_axi_bready  (slv_bready[11]),  .m11_axi_arid    (slv_arid[11]),  .m11_axi_araddr  (slv_araddr[11]),  .m11_axi_arlen   (slv_arlen[11]),  .m11_axi_arsize  (slv_arsize[11]),  .m11_axi_arburst (slv_arburst[11]),  .m11_axi_arlock  (slv_arlock[11]),  .m11_axi_arcache (slv_arcache[11]),  .m11_axi_arprot  (slv_arprot[11]),  .m11_axi_arqos   (slv_arqos[11]),  .m11_axi_arregion(slv_arregion[11]),.m11_axi_aruser  (slv_aruser[11]),  .m11_axi_arvalid (slv_arvalid[11]),  .m11_axi_arready (slv_arready[11]),.m11_axi_rid     (slv_rid[11]),    .m11_axi_rdata   (slv_rdata[11]),  .m11_axi_rresp   (slv_rresp[11]),  .m11_axi_rlast   (slv_rlast[11]),  .m11_axi_ruser   (slv_ruser[11]),  .m11_axi_rvalid  (slv_rvalid[11]),  .m11_axi_rready  (slv_rready[11]),
        .m12_axi_awid    (slv_awid[12]),  .m12_axi_awaddr  (slv_awaddr[12]),  .m12_axi_awlen   (slv_awlen[12]),  .m12_axi_awsize  (slv_awsize[12]),  .m12_axi_awburst (slv_awburst[12]),  .m12_axi_awlock  (slv_awlock[12]),  .m12_axi_awcache (slv_awcache[12]),  .m12_axi_awprot  (slv_awprot[12]),  .m12_axi_awqos   (slv_awqos[12]),  .m12_axi_awregion(slv_awregion[12]),.m12_axi_awuser  (slv_awuser[12]),  .m12_axi_awvalid (slv_awvalid[12]),  .m12_axi_awready (slv_awready[12]),.m12_axi_wdata   (slv_wdata[12]),  .m12_axi_wstrb   (slv_wstrb[12]),  .m12_axi_wlast   (slv_wlast[12]),  .m12_axi_wuser   (slv_wuser[12]),  .m12_axi_wvalid  (slv_wvalid[12]),  .m12_axi_wready  (slv_wready[12]),  .m12_axi_bid     (slv_bid[12]),    .m12_axi_bresp   (slv_bresp[12]),  .m12_axi_buser   (slv_buser[12]),  .m12_axi_bvalid  (slv_bvalid[12]),  .m12_axi_bready  (slv_bready[12]),  .m12_axi_arid    (slv_arid[12]),  .m12_axi_araddr  (slv_araddr[12]),  .m12_axi_arlen   (slv_arlen[12]),  .m12_axi_arsize  (slv_arsize[12]),  .m12_axi_arburst (slv_arburst[12]),  .m12_axi_arlock  (slv_arlock[12]),  .m12_axi_arcache (slv_arcache[12]),  .m12_axi_arprot  (slv_arprot[12]),  .m12_axi_arqos   (slv_arqos[12]),  .m12_axi_arregion(slv_arregion[12]),.m12_axi_aruser  (slv_aruser[12]),  .m12_axi_arvalid (slv_arvalid[12]),  .m12_axi_arready (slv_arready[12]),.m12_axi_rid     (slv_rid[12]),    .m12_axi_rdata   (slv_rdata[12]),  .m12_axi_rresp   (slv_rresp[12]),  .m12_axi_rlast   (slv_rlast[12]),  .m12_axi_ruser   (slv_ruser[12]),  .m12_axi_rvalid  (slv_rvalid[12]),  .m12_axi_rready  (slv_rready[12]),
        .m13_axi_awid    (slv_awid[13]),  .m13_axi_awaddr  (slv_awaddr[13]),  .m13_axi_awlen   (slv_awlen[13]),  .m13_axi_awsize  (slv_awsize[13]),  .m13_axi_awburst (slv_awburst[13]),  .m13_axi_awlock  (slv_awlock[13]),  .m13_axi_awcache (slv_awcache[13]),  .m13_axi_awprot  (slv_awprot[13]),  .m13_axi_awqos   (slv_awqos[13]),  .m13_axi_awregion(slv_awregion[13]),.m13_axi_awuser  (slv_awuser[13]),  .m13_axi_awvalid (slv_awvalid[13]),  .m13_axi_awready (slv_awready[13]),.m13_axi_wdata   (slv_wdata[13]),  .m13_axi_wstrb   (slv_wstrb[13]),  .m13_axi_wlast   (slv_wlast[13]),  .m13_axi_wuser   (slv_wuser[13]),  .m13_axi_wvalid  (slv_wvalid[13]),  .m13_axi_wready  (slv_wready[13]),  .m13_axi_bid     (slv_bid[13]),    .m13_axi_bresp   (slv_bresp[13]),  .m13_axi_buser   (slv_buser[13]),  .m13_axi_bvalid  (slv_bvalid[13]),  .m13_axi_bready  (slv_bready[13]),  .m13_axi_arid    (slv_arid[13]),  .m13_axi_araddr  (slv_araddr[13]),  .m13_axi_arlen   (slv_arlen[13]),  .m13_axi_arsize  (slv_arsize[13]),  .m13_axi_arburst (slv_arburst[13]),  .m13_axi_arlock  (slv_arlock[13]),  .m13_axi_arcache (slv_arcache[13]),  .m13_axi_arprot  (slv_arprot[13]),  .m13_axi_arqos   (slv_arqos[13]),  .m13_axi_arregion(slv_arregion[13]),.m13_axi_aruser  (slv_aruser[13]),  .m13_axi_arvalid (slv_arvalid[13]),  .m13_axi_arready (slv_arready[13]),.m13_axi_rid     (slv_rid[13]),    .m13_axi_rdata   (slv_rdata[13]),  .m13_axi_rresp   (slv_rresp[13]),  .m13_axi_rlast   (slv_rlast[13]),  .m13_axi_ruser   (slv_ruser[13]),  .m13_axi_rvalid  (slv_rvalid[13]),  .m13_axi_rready  (slv_rready[13]),
        .m14_axi_awid    (slv_awid[14]),  .m14_axi_awaddr  (slv_awaddr[14]),  .m14_axi_awlen   (slv_awlen[14]),  .m14_axi_awsize  (slv_awsize[14]),  .m14_axi_awburst (slv_awburst[14]),  .m14_axi_awlock  (slv_awlock[14]),  .m14_axi_awcache (slv_awcache[14]),  .m14_axi_awprot  (slv_awprot[14]),  .m14_axi_awqos   (slv_awqos[14]),  .m14_axi_awregion(slv_awregion[14]),.m14_axi_awuser  (slv_awuser[14]),  .m14_axi_awvalid (slv_awvalid[14]),  .m14_axi_awready (slv_awready[14]),.m14_axi_wdata   (slv_wdata[14]),  .m14_axi_wstrb   (slv_wstrb[14]),  .m14_axi_wlast   (slv_wlast[14]),  .m14_axi_wuser   (slv_wuser[14]),  .m14_axi_wvalid  (slv_wvalid[14]),  .m14_axi_wready  (slv_wready[14]),  .m14_axi_bid     (slv_bid[14]),    .m14_axi_bresp   (slv_bresp[14]),  .m14_axi_buser   (slv_buser[14]),  .m14_axi_bvalid  (slv_bvalid[14]),  .m14_axi_bready  (slv_bready[14]),  .m14_axi_arid    (slv_arid[14]),  .m14_axi_araddr  (slv_araddr[14]),  .m14_axi_arlen   (slv_arlen[14]),  .m14_axi_arsize  (slv_arsize[14]),  .m14_axi_arburst (slv_arburst[14]),  .m14_axi_arlock  (slv_arlock[14]),  .m14_axi_arcache (slv_arcache[14]),  .m14_axi_arprot  (slv_arprot[14]),  .m14_axi_arqos   (slv_arqos[14]),  .m14_axi_arregion(slv_arregion[14]),.m14_axi_aruser  (slv_aruser[14]),  .m14_axi_arvalid (slv_arvalid[14]),  .m14_axi_arready (slv_arready[14]),.m14_axi_rid     (slv_rid[14]),    .m14_axi_rdata   (slv_rdata[14]),  .m14_axi_rresp   (slv_rresp[14]),  .m14_axi_rlast   (slv_rlast[14]),  .m14_axi_ruser   (slv_ruser[14]),  .m14_axi_rvalid  (slv_rvalid[14]),  .m14_axi_rready  (slv_rready[14])
    );

    // ============================================================
    // 6. DUMMY SLAVE RESPONDERS FOR EXPOSED PORTS (g != 4)
    // ============================================================
    genvar g;
    generate
        for (g = 0; g < 15; g = g + 1) begin : GEN_DUMMY_SLAVES
            // Slaves S2 (GPIO), S3 (Timer), S4 (UART), S8 (Encoder), S9 (PID), S10 (PWM) are internal
            if (g != 2 && g != 3 && g != 4 && g != 8 && g != 9 && g != 10) begin : SLV_INST
                always_comb begin
                    slv_awready[g] = !dummy_aw_seen[g] && !slv_bvalid[g];
                    slv_wready[g]  = !dummy_w_seen[g]  && !slv_bvalid[g];
                    slv_arready[g] = !slv_rvalid[g];
                end

                always_ff @(posedge clk) begin
                    if (rst) begin
                        dummy_aw_seen[g]  <= 1'b0;
                        dummy_w_seen[g]   <= 1'b0;
                        dummy_awid_reg[g] <= '0;
                        dummy_addr_reg[g] <= '0;
                        slv_bvalid[g]     <= 1'b0;
                        slv_bid[g]        <= '0;
                        slv_bresp[g]      <= 2'b00;
                        slv_buser[g]      <= '0;

                        slv_rvalid[g]     <= 1'b0;
                        slv_rid[g]        <= '0;
                        slv_rdata[g]      <= '0;
                        slv_rresp[g]      <= 2'b00;
                        slv_rlast[g]      <= 1'b0;
                        slv_ruser[g]      <= '0;
                    end else begin
                        // Latch Write Address
                        if (slv_awvalid[g] && slv_awready[g]) begin
                            dummy_aw_seen[g]  <= 1'b1;
                            dummy_awid_reg[g] <= slv_awid[g];
                            dummy_addr_reg[g] <= slv_awaddr[g];
                        end

                        // Latch Write Data
                        if (slv_wvalid[g] && slv_wready[g]) begin
                            dummy_w_seen[g] <= 1'b1;
                            dummy_mem[g][slv_awaddr[g][7:2]] <= slv_wdata[g];
                        end

                        // Generate Write Response
                        if ((slv_awvalid[g] || dummy_aw_seen[g]) &&
                            (slv_wvalid[g]  || dummy_w_seen[g])  &&
                            !slv_bvalid[g]) begin
                            slv_bvalid[g] <= 1'b1;
                            slv_bid[g]    <= slv_awvalid[g] ? slv_awid[g] : dummy_awid_reg[g];
                            slv_bresp[g]  <= 2'b00; // OKAY
                        end

                        // Clear Write Response
                        if (slv_bvalid[g] && slv_bready[g]) begin
                            slv_bvalid[g]    <= 1'b0;
                            dummy_aw_seen[g] <= 1'b0;
                            dummy_w_seen[g]  <= 1'b0;
                        end

                        // Read Address & Read Response
                        if (slv_arvalid[g] && slv_arready[g]) begin
                            slv_rvalid[g] <= 1'b1;
                            slv_rid[g]    <= slv_arid[g];
                            slv_rdata[g]  <= {16'hCA00 | g, slv_araddr[g][15:0]}; // test signature
                            slv_rresp[g]  <= 2'b00; // OKAY
                            slv_rlast[g]  <= 1'b1;
                        end else if (slv_rvalid[g] && slv_rready[g]) begin
                            slv_rvalid[g] <= 1'b0;
                            slv_rlast[g]  <= 1'b0;
                        end
                    end
                end
            end else begin : SLV4_TIE_OFF
                // S4 is internal; assign dummy signals to prevent floating
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

    // ============================================================
    // 7. TEST TRACKING VARIABLES & SCOREBOARD
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
    // 8. BUS-FUNCTIONAL MASTER TASKS (M0, M1, M2)
    // ============================================================
    task automatic init_masters;
        begin
            // M0
            m0_awid    = '0; m0_awaddr  = '0; m0_awlen   = '0;
            m0_awsize  = 3'b010; m0_awburst = 2'b01; m0_awlock = 1'b0;
            m0_awcache = 4'b0000; m0_awprot = 3'b000; m0_awqos = 4'b0000;
            m0_awuser  = '0; m0_awvalid = 1'b0;
            m0_wdata   = '0; m0_wstrb   = 4'b0000; m0_wlast = 1'b0;
            m0_wuser   = '0; m0_wvalid  = 1'b0; m0_bready = 1'b0;
            m0_arid    = '0; m0_araddr  = '0; m0_arlen   = '0;
            m0_arsize  = 3'b010; m0_arburst = 2'b01; m0_arlock = 1'b0;
            m0_arcache = 4'b0000; m0_arprot = 3'b000; m0_arqos = 4'b0000;
            m0_aruser  = '0; m0_arvalid = 1'b0; m0_rready = 1'b0;

            // M1
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

            // M2
            m2_awid    = '0; m2_awaddr  = '0; m2_awlen   = '0;
            m2_awsize  = 3'b010; m2_awburst = 2'b01; m2_awlock = 1'b0;
            m2_awcache = 4'b0000; m2_awprot = 3'b000; m2_awqos = 4'b0000;
            m2_awuser  = '0; m2_awvalid = 1'b0;
            m2_wdata   = '0; m2_wstrb   = 4'b0000; m2_wlast = 1'b0;
            m2_wuser   = '0; m2_wvalid  = 1'b0; m2_bready = 1'b0;
            m2_arid    = '0; m2_araddr  = '0; m2_arlen   = '0;
            m2_arsize  = 3'b010; m2_arburst = 2'b01; m2_arlock = 1'b0;
            m2_arcache = 4'b0000; m2_arprot = 3'b000; m2_arqos = 4'b0000;
            m2_aruser  = '0; m2_arvalid = 1'b0; m2_rready = 1'b0;

            uart_rx = 1'b1;
            timer_ext_meas_tb = 1'b0;
            timer_capture_tb  = 1'b0;
            enc_a_tb          = 1'b0;
            enc_b_tb          = 1'b0;
            enc_index_tb      = 1'b0;
            enc_drive_active_tb = 1'b0;
            pid_tick_tb       = 1'b0;
            pid_actual_tb     = 16'h0000;
        end
    endtask

    // Master Write Task
    task automatic axi_write(
        input int                   mid,     // 0=M0, 1=M1, 2=M2
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] data,
        input logic [ID_WIDTH-1:0]   id   = 8'h01,
        input logic [7:0]            len  = 8'h00,
        input logic [3:0]            strb = 4'b1111,
        output logic [1:0]           bresp,
        output logic [ID_WIDTH-1:0]  bid
    );
        int timeout;
        bit aw_done, w_done, b_done;
        begin
            aw_done = 0;
            w_done  = 0;
            b_done  = 0;

            @(posedge clk);
            case (mid)
                0: begin
                    m0_awid    = id;
                    m0_awaddr  = addr;
                    m0_awlen   = len;
                    m0_awsize  = 3'b010;
                    m0_awburst = 2'b01;
                    m0_awvalid = 1'b1;
                    m0_wdata   = data;
                    m0_wstrb   = strb;
                    m0_wlast   = 1'b1;
                    m0_wvalid  = 1'b1;
                    m0_bready  = 1'b0;
                end
                1: begin
                    m1_awid    = id;
                    m1_awaddr  = addr;
                    m1_awlen   = len;
                    m1_awsize  = 3'b010;
                    m1_awburst = 2'b01;
                    m1_awvalid = 1'b1;
                    m1_wdata   = data;
                    m1_wstrb   = strb;
                    m1_wlast   = 1'b1;
                    m1_wvalid  = 1'b1;
                    m1_bready  = 1'b0;
                end
                2: begin
                    m2_awid    = id;
                    m2_awaddr  = addr;
                    m2_awlen   = len;
                    m2_awsize  = 3'b010;
                    m2_awburst = 2'b01;
                    m2_awvalid = 1'b1;
                    m2_wdata   = data;
                    m2_wstrb   = strb;
                    m2_wlast   = 1'b1;
                    m2_wvalid  = 1'b1;
                    m2_bready  = 1'b0;
                end
            endcase

            // Wait for AW and W handshakes
            timeout = 0;
            while ((!aw_done || !w_done) && timeout < 500) begin
                @(posedge clk);
                case (mid)
                    0: begin
                        if (m0_awvalid && m0_awready) begin
                            aw_done = 1;
                            m0_awvalid = 1'b0;
                        end
                        if (m0_wvalid && m0_wready) begin
                            w_done = 1;
                            m0_wvalid = 1'b0;
                        end
                    end
                    1: begin
                        if (m1_awvalid && m1_awready) begin
                            aw_done = 1;
                            m1_awvalid = 1'b0;
                        end
                        if (m1_wvalid && m1_wready) begin
                            w_done = 1;
                            m1_wvalid = 1'b0;
                        end
                    end
                    2: begin
                        if (m2_awvalid && m2_awready) begin
                            aw_done = 1;
                            m2_awvalid = 1'b0;
                        end
                        if (m2_wvalid && m2_wready) begin
                            w_done = 1;
                            m2_wvalid = 1'b0;
                        end
                    end
                endcase
                timeout++;
            end

            // Assert BREADY
            case (mid)
                0: m0_bready = 1'b1;
                1: m1_bready = 1'b1;
                2: m2_bready = 1'b1;
            endcase

            // Wait for B response
            timeout = 0;
            while (!b_done && timeout < 500) begin
                @(posedge clk);
                case (mid)
                    0: if (m0_bvalid && m0_bready) begin
                        b_done = 1;
                        bresp  = m0_bresp;
                        bid    = m0_bid;
                        m0_bready = 1'b0;
                    end
                    1: if (m1_bvalid && m1_bready) begin
                        b_done = 1;
                        bresp  = m1_bresp;
                        bid    = m1_bid;
                        m1_bready = 1'b0;
                    end
                    2: if (m2_bvalid && m2_bready) begin
                        b_done = 1;
                        bresp  = m2_bresp;
                        bid    = m2_bid;
                        m2_bready = 1'b0;
                    end
                endcase
                timeout++;
            end
        end
    endtask

    // Master Read Task
    task automatic axi_read(
        input int                   mid,     // 0=M0, 1=M1, 2=M2
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [ID_WIDTH-1:0]   id   = 8'h01,
        input logic [7:0]            len  = 8'h00,
        output logic [DATA_WIDTH-1:0] data,
        output logic [1:0]           rresp,
        output logic [ID_WIDTH-1:0]  rid
    );
        int timeout;
        bit ar_done, r_done;
        begin
            ar_done = 0;
            r_done  = 0;

            @(posedge clk);
            case (mid)
                0: begin
                    m0_arid    = id;
                    m0_araddr  = addr;
                    m0_arlen   = len;
                    m0_arsize  = 3'b010;
                    m0_arburst = 2'b01;
                    m0_arvalid = 1'b1;
                    m0_rready  = 1'b0;
                end
                1: begin
                    m1_arid    = id;
                    m1_araddr  = addr;
                    m1_arlen   = len;
                    m1_arsize  = 3'b010;
                    m1_arburst = 2'b01;
                    m1_arvalid = 1'b1;
                    m1_rready  = 1'b0;
                end
                2: begin
                    m2_arid    = id;
                    m2_araddr  = addr;
                    m2_arlen   = len;
                    m2_arsize  = 3'b010;
                    m2_arburst = 2'b01;
                    m2_arvalid = 1'b1;
                    m2_rready  = 1'b0;
                end
            endcase

            // Wait for AR handshake
            timeout = 0;
            while (!ar_done && timeout < 500) begin
                @(posedge clk);
                case (mid)
                    0: if (m0_arvalid && m0_arready) begin
                        ar_done = 1;
                        m0_arvalid = 1'b0;
                    end
                    1: if (m1_arvalid && m1_arready) begin
                        ar_done = 1;
                        m1_arvalid = 1'b0;
                    end
                    2: if (m2_arvalid && m2_arready) begin
                        ar_done = 1;
                        m2_arvalid = 1'b0;
                    end
                endcase
                timeout++;
            end

            // Assert RREADY
            case (mid)
                0: m0_rready = 1'b1;
                1: m1_rready = 1'b1;
                2: m2_rready = 1'b1;
            endcase

            // Wait for R response
            timeout = 0;
            while (!r_done && timeout < 500) begin
                @(posedge clk);
                case (mid)
                    0: if (m0_rvalid && m0_rready) begin
                        r_done = 1;
                        data   = m0_rdata;
                        rresp  = m0_rresp;
                        rid    = m0_rid;
                        m0_rready = 1'b0;
                    end
                    1: if (m1_rvalid && m1_rready) begin
                        r_done = 1;
                        data   = m1_rdata;
                        rresp  = m1_rresp;
                        rid    = m1_rid;
                        m1_rready = 1'b0;
                    end
                    2: if (m2_rvalid && m2_rready) begin
                        r_done = 1;
                        data   = m2_rdata;
                        rresp  = m2_rresp;
                        rid    = m2_rid;
                        m2_rready = 1'b0;
                    end
                endcase
                timeout++;
            end
        end
    endtask

    // Specialized Handshake Task: AW before W
    task automatic axi_write_aw_before_w(
        input int                   mid,
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] data,
        input int                   delay_cycles,
        output logic [1:0]          bresp
    );
        int timeout;
        bit aw_done, w_done, b_done;
        begin
            aw_done = 0;
            w_done  = 0;
            b_done  = 0;

            @(posedge clk);
            m1_awid    = 8'h11;
            m1_awaddr  = addr;
            m1_awlen   = 8'h00;
            m1_awsize  = 3'b010;
            m1_awburst = 2'b01;
            m1_awvalid = 1'b1;
            m1_wvalid  = 1'b0;
            m1_bready  = 1'b0;

            // Wait for AWREADY
            timeout = 0;
            while (!aw_done && timeout < 500) begin
                @(posedge clk);
                if (m1_awvalid && m1_awready) begin
                    m1_awvalid = 1'b0;
                    aw_done = 1;
                end
                timeout++;
            end

            // Wait delay cycles before asserting W
            repeat (delay_cycles) @(posedge clk);
            m1_wdata   = data;
            m1_wstrb   = 4'b1111;
            m1_wlast   = 1'b1;
            m1_wvalid  = 1'b1;

            // Wait for WREADY
            timeout = 0;
            while (!w_done && timeout < 500) begin
                @(posedge clk);
                if (m1_wvalid && m1_wready) begin
                    m1_wvalid = 1'b0;
                    w_done = 1;
                end
                timeout++;
            end

            // Assert BREADY
            m1_bready = 1'b1;

            // Wait for BVALID
            timeout = 0;
            while (!b_done && timeout < 500) begin
                @(posedge clk);
                if (m1_bvalid && m1_bready) begin
                    b_done = 1;
                    bresp  = m1_bresp;
                    m1_bready = 1'b0;
                end
                timeout++;
            end
        end
    endtask

    // Specialized Handshake Task: W before AW
    task automatic axi_write_w_before_aw(
        input int                   mid,
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] data,
        input int                   delay_cycles,
        output logic [1:0]          bresp
    );
        int timeout;
        bit aw_done, w_done, b_done;
        begin
            aw_done = 0;
            w_done  = 0;
            b_done  = 0;

            @(posedge clk);
            m1_awvalid = 1'b0;
            m1_wdata   = data;
            m1_wstrb   = 4'b1111;
            m1_wlast   = 1'b1;
            m1_wvalid  = 1'b1;
            m1_bready  = 1'b0;

            // Wait delay cycles before asserting AW
            repeat (delay_cycles) @(posedge clk);
            m1_awid    = 8'h22;
            m1_awaddr  = addr;
            m1_awlen   = 8'h00;
            m1_awsize  = 3'b010;
            m1_awburst = 2'b01;
            m1_awvalid = 1'b1;

            // Wait for both AW and W handshakes
            timeout = 0;
            while ((!aw_done || !w_done) && timeout < 500) begin
                @(posedge clk);
                if (m1_awvalid && m1_awready) begin
                    m1_awvalid = 1'b0;
                    aw_done = 1;
                end
                if (m1_wvalid && m1_wready) begin
                    m1_wvalid = 1'b0;
                    w_done = 1;
                end
                timeout++;
            end

            // Assert BREADY
            m1_bready = 1'b1;

            // Wait for BVALID
            timeout = 0;
            while (!b_done && timeout < 500) begin
                @(posedge clk);
                if (m1_bvalid && m1_bready) begin
                    b_done = 1;
                    bresp  = m1_bresp;
                    m1_bready = 1'b0;
                end
                timeout++;
            end
        end
    endtask

    // Backpressure on BREADY Task
    task automatic axi_write_delayed_bready(
        input int                   mid,
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] data,
        input int                   delay_cycles,
        output logic [1:0]          bresp
    );
        int timeout;
        bit aw_done, w_done, b_done;
        begin
            aw_done = 0;
            w_done  = 0;
            b_done  = 0;

            @(posedge clk);
            m1_awid    = 8'h33;
            m1_awaddr  = addr;
            m1_awlen   = 8'h00;
            m1_awsize  = 3'b010;
            m1_awburst = 2'b01;
            m1_awvalid = 1'b1;
            m1_wdata   = data;
            m1_wstrb   = 4'b1111;
            m1_wlast   = 1'b1;
            m1_wvalid  = 1'b1;
            m1_bready  = 1'b0;

            timeout = 0;
            while ((!aw_done || !w_done) && timeout < 500) begin
                @(posedge clk);
                if (m1_awvalid && m1_awready) begin
                    m1_awvalid = 1'b0;
                    aw_done = 1;
                end
                if (m1_wvalid && m1_wready) begin
                    m1_wvalid = 1'b0;
                    w_done = 1;
                end
                timeout++;
            end

            // Apply backpressure by keeping BREADY deasserted for delay_cycles
            repeat (delay_cycles) @(posedge clk);
            m1_bready = 1'b1;

            timeout = 0;
            while (!b_done && timeout < 500) begin
                @(posedge clk);
                if (m1_bvalid && m1_bready) begin
                    b_done = 1;
                    bresp  = m1_bresp;
                    m1_bready = 1'b0;
                end
                timeout++;
            end
        end
    endtask

    // Backpressure on RREADY Task
    task automatic axi_read_delayed_rready(
        input int                   mid,
        input logic [ADDR_WIDTH-1:0] addr,
        input int                   delay_cycles,
        output logic [DATA_WIDTH-1:0] data,
        output logic [1:0]          rresp
    );
        int timeout;
        bit ar_done, r_done;
        begin
            ar_done = 0;
            r_done  = 0;

            @(posedge clk);
            m1_arid    = 8'h44;
            m1_araddr  = addr;
            m1_arlen   = 8'h00;
            m1_arsize  = 3'b010;
            m1_arburst = 2'b01;
            m1_arvalid = 1'b1;
            m1_rready  = 1'b0;

            timeout = 0;
            while (!ar_done && timeout < 500) begin
                @(posedge clk);
                if (m1_arvalid && m1_arready) begin
                    m1_arvalid = 1'b0;
                    ar_done = 1;
                end
                timeout++;
            end

            // Apply backpressure by keeping RREADY deasserted for delay_cycles
            repeat (delay_cycles) @(posedge clk);
            m1_rready = 1'b1;

            timeout = 0;
            while (!r_done && timeout < 500) begin
                @(posedge clk);
                if (m1_rvalid && m1_rready) begin
                    r_done = 1;
                    data   = m1_rdata;
                    rresp  = m1_rresp;
                    m1_rready = 1'b0;
                end
                timeout++;
            end
        end
    endtask

    // ============================================================
    // 9. UART SERIAL VERIFICATION TASKS
    // ============================================================
    // External Serial Byte Injector (Testbench -> DUT uart_rx)
    task automatic uart_inject_byte(
        input logic [7:0] byte_val,
        input int         rx_bit_cycles
    );
        integer bit_idx;
        begin
            $display("[UART_TB_RX] Injecting byte 0x%02h over serial uart_rx (bit period = %0d fixed_clk cycles)...", byte_val, rx_bit_cycles);
            @(negedge fixed_clk);
            // 1. START BIT (0)
            uart_rx = 1'b0;
            repeat (rx_bit_cycles) @(posedge fixed_clk);

            // 2. DATA BITS (LSB to MSB)
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                @(negedge fixed_clk);
                uart_rx = byte_val[bit_idx];
                repeat (rx_bit_cycles) @(posedge fixed_clk);
            end

            // 3. STOP BIT (1)
            @(negedge fixed_clk);
            uart_rx = 1'b1;
            repeat (rx_bit_cycles) @(posedge fixed_clk);

            $display("[UART_TB_RX] Finished serial injection for byte 0x%02h at time %0t", byte_val, $time);
        end
    endtask

    // DUT Serial Frame Monitor (DUT uart_tx -> Testbench)
    task automatic uart_decode_tx(
        input int          tx_bit_cycles,
        output logic [7:0] decoded_byte,
        output logic       frame_ok
    );
        integer bit_idx;
        begin
            frame_ok = 1'b1;
            decoded_byte = 8'h00;

            // Wait for falling edge on uart_tx (START bit)
            @(negedge uart_tx);
            $display("[UART_TB_TX] Detected START bit transition at time %0t", $time);

            // Sample center of START bit
            repeat (tx_bit_cycles / 2) @(posedge fixed_clk);
            #1;
            if (uart_tx !== 1'b0) begin
                $display("[UART_TB_TX ERROR] START bit false trigger (uart_tx is not 0)");
                frame_ok = 1'b0;
            end

            // Sample 8 data bits at center of bit period
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                repeat (tx_bit_cycles) @(posedge fixed_clk);
                #1;
                decoded_byte[bit_idx] = uart_tx;
                $display("[UART_TB_TX] Sampled bit %0d = %b at time %0t", bit_idx, uart_tx, $time);
            end

            // Sample STOP bit
            repeat (tx_bit_cycles) @(posedge fixed_clk);
            #1;
            if (uart_tx !== 1'b1) begin
                $display("[UART_TB_TX ERROR] Invalid STOP bit (uart_tx is not 1)");
                frame_ok = 1'b0;
            end else begin
                $display("[UART_TB_TX] Sampled STOP bit = 1 (valid) at time %0t", $time);
            end

            $display("[UART_TB_TX] Successfully decoded TX byte = 0x%02h", decoded_byte);
        end
    endtask

    // ============================================================
    // 10. MAIN TEST SCENARIOS
    // ============================================================
    initial begin
        logic [31:0] rd_data;
        logic [1:0]  resp;
        logic [7:0]  resp_id;
        logic [7:0]  tx_decoded;
        logic        tx_ok;

`ifdef FSDB
        // Waveform Dump
        $fsdbDumpfile("main_top.fsdb");
        $fsdbDumpvars(0, tb_main_top);
`endif

        $display("================================================================================");
        $display("          STARTING EXHAUSTIVE VERIFICATION OF 3x15 AXI + UART TOP               ");
        $display("================================================================================");

        // Initialize signals
        init_masters();
        rst = 1'b1;

        // ------------------------------------------------------------
        // TEST 1: Power-on Reset & Idle State Verification
        // ------------------------------------------------------------
        $display("\n[SCENARIO 1] Verifying Reset & Initial Idle Conditions...");
        repeat (10) @(posedge clk);
        check_assert("Reset State: uart_tx remains High (Idle)", uart_tx === 1'b1, "uart_tx not high in reset");
        check_assert("Reset State: uart_irq is Low (Inactive)",  uart_irq === 1'b0, "uart_irq high during reset");

        // Release reset
        rst = 1'b0;
        repeat (10) @(posedge clk);
        check_assert("Post-Reset: uart_tx remains High (Idle)",  uart_tx === 1'b1, "uart_tx dropped after reset");
        check_assert("Post-Reset: uart_irq remains Low",        uart_irq === 1'b0, "uart_irq asserted unexpectedly");

        // ------------------------------------------------------------
        // TEST 2: Unmapped Address Access & DECERR Verification
        // ------------------------------------------------------------
        $display("\n[SCENARIO 2] Verifying Unmapped Address Decoding (DECERR = 2'b11)...");

        // 2A: High unmapped write
        axi_write(1, ADDR_UNMAPPED, 32'hDEAD_BEEF, 8'hA1, 8'h00, 4'hF, resp, resp_id);
        check_assert("Unmapped Write High (0x9000_0000): Returns DECERR (2'b11)", resp === 2'b11, $sformatf("Got resp=%b", resp));
        check_assert("Unmapped Write High: Preserves Transaction ID (0xA1)", resp_id === 8'hA1, $sformatf("Got id=%h", resp_id));

        // 2B: High unmapped read
        axi_read(1, ADDR_UNMAPPED, 8'hB1, 8'h00, rd_data, resp, resp_id);
        check_assert("Unmapped Read High (0x9000_0000): Returns DECERR (2'b11)", resp === 2'b11, $sformatf("Got resp=%b", resp));
        check_assert("Unmapped Read High: Read data is 0", rd_data === 32'h0, $sformatf("Got rd_data=%h", rd_data));

        // 2C: Low unmapped write (gap between 0 and IMEM 0x0004_0000)
        axi_write(1, ADDR_UNMAPPED_LO, 32'hFEED_CAFE, 8'hA2, 8'h00, 4'hF, resp, resp_id);
        check_assert("Unmapped Write Low (0x0001_0000): Returns DECERR (2'b11)", resp === 2'b11, $sformatf("Got resp=%b", resp));

        // 2D: Low unmapped read
        axi_read(1, ADDR_UNMAPPED_LO, 8'hB2, 8'h00, rd_data, resp, resp_id);
        check_assert("Unmapped Read Low (0x0001_0000): Returns DECERR (2'b11)", resp === 2'b11, $sformatf("Got resp=%b", resp));

        // 2E: Aperture gap: between Timer and UART (0x4003_4000)
        axi_read(1, 32'h4003_4000, 8'hB3, 8'h00, rd_data, resp, resp_id);
        check_assert("Aperture Gap Read (0x4003_4000): Returns DECERR", resp === 2'b11, $sformatf("Got resp=%b", resp));

        // 2F: Aperture gap: between UART and Encoder (0x4003_6000)
        axi_read(1, 32'h4003_6000, 8'hB4, 8'h00, rd_data, resp, resp_id);
        check_assert("Aperture Gap Read (0x4003_6000): Returns DECERR", resp === 2'b11, $sformatf("Got resp=%b", resp));

        // 2G: Aperture gap: between Encoder and PID (0x4003_E000)
        axi_read(1, 32'h4003_E000, 8'hB5, 8'h00, rd_data, resp, resp_id);
        check_assert("Aperture Gap Read (0x4003_E000): Returns DECERR", resp === 2'b11, $sformatf("Got resp=%b", resp));

        // 2H: Aperture gap: between PID and PWM (0x4004_0000)
        axi_read(1, 32'h4004_0000, 8'hB6, 8'h00, rd_data, resp, resp_id);
        check_assert("Aperture Gap Read (0x4004_0000): Returns DECERR", resp === 2'b11, $sformatf("Got resp=%b", resp));

        // 2I: Aperture gap: above PWM (0x4004_2000)
        axi_read(1, 32'h4004_2000, 8'hB7, 8'h00, rd_data, resp, resp_id);
        check_assert("Aperture Gap Read (0x4004_2000): Returns DECERR", resp === 2'b11, $sformatf("Got resp=%b", resp));

        // ------------------------------------------------------------
        // TEST 3: Crossbar Connectivity Across Slaves and Masters
        // ------------------------------------------------------------
        $display("\n[SCENARIO 3] Verifying Crossbar Routing for Masters (M0, M1, M2) & External Slaves...");

        // 3A: M1 -> S0 (IMEM 0x0004_0000)
        axi_write(1, ADDR_S0_IMEM, 32'h1122_3344, 8'h10, 8'h00, 4'hF, resp, resp_id);
        check_assert("Routing: M1 -> S0 (IMEM) Write Returns OKAY", resp === 2'b00);
        axi_read(1, ADDR_S0_IMEM + 4, 8'h11, 8'h00, rd_data, resp, resp_id);
        check_assert("Routing: M1 -> S0 (IMEM) Read Returns OKAY", resp === 2'b00);
        check_assert("Routing: M1 -> S0 (IMEM) Read Signature Valid", rd_data[31:16] === 16'hCA00);

        // 3B: M1 -> S1 (DMEM 0x0008_0000)
        axi_write(1, ADDR_S1_DMEM, 32'h5566_7788, 8'h12, 8'h00, 4'hF, resp, resp_id);
        check_assert("Routing: M1 -> S1 (DMEM) Write Returns OKAY", resp === 2'b00);
        axi_read(1, ADDR_S1_DMEM + 8, 8'h13, 8'h00, rd_data, resp, resp_id);
        check_assert("Routing: M1 -> S1 (DMEM) Read Returns OKAY", resp === 2'b00);
        check_assert("Routing: M1 -> S1 (DMEM) Read Signature Valid", rd_data[31:16] === 16'hCA01);

        // 3C: M1 -> S11 (WDT 0x8000_4000)
        axi_write(1, ADDR_S11_WDT, 32'h1111_2222, 8'h14, 8'h00, 4'hF, resp, resp_id);
        check_assert("Routing: M1 -> S11 (WDT) Write Returns OKAY", resp === 2'b00);
        axi_read(1, ADDR_S11_WDT, 8'h15, 8'h00, rd_data, resp, resp_id);
        check_assert("Routing: M1 -> S11 (WDT) Read Returns OKAY", resp === 2'b00);
        check_assert("Routing: M1 -> S11 (WDT) Read Signature Valid", rd_data[31:16] === 16'hCA0B);

        // 3D: M1 -> S12 (ADC 0x8000_5000)
        axi_write(1, ADDR_S12_ADC, 32'h3333_4444, 8'h16, 8'h00, 4'hF, resp, resp_id);
        check_assert("Routing: M1 -> S12 (ADC) Write Returns OKAY", resp === 2'b00);
        axi_read(1, ADDR_S12_ADC, 8'h17, 8'h00, rd_data, resp, resp_id);
        check_assert("Routing: M1 -> S12 (ADC) Read Returns OKAY", resp === 2'b00);
        check_assert("Routing: M1 -> S12 (ADC) Read Signature Valid", rd_data[31:16] === 16'hCA0C);

        // 3E: M1 -> S13 (DMA Regs 0x8000_6000)
        axi_write(1, ADDR_S13_DMA, 32'h5555_6666, 8'h18, 8'h00, 4'hF, resp, resp_id);
        check_assert("Routing: M1 -> S13 (DMA) Write Returns OKAY", resp === 2'b00);
        axi_read(1, ADDR_S13_DMA, 8'h19, 8'h00, rd_data, resp, resp_id);
        check_assert("Routing: M1 -> S13 (DMA) Read Returns OKAY", resp === 2'b00);
        check_assert("Routing: M1 -> S13 (DMA) Read Signature Valid", rd_data[31:16] === 16'hCA0D);

        // 3F: M0 (IFU) -> S4 (UART LSR)
        axi_read(0, UART_LSR, 8'h02, 8'h00, rd_data, resp, resp_id);
        check_assert("Routing: M0 (VeeR IFU) -> S4 (UART) Read Returns OKAY", resp === 2'b00);

        // 3G: M2 (DMA) -> S4 (UART LSR)
        axi_read(2, UART_LSR, 8'h03, 8'h00, rd_data, resp, resp_id);
        check_assert("Routing: M2 (DMA) -> S4 (UART) Read Returns OKAY", resp === 2'b00);

        // ------------------------------------------------------------
        // TEST 4: DLAB Setup & Baud Rate Configuration (115200 Baud)
        // ------------------------------------------------------------
        $display("\n[SCENARIO 4] Verifying UART DLAB & 115200 Baud Divisor Setup...");

        // 4A: With DLAB=0, write IER = 0x00
        axi_write(1, UART_IER, 32'h0000_0000, 8'h20, 8'h00, 4'hF, resp, resp_id);
        check_assert("UART: Write IER=0x00 with DLAB=0 Returns OKAY", resp === 2'b00);

        // 4B: Enable DLAB (write LCR = 0x83 -> DLAB=1, 8-N-1)
        axi_write(1, UART_LCR, 32'h0000_0083, 8'h22, 8'h00, 4'hF, resp, resp_id);
        check_assert("UART: Write LCR=0x83 (Enable DLAB) Returns OKAY", resp === 2'b00);

        // 4C: Program Baud Divisor = 347 (for 115200 Baud @ 40 MHz)
        axi_write(1, UART_BAUD_DIV, BAUD_DIV_115200, 8'h23, 8'h00, 4'hF, resp, resp_id);
        check_assert("UART: Write Baud Divisor (347) Returns OKAY", resp === 2'b00);

        // 4D: Disable DLAB (write LCR = 0x03 -> DLAB=0, 8-N-1)
        axi_write(1, UART_LCR, 32'h0000_0003, 8'h24, 8'h00, 4'hF, resp, resp_id);
        check_assert("UART: Write LCR=0x03 (Disable DLAB) Returns OKAY", resp === 2'b00);

        // 4E: Verify normal register access restored (DLAB=0) via LSR
        axi_read(1, UART_LSR, 8'h25, 8'h00, rd_data, resp, resp_id);
        check_assert("UART: Verify normal register access restored (LSR Read OKAY)", resp === 2'b00);
        check_assert("UART: Verify THRE=1 in LSR", rd_data[5] === 1'b1, $sformatf("Got LSR=0x%02h", rd_data[7:0]));

        // ------------------------------------------------------------
        // TEST 5: UART TX Transmission & Serial Waveform Verification
        // ------------------------------------------------------------
        $display("\n[SCENARIO 5] Verifying UART TX Transmission at 115200 Baud (Byte = 0xA5)...");
        fork
            begin
                // AXI Master writes byte 0xA5 to THR (0x8000_3000)
                axi_write(1, UART_RBR_THR, 32'h0000_00A5, 8'h30, 8'h00, 4'hF, resp, resp_id);
                check_assert("UART TX: Write byte 0xA5 to THR Returns OKAY", resp === 2'b00);
            end
            begin
                // Monitor uart_tx pin concurrently
                uart_decode_tx(TX_CYCLES_115200, tx_decoded, tx_ok);
            end
        join

        check_assert("UART TX: Serial frame format (START & STOP bits) valid", tx_ok === 1'b1);
        check_assert("UART TX: Decoded byte exactly matches transmitted byte (0xA5)", tx_decoded === 8'hA5, $sformatf("Decoded 0x%02h vs expected 0xA5", tx_decoded));

        // Check LSR for THRE / TEMT
        axi_read(1, UART_LSR, 8'h31, 8'h00, rd_data, resp, resp_id);
        check_assert("UART TX: LSR bit 5 (THRE) is set", rd_data[5] === 1'b1, $sformatf("Got LSR=0x%02h", rd_data[7:0]));

        // ------------------------------------------------------------
        // TEST 6: UART RX Reception & AXI Readback
        // ------------------------------------------------------------
        $display("\n[SCENARIO 6] Verifying UART RX Reception at 115200 Baud (Byte = 0x5A)...");

        // 6A: Enable RDA interrupt / status flag in IER (IER[0] = 1)
        axi_write(1, UART_IER, 32'h0000_0001, 8'h3F, 8'h00, 4'hF, resp, resp_id);
        check_assert("UART RX: Write IER=0x01 to enable DATA_READY in LSR", resp === 2'b00);

        // 6B: Inject serial byte 0x5A on uart_rx
        uart_inject_byte(8'h5A, RX_CYCLES_115200);

        // 6C: Poll LSR bit 0 (DATA_READY)
        repeat (10) @(posedge clk);
        axi_read(1, UART_LSR, 8'h40, 8'h00, rd_data, resp, resp_id);
        check_assert("UART RX: LSR bit 0 (DATA_READY) asserted", rd_data[0] === 1'b1, $sformatf("Got LSR=0x%02h", rd_data[7:0]));

        // 6D: Read RBR through AXI
        axi_read(1, UART_RBR_THR, 8'h41, 8'h00, rd_data, resp, resp_id);
        check_assert("UART RX: Read RBR Returns OKAY", resp === 2'b00);
        check_assert("UART RX: Received byte matches injected byte (0x5A)", rd_data[7:0] === 8'h5A, $sformatf("Got RBR=0x%02h vs expected 0x5A", rd_data[7:0]));

        // 6E: Verify DATA_READY cleared in LSR
        axi_read(1, UART_LSR, 8'h42, 8'h00, rd_data, resp, resp_id);
        check_assert("UART RX: LSR bit 0 cleared after reading RBR", rd_data[0] === 1'b0, $sformatf("Got LSR=0x%02h", rd_data[7:0]));

        // ------------------------------------------------------------
        // TEST 7: UART Interrupt (IRQ) Behavior
        // ------------------------------------------------------------
        $display("\n[SCENARIO 7] Verifying UART Interrupt Behavior (IER=0 vs IER=1)...");

        // 7A: IER = 0, inject byte 0x3C -> verify IRQ remains 0
        axi_write(1, UART_IER, 32'h0000_0000, 8'h50, 8'h00, 4'hF, resp, resp_id);
        uart_inject_byte(8'h3C, RX_CYCLES_115200);
        repeat (10) @(posedge clk);
        check_assert("UART IRQ: With IER=0, uart_irq remains deasserted (0)", uart_irq === 1'b0);

        // Read out byte to empty FIFO
        axi_read(1, UART_RBR_THR, 8'h51, 8'h00, rd_data, resp, resp_id);
        check_assert("UART IRQ: Flushed RBR byte (0x3C)", rd_data[7:0] === 8'h3C);

        // 7B: Enable RDA interrupt: IER = 0x01
        axi_write(1, UART_IER, 32'h0000_0001, 8'h52, 8'h00, 4'hF, resp, resp_id);
        check_assert("UART IRQ: Write IER=0x01 Returns OKAY", resp === 2'b00);

        // Inject byte 0x7E -> verify IRQ asserts
        uart_inject_byte(8'h7E, RX_CYCLES_115200);
        repeat (10) @(posedge clk);
        check_assert("UART IRQ: With IER=1, uart_irq asserts High upon byte reception", uart_irq === 1'b1);

        // Read RBR -> verify IRQ deasserts
        axi_read(1, UART_RBR_THR, 8'h53, 8'h00, rd_data, resp, resp_id);
        check_assert("UART IRQ: Read received byte (0x7E)", rd_data[7:0] === 8'h7E);
        repeat (10) @(posedge clk);
        check_assert("UART IRQ: uart_irq deasserts Low after reading RBR", uart_irq === 1'b0);

        // ------------------------------------------------------------
        // TEST 8: AXI Handshake Ordering Edge Cases & Backpressure
        // ------------------------------------------------------------
        $display("\n[SCENARIO 8] Verifying AXI Handshake Ordering & Backpressure Edge Cases...");

        // 8A: AW before W on S0 (IMEM)
        axi_write_aw_before_w(1, ADDR_S0_IMEM + 16, 32'hAABB_CCDD, 5, resp);
        check_assert("Handshake: AW asserted 5 cycles before W completes cleanly (OKAY)", resp === 2'b00);

        // 8B: W before AW on S0 (IMEM)
        axi_write_w_before_aw(1, ADDR_S0_IMEM + 20, 32'h1122_3344, 5, resp);
        check_assert("Handshake: W asserted 5 cycles before AW completes cleanly (OKAY)", resp === 2'b00);

        // 8C: Backpressure on B channel (delay BREADY by 6 cycles)
        axi_write_delayed_bready(1, UART_IER, 32'h0000_0000, 6, resp);
        check_assert("Handshake: BREADY backpressure delay handled cleanly (OKAY)", resp === 2'b00);

        // 8D: Backpressure on R channel (delay RREADY by 6 cycles)
        axi_read_delayed_rready(1, UART_LSR, 6, rd_data, resp);
        check_assert("Handshake: RREADY backpressure delay handled cleanly (OKAY)", resp === 2'b00);
        check_assert("Handshake: Read data valid after delayed RREADY (THRE=1)", rd_data[5] === 1'b1);

        // ------------------------------------------------------------
        // TEST 9: AXI Transaction ID Preservation
        // ------------------------------------------------------------
        $display("\n[SCENARIO 9] Verifying AXI Transaction ID Preservation...");
        axi_write(1, ADDR_S0_IMEM, 32'h1234_5678, 8'hA8, 8'h00, 4'hF, resp, resp_id);
        check_assert("ID Preservation: Write ID 0xA8 returned in BID", resp_id === 8'hA8, $sformatf("Got BID=%h", resp_id));

        axi_read(1, UART_LSR, 8'hD4, 8'h00, rd_data, resp, resp_id);
        check_assert("ID Preservation: Read ID 0xD4 returned in RID", resp_id === 8'hD4, $sformatf("Got RID=%h", resp_id));

        axi_write(1, UART_IER, 32'h0000_0001, 8'hFE, 8'h00, 4'hF, resp, resp_id);
        check_assert("ID Preservation: Write ID 0xFE returned in BID", resp_id === 8'hFE, $sformatf("Got BID=%h", resp_id));

        axi_read(1, ADDR_S1_DMEM, 8'h7B, 8'h00, rd_data, resp, resp_id);
        check_assert("ID Preservation: Read ID 0x7B returned in RID", resp_id === 8'h7B, $sformatf("Got RID=%h", resp_id));

        // ------------------------------------------------------------
        // TEST 10: Unsupported Burst Protection (Single-Beat MMIO Peripheral)
        // ------------------------------------------------------------
        $display("\n[SCENARIO 10] Testing Unsupported Bursts (AWLEN > 0, ARLEN > 0)...");

        // 10A: Write with AWLEN = 3 to UART
        axi_write(1, UART_RBR_THR, 32'h0000_0041, 8'h60, 8'h03, 4'hF, resp, resp_id);
        check_assert("Unsupported Burst Write: Completes without hang", resp === 2'b00);

        // 10B: Read with ARLEN = 3 to UART
        axi_read(1, UART_LSR, 8'h61, 8'h03, rd_data, resp, resp_id);
        check_assert("Unsupported Burst Read: Completes without hang", resp === 2'b00);

        // 10C: Verify UART register map integrity after burst attempt
        axi_read(1, UART_LSR, 8'h62, 8'h00, rd_data, resp, resp_id);
        check_assert("UART Integrity: LSR readable & valid after burst attempts", resp === 2'b00);

        // ------------------------------------------------------------
        // TEST 11: Mid-Activity Reset & Recovery
        // ------------------------------------------------------------
        $display("\n[SCENARIO 11] Verifying System Reset During Activity & Clean Recovery...");
        // Assert reset mid-test
        rst = 1'b1;
        repeat (5) @(posedge clk);
        init_masters();
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (10) @(posedge clk);

        // Perform clean transaction post-reset
        axi_write(1, UART_LCR, 32'h0000_0003, 8'h70, 8'h00, 4'hF, resp, resp_id);
        check_assert("Reset Recovery: Write to LCR post-reset returns OKAY", resp === 2'b00);
        axi_read(1, UART_LSR, 8'h71, 8'h00, rd_data, resp, resp_id);
        check_assert("Reset Recovery: Read from LSR post-reset returns OKAY", resp === 2'b00);

        // ============================================================
        // TEST 12: GPIO Peripheral Tests (S2 / m02_axi)
        // ============================================================
        $display("\n================================================================================");
        $display("       GPIO S2 TESTS: AXI Master -> Interconnect -> S2 -> GPIO               ");
        $display("================================================================================");
        // 12A: Safe RW register DIR (0x4003_1008)
        $display("\n[GPIO TEST 1] Write/Readback on DIR register (0x4003_1008)...");
        axi_write(1, GPIO_DIR, 32'hAAAA_5555, 8'h21, 8'h00, 4'hF, resp, resp_id);
        check_assert("GPIO: Write DIR returns OKAY", resp === 2'b00, $sformatf("Got BRESP=%b", resp));
        axi_read(1, GPIO_DIR, 8'h22, 8'h00, rd_data, resp, resp_id);
        check_assert("GPIO: Read DIR returns OKAY", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("GPIO: DIR readback matches written value (0xAAAA_5555)", rd_data === 32'hAAAA_5555, $sformatf("Got RDATA=0x%08h", rd_data));

        // 12B: Safe RW register DEB_TH (0x4003_102C)
        $display("\n[GPIO TEST 2] Write/Readback on DEB_TH register (0x4003_102C)...");
        axi_write(1, GPIO_DEB_TH, 32'h0000_1234, 8'h23, 8'h00, 4'hF, resp, resp_id);
        check_assert("GPIO: Write DEB_TH returns OKAY", resp === 2'b00, $sformatf("Got BRESP=%b", resp));
        axi_read(1, GPIO_DEB_TH, 8'h24, 8'h00, rd_data, resp, resp_id);
        check_assert("GPIO: Read DEB_TH returns OKAY", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("GPIO: DEB_TH readback matches written value (0x0000_1234)", rd_data === 32'h0000_1234, $sformatf("Got RDATA=0x%08h", rd_data));

        // 12C: Multi-master access to GPIO
        $display("\n[GPIO TEST 3] Multi-master access (M0, M2) -> S2 (GPIO)...");
        axi_read(0, GPIO_DIR, 8'h25, 8'h00, rd_data, resp, resp_id);
        check_assert("GPIO: M0 read DIR returns OKAY", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("GPIO: M0 read DIR data matches 0xAAAA_5555", rd_data === 32'hAAAA_5555, $sformatf("Got RDATA=0x%08h", rd_data));

        axi_read(2, GPIO_DIR, 8'h26, 8'h00, rd_data, resp, resp_id);
        check_assert("GPIO: M2 read DIR returns OKAY", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("GPIO: M2 read DIR data matches 0xAAAA_5555", rd_data === 32'hAAAA_5555, $sformatf("Got RDATA=0x%08h", rd_data));

        // ============================================================
        // TEST 13: Timer Peripheral Tests (S3 / m03_axi)
        // ============================================================
        $display("\n================================================================================");
        $display("       TIMER S3 TESTS: AXI Master -> Interconnect -> S3 -> Timer             ");
        $display("================================================================================");
        // 13A: Safe RW register LOAD (0x4003_3004)
        $display("\n[TIMER TEST 1] Write/Readback on LOAD register (0x4003_3004)...");
        axi_write(1, TIMER_LOAD, 32'h0000_ABCD, 8'h31, 8'h00, 4'hF, resp, resp_id);
        check_assert("Timer: Write LOAD returns OKAY", resp === 2'b00, $sformatf("Got BRESP=%b", resp));
        axi_read(1, TIMER_LOAD, 8'h32, 8'h00, rd_data, resp, resp_id);
        check_assert("Timer: Read LOAD returns OKAY", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("Timer: LOAD readback matches written value (0x0000_ABCD)", rd_data === 32'h0000_ABCD, $sformatf("Got RDATA=0x%08h", rd_data));

        // 13B: Safe RW register PRE (0x4003_300C)
        $display("\n[TIMER TEST 2] Write/Readback on PRE register (0x4003_300C)...");
        axi_write(1, TIMER_PRE, 32'h0000_0007, 8'h33, 8'h00, 4'hF, resp, resp_id);
        check_assert("Timer: Write PRE returns OKAY", resp === 2'b00, $sformatf("Got BRESP=%b", resp));
        axi_read(1, TIMER_PRE, 8'h34, 8'h00, rd_data, resp, resp_id);
        check_assert("Timer: Read PRE returns OKAY", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("Timer: PRE readback matches written value (0x0000_0007)", rd_data === 32'h0000_0007, $sformatf("Got RDATA=0x%08h", rd_data));

        // 13C: Safe RW register CMP (0x4003_3018)
        $display("\n[TIMER TEST 3] Write/Readback on CMP register (0x4003_3018)...");
        axi_write(1, TIMER_CMP, 32'h0000_5678, 8'h35, 8'h00, 4'hF, resp, resp_id);
        check_assert("Timer: Write CMP returns OKAY", resp === 2'b00, $sformatf("Got BRESP=%b", resp));
        axi_read(1, TIMER_CMP, 8'h36, 8'h00, rd_data, resp, resp_id);
        check_assert("Timer: Read CMP returns OKAY", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("Timer: CMP readback matches written value (0x0000_5678)", rd_data === 32'h0000_5678, $sformatf("Got RDATA=0x%08h", rd_data));

        // 13D: Multi-master access to Timer
        $display("\n[TIMER TEST 4] Multi-master access (M0, M2) -> S3 (Timer)...");
        axi_read(0, TIMER_LOAD, 8'h37, 8'h00, rd_data, resp, resp_id);
        check_assert("Timer: M0 read LOAD returns OKAY", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("Timer: M0 read LOAD data matches 0x0000_ABCD", rd_data === 32'h0000_ABCD, $sformatf("Got RDATA=0x%08h", rd_data));

        axi_read(2, TIMER_LOAD, 8'h38, 8'h00, rd_data, resp, resp_id);
        check_assert("Timer: M2 read LOAD returns OKAY", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("Timer: M2 read LOAD data matches 0x0000_ABCD", rd_data === 32'h0000_ABCD, $sformatf("Got RDATA=0x%08h", rd_data));

        // ============================================================
        // TEST 14: Quadrature Encoder Tests (S8 / m08_axi)
        // ============================================================
        $display("\n================================================================================");
        $display("       ENCODER S8 TESTS: AXI Master -> Interconnect -> S8 -> Encoder         ");
        $display("================================================================================");
        // 14A: Read-only VERSION register (0x4003_D030)
        $display("\n[ENCODER TEST 1] Read/Write-ignore on VERSION register (0x4003_D030)...");
        axi_read(1, ENC_VERSION, 8'h81, 8'h00, rd_data, resp, resp_id);
        check_assert("Encoder: Read VERSION returns OKAY", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("Encoder: VERSION ID matches 0x0001_0000", rd_data === 32'h0001_0000, $sformatf("Got RDATA=0x%08h", rd_data));

        // Write to RO VERSION register: should be safely ignored and not corrupt
        axi_write(1, ENC_VERSION, 32'hDEAD_BEEF, 8'h82, 8'h00, 4'hF, resp, resp_id);
        check_assert("Encoder: Write to RO VERSION completes OKAY", resp === 2'b00, $sformatf("Got BRESP=%b", resp));
        axi_read(1, ENC_VERSION, 8'h83, 8'h00, rd_data, resp, resp_id);
        check_assert("Encoder: VERSION remains 0x0001_0000 after write attempt", rd_data === 32'h0001_0000, $sformatf("Got RDATA=0x%08h", rd_data));

        // 14B: Safe RW register WINDOW (0x4003_D010)
        $display("\n[ENCODER TEST 2] Write/Readback on WINDOW register (0x4003_D010)...");
        axi_write(1, ENC_WINDOW, 32'h0000_03E8, 8'h84, 8'h00, 4'hF, resp, resp_id);
        check_assert("Encoder: Write WINDOW returns OKAY", resp === 2'b00, $sformatf("Got BRESP=%b", resp));
        axi_read(1, ENC_WINDOW, 8'h85, 8'h00, rd_data, resp, resp_id);
        check_assert("Encoder: Read WINDOW returns OKAY", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("Encoder: WINDOW readback matches written value (0x0000_03E8)", rd_data === 32'h0000_03E8, $sformatf("Got RDATA=0x%08h", rd_data));

        // 14C: Safe RW register SCALE (0x4003_D018)
        $display("\n[ENCODER TEST 3] Write/Readback on SCALE register (0x4003_D018)...");
        axi_write(1, ENC_SCALE, 32'h0000_0064, 8'h86, 8'h00, 4'hF, resp, resp_id);
        check_assert("Encoder: Write SCALE returns OKAY", resp === 2'b00, $sformatf("Got BRESP=%b", resp));
        axi_read(1, ENC_SCALE, 8'h87, 8'h00, rd_data, resp, resp_id);
        check_assert("Encoder: Read SCALE returns OKAY", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("Encoder: SCALE readback matches written value (0x0000_0064)", rd_data === 32'h0000_0064, $sformatf("Got RDATA=0x%08h", rd_data));

        // 14D: Multi-master access to Encoder
        $display("\n[ENCODER TEST 4] Multi-master access (M0, M2) -> S8 (Encoder)...");
        axi_read(0, ENC_VERSION, 8'h88, 8'h00, rd_data, resp, resp_id);
        check_assert("Encoder: M0 read VERSION returns OKAY", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("Encoder: M0 read VERSION data matches 0x0001_0000", rd_data === 32'h0001_0000, $sformatf("Got RDATA=0x%08h", rd_data));

        axi_read(2, ENC_VERSION, 8'h89, 8'h00, rd_data, resp, resp_id);
        check_assert("Encoder: M2 read VERSION returns OKAY", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("Encoder: M2 read VERSION data matches 0x0001_0000", rd_data === 32'h0001_0000, $sformatf("Got RDATA=0x%08h", rd_data));

        // 14E: Invalid aperture offset validation (confirming SLVERR)
        $display("\n[ENCODER TEST 5] Invalid aperture offset rejection (addr[11:8] != 0)...");
        axi_write(1, 32'h4003_D100, 32'hBAD0_0001, 8'h8A, 8'h00, 4'hF, resp, resp_id);
        check_assert("Encoder: Write to invalid offset 0x100 returns SLVERR", resp === 2'b10, $sformatf("Got BRESP=%b (expected 2'b10 SLVERR)", resp));
        axi_read(1, 32'h4003_D100, 8'h8B, 8'h00, rd_data, resp, resp_id);
        check_assert("Encoder: Read from invalid offset 0x100 returns SLVERR", resp === 2'b10, $sformatf("Got RRESP=%b (expected 2'b10 SLVERR)", resp));

        // Offset > 0x30 within page 0
        axi_write(1, 32'h4003_D040, 32'hBAD0_0002, 8'h8C, 8'h00, 4'hF, resp, resp_id);
        check_assert("Encoder: Write to out-of-range offset 0x040 returns SLVERR", resp === 2'b10, $sformatf("Got BRESP=%b (expected 2'b10 SLVERR)", resp));
        axi_read(1, 32'h4003_D040, 8'h8D, 8'h00, rd_data, resp, resp_id);
        check_assert("Encoder: Read from out-of-range offset 0x040 returns SLVERR", resp === 2'b10, $sformatf("Got RRESP=%b (expected 2'b10 SLVERR)", resp));

        // ============================================================
        // TEST 15: PID Controller Tests (S9 / m09_axi)
        // ============================================================
        $display("\n================================================================================");
        $display("       PID S9 TESTS: AXI Master -> Interconnect -> S9 -> PID Controller      ");
        $display("================================================================================");
        // 15A: Read-only VERSION register (0x4003_F034)
        $display("\n[PID TEST 1] Read/Write-ignore on VERSION register (0x4003_F034)...");
        axi_read(1, PID_VERSION, 8'h91, 8'h00, rd_data, resp, resp_id);
        check_assert("PID: Read VERSION returns OKAY", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("PID: VERSION ID matches 0x0001_0000", rd_data === 32'h0001_0000, $sformatf("Got RDATA=0x%08h", rd_data));

        // Write to RO VERSION register: rejected with SLVERR per PID AXI slave specification
        axi_write(1, PID_VERSION, 32'hDEAD_BEEF, 8'h92, 8'h00, 4'hF, resp, resp_id);
        check_assert("PID: Write to RO VERSION returns SLVERR", resp === 2'b10, $sformatf("Got BRESP=%b (expected 2'b10 SLVERR)", resp));
        axi_read(1, PID_VERSION, 8'h93, 8'h00, rd_data, resp, resp_id);
        check_assert("PID: VERSION remains 0x0001_0000 after write attempt", rd_data === 32'h0001_0000, $sformatf("Got RDATA=0x%08h", rd_data));

        // 15B: Safe RW register KP (0x4003_F004)
        $display("\n[PID TEST 2] Write/Readback on KP register (0x4003_F004)...");
        axi_write(1, PID_KP, 32'h0000_0100, 8'h94, 8'h00, 4'hF, resp, resp_id);
        check_assert("PID: Write KP returns OKAY", resp === 2'b00, $sformatf("Got BRESP=%b", resp));
        axi_read(1, PID_KP, 8'h95, 8'h00, rd_data, resp, resp_id);
        check_assert("PID: Read KP returns OKAY", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("PID: KP readback matches written value (0x0000_0100)", rd_data === 32'h0000_0100, $sformatf("Got RDATA=0x%08h", rd_data));

        // 15C: Safe RW register KI (0x4003_F008)
        $display("\n[PID TEST 3] Write/Readback on KI register (0x4003_F008)...");
        axi_write(1, PID_KI, 32'h0000_0020, 8'h96, 8'h00, 4'hF, resp, resp_id);
        check_assert("PID: Write KI returns OKAY", resp === 2'b00, $sformatf("Got BRESP=%b", resp));
        axi_read(1, PID_KI, 8'h97, 8'h00, rd_data, resp, resp_id);
        check_assert("PID: Read KI returns OKAY", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("PID: KI readback matches written value (0x0000_0020)", rd_data === 32'h0000_0020, $sformatf("Got RDATA=0x%08h", rd_data));

        // 15D: Safe RW register KD (0x4003_F00C)
        $display("\n[PID TEST 4] Write/Readback on KD register (0x4003_F00C)...");
        axi_write(1, PID_KD, 32'h0000_0010, 8'h98, 8'h00, 4'hF, resp, resp_id);
        check_assert("PID: Write KD returns OKAY", resp === 2'b00, $sformatf("Got BRESP=%b", resp));
        axi_read(1, PID_KD, 8'h99, 8'h00, rd_data, resp, resp_id);
        check_assert("PID: Read KD returns OKAY", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("PID: KD readback matches written value (0x0000_0010)", rd_data === 32'h0000_0010, $sformatf("Got RDATA=0x%08h", rd_data));

        // 15E: Multi-master access to PID
        $display("\n[PID TEST 5] Multi-master access (M0, M2) -> S9 (PID)...");
        axi_read(0, PID_VERSION, 8'h9A, 8'h00, rd_data, resp, resp_id);
        check_assert("PID: M0 read VERSION returns OKAY", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("PID: M0 read VERSION data matches 0x0001_0000", rd_data === 32'h0001_0000, $sformatf("Got RDATA=0x%08h", rd_data));

        axi_read(2, PID_VERSION, 8'h9B, 8'h00, rd_data, resp, resp_id);
        check_assert("PID: M2 read VERSION returns OKAY", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("PID: M2 read VERSION data matches 0x0001_0000", rd_data === 32'h0001_0000, $sformatf("Got RDATA=0x%08h", rd_data));

        // 15F: Invalid aperture offset validation (confirming SLVERR)
        $display("\n[PID TEST 6] Invalid aperture offset rejection (addr[11:8] != 0)...");
        axi_write(1, 32'h4003_F100, 32'hBAD0_0001, 8'h9C, 8'h00, 4'hF, resp, resp_id);
        check_assert("PID: Write to invalid offset 0x100 returns SLVERR", resp === 2'b10, $sformatf("Got BRESP=%b (expected 2'b10 SLVERR)", resp));
        axi_read(1, 32'h4003_F100, 8'h9D, 8'h00, rd_data, resp, resp_id);
        check_assert("PID: Read from invalid offset 0x100 returns SLVERR", resp === 2'b10, $sformatf("Got RRESP=%b (expected 2'b10 SLVERR)", resp));

        // Offset > 0x34 within page 0
        axi_write(1, 32'h4003_F040, 32'hBAD0_0002, 8'h9E, 8'h00, 4'hF, resp, resp_id);
        check_assert("PID: Write to out-of-range offset 0x040 returns SLVERR", resp === 2'b10, $sformatf("Got BRESP=%b (expected 2'b10 SLVERR)", resp));
        axi_read(1, 32'h4003_F040, 8'h9F, 8'h00, rd_data, resp, resp_id);
        check_assert("PID: Read from out-of-range offset 0x040 returns SLVERR", resp === 2'b10, $sformatf("Got RRESP=%b (expected 2'b10 SLVERR)", resp));

        // ============================================================
        // TEST 16: PWM Peripheral Tests (S10 / m10_axi)
        // ============================================================
        $display("\n================================================================================");
        $display("       PWM S10 TESTS: AXI Master -> Interconnect -> S10 -> PWM               ");
        $display("================================================================================");

        // 16A: Write duty register (PWM_REG0) via interconnect S10 (0x4004_1000)
        $display("\n[PWM TEST 1] Write duty cycle register (0x4004_1000) via M1 -> S10 -> PWM...");
        axi_write(1, PWM_REG0, 32'h0000_0080, 8'hE1, 8'h00, 4'hF, resp, resp_id);
        check_assert("PWM Test1: Write 0x80 to 0x4004_1000 Returns OKAY (BRESP=2'b00)", resp === 2'b00, $sformatf("Got BRESP=%b", resp));

        repeat (5) @(posedge clk);
        $display("[PWM Test1] PWM_OUT_tb = %b at time %0t", PWM_OUT_tb, $time);

        // 16B: Read duty register back (0x4004_1000)
        $display("\n[PWM TEST 2] Read duty cycle register (0x4004_1000) via M1 -> S10 -> PWM...");
        axi_read(1, PWM_REG0, 8'hE2, 8'h00, rd_data, resp, resp_id);
        check_assert("PWM Test2: Read 0x4004_1000 Returns OKAY (RRESP=2'b00)", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("PWM Test2: RDATA[7:0] matches written value 0x80", rd_data[7:0] === 8'h80, $sformatf("Got RDATA[7:0]=0x%02h (expected 0x80)", rd_data[7:0]));

        // 16C: Test remaining PWM registers (PWM_REG1, PWM_REG2, PWM_REG3)
        $display("\n[PWM TEST 3] Test remaining PWM registers (0x4004_1004, 0x4004_1008, 0x4004_100C)...");
        axi_write(1, PWM_REG1, 32'hDEAD_BE01, 8'hE3, 8'h00, 4'hF, resp, resp_id);
        check_assert("PWM Test3: Write PWM_REG1 Returns OKAY", resp === 2'b00, $sformatf("Got BRESP=%b", resp));
        axi_read(1, PWM_REG1, 8'hE4, 8'h00, rd_data, resp, resp_id);
        check_assert("PWM Test3: Read PWM_REG1 Returns OKAY", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("PWM Test3: Read PWM_REG1 data matches (0xDEAD_BE01)", rd_data === 32'hDEAD_BE01, $sformatf("Got RDATA=0x%08h", rd_data));

        axi_write(1, PWM_REG2, 32'hCAFE_0002, 8'hE5, 8'h00, 4'hF, resp, resp_id);
        check_assert("PWM Test3: Write PWM_REG2 Returns OKAY", resp === 2'b00, $sformatf("Got BRESP=%b", resp));
        axi_read(1, PWM_REG2, 8'hE6, 8'h00, rd_data, resp, resp_id);
        check_assert("PWM Test3: Read PWM_REG2 Returns OKAY", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("PWM Test3: Read PWM_REG2 data matches (0xCAFE_0002)", rd_data === 32'hCAFE_0002, $sformatf("Got RDATA=0x%08h", rd_data));

        axi_write(1, PWM_REG3, 32'h1234_5603, 8'hE7, 8'h00, 4'hF, resp, resp_id);
        check_assert("PWM Test3: Write PWM_REG3 Returns OKAY", resp === 2'b00, $sformatf("Got BRESP=%b", resp));
        axi_read(1, PWM_REG3, 8'hE8, 8'h00, rd_data, resp, resp_id);
        check_assert("PWM Test3: Read PWM_REG3 Returns OKAY", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("PWM Test3: Read PWM_REG3 data matches (0x1234_5603)", rd_data === 32'h1234_5603, $sformatf("Got RDATA=0x%08h", rd_data));

        // 16D: Boundary within S10 range
        $display("\n[PWM TEST 4] S10 Address range & boundary verification...");
        axi_write(1, 32'h4004_1FFC, 32'hA5A5_A5A5, 8'hF1, 8'h00, 4'hF, resp, resp_id);
        check_assert("PWM Test4: Write 0x4004_1FFC (last word in S10 aperture) Returns OKAY", resp === 2'b00, $sformatf("Got BRESP=%b", resp));

        // 16E: Master routing - verify M0, M1, M2 all reach S10
        $display("\n[PWM TEST 5] Master routing - verify M0, M1, M2 all reach PWM S10...");
        axi_write(1, PWM_REG0, 32'h0000_0040, 8'hF5, 8'h00, 4'hF, resp, resp_id);
        check_assert("PWM Test5: M1 -> S10 write returns OKAY", resp === 2'b00, $sformatf("Got BRESP=%b", resp));
        axi_read(1, PWM_REG0, 8'hF6, 8'h00, rd_data, resp, resp_id);
        check_assert("PWM Test5: M1 -> S10 read returns OKAY", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("PWM Test5: M1 -> S10 read data matches 0x40", rd_data[7:0] === 8'h40, $sformatf("Got RDATA[7:0]=0x%02h", rd_data[7:0]));

        axi_write(0, PWM_REG0, 32'h0000_0020, 8'hF7, 8'h00, 4'hF, resp, resp_id);
        check_assert("PWM Test5: M0 -> S10 write returns OKAY", resp === 2'b00, $sformatf("Got BRESP=%b", resp));
        axi_read(0, PWM_REG0, 8'hF8, 8'h00, rd_data, resp, resp_id);
        check_assert("PWM Test5: M0 -> S10 read returns OKAY", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("PWM Test5: M0 -> S10 read data matches 0x20", rd_data[7:0] === 8'h20, $sformatf("Got RDATA[7:0]=0x%02h", rd_data[7:0]));

        axi_write(2, PWM_REG0, 32'h0000_00FF, 8'hF9, 8'h00, 4'hF, resp, resp_id);
        check_assert("PWM Test5: M2 -> S10 write returns OKAY", resp === 2'b00, $sformatf("Got BRESP=%b", resp));
        axi_read(2, PWM_REG0, 8'hFA, 8'h00, rd_data, resp, resp_id);
        check_assert("PWM Test5: M2 -> S10 read returns OKAY", resp === 2'b00, $sformatf("Got RRESP=%b", resp));
        check_assert("PWM Test5: M2 -> S10 read data matches 0xFF", rd_data[7:0] === 8'hFF, $sformatf("Got RDATA[7:0]=0x%02h", rd_data[7:0]));

        // 16F: Independent AW/W channel arrivals on PWM slave
        $display("\n================================================================================");
        $display("  PWM AXI4-Lite Independent AW/W Channel Arrival Tests                         ");
        $display("================================================================================");
        $display("\n[PWM AW/W CASE 1] AW-before-W: AW to 0x4004_1000 arrives 8 cycles before W...");
        axi_write_aw_before_w(1, PWM_REG0, 32'h0000_00AA, 8, resp);
        check_assert("PWM AW/W Case1 (AW-before-W): Write completes OKAY", resp === 2'b00, $sformatf("Got BRESP=%b", resp));
        axi_read(1, PWM_REG0, 8'hC1, 8'h00, rd_data, resp, resp_id);
        check_assert("PWM AW/W Case1: Readback data matches 0xAA", rd_data[7:0] === 8'hAA, $sformatf("Got RDATA[7:0]=0x%02h", rd_data[7:0]));

        $display("\n[PWM AW/W CASE 2] W-before-AW: W to 0x4004_1004 arrives 8 cycles before AW...");
        axi_write_w_before_aw(1, PWM_REG1, 32'h0000_00BB, 8, resp);
        check_assert("PWM AW/W Case2 (W-before-AW): Write completes OKAY", resp === 2'b00, $sformatf("Got BRESP=%b", resp));
        axi_read(1, PWM_REG1, 8'hC2, 8'h00, rd_data, resp, resp_id);
        check_assert("PWM AW/W Case2: Readback data matches 0xBB", rd_data[7:0] === 8'hBB, $sformatf("Got RDATA[7:0]=0x%02h", rd_data[7:0]));

        $display("\n[PWM AW/W CASE 3] Simultaneous AW+W to 0x4004_1008...");
        axi_write(1, PWM_REG2, 32'h0000_00CC, 8'hC3, 8'h00, 4'hF, resp, resp_id);
        check_assert("PWM AW/W Case3 (Simultaneous): Write completes OKAY", resp === 2'b00, $sformatf("Got BRESP=%b", resp));
        axi_read(1, PWM_REG2, 8'hC4, 8'h00, rd_data, resp, resp_id);
        check_assert("PWM AW/W Case3: Readback data matches 0xCC", rd_data[7:0] === 8'hCC, $sformatf("Got RDATA[7:0]=0x%02h", rd_data[7:0]));

        $display("\n[PWM STEP COMPLETE] All AW/W independent-channel tests finished.");

        // ------------------------------------------------------------
        // FINAL VERIFICATION SUMMARY SCOREBOARD
        // ------------------------------------------------------------
        repeat (50) @(posedge clk);
        $display("\n================================================================================");
        $display("                         VERIFICATION SCOREBOARD SUMMARY                        ");
        $display("================================================================================");
        $display("  TOTAL CHECKS  : %0d", total_tests);
        $display("  PASSED CHECKS : %0d", passed_tests);
        $display("  FAILED CHECKS : %0d", failed_tests);
        $display("--------------------------------------------------------------------------------");
        if (failed_tests == 0) begin
            $display("  >>> STATUS: ALL TESTS PASSED SUCCESSFULLY! 100%% VERIFIED. <<<");
        end else begin
            $display("  >>> STATUS: VERIFICATION FAILED WITH %0d ERRORS! <<<", failed_tests);
        end
        $display("================================================================================\n");

        $finish;
    end

    // Safety simulation timeout watchdog
    initial begin
        #500_000; // 500 us simulation time limit
        $display("\n[FATAL ERROR] Simulation Watchdog Timeout reached! Terminating simulation.");
        $finish;
    end

endmodule

`default_nettype wire
