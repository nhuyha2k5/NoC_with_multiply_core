// 64-bit mtime/mtimecmp AXI4-Lite timer with interrupt output.
module axi_lite_timer (
  input  logic        clk_i,
  input  logic        rst_ni,
  output logic        irq_o,
  axi_lite_if.slave   s_axi
);
  logic [63:0] mtime_q, mtimecmp_q;
  logic enable_q;
  logic [31:0] awaddr_q, wdata_q;
  logic [3:0] wstrb_q;
  logic aw_q, w_q, bvalid_q, rvalid_q;
  logic [31:0] rdata_q;

  assign irq_o = enable_q && (mtime_q >= mtimecmp_q);
  assign s_axi.awready = !aw_q && !bvalid_q;
  assign s_axi.wready  = !w_q  && !bvalid_q;
  assign s_axi.bvalid  = bvalid_q;
  assign s_axi.bresp   = 2'b00;
  assign s_axi.arready = !rvalid_q;
  assign s_axi.rvalid  = rvalid_q;
  assign s_axi.rdata   = rdata_q;
  assign s_axi.rresp   = 2'b00;

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      mtime_q <= '0; mtimecmp_q <= 64'hffff_ffff_ffff_ffff; enable_q <= 1'b0;
      aw_q <= 1'b0; w_q <= 1'b0; bvalid_q <= 1'b0; rvalid_q <= 1'b0;
      awaddr_q <= '0; wdata_q <= '0; wstrb_q <= '0; rdata_q <= '0;
    end else begin
      mtime_q <= mtime_q + 1'b1;
      if (s_axi.awvalid && s_axi.awready) begin awaddr_q <= s_axi.awaddr; aw_q <= 1'b1; end
      if (s_axi.wvalid && s_axi.wready) begin wdata_q <= s_axi.wdata; wstrb_q <= s_axi.wstrb; w_q <= 1'b1; end
      if (aw_q && w_q) begin
        unique case (awaddr_q[5:2])
          4'h0: for (int b=0;b<4;b++) if (wstrb_q[b]) mtime_q[b*8 +: 8] <= wdata_q[b*8 +: 8];
          4'h1: for (int b=0;b<4;b++) if (wstrb_q[b]) mtime_q[32+b*8 +: 8] <= wdata_q[b*8 +: 8];
          4'h2: for (int b=0;b<4;b++) if (wstrb_q[b]) mtimecmp_q[b*8 +: 8] <= wdata_q[b*8 +: 8];
          4'h3: for (int b=0;b<4;b++) if (wstrb_q[b]) mtimecmp_q[32+b*8 +: 8] <= wdata_q[b*8 +: 8];
          4'h4: if (wstrb_q[0]) enable_q <= wdata_q[0];
          default: ;
        endcase
        aw_q <= 1'b0; w_q <= 1'b0; bvalid_q <= 1'b1;
      end
      if (bvalid_q && s_axi.bready) bvalid_q <= 1'b0;
      if (s_axi.arvalid && s_axi.arready) begin
        unique case (s_axi.araddr[5:2])
          4'h0: rdata_q <= mtime_q[31:0];
          4'h1: rdata_q <= mtime_q[63:32];
          4'h2: rdata_q <= mtimecmp_q[31:0];
          4'h3: rdata_q <= mtimecmp_q[63:32];
          4'h4: rdata_q <= {30'b0, irq_o, enable_q};
          default: rdata_q <= 32'b0;
        endcase
        rvalid_q <= 1'b1;
      end
      if (rvalid_q && s_axi.rready) rvalid_q <= 1'b0;
    end
  end
endmodule
