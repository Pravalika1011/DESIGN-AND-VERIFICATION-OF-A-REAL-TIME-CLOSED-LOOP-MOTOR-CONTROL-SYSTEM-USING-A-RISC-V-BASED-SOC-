/* ============================================================================
 * File: crt0.S
 * Description: Bare-metal C runtime startup and trap vector for VeeR EL2 SoC.
 * Memory Map:
 *   IMEM: 0x4000_0000 - 0x4000_FFFF (64 KiB)
 *   DMEM: 0x4002_0000 - 0x4002_FFFF (64 KiB)
 * ============================================================================ */

    .section .text.init, "ax"
    .global _start
    .type _start, @function

_start:
    /* ------------------------------------------------------------
     * 1. Initialize Stack Pointer (sp) to top of DMEM (0x40030000)
     * ------------------------------------------------------------ */
    la   sp, _stack_top

    /* ------------------------------------------------------------
     * 2. Configure Machine Trap Vector (mtvec) in Direct Mode
     * ------------------------------------------------------------ */
    la   t0, trap_entry
    csrw mtvec, t0

    /* ------------------------------------------------------------
     * 3. Copy .data Section from IMEM (LMA) to DMEM (VMA)
     * ------------------------------------------------------------ */
    la   a0, _sdata
    la   a1, _edata
    la   a2, _sidata

copy_data_loop:
    bgeu a0, a1, copy_data_done
    lw   t0, 0(a2)
    sw   t0, 0(a0)
    addi a0, a0, 4
    addi a2, a2, 4
    j    copy_data_loop

copy_data_done:

    /* ------------------------------------------------------------
     * 4. Zero-Initialize .bss Section in DMEM
     * ------------------------------------------------------------ */
    la   a0, _sbss
    la   a1, _ebss

zero_bss_loop:
    bgeu a0, a1, zero_bss_done
    sw   zero, 0(a0)
    addi a0, a0, 4
    j    zero_bss_loop

zero_bss_done:

    /* ------------------------------------------------------------
     * 5. Transfer Execution to main()
     * ------------------------------------------------------------ */
    call main

    /* ------------------------------------------------------------
     * 6. Safe Post-Execution Halt Loop
     * Store return code in a0 to Mailbox exit code word at 0x4002000C
     * ------------------------------------------------------------ */
    lui  t1, 0x40020
    sw   a0, 12(t1)

halt_loop:
    wfi
    j    halt_loop

    .size _start, . - _start

/* ============================================================================
 * Trap / Interrupt Entry Point
 * Saves caller-saved registers, mepc, and mstatus, calls C dispatcher,
 * and restores context before returning via mret.
 * Stack frame: 80 bytes (16-byte aligned per RISC-V ABI)
 * ============================================================================ */
    .section .text, "ax"
    .align 4
    .global trap_entry
    .type trap_entry, @function

trap_entry:
    addi sp, sp, -80
    sw   ra,   0(sp)
    sw   t0,   4(sp)
    sw   t1,   8(sp)
    sw   t2,  12(sp)
    sw   a0,  16(sp)
    sw   a1,  20(sp)
    sw   a2,  24(sp)
    sw   a3,  28(sp)
    sw   a4,  32(sp)
    sw   a5,  36(sp)
    sw   a6,  40(sp)
    sw   a7,  44(sp)
    sw   t3,  48(sp)
    sw   t4,  52(sp)
    sw   t5,  56(sp)
    sw   t6,  60(sp)
    csrr t0,  mepc
    sw   t0,  64(sp)
    csrr t1,  mstatus
    sw   t1,  68(sp)

    csrr a0,  mcause
    mv   a1,  t0
    call handle_trap

    lw   t1,  68(sp)
    csrw mstatus, t1
    lw   t0,  64(sp)
    csrw mepc,    t0

    lw   ra,   0(sp)
    lw   t0,   4(sp)
    lw   t1,   8(sp)
    lw   t2,  12(sp)
    lw   a0,  16(sp)
    lw   a1,  20(sp)
    lw   a2,  24(sp)
    lw   a3,  28(sp)
    lw   a4,  32(sp)
    lw   a5,  36(sp)
    lw   a6,  40(sp)
    lw   a7,  44(sp)
    lw   t3,  48(sp)
    lw   t4,  52(sp)
    lw   t5,  56(sp)
    lw   t6,  60(sp)
    addi sp, sp, 80

    mret

    .size trap_entry, . - trap_entry
