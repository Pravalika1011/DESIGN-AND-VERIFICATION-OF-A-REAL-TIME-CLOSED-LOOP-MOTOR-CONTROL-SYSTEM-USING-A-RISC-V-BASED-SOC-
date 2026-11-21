# scripts/test_plan_part1.py
# Categories 1-5: RESET, CLOCK, CPU, IMEM, DMEM

def populate_part1(add_tc):
    # ----------------------------------------------------
    # 1. RESET AND INITIALIZATION
    # ----------------------------------------------------
    add_tc(
        "RESET_001",
        "Power-on reset deassertion and vector fetch",
        "Verify SoC behavior from cold power-on. rst is asserted for 20 clock cycles, deasserted synchronously, and core begins fetching from 0x4000_0000.",
        "CP1: rst asserted for 20 cycles; CP2: IFU issues araddr=0x4000_0000 on cycle 21; CP3: S0 IMEM responds with valid instruction 0x00028117; CP4: core does not hang or execute undefined opcode.",
        "EXTERNAL",
        "External rst pin -> Core rst_l / dbg_rst_l -> VeeR IFU -> 64b AXI -> IFU downconverter -> Interconnect S0 -> axi_sram_ctrl -> Core IFU",
        "C crt0.S entry routine initializes gp and sp registers immediately upon reset exit, then clears BSS segment and invokes main().",
        "Mailbox signature 0xA5A50001 written to 0x4002_0000; sp initialized to 0x4002_8000.",
        "Drive clk at 100 MHz (10ns period). Hold rst=1 for 200ns. Release rst at falling edge of clk. Monitor core_ifu_araddr and trace_rv_i_address_ip.",
        "rst_n transitions 0->1 at 200ns; core_ifu_araddr=0x4000_0000 at 220ns; trace_rv_i_valid_ip asserts at 350ns.",
        "Reset & Clock Interface",
        "rst, clk",
        "trace_rv_i_address_ip, trace_rv_i_valid_ip, o_cpu_halt_status",
        "soc_top, u_veer_core, axi_sram_ctrl",
        "Power-on Reset Sequence",
        "0x4000_0000 (IMEM Base)",
        "SV Monitor + C crt0.S",
        "Reset release FSM, PC reset vector"
    )

    add_tc(
        "RESET_002",
        "Warm reset assertion during active instruction fetch",
        "Assert rst while the CPU is actively executing a tight loop in IMEM. Verify that all outstanding AXI transactions are safely aborted and the pipeline flushes cleanly.",
        "CP1: CPU in active loop at 0x4000_0100; CP2: rst asserted for 10 cycles; CP3: IFU AXI bus returns to IDLE (arvalid=0); CP4: Upon release, CPU re-fetches from 0x4000_0000.",
        "EXTERNAL",
        "External rst pin -> Core IFU reset -> IFU width downconverter FSM reset -> Interconnect reset -> IMEM SRAM controller reset",
        "Firmware executes infinite counter increment loop at address 0x4000_0100, writing iteration count to DMEM 0x4002_0010.",
        "Counter values 1, 2, 3... observed; after reset, counter restarts from 0.",
        "Run simulation to T=50us. Assert rst=1 for 100ns (10 cycles). Verify downconverter state returns to S_IDLE immediately.",
        "u_ifu_downconverter.state == S_IDLE during reset; core re-fetches PC=0x4000_0000 after release.",
        "Reset & Clock Interface",
        "rst, clk",
        "trace_rv_i_address_ip, core_ifu_arvalid",
        "axi_width_downconverter_ifu, u_veer_core",
        "Mid-execution Warm Reset",
        "0x4000_0100 -> 0x4000_0000",
        "SV Driving + C loop",
        "FSM reset branches, arready/arvalid deassertion"
    )

    add_tc(
        "RESET_003",
        "Reset assertion during active LSU AXI bus transaction",
        "Assert rst while the CPU LSU has an outstanding write transaction with awvalid=1 and wvalid=1 pending to DMEM. Verify no corrupt write occurs and bvalid clears.",
        "CP1: LSU write initiated to 0x4002_0100; CP2: rst asserted before bready handshake; CP3: DMEM memory contents unchanged at target address; CP4: LSU downconverter FSM resets cleanly.",
        "EXTERNAL",
        "External rst pin -> Core LSU -> LSU downconverter -> Interconnect S1 -> DMEM controller write latch",
        "Firmware attempts 64-bit store instruction (sd or two consecutive sw) to DMEM address 0x4002_0100 with pattern 0xDEADBEEF_CAFEF00D.",
        "Upon post-reset inspection, target address 0x4002_0100 retains original pre-write value (0x00000000).",
        "Monitor m1_awvalid and m1_wvalid. Trigger rst=1 exactly when m1_wvalid=1. Hold for 50ns, then deassert. Inspect DMEM memory array via backdoor.",
        "dut.GEN_INTERNAL_MEM.u_dmem.mem[64] == 32'h0000_0000; u_lsu_downconverter.w_state returns to W_IDLE.",
        "Reset & Clock Interface",
        "rst, clk",
        "core_lsu_awvalid, core_lsu_wvalid, core_lsu_bvalid",
        "axi_width_downconverter_lsu, axi_sram_ctrl",
        "Bus Transaction Abort on Reset",
        "0x4002_0100 (DMEM)",
        "SV Assertions + Backdoor Memory Check",
        "aw_pending, w_pending clear logic"
    )

    add_tc(
        "RESET_004",
        "Reset during peripheral timer countdown and PWM generation",
        "Configure Timer in continuous mode and PWM with 50% duty cycle. While timer is counting and PWM_OUT is toggling, assert rst. Verify outputs halt immediately.",
        "CP1: PWM_OUT actively toggles at 1 MHz; CP2: timer_current_val actively decrements; CP3: rst asserted; CP4: PWM_OUT immediately forced to 0; CP5: timer registers return to default 0.",
        "EXTERNAL",
        "External rst pin -> Peripheral reset tree -> Timer core counter reset & PWM IP counter reset -> External PWM_OUT and timer_pwm pins",
        "Firmware configures Timer (0x4003_3000) with load=1000, ctrl=0x03 (enable, repeat); configures PWM (0x4004_1000) duty=128.",
        "Timer current value decrements; PWM duty reads 128; after reset, registers read 0x0000_0000.",
        "Observe PWM_OUT toggling. Force rst=1. Check PWM_OUT goes low within 1 clock cycle. Verify timer_pwm and timer_trigger remain 0.",
        "PWM_OUT == 0 within 10ns of rst assertion; u_main_top.u_timer.current_val == 0.",
        "PWM & Timer External Outputs",
        "rst, clk",
        "PWM_OUT, timer_pwm, timer_trigger",
        "timer_core, myip_v1_0_S00_AXI, main_top",
        "Peripheral Reset Quiescence",
        "0x4003_3000, 0x4004_1000",
        "SV Protocol Check + Waveform Observation",
        "Counter reset registers, output enable resets"
    )

    add_tc(
        "RESET_005",
        "Reset during active PIC interrupt ISR handling",
        "Assert rst while the core is inside the Timer Interrupt Service Routine (PC in ISR range 0x4000_0200-0x4000_0350). Verify clean trap state reset.",
        "CP1: Timer interrupt fires and core jumps to mtvec ISR; CP2: rst asserted while mepc contains interrupted PC; CP3: Upon reset release, core restarts at 0x4000_0000, not ISR.",
        "EXTERNAL",
        "External rst pin -> Core TLU / PIC controller -> CSR registers (mepc, mcause, mstatus) -> PC reset vector",
        "Firmware sets up mtvec to point to isr_timer(). In ISR, firmware increments a volatile counter and clears timer interrupt status.",
        "After reset, core restarts main(); counter variable is re-initialized to 0 in BSS.",
        "Trigger rst=1 when trace_rv_i_address_ip enters isr_timer(). Hold for 10 cycles, release. Verify PC jumps to 0x4000_0000 and mstatus.MIE is cleared to 0.",
        "PC immediately resets to 0x4000_0000; u_veer_core.veer.dec.tlu.mstatus[3] == 0 (interrupts disabled out of reset).",
        "Reset & Clock Interface",
        "rst, clk",
        "trace_rv_i_address_ip, trace_rv_i_interrupt_ip",
        "el2_tlu, el2_pic_ctrl, veer_wrapper",
        "ISR Interrupt Abort on Reset",
        "0x4000_02F4 (ISR entry)",
        "SV Address Monitor + C ISR",
        "TLU reset state, mstatus/mepc reset values"
    )

    add_tc(
        "RESET_006",
        "Default register values audit across all 6 MMIO slaves",
        "Read all implemented peripheral registers immediately following reset release before any write operations. Verify match against architectural specification.",
        "CP1: GPIO registers DATA_O=0, DIR=0, INT_EN=0; CP2: Timer CTRL=0, LOAD=0, INT_EN=0; CP3: UART IER=0, LCR=0; CP4: Encoder CTRL=0, WINDOW=0; CP5: PID CTRL=0, KP=0; CP6: PWM slv_reg0-3=0.",
        "INTERNAL",
        "VeeR LSU -> LSU width downconverter -> Interconnect S2,S3,S4,S8,S9,S10 -> Peripheral register files -> Read responses",
        "Firmware systematically reads each peripheral register base and asserts equality to 0x0000_0000 (or specified default constant such as PID_RST_OUT_MAX=0x7FFF).",
        "All register read assertions pass; mailbox signature 0x5E5E0006 written to 0x4002_0000 upon full audit pass.",
        "Verify bus read handshakes for each register access. Ensure no bus error or DECERR occurs on valid implemented register offsets.",
        "16 consecutive AXI read beats complete with rresp=2'b00 (OKAY); correct reset default data returned.",
        "None (Internal)",
        "None",
        "None",
        "gpio_regs, timer_regs, axi_uart_top, enc_axi_slave, pid_axi_slave, myip_v1_0_S00_AXI",
        "Power-On Default Register Values",
        "0x4003_1000 - 0x4004_1FFF",
        "C Systematic Readback + SV AXI Protocol Checker",
        "Register reset branches across all 6 peripheral wrappers"
    )

    add_tc(
        "RESET_007",
        "Reset recovery and restart sequence execution",
        "Verify that following a soft or hard reset, the entire SoC software stack cleanly boots, executes memory self-tests, and re-establishes peripheral communication.",
        "CP1: Cold boot executes normally; CP2: rst pulsed for 20 cycles; CP3: Second boot cycle executes identical flow without lingering peripheral state.",
        "EXTERNAL",
        "External rst pin -> Complete SoC hierarchy -> Full boot re-execution",
        "Firmware maintains a boot counter in uninitialized memory; on second boot, verifies that hardware peripherals were re-initialized cleanly.",
        "Mailbox writes 0xCAFE0001 on boot 1, and 0xCAFE0002 on boot 2.",
        "Drive reset sequence twice. Compare trace_rv_i_address_ip trajectory of boot 1 vs boot 2 for exact cycle-accurate alignment.",
        "Boot 1 and Boot 2 execution traces match 100% up to the first asynchronous peripheral stimulus.",
        "Reset & Clock Interface",
        "rst, clk",
        "trace_rv_i_address_ip, trace_rv_i_valid_ip",
        "soc_top, u_veer_core, main_top",
        "Multi-Cycle Reset Reproducibility",
        "0x4000_0000 (Boot Vector)",
        "SV Trace Comparison + C Boot Counter",
        "Complete chip reset and restart state coverage"
    )

    # ----------------------------------------------------
    # 2. CLOCK AND TIMING-RELATED BEHAVIOR
    # ----------------------------------------------------
    add_tc(
        "CLOCK_001",
        "Primary 100 MHz SoC clock period and duty cycle robustness",
        "Verify SoC operation with nominal 10.0ns clock (50% duty cycle) and verify setup/hold stability under ±5% clock jitter in simulation.",
        "CP1: Core boots and runs with 10.0ns period; CP2: Clock period modulated between 9.5ns and 10.5ns; CP3: Zero setup/hold assertion violations triggered.",
        "EXTERNAL",
        "External clk pin -> Clock distribution tree -> VeeR Core, Interconnect, Peripherals",
        "Firmware executes CPU arithmetic stress benchmark (matrix multiplication in DMEM).",
        "Benchmark completes with correct deterministic checksum 0x12345678 in DMEM mailbox.",
        "Instantiate clock generator with dynamic period jitter (10ns +/- 500ps). Monitor all AXI synchronous interfaces for protocol compliance.",
        "Simulation completes with 0 errors; all AXI handshakes respect posedge clk timing.",
        "Clock Input",
        "clk",
        "trace_rv_i_valid_ip, uart_tx",
        "soc_top, main_top",
        "Clock Frequency Stability",
        "N/A",
        "SV Dynamic Clock Generator + C Compute Stress",
        "Pipelined register timing paths"
    )

    add_tc(
        "CLOCK_002",
        "Dual-clock domain ratio verification: 100 MHz AXI to 50 MHz UART fixed clock",
        "Verify asynchronous FIFO synchronization between 100 MHz AXI bus clock (clk) and 50 MHz fixed peripheral clock (fixed_clk) in axi_uart_top.",
        "CP1: clk=100MHz (10ns), fixed_clk=50MHz (20ns); CP2: CPU writes 16 bytes to TX FIFO at 100 MHz; CP3: UART controller pops and transmits bytes at 50 MHz baud clock without FIFO corruption or drop.",
        "EXTERNAL",
        "VeeR LSU (100 MHz) -> Interconnect S4 -> axi_uart_top AXI FIFO (100 MHz) -> CDC synchronizer -> UART Transmitter (50 MHz fixed_clk) -> External uart_tx pin",
        "Firmware bursts 16 ASCII characters ('0123456789ABCDEF') to UART THR register (0x4003_5000) with no delay loops.",
        "UART LSR indicates TX FIFO empty after transmission; all 16 characters transmitted correctly.",
        "Drive clk at 100 MHz and fixed_clk at 50 MHz with arbitrary initial phase offset (5ns). Monitor tx_fifo_push_int (clk) and tx_fifo_pop_int (fixed_clk).",
        "16 push pulses observed on clk; exactly 16 pop pulses observed on fixed_clk; no FIFO overrun/underrun flag asserted.",
        "Clock Inputs & UART Output",
        "clk, fixed_clk",
        "uart_tx",
        "axi_uart_top, axi_internal_fifo, uart_controller",
        "Dual-Clock Domain Crossing (CDC)",
        "0x4003_5000 (UART THR)",
        "SV Multi-Clock Driver + SV Character Monitor",
        "Gray-code FIFO pointer crossing, empty/full sync flags"
    )

    add_tc(
        "CLOCK_003",
        "Timer prescaler clock division accuracy under varying pre_val settings",
        "Verify that Timer core prescaler divides primary clk by exactly (pre_val + 1) cycles before generating counter ticks.",
        "CP1: pre_val=0 (divide by 1): counter decrements every cycle; CP2: pre_val=1 (divide by 2): counter decrements every 2 cycles; CP3: pre_val=9 (divide by 10): counter decrements every 10 cycles.",
        "INTERNAL",
        "VeeR LSU -> Interconnect S3 -> timer_regs PRE & CTRL -> timer_core prescaler counter -> 32-bit decrementer",
        "Firmware sets PRE=9, LOAD=100, CTRL=0x05 (enable, down, prescaler enabled). Samples timer VAL register after 100 CPU cycles.",
        "VAL register reads approximately 100 - (100/10) = 90.",
        "SV testbench directly monitors u_timer.u_timer_core.tick. Measures clock cycles between successive tick pulses.",
        "With pre_val=9, exactly 10 posedge clk intervals measured between successive tick assertions.",
        "None (Internal)",
        "None",
        "None",
        "timer_core, timer_regs",
        "Timer Prescaler Clock Division",
        "0x4003_300C (PRE), 0x4003_3000 (CTRL)",
        "SV Cycle-Accurate Assertion + C Readback",
        "Prescaler counter reload, tick generation logic"
    )

    # ----------------------------------------------------
    # 3. VeeR EL2 CPU INTEGRATION
    # ----------------------------------------------------
    add_tc(
        "CPU_001",
        "Reset vector alignment and initial instruction fetch from 0x4000_0000",
        "Verify that upon reset release, the VeeR EL2 core naturally issues its first fetch to 0x4000_0000 matching the rst_vec parameter.",
        "CP1: rst_vec tied to 31'h2000_0000; CP2: First IFU ARADDR issued is 0x4000_0000; CP3: First instruction decoded is auipc sp.",
        "INTERNAL",
        "VeeR IFU -> core_ifu_araddr (0x4000_0000) -> IFU downconverter -> Interconnect S0 -> IMEM axi_sram_ctrl -> IFU RDATA -> Core Decode",
        "Startup code crt0.S placed at origin 0x4000_0000 starts with auipc sp, 0x28 followed by addi sp, sp, 0.",
        "Core starts executing without trap; sp set to 0x4002_8000.",
        "Monitor core_ifu_araddr at cycle where core_ifu_arvalid asserts for the first time after reset.",
        "core_ifu_araddr == 32'h4000_0000; core_ifu_arsize == 3'b011 (64-bit fetch).",
        "None (Internal)",
        "None",
        "None",
        "soc_top, u_veer_core, veer_wrapper",
        "Reset Vector Alignment",
        "0x4000_0000",
        "SV Protocol Monitor + Assembly crt0.S",
        "rst_vec decoding logic in VeeR IFU"
    )

    add_tc(
        "CPU_002",
        "Sequential integer ALU execution, branches, and register file integrity",
        "Execute comprehensive integer arithmetic, logical, shift, comparison, and conditional branch instructions (RV32I) and verify register file writeback.",
        "CP1: ADD, SUB, XOR, OR, AND, SLL, SRL, SRA produce mathematically correct results; CP2: BEQ, BNE, BLT, BGE branches take correct paths; CP3: x1-x31 registers preserve written state.",
        "INTERNAL",
        "VeeR IFU -> Core Decoder -> ALU Execution Units -> Register File -> LSU -> DMEM Writeback",
        "Firmware runs exhaustive self-test function test_rv32i_alu() evaluating 100 mathematical operations and storing result matrix to DMEM.",
        "All tests pass; DMEM mailbox 0x4002_0004 written with 0x0000_0001 (ALU_PASS).",
        "Monitor trace_rv_i_address_ip and trace_rv_i_insn_ip. Verify no exception is raised (trace_rv_i_exception_ip == 0).",
        "trace_rv_i_exception_ip stays 0 throughout; all branch targets match compiler symbol table.",
        "None (Internal)",
        "None",
        "None",
        "u_veer_core, el2_dec, el2_alu",
        "RV32I Core Execution Integrity",
        "0x4000_0000 - 0x4000_0800",
        "C Exhaustive ALU Test Suite + SV Trace Monitor",
        "ALU operation decode, bypass forwarding paths"
    )

    add_tc(
        "CPU_003",
        "Compressed instruction (RVC) execution and boundary alignment",
        "Verify execution of 16-bit RV32C compressed instructions (c.addi, c.li, c.mv, c.j, c.jr) and verify fetch spanning 32-bit and 64-bit boundaries.",
        "CP1: 16-bit instructions decode correctly; CP2: Instruction spanning word boundary [31:16] and [15:0] of next word executes without alignment trap.",
        "INTERNAL",
        "VeeR IFU -> Decompressor (dec_tlu) -> Core Pipeline -> Writeback",
        "Firmware compiled with -march=rv32imc contains inline assembly with mixed 16-bit and 32-bit instructions spanning unaligned 2-byte boundaries.",
        "Correct execution verified; mailbox 0x4002_0004 receives signature 0xC001_0001.",
        "Verify trace_rv_i_address_ip increments by 2 for compressed instructions and by 4 for uncompressed instructions.",
        "trace_rv_i_address_ip increments by 2 observed; no instruction address misaligned exception raised.",
        "None (Internal)",
        "None",
        "None",
        "u_veer_core, el2_dec",
        "RVC Compressed Instruction Decoding",
        "0x4000_0000 (IMEM)",
        "C Inline Assembly + SV PC Increment Checker",
        "RVC decompressor logic, 16-bit fetch alignment"
    )

    add_tc(
        "CPU_004",
        "LSU sub-word load operations (lb, lbu, lh, lhu, lw)",
        "Verify CPU load instructions with signed and unsigned byte, halfword, and word operations from DMEM across various byte offsets (0, 1, 2, 3).",
        "CP1: lb sign-extends 8-bit negative numbers; CP2: lbu zero-extends 8-bit numbers; CP3: lh sign-extends 16-bit numbers; CP4: lhu zero-extends 16-bit numbers; CP5: lw loads full 32-bit words.",
        "INTERNAL",
        "VeeR LSU -> LSU width downconverter -> Interconnect S1 -> DMEM controller -> Read data -> LSU alignment unit -> Regfile",
        "Firmware writes 0x81828384 to DMEM 0x4002_0200. Executes lb, lbu, lh, lhu at offsets +0, +1, +2, +3. Verifies sign extension.",
        "Readback values: lb(offset 3)=0xFFFFFF81, lbu(offset 3)=0x00000081, lh(offset 2)=0xFFFF8182, lhu(offset 2)=0x00008182.",
        "Monitor core_lsu_araddr, core_lsu_arsize. Verify LSU downconverter properly returns replicated data.",
        "core_lsu_rdata returns {word, word}; core receives correct byte regardless of LSU alignment multiplexer.",
        "None (Internal)",
        "None",
        "None",
        "axi_width_downconverter_lsu, u_veer_core, el2_lsu",
        "Sub-Word Load Sign/Zero Extension",
        "0x4002_0200 (DMEM)",
        "C Data Extraction + SV Bus Monitor",
        "LSU load aligner, sign extension muxes"
    )

    add_tc(
        "CPU_005",
        "LSU sub-word store operations (sb, sh, sw) with byte strobes",
        "Verify CPU store instructions with byte (sb), halfword (sh), and word (sw) operations to DMEM, ensuring adjacent bytes in the same word are unmodified.",
        "CP1: sb updates only target byte; CP2: sh updates only target halfword; CP3: sw updates full word; CP4: Byte strobes wstrb match target addresses exactly.",
        "INTERNAL",
        "VeeR LSU -> core_lsu_wstrb -> LSU width downconverter -> m1_wstrb -> Interconnect S1 -> DMEM byte write enables",
        "Firmware writes 0xFFFFFFFF to DMEM 0x4002_0204. Writes 0xAA with sb at offset 1. Verifies word now equals 0xFFFF_AAFF.",
        "DMEM word at 0x4002_0204 equals 0xFFFFAAFF; halfword write at offset 2 yields 0x5555AAFF.",
        "Monitor m1_wstrb and m1_wdata at Interconnect input during sb and sh operations.",
        "sb at offset 1 generates m1_wstrb=4'b0010; sh at offset 2 generates m1_wstrb=4'b1100.",
        "None (Internal)",
        "None",
        "None",
        "axi_width_downconverter_lsu, axi_sram_ctrl",
        "Byte-Strobe Masked Write Integrity",
        "0x4002_0204 (DMEM)",
        "C Memory Manipulation + SV Strobe Assertions",
        "LSU wstrb generation, SRAM byte write enables"
    )

    add_tc(
        "CPU_006",
        "Stack pointer initialization, push, pop, and stack boundary retention in DMEM",
        "Verify deep recursive function call stack usage in DMEM (starting at SP=0x4002_8000) and verify that stack frame push/pop restores registers cleanly.",
        "CP1: Recursive function depth of 32 calls; CP2: SP decrements by frame size on entry, increments on exit; CP3: Callee-saved registers (s0-s11) preserved.",
        "INTERNAL",
        "VeeR LSU -> Stack memory accesses in DMEM -> Return address and register restoration",
        "Firmware executes recursive factorial or Fibonacci computation: uint32_t fib(n=15). Computes 610.",
        "fib(15) returns exactly 610; SP returns to initial value 0x4002_8000.",
        "Monitor LSU store addresses during recursive descent. Verify SP remains within 0x4002_0000 - 0x4002_8000 and does not underflow.",
        "Min SP observed: ~0x4002_7D00; Max SP: 0x4002_8000; no DMEM boundary violations.",
        "None (Internal)",
        "None",
        "None",
        "u_veer_core, axi_sram_ctrl",
        "Stack Frame Allocation and Memory Retention",
        "0x4002_7000 - 0x4002_8000",
        "C Recursive Computation + SV Stack Limit Assertions",
        "LSU stack push/pop data retention"
    )

    add_tc(
        "CPU_007",
        "WFI (Wait For Interrupt) low-power sleep state and external interrupt wake-up",
        "Verify that executing WFI halts instruction fetching, asserts CPU halt status, and that an external Timer interrupt wakes the core cleanly.",
        "CP1: CPU executes wfi; CP2: IFU stops issuing ARVALID; CP3: o_cpu_halt_status asserts; CP4: Timer interrupt asserts; CP5: Core wakes, services ISR, and resumes.",
        "EXTERNAL",
        "VeeR Pipeline -> wfi decode -> Core halt state -> PIC external interrupt line -> Core wake-up logic -> Pipeline resume",
        "Firmware configures Timer for interrupt in 50us, then executes asm volatile('wfi'). Upon wake-up, writes 0xB007_0001 to mailbox.",
        "Mailbox receives wake-up signature 0xB007_0001; interrupt serviced counter increments.",
        "Monitor o_cpu_halt_status and core_ifu_arvalid. Verify IFU enters quiescence after WFI. Verify timer_intr assertion drops o_cpu_halt_status.",
        "o_cpu_halt_status goes high at T=100us; goes low upon timer_intr at T=150us; instruction fetch resumes.",
        "Timer External Interrupt & Halt Status",
        "None",
        "o_cpu_halt_status, timer_intr",
        "u_veer_core, el2_tlu, timer_core",
        "WFI Quiescence and Asynchronous Wake-Up",
        "0x4000_0000 (WFI loop)",
        "C WFI Invocation + SV Halt/Wake Timing Assertions",
        "TLU sleep control, wake-up interrupt enable"
    )

    add_tc(
        "CPU_008",
        "Trap entry (mcause, mepc, mstatus) and MRET return sequence",
        "Verify processor architectural CSR state transitions during trap entry and return via MRET. Check mepc saves PC, mcause reflects trap cause, and MPIE is restored.",
        "CP1: External interrupt or ECALL triggers trap; CP2: mepc captures PC of interrupted/next instruction; CP3: mstatus.MPP=3, MPIE=MIE, MIE=0; CP4: MRET restores MIE.",
        "INTERNAL",
        "VeeR TLU -> CSR register file (mcause, mepc, mstatus, mtvec) -> Trap vector redirect -> MRET execution",
        "Firmware invokes ecall instruction. ecall_handler() reads mcause (should be 11 for Environment call from M-mode), mepc, then executes mret.",
        "ecall succeeds and returns to instruction immediately following ecall; signature 0xECAL_0001 written to mailbox.",
        "Monitor trace_rv_i_exception_ip and trace_rv_i_address_ip. Verify PC vectoring to mtvec base address.",
        "trace_rv_i_exception_ip pulses high for 1 cycle; PC jumps to mtvec; returns via mret to ecall+4.",
        "None (Internal)",
        "None",
        "None",
        "u_veer_core, el2_tlu",
        "Trap Entry and MRET Architecture",
        "mtvec base, CSRs",
        "C ECALL Trap Test + SV CSR/Trace Monitor",
        "TLU exception handling state machine"
    )

    add_tc(
        "CPU_009",
        "CPU LSU regression on halfword unaligned address access",
        "Regression test for Phase 4 LSU bug: verify that reading halfwords or bytes at non-word-aligned addresses does not trigger spurious NMI or jump to address 0.",
        "CP1: Read halfword at address 0x4002_0002; CP2: LSU downconverter executes single 32-bit read; CP3: CPU does not jump to 0x0000_0000; CP4: Correct 16 bits extracted.",
        "INTERNAL",
        "VeeR LSU -> LSU width downconverter (R_AR_SINGLE) -> Interconnect -> DMEM -> Read data replication -> CPU LSU",
        "Firmware writes 0x12345678 to 0x4002_0000. Reads uint16_t from 0x4002_0002. Verifies result == 0x1234.",
        "Readback equals exactly 0x1234; no crash, no NMI, no jump to 0.",
        "Assert that trace_rv_i_address_ip NEVER equals 32'h0000_0000 during simulation.",
        "trace_rv_i_address_ip stays strictly within 0x4000_0000 - 0x4000_FFFF; R_AR_SINGLE state traversed cleanly.",
        "None (Internal)",
        "None",
        "None",
        "axi_width_downconverter_lsu, u_veer_core",
        "LSU Alignment Regression (Jump-to-0 Immunity)",
        "0x4002_0002",
        "C Unaligned Access Test + SV Never-Zero Assertion",
        "LSU downconverter single-beat read path"
    )

    # ----------------------------------------------------
    # 4. IMEM VERIFICATION
    # ----------------------------------------------------
    add_tc(
        "IMEM_001",
        "IMEM base address 0x4000_0000 instruction read and decode",
        "Verify that instruction fetch at the absolute lower boundary of IMEM (0x4000_0000) accesses word 0 of the internal SRAM array.",
        "CP1: IFU requests araddr=0x4000_0000; CP2: Interconnect decodes to S0 (IMEM); CP3: SRAM controller addresses mem[0]; CP4: Correct opcode returned.",
        "INTERNAL",
        "VeeR IFU -> IFU width downconverter -> Interconnect S0 decode -> axi_sram_ctrl mem[0] -> Read data path -> IFU",
        "Firmware boots from crt0.S at 0x4000_0000.",
        "First instruction executed matches imem.hex word 0.",
        "Monitor dut.GEN_INTERNAL_MEM.u_imem.s_axi_araddr. Verify s_axi_araddr[15:0] == 16'h0000.",
        "u_imem.s_axi_araddr == 16'h0000; u_imem.s_axi_rdata == mem[0].",
        "None (Internal)",
        "None",
        "None",
        "axi_sram_ctrl, axi_interconnect",
        "IMEM Lower Boundary Decode",
        "0x4000_0000",
        "SV Address Assertion + C Boot Flow",
        "Address decoder S0 match at lower boundary"
    )

    add_tc(
        "IMEM_002",
        "IMEM upper boundary address 0x4000_FFFC execution",
        "Verify execution of code located at the highest 32-bit word of the 64 KiB IMEM aperture (0x4000_FFFC), verifying complete 64 KiB memory capacity.",
        "CP1: Function placed at 0x4000_FFFC in linker script; CP2: CPU jumps to 0x4000_FFFC; CP3: SRAM accesses mem[16383]; CP4: Instruction returns cleanly via JALR.",
        "INTERNAL",
        "VeeR IFU -> IFU downconverter -> Interconnect S0 -> axi_sram_ctrl mem[16383] -> Return data -> CPU",
        "Firmware declares special function __attribute__((section(\".imem_top\"))) top_imem_func(). Main calls top_imem_func(), which returns 0xCAFE.",
        "top_imem_func() returns 0xCAFE; mailbox confirms pass.",
        "Check s_axi_araddr at u_imem matches 16'hFFFC when executing top_imem_func().",
        "u_imem.s_axi_araddr == 16'hFFFC; no DECERR returned; return value captured in a0.",
        "None (Internal)",
        "None",
        "None",
        "axi_sram_ctrl, soc.ld",
        "IMEM Upper Boundary 64 KiB Access",
        "0x4000_FFFC",
        "C Far Call Function + SV Address Assertion",
        "Address decoder S0 upper limit comparison"
    )

    add_tc(
        "IMEM_003",
        "Sequential instruction fetch across consecutive 32-bit words",
        "Verify pipelined linear instruction execution across consecutive 32-bit words without pipeline bubbles or fetch stalls.",
        "CP1: Straight-line execution of 50 consecutive instructions; CP2: IFU downconverter delivers dual words every 2 cycles; CP3: IPC approaches 1.",
        "INTERNAL",
        "VeeR IFU -> Dual 32b fetch -> Pipeline decode -> Execution",
        "Firmware executes straight-line sequence of 50 nop / addi instructions.",
        "All 50 instructions execute in ~55 clock cycles.",
        "Measure execution latency between instruction 1 and instruction 50 via trace_rv_i_valid_ip.",
        "trace_rv_i_valid_ip asserts continuously for 50 cycles with minimum stall cycles.",
        "None (Internal)",
        "None",
        "None",
        "u_veer_core, axi_width_downconverter_ifu",
        "Pipelined Sequential Instruction Fetch",
        "0x4000_0100 - 0x4000_01C8",
        "C Linear Assembly Block + SV Cycle Counter",
        "IFU prefetch buffer and branch predictor throughput"
    )

    add_tc(
        "IMEM_004",
        "Instruction fetch across 64-bit alignment boundaries via IFU downconverter",
        "Verify that 64-bit aligned IFU fetches correctly decompose into word0 (addr[2]=0) and word1 (addr[2]=1) in axi_width_downconverter_ifu.",
        "CP1: IFU issues arsize=3 (64-bit); CP2: Downconverter traverses S_AR_WORD0 -> S_R_WORD0 -> S_AR_WORD1 -> S_R_WORD1 -> S_RSP_DUAL; CP3: Combined 64-bit rdata delivered.",
        "INTERNAL",
        "VeeR IFU -> u_ifu_downconverter FSM -> Interconnect S0 -> 2x axi_sram_ctrl read -> u_ifu_downconverter pack -> VeeR IFU",
        "Firmware executes normal C instructions aligned on 8-byte boundaries.",
        "Code executes smoothly without decode faults.",
        "Monitor u_ifu_downconverter.state transitions during instruction fetch.",
        "State sequence 0 -> 1 -> 2 -> 3 -> 4 -> 5 -> 0 repeats deterministically during code fetch.",
        "None (Internal)",
        "None",
        "None",
        "axi_width_downconverter_ifu",
        "IFU 64b to 32b Dual-Word FSM Sequencing",
        "0x4000_0000 (IMEM)",
        "SV State Machine Assertion + C Normal Execution",
        "S_AR_WORD0, S_R_WORD0, S_AR_WORD1, S_R_WORD1 transitions"
    )

    add_tc(
        "IMEM_005",
        "Out-of-bounds IMEM access at 0x4001_0000 DECERR check",
        "Verify that attempting an instruction fetch or LSU read at 0x4001_0000 (immediately beyond IMEM 64 KiB boundary) returns AXI DECERR (2'b11).",
        "CP1: Read address 0x4001_0000 issued; CP2: Interconnect S0 address window does not match; CP3: Interconnect routes to default DECERR slave; CP4: rresp=2'b11 returned.",
        "INTERNAL",
        "VeeR LSU -> Interconnect address decoder -> Default DECERR slave -> DECERR response -> LSU",
        "Firmware performs read from memory pointer 0x4001_0000 (volatile uint32_t*).",
        "CPU receives bus error response without simulator deadlock or bus hang.",
        "Monitor m1_rresp or m0_rresp when address 0x4001_0000 is requested on AXI bus.",
        "m_axi_rresp == 2'b11 (DECERR); transaction finishes within 4 clock cycles.",
        "None (Internal)",
        "None",
        "None",
        "axi_interconnect, main_top",
        "IMEM Aperture Boundary Enforcement",
        "0x4001_0000 (Immediate Out-of-Bounds)",
        "C Out-of-Bounds Read + SV Protocol Assertion",
        "Interconnect default decode error logic"
    )

    add_tc(
        "IMEM_006",
        "Backdoor memory preload using $readmemh into 64 KiB array",
        "Verify that testbench backdoor loading via $readmemh correctly populates the complete 16,384-word (64 KiB) array in axi_sram_ctrl without data corruption.",
        "CP1: $readmemh called before reset release; CP2: Word 0 contains first instruction; CP3: Last word (16383) initialized correctly; CP4: Synthesizable NOP loop overridden.",
        "INTERNAL",
        "Testbench $readmemh -> dut.GEN_INTERNAL_MEM.u_imem.mem[0:16383]",
        "Firmware relies on imem.hex containing valid compiled ELF code.",
        "Core successfully boots and executes main() without encountering uninitialized memory traps.",
        "In testbench, assert dut.GEN_INTERNAL_MEM.u_imem.mem[0] == 32'h00028117 prior to releasing rst.",
        "dut.GEN_INTERNAL_MEM.u_imem.mem[0] == 32'h00028117 check passes unconditionally.",
        "None (Internal)",
        "None",
        "None",
        "axi_sram_ctrl, tb_soc_top",
        "Backdoor Firmware Image Preload",
        "dut.GEN_INTERNAL_MEM.u_imem.mem",
        "SV Testbench Preload Verification",
        "Backdoor SRAM initialization integrity"
    )

    # ----------------------------------------------------
    # 5. DMEM VERIFICATION
    # ----------------------------------------------------
    add_tc(
        "DMEM_001",
        "DMEM base address 0x4002_0000 read and write verification",
        "Verify that reading and writing to the absolute base address of DMEM (0x4002_0000) functions correctly and targets word 0 of the internal DMEM array.",
        "CP1: Write 0xA5A50001 to 0x4002_0000; CP2: Read back from 0x4002_0000; CP3: Value matches; CP4: Internal memory mem[0] equals written word.",
        "INTERNAL",
        "VeeR LSU -> LSU downconverter -> Interconnect S1 -> DMEM axi_sram_ctrl mem[0] -> Readback",
        "Firmware writes 0xA5A50001 to 0x4002_0000 (mailbox register), then reads it back and asserts equality.",
        "Readback value == 0xA5A50001.",
        "Monitor u_dmem.s_axi_awaddr and s_axi_wdata. Verify mem[0] contains 0xA5A50001.",
        "u_dmem.s_axi_awaddr[15:0] == 16'h0000; mem[0] == 32'hA5A50001.",
        "None (Internal)",
        "None",
        "None",
        "axi_sram_ctrl, axi_interconnect",
        "DMEM Base Address Read/Write",
        "0x4002_0000",
        "C Mailbox Write/Read + SV SRAM Latch Monitor",
        "DMEM base address decode and array indexing"
    )

    add_tc(
        "DMEM_002",
        "DMEM upper boundary address 0x4002_FFFC read and write verification",
        "Verify read and write operations at the maximum word address of the 64 KiB DMEM space (0x4002_FFFC), proving full 64 KiB capacity.",
        "CP1: Write 0x55AA_1234 to 0x4002_FFFC; CP2: Read back from 0x4002_FFFC; CP3: Value matches; CP4: Targeted word is mem[16383].",
        "INTERNAL",
        "VeeR LSU -> LSU downconverter -> Interconnect S1 -> DMEM axi_sram_ctrl mem[16383] -> Readback",
        "Firmware writes test pattern to (volatile uint32_t*)0x4002_FFFC, reads back, and verifies.",
        "Readback == 0x55AA1234; mailbox receives 0xCAFE0002 confirmation.",
        "Monitor u_dmem.s_axi_awaddr == 16'hFFFC.",
        "u_dmem.mem[16383] == 32'h55AA1234.",
        "None (Internal)",
        "None",
        "None",
        "axi_sram_ctrl, soc.ld",
        "DMEM Upper Boundary 64 KiB Access",
        "0x4002_FFFC",
        "C Pointer Write/Read + SV Memory Assertion",
        "DMEM upper limit comparison logic"
    )

    add_tc(
        "DMEM_003",
        "Byte write strobes (wstrb = 4'b0001, 0010, 0100, 1000) data isolation",
        "Verify that writing individual bytes to DMEM using byte-wide store instructions modifies only the selected byte while preserving all adjacent bytes.",
        "CP1: Pre-fill word with 0x00000000; CP2: Write byte 0 (0x11); CP3: Write byte 1 (0x22); CP4: Write byte 2 (0x33); CP5: Write byte 3 (0x44); CP6: Word equals 0x44332211.",
        "INTERNAL",
        "VeeR LSU -> core_lsu_wstrb -> LSU downconverter -> m1_wstrb -> DMEM axi_sram_ctrl byte write enables",
        "Firmware writes 0x00000000 to 0x4002_0210. Uses uint8_t pointers to write bytes at +0, +1, +2, +3 sequentially.",
        "Final read of 32-bit word at 0x4002_0210 equals exactly 0x44332211.",
        "Monitor u_dmem.s_axi_wstrb on successive write handshakes.",
        "wstrb values observed in sequence: 4'b0001, 4'b0010, 4'b0100, 4'b1000.",
        "None (Internal)",
        "None",
        "None",
        "axi_sram_ctrl",
        "DMEM Byte Strobe Isolation",
        "0x4002_0210",
        "C Byte-by-Byte Write Test + SV Strobe Monitor",
        "axi_sram_ctrl individual byte lane write enables"
    )

    add_tc(
        "DMEM_004",
        "Halfword write strobes (wstrb = 4'b0011, 1100) data isolation",
        "Verify halfword store instructions (sh) writing lower and upper 16-bit lanes with independent byte strobes.",
        "CP1: Pre-fill word with 0x00000000; CP2: Write lower halfword 0xBEEF (wstrb=4'b0011); CP3: Write upper halfword 0xDEAD (wstrb=4'b1100); CP4: Word equals 0xDEADBEEF.",
        "INTERNAL",
        "VeeR LSU -> core_lsu_wstrb -> LSU downconverter -> m1_wstrb -> DMEM axi_sram_ctrl byte lanes",
        "Firmware writes 0x00000000 to 0x4002_0214. Uses uint16_t pointers to write 0xBEEF at offset 0, and 0xDEAD at offset 2.",
        "32-bit read at 0x4002_0214 equals 0xDEADBEEF.",
        "Check u_dmem.s_axi_wstrb == 4'b0011 then 4'b1100.",
        "wstrb=4'b0011 observed; then wstrb=4'b1100 observed; memory contains 0xDEADBEEF.",
        "None (Internal)",
        "None",
        "None",
        "axi_sram_ctrl",
        "DMEM Halfword Strobe Isolation",
        "0x4002_0214",
        "C Halfword Write Test + SV Strobe Monitor",
        "axi_sram_ctrl 16-bit lane write enables"
    )

    add_tc(
        "DMEM_005",
        "Full 32-bit word write and non-aliasing readback across DMEM address space",
        "Verify that writing to distinct memory locations across DMEM does not cause address aliasing (e.g. between offset 0x0000, 0x1000, 0x4000, 0x8000).",
        "CP1: Write distinct pattern to 0x4002_0000, 0x4002_1000, 0x4002_4000, 0x4002_8000; CP2: Read back all addresses; CP3: Verify zero cross-talk.",
        "INTERNAL",
        "VeeR LSU -> LSU downconverter -> Interconnect S1 -> DMEM controller -> Full memory array",
        "Firmware writes unique pseudo-random numbers to power-of-2 addresses across DMEM. Reads all back and verifies none were overwritten.",
        "All values read back match their respective unique patterns with 0 errors.",
        "Monitor u_dmem.awaddr_reg across writes and verify unique physical memory indices.",
        "Physical memory lines 0, 1024, 4096, 8192 each hold their independent unique data.",
        "None (Internal)",
        "None",
        "None",
        "axi_sram_ctrl",
        "DMEM Non-Aliasing Address Line Integrity",
        "0x4002_0000 - 0x4002_FFFF",
        "C March/Aliasing Test + SV Array Verification",
        "Address bus decoding bits [15:2] across entire array"
    )

    add_tc(
        "DMEM_006",
        "DMEM BSS segment zeroing and static data section initialization",
        "Verify that the startup code crt0.S properly zeroes out uninitialized global variables (.bss) and copies initialized variables (.data) from IMEM to DMEM.",
        "CP1: .bss variables contain 0x00000000; CP2: Initialized global variables contain their specified non-zero constants; CP3: Values are stable before main() entry.",
        "INTERNAL",
        "VeeR Boot Flow -> crt0.S memcpy & memset -> DMEM .data & .bss sections",
        "Firmware declares initialized global: uint32_t g_init = 0x12345678; and uninitialized global: uint32_t g_uninit; in main(), asserts g_init==0x12345678 and g_uninit==0.",
        "Assertions pass; mailbox receives 0xB550_0001.",
        "Inspect DMEM memory contents via backdoor immediately after reset release and before main() execution.",
        "g_init location holds 0x12345678; g_uninit location holds 0x00000000.",
        "None (Internal)",
        "None",
        "None",
        "crt0.S, soc.ld, axi_sram_ctrl",
        "C Runtime Environment Data/BSS Initialization",
        "0x4002_0000+ (DMEM .data and .bss)",
        "C Variable Integrity Check + SV Backdoor Inspection",
        "Data copy loop and BSS zeroing loop in crt0.S"
    )

    add_tc(
        "DMEM_007",
        "Mailbox signature handshake register read/write at 0x4002_0000",
        "Verify the standard testbench-firmware handshake protocol using DMEM word 0 (0x4002_0000) for progress signatures and status reporting.",
        "CP1: Testbench monitors 0x4002_0000; CP2: Firmware writes step signatures (0xA5A50001, 0xCAFE0001...); CP3: Testbench synchronizes verification checkpoints.",
        "INTERNAL",
        "VeeR LSU -> DMEM 0x4002_0000 -> Testbench monitor",
        "Firmware updates mailbox register at each major test milestone.",
        "Mailbox updates from 0xA5A50001 to final PASS signature 0xCAFE0011.",
        "SV testbench wait statement: wait(dut.GEN_INTERNAL_MEM.u_dmem.mem[0] == 32'hCAFE0011); with timeout protection.",
        "Target signature reached before timeout; simulation ends gracefully.",
        "None (Internal)",
        "None",
        "None",
        "axi_sram_ctrl, tb_soc_top",
        "Software-Hardware Mailbox Protocol",
        "0x4002_0000 (Mailbox)",
        "C Mailbox Write + SV Testbench Handshake",
        "Mailbox synchronization interface"
    )

    add_tc(
        "DMEM_008",
        "Out-of-bounds DMEM access at 0x4003_0000 DECERR check",
        "Verify that attempting a load or store to 0x4003_0000 (immediately beyond DMEM 64 KiB boundary) returns AXI DECERR (2'b11).",
        "CP1: LSU issues awaddr=0x4003_0000; CP2: Interconnect S1 address decoder does not match; CP3: Default error slave responds; CP4: bresp=2'b11 returned.",
        "INTERNAL",
        "VeeR LSU -> Interconnect -> Default DECERR slave -> DECERR response -> LSU",
        "Firmware performs write to (volatile uint32_t*)0x4003_0000.",
        "Write completes with bus error; core remains responsive without freeze.",
        "Monitor m1_bresp at interconnect output when 0x4003_0000 is written.",
        "m_axi_bresp == 2'b11 (DECERR); transaction finishes within 4 cycles.",
        "None (Internal)",
        "None",
        "None",
        "axi_interconnect, main_top",
        "DMEM Aperture Boundary Enforcement",
        "0x4003_0000 (Immediate Out-of-Bounds)",
        "C Out-of-Bounds Write + SV Protocol Assertion",
        "Interconnect address decode boundary check"
    )
