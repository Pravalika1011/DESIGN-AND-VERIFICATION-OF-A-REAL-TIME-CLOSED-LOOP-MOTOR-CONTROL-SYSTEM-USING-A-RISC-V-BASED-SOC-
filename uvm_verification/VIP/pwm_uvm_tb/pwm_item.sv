class pwm_item extends uvm_sequence_item;

  bit PWM_OUT;

  `uvm_object_utils(pwm_item)

  function new(string name="pwm_item"); super.new(name); endfunction
endclass
