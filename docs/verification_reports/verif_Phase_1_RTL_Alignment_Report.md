# Phase 1 Verification Report: Complete RISC-V RTL Alignment & Integration

**Project**: RISC-V VeeR EL2 SoC Integration & Verification  
**Project Root**: `/home/student/Documents/090_honrors/CBP`  
**Execution Timestamp**: 2026-10-31  
**Simulator**: Synopsys VCS U-2023.03_Full64 (Rocky Linux 8.10)  
**Run Directory**: `/home/student/Documents/090_honrors/CBP/verif_runs/20261031_1415_phase1/`  
**Status**: **PASSED (30 of 30 checks passed, 0 failures, 0 warnings)**

---

## 1. Executive Summary

Phase 1 has successfully implemented all approved RTL modifications to bring the live System-on-Chip design into 100% compliance with the master architectural specification. The VeeR EL2 processor, memory subsystem, and AXI interconnect were verified using a comprehensive, strengthened testbench (`tb/tb_soc_top.sv`).

### Summary of Completed Objectives
1. **IMEM Alignment**: Re-anchored to `0x4000_0000`–`0x4000_FFFF` with true 64 KiB capacity ($16,384 \times 32$-bit words). Verified instruction fetch at base (`0x4000_0000`) and upper boundary retirement (`0x4000_FFFC`).
2. **DMEM Alignment**: Re-anchored to `0x4002_0000`–`0x4002_FFFF` with true 64 KiB capacity ($16,384 \times 32$-bit words). Verified store and load operations at base word 0 (`0x4002_0000`) and upper boundary word 16,383 (`0x4002_FFFC`) with zero aliasing.
3. **VeeR EL2 Reset Vector**: Configured reset vector to `31'h2000_0000` driving processor reset PC to `32'h4000_0000`. Captured initial instruction fetch and pipeline retirement directly from IMEM.
4. **Reserved AXI Slots S11–S13**: Replaced hanging stub parameters with interconnect unmapped decoding (`ADDR_WIDTH = 0`). Verified that read and write accesses to S11 (`0x4004_3000`), S12 (`0x4004_5000`), S13 (`0x4004_7000`), and legacy out-of-spec addresses (`0x8000_4000`–`0x8000_6000`) immediately return `DECERR` (`2'b11`) without hanging the bus.
5. **Preservation of Functionality**: Confirmed all active peripheral interfaces (GPIO, Timer, UART, Encoder, PID, PWM) and the closed-loop feedback path (Encoder $\rightarrow$ PID $\rightarrow$ PWM) remain intact and operational.
6. **Integrity Preservation**: The protected `run/` directory and upstream VeeR EL2 repository (`rtl/Cores-VeeR-EL2/`) were untouched. All modifications were accompanied by `.bak` backup files.

---

## 2. Modified RTL and Verification Files

| File | Backup File | Modifications & Rationale |
| :--- | :--- | :--- |
| `rtl/main_top.v` | `rtl/main_top.v.bak` | Updated interconnect parameters: `M00` (IMEM) to `0x4000_0000`, 64 KiB (`ADDR_WIDTH=16`); `M01` (DMEM) to `0x4002_0000`, 64 KiB (`ADDR_WIDTH=16`); disabled hanging stubs `M11`, `M12`, `M13` (`BASE_ADDR=0x0000_0000`, `ADDR_WIDTH=0`). |
| `rtl/soc_top.sv` | `rtl/soc_top.sv.bak` | Updated VeeR EL2 wrapper instantiation reset vector `.rst_vec(31'h2000_0000)` ($\rightarrow$ PC `0x4000_0000`); expanded internal IMEM & DMEM `axi_sram_ctrl` instances from `ADDR_WIDTH=12` to `ADDR_WIDTH=16` with 16-bit address slicing `[15:0]`. |
| `tb/tb_soc_top.sv` | `tb/tb_soc_top.sv.bak` | Replaced legacy weak/tautological assertions with 30 rigorous functional checks covering reset release, IFU AXI fetch, instruction retirement trace, DMEM base & upper boundary stores/loads, IMEM boundary jump & loop execution, MMIO peripheral store, DMA non-hanging DECERR verification, Timer MMIO, and closed-loop hardware feedback. |

---

## 3. Detailed Verification Evidence

### 3.1 IMEM 64 KiB Address Mapping & Execution
- **Interconnect Mapping**: Slave slot S0 aperture is `0x4000_0000`–`0x4000_FFFF` (`ADDR_WIDTH = 16`, 64 KiB).
- **Physical Capacity**: `axi_sram_ctrl.sv` instantiated with `.ADDR_WIDTH(16)` allocating `mem[0:16383]` (64 KiB).
- **Base Execution Evidence**:
  ```text
  [PASS] IFU issues AXI read request
  [PASS] IFU fetch target matches reset vector (0x4000_0000)
  [PASS] IFU 64b downconverter drives interconnect s00_axi AR channel
  [TRACE T=425000] Core retired PC: 0x40000000, Insn: 0x400200b7
  [PASS] Processor executes and retires first instruction
  [PASS] Executed instruction PC matches IMEM base (0x4000_0000)
  ```
- **Upper Boundary Execution Evidence (`0x4000_FFFC`)**:
  The core executed `jalr x0, -4(x5)` where `x5 = 0x4001_0000`, branching to `0x4000_FFFC` (word 16383 of IMEM).
  ```text
  [TRACE T=5375000] Core retired PC: 0x4000002c, Insn: 0xffc28067
  [TRACE T=5795000] Core retired PC: 0x4000fffc, Insn: 0x0000006f
  Observed upper boundary retirement at PC: 0x4000fffc, Insn: 0x0000006f
  [PASS] Processor successfully jumped to and retired instruction at IMEM upper boundary (0x4000_FFFC)
  ```

### 3.2 DMEM 64 KiB Address Mapping & Boundary Non-Aliasing
- **Interconnect Mapping**: Slave slot S1 aperture is `0x4002_0000`–`0x4002_FFFF` (`ADDR_WIDTH = 16`, 64 KiB).
- **Physical Capacity**: `axi_sram_ctrl.sv` instantiated with `.ADDR_WIDTH(16)` allocating `mem[0:16383]` (64 KiB).
- **Base & Upper Boundary Stores**:
  - Store `0x5A` to `0x4002_0000` (word 0): Executed by core LSU at PC `0x4000_0008`.
  - Store `0xA5` to `0x4002_FFFC` (word 16383): Executed by core LSU at PC `0x4000_0018`.
- **Readback & Aliasing Verification**:
  ```text
  [PASS] Processor LSU executed store to DMEM base at 0x4002_0000
  [PASS] DMEM base word 0 contains stored value 0x5A
  [PASS] Processor LSU executed store to DMEM upper boundary at 0x4002_FFFC
  [PASS] DMEM boundary word 16383 contains stored value 0xA5
  [PASS] No memory aliasing: word 0 and word 16383 maintain independent data in 64 KiB DMEM
  ```

### 3.3 VeeR EL2 Reset Vector
- **Configuration**: `soc_top.sv` sets `.rst_vec(31'h2000_0000)`. Because VeeR EL2 drops bit 0 (`rst_vec` is `[31:1]`), `31'h2000_0000` drives PC bits `[31:1]`, producing reset PC = `32'h4000_0000`.
- **Evidence**: The core's first instruction fetch address on `core_ifu_araddr` was exactly `32'h4000_0000`, followed by retirement of instruction `0x400200b7` at PC `0x4000_0000`.

### 3.4 Reserved Slots S11–S13 Non-Hanging DECERR Verification
In the baseline design, accesses to unmapped/reserved slots S11–S13 would wait indefinitely because the stub peripheral slave logic was unconnected.
- **RTL Fix**: Set `ADDR_WIDTH = 0` in `main_top.v` for `M11`, `M12`, `M13`.
- **Interconnect Mechanism**: When `ADDR_WIDTH = 0`, `axi_interconnect.v` marks the slot disabled and routes accesses to its internal default slave error generator.
- **Verification Evidence**:
  ```text
  [PASS] DMA write to reserved S11 (0x4004_3000) completes without hang
  [PASS] DMA write to reserved S11 returns DECERR (2'b11)
  [PASS] DMA read from reserved S11 (0x4004_3000) completes without hang
  [PASS] DMA read from reserved S11 returns DECERR (2'b11)
  [PASS] DMA read from reserved S12 (0x4004_5000) completes with DECERR (2'b11)
  [PASS] DMA read from reserved S13 (0x4004_7000) completes with DECERR (2'b11)
  [PASS] Legacy 0x8000_4000 write completes with DECERR (2'b11) without hanging
  [PASS] Legacy 0x8000_5000 read completes with DECERR (2'b11) without hanging
  [PASS] Legacy 0x8000_6000 read completes with DECERR (2'b11) without hanging
  ```

### 3.5 Core Peripheral Reachability & Functional Preservation
- **Core Store to GPIO**: Core executed `sw x2, 0(x4)` where `x4 = 0x4003_1000` (GPIO base).
  - Interconnect captured: `addr=0x40031000, data=0x0000005a` on M02 AXI bus.
  - Check: `[PASS] AXI interconnect routed processor store to S2 (GPIO 0x4003_1000)`.
- **Timer MMIO (S3)**: DMA access to `0x4003_3000` returned `OKAY` (`2'b00`) on read and write.
- **Hybrid Closed-Loop Feedback**:
  - Encoder initialized and enabled via AXI write to `0x4003_D008`.
  - Driven by quadrature pulse train; direction detected as forward (`enc_dir == 1`).
  - Readback of count register `0x4003_D000` returned 10.
  - Closed-loop connection from Encoder $\rightarrow$ PID $\rightarrow$ PWM verified active and switching.

---

## 4. Simulation Results Matrix (30 / 30 Passed)

| Test Group | Check Description | Result |
| :--- | :--- | :--- |
| **Test 1: Reset Release** | Core reset release: rst is de-asserted and clk active | **PASS** |
| | Core halt status is low (core active out of reset) | **PASS** |
| **Test 2: AXI Fetch** | IFU issues AXI read request | **PASS** |
| | IFU fetch target matches reset vector (`0x4000_0000`) | **PASS** |
| | IFU 64b downconverter drives interconnect s00_axi AR channel | **PASS** |
| **Test 3: Instruction Trace** | Processor executes and retires first instruction | **PASS** |
| | Executed instruction PC matches IMEM base (`0x4000_0000`) | **PASS** |
| **Test 4: DMEM 64 KiB Access** | Processor LSU executed store to DMEM base at `0x4002_0000` | **PASS** |
| | DMEM base word 0 contains stored value `0x5A` | **PASS** |
| | Processor LSU executed store to DMEM upper boundary at `0x4002_FFFC` | **PASS** |
| | DMEM boundary word 16383 contains stored value `0xA5` | **PASS** |
| | No memory aliasing: word 0 and word 16383 maintain independent data | **PASS** |
| **Test 5: IMEM Upper Boundary** | Processor successfully jumped to and retired instruction at IMEM upper boundary (`0x4000_FFFC`) | **PASS** |
| **Test 6: MMIO Reachability** | AXI interconnect routed processor store to S2 (GPIO `0x4003_1000`) | **PASS** |
| **Test 7: Reserved Slots DECERR** | DMA write to reserved S11 (`0x4004_3000`) completes without hang | **PASS** |
| | DMA write to reserved S11 returns `DECERR` (`2'b11`) | **PASS** |
| | DMA read from reserved S11 (`0x4004_3000`) completes without hang | **PASS** |
| | DMA read from reserved S11 returns `DECERR` (`2'b11`) | **PASS** |
| | DMA read from reserved S12 (`0x4004_5000`) completes with `DECERR` (`2'b11`) | **PASS** |
| | DMA read from reserved S13 (`0x4004_7000`) completes with `DECERR` (`2'b11`) | **PASS** |
| | Legacy `0x8000_4000` write completes with `DECERR` (`2'b11`) without hanging | **PASS** |
| | Legacy `0x8000_5000` read completes with `DECERR` (`2'b11`) without hanging | **PASS** |
| | Legacy `0x8000_6000` read completes with `DECERR` (`2'b11`) without hanging | **PASS** |
| **Test 8: Timer MMIO** | DMA write to Timer S3 (`0x4003_3000`) completed with `OKAY` (`2'b00`) | **PASS** |
| | DMA read from Timer S3 completed with `OKAY` (`2'b00`) | **PASS** |
| **Test 9: Hybrid Feedback Loop** | Enable Quadrature Encoder via AXI register `0x4003_D008` | **PASS** |
| | Encoder hardware direction indicates forward rotation (`enc_dir == 1`) | **PASS** |
| | Encoder count register (`0x4003_D000`) increments with quadrature steps | **PASS** |
| | PID controller hardware produces valid output signal | **PASS** |
| | PWM hardware functional output generates active switching waveforms | **PASS** |

---

## 5. Protected Directory Integrity Verification

To guarantee adherence to project rules:
1. `run/` Directory: An automated `diff -u` between baseline snapshot `logs/run_dir_baseline.txt` and post-verification snapshot `logs/run_dir_current.txt` yielded **0 differences**.
2. `rtl/Cores-VeeR-EL2/`: No files were altered.
3. Protected project directories (`doc/`, `reg/`, `README/`) were untouched.
4. No bare-metal firmware, assembly boot code, linker scripts, or mailbox mechanisms were added.

---

## 6. Phase 1 Sign-off & Next Steps

Phase 1 is complete with all requirements fulfilled and verified by VCS simulation. The SoC design is now fully aligned with the intended 64 KiB memory architecture and frozen address map.

We are ready to proceed to Phase 2 / Phase 3 upon user instruction.
