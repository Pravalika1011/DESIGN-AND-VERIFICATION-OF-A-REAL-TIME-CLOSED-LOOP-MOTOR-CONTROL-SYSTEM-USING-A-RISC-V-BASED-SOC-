// =============================================================================
// File : pid_ref_model.v
// Desc : Bit-accurate reference model for the PID controller.
//        Written from the SPEC, NOT from the RTL.
//        Uses 64-bit signed integers (Verilog integer is 32-bit; use reg signed
//        [63:0] throughout to match 54-bit ACC_W with headroom).
//        Included inside pid_tb module.
//
//        Key conventions:
//          - Gains are Q16.16 signed 32-bit: value = reg_val / 65536.0
//          - Rounding: (sum + (1<<(FRAC-1))) >>> FRAC  (arithmetic right-shift)
//          - INT limits stored as 32-bit; sign-extended to 54-bit inside
//          - SPEED_W=16, OUT_W=16, FRAC=16, ACC_W=54
// =============================================================================

// ---------------------------------------------------------------------------
// Reference model state
// ---------------------------------------------------------------------------
reg signed [63:0] ref_integrator;
reg signed [16:0] ref_e_prev;       // 17-bit signed error history
reg signed [15:0] ref_act_prev;     // 16-bit signed actual history
reg               ref_first_update;

// ---------------------------------------------------------------------------
// ref_model_reset - reset reference model state
// ---------------------------------------------------------------------------
task ref_model_reset;
    begin
        ref_integrator   = 64'sd0;
        ref_e_prev       = 17'sd0;
        ref_act_prev     = 16'sd0;
        ref_first_update = 1'b1;
    end
endtask

// ---------------------------------------------------------------------------
// ref_model_int_reset - clear integrator and history (mirrors INT_RESET)
// ---------------------------------------------------------------------------
task ref_model_int_reset;
    begin
        ref_integrator   = 64'sd0;
        ref_e_prev       = 17'sd0;
        ref_act_prev     = 16'sd0;
        ref_first_update = 1'b1;
    end
endtask

// ---------------------------------------------------------------------------
// ref_model_compute
//   Inputs  (match RTL register values AT THE TIME OF LATCH):
//     rm_sp       : setpoint  (16-bit signed, passed as 16-bit)
//     rm_act      : actual    (16-bit signed, passed as 16-bit)
//     rm_kp       : Kp Q16.16 (32-bit signed)
//     rm_ki       : Ki Q16.16
//     rm_kd       : Kd Q16.16
//     rm_out_max  : OUT_MAX (16-bit signed stored in 16-bit)
//     rm_out_min  : OUT_MIN (16-bit signed stored in 16-bit)
//     rm_int_max  : INT_MAX lower 32 bits (sign-extended to 54 inside)
//     rm_int_min  : INT_MIN lower 32 bits
//     rm_d_on_meas: D_ON_MEAS flag
//     rm_aw_en    : AW_EN flag
//
//   Outputs:
//     rm_out      : 16-bit PID output after clamping
//     rm_sat_hi   : output saturated high
//     rm_sat_lo   : output saturated low
//     rm_int_sat  : integrator saturated
// ---------------------------------------------------------------------------
task ref_model_compute;
    input signed [15:0] rm_sp;
    input signed [15:0] rm_act;
    input signed [31:0] rm_kp;
    input signed [31:0] rm_ki;
    input signed [31:0] rm_kd;
    input signed [15:0] rm_out_max;
    input signed [15:0] rm_out_min;
    input        [31:0] rm_int_max_reg;
    input        [31:0] rm_int_min_reg;
    input               rm_d_on_meas;
    input               rm_aw_en;
    output signed [15:0] rm_out;
    output               rm_sat_hi;
    output               rm_sat_lo;
    output               rm_int_sat;

    // Local 64-bit signed arithmetic
    reg signed [63:0] e;
    reg signed [63:0] d;
    reg signed [63:0] p_term;
    reg signed [63:0] ki_e;
    reg signed [63:0] d_term;
    reg signed [63:0] i_new;
    reg signed [63:0] i_old;
    reg signed [63:0] sum;
    reg signed [63:0] rounded;
    reg signed [63:0] int_max_ext;
    reg signed [63:0] int_min_ext;
    reg               local_int_sat;
    reg               local_sat_hi;
    reg               local_sat_lo;

    begin
        // Sign-extend INT limits from 32 bits to 64 bits
        int_max_ext = {{32{rm_int_max_reg[31]}}, rm_int_max_reg};
        int_min_ext = {{32{rm_int_min_reg[31]}}, rm_int_min_reg};

        // Error: e = sp - act  (17-bit signed = SPEED_W+1)
        e = $signed(rm_sp) - $signed(rm_act);

        // Derivative
        if (ref_first_update) begin
            d = 64'sd0;
        end else if (!rm_d_on_meas) begin
            // d-on-error: e - e_prev
            d = e - $signed(ref_e_prev);
        end else begin
            // d-on-measurement: -(act - act_prev)
            d = -($signed(rm_act) - $signed(ref_act_prev));
        end

        // P term: Kp * e
        p_term = rm_kp * e;

        // I term: Ki * e
        ki_e   = rm_ki * e;

        // D term: Kd * d
        d_term = rm_kd * d;

        // Integrator pre-accumulate
        i_old = ref_integrator;
        i_new = i_old + ki_e;

        // Clamp integrator
        local_int_sat = 1'b0;
        if (i_new > int_max_ext) begin
            i_new         = int_max_ext;
            local_int_sat = 1'b1;
        end else if (i_new < int_min_ext) begin
            i_new         = int_min_ext;
            local_int_sat = 1'b1;
        end

        // Sum: p + i_new + d
        sum = p_term + i_new + d_term;

        // Round and shift: (sum + (1 << (FRAC-1))) >>> FRAC
        rounded = (sum + 64'sd32768) >>> 16;

        // Output saturation clamp
        local_sat_hi = 1'b0;
        local_sat_lo = 1'b0;
        if (rounded > $signed(rm_out_max)) begin
            rounded      = $signed(rm_out_max);
            local_sat_hi = 1'b1;
        end else if (rounded < $signed(rm_out_min)) begin
            rounded      = $signed(rm_out_min);
            local_sat_lo = 1'b1;
        end

        // Anti-windup: if clamped in the direction of error, discard i_new
        if (rm_aw_en) begin
            if (local_sat_hi && (e > 64'sd0))
                ref_integrator = i_old;   // keep old
            else if (local_sat_lo && (e < 64'sd0))
                ref_integrator = i_old;   // keep old
            else
                ref_integrator = i_new;
        end else begin
            ref_integrator = i_new;
        end

        // Update history
        ref_e_prev       = e[16:0];
        ref_act_prev     = rm_act;
        ref_first_update = 1'b0;

        // Outputs
        rm_out     = rounded[15:0];
        rm_sat_hi  = local_sat_hi;
        rm_sat_lo  = local_sat_lo;
        rm_int_sat = local_int_sat;
    end
endtask

// ---------------------------------------------------------------------------
// wait_and_check_update
//   Drive a tick, wait for pid_out_valid, then compute reference model and
//   check pid_out_o, STATUS.ERROR, STATUS.ACTUAL.
//   Registers must already be written before calling this.
//   rm_sp/act/kp/ki/kd/out_max/out_min/int_max/int_min read from regs below.
// ---------------------------------------------------------------------------
task wait_and_check_update;
    input        [15:0] sp_val;
    input        [15:0] act_val;
    input        [31:0] kp_val;
    input        [31:0] ki_val;
    input        [31:0] kd_val;
    input signed [15:0] out_max_val;
    input signed [15:0] out_min_val;
    input        [31:0] int_max_val;
    input        [31:0] int_min_val;
    input               d_on_meas_val;
    input               aw_en_val;
    input        [7:0]  update_num;

    reg signed [15:0] exp_out;
    reg               exp_sat_hi, exp_sat_lo, exp_int_sat;
    reg        [31:0] rtl_out_reg;
    reg        [31:0] rtl_err_reg;
    reg        [31:0] rtl_act_reg;
    reg        [1:0]  rsp;
    reg               to;
    integer           tw;
    reg        [63:0] desc_buf;

    begin
        // Trigger tick using nonblocking to avoid race with RTL posedge sampling
        // Snapshot counter BEFORE raising tick so we can't miss the pulse
        tw = 0;
        begin : wac_snap
            integer snap_wac;
            snap_wac = pid_valid_cnt;
            @(posedge clk);
            tick_i <= 1'b1;
            @(posedge clk);
            tick_i <= 1'b0;

            // Wait using counter: immune to pulse arriving before we start polling
            @(posedge clk);
            while (pid_valid_cnt == snap_wac && tw < `UPDATE_TIMEOUT) begin
                @(posedge clk);
                tw = tw + 1;
            end
        end

        // Compute reference
        ref_model_compute(
            $signed(sp_val), $signed(act_val),
            $signed(kp_val), $signed(ki_val), $signed(kd_val),
            $signed(out_max_val), $signed(out_min_val),
            int_max_val, int_min_val,
            d_on_meas_val, aw_en_val,
            exp_out, exp_sat_hi, exp_sat_lo, exp_int_sat
        );

        // Extra cycle for slave pipeline to capture
        @(posedge clk);

        // Check pid_out_o directly
        `CHECK_EQ_SIGNED("update pid_out_o", $signed(exp_out), $signed(pid_out_o))

        // Check register readbacks (slave adds pipeline; read after valid)
        axi_read(`ADDR_OUTPUT, rtl_out_reg, rsp);
        `CHECK_EQ_SIGNED("update OUTPUT reg", $signed({{16{exp_out[15]}}, exp_out}),
                         $signed(rtl_out_reg))

        axi_read(`ADDR_ERROR, rtl_err_reg, rsp);
        // ERROR reg: sign-extended 17-bit; ref e is in ref_e_prev after compute
        // (ref_e_prev was updated inside ref_model_compute)
        `CHECK_EQ_SIGNED("update ERROR reg",
             $signed({{15{ref_e_prev[16]}}, ref_e_prev}), $signed(rtl_err_reg))

        axi_read(`ADDR_ACTUAL, rtl_act_reg, rsp);
        `CHECK_EQ_SIGNED("update ACTUAL reg",
             $signed({{16{act_val[15]}}, act_val}), $signed(rtl_act_reg))

        if (tw >= `UPDATE_TIMEOUT) begin
            $display("FAIL update_%0d TIMEOUT waiting for pid_out_valid", update_num);
            total_fails = total_fails + 1; test_fails = test_fails + 1;
        end
    end
endtask
