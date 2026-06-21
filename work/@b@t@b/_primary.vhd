library verilog;
use verilog.vl_types.all;
entity BTB is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        pc_F            : in     vl_logic_vector(31 downto 0);
        pc_E            : in     vl_logic_vector(31 downto 0);
        pc_target_E     : in     vl_logic_vector(31 downto 0);
        branch_E        : in     vl_logic;
        jump_E          : in     vl_logic;
        pc_out          : out    vl_logic_vector(31 downto 0);
        hit             : out    vl_logic
    );
end BTB;
