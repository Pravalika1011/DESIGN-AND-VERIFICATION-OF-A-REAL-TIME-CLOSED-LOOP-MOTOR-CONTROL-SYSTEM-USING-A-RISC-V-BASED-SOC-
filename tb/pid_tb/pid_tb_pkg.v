// =============================================================================
// File : pid_tb_pkg.v
// Desc : Shared parameters, register addresses and helper macros for the
//        PID controller testbench.  Included by pid_tb.v.
// =============================================================================

// ---------------------------------------------------------------------------
// Clock / timing
// ---------------------------------------------------------------------------
`define CLK_PERIOD   10          // 10 ns  -> 100 MHz
`define RESET_CYCLES  8          // hold reset for 8 clocks

// ---------------------------------------------------------------------------
// Register byte addresses (AXI word-aligned)
// ---------------------------------------------------------------------------
`define ADDR_SETPOINT  32'h00
`define ADDR_KP        32'h04
`define ADDR_KI        32'h08
`define ADDR_KD        32'h0C
`define ADDR_OUTPUT    32'h10
`define ADDR_CTRL      32'h14
`define ADDR_STATUS    32'h18
`define ADDR_ERROR     32'h1C
`define ADDR_ACTUAL    32'h20
`define ADDR_OUT_MAX   32'h24
`define ADDR_OUT_MIN   32'h28
`define ADDR_INT_MAX   32'h2C
`define ADDR_INT_MIN   32'h30
`define ADDR_VERSION   32'h34

// ---------------------------------------------------------------------------
// CTRL bit masks
// ---------------------------------------------------------------------------
`define CTRL_ENABLE        32'h01
`define CTRL_INT_RESET     32'h02
`define CTRL_MANUAL_UPDATE 32'h04
`define CTRL_D_ON_MEAS     32'h08
`define CTRL_AW_EN         32'h10
`define CTRL_IRQ_EN        32'h20

// ---------------------------------------------------------------------------
// STATUS bit positions
// ---------------------------------------------------------------------------
`define STAT_BUSY      0
`define STAT_DONE      1
`define STAT_SAT_HI    2
`define STAT_SAT_LO    3
`define STAT_INT_SAT   4
`define STAT_OVERRUN   5

// ---------------------------------------------------------------------------
// AXI response codes
// ---------------------------------------------------------------------------
`define AXI_OKAY    2'b00
`define AXI_SLVERR  2'b10

// ---------------------------------------------------------------------------
// Reset values
// ---------------------------------------------------------------------------
`define RST_OUT_MAX  32'h00007FFF
`define RST_OUT_MIN  32'h00000000
`define RST_INT_MAX  32'h7FFFFFFF
`define RST_INT_MIN  32'h80000000
`define RST_VERSION  32'h00010000

// ---------------------------------------------------------------------------
// Datapath widths (mirror RTL)
// ---------------------------------------------------------------------------
`define SPEED_W   16
`define OUT_W     16
`define GAIN_W    32
`define FRAC      16
`define ERR_W     17
`define ACC_W     54

// ---------------------------------------------------------------------------
// Timeout / watchdog
// ---------------------------------------------------------------------------
`define UPDATE_TIMEOUT  20       // max cycles for one PID update (8 + margin)
`define AXI_TIMEOUT     50       // max cycles waiting for AXI handshake
`define SIM_TIMEOUT     10000000 // overall simulation watchdog (ns)

// ---------------------------------------------------------------------------
// Scoreboard macros
// ---------------------------------------------------------------------------
// Usage: `CHECK_EQ(description, expected, got)
`define CHECK_EQ(desc, exp, got) \
    begin \
        total_checks = total_checks + 1; \
        if ((exp) !== (got)) begin \
            $display("FAIL %s exp=%0h got=%0h @%0t", desc, exp, got, $time); \
            total_fails  = total_fails  + 1; \
            test_fails   = test_fails   + 1; \
        end else begin \
            total_passes = total_passes + 1; \
        end \
    end

`define CHECK_EQ_SIGNED(desc, exp, got) \
    begin \
        total_checks = total_checks + 1; \
        if ($signed(exp) !== $signed(got)) begin \
            $display("FAIL %s exp=%0d got=%0d @%0t", desc, $signed(exp), $signed(got), $time); \
            total_fails  = total_fails  + 1; \
            test_fails   = test_fails   + 1; \
        end else begin \
            total_passes = total_passes + 1; \
        end \
    end

`define CHECK_RESP(desc, exp, got) \
    begin \
        total_checks = total_checks + 1; \
        if ((exp) !== (got)) begin \
            $display("FAIL %s resp exp=%0b got=%0b @%0t", desc, exp, got, $time); \
            total_fails  = total_fails  + 1; \
            test_fails   = test_fails   + 1; \
        end else begin \
            total_passes = total_passes + 1; \
        end \
    end

`define TEST_START(n, name) \
    begin \
        cur_test     = n; \
        test_fails   = 0; \
        $display("[TEST %02d] %s START @%0t", n, name, $time); \
    end

`define TEST_END(n, name) \
    begin \
        if (test_fails == 0) \
            $display("[TEST %02d] %s PASS (checks=%0d fails=0)", n, name, total_checks - prev_checks); \
        else \
            $display("[TEST %02d] %s FAIL (checks=%0d fails=%0d)", n, name, total_checks - prev_checks, test_fails); \
        test_results[n] = (test_fails == 0) ? 1 : 0; \
        test_check_cnt[n] = total_checks - prev_checks; \
        test_fail_cnt[n]  = test_fails; \
        prev_checks  = total_checks; \
    end
