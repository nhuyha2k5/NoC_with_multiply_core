`timescale 1ns/1ps
// Router-level anti-starvation check under credit backpressure.
// A high-class input (NORTH) streams single-flit packets to LOCAL while a
// low-class input (SOUTH) holds one packet for the same output VC. The local
// sink drains one flit every SINK_PERIOD cycles, so the output VC credit falls
// to zero after nearly every flit. Aging must keep counting while the low-class
// packet waits for credit; otherwise it is starved for as long as the
// high-class stream lasts.
module tb_router_starvation;
  import router_pkg::*;
  localparam int SINK_PERIOD=4;
  localparam int FIFO_DEPTH=4;
  logic clk_i=0,rst_ni=0;
  always #5 clk_i=~clk_i;
  logic [1:0] qos_mode=1;
  logic qos_classes=1;
  logic qos_aging=1;
  logic [3:0] qos_age=4;
  logic [33:0] in_flit[0:4];
  logic in_valid[0:4],in_vc[0:4];
  wire [1:0] in_credit[0:4];
  wire [33:0] out_flit[0:4];
  wire out_valid[0:4],out_vc[0:4];
  logic [1:0] out_credit[0:4];
  int sender_credit[0:4];
  int sink_count,sink_timer,cycle,low_sent_cycle,low_seen_cycle,high_seen;
  bit high_on,low_pending,low_seen;
  logic [3:0] high_id;

  router_vc #(.CURRENT_X(1),.CURRENT_Y(1),.FIFO_DEPTH(FIFO_DEPTH)) dut(
    .clk_i,.rst_ni,.qos_mode_i(qos_mode),.qos_classes_i(qos_classes),
    .qos_aging_i(qos_aging),.qos_age_i(qos_age),.qos_weights_i(8'h31),
    .counters_enable_i(1'b0),.counters_clear_i(1'b0),
    .flit_count_o(),.packet_count_o(),.stall_count_o(),.fifo_peak_o(),
    .in_flit_i(in_flit),.in_valid_i(in_valid),.in_vc_i(in_vc),.in_credit_o(in_credit),
    .out_flit_o(out_flit),.out_valid_o(out_valid),.out_vc_o(out_vc),.out_credit_i(out_credit));

  function automatic logic [33:0] packet(input logic [3:0] id,input logic [1:0] traffic_class);
    logic [33:0] h;
    h=make_head(1,1,1,0,NOC_READ_REQ,15);
    h[33:32]=FLIT_HEADTAIL;h[14:11]=id;h[2:1]=traffic_class;
    return h;
  endfunction

  // Credit-respecting sources: NORTH streams class 3, SOUTH sends one class 0.
  always @(posedge clk_i) begin
    if(!rst_ni) begin
      for(int p=0;p<5;p++) sender_credit[p]=FIFO_DEPTH;
    end else begin
      for(int p=0;p<5;p++) begin
        if(in_valid[p]) sender_credit[p]--;
        if(in_credit[p][0]) sender_credit[p]++;
        assert(sender_credit[p]>=0 && sender_credit[p]<=FIFO_DEPTH)
          else $fatal(1,"Sender credit out of range p=%0d",p);
      end
    end
  end
  always @(negedge clk_i) begin
    for(int p=0;p<5;p++) begin in_valid[p]=0;in_vc[p]=0;in_flit[p]='0;end
    if(rst_ni && high_on && sender_credit[PORT_NORTH]>0) begin
      in_valid[PORT_NORTH]=1;in_flit[PORT_NORTH]=packet(high_id,2'd3);high_id=(high_id==4'd9)?4'd1:high_id+1'b1;
    end
    if(rst_ni && low_pending && sender_credit[PORT_SOUTH]>0) begin
      in_valid[PORT_SOUTH]=1;in_flit[PORT_SOUTH]=packet(4'hA,2'd0);low_pending=0;low_sent_cycle=cycle;
    end
  end

  // Slow local sink: one flit consumed (and one credit returned) per period.
  always @(posedge clk_i) begin
    for(int p=0;p<5;p++) out_credit[p]<=0;
    if(!rst_ni) begin sink_count=0;sink_timer=0;cycle=0; end
    else begin
      cycle++;
      if(out_valid[PORT_LOCAL]) begin
        assert(out_vc[PORT_LOCAL]==0) else $fatal(1,"Unexpected VC on local output");
        sink_count++;
        assert(sink_count<=FIFO_DEPTH) else $fatal(1,"Sink overflow: router sent without credit");
        if(out_flit[PORT_LOCAL][14:11]==4'hA) begin low_seen=1;low_seen_cycle=cycle;end
        else high_seen++;
      end
      if(++sink_timer==SINK_PERIOD) begin
        sink_timer=0;
        if(sink_count>0) begin sink_count--;out_credit[PORT_LOCAL]<=2'b01; end
      end
    end
  end

  task automatic run_case(input bit aging,input int window,output bit served,output int wait_cycles);
    @(negedge clk_i);rst_ni=0;qos_aging=aging;high_on=0;low_pending=0;low_seen=0;high_seen=0;high_id=1;
    repeat(3)@(negedge clk_i);rst_ni=1;
    // Saturate the output with high-class traffic before the low packet arrives.
    high_on=1;repeat(40)@(negedge clk_i);
    low_pending=1;
    repeat(window)@(negedge clk_i);
    served=low_seen;wait_cycles=low_seen?low_seen_cycle-low_sent_cycle:-1;
    high_on=0;
  endtask

  initial begin
    bit served;int wait_cycles;
    for(int p=0;p<5;p++) begin in_flit[p]='0;in_valid[p]=0;in_vc[p]=0;out_credit[p]=0;end
    // 1) Aging enabled: low-class packet must win within a bounded time even
    //    though the output credit drops to zero after almost every flit.
    run_case(1'b1,400,served,wait_cycles);
    assert(served) else $fatal(1,"Low-class packet starved under credit backpressure (aging on)");
    assert(wait_cycles<=8*SINK_PERIOD*(qos_age+1))
      else $fatal(1,"Low-class wait %0d cycles exceeds aging bound",wait_cycles);
    assert(high_seen>20) else $fatal(1,"High-class stream did not saturate the output");
    $display("STARVATION aging=1 low_wait_cycles=%0d high_packets=%0d",wait_cycles,high_seen);
    // 2) Aging disabled through the new policy bit: strict class priority is
    //    expected to starve the low class (the A/B baseline for aging).
    run_case(1'b0,400,served,wait_cycles);
    assert(!served) else $fatal(1,"Aging disable bit had no effect");
    $display("STARVATION aging=0 low_served=%0d high_packets=%0d",served,high_seen);
    $display("TEST_PASS: router aging survives credit stalls; aging disable gives strict class priority");
    $finish;
  end
  initial begin #200000;$fatal(1,"Starvation test timeout");end
endmodule
