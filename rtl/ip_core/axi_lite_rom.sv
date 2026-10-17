// Read-only local boot memory for each Ibex tile.
module axi_lite_rom #(
  parameter int WORDS = 4096,
  parameter string INIT_FILE = "",
  localparam int INDEX_W = (WORDS <= 1) ? 1 : $clog2(WORDS)
) (
  input logic       clk_i,
  input logic       rst_ni,
  axi_lite_if.slave s_axi
);
  (* rom_style = "block" *) logic [31:0] mem [0:WORDS-1];
  logic rvalid_q, bvalid_q;
  logic [31:0] rdata_q;
  logic aw_seen_q, w_seen_q;
  logic [1:0] rresp_q;

  initial begin
    for (int i = 0; i < WORDS; i++) mem[i] = 32'h0000_0013;
    if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
  end

  assign s_axi.arready = !rvalid_q;
  assign s_axi.rvalid  = rvalid_q;
  assign s_axi.rdata   = rdata_q;
  assign s_axi.rresp   = rresp_q;
  assign s_axi.awready = !aw_seen_q && !bvalid_q;
  assign s_axi.wready  = !w_seen_q  && !bvalid_q;
  assign s_axi.bvalid  = bvalid_q;
  assign s_axi.bresp   = 2'b10;

  always_ff @(posedge clk_i) begin
    if(rst_ni && s_axi.arvalid && s_axi.arready)
      rdata_q <= s_axi.araddr<WORDS*4 && s_axi.araddr[1:0]==0 ?
                  mem[s_axi.araddr[2 +: INDEX_W]] : 32'b0;
  end
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      rvalid_q <= 1'b0;
      bvalid_q <= 1'b0;
      aw_seen_q <= 1'b0;
      w_seen_q <= 1'b0;
      rresp_q <= 0;
    end else begin
      if (s_axi.arvalid && s_axi.arready) begin
        rresp_q <= s_axi.araddr<WORDS*4 && s_axi.araddr[1:0]==0 ? 2'b00 : 2'b11;
        rvalid_q <= 1'b1;
      end
      if (rvalid_q && s_axi.rready) rvalid_q <= 1'b0;
      if (s_axi.awvalid && s_axi.awready) aw_seen_q <= 1'b1;
      if (s_axi.wvalid  && s_axi.wready)  w_seen_q  <= 1'b1;
      if (aw_seen_q && w_seen_q) begin
        bvalid_q <= 1'b1;
        aw_seen_q <= 1'b0;
        w_seen_q <= 1'b0;
      end
      if (bvalid_q && s_axi.bready) bvalid_q <= 1'b0;
    end
  end
endmodule
