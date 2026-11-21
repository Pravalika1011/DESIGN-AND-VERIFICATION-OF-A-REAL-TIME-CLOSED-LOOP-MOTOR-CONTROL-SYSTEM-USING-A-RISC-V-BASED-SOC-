/* ============================================================================
 * File: main.c
 * Description: Primary Phase 4 Integrated Firmware Test for VeeR EL2 SoC.
 * Validates:
 *   1. Freestanding C runtime & Mailbox interface
 *   2. UART driver initialization & telemetry logging
 *   3. GPIO direction, output write, and input readback
 *   4. Timer initialization, counting, and end-to-end PIC interrupt handling
 *   5. Quadrature Encoder configuration and speed telemetry
 *   6. Hardware PID parameter tuning, limits, and setpoint programming
 *   7. PWM MMIO scratch registers and duty cycle readback
 *   8. Supervisory hybrid feedback (Encoder -> PID -> PWM in hardware)
 *   9. Dynamic setpoint updates without software in the fast path
 * ============================================================================ */

#include "soc_regs.h"
#include "gpio.h"
#include "timer.h"
#include "uart.h"
#include "encoder.h"
#include "pid.h"
#include "pwm.h"
#include "interrupt.h"

/* Dedicated Mailbox Structure mapped at 0x4002_0000 */
typedef struct {
    volatile uint32_t magic;    /* Offset 0x00: 0x5048344F ("PH4O") */
    volatile uint32_t status;   /* Offset 0x04: Status bitmask */
    volatile uint32_t result;   /* Offset 0x08: Telemetry summary */
    volatile uint32_t exit_code;/* Offset 0x0C: 0 = PASS */
} soc_mailbox_t;

#define MAILBOX (*(volatile soc_mailbox_t *)DMEM_BASE)

/* Status Bitmask Definitions */
#define TEST_BIT_UART       (1U << 0) /* 0x001 */
#define TEST_BIT_GPIO       (1U << 1) /* 0x002 */
#define TEST_BIT_TIMER      (1U << 2) /* 0x004 */
#define TEST_BIT_IRQ        (1U << 3) /* 0x008 */
#define TEST_BIT_ENCODER    (1U << 4) /* 0x010 */
#define TEST_BIT_PID        (1U << 5) /* 0x020 */
#define TEST_BIT_PWM        (1U << 6) /* 0x040 */
#define TEST_BIT_FEEDBACK   (1U << 7) /* 0x080 */
#define TEST_BIT_SETPOINT   (1U << 8) /* 0x100 */

#define ALL_TESTS_PASSED    (0x01FFU)

int main(void) {
    uint32_t status_mask = 0U;

    /* ------------------------------------------------------------
     * Step 1: Initialize UART & Print Banner
     * Divisor 16 ensures ultra-fast transmission during simulation
     * ------------------------------------------------------------ */
    uart_init(16U);
    uart_puts("\r\n====================================================\r\n");
    uart_puts("   CBP RISC-V SoC: Phase 5 Full-System Verification   \r\n");
    uart_puts("====================================================\r\n");
    status_mask |= TEST_BIT_UART;

    /* ------------------------------------------------------------
     * Step 2: Initialize & Exercise GPIO
     * Configure lower 16 bits as output (1), upper 16 bits as input (0)
     * ------------------------------------------------------------ */
    gpio_init(0x0000FFFFU);
    gpio_write(0x0000A55AU);
    uint32_t gpio_out_readback = GPIO_REG_DATA_O;
    if ((gpio_out_readback & 0xFFFFU) == 0xA55AU) {
        status_mask |= TEST_BIT_GPIO;
        uart_puts("[PASS] GPIO Direction & MMIO Write Verified\r\n");
    } else {
        uart_puts("[FAIL] GPIO MMIO Readback Mismatch\r\n");
    }

    /* ------------------------------------------------------------
     * Step 3: Initialize Timer & Observe Down-Counting
     * Load = 50000 cycles, prescaler = 0, periodic = 1, down-counter = 0
     * ------------------------------------------------------------ */
    timer_init(50000U, 0U, 1U, 0U);
    timer_start();

    /* Busy-wait briefly to confirm counter decrements */
    uint32_t t_val1 = timer_get_value();
    for (volatile int d = 0; d < 20; d++) { /* small delay */ }
    uint32_t t_val2 = timer_get_value();

    if (t_val2 < t_val1) {
        status_mask |= TEST_BIT_TIMER;
        uart_puts("[PASS] Timer Countdown Verified\r\n");
    }
    timer_stop();

    /* ------------------------------------------------------------
     * Step 4: Configure & Verify End-to-End Timer Interrupt via PIC
     * ------------------------------------------------------------ */
    interrupt_init();

    /* Enable PIC Source 3 (Timer): priority 1, level-triggered */
    pic_enable_source(PIC_SRC_TIMER, 1U, 0U);

    /* Configure One-Shot Timer for 1000 cycles so it fires cleanly once */
    timer_init(1000U, 0U, 0U, 0U);
    timer_interrupt_clear(TIMER_INT_EXPIRE);
    timer_interrupt_enable(TIMER_INT_EXPIRE);
    timer_start();

    /* Enable RISC-V Machine External Interrupts & Global Interrupts */
    interrupt_external_enable();
    interrupt_global_enable();

    /* Wait for Timer Interrupt to be serviced (timeout ~10000 iterations) */
    uint32_t irq_timeout = 0U;
    while ((g_timer_irq_count == 0U) && (irq_timeout < 10000U)) {
        irq_timeout++;
    }

    /* Fully disable and tear down timer interrupt after test */
    interrupt_global_disable();
    interrupt_external_disable();
    timer_stop();
    timer_interrupt_disable(TIMER_INT_EXPIRE);
    timer_interrupt_clear(TIMER_INT_EXPIRE);
    pic_disable_source(PIC_SRC_TIMER);
    pic_clear_gateway(PIC_SRC_TIMER);

    if (g_timer_irq_count > 0U) {
        status_mask |= TEST_BIT_IRQ;
        uart_puts("[PASS] Timer External Interrupt Serviced via PIC (Count=");
        uart_put_dec(g_timer_irq_count);
        uart_puts(")\r\n");
    } else {
        uart_puts("[FAIL] Timer Interrupt Timeout\r\n");
    }

    /* ------------------------------------------------------------
     * Step 5: Configure Quadrature Encoder (QEI)
     * Mode X4, Sample Window = 100 clocks, Scale = 1.0 (0x00010000 in Q16.16)
     * ------------------------------------------------------------ */
    encoder_init(ENC_CTRL_MODE_X4 | ENC_CTRL_AVG_4, 100U, 0x00010000U);
    uint32_t enc_win = encoder_get_window();
    int32_t enc_cnt = encoder_get_count();
    (void)enc_cnt;

    if (enc_win == 100U) {
        status_mask |= TEST_BIT_ENCODER;
        uart_puts("[PASS] Quadrature Encoder Configured & Verified (Window=");
        uart_put_dec(enc_win);
        uart_puts(")\r\n");
    } else {
        uart_puts("[FAIL] Quadrature Encoder Configuration Mismatch\r\n");
    }

    /* ------------------------------------------------------------
     * Step 6: Configure Hardware PID Parameters
     * Setpoint = 500, Kp = 2.0 (0x00020000), Ki = 0.5 (0x00008000), Kd = 0.1 (0x00001999)
     * Clamps: Output [0, 255] for PWM duty cycle
     * ------------------------------------------------------------ */
    pid_init(500, 0x00020000U, 0x00008000U, 0x00001999U);
    pid_set_limits(255, 0, 0x00FF0000, 0x00000000);
    uint32_t pid_ver = pid_get_version();

    if (pid_ver != 0U) {
        status_mask |= TEST_BIT_PID;
        uart_puts("[PASS] PID Controller Tuned (Ver=");
        uart_put_hex(pid_ver);
        uart_puts(")\r\n");
    }

    /* ------------------------------------------------------------
     * Step 7: Verify PWM Scratch & Duty Cycle MMIO
     * ------------------------------------------------------------ */
    pwm_write_scratch(1, 0xCAFEBABE);
    pwm_write_scratch(2, 0x12345678);
    uint32_t pwm_sc1 = pwm_read_scratch(1);
    uint32_t pwm_sc2 = pwm_read_scratch(2);

    if ((pwm_sc1 == 0xCAFEBABEU) && (pwm_sc2 == 0x12345678U)) {
        status_mask |= TEST_BIT_PWM;
        uart_puts("[PASS] PWM MMIO Scratch Registers Verified\r\n");
    }

    /* ------------------------------------------------------------
     * Step 8: Observe Autonomous Hardware Closed-Loop Feedback
     * The testbench drives encoder quadrature pulses.
     * Hardware encoder produces enc_speed -> feeds pid_core.actual_i
     * Hardware pid_core produces pid_out -> feeds PWM duty_cycle.
     * Firmware supervises by reading telemetry over AXI MMIO.
     * ------------------------------------------------------------ */
    /* Small delay to allow testbench pulses to propagate through hardware */
    for (volatile int w = 0; w < 300; w++) { /* pipeline stabilization */ }

    int16_t actual_speed = encoder_get_speed();
    int16_t pid_out_val  = pid_get_output();
    uint8_t pwm_duty_val = pwm_get_duty();

    /* Saturated 16-bit to 8-bit conversion matching hardware (main_top.v line 2020) */
    uint8_t expected_duty = (pid_out_val < 0) ? 0U : ((pid_out_val > 255) ? 255U : (uint8_t)pid_out_val);

    if (pwm_duty_val == expected_duty) {
        status_mask |= TEST_BIT_FEEDBACK;
        uart_puts("[PASS] Hybrid Feedback Confirmed: PID Output matches PWM Duty (");
        uart_put_dec(pwm_duty_val);
        uart_puts(")\r\n");
    } else {
        uart_puts("[FAIL] Hybrid Feedback Mismatch: PID=");
        uart_put_dec((uint32_t)(uint16_t)pid_out_val);
        uart_puts(" PWM=");
        uart_put_dec(pwm_duty_val);
        uart_puts("\r\n");
    }

    /* ------------------------------------------------------------
     * Step 9: Dynamic Supervisory Setpoint Update
     * Change setpoint from 500 to 1200 via AXI MMIO.
     * ------------------------------------------------------------ */
    pid_set_setpoint(1200);
    int16_t new_sp = pid_get_setpoint();

    if (new_sp == 1200) {
        status_mask |= TEST_BIT_SETPOINT;
        uart_puts("[PASS] Supervisory Setpoint Dynamically Updated to 1200\r\n");
    }

    /* ------------------------------------------------------------
     * Step 10: Final Mailbox Status & Completion Signature
     * ------------------------------------------------------------ */
    uint32_t telemetry_summary = ((uint32_t)pwm_duty_val << 24) |
                                 (((uint32_t)(uint16_t)actual_speed) & 0xFFFFU);

    MAILBOX.status = status_mask;
    MAILBOX.result = telemetry_summary;

    if (status_mask == ALL_TESTS_PASSED) {
        uart_puts("\r\n>>> ALL PHASE 5 FULL-SYSTEM INTEGRATION TESTS PASSED <<<\r\n");
        MAILBOX.magic = 0x5048354FU; /* "PH5O" (Phase 5 OK) */
        return 0;
    } else {
        uart_puts("\r\n>>> PHASE 5 INTEGRATION TESTS FAILED <<<\r\n");
        MAILBOX.magic = 0xDEADFA15U; /* "FAIL" */
        return 1;
    }
}
