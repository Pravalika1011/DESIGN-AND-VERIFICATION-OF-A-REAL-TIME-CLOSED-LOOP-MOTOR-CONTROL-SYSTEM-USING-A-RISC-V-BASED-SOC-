class encoder_test extends uvm_test;
encoder_env env;
`uvm_component_utils(encoder_test)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); env=encoder_env::type_id::create("env",this); endfunction
endclass
