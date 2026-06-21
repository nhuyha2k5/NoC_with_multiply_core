library verilog;
use verilog.vl_types.all;
entity output_port is
    generic(
        data_width      : integer := 34;
        fifo_depth      : integer := 4
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        data_in         : in     vl_logic_vector;
        valid_in        : in     vl_logic;
        credit_in       : in     vl_logic;
        data_out        : out    vl_logic_vector;
        valid_out       : out    vl_logic;
        credit_ok       : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of data_width : constant is 1;
    attribute mti_svvh_generic_type of fifo_depth : constant is 1;
end output_port;
