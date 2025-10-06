module shifter ( input wire [1:0]  control,
                 input wire [31:0] operantA,
                                   operantB,
                 output reg [31:0] result);

  localparam [1:0] SHIFTER_SLL = 2'b00;
  localparam [1:0] SHIFTER_SRL = 2'b01;
  localparam [1:0] SHIFTER_SRA = 2'b10;
  localparam [1:0] SHIFTER_ROR = 2'b11;

  wire [4:0] s_shiftAmount = (control == SHIFTER_SLL) ? (~operantB[4:0])+5'd1 : operantB[4:0];
  wire [31:0] s_shiftStage0 = (operantB[0] == 1'b0) ? operantA : {operantA[0],operantA[31:1]};
  wire [31:0] s_shiftStage1 = (s_shiftAmount[1] == 1'b0) ? s_shiftStage0 : {s_shiftStage0[1:0],s_shiftStage0[31:2]};
  wire [31:0] s_shiftStage2 = (s_shiftAmount[2] == 1'b0) ? s_shiftStage1 : {s_shiftStage1[3:0],s_shiftStage1[31:4]};
  wire [31:0] s_shiftStage3 = (s_shiftAmount[3] == 1'b0) ? s_shiftStage2 : {s_shiftStage2[7:0],s_shiftStage2[31:8]};
  wire [31:0] s_shiftStage4 = (s_shiftAmount[4] == 1'b0) ? s_shiftStage3 : {s_shiftStage3[15:0],s_shiftStage3[31:16]};
  wire [31:0] s_shiftMask0 = (operantB[0] == 1'b0) ? {32{1'b1}} : {1'b0,{31{1'b1}}};
  wire [31:0] s_shiftMask1 = (operantB[1] == 1'b0) ? s_shiftMask0 : {{2{1'b0}},s_shiftMask0[31:2]};
  wire [31:0] s_shiftMask2 = (operantB[2] == 1'b0) ? s_shiftMask1 : {{4{1'b0}},s_shiftMask1[31:4]};
  wire [31:0] s_shiftMask3 = (operantB[3] == 1'b0) ? s_shiftMask2 : {{8{1'b0}},s_shiftMask2[31:8]};
  wire [31:0] s_shiftMask4 = (operantB[4] == 1'b0) ? s_shiftMask3 : {{16{1'b0}},s_shiftMask3[31:16]};
  
  genvar n;
  
  generate
    for (n = 0; n < 32 ; n = n + 1)
      begin : gen
        always @*
          case (control)
            SHIFTER_SLL : result[n] = s_shiftStage4[n] & s_shiftMask4[31-n];
            SHIFTER_SRL : result[n] = s_shiftStage4[n] & s_shiftMask4[n];
            SHIFTER_SRA : result[n] = (s_shiftStage4[n] & s_shiftMask4[n]) | (operantA[31] & ~s_shiftMask4[n]);
            default     : result[n] = s_shiftStage4[n];
          endcase
      end
  endgenerate
endmodule
