module divider ( input wire         clock,
                                    reset,
                                    doDivide,
                                    signedDivide,
                 input wire [31:0]  operantA,
                                    operantB,
                 output reg         ready,
                 output wire        carryOut,
                 output wire [31:0] quotient );
/*
 *
 * this is a multi-cycle implementation of a divider useing the ssr principle and using 38 cycles
 *
 */
  reg [2:0] s_currentState, s_nextState;
  localparam [2:0] IDLE = 3'b000;
  localparam [2:0] PREPARE = 3'b001;
  localparam [2:0] DIVIDE = 3'b010;
  localparam [2:0] DETERMINE = 3'b011;
  localparam [2:0] CORRECT = 3'b100;

  reg s_carryOutReg;
  assign carryOut = s_carryOutReg;
  
  always @(posedge clock)
    if (reset == 1'b1) s_carryOutReg <= 1'b0;
    else if (doDivide == 1'b1 && s_currentState == IDLE)
      begin
        if (operantB == 0) s_carryOutReg <= 1'b1;
        else s_carryOutReg <= 1'b0;
      end
  
  always @(posedge clock)
    if (s_currentState == CORRECT) ready <= 1'b1;
    else ready <= 1'b0;
  /*
   *
   * Here we define the state machine controlling the divider
   *
   */
  reg [4:0] s_divideStepCounter;
  wire s_doInit = s_currentState == PREPARE ? 1'b1 : 1'b0;
  wire s_start = s_currentState == IDLE ? doDivide : 1'b0;
  wire s_doDivide =  s_currentState == DIVIDE ? 1'b1 : 1'b0;
  
  always @(posedge clock)
    if (s_currentState == DIVIDE) s_divideStepCounter <= s_divideStepCounter - 5'd1;
    else s_divideStepCounter <= {5{1'b1}};
  
  always @*
    case (s_currentState)
      IDLE      : if (doDivide == 1'b1) s_nextState <= PREPARE;
                  else s_nextState <= IDLE;
      PREPARE   : if (s_carryOutReg == 1'b1) s_nextState <= CORRECT;
                  else s_nextState <= DIVIDE;
      DIVIDE    : if (s_divideStepCounter == 0) s_nextState <= DETERMINE;
                  else s_nextState <= DIVIDE;
      DETERMINE : s_nextState <= CORRECT;
      default   : s_nextState <= IDLE;
    endcase
  
  always @(posedge clock)
    if (reset == 1'b1) s_currentState <= IDLE;
    else s_currentState <= s_nextState;

  /*
   *
   * here we define the input registers that are used during operation
   *
   */
  reg [31:0] s_opperantAReg, s_minusBReg;
  reg [32:0] s_operantBReg;
  reg s_signedDivideReg, s_signAReg;
  
  always @(posedge clock)
    if (s_start == 1'b1) 
      begin
        s_opperantAReg      <= operantA;
        s_operantBReg[31:0] <= operantB;
        s_operantBReg[32]   <= operantB[31] & signedDivide;
        s_signAReg          <= operantA[31] & signedDivide;
        s_signedDivideReg   <= signedDivide;
      end
    else if (s_doInit == 1'b1) s_minusBReg <= ~s_operantBReg[31:0] + 1;
    else if (s_currentState == DIVIDE) s_opperantAReg <= {s_opperantAReg[30:0],1'b0};

  /*
   *
   * Here we do the division
   *
   */
  reg [32:0] s_divideReg;
  wire [32:0] s_add1 = {s_divideReg[31:0],s_opperantAReg[31]};
  wire s_subtract = ~(s_divideReg[32] ^ s_operantBReg[32]);
  wire [32:0] s_RealOperantB = (s_subtract == 1'b1) ? (~s_operantBReg) + 1 : s_operantBReg;
  wire [32:0] s_newRemainder = s_add1 + s_RealOperantB;
  
  always @(posedge clock)
    if (s_doInit == 1'b1) s_divideReg <= {33{s_opperantAReg[31]&s_signedDivideReg}};
    else if (s_currentState == DIVIDE) s_divideReg <= s_newRemainder;

  reg [31:0] s_quotientReg;
  reg s_decrementQuotientReg, s_clearReg, s_enableReg, s_remainderEqualsMinusBReg;
  wire [31:0] s_quotientAdd1 = {s_quotientReg[30:0],1'b0};
  wire [31:0] s_quotientAdd2 = {{31{s_decrementQuotientReg}},1'b1};
  wire [31:0] s_nextQuotient = s_quotientAdd1 + s_quotientAdd2;
  wire s_decrementQuotient = s_doDivide == 1'b1 ? ~s_subtract : (s_divideReg[32] ^ s_signAReg) | s_remainderEqualsMinusBReg;
  
  always @(posedge clock)
    begin
      s_clearReg             <= s_doInit;
      s_enableReg            <= s_doDivide;
      s_decrementQuotientReg <= s_decrementQuotient;
    end
  
  always @(posedge clock)
    if (s_clearReg == 1'b1) s_quotientReg <= 0;
    else if (s_enableReg == 1'b1) s_quotientReg <= s_nextQuotient;
  
  /*
   *
   * Here the final correction is performed
   *
   */
  wire s_remainderIsZero = (s_divideReg == 0) ? 1'b1 : 1'b0;
  wire s_remainderEqualsB = (s_divideReg[31:0] == s_operantBReg[31:0]) ? 1'b1 : 1'b0;
  wire s_remainderEqualsMinusB = (s_divideReg[31:0] == s_minusBReg) ? 1'b1 : 1'b0;
  reg s_remainderIsZeroReg, s_remainderEqualsBReg, s_correctQuotientReg;
  wire s_correctQuotient = ~s_remainderIsZeroReg & ((s_divideReg[32] ^ s_signAReg) | (s_remainderEqualsBReg | s_remainderEqualsMinusBReg));
  
  always @(posedge clock)
    if (s_currentState == DETERMINE)
      begin
        s_remainderIsZeroReg       <= s_remainderIsZero;
        s_remainderEqualsBReg      <= s_remainderEqualsB;
        s_remainderEqualsMinusBReg <= s_remainderEqualsMinusB;
      end
    else if (s_currentState == CORRECT) s_correctQuotientReg <= s_correctQuotient;
  
  assign quotient = (s_decrementQuotientReg == 1'b0) ? s_quotientReg + {{31{1'b0}},s_correctQuotientReg} : s_quotientReg - {{31{1'b0}},s_correctQuotientReg};
endmodule
