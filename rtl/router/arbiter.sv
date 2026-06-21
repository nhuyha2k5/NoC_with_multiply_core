`timescale 1ns/1ps
module arbiter (
    input  logic clk,
    input  logic rst_n,
    input  logic [4:0] req,         
    input  logic [4:0] req_priority, //Bit báo gói tin ưu tiên cao từ 5 cổng
    input  logic [4:0] tail_flag,   
    input  logic credit_ok,   
    output logic [4:0] grant        
);

    typedef enum logic {IDLE, LOCKED} state_t;
    state_t state, next_state;
    
    logic [4:0] locked_grant; 
    logic [4:0] next_grant;   
    logic [4:0] rr_ptr; 
    logic [4:0] high_prio_req;
    logic [4:0] arb_req; 
    
    assign high_prio_req = req & req_priority; // Lọc xem có ai vừa xin đi + vừa có ưu tiên cao không
    assign arb_req = (|high_prio_req) ? high_prio_req : req;
  

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            locked_grant <= 5'b00000;
            rr_ptr <= 5'b00001; 
        end else begin
            state <= next_state;
            if (state == IDLE && req != 5'b00000 && credit_ok) begin
                locked_grant <= next_grant; 
                rr_ptr <= next_grant;  
            end
        end
    end


    always_comb begin
        next_grant = 5'b00000;
        
        case (rr_ptr)
            5'b00001: begin 
                if      (arb_req[1]) next_grant = 5'b00010;
                else if (arb_req[2]) next_grant = 5'b00100;
                else if (arb_req[3]) next_grant = 5'b01000;
                else if (arb_req[4]) next_grant = 5'b10000;
                else if (arb_req[0]) next_grant = 5'b00001;
            end
            5'b00010: begin 
                if      (arb_req[2]) next_grant = 5'b00100;
                else if (arb_req[3]) next_grant = 5'b01000;
                else if (arb_req[4]) next_grant = 5'b10000;
                else if (arb_req[0]) next_grant = 5'b00001;
                else if (arb_req[1]) next_grant = 5'b00010;
            end
            5'b00100: begin
                if      (arb_req[3]) next_grant = 5'b01000;
                else if (arb_req[4]) next_grant = 5'b10000;
                else if (arb_req[0]) next_grant = 5'b00001;
                else if (arb_req[1]) next_grant = 5'b00010;
                else if (arb_req[2]) next_grant = 5'b00100;
            end
            5'b01000: begin 
                if      (arb_req[4]) next_grant = 5'b10000;
                else if (arb_req[0]) next_grant = 5'b00001;
                else if (arb_req[1]) next_grant = 5'b00010;
                else if (arb_req[2]) next_grant = 5'b00100;
                else if (arb_req[3]) next_grant = 5'b01000;
            end
            5'b10000: begin 
                if      (arb_req[0]) next_grant = 5'b00001;
                else if (arb_req[1]) next_grant = 5'b00010;
                else if (arb_req[2]) next_grant = 5'b00100;
                else if (arb_req[3]) next_grant = 5'b01000;
                else if (arb_req[4]) next_grant = 5'b10000;
            end
            default: next_grant = 5'b00000;
        endcase
    end

   
    always_comb begin
        next_state = state;
        grant = 5'b00000;
        case (state)
            IDLE: begin
                if (req != 5'b00000 && credit_ok) begin
                    grant = next_grant; 
                    next_state = LOCKED; 
                end
            end
            LOCKED: begin
                grant = credit_ok ? locked_grant : 5'b00000;              
                if ((tail_flag & locked_grant) != 5'b00000 && credit_ok) begin
                    next_state = IDLE; 
                end
            end
        endcase
    end

endmodule