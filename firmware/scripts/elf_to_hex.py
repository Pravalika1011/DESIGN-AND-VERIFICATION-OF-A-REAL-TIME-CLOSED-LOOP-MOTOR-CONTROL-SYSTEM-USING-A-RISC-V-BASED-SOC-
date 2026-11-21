#!/usr/bin/env python3
"""
elf_to_hex.py
Converts a RISC-V ELF32 executable into a 32-bit word HEX file compatible
with Verilog $readmemh for the 64 KiB IMEM array (16,384 words).
"""

import sys
import os
import struct

IMEM_BASE = 0x40000000
IMEM_SIZE = 64 * 1024       # 64 KiB
IMEM_WORDS = IMEM_SIZE // 4 # 16,384 words

DMEM_BASE = 0x40020000
DMEM_SIZE = 64 * 1024       # 64 KiB

PERIPH_BASE = 0x40031000

def convert_elf(elf_path, hex_path, bin_path=None):
    if not os.path.exists(elf_path):
        print(f"ERROR: ELF file not found: {elf_path}", file=sys.stderr)
        sys.exit(1)

    with open(elf_path, "rb") as f:
        elf = f.read()

    # Parse ELF Header (52 bytes)
    hdr_fmt = "<16sHHIIIIIHHHHHH"
    if len(elf) < 52:
        print("ERROR: File too small to be an ELF executable", file=sys.stderr)
        sys.exit(1)

    magic, e_type, e_machine, e_version, e_entry, e_phoff, e_shoff, e_flags, \
    e_ehsize, e_phentsize, e_phnum, e_shentsize, e_shnum, e_shstrndx = struct.unpack_from(hdr_fmt, elf, 0)

    if magic[:4] != b"\x7fELF":
        print("ERROR: Magic bytes mismatch (not ELF)", file=sys.stderr)
        sys.exit(1)

    if magic[4] != 1: # ELFCLASS32
        print("ERROR: Not an ELF32 file", file=sys.stderr)
        sys.exit(1)

    if magic[5] != 1: # ELFDATA2LSB (Little Endian)
        print("ERROR: Not Little-Endian ELF", file=sys.stderr)
        sys.exit(1)

    if e_machine != 0xF3: # EM_RISCV (243)
        print(f"ERROR: Machine architecture is not RISC-V (e_machine = 0x{e_machine:x})", file=sys.stderr)
        sys.exit(1)

    print(f"=== ELF Validation ===")
    print(f"File:         {elf_path}")
    print(f"Architecture: RISC-V 32-bit (EM_RISCV, Little-Endian)")
    print(f"Entry Point:  0x{e_entry:08X}")

    if e_entry != IMEM_BASE:
        print(f"WARNING: Entry point 0x{e_entry:08X} does not match IMEM base 0x{IMEM_BASE:08X}!", file=sys.stderr)

    # Initialize IMEM buffer filled with RISC-V NOP (32'h0000_0013: addi x0, x0, 0)
    # Little-endian encoding of 0x00000013: 13 00 00 00
    imem_bytes = bytearray(b"\x13\x00\x00\x00" * IMEM_WORDS)
    highest_imem_byte = 0

    # Parse Program Headers
    for i in range(e_phnum):
        ph_offset = e_phoff + i * e_phentsize
        p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags, p_align = struct.unpack_from("<IIIIIIII", elf, ph_offset)

        if p_type == 1: # PT_LOAD
            lma = p_paddr # Physical load address
            print(f"Segment {i}: VMA=0x{p_vaddr:08X}, LMA=0x{p_paddr:08X}, FileSize={p_filesz}B, MemSize={p_memsz}B")

            # Check if this segment belongs in IMEM
            if IMEM_BASE <= lma < (IMEM_BASE + IMEM_SIZE):
                if (lma + p_filesz) > (IMEM_BASE + IMEM_SIZE):
                    print(f"ERROR: Segment {i} exceeds IMEM boundary! (LMA=0x{lma:08X}, Size={p_filesz})", file=sys.stderr)
                    sys.exit(1)

                offset = lma - IMEM_BASE
                data = elf[p_offset : p_offset + p_filesz]
                imem_bytes[offset : offset + p_filesz] = data
                if (offset + p_filesz) > highest_imem_byte:
                    highest_imem_byte = offset + p_filesz
                print(f"  -> Mapped to IMEM: 0x{lma:08X} - 0x{lma+p_filesz:08X} (offset 0x{offset:04X})")

            elif DMEM_BASE <= lma < (DMEM_BASE + DMEM_SIZE):
                print(f"  -> Target is DMEM: 0x{lma:08X} - 0x{lma+p_filesz:08X} (loaded at runtime)")

            elif lma >= PERIPH_BASE:
                print(f"ERROR: Segment {i} targets Peripheral MMIO space (0x{lma:08X})! Overlap violation!", file=sys.stderr)
                sys.exit(1)

    # Convert to 16,384 32-bit hexadecimal words
    with open(hex_path, "w") as f_hex:
        for w_idx in range(IMEM_WORDS):
            w = int.from_bytes(imem_bytes[w_idx*4 : (w_idx+1)*4], byteorder="little")
            f_hex.write(f"{w:08x}\n")

    used_words = (highest_imem_byte + 3) // 4
    print(f"=== IMEM HEX Generation ===")
    print(f"Output File:   {hex_path}")
    print(f"Array Size:    {IMEM_WORDS} lines (64 KiB total)")
    print(f"Program Size:  {highest_imem_byte} bytes ({used_words} words)")
    print(f"Capacity Used: {highest_imem_byte / IMEM_SIZE * 100.0:.2f}%")

    if bin_path:
        with open(bin_path, "wb") as f_bin:
            f_bin.write(imem_bytes[:highest_imem_byte])
        print(f"Raw Binary:    {bin_path}")

    print("SUCCESS: Memory image generation complete.\n")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: elf_to_hex.py <input.elf> <output.hex> [output.bin]")
        sys.exit(1)

    elf_file = sys.argv[1]
    hex_file = sys.argv[2]
    bin_file = sys.argv[3] if len(sys.argv) > 3 else None

    convert_elf(elf_file, hex_file, bin_file)
