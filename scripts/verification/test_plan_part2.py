# scripts/test_plan_part2.py
# Categories 6-8: AXI, INTERCONNECT, GPIO

def populate_part2(add_tc):
    # ----------------------------------------------------
    # 6. AXI WIDTH DOWNCONVERTERS
    # ----------------------------------------------------
    add_tc(
        "AXI_001",
        "IFU 64-bit to 32-bit downconverter dual-beat sequential read (arsize=3)",
        "Verify translation of 64-bit IFU read (arsize=3) into two sequential 32-bit single-beat reads (arsize=2) at word0 (addr[2]=0) and word1 (addr[2]=1).",
        "CP1: Slave arsize=3; CP2: Master issues beat 0 with addr[2]=0, arsize=2; CP3: Master issues beat 1 with addr[2]=1, arsize=2; CP4: Slave receives combined 64-bit rdata.",
        "INTERNAL",
        "VeeR IFU -> axi_width_downconverter_ifu (S_AR_WORD0 -> S_R_WORD0 -> S_AR_WORD1 -> S_R_WORD1) -> Interconnect S0 -> IMEM -> IFU",
        "Firmware executes code aligned on 8-byte boundaries.",
        "Normal program flow; instructions in both 32-bit halves executed.",
        "Monitor u_ifu_downconverter slave and master ports. Assert beat 0 address matches {req_addr[31:3], 3'b000} and beat 1 matches {req_addr[31:3], 3'b100}.",
        "Beat 0 and Beat 1 addresses and data combined into s_axi_rdata == {data_high, data_low}; s_axi_rlast asserts.",
        "None (Internal)",
        "None",
        "None",
        "axi_width_downconverter_ifu",
        "IFU 64b to 32b Downconversion",
        "0x4000_0000 (IMEM)",
        "SV Cycle-Accurate Assertion + C Normal Execution",
        "FSM dual-word states, beat address generation"
    )

    add_tc(
        "AXI_002",
        "IFU 64-bit to 32-bit downconverter single-beat read (arsize=2)",
        "Verify single-beat 32-bit or sub-word read path (arsize <= 2) in axi_width_downconverter_ifu traversing S_AR_SINGLE and S_R_SINGLE.",
        "CP1: Slave arsize=2; CP2: FSM enters S_AR_SINGLE; CP3: Single 32-bit read issued to interconnect; CP4: Data replicated across both 32-bit halves of 64-bit bus.",
        "INTERNAL",
        "VeeR IFU -> axi_width_downconverter_ifu (S_AR_SINGLE -> S_R_SINGLE) -> Interconnect S0 -> IMEM -> IFU",
        "Firmware executes 16-bit compressed instruction sequence that triggers 32-bit sub-word fetch.",
        "Compressed instructions decode and execute without alignment fault.",
        "Monitor u_ifu_downconverter state machine and assert s_axi_rdata == {m_axi_rdata, m_axi_rdata}.",
        "State enters S_AR_SINGLE; single read completes; s_axi_rdata replication verified.",
        "None (Internal)",
        "None",
        "None",
        "axi_width_downconverter_ifu",
        "IFU Sub-Word Fetch Downconversion",
        "0x4000_0000",
        "SV State Assertion + C Compressed Instruction Flow",
        "S_AR_SINGLE, S_R_SINGLE states"
    )

    add_tc(
        "AXI_003",
        "LSU 64-bit to 32-bit downconverter single write to lower word (addr[2]=0)",
        "Verify 32-bit write where only lower write strobes are active (wstrb[7:4]==0, wstrb[3:0]!=0). Downconverter must issue a single 32-bit write to word0.",
        "CP1: w_req_strb[7:4]==0; CP2: FSM enters W_ISSUE_SINGLE; CP3: m_axi_awaddr has addr[2]=0; CP4: Single bresp accepted and returned to core.",
        "INTERNAL",
        "VeeR LSU -> axi_width_downconverter_lsu (W_ISSUE_SINGLE) -> Interconnect -> DMEM/MMIO -> Return BRESP",
        "Firmware writes 32-bit word to an address with addr[2]=0 (e.g. 0x4002_0100).",
        "Target memory receives write data; readback matches.",
        "Monitor u_lsu_downconverter.w_state. Assert W_ISSUE_SINGLE traversed; m_axi_awaddr[2] == 1'b0; m_axi_wstrb == w_req_strb[3:0].",
        "w_is_dual == 0; exactly one AW and W beat issued on master port.",
        "None (Internal)",
        "None",
        "None",
        "axi_width_downconverter_lsu",
        "LSU Lower-Word Single Write",
        "0x4002_0100 (addr[2]=0)",
        "C 32-bit Store + SV FSM State Assertion",
        "W_ISSUE_SINGLE lower strobe path"
    )

    add_tc(
        "AXI_004",
        "LSU 64-bit to 32-bit downconverter single write to upper word (addr[2]=1)",
        "Verify 32-bit write where only upper write strobes are active (wstrb[3:0]==0, wstrb[7:4]!=0). Downconverter must issue a single 32-bit write to word1.",
        "CP1: w_req_strb[3:0]==0; CP2: FSM enters W_ISSUE_SINGLE; CP3: m_axi_awaddr has addr[2]=1; CP4: m_axi_wdata contains w_req_data[63:32].",
        "INTERNAL",
        "VeeR LSU -> axi_width_downconverter_lsu (W_ISSUE_SINGLE upper) -> Interconnect -> DMEM/MMIO -> Return BRESP",
        "Firmware writes 32-bit word to an address with addr[2]=1 (e.g. 0x4002_0104).",
        "Target memory receives write data; readback matches.",
        "Monitor u_lsu_downconverter.m_axi_awaddr[2]. Assert it equals 1'b1; m_axi_wstrb == w_req_strb[7:4].",
        "m_axi_awaddr[2] == 1'b1; m_axi_wdata == w_req_data[63:32]; bresp returned cleanly.",
        "None (Internal)",
        "None",
        "None",
        "axi_width_downconverter_lsu",
        "LSU Upper-Word Single Write",
        "0x4002_0104 (addr[2]=1)",
        "C 32-bit Store + SV FSM State Assertion",
        "W_ISSUE_SINGLE upper strobe path"
    )

    add_tc(
        "AXI_005",
        "LSU 64-bit to 32-bit downconverter dual-word 64-bit write (wstrb[7:0]=0xFF)",
        "Verify full 64-bit write where both lower and upper strobes are active. Downconverter must issue two sequential 32-bit writes and combine bresp.",
        "CP1: wstrb=0xFF; CP2: FSM enters W_DUAL_W0; CP3: Word 0 written at addr[2]=0; CP4: Word 1 written at addr[2]=1; CP5: Combined bresp returned.",
        "INTERNAL",
        "VeeR LSU -> axi_width_downconverter_lsu (W_DUAL_W0 -> W_DUAL_W1) -> Interconnect S1 -> 2x DMEM writes -> Combined BRESP",
        "Firmware executes double-word store (sd) or block memory copy (memcpy 64-bit aligned).",
        "Both 32-bit words updated in DMEM; 64-bit readback matches written pattern.",
        "Monitor u_lsu_downconverter.w_state traversing W_DUAL_W0 then W_DUAL_W1. Verify bresp = w_bresp0 | w_bresp1.",
        "w_is_dual == 1; both beats complete; s_axi_bvalid asserts after beat 1.",
        "None (Internal)",
        "None",
        "None",
        "axi_width_downconverter_lsu",
        "LSU Dual-Word 64b Write",
        "0x4002_0180 (64-bit aligned)",
        "C 64-bit Store + SV FSM Transition Monitor",
        "W_DUAL_W0 and W_DUAL_W1 state sequencing"
    )

    add_tc(
        "AXI_006",
        "LSU 64-bit to 32-bit downconverter dual-beat 64-bit read (arsize=3)",
        "Verify 64-bit load where LSU requests 8 bytes (arsize=3). Downconverter executes two sequential 32-bit reads and merges data into 64-bit response.",
        "CP1: arsize=3; CP2: FSM traverses R_AR_WORD0 -> R_WAIT_WORD0 -> R_AR_WORD1 -> R_WAIT_WORD1 -> R_RSP_DUAL; CP3: Combined 64-bit data returned.",
        "INTERNAL",
        "VeeR LSU -> axi_width_downconverter_lsu read FSM -> Interconnect S1 -> 2x DMEM reads -> Merged 64b RDATA -> LSU",
        "Firmware executes 64-bit load instruction (ld or 64-bit structure read).",
        "Correct 64-bit data received in destination register pair.",
        "Assert that u_lsu_downconverter.s_axi_rdata == {r_data_high, r_data_low} and s_axi_rlast == 1'b1.",
        "s_axi_rdata contains both 32-bit words; rresp reflects OR of both read responses.",
        "None (Internal)",
        "None",
        "None",
        "axi_width_downconverter_lsu",
        "LSU Dual-Beat 64b Read",
        "0x4002_0180",
        "C 64-bit Load + SV Data Merge Assertion",
        "R_AR_WORD0, R_AR_WORD1 dual-beat read states"
    )

    add_tc(
        "AXI_007",
        "LSU downconverter read data replication across high/low words for 32-bit reads",
        "Verify that for all 32-bit and sub-word reads (arsize <= 2), the LSU downconverter replicates the 32-bit read data across both halves {data, data}.",
        "CP1: arsize=2; CP2: Downconverter traverses R_AR_SINGLE -> R_WAIT_SINGLE; CP3: s_axi_rdata = {m_axi_rdata, m_axi_rdata}; CP4: Core receives data regardless of internal alignment.",
        "INTERNAL",
        "VeeR LSU -> axi_width_downconverter_lsu (R_AR_SINGLE) -> Interconnect -> DMEM/MMIO -> Replication mux -> Core LSU",
        "Firmware performs 32-bit load from MMIO register (e.g. GPIO DATA_O 0x4003_1004).",
        "Correct 32-bit value loaded into target register.",
        "Assert that u_lsu_downconverter.s_axi_rdata[63:32] == u_lsu_downconverter.s_axi_rdata[31:0].",
        "s_axi_rdata upper and lower words are identical ({rdata, rdata}); s_axi_rlast asserts.",
        "None (Internal)",
        "None",
        "None",
        "axi_width_downconverter_lsu",
        "LSU Read Data Word Replication",
        "0x4003_1004 (MMIO)",
        "C MMIO Read + SV Word Duplication Assertion",
        "R_WAIT_SINGLE data replication logic"
    )

    add_tc(
        "AXI_008",
        "AXI write response channel buffering and backpressure handling (BVALID/BREADY)",
        "Verify that when the CPU LSU or interconnect delays BREADY, BVALID and BRESP remain stably asserted until accepted, with no dropped responses.",
        "CP1: BVALID asserted by downconverter; CP2: BREADY held low for 5 cycles; CP3: BVALID, BID, and BRESP remain completely stable; CP4: Deasserts 1 cycle after BREADY.",
        "INTERNAL",
        "VeeR LSU -> LSU downconverter W_RSP state -> B Channel Handshake",
        "Firmware performs back-to-back writes to DMEM.",
        "All writes complete successfully without CPU stall.",
        "Testbench injects artificial backpressure on s_axi_bready (delay 50ns). Verify s_axi_bvalid remains high.",
        "No protocol violation: BVALID does not drop early; BRESP preserved.",
        "None (Internal)",
        "None",
        "None",
        "axi_width_downconverter_lsu",
        "AXI Write Response Backpressure",
        "0x4002_0000",
        "SV Handshake Stall Injection + C Burst Writes",
        "W_RSP handshake stability logic"
    )

    add_tc(
        "AXI_009",
        "AXI read response channel buffering and backpressure handling (RVALID/RREADY)",
        "Verify that when RREADY is held low, RVALID, RDATA, and RRESP remain stably asserted until RREADY is asserted.",
        "CP1: RVALID asserted by memory controller or downconverter; CP2: RREADY delayed; CP3: RDATA held completely stable; CP4: Deasserts cleanly on handshake.",
        "INTERNAL",
        "IMEM / DMEM axi_sram_ctrl -> R Channel Handshake -> Downconverter / CPU",
        "Firmware executes instruction fetch loop.",
        "Execution continues normally once backpressure releases.",
        "Inject backpressure on m_axi_rready in testbench. Measure stability of m_axi_rdata and m_axi_rresp.",
        "Data stability check passes: zero bit changes while RVALID=1 and RREADY=0.",
        "None (Internal)",
        "None",
        "None",
        "axi_sram_ctrl, axi_width_downconverter_ifu",
        "AXI Read Response Backpressure",
        "0x4000_0000",
        "SV Handshake Stall Injection + C Execution",
        "Read channel handshake hold logic"
    )

    add_tc(
        "AXI_010",
        "Regression check: LSU sub-word access without triggering spurious NMI/trap-to-0",
        "Exhaustively verify that all sub-word access patterns (lb, lbu, sb, lh, lhu, sh) at byte offsets 0, 1, 2, 3 do not trigger spurious traps or jumps to 0x0000_0000.",
        "CP1: 100 consecutive randomized byte and halfword accesses; CP2: Zero traps to address 0; CP3: Zero NMI assertions; CP4: All data readbacks match expected byte slices.",
        "INTERNAL",
        "VeeR LSU -> LSU width downconverter -> Interconnect S1 -> DMEM -> CPU LSU",
        "Firmware executes test_lsu_alignment_regression() sweeping all 16 byte/halfword read/write combinations.",
        "All 16 combinations pass; signature 0x1500_000A written to mailbox.",
        "Continuous SV assertion: assert property (@(posedge clk) trace_rv_i_address_ip != 32'h0);",
        "Assertion passes with 0 failures over 50,000 cycles.",
        "None (Internal)",
        "None",
        "None",
        "axi_width_downconverter_lsu, u_veer_core",
        "Phase 4 LSU Alignment Regression Closure",
        "0x4002_0300 - 0x4002_0340",
        "C Exhaustive Sub-Word Suite + SV Zero-Trap Assertion",
        "Complete sub-word read/write path coverage"
    )

    # ----------------------------------------------------
    # 7. AXI INTERCONNECT
    # ----------------------------------------------------
    add_tc(
        "INTERCONNECT_001",
        "Master M0 (IFU) address decode to S0 (IMEM 0x4000_0000)",
        "Verify that AXI interconnect correctly decodes Master M0 addresses in range 0x4000_0000 - 0x4000_FFFF and routes read transactions to Slave S0.",
        "CP1: M0 araddr in 0x4000_xxxx; CP2: Interconnect asserts m00_axi_arvalid; CP3: S0 acknowledges; CP4: Read data routed back to M0.",
        "INTERNAL",
        "Master M0 -> axi_interconnect S0 decoder -> m00_axi (S0 IMEM) -> Read return",
        "Firmware fetches instructions from IMEM.",
        "Code executes normally from 0x4000_0000.",
        "Monitor u_main_top.u_axi_interconnect_3x15.m00_axi_arvalid when M0 issues araddr=0x4000_0000.",
        "m00_axi_arvalid asserts; m01..m14 remain deasserted.",
        "None (Internal)",
        "None",
        "None",
        "axi_interconnect, main_top",
        "Interconnect M0 -> S0 Decode",
        "0x4000_0000 - 0x4000_FFFF",
        "SV Interconnect Port Monitor + C Code Execution",
        "Master M0 to S0 address decode comparator"
    )

    add_tc(
        "INTERCONNECT_002",
        "Master M1 (LSU) address decode to S1 (DMEM 0x4002_0000)",
        "Verify that Master M1 read/write addresses in range 0x4002_0000 - 0x4002_FFFF route exclusively to Slave S1.",
        "CP1: M1 awaddr/araddr in 0x4002_xxxx; CP2: m01_axi_awvalid/arvalid asserts; CP3: All other slave valids remain 0; CP4: Write/read completes.",
        "INTERNAL",
        "Master M1 -> axi_interconnect S1 decoder -> m01_axi (S1 DMEM) -> Return",
        "Firmware reads and writes to DMEM.",
        "Readback values match written data.",
        "Monitor u_main_top.u_axi_interconnect_3x15.m01_axi_awvalid and m01_axi_arvalid.",
        "m01_axi_awvalid asserts; m00 and m02..m14 stay low.",
        "None (Internal)",
        "None",
        "None",
        "axi_interconnect, main_top",
        "Interconnect M1 -> S1 Decode",
        "0x4002_0000 - 0x4002_FFFF",
        "SV Interconnect Port Monitor + C Memory Operations",
        "Master M1 to S1 address decode comparator"
    )

    add_tc(
        "INTERCONNECT_003",
        "Master M1 (LSU) address decode to S2 (GPIO 0x4003_1000)",
        "Verify Master M1 address decode to Slave S2 (GPIO aperture 0x4003_1000 - 0x4003_1FFF).",
        "CP1: M1 access to 0x4003_1004; CP2: m02_axi_awvalid asserts; CP3: GPIO register updated; CP4: OKAY response returned.",
        "INTERNAL",
        "Master M1 -> axi_interconnect S2 decoder -> m02_axi -> gpio_axi -> gpio_regs",
        "Firmware writes 0x12345678 to GPIO DATA_O (0x4003_1004). Reads back.",
        "Readback equals 0x12345678.",
        "Monitor u_main_top.m02_axi_awvalid and m02_axi_awaddr.",
        "m02_axi_awvalid asserts with awaddr[11:0] == 12'h004.",
        "None (Internal)",
        "None",
        "None",
        "axi_interconnect, gpio_axi",
        "Interconnect M1 -> S2 (GPIO) Decode",
        "0x4003_1000 - 0x4003_1FFF",
        "C Register Access + SV Interconnect Monitor",
        "S2 address decode comparator"
    )

    add_tc(
        "INTERCONNECT_004",
        "Master M1 (LSU) address decode to S3 (Timer 0x4003_3000)",
        "Verify Master M1 address decode to Slave S3 (Timer aperture 0x4003_3000 - 0x4003_3FFF).",
        "CP1: M1 access to 0x4003_3000; CP2: m03_axi_awvalid asserts; CP3: Timer CTRL register updated; CP4: OKAY response returned.",
        "INTERNAL",
        "Master M1 -> axi_interconnect S3 decoder -> m03_axi -> timer_axi -> timer_regs",
        "Firmware writes 0x00000001 to Timer CTRL (0x4003_3000). Reads back.",
        "Readback equals 0x00000001.",
        "Monitor u_main_top.m03_axi_awvalid.",
        "m03_axi_awvalid asserts; timer_axi accepts write.",
        "None (Internal)",
        "None",
        "None",
        "axi_interconnect, timer_axi",
        "Interconnect M1 -> S3 (Timer) Decode",
        "0x4003_3000 - 0x4003_3FFF",
        "C Register Access + SV Interconnect Monitor",
        "S3 address decode comparator"
    )

    add_tc(
        "INTERCONNECT_005",
        "Master M1 (LSU) address decode to S4 (UART 0x4003_5000)",
        "Verify Master M1 address decode to Slave S4 (UART aperture 0x4003_5000 - 0x4003_5FFF).",
        "CP1: M1 access to 0x4003_5000; CP2: m04_axi_awvalid asserts; CP3: UART THR accepts byte; CP4: OKAY response returned.",
        "INTERNAL",
        "Master M1 -> axi_interconnect S4 decoder -> m04_axi -> axi_uart_top",
        "Firmware writes 'A' (0x41) to UART THR (0x4003_5000).",
        "Character queued into UART TX FIFO.",
        "Monitor u_main_top.m04_axi_awvalid.",
        "m04_axi_awvalid asserts; UART top accepts beat.",
        "None (Internal)",
        "None",
        "None",
        "axi_interconnect, axi_uart_top",
        "Interconnect M1 -> S4 (UART) Decode",
        "0x4003_5000 - 0x4003_5FFF",
        "C Register Access + SV Interconnect Monitor",
        "S4 address decode comparator"
    )

    add_tc(
        "INTERCONNECT_006",
        "Master M1 (LSU) address decode to S8 (Encoder 0x4003_D000)",
        "Verify Master M1 address decode to Slave S8 (Quadrature Encoder aperture 0x4003_D000 - 0x4003_DFFF).",
        "CP1: M1 access to 0x4003_D008; CP2: m08_axi_awvalid asserts; CP3: Encoder CTRL register updated; CP4: OKAY response returned.",
        "INTERNAL",
        "Master M1 -> axi_interconnect S8 decoder -> m08_axi -> enc_axi_slave",
        "Firmware writes 0x00000001 to Encoder CTRL (0x4003_D008). Reads back.",
        "Readback equals 0x00000001.",
        "Monitor u_main_top.m08_axi_awvalid.",
        "m08_axi_awvalid asserts; enc_axi_slave captures write.",
        "None (Internal)",
        "None",
        "None",
        "axi_interconnect, enc_axi_slave",
        "Interconnect M1 -> S8 (Encoder) Decode",
        "0x4003_D000 - 0x4003_DFFF",
        "C Register Access + SV Interconnect Monitor",
        "S8 address decode comparator"
    )

    add_tc(
        "INTERCONNECT_007",
        "Master M1 (LSU) address decode to S9 (PID 0x4003_F000)",
        "Verify Master M1 address decode to Slave S9 (PID Controller aperture 0x4003_F000 - 0x4003_FFFF).",
        "CP1: M1 access to 0x4003_F000; CP2: m09_axi_awvalid asserts; CP3: PID SETPOINT register updated; CP4: OKAY response returned.",
        "INTERNAL",
        "Master M1 -> axi_interconnect S9 decoder -> m09_axi -> pid_axi_slave",
        "Firmware writes 0x00001000 to PID SETPOINT (0x4003_F000). Reads back.",
        "Readback equals 0x00001000.",
        "Monitor u_main_top.m09_axi_awvalid.",
        "m09_axi_awvalid asserts; pid_axi_slave captures write.",
        "None (Internal)",
        "None",
        "None",
        "axi_interconnect, pid_axi_slave",
        "Interconnect M1 -> S9 (PID) Decode",
        "0x4003_F000 - 0x4003_FFFF",
        "C Register Access + SV Interconnect Monitor",
        "S9 address decode comparator"
    )

    add_tc(
        "INTERCONNECT_008",
        "Master M1 (LSU) address decode to S10 (PWM 0x4004_1000)",
        "Verify Master M1 address decode to Slave S10 (PWM aperture 0x4004_1000 - 0x4004_1FFF).",
        "CP1: M1 access to 0x4004_1000; CP2: m10_axi_awvalid asserts; CP3: PWM slv_reg0 updated with duty cycle; CP4: OKAY response returned.",
        "INTERNAL",
        "Master M1 -> axi_interconnect S10 decoder -> m10_axi -> myip_v1_0_S00_AXI",
        "Firmware writes 0x00000080 (duty=128) to PWM slv_reg0 (0x4004_1000). Reads back.",
        "Readback equals 0x00000080.",
        "Monitor u_main_top.m10_axi_awvalid.",
        "m10_axi_awvalid asserts; PWM IP updates duty register.",
        "None (Internal)",
        "None",
        "None",
        "axi_interconnect, myip_v1_0_S00_AXI",
        "Interconnect M1 -> S10 (PWM) Decode",
        "0x4004_1000 - 0x4004_1FFF",
        "C Register Access + SV Interconnect Monitor",
        "S10 address decode comparator"
    )

    add_tc(
        "INTERCONNECT_009",
        "Reserved slave slots S5, S6, S7 access returning DECERR",
        "Verify that accessing disabled interconnect slave slots S5 (0x4003_7000), S6 (0x4003_9000), or S7 (0x4003_B000) produces DECERR (2'b11).",
        "CP1: Access to 0x4003_7000; CP2: M05_ADDR_WIDTH=0; CP3: Interconnect routes to default error slave; CP4: bresp=2'b11, rresp=2'b11 returned.",
        "INTERNAL",
        "Master M1 -> axi_interconnect -> Disabled slot check -> Default DECERR slave -> M1",
        "Firmware performs read from (volatile uint32_t*)0x4003_7000.",
        "Read completes with bus DECERR; CPU continues execution without hang.",
        "Monitor m1_rresp or m1_bresp when 0x4003_7000 is accessed.",
        "rresp == 2'b11; bresp == 2'b11.",
        "None (Internal)",
        "None",
        "None",
        "axi_interconnect",
        "Reserved Slaves S5-S7 DECERR Generation",
        "0x4003_7000, 0x4003_9000, 0x4003_B000",
        "C Probe Read + SV Response Assertion",
        "Disabled slave width=0 decode logic"
    )

    add_tc(
        "INTERCONNECT_010",
        "Reserved slave slots S11, S12, S13, S14 access returning DECERR",
        "Verify that accessing disabled slave slots S11 (0x4004_3000), S12 (0x4004_5000), S13 (0x4004_7000), or S14 (0x4004_9000) produces DECERR.",
        "CP1: Access to 0x4004_3000; CP2: M11_ADDR_WIDTH=0; CP3: Default error slave responds; CP4: bresp=2'b11, rresp=2'b11 returned.",
        "INTERNAL",
        "Master M1 -> axi_interconnect -> Disabled slot check -> Default DECERR slave -> M1",
        "Firmware performs write to (volatile uint32_t*)0x4004_3000.",
        "Write completes with bus DECERR; CPU continues execution without hang.",
        "Monitor m1_bresp when 0x4004_3000 is written.",
        "bresp == 2'b11.",
        "None (Internal)",
        "None",
        "None",
        "axi_interconnect",
        "Reserved Slaves S11-S14 DECERR Generation",
        "0x4004_3000, 0x4004_5000, 0x4004_7000, 0x4004_9000",
        "C Probe Write + SV Response Assertion",
        "Disabled slave width=0 decode logic"
    )

    add_tc(
        "INTERCONNECT_011",
        "Unmapped hole 0x4003_7000-0x4003_CFFF returning DECERR",
        "Verify that unmapped address regions between active peripherals produce immediate DECERR without bus deadlock.",
        "CP1: Read from 0x4003_8000; CP2: Decode misses all valid slave apertures; CP3: Default error slave responds within 4 cycles; CP4: rresp=2'b11.",
        "INTERNAL",
        "Master M1 -> axi_interconnect default decode -> Default DECERR slave -> M1",
        "Firmware performs read from unmapped offset 0x4003_8000.",
        "Read completes cleanly with DECERR.",
        "Check that m1_rvalid asserts within 5 cycles of arvalid and m1_rresp == 2'b11.",
        "m1_rresp == 2'b11; latency <= 5 cycles.",
        "None (Internal)",
        "None",
        "None",
        "axi_interconnect",
        "Address Space Hole DECERR Trap",
        "0x4003_8000 (Unmapped Hole)",
        "C Hole Read + SV Timeout Protection",
        "Default decode branch in read address mux"
    )

    add_tc(
        "INTERCONNECT_012",
        "Legacy unmapped address 0x9000_0000 returning DECERR without hanging",
        "Verify that accessing completely invalid high addresses outside the SoC memory map (0x9000_0000) generates DECERR and does not hang the AXI interconnect.",
        "CP1: M1 access to 0x9000_0000; CP2: Interconnect detects address outside all base/aperture ranges; CP3: DECERR returned; CP4: Next valid transaction succeeds.",
        "INTERNAL",
        "Master M1 -> axi_interconnect -> Default DECERR slave -> Response -> Next transaction to DMEM",
        "Firmware writes to 0x9000_0000, then immediately writes to DMEM 0x4002_0000.",
        "DMEM write succeeds; signature 0xDDEC_0001 written to mailbox.",
        "Monitor m1_bresp for 0x9000_0000 (expect 2'b11) and subsequent DMEM write (expect 2'b00).",
        "First write returns 2'b11; second write returns 2'b00.",
        "None (Internal)",
        "None",
        "None",
        "axi_interconnect",
        "Legacy Out-of-Range Non-Hang Protection",
        "0x9000_0000",
        "C Consecutive Error/Valid Sequence + SV Protocol Check",
        "Interconnect error slave reset and recovery"
    )

    add_tc(
        "INTERCONNECT_013",
        "Arbiter contention between M1 (LSU) and M2 (DMA) for shared peripheral",
        "Verify round-robin or priority arbitration in axi_interconnect when Master M1 and External DMA Master M2 simultaneously attempt write transactions to DMEM.",
        "CP1: M1 and M2 assert awvalid in the same clock cycle; CP2: Interconnect arbiter grants one master; CP3: Second master granted after first completes; CP4: No data corruption.",
        "EXTERNAL",
        "External DMA Master (s02_axi) & VeeR LSU (s01_axi) -> Interconnect arbiter -> Shared Slave S1 (DMEM)",
        "Firmware continuously writes 0x11111111 to DMEM 0x4002_0500.",
        "Memory at 0x4002_0500 holds 0x11111111; DMA target 0x4002_0504 holds 0x22222222.",
        "Drive s02_axi_awvalid=1 and s02_axi_wvalid=1 simultaneously with M1 write to 0x4002_0504. Verify both transactions complete with OKAY.",
        "s02_axi_bvalid asserts; m1_bvalid asserts; both writes succeed without data interleaving.",
        "External DMA Master Port (M2)",
        "s02_axi_awaddr, s02_axi_awvalid, s02_axi_wdata, s02_axi_wvalid, s02_axi_bready",
        "s02_axi_awready, s02_axi_wready, s02_axi_bvalid, s02_axi_bresp",
        "axi_interconnect, arbiter, priority_encoder",
        "Multi-Master Interconnect Arbitration",
        "0x4002_0500 - 0x4002_0504 (DMEM)",
        "SV Concurrent Master Stimulus + C Background Write",
        "Arbiter grant states, request priority logic"
    )

    # ----------------------------------------------------
    # 8. GPIO
    # ----------------------------------------------------
    add_tc(
        "GPIO_001",
        "GPIO output register DATA_O write and pin assertion",
        "Verify that writing to GPIO DATA_O register (0x4003_1004) with direction set to output drives external gpio_io pins correctly.",
        "CP1: DIR set to 0xFFFFFFFF; CP2: Write 0xA5A55A5A to DATA_O; CP3: External gpio_io pins reflect 0xA5A55A5A; CP4: Readback of DATA_O matches.",
        "EXTERNAL",
        "VeeR LSU -> Interconnect S2 -> gpio_regs DATA_O -> gpio_wrapper output buffers -> External gpio_io pins",
        "Firmware configures GPIO DIR (0x4003_1008) = 0xFFFFFFFF. Writes 0xA5A55A5A to DATA_O (0x4003_1004). Reads back.",
        "Readback == 0xA5A55A5A; mailbox receives 0x9910_0001.",
        "Monitor external gpio_io bus. Assert gpio_io == 32'hA5A55A5A.",
        "gpio_io pins transition from Z to 32'hA5A55A5A within 2 clock cycles.",
        "GPIO External I/O",
        "None",
        "gpio_io[31:0]",
        "gpio_regs, gpio_wrapper, gpio_axi",
        "GPIO Output Pin Driving",
        "0x4003_1004 (DATA_O)",
        "C Register Write + SV Pin Monitor",
        "Output register flop updates, tri-state driver enables"
    )

    add_tc(
        "GPIO_002",
        "GPIO input register DATA_I read from external driven pins",
        "Verify that setting GPIO direction to input (DIR=0) allows CPU to read external voltage states on gpio_io through DATA_I register (0x4003_1000).",
        "CP1: DIR set to 0x00000000; CP2: Testbench drives gpio_io=0x12345678; CP3: CPU reads DATA_I; CP4: Value matches driven pattern.",
        "EXTERNAL",
        "External gpio_io pins -> gpio_wrapper input synchronizer -> gpio_regs DATA_I -> Interconnect S2 -> VeeR LSU",
        "Firmware configures GPIO DIR=0. Polls DATA_I (0x4003_1000) and asserts equality to expected testbench stimulus.",
        "Read value matches 0x12345678; mailbox receives 0x9910_0002.",
        "Drive gpio_io with pattern 0x12345678. Release testbench driver before DIR is switched to output.",
        "gpio_io driven with 0x12345678; u_gpio.gpio_i == 32'h12345678.",
        "GPIO External I/O",
        "gpio_io[31:0]",
        "None",
        "gpio_regs, gpio_wrapper",
        "GPIO External Input Reading",
        "0x4003_1000 (DATA_I)",
        "SV Pin Driver + C Polling Read",
        "Input synchronizer flip-flops, DATA_I read multiplexer"
    )

    add_tc(
        "GPIO_003",
        "GPIO direction register DIR input/output isolation",
        "Verify mixed direction configuration: lower 16 bits configured as outputs, upper 16 bits configured as inputs. Verify no driver contention.",
        "CP1: DIR = 0x0000FFFF; CP2: Lower 16 pins drive external values; CP3: Upper 16 pins accept testbench stimulus; CP4: Zero X-states observed on gpio_io.",
        "EXTERNAL",
        "External gpio_io pins <-> gpio_wrapper tri-state drivers <-> gpio_regs DIR",
        "Firmware sets DIR=0x0000FFFF, DATA_O=0x0000AAAA. Reads DATA_I.",
        "Lower 16 bits read back 0xAAAA; upper 16 bits reflect external stimulus.",
        "Drive upper 16 bits of gpio_io with 0x5555; leave lower 16 bits high-Z. Check gpio_io == 0x5555AAAA.",
        "gpio_io == 32'h5555AAAA; no contention or X-states.",
        "GPIO External I/O",
        "gpio_io[31:16]",
        "gpio_io[15:0]",
        "gpio_regs, gpio_wrapper",
        "GPIO Split Direction Isolation",
        "0x4003_1008 (DIR)",
        "SV Mixed Driver + C Bidirectional Read/Write",
        "Per-bit tri-state enable control"
    )

    add_tc(
        "GPIO_004",
        "GPIO atomic set register SET_O bit modification",
        "Verify that writing a bitmask to SET_O (0x4003_1020) sets only the corresponding bits in DATA_O without requiring read-modify-write.",
        "CP1: Initial DATA_O = 0x00000000; CP2: Write 0x0000000F to SET_O; CP3: DATA_O becomes 0x0000000F; CP4: Write 0x000000F0 to SET_O; CP5: DATA_O becomes 0x000000FF.",
        "INTERNAL",
        "VeeR LSU -> Interconnect S2 -> gpio_regs SET_O -> s_reg_data_o bitwise OR",
        "Firmware writes 0 to DATA_O, writes 0x0F to SET_O, reads DATA_O, writes 0xF0 to SET_O, reads DATA_O.",
        "First read == 0x0000000F; second read == 0x000000FF.",
        "Monitor u_gpio.s_reg_data_o transitions on write_commit to offset 0x20.",
        "s_reg_data_o updates from 0x0 -> 0xF -> 0xFF.",
        "None (Internal)",
        "None",
        "None",
        "gpio_regs",
        "GPIO Atomic SET Operation",
        "0x4003_1020 (SET_O)",
        "C Atomic Sequence + SV Register Monitor",
        "ADDR_SET_O register decode and OR logic"
    )

    add_tc(
        "GPIO_005",
        "GPIO atomic clear register CLR_O bit modification",
        "Verify that writing a bitmask to CLR_O (0x4003_1024) clears only the corresponding bits in DATA_O.",
        "CP1: Initial DATA_O = 0xFFFFFFFF; CP2: Write 0x000000FF to CLR_O; CP3: DATA_O becomes 0xFFFFFF00; CP4: Remaining bits untouched.",
        "INTERNAL",
        "VeeR LSU -> Interconnect S2 -> gpio_regs CLR_O -> s_reg_data_o bitwise AND NOT",
        "Firmware initializes DATA_O=0xFFFFFFFF, writes 0x000000FF to CLR_O, reads DATA_O.",
        "Readback == 0xFFFFFF00.",
        "Monitor u_gpio.s_reg_data_o transitions on write_commit to offset 0x24.",
        "s_reg_data_o updates from 0xFFFFFFFF to 0xFFFFFF00.",
        "None (Internal)",
        "None",
        "None",
        "gpio_regs",
        "GPIO Atomic CLEAR Operation",
        "0x4003_1024 (CLR_O)",
        "C Atomic Sequence + SV Register Monitor",
        "ADDR_CLR_O register decode and bitwise-clear logic"
    )

    add_tc(
        "GPIO_006",
        "GPIO atomic toggle register TGL_O bit modification",
        "Verify that writing a bitmask to TGL_O (0x4003_1028) inverts the targeted bits in DATA_O.",
        "CP1: Initial DATA_O = 0xAAAAAAAA; CP2: Write 0xFFFFFFFF to TGL_O; CP3: DATA_O becomes 0x55555555; CP4: Second toggle restores 0xAAAAAAAA.",
        "INTERNAL",
        "VeeR LSU -> Interconnect S2 -> gpio_regs TGL_O -> s_reg_data_o bitwise XOR",
        "Firmware initializes DATA_O=0xAAAAAAAA, writes 0xFFFFFFFF to TGL_O, reads DATA_O, writes 0xFFFFFFFF to TGL_O, reads DATA_O.",
        "First read == 0x55555555; second read == 0xAAAAAAAA.",
        "Monitor u_gpio.s_reg_data_o transitions on write to offset 0x28.",
        "s_reg_data_o alternates between 0xAAAAAAAA and 0x55555555.",
        "None (Internal)",
        "None",
        "None",
        "gpio_regs",
        "GPIO Atomic TOGGLE Operation",
        "0x4003_1028 (TGL_O)",
        "C Atomic Sequence + SV Register Monitor",
        "ADDR_TGL_O register decode and XOR logic"
    )

    add_tc(
        "GPIO_007",
        "GPIO input inversion register INV_IN functionality",
        "Verify that enabling input inversion in INV_IN (0x4003_1034) logically inverts external pin values before presenting to DATA_I.",
        "CP1: External pin driven high (1); CP2: INV_IN bit set to 1; CP3: DATA_I reads low (0); CP4: External pin driven low reads high.",
        "EXTERNAL",
        "External gpio_io pins -> Inverter stage -> gpio_regs DATA_I -> CPU",
        "Firmware configures INV_IN=0x00000001. Reads DATA_I while external pin is held high.",
        "DATA_I bit 0 reads 0 despite external pin being 1.",
        "Drive gpio_io[0] = 1'b1. Verify u_gpio.gpio_i[0] == 1'b0 after inversion.",
        "Inversion verified: internal input logic equals ~external_pin.",
        "GPIO External I/O",
        "gpio_io[0]",
        "None",
        "gpio_regs",
        "GPIO Input Polarity Inversion",
        "0x4003_1034 (INV_IN)",
        "SV Pin Driver + C Inverted Readback",
        "Input polarity XOR stage"
    )

    add_tc(
        "GPIO_008",
        "GPIO output inversion register INV_OUT functionality",
        "Verify that enabling output inversion in INV_OUT (0x4003_1038) inverts DATA_O values before driving external pins.",
        "CP1: DATA_O bit set to 1; CP2: INV_OUT bit set to 1; CP3: External gpio_io pin driven low (0); CP4: INV_OUT=0 restores high.",
        "EXTERNAL",
        "VeeR LSU -> gpio_regs DATA_O -> Inverter stage -> External gpio_io pin",
        "Firmware sets DIR=1, DATA_O=1, INV_OUT=1.",
        "External pin driven low; firmware verifies via loopback or testbench.",
        "Monitor external gpio_io[0]. Assert gpio_io[0] == 1'b0 when DATA_O[0]=1 and INV_OUT[0]=1.",
        "gpio_io[0] == 1'b0 observed on waveform.",
        "GPIO External I/O",
        "None",
        "gpio_io[0]",
        "gpio_regs",
        "GPIO Output Polarity Inversion",
        "0x4003_1038 (INV_OUT)",
        "C Register Write + SV Output Pin Monitor",
        "Output polarity XOR stage"
    )

    add_tc(
        "GPIO_009",
        "GPIO write mask register WR_MASK bit protection",
        "Verify that setting bits in WR_MASK (0x4003_1040) protects the corresponding bits in DATA_O from being modified by direct writes.",
        "CP1: Initial DATA_O = 0x00000000; CP2: Set WR_MASK = 0x0000000F; CP3: Write 0xFFFFFFFF to DATA_O; CP4: Bits [3:0] remain 0, bits [31:4] become 1.",
        "INTERNAL",
        "VeeR LSU -> Interconnect S2 -> gpio_regs WR_MASK logic -> s_reg_data_o",
        "Firmware sets WR_MASK=0x0000000F, writes 0xFFFFFFFF to DATA_O, reads DATA_O.",
        "Readback equals 0xFFFFFFF0 (lower 4 bits masked).",
        "Check s_reg_data_o in u_gpio. Assert bits [3:0] remain 0.",
        "s_reg_data_o == 32'hFFFFFFF0.",
        "None (Internal)",
        "None",
        "None",
        "gpio_regs",
        "GPIO Write Mask Protection",
        "0x4003_1040 (WR_MASK)",
        "C Masked Write Test + SV Flop Monitor",
        "Write mask bit-enable gating logic"
    )

    add_tc(
        "GPIO_010",
        "GPIO interrupt generation on rising edge (INT_TYP, INT_POL)",
        "Verify that configuring GPIO pin 0 for edge-triggered (INT_TYP=1), rising-edge (INT_POL=1) interrupt asserts gpio_intr when external pin transitions 0->1.",
        "CP1: INT_EN[0]=1, INT_TYP[0]=1, INT_POL[0]=1; CP2: gpio_io[0] pulses 0->1; CP3: INT_STS[0] asserts; CP4: gpio_intr output asserts to PIC line 2.",
        "EXTERNAL",
        "External gpio_io[0] rising edge -> gpio_regs edge detector -> INT_STS[0] -> gpio_intr pin -> Core PIC line 2",
        "Firmware configures GPIO interrupt on pin 0 (edge, rising). Waits in loop for volatile flag set by GPIO ISR.",
        "Flag set to 1 upon interrupt service; mailbox receives 0x9910_000A.",
        "Drive gpio_io[0] 0->1 transition. Verify gpio_intr asserts within 2 clock cycles.",
        "gpio_intr asserts; u_soc_top.core_extintsrc_req[2] == 1'b1.",
        "GPIO External I/O & Interrupt",
        "gpio_io[0]",
        "gpio_intr",
        "gpio_regs, soc_top",
        "GPIO Edge-Triggered Interrupt Generation",
        "0x4003_100C (INT_EN), 0x4003_1010 (INT_TYP), 0x4003_1014 (INT_POL)",
        "SV External Edge Stimulus + C ISR Flag Check",
        "Edge detector flip-flops, interrupt OR reduction tree"
    )

    add_tc(
        "GPIO_011",
        "GPIO interrupt status clear (INT_STS W1C) and line deassertion",
        "Verify that writing 1 to INT_STS (0x4003_101C) clears the interrupt status bit and deasserts the external gpio_intr line.",
        "CP1: gpio_intr asserted high; CP2: Firmware writes 1 to INT_STS[0]; CP3: INT_STS[0] clears to 0; CP4: gpio_intr deasserts to 0.",
        "EXTERNAL",
        "VeeR LSU -> Interconnect S2 -> gpio_regs INT_STS W1C -> gpio_intr deassertion",
        "In GPIO ISR, firmware writes 0x00000001 to INT_STS (0x4003_101C). Reads back INT_STS to confirm 0.",
        "INT_STS reads back 0x00000000; interrupt does not immediately re-trigger.",
        "Monitor gpio_intr pin. Assert gpio_intr drops to 0 within 2 cycles of write_commit to INT_STS.",
        "gpio_intr falls to 0; u_gpio.s_reg_int_sts == 0.",
        "GPIO External Interrupt",
        "None",
        "gpio_intr",
        "gpio_regs",
        "GPIO Interrupt Status W1C Clearing",
        "0x4003_101C (INT_STS)",
        "C W1C Write in ISR + SV Interrupt Line Monitor",
        "W1C register clear branch"
    )

    add_tc(
        "GPIO_012",
        "GPIO bidirectional I/O tri-state contention resolution",
        "Verify that when the DUT drives outputs on gpio_io, the testbench driver enters high-impedance (32'bz), preventing 0x0000xxxx driver contention.",
        "CP1: DUT drives gpio_io=0x55555555; CP2: TB driver enables only when driven from TB; CP3: Zero X or contention states on gpio_io bus; CP4: Clean signal levels.",
        "EXTERNAL",
        "DUT gpio_wrapper tri-state output buffers <-> External gpio_io bus <-> Testbench tri-state driver",
        "Firmware writes alternating patterns (0x55555555, 0xAAAAAAAA) to DATA_O with DIR=0xFFFFFFFF.",
        "All output writes complete with clean levels.",
        "SV assertion: assert property (@(posedge clk) !$isunknown(gpio_io));",
        "gpio_io is 100% clean 0 or 1, zero X or Z states when active.",
        "GPIO External Bidirectional Pins",
        "gpio_io[31:0]",
        "gpio_io[31:0]",
        "gpio_wrapper, tb_soc_top",
        "GPIO Bidirectional Driver Contention Immunity",
        "gpio_io pins",
        "SV Tri-State Driver + SV Unknown-Value Assertion",
        "Tri-state enable logic and pin contention resolution"
    )
