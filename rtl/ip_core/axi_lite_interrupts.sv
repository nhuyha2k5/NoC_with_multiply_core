// Interrupt/control MMIO block: PLIC (HARTS contexts, SOURCES sources) at
// 0x0C00_0000, timer at the CLINT map 0x0200_0000 (LEGACY_TIMER=0) or the
// original 2-hart timer/IPI map at 0x3000_2000 (LEGACY_TIMER=1, HARTS=2 only),
// and NoC policy/counters at 0x3000_6000.
module axi_lite_interrupts #(
  parameter int HARTS=2,
  parameter int SOURCES=8,
  parameter bit LEGACY_TIMER=1'b1
)(
  input logic clk_i,rst_ni,
  input logic [SOURCES:1] sources_i,
  output logic [HARTS-1:0] external_irq_o,timer_irq_o,software_irq_o,
  input logic[1439:0] flits_i='0,packets_i='0,stalls_i='0,
  input logic[359:0] peaks_i='0,
  output logic[1:0] qos_mode_o,output logic qos_classes_o,qos_aging_o,
  output logic[3:0] qos_age_o,output logic[7:0] qos_weights_o,source_classes_o,dma_gap_o,
  output logic counters_enable_o,counters_clear_o,
  axi_lite_if.slave s_axi
);
  localparam logic [31:0] PLIC_END=32'h0c20_0000+32'(HARTS)*32'h1000;
  logic wr,rd;
  logic [31:0] wa,wd,ra,pdata,tdata,rdata,ndata;
  logic [3:0] ws;
  logic [1:0] pw,pr,tw,tr,nw,nr,wresp,rresp;
  logic wp,rp,wt,rt,wn,rn;
  assign wp=wa>=32'h0c00_0000 && wa<PLIC_END;
  assign rp=ra>=32'h0c00_0000 && ra<PLIC_END;
  assign wt=LEGACY_TIMER ? (wa>=32'h3000_2000 && wa<32'h3000_2100) : (wa>=32'h0200_0000 && wa<32'h0200_c000);
  assign rt=LEGACY_TIMER ? (ra>=32'h3000_2000 && ra<32'h3000_2100) : (ra>=32'h0200_0000 && ra<32'h0200_c000);
  assign wn=wa[31:8]==24'h300060;
  assign rn=ra[31:8]==24'h300060;
  assign rdata=rp?pdata:(rn?ndata:tdata);
  assign wresp=wp?pw:(wt?tw:(wn?nw:2'b11));
  assign rresp=rp?pr:(rt?tr:(rn?nr:2'b11));
  axi_lite_register_port u_regs(.clk_i,.rst_ni,.s_axi,.wr_en_o(wr),.rd_en_o(rd),
    .wr_addr_o(wa),.wr_data_o(wd),.wr_strb_o(ws),.rd_addr_o(ra),
    .rd_data_i(rdata),.wr_resp_i(wresp),.rd_resp_i(rresp));
  plic_core #(.SOURCES(SOURCES),.CONTEXTS(HARTS)) u_plic(.clk_i,.rst_ni,.sources_i,.wr_en_i(wr&&wp),.rd_en_i(rd&&rp),
    .wr_offset_i(wa[23:0]),.rd_offset_i(ra[23:0]),.wr_data_i(wd),.wr_strb_i(ws),
    .rd_data_o(pdata),.wr_resp_o(pw),.rd_resp_o(pr),.irq_o(external_irq_o));
  if(LEGACY_TIMER)begin:g_legacy_timer
    timer_ipi_core u_timer(.clk_i,.rst_ni,.wr_en_i(wr&&wt),.wr_offset_i(wa[7:0]),
      .rd_offset_i(ra[7:0]),.wr_data_i(wd),.wr_strb_i(ws),.rd_data_o(tdata),
      .wr_resp_o(tw),.rd_resp_o(tr),.timer_irq_o,.software_irq_o);
  end else begin:g_clint
    clint_core #(.HARTS(HARTS)) u_clint(.clk_i,.rst_ni,.wr_en_i(wr&&wt),.wr_offset_i(wa[15:0]),
      .rd_offset_i(ra[15:0]),.wr_data_i(wd),.wr_strb_i(ws),.rd_data_o(tdata),
      .wr_resp_o(tw),.rd_resp_o(tr),.timer_irq_o,.software_irq_o);
  end
  noc_control u_noc_control(.clk_i,.rst_ni,.wr_en_i(wr&&wn),.wr_offset_i(wa[7:0]),.rd_offset_i(ra[7:0]),
    .wr_data_i(wd),.wr_strb_i(ws),.rd_data_o(ndata),.wr_resp_o(nw),.rd_resp_o(nr),
    .flits_i,.packets_i,.stalls_i,.peaks_i,.qos_mode_o,.qos_classes_o,.qos_aging_o,.qos_age_o,.qos_weights_o,
    .source_classes_o,.dma_gap_o,.counters_enable_o,.counters_clear_o);
`ifndef SYNTHESIS
  initial assert(!LEGACY_TIMER || HARTS==2)else $fatal(1,"Legacy timer map supports exactly 2 harts");
`endif
endmodule
