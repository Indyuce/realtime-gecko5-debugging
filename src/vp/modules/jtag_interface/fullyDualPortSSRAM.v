module fullyDualPortSSRAM ( input wire [8:0]  addressA,
                                         addressB,
                       input wire        clockA,
                                         clockB,
                                         writeEnableA, writeEnableB,
                       input wire [31:0] dataInA, dataInB,
                       output reg [31:0] dataOutA, dataOutB);

  reg [31:0] memoryContent [511:0]; // 2kbit memory
  
  always @(posedge clockA)
  begin
    dataOutA <= memoryContent[addressA];
    if (writeEnableA == 1'b1) memoryContent[addressA] <= dataInA;
  end
  always @(posedge clockB)
    begin
      dataOutB <= memoryContent[addressB];
      if (writeEnableB == 1'b1) memoryContent[addressB] <= dataInB;
    end
endmodule
