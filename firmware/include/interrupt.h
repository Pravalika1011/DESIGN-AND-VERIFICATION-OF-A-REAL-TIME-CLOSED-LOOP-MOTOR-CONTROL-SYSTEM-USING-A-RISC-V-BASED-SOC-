#ifndef INTERRUPT_H
#define INTERRUPT_H

#include "soc_regs.h"

/* Standard RISC-V Machine-Mode CSRs */
#define CSR_MSTATUS         0x300
#define CSR_MIE             0x304
#define CSR_MTVEC           0x305
#define CSR_MEPC            0x341
#define CSR_MCAUSE          0x342

/* MSTATUS Bit Masks */
#define MSTATUS_MIE         (1U << 3)

/* MIE Bit Masks */
#define MIE_MEIE            (1U << 11) /* Machine External Interrupt Enable */
#define MIE_MTIE            (1U << 7)  /* Machine Timer Interrupt Enable */
#define MIE_MSIE            (1U << 3)  /* Machine Software Interrupt Enable */

/* MCAUSE Masks */
#define MCAUSE_INT_BIT      (1U << 31)
#define MCAUSE_EXT_INT      (MCAUSE_INT_BIT | 11U)

/* CSR Access Macros */
#define read_csr(reg) ({ \
    uint32_t __v; \
    __asm__ volatile ("csrr %0, " #reg : "=r" (__v) :: "memory"); \
    __v; \
})

#define write_csr(reg, val) ({ \
    __asm__ volatile ("csrw " #reg ", %0" :: "rK" (val) : "memory"); \
})

#define set_csr(reg, bit) ({ \
    __asm__ volatile ("csrs " #reg ", %0" :: "rK" (bit) : "memory"); \
})

#define clear_csr(reg, bit) ({ \
    __asm__ volatile ("csrc " #reg ", %0" :: "rK" (bit) : "memory"); \
})

/* PIC and Interrupt Management Functions */
void pic_init(void);
void pic_enable_source(uint32_t src, uint32_t priority, uint8_t edge_triggered);
void pic_disable_source(uint32_t src);
void pic_clear_gateway(uint32_t src);

void interrupt_init(void);
void interrupt_global_enable(void);
void interrupt_global_disable(void);
void interrupt_external_enable(void);
void interrupt_external_disable(void);

/* Trap / ISR Tracking Variables */
extern volatile uint32_t g_timer_irq_count;
extern volatile uint32_t g_last_mcause;
extern volatile uint32_t g_trap_count;

#endif /* INTERRUPT_H */
