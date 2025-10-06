module icache   ( input wire         clock,
                                     reset,
                  
                  // Here the bus interface is defined
                  output wire        requestBus,
                  input wire         busAccessGranted,
                                     busErrorIn,
                  output wire        beginTransactionOut,
                  output wire [31:0] addressDataOut,
                  input wire  [31:0] addressDataIn,
                  input wire         endTransactionIn,
                  output wire [3:0]  byteEnablesOut,
                  output wire        readNotWriteOut,
                  input wire         dataValidIn,
                  input wire         busyIn,
                  output wire [7:0]  burstSizeOut,

                  // here the profiling interface is defined
                  output reg         instructionFetch,
                                     cacheMiss,
                                     cacheMissActive,
                                     cacheFlushActive,
                                     cacheInsertedNop,
                 
                  // here the exe stage interface is defined
                  output wire [31:0] returnAddress,
                  
                  // here the debug interface is defined
                  output wire [31:0] instructionFetchEa,
                  
                  // here the processor interface is defined
                  input wire         stall,
                                     flushPipe,
                                     flushCache,
                  input wire [1:0]   replacementPolicy,
                                     cacheSize,
                                     numberOfWays,
                  input wire         cacheEnabled,
                                     loadPc,
                                     jump,
                  input wire [29:0]  pcLoadValue,
                                     jumpTarget,
                  output wire [31:0] instruction,
                                     instructionAddress,
                  output wire        insertedNop,
                                     instructionAbort,
                                     instructionResetFilter );

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

  localparam [3:0] IDLE             = 4'd0;
  localparam [3:0] REQUEST_THE_BUS  = 4'd1;
  localparam [3:0] INIT_TRANSACTION = 4'd2;
  localparam [3:0] WAIT_READ_BURST  = 4'd3;
  localparam [3:0] NOP              = 4'd4;
  localparam [3:0] UPDATE_TAGS      = 4'd5;
  localparam [3:0] RELEASE          = 4'd6;
  localparam [3:0] FLUSH_INIT       = 4'd7;
  localparam [3:0] DO_FLUSH         = 4'd8;
  localparam [3:0] FLUSH_DONE       = 4'd9;

  parameter [31:0] NopInstruction = 32'h1500FFFF;
  reg s_flushActiveReg, s_busDataInValidReg, s_cacheEnabledReg;
  reg [3:0] s_stage3ReplacementWayReg;
  reg [2:0] s_wordBurstSelectReg;
  reg [31:0] s_selectedCacheData, s_fetchedInstructionReg, s_busDataInReg;
  reg [3:0] s_cacheStateReg;
  wire s_internalStall, s_flushCache, s_busError, s_hit;
  wire s_stall = stall | s_internalStall;
  
  /*
   *
   * Here the program counter related signals are defined
   *
   */
  reg [31:0] s_stage1PcReg, s_stage3PcReg;
  reg s_stage1ResetFilterReg, s_stage3ResetFilterReg, s_stage3ActivePcReg;
  wire [31:0] s_nextPc = (reset == 1'b1) ? 32'hF0000070 :
                         (loadPc == 1'b1 && stall == 1'b0) ? {pcLoadValue, 2'b00} :
                         (jump == 1'b1 && stall == 1'b0) ? {jumpTarget, 2'b00} :
                         (s_stall == 1'b0) ? s_stage1PcReg + 4 : s_stage1PcReg;
  wire [31:0] s_stage2PcReg = s_stage1PcReg;
  wire [31:0] s_stage3PcNext = (s_stall == 1'b1) ? s_stage3PcReg : s_stage2PcReg;
  wire s_stage1ResetFilterNext = (reset == 1'b1) ? 1'b0 :
                                 (stall == 1'b1) ? s_stage1ResetFilterReg :
                                 (jump == 1'b1)  ? 1'b1 :
                                 (s_internalStall == 1'b0) ? 1'b0 : s_stage1ResetFilterReg;
  wire s_stage2ResetFilterReg = s_stage1ResetFilterReg;
  wire s_stage3ResetFilterNext = (reset == 1'b1) ? 1'b0 :
                                 (s_stall == 1'b0) ? s_stage2ResetFilterReg : s_stage3ResetFilterReg;
  wire s_stage3ActivePcNext = (reset == 1'b1 || (stall == 1'b0 && (flushPipe == 1'b1 || s_flushCache == 1'b1))) ? 1'b0 :
                              (s_internalStall == 1'b0 && stall == 1'b0) ? 1'b1 : s_stage3ActivePcReg;
  
  assign returnAddress          = s_stage2PcReg;
  assign instructionAddress     = s_stage3PcReg;
  assign instructionResetFilter = s_stage3ResetFilterReg & ~s_internalStall;
  assign instructionFetchEa     = s_stage1PcReg;
  
  always @(posedge clock)
    begin
      s_stage1PcReg          <= s_nextPc;
      s_stage3PcReg          <= s_stage3PcNext;
      s_stage1ResetFilterReg <= s_stage1ResetFilterNext;
      s_stage3ResetFilterReg <= s_stage3ResetFilterNext;
      s_stage3ActivePcReg    <= s_stage3ActivePcNext;
    end
  
  /*
   *
   * Here the instruction related signals are defined
   *
   */
  reg s_stage3InsertedNopReg, s_stage3AbortReg, s_stage3ValidReg;
  reg [31:0] s_stage3InstructionReg;
  wire [31:0] s_newInstruction = {s_busDataInReg[7:0],s_busDataInReg[15:8],s_busDataInReg[23:16],s_busDataInReg[31:24]};
  wire [31:0] s_stage3InstructionNext = (reset == 1'b1) ? NopInstruction :
                                        (s_cacheEnabledReg == 1'b0 && stall == 1'b0 &&
                                         (s_internalStall == 1'b0 || flushPipe == 1'b1 || s_flushCache == 1'b1 || s_flushActiveReg == 1'b1)) ? NopInstruction :
                                        (s_cacheEnabledReg == 1'b0 && s_cacheStateReg == RELEASE && s_busError == 1'b0) ? s_newInstruction :
                                        (s_cacheEnabledReg == 1'b1 && stall == 1'b0 &&
                                         ((s_hit == 1'b0 && s_internalStall == 1'b0) || flushPipe == 1'b1 || s_flushCache == 1'b1 || s_flushActiveReg == 1'b1)) ? NopInstruction :
                                        (s_cacheEnabledReg == 1'b1 && s_stall == 1'b0 && s_internalStall == 1'b0 && s_hit == 1'b1) ? s_selectedCacheData :
                                        (s_cacheEnabledReg == 1'b1 && s_cacheStateReg == RELEASE && s_busError == 1'b0) ? s_fetchedInstructionReg : s_stage3InstructionReg;
  wire s_stage3InsertedNopNext = (reset == 1'b1) ? 1'b1 :
                                 (s_cacheEnabledReg == 1'b0 && stall == 1'b0 &&
                                  (s_internalStall == 1'b0 || flushPipe == 1'b1 || s_flushCache == 1'b1 || s_flushActiveReg == 1'b1)) ? 1'b1 :
                                 (s_cacheEnabledReg == 1'b0 && s_cacheStateReg == RELEASE && s_busError == 1'b0) ? 1'b0 :
                                 (s_cacheEnabledReg == 1'b1 && stall == 1'b0 &&
                                  ((s_hit == 1'b0 && s_internalStall == 1'b0) || flushPipe == 1'b1 || s_flushCache == 1'b1 || s_flushActiveReg == 1'b1)) ? 1'b1 :
                                 (s_cacheEnabledReg == 1'b1 && s_stall == 1'b0 && s_internalStall == 1'b0 && s_hit == 1'b1) ? 1'b0 :
                                 (s_cacheEnabledReg == 1'b1 && s_cacheStateReg == RELEASE && s_busError == 1'b0) ? 1'b0 : s_stage3InsertedNopReg;
  wire s_stage3AbortNext = (reset == 1'b1 || s_stall == 1'b0) ? 1'b0 : s_stage3AbortReg | s_busError;
  wire s_stage3ValidNext = (reset == 1'b1) ? 1'b0 : (s_cacheStateReg == RELEASE && s_cacheEnabledReg == 1'b0) ? 1'b1 : (s_stall == 1'b0) ? 1'b0 : s_stage3ValidReg;
  
  assign insertedNop      = s_stage3InsertedNopReg;
  assign instruction      = s_stage3InstructionReg;
  assign instructionAbort = s_stage3AbortReg & s_stage3ActivePcReg & ~s_internalStall;
  
  always @(posedge clock)
    begin
      s_stage3InstructionReg <= s_stage3InstructionNext;
      s_stage3InsertedNopReg <= s_stage3InsertedNopNext;
      s_stage3AbortReg       <= s_stage3AbortNext;
      s_stage3ValidReg       <= s_stage3ValidNext;
    end
  
  /*
   *
   * Here the flush related signals are defined
   *
   */
  reg s_cacheEnabledDelayReg;
  reg [7:0] s_flushCounterReg;
  wire s_flushActiveNext = (s_flushCache == 1'b1 || reset == 1'b1) ? 1'b1 :
                           (s_cacheStateReg == FLUSH_DONE) ? 1'b0 : s_flushActiveReg;
  wire [7:0] s_flushCounterNext = (reset == 1'b1 || s_cacheStateReg == FLUSH_INIT) ? {8{1'b0}} :
                                  (s_cacheStateReg == DO_FLUSH) ? s_flushCounterReg + 8'd1 : s_flushCounterReg;
  
  assign s_flushCache = (flushCache == 1'b1 || (s_cacheEnabledDelayReg == 1'b1 && s_cacheEnabledReg == 1'b0)) ? 1'b1 : 1'b0;
  
  always @ (posedge clock)
    begin
      s_cacheEnabledDelayReg <= s_cacheEnabledReg;
      s_flushActiveReg       <= s_flushActiveNext;
      s_flushCounterReg      <= s_flushCounterNext;
    end
  
  /*
   *
   * Here the state and tag related signals are defined
   *
   */
  reg [23:0] s_newTag, s_compareTag;
  reg [8:0] s_tagStateLookupIndex, s_tagStateForwardIndex, s_tagStateCurrentIndex;
  reg s_hit1, s_hit2, s_hit3, s_hit4;
  reg s_stage3Hit1Reg, s_stage3Hit2Reg, s_stage3Hit3Reg, s_stage3Hit4Reg;
  wire [3:0] s_cacheConfiguration = {numberOfWays, cacheSize};
  wire s_newState = ~s_flushActiveReg;
  wire [3:0] s_tagUpdateVector = (s_cacheStateReg == DO_FLUSH) ? 4'hF :
                                 (s_cacheStateReg == UPDATE_TAGS) ? s_stage3ReplacementWayReg : 4'h0;
  wire [8:0] s_tagIndex = (s_flushActiveReg == 1'b1) ? {1'b0, s_flushCounterReg} :
                          (s_tagUpdateVector == 4'h0) ? s_tagStateLookupIndex : s_tagStateCurrentIndex;
  wire [31:0] s_newCombinedTag = {6'd0 , s_newTag, s_newState};
  wire [31:0] s_combinedTag1, s_combinedTag2, s_combinedTag3, s_combinedTag4;
  wire s_state1 = s_combinedTag1[0];
  wire s_state2 = s_combinedTag2[0];
  wire s_state3 = s_combinedTag3[0];
  wire s_state4 = s_combinedTag4[0];
  wire [23:0] s_tag1   = s_combinedTag1[24:1];
  wire [23:0] s_tag2   = s_combinedTag2[24:1];
  wire [23:0] s_tag3   = s_combinedTag3[24:1];
  wire [23:0] s_tag4   = s_combinedTag4[24:1];
  wire s_stage2Valid1Reg = s_state1 & ~s_flushActiveReg;
  wire s_stage2Valid2Reg = s_state2 & ~s_flushActiveReg;
  wire s_stage2Valid3Reg = s_state3 & ~s_flushActiveReg;
  wire s_stage2Valid4Reg = s_state4 & ~s_flushActiveReg;
  wire s_stage3Hit1Next = (reset == 1'b1) ? 1'b0 :
                          (s_stall == 1'b0) ? s_hit1 :
                          (s_cacheStateReg == RELEASE && s_cacheEnabledReg == 1'b1) ? s_stage3ReplacementWayReg[0] : s_stage3Hit1Reg;
  wire s_stage3Hit2Next = (reset == 1'b1) ? 1'b0 :
                          (s_stall == 1'b0) ? s_hit2 :
                          (s_cacheStateReg == RELEASE && s_cacheEnabledReg == 1'b1) ? s_stage3ReplacementWayReg[1] : s_stage3Hit2Reg;
  wire s_stage3Hit3Next = (reset == 1'b1) ? 1'b0 :
                          (s_stall == 1'b0) ? s_hit3 :
                          (s_cacheStateReg == RELEASE && s_cacheEnabledReg == 1'b1) ? s_stage3ReplacementWayReg[2] : s_stage3Hit3Reg;
  wire s_stage3Hit4Next = (reset == 1'b1) ? 1'b0 :
                          (s_stall == 1'b0) ? s_hit4 :
                          (s_cacheStateReg == RELEASE && s_cacheEnabledReg == 1'b1) ? s_stage3ReplacementWayReg[3] : s_stage3Hit4Reg;
  
  assign s_hit = s_hit1 | s_hit2 | s_hit3 | s_hit4;
  
  always @*
    case (s_cacheConfiguration)
      FOUR_WAY_SET_ASSOCIATIVE_1K : begin
                                      s_newTag               <= s_stage3PcReg[31:8];
                                      s_compareTag           <= s_stage2PcReg[31:8];
                                      s_tagStateLookupIndex  <= { 6'd0 , s_nextPc[7:5] };
                                      s_tagStateForwardIndex <= { 6'd0 , s_stage2PcReg[7:5] };
                                      s_tagStateCurrentIndex <= { 6'd0 , s_stage3PcReg[7:5] };
                                    end
      FOUR_WAY_SET_ASSOCIATIVE_2K,
      TWO_WAY_SET_ASSOCIATIVE_1K  : begin
                                      s_newTag               <= { 1'b0 , s_stage3PcReg[31:9]};
                                      s_compareTag           <= { 1'b0 , s_stage2PcReg[31:9]};
                                      s_tagStateLookupIndex  <= { 5'd0 , s_nextPc[8:5] };
                                      s_tagStateForwardIndex <= { 5'd0 , s_stage2PcReg[8:5] };
                                      s_tagStateCurrentIndex <= { 5'd0 , s_stage3PcReg[8:5] };
                                    end
      FOUR_WAY_SET_ASSOCIATIVE_4K,
      TWO_WAY_SET_ASSOCIATIVE_2K,
      DIRECT_MAPPED_1K            : begin
                                      s_newTag               <= { 2'd0 , s_stage3PcReg[31:10]};
                                      s_compareTag           <= { 2'd0 , s_stage2PcReg[31:10]};
                                      s_tagStateLookupIndex  <= { 4'd0 , s_nextPc[9:5] };
                                      s_tagStateForwardIndex <= { 4'd0 , s_stage2PcReg[9:5] };
                                      s_tagStateCurrentIndex <= { 4'd0 , s_stage3PcReg[9:5] };
                                    end
      FOUR_WAY_SET_ASSOCIATIVE_8K,
      TWO_WAY_SET_ASSOCIATIVE_4K,
      DIRECT_MAPPED_2K            : begin
                                      s_newTag               <= { 3'd0 , s_stage3PcReg[31:11]};
                                      s_compareTag           <= { 3'd0 , s_stage2PcReg[31:11]};
                                      s_tagStateLookupIndex  <= { 3'd0 , s_nextPc[10:5] };
                                      s_tagStateForwardIndex <= { 3'd0 , s_stage2PcReg[10:5] };
                                      s_tagStateCurrentIndex <= { 3'd0 , s_stage3PcReg[10:5] };
                                    end
      TWO_WAY_SET_ASSOCIATIVE_8K,
      DIRECT_MAPPED_4K            : begin
                                      s_newTag               <= { 4'd0 , s_stage3PcReg[31:12]};
                                      s_compareTag           <= { 4'd0 , s_stage2PcReg[31:12]};
                                      s_tagStateLookupIndex  <= { 2'd0 , s_nextPc[11:5] };
                                      s_tagStateForwardIndex <= { 2'd0 , s_stage2PcReg[11:5] };
                                      s_tagStateCurrentIndex <= { 2'd0 , s_stage3PcReg[11:5] };
                                    end
      default                     : begin
                                      s_newTag               <= { 5'd0 , s_stage3PcReg[31:13]};
                                      s_compareTag           <= { 5'd0 , s_stage2PcReg[31:13]};
                                      s_tagStateLookupIndex  <= { 1'b0 , s_nextPc[12:5] };
                                      s_tagStateForwardIndex <= { 1'b0 , s_stage2PcReg[12:5] };
                                      s_tagStateCurrentIndex <= { 1'b0 , s_stage3PcReg[12:5] };
                                    end
    endcase
      
  always @*
    case (numberOfWays)
      FOUR_WAY_SET_ASSOCIATIVE : begin
                                   s_hit1 <= (s_tag1 == s_compareTag) ? s_stage2Valid1Reg : 1'b0;
                                   s_hit2 <= (s_tag2 == s_compareTag) ? s_stage2Valid2Reg : 1'b0;
                                   s_hit3 <= (s_tag3 == s_compareTag) ? s_stage2Valid3Reg : 1'b0;
                                   s_hit4 <= (s_tag4 == s_compareTag) ? s_stage2Valid4Reg : 1'b0;
                                 end
      TWO_WAY_SET_ASSOCIATIVE  : begin
                                   s_hit1 <= (s_tag1 == s_compareTag) ? s_stage2Valid1Reg : 1'b0;
                                   s_hit2 <= (s_tag2 == s_compareTag) ? s_stage2Valid2Reg : 1'b0;
                                   s_hit3 <= 1'b0;
                                   s_hit4 <= 1'b0;
                                 end
      default                  : begin
                                   s_hit1 <= (s_tag1 == s_compareTag) ? s_stage2Valid1Reg : 1'b0;
                                   s_hit2 <= 1'b0; 
                                   s_hit3 <= 1'b0;
                                   s_hit4 <= 1'b0;
                                 end
    endcase
  
  always @(posedge clock)
    begin
      s_stage3Hit1Reg <= s_stage3Hit1Next;
      s_stage3Hit2Reg <= s_stage3Hit2Next;
      s_stage3Hit3Reg <= s_stage3Hit3Next;
      s_stage3Hit4Reg <= s_stage3Hit4Next;
    end
    
  wire [8:0] s_tagIndexB = {1'b1,s_tagIndex[7:0]};
  sram512X32Dp tagRamA( .clockA(clock),
                        .writeEnableA(s_tagUpdateVector[0]),
                        .addressA(s_tagIndex),
                        .dataInA(s_newCombinedTag),
                        .dataOutA(s_combinedTag1),
                        .clockB(clock),
                        .writeEnableB(s_tagUpdateVector[1]),
                        .addressB(s_tagIndexB),
                        .dataInB(s_newCombinedTag),
                        .dataOutB(s_combinedTag2));  
  sram512X32Dp tagRamB( .clockA(clock),
                        .writeEnableA(s_tagUpdateVector[2]),
                        .addressA(s_tagIndex),
                        .dataInA(s_newCombinedTag),
                        .dataOutA(s_combinedTag3),
                        .clockB(clock),
                        .writeEnableB(s_tagUpdateVector[3]),
                        .addressB(s_tagIndexB),
                        .dataInB(s_newCombinedTag),
                        .dataOutB(s_combinedTag4));  
  /*
   *
   * here the data related signals are defined
   *
   */
  reg [8:0] s_dataLookupIndex, s_dataWriteIndex;
  reg [1:0] s_select, s_weSelect;
  reg [3:0] s_weDataVector;
  reg s_iHit;
  wire [31:0] s_dataToCache = {s_busDataInReg[7:0],s_busDataInReg[15:8],s_busDataInReg[23:16],s_busDataInReg[31:24]};
  wire [31:0] s_dataMem1, s_dataMem2, s_dataMem3, s_dataMem4;
  wire [31:0] s_fetchedInstructionNext = (s_cacheEnabledReg == 1'b1 && s_busDataInValidReg == 1'b1 && s_iHit == 1'b1) ? s_dataToCache : s_fetchedInstructionReg;
  wire [9:0] s_dataIndex = (s_weDataVector == 4'h0) ? s_dataLookupIndex : s_dataWriteIndex;
  
  always @*
    case (cacheSize)
      SIZE_8K : begin
                  s_dataLookupIndex <= s_nextPc[10:2];
                  s_dataWriteIndex  <= {s_stage3PcReg[10:5], s_wordBurstSelectReg};
                  s_iHit = (s_dataWriteIndex == s_stage3PcReg[10:2]) ? 1'b1 : 1'b0;
                end
      SIZE_4K : begin
                  s_dataLookupIndex <= {1'b0, s_nextPc[9:2]};
                  s_dataWriteIndex  <= {1'b0, s_stage3PcReg[9:5], s_wordBurstSelectReg};
                  s_iHit = (s_dataWriteIndex[7:0] == s_stage3PcReg[9:2]) ? 1'b1 : 1'b0;
                end
      SIZE_2K : begin
                  s_dataLookupIndex <= {2'd0, s_nextPc[8:2]};
                  s_dataWriteIndex  <= {2'd0, s_stage3PcReg[8:5], s_wordBurstSelectReg};
                  s_iHit = (s_dataWriteIndex[6:0] == s_stage3PcReg[8:2]) ? 1'b1 : 1'b0;
                end
      default : begin
                  s_dataLookupIndex <= {3'd0, s_nextPc[7:2]};
                  s_dataWriteIndex  <= {3'd0, s_stage3PcReg[7:5], s_wordBurstSelectReg};
                  s_iHit = (s_dataWriteIndex[5:0] == s_stage3PcReg[7:2]) ? 1'b1 : 1'b0;
                end
    endcase
  
  always @*
    case (numberOfWays)
      FOUR_WAY_SET_ASSOCIATIVE : begin
                                  s_select[1]   <= s_hit4 | s_hit3;
                                  s_select[0]   <= s_hit4 | s_hit2;
                                  s_weSelect[1] <= s_stage3ReplacementWayReg[3] | s_stage3ReplacementWayReg[2];
                                  s_weSelect[0] <= s_stage3ReplacementWayReg[3] | s_stage3ReplacementWayReg[1];
                                 end
      TWO_WAY_SET_ASSOCIATIVE  : begin
                                   s_select[1]   <= s_hit2;
                                   s_weSelect[1] <= s_stage3ReplacementWayReg[1];
                                   case (cacheSize)
                                     SIZE_8K : begin
                                                 s_select[0]   <= s_stage2PcReg[11];
                                                 s_weSelect[0] <= s_stage3PcReg[11];
                                               end
                                     SIZE_4K : begin
                                                 s_select[0]   <= s_stage2PcReg[10];
                                                 s_weSelect[0] <= s_stage3PcReg[10];
                                               end
                                     SIZE_2K : begin
                                                 s_select[0]   <= s_stage2PcReg[9];
                                                 s_weSelect[0] <= s_stage3PcReg[9];
                                               end
                                     default : begin
                                                 s_select[0]   <= s_stage2PcReg[8];
                                                 s_weSelect[0] <= s_stage3PcReg[8];
                                               end
                                   endcase
                                 end
     default                   : case (cacheSize)
                                   SIZE_8K : begin
                                               s_select   <= s_stage2PcReg[12:11];
                                               s_weSelect <= s_stage3PcReg[12:11];
                                             end
                                   SIZE_4K : begin
                                               s_select   <= s_stage2PcReg[11:10];
                                               s_weSelect <= s_stage3PcReg[11:10];
                                             end
                                   SIZE_2K : begin
                                               s_select   <= s_stage2PcReg[10:9];
                                               s_weSelect <= s_stage3PcReg[10:9];
                                             end
                                   default : begin
                                               s_select   <= s_stage2PcReg[9:8];
                                               s_weSelect <= s_stage3PcReg[9:8];
                                             end
                                 endcase
    endcase
  
  always @*
    case (s_select)
      2'b00   : s_selectedCacheData <= s_dataMem1;
      2'b01   : s_selectedCacheData <= s_dataMem2;
      2'b10   : s_selectedCacheData <= s_dataMem3;
      default : s_selectedCacheData <= s_dataMem4;
    endcase
  
  always @*
    if (s_cacheEnabledReg == 1'b1 && s_busDataInValidReg == 1'b1)
      case (s_weSelect)
        2'b00   : s_weDataVector <= 4'h1;
        2'b01   : s_weDataVector <= 4'h2;
        2'b10   : s_weDataVector <= 4'h4;
        default : s_weDataVector <= 4'h8;
      endcase
    else s_weDataVector <= 4'h0;
  
  always @(posedge clock)
    begin
      s_fetchedInstructionReg <= s_fetchedInstructionNext;
    end

      sram512X32 dataRam1 ( .clock(clock),
                            .writeEnable(s_weDataVector[0]),
                            .address(s_dataIndex[8:0]),
                            .dataIn(s_dataToCache),
                            .dataOut(s_dataMem1));
      sram512X32 dataRam2 ( .clock(clock),
                            .writeEnable(s_weDataVector[1]),
                            .address(s_dataIndex[8:0]),
                            .dataIn(s_dataToCache),
                            .dataOut(s_dataMem2));
      sram512X32 dataRam3 ( .clock(clock),
                            .writeEnable(s_weDataVector[2]),
                            .address(s_dataIndex[8:0]),
                            .dataIn(s_dataToCache),
                            .dataOut(s_dataMem3));
      sram512X32 dataRam4 ( .clock(clock),
                            .writeEnable(s_weDataVector[3]),
                            .address(s_dataIndex[8:0]),
                            .dataIn(s_dataToCache),
                            .dataOut(s_dataMem4));

  /*
   *
   * Here all policy related signals are defined
   *
   */
  reg [1:0] s_newFifo, s_newLru1, s_newLru2, s_newLru3, s_newLru4;
  reg [4:0] s_newPlru, s_stage3PlruReg;
  reg [1:0] s_stage3FifoReg, s_stage3Lru1Reg, s_stage3Lru2Reg, s_stage3Lru3Reg, s_stage3Lru4Reg;
  reg [3:0] s_stage3ReplacementWayNext;
  wire [31:0] s_combinedPolicy, s_dummyPolicy;
  wire [31:0] s_newCombinedPolicy = (s_flushActiveReg == 1'b1) ? {32{1'b0}} : { {17{1'b0}}, s_newPlru, s_newLru4, s_newLru3, s_newLru2, s_newLru1, s_newFifo};
  wire [1:0] s_stage2FifoReg = s_combinedPolicy[1:0];
  wire [1:0] s_stage2Lru1Reg = s_combinedPolicy[3:2];
  wire [1:0] s_stage2Lru2Reg = s_combinedPolicy[5:4];
  wire [1:0] s_stage2Lru3Reg = s_combinedPolicy[7:6];
  wire [1:0] s_stage2Lru4Reg = s_combinedPolicy[9:8];
  wire [4:0] s_stage2PlruReg = s_combinedPolicy[14:10];
  wire s_weNewPolicy = (s_cacheStateReg == UPDATE_TAGS || s_cacheStateReg == DO_FLUSH ||
                        (s_stall == 1'b0 && s_stage3ActivePcReg == 1'b1)) ? 1'b1 : 1'b0;
  wire [1:0] s_stage3FifoNext = (reset == 1'b1) ? 2'b00 :
                                (s_weNewPolicy == 1'b1 &&
                                 ( (s_tagStateCurrentIndex == s_tagStateForwardIndex && s_stall == 1'b0) ||
                                  s_stall == 1'b1)) ? s_newFifo :
                                (s_stall == 1'b0) ? s_stage2FifoReg : s_stage3FifoReg;
  wire [1:0] s_stage3Lru1Next = (reset == 1'b1) ? 2'b00 :
                                (s_weNewPolicy == 1'b1 &&
                                 ( (s_tagStateCurrentIndex == s_tagStateForwardIndex && s_stall == 1'b0) ||
                                  s_stall == 1'b1)) ? s_newLru1 :
                                (s_stall == 1'b0) ? s_stage2Lru1Reg : s_stage3Lru1Reg;
  wire [1:0] s_stage3Lru2Next = (reset == 1'b1) ? 2'b00 :
                                (s_weNewPolicy == 1'b1 &&
                                 ( (s_tagStateCurrentIndex == s_tagStateForwardIndex && s_stall == 1'b0) ||
                                  s_stall == 1'b1)) ? s_newLru2 :
                                (s_stall == 1'b0) ? s_stage2Lru2Reg : s_stage3Lru2Reg;
  wire [1:0] s_stage3Lru3Next = (reset == 1'b1) ? 2'b00 :
                                (s_weNewPolicy == 1'b1 &&
                                 ( (s_tagStateCurrentIndex == s_tagStateForwardIndex && s_stall == 1'b0) ||
                                  s_stall == 1'b1)) ? s_newLru3 :
                                (s_stall == 1'b0) ? s_stage2Lru3Reg : s_stage3Lru3Reg;
  wire [1:0] s_stage3Lru4Next = (reset == 1'b1) ? 2'b00 :
                                (s_weNewPolicy == 1'b1 &&
                                 ( (s_tagStateCurrentIndex == s_tagStateForwardIndex && s_stall == 1'b0) ||
                                  s_stall == 1'b1)) ? s_newLru4 :
                                (s_stall == 1'b0) ? s_stage2Lru4Reg : s_stage3Lru4Reg;
  wire [4:0] s_stage3PlruNext = (reset == 1'b1) ? 5'b00000 :
                                (s_weNewPolicy == 1'b1 &&
                                 ( (s_tagStateCurrentIndex == s_tagStateForwardIndex && s_stall == 1'b0) ||
                                  s_stall == 1'b1)) ? s_newPlru :
                                (s_stall == 1'b0) ? s_stage2PlruReg : s_stage3PlruReg;
  wire [1:0] s_lruSelect = {s_stage3Hit4Reg | s_stage3Hit3Reg, s_stage3Hit4Reg | s_stage3Hit2Reg};
    
  always @*
    if (s_internalStall == 1'b1) s_stage3ReplacementWayNext <= s_stage3ReplacementWayReg;
    else case (replacementPolicy)
      FIFO_REPLACEMENT : case (s_stage2FifoReg)
                           2'b00   : s_stage3ReplacementWayNext <= 4'h1;
                           2'b01   : s_stage3ReplacementWayNext <= 4'h2;
                           2'b10   : s_stage3ReplacementWayNext <= 4'h4;
                           default : s_stage3ReplacementWayNext <= 4'h8;
                         endcase
      PLRU_REPLACEMENT : if (s_stage2PlruReg[4] == 1'b1)
                           begin
                             s_stage3ReplacementWayNext[3:2] <= 2'b00;
                             s_stage3ReplacementWayNext[1:0] <= (s_stage2PlruReg[1:0] == 2'b00 || s_stage2PlruReg[1:0] == 2'b11) ? 2'b01 : ~s_stage2PlruReg[1:0];
                           end
                         else
                           begin
                             s_stage3ReplacementWayNext[1:0] <= 2'b00;
                             s_stage3ReplacementWayNext[3:2] <= (s_stage2PlruReg[3:2] == 2'b00 || s_stage2PlruReg[3:2] == 2'b11) ? 2'b01 : ~s_stage2PlruReg[3:2];
                           end
      default          : s_stage3ReplacementWayNext <= (s_stage2Lru1Reg == 2'b00) ? 4'h1 :
                                                       (s_stage2Lru2Reg == 2'b00) ? 4'h2 :
                                                       (s_stage2Lru3Reg == 2'b00) ? 4'h4 : 4'h8;
    endcase
  
  always @*
    if (s_cacheStateReg == UPDATE_TAGS)
      case (numberOfWays)
        FOUR_WAY_SET_ASSOCIATIVE : begin
                                     s_newFifo      <= s_stage3FifoReg + 2'd1;
                                     s_newPlru[4]   <= s_stage3Hit4Reg | s_stage3Hit3Reg;
                                     s_newPlru[3:2] <= (s_stage3Hit4Reg == 1'b1 || s_stage3Hit3Reg == 1'b1) ? {s_stage3Hit4Reg,s_stage3Hit3Reg} : s_stage3PlruReg[3:2];
                                     s_newPlru[1:0] <= (s_stage3Hit4Reg == 1'b1 || s_stage3Hit3Reg == 1'b1) ? s_stage3PlruReg[1:0] : {s_stage3Hit2Reg,s_stage3Hit1Reg};
                                     case (s_lruSelect)
                                       2'b00    : begin
                                                    s_newLru1 <= 2'b11;
                                                    s_newLru2 <= (s_stage3Lru2Reg > s_stage3Lru1Reg) ? s_stage3Lru2Reg - 2'd1 : s_stage3Lru2Reg;
                                                    s_newLru3 <= (s_stage3Lru3Reg > s_stage3Lru1Reg) ? s_stage3Lru3Reg - 2'd1 : s_stage3Lru3Reg;
                                                    s_newLru4 <= (s_stage3Lru4Reg > s_stage3Lru1Reg) ? s_stage3Lru4Reg - 2'd1 : s_stage3Lru4Reg;
                                                  end
                                       2'b01    : begin
                                                    s_newLru1 <= (s_stage3Lru1Reg > s_stage3Lru2Reg) ? s_stage3Lru1Reg - 2'd1 : s_stage3Lru1Reg;
                                                    s_newLru2 <= 2'b11;
                                                    s_newLru3 <= (s_stage3Lru3Reg > s_stage3Lru2Reg) ? s_stage3Lru3Reg - 2'd1 : s_stage3Lru3Reg;
                                                    s_newLru4 <= (s_stage3Lru4Reg > s_stage3Lru2Reg) ? s_stage3Lru4Reg - 2'd1 : s_stage3Lru4Reg;
                                                  end
                                       2'b10    : begin
                                                    s_newLru1 <= (s_stage3Lru1Reg > s_stage3Lru3Reg) ? s_stage3Lru1Reg - 2'd1 : s_stage3Lru1Reg;
                                                    s_newLru2 <= (s_stage3Lru2Reg > s_stage3Lru3Reg) ? s_stage3Lru2Reg - 2'd1 : s_stage3Lru2Reg;
                                                    s_newLru3 <= 2'b11;
                                                    s_newLru4 <= (s_stage3Lru4Reg > s_stage3Lru3Reg) ? s_stage3Lru4Reg - 2'd1 : s_stage3Lru4Reg;
                                                  end
                                        default : begin
                                                    s_newLru1 <= (s_stage3Lru1Reg > s_stage3Lru4Reg) ? s_stage3Lru1Reg - 2'd1 : s_stage3Lru1Reg;
                                                    s_newLru2 <= (s_stage3Lru2Reg > s_stage3Lru4Reg) ? s_stage3Lru2Reg - 2'd1 : s_stage3Lru2Reg;
                                                    s_newLru3 <= (s_stage3Lru3Reg > s_stage3Lru4Reg) ? s_stage3Lru3Reg - 2'd1 : s_stage3Lru3Reg;
                                                    s_newLru4 <= 2'b11;
                                                  end
                                     endcase
                                   end
        TWO_WAY_SET_ASSOCIATIVE  : begin
                                     s_newFifo[1]   <= 1'b0;
                                     s_newFifo[0]   <= ~s_stage3FifoReg[0];
                                     s_newLru1      <= {s_stage3Hit1Reg, s_stage3Hit1Reg};
                                     s_newLru2      <= {~s_stage3Hit1Reg, ~s_stage3Hit1Reg};
                                     s_newLru3      <= 2'b11;
                                     s_newLru4      <= 2'b11;
                                     s_newPlru[4:2] <= 3'b100;
                                     s_newPlru[1:0] <= {s_stage3Hit2Reg,s_stage3Hit1Reg};
                                   end
        default                  : begin
                                     s_newFifo <= 2'b00;
                                     s_newPlru <= 5'b10010;
                                     s_newLru1 <= 2'b00;
                                     s_newLru2 <= 2'b11;
                                     s_newLru3 <= 2'b11;
                                     s_newLru4 <= 2'b11;
                                   end
      endcase
    else 
      begin
        s_newFifo <= s_stage3FifoReg;
        s_newPlru <= s_stage3PlruReg;
        s_newLru1 <= s_stage3Lru1Reg;
        s_newLru2 <= s_stage3Lru2Reg;
        s_newLru3 <= s_stage3Lru3Reg;
        s_newLru4 <= s_stage3Lru4Reg;
      end

  always @ (posedge clock)
    begin
      s_stage3FifoReg           <= s_stage3FifoNext;
      s_stage3Lru1Reg           <= s_stage3Lru1Next;
      s_stage3Lru2Reg           <= s_stage3Lru2Next;
      s_stage3Lru3Reg           <= s_stage3Lru3Next;
      s_stage3Lru4Reg           <= s_stage3Lru4Next;
      s_stage3PlruReg           <= s_stage3PlruNext;
      s_stage3ReplacementWayReg <= s_stage3ReplacementWayNext;
    end
  
  sram512X32Dp policyRam ( .clockA(clock),
                           .writeEnableA(1'b0),
                           .addressA(s_tagStateLookupIndex),
                           .dataInA( {32{1'b0}} ),
                           .dataOutA(s_combinedPolicy),
                           .clockB(clock),
                           .writeEnableB(s_weNewPolicy),
                           .addressB(s_tagIndex),
                           .dataInB(s_newCombinedPolicy),
                           .dataOutB(s_dummyPolicy));

  /*
   *
   * Here the bus related signals are defined
   *
   */
  reg s_beginTransactionOutReg, s_busErrorReg, s_forceControlReg;
  reg [3:0] s_myBurstCountReg;
  reg [7:0] s_burstSizeOutReg;
  reg [31:0] s_busAddressReg;
  wire s_beginTransactionOutNext = (s_cacheStateReg == INIT_TRANSACTION) ? 1'b1 : 1'b0;
  wire s_weBusRegs = (s_cacheStateReg == INIT_TRANSACTION) ? 1'b1 : 1'b0;
  wire [7:0] s_burstSizeOutNext = (s_weBusRegs == 1'b0 || s_cacheEnabledReg == 1'b0) ? 8'h00 : 8'h07;
  wire [31:0] s_busAddressNext = (s_weBusRegs == 1'b0) ? {32{1'b0}} :
                                 (s_cacheEnabledReg == 1'b0) ? s_stage3PcReg : {s_stage3PcReg[31:5], {5{1'b0}}};
  wire s_busErrorNext = (busAccessGranted == 1'b1 || reset == 1'b1) ? 1'b0 : s_busErrorReg | busErrorIn;
  wire s_forceControlNext = (endTransactionIn == 1'b1 || reset == 1'b1) ? 1'b0 : s_forceControlReg | busAccessGranted;
  wire s_validDataIn = dataValidIn & ~busyIn & s_forceControlReg;
  wire [3:0] s_myBurstCountNext = (busAccessGranted == 1'b1 || reset == 1'b1) ? 4'h0 :
                                  (s_myBurstCountReg != 4'hF &
                                   s_validDataIn == 1'b1) ? s_myBurstCountReg + 4'd1 : s_myBurstCountReg;
  wire [2:0] s_wordBurstSelectNext = (reset == 1'b1 || busAccessGranted == 1'b1) ? 3'b000 :
                                     (s_busDataInValidReg == 1'b1) ? s_wordBurstSelectReg + 3'd1 : s_wordBurstSelectReg;
  wire s_busDataInValidNext = s_validDataIn & ~reset;
  wire [31:0] s_busDataInNext = (s_validDataIn == 1'b1) ? addressDataIn : s_busDataInReg;
  
  assign requestBus = (s_cacheStateReg == REQUEST_THE_BUS) ? 1'b1 : 1'b0;
  assign beginTransactionOut = s_beginTransactionOutReg;
  assign byteEnablesOut = (s_beginTransactionOutReg == 1'b1) ? 4'hF : 4'h0;
  assign burstSizeOut = s_burstSizeOutReg;
  assign addressDataOut = (s_beginTransactionOutReg == 1'b1) ? s_busAddressReg : {32{1'b0}};
  assign readNotWriteOut = s_beginTransactionOutReg;
  
  always @(posedge clock)
    begin
      s_beginTransactionOutReg <= s_beginTransactionOutNext;
      s_burstSizeOutReg        <= s_burstSizeOutNext;
      s_busAddressReg          <= s_busAddressNext;
      s_busErrorReg            <= s_busErrorNext;
      s_forceControlReg        <= s_forceControlNext;
      s_myBurstCountReg        <= s_myBurstCountNext;
      s_wordBurstSelectReg     <= s_wordBurstSelectNext;
      s_busDataInValidReg      <= s_busDataInValidNext;
      s_busDataInReg           <= s_busDataInNext;
    end
  
  /*
   *
   * here some control signals are defined
   *
   */
  assign s_internalStall = s_flushActiveReg |
                           (s_stage3ActivePcReg & ~s_stage3ValidReg & ~s_stage3Hit1Reg & ~s_stage3Hit2Reg & ~s_stage3Hit3Reg & ~s_stage3Hit4Reg);
  assign s_busError = (s_cacheStateReg == RELEASE &&
                       (s_busErrorReg == 1'b1 ||
                        (s_cacheEnabledReg == 1'b0 && s_myBurstCountReg != 4'h1) ||
                        (s_cacheEnabledReg == 1'b1 && s_myBurstCountReg != 4'h8))) ? 1'b1 : 1'b0;
  
  always @(posedge clock) s_cacheEnabledReg <= (reset == 1'b1) ? 1'b0 : (s_cacheStateReg == IDLE) ? cacheEnabled : s_cacheEnabledReg;

  /*
   *
   * here the state machine is defined
   *
   */
  reg [3:0] s_cacheStateNext;
  
  always @*
    case (s_cacheStateReg)
      IDLE             : s_cacheStateNext <= (s_flushActiveReg == 1'b1) ? FLUSH_INIT : (s_internalStall == 1'b1) ? REQUEST_THE_BUS : IDLE;
      REQUEST_THE_BUS  : s_cacheStateNext <= (busAccessGranted == 1'b1) ? INIT_TRANSACTION : REQUEST_THE_BUS;
      INIT_TRANSACTION : s_cacheStateNext <= WAIT_READ_BURST;
      WAIT_READ_BURST  : s_cacheStateNext <= (endTransactionIn == 1'b1 || busErrorIn == 1'b1) ? NOP : WAIT_READ_BURST;
      NOP              : s_cacheStateNext <= (s_cacheEnabledReg == 1'b1) ? UPDATE_TAGS : RELEASE;
      UPDATE_TAGS      : s_cacheStateNext <= RELEASE;
      FLUSH_INIT       : s_cacheStateNext <= DO_FLUSH;
      DO_FLUSH         : s_cacheStateNext <= (s_flushCounterReg == 8'hFF) ? FLUSH_DONE : DO_FLUSH;
      default          : s_cacheStateNext <= IDLE;
    endcase
    
    always @( posedge clock )
      if (reset == 1'b1) s_cacheStateReg <= IDLE;
      else s_cacheStateReg <= s_cacheStateNext;

  /*
   *
   * Here the profiling signals are defined
   *
   */
  always @(posedge clock)
    begin
      instructionFetch <= ~s_stall;
      cacheMiss        <= (s_cacheStateReg == INIT_TRANSACTION) ? 1'b1 : 1'b0;
      cacheMissActive  <= ~s_hit & ~s_stage3ValidReg & ~stall & ~s_flushActiveReg & ~s_flushCache;
      cacheFlushActive <= s_flushActiveReg | s_flushCache;
      cacheInsertedNop <= s_stage3InsertedNopReg;
    end 
endmodule
