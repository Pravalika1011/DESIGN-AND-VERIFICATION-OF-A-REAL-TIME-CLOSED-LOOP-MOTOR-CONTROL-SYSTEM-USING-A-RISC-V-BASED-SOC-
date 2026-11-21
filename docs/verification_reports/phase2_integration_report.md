# Phase 2 — Six-IP AXI Interconnect Integration Report

**Date:** 2026-10-17  
**Project Workspace:** `/home/student/Downloads/090_honrors/CBP`  
**Author:** AI Agent (Antigravity)  
**Status:** Implementation & Verification Complete — 100% Testbench Checks Passed  

---

## Executive Summary

Phase 2 implementation integrates all six target peripheral IPs into the system top-level (`rtl/main_top.v`) via the existing 3-Master × 15-Slave AXI4 crossbar interconnect (`rtl/interconnect/axi_interconnect_wrap_3x15.v`). All six peripherals—GPIO, Timer, UART, Quadrature Encoder, PID Controller, and PWM—are mapped to their designated base addresses with 4 KiB apertures (`ADDR_WIDTH = 12`).

Verification was conducted using Synopsys VCS in directory `run/` using the updated top-level integration testbench `tb/tb_main_top.sv`. All **157 assertion checks passed with 0 errors and 0 warnings**.

---

## 1. Final Address Map & Interconnect Slave Assignments

The table below summarizes the finalized address map configured in `rtl/main_top.v`:

| Peripheral | Interconnect Slave | Base Address | Aperture | `ADDR_WIDTH` | Interface Protocol | Reset Polarity | Status |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **IMEM** | S0 (`m00_axi`) | `0x0004_0000` | 128 KiB | 17 | Full AXI4 | Active-Low | Preserved (External) |
| **DMEM** | S1 (`m01_axi`) | `0x0008_0000` | 128 KiB | 17 | Full AXI4 | Active-Low | Preserved (External) |
| **GPIO** | S2 (`m02_axi`) | `0x4003_1000` | 4 KiB | 12 | AXI4-Lite (via adapter) | Active-Low (`reset_n`) | Integrated (Internal) |
| **Timer** | S3 (`m03_axi`) | `0x4003_3000` | 4 KiB | 12 | AXI4-Lite (via adapter) | Active-Low (`aresetn`) | Integrated (Internal) |
| **UART** | S4 (`m04_axi`) | `0x4003_5000` | 4 KiB | 12 | Full AXI4 | Active-Low (`s_axi_aresetn`)| Integrated (Internal) |
| **Reserved** | S5 (`m05_axi`) | `0x0000_0000` | 0 B | 0 | Full AXI4 | — | Disabled (`WIDTH=0`) |
| **Reserved** | S6 (`m06_axi`) | `0x0000_0000` | 0 B | 0 | Full AXI4 | — | Disabled (`WIDTH=0`) |
| **Reserved** | S7 (`m07_axi`) | `0x0000_0000` | 0 B | 0 | Full AXI4 | — | Disabled (`WIDTH=0`) |
| **Encoder** | S8 (`m08_axi`) | `0x4003_D000` | 4 KiB | 12 | Full AXI4 | Active-Low (`s_axi_aresetn`)| Integrated (Internal) |
| **PID** | S9 (`m09_axi`) | `0x4003_F000` | 4 KiB | 12 | Full AXI4 | Active-Low (`s_axi_aresetn`)| Integrated (Internal) |
| **PWM** | S10 (`m10_axi`)| `0x4004_1000` | 4 KiB | 12 | AXI4-Lite (direct) | Active-Low (`s00_axi_aresetn`)| Integrated (Internal) |
| **WDT** | S11 (`m11_axi`)| `0x8000_4000` | 4 KiB | 12 | Full AXI4 | Active-Low | Preserved (External) |
| **ADC** | S12 (`m12_axi`)| `0x8000_5000` | 4 KiB | 12 | Full AXI4 | Active-Low | Preserved (External) |
| **DMA** | S13 (`m13_axi`)| `0x8000_6000` | 4 KiB | 12 | Full AXI4 | Active-Low | Preserved (External) |
| **Reserved** | S14 (`m14_axi`)| `0x0000_0000` | 0 B | 0 | Full AXI4 | — | Disabled (`WIDTH=0`) |

---

## 2. Interface and Adapter Decisions

### 2.1 GPIO (`gpio_axi.sv`) — Slave S2
- **Protocol:** AXI4-Lite slave with 32-bit registers.
- **Interconnect Port:** Full AXI4 (`m02_axi`).
- **Adapter:** Bridged via `rtl/common/axi4lite_slave_adapter.sv`. The adapter absorbs AXI IDs, burst lengths (`awlen`/`arlen`), response channels, and presents a standard AXI4-Lite interface to `gpio_axi`.
- **Address Handling:** Local 12-bit address `m02_axi_awaddr[11:0]` is zero-extended to 32 bits `{20'h0, addr[11:0]}` to connect cleanly to `gpio_axi`'s 32-bit `awaddr`/`araddr` ports.
- **Reset:** Active-low `~rst` connected to `s_axi_aresetn`.
- **External I/O:** 32-bit bidirectional `gpio_io` and `gpio_intr` interrupt output are exposed as top-level ports.

### 2.2 Timer (`timer_axi.sv`) — Slave S3
- **Protocol:** AXI4-Lite slave with 32-bit registers.
- **Interconnect Port:** Full AXI4 (`m03_axi`).
- **Adapter:** Bridged via `rtl/common/axi4lite_slave_adapter.sv`.
- **Address Handling:** Local 12-bit address `m03_axi_awaddr[11:0]` is zero-extended to 32 bits `{20'h0, addr[11:0]}`.
- **Reset:** Active-low `~rst` connected to `aresetn`.
- **External I/O:** `timer_ext_meas`, `timer_capture`, `timer_pwm`, `timer_trigger`, and `timer_intr` (`irq`) are exposed as top-level ports.

### 2.3 UART (`axi_uart_top.v`) — Slave S4
- **Protocol:** Native Full AXI4 slave with internal FIFOs and dual-clock domain (AXI `clk` + baud `fixed_clk`).
- **Address Handling:** Base address configured to `0x4003_5000`, aperture width `12` (4 KiB window `0x4003_5000`–`0x4003_5FFF`).
- **Interface:** Direct connection to `m04_axi_*` signals inside `main_top.v`.
- **Semantics:** Register at offset `0x00` writes to TX FIFO (`THR`) and reads from RX FIFO (`RBR`). Offset `0x14` reads status (`LSR`).

### 2.4 Quadrature Encoder (`enc_top.v`) — Slave S8
- **Protocol:** Native Full AXI4 slave.
- **Parameter Override:** `.ADDR_WIDTH(12)` explicitly passed to `enc_top`.
- **Address Handling:** `s_axi_awaddr` and `s_axi_araddr` connect directly to 12-bit slices `m08_axi_awaddr[11:0]` and `m08_axi_araddr[11:0]`.
- **Address Validation & Rejection:** Internally, `enc_axi_slave` evaluates:
  ```verilog
  assign wr_valid_map = (wr_addr[ADDR_WIDTH-1:8] == {(ADDR_WIDTH-8){1'b0}}) && (wr_addr[7:0] <= `ENC_ADDR_MAX);
  ```
  With `ADDR_WIDTH=12`, address bits `[11:8]` must be `4'b0000` and offset must be $\le 0\text{x}30$. Offsets $\ge 0\text{x}100$ or $> 0\text{x}30$ in the 4 KiB aperture are rejected with AXI `SLVERR (2'b10)` on both read and write channels.
- **Sideband Handling:** Sideband inputs (`awsize`, `arsize`, `awburst`, `arburst`, `awlock`, `arlock`, `awcache`, `arcache`, `awprot`, `arprot`) are accepted per AXI spec. `buser` and `ruser` are tied to zero.
- **External I/O:** Encoder inputs (`enc_a`, `enc_b`, `enc_index`, `enc_drive_active`) and status outputs (`enc_speed`, `enc_speed_valid`, `enc_count_valid`, `enc_dir`, `enc_fault`, `enc_intr`) are exposed at top level.

### 2.5 PID Controller (`pid_top.v`) — Slave S9
- **Protocol:** Native Full AXI4 slave.
- **Parameter Override:** `.ADDR_WIDTH(12)` explicitly passed to `pid_top`.
- **Address Handling:** Direct connection of 12-bit address slices `m09_axi_awaddr[11:0]` and `m09_axi_araddr[11:0]`.
- **Address Validation & Rejection:** Internally, `pid_axi_slave` evaluates:
  ```verilog
  assign wr_valid_map = (wr_addr[ADDR_WIDTH-1:8] == {(ADDR_WIDTH-8){1'b0}}) && (valid register decode);
  ```
  With `ADDR_WIDTH=12`, bits `[11:8]` must be `4'b0000`. Offsets outside valid registers return `SLVERR (2'b10)`. Read-only registers (e.g. `VERSION` at `0x34`) reject write transactions with `SLVERR (2'b10)`, and invalid apertures $\ge 0\text{x}100$ reject with `SLVERR (2'b10)`.
- **External I/O:** `pid_tick`, `pid_actual`, `pid_out`, `pid_out_valid`, `pid_sat_flag`, `pid_intr` exposed at top level.

### 2.6 PWM Subsystem (`myip_v1_0.v`) — Slave S10
- **Protocol:** AXI4-Lite slave with internal register file (`slv_reg0`..`slv_reg3`).
- **Address Handling:** Base address updated to `0x4004_1000` with 4 KiB aperture (`WIDTH=12`).
- **Direct Connection:** `m10_axi` channel wires connect to `s00_axi_*` ports of `myip_v1_0`. Sideband signals `awlen`, `arlen`, IDs, and user bits are handled cleanly.
- **External I/O:** `PWM_OUT` exposed at top level.

---

## 3. Files Modified and Rationale

| File Path | Description of Changes |
|:---|:---|
| `rtl/main_top.v` | Updated base addresses and aperture widths for S2, S3, S4, S8, S9, S10 (`WIDTH=12`). Added external peripheral I/O ports for GPIO, Timer, Encoder, and PID. Removed external slave ports for S2, S3, S8, S9 and declared internal AXI interconnect wires. Instantiated `gpio_axi` (S2) and `timer_axi` (S3) with `axi4lite_slave_adapter`. Instantiated `enc_top` (S8) and `pid_top` (S9) with `.ADDR_WIDTH(12)`. Connected all clocks, resets, handshakes, and response channels. |
| `run/run_main.f` | Replaced stale absolute paths (`/home/student/Documents/...`) with workspace-relative paths (`../rtl/...`, `../tb/...`). Added include directories for UART, Encoder, PID, and common library. Added source files for GPIO, Timer, Encoder, PID, and `axi4lite_slave_adapter.sv`. |
| `tb/tb_main_top.sv` | Updated address constants for S2 (`0x4003_1000`), S3 (`0x4003_3000`), S4 (`0x4003_5000`), S8 (`0x4003_D000`), S9 (`0x4003_F000`), and S10 (`0x4004_1000`). Connected peripheral testbench signals to DUT. Excluded S2, S3, S4, S8, S9, S10 from dummy responders. Updated Scenario 2 with aperture gap `DECERR` checks. Added Scenarios 12–16 testing GPIO, Timer, Encoder, PID, and PWM (safe RW readback, RO register behavior, multi-master crossbar access, invalid offset `SLVERR` rejection, and independent AW/W channel arrivals). Protected FSDB dump calls with `` `ifdef FSDB ``. |
| `run/run_main.sh` | Created executable compilation and simulation runner script that executes VCS strictly within `run/` without searching outside the authorized workspace. |

---

## 4. Build and Simulation Commands

All compilation and simulation steps were executed strictly inside `/home/student/Downloads/090_honrors/CBP/run`.

### Compilation Command
```bash
cd /home/student/Downloads/090_honrors/CBP/run
vcs -full64 -sverilog -timescale=1ns/1ps -debug_access+all -kdb \
    -f run_main.f \
    -top tb_main_top \
    -o simv \
    -l compile.log
```

### Simulation Command
```bash
./simv > sim.log 2>&1
```

*(Note: License environment variables were sourced from existing configuration scripts within `run/` without exposing external server details).*

---

## 5. Verification Results and Scoreboard Summary

### Results Overview
- **Compilation Status:** PASSED (0 errors, 0 syntax failures).
- **Simulation Status:** PASSED (0 fatal errors, 0 assertion failures, watchdog did not trigger).
- **Log Locations:**
  - Compilation Log: `run/compile.log`
  - Simulation Log: `run/sim.log`

### Detailed Test Scenario Breakdown

| Scenario | Description | Checks Run | Pass | Fail |
|:---|:---|:---:|:---:|:---:|
| **Scenario 1** | Power-on Reset & Initial Idle Conditions | 4 | 4 | 0 |
| **Scenario 2** | Unmapped Address Decoding & Aperture Gaps (`DECERR = 2'b11`) | 9 | 9 | 0 |
| **Scenario 3** | Crossbar Routing across Masters (M0, M1, M2) & External Slaves | 12 | 12 | 0 |
| **Scenario 4** | UART DLAB & 115200 Baud Divisor Configuration | 6 | 6 | 0 |
| **Scenario 5** | UART TX Transmission & Serial Waveform Verification (`0xA5`) | 3 | 3 | 0 |
| **Scenario 6** | UART RX Reception & AXI Readback (`0x5A`) | 5 | 5 | 0 |
| **Scenario 7** | UART Interrupt (IRQ) Behavior & Clearing | 6 | 6 | 0 |
| **Scenario 8** | AXI Handshake Ordering Edge Cases & Backpressure | 4 | 4 | 0 |
| **Scenario 9** | AXI Transaction ID Preservation (`m1_arid`/`m1_awid`) | 4 | 4 | 0 |
| **Scenario 10** | Unsupported Burst Protection & Register Map Integrity | 3 | 3 | 0 |
| **Scenario 11** | Mid-Activity Reset & Recovery | 2 | 2 | 0 |
| **Scenario 12** | **GPIO S2:** Safe RW Readback (`DIR`, `DEB_TH`), Multi-Master (M0, M2) | 8 | 8 | 0 |
| **Scenario 13** | **Timer S3:** Safe RW Readback (`LOAD`, `PRE`, `CMP`), Multi-Master (M0, M2) | 10 | 10 | 0 |
| **Scenario 14** | **Encoder S8:** RO Version, Safe RW (`WINDOW`, `SCALE`), Multi-Master, Invalid Offset Rejection (`SLVERR`) | 15 | 15 | 0 |
| **Scenario 15** | **PID S9:** RO Version, Write-rejection, Safe RW (`KP`, `KI`, `KD`), Multi-Master, Invalid Offset Rejection (`SLVERR`) | 17 | 17 | 0 |
| **Scenario 16** | **PWM S10:** Duty Register (`0x80`), Remaining Registers, Boundary (`0x4004_1FFC`), Multi-Master, AW/W Arrival Variants | 49 | 49 | 0 |
| **TOTAL** | **Full Integrated Verification** | **157** | **157** | **0** |

### Verification Scoreboard Output (from `run/sim.log`)
```
================================================================================
                         VERIFICATION SCOREBOARD SUMMARY                        
================================================================================
  TOTAL CHECKS  : 157
  PASSED CHECKS : 157
  FAILED CHECKS : 0
--------------------------------------------------------------------------------
  >>> STATUS: ALL TESTS PASSED SUCCESSFULLY! 100% VERIFIED. <<<
================================================================================
```

---

## 6. Tests Not Run and Rationale

The following items were intentionally not exercised in the integration testbench:
1. **Dynamic Closed-Loop Motor Control & Mechanical Plant Simulation:**  
   Simulating continuous motor physics, quadrature feedback loop dynamics, and closed-loop PID step-response convergence is reserved for system-level verification where firmware running on the VeeR core governs the feedback loop.
2. **Physical Wire Transceiver Delay Variations:**  
   UART transmission and reception were verified at nominal 115200 baud timings; multi-rate baud sweeps and line noise injection are verified at the standalone IP level.
3. **RISC-V Firmware Execution:**  
   VeeR EL2 core integration and bootloader execution belong to Phase 3. Bus masters M0, M1, and M2 were exercised using bus-functional models.

---

## 7. Known Limitations and Remaining Risks

1. **Standalone IP Warnings:**  
   During compilation, VCS reports a lint warning in `pid_top.v` regarding unconnected ports in `pid_axi_slave` (e.g. `s_axi_awuser`, `s_axi_aruser`, which are unused sidebands). This is an existing standalone IP characteristic and does not affect functionality.
2. **VeeR Instruction / Data Bus Coupling:**  
   In Phase 3, connecting the VeeR core LSU and IFU to the crossbar will require aligning the memory map with the core's reset vector and linker script (e.g. instruction ROM at `0x0004_0000`, data RAM at `0x0008_0000`, and MMIO at `0x4000_0000`+).

---

## 8. Workspace Compliance Confirmation

It is explicitly confirmed that:
- All file inspections, modifications, and creations were restricted exclusively to `/home/student/Downloads/090_honrors/CBP`.
- Zero files outside the authorized workspace were read, written, or referenced.
- All compilation binaries (`simv`, `simv.daidir`), temporary build files (`csrc`), and simulation logs (`compile.log`, `sim.log`) were generated and remain strictly within `/home/student/Downloads/090_honrors/CBP/run`.
- No license server details (IP addresses, ports) have been exposed in logs or user-facing text.
- No Phase 3 actions, RISC-V integrations, or unauthorized modifications have been initiated.
