`timescale 1ns/1ps
module fifo_buffer #(
parameter data_wild = 34,
parameter depth = 4
)(
input logic clk,
input logic rst_n,
input logic wr_en,
input logic [data_wild-1 : 0] data_in,
input logic rd_en,
output logic [data_wild-1 :0] data_out,
output logic empty,
output logic full
);
logic [data_wild-1:0] mem[0:depth-1];
logic [1:0] wr_ptr;
logic [1:0] rd_ptr;
logic [2:0] count;

assign empty = (count==0);
assign full = (count==depth);
assign data_out = mem[rd_ptr];

always_ff@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
	wr_ptr<=2'd0;
	rd_ptr<=2'd0;
	count<=3'd0;
	end else begin
	if(wr_en && !full) begin
	mem[wr_ptr]<= data_in;
	wr_ptr<=wr_ptr+1'd1;
	end
	if(rd_en && !empty) begin
	rd_ptr<=rd_ptr +1'd1;
	end
	case({wr_en && !full, rd_en && !empty}) 
	2'b00: count<=count;
	2'b01: count<=count - 1'b1;
	2'b10: count<=count + 1'b1;
	2'b11: count<=count;
	endcase
	end
end
endmodule