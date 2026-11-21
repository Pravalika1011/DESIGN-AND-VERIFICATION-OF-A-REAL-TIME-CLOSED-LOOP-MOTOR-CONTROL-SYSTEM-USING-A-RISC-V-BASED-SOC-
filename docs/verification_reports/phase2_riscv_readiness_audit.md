# Phase 2 Independent Sign-Off Audit: Readiness for RISC-V Connection

**Project**: RISC-V Fail-Safe Railway Level-Crossing Motor Speed Control SoC  
**Repository Workspace**: `/home/student/Downloads/090_honrors/CBP`  
**Audit Scope**: Independent Read-Only RTL, Testbench, and Simulation Log Verification  
**Date**: October 17, 2026  
**Auditor**: Antigravity Technical Audit Agent  

---

## 1. Executive Summary & Audit Purpose

Following the declared completion of Phase 2, this independent audit was conducted on the physical codebase located strictly within `/home/student/Downloads/090_honrors/CBP`. The objective is to independently verify whether the RTL, interconnect, peripheral adaptations, and hardware hybrid feedback loop are structurally sound, completely verified, and genuinely ready for RISC-V processor connection in Phase 3.

This audit is based exclusively on read-only static code inspection of the RTL source files, testbench implementations, simulation scripts, and simulation run logs.

### Key Audit Findings at a Glance
1. **RTL Connectivity**: All three AXI4 master interfaces (M0, M1, M2) and all fifteen slave interfaces (S0–S14) in [rtl/main_top.v](file:///home/student/Downloads/090_honrors/CBP/rtl/main_top.v) are correctly mapped, parameterized, and connected to their respective submodules or exposed top-level ports.
2. **Hardware Hybrid Feedback**: The closed-loop control path (`enc_speed -> pid_actual`, `timer_trigger -> pid_tick`, `pid_out -> pwm_duty`, `PWM_OUT -> motor plant -> enc_a/enc_b`) is fully implemented in hardware with a 16-bit signed to 8-bit unsigned saturation clamp in [rtl/main_top.v](file:///home/student/Downloads/090_honrors/CBP/rtl/main_top.v) and a single synchronous sequential driver in [rtl/PWM/myip_v1_0_S00_AXI.v](file:///home/student/Downloads/090_honrors/CBP/rtl/PWM/myip_v1_0_S00_AXI.v). Software AXI writes have verified precedence over hardware duty updates.
3. **Verification Evidence**: All 20,392 claimed checks (or 23,519 checks when counting individual assertions in the encoder suite) were confirmed through VCS compilation and simulation logs. Zero compilation errors, zero elaboration warnings, and zero failed test checks were recorded.
4. **RISC-V Connection Prerequisites**:
   - Master M0 (IFU) provides full AXI4 write and read ports; if the future RISC-V instruction fetch unit is read-only, its write channels must be tied off at the processor boundary.
   - IMEM (S0) and DMEM (S1) are exposed as external slave ports of [rtl/main_top.v](file:///home/student/Downloads/090_honrors/CBP/rtl/main_top.v); no on-chip SRAM controller or boot ROM is instantiated inside `main_top.v`. Memory controllers must be bound in Phase 3.
   - All five peripheral interrupts are exposed as top-level ports. An interrupt controller (PLIC or PIC) is required in Phase 3 to aggregate these interrupts for the core.

---

## 2. Top-Level RTL & AXI Connectivity Audit

### 2.1 Master Interfaces (M0, M1, M2)
In [rtl/main_top.v](file:///home/student/Downloads/090_honrors/CBP/rtl/main_top.v), three master interfaces connect to [axi_interconnect_wrap_3x15.v](file:///home/student/Downloads/090_honrors/CBP/rtl/interconnect/axi_interconnect_wrap_3x15.v):
- **M0 (`s00_axi_*`)**: Designated for the VeeR EL2 Instruction Fetch Unit (IFU). Configured with `ID_WIDTH=8`, `ADDR_WIDTH=32`, `DATA_WIDTH=32`, `STRB_WIDTH=4`.
- **M1 (`s01_axi_*`)**: Designated for the VeeR EL2 Load/Store Unit (LSU). Configured with `ID_WIDTH=8`, `ADDR_WIDTH=32`, `DATA_WIDTH=32`, `STRB_WIDTH=4`.
- **M2 (`s02_axi_*`)**: Designated for the System DMA Controller. Configured identically to M0/M1.

All three masters arbitrate across all 15 slaves via the round-robin/priority arbiter in [rtl/interconnect/arbiter.v](file:///home/student/Downloads/090_honrors/CBP/rtl/interconnect/arbiter.v).

### 2.2 Complete 15-Slave Interconnect Slot Verification

| Slot | Slave Module | Implementation Type | Base Address | Aperture | Actual Decode Behavior | Audit Status |
|:---:|:---|:---|:---:|:---:|:---|:---:|
| **S0** | IMEM | External Port | `0x0004_0000` | 128 KiB | Forwarded to `m00_axi_*` | **VERIFIED** |
| **S1** | DMEM | External Port | `0x0008_0000` | 128 KiB | Forwarded to `m01_axi_*` | **VERIFIED** |
| **S2** | GPIO | Internal IP (`gpio_axi`) | `0x4003_1000` | 4 KiB | Adapter `{20'h0, addr[11:0]}`, OKAY | **VERIFIED** |
| **S3** | Timer | Internal IP (`timer_axi`) | `0x4003_3000` | 4 KiB | Adapter `{20'h0, addr[11:0]}`, OKAY | **VERIFIED** |
| **S4** | UART | Internal IP (`axi_uart_top`) | `0x4003_5000` | 4 KiB | Direct `addr[4:0]`, Modulo-32 OKAY | **VERIFIED** |
| **S5** | Reserved | Interconnect Internal | `0x0000_0000` | 0 KiB | Width=0, returns **DECERR (2'b11)** | **VERIFIED** |
| **S6** | Reserved | Interconnect Internal | `0x0000_0000` | 0 KiB | Width=0, returns **DECERR (2'b11)** | **VERIFIED** |
| **S7** | Reserved | Interconnect Internal | `0x0000_0000` | 0 KiB | Width=0, returns **DECERR (2'b11)** | **VERIFIED** |
| **S8** | Encoder | Internal IP (`enc_top`) | `0x4003_D000` | 4 KiB | Direct `.ADDR_WIDTH(12)`, **SLVERR (2'b10)** on $\ge 0\text{x}100$ | **VERIFIED** |
| **S9** | PID | Internal IP (`pid_top`) | `0x4003_F000` | 4 KiB | Direct `.ADDR_WIDTH(12)`, **SLVERR (2'b10)** on $\ge 0\text{x}100$ | **VERIFIED** |
| **S10** | PWM | Internal IP (`myip_v1_0`) | `0x4004_1000` | 4 KiB | Direct `addr[3:0]`, Modulo-16 OKAY | **VERIFIED** |
| **S11** | WDT | External Port | `0x8000_4000` | 4 KiB | Forwarded to `m11_axi_*` | **VERIFIED** |
| **S12** | ADC | External Port | `0x8000_5000` | 4 KiB | Forwarded to `m12_axi_*` | **VERIFIED** |
| **S13** | DMA | External Port | `0x8000_6000` | 4 KiB | Forwarded to `m13_axi_*` | **VERIFIED** |
| **S14** | Seven-Seg | Interconnect Internal | `0x0000_0000` | 0 KiB | Width=0, returns **DECERR (2'b11)** | **VERIFIED** |

### 2.3 Individual Peripheral Submodule Connections in `main_top.v`
- **GPIO (S2, `u_gpio`)**:
  - Instantiates `gpio_axi` with `.NUM_BITS(32)`.
  - Driven by `clk` and `~rst`.
  - Address connections: `{20'h00000, m02_axi_awaddr[11:0]}` and `{20'h00000, m02_axi_araddr[11:0]}`.
  - External I/O: `.io(gpio_io)` (inout 32b) and `.intr(gpio_intr)` (output).
  - Unconnected ports: None.
- **Timer (S3, `u_timer`)**:
  - Instantiates `timer_axi`.
  - Driven by `clk` and `~rst`.
  - Address connections: `{20'h00000, m03_axi_awaddr[11:0]}` and `{20'h00000, m03_axi_araddr[11:0]}`.
  - Functional connections: `.ext_meas_i(timer_ext_meas)`, `.capture_i(timer_capture)`, `.pwm_o(timer_pwm)`, `.trigger_o(timer_trigger)`, `.irq(timer_intr)`.
  - Unconnected ports: None.
- **UART (S4, `u_axi_uart`)**:
  - Instantiates `axi_uart_top`.
  - Driven by `clk`, `fixed_clk`, and `~rst`.
  - ID connection: `axi_awid_i({4'b0000, m04_axi_awid})`, `axi_bid_o(uart_bid_w)` with `m04_axi_bid = uart_bid_w[7:0]`.
  - Functional connections: `.read_interrupt_o(uart_irq)`, `.uart_rx_i(uart_rx)`, `.uart_tx_o(uart_tx)`.
  - Unconnected ports: None.
- **Encoder (S8, `u_encoder`)**:
  - Instantiates `enc_top` with `.ADDR_WIDTH(12)`, `.DATA_WIDTH(32)`, `.ID_WIDTH(8)`.
  - Driven by `clk` and `~rst`.
  - Address connections: `m08_axi_awaddr[11:0]` and `m08_axi_araddr[11:0]`.
  - Functional connections: `.enc_a_i(enc_a)`, `.enc_b_i(enc_b)`, `.enc_index_i(enc_index)`, `.drive_active_i(enc_drive_active)`.
  - Status/Feedback outputs: `.speed_o(enc_speed)`, `.speed_valid_o(enc_speed_valid)`, `.count_valid_o(enc_count_valid)`, `.dir_o(enc_dir)`, `.fault_o(enc_fault)`, `.inta_o(enc_intr)`.
  - Unconnected ports: None.
- **PID Controller (S9, `u_pid`)**:
  - Instantiates `pid_top` with `.ADDR_WIDTH(12)`, `.DATA_WIDTH(32)`, `.ID_WIDTH(8)`.
  - Driven by `clk` and `~rst`.
  - Address connections: `m09_axi_awaddr[11:0]` and `m09_axi_araddr[11:0]`.
  - Hardware feedback connections: `.tick_i(timer_trigger)`, `.actual_i(enc_speed)`.
  - Output connections: `.pid_out_o(pid_out)`, `.pid_out_valid_o(pid_out_valid)`, `.sat_flag_o(pid_sat_flag)`, `.inta_o(pid_intr)`.
  - Submodule `u_pid_axi_slave` connection: `.reg_irq_en_o(w_reg_irq_en)` properly connected, resolving previous `TFIPC` warning.
  - Unconnected ports: None.
- **PWM Generator (S10, `u_pwm_s10`)**:
  - Instantiates `myip_v1_0` with `C_S00_AXI_ADDR_WIDTH(4)`, `C_S00_AXI_DATA_WIDTH(32)`.
  - Driven by `clk` and `~rst`.
  - Address connections: `m10_axi_awaddr[3:0]` and `m10_axi_araddr[3:0]`.
  - Hardware duty input: `.hw_duty_i(pid_to_pwm_duty)`, `.hw_duty_valid_i(pid_out_valid)`.
  - Functional output: `.PWM_OUT(PWM_OUT)`.
  - AXI4-Lite adaptation: `m10_axi_bid` and `m10_axi_rid` tied to zero; `m10_axi_rlast` assigned `pwm_rvalid_w`.
  - Unconnected ports: None.

### 2.4 Documented vs RTL Discrepancies
- **Discrepancy 1 (Cosmetic Header Comment)**: In [rtl/main_top.v](file:///home/student/Downloads/090_honrors/CBP/rtl/main_top.v) lines 16–18, the file header comment contains legacy address ranges:
  - `S2 = GPIO Controller [0x8000_1000 - 0x8000_1FFF]`
  - `S3 = Real-Time Timer [0x8000_2000 - 0x8000_2FFF]`
  - `S4 = UART Subsystem [0x8000_3000 - 0x8000_3FFF]`
  However, the **actual parameter declarations** in lines 60, 63, and 66 are:
  - `M02_BASE_ADDR = 32'h4003_1000`
  - `M03_BASE_ADDR = 32'h4003_3000`
  - `M04_BASE_ADDR = 32'h4003_5000`
  The functional parameters match `phase2_interface_freeze.md` exactly. The header comment is stale documentation.
- **Discrepancy 2 (Unused Testbench Variables)**: In [tb/tb_main_top.sv](file:///home/student/Downloads/090_honrors/CBP/tb/tb_main_top.sv) lines 348–349, variables `pid_tick_tb` and `pid_actual_tb` remain declared and initialized to 0, but are no longer connected to `main_top` because the top-level inputs were removed when the loop was closed in RTL. This is completely benign in the testbench.

---

## 3. Hardware Hybrid Feedback Path Verification

### 3.1 End-to-End Control Datapath
The RTL datapath was traced signal-by-signal:
1. **Periodic Sampling**: In [rtl/timer/timer_core.sv](file:///home/student/Downloads/090_honrors/CBP/rtl/timer/timer_core.sv), when `en && tick && !op_done` and `counter == 0`, `trigger_o` asserts for 1 clock cycle.
2. **PID Activation**: `trigger_o` drives `timer_trigger`, which feeds `u_pid.tick_i`. In [rtl/pid_controler/pid_core.v](file:///home/student/Downloads/090_honrors/CBP/rtl/pid_controler/pid_core.v), edge detector `tick_rise = tick_i & ~tick_prev` starts the FSM.
3. **Speed Feedback**: [rtl/encoder/enc_top.v](file:///home/student/Downloads/090_honrors/CBP/rtl/encoder/enc_top.v) outputs 16-bit signed `w_speed` continuously on `speed_o`. This drives `enc_speed` into `u_pid.actual_i`.
4. **PID Compute & Saturation Clamp**:
   - `pid_core.v` computes signed error `e = setpoint_i - actual_i` (17-bit math), applies Q16.16 gains, and emits `pid_out_o[15:0]` accompanied by 1-cycle strobe `pid_out_valid_o`.
   - In [rtl/main_top.v](file:///home/student/Downloads/090_honrors/CBP/rtl/main_top.v) line 2020:
     ```verilog
     wire [7:0] pid_to_pwm_duty = (pid_out[15])     ? 8'h00 :
                                  (|pid_out[14:8])  ? 8'hFF :
                                  pid_out[7:0];
     ```
     - **Negative Error**: If `pid_out[15] == 1'b1`, value clamps to `8'h00` (0% duty).
     - **Upper Overflow (> 255)**: If `|pid_out[14:8] == 1'b1`, value clamps to `8'hFF` (255/256 duty).
     - **Linear Range (0–255)**: Value passes directly as `pid_out[7:0]`.
     - **Boundary Audits**:
       - `pid_out = 16'h8000 (-32768)` $\to$ `8'h00` (clamped).
       - `pid_out = 16'hFFFF (-1)` $\to$ `8'h00` (clamped).
       - `pid_out = 16'h0000 (0)` $\to$ `8'h00`.
       - `pid_out = 16'h00FF (255)` $\to$ `8'hFF`.
       - `pid_out = 16'h0100 (256)` $\to$ `8'hFF` (clamped).
       - `pid_out = 16'h7FFF (+32767)` $\to$ `8'hFF` (clamped).
     The saturation clamp is verified to be glitch-free and mathematically correct.
5. **PWM Duty Update & Arbiter Priority**:
   - In [rtl/PWM/myip_v1_0_S00_AXI.v](file:///home/student/Downloads/090_honrors/CBP/rtl/PWM/myip_v1_0_S00_AXI.v) lines 268–290:
     ```verilog
     always @(posedge S_AXI_ACLK) begin
         if (!S_AXI_ARESETN) begin
             slv_reg0 <= 0; ...
         end else begin
             if (hw_duty_valid_i) begin
                 slv_reg0[7:0] <= hw_duty_i;
             end
             if (write_commit) begin
                 case (eff_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS : ADDR_LSB])
                     2'h0: for (byte_index = 0; ...)
                               if (eff_wstrb[byte_index])
                                   slv_reg0[(byte_index*8) +: 8] <= eff_wdata[(byte_index*8) +: 8];
                     ...
     ```
   - **Precedence Verification**: In Verilog procedural execution, when `write_commit` and `hw_duty_valid_i` are true simultaneously, the AXI write occurs later in the procedural block and overwrites the hardware duty update. Software intervention maintains strict priority.
   - **Driver Integrity**: `slv_reg0` has exactly one sequential driver. There are no multiple drivers and no inferred latches.
6. **PWM Waveform Output**:
   - In [rtl/PWM/myip_v1_0_S00_AXI.v](file:///home/student/Downloads/090_honrors/CBP/rtl/PWM/myip_v1_0_S00_AXI.v) line 386:
     ```verilog
     assign PWM_OUT = (pwm_counter < duty_cycle) ? 1'b1 : 1'b0;
     ```
   - The counter is purely synchronous, runs continuously modulo-256, and produces glitchless PWM pulses.

---

## 4. Independent Verification of Simulation Logs & Results

The actual simulation logs residing in `run/` and `run/logs/` were inspected and verified:

### 4.1 Suite 1: Top-Level AXI Interconnect Integration
- **Script**: `run/run_main.sh`
- **Testbench**: [tb/tb_main_top.sv](file:///home/student/Downloads/090_honrors/CBP/tb/tb_main_top.sv)
- **Log Files**: `run/compile.log`, `run/sim.log`
- **Compiler Output**: VCS U-2023.03, `0 error(s), 0 warning(s)`.
- **Simulation Time**: 353,945,000 ps (353.945 $\mu$s).
- **Result**: **157 checks executed, 157 passed, 0 failed**.
- **Coverage of Critical Tests**:
  - Valid and invalid address decoding for all 15 slave slots.
  - S8/S9 `SLVERR` generation on out-of-range offsets.
  - S5/S6/S7/S14 `DECERR` generation on unmapped address accesses.
  - Simultaneous multi-master routing (M0, M1, M2 accessing S10 PWM and S8/S9).
  - Independent AW/W channel arrivals: AW-before-W (8 cycles), W-before-AW (8 cycles), and simultaneous AW+W.

### 4.2 Suite 2: Dedicated Hardware Hybrid Feedback
- **Script**: `run/run_feedback.sh`
- **Testbench**: [tb/tb_hybrid_feedback.sv](file:///home/student/Downloads/090_honrors/CBP/tb/tb_hybrid_feedback.sv)
- **Log Files**: `run/compile_feedback.log`, `run/sim_feedback.log`
- **Compiler Output**: VCS U-2023.03, `0 error(s), 0 warning(s)`.
- **Simulation Time**: 17,125,000 ps (17.125 $\mu$s).
- **Result**: **43 checks executed, 43 passed, 0 failed**.
- **Coverage of Critical Tests**:
  - Safe power-on reset state (`PWM_OUT=0`, `duty=0`, `speed=0`).
  - Timer periodic triggering (5 triggers observed in 300 cycles).
  - Autonomous closed-loop execution with active behavioral motor plant model.
  - Concurrent AXI transactions to Timer, Encoder, PID, GPIO, UART during active loop.
  - Saturation limiting (setpoint 1280 clamped to `8'hFF`).
  - Negative error clamping (setpoint 0 clamped to `8'h00`).
  - Loop disable transition (PID disabled, 0 updates emitted, manual duty held).
  - AXI software write priority over hardware duty update (`slv_reg0 = 0xAA`).
  - Reset recovery during active loop.

### 4.3 Suite 3: Standalone Quadrature Encoder
- **Script**: `run/run_enc.sh`
- **Testbench**: `tb/enc_tb.v`
- **Log Files**: `run/logs/enc_compile.log`, `run/logs/enc_sim.log`
- **Simulation Time**: 1,520,150,000 ps (1.52 ms).
- **Result**: **10 test suites passed (comprising 3,137 individual assertion checks, 0 failed)**.
- **Coverage**: Reset values, register write/readback, address decoding & SLVERR, AXI protocol delays & backpressure, x1/x2/x4 quadrature decoding, illegal state transitions, glitch filter thresholds, speed calculation windows, stall timeouts, and 3,000-iteration random burst regression.

### 4.4 Suite 4: Standalone PID Controller
- **Script**: `run/run_pid.sh`
- **Testbench**: `tb/pid_tb/pid_tb.v`
- **Log Files**: `run/logs/pid_sim.log`, `run/compile.log`
- **Simulation Time**: 3,846,445,000 ps (3.84 ms).
- **Result**: **20,176 checks executed, 20,176 passed, 0 failed**.
- **Coverage**: Reset values, register read/write, address decoding & SLVERR, AXI protocol handshakes, tick edge detection, P/I/D math accuracy against bit-exact reference model, anti-windup clamping, extreme values, status flags & IRQs, 20,000 random stimulus iterations, and closed-loop motor disturbance recovery.

### 4.5 Suite 5: Standalone PWM Generator
- **Script**: `run/run_pwm.sh`
- **Testbench**: [tb/tb_pwm_axi.sv](file:///home/student/Downloads/090_honrors/CBP/tb/tb_pwm_axi.sv)
- **Log Files**: `run/compile_pwm.log`, `run/sim_pwm.log`
- **Simulation Time**: 13,345,000 ps (13.345 $\mu$s).
- **Result**: **6 tests executed, 6 passed, 0 failed**.
- **Coverage**: Register write/readback, 0% duty cycle, 25% duty cycle, 50% duty cycle, 75% duty cycle, and 100% duty cycle.

### 4.6 Verification Count Reconciliations
- **Reported in Completion Summary**: $157 + 43 + 10 + 20,176 + 6 = 20,392$ checks.
- **Detailed Assertion Count**: The Encoder test reports 10 high-level test stages (`[TEST 01]` to `[TEST 10]`), each containing dozens to thousands of checks, totaling 3,137 passed assertions. If counted at the assertion level, the total verified checks across the SoC are:
  $$157 + 43 + 3,137 + 20,176 + 6 = 23,519 \text{ passing checks (0 failures)}$$

---

## 5. Clocks, Resets, and Interrupt Architecture

### 5.1 Clock Distribution
- **`clk` (Primary System Clock)**:
  - 100 MHz nominal.
  - Synchronously clocks the AXI interconnect, all master ports, and all peripheral slave logic (GPIO, Timer, Encoder, PID, PWM, and UART AXI bus interface).
  - No clock-domain crossing (CDC) exists between Timer, Encoder, PID, and PWM; the hybrid feedback loop is 100% synchronous to `clk`.
- **`fixed_clk` (UART Dedicated Baud Clock)**:
  - 20 MHz nominal.
  - Feeds `axi_uart_top.fixed_clk_i`.
  - CDC between `clk` and `fixed_clk` is handled internally inside [rtl/UART/axi_uart_top.v](file:///home/student/Downloads/090_honrors/CBP/rtl/UART/axi_uart_top.v) via dual-clock FIFOs in [rtl/UART/axi_internal_fifo.v](file:///home/student/Downloads/090_honrors/CBP/rtl/UART/axi_internal_fifo.v).

### 5.2 Reset Scheme
- **`rst`**: Single top-level active-HIGH synchronous reset input on `main_top`.
- **Propagation**:
  - `u_axi_interconnect_3x15` receives active-high `.rst(rst)`.
  - All peripheral slaves (GPIO, Timer, UART, Encoder, PID, PWM) receive active-low `.s_axi_aresetn(~rst)`.
  - Reset inversion is performed cleanly in `main_top.v` with zero skew or gating hazards.

### 5.3 Interrupt Scheme & Phase 3 Processor Requirement
- **Interrupt Signals Exposed on `main_top`**:
  1. `uart_irq`: Driven by `u_axi_uart.read_interrupt_o` (Level, active-high). Cleared by reading `UART_RBR` or writing `UART_THR`.
  2. `gpio_intr`: Driven by `u_gpio.intr` (Level, active-high). Cleared by writing 1 to `GPIO_INT_STS`.
  3. `timer_intr`: Driven by `u_timer.irq` (Level, active-high). Cleared by writing 1 to `TIMER_INT_STS`.
  4. `enc_intr`: Driven by `u_encoder.inta_o` (Level, active-high). Cleared by writing 1 to `ENC_STATUS`.
  5. `pid_intr`: Driven by `u_pid.inta_o` (Level, active-high). Cleared by writing 1 to `PID_STATUS[1]` (DONE) or `PID_STATUS[5]` (OVERRUN).
- **Phase 3 Requirement**:
  There is currently **NO interrupt controller** (PLIC or PIC) inside `main_top.v`. In Phase 3, when connecting the RISC-V core, an interrupt controller must be provided, or these 5 interrupt lines must be mapped to the core's fast interrupt inputs (`meip` / `fast_irq[*]`).

---

## 6. Readiness for RISC-V Processor Connection (Phase 3 Contract)

The RISC-V processor is **NOT** connected, and no software/firmware boot test has been performed. The following interface contract is established for Phase 3:

### 6.1 Bus Master Interface Contract
1. **Instruction Fetch Unit (IFU $\to$ M0 `s00_axi_*`)**:
   - Must drive standard AXI4 read channels (`araddr`, `arlen`, `arsize`, `arburst`, `arvalid`, `rready`).
   - If the core IFU does not perform writes, write channel ports (`awvalid`, `wvalid`, `bready`) must be tied to 0 at the core instantiation boundary.
   - Address aperture: IFU must target IMEM at `0x0004_0000`–`0x0005_FFFF` (128 KiB).
2. **Load/Store Unit (LSU $\to$ M1 `s01_axi_*`)**:
   - Drives full AXI4 read and write transactions.
   - Must support 32-bit aligned addresses with appropriate `wstrb` byte enables for 8-bit, 16-bit, and 32-bit accesses.
   - Must handle `OKAY (2'b00)`, `SLVERR (2'b10)` (from Encoder/PID on illegal register offsets), and `DECERR (2'b11)` (from unmapped/reserved slots S5/S6/S7/S14).
3. **Transaction IDs**:
   - The interconnect parameter is `ID_WIDTH = 8`.
   - The core must provide 8-bit IDs or zero-extended IDs matching `ID_WIDTH`.
4. **Memory Subsystems (IMEM S0 & DMEM S1)**:
   - S0 and S1 are currently brought out as external ports on `main_top.v`.
   - **Phase 3 Blocker / Requirement**: SRAM blocks or memory controllers must be instantiated and bound to `m00_axi_*` and `m01_axi_*`. The core cannot boot until physical memory is wired to these ports.

---

## 7. Structural Integrity & Risk Assessment Matrix

| Item | Component / File | Audit Finding | Status | Risk / Recommended Action |
|:---|:---|:---|:---:|:---|
| **Header Comments** | [main_top.v](file:///home/student/Downloads/090_honrors/CBP/rtl/main_top.v) lines 16–18 | Comment states legacy addresses (`0x8000_1000`), but parameters use `0x4003_1000`. | **DEFECT (Doc Only)** | Low risk. Update header comment in documentation; functional RTL is correct. |
| **TFIPC Warning** | [pid_top.v](file:///home/student/Downloads/090_honrors/CBP/rtl/pid_controler/pid_top.v) line 185 | Connected `w_reg_irq_en` to `u_pid_axi_slave`. | **VERIFIED** | Zero compiler warnings. Resolved completely. |
| **PWM Duty Port** | [myip_v1_0_S00_AXI.v](file:///home/student/Downloads/090_honrors/CBP/rtl/PWM/myip_v1_0_S00_AXI.v) line 270 | Hardware duty update with AXI write precedence. | **VERIFIED** | Single sequential driver. Verified under test. |
| **Address Rejection** | `enc_top.v`, `pid_top.v` | Validates `addr[11:8]==0`; returns `SLVERR` on $\ge 0\text{x}100$. | **VERIFIED** | Prevents register aliasing across 4 KiB aperture. |
| **Address Aliasing** | `axi_uart_top.v`, `myip_v1_0.v` | Modulo-32 (UART) and Modulo-16 (PWM) aliasing across 4 KiB aperture. | **VERIFIED** | Accepted architectural design; returns `OKAY`. |
| **Decerr Generation** | `axi_interconnect.v` | Unmapped addresses or slots S5, S6, S7, S14 return `DECERR`. | **VERIFIED** | Standard AXI4 compliance verified. |
| **IMEM/DMEM Binding** | `main_top.v` ports | Memory controllers are external ports, not internal SRAMs. | **DEPENDS ON PHASE 3** | Phase 3 top-level must connect SRAM controllers to S0 and S1. |
| **Interrupt Controller** | `main_top.v` ports | 5 interrupts exposed as ports; no internal PLIC/PIC. | **DEPENDS ON PHASE 3** | Phase 3 must route interrupt ports to RISC-V core or PLIC. |
| **IFU Write Channels** | `main_top.v` port list | M0 has write channel inputs; IFU is typically read-only. | **DEPENDS ON RISC-V CORE** | Tie off unused M0 write inputs when instantiating core. |

---

## 8. Final Audit Verdicts

### Verdict A: Phase 2 Completion
**STATUS: COMPLETE**  
All six peripheral IPs are integrated into the AXI interconnect, the autonomous hardware hybrid feedback loop operates correctly in RTL without software polling, all five verification suites compile and pass with zero failures (20,392 checks), and all interfaces are documented and frozen.

### Verdict B: Top-Level Integration Readiness
**STATUS: READY**  
The interconnect, peripheral wrappers, address decoding, reset distribution, clocking, and hardware feedback datapath in [rtl/main_top.v](file:///home/student/Downloads/090_honrors/CBP/rtl/main_top.v) are structurally sound, clean of lint/compilation warnings, and verified.

### Verdict C: RISC-V Connection Readiness
**STATUS: READY FOR CONNECTION (Subject to Phase 3 System Binding)**  
The master interfaces M0 and M1 are fully verified to route read and write requests to all slaves. Connecting the RISC-V processor in Phase 3 requires:
1. Binding SRAM/memory controllers to the exposed S0 (IMEM) and S1 (DMEM) AXI ports.
2. Tying off unused M0 IFU write channel inputs if the core IFU is read-only.
3. Routing the 5 exposed peripheral interrupt signals into the core or a PLIC.
4. Ensuring the core's AXI ID width matches `ID_WIDTH = 8` (or zero-extending it).
