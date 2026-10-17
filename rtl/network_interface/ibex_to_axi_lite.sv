// Converts Ibex instruction/data memory requests into AXI4-Lite transfers.
module ibex_to_axi_lite (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        req_i,
  input  logic        we_i,
  input  logic [3:0]  be_i,
  input  logic [31:0] addr_i,
  input  logic [31:0] wdata_i,
  output logic        gnt_o,
  output logic        rvalid_o,
  output logic [31:0] rdata_o,
  output logic        err_o,
  axi_lite_if.master  m_axi
);
  typedef enum logic [2:0] {
    IDLE, READ_ADDR, READ_DATA, WRITE_ADDR_DATA, WRITE_RESP
  } state_t;

  state_t state_q, state_d;
  logic [31:0] addr_q, wdata_q;
  logic [3:0]  be_q;
  logic aw_done_q, w_done_q;

  assign gnt_o = (state_q == IDLE) && req_i;

  // State-only outputs avoid a combinational handshake feedback delta loop.
  assign m_axi.awaddr=addr_q;
  assign m_axi.wdata=wdata_q;
  assign m_axi.wstrb=be_q;
  assign m_axi.araddr=addr_q;
  assign m_axi.awvalid=(state_q==WRITE_ADDR_DATA) && !aw_done_q;
  assign m_axi.wvalid=(state_q==WRITE_ADDR_DATA) && !w_done_q;
  assign m_axi.arvalid=(state_q==READ_ADDR);
  assign m_axi.rready=(state_q==READ_DATA);
  assign m_axi.bready=(state_q==WRITE_RESP);
  assign rvalid_o=((state_q==READ_DATA) && m_axi.rvalid) ||
                  ((state_q==WRITE_RESP) && m_axi.bvalid);
  assign rdata_o=(state_q==READ_DATA) ? m_axi.rdata : 32'b0;
  assign err_o=((state_q==READ_DATA) && m_axi.rvalid && m_axi.rresp!=0) ||
               ((state_q==WRITE_RESP) && m_axi.bvalid && m_axi.bresp!=0);
  always_comb begin
    state_d=state_q;
    case(state_q)
      IDLE: if(req_i) state_d=we_i ? WRITE_ADDR_DATA : READ_ADDR;
      READ_ADDR: if(m_axi.arready) state_d=READ_DATA;
      READ_DATA: if(m_axi.rvalid) state_d=IDLE;
      WRITE_ADDR_DATA: if((aw_done_q || m_axi.awready) &&
                         (w_done_q || m_axi.wready)) state_d=WRITE_RESP;
      WRITE_RESP: if(m_axi.bvalid) state_d=IDLE;
      default: state_d=IDLE;
    endcase
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      state_q   <= IDLE;
      addr_q    <= '0;
      wdata_q   <= '0;
      be_q      <= '0;
      aw_done_q <= 1'b0;
      w_done_q  <= 1'b0;
    end else begin
      state_q <= state_d;
      if (state_q == IDLE && req_i) begin
        addr_q  <= addr_i;
        wdata_q <= wdata_i;
        be_q    <= be_i;
      end
      if (state_q == WRITE_ADDR_DATA) begin
        if (m_axi.awvalid && m_axi.awready) aw_done_q <= 1'b1;
        if (m_axi.wvalid  && m_axi.wready)  w_done_q  <= 1'b1;
      end
      if ((state_q == WRITE_RESP && m_axi.bvalid) || state_q == IDLE) begin
        aw_done_q <= 1'b0;
        w_done_q  <= 1'b0;
      end
    end
  end
endmodule
