// ============================================================================
// SoC UVM Test Package
// ============================================================================

package soc_test_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import gpio_pkg::*;
  import uart_pkg::*;
  import encoder_pkg::*;
  import pwm_pkg::*;
  import soc_env_pkg::*;

  `include "soc_base_test.sv"
endpackage
