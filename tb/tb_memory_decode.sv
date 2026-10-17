`timescale 1ns/1ps
module tb_memory_decode;
  logic clk_i=0,rst_ni=0;always #5 clk_i=~clk_i;
  axi_lite_if ram(clk_i,rst_ni),rom(clk_i,rst_ni);
  axi_lite_bfm host_ram(.clk_i,.axi(ram));
  axi_lite_bfm host_rom(.clk_i,.axi(rom));
  axi_lite_ram #(.WORDS(256)) u_ram(.clk_i,.rst_ni,.s_axi(ram));
  axi_lite_rom #(.WORDS(256)) u_rom(.clk_i,.rst_ni,.s_axi(rom));
  logic[31:0]d;
  initial begin
    repeat(5)@(negedge clk_i);rst_ni=1;
    host_ram.write('h20000000,'h12345678,15,0,-3);
    host_ram.write('h20000000,'haabbccdd,5,0,3);
    host_ram.read('h20000000,d);assert(d=='h12bb56dd)else $fatal(1,"RAM byte strobes");
    host_ram.write('h20000400,1,15,3);host_ram.read('h20000400,d,3);
    host_ram.write('h20000001,1,15,3);host_ram.read('h20000001,d,3);
    host_ram.write('h30000000,1,15,3);host_ram.read('h30000000,d,3);
    host_ram.read('h20000000,d);assert(d=='h12bb56dd)else $fatal(1,"Invalid write aliased valid RAM");
    host_rom.read(0,d);assert(d=='h13)else $fatal(1,"ROM NOP");
    host_rom.write(0,1,15,2);host_rom.read(0,d);assert(d=='h13)else $fatal(1,"ROM modified");
    host_rom.read(1024,d,3);host_rom.read(2,d,3);
    // Reset after AW only must discard the partial write, retaining memory.
    @(negedge clk_i);ram.awaddr='h20000000;ram.awvalid=1;
    do @(posedge clk_i);while(!ram.awready);
    @(negedge clk_i);ram.awvalid=0;rst_ni=0;
    repeat(3)@(negedge clk_i);rst_ni=1;
    host_ram.read('h20000000,d);assert(d=='h12bb56dd)else $fatal(1,"RAM erased on reset");
    host_ram.write('h20000004,'hdeadcafe);
    host_ram.read('h20000004,d);assert(d=='hdeadcafe)else $fatal(1,"Partial write survived reset");
    $display("TEST_PASS: RAM/ROM range, alignment, read-only, strobes, backpressure and reset retention");$finish;
  end
  initial begin #100000;$fatal(1,"Memory timeout");end
endmodule
