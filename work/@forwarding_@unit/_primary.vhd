library verilog;
use verilog.vl_types.all;
entity Forwarding_Unit is
    port(
        id_ex_rs1       : in     vl_logic_vector(4 downto 0);
        id_ex_rs2       : in     vl_logic_vector(4 downto 0);
        ex_mem_rd       : in     vl_logic_vector(4 downto 0);
        ex_mem_regWrite : in     vl_logic;
        mem_wb_rd       : in     vl_logic_vector(4 downto 0);
        mem_wb_regWrite : in     vl_logic;
        forwardA        : out    vl_logic_vector(1 downto 0);
        forwardB        : out    vl_logic_vector(1 downto 0)
    );
end Forwarding_Unit;
