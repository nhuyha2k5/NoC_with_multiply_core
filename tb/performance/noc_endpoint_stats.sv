// HEAD injection to matching tagged response TAIL. A burst is one transaction.
// Count only requests injected inside the measurement window; drain outside it.
module noc_endpoint_stats(
  input logic clk_i,rst_ni,enable_i,
  input logic [33:0] tx_flit_i[0:8],rx_flit_i[0:8],
  input logic tx_valid_i[0:8],tx_vc_i[0:8],rx_valid_i[0:8],rx_vc_i[0:8]
);
  longint unsigned cycle_q,measure_cycles,rx_flits;
  longint unsigned start_q[0:8][0:15],count_q[0:8],sum_q[0:8],min_q[0:8],max_q[0:8];
  bit active[0:8][0:15];
  logic[3:0] response_tag[0:8];
  bit response_open[0:8];
  always @(posedge clk_i)begin
    if(!rst_ni)begin
      cycle_q=0;measure_cycles=0;rx_flits=0;
      for(int n=0;n<9;n++)begin
        count_q[n]=0;sum_q[n]=0;min_q[n]='1;max_q[n]=0;response_open[n]=0;response_tag[n]=0;
        for(int t=0;t<16;t++)begin active[n][t]=0;start_q[n][t]=0;end
      end
    end else begin
      cycle_q++;
      if(enable_i)begin
        measure_cycles++;
        for(int n=0;n<9;n++)begin
          if(rx_valid_i[n])rx_flits++;
          if(tx_valid_i[n]&&!tx_vc_i[n]&&tx_flit_i[n][33:32]==1)begin
            int t;t=int'(tx_flit_i[n][14:11]);
            assert(!active[n][t])else $fatal(1,"Outstanding tag reused node=%0d tag=%0d",n,t);
            active[n][t]=1;start_q[n][t]=cycle_q;
          end
        end
      end
      for(int n=0;n<9;n++)if(rx_valid_i[n]&&rx_vc_i[n])begin
        if(rx_flit_i[n][33:32]==1)begin response_tag[n]=rx_flit_i[n][14:11];response_open[n]=1;end
        if(rx_flit_i[n][33:32]==2&&response_open[n])begin
          int t;longint unsigned latency;
          t=int'(response_tag[n]);response_open[n]=0;
          if(active[n][t])begin
            latency=cycle_q-start_q[n][t]+1;
            active[n][t]=0;count_q[n]++;sum_q[n]+=latency;
            if(latency<min_q[n])min_q[n]=latency;
            if(latency>max_q[n])max_q[n]=latency;
          end
        end
      end
    end
  end
  task automatic report(input string path);
    int f;
    for(int n=0;n<9;n++)for(int t=0;t<16;t++)assert(!active[n][t])
      else $fatal(1,"Endpoint stats before drain node=%0d tag=%0d",n,t);
    assert(measure_cycles!=0)else $fatal(1,"Empty measurement window");
    f=$fopen(path,"w");if(!f)$fatal(1,"Cannot open stats CSV");
    $fdisplay(f,"node,transactions,min_cycles,mean_cycles,max_cycles,measurement_cycles,global_rx_flits,global_rx_flits_per_cycle");
    for(int n=0;n<9;n++)if(count_q[n])begin
      $fdisplay(f,"%0d,%0d,%0d,%.3f,%0d,%0d,%0d,%.6f",n,count_q[n],min_q[n],
        real'(sum_q[n])/count_q[n],max_q[n],measure_cycles,rx_flits,real'(rx_flits)/measure_cycles);
      $display("ENDPOINT node=%0d transactions=%0d min=%0d avg=%.2f max=%0d cycles",n,count_q[n],min_q[n],real'(sum_q[n])/count_q[n],max_q[n]);
    end
    $fclose(f);
  endtask
endmodule
