class encoder_env extends uvm_env;
encoder_agent agent; encoder_scoreboard sb;
`uvm_component_utils(encoder_env)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); agent=encoder_agent::type_id::create("agent",this); sb=encoder_scoreboard::type_id::create("sb",this); endfunction
endclass
