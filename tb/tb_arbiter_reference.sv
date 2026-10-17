`timescale 1ns/1ps
// Check optimized hardware selection against an independent circular scan.
// The reference also models credit stalls: request_i is sometimes forced to
// zero while waiting_i still marks inputs holding a flit, and the aging enable
// toggles every 1000 cycles.
module tb_arbiter_reference;
  logic clk_i=0,rst_ni=0,accept_i=0,aging_en_i=1;
  logic[4:0] request_i=0,waiting_i=0,priority_i=0,tail_i=0;wire[4:0]grant_o;
  int rr=0,owner=0,age[5];bit locked=0;
  int stall_cycles=0,aged_grants=0;
  logic[31:0] rng=32'h23456789;
  logic[4:0] expected,held;int selected;bit found;
  always #5 clk_i=~clk_i;
  packet_arbiter #(.N(5),.AGE_LIMIT(7)) dut(.clk_i,.rst_ni,.accept_i,.aging_en_i,.request_i,
    .waiting_i,.priority_i,.tail_i,.grant_o);
  function automatic logic[31:0] random_word();rng=rng*32'd1664525+32'd1013904223;return rng;endfunction
  initial begin
    for(int i=0;i<5;i++)age[i]=0;
    repeat(5)@(negedge clk_i);rst_ni=1;
    for(int t=0;t<20000;t++)begin
      @(negedge clk_i);
      if(t%1000==0)aging_en_i=(t/1000)%3!=2;
      held=5'(random_word()>>8);
      // One cycle in four models a shared credit stall: nothing is grantable,
      // but inputs holding a flit are still waiting.
      if((random_word()>>20)%4==0)begin request_i=0;stall_cycles++;end
      else request_i=held;
      waiting_i=held|5'(random_word()>>3);
      priority_i=5'(random_word()>>16);
      tail_i=5'(random_word()>>24);accept_i=1'(random_word()>>17);
      expected=0;found=0;selected=0;
      if(locked)begin if(request_i[owner])begin expected[owner]=1;found=1;selected=owner;end end
      else begin
        for(int pass=0;pass<2;pass++)for(int offset=0;offset<5;offset++)begin
          int idx;idx=(rr+offset)%5;
          if(!found && request_i[idx] && (pass==1 || priority_i[idx] || (aging_en_i && age[idx]>=7)))begin
            expected[idx]=1;found=1;selected=idx;
            if(pass==0 && !priority_i[idx])aged_grants++;
          end
        end
      end
      #1;assert(grant_o==expected)else $fatal(1,"Arbiter reference mismatch t=%0d req=%b wait=%b priority=%b aging=%b actual=%b expected=%b",
        t,request_i,waiting_i,priority_i,aging_en_i,grant_o,expected);
      @(posedge clk_i);
      if(found && accept_i)begin
        if(tail_i[selected])begin locked=0;rr=(selected+1)%5;end
        else if(!locked)begin locked=1;owner=selected;end
      end
      for(int i=0;i<5;i++)begin
        bit pending;pending=request_i[i]||waiting_i[i];
        if(!pending || (found && accept_i && expected[i]))age[i]=0;
        else if(age[i]<7)age[i]++;
      end
    end
    assert(stall_cycles>4000 && aged_grants>100)else $fatal(1,"Reference stimulus too weak stalls=%0d aged=%0d",stall_cycles,aged_grants);
    $display("TEST_PASS: optimized arbiter matches circular reference for 20000 random cycles with credit stalls (%0d), locks, aging (%0d aged grants) and aging disable",stall_cycles,aged_grants);$finish;
  end
endmodule
