/*
 *
 * This module used the definition parameter "CIDEnabled"
 * in case this parameter is defined the register file consists of 32 set's of 32 registers,
 * otherwise (default) there is only 1 set of 32 Registers and the cid is "0000".
 *
 */
 `ifdef GECKO5Education
 `define CIDEnabled
 `endif

module registerFile #( parameter [2:0] processorId = 1,
                      parameter [2:0] NumberOfProcessors = 1,
                      parameter nrOfBreakpoints = 8,
                      parameter ReferenceClockFrequencyInHz = 12000000 )
                    ( input wire         clock,
                                         referenceClock,
                                         reset,
                                         pllReset,
                                         stall,
                      output wire        performSoftReset,

                      // here the interface to the profiling and debug module is defined
                      input wire [31:0]  profilingData,
                                         debugData,
                      
                      // here the d-cache interface is defined
                      input wire         dcacheWe,
                      input wire [8:0]   dcacheTarget,
                      input wire [31:0]  dcacheDataIn,
                      output wire        dcacheEnabled,
                                         dcacheFlush,
                                         dcacheWriteBackEnabled,
                                         dcacheSnarfingEnabled,
                                         dcacheMesiEnabled,
                                         dcacheCoherenceEnabled,
                      output wire [1:0]  dcacheSize,
                                         dcacheReplacementPolicy,
                                         dcacheNumberOfWays,

                      // here the i-cache interface is defined
                      output wire        icacheEnabled,
                                         icacheFlush,
                      output wire [1:0]  icacheSize,
                                         icacheReplacementPolicy,
                                         icacheNumberOfWays,
                      input wire [31:0]  instructionAddress,
                      
                      // here the write back interface is defined
                      input wire [4:0]   writeAddress,
                      input wire [31:0]  writeData,
                      input wire         writeEnable,
                                         writeSpr,
                      input wire [15:0]  writeSprIndex,
                      
                      // here the interface to the execution unit is defined
                      output wire        exeFlag,
                                         exeCarry,
                                         exeOverflow,
                      input wire         exeWeFlag,
                                         exeWeCarry,
                                         exeWeOverflow,
                                         exeFlagIn,
                                         exeCarryIn,
                                         exeOverflowIn,
                      input wire [15:0]  exeSprIndex,
                      input wire [31:0]  multMacLo,
                                         multMacHi,
                      output reg [31:0]  exeSprData,
                      
                      // here the interface to the instruction decoder is defined
                      input wire [31:0]  ebuIr,
                      
                      // here the interface to the exception branch unit is defined
                      input wire         exceptionTaken,
                                         exceptionFinished,
                      input wire [13:0]  exceptionReason,
                      input wire [31:0]  eearNext,
                                         epcrNext,
                      output wire [27:0] BusErrorVector,
                                         TickTimerVector,
                                         AllignmentVector,
                                         RangeVector,
                                         IllegalInstructionVector,
                                         SystemCallVector,
                                         TrapVector,
                                         BreakPointVector,
                                         InterruptVector,
                      
                      // here the instruction decoder interface is defined
                      output wire [3:0]  cid,
                      input wire         isDelaySlotIsn,
                      input wire [8:0]   lookupOperantAAddr,
                                         lookupOperantBAddr,
                      output wire [31:0] operantA,
                                         operantB,
                      
                      // Here the irq signals are defined
                      output wire        tickTimerIrq,
                      output wire        irq,
                      input wire [31:0]  irqVector,
                      
                      // here the special registers are exported
                      output wire [31:0] superVisionRegister,
                                         effectiveAddressRegister,
                                         exceptionPcRegister,
                      output wire        softBios,

                      // here the multi-processor interface is defined
                      input wire         cpuEnabled, // was do_jump
                      output wire        myBarrierValue,
                      input wire [7:0]   barrierValues,
                      input wire [31:0]  jumpAddressIn,
                                         stackTopPointer,
                      input wire [15:0]  cacheConfiguration,
                      input wire [5:0]   memoryDistanceIn,
                      output wire [5:0]  memoryDistanceOut,
                      output reg [31:0]  dataOutReg, // replaces status_out and jump_address_out
                      output reg [2:0]   selectOutReg, // replaces jump_address_index
                      output wire        weStatusOut,
                                         weJumpAddress,
                                         weCacheConfig,
                                         weStackTop); 

  reg [31:0] s_superVisionReg;
  wire [31:0] s_esr;
  wire [3:0] s_cid = `ifdef CIDEnabled s_superVisionReg[31:28] `else 4'd0 `endif;
  wire [8:0] s_writeAddress = (dcacheWe == 1'b1) ? dcacheTarget :
                              (writeSpr == 1'b1) ? writeSprIndex[8:0] : {s_cid,writeAddress};
  wire [31:0] s_writeData = (dcacheWe == 1'b1) ? dcacheDataIn : writeData;
  wire s_writeEnable = ((writeEnable == 1'b1 && stall == 1'b0) || dcacheWe == 1'b1 ||
                        (writeSpr == 1'b1 && s_superVisionReg[0] == 1'b1 &&
                         writeSprIndex[15:9] == 7'd1)) ? 1'b1 : 1'b0;
  
  assign cid                 = s_cid;
  assign exeFlag             = s_superVisionReg[9];
  assign exeCarry            = s_superVisionReg[10];
  assign exeOverflow         = s_superVisionReg[11];
  assign superVisionRegister = s_superVisionReg;

  /*
   *
   * Here the supervision register is defined
   *
   */
  wire [31:0] s_superVisionNext;
  wire s_supervisionMode = s_superVisionReg[0];
  wire s_weSuper = (writeSprIndex == 16'h0011 && s_supervisionMode == 1'b1) ? writeSpr : 1'b0;
                            
  assign s_superVisionNext[27:17] = 11'd0;
  assign s_superVisionNext[15]    = 1'd1;
  assign s_superVisionNext[7]     = 1'd0;
  assign s_superVisionNext[2:0]   = (reset == 1'b1 || (stall == 1'b0 && exceptionTaken == 1'b1)) ? 3'b001 :
                                    (stall == 1'b0 && exceptionFinished == 1'b1) ? s_esr[2:0] :
                                    (stall == 1'b0 && s_weSuper == 1'b1) ? writeData[2:0] : s_superVisionReg[2:0];
  assign s_superVisionNext[6:5]   = (reset == 1'b1 || (stall == 1'b0 && exceptionTaken == 1'b1)) ? 2'd0 :
                                    (stall == 1'b0 && exceptionFinished == 1'b1) ? s_esr[6:5] :
                                    (stall == 1'b0 && s_weSuper == 1'b1) ? writeData[6:5] : s_superVisionReg[6:5];
  assign s_superVisionNext[16]    = (reset == 1'b1) ? 1'b0 :
                                    (stall == 1'b0 && exceptionFinished == 1'b1) ? s_esr[16] :
                                    (stall == 1'b0 && s_weSuper == 1'b1) ? writeData[16] : s_superVisionReg[16];
  assign s_superVisionNext[14]    = (reset == 1'b1) ? 1'b1 :
                                    (stall == 1'b0 && exceptionFinished == 1'b1) ? s_esr[14] :
                                    (stall == 1'b0 && s_weSuper == 1'b1) ? writeData[14] : s_superVisionReg[14];
  assign s_superVisionNext[12]    = (reset == 1'b1) ? 1'b0 :
                                    (stall == 1'b0 && exceptionFinished == 1'b1) ? s_esr[12] :
                                    (stall == 1'b0 && s_weSuper == 1'b1) ? writeData[12] : s_superVisionReg[12];
`ifdef CIDEnabled
  assign s_superVisionNext[8]     = (reset == 1'b1) ? 1'b0 :
                                    (stall == 1'b0 && exceptionFinished == 1'b1) ? s_esr[8] :
                                    (stall == 1'b0 && s_weSuper == 1'b1) ? writeData[8] : s_superVisionReg[8];
`else
  assign s_superVisionNext[8]     = 1'b0;
`endif
  assign s_superVisionNext[4]     = (reset == 1'b1) ? 1'b0 :
                                    (stall == 1'b0 && exceptionFinished == 1'b1) ? s_esr[4] :
                                    (stall == 1'b0 && s_weSuper == 1'b1) ? writeData[4] : s_superVisionReg[4];
  assign s_superVisionNext[3]     = (reset == 1'b1) ? 1'b0 :
                                    (stall == 1'b0 && exceptionFinished == 1'b1) ? s_esr[3] :
                                    (stall == 1'b0 && s_weSuper == 1'b1) ? writeData[3] : s_superVisionReg[3];
  assign s_superVisionNext[13]    = (reset == 1'b1) ? 1'b0 :
                                    (stall == 1'b0 && exceptionTaken == 1'b1) ? isDelaySlotIsn :
                                    (stall == 1'b0 && exceptionFinished == 1'b1) ? s_esr[13] : s_superVisionReg[13];
  assign s_superVisionNext[9]     = (reset == 1'b1) ? 1'b0 : (stall == 1'b1) ? s_superVisionReg[9] :
                                    (exeWeFlag == 1'b1) ? exeFlagIn : 
                                    (exceptionFinished == 1'b1) ? s_esr[9] :
                                    (s_weSuper == 1'b1) ? writeData[9] : s_superVisionReg[9];
  assign s_superVisionNext[10]    = (reset == 1'b1) ? 1'b0 : (stall == 1'b1) ? s_superVisionReg[10] :
                                    (exeWeCarry == 1'b1) ? exeCarryIn : 
                                    (exceptionFinished == 1'b1) ? s_esr[10] :
                                    (s_weSuper == 1'b1) ? writeData[10] : s_superVisionReg[10];
  assign s_superVisionNext[11]    = (reset == 1'b1) ? 1'b0 : (stall == 1'b1) ? s_superVisionReg[11] :
                                    (exeWeOverflow == 1'b1) ? exeOverflowIn : 
                                    (exceptionFinished == 1'b1) ? s_esr[11] :
                                    (s_weSuper == 1'b1) ? writeData[11] : s_superVisionReg[11];
  
`ifdef CIDEnabled  
  wire [3:0] s_cidNext    = cid + 4'd1;
  wire [3:0] s_cidPrev    = cid - 4'd1;
  wire [3:0] s_cidAddress = (exceptionTaken == 1'b0 && writeSpr == 1'b1) ? writeSprIndex[3:0] :
                            (exceptionTaken == 1'b0 && s_superVisionReg[8] == 1'b1) ? s_cidPrev : s_superVisionReg[31:28];
  assign s_superVisionNext[31:28] = (reset == 1'b1) ? 4'd0 : (stall == 1'b1) ? s_superVisionReg[31:28] :
                                    (exceptionTaken == 1'b1 && s_superVisionReg[8] == 1'b1) ? s_cidNext :
                                    (exceptionFinished == 1'b1 && s_superVisionReg[8] == 1'b1) ? s_cidPrev :
                                    (s_weSuper == 1'b1) ? writeData[31:28] : s_superVisionReg[31:28];
`else
  assign s_superVisionNext[31:28] = 4'd0;
`endif

  always @(posedge clock) s_superVisionReg <= s_superVisionNext;

  /*
   *
   * Here the esr is defined
   *
   */
  wire s_weEsr = (exceptionTaken == 1'b1 || (writeSpr == 1'b1 && s_supervisionMode == 1'b1 && writeSprIndex[15:4] == 12'h004)) ? ~stall : 1'b0;
  wire [31:0] s_esrNext = (exceptionTaken == 1'b1) ? s_superVisionReg : writeData;

`ifdef CIDEnabled  
  wire [31:0] s_esrSpr;
  sram16x32DpAr esrRam ( .writeClock(clock),
                         .writeEnable(s_weEsr),
                         .writeAddress(s_cidAddress),
                         .readAddress(exeSprIndex[3:0]),
                         .writeData(s_esrNext),
                         .dataWritePort(s_esr),
                         .dataReadPort(s_esrSpr) );
`else
  reg [31:0] s_esrSpr;
  always @(posedge clock) s_esrSpr <= (reset == 1'b1) ? 32'd0 : (s_weEsr == 1'b1) ? s_esrNext : s_esrSpr;
  assign s_esr = s_esrSpr;
`endif
  
  /*
   *
   * Here the eaa is defined
   *
   */
  wire s_weEear = (exceptionTaken == 1'b1 || (writeSpr == 1'b1 && s_supervisionMode == 1'b1 && writeSprIndex[15:4] == 12'h003)) ? ~stall : 1'b0;
  wire [31:0] s_eearNext = (exceptionTaken == 1'b1) ? eearNext : writeData;

`ifdef CIDEnabled  
  wire [31:0] s_eearSpr;
  sram16x32DpAr eearRam ( .writeClock(clock),
                          .writeEnable(s_weEear),
                          .writeAddress(s_cidAddress),
                          .readAddress(exeSprIndex[3:0]),
                          .writeData(s_eearNext),
                          .dataWritePort(effectiveAddressRegister),
                          .dataReadPort(s_eearSpr) );
`else
  reg [31:0] s_eearSpr;
  always @(posedge clock) s_eearSpr <= (reset == 1'b1) ? 32'd0 : (s_weEear == 1'b1) ? s_eearNext : s_eearSpr;
  assign effectiveAddressRegister = s_eearSpr;
`endif
  
  /*
   *
   * Here the epc is defined
   *
   */
  wire s_weEpcr = (exceptionTaken == 1'b1 || (writeSpr == 1'b1 && s_supervisionMode == 1'b1 && writeSprIndex[15:4] == 12'h002)) ? ~stall : 1'b0;
  wire [31:0] s_epcrNext = (exceptionTaken == 1'b1) ? epcrNext : writeData;

`ifdef CIDEnabled  
  wire [31:0] s_epcrSpr;
  sram16x32DpAr epcrRam ( .writeClock(clock),
                          .writeEnable(s_weEpcr),
                          .writeAddress(s_cidAddress),
                          .readAddress(exeSprIndex[3:0]),
                          .writeData(s_epcrNext),
                          .dataWritePort(exceptionPcRegister),
                          .dataReadPort(s_epcrSpr) );
`else
  reg [31:0] s_epcrSpr;
  always @(posedge clock) s_epcrSpr <= (reset == 1'b1) ? 32'd0 : (s_weEpcr == 1'b1) ? s_epcrNext : s_epcrSpr;
  assign exceptionPcRegister = s_epcrSpr;
`endif
  
  /*
   *
   * Here the i-cache control is defined
   *
   */
  reg [1:0] s_iReplacementPolicyReg, s_iNumberOfWaysReg, s_iSizeReg;
  reg s_flushICacheReg;
  reg [31:0] s_icacheConfigurationRegister;
  wire [1:0] s_iReplacementPolicyNext = (reset == 1'b1) ? 2'b10 :
                                        (writeSpr == 1'b1 && writeSprIndex == 16'h0006 && writeData[29] == 1'b0) ? writeData[17:16] : s_iReplacementPolicyReg;
  wire [1:0] s_iNumberOfWaysNext = (reset == 1'b1) ? 2'b01 :
                                   (writeSpr == 1'b1 && writeSprIndex == 16'h0006 && writeData[29] == 1'b0 && s_superVisionReg[4] == 1'b0) ? writeData[1:0] : s_iNumberOfWaysReg;
  wire [1:0] s_nextIsize = writeData[31:30];
  wire [1:0] s_iSizeNext = (reset == 1'b1) ? 2'b10 :
                           (writeSpr == 1'b1 && writeSprIndex == 16'h0006 && writeData[29] == 1'b0 && s_superVisionReg[4] == 1'b0) ? s_nextIsize : s_iSizeReg;
  wire s_flushICacheNext = (writeSpr == 1'b1 && writeSprIndex == 16'h0006 && stall == 1'b0) ? writeData[29] : 1'b0;
  
  assign icacheReplacementPolicy = s_iReplacementPolicyReg;
  assign icacheEnabled           = s_superVisionReg[4];
  assign icacheFlush             = s_flushICacheReg;
  assign icacheSize              = s_iSizeReg;
  assign icacheNumberOfWays      = s_iNumberOfWaysReg;

  always @(posedge clock)
    begin
      s_iReplacementPolicyReg <= s_iReplacementPolicyNext;
      s_iNumberOfWaysReg      <= s_iNumberOfWaysNext;
      s_iSizeReg              <= s_iSizeNext;
      s_flushICacheReg        <= s_flushICacheNext;
    end
  
  always @*
    begin
      s_icacheConfigurationRegister[31:30] <= s_iSizeReg;
      s_icacheConfigurationRegister[29:20] <= 10'd0;
      s_icacheConfigurationRegister[19]    <= s_superVisionReg[4];
      s_icacheConfigurationRegister[18]    <= 1'b0;
      s_icacheConfigurationRegister[17:16] <= s_iReplacementPolicyReg;
      s_icacheConfigurationRegister[15:7]  <= 9'd1;
      s_icacheConfigurationRegister[2]     <= 1'b0;
      s_icacheConfigurationRegister[1:0]   <= s_iNumberOfWaysReg;
      case (s_iSizeReg)
        2'b00   : case (s_iNumberOfWaysReg)
                    2'b01   : s_icacheConfigurationRegister[6:3] <= 4'h5;
                    2'b10   : s_icacheConfigurationRegister[6:3] <= 4'h4;
                    default : s_icacheConfigurationRegister[6:3] <= 4'h6;
                  endcase
        2'b01   : case (s_iNumberOfWaysReg)
                    2'b01   : s_icacheConfigurationRegister[6:3] <= 4'h6;
                    2'b10   : s_icacheConfigurationRegister[6:3] <= 4'h5;
                    default : s_icacheConfigurationRegister[6:3] <= 4'h7;
                  endcase
        2'b10   : case (s_iNumberOfWaysReg)
                    2'b01   : s_icacheConfigurationRegister[6:3] <= 4'h7;
                    2'b10   : s_icacheConfigurationRegister[6:3] <= 4'h6;
                    default : s_icacheConfigurationRegister[6:3] <= 4'h8;
                  endcase
        default : case (s_iNumberOfWaysReg)
                    2'b01   : s_icacheConfigurationRegister[6:3] <= 4'h8;
                    2'b10   : s_icacheConfigurationRegister[6:3] <= 4'h7;
                    default : s_icacheConfigurationRegister[6:3] <= 4'h9;
                  endcase
      endcase
    end
  
  /*
   *
   * Here the d-cache control is defined
   *
   */
  reg [1:0] s_dReplacementPolicyReg, s_dNumberOfWaysReg, s_dSizeReg;
  reg s_dWriteBackReg, s_dCoherenceEnabledReg, s_dMesiEnabledReg, s_dSnarfingEnabledReg, s_flushDCacheReg;
  reg [31:0] s_dcacheConfigurationRegister;
  wire [1:0] s_dReplacementPolicyNext = (reset == 1'b1) ? 2'b10 :
                                        (writeSpr == 1'b1 && writeSprIndex == 16'h0005 && writeData[29] == 1'b0) ? writeData[17:16] : s_dReplacementPolicyReg;
  wire s_dWriteBackNext = (reset == 1'b1) ? 1'b1 :
                          (writeSpr == 1'b1 && writeSprIndex == 16'h0005 && writeData[29] == 1'b0) ? writeData[8] : s_dWriteBackReg;
  wire s_dSnarfingEnabledNext = (reset == 1'b1) ? 1'b1 :
                                (writeSpr == 1'b1 && writeSprIndex == 16'h0005 && writeData[29] == 1'b0) ? writeData[21] : s_dSnarfingEnabledReg;
  wire s_dMesiEnabledNext = (reset == 1'b1) ? 1'b1 :
                            (writeSpr == 1'b1 && writeSprIndex == 16'h0005 && writeData[29] == 1'b0) ? writeData[20] : s_dMesiEnabledReg;
  wire [1:0] s_dNumberOfWaysNext = (reset == 1'b1) ? 2'b10 :
                                   (writeSpr == 1'b1 && writeSprIndex == 16'h0005 && writeData[29] == 1'b0 && s_superVisionReg[3] == 1'b0) ? writeData[1:0] : s_dNumberOfWaysReg;
  wire [1:0] s_dSizeNext = (reset == 1'b1) ? 2'b10 :
                           (writeSpr == 1'b1 && writeSprIndex == 16'h0005 && writeData[29] == 1'b0 && s_superVisionReg[3] == 1'b0) ? writeData[31:30] : s_dSizeReg;
  wire s_dCoherenceEnabledNext = (reset == 1'b1) ? 1'b0 :
                                 (writeSpr == 1'b1 && writeSprIndex == 16'h0005 && writeData[29] == 1'b0 && s_superVisionReg[3] == 1'b0) ? writeData[18] : s_dCoherenceEnabledReg;
  wire s_flushDCacheNext = (writeSpr == 1'b1 && writeSprIndex == 16'h0005 && stall == 1'b0) ? writeData[29] : 1'b0;
  
  assign dcacheReplacementPolicy = s_dReplacementPolicyReg;
  assign dcacheEnabled           = s_superVisionReg[3];
  assign dcacheFlush             = s_flushDCacheReg;
  assign dcacheWriteBackEnabled  = s_dWriteBackReg;
  assign dcacheSnarfingEnabled   = s_dSnarfingEnabledReg;
  assign dcacheMesiEnabled       = s_dMesiEnabledReg;
  assign dcacheCoherenceEnabled  = s_dCoherenceEnabledReg;
  assign dcacheSize              = s_dSizeReg;
  assign dcacheNumberOfWays      = s_dNumberOfWaysReg;

  always @(posedge clock)
    begin
      s_dReplacementPolicyReg <= s_dReplacementPolicyNext;
      s_dWriteBackReg         <= s_dWriteBackNext;
      s_dSnarfingEnabledReg   <= s_dSnarfingEnabledNext;
      s_dMesiEnabledReg       <= s_dMesiEnabledNext;
      s_dNumberOfWaysReg      <= s_dNumberOfWaysNext;
      s_dSizeReg              <= s_dSizeNext;
      s_dCoherenceEnabledReg  <= s_dCoherenceEnabledNext;
      s_flushDCacheReg        <= s_flushDCacheNext;
    end
  
  always @*
    begin
      s_dcacheConfigurationRegister[31:30] <= s_dSizeReg;
      s_dcacheConfigurationRegister[29:22] <= 8'd0;
      s_dcacheConfigurationRegister[21]    <= s_dSnarfingEnabledReg;
      s_dcacheConfigurationRegister[20]    <= s_dMesiEnabledReg;
      s_dcacheConfigurationRegister[19]    <= s_superVisionReg[3];
      s_dcacheConfigurationRegister[18]    <= s_dCoherenceEnabledReg;
      s_dcacheConfigurationRegister[17:16] <= s_dReplacementPolicyReg;
      s_dcacheConfigurationRegister[15:9]  <= 7'd0;
      s_dcacheConfigurationRegister[8]     <= s_dWriteBackReg;
      s_dcacheConfigurationRegister[7]     <= 1'd1;
      s_dcacheConfigurationRegister[2]     <= 1'd0;
      s_dcacheConfigurationRegister[1:0]   <= s_dNumberOfWaysReg;
      case (s_dSizeReg)
        2'b00   : case (s_dNumberOfWaysReg)
                    2'b01   : s_dcacheConfigurationRegister[6:3] <= 4'h5;
                    2'b10   : s_dcacheConfigurationRegister[6:3] <= 4'h4;
                    default : s_dcacheConfigurationRegister[6:3] <= 4'h6;
                  endcase
        2'b01   : case (s_dNumberOfWaysReg)
                    2'b01   : s_dcacheConfigurationRegister[6:3] <= 4'h6;
                    2'b10   : s_dcacheConfigurationRegister[6:3] <= 4'h5;
                    default : s_dcacheConfigurationRegister[6:3] <= 4'h7;
                  endcase
        2'b10   : case (s_dNumberOfWaysReg)
                    2'b01   : s_dcacheConfigurationRegister[6:3] <= 4'h7;
                    2'b10   : s_dcacheConfigurationRegister[6:3] <= 4'h6;
                    default : s_dcacheConfigurationRegister[6:3] <= 4'h8;
                  endcase
        default : case (s_dNumberOfWaysReg)
                    2'b01   : s_dcacheConfigurationRegister[6:3] <= 4'h8;
                    2'b10   : s_dcacheConfigurationRegister[6:3] <= 4'h7;
                    default : s_dcacheConfigurationRegister[6:3] <= 4'h9;
                  endcase
      endcase
    end

  /*
   *
   * Here the tick timer module is defined
   *
   */
  reg [31:0] s_tickTimerCountReg;
  reg [27:0] s_tickTimerTpReg;
  reg [1:0] s_tickTimerModeReg;
  reg s_tickTimerIpReg, s_tickTimerIeReg;
  wire s_tickTimerMatch = (s_tickTimerCountReg[27:0] == s_tickTimerTpReg) ? 1'b1 : 1'b0;
  wire s_tickTimerReset = (s_tickTimerMatch == 1'b1 && s_tickTimerModeReg == 2'b01) ? 1'b1 : 1'b0;
  wire s_tickTimerCountEnable = (s_tickTimerModeReg == 2'b00 || (s_tickTimerMatch == 1'b1 && s_tickTimerModeReg == 2'b10)) ? 1'b0 : 1'b1;
  wire [1:0] s_tickTimerModeNext = (reset == 1'b1) ? 2'd0 :
                                   (writeSpr == 1'b1 && writeSprIndex == 16'h5000 && s_supervisionMode == 1'b1) ? writeData[31:30] : s_tickTimerModeReg;
  wire s_tickTimerIeNext = (reset == 1'b1) ? 1'b0 :
                           (writeSpr == 1'b1 && writeSprIndex == 16'h5000 && s_supervisionMode == 1'b1) ? writeData[29] : s_tickTimerIeReg;
  wire [27:0] s_tickTimerTpNext = (reset == 1'b1) ? 28'd0 :
                                  (writeSpr == 1'b1 && writeSprIndex == 16'h5000 && s_supervisionMode == 1'b1) ? writeData[27:0] : s_tickTimerTpReg;
  wire s_tickTimerIpNext = (writeSpr == 1'b1 && writeSprIndex == 16'h5000 && s_supervisionMode == 1'b1) ? writeData[28] :
                           (reset == 1'b1 || s_tickTimerModeReg == 2'b00) ? 1'b0 : s_tickTimerIpReg | s_tickTimerMatch;
  wire [31:0] s_tickTimerCountNext = (writeSpr == 1'b1 && writeSprIndex == 16'h5001 && s_supervisionMode == 1'b1) ? writeData :
                                     (reset == 1'b1 || s_tickTimerReset == 1'b1) ? 32'd0 :
                                     (s_tickTimerCountEnable == 1'b1) ? s_tickTimerCountReg + 32'd1 : s_tickTimerCountReg;
  
  assign tickTimerIrq = s_tickTimerIpReg & s_tickTimerIeReg & s_superVisionReg[1];
  
  always @(posedge clock)
    begin
      s_tickTimerModeReg  <= s_tickTimerModeNext;
      s_tickTimerIeReg    <= s_tickTimerIeNext;
      s_tickTimerTpReg    <= s_tickTimerTpNext;
      s_tickTimerIpReg    <= s_tickTimerIpNext;
      s_tickTimerCountReg <= s_tickTimerCountNext;
    end

  /*
   *
   * here the pic module is defined
   *
   */
  reg [31:0] s_picMrReg, s_picSrReg;
  wire [31:0] s_picMrNext = (reset == 1'b1) ? 32'd0 :
                            (writeSpr == 1'b1 && writeSprIndex == 16'h4800 && s_supervisionMode == 1'b1) ? writeData : s_picMrReg;
  
  assign irq = (s_picSrReg == 32'd0) ? 1'b0 : 1'b1;
  
  always @(posedge clock)
    begin
      s_picMrReg <= s_picMrNext;
      s_picSrReg <= s_picMrReg & irqVector;
    end

  /*
   *
   * here the processor id register is defined
   *
   */
  
  wire [31:0] s_procFreqId;
  processorId #( .processorId(processorId),
                 .NumberOfProcessors(NumberOfProcessors),
                 .ReferenceClockFrequencyInHz(ReferenceClockFrequencyInHz)) procId 
              ( .clock(clock),
                .reset(reset),
                .referenceClock(referenceClock),
                .biosBypass(1'b1),
                .procFreqId(s_procFreqId) );

  /*
   *
   * Here the multi-processor interface is defined
   *
   */
  reg s_myBarrierReg, s_cpuEnabledReg, s_weStatusReg, s_weJumpAddressReg, s_weCacheConfigReg;
  reg s_weStackTopReg;
  reg [7:0] s_barrierValuesReg;
  reg [31:0] s_jumpAddressReg;
  reg [15:0] s_cacheConfigurationReg;
  reg [5:0] s_memoryDistanceInReg, s_memoryDistanceOutReg;
  wire s_myBarrierNext = (reset == 1'b1) ? 1'b0 :
                         (writeSpr == 1'b1 && writeSprIndex == 15'h5002) ? writeData[0] : s_myBarrierReg;
  wire [5:0] s_memoryDistanceOutNext = (reset == 1'b1) ? 6'd0 :
                                       (writeSpr == 1'b1 && writeSprIndex == 16'hD800) ? writeData[5:0] : s_memoryDistanceOutReg;
  wire s_weStatusNext = (writeSpr == 1'b1 && writeSprIndex == 15'h5004) ? 1'b1 : 1'b0;
  wire s_weJumpAddressNext = (writeSpr == 1'b1 && writeSprIndex[15:5] == {8'h50, 3'd0}) ? 1'b1 : 1'b0;
  wire s_weCacheConfigNext = (writeSpr == 1'b1 && writeSprIndex[15:3] == {12'h501, 1'd0}) ? 1'b1 : 1'b0;
  wire s_weStackTopNext = (writeSpr == 1'b1 && writeSprIndex[15:3] == {12'h502, 1'd0}) ? 1'b1 : 1'b0;

  assign memoryDistanceOut = s_memoryDistanceOutReg;
  assign weStatusOut       = s_weStatusReg;
  assign weJumpAddress     = s_weJumpAddressReg;
  assign weCacheConfig     = s_weCacheConfigReg;
  assign weStackTop        = s_weStackTopReg;
  assign myBarrierValue    = s_myBarrierReg;

  always @(posedge clock)
    begin
      s_myBarrierReg          <= s_myBarrierNext;
      s_cpuEnabledReg         <= cpuEnabled;
      s_barrierValuesReg      <= barrierValues;
      s_jumpAddressReg        <= jumpAddressIn;
      s_cacheConfigurationReg <= cacheConfiguration;
      s_memoryDistanceInReg   <= memoryDistanceIn;
      s_memoryDistanceOutReg  <= s_memoryDistanceOutNext;
      dataOutReg              <= writeData;
      selectOutReg            <= writeSprIndex[2:0];
      s_weStatusReg           <= s_weStatusNext;
      s_weJumpAddressReg      <= s_weJumpAddressNext;
      s_weCacheConfigReg      <= s_weCacheConfigNext;
      s_weStackTopReg         <= s_weStackTopNext;
    end

  /*
   *
   * Here the spr-mapped exception vectors are defined
   *
   */
  reg s_softBiosReg, s_previosSoftBiosReg;
  reg [27:0] s_BusErrorVectorReg, s_TickTimerVectorReg, s_AllignmentVectorReg, s_IllegalInstructionVectorReg;
  reg [27:0] s_InterruptVectorReg, s_RangeVectorReg, s_SystemCallVectorReg, s_TrapVectorReg, s_BreakPointReg;
  wire [27:0] s_BusErrorVectorNext = (reset == 1'b1) ? 28'h0000008 :
                                     (writeSpr == 1'b1 && writeSprIndex == 16'hE000 && s_supervisionMode == 1'b1) ? writeData[27:0] : s_BusErrorVectorReg;
  wire [27:0] s_TickTimerVectorNext = (reset == 1'b1) ? 28'h0000020 :
                                      (writeSpr == 1'b1 && writeSprIndex == 16'hE003 && s_supervisionMode == 1'b1) ? writeData[27:0] : s_TickTimerVectorReg;
  wire [27:0] s_AllignmentVectorNext = (reset == 1'b1) ? 28'h0000028 :
                                       (writeSpr == 1'b1 && writeSprIndex == 16'hE004 && s_supervisionMode == 1'b1) ? writeData[27:0] : s_AllignmentVectorReg;
  wire [27:0] s_IllegalInstructionVectorNext = (reset == 1'b1) ? 28'h0000030 :
                                               (writeSpr == 1'b1 && writeSprIndex == 16'hE005 && s_supervisionMode == 1'b1) ? writeData[27:0] : s_IllegalInstructionVectorReg;
  wire [27:0] s_InterruptVectorNext = (reset == 1'b1) ? 28'h0000038 :
                                      (writeSpr == 1'b1 && writeSprIndex == 16'hE006 && s_supervisionMode == 1'b1) ? writeData[27:0] : s_InterruptVectorReg;
  wire [27:0] s_RangeVectorNext = (reset == 1'b1) ? 28'h0000050 :
                                  (writeSpr == 1'b1 && writeSprIndex == 16'hE009 && s_supervisionMode == 1'b1) ? writeData[27:0] : s_RangeVectorReg;
  wire [27:0] s_SystemCallVectorNext = (reset == 1'b1) ? 28'h0000058 :
                                       (writeSpr == 1'b1 && writeSprIndex == 16'hE00A && s_supervisionMode == 1'b1) ? writeData[27:0] : s_SystemCallVectorReg;
  wire [27:0] s_TrapVectorNext = (reset == 1'b1) ? 28'h0000060 :
                                 (writeSpr == 1'b1 && writeSprIndex == 16'hE00B && s_supervisionMode == 1'b1) ? writeData[27:0] : s_TrapVectorReg;
  wire [27:0] s_BreakPointNext = (reset == 1'b1) ? 28'h0000068 :
                                 (writeSpr == 1'b1 && writeSprIndex == 16'hE00C && s_supervisionMode == 1'b1) ? writeData[27:0] : s_BreakPointReg;
  wire s_softBiosNext = (pllReset == 1'b1) ? 1'b0 : (writeSpr == 1'b1 && writeSprIndex == 16'hE00F && s_supervisionMode == 1'b1) ? writeData[0] : s_softBiosReg;

  
  assign BusErrorVector           = s_BusErrorVectorReg;
  assign TickTimerVector          = s_TickTimerVectorReg;
  assign AllignmentVector         = s_AllignmentVectorReg;
  assign IllegalInstructionVector = s_IllegalInstructionVectorReg;
  assign InterruptVector          = s_InterruptVectorReg;
  assign RangeVector              = s_RangeVectorReg;
  assign SystemCallVector         = s_SystemCallVectorReg;
  assign TrapVector               = s_TrapVectorReg;
  assign BreakPointVector         = s_BreakPointReg;
  assign softBios                 = s_softBiosReg;
  assign performSoftReset         = ((s_softBiosReg != s_previosSoftBiosReg) || (writeSpr == 1'b1 && writeSprIndex == 16'hE00E)) ? 1'b1 : 1'b0;
  
  always @(posedge clock)
    begin
      s_BusErrorVectorReg           <= s_BusErrorVectorNext;
      s_TickTimerVectorReg          <= s_TickTimerVectorNext;
      s_AllignmentVectorReg         <= s_AllignmentVectorNext;
      s_IllegalInstructionVectorReg <= s_IllegalInstructionVectorNext;
      s_InterruptVectorReg          <= s_InterruptVectorNext;
      s_RangeVectorReg              <= s_RangeVectorNext;
      s_SystemCallVectorReg         <= s_SystemCallVectorNext;
      s_TrapVectorReg               <= s_TrapVectorNext;
      s_BreakPointReg               <= s_BreakPointNext;
      s_softBiosReg                 <= s_softBiosNext;
      s_previosSoftBiosReg          <= s_softBiosReg;
    end

  /*
   *
   * Here the srams for the registers are defined
   *
   */
  wire [31:0] s_operantC, s_operantA, s_operantB;
  assign operantA = (lookupOperantAAddr[4:0] == 5'd0) ? 32'd0 : s_operantA;
  assign operantB = (lookupOperantBAddr[4:0] == 5'd0) ? 32'd0 : s_operantB;
`ifdef CIDEnabled  
  wire s_invertedClock = ~clock;
  sram512X32Dp registers1 ( .clockA(s_invertedClock),
                            .writeEnableA(1'b0),
                            .addressA(lookupOperantAAddr),
                            .dataInA(32'd0),
                            .dataOutA(s_operantA),
                            .clockB(clock),
                            .writeEnableB(s_writeEnable),
                            .addressB(s_writeAddress),
                            .dataInB(s_writeData),
                            .dataOutB());

  sram512X32Dp registers2 ( .clockA(s_invertedClock),
                            .writeEnableA(1'b0),
                            .addressA(lookupOperantBAddr),
                            .dataInA(32'd0),
                            .dataOutA(s_operantB),
                            .clockB(clock),
                            .writeEnableB(s_writeEnable),
                            .addressB(s_writeAddress),
                            .dataInB(s_writeData),
                            .dataOutB());

  sram512X32Dp registers3 ( .clockA(s_invertedClock),
                            .writeEnableA(1'b0),
                            .addressA(exeSprIndex[8:0]),
                            .dataInA(32'd0),
                            .dataOutA(s_operantC),
                            .clockB(clock),
                            .writeEnableB(s_writeEnable),
                            .addressB(s_writeAddress),
                            .dataInB(s_writeData),
                            .dataOutB());
`else
  sram32x32DpAr registers1 ( .writeClock(clock),
                             .writeEnable(s_writeEnable),
                             .writeAddress(s_writeAddress[4:0]),
                             .readAddress(lookupOperantAAddr[4:0]),
                             .writeData(s_writeData),
                             .dataReadPort(s_operantA));

  sram32x32DpAr registers2 ( .writeClock(clock),
                             .writeEnable(s_writeEnable),
                             .writeAddress(s_writeAddress[4:0]),
                             .readAddress(lookupOperantBAddr[4:0]),
                             .writeData(s_writeData),
                             .dataReadPort(s_operantB));

  sram32x32DpAr registers3 ( .writeClock(clock),
                             .writeEnable(s_writeEnable),
                             .writeAddress(s_writeAddress[4:0]),
                             .readAddress(exeSprIndex[4:0]),
                             .writeData(s_writeData),
                             .dataReadPort(s_operantC));
`endif
  /* 
   * Here the exception reason is defined
   *
   */
  reg [3:0] s_exceptionIndexReg;
  wire [3:0] s_exceptionIndex;
  wire s_weExceptionIndexReg = exceptionTaken & ~stall;
  assign s_exceptionIndex[0] = exceptionReason[1] | exceptionReason[3] | exceptionReason[5] | exceptionReason[7] | exceptionReason[9] | exceptionReason[11] | exceptionReason[13];
  assign s_exceptionIndex[1] = exceptionReason[2] | exceptionReason[3] | exceptionReason[6] | exceptionReason[7] | exceptionReason[10] | exceptionReason[11];
  assign s_exceptionIndex[2] = exceptionReason[4] | exceptionReason[5] | exceptionReason[6] | exceptionReason[7] | exceptionReason[12] | exceptionReason[13];
  assign s_exceptionIndex[3] = exceptionReason[8] | exceptionReason[9] | exceptionReason[10] | exceptionReason[11] | exceptionReason[12] | exceptionReason[13];
  
  always @(posedge clock) s_exceptionIndexReg <= (s_weExceptionIndexReg == 1'b1) ? s_exceptionIndex : s_exceptionIndexReg;
  /*
   *
   * Here the spr data is defined
   *
   */
  always @*
    case (exeSprIndex[15:12])
      4'hF    : exeSprData <= (exeSprIndex[11] == 1'b1) ? profilingData : 32'd0;
      4'hE    : case (exeSprIndex[11:0])
                  12'h000  : exeSprData <= { {4{s_superVisionReg[14]}}, s_BusErrorVectorReg };
                  12'h003  : exeSprData <= { {4{s_superVisionReg[14]}}, s_TickTimerVectorReg };
                  12'h004  : exeSprData <= { {4{s_superVisionReg[14]}}, s_AllignmentVectorReg };
                  12'h005  : exeSprData <= { {4{s_superVisionReg[14]}}, s_IllegalInstructionVectorReg };
                  12'h006  : exeSprData <= { {4{s_superVisionReg[14]}}, s_InterruptVectorReg };
                  12'h009  : exeSprData <= { {4{s_superVisionReg[14]}}, s_RangeVectorReg };
                  12'h00A  : exeSprData <= { {4{s_superVisionReg[14]}}, s_SystemCallVectorReg };
                  12'h00B  : exeSprData <= { {4{s_superVisionReg[14]}}, s_TrapVectorReg };
                  12'h00C  : exeSprData <= { {4{s_superVisionReg[14]}}, s_BreakPointReg };
                  12'h00D  : exeSprData <= { {4{s_superVisionReg[14]}}, 28'h0000070 };
                  12'h00F  : exeSprData <= { 31'd0, s_softBiosReg };
                  default  : exeSprData <= 32'd0;
                endcase
      4'hD    : exeSprData <= (exeSprIndex[11] == 1'b1) ? {24'd0, s_memoryDistanceInReg} : 32'd0;
      4'h2    : case (exeSprIndex[11:0])
                  12'h801  : exeSprData <= multMacLo;
                  12'h802  : exeSprData <= multMacHi;
                  default  : exeSprData <= 32'd0;
                endcase
     4'h3     : exeSprData <= (exeSprIndex[11] == 1'b0 && s_supervisionMode == 1'b1) ? debugData : 32'd0;
     4'h4     : case (exeSprIndex[11:0])
                  12'h800  : exeSprData <= s_picMrReg;
                  12'h802  : exeSprData <= s_picSrReg;
                  default  : exeSprData <= 32'd0;
                endcase
     4'h5     : case (exeSprIndex[11:0])
                  12'h000  : exeSprData <= {s_tickTimerModeReg, s_tickTimerIeReg, s_tickTimerIpReg, s_tickTimerTpReg};
                  12'h001  : exeSprData <= s_tickTimerCountReg;
                  12'h002  : exeSprData <= {s_cpuEnabledReg, 15'd0, s_barrierValuesReg, 7'd0, s_myBarrierReg};
                  12'h003  : exeSprData <= s_jumpAddressReg;
                  12'h004  : exeSprData <= {16'd0, s_cacheConfigurationReg};
                  12'h005  : exeSprData <= stackTopPointer;
                  default  : exeSprData <= 32'd0;
                endcase
    4'h0      : case (exeSprIndex[11:8])
                  4'h4     : exeSprData <= s_operantC;
                  4'h0     : case (exeSprIndex[7:0])
                               8'h00   : exeSprData <= 32'h12110001;
                               8'h01   : exeSprData <= (nrOfBreakpoints == 0) ? 32'h00000527 : 32'h00000567;
                               8'h02   : exeSprData <= `ifdef CIDEnabled 32'h0000002F `else 32'h00000020 `endif;
                               8'h05   : exeSprData <= s_dcacheConfigurationRegister;
                               8'h06   : exeSprData <= s_icacheConfigurationRegister;
                               8'h07   : begin
                                           exeSprData[31:3] <= 29'd0;
                                           exeSprData[2:0]  <= (nrOfBreakpoints == 0) ? 3'd0 : nrOfBreakpoints - 1;
                                         end
                               8'h09   : exeSprData <= s_procFreqId;
                               8'h10   : exeSprData <= instructionAddress;
                               8'h11   : exeSprData <= s_superVisionReg;
                               8'h12   : exeSprData <= {28'd0,s_exceptionIndexReg};
                               8'h20,
                               8'h21,
                               8'h22,
                               8'h23,
                               8'h24,
                               8'h25,
                               8'h26,
                               8'h27,
                               8'h28,
                               8'h29,
                               8'h2A,
                               8'h2B,
                               8'h2C,
                               8'h2D,
                               8'h2E,
                               8'h2F   : exeSprData <= s_epcrSpr;
                               8'h30,
                               8'h31,
                               8'h32,
                               8'h33,
                               8'h34,
                               8'h35,
                               8'h36,
                               8'h37,
                               8'h38,
                               8'h39,
                               8'h3A,
                               8'h3B,
                               8'h3C,
                               8'h3D,
                               8'h3E,
                               8'h3F   : exeSprData <= s_eearSpr;
                               8'h40,
                               8'h41,
                               8'h42,
                               8'h43,
                               8'h44,
                               8'h45,
                               8'h46,
                               8'h47,
                               8'h48,
                               8'h49,
                               8'h4A,
                               8'h4B,
                               8'h4C,
                               8'h4D,
                               8'h4E,
                               8'h4F   : exeSprData <= s_esrSpr;
                               8'h50   : exeSprData <= ebuIr;
                               default : exeSprData <= 32'd0;
                             endcase
                  default  : exeSprData <= 32'd0;
                endcase
     default  : exeSprData <= 32'd0;
   endcase
endmodule
