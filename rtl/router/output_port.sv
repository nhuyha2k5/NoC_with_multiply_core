`timescale 1ns/1ps
module output_port #(
	parameter data_width =34,
	parameter fifo_depth =4
)(
	input logic clk,
	input logic rst_n,
	input logic [data_width-1:0] data_in,
	input logic valid_in,
	input logic credit_in,
	output logic [data_width-1:0] data_out,
	output logic valid_out,
	output logic credit_ok
);
	logic [2:0] credit_count;
	always_ff@(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
		credit_count <= fifo_depth;
		end else begin
		case({credit_in , valid_out})
		2'b00: credit_count <= credit_count ;
		2'b01: credit_count <= credit_count - 1'b1;
		2'b10: credit_count <= credit_count + 1'b1;
		2'b11: credit_count <= credit_count ;
		endcase
	end
end
assign credit_ok = (credit_count > 3'd0)? 1'b1 : 1'b0;
assign data_out = data_in;
assign valid_out = valid_in && credit_ok;
endmodule