`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// Module: soc_top
//
// Description:
//   Top-level SoC module integrating the CHIPS Alliance VeeR EL2 RISC-V core
//   with the 3-master x 15-slave AXI interconnect subsystem and six verified
//   peripherals (GPIO, Timer, UART, Encoder, PID, PWM), with complete hardware
//   hybrid feedback loop preservation.
//
//   Master Mappings:
//     - M0: VeeR EL2 IFU via 64b->32b AXI width downconverter (s00_axi)
//     - M1: VeeR EL2 LSU via 64b->32b AXI width downconverter (s01_axi)
//     - M2: DMA Master port exposed externally (s02_axi)
//
//   Slave Mappings (through interconnect):
//     - S0 : IMEM (0x4000_0000, 64 KiB)
//     - S1 : DMEM (0x4002_0000, 64 KiB)
//     - S2 : GPIO (0x4003_1000, 4 KiB) - Internal
//     - S3 : Timer (0x4003_3000, 4 KiB) - Internal
//     - S4 : UART (0x4003_5000, 4 KiB) - Internal
//     - S5..S7: Reserved / Disabled
//     - S8 : Quadrature Encoder (0x4003_D000, 4 KiB) - Internal
//     - S9 : PID Controller (0x4003_F000, 4 KiB) - Internal
//     - S10: PWM (0x4004_1000, 4 KiB) - Internal
//     - S11..S14: Reserved / Disabled
// ============================================================================

module soc_top
  import el2_pkg::*;
#(
    parameter DATA_WIDTH       = 32,
    parameter ADDR_WIDTH       = 32,
    parameter STRB_WIDTH       = (DATA_WIDTH/8),
    parameter ID_WIDTH         = 8,
    parameter AWUSER_WIDTH     = 1,
    parameter WUSER_WIDTH      = 1,
    parameter BUSER_WIDTH      = 1,
    parameter ARUSER_WIDTH     = 1,
    parameter RUSER_WIDTH      = 1,
    parameter USE_INTERNAL_MEM = 1,
    `include "el2_param.vh"
)(
    // Clocks and Resets
    input  wire                     clk,
    input  wire                     fixed_clk,
    input  wire                     rst,

    // UART External Pins & Interrupt
    input  wire                     uart_rx,
    output wire                     uart_tx,
    output wire                     uart_irq,

    // PWM Output
    output wire                     PWM_OUT,

    // GPIO IO & Interrupt
    inout  wire [31:0]              gpio_io,
    output wire                     gpio_intr,

    // Timer IO & Interrupt
    input  wire                     timer_ext_meas,
    input  wire                     timer_capture,
    output wire                     timer_pwm,
    output wire                     timer_trigger,
    output wire                     timer_intr,

    // Quadrature Encoder IO & Interrupt
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

    // PID Controller IO & Interrupt
    output wire [15:0]              pid_out,
    output wire                     pid_out_valid,
    output wire                     pid_sat_flag,
    output wire                     pid_intr,

    // Preserved External DMA Master (M2)
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

    // Core Trace & Status
    output wire [31:0]              trace_rv_i_insn_ip,
    output wire [31:0]              trace_rv_i_address_ip,
    output wire                     trace_rv_i_valid_ip,
    output wire                     trace_rv_i_exception_ip,
    output wire                     trace_rv_i_interrupt_ip,
    output wire                     o_cpu_halt_status,
    output wire                     o_debug_mode_status
);

    // ============================================================
    // Core VeeR EL2 Interface Signals (64-bit)
    // ============================================================
    // IFU
    wire                            core_ifu_arvalid;
    wire                            core_ifu_arready;
    wire [pt.IFU_BUS_TAG-1:0]       core_ifu_arid;
    wire [31:0]                     core_ifu_araddr;
    wire [3:0]                      core_ifu_arregion;
    wire [7:0]                      core_ifu_arlen;
    wire [2:0]                      core_ifu_arsize;
    wire [1:0]                      core_ifu_arburst;
    wire                            core_ifu_arlock;
    wire [3:0]                      core_ifu_arcache;
    wire [2:0]                      core_ifu_arprot;
    wire [3:0]                      core_ifu_arqos;
    wire                            core_ifu_rvalid;
    wire                            core_ifu_rready;
    wire [pt.IFU_BUS_TAG-1:0]       core_ifu_rid;
    wire [63:0]                     core_ifu_rdata;
    wire [1:0]                      core_ifu_rresp;
    wire                            core_ifu_rlast;

    // LSU
    wire                            core_lsu_awvalid;
    wire                            core_lsu_awready;
    wire [pt.LSU_BUS_TAG-1:0]       core_lsu_awid;
    wire [31:0]                     core_lsu_awaddr;
    wire [3:0]                      core_lsu_awregion;
    wire [7:0]                      core_lsu_awlen;
    wire [2:0]                      core_lsu_awsize;
    wire [1:0]                      core_lsu_awburst;
    wire                            core_lsu_awlock;
    wire [3:0]                      core_lsu_awcache;
    wire [2:0]                      core_lsu_awprot;
    wire [3:0]                      core_lsu_awqos;
    wire                            core_lsu_wvalid;
    wire                            core_lsu_wready;
    wire [63:0]                     core_lsu_wdata;
    wire [7:0]                      core_lsu_wstrb;
    wire                            core_lsu_wlast;
    wire                            core_lsu_bvalid;
    wire                            core_lsu_bready;
    wire [1:0]                      core_lsu_bresp;
    wire [pt.LSU_BUS_TAG-1:0]       core_lsu_bid;

    wire                            core_lsu_arvalid;
    wire                            core_lsu_arready;
    wire [pt.LSU_BUS_TAG-1:0]       core_lsu_arid;
    wire [31:0]                     core_lsu_araddr;
    wire [3:0]                      core_lsu_arregion;
    wire [7:0]                      core_lsu_arlen;
    wire [2:0]                      core_lsu_arsize;
    wire [1:0]                      core_lsu_arburst;
    wire                            core_lsu_arlock;
    wire [3:0]                      core_lsu_arcache;
    wire [2:0]                      core_lsu_arprot;
    wire [3:0]                      core_lsu_arqos;
    wire                            core_lsu_rvalid;
    wire                            core_lsu_rready;
    wire [pt.LSU_BUS_TAG-1:0]       core_lsu_rid;
    wire [63:0]                     core_lsu_rdata;
    wire [1:0]                      core_lsu_rresp;
    wire                            core_lsu_rlast;

    // Core Interrupt bus (PIC)
    wire [pt.PIC_TOTAL_INT:1]       core_extintsrc_req;

    assign core_extintsrc_req[1] = uart_irq;
    assign core_extintsrc_req[2] = gpio_intr;
    assign core_extintsrc_req[3] = timer_intr;
    assign core_extintsrc_req[4] = enc_intr;
    assign core_extintsrc_req[5] = pid_intr;
    generate
        if (pt.PIC_TOTAL_INT > 5) begin : GEN_PIC_TIE_OFF
            assign core_extintsrc_req[pt.PIC_TOTAL_INT:6] = '0;
        end
    endgenerate

    // ============================================================
    // VeeR EL2 Core Wrapper Instance
    // ============================================================
    veer_wrapper u_veer_core (
        .clk                        (clk),
        .rst_l                      (~rst),
        .dbg_rst_l                  (~rst),
        .rst_vec                    (31'h2000_0000), // Reset PC = 32'h4000_0000 (IMEM base)
        .nmi_int                    (1'b0),
        .nmi_vec                    (31'd0),
        .jtag_id                    (31'd1),

        // Trace
        .trace_rv_i_insn_ip         (trace_rv_i_insn_ip),
        .trace_rv_i_address_ip      (trace_rv_i_address_ip),
        .trace_rv_i_valid_ip        (trace_rv_i_valid_ip),
        .trace_rv_i_exception_ip    (trace_rv_i_exception_ip),
        .trace_rv_i_ecause_ip       (),
        .trace_rv_i_interrupt_ip    (trace_rv_i_interrupt_ip),
        .trace_rv_i_tval_ip         (),

        // LSU AXI (64-bit)
        .lsu_axi_awvalid            (core_lsu_awvalid),
        .lsu_axi_awready            (core_lsu_awready),
        .lsu_axi_awid               (core_lsu_awid),
        .lsu_axi_awaddr             (core_lsu_awaddr),
        .lsu_axi_awregion           (core_lsu_awregion),
        .lsu_axi_awlen              (core_lsu_awlen),
        .lsu_axi_awsize             (core_lsu_awsize),
        .lsu_axi_awburst            (core_lsu_awburst),
        .lsu_axi_awlock             (core_lsu_awlock),
        .lsu_axi_awcache            (core_lsu_awcache),
        .lsu_axi_awprot             (core_lsu_awprot),
        .lsu_axi_awqos              (core_lsu_awqos),
        .lsu_axi_wvalid             (core_lsu_wvalid),
        .lsu_axi_wready             (core_lsu_wready),
        .lsu_axi_wdata              (core_lsu_wdata),
        .lsu_axi_wstrb              (core_lsu_wstrb),
        .lsu_axi_wlast              (core_lsu_wlast),
        .lsu_axi_bvalid             (core_lsu_bvalid),
        .lsu_axi_bready             (core_lsu_bready),
        .lsu_axi_bresp              (core_lsu_bresp),
        .lsu_axi_bid                (core_lsu_bid),

        .lsu_axi_arvalid            (core_lsu_arvalid),
        .lsu_axi_arready            (core_lsu_arready),
        .lsu_axi_arid               (core_lsu_arid),
        .lsu_axi_araddr             (core_lsu_araddr),
        .lsu_axi_arregion           (core_lsu_arregion),
        .lsu_axi_arlen              (core_lsu_arlen),
        .lsu_axi_arsize             (core_lsu_arsize),
        .lsu_axi_arburst            (core_lsu_arburst),
        .lsu_axi_arlock             (core_lsu_arlock),
        .lsu_axi_arcache            (core_lsu_arcache),
        .lsu_axi_arprot             (core_lsu_arprot),
        .lsu_axi_arqos              (core_lsu_arqos),
        .lsu_axi_rvalid             (core_lsu_rvalid),
        .lsu_axi_rready             (core_lsu_rready),
        .lsu_axi_rid                (core_lsu_rid),
        .lsu_axi_rdata              (core_lsu_rdata),
        .lsu_axi_rresp              (core_lsu_rresp),
        .lsu_axi_rlast              (core_lsu_rlast),

        // IFU AXI (64-bit)
        .ifu_axi_awvalid            (),
        .ifu_axi_awready            (1'b0),
        .ifu_axi_awid               (),
        .ifu_axi_awaddr             (),
        .ifu_axi_awregion           (),
        .ifu_axi_awlen              (),
        .ifu_axi_awsize             (),
        .ifu_axi_awburst            (),
        .ifu_axi_awlock             (),
        .ifu_axi_awcache            (),
        .ifu_axi_awprot             (),
        .ifu_axi_awqos              (),
        .ifu_axi_wvalid             (),
        .ifu_axi_wready             (1'b0),
        .ifu_axi_wdata              (),
        .ifu_axi_wstrb              (),
        .ifu_axi_wlast              (),
        .ifu_axi_bvalid             (1'b0),
        .ifu_axi_bready             (),
        .ifu_axi_bresp              (2'b00),
        .ifu_axi_bid                ('0),

        .ifu_axi_arvalid            (core_ifu_arvalid),
        .ifu_axi_arready            (core_ifu_arready),
        .ifu_axi_arid               (core_ifu_arid),
        .ifu_axi_araddr             (core_ifu_araddr),
        .ifu_axi_arregion           (core_ifu_arregion),
        .ifu_axi_arlen              (core_ifu_arlen),
        .ifu_axi_arsize             (core_ifu_arsize),
        .ifu_axi_arburst            (core_ifu_arburst),
        .ifu_axi_arlock             (core_ifu_arlock),
        .ifu_axi_arcache            (core_ifu_arcache),
        .ifu_axi_arprot             (core_ifu_arprot),
        .ifu_axi_arqos              (core_ifu_arqos),
        .ifu_axi_rvalid             (core_ifu_rvalid),
        .ifu_axi_rready             (core_ifu_rready),
        .ifu_axi_rid                (core_ifu_rid),
        .ifu_axi_rdata              (core_ifu_rdata),
        .ifu_axi_rresp              (core_ifu_rresp),
        .ifu_axi_rlast              (core_ifu_rlast),

        // SB AXI (debug)
        .sb_axi_awvalid             (),
        .sb_axi_awready             (1'b0),
        .sb_axi_awid                (),
        .sb_axi_awaddr              (),
        .sb_axi_awregion            (),
        .sb_axi_awlen               (),
        .sb_axi_awsize              (),
        .sb_axi_awburst             (),
        .sb_axi_awlock              (),
        .sb_axi_awcache             (),
        .sb_axi_awprot              (),
        .sb_axi_awqos               (),
        .sb_axi_wvalid              (),
        .sb_axi_wready              (1'b0),
        .sb_axi_wdata               (),
        .sb_axi_wstrb               (),
        .sb_axi_wlast               (),
        .sb_axi_bvalid              (1'b0),
        .sb_axi_bready              (),
        .sb_axi_bresp               (2'b00),
        .sb_axi_bid                 ('0),
        .sb_axi_arvalid             (),
        .sb_axi_arready             (1'b0),
        .sb_axi_arid                (),
        .sb_axi_araddr              (),
        .sb_axi_arregion            (),
        .sb_axi_arlen               (),
        .sb_axi_arsize              (),
        .sb_axi_arburst             (),
        .sb_axi_arlock              (),
        .sb_axi_arcache             (),
        .sb_axi_arprot              (),
        .sb_axi_arqos               (),
        .sb_axi_rvalid              (1'b0),
        .sb_axi_rready              (),
        .sb_axi_rid                 ('0),
        .sb_axi_rdata               (64'd0),
        .sb_axi_rresp               (2'b00),
        .sb_axi_rlast               (1'b0),

        // Core DMA Slave Port (tie-offs)
        .dma_axi_awvalid            (1'b0),
        .dma_axi_awready            (),
        .dma_axi_awid               ('0),
        .dma_axi_awaddr             (32'd0),
        .dma_axi_awsize             (3'd0),
        .dma_axi_awprot             (3'd0),
        .dma_axi_awlen              (8'd0),
        .dma_axi_awburst            (2'd0),
        .dma_axi_wvalid             (1'b0),
        .dma_axi_wready             (),
        .dma_axi_wdata              (64'd0),
        .dma_axi_wstrb              (8'd0),
        .dma_axi_wlast              (1'b0),
        .dma_axi_bvalid             (),
        .dma_axi_bready             (1'b0),
        .dma_axi_bresp              (),
        .dma_axi_bid                (),
        .dma_axi_arvalid            (1'b0),
        .dma_axi_arready            (),
        .dma_axi_arid               ('0),
        .dma_axi_araddr             (32'd0),
        .dma_axi_arsize             (3'd0),
        .dma_axi_arprot             (3'd0),
        .dma_axi_arlen              (8'd0),
        .dma_axi_arburst            (2'd0),
        .dma_axi_rvalid             (),
        .dma_axi_rready             (1'b0),
        .dma_axi_rid                (),
        .dma_axi_rdata              (),
        .dma_axi_rresp              (),
        .dma_axi_rlast              (),

        // Bus Clock Ratios
        .lsu_bus_clk_en             (1'b1),
        .ifu_bus_clk_en             (1'b1),
        .dbg_bus_clk_en             (1'b1),
        .dma_bus_clk_en             (1'b1),

        // Interrupts
        .timer_int                  (1'b0),
        .soft_int                   (1'b0),
        .extintsrc_req              (core_extintsrc_req),

        .dec_tlu_perfcnt0           (),
        .dec_tlu_perfcnt1           (),
        .dec_tlu_perfcnt2           (),
        .dec_tlu_perfcnt3           (),

        // JTAG
        .jtag_tck                   (1'b0),
        .jtag_tms                   (1'b0),
        .jtag_tdi                   (1'b0),
        .jtag_trst_n                (~rst),
        .jtag_tdo                   (),
        .jtag_tdoEn                 (),
        .core_id                    (28'd0),

        // Memory export tie-offs (for CCM/ICache disabled)
        .mem_clk                    (),
        .iccm_clken                 (),
        .iccm_wren_bank             (),
        .iccm_addr_bank             (),
        .iccm_bank_wr_data          (),
        .iccm_bank_wr_ecc           (),
        .iccm_bank_dout             ('0),
        .iccm_bank_ecc              ('0),
        .dccm_clken                 (),
        .dccm_wren_bank             (),
        .dccm_addr_bank             (),
        .dccm_wr_data_bank          (),
        .dccm_wr_ecc_bank           (),
        .dccm_bank_dout             ('0),
        .dccm_bank_ecc              ('0),
        .ic_b_sb_wren               (),
        .ic_b_sb_bit_en_vec         (),
        .ic_sb_wr_data              (),
        .ic_rw_addr_bank_q          (),
        .ic_bank_way_clken_final    (),
        .ic_bank_way_clken_final_up (),
        .wb_packeddout_pre          ('0),
        .wb_dout_pre_up             ('0),
        .ic_tag_clken_final         (),
        .ic_tag_wren_q              (),
        .ic_tag_wren_biten_vec      (),
        .ic_tag_wr_data             (),
        .ic_rw_addr_q               (),
        .ic_tag_data_raw_pre        ('0),
        .ic_tag_data_raw_packed_pre ('0),

        .iccm_ecc_single_error      (),
        .iccm_ecc_double_error      (),
        .dccm_ecc_single_error      (),
        .dccm_ecc_double_error      (),
        .dccm_write_readback_error  (),

        // MPC / Debug
        .mpc_debug_halt_req         (1'b0),
        .mpc_debug_run_req          (1'b0),
        .mpc_reset_run_req          (1'b1), // Start execution out of reset
        .mpc_debug_halt_ack         (),
        .mpc_debug_run_ack          (),
        .debug_brkpt_status         (),

        .i_cpu_halt_req             (1'b0),
        .o_cpu_halt_ack             (),
        .o_cpu_halt_status          (o_cpu_halt_status),
        .o_debug_mode_status        (o_debug_mode_status),
        .i_cpu_run_req              (1'b0),
        .o_cpu_run_ack              (),
        .scan_mode                  (1'b0),
        .mbist_mode                 (1'b0),

        .dmi_core_enable            (1'b0),
        .dmi_uncore_enable          (1'b0),
        .dmi_uncore_en              (),
        .dmi_uncore_wr_en           (),
        .dmi_uncore_addr            (),
        .dmi_uncore_wdata           (),
        .dmi_uncore_rdata           (32'd0),
        .dmi_active                 ()
    );

    // ============================================================
    // 32-bit Wires connecting to main_top AXI Interconnect
    // ============================================================
    // M0: IFU
    wire [ID_WIDTH-1:0]   m0_arid;
    wire [ADDR_WIDTH-1:0] m0_araddr;
    wire [7:0]            m0_arlen;
    wire [2:0]            m0_arsize;
    wire [1:0]            m0_arburst;
    wire                  m0_arlock;
    wire [3:0]            m0_arcache;
    wire [2:0]            m0_arprot;
    wire [3:0]            m0_arqos;
    wire [3:0]            m0_arregion;
    wire                  m0_arvalid;
    wire                  m0_arready;
    wire [ID_WIDTH-1:0]   m0_rid;
    wire [DATA_WIDTH-1:0] m0_rdata;
    wire [1:0]            m0_rresp;
    wire                  m0_rlast;
    wire                  m0_rvalid;
    wire                  m0_rready;

    // M1: LSU
    wire [ID_WIDTH-1:0]   m1_awid;
    wire [ADDR_WIDTH-1:0] m1_awaddr;
    wire [7:0]            m1_awlen;
    wire [2:0]            m1_awsize;
    wire [1:0]            m1_awburst;
    wire                  m1_awlock;
    wire [3:0]            m1_awcache;
    wire [2:0]            m1_awprot;
    wire [3:0]            m1_awqos;
    wire [3:0]            m1_awregion;
    wire                  m1_awvalid;
    wire                  m1_awready;
    wire [DATA_WIDTH-1:0] m1_wdata;
    wire [STRB_WIDTH-1:0] m1_wstrb;
    wire                  m1_wlast;
    wire                  m1_wvalid;
    wire                  m1_wready;
    wire [ID_WIDTH-1:0]   m1_bid;
    wire [1:0]            m1_bresp;
    wire                  m1_bvalid;
    wire                  m1_bready;

    wire [ID_WIDTH-1:0]   m1_arid;
    wire [ADDR_WIDTH-1:0] m1_araddr;
    wire [7:0]            m1_arlen;
    wire [2:0]            m1_arsize;
    wire [1:0]            m1_arburst;
    wire                  m1_arlock;
    wire [3:0]            m1_arcache;
    wire [2:0]            m1_arprot;
    wire [3:0]            m1_arqos;
    wire [3:0]            m1_arregion;
    wire                  m1_arvalid;
    wire                  m1_arready;
    wire [ID_WIDTH-1:0]   m1_rid;
    wire [DATA_WIDTH-1:0] m1_rdata;
    wire [1:0]            m1_rresp;
    wire                  m1_rlast;
    wire                  m1_rvalid;
    wire                  m1_rready;

    // ============================================================
    // IFU 64b -> 32b Downconverter Bridge
    // ============================================================
    axi_width_downconverter_ifu #(
        .TAG_WIDTH  (pt.IFU_BUS_TAG),
        .ID_WIDTH   (ID_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_ifu_downconverter (
        .clk            (clk),
        .rst_n          (~rst),

        .s_axi_arid     (core_ifu_arid),
        .s_axi_araddr   (core_ifu_araddr),
        .s_axi_arlen    (core_ifu_arlen),
        .s_axi_arsize   (core_ifu_arsize),
        .s_axi_arburst  (core_ifu_arburst),
        .s_axi_arlock   (core_ifu_arlock),
        .s_axi_arcache  (core_ifu_arcache),
        .s_axi_arprot   (core_ifu_arprot),
        .s_axi_arqos    (core_ifu_arqos),
        .s_axi_arregion (core_ifu_arregion),
        .s_axi_arvalid  (core_ifu_arvalid),
        .s_axi_arready  (core_ifu_arready),
        .s_axi_rid      (core_ifu_rid),
        .s_axi_rdata    (core_ifu_rdata),
        .s_axi_rresp    (core_ifu_rresp),
        .s_axi_rlast    (core_ifu_rlast),
        .s_axi_rvalid   (core_ifu_rvalid),
        .s_axi_rready   (core_ifu_rready),

        .m_axi_arid     (m0_arid),
        .m_axi_araddr   (m0_araddr),
        .m_axi_arlen    (m0_arlen),
        .m_axi_arsize   (m0_arsize),
        .m_axi_arburst  (m0_arburst),
        .m_axi_arlock   (m0_arlock),
        .m_axi_arcache  (m0_arcache),
        .m_axi_arprot   (m0_arprot),
        .m_axi_arqos    (m0_arqos),
        .m_axi_arregion (m0_arregion),
        .m_axi_arvalid  (m0_arvalid),
        .m_axi_arready  (m0_arready),
        .m_axi_rid      (m0_rid),
        .m_axi_rdata    (m0_rdata),
        .m_axi_rresp    (m0_rresp),
        .m_axi_rlast    (m0_rlast),
        .m_axi_rvalid   (m0_rvalid),
        .m_axi_rready   (m0_rready)
    );

    // ============================================================
    // LSU 64b -> 32b Downconverter Bridge
    // ============================================================
    axi_width_downconverter_lsu #(
        .TAG_WIDTH  (pt.LSU_BUS_TAG),
        .ID_WIDTH   (ID_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_lsu_downconverter (
        .clk            (clk),
        .rst_n          (~rst),

        .s_axi_awid     (core_lsu_awid),
        .s_axi_awaddr   (core_lsu_awaddr),
        .s_axi_awlen    (core_lsu_awlen),
        .s_axi_awsize   (core_lsu_awsize),
        .s_axi_awburst  (core_lsu_awburst),
        .s_axi_awlock   (core_lsu_awlock),
        .s_axi_awcache  (core_lsu_awcache),
        .s_axi_awprot   (core_lsu_awprot),
        .s_axi_awqos    (core_lsu_awqos),
        .s_axi_awregion (core_lsu_awregion),
        .s_axi_awvalid  (core_lsu_awvalid),
        .s_axi_awready  (core_lsu_awready),
        .s_axi_wdata    (core_lsu_wdata),
        .s_axi_wstrb    (core_lsu_wstrb),
        .s_axi_wlast    (core_lsu_wlast),
        .s_axi_wvalid   (core_lsu_wvalid),
        .s_axi_wready   (core_lsu_wready),
        .s_axi_bid      (core_lsu_bid),
        .s_axi_bresp    (core_lsu_bresp),
        .s_axi_bvalid   (core_lsu_bvalid),
        .s_axi_bready   (core_lsu_bready),

        .s_axi_arid     (core_lsu_arid),
        .s_axi_araddr   (core_lsu_araddr),
        .s_axi_arlen    (core_lsu_arlen),
        .s_axi_arsize   (core_lsu_arsize),
        .s_axi_arburst  (core_lsu_arburst),
        .s_axi_arlock   (core_lsu_arlock),
        .s_axi_arcache  (core_lsu_arcache),
        .s_axi_arprot   (core_lsu_arprot),
        .s_axi_arqos    (core_lsu_arqos),
        .s_axi_arregion (core_lsu_arregion),
        .s_axi_arvalid  (core_lsu_arvalid),
        .s_axi_arready  (core_lsu_arready),
        .s_axi_rid      (core_lsu_rid),
        .s_axi_rdata    (core_lsu_rdata),
        .s_axi_rresp    (core_lsu_rresp),
        .s_axi_rlast    (core_lsu_rlast),
        .s_axi_rvalid   (core_lsu_rvalid),
        .s_axi_rready   (core_lsu_rready),

        .m_axi_awid     (m1_awid),
        .m_axi_awaddr   (m1_awaddr),
        .m_axi_awlen    (m1_awlen),
        .m_axi_awsize   (m1_awsize),
        .m_axi_awburst  (m1_awburst),
        .m_axi_awlock   (m1_awlock),
        .m_axi_awcache  (m1_awcache),
        .m_axi_awprot   (m1_awprot),
        .m_axi_awqos    (m1_awqos),
        .m_axi_awregion (m1_awregion),
        .m_axi_awvalid  (m1_awvalid),
        .m_axi_awready  (m1_awready),
        .m_axi_wdata    (m1_wdata),
        .m_axi_wstrb    (m1_wstrb),
        .m_axi_wlast    (m1_wlast),
        .m_axi_wvalid   (m1_wvalid),
        .m_axi_wready   (m1_wready),
        .m_axi_bid      (m1_bid),
        .m_axi_bresp    (m1_bresp),
        .m_axi_bvalid   (m1_bvalid),
        .m_axi_bready   (m1_bready),

        .m_axi_arid     (m1_arid),
        .m_axi_araddr   (m1_araddr),
        .m_axi_arlen    (m1_arlen),
        .m_axi_arsize   (m1_arsize),
        .m_axi_arburst  (m1_arburst),
        .m_axi_arlock   (m1_arlock),
        .m_axi_arcache  (m1_arcache),
        .m_axi_arprot   (m1_arprot),
        .m_axi_arqos    (m1_arqos),
        .m_axi_arregion (m1_arregion),
        .m_axi_arvalid  (m1_arvalid),
        .m_axi_arready  (m1_arready),
        .m_axi_rid      (m1_rid),
        .m_axi_rdata    (m1_rdata),
        .m_axi_rresp    (m1_rresp),
        .m_axi_rlast    (m1_rlast),
        .m_axi_rvalid   (m1_rvalid),
        .m_axi_rready   (m1_rready)
    );

    // ============================================================
    // Slave Interfaces from main_top (S0 IMEM, S1 DMEM, etc.)
    // ============================================================
    wire [ID_WIDTH-1:0]   s0_awid;
    wire [ADDR_WIDTH-1:0] s0_awaddr;
    wire [7:0]            s0_awlen;
    wire [2:0]            s0_awsize;
    wire [1:0]            s0_awburst;
    wire                  s0_awvalid;
    wire                  s0_awready;
    wire [DATA_WIDTH-1:0] s0_wdata;
    wire [STRB_WIDTH-1:0] s0_wstrb;
    wire                  s0_wlast;
    wire                  s0_wvalid;
    wire                  s0_wready;
    wire [ID_WIDTH-1:0]   s0_bid;
    wire [1:0]            s0_bresp;
    wire                  s0_bvalid;
    wire                  s0_bready;
    wire [ID_WIDTH-1:0]   s0_arid;
    wire [ADDR_WIDTH-1:0] s0_araddr;
    wire [7:0]            s0_arlen;
    wire [2:0]            s0_arsize;
    wire [1:0]            s0_arburst;
    wire                  s0_arvalid;
    wire                  s0_arready;
    wire [ID_WIDTH-1:0]   s0_rid;
    wire [DATA_WIDTH-1:0] s0_rdata;
    wire [1:0]            s0_rresp;
    wire                  s0_rlast;
    wire                  s0_rvalid;
    wire                  s0_rready;

    wire [ID_WIDTH-1:0]   s1_awid;
    wire [ADDR_WIDTH-1:0] s1_awaddr;
    wire [7:0]            s1_awlen;
    wire [2:0]            s1_awsize;
    wire [1:0]            s1_awburst;
    wire                  s1_awvalid;
    wire                  s1_awready;
    wire [DATA_WIDTH-1:0] s1_wdata;
    wire [STRB_WIDTH-1:0] s1_wstrb;
    wire                  s1_wlast;
    wire                  s1_wvalid;
    wire                  s1_wready;
    wire [ID_WIDTH-1:0]   s1_bid;
    wire [1:0]            s1_bresp;
    wire                  s1_bvalid;
    wire                  s1_bready;
    wire [ID_WIDTH-1:0]   s1_arid;
    wire [ADDR_WIDTH-1:0] s1_araddr;
    wire [7:0]            s1_arlen;
    wire [2:0]            s1_arsize;
    wire [1:0]            s1_arburst;
    wire                  s1_arvalid;
    wire                  s1_arready;
    wire [ID_WIDTH-1:0]   s1_rid;
    wire [DATA_WIDTH-1:0] s1_rdata;
    wire [1:0]            s1_rresp;
    wire                  s1_rlast;
    wire                  s1_rvalid;
    wire                  s1_rready;

    // ============================================================
    // main_top Subsystem Instance
    // ============================================================
    main_top #(
        .DATA_WIDTH      (DATA_WIDTH),
        .ADDR_WIDTH      (ADDR_WIDTH),
        .STRB_WIDTH      (STRB_WIDTH),
        .ID_WIDTH        (ID_WIDTH)
    ) u_main_top (
        .clk             (clk),
        .fixed_clk       (fixed_clk),
        .rst             (rst),

        // UART
        .uart_rx         (uart_rx),
        .uart_tx         (uart_tx),
        .uart_irq        (uart_irq),

        // PWM
        .PWM_OUT         (PWM_OUT),

        // GPIO
        .gpio_io         (gpio_io),
        .gpio_intr       (gpio_intr),

        // Timer
        .timer_ext_meas  (timer_ext_meas),
        .timer_capture   (timer_capture),
        .timer_pwm       (timer_pwm),
        .timer_trigger   (timer_trigger),
        .timer_intr      (timer_intr),

        // Encoder
        .enc_a           (enc_a),
        .enc_b           (enc_b),
        .enc_index       (enc_index),
        .enc_drive_active(enc_drive_active),
        .enc_speed       (enc_speed),
        .enc_speed_valid (enc_speed_valid),
        .enc_count_valid (enc_count_valid),
        .enc_dir         (enc_dir),
        .enc_fault       (enc_fault),
        .enc_intr        (enc_intr),

        // PID
        .pid_out         (pid_out),
        .pid_out_valid   (pid_out_valid),
        .pid_sat_flag    (pid_sat_flag),
        .pid_intr        (pid_intr),

        // M0: IFU
        .s00_axi_awid    ('0),
        .s00_axi_awaddr  ('0),
        .s00_axi_awlen   (8'd0),
        .s00_axi_awsize  (3'd0),
        .s00_axi_awburst (2'd0),
        .s00_axi_awlock  (1'b0),
        .s00_axi_awcache (4'd0),
        .s00_axi_awprot  (3'd0),
        .s00_axi_awqos   (4'd0),
        .s00_axi_awuser  ('0),
        .s00_axi_awvalid (1'b0),
        .s00_axi_awready (),
        .s00_axi_wdata   ('0),
        .s00_axi_wstrb   ('0),
        .s00_axi_wlast   (1'b0),
        .s00_axi_wuser   ('0),
        .s00_axi_wvalid  (1'b0),
        .s00_axi_wready  (),
        .s00_axi_bid     (),
        .s00_axi_bresp   (),
        .s00_axi_buser   (),
        .s00_axi_bvalid  (),
        .s00_axi_bready  (1'b0),

        .s00_axi_arid    (m0_arid),
        .s00_axi_araddr  (m0_araddr),
        .s00_axi_arlen   (m0_arlen),
        .s00_axi_arsize  (m0_arsize),
        .s00_axi_arburst (m0_arburst),
        .s00_axi_arlock  (m0_arlock),
        .s00_axi_arcache (m0_arcache),
        .s00_axi_arprot  (m0_arprot),
        .s00_axi_arqos   (m0_arqos),
        .s00_axi_aruser  ('0),
        .s00_axi_arvalid (m0_arvalid),
        .s00_axi_arready (m0_arready),
        .s00_axi_rid     (m0_rid),
        .s00_axi_rdata   (m0_rdata),
        .s00_axi_rresp   (m0_rresp),
        .s00_axi_rlast   (m0_rlast),
        .s00_axi_ruser   (),
        .s00_axi_rvalid  (m0_rvalid),
        .s00_axi_rready  (m0_rready),

        // M1: LSU
        .s01_axi_awid    (m1_awid),
        .s01_axi_awaddr  (m1_awaddr),
        .s01_axi_awlen   (m1_awlen),
        .s01_axi_awsize  (m1_awsize),
        .s01_axi_awburst (m1_awburst),
        .s01_axi_awlock  (m1_awlock),
        .s01_axi_awcache (m1_awcache),
        .s01_axi_awprot  (m1_awprot),
        .s01_axi_awqos   (m1_awqos),
        .s01_axi_awuser  ('0),
        .s01_axi_awvalid (m1_awvalid),
        .s01_axi_awready (m1_awready),
        .s01_axi_wdata   (m1_wdata),
        .s01_axi_wstrb   (m1_wstrb),
        .s01_axi_wlast   (m1_wlast),
        .s01_axi_wuser   ('0),
        .s01_axi_wvalid  (m1_wvalid),
        .s01_axi_wready  (m1_wready),
        .s01_axi_bid     (m1_bid),
        .s01_axi_bresp   (m1_bresp),
        .s01_axi_buser   (),
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
        .s01_axi_aruser  ('0),
        .s01_axi_arvalid (m1_arvalid),
        .s01_axi_arready (m1_arready),
        .s01_axi_rid     (m1_rid),
        .s01_axi_rdata   (m1_rdata),
        .s01_axi_rresp   (m1_rresp),
        .s01_axi_rlast   (m1_rlast),
        .s01_axi_ruser   (),
        .s01_axi_rvalid  (m1_rvalid),
        .s01_axi_rready  (m1_rready),

        // M2: DMA Master
        .s02_axi_awid    (s02_axi_awid),
        .s02_axi_awaddr  (s02_axi_awaddr),
        .s02_axi_awlen   (s02_axi_awlen),
        .s02_axi_awsize  (s02_axi_awsize),
        .s02_axi_awburst (s02_axi_awburst),
        .s02_axi_awlock  (s02_axi_awlock),
        .s02_axi_awcache (s02_axi_awcache),
        .s02_axi_awprot  (s02_axi_awprot),
        .s02_axi_awqos   (s02_axi_awqos),
        .s02_axi_awuser  (s02_axi_awuser),
        .s02_axi_awvalid (s02_axi_awvalid),
        .s02_axi_awready (s02_axi_awready),
        .s02_axi_wdata   (s02_axi_wdata),
        .s02_axi_wstrb   (s02_axi_wstrb),
        .s02_axi_wlast   (s02_axi_wlast),
        .s02_axi_wuser   (s02_axi_wuser),
        .s02_axi_wvalid  (s02_axi_wvalid),
        .s02_axi_wready  (s02_axi_wready),
        .s02_axi_bid     (s02_axi_bid),
        .s02_axi_bresp   (s02_axi_bresp),
        .s02_axi_buser   (s02_axi_buser),
        .s02_axi_bvalid  (s02_axi_bvalid),
        .s02_axi_bready  (s02_axi_bready),
        .s02_axi_arid    (s02_axi_arid),
        .s02_axi_araddr  (s02_axi_araddr),
        .s02_axi_arlen   (s02_axi_arlen),
        .s02_axi_arsize  (s02_axi_arsize),
        .s02_axi_arburst (s02_axi_arburst),
        .s02_axi_arlock  (s02_axi_arlock),
        .s02_axi_arcache (s02_axi_arcache),
        .s02_axi_arprot  (s02_axi_arprot),
        .s02_axi_arqos   (s02_axi_arqos),
        .s02_axi_aruser  (s02_axi_aruser),
        .s02_axi_arvalid (s02_axi_arvalid),
        .s02_axi_arready (s02_axi_arready),
        .s02_axi_rid     (s02_axi_rid),
        .s02_axi_rdata   (s02_axi_rdata),
        .s02_axi_rresp   (s02_axi_rresp),
        .s02_axi_rlast   (s02_axi_rlast),
        .s02_axi_ruser   (s02_axi_ruser),
        .s02_axi_rvalid  (s02_axi_rvalid),
        .s02_axi_rready  (s02_axi_rready),

        // S0: IMEM
        .m00_axi_awid    (s0_awid),
        .m00_axi_awaddr  (s0_awaddr),
        .m00_axi_awlen   (s0_awlen),
        .m00_axi_awsize  (s0_awsize),
        .m00_axi_awburst (s0_awburst),
        .m00_axi_awlock  (),
        .m00_axi_awcache (),
        .m00_axi_awprot  (),
        .m00_axi_awqos   (),
        .m00_axi_awregion(),
        .m00_axi_awuser  (),
        .m00_axi_awvalid (s0_awvalid),
        .m00_axi_awready (s0_awready),
        .m00_axi_wdata   (s0_wdata),
        .m00_axi_wstrb   (s0_wstrb),
        .m00_axi_wlast   (s0_wlast),
        .m00_axi_wuser   (),
        .m00_axi_wvalid  (s0_wvalid),
        .m00_axi_wready  (s0_wready),
        .m00_axi_bid     (s0_bid),
        .m00_axi_bresp   (s0_bresp),
        .m00_axi_buser   (),
        .m00_axi_bvalid  (s0_bvalid),
        .m00_axi_bready  (s0_bready),
        .m00_axi_arid    (s0_arid),
        .m00_axi_araddr  (s0_araddr),
        .m00_axi_arlen   (s0_arlen),
        .m00_axi_arsize  (s0_arsize),
        .m00_axi_arburst (s0_arburst),
        .m00_axi_arlock  (),
        .m00_axi_arcache (),
        .m00_axi_arprot  (),
        .m00_axi_arqos   (),
        .m00_axi_arregion(),
        .m00_axi_aruser  (),
        .m00_axi_arvalid (s0_arvalid),
        .m00_axi_arready (s0_arready),
        .m00_axi_rid     (s0_rid),
        .m00_axi_rdata   (s0_rdata),
        .m00_axi_rresp   (s0_rresp),
        .m00_axi_rlast   (s0_rlast),
        .m00_axi_ruser   (),
        .m00_axi_rvalid  (s0_rvalid),
        .m00_axi_rready  (s0_rready),

        // S1: DMEM
        .m01_axi_awid    (s1_awid),
        .m01_axi_awaddr  (s1_awaddr),
        .m01_axi_awlen   (s1_awlen),
        .m01_axi_awsize  (s1_awsize),
        .m01_axi_awburst (s1_awburst),
        .m01_axi_awlock  (),
        .m01_axi_awcache (),
        .m01_axi_awprot  (),
        .m01_axi_awqos   (),
        .m01_axi_awregion(),
        .m01_axi_awuser  (),
        .m01_axi_awvalid (s1_awvalid),
        .m01_axi_awready (s1_awready),
        .m01_axi_wdata   (s1_wdata),
        .m01_axi_wstrb   (s1_wstrb),
        .m01_axi_wlast   (s1_wlast),
        .m01_axi_wuser   (),
        .m01_axi_wvalid  (s1_wvalid),
        .m01_axi_wready  (s1_wready),
        .m01_axi_bid     (s1_bid),
        .m01_axi_bresp   (s1_bresp),
        .m01_axi_buser   (),
        .m01_axi_bvalid  (s1_bvalid),
        .m01_axi_bready  (s1_bready),
        .m01_axi_arid    (s1_arid),
        .m01_axi_araddr  (s1_araddr),
        .m01_axi_arlen   (s1_arlen),
        .m01_axi_arsize  (s1_arsize),
        .m01_axi_arburst (s1_arburst),
        .m01_axi_arlock  (),
        .m01_axi_arcache (),
        .m01_axi_arprot  (),
        .m01_axi_arqos   (),
        .m01_axi_arregion(),
        .m01_axi_aruser  (),
        .m01_axi_arvalid (s1_arvalid),
        .m01_axi_arready (s1_arready),
        .m01_axi_rid     (s1_rid),
        .m01_axi_rdata   (s1_rdata),
        .m01_axi_rresp   (s1_rresp),
        .m01_axi_rlast   (s1_rlast),
        .m01_axi_ruser   (),
        .m01_axi_rvalid  (s1_rvalid),
        .m01_axi_rready  (s1_rready),

        // m05
        .m05_axi_awid (), .m05_axi_awaddr (), .m05_axi_awlen (), .m05_axi_awsize (), .m05_axi_awburst (), .m05_axi_awlock (), .m05_axi_awcache (), .m05_axi_awprot (), .m05_axi_awqos (), .m05_axi_awregion (), .m05_axi_awuser (), .m05_axi_awvalid (), .m05_axi_wdata (), .m05_axi_wstrb (), .m05_axi_wlast (), .m05_axi_wuser (), .m05_axi_wvalid (), .m05_axi_buser (), .m05_axi_bready (), .m05_axi_arid (), .m05_axi_araddr (), .m05_axi_arlen (), .m05_axi_arsize (), .m05_axi_arburst (), .m05_axi_arlock (), .m05_axi_arcache (), .m05_axi_arprot (), .m05_axi_arqos (), .m05_axi_arregion (), .m05_axi_aruser (), .m05_axi_arvalid (), .m05_axi_ruser (), .m05_axi_rready (),
        .m05_axi_awready(1'b0), .m05_axi_wready(1'b0), .m05_axi_bvalid(1'b0), .m05_axi_bid('0), .m05_axi_bresp(2'b00), .m05_axi_arready(1'b0), .m05_axi_rvalid(1'b0), .m05_axi_rdata('0), .m05_axi_rresp(2'b00), .m05_axi_rlast(1'b0), .m05_axi_rid('0),
        // m06
        .m06_axi_awid (), .m06_axi_awaddr (), .m06_axi_awlen (), .m06_axi_awsize (), .m06_axi_awburst (), .m06_axi_awlock (), .m06_axi_awcache (), .m06_axi_awprot (), .m06_axi_awqos (), .m06_axi_awregion (), .m06_axi_awuser (), .m06_axi_awvalid (), .m06_axi_wdata (), .m06_axi_wstrb (), .m06_axi_wlast (), .m06_axi_wuser (), .m06_axi_wvalid (), .m06_axi_buser (), .m06_axi_bready (), .m06_axi_arid (), .m06_axi_araddr (), .m06_axi_arlen (), .m06_axi_arsize (), .m06_axi_arburst (), .m06_axi_arlock (), .m06_axi_arcache (), .m06_axi_arprot (), .m06_axi_arqos (), .m06_axi_arregion (), .m06_axi_aruser (), .m06_axi_arvalid (), .m06_axi_ruser (), .m06_axi_rready (),
        .m06_axi_awready(1'b0), .m06_axi_wready(1'b0), .m06_axi_bvalid(1'b0), .m06_axi_bid('0), .m06_axi_bresp(2'b00), .m06_axi_arready(1'b0), .m06_axi_rvalid(1'b0), .m06_axi_rdata('0), .m06_axi_rresp(2'b00), .m06_axi_rlast(1'b0), .m06_axi_rid('0),
        // m07
        .m07_axi_awid (), .m07_axi_awaddr (), .m07_axi_awlen (), .m07_axi_awsize (), .m07_axi_awburst (), .m07_axi_awlock (), .m07_axi_awcache (), .m07_axi_awprot (), .m07_axi_awqos (), .m07_axi_awregion (), .m07_axi_awuser (), .m07_axi_awvalid (), .m07_axi_wdata (), .m07_axi_wstrb (), .m07_axi_wlast (), .m07_axi_wuser (), .m07_axi_wvalid (), .m07_axi_buser (), .m07_axi_bready (), .m07_axi_arid (), .m07_axi_araddr (), .m07_axi_arlen (), .m07_axi_arsize (), .m07_axi_arburst (), .m07_axi_arlock (), .m07_axi_arcache (), .m07_axi_arprot (), .m07_axi_arqos (), .m07_axi_arregion (), .m07_axi_aruser (), .m07_axi_arvalid (), .m07_axi_ruser (), .m07_axi_rready (),
        .m07_axi_awready(1'b0), .m07_axi_wready(1'b0), .m07_axi_bvalid(1'b0), .m07_axi_bid('0), .m07_axi_bresp(2'b00), .m07_axi_arready(1'b0), .m07_axi_rvalid(1'b0), .m07_axi_rdata('0), .m07_axi_rresp(2'b00), .m07_axi_rlast(1'b0), .m07_axi_rid('0),
        // m11
        .m11_axi_awid (), .m11_axi_awaddr (), .m11_axi_awlen (), .m11_axi_awsize (), .m11_axi_awburst (), .m11_axi_awlock (), .m11_axi_awcache (), .m11_axi_awprot (), .m11_axi_awqos (), .m11_axi_awregion (), .m11_axi_awuser (), .m11_axi_awvalid (), .m11_axi_wdata (), .m11_axi_wstrb (), .m11_axi_wlast (), .m11_axi_wuser (), .m11_axi_wvalid (), .m11_axi_buser (), .m11_axi_bready (), .m11_axi_arid (), .m11_axi_araddr (), .m11_axi_arlen (), .m11_axi_arsize (), .m11_axi_arburst (), .m11_axi_arlock (), .m11_axi_arcache (), .m11_axi_arprot (), .m11_axi_arqos (), .m11_axi_arregion (), .m11_axi_aruser (), .m11_axi_arvalid (), .m11_axi_ruser (), .m11_axi_rready (),
        .m11_axi_awready(1'b0), .m11_axi_wready(1'b0), .m11_axi_bvalid(1'b0), .m11_axi_bid('0), .m11_axi_bresp(2'b00), .m11_axi_arready(1'b0), .m11_axi_rvalid(1'b0), .m11_axi_rdata('0), .m11_axi_rresp(2'b00), .m11_axi_rlast(1'b0), .m11_axi_rid('0),
        // m12
        .m12_axi_awid (), .m12_axi_awaddr (), .m12_axi_awlen (), .m12_axi_awsize (), .m12_axi_awburst (), .m12_axi_awlock (), .m12_axi_awcache (), .m12_axi_awprot (), .m12_axi_awqos (), .m12_axi_awregion (), .m12_axi_awuser (), .m12_axi_awvalid (), .m12_axi_wdata (), .m12_axi_wstrb (), .m12_axi_wlast (), .m12_axi_wuser (), .m12_axi_wvalid (), .m12_axi_buser (), .m12_axi_bready (), .m12_axi_arid (), .m12_axi_araddr (), .m12_axi_arlen (), .m12_axi_arsize (), .m12_axi_arburst (), .m12_axi_arlock (), .m12_axi_arcache (), .m12_axi_arprot (), .m12_axi_arqos (), .m12_axi_arregion (), .m12_axi_aruser (), .m12_axi_arvalid (), .m12_axi_ruser (), .m12_axi_rready (),
        .m12_axi_awready(1'b0), .m12_axi_wready(1'b0), .m12_axi_bvalid(1'b0), .m12_axi_bid('0), .m12_axi_bresp(2'b00), .m12_axi_arready(1'b0), .m12_axi_rvalid(1'b0), .m12_axi_rdata('0), .m12_axi_rresp(2'b00), .m12_axi_rlast(1'b0), .m12_axi_rid('0),
        // m13
        .m13_axi_awid (), .m13_axi_awaddr (), .m13_axi_awlen (), .m13_axi_awsize (), .m13_axi_awburst (), .m13_axi_awlock (), .m13_axi_awcache (), .m13_axi_awprot (), .m13_axi_awqos (), .m13_axi_awregion (), .m13_axi_awuser (), .m13_axi_awvalid (), .m13_axi_wdata (), .m13_axi_wstrb (), .m13_axi_wlast (), .m13_axi_wuser (), .m13_axi_wvalid (), .m13_axi_buser (), .m13_axi_bready (), .m13_axi_arid (), .m13_axi_araddr (), .m13_axi_arlen (), .m13_axi_arsize (), .m13_axi_arburst (), .m13_axi_arlock (), .m13_axi_arcache (), .m13_axi_arprot (), .m13_axi_arqos (), .m13_axi_arregion (), .m13_axi_aruser (), .m13_axi_arvalid (), .m13_axi_ruser (), .m13_axi_rready (),
        .m13_axi_awready(1'b0), .m13_axi_wready(1'b0), .m13_axi_bvalid(1'b0), .m13_axi_bid('0), .m13_axi_bresp(2'b00), .m13_axi_arready(1'b0), .m13_axi_rvalid(1'b0), .m13_axi_rdata('0), .m13_axi_rresp(2'b00), .m13_axi_rlast(1'b0), .m13_axi_rid('0),
        // m14
        .m14_axi_awid (), .m14_axi_awaddr (), .m14_axi_awlen (), .m14_axi_awsize (), .m14_axi_awburst (), .m14_axi_awlock (), .m14_axi_awcache (), .m14_axi_awprot (), .m14_axi_awqos (), .m14_axi_awregion (), .m14_axi_awuser (), .m14_axi_awvalid (), .m14_axi_wdata (), .m14_axi_wstrb (), .m14_axi_wlast (), .m14_axi_wuser (), .m14_axi_wvalid (), .m14_axi_buser (), .m14_axi_bready (), .m14_axi_arid (), .m14_axi_araddr (), .m14_axi_arlen (), .m14_axi_arsize (), .m14_axi_arburst (), .m14_axi_arlock (), .m14_axi_arcache (), .m14_axi_arprot (), .m14_axi_arqos (), .m14_axi_arregion (), .m14_axi_aruser (), .m14_axi_arvalid (), .m14_axi_ruser (), .m14_axi_rready (),
        .m14_axi_awready(1'b0), .m14_axi_wready(1'b0), .m14_axi_bvalid(1'b0), .m14_axi_bid('0), .m14_axi_bresp(2'b00), .m14_axi_arready(1'b0), .m14_axi_rvalid(1'b0), .m14_axi_rdata('0), .m14_axi_rresp(2'b00), .m14_axi_rlast(1'b0), .m14_axi_rid('0)
    );

    // ============================================================
    // IMEM and DMEM Memory Controllers
    // ============================================================
    generate
        if (USE_INTERNAL_MEM) begin : GEN_INTERNAL_MEM
            // S0: IMEM (64 KiB at 0x4000_0000)
            axi_sram_ctrl #(
                .ADDR_WIDTH (16),
                .DATA_WIDTH (DATA_WIDTH),
                .STRB_WIDTH (STRB_WIDTH),
                .ID_WIDTH   (ID_WIDTH),
                .INIT_NOP   (1)
            ) u_imem (
                .clk            (clk),
                .rst_n          (~rst),
                .s_axi_awid     (s0_awid),
                .s_axi_awaddr   (s0_awaddr[15:0]),
                .s_axi_awlen    (s0_awlen),
                .s_axi_awsize   (s0_awsize),
                .s_axi_awburst  (s0_awburst),
                .s_axi_awvalid  (s0_awvalid),
                .s_axi_awready  (s0_awready),
                .s_axi_wdata    (s0_wdata),
                .s_axi_wstrb    (s0_wstrb),
                .s_axi_wlast    (s0_wlast),
                .s_axi_wvalid   (s0_wvalid),
                .s_axi_wready   (s0_wready),
                .s_axi_bid      (s0_bid),
                .s_axi_bresp    (s0_bresp),
                .s_axi_bvalid   (s0_bvalid),
                .s_axi_bready   (s0_bready),
                .s_axi_arid     (s0_arid),
                .s_axi_araddr   (s0_araddr[15:0]),
                .s_axi_arlen    (s0_arlen),
                .s_axi_arsize   (s0_arsize),
                .s_axi_arburst  (s0_arburst),
                .s_axi_arvalid  (s0_arvalid),
                .s_axi_arready  (s0_arready),
                .s_axi_rid      (s0_rid),
                .s_axi_rdata    (s0_rdata),
                .s_axi_rresp    (s0_rresp),
                .s_axi_rlast    (s0_rlast),
                .s_axi_rvalid   (s0_rvalid),
                .s_axi_rready   (s0_rready)
            );

            // S1: DMEM (64 KiB at 0x4002_0000)
            axi_sram_ctrl #(
                .ADDR_WIDTH (16),
                .DATA_WIDTH (DATA_WIDTH),
                .STRB_WIDTH (STRB_WIDTH),
                .ID_WIDTH   (ID_WIDTH),
                .INIT_NOP   (0)
            ) u_dmem (
                .clk            (clk),
                .rst_n          (~rst),
                .s_axi_awid     (s1_awid),
                .s_axi_awaddr   (s1_awaddr[15:0]),
                .s_axi_awlen    (s1_awlen),
                .s_axi_awsize   (s1_awsize),
                .s_axi_awburst  (s1_awburst),
                .s_axi_awvalid  (s1_awvalid),
                .s_axi_awready  (s1_awready),
                .s_axi_wdata    (s1_wdata),
                .s_axi_wstrb    (s1_wstrb),
                .s_axi_wlast    (s1_wlast),
                .s_axi_wvalid   (s1_wvalid),
                .s_axi_wready   (s1_wready),
                .s_axi_bid      (s1_bid),
                .s_axi_bresp    (s1_bresp),
                .s_axi_bvalid   (s1_bvalid),
                .s_axi_bready   (s1_bready),
                .s_axi_arid     (s1_arid),
                .s_axi_araddr   (s1_araddr[15:0]),
                .s_axi_arlen    (s1_arlen),
                .s_axi_arsize   (s1_arsize),
                .s_axi_arburst  (s1_arburst),
                .s_axi_arvalid  (s1_arvalid),
                .s_axi_arready  (s1_arready),
                .s_axi_rid      (s1_rid),
                .s_axi_rdata    (s1_rdata),
                .s_axi_rresp    (s1_rresp),
                .s_axi_rlast    (s1_rlast),
                .s_axi_rvalid   (s1_rvalid),
                .s_axi_rready   (s1_rready)
            );
        end
    endgenerate

endmodule
`default_nettype wire
