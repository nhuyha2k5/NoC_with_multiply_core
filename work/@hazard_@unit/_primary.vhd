library verilog;
use verilog.vl_types.all;
entity Hazard_Unit is
    port(
        if_id_rs1       : in     vl_logic_vector(4 downto 0);
        if_id_rs2       : in     vl_logic_vector(4 downto 0);
        if_id_uses_rs1  : in     vl_logic;
        if_id_uses_rs2  : in     vl_logic;
        id_ex_rd        : in     vl_logic_vector(4 downto 0);
        id_ex_wb_sel    : in     vl_logic_vector(1 downto 0);
        branch_mispredicted: in     vl_logic;
        stall_pc        : out    vl_logic;
        stall_if_id     : out    vl_logic;
        flush_id_ex     : out    vl_logic;
        flush_if_id     : out    vl_logic
    );
end Hazard_Unit;
