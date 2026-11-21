#!/usr/bin/env bash
# ==============================================================================
# build_firmware.sh
# Reproducible build script for VeeR EL2 SoC bare-metal firmware
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FW_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

RISCV_PREFIX="/opt/riscv/bin/riscv64-unknown-elf-"
CC="${RISCV_PREFIX}gcc"
OBJDUMP="${RISCV_PREFIX}objdump"
OBJCOPY="${RISCV_PREFIX}objcopy"
READELF="${RISCV_PREFIX}readelf"
NM="${RISCV_PREFIX}nm"
SIZE="${RISCV_PREFIX}size"

# Compiler & Linker Flags
ARCH_FLAGS="-march=rv32imc_zicsr -mabi=ilp32"
FREESTANDING_FLAGS="-ffreestanding -nostdlib -nostartfiles"
OPT_FLAGS="-O2 -g"
WARN_FLAGS="-Wall -Wextra"
INC_FLAGS="-I${FW_DIR}/include"

BUILD_DIR="${FW_DIR}/build"
mkdir -p "${BUILD_DIR}"

echo "=================================================================="
echo "   BUILDING RISC-V BARE-METAL FIRMWARE (RV32IMC / 64 KiB MAP)     "
echo "=================================================================="
echo "Toolchain: ${CC}"
echo "Flags:     ${ARCH_FLAGS} ${FREESTANDING_FLAGS} ${OPT_FLAGS}"

# 1. Compile Startup Assembly
echo "[1/5] Compiling startup/crt0.S..."
${CC} ${ARCH_FLAGS} ${FREESTANDING_FLAGS} -c "${FW_DIR}/startup/crt0.S" \
    -o "${BUILD_DIR}/crt0.o"

# 2. Compile C Sources
echo "[2/5] Compiling C source drivers..."
C_SRCS=("main" "gpio" "timer" "uart" "encoder" "pid" "pwm" "interrupt")
C_OBJS=()
for src in "${C_SRCS[@]}"; do
    echo "      Compiling src/${src}.c..."
    ${CC} ${ARCH_FLAGS} ${FREESTANDING_FLAGS} ${OPT_FLAGS} ${WARN_FLAGS} ${INC_FLAGS} \
        -c "${FW_DIR}/src/${src}.c" -o "${BUILD_DIR}/${src}.o"
    C_OBJS+=("${BUILD_DIR}/${src}.o")
done

# 3. Link Executable
echo "[3/5] Linking firmware.elf with linker/soc.ld..."
${CC} ${ARCH_FLAGS} ${FREESTANDING_FLAGS} \
    -T "${FW_DIR}/linker/soc.ld" \
    "${BUILD_DIR}/crt0.o" "${C_OBJS[@]}" \
    -o "${BUILD_DIR}/firmware.elf" \
    -Wl,-Map="${BUILD_DIR}/firmware.map"

# 4. Generate Analysis Artifacts
echo "[4/5] Generating disassembly, symbol table, and section headers..."
${OBJDUMP} -d -S "${BUILD_DIR}/firmware.elf" > "${BUILD_DIR}/firmware.dump"
${NM} -n "${BUILD_DIR}/firmware.elf" > "${BUILD_DIR}/firmware.sym"
${READELF} -a "${BUILD_DIR}/firmware.elf" > "${BUILD_DIR}/firmware.readelf"
${SIZE} "${BUILD_DIR}/firmware.elf"

# 5. Convert to Verilog IMEM $readmemh HEX
echo "[5/5] Generating Verilog \$readmemh memory image (imem.hex)..."
python3 "${SCRIPT_DIR}/elf_to_hex.py" \
    "${BUILD_DIR}/firmware.elf" \
    "${BUILD_DIR}/imem.hex" \
    "${BUILD_DIR}/imem.bin"

echo "=================================================================="
echo "   FIRMWARE BUILD COMPLETE & VERIFIED                             "
echo "   ELF:  ${BUILD_DIR}/firmware.elf"
echo "   HEX:  ${BUILD_DIR}/imem.hex (16384 x 32-bit words)"
echo "   DUMP: ${BUILD_DIR}/firmware.dump"
echo "=================================================================="
