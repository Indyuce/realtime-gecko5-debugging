/*
 * This module is based on the module present in the or1200
 * it is adapted to conncet to the or1300.
 * Note that the external interface can ONLY read/write the spr registers when
 * the core is stalled by the dbg_stall_i input!
 *
 * TODO: implement single-step trace (ST) and branche trace (BT)
 *
 */
module debugUnit #(parameter nrOfBreakpoints = 8) // maximum is 8, minimum 0
                 ( input wire         clock,
                                      reset,
                                      stallIn,
                                      ebuIsDelaySlotIsn,
                                      exeActiveInstruction,
                                      executingBranch,
                                      exceptionTaken,
                                      exeExecutedInstruction,
                                      isRfe,
                   input wire [2:0]   memoryStore,
                                      memoryLoad,
                   output wire        debugIrq,
                                      stallOut,
                   input wire [13:0]  exceptionReason,
                   input wire [15:0]  exeSprIndex,
                                      writeSprIndex,
                   input wire [31:0]  writeData,
                                      instructionFetchEa,
                                      memoryAddress,
                                      storeData,
                                      loadData,
                                      exeSprData,
                                      exeIrIn,
                                      exePcIn,
                   input wire         writeSpr,
                                      supervisionMode,
                                      dcacheRegisterWe,
                   output reg [31:0]  readSprData,
                   // here the exception branch unit interface is defined
                   output wire        debugJumpPending,
                   output wire [29:0] debugJumpAddress,
                   // here the internal spr interface is defined
                   input wire [31:0]  debugSprDataIn,
                   output reg         debugWeSprData,
                   output wire        debugReSprData,
                   output reg [31:0]  debugSprDataOut,
                   output reg [15:0]  debugSprSelect,
                   // here the or1200 external debug interface is defined
                   input wire         dbg_stall_i,  // External Stall Input
                                      dbg_ewt_i,    // External Watchpoint Trigger Input
                   output wire [3:0]  dbg_lss_o,    // External Load/Store Unit Status
                   output wire [1:0]  dbg_is_o,     // External Insn Fetch Status
                   output wire [10:0] dbg_wp_o,     // Watchpoints Outputs
                   output reg         dbg_bp_o,     // Breakpoint Output
                   input wire         dbg_stb_i,    // External Address/Data Strobe
                                      dbg_we_i,     // External Write Enable
                   input wire [15:0]  dbg_adr_i,    // External Address Input
                   input wire [31:0]  dbg_dat_i,    // External Data Input
                   output reg [31:0]  dbg_dat_o,    // External Data Output
                   output reg         dbg_ack_o);   // External Data Acknowledge (not WB compatible)

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

  /*
   *
   * Here the direct connections are defined
   *
   */
  reg [3:0] s_loadStoreStatus;
  wire [5:0] s_select = {memoryStore,memoryLoad};

  assign dbg_wp_o  = 11'd0;
  assign dbg_lss_o = s_loadStoreStatus;
  assign dbg_is_o  = (ebuIsDelaySlotIsn == 1'b1 && stallIn == 1'b0) ? 2'd3 : 
                     (executingBranch == 1'b1 && stallIn == 1'b0) ? 2'd2 :
                     (exeActiveInstruction == 1'b1 && stallIn == 1'b0) ? 2'd1 : 2'd0;
  
  always @*
    case (s_select)
      {STORE_BYTE,NO_LOAD}                    : s_loadStoreStatus <= 4'hA;
      {STORE_HALF_WORD,NO_LOAD}               : s_loadStoreStatus <= 4'hC;
      {STORE_WORD,NO_LOAD}                    : s_loadStoreStatus <= 4'hE;
      {NO_STORE,LOAD_BYTE_ZERO_EXTENDED}      : s_loadStoreStatus <= 4'h2;
      {NO_STORE,LOAD_BYTE_SIGN_EXTENDED}      : s_loadStoreStatus <= 4'h3;
      {NO_STORE,LOAD_HALF_WORD_ZERO_EXTENDED} : s_loadStoreStatus <= 4'h4;
      {NO_STORE,LOAD_HALF_WORD_SIGN_EXTENDED} : s_loadStoreStatus <= 4'h5;
      {NO_STORE,LOAD_WORD_ZERO_EXTENDED}      : s_loadStoreStatus <= 4'h6;
      {NO_STORE,LOAD_WORD_SIGN_EXTENDED}      : s_loadStoreStatus <= 4'h7;
      default                                 : s_loadStoreStatus <= 4'd0;
    endcase

  /*
   *
   * Here we define the acknowledgement
   *
   */
  reg dbgAckReg;
  always @(posedge clock)
    begin
      dbgAckReg <= (reset == 1'b1) ? 1'b0 : dbg_stb_i;
      dbg_ack_o <= (reset == 1'b1) ? 1'b0 : dbgAckReg & dbg_stb_i;
    end

  /*
   *
   * Here we define dmr1 Note: Watchpoints are not supported by this unit
   *
   */
  reg [31:0] s_dmr1;
  
  always @(posedge clock)
    s_dmr1 <= (reset == 1'b0) ? 32'd0 : 
              (writeSpr == 1'b1 && supervisionMode == 1'b1 && writeSprIndex == 16'h3010) ? {8'd0, writeData[23:22], 22'd0} : s_dmr1;
  
  /*
   *
   * Here the debug value and controll registers are defined
   *
   */
  reg [31:0] s_dvrReg [7:0];
  reg [31:0] s_dcrReg [7:0];
  reg [31:0] s_compareValue [7:0];
  wire signed [31:0] s_signedCompare [7:0];
  wire signed [31:0] s_signedDvr [7:0];
  reg [7:0]  s_hit1, s_hit2;
  wire [7:0] s_weDvrReg, s_weDcrReg;
  wire [7:0] s_breakpointHit = s_hit1 & s_hit2;
  
  assign debugIrq  = (s_breakpointHit != 8'd0) ? 1'b1 : 1'b0;
  
  always @(posedge clock) dbg_bp_o <= (reset == 1'b1) ? 1'b0 : (s_breakpointHit != 8'd0) ? 1'b1 : 1'b0;
  
  genvar n;
  
  generate
    for (n = 0; n < 8; n = n + 1)
      begin : gendvr
        assign s_weDvrReg[n] = (supervisionMode == 1'b1 && writeSprIndex[15:3] == 13'h600 && writeSprIndex[2:0] == n) ? writeSpr : 1'b0;
        assign s_weDcrReg[n] = (supervisionMode == 1'b1 && writeSprIndex[15:3] == 13'h601 && writeSprIndex[2:0] == n) ? writeSpr : 1'b0;
        assign s_signedCompare[n] = s_compareValue[n];
        assign s_signedDvr[n] = s_dvrReg[n];
        always @(posedge clock) s_dvrReg[n] <= (n >= nrOfBreakpoints) ? 32'd0 : (reset == 1'b1) ? 32'd0 : (s_weDvrReg[n] == 1'b1) ? writeData : s_dvrReg[n];
        always @(posedge clock) s_dcrReg[n] <= (n >= nrOfBreakpoints) ? 32'd0 : (reset == 1'b1) ? 32'd1 : (s_weDcrReg[n] == 1'b1) ? {24'd0, writeData[7:1], 1'b1} : s_dcrReg[n];
        always @*
          case (s_dcrReg[n][3:1])
            3'd1    : s_compareValue[n] <= (n < nrOfBreakpoints) ? instructionFetchEa : 32'd0;
            3'd2,
            3'd3,
            3'd6    : s_compareValue[n] <= (n < nrOfBreakpoints) ? memoryAddress : 32'd0;
            3'd4    : s_compareValue[n] <= (n < nrOfBreakpoints) ? storeData : 32'd0;
            3'd5    : s_compareValue[n] <= (n < nrOfBreakpoints) ? loadData : 32'd0;
            default : s_compareValue[n] <= (n >= nrOfBreakpoints) ? 32'd0 : (dcacheRegisterWe == 1'd1) ? loadData : storeData;
          endcase
        always @*
          case (s_dcrReg[n][7:5])
            3'd1    : s_hit1[n] <= 1'b1;
            3'd2    : s_hit1[n] <= (memoryLoad != NO_LOAD && n < nrOfBreakpoints) ? 1'b1 : 1'b0;
            3'd3    : s_hit1[n] <= (memoryStore != NO_STORE && n < nrOfBreakpoints) ? 1'b1 : 1'b0;
            3'd4    : s_hit1[n] <= (n < nrOfBreakpoints) ? dcacheRegisterWe : 1'b0;
            3'd5    : s_hit1[n] <= (memoryStore != NO_STORE && n < nrOfBreakpoints) ? 1'b1 : 1'b0;
            3'd6    : s_hit1[n] <= ((memoryLoad != NO_LOAD || memoryStore != NO_STORE) && n < nrOfBreakpoints) ? 1'b1 : 1'b0;
            3'd7    : s_hit1[n] <= ((dcacheRegisterWe == 1'b1 || memoryStore != NO_STORE) && n < nrOfBreakpoints) ? 1'b1 : 1'b0;
            default : s_hit1[n] <= 1'b0;
          endcase
        always @*
          case (s_dcrReg[n][4:1])
            4'b0001,
            4'b1001 : s_hit2[n] <= (s_compareValue[n] == s_dvrReg[n] && n < nrOfBreakpoints) ? 1'b1 : 1'b0;
            4'b0110,
            4'b1110 : s_hit2[n] <= (s_compareValue[n] != s_dvrReg[n] && n < nrOfBreakpoints) ? 1'b1 : 1'b0;
            4'b0010 : s_hit2[n] <= (s_dvrReg[n] < s_compareValue[n] && n < nrOfBreakpoints) ? 1'b1 : 1'b0;
            4'b0011 : s_hit2[n] <= (s_dvrReg[n] <= s_compareValue[n] && n < nrOfBreakpoints) ? 1'b1 : 1'b0;
            4'b0100 : s_hit2[n] <= (s_dvrReg[n] > s_compareValue[n] && n < nrOfBreakpoints) ? 1'b1 : 1'b0;
            4'b0101 : s_hit2[n] <= (s_dvrReg[n] >= s_compareValue[n] && n < nrOfBreakpoints) ? 1'b1 : 1'b0;
            4'b1010 : s_hit2[n] <= (s_signedDvr[n] < s_signedCompare[n] && n < nrOfBreakpoints) ? 1'b1 : 1'b0;
            4'b1011 : s_hit2[n] <= (s_signedDvr[n] <= s_signedCompare[n] && n < nrOfBreakpoints) ? 1'b1 : 1'b0;
            4'b1100 : s_hit2[n] <= (s_signedDvr[n] > s_signedCompare[n] && n < nrOfBreakpoints) ? 1'b1 : 1'b0;
            4'b1101 : s_hit2[n] <= (s_signedDvr[n] >= s_signedCompare[n] && n < nrOfBreakpoints) ? 1'b1 : 1'b0;
            default : s_hit2[n] <= 1'b0;
          endcase
      end
  endgenerate

  /*
   *
   * Here the drr and dsr are defined
   *
   */
  reg         s_trapActiveReg;
  reg [31:0]  s_ddrReg, s_dsrReg;
  wire [13:0] s_stopVector = (exceptionTaken == 1'b1) ? s_dsrReg[13:0] & exceptionReason : 14'd0;

  assign stallOut  = (dbg_stall_i == 1'b1 || s_stopVector != 14'd0) ? 1'b1 : 1'b0;
  
  always @(posedge clock) 
    begin
      s_ddrReg        <= (reset == 1'b1) ? 32'd0 : 
                         (exceptionTaken == 1'b1) ? {18'd0, exceptionReason} :
                         (writeSpr == 1'b1 && supervisionMode == 1'b1 && writeSprIndex == 16'h3015) ? {18'd0, writeData[13:0]} : s_ddrReg;
      s_dsrReg        <= (reset == 1'b1) ? 32'd0 :
                         (writeSpr == 1'b1 && supervisionMode == 1'b1 && writeSprIndex == 16'h3014) ? {18'd0, writeData[13:0]} : s_dsrReg;
      s_trapActiveReg <= (reset == 1'b1 || isRfe == 1'b1) ? 1'b0 : (exceptionTaken == 1'b1 && exceptionReason[13] == 1'b1) ? 1'b1 : s_trapActiveReg;
    end
  
  /*
   *
   * Here the debug read and write interface are defined
   *
   */
  
  assign debugReSprData = dbg_stb_i & ~dbg_we_i & dbg_stall_i;
  
  always @(posedge clock)
    begin
      dbg_dat_o       <= debugSprDataIn;
      debugWeSprData  <= (reset == 1'b1) ? 1'd0 : dbg_stb_i & dbg_we_i & dbg_stall_i;
      debugSprDataOut <= (reset == 1'b1) ? 32'd0 : dbg_dat_i;
      debugSprSelect  <= (reset == 1'b1) ? 16'd0 : dbg_adr_i;
    end
  
  /*
   *
   * Here the nextpc jumping is implemented
   *
   */
  reg [29:0] s_jumpAddressReg;
  reg        s_pendingJumpReg;
  wire s_wePc = (writeSpr == 1'b1 && supervisionMode == 1'b1 && writeSprIndex == 16'h0010) ? 1'b1 : 1'b0;
  
  assign debugJumpPending = s_pendingJumpReg;
  assign debugJumpAddress = s_jumpAddressReg;
  
  always @(posedge clock)
    begin
      s_jumpAddressReg <= (reset == 1'b1) ? 30'd0 : (s_wePc == 1'b1) ? writeData[31:2] : s_jumpAddressReg;
      s_pendingJumpReg <= (reset == 1'b1 || stallIn == 1'b0) ? 1'b0 : s_pendingJumpReg | s_wePc;
    end
  
  /*
   *
   * Here the trace buffer is defined
   *
   */
  reg[7:0]    s_writeAddressReg;
  reg[31:0]   s_timeStampReg;
  wire [31:0] s_tracePc, s_traceIr, s_traceData, s_traceTimeStamp;
  wire        s_weTrace = exeExecutedInstruction & ~stallIn & ~s_trapActiveReg;
  
  always @(posedge clock)
    begin
      s_writeAddressReg <= (reset == 1'b1) ? 8'd0 : (s_weTrace == 1'b1) ? s_writeAddressReg + 8'd1 : s_writeAddressReg;
      s_timeStampReg    <= (reset == 1'b1) ? 32'd0 : s_timeStampReg + 32'd1;
    end
  
  sram512X32Dp traceback1 ( .clockA(~clock),
                            .writeEnableA(1'b0),
                            .addressA(exeSprIndex[7:0]),
                            .dataInA(32'd0),
                            .dataOutA(s_tracePc),
                            .clockB(clock),
                            .writeEnableB(s_weTrace),
                            .addressB(s_writeAddressReg),
                            .dataInB(exePcIn),
                            .dataOutB());
                            
  sram512X32Dp traceback2 ( .clockA(~clock),
                            .writeEnableA(1'b0),
                            .addressA(exeSprIndex[7:0]),
                            .dataInA(32'd0),
                            .dataOutA(s_traceIr),
                            .clockB(clock),
                            .writeEnableB(s_weTrace),
                            .addressB(s_writeAddressReg),
                            .dataInB(exeIrIn),
                            .dataOutB());
                            
  sram512X32Dp traceback3 ( .clockA(~clock),
                            .writeEnableA(1'b0),
                            .addressA(exeSprIndex[7:0]),
                            .dataInA(32'd0),
                            .dataOutA(s_traceData),
                            .clockB(clock),
                            .writeEnableB(s_weTrace),
                            .addressB(s_writeAddressReg),
                            .dataInB(writeData),
                            .dataOutB());

  sram512X32Dp traceback4 ( .clockA(~clock),
                            .writeEnableA(1'b0),
                            .addressA(exeSprIndex[7:0]),
                            .dataInA(32'd0),
                            .dataOutA(s_traceTimeStamp),
                            .clockB(clock),
                            .writeEnableB(s_weTrace),
                            .addressB(s_writeAddressReg),
                            .dataInB(s_timeStampReg),
                            .dataOutB());
  /*
   *
   * Here the registers are put on the output
   *
   */
  always @*
    case (exeSprIndex[15:8])
      8'h30    : case (exeSprIndex[7:0])
                   8'h00   : readSprData <= s_dvrReg[0];
                   8'h01   : readSprData <= s_dvrReg[1];
                   8'h02   : readSprData <= s_dvrReg[2];
                   8'h03   : readSprData <= s_dvrReg[3];
                   8'h04   : readSprData <= s_dvrReg[4];
                   8'h05   : readSprData <= s_dvrReg[5];
                   8'h06   : readSprData <= s_dvrReg[6];
                   8'h07   : readSprData <= s_dvrReg[7];
                   8'h08   : readSprData <= s_dcrReg[0];
                   8'h09   : readSprData <= s_dcrReg[1];
                   8'h0A   : readSprData <= s_dcrReg[2];
                   8'h0B   : readSprData <= s_dcrReg[3];
                   8'h0C   : readSprData <= s_dcrReg[4];
                   8'h0D   : readSprData <= s_dcrReg[5];
                   8'h0E   : readSprData <= s_dcrReg[6];
                   8'h0F   : readSprData <= s_dcrReg[7];
                   8'h10   : readSprData <= s_dmr1;
                   8'h14   : readSprData <= s_dsrReg;
                   8'h15   : readSprData <= s_ddrReg;
                   8'hFF   : readSprData <= {24'd0, s_writeAddressReg};
                   default : readSprData <= 32'd0;
                 endcase
      8'h31    : readSprData <= s_tracePc;
      8'h32    : readSprData <= s_traceIr;
      8'h33    : readSprData <= s_traceData;
      8'h34    : readSprData <= s_traceTimeStamp;
      default  : readSprData <= 32'd0;
    endcase
endmodule
