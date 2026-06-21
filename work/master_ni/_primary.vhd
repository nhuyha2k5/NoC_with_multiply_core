library verilog;
use verilog.vl_types.all;
entity master_ni is
    generic(
        DATA_WIDTH      : integer := 34;
        CURRENT_X       : vl_logic_vector(0 to 1) := (Hi0, Hi0);
        CURRENT_Y       : vl_logic_vector(0 to 1) := (Hi0, Hi0);
        PRIORITY        : vl_logic := Hi0
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        obi_req         : in     vl_logic;
        obi_gnt         : out    vl_logic;
        obi_we          : in     vl_logic;
        obi_be          : in     vl_logic_vector(3 downto 0);
        obi_addr        : in     vl_logic_vector(31 downto 0);
        obi_wdata       : in     vl_logic_vector(31 downto 0);
        obi_rvalid      : out    vl_logic;
        obi_rdata       : out    vl_logic_vector(31 downto 0);
        tx_flit         : out    vl_logic_vector;
        tx_valid        : out    vl_logic;
        tx_credit       : in     vl_logic;
        rx_flit         : in     vl_logic_vector;
        rx_valid        : in     vl_logic;
        rx_credit       : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of DATA_WIDTH : constant is 1;
    attribute mti_svvh_generic_type of CURRENT_X : constant is 1;
    attribute mti_svvh_generic_type of CURRENT_Y : constant is 1;
    attribute mti_svvh_generic_type of PRIORITY : constant is 1;
end master_ni;
