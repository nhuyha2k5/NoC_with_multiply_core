// One credit-accounted FIFO for a single virtual channel.
module vc_fifo #(
  parameter int WIDTH = 34,
  parameter int DEPTH = 4,
  localparam int PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH),
  localparam int CNT_W = $clog2(DEPTH + 1)
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic             push_i,
  input  logic [WIDTH-1:0] data_i,
  input  logic             pop_i,
  output logic [WIDTH-1:0] data_o,
  output logic             empty_o,
  output logic             full_o,
  output logic [CNT_W-1:0] count_o
);
  logic [WIDTH-1:0] mem_q [0:DEPTH-1];
  logic [PTR_W-1:0] wr_ptr_q, rd_ptr_q;
  logic push_ok, pop_ok;

  assign empty_o = (count_o == '0);
  assign full_o  = (count_o == DEPTH);
  assign data_o  = mem_q[rd_ptr_q];
  assign push_ok = push_i && (!full_o || pop_ok);
  assign pop_ok  = pop_i && !empty_o;

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      wr_ptr_q <= '0;
      rd_ptr_q <= '0;
      count_o  <= '0;
    end else begin
      if (push_ok) begin
        mem_q[wr_ptr_q] <= data_i;
        wr_ptr_q <= (wr_ptr_q == DEPTH-1) ? '0 : wr_ptr_q + 1'b1;
      end
      if (pop_ok)
        rd_ptr_q <= (rd_ptr_q == DEPTH-1) ? '0 : rd_ptr_q + 1'b1;

      unique case ({push_ok, pop_ok})
        2'b10: count_o <= count_o + 1'b1;
        2'b01: count_o <= count_o - 1'b1;
        default: count_o <= count_o;
      endcase
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      assert (!(push_i && full_o && !pop_i)) else $error("NoC VC FIFO overflow");
      assert (!(pop_i && empty_o))           else $error("NoC VC FIFO underflow");
    end
  end
`endif
endmodule
