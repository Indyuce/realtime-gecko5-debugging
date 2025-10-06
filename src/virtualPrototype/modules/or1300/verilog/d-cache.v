/*
 * This D-cache is a 2, 4, 8 kbyte coherent cache.
 * It can be configured to use 1,2 or 4 ways.
 * It can be run-time configured to use FIFO,PLRU or LRU replacement
 * It incorporates the load-store unit
 * It provides selectable MSI or MESI coherency protocols
 * It provites a scratchpad memory of up to 1 Mbyte at address 0xC0000000
 *
 * IMPORTANT: The D-cache uses a slightly different memory map than specified in
 *            the or1000 specifications, namely:
 *            0x00000000 - 0x3FFFFFFF -> MESI cache-coherent region
 *            0x40000000 - 0x7FFFFFFF -> Uncacheable region
 *            0x80000000 - 0xBFFFFFFF -> No cache-coherent cached region
 *            0xC0000000 - 0xFFFFFFFF -> Uncacheable region
 *
 * NOTE: The none coherent cache region always uses write-back policy, independent of
 *       the write-back policy specified by the core!
 *
 * The state bits of a cache line:
 * Bit 0 : Valid bit
 * Bit 1 : Shared bit
 * Bit 2 : Dirty bit
 * Bit 3 : Modified bit
 *
 * Overview of cache line states:
 * Invalid   => 0000
 * Valid     => 0001
 * Dirty     => 0101
 * Shared    => 0011
 * Exclusive => 0001
 * Modified  => 1001
 *
 * replacement policy:
 * 00 -> FIFO
 * 01 -> PLRU
 * 1x -> LRU
 *
 * Note: The openrisc is big-endian
 */
module dCache   ( input wire         clock,
                                     reset,
                                     flushCache,
                                     pipelineStall,
                  // Here the bus interface is defined
                  output wire        requestBus,
                  input wire         busAccessGranted,
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
                  output reg         privateDataOut,
                  input wire         privateDataIn,
                  output wire        privateDirtyOut,
                  input wire         privateDirtyIn,
                  output wire [7:0]  burstSizeOut,
                  input wire [7:0]   burstSizeIn,
                  
                  // Here the interface to the scratchpad memory is defined
                  output wire [31:0] dataToSpm,
                  input wire [31:0]  dataFromSpm,
                  output wire [17:0] spmAddress,
                  output wire [3:0]  spmByteEnables,
                  output wire        spmChipSelect,
                  output wire        spmWriteEnable,
                  
                  // Here the profiling signals are defined
                  output reg         cachedWrite,
                                     cachedRead,
                                     uncachedWrite,
                                     uncachedRead,
                                     swapInstruction,
                                     casInstruction,
                                     cacheMiss,
                                     cacheWriteBack,
                                     dataStall,
                                     writeStall,
                                     processorStall,
                                     cacheStall,
                                     writeThrough,
                                     invalidate,
                  
                  // Here the interface to the cpu is defined
                  output wire        stallCpu,
                  input wire         enableCache,
                  input wire         memorySync,
                  input wire [1:0]   replacementPolicy,
                                     numberOfWays,
                                     cacheSize,
                  input wire         writeBackPolicy,
                                     coherenceEnabled,
                                     mesiEnabled,
                                     snarfingEnabled,
                  input wire [29:0]  instructionAddress,
                  input wire [31:0]  dataFromCore,
                                     memoryAddress,
                  input wire [2:0]   memoryStore,
                                     memoryLoad,
                  input wire [7:0]   memoryCompareValue,
                  input wire [8:0]   loadTarget,
                  input wire         wbWriteEnable,
                  input wire [4:0]   wbRegisterAddress,
                  input wire [4:0]   rfOperantAAddress,
                                     rfOperantBAddress,
                                     rfStoreAddress,
                  input wire         rfWriteDestination,
                  input wire [8:0]   rfDestination,
                  input wire [3:0]   cid,
                  output wire        resetExeLoad,
                                     dataAbort,
                  output wire [31:0] abortAddress,
                                     abortMemoryAddress,
                  output reg [31:0]  dataToCore,
                  output wire [8:0]  registerAddress,
                  output wire        registerWe );

  localparam [3:0] STATE_INVALID            = 4'b0000;
  localparam [3:0] STATE_VALID              = 4'b0001;
  localparam [3:0] STATE_DIRTY              = 4'b0101;
  localparam [3:0] STATE_SHARED             = 4'b0011;
  localparam [3:0] STATE_EXCLUSIVE          = 4'b0001;
  localparam [3:0] STATE_MODIFIED           = 4'b1001;
  localparam [3:0] VALID_MASK               = 4'h1;
  localparam [3:0] SHARED_MASK              = 4'h2;
  localparam [3:0] DIRTY_MASK               = 4'h4;
  localparam [3:0] MODIFIED_MASK            = 4'h8;
  
  localparam [1:0] DIRECT_MAPPED            = 2'b00;
  localparam [1:0] TWO_WAY_SET_ASSOCIATIVE  = 2'b01;
  localparam [1:0] FOUR_WAY_SET_ASSOCIATIVE = 2'b10;
  
  localparam [3:0] DIRECT_MAPPED_1K            = 4'b0000;
  localparam [3:0] DIRECT_MAPPED_2K            = 4'b0001;
  localparam [3:0] DIRECT_MAPPED_4K            = 4'b0010;
  localparam [3:0] DIRECT_MAPPED_8K            = 4'b0011;
  localparam [3:0] TWO_WAY_SET_ASSOCIATIVE_1K  = 4'b0100;
  localparam [3:0] TWO_WAY_SET_ASSOCIATIVE_2K  = 4'b0101;
  localparam [3:0] TWO_WAY_SET_ASSOCIATIVE_4K  = 4'b0110;
  localparam [3:0] TWO_WAY_SET_ASSOCIATIVE_8K  = 4'b0111;
  localparam [3:0] FOUR_WAY_SET_ASSOCIATIVE_1K = 4'b1000;
  localparam [3:0] FOUR_WAY_SET_ASSOCIATIVE_2K = 4'b1001;
  localparam [3:0] FOUR_WAY_SET_ASSOCIATIVE_4K = 4'b1010;
  localparam [3:0] FOUR_WAY_SET_ASSOCIATIVE_8K = 4'b1011;
  
  localparam [1:0] SIZE_1K = 2'b00;
  localparam [1:0] SIZE_2K = 2'b01;
  localparam [1:0] SIZE_4K = 2'b10;
  localparam [1:0] SIZE_8K = 2'b11;
  
 
  localparam [1:0] FIFO_REPLACEMENT         = 2'b00;
  localparam [1:0] PLRU_REPLACEMENT         = 2'b01;
  localparam [1:0] LRU_REPLACEMENT          = 2'b10;

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

  localparam [5:0] IDLE             = 6'd0;
  localparam [5:0] REQUEST_THE_BUS  = 6'd1;
  localparam [5:0] INIT_TRANSACTION = 6'd2;
  localparam [5:0] DET_TRANSACTION  = 6'd3;
  localparam [5:0] WAIT_N_BUSY      = 6'd4;
  localparam [5:0] DO_WRITE         = 6'd5;
  localparam [5:0] END_TRANSACTION  = 6'd6;
  localparam [5:0] UPDATE_TAGS      = 6'd7;
  localparam [5:0] RELEASE          = 6'd8;
  localparam [5:0] WAIT_READ_BURST  = 6'd9;
  localparam [5:0] NOP              = 6'd10;
  localparam [5:0] ATOMIC_REQUEST   = 6'd11;
  localparam [5:0] ATOMIC_INIT      = 6'd12;
  localparam [5:0] ATOMIC_WAIT      = 6'd13;
  localparam [5:0] BACKOFF          = 6'd14;
  localparam [5:0] LOOKUP_TAGS      = 6'd15;
  localparam [5:0] STORE_TAGS       = 6'd16;
  localparam [5:0] MARK_SHARED      = 6'd17;
  localparam [5:0] FLUSH_INIT       = 6'd18;
  localparam [5:0] FLUSH_LOOKUP     = 6'd19;
  localparam [5:0] FLUSH_INVALIDATE = 6'd20;
  localparam [5:0] FLUSH_DONE       = 6'd21;

  localparam [4:0] UNCACHEABLE_WRITE     = 5'd0;
  localparam [4:0] UNCACHEABLE_READ      = 5'd1;
  localparam [4:0] ATOMIC_SWAP           = 5'd2;
  localparam [4:0] ATOMIC_CAS            = 5'd3;
  localparam [4:0] CACHE_LINE_WRITE_BACK = 5'd4;
  localparam [4:0] CACHE_LINE_LOAD       = 5'd5;
  localparam [4:0] NOOP                  = 5'd6;
  localparam [4:0] WRITE_THROUGH         = 5'd7;
  localparam [4:0] SNOOPY_WRITE_BACK     = 5'd8;
  localparam [4:0] FLUSH_WRITE_BACK      = 5'd9;

  wire s_internalStall, s_busError;
  wire s_invertedClock = ~clock;
  reg s_flushRequestReg, s_flushActiveReg, s_cacheEnabledReg;
  reg [31:0] s_selectedCacheData, s_busDataInReg;
  reg s_dataForward1, s_dataForward2;
  reg [4:0] s_busTransactionTypeReg;
  reg [2:0] s_busTransactionLengthReg;
  reg[5:0] s_cacheStateReg;
  reg s_busDataInValidReg, s_waitWriteBackReg;
  reg [31:0] s_busAddressReg;
  reg [2:0] s_wordBurstSelectReg;

  /*
   *
   * Here the pipeline stages are defined
   *
   */
  reg [31:0] s_stage1DataFromCoreNext, s_stage1DataFromCoreReg, s_stage1PcReg, s_stage1MemoryAddressReg;
  reg [31:0] s_stage2DataToCoreReg, s_stage2PcReg, s_stage2MemoryAddressReg, s_stage2DataFromCoreReg;
  reg [3:0] s_stage1DataByteEnableNext, s_stage1DataByteEnableReg, s_stage2DataByteEnableReg;
  reg [8:0] s_stage1TargetRegisterReg, s_stage2TargetRegisterReg;
  reg [7:0] s_stage1MemCompValueReg, s_stage2MemCompValueReg;
  reg [2:0] s_stage1LoadActionReg, s_stage2LoadActionReg;
  reg s_stage2AbortReg, s_stage2ValidReg, s_stage1UReadReg, s_stage1UWriteReg, s_stage1CReadReg, s_stage1CWriteReg;
  reg s_stage1SpmReadReg, s_stage1CasReg, s_stage1SwapReg, s_stage1CacheActionReg, s_stage2UReadReg;
  reg s_stage2UWriteReg, s_stage2CReadReg, s_stage2CWriteReg, s_stage2SpmReadReg, s_stage2CasReg, s_stage2SwapReg, s_stage2CacheActionReg;
  
  wire [31:0] s_stage2DataToCoreNext = (s_internalStall == 1'b0) ? s_selectedCacheData :
                                       (s_busDataInValidReg == 1'b1 &&
                                        ( (s_busTransactionTypeReg == CACHE_LINE_LOAD && s_dataForward2 == 1'b1) ||
                                          s_busTransactionTypeReg == UNCACHEABLE_READ ||
                                          s_busTransactionTypeReg == ATOMIC_SWAP ||
                                          s_busTransactionTypeReg == ATOMIC_CAS
                                        ) 
                                       ) ? s_busDataInReg : s_stage2DataToCoreReg;
  wire s_stage2AbortNext        = (reset == 1'b1 || s_internalStall == 1'b0) ? 1'b0 : s_busError;
  wire s_stage2ValidNext        = (reset == 1'b1 || s_internalStall == 1'b0) ? 1'b0 :
                                  (s_cacheStateReg == RELEASE &&
                                   (s_busTransactionTypeReg == UNCACHEABLE_WRITE ||
                                    s_busTransactionTypeReg == UNCACHEABLE_READ ||
                                    s_busTransactionTypeReg == ATOMIC_SWAP ||
                                    s_busTransactionTypeReg == ATOMIC_CAS
                                   )
                                  ) ? 1'b1 : s_stage2ValidReg;
  wire s_spmAddressed           = memoryAddress[31:20] == 12'hC00 ? 1'b1 : 1'b0;
  wire s_spmAction              = (s_spmAddressed == 1'b1 &&
                                   (memoryLoad != NO_LOAD ||
                                    memoryStore == STORE_BYTE ||
                                    memoryStore == STORE_HALF_WORD ||
                                    memoryStore == STORE_WORD) ) ? 1'b1 : 1'b0;
  wire s_stage1UReadNext        = (memoryLoad != NO_LOAD && s_spmAddressed == 1'b0 &&
                                   (s_cacheEnabledReg == 1'b0 || memoryAddress[30] == 1'b1)) ? 1'b1 : 1'b0;
  wire s_stage1UWriteNext       = (s_spmAddressed == 1'b0 && (s_cacheEnabledReg == 1'b0 || memoryAddress[30] == 1'b1) &&
                                   (memoryStore == STORE_BYTE ||
                                    memoryStore == STORE_HALF_WORD ||
                                    memoryStore == STORE_WORD)) ? 1'b1 : 1'b0;
  wire s_stage1CReadNext        = (s_cacheEnabledReg == 1'b1 && memoryAddress[30] == 1'b0 && memoryLoad != NO_LOAD) ? 1'b1 : 1'b0;
  wire s_stage1CWriteNext       = (s_cacheEnabledReg == 1'b1 && memoryAddress[30] == 1'b0 && 
                                   (memoryStore == STORE_BYTE ||
                                    memoryStore == STORE_HALF_WORD ||
                                    memoryStore == STORE_WORD)) ? 1'b1 : 1'b0;
  wire s_stage1SpmReadNext     = (memoryLoad != NO_LOAD) ? s_spmAddressed : 1'b0;
  wire s_stage1CasNext         = (memoryStore == COMPARE_AND_SWAP && s_spmAddressed == 1'b0) ? 1'b1 : 1'b0;
  wire s_stage1SwapNext        = (memoryStore == SWAP && s_spmAddressed == 1'b0) ? 1'b1 : 1'b0;
  wire s_stage1CacheActionNext = (memoryLoad != NO_LOAD || memoryStore != NO_STORE) ? 1'b1 : 1'b0;

  always @*
    case (memoryStore)
      STORE_HALF_WORD  : begin
                           s_stage1DataFromCoreNext   <= {dataFromCore[7:0],dataFromCore[15:8],dataFromCore[7:0],dataFromCore[15:8]};
                           s_stage1DataByteEnableNext <= {memoryAddress[1],memoryAddress[1],~memoryAddress[1],~memoryAddress[1]};
                         end
      STORE_BYTE,
      COMPARE_AND_SWAP : begin
                           s_stage1DataFromCoreNext   <= {dataFromCore[7:0],dataFromCore[7:0],dataFromCore[7:0],dataFromCore[7:0]};
                           case (memoryAddress[1:0])
                             2'b00   : s_stage1DataByteEnableNext <= 4'b0001;
                             2'b01   : s_stage1DataByteEnableNext <= 4'b0010;
                             2'b10   : s_stage1DataByteEnableNext <= 4'b0100;
                             default : s_stage1DataByteEnableNext <= 4'b1000;
                           endcase
                         end
      STORE_WORD,
      SWAP             : begin
                           s_stage1DataFromCoreNext   <= {dataFromCore[7:0],dataFromCore[15:8],dataFromCore[23:16],dataFromCore[31:24]};
                           s_stage1DataByteEnableNext <= 4'hF;
                         end
      default          : begin
                           s_stage1DataFromCoreNext   <= s_stage1DataFromCoreReg;
                           s_stage1DataByteEnableNext <= 4'hF;
                         end
    endcase
 
 always @(posedge clock)
   if (reset == 1'b1 || (s_flushRequestReg == 1'b1 && s_internalStall == 1'b0))
     begin
       s_stage1UReadReg       <= 0;
       s_stage1UWriteReg      <= 0;
       s_stage1CReadReg       <= 0;
       s_stage1CWriteReg      <= 0;
       s_stage1SpmReadReg     <= 0;
       s_stage1CasReg         <= 0;
       s_stage1SwapReg        <= 0;
       s_stage1CacheActionReg <= 0;
     end
   else if (s_internalStall == 1'b0)
     begin
       s_stage1UReadReg       <= s_stage1UReadNext;
       s_stage1UWriteReg      <= s_stage1UWriteNext;
       s_stage1CReadReg       <= s_stage1CReadNext;
       s_stage1CWriteReg      <= s_stage1CWriteNext;
       s_stage1SpmReadReg     <= s_stage1SpmReadNext;
       s_stage1CasReg         <= s_stage1CasNext;
       s_stage1SwapReg        <= s_stage1SwapNext;
       s_stage1CacheActionReg <= s_stage1CacheActionNext;
     end
 
 always @(posedge clock)
   if (s_internalStall == 1'b0)
     begin
       s_stage1DataFromCoreReg   <= s_stage1DataFromCoreNext;
       s_stage1DataByteEnableReg <= s_stage1DataByteEnableNext;
       s_stage1PcReg             <= {instructionAddress,2'b00};
       s_stage1MemoryAddressReg  <= memoryAddress;
       s_stage1MemCompValueReg   <= memoryCompareValue;
       s_stage2PcReg             <= s_stage1PcReg;
       s_stage2MemoryAddressReg  <= s_stage1MemoryAddressReg;
       s_stage2DataFromCoreReg   <= s_stage1DataFromCoreReg;
       s_stage2DataByteEnableReg <= s_stage1DataByteEnableReg;
       s_stage2MemCompValueReg   <= s_stage1MemCompValueReg;
     end

  always @(posedge clock)
    if (reset == 1'b1) 
      begin
        s_stage1LoadActionReg     <= 0;
        s_stage1TargetRegisterReg <= 0;
        s_stage2LoadActionReg     <= 0;
        s_stage2TargetRegisterReg <= 0;
        s_stage2UReadReg          <= 0;
        s_stage2UWriteReg         <= 0;
        s_stage2CReadReg          <= 0;
        s_stage2CWriteReg         <= 0;
        s_stage2SpmReadReg        <= 0;
        s_stage2CasReg            <= 0;
        s_stage2SwapReg           <= 0;
        s_stage2CacheActionReg    <= 0;
      end
    else if (s_internalStall == 1'b0)
      begin
        s_stage1LoadActionReg     <= (s_flushRequestReg == 1'b1) ? NO_LOAD : memoryLoad;
        s_stage1TargetRegisterReg <= loadTarget;
        s_stage2LoadActionReg     <= s_stage1LoadActionReg;
        s_stage2TargetRegisterReg <= s_stage1TargetRegisterReg;
        s_stage2UReadReg          <= s_stage1UReadReg;
        s_stage2UWriteReg         <= s_stage1UWriteReg;
        s_stage2CReadReg          <= s_stage1CReadReg;
        s_stage2CWriteReg         <= s_stage1CWriteReg;
        s_stage2SpmReadReg        <= s_stage1SpmReadReg;
        s_stage2CasReg            <= s_stage1CasReg;
        s_stage2SwapReg           <= s_stage1SwapReg;
        s_stage2CacheActionReg    <= s_stage1CacheActionReg;
      end

  always @(posedge clock) 
    begin
      s_stage2DataToCoreReg <= s_stage2DataToCoreNext;
      s_stage2AbortReg      <= s_stage2AbortNext;
      s_stage2ValidReg      <= s_stage2ValidNext;
    end
  
  /*
   *
   * Here we define the data that is delivered to the write-back stage
   *
   *
   */
  wire [31:0] s_dataToCore = (s_stage2SpmReadReg == 1'b1) ? dataFromSpm : s_stage2DataToCoreReg;
  wire [15:0] s_halfWord = (s_stage2MemoryAddressReg[1] == 1'b0) ? {s_dataToCore[7:0],s_dataToCore[15:8]} : {s_dataToCore[23:16],s_dataToCore[31:24]};
  reg [7:0] s_dataByte;
  always @*
    case (s_stage2MemoryAddressReg[1:0])
      2'b00   : s_dataByte <= s_dataToCore[7:0];
      2'b01   : s_dataByte <= s_dataToCore[15:8];
      2'b10   : s_dataByte <= s_dataToCore[23:16];
      default : s_dataByte <= s_dataToCore[31:24];
    endcase
  

  always @*
    if (s_stage2CasReg == 1'b1) dataToCore <= {{24{1'b0}} , s_dataByte};
    else
      case (s_stage2LoadActionReg)
        LOAD_HALF_WORD_ZERO_EXTENDED : dataToCore <= { {16{1'b0}} , s_halfWord };
        LOAD_HALF_WORD_SIGN_EXTENDED : dataToCore <= { {16{s_halfWord[15]}} , s_halfWord };
        LOAD_BYTE_ZERO_EXTENDED      : dataToCore <= { {24{1'b0}} , s_dataByte };
        LOAD_BYTE_SIGN_EXTENDED      : dataToCore <= { {24{s_dataByte[7]}} , s_dataByte };
        default                      : dataToCore <= { s_dataToCore[7:0], s_dataToCore[15:8] , s_dataToCore[23:16], s_dataToCore[31:24] };
      endcase

  /* 
   *
   * Here the scratchpad memory signals are defined
   *
   *
   */
  assign dataToSpm      = s_stage1DataFromCoreNext;
  assign spmAddress     = memoryAddress[19:2];
  assign spmByteEnables = s_stage1DataByteEnableNext;
  assign spmChipSelect  = s_spmAction & ~s_internalStall;
  assign spmWriteEnable = (s_spmAddressed == 1'b1 && s_internalStall == 1'b0 &&
                           (memoryStore == STORE_BYTE ||
                            memoryStore == STORE_HALF_WORD ||
                            memoryStore == STORE_WORD) ) ? 1'b1 : 1'b0;

  /*
   *
   * Here some output signals are defined
   *
   *
   */
  wire s_registerWe = ~s_internalStall & (s_stage2UReadReg | s_stage2CasReg | s_stage2SwapReg |
                                          s_stage2CReadReg | s_stage2SpmReadReg );
  assign dataAbort          = s_stage2AbortReg & ~s_internalStall;
  assign abortAddress       = s_stage2PcReg;
  assign abortMemoryAddress = s_stage2MemoryAddressReg;
  assign registerAddress    = s_stage2TargetRegisterReg;
  assign registerWe         = s_registerWe;
  
  /*
   *
   * Here the snooping interface is defined
   *
   */
  reg s_doNotSnoopThisBurstReg, s_snoopyStage1ReadActionReg, s_snoopyStage2ReadActionReg;
  reg [31:0] s_snoopyStage1AddressReg, s_snoopyStage2AddressReg, s_snoopyStage3AddressReg;
  reg [7:0] s_snoopyStage1BurstSizeReg;
  reg s_snoopyStage1LookupSnoopReg, s_snoopyStage2LookupSnoopReg;
  reg [23:0] s_snoopyTag;
  reg [8:0] s_snoopyWriteIndex;
  reg [3:0] s_snoopyStage3WaySelectReg;
  reg s_snoopyStage3InvalidateReg, s_snoopyStage3UpdateStateReg, s_snoopyWbDetectReg, s_snoopyDirtyIdReg;
  wire [31:0] s_combinedSnoop1, s_combinedSnoop2, s_combinedSnoop3, s_combinedSnoop4;
  wire [23:0] s_snoopyStage2Tag1Reg = s_combinedSnoop1[27:4];
  wire [23:0] s_snoopyStage2Tag2Reg = s_combinedSnoop2[27:4];
  wire [23:0] s_snoopyStage2Tag3Reg = s_combinedSnoop3[27:4];
  wire [23:0] s_snoopyStage2Tag4Reg = s_combinedSnoop4[27:4];
  wire [3:0] s_snoopyStage2Way1State = s_combinedSnoop1[3:0];
  wire [3:0] s_snoopyStage2Way2State = s_combinedSnoop2[3:0];
  wire [3:0] s_snoopyStage2Way3State = s_combinedSnoop3[3:0];
  wire [3:0] s_snoopyStage2Way4State = s_combinedSnoop4[3:0];
  wire s_doNotSnoopThisBurstNext = (beginTransactionIn == 1'b1 || reset == 1'b1) ? 1'b0 :
                                   (s_cacheStateReg == INIT_TRANSACTION &&
                                    (s_busTransactionTypeReg == WRITE_THROUGH ||
                                     s_busTransactionTypeReg == CACHE_LINE_WRITE_BACK ||
                                     s_busTransactionTypeReg == CACHE_LINE_LOAD ||
                                     s_busTransactionTypeReg == SNOOPY_WRITE_BACK ||
                                     s_busTransactionTypeReg == FLUSH_WRITE_BACK
                                    )
                                   ) ? 1'b1 : s_doNotSnoopThisBurstReg;
  wire [3:0] s_cacheConfiguration = {numberOfWays, cacheSize};
  wire s_snoopyHit1 = (s_snoopyTag == s_snoopyStage2Tag1Reg &&
                       s_snoopyStage2Way1State[0] == 1'b1) ? s_snoopyStage1LookupSnoopReg : 1'b0;
  wire s_snoopyHit2 = (s_snoopyTag == s_snoopyStage2Tag2Reg &&
                       s_snoopyStage2Way2State[0] == 1'b1) ? s_snoopyStage1LookupSnoopReg : 1'b0;
  wire s_snoopyHit3 = (s_snoopyTag == s_snoopyStage2Tag3Reg &&
                       s_snoopyStage2Way3State[0] == 1'b1) ? s_snoopyStage1LookupSnoopReg : 1'b0;
  wire s_snoopyHit4 = (s_snoopyTag == s_snoopyStage2Tag4Reg &&
                       s_snoopyStage2Way4State[0] == 1'b1) ? s_snoopyStage1LookupSnoopReg : 1'b0;
  wire s_snoopyStage3InvalidateNext = ~reset & s_snoopyStage2ReadActionReg & (s_snoopyHit1 | s_snoopyHit2 | s_snoopyHit3 | s_snoopyHit4);
  wire s_snoopyStage3UpdateStateNext = ~reset & 
                                      ((s_snoopyHit1 | s_snoopyHit2 | s_snoopyHit3 | s_snoopyHit4) & ~s_snoopyStage2ReadActionReg ) |
                                       ((s_snoopyHit1 & ~(s_snoopyStage2Way1State[1] | s_snoopyStage2Way1State[2] | s_snoopyStage2Way1State[3])) |
                                        (s_snoopyHit2 & ~(s_snoopyStage2Way2State[1] | s_snoopyStage2Way2State[2] | s_snoopyStage2Way2State[3])) |
                                        (s_snoopyHit3 & ~(s_snoopyStage2Way3State[1] | s_snoopyStage2Way3State[2] | s_snoopyStage2Way3State[3])) |
                                        (s_snoopyHit1 & ~(s_snoopyStage2Way4State[1] | s_snoopyStage2Way4State[2] | s_snoopyStage2Way4State[3])));
  wire s_snoopyWbDetectNext = (reset == 1'b0 && 
                               s_snoopyStage1ReadActionReg == 1'b0 &&
                               s_snoopyStage1LookupSnoopReg == 1'b1 &&
                               s_snoopyStage1BurstSizeReg == 8'h07 &&
                               s_waitWriteBackReg == 1'b1 &&
                               s_snoopyStage1AddressReg[31:5] == s_stage2MemoryAddressReg[31:5]) ? 1'b1 : 1'b0;
  wire s_snoopyDirtyIdNext = ~reset &
                             ((s_snoopyHit1 & s_snoopyStage2Way1State[3]) |
                              (s_snoopyHit2 & s_snoopyStage2Way2State[3]) |
                              (s_snoopyHit3 & s_snoopyStage2Way3State[3]) |
                              (s_snoopyHit4 & s_snoopyStage2Way4State[3]));
  assign  privateDirtyOut = s_snoopyDirtyIdReg;

  always @(posedge clock) 
    begin
      privateDataOut               <= ~reset & (s_snoopyHit1 | s_snoopyHit2 | s_snoopyHit3 | s_snoopyHit4);
      s_snoopyDirtyIdReg           <= s_snoopyDirtyIdNext;
      s_snoopyWbDetectReg          <= s_snoopyWbDetectNext;
      s_snoopyStage1LookupSnoopReg <= ~reset & beginTransactionIn & coherenceEnabled & ~s_doNotSnoopThisBurstReg;
      s_doNotSnoopThisBurstReg     <= s_doNotSnoopThisBurstNext;
      s_snoopyStage2ReadActionReg  <= s_snoopyStage1ReadActionReg;
      s_snoopyStage2AddressReg     <= s_snoopyStage1AddressReg;
      s_snoopyStage3AddressReg     <= s_snoopyStage2AddressReg;
      s_snoopyStage2LookupSnoopReg <= s_snoopyStage1LookupSnoopReg;
      s_snoopyStage3WaySelectReg   <= {s_snoopyHit3, s_snoopyHit2, s_snoopyHit2, s_snoopyHit1};
      s_snoopyStage3InvalidateReg  <= s_snoopyStage3InvalidateNext;
      s_snoopyStage3UpdateStateReg <= s_snoopyStage3UpdateStateNext;
      if (beginTransactionIn == 1'b1)
        begin
          s_snoopyStage1ReadActionReg <= readNotWriteIn;
          s_snoopyStage1AddressReg    <= addressDataIn;
          s_snoopyStage1BurstSizeReg  <= burstSizeIn;
        end
    end
  
  always @*
    case (s_cacheConfiguration)
      FOUR_WAY_SET_ASSOCIATIVE_1K : begin
                                      s_snoopyTag         <= s_snoopyStage2AddressReg[31:8];
                                      s_snoopyWriteIndex  <= { 6'd0, s_snoopyStage3AddressReg[7:5] };
                                    end
      FOUR_WAY_SET_ASSOCIATIVE_2K,
      TWO_WAY_SET_ASSOCIATIVE_1K  : begin
                                      s_snoopyTag         <= { 1'b0, s_snoopyStage2AddressReg[31:9]};
                                      s_snoopyWriteIndex  <= { 5'd0, s_snoopyStage3AddressReg[8:5] };
                                    end
      FOUR_WAY_SET_ASSOCIATIVE_4K,
      TWO_WAY_SET_ASSOCIATIVE_2K,
      DIRECT_MAPPED_1K            : begin
                                      s_snoopyTag         <= { 2'd0, s_snoopyStage2AddressReg[31:10]};
                                      s_snoopyWriteIndex  <= { 4'd0, s_snoopyStage3AddressReg[9:5] };
                                    end
      FOUR_WAY_SET_ASSOCIATIVE_8K,
      TWO_WAY_SET_ASSOCIATIVE_4K,
      DIRECT_MAPPED_2K            : begin
                                      s_snoopyTag         <= { 3'd0, s_snoopyStage2AddressReg[31:11]};
                                      s_snoopyWriteIndex  <= { 3'd0, s_snoopyStage3AddressReg[10:5] };
                                    end
      TWO_WAY_SET_ASSOCIATIVE_8K,
      DIRECT_MAPPED_4K            : begin
                                      s_snoopyTag         <= { 4'd0, s_snoopyStage2AddressReg[31:12]};
                                      s_snoopyWriteIndex  <= { 2'd0, s_snoopyStage3AddressReg[11:5] };
                                    end
      default                     : begin
                                      s_snoopyTag         <= { 5'd0, s_snoopyStage2AddressReg[31:13]};
                                      s_snoopyWriteIndex  <= { 1'b0, s_snoopyStage3AddressReg[12:5]};
                                    end
    endcase
    
  /*
   *
   * Here the snoopy write back buffer is defined
   *
   */
  reg s_snoopyWbBufferEmptyReg, s_snoopyWbBufferFullReg;
  reg [3:0] s_snoopyWbBufferReadAddrReg, s_snoopyWbBufferWriteAddrReg;
  reg [3:0] s_snoopyWbWaySelectReg, s_snoopyWbWaySelectNext;
  reg [11:0] s_snoopyWbBufferEntryReg [15:0];
  reg [10:0] s_snoopyWbBufferNewValue;
  reg [8:0] s_snoopyWbIndexReg;
  reg [23:0] s_snoopyWbTagReg;
  reg [31:0] s_snoopyWbAddress;
  wire [15:0] s_snoopyWbBufferHits;
  wire s_snoopyWbBufferRe = (s_snoopyWbBufferEmptyReg == 1'b0 &&  s_cacheStateReg == LOOKUP_TAGS) ? 1'b1 : 1'b0;
  wire s_snoopyWbBufferWe = (s_snoopyWbBufferFullReg == 1'b0 && s_snoopyDirtyIdReg == 1'b1 && 
                             s_snoopyWbBufferHits == 16'h0000) ? 1'b1 : 1'b0;
  wire [3:0] s_snoopyWbBufferReadAddrNext  = s_snoopyWbBufferReadAddrReg + 4'h1;
  wire [3:0] s_snoopyWbBufferWriteAddrNext = s_snoopyWbBufferWriteAddrReg + 4'h1;
  wire [1:0] s_snoopyWbSelect;
  
  genvar n;
  
  assign s_snoopyWbSelect[1] = s_snoopyWbWaySelectReg[3] | s_snoopyWbWaySelectReg[2];
  assign s_snoopyWbSelect[0] = s_snoopyWbWaySelectReg[3] | s_snoopyWbWaySelectReg[1];
  
  always @ (posedge clock)
    if (reset == 1'b1)
      begin
        s_snoopyWbBufferReadAddrReg  <= 0;
        s_snoopyWbBufferWriteAddrReg <= 0;
        s_snoopyWbBufferEmptyReg     <= 1'b1;
        s_snoopyWbBufferFullReg      <= 1'b0;
      end
    else if (s_snoopyWbBufferRe == 1'b1)
      begin
        s_snoopyWbBufferReadAddrReg  <= s_snoopyWbBufferReadAddrNext;
        s_snoopyWbBufferFullReg      <= 1'b0;
        if (s_snoopyWbBufferReadAddrNext == s_snoopyWbBufferWriteAddrReg)
          s_snoopyWbBufferEmptyReg <= 1'b1; 
      end
   else if (s_snoopyWbBufferWe == 1'b1)
     begin
       s_snoopyWbBufferWriteAddrReg <= s_snoopyWbBufferWriteAddrNext;
       s_snoopyWbBufferEmptyReg     <= 1'b0;
       if (s_snoopyWbBufferWriteAddrNext == s_snoopyWbBufferReadAddrReg)
         s_snoopyWbBufferFullReg <= 1'b1; 
     end
  
  always @*
    begin
      s_snoopyWbBufferNewValue[10]  <= s_snoopyStage3WaySelectReg[3] | s_snoopyStage3WaySelectReg[2];
      s_snoopyWbBufferNewValue[9]   <= s_snoopyStage3WaySelectReg[1] | s_snoopyStage3WaySelectReg[0];
      s_snoopyWbBufferNewValue[8:0] <= s_snoopyWriteIndex;
      case (s_snoopyWbBufferEntryReg[s_snoopyWbBufferReadAddrReg][11:9])
        3'b100  : s_snoopyWbWaySelectNext <= 4'b0001;
        3'b101  : s_snoopyWbWaySelectNext <= 4'b0010;
        3'b110  : s_snoopyWbWaySelectNext <= 4'b0100;
        3'b111  : s_snoopyWbWaySelectNext <= 4'b1000;
        default : s_snoopyWbWaySelectNext <= 4'b0000;
      endcase
    end
  
  always @ (posedge clock)
    if (s_cacheStateReg == STORE_TAGS)
      case (s_snoopyWbSelect)
        2'b00   : s_snoopyWbTagReg <= s_snoopyStage2Tag1Reg;
        2'b01   : s_snoopyWbTagReg <= s_snoopyStage2Tag2Reg;
        2'b10   : s_snoopyWbTagReg <= s_snoopyStage2Tag3Reg;
        default : s_snoopyWbTagReg <= s_snoopyStage2Tag4Reg;
      endcase
  
  always @ (posedge clock)
    if (s_cacheStateReg == REQUEST_THE_BUS &&
        s_snoopyWbBufferEmptyReg == 1'b0 &&
        s_flushActiveReg == 1'b0)
      begin
        s_snoopyWbWaySelectReg <= s_snoopyWbWaySelectNext;
        s_snoopyWbIndexReg     <= s_snoopyWbBufferEntryReg[s_snoopyWbBufferReadAddrReg][8:0];
      end

  always @*
    case (s_cacheConfiguration)
      FOUR_WAY_SET_ASSOCIATIVE_1K : begin
                                      s_snoopyWbAddress[31:8] <= s_snoopyWbTagReg[23:0];
                                      s_snoopyWbAddress[7:5]   <= s_snoopyWbIndexReg[2:0];
                                      s_snoopyWbAddress[4:0]   <= 5'd0;
                                    end
      FOUR_WAY_SET_ASSOCIATIVE_2K,
      TWO_WAY_SET_ASSOCIATIVE_1K  : begin
                                      s_snoopyWbAddress[31:9]  <= s_snoopyWbTagReg[22:0];
                                      s_snoopyWbAddress[8:5]   <= s_snoopyWbIndexReg[3:0];
                                      s_snoopyWbAddress[4:0]   <= 5'd0;
                                    end
      FOUR_WAY_SET_ASSOCIATIVE_4K,
      TWO_WAY_SET_ASSOCIATIVE_2K,
      DIRECT_MAPPED_1K            : begin
                                      s_snoopyWbAddress[31:10] <= s_snoopyWbTagReg[21:0];
                                      s_snoopyWbAddress[9:5]   <= s_snoopyWbIndexReg[4:0];
                                      s_snoopyWbAddress[4:0]   <= 5'd0;
                                    end
      FOUR_WAY_SET_ASSOCIATIVE_8K,
      TWO_WAY_SET_ASSOCIATIVE_4K,
      DIRECT_MAPPED_2K            : begin
                                      s_snoopyWbAddress[31:11] <= s_snoopyWbTagReg[20:0];
                                      s_snoopyWbAddress[10:5]  <= s_snoopyWbIndexReg[5:0];
                                      s_snoopyWbAddress[4:0]   <= 5'd0;
                                    end
      TWO_WAY_SET_ASSOCIATIVE_8K,
      DIRECT_MAPPED_4K            : begin
                                      s_snoopyWbAddress[31:12] <= s_snoopyWbTagReg[19:0];
                                      s_snoopyWbAddress[11:5]  <= s_snoopyWbIndexReg[6:0];
                                      s_snoopyWbAddress[4:0]   <= 5'd0;
                                    end
      default                     : begin
                                      s_snoopyWbAddress[31:13] <= s_snoopyWbTagReg[18:0];
                                      s_snoopyWbAddress[12:5]  <= s_snoopyWbIndexReg[7:0];
                                      s_snoopyWbAddress[4:0]   <= 5'd0;
                                    end
    endcase

  generate
    for (n = 0; n < 16 ; n = n + 1) 
      begin : gen
        always @(posedge clock)
          if ((reset == 1'b1) ||
              (s_snoopyWbBufferReadAddrReg == n && s_snoopyWbBufferRe == 1'b1)) s_snoopyWbBufferEntryReg[n] <= 0;
          else if (s_snoopyWbBufferWriteAddrReg == n && s_snoopyWbBufferWe == 1'b1) s_snoopyWbBufferEntryReg[n] <= {1'b1,s_snoopyWbBufferNewValue};
        
        assign s_snoopyWbBufferHits[n] = (s_snoopyWbBufferEntryReg[n][11] == 1'b1 && s_snoopyWbBufferEntryReg[n][10:0] == s_snoopyWbBufferNewValue) ? 1'b1 : 1'b0;
      end
  endgenerate
  
  
  /*
   *
   * Here the snarfing signals are defined
   *
   */
  reg s_disableSnarfReg, s_snarfActiveReg, s_snarfUpdateTagReg;
  wire s_snarfActiveNext = (s_snoopyStage1ReadActionReg == 1'b0 &&
                            s_snoopyStage1LookupSnoopReg == 1'b1 &&
                            s_snoopyStage1BurstSizeReg == 8'h07 &&
                            s_waitWriteBackReg == 1'b1 &&
                            snarfingEnabled == 1'b1 &&
                            s_disableSnarfReg == 1'b1 &&
                            s_snoopyStage1AddressReg[31:5] == s_stage2MemoryAddressReg[31:5]) ? 1'b1 : 1'b0;
  
  always @ (posedge clock)
    begin
      s_snarfUpdateTagReg <= ~reset & s_snarfActiveReg & endTransactionIn;
      
      if (s_cacheStateReg == BACKOFF &&
          (s_busTransactionTypeReg == ATOMIC_SWAP ||
           s_busTransactionTypeReg == ATOMIC_CAS)) s_disableSnarfReg <= 1'b1;
      else if (s_waitWriteBackReg == 1'b0 || reset == 1'b1) s_disableSnarfReg <= 1'b0;
      
      if (reset == 1'b1 || endTransactionIn == 1'b1) s_snarfActiveReg <= 1'b0;
      else s_snarfActiveReg <= s_snarfActiveReg | s_snarfActiveNext;
    end
  
  /*
   *
   * Here the flush related signals are defined
   *
   */
  reg [3:0] s_stage1State1Reg, s_stage1State2Reg, s_stage1State3Reg, s_stage1State4Reg;
  reg [23:0] s_stage1Tag1Reg, s_stage1Tag2Reg, s_stage1Tag3Reg, s_stage1Tag4Reg;
  reg [3:0] s_flushWaySelectReg, s_flushInvalidateVector;
  reg s_initializingFlushReg, s_flushSelectedDone, s_flushWriteBackRequired;
  reg s_flushEnableCacheDelayReg, s_dcacheDisableActiveReg;
  reg [8:0] s_flushCounterReg;
  reg [1:0] s_flushWaySelect;
  reg [31:0] s_flushWbAddressReg;
  wire s_initializingFlushNext = (reset == 1'b1) ? 1'b1 : (s_cacheStateReg == FLUSH_DONE) ? 1'b0 : s_initializingFlushReg;
  wire s_flushInvalidate = (s_cacheStateReg == FLUSH_INVALIDATE) ? 1'b1 : 1'b0;
  wire s_flushDone = (s_initializingFlushReg == 1'b1) ? s_flushCounterReg[8] : s_flushSelectedDone;
  wire s_flushWay1RequiresWriteBack = s_stage1State1Reg[0] & (s_stage1State1Reg[3] | s_stage1State1Reg[2]);
  wire s_flushWay2RequiresWriteBack = s_stage1State2Reg[0] & (s_stage1State2Reg[3] | s_stage1State2Reg[2]);
  wire s_flushWay3RequiresWriteBack = s_stage1State3Reg[0] & (s_stage1State3Reg[3] | s_stage1State3Reg[2]);
  wire s_flushWay4RequiresWriteBack = s_stage1State4Reg[0] & (s_stage1State4Reg[3] | s_stage1State4Reg[2]);
  wire s_dcacheDisableFlushRequest = ~s_flushActiveReg & s_dcacheDisableActiveReg & ~s_stage1CacheActionReg & ~s_stage2CacheActionReg;
  wire s_flushRequestNext = (s_cacheStateReg == FLUSH_DONE) ? 1'b0 :
                            (reset == 1'b1 || s_dcacheDisableFlushRequest == 1'b1 ||
                             (flushCache == 1'b1 && s_cacheEnabledReg == 1'b1)) ? 1'b1 : s_flushRequestReg;
  wire s_flushActiveNext = (s_cacheStateReg == FLUSH_DONE) ? 1'b0 :
                            (reset == 1'b1 || s_dcacheDisableFlushRequest == 1'b1 ||
                             (s_flushRequestReg == 1'b1 &&
                              s_stage1CacheActionReg == 1'b0 &&
                              s_stage2CacheActionReg == 1'b0)) ? 1'b1 : s_flushActiveReg;
  wire [8:0] s_flushCounterNext = (reset == 1'b1 || s_cacheStateReg == FLUSH_INIT) ? 9'd0 :
                                  (s_cacheStateReg == FLUSH_INVALIDATE) ? s_flushCounterReg + 9'd1 : s_flushCounterReg;
  wire s_dcacheDisableTick = ~s_cacheEnabledReg & s_flushEnableCacheDelayReg;
  wire s_dcacheDisableActiveNext = (reset == 1'b1 || s_cacheStateReg == FLUSH_DONE) ? 1'b0 :
                                   (s_dcacheDisableTick == 1'b1) ? 1'b1 : s_dcacheDisableActiveReg;
  
  always @*
    case (cacheSize)
      SIZE_8K : begin
                  s_flushSelectedDone <= s_flushCounterReg[8];
                  s_flushWaySelect    <= s_flushCounterReg[7:6];
                end
      SIZE_4K : begin
                  s_flushSelectedDone <= s_flushCounterReg[7];
                  s_flushWaySelect    <= s_flushCounterReg[6:5];
                end
      SIZE_2K : begin
                  s_flushSelectedDone <= s_flushCounterReg[6];
                  s_flushWaySelect    <= s_flushCounterReg[5:4];
                end
      default : begin
                  s_flushSelectedDone <= s_flushCounterReg[5];
                  s_flushWaySelect    <= s_flushCounterReg[4:3];
                end
    endcase

  always @*
    if (s_initializingFlushReg == 1'b1) s_flushWriteBackRequired <= 1'b0;
    else case (numberOfWays)
      FOUR_WAY_SET_ASSOCIATIVE : case (s_flushWaySelect)
                                   2'b00   : s_flushWriteBackRequired <= s_flushWay1RequiresWriteBack;
                                   2'b01   : s_flushWriteBackRequired <= s_flushWay2RequiresWriteBack;
                                   2'b10   : s_flushWriteBackRequired <= s_flushWay3RequiresWriteBack;
                                   default : s_flushWriteBackRequired <= s_flushWay4RequiresWriteBack;
                                 endcase
     TWO_WAY_SET_ASSOCIATIVE   : s_flushWriteBackRequired <= (s_flushWaySelect[1] == 1'b0) ? s_flushWay1RequiresWriteBack : s_flushWay2RequiresWriteBack;
     default                   : s_flushWriteBackRequired <= s_flushWay1RequiresWriteBack;
    endcase
  
  always @*
    if (s_cacheStateReg == FLUSH_INVALIDATE)
      begin
        if (s_initializingFlushReg == 1'b1) s_flushInvalidateVector <= 4'hF;
        else case (numberOfWays)
          FOUR_WAY_SET_ASSOCIATIVE : case (s_flushWaySelect)
                                       2'b00   : s_flushInvalidateVector <= 4'h1;
                                       2'b01   : s_flushInvalidateVector <= 4'h2;
                                       2'b10   : s_flushInvalidateVector <= 4'h4;
                                       default : s_flushInvalidateVector <= 4'h8;
                                     endcase
          TWO_WAY_SET_ASSOCIATIVE  : s_flushInvalidateVector <= {2'b11,s_flushWaySelect[1],~s_flushWaySelect[1]};
          default                  : s_flushInvalidateVector <= 4'hF;
        endcase
      end
    else s_flushInvalidateVector <= 4'h0;

  always @ (posedge clock)
    begin
      s_initializingFlushReg     <= s_initializingFlushNext;
      s_flushRequestReg          <= s_flushRequestNext;
      s_flushActiveReg           <= s_flushActiveNext;
      s_flushCounterReg          <= s_flushCounterNext;
      s_flushEnableCacheDelayReg <= s_cacheEnabledReg;
      s_dcacheDisableActiveReg   <= s_dcacheDisableActiveNext;
      if (s_cacheStateReg == FLUSH_INVALIDATE)
        begin
          case (s_flushWaySelect)
            2'b00   : s_flushWaySelectReg <= 4'h1;
            2'b01   : s_flushWaySelectReg <= 4'h2;
            2'b10   : s_flushWaySelectReg <= 4'h4;
            default : s_flushWaySelectReg <= 4'h8;
          endcase
          s_flushWbAddressReg[4:0] <= 0;
          case (cacheSize)
            SIZE_8K : case (numberOfWays)
                        FOUR_WAY_SET_ASSOCIATIVE : begin
                                                     s_flushWbAddressReg[10:5] <= s_flushCounterReg[5:0];
                                                     case (s_flushWaySelect)
                                                       2'b00   : s_flushWbAddressReg[31:11] <= s_stage1Tag1Reg[20:0];
                                                       2'b01   : s_flushWbAddressReg[31:11] <= s_stage1Tag2Reg[20:0];
                                                       2'b10   : s_flushWbAddressReg[31:11] <= s_stage1Tag3Reg[20:0];
                                                       default : s_flushWbAddressReg[31:11] <= s_stage1Tag4Reg[20:0];
                                                     endcase
                                                   end
                        TWO_WAY_SET_ASSOCIATIVE  : begin
                                                     s_flushWbAddressReg[11:5]  <= s_flushCounterReg[6:0];
                                                     s_flushWbAddressReg[31:12] <= (s_flushCounterReg[7] == 1'b0) ? s_stage1Tag1Reg[19:0] : s_stage1Tag2Reg[19:0];
                                                   end
                        default                  : s_flushWbAddressReg[31:5] <= {s_stage1Tag1Reg[18:0],s_flushCounterReg[7:0]};
                      endcase
            SIZE_4K : case (numberOfWays)
                        FOUR_WAY_SET_ASSOCIATIVE : begin
                                                     s_flushWbAddressReg[9:5] <= s_flushCounterReg[4:0];
                                                     case (s_flushWaySelect)
                                                       2'b00   : s_flushWbAddressReg[31:10] <= s_stage1Tag1Reg[21:0];
                                                       2'b01   : s_flushWbAddressReg[31:10] <= s_stage1Tag2Reg[21:0];
                                                       2'b10   : s_flushWbAddressReg[31:10] <= s_stage1Tag3Reg[21:0];
                                                       default : s_flushWbAddressReg[31:10] <= s_stage1Tag4Reg[21:0];
                                                     endcase
                                                   end
                        TWO_WAY_SET_ASSOCIATIVE  : begin
                                                     s_flushWbAddressReg[10:5]  <= s_flushCounterReg[5:0];
                                                     s_flushWbAddressReg[31:11] <= (s_flushCounterReg[6] == 1'b0) ? s_stage1Tag1Reg[20:0] : s_stage1Tag2Reg[20:0];
                                                   end
                        default                  : s_flushWbAddressReg[31:5] <= {s_stage1Tag1Reg[19:0],s_flushCounterReg[6:0]};
                      endcase
            SIZE_2K : case (numberOfWays)
                        FOUR_WAY_SET_ASSOCIATIVE : begin
                                                     s_flushWbAddressReg[8:5] <= s_flushCounterReg[3:0];
                                                     case (s_flushWaySelect)
                                                       2'b00   : s_flushWbAddressReg[31:9] <= s_stage1Tag1Reg[22:0];
                                                       2'b01   : s_flushWbAddressReg[31:9] <= s_stage1Tag2Reg[22:0];
                                                       2'b10   : s_flushWbAddressReg[31:9] <= s_stage1Tag3Reg[22:0];
                                                       default : s_flushWbAddressReg[31:9] <= s_stage1Tag4Reg[22:0];
                                                     endcase
                                                   end
                        TWO_WAY_SET_ASSOCIATIVE  : begin
                                                     s_flushWbAddressReg[9:5]  <= s_flushCounterReg[4:0];
                                                     s_flushWbAddressReg[31:10] <= (s_flushCounterReg[5] == 1'b0) ? s_stage1Tag1Reg[21:0] : s_stage1Tag2Reg[21:0];
                                                   end
                        default                  : s_flushWbAddressReg[31:5] <= {s_stage1Tag1Reg[20:0],s_flushCounterReg[5:0]};
                      endcase
            default : case (numberOfWays)
                        FOUR_WAY_SET_ASSOCIATIVE : begin
                                                     s_flushWbAddressReg[7:5] <= s_flushCounterReg[2:0];
                                                     case (s_flushWaySelect)
                                                       2'b00   : s_flushWbAddressReg[31:8] <= s_stage1Tag1Reg[23:0];
                                                       2'b01   : s_flushWbAddressReg[31:8] <= s_stage1Tag2Reg[23:0];
                                                       2'b10   : s_flushWbAddressReg[31:8] <= s_stage1Tag3Reg[23:0];
                                                       default : s_flushWbAddressReg[31:8] <= s_stage1Tag4Reg[23:0];
                                                     endcase
                                                   end
                        TWO_WAY_SET_ASSOCIATIVE  : begin
                                                     s_flushWbAddressReg[8:5]  <= s_flushCounterReg[3:0];
                                                     s_flushWbAddressReg[31:9] <= (s_flushCounterReg[4] == 1'b0) ? s_stage1Tag1Reg[22:0] : s_stage1Tag2Reg[22:0];
                                                   end
                        default                  : s_flushWbAddressReg[31:5] <= {s_stage1Tag1Reg[21:0],s_flushCounterReg[4:0]};
                      endcase
          endcase
        end
    end
  
  
  /*
   *
   * Here the state and tag related signals are defined
   *
   */
  reg [3:0] s_stage2ReplacementWayReg;
  reg [3:0] s_stage2State1Reg, s_stage2State2Reg, s_stage2State3Reg, s_stage2State4Reg;
  reg s_stage2Hit1Reg, s_stage2Hit2Reg, s_stage2Hit3Reg, s_stage2Hit4Reg, s_privateCacheLineReg;
  reg [23:0] s_newTag, s_hitTag;
  reg[8:0] s_lookupTagIndex, s_forwardTagIndex, s_activeTagIndex, s_rwTagIndex;
  reg s_hit1, s_hit2, s_hit3, s_hit4, s_stage1IsCacheLookupReg, s_stage2IsCacheLookupReg;
  reg s_stage2Hit1Next, s_stage2Hit2Next, s_stage2Hit3Next, s_stage2Hit4Next; 
  wire s_cacheWriteAction = ~s_internalStall & s_stage2CWriteReg;
  wire s_cacheReadAction = ~s_internalStall & s_stage2CReadReg;
  wire [31:0] s_combinedTag1, s_combinedTag2, s_combinedTag3, s_combinedTag4;
  wire [3:0] s_state1 = s_combinedTag1[3:0];
  wire [3:0] s_state2 = s_combinedTag2[3:0];
  wire [3:0] s_state3 = s_combinedTag3[3:0];
  wire [3:0] s_state4 = s_combinedTag4[3:0];
  wire [23:0] s_tag1 = s_combinedTag1[27:4];
  wire [23:0] s_tag2 = s_combinedTag2[27:4];
  wire [23:0] s_tag3 = s_combinedTag3[27:4];
  wire [23:0] s_tag4 = s_combinedTag4[27:4];
  wire s_privateCacheLineNext = (reset == 1'b1 || busAccessGranted == 1'b1) ? 1'b1 : 
                                (privateDataIn == 1'b1) ? 1'b0 : s_privateCacheLineReg;
  wire [3:0] s_updateWaysState  = (s_cacheEnabledReg == 1'b0 || s_initializingFlushReg == 1'b1) ? 4'h0 :
                                  (s_snoopyStage3UpdateStateReg == 1'b1) ? s_snoopyStage3WaySelectReg :
                                  (s_cacheStateReg == MARK_SHARED) ? s_snoopyWbWaySelectReg :
                                  (s_snarfUpdateTagReg == 1'b1 |
                                   ( (s_busTransactionTypeReg == CACHE_LINE_LOAD || s_busTransactionTypeReg == CACHE_LINE_WRITE_BACK) &&
                                     (s_cacheStateReg == INIT_TRANSACTION ||
                                      (s_cacheStateReg == UPDATE_TAGS && s_busError == 1'b0)
                                     ))) ? s_stage2ReplacementWayReg :
                                  (s_cacheWriteAction == 1'b1) ? {s_stage2Hit4Reg, s_stage2Hit3Reg, s_stage2Hit2Reg, s_stage2Hit1Reg} : 4'h0;
  wire [3:0] s_newCacheLineState = ((s_cacheStateReg == INIT_TRANSACTION &&
                                     (s_busTransactionTypeReg == CACHE_LINE_WRITE_BACK || s_busTransactionTypeReg == CACHE_LINE_LOAD)) ||
                                    s_snoopyStage3InvalidateReg == 1'b1) ? STATE_INVALID :
                                   (coherenceEnabled == 1'b1 && writeBackPolicy == 1'b1 &&
                                    s_cacheWriteAction == 1'b1 && s_snarfUpdateTagReg == 1'b0 &&
                                    s_stage2MemoryAddressReg[31] == 1'b0) ? STATE_MODIFIED :
                                   (s_cacheWriteAction == 1'b1 && s_snarfUpdateTagReg == 1'b0 &&
                                    (s_stage2MemoryAddressReg[31] == 1'b1 || (coherenceEnabled == 1'b0 && writeBackPolicy == 1'b1))) ? STATE_DIRTY :
                                   (s_cacheStateReg == UPDATE_TAGS && s_stage2MemoryAddressReg[31] == 1'b0 &&
                                    writeBackPolicy == 1'b1 && s_privateCacheLineReg == 1'b1 && mesiEnabled == 1'b1) ? STATE_EXCLUSIVE :
                                   (((s_cacheWriteAction == 1'b1 || (s_cacheStateReg == UPDATE_TAGS && s_stage2CWriteReg == 1'b1)) && writeBackPolicy == 1'b0) ||
                                    s_snarfUpdateTagReg == 1'b1 || s_cacheStateReg == MARK_SHARED ||
                                    (s_snoopyStage3UpdateStateReg == 1'b1 && s_snoopyStage3InvalidateReg == 1'b0) ||
                                    (s_cacheStateReg == UPDATE_TAGS && s_stage2MemoryAddressReg[31] == 1'b0 && coherenceEnabled == 1'b1)) ? STATE_SHARED :
                                   (s_cacheStateReg == UPDATE_TAGS) ? STATE_VALID : STATE_INVALID;
  wire [31:0] s_tagAddress = (s_snoopyStage3UpdateStateReg == 1'b1) ? s_snoopyStage3AddressReg : s_stage2MemoryAddressReg;
  wire [8:0] s_lookupAddress = (s_flushActiveReg == 1'b1) ? s_flushCounterReg : {1'b0, memoryAddress[12:5]};
  wire [8:0] s_rwAddress = (s_cacheStateReg == LOOKUP_TAGS || s_cacheStateReg == MARK_SHARED) ? s_snoopyWbIndexReg :
                           (s_snoopyStage1LookupSnoopReg == 1'b1) ? {1'b0, s_snoopyStage1AddressReg[12:5]} :
                           (s_snoopyStage3UpdateStateReg == 1'b1) ? {1'b0, s_snoopyStage3AddressReg[12:5]} : {1'b0, s_stage2MemoryAddressReg[12:5]};
  wire [3:0] s_stage1State1Next = (reset == 1'b1) ? STATE_INVALID :
                                  (s_updateWaysState[0] == 1'b1 &&
                                   s_flushActiveReg == 1'b0 &&
                                   ( (s_internalStall == 1'b0 && s_rwTagIndex == s_lookupTagIndex) ||
                                     (s_internalStall == 1'b1 && s_rwTagIndex == s_forwardTagIndex)
                                   )) ? s_newCacheLineState :
                                  (s_internalStall == 1'b0) ? s_state1 : s_stage1State1Reg;
  wire [3:0] s_stage1State2Next = (reset == 1'b1) ? STATE_INVALID :
                                  (s_updateWaysState[1] == 1'b1 &&
                                   s_flushActiveReg == 1'b0 &&
                                   ( (s_internalStall == 1'b0 && s_rwTagIndex == s_lookupTagIndex) ||
                                     (s_internalStall == 1'b1 && s_rwTagIndex == s_forwardTagIndex)
                                   )) ? s_newCacheLineState :
                                  (s_internalStall == 1'b0) ? s_state2 : s_stage1State3Reg;
  wire [3:0] s_stage1State3Next = (reset == 1'b1) ? STATE_INVALID :
                                  (s_updateWaysState[2] == 1'b1 &&
                                   s_flushActiveReg == 1'b0 &&
                                   ( (s_internalStall == 1'b0 && s_rwTagIndex == s_lookupTagIndex) ||
                                     (s_internalStall == 1'b1 && s_rwTagIndex == s_forwardTagIndex)
                                   )) ? s_newCacheLineState :
                                  (s_internalStall == 1'b0) ? s_state3 : s_stage1State3Reg;
  wire [3:0] s_stage1State4Next = (reset == 1'b1) ? STATE_INVALID :
                                  (s_updateWaysState[3] == 1'b1 &&
                                   s_flushActiveReg == 1'b0 &&
                                   ( (s_internalStall == 1'b0 && s_rwTagIndex == s_lookupTagIndex) ||
                                     (s_internalStall == 1'b1 && s_rwTagIndex == s_forwardTagIndex)
                                   )) ? s_newCacheLineState :
                                  (s_internalStall == 1'b0) ? s_state4 : s_stage1State4Reg;
  wire [3:0] s_stage2State1Next = (reset == 1'b1) ? STATE_INVALID :
                                  (s_updateWaysState[0] == 1'b1 &&
                                   ( (s_internalStall == 1'b0 && s_rwTagIndex == s_forwardTagIndex) ||
                                     (s_internalStall == 1'b1 && s_rwTagIndex == s_activeTagIndex)
                                   )) ? s_newCacheLineState :
                                  (s_internalStall == 1'b0) ? s_stage1State1Reg : s_stage2State1Reg;
  wire [3:0] s_stage2State2Next = (reset == 1'b1) ? STATE_INVALID :
                                  (s_updateWaysState[1] == 1'b1 &&
                                   ( (s_internalStall == 1'b0 && s_rwTagIndex == s_forwardTagIndex) ||
                                     (s_internalStall == 1'b1 && s_rwTagIndex == s_activeTagIndex)
                                   )) ? s_newCacheLineState :
                                  (s_internalStall == 1'b0) ? s_stage1State2Reg : s_stage2State2Reg;
  wire [3:0] s_stage2State3Next = (reset == 1'b1) ? STATE_INVALID :
                                  (s_updateWaysState[2] == 1'b1 &&
                                   ( (s_internalStall == 1'b0 && s_rwTagIndex == s_forwardTagIndex) ||
                                     (s_internalStall == 1'b1 && s_rwTagIndex == s_activeTagIndex)
                                   )) ? s_newCacheLineState :
                                  (s_internalStall == 1'b0) ? s_stage1State3Reg : s_stage2State3Reg;
  wire [3:0] s_stage2State4Next = (reset == 1'b1) ? STATE_INVALID :
                                  (s_updateWaysState[3] == 1'b1 &&
                                   ( (s_internalStall == 1'b0 && s_rwTagIndex == s_forwardTagIndex) ||
                                     (s_internalStall == 1'b1 && s_rwTagIndex == s_activeTagIndex)
                                   )) ? s_newCacheLineState :
                                  (s_internalStall == 1'b0) ? s_stage1State4Reg : s_stage2State4Reg;
  wire [23:0] s_stage1Tag1Next = (s_cacheStateReg == UPDATE_TAGS &&
                                  s_updateWaysState[0] == 1'b1 &&
                                  s_rwTagIndex == s_forwardTagIndex) ? s_newTag :
                                 (s_internalStall == 1'b0) ? s_tag1 : s_stage1Tag1Reg;
  wire [23:0] s_stage1Tag2Next = (s_cacheStateReg == UPDATE_TAGS &&
                                  s_updateWaysState[1] == 1'b1 &&
                                  s_rwTagIndex == s_forwardTagIndex) ? s_newTag :
                                 (s_internalStall == 1'b0) ? s_tag2 : s_stage1Tag2Reg;
  wire [23:0] s_stage1Tag3Next = (s_cacheStateReg == UPDATE_TAGS &&
                                  s_updateWaysState[2] == 1'b1 &&
                                  s_rwTagIndex == s_forwardTagIndex) ? s_newTag :
                                 (s_internalStall == 1'b0) ? s_tag3 : s_stage1Tag3Reg;
  wire [23:0] s_stage1Tag4Next = (s_cacheStateReg == UPDATE_TAGS &&
                                  s_updateWaysState[3] == 1'b1 &&
                                  s_rwTagIndex == s_forwardTagIndex) ? s_newTag :
                                 (s_internalStall == 1'b0) ? s_tag4 : s_stage1Tag4Reg;
  wire s_isCacheLookup = (s_cacheEnabledReg == 1'b1 && memoryAddress[30] == 1'b0 &&
                          (memoryStore == STORE_BYTE ||
                           memoryStore == STORE_HALF_WORD ||
                           memoryStore == STORE_WORD ||
                           memoryLoad != NO_LOAD)) ? 1'b1 : 1'b0;
  wire s_hitMask1 = (s_updateWaysState[0] && s_rwTagIndex == s_activeTagIndex ) ? s_newCacheLineState[0] & s_stage2IsCacheLookupReg : s_stage2IsCacheLookupReg;
  wire s_hitMask2 = (s_updateWaysState[1] && s_rwTagIndex == s_activeTagIndex ) ? s_newCacheLineState[0] & s_stage2IsCacheLookupReg : s_stage2IsCacheLookupReg;
  wire s_hitMask3 = (s_updateWaysState[2] && s_rwTagIndex == s_activeTagIndex ) ? s_newCacheLineState[0] & s_stage2IsCacheLookupReg : s_stage2IsCacheLookupReg;
  wire s_hitMask4 = (s_updateWaysState[3] && s_rwTagIndex == s_activeTagIndex ) ? s_newCacheLineState[0] & s_stage2IsCacheLookupReg : s_stage2IsCacheLookupReg;
  wire [31:0] s_newCombinedTag = {4'd0,s_newTag,s_newCacheLineState};

  always @*
    case (s_cacheConfiguration)
      FOUR_WAY_SET_ASSOCIATIVE_1K : begin
                                      s_newTag <= (s_cacheStateReg == MARK_SHARED) ? s_snoopyWbTagReg : s_tagAddress[31:8];
                                      s_hitTag <= s_stage1MemoryAddressReg[31:8];
                                    end
      FOUR_WAY_SET_ASSOCIATIVE_2K,
      TWO_WAY_SET_ASSOCIATIVE_1K  : begin
                                      s_newTag <= (s_cacheStateReg == MARK_SHARED) ? s_snoopyWbTagReg : { 1'b0 ,s_tagAddress[31:9]};
                                      s_hitTag <= { 1'b0 ,s_stage1MemoryAddressReg[31:9]};
                                    end
      FOUR_WAY_SET_ASSOCIATIVE_4K,
      TWO_WAY_SET_ASSOCIATIVE_2K,
      DIRECT_MAPPED_1K            : begin
                                      s_newTag <= (s_cacheStateReg == MARK_SHARED) ? s_snoopyWbTagReg : { {2{1'b0}} ,s_tagAddress[31:10]};
                                      s_hitTag <= { {2{1'b0}} ,s_stage1MemoryAddressReg[31:10]};
                                    end
      FOUR_WAY_SET_ASSOCIATIVE_8K,
      TWO_WAY_SET_ASSOCIATIVE_4K,
      DIRECT_MAPPED_2K            : begin
                                      s_newTag <= (s_cacheStateReg == MARK_SHARED) ? s_snoopyWbTagReg : { {3{1'b0}} ,s_tagAddress[31:11]};
                                      s_hitTag <= { {3{1'b0}} ,s_stage1MemoryAddressReg[31:11]};
                                    end
      TWO_WAY_SET_ASSOCIATIVE_8K,
      DIRECT_MAPPED_4K            : begin
                                      s_newTag <= (s_cacheStateReg == MARK_SHARED) ? s_snoopyWbTagReg : { {4{1'b0}} ,s_tagAddress[31:12]};
                                      s_hitTag <= { {4{1'b0}} ,s_stage1MemoryAddressReg[31:12]};
                                    end
      default                     : begin
                                      s_newTag <= (s_cacheStateReg == MARK_SHARED) ? s_snoopyWbTagReg : { {5{1'b0}} ,s_tagAddress[31:13]};
                                      s_hitTag <= { {5{1'b0}} ,s_stage1MemoryAddressReg[31:13]};
                                    end
    endcase

  always @*
    case (s_cacheConfiguration)
      FOUR_WAY_SET_ASSOCIATIVE_1K : s_rwTagIndex <= { 6'd0 , s_rwAddress[2:0] };
      FOUR_WAY_SET_ASSOCIATIVE_2K,
      TWO_WAY_SET_ASSOCIATIVE_1K  : s_rwTagIndex <= { 5'd0 , s_rwAddress[3:0] };
      FOUR_WAY_SET_ASSOCIATIVE_4K,
      TWO_WAY_SET_ASSOCIATIVE_2K,
      DIRECT_MAPPED_1K            : s_rwTagIndex <= { 4'd0 , s_rwAddress[4:0] };
      FOUR_WAY_SET_ASSOCIATIVE_8K,
      TWO_WAY_SET_ASSOCIATIVE_4K,
      DIRECT_MAPPED_2K            : s_rwTagIndex <= { 3'd0 , s_rwAddress[5:0] };
      TWO_WAY_SET_ASSOCIATIVE_8K,
      DIRECT_MAPPED_4K            : s_rwTagIndex <= { 2'd0 , s_rwAddress[6:0] };
      default                     : s_rwTagIndex <= { 1'd0 , s_rwAddress[7:0] };
    endcase
    
  always @*
    if (s_internalStall == 1'b0)
      begin
        s_stage2Hit1Next = (s_updateWaysState[0] == 1'b1 && s_rwTagIndex == s_forwardTagIndex ) ?
                             s_hit1 & s_stage1IsCacheLookupReg & s_newCacheLineState[0] :
                             s_hit1 & s_stage1IsCacheLookupReg;
        s_stage2Hit2Next = (s_updateWaysState[1] == 1'b1 && s_rwTagIndex == s_forwardTagIndex ) ?
                             s_hit2 & s_stage1IsCacheLookupReg & s_newCacheLineState[0] :
                             s_hit2 & s_stage1IsCacheLookupReg;
        s_stage2Hit3Next = (s_updateWaysState[2] == 1'b1 && s_rwTagIndex == s_forwardTagIndex ) ?
                             s_hit3 & s_stage1IsCacheLookupReg & s_newCacheLineState[0] :
                             s_hit3 & s_stage1IsCacheLookupReg;
        s_stage2Hit4Next = (s_updateWaysState[3] == 1'b1 && s_rwTagIndex == s_forwardTagIndex ) ?
                             s_hit4 & s_stage1IsCacheLookupReg & s_newCacheLineState[0] :
                             s_hit4 & s_stage1IsCacheLookupReg;
      end
    else
      begin
        s_stage2Hit1Next = ((s_cacheStateReg == RELEASE && s_busTransactionTypeReg == CACHE_LINE_LOAD) || s_snarfUpdateTagReg == 1'b1) ?
                             (s_stage2Hit1Reg | s_stage2ReplacementWayReg[0]) & s_hitMask1 : s_stage2Hit1Reg & s_hitMask1;
        s_stage2Hit2Next = ((s_cacheStateReg == RELEASE && s_busTransactionTypeReg == CACHE_LINE_LOAD) || s_snarfUpdateTagReg == 1'b1) ?
                             (s_stage2Hit2Reg | s_stage2ReplacementWayReg[1]) & s_hitMask2 : s_stage2Hit2Reg & s_hitMask2;
        s_stage2Hit3Next = ((s_cacheStateReg == RELEASE && s_busTransactionTypeReg == CACHE_LINE_LOAD) || s_snarfUpdateTagReg == 1'b1) ?
                             (s_stage2Hit3Reg | s_stage2ReplacementWayReg[2]) & s_hitMask3 : s_stage2Hit3Reg & s_hitMask3;
        s_stage2Hit4Next = ((s_cacheStateReg == RELEASE && s_busTransactionTypeReg == CACHE_LINE_LOAD) || s_snarfUpdateTagReg == 1'b1) ?
                             (s_stage2Hit4Reg | s_stage2ReplacementWayReg[3]) & s_hitMask4 : s_stage2Hit4Reg & s_hitMask4;
      end
  
  always @*
    case (numberOfWays)
      FOUR_WAY_SET_ASSOCIATIVE : begin
                                   s_hit1 <= (s_hitTag == s_stage1Tag1Reg) ? s_stage1State1Reg[0] : 1'b0;
                                   s_hit2 <= (s_hitTag == s_stage1Tag2Reg) ? s_stage1State2Reg[0] : 1'b0;
                                   s_hit3 <= (s_hitTag == s_stage1Tag3Reg) ? s_stage1State3Reg[0] : 1'b0;
                                   s_hit4 <= (s_hitTag == s_stage1Tag4Reg) ? s_stage1State4Reg[0] : 1'b0;
                                 end
      TWO_WAY_SET_ASSOCIATIVE  : begin
                                   s_hit1 <= (s_hitTag == s_stage1Tag1Reg) ? s_stage1State1Reg[0] : 1'b0;
                                   s_hit2 <= (s_hitTag == s_stage1Tag2Reg) ? s_stage1State2Reg[0] : 1'b0;
                                   s_hit3 <= 1'b0;
                                   s_hit4 <= 1'b0;
                                 end
      default                  : begin
                                   s_hit1 <= (s_hitTag == s_stage1Tag1Reg) ? s_stage1State1Reg[0] : 1'b0;
                                   s_hit2 <= 1'b0;
                                   s_hit3 <= 1'b0;
                                   s_hit4 <= 1'b0;
                                 end
    endcase

  always @*
    if (s_initializingFlushReg == 1'b1)
      begin
        s_lookupTagIndex  <= s_flushCounterReg[8:0];
        s_forwardTagIndex <= 9'd0;
        s_activeTagIndex  <= 9'd0;
      end
    else case (s_cacheConfiguration)
      FOUR_WAY_SET_ASSOCIATIVE_1K : begin
                                      s_lookupTagIndex  <= { 6'd0 , s_lookupAddress[2:0] };
                                      s_forwardTagIndex <= { 6'd0 , s_stage1MemoryAddressReg[7:5] };
                                      s_activeTagIndex  <= { 6'd0 , s_stage2MemoryAddressReg[7:5] };
                                    end
      FOUR_WAY_SET_ASSOCIATIVE_2K,
      TWO_WAY_SET_ASSOCIATIVE_1K  : begin
                                      s_lookupTagIndex  <= { 5'd0 , s_lookupAddress[3:0] };
                                      s_forwardTagIndex <= { 5'd0 , s_stage1MemoryAddressReg[8:5] };
                                      s_activeTagIndex  <= { 5'd0 , s_stage2MemoryAddressReg[8:5] };
                                    end
      FOUR_WAY_SET_ASSOCIATIVE_4K,
      TWO_WAY_SET_ASSOCIATIVE_2K,
      DIRECT_MAPPED_1K            : begin
                                      s_lookupTagIndex  <= { 4'd0 , s_lookupAddress[4:0] };
                                      s_forwardTagIndex <= { 4'd0 , s_stage1MemoryAddressReg[9:5] };
                                      s_activeTagIndex  <= { 4'd0 , s_stage2MemoryAddressReg[9:5] };
                                    end
      FOUR_WAY_SET_ASSOCIATIVE_8K,
      TWO_WAY_SET_ASSOCIATIVE_4K,
      DIRECT_MAPPED_2K            : begin
                                      s_lookupTagIndex  <= { 3'd0 , s_lookupAddress[5:0] };
                                      s_forwardTagIndex <= { 3'd0 , s_stage1MemoryAddressReg[10:5] };
                                      s_activeTagIndex  <= { 3'd0 , s_stage2MemoryAddressReg[10:5] };
                                    end
      TWO_WAY_SET_ASSOCIATIVE_8K,
      DIRECT_MAPPED_4K            : begin
                                      s_lookupTagIndex  <= { 2'd0 , s_lookupAddress[6:0] };
                                      s_forwardTagIndex <= { 2'd0 , s_stage1MemoryAddressReg[11:5] };
                                      s_activeTagIndex  <= { 2'd0 , s_stage2MemoryAddressReg[11:5] };
                                    end
      default                     : begin
                                      s_lookupTagIndex  <= { 1'b0 , s_lookupAddress[7:0] };
                                      s_forwardTagIndex <= { 1'b0 , s_stage1MemoryAddressReg[12:5] };
                                      s_activeTagIndex  <= { 1'b0 , s_stage2MemoryAddressReg[12:5] };
                                    end
    endcase

  always @(posedge clock)
    begin
      s_privateCacheLineReg    <= s_privateCacheLineNext;
      s_stage1State1Reg        <= s_stage1State1Next;
      s_stage1State2Reg        <= s_stage1State2Next;
      s_stage1State3Reg        <= s_stage1State3Next;
      s_stage1State4Reg        <= s_stage1State4Next;
      s_stage2State1Reg        <= s_stage2State1Next;
      s_stage2State2Reg        <= s_stage2State2Next;
      s_stage2State3Reg        <= s_stage2State3Next;
      s_stage2State4Reg        <= s_stage2State4Next;
      s_stage1Tag1Reg          <= s_stage1Tag1Next;
      s_stage1Tag2Reg          <= s_stage1Tag2Next;
      s_stage1Tag3Reg          <= s_stage1Tag3Next;
      s_stage1Tag4Reg          <= s_stage1Tag4Next;
      s_stage2Hit1Reg          <= s_stage2Hit1Next;
      s_stage2Hit2Reg          <= s_stage2Hit2Next;
      s_stage2Hit3Reg          <= s_stage2Hit3Next;
      s_stage2Hit4Reg          <= s_stage2Hit4Next;
      s_stage1IsCacheLookupReg <= (s_internalStall == 1'b0) ? s_isCacheLookup : s_stage1IsCacheLookupReg;
      s_stage2IsCacheLookupReg <= (s_internalStall == 1'b0) ? s_stage1IsCacheLookupReg : s_stage2IsCacheLookupReg;
    end
  
  sram512X32Dp tagRam1 ( .clockA(s_invertedClock),
                         .writeEnableA(s_flushInvalidateVector[0]),
                         .addressA(s_lookupTagIndex),
                         .dataInA(32'hFFFFFFF0),
                         .dataOutA(s_combinedTag1),
                         .clockB(clock),
                         .writeEnableB(s_updateWaysState[0]),
                         .addressB(s_rwTagIndex),
                         .dataInB(s_newCombinedTag),
                         .dataOutB(s_combinedSnoop1));

  sram512X32Dp tagRam2 ( .clockA(s_invertedClock),
                         .writeEnableA(s_flushInvalidateVector[1]),
                         .addressA(s_lookupTagIndex),
                         .dataInA(32'hFFFFFFF0),
                         .dataOutA(s_combinedTag2),
                         .clockB(clock),
                         .writeEnableB(s_updateWaysState[1]),
                         .addressB(s_rwTagIndex),
                         .dataInB(s_newCombinedTag),
                         .dataOutB(s_combinedSnoop2));

  sram512X32Dp tagRam3 ( .clockA(s_invertedClock),
                         .writeEnableA(s_flushInvalidateVector[2]),
                         .addressA(s_lookupTagIndex),
                         .dataInA(32'hFFFFFFF0),
                         .dataOutA(s_combinedTag3),
                         .clockB(clock),
                         .writeEnableB(s_updateWaysState[2]),
                         .addressB(s_rwTagIndex),
                         .dataInB(s_newCombinedTag),
                         .dataOutB(s_combinedSnoop3));

  sram512X32Dp tagRam4 ( .clockA(s_invertedClock),
                         .writeEnableA(s_flushInvalidateVector[3]),
                         .addressA(s_lookupTagIndex),
                         .dataInA(32'hFFFFFFF0),
                         .dataOutA(s_combinedTag4),
                         .clockB(clock),
                         .writeEnableB(s_updateWaysState[3]),
                         .addressB(s_rwTagIndex),
                         .dataInB(s_newCombinedTag),
                         .dataOutB(s_combinedSnoop4));

  /*
   *
   * Here the data related signals are defined
   *
   */
  reg s_busWriteStallReg;
  reg [1:0] s_dataSelectVector, s_addrBits, s_weSelectVector1, s_weSelectVector2, s_busAddrBits, s_cacheSelectVector;
  reg [3:0] s_weDataCacheVector;
  reg [8:0] s_rwDataIndex, s_lookupDataIndex;
  reg [31:0] s_dataToCache, s_selectedDataFromCache, s_selectedDataFromCacheReg;
  reg [31:0] s_stage1CacheData1Reg, s_stage1CacheData2Reg, s_stage1CacheData3Reg, s_stage1CacheData4Reg;
  reg s_selectedDataValidReg, s_dataForward0;
  wire [31:0] s_dataFromCache1, s_dataFromCache2, s_dataFromCache3, s_dataFromCache4;
  wire [31:0] s_cacheData1, s_cacheData2, s_cacheData3, s_cacheData4;
  wire s_busWriteStall = dataValidIn & busyIn;
  wire s_rwDataCache = s_weDataCacheVector != 4'b0 ||
                       (s_cacheStateReg == DO_WRITE &&
                        s_busWriteStall == 1'b0 &&
                        (s_busTransactionTypeReg == CACHE_LINE_WRITE_BACK ||
                         s_busTransactionTypeReg == SNOOPY_WRITE_BACK ||
                         s_busTransactionTypeReg == FLUSH_WRITE_BACK)) ? 1'b1 : 1'b0;
  wire [5:0] s_dataIndexAddr = (s_cacheWriteAction == 1'b1 || s_snarfActiveReg == 1'b1) ? s_stage2MemoryAddressReg[10:5] : s_busAddressReg[10:5];
  wire s_selectedDataValidNext = (s_busWriteStall == 1'b1) ? s_selectedDataValidReg :
                                 (s_cacheStateReg == DO_WRITE &&
                                  (s_busTransactionTypeReg == CACHE_LINE_WRITE_BACK ||
                                   s_busTransactionTypeReg == SNOOPY_WRITE_BACK ||
                                   s_busTransactionTypeReg == FLUSH_WRITE_BACK)) ? 1'b1 : 1'b0;
  wire [31:0] s_stage1CacheData1Next = (s_weDataCacheVector[0] == 1'b1 &&
                                        ((s_internalStall == 1'b0 && s_dataForward0 == 1'b1) ||
                                         (s_internalStall == 1'b1 && s_dataForward1 == 1'b1))) ? s_dataToCache :
                                       (s_internalStall == 1'b0) ? s_cacheData1 : s_stage1CacheData1Reg;
  wire [31:0] s_stage1CacheData2Next = (s_weDataCacheVector[1] == 1'b1 &&
                                        ((s_internalStall == 1'b0 && s_dataForward0 == 1'b1) ||
                                         (s_internalStall == 1'b1 && s_dataForward1 == 1'b1))) ? s_dataToCache :
                                       (s_internalStall == 1'b0) ? s_cacheData2 : s_stage1CacheData2Reg;
  wire [31:0] s_stage1CacheData3Next = (s_weDataCacheVector[2] == 1'b1 &&
                                        ((s_internalStall == 1'b0 && s_dataForward0 == 1'b1) ||
                                         (s_internalStall == 1'b1 && s_dataForward1 == 1'b1))) ? s_dataToCache :
                                       (s_internalStall == 1'b0) ? s_cacheData3 : s_stage1CacheData3Reg;
  wire [31:0] s_stage1CacheData4Next = (s_weDataCacheVector[3] == 1'b1 &&
                                        ((s_internalStall == 1'b0 && s_dataForward0 == 1'b1) ||
                                         (s_internalStall == 1'b1 && s_dataForward1 == 1'b1))) ? s_dataToCache :
                                       (s_internalStall == 1'b0) ? s_cacheData4 : s_stage1CacheData4Reg;
  wire [31:0] s_selectedData1 = (s_weDataCacheVector[0] == 1'b1 && s_dataForward1 == 1'b1) ? s_dataToCache : s_stage1CacheData1Reg;
  wire [31:0] s_selectedData2 = (s_weDataCacheVector[1] == 1'b1 && s_dataForward1 == 1'b1) ? s_dataToCache : s_stage1CacheData2Reg;
  wire [31:0] s_selectedData3 = (s_weDataCacheVector[2] == 1'b1 && s_dataForward1 == 1'b1) ? s_dataToCache : s_stage1CacheData3Reg;
  wire [31:0] s_selectedData4 = (s_weDataCacheVector[3] == 1'b1 && s_dataForward1 == 1'b1) ? s_dataToCache : s_stage1CacheData4Reg;
  wire [3:0] s_busWaySelect = (s_busTransactionTypeReg == SNOOPY_WRITE_BACK) ? s_snoopyWbWaySelectReg :
                              (s_busTransactionTypeReg == FLUSH_WRITE_BACK) ? s_flushWaySelectReg : s_stage2ReplacementWayReg;
  
  always @*
    begin
      s_rwDataIndex[2:0] <= (s_cacheWriteAction == 1'b1 && s_snarfActiveReg == 1'b0) ? s_stage2MemoryAddressReg[4:2] : s_wordBurstSelectReg;
      case (cacheSize)
        SIZE_8K : begin
                    s_lookupDataIndex  <= memoryAddress[10:2];
                    s_rwDataIndex[8:3] <= s_dataIndexAddr;
                    s_dataForward0     <= (s_rwDataIndex == memoryAddress[10:2]) ? 1'b1 : 1'b0;
                    s_dataForward1     <= (s_rwDataIndex == s_stage1MemoryAddressReg[10:2]) ? 1'b1 : 1'b0;
                    s_dataForward2     <= (s_rwDataIndex == s_stage2MemoryAddressReg[10:2]) ? 1'b1 : 1'b0;
                    s_addrBits         <= s_stage2MemoryAddressReg[12:11];
                    s_busAddrBits      <= s_busAddressReg[12:11];
                  end
        SIZE_4K : begin
                    s_lookupDataIndex  <= { 1'b0, memoryAddress[9:2] };
                    s_rwDataIndex[8:3] <= { 1'b0, s_dataIndexAddr[4:0] };
                    s_dataForward0     <= (s_rwDataIndex[7:0] == memoryAddress[9:2]) ? 1'b1 : 1'b0;
                    s_dataForward1     <= (s_rwDataIndex[7:0] == s_stage1MemoryAddressReg[9:2]) ? 1'b1 : 1'b0;
                    s_dataForward2     <= (s_rwDataIndex[7:0] == s_stage2MemoryAddressReg[9:2]) ? 1'b1 : 1'b0;
                    s_addrBits         <= s_stage2MemoryAddressReg[11:10];
                    s_busAddrBits      <= s_busAddressReg[11:10];
                  end
        SIZE_2K : begin
                    s_lookupDataIndex  <= { 2'd0 , memoryAddress[8:2] };
                    s_rwDataIndex[8:3] <= { 2'd0 , s_dataIndexAddr[3:0] };
                    s_dataForward0     <= (s_rwDataIndex[6:0] == memoryAddress[8:2]) ? 1'b1 : 1'b0;
                    s_dataForward1     <= (s_rwDataIndex[6:0] == s_stage1MemoryAddressReg[8:2]) ? 1'b1 : 1'b0;
                    s_dataForward2     <= (s_rwDataIndex[6:0] == s_stage2MemoryAddressReg[8:2]) ? 1'b1 : 1'b0;
                    s_addrBits         <= s_stage2MemoryAddressReg[10:9];
                    s_busAddrBits      <= s_busAddressReg[10:9];
                  end
        default : begin
                    s_lookupDataIndex  <= { 3'd0 , memoryAddress[7:2] };
                    s_rwDataIndex[8:3] <= { 3'd0 , s_dataIndexAddr[2:0] };
                    s_dataForward0     <= (s_rwDataIndex[5:0] == memoryAddress[7:2]) ? 1'b1 : 1'b0;
                    s_dataForward1     <= (s_rwDataIndex[5:0] == s_stage1MemoryAddressReg[7:2]) ? 1'b1 : 1'b0;
                    s_dataForward2     <= (s_rwDataIndex[5:0] == s_stage2MemoryAddressReg[7:2]) ? 1'b1 : 1'b0;
                    s_addrBits         <= s_stage2MemoryAddressReg[9:8];
                    s_busAddrBits      <= s_busAddressReg[9:8];
                  end
      endcase
    end

  always @*
    case (numberOfWays)
      FOUR_WAY_SET_ASSOCIATIVE : begin
                                   s_dataSelectVector     <= {s_hit4 | s_hit3 , s_hit4 | s_hit2};
                                   s_weSelectVector1      <= 2'b00;
                                   s_weSelectVector2      <= 2'b00;
                                   s_cacheSelectVector[1] <= s_busWaySelect[3] | s_busWaySelect[2];
                                   s_cacheSelectVector[0] <= s_busWaySelect[3] | s_busWaySelect[1];
                                 end
      TWO_WAY_SET_ASSOCIATIVE  : begin
                                   s_dataSelectVector[1] <= s_hit2;
                                   case (cacheSize)
                                     SIZE_8K : s_dataSelectVector[0] <= s_stage1MemoryAddressReg[11];
                                     SIZE_4K : s_dataSelectVector[0] <= s_stage1MemoryAddressReg[10];
                                     SIZE_2K : s_dataSelectVector[0] <= s_stage1MemoryAddressReg[9];
                                     default : s_dataSelectVector[0] <= s_stage1MemoryAddressReg[8];
                                   endcase
                                   s_weSelectVector1[1]   <= s_stage2ReplacementWayReg[1];
                                   s_weSelectVector1[0]   <= s_addrBits[0];
                                   s_weSelectVector2[1]   <= s_stage2Hit2Reg;
                                   s_weSelectVector2[0]   <= s_addrBits[0];
                                   s_cacheSelectVector[1] <= s_busWaySelect[1];
                                   s_cacheSelectVector[0] <= s_busAddrBits[0];
                                 end
      default                  : begin
                                   case (cacheSize)
                                     SIZE_8K : s_dataSelectVector <= s_stage1MemoryAddressReg[12:11];
                                     SIZE_4K : s_dataSelectVector <= s_stage1MemoryAddressReg[11:10];
                                     SIZE_2K : s_dataSelectVector <= s_stage1MemoryAddressReg[10:9];
                                     default : s_dataSelectVector <= s_stage1MemoryAddressReg[9:8];
                                   endcase
                                   s_weSelectVector1   <= s_addrBits;
                                   s_weSelectVector2   <= s_addrBits;
                                   s_cacheSelectVector <= s_busAddrBits;
                                 end
    endcase
  
  always @*
    if (s_busDataInValidReg == 1'b1 &&
        (s_busTransactionTypeReg == CACHE_LINE_LOAD || s_snarfActiveReg == 1'b1))
      begin
        case (numberOfWays)
          FOUR_WAY_SET_ASSOCIATIVE : s_weDataCacheVector <= s_stage2ReplacementWayReg;
          default                  : case (s_weSelectVector1)
                                       2'b00   : s_weDataCacheVector <= 4'h1;
                                       2'b01   : s_weDataCacheVector <= 4'h2;
                                       2'b10   : s_weDataCacheVector <= 4'h4;
                                       default : s_weDataCacheVector <= 4'h8;
                                     endcase
        endcase
      end
    else if (s_cacheWriteAction == 1'b1)
      begin
        case (numberOfWays)
          FOUR_WAY_SET_ASSOCIATIVE : s_weDataCacheVector <= {s_stage2Hit4Reg, s_stage2Hit3Reg, s_stage2Hit2Reg, s_stage2Hit1Reg};
          default                  : case (s_weSelectVector2)
                                       2'b00   : s_weDataCacheVector <= 4'h1;
                                       2'b01   : s_weDataCacheVector <= 4'h2;
                                       2'b10   : s_weDataCacheVector <= 4'h4;
                                       default : s_weDataCacheVector <= 4'h8;
                                     endcase
        endcase
      end
    else s_weDataCacheVector <= 4'h0;
  
  always @*
    case (s_dataSelectVector)
      2'b00   : s_selectedCacheData <= s_selectedData1;
      2'b01   : s_selectedCacheData <= s_selectedData2;
      2'b10   : s_selectedCacheData <= s_selectedData3;
      default : s_selectedCacheData <= s_selectedData4;
    endcase
    
  always @*
    case (s_cacheSelectVector)
      2'b00   : s_selectedDataFromCache <= s_dataFromCache1;
      2'b01   : s_selectedDataFromCache <= s_dataFromCache2;
      2'b10   : s_selectedDataFromCache <= s_dataFromCache3;
      default : s_selectedDataFromCache <= s_dataFromCache4;
    endcase

  always @*
    if (s_cacheWriteAction == 1'b1 && s_snarfActiveReg == 1'b0)
      begin
        s_dataToCache[31:24] <= (s_stage2DataByteEnableReg[3] == 1'b1) ? s_stage2DataFromCoreReg[31:24] : s_stage2DataToCoreReg[31:24];
        s_dataToCache[23:16] <= (s_stage2DataByteEnableReg[2] == 1'b1) ? s_stage2DataFromCoreReg[23:16] : s_stage2DataToCoreReg[23:16];
        s_dataToCache[15:8]  <= (s_stage2DataByteEnableReg[1] == 1'b1) ? s_stage2DataFromCoreReg[15:8] : s_stage2DataToCoreReg[15:8];
        s_dataToCache[7:0]   <= (s_stage2DataByteEnableReg[0] == 1'b1) ? s_stage2DataFromCoreReg[7:0] : s_stage2DataToCoreReg[7:0];
      end
    else s_dataToCache <= s_busDataInReg;
  
  always @ (posedge clock)
    begin
      s_busWriteStallReg         <= ~reset & s_busWriteStall;
      s_selectedDataFromCacheReg <= (s_busWriteStallReg == 1'b0) ? s_selectedDataFromCache : s_selectedDataFromCacheReg;
      s_selectedDataValidReg     <= s_selectedDataValidNext;
      s_stage1CacheData1Reg      <= s_stage1CacheData1Next;
      s_stage1CacheData2Reg      <= s_stage1CacheData2Next;
      s_stage1CacheData3Reg      <= s_stage1CacheData3Next;
      s_stage1CacheData4Reg      <= s_stage1CacheData4Next;
    end
  
  
  sram512X32Dp dataRam1 ( .clockA(s_invertedClock),
                          .writeEnableA(1'b0),
                          .addressA(s_lookupDataIndex[8:0]),
                          .dataInA({32{1'b0}}),
                          .dataOutA(s_cacheData1),
                          .clockB(clock),
                          .writeEnableB(s_weDataCacheVector[0] & s_rwDataCache),
                          .addressB(s_rwDataIndex[8:0]),
                          .dataInB(s_dataToCache),
                          .dataOutB(s_dataFromCache1));

  sram512X32Dp dataRam2 ( .clockA(s_invertedClock),
                          .writeEnableA(1'b0),
                          .addressA(s_lookupDataIndex[8:0]),
                          .dataInA({32{1'b0}}),
                          .dataOutA(s_cacheData2),
                          .clockB(clock),
                          .writeEnableB(s_weDataCacheVector[1] & s_rwDataCache),
                          .addressB(s_rwDataIndex[8:0]),
                          .dataInB(s_dataToCache),
                          .dataOutB(s_dataFromCache2));

  sram512X32Dp dataRam3 ( .clockA(s_invertedClock),
                          .writeEnableA(1'b0),
                          .addressA(s_lookupDataIndex[8:0]),
                          .dataInA({32{1'b0}}),
                          .dataOutA(s_cacheData3),
                          .clockB(clock),
                          .writeEnableB(s_weDataCacheVector[2] & s_rwDataCache),
                          .addressB(s_rwDataIndex[8:0]),
                          .dataInB(s_dataToCache),
                          .dataOutB(s_dataFromCache3));

  sram512X32Dp dataRam4 ( .clockA(s_invertedClock),
                          .writeEnableA(1'b0),
                          .addressA(s_lookupDataIndex[8:0]),
                          .dataInA({32{1'b0}}),
                          .dataOutA(s_cacheData4),
                          .clockB(clock),
                          .writeEnableB(s_weDataCacheVector[3] & s_rwDataCache),
                          .addressB(s_rwDataIndex[8:0]),
                          .dataInB(s_dataToCache),
                          .dataOutB(s_dataFromCache4));

  /*
   *
   * Here the replacement policy related signals are defined
   *
   */
  reg [4:0] s_newPlru;
  reg [3:0] s_replacementWay;
  reg [1:0] s_newLru1, s_newLru2, s_newLru3, s_newLru4, s_newFifo, s_lruSelect;
  reg [4:0] s_stage1PlruReg, s_stage2PlruReg;
  reg [1:0] s_stage1Lru1Reg, s_stage1Lru2Reg, s_stage1Lru3Reg, s_stage1Lru4Reg, s_stage1FifoReg;
  reg [1:0] s_stage2Lru1Reg, s_stage2Lru2Reg, s_stage2Lru3Reg, s_stage2Lru4Reg, s_stage2FifoReg;
  reg [23:0] s_stage2SelectedTagReg;
  wire [31:0] s_combinedPolicy;
  wire [31:0] s_newCombinedPolicy = {{17{1'b0}}, s_newPlru, s_newLru4, s_newLru3, s_newLru2, s_newLru1, s_newFifo};
  wire [1:0] s_policySelect;
  wire s_weNewPolicy = ((s_cacheStateReg == UPDATE_TAGS && s_busTransactionTypeReg == CACHE_LINE_LOAD) ||
                        s_cacheWriteAction == 1'b1 ||
                        s_cacheReadAction == 1'b1) ? 1'b1 : 1'b0;
  wire [4:0] s_stage1PlruNext = (((s_internalStall == 1'b0 && s_rwTagIndex == s_lookupTagIndex) ||
                                  (s_internalStall == 1'b1 && s_rwTagIndex == s_forwardTagIndex)) &&
                                 s_weNewPolicy == 1'b1) ? s_newPlru : 
                                (s_internalStall == 1'b0) ? s_combinedPolicy[14:10] : s_stage1PlruReg;
  wire [1:0] s_stage1Lru1Next = (((s_internalStall == 1'b0 && s_rwTagIndex == s_lookupTagIndex) ||
                                  (s_internalStall == 1'b1 && s_rwTagIndex == s_forwardTagIndex)) &&
                                 s_weNewPolicy == 1'b1) ? s_newLru1 : 
                                (s_internalStall == 1'b0) ? s_combinedPolicy[3:2] : s_stage1Lru1Reg;
  wire [1:0] s_stage1Lru2Next = (((s_internalStall == 1'b0 && s_rwTagIndex == s_lookupTagIndex) ||
                                  (s_internalStall == 1'b1 && s_rwTagIndex == s_forwardTagIndex)) &&
                                 s_weNewPolicy == 1'b1) ? s_newLru2 : 
                                (s_internalStall == 1'b0) ? s_combinedPolicy[5:4] : s_stage1Lru2Reg;
  wire [1:0] s_stage1Lru3Next = (((s_internalStall == 1'b0 && s_rwTagIndex == s_lookupTagIndex) ||
                                  (s_internalStall == 1'b1 && s_rwTagIndex == s_forwardTagIndex)) &&
                                 s_weNewPolicy == 1'b1) ? s_newLru3 : 
                                (s_internalStall == 1'b0) ? s_combinedPolicy[7:6] : s_stage1Lru3Reg;
  wire [1:0] s_stage1Lru4Next = (((s_internalStall == 1'b0 && s_rwTagIndex == s_lookupTagIndex) ||
                                  (s_internalStall == 1'b1 && s_rwTagIndex == s_forwardTagIndex)) &&
                                 s_weNewPolicy == 1'b1) ? s_newLru4 : 
                                (s_internalStall == 1'b0) ? s_combinedPolicy[9:8] : s_stage1Lru4Reg;
  wire [1:0] s_stage1FifoNext = (((s_internalStall == 1'b0 && s_rwTagIndex == s_lookupTagIndex) ||
                                  (s_internalStall == 1'b1 && s_rwTagIndex == s_forwardTagIndex)) &&
                                 s_weNewPolicy == 1'b1) ? s_newFifo : 
                                (s_internalStall == 1'b0) ? s_combinedPolicy[1:0] : s_stage1FifoReg;
  wire [4:0] s_stage2PlruNext = (((s_internalStall == 1'b0 && s_rwTagIndex == s_lookupTagIndex) ||
                                  (s_internalStall == 1'b1 && s_rwTagIndex == s_forwardTagIndex)) &&
                                 s_weNewPolicy == 1'b1) ? s_newPlru : 
                                (s_internalStall == 1'b0) ? s_stage1PlruReg : s_stage2PlruReg;
  wire [1:0] s_stage2Lru1Next = (((s_internalStall == 1'b0 && s_rwTagIndex == s_lookupTagIndex) ||
                                  (s_internalStall == 1'b1 && s_rwTagIndex == s_forwardTagIndex)) &&
                                 s_weNewPolicy == 1'b1) ? s_newLru1 : 
                                (s_internalStall == 1'b0) ? s_stage1Lru1Reg : s_stage2Lru1Reg;
  wire [1:0] s_stage2Lru2Next = (((s_internalStall == 1'b0 && s_rwTagIndex == s_lookupTagIndex) ||
                                  (s_internalStall == 1'b1 && s_rwTagIndex == s_forwardTagIndex)) &&
                                 s_weNewPolicy == 1'b1) ? s_newLru2 : 
                                (s_internalStall == 1'b0) ? s_stage1Lru2Reg : s_stage2Lru2Reg;
  wire [1:0] s_stage2Lru3Next = (((s_internalStall == 1'b0 && s_rwTagIndex == s_lookupTagIndex) ||
                                  (s_internalStall == 1'b1 && s_rwTagIndex == s_forwardTagIndex)) &&
                                 s_weNewPolicy == 1'b1) ? s_newLru3 : 
                                (s_internalStall == 1'b0) ? s_stage1Lru3Reg : s_stage2Lru3Reg;
  wire [1:0] s_stage2Lru4Next = (((s_internalStall == 1'b0 && s_rwTagIndex == s_lookupTagIndex) ||
                                  (s_internalStall == 1'b1 && s_rwTagIndex == s_forwardTagIndex)) &&
                                 s_weNewPolicy == 1'b1) ? s_newLru4 : 
                                (s_internalStall == 1'b0) ? s_stage1Lru4Reg : s_stage2Lru4Reg;
  wire [1:0] s_stage2FifoNext = (((s_internalStall == 1'b0 && s_rwTagIndex == s_lookupTagIndex) ||
                                  (s_internalStall == 1'b1 && s_rwTagIndex == s_forwardTagIndex)) &&
                                 s_weNewPolicy == 1'b1) ? s_newFifo : 
                                (s_internalStall == 1'b0) ? s_stage1FifoReg : s_stage2FifoReg;

  assign s_policySelect[1] = s_replacementWay[3] | s_replacementWay[2];
  assign s_policySelect[0] = s_replacementWay[3] | s_replacementWay[1];

  always @*
    case (replacementPolicy)
      FIFO_REPLACEMENT : case (s_stage1FifoReg)
                           2'b00   : s_replacementWay <= 4'h1;
                           2'b01   : s_replacementWay <= 4'h2;
                           2'b10   : s_replacementWay <= 4'h4;
                           default : s_replacementWay <= 4'h8;
                         endcase
      PLRU_REPLACEMENT : if (s_stage1PlruReg[4] == 1'b1)
                           begin
                             s_replacementWay[3:2] <= 2'b00;
                             s_replacementWay[1:0] <= (s_stage1PlruReg[1:0] == 2'b00 || s_stage1PlruReg[1:0] == 2'b11) ? 2'b01 : ~s_stage1PlruReg[1:0];
                           end
                         else
                           begin
                             s_replacementWay[1:0] <= 2'b00;
                             s_replacementWay[3:2] <= (s_stage1PlruReg[3:2] == 2'b00 || s_stage1PlruReg[3:2] == 2'b11) ? 2'b01 : ~s_stage1PlruReg[3:2];
                           end
      default          : s_replacementWay <= ((s_stage1Lru1Reg <= s_stage1Lru2Reg) & (s_stage1Lru1Reg <= s_stage1Lru3Reg) & (s_stage1Lru1Reg <= s_stage1Lru4Reg)) ? 4'h1 :
                                             ((s_stage1Lru2Reg <= s_stage1Lru1Reg) & (s_stage1Lru2Reg <= s_stage1Lru3Reg) & (s_stage1Lru2Reg <= s_stage1Lru4Reg)) ? 4'h2 :
                                             ((s_stage1Lru3Reg <= s_stage1Lru1Reg) & (s_stage1Lru3Reg <= s_stage1Lru2Reg) & (s_stage1Lru3Reg <= s_stage1Lru4Reg)) ? 4'h4 : 4'h8;
    endcase
  
  always @*
    if (s_cacheStateReg == UPDATE_TAGS)
      begin
        s_lruSelect <= 2'b00;
        s_newLru1   <= s_stage2Lru1Reg;
        s_newLru2   <= s_stage2Lru2Reg;
        s_newLru3   <= s_stage2Lru3Reg;
        s_newLru4   <= s_stage2Lru4Reg;
        s_newPlru   <= s_stage2PlruReg;
        case (numberOfWays)
          FOUR_WAY_SET_ASSOCIATIVE : begin
                                       s_newFifo      <= s_stage2FifoReg + 2'd1;
                                     end
          TWO_WAY_SET_ASSOCIATIVE  : begin
                                       s_newFifo[1] <= 1'b0;
                                       s_newFifo[0] <= ~s_stage2FifoReg[0];
                                     end
          default                  : begin
                                       s_newFifo <= 2'b00;
                                     end
        endcase
      end
    else 
      begin
        s_newFifo   <= s_stage2FifoReg;
        s_lruSelect[1] <= s_stage2Hit4Reg | s_stage2Hit3Reg;
        s_lruSelect[0] <= s_stage2Hit4Reg | s_stage2Hit2Reg;
        case (numberOfWays)
          FOUR_WAY_SET_ASSOCIATIVE : begin
                                       s_newPlru[4]   <= s_stage2Hit4Reg | s_stage2Hit3Reg;
                                       s_newPlru[3:0] <= (s_stage2Hit4Reg == 1'b1 || s_stage2Hit3Reg == 1'b1) ? {s_stage2Hit4Reg, s_stage2Hit3Reg, s_stage2PlruReg[1:0]}
                                                                                                              : {s_stage2PlruReg[3:2], s_stage2Hit2Reg, s_stage2Hit1Reg};
                                       case (s_lruSelect)
                                         2'b00    : begin
                                                      s_newLru1 <= 2'b11;
                                                      s_newLru2 <= (s_stage2Lru2Reg > s_stage2Lru1Reg) ? s_stage2Lru2Reg - 2'd1 : s_stage2Lru2Reg;
                                                      s_newLru3 <= (s_stage2Lru3Reg > s_stage2Lru1Reg) ? s_stage2Lru3Reg - 2'd1 : s_stage2Lru3Reg;
                                                      s_newLru4 <= (s_stage2Lru4Reg > s_stage2Lru1Reg) ? s_stage2Lru4Reg - 2'd1 : s_stage2Lru4Reg;
                                                    end
                                         2'b01    : begin
                                                      s_newLru1 <= (s_stage2Lru1Reg > s_stage2Lru2Reg) ? s_stage2Lru1Reg - 2'd1 : s_stage2Lru1Reg;
                                                      s_newLru2 <= 2'b11;
                                                      s_newLru3 <= (s_stage2Lru3Reg > s_stage2Lru2Reg) ? s_stage2Lru3Reg - 2'd1 : s_stage2Lru3Reg;
                                                      s_newLru4 <= (s_stage2Lru4Reg > s_stage2Lru2Reg) ? s_stage2Lru4Reg - 2'd1 : s_stage2Lru4Reg;
                                                    end
                                         2'b10    : begin
                                                      s_newLru1 <= (s_stage2Lru1Reg > s_stage2Lru3Reg) ? s_stage2Lru1Reg - 2'd1 : s_stage2Lru1Reg;
                                                      s_newLru2 <= (s_stage2Lru2Reg > s_stage2Lru3Reg) ? s_stage2Lru2Reg - 2'd1 : s_stage2Lru2Reg;
                                                      s_newLru3 <= 2'b11;
                                                      s_newLru4 <= (s_stage2Lru4Reg > s_stage2Lru3Reg) ? s_stage2Lru4Reg - 2'd1 : s_stage2Lru4Reg;
                                                    end
                                         default : begin
                                                      s_newLru1 <= (s_stage2Lru1Reg > s_stage2Lru4Reg) ? s_stage2Lru1Reg - 2'd1 : s_stage2Lru1Reg;
                                                      s_newLru2 <= (s_stage2Lru2Reg > s_stage2Lru4Reg) ? s_stage2Lru2Reg - 2'd1 : s_stage2Lru2Reg;
                                                      s_newLru3 <= (s_stage2Lru3Reg > s_stage2Lru4Reg) ? s_stage2Lru3Reg - 2'd1 : s_stage2Lru3Reg;
                                                      s_newLru4 <= 2'b11;
                                                    end
                                       endcase
                                     end
          TWO_WAY_SET_ASSOCIATIVE  : begin
                                       s_newPlru[4:2] <= 3'b100;
                                       s_newPlru[1:0] <= {s_stage2Hit2Reg, s_stage2Hit1Reg};
                                       s_newLru1      <= (s_stage2Hit1Reg == 1'b1) ? 2'b11 : 2'b00;
                                       s_newLru2      <= (s_stage2Hit1Reg == 1'b1) ? 2'b00 : 2'b11;
                                       s_newLru3      <= 2'b11;
                                       s_newLru4      <= 2'b11;
                                     end
          default                  : begin
                                       s_newPlru <= 5'b10010;
                                       s_newLru1 <= 2'b00;
                                       s_newLru2 <= 2'b11;
                                       s_newLru3 <= 2'b11;
                                       s_newLru4 <= 2'b11;
                                     end
        endcase
      end

  always @(posedge clock)
    begin
      s_stage1PlruReg           <= s_stage1PlruNext;
      s_stage1Lru1Reg           <= s_stage1Lru1Next;
      s_stage1Lru2Reg           <= s_stage1Lru2Next;
      s_stage1Lru3Reg           <= s_stage1Lru3Next;
      s_stage1Lru4Reg           <= s_stage1Lru4Next;
      s_stage1FifoReg           <= s_stage1FifoNext;
      s_stage2PlruReg           <= s_stage2PlruNext;
      s_stage2Lru1Reg           <= s_stage2Lru1Next;
      s_stage2Lru2Reg           <= s_stage2Lru2Next;
      s_stage2Lru3Reg           <= s_stage2Lru3Next;
      s_stage2Lru4Reg           <= s_stage2Lru4Next;
      s_stage2FifoReg           <= s_stage2FifoNext;
      if (s_internalStall == 1'b0)
        begin
          s_stage2ReplacementWayReg <= s_replacementWay;
          case (s_policySelect)
            2'b00   : s_stage2SelectedTagReg <= s_stage1Tag1Reg;
            2'b01   : s_stage2SelectedTagReg <= s_stage1Tag2Reg;
            2'b10   : s_stage2SelectedTagReg <= s_stage1Tag3Reg;
            default : s_stage2SelectedTagReg <= s_stage1Tag4Reg;
          endcase
        end
    end
      
    sram512X32Dp policyRam ( .clockA(s_invertedClock),
                             .writeEnableA(s_flushInvalidate),
                             .addressA(s_lookupTagIndex),
                             .dataInA({32{1'b0}}),
                             .dataOutA(s_combinedPolicy),
                             .clockB(clock),
                             .writeEnableB(s_weNewPolicy),
                             .addressB(s_rwTagIndex),
                             .dataInB(s_newCombinedPolicy),
                             .dataOutB());

  /*
   *
   * Here the bus related signals are defined
   *
   */
  reg s_beginTransactionReg, s_forceControlReg, s_dataValidReg, s_endTransactionReg, s_forceDataReg;
  reg s_readnWriteReg;
  reg [31:0] s_busDataOutReg, s_writeBackAddress, s_busAddressNext;
  reg [3:0] s_byteEnablesReg, s_myBurstCountReg;
  reg [7:0] s_burstSizeReg;
  reg s_doStore, s_busErrorReg;
  
  wire s_weBusDataOut = (s_busWriteStall == 1'b0 &&
                         (s_selectedDataValidReg == 1'b1 ||
                          (s_cacheStateReg == DO_WRITE &&
                           s_busTransactionTypeReg != CACHE_LINE_WRITE_BACK &&
                           s_busTransactionTypeReg != SNOOPY_WRITE_BACK &&
                           s_busTransactionTypeReg != FLUSH_WRITE_BACK))) ? 1'b1 : 1'b0;
  wire [31:0] s_busDataOutNext = (s_weBusDataOut == 1'b0) ? s_busDataOutReg :
                                 (s_busTransactionTypeReg != CACHE_LINE_WRITE_BACK &&
                                  s_busTransactionTypeReg != SNOOPY_WRITE_BACK &&
                                  s_busTransactionTypeReg != FLUSH_WRITE_BACK) ? s_stage2DataFromCoreReg : 
                                 (s_busWriteStallReg == 1'b1) ? s_selectedDataFromCacheReg : s_selectedDataFromCache;
  wire s_dataValidNext = (s_busWriteStall == 1'b1 ||
                          s_selectedDataValidReg == 1'b1 ||
                          (s_cacheStateReg == DO_WRITE &&
                           s_busTransactionTypeReg != CACHE_LINE_WRITE_BACK &&
                           s_busTransactionTypeReg != SNOOPY_WRITE_BACK &&
                           s_busTransactionTypeReg != FLUSH_WRITE_BACK)) ? 1'b1 : 1'b0;
  wire s_beginTransactionNext = ((s_cacheStateReg == INIT_TRANSACTION && s_busTransactionTypeReg != NOOP) ||
                                 s_cacheStateReg == ATOMIC_INIT) ? 1'b1 : 1'b0;
  wire s_endTransactionNext = (s_cacheStateReg == END_TRANSACTION || s_cacheStateReg == BACKOFF ||
                               ((s_busTransactionTypeReg == CACHE_LINE_WRITE_BACK ||
                                 s_busTransactionTypeReg == SNOOPY_WRITE_BACK ||
                                 s_busTransactionTypeReg == FLUSH_WRITE_BACK) &&
                                s_busWriteStall == 1'b0 &&
                                s_dataValidReg == 1'b1 &&
                                s_selectedDataValidReg == 1'b0)) ? 1'b1 : 1'b0;
  wire s_weBusRegs = ((s_cacheStateReg == INIT_TRANSACTION && s_busTransactionTypeReg != NOOP) ||
                      s_cacheStateReg == ATOMIC_INIT) ? 1'b1 : 1'b0;
  wire s_readnWriteNext = (s_weBusRegs == 1'b0 ||
                           (s_cacheStateReg == ATOMIC_INIT && s_doStore == 1'b1) ||
                           s_busTransactionTypeReg == UNCACHEABLE_WRITE ||
                           s_busTransactionTypeReg == WRITE_THROUGH ||
                           s_busTransactionTypeReg == CACHE_LINE_WRITE_BACK ||
                           s_busTransactionTypeReg == FLUSH_WRITE_BACK ||
                           s_busTransactionTypeReg == SNOOPY_WRITE_BACK) ? 1'b0 : 1'b1;
  wire [7:0] s_burstSizeNext = (s_weBusRegs == 1'b0) ? {8{1'b0}} : {{5{1'b0}}, s_busTransactionLengthReg};
  wire [3:0] s_byteEnablesNext = (s_weBusRegs == 1'b0) ? 4'h0 :
                           (s_busTransactionTypeReg == CACHE_LINE_WRITE_BACK ||
                            s_busTransactionTypeReg == CACHE_LINE_LOAD ||
                            s_busTransactionTypeReg == FLUSH_WRITE_BACK ||
                            s_busTransactionTypeReg == SNOOPY_WRITE_BACK) ? 4'hF : s_stage2DataByteEnableReg;
  wire s_busErrorNext = (busAccessGranted == 1'b1 || reset == 1'b1) ? 1'b0 : busErrorIn | s_busErrorReg;
  wire [3:0] s_expectedBurstSize = {1'b0,s_busTransactionLengthReg} + 4'd1;
  wire s_forceControlNext = (endTransactionIn == 1'b1 || reset == 1'b1) ? 1'b0 : s_forceControlReg | busAccessGranted;
  wire s_forceDataNext = (endTransactionIn == 1'b1 || reset == 1'b1) ? 1'b0 : (beginTransactionIn == 1'b1 && readNotWriteIn == 1'b0) ? s_forceControlReg : s_forceDataReg;
  wire [3:0] s_myBurstCountNext = (busAccessGranted == 1'b1) ? 4'h0 :
                                  (s_myBurstCountReg != 4'hF &&
                                   dataValidIn == 1'b1 &&
                                   busyIn == 1'b0 &&
                                   s_forceControlReg == 1'b1) ? s_myBurstCountReg + 4'd1 : s_myBurstCountReg;
  wire [2:0] s_wordBurstSelectNext = (busAccessGranted == 1'b1 || s_snarfActiveNext == 1'b1) ? 3'b000 :
                                     ((s_busWriteStall == 1'b0 && s_cacheStateReg == DO_WRITE) ||
                                      s_busDataInValidReg == 1'b1) ? s_wordBurstSelectReg + 3'd1 : s_wordBurstSelectReg;
  wire [31:0] s_busDataInNext = (dataValidIn == 1'b1 && busyIn == 1'b0 &&
                                 ((s_forceControlReg == 1'b1 && s_forceDataReg == 1'b0) ||
                                  (s_snarfActiveNext == 1'b1 || s_snarfActiveReg == 1'b1))) ? addressDataIn : s_busDataInReg;
  wire s_busDataInValidNext = (dataValidIn == 1'b1 && busyIn == 1'b0 &&
                               ((s_forceControlReg == 1'b1 && s_forceDataReg == 1'b0) ||
                                (s_snarfActiveNext == 1'b1 || s_snarfActiveReg == 1'b1))) ? 1'b1 : 1'b0;
                            
                          
  
  assign requestBus = (s_cacheStateReg == REQUEST_THE_BUS || s_cacheStateReg == ATOMIC_REQUEST ||
                       (s_cacheStateReg == WAIT_READ_BURST &&
                        (s_busTransactionTypeReg == ATOMIC_SWAP || s_busTransactionTypeReg == ATOMIC_CAS))) ? 1'b1 : 1'b0;
  assign addressDataOut = (s_beginTransactionReg == 1'b1) ? s_busAddressReg : 
                          (s_forceControlReg == 1'b1 && s_dataValidReg == 1'b1) ? s_busDataOutReg : {32{1'b0}};
  assign beginTransactionOut = s_beginTransactionReg;
  assign endTransactionOut = s_forceControlReg & s_endTransactionReg;
  assign byteEnablesOut = s_byteEnablesReg;
  assign readNotWriteOut = s_readnWriteReg;
  assign dataValidOut = s_dataValidReg & s_forceControlReg;
  assign burstSizeOut = s_burstSizeReg;
  assign s_busError = ((s_busErrorReg == 1'b1 || s_expectedBurstSize != s_myBurstCountReg) &&
                       (s_cacheStateReg == RELEASE || s_cacheStateReg == UPDATE_TAGS)) ? 1'b1 : 1'b0;
  
  always @*
    if (s_busTransactionTypeReg == ATOMIC_SWAP) s_doStore <= 1'b1;
    else if (s_busTransactionTypeReg == ATOMIC_CAS)
      case (s_busAddressReg[1:0])
        2'b00   : s_doStore <= (s_stage2DataToCoreReg[7:0] == s_stage2MemCompValueReg) ? 1'b1 : 1'b0;
        2'b01   : s_doStore <= (s_stage2DataToCoreReg[15:8] == s_stage2MemCompValueReg) ? 1'b1 : 1'b0;
        2'b10   : s_doStore <= (s_stage2DataToCoreReg[23:16] == s_stage2MemCompValueReg) ? 1'b1 : 1'b0;
        default : s_doStore <= (s_stage2DataToCoreReg[31:24] == s_stage2MemCompValueReg) ? 1'b1 : 1'b0;
      endcase
    else s_doStore <= 1'b0;
  
  always @*
    case (s_cacheConfiguration)
      FOUR_WAY_SET_ASSOCIATIVE_1K : s_writeBackAddress <= {s_stage2SelectedTagReg[23:0],s_stage2MemoryAddressReg[7:5], {5{1'b0}}};
      FOUR_WAY_SET_ASSOCIATIVE_2K,
      TWO_WAY_SET_ASSOCIATIVE_1K  : s_writeBackAddress <= {s_stage2SelectedTagReg[22:0],s_stage2MemoryAddressReg[8:5], {5{1'b0}}};
      FOUR_WAY_SET_ASSOCIATIVE_4K,
      TWO_WAY_SET_ASSOCIATIVE_2K,
      DIRECT_MAPPED_1K            : s_writeBackAddress <= {s_stage2SelectedTagReg[21:0],s_stage2MemoryAddressReg[9:5], {5{1'b0}}};
      FOUR_WAY_SET_ASSOCIATIVE_8K,
      TWO_WAY_SET_ASSOCIATIVE_4K,
      DIRECT_MAPPED_2K            : s_writeBackAddress <= {s_stage2SelectedTagReg[20:0],s_stage2MemoryAddressReg[10:5], {5{1'b0}}};
      TWO_WAY_SET_ASSOCIATIVE_8K,
      DIRECT_MAPPED_4K            : s_writeBackAddress <= {s_stage2SelectedTagReg[19:0],s_stage2MemoryAddressReg[11:5], {5{1'b0}}};
      default                     : s_writeBackAddress <= {s_stage2SelectedTagReg[18:0],s_stage2MemoryAddressReg[12:5], {5{1'b0}}};
    endcase
  
  always @*
    if (s_weBusRegs == 1'b0) s_busAddressNext <= s_busAddressReg;
    else case (s_busTransactionTypeReg)
      CACHE_LINE_WRITE_BACK : s_busAddressNext <= s_writeBackAddress;
      CACHE_LINE_LOAD       : s_busAddressNext <= {s_stage2MemoryAddressReg[31:5], {5{1'b0}}};
      SNOOPY_WRITE_BACK     : s_busAddressNext <= s_snoopyWbAddress;
      FLUSH_WRITE_BACK      : s_busAddressNext <= s_flushWbAddressReg;
      default               : s_busAddressNext <= s_stage2MemoryAddressReg;
    endcase
  
  always @ (posedge clock)
    begin
      s_busDataOutReg       <= s_busDataOutNext;
      s_dataValidReg        <= s_dataValidNext;
      s_beginTransactionReg <= s_beginTransactionNext;
      s_endTransactionReg   <= s_endTransactionNext;
      s_readnWriteReg       <= s_readnWriteNext;
      s_burstSizeReg        <= s_burstSizeNext;
      s_byteEnablesReg      <= s_byteEnablesNext;
      s_busAddressReg       <= s_busAddressNext;
      s_busErrorReg         <= s_busErrorNext;
      s_forceControlReg     <= s_forceControlNext;
      s_forceDataReg        <= s_forceDataNext;
      s_myBurstCountReg     <= s_myBurstCountNext;
      s_wordBurstSelectReg  <= s_wordBurstSelectNext;
      s_busDataInReg        <= s_busDataInNext;
      s_busDataInValidReg   <= s_busDataInValidNext;
    end

  /*
   *
   * Here some generic control signals are defined
   *
   */
  reg s_writeThroughDoneReg;
  reg [10:0] s_waitWriteBackTimeOutReg;
  wire s_cacheRwCollision = ((s_snoopyStage1LookupSnoopReg == 1'b1 ||
                              s_snoopyStage2LookupSnoopReg == 1'b1 ||
                              s_snoopyStage3UpdateStateReg == 1'b1 ||
                              s_cacheStateReg == LOOKUP_TAGS ||
                              s_cacheStateReg == MARK_SHARED ||
                              (s_cacheStateReg == DO_WRITE && s_busTransactionTypeReg == SNOOPY_WRITE_BACK)) &&
                             (s_stage2CWriteReg == 1'b1 || s_stage2CReadReg == 1'b1)) ? 1'b1 : 1'b0;
  wire s_writeThroughRequired = (s_stage2CWriteReg == 1'b1 &&
                                 ( (s_stage2Hit1Reg == 1'b1 && s_stage2State1Reg[1] == 1'b1) ||
                                   (s_stage2Hit2Reg == 1'b1 && s_stage2State2Reg[1] == 1'b1) ||
                                   (s_stage2Hit3Reg == 1'b1 && s_stage2State3Reg[1] == 1'b1) ||
                                   (s_stage2Hit4Reg == 1'b1 && s_stage2State4Reg[1] == 1'b1))) ? 1'b1 : 1'b0;
  wire s_waitWriteBackNext = (reset == 1'b1 ||
                              s_waitWriteBackTimeOutReg[10] == 1'b1 ||
                              s_snarfUpdateTagReg == 1'b1 ||
                              ((snarfingEnabled == 1'b0 || s_disableSnarfReg == 1'b1)&&
                               s_snoopyWbDetectReg == 1'b1)) ? 1'b0 :
                             (s_cacheStateReg == BACKOFF) ? 1'b1 : s_waitWriteBackReg;
  wire [10:0] s_waitWriteBackTimeOutNext = (s_waitWriteBackReg == 1'b0) ? {11{1'b0}} : s_waitWriteBackTimeOutReg + 11'd1;
  wire s_writeDependencyStall = (wbWriteEnable == 1'b1 &&
                                 (s_registerWe == 1'b1 ||
                                  (s_stage1TargetRegisterReg[4:0] == wbRegisterAddress &&
                                   s_stage1TargetRegisterReg[8:5] == cid &&
                                   (s_stage1CReadReg == 1'b1 ||
                                    s_stage1UReadReg == 1'b1 ||
                                    s_stage1CasReg == 1'b1 ||
                                    s_stage1SwapReg == 1'b1)))) ? 1'b1 : 1'b0;
  wire s_memorySyncStall = (memorySync == 1'b1 &&
                            (s_stage1CacheActionReg == 1'b1 ||
                             s_stage2CacheActionReg == 1'b1 ||
                             s_flushRequestReg == 1'b1)) ? 1'b1 : 1'b0;
  wire s_dataDependencyStall = ( (cid == s_stage1TargetRegisterReg[8:5] &&
                                  (s_stage1CReadReg == 1'b1 ||
                                   s_stage1UReadReg == 1'b1 ||
                                   s_stage1CasReg == 1'b1 ||
                                   s_stage1SwapReg == 1'b1 ||
                                   s_stage1SpmReadReg == 1'b1) &&
                                  s_stage1TargetRegisterReg[4:0] != {5{1'b0}} &&
                                  (rfOperantAAddress == s_stage1TargetRegisterReg[4:0] ||
                                   rfOperantBAddress == s_stage1TargetRegisterReg[4:0] ||
                                   rfStoreAddress == s_stage1TargetRegisterReg[4:0])
                                 ) || 
                                 (cid == s_stage2TargetRegisterReg[8:5] &&
                                  (s_stage2CReadReg == 1'b1 ||
                                   s_stage2UReadReg == 1'b1 ||
                                   s_stage2CasReg == 1'b1 ||
                                   s_stage2SwapReg == 1'b1 ||
                                   s_stage2SpmReadReg == 1'b1) &&
                                  s_stage2TargetRegisterReg[4:0] != {5{1'b0}} &&
                                  (rfOperantAAddress == s_stage2TargetRegisterReg[4:0] ||
                                   rfOperantBAddress == s_stage2TargetRegisterReg[4:0] ||
                                   rfStoreAddress == s_stage2TargetRegisterReg[4:0])
                                 ) || 
                                 ( (memoryLoad != NO_LOAD ||
                                    memoryStore == COMPARE_AND_SWAP ||
                                    memoryStore == SWAP) &&
                                   (rfOperantAAddress == loadTarget[4:0] ||
                                    rfOperantBAddress == loadTarget[4:0] ||
                                    rfStoreAddress == loadTarget[4:0])
                                 ) || 
                                 (rfWriteDestination == 1'b1 &&
                                  (((s_stage1CReadReg == 1'b1 ||
                                     s_stage1UReadReg == 1'b1 ||
                                     s_stage1CasReg == 1'b1 ||
                                     s_stage1SwapReg == 1'b1) && s_stage1TargetRegisterReg == rfDestination) ||
                                   ((s_stage2CReadReg == 1'b1 ||
                                     s_stage2UReadReg == 1'b1 ||
                                     s_stage2CasReg == 1'b1 ||
                                     s_stage2SwapReg == 1'b1) && s_stage2TargetRegisterReg == rfDestination))
                                 )) ? 1'b1 : 1'b0;
  wire s_processorStall = ( ((s_internalStall == 1'b1 || s_flushRequestReg == 1'b1)&&
                             (memoryStore != NO_STORE || memoryLoad != NO_LOAD)) ||
                            s_writeDependencyStall == 1'b1 ||
                            s_dataDependencyStall == 1'b1 ||
                            s_memorySyncStall == 1'b1 ||
                            s_dcacheDisableActiveReg == 1'b1 ||
                            s_dcacheDisableTick == 1'b1) ? 1'b1 : 1'b0;
  wire s_cacheMiss = ((s_stage2CWriteReg == 1'b1 || s_stage2CReadReg == 1'b1) &&
                      s_stage2Hit1Reg == 1'b0 &&
                      s_stage2Hit2Reg == 1'b0 &&
                      s_stage2Hit3Reg == 1'b0 &&
                      s_stage2Hit4Reg == 1'b0) ? 1'b1 : 1'b0;
  wire s_uncacheableAction = (s_stage2ValidReg == 1'b0 && 
                              (s_stage2UWriteReg == 1'b1 ||
                               s_stage2UReadReg == 1'b1 ||
                               s_stage2SwapReg == 1'b1 ||
                               s_stage2CasReg == 1'b1)) ? 1'b1 : 1'b0;

  assign s_internalStall = s_cacheMiss | s_uncacheableAction | (s_writeThroughRequired & ~s_writeThroughDoneReg);
  assign stallCpu = s_processorStall;
  assign resetExeLoad = pipelineStall & ~s_internalStall & ~s_flushRequestReg & ~s_dcacheDisableActiveReg & ~s_dcacheDisableTick;
  
  always @ (posedge clock)
    begin
      s_waitWriteBackTimeOutReg <= s_waitWriteBackTimeOutNext;
      s_waitWriteBackReg        <= s_waitWriteBackNext;
      if (s_cacheStateReg == RELEASE && s_busTransactionTypeReg == WRITE_THROUGH) s_writeThroughDoneReg <= 1'b1;
      else s_writeThroughDoneReg <= 1'b0;
    end

  /*
   *
   * Here the cache state machine is described
   *
   */
  reg [2:0] s_busTransactionLengthNext;
  reg [4:0] s_busTransactionTypeNext;
  reg [5:0] s_cacheStateNext;
  wire s_dirtyReplacer = (s_stage2ReplacementWayReg[0] & (s_stage2State1Reg[2] | s_stage2State1Reg[3])) ||
                         (s_stage2ReplacementWayReg[1] & (s_stage2State2Reg[2] | s_stage2State2Reg[3])) ||
                         (s_stage2ReplacementWayReg[2] & (s_stage2State3Reg[2] | s_stage2State3Reg[3])) ||
                         (s_stage2ReplacementWayReg[3] & (s_stage2State4Reg[2] | s_stage2State4Reg[3]));
  wire [3:0] s_action = {s_stage2CReadReg,
                         s_stage2CWriteReg,
                         s_stage2UReadReg | s_stage2CasReg | s_stage2SwapReg,
                         s_stage2UWriteReg};
  
  always @*
    if (reset == 1'b1)
      begin
        s_busTransactionLengthNext <= 3'b000;
        s_busTransactionTypeNext   <= NOOP;
      end
    else if (s_cacheStateReg == DET_TRANSACTION)
      begin
        if (s_flushActiveReg == 1'b1)
          begin
            s_busTransactionLengthNext <= 3'b111;
            s_busTransactionTypeNext   <= FLUSH_WRITE_BACK;
          end
        else if (s_snoopyWbBufferEmptyReg == 1'b0)
          begin
            s_busTransactionLengthNext <= 3'b111;
            s_busTransactionTypeNext   <= SNOOPY_WRITE_BACK;
          end
        else case (s_action)
          4'b0001  : begin
                       s_busTransactionLengthNext <= 3'b000;
                       s_busTransactionTypeNext   <= UNCACHEABLE_WRITE;
                     end
          4'b0010  : begin
                       s_busTransactionLengthNext <= 3'b000;
                       s_busTransactionTypeNext   <= (s_stage2CasReg == 1'b1) ? ATOMIC_CAS :
                                                     (s_stage2SwapReg == 1'b1) ? ATOMIC_SWAP : UNCACHEABLE_READ;
                     end
          4'b0100  : begin
                       s_busTransactionLengthNext <= (s_writeThroughRequired == 1'b1) ? 3'b000 : 3'b111;
                       s_busTransactionTypeNext   <= (s_writeThroughRequired == 1'b1) ? WRITE_THROUGH :
                                                     (s_dirtyReplacer == 1'b1) ? CACHE_LINE_WRITE_BACK : CACHE_LINE_LOAD;
                     end
          4'b1000  : begin
                       s_busTransactionLengthNext <= 3'b111;
                       s_busTransactionTypeNext   <= (s_dirtyReplacer == 1'b1) ? CACHE_LINE_WRITE_BACK : CACHE_LINE_LOAD;
                     end
          default  : begin
                       s_busTransactionLengthNext <= 3'b000;
                       s_busTransactionTypeNext   <= NOOP;
                     end
        endcase
      end
    else
      begin
        s_busTransactionLengthNext <= s_busTransactionLengthReg;
        s_busTransactionTypeNext   <= s_busTransactionTypeReg;
      end
  
  always @*
    case (s_cacheStateReg)
      IDLE               : s_cacheStateNext <= (s_flushActiveReg == 1'b1) ? FLUSH_INIT :
                                               (s_snoopyWbBufferEmptyReg == 1'b0 ||
                                                (s_internalStall == 1'b1 &&
                                                 s_cacheRwCollision == 1'b0 &&
                                                 s_waitWriteBackReg == 1'b0)) ? REQUEST_THE_BUS : IDLE;
      REQUEST_THE_BUS    : s_cacheStateNext <= (busAccessGranted == 1'b1) ? DET_TRANSACTION : REQUEST_THE_BUS;
      DET_TRANSACTION    : s_cacheStateNext <= (s_snoopyStage1LookupSnoopReg == 1'b1 ||
                                                s_snoopyStage2LookupSnoopReg == 1'b1 ||
                                                s_snoopyStage3UpdateStateReg == 1'b1) ? DET_TRANSACTION :
                                               (s_snoopyWbBufferEmptyReg == 1'b0 &&
                                                s_flushActiveReg == 1'b0) ? LOOKUP_TAGS : INIT_TRANSACTION;
      INIT_TRANSACTION   : case (s_busTransactionTypeReg)
                             UNCACHEABLE_WRITE,
                             CACHE_LINE_WRITE_BACK,
                             SNOOPY_WRITE_BACK,
                             FLUSH_WRITE_BACK,
                             WRITE_THROUGH          : s_cacheStateNext <= DO_WRITE;
                             UNCACHEABLE_READ,
                             ATOMIC_CAS,
                             ATOMIC_SWAP,
                             CACHE_LINE_LOAD        : s_cacheStateNext <= WAIT_READ_BURST;
                             default                : s_cacheStateNext <= END_TRANSACTION;
                           endcase
      DO_WRITE           : s_cacheStateNext <= (busErrorIn == 1'b1) ? END_TRANSACTION :
                                               ((s_wordBurstSelectReg == s_busTransactionLengthReg && s_busWriteStall == 1'b0)||
                                                s_busTransactionTypeReg == UNCACHEABLE_WRITE ||
                                                s_busTransactionTypeReg == WRITE_THROUGH) ? WAIT_N_BUSY : DO_WRITE;
      WAIT_N_BUSY        : s_cacheStateNext <= (endTransactionIn == 1'b1) ? NOP :
                                               ((busyIn == 1'b0 &&
                                                 (s_busTransactionTypeReg == UNCACHEABLE_WRITE ||
                                                  s_busTransactionTypeReg == WRITE_THROUGH ||
                                                  s_busTransactionTypeReg == ATOMIC_CAS ||
                                                  s_busTransactionTypeReg == ATOMIC_SWAP)) ||
                                                busErrorIn == 1'b1) ? END_TRANSACTION : WAIT_N_BUSY;
      WAIT_READ_BURST   : s_cacheStateNext <= (privateDirtyIn == 1'b1 &&
                                               (s_busTransactionTypeReg == CACHE_LINE_LOAD ||
                                                s_busTransactionTypeReg == ATOMIC_SWAP ||
                                                s_busTransactionTypeReg == ATOMIC_CAS)) ? BACKOFF :
                                              (endTransactionIn == 1'b1 &&
                                               (s_busTransactionTypeReg == ATOMIC_SWAP ||
                                                s_busTransactionTypeReg == ATOMIC_CAS)) ? ATOMIC_REQUEST :
                                              (endTransactionIn == 1'b1) ? NOP :
                                              (busErrorIn == 1'b1) ? END_TRANSACTION : WAIT_READ_BURST;
      END_TRANSACTION  : s_cacheStateNext <= (s_busTransactionTypeReg == NOOP) ? IDLE : NOP;
      NOP              : s_cacheStateNext <= (s_busTransactionTypeReg == FLUSH_WRITE_BACK) ? FLUSH_LOOKUP :
                                             ((s_busTransactionTypeReg == CACHE_LINE_WRITE_BACK && s_busErrorReg == 1'b0) ||
                                              s_busTransactionTypeReg == SNOOPY_WRITE_BACK) ? IDLE :
                                             (s_busTransactionTypeReg == CACHE_LINE_LOAD) ? UPDATE_TAGS : RELEASE;
      UPDATE_TAGS      : s_cacheStateNext <= RELEASE;
      ATOMIC_REQUEST   : s_cacheStateNext <= (busAccessGranted == 1'b1) ? ATOMIC_INIT : ATOMIC_REQUEST;
      ATOMIC_INIT      : s_cacheStateNext <= (s_doStore == 1'b1) ? DO_WRITE : ATOMIC_WAIT;
      ATOMIC_WAIT      : s_cacheStateNext <= (endTransactionIn == 1'b1) ? NOP :
                                             (busErrorIn == 1'b1) ? END_TRANSACTION : ATOMIC_WAIT;
      LOOKUP_TAGS      : s_cacheStateNext <= STORE_TAGS;
      STORE_TAGS       : s_cacheStateNext <= MARK_SHARED;
      MARK_SHARED      : s_cacheStateNext <= INIT_TRANSACTION;
      FLUSH_INIT       : s_cacheStateNext <= FLUSH_LOOKUP;
      FLUSH_LOOKUP     : s_cacheStateNext <= (s_flushDone == 1'b1) ? FLUSH_DONE : FLUSH_INVALIDATE;
      FLUSH_INVALIDATE : s_cacheStateNext <= (s_flushWriteBackRequired == 1'b1) ? REQUEST_THE_BUS : FLUSH_LOOKUP;
      default          : s_cacheStateNext <= IDLE;
    endcase

  always @ (posedge clock)
    begin
      s_busTransactionLengthReg <= s_busTransactionLengthNext;
      s_busTransactionTypeReg   <= s_busTransactionTypeNext;
      s_cacheEnabledReg         <= (reset == 1'b1) ? 1'b0 : (s_cacheStateReg == IDLE) ? enableCache : s_cacheEnabledReg;
      if (reset == 1'b1) s_cacheStateReg <= IDLE;
      else s_cacheStateReg <= s_cacheStateNext;
    end

  /*
   *
   * Here the profiling signals are generated
   *
   */
   always @ (posedge clock)
     begin
       cachedWrite     <= ~s_internalStall && s_stage2CWriteReg;
       cachedRead      <= ~s_internalStall && s_stage2CReadReg;
       uncachedWrite   <= ~s_internalStall && s_stage2UWriteReg;
       uncachedRead    <= ~s_internalStall && s_stage2UReadReg;
       swapInstruction <= ~s_internalStall && s_stage2SwapReg;
       casInstruction  <= ~s_internalStall && s_stage2CasReg;
       cacheMiss       <= (s_cacheStateReg == INIT_TRANSACTION && s_busTransactionTypeReg == CACHE_LINE_LOAD) ? 1'b1 : 1'b0;
       cacheWriteBack  <= (s_cacheStateReg == INIT_TRANSACTION && s_busTransactionTypeReg == CACHE_LINE_WRITE_BACK) ? 1'b1 : 1'b0;
       dataStall       <= s_dataDependencyStall;
       writeStall      <= s_writeDependencyStall;
       processorStall  <= s_processorStall;
       cacheStall      <= s_internalStall;
       writeThrough    <= s_writeThroughDoneReg;
       invalidate      <= s_snoopyStage3InvalidateReg;
     end

endmodule
