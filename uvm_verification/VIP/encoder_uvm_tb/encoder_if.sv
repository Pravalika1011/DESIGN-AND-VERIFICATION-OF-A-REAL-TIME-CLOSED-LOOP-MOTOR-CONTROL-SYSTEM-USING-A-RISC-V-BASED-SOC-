interface encoder_if;
logic clk;
logic rst;
logic enc_a;
logic enc_b;
logic enc_index;
logic enc_drive_active;
logic [15:0] enc_speed;
logic enc_speed_valid;
logic enc_count_valid;
logic enc_dir;
logic enc_fault;
logic enc_intr;
endinterface
