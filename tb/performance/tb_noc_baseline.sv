`timescale 1ns/1ps
// Open-loop traffic with unlimited (bounded by test length) source queues.
// Fixed measurement window; drain is never counted as throughput time.
module tb_noc_baseline;
  import router_pkg::*;
  logic clk_i=0,rst_ni=0;
  logic [33:0] tx[9],rx[9];
  logic tv[9],tc[9],rv[9],rc[9];
  logic [1:0] txcr[9],rxcr[9];
  int credit[9][2],owed[9][2],active[9],phase[9],head[9],tail[9];
  int pending[9][16384],receive_id[9][2],receive_phase[9][2];
  int destination[65536],channel[65536],started[65536],enqueued[65536];
  bit seen[65536],cohort[65536];
  int histogram[2][65536];
  int samples[2],maxlat[2]; longint sumlat[2],sumqueue[2];
  int next_id,received,injected,offered_window,rx_window,tx_window,rx_flits;
  int rate=10,pattern=0,stall=0,seed=1,measure=3000,warmup=500,cycle;
  logic [1:0] qos_mode=1;
  logic qos_classes=0;
  // Traffic class carried in header [2:1]. The packet ID is packed around it
  // (bits [23:17], [16:3], [0]) so enabling class priority measures classes,
  // not accidental ID bits. HIGH_CLASS_SRC>=0 gives that source class 3.
  int high_class_src=-1;
  function automatic logic [21:0] id_bits(input int id);return 22'(id);endfunction
  function automatic logic [31:0] head_payload(input int id,input int s,input int d);
    logic [21:0] b;logic [31:0] h;
    b=id_bits(id);
    h={2'(d/3),2'(d%3),2'(s/3),2'(s%3),b[21:15],b[14:1],2'(s==high_class_src?3:0),b[0]};
    return h;
  endfunction
  function automatic int head_id(input logic [31:0] h);
    return int'({h[23:17],h[16:3],h[0]});
  endfunction
  logic [31:0] rng;
  logic [31:0] sink_rng;
  string csv="baseline.csv";
  int fd;
  longint occupancy_sum,link_busy,source_stall;
  int occupancy_max;
  wire [2:0] occupancy[9][5][2];
  always #5 clk_i=~clk_i;
  mesh_3x3_vc dut(.clk_i,.rst_ni,.qos_mode_i(qos_mode),.qos_classes_i(qos_classes),
    .local_tx_flit_i(tx),.local_tx_valid_i(tv),
    .local_tx_vc_i(tc),.local_tx_credit_o(txcr),.local_rx_flit_o(rx),
    .local_rx_valid_o(rv),.local_rx_vc_o(rc),.local_rx_credit_i(rxcr));
  for(genvar x=0;x<3;x++)for(genvar y=0;y<3;y++)
    for(genvar p=0;p<5;p++)for(genvar v=0;v<2;v++)
      assign occupancy[x*3+y][p][v]=dut.g_x[x].g_y[y].u_router.g_input[p].u_input.g_vc[v].u_fifo.count_o;
  function automatic int random_number();
    rng=rng*32'd1664525+32'd1013904223;
    return int'(rng>>1);
  endfunction
  function automatic int random_sink();
    sink_rng=sink_rng*32'd1664525+32'd1013904223;
    return int'(sink_rng>>1);
  endfunction
  function automatic int choose_destination(input int src);
    int d;
    case(pattern)
      1:d=4; // hotspot
      2:d=8-src; // complement/corner
      3:d=(src%3)*3+src/3; // transpose
      4:d=(src+1)%9;
      default:begin d=random_number()%8; if(d>=src)d++;end
    endcase
    return d;
  endfunction
  function automatic int percentile(input int vc,input int percent);
    int count,target;
    count=0;target=(samples[vc]*percent+99)/100;
    for(int i=0;i<65536;i++)begin count+=histogram[vc][i];if(count>=target)return i;end
    return 0;
  endfunction
  task automatic drive(input bit generate_packets,input bit drain);
    int id,d,v;
    @(negedge clk_i);
    for(int s=0;s<9;s++)begin
      tv[s]=0;tx[s]=0;tc[s]=0;rxcr[s]=0;
      for(int c=0;c<2;c++)if(owed[s][c]>0 && (drain || random_sink()%100>=stall))rxcr[s][c]=1;
      if(generate_packets && random_number()%100<rate)begin
        id=next_id++;assert(id<65536 && tail[s]<16384)else $fatal(1,"Traffic capacity");
        d=choose_destination(s);destination[id]=d;channel[id]=random_number()%2;
        enqueued[id]=cycle;pending[s][tail[s]++]=id;
        if(cycle>=warmup && cycle<warmup+measure)offered_window++;
      end
      if(active[s]<0 && head[s]<tail[s])begin active[s]=pending[s][head[s]++];phase[s]=0;end
      if(active[s]>=0)begin
        id=active[s];v=channel[id];d=destination[id];tc[s]=v[0];
        if(credit[s][v]>0)begin
          tv[s]=1;
          case(phase[s])
            0:tx[s]={FLIT_HEAD,head_payload(id,s,d)};
            1:tx[s]={FLIT_BODY,32'(id)^32'h13579bdf};
            2:tx[s]={FLIT_TAIL,32'(id)^32'hfedcba98};
          endcase
        end else if(cycle>=warmup && cycle<warmup+measure)source_stall++;
      end
    end
  endtask
  task automatic sample;
    int id,v,lat;
    @(posedge clk_i);
    for(int s=0;s<9;s++)begin
      for(int c=0;c<2;c++)begin
        credit[s][c]+=int'(txcr[s][c])-int'(tv[s] && tc[s]==c);
        if(rxcr[s][c])owed[s][c]--;
        assert(credit[s][c]>=0 && credit[s][c]<=4)else $fatal(1,"Injection credits");
      end
      if(tv[s])begin
        id=active[s];
        if(phase[s]==0)begin
          started[id]=cycle;cohort[id]=(cycle>=warmup && cycle<warmup+measure);injected++;
          if(cohort[id])tx_window++;
        end
        if(phase[s]==2)active[s]=-1;else phase[s]++;
      end
      if(rv[s])begin
        v=int'(rc[s]);owed[s][v]++;
        assert(owed[s][v]<=4)else $fatal(1,"Sink buffer overflow");
        if(cycle>=warmup && cycle<warmup+measure)rx_flits++;
        case(rx[s][33:32])
          FLIT_HEAD:begin
            id=head_id(rx[s][31:0]);
            assert(receive_id[s][v]<0 && id<next_id && destination[id]==s && channel[id]==v && !seen[id])else $fatal(1,"Misroute/duplicate/interleaved head");
            receive_id[s][v]=id;receive_phase[s][v]=1;
          end
          FLIT_BODY:begin
            id=receive_id[s][v];
            assert(id>=0 && receive_phase[s][v]==1 && rx[s][31:0]==(32'(id)^32'h13579bdf))else $fatal(1,"Body corruption/order");
            receive_phase[s][v]=2;
          end
          FLIT_TAIL:begin
            id=receive_id[s][v];
            assert(id>=0 && receive_phase[s][v]==2 && rx[s][31:0]==(32'(id)^32'hfedcba98) && !seen[id])else $fatal(1,"Tail corruption/order/duplicate");
            seen[id]=1;received++;receive_id[s][v]=-1;
            if(cycle>=warmup && cycle<warmup+measure)rx_window++;
            if(cohort[id])begin
              lat=cycle-started[id];assert(lat<65536)else $fatal(1,"Latency histogram overflow");
              samples[v]++;sumlat[v]+=lat;histogram[v][lat]++;
              sumqueue[v]+=started[id]-enqueued[id];if(lat>maxlat[v])maxlat[v]=lat;
            end
          end
          default:$fatal(1,"Unexpected flit type");
        endcase
      end
      if(cycle>=warmup && cycle<warmup+measure)begin
        for(int p=0;p<5;p++)begin
          if(p!=PORT_LOCAL && dut.link_valid[s][p])link_busy++;
          for(int c=0;c<2;c++)begin
            occupancy_sum+=occupancy[s][p][c];
            if(occupancy[s][p][c]>occupancy_max)occupancy_max=occupancy[s][p][c];
          end
        end
      end
    end
    cycle++;
  endtask
  initial begin
    void'($value$plusargs("RATE=%d",rate));void'($value$plusargs("PATTERN=%d",pattern));
    void'($value$plusargs("STALL=%d",stall));void'($value$plusargs("SEED=%d",seed));
    void'($value$plusargs("QOS_MODE=%d",qos_mode));
    void'($value$plusargs("QOS_CLASSES=%d",qos_classes));
    void'($value$plusargs("HIGH_CLASS_SRC=%d",high_class_src));
    void'($value$plusargs("CSV=%s",csv));rng=seed;sink_rng=seed^32'h1234abcd;
    next_id=0;received=0;injected=0;cycle=0;
    for(int s=0;s<9;s++)begin
      active[s]=-1;tv[s]=0;tc[s]=0;tx[s]=0;rxcr[s]=0;head[s]=0;tail[s]=0;
      for(int c=0;c<2;c++)begin credit[s][c]=4;owed[s][c]=0;receive_id[s][c]=-1;end
    end
    repeat(8)@(negedge clk_i);rst_ni=1;
    repeat(warmup+measure)begin drive(1,0);sample();end
    // Stop arrivals and drain every queued packet; no packet is silently dropped.
    while(received<next_id && cycle<60000)begin drive(0,1);sample();end
    assert(received==next_id && injected==next_id)else $fatal(1,"NoC deadlock/loss offered=%0d injected=%0d received=%0d",next_id,injected,received);
    for(int i=0;i<next_id;i++)assert(seen[i])else $fatal(1,"Missing packet %0d",i);
    fd=$fopen(csv,"w");assert(fd!=0)else $fatal(1,"CSV open failed");
    $fdisplay(fd,"pattern,rate_pct,stall_pct,seed,vc,qos_mode,qos_classes,offered_pkts,head_injected,tail_received,cycles,flits_per_node_cycle,packets_per_node_cycle,avg_latency,p95_latency,p99_latency,max_latency,avg_source_queue_delay,avg_fifo_occupancy,max_fifo_occupancy,link_util,source_stall_cycles,cohort_samples");
    for(int v=0;v<2;v++)begin
      $fdisplay(fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%.6f,%.6f,%.3f,%0d,%0d,%0d,%.3f,%.6f,%0d,%.6f,%0d,%0d",pattern,rate,stall,seed,v,qos_mode,qos_classes,offered_window,tx_window,rx_window,measure,real'(rx_flits)/(9*measure),real'(rx_window)/(9*measure),real'(sumlat[v])/samples[v],percentile(v,95),percentile(v,99),maxlat[v],real'(sumqueue[v])/samples[v],real'(occupancy_sum)/(90*measure),occupancy_max,real'(link_busy)/(24*measure),source_stall,samples[v]);
      $display("BASELINE pattern=%0d rate=%0d stall=%0d VC=%0d avg=%.2f p99=%0d max=%0d flit/node/cycle=%.4f",pattern,rate,stall,v,real'(sumlat[v])/samples[v],percentile(v,99),maxlat[v],real'(rx_flits)/(9*measure));
    end
    $fclose(fd);$display("TEST_PASS: raw NoC all %0d packets delivered exactly once",next_id);$finish;
  end
endmodule
