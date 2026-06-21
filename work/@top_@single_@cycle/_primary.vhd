library verilog;
use verilog.vl_types.all;
entity Top_Single_Cycle is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        start           : in     vl_logic;
        inst_we         : in     vl_logic;
        inst_addr       : in     vl_logic_vector(31 downto 0);
        inst_data       : in     vl_logic_vector(31 downto 0);
        pc              : out    vl_logic_vector(31 downto 0);
        instr           : out    vl_logic_vector(31 downto 0)
    );
end Top_Single_Cycle;
