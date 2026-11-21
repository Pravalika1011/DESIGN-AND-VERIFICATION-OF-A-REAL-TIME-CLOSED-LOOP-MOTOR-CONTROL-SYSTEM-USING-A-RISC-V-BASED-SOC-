class gpio_agent extends uvm_agent;
  gpio_driver    drv;
  gpio_monitor   mon;
  gpio_sequencer seqr;
  virtual gpio_if vif;

  `uvm_component_utils(gpio_agent)

  function new(string n, uvm_component p);
    super.new(n, p);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    drv  = gpio_driver::type_id::create("drv", this);
    mon  = gpio_monitor::type_id::create("mon", this);
    seqr = gpio_sequencer::type_id::create("seqr", this);

    if (!uvm_config_db #(virtual gpio_if)::get(
        this,
        "",
        "vif",
        vif
    )) begin
        `uvm_fatal("NOVIF", "GPIO virtual interface not found")
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(seqr.seq_item_export);
    drv.vif = vif;
    mon.vif = vif;
  endfunction
endclass
