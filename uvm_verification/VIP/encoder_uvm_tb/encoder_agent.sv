class encoder_agent extends uvm_agent;
  encoder_driver    drv;
  encoder_monitor   mon;
  encoder_sequencer seqr;
  virtual encoder_if vif;

  `uvm_component_utils(encoder_agent)

  function new(string n, uvm_component p);
    super.new(n, p);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    drv  = encoder_driver::type_id::create("drv", this);
    mon  = encoder_monitor::type_id::create("mon", this);
    seqr = encoder_sequencer::type_id::create("seqr", this);

    if (!uvm_config_db #(virtual encoder_if)::get(
        this,
        "",
        "vif",
        vif
    )) begin
        `uvm_fatal("NOVIF", "Encoder virtual interface not found")
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(seqr.seq_item_export);
    drv.vif = vif;
    mon.vif = vif;
  endfunction
endclass
