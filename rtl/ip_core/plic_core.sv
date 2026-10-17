// Level-sensitive gateways, CONTEXTS machine contexts, standard PLIC offsets:
// priority 0x4*id, pending 0x1000, enable 0x2000+0x80*c, threshold
// 0x200000+0x1000*c, claim/complete 0x200004+0x1000*c. Context c is hart c.
// Claim atomically removes pending; gateway rearms only on valid completion.
module plic_core #(
  parameter int SOURCES=8,
  parameter int CONTEXTS=2,
  localparam int CTX_W=(CONTEXTS>1)?$clog2(CONTEXTS):1
)(
  input logic clk_i,rst_ni,
  input logic [SOURCES:1] sources_i,
  input logic wr_en_i,rd_en_i,
  input logic [23:0] wr_offset_i,rd_offset_i,
  input logic [31:0] wr_data_i,
  input logic [3:0] wr_strb_i,
  output logic [31:0] rd_data_o,
  output logic [1:0] wr_resp_o,rd_resp_o,
  output logic [CONTEXTS-1:0] irq_o
);
  logic [2:0] priority_q[1:SOURCES],threshold_q[0:CONTEXTS-1];
  logic [SOURCES:1] pending_q,inflight_q,enable_q[0:CONTEXTS-1];
  logic [CTX_W-1:0] owner_q[1:SOURCES];
  logic [31:0] winner[0:CONTEXTS-1];
  localparam int LEAVES=2**$clog2(SOURCES);
  localparam int ID_W=$clog2(SOURCES+1);
  logic [2:0] tree_priority[0:CONTEXTS-1][1:2*LEAVES-1];
  logic [ID_W-1:0] tree_id[0:CONTEXTS-1][1:2*LEAVES-1];
  for(genvar c=0;c<CONTEXTS;c++)begin:g_context
    for(genvar s=0;s<LEAVES;s++)begin:g_leaf
      if(s<SOURCES)begin
        assign tree_priority[c][LEAVES+s]=(pending_q[s+1]&&enable_q[c][s+1]&&priority_q[s+1]>threshold_q[c])?priority_q[s+1]:0;
        assign tree_id[c][LEAVES+s]=ID_W'(s+1);
      end else begin
        assign tree_priority[c][LEAVES+s]=0;assign tree_id[c][LEAVES+s]=0;
      end
    end
    for(genvar n=1;n<LEAVES;n++)begin:g_select
      // Left subtree wins equal priorities, preserving lowest-source-ID ties.
      assign tree_priority[c][n]=tree_priority[c][2*n]>=tree_priority[c][2*n+1]?
        tree_priority[c][2*n]:tree_priority[c][2*n+1];
      assign tree_id[c][n]=tree_priority[c][2*n]>=tree_priority[c][2*n+1]?
        tree_id[c][2*n]:tree_id[c][2*n+1];
    end
    assign winner[c]=tree_priority[c][1]!=0?32'(tree_id[c][1]):0;
    // Timing boundary: IRQ incurs one clock, claim still uses current pending.
    always_ff @(posedge clk_i)
      if(!rst_ni)irq_o[c]<=0;else irq_o[c]<=tree_priority[c][1]!=0;
  end
  function automatic logic valid_offset(input logic [23:0] off);
    logic ok;
    ok=(off>=4 && off<=SOURCES*4 && off[1:0]==0) || off==24'h001000;
    for(int c=0;c<CONTEXTS;c++)
      if(off==24'h002000+24'(c)*24'h80 || off==24'h200000+24'(c)*24'h1000 ||
         off==24'h200004+24'(c)*24'h1000) ok=1;
    return ok;
  endfunction
  always_comb begin
    rd_data_o=0;
    wr_resp_o=valid_offset(wr_offset_i)?0:2'b11;
    rd_resp_o=valid_offset(rd_offset_i)?0:2'b11;
    if(rd_offset_i>=4 && rd_offset_i<=SOURCES*4 && rd_offset_i[1:0]==0)
      rd_data_o={29'b0,priority_q[rd_offset_i>>2]};
    if(rd_offset_i==24'h001000)rd_data_o={{(31-SOURCES){1'b0}},pending_q,1'b0};
    for(int c=0;c<CONTEXTS;c++)begin
      if(rd_offset_i==24'h002000+24'(c)*24'h80)rd_data_o={{(31-SOURCES){1'b0}},enable_q[c],1'b0};
      if(rd_offset_i==24'h200000+24'(c)*24'h1000)rd_data_o={29'b0,threshold_q[c]};
      if(rd_offset_i==24'h200004+24'(c)*24'h1000)rd_data_o=winner[c];
    end
  end
  always_ff @(posedge clk_i) begin
    if(!rst_ni) begin
      pending_q<=0;inflight_q<=0;
      for(int c=0;c<CONTEXTS;c++) begin enable_q[c]<=0;threshold_q[c]<=0;end
      for(int s=1;s<=SOURCES;s++) begin priority_q[s]<=0;owner_q[s]<=0;end
    end else begin
      for(int s=1;s<=SOURCES;s++)
        if(sources_i[s] && !inflight_q[s]) pending_q[s]<=1;
      if(wr_en_i && wr_resp_o==0) begin
        if(wr_strb_i[0] && wr_offset_i>=4 && wr_offset_i<=SOURCES*4)
          priority_q[wr_offset_i>>2]<=wr_data_i[2:0];
        for(int c=0;c<CONTEXTS;c++) begin
          if(wr_offset_i==(24'h002000+24'(c)*24'h80))
            for(int s=1;s<=SOURCES;s++) if(wr_strb_i[s/8]) enable_q[c][s]<=wr_data_i[s];
          if(wr_offset_i==(24'h200000+24'(c)*24'h1000) && wr_strb_i[0]) threshold_q[c]<=wr_data_i[2:0];
          if(wr_offset_i==(24'h200004+24'(c)*24'h1000) && &wr_strb_i &&
             wr_data_i>0 && wr_data_i<=SOURCES)
            if(inflight_q[wr_data_i] && owner_q[wr_data_i]==CTX_W'(c) && enable_q[c][wr_data_i])
              inflight_q[wr_data_i]<=0;
        end
      end
      if(rd_en_i)
        for(int c=0;c<CONTEXTS;c++)
          if(rd_offset_i==(24'h200004+24'(c)*24'h1000) && winner[c]!=0) begin
            pending_q[winner[c]]<=0;inflight_q[winner[c]]<=1;owner_q[winner[c]]<=CTX_W'(c);
          end
    end
  end
`ifndef SYNTHESIS
  initial assert(SOURCES>=1&&SOURCES<=31&&CONTEXTS>=1&&CONTEXTS<=16)
    else $fatal(1,"PLIC supports 1..31 sources and 1..16 contexts");
`endif
endmodule
