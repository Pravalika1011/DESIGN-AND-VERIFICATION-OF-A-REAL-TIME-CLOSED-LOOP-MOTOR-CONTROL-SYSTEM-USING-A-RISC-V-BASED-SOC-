class encoder_sequencer extends uvm_sequencer #(encoder_item);
`uvm_component_utils(encoder_sequencer)
function new(string n,uvm_component p);super.new(n,p);endfunction
endclass
