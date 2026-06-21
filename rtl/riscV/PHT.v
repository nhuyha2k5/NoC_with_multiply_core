// Pattern History Table (PHT)
module PHT (
    input clk,
    input rst_n,
    input [7:0] predict_index,
    input [7:0] update_index,
    input update_taken,
    input update_en,
    output [1:0] prediction
);
    reg [1:0] pht_table [255:0];
   
    wire [1:0] update_counter = pht_table[update_index];

    assign prediction = pht_table[predict_index];
integer i;
    always @(posedge clk or negedge rst_n) begin
		  
        if (!rst_n) begin
            for (i = 0; i < 256; i = i + 1)
                pht_table[i] <= 2'b01;
        end else if (update_en) begin
            if (update_taken) begin
                if (update_counter != 2'b11)
                    pht_table[update_index] <= update_counter + 2'b01;
                else
                    pht_table[update_index] <= update_counter;
            end else begin
                if (update_counter != 2'b00)
                    pht_table[update_index] <= update_counter - 2'b01;
                else
                    pht_table[update_index] <= update_counter;
            end
        end
    end
endmodule
