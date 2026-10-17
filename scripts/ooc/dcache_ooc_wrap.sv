// OOC wrapper: flattens interface ports so mesi_dcache can be synthesized alone.
module dcache_ooc_wrap #(parameter int LINES=128)(
  input logic clk_i,rst_ni,
  input logic [31:0] s_awaddr,s_wdata,s_araddr, input logic [3:0] s_wstrb,
  input logic s_awvalid,s_wvalid,s_bready,s_arvalid,s_rready,
  output logic s_awready,s_wready,s_bvalid,s_arready,s_rvalid, output logic [1:0] s_bresp,s_rresp, output logic [31:0] s_rdata,
  output logic [31:0] m_awaddr,m_wdata,m_araddr, output logic [3:0] m_wstrb,
  output logic m_awvalid,m_wvalid,m_bready,m_arvalid,m_rready,
  input logic m_awready,m_wready,m_bvalid,m_arready,m_rvalid, input logic [1:0] m_bresp,m_rresp, input logic [31:0] m_rdata,
  output logic c_req_valid,c_complete,c_snoop_ack,c_snoop_hit,c_snoop_err, output logic [1:0] c_req_cmd, output logic [31:0] c_req_addr,
  input logic c_grant,c_grant_shared,c_grant_err,c_snoop_valid,c_snoop_cmd, input logic [31:0] c_snoop_addr,
  output logic [31:0] hits,misses,wbs,invs);
  axi_lite_if s(clk_i,rst_ni); axi_lite_if m(clk_i,rst_ni); coherence_if c(clk_i,rst_ni);
  assign s.awaddr=s_awaddr;assign s.wdata=s_wdata;assign s.araddr=s_araddr;assign s.wstrb=s_wstrb;
  assign s.awvalid=s_awvalid;assign s.wvalid=s_wvalid;assign s.bready=s_bready;assign s.arvalid=s_arvalid;assign s.rready=s_rready;
  assign s_awready=s.awready;assign s_wready=s.wready;assign s_bvalid=s.bvalid;assign s_arready=s.arready;assign s_rvalid=s.rvalid;
  assign s_bresp=s.bresp;assign s_rresp=s.rresp;assign s_rdata=s.rdata;
  assign m_awaddr=m.awaddr;assign m_wdata=m.wdata;assign m_araddr=m.araddr;assign m_wstrb=m.wstrb;
  assign m_awvalid=m.awvalid;assign m_wvalid=m.wvalid;assign m_bready=m.bready;assign m_arvalid=m.arvalid;assign m_rready=m.rready;
  assign m.awready=m_awready;assign m.wready=m_wready;assign m.bvalid=m_bvalid;assign m.arready=m_arready;assign m.rvalid=m_rvalid;
  assign m.bresp=m_bresp;assign m.rresp=m_rresp;assign m.rdata=m_rdata;
  assign c_req_valid=c.req_valid;assign c_complete=c.complete;assign c_snoop_ack=c.snoop_ack;assign c_snoop_hit=c.snoop_hit;
  assign c_snoop_err=c.snoop_err;assign c_req_cmd=c.req_cmd;assign c_req_addr=c.req_addr;
  assign c.grant=c_grant;assign c.grant_shared=c_grant_shared;assign c.grant_err=c_grant_err;
  assign c.snoop_valid=c_snoop_valid;assign c.snoop_cmd=c_snoop_cmd;assign c.snoop_addr=c_snoop_addr;
  mesi_dcache #(.LINES(LINES)) u_dcache(.clk_i,.rst_ni,.s_axi(s),.m_axi(m),.coh(c),
    .hit_count_o(hits),.miss_count_o(misses),.writeback_count_o(wbs),.invalidate_count_o(invs));
endmodule
