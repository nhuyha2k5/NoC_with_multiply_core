// Byte-writeable shared AXI4-Lite RAM.
module axi_lite_ram #(
  parameter int WORDS = 4096,
  parameter logic [31:0] BASE_ADDR = 32'h2000_0000,
  parameter string INIT_FILE = "",
  localparam int ADDR_LSB = 2,
  localparam int INDEX_W = (WORDS <= 1) ? 1 : $clog2(WORDS)
) (
  input logic       clk_i,
  input logic       rst_ni,
  axi_lite_if.slave s_axi
);
  // Keep the memory array out of the asynchronous-reset process so Vivado can
  // infer true block RAM instead of attempting to build the array from FFs.
  (* ram_style = "block" *) logic [31:0] mem [0:WORDS-1];
  logic [31:0] awaddr_q, wdata_q;
  logic [3:0]  wstrb_q;
  logic aw_hold_q, w_hold_q;
  logic bvalid_q, rvalid_q;
  logic [31:0] rdata_q;
  logic [1:0] bresp_q,rresp_q;
  function automatic logic legal(input logic [31:0] addr);
    return addr[1:0]==0 && {1'b0,addr}>={1'b0,BASE_ADDR} &&
           {1'b0,addr}<({1'b0,BASE_ADDR}+33'(WORDS*4));
  endfunction

  initial begin
    for (int i = 0; i < WORDS; i++) mem[i] = 32'b0;
    if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
  end

  assign s_axi.awready = !aw_hold_q && !bvalid_q;
  assign s_axi.wready  = !w_hold_q  && !bvalid_q;
  assign s_axi.bvalid  = bvalid_q;
  assign s_axi.bresp   = bresp_q;
  assign s_axi.arready = !rvalid_q;
  assign s_axi.rvalid  = rvalid_q;
  assign s_axi.rdata   = rdata_q;
  assign s_axi.rresp   = rresp_q;

  // BRAM-friendly byte-write port. Memory contents are intentionally not
  // reset; INIT_FILE (or the initial zero image) defines power-up contents.
  always @(posedge clk_i) begin
    if (rst_ni && aw_hold_q && w_hold_q && !bvalid_q && legal(awaddr_q)) begin
      if (wstrb_q[0]) mem[awaddr_q[ADDR_LSB +: INDEX_W]][7:0]   <= wdata_q[7:0];
      if (wstrb_q[1]) mem[awaddr_q[ADDR_LSB +: INDEX_W]][15:8]  <= wdata_q[15:8];
      if (wstrb_q[2]) mem[awaddr_q[ADDR_LSB +: INDEX_W]][23:16] <= wdata_q[23:16];
      if (wstrb_q[3]) mem[awaddr_q[ADDR_LSB +: INDEX_W]][31:24] <= wdata_q[31:24];
    end
    if(rst_ni && s_axi.arvalid && s_axi.arready)
      rdata_q <= legal(s_axi.araddr) ? mem[s_axi.araddr[ADDR_LSB +: INDEX_W]] : 32'b0;
  end

  always @(posedge clk_i) begin
    if (!rst_ni) begin
      awaddr_q <= '0;
      wdata_q  <= '0;
      wstrb_q  <= '0;
      aw_hold_q <= 1'b0;
      w_hold_q  <= 1'b0;
      bvalid_q  <= 1'b0;
      rvalid_q  <= 1'b0;
      bresp_q <= 0;
      rresp_q <= 0;
    end else begin
      if (s_axi.awvalid && s_axi.awready) begin
        awaddr_q <= s_axi.awaddr;
        aw_hold_q <= 1'b1;
      end
      if (s_axi.wvalid && s_axi.wready) begin
        wdata_q <= s_axi.wdata;
        wstrb_q <= s_axi.wstrb;
        w_hold_q <= 1'b1;
      end

      if (aw_hold_q && w_hold_q && !bvalid_q) begin
        aw_hold_q <= 1'b0;
        w_hold_q  <= 1'b0;
        bvalid_q  <= 1'b1;
        bresp_q <= legal(awaddr_q) ? 2'b00 : 2'b11;
      end
      if (bvalid_q && s_axi.bready) bvalid_q <= 1'b0;

      if (s_axi.arvalid && s_axi.arready) begin
        rresp_q <= legal(s_axi.araddr) ? 2'b00 : 2'b11;
        rvalid_q <= 1'b1;
      end
      if (rvalid_q && s_axi.rready) rvalid_q <= 1'b0;
    end
  end
endmodule
