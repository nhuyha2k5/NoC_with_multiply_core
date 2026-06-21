library verilog;
use verilog.vl_types.all;
entity IF_ID is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        stall           : in     vl_logic;
        flush           : in     vl_logic;
        if_pc           : in     vl_logic_vector(31 downto 0);
        if_pc_plus4     : in     vl_logic_vector(31 downto 0);
        if_instr        : in     vl_logic_vector(31 downto 0);
        id_pc           : out    vl_logic_vector(31 downto 0);
        id_pc_plus4     : out    vl_logic_vector(31 downto 0);
        id_instr        : out    vl_logic_vector(31 downto 0)
    );
end IF_ID;
