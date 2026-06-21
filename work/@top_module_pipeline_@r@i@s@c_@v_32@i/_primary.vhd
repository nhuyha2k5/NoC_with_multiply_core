library verilog;
use verilog.vl_types.all;
entity Top_module_pipeline_RISC_V_32I is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        start           : in     vl_logic;
        DataOrReg       : in     vl_logic;
        check_address   : in     vl_logic_vector(31 downto 0);
        value           : out    vl_logic_vector(31 downto 0);
        instruction     : in     vl_logic_vector(31 downto 0);
        address         : in     vl_logic_vector(31 downto 0)
    );
end Top_module_pipeline_RISC_V_32I;
