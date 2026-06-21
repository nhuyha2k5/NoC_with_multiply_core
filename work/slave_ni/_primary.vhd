library verilog;
use verilog.vl_types.all;
entity slave_ni is
    generic(
        DATA_WIDTH      : integer := 34;
        CURRENT_X       : vl_logic_vector(0 to 1) := (Hi1, Hi0);
        CURRENT_Y       : vl_logic_vector(0 to 1) := (Hi1, Hi0);
        MEM_DEPTH       : integer := 1024
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        rx_flit         : in     vl_logic_vector;
        rx_valid        : in     vl_logic;
        rx_credit       : out    vl_logic;
        tx_flit         : out    vl_logic_vector;
        tx_valid        : out    vl_logic;
        tx_credit       : in     vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of DATA_WIDTH : constant is 1;
    attribute mti_svvh_generic_type of CURRENT_X : constant is 1;
    attribute mti_svvh_generic_type of CURRENT_Y : constant is 1;
    attribute mti_svvh_generic_type of MEM_DEPTH : constant is 1;
end slave_ni;
