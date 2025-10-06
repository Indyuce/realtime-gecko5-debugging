module adder ( input wire         clock,
                                  reset,
                                  stall,
                                  carryIn,
               input wire [1:0]   control,
               input wire [3:0]   compareControl,
               input wire [31:0]  operantA,
                                  operantB,
               output wire [31:0] result,
               output wire        carryOut,
                                  overflow,
                                  flag );

reg s_overflowReg, s_carryOutReg, s_flag, s_flagReg;
wire [32:0] s_extendedOperantA = {1'b0,operantA};
wire [32:0] s_extendedOperantB = control[1] == 1'b0 ? {1'b0,operantB} : {1'b0,~operantB};
wire s_carryIn = control[1] | (carryIn & control[0]);
wire [32:0] s_extendedCarryIn;

assign s_extendedCarryIn[32:1] = {32{1'b0}};
assign s_extendedCarryIn[0] = s_carryIn;

wire [32:0] s_extendedSum = s_extendedOperantA + s_extendedOperantB + s_extendedCarryIn;

assign result = s_extendedSum[31:0];
assign overflow = s_overflowReg;
assign carryOut = s_carryOutReg;
assign flag = s_flagReg;

wire s_equal = operantA == operantB ? 1'b1 : 1'b0;
wire s_unsignedSmaller = operantA < operantB ? 1'b1 : 1'b0;
wire signed [31:0] s_signedOperantA = operantA;
wire signed [31:0] s_signedOperantB = operantB;
wire s_signedSmaller = s_signedOperantA < s_signedOperantB ? 1'b1 : 1'b0;

always @*
  case (compareControl)
    4'b0000 : s_flag <= s_equal;
    4'b0001 : s_flag <= ~s_equal;
    4'b0010 : s_flag <= ~(s_equal | s_unsignedSmaller);
    4'b1010 : s_flag <= ~(s_equal | s_signedSmaller);
    4'b0011 : s_flag <= ~s_unsignedSmaller;
    4'b1011 : s_flag <= ~s_signedSmaller;
    4'b0100 : s_flag <= s_unsignedSmaller;
    4'b1100 : s_flag <= s_signedSmaller;
    4'b0101 : s_flag <= s_equal | s_unsignedSmaller;
    4'b1101 : s_flag <= s_equal | s_signedSmaller;
    default : s_flag <= s_flagReg;
  endcase

always @(posedge clock)
  if (reset == 1'b1)
    begin
      s_flagReg     <= 1'b0;
      s_overflowReg <= 1'b0;
      s_carryOutReg <= 1'b0;
    end
  else if (stall == 1'b0)
    begin
      s_flagReg     <= s_flag;
      s_overflowReg <= (operantA[31] & operantB[31] & ~s_extendedSum[31]) |
                       (~operantA[31] & ~operantB[31] & s_extendedSum[31]);
      s_carryOutReg <= s_extendedSum[32];
    end

endmodule
