// VC707 board wrapper, parameterized SoC clock and four firmware images.
module vc707_top #(
  parameter int CLOCK_HZ=100_000_000,
  parameter string ROM0_INIT_FILE="core0.mem",
  parameter string ROM1_INIT_FILE="core1.mem",
  parameter string ROM2_INIT_FILE="core2.mem",
  parameter string ROM3_INIT_FILE="core3.mem"
) (
  input  logic       SYSCLK_P,
  input  logic       SYSCLK_N,
  input  logic       CPU_RESET,
  input  logic [7:0] GPIO_DIP_SW,
  output logic [7:0] GPIO_LED,
  output logic       USB_UART_TX
);
  logic clk_200mhz, clk_fb, clk_fb_buf, clk_50mhz_raw, clk_50mhz;
  logic mmcm_locked;
  (* ASYNC_REG="TRUE" *) logic [3:0] reset_sync_q;
  // Plain (no async set/reset) register that drives the SoC reset tree. BRAM
  // enables that include rst_ni are then driven by a synchronously timed
  // register, which removes the RAMB async-control hazard (DRC REQP-1839).
  logic rst_q = 1'b0;
  logic rst_ni;
  logic [7:0] gpio_data, gpio_oe;
  logic uart_tx;
  // Board outputs leave from IOB flip-flops: one cycle of latency on LEDs/UART
  // in exchange for a short, fixed clock-to-pad path.
  (* IOB="TRUE" *) logic [7:0] led_q = '0;
  (* IOB="TRUE" *) logic uart_q = 1'b1;
  (* ASYNC_REG="TRUE" *) logic [7:0] dip_meta_q,dip_sync_q;

  IBUFDS #(
    .DIFF_TERM("TRUE"),
    .IBUF_LOW_PWR("FALSE"),
    .IOSTANDARD("LVDS")
  ) u_sysclk_ibuf (
    .I(SYSCLK_P), .IB(SYSCLK_N), .O(clk_200mhz)
  );

  // 200 MHz / 1 * 5 = 1000 MHz VCO; output divider follows CLOCK_HZ.
  MMCME2_BASE #(
    .BANDWIDTH("OPTIMIZED"),
    .CLKIN1_PERIOD(5.0),
    .DIVCLK_DIVIDE(1),
    .CLKFBOUT_MULT_F(5.0),
    .CLKOUT0_DIVIDE_F(1_000_000_000.0/CLOCK_HZ),
    .STARTUP_WAIT("FALSE")
  ) u_clock_mmcm (
    .CLKIN1(clk_200mhz),
    .CLKFBIN(clk_fb_buf),
    .RST(CPU_RESET),
    .PWRDWN(1'b0),
    .CLKFBOUT(clk_fb),
    .CLKOUT0(clk_50mhz_raw),
    .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
    .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
    .LOCKED(mmcm_locked)
  );

  BUFG u_feedback_buf (.I(clk_fb), .O(clk_fb_buf));
  BUFG u_soc_clock_buf (.I(clk_50mhz_raw), .O(clk_50mhz));

  // Assert asynchronously while the MMCM is unlocked, release synchronously,
  // then retime once more without async control. Every SoC reset is
  // synchronous and is held for several cycles, so the extra cycle is harmless.
  always_ff @(posedge clk_50mhz or negedge mmcm_locked) begin
    if (!mmcm_locked) reset_sync_q <= '0;
    else              reset_sync_q <= {reset_sync_q[2:0], 1'b1};
  end
  always_ff @(posedge clk_50mhz) rst_q <= reset_sync_q[3];
  assign rst_ni = rst_q;
  always_ff @(posedge clk_50mhz) begin
    led_q  <= gpio_data & gpio_oe;
    uart_q <= uart_tx;
  end
  assign GPIO_LED = led_q;
  assign USB_UART_TX = uart_q;
  always_ff @(posedge clk_50mhz)
    if(!rst_ni)begin dip_meta_q<=0;dip_sync_q<=0;end
    else begin dip_meta_q<=GPIO_DIP_SW;dip_sync_q<=dip_meta_q;end

  ibex_mesh_soc #(.CLOCK_HZ(CLOCK_HZ),.ROM0_INIT_FILE(ROM0_INIT_FILE),.ROM1_INIT_FILE(ROM1_INIT_FILE),
                .ROM2_INIT_FILE(ROM2_INIT_FILE),.ROM3_INIT_FILE(ROM3_INIT_FILE)) u_soc (
    .clk_i(clk_50mhz),
    .rst_ni,
    .gpio_i(dip_sync_q),
    .gpio_o(gpio_data),
    .gpio_oe_o(gpio_oe),
    .uart_tx_o(uart_tx),
    .debug_pc0_o(), .debug_pc1_o(), .debug_pc2_o(), .debug_pc3_o(),
    .cache0_hits_o(), .cache0_misses_o(),
    .cache1_hits_o(), .cache1_misses_o(),
    .cache2_hits_o(), .cache2_misses_o(),
    .cache3_hits_o(), .cache3_misses_o()
  );
endmodule
