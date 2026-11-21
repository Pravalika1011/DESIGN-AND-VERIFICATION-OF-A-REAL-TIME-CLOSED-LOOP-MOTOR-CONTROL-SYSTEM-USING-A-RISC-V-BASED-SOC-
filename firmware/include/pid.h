#ifndef PID_H
#define PID_H

#include "soc_regs.h"

/* PID Control Bit Positions */
#define PID_CTRL_ENABLE         (1U << 0)
#define PID_CTRL_INT_RESET      (1U << 1)
#define PID_CTRL_MANUAL_UPDATE  (1U << 2)
#define PID_CTRL_D_ON_MEAS      (1U << 3)
#define PID_CTRL_AW_EN          (1U << 4) /* Anti-windup enable */
#define PID_CTRL_IRQ_EN         (1U << 5)

/* PID Status Bit Positions */
#define PID_STAT_BUSY           (1U << 0)
#define PID_STAT_DONE           (1U << 1)
#define PID_STAT_SAT_HI         (1U << 2)
#define PID_STAT_SAT_LO         (1U << 3)
#define PID_STAT_INT_SAT        (1U << 4)
#define PID_STAT_OVERRUN        (1U << 5)

void pid_init(int16_t setpoint, uint32_t kp, uint32_t ki, uint32_t kd);
void pid_set_limits(int16_t out_max, int16_t out_min, int32_t int_max, int32_t int_min);
void pid_set_setpoint(int16_t setpoint);
int16_t pid_get_setpoint(void);
void pid_enable(uint8_t enable_irq);
void pid_disable(void);
void pid_reset_integrator(void);
int16_t pid_get_output(void);
int16_t pid_get_error(void);
int16_t pid_get_actual(void);
uint32_t pid_get_status(void);
void pid_clear_status(uint32_t mask);
uint32_t pid_get_version(void);

#endif /* PID_H */
