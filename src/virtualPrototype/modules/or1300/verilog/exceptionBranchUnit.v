module exceptionBranchUnit ( input wire         clock,
                                                reset,
                                                irq,
                                                tickTimerIrq,
                                                stall,
                             output wire        flushPipe,
                             input wire [31:0]  irIn,
                             output wire [31:0] exceptionIr,
                             
                             // here the intrface to the execution unit is defined
                             input wire         isJump,
                                                isRfe,
                                                systemCall,
                                                trap,
                                                allignmentError,
                                                instructionAbort,
                                                invalidInstruction,
                                                activeInstruction,
                                                divZeroException,
                                                overflow,
                                                weOverflow,
                                                writeSpr,
                             input wire [31:0]  pc,
                                                nextPc,
                             input wire [1:0]   syncCommand,
                             
                             // here the interface to the register file is defined
                             input wire [31:0]  supervisionRegister,
                                                exceptionPcRegister,
                             input wire         custom,
                                                rfActiveInstruction,
                                                rfIsDelaySlotIsn,
                             output wire [31:0] epcrNext,
                                                eearNext,
                             output wire        exceptionTaken,
                                                exceptionFinished,
                             input wire [27:0]  BusErrorVector,
                                                TickTimerVector,
                                                AllignmentVector,
                                                RangeVector,
                                                IllegalInstructionVector,
                                                SystemCallVector,
                                                TrapVector,
                                                BreakPointVector,
                                                InterruptVector,
                             // here the interface to the debug unit is defined
                             input wire         debugIrq,
                                                debugJumpPending,
                             input wire [29:0]  debugJumpAddress,
                             output wire[13:0]  exceptionReason,
                             
                             // here the interface to the d-cache is defined
                             input wire         dataAbort,
                             input wire [31:0]  abortAddress,
                                                abortMemoryAddress,
                             
                             // here the interface to the i-cache is defined
                             output wire        loadPc,
                                                memorySync,
                             output wire [29:0] pcLoadValue);
  reg s_dataAbortReg;
  reg [31:0] s_jumpInstrAddressReg, s_abortMemoryAddressReg, s_abortAddressReg, s_exceptionIrReg;
  wire s_dataAbort = s_dataAbortReg | dataAbort;
  wire s_maskedIrq = (supervisionRegister[2] == 1'b0 || writeSpr == 1'b1 || custom == 1'b1 || rfActiveInstruction == 1'b0) ? 1'b0 : irq;
  wire s_tickTimerIrq = (supervisionRegister[1] == 1'b0 || writeSpr == 1'b1 || custom == 1'b1 || rfActiveInstruction == 1'b0) ? 1'b0 : tickTimerIrq;
  wire s_overflowIrq = overflow & weOverflow & supervisionRegister[12];
  wire s_exceptionActive = (instructionAbort | invalidInstruction | systemCall | trap |
                            divZeroException | allignmentError | s_dataAbort | s_maskedIrq |
                            s_overflowIrq | s_tickTimerIrq | debugIrq);
  wire s_doSync = (syncCommand == 2'b01 || syncCommand == 2'b10) ? 1'b1 : 1'b0;
  wire [31:0] s_jumpInstrAddressNext = (stall == 1'b0 && isJump == 1'b1) ? pc : s_jumpInstrAddressReg;
  wire s_dataAbortNext = (reset == 1'b1 || stall == 1'b0) ? 1'b0 : s_dataAbortReg | dataAbort;
  wire [31:0] s_abortMemoryAddressNext = (stall == 1'b1 && dataAbort == 1'b1) ? abortMemoryAddress : s_abortMemoryAddressReg;
  wire [31:0] s_abortAddressNext = (stall == 1'b1 && dataAbort == 1'b1) ? abortAddress : s_abortAddressReg;
  wire [31:0] s_abortAddress = (s_dataAbortReg == 1'b1) ? s_abortAddressReg : abortAddress;
  wire [31:0] s_abortMemoryAddress = (s_dataAbortReg == 1'b1) ? s_abortMemoryAddressReg : abortMemoryAddress;
  
  wire [31:0] s_exceptionVector = (supervisionRegister[31:28] == 4'hE && supervisionRegister[8] == 1'b1) ? {{4{supervisionRegister[14]}} , RangeVector} :
                                  (instructionAbort == 1'b1)                                             ? {{4{supervisionRegister[14]}} , BusErrorVector} :
                                  (invalidInstruction == 1'b1)                                           ? {{4{supervisionRegister[14]}} , IllegalInstructionVector} :
                                  (allignmentError == 1'b1)                                              ? {{4{supervisionRegister[14]}} , AllignmentVector} :
                                  (systemCall == 1'b1)                                                   ? {{4{supervisionRegister[14]}} , SystemCallVector} :
                                  (trap == 1'b1)                                                         ? {{4{supervisionRegister[14]}} , TrapVector} :
                                  (debugIrq == 1'b1)                                                     ? {{4{supervisionRegister[14]}} , BreakPointVector} :
                                  (s_dataAbort == 1'b1)                                                  ? {{4{supervisionRegister[14]}} , BusErrorVector} :
                                  (divZeroException == 1'b1 || s_overflowIrq == 1'b1)                    ? {{4{supervisionRegister[14]}} , RangeVector} :
                                  (s_maskedIrq == 1'b1)                                                  ? {{4{supervisionRegister[14]}} , InterruptVector} :
                                  (s_tickTimerIrq == 1'b1)                                               ? {{4{supervisionRegister[14]}} , TickTimerVector} :
                                                                                                           32'hF0000070;

  assign exceptionReason[13] = (s_exceptionVector == {{4{supervisionRegister[14]}} , TrapVector}) ? 1'b1 : 1'b0;
  assign exceptionReason[12] = (s_exceptionVector == {{4{supervisionRegister[14]}} , BreakPointVector}) ? 1'b1 : 1'b0;
  assign exceptionReason[11] = (s_exceptionVector == {{4{supervisionRegister[14]}} , SystemCallVector}) ? 1'b1 : 1'b0;
  assign exceptionReason[10] = (s_exceptionVector == {{4{supervisionRegister[14]}} , RangeVector}) ? 1'b1 : 1'b0;
  assign exceptionReason[9]  = 1'b0;
  assign exceptionReason[8]  = 1'b0;
  assign exceptionReason[7]  = (s_exceptionVector == {{4{supervisionRegister[14]}} , InterruptVector}) ? 1'b1 : 1'b0;
  assign exceptionReason[6]  = (s_exceptionVector == {{4{supervisionRegister[14]}} , IllegalInstructionVector}) ? 1'b1 : 1'b0;
  assign exceptionReason[5]  = (s_exceptionVector == {{4{supervisionRegister[14]}} , AllignmentVector}) ? 1'b1 : 1'b0;
  assign exceptionReason[4]  = (s_exceptionVector == {{4{supervisionRegister[14]}} , TickTimerVector}) ? 1'b1 : 1'b0;
  assign exceptionReason[3]  = 1'b0;
  assign exceptionReason[2]  = 1'b0;
  assign exceptionReason[1]  = (s_exceptionVector == {{4{supervisionRegister[14]}} , BusErrorVector}) ? 1'b1 : 1'b0;
  assign exceptionReason[0]  = (s_exceptionVector == 32'hF0000070) ? 1'b1 : 1'b0;
  

  assign loadPc            = s_exceptionActive | isRfe | s_doSync | debugJumpPending;
  assign pcLoadValue       = (debugJumpPending == 1'b1) ? debugJumpAddress :
                             (s_exceptionActive == 1'b1) ? s_exceptionVector[31:2] :
                             (isRfe == 1'b1) ? exceptionPcRegister[31:2] : nextPc[31:2];
  assign flushPipe         = s_exceptionActive | isRfe | s_doSync | debugJumpPending;
  assign epcrNext          = (s_dataAbort == 1'b1) ? s_abortAddress : 
                             (rfIsDelaySlotIsn == 1'b1) ? s_jumpInstrAddressReg : nextPc;
  assign eearNext          = (s_dataAbort == 1'b1) ? s_abortMemoryAddress : pc;
  assign memorySync        = (syncCommand == 2'b01 || syncCommand == 2'b11) ? 1'b1 : 1'b0;
  assign exceptionTaken    = s_exceptionActive;
  assign exceptionFinished = ~s_exceptionActive & isRfe;
  assign exceptionIr       = s_exceptionIrReg;
  
  always @ (posedge clock)
    begin
      s_jumpInstrAddressReg   <= s_jumpInstrAddressNext;
      s_dataAbortReg          <= s_dataAbortNext;
      s_abortMemoryAddressReg <= s_abortMemoryAddressNext;
      s_abortAddressReg       <= s_abortAddressNext;
      s_exceptionIrReg        <= (stall == 1'b0 && s_exceptionActive == 1'b1) ? irIn : s_exceptionIrReg;
    end
endmodule
