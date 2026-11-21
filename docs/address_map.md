# Address Map and Register Offsets

Source: `docs/specification/CBP_SoC_Specification.pdf`, `firmware/include/soc_regs.h`.

## System map

| Slot | Block | Base | End | Size | Protocol |
|---|---|---|---|---|---|
| S0 | IMEM | `0x4000_0000` | `0x4000_FFFF` | 64 KiB | AXI4 |
| — | gap | `0x4001_0000` | `0x4001_FFFF` | 64 KiB | DECERR |
| S1 | DMEM | `0x4002_0000` | `0x4002_FFFF` | 64 KiB | AXI4 |
| S2 | GPIO | `0x4003_1000` | `0x4003_1FFF` | 4 KiB | AXI4-Lite |
| S3 | Timer | `0x4003_3000` | `0x4003_3FFF` | 4 KiB | AXI4-Lite |
| S4 | UART | `0x4003_5000` | `0x4003_5FFF` | 4 KiB | AXI4-Lite |
| S5–S7 | reserved | `0x4003_7000` / `9000` / `B000` | +4 KiB | 4 KiB | DECERR |
| S8 | Quadrature Encoder | `0x4003_D000` | `0x4003_DFFF` | 4 KiB | AXI4 (bridge) |
| S9 | PID controller | `0x4003_F000` | `0x4003_FFFF` | 4 KiB | AXI4 (bridge) |
| S10 | PWM | `0x4004_1000` | `0x4004_1FFF` | 4 KiB | AXI4-Lite |
| S11–S14 | disabled (`ADDR_WIDTH = 0`) | `0x4004_3000` … `0x4004_9000` | +4 KiB | 4 KiB | DECERR |
| core | VeeR PIC | `0xF00C_0000` | — | — | core-local |

A 4 KiB guard buffer follows every slot; all guard buffers and unmapped addresses return DECERR (`2'b11`).

## DMEM layout (firmware)

| Region | Address |
|---|---|
| mailbox: magic, status, result, exit code | `0x4002_0000 – 0x4002_000F` |
| `.data`, `.bss`, heap (4 KiB) | from `0x4002_0010` |
| stack top | `0x4003_0000` (grows down) |

## Register offsets

| GPIO `0x4003_1000` | Timer `0x4003_3000` | UART `0x4003_5000` |
|---|---|---|
| 0x00 DATA_I, 0x04 DATA_O, 0x08 DIR | 0x00 CTRL, 0x04 LOAD, 0x08 VAL | 0x00 THR/RBR |
| 0x0C INT_EN, 0x10 INT_TYP, 0x14 INT_POL | 0x0C PRE, 0x10 INT_EN | 0x04 IER |
| 0x18 INT_ANY, 0x1C INT_STS (W1C) | 0x14 INT_STS (W1C) | 0x08 BAUD_DIV (DLAB = 1, reset 868) |
| 0x20 SET_O, 0x24 CLR_O, 0x28 TGL_O | 0x18 CMP, 0x1C CAP | 0x0C LCR, 0x14 LSR |

| Encoder `0x4003_D000` | PID `0x4003_F000` | PWM `0x4004_1000` |
|---|---|---|
| 0x00 COUNT, 0x04 SPEED, 0x08 CTRL | 0x00 SETPOINT, 0x04 KP, 0x08 KI, 0x0C KD (Q16.16) | 0x00 DUTY_CYCLE [7:0] |
| 0x0C STATUS, 0x10 WINDOW, 0x14 FILTER | 0x10 OUTPUT, 0x14 CTRL, 0x18 STATUS | 0x04–0x0C scratch REG1–REG3 |
| 0x18 SCALE, 0x1C STALL_TMO, 0x20 REV_COUNT | 0x1C ERROR, 0x20 ACTUAL | |
| 0x24 INDEX_POS, 0x28 RAW_DELTA, 0x2C IRQ_EN, 0x30 VERSION | 0x24 OUT_MAX, 0x28 OUT_MIN, 0x2C INT_MAX, 0x30 INT_MIN, 0x34 VERSION | |

## Interrupts (VeeR PIC)

| Source | Peripheral | Signal |
|---|---|---|
| 1 | UART | `uart_irq` |
| 2 | GPIO | `gpio_intr` |
| 3 | Timer | `timer_intr` |
| 4 | Encoder | `enc_intr` |
| 5 | PID | `pid_intr` |
