class encoder_monitor extends uvm_monitor;
  virtual encoder_if vif;
  uvm_analysis_port #(encoder_item) ap;

  `uvm_component_utils(encoder_monitor)

  function new(string n, uvm_component p);
    super.new(n, p);
    ap = new("ap", this);
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      encoder_item item;
      @(posedge vif.clk);
      item = encoder_item::type_id::create("item");
      item.enc_a            = vif.enc_a;
      item.enc_b            = vif.enc_b;
      item.enc_index        = vif.enc_index;
      item.enc_drive_active = vif.enc_drive_active;
      item.enc_speed        = vif.enc_speed;
      item.enc_speed_valid  = vif.enc_speed_valid;
      item.enc_count_valid  = vif.enc_count_valid;
      item.enc_dir          = vif.enc_dir;
      item.enc_fault        = vif.enc_fault;
      item.enc_intr         = vif.enc_intr;
      ap.write(item);
    end
  endtask
endclass
