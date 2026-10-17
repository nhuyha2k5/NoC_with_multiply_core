// MMIO policy and router counters at 0x30006000, accessed through node 5.
// POLICY (+8): [1:0] mode, [2] class priority, [3] aging disable,
// [11:8] age limit, [19:16]/[23:20] VC0/VC1 weights.
module noc_control(
  input logic clk_i,rst_ni,wr_en_i,
  input logic[7:0] wr_offset_i,rd_offset_i,
  input logic[31:0] wr_data_i,input logic[3:0] wr_strb_i,
  output logic[31:0] rd_data_o,output logic[1:0] wr_resp_o,rd_resp_o,
  input logic[1439:0] flits_i='0,packets_i='0,stalls_i='0,
  input logic[359:0] peaks_i='0,
  output logic[1:0] qos_mode_o,output logic qos_classes_o,qos_aging_o,
  output logic[3:0] qos_age_o,output logic[7:0] qos_weights_o,source_classes_o,dma_gap_o,
  output logic counters_enable_o,counters_clear_o
);
  logic[31:0] control,policy,selector,merged_policy;
  logic[63:0] cycles;
  logic[5:0] index_q;
  function automatic logic valid_offset(input logic[7:0] a);
    return a[1:0]==0&&a<=44;
  endfunction
  assign qos_mode_o=policy[1:0];assign qos_classes_o=policy[2];assign qos_aging_o=!policy[3];
  assign qos_age_o=policy[11:8];assign qos_weights_o=policy[23:16];
  assign counters_enable_o=control[0]&&!control[1];
  always_comb begin
    merged_policy=policy;
    for(int b=0;b<4;b++)if(wr_strb_i[b])merged_policy[b*8+:8]=wr_data_i[b*8+:8];
    wr_resp_o=valid_offset(wr_offset_i)?0:3;rd_resp_o=valid_offset(rd_offset_i)?0:3;
    if(wr_resp_o==0)begin
      if(wr_offset_i==0||wr_offset_i>=24)wr_resp_o=2;
      if(wr_offset_i==8&&(merged_policy[1:0]>2||merged_policy[11:8]==0||
         merged_policy[19:16]==0||merged_policy[23:20]==0))wr_resp_o=2;
      if(wr_offset_i==20&&wr_strb_i[0]&&(wr_data_i[3:0]>8||wr_data_i[6:4]>4))wr_resp_o=2;
    end
    rd_data_o=0;
    case(rd_offset_i)
      0:rd_data_o=32'h4e4f4303;4:rd_data_o=control;8:rd_data_o=policy;
      12:rd_data_o={24'b0,source_classes_o};16:rd_data_o={24'b0,dma_gap_o};20:rd_data_o=selector;
      24:rd_data_o=flits_i[index_q*32+:32];28:rd_data_o=packets_i[index_q*32+:32];
      32:rd_data_o=stalls_i[index_q*32+:32];36:rd_data_o={24'b0,peaks_i[index_q*8+:8]};
      40:rd_data_o=cycles[31:0];44:rd_data_o=cycles[63:32];default:;
    endcase
  end
  always_ff @(posedge clk_i)begin
    if(!rst_ni)begin
      control<=1;policy<=32'h00310f05;selector<=0;index_q<=0;source_classes_o<=8'h4a;
      dma_gap_o<=0;cycles<=0;counters_clear_o<=0;
    end else begin
      counters_clear_o<=0;
      if(counters_clear_o)cycles<=0;else if(counters_enable_o)cycles<=cycles+1'b1;
      if(wr_en_i&&wr_resp_o==0)case(wr_offset_i)
        4:if(wr_strb_i[0])begin control<={30'b0,wr_data_i[1:0]};counters_clear_o<=wr_data_i[2];end
        8:policy<=merged_policy&32'h00ff0f0f;
        12:if(wr_strb_i[0])source_classes_o<=wr_data_i[7:0];
        16:if(wr_strb_i[0])dma_gap_o<=wr_data_i[7:0];
        20:if(wr_strb_i[0])begin
          selector<={25'b0,wr_data_i[6:0]};index_q<=6'(wr_data_i[3:0])*6'd5+6'(wr_data_i[6:4]);
        end
        default:;
      endcase
    end
  end
endmodule
