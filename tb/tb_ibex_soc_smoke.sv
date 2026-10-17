`timescale 1ns/1ps

module tb_ibex_soc_smoke;
  logic clk_i = 1'b0;
  logic rst_ni = 1'b0;
  logic [7:0] gpio_i = 8'h00;
  logic [7:0] gpio_o;
  logic [7:0] gpio_oe_o;
  logic uart_tx_o;
  logic [31:0] debug_pc0_o;
  logic [31:0] debug_pc1_o;
  logic [31:0] cache0_hits_o;
  logic [31:0] cache0_misses_o;
  logic [31:0] cache1_hits_o;
  logic [31:0] cache1_misses_o;

  always #10 clk_i = ~clk_i;

  ibex_mesh_soc #(.CLOCK_HZ(50_000_000)) dut (
    .clk_i,
    .rst_ni,
    .gpio_i,
    .gpio_o,
    .gpio_oe_o,
    .uart_tx_o,
    .debug_pc0_o,
    .debug_pc1_o,
    .cache0_hits_o,
    .cache0_misses_o,
    .cache1_hits_o,
    .cache1_misses_o
  );

  initial begin
    repeat (5) @(posedge clk_i);
    rst_ni <= 1'b1;

    // Empty ROMs contain NOPs. Both real Ibex instances must leave the
    // reset vector and continue fetching independently.
    repeat (100) @(posedge clk_i);
    assert (debug_pc0_o > 32'h0000_0080)
      else $fatal(1, "Ibex hart 0 did not advance: pc=%08x", debug_pc0_o);
    assert (debug_pc1_o > 32'h0000_0080)
      else $fatal(1, "Ibex hart 1 did not advance: pc=%08x", debug_pc1_o);
    assert (!$isunknown({debug_pc0_o, debug_pc1_o, uart_tx_o, gpio_o, gpio_oe_o,
                         cache0_hits_o, cache0_misses_o,
                         cache1_hits_o, cache1_misses_o}))
      else $fatal(1, "Unknown value observed at SoC outputs");

    $display("TEST_PASS: two Ibex cores booted in the AXI/VC 3x3 NoC SoC (pc0=%08x pc1=%08x)",
             debug_pc0_o, debug_pc1_o);
    $finish;
  end

  initial begin
    #10000;
    $fatal(1, "Timeout waiting for the two Ibex cores");
  end
endmodule
