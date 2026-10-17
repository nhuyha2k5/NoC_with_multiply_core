// Physical router input containing two independent virtual-channel FIFOs.
module input_port_vc #(
  parameter int FLIT_WIDTH = 34,
  parameter int FIFO_DEPTH = 4,
  parameter logic [1:0] CURRENT_X = 2'd0,
  parameter logic [1:0] CURRENT_Y = 2'd0
) (
  input  logic                         clk_i,
  input  logic                         rst_ni,
  input  logic [FLIT_WIDTH-1:0]        flit_i,
  input  logic                         valid_i,
  input  logic                         vc_i,
  output logic [1:0]                   credit_o,
  input  logic [1:0]                   pop_i,
  output logic [2*FLIT_WIDTH-1:0]      flit_o,
  output logic [1:0]                   valid_o,
  output logic [2*5-1:0]               request_o,
  output logic [1:0]                   tail_o,
  output logic [3:0]                   qos_o,
  output logic [7:0]                   occupancy_o
);
  import router_pkg::*;

  logic [FLIT_WIDTH-1:0] fifo_data [0:1];
  logic [1:0] fifo_empty, fifo_full;
  logic [4:0] route_q [0:1];
  logic [1:0] route_valid_q;
  logic [4:0] route_now [0:1];
  logic [1:0] qos_q[0:1];
  logic [$clog2(FIFO_DEPTH+1)-1:0] counts[0:1];
  assign occupancy_o=8'(counts[0])+8'(counts[1]);

  for (genvar v = 0; v < 2; v++) begin : g_vc
    vc_fifo #(.WIDTH(FLIT_WIDTH), .DEPTH(FIFO_DEPTH)) u_fifo (
      .clk_i, .rst_ni,
      .push_i(valid_i && (vc_i == v[0])),
      .data_i(flit_i),
      .pop_i(pop_i[v]),
      .data_o(fifo_data[v]),
      .empty_o(fifo_empty[v]),
      .full_o(fifo_full[v]),
      .count_o(counts[v])
    );

    always_comb begin
      route_now[v] = xy_route(CURRENT_X, CURRENT_Y,
                              fifo_data[v][31:30], fifo_data[v][29:28]);
      flit_o[v*FLIT_WIDTH +: FLIT_WIDTH] = fifo_data[v];
      valid_o[v] = !fifo_empty[v];
      qos_o[v*2+:2]=route_valid_q[v]?qos_q[v]:fifo_data[v][2:1];
      tail_o[v] = !fifo_empty[v] &&
                  ((fifo_data[v][33:32] == FLIT_TAIL) ||
                   (fifo_data[v][33:32] == FLIT_HEADTAIL));
      request_o[v*5 +: 5] = '0;
      if (!fifo_empty[v]) begin
        if (route_valid_q[v])
          request_o[v*5 +: 5] = route_q[v];
        else if ((fifo_data[v][33:32] == FLIT_HEAD) ||
                 (fifo_data[v][33:32] == FLIT_HEADTAIL))
          request_o[v*5 +: 5] = route_now[v];
      end
    end

    always_ff @(posedge clk_i) begin
      if (!rst_ni) begin
        route_q[v]       <= '0;
        route_valid_q[v] <= 1'b0;
        qos_q[v]<=0;
      end else if (pop_i[v] && !fifo_empty[v]) begin
        if (fifo_data[v][33:32] == FLIT_HEAD) begin
          route_q[v]       <= route_now[v];
          route_valid_q[v] <= 1'b1;
          qos_q[v]<=fifo_data[v][2:1];
        end else if ((fifo_data[v][33:32] == FLIT_TAIL) ||
                     (fifo_data[v][33:32] == FLIT_HEADTAIL)) begin
          route_q[v]       <= '0;
          route_valid_q[v] <= 1'b0;
        end
      end
    end
  end

  assign credit_o[0] = pop_i[0] && !fifo_empty[0];
  assign credit_o[1] = pop_i[1] && !fifo_empty[1];

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (rst_ni && valid_i)
      assert (!fifo_full[vc_i] || pop_i[vc_i]) else $fatal(1,"NoC input VC overflow");
  end
`endif
endmodule
