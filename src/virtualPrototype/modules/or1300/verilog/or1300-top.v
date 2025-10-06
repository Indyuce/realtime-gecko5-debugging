module or1300Top #( parameter [2:0] processorId = 1,
                    parameter [2:0] NumberOfProcessors = 1,
                    parameter nrOfBreakpoints = 8,
                    parameter ReferenceClockFrequencyInHz = 12000000 )
                  ( input wire         clock,
                                       referenceClock,
                                       reset,
                                       pllReset,
                    input wire [31:0]  irqVector,
                    output wire        performSoftReset,

                    // Here the custom instruction interface is defined
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
                    
                    // Here the interface to the scratchpad memory is defined
                    output wire [31:0] dataToSpm,
                    input wire [31:0]  dataFromSpm,
                    output wire [17:0] spmAddress,
                    output wire [3:0]  spmByteEnables,
                    output wire        spmChipSelect,
                    output wire        spmWriteEnable,

                    // here the multi-processor interface is defined
                    input wire         cpuEnabled, // was do_jump
                                       profilingActive,
                                       busIdle,
                                       snoopableBurst,
                    output wire        myBarrierValue,
                    input wire [7:0]   barrierValues,
                    input wire [31:0]  jumpAddressIn,
                                       stackTopPointer,
                    input wire [15:0]  cacheConfiguration,
                    input wire [5:0]   memoryDistanceIn,
                    output wire [5:0]  memoryDistanceOut,
                    output wire [31:0] dataOutReg, // replaces status_out and jump_address_out
                    output wire [2:0]  selectOutReg, // replaces jump_address_index
                    output wire        weStatusOut,
                                       weJumpAddress,
                                       weCacheConfig,
                                       weStackTop,
                                       softBios,

                    // here the or1200 external debug interface is defined
                    input wire         dbg_stall_i,  // External Stall Input
                                       dbg_ewt_i,    // External Watchpoint Trigger Input
                    output wire [3:0]  dbg_lss_o,    // External Load/Store Unit Status
                    output wire [1:0]  dbg_is_o,     // External Insn Fetch Status
                    output wire [10:0] dbg_wp_o,     // Watchpoints Outputs
                    output wire        dbg_bp_o,     // Breakpoint Output
                    input wire         dbg_stb_i,    // External Address/Data Strobe
                                       dbg_we_i,     // External Write Enable
                    input wire [15:0]  dbg_adr_i,    // External Address Input
                    input wire [31:0]  dbg_dat_i,    // External Data Input
                    output wire [31:0] dbg_dat_o,    // External Data Output
                    output wire        dbg_ack_o,    // External Data Acknowledge (not WB compatible)

                    // Here the bus interface is defined
                    output wire        icacheRequestBus,
                                       dcacheRequestBus,
                    input wire         icacheBusAccessGranted,
                                       dcacheBusAccessGranted,
                                       busErrorIn,
                    output wire        beginTransactionOut,
                    input wire         beginTransactionIn,
                    output wire [31:0] addressDataOut,
                    input wire  [31:0] addressDataIn,
                    output wire        endTransactionOut,
                    input wire         endTransactionIn,
                    output wire [3:0]  byteEnablesOut,
                    output wire        readNotWriteOut,
                    input wire         readNotWriteIn,
                    output wire        dataValidOut,
                    input wire         dataValidIn,
                    input wire         busyIn,
                    output wire        privateDataOut,
                    input wire         privateDataIn,
                    output wire        privateDirtyOut,
                    input wire         privateDirtyIn,
                    output wire [7:0]  burstSizeOut,
                    input wire [7:0]   burstSizeIn);

  wire        s_debugWeSprData, s_debugReSprData;
  wire [31:0] s_debugSprDataOut;
  wire [15:0] s_debugSprSelect;
  wire        s_debugJumpPending;
  wire [29:0] s_debugJumpAddress;

  /*
   *
   * Fetch stage
   *
   */
  wire s_icacheBeginTransactionOut, s_stall, s_ebuFlush, s_flushIcache, s_icacheEnabled;
  wire s_ebuLoadPc, s_idecJump, s_icacheInsertedNop, s_icacheInstructionAbort, icacheInstructionResetFilter, s_icacheInsertedNopProf;
  wire [31:0] s_icacheAddressDataOut, s_icacheReturnAddress, s_icacheInstruction, s_icacheInstructionAddress;
  wire [31:0] s_SupervisionRegister, s_instructionFetchEa;
  wire [29:0] s_ebuPcLoadValue, s_exeJumpRegister;
  wire [7:0] s_icacheBurstSizeOut;
  wire [3:0] s_icacheByteEnablesOut;
  wire [1:0] s_icacheReplacementPolicy, s_icacheSize, s_icacheNumberOfWays;
  wire s_icacheReadNotWriteOut, s_instructionFetch, s_icacheMiss, s_icacheMissActive, s_icacheFlushActive, s_cacheInsertedNop;
  
  icache theIcache ( .clock(clock),
                     .reset(reset),
                     .requestBus(icacheRequestBus),
                     .busAccessGranted(icacheBusAccessGranted),
                     .busErrorIn(busErrorIn),
                     .beginTransactionOut(s_icacheBeginTransactionOut),
                     .addressDataOut(s_icacheAddressDataOut),
                     .addressDataIn(addressDataIn),
                     .endTransactionIn(endTransactionIn),
                     .byteEnablesOut(s_icacheByteEnablesOut),
                     .readNotWriteOut(s_icacheReadNotWriteOut),
                     .dataValidIn(dataValidIn),
                     .busyIn(busyIn),
                     .burstSizeOut(s_icacheBurstSizeOut),
                     .instructionFetch(s_instructionFetch),
                     .cacheMiss(s_icacheMiss),
                     .cacheMissActive(s_icacheMissActive),
                     .cacheFlushActive(s_icacheFlushActive),
                     .cacheInsertedNop(s_icacheInsertedNopProf),
                     .returnAddress(s_icacheReturnAddress),
                     .stall(s_stall),
                     .flushPipe(s_ebuFlush),
                     .instructionFetchEa(s_instructionFetchEa),
                     .flushCache(s_flushIcache),
                     .replacementPolicy(s_icacheReplacementPolicy),
                     .cacheSize(s_icacheSize),
                     .numberOfWays(s_icacheNumberOfWays),
                     .cacheEnabled(s_icacheEnabled),
                     .loadPc(s_ebuLoadPc),
                     .jump(s_idecJump),
                     .pcLoadValue(s_ebuPcLoadValue),
                     .jumpTarget(s_exeJumpRegister),
                     .instruction(s_icacheInstruction),
                     .instructionAddress(s_icacheInstructionAddress),
                     .insertedNop(s_icacheInsertedNop),
                     .instructionAbort(s_icacheInstructionAbort),
                     .instructionResetFilter(icacheInstructionResetFilter) );
  
  /*
   *
   * Decode stage
   *
   */
  wire s_idecUseForwardedOperantA, s_idecUseForwardedOperantB, s_idecUseForwardedStoreData, s_idecEbuIsDelaySlotIsn, s_dcacheRegisterWe;
  wire [3:0] s_rfCid;
  wire [8:0] s_idecLookupOperantAAddr, s_idecLookupOperantBAddr, s_dcacheRegisterAddress;
  wire [31:0] s_rfOperantA, s_rfOperantB, s_dcacheDataToCore;
  wire [31:0] s_idecForwardedOperantA, s_idecForwardedOperantB, s_idecForwardedStoreData;
  wire [31:0] s_exeOperantA, s_exeOperantB, s_exeInstructionAddress, s_exestoreData, s_idIr;
  wire [4:0] s_exeOperantAAddr, s_exeOperantBAddr, s_exeStoreAddr;
  wire [8:0] s_exeDestination;
  wire s_exeWeDestination, s_exeIsJump, s_exeValidInstruction, s_exeActiveInstruction, s_exeCustom, s_exeInstructionAbort, s_exeFastFlag;
  wire s_exeIsRfe, s_exeSystemCall, s_exeTrap, s_exeDivide, s_exeMultiply, s_exeUpdateCarry, s_exeUpdateOverflow, s_exeUpdateFlag;
  wire [1:0] s_exeIsSpr, s_exeSyncCommand;
  wire [2:0] s_exeExeControl, s_exeResultSelection, s_exeStore, s_exeLoad, s_IdIsStore;
  wire [3:0] s_exeCompareCntrl;
  wire [15:0] s_exeSprOrMask, s_exeImediateValue;
  wire s_branchPenalty, s_idUseImmediate, s_executingBranch;
  
  instructionDecoder decoder ( .clock(clock),
                               .reset(reset),
                               .stall(s_stall),
                               .flush(s_ebuFlush),
                               .executingBranch(s_executingBranch),
                               .ir(s_icacheInstruction),
                               .pc(s_icacheInstructionAddress),
                               .resetFilterIn(icacheInstructionResetFilter),
                               .abort(s_icacheInstructionAbort),
                               .insertedNop(s_icacheInsertedNop),
                               .jump(s_idecJump),
                               .cid(s_rfCid),
                               .lookupOperantAAddr(s_idecLookupOperantAAddr),
                               .lookupOperantBAddr(s_idecLookupOperantBAddr),
                               .rfOperantA(s_rfOperantA),
                               .rfOperantB(s_rfOperantB),
                               .forwardedOperantA(s_idecForwardedOperantA),
                               .forwardedOperantB(s_idecForwardedOperantB),
                               .forwardedStoreData(s_idecForwardedStoreData),
                               .useForwardedOperantA(s_idecUseForwardedOperantA),
                               .useForwardedOperantB(s_idecUseForwardedOperantB),
                               .useForwardedStoreData(s_idecUseForwardedStoreData),
                               .useImmediate(s_idUseImmediate),
                               .isStore(s_IdIsStore),
                               .ebuIsDelaySlotIsn(s_idecEbuIsDelaySlotIsn),
                               .dcacheWe(s_dcacheRegisterWe),
                               .dcacheTarget(s_dcacheRegisterAddress),
                               .dcacheDataIn(s_dcacheDataToCore),
                               .exeOperantA(s_exeOperantA),
                               .exeOperantB(s_exeOperantB),
                               .instructionAddress(s_exeInstructionAddress),
                               .exestoreData(s_exestoreData),
                               .exeIr(s_idIr),
                               .exeOperantAAddr(s_exeOperantAAddr),
                               .exeOperantBAddr(s_exeOperantBAddr),
                               .exeStoreAddr(s_exeStoreAddr),
                               .exeDestination(s_exeDestination),
                               .exeWeDestination(s_exeWeDestination),
                               .exeIsJump(s_exeIsJump),
                               .exeValidInstruction(s_exeValidInstruction),
                               .exeActiveInstruction(s_exeActiveInstruction),
                               .exeCustom(s_exeCustom),
                               .exeInstructionAbort(s_exeInstructionAbort),
                               .exeIsRfe(s_exeIsRfe),
                               .exeSystemCall(s_exeSystemCall),
                               .exeTrap(s_exeTrap),
                               .exeDivide(s_exeDivide),
                               .exeMultiply(s_exeMultiply),
                               .exeUpdateCarry(s_exeUpdateCarry),
                               .exeUpdateOverflow(s_exeUpdateOverflow),
                               .exeUpdateFlag(s_exeUpdateFlag),
                               .exeIsSpr(s_exeIsSpr),
                               .exeSyncCommand(s_exeSyncCommand),
                               .exeExeControl(s_exeExeControl),
                               .exeResultSelection(s_exeResultSelection),
                               .exeStore(s_exeStore),
                               .exeLoad(s_exeLoad),
                               .exeCompareCntrl(s_exeCompareCntrl),
                               .exeSprOrMask(s_exeSprOrMask),
                               .exeImediateValue(s_exeImediateValue),
                               .fastFlag(s_exeFastFlag),
                               .branchPenalty(s_branchPenalty));

  /*
   *
   * Execution stage
   *
   */
  wire s_dcacheStall, s_dividerStall, s_multiplierStall, s_custInstrStall;
  wire s_exeCarryIn, s_exeOverflowIn, s_exeFlagIn, s_exeResetLoad;
  wire [31:0] s_rfSprData, s_exeMemoryAddress, s_exeWriteData, s_exePc;
  wire [15:0] s_exeSprIndex, s_exeWriteSprIndex;
  wire [31:0] s_exeMacLo, s_exeMacHi, s_exeIr, s_exeDataOut;
  wire [31:0] s_exeForwardedOperantA, s_exeForwardedOperantB, s_exeForwardedStoreData;
  wire        s_exeUseForwardedOpA, s_exeUseForwardedOpB, s_exeUseForwardedStoreData;
  wire [2:0]  s_exeMemoryLoad, s_exeMemoryStore;
  wire [8:0]  s_exeLoadTarget;
  wire [7:0]  s_exeMemoryCompareValue;
  wire [4:0]  s_exeWriteAddress;
  wire [1:0]  s_exeSyncCommandOut;
  wire        s_exeWriteEnable, s_exeWriteSpr, s_exeInstructionAbortOut, s_exeSystemCallOut;
  wire        s_exeAllignmentError, s_exeInvalidInstruction, s_exeIsRfeOut, s_exeTrapOut;
  wire        s_exeDivZeroException, s_exeCarryOut, s_exeWeCarry, s_exeIsJumpOut, s_exeActiveInstructionOut;
  wire        s_exeOverflowOut, s_exeWeOverflow, s_exeFlagOut, s_exeWeFlag, s_debugStall;

  
  assign s_stall = s_dividerStall | s_multiplierStall | s_custInstrStall | s_dcacheStall | s_debugStall;

  executionUnit execute ( .clock(clock),
                          .reset(reset),
                          .stall(s_stall),
                          .flush(s_ebuFlush),
                          .dividerStallIn(s_dcacheStall),
                          .multiplierStallIn(s_dcacheStall),
                          .custInstrStallIn(s_dcacheStall),
                          .dividerStallOut(s_dividerStall),
                          .multiplierStallOut(s_multiplierStall),
                          .custInstrStallOut(s_custInstrStall),
                          .operantA(s_exeOperantA),
                          .operantB(s_exeOperantB),
                          .storeDataIn(s_exestoreData),
                          .operantAAddr(s_exeOperantAAddr),
                          .operantBAddr(s_exeOperantBAddr),
                          .destination(s_exeDestination),
                          .immValue(s_exeImediateValue),
                          .weDestination(s_exeWeDestination),
                          .custom(s_exeCustom),
                          .validInstruction(s_exeValidInstruction),
                          .activeInstructionIn(s_exeActiveInstruction),
                          .instructionAbortIn(s_exeInstructionAbort),
                          .instructionAddress(s_exeInstructionAddress),
                          .sprData(s_rfSprData),
                          .sprIndex(s_exeSprIndex),
                          .isSpr(s_exeIsSpr),
                          .sprOrMask(s_exeSprOrMask),
                          .isJumpIn(s_exeIsJump),
                          .isRfeIn(s_exeIsRfe),
                          .systemCallIn(s_exeSystemCall),
                          .trapIn(s_exeTrap),
                          .divide(s_exeDivide),
                          .multiply(s_exeMultiply),
                          .carryIn(s_exeCarryIn),
                          .updateCarry(s_exeUpdateCarry),
                          .overflowIn(s_exeOverflowIn),
                          .updateOverflow(s_exeUpdateOverflow),
                          .flagIn(s_exeFlagIn),
                          .updateFlag(s_exeUpdateFlag),
                          .syncCommandIn(s_exeSyncCommand),
                          .compareCntrl(s_exeCompareCntrl),
                          .exeControl(s_exeExeControl),
                          .resultSelection(s_exeResultSelection),
                          .store(s_exeStore),
                          .load(s_exeLoad),
                          .supervisionRegister(s_SupervisionRegister),
                          .fastFlag(s_exeFastFlag),
                          .multMacLo(s_exeMacLo),
                          .multMacHi(s_exeMacHi),
                          .debugSprSelect(s_debugSprSelect),
                          .debugWeSprData(s_debugWeSprData),
                          .debugReSprData(s_debugReSprData),
                          .debugSprDataOut(s_debugSprDataOut),
                          .returnAddress(s_icacheReturnAddress),
                          .customInstructionDataA(customInstructionDataA),
                          .customInstructionDataB(customInstructionDataB),
                          .customInstructionN(customInstructionN),
                          .customInstructionReadRa(customInstructionReadRa),
                          .customInstructionReadRb(customInstructionReadRb),
                          .customInstructionWriteRc(customInstructionWriteRc),
                          .customInstructionA(customInstructionA),
                          .customInstructionB(customInstructionB),
                          .customInstructionC(customInstructionC),
                          .customInstructionStart(customInstructionStart),
                          .customInstructionClockEnable(customInstructionClockEnable),
                          .customInstructionResult(customInstructionResult),
                          .customInstructionDone(customInstructionDone),
                          .irIn(s_idIr),
                          .irOut(s_exeIr),
                          .forwardedOperantA(s_exeForwardedOperantA),
                          .forwardedOperantB(s_exeForwardedOperantB),
                          .forwardedStoreData(s_exeForwardedStoreData),
                          .useForwardedOpA(s_exeUseForwardedOpA),
                          .useForwardedOpB(s_exeUseForwardedOpB),
                          .useForwardedStoreData(s_exeUseForwardedStoreData),
                          .resetLoad(s_exeResetLoad),
                          .dataOut(s_exeDataOut),
                          .memoryAddress(s_exeMemoryAddress),
                          .memoryLoad(s_exeMemoryLoad),
                          .memoryStore(s_exeMemoryStore),
                          .loadTarget(s_exeLoadTarget),
                          .memoryCompareValue(s_exeMemoryCompareValue),
                          .writeAddress(s_exeWriteAddress),
                          .writeData(s_exeWriteData),
                          .pc(s_exePc),
                          .writeSprIndex(s_exeWriteSprIndex),
                          .jumpRegister(s_exeJumpRegister),
                          .syncCommand(s_exeSyncCommandOut),
                          .isJump(s_exeIsJumpOut),
                          .isRfe(s_exeIsRfeOut),
                          .writeEnable(s_exeWriteEnable),
                          .writeSpr(s_exeWriteSpr),
                          .systemCall(s_exeSystemCallOut),
                          .trap(s_exeTrapOut),
                          .allignmentError(s_exeAllignmentError),
                          .instructionAbort(s_exeInstructionAbortOut),
                          .invalidInstruction(s_exeInvalidInstruction),
                          .activeInstruction(s_exeActiveInstructionOut),
                          .divZeroException(s_exeDivZeroException),
                          .carryOut(s_exeCarryOut),
                          .weCarry(s_exeWeCarry),
                          .overflowOut(s_exeOverflowOut),
                          .weOverflow(s_exeWeOverflow),
                          .flagOut(s_exeFlagOut),
                          .weFlag(s_exeWeFlag) );

  /*
   *
   * Memory stage
   *
   */
  
  wire        s_flushDcache, s_dcacheBeginTransactionOut, s_dcacheReadNotWriteOut, s_ebuMemorySync;
  wire [31:0] s_dcacheAddressDataOut, s_dcacheAbortAddress, s_dcacheAbortMemoryAddress;
  wire [3:0]  s_dcacheByteEnablesOut;
  wire [7:0]  s_dcacheBurstSizeOut;
  wire [1:0]  s_dcacheReplacementPolicy, s_dcacheNumberOfWays, s_dcacheCacheSize;
  wire        s_dcacheWriteBackPolicy, s_dcacheCoherenceEnabled, s_dcacheMesiEnabled, s_dcacheSnarfingEnabled;
  wire        s_dcacheDataAbort, s_dcacheEnabled;
  wire        s_cachedWrite, s_cachedRead, s_uncachedWrite, s_uncachedRead, s_swapInstruction;
  wire        s_casInstruction, s_cacheMiss, s_cacheWriteBack, s_dataStall, s_writeStall;
  wire        s_processorStall, s_cacheStall, s_writeThrough, s_invalidate;
  
  dCache datacache ( .clock(clock),
                     .reset(reset),
                     .flushCache(s_flushDcache),
                     .pipelineStall(s_stall),
                     .requestBus(dcacheRequestBus),
                     .busAccessGranted(dcacheBusAccessGranted),
                     .busErrorIn(busErrorIn),
                     .beginTransactionOut(s_dcacheBeginTransactionOut),
                     .beginTransactionIn(beginTransactionIn),
                     .addressDataOut(s_dcacheAddressDataOut),
                     .addressDataIn(addressDataIn),
                     .endTransactionOut(endTransactionOut),
                     .endTransactionIn(endTransactionIn),
                     .byteEnablesOut(s_dcacheByteEnablesOut),
                     .readNotWriteOut(s_dcacheReadNotWriteOut),
                     .readNotWriteIn(readNotWriteIn),
                     .dataValidOut(dataValidOut),
                     .dataValidIn(dataValidIn),
                     .busyIn(busyIn),
                     .privateDataOut(privateDataOut),
                     .privateDataIn(privateDataIn),
                     .privateDirtyOut(privateDirtyOut),
                     .privateDirtyIn(privateDirtyIn),
                     .burstSizeOut(s_dcacheBurstSizeOut),
                     .burstSizeIn(burstSizeIn),
                     .dataToSpm(dataToSpm),
                     .dataFromSpm(dataFromSpm),
                     .spmAddress(spmAddress),
                     .spmByteEnables(spmByteEnables),
                     .spmChipSelect(spmChipSelect),
                     .spmWriteEnable(spmWriteEnable),
                     .cachedWrite(s_cachedWrite),
                     .cachedRead(s_cachedRead),
                     .uncachedWrite(s_uncachedWrite),
                     .uncachedRead(s_uncachedRead),
                     .swapInstruction(s_swapInstruction),
                     .casInstruction(s_casInstruction),
                     .cacheMiss(s_cacheMiss),
                     .cacheWriteBack(s_cacheWriteBack),
                     .dataStall(s_dataStall),
                     .writeStall(s_writeStall),
                     .processorStall(s_processorStall),
                     .cacheStall(s_cacheStall),
                     .writeThrough(s_writeThrough),
                     .invalidate(s_invalidate),
                     .stallCpu(s_dcacheStall),
                     .enableCache(s_dcacheEnabled),
                     .memorySync(s_ebuMemorySync),
                     .replacementPolicy(s_dcacheReplacementPolicy),
                     .numberOfWays(s_dcacheNumberOfWays),
                     .cacheSize(s_dcacheCacheSize),
                     .writeBackPolicy(s_dcacheWriteBackPolicy),
                     .coherenceEnabled(s_dcacheCoherenceEnabled),
                     .mesiEnabled(s_dcacheMesiEnabled),
                     .snarfingEnabled(s_dcacheSnarfingEnabled),
                     .instructionAddress(s_exePc[31:2]),
                     .dataFromCore(s_exeDataOut),
                     .memoryAddress(s_exeMemoryAddress),
                     .memoryStore(s_exeMemoryStore),
                     .memoryLoad(s_exeMemoryLoad),
                     .memoryCompareValue(s_exeMemoryCompareValue),
                     .loadTarget(s_exeLoadTarget),
                     .wbWriteEnable(s_exeWriteEnable),
                     .wbRegisterAddress(s_exeWriteAddress),
                     .rfOperantAAddress(s_exeOperantAAddr),
                     .rfOperantBAddress(s_exeOperantBAddr),
                     .rfStoreAddress(s_exeStoreAddr),
                     .rfWriteDestination(s_exeWeDestination),
                     .rfDestination(s_exeDestination),
                     .cid(s_SupervisionRegister[31:28]),
                     .resetExeLoad(s_exeResetLoad),
                     .dataAbort(s_dcacheDataAbort),
                     .abortAddress(s_dcacheAbortAddress),
                     .abortMemoryAddress(s_dcacheAbortMemoryAddress),
                     .dataToCore(s_dcacheDataToCore),
                     .registerAddress(s_dcacheRegisterAddress),
                     .registerWe(s_dcacheRegisterWe) );

  /*
   *
   * Write back stage
   *
   */
   wire [31:0] s_profilingData, s_ebuInstruction, s_effectiveAddressRegister, s_exceptionPcRegister, s_debugData;
   wire [31:0] s_eearNext, s_epcrNext;
   wire [27:0] s_BusErrorVector, s_TickTimerVector, s_AllignmentVector, s_RangeVector;
   wire [27:0] s_IllegalInstructionVector , s_SystemCallVector, s_TrapVector, s_InterruptVector, s_BreakPointVector;
   wire [13:0] s_exceptionReason;
   wire        s_tickTimerIrq, s_irq, s_exceptionTaken, s_exceptionFinished;
   
   registerFile #( .processorId(processorId),
                   .NumberOfProcessors(NumberOfProcessors),
                   .nrOfBreakpoints(nrOfBreakpoints),
                   .ReferenceClockFrequencyInHz(ReferenceClockFrequencyInHz)) registers
                 ( .clock(clock),
                   .referenceClock(referenceClock),
                   .reset(reset),
                   .pllReset(pllReset),
                   .stall(s_stall),
                   .performSoftReset(performSoftReset),
                   .profilingData(s_profilingData),
                   .debugData(s_debugData),
                   .dcacheWe(s_dcacheRegisterWe),
                   .dcacheTarget(s_dcacheRegisterAddress),
                   .dcacheDataIn(s_dcacheDataToCore),
                   .dcacheEnabled(s_dcacheEnabled),
                   .dcacheFlush(s_flushDcache),
                   .dcacheWriteBackEnabled(s_dcacheWriteBackPolicy),
                   .dcacheSnarfingEnabled(s_dcacheSnarfingEnabled),
                   .dcacheMesiEnabled(s_dcacheMesiEnabled),
                   .dcacheCoherenceEnabled(s_dcacheCoherenceEnabled),
                   .dcacheSize(s_dcacheCacheSize),
                   .dcacheReplacementPolicy(s_dcacheReplacementPolicy),
                   .dcacheNumberOfWays(s_dcacheNumberOfWays),
                   .icacheEnabled(s_icacheEnabled),
                   .icacheFlush(s_flushIcache),
                   .icacheSize(s_icacheSize),
                   .icacheReplacementPolicy(s_icacheReplacementPolicy),
                   .icacheNumberOfWays(s_icacheNumberOfWays),
                   .instructionAddress(s_icacheInstructionAddress),
                   .writeAddress(s_exeWriteAddress),
                   .writeData(s_exeWriteData),
                   .writeEnable(s_exeWriteEnable),
                   .writeSpr(s_exeWriteSpr),
                   .writeSprIndex(s_exeWriteSprIndex),
                   .exceptionReason(s_exceptionReason),
                   .exeFlag(s_exeFlagIn),
                   .exeCarry(s_exeCarryIn),
                   .exeOverflow(s_exeOverflowIn),
                   .exeWeFlag(s_exeWeFlag),
                   .exeWeCarry(s_exeWeCarry),
                   .exeWeOverflow(s_exeWeOverflow),
                   .exeFlagIn(s_exeFlagOut),
                   .exeCarryIn(s_exeCarryOut),
                   .exeOverflowIn(s_exeOverflowOut),
                   .exeSprIndex(s_exeSprIndex),
                   .multMacLo(s_exeMacLo),
                   .multMacHi(s_exeMacHi),
                   .exeSprData(s_rfSprData),
                   .ebuIr(s_ebuInstruction),
                   .exceptionTaken(s_exceptionTaken),
                   .exceptionFinished(s_exceptionFinished),
                   .eearNext(s_eearNext),
                   .epcrNext(s_epcrNext),
                   .BusErrorVector(s_BusErrorVector),
                   .TickTimerVector(s_TickTimerVector),
                   .AllignmentVector(s_AllignmentVector),
                   .RangeVector(s_RangeVector),
                   .IllegalInstructionVector(s_IllegalInstructionVector),
                   .SystemCallVector(s_SystemCallVector),
                   .TrapVector(s_TrapVector),
                   .InterruptVector(s_InterruptVector),
                   .BreakPointVector(s_BreakPointVector),
                   .cid(s_rfCid),
                   .isDelaySlotIsn(s_idecEbuIsDelaySlotIsn),
                   .lookupOperantAAddr(s_idecLookupOperantAAddr),
                   .lookupOperantBAddr(s_idecLookupOperantBAddr),
                   .operantA(s_rfOperantA),
                   .operantB(s_rfOperantB),
                   .tickTimerIrq(s_tickTimerIrq),
                   .irq(s_irq),
                   .irqVector(irqVector),
                   .superVisionRegister(s_SupervisionRegister),
                   .effectiveAddressRegister(s_effectiveAddressRegister), // TODO: connect!
                   .exceptionPcRegister(s_exceptionPcRegister),
                   .cpuEnabled(cpuEnabled), // was do_jump
                   .softBios(softBios),
                   .myBarrierValue(myBarrierValue),
                   .barrierValues(barrierValues),
                   .jumpAddressIn(jumpAddressIn),
                   .stackTopPointer(stackTopPointer),
                   .cacheConfiguration(cacheConfiguration),
                   .memoryDistanceIn(memoryDistanceIn),
                   .memoryDistanceOut(memoryDistanceOut),
                   .dataOutReg(dataOutReg), // replaces status_out and jump_address_out
                   .selectOutReg(selectOutReg), // replaces jump_address_index
                   .weStatusOut(weStatusOut),
                   .weJumpAddress(weJumpAddress),
                   .weCacheConfig(weCacheConfig),
                   .weStackTop(weStackTop));

  /*
   *
   * Forwarding
   *
   */
  forwardUnit forward ( .clock(clock),
                        .stall(s_stall),
                        .flush(s_ebuFlush),
                        .exeForwardOperantA(s_exeForwardedOperantA),
                        .exeForwardOperantB(s_exeForwardedOperantB),
                        .exeForwardStoreData(s_exeForwardedStoreData),
                        .exeUseForwardedOpA(s_exeUseForwardedOpA),
                        .exeUseForwardedOpB(s_exeUseForwardedOpB),
                        .exeUseForwardedStoreData(s_exeUseForwardedStoreData),
                        .rfForwardedOperantA(s_idecForwardedOperantA),
                        .rfForwardedOperantB(s_idecForwardedOperantB),
                        .rfForwardedStoreData(s_idecForwardedStoreData),
                        .rfUseForwardedOpA(s_idecUseForwardedOperantA),
                        .rfUseForwardedOpB(s_idecUseForwardedOperantB),
                        .rfUseForwardedStoreData(s_idecUseForwardedStoreData),
                        .idOperantAAddr(s_idecLookupOperantAAddr[4:0]),
                        .idOperantBAddr(s_idecLookupOperantBAddr[4:0]),
                        .idUseImmediate(s_idUseImmediate),
                        .idIsJump(s_idecJump),
                        .idStore(s_IdIsStore),
                        .writeAddress(s_exeWriteAddress),
                        .writeEnable(s_exeWriteEnable),
                        .rfDestination(s_exeDestination[4:0]),
                        .rfWeDestination(s_exeWeDestination),
                        .writeData(s_exeWriteData),
                        .dcacheRegisterAddress(s_dcacheRegisterAddress),
                        .dcacheRegisterWe(s_dcacheRegisterWe),
                        .dcacheRegisterData(s_dcacheDataToCore),
                        .cid(s_rfCid),
                        .rfOperantAAddr(s_exeOperantAAddr),
                        .rfOperantBAddr(s_exeOperantBAddr),
                        .rfStoreAddr(s_exeStoreAddr) );

  /*
   *
   * Branching
   *
   */
  wire s_debugIrq;
  exceptionBranchUnit branch ( .clock(clock),
                               .reset(reset),
                               .irq(s_irq),
                               .tickTimerIrq(s_tickTimerIrq),
                               .stall(s_stall),
                               .flushPipe(s_ebuFlush),
                               .irIn(s_exeIr),
                               .exceptionIr(s_ebuInstruction),
                               .isJump(s_exeIsJumpOut),
                               .isRfe(s_exeIsRfeOut),
                               .systemCall(s_exeSystemCallOut),
                               .trap(s_exeTrapOut),
                               .allignmentError(s_exeAllignmentError),
                               .instructionAbort(s_exeInstructionAbortOut),
                               .invalidInstruction(s_exeInvalidInstruction),
                               .activeInstruction(s_exeActiveInstructionOut),
                               .divZeroException(s_exeDivZeroException),
                               .overflow(s_exeOverflowOut),
                               .weOverflow(s_exeWeOverflow),
                               .writeSpr(s_exeWriteSpr),
                               .pc(s_exePc),
                               .nextPc(s_exeInstructionAddress),
                               .syncCommand(s_exeSyncCommandOut),
                               .supervisionRegister(s_SupervisionRegister),
                               .exceptionPcRegister(s_exceptionPcRegister),
                               .custom(s_exeCustom),
                               .rfActiveInstruction(s_exeActiveInstruction),
                               .rfIsDelaySlotIsn(s_idecEbuIsDelaySlotIsn),
                               .debugIrq(s_debugIrq),
                               .debugJumpPending(s_debugJumpPending),
                               .debugJumpAddress(s_debugJumpAddress),
                               .exceptionReason(s_exceptionReason),
                               .epcrNext(s_epcrNext),
                               .eearNext(s_eearNext),
                               .exceptionTaken(s_exceptionTaken),
                               .exceptionFinished(s_exceptionFinished),
                               .BusErrorVector(s_BusErrorVector),
                               .TickTimerVector(s_TickTimerVector),
                               .AllignmentVector(s_AllignmentVector),
                               .RangeVector(s_RangeVector),
                               .IllegalInstructionVector(s_IllegalInstructionVector),
                               .SystemCallVector(s_SystemCallVector),
                               .TrapVector(s_TrapVector),
                               .InterruptVector(s_InterruptVector),
                               .BreakPointVector(s_BreakPointVector),
                               .dataAbort(s_dcacheDataAbort),
                               .abortAddress(s_dcacheAbortAddress),
                               .abortMemoryAddress(s_dcacheAbortMemoryAddress),
                               .loadPc(s_ebuLoadPc),
                               .memorySync(s_ebuMemorySync),
                               .pcLoadValue(s_ebuPcLoadValue));

  /*
   *
   * profiling
   *
   */
  wire s_comittedInstruction = s_exeActiveInstruction & ~s_stall;
  profilingModule profile ( .reset(reset),
                            .clock(clock),
                            .stall(s_stall),
                            .weSpsr(s_exeWriteSpr),
                            .profilingActive(profilingActive),
                            .spsrWriteIndex(s_exeWriteSprIndex),
                            .dataFromCore(s_exeWriteData),
                            .profilingInstructionFetch(s_instructionFetch),
                            .profilingICacheMiss(s_icacheMiss),
                            .profilingICacheMissActive(s_icacheMissActive),
                            .profilingICacheFlushActive(s_icacheFlushActive),
                            .profilingICacheInsertedNop(s_icacheInsertedNopProf),
                            .profilingDCacheUncachedWrite(s_uncachedWrite),
                            .profilingDCacheUncachedRead(s_uncachedRead),
                            .profilingDCacheCachedWrite(s_cachedWrite),
                            .profilingDCacheCachedRead(s_cachedRead),
                            .profilingDCacheSwap(s_swapInstruction),
                            .profilingDCacheCas(s_casInstruction),
                            .profilingDCacheMiss(s_cacheMiss),
                            .profilingDCacheWriteBack(s_cacheWriteBack),
                            .profilingDCacheDataStall(s_dataStall),
                            .profilingDCacheWriteStall(s_writeStall),
                            .profilingDCacheProcessorStall(s_processorStall),
                            .profilingDCacheStall(s_cacheStall),
                            .profilingDCacheWriteThrough(s_writeThrough),
                            .profilingDCacheInvalidate(s_invalidate),
                            .profilingBranchPenalty(s_branchPenalty),
                            .profilingComittedInstruction(s_comittedInstruction),
                            .profilingStall(s_stall),
                            .busIdle(busIdle),
                            .snoopableBurst(snoopableBurst),
                            .spsrReadIndex(s_exeSprIndex),
                            .dataToCore(s_profilingData) );

  /*
   *
   * debuging
   *
   */
  debugUnit #(.nrOfBreakpoints(nrOfBreakpoints)) debug 
                  ( .clock(clock),
                    .reset(pllReset),
                    .stallIn(s_stall),
                    .isRfe(s_exeIsRfeOut),
                    .ebuIsDelaySlotIsn(s_idecEbuIsDelaySlotIsn),
                    .exeActiveInstruction(s_exeActiveInstruction),
                    .exeExecutedInstruction(s_exeActiveInstructionOut),
                    .executingBranch(s_executingBranch),
                    .memoryStore(s_exeMemoryStore),
                    .memoryLoad(s_exeMemoryLoad),
                    .debugIrq(s_debugIrq),
                    .stallOut(s_debugStall),
                    .exceptionTaken(s_exceptionTaken),
                    .exceptionReason(s_exceptionReason),
                    .exeSprIndex(s_exeSprIndex),
                    .writeSprIndex(s_exeWriteSprIndex),
                    .writeData(s_exeWriteData),
                    .exeIrIn(s_exeIr),
                    .exePcIn(s_exePc),
                    .writeSpr(s_exeWriteSpr),
                    .supervisionMode(s_SupervisionRegister[0]),
                    .readSprData(s_debugData),
                    .instructionFetchEa(s_instructionFetchEa),
                    .memoryAddress(s_exeMemoryAddress),
                    .storeData(s_exeDataOut),
                    .loadData(s_dcacheDataToCore),
                    .debugSprDataIn(s_rfSprData),
                    .debugWeSprData(s_debugWeSprData),
                    .debugReSprData(s_debugReSprData),
                    .debugSprDataOut(s_debugSprDataOut),
                    .debugSprSelect(s_debugSprSelect),
                    .debugJumpPending(s_debugJumpPending),
                    .debugJumpAddress(s_debugJumpAddress),
                    .dbg_stall_i(dbg_stall_i),
                    .dbg_ewt_i(dbg_ewt_i),
                    .dbg_lss_o(dbg_lss_o),
                    .dbg_is_o(dbg_is_o),
                    .dbg_wp_o(dbg_wp_o),
                    .dbg_bp_o(dbg_bp_o),
                    .dbg_stb_i(dbg_stb_i),
                    .dbg_we_i(dbg_we_i),
                    .dbg_adr_i(dbg_adr_i),
                    .dbg_dat_i(dbg_dat_i),
                    .dbg_dat_o(dbg_dat_o),
                    .dbg_ack_o(dbg_ack_o));
  /*
   *
   * Here the common signals are defined
   *
   */
  assign beginTransactionOut = s_icacheBeginTransactionOut | s_dcacheBeginTransactionOut;
  assign addressDataOut      = s_icacheAddressDataOut | s_dcacheAddressDataOut;
  assign byteEnablesOut      = s_icacheByteEnablesOut | s_dcacheByteEnablesOut;
  assign readNotWriteOut     = s_icacheReadNotWriteOut | s_dcacheReadNotWriteOut;
  assign burstSizeOut        = s_icacheBurstSizeOut | s_dcacheBurstSizeOut;
endmodule
