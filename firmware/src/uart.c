#include "uart.h"

void uart_init(uint32_t baud_divisor) {
    /* Set DLAB = 1 to program baud divisor */
    UART_REG_LCR = UART_LCR_DLAB;
    UART_REG_BAUD_DIV = baud_divisor;

    /* Set DLAB = 0 and configure 8N1 (8 data bits, 1 stop bit, no parity) */
    UART_REG_LCR = UART_LCR_WLEN8 | UART_LCR_STOP1 | UART_LCR_PARITY_NONE;
}

void uart_putc(char c) {
    /* Write character directly to UART TX FIFO */
    UART_REG_THR = (uint32_t)(uint8_t)c;
}

void uart_puts(const char *str) {
    if (!str) return;
    while (*str) {
        if (*str == '\n') {
            uart_putc('\r');
        }
        uart_putc(*str++);
    }
}

void uart_put_hex(uint32_t val) {
    static const char hex_digits[] = "0123456789ABCDEF";
    uart_puts("0x");
    for (int i = 28; i >= 0; i -= 4) {
        uart_putc(hex_digits[(val >> i) & 0xFU]);
    }
}

void uart_put_dec(uint32_t val) {
    char buf[12];
    int i = 0;
    if (val == 0U) {
        uart_putc('0');
        return;
    }
    while (val > 0U) {
        buf[i++] = (char)('0' + (val % 10U));
        val /= 10U;
    }
    while (--i >= 0) {
        uart_putc(buf[i]);
    }
}

char uart_getc_nonblocking(uint8_t *valid) {
    if (UART_REG_LSR & UART_LSR_DATA_READY) {
        if (valid) *valid = 1U;
        return (char)(UART_REG_RBR & 0xFFU);
    }
    if (valid) *valid = 0U;
    return '\0';
}
