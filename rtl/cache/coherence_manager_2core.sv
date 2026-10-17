// Two-client MESI snoop controller (interface wrapper).
//
// The protocol logic lives in coherence_manager. With N_CORES=2 it is the
// original two-core manager cycle for cycle: the single peer is snooped, the
// requester is granted after the peer's ack, grant_err reports a refused dirty
// write-back, and EARLY_RELEASE selects overlapped or fully serialised
// transactions. This module keeps the original name, parameter and ports so
// the two-core SoC and testbenches are unchanged.
module coherence_manager_2core #(
  parameter bit EARLY_RELEASE = 1'b1
) (
  input  logic          clk_i,
  input  logic          rst_ni,
  coherence_if.manager  core0,
  coherence_if.manager  core1
);
  logic [1:0] grant, snoop_valid;
  logic       grant_shared, grant_err, snoop_cmd;
  logic [31:0] snoop_addr;

  coherence_manager #(.N_CORES(2), .EARLY_RELEASE(EARLY_RELEASE)) u_manager (
    .clk_i, .rst_ni,
    .req_valid_i({core1.req_valid, core0.req_valid}),
    .req_cmd_i({core1.req_cmd, core0.req_cmd}),
    .req_addr_i({core1.req_addr, core0.req_addr}),
    .complete_i({core1.complete, core0.complete}),
    .grant_o(grant), .grant_shared_o(grant_shared), .grant_err_o(grant_err),
    .snoop_valid_o(snoop_valid), .snoop_cmd_o(snoop_cmd), .snoop_addr_o(snoop_addr),
    .snoop_ack_i({core1.snoop_ack, core0.snoop_ack}),
    .snoop_hit_i({core1.snoop_hit, core0.snoop_hit}),
    .snoop_err_i({core1.snoop_err, core0.snoop_err})
  );

  assign core0.grant        = grant[0];
  assign core1.grant        = grant[1];
  assign core0.grant_shared = grant_shared;
  assign core1.grant_shared = grant_shared;
  assign core0.grant_err    = grant_err;
  assign core1.grant_err    = grant_err;
  assign core0.snoop_valid  = snoop_valid[0];
  assign core1.snoop_valid  = snoop_valid[1];
  assign core0.snoop_cmd    = snoop_cmd;
  assign core1.snoop_cmd    = snoop_cmd;
  assign core0.snoop_addr   = snoop_addr;
  assign core1.snoop_addr   = snoop_addr;
endmodule
