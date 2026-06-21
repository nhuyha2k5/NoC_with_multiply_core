library verilog;
use verilog.vl_types.all;
entity crossbar_switch is
    generic(
        data_width      : integer := 34
    );
    port(
        grant           : in     vl_logic_vector(4 downto 0);
        data_in         : in     vl_logic_vector;
        data_out        : out    vl_logic_vector;
        valid_out       : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of data_width : constant is 1;
end crossbar_switch;
