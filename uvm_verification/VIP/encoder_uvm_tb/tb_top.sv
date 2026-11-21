module tb_top;
import uvm_pkg::*; import encoder_pkg::*;
encoder_if vif();
initial run_test("encoder_test");
endmodule
