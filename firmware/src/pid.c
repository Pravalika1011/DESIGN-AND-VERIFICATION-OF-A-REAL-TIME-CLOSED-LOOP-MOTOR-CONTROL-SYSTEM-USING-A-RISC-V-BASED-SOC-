#include "pid.h"

void pid_init(int16_t setpoint, uint32_t kp, uint32_t ki, uint32_t kd) {
    /* Disable PID while configuring */
    PID_REG_CTRL = 0U;

    /* Set parameters */
    PID_REG_SETPOINT = (uint32_t)(uint16_t)setpoint;
    PID_REG_KP       = kp;
    PID_REG_KI       = ki;
    PID_REG_KD       = kd;

    /* Default saturation limits (8-bit PWM clamp: 0 to 255) */
    PID_REG_OUT_MAX  = 255U;
    PID_REG_OUT_MIN  = 0U;
    PID_REG_INT_MAX  = 0x00FF0000U; /* Q16.16 */
    PID_REG_INT_MIN  = 0x00000000U;

    /* Clear status flags */
    PID_REG_STATUS   = 0xFFFFFFFFU;

    /* Enable with anti-windup */
    PID_REG_CTRL     = PID_CTRL_ENABLE | PID_CTRL_AW_EN;
}

void pid_set_limits(int16_t out_max, int16_t out_min, int32_t int_max, int32_t int_min) {
    PID_REG_OUT_MAX = (uint32_t)(uint16_t)out_max;
    PID_REG_OUT_MIN = (uint32_t)(uint16_t)out_min;
    PID_REG_INT_MAX = (uint32_t)int_max;
    PID_REG_INT_MIN = (uint32_t)int_min;
}

void pid_set_setpoint(int16_t setpoint) {
    PID_REG_SETPOINT = (uint32_t)(uint16_t)setpoint;
}

int16_t pid_get_setpoint(void) {
    return (int16_t)(PID_REG_SETPOINT & 0xFFFFU);
}

void pid_enable(uint8_t enable_irq) {
    uint32_t ctrl = PID_CTRL_ENABLE | PID_CTRL_AW_EN;
    if (enable_irq) {
        ctrl |= PID_CTRL_IRQ_EN;
    }
    PID_REG_CTRL = ctrl;
}

void pid_disable(void) {
    PID_REG_CTRL &= ~PID_CTRL_ENABLE;
}

void pid_reset_integrator(void) {
    PID_REG_CTRL |= PID_CTRL_INT_RESET;
}

int16_t pid_get_output(void) {
    return (int16_t)(PID_REG_OUTPUT & 0xFFFFU);
}

int16_t pid_get_error(void) {
    return (int16_t)(PID_REG_ERROR & 0xFFFFU);
}

int16_t pid_get_actual(void) {
    return (int16_t)(PID_REG_ACTUAL & 0xFFFFU);
}

uint32_t pid_get_status(void) {
    return PID_REG_STATUS;
}

void pid_clear_status(uint32_t mask) {
    PID_REG_STATUS = mask; /* W1C */
}

uint32_t pid_get_version(void) {
    return PID_REG_VERSION;
}
