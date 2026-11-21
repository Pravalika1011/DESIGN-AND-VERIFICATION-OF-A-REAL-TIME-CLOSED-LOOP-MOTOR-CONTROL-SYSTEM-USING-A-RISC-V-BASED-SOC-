class gpio_item extends uvm_sequence_item;

  bit [31:0] gpio_io;
  bit gpio_intr;

  `uvm_object_utils(gpio_item)

  function new(string name="gpio_item"); super.new(name); endfunction
endclass
