/*
================================================================================
 Project        : Fail-Safe Railway Level-Crossing Control System (Honours CBP)
 Module         : main_top
 Description    : System Top-Level Module integrating 3-Master x 15-Slave AXI4
                  interconnect and direct S4 UART connection.

 Architecture:
   - Masters:
       M0 = VeeR EL2 IFU (s00_axi)
       M1 = VeeR EL2 LSU (s01_axi)
       M2 = DMA Controller (s02_axi)
   - Slaves:
       S0  = Instruction Memory (m00_axi) [0x0004_0000 - 0x0005_FFFF]
       S1  = Data Memory        (m01_axi) [0x0008_0000 - 0x0009_FFFF]
       S2  = GPIO Controller    (m02_axi) [0x8000_1000 - 0x8000_1FFF]
       S3  = Real-Time Timer    (m03_axi) [0x8000_2000 - 0x8000_2FFF]
       S4  = UART Subsystem     (internal to axi_uart_top) [0x8000_3000 - 0x8000_3FFF]
       S5  = Encoder Interface  (m05_axi)
       S6  = PID Controller     (m06_axi)
       S7  = PWM Generator      (m07_axi)
       S8  = Keypad Controller  (m08_axi)
       S9  = Authentication     (m09_axi)
       S10 = PWM / Buzzer       (m10_axi)
       S11 = Watchdog Timer     (m11_axi) [0x8000_4000 - 0x8000_4FFF]
       S12 = ADC Interface      (m12_axi) [0x8000_5000 - 0x8000_5FFF]
       S13 = DMA Registers      (m13_axi) [0x8000_6000 - 0x8000_6FFF]
       S14 = Seven-Segment Disp (m14_axi)
================================================================================
*/

`timescale 1ns / 1ps
`default_nettype none

module main_top #(
    parameter DATA_WIDTH      = 32,
    parameter ADDR_WIDTH      = 32,
    parameter STRB_WIDTH      = (DATA_WIDTH/8),
    parameter ID_WIDTH        = 8,
    parameter AWUSER_ENABLE   = 0,
    parameter AWUSER_WIDTH    = 1,
    parameter WUSER_ENABLE    = 0,
    parameter WUSER_WIDTH     = 1,
    parameter BUSER_ENABLE    = 0,
    parameter BUSER_WIDTH     = 1,
    parameter ARUSER_ENABLE   = 0,
    parameter ARUSER_WIDTH    = 1,
    parameter RUSER_ENABLE    = 0,
    parameter RUSER_WIDTH     = 1,

    // ------------------------------------------------------------
    // Documented Project Base Addresses & Apertures
    // ------------------------------------------------------------
    parameter M00_BASE_ADDR   = 32'h4000_0000,          // S0:  IMEM
    parameter M00_ADDR_WIDTH  = 32'd16,                 // 64 KB (0x4000_0000 - 0x4000_FFFF)

    parameter M01_BASE_ADDR   = 32'h4002_0000,          // S1:  DMEM
    parameter M01_ADDR_WIDTH  = 32'd16,                 // 64 KB (0x4002_0000 - 0x4002_FFFF)

    parameter M02_BASE_ADDR   = 32'h4003_1000,          // S2:  GPIO
    parameter M02_ADDR_WIDTH  = 32'd12,                 // 4 KB (0x4003_1000 - 0x4003_1FFF)

    parameter M03_BASE_ADDR   = 32'h4003_3000,          // S3:  Timer
    parameter M03_ADDR_WIDTH  = 32'd12,                 // 4 KB (0x4003_3000 - 0x4003_3FFF)

    parameter M04_BASE_ADDR   = 32'h4003_5000,          // S4:  UART (TARGET)
    parameter M04_ADDR_WIDTH  = 32'd12,                 // 4 KB (0x4003_5000 - 0x4003_5FFF)

    // Unassigned peripherals structurally available (disabled with width=0 by default)
    parameter M05_BASE_ADDR   = 32'h0000_0000,          // S5:  Reserved / Disabled
    parameter M05_ADDR_WIDTH  = 32'd0,

    parameter M06_BASE_ADDR   = 32'h0000_0000,          // S6:  Reserved / Disabled
    parameter M06_ADDR_WIDTH  = 32'd0,

    parameter M07_BASE_ADDR   = 32'h0000_0000,          // S7:  Reserved / Disabled
    parameter M07_ADDR_WIDTH  = 32'd0,

    parameter M08_BASE_ADDR   = 32'h4003_D000,          // S8:  Quadrature Encoder
    parameter M08_ADDR_WIDTH  = 32'd12,                 // 4 KB (0x4003_D000 - 0x4003_DFFF)

    parameter M09_BASE_ADDR   = 32'h4003_F000,          // S9:  PID Controller
    parameter M09_ADDR_WIDTH  = 32'd12,                 // 4 KB (0x4003_F000 - 0x4003_FFFF)

    parameter M10_BASE_ADDR   = 32'h4004_1000,          // S10: PWM [0x4004_1000 - 0x4004_1FFF]
    parameter M10_ADDR_WIDTH  = 32'd12,                 // 4 KB

    parameter M11_BASE_ADDR   = 32'h0000_0000,          // S11: Reserved / Disabled
    parameter M11_ADDR_WIDTH  = 32'd0,

    parameter M12_BASE_ADDR   = 32'h0000_0000,          // S12: Reserved / Disabled
    parameter M12_ADDR_WIDTH  = 32'd0,

    parameter M13_BASE_ADDR   = 32'h0000_0000,          // S13: Reserved / Disabled
    parameter M13_ADDR_WIDTH  = 32'd0,

    parameter M14_BASE_ADDR   = 32'h0000_0000,          // S14: Seven-Segment Display
    parameter M14_ADDR_WIDTH  = 32'd0
)
(
    // ------------------------------------------------------------
    // Clocks and Resets
    // ------------------------------------------------------------
    input  wire                     clk,            // AXI system clock
    input  wire                     fixed_clk,      // Dedicated UART baud clock
    input  wire                     rst,            // Active-high synchronous reset

    // ------------------------------------------------------------
    // Dedicated UART External Pins & Interrupt
    // ------------------------------------------------------------
    input  wire                     uart_rx,
    output wire                     uart_tx,
    output wire                     uart_irq,

    // >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    // >>> PWM S10 INTEGRATION - ADDED CODE - BEGIN
    // >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    // S10: PWM functional output
    output wire                     PWM_OUT,

    // S2: GPIO functional IO & interrupt
    inout  wire [31:0]              gpio_io,
    output wire                     gpio_intr,

    // S3: Timer functional IO & interrupt
    input  wire                     timer_ext_meas,
    input  wire                     timer_capture,
    output wire                     timer_pwm,
    output wire                     timer_trigger,
    output wire                     timer_intr,

    // S8: Quadrature Encoder functional IO & sidebands
    input  wire                     enc_a,
    input  wire                     enc_b,
    input  wire                     enc_index,
    input  wire                     enc_drive_active,
    output wire [15:0]              enc_speed,
    output wire                     enc_speed_valid,
    output wire                     enc_count_valid,
    output wire                     enc_dir,
    output wire                     enc_fault,
    output wire                     enc_intr,

    // S9: PID Controller functional IO & interrupt
    output wire [15:0]              pid_out,
    output wire                     pid_out_valid,
    output wire                     pid_sat_flag,
    output wire                     pid_intr,

    // ============================================================
    // Master Interfaces (Inputs to Interconnect)
    // ============================================================
    // M0: VeeR EL2 IFU
    input  wire [ID_WIDTH-1:0]      s00_axi_awid,
    input  wire [ADDR_WIDTH-1:0]    s00_axi_awaddr,
    input  wire [7:0]               s00_axi_awlen,
    input  wire [2:0]               s00_axi_awsize,
    input  wire [1:0]               s00_axi_awburst,
    input  wire                     s00_axi_awlock,
    input  wire [3:0]               s00_axi_awcache,
    input  wire [2:0]               s00_axi_awprot,
    input  wire [3:0]               s00_axi_awqos,
    input  wire [AWUSER_WIDTH-1:0]  s00_axi_awuser,
    input  wire                     s00_axi_awvalid,
    output wire                     s00_axi_awready,
    input  wire [DATA_WIDTH-1:0]    s00_axi_wdata,
    input  wire [STRB_WIDTH-1:0]    s00_axi_wstrb,
    input  wire                     s00_axi_wlast,
    input  wire [WUSER_WIDTH-1:0]   s00_axi_wuser,
    input  wire                     s00_axi_wvalid,
    output wire                     s00_axi_wready,
    output wire [ID_WIDTH-1:0]      s00_axi_bid,
    output wire [1:0]               s00_axi_bresp,
    output wire [BUSER_WIDTH-1:0]   s00_axi_buser,
    output wire                     s00_axi_bvalid,
    input  wire                     s00_axi_bready,
    input  wire [ID_WIDTH-1:0]      s00_axi_arid,
    input  wire [ADDR_WIDTH-1:0]    s00_axi_araddr,
    input  wire [7:0]               s00_axi_arlen,
    input  wire [2:0]               s00_axi_arsize,
    input  wire [1:0]               s00_axi_arburst,
    input  wire                     s00_axi_arlock,
    input  wire [3:0]               s00_axi_arcache,
    input  wire [2:0]               s00_axi_arprot,
    input  wire [3:0]               s00_axi_arqos,
    input  wire [ARUSER_WIDTH-1:0]  s00_axi_aruser,
    input  wire                     s00_axi_arvalid,
    output wire                     s00_axi_arready,
    output wire [ID_WIDTH-1:0]      s00_axi_rid,
    output wire [DATA_WIDTH-1:0]    s00_axi_rdata,
    output wire [1:0]               s00_axi_rresp,
    output wire                     s00_axi_rlast,
    output wire [RUSER_WIDTH-1:0]   s00_axi_ruser,
    output wire                     s00_axi_rvalid,
    input  wire                     s00_axi_rready,

    // M1: VeeR EL2 LSU
    input  wire [ID_WIDTH-1:0]      s01_axi_awid,
    input  wire [ADDR_WIDTH-1:0]    s01_axi_awaddr,
    input  wire [7:0]               s01_axi_awlen,
    input  wire [2:0]               s01_axi_awsize,
    input  wire [1:0]               s01_axi_awburst,
    input  wire                     s01_axi_awlock,
    input  wire [3:0]               s01_axi_awcache,
    input  wire [2:0]               s01_axi_awprot,
    input  wire [3:0]               s01_axi_awqos,
    input  wire [AWUSER_WIDTH-1:0]  s01_axi_awuser,
    input  wire                     s01_axi_awvalid,
    output wire                     s01_axi_awready,
    input  wire [DATA_WIDTH-1:0]    s01_axi_wdata,
    input  wire [STRB_WIDTH-1:0]    s01_axi_wstrb,
    input  wire                     s01_axi_wlast,
    input  wire [WUSER_WIDTH-1:0]   s01_axi_wuser,
    input  wire                     s01_axi_wvalid,
    output wire                     s01_axi_wready,
    output wire [ID_WIDTH-1:0]      s01_axi_bid,
    output wire [1:0]               s01_axi_bresp,
    output wire [BUSER_WIDTH-1:0]   s01_axi_buser,
    output wire                     s01_axi_bvalid,
    input  wire                     s01_axi_bready,
    input  wire [ID_WIDTH-1:0]      s01_axi_arid,
    input  wire [ADDR_WIDTH-1:0]    s01_axi_araddr,
    input  wire [7:0]               s01_axi_arlen,
    input  wire [2:0]               s01_axi_arsize,
    input  wire [1:0]               s01_axi_arburst,
    input  wire                     s01_axi_arlock,
    input  wire [3:0]               s01_axi_arcache,
    input  wire [2:0]               s01_axi_arprot,
    input  wire [3:0]               s01_axi_arqos,
    input  wire [ARUSER_WIDTH-1:0]  s01_axi_aruser,
    input  wire                     s01_axi_arvalid,
    output wire                     s01_axi_arready,
    output wire [ID_WIDTH-1:0]      s01_axi_rid,
    output wire [DATA_WIDTH-1:0]    s01_axi_rdata,
    output wire [1:0]               s01_axi_rresp,
    output wire                     s01_axi_rlast,
    output wire [RUSER_WIDTH-1:0]   s01_axi_ruser,
    output wire                     s01_axi_rvalid,
    input  wire                     s01_axi_rready,

    // M2: DMA Controller
    input  wire [ID_WIDTH-1:0]      s02_axi_awid,
    input  wire [ADDR_WIDTH-1:0]    s02_axi_awaddr,
    input  wire [7:0]               s02_axi_awlen,
    input  wire [2:0]               s02_axi_awsize,
    input  wire [1:0]               s02_axi_awburst,
    input  wire                     s02_axi_awlock,
    input  wire [3:0]               s02_axi_awcache,
    input  wire [2:0]               s02_axi_awprot,
    input  wire [3:0]               s02_axi_awqos,
    input  wire [AWUSER_WIDTH-1:0]  s02_axi_awuser,
    input  wire                     s02_axi_awvalid,
    output wire                     s02_axi_awready,
    input  wire [DATA_WIDTH-1:0]    s02_axi_wdata,
    input  wire [STRB_WIDTH-1:0]    s02_axi_wstrb,
    input  wire                     s02_axi_wlast,
    input  wire [WUSER_WIDTH-1:0]   s02_axi_wuser,
    input  wire                     s02_axi_wvalid,
    output wire                     s02_axi_wready,
    output wire [ID_WIDTH-1:0]      s02_axi_bid,
    output wire [1:0]               s02_axi_bresp,
    output wire [BUSER_WIDTH-1:0]   s02_axi_buser,
    output wire                     s02_axi_bvalid,
    input  wire                     s02_axi_bready,
    input  wire [ID_WIDTH-1:0]      s02_axi_arid,
    input  wire [ADDR_WIDTH-1:0]    s02_axi_araddr,
    input  wire [7:0]               s02_axi_arlen,
    input  wire [2:0]               s02_axi_arsize,
    input  wire [1:0]               s02_axi_arburst,
    input  wire                     s02_axi_arlock,
    input  wire [3:0]               s02_axi_arcache,
    input  wire [2:0]               s02_axi_arprot,
    input  wire [3:0]               s02_axi_arqos,
    input  wire [ARUSER_WIDTH-1:0]  s02_axi_aruser,
    input  wire                     s02_axi_arvalid,
    output wire                     s02_axi_arready,
    output wire [ID_WIDTH-1:0]      s02_axi_rid,
    output wire [DATA_WIDTH-1:0]    s02_axi_rdata,
    output wire [1:0]               s02_axi_rresp,
    output wire                     s02_axi_rlast,
    output wire [RUSER_WIDTH-1:0]   s02_axi_ruser,
    output wire                     s02_axi_rvalid,
    input  wire                     s02_axi_rready,

    // ============================================================
    // Exposed Peripheral/Memory Slave Interfaces (S0..S3, S5..S14)
    // S4 is connected internally to UART.
    // ============================================================
    // S0: IMEM
    output wire [ID_WIDTH-1:0]      m00_axi_awid,
    output wire [ADDR_WIDTH-1:0]    m00_axi_awaddr,
    output wire [7:0]               m00_axi_awlen,
    output wire [2:0]               m00_axi_awsize,
    output wire [1:0]               m00_axi_awburst,
    output wire                     m00_axi_awlock,
    output wire [3:0]               m00_axi_awcache,
    output wire [2:0]               m00_axi_awprot,
    output wire [3:0]               m00_axi_awqos,
    output wire [3:0]               m00_axi_awregion,
    output wire [AWUSER_WIDTH-1:0]  m00_axi_awuser,
    output wire                     m00_axi_awvalid,
    input  wire                     m00_axi_awready,
    output wire [DATA_WIDTH-1:0]    m00_axi_wdata,
    output wire [STRB_WIDTH-1:0]    m00_axi_wstrb,
    output wire                     m00_axi_wlast,
    output wire [WUSER_WIDTH-1:0]   m00_axi_wuser,
    output wire                     m00_axi_wvalid,
    input  wire                     m00_axi_wready,
    input  wire [ID_WIDTH-1:0]      m00_axi_bid,
    input  wire [1:0]               m00_axi_bresp,
    input  wire [BUSER_WIDTH-1:0]   m00_axi_buser,
    input  wire                     m00_axi_bvalid,
    output wire                     m00_axi_bready,
    output wire [ID_WIDTH-1:0]      m00_axi_arid,
    output wire [ADDR_WIDTH-1:0]    m00_axi_araddr,
    output wire [7:0]               m00_axi_arlen,
    output wire [2:0]               m00_axi_arsize,
    output wire [1:0]               m00_axi_arburst,
    output wire                     m00_axi_arlock,
    output wire [3:0]               m00_axi_arcache,
    output wire [2:0]               m00_axi_arprot,
    output wire [3:0]               m00_axi_arqos,
    output wire [3:0]               m00_axi_arregion,
    output wire [ARUSER_WIDTH-1:0]  m00_axi_aruser,
    output wire                     m00_axi_arvalid,
    input  wire                     m00_axi_arready,
    input  wire [ID_WIDTH-1:0]      m00_axi_rid,
    input  wire [DATA_WIDTH-1:0]    m00_axi_rdata,
    input  wire [1:0]               m00_axi_rresp,
    input  wire                     m00_axi_rlast,
    input  wire [RUSER_WIDTH-1:0]   m00_axi_ruser,
    input  wire                     m00_axi_rvalid,
    output wire                     m00_axi_rready,

    // S1: DMEM
    output wire [ID_WIDTH-1:0]      m01_axi_awid,
    output wire [ADDR_WIDTH-1:0]    m01_axi_awaddr,
    output wire [7:0]               m01_axi_awlen,
    output wire [2:0]               m01_axi_awsize,
    output wire [1:0]               m01_axi_awburst,
    output wire                     m01_axi_awlock,
    output wire [3:0]               m01_axi_awcache,
    output wire [2:0]               m01_axi_awprot,
    output wire [3:0]               m01_axi_awqos,
    output wire [3:0]               m01_axi_awregion,
    output wire [AWUSER_WIDTH-1:0]  m01_axi_awuser,
    output wire                     m01_axi_awvalid,
    input  wire                     m01_axi_awready,
    output wire [DATA_WIDTH-1:0]    m01_axi_wdata,
    output wire [STRB_WIDTH-1:0]    m01_axi_wstrb,
    output wire                     m01_axi_wlast,
    output wire [WUSER_WIDTH-1:0]   m01_axi_wuser,
    output wire                     m01_axi_wvalid,
    input  wire                     m01_axi_wready,
    input  wire [ID_WIDTH-1:0]      m01_axi_bid,
    input  wire [1:0]               m01_axi_bresp,
    input  wire [BUSER_WIDTH-1:0]   m01_axi_buser,
    input  wire                     m01_axi_bvalid,
    output wire                     m01_axi_bready,
    output wire [ID_WIDTH-1:0]      m01_axi_arid,
    output wire [ADDR_WIDTH-1:0]    m01_axi_araddr,
    output wire [7:0]               m01_axi_arlen,
    output wire [2:0]               m01_axi_arsize,
    output wire [1:0]               m01_axi_arburst,
    output wire                     m01_axi_arlock,
    output wire [3:0]               m01_axi_arcache,
    output wire [2:0]               m01_axi_arprot,
    output wire [3:0]               m01_axi_arqos,
    output wire [3:0]               m01_axi_arregion,
    output wire [ARUSER_WIDTH-1:0]  m01_axi_aruser,
    output wire                     m01_axi_arvalid,
    input  wire                     m01_axi_arready,
    input  wire [ID_WIDTH-1:0]      m01_axi_rid,
    input  wire [DATA_WIDTH-1:0]    m01_axi_rdata,
    input  wire [1:0]               m01_axi_rresp,
    input  wire                     m01_axi_rlast,
    input  wire [RUSER_WIDTH-1:0]   m01_axi_ruser,
    input  wire                     m01_axi_rvalid,
    output wire                     m01_axi_rready,

    // >>> S2 (GPIO) and S3 (Timer) m02_axi / m03_axi ports removed from module port list.
    // >>> They are now connected to internal peripherals (see internal wire declarations below).


    // S5: Encoder Interface
    output wire [ID_WIDTH-1:0]      m05_axi_awid,
    output wire [ADDR_WIDTH-1:0]    m05_axi_awaddr,
    output wire [7:0]               m05_axi_awlen,
    output wire [2:0]               m05_axi_awsize,
    output wire [1:0]               m05_axi_awburst,
    output wire                     m05_axi_awlock,
    output wire [3:0]               m05_axi_awcache,
    output wire [2:0]               m05_axi_awprot,
    output wire [3:0]               m05_axi_awqos,
    output wire [3:0]               m05_axi_awregion,
    output wire [AWUSER_WIDTH-1:0]  m05_axi_awuser,
    output wire                     m05_axi_awvalid,
    input  wire                     m05_axi_awready,
    output wire [DATA_WIDTH-1:0]    m05_axi_wdata,
    output wire [STRB_WIDTH-1:0]    m05_axi_wstrb,
    output wire                     m05_axi_wlast,
    output wire [WUSER_WIDTH-1:0]   m05_axi_wuser,
    output wire                     m05_axi_wvalid,
    input  wire                     m05_axi_wready,
    input  wire [ID_WIDTH-1:0]      m05_axi_bid,
    input  wire [1:0]               m05_axi_bresp,
    input  wire [BUSER_WIDTH-1:0]   m05_axi_buser,
    input  wire                     m05_axi_bvalid,
    output wire                     m05_axi_bready,
    output wire [ID_WIDTH-1:0]      m05_axi_arid,
    output wire [ADDR_WIDTH-1:0]    m05_axi_araddr,
    output wire [7:0]               m05_axi_arlen,
    output wire [2:0]               m05_axi_arsize,
    output wire [1:0]               m05_axi_arburst,
    output wire                     m05_axi_arlock,
    output wire [3:0]               m05_axi_arcache,
    output wire [2:0]               m05_axi_arprot,
    output wire [3:0]               m05_axi_arqos,
    output wire [3:0]               m05_axi_arregion,
    output wire [ARUSER_WIDTH-1:0]  m05_axi_aruser,
    output wire                     m05_axi_arvalid,
    input  wire                     m05_axi_arready,
    input  wire [ID_WIDTH-1:0]      m05_axi_rid,
    input  wire [DATA_WIDTH-1:0]    m05_axi_rdata,
    input  wire [1:0]               m05_axi_rresp,
    input  wire                     m05_axi_rlast,
    input  wire [RUSER_WIDTH-1:0]   m05_axi_ruser,
    input  wire                     m05_axi_rvalid,
    output wire                     m05_axi_rready,

    // S6: PID Controller
    output wire [ID_WIDTH-1:0]      m06_axi_awid,
    output wire [ADDR_WIDTH-1:0]    m06_axi_awaddr,
    output wire [7:0]               m06_axi_awlen,
    output wire [2:0]               m06_axi_awsize,
    output wire [1:0]               m06_axi_awburst,
    output wire                     m06_axi_awlock,
    output wire [3:0]               m06_axi_awcache,
    output wire [2:0]               m06_axi_awprot,
    output wire [3:0]               m06_axi_awqos,
    output wire [3:0]               m06_axi_awregion,
    output wire [AWUSER_WIDTH-1:0]  m06_axi_awuser,
    output wire                     m06_axi_awvalid,
    input  wire                     m06_axi_awready,
    output wire [DATA_WIDTH-1:0]    m06_axi_wdata,
    output wire [STRB_WIDTH-1:0]    m06_axi_wstrb,
    output wire                     m06_axi_wlast,
    output wire [WUSER_WIDTH-1:0]   m06_axi_wuser,
    output wire                     m06_axi_wvalid,
    input  wire                     m06_axi_wready,
    input  wire [ID_WIDTH-1:0]      m06_axi_bid,
    input  wire [1:0]               m06_axi_bresp,
    input  wire [BUSER_WIDTH-1:0]   m06_axi_buser,
    input  wire                     m06_axi_bvalid,
    output wire                     m06_axi_bready,
    output wire [ID_WIDTH-1:0]      m06_axi_arid,
    output wire [ADDR_WIDTH-1:0]    m06_axi_araddr,
    output wire [7:0]               m06_axi_arlen,
    output wire [2:0]               m06_axi_arsize,
    output wire [1:0]               m06_axi_arburst,
    output wire                     m06_axi_arlock,
    output wire [3:0]               m06_axi_arcache,
    output wire [2:0]               m06_axi_arprot,
    output wire [3:0]               m06_axi_arqos,
    output wire [3:0]               m06_axi_arregion,
    output wire [ARUSER_WIDTH-1:0]  m06_axi_aruser,
    output wire                     m06_axi_arvalid,
    input  wire                     m06_axi_arready,
    input  wire [ID_WIDTH-1:0]      m06_axi_rid,
    input  wire [DATA_WIDTH-1:0]    m06_axi_rdata,
    input  wire [1:0]               m06_axi_rresp,
    input  wire                     m06_axi_rlast,
    input  wire [RUSER_WIDTH-1:0]   m06_axi_ruser,
    input  wire                     m06_axi_rvalid,
    output wire                     m06_axi_rready,

    // S7: PWM Generator
    output wire [ID_WIDTH-1:0]      m07_axi_awid,
    output wire [ADDR_WIDTH-1:0]    m07_axi_awaddr,
    output wire [7:0]               m07_axi_awlen,
    output wire [2:0]               m07_axi_awsize,
    output wire [1:0]               m07_axi_awburst,
    output wire                     m07_axi_awlock,
    output wire [3:0]               m07_axi_awcache,
    output wire [2:0]               m07_axi_awprot,
    output wire [3:0]               m07_axi_awqos,
    output wire [3:0]               m07_axi_awregion,
    output wire [AWUSER_WIDTH-1:0]  m07_axi_awuser,
    output wire                     m07_axi_awvalid,
    input  wire                     m07_axi_awready,
    output wire [DATA_WIDTH-1:0]    m07_axi_wdata,
    output wire [STRB_WIDTH-1:0]    m07_axi_wstrb,
    output wire                     m07_axi_wlast,
    output wire [WUSER_WIDTH-1:0]   m07_axi_wuser,
    output wire                     m07_axi_wvalid,
    input  wire                     m07_axi_wready,
    input  wire [ID_WIDTH-1:0]      m07_axi_bid,
    input  wire [1:0]               m07_axi_bresp,
    input  wire [BUSER_WIDTH-1:0]   m07_axi_buser,
    input  wire                     m07_axi_bvalid,
    output wire                     m07_axi_bready,
    output wire [ID_WIDTH-1:0]      m07_axi_arid,
    output wire [ADDR_WIDTH-1:0]    m07_axi_araddr,
    output wire [7:0]               m07_axi_arlen,
    output wire [2:0]               m07_axi_arsize,
    output wire [1:0]               m07_axi_arburst,
    output wire                     m07_axi_arlock,
    output wire [3:0]               m07_axi_arcache,
    output wire [2:0]               m07_axi_arprot,
    output wire [3:0]               m07_axi_arqos,
    output wire [3:0]               m07_axi_arregion,
    output wire [ARUSER_WIDTH-1:0]  m07_axi_aruser,
    output wire                     m07_axi_arvalid,
    input  wire                     m07_axi_arready,
    input  wire [ID_WIDTH-1:0]      m07_axi_rid,
    input  wire [DATA_WIDTH-1:0]    m07_axi_rdata,
    input  wire [1:0]               m07_axi_rresp,
    input  wire                     m07_axi_rlast,
    input  wire [RUSER_WIDTH-1:0]   m07_axi_ruser,
    input  wire                     m07_axi_rvalid,
    output wire                     m07_axi_rready,

    // >>> S8 (Encoder) and S9 (PID) m08_axi / m09_axi ports removed from module port list.
    // >>> They are now connected to internal peripherals (see internal wire declarations below).


    // >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    // >>> PWM S10 INTEGRATION - MODIFIED EXISTING CODE - BEGIN
    // >>> S10 m10_axi ports removed from module port list.
    // >>> They are now internal wires (see internal wire declarations below).
    // <<< PWM S10 INTEGRATION - MODIFIED EXISTING CODE - END
    // <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    // S11: Watchdog Timer
    output wire [ID_WIDTH-1:0]      m11_axi_awid,
    output wire [ADDR_WIDTH-1:0]    m11_axi_awaddr,
    output wire [7:0]               m11_axi_awlen,
    output wire [2:0]               m11_axi_awsize,
    output wire [1:0]               m11_axi_awburst,
    output wire                     m11_axi_awlock,
    output wire [3:0]               m11_axi_awcache,
    output wire [2:0]               m11_axi_awprot,
    output wire [3:0]               m11_axi_awqos,
    output wire [3:0]               m11_axi_awregion,
    output wire [AWUSER_WIDTH-1:0]  m11_axi_awuser,
    output wire                     m11_axi_awvalid,
    input  wire                     m11_axi_awready,
    output wire [DATA_WIDTH-1:0]    m11_axi_wdata,
    output wire [STRB_WIDTH-1:0]    m11_axi_wstrb,
    output wire                     m11_axi_wlast,
    output wire [WUSER_WIDTH-1:0]   m11_axi_wuser,
    output wire                     m11_axi_wvalid,
    input  wire                     m11_axi_wready,
    input  wire [ID_WIDTH-1:0]      m11_axi_bid,
    input  wire [1:0]               m11_axi_bresp,
    input  wire [BUSER_WIDTH-1:0]   m11_axi_buser,
    input  wire                     m11_axi_bvalid,
    output wire                     m11_axi_bready,
    output wire [ID_WIDTH-1:0]      m11_axi_arid,
    output wire [ADDR_WIDTH-1:0]    m11_axi_araddr,
    output wire [7:0]               m11_axi_arlen,
    output wire [2:0]               m11_axi_arsize,
    output wire [1:0]               m11_axi_arburst,
    output wire                     m11_axi_arlock,
    output wire [3:0]               m11_axi_arcache,
    output wire [2:0]               m11_axi_arprot,
    output wire [3:0]               m11_axi_arqos,
    output wire [3:0]               m11_axi_arregion,
    output wire [ARUSER_WIDTH-1:0]  m11_axi_aruser,
    output wire                     m11_axi_arvalid,
    input  wire                     m11_axi_arready,
    input  wire [ID_WIDTH-1:0]      m11_axi_rid,
    input  wire [DATA_WIDTH-1:0]    m11_axi_rdata,
    input  wire [1:0]               m11_axi_rresp,
    input  wire                     m11_axi_rlast,
    input  wire [RUSER_WIDTH-1:0]   m11_axi_ruser,
    input  wire                     m11_axi_rvalid,
    output wire                     m11_axi_rready,

    // S12: ADC Interface
    output wire [ID_WIDTH-1:0]      m12_axi_awid,
    output wire [ADDR_WIDTH-1:0]    m12_axi_awaddr,
    output wire [7:0]               m12_axi_awlen,
    output wire [2:0]               m12_axi_awsize,
    output wire [1:0]               m12_axi_awburst,
    output wire                     m12_axi_awlock,
    output wire [3:0]               m12_axi_awcache,
    output wire [2:0]               m12_axi_awprot,
    output wire [3:0]               m12_axi_awqos,
    output wire [3:0]               m12_axi_awregion,
    output wire [AWUSER_WIDTH-1:0]  m12_axi_awuser,
    output wire                     m12_axi_awvalid,
    input  wire                     m12_axi_awready,
    output wire [DATA_WIDTH-1:0]    m12_axi_wdata,
    output wire [STRB_WIDTH-1:0]    m12_axi_wstrb,
    output wire                     m12_axi_wlast,
    output wire [WUSER_WIDTH-1:0]   m12_axi_wuser,
    output wire                     m12_axi_wvalid,
    input  wire                     m12_axi_wready,
    input  wire [ID_WIDTH-1:0]      m12_axi_bid,
    input  wire [1:0]               m12_axi_bresp,
    input  wire [BUSER_WIDTH-1:0]   m12_axi_buser,
    input  wire                     m12_axi_bvalid,
    output wire                     m12_axi_bready,
    output wire [ID_WIDTH-1:0]      m12_axi_arid,
    output wire [ADDR_WIDTH-1:0]    m12_axi_araddr,
    output wire [7:0]               m12_axi_arlen,
    output wire [2:0]               m12_axi_arsize,
    output wire [1:0]               m12_axi_arburst,
    output wire                     m12_axi_arlock,
    output wire [3:0]               m12_axi_arcache,
    output wire [2:0]               m12_axi_arprot,
    output wire [3:0]               m12_axi_arqos,
    output wire [3:0]               m12_axi_arregion,
    output wire [ARUSER_WIDTH-1:0]  m12_axi_aruser,
    output wire                     m12_axi_arvalid,
    input  wire                     m12_axi_arready,
    input  wire [ID_WIDTH-1:0]      m12_axi_rid,
    input  wire [DATA_WIDTH-1:0]    m12_axi_rdata,
    input  wire [1:0]               m12_axi_rresp,
    input  wire                     m12_axi_rlast,
    input  wire [RUSER_WIDTH-1:0]   m12_axi_ruser,
    input  wire                     m12_axi_rvalid,
    output wire                     m12_axi_rready,

    // S13: DMA Registers
    output wire [ID_WIDTH-1:0]      m13_axi_awid,
    output wire [ADDR_WIDTH-1:0]    m13_axi_awaddr,
    output wire [7:0]               m13_axi_awlen,
    output wire [2:0]               m13_axi_awsize,
    output wire [1:0]               m13_axi_awburst,
    output wire                     m13_axi_awlock,
    output wire [3:0]               m13_axi_awcache,
    output wire [2:0]               m13_axi_awprot,
    output wire [3:0]               m13_axi_awqos,
    output wire [3:0]               m13_axi_awregion,
    output wire [AWUSER_WIDTH-1:0]  m13_axi_awuser,
    output wire                     m13_axi_awvalid,
    input  wire                     m13_axi_awready,
    output wire [DATA_WIDTH-1:0]    m13_axi_wdata,
    output wire [STRB_WIDTH-1:0]    m13_axi_wstrb,
    output wire                     m13_axi_wlast,
    output wire [WUSER_WIDTH-1:0]   m13_axi_wuser,
    output wire                     m13_axi_wvalid,
    input  wire                     m13_axi_wready,
    input  wire [ID_WIDTH-1:0]      m13_axi_bid,
    input  wire [1:0]               m13_axi_bresp,
    input  wire [BUSER_WIDTH-1:0]   m13_axi_buser,
    input  wire                     m13_axi_bvalid,
    output wire                     m13_axi_bready,
    output wire [ID_WIDTH-1:0]      m13_axi_arid,
    output wire [ADDR_WIDTH-1:0]    m13_axi_araddr,
    output wire [7:0]               m13_axi_arlen,
    output wire [2:0]               m13_axi_arsize,
    output wire [1:0]               m13_axi_arburst,
    output wire                     m13_axi_arlock,
    output wire [3:0]               m13_axi_arcache,
    output wire [2:0]               m13_axi_arprot,
    output wire [3:0]               m13_axi_arqos,
    output wire [3:0]               m13_axi_arregion,
    output wire [ARUSER_WIDTH-1:0]  m13_axi_aruser,
    output wire                     m13_axi_arvalid,
    input  wire                     m13_axi_arready,
    input  wire [ID_WIDTH-1:0]      m13_axi_rid,
    input  wire [DATA_WIDTH-1:0]    m13_axi_rdata,
    input  wire [1:0]               m13_axi_rresp,
    input  wire                     m13_axi_rlast,
    input  wire [RUSER_WIDTH-1:0]   m13_axi_ruser,
    input  wire                     m13_axi_rvalid,
    output wire                     m13_axi_rready,

    // S14: Seven-Segment Display
    output wire [ID_WIDTH-1:0]      m14_axi_awid,
    output wire [ADDR_WIDTH-1:0]    m14_axi_awaddr,
    output wire [7:0]               m14_axi_awlen,
    output wire [2:0]               m14_axi_awsize,
    output wire [1:0]               m14_axi_awburst,
    output wire                     m14_axi_awlock,
    output wire [3:0]               m14_axi_awcache,
    output wire [2:0]               m14_axi_awprot,
    output wire [3:0]               m14_axi_awqos,
    output wire [3:0]               m14_axi_awregion,
    output wire [AWUSER_WIDTH-1:0]  m14_axi_awuser,
    output wire                     m14_axi_awvalid,
    input  wire                     m14_axi_awready,
    output wire [DATA_WIDTH-1:0]    m14_axi_wdata,
    output wire [STRB_WIDTH-1:0]    m14_axi_wstrb,
    output wire                     m14_axi_wlast,
    output wire [WUSER_WIDTH-1:0]   m14_axi_wuser,
    output wire                     m14_axi_wvalid,
    input  wire                     m14_axi_wready,
    input  wire [ID_WIDTH-1:0]      m14_axi_bid,
    input  wire [1:0]               m14_axi_bresp,
    input  wire [BUSER_WIDTH-1:0]   m14_axi_buser,
    input  wire                     m14_axi_bvalid,
    output wire                     m14_axi_bready,
    output wire [ID_WIDTH-1:0]      m14_axi_arid,
    output wire [ADDR_WIDTH-1:0]    m14_axi_araddr,
    output wire [7:0]               m14_axi_arlen,
    output wire [2:0]               m14_axi_arsize,
    output wire [1:0]               m14_axi_arburst,
    output wire                     m14_axi_arlock,
    output wire [3:0]               m14_axi_arcache,
    output wire [2:0]               m14_axi_arprot,
    output wire [3:0]               m14_axi_arqos,
    output wire [3:0]               m14_axi_arregion,
    output wire [ARUSER_WIDTH-1:0]  m14_axi_aruser,
    output wire                     m14_axi_arvalid,
    input  wire                     m14_axi_arready,
    input  wire [ID_WIDTH-1:0]      m14_axi_rid,
    input  wire [DATA_WIDTH-1:0]    m14_axi_rdata,
    input  wire [1:0]               m14_axi_rresp,
    input  wire                     m14_axi_rlast,
    input  wire [RUSER_WIDTH-1:0]   m14_axi_ruser,
    input  wire                     m14_axi_rvalid,
    output wire                     m14_axi_rready
);

    // ============================================================
    // Internal Wires for Slave S2 (m02) to GPIO Connection
    // ============================================================
    wire [ID_WIDTH-1:0]      m02_axi_awid;
    wire [ADDR_WIDTH-1:0]    m02_axi_awaddr;
    wire [7:0]               m02_axi_awlen;
    wire [2:0]               m02_axi_awsize;
    wire [1:0]               m02_axi_awburst;
    wire                     m02_axi_awlock;
    wire [3:0]               m02_axi_awcache;
    wire [2:0]               m02_axi_awprot;
    wire [3:0]               m02_axi_awqos;
    wire [3:0]               m02_axi_awregion;
    wire [AWUSER_WIDTH-1:0]  m02_axi_awuser;
    wire                     m02_axi_awvalid;
    wire                     m02_axi_awready;

    wire [DATA_WIDTH-1:0]    m02_axi_wdata;
    wire [STRB_WIDTH-1:0]    m02_axi_wstrb;
    wire                     m02_axi_wlast;
    wire [WUSER_WIDTH-1:0]   m02_axi_wuser;
    wire                     m02_axi_wvalid;
    wire                     m02_axi_wready;

    wire [ID_WIDTH-1:0]      m02_axi_bid;
    wire [1:0]               m02_axi_bresp;
    wire [BUSER_WIDTH-1:0]   m02_axi_buser;
    wire                     m02_axi_bvalid;
    wire                     m02_axi_bready;

    wire [ID_WIDTH-1:0]      m02_axi_arid;
    wire [ADDR_WIDTH-1:0]    m02_axi_araddr;
    wire [7:0]               m02_axi_arlen;
    wire [2:0]               m02_axi_arsize;
    wire [1:0]               m02_axi_arburst;
    wire                     m02_axi_arlock;
    wire [3:0]               m02_axi_arcache;
    wire [2:0]               m02_axi_arprot;
    wire [3:0]               m02_axi_arqos;
    wire [3:0]               m02_axi_arregion;
    wire [ARUSER_WIDTH-1:0]  m02_axi_aruser;
    wire                     m02_axi_arvalid;
    wire                     m02_axi_arready;

    wire [ID_WIDTH-1:0]      m02_axi_rid;
    wire [DATA_WIDTH-1:0]    m02_axi_rdata;
    wire [1:0]               m02_axi_rresp;
    wire                     m02_axi_rlast;
    wire [RUSER_WIDTH-1:0]   m02_axi_ruser;
    wire                     m02_axi_rvalid;
    wire                     m02_axi_rready;

    // ============================================================
    // Internal Wires for Slave S3 (m03) to Timer Connection
    // ============================================================
    wire [ID_WIDTH-1:0]      m03_axi_awid;
    wire [ADDR_WIDTH-1:0]    m03_axi_awaddr;
    wire [7:0]               m03_axi_awlen;
    wire [2:0]               m03_axi_awsize;
    wire [1:0]               m03_axi_awburst;
    wire                     m03_axi_awlock;
    wire [3:0]               m03_axi_awcache;
    wire [2:0]               m03_axi_awprot;
    wire [3:0]               m03_axi_awqos;
    wire [3:0]               m03_axi_awregion;
    wire [AWUSER_WIDTH-1:0]  m03_axi_awuser;
    wire                     m03_axi_awvalid;
    wire                     m03_axi_awready;

    wire [DATA_WIDTH-1:0]    m03_axi_wdata;
    wire [STRB_WIDTH-1:0]    m03_axi_wstrb;
    wire                     m03_axi_wlast;
    wire [WUSER_WIDTH-1:0]   m03_axi_wuser;
    wire                     m03_axi_wvalid;
    wire                     m03_axi_wready;

    wire [ID_WIDTH-1:0]      m03_axi_bid;
    wire [1:0]               m03_axi_bresp;
    wire [BUSER_WIDTH-1:0]   m03_axi_buser;
    wire                     m03_axi_bvalid;
    wire                     m03_axi_bready;

    wire [ID_WIDTH-1:0]      m03_axi_arid;
    wire [ADDR_WIDTH-1:0]    m03_axi_araddr;
    wire [7:0]               m03_axi_arlen;
    wire [2:0]               m03_axi_arsize;
    wire [1:0]               m03_axi_arburst;
    wire                     m03_axi_arlock;
    wire [3:0]               m03_axi_arcache;
    wire [2:0]               m03_axi_arprot;
    wire [3:0]               m03_axi_arqos;
    wire [3:0]               m03_axi_arregion;
    wire [ARUSER_WIDTH-1:0]  m03_axi_aruser;
    wire                     m03_axi_arvalid;
    wire                     m03_axi_arready;

    wire [ID_WIDTH-1:0]      m03_axi_rid;
    wire [DATA_WIDTH-1:0]    m03_axi_rdata;
    wire [1:0]               m03_axi_rresp;
    wire                     m03_axi_rlast;
    wire [RUSER_WIDTH-1:0]   m03_axi_ruser;
    wire                     m03_axi_rvalid;
    wire                     m03_axi_rready;

    // ============================================================
    // Internal Wires for Slave S4 (m04) to UART Connection
    // ============================================================
    wire [ID_WIDTH-1:0]      m04_axi_awid;
    wire [ADDR_WIDTH-1:0]    m04_axi_awaddr;
    wire [7:0]               m04_axi_awlen;
    wire [2:0]               m04_axi_awsize;
    wire [1:0]               m04_axi_awburst;
    wire                     m04_axi_awlock;
    wire [3:0]               m04_axi_awcache;
    wire [2:0]               m04_axi_awprot;
    wire [3:0]               m04_axi_awqos;
    wire [3:0]               m04_axi_awregion;
    wire [AWUSER_WIDTH-1:0]  m04_axi_awuser;
    wire                     m04_axi_awvalid;
    wire                     m04_axi_awready;

    wire [DATA_WIDTH-1:0]    m04_axi_wdata;
    wire [STRB_WIDTH-1:0]    m04_axi_wstrb;
    wire                     m04_axi_wlast;
    wire [WUSER_WIDTH-1:0]   m04_axi_wuser;
    wire                     m04_axi_wvalid;
    wire                     m04_axi_wready;

    wire [ID_WIDTH-1:0]      m04_axi_bid;
    wire [1:0]               m04_axi_bresp;
    wire [BUSER_WIDTH-1:0]   m04_axi_buser;
    wire                     m04_axi_bvalid;
    wire                     m04_axi_bready;

    wire [ID_WIDTH-1:0]      m04_axi_arid;
    wire [ADDR_WIDTH-1:0]    m04_axi_araddr;
    wire [7:0]               m04_axi_arlen;
    wire [2:0]               m04_axi_arsize;
    wire [1:0]               m04_axi_arburst;
    wire                     m04_axi_arlock;
    wire [3:0]               m04_axi_arcache;
    wire [2:0]               m04_axi_arprot;
    wire [3:0]               m04_axi_arqos;
    wire [3:0]               m04_axi_arregion;
    wire [ARUSER_WIDTH-1:0]  m04_axi_aruser;
    wire                     m04_axi_arvalid;
    wire                     m04_axi_arready;

    wire [ID_WIDTH-1:0]      m04_axi_rid;
    wire [DATA_WIDTH-1:0]    m04_axi_rdata;
    wire [1:0]               m04_axi_rresp;
    wire                     m04_axi_rlast;
    wire [RUSER_WIDTH-1:0]   m04_axi_ruser;
    wire                     m04_axi_rvalid;
    wire                     m04_axi_rready;

    // ============================================================
    // Internal Wires for Slave S8 (m08) to Encoder Connection
    // ============================================================
    wire [ID_WIDTH-1:0]      m08_axi_awid;
    wire [ADDR_WIDTH-1:0]    m08_axi_awaddr;
    wire [7:0]               m08_axi_awlen;
    wire [2:0]               m08_axi_awsize;
    wire [1:0]               m08_axi_awburst;
    wire                     m08_axi_awlock;
    wire [3:0]               m08_axi_awcache;
    wire [2:0]               m08_axi_awprot;
    wire [3:0]               m08_axi_awqos;
    wire [3:0]               m08_axi_awregion;
    wire [AWUSER_WIDTH-1:0]  m08_axi_awuser;
    wire                     m08_axi_awvalid;
    wire                     m08_axi_awready;

    wire [DATA_WIDTH-1:0]    m08_axi_wdata;
    wire [STRB_WIDTH-1:0]    m08_axi_wstrb;
    wire                     m08_axi_wlast;
    wire [WUSER_WIDTH-1:0]   m08_axi_wuser;
    wire                     m08_axi_wvalid;
    wire                     m08_axi_wready;

    wire [ID_WIDTH-1:0]      m08_axi_bid;
    wire [1:0]               m08_axi_bresp;
    wire [BUSER_WIDTH-1:0]   m08_axi_buser;
    wire                     m08_axi_bvalid;
    wire                     m08_axi_bready;

    wire [ID_WIDTH-1:0]      m08_axi_arid;
    wire [ADDR_WIDTH-1:0]    m08_axi_araddr;
    wire [7:0]               m08_axi_arlen;
    wire [2:0]               m08_axi_arsize;
    wire [1:0]               m08_axi_arburst;
    wire                     m08_axi_arlock;
    wire [3:0]               m08_axi_arcache;
    wire [2:0]               m08_axi_arprot;
    wire [3:0]               m08_axi_arqos;
    wire [3:0]               m08_axi_arregion;
    wire [ARUSER_WIDTH-1:0]  m08_axi_aruser;
    wire                     m08_axi_arvalid;
    wire                     m08_axi_arready;

    wire [ID_WIDTH-1:0]      m08_axi_rid;
    wire [DATA_WIDTH-1:0]    m08_axi_rdata;
    wire [1:0]               m08_axi_rresp;
    wire                     m08_axi_rlast;
    wire [RUSER_WIDTH-1:0]   m08_axi_ruser;
    wire                     m08_axi_rvalid;
    wire                     m08_axi_rready;

    // ============================================================
    // Internal Wires for Slave S9 (m09) to PID Connection
    // ============================================================
    wire [ID_WIDTH-1:0]      m09_axi_awid;
    wire [ADDR_WIDTH-1:0]    m09_axi_awaddr;
    wire [7:0]               m09_axi_awlen;
    wire [2:0]               m09_axi_awsize;
    wire [1:0]               m09_axi_awburst;
    wire                     m09_axi_awlock;
    wire [3:0]               m09_axi_awcache;
    wire [2:0]               m09_axi_awprot;
    wire [3:0]               m09_axi_awqos;
    wire [3:0]               m09_axi_awregion;
    wire [AWUSER_WIDTH-1:0]  m09_axi_awuser;
    wire                     m09_axi_awvalid;
    wire                     m09_axi_awready;

    wire [DATA_WIDTH-1:0]    m09_axi_wdata;
    wire [STRB_WIDTH-1:0]    m09_axi_wstrb;
    wire                     m09_axi_wlast;
    wire [WUSER_WIDTH-1:0]   m09_axi_wuser;
    wire                     m09_axi_wvalid;
    wire                     m09_axi_wready;

    wire [ID_WIDTH-1:0]      m09_axi_bid;
    wire [1:0]               m09_axi_bresp;
    wire [BUSER_WIDTH-1:0]   m09_axi_buser;
    wire                     m09_axi_bvalid;
    wire                     m09_axi_bready;

    wire [ID_WIDTH-1:0]      m09_axi_arid;
    wire [ADDR_WIDTH-1:0]    m09_axi_araddr;
    wire [7:0]               m09_axi_arlen;
    wire [2:0]               m09_axi_arsize;
    wire [1:0]               m09_axi_arburst;
    wire                     m09_axi_arlock;
    wire [3:0]               m09_axi_arcache;
    wire [2:0]               m09_axi_arprot;
    wire [3:0]               m09_axi_arqos;
    wire [3:0]               m09_axi_arregion;
    wire [ARUSER_WIDTH-1:0]  m09_axi_aruser;
    wire                     m09_axi_arvalid;
    wire                     m09_axi_arready;

    wire [ID_WIDTH-1:0]      m09_axi_rid;
    wire [DATA_WIDTH-1:0]    m09_axi_rdata;
    wire [1:0]               m09_axi_rresp;
    wire                     m09_axi_rlast;
    wire [RUSER_WIDTH-1:0]   m09_axi_ruser;
    wire                     m09_axi_rvalid;
    wire                     m09_axi_rready;

    // >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    // >>> PWM S10 INTEGRATION - ADDED CODE - BEGIN
    // >>> Internal wires for Slave S10 (m10) to PWM connection
    // >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    wire [ID_WIDTH-1:0]      m10_axi_awid;
    wire [ADDR_WIDTH-1:0]    m10_axi_awaddr;
    wire [7:0]               m10_axi_awlen;
    wire [2:0]               m10_axi_awsize;
    wire [1:0]               m10_axi_awburst;
    wire                     m10_axi_awlock;
    wire [3:0]               m10_axi_awcache;
    wire [2:0]               m10_axi_awprot;
    wire [3:0]               m10_axi_awqos;
    wire [3:0]               m10_axi_awregion;
    wire [AWUSER_WIDTH-1:0]  m10_axi_awuser;
    wire                     m10_axi_awvalid;
    wire                     m10_axi_awready;

    wire [DATA_WIDTH-1:0]    m10_axi_wdata;
    wire [STRB_WIDTH-1:0]    m10_axi_wstrb;
    wire                     m10_axi_wlast;
    wire [WUSER_WIDTH-1:0]   m10_axi_wuser;
    wire                     m10_axi_wvalid;
    wire                     m10_axi_wready;

    wire [ID_WIDTH-1:0]      m10_axi_bid;
    wire [1:0]               m10_axi_bresp;
    wire [BUSER_WIDTH-1:0]   m10_axi_buser;
    wire                     m10_axi_bvalid;
    wire                     m10_axi_bready;

    wire [ID_WIDTH-1:0]      m10_axi_arid;
    wire [ADDR_WIDTH-1:0]    m10_axi_araddr;
    wire [7:0]               m10_axi_arlen;
    wire [2:0]               m10_axi_arsize;
    wire [1:0]               m10_axi_arburst;
    wire                     m10_axi_arlock;
    wire [3:0]               m10_axi_arcache;
    wire [2:0]               m10_axi_arprot;
    wire [3:0]               m10_axi_arqos;
    wire [3:0]               m10_axi_arregion;
    wire [ARUSER_WIDTH-1:0]  m10_axi_aruser;
    wire                     m10_axi_arvalid;
    wire                     m10_axi_arready;

    wire [ID_WIDTH-1:0]      m10_axi_rid;
    wire [DATA_WIDTH-1:0]    m10_axi_rdata;
    wire [1:0]               m10_axi_rresp;
    wire                     m10_axi_rlast;
    wire [RUSER_WIDTH-1:0]   m10_axi_ruser;
    wire                     m10_axi_rvalid;
    wire                     m10_axi_rready;
    // <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    // <<< PWM S10 INTEGRATION - ADDED CODE - END
    // <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    // ============================================================
    // Existing 3-Master x 15-Slave Interconnect Instantiation
    // ============================================================
    axi_interconnect_wrap_3x15 #(
        .DATA_WIDTH         (DATA_WIDTH),
        .ADDR_WIDTH         (ADDR_WIDTH),
        .STRB_WIDTH         (STRB_WIDTH),
        .ID_WIDTH           (ID_WIDTH),
        .AWUSER_ENABLE      (AWUSER_ENABLE),
        .AWUSER_WIDTH       (AWUSER_WIDTH),
        .WUSER_ENABLE       (WUSER_ENABLE),
        .WUSER_WIDTH        (WUSER_WIDTH),
        .BUSER_ENABLE       (BUSER_ENABLE),
        .BUSER_WIDTH        (BUSER_WIDTH),
        .ARUSER_ENABLE      (ARUSER_ENABLE),
        .ARUSER_WIDTH       (ARUSER_WIDTH),
        .RUSER_ENABLE       (RUSER_ENABLE),
        .RUSER_WIDTH        (RUSER_WIDTH),

        .M00_BASE_ADDR      (M00_BASE_ADDR),
        .M00_ADDR_WIDTH     (M00_ADDR_WIDTH),
        .M01_BASE_ADDR      (M01_BASE_ADDR),
        .M01_ADDR_WIDTH     (M01_ADDR_WIDTH),
        .M02_BASE_ADDR      (M02_BASE_ADDR),
        .M02_ADDR_WIDTH     (M02_ADDR_WIDTH),
        .M03_BASE_ADDR      (M03_BASE_ADDR),
        .M03_ADDR_WIDTH     (M03_ADDR_WIDTH),
        .M04_BASE_ADDR      (M04_BASE_ADDR),
        .M04_ADDR_WIDTH     (M04_ADDR_WIDTH),
        .M05_BASE_ADDR      (M05_BASE_ADDR),
        .M05_ADDR_WIDTH     (M05_ADDR_WIDTH),
        .M06_BASE_ADDR      (M06_BASE_ADDR),
        .M06_ADDR_WIDTH     (M06_ADDR_WIDTH),
        .M07_BASE_ADDR      (M07_BASE_ADDR),
        .M07_ADDR_WIDTH     (M07_ADDR_WIDTH),
        .M08_BASE_ADDR      (M08_BASE_ADDR),
        .M08_ADDR_WIDTH     (M08_ADDR_WIDTH),
        .M09_BASE_ADDR      (M09_BASE_ADDR),
        .M09_ADDR_WIDTH     (M09_ADDR_WIDTH),
        .M10_BASE_ADDR      (M10_BASE_ADDR),
        .M10_ADDR_WIDTH     (M10_ADDR_WIDTH),
        .M11_BASE_ADDR      (M11_BASE_ADDR),
        .M11_ADDR_WIDTH     (M11_ADDR_WIDTH),
        .M12_BASE_ADDR      (M12_BASE_ADDR),
        .M12_ADDR_WIDTH     (M12_ADDR_WIDTH),
        .M13_BASE_ADDR      (M13_BASE_ADDR),
        .M13_ADDR_WIDTH     (M13_ADDR_WIDTH),
        .M14_BASE_ADDR      (M14_BASE_ADDR),
        .M14_ADDR_WIDTH     (M14_ADDR_WIDTH)
    ) u_axi_interconnect_3x15 (
        .clk                (clk),
        .rst                (rst),

        // M0 Master (VeeR IFU)
        .s00_axi_awid       (s00_axi_awid),
        .s00_axi_awaddr     (s00_axi_awaddr),
        .s00_axi_awlen      (s00_axi_awlen),
        .s00_axi_awsize     (s00_axi_awsize),
        .s00_axi_awburst    (s00_axi_awburst),
        .s00_axi_awlock     (s00_axi_awlock),
        .s00_axi_awcache    (s00_axi_awcache),
        .s00_axi_awprot     (s00_axi_awprot),
        .s00_axi_awqos      (s00_axi_awqos),
        .s00_axi_awuser     (s00_axi_awuser),
        .s00_axi_awvalid    (s00_axi_awvalid),
        .s00_axi_awready    (s00_axi_awready),
        .s00_axi_wdata      (s00_axi_wdata),
        .s00_axi_wstrb      (s00_axi_wstrb),
        .s00_axi_wlast      (s00_axi_wlast),
        .s00_axi_wuser      (s00_axi_wuser),
        .s00_axi_wvalid     (s00_axi_wvalid),
        .s00_axi_wready     (s00_axi_wready),
        .s00_axi_bid        (s00_axi_bid),
        .s00_axi_bresp      (s00_axi_bresp),
        .s00_axi_buser      (s00_axi_buser),
        .s00_axi_bvalid     (s00_axi_bvalid),
        .s00_axi_bready     (s00_axi_bready),
        .s00_axi_arid       (s00_axi_arid),
        .s00_axi_araddr     (s00_axi_araddr),
        .s00_axi_arlen      (s00_axi_arlen),
        .s00_axi_arsize     (s00_axi_arsize),
        .s00_axi_arburst    (s00_axi_arburst),
        .s00_axi_arlock     (s00_axi_arlock),
        .s00_axi_arcache    (s00_axi_arcache),
        .s00_axi_arprot     (s00_axi_arprot),
        .s00_axi_arqos      (s00_axi_arqos),
        .s00_axi_aruser     (s00_axi_aruser),
        .s00_axi_arvalid    (s00_axi_arvalid),
        .s00_axi_arready    (s00_axi_arready),
        .s00_axi_rid        (s00_axi_rid),
        .s00_axi_rdata      (s00_axi_rdata),
        .s00_axi_rresp      (s00_axi_rresp),
        .s00_axi_rlast      (s00_axi_rlast),
        .s00_axi_ruser      (s00_axi_ruser),
        .s00_axi_rvalid     (s00_axi_rvalid),
        .s00_axi_rready     (s00_axi_rready),

        // M1 Master (VeeR LSU)
        .s01_axi_awid       (s01_axi_awid),
        .s01_axi_awaddr     (s01_axi_awaddr),
        .s01_axi_awlen      (s01_axi_awlen),
        .s01_axi_awsize     (s01_axi_awsize),
        .s01_axi_awburst    (s01_axi_awburst),
        .s01_axi_awlock     (s01_axi_awlock),
        .s01_axi_awcache    (s01_axi_awcache),
        .s01_axi_awprot     (s01_axi_awprot),
        .s01_axi_awqos      (s01_axi_awqos),
        .s01_axi_awuser     (s01_axi_awuser),
        .s01_axi_awvalid    (s01_axi_awvalid),
        .s01_axi_awready    (s01_axi_awready),
        .s01_axi_wdata      (s01_axi_wdata),
        .s01_axi_wstrb      (s01_axi_wstrb),
        .s01_axi_wlast      (s01_axi_wlast),
        .s01_axi_wuser      (s01_axi_wuser),
        .s01_axi_wvalid     (s01_axi_wvalid),
        .s01_axi_wready     (s01_axi_wready),
        .s01_axi_bid        (s01_axi_bid),
        .s01_axi_bresp      (s01_axi_bresp),
        .s01_axi_buser      (s01_axi_buser),
        .s01_axi_bvalid     (s01_axi_bvalid),
        .s01_axi_bready     (s01_axi_bready),
        .s01_axi_arid       (s01_axi_arid),
        .s01_axi_araddr     (s01_axi_araddr),
        .s01_axi_arlen      (s01_axi_arlen),
        .s01_axi_arsize     (s01_axi_arsize),
        .s01_axi_arburst    (s01_axi_arburst),
        .s01_axi_arlock     (s01_axi_arlock),
        .s01_axi_arcache    (s01_axi_arcache),
        .s01_axi_arprot     (s01_axi_arprot),
        .s01_axi_arqos      (s01_axi_arqos),
        .s01_axi_aruser     (s01_axi_aruser),
        .s01_axi_arvalid    (s01_axi_arvalid),
        .s01_axi_arready    (s01_axi_arready),
        .s01_axi_rid        (s01_axi_rid),
        .s01_axi_rdata      (s01_axi_rdata),
        .s01_axi_rresp      (s01_axi_rresp),
        .s01_axi_rlast      (s01_axi_rlast),
        .s01_axi_ruser      (s01_axi_ruser),
        .s01_axi_rvalid     (s01_axi_rvalid),
        .s01_axi_rready     (s01_axi_rready),

        // M2 Master (DMA Controller)
        .s02_axi_awid       (s02_axi_awid),
        .s02_axi_awaddr     (s02_axi_awaddr),
        .s02_axi_awlen      (s02_axi_awlen),
        .s02_axi_awsize     (s02_axi_awsize),
        .s02_axi_awburst    (s02_axi_awburst),
        .s02_axi_awlock     (s02_axi_awlock),
        .s02_axi_awcache    (s02_axi_awcache),
        .s02_axi_awprot     (s02_axi_awprot),
        .s02_axi_awqos      (s02_axi_awqos),
        .s02_axi_awuser     (s02_axi_awuser),
        .s02_axi_awvalid    (s02_axi_awvalid),
        .s02_axi_awready    (s02_axi_awready),
        .s02_axi_wdata      (s02_axi_wdata),
        .s02_axi_wstrb      (s02_axi_wstrb),
        .s02_axi_wlast      (s02_axi_wlast),
        .s02_axi_wuser      (s02_axi_wuser),
        .s02_axi_wvalid     (s02_axi_wvalid),
        .s02_axi_wready     (s02_axi_wready),
        .s02_axi_bid        (s02_axi_bid),
        .s02_axi_bresp      (s02_axi_bresp),
        .s02_axi_buser      (s02_axi_buser),
        .s02_axi_bvalid     (s02_axi_bvalid),
        .s02_axi_bready     (s02_axi_bready),
        .s02_axi_arid       (s02_axi_arid),
        .s02_axi_araddr     (s02_axi_araddr),
        .s02_axi_arlen      (s02_axi_arlen),
        .s02_axi_arsize     (s02_axi_arsize),
        .s02_axi_arburst    (s02_axi_arburst),
        .s02_axi_arlock     (s02_axi_arlock),
        .s02_axi_arcache    (s02_axi_arcache),
        .s02_axi_arprot     (s02_axi_arprot),
        .s02_axi_arqos      (s02_axi_arqos),
        .s02_axi_aruser     (s02_axi_aruser),
        .s02_axi_arvalid    (s02_axi_arvalid),
        .s02_axi_arready    (s02_axi_arready),
        .s02_axi_rid        (s02_axi_rid),
        .s02_axi_rdata      (s02_axi_rdata),
        .s02_axi_rresp      (s02_axi_rresp),
        .s02_axi_rlast      (s02_axi_rlast),
        .s02_axi_ruser      (s02_axi_ruser),
        .s02_axi_rvalid     (s02_axi_rvalid),
        .s02_axi_rready     (s02_axi_rready),

        // S0: IMEM
        .m00_axi_awid       (m00_axi_awid),
        .m00_axi_awaddr     (m00_axi_awaddr),
        .m00_axi_awlen      (m00_axi_awlen),
        .m00_axi_awsize     (m00_axi_awsize),
        .m00_axi_awburst    (m00_axi_awburst),
        .m00_axi_awlock     (m00_axi_awlock),
        .m00_axi_awcache    (m00_axi_awcache),
        .m00_axi_awprot     (m00_axi_awprot),
        .m00_axi_awqos      (m00_axi_awqos),
        .m00_axi_awregion   (m00_axi_awregion),
        .m00_axi_awuser     (m00_axi_awuser),
        .m00_axi_awvalid    (m00_axi_awvalid),
        .m00_axi_awready    (m00_axi_awready),
        .m00_axi_wdata      (m00_axi_wdata),
        .m00_axi_wstrb      (m00_axi_wstrb),
        .m00_axi_wlast      (m00_axi_wlast),
        .m00_axi_wuser      (m00_axi_wuser),
        .m00_axi_wvalid     (m00_axi_wvalid),
        .m00_axi_wready     (m00_axi_wready),
        .m00_axi_bid        (m00_axi_bid),
        .m00_axi_bresp      (m00_axi_bresp),
        .m00_axi_buser      (m00_axi_buser),
        .m00_axi_bvalid     (m00_axi_bvalid),
        .m00_axi_bready     (m00_axi_bready),
        .m00_axi_arid       (m00_axi_arid),
        .m00_axi_araddr     (m00_axi_araddr),
        .m00_axi_arlen      (m00_axi_arlen),
        .m00_axi_arsize     (m00_axi_arsize),
        .m00_axi_arburst    (m00_axi_arburst),
        .m00_axi_arlock     (m00_axi_arlock),
        .m00_axi_arcache    (m00_axi_arcache),
        .m00_axi_arprot     (m00_axi_arprot),
        .m00_axi_arqos      (m00_axi_arqos),
        .m00_axi_arregion   (m00_axi_arregion),
        .m00_axi_aruser     (m00_axi_aruser),
        .m00_axi_arvalid    (m00_axi_arvalid),
        .m00_axi_arready    (m00_axi_arready),
        .m00_axi_rid        (m00_axi_rid),
        .m00_axi_rdata      (m00_axi_rdata),
        .m00_axi_rresp      (m00_axi_rresp),
        .m00_axi_rlast      (m00_axi_rlast),
        .m00_axi_ruser      (m00_axi_ruser),
        .m00_axi_rvalid     (m00_axi_rvalid),
        .m00_axi_rready     (m00_axi_rready),

        // S1: DMEM
        .m01_axi_awid       (m01_axi_awid),
        .m01_axi_awaddr     (m01_axi_awaddr),
        .m01_axi_awlen      (m01_axi_awlen),
        .m01_axi_awsize     (m01_axi_awsize),
        .m01_axi_awburst    (m01_axi_awburst),
        .m01_axi_awlock     (m01_axi_awlock),
        .m01_axi_awcache    (m01_axi_awcache),
        .m01_axi_awprot     (m01_axi_awprot),
        .m01_axi_awqos      (m01_axi_awqos),
        .m01_axi_awregion   (m01_axi_awregion),
        .m01_axi_awuser     (m01_axi_awuser),
        .m01_axi_awvalid    (m01_axi_awvalid),
        .m01_axi_awready    (m01_axi_awready),
        .m01_axi_wdata      (m01_axi_wdata),
        .m01_axi_wstrb      (m01_axi_wstrb),
        .m01_axi_wlast      (m01_axi_wlast),
        .m01_axi_wuser      (m01_axi_wuser),
        .m01_axi_wvalid     (m01_axi_wvalid),
        .m01_axi_wready     (m01_axi_wready),
        .m01_axi_bid        (m01_axi_bid),
        .m01_axi_bresp      (m01_axi_bresp),
        .m01_axi_buser      (m01_axi_buser),
        .m01_axi_bvalid     (m01_axi_bvalid),
        .m01_axi_bready     (m01_axi_bready),
        .m01_axi_arid       (m01_axi_arid),
        .m01_axi_araddr     (m01_axi_araddr),
        .m01_axi_arlen      (m01_axi_arlen),
        .m01_axi_arsize     (m01_axi_arsize),
        .m01_axi_arburst    (m01_axi_arburst),
        .m01_axi_arlock     (m01_axi_arlock),
        .m01_axi_arcache    (m01_axi_arcache),
        .m01_axi_arprot     (m01_axi_arprot),
        .m01_axi_arqos      (m01_axi_arqos),
        .m01_axi_arregion   (m01_axi_arregion),
        .m01_axi_aruser     (m01_axi_aruser),
        .m01_axi_arvalid    (m01_axi_arvalid),
        .m01_axi_arready    (m01_axi_arready),
        .m01_axi_rid        (m01_axi_rid),
        .m01_axi_rdata      (m01_axi_rdata),
        .m01_axi_rresp      (m01_axi_rresp),
        .m01_axi_rlast      (m01_axi_rlast),
        .m01_axi_ruser      (m01_axi_ruser),
        .m01_axi_rvalid     (m01_axi_rvalid),
        .m01_axi_rready     (m01_axi_rready),

        // S2: GPIO
        .m02_axi_awid       (m02_axi_awid),
        .m02_axi_awaddr     (m02_axi_awaddr),
        .m02_axi_awlen      (m02_axi_awlen),
        .m02_axi_awsize     (m02_axi_awsize),
        .m02_axi_awburst    (m02_axi_awburst),
        .m02_axi_awlock     (m02_axi_awlock),
        .m02_axi_awcache    (m02_axi_awcache),
        .m02_axi_awprot     (m02_axi_awprot),
        .m02_axi_awqos      (m02_axi_awqos),
        .m02_axi_awregion   (m02_axi_awregion),
        .m02_axi_awuser     (m02_axi_awuser),
        .m02_axi_awvalid    (m02_axi_awvalid),
        .m02_axi_awready    (m02_axi_awready),
        .m02_axi_wdata      (m02_axi_wdata),
        .m02_axi_wstrb      (m02_axi_wstrb),
        .m02_axi_wlast      (m02_axi_wlast),
        .m02_axi_wuser      (m02_axi_wuser),
        .m02_axi_wvalid     (m02_axi_wvalid),
        .m02_axi_wready     (m02_axi_wready),
        .m02_axi_bid        (m02_axi_bid),
        .m02_axi_bresp      (m02_axi_bresp),
        .m02_axi_buser      (m02_axi_buser),
        .m02_axi_bvalid     (m02_axi_bvalid),
        .m02_axi_bready     (m02_axi_bready),
        .m02_axi_arid       (m02_axi_arid),
        .m02_axi_araddr     (m02_axi_araddr),
        .m02_axi_arlen      (m02_axi_arlen),
        .m02_axi_arsize     (m02_axi_arsize),
        .m02_axi_arburst    (m02_axi_arburst),
        .m02_axi_arlock     (m02_axi_arlock),
        .m02_axi_arcache    (m02_axi_arcache),
        .m02_axi_arprot     (m02_axi_arprot),
        .m02_axi_arqos      (m02_axi_arqos),
        .m02_axi_arregion   (m02_axi_arregion),
        .m02_axi_aruser     (m02_axi_aruser),
        .m02_axi_arvalid    (m02_axi_arvalid),
        .m02_axi_arready    (m02_axi_arready),
        .m02_axi_rid        (m02_axi_rid),
        .m02_axi_rdata      (m02_axi_rdata),
        .m02_axi_rresp      (m02_axi_rresp),
        .m02_axi_rlast      (m02_axi_rlast),
        .m02_axi_ruser      (m02_axi_ruser),
        .m02_axi_rvalid     (m02_axi_rvalid),
        .m02_axi_rready     (m02_axi_rready),

        // S3: Timer
        .m03_axi_awid       (m03_axi_awid),
        .m03_axi_awaddr     (m03_axi_awaddr),
        .m03_axi_awlen      (m03_axi_awlen),
        .m03_axi_awsize     (m03_axi_awsize),
        .m03_axi_awburst    (m03_axi_awburst),
        .m03_axi_awlock     (m03_axi_awlock),
        .m03_axi_awcache    (m03_axi_awcache),
        .m03_axi_awprot     (m03_axi_awprot),
        .m03_axi_awqos      (m03_axi_awqos),
        .m03_axi_awregion   (m03_axi_awregion),
        .m03_axi_awuser     (m03_axi_awuser),
        .m03_axi_awvalid    (m03_axi_awvalid),
        .m03_axi_awready    (m03_axi_awready),
        .m03_axi_wdata      (m03_axi_wdata),
        .m03_axi_wstrb      (m03_axi_wstrb),
        .m03_axi_wlast      (m03_axi_wlast),
        .m03_axi_wuser      (m03_axi_wuser),
        .m03_axi_wvalid     (m03_axi_wvalid),
        .m03_axi_wready     (m03_axi_wready),
        .m03_axi_bid        (m03_axi_bid),
        .m03_axi_bresp      (m03_axi_bresp),
        .m03_axi_buser      (m03_axi_buser),
        .m03_axi_bvalid     (m03_axi_bvalid),
        .m03_axi_bready     (m03_axi_bready),
        .m03_axi_arid       (m03_axi_arid),
        .m03_axi_araddr     (m03_axi_araddr),
        .m03_axi_arlen      (m03_axi_arlen),
        .m03_axi_arsize     (m03_axi_arsize),
        .m03_axi_arburst    (m03_axi_arburst),
        .m03_axi_arlock     (m03_axi_arlock),
        .m03_axi_arcache    (m03_axi_arcache),
        .m03_axi_arprot     (m03_axi_arprot),
        .m03_axi_arqos      (m03_axi_arqos),
        .m03_axi_arregion   (m03_axi_arregion),
        .m03_axi_aruser     (m03_axi_aruser),
        .m03_axi_arvalid    (m03_axi_arvalid),
        .m03_axi_arready    (m03_axi_arready),
        .m03_axi_rid        (m03_axi_rid),
        .m03_axi_rdata      (m03_axi_rdata),
        .m03_axi_rresp      (m03_axi_rresp),
        .m03_axi_rlast      (m03_axi_rlast),
        .m03_axi_ruser      (m03_axi_ruser),
        .m03_axi_rvalid     (m03_axi_rvalid),
        .m03_axi_rready     (m03_axi_rready),

        // S4: UART (connected internally to UART logic below)
        .m04_axi_awid       (m04_axi_awid),
        .m04_axi_awaddr     (m04_axi_awaddr),
        .m04_axi_awlen      (m04_axi_awlen),
        .m04_axi_awsize     (m04_axi_awsize),
        .m04_axi_awburst    (m04_axi_awburst),
        .m04_axi_awlock     (m04_axi_awlock),
        .m04_axi_awcache    (m04_axi_awcache),
        .m04_axi_awprot     (m04_axi_awprot),
        .m04_axi_awqos      (m04_axi_awqos),
        .m04_axi_awregion   (m04_axi_awregion),
        .m04_axi_awuser     (m04_axi_awuser),
        .m04_axi_awvalid    (m04_axi_awvalid),
        .m04_axi_awready    (m04_axi_awready),
        .m04_axi_wdata      (m04_axi_wdata),
        .m04_axi_wstrb      (m04_axi_wstrb),
        .m04_axi_wlast      (m04_axi_wlast),
        .m04_axi_wuser      (m04_axi_wuser),
        .m04_axi_wvalid     (m04_axi_wvalid),
        .m04_axi_wready     (m04_axi_wready),
        .m04_axi_bid        (m04_axi_bid),
        .m04_axi_bresp      (m04_axi_bresp),
        .m04_axi_buser      (m04_axi_buser),
        .m04_axi_bvalid     (m04_axi_bvalid),
        .m04_axi_bready     (m04_axi_bready),
        .m04_axi_arid       (m04_axi_arid),
        .m04_axi_araddr     (m04_axi_araddr),
        .m04_axi_arlen      (m04_axi_arlen),
        .m04_axi_arsize     (m04_axi_arsize),
        .m04_axi_arburst    (m04_axi_arburst),
        .m04_axi_arlock     (m04_axi_arlock),
        .m04_axi_arcache    (m04_axi_arcache),
        .m04_axi_arprot     (m04_axi_arprot),
        .m04_axi_arqos      (m04_axi_arqos),
        .m04_axi_arregion   (m04_axi_arregion),
        .m04_axi_aruser     (m04_axi_aruser),
        .m04_axi_arvalid    (m04_axi_arvalid),
        .m04_axi_arready    (m04_axi_arready),
        .m04_axi_rid        (m04_axi_rid),
        .m04_axi_rdata      (m04_axi_rdata),
        .m04_axi_rresp      (m04_axi_rresp),
        .m04_axi_rlast      (m04_axi_rlast),
        .m04_axi_ruser      (m04_axi_ruser),
        .m04_axi_rvalid     (m04_axi_rvalid),
        .m04_axi_rready     (m04_axi_rready),

        // S5: Encoder
        .m05_axi_awid       (m05_axi_awid),
        .m05_axi_awaddr     (m05_axi_awaddr),
        .m05_axi_awlen      (m05_axi_awlen),
        .m05_axi_awsize     (m05_axi_awsize),
        .m05_axi_awburst    (m05_axi_awburst),
        .m05_axi_awlock     (m05_axi_awlock),
        .m05_axi_awcache    (m05_axi_awcache),
        .m05_axi_awprot     (m05_axi_awprot),
        .m05_axi_awqos      (m05_axi_awqos),
        .m05_axi_awregion   (m05_axi_awregion),
        .m05_axi_awuser     (m05_axi_awuser),
        .m05_axi_awvalid    (m05_axi_awvalid),
        .m05_axi_awready    (m05_axi_awready),
        .m05_axi_wdata      (m05_axi_wdata),
        .m05_axi_wstrb      (m05_axi_wstrb),
        .m05_axi_wlast      (m05_axi_wlast),
        .m05_axi_wuser      (m05_axi_wuser),
        .m05_axi_wvalid     (m05_axi_wvalid),
        .m05_axi_wready     (m05_axi_wready),
        .m05_axi_bid        (m05_axi_bid),
        .m05_axi_bresp      (m05_axi_bresp),
        .m05_axi_buser      (m05_axi_buser),
        .m05_axi_bvalid     (m05_axi_bvalid),
        .m05_axi_bready     (m05_axi_bready),
        .m05_axi_arid       (m05_axi_arid),
        .m05_axi_araddr     (m05_axi_araddr),
        .m05_axi_arlen      (m05_axi_arlen),
        .m05_axi_arsize     (m05_axi_arsize),
        .m05_axi_arburst    (m05_axi_arburst),
        .m05_axi_arlock     (m05_axi_arlock),
        .m05_axi_arcache    (m05_axi_arcache),
        .m05_axi_arprot     (m05_axi_arprot),
        .m05_axi_arqos      (m05_axi_arqos),
        .m05_axi_arregion   (m05_axi_arregion),
        .m05_axi_aruser     (m05_axi_aruser),
        .m05_axi_arvalid    (m05_axi_arvalid),
        .m05_axi_arready    (m05_axi_arready),
        .m05_axi_rid        (m05_axi_rid),
        .m05_axi_rdata      (m05_axi_rdata),
        .m05_axi_rresp      (m05_axi_rresp),
        .m05_axi_rlast      (m05_axi_rlast),
        .m05_axi_ruser      (m05_axi_ruser),
        .m05_axi_rvalid     (m05_axi_rvalid),
        .m05_axi_rready     (m05_axi_rready),

        // S6: PID
        .m06_axi_awid       (m06_axi_awid),
        .m06_axi_awaddr     (m06_axi_awaddr),
        .m06_axi_awlen      (m06_axi_awlen),
        .m06_axi_awsize     (m06_axi_awsize),
        .m06_axi_awburst    (m06_axi_awburst),
        .m06_axi_awlock     (m06_axi_awlock),
        .m06_axi_awcache    (m06_axi_awcache),
        .m06_axi_awprot     (m06_axi_awprot),
        .m06_axi_awqos      (m06_axi_awqos),
        .m06_axi_awregion   (m06_axi_awregion),
        .m06_axi_awuser     (m06_axi_awuser),
        .m06_axi_awvalid    (m06_axi_awvalid),
        .m06_axi_awready    (m06_axi_awready),
        .m06_axi_wdata      (m06_axi_wdata),
        .m06_axi_wstrb      (m06_axi_wstrb),
        .m06_axi_wlast      (m06_axi_wlast),
        .m06_axi_wuser      (m06_axi_wuser),
        .m06_axi_wvalid     (m06_axi_wvalid),
        .m06_axi_wready     (m06_axi_wready),
        .m06_axi_bid        (m06_axi_bid),
        .m06_axi_bresp      (m06_axi_bresp),
        .m06_axi_buser      (m06_axi_buser),
        .m06_axi_bvalid     (m06_axi_bvalid),
        .m06_axi_bready     (m06_axi_bready),
        .m06_axi_arid       (m06_axi_arid),
        .m06_axi_araddr     (m06_axi_araddr),
        .m06_axi_arlen      (m06_axi_arlen),
        .m06_axi_arsize     (m06_axi_arsize),
        .m06_axi_arburst    (m06_axi_arburst),
        .m06_axi_arlock     (m06_axi_arlock),
        .m06_axi_arcache    (m06_axi_arcache),
        .m06_axi_arprot     (m06_axi_arprot),
        .m06_axi_arqos      (m06_axi_arqos),
        .m06_axi_arregion   (m06_axi_arregion),
        .m06_axi_aruser     (m06_axi_aruser),
        .m06_axi_arvalid    (m06_axi_arvalid),
        .m06_axi_arready    (m06_axi_arready),
        .m06_axi_rid        (m06_axi_rid),
        .m06_axi_rdata      (m06_axi_rdata),
        .m06_axi_rresp      (m06_axi_rresp),
        .m06_axi_rlast      (m06_axi_rlast),
        .m06_axi_ruser      (m06_axi_ruser),
        .m06_axi_rvalid     (m06_axi_rvalid),
        .m06_axi_rready     (m06_axi_rready),

        // S7: PWM Generator
        .m07_axi_awid       (m07_axi_awid),
        .m07_axi_awaddr     (m07_axi_awaddr),
        .m07_axi_awlen      (m07_axi_awlen),
        .m07_axi_awsize     (m07_axi_awsize),
        .m07_axi_awburst    (m07_axi_awburst),
        .m07_axi_awlock     (m07_axi_awlock),
        .m07_axi_awcache    (m07_axi_awcache),
        .m07_axi_awprot     (m07_axi_awprot),
        .m07_axi_awqos      (m07_axi_awqos),
        .m07_axi_awregion   (m07_axi_awregion),
        .m07_axi_awuser     (m07_axi_awuser),
        .m07_axi_awvalid    (m07_axi_awvalid),
        .m07_axi_awready    (m07_axi_awready),
        .m07_axi_wdata      (m07_axi_wdata),
        .m07_axi_wstrb      (m07_axi_wstrb),
        .m07_axi_wlast      (m07_axi_wlast),
        .m07_axi_wuser      (m07_axi_wuser),
        .m07_axi_wvalid     (m07_axi_wvalid),
        .m07_axi_wready     (m07_axi_wready),
        .m07_axi_bid        (m07_axi_bid),
        .m07_axi_bresp      (m07_axi_bresp),
        .m07_axi_buser      (m07_axi_buser),
        .m07_axi_bvalid     (m07_axi_bvalid),
        .m07_axi_bready     (m07_axi_bready),
        .m07_axi_arid       (m07_axi_arid),
        .m07_axi_araddr     (m07_axi_araddr),
        .m07_axi_arlen      (m07_axi_arlen),
        .m07_axi_arsize     (m07_axi_arsize),
        .m07_axi_arburst    (m07_axi_arburst),
        .m07_axi_arlock     (m07_axi_arlock),
        .m07_axi_arcache    (m07_axi_arcache),
        .m07_axi_arprot     (m07_axi_arprot),
        .m07_axi_arqos      (m07_axi_arqos),
        .m07_axi_arregion   (m07_axi_arregion),
        .m07_axi_aruser     (m07_axi_aruser),
        .m07_axi_arvalid    (m07_axi_arvalid),
        .m07_axi_arready    (m07_axi_arready),
        .m07_axi_rid        (m07_axi_rid),
        .m07_axi_rdata      (m07_axi_rdata),
        .m07_axi_rresp      (m07_axi_rresp),
        .m07_axi_rlast      (m07_axi_rlast),
        .m07_axi_ruser      (m07_axi_ruser),
        .m07_axi_rvalid     (m07_axi_rvalid),
        .m07_axi_rready     (m07_axi_rready),

        // S8: Keypad Controller
        .m08_axi_awid       (m08_axi_awid),
        .m08_axi_awaddr     (m08_axi_awaddr),
        .m08_axi_awlen      (m08_axi_awlen),
        .m08_axi_awsize     (m08_axi_awsize),
        .m08_axi_awburst    (m08_axi_awburst),
        .m08_axi_awlock     (m08_axi_awlock),
        .m08_axi_awcache    (m08_axi_awcache),
        .m08_axi_awprot     (m08_axi_awprot),
        .m08_axi_awqos      (m08_axi_awqos),
        .m08_axi_awregion   (m08_axi_awregion),
        .m08_axi_awuser     (m08_axi_awuser),
        .m08_axi_awvalid    (m08_axi_awvalid),
        .m08_axi_awready    (m08_axi_awready),
        .m08_axi_wdata      (m08_axi_wdata),
        .m08_axi_wstrb      (m08_axi_wstrb),
        .m08_axi_wlast      (m08_axi_wlast),
        .m08_axi_wuser      (m08_axi_wuser),
        .m08_axi_wvalid     (m08_axi_wvalid),
        .m08_axi_wready     (m08_axi_wready),
        .m08_axi_bid        (m08_axi_bid),
        .m08_axi_bresp      (m08_axi_bresp),
        .m08_axi_buser      (m08_axi_buser),
        .m08_axi_bvalid     (m08_axi_bvalid),
        .m08_axi_bready     (m08_axi_bready),
        .m08_axi_arid       (m08_axi_arid),
        .m08_axi_araddr     (m08_axi_araddr),
        .m08_axi_arlen      (m08_axi_arlen),
        .m08_axi_arsize     (m08_axi_arsize),
        .m08_axi_arburst    (m08_axi_arburst),
        .m08_axi_arlock     (m08_axi_arlock),
        .m08_axi_arcache    (m08_axi_arcache),
        .m08_axi_arprot     (m08_axi_arprot),
        .m08_axi_arqos      (m08_axi_arqos),
        .m08_axi_arregion   (m08_axi_arregion),
        .m08_axi_aruser     (m08_axi_aruser),
        .m08_axi_arvalid    (m08_axi_arvalid),
        .m08_axi_arready    (m08_axi_arready),
        .m08_axi_rid        (m08_axi_rid),
        .m08_axi_rdata      (m08_axi_rdata),
        .m08_axi_rresp      (m08_axi_rresp),
        .m08_axi_rlast      (m08_axi_rlast),
        .m08_axi_ruser      (m08_axi_ruser),
        .m08_axi_rvalid     (m08_axi_rvalid),
        .m08_axi_rready     (m08_axi_rready),

        // S9: Authentication
        .m09_axi_awid       (m09_axi_awid),
        .m09_axi_awaddr     (m09_axi_awaddr),
        .m09_axi_awlen      (m09_axi_awlen),
        .m09_axi_awsize     (m09_axi_awsize),
        .m09_axi_awburst    (m09_axi_awburst),
        .m09_axi_awlock     (m09_axi_awlock),
        .m09_axi_awcache    (m09_axi_awcache),
        .m09_axi_awprot     (m09_axi_awprot),
        .m09_axi_awqos      (m09_axi_awqos),
        .m09_axi_awregion   (m09_axi_awregion),
        .m09_axi_awuser     (m09_axi_awuser),
        .m09_axi_awvalid    (m09_axi_awvalid),
        .m09_axi_awready    (m09_axi_awready),
        .m09_axi_wdata      (m09_axi_wdata),
        .m09_axi_wstrb      (m09_axi_wstrb),
        .m09_axi_wlast      (m09_axi_wlast),
        .m09_axi_wuser      (m09_axi_wuser),
        .m09_axi_wvalid     (m09_axi_wvalid),
        .m09_axi_wready     (m09_axi_wready),
        .m09_axi_bid        (m09_axi_bid),
        .m09_axi_bresp      (m09_axi_bresp),
        .m09_axi_buser      (m09_axi_buser),
        .m09_axi_bvalid     (m09_axi_bvalid),
        .m09_axi_bready     (m09_axi_bready),
        .m09_axi_arid       (m09_axi_arid),
        .m09_axi_araddr     (m09_axi_araddr),
        .m09_axi_arlen      (m09_axi_arlen),
        .m09_axi_arsize     (m09_axi_arsize),
        .m09_axi_arburst    (m09_axi_arburst),
        .m09_axi_arlock     (m09_axi_arlock),
        .m09_axi_arcache    (m09_axi_arcache),
        .m09_axi_arprot     (m09_axi_arprot),
        .m09_axi_arqos      (m09_axi_arqos),
        .m09_axi_arregion   (m09_axi_arregion),
        .m09_axi_aruser     (m09_axi_aruser),
        .m09_axi_arvalid    (m09_axi_arvalid),
        .m09_axi_arready    (m09_axi_arready),
        .m09_axi_rid        (m09_axi_rid),
        .m09_axi_rdata      (m09_axi_rdata),
        .m09_axi_rresp      (m09_axi_rresp),
        .m09_axi_rlast      (m09_axi_rlast),
        .m09_axi_ruser      (m09_axi_ruser),
        .m09_axi_rvalid     (m09_axi_rvalid),
        .m09_axi_rready     (m09_axi_rready),

        // S10: Buzzer
        .m10_axi_awid       (m10_axi_awid),
        .m10_axi_awaddr     (m10_axi_awaddr),
        .m10_axi_awlen      (m10_axi_awlen),
        .m10_axi_awsize     (m10_axi_awsize),
        .m10_axi_awburst    (m10_axi_awburst),
        .m10_axi_awlock     (m10_axi_awlock),
        .m10_axi_awcache    (m10_axi_awcache),
        .m10_axi_awprot     (m10_axi_awprot),
        .m10_axi_awqos      (m10_axi_awqos),
        .m10_axi_awregion   (m10_axi_awregion),
        .m10_axi_awuser     (m10_axi_awuser),
        .m10_axi_awvalid    (m10_axi_awvalid),
        .m10_axi_awready    (m10_axi_awready),
        .m10_axi_wdata      (m10_axi_wdata),
        .m10_axi_wstrb      (m10_axi_wstrb),
        .m10_axi_wlast      (m10_axi_wlast),
        .m10_axi_wuser      (m10_axi_wuser),
        .m10_axi_wvalid     (m10_axi_wvalid),
        .m10_axi_wready     (m10_axi_wready),
        .m10_axi_bid        (m10_axi_bid),
        .m10_axi_bresp      (m10_axi_bresp),
        .m10_axi_buser      (m10_axi_buser),
        .m10_axi_bvalid     (m10_axi_bvalid),
        .m10_axi_bready     (m10_axi_bready),
        .m10_axi_arid       (m10_axi_arid),
        .m10_axi_araddr     (m10_axi_araddr),
        .m10_axi_arlen      (m10_axi_arlen),
        .m10_axi_arsize     (m10_axi_arsize),
        .m10_axi_arburst    (m10_axi_arburst),
        .m10_axi_arlock     (m10_axi_arlock),
        .m10_axi_arcache    (m10_axi_arcache),
        .m10_axi_arprot     (m10_axi_arprot),
        .m10_axi_arqos      (m10_axi_arqos),
        .m10_axi_arregion   (m10_axi_arregion),
        .m10_axi_aruser     (m10_axi_aruser),
        .m10_axi_arvalid    (m10_axi_arvalid),
        .m10_axi_arready    (m10_axi_arready),
        .m10_axi_rid        (m10_axi_rid),
        .m10_axi_rdata      (m10_axi_rdata),
        .m10_axi_rresp      (m10_axi_rresp),
        .m10_axi_rlast      (m10_axi_rlast),
        .m10_axi_ruser      (m10_axi_ruser),
        .m10_axi_rvalid     (m10_axi_rvalid),
        .m10_axi_rready     (m10_axi_rready),

        // S11: Watchdog
        .m11_axi_awid       (m11_axi_awid),
        .m11_axi_awaddr     (m11_axi_awaddr),
        .m11_axi_awlen      (m11_axi_awlen),
        .m11_axi_awsize     (m11_axi_awsize),
        .m11_axi_awburst    (m11_axi_awburst),
        .m11_axi_awlock     (m11_axi_awlock),
        .m11_axi_awcache    (m11_axi_awcache),
        .m11_axi_awprot     (m11_axi_awprot),
        .m11_axi_awqos      (m11_axi_awqos),
        .m11_axi_awregion   (m11_axi_awregion),
        .m11_axi_awuser     (m11_axi_awuser),
        .m11_axi_awvalid    (m11_axi_awvalid),
        .m11_axi_awready    (m11_axi_awready),
        .m11_axi_wdata      (m11_axi_wdata),
        .m11_axi_wstrb      (m11_axi_wstrb),
        .m11_axi_wlast      (m11_axi_wlast),
        .m11_axi_wuser      (m11_axi_wuser),
        .m11_axi_wvalid     (m11_axi_wvalid),
        .m11_axi_wready     (m11_axi_wready),
        .m11_axi_bid        (m11_axi_bid),
        .m11_axi_bresp      (m11_axi_bresp),
        .m11_axi_buser      (m11_axi_buser),
        .m11_axi_bvalid     (m11_axi_bvalid),
        .m11_axi_bready     (m11_axi_bready),
        .m11_axi_arid       (m11_axi_arid),
        .m11_axi_araddr     (m11_axi_araddr),
        .m11_axi_arlen      (m11_axi_arlen),
        .m11_axi_arsize     (m11_axi_arsize),
        .m11_axi_arburst    (m11_axi_arburst),
        .m11_axi_arlock     (m11_axi_arlock),
        .m11_axi_arcache    (m11_axi_arcache),
        .m11_axi_arprot     (m11_axi_arprot),
        .m11_axi_arqos      (m11_axi_arqos),
        .m11_axi_arregion   (m11_axi_arregion),
        .m11_axi_aruser     (m11_axi_aruser),
        .m11_axi_arvalid    (m11_axi_arvalid),
        .m11_axi_arready    (m11_axi_arready),
        .m11_axi_rid        (m11_axi_rid),
        .m11_axi_rdata      (m11_axi_rdata),
        .m11_axi_rresp      (m11_axi_rresp),
        .m11_axi_rlast      (m11_axi_rlast),
        .m11_axi_ruser      (m11_axi_ruser),
        .m11_axi_rvalid     (m11_axi_rvalid),
        .m11_axi_rready     (m11_axi_rready),

        // S12: ADC
        .m12_axi_awid       (m12_axi_awid),
        .m12_axi_awaddr     (m12_axi_awaddr),
        .m12_axi_awlen      (m12_axi_awlen),
        .m12_axi_awsize     (m12_axi_awsize),
        .m12_axi_awburst    (m12_axi_awburst),
        .m12_axi_awlock     (m12_axi_awlock),
        .m12_axi_awcache    (m12_axi_awcache),
        .m12_axi_awprot     (m12_axi_awprot),
        .m12_axi_awqos      (m12_axi_awqos),
        .m12_axi_awregion   (m12_axi_awregion),
        .m12_axi_awuser     (m12_axi_awuser),
        .m12_axi_awvalid    (m12_axi_awvalid),
        .m12_axi_awready    (m12_axi_awready),
        .m12_axi_wdata      (m12_axi_wdata),
        .m12_axi_wstrb      (m12_axi_wstrb),
        .m12_axi_wlast      (m12_axi_wlast),
        .m12_axi_wuser      (m12_axi_wuser),
        .m12_axi_wvalid     (m12_axi_wvalid),
        .m12_axi_wready     (m12_axi_wready),
        .m12_axi_bid        (m12_axi_bid),
        .m12_axi_bresp      (m12_axi_bresp),
        .m12_axi_buser      (m12_axi_buser),
        .m12_axi_bvalid     (m12_axi_bvalid),
        .m12_axi_bready     (m12_axi_bready),
        .m12_axi_arid       (m12_axi_arid),
        .m12_axi_araddr     (m12_axi_araddr),
        .m12_axi_arlen      (m12_axi_arlen),
        .m12_axi_arsize     (m12_axi_arsize),
        .m12_axi_arburst    (m12_axi_arburst),
        .m12_axi_arlock     (m12_axi_arlock),
        .m12_axi_arcache    (m12_axi_arcache),
        .m12_axi_arprot     (m12_axi_arprot),
        .m12_axi_arqos      (m12_axi_arqos),
        .m12_axi_arregion   (m12_axi_arregion),
        .m12_axi_aruser     (m12_axi_aruser),
        .m12_axi_arvalid    (m12_axi_arvalid),
        .m12_axi_arready    (m12_axi_arready),
        .m12_axi_rid        (m12_axi_rid),
        .m12_axi_rdata      (m12_axi_rdata),
        .m12_axi_rresp      (m12_axi_rresp),
        .m12_axi_rlast      (m12_axi_rlast),
        .m12_axi_ruser      (m12_axi_ruser),
        .m12_axi_rvalid     (m12_axi_rvalid),
        .m12_axi_rready     (m12_axi_rready),

        // S13: DMA Registers
        .m13_axi_awid       (m13_axi_awid),
        .m13_axi_awaddr     (m13_axi_awaddr),
        .m13_axi_awlen      (m13_axi_awlen),
        .m13_axi_awsize     (m13_axi_awsize),
        .m13_axi_awburst    (m13_axi_awburst),
        .m13_axi_awlock     (m13_axi_awlock),
        .m13_axi_awcache    (m13_axi_awcache),
        .m13_axi_awprot     (m13_axi_awprot),
        .m13_axi_awqos      (m13_axi_awqos),
        .m13_axi_awregion   (m13_axi_awregion),
        .m13_axi_awuser     (m13_axi_awuser),
        .m13_axi_awvalid    (m13_axi_awvalid),
        .m13_axi_awready    (m13_axi_awready),
        .m13_axi_wdata      (m13_axi_wdata),
        .m13_axi_wstrb      (m13_axi_wstrb),
        .m13_axi_wlast      (m13_axi_wlast),
        .m13_axi_wuser      (m13_axi_wuser),
        .m13_axi_wvalid     (m13_axi_wvalid),
        .m13_axi_wready     (m13_axi_wready),
        .m13_axi_bid        (m13_axi_bid),
        .m13_axi_bresp      (m13_axi_bresp),
        .m13_axi_buser      (m13_axi_buser),
        .m13_axi_bvalid     (m13_axi_bvalid),
        .m13_axi_bready     (m13_axi_bready),
        .m13_axi_arid       (m13_axi_arid),
        .m13_axi_araddr     (m13_axi_araddr),
        .m13_axi_arlen      (m13_axi_arlen),
        .m13_axi_arsize     (m13_axi_arsize),
        .m13_axi_arburst    (m13_axi_arburst),
        .m13_axi_arlock     (m13_axi_arlock),
        .m13_axi_arcache    (m13_axi_arcache),
        .m13_axi_arprot     (m13_axi_arprot),
        .m13_axi_arqos      (m13_axi_arqos),
        .m13_axi_arregion   (m13_axi_arregion),
        .m13_axi_aruser     (m13_axi_aruser),
        .m13_axi_arvalid    (m13_axi_arvalid),
        .m13_axi_arready    (m13_axi_arready),
        .m13_axi_rid        (m13_axi_rid),
        .m13_axi_rdata      (m13_axi_rdata),
        .m13_axi_rresp      (m13_axi_rresp),
        .m13_axi_rlast      (m13_axi_rlast),
        .m13_axi_ruser      (m13_axi_ruser),
        .m13_axi_rvalid     (m13_axi_rvalid),
        .m13_axi_rready     (m13_axi_rready),

        // S14: Seven-Segment
        .m14_axi_awid       (m14_axi_awid),
        .m14_axi_awaddr     (m14_axi_awaddr),
        .m14_axi_awlen      (m14_axi_awlen),
        .m14_axi_awsize     (m14_axi_awsize),
        .m14_axi_awburst    (m14_axi_awburst),
        .m14_axi_awlock     (m14_axi_awlock),
        .m14_axi_awcache    (m14_axi_awcache),
        .m14_axi_awprot     (m14_axi_awprot),
        .m14_axi_awqos      (m14_axi_awqos),
        .m14_axi_awregion   (m14_axi_awregion),
        .m14_axi_awuser     (m14_axi_awuser),
        .m14_axi_awvalid    (m14_axi_awvalid),
        .m14_axi_awready    (m14_axi_awready),
        .m14_axi_wdata      (m14_axi_wdata),
        .m14_axi_wstrb      (m14_axi_wstrb),
        .m14_axi_wlast      (m14_axi_wlast),
        .m14_axi_wuser      (m14_axi_wuser),
        .m14_axi_wvalid     (m14_axi_wvalid),
        .m14_axi_wready     (m14_axi_wready),
        .m14_axi_bid        (m14_axi_bid),
        .m14_axi_bresp      (m14_axi_bresp),
        .m14_axi_buser      (m14_axi_buser),
        .m14_axi_bvalid     (m14_axi_bvalid),
        .m14_axi_bready     (m14_axi_bready),
        .m14_axi_arid       (m14_axi_arid),
        .m14_axi_araddr     (m14_axi_araddr),
        .m14_axi_arlen      (m14_axi_arlen),
        .m14_axi_arsize     (m14_axi_arsize),
        .m14_axi_arburst    (m14_axi_arburst),
        .m14_axi_arlock     (m14_axi_arlock),
        .m14_axi_arcache    (m14_axi_arcache),
        .m14_axi_arprot     (m14_axi_arprot),
        .m14_axi_arqos      (m14_axi_arqos),
        .m14_axi_arregion   (m14_axi_arregion),
        .m14_axi_aruser     (m14_axi_aruser),
        .m14_axi_arvalid    (m14_axi_arvalid),
        .m14_axi_arready    (m14_axi_arready),
        .m14_axi_rid        (m14_axi_rid),
        .m14_axi_rdata      (m14_axi_rdata),
        .m14_axi_rresp      (m14_axi_rresp),
        .m14_axi_rlast      (m14_axi_rlast),
        .m14_axi_ruser      (m14_axi_ruser),
        .m14_axi_rvalid     (m14_axi_rvalid),
        .m14_axi_rready     (m14_axi_rready)
    );

    // ============================================================
    // Direct Signal Adaptation for S4 UART (axi_uart_top)
    // ============================================================
    wire [11:0] uart_bid_w;
    wire [11:0] uart_rid_w;

    wire uart_awready_w;
    wire uart_wready_w;
    wire uart_bvalid_w;
    wire [1:0] uart_bresp_w;
    wire uart_arready_w;
    wire [31:0] uart_rdata_w;
    wire [1:0] uart_rresp_w;
    wire uart_rvalid_w;

    // Connect slave response signals back to interconnect m04
    assign m04_axi_awready = uart_awready_w;
    assign m04_axi_wready  = uart_wready_w;
    assign m04_axi_bid     = uart_bid_w[7:0];
    assign m04_axi_bresp   = uart_bresp_w;
    assign m04_axi_buser   = {BUSER_WIDTH{1'b0}};
    assign m04_axi_bvalid  = uart_bvalid_w;

    assign m04_axi_arready = uart_arready_w;
    assign m04_axi_rid     = uart_rid_w[7:0];
    assign m04_axi_rdata   = uart_rdata_w;
    assign m04_axi_rresp   = uart_rresp_w;
    assign m04_axi_rlast   = uart_rvalid_w; // Single-beat read terminates on valid data beat
    assign m04_axi_ruser   = {RUSER_WIDTH{1'b0}};
    assign m04_axi_rvalid  = uart_rvalid_w;

    axi_uart_top u_axi_uart (
        .fixed_clk_i      (fixed_clk),
        .axi_aclk_i       (clk),
        .axi_aresetn_i    (~rst),

        // Read address channel
        .axi_arid_i       ({4'b0000, m04_axi_arid}),
        .axi_araddr_i     (m04_axi_araddr[4:0]),
        .axi_arvalid_i    (m04_axi_arvalid),
        .axi_arready_o    (uart_arready_w),

        // Read data channel
        .axi_rid_o        (uart_rid_w),
        .axi_rdata_o      (uart_rdata_w),
        .axi_rresp_o      (uart_rresp_w),
        .axi_rvalid_o     (uart_rvalid_w),
        .axi_rready_i     (m04_axi_rready),

        // Write address channel
        .axi_awid_i       ({4'b0000, m04_axi_awid}),
        .axi_awaddr_i     (m04_axi_awaddr[4:0]),
        .axi_awvalid_i    (m04_axi_awvalid),
        .axi_awready_o    (uart_awready_w),

        // Write data channel
        .axi_wdata_i      (m04_axi_wdata),
        .axi_wstrb_i      (m04_axi_wstrb),
        .axi_wvalid_i     (m04_axi_wvalid),
        .axi_wready_o     (uart_wready_w),

        // Write response channel
        .axi_bid_o        (uart_bid_w),
        .axi_bresp_o      (uart_bresp_w),
        .axi_bvalid_o     (uart_bvalid_w),
        .axi_bready_i     (m04_axi_bready),

        // UART pins and interrupt
        .read_interrupt_o (uart_irq),
        .uart_rx_i        (uart_rx),
        .uart_tx_o        (uart_tx)
    );

    // >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    // >>> PWM S10 INTEGRATION - ADDED CODE - BEGIN
    // >>> Direct Signal Adaptation for S10 PWM (myip_v1_0)
    // >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

    // Internal wires for PWM AXI4-Lite outputs
    wire        pwm_awready_w;
    wire        pwm_wready_w;
    wire [1:0]  pwm_bresp_w;
    wire        pwm_bvalid_w;
    wire        pwm_arready_w;
    wire [31:0] pwm_rdata_w;
    wire [1:0]  pwm_rresp_w;
    wire        pwm_rvalid_w;

    // Connect PWM AXI4-Lite slave responses back to interconnect m10
    // AW channel
    assign m10_axi_awready = pwm_awready_w;
    // W channel
    assign m10_axi_wready  = pwm_wready_w;
    // B channel
    assign m10_axi_bid     = {ID_WIDTH{1'b0}};     // AXI4-Lite: no BID — tie to zero
    assign m10_axi_bresp   = pwm_bresp_w;
    assign m10_axi_buser   = {BUSER_WIDTH{1'b0}};  // AXI4-Lite: no BUSER
    assign m10_axi_bvalid  = pwm_bvalid_w;
    // AR channel
    assign m10_axi_arready = pwm_arready_w;
    // R channel
    assign m10_axi_rid     = {ID_WIDTH{1'b0}};     // AXI4-Lite: no RID — tie to zero
    assign m10_axi_rdata   = pwm_rdata_w;
    assign m10_axi_rresp   = pwm_rresp_w;
    assign m10_axi_rlast   = pwm_rvalid_w;         // AXI4-Lite: single-beat; rlast=rvalid
    assign m10_axi_ruser   = {RUSER_WIDTH{1'b0}};  // AXI4-Lite: no RUSER
    assign m10_axi_rvalid  = pwm_rvalid_w;

    // Saturated 16-bit signed to 8-bit unsigned duty cycle conversion for PWM
    wire [7:0] pid_to_pwm_duty = (pid_out[15])     ? 8'h00 :
                                 (|pid_out[14:8])  ? 8'hFF :
                                 pid_out[7:0];

    // PWM IP instantiation (existing verified AXI4-Lite PWM)
    myip_v1_0 #(
        .C_S00_AXI_DATA_WIDTH (DATA_WIDTH),
        .C_S00_AXI_ADDR_WIDTH (4)
    ) u_pwm_s10 (
        // Clock and reset
        .s00_axi_aclk    (clk),
        .s00_axi_aresetn (~rst),         // invert: main_top rst is active-HIGH

        // PWM functional output
        .PWM_OUT         (PWM_OUT),

        // Hardware closed-loop duty input from PID
        .hw_duty_i       (pid_to_pwm_duty),
        .hw_duty_valid_i (pid_out_valid),

        // AW channel
        .s00_axi_awaddr  (m10_axi_awaddr[3:0]),
        .s00_axi_awprot  (m10_axi_awprot),
        .s00_axi_awvalid (m10_axi_awvalid),
        .s00_axi_awready (pwm_awready_w),

        // W channel
        .s00_axi_wdata   (m10_axi_wdata),
        .s00_axi_wstrb   (m10_axi_wstrb),
        .s00_axi_wvalid  (m10_axi_wvalid),
        .s00_axi_wready  (pwm_wready_w),

        // B channel
        .s00_axi_bresp   (pwm_bresp_w),
        .s00_axi_bvalid  (pwm_bvalid_w),
        .s00_axi_bready  (m10_axi_bready),

        // AR channel
        .s00_axi_araddr  (m10_axi_araddr[3:0]),
        .s00_axi_arprot  (m10_axi_arprot),
        .s00_axi_arvalid (m10_axi_arvalid),
        .s00_axi_arready (pwm_arready_w),

        // R channel
        .s00_axi_rdata   (pwm_rdata_w),
        .s00_axi_rresp   (pwm_rresp_w),
        .s00_axi_rvalid  (pwm_rvalid_w),
        .s00_axi_rready  (m10_axi_rready)
    );

    // <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    // <<< PWM S10 INTEGRATION - ADDED CODE - END
    // <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    // ============================================================
    // Direct Signal Adaptation for S2 GPIO (gpio_axi)
    // ============================================================
    wire        gpio_awready_w;
    wire        gpio_wready_w;
    wire [1:0]  gpio_bresp_w;
    wire        gpio_bvalid_w;
    wire        gpio_arready_w;
    wire [31:0] gpio_rdata_w;
    wire [1:0]  gpio_rresp_w;
    wire        gpio_rvalid_w;

    assign m02_axi_awready = gpio_awready_w;
    assign m02_axi_wready  = gpio_wready_w;
    assign m02_axi_bid     = {ID_WIDTH{1'b0}};
    assign m02_axi_bresp   = gpio_bresp_w;
    assign m02_axi_buser   = {BUSER_WIDTH{1'b0}};
    assign m02_axi_bvalid  = gpio_bvalid_w;

    assign m02_axi_arready = gpio_arready_w;
    assign m02_axi_rid     = {ID_WIDTH{1'b0}};
    assign m02_axi_rdata   = gpio_rdata_w;
    assign m02_axi_rresp   = gpio_rresp_w;
    assign m02_axi_rlast   = gpio_rvalid_w;
    assign m02_axi_ruser   = {RUSER_WIDTH{1'b0}};
    assign m02_axi_rvalid  = gpio_rvalid_w;

    gpio_axi #(
        .NUM_BITS (32)
    ) u_gpio (
        .s_axi_aclk    (clk),
        .s_axi_aresetn (~rst),

        .s_axi_awaddr  ({20'h00000, m02_axi_awaddr[11:0]}),
        .s_axi_awprot  (m02_axi_awprot),
        .s_axi_awvalid (m02_axi_awvalid),
        .s_axi_awready (gpio_awready_w),

        .s_axi_wdata   (m02_axi_wdata),
        .s_axi_wstrb   (m02_axi_wstrb),
        .s_axi_wvalid  (m02_axi_wvalid),
        .s_axi_wready  (gpio_wready_w),

        .s_axi_bresp   (gpio_bresp_w),
        .s_axi_bvalid  (gpio_bvalid_w),
        .s_axi_bready  (m02_axi_bready),

        .s_axi_araddr  ({20'h00000, m02_axi_araddr[11:0]}),
        .s_axi_arprot  (m02_axi_arprot),
        .s_axi_arvalid (m02_axi_arvalid),
        .s_axi_arready (gpio_arready_w),

        .s_axi_rdata   (gpio_rdata_w),
        .s_axi_rresp   (gpio_rresp_w),
        .s_axi_rvalid  (gpio_rvalid_w),
        .s_axi_rready  (m02_axi_rready),

        .io            (gpio_io),
        .intr          (gpio_intr)
    );

    // ============================================================
    // Direct Signal Adaptation for S3 Timer (timer_axi)
    // ============================================================
    wire        timer_awready_w;
    wire        timer_wready_w;
    wire [1:0]  timer_bresp_w;
    wire        timer_bvalid_w;
    wire        timer_arready_w;
    wire [31:0] timer_rdata_w;
    wire [1:0]  timer_rresp_w;
    wire        timer_rvalid_w;

    assign m03_axi_awready = timer_awready_w;
    assign m03_axi_wready  = timer_wready_w;
    assign m03_axi_bid     = {ID_WIDTH{1'b0}};
    assign m03_axi_bresp   = timer_bresp_w;
    assign m03_axi_buser   = {BUSER_WIDTH{1'b0}};
    assign m03_axi_bvalid  = timer_bvalid_w;

    assign m03_axi_arready = timer_arready_w;
    assign m03_axi_rid     = {ID_WIDTH{1'b0}};
    assign m03_axi_rdata   = timer_rdata_w;
    assign m03_axi_rresp   = timer_rresp_w;
    assign m03_axi_rlast   = timer_rvalid_w;
    assign m03_axi_ruser   = {RUSER_WIDTH{1'b0}};
    assign m03_axi_rvalid  = timer_rvalid_w;

    timer_axi u_timer (
        .aclk         (clk),
        .aresetn      (~rst),

        .awaddr       ({20'h00000, m03_axi_awaddr[11:0]}),
        .awprot       (m03_axi_awprot),
        .awvalid      (m03_axi_awvalid),
        .awready      (timer_awready_w),

        .wdata        (m03_axi_wdata),
        .wstrb        (m03_axi_wstrb),
        .wvalid       (m03_axi_wvalid),
        .wready       (timer_wready_w),

        .bresp        (timer_bresp_w),
        .bvalid       (timer_bvalid_w),
        .bready       (m03_axi_bready),

        .araddr       ({20'h00000, m03_axi_araddr[11:0]}),
        .arprot       (m03_axi_arprot),
        .arvalid      (m03_axi_arvalid),
        .arready      (timer_arready_w),

        .rdata        (timer_rdata_w),
        .rresp        (timer_rresp_w),
        .rvalid       (timer_rvalid_w),
        .rready       (m03_axi_rready),

        .ext_meas_i   (timer_ext_meas),
        .capture_i    (timer_capture),
        .pwm_o        (timer_pwm),
        .trigger_o    (timer_trigger),
        .irq          (timer_intr)
    );

    // ============================================================
    // Direct Signal Adaptation for S8 Encoder (enc_top)
    // ============================================================
    assign m08_axi_buser = {BUSER_WIDTH{1'b0}};
    assign m08_axi_ruser = {RUSER_WIDTH{1'b0}};

    enc_top #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (12),
        .ID_WIDTH   (ID_WIDTH)
    ) u_encoder (
        .s_axi_aclk     (clk),
        .s_axi_aresetn  (~rst),

        .s_axi_awid     (m08_axi_awid),
        .s_axi_awaddr   (m08_axi_awaddr[11:0]),
        .s_axi_awlen    (m08_axi_awlen),
        .s_axi_awsize   (m08_axi_awsize),
        .s_axi_awburst  (m08_axi_awburst),
        .s_axi_awlock   (m08_axi_awlock),
        .s_axi_awcache  (m08_axi_awcache),
        .s_axi_awprot   (m08_axi_awprot),
        .s_axi_awvalid  (m08_axi_awvalid),
        .s_axi_awready  (m08_axi_awready),

        .s_axi_wdata    (m08_axi_wdata),
        .s_axi_wstrb    (m08_axi_wstrb),
        .s_axi_wlast    (m08_axi_wlast),
        .s_axi_wvalid   (m08_axi_wvalid),
        .s_axi_wready   (m08_axi_wready),

        .s_axi_bid      (m08_axi_bid),
        .s_axi_bresp    (m08_axi_bresp),
        .s_axi_bvalid   (m08_axi_bvalid),
        .s_axi_bready   (m08_axi_bready),

        .s_axi_arid     (m08_axi_arid),
        .s_axi_araddr   (m08_axi_araddr[11:0]),
        .s_axi_arlen    (m08_axi_arlen),
        .s_axi_arsize   (m08_axi_arsize),
        .s_axi_arburst  (m08_axi_arburst),
        .s_axi_arlock   (m08_axi_arlock),
        .s_axi_arcache  (m08_axi_arcache),
        .s_axi_arprot   (m08_axi_arprot),
        .s_axi_arvalid  (m08_axi_arvalid),
        .s_axi_arready  (m08_axi_arready),

        .s_axi_rid      (m08_axi_rid),
        .s_axi_rdata    (m08_axi_rdata),
        .s_axi_rresp    (m08_axi_rresp),
        .s_axi_rlast    (m08_axi_rlast),
        .s_axi_rvalid   (m08_axi_rvalid),
        .s_axi_rready   (m08_axi_rready),

        .enc_a_i        (enc_a),
        .enc_b_i        (enc_b),
        .enc_index_i    (enc_index),
        .drive_active_i (enc_drive_active),

        .speed_o        (enc_speed),
        .speed_valid_o  (enc_speed_valid),
        .count_valid_o  (enc_count_valid),
        .dir_o          (enc_dir),
        .fault_o        (enc_fault),
        .inta_o         (enc_intr)
    );

    // ============================================================
    // Direct Signal Adaptation for S9 PID Controller (pid_top)
    // ============================================================
    assign m09_axi_buser = {BUSER_WIDTH{1'b0}};
    assign m09_axi_ruser = {RUSER_WIDTH{1'b0}};

    pid_top #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (12),
        .ID_WIDTH   (ID_WIDTH)
    ) u_pid (
        .s_axi_aclk      (clk),
        .s_axi_aresetn   (~rst),

        .s_axi_awid      (m09_axi_awid),
        .s_axi_awaddr    (m09_axi_awaddr[11:0]),
        .s_axi_awlen     (m09_axi_awlen),
        .s_axi_awsize    (m09_axi_awsize),
        .s_axi_awburst   (m09_axi_awburst),
        .s_axi_awlock    (m09_axi_awlock),
        .s_axi_awcache   (m09_axi_awcache),
        .s_axi_awprot    (m09_axi_awprot),
        .s_axi_awvalid   (m09_axi_awvalid),
        .s_axi_awready   (m09_axi_awready),

        .s_axi_wdata     (m09_axi_wdata),
        .s_axi_wstrb     (m09_axi_wstrb),
        .s_axi_wlast     (m09_axi_wlast),
        .s_axi_wvalid    (m09_axi_wvalid),
        .s_axi_wready    (m09_axi_wready),

        .s_axi_bid       (m09_axi_bid),
        .s_axi_bresp     (m09_axi_bresp),
        .s_axi_bvalid    (m09_axi_bvalid),
        .s_axi_bready    (m09_axi_bready),

        .s_axi_arid      (m09_axi_arid),
        .s_axi_araddr    (m09_axi_araddr[11:0]),
        .s_axi_arlen     (m09_axi_arlen),
        .s_axi_arsize    (m09_axi_arsize),
        .s_axi_arburst   (m09_axi_arburst),
        .s_axi_arlock    (m09_axi_arlock),
        .s_axi_arcache   (m09_axi_arcache),
        .s_axi_arprot    (m09_axi_arprot),
        .s_axi_arvalid   (m09_axi_arvalid),
        .s_axi_arready   (m09_axi_arready),

        .s_axi_rid       (m09_axi_rid),
        .s_axi_rdata     (m09_axi_rdata),
        .s_axi_rresp     (m09_axi_rresp),
        .s_axi_rlast     (m09_axi_rlast),
        .s_axi_rvalid    (m09_axi_rvalid),
        .s_axi_rready    (m09_axi_rready),

        .tick_i          (timer_trigger),
        .actual_i        (enc_speed),
        .pid_out_o       (pid_out),
        .pid_out_valid_o (pid_out_valid),
        .sat_flag_o      (pid_sat_flag),
        .inta_o          (pid_intr)
    );

endmodule

`default_nettype wire
