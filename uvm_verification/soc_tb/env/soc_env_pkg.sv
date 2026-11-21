// ============================================================================
// SoC UVM Environment Package
// ============================================================================

package soc_env_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import gpio_pkg::*;
  import uart_pkg::*;
  import encoder_pkg::*;
  import pwm_pkg::*;

  `include "soc_checker.sv"
  `include "soc_env.sv"
endpackage
