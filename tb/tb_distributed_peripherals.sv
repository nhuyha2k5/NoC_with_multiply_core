`timescale 1ns/1ps

module tb_distributed_peripherals;
  logic clk_i = 1'b0;
  logic rst_ni = 1'b0;
  always #5 clk_i = ~clk_i;

  axi_lite_if cpu_axi(clk_i, rst_ni);
  logic [33:0] local_tx_flit[0:8], local_rx_flit[0:8];
  logic local_tx_valid[0:8], local_tx_vc[0:8];
  logic local_rx_valid[0:8], local_rx_vc[0:8];
  logic [1:0] local_tx_credit[0:8], local_rx_credit[0:8];

  logic [33:0] master_flit, uart_flit, gpio_flit, timer_flit, mailbox_flit;
  logic master_valid, master_vc, uart_valid, uart_vc, gpio_valid, gpio_vc;
  logic timer_valid, timer_vc, mailbox_valid, mailbox_vc;
  logic [1:0] master_credit, uart_credit, gpio_credit, timer_credit, mailbox_credit;
  logic uart_tx, uart_irq, timer_irq, irq0, irq1;
  logic [7:0] gpio_i = 8'hA6;
  logic [7:0] gpio_o, gpio_oe;

  always_comb begin
    for (int i = 0; i < 9; i++) begin
      local_tx_flit[i] = '0;
      local_tx_valid[i] = 1'b0;
      local_tx_vc[i] = 1'b0;
      local_rx_credit[i] = '0;
    end
    local_tx_flit[0]=master_flit; local_tx_valid[0]=master_valid; local_tx_vc[0]=master_vc; local_rx_credit[0]=master_credit;
    local_tx_flit[1]=uart_flit; local_tx_valid[1]=uart_valid; local_tx_vc[1]=uart_vc; local_rx_credit[1]=uart_credit;
    local_tx_flit[3]=gpio_flit; local_tx_valid[3]=gpio_valid; local_tx_vc[3]=gpio_vc; local_rx_credit[3]=gpio_credit;
    local_tx_flit[5]=timer_flit; local_tx_valid[5]=timer_valid; local_tx_vc[5]=timer_vc; local_rx_credit[5]=timer_credit;
    local_tx_flit[7]=mailbox_flit; local_tx_valid[7]=mailbox_valid; local_tx_vc[7]=mailbox_vc; local_rx_credit[7]=mailbox_credit;
  end

  mesh_3x3_vc u_mesh (
    .clk_i, .rst_ni, .local_tx_flit_i(local_tx_flit),
    .local_tx_valid_i(local_tx_valid), .local_tx_vc_i(local_tx_vc),
    .local_tx_credit_o(local_tx_credit), .local_rx_flit_o(local_rx_flit),
    .local_rx_valid_o(local_rx_valid), .local_rx_vc_o(local_rx_vc),
    .local_rx_credit_i(local_rx_credit)
  );

  axi_lite_to_mesh #(.CURRENT_X(0), .CURRENT_Y(0)) u_master (
    .clk_i, .rst_ni, .s_axi(cpu_axi), .tx_flit_o(master_flit),
    .tx_valid_o(master_valid), .tx_vc_o(master_vc), .tx_credit_i(local_tx_credit[0]),
    .rx_flit_i(local_rx_flit[0]), .rx_valid_i(local_rx_valid[0]),
    .rx_vc_i(local_rx_vc[0]), .rx_credit_o(master_credit)
  );
  uart_node #(.CLOCK_HZ(1_000_000)) u_uart (
    .clk_i,.rst_ni,.uart_tx_o(uart_tx),.uart_irq_o(uart_irq),
    .noc_rx_flit_i(local_rx_flit[1]),.noc_rx_valid_i(local_rx_valid[1]),.noc_rx_vc_i(local_rx_vc[1]),.noc_rx_credit_o(uart_credit),
    .noc_tx_flit_o(uart_flit),.noc_tx_valid_o(uart_valid),.noc_tx_vc_o(uart_vc),.noc_tx_credit_i(local_tx_credit[1])
  );
  gpio_node u_gpio (
    .clk_i,.rst_ni,.gpio_i,.gpio_o,.gpio_oe_o(gpio_oe),
    .noc_rx_flit_i(local_rx_flit[3]),.noc_rx_valid_i(local_rx_valid[3]),.noc_rx_vc_i(local_rx_vc[3]),.noc_rx_credit_o(gpio_credit),
    .noc_tx_flit_o(gpio_flit),.noc_tx_valid_o(gpio_valid),.noc_tx_vc_o(gpio_vc),.noc_tx_credit_i(local_tx_credit[3])
  );
  timer_node u_timer (
    .clk_i,.rst_ni,.timer_irq_o(timer_irq),
    .noc_rx_flit_i(local_rx_flit[5]),.noc_rx_valid_i(local_rx_valid[5]),.noc_rx_vc_i(local_rx_vc[5]),.noc_rx_credit_o(timer_credit),
    .noc_tx_flit_o(timer_flit),.noc_tx_valid_o(timer_valid),.noc_tx_vc_o(timer_vc),.noc_tx_credit_i(local_tx_credit[5])
  );
  mailbox_node u_mailbox (
    .clk_i,.rst_ni,.irq_hart0_o(irq0),.irq_hart1_o(irq1),
    .noc_rx_flit_i(local_rx_flit[7]),.noc_rx_valid_i(local_rx_valid[7]),.noc_rx_vc_i(local_rx_vc[7]),.noc_rx_credit_o(mailbox_credit),
    .noc_tx_flit_o(mailbox_flit),.noc_tx_valid_o(mailbox_valid),.noc_tx_vc_o(mailbox_vc),.noc_tx_credit_i(local_tx_credit[7])
  );

  task automatic axi_write(input logic [31:0] addr, input logic [31:0] data);
    bit aw_done, w_done;
    begin
      aw_done=0; w_done=0;
      @(negedge clk_i);
      cpu_axi.awaddr=addr; cpu_axi.awvalid=1;
      cpu_axi.wdata=data; cpu_axi.wstrb=4'hf; cpu_axi.wvalid=1; cpu_axi.bready=1;
      while (!aw_done || !w_done) begin
        @(posedge clk_i);
        if (cpu_axi.awvalid&&cpu_axi.awready) aw_done=1;
        if (cpu_axi.wvalid&&cpu_axi.wready) w_done=1;
        @(negedge clk_i);
        if (aw_done) cpu_axi.awvalid=0;
        if (w_done) cpu_axi.wvalid=0;
      end
      while (!cpu_axi.bvalid) @(posedge clk_i);
      assert(cpu_axi.bresp==2'b00) else $fatal(1,"Peripheral write failed at %08x",addr);
      @(negedge clk_i); cpu_axi.bready=0;
    end
  endtask

  task automatic axi_read(input logic [31:0] addr, output logic [31:0] data);
    begin
      @(negedge clk_i);
      cpu_axi.araddr=addr; cpu_axi.arvalid=1; cpu_axi.rready=1;
      while (!(cpu_axi.arvalid&&cpu_axi.arready)) @(posedge clk_i);
      @(negedge clk_i); cpu_axi.arvalid=0;
      while (!cpu_axi.rvalid) @(posedge clk_i);
      data=cpu_axi.rdata;
      assert(cpu_axi.rresp==2'b00) else $fatal(1,"Peripheral read failed at %08x",addr);
      @(negedge clk_i); cpu_axi.rready=0;
    end
  endtask

  logic [31:0] read_data;
  initial begin
    cpu_axi.awaddr='0; cpu_axi.awvalid=0; cpu_axi.wdata='0; cpu_axi.wstrb='0;
    cpu_axi.wvalid=0; cpu_axi.bready=0; cpu_axi.araddr='0; cpu_axi.arvalid=0; cpu_axi.rready=0;
    repeat(5) @(posedge clk_i); rst_ni=1; repeat(3) @(posedge clk_i);

    axi_write(32'h3000_1000, 32'h0000_005A);
    axi_write(32'h3000_1004, 32'h0000_00F0);
    assert(gpio_o==8'h5A && gpio_oe==8'hF0) else $fatal(1,"GPIO node mapping failed");
    axi_read(32'h3000_1008, read_data);
    assert(read_data[7:0]==8'hA6) else $fatal(1,"GPIO input read failed");

    axi_write(32'h3000_3004, 32'hCAFE_BABE);
    assert(irq1) else $fatal(1,"Mailbox hart1 IRQ was not raised");
    axi_read(32'h3000_3004, read_data);
    assert(read_data==32'hCAFE_BABE) else $fatal(1,"Mailbox data mismatch");
    axi_write(32'h3000_300C, 32'h2);
    assert(!irq1) else $fatal(1,"Mailbox hart1 IRQ did not clear");

    axi_write(32'h3000_2008, 32'd1);
    axi_write(32'h3000_200C, 32'd0);
    axi_write(32'h3000_2010, 32'd1);
    repeat(2) @(posedge clk_i);
    assert(timer_irq) else $fatal(1,"Timer node IRQ did not assert");

    axi_read(32'h3000_0004, read_data);
    assert(!$isunknown(read_data)) else $fatal(1,"UART status contained X");

    $display("TEST_PASS: UART/GPIO/timer/mailbox addresses reached four separate mesh nodes");
    $finish;
  end

  initial begin
    #300000; $fatal(1,"Timeout waiting for distributed peripheral test");
  end
endmodule
