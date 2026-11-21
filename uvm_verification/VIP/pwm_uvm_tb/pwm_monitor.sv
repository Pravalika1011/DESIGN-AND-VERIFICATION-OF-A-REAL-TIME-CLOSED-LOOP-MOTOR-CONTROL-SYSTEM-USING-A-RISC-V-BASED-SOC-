class pwm_monitor extends uvm_monitor;
  virtual pwm_if vif;
  uvm_analysis_port #(pwm_item) ap;

  `uvm_component_utils(pwm_monitor)

  function new(string n, uvm_component p);
    super.new(n, p);
    ap = new("ap", this);
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      pwm_item item;
      @(posedge vif.clk);
      item = pwm_item::type_id::create("item");
      item.PWM_OUT = vif.PWM_OUT;
      ap.write(item);
    end
  endtask
endclass
