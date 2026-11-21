#ifndef SOC_REGS_H
#define SOC_REGS_H

#include <stdint.h>

/* ============================================================================
 * CBP RISC-V VeeR EL2 SoC Memory Map & Register Definitions
 * Authority: Authoritative Implemented RTL Baseline & Phase 2 Specification
 * ============================================================================ */

/* Base Addresses */
#define IMEM_BASE           0x40000000U
#define IMEM_SIZE           0x00010000U /* 64 KiB */
#define IMEM_END            (IMEM_BASE + IMEM_SIZE - 1U)

#define DMEM_BASE           0x40020000U
#define DMEM_SIZE           0x00010000U /* 64 KiB */
#define DMEM_END            (DMEM_BASE + DMEM_SIZE - 1U)
#define STACK_TOP           (DMEM_BASE + DMEM_SIZE) /* 0x40030000 */

/* Peripheral Base Addresses (4 KiB each) */
#define GPIO_BASE           0x40031000U
#define TIMER_BASE          0x40033000U
#define UART_BASE           0x40035000U
#define ENC_BASE            0x4003D000U
#define PID_BASE            0x4003F000U
#define PWM_BASE            0x40041000U

/* Macro for volatile 32-bit register access */
#define REG32(addr)         (*(volatile uint32_t *)((uintptr_t)(addr)))

/* ----------------------------------------------------------------------------
 * GPIO Registers (Base: 0x40031000)
 * ---------------------------------------------------------------------------- */
#define GPIO_REG_DATA_I     REG32(GPIO_BASE + 0x00U)
#define GPIO_REG_DATA_O     REG32(GPIO_BASE + 0x04U)
#define GPIO_REG_DIR        REG32(GPIO_BASE + 0x08U)
#define GPIO_REG_INT_EN     REG32(GPIO_BASE + 0x0CU)
#define GPIO_REG_INT_TYP    REG32(GPIO_BASE + 0x10U)
#define GPIO_REG_INT_POL    REG32(GPIO_BASE + 0x14U)
#define GPIO_REG_INT_ANY    REG32(GPIO_BASE + 0x18U)
#define GPIO_REG_INT_STS    REG32(GPIO_BASE + 0x1CU)
#define GPIO_REG_SET_O      REG32(GPIO_BASE + 0x20U)
#define GPIO_REG_CLR_O      REG32(GPIO_BASE + 0x24U)
#define GPIO_REG_TGL_O      REG32(GPIO_BASE + 0x28U)

/* ----------------------------------------------------------------------------
 * Timer Registers (Base: 0x40033000)
 * ---------------------------------------------------------------------------- */
#define TIMER_REG_CTRL      REG32(TIMER_BASE + 0x00U)
#define TIMER_REG_LOAD      REG32(TIMER_BASE + 0x04U)
#define TIMER_REG_VAL       REG32(TIMER_BASE + 0x08U)
#define TIMER_REG_PRE       REG32(TIMER_BASE + 0x0CU)
#define TIMER_REG_INT_EN    REG32(TIMER_BASE + 0x10U)
#define TIMER_REG_INT_STS   REG32(TIMER_BASE + 0x14U)
#define TIMER_REG_CMP       REG32(TIMER_BASE + 0x18U)
#define TIMER_REG_CAP       REG32(TIMER_BASE + 0x1CU)

/* ----------------------------------------------------------------------------
 * UART Registers (Base: 0x40035000)
 * ---------------------------------------------------------------------------- */
#define UART_REG_RBR        REG32(UART_BASE + 0x00U)
#define UART_REG_THR        REG32(UART_BASE + 0x00U)
#define UART_REG_IER        REG32(UART_BASE + 0x04U)
#define UART_REG_BAUD_DIV   REG32(UART_BASE + 0x08U)
#define UART_REG_LCR        REG32(UART_BASE + 0x0CU)
#define UART_REG_LSR        REG32(UART_BASE + 0x14U)

/* ----------------------------------------------------------------------------
 * Quadrature Encoder Registers (Base: 0x4003D000)
 * ---------------------------------------------------------------------------- */
#define ENC_REG_COUNT       REG32(ENC_BASE + 0x00U)
#define ENC_REG_SPEED       REG32(ENC_BASE + 0x04U)
#define ENC_REG_CTRL        REG32(ENC_BASE + 0x08U)
#define ENC_REG_STATUS      REG32(ENC_BASE + 0x0CU)
#define ENC_REG_WINDOW      REG32(ENC_BASE + 0x10U)
#define ENC_REG_FILTER      REG32(ENC_BASE + 0x14U)
#define ENC_REG_SCALE       REG32(ENC_BASE + 0x18U)
#define ENC_REG_STALL_TMO   REG32(ENC_BASE + 0x1CU)
#define ENC_REG_REV_COUNT   REG32(ENC_BASE + 0x20U)
#define ENC_REG_INDEX_POS   REG32(ENC_BASE + 0x24U)
#define ENC_REG_RAW_DELTA   REG32(ENC_BASE + 0x28U)
#define ENC_REG_IRQ_EN      REG32(ENC_BASE + 0x2CU)
#define ENC_REG_VERSION     REG32(ENC_BASE + 0x30U)

/* ----------------------------------------------------------------------------
 * PID Controller Registers (Base: 0x4003F000)
 * ---------------------------------------------------------------------------- */
#define PID_REG_SETPOINT    REG32(PID_BASE + 0x00U)
#define PID_REG_KP          REG32(PID_BASE + 0x04U)
#define PID_REG_KI          REG32(PID_BASE + 0x08U)
#define PID_REG_KD          REG32(PID_BASE + 0x0CU)
#define PID_REG_OUTPUT      REG32(PID_BASE + 0x10U)
#define PID_REG_CTRL        REG32(PID_BASE + 0x14U)
#define PID_REG_STATUS      REG32(PID_BASE + 0x18U)
#define PID_REG_ERROR       REG32(PID_BASE + 0x1CU)
#define PID_REG_ACTUAL      REG32(PID_BASE + 0x20U)
#define PID_REG_OUT_MAX     REG32(PID_BASE + 0x24U)
#define PID_REG_OUT_MIN     REG32(PID_BASE + 0x28U)
#define PID_REG_INT_MAX     REG32(PID_BASE + 0x2CU)
#define PID_REG_INT_MIN     REG32(PID_BASE + 0x30U)
#define PID_REG_VERSION     REG32(PID_BASE + 0x34U)

/* ----------------------------------------------------------------------------
 * PWM Registers (Base: 0x40041000)
 * ---------------------------------------------------------------------------- */
#define PWM_REG_DUTY        REG32(PWM_BASE + 0x00U)
#define PWM_REG_SCRATCH1    REG32(PWM_BASE + 0x04U)
#define PWM_REG_SCRATCH2    REG32(PWM_BASE + 0x08U)
#define PWM_REG_SCRATCH3    REG32(PWM_BASE + 0x0CU)

/* ----------------------------------------------------------------------------
 * VeeR EL2 Programmable Interrupt Controller (PIC) (Base: 0xF00C0000)
 * ---------------------------------------------------------------------------- */
#define PIC_BASE            0xF00C0000U
#define PIC_MEIPL(src)      REG32(PIC_BASE + 0x0000U + 4U * (src))
#define PIC_MEIP            REG32(PIC_BASE + 0x1000U)
#define PIC_MEIE(src)       REG32(PIC_BASE + 0x2000U + 4U * (src))
#define PIC_MPICCFG         REG32(PIC_BASE + 0x3000U)
#define PIC_MEIGWCTRL(src)  REG32(PIC_BASE + 0x4000U + 4U * (src))
#define PIC_MEIGWCLR(src)   REG32(PIC_BASE + 0x5000U + 4U * (src))

/* Peripheral PIC Source IDs */
#define PIC_SRC_UART        1U
#define PIC_SRC_GPIO        2U
#define PIC_SRC_TIMER       3U
#define PIC_SRC_ENCODER     4U
#define PIC_SRC_PID         5U

#endif /* SOC_REGS_H */
