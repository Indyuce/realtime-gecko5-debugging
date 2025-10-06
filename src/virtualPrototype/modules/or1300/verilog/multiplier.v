module multiplier ( input wire         clock,
                                       reset,
                                       doMultiply,
                    input wire [2:0]   control,
                    input wire [31:0]  operantA,
                                       operantB,
                    input wire         weMacLo,
                                       weMacHi,
                    input wire [31:0]  weMacData,
                    output wire        done,
                    output wire [31:0] result,
                                       macLoData,
                                       macHiData );
  localparam [2:0] MAC_READ_CLEAR = 3'b100;
  localparam [2:0] MULTIPLY_ADD = 3'b010;
  localparam [2:0] MULTIPLY_SUB = 3'b011;

  reg [31:0] s_macDataLoReg, s_macDataHiReg;
  wire s_clearMac;
  wire [31:0] s_multResult = operantA * operantB;
  assign done = ((doMultiply == 1'b1 && control != MAC_READ_CLEAR) || (s_clearMac == 1'b1)) ? 1'b1 : 1'b0;
  assign result = (control == MAC_READ_CLEAR) ? s_macDataLoReg : s_multResult;
  assign macLoData = s_macDataLoReg;
  assign macHiData = s_macDataHiReg;

  /*
   *
   * Here we define the pipeline registers required for the mac operations (3 cycle)
   *
   */
  reg [1:0] s_macPipeReg;
  always @(posedge clock)
    if (reset == 1'b1 || weMacLo == 1'b1) s_macPipeReg <= 0;
    else if (control[1] == 1'b1 && doMultiply == 1'b1) s_macPipeReg <= {s_macPipeReg[0], 1'b1};
    else s_macPipeReg <= {s_macPipeReg[0], 1'b0};

  reg [2:0] s_controlPipeReg;
  reg [31:0] s_multResultPipeReg;
  always @(posedge clock)
    if (doMultiply == 1'b1)
      begin
        s_controlPipeReg    <= control;
        s_multResultPipeReg <= s_multResult;
      end

  /*
   *
   * Here we do the actual mac
   *
   */
  assign s_clearMac = (s_macPipeReg[0] == 1'b1 && s_controlPipeReg == MAC_READ_CLEAR) ||
                      (s_macPipeReg[0] == 1'b0 && control == MAC_READ_CLEAR && doMultiply == 1'b1) ? 1'b1 : 1'b0;
  wire [32:0] s_extendedMacLo = {1'b0,s_macDataLoReg};
  wire [31:0] s_negativeMultResult = (~s_multResultPipeReg) + 1;
  wire [32:0] s_extendedMultResult = (s_controlPipeReg[0] == 1'b1) ? {1'b0,s_negativeMultResult} : {1'b0,s_multResultPipeReg};
  wire [32:0] s_newMacLoData = s_extendedMacLo + s_extendedMultResult;
  
  always @(posedge clock)
    if (reset == 1'b1 || s_clearMac == 1'b1) s_macDataLoReg <= 0;
    else if (weMacLo == 1'b1) s_macDataLoReg <= weMacData;
    else if (s_macPipeReg[0] == 1'b1 && 
             (s_controlPipeReg == MULTIPLY_ADD || s_controlPipeReg == MULTIPLY_SUB)) s_macDataLoReg <= s_newMacLoData[31:0];

  wire [2:0] s_situation = {s_controlPipeReg[0],s_newMacLoData[32],s_multResultPipeReg[31]};
  reg[1:0] s_macHiCommandReg;
  
  always @(posedge clock)
    if (s_macPipeReg[0] == 1'b1)
      case (s_situation)
        3'b010  : s_macHiCommandReg <= 2'b01;
        3'b111  : s_macHiCommandReg <= 2'b01;
        3'b001  : s_macHiCommandReg <= 2'b10;
        3'b100  : s_macHiCommandReg <= 2'b10;
        default : s_macHiCommandReg <= 2'b00;
      endcase
  
  always @(posedge clock)
    if (reset == 1'b1) s_macDataHiReg <= 0;
    else if (weMacHi == 1'b1) s_macDataHiReg <= weMacData;
    else if (s_macPipeReg[1] == 1'b1)
      begin
        if (s_macHiCommandReg[0] == 1'b1) s_macDataHiReg <= s_macDataHiReg + 1;
        else if (s_macHiCommandReg[1] == 1'b1) s_macDataHiReg <= s_macDataHiReg - 1;
      end
endmodule
