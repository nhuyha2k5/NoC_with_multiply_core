// Queued initiator: every accepted request reserves response storage.
// Network replies carry tags and may arrive out of order; AXI retires in order.
module axi_lite_to_mesh #(
  parameter int FIFO_DEPTH=4, OUTSTANDING=4,
  parameter logic [1:0] CURRENT_X=0,CURRENT_Y=0,
  localparam int SLOT_W=(OUTSTANDING<=1)?1:$clog2(OUTSTANDING),
  localparam int COUNT_W=$clog2(OUTSTANDING+1),
  localparam int CREDIT_W=$clog2(FIFO_DEPTH+1)
)(
  input logic clk_i,rst_ni,
  input logic tx_ready_i=1'b1,
  input logic [1:0] qos_i=2'b00,
  axi_lite_if.slave s_axi,
  output logic [33:0] tx_flit_o,
  output logic tx_valid_o,tx_vc_o,
  input logic [1:0] tx_credit_i,
  input logic [33:0] rx_flit_i,
  input logic rx_valid_i,rx_vc_i,
  output logic [1:0] rx_credit_o
);
  import router_pkg::*;
  logic [OUTSTANDING-1:0] busy_q,done_q,write_q;
  logic [31:0] addr_q[OUTSTANDING],data_q[OUTSTANDING],result_q[OUTSTANDING];
  logic [3:0] strb_q[OUTSTANDING];
  logic [1:0] resp_q[OUTSTANDING],qos_q[OUTSTANDING];
  logic [SLOT_W-1:0] alloc_q,retire_q,issue_slot;
  logic [COUNT_W-1:0] count_q;
  logic aw_hold_q,w_hold_q;
  logic [31:0] awaddr_q,wdata_q;
  logic [3:0] wstrb_q;
  logic allocate,allocate_write,retire,issue_empty,issue_full,issue_pop;
  logic [31:0] allocate_addr;
  logic issue_legal;
  logic [1:0] tx_phase_q;
  logic [CREDIT_W-1:0] credit_q;
  logic tx_fire,rx_head_q;
  logic [3:0] rx_tag_q;
  logic [1:0] rx_resp_q;
  logic [3:0] coord;
  function automatic logic [SLOT_W-1:0] next_slot(input logic [SLOT_W-1:0] p);
    return p==OUTSTANDING-1 ? '0 : p+1'b1;
  endfunction
  assign s_axi.awready=rst_ni&&!aw_hold_q;
  assign s_axi.wready=rst_ni&&!w_hold_q;
  assign s_axi.arready=rst_ni&&(count_q<OUTSTANDING)&&!(aw_hold_q&&w_hold_q);
  assign allocate_write=aw_hold_q&&w_hold_q;
  assign allocate=rst_ni&&(count_q<OUTSTANDING)&&(allocate_write||(s_axi.arvalid&&s_axi.arready));
  assign allocate_addr=allocate_write?awaddr_q:s_axi.araddr;
  assign issue_legal=supported_address(allocate_addr)&&allocate_addr[1:0]==0;
  assign s_axi.rvalid=rst_ni&&(count_q!=0)&&done_q[retire_q]&&!write_q[retire_q];
  assign s_axi.bvalid=rst_ni&&(count_q!=0)&&done_q[retire_q]&&write_q[retire_q];
  assign s_axi.rdata=result_q[retire_q];
  assign s_axi.rresp=resp_q[retire_q];
  assign s_axi.bresp=resp_q[retire_q];
  assign retire=(s_axi.rvalid&&s_axi.rready)||(s_axi.bvalid&&s_axi.bready);
  vc_fifo #(.WIDTH(SLOT_W),.DEPTH(OUTSTANDING)) u_issue(
    .clk_i,.rst_ni,.push_i(allocate&&issue_legal),.data_i(alloc_q),
    .pop_i(issue_pop),.data_o(issue_slot),.empty_o(issue_empty),.full_o(issue_full),.count_o());
  assign coord=address_coord(addr_q[issue_slot]);
  assign tx_valid_o=rst_ni&&!issue_empty&&(credit_q!=0);
  assign tx_vc_o=0;
  assign tx_fire=tx_valid_o&&tx_ready_i;
  assign issue_pop=tx_fire&&tx_phase_q==2;
  always_comb begin
    tx_flit_o='0;
    case(tx_phase_q)
      0:begin
        tx_flit_o=make_head(coord[3:2],coord[1:0],CURRENT_X,CURRENT_Y,
                           write_q[issue_slot]?NOC_WRITE_REQ:NOC_READ_REQ,strb_q[issue_slot]);
        tx_flit_o[14:11]=4'(issue_slot);
        tx_flit_o[2:1]=qos_q[issue_slot];
      end
      1:tx_flit_o={FLIT_BODY,addr_q[issue_slot]};
      2:tx_flit_o={FLIT_TAIL,write_q[issue_slot]?data_q[issue_slot]:32'b0};
      default:;
    endcase
    rx_credit_o=0;
    if(rst_ni&&rx_valid_i)rx_credit_o[rx_vc_i]=1;
  end
  always_ff @(posedge clk_i)begin
    if(!rst_ni)begin
      busy_q<=0;done_q<=0;write_q<=0;alloc_q<=0;retire_q<=0;count_q<=0;
      aw_hold_q<=0;w_hold_q<=0;awaddr_q<=0;wdata_q<=0;wstrb_q<=0;
      tx_phase_q<=0;credit_q<=FIFO_DEPTH;rx_head_q<=0;rx_tag_q<=0;rx_resp_q<=0;
    end else begin
      if(s_axi.awvalid&&s_axi.awready)begin aw_hold_q<=1;awaddr_q<=s_axi.awaddr;end
      if(s_axi.wvalid&&s_axi.wready)begin w_hold_q<=1;wdata_q<=s_axi.wdata;wstrb_q<=s_axi.wstrb;end
      if(allocate)begin
        busy_q[alloc_q]<=1;done_q[alloc_q]<=!issue_legal;write_q[alloc_q]<=allocate_write;
        addr_q[alloc_q]<=allocate_addr;data_q[alloc_q]<=wdata_q;
        strb_q[alloc_q]<=allocate_write?wstrb_q:4'b0;
        // Interrupt management and NoC control are latency-sensitive MMIO.
        qos_q[alloc_q]<=(allocate_addr[31:24]==8'h0c||allocate_addr[31:24]==8'h02||allocate_addr[31:12]==20'h30002||
                        allocate_addr[31:12]==20'h30006)?2'd3:qos_i;
        result_q[alloc_q]<=0;resp_q[alloc_q]<=issue_legal?2'b00:2'b11;
        alloc_q<=next_slot(alloc_q);
        if(allocate_write)begin aw_hold_q<=0;w_hold_q<=0;end
      end
      if(retire)begin busy_q[retire_q]<=0;done_q[retire_q]<=0;retire_q<=next_slot(retire_q);end
      case({allocate,retire})
        2'b10:count_q<=count_q+1'b1;
        2'b01:count_q<=count_q-1'b1;
        default:;
      endcase
      if(tx_fire)tx_phase_q<=tx_phase_q==2?0:tx_phase_q+1'b1;
      case({tx_credit_i[0],tx_fire})
        2'b10:credit_q<=credit_q+1'b1;
        2'b01:credit_q<=credit_q-1'b1;
        default:;
      endcase
      if(rx_valid_i&&rx_vc_i)begin
        if(rx_flit_i[33:32]==FLIT_HEAD)begin
          rx_head_q<=1;rx_tag_q<=rx_flit_i[14:11];rx_resp_q<=rx_flit_i[16:15];
        end else if(rx_flit_i[33:32]==FLIT_TAIL&&rx_head_q)begin
          rx_head_q<=0;
          if(rx_tag_q<OUTSTANDING)begin
            result_q[rx_tag_q]<=rx_flit_i[31:0];resp_q[rx_tag_q]<=rx_resp_q;done_q[rx_tag_q]<=1;
          end
        end
      end
    end
  end
`ifndef SYNTHESIS
  initial assert(OUTSTANDING>=1&&OUTSTANDING<=16)else $fatal(1,"NI tags support 1..16 slots");
  always @(posedge clk_i)if(rst_ni)begin
    assert(count_q<=OUTSTANDING&&credit_q<=FIFO_DEPTH)else $fatal(1,"NI capacity/credit overflow");
    if(rx_valid_i&&rx_vc_i&&rx_flit_i[33:32]==FLIT_HEAD)
      assert(!rx_head_q)else $fatal(1,"Nested response header");
    if(rx_valid_i&&rx_vc_i&&rx_flit_i[33:32]==FLIT_TAIL)
      assert(rx_head_q&&rx_tag_q<OUTSTANDING&&busy_q[rx_tag_q]&&!done_q[rx_tag_q])
        else $fatal(1,"Unexpected/duplicate response tag %0d",rx_tag_q);
  end
`endif
endmodule
