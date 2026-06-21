library verilog;
use verilog.vl_types.all;
entity fifo_buffer is
    generic(
        data_wild       : integer := 34;
        depth           : integer := 4
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        wr_en           : in     vl_logic;
        data_in         : in     vl_logic_vector;
        rd_en           : in     vl_logic;
        data_out        : out    vl_logic_vector;
        empty           : out    vl_logic;
        full            : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of data_wild : constant is 1;
    attribute mti_svvh_generic_type of depth : constant is 1;
end fifo_buffer;
