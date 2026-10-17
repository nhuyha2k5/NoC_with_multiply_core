// Shared packet format, port numbering and XY-routing helpers for NoC v2.
package router_pkg;
  parameter int FLIT_WIDTH = 34;
  parameter int NUM_PORTS  = 5;
  parameter int NUM_VCS    = 2;

  localparam int PORT_LOCAL = 0;
  localparam int PORT_NORTH = 1;
  localparam int PORT_SOUTH = 2;
  localparam int PORT_EAST  = 3;
  localparam int PORT_WEST  = 4;

  localparam logic [1:0] FLIT_BODY     = 2'b00;
  localparam logic [1:0] FLIT_HEAD     = 2'b01;
  localparam logic [1:0] FLIT_TAIL     = 2'b10;
  localparam logic [1:0] FLIT_HEADTAIL = 2'b11;

  localparam logic [2:0] NOC_READ_REQ   = 3'd0;
  localparam logic [2:0] NOC_WRITE_REQ  = 3'd1;
  localparam logic [2:0] NOC_READ_RESP  = 3'd2;
  localparam logic [2:0] NOC_WRITE_RESP = 3'd3;
  localparam logic [2:0] NOC_ERROR_RESP = 3'd4;
  // VC0: burst read/write. VC1: burst read response uses opcode 5.
  // Header [14:11]=tag, [10:3]=AXLEN, [2:1]=QoS, [16:15]=legacy RESP.
  localparam logic [2:0] NOC_BURST_READ = 3'd5;
  localparam logic [2:0] NOC_BURST_WRITE = 3'd6;

  // Address map. Default: 4-core SoC (Step 3). Define NOC_LEGACY_2CORE_MAP
  // to get the original 2-core map used by the block-level testbenches.
  //   0x0200_0000..0x0200_BFFF CLINT                         -> (1,2)
  //   0x0C00_0000..0x0C20_3FFF PLIC, 4 contexts              -> (1,2)
  //   0x2000_0000..0x2001_FFFF shared RAM 128 KB             -> (1,1)
  //     (0x2000_8000..0x2000_BFFF noncoherent engine window)
  //   0x3000_0xxx UART, 1xxx GPIO, 3xxx mailbox, 7xxx locks  -> (0,1)
  //   0x3000_4xxx DMA -> (1,0), 5xxx accelerator -> (2,1), 6xxx NoC control -> (1,2)
`ifdef NOC_LEGACY_2CORE_MAP
  localparam logic [31:0] SHARED_END = 32'h2001_0000;
`else
  localparam logic [31:0] SHARED_END = 32'h2002_0000;
`endif
  function automatic logic shared_address(input logic [31:0] addr);
    return addr >= 32'h2000_0000 && addr < SHARED_END;
  endfunction
  function automatic logic cache_address(input logic [31:0] addr);
    return addr[1:0]==0 && shared_address(addr) && !(addr >= 32'h2000_8000 && addr < 32'h2000_c000);
  endfunction
  function automatic logic engine_range(input logic [31:0] addr, input logic [31:0] bytes);
    logic [32:0] finish;
    finish = {1'b0,addr} + {1'b0,bytes};
    return addr[1:0] == 0 && bytes[1:0] == 0 &&
      addr >= 32'h2000_8000 && finish <= 33'h02000_c000;
  endfunction
`ifdef NOC_LEGACY_2CORE_MAP
  function automatic logic supported_address(input logic [31:0] addr);
    return shared_address(addr) ||
      (addr >= 32'h3000_0000 && addr < 32'h3000_7000) ||
      (addr >= 32'h0c00_0000 && addr < 32'h0c20_2000);
  endfunction
  function automatic logic [3:0] address_coord(input logic [31:0] addr);
    if (shared_address(addr)) return {2'd1,2'd1};
    if (addr[31:24] == 8'h0c) return {2'd1,2'd2};
    case (addr[15:12])
      0: return {2'd0,2'd1};
      1: return {2'd1,2'd0};
      2: return {2'd1,2'd2};
      3: return {2'd2,2'd1};
      4: return {2'd2,2'd0};
      5: return {2'd0,2'd2};
      6: return {2'd1,2'd2};
      default: return 4'b0;
    endcase
  endfunction
`else
  // 0x3000_2xxx (old timer) is no longer mapped: the CLINT replaced it.
  function automatic logic supported_address(input logic [31:0] addr);
    return shared_address(addr) ||
      (addr >= 32'h3000_0000 && addr < 32'h3000_8000 && addr[15:12] != 4'h2) ||
      (addr >= 32'h0200_0000 && addr < 32'h0200_c000) ||
      (addr >= 32'h0c00_0000 && addr < 32'h0c20_4000);
  endfunction
  function automatic logic [3:0] address_coord(input logic [31:0] addr);
    if (shared_address(addr)) return {2'd1,2'd1};
    if (addr[31:24] == 8'h0c || addr[31:24] == 8'h02) return {2'd1,2'd2};
    case (addr[15:12])
      0, 1, 3, 7: return {2'd0,2'd1};
      4: return {2'd1,2'd0};
      5: return {2'd2,2'd1};
      6: return {2'd1,2'd2};
      default: return 4'b0;
    endcase
  endfunction
`endif

  function automatic logic [4:0] xy_route(
    input logic [1:0] current_x,
    input logic [1:0] current_y,
    input logic [1:0] dest_x,
    input logic [1:0] dest_y
  );
    logic [4:0] route;
    begin
      route = 5'b0;
      if (dest_x > current_x)       route[PORT_EAST] = 1'b1;
      else if (dest_x < current_x)  route[PORT_WEST] = 1'b1;
      else if (dest_y > current_y)  route[PORT_SOUTH] = 1'b1;
      else if (dest_y < current_y)  route[PORT_NORTH] = 1'b1;
      else                          route[PORT_LOCAL] = 1'b1;
      return route;
    end
  endfunction

  function automatic logic [33:0] make_head(
    input logic [1:0] dest_x,
    input logic [1:0] dest_y,
    input logic [1:0] src_x,
    input logic [1:0] src_y,
    input logic [2:0] opcode,
    input logic [3:0] strb
  );
    return {FLIT_HEAD, dest_x, dest_y, src_x, src_y, opcode, strb, 17'b0};
  endfunction
endpackage
