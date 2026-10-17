// Two-buffer burst DMA. Reads, writes and B retirement run independently.
// Errors/abort stop new work, drain all accepted AXI operations, and preserve
// backpressured VALID. A watchdog reports stalls; it never drops live traffic.
module axi4_dma # (parameter int MAX_BEATS=16)(
  input logic clk_i,rst_ni,
  input logic[1:0] qos_i=0,
  input logic[7:0] issue_gap_i=0,
  axi_lite_if.slave s_axi,axi4_if.master m_axi,
  output logic irq_done_o,irq_error_o
);
  import router_pkg::*;
  typedef enum logic[1:0]{FREE,READING,READY,WRITING} buffer_state_t;
  buffer_state_t state[2];
  logic[31:0] buffer_data[2][MAX_BEATS];
  logic[4:0] beats[2];logic[31:0] offset[2];logic bad[2];
  logic wr,rd,busy,done,error,start,config_valid,abort_req,progress;
  logic[31:0] wa,wd,ra,rdata,src,dst,length,read_offset,cycles,bytes_done,watchdog,quiet,error_code;
  logic[3:0] ws;logic[1:0] wresp,rresp,irq_enable;
  logic[4:0] burst_limit,chunk;
  logic read_bank,write_bank,ar_pending;
  logic[1:0] write_phase;
  // AXI4 may interleave R beats from different IDs. Count each buffer's
  // position independently even though the current NI retires in order.
  logic[4:0] rbeat[2],wbeat;
  logic[7:0] gap;
  logic[1:0] read_qos,write_qos;
  logic[31:0] src_next,dst_next,remaining_words;
  logic[10:0] src_boundary,dst_boundary;
  assign src_next=src+read_offset;assign dst_next=dst+read_offset;
  assign remaining_words=(length-read_offset)>>2;
  assign src_boundary=(13'd4096-{1'b0,src_next[11:0]})>>2;
  assign dst_boundary=(13'd4096-{1'b0,dst_next[11:0]})>>2;
  always_comb begin
    chunk=burst_limit;
    if(remaining_words<chunk)chunk=5'(remaining_words);
    if(src_boundary<chunk)chunk=5'(src_boundary);
    if(dst_boundary<chunk)chunk=5'(dst_boundary);
  end
  assign config_valid=engine_range(src,length)&&engine_range(dst,length)&&
    (({1'b0,src}+{1'b0,length}<={1'b0,dst})||({1'b0,dst}+{1'b0,length}<={1'b0,src}));
  assign start=wr&&wresp==0&&wa[7:0]==12&&ws[0]&&wd[0]&&!busy;
  assign abort_req=wr&&wresp==0&&wa[7:0]==12&&ws[0]&&wd[1]&&busy;
  assign irq_done_o=done&&irq_enable[0];assign irq_error_o=error&&irq_enable[1];
  always_comb begin
    rdata=0;wresp=0;rresp=0;
    if(wa[31:8]!=24'h300040||wa[1:0]!=0||wa[7:0]>40)wresp=3;
    if(ra[31:8]!=24'h300040||ra[1:0]!=0||ra[7:0]>40)rresp=3;
    if(wresp==0)begin
      if((busy&&(wa[7:0]<12||wa[7:0]==32||wa[7:0]==40))||
        wa[7:0]==24||wa[7:0]==28||wa[7:0]==36)wresp=2;
      if(busy&&wa[7:0]==12&&ws[0]&&wd[0])wresp=2;
      if(wa[7:0]==40&&ws[0]&&(wd[7:0]==0||wd[7:0]>MAX_BEATS))wresp=2;
    end
    case(ra[7:0])
      0:rdata=src;4:rdata=dst;8:rdata=length;16:rdata={29'b0,error,done,busy};
      20:rdata={30'b0,irq_enable};24:rdata=cycles;28:rdata=bytes_done;
      32:rdata=watchdog;36:rdata=error_code;40:rdata={27'b0,burst_limit};default:;
    endcase
  end
  axi_lite_register_port u_regs(.clk_i,.rst_ni,.s_axi,.wr_en_o(wr),.rd_en_o(rd),
    .wr_addr_o(wa),.wr_data_o(wd),.wr_strb_o(ws),.rd_addr_o(ra),.rd_data_i(rdata),.wr_resp_i(wresp),.rd_resp_i(rresp));
  assign m_axi.araddr=src+offset[read_bank];assign m_axi.arid={3'b0,read_bank};
  assign m_axi.arlen=8'(beats[read_bank]-1'b1);assign m_axi.arsize=2;assign m_axi.arburst=1;
  assign m_axi.arlock=0;assign m_axi.arcache=0;assign m_axi.arprot=0;assign m_axi.arqos={2'b0,read_qos};
  assign m_axi.arvalid=rst_ni&&ar_pending;assign m_axi.rready=rst_ni&&busy;
  assign m_axi.awaddr=dst+offset[write_bank];assign m_axi.awid={3'b0,write_bank};
  assign m_axi.awlen=8'(beats[write_bank]-1'b1);assign m_axi.awsize=2;assign m_axi.awburst=1;
  assign m_axi.awlock=0;assign m_axi.awcache=0;assign m_axi.awprot=0;assign m_axi.awqos={2'b0,write_qos};
  assign m_axi.awvalid=rst_ni&&write_phase==1;
  assign m_axi.wdata=buffer_data[write_bank][wbeat[$clog2(MAX_BEATS)-1:0]];
  assign m_axi.wstrb=15;assign m_axi.wlast=wbeat+1==beats[write_bank];
  assign m_axi.wvalid=rst_ni&&write_phase==2;assign m_axi.bready=rst_ni&&busy;
  assign progress=(m_axi.arvalid&&m_axi.arready)||(m_axi.rvalid&&m_axi.rready)||
    (m_axi.awvalid&&m_axi.awready)||(m_axi.wvalid&&m_axi.wready)||(m_axi.bvalid&&m_axi.bready);
  always_ff @(posedge clk_i)begin
    if(!rst_ni)begin
      busy<=0;done<=0;error<=0;src<=0;dst<=0;length<=0;read_offset<=0;cycles<=0;bytes_done<=0;
      watchdog<=0;quiet<=0;error_code<=0;irq_enable<=0;burst_limit<=MAX_BEATS;
      read_bank<=0;write_bank<=0;ar_pending<=0;write_phase<=0;wbeat<=0;gap<=0;
      read_qos<=0;write_qos<=0;
      for(int b=0;b<2;b++)begin state[b]<=FREE;beats[b]<=0;offset[b]<=0;bad[b]<=0;rbeat[b]<=0;end
    end else begin
      if(busy)cycles<=cycles+1'b1;
      if(gap!=0)gap<=gap-1'b1;
      if(!busy||progress)quiet<=0;else if(quiet!=32'hffffffff)quiet<=quiet+1'b1;
      if(wr&&wresp==0)begin
        for(int b=0;b<4;b++)if(ws[b])case(wa[7:0])
          0:src[b*8+:8]<=wd[b*8+:8];4:dst[b*8+:8]<=wd[b*8+:8];8:length[b*8+:8]<=wd[b*8+:8];
          32:watchdog[b*8+:8]<=wd[b*8+:8];default:;
        endcase
        if(wa[7:0]==20&&ws[0])irq_enable<=wd[1:0];
        if(wa[7:0]==16&&ws[0])begin if(wd[1])done<=0;if(wd[2]&&!busy)begin error<=0;error_code<=0;end end
        if(wa[7:0]==40&&ws[0])burst_limit<=wd[4:0];
      end
      if(start)begin
        done<=0;error<=0;error_code<=0;read_offset<=0;cycles<=0;bytes_done<=0;quiet<=0;gap<=0;
        read_bank<=0;write_bank<=0;rbeat[0]<=0;rbeat[1]<=0;wbeat<=0;
        if(length==0)done<=1;
        else if(!config_valid)begin error<=1;error_code<=1;end
        else busy<=1;
      end
      if(busy&&!error&&!abort_req&&gap==0&&!ar_pending&&state[read_bank]==FREE&&read_offset<length)begin
        beats[read_bank]<=chunk;offset[read_bank]<=read_offset;bad[read_bank]<=0;
        state[read_bank]<=READING;ar_pending<=1;read_qos<=qos_i;
      end
      if(m_axi.arvalid&&m_axi.arready)begin
        ar_pending<=0;read_offset<=read_offset+({27'b0,beats[read_bank]}<<2);read_bank<=!read_bank;gap<=issue_gap_i;
      end
      if(m_axi.rvalid&&m_axi.rready)begin
        buffer_data[m_axi.rid[0]][rbeat[m_axi.rid[0]][$clog2(MAX_BEATS)-1:0]]<=m_axi.rdata;
        if(m_axi.rresp!=0)begin bad[m_axi.rid[0]]<=1;error<=1;error_code<=2;end
        if(m_axi.rlast)begin
          state[m_axi.rid[0]]<=(error||abort_req||bad[m_axi.rid[0]]||m_axi.rresp!=0)?FREE:READY;
          rbeat[m_axi.rid[0]]<=0;
        end else rbeat[m_axi.rid[0]]<=rbeat[m_axi.rid[0]]+1'b1;
      end
      if(busy&&write_phase==0&&!error&&!abort_req&&state[write_bank]==READY)begin
        state[write_bank]<=WRITING;write_phase<=1;wbeat<=0;write_qos<=qos_i;
      end
      if(m_axi.awvalid&&m_axi.awready)write_phase<=2;
      if(m_axi.wvalid&&m_axi.wready)begin
        if(m_axi.wlast)begin write_phase<=0;write_bank<=!write_bank;wbeat<=0;end
        else wbeat<=wbeat+1'b1;
      end
      if(m_axi.bvalid&&m_axi.bready)begin
        state[m_axi.bid[0]]<=FREE;
        if(m_axi.bresp!=0)begin error<=1;error_code<=3;end
        else bytes_done<=bytes_done+({27'b0,beats[m_axi.bid[0]]}<<2);
      end
      if(error)for(int b=0;b<2;b++)if(state[b]==READY)state[b]<=FREE;
      if(busy&&watchdog!=0&&quiet>=watchdog&&!error)begin error<=1;error_code<=4;end
      if(abort_req)begin error<=1;error_code<=5;end
      if(busy&&state[0]==FREE&&state[1]==FREE&&!ar_pending&&write_phase==0)begin
        if(error)busy<=0;
        else if(bytes_done==length)begin busy<=0;done<=1;end
      end
    end
  end
`ifndef SYNTHESIS
  always @(posedge clk_i)if(rst_ni)begin
    if(m_axi.rvalid&&m_axi.rready)
      assert(m_axi.rid<2&&state[m_axi.rid[0]]==READING&&m_axi.rlast==(rbeat[m_axi.rid[0]]+1==beats[m_axi.rid[0]]))
        else $fatal(1,"DMA read response ownership/length");
    if(m_axi.bvalid&&m_axi.bready)assert(m_axi.bid<2&&state[m_axi.bid[0]]==WRITING)else $fatal(1,"DMA B ownership");
  end
`endif
endmodule
