library verilog;
use verilog.vl_types.all;
entity PHT is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        predict_index   : in     vl_logic_vector(7 downto 0);
        update_index    : in     vl_logic_vector(7 downto 0);
        update_taken    : in     vl_logic;
        update_en       : in     vl_logic;
        prediction      : out    vl_logic_vector(1 downto 0)
    );
end PHT;
