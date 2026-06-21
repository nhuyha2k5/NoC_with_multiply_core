library verilog;
use verilog.vl_types.all;
entity control_unit is
    port(
        opcode          : in     vl_logic_vector(6 downto 0);
        funct3          : in     vl_logic_vector(2 downto 0);
        funct7          : in     vl_logic_vector(6 downto 0);
        regWrite_D      : out    vl_logic;
        imm_sel         : out    vl_logic_vector(2 downto 0);
        alu_srcA_D      : out    vl_logic;
        alu_srcB_D      : out    vl_logic;
        alu_ctrl        : out    vl_logic_vector(10 downto 0);
        branch_D        : out    vl_logic;
        bropcode        : out    vl_logic_vector(2 downto 0);
        jump_D          : out    vl_logic_vector(1 downto 0);
        load_sel_D      : out    vl_logic_vector(2 downto 0);
        store_sel_D     : out    vl_logic_vector(2 downto 0);
        memWrite_D      : out    vl_logic;
        write_back_D    : out    vl_logic_vector(1 downto 0);
        uses_rs1_D      : out    vl_logic;
        uses_rs2_D      : out    vl_logic
    );
end control_unit;
