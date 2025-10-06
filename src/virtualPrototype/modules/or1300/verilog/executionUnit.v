module executionUnit ( input wire         clock,
                                          reset,
                                          stall,
                                          flush,
                                          dividerStallIn,
                                          multiplierStallIn,
                                          custInstrStallIn,
                       output wire        dividerStallOut,
                                          multiplierStallOut,
                                          custInstrStallOut,
                       
                       // here the interface to the register file is defined
                       input wire [31:0]  operantA,
                                          operantB,
                                          storeDataIn,
                       input wire [4:0]   operantAAddr,
                                          operantBAddr,
                       input wire [8:0]   destination,
                       input wire [15:0]  immValue,
                       input wire         weDestination,
                                          custom,
                                          validInstruction,
                                          activeInstructionIn,
                                          instructionAbortIn,
                       input wire [31:0]  instructionAddress,
                                          sprData,
                       output wire [15:0] sprIndex,
                       input wire [1:0]   isSpr,
                       input wire [15:0]  sprOrMask,
                       input wire         isJumpIn,
                                          isRfeIn,
                                          systemCallIn,
                                          trapIn,
                                          divide,
                                          multiply,
                                          carryIn,
                                          updateCarry,
                                          overflowIn,
                                          updateOverflow,
                                          flagIn,
                                          updateFlag,
                       input wire [1:0]   syncCommandIn,
                       input wire [3:0]   compareCntrl,
                       input wire [2:0]   exeControl,
                                          resultSelection,
                                          store,
                                          load,
                       input wire [31:0]  supervisionRegister,
                       output wire        fastFlag,
                       output wire [31:0] multMacLo,
                                          multMacHi,
                       
                       // here the debug interface is defined
                       input wire [15:0]  debugSprSelect,
                       input wire         debugWeSprData,
                       input wire         debugReSprData,
                       input  wire [31:0] debugSprDataOut,
                       
                       // here the i$ interface is defined
                       input wire [31:0]  returnAddress,
                       
                       // here the custom instruction interface is defined
                       output wire [31:0] customInstructionDataA,
                                          customInstructionDataB,
                       output wire [7:0]  customInstructionN,
                       output wire        customInstructionReadRa,
                                          customInstructionReadRb,
                                          customInstructionWriteRc,
                       output wire [4:0]  customInstructionA,
                                          customInstructionB,
                                          customInstructionC,
                       output wire        customInstructionStart,
                                          customInstructionClockEnable,
                       input wire [31:0]  customInstructionResult,
                       input wire         customInstructionDone,
                       
                       // here the IR-passthrough is defined
                       input wire [31:0]  irIn,
                       output wire [31:0] irOut,
                       
                       // here the interface to the foreward unit is defined
                       input wire [31:0]  forwardedOperantA,
                                          forwardedOperantB,
                                          forwardedStoreData,
                       input wire         useForwardedOpA,
                                          useForwardedOpB,
                                          useForwardedStoreData,
                       // here the interface to the d$ is defined
                       input wire         resetLoad,
                       output wire [31:0] dataOut,
                                          memoryAddress,
                       output wire [2:0]  memoryLoad,
                                          memoryStore,
                       output wire [8:0]  loadTarget,
                       output wire [7:0]  memoryCompareValue,
                       
                       // here the write back interface is defined
                       output wire [4:0]  writeAddress,
                       output wire [31:0] writeData,
                                          pc,
                       output wire [15:0] writeSprIndex,
                       output wire [31:2] jumpRegister,
                       output wire [1:0]  syncCommand,
                       output wire        isJump,
                                          isRfe,
                                          writeEnable,
                                          writeSpr,
                                          systemCall,
                                          trap,
                                          allignmentError,
                                          instructionAbort,
                                          invalidInstruction,
                                          activeInstruction,
                                          divZeroException,
                                          carryOut,
                                          weCarry,
                                          overflowOut,
                                          weOverflow,
                                          flagOut,
                                          weFlag );

  localparam [2:0] NO_LOAD                      = 3'b000;
  localparam [2:0] LOAD_BYTE_ZERO_EXTENDED      = 3'b001;
  localparam [2:0] LOAD_BYTE_SIGN_EXTENDED      = 3'b101;
  localparam [2:0] LOAD_HALF_WORD_ZERO_EXTENDED = 3'b010;
  localparam [2:0] LOAD_HALF_WORD_SIGN_EXTENDED = 3'b110;
  localparam [2:0] LOAD_WORD_ZERO_EXTENDED      = 3'b011;
  localparam [2:0] LOAD_WORD_SIGN_EXTENDED      = 3'b111;

  localparam [2:0] NO_STORE                     = 3'b000;
  localparam [2:0] STORE_BYTE                   = 3'b001;
  localparam [2:0] STORE_HALF_WORD              = 3'b010;
  localparam [2:0] STORE_WORD                   = 3'b011;
  localparam [2:0] COMPARE_AND_SWAP             = 3'b100;
  localparam [2:0] SWAP                         = 3'b101;
                        
  wire [31:0] s_operantA = (useForwardedOpA == 1'b1) ? forwardedOperantA : operantA;
  wire [31:0] s_operantB = (useForwardedOpB == 1'b1) ? forwardedOperantB : operantB;
  wire [31:0] s_adderResult;
  
  /* 
   *
   * Here the pipeline registers are defined
   *
   */
  reg s_updateCarryReg, s_updateOverflowReg, s_updateFlagReg, s_writeSprReg;
  reg s_weDestinationReg, s_isJumpReg, s_trapReg, s_isRfeReg, s_systemCallReg;
  reg s_instructionAbortReg, s_invalidInstructionReg, s_activeInstructionReg;
  reg [31:0] s_resultReg, s_customResultReg, s_selectedResult, s_memoryAddressReg;
  reg [31:0] s_irReg, s_pcReg, s_dataOutReg;
  reg [2:0] s_resultSelectionReg, s_storeReg, s_loadReg;
  reg [15:0] s_writeSprIndexReg;
  reg [8:0] s_destinationReg;
  reg [1:0] s_syncCommandReg;
  reg [7:0] s_memoryCompareValueReg;
  wire [15:0] s_sprIndex = (debugReSprData == 1'b1) ? debugSprSelect : s_operantA[15:0] | sprOrMask;
  wire s_updateCarryNext = (reset == 1'b1) ? 1'b0 :
                           (stall == 1'b1) ? s_updateCarryReg : 
                           (flush == 1'b1) ? 1'b0 : updateCarry;
  wire s_updateOverflowNext = (reset == 1'b1) ? 1'b0 :
                              (stall == 1'b1) ? s_updateOverflowReg :
                              (flush == 1'b1) ? 1'b0 : updateOverflow;
  wire s_updateFlagNext = (reset == 1'b1) ? 1'b0 :
                          (stall == 1'b1) ? s_updateFlagReg :
                          (flush == 1'b1) ? 1'b0 : updateFlag;
  wire [2:0] s_resultSelectionNext = (stall == 1'b1) ? s_resultSelectionReg : resultSelection;
  wire [15:0] s_writeSprIndexNext = (stall == 1'b0 && isSpr == 2'b10) ? s_sprIndex : s_writeSprIndexReg;
  wire s_writeSprNext = (reset == 1'b1) ? 1'b0 :
                        (stall == 1'b1) ? s_writeSprReg :
                        (flush == 1'b1) ? 1'b0 :
                        (isSpr == 2'b10) ? 1'b1 : 1'b0;
  wire [31:0] s_result = (debugWeSprData == 1'b1) ? debugSprDataOut : (s_resultSelectionReg == 3'b111) ? s_customResultReg : s_resultReg;
  wire [31:0] s_resultNext = (stall == 1'b1) ? s_resultReg : s_selectedResult;
  wire [31:0] s_customResultNext = (customInstructionDone == 1'b1) ? customInstructionResult : s_customResultReg;
  wire s_weDestinationNext = (reset == 1'b1) ? 1'b0 : (stall == 1'b1) ? s_weDestinationReg : (flush == 1'b1) ? 1'b0 : weDestination;
  wire [8:0] s_destinationNext = (stall == 1'b1) ? s_destinationReg : destination;
  wire s_isJumpNext = (reset == 1'b1) ? 1'b0 : (stall == 1'b1) ? s_isJumpReg : (flush == 1'b1) ? 1'b0 : isJumpIn;
  wire [31:0] s_memoryAddressNext = (stall == 1'b1) ? s_memoryAddressReg :
                                    (store == SWAP || store == COMPARE_AND_SWAP) ? s_operantA :
                                    (store != NO_STORE || load != NO_LOAD) ? s_adderResult : s_memoryAddressReg;
  wire [2:0] s_storeNext = (reset == 1'b1 || resetLoad == 1'b1) ? NO_STORE :
                           (stall == 1'b1) ? s_storeReg : (flush == 1'b1) ? NO_STORE : store;
  wire [2:0] s_loadNext = (reset == 1'b1 || resetLoad == 1'b1) ? NO_LOAD :
                          (stall == 1'b1) ? s_loadReg : (flush == 1'b1) ? NO_LOAD : load;
  wire s_trap;
  wire s_trapNext = (reset == 1'b1) ? 1'b0 : (stall == 1'b1) ? s_trapReg : (flush == 1'b1) ? 1'b0 : s_trap;
  wire [1:0] s_syncCommandNext = (reset == 1'b1) ? 2'b00 : (stall == 1'b1) ? s_syncCommandReg : (flush == 1'b1) ? 2'b00 : syncCommandIn;
  wire [7:0] s_memoryCompareValueNext = (stall == 1'b1) ? s_memoryCompareValueReg :
                                        (store == COMPARE_AND_SWAP) ? immValue[7:0] : s_memoryCompareValueReg;
  wire s_isRfeNext = (reset == 1'b1) ? 1'b0 : (stall == 1'b1) ? s_isRfeReg : (flush == 1'b1) ? 1'b0 : isRfeIn;
  wire s_systemCallNext = (reset == 1'b1) ? 1'b0 : (stall == 1'b1) ? s_systemCallReg : (flush == 1'b1) ? 1'b0 : systemCallIn;
  wire [31:0] s_irNext = (stall == 1'b1) ? s_irReg : irIn;
  wire [31:0] s_pcNext = (stall == 1'b1) ? s_pcReg : instructionAddress;
  wire s_instructionAbortNext = (reset == 1'b1) ? 1'b0 : (stall == 1'b1) ? s_instructionAbortReg : (flush == 1'b1) ? 1'b0 : instructionAbortIn;
  wire s_invalidInstructionNext = (reset == 1'b1) ? 1'b0 : (stall == 1'b1) ? s_invalidInstructionReg : (flush == 1'b1) ? 1'b0 : ~validInstruction;
  wire s_activeInstructionNext = (reset == 1'b1) ? 1'b0 : (stall == 1'b1) ? s_activeInstructionReg : (flush == 1'b1) ? 1'b0 : activeInstructionIn;
  wire [31:0] s_dataOutNext = (stall == 1'b1 || store == NO_STORE) ? s_dataOutReg : (useForwardedStoreData == 1'b1) ? forwardedStoreData : storeDataIn;
  
  assign weCarry            = s_updateCarryReg;
  assign weOverflow         = s_updateOverflowReg;
  assign weFlag             = s_updateFlagReg;
  assign writeSprIndex      = (debugWeSprData == 1'b1) ? debugSprSelect : s_writeSprIndexReg;
  assign writeSpr           = (debugWeSprData == 1'b1) ? debugWeSprData : s_writeSprReg;
  assign writeData          = s_result;
  assign writeEnable        = s_weDestinationReg;
  assign writeAddress       = s_destinationReg[4:0];
  assign loadTarget         = s_destinationReg;
  assign sprIndex           = s_sprIndex;
  assign isJump             = s_isJumpReg;
  assign memoryAddress      = s_memoryAddressReg;
  assign trap               = s_trapReg;
  assign syncCommand        = s_syncCommandReg;
  assign memoryCompareValue = s_memoryCompareValueReg;
  assign isRfe              = s_isRfeReg;
  assign systemCall         = s_systemCallReg;
  assign irOut              = s_irReg;
  assign pc                 = s_pcReg;
  assign instructionAbort   = s_instructionAbortReg;
  assign invalidInstruction = s_invalidInstructionReg;
  assign activeInstruction  = s_activeInstructionReg;
  assign dataOut            = s_dataOutReg;

  always @ (posedge clock)
    begin
      s_updateCarryReg        <= s_updateCarryNext;
      s_updateOverflowReg     <= s_updateOverflowNext;
      s_updateFlagReg         <= s_updateFlagNext;
      s_resultSelectionReg    <= s_resultSelectionNext;
      s_writeSprIndexReg      <= s_writeSprIndexNext;
      s_writeSprReg           <= s_writeSprNext;
      s_resultReg             <= s_resultNext;
      s_customResultReg       <= s_customResultNext;
      s_weDestinationReg      <= s_weDestinationNext;
      s_destinationReg        <= s_destinationNext;
      s_isJumpReg             <= s_isJumpNext;
      s_memoryAddressReg      <= s_memoryAddressNext;
      s_storeReg              <= s_storeNext;
      s_loadReg               <= s_loadNext;
      s_trapReg               <= s_trapNext;
      s_syncCommandReg        <= s_syncCommandNext;
      s_memoryCompareValueReg <= s_memoryCompareValueNext;
      s_isRfeReg              <= s_isRfeNext;
      s_systemCallReg         <= s_systemCallNext;
      s_irReg                 <= s_irNext;
      s_pcReg                 <= s_pcNext;
      s_instructionAbortReg   <= s_instructionAbortNext;
      s_invalidInstructionReg <= s_invalidInstructionNext;
      s_activeInstructionReg  <= s_activeInstructionNext;
      s_dataOutReg            <= s_dataOutNext;
    end

  /*
   *
   * Here the allignment error related signals are defined
   *
   */
  wire s_allignmentError = ( ((s_storeReg == STORE_WORD || s_loadReg == LOAD_WORD_ZERO_EXTENDED || s_loadReg == LOAD_WORD_SIGN_EXTENDED) && s_memoryAddressReg[1:0] != 2'b00) ||
                             ((s_storeReg == STORE_HALF_WORD || s_loadReg == LOAD_HALF_WORD_ZERO_EXTENDED || s_loadReg == LOAD_HALF_WORD_SIGN_EXTENDED) && s_memoryAddressReg[0] != 1'b0) ||
                             (s_storeReg == SWAP && s_memoryAddressReg[1:0] != 2'b00)) ? 1'b1 : 1'b0;
  
  assign allignmentError = s_allignmentError;
  assign memoryStore     = (s_allignmentError == 1'b1) ? NO_STORE : s_storeReg;
  assign memoryLoad      = (s_allignmentError == 1'b1) ? NO_LOAD : s_loadReg;

  /*
   *
   * Here the flag related signals are defined
   *
   */
  wire s_dividerCarryOut, s_adderCarryOut, s_adderOverflow, s_adderFlag;
  wire s_carryOut    = (s_updateCarryReg == 1'b0) ? carryIn :
                       (s_resultSelectionReg == 3'b101) ? s_dividerCarryOut : s_adderCarryOut;
  wire s_overFlowOut = (s_updateOverflowReg == 1'b0) ? overflowIn : s_adderOverflow;
  wire s_flagIn      = (s_updateFlagReg == 1'b0) ? flagIn : s_adderFlag;
  
  assign carryOut    = s_carryOut;
  assign overflowOut = s_overFlowOut;
  assign fastFlag    = (s_updateFlagReg == 1'b1) ? s_adderFlag : supervisionRegister[9];
  assign flagOut     = s_adderFlag;

  /*
   *
   * Here the trap related signals are defined
   *
   */
  wire [16:0] s_trapSelection0 = (operantB[4] == 1'b1) ? supervisionRegister[31:16] : supervisionRegister[15:0];
  wire [7:0]  s_trapSelection1 = (operantB[3] == 1'b1) ? s_trapSelection0[15:8] : s_trapSelection0[7:0];
  wire [3:0]  s_trapSelection2 = (operantB[2] == 1'b1) ? s_trapSelection1[7:4] : s_trapSelection1[3:0];
  wire [1:0]  s_trapSelection3 = (operantB[1] == 1'b1) ? s_trapSelection2[3:2] : s_trapSelection2[1:0];
  wire        s_trapSelection4 = (operantB[0] == 1'b1) ? s_trapSelection3[1] : s_trapSelection3[0];
  
  assign s_trap = trapIn & s_trapSelection4;

  /*
   *
   * Here we define the adder
   *
   */
  assign jumpRegister = s_adderResult[31:2];
  
  adder theAdder ( .clock(clock),
                   .reset(reset),
                   .stall(stall),
                   .carryIn(s_carryOut),
                   .control(exeControl[1:0]),
                   .compareControl(compareCntrl),
                   .operantA(s_operantA),
                   .operantB(s_operantB),
                   .result(s_adderResult),
                   .carryOut(s_adderCarryOut),
                   .overflow(s_adderOverflow),
                   .flag(s_adderFlag) );

  /*
   *
   * Here we define the logic unit
   *
   */
 wire [31:0] s_logicResult;
 
 logicUnit theLogicUnit ( .control(exeControl),
                          .operantA(s_operantA),
                          .operantB(s_operantB),
                          .result(s_logicResult) );

  /*
   *
   * Here we define the shifter
   *
   */
  wire [31:0] s_shiftResult;
  
  shifter theShifter ( .control(exeControl[1:0]),
                       .operantA(s_operantA),
                       .operantB(s_operantB),
                       .result(s_shiftResult));

  /*
   *
   * Here we define the bit finder
   *
   */
  wire [31:0] s_bitFinderResult;
  
  bitFinder theBitFinder ( .control(exeControl[1:0]),
                           .flag(s_flagIn),
                           .operantA(s_operantA),
                           .operantB(s_operantB),
                           .result(s_bitFinderResult));

  /*
   *
   * Here we define the divider
   *
   */
  reg s_dividerBusyReg, s_dividerDoneReg;
  wire[31:0] s_dividerResult;
  wire s_dividerReady;
  wire s_doDivide = divide & ~s_dividerBusyReg & ~dividerStallIn & ~flush;
  wire s_dividerBusyNext = (reset == 1'b1 || s_dividerReady == 1'b1) ? 1'b0 : s_dividerBusyReg | s_doDivide;
  wire s_dividerDoneNext = (reset == 1'b1 || dividerStallIn == 1'b0) ? 1'b0 : s_dividerDoneReg | s_dividerReady;
  
  assign divZeroException = (s_dividerReady | s_dividerDoneReg) & s_dividerCarryOut;
  assign dividerStallOut = divide & ~s_dividerReady & ~s_dividerDoneReg;
  
  always @(posedge clock) 
    begin
      s_dividerBusyReg <= s_dividerBusyNext;
      s_dividerDoneReg <= s_dividerDoneNext;
    end
  
  divider theDivider ( .clock(clock),
                       .reset(reset),
                       .doDivide(s_doDivide),
                       .signedDivide(exeControl[0]),
                       .operantA(s_operantA),
                       .operantB(s_operantB),
                       .ready(s_dividerReady),
                       .carryOut(s_dividerCarryOut),
                       .quotient(s_dividerResult) );

  /*
   *
   * Here we define the multiplier
   *
   */
  reg s_multBusyReg, s_multDoneReg;
  wire[31:0] s_multResult;
  wire s_multReady;
  wire s_doMultiply   = multiply & ~s_multBusyReg & ~multiplierStallIn & ~flush;
  wire s_multBusyNext = (reset == 1'b1 || s_multReady == 1'b1) ? 1'b0 : s_multBusyReg | s_doMultiply;
  wire s_multDoneNext = (reset == 1'b1 || multiplierStallIn == 1'b0) ? 1'b0 : s_multDoneReg | s_multReady;
  wire s_weMacLo      = ((s_writeSprIndexReg == 16'h2801 && s_writeSprReg == 1'b1) ||
                         (debugSprSelect == 16'h2801 && debugWeSprData == 1'b1)) ? 1'b1 : 1'b0;
  wire s_weMacHi      = ((s_writeSprIndexReg == 16'h2802 && s_writeSprReg == 1'b1) ||
                         (debugSprSelect == 16'h2802 && debugWeSprData == 1'b1)) ? 1'b1 : 1'b0;
  
  
  assign multiplierStallOut = multiply & ~s_multReady & ~s_multDoneReg;
  
  always @(posedge clock)
    begin
      s_multBusyReg <= s_multBusyNext;
      s_multDoneReg <= s_multDoneNext;
    end
  
  multiplier theMultiplier ( .clock(clock),
                             .reset(reset),
                             .doMultiply(s_doMultiply),
                             .control(exeControl),
                             .operantA(s_operantA),
                             .operantB(s_operantB),
                             .weMacLo(s_weMacLo),
                             .weMacHi(s_weMacHi),
                             .weMacData(s_result),
                             .done(s_multReady),
                             .result(s_multResult),
                             .macLoData(multMacLo),
                             .macHiData(multMacHi) );

  /*
   *
   * Here we define the customInstruction interface
   *
   */
  reg s_custBusyReg, s_custDoneReg;
  wire s_doCustom = custom & ~s_custBusyReg & ~custInstrStallIn;
  wire s_custBusyNext = (reset == 1'b1 || customInstructionDone == 1'b1) ? 1'b0 : s_doCustom | s_custBusyReg;
  wire s_custDoneNext = (reset == 1'b1 || custInstrStallIn == 1'b0) ? 1'b0 : customInstructionDone | s_custDoneReg;

  assign customInstructionStart       = s_doCustom;
  assign customInstructionClockEnable = s_doCustom | s_custBusyReg;
  assign custInstrStallOut            = custom & ~customInstructionDone & ~s_custDoneReg;
  assign customInstructionDataA       = s_operantA;
  assign customInstructionDataB       = s_operantB;
  assign customInstructionN           = immValue[7:0];
  assign customInstructionReadRa      = immValue[10];
  assign customInstructionReadRb      = immValue[9];
  assign customInstructionWriteRc     = immValue[8];
  assign customInstructionA           = operantAAddr;
  assign customInstructionB           = operantBAddr;
  assign customInstructionC           = destination[4:0];
  
  always @ (posedge clock)
    begin
      s_custBusyReg <= s_custBusyNext;
      s_custDoneReg <= s_custDoneNext;
    end
  /*
   *
   * Here we define the selected result
   *
   */
  always @*
    case (resultSelection)
      3'b000  : s_selectedResult <= s_adderResult;
      3'b001  : s_selectedResult <= s_logicResult;
      3'b010  : s_selectedResult <= s_shiftResult;
      3'b011  : s_selectedResult <= s_bitFinderResult;
      3'b100  : s_selectedResult <= (isSpr == 2'b11) ? sprData : (isSpr == 2'b10) ? s_operantB : returnAddress;
      3'b101  : s_selectedResult <= s_dividerResult;
      3'b110  : s_selectedResult <= s_multResult;
      default : s_selectedResult <= {32{1'b0}};
    endcase      
endmodule
