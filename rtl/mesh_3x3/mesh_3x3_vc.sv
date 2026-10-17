// Fixed 3x3 mesh wiring for the VC-capable routers.
module mesh_3x3_vc #(
  parameter int FLIT_WIDTH = 34,
  parameter int FIFO_DEPTH = 4
) (
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input logic [1:0] qos_mode_i=1,
  input logic qos_classes_i=1'b1,
  input logic qos_aging_i=1'b1,
  input logic [3:0] qos_age_i=15,
  input logic [7:0] qos_weights_i=8'h31,
  input logic counters_enable_i=1'b0,counters_clear_i=1'b0,
  output logic [1439:0] flit_count_o,packet_count_o,stall_count_o,
  output logic [359:0] fifo_peak_o,

  input  logic [FLIT_WIDTH-1:0]  local_tx_flit_i [0:8],
  input  logic                   local_tx_valid_i[0:8],
  input  logic                   local_tx_vc_i   [0:8],
  output logic [1:0]             local_tx_credit_o[0:8],

  output logic [FLIT_WIDTH-1:0]  local_rx_flit_o [0:8],
  output logic                   local_rx_valid_o[0:8],
  output logic                   local_rx_vc_o   [0:8],
  input  logic [1:0]             local_rx_credit_i[0:8]
);
  import router_pkg::*;

  logic [FLIT_WIDTH-1:0] link_flit [0:8][0:4];
  logic                  link_valid[0:8][0:4];
  logic                  link_vc   [0:8][0:4];
  logic [1:0]            input_credit[0:8][0:4];

  for (genvar x = 0; x < 3; x++) begin : g_x
    for (genvar y = 0; y < 3; y++) begin : g_y
      localparam int IDX = x*3 + y;
      localparam int IDX_N = x*3 + (y-1);
      localparam int IDX_S = x*3 + (y+1);
      localparam int IDX_W = (x-1)*3 + y;
      localparam int IDX_E = (x+1)*3 + y;

      logic [FLIT_WIDTH-1:0] router_in_flit [0:4];
      logic                  router_in_valid[0:4];
      logic                  router_in_vc   [0:4];
      logic [1:0]            router_out_credit[0:4];

      assign router_in_flit[PORT_LOCAL]  = local_tx_flit_i[IDX];
      assign router_in_valid[PORT_LOCAL] = local_tx_valid_i[IDX];
      assign router_in_vc[PORT_LOCAL]    = local_tx_vc_i[IDX];
      assign router_out_credit[PORT_LOCAL] = local_rx_credit_i[IDX];

      if (y == 0) begin : g_north_edge
        assign router_in_flit[PORT_NORTH] = '0;
        assign router_in_valid[PORT_NORTH] = 1'b0;
        assign router_in_vc[PORT_NORTH] = 1'b0;
        assign router_out_credit[PORT_NORTH] = '0;
      end else begin : g_north_link
        assign router_in_flit[PORT_NORTH] = link_flit[IDX_N][PORT_SOUTH];
        assign router_in_valid[PORT_NORTH] = link_valid[IDX_N][PORT_SOUTH];
        assign router_in_vc[PORT_NORTH] = link_vc[IDX_N][PORT_SOUTH];
        assign router_out_credit[PORT_NORTH] = input_credit[IDX_N][PORT_SOUTH];
      end

      if (y == 2) begin : g_south_edge
        assign router_in_flit[PORT_SOUTH] = '0;
        assign router_in_valid[PORT_SOUTH] = 1'b0;
        assign router_in_vc[PORT_SOUTH] = 1'b0;
        assign router_out_credit[PORT_SOUTH] = '0;
      end else begin : g_south_link
        assign router_in_flit[PORT_SOUTH] = link_flit[IDX_S][PORT_NORTH];
        assign router_in_valid[PORT_SOUTH] = link_valid[IDX_S][PORT_NORTH];
        assign router_in_vc[PORT_SOUTH] = link_vc[IDX_S][PORT_NORTH];
        assign router_out_credit[PORT_SOUTH] = input_credit[IDX_S][PORT_NORTH];
      end

      if (x == 0) begin : g_west_edge
        assign router_in_flit[PORT_WEST] = '0;
        assign router_in_valid[PORT_WEST] = 1'b0;
        assign router_in_vc[PORT_WEST] = 1'b0;
        assign router_out_credit[PORT_WEST] = '0;
      end else begin : g_west_link
        assign router_in_flit[PORT_WEST] = link_flit[IDX_W][PORT_EAST];
        assign router_in_valid[PORT_WEST] = link_valid[IDX_W][PORT_EAST];
        assign router_in_vc[PORT_WEST] = link_vc[IDX_W][PORT_EAST];
        assign router_out_credit[PORT_WEST] = input_credit[IDX_W][PORT_EAST];
      end

      if (x == 2) begin : g_east_edge
        assign router_in_flit[PORT_EAST] = '0;
        assign router_in_valid[PORT_EAST] = 1'b0;
        assign router_in_vc[PORT_EAST] = 1'b0;
        assign router_out_credit[PORT_EAST] = '0;
      end else begin : g_east_link
        assign router_in_flit[PORT_EAST] = link_flit[IDX_E][PORT_WEST];
        assign router_in_valid[PORT_EAST] = link_valid[IDX_E][PORT_WEST];
        assign router_in_vc[PORT_EAST] = link_vc[IDX_E][PORT_WEST];
        assign router_out_credit[PORT_EAST] = input_credit[IDX_E][PORT_WEST];
      end

      router_vc #(
        .FLIT_WIDTH(FLIT_WIDTH), .FIFO_DEPTH(FIFO_DEPTH),
        .CURRENT_X(x[1:0]), .CURRENT_Y(y[1:0])
      ) u_router (
        .clk_i, .rst_ni,
        .qos_mode_i,.qos_classes_i,.qos_aging_i,.qos_age_i,.qos_weights_i,.counters_enable_i,.counters_clear_i,
        .flit_count_o(flit_count_o[IDX*160+:160]),.packet_count_o(packet_count_o[IDX*160+:160]),
        .stall_count_o(stall_count_o[IDX*160+:160]),.fifo_peak_o(fifo_peak_o[IDX*40+:40]),
        .in_flit_i(router_in_flit),
        .in_valid_i(router_in_valid),
        .in_vc_i(router_in_vc),
        .in_credit_o(input_credit[IDX]),
        .out_flit_o(link_flit[IDX]),
        .out_valid_o(link_valid[IDX]),
        .out_vc_o(link_vc[IDX]),
        .out_credit_i(router_out_credit)
      );

      assign local_tx_credit_o[IDX] = input_credit[IDX][PORT_LOCAL];
      assign local_rx_flit_o[IDX]   = link_flit[IDX][PORT_LOCAL];
      assign local_rx_valid_o[IDX]  = link_valid[IDX][PORT_LOCAL];
      assign local_rx_vc_o[IDX]     = link_vc[IDX][PORT_LOCAL];
    end
  end
endmodule
