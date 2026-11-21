# PID Controller IP — Design Reference

**Project:** Motor-Control SoC  
**Version:** 1.1  
**Date:** 2026-10-03  
**Author:** Honours CBP Project  
**License:** MIT

---

## 1. Purpose

The PID Controller IP provides a synthesizable, fixed-point, fully digital
Proportional-Integral-Derivative controller intended for closed-loop motor
speed control:

```
encoder (actual speed)
        |
        v
      PID IP  <--- setpoint (from CPU via AXI4 register write)
        |
        v
    PWM IP
        |
        v
      Motor
```

The CPU configures gains, limits, and operating modes through an AXI4 slave
register interface.  The PID update is triggered either by an external
periodic tick signal or by a software manual-update command.

---

## 2. PID Architecture

### Fixed-point representation

All gains are Q16.16 signed fixed-point:

- Bit [31:16] — integer part (signed)
- Bit [15:0]  — fractional part

Arithmetic widths:

| Symbol  | Value | Description                         |
|---------|-------|-------------------------------------|
| SPEED_W | 16    | Setpoint / actual speed width       |
| OUT_W   | 16    | Output width                        |
| GAIN_W  | 32    | Q16.16 gain width                   |
| FRAC    | 16    | Fractional bits                     |
| ERR_W   | 17    | Error width = SPEED_W + 1           |
| DERIV_W | 18    | Derivative width = ERR_W + 1 (prevents overflow on large steps) |
| PROD_W  | 50    | Product width = GAIN_W + DERIV_W    |
| ACC_W   | 54    | Accumulator width = PROD_W + 4      |

### PID algorithm (per update cycle)

```
error       = setpoint - actual               // ERR_W (17-bit signed)
derivative  = error - error_prev              // DERIV_W (18-bit signed)
              OR -(actual - actual_prev)       // depending on D_ON_MEAS

P = Kp × error                                // PROD_W (50-bit)
I = integrator + Ki × error                   // ACC_W  (54-bit)
D = Kd × derivative                           // PROD_W (50-bit)

sum = P + clamped(I) + D                      // ACC_W+2 wide
output = round(sum >> FRAC)                   // arithmetic right shift with rounding
output = clamp(output, OUT_MIN, OUT_MAX)
```

### Rounding

```
ROUND_C = 1 << (FRAC - 1)   // 0x8000 in ACC_W representation
output_raw = (sum + ROUND_C) >>> FRAC   // arithmetic signed right shift
```

### Integrator saturation

The pre-accumulation value `i_pre = integrator + ki_e` is clamped to
`[INT_MIN, INT_MAX]` before the final sum.  The `INT_SAT` flag is set when
clamping occurs.

### Anti-windup (conditional integration)

When `AW_EN = 1`:
- If output is clamped HIGH and error is positive → discard `i_new`, keep old integrator
- If output is clamped LOW and error is negative → discard `i_new`, keep old integrator
- Otherwise → commit `i_new`

This is a **conditional-integration** scheme (not back-calculation).

### Derivative kick suppression

On the first update after reset, ENABLE rising edge, or INT_RESET, the
derivative term is forced to zero and the previous-value registers are loaded
with the current sample.  This prevents a large derivative spike on the first
cycle.

---

## 3. File Structure

```
CBP/rtl/pid_controler/
    pid_defines.v       — compile-time constants, register map, FSM states
    pid_core.v          — PID datapath, FSM, arithmetic
    pid_axi_slave.v     — AXI4 slave register file and bus interface
    pid_top.v           — top-level: reset synchronizer + instances

CBP/README/
    pid_controller_README.md   — this document
```

---

## 4. Module Responsibilities

### pid_defines.v
Compile-time `define macros only:
- Register map offsets (`PID_REG_*`)
- CTRL bit positions (`PID_CTRL_*`)
- STATUS bit positions with type annotations (`PID_STAT_*`)
- Reset values, version ID
- FSM state encodings (4-bit binary)
- Data-path width definitions
- INT_MAX/INT_MIN 32-bit register storage convention

### pid_core.v
PID datapath and FSM:
- Fixed-point signed arithmetic (explicit sign extension throughout)
- 8-state FSM (IDLE → LATCH → MUL_P → MUL_I → MUL_D → SUM → CLAMP → COMMIT)
- Shared multiplier sequencing (one multiply per FSM state)
- Integrator saturation clamping
- Output saturation clamping
- Conditional-integration anti-windup
- Derivative-on-error or derivative-on-measurement
- Gain/limit shadowing (inputs latched at LATCH state)
- `sat_flag_o` level output
- INT_RESET highest-priority abort (also in FSM next-state logic)
- ENABLE=0 abort at any state including COMMIT

### pid_axi_slave.v
AXI4 slave register file:
- Full AXI4 (not AXI4-Lite): independent AW/W channel acceptance
- Write burst draining until WLAST (WR_DRAIN state)
- Multi-beat read: ARLEN+1 beats of zero data + SLVERR
- Sticky W1C: DONE, OVERRUN (new-event priority over simultaneous clear)
- Sticky RO: SAT_HI, SAT_LO, INT_SAT (not clearable by software)
- `irq_o` level output: `(w1c_done | w1c_overrun) & ctrl_irq_en`
- 16-bit sign-extension validation for SETPOINT, OUT_MAX, OUT_MIN
- WSTRB byte-lane support
- SLVERR for invalid/misaligned/burst accesses; invalid reads return 0

### pid_top.v
Top-level integration:
- 2-flop async-assert / sync-deassert reset synchronizer
- Instantiates pid_core and pid_axi_slave
- Routes `irq_o` → `inta_o` (sticky level interrupt)
- Exposes `sat_flag_o` at the top level
- Does NOT contain any SoC base address assignment

---

## 5. Full AXI4 Interface

The PID IP implements a **Full AXI4** slave, not AXI4-Lite.

### Port list (pid_top.v)

| Channel  | Signal          | Width          | Direction |
|----------|-----------------|----------------|-----------|
| Global   | s_axi_aclk      | 1              | in        |
| Global   | s_axi_aresetn   | 1              | in        |
| AW       | s_axi_awid      | ID_WIDTH (8)   | in        |
| AW       | s_axi_awaddr    | ADDR_WIDTH(32) | in        |
| AW       | s_axi_awlen     | 8              | in        |
| AW       | s_axi_awsize    | 3              | in        |
| AW       | s_axi_awburst   | 2              | in        |
| AW       | s_axi_awlock    | 1              | in        |
| AW       | s_axi_awcache   | 4              | in        |
| AW       | s_axi_awprot    | 3              | in        |
| AW       | s_axi_awvalid   | 1              | in        |
| AW       | s_axi_awready   | 1              | out       |
| W        | s_axi_wdata     | 32             | in        |
| W        | s_axi_wstrb     | 4              | in        |
| W        | s_axi_wlast     | 1              | in        |
| W        | s_axi_wvalid    | 1              | in        |
| W        | s_axi_wready    | 1              | out       |
| B        | s_axi_bid       | ID_WIDTH (8)   | out       |
| B        | s_axi_bresp     | 2              | out       |
| B        | s_axi_bvalid    | 1              | out       |
| B        | s_axi_bready    | 1              | in        |
| AR       | s_axi_arid      | ID_WIDTH (8)   | in        |
| AR       | s_axi_araddr    | ADDR_WIDTH(32) | in        |
| AR       | s_axi_arlen     | 8              | in        |
| AR       | s_axi_arsize    | 3              | in        |
| AR       | s_axi_arburst   | 2              | in        |
| AR       | s_axi_arlock    | 1              | in        |
| AR       | s_axi_arcache   | 4              | in        |
| AR       | s_axi_arprot    | 3              | in        |
| AR       | s_axi_arvalid   | 1              | in        |
| AR       | s_axi_arready   | 1              | out       |
| R        | s_axi_rid       | ID_WIDTH (8)   | out       |
| R        | s_axi_rdata     | 32             | out       |
| R        | s_axi_rresp     | 2              | out       |
| R        | s_axi_rlast     | 1              | out       |
| R        | s_axi_rvalid    | 1              | out       |
| R        | s_axi_rready    | 1              | in        |

### PID external ports

| Signal          | Width | Direction | Description                          |
|-----------------|-------|-----------|--------------------------------------|
| tick_i          | 1     | in        | Periodic update trigger              |
| actual_i        | 16    | in        | Measured speed (signed)              |
| pid_out_o       | 16    | out       | PID output (signed)                  |
| pid_out_valid_o | 1     | out       | One-cycle pulse when output is valid |
| sat_flag_o      | 1     | out       | Level: last update hit sat limit     |
| inta_o          | 1     | out       | Level interrupt (sticky DONE/OVERRUN & IRQ_EN) |

---

## 6. Register Map

Base address: **TBD — will be assigned at SoC integration time.**

All registers are 32-bit word aligned.

| Offset | Name         | Type      | Reset      | Description                          |
|--------|--------------|-----------|------------|--------------------------------------|
| 0x00   | PID_SETPOINT | RW        | 0x0000     | Signed 16-bit setpoint (sign-ext to 32) |
| 0x04   | PID_KP       | RW        | 0x00000000 | Q16.16 proportional gain             |
| 0x08   | PID_KI       | RW        | 0x00000000 | Q16.16 integral gain                 |
| 0x0C   | PID_KD       | RW        | 0x00000000 | Q16.16 derivative gain               |
| 0x10   | PID_OUTPUT   | RO        | —          | Signed output, sign-extended to 32   |
| 0x14   | PID_CTRL     | RW        | 0x00000000 | Control register (see below)         |
| 0x18   | PID_STATUS   | RO/W1C    | 0x00000000 | Status register (see below)          |
| 0x1C   | PID_ERROR    | RO        | —          | Signed error, sign-extended to 32    |
| 0x20   | PID_ACTUAL   | RO        | —          | Latched actual speed, sign-extended  |
| 0x24   | PID_OUT_MAX  | RW        | 0x00007FFF | Output upper clamp (+32767)          |
| 0x28   | PID_OUT_MIN  | RW        | 0x00000000 | Output lower clamp (0)               |
| 0x2C   | PID_INT_MAX  | RW        | 0x7FFFFFFF | Integrator upper clamp (lower 32b)   |
| 0x30   | PID_INT_MIN  | RW        | 0x80000000 | Integrator lower clamp (lower 32b)   |
| 0x34   | PID_VERSION  | RO        | 0x00010000 | Version ID                           |

All other addresses: read returns 0, write is ignored (SLVERR).

### PID_CTRL [0x14]

| Bit | Name          | Access | Description                            |
|-----|---------------|--------|----------------------------------------|
| 0   | ENABLE        | RW     | Enable PID updates                     |
| 1   | INT_RESET     | RW     | One-cycle command: clear integrator, e_prev, act_prev; abort active update |
| 2   | MANUAL_UPDATE | RW     | Self-clearing: trigger one update      |
| 3   | D_ON_MEAS     | RW     | 0=derivative on error, 1=on measurement|
| 4   | AW_EN         | RW     | Enable conditional-integration anti-windup |
| 5   | IRQ_EN        | RW     | Enable interrupt output                |
| 31:6| —             | —      | Reserved, reads 0                      |

### PID_STATUS [0x18]

| Bit | Name    | Type          | Description                                           |
|-----|---------|---------------|-------------------------------------------------------|
| 0   | BUSY    | RO            | Update in progress                                    |
| 1   | DONE    | RO / W1C      | Update completed (sticky; write 1 to clear)           |
| 2   | SAT_HI  | RO sticky     | Output clamped HIGH (sticky; **not clearable by SW**) |
| 3   | SAT_LO  | RO sticky     | Output clamped LOW (sticky; **not clearable by SW**)  |
| 4   | INT_SAT | RO sticky     | Integrator clamped (sticky; **not clearable by SW**)  |
| 5   | OVERRUN | RO / W1C      | Tick arrived while BUSY (sticky; write 1 to clear)    |
| 31:6| —       | —             | Reads 0                                               |

---

## 7. Fixed-Point Representation

Gains Kp, Ki, Kd are Q16.16 signed values:
```
actual_value = register_value / 65536.0
```
Example: Kp = 1.5 → write 0x00018000

SETPOINT, OUT_MAX, OUT_MIN, PID_OUTPUT, PID_ERROR, PID_ACTUAL are signed
16-bit values sign-extended to 32 bits in the register.

For **SETPOINT, OUT_MAX, OUT_MIN writes**: the upper 16 bits (bits [31:16])
must equal the sign-extension of bit [15].  An invalid upper-half encoding
returns SLVERR and the register is not modified.

Valid write examples: `0x00007FFF`, `0xFFFF8000`, `0xFFFFFFFF`  
Invalid: `0x00010000`, `0x0000FFFF`

---

## 8. PID Algorithm Step-by-Step

1. **LATCH** — Capture setpoint, actual, Kp, Ki, Kd, OUT_MAX, OUT_MIN, INT_MAX, INT_MIN, D_ON_MEAS, AW_EN into shadow registers.  Compute error (17-bit) and derivative (18-bit) from the latched values.

2. **MUL_P** — `p_term = Kp × error` (50-bit product)

3. **MUL_I** — `ki_e = Ki × error` (50-bit product)

4. **MUL_D** — `d_term = Kd × derivative` (50-bit product)

5. **SUM** — `i_pre = integrator + ki_e` (54-bit); `sum_pd = p_term + d_term` (56-bit)

6. **CLAMP** — Clamp `i_pre` to `[INT_MIN, INT_MAX]` → `i_new`; compute `full_sum = sum_pd + i_clamped`; round and scale to output; clamp output to `[OUT_MIN, OUT_MAX]`; set `sat_hi_r` / `sat_lo_r` / `int_sat_r`

7. **COMMIT** — Apply anti-windup decision to integrator; commit `pid_out_o`, `error_o`, `actual_o`; pulse `pid_out_valid_o`, `done_o`, `sat_hi_o`, `sat_lo_o`, `int_sat_o`; update `sat_flag_o` level; clear `busy_o`

---

## 9. FSM States and Latency

States (binary-encoded, 4 bits):

| Encoding | State  | Action                                    |
|----------|--------|-------------------------------------------|
| 4'h0     | IDLE   | Wait for ENABLE + tick or MANUAL_UPDATE   |
| 4'h1     | LATCH  | Capture shadow registers; compute e, d    |
| 4'h2     | MUL_P  | p_term = Kp × e                           |
| 4'h3     | MUL_I  | ki_e   = Ki × e                           |
| 4'h4     | MUL_D  | d_term = Kd × d                           |
| 4'h5     | SUM    | i_pre = integrator + ki_e; sum_pd = P+D   |
| 4'h6     | CLAMP  | Clamp integrator; complete sum; round; clamp output |
| 4'h7     | COMMIT | Anti-windup; commit results; pulse outputs |

**Latency:** 8 clock cycles from the clock edge where IDLE detects the tick
to the clock edge where `pid_out_valid_o` is pulsed (7 active states + 1 cycle
for IDLE→LATCH transition).

INT_RESET aborts any in-progress state immediately (via FSM next-state logic)
and returns to IDLE in one clock cycle.

---

## 10. Output Saturation

```
if (u_raw > OUT_MAX):   u = OUT_MAX;  SAT_HI = 1
if (u_raw < OUT_MIN):   u = OUT_MIN;  SAT_LO = 1
otherwise:              u = u_raw
```

`sat_flag_o` is a **level** output set to `SAT_HI | SAT_LO` at COMMIT.
It reflects whether the **most recent completed** update was saturated.
It is cleared on reset and when ENABLE = 0.  It is overwritten by each
subsequent COMMIT.

`SAT_HI` and `SAT_LO` in PID_STATUS are **sticky RO** bits — they accumulate
from core pulses and cannot be cleared by software.

---

## 11. Integral Saturation

```
if (i_pre > INT_MAX):   i_new = INT_MAX;  INT_SAT = 1
if (i_pre < INT_MIN):   i_new = INT_MIN;  INT_SAT = 1
otherwise:              i_new = i_pre
```

`INT_SAT` in PID_STATUS is **sticky RO** — accumulated from core pulses,
not clearable by software.

---

## 12. Anti-Windup Behavior

When `AW_EN = 1` (conditional-integration):

- Output clamped HIGH (`sat_hi_r = 1`) AND `error > 0` → discard `i_new`, keep `integrator` unchanged
- Output clamped LOW (`sat_lo_r = 1`) AND `error < 0` → discard `i_new`, keep `integrator` unchanged
- Otherwise → commit `i_new` to `integrator`

When `AW_EN = 0`: always commit `i_new`.

---

## 13. Derivative Handling

**Derivative width:** 18-bit signed (`DERIV_W = 18`).  This prevents
overflow when `error` changes by the full-scale range between two
consecutive updates (maximum difference ≈ ±131070 which exceeds 17-bit range).

**D-on-error** (`D_ON_MEAS = 0`):
```
d = sign_ext_18(e_current) - sign_ext_18(e_prev)
```

**D-on-measurement** (`D_ON_MEAS = 1`):
```
d = -(sign_ext_18(actual) - sign_ext_18(actual_prev))
```

**First update suppression:** On the first update after reset / ENABLE rising
edge / INT_RESET, `d = 0` is forced.  This eliminates derivative kick.

---

## 14. Gain and Limit Shadowing

At the start of each update cycle (LATCH state), the current register values
for Kp, Ki, Kd, OUT_MAX, OUT_MIN, INT_MAX, INT_MIN, D_ON_MEAS, and AW_EN are
captured into shadow registers.  Any software writes to these registers while
the FSM is busy will not affect the current calculation — they take effect only
at the start of the next update.

---

## 15. Reset Behavior

- Reset signal: `s_axi_aresetn` (active-low)
- Assertion: asynchronous (immediately resets the 2-flop synchronizer)
- Deassertion: synchronous through 2-flop synchronizer in `pid_top.v`
- Synchronized reset (`rst_n_sync`) is distributed to both `pid_core` and `pid_axi_slave`
- No `initial` blocks; no register initializers; all registers have explicit reset assignments
- On reset: all registers zero; `first_update = 1`; FSM returns to IDLE; all status bits clear

---

## 16. Interrupt Behavior

```
inta_o = (w1c_done | w1c_overrun) & ctrl_irq_en
```

- `inta_o` is a **level** signal, asserted as long as `DONE` or `OVERRUN`
  sticky bits are set and `IRQ_EN = 1`
- Driven from `pid_axi_slave.irq_o` → `pid_top.inta_o`
- **Not** derived from one-cycle core pulses (corrected in v1.1)
- Deasserts when software clears `DONE` and `OVERRUN` via W1C, or when `IRQ_EN = 0`

---

## 17. AXI Transaction Assumptions and Unsupported-Access Behavior

### Supported (RESP_OKAY)
- Single-beat write (`AWLEN = 0`, `AWSIZE = 2`, 4-byte aligned address), address maps to a writable register, data passes 16-bit sign-extension check (for SETPOINT/OUT_MAX/OUT_MIN)
- Single-beat read (`ARLEN = 0`, `ARSIZE = 2`, 4-byte aligned address), address maps to any register

### SLVERR returned, no register modified
- Misaligned address (bits [1:0] ≠ 00)
- Address outside the register map (offset > 0x34)
- Write to read-only register (treated as no-op via default case)
- Multi-beat write burst (`AWLEN > 0`): all W beats are drained until `WLAST`; one SLVERR BRESP is returned
- Multi-beat read burst (`ARLEN > 0`): `ARLEN + 1` beats are returned, all with `RDATA = 0` and `RRESP = SLVERR`; `RLAST` asserted only on the final beat
- 16-bit register write where bits [31:16] are not a valid sign extension of bit [15]

### AXI4 handshake properties maintained
- AW and W channels are accepted independently (AXI4, not AXI4-Lite)
- `BID = AWID` of the corresponding write transaction
- `RID = ARID` of the corresponding read transaction
- `BVALID` held until `BREADY`
- `RVALID` held until `RREADY`
- No combinational `VALID → READY` path
- One outstanding write transaction at a time (new AW not accepted until previous B is consumed)

---

## 18. INT_MAX / INT_MIN 32-bit Register Representation

`ACC_W = 54` bits but the AXI registers `PID_INT_MAX` (0x2C) and
`PID_INT_MIN` (0x30) are 32 bits.  Only the **lower 32 bits** are stored.
Inside `pid_core`, the 54-bit internal limit is reconstructed by sign-extending
bit [31]:

```
limit[53:0] = { {22{reg[31]}}, reg[31:0] }
```

Software must choose integrator limit values in the range `[-2^31 .. 2^31-1]`.
Values outside this range require wider 54-bit limit registers (not currently
supported via the register interface).

---

## 19. Assumptions and Limitations

1. The AXI clock (`s_axi_aclk`) is the only clock in the design.
2. `tick_i` and `actual_i` are assumed to be in the same clock domain.
3. The PID has one outstanding write transaction at a time.
4. Burst transactions on the register interface are not supported for functional access (single-beat only); bursts are drained and rejected with SLVERR.
5. The PID does not implement stall/fault inputs beyond what is already present.
6. No SoC base address has been assigned; integration is deferred.
7. `SAT_HI`, `SAT_LO`, and `INT_SAT` in PID_STATUS are sticky RO — once set they remain set until the next reset. There is no software-visible clear for these bits.
8. `INT_RESET` clears the integrator and previous-value registers but does not clear `SAT_HI`, `SAT_LO`, or `INT_SAT` in the status register.

---

## 20. Verification Commands Executed

The following commands were actually executed from the PID RTL directory:

```bash
cd /home/student/Documents/090_honrors/CBP/rtl/pid_controler

vcs -full64 -sverilog +v2k +lint=all \
    pid_defines.v pid_core.v pid_axi_slave.v pid_top.v \
    -o /tmp/pid_chk
```

Tool: VCS U-2023.03_Full64, Rocky Linux 8.10 x86_64

---

## 21. Exact Verification Results

```
Parsing design file 'pid_defines.v'
Parsing design file 'pid_core.v'
  Included: pid_defines.v
Parsing design file 'pid_axi_slave.v'
  Included: pid_defines.v
Parsing design file 'pid_top.v'
  Included: pid_defines.v

Top Level Modules: pid_top
No TimeScale specified

Lint-[NS] Null statement  (pid_core.v:602)
  default: ;  — intentional, correct Verilog-2001 style

Lint-[NS] Null statement  (pid_axi_slave.v:467)
  ; in PID_REG_STATUS case — intentional (W1C handled in blk_w1c)

Lint-[NS] Null statement  (pid_axi_slave.v:507)
  default: ;  — intentional

Lint-[UI] Unused input  (x8: awburst, awlock, awcache, awprot,
                              arburst, arlock, arcache, arprot)
  These are required AXI4 protocol ports.  A single-beat register
  peripheral does not act on these sideband signals functionally.
  Removing them would break AXI4 compliance.  wlast is now USED
  (in WR_DRAIN) and no longer generates a UI warning.

Errors:   0
Warnings: 0
CPU time: .161 seconds to compile + .153 seconds to elab + .093 seconds to link
```

iverilog and verilator were not available on this system.  The VCS compile +
elaborate + link cycle serves as the primary syntax and elaboration check.

---

## 22. Known Issues / Remaining Items

1. **Base address not assigned** — SoC integration is deferred; no base address is hard-coded.
2. **SAT_HI / SAT_LO / INT_SAT are not software-clearable** — by design per the original spec. Software must rely on reset or power-cycle to clear these bits.
3. **One outstanding write at a time** — the slave does not queue multiple write transactions.  This is intentional for a register peripheral.
4. **No stall / fault input** — not specified in the current architecture.
5. **Functional simulation** — deferred to the next phase (Phase 2).  No functional test vectors have been applied.
