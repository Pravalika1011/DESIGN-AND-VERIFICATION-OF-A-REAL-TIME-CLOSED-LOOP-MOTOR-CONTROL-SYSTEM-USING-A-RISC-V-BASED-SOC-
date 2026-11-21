class uart_monitor extends uvm_monitor;
  virtual uart_if vif;
  uvm_analysis_port #(uart_item) ap;

  `uvm_component_utils(uart_monitor)

  function new(string n, uvm_component p);
    super.new(n, p);
    ap = new("ap", this);
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      uart_item item;
      @(posedge vif.clk);
      item = uart_item::type_id::create("item");
      item.uart_rx  = vif.uart_rx;
      item.uart_tx  = vif.uart_tx;
      item.uart_irq = vif.uart_irq;
      ap.write(item);
    end
  endtask
endclass
