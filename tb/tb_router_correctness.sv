`timescale 1ns/1ps
module tb_router_correctness;
  import router_pkg::*;
  logic clk_i=0,rst_ni=0;
  logic push=0,pop=0;logic[7:0] data=0;
  wire[7:0] front;wire empty,full;wire[2:0] count;
  logic[33:0] in_flit[5];logic in_valid[5],in_vc[5];wire[1:0] in_credit[5];
  wire[33:0] out_flit[5];wire out_valid[5],out_vc[5];logic[1:0] out_credit[5];
  int requests=0,responses=0;
  always #5 clk_i=~clk_i;
  vc_fifo #(.WIDTH(8),.DEPTH(4)) fifo(.clk_i,.rst_ni,.push_i(push),.pop_i(pop),.data_i(data),.data_o(front),.empty_o(empty),.full_o(full),.count_o(count));
  router_vc router(.clk_i,.rst_ni,.in_flit_i(in_flit),.in_valid_i(in_valid),.in_vc_i(in_vc),
    .in_credit_o(in_credit),.out_flit_o(out_flit),.out_valid_o(out_valid),.out_vc_o(out_vc),.out_credit_i(out_credit));
  function automatic logic[33:0] header(input logic[1:0]kind,input int id);
    return {kind,2'b0,2'b0,2'b0,2'b0,3'b0,4'b0,17'(id)};
  endfunction
  task automatic send(input int port,input bit vc,input logic[33:0]flit);
    @(negedge clk_i);in_valid[port]=1;in_vc[port]=vc;in_flit[port]=flit;
    @(negedge clk_i);in_valid[port]=0;
  endtask
  always @(posedge clk_i)if(rst_ni && out_valid[0])begin
    if(out_vc[0])begin
      assert(out_flit[0]==header(FLIT_HEADTAIL,77))else $fatal(1,"Response corruption");responses++;
    end else begin
      case(requests)
        0:assert(out_flit[0]==header(FLIT_HEAD,11))else $fatal(1,"Request header");
        1,2,3,4:assert(out_flit[0]=={FLIT_BODY,32'(requests)})else $fatal(1,"Request body order");
        5:assert(out_flit[0]=={FLIT_TAIL,32'd5})else $fatal(1,"Request tail");
        6:assert(out_flit[0]==header(FLIT_HEADTAIL,88))else $fatal(1,"VC packet ownership violated");
        default:$fatal(1,"Unexpected request");
      endcase
      requests++;
    end
  end
  initial begin
    for(int p=0;p<5;p++)begin in_valid[p]=0;in_vc[p]=0;in_flit[p]=0;out_credit[p]=0;end
    repeat(5)@(negedge clk_i);rst_ni=1;
    // Full FIFO pop and push on the same edge must preserve the new word.
    for(int i=0;i<4;i++)begin @(negedge clk_i);push=1;data=8'(i);end
    @(negedge clk_i);assert(full && front==0)else $fatal(1,"FIFO fill");pop=1;data=4;
    @(negedge clk_i);push=0;assert(full && count==4 && front==1)else $fatal(1,"Full simultaneous push/pop lost word");
    for(int i=1;i<=4;i++)begin assert(front==i)else $fatal(1,"FIFO ordering");@(negedge clk_i);end
    pop=0;assert(empty)else $fatal(1,"FIFO drain");
    // Exhaust all four downstream VC0 credits before finishing its packet.
    send(0,0,header(FLIT_HEAD,11));
    for(int i=1;i<=4;i++)send(0,0,{FLIT_BODY,32'(i)});
    send(0,0,{FLIT_TAIL,32'd5});
    assert(requests==4)else $fatal(1,"Expected credit stall");
    send(1,0,header(FLIT_HEADTAIL,88));
    send(1,1,header(FLIT_HEADTAIL,77));
    repeat(8)@(negedge clk_i);
    assert(responses==1 && requests==4)else $fatal(1,"VC1 could not bypass credit-stalled VC0");
    // Return only the four credits actually consumed, then drain.
    for(int i=0;i<4;i++)begin @(negedge clk_i);out_credit[0][0]=1;end
    @(negedge clk_i);out_credit[0][0]=0;
    repeat(8)@(negedge clk_i);
    assert(requests==7 && responses==1)else $fatal(1,"Router recovery failed");
    $display("TEST_PASS: FIFO full pop/push, VC bypass under credit stall, same-VC wormhole ownership");$finish;
  end
  initial begin #100000;$fatal(1,"Router correctness timeout");end
endmodule
