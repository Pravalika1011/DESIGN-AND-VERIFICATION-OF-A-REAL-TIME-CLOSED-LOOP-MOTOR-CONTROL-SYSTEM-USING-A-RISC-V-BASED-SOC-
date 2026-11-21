#include "encoder.h"

void encoder_init(uint32_t mode_flags, uint32_t window, uint32_t scale) {
    /* Disable encoder first */
    ENC_REG_CTRL = 0U;

    /* Configure measurement parameters */
    ENC_REG_WINDOW    = window;
    ENC_REG_SCALE     = scale;
    ENC_REG_FILTER    = 4U;       /* 4-clock glitch filter */
    ENC_REG_STALL_TMO = 100000U;  /* Stall timeout */

    /* Clear any pending status */
    ENC_REG_STATUS = 0xFFFFFFFFU;

    /* Apply configuration with enable */
    ENC_REG_CTRL = mode_flags | ENC_CTRL_ENABLE;
}

void encoder_enable(void) {
    ENC_REG_CTRL |= ENC_CTRL_ENABLE;
}

void encoder_disable(void) {
    ENC_REG_CTRL &= ~ENC_CTRL_ENABLE;
}

void encoder_reset_count(void) {
    ENC_REG_CTRL |= ENC_CTRL_COUNT_RESET;
}

int32_t encoder_get_count(void) {
    return (int32_t)ENC_REG_COUNT;
}

int16_t encoder_get_speed(void) {
    return (int16_t)(ENC_REG_SPEED & 0xFFFFU);
}

uint32_t encoder_get_status(void) {
    return ENC_REG_STATUS;
}

void encoder_clear_status(uint32_t mask) {
    ENC_REG_STATUS = mask; /* W1C */
}

uint32_t encoder_get_ctrl(void) {
    return ENC_REG_CTRL;
}

uint32_t encoder_get_window(void) {
    return ENC_REG_WINDOW;
}

uint32_t encoder_get_version(void) {
    return ENC_REG_VERSION;
}
