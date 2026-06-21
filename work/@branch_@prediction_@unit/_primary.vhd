library verilog;
use verilog.vl_types.all;
entity Branch_Prediction_Unit is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        branch_E        : in     vl_logic;
        jump_E          : in     vl_logic;
        branch          : in     vl_logic;
        pc_F            : in     vl_logic_vector(31 downto 0);
        pc_D            : in     vl_logic_vector(31 downto 0);
        pc_E            : in     vl_logic_vector(31 downto 0);
        pc_target       : in     vl_logic_vector(31 downto 0);
        pc_next         : out    vl_logic_vector(31 downto 0);
        pc_restore      : out    vl_logic_vector(31 downto 0);
        flush           : out    vl_logic;
        taken_F         : out    vl_logic
    );
end Branch_Prediction_Unit;
