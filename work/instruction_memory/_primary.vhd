library verilog;
use verilog.vl_types.all;
entity instruction_memory is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        we              : in     vl_logic;
        addr_ext        : in     vl_logic_vector(31 downto 0);
        din_ext         : in     vl_logic_vector(31 downto 0);
        pc              : in     vl_logic_vector(31 downto 0);
        instr           : out    vl_logic_vector(31 downto 0)
    );
end instruction_memory;
