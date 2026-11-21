#include "timer.h"

void timer_init(uint32_t load_val, uint16_t prescaler, uint8_t periodic, uint8_t up_count) {
    /* Stop timer first */
    TIMER_REG_CTRL = 0U;

    /* Set load and prescaler */
    TIMER_REG_LOAD = load_val;
    TIMER_REG_PRE  = (uint32_t)prescaler;

    uint32_t ctrl = 0U;
    if (periodic) {
        ctrl |= TIMER_CTRL_PERIODIC;
    }
    if (prescaler > 0U) {
        ctrl |= TIMER_CTRL_PRE_EN;
    }
    if (up_count) {
        ctrl |= TIMER_CTRL_DIR_UP;
    }

    TIMER_REG_CTRL = ctrl;
}

void timer_start(void) {
    TIMER_REG_CTRL |= TIMER_CTRL_EN;
}

void timer_stop(void) {
    TIMER_REG_CTRL &= ~TIMER_CTRL_EN;
}

uint32_t timer_get_value(void) {
    return TIMER_REG_VAL;
}

void timer_set_load(uint32_t load_val) {
    TIMER_REG_LOAD = load_val;
}

void timer_set_compare(uint32_t cmp_val) {
    TIMER_REG_CMP = cmp_val;
}

void timer_interrupt_enable(uint32_t int_mask) {
    TIMER_REG_INT_EN |= int_mask;
}

void timer_interrupt_disable(uint32_t int_mask) {
    TIMER_REG_INT_EN &= ~int_mask;
}

void timer_interrupt_clear(uint32_t int_mask) {
    TIMER_REG_INT_STS = int_mask; /* W1C */
}

uint32_t timer_interrupt_status(void) {
    return TIMER_REG_INT_STS;
}
