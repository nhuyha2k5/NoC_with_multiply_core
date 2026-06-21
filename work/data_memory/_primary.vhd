library verilog;
use verilog.vl_types.all;
entity data_memory is
    port(
        clk             : in     vl_logic;
        mem_write       : in     vl_logic;
        addr            : in     vl_logic_vector(31 downto 0);
        write_data      : in     vl_logic_vector(31 downto 0);
        load_sel        : in     vl_logic_vector(2 downto 0);
        store_sel       : in     vl_logic_vector(2 downto 0);
        read_data       : out    vl_logic_vector(31 downto 0);
        debug_addr      : in     vl_logic_vector(9 downto 0);
        debug_val       : out    vl_logic_vector(31 downto 0)
    );
end data_memory;
