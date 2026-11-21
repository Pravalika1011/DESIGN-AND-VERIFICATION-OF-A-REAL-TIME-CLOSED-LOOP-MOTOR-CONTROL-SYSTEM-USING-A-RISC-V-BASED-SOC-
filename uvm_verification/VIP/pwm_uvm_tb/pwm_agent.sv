class pwm_agent extends uvm_agent;
  pwm_monitor    mon;
  virtual pwm_if vif;

  `uvm_component_utils(pwm_agent)

  function new(string n, uvm_component p);
    super.new(n, p);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = pwm_monitor::type_id::create("mon", this);

    if (!uvm_config_db #(virtual pwm_if)::get(
        this,
        "",
        "vif",
        vif
    )) begin
        `uvm_fatal("NOVIF", "PWM virtual interface not found")
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    mon.vif = vif;
  endfunction
endclass
