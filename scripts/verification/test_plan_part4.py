# scripts/test_plan_part4.py
# Categories 12-15: PID, PWM, HYBRID, INTERRUPT

def populate_part4(add_tc):
    # ----------------------------------------------------
    # 12. PID CONTROLLER
    # ----------------------------------------------------
    add_tc(
        "PID_001",
        "PID proportional response calculation (Kp * e)",
        "Program setpoint=1000, actual=800 (error=200). Set Kp=0x0002_0000 (2.0 in Q16.16), Ki=0, Kd=0. Trigger update. Verify PID output = 200 * 2 = 400.",
        "CP1: error = 1000 - 800 = 200; CP2: Proportional term = 200 * 2.0 = 400; CP3: OUTPUT register (0x4003_F010) reads 400; CP4: pid_out bus equals 16'd400.",
        "EXTERNAL",
        "VeeR LSU -> PID SETPOINT, KP -> Hardware tick / manual update -> pid_core ALU -> pid_out bus -> External observation",
        "Firmware writes SETPOINT=1000, KP=0x00020000, KI=0, KD=0, CTRL=0x05 (enable, manual update). Reads OUTPUT (0x4003_F010).",
        "OUTPUT reads 400; ERROR reads 200; mailbox receives 0x091D_0001.",
        "Monitor external pid_out bus and pid_out_valid pin when update occurs.",
        "pid_out == 16'd400; pid_out_valid pulses high for 1 cycle.",
        "PID Controller External Output Bus",
        "None",
        "pid_out[15:0], pid_out_valid",
        "pid_core, pid_axi_slave",
        "PID Proportional Control Response",
        "0x4003_F000 (SETPOINT), 0x4003_F004 (KP), 0x4003_F010 (OUTPUT)",
        "C Gain/Setpoint Config + SV Output Bus Assertion",
        "Proportional multiplier product and truncator"
    )

    add_tc(
        "PID_002",
        "PID integral accumulation (Ki * integral(e)) over multiple sampling ticks",
        "Set Kp=0, Ki=0x0001_0000 (1.0), Kd=0 with constant error=10. Provide 5 ticks. Verify output accumulates: 10, 20, 30, 40, 50.",
        "CP1: Constant error=10; CP2: Integrator adds error on every tick; CP3: After 5 ticks, OUTPUT reads 50; CP4: INT_SAT remains 0.",
        "INTERNAL",
        "Hardware tick_i pulses -> pid_core integrator accumulator -> Scaled output -> PID OUTPUT register",
        "Firmware sets SETPOINT=10, KI=0x00010000, KP=0, KD=0, CTRL=0x01 (enable).",
        "After 5 timer triggers, OUTPUT reads 50.",
        "Drive 5 pulses on u_pid.tick_i in testbench. Sample u_pid.pid_out at each tick.",
        "Output sequence: 10, 20, 30, 40, 50 observed on pid_out.",
        "None (Internal)",
        "None",
        "None",
        "pid_core",
        "PID Integrator Accumulation",
        "0x4003_F008 (KI), 0x4003_F010 (OUTPUT)",
        "SV Tick Driver + C Accumulated Value Read",
        "Integrator accumulator register and saturation check"
    )

    add_tc(
        "PID_003",
        "PID derivative response calculation (Kd * delta_e)",
        "Set Kp=0, Ki=0, Kd=0x0001_0000 (1.0). Change error from 0 to 50 in one step. Verify derivative output = 50 * 1.0 = 50 on first tick, then 0 on second tick.",
        "CP1: Step error delta = 50; CP2: Tick 1 produces output 50; CP3: Error stays constant at 50; CP4: Tick 2 delta=0, producing output 0.",
        "INTERNAL",
        "Step change on SETPOINT -> pid_core derivative subtractor -> Kd multiplier -> PID output",
        "Firmware sets KD=0x00010000, KP=0, KI=0. Sets SETPOINT=0, ticks. Sets SETPOINT=50, ticks. Reads OUTPUT.",
        "Tick 1 OUTPUT=50; Tick 2 OUTPUT=0.",
        "Verify u_pid.pid_out equals 50 on tick 1 and 0 on tick 2.",
        "Derivative response transient verified.",
        "None (Internal)",
        "None",
        "None",
        "pid_core",
        "PID Derivative Transient Response",
        "0x4003_F00C (KD)",
        "C Step Change Test + SV Bus Monitor",
        "Derivative differentiator register (e - e_prev)"
    )

    add_tc(
        "PID_004",
        "Derivative on Error vs Derivative on Measurement mode selection (D_ON_MEAS)",
        "Verify CTRL[3] (D_ON_MEAS): when 0, derivative acts on (error - error_prev); when 1, derivative acts on -(actual - actual_prev) to avoid setpoint kick.",
        "CP1: D_ON_MEAS=1; CP2: Step change on SETPOINT with constant actual produces 0 derivative output; CP3: Step change on actual produces negative derivative output.",
        "INTERNAL",
        "VeeR LSU -> pid_regs CTRL[3] -> pid_core derivative multiplexer -> Output ALU",
        "Firmware sets CTRL[3]=1, changes SETPOINT from 0 to 100. Verifies no derivative kick.",
        "Output does not spike upon setpoint jump when D_ON_MEAS=1.",
        "Check u_pid.u_pid_core.deriv_term remains 0 during setpoint change.",
        "Setpoint kick immunity verified.",
        "None (Internal)",
        "None",
        "None",
        "pid_core",
        "Derivative on Measurement Anti-Kick Mode",
        "0x4003_F014 (CTRL bit 3)",
        "C Anti-Kick Test + SV Internal Node Assertion",
        "D_ON_MEAS multiplexer in pid_core"
    )

    add_tc(
        "PID_005",
        "PID output saturation clamping at positive limit (OUT_MAX, SAT_HI flag)",
        "Set OUT_MAX (0x4003_F024) to 500. Drive large error resulting in raw PID sum of 2,000. Verify output is clamped to 500 and STATUS bit 2 (SAT_HI) asserts.",
        "CP1: Raw output exceeds OUT_MAX; CP2: Clamped to 500; CP3: STATUS[2] (SAT_HI) latches high; CP4: External pid_sat_flag pin asserts high.",
        "EXTERNAL",
        "Raw PID sum -> Clamping comparator -> Output register (clamped to OUT_MAX) -> pid_sat_flag pin",
        "Firmware sets OUT_MAX=500, SETPOINT=5000, KP=0x00010000. Reads OUTPUT and STATUS.",
        "OUTPUT reads exactly 500; STATUS bit 2 reads 1.",
        "Monitor external pid_sat_flag pin. Assert pid_sat_flag == 1'b1.",
        "pid_sat_flag asserts high; pid_out == 16'd500.",
        "PID Controller External Saturation Flag",
        "None",
        "pid_sat_flag, pid_out[15:0]",
        "pid_core, main_top",
        "PID Output Positive Saturation Clamping",
        "0x4003_F024 (OUT_MAX), pid_sat_flag pin",
        "C Saturation Test + SV Saturation Pin Monitor",
        "Output saturation upper clamp comparator"
    )

    add_tc(
        "PID_006",
        "PID output saturation clamping at negative limit (OUT_MIN, SAT_LO flag)",
        "Set OUT_MIN (0x4003_F028) to -200 (signed). Drive negative error. Verify output clamped to -200 and STATUS bit 3 (SAT_LO) asserts.",
        "CP1: Raw output falls below OUT_MIN; CP2: Clamped to -200; CP3: STATUS[3] (SAT_LO) asserts; CP4: Output remains within legal signed range.",
        "INTERNAL",
        "Raw negative PID sum -> Lower clamp comparator -> Output clamped to OUT_MIN -> STATUS[3]",
        "Firmware sets OUT_MIN=-200, SETPOINT=-1000, KP=0x00010000. Reads OUTPUT and STATUS.",
        "OUTPUT reads -200 (0xFF38); STATUS bit 3 reads 1.",
        "Verify u_pid.pid_out == 16'hFF38 when saturated low.",
        "Signed lower clamp verified.",
        "None (Internal)",
        "None",
        "None",
        "pid_core",
        "PID Output Negative Saturation Clamping",
        "0x4003_F028 (OUT_MIN)",
        "C Negative Saturation Test + SV Bus Assertion",
        "Output saturation lower clamp comparator"
    )

    add_tc(
        "PID_007",
        "Integrator anti-windup clamping (AW_EN, INT_MAX, INT_MIN, INT_SAT flag)",
        "Enable anti-windup (CTRL[4]=1) and program INT_MAX (0x4003_F02C) to 1,000. Drive sustained error. Verify accumulator clamps at 1,000 and STATUS[4] asserts.",
        "CP1: AW_EN=1; CP2: Sustained positive error applied; CP3: Integrator accumulation halts at INT_MAX; CP4: STATUS[4] (INT_SAT) asserts.",
        "INTERNAL",
        "pid_core integrator adder -> Anti-windup clamp comparator -> Integrator accumulator register",
        "Firmware enables anti-windup, applies 20 ticks. Verifies integrator does not wind up to infinity.",
        "Integrator clamped; STATUS bit 4 reads 1; quick recovery upon error sign inversion.",
        "Monitor u_pid.u_pid_core.integrator accumulator register.",
        "Accumulator clamps precisely at INT_MAX threshold.",
        "None (Internal)",
        "None",
        "None",
        "pid_core",
        "PID Integrator Anti-Windup Protection",
        "0x4003_F02C (INT_MAX), 0x4003_F014 (CTRL[4])",
        "C Anti-Windup Stress Test + SV Accumulator Monitor",
        "Anti-windup clamping logic and saturation bit"
    )

    add_tc(
        "PID_008",
        "PID manual software update command trigger (CTRL[2])",
        "Verify that writing 1 to CTRL[2] (MANUAL_UPDATE) forces an immediate PID calculation cycle without waiting for a hardware tick pulse.",
        "CP1: Hardware tick inactive; CP2: Write CTRL[2]=1; CP3: pid_core FSM leaves IDLE and computes; CP4: STATUS[1] (DONE) asserts; CP5: CTRL[2] self-clears.",
        "INTERNAL",
        "VeeR LSU -> pid_regs CTRL[2] manual strobe -> pid_core calculation FSM -> Done interrupt",
        "Firmware writes CTRL[2]=1. Polls STATUS bit 1 (DONE). Verifies calculation completed.",
        "STATUS DONE reads 1; CTRL[2] reads back 0 (self-cleared).",
        "Monitor u_pid.u_pid_core.state traversing CALC states upon CTRL[2] write.",
        "FSM executes full calculation pipeline and returns to IDLE.",
        "None (Internal)",
        "None",
        "None",
        "pid_core, pid_axi_slave",
        "PID Manual Software Computation Trigger",
        "0x4003_F014 (CTRL[2])",
        "C Manual Update Strobe + SV FSM State Monitor",
        "Manual update strobe generation, self-clearing flop"
    )

    add_tc(
        "PID_009",
        "PID integrator reset self-clearing command (CTRL[1])",
        "Verify that writing 1 to CTRL[1] (INT_RESET) zeroes the internal integrator accumulator, e_prev, and act_prev in a single clock cycle.",
        "CP1: Integrator holds non-zero value; CP2: Write CTRL[1]=1; CP3: Integrator clears to 0 immediately; CP4: CTRL[1] reads back 0.",
        "INTERNAL",
        "VeeR LSU -> pid_regs CTRL[1] reset strobe -> Integrator accumulator synchronous clear",
        "Firmware accumulates integral term, writes CTRL[1]=1. Reads OUTPUT to confirm integral reset to 0.",
        "Integrator term cleared; OUTPUT drops to proportional component only.",
        "Assert u_pid.u_pid_core.integrator == 0 on the cycle after CTRL[1] write.",
        "Integrator register synchronously zeroes; CTRL[1] self-clears.",
        "None (Internal)",
        "None",
        "None",
        "pid_core",
        "PID Integrator Synchronous Reset",
        "0x4003_F014 (CTRL[1])",
        "C Integrator Clear Command + SV Flop Assertion",
        "Synchronous clear on integrator, e_prev, act_prev"
    )

    add_tc(
        "PID_010",
        "PID interrupt generation on computation DONE and OVERRUN flags",
        "Verify that setting CTRL[5] (IRQ_EN) asserts external pid_intr to PIC line 5 when DONE or OVERRUN status bits are set.",
        "CP1: IRQ_EN=1; CP2: Calculation completes -> DONE=1; CP3: pid_intr asserts high to core; CP4: Writing 1 to STATUS[1] deasserts interrupt.",
        "EXTERNAL",
        "pid_core DONE flag -> STATUS[1] sticky bit -> IRQ_EN gate -> pid_intr pin -> PIC line 5",
        "Firmware enables PID interrupt, triggers update. In PID ISR, clears DONE bit and increments PID execution counter.",
        "PID ISR executes; pid_intr deasserts; execution counter increments.",
        "Monitor external pid_intr pin. Assert pid_intr goes high upon calculation completion.",
        "pid_intr asserts; u_soc_top.core_extintsrc_req[5] == 1'b1.",
        "PID External Interrupt",
        "None",
        "pid_intr",
        "pid_axi_slave, soc_top",
        "PID Interrupt Generation to PIC",
        "0x4003_F014 (CTRL[5]), pid_intr pin",
        "SV Interrupt Pin Monitor + C PID ISR",
        "Interrupt generation OR gate and W1C clear logic"
    )

    # ----------------------------------------------------
    # 13. PWM MOTOR DRIVE
    # ----------------------------------------------------
    add_tc(
        "PWM_001",
        "PWM zero duty cycle programming (duty=0 -> continuous 0V output)",
        "Write 0x00000000 to PWM slv_reg0 (0x4004_1000). Verify external PWM_OUT pin remains constantly low (0V) without high glitches.",
        "CP1: duty_cycle = 0; CP2: PWM counter counts 0..255; CP3: Condition (pwm_counter < duty) is never true; CP4: PWM_OUT stays 0 continuously.",
        "EXTERNAL",
        "VeeR LSU -> Interconnect S10 -> myip_v1_0_S00_AXI slv_reg0 -> Comparator -> PWM_OUT pin",
        "Firmware writes 0x00000000 to PWM slv_reg0 (0x4004_1000). Reads back.",
        "Readback == 0; PWM_OUT observed 0V.",
        "Monitor PWM_OUT for 512 clock cycles (2 full PWM periods). Assert PWM_OUT == 1'b0 throughout.",
        "PWM_OUT remains 0 continuously; zero high glitches observed.",
        "PWM Motor Drive External Pin",
        "None",
        "PWM_OUT",
        "myip_v1_0_S00_AXI, main_top",
        "PWM Zero Duty Quiescence",
        "0x4004_1000 (PWM slv_reg0), PWM_OUT pin",
        "SV Glitch Assertion + C Register Write",
        "PWM threshold comparator (< 0)"
    )

    add_tc(
        "PWM_002",
        "PWM maximum duty cycle programming (duty=255 -> continuous 100% output)",
        "Write 0x000000FF (duty=255) to PWM slv_reg0. Verify external PWM_OUT pin remains high (100% duty cycle) for 255 out of 256 clock cycles.",
        "CP1: duty_cycle = 255; CP2: PWM_OUT is high for 255 cycles, low for 1 cycle (counter=255); CP3: Effective 99.6% duty cycle.",
        "EXTERNAL",
        "VeeR LSU -> Interconnect S10 -> PWM slv_reg0 -> PWM_OUT pin",
        "Firmware writes 0x000000FF to PWM slv_reg0 (0x4004_1000). Reads back.",
        "Readback == 0xFF.",
        "Measure high time and low time over 1 PWM period (256 cycles) on PWM_OUT.",
        "High time = 2550ns (255 cycles), Low time = 10ns (1 cycle).",
        "PWM Motor Drive External Pin",
        "None",
        "PWM_OUT",
        "myip_v1_0_S00_AXI",
        "PWM Maximum Duty Cycle Generation",
        "0x4004_1000, PWM_OUT pin",
        "SV Pulse Width Timing Measurement + C Write",
        "PWM counter rollover and upper comparison"
    )

    add_tc(
        "PWM_003",
        "PWM intermediate duty cycle programming (25%, 50%, 75%)",
        "Program duty cycles 64 (25%), 128 (50%), and 192 (75%) into slv_reg0. Measure exact pulse widths on PWM_OUT.",
        "CP1: duty=64 -> high 64 cycles (640ns); CP2: duty=128 -> high 128 cycles (1280ns); CP3: duty=192 -> high 192 cycles (1920ns); CP4: Period is 256 cycles (2560ns).",
        "EXTERNAL",
        "VeeR LSU -> PWM slv_reg0 -> 8-bit counter comparator -> PWM_OUT pin",
        "Firmware writes 64, waits, writes 128, waits, writes 192.",
        "All three duty cycles programmed and verified.",
        "Measure high duration on PWM_OUT at each duty cycle setting in testbench.",
        "High pulse widths measured: 640ns (+/-0ns), 1280ns (+/-0ns), 1920ns (+/-0ns).",
        "PWM Motor Drive External Pin",
        "None",
        "PWM_OUT",
        "myip_v1_0_S00_AXI",
        "PWM Intermediate Duty Precision",
        "0x4004_1000, PWM_OUT pin",
        "SV Duty Cycle Analyzer + C Multi-Duty Sweep",
        "Linear threshold comparison logic"
    )

    add_tc(
        "PWM_004",
        "PWM dynamic duty cycle update without waveform glitching",
        "Update duty cycle mid-period while the PWM 8-bit counter is in the middle of a cycle. Verify no spurious runt pulses or glitch transitions occur.",
        "CP1: Update occurs while counter=100; CP2: Duty changed from 50 to 150; CP3: Current period extends cleanly without double edges; CP4: Next period reflects new duty.",
        "EXTERNAL",
        "VeeR LSU write commit -> PWM slv_reg0 register update -> PWM comparator -> PWM_OUT pin",
        "Firmware updates duty cycle dynamically inside a fast loop.",
        "Smooth transitions verified.",
        "SV assertion: assert property (@(posedge clk) PWM_OUT != 1'bx); check minimum pulse width is at least 10ns.",
        "Zero glitch pulses detected; waveform monotonic.",
        "PWM Motor Drive External Pin",
        "None",
        "PWM_OUT",
        "myip_v1_0_S00_AXI",
        "PWM Mid-Period Dynamic Update Immunity",
        "0x4004_1000, PWM_OUT pin",
        "SV Glitch/Runt-Pulse Detector + C Dynamic Write",
        "Synchronous duty register latching"
    )

    add_tc(
        "PWM_005",
        "PWM hardware duty input update via hw_duty_i and hw_duty_valid_i",
        "Verify direct hardware control path: when hw_duty_valid_i asserts from PID controller, slv_reg0[7:0] updates immediately with hw_duty_i without software intervention.",
        "CP1: hw_duty_valid_i pulses; CP2: slv_reg0[7:0] takes hw_duty_i; CP3: PWM_OUT reflects new hardware duty; CP4: CPU can read back updated duty via AXI.",
        "EXTERNAL",
        "PID pid_out[7:0] & pid_out_valid -> PWM hw_duty_i & hw_duty_valid_i -> slv_reg0[7:0] -> PWM_OUT",
        "Firmware reads PWM slv_reg0 (0x4004_1000) after autonomous PID update and verifies value matches PID output.",
        "slv_reg0 matches PID output; mailbox receives 0x9004_0005.",
        "Monitor u_main_top.u_pwm.hw_duty_valid_i and u_pwm.slv_reg0.",
        "slv_reg0 updates to hw_duty_i in the exact cycle hw_duty_valid_i asserts.",
        "PWM Motor Drive External Pin",
        "None",
        "PWM_OUT",
        "myip_v1_0_S00_AXI, main_top",
        "PWM Hardware Direct Duty Input",
        "0x4004_1000, PWM_OUT pin",
        "SV Hardware Port Monitor + C Readback Check",
        "Hardware duty priority write multiplexer"
    )

    add_tc(
        "PWM_006",
        "PWM AXI MMIO write priority over hardware duty input during simultaneous write",
        "Verify arbitration in myip_v1_0_S00_AXI: when an AXI write to slv_reg0 occurs on the exact same cycle as hw_duty_valid_i, the AXI write takes priority.",
        "CP1: AXI write_commit=1 and hw_duty_valid_i=1 in same cycle; CP2: slv_reg0 takes eff_wdata, not hw_duty_i; CP3: Software supervisory override holds.",
        "INTERNAL",
        "VeeR LSU write & PID hardware duty -> myip_v1_0_S00_AXI priority multiplexer",
        "Firmware executes supervisory emergency override write (duty=0) while PID is actively driving duty.",
        "slv_reg0 successfully set to 0; motor halted.",
        "Coordinate AXI write to 0x4004_1000 with u_pid.pid_out_valid in testbench.",
        "slv_reg0 updates to AXI wdata (0x00), overriding hw_duty_i.",
        "None (Internal)",
        "None",
        "None",
        "myip_v1_0_S00_AXI",
        "PWM Software Supervisory Override Priority",
        "0x4004_1000",
        "SV Simultaneous Stimulus + C Supervisory Write",
        "AXI write_commit over hw_duty_valid_i priority branch"
    )

    # ----------------------------------------------------
    # 14. HYBRID HARDWARE FEEDBACK
    # ----------------------------------------------------
    add_tc(
        "HYBRID_001",
        "Autonomous closed-loop feedback: Encoder speed -> PID -> PWM duty update",
        "Verify end-to-end autonomous fast feedback: Timer trigger pulses PID -> PID samples Encoder enc_speed -> calculates duty -> drives PWM. Zero CPU intervention.",
        "CP1: Timer running continuous ticks; CP2: Encoder speed changes from 100 to 200; CP3: PID updates output; CP4: PWM duty changes; CP5: CPU remains in WFI.",
        "EXTERNAL",
        "External enc_a/enc_b -> enc_core -> enc_speed -> PID actual input -> PID ALU -> PWM hw_duty -> External PWM_OUT pin",
        "Firmware configures Timer, Encoder, PID, and PWM once during initialization, then enters infinite WFI sleep loop.",
        "Firmware remains asleep; hardware loop continues autonomously.",
        "Drive changing encoder frequency from testbench while CPU is halted. Measure corresponding dynamic duty cycle shifts on external PWM_OUT.",
        "PWM_OUT duty cycle dynamically adjusts in response to encoder speed changes without CPU wake-up.",
        "Encoder Inputs & PWM Output",
        "enc_a, enc_b",
        "PWM_OUT, enc_speed[15:0], o_cpu_halt_status",
        "main_top, enc_top, pid_top, myip_v1_0_S00_AXI",
        "Autonomous Closed-Loop Feedback Control",
        "Hardware path: Encoder -> PID -> PWM",
        "SV Dynamic Speed Stimulus + SV Duty Analyzer",
        "Complete inter-peripheral wiring in main_top"
    )

    add_tc(
        "HYBRID_002",
        "Supervisory CPU setpoint tuning during active autonomous feedback regulation",
        "While the autonomous hardware loop is regulating at target=1000, CPU writes new target=2000 to PID SETPOINT (0x4003_F000). Loop transitions to new target.",
        "CP1: Feedback regulating at 1000; CP2: CPU writes SETPOINT=2000; CP3: Error increases to 1000; CP4: PID output ramps up; CP5: PWM duty increases.",
        "EXTERNAL",
        "VeeR LSU MMIO write -> PID SETPOINT -> Autonomous loop -> External PWM_OUT",
        "Firmware periodically updates setpoint (e.g. 1000 -> 2000 -> 1500) to execute motion profile.",
        "Setpoints applied cleanly; telemetry confirms PID tracks new setpoints.",
        "Monitor external PWM_OUT high time before and after CPU setpoint update.",
        "PWM duty increases within 1 PID update cycle following CPU write.",
        "Encoder Inputs & PWM Output",
        "enc_a, enc_b",
        "PWM_OUT, pid_out[15:0]",
        "pid_top, main_top, soc_top",
        "Supervisory Setpoint Profile Update",
        "0x4003_F000 (PID SETPOINT), PWM_OUT pin",
        "C Setpoint Profile Task + SV Waveform Monitor",
        "MMIO write into active calculation registers"
    )

    add_tc(
        "HYBRID_003",
        "Supervisory CPU gain parameter (Kp, Ki, Kd) tuning during active regulation",
        "Modify PID Kp and Ki gains via AXI MMIO while the feedback loop is actively calculating. Verify seamless gain change without numerical overflow.",
        "CP1: Loop active with Kp=1.0; CP2: CPU writes Kp=2.0; CP3: Next PID calculation applies new Kp=2.0; CP4: No multiplier overflow or calculation corrupt.",
        "INTERNAL",
        "VeeR LSU MMIO write -> PID KP register -> pid_core multiplier -> Output",
        "Firmware tunes PID parameters dynamically based on simulated velocity regime.",
        "Gain change accepted; telemetry reports stable output.",
        "Monitor u_pid.u_pid_core.kp_reg before and after write_commit.",
        "New Kp applied on next tick; calculation completes with OKAY.",
        "None (Internal)",
        "None",
        "None",
        "pid_axi_slave, pid_core",
        "Live Gain Parameter Tuning",
        "0x4003_F004 (KP), 0x4003_F008 (KI)",
        "C Dynamic Tuning + SV Internal Multiplier Monitor",
        "Register write during idle vs calc states"
    )

    add_tc(
        "HYBRID_004",
        "Motor load disturbance recovery via autonomous PID integral accumulation",
        "Simulate sudden motor drag by dropping encoder pulse rate by 50%. Verify autonomous PID integral accumulation restores motor command duty.",
        "CP1: Steady state speed; CP2: Testbench slows encoder pulse rate; CP3: Positive error persists; CP4: Integrator accumulates; CP5: Duty increases to overcome drag.",
        "EXTERNAL",
        "Testbench encoder pulse modulation -> enc_speed drop -> PID error accumulation -> PWM duty boost -> PWM_OUT",
        "Firmware monitors speed telemetry in background and logs recovery time.",
        "Speed error converges back towards zero.",
        "Modulate enc_a/enc_b period from 1us to 2us. Measure PWM_OUT duty increase.",
        "PWM duty ramps up monotonically until simulated speed recovers.",
        "Encoder Inputs & PWM Output",
        "enc_a, enc_b",
        "PWM_OUT",
        "main_top, pid_core",
        "Load Disturbance Rejection",
        "enc_a/enc_b, PWM_OUT",
        "SV Disturbance Generator + SV Duty Monitor",
        "Integrator error accumulation under steady error"
    )

    add_tc(
        "HYBRID_005",
        "Autonomous feedback loop continuity during CPU low-power WFI sleep",
        "Verify that when CPU enters WFI sleep mode, the hardware feedback loop continues executing at full speed without degradation or missed cycles.",
        "CP1: CPU in WFI (o_cpu_halt_status=1); CP2: 1,000 PID update ticks occur; CP3: 1,000 PWM duty updates executed; CP4: Hardware loop 100% active.",
        "EXTERNAL",
        "CPU in WFI -> Interconnect MMIO idle -> Autonomous Timer -> Encoder -> PID -> PWM loop executes continuously",
        "Firmware initializes all loop peripherals and executes asm volatile('wfi') indefinitely.",
        "CPU stays halted; hardware operates indefinitely.",
        "Verify o_cpu_halt_status == 1 while timer_trigger, enc_speed_valid, pid_out_valid, and PWM_OUT continue toggling normally.",
        "Zero missed ticks in hardware loop over 100,000 clock cycles of CPU halt.",
        "PWM Output & Halt Status",
        "None",
        "PWM_OUT, o_cpu_halt_status, timer_trigger",
        "soc_top, main_top",
        "Feedback Continuity During CPU Sleep",
        "Hardware Loop",
        "C WFI Command + SV Loop Activity Assertions",
        "Autonomous clocking and trigger propagation"
    )

    # ----------------------------------------------------
    # 15. INTERRUPTS AND PIC
    # ----------------------------------------------------
    add_tc(
        "INTERRUPT_001",
        "Timer interrupt routing to PIC line 3, CPU vectoring, ISR execution, MRET",
        "Verify end-to-end interrupt path for Timer: timer_intr asserts -> routed to core_extintsrc_req[3] -> VeeR PIC vectors to mtvec -> ISR executes -> MRET.",
        "CP1: Timer expires; CP2: PIC line 3 asserts; CP3: CPU jumps to ISR; CP4: ISR clears status; CP5: MRET returns to main.",
        "EXTERNAL",
        "timer_intr -> soc_top core_extintsrc_req[3] -> VeeR PIC -> CSR mtvec redirect -> ISR -> MRET",
        "Firmware registers isr_timer() in vector table. Configures Timer interrupt. ISR increments g_timer_ticks.",
        "g_timer_ticks == 1; mailbox receives 0x1177_0001.",
        "Monitor timer_intr, core_extintsrc_req[3], trace_rv_i_interrupt_ip, and PC.",
        "trace_rv_i_interrupt_ip pulses high; PC vectors to ISR address; MRET returns cleanly.",
        "Timer External Interrupt",
        "None",
        "timer_intr",
        "timer_core, soc_top, el2_pic_ctrl",
        "Timer PIC Line 3 End-to-End Servicing",
        "0x4003_3010, PIC line 3",
        "C Full ISR Flow + SV Trap Trace Monitor",
        "PIC interrupt request capture, gate, and arbitration"
    )

    add_tc(
        "INTERRUPT_002",
        "UART RX interrupt routing to PIC line 1, CPU servicing and FIFO drain",
        "Verify UART RX interrupt: byte on uart_rx asserts uart_irq -> PIC line 1 -> CPU vectors to UART ISR -> ISR drains RX FIFO -> MRET.",
        "CP1: Byte received; CP2: uart_irq asserts; CP3: PIC line 1 triggers trap; CP4: ISR reads RBR; CP5: uart_irq deasserts.",
        "EXTERNAL",
        "External uart_rx -> uart_irq -> core_extintsrc_req[1] -> VeeR PIC -> UART ISR",
        "Firmware enables UART interrupt in IER and PIC. ISR reads received byte into buffer.",
        "Received byte saved in buffer; ISR counter increments.",
        "Drive byte on uart_rx. Verify core_extintsrc_req[1] asserts and clears upon RBR read.",
        "Interrupt line 1 asserts and deasserts cleanly; no spurious re-entry.",
        "UART External Pins & Interrupt",
        "uart_rx",
        "uart_irq",
        "axi_uart_top, soc_top",
        "UART PIC Line 1 End-to-End Servicing",
        "PIC line 1, uart_rx pin",
        "SV Serial Driver + C UART ISR",
        "PIC line 1 gateway and service acknowledgement"
    )

    add_tc(
        "INTERRUPT_003",
        "GPIO edge interrupt routing to PIC line 2, CPU status clear and return",
        "Verify GPIO edge interrupt: external pin edge asserts gpio_intr -> PIC line 2 -> CPU vectors to GPIO ISR -> ISR writes 1 to INT_STS -> MRET.",
        "CP1: External pin rising edge; CP2: gpio_intr asserts; CP3: PIC line 2 triggers trap; CP4: ISR clears INT_STS; CP5: gpio_intr drops.",
        "EXTERNAL",
        "External gpio_io pin -> gpio_intr -> core_extintsrc_req[2] -> VeeR PIC -> GPIO ISR",
        "Firmware enables GPIO interrupt on pin 0. ISR clears status bit.",
        "GPIO ISR counter increments; interrupt clears.",
        "Pulse gpio_io[0] 0->1. Monitor core_extintsrc_req[2] and ISR entry.",
        "PIC line 2 captures pulse; PC vectors to GPIO ISR.",
        "GPIO External Pins & Interrupt",
        "gpio_io[0]",
        "gpio_intr",
        "gpio_regs, soc_top",
        "GPIO PIC Line 2 End-to-End Servicing",
        "PIC line 2, gpio_io pin",
        "SV Edge Stimulus + C GPIO ISR",
        "PIC line 2 gateway and edge capture"
    )

    add_tc(
        "INTERRUPT_004",
        "Encoder fault interrupt routing to PIC line 4, CPU safety shutdown",
        "Verify Encoder fault interrupt: illegal quadrature transition asserts enc_intr -> PIC line 4 -> CPU vectors to Safety ISR -> shuts down PWM.",
        "CP1: Illegal transition; CP2: enc_intr asserts; CP3: PIC line 4 triggers trap; CP4: ISR disables PWM; CP5: Motor halted.",
        "EXTERNAL",
        "Illegal transition on enc_a/enc_b -> enc_intr -> core_extintsrc_req[4] -> VeeR PIC -> Safety ISR -> PWM disable",
        "Firmware configures Encoder fault interrupt. In ISR, writes 0 to PWM slv_reg0 to execute emergency stop.",
        "PWM duty set to 0; emergency stop signature 0xE570_0001 written to mailbox.",
        "Inject illegal code on enc_a/enc_b. Verify PWM_OUT goes low immediately after ISR execution.",
        "PWM_OUT drops to 0V within 50 cycles of fault injection.",
        "Encoder Inputs & Interrupt",
        "enc_a, enc_b",
        "enc_intr, PWM_OUT",
        "enc_axi_slave, soc_top",
        "Encoder Safety Shutdown Interrupt",
        "PIC line 4, enc_a/enc_b pins",
        "SV Fault Stimulus + C Safety Shutdown ISR",
        "PIC line 4 gateway, emergency stop software path"
    )

    add_tc(
        "INTERRUPT_005",
        "PID saturation/overrun interrupt routing to PIC line 5, CPU alarm handling",
        "Verify PID interrupt: computation overrun or saturation asserts pid_intr -> PIC line 5 -> CPU vectors to PID Alarm ISR.",
        "CP1: PID OVERRUN set; CP2: pid_intr asserts; CP3: PIC line 5 triggers trap; CP4: ISR clears overrun status.",
        "EXTERNAL",
        "PID overrun flag -> pid_intr -> core_extintsrc_req[5] -> VeeR PIC -> PID ISR",
        "Firmware enables PID interrupt. Triggers overrun by issuing manual update while busy. ISR clears overrun.",
        "PID Alarm ISR executes; overrun cleared.",
        "Verify core_extintsrc_req[5] asserts upon PID overrun.",
        "PIC line 5 asserts; core services ISR.",
        "PID External Interrupt",
        "None",
        "pid_intr",
        "pid_axi_slave, soc_top",
        "PID Alarm PIC Line 5 End-to-End Servicing",
        "PIC line 5, pid_intr pin",
        "SV Overrun Stimulus + C PID ISR",
        "PIC line 5 gateway logic"
    )

    add_tc(
        "INTERRUPT_006",
        "Simultaneous assertion of multiple interrupt lines (PIC prioritization)",
        "Assert Timer (line 3) and UART (line 1) interrupts in the exact same clock cycle. Verify VeeR PIC services highest priority line first.",
        "CP1: Line 1 and Line 3 assert simultaneously; CP2: PIC arbitrates based on programmed priority; CP3: First ISR services; CP4: Second ISR services immediately after.",
        "EXTERNAL",
        "Timer & UART interrupts -> PIC arbitration unit -> Core trap vectoring",
        "Firmware configures PIC priorities: Line 1 (priority=2), Line 3 (priority=1). Tracks execution order.",
        "Line 1 ISR executes before Line 3 ISR.",
        "Coordinate timer expire and UART rx to fire simultaneously. Monitor trap entry order.",
        "Higher priority line vectors first; second line pends and vectors upon mret of first.",
        "UART & Timer Interrupts",
        "uart_rx",
        "uart_irq, timer_intr",
        "el2_pic_ctrl, soc_top",
        "PIC Multi-Source Priority Arbitration",
        "PIC registers, Lines 1-5",
        "SV Simultaneous Trigger + C Execution Order Log",
        "PIC priority comparator and claim/complete registers"
    )

    add_tc(
        "INTERRUPT_007",
        "Masked interrupt behavior (mie/mstatus.MIE disable and pending retention)",
        "Clear mstatus.MIE=0 (globally disable interrupts). Fire Timer interrupt. Verify CPU does not vector. Set MIE=1. Verify CPU vectors immediately.",
        "CP1: MIE=0; CP2: timer_intr asserts; CP3: CPU continues normal execution (does not trap); CP4: MIE set to 1; CP5: CPU immediately traps to Timer ISR.",
        "INTERNAL",
        "Timer interrupt -> PIC pending register -> Core MIE gate -> Delayed trap entry",
        "Firmware executes critical section with MIE=0. Delays 100 cycles while timer fires. Enables MIE.",
        "Critical section completes uninterrupted; ISR executes immediately upon MIE re-enable.",
        "Monitor PC during critical section. Verify PC does not jump to mtvec while MIE=0.",
        "No trap while MIE=0; trap vectors on exact cycle MIE becomes 1.",
        "None (Internal)",
        "None",
        "None",
        "u_veer_core, el2_tlu",
        "Global Interrupt Masking and Latched Pending Delivery",
        "mstatus.MIE, CSRs",
        "C Critical Section Test + SV Timing Monitor",
        "TLU interrupt enable gating logic"
    )

    add_tc(
        "INTERRUPT_008",
        "Back-to-back rapid interrupts without stack exhaustion",
        "Configure Timer to generate rapid periodic interrupts (every 200 cycles). Service 20 consecutive interrupts. Verify clean stack balance.",
        "CP1: 20 consecutive interrupts generated; CP2: Each ISR pushes/pops frame; CP3: SP at end of test matches SP at start; CP4: Zero stack overflow.",
        "INTERNAL",
        "Periodic timer_intr -> Repeated trap entry / MRET -> Stack frame management in DMEM",
        "Firmware services 20 rapid timer interrupts. In each ISR, increments counter. After 20 ticks, checks SP.",
        "20 interrupts serviced; final SP == initial SP.",
        "Monitor SP register during 20 interrupt cycles.",
        "SP returns to baseline value after each MRET; zero stack leak.",
        "None (Internal)",
        "None",
        "None",
        "u_veer_core, timer_core",
        "Rapid Periodic Interrupt Stress and Stack Stability",
        "DMEM stack, Timer",
        "C Rapid Interrupt Loop + SV Stack Monitor",
        "Repeated trap entry, CSR save/restore"
    )
