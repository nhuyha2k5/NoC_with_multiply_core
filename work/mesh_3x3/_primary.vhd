library verilog;
use verilog.vl_types.all;
entity mesh_3x3 is
    generic(
        DATA_WIDTH      : integer := 34
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        fmax_pc_00      : out    vl_logic_vector(31 downto 0);
        fmax_alu_00     : out    vl_logic_vector(31 downto 0);
        fmax_pc_22      : out    vl_logic_vector(31 downto 0);
        fmax_alu_22     : out    vl_logic_vector(31 downto 0);
        dummy_output    : out    vl_logic_vector(31 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of DATA_WIDTH : constant is 1;
end mesh_3x3;
