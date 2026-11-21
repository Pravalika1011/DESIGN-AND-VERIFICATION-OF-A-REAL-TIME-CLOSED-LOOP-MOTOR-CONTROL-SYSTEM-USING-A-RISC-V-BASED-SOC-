#include "pwm.h"

void pwm_set_duty(uint8_t duty) {
    PWM_REG_DUTY = (uint32_t)duty;
}

uint8_t pwm_get_duty(void) {
    return (uint8_t)(PWM_REG_DUTY & 0xFFU);
}

void pwm_write_scratch(uint8_t reg_idx, uint32_t val) {
    switch (reg_idx) {
        case 1: PWM_REG_SCRATCH1 = val; break;
        case 2: PWM_REG_SCRATCH2 = val; break;
        case 3: PWM_REG_SCRATCH3 = val; break;
        default: break;
    }
}

uint32_t pwm_read_scratch(uint8_t reg_idx) {
    switch (reg_idx) {
        case 1: return PWM_REG_SCRATCH1;
        case 2: return PWM_REG_SCRATCH2;
        case 3: return PWM_REG_SCRATCH3;
        default: return 0U;
    }
}
