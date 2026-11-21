# scripts/test_plan_part5.py
# Categories 16-20: ERROR, CONCURRENCY, BOUNDARY, EXTERNAL, INTEGRATION

def populate_part5(add_tc):
    # ----------------------------------------------------
    # 16. ERROR HANDLING
    # ----------------------------------------------------
    add_tc(
        "ERROR_001",
        "Interconnect DECERR response on unmapped address read (0x9000_0000)",
        "Issue an AXI read to unmapped address 0x9000_0000. Verify that the interconnect default error slave asserts rvalid, returns rresp=2'b11 (DECERR), and does not hang.",
        "CP1: arvalid asserts for 0x9000_0000; CP2: Default slave asserts arready; CP3: rvalid asserts with rresp=2'b11; CP4: Master completes transaction cleanly.",
        "INTERNAL",
        "VeeR LSU -> axi_interconnect default slave -> DECERR response -> LSU error response",
        "Firmware attempts volatile load from 0x9000_0000.",
        "Load completes with bus error; core remains stable without hanging.",
        "Assert m1_rresp == 2'b11 and transaction finishes within 10 cycles.",
        "m1_rresp == 2'b11; latency <= 5 clock cycles.",
        "None (Internal)",
        "None",
        "None",
        "axi_interconnect",
        "Unmapped Address Read DECERR Generation",
        "0x9000_0000",
        "C Unmapped Load Probe + SV Protocol Checker",
        "Interconnect default slave read FSM"
    )

    add_tc(
        "ERROR_002",
        "Interconnect DECERR response on unmapped address write (0x9000_0000)",
        "Issue an AXI write to unmapped address 0x9000_0000. Verify that the interconnect default slave accepts awvalid/wvalid and returns bresp=2'b11 (DECERR).",
        "CP1: awvalid/wvalid asserted for 0x9000_0000; CP2: Default slave accepts address and data; CP3: bvalid asserts with bresp=2'b11; CP4: No hang.",
        "INTERNAL",
        "VeeR LSU -> axi_interconnect default slave -> DECERR response -> LSU write complete",
        "Firmware attempts volatile store to 0x9000_0000 with pattern 0xBAD0BAD0.",
        "Store completes with bus error; next instruction executes normally.",
        "Assert m1_bresp == 2'b11 and m1_bvalid asserts within 5 cycles of write commit.",
        "m1_bresp == 2'b11; bus frees immediately.",
        "None (Internal)",
        "None",
        "None",
        "axi_interconnect",
        "Unmapped Address Write DECERR Generation",
        "0x9000_0000",
        "C Unmapped Store Probe + SV Protocol Checker",
        "Interconnect default slave write FSM"
    )

    add_tc(
        "ERROR_003",
        "Interconnect DECERR on reserved slave S5 access (0x0000_0000)",
        "Issue read/write to address 0x0000_0000 (disabled slave S5 aperture). Verify interconnect returns DECERR and core does not vector to 0x0.",
        "CP1: Address 0x0000_0000 requested; CP2: M05_ADDR_WIDTH=0; CP3: Default slave responds with DECERR; CP4: Zero data written; zero hang.",
        "INTERNAL",
        "VeeR LSU -> axi_interconnect -> Disabled S5 check -> Default slave -> DECERR",
        "Firmware performs read/write probe to address 0x0000_0000.",
        "Read/write completes with bus error; core does not crash.",
        "Assert that trace_rv_i_address_ip does not jump to 0x0000_0000 upon receiving bus error.",
        "trace_rv_i_address_ip remains in normal program range; rresp/bresp == 2'b11.",
        "None (Internal)",
        "None",
        "None",
        "axi_interconnect",
        "Disabled Slave S5 DECERR Protection",
        "0x0000_0000",
        "C Address 0 Probe + SV Zero-PC Assertion",
        "M05 disabled slave comparator"
    )

    add_tc(
        "ERROR_004",
        "Interconnect DECERR on reserved slave S11 access (0x4005_0000)",
        "Issue write to 0x4005_0000 (disabled slave S11 slot). Verify interconnect returns DECERR and no internal peripheral register is corrupted.",
        "CP1: Address 0x4005_0000 requested; CP2: M11_ADDR_WIDTH=0; CP3: bresp=2'b11 returned; CP4: Adjacent valid slaves (PWM at 0x4004_1000) unaffected.",
        "INTERNAL",
        "VeeR LSU -> axi_interconnect -> Disabled S11 check -> Default slave -> DECERR",
        "Firmware writes to 0x4005_0000, then verifies PWM registers are unchanged.",
        "PWM registers retain original values; write error reported.",
        "Monitor m1_bresp and u_pwm.slv_reg0.",
        "bresp == 2'b11; u_pwm.slv_reg0 untouched.",
        "None (Internal)",
        "None",
        "None",
        "axi_interconnect",
        "Disabled Slave S11 DECERR Protection",
        "0x4005_0000",
        "C S11 Write Probe + C Neighbor Register Audit",
        "M11 disabled slave comparator"
    )

    add_tc(
        "ERROR_005",
        "AXI width downconverter error response propagation to CPU LSU",
        "Verify that when the interconnect returns DECERR or SLVERR to the LSU width downconverter, the error is faithfully propagated back to the 64-bit core LSU bus.",
        "CP1: Interconnect returns m_axi_bresp=2'b11; CP2: Downconverter latches error; CP3: s_axi_bresp returned to core is 2'b11; CP4: s_axi_bvalid asserts.",
        "INTERNAL",
        "Interconnect default slave -> LSU width downconverter W_WAIT_BRESP -> Core LSU s_axi_bresp",
        "Firmware writes to invalid address. Core LSU receives bus error response.",
        "Bus error correctly recorded in core LSU status.",
        "Monitor u_lsu_downconverter.s_axi_bresp when m_axi_bresp is forced to 2'b11.",
        "s_axi_bresp == 2'b11; error is not swallowed or converted to OKAY.",
        "None (Internal)",
        "None",
        "None",
        "axi_width_downconverter_lsu",
        "Downconverter Bus Error Propagation",
        "LSU Master/Slave Interfaces",
        "SV Response Checker + C Error Probe",
        "Error response bypass and OR logic"
    )

    add_tc(
        "ERROR_006",
        "CPU recovery and non-hang behavior on receiving bus DECERR",
        "Verify that after the CPU encounters an unmapped access and receives DECERR, the pipeline recovers immediately and executes subsequent valid memory accesses normally.",
        "CP1: CPU receives DECERR from 0x9000_0000; CP2: CPU pipeline does not deadlock; CP3: Subsequent write to DMEM 0x4002_0000 succeeds; CP4: Full recovery.",
        "INTERNAL",
        "VeeR LSU -> Invalid Access -> DECERR -> Pipeline recovery -> Valid DMEM access",
        "Firmware writes to 0x9000_0000, then immediately writes 0x12345678 to 0x4002_0000. Reads back.",
        "Readback == 0x12345678; recovery confirmed; mailbox receives 0xEEEE_0001.",
        "Verify that simulation does not hit timeout and no AXI channel remains hung.",
        "All AXI channels return to idle; next transaction completes in normal cycles.",
        "None (Internal)",
        "None",
        "None",
        "u_veer_core, axi_width_downconverter_lsu, axi_interconnect",
        "Post-Error Pipeline and Bus Recovery",
        "0x9000_0000 -> 0x4002_0000",
        "C Consecutive Error-then-Valid Sequence",
        "Pipeline stall clear, bus handshake recovery"
    )

    # ----------------------------------------------------
    # 17. CONCURRENT AND STRESS SCENARIOS
    # ----------------------------------------------------
    add_tc(
        "CONCURRENCY_001",
        "Concurrent M0 instruction fetch from IMEM and M1 LSU store to DMEM",
        "Verify simultaneous non-interfering operation: Master M0 fetches instructions from IMEM (0x4000_xxxx) while Master M1 performs continuous stores to DMEM (0x4002_xxxx).",
        "CP1: M0 arvalid=1 to S0; CP2: M1 awvalid=1 to S1 in exact same cycle; CP3: Interconnect routes both independently; CP4: Zero cross-master wait states.",
        "INTERNAL",
        "M0 -> Interconnect S0 (IMEM) || M1 -> Interconnect S1 (DMEM) -> Concurrent execution",
        "Firmware executes tightly-coded loop in IMEM performing back-to-back stores to DMEM array.",
        "Memory array correctly populated; loop execution rate reaches peak theoretical throughput.",
        "Assert m00_axi_arvalid and m01_axi_awvalid are asserted simultaneously in the same clock cycle.",
        "Simultaneous valid handshakes observed on independent slave ports; zero conflict.",
        "None (Internal)",
        "None",
        "None",
        "axi_interconnect, main_top",
        "Crossbar Non-Blocking Concurrent Access",
        "0x4000_xxxx & 0x4002_xxxx",
        "C Tight Memory Loop + SV Crossbar Port Monitor",
        "Interconnect independent crossbar multiplexers"
    )

    add_tc(
        "CONCURRENCY_002",
        "Concurrent CPU MMIO access and autonomous Hybrid feedback operation",
        "Verify that supervisory CPU read/write transactions to GPIO/Timer do not interrupt or delay autonomous real-time Encoder -> PID -> PWM feedback updates.",
        "CP1: Fast feedback loop active (period 10us); CP2: CPU continuously accesses GPIO and Timer registers; CP3: PID update jitter is strictly zero.",
        "EXTERNAL",
        "CPU MMIO -> Interconnect S2/S3 || Autonomous feedback -> PID/PWM hardware path -> External PWM_OUT",
        "Firmware runs heavy MMIO polling loop reading GPIO DATA_I and Timer VAL continuously.",
        "MMIO polling loop runs without error; no bus stalls.",
        "Measure cycle intervals between successive u_pid.pid_out_valid pulses during CPU MMIO activity.",
        "PID update interval remains completely jitter-free (exact 100-cycle period).",
        "Encoder Inputs & PWM Output",
        "enc_a, enc_b",
        "PWM_OUT, gpio_io[31:0]",
        "main_top, soc_top",
        "Hardware-Software Resource Isolation",
        "MMIO + Hardware Datapath",
        "C Intensive MMIO Polling + SV PID Jitter Measurement",
        "Peripheral register bus separation from direct datapath"
    )

    add_tc(
        "CONCURRENCY_003",
        "Concurrent UART transmission while Timer interrupt is serviced",
        "Verify that when UART is actively transmitting a multi-byte string, a Timer interrupt fires and is serviced by the CPU without corrupting UART character timing.",
        "CP1: UART transmitting byte at 115200 baud; CP2: Timer interrupt vectors and executes 50-instruction ISR; CP3: uart_tx bit timing unaffected.",
        "EXTERNAL",
        "UART transmitter shift register || Timer interrupt -> CPU ISR execution -> External uart_tx pin",
        "Firmware begins printing long string via UART, configures periodic timer interrupt during transmission.",
        "Complete string received cleanly on UART receiver; all interrupts serviced.",
        "Measure UART bit duration during ISR execution in testbench.",
        "uart_tx bit widths strictly maintain 8.68us (+/-0.5%); zero baud jitter.",
        "UART Output & Timer Interrupt",
        "None",
        "uart_tx, timer_intr",
        "axi_uart_top, timer_core, u_veer_core",
        "Asynchronous Interrupt vs Autonomous Peripheral Transmission",
        "UART THR + Timer ISR",
        "C Concurrent Print/ISR Stress + SV Bit Width Monitor",
        "Hardware UART baud generator autonomy from CPU state"
    )

    add_tc(
        "CONCURRENCY_004",
        "Concurrent External DMA (M2) write to DMEM while CPU executes from IMEM",
        "Drive DMA transactions from external s02_axi port into DMEM while CPU is fetching and executing compute code from IMEM.",
        "CP1: s02_axi writes 128 bytes to DMEM 0x4002_0800; CP2: CPU executes sorting algorithm in IMEM; CP3: Both masters operate at full bandwidth.",
        "EXTERNAL",
        "External DMA Master (s02_axi) -> Interconnect S1 (DMEM) || VeeR IFU -> Interconnect S0 (IMEM)",
        "Firmware computes checksum of code while DMA transfers background buffer into DMEM.",
        "Both computations finish with correct golden checksums.",
        "Drive DMA write burst on s02_axi. Monitor core_ifu_arvalid and s02_axi_wvalid.",
        "Both valid signals assert concurrently; zero interference.",
        "External DMA Master Port (M2)",
        "s02_axi_awaddr, s02_axi_awvalid, s02_axi_wdata, s02_axi_wvalid, s02_axi_bready",
        "s02_axi_awready, s02_axi_wready, s02_axi_bvalid, trace_rv_i_valid_ip",
        "axi_interconnect, main_top",
        "Multi-Master Concurrent Memory Access",
        "0x4000_xxxx (IMEM) & 0x4002_0800 (DMEM)",
        "SV External DMA Stimulus + C CPU Compute Task",
        "Independent master-to-slave routing matrix"
    )

    add_tc(
        "CONCURRENCY_005",
        "Contention between M1 (LSU) and M2 (DMA) simultaneously addressing DMEM",
        "Force Master M1 and External DMA Master M2 to issue writes to adjacent DMEM words in the exact same cycle. Verify arbiter alternates access cleanly.",
        "CP1: M1 writes to 0x4002_0A00; CP2: M2 writes to 0x4002_0A04 in same cycle; CP3: Arbiter grants one, holds other; CP4: Both writes complete with OKAY.",
        "EXTERNAL",
        "M1 (LSU) & M2 (DMA) -> axi_interconnect arbiter -> S1 (DMEM) -> Dual OKAY responses",
        "Firmware writes 0x11111111 to 0x4002_0A00 in a tight loop.",
        "Both memory words hold their correct independent data without data corruption.",
        "Drive s02_axi_awvalid=1 targeting 0x4002_0A04 simultaneously with M1 write. Monitor arbiter grant signal.",
        "One master granted cycle N; second master granted cycle N+2; both bresp==2'b00.",
        "External DMA Master Port (M2)",
        "s02_axi_awaddr, s02_axi_awvalid, s02_axi_wdata, s02_axi_wvalid, s02_axi_bready",
        "s02_axi_awready, s02_axi_wready, s02_axi_bvalid",
        "axi_interconnect, arbiter",
        "Shared Slave Arbiter Contention Resolution",
        "0x4002_0A00 - 0x4002_0A04 (DMEM)",
        "SV Concurrent Drive + C Contention Loop",
        "Arbiter round-robin state transitions"
    )

    # ----------------------------------------------------
    # 18. BOUNDARY CONDITIONS
    # ----------------------------------------------------
    add_tc(
        "BOUNDARY_001",
        "IMEM 64 KiB boundary wrap-around prevention (0x4000_FFFF to 0x4001_0000)",
        "Verify that sequential instruction execution approaching the end of IMEM (0x4000_FFFC) does not wrap around to 0x4000_0000.",
        "CP1: Code executed at 0x4000_FFFC; CP2: Attempt to increment PC to 0x4001_0000 triggers DECERR / trap; CP3: Does not silently jump to 0x4000_0000.",
        "INTERNAL",
        "VeeR IFU sequential fetch -> IMEM upper bound -> Interconnect DECERR -> Instruction access fault trap",
        "Firmware places jump instruction at 0x4000_FFFC safely branching back to main program.",
        "Branch succeeds without wrapping.",
        "Check address issued on AXI bus. Assert araddr does not wrap from 0x4000_FFFC to 0x4000_0000.",
        "No address wrap-around observed; memory indexing strictly bounded.",
        "None (Internal)",
        "None",
        "None",
        "axi_sram_ctrl, u_veer_core",
        "IMEM Address Space Wrap-Around Prevention",
        "0x4000_FFFC",
        "C Boundary Branch Test + SV Address Assertion",
        "IMEM address bit mask [15:2]"
    )

    add_tc(
        "BOUNDARY_002",
        "DMEM 64 KiB boundary wrap-around prevention (0x4002_FFFF to 0x4003_0000)",
        "Verify that word store to 0x4002_FFFC does not corrupt word at 0x4002_0000.",
        "CP1: Write distinct pattern to 0x4002_0000; CP2: Write distinct pattern to 0x4002_FFFC; CP3: Verify 0x4002_0000 retains its original value.",
        "INTERNAL",
        "VeeR LSU -> DMEM controller mem[16383] vs mem[0]",
        "Firmware writes 0xAAAAAAAA to 0x4002_0000. Writes 0x55555555 to 0x4002_FFFC. Reads back 0x4002_0000.",
        "Readback at 0x4002_0000 equals 0xAAAAAAAA (no wrap-around corruption).",
        "Monitor u_dmem.mem[0] and u_dmem.mem[16383].",
        "mem[0] == 32'hAAAAAAAA; mem[16383] == 32'h55555555.",
        "None (Internal)",
        "None",
        "None",
        "axi_sram_ctrl",
        "DMEM Address Space Wrap-Around Prevention",
        "0x4002_0000 & 0x4002_FFFC",
        "C End-Point Isolation Test + SV Array Check",
        "DMEM address bit mask [15:2]"
    )

    add_tc(
        "BOUNDARY_003",
        "GPIO 32-bit all-ones (0xFFFFFFFF) and all-zeros (0x00000000) data patterns",
        "Write alternating boundary bitmasks (0xFFFFFFFF and 0x00000000) to GPIO DATA_O. Verify all 32 external gpio_io pins switch simultaneously.",
        "CP1: Write 0xFFFFFFFF; CP2: All 32 pins driven high; CP3: Write 0x00000000; CP4: All 32 pins driven low; CP5: Zero bit stuck-at faults.",
        "EXTERNAL",
        "VeeR LSU -> GPIO DATA_O -> All 32 external gpio_io pins",
        "Firmware writes 0xFFFFFFFF, reads back, writes 0x00000000, reads back.",
        "Both readbacks match.",
        "Monitor external gpio_io[31:0]. Assert all bits switch simultaneously.",
        "gpio_io transitions 0x00000000 <-> 0xFFFFFFFF cleanly.",
        "GPIO External I/O",
        "None",
        "gpio_io[31:0]",
        "gpio_regs, gpio_wrapper",
        "GPIO 32-Bit Full-Width Simultaneous Switching",
        "0x4003_1004 (DATA_O), gpio_io pins",
        "SV 32-Bit Bus Monitor + C Extreme Pattern Write",
        "All 32 output flop lanes and tri-state buffers"
    )

    add_tc(
        "BOUNDARY_004",
        "Timer counter 32-bit maximum load value (0xFFFFFFFF) countdown",
        "Program Timer LOAD register with maximum 32-bit value 0xFFFFFFFF. Verify counter begins counting down from 0xFFFFFFFF without overflow or truncation.",
        "CP1: LOAD = 0xFFFFFFFF; CP2: VAL decrements: 0xFFFFFFFF, 0xFFFFFFFE...; CP3: Full 32-bit decrementer operational.",
        "INTERNAL",
        "VeeR LSU -> Timer LOAD -> timer_core 32-bit downcounter",
        "Firmware sets LOAD=0xFFFFFFFF, CTRL=0x01. Reads VAL.",
        "VAL reads ~0xFFFFFFF0.",
        "Monitor u_timer.u_timer_core.counter bits [31:0].",
        "All 32 counter bits decrement properly; bit 31 remains 1.",
        "None (Internal)",
        "None",
        "None",
        "timer_core",
        "Timer 32-Bit Maximum Value Countdown",
        "0x4003_3004 (LOAD)",
        "C Max Load Test + SV Flop Monitor",
        "Full 32-bit subtraction carry chain"
    )

    add_tc(
        "BOUNDARY_005",
        "Encoder 32-bit position count positive/negative wrap-around",
        "Verify signed 32-bit position counter behavior at extreme boundaries: counting past 0x7FFFFFFF (positive wrap) and below 0x80000000 (negative wrap).",
        "CP1: COUNT set to 0x7FFFFFFF; CP2: Forward pulse applied; CP3: COUNT wraps to 0x80000000 (-2147483648); CP4: Reverse pulse wraps back to 0x7FFFFFFF.",
        "EXTERNAL",
        "enc_a/enc_b pulses -> enc_core 32-bit signed counter wrap-around",
        "Firmware initializes COUNT to 0x7FFFFFFF, applies forward pulse, reads COUNT.",
        "COUNT reads 0x80000000; signed overflow detected in software.",
        "Monitor u_encoder.count_reg across wrap transition.",
        "count_reg transitions 32'h7FFFFFFF -> 32'h80000000.",
        "Quadrature Encoder External Inputs",
        "enc_a, enc_b",
        "None",
        "enc_core",
        "Encoder 32-Bit Signed Count Wrap-Around",
        "0x4003_D000 (COUNT), enc_a/enc_b pins",
        "SV Boundary Pulse Generator + C Readback",
        "Position counter rollover and overflow bit"
    )

    add_tc(
        "BOUNDARY_006",
        "PID maximum positive error (+32767) and maximum negative error (-32768)",
        "Apply extreme error inputs to PID controller: setpoint=+32767, actual=0 (max positive) and setpoint=-32768, actual=0 (max negative). Verify numerical stability.",
        "CP1: Positive error = +32767; CP2: Output saturates cleanly to OUT_MAX without sign flip; CP3: Negative error = -32768; CP4: Output saturates cleanly to OUT_MIN.",
        "INTERNAL",
        "VeeR LSU -> PID SETPOINT -> pid_core ALU -> Saturation clamp",
        "Firmware tests boundary setpoints +32767 and -32768. Reads OUTPUT.",
        "Positive setpoint clamps at OUT_MAX (+32767); negative setpoint clamps at OUT_MIN (0). Zero sign inversion.",
        "Assert that u_pid.pid_out is positive for +32767 and non-negative for -32768.",
        "Numerical stability verified: no signed multiplication overflow flip.",
        "None (Internal)",
        "None",
        "None",
        "pid_core",
        "PID Extreme Error Numerical Dynamic Range",
        "0x4003_F000 (SETPOINT)",
        "C Extreme Value Test + SV Sign Bit Assertion",
        "Multiplier saturation logic and sign bit protection"
    )

    # ----------------------------------------------------
    # 19. EXTERNAL INTERFACES
    # ----------------------------------------------------
    add_tc(
        "EXTERNAL_001",
        "External UART loopback cable verification (uart_tx connected to uart_rx)",
        "Connect external uart_tx pin directly to external uart_rx pin in testbench. Transmit data packet from CPU. Verify CPU receives identical packet via UART ISR.",
        "CP1: uart_tx wired to uart_rx; CP2: Firmware sends 'SoC_PASS'; CP3: UART RX interrupt triggers; CP4: Received packet matches transmitted packet byte-for-byte.",
        "EXTERNAL",
        "VeeR CPU -> UART TX -> External uart_tx pin -> Testbench Loopback Wire -> External uart_rx pin -> UART RX -> VeeR CPU",
        "Firmware transmits test payload string. In UART RX ISR, receives bytes into buffer. Asserts strcmp(tx_buf, rx_buf) == 0.",
        "Loopback payload matches 100%; signature 0x1009_0001 written to mailbox.",
        "Instantiate wire in testbench: assign uart_rx = uart_tx; monitor serialized data bits on the loopback net.",
        "Zero bit corruption over 1,000 transmitted bytes on loopback net.",
        "External UART Serial Loopback",
        "uart_rx",
        "uart_tx, uart_irq",
        "axi_uart_top, main_top, soc_top",
        "External Serial Loopback Channel Verification",
        "uart_tx -> uart_rx loopback net",
        "C Transmit/Receive Full-Duplex Test + SV Loopback Wire",
        "Simultaneous TX and RX operation in axi_uart_top"
    )

    add_tc(
        "EXTERNAL_002",
        "External Quadrature Encoder stimulus generation (enc_a, enc_b, enc_index)",
        "Generate realistic physical motor encoder waveform from testbench with configurable RPM and acceleration. Verify SoC calculates correct angular velocity.",
        "CP1: Testbench generates 1000 RPM quadrature waveforms; CP2: enc_index pulses once per revolution (1000 CPR); CP3: SoC telemetry matches simulated RPM.",
        "EXTERNAL",
        "Testbench Motor Model -> enc_a, enc_b, enc_index pins -> enc_top -> enc_speed bus -> CPU telemetry readback",
        "Firmware samples SPEED and REV_COUNT registers every 10ms. Computes angular speed in RPM.",
        "Computed RPM equals simulated 1000 RPM (+/-2%).",
        "Implement Behavioral Motor Stimulus model in SV testbench. Drive enc_a, enc_b, enc_index.",
        "Continuous smooth quadrature stream delivered to DUT.",
        "Quadrature Encoder External Inputs",
        "enc_a, enc_b, enc_index",
        "enc_speed[15:0], enc_dir",
        "enc_top, main_top",
        "External Motor Physical Stimulus Integration",
        "enc_a, enc_b, enc_index pins",
        "SV Behavioral Motor Model + C Speed Calculation",
        "Physical interface conditioning and synchronization"
    )

    add_tc(
        "EXTERNAL_003",
        "External GPIO loopback between output pins and input pins",
        "Connect lower 16 bits of gpio_io (outputs) to upper 16 bits of gpio_io (inputs) via external testbench loopback. Transmit sliding bit patterns.",
        "CP1: TB wires gpio_io[31:16] = gpio_io[15:0]; CP2: CPU writes walking-1s on lower bits; CP3: CPU reads identical pattern on upper bits.",
        "EXTERNAL",
        "VeeR LSU -> GPIO DATA_O[15:0] -> External gpio_io[15:0] -> TB loopback -> External gpio_io[31:16] -> GPIO DATA_I[31:16] -> VeeR LSU",
        "Firmware sets DIR=0x0000FFFF. Walks 1 from bit 0 to bit 15. Verifies bit appears at bits [31:16].",
        "All 16 walking-1 and walking-0 patterns verified through external loopback.",
        "Testbench loopback connection: assign gpio_io[31:16] = gpio_io[15:0]; monitor pin values.",
        "gpio_io[31:16] matches gpio_io[15:0] with 0 propagation delay errors.",
        "GPIO External Pin Loopback",
        "gpio_io[31:16]",
        "gpio_io[15:0]",
        "gpio_wrapper, main_top",
        "External GPIO Pin-to-Pin Loopback",
        "gpio_io external pins",
        "C Walking-Bit Test + SV Pin Loopback",
        "Bidirectional pin driving and input buffer capture"
    )

    add_tc(
        "EXTERNAL_004",
        "External Timer capture strobe generation via timer_capture pin",
        "Drive asynchronous external strobe pulses into timer_capture pin. Verify capture timestamp accuracy against primary clock cycles.",
        "CP1: Asynchronous pulse on timer_capture; CP2: Two-stage synchronizer latches strobe; CP3: Counter latched into CAP register; CP4: Strobe IRQ fires.",
        "EXTERNAL",
        "External timer_capture pin -> timer_core capture synchronizer -> CAP register -> CPU read",
        "Firmware enables capture interrupt, records CAP value for each external event.",
        "Captured values reflect exact elapsed clock cycles between external pulses.",
        "Drive timer_capture pulses at exact cycle intervals (e.g. at T=5000 cycles, T=15000 cycles).",
        "Delta between CAP timestamps matches driven pulse interval.",
        "Timer External Capture Pin",
        "timer_capture",
        "timer_intr",
        "timer_core, main_top",
        "External Pulse Timestamp Capture",
        "timer_capture pin",
        "SV Asynchronous Pulse Generator + C Timestamp Log",
        "Capture input synchronizer and edge detector"
    )

    add_tc(
        "EXTERNAL_005",
        "External PWM waveform monitoring and duty-cycle measurement on PWM_OUT",
        "Sample external PWM_OUT pin at 1GHz resolution. Measure switching frequency, rise/fall edge integrity, and duty-cycle linearity across 0..255 range.",
        "CP1: PWM programmed to duty 0, 64, 128, 192, 255; CP2: External pin measured; CP3: Measured duty cycle matches programmed value with <0.5% error.",
        "EXTERNAL",
        "PWM IP counter & comparator -> External PWM_OUT pin -> Testbench Waveform Analyzer",
        "Firmware sweeps duty cycle in steps of 32 from 0 to 255, pausing 10us at each step.",
        "Duty sweep completes; mailbox confirms pass.",
        "SV verification task analyzes PWM_OUT high/low time, frequency (390.625 kHz at 100MHz / 256), and jitter.",
        "PWM period measured at exactly 2560ns (390.625 kHz); linearity error < 0.2%.",
        "PWM Motor Drive External Pin",
        "None",
        "PWM_OUT",
        "myip_v1_0_S00_AXI, main_top",
        "External PWM Waveform Signal Quality Analysis",
        "PWM_OUT pin",
        "SV High-Resolution Waveform Analyzer + C Duty Sweep",
        "PWM output driver, duty cycle counter linearity"
    )

    # ----------------------------------------------------
    # 20. FULL SYSTEM END-TO-END
    # ----------------------------------------------------
    add_tc(
        "INTEGRATION_001",
        "End-to-end Railway Level-Crossing Barrier Automation Scenario",
        "Full-system demonstration: 1. Train approach simulated via Quadrature Encoder; 2. CPU receives Encoder interrupt; 3. CPU sets PID target to lower barrier; 4. Hybrid loop accelerates motor (PWM duty increases); 5. Encoder speed feedback stabilizes descent; 6. Limit switch GPIO interrupt fires; 7. Motor halts; 8. Status printed to UART; 9. CPU halts in WFI.",
        "CP1: Train detected (Encoder pulses); CP2: CPU wakes, updates PID; CP3: Autonomous loop drives PWM; CP4: GPIO limit switch triggers; CP5: Motor stops (duty=0); CP6: UART logs completion; CP7: CPU enters WFI cleanly.",
        "EXTERNAL",
        "All SoC Subsystems: VeeR CPU + IMEM + DMEM + UART + GPIO + Timer + Encoder + PID + PWM + PIC + Hybrid Feedback Loop",
        "Firmware implements complete supervisory barrier control state machine: IDLE -> LOWERING -> REGULATING -> LATCHED -> REPORTING -> SLEEP.",
        "Complete event sequence executed; final signature 0xCAFE_0011 written to mailbox; UART prints 'TRAIN_PASS_BARRIER_SECURE'.",
        "Drive complete environmental stimulus sequence: encoder pulses -> GPIO limit switch -> UART receive monitor -> PWM monitor.",
        "All 7 checkpoints pass sequentially; simulation terminates normally with code 0.",
        "Full SoC External Interfaces (UART, GPIO, PWM, Encoder, Timer)",
        "enc_a, enc_b, enc_index, gpio_io[0] (limit switch), clk, rst",
        "PWM_OUT, uart_tx, o_cpu_halt_status",
        "soc_top, main_top, u_veer_core, all peripherals",
        "Full-System Autonomous Railway Level-Crossing Automation",
        "Entire SoC Address Map & Hardware Loop",
        "C Complete Application Firmware + SV System Stimulus Scenario",
        "End-to-end full chip integration coverage"
    )

    add_tc(
        "INTEGRATION_002",
        "Full SoC Multi-Peripheral Stress and Stability Verification over 50,000 clock cycles",
        "Continuous long-running stress test: CPU runs compute-intensive benchmark while Timer generates interrupts, UART streams telemetry, Encoder pulses continuously, and DMA writes background buffers.",
        "CP1: 50,000 continuous clock cycles of simultaneous activity; CP2: Zero bus errors; CP3: Zero dropped interrupts; CP4: Zero data corruption; CP5: Clean exit.",
        "EXTERNAL",
        "Full SoC under sustained concurrent load (CPU + 3 AXI Masters + 6 Peripherals)",
        "Firmware runs long-running stress task verifying memory integrity and peripheral status continuously.",
        "50,000 cycles completed with 0 errors; mailbox receives 0x577E_5500.",
        "Testbench drives randomized concurrent stimulus on all external interfaces throughout the 50,000 cycle window.",
        "Zero assertion failures; all protocol monitors pass; normal exit code 0.",
        "All External Interfaces",
        "clk, rst, enc_a, enc_b, uart_rx, gpio_io, s02_axi_*",
        "uart_tx, PWM_OUT, gpio_io, timer_pwm, o_cpu_halt_status",
        "soc_top, main_top, u_veer_core, all peripherals",
        "Full-System Sustained Stress & Long-Term Stability",
        "Full SoC Map",
        "C Stress Benchmark + SV Multi-Agent Randomized Stimulus",
        "Complete chip-level toggle and functional coverage"
    )
