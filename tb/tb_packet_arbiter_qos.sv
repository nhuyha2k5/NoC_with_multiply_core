`timescale 1ns/1ps

module tb_packet_arbiter_qos;
  logic clk_i = 1'b0;
  logic rst_ni = 1'b0;
  logic [2:0] request_i, priority_i, tail_i, grant_o;
  always #5 clk_i = ~clk_i;

  packet_arbiter #(.N(3), .AGE_LIMIT(3)) dut (
    .clk_i, .rst_ni, .request_i, .priority_i, .tail_i, .grant_o
  );

  initial begin
    request_i = '0;
    priority_i = '0;
    tail_i = '1;
    repeat (3) @(posedge clk_i);
    rst_ni = 1'b1;

    // A high-priority response wins over an ordinary request.
    @(negedge clk_i);
    request_i = 3'b011;
    priority_i = 3'b010;
    #1;
    assert (grant_o == 3'b010) else $fatal(1, "QoS priority selection failed");

    // Packet lock prevents a priority packet from preempting a wormhole packet.
    @(negedge clk_i);
    request_i = 3'b001;
    priority_i = 3'b000;
    tail_i = 3'b000;
    #1;
    assert (grant_o == 3'b001) else $fatal(1, "Initial packet was not granted");
    @(posedge clk_i);
    @(negedge clk_i);
    request_i = 3'b011;
    priority_i = 3'b010;
    tail_i = 3'b010;
    #1;
    assert (grant_o == 3'b001) else $fatal(1, "Priority traffic broke packet lock");
    tail_i[0] = 1'b1;
    @(posedge clk_i);

    // Sustained high priority traffic must not starve the normal request.
    @(negedge clk_i);
    request_i = 3'b011;
    priority_i = 3'b010;
    tail_i = 3'b111;
    begin
      bit saw_low;
      saw_low = 0;
      repeat (8) begin
        #1;
        if (grant_o[0]) saw_low = 1;
        @(posedge clk_i);
        @(negedge clk_i);
      end
      assert (saw_low) else $fatal(1, "Aged normal traffic was starved");
    end

    $display("TEST_PASS: packet lock, response priority and anti-starvation aging");
    $finish;
  end
endmodule
