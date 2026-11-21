#ifndef ENCODER_H
#define ENCODER_H

#include "soc_regs.h"

/* Encoder Control Bit Positions */
#define ENC_CTRL_ENABLE         (1U << 0)
#define ENC_CTRL_COUNT_RESET    (1U << 1)
#define ENC_CTRL_MODE_X1        (0U << 2)
#define ENC_CTRL_MODE_X2        (1U << 2)
#define ENC_CTRL_MODE_X4        (2U << 2)
#define ENC_CTRL_AVG_1          (0U << 4)
#define ENC_CTRL_AVG_2          (1U << 4)
#define ENC_CTRL_AVG_4          (2U << 4)
#define ENC_CTRL_AVG_8          (3U << 4)
#define ENC_CTRL_SWAP_AB        (1U << 6)
#define ENC_CTRL_INDEX_CLR      (1U << 7)
#define ENC_CTRL_DRIVE_ASSERT   (1U << 8)
#define ENC_CTRL_FAULT_EN       (1U << 9)

/* Encoder Status Bit Positions */
#define ENC_STAT_VALID          (1U << 0)
#define ENC_STAT_DIR            (1U << 1)
#define ENC_STAT_OVERFLOW       (1U << 2)
#define ENC_STAT_ILLEGAL        (1U << 3)
#define ENC_STAT_STALL          (1U << 4)
#define ENC_STAT_FAULT          (1U << 5)

void encoder_init(uint32_t mode_flags, uint32_t window, uint32_t scale);
void encoder_enable(void);
void encoder_disable(void);
void encoder_reset_count(void);
int32_t encoder_get_count(void);
int16_t encoder_get_speed(void);
uint32_t encoder_get_status(void);
void encoder_clear_status(uint32_t mask);
uint32_t encoder_get_ctrl(void);
uint32_t encoder_get_window(void);
uint32_t encoder_get_version(void);

#endif /* ENCODER_H */
