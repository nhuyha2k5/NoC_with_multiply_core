`timescale 1ns/1ps
// 4-hart interrupt block (axi_lite_interrupts HARTS=4, SOURCES=16, CLINT map):
//  PLIC: 16 sources x 4 contexts (context c = hart c), register offsets and
//        DECERR edges, per-context enable/threshold, claim/complete ownership,
//        4-way race on one source, all contexts claiming at once, 16-source
//        priority order with ID tie-break, reset in flight;
//  CLINT: msip/mtimecmp per hart, mtime, 64-bit compare across the 32-bit
//        boundary, byte strobes, reserved offsets, old timer map removed;
//  MEIP + MTIP + MSIP on all four harts at once.
module tb_interrupts_4hart;
  localparam int HARTS = 4;
  localparam int SOURCES = 16;
  logic clk_i=0,rst_ni=0;
  always #5 clk_i=~clk_i;
  axi_lite_if axi(clk_i,rst_ni);
  axi_lite_bfm host(.clk_i,.axi);
  logic [SOURCES:1] sources=0;
  logic [HARTS-1:0] ext,timer,ipi;
  logic [31:0] d,lo,hi0,hi1;
  int checks=0;
  axi_lite_interrupts #(.HARTS(HARTS),.SOURCES(SOURCES),.LEGACY_TIMER(1'b0)) dut(
    .clk_i,.rst_ni,.sources_i(sources),.external_irq_o(ext),.timer_irq_o(timer),
    .software_irq_o(ipi),.s_axi(axi));

  localparam logic [31:0] PLIC='h0c000000, PENDING='h0c001000, CLINT='h02000000;
  function automatic logic [31:0] prio(input int id);return PLIC+4*id;endfunction
  function automatic logic [31:0] enable(input int ctx);return 'h0c002000+ctx*'h80;endfunction
  function automatic logic [31:0] thresh(input int ctx);return 'h0c200000+ctx*'h1000;endfunction
  function automatic logic [31:0] claim_addr(input int ctx);return 'h0c200004+ctx*'h1000;endfunction
  function automatic logic [31:0] msip(input int h);return CLINT+4*h;endfunction
  function automatic logic [31:0] mtimecmp(input int h);return CLINT+'h4000+8*h;endfunction
  localparam logic [31:0] MTIME=CLINT+'hbff8;
  task automatic settle;repeat(3)@(negedge clk_i);endtask
  task automatic expect_claim(input int ctx,input int id,input string what);
    host.read(claim_addr(ctx),d);checks++;
    assert(d==id)else $fatal(1,"%s: ctx%0d claim got %0d expected %0d",what,ctx,d,id);
  endtask
  task automatic complete(input int ctx,input int id,input logic[3:0] strb=15);
    host.write(claim_addr(ctx),id,strb);
  endtask
  task automatic expect_ext(input logic [HARTS-1:0] value,input string what);
    settle;checks++;assert(ext==value)else $fatal(1,"%s: ext=%b expected %b",what,ext,value);
  endtask
  task automatic plic_clean;
    sources=0;
    for(int c=0;c<HARTS;c++)begin host.write(enable(c),0);host.write(thresh(c),0);end
    for(int s=1;s<=SOURCES;s++)host.write(prio(s),0);
  endtask

  initial begin
    repeat(5)@(negedge clk_i);rst_ni=1;

    // ---- Reset values and register map edges ----
    for(int c=0;c<HARTS;c++)begin
      host.read(enable(c),d);assert(d==0)else $fatal(1,"Enable ctx%0d reset",c);
      host.read(thresh(c),d);assert(d==0)else $fatal(1,"Threshold ctx%0d reset",c);
      host.read(claim_addr(c),d);assert(d==0)else $fatal(1,"Claim ctx%0d reset",c);
      host.read(msip(c),d);assert(d==0)else $fatal(1,"MSIP hart%0d reset",c);
      host.read(mtimecmp(c),lo);host.read(mtimecmp(c)+4,hi0);
      assert(lo==32'hffffffff && hi0==32'hffffffff)else $fatal(1,"mtimecmp hart%0d reset",c);
    end
    assert(ext==0 && timer==0 && ipi==0)else $fatal(1,"Interrupt outputs after reset");
    host.read(prio(16),d);host.write(prio(16),7);host.read(prio(16),d);
    assert(d==7)else $fatal(1,"Source 16 priority");
    host.read(prio(17),d,3);host.write(prio(17),1,15,3);host.read(PLIC,d,3);
    host.read('h0c002200,d,3);host.write('h0c002200,1,15,3);     // enable of context 4
    host.read('h0c204000,d,3);host.read('h0c204004,d,3);          // context 4 threshold/claim
    host.read('h0c002004,d,3);host.write('h0c200008,1,15,3);
    host.read('h30002000,d,3);host.write('h30002020,1,15,3);      // legacy timer map is gone
    host.read(msip(4),d,3);host.read(mtimecmp(4),d,3);host.read(CLINT+'hbff0,d,3);
    host.read(CLINT+2,d,3);host.write(CLINT+'h8000,1,15,3);host.read(CLINT+'hc000,d,3);
    host.read('h30006000,d);assert(d==32'h4e4f4303)else $fatal(1,"NoC control ID");
    plic_clean;

    // ---- Every context sees only its enabled sources (16 sources, 4 groups) ----
    for(int s=1;s<=SOURCES;s++)host.write(prio(s),1+(s%7));
    for(int c=0;c<HARTS;c++)host.write(enable(c),32'hf<<(1+4*c));
    for(int c=0;c<HARTS;c++)begin
      // Pending is latched until claimed, so earlier contexts stay asserted.
      sources=0;sources[1+4*c]=1;
      expect_ext(4'hf>>(3-c),"Source routed to its context only");
    end
    sources='1;expect_ext(4'hf,"All contexts interrupted");
    host.read(PENDING,d);assert(d==32'h1fffe)else $fatal(1,"Pending of 16 sources: %h",d);
    // Each context claims its four sources in priority order (ties: lowest ID).
    for(int c=0;c<HARTS;c++)begin
      bit taken[4];
      for(int k=0;k<4;k++)taken[k]=0;
      for(int k=0;k<4;k++)begin
        int best;best=-1;
        // Highest priority first; equal priorities go to the lowest ID.
        for(int j=0;j<4;j++)
          if(!taken[j] && (best<0 || 1+((1+4*c+j)%7) > 1+((1+4*c+best)%7)))best=j;
        taken[best]=1;
        expect_claim(c,1+4*c+best,"Per-context priority order");
      end
      expect_claim(c,0,"Context drained");
    end
    expect_ext(0,"No IRQ with every source in flight");
    sources=0;
    for(int c=0;c<HARTS;c++)for(int k=0;k<4;k++)complete(c,1+4*c+k);
    expect_ext(0,"Stale IRQ after drain");
    plic_clean;

    // ---- Per-context threshold ----
    host.write(prio(11),4);for(int c=0;c<HARTS;c++)host.write(enable(c),1<<11);
    host.write(thresh(0),4);host.write(thresh(1),3);host.write(thresh(2),7);host.write(thresh(3),0);
    sources[11]=1;expect_ext(4'b1010,"Threshold equal/above masks, below unmasks");
    host.read(thresh(2),d);assert(d==7)else $fatal(1,"Threshold readback");
    // ---- 4-way race on one source: one winner, the rest read 0 ----
    for(int c=0;c<HARTS;c++)host.write(thresh(c),0);
    expect_ext(4'hf,"Shared source to all four contexts");
    expect_claim(2,11,"Context 2 wins the race");
    expect_ext(0,"Losers drop the IRQ after the claim");
    for(int c=0;c<HARTS;c++)if(c!=2)expect_claim(c,0,"Loser context gets 0");
    for(int c=0;c<HARTS;c++)if(c!=2)complete(c,11);
    sources[11]=0;expect_ext(0,"Non-owner completion ignored");
    sources[11]=1;expect_ext(0,"Source still in flight for the owner");
    sources[11]=0;complete(2,11);expect_ext(0,"Owner completion with level low");
    plic_clean;

    // ---- All contexts claim different sources at the same time ----
    host.write(prio(3),2);host.write(prio(9),5);host.write(prio(10),6);host.write(prio(16),1);
    host.write(enable(0),1<<3);host.write(enable(1),1<<9);host.write(enable(2),1<<10);host.write(enable(3),1<<16);
    sources[3]=1;sources[9]=1;sources[10]=1;sources[16]=1;expect_ext(4'hf,"Four independent IRQs");
    expect_claim(3,16,"Context 3");expect_claim(1,9,"Context 1");
    expect_claim(0,3,"Context 0");expect_claim(2,10,"Context 2");
    sources=0;complete(0,3);complete(1,9);complete(2,10);complete(3,16);
    expect_ext(0,"All completed");
    // Wrong-strobe and out-of-range completions are ignored.
    sources[9]=1;settle;expect_claim(1,9,"Claim for strobe test");
    complete(1,9,4'b0001);complete(1,17);complete(1,0);sources[9]=0;
    sources[9]=1;expect_ext(0,"Partial/out-of-range completion accepted");
    sources[9]=0;complete(1,9);expect_ext(0,"Valid completion with level low");
    plic_clean;

    // ---- CLINT: MSIP per hart ----
    for(int h=0;h<HARTS;h++)begin
      host.write(msip(h),32'hffffffff);host.read(msip(h),d);
      assert(d==1 && ipi==(4'hf>>(3-h)))else $fatal(1,"MSIP hart%0d: d=%h ipi=%b",h,d,ipi);
    end
    for(int h=0;h<HARTS;h++)begin
      host.write(msip(h),0);
      assert(ipi==(4'hf<<(h+1)))else $fatal(1,"Clearing MSIP hart%0d disturbed others: %b",h,ipi);
    end
    host.write(msip(1),1,4'b0000);assert(ipi==0)else $fatal(1,"Zero-strobe MSIP write took effect");
    // ---- CLINT: per-hart compare ----
    for(int h=0;h<HARTS;h++)begin host.write(mtimecmp(h),0);host.write(mtimecmp(h)+4,0);end
    settle;assert(timer==4'hf)else $fatal(1,"MTIP with mtimecmp=0: %b",timer);
    for(int h=0;h<HARTS;h++)begin
      host.write(mtimecmp(h)+4,32'hffffffff);settle;
      assert(timer==(4'hf<<(h+1)))else $fatal(1,"Masking hart%0d compare disturbed others: %b",h,timer);
    end
    // Byte strobes on mtimecmp.
    host.write(mtimecmp(2),32'h11223344);host.write(mtimecmp(2),32'haabbccdd,4'b0100);
    host.read(mtimecmp(2),d);assert(d==32'h11bb3344)else $fatal(1,"mtimecmp byte strobe: %h",d);
    // 64-bit compare across the 32-bit boundary; safe hi/lo/hi read.
    host.write(mtimecmp(3)+4,32'hffffffff);host.write(mtimecmp(3),5);host.write(mtimecmp(3)+4,1);
    host.write(MTIME+4,0);host.write(MTIME,32'hffffff80);
    assert(timer[3]==0)else $fatal(1,"Timer fired before 64-bit compare");
    begin
      int waited=0;
      while(!timer[3])begin @(negedge clk_i);waited++;assert(waited<400)else $fatal(1,"64-bit compare never fired");end
    end
    do begin host.read(MTIME+4,hi0);host.read(MTIME,lo);host.read(MTIME+4,hi1);end while(hi0!=hi1);
    assert(hi1==1 && lo>=5)else $fatal(1,"mtime carry wrong: %h_%h",hi1,lo);
    assert(timer==4'b1000)else $fatal(1,"Only hart3 compare should match: %b",timer);
    // Rearm: moving compare ahead clears MTIP.
    host.write(mtimecmp(3)+4,32'hffffffff);host.write(mtimecmp(3),lo+1000);host.write(mtimecmp(3)+4,hi1);
    settle;assert(timer==0)else $fatal(1,"Rearm did not clear MTIP");

    // ---- MEIP, MTIP and MSIP together on all four harts ----
    host.write(prio(5),1);for(int c=0;c<HARTS;c++)host.write(enable(c),1<<5);sources[5]=1;
    for(int h=0;h<HARTS;h++)begin host.write(mtimecmp(h),0);host.write(mtimecmp(h)+4,0);host.write(msip(h),1);end
    settle;
    assert(ext==4'hf&&timer==4'hf&&ipi==4'hf)else $fatal(1,"Concurrent MEIP/MTIP/MSIP ext=%b timer=%b ipi=%b",ext,timer,ipi);
    host.write(msip(2),0);host.write(mtimecmp(1)+4,32'hffffffff);settle;
    assert(ipi==4'b1011 && timer==4'b1101 && ext==4'hf)else $fatal(1,"Selective clear disturbed others");
    sources[5]=0;expect_claim(3,5,"MEIP claim with other IRQs pending");complete(3,5);

    // ---- Reset in flight clears PLIC and CLINT state ----
    sources[7]=1;host.write(prio(7),3);host.write(enable(1),1<<7);settle;expect_claim(1,7,"Pre-reset claim");
    @(negedge clk_i);rst_ni=0;sources=0;repeat(3)@(negedge clk_i);rst_ni=1;settle;
    assert(ext==0&&timer==0&&ipi==0)else $fatal(1,"Outputs not cleared by reset");
    host.read(PENDING,d);assert(d==0)else $fatal(1,"Pending survived reset");
    host.read(enable(1),d);assert(d==0)else $fatal(1,"Enable survived reset");
    host.read(mtimecmp(0)+4,d);assert(d==32'hffffffff)else $fatal(1,"mtimecmp survived reset");
    host.read(msip(0),d);assert(d==0)else $fatal(1,"MSIP survived reset");
    host.write(prio(7),3);host.write(enable(1),1<<7);sources[7]=1;expect_ext(4'b0010,"Post-reset IRQ");
    expect_claim(1,7,"Post-reset claim (in-flight cleared by reset)");sources[7]=0;complete(1,7);
    $display("TEST_PASS: 4-hart interrupts (%0d claim/IRQ checks): PLIC 16 sources x 4 contexts, offsets/DECERR, per-context order and threshold, 4-way race, simultaneous claims, ignored completions, CLINT MSIP/MTIP per hart, 64-bit compare, byte strobes, MEIP+MTIP+MSIP on 4 harts, reset",checks);
    $finish;
  end
  initial begin #2000000;$fatal(1,"4-hart IRQ timeout");end
endmodule
