class gpio_monitor extends uvm_monitor;
  virtual gpio_if vif;
  uvm_analysis_port #(gpio_item) ap;

  `uvm_component_utils(gpio_monitor)

  function new(string n, uvm_component p);
    super.new(n, p);
    ap = new("ap", this);
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      gpio_item item;
      @(posedge vif.clk);
      if (vif.gpio_drv_en != 32'h0) begin
        item = gpio_item::type_id::create("item");
        item.gpio_io   = vif.gpio_io;
        item.gpio_intr = vif.gpio_intr;
        ap.write(item);
      end
    end
  endtask
endclass
