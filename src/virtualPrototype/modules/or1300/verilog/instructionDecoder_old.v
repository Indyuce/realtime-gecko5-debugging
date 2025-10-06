module instructionDecoder ( // Here the i$ interface is defined
                            input wire [31:0]  ir,
                                               pc,
                            input wire         resetFilterIn,
                                               abort,
                            
                            // Here the control signals are defined
                            output wire [4:0]  operantAAddr,
                                               operantBAddr,
                                               destination,
                            output wire        weDestination,
                                               useImediate,
                            output wire [25:0] imediateValue,
                            output wire [2:0]  imediateFormat,
                            output wire [31:0] instructionAddress,
                            output wire        validInstruction,
                                               activeInstruction,
                                               instructionAbort,
                                               resetFilter,
                            output wire [3:0]  compareCntrl,
                            output wire [2:0]  exeControl,
                                               store,
                                               load,
                                               resultSelection,
                            output wire [1:0]  isSpr,
                                               jumpCondition,
                                               syncCommand,
                            output wire        isJump,
                                               usePc,
                                               isRfe,
                                               systemCall,
                                               trap,
                                               divide,
                                               multiply,
                                               custom,
                                               updateCarry,
                                               updateOverflow,
                                               updateFlag );

   localparam [31:0] CONTEXT_SYNC_COMMAND = 32'h23000000;
   localparam [31:0] MEMORY_SYNC_COMMAND  = 32'h22000000;
   localparam [31:0] PIPE_SYNC_COMMAND    = 32'h22800000;
   localparam [15:0] SYSTEM_CALL_COMMAND  = 16'h2000;
   localparam [15:0] TRAP_COMMAND         = 16'h2100;
   
   wire s_validInstruction  = ((ir[31:26] == 6'b111000 && ir[9:8] == 2'b00 && (ir[3:0] == 4'h0 || ir[3:0] == 4'h1 || ir[3:0] == 4'h2 || ir[3:0] == 4'h3 || ir[3:0] == 4'h4 ||
                                ir[3:0] == 4'h5 || ir[3:0] == 4'h8 || ir[3:0] == 4'hC || ir[3:0] == 4'hD || ir[3:0] == 4'hE)) ||
                               (ir[31:26] == 6'b111000 && ir[9] == 1'b0 && ir[3:0] == 4'hF) || ir[31:26] == 6'b100111 || ir[31:28] == 4'b1010 || ir[31:24] == 8'h15 ||
                               ir[31:26] == 6'b000000 || ir[31:26] == 6'b101110 || ir[31:26] == 6'b001001 || ir[31:25] == 7'b1110010 || ir[31:25] == 7'b1011110 ||
                               (ir[31:26] == 6'b000110 && ir[16] == 1'b0) || ir[31:26] == 6'b010001 || ir[31:26] == 6'b000001 || ir[31:26] == 6'b010010 || ir[31:26] == 6'b000011 ||
                               ir[31:26] == 6'b000100 || (ir[31:26] == 6'b111000 && ir[9:8] == 2'b11 && (ir[3:0] == 4'h9 || ir[3:0] == 4'hA)) || ir[31:26] == 6'b010011 ||
                               (ir[31:26] == 6'b110001 && (ir[3:0] == 4'h1 || ir[4:0] == 4'h2)) || (ir[31:26] == 6'b000110 && ir[16] == 1'b1 && ir[15:0] == 16'd0) ||
                               (ir[31:26] == 6'b111000 && ir[9:0] == 2'b11 && (ir[3:0] == 4'h6 || ir[3:0] == 4'hB)) || ir[31:26] == 6'b101100 || ir[31:26] == 6'b011100 ||
                               ir[31:26] == 6'b110101 || ir[31:26] == 6'b110110 || ir[31:26] == 6'b110111 || ir[31:26] == 6'b100001 || ir[31:26] == 6'b100010 || 
                               ir[31:26] == 6'b100011 || ir[31:26] == 6'b100100 || ir[31:26] == 6'b100101 || ir[31:26] == 6'b100110 || ir[31:26] == 6'b101101 ||
                               ir[31:26] == 6'b110000 || (ir[31:26] == 6'b011101 && ir[10] == 1'b0) || ir == CONTEXT_SYNC_COMMAND || ir == MEMORY_SYNC_COMMAND ||
                               ir == PIPE_SYNC_COMMAND || ir[31:16] == SYSTEM_CALL_COMMAND || ir[31:16] == TRAP_COMMAND) ? 1'b1 : 1'b0;

   assign operantAAddr      = ir[20:16];
   assign operantBAddr      = (ir[31:26] == 6'b101101) ? 5'd0 : ir[15:11];
   assign imediateValue     = ir[25:0];
   assign destination       = (ir[31:26] == 6'b000001 || ir[31:26] == 6'b010010) ? 5'b01001 : ir[25:21];
   assign compareCntrl      = ir[24:21];
   assign isSpr[1]          = (ir[31:26] == 6'b101101 || ir[31:26] == 6'b110000) ? 1'b1 : 1'b0;
   assign isSpr[0]          = (ir[31:26] == 6'b101101) ? 1'b1 : 1'b0;
   assign isRfe             = (ir[31:26] == 6'b001001) ? 1'b1 : 1'b0;
   assign updateFlag        = (ir[31:25] == 7'b1110010 || ir[31:25] == 7'b1011110) ? 1'b1 : 1'b0;
   assign load[2]           = ((ir[31:26] == 6'b100010 || ir[31:26] == 6'b100110 || ir[31:26] == 6'b100100) &&
                               ir[25:21] != 5'd0) ? 1'b1 : 1'b0;
   assign load[1]           = ((ir[31:26] == 6'b100110 || ir[31:26] == 6'b100101 || ir[31:26] == 6'b100010 || ir[31:26] == 6'b100001) &&
                               ir[25:21] != 5'd0) ? 1'b1 : 1'b0;
   assign load[0]           = ((ir[31:26] == 6'b100100 || ir[31:26] == 6'b100011 || ir[31:26] == 6'b100010 || ir[31:26] == 6'b100001) &&
                               ir[25:21] != 5'd0) ? 1'b1 : 1'b0;
   assign store[2]          = (ir[31:26] == 6'b011101 && ir[10] == 1'b0) ? 1'b1 : 1'b0;
   assign store[1]          = (ir[31:26] == 6'b110111 || ir[31:26] == 6'b110101 || (ir[31:26] == 6'b011101 && ir[10:9] == 2'b01)) ? 1'b1 : 1'b0;
   assign store[0]          = (ir[31:26] == 6'b110101 || ir[31:26] == 6'b110110 || (ir[31:26] == 6'b011101 && ir[10] == 1'b0 && ir[8] == 1'b1)) ? 1'b1 : 1'b0;
   assign custom            = (ir[31:26] == 6'b011100) ? 1'b1 : 1'b0;
   assign multiply          = ( (ir[31:26] == 6'b110001 && (ir[3:0] == 4'd1 || ir[3:0] == 4'd2)) ||
                                ir[31:26] == 6'b010011 ||
                                (ir[31:26] == 6'b000110 && ir[16] == 1'b1 && ir[15:0] == 16'd0) ||
                                (ir[31:26] == 6'b111000 && ir[9:8] == 2'b11 && (ir[3:0] == 4'h6 || ir[3:0] == 4'hB)) ||
                                ir[31:26] == 6'b101100) ? 1'b1 : 1'b0;
  assign divide             = (ir[31:26] == 6'b111000 && ir[9:8] == 2'b11 && (ir[3:0] == 4'h9 || ir[3:0] == 4'hA)) ? 1'b1 : 1'b0;
  assign syncCommand        = (ir == CONTEXT_SYNC_COMMAND || ir == MEMORY_SYNC_COMMAND || ir == PIPE_SYNC_COMMAND) ? ~ir[24:23] : 2'd0;
  assign trap               = (ir[31:16] == TRAP_COMMAND) ? 1'b1 : 1'b0;
  assign systemCall         = (ir[31:16] == SYSTEM_CALL_COMMAND) ? 1'b1 : 1'b0;
  assign usePc              = (ir[31:27] == 5'b00000 || ir[31:26] == 6'b000011 || ir[31:26] == 6'b000100) ? 1'b1 : 1'b0;
  assign jumpCondition[1]   = (ir[31:26] == 6'b000011 || ir[31:26] == 6'b000100) ? 1'b1 : 1'b0;
  assign jumpCondition[0]   = (ir[31:26] == 6'b000100 || ir[31:26] == 5'b00000) ? 1'b1 : 1'b0;
  assign isJump             = (ir[31:27] == 5'b00000 || ir[31:26] == 6'b010001 || ir[31:26] == 6'b010010 ||
                               ir[31:26] == 6'b000011 || ir[31:26] == 6'b000100) ? 1'b1 : 1'b0;
  assign imediateFormat[2]  = (ir[31:26] == 6'b101001 || ir[31:26] == 6'b101010) ? 1'b1 : 1'b0;
  assign imediateFormat[1]  = ( (ir[31:26] == 6'b000110 && ir[16] == 1'b0) || ir[31:26] == 6'b110101 || ir[31:26] == 6'b110110 ||
                               ir[31:26] == 6'b110111 || ir[31:26] == 6'b110000 || ir[31:26] == 6'b010011) ? 1'b1 : 1'b0;
  assign imediateFormat[0]  = (ir[31:27] == 5'b00000 || ir[31:26] == 6'b110101 || ir[31:26] == 6'b110110 || ir[31:26] == 6'b110111 ||
                               ir[31:26] == 6'b010011 || ir[31:26] == 6'b000011 || ir[31:26] == 6'b110000 || ir[31:26] == 6'b000100) ? 1'b1 : 1'b0;
  assign useImediate        = (ir[31:26] == 6'b100111 || ir[31:28] == 4'b1010 || ir[31:26] == 6'b101110 || ir[31:27] == 5'b00000 ||
                               (ir[31:26] == 6'b000110 && ir[16] == 1'b0) || ir[31:26] == 6'b010011 || ir[31:26] == 6'b101100 || 
                               ir[31:26] == 6'b110101 || ir[31:26] == 6'b110110 || ir[31:26] == 6'b110111 || ir[31:26] == 6'b000011 ||
                               ir[31:26] == 6'b000100 || ir[31:26] == 6'b100001 || ir[31:26] == 6'b100010 || ir[31:26] == 6'b100011 ||
                               ir[31:26] == 6'b100100 || ir[31:26] == 6'b100101 || ir[31:26] == 6'b100110 ||
                               ir[31:16] == TRAP_COMMAND) ? 1'b1 : 1'b0;
  assign resultSelection[2] = (ir[31:26] == 6'b000001 || ir[31:26] == 6'b101101 || ir[31:26] == 6'b110000 ||
                               (ir[31:26] == 6'b111000 && ir[9:8] == 2'b11 && (ir[3:0] == 4'h9 || ir[3:0] == 4'hA)) ||
                               (ir[31:26] == 6'b000110 && ir[16] == 1'b1 && ir[15:0] == 16'd0) ||
                               (ir[31:26] == 6'b111000 && ir[9:8] == 2'b11 && (ir[3:0] == 4'h6 || ir[3:0] == 4'hB)) ||
                               ir[31:26] == 6'b101100 || ir[31:26] == 6'b011100 || ir[31:26] == 6'b010010) ? 1'b1 : 1'b0;
  assign resultSelection[1] = ((ir[31:26] == 6'b111000 && ir[9:8] == 2'b00 && (ir[3:0] == 4'h8 || ir[3:0] == 4'hE)) ||
                               (ir[31:26] == 6'b000110 && ir[16] == 1'b1 && ir[15:0] == 16'd0) ||
                               (ir[31:26] == 6'b111000 && ir[9:8] == 2'b11 && (ir[3:0] == 4'h6 || ir[3:0] == 4'hB)) ||
                               ir[31:26] == 6'b101100 || ir[31:26] == 6'b011100 ||
                               (ir[31:26] == 6'b111000 && ir[9] == 1'b0 && ir[3:0] == 4'hF) ||
                               ir[31:26] == 6'b101110) ? 1'b1 : 1'b0;
  assign resultSelection[0] = ((ir[31:26] == 6'b111000 && ir[9:8] == 2'b00 && (ir[3:0] == 4'h3 || ir[3:0] == 4'h4 ||
                                ir[3:0] == 4'h5 || ir[3:0] == 4'hC || ir[3:0] == 4'hD || ir[3:0] == 4'hE)) ||
                               (ir[31:26] == 6'b111000 && ir[9:8] == 1'b00 && (ir[3:0] == 4'h9 || ir[3:0] == 4'hA)) ||
                               (ir[31:26] == 6'b111000 && ir[9] == 1'b0 && ir[3:0] == 4'hF) ||
                               ir[31:26] == 6'b011100 || (ir[31:28] == 4'b1010 && ir[27:26] != 2'b00)) ? 1'b1 : 1'b0;
  assign exeControl[2]      = ((ir[31:26] == 6'b000110 && ir[16] == 1'b1 && ir[15:0] == 16'd0) ||
                               (ir[31:26] == 6'b111000 && ir[3:0] == 4'hC)) ? 1'b1 : 1'b0;
  assign exeControl[1]      = ((ir[31:26] == 6'b111000 && ((( ir[2] == 1'b1 || ir[2:0] == 3'b010) && ir[3] == 1'b0 && ir[9:8] == 2'b00) ||
                                ((ir[3:0] == 4'hC || ir[3:0] == 4'h8) && ir[7] == 1'b1) || (ir[3:0] == 4'hF && ir[8] == 1'b1))) ||
                               ir[31:27] == 5'b10101 || (ir[31:26] == 6'b101110 && ir[7] == 1'b1) || ir[31:25] == 7'b1110010 || ir[31:25] == 7'b1011110 ||
                               (ir[31:26] == 6'b110001 && (ir[3:0] == 4'h1 || ir[3:0] == 4'h2))) ? 1'b1 : 1'b0;
  assign exeControl[0]      = ((ir[31:26] == 6'b111000 && ((ir[0] == 1'b1 && ir[3] == 1'b0) || ((ir[3:0] == 4'hC || ir[3:0] == 4'h8) && ir[6] == 1'b1) || ir[3:0] == 4'hF)) ||
                               (ir[31:26] == 6'b111000 && ir[9:8] == 2'b11 && ir[3:0] == 4'h9) ||
                               (ir[31:26] == 6'b110001 && ir[3:0] == 4'h2) || (ir[31:26] == 6'b111000 && ir[9:8] == 2'b11 && ir[3:0] == 4'h6) ||
                               (ir[31:28] == 4'b1010 && ir[27:26] != 2'b10) || (ir[31:26] == 6'b101110 && ir[6] == 1'b1) ||
                               ir[31:26] == 6'b010011 || ir[31:26] == 6'b101100) ? 1'b1 : 1'b0;
  assign updateOverflow     = ((ir[31:26] == 6'b111000 && ir[9:8] == 2'b00 && ir[3:2] == 2'b00) ||
                               (ir[31:26] == 6'b111000 && ir[9:8] == 2'b11 && (ir[3:0] == 4'h6 || ir[3:0] == 4'hB)) ||
                               ir[31:26] == 6'b100111 || ir[31:26] == 6'b101100 || ir[31:26] == 6'b101000) ? 1'b1 : 1'b0;
  assign updateCarry        = ((ir[31:26] == 6'b111000 && ir[9:8] == 2'b00 && ir[3:2] == 2'b00) ||
                               (ir[31:26] == 6'b111000 && ir[9:8] == 2'b11 && (ir[3:0] == 4'h9 || ir[3:0] == 4'ha)) ||
                               ir[31:26] == 6'b100111 || ir[31:26] == 6'b101000) ? 1'b1 : 1'b0;
  assign weDestination      = ((ir[31:26] == 6'b111000 && ir[9:8] == 2'b00 && (ir[3:0] == 4'h0 || ir[3:0] == 4'h1 || ir[3:0] == 4'h2 || ir[3:0] == 4'h3 || ir[3:0] == 4'h4 ||
                                ir[3:0] == 4'h5 || ir[3:0] == 4'h8 || ir[3:0] == 4'hC || ir[3:0] == 4'hD || ir[3:0] == 4'hE)) ||
                               (ir[31:26] == 6'b111000 && ir[9] == 1'b0 && ir[3:0] == 4'hF) || (ir[31:26] == 6'b000110 && ir[16] == 1'b0) ||
                               ir[31:26] == 6'b100111 || ir[31:26] == 6'b101110 || ir[31:28] == 4'b1010 || ir[31:26] == 6'b000001 ||
                               (ir[31:26] == 6'b000110 && ir[16] == 1'b1 && ir[15:0] == 16'd0) || ir[31:26] == 6'b101100 ||
                               (ir[31:26] == 6'b111000 && ir[9:8] == 2'b11 && (ir[3:0] == 4'h6 || ir[3:0] == 4'hB)) ||
                               (ir[31:26] == 6'b111000 && ir[9:8] == 2'b11 && (ir[3:0] == 4'h9 || ir[3:0] == 4'hA)) ||
                               (ir[31:26] == 6'b011100 && ir[8] == 1'b0) || ir[31:26] == 6'b010010 || ir[31:26] == 6'b101101) ? 1'b1 : 1'b0;
  assign validInstruction   = s_validInstruction;
  assign activeInstruction  = (ir[31:24] != 8'h15) ? s_validInstruction : 1'b0;
  assign instructionAddress = pc;
  assign instructionAbort   = abort;
  assign resetFilter        = resetFilterIn;
endmodule
