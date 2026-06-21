`timescale 1ns/1ps
module crossbar_switch #(
	parameter data_width = 34
)(
	input logic [4:0] grant,
	input logic	[(5*data_width)-1:0] data_in,
	output logic [data_width-1:0] data_out,
	output logic valid_out
);
	always_comb begin
	case(grant) 
	5'b00001:begin
	data_out = data_in[33:0];
	valid_out = 1'b1;
	end
	5'b00010: begin
	data_out = data_in[67:34];
	valid_out = 1'b1;
	end
	5'b00100: begin
	data_out = data_in[101:68];
	valid_out = 1'b1;
	end
	5'b01000: begin
	data_out = data_in[135:102];
	valid_out = 1'b1;
	end
	5'b10000: begin
	data_out = data_in[169:136];
	valid_out = 1'b1;
	end
	default: begin
	data_out = 34'd0;
	valid_out = 1'b0;
	end
	endcase
end
endmodule	
	
			
	