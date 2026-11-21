class encoder_driver extends uvm_driver #(encoder_item);
  virtual encoder_if vif;

  `uvm_component_utils(encoder_driver)

  function new(string n, uvm_component p);
    super.new(n, p);
  endfunction

  task run_phase(uvm_phase phase);
    vif.enc_a            <= 1'b0;
    vif.enc_b            <= 1'b0;
    vif.enc_index        <= 1'b0;
    vif.enc_drive_active <= 1'b1;

    forever begin
      seq_item_port.get_next_item(req);
      @(posedge vif.clk);
      vif.enc_a            <= req.enc_a;
      vif.enc_b            <= req.enc_b;
      vif.enc_index        <= req.enc_index;
      vif.enc_drive_active <= req.enc_drive_active;
      seq_item_port.item_done();
    end
  endtask
endclass
