# scripts/test_plan_part3.py
# Categories 9-11: TIMER, UART, ENCODER

def populate_part3(add_tc):
    # ----------------------------------------------------
    # 9. TIMER
    # ----------------------------------------------------
    add_tc(
        "TIMER_001",
        "Timer configuration register CTRL enable and continuous down-counting",
        "Verify that writing CTRL[0]=1 (enable) and CTRL[1]=1 (continuous/repeat) causes the 32-bit counter to decrement on every clock cycle and reload from LOAD.",
        "CP1: LOAD set to 1000; CP2: CTRL set to 0x03; CP3: VAL register counts down 1000, 999... 0; CP4: Upon reaching 0, reloads to 1000.",
        "INTERNAL",
        "VeeR LSU -> Interconnect S3 -> timer_regs CTRL & LOAD -> timer_core 32b downcounter",
        "Firmware configures Timer LOAD=1000, CTRL=0x03. Reads VAL at multiple intervals. Confirms VAL2 < VAL1.",
        "VAL decrements monotonically; reloads to 1000 upon reaching 0.",
        "Monitor u_timer.u_timer_core.counter. Check that counter wraps from 0 to 1000 on continuous mode.",
        "Continuous countdown and reload verified without counter stalling.",
        "None (Internal)",
        "None",
        "None",
        "timer_core, timer_regs",
        "Timer Continuous Down-Counting",
        "0x4003_3000 (CTRL), 0x4003_3004 (LOAD), 0x4003_3008 (VAL)",
        "C Periodic Sampling + SV Counter Flop Monitor",
        "Repeat mode reload multiplexer"
    )

    add_tc(
        "TIMER_002",
        "Timer one-shot mode countdown and halt at zero",
        "Verify that in one-shot mode (CTRL[1]=0), the counter decrements from LOAD to zero and halts permanently at 0 until re-enabled.",
        "CP1: CTRL=0x01 (one-shot); CP2: Counter decrements to 0; CP3: Counter remains 0 for >100 cycles; CP4: Does not reload automatically.",
        "INTERNAL",
        "VeeR LSU -> Interconnect S3 -> timer_regs -> timer_core one-shot halt logic",
        "Firmware sets LOAD=500, CTRL=0x01 (one-shot). Waits 1000 cycles. Reads VAL multiple times.",
        "VAL reads exactly 0 on all subsequent reads.",
        "Assert that when counter reaches 0 with mode==0, counter stays 0 until load_cmd or en toggles.",
        "Counter halts at 0; no spurious reload.",
        "None (Internal)",
        "None",
        "None",
        "timer_core",
        "Timer One-Shot Mode Halt",
        "0x4003_3000 (CTRL)",
        "C Value Polling + SV State Assertion",
        "One-shot zero halt branch"
    )

    add_tc(
        "TIMER_003",
        "Timer prescaler division accuracy (pre_en=1, pre_val=0x000F)",
        "Verify that setting pre_en=1 with pre_val=15 (0x000F) causes the 32-bit counter to decrement once every 16 clock cycles.",
        "CP1: pre_val=15; CP2: Counter decrements by 1 every 16 cycles; CP3: Elapsed cycles for 10 counter ticks is exactly 160 cycles.",
        "INTERNAL",
        "VeeR LSU -> timer_regs PRE -> timer_core prescaler counter -> Timer decrementer",
        "Firmware sets PRE=15, LOAD=100, CTRL=0x05 (enable, repeat, prescaler).",
        "Counter decrements at 1/16th of core frequency.",
        "Measure clock cycles between counter decrement edges in testbench.",
        "Delta cycles between counter decrements equals 16 cycles +/- 0 cycles.",
        "None (Internal)",
        "None",
        "None",
        "timer_core",
        "Timer Prescaler Ratio Precision",
        "0x4003_300C (PRE)",
        "SV Cycle Timing Measurement + C Configuration",
        "Prescaler comparator and reload logic"
    )

    add_tc(
        "TIMER_004",
        "Timer count direction Up mode (dir=1) counting from 0 to load_val",
        "Verify that setting dir=1 in CTRL register causes the counter to count upwards from 0 towards load_val.",
        "CP1: dir=1, LOAD=1000; CP2: Counter increments: 0, 1, 2...; CP3: Upon reaching 1000, wraps to 0.",
        "INTERNAL",
        "VeeR LSU -> timer_regs CTRL[3] -> timer_core up-counter logic",
        "Firmware sets LOAD=1000, CTRL=0x0B (enable, repeat, up). Reads VAL at intervals.",
        "VAL2 > VAL1 confirmed.",
        "Monitor u_timer.u_timer_core.counter incrementing on tick.",
        "Counter increments monotonically; wraps to 0 on reaching load_val.",
        "None (Internal)",
        "None",
        "None",
        "timer_core",
        "Timer Up-Count Direction",
        "0x4003_3000 (CTRL[3])",
        "C Direction Check + SV Flop Monitor",
        "Up-count adder branch"
    )

    add_tc(
        "TIMER_005",
        "Timer PWM generation via compare register CMP matching",
        "Verify that setting pwm_en=1 (CTRL[4]) and programming CMP (0x4003_3018) generates a square wave on the external timer_pwm pin.",
        "CP1: LOAD=1000, CMP=500, pwm_en=1; CP2: timer_pwm is high when counter < CMP, low when counter >= CMP; CP3: Output toggles at external pin.",
        "EXTERNAL",
        "timer_core counter & cmp_val comparator -> timer_pwm pin -> External observation",
        "Firmware configures Timer LOAD=1000, CMP=500, CTRL=0x13 (enable, repeat, pwm_en).",
        "Timer PWM enabled; readback confirms CMP=500.",
        "Monitor external timer_pwm pin. Measure duty cycle and period.",
        "timer_pwm exhibits 50% duty cycle with period of 1000 clock cycles (10.0us).",
        "Timer External Output",
        "None",
        "timer_pwm",
        "timer_core, main_top",
        "Timer PWM Waveform Generation",
        "0x4003_3018 (CMP), timer_pwm pin",
        "SV Frequency/Duty Measurement + C Configuration",
        "PWM compare output logic"
    )

    add_tc(
        "TIMER_006",
        "Timer input capture register CAP latching on external capture pulse",
        "Verify that setting cap_en=1 (CTRL[6]) causes an external pulse on timer_capture pin to latch the current counter value into CAP register (0x4003_301C).",
        "CP1: cap_en=1; CP2: Pulse timer_capture=1 when counter=750; CP3: CAP register latches 750; CP4: capture_stb asserts; CP5: INT_STS[1] asserts.",
        "EXTERNAL",
        "External timer_capture pin -> Edge detector -> CAP register latch & capture_stb -> timer_regs INT_STS[1]",
        "Firmware configures Timer cap_en=1, INT_EN=0x02. Waits for capture interrupt. Reads CAP register.",
        "CAP register contains latched counter value (~750); interrupt serviced.",
        "Pulse timer_capture high for 1 clock cycle at known simulation time. Verify u_timer.capture_val matches counter.",
        "capture_val == counter at posedge timer_capture; capture_stb pulses high for 1 cycle.",
        "Timer External Capture Pin",
        "timer_capture",
        "timer_intr",
        "timer_core, timer_regs",
        "Timer Input Capture on External Pulse",
        "0x4003_301C (CAP), timer_capture pin",
        "SV External Pulse Driver + C CAP Readback",
        "Capture edge detector, CAP latch enable"
    )

    add_tc(
        "TIMER_007",
        "Timer external measurement mode ext_en counting external pulses",
        "Verify that setting ext_en=1 (CTRL[5]) disables internal clock decrementing and decrements the counter only upon rising edges of external timer_ext_meas pin.",
        "CP1: ext_en=1; CP2: Counter holds constant when timer_ext_meas=0; CP3: 5 pulses on timer_ext_meas decrement counter by exactly 5.",
        "EXTERNAL",
        "External timer_ext_meas pin -> Edge detector -> ext_tick -> Counter decrementer",
        "Firmware sets ext_en=1, LOAD=100. Reads VAL before and after external pulse burst.",
        "VAL decreases by exactly the number of external pulses applied (5).",
        "Drive 5 pulses on timer_ext_meas with arbitrary spacing (100ns). Monitor counter.",
        "Counter decrements from 100 -> 99 -> 98 -> 97 -> 96 -> 95.",
        "Timer External Measure Pin",
        "timer_ext_meas",
        "None",
        "timer_core",
        "Timer External Event Counting",
        "0x4003_3000 (CTRL[5]), timer_ext_meas pin",
        "SV Pulse Stimulus + C Counter Readback",
        "ext_meas edge detector, ext_tick gating logic"
    )

    add_tc(
        "TIMER_008",
        "Timer interrupt generation on counter underflow/expire",
        "Verify that when counter reaches 0 with INT_EN[0]=1, timer_intr output asserts to PIC line 3 and sets INT_STS[0].",
        "CP1: INT_EN[0]=1; CP2: Counter transitions 1->0; CP3: INT_STS[0] asserts; CP4: timer_intr asserts high to core.",
        "EXTERNAL",
        "timer_core counter expire -> timer_regs INT_STS[0] -> timer_intr pin -> PIC line 3",
        "Firmware enables timer interrupt, configures mtvec. In ISR, clears INT_STS and increments interrupt counter.",
        "Interrupt counter increments; timer_intr deasserts.",
        "Monitor timer_intr pin at moment counter hits 0. Assert timer_intr goes high.",
        "timer_intr asserts within 1 cycle of counter==0.",
        "Timer External Interrupt Pin",
        "None",
        "timer_intr",
        "timer_core, timer_regs, soc_top",
        "Timer Expire Interrupt Assertion",
        "0x4003_3010 (INT_EN), 0x4003_3014 (INT_STS)",
        "SV Interrupt Pin Monitor + C ISR",
        "Expire IRQ pulse generation, status latch"
    )

    add_tc(
        "TIMER_009",
        "Timer hardware trigger pulse trigger_o output generation on expire",
        "Verify that when the timer counter expires, the external timer_trigger output pulses high for exactly 1 clock cycle to trigger the downstream PID controller.",
        "CP1: Counter expires; CP2: timer_trigger pulses 0->1->0 for 1 cycle; CP3: trigger connects directly to PID tick_i input in main_top.",
        "EXTERNAL",
        "timer_core expire logic -> timer_trigger pin -> main_top u_pid.tick_i",
        "Firmware configures Timer for fast continuous tick (e.g. LOAD=100) to pace PID updates.",
        "PID updates occur synchronously with timer trigger period.",
        "Monitor external timer_trigger pin. Assert pulse width is exactly 1 clock cycle (10.0ns).",
        "timer_trigger asserts for exactly 10.0ns; u_main_top.u_pid.tick_i receives pulse.",
        "Timer Hardware Trigger Pin",
        "None",
        "timer_trigger",
        "timer_core, main_top",
        "Timer Hardware Trigger for PID Synchronization",
        "timer_trigger pin",
        "SV Pulse Width Assertion + C Timer Pacing",
        "trigger_o pulse generation logic"
    )

    # ----------------------------------------------------
    # 10. UART
    # ----------------------------------------------------
    add_tc(
        "UART_001",
        "UART transmission THR write and TX serial character frame generation",
        "Verify that writing an 8-bit character to UART THR (0x4003_5000) generates an RS-232 serial frame on external uart_tx pin (1 start, 8 data, 1 stop bit).",
        "CP1: Write 'U' (0x55) to THR; CP2: uart_tx line goes low (start bit); CP3: 8 data bits transmitted LSB-first; CP4: uart_tx line goes high (stop bit).",
        "EXTERNAL",
        "VeeR LSU -> Interconnect S4 -> axi_uart_top TX FIFO -> uart_transmitter -> External uart_tx pin",
        "Firmware writes 0x55 ('U') to UART THR (0x4003_5000).",
        "Transmission completed; LSR confirms TX FIFO empty.",
        "Sample uart_tx pin. Decode bit timing and payload. Verify payload equals 8'h55.",
        "Decoded UART frame matches 0x55; start bit=0, stop bit=1 verified.",
        "UART External Serial Pins",
        "None",
        "uart_tx",
        "axi_uart_top, uart_transmitter",
        "UART Serial Frame Transmission",
        "0x4003_5000 (THR), uart_tx pin",
        "SV UART Frame Receiver Monitor + C Print Function",
        "Transmitter shift register, baud counter reload"
    )

    add_tc(
        "UART_002",
        "UART TX FIFO status check (LSR bits 5 and 6: THRE and TEMT)",
        "Verify UART Line Status Register (LSR 0x4003_5014) bits: bit 5 (Transmitter FIFO Empty) and bit 6 (Transmitter Empty) flags.",
        "CP1: After reset, THRE=1 and TEMT=1; CP2: Writing character causes THRE=0 and TEMT=0; CP3: When shift register finishes, TEMT=1.",
        "INTERNAL",
        "VeeR LSU -> Interconnect S4 -> axi_uart_top LSR register -> CPU",
        "Firmware polls LSR before and after writing characters. Asserts TEMT asserts once transmission finishes.",
        "LSR bits 5 and 6 behave according to specification; mailbox receives 0x0A87_0002.",
        "Monitor LSR read data at bus during active transmission.",
        "LSR[5]=0 while FIFO has data; LSR[6]=0 while shift register active; both 1 when idle.",
        "None (Internal)",
        "None",
        "None",
        "axi_uart_top, uart_controller",
        "UART Transmitter FIFO Status Flags",
        "0x4003_5014 (LSR)",
        "C Polling Loop + SV Bus Monitor",
        "LSR status multiplexer and FIFO empty flags"
    )

    add_tc(
        "UART_003",
        "UART reception of serial frame on uart_rx and RBR register readback",
        "Verify that driving an external serial frame on uart_rx pin captures the byte into RX FIFO and allows CPU to read it from RBR (0x4003_5000).",
        "CP1: Testbench drives serial frame 'K' (0x4B) on uart_rx; CP2: uart_receiver samples bits at mid-bit intervals; CP3: Byte pushed to RX FIFO; CP4: CPU reads 0x4B from RBR.",
        "EXTERNAL",
        "External uart_rx pin -> uart_receiver -> RX FIFO -> axi_uart_top RBR -> Interconnect S4 -> VeeR LSU",
        "Firmware polls LSR bit 0 (Data Ready). When ready, reads RBR (0x4003_5000) and asserts equality to 0x4B.",
        "Read byte equals 0x4B; mailbox receives 0x0A87_0003.",
        "Drive uart_rx pin with 115200 baud serial frame containing 0x4B.",
        "axi_uart_top pushes 0x4B to rx_fifo; data_ready asserts; RDATA returns 0x4B.",
        "UART External Serial Pins",
        "uart_rx",
        "None",
        "axi_uart_top, uart_receiver, axi_internal_fifo",
        "UART Serial Frame Reception",
        "0x4003_5000 (RBR), uart_rx pin",
        "SV Serial Frame Transmitter + C Receiver Read",
        "Receiver oversampling FSM, RX FIFO push"
    )

    add_tc(
        "UART_004",
        "UART RX data ready status bit (LSR bit 0) assertion and auto-clear on read",
        "Verify that LSR bit 0 (Data Ready) asserts when a character is available in the RX FIFO, and automatically clears when RBR is read.",
        "CP1: RX FIFO empty: LSR[0]=0; CP2: Byte received: LSR[0]=1; CP3: CPU reads RBR: LSR[0]=0.",
        "INTERNAL",
        "axi_uart_top RX FIFO empty flag -> LSR[0] -> Read acknowledge pop -> LSR[0] clear",
        "Firmware checks LSR[0]==0 initially; waits for LSR[0]==1; reads RBR; asserts LSR[0]==0.",
        "LSR[0] transitions 0 -> 1 -> 0 cleanly.",
        "Monitor u_axi_uart_top.rx_fifo_empty_int. Assert LSR[0] == ~rx_fifo_empty_int.",
        "LSR[0] assertion and deassertion cycle-accurate match verified.",
        "None (Internal)",
        "None",
        "None",
        "axi_uart_top, uart_controller",
        "UART RX Data Ready Flag Auto-Clear",
        "0x4003_5014 (LSR bit 0)",
        "C Polling Sequence + SV Internal FIFO Monitor",
        "RX FIFO pop-on-read logic"
    )

    add_tc(
        "UART_005",
        "UART RX interrupt generation (IER bit 0, uart_irq to PIC line 1)",
        "Verify that enabling IER[0]=1 causes reception of a character on uart_rx to assert the external uart_irq pin to PIC line 1.",
        "CP1: IER set to 0x01; CP2: Byte arrives on uart_rx; CP3: read_interrupt_o / uart_irq asserts; CP4: CPU vectors to UART ISR.",
        "EXTERNAL",
        "External uart_rx pin -> uart_receiver -> RX FIFO non-empty -> read_interrupt_o -> uart_irq pin -> PIC line 1",
        "Firmware enables UART interrupt in IER, registers ISR. When ISR executes, reads RBR and increments received packet counter.",
        "ISR executes; received character processed; uart_irq deasserts.",
        "Drive serial frame on uart_rx. Assert uart_irq goes high when stop bit is validated.",
        "uart_irq asserts; u_soc_top.core_extintsrc_req[1] == 1'b1.",
        "UART External Pins & Interrupt",
        "uart_rx",
        "uart_irq",
        "axi_uart_top, soc_top",
        "UART Receive Interrupt Generation",
        "0x4003_5004 (IER), uart_irq pin",
        "SV Serial Frame Stimulus + C UART ISR",
        "Interrupt enable AND gate, interrupt output driver"
    )

    add_tc(
        "UART_006",
        "UART programmable baud rate divisor register configuration",
        "Verify that writing custom baud divisor values to UART_BAUD_DIVISOR (0x4003_5008) alters the bit transmission duration on uart_tx.",
        "CP1: Divisor set to 434 (115200 baud at 50MHz); CP2: Bit duration is 8.68us; CP3: Divisor changed to 217; CP4: Bit duration is 4.34us.",
        "EXTERNAL",
        "VeeR LSU -> axi_uart_top baud divisor register -> Baud rate generator counter -> uart_tx bit duration",
        "Firmware writes 434 then 217 to BAUD_DIVISOR (0x4003_5008). Transmits test characters.",
        "Characters transmitted at both baud rates.",
        "Measure width of start bit on uart_tx at divisor 434 vs divisor 217 in testbench.",
        "Start bit width measured: 8.68us (+/-1%) at div 434; 4.34us (+/-1%) at div 217.",
        "UART External Serial Output",
        "None",
        "uart_tx",
        "axi_uart_top, uart_controller",
        "UART Baud Rate Divisor Scaling",
        "0x4003_5008 (BAUD_DIVISOR), uart_tx pin",
        "SV Pulse Width Timing Monitor + C Divisor Config",
        "Baud generator prescaler reload logic"
    )

    add_tc(
        "UART_007",
        "UART Line Control Register (LCR) parity configuration (even/odd/none)",
        "Verify Line Control Register (LCR 0x4003_500C) parity modes: odd parity (LCR[3]=1, LCR[4]=0) and even parity (LCR[3]=1, LCR[4]=1).",
        "CP1: Odd parity enabled: parity bit makes total 1s odd; CP2: Even parity enabled: parity bit makes total 1s even; CP3: Parity bit present on uart_tx frame.",
        "EXTERNAL",
        "VeeR LSU -> axi_uart_top LCR -> uart_parity_bit_compute -> uart_transmitter -> uart_tx pin",
        "Firmware configures LCR for even parity, transmits 0x55 (4 ones, parity bit should be 0).",
        "Readback confirms LCR parity bits programmed.",
        "Decode 11-bit UART frame on uart_tx pin. Check parity bit polarity.",
        "Parity bit verified: 0 for 0x55 with even parity; 1 for 0x55 with odd parity.",
        "UART External Serial Output",
        "None",
        "uart_tx",
        "axi_uart_top, uart_parity_bit_compute",
        "UART Parity Computation and Framing",
        "0x4003_500C (LCR), uart_tx pin",
        "SV 11-Bit Frame Decoder + C Parity Config",
        "Parity calculation XOR tree, framer state machine"
    )

    # ----------------------------------------------------
    # 11. QUADRATURE ENCODER
    # ----------------------------------------------------
    add_tc(
        "ENCODER_001",
        "Forward quadrature decoding (A leads B) incrementing position COUNT",
        "Drive quadrature sequence 00 -> 01 -> 11 -> 10 -> 00 on external enc_a and enc_b pins. Verify COUNT register (0x4003_D000) increments by 1 per cycle.",
        "CP1: Forward quadrature sequence applied; CP2: enc_dir asserts high (forward); CP3: COUNT increments from 0 to 100 over 100 cycles; CP4: STATUS[DIR]=1.",
        "EXTERNAL",
        "External enc_a, enc_b pins -> enc_input_cond -> enc_quad_dec -> enc_core 32b COUNT -> enc_axi_slave -> VeeR LSU",
        "Firmware reads COUNT before and after stimulus. Asserts final COUNT == 100, STATUS bit 1 == 1.",
        "COUNT reads 100; mailbox receives 0x0E4C_0001.",
        "Drive 100 quadrature forward cycles on enc_a and enc_b (period 1us). Monitor enc_dir and enc_count_valid.",
        "enc_dir == 1; enc_count_valid pulses 100 times; u_encoder.count_reg == 100.",
        "Quadrature Encoder External Inputs",
        "enc_a, enc_b",
        "enc_dir, enc_count_valid",
        "enc_top, enc_quad_dec, enc_core",
        "Forward Quadrature Position Decoding",
        "0x4003_D000 (COUNT), enc_a/enc_b pins",
        "SV Quadrature Waveform Generator + C COUNT Read",
        "Forward state transition table in enc_quad_dec"
    )

    add_tc(
        "ENCODER_002",
        "Reverse quadrature decoding (B leads A) decrementing position COUNT",
        "Drive quadrature sequence 00 -> 10 -> 11 -> 01 -> 00 on enc_a and enc_b pins. Verify COUNT register decrements by 1 per cycle.",
        "CP1: Reverse quadrature sequence applied; CP2: enc_dir goes low (reverse); CP3: COUNT decrements from 0 to -100 (0xFFFFFF9C); CP4: STATUS[DIR]=0.",
        "EXTERNAL",
        "External enc_a, enc_b pins -> enc_quad_dec -> enc_core signed decrement -> enc_axi_slave -> VeeR LSU",
        "Firmware reads COUNT before and after stimulus. Asserts COUNT == -100 (signed int32).",
        "COUNT reads -100 (0xFFFFFF9C); mailbox receives 0x0E4C_0002.",
        "Drive 100 quadrature reverse cycles on enc_a and enc_b. Monitor enc_dir and count register.",
        "enc_dir == 0; count_reg decrements monotonically to -100.",
        "Quadrature Encoder External Inputs",
        "enc_a, enc_b",
        "enc_dir, enc_count_valid",
        "enc_top, enc_quad_dec, enc_core",
        "Reverse Quadrature Position Decoding",
        "0x4003_D000 (COUNT), enc_a/enc_b pins",
        "SV Reverse Quadrature Generator + C COUNT Read",
        "Reverse state transition table in enc_quad_dec"
    )

    add_tc(
        "ENCODER_003",
        "Quadrature stationary state with no count drift",
        "Hold enc_a and enc_b at steady state (e.g. 00, 01, 11, or 10) for 10,000 clock cycles. Verify COUNT register remains completely unchanged.",
        "CP1: enc_a=1, enc_b=0 static; CP2: 10,000 clock cycles elapse; CP3: COUNT does not increment or decrement; CP4: Speed decays to 0.",
        "EXTERNAL",
        "External enc_a, enc_b static levels -> enc_quad_dec idle -> enc_core hold",
        "Firmware samples COUNT at start and after delay loop. Asserts COUNT_initial == COUNT_final.",
        "COUNT_initial == COUNT_final.",
        "Hold enc_a=1, enc_b=0 for 100us. Check enc_count_valid never asserts.",
        "enc_count_valid == 0 throughout stationary period; zero spurious counts.",
        "Quadrature Encoder External Inputs",
        "enc_a, enc_b",
        "enc_count_valid, enc_speed",
        "enc_quad_dec, enc_core",
        "Stationary State Zero-Drift Robustness",
        "0x4003_D000 (COUNT)",
        "SV Static Signal Hold + C Drift Monitor",
        "No-change state transitions (00->00, 11->11)"
    )

    add_tc(
        "ENCODER_004",
        "Illegal quadrature transition detection, STATUS[ILLEGAL] and enc_fault",
        "Drive invalid simultaneous two-bit transition (00 -> 11 or 01 -> 10) on enc_a and enc_b. Verify STATUS bit 3 (ILLEGAL) asserts and external enc_fault pin goes high.",
        "CP1: enc_a and enc_b toggle simultaneously (00->11); CP2: enc_quad_dec detects illegal code; CP3: enc_fault pin asserts high; CP4: STATUS[3] sets.",
        "EXTERNAL",
        "External enc_a, enc_b invalid transition -> enc_quad_dec illegal detector -> enc_fault pin & STATUS[3] -> enc_intr",
        "Firmware polls STATUS (0x4003_D00C) after illegal transition; asserts bit 3 is set; writes 1 to clear bit 3.",
        "STATUS bit 3 reads 1; clears to 0 upon W1C write.",
        "Force enc_a=1 and enc_b=1 in the same simulation step from 00. Monitor external enc_fault pin.",
        "enc_fault asserts high within 2 clock cycles; STATUS[3] latches high.",
        "Quadrature Encoder External Pins",
        "enc_a, enc_b",
        "enc_fault, enc_intr",
        "enc_quad_dec, enc_axi_slave",
        "Illegal Quadrature Code Fault Detection",
        "0x4003_D00C (STATUS bit 3), enc_fault pin",
        "SV Invalid Transition Stimulus + C Fault Polling",
        "Illegal transition case branch in decode table"
    )

    add_tc(
        "ENCODER_005",
        "Speed calculation over measurement WINDOW register",
        "Program WINDOW (0x4003_D010) to 10,000 clock cycles. Drive 50 quadrature pulses within window. Verify SPEED register (0x4003_D004) computes proportional speed.",
        "CP1: WINDOW set to 10,000; CP2: 50 pulses applied; CP3: Window expires; CP4: SPEED updates with filtered velocity; CP5: enc_speed_valid asserts.",
        "EXTERNAL",
        "enc_a, enc_b pulses -> enc_speed_calc delta count over window -> SPEED register -> enc_speed bus -> PID actual input",
        "Firmware configures WINDOW=10000, SCALE=0x00010000 (1.0 in Q16.16). Reads SPEED register.",
        "SPEED register reflects non-zero measured velocity proportional to pulse rate.",
        "Monitor external enc_speed and enc_speed_valid pins.",
        "enc_speed_valid pulses high on window boundary; enc_speed reflects delta count.",
        "Quadrature Encoder External Pins & Bus",
        "enc_a, enc_b",
        "enc_speed[15:0], enc_speed_valid",
        "enc_speed_calc, enc_core",
        "Velocity Measurement Over Window",
        "0x4003_D004 (SPEED), 0x4003_D010 (WINDOW)",
        "SV Rate-Controlled Generator + C Speed Read",
        "Window accumulator, Q16.16 speed scaling unit"
    )

    add_tc(
        "ENCODER_006",
        "Revolution counter REV_COUNT increment on enc_index pulse",
        "Pulse external enc_index pin while encoder is rotating forward. Verify REV_COUNT register (0x4003_D020) increments by 1.",
        "CP1: enc_index pulses high for 1 cycle; CP2: REV_COUNT increments from 0 to 1; CP3: Reverse rotation decrements REV_COUNT.",
        "EXTERNAL",
        "External enc_index pin -> enc_input_cond -> REV_COUNT incrementer -> enc_axi_slave",
        "Firmware reads REV_COUNT (0x4003_D020) before and after index pulses.",
        "REV_COUNT increments from 0 to 1.",
        "Drive enc_index=1 for 20ns during forward motion. Verify rev_count_reg updates.",
        "rev_count_reg increments to 1; STATUS[5] (INDEX_SEEN) sets.",
        "Quadrature Encoder External Index Pin",
        "enc_index",
        "None",
        "enc_core, enc_axi_slave",
        "Revolution Counter Index Latching",
        "0x4003_D020 (REV_COUNT), enc_index pin",
        "SV Index Pulse Driver + C Revolution Readback",
        "Index edge detector, rev counter increment/decrement"
    )

    add_tc(
        "ENCODER_007",
        "Index position capture register INDEX_POS latching",
        "Verify that asserting enc_index latches the current 32-bit position COUNT into the INDEX_POS register (0x4003_D024).",
        "CP1: COUNT reaches 500; CP2: enc_index pulsed; CP3: INDEX_POS latches 500; CP4: INDEX_POS remains 500 as COUNT continues advancing.",
        "EXTERNAL",
        "External enc_index pin -> INDEX_POS capture register -> enc_axi_slave -> CPU",
        "Firmware reads INDEX_POS after index pulse. Verifies INDEX_POS == captured count.",
        "INDEX_POS reads 500; mailbox receives 0x0E4C_0007.",
        "Pulse enc_index when u_encoder.count_reg == 500. Check u_encoder.index_pos_reg.",
        "index_pos_reg == 500.",
        "Quadrature Encoder External Index Pin",
        "enc_index",
        "None",
        "enc_core",
        "Index Position Timestamp Latching",
        "0x4003_D024 (INDEX_POS), enc_index pin",
        "SV Timed Index Driver + C Position Verification",
        "Index capture register clock-enable"
    )

    add_tc(
        "ENCODER_008",
        "Stall timeout counter STALL_TMO assertion when motion stops",
        "Program STALL_TMO (0x4003_D01C) to 5,000 cycles. Stop encoder pulses. Verify that after 5,000 idle cycles, STATUS bit 4 (STALL) asserts.",
        "CP1: STALL_TMO set to 5000; CP2: Pulses stop; CP3: 5000 cycles elapse; CP4: STATUS[4] (STALL) sets; CP5: SPEED decays to 0.",
        "EXTERNAL",
        "Timer counter in enc_speed_calc -> Stall timeout comparator -> STATUS[4] flag",
        "Firmware sets STALL_TMO=5000. Waits 10,000 cycles without pulses. Reads STATUS and SPEED.",
        "STATUS bit 4 reads 1; SPEED reads 0.",
        "Stop enc_a/enc_b driving. Measure clock cycles until STATUS[4] asserts.",
        "STATUS[4] asserts exactly 5,000 cycles after last quadrature edge.",
        "Quadrature Encoder External Inputs",
        "enc_a, enc_b",
        "enc_speed[15:0]",
        "enc_speed_calc, enc_axi_slave",
        "Encoder Motion Stall Timeout Detection",
        "0x4003_D01C (STALL_TMO), 0x4003_D00C (STATUS)",
        "SV Motion Cessation Stimulus + C Stall Check",
        "Stall timer counter and threshold comparison"
    )

    add_tc(
        "ENCODER_009",
        "Glitch filter FILTER register suppressing sub-threshold noise",
        "Program FILTER (0x4003_D014) to 4 cycles. Inject narrow 10ns glitches (<4 cycles) on enc_a and enc_b. Verify glitches are completely rejected and COUNT does not advance.",
        "CP1: FILTER set to 4; CP2: Noise pulses of width 1-3 cycles injected; CP3: Noise filtered by enc_input_cond; CP4: COUNT remains 0.",
        "EXTERNAL",
        "External noisy enc_a, enc_b pins -> enc_input_cond majority/integrating filter -> Filtered clean signals -> Decoder",
        "Firmware sets FILTER=4. Polls COUNT after testbench noise burst. Asserts COUNT==0.",
        "COUNT reads 0; zero noise-induced counts.",
        "Drive high-frequency noise spikes (1 cycle width) on enc_a. Monitor filtered signal internal to DUT.",
        "Filtered signal remains 0; noise rejected.",
        "Quadrature Encoder External Inputs",
        "enc_a, enc_b",
        "None",
        "enc_input_cond",
        "Input Glitch Filter Noise Immunity",
        "0x4003_D014 (FILTER), enc_a/enc_b pins",
        "SV Narrow Glitch Generator + C Count Readback",
        "Glitch counter filter shift registers"
    )

    add_tc(
        "ENCODER_010",
        "Encoder interrupt generation on fault and index events (IRQ_EN)",
        "Verify that enabling IRQ_EN (0x4003_D02C) generates enc_intr on illegal transition or index detection, routing to PIC line 4.",
        "CP1: IRQ_EN set to enable illegal and index interrupts; CP2: Fault injected; CP3: enc_intr pin asserts; CP4: CPU vectors to Encoder ISR.",
        "EXTERNAL",
        "enc_core fault/index event -> IRQ_EN mask -> enc_intr pin -> PIC line 4 -> VeeR CPU",
        "Firmware configures Encoder IRQ_EN=0x28 (index + illegal). Registers ISR. Waits for interrupt flag.",
        "ISR sets flag; reads STATUS; clears interrupt; returns.",
        "Inject illegal transition on enc_a/enc_b. Verify external enc_intr pin goes high.",
        "enc_intr asserts high; u_soc_top.core_extintsrc_req[4] == 1'b1.",
        "Encoder External Pins & Interrupt",
        "enc_a, enc_b",
        "enc_intr",
        "enc_axi_slave, soc_top",
        "Encoder Interrupt Routing to PIC",
        "0x4003_D02C (IRQ_EN), enc_intr pin",
        "SV Fault Stimulus + C Encoder ISR",
        "Interrupt mask logic, enc_intr output driver"
    )

    add_tc(
        "ENCODER_011",
        "Encoder AXI slave write-1-to-clear status bit arbitration",
        "Verify STATUS register W1C arbitration: when software writes 1 to clear a status bit at the exact same cycle a new hardware event arrives, the new event wins.",
        "CP1: STATUS[5] (INDEX_SEEN) is 1; CP2: Software writes 1 to clear STATUS[5]; CP3: enc_index pulses in the same cycle; CP4: STATUS[5] remains 1.",
        "EXTERNAL",
        "VeeR LSU write commit & Hardware index pulse -> enc_axi_slave W1C arbitration logic",
        "Firmware attempts to clear STATUS[5] while index pulses continue.",
        "Hardware event precedence verified; status retains 1.",
        "Coordinate AXI write to STATUS with posedge enc_index in testbench.",
        "STATUS[5] remains 1'b1 (new hardware event wins simultaneous clear).",
        "Encoder External Index Pin",
        "enc_index",
        "None",
        "enc_axi_slave",
        "W1C Status Simultaneous Hardware-Event Arbitration",
        "0x4003_D00C (STATUS)",
        "SV Cycle-Accurate Concurrent Drive + C W1C Clear",
        "Simultaneous W1C clear and hardware set priority"
    )
