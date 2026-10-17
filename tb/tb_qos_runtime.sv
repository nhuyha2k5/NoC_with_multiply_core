`timescale 1ns/1ps
module tb_qos_runtime;
  import router_pkg::*;
  logic clk_i=0,rst_ni=0;
  always #5 clk_i=~clk_i;
  logic [1:0] qos_mode=1;
  logic qos_classes=1;
  logic [3:0] qos_age=4;
  logic [7:0] qos_weights=8'h31;
  logic counters_enable=1,counters_clear=0;
  logic return_credit=1;
  logic [33:0] in_flit[0:4];
  logic in_valid[0:4],in_vc[0:4];
  wire [1:0] in_credit[0:4];
  wire [33:0] out_flit[0:4];
  wire out_valid[0:4],out_vc[0:4];
  logic [1:0] out_credit[0:4];
  wire [159:0] flits,packets,stalls;
  wire [39:0] peaks;
  int n_out=0;
  int seen[0:15];
  router_vc #(.CURRENT_X(1),.CURRENT_Y(1)) dut(
    .clk_i,.rst_ni,.qos_mode_i(qos_mode),.qos_classes_i(qos_classes),
    .qos_age_i(qos_age),.qos_weights_i(qos_weights),
    .counters_enable_i(counters_enable),.counters_clear_i(counters_clear),
    .flit_count_o(flits),.packet_count_o(packets),.stall_count_o(stalls),.fifo_peak_o(peaks),
    .in_flit_i(in_flit),.in_valid_i(in_valid),.in_vc_i(in_vc),.in_credit_o(in_credit),
    .out_flit_o(out_flit),.out_valid_o(out_valid),.out_vc_o(out_vc),.out_credit_i(out_credit));
  function automatic logic [33:0] head(input int id,input int traffic_class);
    logic [33:0] h;
    h=make_head(1,1,0,0,NOC_READ_REQ,15);
    h[33:32]=FLIT_HEADTAIL;
    h[14:11]=4'(id);
    h[2:1]=2'(traffic_class);
    return h;
  endfunction
  always @(posedge clk_i)begin
    for(int p=0;p<5;p++)out_credit[p]<=0;
    if(rst_ni&&out_valid[0])begin
      assert(n_out<16)else $fatal(1,"Unexpected QoS output");
      seen[n_out]=out_flit[0][14:11];n_out++;
      if(return_credit)out_credit[0][out_vc[0]]<=1;
    end
  end
  task automatic reset_case;
    @(negedge clk_i);rst_ni=0;
    for(int p=0;p<5;p++)begin in_flit[p]=0;in_valid[p]=0;in_vc[p]=0;out_credit[p]=0;end
    n_out=0;
    repeat(3)@(negedge clk_i);
    rst_ni=1;
  endtask
  task automatic pair(input int lo,input int hi,input bit split_vc);
    @(negedge clk_i);
    in_valid[1]=1;in_vc[1]=0;in_flit[1]=head(lo,0);
    in_valid[2]=1;in_vc[2]=split_vc;in_flit[2]=head(hi,3);
    @(negedge clk_i);in_valid[1]=0;in_valid[2]=0;
  endtask
  task automatic await_count(input int wanted);
    for(int t=0;t<30;t++)begin
      @(negedge clk_i);
      if(n_out==wanted)return;
    end
    $fatal(1,"QoS router timed out wanted=%0d got=%0d",wanted,n_out);
  endtask
  initial begin
    for(int p=0;p<5;p++)begin in_flit[p]=0;in_valid[p]=0;in_vc[p]=0;out_credit[p]=0;end
    reset_case();
    // Same VC, simultaneous contenders: configured class decides ahead of RR cursor.
    qos_mode=1;qos_classes=1;
    pair(1,2,0);await_count(2);
    assert(seen[0]==2&&seen[1]==1)else $fatal(1,"Traffic class did not override input RR");
    assert(flits[31:0]==2&&packets[31:0]==2)else $fatal(1,"QoS counters wrong");
    assert(peaks[15:8]>=1&&peaks[23:16]>=1)else $fatal(1,"Input FIFO peak missing");
    // Disabling class restores RR order under the same initial state.
    reset_case();qos_classes=0;
    pair(1,2,0);await_count(2);
    assert(seen[0]==1&&seen[1]==2)else $fatal(1,"Class disable did not restore RR");
    // Link weights of VC0=1, VC1=3 should choose one VC0 then three VC1.
    reset_case();qos_mode=2;qos_classes=0;qos_weights=8'h31;
    for(int i=0;i<4;i++)begin
      @(negedge clk_i);
      in_valid[1]=1;in_vc[1]=0;in_flit[1]=head(i,0);
      in_valid[2]=1;in_vc[2]=1;in_flit[2]=head(8+i,0);
    end
    @(negedge clk_i);in_valid[1]=0;in_valid[2]=0;
    await_count(8);
    assert(seen[0]<8&&seen[1]>=8&&seen[2]>=8&&seen[3]>=8)
      else $fatal(1,"VC weighted schedule wrong: %0d,%0d,%0d,%0d",seen[0],seen[1],seen[2],seen[3]);
    assert(flits[31:0]==8&&packets[31:0]==8)else $fatal(1,"Weighted counters wrong");
    // Withholding all downstream returns must register a real credit stall.
    reset_case();qos_mode=0;return_credit=0;
    for(int i=0;i<5;i++)begin
      @(negedge clk_i);in_valid[1]=1;in_vc[1]=0;in_flit[1]=head(i,0);
    end
    @(negedge clk_i);in_valid[1]=0;
    repeat(5)@(negedge clk_i);
    assert(n_out==4&&stalls[31:0]>0)else $fatal(1,"Credit stall counter missing");
    @(negedge clk_i);counters_clear=1;
    @(negedge clk_i);counters_clear=0;
    assert(flits[31:0]==0&&packets[31:0]==0&&peaks[7:0]==0)
      else $fatal(1,"QoS counter clear failed");
    $display("TEST_PASS: runtime traffic classes, RR disable, weighted VC scheduling, counters/clear");
    $finish;
  end
  initial begin #100000;$fatal(1,"QoS runtime timeout");end
endmodule
