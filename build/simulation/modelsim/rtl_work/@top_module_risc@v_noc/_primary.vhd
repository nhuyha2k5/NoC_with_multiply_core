library verilog;
use verilog.vl_types.all;
entity Top_module_riscV_noc is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        start           : in     vl_logic;
        DataOrReg       : in     vl_logic;
        check_address   : in     vl_logic_vector(31 downto 0);
        value           : out    vl_logic_vector(31 downto 0);
        instr_addr_o    : out    vl_logic_vector(31 downto 0);
        instr_rdata_i   : in     vl_logic_vector(31 downto 0);
        mem_req_o       : out    vl_logic;
        mem_we_o        : out    vl_logic;
        mem_addr_o      : out    vl_logic_vector(31 downto 0);
        mem_wdata_o     : out    vl_logic_vector(31 downto 0);
        mem_store_sel_o : out    vl_logic_vector(2 downto 0);
        mem_load_sel_o  : out    vl_logic_vector(2 downto 0);
        mem_rdata_i     : in     vl_logic_vector(31 downto 0);
        stall_external  : in     vl_logic
    );
end Top_module_riscV_noc;
