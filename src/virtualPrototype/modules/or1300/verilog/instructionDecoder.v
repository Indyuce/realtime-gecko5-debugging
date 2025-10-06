module instructionDecoder ( input wire         clock,
                                               reset,
                                               stall,
                                               flush,
                             
                            // Here the i$ interface is defined
                            input wire [31:0]  ir,
                                               pc,
                            input wire         resetFilterIn,
                                               abort,
                                               insertedNop,
                            output wire        jump,
                            
                            // Here the register file interface is defined
                            input wire [3:0]   cid,
                            output wire [8:0]  lookupOperantAAddr,
                                               lookupOperantBAddr,
                            input wire [31:0]  rfOperantA,
                                               rfOperantB,
                            
                            // Here the forward unit signals are defined
                            input wire [31:0]  forwardedOperantA,
                                               forwardedOperantB,
                                               forwardedStoreData,
                            input wire         useForwardedOperantA,
                                               useForwardedOperantB,
                                               useForwardedStoreData,
                            output wire        useImmediate,
                            output wire [2:0]  isStore,
                            
                            // here the interface to the exception branch unit is defined
                            output wire        ebuIsDelaySlotIsn,
                            
                            // here the interface to the debug unit is defined
                            output reg         executingBranch,
                            
                            // here the d-cache signals are defined
                            input wire         dcacheWe,
                            input wire [8:0]   dcacheTarget,
                            input wire [31:0]  dcacheDataIn,
                            
                            // Here the execution unit interface signals are defined
                            output wire [31:0] exeOperantA,
                                               exeOperantB,
                                               instructionAddress,
                                               exestoreData,
                                               exeIr,
                            output wire [4:0]  exeOperantAAddr,
                                               exeOperantBAddr,
                                               exeStoreAddr,
                            output wire [8:0]  exeDestination,
                            output wire        exeWeDestination,
                                               exeIsJump,
                                               exeValidInstruction,
                                               exeActiveInstruction,
                                               exeCustom,
                                               exeInstructionAbort,
                                               exeIsRfe,
                                               exeSystemCall,
                                               exeTrap,
                                               exeDivide,
                                               exeMultiply,
                                               exeUpdateCarry,
                                               exeUpdateOverflow,
                                               exeUpdateFlag,
                            output wire [1:0]  exeIsSpr,
                                               exeSyncCommand,
                            output wire [2:0]  exeExeControl,
                                               exeResultSelection,
                                               exeStore,
                                               exeLoad,
                            output wire [3:0]  exeCompareCntrl,
                            output wire [15:0] exeSprOrMask,
                                               exeImediateValue,
                            input wire         fastFlag,
                            
                            // here the profiling interface is defined
                            output wire        branchPenalty);

  localparam [31:0] CONTEXT_SYNC_COMMAND = 32'h23000000;
  localparam [31:0] MEMORY_SYNC_COMMAND  = 32'h22000000;
  localparam [31:0] PIPE_SYNC_COMMAND    = 32'h22800000;
  localparam [15:0] SYSTEM_CALL_COMMAND  = 16'h2000;
  localparam [15:0] TRAP_COMMAND         = 16'h2100;
  localparam [2:0]  SIGN_EXTENDED_HW     = 3'd0;
  localparam [2:0]  SIGN_EXTENDED_EHW    = 3'd1;
  localparam [2:0]  HW_MOVED_HIGH        = 3'd2;
  localparam [2:0]  SIGN_EXTENDED_BHW    = 3'd3;
  localparam [2:0]  ZERO_EXTENDED_HW     = 3'd4;
  localparam [1:0]  JUMP_ALWAYS_B        = 2'd0;
  localparam [1:0]  JUMP_ALWAYS          = 2'd1;
  localparam [1:0]  JUMP_FLAG_CLEAR      = 2'd2;
  localparam [1:0]  JUMP_FLAG_SET        = 2'd3;

  reg [31:0] s_imediateValue;
  wire s_validInstruction         = ((ir[31:26] == 6'b111000 && ir[9:8] == 2'b00 && (ir[3:0] == 4'h0 || ir[3:0] == 4'h1 || ir[3:0] == 4'h2 || ir[3:0] == 4'h3 || ir[3:0] == 4'h4 ||
                                      ir[3:0] == 4'h5 || ir[3:0] == 4'h8 || ir[3:0] == 4'hC || ir[3:0] == 4'hD || ir[3:0] == 4'hE)) ||
                                     (ir[31:26] == 6'b111000 && ir[9] == 1'b0 && ir[3:0] == 4'hF) || ir[31:26] == 6'b100111 || ir[31:28] == 4'b1010 || ir[31:24] == 8'h15 ||
                                     ir[31:26] == 6'b000000 || ir[31:26] == 6'b101110 || ir[31:26] == 6'b001001 || ir[31:25] == 7'b1110010 || ir[31:25] == 7'b1011110 ||
                                     (ir[31:26] == 6'b000110 && ir[16] == 1'b0) || ir[31:26] == 6'b010001 || ir[31:26] == 6'b000001 || ir[31:26] == 6'b010010 || ir[31:26] == 6'b000011 ||
                                     ir[31:26] == 6'b000100 || (ir[31:26] == 6'b111000 && ir[9:8] == 2'b11 && (ir[3:0] == 4'h9 || ir[3:0] == 4'hA)) || ir[31:26] == 6'b010011 ||
                                     (ir[31:26] == 6'b110001 && (ir[3:0] == 4'h1 || ir[4:0] == 4'h2)) || (ir[31:26] == 6'b000110 && ir[16] == 1'b1 && ir[15:0] == 16'd0) ||
                                     (ir[31:26] == 6'b111000 && ir[9:8] == 2'b11 && (ir[3:0] == 4'h6 || ir[3:0] == 4'hB)) || ir[31:26] == 6'b101100 || ir[31:26] == 6'b011100 ||
                                     ir[31:26] == 6'b110101 || ir[31:26] == 6'b110110 || ir[31:26] == 6'b110111 || ir[31:26] == 6'b100001 || ir[31:26] == 6'b100010 || 
                                     ir[31:26] == 6'b100011 || ir[31:26] == 6'b100100 || ir[31:26] == 6'b100101 || ir[31:26] == 6'b100110 || ir[31:26] == 6'b101101 ||
                                     ir[31:26] == 6'b110000 || (ir[31:26] == 6'b011101 && ir[10] == 1'b0) || ir == CONTEXT_SYNC_COMMAND || ir == MEMORY_SYNC_COMMAND ||
                                     ir == PIPE_SYNC_COMMAND || ir[31:16] == SYSTEM_CALL_COMMAND || ir[31:16] == TRAP_COMMAND) ? 1'b1 : 1'b0;
  wire [4:0] s_operantAAddr       = ir[20:16];
  wire s_usePc                    = (ir[31:27] == 5'b00000 || ir[31:26] == 6'b000011 || ir[31:26] == 6'b000100) ? 1'b1 : 1'b0;
  wire [2:0] s_imediateFormat, s_store, s_exeControl, s_resultSelection, s_load;
  wire [1:0] s_isSpr, s_jumpCondition;
  wire [8:0] s_lookupOperantBAddr = (ir[31:26] == 6'b101101) ? {cid, 5'd0} : {cid, ir[15:11]};
  wire s_useImediate              = (ir[31:26] == 6'b100111 || ir[31:28] == 4'b1010 || ir[31:26] == 6'b101110 || ir[31:27] == 5'b00000 || ir[31:25] == 7'b1011110 ||
                                     (ir[31:26] == 6'b000110 && ir[16] == 1'b0) || ir[31:26] == 6'b010011 || ir[31:26] == 6'b101100 || 
                                     ir[31:26] == 6'b110101 || ir[31:26] == 6'b110110 || ir[31:26] == 6'b110111 || ir[31:26] == 6'b000011 ||
                                     ir[31:26] == 6'b000100 || ir[31:26] == 6'b100001 || ir[31:26] == 6'b100010 || ir[31:26] == 6'b100011 ||
                                     ir[31:26] == 6'b100100 || ir[31:26] == 6'b100101 || ir[31:26] == 6'b100110 ||
                                     ir[31:16] == TRAP_COMMAND) ? 1'b1 : 1'b0;
  wire s_isJump                   = (ir[31:27] == 5'b00000 || ir[31:26] == 6'b010001 || ir[31:26] == 6'b010010 ||
                                     ir[31:26] == 6'b000011 || ir[31:26] == 6'b000100) ? 1'b1 : 1'b0;
  wire [4:0] s_destination        = (ir[31:26] == 6'b000001 || ir[31:26] == 6'b010010) ? 5'b01001 : ir[25:21];
  wire s_weDestination            = ((ir[31:26] == 6'b111000 && ir[9:8] == 2'b00 && (ir[3:0] == 4'h0 || ir[3:0] == 4'h1 || ir[3:0] == 4'h2 || ir[3:0] == 4'h3 || ir[3:0] == 4'h4 ||
                                      ir[3:0] == 4'h5 || ir[3:0] == 4'h8 || ir[3:0] == 4'hC || ir[3:0] == 4'hD || ir[3:0] == 4'hE)) ||
                                     (ir[31:26] == 6'b111000 && ir[9] == 1'b0 && ir[3:0] == 4'hF) || (ir[31:26] == 6'b000110 && ir[16] == 1'b0) ||
                                     ir[31:26] == 6'b100111 || ir[31:26] == 6'b101110 || ir[31:28] == 4'b1010 || ir[31:26] == 6'b000001 ||
                                     (ir[31:26] == 6'b000110 && ir[16] == 1'b1 && ir[15:0] == 16'd0) || ir[31:26] == 6'b101100 ||
                                     (ir[31:26] == 6'b111000 && ir[9:8] == 2'b11 && (ir[3:0] == 4'h6 || ir[3:0] == 4'hB)) ||
                                     (ir[31:26] == 6'b111000 && ir[9:8] == 2'b11 && (ir[3:0] == 4'h9 || ir[3:0] == 4'hA)) ||
                                     (ir[31:26] == 6'b011100 && ir[8] == 1'b0) || ir[31:26] == 6'b010010 || ir[31:26] == 6'b101101) ? 1'b1 : 1'b0;
  wire s_activeInstruction        = (ir[31:24] != 8'h15) ? s_validInstruction : 1'b0;
  wire s_custom                   = (ir[31:26] == 6'b011100) ? 1'b1 : 1'b0;
  wire s_isRfe                    = (ir[31:26] == 6'b001001) ? 1'b1 : 1'b0;
  wire s_systemCall               = (ir[31:16] == SYSTEM_CALL_COMMAND) ? 1'b1 : 1'b0;
  wire s_trap                     = (ir[31:16] == TRAP_COMMAND) ? 1'b1 : 1'b0;
  wire s_divide                   = (ir[31:26] == 6'b111000 && ir[9:8] == 2'b11 && (ir[3:0] == 4'h9 || ir[3:0] == 4'hA)) ? 1'b1 : 1'b0;
  wire s_multiply                 = ( (ir[31:26] == 6'b110001 && (ir[3:0] == 4'd1 || ir[3:0] == 4'd2)) ||
                                      ir[31:26] == 6'b010011 ||
                                      (ir[31:26] == 6'b000110 && ir[16] == 1'b1 && ir[15:0] == 16'd0) ||
                                      (ir[31:26] == 6'b111000 && ir[9:8] == 2'b11 && (ir[3:0] == 4'h6 || ir[3:0] == 4'hB)) ||
                                      ir[31:26] == 6'b101100) ? 1'b1 : 1'b0;
  wire s_updateCarry              = ((ir[31:26] == 6'b111000 && ir[9:8] == 2'b00 && ir[3:2] == 2'b00) ||
                                     (ir[31:26] == 6'b111000 && ir[9:8] == 2'b11 && (ir[3:0] == 4'h9 || ir[3:0] == 4'ha)) ||
                                     ir[31:26] == 6'b100111 || ir[31:26] == 6'b101000) ? 1'b1 : 1'b0;
  wire s_updateOverflow           = ((ir[31:26] == 6'b111000 && ir[9:8] == 2'b00 && ir[3:2] == 2'b00) ||
                                     (ir[31:26] == 6'b111000 && ir[9:8] == 2'b11 && (ir[3:0] == 4'h6 || ir[3:0] == 4'hB)) ||
                                     ir[31:26] == 6'b100111 || ir[31:26] == 6'b101100 || ir[31:26] == 6'b101000) ? 1'b1 : 1'b0;
  wire s_updateFlag               = (ir[31:25] == 7'b1110010 || ir[31:25] == 7'b1011110) ? 1'b1 : 1'b0;
  wire [1:0] s_syncCommand        = (ir == CONTEXT_SYNC_COMMAND || ir == MEMORY_SYNC_COMMAND || ir == PIPE_SYNC_COMMAND) ? ~ir[24:23] : 2'd0;
  wire [3:0] s_compareCntrl       = ir[24:21];

  assign lookupOperantAAddr   = {cid, s_operantAAddr};
  assign useImmediate         = s_useImediate;
  assign isStore              = s_store;
  assign lookupOperantBAddr   = s_lookupOperantBAddr;
  assign s_imediateFormat[2]  = (ir[31:26] == 6'b101001 || ir[31:26] == 6'b101010) ? 1'b1 : 1'b0;
  assign s_imediateFormat[1]  = ( (ir[31:26] == 6'b000110 && ir[16] == 1'b0) || ir[31:26] == 6'b110101 || ir[31:26] == 6'b110110 ||
                                ir[31:26] == 6'b110111 || ir[31:26] == 6'b110000 || ir[31:26] == 6'b010011) ? 1'b1 : 1'b0;
  assign s_imediateFormat[0]  = (ir[31:27] == 5'b00000 || ir[31:26] == 6'b110101 || ir[31:26] == 6'b110110 || ir[31:26] == 6'b110111 ||
                                ir[31:26] == 6'b010011 || ir[31:26] == 6'b000011 || ir[31:26] == 6'b110000 || ir[31:26] == 6'b000100) ? 1'b1 : 1'b0;
  assign s_isSpr[1]           = (ir[31:26] == 6'b101101 || ir[31:26] == 6'b110000) ? 1'b1 : 1'b0;
  assign s_isSpr[0]           = (ir[31:26] == 6'b101101) ? 1'b1 : 1'b0;
  assign s_jumpCondition[1]   = (ir[31:26] == 6'b000011 || ir[31:26] == 6'b000100) ? 1'b1 : 1'b0;
  assign s_jumpCondition[0]   = (ir[31:26] == 6'b000100 || ir[31:26] == 5'b00000) ? 1'b1 : 1'b0;
  assign s_store[2]           = (ir[31:26] == 6'b011101 && ir[10] == 1'b0) ? 1'b1 : 1'b0;
  assign s_store[1]           = (ir[31:26] == 6'b110111 || ir[31:26] == 6'b110101 || (ir[31:26] == 6'b011101 && ir[10:9] == 2'b01)) ? 1'b1 : 1'b0;
  assign s_store[0]           = (ir[31:26] == 6'b110101 || ir[31:26] == 6'b110110 || (ir[31:26] == 6'b011101 && ir[10] == 1'b0 && ir[8] == 1'b1)) ? 1'b1 : 1'b0;
  assign s_exeControl[2]      = ((ir[31:26] == 6'b000110 && ir[16] == 1'b1 && ir[15:0] == 16'd0) ||
                                 (ir[31:26] == 6'b111000 && ir[3:0] == 4'hC)) ? 1'b1 : 1'b0;
  assign s_exeControl[1]      = ((ir[31:26] == 6'b111000 && ((( ir[2] == 1'b1 || ir[2:0] == 3'b010) && ir[3] == 1'b0 && ir[9:8] == 2'b00) ||
                                  ((ir[3:0] == 4'hC || ir[3:0] == 4'h8) && ir[7] == 1'b1) || (ir[3:0] == 4'hF && ir[8] == 1'b1))) ||
                                 ir[31:27] == 5'b10101 || (ir[31:26] == 6'b101110 && ir[7] == 1'b1) || ir[31:25] == 7'b1110010 || ir[31:25] == 7'b1011110 ||
                                 (ir[31:26] == 6'b110001 && (ir[3:0] == 4'h1 || ir[3:0] == 4'h2))) ? 1'b1 : 1'b0;
  assign s_exeControl[0]      = ((ir[31:26] == 6'b111000 && ((ir[0] == 1'b1 && ir[3] == 1'b0) || ((ir[3:0] == 4'hC || ir[3:0] == 4'h8) && ir[6] == 1'b1) || ir[3:0] == 4'hF)) ||
                                 (ir[31:26] == 6'b111000 && ir[9:8] == 2'b11 && ir[3:0] == 4'h9) ||
                                 (ir[31:26] == 6'b110001 && ir[3:0] == 4'h2) || (ir[31:26] == 6'b111000 && ir[9:8] == 2'b11 && ir[3:0] == 4'h6) ||
                                 (ir[31:28] == 4'b1010 && ir[27:26] != 2'b10) || (ir[31:26] == 6'b101110 && ir[6] == 1'b1) ||
                                 ir[31:26] == 6'b010011 || ir[31:26] == 6'b101100) ? 1'b1 : 1'b0;
  assign s_resultSelection[2] = (ir[31:26] == 6'b000001 || ir[31:26] == 6'b101101 || ir[31:26] == 6'b110000 ||
                                 (ir[31:26] == 6'b111000 && ir[9:8] == 2'b11 && (ir[3:0] == 4'h9 || ir[3:0] == 4'hA)) ||
                                 (ir[31:26] == 6'b000110 && ir[16] == 1'b1 && ir[15:0] == 16'd0) ||
                                 (ir[31:26] == 6'b111000 && ir[9:8] == 2'b11 && (ir[3:0] == 4'h6 || ir[3:0] == 4'hB)) ||
                                 ir[31:26] == 6'b101100 || ir[31:26] == 6'b011100 || ir[31:26] == 6'b010010) ? 1'b1 : 1'b0;
  assign s_resultSelection[1] = ((ir[31:26] == 6'b111000 && ir[9:8] == 2'b00 && (ir[3:0] == 4'h8 || ir[3:0] == 4'hE)) ||
                                 (ir[31:26] == 6'b000110 && ir[16] == 1'b1 && ir[15:0] == 16'd0) ||
                                 (ir[31:26] == 6'b111000 && ir[9:8] == 2'b11 && (ir[3:0] == 4'h6 || ir[3:0] == 4'hB)) ||
                                 ir[31:26] == 6'b101100 || ir[31:26] == 6'b011100 ||
                                 (ir[31:26] == 6'b111000 && ir[9] == 1'b0 && ir[3:0] == 4'hF) ||
                                 ir[31:26] == 6'b101110) ? 1'b1 : 1'b0;
  assign s_resultSelection[0] = ((ir[31:26] == 6'b111000 && ir[9:8] == 2'b00 && (ir[3:0] == 4'h3 || ir[3:0] == 4'h4 ||
                                  ir[3:0] == 4'h5 || ir[3:0] == 4'hC || ir[3:0] == 4'hD || ir[3:0] == 4'hE)) ||
                                 (ir[31:26] == 6'b111000 && ir[9:8] == 2'b11 && (ir[3:0] == 4'h9 || ir[3:0] == 4'hA)) ||
                                 (ir[31:26] == 6'b111000 && ir[9] == 1'b0 && ir[3:0] == 4'hF) ||
                                 ir[31:26] == 6'b011100 || (ir[31:28] == 4'b1010 && ir[27:26] != 2'b00)) ? 1'b1 : 1'b0;
   assign s_load[2]           = ((ir[31:26] == 6'b100010 || ir[31:26] == 6'b100110 || ir[31:26] == 6'b100100) &&
                                 ir[25:21] != 5'd0) ? 1'b1 : 1'b0;
   assign s_load[1]           = ((ir[31:26] == 6'b100110 || ir[31:26] == 6'b100101 || ir[31:26] == 6'b100010 || ir[31:26] == 6'b100001) &&
                                 ir[25:21] != 5'd0) ? 1'b1 : 1'b0;
   assign s_load[0]           = ((ir[31:26] == 6'b100100 || ir[31:26] == 6'b100011 || ir[31:26] == 6'b100010 || ir[31:26] == 6'b100001) &&
                                 ir[25:21] != 5'd0) ? 1'b1 : 1'b0;
  
  /*
   *
   * Here we determine the imediate value
   *
   */
  always @*
    case (s_imediateFormat)
      SIGN_EXTENDED_EHW : s_imediateValue <= { {4{ir[25]}}, ir[25:0], 2'd0 };
      ZERO_EXTENDED_HW  : s_imediateValue <= { 16'd0, ir[15:0] };
      SIGN_EXTENDED_HW  : s_imediateValue <= { {16{ir[15]}}, ir[15:0] };
      HW_MOVED_HIGH     : s_imediateValue <= { ir[15:0], 16'd0 };
      default           : s_imediateValue <= { {16{ir[25]}}, ir[25:21], ir[10:0] };
    endcase

  /*
   *
   * Here some control signals are defined
   *
   */
  reg s_correctJumpFilterActiveReg, s_isJumpReg, s_isDelaySlotReg, s_branchPenaltyReg;
  reg [1:0] s_jumpConditionReg;
  wire s_jump = (s_isJumpReg == 1'b1 && stall == 1'b0 && flush == 1'b0 &&
                 (s_jumpConditionReg == JUMP_ALWAYS || s_jumpConditionReg == JUMP_ALWAYS_B ||
                  (s_jumpConditionReg == JUMP_FLAG_CLEAR && fastFlag == 1'b0) ||
                  (s_jumpConditionReg == JUMP_FLAG_SET && fastFlag == 1'b1))) ? 1'b1 : 1'b0;
  wire s_correctJumpFlush = (s_correctJumpFilterActiveReg == 1'b1 && s_isDelaySlotReg == 1'b0 && resetFilterIn == 1'b0) ? 1'b1 : 1'b0;
  wire s_correctJumpFilterActiveNext = (reset == 1'b1) ? 1'b0:
                                       (stall == 1'b1) ? s_correctJumpFilterActiveReg :
                                       (flush == 1'b1) ? 1'b0 :
                                       (s_jump == 1'b1) ? 1'b1 :
                                       (resetFilterIn == 1'b1) ? 1'b0 : s_correctJumpFilterActiveReg;
  wire s_isJumpNext = (reset == 1'b1) ? 1'b0 :
                      (stall == 1'b1) ? s_isJumpReg :
                      (s_correctJumpFlush == 1'b1 || flush == 1'b1) ? 1'b0 : s_isJump;
  wire s_isDelaySlotNext = (reset == 1'b1) ? 1'b0 :
                           (stall == 1'b1) ? s_isDelaySlotReg :
                           (s_isJump == 1'b1 && s_correctJumpFlush == 1'b0) ? 1'b1 :
                           (insertedNop == 1'b0) ? 1'b0 : s_isDelaySlotReg;
  wire [1:0] s_jumpConditionNext = (stall == 1'b1) ? s_jumpConditionReg : (s_isJump == 1'b1) ? s_jumpCondition : s_jumpConditionReg;
  wire s_branchPenaltyNext = (stall == 1'b1) ? s_branchPenaltyReg : s_correctJumpFlush;
  
  assign exeIsJump     = s_isJumpReg;
  assign jump          = s_jump;
  assign branchPenalty = s_branchPenaltyReg;
  
  always @(posedge clock)
    begin
      s_correctJumpFilterActiveReg <= s_correctJumpFilterActiveNext;
      s_isJumpReg                  <= s_isJumpNext;
      s_isDelaySlotReg             <= s_isDelaySlotNext;
      s_jumpConditionReg           <= s_jumpConditionNext;
      s_branchPenaltyReg           <= s_branchPenaltyNext;
      executingBranch              <= s_jumpConditionReg[1];
    end
  /*
   *
   * Here the pipeline registers are defined
   *
   */
  reg [31:0] s_exeOperantAReg, s_exeOperantBReg, s_instructionAddressReg, s_storeDataReg, s_irReg;
  reg [4:0] s_storeAddrReg, s_operantAAddrReg, s_operantBAddrReg;
  reg [2:0] s_exeControlReg, s_resultSelectionReg, s_storeReg, s_loadReg;
  reg [3:0] s_compareCntrlReg;
  reg [8:0] s_destinationReg;
  reg s_weDestinationReg, s_validInstructionReg, s_activeInstructionReg, s_CustomReg;
  reg s_InstructionAbortReg, s_isRfeReg, s_systemCallReg, s_trapReg, s_divideReg;
  reg s_multiplyReg, s_updateCarryReg, s_updateOverflowReg, s_updateFlagReg, s_isDelaySlotIsnReg;
  reg [1:0] s_isSprReg, s_syncCommandReg;
  reg [15:0] s_sprOrMaskReg;
  wire [31:0] s_exeOperantANext = (stall == 1'b1 && dcacheWe == 1'b1 && dcacheTarget[8:5] == cid && dcacheTarget[4:0] == s_operantAAddrReg) ? dcacheDataIn :
                                  (stall == 1'b1) ? s_exeOperantAReg :
                                  (s_usePc == 1'b1) ? pc :
                                  (s_operantAAddr == 5'd0) ? 32'd0 :
                                  (useForwardedOperantA == 1'b1) ? forwardedOperantA : rfOperantA;
  wire [31:0] s_exeOperantBNext = (stall == 1'b1 && dcacheWe == 1'b1 && dcacheTarget[8:5] == cid && dcacheTarget[4:0] == s_operantBAddrReg) ? dcacheDataIn :
                                  (stall == 1'b1) ? s_exeOperantBReg :
                                  (s_useImediate == 1'b1) ? s_imediateValue :
                                  (s_lookupOperantBAddr[4:0] == 5'd0) ? 32'd0 :
                                  (useForwardedOperantB == 1'b1) ? forwardedOperantB : rfOperantB;
  wire [31:0] s_storeDataNext = (stall == 1'b1 && dcacheWe == 1'b1 && dcacheTarget[8:5] == cid && dcacheTarget[4:0] == s_storeAddrReg) ? dcacheDataIn :
                                (stall == 1'b1) ? s_storeDataReg :
                                (useForwardedStoreData == 1'b1) ? forwardedStoreData : rfOperantB;
  wire [31:0] s_instructionAddressNext = (stall == 1'b0) ? pc : s_instructionAddressReg;
  wire [4:0] s_storeAddrNext = (stall == 1'b1) ? s_storeAddrReg :
                               (s_store != 3'b0) ? ir[15:11] : 5'b0;
  wire [4:0] s_operantAAddrNext = (stall == 1'b1) ? s_operantAAddrReg :
                                  (s_isJump == 1'b1) ? 5'b0 : s_operantAAddr;
  wire [4:0] s_operantBAddrNext = (stall == 1'b1) ? s_operantBAddrReg :
                                  (s_useImediate == 1'b1) ? 5'b0 : ir[15:11];
  wire [8:0] s_destinationNext = (stall == 1'b1) ? s_destinationReg : {cid, s_destination};
  wire s_weDestinationNext = (reset == 1'b1) ? 1'b0 : (stall == 1'b1) ? s_weDestinationReg : (flush == 1'b1 || s_correctJumpFlush == 1'b1) ? 1'b0 : s_weDestination;
  wire s_validInstructionNext = (reset == 1'b1) ? 1'b1 : (stall == 1'b1) ? s_validInstructionReg :
                                (flush == 1'b1 || s_correctJumpFlush == 1'b1) ? 1'b1 : s_validInstruction;
  wire s_activeInstructionNext = (reset == 1'b1) ? 1'b0 : (stall == 1'b1) ? s_activeInstructionReg :
                                 (flush == 1'b1 || s_correctJumpFlush == 1'b1) ? 1'b0 : s_activeInstruction;
  wire [1:0] s_isSprNext = (reset == 1'b1) ? 1'b0 : (stall == 1'b1) ? s_isSprReg :
                           (flush == 1'b1 || s_correctJumpFlush == 1'b1) ? 1'b0 : s_isSpr;
  wire [15:0] s_sprOrMaskNext = (stall == 1'b1) ? s_sprOrMaskReg : (ir[31:26] == 6'h30) ? {ir[25:21], ir[10:0]} : ir[15:0];
  wire s_CustomNext = (reset == 1'b1) ? 1'b0 : (stall == 1'b1) ? s_CustomReg : 
                      (flush == 1'b1 || s_correctJumpFlush == 1'b1) ? 1'b0 : s_custom;
  wire s_InstructionAbortNext = (reset == 1'b1) ? 1'b0 : (stall == 1'b1) ? s_InstructionAbortReg :
                                (flush == 1'b1 || s_correctJumpFlush == 1'b1) ? 1'b0 : abort;
  wire s_isRfeNext = (reset == 1'b1) ? 1'b0 : (stall == 1'b1) ? s_isRfeReg :
                     (flush == 1'b1 || s_correctJumpFlush == 1'b1) ? 1'b0 : s_isRfe;
  wire s_systemCallNext = (reset == 1'b1) ? 1'b0 : (stall == 1'b1) ? s_systemCallReg :
                          (flush == 1'b1 || s_correctJumpFlush == 1'b1) ? 1'b0 : s_systemCall;
  wire s_trapNext = (reset == 1'b1) ? 1'b0 : (stall == 1'b1) ? s_trapReg :
                    (flush == 1'b1 || s_correctJumpFlush == 1'b1) ? 1'b0 : s_trap;
  wire s_divideNext = (reset == 1'b1) ? 1'b0 : (stall == 1'b1) ? s_divideReg :
                      (flush == 1'b1 || s_correctJumpFlush == 1'b1) ? 1'b0 : s_divide;
  wire s_multiplyNext = (reset == 1'b1) ? 1'b0 : (stall == 1'b1) ? s_multiplyReg :
                        (flush == 1'b1 || s_correctJumpFlush == 1'b1) ? 1'b0 : s_multiply;
  wire s_updateCarryNext = (reset == 1'b1) ? 1'b0 : (stall == 1'b1) ? s_updateCarryReg :
                           (flush == 1'b1 || s_correctJumpFlush == 1'b1) ? 1'b0 : s_updateCarry;
  wire s_updateOverflowNext = (reset == 1'b1) ? 1'b0 : (stall == 1'b1) ? s_updateOverflowReg :
                              (flush == 1'b1 || s_correctJumpFlush == 1'b1) ? 1'b0 : s_updateOverflow;
  wire s_updateFlagNext = (reset == 1'b1) ? 1'b0 : (stall == 1'b1) ? s_updateFlagReg :
                          (flush == 1'b1 || s_correctJumpFlush == 1'b1) ? 1'b0 : s_updateFlag;
  wire [1:0] s_syncCommandNext = (reset == 1'b1) ? 2'd0 : (stall == 1'b1) ? s_syncCommandReg :
                                 (flush == 1'b1 || s_correctJumpFlush == 1'b1) ? 2'd0 : s_syncCommand;
  wire [2:0] s_exeControlNext = (reset == 1'b1) ? 3'd0 : (stall == 1'b1) ? s_exeControlReg : s_exeControl;
  wire [2:0] s_resultSelectionNext = (reset == 1'b1) ? 3'd0 : (stall == 1'b1) ? s_resultSelectionReg : s_resultSelection;
  wire [2:0] s_storeNext = (reset == 1'b1) ? 3'd0 : (stall == 1'b1) ? s_storeReg :
                           (flush == 1'b1 || s_correctJumpFlush == 1'b1) ? 3'd0 : s_store;
  wire [2:0] s_loadNext = (reset == 1'b1) ? 3'd0 : (stall == 1'b1) ? s_loadReg :
                          (flush == 1'b1 || s_correctJumpFlush == 1'b1) ? 3'd0 : s_load;
  wire [3:0] s_compareCntrlNext = (stall == 1'b1) ? s_compareCntrlReg : s_compareCntrl;
  wire s_isDelaySlotIsnNext = (reset == 1'b1) ? 1'b0 : (stall == 1'b1) ? s_isDelaySlotIsnReg :
                              (s_isDelaySlotReg == 1'b1 && insertedNop == 1'b0) ? 1'b1 : 1'b0;
  wire [31:0] s_irNext = (stall == 1'b1) ? s_irReg : ir;

  assign exeOperantA          = s_exeOperantAReg;
  assign exeOperantB          = s_exeOperantBReg;
  assign exestoreData         = s_storeDataReg;
  assign instructionAddress   = s_instructionAddressReg;
  assign exeStoreAddr         = s_storeAddrReg;
  assign exeOperantAAddr      = s_operantAAddrReg;
  assign exeOperantBAddr      = s_operantBAddrReg;
  assign exeDestination       = s_destinationReg;
  assign exeWeDestination     = s_weDestinationReg;
  assign exeValidInstruction  = s_validInstructionReg;
  assign exeActiveInstruction = s_activeInstructionReg;
  assign exeIsSpr             = s_isSprReg;
  assign exeSprOrMask         = s_sprOrMaskReg;
  assign exeImediateValue     = s_sprOrMaskReg;
  assign exeCustom            = s_CustomReg;
  assign exeInstructionAbort  = s_InstructionAbortReg;
  assign exeIsRfe             = s_isRfeReg;
  assign exeSystemCall        = s_systemCallReg;
  assign exeTrap              = s_trapReg;
  assign exeDivide            = s_divideReg;
  assign exeMultiply          = s_multiplyReg;
  assign exeUpdateCarry       = s_updateCarryReg;
  assign exeUpdateOverflow    = s_updateOverflowReg;
  assign exeUpdateFlag        = s_updateFlagReg;
  assign exeSyncCommand       = s_syncCommandReg;
  assign exeExeControl        = s_exeControlReg;
  assign exeResultSelection   = s_resultSelectionReg;
  assign exeStore             = s_storeReg;
  assign exeLoad              = s_loadReg;
  assign exeCompareCntrl      = s_compareCntrlReg;
  assign ebuIsDelaySlotIsn    = s_isDelaySlotIsnReg;
  assign exeIr                = s_irReg;
  
  always @(posedge clock)
    begin
      s_exeOperantAReg        <= s_exeOperantANext;
      s_exeOperantBReg        <= s_exeOperantBNext;
      s_instructionAddressReg <= s_instructionAddressNext;
      s_storeDataReg          <= s_storeDataNext;
      s_storeAddrReg          <= s_storeAddrNext;
      s_operantAAddrReg       <= s_operantAAddrNext;
      s_operantBAddrReg       <= s_operantBAddrNext;
      s_destinationReg        <= s_destinationNext;
      s_weDestinationReg      <= s_weDestinationNext;
      s_validInstructionReg   <= s_validInstructionNext;
      s_activeInstructionReg  <= s_activeInstructionNext;
      s_isSprReg              <= s_isSprNext;
      s_sprOrMaskReg          <= s_sprOrMaskNext;
      s_CustomReg             <= s_CustomNext;
      s_InstructionAbortReg   <= s_InstructionAbortNext;
      s_isRfeReg              <= s_isRfeNext;
      s_systemCallReg         <= s_systemCallNext;
      s_trapReg               <= s_trapNext;
      s_divideReg             <= s_divideNext;
      s_multiplyReg           <= s_multiplyNext;
      s_updateCarryReg        <= s_updateCarryNext;
      s_updateOverflowReg     <= s_updateOverflowNext;
      s_updateFlagReg         <= s_updateFlagNext;
      s_syncCommandReg        <= s_syncCommandNext;
      s_exeControlReg         <= s_exeControlNext;
      s_resultSelectionReg    <= s_resultSelectionNext;
      s_storeReg              <= s_storeNext;
      s_loadReg               <= s_loadNext;
      s_compareCntrlReg       <= s_compareCntrlNext;
      s_isDelaySlotIsnReg     <= s_isDelaySlotIsnNext;
      s_irReg                 <= s_irNext;
    end
endmodule
