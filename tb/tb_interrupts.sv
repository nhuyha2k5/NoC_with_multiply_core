`timescale 1ns/1ps
// PLIC / timer / IPI verification suite (BFM driven, self-checking).
// PLIC policy under test (RISC-V PLIC 1.0 semantics, documented in
// docs/bao_cao_buoc1_2_20261008.md):
//  - level-sensitive gateways; a pulse that ends while the source is in flight
//    is not remembered (event coalescing);
//  - claim returns the highest priority enabled pending source whose priority
//    is strictly above the context threshold, lowest ID on ties, 0 if none;
//  - complete must be a full-word write from the claiming context while the
//    source is enabled for it; otherwise it is ignored (spec "silently
//    ignored"). Recovery after disabling an in-flight source is: re-enable,
//    then complete.
module tb_interrupts;
  logic clk_i=0,rst_ni=0;
  always #5 clk_i=~clk_i;
  axi_lite_if axi(clk_i,rst_ni);
  axi_lite_bfm host(.clk_i,.axi);
  logic [8:1] sources=0;
  bit gpio_mode=0;
  axi_lite_if gpio_axi(clk_i,rst_ni);
  axi_lite_bfm gpio_host(.clk_i,.axi(gpio_axi));
  logic [7:0] gpio_in=0,gpio_out,gpio_oe;
  logic gpio_irq;
  axi_lite_gpio u_gpio(.clk_i,.rst_ni,.gpio_i(gpio_in),.gpio_o(gpio_out),.gpio_oe_o(gpio_oe),
    .irq_o(gpio_irq),.s_axi(gpio_axi));
  logic [1:0] ext,timer,ipi;
  logic [31:0] d,hi0,lo,hi1;
  int checks=0;
  axi_lite_interrupts dut(.clk_i,.rst_ni,.sources_i({gpio_mode?gpio_irq:sources[8],sources[7:1]}),
    .external_irq_o(ext),.timer_irq_o(timer),.software_irq_o(ipi),.s_axi(axi));

  localparam logic [31:0] PLIC='h0c000000, PENDING='h0c001000;
  function automatic logic [31:0] prio(input int id);return PLIC+4*id;endfunction
  function automatic logic [31:0] enable(input int ctx);return 'h0c002000+ctx*'h80;endfunction
  function automatic logic [31:0] thresh(input int ctx);return 'h0c200000+ctx*'h1000;endfunction
  function automatic logic [31:0] claim_addr(input int ctx);return 'h0c200004+ctx*'h1000;endfunction
  task automatic settle;repeat(3)@(negedge clk_i);endtask
  task automatic expect_claim(input int ctx,input int id,input string what);
    host.read(claim_addr(ctx),d);checks++;
    assert(d==id)else $fatal(1,"%s: ctx%0d claim got %0d expected %0d",what,ctx,d,id);
  endtask
  task automatic complete(input int ctx,input int id,input logic[3:0] strb=15);
    host.write(claim_addr(ctx),id,strb);
  endtask
  task automatic expect_ext(input logic [1:0] value,input string what);
    settle;checks++;assert(ext==value)else $fatal(1,"%s: ext=%b expected %b",what,ext,value);
  endtask
  task automatic plic_clean;
    sources=0;
    for(int c=0;c<2;c++)begin host.write(enable(c),0);host.write(thresh(c),0);end
    for(int s=1;s<=8;s++)host.write(prio(s),0);
  endtask

  initial begin
    repeat(5)@(negedge clk_i);rst_ni=1;
    // ---- Original smoke: priority/threshold/claim/complete/two contexts ----
    host.write(prio(1),2,15,0,3);host.write(prio(2),5,15,0,-3);
    host.write(enable(0),6);host.write(enable(1),6);
    sources=3;settle;
    assert(ext==3)else $fatal(1,"PLIC missing contexts");
    host.write(thresh(0),5);assert(!ext[0])else $fatal(1,"PLIC threshold failed");
    host.write(thresh(0),0);
    expect_claim(0,2,"Priority claim");
    expect_claim(1,1,"Claim delivered twice");
    expect_claim(0,0,"Inflight claimed again");
    complete(1,2);expect_ext(0,"Wrong-context completion rearmed gateway");
    complete(0,2);settle;assert(ext!=0)else $fatal(1,"Level source did not repend after completion");
    sources=0;expect_claim(0,2,"Reclaim");
    complete(0,2);complete(1,1);

    // ---- Register read-back ----
    host.read(prio(2),d);assert(d==5)else $fatal(1,"Priority readback");
    host.write(prio(3),32'hffffffff);host.read(prio(3),d);assert(d==7)else $fatal(1,"Priority width not 3 bits");
    host.read(enable(1),d);assert(d==6)else $fatal(1,"Enable readback");
    host.write(thresh(1),4);host.read(thresh(1),d);assert(d==4)else $fatal(1,"Threshold readback");
    plic_clean;

    // ---- Invalid offsets return DECERR, valid ones OKAY ----
    host.read(prio(9),d,3);host.write(prio(9),1,15,3);
    host.read('h0c002004,d,3);host.read('h0c200008,d,3);host.write('h0c000002,1,15,3);
    host.read(PENDING,d);

    // ---- Priority 0 never interrupts; pending is still visible ----
    host.write(enable(0),'h1fe);sources[4]=1;settle;
    assert(ext==0)else $fatal(1,"Priority-0 source interrupted");
    host.read(PENDING,d);assert(d[4])else $fatal(1,"Priority-0 source not pending");
    expect_claim(0,0,"Priority-0 claim");
    // ---- Threshold equal to priority masks; one below unmasks ----
    host.write(prio(4),3);host.write(thresh(0),3);expect_ext(0,"Threshold==priority must mask");
    expect_claim(0,0,"Masked claim");
    host.write(thresh(0),2);expect_ext(1,"Threshold below priority must unmask");
    expect_claim(0,4,"Unmasked claim");complete(0,4);sources[4]=0;
    plic_clean;

    // ---- All 8 sources at once: priority order, ID tie-break ----
    begin
      int pr[9]='{0,3,6,6,1,7,2,6,3};
      int order[8]='{5,2,3,7,1,8,6,4};
      for(int s=1;s<=8;s++)host.write(prio(s),pr[s]);
      host.write(enable(0),'h1fe);sources=8'hff;settle;
      for(int k=0;k<8;k++)begin expect_claim(0,order[k],"Global arbitration order");end
      expect_claim(0,0,"Claim after all sources in flight");
      sources=0;for(int k=0;k<8;k++)complete(0,order[k]);
      expect_ext(0,"Stale IRQ after full drain");
      host.read(PENDING,d);assert(d==0)else $fatal(1,"Pending left after drain: %h",d);
    end
    plic_clean;

    // ---- Enable change while pending ----
    host.write(prio(2),4);host.write(enable(0),4);sources[2]=1;expect_ext(1,"Enabled source");
    host.write(enable(0),0);expect_ext(0,"Disable must drop IRQ while pending");
    expect_claim(0,0,"Disabled source must not be claimable");
    host.read(PENDING,d);assert(d[2])else $fatal(1,"Pending lost on disable");
    host.write(enable(0),4);expect_ext(1,"Re-enable must restore IRQ");
    expect_claim(0,2,"Claim after re-enable");
    // ---- Complete while disabled is ignored (spec); recovery path ----
    host.write(enable(0),0);complete(0,2);host.write(enable(0),4);
    expect_ext(0,"Completion while disabled must be ignored");
    expect_claim(0,0,"Source must still be in flight");
    complete(0,2);expect_ext(1,"Re-enable then complete must rearm the gateway");
    expect_claim(0,2,"Claim after recovery");
    // ---- Partial-strobe and out-of-range completions are ignored ----
    complete(0,2,4'b0001);expect_ext(0,"Partial-strobe completion accepted");
    complete(0,0);complete(0,9);complete(0,'hffffffff);expect_ext(0,"Out-of-range completion accepted");
    sources[2]=0;complete(0,2);expect_ext(0,"Cleared level must not repend");
    complete(0,2);expect_ext(0,"Duplicate completion");
    expect_claim(0,0,"Duplicate completion created a claim");
    // ---- Level gateway coalescing: pulse during flight is dropped ----
    sources[2]=1;settle;expect_claim(0,2,"Pulse claim");
    sources[2]=0;settle;sources[2]=1;settle;sources[2]=0;
    complete(0,2);expect_ext(0,"Pulse while in flight must coalesce (level gateway)");
    plic_clean;

    // ---- Two contexts race for one source ----
    host.write(prio(6),5);host.write(enable(0),'h40);host.write(enable(1),'h40);
    sources[6]=1;expect_ext(3,"Shared source to both contexts");
    expect_claim(1,6,"Context 1 wins the race");
    expect_ext(0,"Loser context must drop IRQ after claim");
    expect_claim(0,0,"Loser context gets 0");
    complete(0,6);expect_ext(0,"Non-owner completion accepted");
    sources[6]=0;complete(1,6);expect_ext(0,"Owner completion with level low");
    plic_clean;

    // ---- Reset while pending/in flight ----
    host.write(prio(1),7);host.write(prio(3),7);host.write(enable(0),'h0a);
    sources[1]=1;sources[3]=1;settle;expect_claim(0,1,"Pre-reset claim");
    @(negedge clk_i);rst_ni=0;sources=0;repeat(3)@(negedge clk_i);rst_ni=1;settle;
    assert(ext==0&&timer==0&&ipi==0)else $fatal(1,"Outputs not cleared by reset");
    host.read(PENDING,d);assert(d==0)else $fatal(1,"Pending survived reset");
    host.read(enable(0),d);assert(d==0)else $fatal(1,"Enable survived reset");
    host.read(prio(1),d);assert(d==0)else $fatal(1,"Priority survived reset");
    host.write(prio(1),7);host.write(enable(0),2);sources[1]=1;expect_ext(1,"Post-reset IRQ");
    expect_claim(0,1,"Post-reset claim (inflight cleared by reset)");sources[1]=0;complete(0,1);
    plic_clean;

    // ---- Timer and IPI (original checks) ----
    host.write('h30002020,1);assert(ipi==1)else $fatal(1,"Hart0 MSIP failed");
    host.write('h30002024,1);assert(ipi==3)else $fatal(1,"Hart1 MSIP failed");
    host.write('h30002020,0);host.write('h30002024,0);assert(ipi==0)else $fatal(1,"MSIP clear failed");
    host.write('h30002008,1);host.write('h3000200c,0);
    host.write('h30002018,'hffffffff);host.write('h3000201c,'hffffffff);
    host.write('h30002010,3);assert(timer==1)else $fatal(1,"Per-hart compare failed");
    host.write('h30002018,1);host.write('h3000201c,0);assert(timer==3)else $fatal(1,"Hart1 timer failed");
    host.write('h30002010,0);assert(timer==0)else $fatal(1,"Timer mask failed");
    host.read('h0c000040,d,3);host.write('h30002014,0,15,3);
    // ---- 64-bit compare across the 32-bit boundary; safe hi/lo/hi read ----
    host.write('h30002010,0);
    host.write('h3000200c,'hffffffff);host.write('h30002008,'h00000005);host.write('h3000200c,1);
    host.write('h30002004,0);host.write('h30002000,'hffffff80);
    host.write('h30002010,1);
    assert(timer[0]==0)else $fatal(1,"Timer fired before 64-bit compare");
    begin
      int waited=0;
      while(!timer[0])begin @(negedge clk_i);waited++;assert(waited<400)else $fatal(1,"64-bit compare never fired");end
    end
    do begin host.read('h30002004,hi0);host.read('h30002000,lo);host.read('h30002004,hi1);end while(hi0!=hi1);
    assert(hi1==1 && lo>=5)else $fatal(1,"mtime carry wrong: %h_%h",hi1,lo);
    // Rearm periodic timer: moving compare ahead clears MTIP.
    host.write('h3000200c,'hffffffff);host.write('h30002008,lo+1000);host.write('h3000200c,hi1);
    assert(timer[0]==0)else $fatal(1,"Rearm did not clear MTIP");
    host.write('h30002010,0);
    // ---- MSIP, MTIP and MEIP together on both harts ----
    host.write(prio(5),1);host.write(enable(0),'h20);host.write(enable(1),'h20);sources[5]=1;
    host.write('h30002008,0);host.write('h3000200c,0);host.write('h30002018,0);host.write('h3000201c,0);
    host.write('h30002010,3);host.write('h30002020,1);host.write('h30002024,1);settle;
    assert(ext==3&&timer==3&&ipi==3)else $fatal(1,"Concurrent MEIP/MTIP/MSIP ext=%b timer=%b ipi=%b",ext,timer,ipi);
    host.write('h30002024,0);assert(ipi==1&&timer==3&&ext==3)else $fatal(1,"Clearing hart1 MSIP disturbed others");
    host.write('h30002010,1);assert(timer==1&&ipi==1)else $fatal(1,"Masking hart1 MTIP disturbed others");
    host.write('h30002020,0);host.write('h30002010,0);sources[5]=0;
    expect_claim(1,5,"MEIP claim with other IRQs");complete(1,5);
    plic_clean;

    // ---- GPIO edge -> source 8 -> PLIC; clear peripheral before completion ----
    gpio_mode=1;
    host.write(prio(8),7);
    host.write(enable(0),'h100);
    gpio_host.write('h3000100c,4);gpio_host.write('h30001010,4);
    gpio_in=4;repeat(4)@(negedge clk_i);
    assert(gpio_irq&&ext[0])else $fatal(1,"GPIO IRQ not routed to PLIC");
    expect_claim(0,8,"GPIO PLIC claim");
    gpio_host.write('h30001018,4);
    complete(0,8);
    gpio_host.read('h30001018,d);assert(d==0)else $fatal(1,"GPIO W1C pending");
    expect_ext(0,"GPIO stale IRQ");
    $display("TEST_PASS: PLIC full suite (%0d claim/IRQ checks): priority 0, threshold edges, 8-source order and ties, enable while pending/in flight, ignored completions and recovery, coalescing, two-context race, reset; 64-bit timer carry and rearm; concurrent MEIP/MTIP/MSIP; GPIO",checks);
    $finish;
  end
  initial begin #400000;$fatal(1,"IRQ timeout");end
endmodule
