// Bounded AXI4 burst NI: independent read/write queues, two slots each by
// default. Entire responses have reserved storage before AR/AW acceptance.
module axi4_to_mesh #(
  parameter int SLOTS=2,MAX_BEATS=16,FIFO_DEPTH=4,
  parameter logic[1:0] CURRENT_X=2,CURRENT_Y=0,
  localparam int SW=(SLOTS<2)?1:$clog2(SLOTS),
  localparam int BW=(MAX_BEATS<2)?1:$clog2(MAX_BEATS),
  localparam int CW=$clog2(FIFO_DEPTH+1)
)(
  input logic clk_i,rst_ni,
  input logic tx_ready_i=1'b1,
  axi4_if.slave s_axi,
  output logic[33:0] tx_flit_o,
  output logic tx_valid_o,tx_vc_o,
  input logic[1:0] tx_credit_i,
  input logic[33:0] rx_flit_i,
  input logic rx_valid_i,rx_vc_i,
  output logic[1:0] rx_credit_o
);
  import router_pkg::*;
  logic[SLOTS-1:0] rb,ri,rd,re,wb,wi,wd,wfilled;
  logic[1:0] we[SLOTS],wrsp[SLOTS];
  logic[31:0] ra[SLOTS],wa[SLOTS],rdata[SLOTS][MAX_BEATS],wdata[SLOTS][MAX_BEATS];
  logic[3:0] rid[SLOTS],wid[SLOTS],rqos[SLOTS],wqos[SLOTS],wstrb[SLOTS][MAX_BEATS];
  logic[1:0] rresp[SLOTS][MAX_BEATS];
  logic[7:0] rlen[SLOTS],wlen[SLOTS];
  logic[SW-1:0] ralloc,rret,rsend,walloc,wret,wsend,wfill,txslot;
  logic[$clog2(SLOTS+1)-1:0] rcount,wcount;
  logic[7:0] rbeat,wbeat,txbeat,rxbeat;
  logic[3:0] rxtag;
  logic[1:0] rxcode,rxphase;
  logic rxwrite,txwrite,rr;
  logic[2:0] phase;
  logic[CW-1:0] credit;
  logic rp,wp,tf,rf,bf,arf,awf;
  function automatic logic[SW-1:0] nxt(input logic[SW-1:0] p);
    return p==SLOTS-1?'0:p+1'b1;
  endfunction
  function automatic logic legal(input logic[31:0] a,input logic[7:0] len,
    input logic[2:0] size,input logic[1:0] burst,input logic lock);
    logic[32:0] finish;
    finish={1'b0,a}+(({25'b0,len}+33'd1)<<2);
    return size==2&&burst==1&&!lock&&a[1:0]==0&&len<MAX_BEATS&&
      shared_address(a)&&finish<={1'b0,SHARED_END}&&({1'b0,a[11:0]}+(({5'b0,len}+13'd1)<<2)<=4096);
  endfunction
  assign s_axi.arready=rst_ni&&rcount<SLOTS;
  assign s_axi.awready=rst_ni&&wcount<SLOTS;
  assign s_axi.wready=rst_ni&&wb[wfill]&&!wfilled[wfill];
  assign s_axi.rvalid=rst_ni&&rcount!=0&&rd[rret];
  assign s_axi.rdata=re[rret]?32'b0:rdata[rret][rbeat[BW-1:0]];
  assign s_axi.rresp=re[rret]?2'b11:rresp[rret][rbeat[BW-1:0]];
  assign s_axi.rid=rid[rret];
  assign s_axi.rlast=rbeat==rlen[rret];
  assign s_axi.bvalid=rst_ni&&wcount!=0&&wd[wret];
  assign s_axi.bresp=wrsp[wret];
  assign s_axi.bid=wid[wret];
  assign arf=s_axi.arvalid&&s_axi.arready;
  assign awf=s_axi.awvalid&&s_axi.awready;
  assign rf=s_axi.rvalid&&s_axi.rready&&s_axi.rlast;
  assign bf=s_axi.bvalid&&s_axi.bready;
  assign rp=rb[rsend]&&!ri[rsend]&&!re[rsend];
  assign wp=wb[wsend]&&!wi[wsend]&&wfilled[wsend]&&we[wsend]==0;
  assign tx_valid_o=rst_ni&&phase!=0&&credit!=0;
  assign tx_vc_o=0;
  assign tf=tx_valid_o&&tx_ready_i;
  always_comb begin
    tx_flit_o=0;
    case(phase)
      1:begin
        tx_flit_o=make_head(1,1,CURRENT_X,CURRENT_Y,txwrite?NOC_BURST_WRITE:NOC_BURST_READ,0);
        tx_flit_o[14:11]={txwrite,3'(txslot)};
        tx_flit_o[10:3]=txwrite?wlen[txslot]:rlen[txslot];
        tx_flit_o[2:1]=txwrite?wqos[txslot][1:0]:rqos[txslot][1:0];
      end
      2:tx_flit_o={FLIT_BODY,txwrite?wa[txslot]:ra[txslot]};
      3:tx_flit_o={FLIT_TAIL,32'b0};
      4:tx_flit_o={FLIT_BODY,28'b0,wstrb[txslot][txbeat[BW-1:0]]};
      5:tx_flit_o={txbeat==wlen[txslot]?FLIT_TAIL:FLIT_BODY,wdata[txslot][txbeat[BW-1:0]]};
      default:;
    endcase
    rx_credit_o=0;if(rst_ni&&rx_valid_i)rx_credit_o[rx_vc_i]=1;
  end
  always_ff @(posedge clk_i)begin
    if(!rst_ni)begin
      rb<=0;ri<=0;rd<=0;re<=0;wb<=0;wi<=0;wd<=0;wfilled<=0;
      ralloc<=0;rret<=0;rsend<=0;walloc<=0;wret<=0;wsend<=0;wfill<=0;
      rcount<=0;wcount<=0;rbeat<=0;wbeat<=0;txbeat<=0;rxbeat<=0;
      phase<=0;txslot<=0;txwrite<=0;rr<=0;credit<=FIFO_DEPTH;
      rxphase<=0;rxtag<=0;rxcode<=0;rxwrite<=0;
    end else begin
      if(arf)begin
        rb[ralloc]<=1;ri[ralloc]<=0;
        re[ralloc]<=!legal(s_axi.araddr,s_axi.arlen,s_axi.arsize,s_axi.arburst,s_axi.arlock);
        rd[ralloc]<=!legal(s_axi.araddr,s_axi.arlen,s_axi.arsize,s_axi.arburst,s_axi.arlock);
        ra[ralloc]<=s_axi.araddr;rlen[ralloc]<=s_axi.arlen;rid[ralloc]<=s_axi.arid;rqos[ralloc]<=s_axi.arqos;
        ralloc<=nxt(ralloc);
      end
      if(awf)begin
        wb[walloc]<=1;wi[walloc]<=0;wd[walloc]<=0;wfilled[walloc]<=0;
        we[walloc]<=legal(s_axi.awaddr,s_axi.awlen,s_axi.awsize,s_axi.awburst,s_axi.awlock)?0:3;
        wa[walloc]<=s_axi.awaddr;wlen[walloc]<=s_axi.awlen;wid[walloc]<=s_axi.awid;wqos[walloc]<=s_axi.awqos;
        walloc<=nxt(walloc);
      end
      if(s_axi.wvalid&&s_axi.wready)begin
        if(wbeat<MAX_BEATS)begin wdata[wfill][wbeat[BW-1:0]]<=s_axi.wdata;wstrb[wfill][wbeat[BW-1:0]]<=s_axi.wstrb;end
        if(s_axi.wlast!=(wbeat==wlen[wfill])&&we[wfill]==0)we[wfill]<=2;
        if(wbeat==wlen[wfill])begin
          wfilled[wfill]<=1;wfill<=nxt(wfill);wbeat<=0;
        end else wbeat<=wbeat+1'b1;
      end
      if(s_axi.rvalid&&s_axi.rready)rbeat<=s_axi.rlast?0:rbeat+1'b1;
      if(rf)begin rb[rret]<=0;rd[rret]<=0;rret<=nxt(rret);end
      if(bf)begin wb[wret]<=0;wd[wret]<=0;wret<=nxt(wret);end
      case({arf,rf})2'b10:rcount<=rcount+1'b1;2'b01:rcount<=rcount-1'b1;default:;endcase
      case({awf,bf})2'b10:wcount<=wcount+1'b1;2'b01:wcount<=wcount-1'b1;default:;endcase
      // Local errors also advance issue cursors, without injecting packets.
      if(rb[rsend]&&!ri[rsend]&&re[rsend])begin ri[rsend]<=1;rsend<=nxt(rsend);end
      if(wb[wsend]&&!wi[wsend]&&wfilled[wsend]&&we[wsend]!=0)begin
        wi[wsend]<=1;wd[wsend]<=1;wrsp[wsend]<=we[wsend];wsend<=nxt(wsend);
      end
      if(phase==0&&(rp||wp))begin
        txwrite<=wp&&(!rp||rr);txslot<=(wp&&(!rp||rr))?wsend:rsend;txbeat<=0;phase<=1;
      end
      if(tf)case(phase)
        1:phase<=2;
        2:phase<=txwrite?4:3;
        3:begin phase<=0;ri[txslot]<=1;rsend<=nxt(rsend);rr<=1;end
        4:phase<=5;
        5:if(txbeat==wlen[txslot])begin phase<=0;wi[txslot]<=1;wsend<=nxt(wsend);rr<=0;end
          else begin txbeat<=txbeat+1'b1;phase<=4;end
        default:;
      endcase
      case({tx_credit_i[0],tf})2'b10:credit<=credit+1'b1;2'b01:credit<=credit-1'b1;default:;endcase
      if(rx_valid_i&&rx_vc_i)begin
        if(rx_flit_i[33:32]==FLIT_HEAD)begin
          rxtag<=rx_flit_i[14:11];rxwrite<=rx_flit_i[14];rxbeat<=0;
          rxcode<=rx_flit_i[16:15];rxphase<=rx_flit_i[14]?2:1;
        end else if(rxphase==1)begin rxcode<=rx_flit_i[1:0];rxphase<=2;end
        else if(rxphase==2)begin
          if(rxwrite)begin wd[rxtag[SW-1:0]]<=1;wrsp[rxtag[SW-1:0]]<=rxcode;rxphase<=0;end
          else begin
            rdata[rxtag[SW-1:0]][rxbeat[BW-1:0]]<=rx_flit_i[31:0];
            rresp[rxtag[SW-1:0]][rxbeat[BW-1:0]]<=rxcode;
            if(rx_flit_i[33:32]==FLIT_TAIL)begin rd[rxtag[SW-1:0]]<=1;rxphase<=0;end
            else begin rxbeat<=rxbeat+1'b1;rxphase<=1;end
          end
        end
      end
    end
  end
`ifndef SYNTHESIS
  initial begin
    assert(SLOTS>=1&&SLOTS<=8&&(SLOTS&(SLOTS-1))==0)else $fatal(1,"AXI slots must be 1,2,4,8");
    assert(MAX_BEATS>=2&&MAX_BEATS<=16&&(MAX_BEATS&(MAX_BEATS-1))==0)else $fatal(1,"Burst capacity 2,4,8,16");
  end
  always @(posedge clk_i)if(rst_ni)begin
    assert(credit<=FIFO_DEPTH&&rcount<=SLOTS&&wcount<=SLOTS)else $fatal(1,"Burst NI capacity");
    if(rx_valid_i&&rx_vc_i&&rx_flit_i[33:32]==FLIT_HEAD)begin
      assert(rxphase==0&&rx_flit_i[13:11]<SLOTS)else $fatal(1,"Unexpected burst response");
      if(rx_flit_i[14])assert(wb[rx_flit_i[11+:SW]]&&!wd[rx_flit_i[11+:SW]])else $fatal(1,"Unexpected B tag");
      else assert(rb[rx_flit_i[11+:SW]]&&!rd[rx_flit_i[11+:SW]]&&rx_flit_i[10:3]==rlen[rx_flit_i[11+:SW]])
        else $fatal(1,"Unexpected R tag/length");
    end
    if(rx_valid_i&&rx_vc_i&&rxphase==2&&!rxwrite)
      assert((rx_flit_i[33:32]==FLIT_TAIL)==(rxbeat==rlen[rxtag[SW-1:0]]))else $fatal(1,"Burst response length");
  end
`endif
endmodule
