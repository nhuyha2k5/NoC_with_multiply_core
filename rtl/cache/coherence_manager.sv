// N-client MESI snoop controller (generalisation of the original two-core
// manager; coherence_manager_2core is a thin wrapper with N_CORES=2 and
// reproduces the original behaviour cycle for cycle).
//
// Every cache miss or ownership upgrade is ordered here. For each request the
// manager snoops all other caches (N_CORES-1 peers) at the same time and
// grants the requester only after every peer has acknowledged. A peer's
// snoop_valid drops as soon as that peer acknowledges, so each peer sees
// exactly one snoop per transaction. grant_shared is the OR of the peers'
// snoop_hit and grant_err the OR of their snoop_err. At most one peer can own
// a dirty copy, so at most one peer can refuse; the requester then returns a
// bus error instead of reading stale memory. Keeping this control plane
// separate from the NoC request/response VCs prevents a coherence/data
// dependency cycle.
//
// EARLY_RELEASE=1 (default): the manager is released as soon as the grant is
// issued, so the requester's memory read over the NoC overlaps with the next
// coherence transaction. A granted request stays "in flight" until the
// requester signals complete; a request to the same word as any other core's
// in-flight transaction is held back, which keeps per-address ordering.
// Different addresses proceed: an in-flight cache answers clean snoops
// immediately and delays dirty snoops until its own NoC access finishes (see
// mesi_dcache). EARLY_RELEASE=0 keeps the fully serialised behaviour (the
// manager waits for complete before taking any other request) for A/B runs.
//
// Arbitration is round robin over eligible requesters: a core that stays
// eligible loses at most N_CORES-1 consecutive decisions.
module coherence_manager #(
  parameter int N_CORES = 4,
  parameter bit EARLY_RELEASE = 1'b1,
  localparam int ID_W = (N_CORES > 1) ? $clog2(N_CORES) : 1
) (
  input  logic                     clk_i,
  input  logic                     rst_ni,
  input  logic [N_CORES-1:0]       req_valid_i,
  input  logic [N_CORES-1:0][1:0]  req_cmd_i,
  input  logic [N_CORES-1:0][31:0] req_addr_i,
  input  logic [N_CORES-1:0]       complete_i,
  output logic [N_CORES-1:0]       grant_o,
  output logic                     grant_shared_o,
  output logic                     grant_err_o,
  output logic [N_CORES-1:0]       snoop_valid_o,
  output logic                     snoop_cmd_o,
  output logic [31:0]              snoop_addr_o,
  input  logic [N_CORES-1:0]       snoop_ack_i,
  input  logic [N_CORES-1:0]       snoop_hit_i,
  input  logic [N_CORES-1:0]       snoop_err_i
);
  import coherence_pkg::*;

  typedef enum logic [1:0] {IDLE, SNOOP_PEERS, GRANT_REQUESTER, WAIT_COMPLETE} state_t;
  state_t state_q, state_d;

  logic [ID_W-1:0]    owner_q, owner_d, rr_q, pick;
  logic               found;
  logic [1:0]         cmd_q, cmd_d;
  logic [31:0]        addr_q, addr_d;
  logic [N_CORES-1:0] pending_q, pending_d;   // peers whose snoop is outstanding
  logic [N_CORES-1:0] acked;
  logic               peer_hit_q, peer_hit_d;
  logic               peer_err_q, peer_err_d;
  logic [N_CORES-1:0] inflight_q;
  logic [29:0]        inflight_addr_q[N_CORES];
  logic [N_CORES-1:0] eligible;

  // A core may start a new transaction unless another core has one in
  // flight for the same word (the requester's own in-flight bit blocks it).
  always_comb begin
    for (int c = 0; c < N_CORES; c++) begin
      eligible[c] = req_valid_i[c] && !inflight_q[c];
      for (int d = 0; d < N_CORES; d++)
        if (d != c && inflight_q[d] && inflight_addr_q[d] == req_addr_i[c][31:2])
          eligible[c] = 1'b0;
    end
  end

  // Round robin: first eligible core at or after rr_q.
  always_comb begin
    found = 1'b0;
    pick  = rr_q;
    for (int k = 0; k < N_CORES; k++) begin
      int c;
      c = int'(rr_q) + k;
      if (c >= N_CORES) c = c - N_CORES;
      if (!found && eligible[c]) begin
        found = 1'b1;
        pick  = ID_W'(c);
      end
    end
  end

  always_comb begin
    for (int c = 0; c < N_CORES; c++) begin
      grant_o[c]       = (state_q == GRANT_REQUESTER) && (owner_q == ID_W'(c));
      snoop_valid_o[c] = (state_q == SNOOP_PEERS) && pending_q[c];
    end
  end
  assign grant_shared_o = peer_hit_q;
  assign grant_err_o    = peer_err_q;
  assign snoop_cmd_o    = (cmd_q == COH_GETS) ? SNOOP_READ_SHARED : SNOOP_INVALIDATE;
  assign snoop_addr_o   = addr_q;
  assign acked          = pending_q & snoop_ack_i;

  always_comb begin
    state_d    = state_q;
    owner_d    = owner_q;
    cmd_d      = cmd_q;
    addr_d     = addr_q;
    pending_d  = pending_q;
    peer_hit_d = peer_hit_q;
    peer_err_d = peer_err_q;

    unique case (state_q)
      IDLE: begin
        peer_hit_d = 1'b0;
        peer_err_d = 1'b0;
        if (found) begin
          owner_d   = pick;
          cmd_d     = req_cmd_i[pick];
          addr_d    = req_addr_i[pick];
          pending_d = ~(N_CORES'(1) << pick);
          state_d   = SNOOP_PEERS;
        end
      end

      SNOOP_PEERS: begin
        pending_d  = pending_q & ~acked;
        peer_hit_d = peer_hit_q | (|(acked & snoop_hit_i));
        peer_err_d = peer_err_q | (|(acked & snoop_err_i));
        if (pending_d == '0)
          state_d = GRANT_REQUESTER;
      end

      GRANT_REQUESTER: state_d = EARLY_RELEASE ? IDLE : WAIT_COMPLETE;

      WAIT_COMPLETE: begin
        if (complete_i[owner_q])
          state_d = IDLE;
      end

      default: state_d = IDLE;
    endcase
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      state_q    <= IDLE;
      owner_q    <= '0;
      rr_q       <= '0;
      cmd_q      <= COH_GETS;
      addr_q     <= '0;
      pending_q  <= '0;
      peer_hit_q <= 1'b0;
      peer_err_q <= 1'b0;
      inflight_q <= '0;
      for (int c = 0; c < N_CORES; c++)
        inflight_addr_q[c] <= '0;
    end else begin
      state_q    <= state_d;
      owner_q    <= owner_d;
      cmd_q      <= cmd_d;
      addr_q     <= addr_d;
      pending_q  <= pending_d;
      peer_hit_q <= peer_hit_d;
      peer_err_q <= peer_err_d;
      if (state_q == GRANT_REQUESTER) begin
        rr_q <= (owner_q == ID_W'(N_CORES - 1)) ? '0 : owner_q + 1'b1;
        inflight_q[owner_q] <= 1'b1;
        inflight_addr_q[owner_q] <= addr_q[31:2];
      end
      for (int c = 0; c < N_CORES; c++)
        if (complete_i[c]) inflight_q[c] <= 1'b0;
    end
  end

`ifndef SYNTHESIS
  initial begin
    assert (N_CORES >= 2 && N_CORES <= 16)
      else $fatal(1, "coherence_manager supports 2..16 cores");
  end

  // Consecutive arbitration decisions a core lost while eligible.
  int unsigned lost_q[N_CORES];
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      for (int c = 0; c < N_CORES; c++) lost_q[c] <= 0;
    end else if (state_q == IDLE && found) begin
      for (int c = 0; c < N_CORES; c++)
        if (!eligible[c] || pick == ID_W'(c)) lost_q[c] <= 0;
        else lost_q[c] <= lost_q[c] + 1;
    end
  end

  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      assert ($onehot0(grant_o))
        else $error("MESI manager granted two requesters at once");
      if (state_q == SNOOP_PEERS)
        assert (!snoop_valid_o[owner_q])
          else $error("MESI manager snooped the requester itself");
      for (int c = 0; c < N_CORES; c++) begin
        for (int d = c + 1; d < N_CORES; d++)
          assert (!(inflight_q[c] && inflight_q[d] && inflight_addr_q[c] == inflight_addr_q[d]))
            else $error("MESI manager has two in-flight transactions for one word");
        assert (!complete_i[c] || inflight_q[c] ||
                (state_q == GRANT_REQUESTER && owner_q == ID_W'(c)))
          else $error("MESI complete without an in-flight grant (core %0d)", c);
        if (state_q == IDLE && found && eligible[c] && pick != ID_W'(c))
          assert (lost_q[c] < N_CORES - 1)
            else $error("MESI manager bypassed an eligible requester %0d times (core %0d)",
                        lost_q[c] + 1, c);
      end
    end
  end
`endif
endmodule
