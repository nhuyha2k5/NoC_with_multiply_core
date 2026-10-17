`timescale 1ns/1ps
module tb_axi4_burst_mesh;
  logic clk_i=0,rst_ni=0;always #5 clk_i=~clk_i;
  axi4_if axi(clk_i,rst_ni);
  axi_lite_if lite(clk_i,rst_ni);
  axi4_bfm host(.clk_i,.axi);
  axi_lite_bfm cpu(.clk_i,.axi(lite));
  logic[33:0] tx[0:8],rx[0:8];
  logic tv[0:8],tvc[0:8],rv[0:8],rvc[0:8];
  logic[1:0] tc[0:8],rc[0:8];
  axi4_to_mesh ni(.clk_i,.rst_ni,.s_axi(axi),.tx_flit_o(tx[6]),.tx_valid_o(tv[6]),.tx_vc_o(tvc[6]),
    .tx_credit_i(tc[6]),.rx_flit_i(rx[6]),.rx_valid_i(rv[6]),.rx_vc_i(rvc[6]),.rx_credit_o(rc[6]));
  axi_lite_to_mesh cpu_ni(.clk_i,.rst_ni,.s_axi(lite),.tx_flit_o(tx[0]),.tx_valid_o(tv[0]),.tx_vc_o(tvc[0]),
    .tx_credit_i(tc[0]),.rx_flit_i(rx[0]),.rx_valid_i(rv[0]),.rx_vc_i(rvc[0]),.rx_credit_o(rc[0]));
  shared_ram_node ram(.clk_i,.rst_ni,.noc_tx_flit_o(tx[4]),.noc_tx_valid_o(tv[4]),.noc_tx_vc_o(tvc[4]),
    .noc_tx_credit_i(tc[4]),.noc_rx_flit_i(rx[4]),.noc_rx_valid_i(rv[4]),.noc_rx_vc_i(rvc[4]),.noc_rx_credit_o(rc[4]));
  for(genvar n=0;n<9;n++)if(n!=0&&n!=4&&n!=6)begin
    assign tx[n]=0;assign tv[n]=0;assign tvc[n]=0;assign rc[n]=0;
  end
  mesh_3x3_vc mesh(.clk_i,.rst_ni,.local_tx_flit_i(tx),.local_tx_valid_i(tv),.local_tx_vc_i(tvc),
    .local_tx_credit_o(tc),.local_rx_flit_o(rx),.local_rx_valid_o(rv),.local_rx_vc_o(rvc),.local_rx_credit_i(rc));
  logic[31:0] data[256],d,mask;
  initial begin
    repeat(5)@(negedge clk_i);rst_ni=1;
    for(int length=1;length<=16;length++)begin
      host.write('h20008000,length,'h12340000+length,4'(length));
      host.send_read('h20008000,length,4'(length));
      host.receive_read(length,4'(length),data);
      for(int i=0;i<length;i++)assert(data[i]==host.value('h12340000+length,i))else $fatal(1,"Burst data");
    end
    host.write('h20008200,16,'h87654321,3,0,1);
    host.send_read('h20008200,16,7);host.receive_read(16,7,data);
    for(int i=0;i<16;i++)begin
      mask=i%2?32'hff00ff00:32'h00ff00ff;
      assert(data[i]==(host.value('h87654321,i)&mask))else $fatal(1,"Burst byte strobe");
    end
    // Two AR outstanding while write/read CPU traffic runs concurrently.
    fork
      begin
        host.send_read('h20008200,16,2);host.send_read('h20008000,16,9);
        host.receive_read(16,2,data);host.receive_read(16,9,data);
      end
      host.write('h20008400,16,'hfeedface,4);
      begin
        for(int i=0;i<16;i++)begin
          cpu.write('h20008600+i*4,32'(i));cpu.read('h20008600+i*4,d);
          assert(d==i)else $fatal(1,"Concurrent legacy memory");
        end
      end
    join
    host.write('h20008ffc,2,1,0,3); // forbidden 4-KiB crossing
    host.send_read('h20008ffc,2,1);host.receive_read(2,1,data,3);
    host.send_read('h20008001,3,1);host.receive_read(3,1,data,3);
    host.send_read('h30004000,4,1);host.receive_read(4,1,data,3);
    host.send_read('h20008000,17,1);host.receive_read(17,1,data,3);
    host.write('h20008000,17,1,0,3);
    host.write('h20008800,4,1,0,2,0,1); // malformed WLAST cannot write RAM
    cpu.read('h20008800,d);assert(d==0)else $fatal(1,"Rejected burst modified RAM");
    axi.arsize=1;host.send_read('h20008000,2,1);host.receive_read(2,1,data,3);axi.arsize=2;
    @(negedge clk_i);rst_ni=0;repeat(4)@(negedge clk_i);rst_ni=1;
    cpu.read('h20008400,d);assert(d=='hfeedface)else $fatal(1,"Burst RAM reset retention");
    $display("TEST_PASS: AXI4 burst 1..16, IDs, outstanding R/W, byte strobes, stalls, legacy coexistence, errors and reset");$finish;
  end
  initial begin #2000000;$fatal(1,"AXI burst mesh timeout");end
endmodule
