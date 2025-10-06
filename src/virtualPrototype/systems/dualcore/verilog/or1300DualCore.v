module or1300DualCore ( input wire         clock12MHz,
                                             clock50MHz,
                                             nReset,
                          input wire         RxD,
                          output wire        TxD,

                          output wire        sdramClk,
                          output wire        sdramCke,
                                             sdramCsN,
                                             sdramRasN,
                                             sdramCasN,
                                             sdramWeN,
                          output wire [1:0]  sdramDqmN,
                          output wire [12:0] sdramAddr,
                          output wire [1:0]  sdramBa,
                          inout wire [15:0]  sdramData,

                          // The spi interface
                          output wire        spiScl,
                                             spiNCs,
                          inout wire         spiSiIo0,
                                             spiSoIo1,
                                             spiIo2,
                                             spiIo3,
                          output             pixelClock,
                                             horizontalSync,
                                             verticalSync,
                                             activePixel,
`ifdef GECKO5Education
                          output wire [4:0]  hdmiRed,
                                             hdmiBlue,
                                             hdmiGreen,

                          output wire [2:0]  displaySelect,
                          output wire [7:0]  nSegments,

                          output wire [3:0]  rgbRow,
                          output wire [9:0]  red,
                                             green,
                                             blue,

                          input wire [4:0]   nButtons, 
                          input wire [7:0]   nDipSwitch,
                          input wire [4:0]   nJoystick,
`else
                          output [3:0]       hdmiRed,
                                             hdmiGreen,
                                             hdmiBlue,

                          output wire [7:0]  display1,
                                             display2,
                                             display3,
                                             display4,

                          output wire [107:0] leds,

                          input wire [6:1]   nButtons, // nButtons[0] is dedicated for reset
                          input wire [7:0]   nDipSwitch1,
                          input wire [7:0]   nDipSwitch2,
`endif
                          output wire        SCL,
                          inout wire         SDA,
                          input wire         camPclk,
                                             camHsync,
                                             camVsync,
                          input wire [7:0]   camData
                           );

  wire        s_busIdle, s_snoopableBurst, s_cpu1BarrierValue, s_cpu2BarrierValue;
  wire        s_hdmiDone, s_hdmiDone1, s_systemClock, s_systemClockX2, s_swapByteDone, s_swapByteDone1, s_flashDone;
  wire [31:0] s_hdmiResult, s_hdmiResult1, s_swapByteResult, s_swapByteResult1, s_flashResult;
  wire [7:0]  s_barrierValues = { {6{s_cpu1BarrierValue}}, s_cpu2BarrierValue, s_cpu1BarrierValue};
  wire [5:0]  s_memoryDistance;
  wire        s_busError, s_beginTransaction, s_endTransaction;
  wire [31:0] s_addressData;
  wire [3:0]  s_byteEnables;
  wire        s_readNotWrite, s_dataValid, s_busy, s_privateData, s_privateDirty;
  wire [7:0]  s_burstSize;
  
  /*
   *
   * We use a PLL to generate the required clocks for the HDMI part
   *
   */
  reg[4:0] s_resetCountReg, s_softResetCountReg;
  wire     s_pixelClock;
  wire     s_pixelClkX2;
  wire     s_pllLocked;
  wire     s_reset = ~s_resetCountReg[4];
  wire     s_performSoftReset;

  always @(posedge s_systemClock or negedge s_pllLocked)
    if (s_pllLocked == 1'b0) s_resetCountReg <= 5'd0;
    else s_resetCountReg <= (s_resetCountReg[4] == 1'b0) ? s_resetCountReg + 5'd1 : s_resetCountReg;
  
  always @(posedge s_systemClock)
    s_softResetCountReg <= (s_resetCountReg[4] == 1'b0) ? 5'b10000 :
                           (s_softResetCountReg[4] == 1'b1 && s_performSoftReset == 1'b1) ? 5'd0 :
                           (s_softResetCountReg[4] == 1'b0) ? s_softResetCountReg + 5'd1 : s_softResetCountReg;

`ifdef GECKO5Education
  wire s_resetPll = ~nReset;
  wire s_feedbackClock;

  EHXPLLL #(
        .PLLRST_ENA("ENABLED"),
        .INTFB_WAKE("DISABLED"),
        .STDBY_ENABLE("DISABLED"),
        .DPHASE_SOURCE("DISABLED"),
        .OUTDIVIDER_MUXA("DIVA"),
        .OUTDIVIDER_MUXB("DIVB"),
        .OUTDIVIDER_MUXC("DIVC"),
        .OUTDIVIDER_MUXD("DIVD"),
        .CLKI_DIV(1),
        .CLKOP_ENABLE("ENABLED"),
        .CLKOP_DIV(4),
        .CLKOP_CPHASE(1),
        .CLKOP_FPHASE(0),
        .CLKOS_ENABLE("ENABLED"),
        .CLKOS_DIV(8),
        .CLKOS_CPHASE(1),
        .CLKOS_FPHASE(0),
        .CLKOS2_ENABLE("ENABLED"),
        .CLKOS2_DIV(10),
        .CLKOS2_CPHASE(1),
        .CLKOS2_FPHASE(0),
        .CLKOS3_ENABLE("ENABLED"),
        .CLKOS3_DIV(5),
        .CLKOS3_CPHASE(1),
        .CLKOS3_FPHASE(0),
        .FEEDBK_PATH("INT_OP"),
        .CLKFB_DIV(2)
    ) pll_1 (
        .RST(s_resetPll),
        .STDBY(1'b0),
        .CLKI(clock12MHz),
        .CLKOP(s_pixelClkX2),
        .CLKOS(s_pixelClock),
        .CLKOS2(s_systemClock),
        .CLKOS3(s_systemClockX2),
        .CLKFB(s_feedbackClock),
        .CLKINTFB(s_feedbackClock),
        .PHASESEL0(1'b0),
        .PHASESEL1(1'b0),
        .PHASEDIR(1'b1),
        .PHASESTEP(1'b1),
        .PHASELOADREG(1'b1),
        .PLLWAKESYNC(1'b0),
        .ENCLKOP(1'b0),
        .LOCK(s_pllLocked)
	);
`else
  wire[4:0] s_pllClocks;
  
  assign s_pixelClock = s_pllClocks[0];
  assign s_pixelClkX2 = s_pllClocks[1];
  assign s_systemClock = s_pllClocks[2];
  assign s_systemClockX2 = s_pllClocks[3];

  
	altpll	altpll_component (
				.areset (~nReset),
				.inclk ({1'b0,clock12MHz}),
				.clk (s_pllClocks),
				.locked (s_pllLocked),
				.activeclock (),
				.clkbad (),
				.clkena ({6{1'b1}}),
				.clkloss (),
				.clkswitch (1'b0),
				.configupdate (1'b0),
				.enable0 (),
				.enable1 (),
				.extclk (),
				.extclkena ({4{1'b1}}),
				.fbin (1'b1),
				.fbmimicbidir (),
				.fbout (),
				.fref (),
				.icdrclk (),
				.pfdena (1'b1),
				.phasecounterselect ({4{1'b1}}),
				.phasedone (),
				.phasestep (1'b1),
				.phaseupdown (1'b1),
				.pllena (1'b1),
				.scanaclr (1'b0),
				.scanclk (1'b0),
				.scanclkena (1'b1),
				.scandata (1'b0),
				.scandataout (),
				.scandone (),
				.scanread (1'b0),
				.scanwrite (1'b0),
				.sclkout0 (),
				.sclkout1 (),
				.vcooverrange (),
				.vcounderrange ());
	defparam
		altpll_component.bandwidth_type = "AUTO",
		altpll_component.clk0_divide_by = 16,
		altpll_component.clk0_duty_cycle = 50,
		altpll_component.clk0_multiply_by = 99,
		altpll_component.clk0_phase_shift = "0",
		altpll_component.clk1_divide_by = 8,
		altpll_component.clk1_duty_cycle = 50,
		altpll_component.clk1_multiply_by = 99,
		altpll_component.clk1_phase_shift = "0",
		altpll_component.clk2_divide_by = 28,
		altpll_component.clk2_duty_cycle = 50,
		altpll_component.clk2_multiply_by = 99,
		altpll_component.clk2_phase_shift = "0",
		altpll_component.clk3_divide_by = 14,
		altpll_component.clk3_duty_cycle = 50,
		altpll_component.clk3_multiply_by = 99,
		altpll_component.clk3_phase_shift = "0",
		altpll_component.compensate_clock = "CLK0",
		altpll_component.inclk0_input_frequency = 83333,
		altpll_component.intended_device_family = "Cyclone IV E",
		altpll_component.lpm_hint = "CBX_MODULE_PREFIX=test",
		altpll_component.lpm_type = "altpll",
		altpll_component.operation_mode = "NORMAL",
		altpll_component.pll_type = "AUTO",
		altpll_component.port_activeclock = "PORT_UNUSED",
		altpll_component.port_areset = "PORT_USED",
		altpll_component.port_clkbad0 = "PORT_UNUSED",
		altpll_component.port_clkbad1 = "PORT_UNUSED",
		altpll_component.port_clkloss = "PORT_UNUSED",
		altpll_component.port_clkswitch = "PORT_UNUSED",
		altpll_component.port_configupdate = "PORT_UNUSED",
		altpll_component.port_fbin = "PORT_UNUSED",
		altpll_component.port_inclk0 = "PORT_USED",
		altpll_component.port_inclk1 = "PORT_UNUSED",
		altpll_component.port_locked = "PORT_USED",
		altpll_component.port_pfdena = "PORT_UNUSED",
		altpll_component.port_phasecounterselect = "PORT_UNUSED",
		altpll_component.port_phasedone = "PORT_UNUSED",
		altpll_component.port_phasestep = "PORT_UNUSED",
		altpll_component.port_phaseupdown = "PORT_UNUSED",
		altpll_component.port_pllena = "PORT_UNUSED",
		altpll_component.port_scanaclr = "PORT_UNUSED",
		altpll_component.port_scanclk = "PORT_UNUSED",
		altpll_component.port_scanclkena = "PORT_UNUSED",
		altpll_component.port_scandata = "PORT_UNUSED",
		altpll_component.port_scandataout = "PORT_UNUSED",
		altpll_component.port_scandone = "PORT_UNUSED",
		altpll_component.port_scanread = "PORT_UNUSED",
		altpll_component.port_scanwrite = "PORT_UNUSED",
		altpll_component.port_clk0 = "PORT_USED",
		altpll_component.port_clk1 = "PORT_USED",
		altpll_component.port_clk2 = "PORT_USED",
		altpll_component.port_clk3 = "PORT_USED",
		altpll_component.port_clk4 = "PORT_UNUSED",
		altpll_component.port_clk5 = "PORT_UNUSED",
		altpll_component.port_clkena0 = "PORT_UNUSED",
		altpll_component.port_clkena1 = "PORT_UNUSED",
		altpll_component.port_clkena2 = "PORT_UNUSED",
		altpll_component.port_clkena3 = "PORT_UNUSED",
		altpll_component.port_clkena4 = "PORT_UNUSED",
		altpll_component.port_clkena5 = "PORT_UNUSED",
		altpll_component.port_extclk0 = "PORT_UNUSED",
		altpll_component.port_extclk1 = "PORT_UNUSED",
		altpll_component.port_extclk2 = "PORT_UNUSED",
		altpll_component.port_extclk3 = "PORT_UNUSED",
		altpll_component.self_reset_on_loss_lock = "OFF",
		altpll_component.width_clock = 5;

`endif

  /*
   * Here we instantiate the switches controller
   *
   */
  wire s_switchesEndTransaction, s_switchesDataValid, s_switchesBusError;
  wire s_dipswitchIrq, s_buttonsIrq, s_1KHzTick;
  wire [31:0] s_switchesAddressData;

  switches #( .cpuFrequencyInHz(`ifdef GECKO5Education 42857143 `else 42428571 `endif),
              .baseAddress(32'h50000080)) switchesAndJoy
            ( .clock(s_systemClock),
              .reset(s_reset),
              .oneKHzTick(s_1KHzTick),
              .irqDip(s_dipswitchIrq),
              .irqJoy(s_buttonsIrq),
              .beginTransactionIn(s_beginTransaction),
              .endTransactionIn(s_endTransaction),
              .readNotWriteIn(s_readNotWrite),
              .dataValidIn(s_dataValid),
              .busyIn(s_busy),
              .addressDataIn(s_addressData),
              .byteEnablesIn(s_byteEnables),
              .burstSizeIn(s_burstSize),
              .endTransactionOut(s_switchesEndTransaction),
              .dataValidOut(s_switchesDataValid),
              .busErrorOut(s_switchesBusError),
              .addressDataOut(s_switchesAddressData),
`ifdef GECKO5Education
              .nButtons(nButtons),
              .nDipSwitch(nDipSwitch),
              .nJoystick(nJoystick)
`else
              .nButtons(nButtons),
              .nDipSwitch1(nDipSwitch1),
              .nDipSwitch2(nDipSwitch2)
`endif
            );

  /*
   *
   * Here we instantiate the seven segments controller
   *
   */
  wire s_7SegEndTransaction, s_7SegDataValid, s_7SegBusError;
  wire [31:0] s_7SegAddressData;
  
  sevenSegments #( .initialBaseAddress(32'h50000060)) sevenSeg
                 ( .clock(s_systemClock),
                   .reset(s_reset),
                   .beginTransactionIn(s_beginTransaction),
                   .endTransactionIn(s_endTransaction),
                   .readNotWriteIn(s_readNotWrite),
                   .dataValidIn(s_dataValid),
                   .busyIn(s_busy),
                   .addressDataIn(s_addressData),
                   .byteEnablesIn(s_byteEnables),
                   .burstSizeIn(s_burstSize),
                   .endTransactionOut(s_7SegEndTransaction),
                   .dataValidOut(s_7SegDataValid),
                   .busErrorOut(s_7SegBusError),
                   .addressDataOut(s_7SegAddressData),
`ifdef GECKO5Education
                   .oneKhzTick(s_1KHzTick),
                   .displaySelect(displaySelect),
                   .nSegments(nSegments)
`else
                   .display1(display1),
                   .display2(display2),
                   .display3(display3),
                   .display4(display4)
`endif
                      );

  /*
   *
   * Here we instantiate the seven segments controller
   *
   */
  wire s_ledsEndTransaction, s_ledsDataValid, s_ledsBusError;
  wire [31:0] s_ledsAddressData;
  
  leds #(.initialBaseAddress(32'h50000800)) rgb
       ( .clock(s_systemClock),
         .reset(s_reset),
         .beginTransactionIn(s_beginTransaction),
         .endTransactionIn(s_endTransaction),
         .readNotWriteIn(s_readNotWrite),
         .dataValidIn(s_dataValid),
         .busyIn(s_busy),
         .busErrorIn(s_busError),
         .addressDataIn(s_addressData),
         .byteEnablesIn(s_byteEnables),
         .burstSizeIn(s_burstSize),
         .endTransactionOut(s_ledsEndTransaction),
         .dataValidOut(s_ledsDataValid),
         .busErrorOut(s_ledsBusError),
         .addressDataOut(s_ledsAddressData),
`ifdef GECKO5Education
         .oneKhzTick(s_1KHzTick),
         .rgbRow(rgbRow),
         .nRed(red),
         .nGreen(green),
         .nBlue(blue) 
`else
         .leds(leds)
`endif
             );

  /*
   * Here we instantiate the UART
   *
   */
  wire s_uartIrq, s_uartEndTransaction, s_uartDataValid, s_uartBusError;
  wire [31:0] s_uartAddressData;
  uartBus #( .baseAddress(32'h50000000) ) uart1
           ( .clock(s_systemClock),
             .clock_50MHz(clock50MHz),
             .reset(s_reset),
             .irq(s_uartIrq),
             .beginTransactionIn(s_beginTransaction),
             .endTransactionIn(s_endTransaction),
             .readNWriteIn(s_readNotWrite),
             .dataValidIn(s_dataValid),
             .busyIn(s_busy),
             .addressDataIn(s_addressData),
             .byteEnablesIn(s_byteEnables),
             .burstSizeIn(s_burstSize),
             .addressDataOut(s_uartAddressData),
             .endTransactionOut(s_uartEndTransaction),
             .dataValidOut(s_uartDataValid),
             .busErrorOut(s_uartBusError),
             .RxD(RxD),
             .TxD(TxD));
  /*
   * Here we instantiate a 8 kbyte SSRAM in uncacheable space (for locks for example)
   *
   */
  wire s_ssramEndTransaction, s_ssramDataValid;
  wire [31:0] s_ssramAddressData;
   
  ssram_8k #(.baseAddress(32'hE0000000)) ssram1
            (.clock(s_systemClock),
             .reset(s_cpuReset),
             .beginTransactionIn(s_beginTransaction),
             .endTransactionIn(s_endTransaction),
             .readNotWriteIn(s_readNotWrite),
             .dataValidIn(s_dataValid),
             .busyIn(s_busy),
             .busErrorIn(s_busError),
             .addressDataIn(s_addressData),
             .byteEnablesIn(s_byteEnables),
             .burstSizeIn(s_burstSize),
             .endTransactionOut(s_ssramEndTransaction),
             .dataValidOut(s_ssramDataValid),
             .addressDataOut(s_ssramAddressData));

  /*
   * Here we instantiate the SDRAM controller
   *
   */
  wire        s_sdramInitBusy, s_sdramEndTransaction, s_sdramDataValid;
  wire        s_sdramBusy, s_sdramBusError;
  wire [31:0] s_sdramAddressData;
  wire        s_cpuReset = s_reset | s_sdramInitBusy | ~s_softResetCountReg[4];
  
  sdramController #( .baseAddress(32'h00000000),
                     .systemClockInHz(`ifdef GECKO5Education 42857143 `else 42428571 `endif)) sdram
                   ( .clock(s_systemClock),
                     .clockX2(s_systemClockX2),
                     .reset(s_reset),
                     .memoryDistanceIn(s_memoryDistance),
                     .sdramInitBusy(s_sdramInitBusy),
                     .beginTransactionIn(s_beginTransaction),
                     .endTransactionIn(s_endTransaction),
                     .readNotWriteIn(s_readNotWrite),
                     .dataValidIn(s_dataValid),
                     .busErrorIn(s_busError),
                     .busyIn(s_busy),
                     .addressDataIn(s_addressData),
                     .byteEnablesIn(s_byteEnables),
                     .burstSizeIn(s_burstSize),
                     .endTransactionOut(s_sdramEndTransaction),
                     .dataValidOut(s_sdramDataValid),
                     .busyOut(s_sdramBusy),
                     .busErrorOut(s_sdramBusError),
                     .addressDataOut(s_sdramAddressData),
                     .sdramClk(sdramClk),
                     .sdramCke(sdramCke),
                     .sdramCsN(sdramCsN),
                     .sdramRasN(sdramRasN),
                     .sdramCasN(sdramCasN),
                     .sdramWeN(sdramWeN),
                     .sdramDqmN(sdramDqmN),
                     .sdramAddr(sdramAddr),
                     .sdramBa(sdramBa),
                     .sdramData(sdramData));

  /*
   * Here we instantiate the CPU
   *
   */
  wire [31:0] s_cpu1IrqVector, s_cpu1CiResult;
  wire [31:0] s_cpu1CiDataA, s_cpu1CiDataB;
  wire [7:0]  s_cpu1CiN;
  wire        s_cpu1CiRa, s_cpu1CiRb, s_cpu1CiRc, s_cpu1CiStart, s_cpu1CiCke, s_cpu1CiDone;
  wire [4:0]  s_cpu1CiA, s_cpu1CiB, s_cpu1CiC;
  wire [31:0] s_cpu1DataToSpm, s_cpu1DataFromSpm;
  wire [17:0] s_cpu1SpmAddress;
  wire [3:0]  s_cpu1SpmByteEnables;
  wire        s_cpu1SpmChipSelect, s_cpu1SpmWriteEnable;
  wire        s_cpu1Enabled, s_cpu1ProfilingActive;
  wire [31:0] s_cpu1JumpAddressIn = 32'd0;
  wire [15:0] s_cpu1CacheConfiguration = 16'd0;
  wire [31:0] s_cpu1DataOutReg;
  wire [2:0]  s_cpu1SelectOutReg;
  wire        s_cpu1WeStatusOut, s_cpu1WeJumpAddress, s_cpu1WeCacheConfig, s_cpu1WeStackTop;
  wire        s_cpu1IcacheRequestBus, s_cpu1DcacheRequestBus;
  wire        s_cpu1IcacheBusAccessGranted, s_cpu1DcacheBusAccessGranted;
  wire        s_cpu1BeginTransaction, s_cpu1EndTransaction, s_cpu1ReadNotWrite;
  wire [31:0] s_cpu1AddressData, s_delayResult, s_i2cCiResult, s_camCiResult;
  wire [3:0]  s_cpu1byteEnables;
  wire        s_cpu1DataValid, s_cpu1PrivateData, s_cpu1PrivateDirty, s_camCiDone;
  wire [7:0]  s_cpu1BurstSize;
  wire        s_spm1Irq;
  wire        s_softBios, s_delayCiDone, s_i2cCiDone;
  reg [31:0]  s_cpu1stackTopReg;
  
  always @(posedge s_systemClock)
    begin
      s_cpu1stackTopReg <= (s_cpuReset == 1'b1) ? 32'hC0001FFC :
                           (s_cpu1WeStackTop == 1'b1 && s_cpu1SelectOutReg == 2'd0) ? s_cpu1DataOutReg :
                           s_cpu1stackTopReg;
    end
    
  assign s_cpu1IrqVector[31:4] = 28'd0;
  assign s_cpu1IrqVector[3] = s_buttonsIrq;
  assign s_cpu1IrqVector[2] = s_dipswitchIrq;
  assign s_cpu1IrqVector[1] = s_spm1Irq;
  assign s_cpu1IrqVector[0] = s_uartIrq;
  assign s_cpu1CiDone = s_hdmiDone | s_swapByteDone | s_flashDone | s_delayCiDone | s_i2cCiDone | s_camCiDone;
  assign s_cpu1Enabled = 1'b1;
  assign s_cpu1ProfilingActive = 1'b1;
  assign s_cpu1CiResult = s_hdmiResult | s_swapByteResult | s_flashResult | s_delayResult | s_i2cCiResult | s_camCiResult; 

  or1300Top #( .processorId(1),
               .NumberOfProcessors(2),
               .nrOfBreakpoints(`ifdef GECKO5Education 8 `else 4 `endif),
               .ReferenceClockFrequencyInHz(50000000) ) cpu1
             ( .clock(s_systemClock),
               .referenceClock(clock50MHz),
               .reset(s_cpuReset),
               .pllReset(s_reset),
               .performSoftReset(s_performSoftReset),
               .softBios(s_softBios),
               .irqVector(s_cpu1IrqVector),
               .customInstructionDataA(s_cpu1CiDataA),
               .customInstructionDataB(s_cpu1CiDataB),
               .customInstructionN(s_cpu1CiN),
               .customInstructionReadRa(s_cpu1CiRa),
               .customInstructionReadRb(s_cpu1CiRb),
               .customInstructionWriteRc(s_cpu1CiRc),
               .customInstructionA(s_cpu1CiA),
               .customInstructionB(s_cpu1CiB),
               .customInstructionC(s_cpu1CiC),
               .customInstructionStart(s_cpu1CiStart),
               .customInstructionClockEnable(s_cpu1CiCke),
               .customInstructionResult(s_cpu1CiResult),
               .customInstructionDone(s_cpu1CiDone),
               .dataToSpm(s_cpu1DataToSpm),
               .dataFromSpm(s_cpu1DataFromSpm),
               .spmAddress(s_cpu1SpmAddress),
               .spmByteEnables(s_cpu1SpmByteEnables),
               .spmChipSelect(s_cpu1SpmChipSelect),
               .spmWriteEnable(s_cpu1SpmWriteEnable),
               .cpuEnabled(s_cpu1Enabled),
               .profilingActive(s_cpu1ProfilingActive),
               .busIdle(s_busIdle),
               .snoopableBurst(s_snoopableBurst),
               .myBarrierValue(s_cpu1BarrierValue),
               .barrierValues(s_barrierValues),
               .jumpAddressIn(s_cpu1JumpAddressIn),
               .stackTopPointer(s_cpu1stackTopReg),
               .cacheConfiguration(s_cpu1CacheConfiguration),
               .memoryDistanceIn(s_memoryDistance),
               .memoryDistanceOut(s_memoryDistance),
               .dataOutReg(s_cpu1DataOutReg),
               .selectOutReg(s_cpu1SelectOutReg),
               .weStatusOut(s_cpu1WeStatusOut),
               .weJumpAddress(s_cpu1WeJumpAddress),
               .weCacheConfig(s_cpu1WeCacheConfig),
               .weStackTop(s_cpu1WeStackTop),
               // here the or1200 external debug interface is defined
               .dbg_stall_i(1'b0),
               .dbg_ewt_i(1'b0),
               .dbg_lss_o(),
               .dbg_is_o(),
               .dbg_wp_o(),
               .dbg_bp_o(),
               .dbg_stb_i(1'b0),
               .dbg_we_i(1'b0),
               .dbg_adr_i(32'd0),
               .dbg_dat_i(32'd0),
               .dbg_dat_o(),
               .dbg_ack_o(),
               .icacheRequestBus(s_cpu1IcacheRequestBus),
               .dcacheRequestBus(s_cpu1DcacheRequestBus),
               .icacheBusAccessGranted(s_cpu1IcacheBusAccessGranted),
               .dcacheBusAccessGranted(s_cpu1DcacheBusAccessGranted),
               .busErrorIn(s_busError),
               .beginTransactionOut(s_cpu1BeginTransaction),
               .beginTransactionIn(s_beginTransaction),
               .addressDataOut(s_cpu1AddressData),
               .addressDataIn(s_addressData),
               .endTransactionOut(s_cpu1EndTransaction),
               .endTransactionIn(s_endTransaction),
               .byteEnablesOut(s_cpu1byteEnables),
               .readNotWriteOut(s_cpu1ReadNotWrite),
               .readNotWriteIn(s_readNotWrite),
               .dataValidOut(s_cpu1DataValid),
               .dataValidIn(s_dataValid),
               .busyIn(s_busy),
               .privateDataOut(s_cpu1PrivateData),
               .privateDataIn(s_privateData),
               .privateDirtyOut(s_cpu1PrivateDirty),
               .privateDirtyIn(s_privateDirty),
               .burstSizeOut(s_cpu1BurstSize),
               .burstSizeIn(s_burstSize) );

  /*
   *
   * Here we instantiate a 4 kbyte Scratch Pad Memory
   *
   */
  wire s_spm1RequestTransaction, s_spm1TransactionGranted;
  wire s_spm1BeginTransaction, s_spm1EndTransaction, s_spm1DataValid;
  wire s_spm1ReadNotWrite, s_spm1BusError, s_spm1Busy;
  wire [3:0]  s_spm1ByteEnables;
  wire [7:0]  s_spm1BurstSize;
  wire [31:0] s_spm1AddressData;
  
  spm4k #(.slaveBaseAddress(32'h50000040),
          .spmBaseAddress(32'hC0000000)) spm1
         (.clock(s_systemClock),
          .reset(s_reset),
          .dataToSpm(s_cpu1DataToSpm),
          .dataFromSpm(s_cpu1DataFromSpm),
          .spmAddress(s_cpu1SpmAddress),
          .spmByteEnables(s_cpu1SpmByteEnables),
          .spmCs(s_cpu1SpmChipSelect),
          .spmWe(s_cpu1SpmWriteEnable),
          .irq(s_spm1Irq),
          .requestTransaction(s_spm1RequestTransaction),
          .transactionGranted(s_spm1TransactionGranted),
          .beginTransactionIn(s_beginTransaction),
          .endTransactionIn(s_endTransaction),
          .readNotWriteIn(s_readNotWrite),
          .dataValidIn(s_dataValid),
          .busErrorIn(s_busError),
          .busyIn(s_busy),
          .addressDataIn(s_addressData),
          .byteEnablesIn(s_byteEnables),
          .burstSizeIn(s_burstSize),
          .beginTransactionOut(s_spm1BeginTransaction),
          .endTransactionOut(s_spm1EndTransaction),
          .dataValidOut(s_spm1DataValid),
          .readNotWriteOut(s_spm1ReadNotWrite),
          .busErrorOut(s_spm1BusError),
          .busyOut(s_spm1Busy),
          .byteEnablesOut(s_spm1ByteEnables),
          .burstSizeOut(s_spm1BurstSize),
          .addressDataOut(s_spm1AddressData));

  /*
   * Here we instantiate the CPU 2
   *
   */
  wire [31:0] s_cpu2IrqVector, s_cpu2CiResult;
  wire [31:0] s_cpu2CiDataA, s_cpu2CiDataB;
  wire [7:0]  s_cpu2CiN;
  wire        s_cpu2CiRa, s_cpu2CiRb, s_cpu2CiRc, s_cpu2CiStart, s_cpu2CiCke, s_cpu2CiDone;
  wire [4:0]  s_cpu2CiA, s_cpu2CiB, s_cpu2CiC;
  wire [31:0] s_cpu2DataToSpm, s_cpu2DataFromSpm;
  wire [17:0] s_cpu2SpmAddress;
  wire [3:0]  s_cpu2SpmByteEnables;
  wire        s_cpu2SpmChipSelect, s_cpu2SpmWriteEnable;
  wire        s_cpu2IcacheRequestBus, s_cpu2DcacheRequestBus;
  wire        s_cpu2IcacheBusAccessGranted, s_cpu2DcacheBusAccessGranted;
  wire        s_cpu2BeginTransaction, s_cpu2EndTransaction, s_cpu2ReadNotWrite;
  wire [31:0] s_cpu2AddressData, s_delayResult1;
  wire [3:0]  s_cpu2byteEnables;
  wire        s_cpu2DataValid, s_cpu2PrivateData, s_cpu2PrivateDirty;
  wire [7:0]  s_cpu2BurstSize;
  wire        s_spm2Irq, s_delayCiDone1;
  
  reg         s_cpu2EnabledReg[2], s_cpu2ProfilingEnabledReg[2];
  reg [15:0]  s_cpu2CacheConfigurationReg[2];
  reg [31:0]  s_cpu2JumpAddressReg[2];
  reg [31:0]  s_cpu2stackTopReg[2];
  
  assign s_cpu2IrqVector[31:1] = 31'd0;
  assign s_cpu2IrqVector[0] = s_spm2Irq;
  assign s_cpu2CiDone = s_hdmiDone1 | s_swapByteDone1 | s_delayCiDone1;
  assign s_cpu2CiResult = s_hdmiResult1 | s_swapByteResult1 | s_delayResult1;
  
  always @(posedge s_systemClock)
    begin
      s_cpu2EnabledReg[1] <= s_cpu2EnabledReg[0];
      s_cpu2EnabledReg[0] <= (s_cpuReset == 1'b1) ? 1'b0 : 
                          (s_cpu1WeStatusOut == 1'b1) ? s_cpu1DataOutReg[1] : s_cpu2EnabledReg[0];
      s_cpu2ProfilingEnabledReg[1] <= s_cpu2ProfilingEnabledReg[0];
      s_cpu2ProfilingEnabledReg[0] <= (s_cpuReset == 1'b1) ? 1'b0 : 
                          (s_cpu1WeStatusOut == 1'b1) ? s_cpu1DataOutReg[9] : s_cpu2ProfilingEnabledReg[0];
      s_cpu2CacheConfigurationReg[1] <= s_cpu2CacheConfigurationReg[0];
      s_cpu2CacheConfigurationReg[0] <= (s_cpuReset == 1'b1) ? 16'd0 :
                                     (s_cpu1WeStatusOut == 1'b1) ? s_cpu1DataOutReg[31:16] : 
                                     (s_cpu1WeCacheConfig == 1'b1 && s_cpu1SelectOutReg == 3'd1) ? s_cpu1DataOutReg[15:0] : s_cpu2CacheConfigurationReg[0];
      s_cpu2JumpAddressReg[1] <= s_cpu2JumpAddressReg[0];
      s_cpu2JumpAddressReg[0] <= (s_cpuReset == 1'b1) ? 32'h00000100 :
                              (s_cpu1WeJumpAddress == 1'b1 && s_cpu1SelectOutReg == 3'd1) ? s_cpu1DataOutReg : s_cpu2JumpAddressReg[0];
      s_cpu2stackTopReg[1] <= s_cpu2stackTopReg[0];
      s_cpu2stackTopReg[0] <= (s_cpuReset == 1'b1) ? 32'hC0001FFC :
                           (s_cpu1WeStackTop == 1'b1 && s_cpu1SelectOutReg == 3'd1) ? s_cpu1DataOutReg :
                           s_cpu2stackTopReg[0];
    end
    
  or1300Top #( .processorId(2),
               .NumberOfProcessors(2),
               .nrOfBreakpoints(`ifdef GECKO5Education 8 `else 4 `endif),
               .ReferenceClockFrequencyInHz(50000000) ) cpu2
             ( .clock(s_systemClock),
               .referenceClock(clock50MHz),
               .reset(s_cpuReset),
               .pllReset(s_reset),
               .performSoftReset(),
               .softBios(),
               .irqVector(s_cpu2IrqVector),
               .customInstructionDataA(s_cpu2CiDataA),
               .customInstructionDataB(s_cpu2CiDataB),
               .customInstructionN(s_cpu2CiN),
               .customInstructionReadRa(s_cpu2CiRa),
               .customInstructionReadRb(s_cpu2CiRb),
               .customInstructionWriteRc(s_cpu2CiRc),
               .customInstructionA(s_cpu2CiA),
               .customInstructionB(s_cpu2CiB),
               .customInstructionC(s_cpu2CiC),
               .customInstructionStart(s_cpu2CiStart),
               .customInstructionClockEnable(s_cpu2CiCke),
               .customInstructionResult(s_cpu2CiResult),
               .customInstructionDone(s_cpu2CiDone),
               .dataToSpm(s_cpu2DataToSpm),
               .dataFromSpm(s_cpu2DataFromSpm),
               .spmAddress(s_cpu2SpmAddress),
               .spmByteEnables(s_cpu2SpmByteEnables),
               .spmChipSelect(s_cpu2SpmChipSelect),
               .spmWriteEnable(s_cpu2SpmWriteEnable),
               .cpuEnabled(s_cpu2EnabledReg[1]),
               .profilingActive(s_cpu2ProfilingEnabledReg[1]),
               .busIdle(s_busIdle),
               .snoopableBurst(s_snoopableBurst),
               .myBarrierValue(s_cpu2BarrierValue),
               .barrierValues(s_barrierValues),
               .jumpAddressIn(s_cpu2JumpAddressReg[1]),
               .stackTopPointer(s_cpu2stackTopReg[1]),
               .cacheConfiguration(s_cpu2CacheConfigurationReg[1]),
               .memoryDistanceIn(s_memoryDistance),
               .memoryDistanceOut(),
               .dataOutReg(),
               .selectOutReg(),
               .weStatusOut(),
               .weJumpAddress(),
               .weCacheConfig(),
               .weStackTop(),
               // here the or1200 external debug interface is defined
               .dbg_stall_i(1'b0),
               .dbg_ewt_i(1'b0),
               .dbg_lss_o(),
               .dbg_is_o(),
               .dbg_wp_o(),
               .dbg_bp_o(),
               .dbg_stb_i(1'b0),
               .dbg_we_i(1'b0),
               .dbg_adr_i(32'd0),
               .dbg_dat_i(32'd0),
               .dbg_dat_o(),
               .dbg_ack_o(),
               .icacheRequestBus(s_cpu2IcacheRequestBus),
               .dcacheRequestBus(s_cpu2DcacheRequestBus),
               .icacheBusAccessGranted(s_cpu2IcacheBusAccessGranted),
               .dcacheBusAccessGranted(s_cpu2DcacheBusAccessGranted),
               .busErrorIn(s_busError),
               .beginTransactionOut(s_cpu2BeginTransaction),
               .beginTransactionIn(s_beginTransaction),
               .addressDataOut(s_cpu2AddressData),
               .addressDataIn(s_addressData),
               .endTransactionOut(s_cpu2EndTransaction),
               .endTransactionIn(s_endTransaction),
               .byteEnablesOut(s_cpu2byteEnables),
               .readNotWriteOut(s_cpu2ReadNotWrite),
               .readNotWriteIn(s_readNotWrite),
               .dataValidOut(s_cpu2DataValid),
               .dataValidIn(s_dataValid),
               .busyIn(s_busy),
               .privateDataOut(s_cpu2PrivateData),
               .privateDataIn(s_privateData),
               .privateDirtyOut(s_cpu2PrivateDirty),
               .privateDirtyIn(s_privateDirty),
               .burstSizeOut(s_cpu2BurstSize),
               .burstSizeIn(s_burstSize) );

  /*
   *
   * Here we instantiate a 4 kbyte Scratch Pad Memory
   *
   */
  wire s_spm2RequestTransaction, s_spm2TransactionGranted;
  wire s_spm2BeginTransaction, s_spm2EndTransaction, s_spm2DataValid;
  wire s_spm2ReadNotWrite, s_spm2BusError, s_spm2Busy;
  wire [3:0]  s_spm2ByteEnables;
  wire [7:0]  s_spm2BurstSize;
  wire [31:0] s_spm2AddressData;
  
  spm4k #(.slaveBaseAddress(32'h50000100),
          .spmBaseAddress(32'hC0000000)) spm2
         (.clock(s_systemClock),
          .reset(s_reset),
          .dataToSpm(s_cpu2DataToSpm),
          .dataFromSpm(s_cpu2DataFromSpm),
          .spmAddress(s_cpu2SpmAddress),
          .spmByteEnables(s_cpu2SpmByteEnables),
          .spmCs(s_cpu2SpmChipSelect),
          .spmWe(s_cpu2SpmWriteEnable),
          .irq(s_spm2Irq),
          .requestTransaction(s_spm2RequestTransaction),
          .transactionGranted(s_spm2TransactionGranted),
          .beginTransactionIn(s_beginTransaction),
          .endTransactionIn(s_endTransaction),
          .readNotWriteIn(s_readNotWrite),
          .dataValidIn(s_dataValid),
          .busErrorIn(s_busError),
          .busyIn(s_busy),
          .addressDataIn(s_addressData),
          .byteEnablesIn(s_byteEnables),
          .burstSizeIn(s_burstSize),
          .beginTransactionOut(s_spm2BeginTransaction),
          .endTransactionOut(s_spm2EndTransaction),
          .dataValidOut(s_spm2DataValid),
          .readNotWriteOut(s_spm2ReadNotWrite),
          .busErrorOut(s_spm2BusError),
          .busyOut(s_spm2Busy),
          .byteEnablesOut(s_spm2ByteEnables),
          .burstSizeOut(s_spm2BurstSize),
          .addressDataOut(s_spm2AddressData));

  /*
   *
   * Here we define a custom instruction that swaps bytes
   *
   */
  swapByte #(.customIntructionNr(8'd1)) swap1
            (.ciN(s_cpu1CiN),
             .ciDataA(s_cpu1CiDataA),
             .ciDataB(s_cpu1CiDataB),
             .ciStart(s_cpu1CiStart),
             .ciCke(s_cpu1CiCke),
             .ciDone(s_swapByteDone),
             .ciResult(s_swapByteResult));

  swapByte #(.customIntructionNr(8'd1)) swap2
            (.ciN(s_cpu2CiN),
             .ciDataA(s_cpu2CiDataA),
             .ciDataB(s_cpu2CiDataB),
             .ciStart(s_cpu2CiStart),
             .ciCke(s_cpu2CiCke),
             .ciDone(s_swapByteDone1),
             .ciResult(s_swapByteResult1));

  /*
   *
   * Here we define a custom instruction that implements a simple I2C interface
   *
   */
  i2cCustomInstr #(.CLOCK_FREQUENCY(59400000),
                   .I2C_FREQUENCY(400000),
                   .CUSTOM_ID(8'd5)) i2cm
                  (.clock(s_systemClock),
                   .reset(s_cpuReset),
                   .ciStart(s_cpu1CiStart),
                   .ciCke(s_cpu1CiCke),
                   .ciN(s_cpu1CiN),
                   .ciOppA(s_cpu1CiDataA),
                   .ciDone(s_i2cCiDone),
                   .result(s_i2cCiResult),
                   .SDA(SDA),
                   .SCL(SCL));

  /*
   *
   * Here we define a custom instruction that implements a blocking micro-second(s) delay element
   *
   */
  delayIse #(.referenceClockFrequencyInHz(50000000),
             .customInstructionId(8'd6) ) delayMicro
            (.clock(s_systemClock),
             .referenceClock(clock50MHz),
             .reset(s_cpuReset),
             .ciStart(s_cpu1CiStart),
             .ciCke(s_cpu1CiCke),
             .ciN(s_cpu1CiN),
             .ciValueA(s_cpu1CiDataA),
             .ciValueB(s_cpu1CiDataB),
             .ciDone(s_delayCiDone),
             .ciResult(s_delayResult));

  delayIse #(.referenceClockFrequencyInHz(50000000),
             .customInstructionId(8'd6) ) delayMicro1
            (.clock(s_systemClock),
             .referenceClock(clock50MHz),
             .reset(s_cpuReset),
             .ciStart(s_cpu2CiStart),
             .ciCke(s_cpu2CiCke),
             .ciN(s_cpu2CiN),
             .ciValueA(s_cpu2CiDataA),
             .ciValueB(s_cpu2CiDataB),
             .ciDone(s_delayCiDone1),
             .ciResult(s_delayResult1));

  /*
   *
   * Here we define the camera interface
   *
   */
  wire s_camReqBus, s_camAckBus, s_camBeginTransaction, s_camEndTransaction;
  wire s_camDataValid;
  wire [31:0] s_camAddressData;
  wire [3:0] s_camByteEnables;
  wire [7:0] s_camBurstSize;
  
  camera #(.customInstructionId(8'd7),
           .clockFrequencyInHz(59400000)) camIf
          (.clock(s_systemClock),
           .pclk(camPclk),
           .reset(s_cpuReset),
           .hsync(camHsync),
           .vsync(camVsync),
           .ciStart(s_cpu1CiStart),
           .ciCke(s_cpu1CiCke),
           .ciN(s_cpu1CiN),
           .camData(camData),
           .ciValueA(s_cpu1CiDataA),
           .ciValueB(s_cpu1CiDataB),
           .ciResult(s_camCiResult),
           .ciDone(s_camCiDone),
           .requestBus(s_camReqBus),
           .busGrant(s_camAckBus),
           .beginTransactionOut(s_camBeginTransaction),
           .addressDataOut(s_camAddressData),
           .endTransactionOut(s_camEndTransaction),
           .byteEnablesOut(s_camByteEnables),
           .dataValidOut(s_camDataValid),
           .burstSizeOut(s_camBurstSize),
           .busyIn(s_busy),
           .busErrorIn(s_busError));

  /*
   *
   * Here the hdmi controller is defined
   *
   */
  wire        s_hdmiRequestBus, s_hdmiBusgranted, s_hdmiBeginTransaction;
  wire        s_hdmiEndTransaction, s_hdmiDataValid, s_hdmiReadNotWrite;
  wire [3:0]  s_hdmiByteEnables;
  wire [7:0]  s_hdmiBurstSize;
  wire [31:0] s_hdmiAddressData;

  screens #(.baseAddress(32'h50000020),
            .pixelClockFrequency(27'd74250000),
            .cursorBlinkFrequency(27'd1)) hdmi 
           (.pixelClockIn(s_pixelClock),
            .clock(s_systemClock),
            .reset(s_reset),
            .testPicture(1'b0),
            .nrOfScreens(2'd2),
            .ci1N(s_cpu1CiN),
            .ci1DataA(s_cpu1CiDataA),
            .ci1DataB(s_cpu1CiDataB),
            .ci1Start(s_cpu1CiStart),
            .ci1Cke(s_cpu1CiCke),
            .ci1Done(s_hdmiDone),
            .ci1Result(s_hdmiResult),
            .ci2N(s_cpu2CiN),
            .ci2DataA(s_cpu2CiDataA),
            .ci2DataB(s_cpu2CiDataB),
            .ci2Start(s_cpu2CiStart),
            .ci2Cke(s_cpu2CiCke),
            .ci2Done(s_hdmiDone1),
            .ci2Result(s_hdmiResult1),
            .ci3N(8'd0),
            .ci3DataA(32'd0),
            .ci3DataB(32'd0),
            .ci3Start(1'b0),
            .ci3Cke(1'b0),
            .ci3Done(),
            .ci3Result(),
            .requestTransaction(s_hdmiRequestBus),
            .transactionGranted(s_hdmiBusgranted),
            .beginTransactionIn(s_beginTransaction),
            .endTransactionIn(s_endTransaction),
            .readNotWriteIn(s_readNotWrite),
            .dataValidIn(s_dataValid),
            .busErrorIn(s_busError),
            .addressDataIn(s_addressData),
            .byteEnablesIn(s_byteEnables),
            .burstSizeIn(s_burstSize),
            .beginTransactionOut(s_hdmiBeginTransaction),
            .endTransactionOut(s_hdmiEndTransaction),
            .dataValidOut(s_hdmiDataValid),
            .readNotWriteOut(s_hdmiReadNotWrite),
            .byteEnablesOut(s_hdmiByteEnables),
            .burstSizeOut(s_hdmiBurstSize),
            .addressDataOut(s_hdmiAddressData),
            .pixelClkX2(s_pixelClkX2),

`ifdef GECKO5Education
            .hdmiRed(hdmiRed),
            .hdmiGreen(hdmiGreen),
            .hdmiBlue(hdmiBlue),
`else
            .red(hdmiRed),
            .green(hdmiGreen),
            .blue(hdmiBlue),
`endif
            .pixelClock(pixelClock),
            .horizontalSync(horizontalSync),
            .verticalSync(verticalSync),
            .activePixel(activePixel)
            );

  /*
   *
   * Here the spi-flash controller is defined
   *
   */
  wire [31:0] s_flashAddressData;
  wire s_flashEndTransaction, s_flashDataValid, s_flashBusError;
  spiBus #( .baseAddress(32'h04000000),
            .customIntructionNr(8'd2)) flash
          ( .clock(s_systemClock),
            .reset(s_reset),
            .spiScl(spiScl),
            .spiNCs(spiNCs),
            .spiSiIo0(spiSiIo0),
            .spiSoIo1(spiSoIo1),
            .spiIo2(spiIo2),
            .spiIo3(spiIo3),
            .ciN(s_cpu1CiN),
            .ciDataA(s_cpu1CiDataA),
            .ciDataB(s_cpu1CiDataB),
            .ciStart(s_cpu1CiStart),
            .ciCke(s_cpu1CiCke),
            .ciDone(s_flashDone),
            .ciResult(s_flashResult),
            .beginTransactionIn(s_beginTransaction),
            .endTransactionIn(s_endTransaction),
            .readNotWriteIn(s_readNotWrite),
            .busErrorIn(s_busError),
            .addressDataIn(s_addressData),
            .burstSizeIn(s_burstSize),
            .byteEnablesIn(s_byteEnables),
            .addressDataOut(s_flashAddressData),
            .endTransactionOut(s_flashEndTransaction),
            .dataValidOut(s_flashDataValid),
            .busErrorOut(s_flashBusError) );

  /*
   *
   * Here we define the bios
   *
   */
  wire [31:0] s_biosAddressData;
  wire        s_biosBusError, s_biosDataValid, s_biosEndTransaction;
  bios start (.clock(s_systemClock),
              .reset(s_reset),
              .softRomActive(s_softBios),
              .addressDataIn(s_addressData),
              .beginTransactionIn(s_beginTransaction),
              .endTransactionIn(s_endTransaction),
              .readNotWriteIn(s_readNotWrite),
              .busErrorIn(s_busError),
              .dataValidIn(s_dataValid),
              .byteEnablesIn(s_byteEnables),
              .burstSizeIn(s_burstSize),
              .addressDataOut(s_biosAddressData),
              .busErrorOut(s_biosBusError),
              .dataValidOut(s_biosDataValid),
              .endTransactionOut(s_biosEndTransaction));

  /*
   *
   * Here we define the bus arbiter
   *
   */
 wire [31:0] s_busRequests, s_busGrants;
 wire        s_arbBusError, s_arbEndTransaction;
 
 assign s_busRequests[31] = s_hdmiRequestBus;
 assign s_busRequests[30] = s_camReqBus;
 assign s_busRequests[29] = s_cpu1IcacheRequestBus;
 assign s_busRequests[28] = s_cpu1DcacheRequestBus;
 assign s_busRequests[27] = s_cpu2IcacheRequestBus;
 assign s_busRequests[26] = s_cpu2DcacheRequestBus;
 assign s_busRequests[25] = s_spm1RequestTransaction;
 assign s_busRequests[24] = s_spm2RequestTransaction;
 assign s_busRequests[23:0] = 24'd0;
 
 assign s_hdmiBusgranted             = s_busGrants[31];
 assign s_camAckBus                  = s_busGrants[30];
 assign s_cpu1IcacheBusAccessGranted = s_busGrants[29];
 assign s_cpu1DcacheBusAccessGranted = s_busGrants[28];
 assign s_cpu2IcacheBusAccessGranted = s_busGrants[27];
 assign s_cpu2DcacheBusAccessGranted = s_busGrants[26];
 assign s_spm1TransactionGranted     = s_busGrants[25];
 assign s_spm2TransactionGranted     = s_busGrants[24];

 busArbiter arbiter ( .clock(s_systemClock),
                      .reset(s_reset),
                      .busRequests(s_busRequests),
                      .busGrants(s_busGrants),
                      .busErrorOut(s_arbBusError),
                      .endTransactionOut(s_arbEndTransaction),
                      .busIdle(s_busIdle),
                      .snoopableBurst(s_snoopableBurst),
                      .beginTransactionIn(s_beginTransaction),
                      .endTransactionIn(s_endTransaction),
                      .dataValidIn(s_dataValid),
                      .addressDataIn(s_addressData[31:30]),
                      .burstSizeIn(s_burstSize));
 
  /*
   *
   * Here we define the bus architecture
   *
   */
 assign s_busError         = s_arbBusError | s_biosBusError | s_uartBusError | s_sdramBusError | s_spm1BusError | s_spm2BusError | s_7SegBusError |
                             s_switchesBusError | s_ledsBusError;
 assign s_beginTransaction = s_cpu1BeginTransaction | s_cpu2BeginTransaction | s_hdmiBeginTransaction | s_spm1BeginTransaction | s_spm2BeginTransaction | s_camBeginTransaction;
 assign s_endTransaction   = s_cpu1EndTransaction | s_cpu2EndTransaction | s_arbEndTransaction | s_biosEndTransaction | s_uartEndTransaction |
                             s_sdramEndTransaction | s_hdmiEndTransaction | s_spm1EndTransaction | s_spm2EndTransaction | s_7SegEndTransaction |
                             s_switchesEndTransaction | s_ledsEndTransaction | s_flashEndTransaction | s_camEndTransaction | s_ssramEndTransaction;
 assign s_addressData      = s_cpu1AddressData | s_cpu2AddressData | s_biosAddressData | s_uartAddressData | s_sdramAddressData | s_hdmiAddressData |
                             s_spm1AddressData | s_spm2AddressData | s_7SegAddressData | s_switchesAddressData | s_ledsAddressData | s_flashAddressData |
                             s_camAddressData | s_ssramAddressData;
 assign s_byteEnables      = s_cpu1byteEnables | s_cpu2byteEnables | s_hdmiByteEnables | s_spm1ByteEnables | s_spm2ByteEnables | s_camByteEnables;
 assign s_readNotWrite     = s_cpu1ReadNotWrite | s_cpu2ReadNotWrite | s_hdmiReadNotWrite | s_spm1ReadNotWrite | s_spm2ReadNotWrite;
 assign s_dataValid        = s_cpu1DataValid | s_cpu2DataValid | s_biosDataValid | s_uartDataValid | s_sdramDataValid | s_hdmiDataValid | s_spm1DataValid | s_spm2DataValid |
                             s_7SegDataValid | s_switchesDataValid | s_ledsDataValid | s_flashDataValid | s_camDataValid | s_ssramDataValid;
 assign s_busy             = s_sdramBusy | s_spm1Busy | s_spm2Busy;
 assign s_privateData      = s_cpu1PrivateData | s_cpu2PrivateData;
 assign s_privateDirty     = s_cpu1PrivateDirty | s_cpu2PrivateDirty;
 assign s_burstSize        = s_cpu1BurstSize | s_cpu2BurstSize | s_hdmiBurstSize | s_spm1BurstSize | s_spm2BurstSize | s_camBurstSize;
 
endmodule
