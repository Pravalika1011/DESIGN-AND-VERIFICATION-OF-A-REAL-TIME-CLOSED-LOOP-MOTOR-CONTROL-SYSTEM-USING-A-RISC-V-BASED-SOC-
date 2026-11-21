// ============================================================================
// SoC UVM Environment
// Integrates the 4 external peripheral VIP agents: GPIO, UART, Encoder, PWM
// and the minimal signal-driving checker.
// ============================================================================

class soc_env extends uvm_env;
  gpio_pkg::gpio_agent       gpio_agent;
  uart_pkg::uart_agent       uart_agent;
  encoder_pkg::encoder_agent encoder_agent;
  pwm_pkg::pwm_agent         pwm_agent;
  soc_checker                checker_h;

  `uvm_component_utils(soc_env)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    gpio_agent    = gpio_pkg::gpio_agent::type_id::create("gpio_agent", this);
    uart_agent    = uart_pkg::uart_agent::type_id::create("uart_agent", this);
    encoder_agent = encoder_pkg::encoder_agent::type_id::create("encoder_agent", this);
    pwm_agent     = pwm_pkg::pwm_agent::type_id::create("pwm_agent", this);
    checker_h     = soc_checker::type_id::create("checker_h", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    gpio_agent.mon.ap.connect(checker_h.gpio_export);
    uart_agent.mon.ap.connect(checker_h.uart_export);
    encoder_agent.mon.ap.connect(checker_h.encoder_export);
    pwm_agent.mon.ap.connect(checker_h.pwm_export);
  endfunction
endclass
