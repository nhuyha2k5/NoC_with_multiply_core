library verilog;
use verilog.vl_types.all;
entity input_port is
    generic(
        current_x       : vl_logic_vector(0 to 1) := (Hi0, Hi1);
        current_y       : vl_logic_vector(0 to 1) := (Hi0, Hi1)
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        flit_in         : in     vl_logic_vector(33 downto 0);
        valid_in        : in     vl_logic;
        pop_en          : in     vl_logic;
        flit_out        : out    vl_logic_vector(33 downto 0);
        valid_out       : out    vl_logic;
        port_req        : out    vl_logic_vector(4 downto 0);
        is_prio         : out    vl_logic;
        credit_out      : out    vl_logic;
        is_tail         : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of current_x : constant is 1;
    attribute mti_svvh_generic_type of current_y : constant is 1;
end input_port;
