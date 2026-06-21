library verilog;
use verilog.vl_types.all;
entity slave_node is
    generic(
        DATA_WIDTH      : integer := 34;
        CURRENT_X       : vl_logic_vector(0 to 1) := (Hi1, Hi0);
        CURRENT_Y       : vl_logic_vector(0 to 1) := (Hi1, Hi0);
        MEM_DEPTH       : integer := 1024
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        n_flit_in       : in     vl_logic_vector;
        n_valid_in      : in     vl_logic;
        n_credit_out    : out    vl_logic;
        n_flit_out      : out    vl_logic_vector;
        n_valid_out     : out    vl_logic;
        n_credit_in     : in     vl_logic;
        s_flit_in       : in     vl_logic_vector;
        s_valid_in      : in     vl_logic;
        s_credit_out    : out    vl_logic;
        s_flit_out      : out    vl_logic_vector;
        s_valid_out     : out    vl_logic;
        s_credit_in     : in     vl_logic;
        e_flit_in       : in     vl_logic_vector;
        e_valid_in      : in     vl_logic;
        e_credit_out    : out    vl_logic;
        e_flit_out      : out    vl_logic_vector;
        e_valid_out     : out    vl_logic;
        e_credit_in     : in     vl_logic;
        w_flit_in       : in     vl_logic_vector;
        w_valid_in      : in     vl_logic;
        w_credit_out    : out    vl_logic;
        w_flit_out      : out    vl_logic_vector;
        w_valid_out     : out    vl_logic;
        w_credit_in     : in     vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of DATA_WIDTH : constant is 1;
    attribute mti_svvh_generic_type of CURRENT_X : constant is 1;
    attribute mti_svvh_generic_type of CURRENT_Y : constant is 1;
    attribute mti_svvh_generic_type of MEM_DEPTH : constant is 1;
end slave_node;
