class gpio_driver extends uvm_driver #(gpio_item);
  virtual gpio_if vif;

  `uvm_component_utils(gpio_driver)

  function new(string n, uvm_component p);
    super.new(n, p);
  endfunction

  task run_phase(uvm_phase phase);
    // Initialize VIP side to high-impedance (release bus)
    vif.gpio_drv_val <= 32'h0000_0000;
    vif.gpio_drv_en  <= 32'h0000_0000;

    forever begin
      seq_item_port.get_next_item(req);
      @(posedge vif.clk);
      // Drive stimulus on pins
      vif.gpio_drv_val <= req.gpio_io;
      vif.gpio_drv_en  <= 32'hFFFF_FFFF;
      @(posedge vif.clk);
      // Release drive back to high-impedance to prevent bus contention
      vif.gpio_drv_en  <= 32'h0000_0000;
      seq_item_port.item_done();
    end
  endtask
endclass
