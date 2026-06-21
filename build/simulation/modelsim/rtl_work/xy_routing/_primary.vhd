library verilog;
use verilog.vl_types.all;
entity xy_routing is
    generic(
        xy_width        : integer := 2
    );
    port(
        cur_x           : in     vl_logic_vector;
        cur_y           : in     vl_logic_vector;
        des_x           : in     vl_logic_vector;
        des_y           : in     vl_logic_vector;
        \port\          : out    vl_logic_vector(4 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of xy_width : constant is 1;
end xy_routing;
