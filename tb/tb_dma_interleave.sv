`timescale 1ns/1ps
module tb_dma_interleave;
  logic clk_i=0,rst_ni=0;
  always #5 clk_i=~clk_i;
  axi_lite_if ctrl(clk_i,rst_ni);
  axi4_if mem(clk_i,rst_ni);
  axi_lite_bfm host(.clk_i,.axi(ctrl));
  wire irq_done,irq_error;
  axi4_dma #(.MAX_BEATS(4)) dut(.clk_i,.rst_ni,.s_axi(ctrl),.m_axi(mem),
    .irq_done_o(irq_done),.irq_error_o(irq_error));
  int ar_count=0,aw_count=0,write_beat=0;
  logic [31:0] ar_addr[0:1],aw_addr,dst_word[0:7];
  logic [3:0] ar_id[0:1],aw_id;
  logic [7:0] ar_len[0:1];
  logic [31:0] status;
  assign mem.arready=1;
  assign mem.awready=1;
  assign mem.wready=1;
  always @(posedge clk_i)begin
    if(!rst_ni)begin
      ar_count<=0;aw_count<=0;write_beat<=0;
      mem.bvalid<=0;mem.bresp<=0;mem.bid<=0;
    end else begin
      if(mem.arvalid&&mem.arready)begin
        assert(ar_count<2)else $fatal(1,"Extra read burst");
        ar_addr[ar_count]<=mem.araddr;ar_id[ar_count]<=mem.arid;
        ar_len[ar_count]<=mem.arlen;ar_count<=ar_count+1;
      end
      if(mem.awvalid&&mem.awready)begin
        assert(aw_count<2)else $fatal(1,"Extra write burst");
        aw_addr<=mem.awaddr;aw_id<=mem.awid;write_beat<=0;aw_count<=aw_count+1;
      end
      if(mem.wvalid&&mem.wready)begin
        assert(aw_count>0&&mem.wstrb==4'hf)else $fatal(1,"Write without AW/STRB");
        dst_word[((aw_addr-32'h20008400)>>2)+write_beat]<=mem.wdata;
        if(mem.wlast)begin
          assert(write_beat==3)else $fatal(1,"Early WLAST");
          mem.bvalid<=1;mem.bid<=aw_id;
        end else write_beat<=write_beat+1;
      end
      if(mem.bvalid&&mem.bready)mem.bvalid<=0;
    end
  end
  task automatic response_beat(input bit bank,input int beat);
    @(negedge clk_i);
    mem.rvalid=1;mem.rid={3'b0,bank};mem.rdata=32'(bank?200:100)+32'(beat);
    mem.rresp=0;mem.rlast=beat==3;
    do @(posedge clk_i);while(!mem.rready);
    @(negedge clk_i);mem.rvalid=0;
  endtask
  initial begin
    mem.rvalid=0;mem.rid=0;mem.rdata=0;mem.rresp=0;mem.rlast=0;
    repeat(5)@(negedge clk_i);rst_ni=1;
    host.write('h30004000,'h20008000);
    host.write('h30004004,'h20008400);
    host.write('h30004008,32);
    host.write('h30004028,4);
    host.write('h3000400c,1);
    wait(ar_count==2);
    assert(ar_id[0]==0&&ar_id[1]==1&&ar_len[0]==3&&ar_len[1]==3&&
      ar_addr[0]==32'h20008000&&ar_addr[1]==32'h20008010)
      else $fatal(1,"DMA did not issue two read IDs/bursts");
    for(int beat=0;beat<4;beat++)begin
      response_beat(0,beat);
      response_beat(1,beat);
    end
    do host.read('h30004010,status);while(status[0]);
    assert(status==2&&aw_count==2)else $fatal(1,"Interleaved DMA completion %h",status);
    for(int beat=0;beat<4;beat++)begin
      assert(dst_word[beat]==32'(100+beat))else $fatal(1,"ID0 beat %0d",beat);
      assert(dst_word[beat+4]==32'(200+beat))else $fatal(1,"ID1 beat %0d",beat);
    end
    $display("TEST_PASS: AXI4 DMA interleaved read IDs preserve per-buffer beat order");
    $finish;
  end
  initial begin #100000;$fatal(1,"DMA interleave timeout");end
endmodule
