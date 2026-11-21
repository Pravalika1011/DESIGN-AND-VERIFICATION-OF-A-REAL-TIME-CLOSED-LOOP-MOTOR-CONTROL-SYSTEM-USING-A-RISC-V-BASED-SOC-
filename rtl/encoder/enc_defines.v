// =============================================================================
// Project      : Motor-Control SoC - Quadrature Encoder Interface IP
// File         : enc_defines.v
// Description  : QEI – compile-time definitions.
//                Contains:
//                  - register map offsets (byte addresses 0x00-0x30)
//                  - ENC_CTRL bit positions
//                  - ENC_STATUS bit positions (with type annotation)
//                  - register reset values
//                  - version identifier
//                  - data-path width definitions
//
// Author       : Honours CBP Project
// Created      : 2026-10-06
// Revised      : 2026-10-06  v1.0  Initial release
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

`ifndef ENC_DEFINES_V
`define ENC_DEFINES_V

// ---------------------------------------------------------------------------
// Data-path widths
// ---------------------------------------------------------------------------
`define ENC_COUNT_W     32          // signed position counter width
`define ENC_SPEED_W     16          // signed speed output width
`define ENC_SCALE_W     32          // Q16.16 scale factor width
`define ENC_WINDOW_W    32          // window length counter width
`define ENC_STALL_W     32          // stall timeout counter width
`define ENC_FILTER_W    4           // glitch filter cycles field width

// ---------------------------------------------------------------------------
// Register map offsets  (byte addresses; word index = addr[7:2])
// Valid range 0x00-0x30 (addresses with bits [31:8] != 0 are SLVERR)
// ---------------------------------------------------------------------------
`define ENC_REG_COUNT       8'h00   // 0x00  RW   signed 32-bit position count
`define ENC_REG_SPEED       8'h04   // 0x04  RO   filtered speed, sign-ext from 16b
`define ENC_REG_CTRL        8'h08   // 0x08  RW   control register
`define ENC_REG_STATUS      8'h0C   // 0x0C  RO/W1C  status register
`define ENC_REG_WINDOW      8'h10   // 0x10  RW   window length in clocks
`define ENC_REG_FILTER      8'h14   // 0x14  RW   glitch filter cycles [3:0]
`define ENC_REG_SCALE       8'h18   // 0x18  RW   signed Q16.16 speed scale
`define ENC_REG_STALL_TMO   8'h1C   // 0x1C  RW   stall timeout in clocks
`define ENC_REG_REV_COUNT   8'h20   // 0x20  RO   revolution counter
`define ENC_REG_INDEX_POS   8'h24   // 0x24  RO   count captured at last index
`define ENC_REG_RAW_DELTA   8'h28   // 0x28  RO   signed count delta of last window
`define ENC_REG_IRQ_EN      8'h2C   // 0x2C  RW   interrupt enable mask
`define ENC_REG_VERSION     8'h30   // 0x30  RO   version constant

// Number of valid registers (word indices 0x00..0x30 -> indices 0..12)
`define ENC_NUM_REGS        13

// Maximum valid byte offset (inclusive)
`define ENC_ADDR_MAX        8'h30

// ---------------------------------------------------------------------------
// ENC_CTRL bit positions  [0x08]
// ---------------------------------------------------------------------------
`define ENC_CTRL_ENABLE         0   // [0]  RW   enable decoder and counters
`define ENC_CTRL_COUNT_RESET    1   // [1]  RW   write 1 = self-clearing count reset
`define ENC_CTRL_MODE_LO        2   // [3:2] RW  quadrature mode LSB
`define ENC_CTRL_MODE_HI        3   // [3:2] RW  quadrature mode MSB
`define ENC_CTRL_AVG_SEL_LO     4   // [5:4] RW  moving-average selector LSB
`define ENC_CTRL_AVG_SEL_HI     5   // [5:4] RW  moving-average selector MSB
`define ENC_CTRL_SWAP_AB        6   // [6]  RW   swap A/B sense (reverse direction)
`define ENC_CTRL_INDEX_CLR_EN   7   // [7]  RW   index clears count when 1
`define ENC_CTRL_DRIVE_ASSERT   8   // [8]  RW   software drive-active assertion
`define ENC_CTRL_FAULT_EN       9   // [9]  RW   gate fault_o with this bit

// MODE field encoding (bits [3:2])
`define ENC_MODE_X1         2'b00   // x1  – one edge of A
`define ENC_MODE_X2         2'b01   // x2  – both edges of A
`define ENC_MODE_X4         2'b10   // x4  – all edges of A and B
`define ENC_MODE_X4_RSV     2'b11   // reserved, treated as x4

// AVG_SEL field encoding (bits [5:4])
`define ENC_AVG_1           2'b00   // moving average over 1 sample (bypass)
`define ENC_AVG_2           2'b01   // moving average over 2 samples
`define ENC_AVG_4           2'b10   // moving average over 4 samples
`define ENC_AVG_8           2'b11   // moving average over 8 samples

// ---------------------------------------------------------------------------
// ENC_STATUS bit positions  [0x0C]
//
//   TYPE ANNOTATIONS:
//     [0] VALID       RO/W1C  – sticky; new speed update ready
//     [1] DIR         RO      – current rotation direction (1=forward)
//     [2] OVERFLOW    RO/W1C  – sticky; signed 32-bit count wrapped
//     [3] ILLEGAL     RO/W1C  – sticky; illegal A+B simultaneous transition
//     [4] STALL       RO/W1C  – sticky; drive active, no edge within STALL_TMO
//     [5] INDEX_SEEN  RO/W1C  – sticky; index (Z) rising edge detected
//
//   fault_o = (ILLEGAL | STALL) & FAULT_EN  (level)
//   inta_o  = |(STATUS & IRQ_EN_MASK)       (level)
// ---------------------------------------------------------------------------
`define ENC_STAT_VALID      0       // [0]  RO/W1C  new filtered speed ready
`define ENC_STAT_DIR        1       // [1]  RO      direction: 1=forward
`define ENC_STAT_OVERFLOW   2       // [2]  RO/W1C  count overflow
`define ENC_STAT_ILLEGAL    3       // [3]  RO/W1C  illegal transition
`define ENC_STAT_STALL      4       // [4]  RO/W1C  stall detected
`define ENC_STAT_INDEX_SEEN 5       // [5]  RO/W1C  index pulse seen

// W1C-able mask (bits that can be cleared by writing 1)
`define ENC_STAT_W1C_MASK   6'h3D   // bits 0,2,3,4,5; bit 1 (DIR) is RO

// ---------------------------------------------------------------------------
// Register reset values
// ---------------------------------------------------------------------------
`define ENC_RST_COUNT       32'h0000_0000   // position count = 0
`define ENC_RST_SPEED       32'h0000_0000   // speed = 0
`define ENC_RST_CTRL        32'h0000_0000   // all disabled
`define ENC_RST_STATUS      32'h0000_0000   // no events
`define ENC_RST_WINDOW      32'd100000      // 100,000 clock cycles
`define ENC_RST_FILTER      32'h0000_0002   // 2-cycle glitch filter
`define ENC_RST_SCALE       32'h0001_0000   // 1.0 in Q16.16
`define ENC_RST_STALL_TMO   32'h0000_0000   // 0 = disabled
`define ENC_RST_REV_COUNT   32'h0000_0000
`define ENC_RST_INDEX_POS   32'h0000_0000
`define ENC_RST_RAW_DELTA   32'h0000_0000
`define ENC_RST_IRQ_EN      32'h0000_0000   // all masked
`define ENC_RST_VERSION     32'h0001_0000   // v1.0

// ---------------------------------------------------------------------------
// Version identifier
// ---------------------------------------------------------------------------
`define ENC_VERSION_ID      32'h0001_0000

`endif // ENC_DEFINES_V
