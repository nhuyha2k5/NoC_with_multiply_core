`timescale 1ns/1ps
// Real 4-Ibex firmware run on the full SoC (sw/demo.c, one image per hart).
module tb_firmware;
  localparam int HARTS = 4;
  localparam int CLOCK_HZ = 100_000_000;
  // Fast UART in simulation (16 clocks/bit); the board build uses 115200.
  localparam int UART_BAUD = 6_250_000;
  localparam int CLKS_PER_BIT = CLOCK_HZ / UART_BAUD;
  logic clk_i=0,rst_ni=0;
  logic [7:0] gpio_i=0;
  wire [7:0] gpio_o,gpio_oe_o;
  wire uart_tx_o;
  wire [31:0] pc[HARTS],hits[HARTS],misses[HARTS];
  always #5 clk_i=~clk_i;
  ibex_mesh_soc #(.ROM0_INIT_FILE("core0.mem"),.ROM1_INIT_FILE("core1.mem"),
                  .ROM2_INIT_FILE("core2.mem"),.ROM3_INIT_FILE("core3.mem"),
                  .CLOCK_HZ(CLOCK_HZ),.UART_BAUD(UART_BAUD)) dut(
    .clk_i,.rst_ni,.gpio_i,.gpio_o,.gpio_oe_o,.uart_tx_o,
    .debug_pc0_o(pc[0]),.debug_pc1_o(pc[1]),.debug_pc2_o(pc[2]),.debug_pc3_o(pc[3]),
    .cache0_hits_o(hits[0]),.cache0_misses_o(misses[0]),.cache1_hits_o(hits[1]),.cache1_misses_o(misses[1]),
    .cache2_hits_o(hits[2]),.cache2_misses_o(misses[2]),.cache3_hits_o(hits[3]),.cache3_misses_o(misses[3]));
  noc_endpoint_stats stats(.clk_i,.rst_ni,.enable_i(rst_ni),
    .tx_flit_i(dut.node_tx_flit),.rx_flit_i(dut.node_rx_flit),
    .tx_valid_i(dut.node_tx_valid),.tx_vc_i(dut.node_tx_vc),
    .rx_valid_i(dut.node_rx_valid),.rx_vc_i(dut.node_rx_vc));

  // Shared RAM word at byte offset from 0x2000_0000 (four interleaved banks).
  function automatic logic [31:0] ram(input int offset);
    int w;w=offset/4;
    case(w%4)
      0:return dut.u_ram_node.u_ram.g_bank[0].mem[w/4];
      1:return dut.u_ram_node.u_ram.g_bank[1].mem[w/4];
      2:return dut.u_ram_node.u_ram.g_bank[2].mem[w/4];
      default:return dut.u_ram_node.u_ram.g_bank[3].mem[w/4];
    endcase
  endfunction
  function automatic longint flit_hops();
    longint s;s=0;
    for(int i=0;i<45;i++)s+=dut.router_flits[i*32+:32];
    return s;
  endfunction
  function automatic int mark(input int h);return 'hbe00+h*'h40;endfunction
  localparam int PAR='hbd00;
  localparam int P_MM1=0,P_MM2=4,P_MM4=8,P_SUM1=12,P_SUM2=16,P_SUM4=20,P_ACC_ENGINE=24,P_ACC_E2E=28,
                 P_STATUS=32,P_PHASE=36,P_SUM=40,P_FLUSH=44,P_DISPATCH_COLD=48,P_DISPATCH_WARM=52,
                 P_COUNTER=56,P_MMSUM=60;

  // Snapshot cycle/cache/NoC counters whenever firmware moves to a new phase.
  longint cycle=0;
  longint snap_cycle[0:31],snap_flits[0:31];
  int snap_hit[0:31][HARTS],snap_miss[0:31][HARTS];
  logic [31:0] phase_q=0;
  always @(posedge clk_i) if(rst_ni) begin
    logic [31:0] p;
    cycle++;
    p=ram(PAR+P_PHASE);
    if(p!==phase_q && p<32) begin
      phase_q=p;
      snap_cycle[p]=cycle;snap_flits[p]=flit_hops();
      for(int h=0;h<HARTS;h++)begin snap_hit[p][h]=hits[h];snap_miss[p][h]=misses[h];end
    end
  end
  // Ibex ALU 'unique case (1'b1)' on {multdiv_sel_i, adder_op_b_negate} is
  // reported by Questa inside delta cycles. Sample the settled values on the
  // falling edge: a real overlap would make synthesis and simulation differ.
  int alu_overlap[HARTS],alu_mul_cycles[HARTS];
  for(genvar h=0;h<HARTS;h++)begin:g_alu
    initial begin alu_overlap[h]=0;alu_mul_cycles[h]=0;end
    always @(negedge clk_i) if(rst_ni) begin
      if(dut.g_cpu[h].u_cpu.u_tile.u_ibex.u_ibex_core.ex_block_i.alu_i.multdiv_sel_i)begin
        alu_mul_cycles[h]++;
        if(dut.g_cpu[h].u_cpu.u_tile.u_ibex.u_ibex_core.ex_block_i.alu_i.adder_op_b_negate)alu_overlap[h]++;
      end
    end
  end
  // Real GPIO event for PLIC source 8 once firmware has armed the edge IRQ.
  initial begin
    wait(rst_ni && phase_q==15);
    repeat(20)@(posedge clk_i);gpio_i[0]=1;
  end

  // UART receiver (8N1): every line is echoed with a "UART:" prefix and kept.
  string uart_lines[$];
  initial begin
    string line;
    int fd;
    fd=$fopen("uart.log","w");
    line="";
    forever begin
      logic [7:0] ch;
      @(negedge uart_tx_o);
      repeat(CLKS_PER_BIT/2)@(posedge clk_i);
      if(uart_tx_o)continue;   // glitch, not a start bit
      for(int b=0;b<8;b++)begin repeat(CLKS_PER_BIT)@(posedge clk_i);ch[b]=uart_tx_o;end
      repeat(CLKS_PER_BIT)@(posedge clk_i);
      assert(uart_tx_o)else $fatal(1,"UART stop bit missing");
      if(ch==8'h0a)begin
        $display("UART: %s",line);$fdisplay(fd,"%s",line);$fflush(fd);
        uart_lines.push_back(line);line="";
      end else line={line,string'(ch)};
    end
  end

  task automatic report(input int fd,input string kernel,input string mode,input int p0,input int fw_offset);
    longint c,f;int dh[HARTS],dm[HARTS];
    c=snap_cycle[p0+1]-snap_cycle[p0];f=snap_flits[p0+1]-snap_flits[p0];
    for(int h=0;h<HARTS;h++)begin dh[h]=snap_hit[p0+1][h]-snap_hit[p0][h];dm[h]=snap_miss[p0+1][h]-snap_miss[p0][h];end
    $display("PARALLEL kernel=%s mode=%s fw_cycles=%0d tb_cycles=%0d flit_hops=%0d hit=%0d/%0d/%0d/%0d miss=%0d/%0d/%0d/%0d",
      kernel,mode,ram(PAR+fw_offset),c,f,dh[0],dh[1],dh[2],dh[3],dm[0],dm[1],dm[2],dm[3]);
    $fdisplay(fd,"%s,%s,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",kernel,mode,ram(PAR+fw_offset),c,f,
      dh[0],dm[0],dh[1],dm[1],dh[2],dm[2],dh[3],dm[3]);
  endtask

  initial begin
    repeat(10) @(negedge clk_i); rst_ni=1;
    // ram() is a function: poll every clock instead of wait() so the RAM
    // contents are re-evaluated.
    while(!(ram(mark(0))==32'h600d0000 || (ram(mark(0))>>20)==32'hbad))@(posedge clk_i);
    assert(ram(mark(0))==32'h600d0000) else $fatal(1,"Hart0 firmware failed: mark=%h",ram(mark(0)));
    for(int h=1;h<HARTS;h++)begin
      assert(ram(mark(h))==(32'h600d0000|h)) else $fatal(1,"Hart%0d not complete: mark=%h",h,ram(mark(h)));
      assert(ram(mark(h)+8)==1) else $fatal(1,"Hart%0d never took its CLINT software interrupt",h);
      assert(ram(mark(h)+4)&32) else $fatal(1,"Hart%0d never took a mailbox interrupt on its PLIC context",h);
    end
    assert(ram('hbf80)==32'hc594bfc3 && ram('hbf84)==32'h33db76a7 &&
           ram('hbf88)==32'h13 && ram('hbf8c)==0) else $fatal(1,"Fibonacci100 incorrect");
    assert((ram(mark(0)+4)&7)==7 && ram(mark(0)+12)==1)
      else $fatal(1,"Missing DMA/accelerator/mailbox interrupt or CLINT timer on hart0");
    assert(ram(mark(0)+4)&64) else $fatal(1,"GPIO source 8 not serviced by firmware");
    assert(ram(PAR+P_COUNTER)==HARTS*32) else $fatal(1,"Test-and-set counter %0d, expected %0d",ram(PAR+P_COUNTER),HARTS*32);
    assert(ram(PAR+P_STATUS)==32'h7f)
      else $fatal(1,"Benchmark self-check failed: status=%h (bit0 mm2, bit1 mm4, bit2 ACC, bit3 sum2, bit4 sum4, bit5 lock, bit6 GPIO)",ram(PAR+P_STATUS));
    assert(gpio_o==8'h5a && gpio_oe_o==8'hff) else $fatal(1,"Firmware GPIO result");
    // Wait for the UART report and outstanding NoC responses.
    begin
      int waited=0;
      while(!(uart_lines.size()>0 && uart_lines[$].substr(0,5)=="RESULT"))begin
        @(posedge clk_i);waited++;
        assert(waited<2000000)else $fatal(1,"UART report not received (%0d lines)",uart_lines.size());
      end
      assert(uart_lines[$].substr(0,10)=="RESULT PASS")else $fatal(1,"Firmware UART result: %s",uart_lines[$]);
      assert(uart_lines.size()==8)else $fatal(1,"Expected 8 UART report lines, got %0d",uart_lines.size());
    end
    repeat(300)@(posedge clk_i);
    stats.report("firmware_endpoints.csv");
    begin
      int fd;
      fd=$fopen("parallel_metrics.csv","w");
      $fdisplay(fd,"kernel,mode,fw_cycles,tb_cycles,flit_hops,c0_hits,c0_misses,c1_hits,c1_misses,c2_hits,c2_misses,c3_hits,c3_misses");
      report(fd,"matmul16","1hart",1,P_MM1);
      report(fd,"matmul16","2hart",3,P_MM2);
      report(fd,"matmul16","4hart",5,P_MM4);
      report(fd,"matmul16","accelerator",7,P_ACC_E2E);
      report(fd,"sum512","1hart",9,P_SUM1);
      report(fd,"sum512","2hart",11,P_SUM2);
      report(fd,"sum512","4hart",13,P_SUM4);
      $fclose(fd);
      $display("PARALLEL_SPEEDUP matmul16 x2=%0.3f x4=%0.3f sum512 x2=%0.3f x4=%0.3f acc_vs_1hart=%0.3f acc_engine_cycles=%0d flush_all_cycles=%0d dispatch_cold=%0d dispatch_warm=%0d mm_checksum=%h sum=%h",
        real'(ram(PAR+P_MM1))/real'(ram(PAR+P_MM2)),real'(ram(PAR+P_MM1))/real'(ram(PAR+P_MM4)),
        real'(ram(PAR+P_SUM1))/real'(ram(PAR+P_SUM2)),real'(ram(PAR+P_SUM1))/real'(ram(PAR+P_SUM4)),
        real'(ram(PAR+P_MM1))/real'(ram(PAR+P_ACC_E2E)),ram(PAR+P_ACC_ENGINE),ram(PAR+P_FLUSH),
        ram(PAR+P_DISPATCH_COLD),ram(PAR+P_DISPATCH_WARM),ram(PAR+P_MMSUM),ram(PAR+P_SUM));
      assert(ram(PAR+P_DISPATCH_COLD)>0 && ram(PAR+P_DISPATCH_WARM)>0)else $fatal(1,"Dispatch overhead not measured");
    end
    for(int h=0;h<HARTS;h++)
      assert(alu_overlap[h]==0)else $fatal(1,"Ibex%0d ALU unique-case overlap at a settled clock edge: %0d",h,alu_overlap[h]);
    $display("IBEX_ALU_UNIQUE settled_overlap=0 multdiv_cycles=%0d/%0d/%0d/%0d (Questa vsim-8360 reports are delta-cycle glitches)",
      alu_mul_cycles[0],alu_mul_cycles[1],alu_mul_cycles[2],alu_mul_cycles[3]);
    $display("FIRMWARE_METRIC hart0_total_cycles=%0d hart1_total_cycles=%0d fib100_cycles=%0d hits=%0d/%0d/%0d/%0d misses=%0d/%0d/%0d/%0d",
      ram(mark(0)+24),ram(mark(1)+24),ram(mark(1)+16),hits[0],hits[1],hits[2],hits[3],misses[0],misses[1],misses[2],misses[3]);
    $display("TEST_PASS: real 4-Ibex C firmware: boot of 4 harts, CLINT IPI+timer, PLIC ctx0-3, mailbox doorbells, test-and-set lock (%0d increments), F100, DMA, accelerator, GPIO source 8, matmul/sum on 1/2/4 harts with MESI, UART report; dma_cycles=%0d acc_cycles=%0d",
      ram(PAR+P_COUNTER),ram(mark(0)+16),ram(mark(0)+20));
    $finish;
  end
  initial begin
    #100_000_000;
    $fatal(1,"Firmware timeout pc=%h/%h/%h/%h mark0=%h mark1=%h mark2=%h mark3=%h irqflags=%h phase=%0d",
      pc[0],pc[1],pc[2],pc[3],ram(mark(0)),ram(mark(1)),ram(mark(2)),ram(mark(3)),ram(mark(0)+4),phase_q);
  end
endmodule
