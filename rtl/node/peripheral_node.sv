// Merged peripheral node (4-core SoC, mesh (0,1)): UART 0x3000_0xxx,
// GPIO 0x3000_1xxx, mailbox 0x3000_3xxx and test-and-set locks 0x3000_7xxx
// behind one mesh endpoint.
//
// mesh_to_axi_lite executes one AXI-Lite transaction at a time and holds its
// address from AW/AR until the B/R handshake, so the slave is selected
// combinationally from the address and every response comes from the slave
// that received the request. Any other address is answered locally with
// DECERR and never reaches a slave.
module peripheral_node #(
  parameter logic [1:0] CURRENT_X = 2'd0,
  parameter logic [1:0] CURRENT_Y = 2'd1,
  parameter int CLOCK_HZ = 50_000_000,
  parameter int BAUD = 115_200,
  parameter int GPIO_WIDTH = 8,
  parameter int HARTS = 4,
  parameter int LOCKS = 16
) (
  input  logic clk_i, input logic rst_ni,
  output logic uart_tx_o, output logic uart_irq_o,
  input  logic [GPIO_WIDTH-1:0] gpio_i,
  output logic [GPIO_WIDTH-1:0] gpio_o, gpio_oe_o,
  output logic gpio_irq_o,
  output logic [HARTS-1:0] mailbox_irq_o,
  input  logic [33:0] noc_rx_flit_i, input logic noc_rx_valid_i, input logic noc_rx_vc_i,
  output logic [1:0] noc_rx_credit_o,
  output logic [33:0] noc_tx_flit_o, output logic noc_tx_valid_o, output logic noc_tx_vc_o,
  input  logic [1:0] noc_tx_credit_i
);
  localparam int NS = 4;     // 0 UART, 1 GPIO, 2 mailbox, 3 locks
  localparam int NONE = NS;

  axi_lite_if ep(clk_i, rst_ni);
  axi_lite_if s[NS](clk_i, rst_ni);

  mesh_to_axi_lite #(.CURRENT_X(CURRENT_X), .CURRENT_Y(CURRENT_Y)) u_endpoint (
    .clk_i, .rst_ni, .rx_flit_i(noc_rx_flit_i), .rx_valid_i(noc_rx_valid_i),
    .rx_vc_i(noc_rx_vc_i), .rx_credit_o(noc_rx_credit_o), .tx_flit_o(noc_tx_flit_o),
    .tx_valid_o(noc_tx_valid_o), .tx_vc_o(noc_tx_vc_o), .tx_credit_i(noc_tx_credit_i),
    .m_axi(ep)
  );

  function automatic int decode(input logic [31:0] addr);
    if (addr[31:16] != 16'h3000) return NONE;
    case (addr[15:12])
      4'h0: return 0;
      4'h1: return 1;
      4'h3: return 2;
      4'h7: return 3;
      default: return NONE;
    endcase
  endfunction

  int wsel, rsel;
  logic [NS-1:0] awready_s, wready_s, bvalid_s, arready_s, rvalid_s;
  logic [1:0]    bresp_s[NS], rresp_s[NS];
  logic [31:0]   rdata_s[NS];
  logic          err_b_q, err_r_q;

  assign wsel = decode(ep.awaddr);
  assign rsel = decode(ep.araddr);

  for (genvar k = 0; k < NS; k++) begin : g_port
    assign s[k].awaddr  = ep.awaddr;
    assign s[k].awvalid = ep.awvalid && wsel == k;
    assign s[k].wdata   = ep.wdata;
    assign s[k].wstrb   = ep.wstrb;
    assign s[k].wvalid  = ep.wvalid && wsel == k;
    assign s[k].bready  = ep.bready && wsel == k;
    assign s[k].araddr  = ep.araddr;
    assign s[k].arvalid = ep.arvalid && rsel == k;
    assign s[k].rready  = ep.rready && rsel == k;
    assign awready_s[k] = s[k].awready;
    assign wready_s[k]  = s[k].wready;
    assign bvalid_s[k]  = s[k].bvalid;
    assign bresp_s[k]   = s[k].bresp;
    assign arready_s[k] = s[k].arready;
    assign rvalid_s[k]  = s[k].rvalid;
    assign rresp_s[k]   = s[k].rresp;
    assign rdata_s[k]   = s[k].rdata;
  end

  // Unmapped address: accept AW+W (presented together by the endpoint) or AR
  // and return DECERR one cycle later.
  always_comb begin
    if (wsel == NONE) begin
      ep.awready = !err_b_q;
      ep.wready  = !err_b_q;
      ep.bvalid  = err_b_q;
      ep.bresp   = 2'b11;
    end else begin
      ep.awready = awready_s[wsel];
      ep.wready  = wready_s[wsel];
      ep.bvalid  = bvalid_s[wsel];
      ep.bresp   = bresp_s[wsel];
    end
    if (rsel == NONE) begin
      ep.arready = !err_r_q;
      ep.rvalid  = err_r_q;
      ep.rresp   = 2'b11;
      ep.rdata   = '0;
    end else begin
      ep.arready = arready_s[rsel];
      ep.rvalid  = rvalid_s[rsel];
      ep.rresp   = rresp_s[rsel];
      ep.rdata   = rdata_s[rsel];
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      err_b_q <= 1'b0;
      err_r_q <= 1'b0;
    end else begin
      if (wsel == NONE && ep.awvalid && ep.wvalid && !err_b_q) err_b_q <= 1'b1;
      else if (err_b_q && ep.bready) err_b_q <= 1'b0;
      if (rsel == NONE && ep.arvalid && !err_r_q) err_r_q <= 1'b1;
      else if (err_r_q && ep.rready) err_r_q <= 1'b0;
    end
  end

  axi_lite_uart #(.CLOCK_HZ(CLOCK_HZ), .BAUD(BAUD)) u_uart (
    .clk_i, .rst_ni, .tx_o(uart_tx_o), .irq_o(uart_irq_o), .s_axi(s[0])
  );
  axi_lite_gpio #(.WIDTH(GPIO_WIDTH)) u_gpio (
    .clk_i, .rst_ni, .gpio_i, .gpio_o, .gpio_oe_o, .irq_o(gpio_irq_o), .s_axi(s[1])
  );
  axi_lite_mailbox #(.HARTS(HARTS)) u_mailbox (
    .clk_i, .rst_ni, .irq_o(mailbox_irq_o), .s_axi(s[2])
  );
  axi_lite_tas #(.LOCKS(LOCKS)) u_locks (.clk_i, .rst_ni, .s_axi(s[3]));
endmodule
