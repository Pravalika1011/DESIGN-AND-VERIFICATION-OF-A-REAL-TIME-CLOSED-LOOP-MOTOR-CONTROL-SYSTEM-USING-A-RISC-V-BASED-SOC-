# Phase 2 System Interface Freeze Document

**Project**: RISC-V Fail-Safe Railway Level-Crossing Motor Speed Control SoC  
**Repository**: `/home/student/Downloads/090_honrors/CBP`  
**Phase**: Phase 2 Complete — Frozen Interfaces for Phase 3 RISC-V Processor Connection  
**Date**: October 17, 2026  
**Status**: FROZEN  

---

## 1. Scope & Objective

This document freezes all interconnect address mappings, master/slave bus protocols, peripheral register interfaces, clocking/reset schemes, and interrupt definitions verified in Phase 2. Phase 3 shall instantiate and connect the RISC-V core (VeeR EL2) to the frozen master interfaces and interrupt lines without modifying peripheral RTL, interconnect decoding parameters, or register maps.

---

## 2. AXI Interconnect Architecture & Frozen Address Map

The interconnect provides a 3-master $\times$ 15-slave crossbar matrix implemented in [axi_interconnect_wrap_3x15.v](file:///home/student/Downloads/090_honrors/CBP/rtl/interconnect/axi_interconnect_wrap_3x15.v) and [main_top.v](file:///home/student/Downloads/090_honrors/CBP/rtl/main_top.v).

### 2.1 Complete 15-Slave Interconnect Allocation Table

| Slot | Slave Name | Base Address | Aperture | Width Param | Protocol | Out-of-Range Behavior |
|:---:|:---|:---:|:---:|:---:|:---|:---|
| **S0** | Instruction Memory (IMEM) | `0x0004_0000` | 128 KiB | `M00_ADDR_WIDTH=17` | Full AXI4 | Mapped window |
| **S1** | Data Memory (DMEM) | `0x0008_0000` | 128 KiB | `M01_ADDR_WIDTH=17` | Full AXI4 | Mapped window |
| **S2** | GPIO Controller | `0x4003_1000` | 4 KiB | `M02_ADDR_WIDTH=12` | AXI4-Lite (Adapter) | Modulo/Zero-return |
| **S3** | Real-Time Timer | `0x4003_3000` | 4 KiB | `M03_ADDR_WIDTH=12` | AXI4-Lite (Adapter) | Modulo/Zero-return |
| **S4** | UART Subsystem | `0x4003_5000` | 4 KiB | `M04_ADDR_WIDTH=12` | Full AXI4 (Direct) | Modulo-32 aliasing (OKAY) |
| **S5** | Reserved / Disabled | `0x0000_0000` | 0 KiB | `M05_ADDR_WIDTH=0` | Full AXI4 | **DECERR (2'b11)** |
| **S6** | Reserved / Disabled | `0x0000_0000` | 0 KiB | `M06_ADDR_WIDTH=0` | Full AXI4 | **DECERR (2'b11)** |
| **S7** | Reserved / Disabled | `0x0000_0000` | 0 KiB | `M07_ADDR_WIDTH=0` | Full AXI4 | **DECERR (2'b11)** |
| **S8** | Quadrature Encoder | `0x4003_D000` | 4 KiB | `M08_ADDR_WIDTH=12` | Full AXI4 (`ADDR_WIDTH=12`) | **SLVERR (2'b10)** on $\ge 0\text{x}100$ |
| **S9** | PID Controller | `0x4003_F000` | 4 KiB | `M09_ADDR_WIDTH=12` | Full AXI4 (`ADDR_WIDTH=12`) | **SLVERR (2'b10)** on $\ge 0\text{x}100$ |
| **S10** | PWM Generator | `0x4004_1000` | 4 KiB | `M10_ADDR_WIDTH=12` | AXI4-Lite (Direct) | Modulo-16 aliasing (OKAY) |
| **S11** | Watchdog Timer (WDT) | `0x8000_4000` | 4 KiB | `M11_ADDR_WIDTH=12` | Full AXI4 | Mapped window |
| **S12** | ADC Interface | `0x8000_5000` | 4 KiB | `M12_ADDR_WIDTH=12` | Full AXI4 | Mapped window |
| **S13** | DMA Registers | `0x8000_6000` | 4 KiB | `M13_ADDR_WIDTH=12` | Full AXI4 | Mapped window |
| **S14** | Seven-Segment Display | `0x0000_0000` | 0 KiB | `M14_ADDR_WIDTH=0` | Full AXI4 | **DECERR (2'b11)** |

---

## 3. Master Interface Specifications for Phase 3

| Master Port | Target Subsystem | Bus Type | Expected Master in Phase 3 |
|:---|:---|:---:|:---|
| **M0** (`s00_axi_*`) | Instruction Fetch | Full AXI4 | VeeR EL2 Instruction Fetch Unit (IFU) |
| **M1** (`s01_axi_*`) | Load / Store Data | Full AXI4 | VeeR EL2 Load/Store Unit (LSU) |
| **M2** (`s02_axi_*`) | Direct Memory Access | Full AXI4 | System DMA Controller |

- **ID Width**: 8 bits (`ID_WIDTH = 8`).
- **Data Width**: 32 bits (`DATA_WIDTH = 32`).
- **Address Width**: 32 bits (`ADDR_WIDTH = 32`).
- **Byte Strobes**: 4 bits (`STRB_WIDTH = 4`).

---

## 4. Frozen Peripheral Register Maps

### 4.1 GPIO Controller (S2: `0x4003_1000`)
| Offset | Register Name | Access | Reset Value | Description |
|:---:|:---|:---:|:---:|:---|
| `0x00` | `GPIO_DATA_I` | RO | External | Current state of GPIO input pins |
| `0x04` | `GPIO_DATA_O` | RW | `0x0000_0000` | Output pin drive register |
| `0x08` | `GPIO_DIR` | RW | `0x0000_0000` | Pin direction: 0 = Input, 1 = Output |
| `0x0C` | `GPIO_INT_EN` | RW | `0x0000_0000` | Interrupt enable mask |
| `0x10` | `GPIO_INT_STS`| W1C | `0x0000_0000` | Interrupt status (write 1 to clear) |
| `0x2C` | `GPIO_DEB_TH` | RW | `0x0000_0000` | Debounce filter clock cycle threshold |

### 4.2 Real-Time Timer (S3: `0x4003_3000`)
| Offset | Register Name | Access | Reset Value | Description |
|:---:|:---|:---:|:---:|:---|
| `0x00` | `TIMER_CTRL` | RW | `0x0000_0000` | `[0]` Enable, `[1]` Mode (1=periodic), `[2]` Prescaler En, `[3]` Dir |
| `0x04` | `TIMER_LOAD` | RW | `0x0000_0000` | Counter reload value (triggers immediate reload on write) |
| `0x08` | `TIMER_VAL` | RO | `0x0000_0000` | Current counter live value |
| `0x0C` | `TIMER_PRE` | RW | `0x0000_0000` | 16-bit prescaler division ratio |
| `0x10` | `TIMER_INT_EN`| RW | `0x0000_0000` | Interrupt enable: `[0]` Expire, `[1]` Capture |
| `0x14` | `TIMER_INT_STS`| W1C | `0x0000_0000` | Interrupt status flag |
| `0x18` | `TIMER_CMP` | RW | `0x0000_0000` | PWM compare value |
| `0x1C` | `TIMER_CAP` | RO | `0x0000_0000` | Captured counter value on external strobe |

### 4.3 UART Subsystem (S4: `0x4003_5000`)
| Offset | Register Name | Access | Reset Value | Description |
|:---:|:---|:---:|:---:|:---|
| `0x00` | `UART_RBR_THR`| RW | `0x0000_0000` | RX Buffer (RO) / TX Holding (WO) (when LCR[7]=0) |
| `0x04` | `UART_IER` | RW | `0x0000_0000` | Interrupt Enable Register |
| `0x08` | `UART_IIR_FCR`| RW | `0x0000_0001` | Interrupt Ident (RO) / FIFO Control (WO) |
| `0x0C` | `UART_LCR` | RW | `0x0000_0000` | Line Control Register (bit 7 = DLAB divisor latch access) |
| `0x10` | `UART_MCR` | RW | `0x0000_0000` | Modem Control Register |
| `0x14` | `UART_LSR` | RO | `0x0000_0060` | Line Status: bit 5 = THRE, bit 6 = TEMT, bit 0 = DR |

### 4.4 Quadrature Encoder (S8: `0x4003_D000`)
| Offset | Register Name | Access | Reset Value | Description |
|:---:|:---|:---:|:---:|:---|
| `0x00` | `ENC_COUNT` | RW | `0x0000_0000` | Signed 32-bit position count |
| `0x04` | `ENC_SPEED` | RO | `0x0000_0000` | Signed 16-bit filtered speed (sign-extended to 32 bits) |
| `0x08` | `ENC_CTRL` | RW | `0x0000_0000` | `[0]` Enable, `[1]` Reset, `[3:2]` Mode (x1/x2/x4), `[5:4]` Avg Sel |
| `0x0C` | `ENC_STATUS` | RO/W1C | `0x0000_0000` | Status and sticky events |
| `0x10` | `ENC_WINDOW`| RW | `0x0000_03E8` | Measurement window length in clock cycles |
| `0x14` | `ENC_FILTER`| RW | `0x0000_0003` | Input glitch filter cycle threshold |
| `0x18` | `ENC_SCALE` | RW | `0x0001_0000` | Signed Q16.16 speed scale factor |
| `0x1C` | `ENC_STALL_TMO`| RW | `0x000F_4240`| Stall timeout in clocks |
| `0x20` | `ENC_REV_COUNT`| RO | `0x0000_0000` | Full revolutions count |
| `0x24` | `ENC_INDEX_POS`| RO | `0x0000_0000` | Position count at last index pulse |
| `0x28` | `ENC_RAW_DELTA`| RO | `0x0000_0000` | Raw unscaled count delta of last window |
| `0x2C` | `ENC_IRQ_EN` | RW | `0x0000_0000` | Interrupt enable mask |
| `0x30` | `ENC_VERSION`| RO | `0x0001_0000` | IP Core version constant |

### 4.5 PID Controller (S9: `0x4003_F000`)
| Offset | Register Name | Access | Reset Value | Description |
|:---:|:---|:---:|:---:|:---|
| `0x00` | `PID_SETPOINT` | RW | `0x0000_0000` | Signed 16-bit target speed (sign-extended to 32 bits) |
| `0x04` | `PID_KP` | RW | `0x0000_0000` | Signed Q16.16 Proportional gain |
| `0x08` | `PID_KI` | RW | `0x0000_0000` | Signed Q16.16 Integral gain |
| `0x0C` | `PID_KD` | RW | `0x0000_0000` | Signed Q16.16 Derivative gain |
| `0x10` | `PID_OUTPUT` | RO | `0x0000_0000` | Signed 16-bit computed control output |
| `0x14` | `PID_CTRL` | RW | `0x0000_0000` | `[0]` Enable, `[1]` Int Reset, `[2]` Manual Upd, `[3]` D on Meas, `[4]` Anti-windup, `[5]` IRQ En |
| `0x18` | `PID_STATUS` | RO/W1C | `0x0000_0000` | `[0]` Busy, `[1]` Done, `[2]` Sat Hi, `[3]` Sat Lo, `[4]` Int Sat, `[5]` Overrun |
| `0x1C` | `PID_ERROR` | RO | `0x0000_0000` | Signed 17-bit instantaneous error |
| `0x20` | `PID_ACTUAL` | RO | `0x0000_0000` | Signed 16-bit measured speed feedback from Encoder |
| `0x24` | `PID_OUT_MAX` | RW | `0x0000_7FFF` | Upper saturation limit (+32767) |
| `0x28` | `PID_OUT_MIN` | RW | `0x0000_0000` | Lower saturation limit (0) |
| `0x2C` | `PID_INT_MAX` | RW | `0x7FFF_FFFF` | Integrator accumulator clamp max |
| `0x30` | `PID_INT_MIN` | RW | `0x8000_0000` | Integrator accumulator clamp min |
| `0x34` | `PID_VERSION` | RO | `0x0001_0000` | IP Core version constant |

### 4.6 PWM Generator (S10: `0x4004_1000`)
| Offset | Register Name | Access | Reset Value | Description |
|:---:|:---|:---:|:---:|:---|
| `0x00` | `PWM_REG0` | RW | `0x0000_0000` | Duty cycle register `slv_reg0[7:0]` (0 to 255) |
| `0x04` | `PWM_REG1` | RW | `0x0000_0000` | General configuration register 1 |
| `0x08` | `PWM_REG2` | RW | `0x0000_0000` | General configuration register 2 |
| `0x0C` | `PWM_REG3` | RW | `0x0000_0000` | General configuration register 3 |

---

## 5. Clock, Reset, and Interrupt Scheme

### 5.1 System Clocks and Resets
- **`clk`**: 100 MHz primary synchronous clock. Drives AXI interconnect, masters, and all peripherals.
- **`fixed_clk`**: 20 MHz dedicated baud reference clock for UART.
- **`rst`**: Active-HIGH synchronous reset input at `main_top`. Internally inverted to active-low (`~rst`) for standard AXI IP cores (`s_axi_aresetn`).

### 5.2 Interrupt Mapping to Processor (Phase 3 Targets)

| Interrupt Signal | Source Module | Type / Polarity | Clearing Mechanism | Routing in Phase 3 |
|:---|:---|:---:|:---|:---|
| `gpio_intr` | GPIO (S2) | Level, Active-High | W1C in `GPIO_INT_STS` | Core IRQ / PIC line |
| `timer_intr` | Timer (S3) | Level, Active-High | W1C in `TIMER_INT_STS` | Core IRQ / Timer IRQ |
| `uart_irq` | UART (S4) | Level, Active-High | Read `UART_RBR` or write `UART_THR` | Core IRQ / External line |
| `enc_intr` | Encoder (S8) | Level, Active-High | W1C in `ENC_STATUS` | Core IRQ / Fast interrupt |
| `pid_intr` | PID (S9) | Level, Active-High | W1C `PID_STATUS[1]` / `[5]` | Core IRQ / Fast interrupt |

---

## 6. Integration Rules for Phase 3

1. **VeeR EL2 Bus Master Binding**:
   - IFU AXI master connects to `main_top.s00_axi_*` (Slot M0).
   - LSU AXI master connects to `main_top.s01_axi_*` (Slot M1).
   - DMA master connects to `main_top.s02_axi_*` (Slot M2).
2. **Memory Map Invariants**:
   - Do not alter `M00_BASE_ADDR` through `M14_BASE_ADDR` parameters or aperture widths.
   - S5, S6, S7, S14 remain reserved/disabled (`ADDR_WIDTH=0`) and must generate `DECERR`.
3. **Hardware Loop Transparency**:
   - The hardware hybrid closed-loop operates autonomously.
   - Software can read status or override setpoints/gains at any time without stalling the interconnect or corrupting feedback timing.
