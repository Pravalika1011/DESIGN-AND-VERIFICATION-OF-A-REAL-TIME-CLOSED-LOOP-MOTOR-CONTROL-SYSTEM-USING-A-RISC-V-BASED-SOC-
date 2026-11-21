#ifndef UART_H
#define UART_H

#include "soc_regs.h"

/* Line Status Register (LSR) Flags */
#define UART_LSR_DATA_READY     (1U << 0)
#define UART_LSR_THRE           (1U << 5) /* TX FIFO Empty */
#define UART_LSR_TEMT           (1U << 6) /* Transmitter Empty */

/* Line Control Register (LCR) Flags */
#define UART_LCR_WLEN8          (3U << 0) /* 8-bit word length */
#define UART_LCR_STOP1          (0U << 2) /* 1 stop bit */
#define UART_LCR_PARITY_NONE    (0U << 3) /* No parity */
#define UART_LCR_DLAB           (1U << 7) /* Divisor Latch Access Bit */

void uart_init(uint32_t baud_divisor);
void uart_putc(char c);
void uart_puts(const char *str);
void uart_put_hex(uint32_t val);
void uart_put_dec(uint32_t val);
char uart_getc_nonblocking(uint8_t *valid);

#endif /* UART_H */
