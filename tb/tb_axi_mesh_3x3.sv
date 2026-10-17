`timescale 1ns/1ps
module tb_axi_mesh_3x3;
  logic clk_i = 1'b0;
  logic rst_ni = 1'b0;
  always #5 clk_i = ~clk_i;

  axi_lite_if cpu_axi(clk_i, rst_ni);
  axi_lite_if ram_axi(clk_i, rst_ni);

  logic [33:0] local_tx_flit[0:8], local_rx_flit[0:8];
  logic local_tx_valid[0:8], local_tx_vc[0:8];
  logic local_rx_valid[0:8], local_rx_vc[0:8];
  logic [1:0] local_tx_credit[0:8], local_rx_credit[0:8];
  logic [33:0] master_tx_flit, slave_tx_flit;
  logic master_tx_valid, master_tx_vc, slave_tx_valid, slave_tx_vc;
  logic [1:0] master_rx_credit, slave_rx_credit;

  always_comb begin
    for (int i=0;i<9;i++) begin
      local_tx_flit[i]='0; local_tx_valid[i]=1'b0; local_tx_vc[i]=1'b0;
      local_rx_credit[i]='0;
    end
    local_tx_flit[0]=master_tx_flit; local_tx_valid[0]=master_tx_valid; local_tx_vc[0]=master_tx_vc;
    local_rx_credit[0]=master_rx_credit;
    local_tx_flit[4]=slave_tx_flit; local_tx_valid[4]=slave_tx_valid; local_tx_vc[4]=slave_tx_vc;
    local_rx_credit[4]=slave_rx_credit;
  end

  mesh_3x3_vc u_mesh (
    .clk_i, .rst_ni,
    .local_tx_flit_i(local_tx_flit), .local_tx_valid_i(local_tx_valid),
    .local_tx_vc_i(local_tx_vc), .local_tx_credit_o(local_tx_credit),
    .local_rx_flit_o(local_rx_flit), .local_rx_valid_o(local_rx_valid),
    .local_rx_vc_o(local_rx_vc), .local_rx_credit_i(local_rx_credit)
  );

  axi_lite_to_mesh #(.CURRENT_X(0),.CURRENT_Y(0)) u_master_bridge (
    .clk_i,.rst_ni,.s_axi(cpu_axi),
    .tx_flit_o(master_tx_flit),.tx_valid_o(master_tx_valid),.tx_vc_o(master_tx_vc),
    .tx_credit_i(local_tx_credit[0]),
    .rx_flit_i(local_rx_flit[0]),.rx_valid_i(local_rx_valid[0]),.rx_vc_i(local_rx_vc[0]),
    .rx_credit_o(master_rx_credit)
  );

  mesh_to_axi_lite #(.CURRENT_X(1),.CURRENT_Y(1)) u_slave_bridge (
    .clk_i,.rst_ni,
    .rx_flit_i(local_rx_flit[4]),.rx_valid_i(local_rx_valid[4]),.rx_vc_i(local_rx_vc[4]),
    .rx_credit_o(slave_rx_credit),
    .tx_flit_o(slave_tx_flit),.tx_valid_o(slave_tx_valid),.tx_vc_o(slave_tx_vc),
    .tx_credit_i(local_tx_credit[4]),.m_axi(ram_axi)
  );

  axi_lite_ram #(.WORDS(256)) u_ram (.clk_i,.rst_ni,.s_axi(ram_axi));

  task automatic axi_write(input logic [31:0] addr,input logic [31:0] data);
    bit aw_done,w_done;
    begin
      aw_done=0; w_done=0;
      @(negedge clk_i);
      cpu_axi.awaddr=addr; cpu_axi.awvalid=1;
      cpu_axi.wdata=data; cpu_axi.wstrb=4'hf; cpu_axi.wvalid=1;
      cpu_axi.bready=1;
      while (!aw_done || !w_done) begin
        @(posedge clk_i);
        if (cpu_axi.awvalid && cpu_axi.awready) aw_done=1;
        if (cpu_axi.wvalid && cpu_axi.wready) w_done=1;
        @(negedge clk_i);
        if (aw_done) cpu_axi.awvalid=0;
        if (w_done) cpu_axi.wvalid=0;
      end
      while (!cpu_axi.bvalid) @(posedge clk_i);
      assert(cpu_axi.bresp==2'b00) else $fatal(1,"AXI write response error");
      @(negedge clk_i); cpu_axi.bready=0;
    end
  endtask

  task automatic axi_read(input logic [31:0] addr,output logic [31:0] data);
    begin
      @(negedge clk_i);
      cpu_axi.araddr=addr; cpu_axi.arvalid=1; cpu_axi.rready=1;
      while (!(cpu_axi.arvalid&&cpu_axi.arready)) @(posedge clk_i);
      @(negedge clk_i); cpu_axi.arvalid=0;
      while (!cpu_axi.rvalid) @(posedge clk_i);
      data=cpu_axi.rdata;
      assert(cpu_axi.rresp==2'b00) else $fatal(1,"AXI read response error");
      @(negedge clk_i); cpu_axi.rready=0;
    end
  endtask

  logic [31:0] read_data;
`ifdef TRACE_NOC
  always @(posedge clk_i) begin
    if (master_tx_valid) $display("%0t master tx vc%0d %h",$time,master_tx_vc,master_tx_flit);
    if (local_rx_valid[4]) $display("%0t node4 rx vc%0d %h",$time,local_rx_vc[4],local_rx_flit[4]);
    if (slave_tx_valid) $display("%0t slave tx vc%0d %h",$time,slave_tx_vc,slave_tx_flit);
    if (local_rx_valid[0]) $display("%0t node0 rx vc%0d %h",$time,local_rx_vc[0],local_rx_flit[0]);
  end
`endif
  initial begin
    cpu_axi.awaddr='0; cpu_axi.awvalid=0; cpu_axi.wdata='0; cpu_axi.wstrb='0;
    cpu_axi.wvalid=0; cpu_axi.bready=0; cpu_axi.araddr='0; cpu_axi.arvalid=0; cpu_axi.rready=0;
    repeat(5) @(posedge clk_i); rst_ni=1;
    repeat(3) @(posedge clk_i);
    axi_write(32'h2000_0010,32'hDEAD_BEEF);
    axi_read(32'h2000_0010,read_data);
    assert(read_data==32'hDEAD_BEEF) else $fatal(1,"Expected DEADBEEF, got %08x",read_data);
    $display("TEST_PASS: AXI4-Lite write/read crossed the 3x3 NoC using VC0 requests and VC1 responses");
    $finish;
  end

  initial begin
    #100000;
    $fatal(1,"Timeout");
  end
endmodule
