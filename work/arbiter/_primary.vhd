library verilog;
use verilog.vl_types.all;
entity arbiter is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        req             : in     vl_logic_vector(4 downto 0);
        req_priority    : in     vl_logic_vector(4 downto 0);
        tail_flag       : in     vl_logic_vector(4 downto 0);
        credit_ok       : in     vl_logic;
        grant           : out    vl_logic_vector(4 downto 0)
    );
end arbiter;
