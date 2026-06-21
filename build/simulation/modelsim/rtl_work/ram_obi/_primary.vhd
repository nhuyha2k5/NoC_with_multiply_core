library verilog;
use verilog.vl_types.all;
entity ram_obi is
    generic(
        MEM_SIZE_BYTES  : integer := 1024;
        INIT_FILE       : string  := ""
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        req_a_i         : in     vl_logic;
        gnt_a_o         : out    vl_logic;
        we_a_i          : in     vl_logic;
        be_a_i          : in     vl_logic_vector(3 downto 0);
        addr_a_i        : in     vl_logic_vector(31 downto 0);
        wdata_a_i       : in     vl_logic_vector(31 downto 0);
        rvalid_a_o      : out    vl_logic;
        rdata_a_o       : out    vl_logic_vector(31 downto 0);
        req_b_i         : in     vl_logic;
        gnt_b_o         : out    vl_logic;
        we_b_i          : in     vl_logic;
        be_b_i          : in     vl_logic_vector(3 downto 0);
        addr_b_i        : in     vl_logic_vector(31 downto 0);
        wdata_b_i       : in     vl_logic_vector(31 downto 0);
        rvalid_b_o      : out    vl_logic;
        rdata_b_o       : out    vl_logic_vector(31 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of MEM_SIZE_BYTES : constant is 1;
    attribute mti_svvh_generic_type of INIT_FILE : constant is 1;
end ram_obi;
