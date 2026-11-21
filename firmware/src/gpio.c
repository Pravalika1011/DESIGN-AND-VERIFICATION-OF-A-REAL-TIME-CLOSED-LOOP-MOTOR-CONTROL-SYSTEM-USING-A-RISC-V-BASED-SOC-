#include "gpio.h"

void gpio_init(uint32_t dir_mask) {
    GPIO_REG_DIR = dir_mask;
    GPIO_REG_DATA_O = 0x00000000U;
}

void gpio_set_direction(uint32_t mask, uint32_t dir) {
    if (dir == GPIO_DIR_OUT) {
        GPIO_REG_DIR |= mask;
    } else {
        GPIO_REG_DIR &= ~mask;
    }
}

void gpio_write(uint32_t value) {
    GPIO_REG_DATA_O = value;
}

uint32_t gpio_read(void) {
    return GPIO_REG_DATA_I;
}

void gpio_set_pin(uint8_t pin) {
    if (pin < 32U) {
        GPIO_REG_SET_O = (1U << pin);
    }
}

void gpio_clear_pin(uint8_t pin) {
    if (pin < 32U) {
        GPIO_REG_CLR_O = (1U << pin);
    }
}

void gpio_toggle_pin(uint8_t pin) {
    if (pin < 32U) {
        GPIO_REG_TGL_O = (1U << pin);
    }
}

void gpio_interrupt_config(uint32_t pin_mask, uint32_t type, uint32_t pol, uint32_t any_edge) {
    GPIO_REG_INT_TYP = type;
    GPIO_REG_INT_POL = pol;
    GPIO_REG_INT_ANY = any_edge;
    GPIO_REG_INT_EN  |= pin_mask;
}

void gpio_interrupt_clear(uint32_t mask) {
    GPIO_REG_INT_STS = mask; /* W1C */
}

uint32_t gpio_interrupt_status(void) {
    return GPIO_REG_INT_STS;
}
