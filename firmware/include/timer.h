#ifndef TIMER_H
#define TIMER_H

#include "soc_regs.h"

/* Timer Control Bit Definitions */
#define TIMER_CTRL_EN           (1U << 0)
#define TIMER_CTRL_PERIODIC     (1U << 1)
#define TIMER_CTRL_PRE_EN       (1U << 2)
#define TIMER_CTRL_DIR_UP       (1U << 3)
#define TIMER_CTRL_PWM_EN       (1U << 4)
#define TIMER_CTRL_EXT_EN       (1U << 5)
#define TIMER_CTRL_CAP_EN       (1U << 6)

/* Timer Interrupt Flags */
#define TIMER_INT_EXPIRE        (1U << 0)
#define TIMER_INT_CAPTURE       (1U << 1)

void timer_init(uint32_t load_val, uint16_t prescaler, uint8_t periodic, uint8_t up_count);
void timer_start(void);
void timer_stop(void);
uint32_t timer_get_value(void);
void timer_set_load(uint32_t load_val);
void timer_set_compare(uint32_t cmp_val);
void timer_interrupt_enable(uint32_t int_mask);
void timer_interrupt_disable(uint32_t int_mask);
void timer_interrupt_clear(uint32_t int_mask);
uint32_t timer_interrupt_status(void);

#endif /* TIMER_H */
