// QoS round-robin output arbiter that locks ownership until the tail flit.
// Priority traffic is selected first. Per-request aging promotes a waiting
// normal packet, so sustained response traffic cannot starve requests.
//
// request_i is the grantable set (already gated by downstream credit).
// waiting_i marks inputs that hold a flit for this output but may be blocked by
// a condition shared by all inputs (credit). Ages advance while an input is
// waiting, so a credit stall cannot reset them; otherwise a high-priority
// stream that drains credit after every flit would starve lower classes.
module packet_arbiter #(
  parameter int N = 10,
  parameter int AGE_LIMIT = 15,
  localparam int AGE_W = (AGE_LIMIT <= 1) ? 1 : $clog2(AGE_LIMIT + 1),
  localparam int IDX_W = (N <= 1) ? 1 : $clog2(N)
) (
  input  logic         clk_i,
  input  logic         rst_ni,
  input  logic         accept_i = 1'b1,
  input  logic         aging_en_i = 1'b1,
  input  logic [AGE_W-1:0] age_limit_i = AGE_W'(AGE_LIMIT),
  input  logic [N-1:0] request_i,
  input  logic [N-1:0] waiting_i = '0,
  input  logic [N-1:0] priority_i,
  input  logic [N-1:0] tail_i,
  output logic [N-1:0] grant_o
);
  logic                locked_q;
  logic [IDX_W-1:0]    lock_idx_q;
  logic [IDX_W-1:0]    rr_q;
  logic [IDX_W-1:0]    selected_idx;
  logic                selected_valid;
  logic [AGE_W-1:0]    age_q[0:N-1];
  logic [N-1:0]        effective_priority;
  logic [N-1:0]        pending;

  assign pending = request_i | waiting_i;

  always_comb begin
    for (int i = 0; i < N; i++)
      effective_priority[i] = priority_i[i] || (aging_en_i && age_q[i] >= age_limit_i);
  end

  // Masked round-robin selection: no 32-bit modulo arithmetic or variable
  // 5-way indexing inside a nested priority scan. Priority class is chosen
  // first, then the least-significant candidate at/above the RR cursor.
  logic [N-1:0] eligible,above_cursor,candidates;
  always_comb begin
    eligible=request_i;
    if(|(request_i & effective_priority))eligible=request_i & effective_priority;
    above_cursor=eligible & ({N{1'b1}} << rr_q);
    candidates=(|above_cursor) ? above_cursor : eligible;
    grant_o=candidates & (~candidates + N'(1));
    if(locked_q)grant_o=request_i & (N'(1) << lock_idx_q);
    selected_valid=|grant_o;
    selected_idx='0;
    for(int i=0;i<N;i++)if(grant_o[i])selected_idx=IDX_W'(i);
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      locked_q   <= 1'b0;
      lock_idx_q <= '0;
      rr_q       <= '0;
      for (int i = 0; i < N; i++) age_q[i] <= '0;
    end else if (selected_valid && accept_i) begin
      if (tail_i[selected_idx]) begin
        locked_q <= 1'b0;
        rr_q <= (selected_idx == N-1) ? '0 : selected_idx + 1'b1;
      end else if (!locked_q) begin
        locked_q   <= 1'b1;
        lock_idx_q <= selected_idx;
      end
      for (int i = 0; i < N; i++) begin
        if (!pending[i] || grant_o[i])
          age_q[i] <= '0;
        else if (age_q[i] < AGE_LIMIT)
          age_q[i] <= age_q[i] + 1'b1;
      end
    end else begin
      for (int i = 0; i < N; i++) begin
        if (!pending[i])
          age_q[i] <= '0;
        else if (age_q[i] < AGE_LIMIT)
          age_q[i] <= age_q[i] + 1'b1;
      end
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk_i)
    if (rst_ni) begin
      assert ($onehot0(grant_o)) else $error("NoC arbiter grant is not one-hot");
      assert ((grant_o & ~request_i) == '0) else $error("NoC arbiter granted a non-requester");
    end
`endif
endmodule
