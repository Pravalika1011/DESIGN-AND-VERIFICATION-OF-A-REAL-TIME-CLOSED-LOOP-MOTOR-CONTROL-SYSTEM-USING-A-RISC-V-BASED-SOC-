#ifndef GPIO_H
#define GPIO_H

#include "soc_regs.h"

/* GPIO Direction: 1 = Output, 0 = Input */
#define GPIO_DIR_IN         0U
#define GPIO_DIR_OUT        1U

void gpio_init(uint32_t dir_mask);
void gpio_set_direction(uint32_t mask, uint32_t dir);
void gpio_write(uint32_t value);
uint32_t gpio_read(void);
void gpio_set_pin(uint8_t pin);
void gpio_clear_pin(uint8_t pin);
void gpio_toggle_pin(uint8_t pin);
void gpio_interrupt_config(uint32_t pin_mask, uint32_t type, uint32_t pol, uint32_t any_edge);
void gpio_interrupt_clear(uint32_t mask);
uint32_t gpio_interrupt_status(void);

#endif /* GPIO_H */
