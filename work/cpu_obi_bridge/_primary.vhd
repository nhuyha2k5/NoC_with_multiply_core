library verilog;
use verilog.vl_types.all;
entity cpu_obi_bridge is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        cpu_req         : in     vl_logic;
        cpu_we          : in     vl_logic;
        cpu_addr        : in     vl_logic_vector(31 downto 0);
        cpu_wdata       : in     vl_logic_vector(31 downto 0);
        cpu_store_sel   : in     vl_logic_vector(2 downto 0);
        cpu_stall       : out    vl_logic;
        cpu_rdata       : out    vl_logic_vector(31 downto 0);
        noc_req         : out    vl_logic;
        noc_gnt         : in     vl_logic;
        noc_we          : out    vl_logic;
        noc_be          : out    vl_logic_vector(3 downto 0);
        noc_addr        : out    vl_logic_vector(31 downto 0);
        noc_wdata       : out    vl_logic_vector(31 downto 0);
        noc_rvalid      : in     vl_logic;
        noc_rdata       : in     vl_logic_vector(31 downto 0);
        local_req       : out    vl_logic;
        local_gnt       : in     vl_logic;
        local_we        : out    vl_logic;
        local_be        : out    vl_logic_vector(3 downto 0);
        local_addr      : out    vl_logic_vector(31 downto 0);
        local_wdata     : out    vl_logic_vector(31 downto 0);
        local_rvalid    : in     vl_logic;
        local_rdata     : in     vl_logic_vector(31 downto 0)
    );
end cpu_obi_bridge;
