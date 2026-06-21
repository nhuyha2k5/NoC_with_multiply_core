`timescale 1ns/1ps
module input_port #(
	parameter current_x = 2'd1,
	parameter current_y = 2'd1
)(
	input logic clk,
	input logic rst_n,
	input logic [33:0] flit_in,
	input logic valid_in,
	input logic pop_en,
	output logic [33:0] flit_out,
	output logic valid_out,
	output logic [4:0] port_req,
	output logic is_prio,
	output logic credit_out,
	output logic is_tail
);
	logic fifo_empty;
	logic fifo_full;
	logic [4:0] xy_port_req;
	logic [1:0] flit_type;
	logic [1:0] des_x, des_y;
	
fifo_buffer #(
	.data_wild(34),
	.depth(4)
) m_fifo(
	.clk(clk),
	.rst_n(rst_n),
	.wr_en(valid_in && !fifo_full),
	.data_in(flit_in),
	.rd_en(pop_en),
	.data_out(flit_out),
	.empty(fifo_empty),
	.full(fifo_full)
);

assign valid_out = ~fifo_empty;
assign credit_out = pop_en && ~fifo_empty;
assign flit_type = flit_out[33:32];
assign des_x = flit_out[31:30];
assign des_y = flit_out[29:28];
assign is_tail = valid_out && (flit_type == 2'b10 || flit_type == 2'b11);
assign is_prio = valid_out && (flit_type == 2'b01) && flit_out[18];
xy_routing #(
	.xy_width(2)
) m_xy_routing(
	.cur_x(current_x),
	.cur_y(current_y),
	.des_x(des_x),
	.des_y(des_y),
	.port(xy_port_req)
);
always_comb begin
	if(valid_out && (flit_type == 2'b01 )) begin // head = 01 mới xét đến việc chọn cổng, body và tail thì cứ đi thẳng 
		port_req = xy_port_req;
	end 
		else begin
		port_req = 5'b00000;
	end
end
endmodule	