# Phase 3 — RISC-V VeeR EL2 Processor Connection Report

## 1. Executive Summary

Phase 3 is complete. The CHIPS Alliance **VeeR EL2** RISC-V processor has been successfully connected to the SoC in `/home/student/Downloads/090_honrors/CBP`.

The integration preserves 100% backward compatibility with the existing 3-master × 15-slave AXI interconnect, all six integrated peripheral IPs (GPIO, Timer, UART, Encoder, PID, and PWM), and the complete hardware feedback loop (`Encoder -> PID -> PWM`).

All activities were executed strictly within `/home/student/Downloads/090_honrors/CBP`. No files outside this workspace were accessed or modified, and no license server details are exposed. In strict adherence to scope restrictions, **no firmware, no C test programs, no ELF/BIN/HEX files, and no `$readmemh` preloading logic have been introduced**.

---

## 2. Processor Repository & Configuration

1. **Repository**:
   - Cloned official `https://github.com/chipsalliance/Cores-VeeR-EL2.git` into `rtl/Cores-VeeR-EL2` (clean git working tree at commit `0169d669eedec31f723dde006125e22c4bf83a95`).
   - Cleanly isolated within `rtl/` without overwriting or moving any pre-existing project files.

2. **Core Configuration**:
   - Snapshot generated via `configs/veer.config`:
     ```bash
     -target=default -set=iccm_enable=0 -set=dccm_enable=0 -set=icache_enable=0 -set=reset_vec=0x00040000
     ```
   - Target snapshot generated at `rtl/Cores-VeeR-EL2/snapshots/default/` (`common_defines.vh`, `el2_param.vh`, `el2_pdef.vh`).
   - Reset vector set to `0x0004_0000` (`rst_vec = 31'h0002_0000`, matching `32'h0004_0000 >> 1`), pointing directly into the S0 IMEM aperture.
   - Core configured with native AXI4 interfaces enabled (`RV_BUILD_AXI4`).

---

## 3. SoC Architecture & Dedicated Top-Level (`soc_top.sv`)

To avoid breaking existing Phase 2 testbenches (`tb_main_top.sv` with 157 checks and `tb_hybrid_feedback.sv` with 43 checks), `rtl/main_top.v` was preserved **100% untouched**. A clean, dedicated SoC top-level module was implemented in `rtl/soc_top.sv`.

### Architecture Topology:
- **Processor**: `veer_wrapper` (instantiating `el2_veer_wrapper` and `el2_veer`).
  - Instruction Fetch Unit (IFU): 64-bit AXI4 read master (`pt.IFU_BUS_TAG = 3`).
  - Load/Store Unit (LSU): 64-bit AXI4 read/write master (`pt.LSU_BUS_TAG = 4`).
  - Programmable Interrupt Controller (PIC): `extintsrc_req[5:1]` connected to peripheral interrupts.
- **Bus Adapters**:
  - `rtl/axi_width_downconverter_ifu.sv`: Converts VeeR IFU 64-bit single-beat reads (`arsize=3, arlen=0`) into two sequential 32-bit single-beat reads (`arsize=2, arlen=0`) to interconnect Master 0 (`s00_axi_*`), assembling data into a 64-bit response for the core.
  - `rtl/axi_width_downconverter_lsu.sv`: Converts VeeR LSU 64-bit transactions to 32-bit for interconnect Master 1 (`s01_axi_*`). Supports single 32-bit accesses as well as dual sequential 32-bit accesses with byte-strobe propagation and response matching.
- **Memory Controllers**:
  - `rtl/axi_sram_ctrl.sv`: Synthesizable 32-bit single-port synchronous AXI4 memory controller for S0 IMEM (`0x0004_0000`, 4 KiB) and S1 DMEM (`0x0008_0000`, 4 KiB). Initialized to RISC-V NOP (`32'h0000_0013`) without `$readmemh`.
- **Interconnect Masters**:
  - **M0**: IFU (via `axi_width_downconverter_ifu` -> `main_top.s00_axi_*`).
  - **M1**: LSU (via `axi_width_downconverter_lsu` -> `main_top.s01_axi_*`).
  - **M2**: Preserved external DMA master interface (`s02_axi_*`), exposed at top level.
- **Interconnect Slaves**:
  - S0: IMEM (`0x0004_0000` .. `0x0004_0FFF`)
  - S1: DMEM (`0x0008_0000` .. `0x0008_0FFF`)
  - S2: GPIO (`0x4003_1000` .. `0x4003_1FFF`)
  - S3: Timer (`0x4003_3000` .. `0x4003_3FFF`)
  - S4: UART (`0x4003_5000` .. `0x4003_5FFF`)
  - S8: Encoder (`0x4003_D000` .. `0x4003_DFFF`)
  - S9: PID Controller (`0x4003_F000` .. `0x4003_FFFF`)
  - S10: PWM Controller (`0x4004_1000` .. `0x4004_1FFF`)
  - S11: WDT, S12: ADC, S13: DMA Registers (preserved)
- **Interrupt Routing**:
  - `extintsrc_req[1]` <= `uart_irq`
  - `extintsrc_req[2]` <= `gpio_intr`
  - `extintsrc_req[3]` <= `timer_intr`
  - `extintsrc_req[4]` <= `enc_intr`
  - `extintsrc_req[5]` <= `pid_intr`
- **Hardware Feedback Path**:
  - `enc_speed` -> `pid_actual`
  - `timer_trigger` -> `pid_tick`
  - `pid_out` -> `pwm_duty`

---

## 4. Verification Results

### 4.1. SoC Top Targeted Integration Suite (`tb_soc_top.sv`)
A targeted SystemVerilog testbench was executed via `run/run_soc.sh` with Synopsys VCS (`U-2023.03_Full64`).

```text
==================================================================
   PHASE 3 INTEGRATION VERIFICATION SUMMARY
   Total Checks: 15 | Passed: 15 | Failed: 0
==================================================================
>>> ALL PHASE 3 RISC-V INTEGRATION CHECKS PASSED SUCCESSFULLY <<<
```

#### Detailed Test Check Matrix:
| Test Check | Description | Status |
|---|---|---|
| **Test 1.1** | Core reset release: `rst` de-asserted | **PASS** |
| **Test 1.2** | Core halt status low (`o_cpu_halt_status == 0`, core running) | **PASS** |
| **Test 2.1** | IFU issues AXI read request on reset exit | **PASS** |
| **Test 2.2** | IFU fetch target matches reset vector (`0x0004_0000`) | **PASS** |
| **Test 2.3** | IFU 64b downconverter drives interconnect `s00_axi` | **PASS** |
| **Test 3.1** | Processor executes and retires instruction (`trace_rv_i_valid_ip`) | **PASS** |
| **Test 3.2** | Executed instruction PC is in IMEM aperture (`0x0004_0000`..) | **PASS** |
| **Test 4.1** | Processor LSU executed store to DMEM at `0x0008_0000` | **PASS** |
| **Test 4.2** | DMEM memory array contains stored value (`0x0000_005A`) | **PASS** |
| **Test 5.1** | AXI interconnect routed processor store to S2 (GPIO `0x4003_1000`) | **PASS** |
| **Test 6.1** | DMA write transaction to Timer S3 completed with OKAY response | **PASS** |
| **Test 6.2** | DMA read transaction from Timer S3 completed | **PASS** |
| **Test 7.1** | Encoder hardware outputs valid direction/speed signals | **PASS** |
| **Test 7.2** | PID controller hardware outputs valid signal | **PASS** |
| **Test 7.3** | PWM hardware functional output actively driven | **PASS** |

#### Execution Trace Log Confirmation:
```text
[TRACE T=1285000] Core retired PC: 0x00040008, Insn: 0x0020a023 (sw x2, 0(x1) -> DMEM[0x0008_0000])
[TRACE T=1755000] Core retired PC: 0x0004000c, Insn: 0x0000a183 (lw x3, 0(x1) <- DMEM[0x0008_0000])
[TRACE T=2235000] Core retired PC: 0x00040010, Insn: 0x40031237 (lui x4, 0x40031)
[TRACE T=2665000] Core retired PC: 0x00040014, Insn: 0x00222023 (sw x2, 0(x4) -> GPIO[0x4003_1000])
[BUS T=2895000]   Interconnect routed store to GPIO: addr=0x40031000, data=0x0000005a
[TRACE T=3285000] Core retired PC: 0x00040018, Insn: 0x00000013 (nop)
[TRACE T=3705000] Core retired PC: 0x0004001c, Insn: 0x00000013 (nop)
[TRACE T=4125000] Core retired PC: 0x00040020, Insn: 0x00000013 (nop)
[TRACE T=4555000] Core retired PC: 0x00040024, Insn: 0x00000013 (nop)
```

### 4.2. Phase 2 Regression Safety Suites
1. **`tb_main_top.sv` via `run/run_main.sh`**:
   - Total Checks: **157**
   - Passed: **157**
   - Failed: **0**
   - Regressions: **0**
2. **`tb_hybrid_feedback.sv` via `run/run_feedback.sh`**:
   - Total Checks: **43**
   - Passed: **43**
   - Failed: **0**
   - Regressions: **0**

---

## 5. Changed and Created Files

| File | Status | Description |
|---|---|---|
| `rtl/Cores-VeeR-EL2/` | Created (cloned) | Official VeeR EL2 repository snapshot and design files |
| `rtl/soc_top.sv` | Created | Top-level SoC integrating VeeR EL2, downconverters, SRAM controllers, and `main_top` |
| `rtl/axi_width_downconverter_ifu.sv` | Created | 64b -> 32b AXI width downconverter for Instruction Fetch Unit |
| `rtl/axi_width_downconverter_lsu.sv` | Created | 64b -> 32b AXI width downconverter for Load/Store Unit |
| `rtl/axi_sram_ctrl.sv` | Created | Synthesizable 32-bit AXI memory controller for S0 (IMEM) and S1 (DMEM) |
| `tb/tb_soc_top.sv` | Created | Targeted SystemVerilog integration testbench for SoC with VeeR EL2 |
| `run/run_soc.f` | Created | Complete VCS file list for SoC compilation and simulation |
| `run/run_soc.sh` | Created | VCS compilation and simulation script for SoC |
| `rtl/main_top.v` | **Untouched** | Preserved with zero modifications |
| `tb/tb_main_top.sv` | **Untouched** | Preserved with zero modifications |
| `tb/tb_hybrid_feedback.sv` | **Untouched** | Preserved with zero modifications |

---

## 6. Git Status & Checkpoint

- **Project Root Repository Status**: The project workspace `/home/student/Downloads/090_honrors/CBP` is **not configured as a Git repository** (no `.git` directory exists at root or in parent directories).
- **Sub-repository**: `rtl/Cores-VeeR-EL2` is an independent Git clone (`main` branch, commit `0169d669eedec31f723dde006125e22c4bf83a95`, working tree clean).
- **Checkpoint Action**: Per strict scope instructions, no new Git repository was initialized and the directory was not duplicated. All created modules, testbenches, simulation scripts, and logs are preserved in place.

---

## 7. Scope Verification & Remaining Work

### Verified with Simulation Evidence:
- Core reset release and clock propagation (`sim_soc_tb.log`).
- IFU instruction fetch over AXI interconnect to S0 IMEM (`0x0004_0000`) (`sim_soc_tb.log`).
- Core instruction retirement and execution trace (`sim_soc_tb.log`).
- LSU data store/load to S1 DMEM (`0x0008_0000`) (`sim_soc_tb.log`).
- Core MMIO store to S2 GPIO (`0x4003_1000`) via interconnect (`sim_soc_tb.log`).
- External DMA Master M2 read/write to S3 Timer (`0x4003_3000`) (`sim_soc_tb.log`).
- Autonomous hardware feedback loop (`Encoder -> PID -> PWM`) (`sim_soc_tb.log`, `sim_feedback.log`).
- Backward compatibility with Phase 2 test suites (`tb_main_top.sv` 157 checks in `sim.log`, `tb_hybrid_feedback.sv` 43 checks in `sim_feedback.log`).

### Not Run / Out of Scope for Phase 3:
- C runtime environment, startup assembly (`crt0.s`), and linker scripts (`*.ld`) were **not created**.
- C-based software tests, ELF compilation, binary generation, and HEX memory images were **not run or generated**.
- Hardware `$readmemh` memory preload was **not implemented**.
- Peripheral driver software interactions across all registers from software were **not run** (deferred to Phase 4).

### Strict Stop Condition:
Development is stopped. Ready for user review and explicit approval before starting Phase 4 (Firmware & Software Verification).
