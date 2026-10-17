interface coherence_if (
  input logic clk_i,
  input logic rst_ni
);
  logic        req_valid;
  logic [1:0]  req_cmd;
  logic [31:0] req_addr;
  logic        grant;
  logic        grant_shared;
  logic        grant_err;     // peer could not write back dirty data: fail request
  logic        complete;

  logic        snoop_valid;
  logic        snoop_cmd;
  logic [31:0] snoop_addr;
  logic        snoop_ack;
  logic        snoop_hit;
  logic        snoop_err;     // dirty write-back exhausted retries; line kept

  modport cache (
    input  clk_i, rst_ni,
    output req_valid, req_cmd, req_addr, complete,
    input  grant, grant_shared, grant_err,
    input  snoop_valid, snoop_cmd, snoop_addr,
    output snoop_ack, snoop_hit, snoop_err
  );

  modport manager (
    input  clk_i, rst_ni,
    input  req_valid, req_cmd, req_addr, complete,
    output grant, grant_shared, grant_err,
    output snoop_valid, snoop_cmd, snoop_addr,
    input  snoop_ack, snoop_hit, snoop_err
  );
endinterface
