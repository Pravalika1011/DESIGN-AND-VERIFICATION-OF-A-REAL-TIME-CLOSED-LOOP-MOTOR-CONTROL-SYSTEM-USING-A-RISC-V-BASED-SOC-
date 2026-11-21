#ifndef PWM_H
#define PWM_H

#include "soc_regs.h"

void pwm_set_duty(uint8_t duty);
uint8_t pwm_get_duty(void);
void pwm_write_scratch(uint8_t reg_idx, uint32_t val);
uint32_t pwm_read_scratch(uint8_t reg_idx);

#endif /* PWM_H */
