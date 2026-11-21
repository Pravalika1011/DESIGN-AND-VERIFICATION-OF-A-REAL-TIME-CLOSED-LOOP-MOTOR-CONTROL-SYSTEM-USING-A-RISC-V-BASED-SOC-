// =============================================================================
// Project      : Motor-Control SoC - PID Controller IP
// File         : pid_defines.v
// Description  : PID Controller IP – compile-time definitions.
//                Contains:
//                  - register map offsets
//                  - PID_CTRL bit positions
//                  - PID_STATUS bit positions (with type annotation)
//                  - register reset values
//                  - version identifier
//                  - FSM state encodings (binary, 4-bit)
//                  - data-path width definitions
//                  - INT_MAX/INT_MIN 32-bit storage convention
//
// Author       : Honours CBP Project
// Created      : 2026-10-03
// Revised      : 2026-10-03  v1.0  Initial release
//
// License (MIT):
//   Copyright (c) 2026 Honours CBP Project
//   Permission is hereby granted, free of charge, to any person obtaining a
//   copy of this software and associated documentation files (the "Software"),
//   to deal in the Software without restriction, including without limitation
//   the rights to use, copy, modify, merge, publish, distribute, sublicense,
//   and/or sell copies of the Software, and to permit persons to whom the
//   Software is furnished to do so, subject to the following conditions:
//   The above copyright notice and this permission notice shall be included in
//   all copies or substantial portions of the Software.
//   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
// =============================================================================

`ifndef PID_DEFINES_V
`define PID_DEFINES_V

// ---------------------------------------------------------------------------
// Data-path widths  (must match pid_core.v parameters exactly)
// ---------------------------------------------------------------------------
`define PID_SPEED_W     16          // speed / setpoint word width
`define PID_OUT_W       16          // output word width
`define PID_GAIN_W      32          // Q16.16 gain width
`define PID_FRAC        16          // fractional bits in Q16.16 gain

// Derived widths
`define PID_ERR_W       17          // SPEED_W + 1  = 17
`define PID_DERIV_W     18          // ERR_W + 1 = 18  (prevents derivative overflow)
`define PID_PROD_W      50          // GAIN_W + DERIV_W + 0 = 50  (32+18=50; fits in 50b)
`define PID_ACC_W       54          // PROD_W + 4 = 54

// ---------------------------------------------------------------------------
// Register map offsets  (word index = addr[7:2], 32-bit aligned)
// ---------------------------------------------------------------------------
`define PID_REG_SETPOINT    6'h00   // 0x00  RW  signed 16-bit setpoint
`define PID_REG_KP          6'h01   // 0x04  RW  Q16.16 Kp
`define PID_REG_KI          6'h02   // 0x08  RW  Q16.16 Ki
`define PID_REG_KD          6'h03   // 0x0C  RW  Q16.16 Kd
`define PID_REG_OUTPUT      6'h04   // 0x10  RO  signed output (sign-extended to 32)
`define PID_REG_CTRL        6'h05   // 0x14  RW  control register
`define PID_REG_STATUS      6'h06   // 0x18  see STATUS bit table below
`define PID_REG_ERROR       6'h07   // 0x1C  RO  signed error
`define PID_REG_ACTUAL      6'h08   // 0x20  RO  signed actual speed
`define PID_REG_OUT_MAX     6'h09   // 0x24  RW  signed 16-bit output max
`define PID_REG_OUT_MIN     6'h0A   // 0x28  RW  signed 16-bit output min
`define PID_REG_INT_MAX     6'h0B   // 0x2C  RW  signed integrator max (lower 32 bits)
`define PID_REG_INT_MIN     6'h0C   // 0x30  RW  signed integrator min (lower 32 bits)
`define PID_REG_VERSION     6'h0D   // 0x34  RO  version

// ---------------------------------------------------------------------------
// PID_CTRL bit positions  [0x14]
// ---------------------------------------------------------------------------
`define PID_CTRL_ENABLE         0   // [0]  RW   enable PID updates
`define PID_CTRL_INT_RESET      1   // [1]  RW   one-cycle self-clearing command:
                                    //           clears integrator, e_prev, act_prev
`define PID_CTRL_MANUAL_UPDATE  2   // [2]  RW   self-clearing: trigger one manual update
`define PID_CTRL_D_ON_MEAS      3   // [3]  RW   0=d-on-error  1=d-on-measurement
`define PID_CTRL_AW_EN          4   // [4]  RW   anti-windup enable
`define PID_CTRL_IRQ_EN         5   // [5]  RW   interrupt enable

// ---------------------------------------------------------------------------
// PID_STATUS bit positions  [0x18]
//
//   TYPE ANNOTATIONS:
//     [0] BUSY     RO          – read-only, cannot be cleared by software
//     [1] DONE     RO / W1C   – sticky; cleared by writing 1; new event wins
//                               over simultaneous W1C clear
//     [2] SAT_HI   RO sticky  – set when output clamped HIGH; READ-ONLY;
//                               NOT clearable by software (W1C does NOT apply)
//     [3] SAT_LO   RO sticky  – set when output clamped LOW; READ-ONLY;
//                               NOT clearable by software (W1C does NOT apply)
//     [4] INT_SAT  RO sticky  – set when integrator clamped; READ-ONLY;
//                               NOT clearable by software (W1C does NOT apply)
//     [5] OVERRUN  RO / W1C   – sticky; cleared by writing 1; new event wins
//                               over simultaneous W1C clear
//
//   IRQ equation:
//     irq_o = (DONE_sticky | OVERRUN_sticky) & IRQ_EN
//     The interrupt is generated from the sticky DONE and OVERRUN bits,
//     not from the core's one-cycle pulses.  It deasserts when both
//     sticky bits are cleared by software or when IRQ_EN = 0.
// ---------------------------------------------------------------------------
`define PID_STAT_BUSY       0       // [0]  RO         update in progress
`define PID_STAT_DONE       1       // [1]  RO/W1C     update completed (sticky)
`define PID_STAT_SAT_HI     2       // [2]  RO sticky  output saturated high
`define PID_STAT_SAT_LO     3       // [3]  RO sticky  output saturated low
`define PID_STAT_INT_SAT    4       // [4]  RO sticky  integrator saturated
`define PID_STAT_OVERRUN    5       // [5]  RO/W1C     tick arrived while BUSY (sticky)

// ---------------------------------------------------------------------------
// Register reset values
// ---------------------------------------------------------------------------
`define PID_RST_OUT_MAX     32'h0000_7FFF   // +32767 (signed)
`define PID_RST_OUT_MIN     32'h0000_0000   //  0

// ---------------------------------------------------------------------------
// Version identifier
// ---------------------------------------------------------------------------
`define PID_VERSION_ID      32'h0001_0000

// ---------------------------------------------------------------------------
// FSM state encoding  (binary, 4 bits)
// ---------------------------------------------------------------------------
`define PID_ST_IDLE     4'h0        // idle, waiting for enable + tick or manual
`define PID_ST_LATCH    4'h1        // latch inputs into shadow registers
`define PID_ST_MUL_P    4'h2        // multiply: p_term  = Kp * error
`define PID_ST_MUL_I    4'h3        // multiply: ki_e    = Ki * error
`define PID_ST_MUL_D    4'h4        // multiply: d_term  = Kd * derivative
`define PID_ST_SUM      4'h5        // integrator accumulate + partial sum P+D
`define PID_ST_CLAMP    4'h6        // clamp integrator, complete sum, clamp output
`define PID_ST_COMMIT   4'h7        // anti-windup decision, commit results

// ---------------------------------------------------------------------------
// INT_MAX / INT_MIN 32-bit register storage convention
//
//   ACC_W = 54 bits.  The 32-bit registers PID_INT_MAX (0x2C) and
//   PID_INT_MIN (0x30) store the LOWER 32 bits of the 54-bit limit value.
//   Bits [53:32] of the limit used inside pid_core are obtained by
//   sign-extending bit [31] of the stored value:
//
//       limit[ACC_W-1:0] = { {(ACC_W-32){reg[31]}}, reg[31:0] }
//
//   Software must choose limit values within [-2^31 .. 2^31-1].
// ---------------------------------------------------------------------------
`define PID_INT_REG_W   32          // bits stored in the register

`endif // PID_DEFINES_V
