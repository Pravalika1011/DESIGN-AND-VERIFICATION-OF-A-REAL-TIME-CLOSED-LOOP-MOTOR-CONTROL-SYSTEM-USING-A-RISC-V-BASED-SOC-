interface gpio_if;
  logic        clk;
  logic        rst;
  wire  [31:0] gpio_io;
  logic        gpio_intr;

  // VIP-side tri-state driver signals
  logic [31:0] gpio_drv_val;
  logic [31:0] gpio_drv_en;

  genvar i;
  generate
    for (i = 0; i < 32; i++) begin : gen_gpio_tri
      assign gpio_io[i] = gpio_drv_en[i] ? gpio_drv_val[i] : 1'bz;
    end
  endgenerate
endinterface
