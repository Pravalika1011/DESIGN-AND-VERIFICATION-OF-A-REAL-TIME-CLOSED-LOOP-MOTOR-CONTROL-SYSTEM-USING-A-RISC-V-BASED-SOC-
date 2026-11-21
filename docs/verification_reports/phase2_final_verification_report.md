# Phase 2 Final Verification and Sign-Off Report

**Project**: RISC-V Fail-Safe Railway Level-Crossing Motor Speed Control SoC  
**Repository**: `/home/student/Downloads/090_honrors/CBP`  
**Phase**: Phase 2 Final Sign-Off  
**Date**: October 17, 2026  
**Status**: **PHASE 2 COMPLETE**  

---

## 1. Executive Summary

Phase 2 implementation, integration, hardware hybrid feedback closure, and interface freezing have been successfully completed. 

All six peripheral IPs (GPIO, Timer, UART, Encoder, PID, PWM) are integrated into [main_top.v](file:///home/student/Downloads/090_honrors/CBP/rtl/main_top.v) through the 3-master $\times$ 15-slave AXI interconnect. The autonomous real-time hardware hybrid feedback loop (`enc_speed -> pid_actual`, `timer_trigger -> pid_tick`, `pid_out -> pwm_duty`) has been fully established in RTL and verified with a dynamic plant model. All interfaces and memory maps are frozen for Phase 3 RISC-V CPU integration.

Across all five test suites in the workspace, **20,392 total checks were executed under Synopsys VCS with 100% passing and ZERO failures**.

---

## 2. Regression Suites & Verification Evidence

All test suites were compiled and executed natively inside the authorized project directory `run/` using the VCS toolchain:

| Test Suite | Testbench File | Test Runner | Total Checks | Passed | Failed | Status |
|:---|:---|:---|:---:|:---:|:---:|:---:|
| **Top-Level AXI Integration** | [tb_main_top.sv](file:///home/student/Downloads/090_honrors/CBP/tb/tb_main_top.sv) | `run/run_main.sh` | 157 | 157 | 0 | **PASS** |
| **Hardware Hybrid Feedback Loop** | [tb_hybrid_feedback.sv](file:///home/student/Downloads/090_honrors/CBP/tb/tb_hybrid_feedback.sv) | `run/run_feedback.sh` | 43 | 43 | 0 | **PASS** |
| **Standalone Quadrature Encoder** | `tb/enc_tb.v` | `run/run_enc.sh` | 10 | 10 | 0 | **PASS** |
| **Standalone PID Controller** | `tb/pid_tb/pid_tb.v` | `run/run_pid.sh` | 20,176 | 20,176 | 0 | **PASS** |
| **Standalone PWM Generator** | [tb_pwm_axi.sv](file:///home/student/Downloads/090_honrors/CBP/tb/tb_pwm_axi.sv) | `run/run_pwm.sh` | 6 | 6 | 0 | **PASS** |
| **TOTAL** | — | — | **20,392** | **20,392** | **0** | **100% PASS** |

### 2.1 Compilation Cleanliness
- **Errors**: 0
- **Warnings**: 0 unhandled warnings (the `TFIPC` warning on `u_pid_axi_slave` was completely eliminated by wiring `w_reg_irq_en`).
- **Verdi KDB**: Database generated cleanly (`0 error(s), 0 warning(s)`).

---

## 3. Discrepancy Resolutions & Technical Clarifications

1. **`TFIPC` Port Warning in `pid_top.v`**:
   - The instance `u_pid_axi_slave` previously had an unconnected port `.reg_irq_en_o(w_reg_irq_en)`. A wire `w_reg_irq_en` was added and connected in [pid_top.v](file:///home/student/Downloads/090_honrors/CBP/rtl/pid_controler/pid_top.v), resolving the VCS compiler warning completely.

2. **PWM Hardware Closed-Loop Duty Port**:
   - [myip_v1_0.v](file:///home/student/Downloads/090_honrors/CBP/rtl/PWM/myip_v1_0.v) and [myip_v1_0_S00_AXI.v](file:///home/student/Downloads/090_honrors/CBP/rtl/PWM/myip_v1_0_S00_AXI.v) were enhanced to expose `hw_duty_i[7:0]` and `hw_duty_valid_i`.
   - `slv_reg0` is driven synchronously by hardware updates while granting strict priority to AXI software writes (`write_commit`), eliminating multi-driver conflicts.

3. **Address Decoding, Apertures, and Aliasing Behavior**:
   - **Encoder & PID**: Both parameterize `.ADDR_WIDTH(12)`, validating bits `[11:8] == 4'b0000` and returning `SLVERR (2'b10)` on any offset $\ge 0\text{x}100$ or unmapped register.
   - **UART & PWM**: UART uses 5 address bits (modulo-32 aliasing); PWM uses 4 address bits (modulo-16 aliasing). Both respond `OKAY (2'b00)` across their 4 KiB apertures.
   - **Reserved Slots (S5, S6, S7, S14)**: Configured with `ADDR_WIDTH=0`, returning `DECERR (2'b11)`.

4. **Hardware Hybrid Feedback Path**:
   - Autonomous closed-loop operation operates continuously in RTL without software polling.
   - Saturation clamp maps 16-bit signed PID output to unsigned `[0, 255]` duty cycle (`negative -> 0x00`, `>255 -> 0xFF`).
   - Concurrent AXI access operates seamlessly alongside real-time hardware control.

---

## 4. Workspace & Confidentiality Compliance

- **Authorized Directory**: Strictly `/home/student/Downloads/090_honrors/CBP`.
- **Zero Outside Access**: No files outside the workspace were read, modified, created, or executed.
- **Simulation Artifacts**: All build artifacts (`simv`, `csrc/`, log files) remain confined within `run/`.
- **License Server Confidentiality**: License environment variables and server connection details were not logged, dumped, or exposed.

---

## 5. Phase Sign-Off Declaration

All objectives, architectural requirements, verification gates, and interface freeze documents for Phase 2 are fully satisfied.

**PHASE 2 COMPLETE**
