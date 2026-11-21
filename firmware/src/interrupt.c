#include "interrupt.h"
#include "timer.h"

volatile uint32_t g_timer_irq_count = 0U;
volatile uint32_t g_last_mcause = 0U;
volatile uint32_t g_last_mepc = 0U;
volatile uint32_t g_trap_count = 0U;

void pic_init(void) {
    /* Set priority order to standard RISC-V */
    PIC_MPICCFG = 0U;

    /* Set interrupt threshold to 0 (allow all priorities > 0) */
    PIC_MEIPL(0) = 0U;

    /* Disable all PIC sources initially */
    for (uint32_t i = 1U; i <= 5U; i++) {
        PIC_MEIE(i) = 0U;
        PIC_MEIGWCLR(i) = 0U;
    }
}

void pic_enable_source(uint32_t src, uint32_t priority, uint8_t edge_triggered) {
    if (src >= 1U && src <= 31U) {
        /* Gateway config: bit 0 = type (0=level, 1=edge), bit 1 = polarity (0=active-high) */
        PIC_MEIGWCTRL(src) = (edge_triggered ? 1U : 0U);
        PIC_MEIGWCLR(src)  = 0U;
        PIC_MEIPL(src)     = priority;
        PIC_MEIE(src)      = 1U;
    }
}

void pic_disable_source(uint32_t src) {
    if (src >= 1U && src <= 31U) {
        PIC_MEIE(src) = 0U;
    }
}

void pic_clear_gateway(uint32_t src) {
    if (src >= 1U && src <= 31U) {
        PIC_MEIGWCLR(src) = 0U;
    }
}

void interrupt_init(void) {
    pic_init();
    g_timer_irq_count = 0U;
    g_last_mcause = 0U;
    g_trap_count = 0U;
}

void interrupt_global_enable(void) {
    set_csr(mstatus, MSTATUS_MIE);
}

void interrupt_global_disable(void) {
    clear_csr(mstatus, MSTATUS_MIE);
}

void interrupt_external_enable(void) {
    set_csr(mie, MIE_MEIE);
}

void interrupt_external_disable(void) {
    clear_csr(mie, MIE_MEIE);
}

/* C-level Trap Dispatcher invoked from assembly trap_entry */
void handle_trap(uint32_t mcause, uint32_t mepc) {
    g_last_mcause = mcause;
    g_last_mepc   = mepc;
    g_trap_count++;

    if (mcause == MCAUSE_EXT_INT) {
        /* Check if Timer asserted interrupt */
        if (TIMER_REG_INT_STS & TIMER_INT_EXPIRE) {
            /* Disable Timer peripheral interrupt at source to stop continuous re-triggering */
            TIMER_REG_INT_EN &= ~TIMER_INT_EXPIRE;

            /* Clear Timer peripheral interrupt (W1C) */
            TIMER_REG_INT_STS = TIMER_INT_EXPIRE;

            /* Disable PIC source and clear PIC gateway for Timer source 3 */
            PIC_MEIE(PIC_SRC_TIMER)     = 0U;
            PIC_MEIGWCLR(PIC_SRC_TIMER) = 0U;

            /* Increment handled count */
            g_timer_irq_count++;
        }
    }
}
