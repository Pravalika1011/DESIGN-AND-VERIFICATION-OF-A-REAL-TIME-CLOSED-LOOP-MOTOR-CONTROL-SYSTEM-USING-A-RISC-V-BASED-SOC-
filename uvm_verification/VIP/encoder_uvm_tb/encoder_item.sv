class encoder_item extends uvm_sequence_item;

  rand bit enc_a;
  rand bit enc_b;
  rand bit enc_index;
  rand bit enc_drive_active;
  bit [15:0] enc_speed;
  bit enc_speed_valid;
  bit enc_count_valid;
  bit enc_dir;
  bit enc_fault;
  bit enc_intr;

  `uvm_object_utils(encoder_item)

  function new(string name="encoder_item"); super.new(name); endfunction
endclass
