// Inference probe: 128x32, one synchronous write port, three async read ports.
module lutram_probe(input logic clk_i,we_i,input logic [6:0] wa_i,ra0_i,ra1_i,ra2_i,
  input logic [31:0] wd_i,output logic [31:0] rd0_o,rd1_o,rd2_o);
  logic [31:0] mem[0:127];
  always_ff @(posedge clk_i) if(we_i) mem[wa_i]<=wd_i;
  assign rd0_o=mem[ra0_i];assign rd1_o=mem[ra1_i];assign rd2_o=mem[ra2_i];
endmodule
