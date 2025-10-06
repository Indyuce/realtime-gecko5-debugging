module leds #( parameter [31:0] initialBaseAddress = 32'h50000000)
             ( input wire          clock,
                                   reset,
                       
               // Here the bus interface is defined
               input wire          beginTransactionIn,
                                   endTransactionIn,
                                   readNotWriteIn,
                                   dataValidIn,
                                   busyIn,
                                   busErrorIn,
               input wire [31:0]   addressDataIn,
               input wire [3:0]    byteEnablesIn,
               input wire [7:0]    burstSizeIn,
               output wire         endTransactionOut,
                                   dataValidOut,
               output reg          busErrorOut,
               output wire [31:0]  addressDataOut,
`ifdef GECKO5Education
               input wire          oneKhzTick,
               output wire [3:0]   rgbRow,
               output reg [9:0]    nRed,
                                   nGreen,
                                   nBlue
`else
               output wire [107:0] leds
`endif
             );

  /*
   *
   * Here the bus input interface is defined
   *
   */
  reg s_transactionActiveReg, s_readNotWriteReg, s_beginTransactionReg, s_dataInValidReg, s_endTransactionReg;
  reg [3:0]  s_byteEnablesReg;
  reg [7:0]  s_burstSizeReg;
  reg [8:0] s_toBeTransmittedReg;
  reg [31:0] s_busAddressReg, s_baseAddressReg, s_dataInReg;
  reg [8:0]  s_indexReg;
  wire s_isMyTransaction = (s_transactionActiveReg == 1'b1 && s_busAddressReg[31:11] == s_baseAddressReg[31:11]) ? 1'b1 : 1'b0;
  wire s_busErrorOut = (s_isMyTransaction == 1'b1 && s_byteEnablesReg != 4'hF) ? 1'b1 : 1'b0;
  wire s_weBaseAddress = (s_isMyTransaction == 1'b1 && s_readNotWriteReg == 1'b0 && s_indexReg == 9'b111111111 && s_dataInValidReg == 1'b1) ? 1'b1 : 1'b0;
  
  always @(posedge clock)
    begin
      s_transactionActiveReg <= (reset == 1'b1 || s_endTransactionReg == 1'b1) ? 1'b0 : s_transactionActiveReg | beginTransactionIn;
      s_busAddressReg        <= (beginTransactionIn == 1'b1) ? addressDataIn : s_busAddressReg;
      s_baseAddressReg       <= (reset == 1'b1) ? initialBaseAddress : (s_weBaseAddress == 1'b1) ? s_dataInReg : s_baseAddressReg;
      s_readNotWriteReg      <= (beginTransactionIn == 1'b1) ? readNotWriteIn : s_readNotWriteReg;
      s_byteEnablesReg       <= (beginTransactionIn == 1'b1) ? byteEnablesIn : s_byteEnablesReg;
      s_burstSizeReg         <= (beginTransactionIn == 1'b1) ? burstSizeIn : s_burstSizeReg;
      s_beginTransactionReg  <= beginTransactionIn;
      s_dataInReg            <= (dataValidIn == 1'b1) ? addressDataIn : s_dataInReg;
      s_dataInValidReg       <= dataValidIn;
      s_endTransactionReg    <= endTransactionIn;
      busErrorOut            <= (reset == 1'b1 || endTransactionIn == 1'b1 || s_endTransactionReg == 1'b1) ? 1'b0 : s_busErrorOut;
    end
  
  /*
   *
   * Here the led functionality is defined
   *
   */
  reg [2:0] s_ledsReg [127:0];
  reg [3:0] s_rowSelectReg;
  reg s_busDataOutValidReg;
  wire [2:0] s_ledsNext [127:0];
  wire [127:0] s_weRed, s_weGreen, s_weBlue;
  wire [11:0] s_selectedLine[11:0];
  wire s_pixelBased = s_indexReg[8];
  wire [7:0] s_pixelIndex = s_indexReg[7:0];
  wire s_we = s_dataInValidReg & ~s_readNotWriteReg & s_isMyTransaction;
  wire s_re = ~s_toBeTransmittedReg[8] & ~busyIn;
  
  genvar n;
  
  always @(posedge clock) s_indexReg <= (s_beginTransactionReg == 1'b1 && s_isMyTransaction == 1'b1) ? s_busAddressReg[10:2] : (s_we == 1'b1 || s_re == 1'b1) ? s_indexReg + 9'd1 : s_indexReg;
  
  generate
    for ( n = 0 ; n < 128 ; n = n + 1 )
      begin : genleds
        assign s_selectedLine[n/12][n%12] = (s_pixelIndex[1:0] == 2'd0) ? s_ledsReg[n][0] :
                                            (s_pixelIndex[1:0] == 2'd1) ? s_ledsReg[n][1] :
                                            (s_pixelIndex[1:0] == 2'd2) ? s_ledsReg[n][2] : s_ledsReg[n][0] & s_ledsReg[n][1] & s_ledsReg[n][2];
        assign s_ledsNext[n][0] = (s_pixelBased == 1'b1) ? s_dataInReg[0] : 
                                  (s_pixelIndex[7:6] == 2'd0) ? s_dataInReg[11-(n % 12)] :
                                  (s_pixelIndex[7:6] == 2'd1) ? s_dataInReg[11-(n % 12)] | s_ledsReg[n][0] :
                                  (s_pixelIndex[7:6] == 2'd1) ? ~s_dataInReg[11-(n % 12)] & s_ledsReg[n][0] : s_dataInReg[11-(n % 12)] ^ s_ledsReg[n][0];
        assign s_ledsNext[n][1] = (s_pixelBased == 1'b1) ? s_dataInReg[1] : 
                                  (s_pixelIndex[7:6] == 2'd0) ? s_dataInReg[11-(n % 12)] :
                                  (s_pixelIndex[7:6] == 2'd1) ? s_dataInReg[11-(n % 12)] | s_ledsReg[n][1] :
                                  (s_pixelIndex[7:6] == 2'd1) ? ~s_dataInReg[11-(n % 12)] & s_ledsReg[n][1] : s_dataInReg[11-(n % 12)] ^ s_ledsReg[n][1];
        assign s_ledsNext[n][2] = (s_pixelBased == 1'b1) ? s_dataInReg[2] : 
                                  (s_pixelIndex[7:6] == 2'd0) ? s_dataInReg[11-(n % 12)] :
                                  (s_pixelIndex[7:6] == 2'd1) ? s_dataInReg[11-(n % 12)] | s_ledsReg[n][2] :
                                  (s_pixelIndex[7:6] == 2'd1) ? ~s_dataInReg[11-(n % 12)] & s_ledsReg[n][2] : s_dataInReg[11-(n % 12)] ^ s_ledsReg[n][2];
        assign s_weRed[n]   = ((s_pixelBased == 1'b1 && s_pixelIndex[6:0] == n) ||
                               (s_pixelBased == 1'b0 && s_pixelIndex[5:2] == (n/12) && (s_pixelIndex[1:0] == 2'd2 ||s_pixelIndex[1:0] == 2'd3))) ? s_we : 1'b0;
        assign s_weGreen[n] = ((s_pixelBased == 1'b1 && s_pixelIndex[6:0] == n) ||
                               (s_pixelBased == 1'b0 && s_pixelIndex[5:2] == (n/12) && (s_pixelIndex[1:0] == 2'd1 ||s_pixelIndex[1:0] == 2'd3))) ? s_we : 1'b0;
        assign s_weBlue[n]  = ((s_pixelBased == 1'b1 && s_pixelIndex[6:0] == n) ||
                               (s_pixelBased == 1'b0 && s_pixelIndex[5:2] == (n/12) && (s_pixelIndex[1:0] == 2'd0 ||s_pixelIndex[1:0] == 2'd3))) ? s_we : 1'b0;
        always @(posedge clock) 
          begin
            s_ledsReg[n][0] <= (reset == 1'b1) ? 1'b0 : (s_weBlue[n] == 1'b1) ? s_ledsNext[n][0] : s_ledsReg[n][0];
            s_ledsReg[n][1] <= (reset == 1'b1) ? 1'b0 : (s_weGreen[n] == 1'b1) ? s_ledsNext[n][1] : s_ledsReg[n][1];
            s_ledsReg[n][2] <= (reset == 1'b1) ? 1'b0 : (s_weRed[n] == 1'b1) ? s_ledsNext[n][2] : s_ledsReg[n][2];
          end
      end
`ifdef GECKO5Education
    wire [7:0] s_lineOffset [9:0];
   
    for ( n = 0 ; n < 10 ; n = n + 1 )
      begin : gencolors
         always @(posedge clock)
           begin
             nRed[n]   <= ~s_ledsReg[n*12+s_rowSelectReg][2];
             nGreen[n] <= ~s_ledsReg[n*12+s_rowSelectReg][1];
             nBlue[n]  <= ~s_ledsReg[n*12+s_rowSelectReg][0];
           end
      end
      
    always @(posedge clock) s_rowSelectReg <= (reset == 1'b1 || (s_rowSelectReg == 4'd0 && oneKhzTick == 1'b1)) ? 4'd11 : (oneKhzTick == 1'b1) ? s_rowSelectReg - 4'd1 : s_rowSelectReg;
    
    assign rgbRow = s_rowSelectReg;
`else
    for ( n = 0 ; n < 108 ; n = n + 1 )
      begin : assignLeds
        assign leds[n] = s_ledsReg[n][2] | s_ledsReg[n][1] | s_ledsReg[n][0];
      end
`endif
  endgenerate
  
  /*
   *
   * Here the bus output signals are defined
   *
   */
  reg [31:0] s_busDataOutReg;
  reg s_endTransactionOutReg;
  wire [31:0] s_busDataOutNext = (s_indexReg == 9'b111111111) ? s_baseAddressReg :
                                 (s_pixelBased == 1'b1) ? {29'd0,s_ledsReg[s_pixelIndex[6:0]]} :
                                 (s_pixelIndex[5:2] < 4'd10) ? {20'd0,s_selectedLine[s_pixelIndex[5:2]]} : 32'd0;
  
  assign endTransactionOut = s_endTransactionOutReg;
  assign dataValidOut = s_busDataOutValidReg;
  assign addressDataOut = s_busDataOutReg;

  always @(posedge clock)
    begin
      s_toBeTransmittedReg   <= (reset == 1'b1 || busErrorIn == 1'b1) ? 9'b100000000 :
                                (s_beginTransactionReg == 1'b1 && s_isMyTransaction == 1'b1 && s_readNotWriteReg == 1'b1) ? {1'b0,s_burstSizeReg} :
                                (s_re == 1'b1) ? s_toBeTransmittedReg - 9'd1 : s_toBeTransmittedReg;
      s_busDataOutReg        <= (s_toBeTransmittedReg[8] == 1'b0) ? s_busDataOutNext : (busyIn == 1'b1) ? s_busDataOutReg : 32'h0;
      s_busDataOutValidReg   <= (s_toBeTransmittedReg[8] == 1'b0) ? 1'b1 : (busyIn == 1'b1) ? s_busDataOutValidReg : 1'b0;
      s_endTransactionOutReg <= (s_busDataOutValidReg == 1'b1 && busyIn == 1'b0 && s_toBeTransmittedReg[8] == 1'b1) ? 1'b1 : 1'b0;
    end
endmodule
