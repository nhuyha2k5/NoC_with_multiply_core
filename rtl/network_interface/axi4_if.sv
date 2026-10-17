// AXI4 memory-mapped, 32-bit data/address and 4-bit transaction IDs.
// Optional USER/REGION signals are not used by this platform.
interface axi4_if(input logic clk_i,rst_ni);
  logic [31:0] awaddr,wdata,araddr,rdata;
  logic [3:0] awid,bid,arid,rid,wstrb,awcache,arcache,awqos,arqos;
  logic [7:0] awlen,arlen;
  logic [2:0] awsize,arsize,awprot,arprot;
  logic [1:0] awburst,arburst,bresp,rresp;
  logic awlock,arlock,awvalid,awready,wlast,wvalid,wready,bvalid,bready;
  logic arvalid,arready,rlast,rvalid,rready;
  modport master(output awaddr,awid,awlen,awsize,awburst,awlock,awcache,awprot,awqos,awvalid,
    wdata,wstrb,wlast,wvalid,bready,araddr,arid,arlen,arsize,arburst,arlock,arcache,arprot,arqos,arvalid,rready,
    input awready,wready,bid,bresp,bvalid,arready,rid,rdata,rresp,rlast,rvalid);
  modport slave(input awaddr,awid,awlen,awsize,awburst,awlock,awcache,awprot,awqos,awvalid,
    wdata,wstrb,wlast,wvalid,bready,araddr,arid,arlen,arsize,arburst,arlock,arcache,arprot,arqos,arvalid,rready,
    output awready,wready,bid,bresp,bvalid,arready,rid,rdata,rresp,rlast,rvalid);
endinterface
