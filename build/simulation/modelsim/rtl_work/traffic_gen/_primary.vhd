library verilog;
use verilog.vl_types.all;
entity traffic_gen is
    generic(
        DEST_X          : vl_logic_vector(0 to 1) := (Hi1, Hi0);
        DEST_Y          : vl_logic_vector(0 to 1) := (Hi1, Hi0);
        LOAD_FACTOR     : integer := 10;
        WRITE_PROB      : integer := 50
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        obi_req         : out    vl_logic;
        obi_gnt         : in     vl_logic;
        obi_we          : out    vl_logic;
        obi_be          : out    vl_logic_vector(3 downto 0);
        obi_addr        : out    vl_logic_vector(31 downto 0);
        obi_wdata       : out    vl_logic_vector(31 downto 0);
        obi_rvalid      : in     vl_logic;
        obi_rdata       : in     vl_logic_vector(31 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of DEST_X : constant is 1;
    attribute mti_svvh_generic_type of DEST_Y : constant is 1;
    attribute mti_svvh_generic_type of LOAD_FACTOR : constant is 1;
    attribute mti_svvh_generic_type of WRITE_PROB : constant is 1;
end traffic_gen;
