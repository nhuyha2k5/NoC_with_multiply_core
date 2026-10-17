// Unified memory endpoint for legacy single-word and AXI4 burst packets.
// Slots pipeline parsing, RAM execution and network response serialization.
module mesh_to_axi4 #(
  parameter int SLOTS=2,MAX_BEATS=16,FIFO_DEPTH=4,
  parameter logic[1:0] CURRENT_X=1,CURRENT_Y=1,
  localparam int SW=(SLOTS<2)?1:$clog2(SLOTS),
  localparam int BW=$clog2(MAX_BEATS),localparam int CW=$clog2(FIFO_DEPTH+1)
)(
  input logic clk_i,rst_ni,
  input logic[33:0] rx_flit_i,
  input logic rx_valid_i,rx_vc_i,
  output logic[1:0] rx_credit_o,
  output logic[33:0] tx_flit_o,
  output logic tx_valid_o,tx_vc_o,
  input logic[1:0] tx_credit_i,
  axi4_if.master m_axi
);
  import router_pkg::*;
  logic[33:0] flit,head[SLOTS];
  logic[SLOTS-1:0] filled,done,writes,bursts;
  logic[31:0] address[SLOTS],data[SLOTS][MAX_BEATS];
  logic[3:0] strobes[SLOTS][MAX_BEATS];
  logic[1:0] codes[SLOTS][MAX_BEATS],bcodes[SLOTS];
  logic[7:0] len[SLOTS],pbeat,ebeat,tbeat;
  logic[SW-1:0] alloc,execute,retire;
  logic[$clog2(SLOTS+1)-1:0] count;
  logic[2:0] parser,engine;
  logic[1:0] serializer;
  logic empty,pop,claim,release_slot,tf;
  logic[CW-1:0] credit;
  function automatic logic[SW-1:0] nxt(input logic[SW-1:0] p);
    return p==SLOTS-1?'0:p+1'b1;
  endfunction
  vc_fifo #(.WIDTH(34),.DEPTH(FIFO_DEPTH)) u_rx(
    .clk_i,.rst_ni,.push_i(rx_valid_i&&!rx_vc_i),.data_i(rx_flit_i),.pop_i(pop),
    .data_o(flit),.empty_o(empty),.full_o(),.count_o());
  assign pop=!empty&&(parser!=0||count<SLOTS);
  assign claim=pop&&parser==0&&flit[33:32]==FLIT_HEAD;
  assign rx_credit_o={rx_valid_i&&rx_vc_i,pop};
  assign m_axi.awaddr=address[execute];
  assign m_axi.awid=head[execute][14:11];
  assign m_axi.awlen=len[execute];
  assign m_axi.awsize=2;assign m_axi.awburst=1;assign m_axi.awlock=0;
  assign m_axi.awcache=0;assign m_axi.awprot=0;assign m_axi.awqos={2'b0,head[execute][2:1]};
  assign m_axi.awvalid=rst_ni&&engine==3;
  assign m_axi.wdata=data[execute][ebeat[BW-1:0]];
  assign m_axi.wstrb=strobes[execute][ebeat[BW-1:0]];
  assign m_axi.wlast=ebeat==len[execute];
  assign m_axi.wvalid=rst_ni&&engine==4;
  assign m_axi.bready=engine==5;
  assign m_axi.araddr=address[execute];
  assign m_axi.arid=head[execute][14:11];
  assign m_axi.arlen=len[execute];
  assign m_axi.arsize=2;assign m_axi.arburst=1;assign m_axi.arlock=0;
  assign m_axi.arcache=0;assign m_axi.arprot=0;assign m_axi.arqos={2'b0,head[execute][2:1]};
  assign m_axi.arvalid=rst_ni&&engine==1;
  assign m_axi.rready=engine==2;
  assign tx_valid_o=rst_ni&&count!=0&&done[retire]&&credit!=0;
  assign tx_vc_o=1;
  assign tf=tx_valid_o;
  assign release_slot=tf&&(serializer==3||(serializer==2&&tbeat==len[retire]));
  always_comb begin
    tx_flit_o=0;
    case(serializer)
      0:begin
        tx_flit_o=make_head(head[retire][27:26],head[retire][25:24],CURRENT_X,CURRENT_Y,
          writes[retire]?(bcodes[retire]==0?NOC_WRITE_RESP:NOC_ERROR_RESP):
          (bursts[retire]?NOC_BURST_READ:(codes[retire][0]==0?NOC_READ_RESP:NOC_ERROR_RESP)),0);
        tx_flit_o[14:11]=head[retire][14:11];tx_flit_o[10:3]=len[retire];
        tx_flit_o[16:15]=writes[retire]?bcodes[retire]:codes[retire][0];
        tx_flit_o[2:1]=head[retire][2:1];
      end
      1:tx_flit_o={FLIT_BODY,30'b0,codes[retire][tbeat[BW-1:0]]};
      2:tx_flit_o={tbeat==len[retire]?FLIT_TAIL:FLIT_BODY,data[retire][tbeat[BW-1:0]]};
      3:tx_flit_o={FLIT_TAIL,writes[retire]?{30'b0,bcodes[retire]}:data[retire][0]};
    endcase
  end
  always_ff @(posedge clk_i)begin
    if(!rst_ni)begin
      filled<=0;done<=0;writes<=0;bursts<=0;alloc<=0;execute<=0;retire<=0;
      count<=0;parser<=0;engine<=0;serializer<=0;pbeat<=0;ebeat<=0;tbeat<=0;credit<=FIFO_DEPTH;
    end else begin
      case({claim,release_slot})2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;default:;endcase
      if(pop)case(parser)
        0:if(claim)begin
          head[alloc]<=flit;filled[alloc]<=0;done[alloc]<=0;pbeat<=0;
          writes[alloc]<=flit[23:21]==NOC_WRITE_REQ||flit[23:21]==NOC_BURST_WRITE;
          bursts[alloc]<=flit[23:21]==NOC_BURST_READ||flit[23:21]==NOC_BURST_WRITE;
          len[alloc]<=(flit[23:21]==NOC_BURST_READ||flit[23:21]==NOC_BURST_WRITE)?flit[10:3]:0;
          parser<=1;
        end
        1:begin address[alloc]<=flit[31:0];parser<=bursts[alloc]&&writes[alloc]?3:2;end
        2:begin
          data[alloc][0]<=flit[31:0];strobes[alloc][0]<=head[alloc][20:17];
          filled[alloc]<=1;alloc<=nxt(alloc);parser<=0;
        end
        3:begin strobes[alloc][pbeat[BW-1:0]]<=flit[3:0];parser<=4;end
        4:begin
          data[alloc][pbeat[BW-1:0]]<=flit[31:0];
          if(pbeat==len[alloc])begin filled[alloc]<=1;alloc<=nxt(alloc);parser<=0;end
          else begin pbeat<=pbeat+1'b1;parser<=3;end
        end
        default:parser<=0;
      endcase
      case(engine)
        0:if(filled[execute]&&!done[execute])begin engine<=writes[execute]?3:1;ebeat<=0;end
        1:if(m_axi.arready)engine<=2;
        2:if(m_axi.rvalid)begin
          data[execute][ebeat[BW-1:0]]<=m_axi.rdata;codes[execute][ebeat[BW-1:0]]<=m_axi.rresp;
          if(m_axi.rlast)begin done[execute]<=1;execute<=nxt(execute);engine<=0;end
          else ebeat<=ebeat+1'b1;
        end
        3:if(m_axi.awready)engine<=4;
        4:if(m_axi.wready)begin if(m_axi.wlast)engine<=5;else ebeat<=ebeat+1'b1;end
        5:if(m_axi.bvalid)begin bcodes[execute]<=m_axi.bresp;done[execute]<=1;execute<=nxt(execute);engine<=0;end
        default:engine<=0;
      endcase
      if(tf)case(serializer)
        0:begin serializer<=bursts[retire]&&!writes[retire]?1:3;tbeat<=0;end
        1:serializer<=2;
        2:if(tbeat==len[retire])serializer<=0;else begin serializer<=1;tbeat<=tbeat+1'b1;end
        3:serializer<=0;
      endcase
      if(release_slot)begin filled[retire]<=0;done[retire]<=0;retire<=nxt(retire);end
      case({tx_credit_i[1],tf})2'b10:credit<=credit+1'b1;2'b01:credit<=credit-1'b1;default:;endcase
    end
  end
`ifndef SYNTHESIS
  always @(posedge clk_i)if(rst_ni)begin
    assert(credit<=FIFO_DEPTH&&count<=SLOTS)else $fatal(1,"Memory NI capacity");
    if(claim)begin
      assert(flit[23:21]==NOC_READ_REQ||flit[23:21]==NOC_WRITE_REQ||flit[23:21]==NOC_BURST_READ||flit[23:21]==NOC_BURST_WRITE)
        else $fatal(1,"Invalid memory request opcode");
      if(flit[23:21]==NOC_BURST_READ||flit[23:21]==NOC_BURST_WRITE)
        assert(flit[10:3]<MAX_BEATS)else $fatal(1,"Burst exceeds endpoint storage");
    end
    if(engine==2&&m_axi.rvalid)assert(m_axi.rlast==(ebeat==len[execute]))else $fatal(1,"RAM RLAST mismatch");
  end
`endif
endmodule
