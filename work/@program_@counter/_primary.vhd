library verilog;
use verilog.vl_types.all;
entity Program_Counter is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        start           : in     vl_logic;
        stall           : in     vl_logic;
        pc_next         : in     vl_logic_vector(31 downto 0);
        pc_out          : out    vl_logic_vector(31 downto 0)
    );
end Program_Counter;
