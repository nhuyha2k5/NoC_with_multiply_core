library verilog;
use verilog.vl_types.all;
entity MEM_WB is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        mem_pc_plus4    : in     vl_logic_vector(31 downto 0);
        mem_alu_result  : in     vl_logic_vector(31 downto 0);
        mem_mem_data    : in     vl_logic_vector(31 downto 0);
        mem_rd          : in     vl_logic_vector(4 downto 0);
        mem_regWrite    : in     vl_logic;
        mem_write_back  : in     vl_logic_vector(1 downto 0);
        wb_pc_plus4     : out    vl_logic_vector(31 downto 0);
        wb_alu_result   : out    vl_logic_vector(31 downto 0);
        wb_mem_data     : out    vl_logic_vector(31 downto 0);
        wb_rd           : out    vl_logic_vector(4 downto 0);
        wb_regWrite     : out    vl_logic;
        wb_write_back   : out    vl_logic_vector(1 downto 0)
    );
end MEM_WB;
