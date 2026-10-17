`timescale 1ns/1ps
module tb_uart_irq;
  logic clk_i=0,rst_ni=0,tx,irq;
  always #5 clk_i=~clk_i;
  axi_lite_if axi(clk_i,rst_ni);
  axi_lite_bfm host(.clk_i,.axi);
  axi_lite_uart #(.CLOCK_HZ(1000000),.BAUD(100000)) dut(.clk_i,.rst_ni,.tx_o(tx),.irq_o(irq),.s_axi(axi));
  byte received;
  initial begin
    repeat(5)@(negedge clk_i);rst_ni=1;repeat(2)@(negedge clk_i);
    assert(!irq&&tx)else $fatal(1,"UART IRQ asserted at idle/reset");
    host.write('h30000008,1);
    fork
      host.write('h30000000,'hA6);
      begin
        @(negedge tx);repeat(15)@(negedge clk_i);
        for(int b=0;b<8;b++)begin received[b]=tx;repeat(10)@(negedge clk_i);end
        assert(tx&&received=='hA6)else $fatal(1,"UART waveform %h",received);
      end
    join
    repeat(15)@(negedge clk_i);assert(irq)else $fatal(1,"UART completion IRQ missing");
    host.write('h3000000c,1);assert(!irq)else $fatal(1,"UART W1C failed");
    $display("TEST_PASS: UART 8N1 waveform and completion enable/W1C");$finish;
  end
  initial begin #50000;$fatal(1,"UART timeout");end
endmodule
