# Phase 2 AXI Interconnect Integration Report

**Project**: RISC-V Fail-Safe Railway Level-Crossing Motor Speed Control SoC  
**Repository**: `/home/student/Downloads/090_honrors/CBP`  
**Phase**: Phase 2 — AXI Interconnect Integration & Peripheral Verification  
**Date**: October 17, 2026  
**Status**: COMPLETE  

---

## 1. Executive Summary

In Phase 2, the system top-level integration module [main_top.v](file:///home/student/Downloads/090_honrors/CBP/rtl/main_top.v) was verified and finalized to integrate six peripheral IPs through the 3-master $\times$ 15-slave AXI4 interconnect [axi_interconnect_wrap_3x15.v](file:///home/student/Downloads/090_honrors/CBP/rtl/interconnect/axi_interconnect_wrap_3x15.v). All six target peripheral IPs:
1. **GPIO Controller** (Slave slot S2 / `m02_axi`) at `0x4003_1000` (4 KiB)
2. **Real-Time Timer** (Slave slot S3 / `m03_axi`) at `0x4003_3000` (4 KiB)
3. **UART Subsystem** (Slave slot S4 / `m04_axi`) at `0x4003_5000` (4 KiB)
4. **Quadrature Encoder** (Slave slot S8 / `m08_axi`) at `0x4003_D000` (4 KiB)
5. **PID Controller** (Slave slot S9 / `m09_axi`) at `0x4003_F000` (4 KiB)
6. **PWM Generator** (Slave slot S10 / `m10_axi`) at `0x4004_1000` (4 KiB)

have been verified across all 3 masters (M0 IFU, M1 LSU, M2 DMA) using Synopsys VCS. All 157 integration assertion checks in [tb_main_top.sv](file:///home/student/Downloads/090_honrors/CBP/tb/tb_main_top.sv) executed with **0 errors and 0 failures**.

---

## 2. AXI Interconnect Architecture & Address Decode

The interconnect topology consists of 3 AXI4 masters arbitrating for access to 15 slave interfaces.

### 2.1 Complete Interconnect Slot Allocation

| Slave Slot | Target IP | Base Address | Aperture | Interconnect Parameter | Status |
|:---:|:---|:---:|:---:|:---|:---:|
| **S0** | Instruction Memory (IMEM) | `0x0004_0000` | 128 KiB | `M00_BASE_ADDR`, `M00_ADDR_WIDTH=17` | Verified |
| **S1** | Data Memory (DMEM) | `0x0008_0000` | 128 KiB | `M01_BASE_ADDR`, `M01_ADDR_WIDTH=17` | Verified |
| **S2** | GPIO Controller | `0x4003_1000` | 4 KiB | `M02_BASE_ADDR`, `M02_ADDR_WIDTH=12` | **Verified (Phase 2)** |
| **S3** | Real-Time Timer | `0x4003_3000` | 4 KiB | `M03_BASE_ADDR`, `M03_ADDR_WIDTH=12` | **Verified (Phase 2)** |
| **S4** | UART Subsystem | `0x4003_5000` | 4 KiB | `M04_BASE_ADDR`, `M04_ADDR_WIDTH=12` | **Verified (Phase 2)** |
| **S5** | Reserved / Disabled | `0x0000_0000` | 0 KiB | `M05_BASE_ADDR`, `M05_ADDR_WIDTH=0` | DECERR / Inactive |
| **S6** | Reserved / Disabled | `0x0000_0000` | 0 KiB | `M06_BASE_ADDR`, `M06_ADDR_WIDTH=0` | DECERR / Inactive |
| **S7** | Reserved / Disabled | `0x0000_0000` | 0 KiB | `M07_BASE_ADDR`, `M07_ADDR_WIDTH=0` | DECERR / Inactive |
| **S8** | Quadrature Encoder | `0x4003_D000` | 4 KiB | `M08_BASE_ADDR`, `M08_ADDR_WIDTH=12` | **Verified (Phase 2)** |
| **S9** | PID Controller | `0x4003_F000` | 4 KiB | `M09_BASE_ADDR`, `M09_ADDR_WIDTH=12` | **Verified (Phase 2)** |
| **S10** | PWM Generator | `0x4004_1000` | 4 KiB | `M10_BASE_ADDR`, `M10_ADDR_WIDTH=12` | **Verified (Phase 2)** |
| **S11** | Watchdog Timer (WDT) | `0x8000_4000` | 4 KiB | `M11_BASE_ADDR`, `M11_ADDR_WIDTH=12` | Verified |
| **S12** | ADC Interface | `0x8000_5000` | 4 KiB | `M12_BASE_ADDR`, `M12_ADDR_WIDTH=12` | Verified |
| **S13** | DMA Registers | `0x8000_6000` | 4 KiB | `M13_BASE_ADDR`, `M13_ADDR_WIDTH=12` | Verified |
| **S14** | Seven-Segment Display | `0x0000_0000` | 0 KiB | `M14_BASE_ADDR`, `M14_ADDR_WIDTH=0` | DECERR / Inactive |

---

## 3. Peripheral Protocol Adaptation & Address Handling

### 3.1 GPIO Controller (S2)
- **Protocol**: AXI4-Lite slave via [axi4lite_slave_adapter.sv](file:///home/student/Downloads/090_honrors/CBP/rtl/common/axi4lite_slave_adapter.sv).
- **Address Handling**: Interconnect passes full address to adapter; adapter slices local address and forwards `{20'h0, m02_axi_awaddr[11:0]}` to `gpio_axi.sv`.
- **Register Decode**: Offsets `0x00` (DATA_IN), `0x04` (DATA_OUT), `0x08` (DIR), `0x0C` (INT_EN), `0x10` (INT_STS), `0x2C` (DEBOUNCE).
- **Aperture Behavior**: Responds with `OKAY (2'b00)` for valid register accesses; unmapped offsets return `0x0000_0000`.

### 3.2 Real-Time Timer (S3)
- **Protocol**: AXI4-Lite slave via [axi4lite_slave_adapter.sv](file:///home/student/Downloads/090_honrors/CBP/rtl/common/axi4lite_slave_adapter.sv).
- **Address Handling**: Interconnect forwards `{20'h0, m03_axi_awaddr[11:0]}` to `timer_axi.sv`.
- **Register Decode**: Offsets `0x00` (CTRL), `0x04` (LOAD), `0x08` (VAL), `0x0C` (PRE), `0x10` (INT_EN), `0x14` (INT_STS), `0x18` (CMP), `0x1C` (CAP).
- **Aperture Behavior**: Responds with `OKAY (2'b00)` for mapped registers; out-of-range reads return `0x0000_0000`.

### 3.3 UART Subsystem (S4)
- **Protocol**: Direct AXI4 slave [axi_uart_top.v](file:///home/student/Downloads/090_honrors/CBP/rtl/UART/axi_uart_top.v).
- **Address Handling**: IP declares `_AXI_UART_ADDR_WIDTH_ = 5`, decoding `s_axi_awaddr[4:0]`.
- **Aperture Behavior**: The 4 KiB aperture (`0x4003_5000 - 0x4003_5FFF`) is mapped to UART by the interconnect. Accesses alias modulo-32 across the 4 KiB window. Responds with `OKAY (2'b00)`.

### 3.4 Quadrature Encoder Interface (S8)
- **Protocol**: Direct Full AXI4 slave [enc_top.v](file:///home/student/Downloads/090_honrors/CBP/rtl/encoder/enc_top.v).
- **Parameterization**: Configured with `.ADDR_WIDTH(12)`.
- **Address Validation & Rejection**:
  - Validates `addr[ADDR_WIDTH-1:8] == 4'b0000` (i.e. bits `[11:8]`).
  - Validates word offset $\le 8\text{h}30$ (`ENC_ADDR_MAX`).
  - Returns **`SLVERR (2'b10)`** on any offset $\ge 0\text{x}100$ or unmapped offset within `0x00-0xFF`, preventing invalid access or aliasing.

### 3.5 PID Controller (S9)
- **Protocol**: Direct Full AXI4 slave [pid_top.v](file:///home/student/Downloads/090_honrors/CBP/rtl/pid_controler/pid_top.v).
- **Parameterization**: Configured with `.ADDR_WIDTH(12)`.
- **Address Validation & Rejection**:
  - Validates `addr[ADDR_WIDTH-1:8] == 4'b0000` (bits `[11:8]`).
  - Validates that `reg_idx` matches one of the mapped registers (`SETPOINT`, `KP`, `KI`, `KD`, `CTRL`, `STATUS`, `OUT_MAX`, `OUT_MIN`, `INT_MAX`, `INT_MIN`).
  - Returns **`SLVERR (2'b10)`** on unmapped offsets or offsets $\ge 0\text{x}100$.

### 3.6 PWM Generator (S10)
- **Protocol**: AXI4-Lite slave [myip_v1_0.v](file:///home/student/Downloads/090_honrors/CBP/rtl/PWM/myip_v1_0.v).
- **Address Handling**: `C_S00_AXI_ADDR_WIDTH = 4`, decoding `s00_axi_awaddr[3:2]`.
- **Aperture Behavior**: Modulo-16 address aliasing across the 4 KiB aperture (`0x4004_1000 - 0x4004_1FFF`). Always returns `OKAY (2'b00)`.
- **Independent AW/W Channel Arrivals**: Verified for simultaneous arrival, AW-before-W (8 cycle skew), and W-before-AW (8 cycle skew).

---

## 4. Verification Evidence & Summary

All 157 verification checks in [tb_main_top.sv](file:///home/student/Downloads/090_honrors/CBP/tb/tb_main_top.sv) executed via [run_main.sh](file:///home/student/Downloads/090_honrors/CBP/run/run_main.sh):

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

All 3 masters successfully access each of the 6 peripherals with clean arbitration, zero bus deadlocks, and verified write/read integrity.
