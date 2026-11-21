class uart_driver extends uvm_driver #(uart_item);
  virtual uart_if vif;

  `uvm_component_utils(uart_driver)

  function new(string n, uvm_component p);
    super.new(n, p);
  endfunction

  task run_phase(uvm_phase phase);
    // UART RX idle state is logic 1
    vif.uart_rx <= 1'b1;

    forever begin
      seq_item_port.get_next_item(req);
      @(posedge vif.clk);
      vif.uart_rx <= req.uart_rx;
      seq_item_port.item_done();
    end
  endtask
endclass
