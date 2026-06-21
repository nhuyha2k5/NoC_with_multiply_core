`timescale 1ns/1ps
module xy_routing #(
parameter xy_width =2
)
(	
input logic [xy_width-1 :0] cur_x,
input logic [xy_width-1 :0] cur_y,
input logic [xy_width-1 :0] des_x,
input logic [xy_width-1 :0] des_y,
output logic [4:0] port

);
localparam LOCAL=0;
localparam north=1;
localparam south=2;
localparam east=3;
localparam west=4;

always_comb begin
	port= 5'b00000; //one-hot
	if(cur_x<des_x)begin
		port[east]=1'b1;
	end 
	else if(cur_x>des_x) begin
		port[west]=1'b1;
	end else begin
	if(cur_y<des_y) begin
		port[south]=1'b1;
	end
	else if(cur_y>des_y) begin
		port[north]=1'b1;
	end 
	else begin
		port[LOCAL]=1'b1;
	end
	end
	end
endmodule
