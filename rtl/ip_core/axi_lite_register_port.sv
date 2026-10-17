// Independent AW/W capture, stable B/R under backpressure, one write + one read.
module axi_lite_register_port (
  input logic clk_i, rst_ni,
  axi_lite_if.slave s_axi,
  output logic wr_en_o, rd_en_o,
  output logic [31:0] wr_addr_o, wr_data_o, rd_addr_o,
  output logic [3:0] wr_strb_o,
  input logic [31:0] rd_data_i,
  input logic [1:0] wr_resp_i, rd_resp_i
);
  logic aw_q,w_q,b_q,r_q;
  logic [31:0] rdata_q;
  logic [1:0] bresp_q,rresp_q;
  assign s_axi.awready = !aw_q && !b_q;
  assign s_axi.wready = !w_q && !b_q;
  assign s_axi.bvalid = b_q;
  assign s_axi.bresp = bresp_q;
  assign s_axi.arready = !r_q;
  assign s_axi.rvalid = r_q;
  assign s_axi.rdata = rdata_q;
  assign s_axi.rresp = rresp_q;
  assign wr_en_o = aw_q && w_q && !b_q;
  assign rd_en_o = s_axi.arvalid && s_axi.arready;
  assign rd_addr_o = s_axi.araddr;
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      aw_q<=0; w_q<=0; b_q<=0; r_q<=0;
      wr_addr_o<=0; wr_data_o<=0; wr_strb_o<=0;
      rdata_q<=0; bresp_q<=0; rresp_q<=0;
    end else begin
      if(s_axi.awvalid && s_axi.awready) begin aw_q<=1; wr_addr_o<=s_axi.awaddr; end
      if(s_axi.wvalid && s_axi.wready) begin w_q<=1; wr_data_o<=s_axi.wdata; wr_strb_o<=s_axi.wstrb; end
      if(wr_en_o) begin aw_q<=0; w_q<=0; b_q<=1; bresp_q<=wr_resp_i; end
      if(b_q && s_axi.bready) b_q<=0;
      if(rd_en_o) begin r_q<=1; rdata_q<=rd_data_i; rresp_q<=rd_resp_i; end
      if(r_q && s_axi.rready) r_q<=0;
    end
  end
endmodule
