class uart_agent extends uvm_agent;
  uart_driver    drv;
  uart_monitor   mon;
  uart_sequencer seqr;
  virtual uart_if vif;

  `uvm_component_utils(uart_agent)

  function new(string n, uvm_component p);
    super.new(n, p);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    drv  = uart_driver::type_id::create("drv", this);
    mon  = uart_monitor::type_id::create("mon", this);
    seqr = uart_sequencer::type_id::create("seqr", this);

    if (!uvm_config_db #(virtual uart_if)::get(
        this,
        "",
        "vif",
        vif
    )) begin
        `uvm_fatal("NOVIF", "UART virtual interface not found")
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(seqr.seq_item_export);
    drv.vif = vif;
    mon.vif = vif;
  endfunction
endclass
