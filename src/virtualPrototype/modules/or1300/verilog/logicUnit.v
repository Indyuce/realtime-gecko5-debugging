module logicUnit ( input wire [2:0]   control,
                   input wire [31:0]  operantA,
                                      operantB,
                   output wire [31:0] result );

  reg [31:0] s_logicResult, s_extendResult;
  
  assign result = (control[2] == 1'b0) ? s_logicResult : s_extendResult;

  always @*
    case (control[1:0])
      2'b01   : s_logicResult <= operantA & operantB;
      2'b10   : s_logicResult <= operantA | operantB;
      2'b11   : s_logicResult <= operantA ^ operantB;
      default : s_logicResult <= operantA;
    endcase
  
  always @*
    case (control[1:0])
      2'b00   : s_extendResult <= {{16{operantA[15]}},operantA[15:0]};
      2'b01   : s_extendResult <= {{24{operantA[7]}},operantA[7:0]};
      2'b10   : s_extendResult <= {{16{1'b0}},operantA[15:0]};
      default : s_extendResult <= {{24{1'b0}},operantA[7:0]};
    endcase
endmodule
