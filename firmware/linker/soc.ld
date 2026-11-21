/* ============================================================================
 * Linker Script: soc.ld
 * Target SoC: VeeR EL2 RISC-V SoC (Honours CBP)
 * Memory Configuration:
 *   IMEM: 0x4000_0000 - 0x4000_FFFF (64 KiB)
 *   DMEM: 0x4002_0000 - 0x4002_FFFF (64 KiB)
 * ============================================================================ */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    IMEM (rx)  : ORIGIN = 0x40000000, LENGTH = 64K
    DMEM (rwx) : ORIGIN = 0x40020000, LENGTH = 64K
}

SECTIONS
{
    /* ------------------------------------------------------------
     * Program Code & Read-Only Data in IMEM
     * ------------------------------------------------------------ */
    .text : {
        . = ALIGN(4);
        *(.text.init)           /* Reset entry _start must be at 0x4000_0000 */
        *(.text .text.*)
        . = ALIGN(4);
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
        . = ALIGN(4);
        _etext = .;
    } > IMEM

    /* LMA address of initialized data section in IMEM */
    _sidata = LOADADDR(.data);

    /* ------------------------------------------------------------
     * Dedicated Mailbox & Status Region at Base of DMEM (16 Bytes)
     * Word 0 (0x4002_0000): Magic Signature
     * Word 1 (0x4002_0004): Verification Status Bitmask
     * Word 2 (0x4002_0008): Computed Math Result
     * Word 3 (0x4002_000C): Reserved / Heartbeat
     * ------------------------------------------------------------ */
    .mailbox (NOLOAD) : {
        . = ALIGN(4);
        _smailbox = .;
        . = . + 16;
        _emailbox = .;
    } > DMEM

    /* ------------------------------------------------------------
     * Initialized Data Section in DMEM (Loaded from IMEM)
     * ------------------------------------------------------------ */
    .data : AT(_etext) {
        . = ALIGN(4);
        _sdata = .;
        *(.data .data.*)
        *(.sdata .sdata.*)
        . = ALIGN(4);
        _edata = .;
    } > DMEM

    /* ------------------------------------------------------------
     * Zero-Initialized Data (BSS) in DMEM
     * ------------------------------------------------------------ */
    .bss (NOLOAD) : {
        . = ALIGN(4);
        _sbss = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > DMEM

    /* ------------------------------------------------------------
     * Heap and Stack in DMEM
     * Stack starts at top of DMEM (0x4003_0000) and grows downward
     * ------------------------------------------------------------ */
    .heap (NOLOAD) : {
        . = ALIGN(4);
        _sheap = .;
        . = . + 4K;             /* Minimum 4 KiB heap reservation */
        . = ALIGN(4);
        _eheap = .;
    } > DMEM

    _stack_top = ORIGIN(DMEM) + LENGTH(DMEM); /* 0x4003_0000 */

    /* Assert that code + LMA data fits within IMEM */
    ASSERT((_etext + SIZEOF(.data)) <= (ORIGIN(IMEM) + LENGTH(IMEM)), "ERROR: IMEM Overflow!")

    /* Assert that data + bss + heap fits within DMEM */
    ASSERT(_eheap <= _stack_top, "ERROR: DMEM Overflow!")

    /* Assert that sections do not enter peripheral region (>= 0x4003_1000) */
    ASSERT(_stack_top <= 0x40031000, "ERROR: Stack encroaches on Peripheral MMIO space!")
}
