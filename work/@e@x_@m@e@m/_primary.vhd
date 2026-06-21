library verilog;
use verilog.vl_types.all;
entity EX_MEM is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        flush           : in     vl_logic;
        ex_pc_plus4     : in     vl_logic_vector(31 downto 0);
        ex_alu_result   : in     vl_logic_vector(31 downto 0);
        ex_rs2_data     : in     vl_logic_vector(31 downto 0);
        ex_rd           : in     vl_logic_vector(4 downto 0);
        ex_regWrite     : in     vl_logic;
        ex_load_sel     : in     vl_logic_vector(2 downto 0);
        ex_store_sel    : in     vl_logic_vector(2 downto 0);
        ex_memWrite     : in     vl_logic;
        ex_write_back   : in     vl_logic_vector(1 downto 0);
        mem_pc_plus4    : out    vl_logic_vector(31 downto 0);
        mem_alu_result  : out    vl_logic_vector(31 downto 0);
        mem_rs2_data    : out    vl_logic_vector(31 downto 0);
        mem_rd          : out    vl_logic_vector(4 downto 0);
        mem_regWrite    : out    vl_logic;
        mem_load_sel    : out    vl_logic_vector(2 downto 0);
        mem_store_sel   : out    vl_logic_vector(2 downto 0);
        mem_memWrite    : out    vl_logic;
        mem_write_back  : out    vl_logic_vector(1 downto 0)
    );
end EX_MEM;
