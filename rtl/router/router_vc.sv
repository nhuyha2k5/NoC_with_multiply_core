// Packet ownership belongs to an output VC, not the whole physical link.
// Independent VC reservations allow responses to bypass a credit-stalled request.
module router_vc #(
  parameter int FLIT_WIDTH=34,FIFO_DEPTH=4,
  parameter logic [1:0] CURRENT_X=0,CURRENT_Y=0,
  localparam int CREDIT_W=$clog2(FIFO_DEPTH+1)
)(
  input logic clk_i,rst_ni,
  input logic [1:0] qos_mode_i=1,
  input logic qos_classes_i=1'b1,
  input logic qos_aging_i=1'b1,
  input logic [3:0] qos_age_i=15,
  input logic [7:0] qos_weights_i=8'h31,
  input logic counters_enable_i=1'b0,counters_clear_i=1'b0,
  output logic [159:0] flit_count_o,packet_count_o,stall_count_o,
  output logic [39:0] fifo_peak_o,
  input logic [FLIT_WIDTH-1:0] in_flit_i[0:4],
  input logic in_valid_i[0:4],in_vc_i[0:4],
  output logic [1:0] in_credit_o[0:4],
  output logic [FLIT_WIDTH-1:0] out_flit_o[0:4],
  output logic out_valid_o[0:4],out_vc_o[0:4],
  input logic [1:0] out_credit_i[0:4]
);
  logic [2*FLIT_WIDTH-1:0] vc_flit[0:4];
  logic [1:0] vc_valid[0:4],vc_tail[0:4],vc_pop[0:4];
  logic [9:0] vc_request[0:4];
  logic [4:0] requests[0:4][0:1],waiting[0:4][0:1],grants[0:4][0:1],tails[0:1];
  logic [1:0] link_request[0:4],link_grant[0:4];
  logic [CREDIT_W-1:0] credit_q[0:4][0:1];
  logic [3:0] vc_qos[0:4];logic [7:0] occupancy[0:4];
  logic [4:0] packet_priority[0:4][0:1];logic [1:0] max_class[0:4][0:1];
  logic [1:0] link_priority[0:4];logic [3:0] budget[0:4][0:1];
  logic [1:0] budget_eligible[0:4];logic reload_budget[0:4],credit_stall[0:4];
  for(genvar p=0;p<5;p++) begin:g_input
    input_port_vc #(.FLIT_WIDTH(FLIT_WIDTH),.FIFO_DEPTH(FIFO_DEPTH),
      .CURRENT_X(CURRENT_X),.CURRENT_Y(CURRENT_Y)) u_input(
      .clk_i,.rst_ni,.flit_i(in_flit_i[p]),.valid_i(in_valid_i[p]),.vc_i(in_vc_i[p]),
      .credit_o(in_credit_o[p]),.pop_i(vc_pop[p]),.flit_o(vc_flit[p]),
      .valid_o(vc_valid[p]),.request_o(vc_request[p]),.tail_o(vc_tail[p]),
      .qos_o(vc_qos[p]),.occupancy_o(occupancy[p]));
  end
  always_comb begin
    for(int v=0;v<2;v++)
      for(int p=0;p<5;p++) tails[v][p]=vc_tail[p][v];
    for(int o=0;o<5;o++) begin
      credit_stall[o]=0;
      for(int v=0;v<2;v++) begin
        max_class[o][v]=0;packet_priority[o][v]=0;
        for(int p=0;p<5;p++)begin
          // Waiting ignores credit so a shared credit stall keeps ages advancing.
          waiting[o][v][p]=vc_valid[p][v] && vc_request[p][v*5+o];
          requests[o][v][p]=waiting[o][v][p] && credit_q[o][v]!=0;
        end
        for(int p=0;p<5;p++)begin
          if(requests[o][v][p]&&vc_qos[p][v*2+:2]>max_class[o][v])max_class[o][v]=vc_qos[p][v*2+:2];
          if(vc_valid[p][v]&&vc_request[p][v*5+o]&&credit_q[o][v]==0)credit_stall[o]=1;
        end
        for(int p=0;p<5;p++)packet_priority[o][v][p]=qos_classes_i&&max_class[o][v]!=0&&vc_qos[p][v*2+:2]==max_class[o][v];
        link_request[o][v]=|grants[o][v];
        budget_eligible[o][v]=link_request[o][v]&&budget[o][v]!=0;
      end
      reload_budget[o]=!(|budget_eligible[o]);
      case(qos_mode_i)
        0:link_priority[o]=0;
        2:link_priority[o]=reload_budget[o]?link_request[o]:budget_eligible[o];
        default:link_priority[o]=2'b10;
      endcase
    end
  end
  always_comb begin
    for(int p=0;p<5;p++) vc_pop[p]=0;
    for(int o=0;o<5;o++) begin
      out_flit_o[o]=0;out_valid_o[o]=0;out_vc_o[o]=0;
      for(int v=0;v<2;v++)
        for(int p=0;p<5;p++)
          if(link_grant[o][v] && grants[o][v][p]) begin
            out_flit_o[o]=vc_flit[p][v*FLIT_WIDTH+:FLIT_WIDTH];
            out_valid_o[o]=1;out_vc_o[o]=v[0];vc_pop[p][v]=1;
          end
    end
  end
  for(genvar o=0;o<5;o++) begin:g_output
    // Physical link is arbitrated every flit, with response priority + aging.
    packet_arbiter #(.N(2)) u_link_arbiter(
      .clk_i,.rst_ni,.request_i(link_request[o]),.priority_i(link_priority[o]),
      .aging_en_i(qos_aging_i),.age_limit_i(qos_age_i),
      .tail_i(2'b11),.grant_o(link_grant[o]),.accept_i(1'b1));
    for(genvar v=0;v<2;v++) begin:g_vc
      packet_arbiter #(.N(5)) u_packet_arbiter(
        .clk_i,.rst_ni,.request_i(requests[o][v]),.waiting_i(waiting[o][v]),
        .priority_i(packet_priority[o][v]),.aging_en_i(qos_aging_i),.age_limit_i(qos_age_i),
        .tail_i(tails[v]),.grant_o(grants[o][v]),.accept_i(link_grant[o][v]));
      always_ff @(posedge clk_i)
        if(!rst_ni) credit_q[o][v]<=FIFO_DEPTH;
        else case({out_credit_i[o][v],out_valid_o[o] && out_vc_o[o]==v[0]})
          2'b10: if(credit_q[o][v]<FIFO_DEPTH) credit_q[o][v]<=credit_q[o][v]+1'b1;
          2'b01: credit_q[o][v]<=credit_q[o][v]-1'b1;
          default: ;
        endcase
      always_ff @(posedge clk_i)begin
        if(!rst_ni||qos_mode_i!=2)budget[o][v]<=qos_weights_i[v*4+:4];
        else if(reload_budget[o])budget[o][v]<=qos_weights_i[v*4+:4]-(link_grant[o][v]?4'd1:4'd0);
        else if(link_grant[o][v]&&budget[o][v]!=0)budget[o][v]<=budget[o][v]-1'b1;
      end
`ifndef SYNTHESIS
      always @(posedge clk_i) if(rst_ni) begin
        assert(credit_q[o][v]<=FIFO_DEPTH) else $fatal(1,"Credit overflow");
        assert(!(out_valid_o[o] && out_vc_o[o]==v[0] && credit_q[o][v]==0))
          else $fatal(1,"Send without credit");
      end
`endif
    end
    always_ff @(posedge clk_i)begin
      if(!rst_ni||counters_clear_i)begin
        flit_count_o[o*32+:32]<=0;packet_count_o[o*32+:32]<=0;
        stall_count_o[o*32+:32]<=0;fifo_peak_o[o*8+:8]<=0;
      end else if(counters_enable_i)begin
        if(out_valid_o[o]&&flit_count_o[o*32+:32]!=32'hffffffff)flit_count_o[o*32+:32]<=flit_count_o[o*32+:32]+1'b1;
        if(out_valid_o[o]&&out_flit_o[o][32]&&packet_count_o[o*32+:32]!=32'hffffffff)
          packet_count_o[o*32+:32]<=packet_count_o[o*32+:32]+1'b1;
        if(credit_stall[o]&&stall_count_o[o*32+:32]!=32'hffffffff)stall_count_o[o*32+:32]<=stall_count_o[o*32+:32]+1'b1;
        if(occupancy[o]>fifo_peak_o[o*8+:8])fifo_peak_o[o*8+:8]<=occupancy[o];
      end
    end
  end
endmodule
